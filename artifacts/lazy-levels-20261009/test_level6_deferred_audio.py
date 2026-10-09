"""Offline actual-source coroutine contract for deferred Level 6 effect preloads.

No imports or commands contact Studio. The exact selected source block includes
its own attribute-event hooks, and the oneShot consumer is also taken verbatim.
These synthetic engine callbacks do not measure native downloads or gameplay.
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
DEFAULT = ROOT / "StarterPlayer/StarterPlayerScripts/Level 6 Playground Client.LocalScript.lua"
CANDIDATE = HERE / "candidates/Level6DeferredAudio.candidate.luau"


def mutations(source):
    start = source.index("local refused = {}")
    end = source.index("\nlocal function oneShot(key, volume)", start)
    block = source[start:end]
    changes = [
        ("lobby eligibility ignored", 'return player:GetAttribute(IN_PREVIEW) == true and player:GetAttribute("Level5VoidRound") ~= true', 'return true'),
        ("Level 5 eligibility ignored", ' and player:GetAttribute("Level5VoidRound") ~= true', ''),
        ("preload owner ignored", 'if effectPreloadBusy or effectCursor > #effectKeys or not effectsEligible() then return end', 'if effectCursor > #effectKeys or not effectsEligible() then return end'),
        ("per-call eligibility ignored", 'while effectCursor <= #effectKeys and effectsEligible() do', 'while effectCursor <= #effectKeys do'),
        ("completed cursor reset", 'local function preloadEffects()\n', 'local function preloadEffects()\n\teffectCursor = 1\n'),
        ("real refusal ignored", 'refused[key] = true', 'local ignored = true'),
        ("drained owner retained", '\t\teffectPreloadBusy = false', '\t\teffectPreloadBusy = true'),
        ("Level 5 transition signal removed", 'player:GetAttributeChangedSignal("Level5VoidRound"):Connect(preloadEffects)', '-- removed Level 5 transition hook'),
        ("outer setup failure locks owner", '\t\teffectPreloadBusy = false\n\t\tif not ok then', '\t\tif ok then effectPreloadBusy = false end\n\t\tif not ok then'),
    ]
    for name, before, after in changes:
        assert block.count(before) == 1, f"Mutation anchor is not exact: {name}"
        mutant = block.replace(before, after, 1)
        yield name, source[:start] + mutant + source[end:]


def run(source, executable):
    start = source.index("local refused = {}")
    end = source.index("\nlocal function oneShot(key, volume)", start)
    consumer_end = source.index("\n-- footsteps and room tone:", end)
    fragment = source[start:consumer_end]
    harness = (HERE / "level6_deferred_audio_harness.luau").read_text(encoding="utf-8")
    assert harness.count("-- __ACTUAL_LEVEL6_AUDIO_SOURCE__") == 1
    script = harness.replace("-- __ACTUAL_LEVEL6_AUDIO_SOURCE__", fragment)
    with tempfile.TemporaryDirectory(prefix="level6-audio-") as directory:
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
        "scope": "Offline actual-source audio eligibility, coroutine owner, cancellation drain, and fallback contract",
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
