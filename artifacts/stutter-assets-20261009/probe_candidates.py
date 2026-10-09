"""Compile candidates in fresh native modules and run the tiny actual-kit probe."""
import json
import sys
from pathlib import Path

ROOT = Path(__file__).resolve().parents[2]
sys.path.insert(0, str(ROOT / "tools"))
from sync_from_studio import StudioMcpClient, find_mcp_batch, select_studio, RELEASE_STUDIO_NAME
from push_repo_to_studio import luau_string

records = []
if len(sys.argv) > 1:
    records = json.loads(Path(sys.argv[1]).read_text())
else:
    for name in ("scoped-before", "visuals-before", "renderer-before"):
        records += json.loads((ROOT / ".git/stutter-assets-20261009" / name / "sources.json").read_text())
originals = "{" + ",".join("{path=" + luau_string(r["path"]) + ",source=" + luau_string(Path(r["sourceFile"]).read_bytes().decode("utf-8")) + "}" for r in records) + "}"
candidates = list((ROOT / "artifacts/stutter-assets-20261009/visual-candidates").glob("*.luau"))
candidates += list((ROOT / "artifacts/stutter-assets-20261009/candidates").glob("*.luau"))
items = "{" + ",".join("{name=" + luau_string(p.name) + ",source=" + luau_string(p.read_text()) + "}" for p in candidates) + "}"
probe_source = (ROOT / "artifacts/stutter-assets-20261009/probe_renderer_native.luau").read_text()
code = '''assert(game.PlaceId==131311258779917 and game.GameId==10559217407,"wrong place")
assert(not game:GetService("RunService"):IsRunning(),"requires Edit")
local SES=game:GetService("ScriptEditorService")
local originals=''' + originals + '''
local function resolve(path)
 local s=game for name in path:gmatch("[^.]+") do s=assert(s:FindFirstChild(name),name) end return s
end
local function guard()
 for _,r in originals do local s=resolve(r.path) assert(s.Source==r.source and SES:GetEditorSource(s)==r.source,"original changed: "..r.path) end
end
local owned={} local rendererModule local compiled={}
local function stage(name,source)
 guard()
 local module=Instance.new("ModuleScript") table.insert(owned,module)
 module.Name=name module.Parent=game:GetService("ServerStorage")
 assert(module.Source=="" and SES:GetEditorSource(module)=="","fresh baseline not empty")
 SES:UpdateSourceAsync(module,function(current)
  guard() assert(current=="" and module.Source=="" and SES:GetEditorSource(module)=="","staging baseline changed") return source
 end)
 guard() assert(module.Source==source and SES:GetEditorSource(module)==source,"staging failed") return module
end
local ok,result=xpcall(function()
 for _,item in ''' + items + ''' do
  local source="return function()\\n"..item.source.."\\nend"
  local module=stage("StutterAssetsCompileProbe",source)
  assert(type(require(module))=="function","compile probe")
  table.insert(compiled,item.name)
  if item.name:find("BlenderRoomRenderer",1,true) then
   rendererModule=stage("StutterAssetsRendererCandidate",item.source)
  end
 end
 local probe=stage("StutterAssetsActualKitProbe",''' + luau_string(probe_source) + ''')
 local native=require(probe)(assert(rendererModule))
 return {compiled=compiled,renderer=native}
end,debug.traceback)
for _,module in owned do module:Destroy() end
guard()
assert(ok,result)
result.authoritativeSourcesPreserved=true result.probesDestroyed=true
return game:GetService("HttpService"):JSONEncode(result)
'''
checkpoint = ROOT / ".git/stutter-assets-20261009"
(checkpoint / "probe-candidates.luau").write_text(code, encoding="utf-8")
client = StudioMcpClient(find_mcp_batch())
try:
    client.initialize()
    studio = select_studio(client, RELEASE_STUDIO_NAME, 20)
    result = client.call("execute_luau", {"studio_id": studio["id"], "datamodel_type": "Edit", "code": code})
finally:
    client.close()
(ROOT / "artifacts/stutter-assets-20261009/native-candidate-probes.json").write_text(result + "\n", encoding="utf-8")
print(result)
