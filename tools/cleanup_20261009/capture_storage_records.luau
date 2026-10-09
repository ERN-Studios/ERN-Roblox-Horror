-- Native diagnostic-data backup only; never changes persistent objects/settings.
local HS=game:GetService("HttpService")
local ENC=game:GetService("EncodingService")
local SER=game:GetService("SerializationService")
local SES=game:GetService("ScriptEditorService")
local RS=game:GetService("RunService")
local SS=game:GetService("ServerStorage")
local BASE="http://127.0.0.1:18913"
local KEY="__MongoTVStorageCleanup20261009"
local names={
 "TEMP_PipeEntityLobbyRigResult_0748Z","TEMP_PipeEntityMPResult_0457Z",
 "TEMP_PipeEntityMPResult_0503Z","TEMP_PipeEntityMPResult_0508Z",
 "TEMP_PipeEntityMPResult_0638Z","TEMP_PipeEntityMPResult_0706Z",
 "TEMP_PipeEntityMPResult_1609Z","TEMP_PipeEntityMPResult_1624Z",
 "TEMP_PipeEntityMPResult_1633Z","TEMP_PipeEntityMPResult_1640Z",
 "TEMP_PipeEntityMPResult_1648Z","TEMP_PipeEntityMultiplayerLaunch",
}
assert(game.PlaceId==131311258779917 and game.GameId==10559217407,"wrong place")
assert(not RS:IsRunning() and HS.HttpEnabled,"Edit/existing HTTP required")
assert(shared[KEY]==nil,"owned prior capture must be released explicitly")
local function sha(raw)
 local d=ENC:ComputeBufferHash(raw,Enum.HashAlgorithm.Sha256)
 local h={} for i=0,buffer.len(d)-1 do h[i+1]=string.format("%02x",buffer.readu8(d,i)) end
 return table.concat(h)
end
local function typed(value)
 local kind=typeof(value)
 assert(kind=="string" or kind=="number" or kind=="boolean","unexpected diagnostic attribute type: "..kind)
 return {type=kind,value=value}
end
local function facts(f)
 local attrs={} for k,v in f:GetAttributes() do attrs[k]=typed(v) end
 local tags=f:GetTags() table.sort(tags)
 return {name=f.Name,class=f.ClassName,archivable=f.Archivable,
  tags=tags,attributes=attrs,children=#f:GetChildren(),
  properties={Sandboxed=f.Sandboxed,IconTint={f.IconTint.R,f.IconTint.G,f.IconTint.B},
   Capabilities=tostring(f.Capabilities)}}
end
local function same(a,b)
 if typeof(a)~=typeof(b) then return false end
 if typeof(a)~="table" then return a==b end
 for k,v in a do if not same(v,b[k]) then return false end end
 for k in b do if a[k]==nil then return false end end
 return true
end
local function postParts(kind,raw)
 local count=math.ceil(#raw/750000)
 for i=0,count-1 do
  assert(HS:PostAsync(BASE.."/"..kind.."/"..i,string.sub(raw,i*750000+1,(i+1)*750000),Enum.HttpContentType.TextPlain)=="saved","archive receiver failed")
 end
 return {parts=count,bytes=#raw,sha256=sha(buffer.fromstring(raw))}
end
local roots,records,rootRefs,scriptRefs,sourceRecords={},{},{},{},{}
local lease={phase="capture"}
shared[KEY]=lease -- Reserve before any HTTP/serialization yield.
local epoch=0
local ownedConnections={}
local function sourceTreeChanged(s)
 if s:IsA("LuaSourceContainer") then epoch+=1 end
end
local function guardCaptured()
 assert(shared[KEY]==lease and not RS:IsRunning(),"capture lease/mode changed")
 local seenRoots={}
 for _,r in SS:GetChildren() do
  local row=assert(rootRefs[r],"new unrelated root during capture")
  assert(r.Name==row.name and r.ClassName==row.class,"root identity changed during capture")
  seenRoots[r]=true
 end
 for r in rootRefs do assert(seenRoots[r] and r.Parent==SS,"root removed/moved during capture") end
 local seenSources={}
 for i,s in game:GetDescendants() do
  if s:IsA("LuaSourceContainer") then
   assert(scriptRefs[s],"new source during capture") seenSources[s]=true
  end
  if i%1000==0 then task.wait() end
 end
 for s,row in scriptRefs do
  assert(seenSources[s] and s.Parent and s:GetFullName()==row.path and s.ClassName==row.class and s.Source==row.source and SES:GetEditorSource(s)==row.source,"concurrent original source edit during capture: "..row.path)
  assert(s.Archivable==row.properties.Archivable and tostring(s.LinkedSource)==row.properties.LinkedSource and same(s:GetAttributes(),row.attributes),"original script properties/attributes changed during capture")
  if s:IsA("BaseScript") then
   assert(s.Enabled==row.properties.Enabled and s.Disabled==row.properties.Disabled and tostring(s.RunContext)==row.properties.RunContext,"BaseScript properties changed during capture")
  end
 end
 for i,r in roots do assert(r.Parent==SS and same(facts(r),records[i]),"candidate changed during capture") end
 assert(epoch==0,"script/root set changed during yielding capture census")
 assert(shared[KEY]==lease and not RS:IsRunning(),"capture lease/mode changed after census")
end
local completedState
local ok,result=xpcall(function()
 table.insert(ownedConnections,game.DescendantAdded:Connect(sourceTreeChanged))
 table.insert(ownedConnections,game.DescendantRemoving:Connect(sourceTreeChanged))
 table.insert(ownedConnections,SS.ChildAdded:Connect(function() epoch+=1 end))
 table.insert(ownedConnections,SS.ChildRemoved:Connect(function() epoch+=1 end))
 assert(HS:JSONDecode(HS:GetAsync(BASE.."/context",true)).schema=="folder-diagnostic-archive-v1","wrong receiver")
 for _,name in names do
  local found={}
  for _,f in SS:GetChildren() do if f.Name==name then table.insert(found,f) end end
  assert(#found==1,"missing/duplicate diagnostic root: "..name)
  local f=found[1]
  assert(f.ClassName=="Folder" and #f:GetChildren()==0 and f.Archivable,"unexpected diagnostic object")
  table.insert(roots,f) table.insert(records,facts(f))
 end
 for _,r in SS:GetChildren() do rootRefs[r]={name=r.Name,class=r.ClassName} end
 local target={} for _,r in roots do target[r]=true end
 local refs={}
 for i,s in game:GetDescendants() do
  if s:IsA("ObjectValue") and target[s.Value] then table.insert(refs,s:GetFullName()) end
  if s:IsA("LuaSourceContainer") then
   assert(SES:GetEditorSource(s)==s.Source,"original Source/editor conflict")
   local p={Archivable=s.Archivable,LinkedSource=tostring(s.LinkedSource)}
   if s:IsA("BaseScript") then p.Enabled=s.Enabled p.Disabled=s.Disabled p.RunContext=tostring(s.RunContext) end
   local row={path=s:GetFullName(),class=s.ClassName,source=s.Source,properties=p,attributes=s:GetAttributes()}
   scriptRefs[s]=row
   table.insert(sourceRecords,{path=row.path,class=row.class,sourceSHA256=sha(buffer.fromstring(row.source)),properties=p,attributes=row.attributes})
  end
  if i%1000==0 then task.wait() end
 end
 assert(#refs==0,"diagnostic root has inbound ObjectValue reference")
 local native=SER:SerializeInstancesAsync(roots)
 local referenceRoots=table.clone(roots) table.insert(referenceRoots,game:GetService("StarterPlayer"))
 local references=SER:SerializeInstancesAsync(referenceRoots)
 guardCaptured()
 table.sort(sourceRecords,function(a,b) return a.path<b.path end)
 local archive={schema="folder-diagnostic-archive-v1",placeId=game.PlaceId,universeId=game.GameId,
  capturedAtUtc=DateTime.now():ToIsoDate(),nativeBytes=buffer.len(native),nativeSHA256=sha(native),
  roots=records,sourceInventory=sourceRecords,inboundObjectValues=refs,
  referencesSHA256=sha(references),referencesBytes=buffer.len(references),referenceRootCount=#referenceRoots,
  rootCountBefore=(function() local n=0 for _ in rootRefs do n+=1 end return n end)(),noPersistentMutation=true,
  deletionApproved=false,referenceProofScope="captured joint forest only; fresh property-only reference guard required before any removal"}
 local transfer={native=postParts("native",buffer.tostring(native)),references=postParts("references",buffer.tostring(references)),facts=postParts("facts",HS:JSONEncode(archive))}
 assert(HS:PostAsync(BASE.."/finalize",HS:JSONEncode(transfer),Enum.HttpContentType.ApplicationJson)=="saved","archive not finalized")
 guardCaptured() -- HTTP transfer yields too; a saved archive alone cannot bless stale state.
 completedState={roots=roots,facts=records,rootRefs=rootRefs,scriptRefs=scriptRefs,same=same,factsOf=facts,
  nativeSHA256=archive.nativeSHA256,referencesSHA256=archive.referencesSHA256,rootCountBefore=archive.rootCountBefore,
  deletionApproved=false,completed={},captureAtUtc=archive.capturedAtUtc}
 return {roots=#roots,nativeBytes=archive.nativeBytes,nativeSHA256=archive.nativeSHA256,scriptCount=#sourceRecords,rootCountBefore=archive.rootCountBefore}
end,debug.traceback)
for _,connection in ownedConnections do
 local clean,why=pcall(function() connection:Disconnect() end)
 if not clean then ok=false result=tostring(result).."\ncapture watcher cleanup failed: "..tostring(why) end
end
if ok and shared[KEY]~=lease then ok=false result="capture lease changed during watcher cleanup" end
if not ok then if shared[KEY]==lease then shared[KEY]=nil end error(result) end
shared[KEY]=completedState
return HS:JSONEncode(result)
