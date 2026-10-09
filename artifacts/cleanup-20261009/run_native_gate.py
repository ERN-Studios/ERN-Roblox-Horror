"""Run one isolated review gate and persist its actual MCP response."""
from pathlib import Path
import json
import sys
from datetime import datetime, timezone
ROOT=Path(__file__).resolve().parents[2]
sys.path.insert(0,str(ROOT/"tools"))
from sync_from_studio import StudioMcpClient,find_mcp_batch,select_studio,RELEASE_STUDIO_NAME
from push_repo_to_studio import luau_string

name=sys.argv[1]
if name=="core024":
 code=(ROOT/"artifacts/cleanup-20261009/core024/native-fixture.luau").read_text(encoding="utf-8")
 mode="Edit"
elif name=="N01":
 source=(ROOT/".git/mongotv-cleanup-20261009/client-before/UIRegression.N01.probe.lua").read_text(encoding="utf-8")
 code=f'''local SES=game:GetService("ScriptEditorService") local HS=game:GetService("HttpService")
local RS=game:GetService("ReplicatedStorage") local live=RS:WaitForChild("UIRegression")
local before=live.Source
local function guard()
 assert(RS:FindFirstChild("UIRegression")==live,"original identity changed")
 assert(live.Source==before and SES:GetEditorSource(live)==before,"original source/editor changed")
end
local probe=nil
local candidate={luau_string(source)}
local ok,result=xpcall(function()
 guard()
 probe=Instance.new("ModuleScript") probe.Name="N01_Isolated_Probe"
 assert(probe.Source=="" and SES:GetEditorSource(probe)=="","new probe must start empty")
 SES:UpdateSourceAsync(probe,function(current)
  guard()
  assert(current=="" and probe.Source=="" and SES:GetEditorSource(probe)=="","staging baseline changed")
  return candidate
 end)
 guard()
 assert(probe.Source==candidate and SES:GetEditorSource(probe)==candidate,"probe stage failed")
 local report,failed,measurements=require(probe).CleanupSharedHudProbe()
 local rows=HS:JSONDecode(measurements) local selected={{}}
 for _,row in rows do
  if row.Level==1 then table.insert(selected,row) end
 end
 return {{report=report,failed=failed,rows=selected,totalRows=#rows}}
end,debug.traceback)
local destroyed,cleanupError=pcall(function() if probe then probe:Destroy() end end)
local stable,guardError=pcall(guard)
local errors={{}}
if not ok then table.insert(errors,tostring(result)) end
if not destroyed then table.insert(errors,"probe cleanup failed: "..tostring(cleanupError)) end
if not stable then table.insert(errors,"final original guard failed: "..tostring(guardError)) end
if #errors>0 then error(table.concat(errors,"\\n"),0) end
return HS:JSONEncode(result)'''
 mode="Client"
else: raise SystemExit("unknown gate")
attempt=datetime.now(timezone.utc).strftime("%Y%m%dT%H%M%S%fZ")
checkpoint=ROOT/".git/mongotv-cleanup-20261009"
(checkpoint/f"{name}-{attempt}-gate.luau").write_text(code,encoding="utf-8")
client=StudioMcpClient(find_mcp_batch())
try:
 client.initialize();studio=select_studio(client,RELEASE_STUDIO_NAME,15)
 result=client.call("execute_luau",{"studio_id":studio["id"],"datamodel_type":mode,"code":code})
finally:client.close()
out=ROOT/"artifacts/cleanup-20261009"/f"{name}-native-gate.json"
out.write_text(result+"\n",encoding="utf-8")
(checkpoint/f"{name}-{attempt}-result.json").write_text(result+"\n",encoding="utf-8")
data=json.loads(result)
print(json.dumps({k:v for k,v in data.items() if k not in {"rows","report"}}))
