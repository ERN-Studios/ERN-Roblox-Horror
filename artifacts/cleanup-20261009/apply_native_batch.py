"""Install one reviewed source against exact live native/editor baselines.

No creation, deletion, property/attribute changes, publication or full sync.
The canonical mirror must contain the reviewed candidate. Native before-source
comes from this task's verified checkpoint and is rechecked inside the callback.
"""
from pathlib import Path
from datetime import datetime, timezone
import json
import sys

ROOT=Path(__file__).resolve().parents[2]
sys.path.insert(0,str(ROOT/"tools"))
from sync_from_studio import StudioMcpClient,find_mcp_batch,select_studio,RELEASE_STUDIO_NAME
from push_repo_to_studio import luau_string
from studio_source_contract import canonical_bytes,sha256_of,normalize

rel=sys.argv[1]; label=sys.argv[2]
checkpoint=ROOT/".git"/"mongotv-cleanup-20261009"
snapshot=json.loads((checkpoint/"baseline-native.json").read_text(encoding="utf-8"))
manifest_path=ROOT/"studio-sync-manifest.json"
manifest_before=manifest_path.read_bytes()
manifest=json.loads(manifest_before)
entry=next(i for i in manifest["items"] if i.get("file")==rel)
native=next(i for i in snapshot["items"] if i["studioPath"]==entry["studioPath"])
before=native["source"]
after=normalize((ROOT/rel).read_text(encoding="utf-8"))
assert before!=after,"no source change"
assert native["sourceEditorMatches"],"baseline editor conflict"
segments="{"+",".join(luau_string(s) for s in native["segments"])+"}"
checks=[]
attributes=native["attributes"]
if attributes==[] or attributes=={}:
 checks.append('assert(next(s:GetAttributes())==nil,"attributes changed")')
else:
 assert all(isinstance(v,(str,bool,int,float)) for v in attributes.values()),"unsupported typed attribute"
 checks.append(f'local attributes=s:GetAttributes() local count=0 for _ in attributes do count+=1 end assert(count=={len(attributes)},"attributes changed")')
 for key,value in attributes.items():
  encoded=luau_string(value) if isinstance(value,str) else str(value).lower()
  checks.append(f'assert(attributes[{luau_string(key)}]=={encoded},"attribute changed")')
for key,value in native["properties"].items():
 if key=="Enabled": continue
 encoded=luau_string(value) if isinstance(value,str) else str(value).lower()
 lhs=f"tostring(s.{key})" if key=="RunContext" else f"s.{key}"
 checks.append(f"assert({lhs}=={encoded}, {luau_string('changed property '+key)})")
code=f'''
assert(game.PlaceId==131311258779917 and game.GameId==10559217407,"wrong place")
assert(not game:GetService("RunService"):IsRunning(),"requires Edit")
local s=game
for _,name in {segments} do
 local found=nil
 for _,child in s:GetChildren() do
  if child.Name==name then assert(not found,"ambiguous path") found=child end
 end
 s=assert(found,"missing path")
end
assert(s.ClassName=={luau_string(native["className"])},"class changed")
local SES=game:GetService("ScriptEditorService")
local before={luau_string(before)} local after={luau_string(after)}
local function guard()
 {" ".join(checks)}
 assert(s.Source==before,"native Source changed")
 assert(SES:GetEditorSource(s)==before,"editor source changed")
end
guard()
SES:UpdateSourceAsync(s,function(current)
 guard()
 assert(current==before,"callback baseline changed")
 return after
end)
assert(s.Source==after,"native write failed")
assert(SES:GetEditorSource(s)==after,"editor write failed")
return game:GetService("HttpService"):JSONEncode({{path=s:GetFullName(),class=s.ClassName,bytes=#s.Source,editorMatches=true}})
'''
(checkpoint/f"{label}-install.luau").write_text(code,encoding="utf-8")
client=StudioMcpClient(find_mcp_batch())
try:
 client.initialize();studio=select_studio(client,RELEASE_STUDIO_NAME,15)
 result=json.loads(client.call("execute_luau",{"studio_id":studio["id"],"datamodel_type":"Edit","code":code}))
finally:client.close()
assert (ROOT/rel).read_text(encoding="utf-8")==after,"mirror changed during write"
assert manifest_path.read_bytes()==manifest_before,"manifest changed concurrently; reconcile separately"
entry["sha256"]=sha256_of(after);entry["bytes"]=len(canonical_bytes(after))
entry["status"]="synced";entry["sourceEditorMatches"]=True
manifest_path.write_text(json.dumps(manifest,ensure_ascii=False,indent=2)+"\n",encoding="utf-8")
result.update({"file":rel,"beforeSha256":sha256_of(before),"afterSha256":sha256_of(after),"capturedAtUtc":datetime.now(timezone.utc).isoformat(),"published":False})
(ROOT/"artifacts"/"cleanup-20261009"/f"{label}-native-install.json").write_text(json.dumps(result,indent=2)+"\n",encoding="utf-8")
print(json.dumps(result))
