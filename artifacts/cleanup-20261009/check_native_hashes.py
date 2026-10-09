"""Bounded read-only native SHA256/editor check against the current manifest."""
from pathlib import Path
import json
import sys
ROOT=Path(__file__).resolve().parents[2]
sys.path.insert(0,str(ROOT/"tools"))
from sync_from_studio import StudioMcpClient,find_mcp_batch,select_studio,RELEASE_STUDIO_NAME
from push_repo_to_studio import luau_string
manifest=json.loads((ROOT/"studio-sync-manifest.json").read_text(encoding="utf-8"))
expected="{"+",".join("["+luau_string(i["studioPath"])+"]="+luau_string(i["sha256"]) for i in manifest["items"] if i["className"] in {"Script","LocalScript","ModuleScript"})+"}"
code=f'''assert(game.PlaceId==131311258779917 and game.GameId==10559217407,"wrong place")
local expected={expected} local ENC=game:GetService("EncodingService") local SES=game:GetService("ScriptEditorService")
local rows={{}} local count=0
for _,s in game:GetDescendants() do
 if s:IsA("LuaSourceContainer") then
  count+=1 local body=s.Source:gsub("\\r\\n","\\n")
  local b=ENC:ComputeBufferHash(buffer.fromstring(body),Enum.HashAlgorithm.Sha256) local a={{}}
  for i=0,buffer.len(b)-1 do a[#a+1]=string.format("%02x",buffer.readu8(b,i)) end
  local path=s:GetFullName() local hash=table.concat(a)
  if expected[path]~=hash or SES:GetEditorSource(s)~=s.Source then
   table.insert(rows,{{path=path,expected=expected[path],actual=hash,editorMatches=SES:GetEditorSource(s)==s.Source}})
  end
  expected[path]=nil
 end
end
for path,hash in expected do table.insert(rows,{{path=path,missing=true,expected=hash}}) end
return game.HttpService:JSONEncode({{scripts=count,failures=rows}})'''
client=StudioMcpClient(find_mcp_batch())
try:
 client.initialize();studio=select_studio(client,RELEASE_STUDIO_NAME,15)
 result=client.call("execute_luau",{"studio_id":studio["id"],"datamodel_type":"Edit","code":code})
finally:client.close()
label=sys.argv[1] if len(sys.argv)>1 else "current"
(ROOT/"artifacts/cleanup-20261009"/f"{label}-native-hashes.json").write_text(result+"\n",encoding="utf-8")
data=json.loads(result);print(result);sys.exit(bool(data["failures"]))
