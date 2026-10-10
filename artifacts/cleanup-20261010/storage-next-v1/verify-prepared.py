"""Offline checks of the actual prepared request; no Studio/network calls."""
from pathlib import Path
import hashlib
import importlib.util
import json
import re
import subprocess
import tempfile

ROOT = Path(__file__).resolve().parents[3]
OUT = Path(__file__).resolve().parent
LU = Path("C:/Users/mikke/AppData/Local/Temp/codex-luau-0.737")
helper = ROOT / "tools/cleanup_20261009/test_external_storage_reopen_ownership.py"
fixture = ROOT / "tools/cleanup_20261009/external_storage_reopen_ownership_fixture.luau"
frozen = ROOT / "artifacts/cleanup-serverstorage-20261009/external-storage-reopen-v1/reopen-source.luau"
source_path = OUT / "restoration-supplement-probe.luau"

def sha(raw):
    return hashlib.sha256(raw).hexdigest()

inputs = {p: p.read_bytes() for p in (helper, fixture, frozen, source_path, OUT / "restore-supplement.json")}
actual = inputs[source_path].decode("utf-8")
module_spec = importlib.util.spec_from_file_location("s06_offline_current_helper", helper)
module = importlib.util.module_from_spec(module_spec)
module_spec.loader.exec_module(module)
compiled = []
with tempfile.TemporaryDirectory(prefix="mongotv-exact-supplement-offline-") as name:
    directory = Path(name)
    new = directory / "new_reopen_contract.luau"
    old = directory / "before_reopen_contract.luau"
    driver = directory / "ownership.luau"
    new.write_text(module.module(actual, True), encoding="utf-8")
    old.write_text(module.module(inputs[frozen].decode("utf-8"), False), encoding="utf-8")
    driver.write_bytes(inputs[fixture])
    for path in (source_path, new, old, driver):
        for opt in ("-O0", "-O1"):
            result = subprocess.run([str(LU / "luau-compile.exe"), opt, str(path)], capture_output=True, timeout=20)
            assert result.returncode == 0, result.stderr.decode(errors="replace")
            compiled.append({"name": path.name, "opt": opt, "sourceSHA256": sha(path.read_bytes()), "exitCode": result.returncode})
    result = subprocess.run([str(LU / "luau.exe"), driver.name], cwd=directory, capture_output=True, text=True, timeout=30)
    assert result.returncode == 0, result.stdout + result.stderr
    match = re.search(r"S06 actual-source ownership fixture passed: cases=(\d+) checks=(\d+)", result.stdout)
    assert match and int(match[1]) == 16
assert all(path.read_bytes() == raw for path, raw in inputs.items()), "Source changed during offline check"
assert actual.count("copy.CFrame=wanted") == 1
assert actual.index("report.copyAdoptionErrors=adoptCopies(copies)") < actual.index('restoreFourCFrames(snapshot,"first-reopen")')
assert actual.index("secondAdoptionErrors=adoptCopies(copies2)") < actual.index('restoreFourCFrames(secondSnapshot,"second-reopen")')
assert actual.count("copyOwnedNodes[copy] and not knownOriginals[copy]") == 1
assert "copy.CFrame==wanted and canonical({copy.CFrame:GetComponents()})==canonical(spec.components)" in actual
assert "sha(secondNative)==context.nativeSHA256" in actual
report = {"schema": "s06-exact-supplement-offline-preflight-v1", "pass": True, "nativeCalls": 0,
    "candidateExecuted": False, "normalizationApplied": False, "restorationCertified": False,
    "actualPreparedOwnershipCases": int(match[1]), "actualPreparedOwnershipAssertions": int(match[2]),
    "compiledUnits": compiled, "inputHashesBeforeAfterExact": [{"path": str(p.relative_to(ROOT)), "bytes": len(raw), "sha256": sha(raw)} for p, raw in inputs.items()],
    "supplementFaultGateStatus": "Pending: complete real helper constructor/setter/commit-then-throw and original-guard failure fixture before any native execution.",
    "scope": "Existing actual registration/adoption/cleanup code from this prepared request executed with synthetic identities in 16 scenarios, including historical two leak controls; eight O0/O1 compiles. New supplement path remains prepared/unexecuted and is not certified by these ownership contracts."}
target = OUT / "offline-preflight.json"
assert not target.exists()
with target.open("xb") as stream:
    stream.write((json.dumps(report, indent=2) + "\n").encode())
print(json.dumps({"pass": True, "ownershipCases": int(match[1]), "ownershipAssertions": int(match[2]), "compileUnits": len(compiled), "nativeCalls": 0}))
