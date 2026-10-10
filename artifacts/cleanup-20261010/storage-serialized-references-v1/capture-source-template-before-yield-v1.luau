-- S04 common read-only guards. Concatenate with one reviewed capture/reopen suffix.
-- No original Source/Parent/Archivable writes; no require of gameplay modules.
local A = {}
A.HS = game:GetService("HttpService")
A.ENC = game:GetService("EncodingService")
A.SER = game:GetService("SerializationService")
A.SES = game:GetService("ScriptEditorService")
A.REF = game:GetService("ReflectionService")
A.RS = game:GetService("RunService")
A.SS = game:GetService("ServerStorage")
A.KEY = "__MongoTVRetiredAuthoringArchive20261009"
A.ORIGINAL_KEY = "__MongoTVStorageCleanup20261009"
A.SCHEMA = "retired-authoring-native-archive-v1"
A.BASE = "http://127.0.0.1:18914"
A.NAMES = {
 "LobbyReimaginedBlenderSource20261001", "LobbyReimaginedBlenderSource20261001R2",
 "LobbyReimaginedBlenderSource20261001R3", "LobbyReimaginedBlenderSource20261001R3B",
 "Level1BlenderKit",
}
A.COUNTS = {97,97,104,104,1215}
A.CAPS = SecurityCapabilities.new(table.unpack(Enum.SecurityCapability:GetEnumItems()))
local propertyCache = {}
function A.check(value,message) assert(value,message) end
function A.mode()
 A.check(game.PlaceId==131311258779917 and game.GameId==10559217407,"Wrong place/universe")
 A.check(not A.RS:IsRunning(),"Edit required; never switch another session's mode")
 A.check(A.HS.HttpEnabled,"Existing HttpEnabled required; do not change service settings")
end
function A.sha(raw)
 local digest=A.ENC:ComputeBufferHash(raw,Enum.HashAlgorithm.Sha256)
 local chars={} for i=0,buffer.len(digest)-1 do chars[i+1]=string.format("%02x",buffer.readu8(digest,i)) end
 return table.concat(chars)
end
function A.shaText(text) return A.sha(buffer.fromstring(text)) end
function A.same(a,b)
 if typeof(a)~=typeof(b) then return false end
 if typeof(a)~="table" then return a==b end
 for k,v in a do if not A.same(v,b[k]) then return false end end
 for k in b do if a[k]==nil then return false end end return true
end
function A.tags(item) local tags=item:GetTags() table.sort(tags) return tags end
function A.typed(v,index)
 local kind=typeof(v)
 if kind=="nil" then return {type=kind} end
 if kind=="string" or kind=="boolean" or kind=="number" then return {type=kind,value=v} end
 if kind=="Instance" then return {type=kind,node=index and index[v],external=if not index or not index[v] then v:GetFullName() else nil,class=v.ClassName} end
 if kind=="CFrame" then return {type=kind,value={v:GetComponents()}} end
 if kind=="Vector3" or kind=="Vector3int16" then return {type=kind,value={v.X,v.Y,v.Z}} end
 if kind=="Vector2" or kind=="Vector2int16" then return {type=kind,value={v.X,v.Y}} end
 if kind=="Color3" then return {type=kind,value={v.R,v.G,v.B}} end
 if kind=="UDim" then return {type=kind,value={v.Scale,v.Offset}} end
 if kind=="UDim2" then return {type=kind,value={v.X.Scale,v.X.Offset,v.Y.Scale,v.Y.Offset}} end
 if kind=="NumberRange" then return {type=kind,value={v.Min,v.Max}} end
 if kind=="BrickColor" then return {type=kind,value=v.Number} end
 if kind=="PhysicalProperties" then return {type=kind,value={v.Density,v.Friction,v.Elasticity,v.FrictionWeight,v.ElasticityWeight}} end
 if kind=="NumberSequence" or kind=="ColorSequence" then
  local values={} for _,p in v.Keypoints do values[#values+1]={time=p.Time,value=A.typed(p.Value,index),envelope=if kind=="NumberSequence" then p.Envelope else nil} end
  return {type=kind,value=values}
 end
 if kind=="Content" then
  local source=tostring(v.SourceType)
  A.check(v.SourceType~=Enum.ContentSourceType.Object,"Opaque Object Content requires a different recovery port")
  return {type=kind,sourceType=source,uri=if v.SourceType==Enum.ContentSourceType.Uri then v.Uri else nil}
 end
 -- Engine enum/security-capability values are compared read-only as their stable spelling.
 if kind=="EnumItem" or kind=="SecurityCapabilities" then return {type=kind,value=tostring(v)} end
 return {type=kind,value=tostring(v),comparison="readable-string",requiresReview=true}
end
function A.attributes(item,index)
 local values={} for k,v in item:GetAttributes() do values[k]=A.typed(v,index) end return values
end
function A.properties(class)
 if not propertyCache[class] then
  local reflected=A.REF:GetPropertiesOfClass(class,{Security=A.CAPS,ExcludeInherited=false,ExcludeDisplay=true})
  A.check(reflected~=nil,"Unreflected class in retired forest: "..class)
  propertyCache[class]=reflected
 end return propertyCache[class]
end
function A.collect(roots)
 local nodes,index,parents={},{},{}
 local function walk(node,parent)
  A.check(index[node]==nil,"Overlapping/duplicated archive tree")
  nodes[#nodes+1]=node index[node]=#nodes parents[node]=parent
  A.check(not node:IsA("LuaSourceContainer"),"Retired five-root scope must contain zero scripts")
  A.check(node.Archivable,"Archivable=false requires an independently reviewed native port")
  for _,child in node:GetChildren() do walk(child,node) end
 end
 for _,root in roots do walk(root,nil) end return nodes,index,parents
end
function A.forestFacts(roots)
 local nodes,index,parents=A.collect(roots)
 local rows,opaque,unsupported={},{},{}
 -- New native identities are expected on reopen. Neither is a gameplay/property normalization.
 local identity={UniqueId=true,HistoryId=true}
 for i,node in nodes do
  local p={}
  for _,spec in A.properties(node.ClassName) do
   if spec.Serialized and spec.Name~="Parent" and not identity[spec.Name] then
    local ok,v=pcall(function() return node[spec.Name] end)
    if ok then
     local encoded=if node:IsA("StringValue") and spec.Name=="Value" then {type="string",bytes=#v,sha256=A.shaText(v)} else A.typed(v,index)
     p[spec.Name]=encoded
     if encoded.requiresReview then unsupported[node.ClassName.."."..spec.Name..":"..encoded.type]=true end
    else opaque[node.ClassName.."."..spec.Name]=true end
   end
  end
  local children={} for _,child in node:GetChildren() do children[#children+1]=index[child] end
  rows[i]={id=i,parent=if parents[node] then index[parents[node]] else 0,name=node.Name,class=node.ClassName,
   archivable=node.Archivable,attributes=A.attributes(node,index),tags=A.tags(node),children=children,properties=p}
  if i%200==0 then task.wait() end
 end
 local opaqueNames={} for name in opaque do opaqueNames[#opaqueNames+1]=name end table.sort(opaqueNames)
 local unsupportedNames={} for name in unsupported do unsupportedNames[#unsupportedNames+1]=name end table.sort(unsupportedNames)
 local rootsInfo={}
 for i,root in roots do rootsInfo[i]={name=root.Name,class=root.ClassName,instances=1+#root:GetDescendants(),index=index[root]} end
 return {roots=rootsInfo,nodes=rows,instanceCount=#nodes,scriptCount=0,opaqueSerializedProperties=opaqueNames,
  unsupportedReadableProperties=unsupportedNames,identityExclusions={"UniqueId","HistoryId"},
  referenceScope="all readable serialized forest properties; engine binary preserves inaccessible fields"},nodes,index
end
function A.scriptRow(script)
 local source=script.Source
 A.check(A.SES:GetEditorSource(script)==source,"Source/editor conflict: "..script:GetFullName())
 local properties={Archivable=script.Archivable,LinkedSource=tostring(script.LinkedSource)}
 if script:IsA("BaseScript") then properties.Enabled=script.Enabled properties.Disabled=script.Disabled properties.RunContext=tostring(script.RunContext) end
 return {path=script:GetFullName(),class=script.ClassName,parent=script.Parent,source=source,properties=properties,attributes=script:GetAttributes(),tags=A.tags(script)}
end
function A.contextPredicates(state)
 local runningOk,running=pcall(function()return A.RS:IsRunning()end)
 local httpOk,httpEnabled=pcall(function()return A.HS.HttpEnabled end)
 local previous=state and state.previous
 return {atClock=os.clock(),epoch=state and state.epoch or 0,
  modeReadable=runningOk,running=if runningOk then running else nil,httpReadable=httpOk,httpEnabled=if httpOk then httpEnabled else nil,
  placeMatches=game.PlaceId==131311258779917,universeMatches=game.GameId==10559217407,
  ownedLease=state~=nil and shared[A.KEY]==state,previousLedgerAcquired=previous~=nil,
  previousLedgerSame=previous~=nil and shared[A.ORIGINAL_KEY]==previous,
  previousProbeLeaseAbsent=previous~=nil and not previous.probeLease,
  previousPortLeaseAbsent=previous~=nil and not previous.portLease}
end
function A.nodeMetadata(node)
 if typeof(node)~="Instance" then return {kind=typeof(node)} end
 local ok,path=pcall(function()return node:GetFullName()end)
 return {class=node.ClassName,path=if ok then string.sub(path,1,384) else "<unreadable path>",pathTruncated=ok and #path>384}
end
function A.event(state,kind,node,argument)
 -- Fail-closed epoch behavior is unchanged; diagnostics never record event values.
 state.epoch+=1
 state.epochReasons=state.epochReasons or {} state.epochKinds=state.epochKinds or {}
 state.epochKinds[kind]=(state.epochKinds[kind] or 0)+1
 local row=A.nodeMetadata(node) row.kind=kind row.epoch=state.epoch row.argumentKind=typeof(argument)
 if string.sub(kind,-8)==".Changed" and typeof(node)=="Instance" then
  if node:IsA("ValueBase") then row.property="Value" -- ValueBase Changed passes the value, never a property name.
  elseif typeof(argument)=="string" then
   for _,spec in propertyCache[node.ClassName] or {} do if argument==spec.Name then row.property=spec.Name break end end
   if not row.property and (argument=="Source" or argument=="Parent" or argument=="Name" or argument=="Archivable") then row.property=argument end
   if not row.property then row.property="<unclassified property>" end
  end
 end
 row.context=A.contextPredicates(state)
 if #state.epochReasons<32 then state.epochReasons[#state.epochReasons+1]=row
 else state.epochReasonDropped=(state.epochReasonDropped or 0)+1 end
 state.lastEpochReason=row
end
function A.watchNode(state,node,scope,includeChildren)
 state.connections[#state.connections+1]=node.Changed:Connect(function(argument)A.event(state,scope..".Changed",node,argument)end)
 state.connections[#state.connections+1]=node.AttributeChanged:Connect(function()A.event(state,scope..".AttributeChanged",node)end)
 if includeChildren then
  state.connections[#state.connections+1]=node.ChildAdded:Connect(function(child)A.event(state,scope..".ChildAdded",child)end)
  state.connections[#state.connections+1]=node.ChildRemoved:Connect(function(child)A.event(state,scope..".ChildRemoved",child)end)
 end
end
function A.watchInventory(state)
 local function watch(node,kind) if node:IsA("LuaSourceContainer") or node.Parent==A.SS then A.event(state,kind,node) end end
 state.connections[#state.connections+1]=game.DescendantAdded:Connect(function(node)watch(node,"game.DescendantAdded")end)
 state.connections[#state.connections+1]=game.DescendantRemoving:Connect(function(node)watch(node,"game.DescendantRemoving")end)
 state.connections[#state.connections+1]=A.SS.ChildAdded:Connect(function(node)A.event(state,"ServerStorage.ChildAdded",node)end)
 state.connections[#state.connections+1]=A.SS.ChildRemoved:Connect(function(node)A.event(state,"ServerStorage.ChildRemoved",node)end)
end
function A.checkpoint(state,label)
 local row=A.contextPredicates(state) row.checkpoint=label state.lastGuardObservation=row
 A.mode()
 A.check(row.ownedLease and row.previousLedgerSame and row.epoch==0
  and row.previousProbeLeaseAbsent and row.previousPortLeaseAbsent,"Original/mode/lease changed during "..label)
end
function A.diagnostics(state)
 if not state then return {stateAvailable=false,context=A.contextPredicates(nil)} end
 return {stateAvailable=true,baselineComplete=state.baselineComplete,watchersConnected=state.watchersConnected,
  epoch=state.epoch,epochReasons=state.epochReasons or {},epochKinds=state.epochKinds or {},
  epochReasonDropped=state.epochReasonDropped or 0,lastEpochReason=state.lastEpochReason,
  lastGuardObservation=state.lastGuardObservation,context=A.contextPredicates(state),
  limits="Bounded metadata only. Event origin/actor is unproven; values, Source bodies and raw attributes are never recorded."}
end
function A.heldOriginals(state)
 -- Held Parent=nil originals belong to another actor's earlier cleanup, never to this probe.
 local previous=assert(shared[A.ORIGINAL_KEY],"Held-original identity ledger unavailable")
 A.check(previous.rootRefs and not previous.probeLease and not previous.portLease,"Held-original ledger busy/incomplete")
 state.previous=previous state.heldRoots={} state.heldRows={} state.previousRoots={}
 local processed=0
 for root in previous.rootRefs do
  state.previousRoots[root]=true
  state.knownOriginals[root]=true
  if root.Parent==nil then
   state.heldRoots[root]=true
   local tree={root} for _,node in root:GetDescendants() do tree[#tree+1]=node end
   for _,node in tree do
    A.check(not state.heldRows[node],"Held original trees overlap")
    state.knownOriginals[node]=true
    local children=node:GetChildren()
    local row={parent=node.Parent,name=node.Name,class=node.ClassName,archivable=node.Archivable,
     attributes=node:GetAttributes(),tags=A.tags(node),children=children,properties={}}
    for _,spec in A.properties(node.ClassName) do
     if spec.Serialized and spec.Name~="Parent" and spec.Name~="Source" then
      local readable,value=pcall(function()return node[spec.Name]end)
      row.properties[#row.properties+1]={name=spec.Name,readable=readable,value=if readable then value else nil}
     end
    end
    if node:IsA("LuaSourceContainer") then row.script=A.scriptRow(node) end
    state.heldRows[node]=row
    A.check(#state.connections<100000,"Held-original watcher bound exceeded")
    A.watchNode(state,node,"heldOriginal",true)
    processed+=1
    if processed%500==0 then
     task.wait() A.checkpoint(state,"held baseline yield")
    end
   end
  end
 end
end
function A.guardHeld(state)
 local processed=0
 A.check(shared[A.ORIGINAL_KEY]==state.previous and not state.previous.probeLease and not state.previous.portLease,"Held-original ledger changed/busy")
 for root in state.previous.rootRefs do
  A.check(state.previousRoots[root],"Held-original ledger gained an identity")
  A.check((root.Parent==nil)==(state.heldRoots[root]==true),"Held-original root set changed")
 end
 for root in state.previousRoots do A.check(state.previous.rootRefs[root]~=nil,"Held-original ledger lost an identity") end
 for root in state.heldRoots do A.check(root.Parent==nil and not root:IsDescendantOf(game),"Held original entered the place") end
 for node,row in state.heldRows do
  A.check(node.Parent==row.parent and node.Name==row.name and node.ClassName==row.class and node.Archivable==row.archivable,
   "Held original hierarchy/properties changed")
  A.check(A.same(node:GetAttributes(),row.attributes) and A.same(A.tags(node),row.tags) and A.same(node:GetChildren(),row.children),"Held original children/attrs/tags changed")
  for _,slot in row.properties do
   local readable,value=pcall(function()return node[slot.name]end)
   A.check(readable==slot.readable and (not readable or value==slot.value),"Held original serialized field changed")
  end
  if row.script then A.check(A.same(A.scriptRow(node),row.script),"Held original Source/editor changed") end
  processed+=1
  if processed%500==0 then
   task.wait() A.checkpoint(state,"held guard yield")
  end
 end
end
function A.begin(config)
 A.mode()
 A.check(type(config)=="table" and config.expectedRootCount>=5 and config.expectedSourceCount>=1,"Explicit fresh counts required")
 A.check(type(config.captureId)=="string" and #config.captureId>=16,"Pinned receiver capture ID required")
 A.check(shared[A.KEY]==nil,"A previous S04 lease/state exists; do not replace it")
 local state={phase="capture",config=config,roots={},sources={},rootRefs={},knownOriginals={},connections={},epoch=0,baselineComplete=false,watchersConnected=true}
 shared[A.KEY]=state
 A.watchInventory(state)
 for _,root in A.SS:GetChildren() do
  state.rootRefs[root]={name=root.Name,class=root.ClassName,archivable=root.Archivable,attributes=root:GetAttributes(),tags=A.tags(root)}
  A.watchNode(state,root,"storageRoot",false)
 end
 A.check(#A.SS:GetChildren()==config.expectedRootCount,"Fresh ServerStorage count changed")
 for _,name in A.NAMES do
  local matches={} for _,root in A.SS:GetChildren() do if root.Name==name then matches[#matches+1]=root end end
  A.check(#matches==1 and matches[1].ClassName=="Folder","Missing/duplicate/wrong retired root: "..name)
  state.roots[#state.roots+1]=matches[1]
 end
 for i,root in state.roots do A.check(1+#root:GetDescendants()==A.COUNTS[i],"Retired root count changed: "..root.Name) end
 state.facts,state.nodes,state.index=A.forestFacts(state.roots)
 A.check(state.facts.instanceCount==1617,"Retired forest count changed")
 for _,node in state.nodes do
  A.watchNode(state,node,"retiredForest",true)
 end
 local count=0
 for i,node in game:GetDescendants() do
  state.knownOriginals[node]=true
  if node:IsA("LuaSourceContainer") then
   state.sources[node]=A.scriptRow(node) count+=1
   A.watchNode(state,node,"liveSource",false)
  end
  if i%1000==0 then task.wait() end
 end
 A.check(count==config.expectedSourceCount,"Fresh Source count changed")
 A.heldOriginals(state)
 state.sourceCount=count state.baselineComplete=true return state
end
function A.guard(state)
 state.lastGuardObservation=A.contextPredicates(state) state.lastGuardObservation.checkpoint="original guard entry"
 A.mode() A.check(shared[A.KEY]==state,"S04 lease replaced")
 A.check(state.baselineComplete and state.epoch==0,"Capture incomplete or concurrent original event")
 local seenRoots={} for _,root in A.SS:GetChildren() do
  local row=state.rootRefs[root]
  A.check(row and root.Name==row.name and root.ClassName==row.class and root.Archivable==row.archivable
   and A.same(root:GetAttributes(),row.attributes) and A.same(A.tags(root),row.tags),"Original ServerStorage inventory changed") seenRoots[root]=true
 end
 for root in state.rootRefs do A.check(seenRoots[root] and root.Parent==A.SS,"Original root removed/reparented") end
 A.check(#A.SS:GetChildren()==state.config.expectedRootCount,"Original root count changed")
 for i,root in state.roots do A.check(root.Parent==A.SS and root.Name==A.NAMES[i],"Retired original changed parent/name") end
 local facts,nodes=A.forestFacts(state.roots)
 A.check(A.same(facts,state.facts),"Original forest facts changed")
 for i,node in nodes do A.check(node==state.nodes[i],"Original forest identity/order changed") end
 if state.nativeSHA256 then
  local originalBytes=A.SER:SerializeInstancesAsync(state.roots)
  A.check(buffer.len(originalBytes)==state.nativeBytes and A.sha(originalBytes)==state.nativeSHA256,"Opaque original native forest changed")
 end
 local seen={} local count=0
 for i,node in game:GetDescendants() do
  if node:IsA("LuaSourceContainer") then A.check(state.sources[node]~=nil,"New original Source") seen[node]=true count+=1 end
  if i%1000==0 then task.wait() end
 end
 A.check(count==state.sourceCount,"Original Source count changed")
 for node,row in state.sources do
  A.check(seen[node] and node:IsDescendantOf(game) and node.Parent==row.parent,"Original Source detached/moved")
  A.check(A.same(A.scriptRow(node),row),"Original Source/editor/properties/attrs changed: "..row.path)
 end
 A.guardHeld(state)
 A.check(state.epoch==0,"Original event during guard") A.mode()
end
function A.disconnect(state)
 local errors={} for _,connection in state.connections do local ok,why=pcall(function()connection:Disconnect()end) if not ok then errors[#errors+1]=tostring(why) end end
 state.connections={} state.watchersConnected=false return errors
end
function A.post(config,path,body)
 return A.HS:RequestAsync({Url=A.BASE..path,Method="POST",Headers={["Content-Type"]="application/octet-stream",["X-Archive-Capture"]=config.captureId},Body=body})
end
function A.upload(config,kind,text)
 local bytes=#text local parts=math.ceil(bytes/500000)
 for i=0,parts-1 do
  A.mode() local response=A.post(config,"/part/"..kind.."/"..i,string.sub(text,i*500000+1,(i+1)*500000))
  A.check(response.Success and response.Body=="saved","Archive receiver failed for "..kind)
 end
 return {parts=parts,bytes=bytes,sha256=A.shaText(text)}
end
function A.references(state)
 local classes,external,internal,unreadable,missing={},{},{},{},{}
 local slots=0
 for i,node in game:GetDescendants() do
  local props=classes[node.ClassName]
  if not props then
   props=A.REF:GetPropertiesOfClass(node.ClassName,{Security=A.CAPS,ExcludeInherited=false,ExcludeDisplay=true})
   if props==nil then
    A.check(node.ClassName=="" and node.Name=="FilteredSelection" and node.Parent==game,"Unreflected original class")
    missing[#missing+1]={name=node.Name,class=node.ClassName,scope="transient editor metadata"}
    props={}
   end
   classes[node.ClassName]=props
  end
  for _,spec in props do
   if spec.Name~="Parent" and spec.Type.ScriptType=="Instance" then
    slots+=1 A.check(slots<=300000,"Reference scan exceeds reviewed bound")
    local ok,v=pcall(function()return node[spec.Name]end)
    if ok and typeof(v)=="Instance" and state.index[v] then
     local row={from=node:GetFullName(),property=spec.Name,targetNode=state.index[v],serialized=spec.Serialized,type=spec.Type.InstanceType}
     if state.index[node] then row.fromNode=state.index[node] internal[#internal+1]=row else external[#external+1]=row end
    elseif not ok then
     local key=node.ClassName.."."..spec.Name..":"..tostring(spec.Serialized)
     local row=unreadable[key]
     if not row then row={class=node.ClassName,property=spec.Name,serialized=spec.Serialized,type=spec.Type.InstanceType,count=0,samples={}} unreadable[key]=row end
     row.count+=1 if #row.samples<2 then row.samples[#row.samples+1]=node:GetFullName() end
    end
   end
  end
  if i%1000==0 then task.wait() end
 end
 local protected={} for _,row in unreadable do protected[#protected+1]=row end table.sort(protected,function(a,b)return a.class..a.property<b.class..b.property end)
 return {slots=slots,externalReadable=external,internalReadable=internal,unreadable=protected,missingReflectionClasses=missing,
  limits="Unreadable references remain opaque; this five-root recovery pack does not approve removal or include other native roots."}
end

local PORT_CONFIG=A.HS:JSONDecode([====[{"bake":{"className":"ModuleScript","properties":{"Archivable":true,"LinkedSource":""},"rawBytes":12341,"rawSHA256":"1f564fdde835ad89b529d9069ddf87b0ed4991636f363eacbd098cc0b342ff28","segments":["ServerScriptService","LobbyReimaginedPreview","RuntimeBake"]},"captureId":"643e0e0973fc457dae8136902d10587a","catalogSHA256":"81115530329fefcca83091e74379f63983ca0aa4b1da0b43bc64e653956623dd","expectedRootCount":52,"expectedSceneCount":417075,"expectedSourceCount":213,"maxDetachSeconds":60,"nativeSHA256":"e808f055403bd331b76e0831955b192abc8b4a914865c3936aa9b2d23ed2a8d7","privateToken":"__ROOT_PRIVATE_TOKEN__","renderer":{"className":"ModuleScript","properties":{"Archivable":true,"LinkedSource":""},"rawBytes":31759,"rawSHA256":"0f217e5a3f56751e7672efc035861a2cec1b5f23d581a52020411a8d081790cf","segments":["ServerScriptService","Level 1 Systems","BlenderRoomRenderer"]},"schema":"retired-authoring-joint-reference-config-v1","sources":[{"className":"LocalScript","properties":{"Archivable":true,"Disabled":false,"Enabled":true,"LinkedSource":"","RunContext":"Enum.RunContext.Legacy"},"rawBytes":42196,"rawSHA256":"80818a55cab10e8bd85c5c48ac6953280f4013bd9272736eda781219fc6fce92","segments":["ReplicatedFirst","Lobby Loading Screen"]},{"className":"ModuleScript","properties":{"Archivable":true,"LinkedSource":""},"rawBytes":8952,"rawSHA256":"62976a1da7582053ce67bff170e0c950969d2ac914a0a50502845390bf0cbdc2","segments":["ReplicatedStorage","DeathAdvice"]},{"className":"ModuleScript","properties":{"Archivable":true,"LinkedSource":""},"rawBytes":2835,"rawSHA256":"19c3df737e2e90924fb3fb1350d55dcd05595dd59c2fafda8d06e407848841d5","segments":["ReplicatedStorage","DevAccess"]},{"className":"ModuleScript","properties":{"Archivable":true,"LinkedSource":""},"rawBytes":3110,"rawSHA256":"4c2db65af38dd00092ab2af74d670b22fd5af9a1d3cf1e80af95fd5ffba4a230","segments":["ReplicatedStorage","FlashlightProfiles"]},{"className":"ModuleScript","properties":{"Archivable":true,"LinkedSource":""},"rawBytes":5063,"rawSHA256":"084cfec8d568140ffd05eaf7e38c29ec12755c0142ea51d7b77bf2d51d39860f","segments":["ReplicatedStorage","Level 2 Entity Audio Bank"]},{"className":"ModuleScript","properties":{"Archivable":true,"LinkedSource":""},"rawBytes":36273,"rawSHA256":"7cae5a9d4208e6e03605b27360c63be020f9f70bcabdfad0818051fb1008201d","segments":["ReplicatedStorage","Level 4 Usher Animations"]},{"className":"ModuleScript","properties":{"Archivable":true,"LinkedSource":""},"rawBytes":8923,"rawSHA256":"0f2d4b561ae206ffd07c4345a5e7372853c54863071946e525bd3fa0970c4a7b","segments":["ReplicatedStorage","LoadingCardView"]},{"className":"ModuleScript","properties":{"Archivable":true,"LinkedSource":""},"rawBytes":21531,"rawSHA256":"ede7dd4a687e76d0aefba2356869e0e31d70dc953b963680ae8fd607ea32e165","segments":["ReplicatedStorage","MasterConfiguration"]},{"className":"ModuleScript","properties":{"Archivable":true,"LinkedSource":""},"rawBytes":6906,"rawSHA256":"7465190a4b065cc0398923bfeb5938914e2cdfd7e06db574df25109a5c1d9649","segments":["ReplicatedStorage","ProtectionClient"]},{"className":"ModuleScript","properties":{"Archivable":true,"LinkedSource":""},"rawBytes":76673,"rawSHA256":"98983afec6256d7f4c2286ae3228c68c06e5e78a1a9f6e3470dda6281ee42559","segments":["ReplicatedStorage","RoundHud"]},{"className":"ModuleScript","properties":{"Archivable":true,"LinkedSource":""},"rawBytes":10221,"rawSHA256":"6021c4c5fa8cb3395b47ce417915d7f7cb54ced5f54e1466f67e1ecce33370aa","segments":["ReplicatedStorage","SceneEffectBudget"]},{"className":"ModuleScript","properties":{"Archivable":true,"LinkedSource":""},"rawBytes":3945,"rawSHA256":"393dfb9c410700a78328d6e056c813fa25baf0bd9f8c5191c7de0e951eb5ec40","segments":["ReplicatedStorage","SlideContinuationSafety"]},{"className":"ModuleScript","properties":{"Archivable":true,"LinkedSource":""},"rawBytes":101439,"rawSHA256":"863027af3565a3ac224b2fcdbdc365b76dd23d6a2b74f7598e3fc7bd39af61d4","segments":["ReplicatedStorage","UIDevice"]},{"className":"ModuleScript","properties":{"Archivable":true,"LinkedSource":""},"rawBytes":313853,"rawSHA256":"a862519414051a16dd3e401f1753fdd9ae1c4d78a1d217ced8fded0b596163c6","segments":["ReplicatedStorage","UIRegression"]},{"className":"ModuleScript","properties":{"Archivable":true,"LinkedSource":""},"rawBytes":12426,"rawSHA256":"94b0216cf9dcbe9f0380c68ad832233777882b57312dc8de68804d9fdc0095c3","segments":["ReplicatedStorage","UIStyle"]},{"className":"ModuleScript","properties":{"Archivable":true,"LinkedSource":""},"rawBytes":6018,"rawSHA256":"c5aaa9b16a974cc13fa24a89a6d4dae3f26637f49ec53fccd1803dd562b9ab5b","segments":["ReplicatedStorage","ZyntraChallenges"]},{"className":"ModuleScript","properties":{"Archivable":true,"LinkedSource":""},"rawBytes":21638,"rawSHA256":"b52815530258702531d3365eee447c0361abdb2c2d62aac98001b830437e0202","segments":["ReplicatedStorage","ZyntraConfig"]},{"className":"ModuleScript","properties":{"Archivable":true,"LinkedSource":""},"rawBytes":1496,"rawSHA256":"c52745e7c9ab71d055d66512c8522f6629b1bafe39dc0079dc05a6da4e348515","segments":["ReplicatedStorage","ZyntraDailyResearch"]},{"className":"ModuleScript","properties":{"Archivable":true,"LinkedSource":""},"rawBytes":16287,"rawSHA256":"9c5cefbe50c5dd637f751d83b6c374eedce35ad6a7032beca397c6b96e9a3d09","segments":["ReplicatedStorage","ZyntraDetectorVisual"]},{"className":"ModuleScript","properties":{"Archivable":true,"LinkedSource":""},"rawBytes":35972,"rawSHA256":"5e2a0151609bea62fa2592610fe2292f79124dc4428e22defffdf2aa6d5c4467","segments":["ReplicatedStorage","ZyntraShopUI","ShopBinder"]},{"className":"ModuleScript","properties":{"Archivable":true,"LinkedSource":""},"rawBytes":23228,"rawSHA256":"665da0c8a0f0b7a45cc7bfa6181ffbafff5a6322e3f1113891804a044ff8a365","segments":["ReplicatedStorage","ZyntraShopUI","ShopData"]},{"className":"ModuleScript","properties":{"Archivable":true,"LinkedSource":""},"rawBytes":5823,"rawSHA256":"ac7fc5a7278eea8c36c9fccc80a040887ce61913bc6142a3c60bc1075b293af4","segments":["ReplicatedStorage","ZyntraSkins"]},{"className":"Script","properties":{"Archivable":true,"Disabled":false,"Enabled":true,"LinkedSource":"","RunContext":"Enum.RunContext.Legacy"},"rawBytes":2567,"rawSHA256":"19c6dab6bc7c09d5affd25180a54f14f03cfa954bb52bf90313de570564ac8de","segments":["ServerScriptService","AvatarNormalize"]},{"className":"Script","properties":{"Archivable":true,"Disabled":false,"Enabled":true,"LinkedSource":"","RunContext":"Enum.RunContext.Legacy"},"rawBytes":7325,"rawSHA256":"2d9ded3b5b786cccf1f54a4e8e94d28781d0869f57141353946ad8634499d512","segments":["ServerScriptService","Crouch State Server"]},{"className":"Script","properties":{"Archivable":true,"Disabled":false,"Enabled":true,"LinkedSource":"","RunContext":"Enum.RunContext.Legacy"},"rawBytes":6494,"rawSHA256":"6a6dedd4b3de72d8ad729b29c7eb56a1e82b00700913f1ec0d62568b8978d06b","segments":["ServerScriptService","FlashlightSync"]},{"className":"ModuleScript","properties":{"Archivable":true,"LinkedSource":""},"rawBytes":7763,"rawSHA256":"3ecdd96e368146fdfad94aaced595ec96ad26b89de2172f521aabdaa42e6cd0a","segments":["ServerScriptService","FriendBoost"]},{"className":"Script","properties":{"Archivable":true,"Disabled":false,"Enabled":true,"LinkedSource":"","RunContext":"Enum.RunContext.Legacy"},"rawBytes":196628,"rawSHA256":"59e4d7350d436d6f2b252742f0dd43d00ce3b0aed8980dddbe54ed24a75765d4","segments":["ServerScriptService","GameManager"]},{"className":"Script","properties":{"Archivable":true,"Disabled":false,"Enabled":true,"LinkedSource":"","RunContext":"Enum.RunContext.Legacy"},"rawBytes":16903,"rawSHA256":"f279e4816d991f37b336c381a25feccc0b6dfc829d683a9a97841f70d615e156","segments":["ServerScriptService","HazmatSkinVisuals"]},{"className":"ModuleScript","properties":{"Archivable":true,"LinkedSource":""},"rawBytes":31759,"rawSHA256":"0f217e5a3f56751e7672efc035861a2cec1b5f23d581a52020411a8d081790cf","segments":["ServerScriptService","Level 1 Systems","BlenderRoomRenderer"]},{"className":"Script","properties":{"Archivable":true,"Disabled":false,"Enabled":true,"LinkedSource":"","RunContext":"Enum.RunContext.Legacy"},"rawBytes":67280,"rawSHA256":"7a1e689543b043c4d5da90270b32abbe02525183ef71adea85664a171bf5bd01","segments":["ServerScriptService","Level 1 Systems","EntityAI"]},{"className":"Script","properties":{"Archivable":true,"Disabled":false,"Enabled":true,"LinkedSource":"","RunContext":"Enum.RunContext.Legacy"},"rawBytes":10869,"rawSHA256":"6392c4420fd7bcf52e1d8c7abd73930b55d41f738eb74a4939bf455118ebb5a9","segments":["ServerScriptService","Level 1 Systems","EntityAnimation"]},{"className":"Script","properties":{"Archivable":true,"Disabled":false,"Enabled":true,"LinkedSource":"","RunContext":"Enum.RunContext.Legacy"},"rawBytes":11569,"rawSHA256":"4891d4175d4d1c185090128f3d7872dd07ca69a79c2d8304ed92eebac2363727","segments":["ServerScriptService","Level 1 Systems","EntityKill"]},{"className":"Script","properties":{"Archivable":true,"Disabled":false,"Enabled":true,"LinkedSource":"","RunContext":"Enum.RunContext.Legacy"},"rawBytes":93377,"rawSHA256":"8ea483bda5477c34c72e07dc9fd5d4b9b5aa5264788869aaf61c51f50d2fb36f","segments":["ServerScriptService","Level 1 Systems","MazeGenerator"]},{"className":"Script","properties":{"Archivable":true,"Disabled":false,"Enabled":true,"LinkedSource":"","RunContext":"Enum.RunContext.Legacy"},"rawBytes":115391,"rawSHA256":"9cdc5ea50c1666cd04e95e4154e7bea70bf973a95c4e7ff7781e2d28dc35bc40","segments":["ServerScriptService","Level 1 Systems","PuzzleManager"]},{"className":"ModuleScript","properties":{"Archivable":true,"LinkedSource":""},"rawBytes":12107,"rawSHA256":"0d420b4371f37deaa21d4830743d9fa5b5d3c6169288ceb0acad719f37d73c87","segments":["ServerScriptService","Level 2 Systems","Level 2 Configuration"]},{"className":"ModuleScript","properties":{"Archivable":true,"LinkedSource":""},"rawBytes":47083,"rawSHA256":"8f62fc39e7993c2cda2e51921ad257b1ee94e3aef898fe827293ee25bc08e871","segments":["ServerScriptService","Level 2 Systems","Level 2 Exit Transition Test Suite"]},{"className":"ModuleScript","properties":{"Archivable":true,"LinkedSource":""},"rawBytes":50980,"rawSHA256":"e1ad3a0a111a9c0053b321b7ba82e20a85f348a9a6ff73fdf765f1860573f758","segments":["ServerScriptService","Level 2 Systems","Level 2 Objective Controller"]},{"className":"ModuleScript","properties":{"Archivable":true,"LinkedSource":""},"rawBytes":16481,"rawSHA256":"84c3edb8eff60ab023f5c7d9d5f608b324f92fb634dacfe2afc84b02d8d1f596","segments":["ServerScriptService","Level 2 Systems","Level 2 Pool Foam Animation Adapter"]},{"className":"ModuleScript","properties":{"Archivable":true,"LinkedSource":""},"rawBytes":16193,"rawSHA256":"17a5cd900d64960f6f2895b5a5add6569e9e47c8339662371385b0b12654b1f6","segments":["ServerScriptService","Level 2 Systems","Level 2 Pool Foam Configuration"]},{"className":"ModuleScript","properties":{"Archivable":true,"LinkedSource":""},"rawBytes":99086,"rawSHA256":"25141362d024adc588e9f7ed07d882b446059f42d931db26983b07d2ccb5d472","segments":["ServerScriptService","Level 2 Systems","Level 2 Pool Foam Controller"]},{"className":"ModuleScript","properties":{"Archivable":true,"LinkedSource":""},"rawBytes":124369,"rawSHA256":"3af9563be049c290b3ac9877cca94e8679bf8a9094eebd999a84b7d932a604e8","segments":["ServerScriptService","Level 2 Systems","Level 2 Pool Foam Navigator"]},{"className":"ModuleScript","properties":{"Archivable":true,"LinkedSource":""},"rawBytes":17971,"rawSHA256":"3f50361755427bf9438f5f2d43961348d646eda41ac060ae0754595ad2c6c4dc","segments":["ServerScriptService","Level 2 Systems","Level 2 Pool Foam Observer"]},{"className":"ModuleScript","properties":{"Archivable":true,"LinkedSource":""},"rawBytes":11278,"rawSHA256":"759d388240f4079f06d06282923f76da8bbf0023af6d79415be48eb5d6a62a9a","segments":["ServerScriptService","Level 2 Systems","Level 2 Pool Foam Proxy Factory"]},{"className":"ModuleScript","properties":{"Archivable":true,"LinkedSource":""},"rawBytes":691,"rawSHA256":"600ff29d74a931b358d4817506f5aaee2e046a26f25aecf5367a312d8f267703","segments":["ServerScriptService","Level 2 Systems","Level 2 Pool Slide Configuration"]},{"className":"ModuleScript","properties":{"Archivable":true,"LinkedSource":""},"rawBytes":41664,"rawSHA256":"69275a49cf43bb2174cda313fdb3ad41f13f8efb5ee6bb04acbc1811c211e44c","segments":["ServerScriptService","Level 2 Systems","Level 2 Pool Slide Controller"]},{"className":"ModuleScript","properties":{"Archivable":true,"LinkedSource":""},"rawBytes":138829,"rawSHA256":"ab318044f367b69dc643c065f81f549c0c22e7c903bdd01cb398f4a07ad95549","segments":["ServerScriptService","Level 2 Systems","Level 2 Pool Slide Navigator"]},{"className":"ModuleScript","properties":{"Archivable":true,"LinkedSource":""},"rawBytes":7632,"rawSHA256":"aa78235250c8aa39bef76b2136f6452b6f1915115b44c97876026d3a092192b1","segments":["ServerScriptService","Level 2 Systems","Level 2 Pool Slide Rig Adapter"]},{"className":"ModuleScript","properties":{"Archivable":true,"LinkedSource":""},"rawBytes":22302,"rawSHA256":"8608150767d697f3f6fda087748bc2b31ddb2a67c552d14922cd46b75c556cfa","segments":["ServerScriptService","Level 2 Systems","Level 2 Poolrooms Runtime"]},{"className":"ModuleScript","properties":{"Archivable":true,"LinkedSource":""},"rawBytes":9496,"rawSHA256":"6f77656fb77fb4ee10053b5e6ea0eb5d3313e4ed5fda08b8694eea3ff06c7dd9","segments":["ServerScriptService","Level 2 Systems","Level 2 Round Adapter"]},{"className":"Script","properties":{"Archivable":true,"Disabled":false,"Enabled":true,"LinkedSource":"","RunContext":"Enum.RunContext.Legacy"},"rawBytes":22185,"rawSHA256":"8b7a60f37ea7c4687be0063d15e4e8d3852b56421e94219fa33890c89c09c689","segments":["ServerScriptService","Level 2 Systems","Level 2 Slide Ragdoll Service"]},{"className":"ModuleScript","properties":{"Archivable":true,"LinkedSource":""},"rawBytes":263658,"rawSHA256":"d74c6a33207209df2c7e546b3d4f1527918c04019639f37283f2ad8cd3d43537","segments":["ServerScriptService","Level 2 Systems","Level 2 World Builder"]},{"className":"ModuleScript","properties":{"Archivable":true,"LinkedSource":""},"rawBytes":8054,"rawSHA256":"bbf8d3b22ab76891958b1180ac41ab8a01faaaf2a261f9e7e3b09a5c97929941","segments":["ServerScriptService","Level 2 Systems","README - LEVEL 2 POOL FOAM"]},{"className":"ModuleScript","properties":{"Archivable":true,"LinkedSource":""},"rawBytes":5828,"rawSHA256":"6992c8687051748f053a7a1c0312a5a8c2700c75905f58dc278eaf51cbbd7c98","segments":["ServerScriptService","Level 2 Systems","README - LEVEL 2 TWEAKS"]},{"className":"ModuleScript","properties":{"Archivable":true,"LinkedSource":""},"rawBytes":2965,"rawSHA256":"870130d1282ed11df29998e286221a6597cc8d9e40e62baad5f957d020dfc72c","segments":["ServerScriptService","Level 3 Kit Warmup"]},{"className":"ModuleScript","properties":{"Archivable":true,"LinkedSource":""},"rawBytes":12479,"rawSHA256":"81118f18a222559da860961d23727b876a46298d12609d91c3fbd460425e2ce6","segments":["ServerScriptService","Level 3 Systems","Level 3 Balloon Dressing"]},{"className":"ModuleScript","properties":{"Archivable":true,"LinkedSource":""},"rawBytes":19831,"rawSHA256":"76752edb0cb176b14f98c41478f4858efbfaed31c2f1d90db82fdad901d08500","segments":["ServerScriptService","Level 3 Systems","Level 3 Configuration"]},{"className":"ModuleScript","properties":{"Archivable":true,"LinkedSource":""},"rawBytes":8896,"rawSHA256":"19a59fc800920a881463159c0f724179671355936e4cfca2e8b2fd588e1a6911","segments":["ServerScriptService","Level 3 Systems","Level 3 Crayon Wall Art"]},{"className":"ModuleScript","properties":{"Archivable":true,"LinkedSource":""},"rawBytes":27072,"rawSHA256":"5b7f7df412af8d7292687a25064f04fcdd10bf93e52ee72ea33efa95477b90f7","segments":["ServerScriptService","Level 3 Systems","Level 3 Hiding Controller"]},{"className":"ModuleScript","properties":{"Archivable":true,"LinkedSource":""},"rawBytes":47577,"rawSHA256":"cf309386c0cd5aef85c3f8208ea28d51f2c8206d27019d86e4d58902f2cc325f","segments":["ServerScriptService","Level 3 Systems","Level 3 Layout Generator"]},{"className":"ModuleScript","properties":{"Archivable":true,"LinkedSource":""},"rawBytes":194657,"rawSHA256":"3b8e0734183af35e2aba7b258cd0e3c87c377cb9d323f4a5586bcb06f6663b3e","segments":["ServerScriptService","Level 3 Systems","Level 3 Mall Manager AI Controller"]},{"className":"ModuleScript","properties":{"Archivable":true,"LinkedSource":""},"rawBytes":20901,"rawSHA256":"803c62833b63d7b2a4f45216c782087ee7b526140399a3bf27cdb31585e1f5a1","segments":["ServerScriptService","Level 3 Systems","Level 3 Music Sequence Controller"]},{"className":"ModuleScript","properties":{"Archivable":true,"LinkedSource":""},"rawBytes":75471,"rawSHA256":"195c1bb7bfb87aad6172dfedeb66fb146938462cb31f65eb4cbe43c9b9ba1cf7","segments":["ServerScriptService","Level 3 Systems","Level 3 Objective Controller"]},{"className":"ModuleScript","properties":{"Archivable":true,"LinkedSource":""},"rawBytes":32558,"rawSHA256":"bfb6470711f716e4ea94c25fd3d3ac45bf6e6cc85eb50418c7e1aac61e566ef1","segments":["ServerScriptService","Level 3 Systems","Level 3 Round Adapter"]},{"className":"ModuleScript","properties":{"Archivable":true,"LinkedSource":""},"rawBytes":204479,"rawSHA256":"6c67aace5c22ab1eb62381d864cd2c328e8762756390f43a0aadf2f9d96eab75","segments":["ServerScriptService","Level 3 Systems","Level 3 Test Suite"]},{"className":"ModuleScript","properties":{"Archivable":true,"LinkedSource":""},"rawBytes":114103,"rawSHA256":"41b4e318bfaf693d95cdba96f4378524496884a236e74fbdb66ef03904afb1c8","segments":["ServerScriptService","Level 3 Systems","Level 3 World Builder"]},{"className":"ModuleScript","properties":{"Archivable":true,"LinkedSource":""},"rawBytes":18179,"rawSHA256":"89fc2abec94362a1759d572346513092c72d718a780b3da679712ced0df6b53b","segments":["ServerScriptService","Level 3 Systems","Level 3 Worn Party Room Dressing"]},{"className":"ModuleScript","properties":{"Archivable":true,"LinkedSource":""},"rawBytes":30505,"rawSHA256":"0b5d4034c3a9016f6e4405024d713244ad936cf97988f13e03296ed016b39035","segments":["ServerScriptService","Level 3 Systems","Level 3 Worn Party Visual Adapter"]},{"className":"ModuleScript","properties":{"Archivable":true,"LinkedSource":""},"rawBytes":7425,"rawSHA256":"af6225d22fb998db4cd2417cd552f934c75ff2c82cb223c4dd9e27daefd98aa6","segments":["ServerScriptService","Level 4 Systems","Level 4 Configuration"]},{"className":"ModuleScript","properties":{"Archivable":true,"LinkedSource":""},"rawBytes":16515,"rawSHA256":"5952c86feb05085642a9fd27cce02332c96da3f7d3ebb09ab5d1ae46cbafc861","segments":["ServerScriptService","Level 4 Systems","Level 4 Light Director"]},{"className":"ModuleScript","properties":{"Archivable":true,"LinkedSource":""},"rawBytes":50254,"rawSHA256":"a01afa1615437ecec70f7b77acef4b1ad3feb30ba11c2d040f01bc1ace9bb9c2","segments":["ServerScriptService","Level 4 Systems","Level 4 Objective Controller"]},{"className":"ModuleScript","properties":{"Archivable":true,"LinkedSource":""},"rawBytes":6821,"rawSHA256":"59f1cd5e87c72c89a60e0f1c4119a5d931b9084ba9689df1e1b94f06a3869335","segments":["ServerScriptService","Level 4 Systems","Level 4 Test Suite"]},{"className":"ModuleScript","properties":{"Archivable":true,"LinkedSource":""},"rawBytes":34659,"rawSHA256":"ec4252424a0a513ca370851a5ff45b212bab4c2bfcbe20cba58c0a740a2b2a2f","segments":["ServerScriptService","Level 4 Systems","Level 4 Usher Controller"]},{"className":"ModuleScript","properties":{"Archivable":true,"LinkedSource":""},"rawBytes":370812,"rawSHA256":"a0ebc21544cf40e7a8d8280dc431ce65b396473b8c9b3cb5ae43fe4cbd3d60e5","segments":["ServerScriptService","Level 4 Systems","Level 4 Usher Nav"]},{"className":"ModuleScript","properties":{"Archivable":true,"LinkedSource":""},"rawBytes":12529,"rawSHA256":"884dbd28fea79343f03ff8c41827e76b049334fabc612e17bd7bcb9e518dade8","segments":["ServerScriptService","Level 6 Systems","Level 6 Balloon Dressing"]},{"className":"ModuleScript","properties":{"Archivable":true,"LinkedSource":""},"rawBytes":19430,"rawSHA256":"b4501e2e9a0f7110d2c23ef28f602be198f0ff5288d3ff1a35133a4352795d38","segments":["ServerScriptService","Level 6 Systems","Level 6 Configuration"]},{"className":"ModuleScript","properties":{"Archivable":true,"LinkedSource":""},"rawBytes":8896,"rawSHA256":"3df3174cde7c5d2cabff90f2425bd0034a769ed3705545c2a5f0f1ebac133fb2","segments":["ServerScriptService","Level 6 Systems","Level 6 Crayon Wall Art"]},{"className":"ModuleScript","properties":{"Archivable":true,"LinkedSource":""},"rawBytes":25600,"rawSHA256":"3592e7bef181cbc80cd1f0e7e4d89126a76bdb554b6a0c7c6594cfbbf2a9249b","segments":["ServerScriptService","Level 6 Systems","Level 6 Hiding Controller"]},{"className":"ModuleScript","properties":{"Archivable":true,"LinkedSource":""},"rawBytes":31504,"rawSHA256":"468845e712b1cfdb5604f5df2a33fb1f0512aab635ce7733ec1dfb529edc822d","segments":["ServerScriptService","Level 6 Systems","Level 6 Kit Metadata"]},{"className":"ModuleScript","properties":{"Archivable":true,"LinkedSource":""},"rawBytes":47446,"rawSHA256":"cfb3b3106fc12125651ed9a3d85841838857021ea72e92307f36aec752781d01","segments":["ServerScriptService","Level 6 Systems","Level 6 Layout Generator"]},{"className":"ModuleScript","properties":{"Archivable":true,"LinkedSource":""},"rawBytes":188782,"rawSHA256":"c26ccd488f2875d7316b8c1fa5cbaba901b67c54f17a8e24a915cd522c00f914","segments":["ServerScriptService","Level 6 Systems","Level 6 Mall Manager AI Controller"]},{"className":"ModuleScript","properties":{"Archivable":true,"LinkedSource":""},"rawBytes":21426,"rawSHA256":"981f70c781cf0f2906bd869ea8e9c00f689685d00d8da65203ea83c6087c26a0","segments":["ServerScriptService","Level 6 Systems","Level 6 Music Sequence Controller"]},{"className":"ModuleScript","properties":{"Archivable":true,"LinkedSource":""},"rawBytes":72634,"rawSHA256":"34bb18d65b31395271dde6a8d09e60283bfcf05092b1842917462474e4fd8e28","segments":["ServerScriptService","Level 6 Systems","Level 6 Objective Controller"]},{"className":"ModuleScript","properties":{"Archivable":true,"LinkedSource":""},"rawBytes":105852,"rawSHA256":"d03ffa84eab839acf755b3e95399853707bfc354d0a464acb188ee2a68186be6","segments":["ServerScriptService","Level 6 Systems","Level 6 Playground Game"]},{"className":"ModuleScript","properties":{"Archivable":true,"LinkedSource":""},"rawBytes":18364,"rawSHA256":"a5a16e313fe93686666ef9de3eed498b95b381c20f43b1b34a67855ce656455f","segments":["ServerScriptService","Level 6 Systems","Level 6 Room Dressing"]},{"className":"ModuleScript","properties":{"Archivable":true,"LinkedSource":""},"rawBytes":23744,"rawSHA256":"18551739c7a6b25b71ce1f5a9f3514c924b25b799e8b724552af4f9859c16ecc","segments":["ServerScriptService","Level 6 Systems","Level 6 Visual Adapter"]},{"className":"ModuleScript","properties":{"Archivable":true,"LinkedSource":""},"rawBytes":102901,"rawSHA256":"a5bad2b19ce4d4d8915b58f50c100f6d31e94f71cd53acabdfee9bb014ae1917","segments":["ServerScriptService","Level 6 Systems","Level 6 World Builder"]},{"className":"ModuleScript","properties":{"Archivable":true,"LinkedSource":""},"rawBytes":10474,"rawSHA256":"a027c4bbe3965368c67921b814d1f1c2e8ce96e088393b7d224b6b837219c1bc","segments":["ServerScriptService","Level 6 Systems","Level6BlenderRuntimeBake"]},{"className":"Script","properties":{"Archivable":true,"Disabled":false,"Enabled":true,"LinkedSource":"","RunContext":"Enum.RunContext.Legacy"},"rawBytes":15171,"rawSHA256":"710ed195de3f6c24ba59682597857514cf34053e9018afee60a373a67011d159","segments":["ServerScriptService","Level Leaderboards"]},{"className":"ModuleScript","properties":{"Archivable":true,"LinkedSource":""},"rawBytes":427,"rawSHA256":"b5edbf084450ddc309845668e1dc9f8df79af9e5edd94b827dbf6c1cd4040b76","segments":["ServerScriptService","Level2Generator"]},{"className":"ModuleScript","properties":{"Archivable":true,"LinkedSource":""},"rawBytes":437,"rawSHA256":"3395a2c38e9de3e6b99568545fd1b5d719d8aa5d4e4cb5c2da3f0a6ada0da07d","segments":["ServerScriptService","Level3Generator"]},{"className":"ModuleScript","properties":{"Archivable":true,"LinkedSource":""},"rawBytes":15758,"rawSHA256":"e52aedfa7ca13f98af4a4381fedd8ed87ca818c638e65872d0be533119077566","segments":["ServerScriptService","Level4RoundGenerator"]},{"className":"Script","properties":{"Archivable":true,"Disabled":false,"Enabled":true,"LinkedSource":"","RunContext":"Enum.RunContext.Legacy"},"rawBytes":69763,"rawSHA256":"0ba8eeef1d824195f6fd69abe899bd04471581e3de853503f1beb8783273cfef","segments":["ServerScriptService","Level5PreviewAccess"]},{"className":"Script","properties":{"Archivable":true,"Disabled":false,"Enabled":true,"LinkedSource":"","RunContext":"Enum.RunContext.Legacy"},"rawBytes":35534,"rawSHA256":"62c22dbcde5c87ff6d0054be7d60a0890298ed5ebb9b1bf6f61e431f45e38655","segments":["ServerScriptService","Level6PreviewAccess"]},{"className":"ModuleScript","properties":{"Archivable":true,"LinkedSource":""},"rawBytes":1205,"rawSHA256":"42a3baf2011c779ab72e8e6ff71eda8add9da05e2ac0cb44c79ec91de323bc7a","segments":["ServerScriptService","LevelWorldStorage"]},{"className":"Script","properties":{"Archivable":true,"Disabled":false,"Enabled":true,"LinkedSource":"","RunContext":"Enum.RunContext.Legacy"},"rawBytes":10109,"rawSHA256":"e93da983c1dc485dbe6435cf9cb09feb7f773167967d043f4473b9db8b262e00","segments":["ServerScriptService","Live Level Server"]},{"className":"Script","properties":{"Archivable":true,"Disabled":false,"Enabled":true,"LinkedSource":"","RunContext":"Enum.RunContext.Legacy"},"rawBytes":8235,"rawSHA256":"34844a50d05b1840e591863f77f5861f982dcd48b4b1344d33632bef93eb294c","segments":["ServerScriptService","Lobby DJ"]},{"className":"Script","properties":{"Archivable":true,"Disabled":false,"Enabled":true,"LinkedSource":"","RunContext":"Enum.RunContext.Legacy"},"rawBytes":18870,"rawSHA256":"db9b3b4c8b8180a476b1ce5e8a6ddb061049109e4bc6585e4acf999a30d39bce","segments":["ServerScriptService","Lobby Tunnel Reach"]},{"className":"Script","properties":{"Archivable":true,"Disabled":false,"Enabled":true,"LinkedSource":"","RunContext":"Enum.RunContext.Legacy"},"rawBytes":7124,"rawSHA256":"790fad57bf00234e1ae66656227b8949b1917be257b3d4c3647b4e519d41c92c","segments":["ServerScriptService","LobbyPartyModeController"]},{"className":"Script","properties":{"Archivable":true,"Disabled":false,"Enabled":true,"LinkedSource":"","RunContext":"Enum.RunContext.Legacy"},"rawBytes":2072,"rawSHA256":"997e0052ad6e0f5418be32493f7b16ad833f7cdc9e6ae0ee54b5a48fca05901a","segments":["ServerScriptService","LobbyReimaginedPreview","Bootstrap"]},{"className":"ModuleScript","properties":{"Archivable":true,"LinkedSource":""},"rawBytes":54562,"rawSHA256":"efd4d294e896e6a319211a791267470cf3378854447f56fbdf9c5044d5938e4b","segments":["ServerScriptService","LobbyReimaginedPreview","Builder"]},{"className":"ModuleScript","properties":{"Archivable":true,"LinkedSource":""},"rawBytes":5885,"rawSHA256":"398525b604d917c7c47ddcc20ae886e140fd0e21a5f534ccb80ae720ceb47957","segments":["ServerScriptService","LobbyReimaginedPreview","DevBayAccessGuard"]},{"className":"ModuleScript","properties":{"Archivable":true,"LinkedSource":""},"rawBytes":67522,"rawSHA256":"5c120357fad94d1274a7eb6e39c6ce0cbf996505246b3b6b5c68d3dfa5cff98a","segments":["ServerScriptService","LobbyReimaginedPreview","EndBlockades"]},{"className":"ModuleScript","properties":{"Archivable":true,"LinkedSource":""},"rawBytes":10428,"rawSHA256":"534482ac3380b2d3070fd7e4aec9ae9197e2d3b2e06a32a5e692888047aa770e","segments":["ServerScriptService","LobbyReimaginedPreview","LobbyPolishBays"]},{"className":"ModuleScript","properties":{"Archivable":true,"LinkedSource":""},"rawBytes":15812,"rawSHA256":"9dd927b5927249b42655c297d96a24a06c581c6fa9f01adac0ce7cde4e40746d","segments":["ServerScriptService","LobbyReimaginedPreview","LobbyPolishScene"]},{"className":"ModuleScript","properties":{"Archivable":true,"LinkedSource":""},"rawBytes":22848,"rawSHA256":"6b4ef80ea746c39c900c59f6311ad1f7ea862cb20b24aa1aaab85816ec71c54e","segments":["ServerScriptService","LobbyReimaginedPreview","MaterialPolish"]},{"className":"ModuleScript","properties":{"Archivable":true,"LinkedSource":""},"rawBytes":22645,"rawSHA256":"6c7135608842a9a2ca5b7588d7c1327dddd768f6b71e31900f7f757b44a092c5","segments":["ServerScriptService","LobbyReimaginedPreview","QueueBridge"]},{"className":"ModuleScript","properties":{"Archivable":true,"LinkedSource":""},"rawBytes":12341,"rawSHA256":"1f564fdde835ad89b529d9069ddf87b0ed4991636f363eacbd098cc0b342ff28","segments":["ServerScriptService","LobbyReimaginedPreview","RuntimeBake"]},{"className":"ModuleScript","properties":{"Archivable":true,"LinkedSource":""},"rawBytes":24220,"rawSHA256":"bd78855f31e75194e6a52bb3accc796aa26b739945904c9ee05cb91b5c7888f7","segments":["ServerScriptService","LobbyShopDisplay"]},{"className":"Script","properties":{"Archivable":true,"Disabled":false,"Enabled":true,"LinkedSource":"","RunContext":"Enum.RunContext.Legacy"},"rawBytes":24422,"rawSHA256":"d04548421adab66453a12a5cc829d0810a96e096a55bac0d2bfbd4d1b59f245d","segments":["ServerScriptService","LunaTribute"]},{"className":"ModuleScript","properties":{"Archivable":true,"LinkedSource":""},"rawBytes":2197,"rawSHA256":"0576d8028780dbaa9af52a04729a12d4083b71223a5c2225d0bc462604b2c6d7","segments":["ServerScriptService","NoiseRegistry"]},{"className":"ModuleScript","properties":{"Archivable":true,"LinkedSource":""},"rawBytes":7408,"rawSHA256":"0447ca2a84e9d7f9e4c997c1eafdf450bd0c262ee69d4b0db24f3f8c26a80b2b","segments":["ServerScriptService","PlayerProtection"]},{"className":"ModuleScript","properties":{"Archivable":true,"LinkedSource":""},"rawBytes":6278,"rawSHA256":"f9de2995a607bd6101738acd4b955b8ba4d407c85c91a8111dd44dab032c9fd2","segments":["ServerScriptService","PurchaseAlerts"]},{"className":"ModuleScript","properties":{"Archivable":true,"LinkedSource":""},"rawBytes":4473,"rawSHA256":"df169b0af66304a6216d5448464254987f2a59cd0cc44bb6bbe9d218443eef9c","segments":["ServerScriptService","ReentryPlacement"]},{"className":"ModuleScript","properties":{"Archivable":true,"LinkedSource":""},"rawBytes":76041,"rawSHA256":"cba82006005ee3b0ff64dffca769839ba863048ecc973dd461ab3bc89aff5960","segments":["ServerScriptService","Round Completion Routing"]},{"className":"ModuleScript","properties":{"Archivable":true,"LinkedSource":""},"rawBytes":135637,"rawSHA256":"7a79483f659df16b76837a01e20d06f895c1f3e142aa96b4138f5072be4018a0","segments":["ServerScriptService","Round Completion Test Suite"]},{"className":"ModuleScript","properties":{"Archivable":true,"LinkedSource":""},"rawBytes":8712,"rawSHA256":"e45e4943448ad99ef9c7bd4861e1e5fa18969523730c78146c4cb886a5c7debd","segments":["ServerScriptService","Round Loading Runtime"]},{"className":"ModuleScript","properties":{"Archivable":true,"LinkedSource":""},"rawBytes":15550,"rawSHA256":"d82beaefcced451556031a8dcd0c5d9a47ef47057918c728a283ace762f70c5b","segments":["ServerScriptService","Round Loading Test Suite"]},{"className":"Script","properties":{"Archivable":true,"Disabled":false,"Enabled":true,"LinkedSource":"","RunContext":"Enum.RunContext.Legacy"},"rawBytes":12066,"rawSHA256":"1f37b265e7cbb8fe9de76231e7f4ccf9eded7ec4cd3981d08694c196a8ddccb7","segments":["ServerScriptService","RouteMarkerService"]},{"className":"ModuleScript","properties":{"Archivable":true,"LinkedSource":""},"rawBytes":8031,"rawSHA256":"f402876ad679c6f324368342239db8d850d2a8e18faf378051556e1ec3dcc31c","segments":["ServerScriptService","ServerKind"]},{"className":"ModuleScript","properties":{"Archivable":true,"LinkedSource":""},"rawBytes":1279,"rawSHA256":"4e5f91990b1d2cddcca1310ef877f709cf308ef450d43ff48b4399b0d1cd40b2","segments":["ServerScriptService","TeamObjectives"]},{"className":"ModuleScript","properties":{"Archivable":true,"LinkedSource":""},"rawBytes":118461,"rawSHA256":"ee5ef0360a0e2e45ed0af25ade662e8ac6fd6fb8c1b5e6bd7f9b8c266bc83e1a","segments":["ServerScriptService","TunnelLobbyBuilder"]},{"className":"ModuleScript","properties":{"Archivable":true,"LinkedSource":""},"rawBytes":19089,"rawSHA256":"b966bf4298d13e57bd8ef6a9a041c63175f5ed6e80487a819e8d4ae1d29df818","segments":["ServerScriptService","ZyntraAnalytics"]},{"className":"ModuleScript","properties":{"Archivable":true,"LinkedSource":""},"rawBytes":1819,"rawSHA256":"aed8a9a492ea2ce58ad112e3806873a6730d7b3d8906470888350b47772f05ab","segments":["ServerScriptService","ZyntraDetectorSensing"]},{"className":"Script","properties":{"Archivable":true,"Disabled":false,"Enabled":true,"LinkedSource":"","RunContext":"Enum.RunContext.Legacy"},"rawBytes":4366,"rawSHA256":"ff79be5f3812aa0c2c932c87edf50ca8d31e89a3d780530722e8fea82b74eb8e","segments":["ServerScriptService","ZyntraDetectorService"]},{"className":"Script","properties":{"Archivable":true,"Disabled":false,"Enabled":true,"LinkedSource":"","RunContext":"Enum.RunContext.Legacy"},"rawBytes":215340,"rawSHA256":"2b9194ab62391f61b2ec7292d8d3c10bfe798adf1922c5959b44a62e749b18af","segments":["ServerScriptService","ZyntraMonetization"]},{"className":"LocalScript","properties":{"Archivable":true,"Disabled":true,"Enabled":false,"LinkedSource":"","RunContext":"Enum.RunContext.Legacy"},"rawBytes":9288,"rawSHA256":"75162f7219bc5966ff5ee367360338a5d56356f085529e4188fc41f51f239c72","segments":["ServerStorage","Archive","FieldNotesRetired_20260922","Field Notes Client"]},{"className":"Script","properties":{"Archivable":true,"Disabled":true,"Enabled":false,"LinkedSource":"","RunContext":"Enum.RunContext.Legacy"},"rawBytes":21612,"rawSHA256":"a0aed81a20ee24e8a1f1413a09e75fd001281ae639ea4cb8e9cb9f55b69b0bcd","segments":["ServerStorage","Archive","FieldNotesRetired_20260922","FieldNotesService"]},{"className":"ModuleScript","properties":{"Archivable":true,"LinkedSource":""},"rawBytes":7373,"rawSHA256":"7734ab1c871eee83d85bf7712f413bc72ea728ff9b4eccfad2349a1647409f18","segments":["ServerStorage","Archive","FieldNotesRetired_20260922","ZyntraFieldNotes"]},{"className":"ModuleScript","properties":{"Archivable":true,"LinkedSource":""},"rawBytes":16492,"rawSHA256":"71457d7ecb83dff9e7999cc8cf75203c4ec14bb78a4e1a3f6ea08fb9794af7f0","segments":["ServerStorage","Archive","FieldNotesRetired_20260922","ZyntraFieldNotesPage"]},{"className":"ModuleScript","properties":{"Archivable":true,"LinkedSource":""},"rawBytes":84738,"rawSHA256":"380beb91a4623994c5e86b2c956eb9c68033d4df9fa0e9b4844ff451da9047b0","segments":["ServerStorage","Archive","Level 2 Kids Skylight Backup 20260806","Level 2 World Builder Before Kids Skylights"]},{"className":"ModuleScript","properties":{"Archivable":true,"LinkedSource":""},"rawBytes":69618,"rawSHA256":"8971886166a1fa4a79671c35f533589b13ba5a36449f1134ad73018b0db61328","segments":["ServerStorage","Archive","Level 2 Kids Texture Backup 20260806","Level 2 World Builder Before Kids Textures"]},{"className":"ModuleScript","properties":{"Archivable":true,"LinkedSource":""},"rawBytes":5803,"rawSHA256":"d24bd2185aead26ced59abb64f639f61494457642b6323943ce32d67f4bf2c6f","segments":["ServerStorage","Archive","Level 2 Kids V1 Backup 20260811","Level 2 Configuration"]},{"className":"ModuleScript","properties":{"Archivable":true,"LinkedSource":""},"rawBytes":97093,"rawSHA256":"fdc69a799166da1f1b6324a8e09766d67fec298985d3408eb1d80685bba340d1","segments":["ServerStorage","Archive","Level 2 Kids V1 Backup 20260811","Level 2 World Builder"]},{"className":"ModuleScript","properties":{"Archivable":true,"LinkedSource":""},"rawBytes":5926,"rawSHA256":"24cec1cebf1816fd727c70992588c96d89c92432f2aa53b777a920d2002b529c","segments":["ServerStorage","Archive","Level 2 Lever Redesign Backup 20260806","Level 2 Configuration"]},{"className":"ModuleScript","properties":{"Archivable":true,"LinkedSource":""},"rawBytes":7391,"rawSHA256":"c9a9847ad63b338abba95480a1cbe09d8e8f9f4651282551c85f1cfe870a520d","segments":["ServerStorage","Archive","Level 2 Lever Redesign Backup 20260806","Level 2 Objective Controller"]},{"className":"ModuleScript","properties":{"Archivable":true,"LinkedSource":""},"rawBytes":58002,"rawSHA256":"4fca985383c272391f20ec44524c257f6e539a698b6480ddb5d4ec591e6aa046","segments":["ServerStorage","Archive","Level 2 Lever Redesign Backup 20260806","Level 2 World Builder"]},{"className":"ModuleScript","properties":{"Archivable":true,"LinkedSource":""},"rawBytes":68535,"rawSHA256":"343bcc9bf8bffcd225f1692ac722971c3e1d2e9551ba059614a8f3fd7387417b","segments":["ServerStorage","Archive","Level 2 Pump Scale Backup 20260806","Level 2 World Builder Before 40 Percent Reduction"]},{"className":"ModuleScript","properties":{"Archivable":true,"LinkedSource":""},"rawBytes":9801,"rawSHA256":"8befab8a370d8e8c325243136e4ef624c548ffd54e4d54b07b5c169633e4d90a","segments":["ServerStorage","Archive","Level2AudioBackup_20260831_NoDistantSplash","Level 2 Configuration"]},{"className":"LocalScript","properties":{"Archivable":true,"Disabled":false,"Enabled":true,"LinkedSource":"","RunContext":"Enum.RunContext.Legacy"},"rawBytes":26598,"rawSHA256":"2b8c34b1b886f3ec85f303b8666ac6e69bfd8ebf9110ac61ae31804e7d67e0cd","segments":["ServerStorage","Archive","Level2AudioBackup_20260831_NoDistantSplash","Level 2 Sound Controller"]},{"className":"LocalScript","properties":{"Archivable":true,"Disabled":true,"Enabled":false,"LinkedSource":"","RunContext":"Enum.RunContext.Legacy"},"rawBytes":9372,"rawSHA256":"1f6f81df549b4cecfaaf83490c7f61dc0a2182f6cf1208ac2af4010e745f762d","segments":["ServerStorage","Archive","Level2RetiredSlidemouth_20260831","Level 2 Slidemouth Client"]},{"className":"ModuleScript","properties":{"Archivable":true,"LinkedSource":""},"rawBytes":167166,"rawSHA256":"a2f0d1ed7e8b28de5803dccef88d517fbf61b9c255ec331c3c0db42b60652118","segments":["ServerStorage","Archive","Level2RetiredSlidemouth_20260831","Level 2 Slidemouth Controller"]},{"className":"ModuleScript","properties":{"Archivable":true,"LinkedSource":""},"rawBytes":295599,"rawSHA256":"c3f183e46ae15fbbd6eb1b20d91291b0f1038a08cec43f89a4f19c7cd09f41bf","segments":["ServerStorage","Archive","Level2RetiredSlidemouth_20260831","Level 2 Slidemouth Test Suite"]},{"className":"Script","properties":{"Archivable":true,"Disabled":false,"Enabled":true,"LinkedSource":"","RunContext":"Enum.RunContext.Legacy"},"rawBytes":2250,"rawSHA256":"19d0da27795704865d9b179ea3818ad56425607937a97b4259af336f4e4f2b4b","segments":["ServerStorage","Archive","RetiredLobbyAssets","Miso","MisoPatrol"]},{"className":"Script","properties":{"Archivable":true,"Disabled":false,"Enabled":true,"LinkedSource":"","RunContext":"Enum.RunContext.Legacy"},"rawBytes":7028,"rawSHA256":"58a68c6b32aa9e7aa03f5cf2649e7ccbaf70b88db991e2061b6558ac66add55c","segments":["ServerStorage","Level 4 Cinema Blender","Doors","PushDoors"]},{"className":"Script","properties":{"Archivable":true,"Disabled":false,"Enabled":true,"LinkedSource":"","RunContext":"Enum.RunContext.Client"},"rawBytes":6158,"rawSHA256":"d7f63f21b4a827e4fcc91e0246424438fa871aa7f90013b8599ef18a51d64991","segments":["ServerStorage","Level 4 Cinema Blender","OccasionalFixtureFlicker"]},{"className":"LocalScript","properties":{"Archivable":true,"Disabled":true,"Enabled":false,"LinkedSource":"","RunContext":"Enum.RunContext.Legacy"},"rawBytes":167,"rawSHA256":"4095140216ad0d9515e60d4697c207f537da5a11847fda2421995c4fe03194da","segments":["ServerStorage","Project Mirror","IMPORTANT"]},{"className":"Script","properties":{"Archivable":true,"Disabled":false,"Enabled":true,"LinkedSource":"","RunContext":"Enum.RunContext.Legacy"},"rawBytes":235,"rawSHA256":"e583992400de7c9bafd421907b8b33f1a6aaa859526e64282702fd70f4a08acf","segments":["ServerStorage","Project Mirror","Script"]},{"className":"LocalScript","properties":{"Archivable":true,"Disabled":false,"Enabled":true,"LinkedSource":"","RunContext":"Enum.RunContext.Legacy"},"rawBytes":28802,"rawSHA256":"49eab7530cfc33b8af13b995ae1fa87f482a489b6d108ec2410d12dd19b720f0","segments":["StarterPlayer","StarterCharacter","Animate"]},{"className":"LocalScript","properties":{"Archivable":true,"Disabled":false,"Enabled":true,"LinkedSource":"","RunContext":"Enum.RunContext.Legacy"},"rawBytes":1539,"rawSHA256":"1adfdded75ae74aba87cb74c69590e55219b2ac9e7f5adc1a7f535cceb39fa8b","segments":["StarterPlayer","StarterCharacterScripts","DanceEmote"]},{"className":"LocalScript","properties":{"Archivable":true,"Disabled":false,"Enabled":true,"LinkedSource":"","RunContext":"Enum.RunContext.Legacy"},"rawBytes":300,"rawSHA256":"b5309d09c60b9fb5ea319c24d34cbdc3b861fdb1726727a608944e528462e66f","segments":["StarterPlayer","StarterCharacterScripts","DisableDefaultWalkingSound"]},{"className":"LocalScript","properties":{"Archivable":true,"Disabled":true,"Enabled":false,"LinkedSource":"","RunContext":"Enum.RunContext.Legacy"},"rawBytes":654,"rawSHA256":"3f84b7c495f091703b0636958f6691c0c2f23c9c7f487e1a3637b3b0e7c37f07","segments":["StarterPlayer","StarterCharacterScripts","SetRunAnimation"]},{"className":"LocalScript","properties":{"Archivable":true,"Disabled":false,"Enabled":true,"LinkedSource":"","RunContext":"Enum.RunContext.Legacy"},"rawBytes":16078,"rawSHA256":"cf4d7e6356197d4609ab105e41b039aed668d96a064684e3874445fd7754e771","segments":["StarterPlayer","StarterPlayerScripts","Achievements Client"]},{"className":"LocalScript","properties":{"Archivable":true,"Disabled":false,"Enabled":true,"LinkedSource":"","RunContext":"Enum.RunContext.Legacy"},"rawBytes":27789,"rawSHA256":"b45d19ac83cb15ecc4a97274e58efda7a14a38cd789d913066e7f12f89e54ffa","segments":["StarterPlayer","StarterPlayerScripts","DevCheats"]},{"className":"LocalScript","properties":{"Archivable":true,"Disabled":false,"Enabled":true,"LinkedSource":"","RunContext":"Enum.RunContext.Legacy"},"rawBytes":12165,"rawSHA256":"2b12a543132bc0af7e624e50559756236f7f1b717bfe764433f6fbea5be81e4b","segments":["StarterPlayer","StarterPlayerScripts","EntityShakeController"]},{"className":"LocalScript","properties":{"Archivable":true,"Disabled":false,"Enabled":true,"LinkedSource":"","RunContext":"Enum.RunContext.Legacy"},"rawBytes":31986,"rawSHA256":"19b514e404b69ac05aa1d635b8d779922f721a3ee055671e1cbfb016a514e788","segments":["StarterPlayer","StarterPlayerScripts","First Entry Guide"]},{"className":"LocalScript","properties":{"Archivable":true,"Disabled":false,"Enabled":true,"LinkedSource":"","RunContext":"Enum.RunContext.Legacy"},"rawBytes":37276,"rawSHA256":"b1b1322a39a3a9a493b265f9317f7ba530f8726d5a2b2dfb294d7b3826dcc3aa","segments":["StarterPlayer","StarterPlayerScripts","FlashlightController"]},{"className":"LocalScript","properties":{"Archivable":true,"Disabled":false,"Enabled":true,"LinkedSource":"","RunContext":"Enum.RunContext.Legacy"},"rawBytes":22328,"rawSHA256":"ca3eaf116eca6398205b1a3e84e6ca4ae1e8455ff471074848d072c9933e8ec0","segments":["StarterPlayer","StarterPlayerScripts","Found Footage HUD"]},{"className":"LocalScript","properties":{"Archivable":true,"Disabled":false,"Enabled":true,"LinkedSource":"","RunContext":"Enum.RunContext.Legacy"},"rawBytes":14668,"rawSHA256":"156a290c6ee54e73ba271438681e70ac2de76f9d1b75d693c684445350aa6562","segments":["StarterPlayer","StarterPlayerScripts","Friend Boost Client"]},{"className":"LocalScript","properties":{"Archivable":true,"Disabled":false,"Enabled":true,"LinkedSource":"","RunContext":"Enum.RunContext.Legacy"},"rawBytes":22483,"rawSHA256":"f5d078e43ea5054252c621c86450867782f5fd504a1bb07c2e0205cfca89df84","segments":["StarterPlayer","StarterPlayerScripts","HazmatSkinDriver"]},{"className":"LocalScript","properties":{"Archivable":true,"Disabled":false,"Enabled":true,"LinkedSource":"","RunContext":"Enum.RunContext.Legacy"},"rawBytes":7088,"rawSHA256":"7e5cedc84631a6af3f7edc126cb6775c9c498f42e851484c4980c3a3a6846a88","segments":["StarterPlayer","StarterPlayerScripts","JumpscareUI"]},{"className":"LocalScript","properties":{"Archivable":true,"Disabled":false,"Enabled":true,"LinkedSource":"","RunContext":"Enum.RunContext.Legacy"},"rawBytes":11661,"rawSHA256":"a2c09bc7e9bba5ebd04462bfd7d0e0dba49f7453cf3a0403dfb0b0db8d7b5651","segments":["StarterPlayer","StarterPlayerScripts","Level 1 Cable Current"]},{"className":"LocalScript","properties":{"Archivable":true,"Disabled":false,"Enabled":true,"LinkedSource":"","RunContext":"Enum.RunContext.Legacy"},"rawBytes":25299,"rawSHA256":"7a4734112fcfee5322766d7c92d9f9eda2054196920e42275de79d3536e1a238","segments":["StarterPlayer","StarterPlayerScripts","Level 1 Entity Motion"]},{"className":"LocalScript","properties":{"Archivable":true,"Disabled":false,"Enabled":true,"LinkedSource":"","RunContext":"Enum.RunContext.Legacy"},"rawBytes":12239,"rawSHA256":"dd27aa5bb7e87e75f54c3d4b0c60340b5037213b078e156a7ea0e980298d83fa","segments":["StarterPlayer","StarterPlayerScripts","Level 1 Hardware Client"]},{"className":"LocalScript","properties":{"Archivable":true,"Disabled":false,"Enabled":true,"LinkedSource":"","RunContext":"Enum.RunContext.Legacy"},"rawBytes":3567,"rawSHA256":"0246c4f92a20dcb448c4e4d6784bf9c96edd43758cff72d30f588e5703777f03","segments":["StarterPlayer","StarterPlayerScripts","Level 1 Sound Controller"]},{"className":"LocalScript","properties":{"Archivable":true,"Disabled":false,"Enabled":true,"LinkedSource":"","RunContext":"Enum.RunContext.Legacy"},"rawBytes":20263,"rawSHA256":"5d6405b2b806e286966c63b0f19959d348ef7b6b6f36f87257afb2ef21b294a8","segments":["StarterPlayer","StarterPlayerScripts","Level 2 Entity Audio"]},{"className":"LocalScript","properties":{"Archivable":true,"Disabled":false,"Enabled":true,"LinkedSource":"","RunContext":"Enum.RunContext.Legacy"},"rawBytes":6313,"rawSHA256":"26ea6117a24bbed904ff0f22fb486148eb34332bd466b84fa19d47d3d6d72b39","segments":["StarterPlayer","StarterPlayerScripts","Level 2 Lighting Controller"]},{"className":"LocalScript","properties":{"Archivable":true,"Disabled":false,"Enabled":true,"LinkedSource":"","RunContext":"Enum.RunContext.Legacy"},"rawBytes":2475,"rawSHA256":"26d18cbc58573adca1d32b0d5004667ea22be0ff90141880177609a79031a733","segments":["StarterPlayer","StarterPlayerScripts","Level 2 Objective UI"]},{"className":"LocalScript","properties":{"Archivable":true,"Disabled":false,"Enabled":true,"LinkedSource":"","RunContext":"Enum.RunContext.Legacy"},"rawBytes":19192,"rawSHA256":"8240023062cb4c0502d187bbddab7fa3dcbeda4b92144ae3a31478d074b4a2de","segments":["StarterPlayer","StarterPlayerScripts","Level 2 Pool Foam Client"]},{"className":"LocalScript","properties":{"Archivable":true,"Disabled":false,"Enabled":true,"LinkedSource":"","RunContext":"Enum.RunContext.Legacy"},"rawBytes":18933,"rawSHA256":"486b6cc4883fa35e55772d80dda456c512d315427efa52f52c49c296883f0f4e","segments":["StarterPlayer","StarterPlayerScripts","Level 2 Poolrooms Ambience"]},{"className":"LocalScript","properties":{"Archivable":true,"Disabled":false,"Enabled":true,"LinkedSource":"","RunContext":"Enum.RunContext.Legacy"},"rawBytes":32214,"rawSHA256":"60489c6dc4f7383fc606b00fda0cea104258c232407b8625bff30c7bdde51181","segments":["StarterPlayer","StarterPlayerScripts","Level 2 Slide Controller"]},{"className":"LocalScript","properties":{"Archivable":true,"Disabled":false,"Enabled":true,"LinkedSource":"","RunContext":"Enum.RunContext.Legacy"},"rawBytes":41930,"rawSHA256":"7a0fe4360e5ffa6871df1e8cdcded6c10dda8efaa4186e7dcba59a9d2b3438e8","segments":["StarterPlayer","StarterPlayerScripts","Level 2 Sound Controller"]},{"className":"LocalScript","properties":{"Archivable":true,"Disabled":false,"Enabled":true,"LinkedSource":"","RunContext":"Enum.RunContext.Legacy"},"rawBytes":47023,"rawSHA256":"a549b23d2d8b201b3d293c889c9efd5fccd4ee13f160b6c0459dd6352ccf49f0","segments":["StarterPlayer","StarterPlayerScripts","Level 3 Lighting Controller"]},{"className":"LocalScript","properties":{"Archivable":true,"Disabled":false,"Enabled":true,"LinkedSource":"","RunContext":"Enum.RunContext.Legacy"},"rawBytes":6548,"rawSHA256":"81309944181cf982fd2eda88291244bde8cdcaf5c2ecbd4c8c0f05f9f733cf37","segments":["StarterPlayer","StarterPlayerScripts","Level 3 Mall Manager Visual Smoother"]},{"className":"LocalScript","properties":{"Archivable":true,"Disabled":false,"Enabled":true,"LinkedSource":"","RunContext":"Enum.RunContext.Legacy"},"rawBytes":35699,"rawSHA256":"560ec623fdc33504d71cf68e62803878748b5ede3053019c189f3b8376be02a5","segments":["StarterPlayer","StarterPlayerScripts","Level 3 Reader Client"]},{"className":"LocalScript","properties":{"Archivable":true,"Disabled":false,"Enabled":true,"LinkedSource":"","RunContext":"Enum.RunContext.Legacy"},"rawBytes":46833,"rawSHA256":"8896ccdacbbd00116686a7f0547059b72e24776c99c119b4c8cd207d0eea3d3b","segments":["StarterPlayer","StarterPlayerScripts","Level 3 Sound Controller"]},{"className":"LocalScript","properties":{"Archivable":true,"Disabled":false,"Enabled":true,"LinkedSource":"","RunContext":"Enum.RunContext.Legacy"},"rawBytes":21498,"rawSHA256":"2fe086d3537da9d720e13b2c5b9c8e89d80117951ccfcbc4e83a5854608df612","segments":["StarterPlayer","StarterPlayerScripts","Level 3 Table Hiding Client"]},{"className":"LocalScript","properties":{"Archivable":true,"Disabled":false,"Enabled":true,"LinkedSource":"","RunContext":"Enum.RunContext.Legacy"},"rawBytes":14048,"rawSHA256":"57ade12fbaee0f8507316b79987b26105f530823ff6eebd427c7330734a3d29a","segments":["StarterPlayer","StarterPlayerScripts","Level 4 Lighting Controller"]},{"className":"LocalScript","properties":{"Archivable":true,"Disabled":false,"Enabled":true,"LinkedSource":"","RunContext":"Enum.RunContext.Legacy"},"rawBytes":49585,"rawSHA256":"6909fa9518d2c6ff5d58f6958871bdf7ec18eb8115118a8311900c04f38bfd27","segments":["StarterPlayer","StarterPlayerScripts","Level 4 Round Client"]},{"className":"LocalScript","properties":{"Archivable":true,"Disabled":false,"Enabled":true,"LinkedSource":"","RunContext":"Enum.RunContext.Legacy"},"rawBytes":46203,"rawSHA256":"7be4083ac513eac0e89d512be2e0caffccee9a0f558f578d184ffec15d077c64","segments":["StarterPlayer","StarterPlayerScripts","Level 5 Lighting Controller"]},{"className":"LocalScript","properties":{"Archivable":true,"Disabled":false,"Enabled":true,"LinkedSource":"","RunContext":"Enum.RunContext.Legacy"},"rawBytes":5003,"rawSHA256":"4195aac0219e5abaca0324a03c2005603bb695cb87b4cb2659e36e419b27db30","segments":["StarterPlayer","StarterPlayerScripts","Level 6 Dev ESP"]},{"className":"LocalScript","properties":{"Archivable":true,"Disabled":false,"Enabled":true,"LinkedSource":"","RunContext":"Enum.RunContext.Legacy"},"rawBytes":66400,"rawSHA256":"08867cb5fbfc46dc91e484ffb302ca06065d14f9d0166a77e8ab10dcf443d7dc","segments":["StarterPlayer","StarterPlayerScripts","Level 6 Playground Client"]},{"className":"LocalScript","properties":{"Archivable":true,"Disabled":true,"Enabled":false,"LinkedSource":"","RunContext":"Enum.RunContext.Legacy"},"rawBytes":59188,"rawSHA256":"156b7f2ef89c50d6ac208c660ecb6c33a67e278500d4996d4c708c51af3b9029","segments":["StarterPlayer","StarterPlayerScripts","Level 6 Reader Client"]},{"className":"LocalScript","properties":{"Archivable":true,"Disabled":true,"Enabled":false,"LinkedSource":"","RunContext":"Enum.RunContext.Legacy"},"rawBytes":46887,"rawSHA256":"dce904e81c3fc07ee8d7136f7510082b1fe60f6244a19aa0ffd96090383d9115","segments":["StarterPlayer","StarterPlayerScripts","Level 6 Sound Controller"]},{"className":"LocalScript","properties":{"Archivable":true,"Disabled":false,"Enabled":true,"LinkedSource":"","RunContext":"Enum.RunContext.Legacy"},"rawBytes":2219,"rawSHA256":"61db652abcb787fb31454fdeea4f906396fd82c99c4818164afedfa3c28f20f4","segments":["StarterPlayer","StarterPlayerScripts","Level2AlertClient"]},{"className":"LocalScript","properties":{"Archivable":true,"Disabled":false,"Enabled":true,"LinkedSource":"","RunContext":"Enum.RunContext.Legacy"},"rawBytes":14900,"rawSHA256":"4283fc7a685893b3e0e62cebdc7520268ebb125760b800bfeb5bb4fff15d12ce","segments":["StarterPlayer","StarterPlayerScripts","Level2PoolroomsPresentation"]},{"className":"LocalScript","properties":{"Archivable":true,"Disabled":false,"Enabled":true,"LinkedSource":"","RunContext":"Enum.RunContext.Legacy"},"rawBytes":1407,"rawSHA256":"e024ae800bea7082e72a590e948c0b54e9db503db70ef24e50f51024726ad4d3","segments":["StarterPlayer","StarterPlayerScripts","Level4PreviewPrompt"]},{"className":"LocalScript","properties":{"Archivable":true,"Disabled":false,"Enabled":true,"LinkedSource":"","RunContext":"Enum.RunContext.Legacy"},"rawBytes":2561,"rawSHA256":"3b660cc8958f45e34413662285d25af841abab53f001daa6da21e1de883daf41","segments":["StarterPlayer","StarterPlayerScripts","Level6PreviewTransport"]},{"className":"LocalScript","properties":{"Archivable":true,"Disabled":false,"Enabled":true,"LinkedSource":"","RunContext":"Enum.RunContext.Legacy"},"rawBytes":18350,"rawSHA256":"5722867c4602ee8d248473dd78f3ce9afe9ec494c8d1767c8a91b7c7d9635163","segments":["StarterPlayer","StarterPlayerScripts","Lobby DJ Client"]},{"className":"LocalScript","properties":{"Archivable":true,"Disabled":false,"Enabled":true,"LinkedSource":"","RunContext":"Enum.RunContext.Legacy"},"rawBytes":31937,"rawSHA256":"11a493d5423d1234eaa20f2ff6248a3807fa7baf0455b7f6f9814d7e190b22c9","segments":["StarterPlayer","StarterPlayerScripts","Lobby Tunnel Reach Client"]},{"className":"LocalScript","properties":{"Archivable":true,"Disabled":false,"Enabled":true,"LinkedSource":"","RunContext":"Enum.RunContext.Legacy"},"rawBytes":7021,"rawSHA256":"fda84a982df70caf1044eee533161d2fe2bd94ed5808701ad1b82acb087fdc4a","segments":["StarterPlayer","StarterPlayerScripts","LobbyCeilingSweeps"]},{"className":"LocalScript","properties":{"Archivable":true,"Disabled":false,"Enabled":true,"LinkedSource":"","RunContext":"Enum.RunContext.Legacy"},"rawBytes":5033,"rawSHA256":"187b2f54577f23dfd40ffcd23624acd1d01fe9e8b37dba58e30cdbc3ddccd80b","segments":["StarterPlayer","StarterPlayerScripts","LobbyLevel3GateFlicker"]},{"className":"LocalScript","properties":{"Archivable":true,"Disabled":false,"Enabled":true,"LinkedSource":"","RunContext":"Enum.RunContext.Legacy"},"rawBytes":10226,"rawSHA256":"77d9d1631cafe4f9c7f2f06ab7fee4b78ea846985215c3672c1e251f688917f6","segments":["StarterPlayer","StarterPlayerScripts","LobbyMusicController"]},{"className":"LocalScript","properties":{"Archivable":true,"Disabled":false,"Enabled":true,"LinkedSource":"","RunContext":"Enum.RunContext.Legacy"},"rawBytes":4848,"rawSHA256":"ecb544ac31e9cc343858a399cab93da1a0a71f861ee519643c7834d7848ae0ac","segments":["StarterPlayer","StarterPlayerScripts","LobbyReimaginedQueueController"]},{"className":"LocalScript","properties":{"Archivable":true,"Disabled":false,"Enabled":true,"LinkedSource":"","RunContext":"Enum.RunContext.Legacy"},"rawBytes":40738,"rawSHA256":"b6405e22690cc004eb2e4d088f4ea541618125dbcdc51a11c99655778ffa9576","segments":["StarterPlayer","StarterPlayerScripts","Lucky Wheel Client"]},{"className":"LocalScript","properties":{"Archivable":true,"Disabled":false,"Enabled":true,"LinkedSource":"","RunContext":"Enum.RunContext.Legacy"},"rawBytes":10614,"rawSHA256":"4094dc40c82aa71fba3c30d7d2296b11ec217db02bf12c60c721d1f8735ab7d4","segments":["StarterPlayer","StarterPlayerScripts","MasterTuningClient"]},{"className":"LocalScript","properties":{"Archivable":true,"Disabled":false,"Enabled":true,"LinkedSource":"","RunContext":"Enum.RunContext.Legacy"},"rawBytes":54956,"rawSHA256":"3c80a7e0264b2b2a972419e52e5c2cd5ed6791b3f82d81ada22e893d152f71d6","segments":["StarterPlayer","StarterPlayerScripts","NoiseReporter"]},{"className":"LocalScript","properties":{"Archivable":true,"Disabled":false,"Enabled":true,"LinkedSource":"","RunContext":"Enum.RunContext.Legacy"},"rawBytes":44987,"rawSHA256":"795901a09d859556d2efeaf433c6d3fb592030dfa71f5ab171c32f3b110fc12c","segments":["StarterPlayer","StarterPlayerScripts","ProtectionHUD"]},{"className":"LocalScript","properties":{"Archivable":true,"Disabled":false,"Enabled":true,"LinkedSource":"","RunContext":"Enum.RunContext.Legacy"},"rawBytes":8315,"rawSHA256":"50c517b7f8664471a0ff4934d7e737a65f7a0a4c7a747c3d23d11a47f8640271","segments":["StarterPlayer","StarterPlayerScripts","PuzzleUI"]},{"className":"LocalScript","properties":{"Archivable":true,"Disabled":false,"Enabled":true,"LinkedSource":"","RunContext":"Enum.RunContext.Legacy"},"rawBytes":15632,"rawSHA256":"431e40732f1c568993cfaae749dd12893a3a8c7abc03fbef3fb9acd81ea11868","segments":["StarterPlayer","StarterPlayerScripts","R4DevGateController"]},{"className":"LocalScript","properties":{"Archivable":true,"Disabled":false,"Enabled":true,"LinkedSource":"","RunContext":"Enum.RunContext.Legacy"},"rawBytes":13218,"rawSHA256":"ff730eb9216f3376e17766ec6b19abaa68f3fa106ba91bfe558c25ef88cb7adb","segments":["StarterPlayer","StarterPlayerScripts","Round Entry Client"]},{"className":"LocalScript","properties":{"Archivable":true,"Disabled":false,"Enabled":true,"LinkedSource":"","RunContext":"Enum.RunContext.Legacy"},"rawBytes":17883,"rawSHA256":"bd1cdb46003ae1dd4f151f1c1a0cc7c2ca85ed4add9dd9fe18a27bd765e20752","segments":["StarterPlayer","StarterPlayerScripts","Round Exit Client"]},{"className":"LocalScript","properties":{"Archivable":true,"Disabled":false,"Enabled":true,"LinkedSource":"","RunContext":"Enum.RunContext.Legacy"},"rawBytes":15589,"rawSHA256":"310c422c1e7ec3b853ae8afcab071c0fa8fb8fdcebbfbcc30c948a91fe2bf7ae","segments":["StarterPlayer","StarterPlayerScripts","Round HUD"]},{"className":"LocalScript","properties":{"Archivable":true,"Disabled":false,"Enabled":true,"LinkedSource":"","RunContext":"Enum.RunContext.Legacy"},"rawBytes":244615,"rawSHA256":"f524a7e6865c01b412581b46e64c12c2c2c786bf9c84c23f3b7d7a359d3f422c","segments":["StarterPlayer","StarterPlayerScripts","RoundUI"]},{"className":"LocalScript","properties":{"Archivable":true,"Disabled":false,"Enabled":true,"LinkedSource":"","RunContext":"Enum.RunContext.Legacy"},"rawBytes":3537,"rawSHA256":"d87559348d39821adfb35191a3b8b030967537cc0d8da955222217d7686bcaa0","segments":["StarterPlayer","StarterPlayerScripts","SceneEffectBudgetClient"]},{"className":"LocalScript","properties":{"Archivable":true,"Disabled":false,"Enabled":true,"LinkedSource":"","RunContext":"Enum.RunContext.Legacy"},"rawBytes":33136,"rawSHA256":"0abe08bcdf612c2b8d38b554a61ecdb55c70538326e124d75f73275c45cacfa1","segments":["StarterPlayer","StarterPlayerScripts","Shop Display Client"]},{"className":"LocalScript","properties":{"Archivable":true,"Disabled":false,"Enabled":true,"LinkedSource":"","RunContext":"Enum.RunContext.Legacy"},"rawBytes":71742,"rawSHA256":"0fc2ce5ee4787d7196193f2849ca3dc9fdfbc85e5f5286a11901543a610d327f","segments":["StarterPlayer","StarterPlayerScripts","SoundController"]},{"className":"LocalScript","properties":{"Archivable":true,"Disabled":false,"Enabled":true,"LinkedSource":"","RunContext":"Enum.RunContext.Legacy"},"rawBytes":20082,"rawSHA256":"f912a197184846e20cb1ba1c65a34bda3a2b6acdc3d263e0dc73abb3dc20645b","segments":["StarterPlayer","StarterPlayerScripts","SpectateController"]},{"className":"LocalScript","properties":{"Archivable":true,"Disabled":false,"Enabled":true,"LinkedSource":"","RunContext":"Enum.RunContext.Legacy"},"rawBytes":177,"rawSHA256":"3a6b69f7cd382bb9584775b173dc6b20289ebb07725952e0429bb5df59246dfa","segments":["StarterPlayer","StarterPlayerScripts","Team Objective Feed"]},{"className":"LocalScript","properties":{"Archivable":true,"Disabled":false,"Enabled":true,"LinkedSource":"","RunContext":"Enum.RunContext.Legacy"},"rawBytes":35698,"rawSHA256":"9b9772bdd2cb6f3bff76b779a7d05971b08c7a9b9512340e09ac4b637252e8f7","segments":["StarterPlayer","StarterPlayerScripts","Zyntra Daily L4"]},{"className":"LocalScript","properties":{"Archivable":true,"Disabled":false,"Enabled":true,"LinkedSource":"","RunContext":"Enum.RunContext.Legacy"},"rawBytes":47822,"rawSHA256":"4a0c96c62010ba65d3a6953f4888e3714754f0a17e6d0df72deb62adb58fe476","segments":["StarterPlayer","StarterPlayerScripts","Zyntra Dev L4"]},{"className":"LocalScript","properties":{"Archivable":true,"Disabled":false,"Enabled":true,"LinkedSource":"","RunContext":"Enum.RunContext.Legacy"},"rawBytes":84795,"rawSHA256":"36840bc50c391816388d98ace74548610e90ca386380fd43ee0e41fa9f8da364","segments":["StarterPlayer","StarterPlayerScripts","Zyntra Shop L4"]},{"className":"LocalScript","properties":{"Archivable":true,"Disabled":false,"Enabled":true,"LinkedSource":"","RunContext":"Enum.RunContext.Legacy"},"rawBytes":3722,"rawSHA256":"10a6bda3853afdf1c9fe4dbf46ef45ef6ee3f3bb15030cfa0e0f8b5cda092bdd","segments":["StarterPlayer","StarterPlayerScripts","ZyntraDetectorClient"]},{"className":"LocalScript","properties":{"Archivable":true,"Disabled":false,"Enabled":true,"LinkedSource":"","RunContext":"Enum.RunContext.Legacy"},"rawBytes":64900,"rawSHA256":"1436e08e705a4b7f7a1457b4cd7769210ea49aada4ba386291fedcf05c944cf5","segments":["StarterPlayer","StarterPlayerScripts","ZyntraStore"]}],"studioId":"b609b91a-e648-42ab-ba5f-a996912e9552","transferBase":"http://127.0.0.1:18917"}
]====])
-- PROPOSAL ONLY: append unchanged S04 common + fresh pinned PORT_CONFIG.
-- Root must provide a reviewed loopback receiver; no native execution by author.
-- Original object/property/Source writes, Instance.new, require and deserialization: none.
local config=PORT_CONFIG
local state,ledger,ownedState
local report={schema="retired-authoring-joint-serialized-references-v1",passed=false,
 stage="mcp-completion",nativeExecutedByAuthor=false,deletionApproved=false,
 referenceAbsenceCertified=false,originalWrites=0,instancesCreated=0,modeSwitches=0,
 cleanupErrors={},limits="Readonly joint serialization only; raw binary DOM/property semantics and compatible nonserialized holders remain separate pending gates."}
report.captureId=config.captureId
A.KEY="__MongoTVRetiredAuthoringSerializedReference_"..config.captureId
A.ORIGINAL_KEY="__MongoTVRetiredAuthoringSerializedReferenceLedger_"..config.captureId
A.BASE=config.transferBase
local previousWatchInventory=A.watchInventory
function A.watchInventory(s)
 A.check(ownedState==nil,"Only one current owned capture state")
 ownedState=s -- Exact identity before A.begin's first connection or yielding census.
 previousWatchInventory(s)
end
function A.post(cfg,path,body)
 return A.HS:RequestAsync({Url=A.BASE..path,Method="POST",Headers={["Content-Type"]="application/octet-stream",
  ["X-Archive-Capture"]=cfg.captureId,["X-Reference-Token"]=cfg.privateToken},Body=body})
end
local witnesses,readability,roots={},{},{}
local function unique(parent,name)
 local found=nil for _,child in parent:GetChildren() do if child.Name==name then
  A.check(not found,"Duplicate requested identity") found=child end end return found
end
local function resolve(segments)
 local node=game for _,name in segments do node=assert(unique(node,name),"Pinned path missing")end return node
end
local function sources()
 local seen={} local count=0
 for _,pin in config.sources do
  local node=resolve(pin.segments) local row=state.sources[node]
  A.check(row and not seen[node] and node.ClassName==pin.className,"Pinned Source identity/class differs")
  A.check(A.shaText(row.source)==pin.rawSHA256 and #row.source==pin.rawBytes and A.same(row.properties,pin.properties),"Fresh Source pin differs")
  A.check(A.same(A.scriptRow(node),row),"Current Source/editor/metadata changed")
  seen[node]=true count+=1
 end
 for node in state.sources do A.check(seen[node],"Unpinned Source")end
 A.check(count==213 and state.sourceCount==213,"All 213 current Sources required")
end
local function descriptors(class,names)
 local found={}
 for _,spec in A.properties(class) do if names[spec.Name] then
  A.check(spec.Type.ScriptType=="Instance","Witness is not an Instance-valued slot")
  A.check(spec.Type.InstanceType==(if class=="WeldConstraint" then "BasePart" else "Instance"),"Witness target type differs from reviewed actual schema")
  found[spec.Name]={name=spec.Name,serialized=spec.Serialized,instanceType=spec.Type.InstanceType,scriptType=spec.Type.ScriptType}
 end end
 for name in names do A.check(found[name]~=nil,"Required reflected witness field missing")end
 return found
end
local function witnessRow(node)
 local names=if node.ClassName=="WeldConstraint" then {Part0Internal=true,Part1Internal=true} else {PlaceAvatarRules=true}
 local row={parent=node.Parent,name=node.Name,class=node.ClassName,archivable=node.Archivable,
  attributes=node:GetAttributes(),tags=A.tags(node),children=node:GetChildren(),slots={}}
 for name,spec in descriptors(node.ClassName,names) do
  A.check(spec.serialized==true,"Required witness slot is not serialized in actual schema")
  local ok,value=pcall(function()return node[name]end)
  row.slots[name]={spec=spec,readable=ok,value=if ok then value else nil,error=if ok then nil else tostring(value)}
 end
 return row
end
local function guard()
 A.guard(state) sources()
 local current={} local count=0 for _,node in game:GetDescendants() do if node.ClassName=="WeldConstraint" then
  A.check(witnesses[node]~=nil,"New/uncovered WeldConstraint") current[node]=true count+=1 end end
 A.check(count==109,"Exact current 109 WeldConstraints required")
 for node,row in witnesses do
  A.check(node:IsDescendantOf(game) and A.same(witnessRow(node),row),"Witness identity/readability/fields changed")
  if node.ClassName=="WeldConstraint" then A.check(current[node],"Witness disappeared")end
 end
 A.check(state.epoch==0,"Reference capture changed during guard") A.mode()
end
local ok,why=xpcall(function()
 A.mode()
 A.check(type(config.privateToken)=="string" and #config.privateToken==64 and string.match(config.privateToken,"^[0-9a-f]+$"),
  "Fresh Root-private transfer token required")
 A.check(type(config.transferBase)=="string" and string.match(config.transferBase,"^http://127%.0%.0%.1:%d+$"),"Reviewed loopback receiver required")
 A.check(shared[A.KEY]==nil and shared[A.ORIGINAL_KEY]==nil,"Fresh owned reference namespace required")
 ledger={rootRefs={},historicalContinuation=false,captureId=config.captureId}
 for _,root in A.SS:GetChildren() do ledger.rootRefs[root]=true end
 shared[A.ORIGINAL_KEY]=ledger state=A.begin(config) ledger.referenceState=state
 sources() A.guard(state)
 local five=A.SER:SerializeInstancesAsync(state.roots)
 A.check(buffer.len(five)==8050869 and A.sha(five)==config.nativeSHA256,"Exact original five-forest archive differs")
 state.nativeBytes=buffer.len(five) state.nativeSHA256=A.sha(five)
 roots=table.clone(state.roots)
 local starter=game:GetService("StarterPlayer")
 A.check(starter.Parent==game and starter.Name=="StarterPlayer" and starter.Archivable,"StarterPlayer identity/Archivable differs")
 roots[#roots+1]=starter witnesses[starter]=witnessRow(starter)
 local covered={} local coverageRows={}
 for _,root in roots do
  local tree={root} for _,node in root:GetDescendants() do tree[#tree+1]=node end
  for _,node in tree do A.check(not covered[node] and node.Archivable,"Overlapping/unarchivable joint forest") covered[node]=true end
 end
 local count=0
 for _,node in game:GetDescendants() do if node.ClassName=="WeldConstraint" then
  count+=1 A.check(count<=109 and node.Archivable,"Witness count/Archivable differs")
  witnesses[node]=witnessRow(node)
  coverageRows[#coverageRows+1]={path=node:GetFullName(),name=node.Name,class=node.ClassName,coveredByStarterPlayer=covered[node]==true}
  if not covered[node] then A.check(#node:GetChildren()==0,"Unexpected WeldConstraint child scope") roots[#roots+1]=node covered[node]=true end
 end end
 A.check(count==109,"Exact current 109 WeldConstraints required")
 for node,row in witnesses do for name,slot in row.slots do
  local key=row.class.."."..name local summary=readability[key]
  if not summary then summary={class=row.class,property=name,serialized=slot.spec.serialized,
   instanceType=slot.spec.instanceType,readable=0,unreadable=0,errorSamples={}} readability[key]=summary end
  if slot.readable then summary.readable+=1 else summary.unreadable+=1
   if #summary.errorSamples<2 then summary.errorSamples[#summary.errorSamples+1]=string.sub(slot.error,1,512)end end
 end end
 -- Watch the complete StarterPlayer tree and every witness; never require its scripts.
 local watch={} for _,node in {starter,table.unpack(starter:GetDescendants())} do watch[node]=true end
 for node in witnesses do watch[node]=true end
 for node in watch do A.watchNode(state,node,"referenceWitness",true)end
 guard()
 local joint=A.SER:SerializeInstancesAsync(roots)
 A.check(buffer.len(joint)>8050869 and buffer.len(joint)<=32*1024*1024,"Bounded complete joint payload required")
 guard()
 local again=A.SER:SerializeInstancesAsync(roots)
 A.check(buffer.len(again)==buffer.len(joint) and A.sha(again)==A.sha(joint),"Joint serializer bytes changed")
 guard()
 report.referenceBytes=buffer.len(joint) report.referenceSHA256=A.sha(joint)
 report.actualReflection={WeldConstraint=descriptors("WeldConstraint",{Part0Internal=true,Part1Internal=true}),
  StarterPlayer=descriptors("StarterPlayer",{PlaceAvatarRules=true})}
 report.weldConstraints=count report.inputRootCount=#roots report.witnessCoverage=coverageRows
 report.actualWitnessReadability=readability
 report.fiveForestsNativeSHA256=state.nativeSHA256 report.all213SourcesUnchanged=true
 report.opaqueSlotsRemainUncertified=true
 report.captureId=config.captureId report.placeId=game.PlaceId report.universeId=game.GameId
 -- Transfer raw engine bytes, not a Lune-normalized reserialization. Saved != accepted.
 report.transfer=A.upload(config,"references",buffer.tostring(joint))
 guard()
 report.rawEngineSerializationCaptured=true
end,debug.traceback)
if not state and ownedState and ownedState.config==config then state=ownedState end
local finalOk,finalWhy=false,"Baseline unavailable"
if state and state.baselineComplete then finalOk,finalWhy=pcall(guard)end
local retained={}
if state then for _,connection in state.connections do
 local clean,err=pcall(function()connection:Disconnect()end)
 if not clean then retained[#retained+1]=connection report.cleanupErrors[#report.cleanupErrors+1]=tostring(err)end
end state.connections=retained state.watchersConnected=#retained>0 end
local postOk,postWhy=false,"Baseline unavailable"
if state and state.baselineComplete then postOk,postWhy=pcall(guard)end
report.finalOriginalGuardPassed=finalOk report.postCleanupOriginalGuardPassed=postOk
report.connectionsRetained=#retained
if state and shared[A.KEY]==state and #retained==0 then shared[A.KEY]=nil end
if ledger and shared[A.ORIGINAL_KEY]==ledger and #retained==0 then shared[A.ORIGINAL_KEY]=nil end
report.ownedLeaseReleased=state~=nil and shared[A.KEY]~=state
report.ownedLedgerReleased=ledger~=nil and shared[A.ORIGINAL_KEY]~=ledger
report.passed=ok and finalOk and postOk and #report.cleanupErrors==0
report.error=if ok then nil else tostring(why)
report.finalGuardError=if finalOk then nil else tostring(finalWhy)
report.postCleanupGuardError=if postOk then nil else tostring(postWhy)
report.diagnostics=A.diagnostics(state)
return A.HS:JSONEncode(report)
