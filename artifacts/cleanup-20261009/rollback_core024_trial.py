"""Exact guarded recovery of the failed cloned-script staging trial."""
from pathlib import Path
import json
import sys
ROOT=Path(__file__).resolve().parents[2]
sys.path.insert(0,str(ROOT/"tools"))
from sync_from_studio import StudioMcpClient,find_mcp_batch,select_studio,RELEASE_STUDIO_NAME
from push_repo_to_studio import luau_string
snapshot=json.loads((ROOT/".git/mongotv-cleanup-20261009/baseline-native.json").read_text(encoding="utf-8"))
native=next(i for i in snapshot["items"] if i["studioPath"]=="ServerScriptService.LobbyReimaginedPreview.EndBlockades")
before=native["source"]
candidate=(ROOT/"artifacts/cleanup-20261009/core024/EndBlockades.candidate.luau").read_text(encoding="utf-8")
code=f'''assert(game.PlaceId==131311258779917 and game.GameId==10559217407,"wrong place")
local s=game.ServerScriptService.LobbyReimaginedPreview.EndBlockades
local SES=game:GetService("ScriptEditorService") local ENC=game:GetService("EncodingService")
local before={luau_string(before)} local candidate={luau_string(candidate)}
assert(s.ClassName=="ModuleScript" and s.Source==candidate and SES:GetEditorSource(s)==candidate,"unexpected live state; preserve and reconcile")
SES:UpdateSourceAsync(s,function(current)
 assert(current==candidate and s.Source==candidate and SES:GetEditorSource(s)==candidate,"changed during rollback")
 return before
end)
assert(s.Source==before and SES:GetEditorSource(s)==before,"rollback source/editor failed")
local b=ENC:ComputeBufferHash(buffer.fromstring(s.Source),Enum.HashAlgorithm.Sha256) local a={{}}
for i=0,buffer.len(b)-1 do a[#a+1]=string.format("%02x",buffer.readu8(b,i)) end
return game.HttpService:JSONEncode({{rolledBack=true,sourceEditorMatches=true,sha256=table.concat(a),path=s:GetFullName(),published=false}})'''
client=StudioMcpClient(find_mcp_batch())
try:
 client.initialize();studio=select_studio(client,RELEASE_STUDIO_NAME,15)
 result=client.call("execute_luau",{"studio_id":studio["id"],"datamodel_type":"Edit","code":code})
finally:client.close()
(ROOT/"artifacts/cleanup-20261009/core024-trial-rollback.json").write_text(result+"\n",encoding="utf-8")
print(result)
