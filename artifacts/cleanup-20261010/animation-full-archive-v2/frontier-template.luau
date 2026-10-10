-- Root-owned READONLY instance metadata collector. No require, clone, serializer,
-- Instance.new, Source/editor/Parent/property write, upload, listener or spawned task.
-- REQUEST is inserted by the driver; shared scratch writes are counted separately.
local H=game:GetService("HttpService")
local E=game:GetService("EncodingService")
local SES=game:GetService("ScriptEditorService")
local RS=game:GetService("RunService")
local SS=game:GetService("ServerStorage")
local P=REQUEST
assert(type(P)=="table" and type(P.captureId)=="string" and P.captureId:match("^[a-zA-Z0-9%-]+$") and #P.captureId>=24)
assert(type(P.templateSHA256)=="string" and #P.templateSHA256==64)
local key="__MongoTVAnimationCacheInventory20261010V1_"..P.captureId
local ownerKey=key.."_owner"
local LIMIT_BYTES,CHUNK_BYTES,MAX_RECORDS=10000000,12000,10000
local state
local function mode()
 assert(game.PlaceId==131311258779917 and game.GameId==10559217407,"Wrong place/universe")
 assert(not RS:IsRunning(),"Edit required; never switch Play")
end
local function sha(text)
 local digest=E:ComputeBufferHash(buffer.fromstring(text),Enum.HashAlgorithm.Sha256)
 local out={} for i=0,buffer.len(digest)-1 do out[#out+1]=string.format("%02x",buffer.readu8(digest,i)) end
 return table.concat(out)
end
local function canonical(value)
 if type(value)~="table" then return H:JSONEncode(value) end
 local keys={} for k in value do keys[#keys+1]=k end
 table.sort(keys,function(a,b) return tostring(a)<tostring(b) end)
 local parts={} for _,k in keys do parts[#parts+1]=H:JSONEncode(tostring(k))..":"..canonical(value[k]) end
 return "{"..table.concat(parts,",").."}"
end
local function number(n) return string.format("%.17g",n) end
local function numbers(...)local out={} for _,v in {...} do out[#out+1]=number(v) end return out end
local function typed(value)
 local kind=typeof(value)
 if kind=="nil" then return {kind="nil"} end
 if kind=="string" or kind=="boolean" then return {kind=kind,value=value} end
 if kind=="number" then return {kind=kind,value=number(value)} end
 if kind=="EnumItem" then return {kind=kind,value=tostring(value)} end
 if kind=="Vector2" then return {kind=kind,components=numbers(value.X,value.Y)} end
 if kind=="Vector3" then return {kind=kind,components=numbers(value.X,value.Y,value.Z)} end
 if kind=="Color3" then return {kind=kind,components=numbers(value.R,value.G,value.B)} end
 if kind=="BrickColor" then return {kind=kind,number=value.Number,name=value.Name} end
 if kind=="CFrame" then return {kind=kind,components=numbers(value:GetComponents())} end
 if kind=="UDim" then return {kind=kind,components=numbers(value.Scale,value.Offset)} end
 if kind=="UDim2" then return {kind=kind,components=numbers(value.X.Scale,value.X.Offset,value.Y.Scale,value.Y.Offset)} end
 if kind=="Rect" then return {kind=kind,components=numbers(value.Min.X,value.Min.Y,value.Max.X,value.Max.Y)} end
 if kind=="NumberRange" then return {kind=kind,components=numbers(value.Min,value.Max)} end
 if kind=="NumberSequence" or kind=="ColorSequence" then
  local points={}
  for _,point in value.Keypoints do
   points[#points+1]={time=number(point.Time),value=typed(point.Value),envelope=if kind=="NumberSequence" then number(point.Envelope) else nil}
  end
  return {kind=kind,keypoints=points}
 end
 if kind=="Instance" then return {kind=kind,instanceId=value:GetDebugId(16),className=value.ClassName,path=value:GetFullName()} end
 error("Unsupported metadata datatype; never omit as nil: "..kind)
end
local function attributes(node)
 local out={} for name,value in node:GetAttributes() do out[#out+1]={name=name,value=typed(value)} end
 table.sort(out,function(a,b)return a.name<b.name end) return out
end
local function tags(node)local out=node:GetTags() table.sort(out) return out end
local function segments(node)
 local out={} while node~=game do out[#out+1]=node.Name node=node.Parent assert(node,"Detached metadata path") end
 local ordered={} for i=#out,1,-1 do ordered[#ordered+1]=out[i] end return ordered
end
local function basic(node)
 return {instanceId=node:GetDebugId(16),parentId=if node.Parent then node.Parent:GetDebugId(16) else nil,
  name=node.Name,className=node.ClassName,archivable=node.Archivable,segments=segments(node),
  childCount=#node:GetChildren(),attributes=attributes(node),tags=tags(node)}
end
local function scriptProperties(node)
 local properties={Archivable=node.Archivable,LinkedSource=tostring(node.LinkedSource)}
 if node:IsA("BaseScript") then
  properties.Enabled=node.Enabled properties.Disabled=node.Disabled properties.RunContext=tostring(node.RunContext)
 end
 return properties
end
local function scriptRow(node)
 local row=basic(node)
 local source=node.Source local editor=SES:GetEditorSource(node)
 assert(source==editor and node.Source==source and SES:GetEditorSource(node)==editor,"Source/editor conflict or unstable read")
 row.sourceBytes=#source row.rawSourceSHA256=sha(source) row.rawEditorSHA256=sha(editor)
 row.properties=scriptProperties(node)
 return row,source,editor
end
local function sourceCatalog()
 local refs,rows={},{}
 for i,node in game:GetDescendants() do
  if node:IsA("LuaSourceContainer") then
   local row,source,editor=scriptRow(node)
   local facts=basic(node) facts.properties=scriptProperties(node)
   refs[#refs+1]={node=node,row=row,source=source,editor=editor,facts=facts} rows[#rows+1]=row
  end
  if i%1000==0 then task.wait() mode() end
 end
 table.sort(rows,function(a,b)return a.instanceId<b.instanceId end)
 assert(#refs==213,"Fresh 213 Source baseline required")
 return refs,sha(canonical(rows)),rows
end
local function guardSources(s)
 mode()
 for _,ref in s.sources do
  assert(ref.node:IsDescendantOf(game) and ref.node.Source==ref.source and SES:GetEditorSource(ref.node)==ref.editor,"Original Source/editor/identity changed")
  local facts=basic(ref.node) facts.properties=scriptProperties(ref.node)
  assert(canonical(facts)==canonical(ref.facts),"Original class/properties/attrs/tags changed")
 end
end
local function uniqueRoot(name,className,topCount)
 local found
 for _,node in SS:GetChildren() do if node.Name==name then assert(not found,"Duplicate named root") found=node end end
 assert(found and found.ClassName==className and #found:GetChildren()==topCount,"Fresh exact animation root/class/topchildren changed")
 return found
end
local function header(node)
 local row=basic(node) local children={}
 for _,child in node:GetChildren() do children[#children+1]=child:GetDebugId(16) end
 table.sort(children) row.directChildIds=children return row
end
local function rootGuard(s)
 mode()
 for _,r in s.roots do
  assert(uniqueRoot(r.header.name,r.header.className,r.header.childCount)==r.node,"Animation named root identity/collision changed")
  assert(r.node.Parent==SS and canonical(header(r.node))==canonical(r.header),"Animation root identity/metadata/topchildren changed")
 end
end
local function metadata(node)
 local row=basic(node)
 row.publishedAssetId=typed(node:GetAttribute("PublishedAssetId"))
 row.animationIdAttribute=typed(node:GetAttribute("AnimationId"))
 if node:IsA("Animation") then
  local ok,value=pcall(function()return node.AnimationId end)
  row.animationId={readable=ok,value=if ok then typed(value) else nil}
  if not ok then row.metadataIncomplete=true end
 end
 if node:IsA("KeyframeSequence") then
  for _,name in {"Loop","Priority","AuthoredHipHeight"} do
   local ok,value=pcall(function()return node[name]end)
   row.sequenceProperties=row.sequenceProperties or {}
   row.sequenceProperties[#row.sequenceProperties+1]={name=name,readable=ok,value=if ok then typed(value) else nil}
   if not ok then row.metadataIncomplete=true end
  end
 end
 if (node.Name=="PublishedAssetId" or node.Name=="AnimationId") and node:IsA("ValueBase") then
  local ok,value=pcall(function()return node.Value end)
  row.namedIdValue={readable=ok,value=if ok then typed(value) else nil}
  if not ok then row.metadataIncomplete=true end
 end
 row.inferredPublisherVersion=node.Name:match("^MongoTV_Entity_.+_(v%d[%w_]*)$")
 return row
end
local function candidate(node,top)
 return top or node:IsA("AnimationClip") or node:IsA("Animation")
  or node:GetAttribute("PublishedAssetId")~=nil or node:GetAttribute("AnimationId")~=nil
  or ((node.Name=="PublishedAssetId" or node.Name=="AnimationId") and node:IsA("ValueBase"))
end
local function ownership(s)
 assert(s and shared[key]==s and shared[ownerKey]==s,"Foreign collector namespace/identity preserved")
 assert(s.captureId==P.captureId and s.templateSHA256==P.templateSHA256,"Collector purpose/code binding changed")
end
local function guards(s)
 ownership(s) s.assertOwned() s.readProgress() guardSources(s) rootGuard(s)
 for _,ref in s.records do assert(canonical(metadata(ref.node))==canonical(ref.row),"Actual cache/Animation/attrs/tags/childcounts changed") end
end
local function close(s)
 ownership(s) s.assertOwned() s.readProgress()
 shared[key]=nil shared[ownerKey]=nil
 s.advance(2,false)
 return {schema="mongotv-animation-cache-read-close-v1",closed=true,collectorStateWrites=s.progress.stateWrites,
  nativeInstanceWrites=0,nativeSourceWrites=0,nativePropertyWrites=0,modeSwitches=0}
end
local function freeze(value)
 if type(value)~="table" or typeof(value)=="Instance" or table.isfrozen(value) then return end
 for _,v in value do if type(v)=="table" then freeze(v) end end table.freeze(value)
end
local function discovery(s,record)
 local rows,facts={},{} local incomplete=false
 for _,r in s.roots do
  local top={} for _,node in r.node:GetChildren() do top[node]=true end
  local nodes=r.node:GetDescendants() local histogram={} local count=0 local identities={}
  for i,node in nodes do
   histogram[node.ClassName]=(histogram[node.ClassName] or 0)+1
   assert(not node:IsA("LuaSourceContainer"),"New script in retired animation data forest")
   if candidate(node,top[node]) then
    local comparison=metadata(node)
    identities[#identities+1]=comparison.instanceId
    count+=1
    if record then
     local row=metadata(node) row.rootName=r.node.Name row.topChild=top[node]==true
     s.records[#s.records+1]={node=node,row=comparison}
     rows[#rows+1]=row incomplete=incomplete or row.metadataIncomplete==true
     assert(#rows<=MAX_RECORDS,"Bounded metadata record limit; do not truncate")
    end
   end
   if i%1000==0 then task.wait() ownership(s) s.assertOwned() s.readProgress() rootGuard(s) end
  end
  table.sort(identities)
  facts[#facts+1]={root=r.header,descendantCount=#nodes,nodeCount=#nodes+1,classHistogram=histogram,metadataRecordCount=count,candidateIdentitySHA256=sha(canonical(identities))}
 end
 return rows,facts,incomplete
end
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
