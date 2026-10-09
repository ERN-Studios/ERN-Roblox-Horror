"""Root-run isolated C05 gate. Execute only after N01 full/touch baseline passes.

python artifacts/cleanup-20261009/run_C05_probe.py full
python artifacts/cleanup-20261009/run_C05_probe.py touch
python artifacts/cleanup-20261009/run_C05_probe.py full --current
python artifacts/cleanup-20261009/run_C05_probe.py touch --current

Creates a new empty ModuleScript, preserves exact original source/editor and
controlled attributes including nil, compares native public API keys/arity,
and retains the entire compact report. Does not rewrite any original script.
"""
from pathlib import Path
from datetime import datetime, timezone
import argparse
import hashlib
import json
import re
import sys

ROOT = Path(__file__).resolve().parents[2]
CHECKPOINT = ROOT / ".git/mongotv-cleanup-20261009"
sys.path.insert(0, str(ROOT / "tools"))
from sync_from_studio import StudioMcpClient, find_mcp_batch, select_studio, RELEASE_STUDIO_NAME
from push_repo_to_studio import luau_string


def sha_lf(source):
    return hashlib.sha256(source.replace("\r\n", "\n").encode()).hexdigest()


def attributes(source, name):
    start = source.index(f"local {name} = {{")
    block = source[start:source.index("\n}", start)]
    uncommented = "\n".join(line.split("--", 1)[0] for line in block.splitlines())
    return re.findall(r'"([A-Za-z0-9_]+)"', uncommented)


def unpack(raw):
    data = json.loads(raw)
    if isinstance(data, dict) and "content" in data:
        for entry in data["content"]:
            if entry.get("type") == "text":
                try:
                    value = json.loads(entry["text"])
                except (TypeError, ValueError):
                    continue
                if isinstance(value, dict) and value.get("gate") == "C05":
                    return value
    return data


def main():
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument("mode", choices=["full", "touch"])
    parser.add_argument("--current", action="store_true", help="Run current authoritative QA without staging C05")
    parser.add_argument("--label", help="Separate receipt label for a later authoritative after-gate")
    args = parser.parse_args()
    prepared = json.loads((ROOT / "artifacts/cleanup-20261009/C05-prepared.json").read_text(encoding="utf8"))
    original = (ROOT / "ReplicatedStorage/UIRegression.ModuleScript.lua").read_text(encoding="utf8")
    owner = (ROOT / "ReplicatedStorage/RoundHud.ModuleScript.lua").read_text(encoding="utf8")
    candidate = (CHECKPOINT / "client-before/N01/UIRegression.C05.candidate.lua").read_text(encoding="utf8")
    if not args.current:
        assert sha_lf(original) == prepared["currentBeforeSha256"], "C05 requires its exact prepared authoritative baseline"
        assert sha_lf(candidate) == prepared["candidateSha256"], "C05 candidate changed"
    workspace_names = attributes(original, "BORROWED_WORKSPACE_ATTRIBUTES")
    player_names = attributes(original, "BORROWED_PLAYER_ATTRIBUTES")
    assert workspace_names and player_names
    ws = "{" + ",".join(luau_string(name) for name in workspace_names) + "}"
    ps = "{" + ",".join(luau_string(name) for name in player_names) + "}"
    entry = "RunAllCompact()" if args.mode == "full" else 'Compact("TouchTargetMatrix")'
    code = f'''
assert(game.PlaceId==131311258779917 and game.GameId==10559217407,"wrong place")
local SES=game:GetService("ScriptEditorService") local HS=game:GetService("HttpService")
local ENC=game:GetService("EncodingService") local RS=game:GetService("ReplicatedStorage")
local player=game:GetService("Players").LocalPlayer
local function unique(name)
 local result=nil
 for _,child in RS:GetChildren() do if child.Name==name then assert(not result,"ambiguous original path") result=child end end
 assert(result and result.ClassName=="ModuleScript","original class/path changed") return result
end
local live,owner=unique("UIRegression"),unique("RoundHud")
local before,ownerBefore=live.Source,owner.Source
local function hash(source)
 local b=ENC:ComputeBufferHash(buffer.fromstring(source:gsub("\\r\\n","\\n")),Enum.HashAlgorithm.Sha256) local out={{}}
 for i=0,buffer.len(b)-1 do out[#out+1]=string.format("%02x",buffer.readu8(b,i)) end return table.concat(out)
end
local function guard()
 assert(unique("UIRegression")==live and unique("RoundHud")==owner,"original identity changed")
 assert(live.Source==before and SES:GetEditorSource(live)==before,"original UIRegression source/editor changed")
 assert(owner.Source==ownerBefore and SES:GetEditorSource(owner)==ownerBefore,"original RoundHud source/editor changed")
 assert(hash(before)=={luau_string(sha_lf(original))} and hash(ownerBefore)=={luau_string(sha_lf(owner))},"repo/native baseline mismatch")
end
local function capture(object,names)
 local out={{}} for _,name in names do out[name]={{Value=object:GetAttribute(name)}} end return out
end
local function drift(object,saved)
 local out={{}} for name,row in saved do
  local actual=object:GetAttribute(name)
  if actual~=row.Value then out[#out+1]={{Name=name,Before=tostring(row.Value),After=tostring(actual)}} end
 end return out
end
local function api(module)
 local out={{}} for name,value in module do
  local row={{Name=tostring(name),Type=type(value)}}
  if type(value)=="function" then row.Params,row.Variadic=debug.info(value,"a") end
  out[#out+1]=row
 end table.sort(out,function(a,b) return a.Name<b.Name end) return out
end
guard()
assert(workspace:GetAttribute("UIRegressionHarnessLockToken")==nil,"harness lock already held")
local savedWS,savedPlayer=capture(workspace,{ws}),capture(player,{ps})
local savedLock=capture(workspace,{{"UIRegressionHarnessLockToken","UIRegressionHarnessLockLane","UIRegressionHarnessLockBeat"}})
local useCurrent={str(args.current).lower()}
local probe=nil
if not useCurrent then probe=Instance.new("ModuleScript") probe.Name="MongoTVCleanupC05_{args.mode}" end
local candidate={luau_string(candidate)}
local ok,result=pcall(function()
 if probe then
  assert(probe.Source=="" and SES:GetEditorSource(probe)=="","new probe must start empty")
  SES:UpdateSourceAsync(probe,function(current)
   guard() assert(current=="" and probe.Source=="" and SES:GetEditorSource(probe)=="","empty temporary baseline changed")
   return candidate
  end)
  assert(probe.Source==candidate and SES:GetEditorSource(probe)==candidate,"temporary source/editor mismatch")
 end
 local actual=require(live)
 local test=if probe then require(probe) else actual
 local actualAPI,candidateAPI=api(actual),api(test)
 assert(HS:JSONEncode(actualAPI)==HS:JSONEncode(candidateAPI),"public API key/type/arity changed")
 local report,failed=test.{entry}
 return {{report=report,failed=failed,publicAPI=actualAPI}}
end)
local destroyed,cleanupError=pcall(function() if probe then probe:Destroy() end end)
local stable,guardError=pcall(guard)
local output={{gate="C05",mode={luau_string(args.mode)},current=useCurrent,probeCreated=probe~=nil,ok=ok,temporaryDestroyed=destroyed,originalSourcesUnchanged=stable,
 workspaceDrift=drift(workspace,savedWS),playerDrift=drift(player,savedPlayer),lockDrift=drift(workspace,savedLock),
 beforeSha256={luau_string(sha_lf(original))},candidateSha256={luau_string(sha_lf(candidate))}}}
if ok then output.result=result else output.error=tostring(result) end
if not destroyed then output.cleanupError=tostring(cleanupError) end
if not stable then output.guardError=tostring(guardError) end
return HS:JSONEncode(output)
'''
    attempt = datetime.now(timezone.utc).strftime("%Y%m%dT%H%M%S%fZ")
    label = f"B06-final-{args.mode}" if args.current else f"B07-C05-{args.mode}"
    if args.label:
        assert re.fullmatch(r"[A-Za-z0-9-]+", args.label), "unsafe receipt label"
        label = args.label
    (CHECKPOINT / f"{label}-{attempt}.luau").write_text(code, encoding="utf8")
    client = StudioMcpClient(find_mcp_batch())
    try:
        client.initialize()
        studio = select_studio(client, RELEASE_STUDIO_NAME, 15)
        raw = client.call("execute_luau", {"studio_id": studio["id"], "datamodel_type": "Client", "code": code})
    finally:
        client.close()
    (ROOT / "artifacts/cleanup-20261009" / f"{label}.json").write_text(raw + "\n", encoding="utf8")
    (CHECKPOINT / f"{label}-{attempt}-result.json").write_text(raw + "\n", encoding="utf8")
    value = unpack(raw)
    print(json.dumps(value, ensure_ascii=True))
    if not isinstance(value, dict) or not value.get("ok") or not value.get("temporaryDestroyed") or not value.get("originalSourcesUnchanged"):
        raise SystemExit(1)
    if any(value.get(name) for name in ["workspaceDrift", "playerDrift", "lockDrift"]) or value["result"]["failed"]:
        raise SystemExit(1)


if __name__ == "__main__":
    main()
