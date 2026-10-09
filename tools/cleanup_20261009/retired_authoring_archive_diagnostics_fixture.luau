-- Offline current-common diagnostics/bounded-yield contract. No Studio/native instances.
local makeCommon=require("./native_common_fixture")
local expectedNames={"LobbyReimaginedBlenderSource20261001","LobbyReimaginedBlenderSource20261001R2",
 "LobbyReimaginedBlenderSource20261001R3","LobbyReimaginedBlenderSource20261001R3B","Level1BlenderKit"}
local expectedCounts={97,97,104,104,1215}
local scenarios={"none","epoch","mode","owned-lease","previous-lease","guard-epoch"}
local cases=0
for _,scenario in scenarios do
 local shared={} local running=false local waits=0 local onWait=function()end
 local function signal()
  local event={listeners={}}
  function event:Connect(callback)
   self.listeners[#self.listeners+1]=callback return {Disconnect=function()end}
  end
  function event:Fire(value)for _,fn in self.listeners do fn(value) end end
  return event
 end
 local function node(name,class)
  local value={Name=name,ClassName=class or "Folder",Archivable=true,Parent=nil,children={}}
  value.Changed=signal() value.AttributeChanged=signal() value.ChildAdded=signal() value.ChildRemoved=signal()
  function value:IsA(kind)return kind==self.ClassName or kind=="ValueBase" and self.ClassName=="StringValue" end
  function value:GetFullName()return self.Name end
  function value:GetChildren()return self.children end
  function value:GetDescendants()return self.children end
  function value:GetAttributes()return {}end
  function value:GetTags()return {}end
  function value:IsDescendantOf()return false end
  return value
 end
 local root=node("HeldOriginal")
 for i=1,500 do local child=node("Child"..i) child.Parent=root root.children[#root.children+1]=child end
 local previous={rootRefs={[root]={name=root.Name,class=root.ClassName}}}
 local game={PlaceId=131311258779917,GameId=10559217407}
 local services={HttpService={HttpEnabled=true},RunService={IsRunning=function()return running end},
  ReflectionService={GetPropertiesOfClass=function()return {{Name="Name",Serialized=false},{Name="Source",Serialized=false},{Name="Value",Serialized=false}}end}}
 function game:GetService(name)return services[name] or {}end
 local fakeTypeof=function(value)if type(value)=="table" and value.ClassName then return "Instance" end return typeof(value) end
 local A=makeCommon(game,shared,{new=function()return {}end},
  {SecurityCapability={GetEnumItems=function()return {}end}},fakeTypeof,{wait=function()waits+=1 onWait()end})
 for i,name in expectedNames do assert(A.NAMES[i]==name and A.COUNTS[i]==expectedCounts[i],"Five-root scope changed") end
 assert(#A.NAMES==5 and #A.COUNTS==5)
 local state={epoch=0,connections={},knownOriginals={},watchersConnected=true,baselineComplete=false}
 shared[A.KEY]=state shared[A.ORIGINAL_KEY]=previous
 onWait=function()
  if scenario=="epoch" then root.Changed:Fire("Name")
  elseif scenario=="mode" then running=true
  elseif scenario=="owned-lease" then shared[A.KEY]={foreign=true}
  elseif scenario=="previous-lease" then previous.probeLease={} end
 end
 local ok=pcall(function()A.heldOriginals(state)end)
 assert(ok==(scenario=="none" or scenario=="guard-epoch"),scenario)
 assert(waits==1,"Held baseline must yield at 500 nodes")
 local diagnostic=A.diagnostics(state)
 if scenario=="epoch" then
  assert(diagnostic.epoch==1 and diagnostic.epochReasons[1].property=="Name")
  assert(diagnostic.lastGuardObservation.epoch==1 and diagnostic.context.ownedLease)
 elseif scenario=="mode" then assert(diagnostic.lastGuardObservation.running==true)
 elseif scenario=="owned-lease" then assert(not diagnostic.lastGuardObservation.ownedLease)
 elseif scenario=="previous-lease" then assert(not diagnostic.lastGuardObservation.previousProbeLeaseAbsent)
 elseif scenario=="guard-epoch" then
  onWait=function()root.Changed:Fire("Name")end
  assert(not pcall(function()A.guardHeld(state)end),"Guard-yield epoch must reject")
  assert(waits==2 and state.lastGuardObservation.checkpoint=="held guard yield")
 else
  local secret="UNLOGGABLE_SOURCE_OR_VALUE_BODY_123456789"
  local stringValue=node("FixtureStringValue","StringValue")
  for _=1,70 do A.event(state,"fixture.Changed",stringValue,secret)end
  assert(state.epoch==70 and #state.epochReasons==32 and state.epochReasonDropped==38)
  assert(state.lastEpochReason.property=="Value" and state.epochReasons[1].argumentKind=="string")
  local function inspect(value)
   if type(value)=="table" then for _,child in value do inspect(child)end
   elseif type(value)=="string" then assert(not string.find(value,secret,1,true),"Diagnostic leaked Source/value body") end
  end
  inspect(A.diagnostics(state))
  A.properties("ModuleScript")
  local script=node("FixtureModuleScript","ModuleScript")
  A.event(state,"fixture.Changed",script,secret)
  assert(state.lastEpochReason.property=="<unclassified property>")
  A.event(state,"fixture.AttributeChanged",script,secret)
  inspect(A.diagnostics(state))
 end
 cases+=1
end
print("S04 offline current-common diagnostic scenarios passed: "..cases)
