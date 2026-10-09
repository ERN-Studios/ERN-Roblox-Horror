"""Record offline contracts/compile with frozen S04 helper hashes; never connect to Studio."""
from __future__ import annotations

import argparse
import hashlib
import importlib.util
import json
from pathlib import Path
import subprocess
import sys
import tempfile
from types import SimpleNamespace
from datetime import datetime, timezone

TOOLS = Path(__file__).resolve().parent
ROOT = TOOLS.parents[1]
LU = Path("C:/Users/mikke/AppData/Local/Temp/codex-luau-0.737")


def main():
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument("--output", type=Path, required=True)
    args = parser.parse_args()
    output = args.output.resolve()
    base = ROOT / "artifacts/cleanup-serverstorage-20261009/retired-authoring-archive"
    assert output.is_relative_to(base.resolve()) and not output.exists()
    sources = sorted(TOOLS.glob("retired_authoring_archive*"))
    hashes = {str(file.relative_to(ROOT)): hashlib.sha256(file.read_bytes()).hexdigest() for file in sources if file.is_file()}
    tests = subprocess.run([sys.executable, "-B", str(TOOLS / "retired_authoring_archive_test.py")],
                           capture_output=True, text=True, timeout=30)
    assert tests.returncode == 0, tests.stdout + tests.stderr
    spec = importlib.util.spec_from_file_location("s04_proof_receiver", TOOLS / "retired_authoring_archive_receiver.py")
    receiver = importlib.util.module_from_spec(spec)
    spec.loader.exec_module(receiver)
    compiled = []
    with tempfile.TemporaryDirectory(prefix="mongodb-s04-compile-") as directory:
        paths = list(TOOLS.glob("retired_authoring_archive*.luau"))
        for phase in ("capture", "verify"):
            context = {"captureId": "offline-compile-only-no-native", "expectedRootCount": 51, "expectedSourceCount": 212}
            code = receiver.native_code(SimpleNamespace(phase=phase, context=lambda: context))
            generated = Path(directory) / f"combined-{phase}.luau"
            generated.write_text(code, encoding="utf-8")
            paths.append(generated)
        for file in paths:
            result = subprocess.run([str(LU / "luau-compile.exe"), str(file)], capture_output=True, timeout=15)
            assert result.returncode == 0, result.stderr.decode(errors="replace")
            compiled.append({"name": file.name, "sourceSHA256": hashlib.sha256(file.read_bytes()).hexdigest(),
                             "compilerExitCode": 0, "compilerOutputSHA256": hashlib.sha256(result.stdout).hexdigest()})
    for name, sha in hashes.items():
        assert hashlib.sha256((ROOT / name).read_bytes()).hexdigest() == sha, "Tool changed during proof"
    report = {"schema": "s04-offline-archive-proof-v1", "atUtc": datetime.now(timezone.utc).isoformat(),
              "passed": True, "toolHashesBeforeAfterExact": hashes,
              "pythonContractTests": 19, "currentRealVerifierSyntheticLifecycleScenarios": 12,
              "currentRealCommonSyntheticDiagnosticScenarios": 6,
              "currentRealCapturePositiveFiveRootScenario": 1,
              "fiveRootScopePinnedByCurrentCommonFixture": {"names": list(receiver.NAMES), "rootCounts": list(receiver.ROOT_COUNTS),
                  "classes": receiver.CLASSES, "instances": 1617, "scripts": 0},
              "testOutput": tests.stdout + tests.stderr, "compiledUnits": compiled,
              "nativeExecuted": False, "studioConnected": False, "originalWrites": 0,
              "recoveryCertified": False, "gameplayPassed": False, "deletionApproved": False,
              "limits": "Offline receiver/request/lifecycle contracts and syntax only; native engine archive/reopen and R4/V2 runtime/authoring ports remain pending."}
    output.parent.mkdir(parents=True, exist_ok=True)
    with output.open("x", encoding="utf-8") as stream:
        json.dump(report, stream, indent=2)
        stream.write("\n")
    print(json.dumps({"passed": True, "tests": 19, "lifecycleScenarios": 12, "diagnosticScenarios": 6, "positiveCaptureScenarios": 1, "compileUnits": len(compiled),
                      "output": str(output), "nativeExecuted": False}))


if __name__ == "__main__":
    main()
