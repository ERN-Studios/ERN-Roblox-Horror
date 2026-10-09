"""Actual-source, offline Round Entry batching contract checks.

This models callbacks and yielding engine calls; it is not a Roblox gameplay,
multiplayer, streaming, renderer, or actual-asset performance result. Importing
this file never contacts Studio. The default source is the canonical mirror;
--candidate selects the scoped candidate before its verified export.
"""
from pathlib import Path
import argparse
import hashlib
import json
import os
import shutil
import subprocess
import tempfile

ROOT = Path(__file__).resolve().parents[2]
HERE = Path(__file__).parent
DEFAULT = ROOT / "StarterPlayer/StarterPlayerScripts/Round Entry Client.LocalScript.lua"
CANDIDATE = HERE / "candidates/RoundEntryBatch.candidate.luau"


def mutations(source):
    changes = [
        ("required callback omitted", "if not reported[key] or failed[key] then loaded = false end", "if failed[key] then loaded = false end"),
        ("failed callback ignored", "if not reported[key] or failed[key] then loaded = false end", "if not reported[key] then loaded = false end"),
        ("unknown dependency failure ignored", "unexpectedFailure = true", "unexpectedFailure = false"),
        ("HTTP asset aliases lost", "return id and \"assetid:\" .. id or value", "return value"),
        ("temporary carrier leaked", "if not pcall(function() instance:Destroy() end) then ok = false end", "if false then ok = false end"),
        ("engine exception accepted", "local loaded = ok and not unexpectedFailure", "local loaded = not unexpectedFailure"),
        ("engine owner released early", "\t\t\t\tloadCarriers(pending)", "\t\t\t\tentryPreloadBusy = false\n\t\t\t\tloadCarriers(pending)"),
        ("unbounded retries", "(carrier.Attempts or 0) < 2", "(carrier.Attempts or 0) < 200"),
        ("stale request readiness accepted", "\t\t\tif current(request) then\n\t\t\t\trequest.AssetsReady", "\t\t\tif true then\n\t\t\t\trequest.AssetsReady"),
    ]
    for name, before, after in changes:
        assert source.count(before) == 1, f"Mutation anchor is not exact: {name}"
        yield name, source.replace(before, after, 1)


def run(source, executable):
    harness = (HERE / "round_entry_batch_harness.luau").read_text(encoding="utf-8")
    assert harness.count("-- __ACTUAL_ROUND_ENTRY_SOURCE__") == 1
    script = harness.replace("-- __ACTUAL_ROUND_ENTRY_SOURCE__", source)
    with tempfile.TemporaryDirectory(prefix="round-entry-batch-") as directory:
        path = Path(directory) / "test.luau"
        path.write_text(script, encoding="utf-8")
        return subprocess.run([str(executable), str(path)], capture_output=True, text=True, timeout=45)


def main():
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument("--candidate", action="store_true")
    parser.add_argument("--source", type=Path)
    parser.add_argument("--luau", type=Path)
    parser.add_argument("--mutations", action="store_true")
    args = parser.parse_args()
    source_path = args.source or (CANDIDATE if args.candidate else DEFAULT)
    executable = args.luau or os.environ.get("LUAU_BIN") or shutil.which("luau")
    if not executable:
        parser.error("Pass --luau, set LUAU_BIN, or add the Luau CLI to PATH")
    source = source_path.read_text(encoding="utf-8")
    result = run(source, executable)
    mutation_results = []
    if args.mutations and result.returncode == 0:
        for name, mutant in mutations(source):
            mutant_result = run(mutant, executable)
            mutation_results.append({"mutation": name, "rejected": mutant_result.returncode != 0})
            if mutant_result.returncode == 0:
                result = subprocess.CompletedProcess([], 1, result.stdout, "Mutation survived: " + name)
    receipt = {
        "source": str(source_path.relative_to(ROOT)) if source_path.is_relative_to(ROOT) else str(source_path),
        "sourceSHA256": hashlib.sha256(source.encode()).hexdigest(),
        "scope": "Offline actual-source callback, retry, cancellation, cleanup, and readiness contract",
        "exitCode": result.returncode,
        "stdout": result.stdout.strip(),
        "stderr": result.stderr.strip(),
        "nativeGameplayVerified": False,
        "actualAssetPerformanceVerified": False,
        "mutations": mutation_results,
    }
    print(json.dumps(receipt, indent=2))
    return result.returncode


if __name__ == "__main__":
    raise SystemExit(main())
