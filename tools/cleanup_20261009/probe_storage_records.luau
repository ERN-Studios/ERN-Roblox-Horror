-- Archive/reconstruction/reference port. All created instances are unparented and test-owned.
local HS=game:GetService("HttpService")
local SS=game:GetService("ServerStorage")
local RS=game:GetService("RunService")
local SES=game:GetService("ScriptEditorService")
local REF=game:GetService("ReflectionService")
local CAPS=SecurityCapabilities.new(table.unpack(Enum.SecurityCapability:GetEnumItems()))
local KEY="__MongoTVStorageCleanup20261009"
assert(game.PlaceId==131311258779917 and game.GameId==10559217407 and not RS:IsRunning(),"wrong place/mode")
local state=assert(shared[KEY],"no exact captured originals")
assert(state.roots and not state.probeLease and not state.portLease,"capture/probe/port already in progress")
assert(not state.storagePort or next(state.storagePort.removed)==nil,"initial reconstruction probe cannot rerun after records were removed")
local lease={} state.probeLease=lease
state.nativeProbePass=false
state.deletionApproved=false
local copies,report={},{schema="storage-diagnostic-native-port-v1",checks=0,inboundReferences={},readErrors={},selectedTargets={},classes=0,referenceProperties=0,editorMetadataExceptions={},nonserializedReadExceptions={},serializedArchiveReferenceChecks={},deletionApproved=false,
 limits="Unparented Folder reconstruction/readable references only. Protected nonserialized authoring holders remain opaque; joint reference guard must be refreshed immediately before any removal."}
-- Refresh unrelated developer state read-only. Archive facts/CAS for targets stay fixed.
-- The write port must compare this fresh invocation baseline after its final yield.
local prior=state.scriptRefs
local sourceRefs,rootRefs={},{}
local ownedConnections={}
local epoch=0
report.concurrentArchiveSourceChanges={}
local rootCountBefore=0
local function check(value,message)
 assert(value,message) report.checks+=1
end
local function originals()
 check(shared[KEY]==state and state.probeLease==lease,"probe lease changed")
 check(epoch==0,"source/root set changed during yielding probe")
 for i,f in state.roots do
  check(f.Parent==SS and state.same(state.factsOf(f),state.facts[i]),"original changed since archive")
 end
 for f,p in rootRefs do check(f.Parent==SS and f.Name==p.name and f.ClassName==p.class,"unrelated root changed during port") end
 check(#SS:GetChildren()==rootCountBefore,"root inventory changed during port")
 for s,row in sourceRefs do
  check(s.Parent and s:GetFullName()==row.path and s.ClassName==row.class and s.Source==row.source and SES:GetEditorSource(s)==row.source,"authoritative original source changed")
  check(s.Archivable==row.properties.Archivable and tostring(s.LinkedSource)==row.properties.LinkedSource and state.same(s:GetAttributes(),row.attributes),"original properties/attributes changed")
  if s:IsA("BaseScript") then
   check(s.Enabled==row.properties.Enabled and s.Disabled==row.properties.Disabled and tostring(s.RunContext)==row.properties.RunContext,"original BaseScript properties changed")
  end
 end
end
local ok,err=xpcall(function()
 local function sourceTreeChanged(s) if s:IsA("LuaSourceContainer") then epoch+=1 end end
 table.insert(ownedConnections,game.DescendantAdded:Connect(sourceTreeChanged))
 table.insert(ownedConnections,game.DescendantRemoving:Connect(sourceTreeChanged))
 table.insert(ownedConnections,SS.ChildAdded:Connect(function() epoch+=1 end))
 table.insert(ownedConnections,SS.ChildRemoved:Connect(function() epoch+=1 end))
 for _,f in SS:GetChildren() do rootRefs[f]={name=f.Name,class=f.ClassName} rootCountBefore+=1 end
 for i,s in game:GetDescendants() do
  if s:IsA("LuaSourceContainer") then
   local p={Archivable=s.Archivable,LinkedSource=tostring(s.LinkedSource)}
   if s:IsA("BaseScript") then p.Enabled=s.Enabled p.Disabled=s.Disabled p.RunContext=tostring(s.RunContext) end
   local row={path=s:GetFullName(),class=s.ClassName,source=s.Source,properties=p,attributes=s:GetAttributes()}
   sourceRefs[s]=row
   if not prior[s] or prior[s].source~=row.source or prior[s].path~=row.path or not state.same(prior[s].properties,p) or not state.same(prior[s].attributes,row.attributes) then
    table.insert(report.concurrentArchiveSourceChanges,{path=row.path,priorPath=prior[s] and prior[s].path or nil,kind=if prior[s] then "changed-or-moved" else "added"})
   end
  end
  if i%1000==0 then task.wait() end
 end
 for s,row in prior do if not sourceRefs[s] then table.insert(report.concurrentArchiveSourceChanges,{path=row.path,kind="removed"}) end end
 originals()
 local targets={} for _,f in state.roots do targets[f]=true end
 for _,s in game:GetService("Selection"):Get() do if targets[s] then table.insert(report.selectedTargets,s.Name) end end
 local classes={}
 for i,s in game:GetDescendants() do
  local props=classes[s.ClassName]
  if not props then
   props={}
   local reflected=REF:GetPropertiesOfClass(s.ClassName,{Security=CAPS,ExcludeInherited=false,ExcludeDisplay=true})
   if reflected==nil then
    check(s.ClassName=="" and s.Name=="FilteredSelection" and s.Parent==game,"unreflected place object")
    table.insert(report.editorMetadataExceptions,{class=s.ClassName,name=s.Name,reason="transient editor filtered selection; Selection:Get() checked separately"})
    reflected=REF:GetPropertiesOfClass("Instance",{Security=CAPS,ExcludeInherited=false,ExcludeDisplay=true})
   end
   for _,p in reflected do
    if p.Type.ScriptType=="Instance" then table.insert(props,p) end
   end
   classes[s.ClassName]=props report.classes+=1
  end
  for _,p in props do
   local read,value=pcall(function() return s[p.Name] end)
   report.referenceProperties+=1
   if read then
    if targets[value] then table.insert(report.inboundReferences,{path=s:GetFullName(),property=p.Name,target=value.Name}) end
   elseif p.Type.InstanceType=="Instance" or p.Type.InstanceType=="Folder" or p.Type.InstanceType=="Object" then
    local row={path=s:GetFullName(),property=p.Name,type=p.Type.InstanceType,error=tostring(value),serialized=p.Serialized}
    if p.Serialized==false and ((s.ClassName=="GuiService" and (p.Name=="CoreEffectFolder" or p.Name=="CoreGuiFolder"))
      or (s.ClassName=="Selection" and p.Name=="ActiveInstance")
      or (s.ClassName=="StudioService" and p.Name=="HoverInstance")
      or (s.ClassName=="Player" and p.Name=="PendingRequestedTool")) then
     row.reason="protected nonserialized engine/editor holder; current Selection checked separately; pointer itself remains unreadable and does not approve deletion"
     table.insert(report.nonserializedReadExceptions,row)
    elseif s==game:GetService("StarterPlayer") and p.Name=="PlaceAvatarRules" and p.Serialized==true then
     row.reason="capture-time joint archive only; fresh same-epoch reference guard still required before removal"
     table.insert(report.serializedArchiveReferenceChecks,row)
    else table.insert(report.readErrors,row) end
   end
  end
  if i%1000==0 then task.wait() end
 end
 check(#report.inboundReferences==0,"inbound native Instance property reference")
 check(#report.readErrors==0,"unreadable Folder-compatible reference property")
 check(#report.selectedTargets==0,"selected diagnostic target; preserve authoring selection")
 local seen={}
 for i,s in game:GetDescendants() do
  if s:IsA("LuaSourceContainer") then check(sourceRefs[s]~=nil,"new script during probe") seen[s]=true end
  if i%1000==0 then task.wait() end
 end
 for s in sourceRefs do check(seen[s],"script removed during probe") end
 for i,record in state.facts do
  local f=Instance.new("Folder") table.insert(copies,f)
  check(f.Parent==nil and #f:GetChildren()==0,"fresh unparented Folder baseline")
  f.Name=record.name f.Archivable=record.archivable
  for k,v in record.attributes do
   check(typeof(v.value)==v.type,"typed diagnostic data mismatch") f:SetAttribute(k,v.value)
  end
  for _,tag in record.tags do f:AddTag(tag) end
  check(state.same(state.factsOf(f),record),"native reconstruction differs from complete readable facts")
  check(f.Parent==nil and #f:GetChildren()==0,"probe escaped ownership")
 end
 originals()
 check(not RS:IsRunning(),"mode changed during probe")
end,debug.traceback)
local destroyed=0
for _,f in copies do
 local clean,why=pcall(function() f:Destroy() end)
 if clean then destroyed+=1 else ok=false err=tostring(err).."\nprobe cleanup failed: "..tostring(why) end
end
local final,why=pcall(originals)
if not final then ok=false err=tostring(err).."\nfinal originals check: "..tostring(why) end
for _,connection in ownedConnections do
 local clean,reason=pcall(function() connection:Disconnect() end)
 if not clean then ok=false err=tostring(err).."\nprobe watcher cleanup failed: "..tostring(reason) end
end
report.pass=ok report.error=if ok then nil else tostring(err)
report.created=#copies report.destroyed=destroyed
report.capturedAtUtc=DateTime.now():ToIsoDate()
state.nativeProbePass=ok state.nativeProbeReport=report
if state.probeLease==lease then state.probeLease=nil end
return HS:JSONEncode(report)
