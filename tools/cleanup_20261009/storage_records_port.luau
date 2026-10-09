-- S01: exact archived originals only. No Destroy, cloning, source writes or modeswitch.
-- Caller pins an externally verified current reference pack; v7 is the default.
-- Prepend local PORT_CONFIG={action="trial"|"remove",names={...},referencesSHA256="..."}.
local supplied=PORT_CONFIG or {action="trial",names={"TEMP_PipeEntityMultiplayerLaunch"}}
assert(type(supplied)=="table","config must be a table")
-- Snapshot caller input before any yield; never follow an externally aliased table.
local config={action=supplied.action,referencesSHA256=supplied.referencesSHA256,
 names=if type(supplied.names)=="table" then table.clone(supplied.names) else supplied.names}
local HS=game:GetService("HttpService")
local ENC=game:GetService("EncodingService")
local SER=game:GetService("SerializationService")
local SES=game:GetService("ScriptEditorService")
local REF=game:GetService("ReflectionService")
local RS=game:GetService("RunService")
local SS=game:GetService("ServerStorage")
local Selection=game:GetService("Selection")
local KEY="__MongoTVStorageCleanup20261009"
local SCHEMA="storage-record-same-original-port-v1"
local NATIVE_SHA="9613ba71dbe8255cf67b28ac4fa58e9d3e5e034a231dcf79cf72dff81f395098"
local REFERENCES_SHA=if config.referencesSHA256==nil then "74a893a614cc2ffb738e4a7ea4498101c23971074961af310583fe7390a0c821" else config.referencesSHA256
assert(type(REFERENCES_SHA)=="string" and #REFERENCES_SHA==64
 and string.match(REFERENCES_SHA,"^[0-9a-f]+$"),"reference SHA must be caller-verified lowercase 64hex")
local MAX_SLOTS=10000
local ALL_NAMES={
 "TEMP_PipeEntityLobbyRigResult_0748Z","TEMP_PipeEntityMPResult_0457Z",
 "TEMP_PipeEntityMPResult_0503Z","TEMP_PipeEntityMPResult_0508Z",
 "TEMP_PipeEntityMPResult_0638Z","TEMP_PipeEntityMPResult_0706Z",
 "TEMP_PipeEntityMPResult_1609Z","TEMP_PipeEntityMPResult_1624Z",
 "TEMP_PipeEntityMPResult_1633Z","TEMP_PipeEntityMPResult_1640Z",
 "TEMP_PipeEntityMPResult_1648Z","TEMP_PipeEntityMultiplayerLaunch",
}
assert(game.PlaceId==131311258779917 and game.GameId==10559217407 and not RS:IsRunning(),"wrong place/mode")
assert(config.action=="trial" or config.action=="remove","unsupported action")
assert(type(config.names)=="table" and #config.names>=1 and #config.names<=4,"group must contain 1..4 exact names")
local configuredCount=0
for index in config.names do
 assert(type(index)=="number" and index%1==0 and index>=1 and index<=#config.names,"group must be a dense name array")
 configuredCount+=1
end
assert(configuredCount==#config.names,"group must be a dense name array")
local state=assert(shared[KEY],"no captured originals")
assert(state.nativeProbePass and not state.probeLease and not state.portLease,"capture/probe/port unavailable")
assert(state.nativeSHA256==NATIVE_SHA and state.referencesSHA256==REFERENCES_SHA,"captured hashes do not match caller-verified pack")
assert(type(state.roots)=="table" and #state.roots==12 and #state.facts==12,"wrong captured set")
local port=state.storagePort
if port==nil then port={schema=SCHEMA,removed={},trials={}} state.storagePort=port end
assert(port.schema==SCHEMA and type(port.removed)=="table" and type(port.trials)=="table","foreign port state")
local lease={} state.portLease=lease
local connections,slots,sources,remotes,rootRows={},{},{},{},{}
local descendantCount=0
local targets,group,byName,capturedIndex={},{},{},{}
local budgets={}
local writing=false
local epoch=0
local attempted={}
local trialKey,pendingTrial
local checks=0
local report={schema=SCHEMA,action=config.action,names=table.clone(config.names),pass=false,
 nativeSHA256=NATIVE_SHA,referencesSHA256=REFERENCES_SHA,unknownReferences="opaque; not proven null",
 nonserializedReadExceptions={},serializedReferenceExceptions={},editorMetadataExceptions={},
 nativeDestroyCalls=0,sourceWrites=0,modeSwitches=0,
 limits="Same-original tree removal and data/inventory/authoring selectors only; no Destroy, full Studio UI, gameplay, multiplayer, streaming or performance certification."}
local function check(value,message)
 assert(value,message) checks+=1
end
local function leaseOwned()
 return shared[KEY]==state and state.portLease==lease and state.storagePort==port
end
local function owned()
 return leaseOwned() and not state.probeLease and state.nativeProbePass==true
end
local function sha(raw)
 local hash=ENC:ComputeBufferHash(raw,Enum.HashAlgorithm.Sha256)
 local bytes={} for i=0,buffer.len(hash)-1 do bytes[i+1]=string.format("%02x",buffer.readu8(hash,i)) end
 return table.concat(bytes)
end
local function tags(f)
 local values=f:GetTags() table.sort(values) return values
end
local function scriptRow(s)
 local properties={Archivable=s.Archivable,LinkedSource=tostring(s.LinkedSource)}
 if s:IsA("BaseScript") then
  properties.Enabled=s.Enabled properties.Disabled=s.Disabled properties.RunContext=tostring(s.RunContext)
 end
 local source=s.Source
 check(SES:GetEditorSource(s)==source,"Source/editor conflict: "..s:GetFullName())
 return {path=s:GetFullName(),class=s.ClassName,parent=s.Parent,source=source,
  properties=properties,attributes=s:GetAttributes(),tags=tags(s)}
end
local function remoteRow(s)
 return {path=s:GetFullName(),class=s.ClassName,parent=s.Parent,archivable=s.Archivable,
  attributes=s:GetAttributes(),tags=tags(s)}
end
local function isRemote(s)
 return s:IsA("RemoteEvent") or s:IsA("UnreliableRemoteEvent") or s:IsA("RemoteFunction")
end
local function targetFacts()
 check(owned() and not RS:IsRunning(),"lease/mode changed")
 for i,f in state.roots do
  local removed=port.removed[f]
  local expected=if attempted[f] then nil elseif removed then nil else SS
  check(f.Parent==expected and f.ClassName=="Folder" and #f:GetChildren()==0,"captured original parent/class/children changed")
  check(state.same(state.factsOf(f),state.facts[i]),"captured original data changed")
 end
end
local function arraySet(values)
 local set={} for _,v in values do check(set[v]==nil,"duplicate identity") set[v]=true end return set
end
local function authoring()
 local selected=Selection:Get()
 for _,f in selected do check(not capturedIndex[f],"captured original selected") end
 local maps={}
 for _,name in {"Level 4 Cinema Blender","Level 5 Void","Level 6 Indoor Playground"} do
  local found
  for _,parent in {workspace,SS} do
   for _,f in parent:GetChildren() do
    if f.Name==name then check(not found and f:IsA("Model"),"ambiguous/wrong authored map") found=f end
   end
  end
  if found then maps[name]={ref=found,parent=found.Parent} end
 end
 local scratch={}
 for _,f in SS:GetChildren() do
  if string.find(f.Name,"^__L2KMeshWire_") or string.find(f.Name,"^__.*_Installing_") then
   scratch[f]={name=f.Name,class=f.ClassName}
  end
 end
 return {selection=selected,maps=maps,scratch=scratch}
end
local function treeEvent(kind,node)
 local budget=budgets[node]
 if writing and targets[node] and budget and (budget[kind] or 0)>0 then
  budget[kind]-=1
 else epoch+=1 end
end
local function prepareEvents(f,removing)
 local budget=budgets[f] or {} budgets[f]=budget
 for _,kind in if removing then {"gameRemove","rootRemove"} else {"gameAdd","rootAdd"} do
  budget[kind]=(budget[kind] or 0)+1
 end
end
local function opaque(s,p,errorText)
 if p.Serialized==false then
  if s.ClassName=="GuiService" and (p.Name=="CoreEffectFolder" or p.Name=="CoreGuiFolder")
   or s.ClassName=="Selection" and p.Name=="ActiveInstance"
   or s.ClassName=="StudioService" and p.Name=="HoverInstance" then
   check(string.find(errorText,"RobloxScript",1,true)~=nil,"unexpected protected pointer failure")
   return "nonserialized"
  elseif s.ClassName=="Player" and p.Name=="PendingRequestedTool" then
   check(string.find(errorText,"not a valid member",1,true)~=nil,"unexpected unavailable Player pointer failure")
   return "nonserialized"
  end
 elseif s==game:GetService("StarterPlayer") and p.Name=="PlaceAvatarRules" and p.Serialized==true then
  check(string.find(errorText,"RobloxScript",1,true)~=nil,"unexpected serialized pointer failure")
  return "serialized"
 end
 error("unreadable Folder-compatible property: "..s:GetFullName().."."..p.Name..": "..errorText)
end
local function readSlots()
 check(#slots<=MAX_SLOTS,"compatible slot bound exceeded")
 for _,slot in slots do
  local read,value=pcall(function() return slot.owner[slot.name] end)
  check(read==slot.read,"reference property accessibility changed")
  if read then
   check(value==slot.value,"reference property changed")
   check(not capturedIndex[value],"inbound Folder-compatible reference")
  else
   check(tostring(value)==slot.error,"opaque reference error changed")
  end
 end
end
local baselineAuthoring
local function freshGuards()
 targetFacts()
 check(epoch==0,"foreign tree activity during port")
 local detached=0 for _ in attempted do detached+=1 end
 -- Native count plus the all-tree epoch; no giant Lua graph walk in write phase.
 check(#game:GetDescendants()==descendantCount-detached,"descendant inventory delta differs")
 for s,row in sources do check(state.same(scriptRow(s),row),"authoritative source/properties changed: "..row.path) end
 for s,row in remotes do check(state.same(remoteRow(s),row),"remote inventory/properties changed") end
 local seenRoots={}
 for _,f in SS:GetChildren() do
  local row=rootRows[f]
  check(row~=nil and not attempted[f] and f.Name==row.name and f.ClassName==row.class
   and f.Archivable==row.archivable and state.same(f:GetAttributes(),row.attributes)
   and state.same(tags(f),row.tags),"root inventory/properties differs")
  seenRoots[f]=true
 end
 for f in rootRows do if not attempted[f] then check(seenRoots[f],"foreign root removed") end end
 check(state.same(authoring(),baselineAuthoring),"selection/maps/importer-scratch changed")
 readSlots()
 check(owned() and not RS:IsRunning() and epoch==0,"final lease/mode/epoch changed")
end
local function domain()
 return {sources=sources,remotes=remotes,roots=rootRows,authoring=baselineAuthoring}
end
local function rollback()
 local failures={}
 for _,f in group do
  if attempted[f] then
   local restored,why=pcall(function()
    check(leaseOwned(),"rollback lease changed; preserve foreign state")
    if f.Parent==SS then attempted[f]=nil return end -- Setter failed before changing Parent, or already restored.
    check(f.Parent==nil,"rollback original reparented by another actor")
    check(state.same(state.factsOf(f),state.facts[capturedIndex[f]]),"rollback original data changed; preserve foreign edit")
    for _,sibling in SS:GetChildren() do check(sibling.Name~=f.Name,"rollback name collision") end
    prepareEvents(f,false)
    f.Parent=SS
    check(f.Parent==SS,"rollback did not restore exact original")
    attempted[f]=nil
   end)
   if not restored then table.insert(failures,{name=f.Name,error=tostring(why)}) end
  end
 end
 return failures
end
local ok,err=xpcall(function()
 local expectedNames=arraySet(ALL_NAMES)
 for i,f in state.roots do
  check(expectedNames[f.Name] and byName[f.Name]==nil,"captured names/identity differ")
  byName[f.Name]={ref=f,index=i}
  capturedIndex[f]=i
 end
 local seenNames={}
 for _,name in config.names do
  check(type(name)=="string" and not seenNames[name] and byName[name]~=nil,"bad/duplicate exact target name")
  seenNames[name]=true
  local f=byName[name].ref
  check(not port.removed[f] and f.Parent==SS,"requested group already removed/moved")
  targets[f]=true table.insert(group,f)
 end
 table.sort(report.names)
 trialKey=table.concat(report.names,"|")
 targetFacts()
 table.insert(connections,game.DescendantAdded:Connect(function(f) treeEvent("gameAdd",f) end))
 table.insert(connections,game.DescendantRemoving:Connect(function(f) treeEvent("gameRemove",f) end))
 table.insert(connections,SS.ChildAdded:Connect(function(f) treeEvent("rootAdd",f) end))
 table.insert(connections,SS.ChildRemoved:Connect(function(f) treeEvent("rootRemove",f) end))
 for _,f in SS:GetChildren() do
  rootRows[f]={name=f.Name,class=f.ClassName,archivable=f.Archivable,attributes=f:GetAttributes(),tags=tags(f)}
 end
 baselineAuthoring=authoring()
 local classes={}
 local caps=SecurityCapabilities.new(table.unpack(Enum.SecurityCapability:GetEnumItems()))
 local census=game:GetDescendants()
 descendantCount=#census
 for i,s in census do
  if s:IsA("LuaSourceContainer") then
   local row=scriptRow(s) sources[s]=row
   for _,name in ALL_NAMES do check(not string.find(row.source,name,1,true),"current source calls exact diagnostic name: "..row.path) end
  elseif isRemote(s) then remotes[s]=remoteRow(s) end
  local props=classes[s.ClassName]
  if props==nil then
   props={}
   local reflected=REF:GetPropertiesOfClass(s.ClassName,{Security=caps,ExcludeInherited=false,ExcludeDisplay=true})
   if reflected==nil then
    check(s.ClassName=="" and s.Name=="FilteredSelection" and s.Parent==game,"unreflected place class")
    table.insert(report.editorMetadataExceptions,{name=s.Name,class=s.ClassName})
    reflected=REF:GetPropertiesOfClass("Instance",{Security=caps,ExcludeInherited=false,ExcludeDisplay=true})
   end
   for _,p in reflected do
    if p.Name~="Parent" and p.Type.ScriptType=="Instance"
     and (p.Type.InstanceType=="Instance" or p.Type.InstanceType=="Folder" or p.Type.InstanceType=="Object") then table.insert(props,p) end
   end
   classes[s.ClassName]=props
  end
  for _,p in props do
   local read,value=pcall(function() return s[p.Name] end)
   local slot={owner=s,name=p.Name,read=read}
   if read then slot.value=value check(not capturedIndex[value],"inbound native reference to captured set")
   else
    slot.error=tostring(value)
    local kind=opaque(s,p,slot.error)
    local rows=if kind=="serialized" then report.serializedReferenceExceptions else report.nonserializedReadExceptions
    table.insert(rows,{path=s:GetFullName(),property=p.Name,type=p.Type.InstanceType,serialized=p.Serialized,error=slot.error})
   end
   table.insert(slots,slot) check(#slots<=MAX_SLOTS,"compatible slot bound exceeded")
  end
  if i%1000==0 then task.wait() end
 end
 freshGuards()
 if config.action=="remove" then
  local trial=assert(port.trials[trialKey],"identical group must pass trial first")
  check(trial.nativeSHA256==NATIVE_SHA and trial.referencesSHA256==REFERENCES_SHA
   and state.same(trial.domain,domain()),"trial baseline changed; repeat trial")
 end
 local native=SER:SerializeInstancesAsync(state.roots)
 local joint=table.clone(state.roots) table.insert(joint,game:GetService("StarterPlayer"))
 local references=SER:SerializeInstancesAsync(joint)
 -- Last yield precedes this caller-pinned SHA/CAS. No yield occurs in write/after/rollback.
 check(sha(native)==NATIVE_SHA,"current native target archive differs")
 check(sha(references)==REFERENCES_SHA,"fresh joint protected-reference proof differs")
 freshGuards()
 writing=true
 for _,f in group do
  check(owned() and not RS:IsRunning(),"write lease/mode changed")
  prepareEvents(f,true)
  attempted[f]=true -- Includes a setter that throws after changing Parent.
  f.Parent=nil
  check(f.Parent==nil,"same original was reparented during write")
 end
 freshGuards()
 report.absenceGuardsPass=true
 if config.action=="trial" then
  local failures=rollback()
  check(#failures==0,"trial rollback incomplete")
  freshGuards()
  report.sameOriginalsRestored=true
 else
  for _,f in group do port.removed[f]={name=f.Name,nativeSHA256=NATIVE_SHA,ref=f} end
  report.sameOriginalsRetained=true
 end
 if config.action=="trial" then
  -- Settle deferred tree events only after every original is safely restored.
  -- Actual removal never yields after the first Parent=nil assignment.
  task.wait()
  freshGuards()
  pendingTrial={nativeSHA256=NATIVE_SHA,referencesSHA256=REFERENCES_SHA,domain=domain()}
  report.settleGuardsPass=true
 end
end,debug.traceback)
if not ok then
 report.rollbackFailures=rollback()
 -- Own tentative remove bookkeeping must never outlive a restored original.
 if leaseOwned() then
  for _,f in group do if f.Parent==SS and attempted[f]==nil then port.removed[f]=nil end end
 end
end
for _,connection in connections do
 local clean,why=pcall(function() connection:Disconnect() end)
 if not clean then ok=false err=tostring(err).."\nwatcher cleanup failed: "..tostring(why) end
end
if ok then
 local guarded,why=pcall(freshGuards)
 if not guarded then ok=false err="post-cleanup guards failed: "..tostring(why) end
end
if not ok then
 -- Cleanup failure is also a failed port: independently restore own detached group.
 local failures=rollback()
 if #failures>0 then report.cleanupRollbackFailures=failures end
 if leaseOwned() then
  for _,f in group do if f.Parent==SS and attempted[f]==nil then port.removed[f]=nil end end
 end
end
report.pass=ok report.error=if ok then nil else tostring(err)
report.checks=checks report.referenceSlots=#slots
local sourceCount,remoteCount,rootCount=0,0,0
for _ in sources do sourceCount+=1 end
for _ in remotes do remoteCount+=1 end
for _ in rootRows do rootCount+=1 end
report.sources=sourceCount report.remotes=remoteCount report.descendantsBefore=descendantCount report.rootsBefore=rootCount
report.descendantsAfter=#game:GetDescendants()
report.rootsAfter=#SS:GetChildren()
report.retainedGroupRollbackReferences=0
for _,f in group do if f.Parent==nil then report.retainedGroupRollbackReferences+=1 end end
report.exactNameCallerChecks=sourceCount*#ALL_NAMES
report.capturedAtUtc=DateTime.now():ToIsoDate()
if leaseOwned() then
 if ok and pendingTrial then port.trials[trialKey]=pendingTrial end
 port.lastReport=report
 if not ok then
  -- Any partial state remains reachable for manual, guarded recovery.
  port.pendingRollback=group
 end
 state.portLease=nil
end
return HS:JSONEncode(report)
