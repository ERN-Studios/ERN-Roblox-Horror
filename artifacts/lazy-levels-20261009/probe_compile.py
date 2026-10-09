"""Compile candidates in fresh empty native modules, guarding all captured originals."""
from pathlib import Path
import hashlib
import json
import sys
import argparse
import re

ROOT = Path(__file__).resolve().parents[2]
HERE = Path(__file__).resolve().parent
sys.path.insert(0, str(ROOT / "tools"))
from sync_from_studio import StudioMcpClient, find_mcp_batch, select_studio, RELEASE_STUDIO_NAME
from push_repo_to_studio import luau_string

parser = argparse.ArgumentParser(description=__doc__)
parser.add_argument("baseline", type=Path)
parser.add_argument("--label", default="native-compile")
parser.add_argument("--candidates", nargs="+", type=Path)
args = parser.parse_args()
assert re.fullmatch(r"[A-Za-z0-9_.-]{1,70}", args.label)
records = json.loads(args.baseline.read_bytes())
candidates = args.candidates or [HERE / "LevelWorldStorage.candidate.luau", *sorted((HERE / "candidates").glob("*.luau"))]
assert candidates and len(records) >= 10
assert len({p.resolve() for p in candidates}) == len(candidates)
receipt_path = HERE / (args.label + ".json")
checkpoint = ROOT / ".git/lazy-levels-20261009" / (args.label + ".luau")
assert not receipt_path.exists() and not checkpoint.exists(), "Do not overwrite native compilation evidence"
native = "{" + ",".join("{path="+luau_string(r["path"])+",class="+luau_string(r["class"])+",hash="+luau_string(r["sha256"])+"}" for r in records) + "}"
items = "{" + ",".join("{name="+luau_string(p.name)+",source="+luau_string(p.read_bytes().decode("utf-8"))+"}" for p in candidates) + "}"
code = '''assert(game.PlaceId==131311258779917 and game.GameId==10559217407 and not game:GetService("RunService"):IsRunning(),"Wrong place/state")
local SES=game:GetService("ScriptEditorService") local HS=game:GetService("HttpService") local originals='''+native+'''
local function hash(value)
 local b=game:GetService("EncodingService"):ComputeBufferHash(buffer.fromstring(value),Enum.HashAlgorithm.Sha256)
 local t={} for i=0,buffer.len(b)-1 do t[i+1]=string.format("%02x",buffer.readu8(b,i)) end return table.concat(t)
end
local function resolve(path)
 local current=game for name in path:gmatch("[^.]+") do
  local found for _,child in current:GetChildren() do if child.Name==name then assert(not found,"Ambiguous original") found=child end end
  current=assert(found,"Missing original "..path)
 end return current
end
for _,row in originals do row.instance=resolve(row.path) end
local function guard()
 for _,row in originals do local s=resolve(row.path)
  assert(s==row.instance and s.ClassName==row.class and hash(s.Source)==row.hash and SES:GetEditorSource(s)==s.Source,"Authoritative original changed: "..row.path)
 end
end
local owned={} local compiled={}
local ok,result=xpcall(function()
 guard()
 for _,item in '''+items+''' do
  local module=Instance.new("ModuleScript") table.insert(owned,module)
  module.Name="LazyLevelsCompileProbe" module.Parent=game:GetService("ServerStorage")
  assert(module.Source=="" and SES:GetEditorSource(module)=="","Fresh staging baseline is not empty")
  local source="return function()\\n"..item.source.."\\nend"
  SES:UpdateSourceAsync(module,function(current)
   guard() assert(current=="" and module.Source=="" and SES:GetEditorSource(module)=="","Empty staging baseline changed") return source
  end)
  guard() assert(module.Source==source and SES:GetEditorSource(module)==source,"Staged source differs")
  assert(type(require(module))=="function","Compile wrapper failed")
  table.insert(compiled,{name=item.name,sourceSHA256=hash(item.source),bytes=#item.source})
  task.wait()
 end
 return {compiled=compiled}
end,debug.traceback)
for _,module in owned do module:Destroy() end
guard()
assert(ok,result)
result.authoritativeSourcesPreserved=true result.probesDestroyed=true result.placeId=game.PlaceId
return HS:JSONEncode(result)
'''
checkpoint.write_text(code, encoding="utf-8", newline="\n")
client = StudioMcpClient(find_mcp_batch())
try:
    client.initialize()
    studio = select_studio(client, RELEASE_STUDIO_NAME, 20)
    result = json.loads(client.call("execute_luau", {"studio_id":studio["id"], "datamodel_type":"Edit", "code":code}))
finally:
    client.close()
assert len(result["compiled"]) == len(candidates)
for row, path in zip(result["compiled"], candidates):
    assert row["name"] == path.name
    assert row["sourceSHA256"] == hashlib.sha256(path.read_bytes()).hexdigest()
receipt_path.write_text(json.dumps(result, indent=2)+"\n", encoding="utf-8")
print(json.dumps({"compiled":len(result["compiled"]), "originalsPreserved":result["authoritativeSourcesPreserved"], "probesDestroyed":result["probesDestroyed"]}))
