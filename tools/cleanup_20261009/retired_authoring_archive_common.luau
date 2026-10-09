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
