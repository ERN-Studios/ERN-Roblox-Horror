"""Offline current-source ownership/cleanup contracts; no Studio, network or native calls."""
from __future__ import annotations

import argparse
from datetime import datetime, timezone
import hashlib
import json
from pathlib import Path
import re
import subprocess
import tempfile

ROOT = Path(__file__).resolve().parents[2]
TOOLS = Path(__file__).resolve().parent
ARTIFACTS = ROOT / "artifacts/cleanup-serverstorage-20261009"
FROZEN = ARTIFACTS / "external-storage-reopen-v1"
LU = Path("C:/Users/mikke/AppData/Local/Temp/codex-luau-0.737")
FROZEN_SOURCE_SHA = "52a3fc3aa70acd4e60977594f96caee7a2bba583f021246aa5677a0a0f9305d7"


def sha(raw):
    return hashlib.sha256(raw).hexdigest()


def segment(text, start, end):
    assert text.count(start) == text.count(end) == 1, "Actual source boundaries changed"
    return text.split(start, 1)[1].split(end, 1)[0]


def module(source, hardened):
    functions = segment(source, "-- OWNERSHIP CONTRACT BEGIN: exercised from this exact source offline.\n",
                        "-- OWNERSHIP CONTRACT END.") if hardened else ""
    stage = " copies=SER:DeserializeInstancesAsync(raw)" + segment(
        source, " copies=SER:DeserializeInstancesAsync(raw)", " local snapshot=forestSnapshot(copies,false)")
    cleanup_marker = ("-- Independently clean every adopted root, even if an earlier returned root was foreign.\n"
                      if hardened else "-- Independently clean only returned unparented copies; no original Destroy/restore.\n")
    cleanup = segment(source, cleanup_marker, "local valid,reason=pcall(function()")
    registration = "protectOriginals(env.census)" if hardened else ""
    max_originals = re.search(r"^local MAX_ORIGINALS=(\d+)$", source, re.MULTILINE)
    bound = int(max_originals[1]) if hardened else 0
    return """return function(env)
 local game,state,rows=env.game,env.state,env.rows
 local check,typeof,owned=env.check,env.typeof,env.owned
 local task={wait=env.wait}
 local epoch=0
 local MAX_NODES=25000
 local copyOwnedNodes,copyOwnedRoots,knownOriginals={},{},{}
 local knownOriginalCount=0
 local copies={}
 local report={createdRoots=0,destroyedRoots=0}
 local SER={DeserializeInstancesAsync=function()return env.copies end}
 local raw="offline-only"
 local originals=env.originals
""" + f" local MAX_ORIGINALS={bound}\n" + functions + """
 local baselineComplete,baselineError=pcall(function()
 """ + registration + """
 end)
 local ok,why=baselineComplete,baselineError
 if baselineComplete then
  ok,why=xpcall(function()
""" + stage + """
  end,debug.traceback)
 end
 env.beforeCleanup()
""" + cleanup + """
 local protected=knownOriginals[game]==true
 for _,s in env.census do protected=protected and knownOriginals[s]==true end
 for root in state.rootRefs do
  protected=protected and knownOriginals[root]==true
  for _,s in root:GetDescendants() do protected=protected and knownOriginals[s]==true end
 end
 for script in state.scriptRefs do
  protected=protected and knownOriginals[script]==true
  for _,s in script:GetDescendants() do protected=protected and knownOriginals[s]==true end
 end
 report.pass=ok report.error=tostring(why) report.baselineComplete=baselineComplete
 report.protectedGameAndLedger=protected
 return report
end
"""


def main():
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument("--output", type=Path, required=True)
    args = parser.parse_args()
    output = args.output.resolve()
    assert output.is_relative_to((ARTIFACTS / "S06-reopen-ownership").resolve()) and not output.exists()
    frozen_hashes = {p.name: sha(p.read_bytes()) for p in FROZEN.iterdir() if p.is_file()}
    assert frozen_hashes["reopen-source.luau"] == FROZEN_SOURCE_SHA
    helper = TOOLS / "external_storage_archive_reopen.luau"
    fixture = TOOLS / "external_storage_reopen_ownership_fixture.luau"
    sources = [helper, fixture, Path(__file__)]
    hashes = {str(p.relative_to(ROOT)): sha(p.read_bytes()) for p in sources}
    actual = helper.read_text(encoding="utf8")
    # Positive actual call-site order: protection precedes native DS, complete
    # adoption precedes aggregate rejection and expected-count assertions.
    assert actual.count("\n protectOriginals(census)") == 1
    assert actual.index("\n protectOriginals(census)") < actual.index(" copies=SER:DeserializeInstancesAsync(raw)")
    assert actual.index(" report.copyAdoptionErrors=adoptCopies(copies)") < actual.index(" check(#report.copyAdoptionErrors==0") < actual.index(" check(#copies==23")
    assert "copyOwnedNodes[s] and not knownOriginals[s]" in actual
    assert "for _,f in copyOwnedRoots do" in actual and "f:Destroy()" in actual
    compiled = []
    with tempfile.TemporaryDirectory(prefix="mongotv-s06-ownership-") as name:
        directory = Path(name)
        (directory / "new_reopen_contract.luau").write_text(module(actual, True), encoding="utf8")
        frozen = (FROZEN / "reopen-source.luau").read_text(encoding="utf8")
        (directory / "before_reopen_contract.luau").write_text(module(frozen, False), encoding="utf8")
        driver = directory / "ownership.luau"
        driver.write_bytes(fixture.read_bytes())
        for path in (helper, fixture, directory / "new_reopen_contract.luau", directory / "before_reopen_contract.luau"):
            result = subprocess.run([str(LU / "luau-compile.exe"), str(path)], capture_output=True, timeout=20)
            assert result.returncode == 0, result.stderr.decode(errors="replace")
            compiled.append({"name": path.name, "sourceSHA256": sha(path.read_bytes()), "exitCode": 0})
        result = subprocess.run([str(LU / "luau.exe"), driver.name], cwd=directory,
                                capture_output=True, text=True, timeout=30)
        assert result.returncode == 0, result.stdout + result.stderr
        match = re.search(r"S06 actual-source ownership fixture passed: cases=(\d+) checks=(\d+)", result.stdout)
        assert match and int(match[1]) == 16
    assert {p.name: sha(p.read_bytes()) for p in FROZEN.iterdir() if p.is_file()} == frozen_hashes, "Frozen executed v1 evidence changed"
    assert {str(p.relative_to(ROOT)): sha(p.read_bytes()) for p in sources} == hashes, "Tool changed during proof"
    report = {"schema": "s06-reopen-ownership-offline-proof-v1", "atUtc": datetime.now(timezone.utc).isoformat(),
              "pass": True, "cases": int(match[1]), "checks": int(match[2]), "compiledUnits": compiled,
              "actualSourceHashesBeforeAfterExact": hashes, "executedV1EvidenceHashesBeforeAfterExact": frozen_hashes,
              "oldActualFirstRootAndChildFailureLeakControls": 2,
              "currentActualOwnershipScenarios": 14, "nativeCalls": 0, "studioConnected": False,
              "productionSourceWrites": 0, "originalInstanceWrites": 0, "restorationCertified": False,
              "scope": "Actual helper registration/adoption/call-site/cleanup code with fake instance/service boundaries; protects all game/ledger identities, cleans every later eligible root independently. Future helper hardening only; executed native v1 receipts remain exact. No new native engine, asset, runtime or removal approval."}
    output.parent.mkdir(parents=True, exist_ok=True)
    with output.open("x", encoding="utf8") as stream:
        json.dump(report, stream, indent=2)
        stream.write("\n")
    print(json.dumps({"pass": True, "cases": report["cases"], "checks": report["checks"],
                      "compiledUnits": len(compiled), "nativeCalls": 0, "output": str(output)}))


if __name__ == "__main__":
    main()
