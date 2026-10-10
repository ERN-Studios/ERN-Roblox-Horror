-- Concatenate immutable common prefix, exact transaction core and pinned PORT_CONFIG.
-- Trial only: five same-original Parent=nil -> original ServerStorage; never Destroy originals.
local B={}
local config=PORT_CONFIG
local state,purposeLedger
local entries,factories={},{}
local report={schema="retired-authoring-controlled-absence-v1",stage="mcp-completion",passed=false,
 deletionApproved=false,referenceAbsenceCertified=false,originalSourceWrites=0,foreignWrites=0,
 permanentRemoval=false,modeSwitches=0,probeCreated=0,probeDestroyed=0,probeRemaining=0,
 probeSourceAttempts=0,probeSourceReadbacks=0,cleanupErrors={},selectorPhases={},parentWrites=0}
local owned,ownedOrder={},{}
local previousDisconnect=A.disconnect
function A.disconnect(s)
 local errors,retained={},{}
 for _,connection in s.connections do
  local ok,why=pcall(function()connection:Disconnect()end)
  if not ok then errors[#errors+1]=tostring(why) retained[#retained+1]=connection end
 end
 s.connections=retained s.watchersConnected=#retained>0
 return errors
end
local previousEvent=A.event
A.KEY="__MongoTVRetiredAuthoringAbsence20261010V1_"..config.captureId
A.ORIGINAL_KEY="__MongoTVRetiredAuthoringCurrentLedger20261010V1_"..config.captureId
report.originalHeldMetadataIsHistorical=true
report.historicalHeldOriginalsVerified=false
report.currentPurposeLedgerOnly=true
function A.event(s,kind,node,argument)
 local budgets=s.expectedEvents
 local property=if string.sub(kind,-8)==".Changed" then argument else nil
 local key=kind..(if property~=nil then ":"..tostring(property) else "")
 local slots=budgets and budgets[node]
 if slots and slots[key] and slots[key]>0 then
  slots[key]-=1
  s.expectedEventCounts[key]=(s.expectedEventCounts[key] or 0)+1
  return
 end
 previousEvent(s,kind,node,argument)
end
local function unique(parent,name)
 local found=nil
 for _,child in parent:GetChildren() do
  if child.Name==name then A.check(not found,"Duplicate child: "..name) found=child end
 end
 return found
end
local function resolve(segments)
 local node=game
 for _,name in segments do node=assert(unique(node,name),"Missing pinned path segment: "..name) end
 return node
end
function B.restoreLease()
 A.mode()
 A.check(state and shared[A.KEY]==state and shared[A.ORIGINAL_KEY]==state.previous,
  "Owned absence lease/original identity ledger changed")
 A.check(not state.previous.probeLease and not state.previous.portLease,"Other original ledger lease appeared")
end
function B.lease()
 B.restoreLease()
 A.check(state.epoch==0,"Concurrent original event")
end
function B.sources()
 B.lease()
 for node,row in state.sources do
  A.check(node:IsDescendantOf(game) and A.same(A.scriptRow(node),row),"Fresh Source/editor/properties changed: "..row.path)
 end
end
function B.bindSources()
 local seen={}
 for _,pin in config.sources do
  local node=resolve(pin.segments)
  A.check(not seen[node] and node.ClassName==pin.className and state.sources[node],"Fresh pinned Source identity/class differs")
  local row=state.sources[node]
  A.check(A.shaText(row.source)==pin.rawSHA256 and #row.source==pin.rawBytes,"Current Source differs from frozen fresh export: "..row.path)
  A.check(A.same(row.properties,pin.properties),"Current Source properties differ from frozen fresh export: "..row.path)
  for _,name in A.NAMES do
   A.check(not string.find(row.source,'"'..name..'"',1,true) and not string.find(row.source,"'"..name.."'",1,true),
    "Direct retired-name consumer requires closure review: "..row.path)
  end
  seen[node]=true
 end
 local count=0 for node in state.sources do A.check(seen[node],"Unpinned live Source") count+=1 end
 A.check(count==213 and #config.sources==213,"All 213 Sources required")
 report.currentSourcesPinned=count
end
local function exactValue(a,b,components)
 if typeof(a)~=typeof(b) then return false end
 if typeof(a)=="buffer" then return buffer.tostring(a)==buffer.tostring(b) end
 if a~=b then return false end
 if components then return A.same({a:GetComponents()},components) end
 return true
end
function B.snapshot(root)
 local nodes,index=A.collect({root})
 local rows={}
 for _,node in nodes do
  local row={parent=node.Parent,name=node.Name,class=node.ClassName,archivable=node.Archivable,
   children=node:GetChildren(),attributes=A.attributes(node,index),tags=A.tags(node),properties={}}
  for _,spec in A.properties(node.ClassName) do
   if spec.Serialized and spec.Name~="Parent" then
    local readable,value=pcall(function()return node[spec.Name]end)
    row.properties[#row.properties+1]={name=spec.Name,readable=readable,value=if readable then value else nil,
     components=if readable and typeof(value)=="CFrame" then {value:GetComponents()} else nil}
   end
  end
  rows[node]=row
 end
 return {root=root,nodes=nodes,index=index,rows=rows}
end
function B.tree(snapshot,allowDetached)
 local root=snapshot.root
 A.check(root.Parent==A.SS or (allowDetached and root.Parent==nil),"Foreign root Parent preserved")
 for node,row in snapshot.rows do
  A.check((node==root or node.Parent==row.parent) and node.Name==row.name and node.ClassName==row.class
   and node.Archivable==row.archivable,"Original retired hierarchy/identity changed")
  A.check(A.same(node:GetChildren(),row.children) and A.same(A.attributes(node,snapshot.index),row.attributes)
   and A.same(A.tags(node),row.tags),"Original retired children/attrs/tags changed")
  for _,slot in row.properties do
   local readable,value=pcall(function()return node[slot.name]end)
   A.check(readable==slot.readable and (not readable or exactValue(value,slot.value,slot.components)),
    "Original retired readable serialized field changed: "..slot.name)
  end
 end
end
function B.inventory()
 B.sources()
 local removed,seen=0,{}
 for _,entry in entries do
  local parent=entry.root.Parent
  A.check(parent==A.SS or (entry.invoked and parent==nil),"Unowned original Parent change")
  if parent==nil then removed+=1 end
 end
 for _,root in A.SS:GetChildren() do
  local row=state.rootRefs[root]
  A.check(row and root.Name==row.name and root.ClassName==row.class and root.Archivable==row.archivable
   and A.same(root:GetAttributes(),row.attributes) and A.same(A.tags(root),row.tags),"Current storage root inventory changed")
  seen[root]=true
 end
 for root in state.rootRefs do
  if root.Parent==A.SS then A.check(seen[root],"Storage root disappeared")
  else
   local allowed=false for _,entry in entries do if entry.root==root and entry.invoked and root.Parent==nil then allowed=true end end
   A.check(allowed,"Foreign storage root removal")
  end
 end
 A.check(#A.SS:GetChildren()==52-removed,"Storage root count differs from own transitions")
 return removed
end
function B.gameCensus(absent)
 local expected=config.expectedSceneCount-(if absent then 1617 else 0)
 local seen={} local nodes=game:GetDescendants()
 A.check(#nodes==expected,"Game object count differs from exact five-forest absence")
 for _,node in nodes do
  A.check(state.gameOriginals[node] and (not absent or not state.index[node]),"New/retired game descendant appeared")
  seen[node]=true
 end
 for node in state.gameOriginals do
  A.check(seen[node] or (absent and state.index[node]),"Unrelated original game descendant disappeared")
 end
end
local function forbidden() error("Write/initializer boundary is forbidden in selector port") end
local denied=setmetatable({}, {__index=forbidden,__newindex=forbidden})
function B.environment(missing,incomplete)
 local log={}
 local storage={}
 function storage:FindFirstChild(name)
  log[#log+1]=name
  A.check(name=="LobbyReimaginedBlenderSource20261001R4" or name=="Level1BlenderKitV2"
   or name=="Level1ElevatorInsetKit","Unexpected/retired asset selector: "..tostring(name))
  if name==missing then return nil end
  local original=unique(A.SS,name)
  if name==incomplete then
   -- A read-only service-boundary override; no original Ready attribute write.
   return {GetAttribute=function(_,attribute)if attribute=="Ready" then return false end return original:GetAttribute(attribute)end,
    FindFirstChild=function(_,child)return original:FindFirstChild(child)end}
  end
  return original
 end
 local proxy={PlaceId=game.PlaceId,GameId=game.GameId,CreatorId=game.CreatorId}
 local http={GenerateGUID=function(_,...)return A.HS:GenerateGUID(...)end,
  JSONDecode=function(_,...)return A.HS:JSONDecode(...)end}
 local encoding={ComputeBufferHash=function(_,...)return A.ENC:ComputeBufferHash(...)end,
  Base64Decode=function(_,...)return A.ENC:Base64Decode(...)end,
  DecompressBuffer=function(_,...)return A.ENC:DecompressBuffer(...)end}
 local run={IsClient=function()return A.RS:IsClient()end}
 function proxy:GetService(name)
  if name=="ServerStorage" then return storage end
  if name=="HttpService" then return http end
  if name=="EncodingService" then return encoding end
  if name=="RunService" then return run end
  if name=="AssetService" then return denied end
  error("Unexpected service/initializer: "..name)
 end
 table.freeze(proxy) table.freeze(storage) table.freeze(http) table.freeze(encoding) table.freeze(run)
 return proxy,log
end
function B.factory(kind,env)
 return factories[kind](env,denied,denied,denied,forbidden,denied,denied,forbidden,forbidden,forbidden,denied,denied)
end
function B.selectors(label)
 B.inventory()
 local proxy,bakeLog=B.environment()
 local bake=B.factory("bake",proxy)
 local manifest=bake.GetManifest()
 local rendererProxy,rendererLog=B.environment()
 local renderer=B.factory("renderer",rendererProxy)
 local ready,why=renderer.IsReady()
 A.check(ready==true and why==nil,"Actual current V2/elevator IsReady failed")
 A.check(A.same(bakeLog,{"LobbyReimaginedBlenderSource20261001R4"})
  and A.same(rendererLog,{"Level1BlenderKitV2","Level1ElevatorInsetKit"}),"Actual asset selectors differ")
 if state.manifest then A.check(A.same(state.manifest,manifest),"Fresh factory manifest differs across absence") else state.manifest=manifest end
 local failures={}
 for _,name in {"LobbyReimaginedBlenderSource20261001R4","Level1BlenderKitV2","Level1ElevatorInsetKit"} do
  local env,log=B.environment(name)
  if name=="LobbyReimaginedBlenderSource20261001R4" then
   local module=B.factory("bake",env)
   local ok,errorText=pcall(module.GetManifest)
   A.check(not ok and string.find(tostring(errorText),"Preview raw source not installed",1,true),"Missing R4 silently selected a fallback")
  else
   local module=B.factory("renderer",env)
   local missingReady,reason=module.IsReady()
   A.check(missingReady==false and reason=="PREVIEW_NOT_READY","Missing current kit silently selected a fallback")
  end
  failures[#failures+1]={missing=name,selectors=log,controlledBoundary=true}
 end
 for _,name in {"LobbyReimaginedBlenderSource20261001R4","Level1BlenderKitV2","Level1ElevatorInsetKit"} do
  local env,log=B.environment(nil,name)
  if name=="LobbyReimaginedBlenderSource20261001R4" then
   local module=B.factory("bake",env)
   local ok,errorText=pcall(module.GetManifest)
   A.check(not ok and string.find(tostring(errorText),"Incomplete/unowned preview source",1,true),"Incomplete R4 silently selected a fallback")
  else
   local module=B.factory("renderer",env)
   local incompleteReady,reason=module.IsReady()
   A.check(incompleteReady==false and reason=="PREVIEW_NOT_READY","Incomplete current kit silently selected a fallback")
  end
  failures[#failures+1]={incomplete=name,selectors=log,controlledBoundary=true}
 end
 report.selectorPhases[#report.selectorPhases+1]={phase=label,actualFreshFactories=true,manifestEqual=true,
  ready=true,assetSelectors={bake=bakeLog,renderer=rendererLog},failureCases=failures}
end
function B.stage(kind,pin)
 local original=resolve(pin.segments)
 A.guard(state) B.bindSources()
 local body="return function(game,script,workspace,Instance,require,task,coroutine,spawn,delay,wait,shared,_G)\n"..original.Source.."\nend"
 local probe=Instance.new("ModuleScript")
 owned[probe]={name="MongoTV_S04_"..kind.."_"..config.captureId,body=body,
  archivable=probe.Archivable,linkedSource=tostring(probe.LinkedSource),attributes=probe:GetAttributes(),tags=A.tags(probe)}
 ownedOrder[#ownedOrder+1]=probe report.probeCreated+=1
 probe.Name=owned[probe].name
 A.check(probe.Archivable==true and tostring(probe.LinkedSource)=="" and next(owned[probe].attributes)==nil and #owned[probe].tags==0,
  "Fresh probe metadata must have exact default baseline")
 A.check(probe.Source=="" and A.SES:GetEditorSource(probe)=="" and probe.Parent==nil and #probe:GetChildren()==0,
  "Fresh probe must have exact empty Source/editor baseline")
 report.probeSourceAttempts+=1
 A.SES:UpdateSourceAsync(probe,function(current)
  B.inventory()
  for _,entry in entries do B.tree(entry.snapshot,false) end
  A.check(current=="" and probe.Source=="" and A.SES:GetEditorSource(probe)=="" and probe.Parent==nil
   and probe.Name==owned[probe].name and probe.ClassName=="ModuleScript" and #probe:GetChildren()==0,"Probe identity/empty editor CAS changed")
  local row=owned[probe]
  A.check(probe.Archivable==row.archivable and tostring(probe.LinkedSource)==row.linkedSource
   and A.same(probe:GetAttributes(),row.attributes) and A.same(A.tags(probe),row.tags),"Foreign probe metadata preserved")
  return body
 end)
 A.check(probe.Source==body and A.SES:GetEditorSource(probe)==body,"Staged Source/editor differs")
 local row=owned[probe]
 A.check(probe.Name==row.name and probe.ClassName=="ModuleScript" and probe.Parent==nil and #probe:GetChildren()==0
  and probe.Archivable==row.archivable and tostring(probe.LinkedSource)==row.linkedSource
  and A.same(probe:GetAttributes(),row.attributes) and A.same(A.tags(probe),row.tags),"Staged probe metadata/hierarchy differs")
 report.probeSourceReadbacks+=1
 A.guard(state) B.bindSources()
 local factory=require(probe)
 A.check(type(factory)=="function","Actual whole-source factory did not compile")
 A.guard(state) B.bindSources()
 return factory
end
function B.budget(entry,phase)
 local node=entry.root
 local slots=state.expectedEvents[node] or {} state.expectedEvents[node]=slots
 local kinds={"storageRoot.Changed:Parent","retiredForest.Changed:Parent",
  if phase=="detach" then "ServerStorage.ChildRemoved" else "ServerStorage.ChildAdded",
  if phase=="detach" then "game.DescendantRemoving" else "game.DescendantAdded"}
 for _,key in kinds do slots[key]=(slots[key] or 0)+1 end
end
local ok,why=xpcall(function()
 A.mode()
 A.check(shared[A.KEY]==nil and shared[A.ORIGINAL_KEY]==nil,"Fresh purpose-bound namespace already occupied")
 A.check(shared.__MongoTVStorageCleanup20261009==nil,"Historical ledger reappeared; require fresh reconciliation rather than guessing context")
 purposeLedger={schema="retired-authoring-current-purpose-ledger-v1",captureId=config.captureId,
  rootRefs={},historicalContinuation=false,originalHeldMetadataIsHistorical=true}
 for _,root in A.SS:GetChildren() do purposeLedger.rootRefs[root]=true end
 A.check(#A.SS:GetChildren()==52,"Current purpose ledger requires exactly 52 roots")
 shared[A.ORIGINAL_KEY]=purposeLedger
 state=A.begin(config)
 purposeLedger.absenceState=state
 B.bindSources()
 state.gameOriginals={}
 for _,node in game:GetDescendants() do state.gameOriginals[node]=true end
 B.gameCensus(false)
 for i,root in state.roots do
  A.check(state.previous==purposeLedger and purposeLedger.rootRefs[root]~=nil,"Fresh purpose ledger lost a retired original")
  entries[i]={root=root,name=root.Name,snapshot=B.snapshot(root),invoked=false}
 end
 A.guard(state)
 local native=A.SER:SerializeInstancesAsync(state.roots)
 A.check(buffer.len(native)==8050869 and A.sha(native)==config.nativeSHA256,"Historical exact five-root native archive mismatch")
 state.nativeSHA256=config.nativeSHA256 state.nativeBytes=8050869
 state.references=A.references(state)
 A.check(#state.references.externalReadable==0,"Readable inbound reference blocks controlled absence")
 report.referenceSlots=state.references.slots report.unreadableReferenceKinds=state.references.unreadable
 report.referenceBoundary="All recorded unreadable slots are Instance-valued. Compatible protected/native/editor slots remain pending; this port cannot approve deletion."
 A.guard(state)
 state.activeRoots={}
 for _,name in {"LobbyReimaginedBlenderSource20261001R4","Level1BlenderKitV2","Level1ElevatorInsetKit"} do
  local root=assert(unique(A.SS,name),"Missing current selected root: "..name)
  state.activeRoots[#state.activeRoots+1]=root
 end
 state.activeNative=A.SER:SerializeInstancesAsync(state.activeRoots)
 state.activeSHA256=A.sha(state.activeNative)
 local activeFacts,activeNodes=A.forestFacts(state.activeRoots)
 state.activeFacts=activeFacts state.activeNodes=activeNodes
 for _,node in activeNodes do A.watchNode(state,node,"currentSelectedForest",true) end
 factories.bake=B.stage("bake",config.bake)
 factories.renderer=B.stage("renderer",config.renderer)
 B.selectors("before")
 A.guard(state)
 state.expectedEvents={} state.expectedEventCounts={}
 local transaction,pending=T.run(entries,{
  preflight=function()
   B.inventory() B.gameCensus(false)
   for _,entry in entries do B.tree(entry.snapshot,false) end
   state.trialStarted=os.clock()
  end,
  parent=function(entry)return entry.root.Parent end,
  originalParent=function()return A.SS end,
  detachEligibility=function(entry)
   B.inventory() B.tree(entry.snapshot,false)
   A.check(os.clock()-state.trialStarted<=config.maxDetachSeconds,"Bounded no-yield detach window exceeded")
  end,
  rollbackEligibility=function(entry)
   -- Unrelated Source/epoch changes revoke the final port, not this scoped inverse.
   B.restoreLease() B.tree(entry.snapshot,true)
   A.check(state.previous.rootRefs[entry.root]~=nil,"Owned original identity ledger lost this root")
   A.check(unique(A.SS,entry.name)==nil or unique(A.SS,entry.name)==entry.root,"Name collision; preserve foreign root")
  end,
  beforeWrite=function(_,phase)if phase=="restore" then B.restoreLease() else B.lease() end end,
  setParent=function(entry,parent)
   if parent==A.SS then B.restoreLease() else B.lease() end
   A.check((parent==nil and entry.root.Parent==A.SS) or (parent==A.SS and entry.root.Parent==nil),"Immediate native Parent CAS differs")
   local phase=if parent==nil then "detach" else "restore"
   B.budget(entry,phase) entry.invoked=true
   report.parentWrites+=1
   entry.root.Parent=parent -- The only original property write in the entire trial.
  end,
  afterWrite=function(_,phase)if phase=="restore" then B.restoreLease() else B.lease() end end,
  absentPort=function()
   A.check(B.inventory()==5,"Exact five roots must be absent")
   B.gameCensus(true)
   for _,entry in entries do B.tree(entry.snapshot,true) end
   B.selectors("absent")
  end,
  finalGuard=function()
   A.check(B.inventory()==0,"Original roots not all restored")
   B.gameCensus(false)
   for _,entry in entries do B.tree(entry.snapshot,false) end
  end,
 })
 report.transaction=transaction state.pending=pending
 report.noYieldTrialWallSeconds=os.clock()-state.trialStarted
 A.check(transaction.passed,"Controlled absence transaction failed")
 -- Serialize/facts/HTTP/task.wait are forbidden between the first detach and final restore.
 task.wait() task.wait()
 B.selectors("restored")
 A.guard(state)
 local activeAgain=A.SER:SerializeInstancesAsync(state.activeRoots)
 A.check(buffer.len(activeAgain)==buffer.len(state.activeNative) and A.sha(activeAgain)==state.activeSHA256,
  "Current R4/V2/elevator opaque native data changed")
 local activeAfter,nodesAfter=A.forestFacts(state.activeRoots)
 A.check(A.same(activeAfter,state.activeFacts) and A.same(nodesAfter,state.activeNodes),"Current selected asset facts/identities changed")
 A.guard(state) B.bindSources() B.gameCensus(false)
 report.originalNativeArchiveUnchanged=true report.currentSelectedNativeUnchanged=true
 report.activeNativeBytes=buffer.len(activeAgain) report.activeNativeSHA256=state.activeSHA256
 report.currentSelectedFactsUnchanged=true report.all213SourcesUnchanged=true
end,debug.traceback)
if not state then
 local candidate=shared[A.KEY]
 if candidate and candidate.config==config then state=candidate end
end
if purposeLedger and state then purposeLedger.absenceState=state end
-- Recovery evidence is scoped separately from a global-concurrency refusal.
-- An unrelated Source change cannot convert a restored tree into a port PASS.
if state and state.baselineComplete and #entries==5 then
 local recovered,recoveryWhy=pcall(function()
  B.restoreLease()
  for _,entry in entries do A.check(entry.root.Parent==A.SS,"Original root remains detached") B.tree(entry.snapshot,false) end
  local original=A.SER:SerializeInstancesAsync(state.roots)
  B.restoreLease()
  for _,entry in entries do B.tree(entry.snapshot,false) end
  A.check(buffer.len(original)==8050869 and A.sha(original)==config.nativeSHA256,"Recovered original native archive differs")
 end)
 report.scopedOriginalRecoveryPassed=recovered
 report.scopedOriginalRecoveryError=if recovered then nil else tostring(recoveryWhy)
 report.originalNativeArchiveUnchanged=recovered
 local sourcesOk,sourceWhy=pcall(function()
  B.restoreLease()
  for node,row in state.sources do
   A.check(node:IsDescendantOf(game) and A.same(A.scriptRow(node),row),"Original Source/editor changed: "..row.path)
  end
  local count=0 for _,node in game:GetDescendants() do if node:IsA("LuaSourceContainer") then
   A.check(state.sources[node],"A foreign Source appeared") count+=1 end end
  A.check(count==213,"Current Source count changed")
 end)
 report.all213SourcesUnchanged=sourcesOk
 report.scopedSourceGuardError=if sourcesOk then nil else tostring(sourceWhy)
end
-- Exact owned probe cleanup only. Independently attempt every probe and connection.
for _,probe in ownedOrder do
 local row=owned[probe]
 local clean,err=pcall(function()
  A.check(probe.ClassName=="ModuleScript" and probe.Name==row.name and probe.Parent==nil and #probe:GetChildren()==0,
   "Foreign probe hierarchy/identity preserved")
  A.check(probe.Archivable==row.archivable and tostring(probe.LinkedSource)==row.linkedSource
   and A.same(probe:GetAttributes(),row.attributes) and A.same(A.tags(probe),row.tags),"Foreign probe metadata preserved")
  local source=probe.Source
  A.check((source=="" or source==row.body) and A.SES:GetEditorSource(probe)==source,"Foreign probe Source/editor preserved")
  probe:Destroy() report.probeDestroyed+=1 owned[probe]=nil
 end)
 if not clean then report.cleanupErrors[#report.cleanupErrors+1]={scope="ownedProbe",error=tostring(err)} end
end
for _ in owned do report.probeRemaining+=1 end
local finalOk,finalWhy=false,"Baseline unavailable"
if state and state.baselineComplete then finalOk,finalWhy=pcall(function()A.guard(state) B.bindSources() B.gameCensus(false)end) end
report.finalOriginalGuardPassed=finalOk
local disconnectErrors=if state then A.disconnect(state) else {}
for _,err in disconnectErrors do report.cleanupErrors[#report.cleanupErrors+1]={scope="connection",error=err} end
local postOk,postWhy=false,"Baseline unavailable"
if state and state.baselineComplete then postOk,postWhy=pcall(function()A.guard(state) B.bindSources() B.gameCensus(false)end) end
report.postCleanupOriginalGuardPassed=postOk
report.passed=ok and finalOk and postOk and #report.cleanupErrors==0 and report.probeRemaining==0
report.error=if ok then nil else tostring(why)
report.finalGuardError=if finalOk then nil else tostring(finalWhy)
report.postCleanupGuardError=if postOk then nil else tostring(postWhy)
report.diagnostics=A.diagnostics(state)
if state then
 report.expectedEventCounts=state.expectedEventCounts
 report.pendingOriginals={} for _,entry in entries do if entry.root.Parent~=A.SS then report.pendingOriginals[#report.pendingOriginals+1]=entry.name end end
 state.completedReport=report state.ownedProbes=owned state.originalEntries=entries
 if shared[A.KEY]==state and #report.pendingOriginals==0 and report.probeRemaining==0 and #state.connections==0 then shared[A.KEY]=nil end
 if shared[A.ORIGINAL_KEY]==purposeLedger and #report.pendingOriginals==0 and report.probeRemaining==0 and #state.connections==0 then
  shared[A.ORIGINAL_KEY]=nil
 end
elseif purposeLedger and shared[A.ORIGINAL_KEY]==purposeLedger then
 shared[A.ORIGINAL_KEY]=nil
end
report.ownedLeaseReleased=state~=nil and shared[A.KEY]~=state
report.ownedCurrentLedgerReleased=purposeLedger~=nil and shared[A.ORIGINAL_KEY]~=purposeLedger
report.connectionsRetained=if state then #state.connections else 0
report.limits="Actual current data selectors + same-original absence/inverse only. No Ensure/Build/Begin, asset-service bake/download/render, gameplay, multiplayer, streaming, reserved-server, performance gain or deletion certificate. Deferred event budgets classify expected own transitions; they do not establish actor provenance. Post-disconnect guards are point-in-time. Unknown transport is not cancellation."
return A.HS:JSONEncode(report)
