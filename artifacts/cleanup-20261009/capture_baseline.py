"""Read-only native Studio snapshot and exact mirror comparison for cleanup.

Native sources and the pre-existing dirty checkpoint stay under .git, outside
the tracked mirror. Reviewed hashes, properties and verdicts are JSON evidence.
"""
from pathlib import Path
import hashlib
import json
import subprocess
import sys
from datetime import datetime, timezone

ROOT = Path(__file__).resolve().parents[2]
sys.path.insert(0, str(ROOT / "tools"))
from sync_from_studio import StudioMcpClient, find_mcp_batch, select_studio, RELEASE_STUDIO_NAME
from studio_source_contract import normalize, classify, permits_trailing_newline

LUA = r'''
assert(game.PlaceId == 131311258779917 and game.GameId == 10559217407, "wrong place")
local SES=game:GetService("ScriptEditorService")
local out={placeId=game.PlaceId,universeId=game.GameId,placeVersion=game.PlaceVersion,items={}}
for i,s in game:GetDescendants() do
 if s:IsA("LuaSourceContainer") or s:IsA("RemoteEvent") then
  local seg={} local c=s
  while c and c~=game do table.insert(seg,1,c.Name) c=c.Parent end
  local p={Archivable=s.Archivable}
  local item={studioPath=s:GetFullName(),segments=seg,className=s.ClassName,properties=p,attributes=s:GetAttributes()}
  if s:IsA("LuaSourceContainer") then
   item.sourceBytes=#s.Source
   local ok,e=pcall(function() return SES:GetEditorSource(s) end)
   item.sourceEditorMatches=ok and e==s.Source
   if not item.sourceEditorMatches then item.editorSource=ok and e or tostring(e) end
   p.LinkedSource=tostring(s.LinkedSource)
  end
  if s:IsA("BaseScript") then p.Disabled=s.Disabled p.Enabled=s.Enabled p.RunContext=tostring(s.RunContext) end
  table.insert(out.items,item)
 end
 if i%1000==0 then task.wait() end
end
table.sort(out.items,function(a,b) return a.studioPath<b.studioPath end)
return game:GetService("HttpService"):JSONEncode(out)
'''

def main():
 label=sys.argv[1] if len(sys.argv)>1 else "baseline"
 checkpoint=ROOT/".git"/"mongotv-cleanup-20261009"
 checkpoint.mkdir(exist_ok=True)
 if not (checkpoint/"preexisting.patch").exists():
  (checkpoint/"preexisting.patch").write_bytes(subprocess.check_output(["git","diff","--binary"],cwd=ROOT))
  (checkpoint/"status-before.txt").write_bytes(subprocess.check_output(["git","status","--porcelain=v1"],cwd=ROOT))
  for rel in ["studio-sync-manifest.json","StarterPlayer/StarterPlayerScripts/RoundUI.LocalScript.lua"]:
   dst=checkpoint/"preexisting"/rel; dst.parent.mkdir(parents=True,exist_ok=True); dst.write_bytes((ROOT/rel).read_bytes())
 client=StudioMcpClient(find_mcp_batch())
 try:
  client.initialize()
  studio=select_studio(client,RELEASE_STUDIO_NAME,15)
  state=client.call("get_studio_state",{"studio_id":studio["id"]})
  if "Current Studio Mode: Edit" not in state: raise RuntimeError("capture requires Edit")
  data=json.loads(client.call("execute_luau",{"studio_id":studio["id"],"datamodel_type":"Edit","code":LUA}))
  for item in data["items"]:
   if "sourceBytes" not in item: continue
   chunks=[]; start=1
   while start<=item["sourceBytes"]:
    segments="{"+",".join(json.dumps(s,ensure_ascii=False) for s in item["segments"])+"}"
    code=f'''local s=game for _,n in {segments} do s=assert(s:FindFirstChild(n),n) end
local src=s.Source assert(#src=={item["sourceBytes"]},"source changed")
local last=math.min({start}+23999,#src)
while last<#src and string.byte(src,last+1)>=128 and string.byte(src,last+1)<192 do last-=1 end
return game:GetService("HttpService"):JSONEncode({{text=string.sub(src,{start},last),last=last}})'''
    chunk=json.loads(client.call("execute_luau",{"studio_id":studio["id"],"datamodel_type":"Edit","code":code}))
    chunks.append(chunk["text"]); start=chunk["last"]+1
   item["source"]="".join(chunks)
  # Recheck metadata after export; candidate writes also compare exact fresh bytes.
  latest=json.loads(client.call("execute_luau",{"studio_id":studio["id"],"datamodel_type":"Edit","code":LUA}))
  if latest!=dict(data,items=[{k:v for k,v in x.items() if k!="source"} for x in data["items"]]):
   raise RuntimeError("native metadata changed during export; rerun snapshot")
 finally: client.close()
 data["capturedAtUtc"]=datetime.now(timezone.utc).isoformat()
 (checkpoint/f"{label}-native.json").write_text(json.dumps(data,ensure_ascii=False),encoding="utf-8")
 manifest=json.loads((ROOT/"studio-sync-manifest.json").read_text(encoding="utf-8"))
 bypath={i["studioPath"]:i for i in manifest["items"]}
 nativepaths=set(); failures=[]; conflicts=[]
 for item in data["items"]:
  nativepaths.add(item["studioPath"])
  old=bypath.get(item["studioPath"])
  source=item.pop("source",None)
  if source is None: continue
  item["nativeSha256"]=hashlib.sha256(normalize(source).encode()).hexdigest()
  if not item["sourceEditorMatches"]: conflicts.append(item["studioPath"])
  if old is None: failures.append({"path":item["studioPath"],"reason":"not in manifest"}); continue
  item["file"]=old["file"]
  path=ROOT/old["file"]
  repo=normalize(path.read_text(encoding="utf-8")) if path.exists() else ""
  item["repoSha256"]=hashlib.sha256(repo.encode()).hexdigest()
  item["verdict"]=classify(repo,source,allow_trailing_newline=permits_trailing_newline(old))
  issues=[]
  if item["verdict"]=="drifted": issues.append("source drift")
  if old["sha256"]!=item["repoSha256"]: issues.append("manifest hash")
  if old["className"]!=item["className"]: issues.append("class")
  for key,value in old.get("properties",{}).items():
   if item["properties"].get(key)!=value: issues.append("property "+key)
  if old.get("attributes",[])!=item["attributes"]: issues.append("attributes")
  if issues: failures.append({"path":item["studioPath"],"reason":issues})
 for path in sorted(set(bypath)-nativepaths): failures.append({"path":path,"reason":"manifest-only"})
 data["failures"]=failures; data["editorConflicts"]=conflicts
 data["counts"]={"scripts":sum(i["className"] in {"Script","LocalScript","ModuleScript"} for i in data["items"]),"remoteEvents":sum(i["className"]=="RemoteEvent" for i in data["items"])}
 out=ROOT/"artifacts"/"cleanup-20261009"/f"{label}-parity.json"
 out.write_text(json.dumps(data,ensure_ascii=False,indent=2)+"\n",encoding="utf-8")
 print(json.dumps({"label":label,"placeId":data["placeId"],"counts":data["counts"],"failures":failures,"editorConflicts":conflicts}))
 if failures or conflicts: sys.exit(1)

if __name__=="__main__": main()
