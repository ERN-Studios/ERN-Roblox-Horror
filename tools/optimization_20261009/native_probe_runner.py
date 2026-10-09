"""Owner-run, sequential isolated native contracts; never a gameplay/performance pass.

Default invocation only prepares Luau files locally. --run is the explicit Studio
mutation boundary. No native backup is taken, following the owner's 2026-10-09
instruction. A fresh ModuleScript is the only Studio source this runner writes.
Authoritative originals are compared exactly, never restored over concurrent edits.
"""
from __future__ import annotations

import argparse
from datetime import datetime, timezone
import hashlib
import json
from pathlib import Path
import sys

ROOT = Path(__file__).resolve().parents[2]
TASK = ROOT / "tools/optimization_20261009"
sys.path.insert(0, str(ROOT / "tools"))
from sync_from_studio import StudioMcpClient, find_mcp_batch, select_studio


PROBES = (
    ("loading-contract", "loading/install/native-loading-contract-probe.luau", 51),
    ("native-visibility", "loading/native-visibility-probe.luau", 14),
    ("spectate-contract", "loading/install/native-spectate-contract-probe.luau", 51),
    ("effects-contract", "effects/native_contract_probe.luau", 14),
)


def sha(text: str) -> str:
    return hashlib.sha256(text.encode("utf-8")).hexdigest()


def literal(value) -> str:
    # JSON text inside a Lua string; JSONDecode restores Unicode and literal
    # escapes correctly. No source ever passes through shell interpolation.
    return json.dumps(json.dumps(value, ensure_ascii=True))


def read_source(path: Path) -> str:
    return path.read_bytes().decode("utf-8")


def load_inputs():
    manifest = json.loads((TASK / "proposed-source-manifest.json").read_text(encoding="utf-8"))
    assert manifest["placeId"] == 131311258779917 and manifest["universeId"] == 10559217407
    sources = []
    for row in manifest["scripts"]:
        path = (ROOT / row["afterFile"]).resolve()
        assert path.is_relative_to(TASK), "Only reviewed task-owned source inputs"
        source = read_source(path)
        assert sha(source) == row["afterSha256"], "Reviewed source hash changed: " + row["afterFile"]
        sources.append({"segments": row["segments"], "class": row["class"],
                        "source": source, "sha256": sha(source)})
    assert len(sources) == 5, "Expected the five reviewed installed sources"
    budget = next(row["source"] for row in sources if row["segments"] == ["ReplicatedStorage", "SceneEffectBudget"])
    loading = next(row["source"] for row in sources if row["segments"] == ["ReplicatedFirst", "Lobby Loading Screen"])
    # Native visibility uses the exact production helpers from the installed
    # loading source, including rotated OBB distance and GUI ancestry checks.
    visibility = read_source(TASK / "loading/native-visibility-probe.luau")
    helpers = visibility[visibility.index("local BOOT_ASSET_RADIUS"):visibility.index("return function()")].strip()
    assert helpers in loading, "Native visibility helper diverged from installed loading proposal"
    for filename, path in (("loading-offline-result.json", ["ReplicatedFirst", "Lobby Loading Screen"]),
                           ("spectate-offline-result.json", ["ServerScriptService", "GameManager"])):
        result = json.loads((TASK / "loading/install" / filename).read_text(encoding="utf-8"))
        expected = next(row["sha256"] for row in sources if row["segments"] == path)
        assert result["source_sha256"] == expected, "Frozen contract belongs to a different source"
    return sources, budget


def staged_source(fixture: str, budget: str | None = None) -> str:
    # Local print captures the existing contracts' assertion totals. Every
    # required module returns one run function, never an already-executed result.
    prefix = '''local output = {}
local function print(...)
 local values = table.pack(...)
 local line = {}
 for i=1,values.n do table.insert(line,tostring(values[i])) end
 table.insert(output,table.concat(line,"\\t"))
end
local fixture = (function()
'''
    source = prefix + fixture + '\nend)()\nassert(type(fixture)=="function","Fixture must return a run function")\n'
    if budget is not None:
        source += "local Budget = (function()\n" + budget + '\nend)()\nassert(type(Budget)=="table","Budget closure did not return its module")\n'
    return source + 'return function()\n local result=fixture(' + ("Budget" if budget is not None else "") + ')\n return {result=result,output=output}\nend\n'


LUA_RUNNER = r'''local H=game:GetService("HttpService")
local SES=game:GetService("ScriptEditorService")
local RS=game:GetService("RunService")
local expected=H:JSONDecode(__EXPECTED__)
local probeName=H:JSONDecode(__NAME__)
local fixtureSource=H:JSONDecode(__FIXTURE__)
local expectedStage=H:JSONDecode(__STAGE__)
local originals,installed,phases={},{},{}
local stage,stageParent,stageName=nil,nil,nil
local snapshotComplete=false
local existingEditorConflicts=0
local function guard()
 assert(not RS:IsRunning(),"Edit required; owner playtest must remain untouched")
 assert(game.PlaceId==131311258779917 and game.GameId==10559217407,"Unexpected place/universe")
end
local function targetAt(segments)
 local current=game
 for _,segment in ipairs(segments) do
  local match=nil
  for _,child in ipairs(current:GetChildren()) do
   if child.Name==segment then assert(match==nil,"Ambiguous target path: "..segment); match=child end
  end
  assert(match~=nil,"Missing target path: "..segment)
  current=match
 end
 return current
end
local function verifyOriginals(phase)
 local conflicts={}
 local contextOk,contextProblem=pcall(guard)
 if not contextOk then table.insert(conflicts,{path="<execution-context>",error=tostring(contextProblem)}) end
 for _,row in ipairs(originals) do
  local ok,problem=pcall(function()
   local node=row.instance
   assert(node.Parent==row.parent and node.Name==row.name and node.ClassName==row.class
    and node:GetDebugId(0)==row.id and node:GetFullName()==row.path,"Original identity changed")
   assert(node.Source==row.source and SES:GetEditorSource(node)==row.editor,"Original Source/editor changed")
  end)
  if not ok then table.insert(conflicts,{path=row.path,id=row.id,error=tostring(problem)}) end
 end
 for _,row in ipairs(installed) do
  local ok,problem=pcall(function()
   local node=targetAt(row.segments)
   assert(node==row.instance and node:GetDebugId(0)==row.id and node.ClassName==row.class,"Installed identity changed")
   assert(node.Source==row.source and SES:GetEditorSource(node)==row.source,"Installed Source/editor CAS failed")
  end)
  if not ok then table.insert(conflicts,{path=table.concat(row.segments,"."),id=row.id,error=tostring(problem)}) end
 end
 table.insert(phases,{phase=phase,originalsChecked=#originals,installedChecked=#installed,conflicts=conflicts})
 assert(#conflicts==0,"Original preservation failed at "..phase..": "..H:JSONEncode(conflicts))
end
local function assertStageIdentity()
 guard()
 assert(stage~=nil and stage.ClassName=="ModuleScript" and stage.Parent==stageParent
  and stage.Name==stageName and stageParent:FindFirstChild(stageName)==stage,"Test module identity changed")
end
local ok,result=xpcall(function()
 guard()
 for index,node in ipairs(game:GetDescendants()) do
  if node:IsA("LuaSourceContainer") then
   local source,editor=node.Source,SES:GetEditorSource(node)
   table.insert(originals,{instance=node,parent=node.Parent,name=node.Name,class=node.ClassName,
    id=node:GetDebugId(0),path=node:GetFullName(),source=source,editor=editor})
   if source~=editor then existingEditorConflicts+=1 end
  end
  if index%2000==0 then task.wait() end
 end
 snapshotComplete=true
 for _,row in ipairs(expected) do
  local node=targetAt(row.segments)
  assert(node.ClassName==row.class,"Installed target class changed")
  assert(node.Source==row.source and SES:GetEditorSource(node)==row.source,"Installed source does not match reviewed proposal: "..node:GetFullName())
  table.insert(installed,{instance=node,id=node:GetDebugId(0),segments=row.segments,class=row.class,source=node.Source,sha256=row.sha256})
 end
 verifyOriginals("before-create")
 stage=Instance.new("ModuleScript") -- NEVER clone a LuaSourceContainer.
 stageName="_OptimizationContract_"..probeName.."_"..H:GenerateGUID(false)
 stage.Name=stageName
 assert(stage.Source=="" and SES:GetEditorSource(stage)=="","Fresh module Source/editor baseline not empty")
 stageParent=game:GetService("ServerStorage")
 assert(stageParent:FindFirstChild(stageName)==nil,"Test name collision")
 stage.Parent=stageParent
 assertStageIdentity()
 assert(stage.Source=="" and SES:GetEditorSource(stage)=="","Parenting changed empty Source/editor baseline")
 verifyOriginals("before-staging")
 local actualStage=expectedStage
 if probeName=="effects-contract" then
  -- Capture the actual installed Source, after CAS; do not require or clone it.
  local actualBudget=targetAt({"ReplicatedStorage","SceneEffectBudget"}).Source
  local prefix=H:JSONDecode(__WRAPPER_PREFIX__)
  local suffix=H:JSONDecode(__WRAPPER_SUFFIX__)
  actualStage=prefix..fixtureSource.."\nend)()\nassert(type(fixture)==\"function\",\"Fixture must return a run function\")\n"
   .."local Budget = (function()\n"..actualBudget.."\nend)()\nassert(type(Budget)==\"table\",\"Budget closure did not return its module\")\n"..suffix
  assert(actualStage==expectedStage,"Actual installed Budget produced a different staged closure")
 end
 SES:UpdateSourceAsync(stage,function(current)
  assertStageIdentity()
  verifyOriginals("inside-staging-callback")
  assert(current=="" and stage.Source=="" and SES:GetEditorSource(stage)=="","Fresh empty Source/editor CAS failed inside staging")
  return actualStage
 end)
 local deadline=os.clock()+1
 while (stage.Source~=actualStage or SES:GetEditorSource(stage)~=actualStage) and os.clock()<deadline do task.wait() end
 assertStageIdentity()
 assert(stage.Source==actualStage and SES:GetEditorSource(stage)==actualStage,"Staged Source/editor mismatch")
 verifyOriginals("after-staging")
 local run=require(stage)
 assert(type(run)=="function","Required probe must return a run function")
 verifyOriginals("after-require-before-run")
 local contract=run()
 verifyOriginals("after-contract")
 return contract
end,debug.traceback)
-- Finally: dispose only the fresh, test-owned script even if require/run/CAS fails.
local cleanupOk,cleanupProblem=pcall(function()
 if stage then
  stage:Destroy()
  assert(stage.Parent==nil,"Test module cleanup failed")
  if stageParent then assert(stageParent:FindFirstChild(stageName)~=stage,"Test module remained in staging parent") end
 end
end)
local originalsOk,originalsProblem=pcall(function()
 if snapshotComplete then verifyOriginals("after-cleanup-success-or-failure") end
end)
local pins={}
for _,row in ipairs(installed) do
 table.insert(pins,{path=table.concat(row.segments,"."),class=row.class,id=row.id,sha256=row.sha256})
end
return H:JSONEncode({probe=probeName,passed=ok and cleanupOk and originalsOk,snapshotComplete=snapshotComplete,
 contract=if ok then result else nil,error=if ok then nil else tostring(result),
 cleanupPassed=cleanupOk,cleanupError=if cleanupOk then nil else tostring(cleanupProblem),
 originalsPreserved=originalsOk and snapshotComplete,preservationError=if originalsOk then nil else tostring(originalsProblem),
 originalsCount=#originals,existingEditorConflicts=existingEditorConflicts,phases=phases,installed=pins,
 verifiedUtc=os.date("!%Y-%m-%dT%H:%M:%SZ"),kind="synthetic-native-contract",
 gameplay=false,performance=false,multiplayer=false,actualAssetFetches=false,realReplicationFocusCalls=false})
'''


def make_code(name: str, fixture: str, sources, budget: str):
    stage = staged_source(fixture, budget if name == "effects-contract" else None)
    prefix = staged_source("SENTINEL").split("SENTINEL")[0]
    suffix = 'return function()\n local result=fixture(Budget)\n return {result=result,output=output}\nend\n'
    replacements = {"__EXPECTED__": literal(sources), "__NAME__": literal(name),
                    "__FIXTURE__": literal(fixture), "__STAGE__": literal(stage),
                    "__WRAPPER_PREFIX__": literal(prefix), "__WRAPPER_SUFFIX__": literal(suffix)}
    code = LUA_RUNNER
    for marker, value in replacements.items():
        code = code.replace(marker, value)
    return code, stage


def utc() -> str:
    return datetime.now(timezone.utc).isoformat()


def main():
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument("--run", action="store_true", help="Root only: stage and run isolated probes in the released Edit session")
    parser.add_argument("--emit", type=Path, default=ROOT / "_local/optimization-20261009/native-probes",
                        help="Local preparation directory; no Studio connection without --run")
    parser.add_argument("--receipt", type=Path, default=TASK / "native-probe-receipt.json")
    args = parser.parse_args()
    sources, budget = load_inputs()
    args.emit.mkdir(parents=True, exist_ok=True)
    prepared = []
    for name, relative, checks in PROBES:
        fixture = read_source(TASK / relative)
        code, stage = make_code(name, fixture, sources, budget)
        (args.emit / (name + ".runner.luau")).write_text(code, encoding="utf-8", newline="\n")
        (args.emit / (name + ".module.luau")).write_text(stage, encoding="utf-8", newline="\n")
        prepared.append((name, checks, code, {"fixtureFile": str((TASK / relative).relative_to(ROOT)),
                         "fixtureSha256": sha(fixture), "stagedSourceSha256": sha(stage)}))
    if not args.run:
        print(f"Prepared {len(prepared)} sequential probes in {args.emit}; no Studio connection or native test run.")
        return
    installation = json.loads((TASK / "source-install-receipt.json").read_text(encoding="utf-8"))
    assert installation["complete"] is True, "Install all five sources before probing"
    receipt = {"startedUtc": utc(), "studioName": "[UPDATE] BACKROOMS: STAY QUIET",
               "placeId": 131311258779917, "universeId": 10559217407,
               "backupPolicy": "Owner explicitly instructed no native backup (2026-10-09)",
               "kind": "synthetic-native-contract", "gameplay": False, "performance": False,
               "multiplayer": False, "actualAssetFetches": False, "realReplicationFocusCalls": False,
               "complete": False, "probes": []}
    def save():
        args.receipt.parent.mkdir(parents=True, exist_ok=True)
        args.receipt.write_text(json.dumps(receipt, indent=2, ensure_ascii=True) + "\n", encoding="utf-8")
    client = None
    save()
    try:
        client = StudioMcpClient(find_mcp_batch())
        client.initialize()
        studio = select_studio(client, "[UPDATE] BACKROOMS: STAY QUIET", 25)
        sid = studio.get("studio_id") or studio.get("id")
        receipt["studioId"] = sid
        for name, expected_checks, code, provenance in prepared:
            row = {"probe": name, "startedUtc": utc(), **provenance}
            receipt["probes"].append(row)
            save()
            try:
                result = json.loads(client.call("execute_luau", {"studio_id": sid, "datamodel_type": "Edit", "code": code}))
                row.update(result)
                contract = result.get("contract") or {}
                detail = contract.get("result") or {}
                checks = detail.get("Checks", detail.get("checks"))
                if checks is None:
                    output = contract.get("output", [])
                    prefix = "loading policy contract checks: " if name == "loading-contract" else "spectator focus contract checks: "
                    totals = [line[len(prefix):] for line in output if line.startswith(prefix)]
                    checks = int(totals[0]) if len(totals) == 1 else None
                row["assertionChecks"] = checks
                assert result["passed"], "Native contract or preservation failed"
                assert checks == expected_checks, f"Unexpected assertion count: {checks}, expected {expected_checks}"
                print(f"{name}: {checks} synthetic native assertions; originals and cleanup verified", flush=True)
            except Exception as error:
                row["passed"] = False
                row["runnerError"] = f"{type(error).__name__}: {error}"
                raise
            finally:
                row["finishedUtc"] = utc()
                save()
        receipt["complete"] = True
    except Exception as error:
        receipt["error"] = f"{type(error).__name__}: {error}"
        raise
    finally:
        receipt["finishedUtc"] = utc()
        save()
        if client is not None:
            client.close()


if __name__ == "__main__":
    main()
