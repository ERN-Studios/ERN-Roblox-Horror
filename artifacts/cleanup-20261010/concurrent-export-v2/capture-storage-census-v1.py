from pathlib import Path
import importlib.util,json,sys,hashlib
HERE=Path(__file__).resolve().parent
ROOT=HERE.parents[2]
sys.dont_write_bytecode=True
sys.path.insert(0,str(ROOT/'tools'))
from sync_from_studio import StudioMcpClient,find_mcp_batch,require_edit_state
SID='1b603e69-7ae1-4572-b210-d5bf05c684ff'
spec=importlib.util.spec_from_file_location('reader',HERE/'after/parity-reader.py');reader=importlib.util.module_from_spec(spec);spec.loader.exec_module(reader)
code=reader.CODE+r'''
local _, before=catalog()
local S=game:GetService("ServerStorage")
local roots={}
for _,n in S:GetChildren() do
 local descendants=n:GetDescendants()
 local scripts=0
 for i,d in descendants do
  if d:IsA("LuaSourceContainer") then scripts+=1 end
  if i%10000==0 then task.wait();mode() end
 end
 roots[#roots+1]={name=n.Name,className=n.ClassName,instanceId=n:GetDebugId(16),
 parentId=n.Parent:GetDebugId(16),nodeCount=#descendants+1,descendantScriptCount=scripts,
 attributes=n:GetAttributes(),tags=n:GetTags(),archivable=n.Archivable}
end
table.sort(roots,function(a,b)return a.name<b.name end)
local _,after=catalog()
assert(before.catalogSHA256==after.catalogSHA256 and #roots==before.serverStorageRootCount)
return H:JSONEncode({pass=true,nativeWrites=0,modeSwitches=0,before=before,after=after,roots=roots,
limits="Readonly root facts; not full asset/ref properties or deletion approval"})
'''
def save(name,raw):
 with (HERE/name).open('xb') as f:assert f.write(raw)==len(raw)
save('storage-census-read-v1.luau',code.encode())
client=StudioMcpClient(find_mcp_batch())
try:
 client.initialize();require_edit_state(client,SID)
 raw=client.call('execute_luau',{'studio_id':SID,'datamodel_type':'Edit','code':code})
 assert len(raw.encode())<50000
 result=json.loads(raw);assert result['pass'] is True
 save('storage-census-v1.json',(json.dumps(result,indent=2)+'\n').encode())
 print(json.dumps({'pass':True,'roots':len(result['roots']),'catalogSHA256':result['after']['catalogSHA256'],'nativeWrites':0}))
finally:client.close()
