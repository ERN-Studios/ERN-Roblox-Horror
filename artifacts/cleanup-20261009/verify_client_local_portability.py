"""Reproduce prepared gates using only portable evidence inputs, never .git."""
from pathlib import Path
import hashlib
import importlib.util
import json
import os
import subprocess
import sys
import tempfile

sys.dont_write_bytecode = True
ROOT = Path(__file__).resolve().parents[2]
OUT = ROOT / "artifacts/cleanup-20261009"


def sha(path):
    return hashlib.sha256(path.read_bytes()).hexdigest()


def main():
    manifest = json.loads((OUT / "remaining-clients-proposals.json").read_text(encoding="utf8"))
    index = json.loads((OUT / "client-local-proofs/index.json").read_text(encoding="utf8"))
    sources = {row["file"]: sha(ROOT / row["file"]) for row in manifest["installUnits"]}
    spec = importlib.util.spec_from_file_location("client_local_contracts", OUT / "run_client_local_contracts.py")
    runner = importlib.util.module_from_spec(spec)
    spec.loader.exec_module(runner)
    runner.PORTABLE_ONLY = True
    for group in ["proposals", "installUnits"]:
        for row in manifest[group]:
            for phase in ["before", "candidate"]:
                assert runner.proof_path(row, phase) == ROOT / row[f"{phase}PortablePath"]
    # Verify a legacy/nonexistent primary path falls back to portable evidence.
    example = dict(manifest["installUnits"][0])
    example["beforePath"] = ".git/definitely-not-a-proof.lua"
    runner.PORTABLE_ONLY = False
    assert runner.proof_path(example, "before") == ROOT / example["beforePortablePath"]
    # Changed present input must fail closed; never silently choose another copy.
    with tempfile.TemporaryDirectory(prefix="client-proof-negative-") as temporary:
        corrupt = Path(temporary) / "corrupt.lua"
        corrupt.write_bytes(b"return 'wrong input'\n")
        example["beforePath"] = str(corrupt)
        try:
            runner.proof_path(example, "before")
        except AssertionError as error:
            assert "immutable saved proof input changed" in str(error)
        else:
            raise AssertionError("Changed immutable input was accepted")
    commands = [["--authoring", "--portable-only"]]
    for suite in ["test_round_hud", "test_round_hud_shared", "test_hud_b6_b7", "test_ui_regression_shared", "test_zyntra_store_compact", "test_first_entry_guide"]:
        for phase in ["before", "candidate"]:
            commands.append(["--existing", suite, "--phase", phase, "--portable-only"])
    results = []
    for command in commands:
        result = subprocess.run([sys.executable, str(OUT / "run_client_local_contracts.py"), *command], capture_output=True, text=True, timeout=180)
        results.append({"args": command, "exitCode": result.returncode, "stdout": result.stdout, "stderr": result.stderr})
        if result.returncode:
            break
    for file, expected in sources.items():
        assert sha(ROOT / file) == expected, "Concurrent/canonical source changed during portable gate: " + file
    for file, expected in index["preparedReceiptsUnchanged"].items():
        assert sha(OUT / file) == expected, "Prepared raw receipt changed: " + file
    for copy in index["copies"]:
        assert sha(ROOT / copy["portablePath"]) == copy["byteSha256"]
    receipt = {"productionWrites": False, "studioCalls": False, "checkpointReadsRequired": False,
               "portableProofBytesUnchanged": True, "preparedReceiptsUnchanged": True,
               "canonicalSourceBytesUnchanged": True, "missingPrimaryFallbackPass": True,
               "corruptPrimaryRejected": True, "gates": results}
    (OUT / "client-local-portability-gates.json").write_text(json.dumps(receipt, indent=2) + "\n", encoding="utf8")
    print(json.dumps({"pass": all(row["exitCode"] == 0 for row in results), "gates": [{"args": row["args"], "exitCode": row["exitCode"], "stdout": row["stdout"]} for row in results]}, indent=2))
    raise SystemExit(1 if any(row["exitCode"] for row in results) else 0)


if __name__ == "__main__":
    main()
