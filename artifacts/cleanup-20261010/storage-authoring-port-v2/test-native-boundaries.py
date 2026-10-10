"""Replay exact native hook/environment slices with explicit offline boundaries.

No Studio, MCP, game instances, original setters, production files or index writes.
The old V1 inverse-adoption counterexample is deliberately retained as evidence.
"""
from pathlib import Path
import argparse
import hashlib
import json
import subprocess
import tempfile

HERE = Path(__file__).resolve().parent
ROOT = HERE.parents[2]
V1 = HERE.with_name("storage-authoring-port-v1")
LUAU = Path("C:/Users/mikke/AppData/Local/Temp/codex-luau-0.737/luau-compile.exe")
LUNE = Path("C:/Users/mikke/AppData/Local/Temp/codex-lune-0.10.5/lune.exe")
sha = lambda raw: hashlib.sha256(raw).hexdigest()


def between(text, first, last):
    assert text.count(first) == 1 and text.count(last) == 1, (first, last)
    return text.split(first, 1)[1].split(last, 1)[0]


def main():
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument("--receipt", type=Path, required=True)
    args = parser.parse_args()
    target = args.receipt.resolve()
    assert target.is_relative_to(ROOT / "artifacts/cleanup-20261010") and target.parent.is_dir() and not target.exists()
    files = [V1 / "native-trial.luau", HERE / "native-trial.luau", HERE / "transaction-core.luau",
             ROOT / "ServerScriptService/LobbyReimaginedPreview/RuntimeBake.ModuleScript.lua"]
    raws = {path: path.read_bytes() for path in files}
    sources = {path: raw.decode().replace("\r\n", "\n") for path, raw in raws.items()}
    core = sources[HERE / "transaction-core.luau"]
    bake = sources[files[-1]]
    assert sha(bake.encode()) == "1f564fdde835ad89b529d9069ddf87b0ed4991636f363eacbd098cc0b342ff28"
    receipt = {"schema": "retired-authoring-actual-native-boundaries-offline-v2", "passed": False,
               "nativeCalls": 0, "productionWrites": 0, "inputs": [{"path": p.relative_to(ROOT).as_posix(),
               "bytes": len(raw), "sha256": sha(raw)} for p, raw in raws.items()],
               "limits": "Exact native slices with table/metatable service and Parent boundaries. No actual Instance/engine scheduling/asset/absence/reference/gameplay/deletion proof."}
    chunks = [core, "local JSON=require('@lune/serde')\nlocal results={}\nlocal checks=0\nlocal function check(ok,why) checks+=1 assert(ok,why) end\n"]
    extracts = []
    for version, path in (("v1", files[0]), ("v2", files[1])):
        suffix = sources[path]
        rollback = "function(entry)" + between(suffix, "rollbackEligibility=function(entry)", "  beforeWrite=").removesuffix("  end,\n") + "end"
        setter = "function(entry,parent)" + between(suffix, "setParent=function(entry,parent)", "  afterWrite=").removesuffix("  end,\n") + "end"
        environment = "function B.environment" + between(suffix, "function B.environment", "function B.factory")
        unique = "local function unique" + between(suffix, "local function unique", "local function resolve")
        extracts.append({"version": version, "rollbackSHA256": sha(rollback.encode()), "setParentSHA256": sha(setter.encode()),
                         "environmentSHA256": sha(environment.encode()), "uniqueSHA256": sha(unique.encode())})
        chunks.append("\nlocal function run_" + version + "(target,fault)\n")
        chunks.append(r'''
 local SS={} local foreign={} local state={previous={rootRefs={}},epoch=0}
 local entries={} local report={parentWrites=0} local nested=false local budget={}
 for i=1,5 do
  local values={Parent=SS,Name="old"..i,metadata="original"}
  local root=setmetatable({}, {__index=values,__newindex=function(_,key,value)
   values[key]=value
   if key=="Parent" and i==target and fault=="commit-then-error" and value==nil then error("own setter committed then failed") end
  end})
  entries[i]={root=root,name=values.Name,snapshot={root=root},invoked=false}
  state.previous.rootRefs[root]=true
 end
 function SS:GetChildren()local out={} for _,e in entries do if e.root.Parent==SS then out[#out+1]=e.root end end return out end
 local A={SS=SS,check=check}
 local B={}
 function B.restoreLease()check(true,"controlled same owned lease/mode")end
 function B.lease()
  B.restoreLease()
  if not nested and target and entries[target].root.Parent==SS and report.parentWrites==target-1 then
   nested=true
   if fault=="foreign-nil-throw" or fault=="foreign-nil-cas" or fault=="foreign-nil-epoch" then entries[target].root.Parent=nil end
   if fault=="foreign-nil-epoch" then state.epoch=1 end
   if fault=="foreign-nil-throw" or fault=="refuse-still-original" then error("native hook refused before invocation") end
  end
  check(state.epoch==0,"foreign Source/global event")
 end
 function B.tree(snapshot,detached)
  check(snapshot.root.metadata=="original","same root metadata")
  check(snapshot.root.Parent==SS or (detached and snapshot.root.Parent==nil),"foreign Parent")
 end
 function B.budget(entry,phase)budget[#budget+1]={entry=entry,phase=phase}end
''')
        chunks.append(unique)
        chunks.append(" local hooks={rollbackEligibility=" + rollback + ",setParent=" + setter + "}\n")
        chunks.append(r'''
 hooks.preflight=function()end
 hooks.parent=function(e)return e.root.Parent end
 hooks.originalParent=function()return SS end
 hooks.detachEligibility=function(e)check(e.root.Parent==SS,"original CAS")end
 hooks.beforeWrite=function()end
 hooks.afterWrite=function()end
 hooks.absentPort=function()for _,e in entries do check(e.root.Parent==nil,"all absent")end end
 hooks.finalGuard=function()check(state.epoch==0,"global event fails final") for _,e in entries do check(e.root.Parent==SS,"all originals restored")end end
 local transaction=T.run(entries,hooks)
 local foreignNil=fault=="foreign-nil-throw" or fault=="foreign-nil-cas" or fault=="foreign-nil-epoch"
 local preserved=''' + ("false" if version == "v1" else "true") + r'''
 if foreignNil then
  check(not transaction.passed,"failure never certifies pass")
  check(entries[target].invoked==not preserved,"actual setter invocation ownership")
  check(entries[target].root.Parent==(if preserved then nil else SS),"V1 reproduces adoption; V2 preserves foreign nil")
  check(#transaction.pending==(if preserved then 1 else 0),"foreign pending is exact")
  check(report.parentWrites==2*(target-1)+(if preserved then 0 else 1),"no unowned inverse setter")
 elseif fault=="refuse-still-original" then
  check(not transaction.passed and #transaction.pending==0,"uninvoked original safely disarmed")
  check(not entries[target].invoked and report.parentWrites==2*(target-1),"no uninvoked original setter")
 elseif fault=="commit-then-error" then
  check(not transaction.passed and #transaction.pending==0,"owned commit-then-error restored")
  check(entries[target].invoked and report.parentWrites==2*target,"owned inverse allowed")
 else check(transaction.passed and report.parentWrites==10,"successful owned transaction") end
 for i,e in entries do if not (foreignNil and preserved and i==target) then check(e.root.Parent==SS,"independent other original restored")end end
 results[#results+1]={version="''' + version + r'''",target=target,fault=fault,parentWrites=report.parentWrites,
  passed=transaction.passed,pending=transaction.pending,counterexample=foreignNil and not preserved,
  foreignNilPreserved=foreignNil and preserved}
end
''')
        chunks.append("run_" + version + "(nil,'success')\nfor _,target in {1,3,5} do for _,fault in {'foreign-nil-throw','foreign-nil-cas','foreign-nil-epoch','refuse-still-original','commit-then-error'} do run_" + version + "(target,fault) end end\n")
        chunks.append("\nlocal function domain_" + version + "(clientDomain)\n")
        chunks.append(r'''
 local game={PlaceId=131311258779917,GameId=10559217407,CreatorId=1039373905}
 local forbidden=function()error("denied initializer/write")end
 local denied=setmetatable({},{__index=forbidden,__newindex=forbidden})
 local A={check=check,SS={GetChildren=function()return {}end},RS={IsClient=function()return true end},
  HS={GenerateGUID=function()return "offline-domain-only" end},ENC=denied}
 local B={}
''')
        chunks.append(unique + environment)
        chunks.append(" local factory=function(game,script,workspace,Instance,require,task,coroutine,spawn,delay,wait,shared,_G)\n" + bake + "\nend\n")
        chunks.append(r'''
 local env,log=B.environment(nil,nil,clientDomain)
 local module=factory(env,denied,denied,denied,forbidden,denied,denied,forbidden,forbidden,forbidden,denied,denied)
 local ok,why=pcall(module.GetManifest)
 check(not ok,"semantic boundary deliberately lacks assets")
 local projected=''' + ("true" if version == "v1" else "clientDomain==true") + r'''
 if projected then check(string.find(tostring(why),"Preview bake is server-only",1,true)~=nil and #log==0,"actual body rejects client before selector")
 else check(string.find(tostring(why),"Preview raw source not installed",1,true)~=nil and #log==1 and log[1]=="LobbyReimaginedBlenderSource20261001R4","actual body reaches current selector under controlled server projection") end
 results[#results+1]={version="''' + version + r'''",semanticDomainCase=true,controlledClient=clientDomain==true,
  actualEditBoundaryIsClient=true,selectors=log,serverOnlyRejected=projected}
end
''')
        chunks.append("domain_" + version + "(nil) domain_" + version + "(true) domain_" + version + "(false)\n")
    chunks.append("print(JSON.encode('json',{passed=true,cases=#results,checks=checks,results=results}))\n")
    fixture = "".join(chunks).encode()
    receipt["extractedActualSlices"] = extracts
    receipt["fixtureBytes"] = len(fixture)
    receipt["fixtureSHA256"] = sha(fixture)
    try:
        with tempfile.TemporaryDirectory(prefix="mongotv-s04-actual-boundaries-") as directory:
            path = Path(directory) / "actual-boundaries.luau"
            path.write_bytes(fixture)
            compiled = subprocess.run([str(LUAU), str(path)], capture_output=True, text=True, timeout=30)
            receipt["compile"] = {"exitCode": compiled.returncode, "stderr": compiled.stderr[:5000]}
            assert compiled.returncode == 0, compiled.stderr
            replay = subprocess.run([str(LUNE), "run", str(path)], capture_output=True, text=True, timeout=60)
            receipt["exitCode"] = replay.returncode
            receipt["stderr"] = replay.stderr[:6000]
            assert replay.returncode == 0, replay.stderr
            receipt["replay"] = json.loads(replay.stdout)
            assert receipt["replay"]["passed"] and receipt["replay"]["cases"] == 38
            receipt["passed"] = True
    except BaseException as error:
        receipt["error"] = str(error)
        raise
    finally:
        for path, raw in raws.items():
            assert path.read_bytes() == raw, "Candidate drift during replay"
        with target.open("xb") as stream:
            stream.write((json.dumps(receipt, ensure_ascii=False, indent=2) + "\n").encode())
    print(json.dumps({"passed": True, "cases": receipt["replay"]["cases"], "checks": receipt["replay"]["checks"], "receiptSHA256": sha(target.read_bytes())}))


if __name__ == "__main__":
    main()
