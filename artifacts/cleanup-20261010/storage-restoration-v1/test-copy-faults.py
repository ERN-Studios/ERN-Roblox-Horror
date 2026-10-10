"""Execute actual prepare/adopt/restore/reopen/cleanup fragments with owned fakes."""
from pathlib import Path
import argparse
import hashlib
import json
import subprocess
import tempfile

HERE = Path(__file__).resolve().parent
ROOT = HERE.parents[2]
LU = Path("C:/Users/mikke/AppData/Local/Temp/codex-luau-0.737/luau-compile.exe")
LUNE = Path("C:/Users/mikke/AppData/Local/Temp/codex-lune-0.10.5/lune.exe")
source = (HERE / "restoration-probe-v4.luau").read_bytes()
before_source = (HERE / "restoration-probe-v3.luau").read_bytes()
text = source.decode()
fixture = (HERE / "copy-faults.luau").read_bytes()
supplement = (HERE / "restore-supplement.json").read_bytes()
sha = lambda raw: hashlib.sha256(raw).hexdigest()
parser = argparse.ArgumentParser(description=__doc__)
parser.add_argument("--receipt", type=Path, default=HERE / "copy-fault-proof.json")
args = parser.parse_args()
target = args.receipt.resolve()
assert target.is_relative_to(ROOT / "artifacts/cleanup-20261010") and not target.exists(), "New owned cleanup receipt only"
assert target.parent.is_dir()

def segment(start, end):
    assert text.count(start) == text.count(end) == 1
    return text.split(start, 1)[1].split(end, 1)[0]

ownership = segment("-- OWNERSHIP CONTRACT BEGIN: exercised from this exact source offline.\n", "-- OWNERSHIP CONTRACT END.")
restore = segment("-- RESTORE SUPPLEMENT CONTRACT BEGIN: extract this exact helper offline.\n", "-- RESTORE SUPPLEMENT CONTRACT END.")
stage = " copies=SER:DeserializeInstancesAsync(raw)" + segment(" copies=SER:DeserializeInstancesAsync(raw)", " local transfer=postParts(buffer.tostring(roundtrip))")
cleanup = segment("-- Independently clean every adopted root, even if an earlier returned root was foreign.\n", "local valid,reason=pcall(function()")
canonical = "local function canonical(value)\n" + segment("local function canonical(value)\n", "local function tags(s)")
header = '''return function(env)
 local game,state,rows,roots=env.game,env.state,env.rows,env.roots
 local report={createdRoots=0,destroyedRoots=0,sourceWrites=0,originalParentWrites=0,modeSwitches=0}
 local copyOwnedNodes,copyOwnedRoots,knownOriginals={},{},{}
 local knownOriginalCount=0
 local check=env.check
 local MAX_ORIGINALS,MAX_NODES=500000,25000
 local task={wait=function()env.check(false,"Unexpected registration yield in small fixture")end}
 local owned=function()return true end
 local epoch=0
 local sha=env.sha
 local CFrame=env.CFrame
 local typeof=env.typeof
 local originals=env.originals
 local SER=env.SER
 local raw=env.raw
 local expectedSources=env.expectedSources
 local nodes=env.originalSnapshot.nodes
 local forestSnapshot=env.forestSnapshot
 local copies={}
'''
def actual_lexical_module(candidate):
    before = candidate.decode()
    marker = "-- RESTORE SUPPLEMENT CONTRACT BEGIN: extract this exact helper offline."
    helper = before.split(marker + "\n", 1)[1].split("-- RESTORE SUPPLEMENT CONTRACT END.", 1)[0]
    # Preserve the candidate's declaration order rather than injecting a binding.
    forward = "local supplement -- Forward declaration: the helper must capture this local, never a global."
    late = "local context,originalSnapshot,supplement"
    assert before.count(forward) + before.count(late) == 1
    early_declaration = forward + "\n" if forward in before else ""
    late_declaration = late if late in before else "local context,originalSnapshot"
    assert before.index(marker) < before.index(late_declaration)
    if early_declaration:
        assert before.index(forward) < before.index(marker)
    return header + canonical + ownership + early_declaration + helper + "\n" + late_declaration + '''
 context,originalSnapshot,supplement=env.context,env.originalSnapshot,env.supplement
 protectOriginals(env.census)
 local ok,why=xpcall(function()
''' + stage + '''
 end,debug.traceback)
 env.beforeCleanup()
''' + cleanup + '''
 local valid,problem=pcall(env.originals)
 if not valid then ok=false why=tostring(why).."\\noriginal guard failed: "..tostring(problem) end
 report.pass=ok report.error=if ok then nil else tostring(why)
 return report
end
'''
module = actual_lexical_module(source)
before_module = actual_lexical_module(before_source)
with tempfile.TemporaryDirectory(prefix="mongotv-storage-copy-faults-") as name:
    tmp = Path(name)
    paths = {"actual_recipe.luau": module.encode(), "actual_recipe_before.luau": before_module.encode(), "copy-faults.luau": fixture, "restore-supplement.json": supplement}
    for filename, raw in paths.items():
        (tmp / filename).write_bytes(raw)
    compiled = []
    for path in (HERE / "restoration-probe-v4.luau", HERE / "capture-live-baseline.luau", tmp / "actual_recipe.luau", tmp / "actual_recipe_before.luau", tmp / "copy-faults.luau"):
        for opt in ("-O0", "-O1"):
            result = subprocess.run([str(LU), opt, str(path)], capture_output=True, timeout=20)
            if result.returncode != 0:
                failure = {"schema": "storage-copy-fault-failed-compile-v1", "nativeCalls": 0,
                    "candidateSHA256": sha(source), "fixtureSHA256": sha(fixture), "name": path.name,
                    "opt": opt, "exitCode": result.returncode, "stderr": result.stderr.decode(errors="replace")}
                payload = (json.dumps(failure, indent=2) + "\n").encode()
                with (HERE / ("copy-compile-failure-" + sha(payload)[:12] + ".json")).open("xb") as stream:
                    stream.write(payload)
                raise AssertionError(failure["stderr"])
            compiled.append({"name": path.name, "opt": opt, "sourceSHA256": sha(path.read_bytes()), "exitCode": 0})
    result = subprocess.run([str(LUNE), "run", "copy-faults.luau", str(ROOT / "artifacts/cleanup-serverstorage-20261009/external-storage-archive-v1/native.rbxm")],
        cwd=tmp, capture_output=True, text=True, timeout=60)
    if result.returncode != 0:
        failure = {"schema": "storage-copy-fault-failed-execution-v1", "nativeCalls": 0,
            "candidateSHA256": sha(source), "fixtureSHA256": sha(fixture), "moduleSHA256": sha(module.encode()),
            "exitCode": result.returncode, "stdout": result.stdout, "stderr": result.stderr}
        target = HERE / ("copy-fault-failure-" + sha(encode := json.dumps(failure, indent=2).encode())[:12] + ".json")
        with target.open("xb") as stream: stream.write(encode + b"\n")
        raise AssertionError(result.stdout + result.stderr)
    rows = json.loads(result.stdout)
assert (HERE / "restoration-probe-v4.luau").read_bytes() == source
assert (HERE / "restoration-probe-v3.luau").read_bytes() == before_source
assert (HERE / "copy-faults.luau").read_bytes() == fixture
assert (HERE / "restore-supplement.json").read_bytes() == supplement
report = {"schema": "storage-restoration-actual-copy-fault-proof-v1", "pass": True, "nativeCalls": 0,
    "candidateExecutedNative": False, "restorationCertified": False, "normalizationApplied": False,
    "candidateSHA256": sha(source), "fixtureSHA256": sha(fixture), "actualModuleSHA256": sha(module.encode()),
    "negativeControlCandidateSHA256": sha(before_source), "negativeControlModuleSHA256": sha(before_module.encode()),
    "globalSupplementInjected": False,
    "compiledUnits": compiled, "results": rows,
    "scope": "Actual lexical constructor-path, ownership/adoption, setters, first/second DS/serialize ordering and independent root cleanup fragments executed. Source/parent/identity invariants checked on owned fakes; hashes are real. CFrame, serializer, reflection, scene, callbacks and originals guard are explicit fixture boundaries. Lune exact construction failed separately; Root native readonly constructor passed separately. No Roblox-engine setter/recovery/gameplay assertion."}
assert not target.exists()
with target.open("xb") as stream:
    stream.write((json.dumps(report, indent=2) + "\n").encode())
print(json.dumps({"pass": True, "cases": rows["cases"], "checks": rows["checks"], "compiledUnits": len(compiled), "nativeCalls": 0}))
