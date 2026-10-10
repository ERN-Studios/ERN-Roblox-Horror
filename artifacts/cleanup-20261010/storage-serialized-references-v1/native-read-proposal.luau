-- PROPOSAL ONLY: append unchanged S04 common + fresh pinned PORT_CONFIG.
-- Root must provide a reviewed loopback receiver; no native execution by author.
-- Original object/property/Source writes, Instance.new, require and deserialization: none.
local config=PORT_CONFIG
local state,ledger
local report={schema="retired-authoring-joint-serialized-references-v1",passed=false,
 stage="mcp-completion",nativeExecutedByAuthor=false,deletionApproved=false,
 referenceAbsenceCertified=false,originalWrites=0,instancesCreated=0,modeSwitches=0,
 cleanupErrors={},limits="Readonly joint serialization only; raw binary DOM/property semantics and compatible nonserialized holders remain separate pending gates."}
A.KEY="__MongoTVRetiredAuthoringSerializedReference_"..config.captureId
A.ORIGINAL_KEY="__MongoTVRetiredAuthoringSerializedReferenceLedger_"..config.captureId
A.BASE=config.transferBase
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
if not state then local candidate=shared[A.KEY] if candidate and candidate.config==config then state=candidate end end
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
