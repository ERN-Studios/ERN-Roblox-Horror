-- READONLY first archive frontier only; existing prefix helpers are local and
-- no shared collector state is acquired. No original/probe/setter/require/upload.
local report={schema="mongotv-animation-archive-reference-frontier-v1",passed=false,
 nativeInstanceWrites=0,nativeSourceWrites=0,nativePropertyWrites=0,collectorStateWrites=0,modeSwitches=0,
 deletionApproved=false,fullNativeArchiveCertified=false,referenceAbsenceCertified=false}
local original
local readSlot
local function checkedMetadata(s)
 guardSources(s) rootGuard(s)
 for _,ref in s.cacheRecords do
  assert(ref.node:IsDescendantOf(game) and canonical(metadata(ref.node))==canonical(ref.row),"Pinned actual cache record changed")
 end
 if s.slots then for _,ref in s.slots do
  assert(canonical(readSlot(ref.node,ref.row.name))==canonical(ref.row),"Reference frontier slot/readability changed")
 end end
end
local function resolveChild(parent,id)
 local found
 for _,child in parent:GetChildren() do if child:GetDebugId(16)==id then assert(not found,"Duplicate native identity")found=child end end
 return assert(found,"Exact native child identity missing")
end
local ok,why=xpcall(function()
 mode()
 local refs,sourceHash=sourceCatalog()
 assert(sourceHash==P.expectedSourceCatalogSHA256,"Actual inventory Source epoch changed")
 original={sources=refs,roots={},cacheRecords={}}
 for _,pin in P.roots do
  local root=uniqueRoot(pin.name,pin.className,pin.childCount)
  assert(canonical(header(root))==canonical(pin),"Actual inventory root identity/header changed")
  original.roots[#original.roots+1]={node=root,header=pin}
 end
 local rootIndex={} local targets={} local wanted={}
 for _,pin in P.records do assert(not wanted[pin.instanceId],"Duplicate inventory identity")wanted[pin.instanceId]=pin end
 local function discoverPinned()
  local observed={}
  for _,r in original.roots do
   rootIndex[r.header.name]=r.node
   local tops={}for _,node in r.node:GetChildren()do tops[node]=true end
   for i,node in r.node:GetDescendants()do
    if candidate(node,tops[node])then
     local id=node:GetDebugId(16)
     assert(wanted[id] and not observed[id],"New/duplicate uncovered cache identity")observed[id]=node
    end
    if i%1000==0 then task.wait()mode()rootGuard(original)end
   end
  end
  for id in wanted do assert(observed[id],"Pinned cache identity disappeared")end
  return observed
 end
 targets=discoverPinned()
 for _,pin in P.records do
  local root=assert(rootIndex[pin.rootName])local target=assert(targets[pin.instanceId],"Pinned cache native identity missing")
  assert(target:IsDescendantOf(root),"Cache identity belongs to different root")
  local row=table.clone(pin)row.rootName=nil row.topChild=nil
  assert(canonical(metadata(target))==canonical(row),"Actual inventory cache row changed")
  original.cacheRecords[#original.cacheRecords+1]={node=target,row=row}
 end
 checkedMetadata(original)
 local reflection=game:GetService("ReflectionService")
 local caps=SecurityCapabilities.new(table.unpack(Enum.SecurityCapability:GetEnumItems()))
 local schemas={} local byClass={}
 for _,class in P.classes do
  local specs=assert(reflection:GetPropertiesOfClass(class,{Security=caps,ExcludeInherited=false,ExcludeDisplay=true}),"Missing reflected animation class")
  local serialized,reference={},{}
  for _,spec in specs do
   if spec.Serialized then serialized[#serialized+1]=spec.Name end
   if spec.Type.ScriptType=="Instance" and spec.Name~="Parent" then
    reference[#reference+1]={name=spec.Name,serialized=spec.Serialized,scriptType=spec.Type.ScriptType,instanceType=spec.Type.InstanceType}
   end
  end
  table.sort(serialized)table.sort(reference,function(a,b)return a.name<b.name end)
  byClass[class]=reference schemas[#schemas+1]={className=class,serializedPropertyNames=serialized,instanceSlots=reference}
 end
 readSlot=function(node,name)
  local descriptor
  for _,spec in byClass[node.ClassName] do if spec.name==name then descriptor=spec end end
  assert(descriptor,"Required actual reflected Instance slot missing")
  local readable,value=pcall(function()return node[name]end)
  return {holder=basic(node),name=name,descriptor=descriptor,readable=readable,
   value=if readable then typed(value)else nil,error=if readable then nil else tostring(value):sub(1,512)}
 end
 local slots={}original.slots={}
 for _,ref in original.cacheRecords do
  if ref.node.ClassName=="ObjectValue" then
   local row=readSlot(ref.node,"Value")slots[#slots+1]=row original.slots[#original.slots+1]={node=ref.node,row=row}
  end
 end
 local model=assert(rootIndex.RBX_ANIMSAVES)
 local modelRow=readSlot(model,"PrimaryPart")slots[#slots+1]=modelRow original.slots[#original.slots+1]={node=model,row=modelRow}
 assert(#slots==28,"Exact 27 ObjectValue.Value plus one container PrimaryPart required")
 checkedMetadata(original)
 for _,first in slots do
  local holder
  if first.holder.instanceId==model:GetDebugId(16)then holder=model
  else holder=resolveChild(model,first.holder.instanceId)end
  assert(canonical(readSlot(holder,first.name))==canonical(first),"Reference frontier slot/readability changed during capture")
 end
 checkedMetadata(original)
 local _,sourceAfter=sourceCatalog()
 assert(sourceAfter==sourceHash,"Full Source catalog changed during frontier read")
 local afterTargets=discoverPinned()
 for id,node in targets do assert(afterTargets[id]==node,"Original cache identity changed during frontier read")end
 checkedMetadata(original)
 report.passed=true report.sourceCount=213 report.sourceCatalogSHA256=sourceHash
 report.originalSourceEditorPropertiesUnchanged=true report.originalRootCacheMetadataUnchanged=true
 report.inventoryManifestSHA256=P.inventoryManifestSHA256 report.schemas=schemas report.slots=slots
 report.slotCount=#slots report.cacheRecords=#original.cacheRecords
 report.limits="Actual reflection +27 Value/one PrimaryPart frontier only. Other serialized Instance slots/full data/reference closure, raw native archive and exact off-place reopen remain pending. Unreadable/missing is never nil. No upload/delete/recovery/gameplay/performance certificate. Point-in-time guards only."
end,debug.traceback)
if not ok then report.error=tostring(why):sub(1,6000)end
if original then
 local finalOk,finalError=pcall(checkedMetadata,original)
 report.finalOriginalGuardPassed=finalOk
 report.passed=report.passed and finalOk
 if not finalOk then report.finalGuardError=tostring(finalError):sub(1,2000)end
end
local encoded=H:JSONEncode(report)
assert(#encoded<=20000,"Frontier response exceeds bound; do not truncate or infer missing slots")
return encoded
