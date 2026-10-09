"""Run actual Level 5/6 lifecycle source regions with deterministic engine boundaries.

The default reads canonical mirrors; --candidate reads only this task's candidates.
No Studio/network operations. Fixtures do not establish native streaming/gameplay.
"""
import argparse
import importlib.util
import os
from pathlib import Path
import shutil
import subprocess
import tempfile

ROOT = Path(__file__).resolve().parents[2]
HERE = Path(__file__).parent
spec = importlib.util.spec_from_file_location('primitives', ROOT/'tools/tests/test_round_entry_client.py')
fixture = importlib.util.module_from_spec(spec)
spec.loader.exec_module(fixture)
PRIMITIVES = fixture.HARNESS[:fixture.HARNESS.index('local function context()')]


def region(source, start, stop):
    begin = source.index(start)
    return source[begin:source.index(stop, begin)]


HARNESS = r'''
Vector3.zero=Vector3.new(0,0,0);Vector3.xAxis=Vector3.new(1,0,0);Vector3.zAxis=Vector3.new(0,0,1)
local CFrame={lookAt=function(point,other) return {Position=point,LookVector=Vector3.zAxis} end,
 new=function(point) return {Position=point} end}
local Color3={new=function(...) return {...} end}
local Content={fromObject=function(object) return object end}
Enum.CreateContentResult={Success="Success"};Enum.CollisionFidelity={Box="Box"};Enum.Material={SmoothPlastic="SmoothPlastic"}
Enum.HumanoidStateType={Seated="Seated",Dead="Dead"}
local oldIsA=nodeMethods.IsA
function nodeMethods:IsA(class) return oldIsA(self,class) or class=="Light" and (self.ClassName=="PointLight" or self.ClassName=="SpotLight") end
function nodeMethods:GetPivot() return {Position=self.Root.Position,LookVector=Vector3.zAxis} end
function nodeMethods:GetChildren() return self.Children end
function nodeMethods:PivotTo(frame)
 self.Root.Position=frame.Position
 if self.TestContext and self.TestContext.PivotAdvance then
  self.TestContext.Now+=self.TestContext.PivotAdvance;self.TestContext.PivotAdvance=nil
 end
end
function nodeMethods:Destroy() self.Destroyed=true;self.Parent=nil end
local function bindableCopy(value,seen)
 if type(value)~="table" or value.Kind then return value end
 seen=seen or {};if seen[value] then return seen[value] end
 local copy={};seen[value]=copy
 for k,v in pairs(value) do copy[bindableCopy(k,seen)]=bindableCopy(v,seen) end
 return copy
end
function nodeMethods:Invoke(...)
 local args=table.pack(...)
 for i=1,args.n do args[i]=bindableCopy(args[i]) end
 if self.OwnerContext then
  local ctx=self.OwnerContext;ctx.BindableCalls=ctx.BindableCalls or {}
  table.insert(ctx.BindableCalls,{name=self.Name,token=self.Name=="Level6EnterFromLevel" and args[3] or args[2]})
 end
 return self.OnInvoke(table.unpack(args,1,args.n))
end
local function context()
 local ctx={Now=100,Queue={},PlayersList={},New={},Warns={},StreamReady=true,FloorChecks=0,Streams=0,
  ActivateCalls=0,ParkCalls=0,Timeline={},Phase="idle",FinaleResets=0,GameScans=0}
 ctx.Workspace=node("Workspace","Workspace");ctx.Workspace.ChildAdded=signal();ctx.Storage=node("ServerStorage","ServerStorage")
 ctx.Players={GetPlayers=function() return ctx.PlayersList end,PlayerRemoving=signal()}
 ctx.Task={spawn=function(fn,...)
   local args={...};table.insert(ctx.Queue,{Thread=coroutine.create(function() fn(table.unpack(args)) end),At=ctx.Now}) end,
  wait=function(seconds) return coroutine.yield(seconds or .03) end,
  delay=function(seconds,fn) table.insert(ctx.Queue,{Thread=coroutine.create(fn),At=ctx.Now+seconds}) end}
 function ctx:Advance(delta)
  local target=self.Now+delta;local steps=0
  while true do
   local index,first
   for i,t in ipairs(self.Queue) do if not first or t.At<first.At then index,first=i,t end end
   if not first or first.At>target then break end
   table.remove(self.Queue,index);self.Now=first.At;steps+=1;assert(steps<10000,"scheduler runaway")
   local ok,delay=coroutine.resume(first.Thread);assert(ok,delay)
   if coroutine.status(first.Thread)~="dead" then first.At=self.Now+(delay or .03);table.insert(self.Queue,first) end
  end
  self.Now=target
 end
 ctx.Instance={new=function(class) local item=node(class,class);item.OwnerContext=ctx;table.insert(ctx.New,item);return item end}
 local oldStorageFind=ctx.Storage.FindFirstChild
 function ctx.Storage:FindFirstChild(name)
  for _,item in ipairs(ctx.New) do if item.Parent==self and item.Name==name then return item end end
  return oldStorageFind(self,name)
 end
 ctx.Models={}
 for _,level in ipairs({5,6}) do
  local model=node("Model",level==5 and "Level 5 Void" or "Level 6 Indoor Playground",ctx.Storage)
  model:SetAttribute("Level"..level.."Preview",true);model:SetAttribute("PreviewOnly",true)
  model:SetAttribute("Level"..level.."PreviewReady",true);model:SetAttribute("Origin",Vector3.zero)
  local exit=node("Part","Level"..level.."Exit",model)
  exit.Position=Vector3.new(level==5 and 200 or 500,5,0);exit.CFrame={Position=exit.Position,LookVector=Vector3.zAxis}
  local prompt=node("ProximityPrompt","Level"..level.."DeveloperPreviewReturnPrompt",exit);prompt.Enabled=true
  model.Exit=exit;ctx.Models[level]=model
 end
 local slideHolder=node("Folder","Slides",ctx.Models[6]);node("Folder","Level6ArenaSlideSource",ctx.Storage)
 local oldSlideFind=slideHolder.FindFirstChild
 function slideHolder:FindFirstChild(name)
  if ctx.BakedPart and ctx.BakedPart.Parent==self and ctx.BakedPart.Name==name then return ctx.BakedPart end
  return oldSlideFind(self,name)
 end
 local oldWorkspaceFind=ctx.Workspace.FindFirstChild
 function ctx.Workspace:FindFirstChild(name)
  for _,model in pairs(ctx.Models) do if model.Name==name and model.Parent==self then return model end end
  return oldWorkspaceFind(self,name)
 end
 ctx.WorldStorage={Get=function(level) return ctx.Models[level] end,
  Activate=function(level)
   ctx.ActivateCalls+=1
   if ctx.MissingWorld then return nil end
   local model=ctx.Models[level];local changed=model.Parent~=ctx.Workspace
   model.Parent=ctx.Workspace;table.insert(ctx.Timeline,"activate"..level)
   if changed then ctx.Workspace.ChildAdded:Fire(model) end
   return model
  end,
  Deactivate=function(level)
   local model=ctx.Models[level]
   if model.Parent==ctx.Workspace then ctx.ParkCalls+=1;table.insert(ctx.Timeline,"park"..level);model.Parent=ctx.Storage end
   return model
  end}
 function ctx.Workspace:Raycast(_,_,params)
  local model=params.FilterDescendantsInstances[1];ctx.FloorChecks+=1
  table.insert(ctx.Timeline,"floor"..model:GetAttribute("LevelNumber"))
  if ctx.NoFloor or model.Parent~=self then return nil end
  return {Normal=Vector3.yAxis}
 end
 for level,model in pairs(ctx.Models) do model:SetAttribute("LevelNumber",level) end
 function ctx:Player(name)
  local player=node("Player",name);player.Parent=self.Players;player.Allowed=true
  local character=node("Model",name.."Character",self.Workspace)
  local root=node("Part","HumanoidRootPart",character);root.Position=Vector3.zero;root.Anchored=false
  local humanoid=node("Humanoid","Humanoid",character);humanoid.Health=100;humanoid.RootPart=root
  function humanoid:GetState() return "Running" end
  character.Root=root;character.TestContext=self;player.Character=character;player.Humanoid=humanoid;player.Root=root
  table.insert(self.PlayersList,player);return player
 end
 ctx.Door=node("Part","Door",ctx.Workspace);ctx.Door.Position=Vector3.zero
 ctx.EntryPrompt=node("ProximityPrompt","Entry",ctx.Door)
 ctx.DevAccess={IsLevel5Allowed=function(p) return p.Allowed end,IsLevel6Allowed=function(p) return p.Allowed end}
 ctx.Bridge={RegisterPreviewLauncher=function(level,_,callbacks) ctx.Callbacks=ctx.Callbacks or {};ctx.Callbacks[level]=callbacks end,
  LockPreviewController=function(context,nextUse,locks)
   for _,player in ipairs(context.Members or {context.Player}) do locks[player]=context;nextUse[player]=math.huge end
   return true
  end,
  PreparePreviewGroup=function(context,model,exit,stream)
   if ctx.PrepareThrow then error("prepare fixture failure") end
   local entries={}
   for _,player in ipairs(context.Members or {context.Player}) do
    if not stream(player,exit.Position) or ctx.PrepareFail then return nil,"STREAM_FAILED" end
    table.insert(entries,{player=player,character=player.Character,frame=exit.CFrame})
   end
   return entries
  end,
  CommitPreviewGroup=function(_,entries,commit,rollback)
   if ctx.CommitDelay then ctx.Task.wait(ctx.CommitDelay) end
   if ctx.CommitThrow then error("commit fixture failure") end
   for _,entry in ipairs(entries) do
    entry.character:PivotTo(entry.frame)
    if not commit(entry) then rollback(entry);return false,"JOIN_FAILED" end
    if ctx.AfterCommit then ctx.AfterCommit(entry);rollback(entry);return false,"LATER_COMMIT_FAILED" end
   end
   return true
  end,
  PartyLandings=function() return {} end}
 return ctx
end
local function run(ctx,fn,delta) ctx.Task.spawn(fn);ctx:Advance(delta or .1) end
local function boot(ctx)
 local Players,workspace,ServerStorage,WorldStorage=ctx.Players,ctx.Workspace,ctx.Storage,ctx.WorldStorage
 local DevAccess,Instance,task=ctx.DevAccess,ctx.Instance,ctx.Task
 local os={clock=function() return ctx.Now end}
 local warn=function(message) table.insert(ctx.Warns,message) end
 local HttpService={GenerateGUID=function()
  ctx.GuidCalls=(ctx.GuidCalls or 0)+1;return "fixture-guid-"..ctx.GuidCalls
 end,JSONDecode=function()return {verts={},normals={},colours={},tris={}}end}
 local function r3Bridge() return ctx.Bridge end
 local function beginR3Entry() end
 local function finishR3Entry() end
 local function isR3Entry() return false end
 local function tell() end
 local function hookExit() end
 local ReplicatedStorage={FindFirstChild=function() return nil end}
 local function stream(player,position)
  ctx.Streams+=1
  local delay=ctx.StreamDelays and ctx.StreamDelays[player] or ctx.StreamDelay
  if delay then task.wait(delay) end
  if ctx.StreamThrow then error("stream fixture failure") end
  if ctx.StreamResults and ctx.StreamResults[player]~=nil then return ctx.StreamResults[player] end
  return ctx.StreamReady
 end
 local streamReady=stream
 local transport={FireClient=function() end}
 local event={FireClient=function() end}
 local returnHandler=function() end
 local roundStatus={FireClient=function() end}
 local CONFIG={EntityEnabled=true}
 local session=nil
 local lifeWatch={}
 local Session={}
 local Game={}
 local arenaSlides={busy=false,job=false}
 local function finaleReset() ctx.FinaleResets+=1 end
__GAME_STATE__
__GAME_REMOVE__
__SESSION_FINISH__
__GAME_DISCONNECT__
 local Playground=Game
 function Game.AddPlayer(player)
  if ctx.JoinFail then return false,"JOIN_FAILED" end
  if not session then
   session=setmetatable({active=true,phase="counting",players={},info={model=ctx.Models[6],arena=true},escapedCount=0,
    heartbeat={Disconnect=function() ctx.HeartbeatDisconnected=true end},
    child={Destroy=function() ctx.ChildDestroyed=true end}}, {__index=Session})
   function session:count() local count=0;for _ in pairs(self.players) do count+=1 end;return count end
   function session:living() return self:count() end
   function session:target() return math.max(1,self:count()) end
   ctx.Session=session
  end
  session.players[player]={}
  if ctx.JoinThrow then error("partial AddPlayer fixture failure") end
  return true
 end
 local Void={}
 local IN_LEVEL,LIVE,MODEL_NAME,EXIT_NAME,RETURN_PROMPT="Level5VoidRound","Level6PlaygroundPreview","Level 5 Void","Level5Exit","Level5DeveloperPreviewReturnPrompt"
 local nextUse,members,leaving={}, {}, {}
 local COOLDOWN=2
 local function liveDoor() return ctx.Door end
 local function upright(position) return {Position=position,LookVector=Vector3.zAxis} end
__L5_READY__
__L5_PLAYER__
__L5_RELEASE__
__L5_FLOOR__
__L5_CLAIM__
__L5_JOIN__
__L5_LEAVE__
__L5_CONTINUE__
__L5_DISCONNECT__
 function Void.TellBusy() ctx.BusyNotice=true end
 function Void.Suit(player,frame) player:SetAttribute("InRound",true);player.Character:PivotTo(frame) end
__L5_ENTER__
 local enter5=onEnter
__L5_QUEUE__
__L5_PARTY__
 local function checkpoints() return {{}} end
 local function plateRecords() ctx.GameScans+=1;return ctx.PlateRecords or {} end
 local function moveGate(record,open) record.open=open;table.insert(ctx.Timeline,"gateReset") end
 local function movePlate() table.insert(ctx.Timeline,"plateReset") end
 local function tendBalls() ctx.GameScans+=1 end
 local function tick5()
  for _=1,1 do
__L5_LIVE_GUARD__
__L5_MEMBER_CLEANUP__
   local empty=next(members)==nil
   for _,record in ipairs(plateRecords(model)) do
__L5_EMPTY_RESET__
   end
   tendBalls(model)
__L5_PARK__
  end
 end
 local api5={Claim=Void.Claim,LetGo=Void.LetGo,Join=Void.Join,Leave=Void.Leave,Continue=Void.Continue,Enter=enter5,
  Ready=readyPreview,Tick=tick5,Member=function(p) return members[p] end,
  Finale=function(state) finale.state=state end,Hold=function() return hold.token,hold.untilClock end}
 local Runtime={}
 local IN_PREVIEW,MODEL_NAME,EXIT_NAME="Level6PlaygroundPreview","Level 6 Indoor Playground","Level6Exit"
 local nextUse={}
 local function lobbyPart(name) return name=="Level6SealedDoor" and ctx.Door or nil end
__L6_ENSURE__
__L6_LEAVE__
__L6_CLAIM__
__L6_DISCONNECT__
 function Runtime.Emptied() letGo(nil) end
 local function tellBusy() ctx.BusyNotice=true end
__L6_JOIN__
__L6_PLAYER__
__L6_READY_FLOOR_UPRIGHT__
__L6_RELEASE__
 local function returnPrompt(exit) return exit and exit:FindFirstChild("Level6DeveloperPreviewReturnPrompt") end
 function Runtime.Suit(player,frame)
  ctx.SuitCalls=(ctx.SuitCalls or 0)+1
  if ctx.SuitDelay then task.wait(ctx.SuitDelay) end
  player:SetAttribute("InRound",true)
  if not ctx.LoadFail then player.Character:PivotTo(frame) end
 end
__L6_ENTER__
 local enter6=onEnter
__L6_QUEUE__
__L6_CONTINUE_BINDABLE__
__L6_PARTY__
 local function tick6()
__L6_POLL__
 end
 local api6={Claim=claim,LetGo=letGo,Join=Runtime.Join,Leave=Runtime.Leave,Enter=enter6,Ready=previewReady,Tick=tick6,
  Hold=function() return partyLock.token,partyLock.holdUntil end,
  Finish=function() if session then session:finish() end end,
  State=Game.State}
 local AssetService={CreateEditableMesh=function()
  return {Destroy=function() ctx.EditableDestroyed=true end}
 end,
 CreateDataModelContentAsync=function(_,mesh)
  if ctx.BakeDelay then task.wait(ctx.BakeDelay) end
  return Enum.CreateContentResult.Success,mesh
 end,
 CreateMeshPartAsync=function()
  if ctx.PartDelay then task.wait(ctx.PartDelay) end
  ctx.BakedPart=node("MeshPart","Baked");return ctx.BakedPart
 end}
__SLIDE_BUILD__
__SLIDE_JOB__
 local function liveServer(level)
  local LEVEL,info,MARKER=level,{},"Level6PlaygroundPreview"
  local arrivals,parties={},{}
  local print=function()end
__LIVE_PACKET__
__LIVE_ONPLAYER__
__LIVE_STANDING__
__LIVE_LAUNCH__
  return {Add=function(p,session)
   function p:GetJoinData()return {TeleportData={LiveLevel=level,LiveSession=session,Expected=2}}end
   onPlayer(p)
  end,Launch=function(session,list)return launch(session,parties[session],list)end,
  Party=function(session)return parties[session]end}
 end
 local litBefore={};local exitLamp={bulb=nil,base=0}
 local function clearReplica(model)
__CLIENT_CLEAR__
 end
 return api5,api6,arenaSlides.build,litBefore,exitLamp,clearReplica,prepareSlides,liveServer
end
'''

TESTS = r'''
local function fresh() local ctx=context();local a,b,slides,lit,lamp,clear,prepare,live=boot(ctx);return ctx,a,b,slides,lit,lamp,clear,prepare,live end
do
 local ctx,a,b=fresh()
 local m5,m6=ctx.Models[5],ctx.Models[6]
 check(a.Ready()==m5 and b.Ready()==m6,"dormant metadata and return anchors remain available")
 check(ctx.Callbacks[5].ready()==m5 and ctx.Callbacks[6].ready()==m6,"queue readiness accepts dormant authored worlds")
 check(ctx.ActivateCalls==0 and ctx.FloorChecks==0,"readiness probes neither mount maps nor pretend parked floor rays succeed")
 a.Tick();b.Tick()
 check(ctx.GameScans==0 and ctx.ActivateCalls==0,"inactive Level 5 gameplay loop never scans parked geometry")
end
do
 local ctx,a,b=fresh();local group={};local other={}
 check(a.Claim(group) and ctx.Models[5].Parent==ctx.Workspace,"accepted Level 5 claim mounts its original model")
 a.Tick();check(ctx.Models[5].Parent==ctx.Workspace,"pending Level 5 stream claim retains map with no joined member")
 check(not a.Claim(other),"another Level 5 group cannot steal an in-flight claim")
 ctx:Advance(91);a.Tick();check(ctx.Models[5].Parent==ctx.Storage,"expired abandoned Level 5 claim parks map")
 check(a.Claim(other),"Level 5 can activate the same map on second entry")
 local p=ctx:Player("dead5");check(a.Join(p,other),"Level 5 joins its reserved party")
 p.Humanoid.Health=0;a.Member(p).dead=true;ctx:Advance(91);a.Tick()
 check(ctx.Models[5].Parent==ctx.Workspace,"dead Level 5 members retain map for paid reentry and ending")
 a.Leave(p,true);ctx.PlateRecords={{locked=true,quiet=true,open=true}};a.Tick()
 check(ctx.Models[5].Parent==ctx.Storage and not ctx.PlateRecords[1].locked,"empty Level 5 resets locked gates before parking")
 local gate,park
 for index,item in ipairs(ctx.Timeline) do if item=="gateReset" then gate=index elseif item=="park5" then park=index end end
 check(gate and park and gate<park,"actual empty gate reset precedes deactivation")
 a.Finale("resetting");check(not a.Claim({}),"fresh Level 5 party cannot overlap old finale reset")
 ctx.Models[5].Parent=ctx.Workspace;a.Tick()
 check(ctx.Models[5].Parent==ctx.Workspace,"busy Level 5 finale cleanup prevents parking")
 a.Finale("idle");a.Tick();check(ctx.Models[5].Parent==ctx.Storage,"Level 5 parks after finale cleanup completes")
end
for _,level in ipairs({5,6}) do
 local ctx,a,b=fresh();local api=level==5 and a or b;ctx.MissingWorld=true
 check(not api.Claim({}),"missing authored world rejects Level "..level.." claim")
 check(api.Hold()==nil,"failed activation clears Level "..level.." reservation")
end
for _,level in ipairs({5,6}) do
 local ctx,a,b=fresh();local api=level==5 and a or b;local p=ctx:Player("entry"..level)
 run(ctx,function() api.Enter(p,ctx.EntryPrompt) end)
 check(ctx.Models[level].Parent==ctx.Workspace and p:GetAttribute("Level6PlaygroundPreview")==true,
  "actual E entry activates Level "..level.." before authorized join")
 check(ctx.Streams==1 and ctx.FloorChecks>=2,"actual E entry retains real floor checks around streaming")
 local active,floor
 for index,item in ipairs(ctx.Timeline) do if item=="activate"..level and not active then active=index end
  if item=="floor"..level and not floor then floor=index end end
 check(active and floor and active<floor,"Level "..level.." floor is checked only after actual activation")
 api.Leave(p,true)
 if level==6 then b.Tick();check(ctx.Models[6].Parent==ctx.Workspace,"last Level 6 leave waits for session cleanup");b.Finish() end
 api.Tick();check(ctx.Models[level].Parent==ctx.Storage,"actual E leave eventually parks Level "..level)
end
for _,level in ipairs({5,6}) do
 for _,failure in ipairs({"NoFloor","StreamReady"}) do
  local ctx,a,b=fresh();local api=level==5 and a or b;local p=ctx:Player("failed")
  if failure=="NoFloor" then ctx.NoFloor=true else ctx.StreamReady=false end
  run(ctx,function() api.Enter(p,ctx.EntryPrompt) end)
  api.Tick()
  check(p:GetAttribute("Level6PlaygroundPreview")~=true and ctx.Models[level].Parent==ctx.Storage,
   "actual Level "..level.." E failure releases and parks: "..failure)
 end
end
for _,level in ipairs({5,6}) do
 local ctx,a,b=fresh();local p=ctx:Player("queued");local api=level==5 and a or b
 local accepted
 run(ctx,function() accepted=ctx.Callbacks[level].launch({Player=p}) end)
 check(accepted==true and ctx.Models[level].Parent==ctx.Workspace,"actual queue launch mounts Level "..level)
 check(ctx.Streams==1 and ctx.FloorChecks>=1,"actual queue keeps post-mount floor/stream checks")
 api.Leave(p,true);if level==6 then b.Finish() end;api.Tick()
 check(ctx.Models[level].Parent==ctx.Storage,"queue member removal eventually parks Level "..level)
end
for _,level in ipairs({5,6}) do
 local ctx,a,b=fresh();local p=ctx:Player("live");local api=level==5 and a or b;local joined,count
 local launcher=ctx.Storage:FindFirstChild("Level"..level.."LaunchParty")
 run(ctx,function() joined,count=launcher:Invoke({p},{}) end)
 check(joined and count==1 and ctx.Models[level].Parent==ctx.Workspace,"actual live-party launcher mounts Level "..level)
 check(ctx.Streams==1 and ctx.FloorChecks>=1,"live-party launcher checks actual floor after mounting")
 api.Leave(p,true);if level==6 then b.Finish() end;api.Tick()
 check(ctx.Models[level].Parent==ctx.Storage,"live-party leave eventually parks Level "..level)
end
do
 local ctx,a,b=fresh();local p=ctx:Player("transfer");local group={}
 check(a.Claim(group) and a.Join(p,group),"continuing player begins as Level 5 member")
 p:SetAttribute("InRound",true);run(ctx,function() a.Continue(p) end)
 check(not a.Member(p) and p:GetAttribute("Level5VoidRound")~=true,"actual Continue removes old Level 5 membership")
 a.Tick();check(ctx.Models[5].Parent==ctx.Storage and ctx.Models[6].Parent==ctx.Workspace,"successful transfer releases old map and keeps selected map")
 check(p:GetAttribute("Level6PlaygroundPreview")==true and b.State().phase~="idle","successful continuation joins actual Level 6 lifecycle")
 check(type(group.level6PartyToken)=="string" and ctx.GuidCalls==1,"Continue mints one scalar party identity on its actual Level 5 group")
 local tokens={};for _,call in ipairs(ctx.BindableCalls)do if call.name=="Level6EnterFromLevel"then table.insert(tokens,call.token)end end
 check(#tokens==2 and tokens[1]==group.level6PartyToken and tokens[2]==tokens[1],"prepare and enter preserve scalar identity across actual Invoke table-copy boundary")
end
do
 local ctx,a,b=fresh();local p,q=ctx:Player("continue first"),ctx:Player("continue late");local group={}
 a.Claim(group);a.Join(p,group);a.Join(q,group);p:SetAttribute("InRound",true);q:SetAttribute("InRound",true)
 run(ctx,function()a.Continue(p)end);run(ctx,function()a.Continue(q)end);a.Tick()
 check(not a.Member(p) and not a.Member(q) and ctx.Models[5].Parent==ctx.Storage,"both continuing cohort members release the old map across copied Invoke calls")
 check(ctx.GuidCalls==1 and b.Hold()==group.level6PartyToken and ctx.Session:count()==2,"late continuer reuses one scalar party and joins the same Level 6 session")
end
do
 local ctx,a,b=fresh();local p=ctx:Player("failed transfer");local group={}
 a.Claim(group);a.Join(p,group);p:SetAttribute("InRound",true);ctx.StreamReady=false
 run(ctx,function() a.Continue(p) end)
 a.Tick();b.Tick()
 check(a.Member(p)~=nil and ctx.Models[5].Parent==ctx.Workspace,"failed destination preparation retains original Level 5 map/member")
 check(ctx.Models[6].Parent==ctx.Storage and b.Hold()==nil,"failed continuation releases unused Level 6 reservation")
 ctx:Advance(3.2);a.Tick();check(ctx.Models[5].Parent==ctx.Storage,"existing failed-transfer recovery releases Level 5 later")
end
do
 local ctx,a,b=fresh();local p=ctx:Player("invalid")
 local enter=ctx.Storage:FindFirstChild("Level6EnterFromLevel")
 check(not enter.OnInvoke(p,"invalid",{}),"invalid continuation step is rejected")
 check(ctx.ActivateCalls==0 and ctx.Models[6].Parent==ctx.Storage,"invalid continuation never mounts Level 6")
end
do
 local ctx,a,b=fresh();local p=ctx:Player("dead6");local group={};b.Claim(group);b.Join(p,group)
 p.Humanoid.Health=0;ctx.Session.players[p].dead=true;ctx:Advance(91);b.Tick()
 check(ctx.Models[6].Parent==ctx.Workspace,"Level 6 dead participant retains map during reentry window")
 b.Leave(p,true);b.Tick()
 check(ctx.Models[6].Parent==ctx.Workspace and b.State().phase~="idle","RemovePlayer interrupt alone cannot park Level 6")
 check(not b.Claim({}),"fresh Level 6 claim cannot overlap unfinished previous session cleanup")
 b.Finish();b.Tick()
 check(ctx.HeartbeatDisconnected and ctx.ChildDestroyed and ctx.FinaleResets==1,"actual finish disconnects heartbeat, destroys owned doll and resets finale")
 check(b.State().phase=="idle" and ctx.Models[6].Parent==ctx.Storage,"parking follows actual session=nil cleanup")
 check(b.Claim({}),"Level 6 accepts a second party after prior cleanup completed")
end
do
 local ctx,a,b=fresh();local p=ctx:Player("shared leave");local group={};a.Claim(group);a.Join(p,group)
 a.Member(p).suited=true;p:SetAttribute("InRound",false);p:SetAttribute("Level6PlaygroundPreview",nil)
 a.Tick();check(not a.Member(p) and ctx.Models[5].Parent==ctx.Storage,"shared-marker cleanup drops member and frees old Level 5 hold")
end
do
 local ctx,a,b=fresh();local p=ctx:Player("ending6");local group={};b.Claim(group);b.Join(p,group)
 p.Humanoid.Health=0;b.Finish();ctx:Advance(91);b.Tick()
 check(b.State().phase=="idle" and ctx.Models[6].Parent==ctx.Workspace,"Level 6 participant marker retains completed map during ending/reentry window")
 b.Leave(p,true);b.Tick();check(ctx.Models[6].Parent==ctx.Storage,"last ending-window marker removal releases map")
end
for _,level in ipairs({5,6}) do
 local ctx,a,b=fresh();local api=level==5 and a or b;local group={};local p=ctx:Player("disconnect"..level)
 api.Claim(group);api.Join(p,group);ctx.Players.PlayerRemoving:Fire(p);table.remove(ctx.PlayersList,1);p.Parent=nil
 api.Tick();if level==6 then check(ctx.Models[6].Parent==ctx.Workspace,"disconnect waits for Level 6 session cleanup");b.Finish();b.Tick() end
 check(api.Hold()==nil and ctx.Models[level].Parent==ctx.Storage,"actual disconnect handler releases final Level "..level.." reservation")
end
for _,level in ipairs({5,6}) do
 local ctx,a,b=fresh();local api=level==5 and a or b;local group={};local p,q=ctx:Player("first"),ctx:Player("second")
 api.Claim(group);check(api.Join(p,group) and api.Join(q,group),"same party admits both Level "..level.." members")
 api.Leave(p,true);ctx:Advance(91);api.Tick()
 check(ctx.Models[level].Parent==ctx.Workspace,"remaining Level "..level.." party member retains original map after hold expiry")
 api.Leave(q,true);if level==6 then b.Finish() end;api.Tick()
 check(ctx.Models[level].Parent==ctx.Storage,"last Level "..level.." party member releases map")
end
do
 local ctx,a,b,slides,lit,lamp,clear=fresh();local model=ctx.Models[6]
 local holder=model:FindFirstChild("Slides");local baked=node("MeshPart","RuntimeSlide",holder)
 local source=ctx.Storage:FindFirstChild("Level6ArenaSlideSource");node("Folder","RuntimeSlide",source)
 check(#ctx.Queue==0 and b.State().phase=="idle","parked startup schedules no slide build or decode")
 check(ctx.ActivateCalls==0 and model.Parent==ctx.Storage,"startup never activates the map")
 ctx:Advance(600);local group={};b.Claim(group)
 check(b.Claim(group),"own pending party can repeat Claim before its deferred bake starts")
 ctx:Advance(.1)
 check(b.State().phase=="idle" and model==ctx.Models[6] and holder:FindFirstChild("RuntimeSlide")==baked,"late first mount prepares the same persistent slide instance")
 b.LetGo(group);b.Tick();b.Claim({});ctx:Advance(.1)
 check(holder:FindFirstChild("RuntimeSlide")==baked,"second mount never drops persistent generated dressing")
 local spot=node("SpotLight","Changed");spot.Parent={};spot.Color="red";spot.Brightness=30;spot.Angle=85
 lit[spot]={"normal",2,40};local bulb=node("PointLight","Exit");bulb.Parent={};bulb.Brightness=.2;lamp.bulb, lamp.base=bulb,1
 clear(nil)
 check(next(lit)==nil and lamp.bulb==nil,"replica removal releases all strong lamp references")
 check(spot.Color=="normal" and spot.Brightness==2 and spot.Angle==40 and bulb.Brightness==1,"replica cleanup restores every borrowed light property")
end
do
 local ctx,a,b,slides,lit,lamp,clear,prepare=fresh();local model=ctx.Models[6]
 node("Folder","MissingSlide",ctx.Storage:FindFirstChild("Level6ArenaSlideSource"))
 local group={};b.Claim(group);prepare(model);ctx:Advance(.1)
 check(#ctx.Warns==1 and #ctx.Queue==1,"duplicate mount triggers share one bounded preparation job: warns="..#ctx.Warns.." queued="..#ctx.Queue)
 b.LetGo(group);b.Tick();check(model.Parent==ctx.Storage and b.State().phase=="idle","failed bake retry wait permits an empty map to park")
 ctx:Advance(6)
 check(b.State().phase=="idle" and #ctx.Queue==0 and #ctx.Warns==1,"unmount stops pending bake retries and releases preparing ownership")
 b.Claim({});ctx:Advance(.1)
 check(#ctx.Warns==2 and b.State().phase=="idle","later remount starts a fresh bounded retry job without holding an idle map")
 ctx:Advance(241)
 check(b.State().phase=="idle" and #ctx.Queue==0 and #ctx.Warns==41,"slide failure retries are bounded to forty per active mount")
end
do
 local ctx,a,b,slides,lit,lamp,clear,prepare=fresh();local model=ctx.Models[6]
 local item=node("Folder","NewSlide",ctx.Storage:FindFirstChild("Level6ArenaSlideSource"))
 item:SetAttribute("Parts",0);item:SetAttribute("Centre",Vector3.zero);ctx.BakeDelay=2
 local group={};b.Claim(group);prepare(model);ctx:Advance(.1)
 check(b.State().phase=="preparing" and b.Claim(group),"same pending party can repeat Claim during actual yielding bake")
 b.LetGo(group);b.Tick();check(model.Parent==ctx.Workspace,"actual non-cancelable bake retains map until worker drains")
 ctx:Advance(2);b.Tick()
 check(ctx.EditableDestroyed and model.Parent==ctx.Storage and b.State().phase=="idle","completed bake releases owner and parks empty map")
 local baked=model:FindFirstChild("Slides"):FindFirstChild("NewSlide")
 check(baked==ctx.BakedPart and #ctx.Queue==0,"successful bake preserves generated slide and releases one owned job")
 b.Claim({});ctx:Advance(.1);check(model:FindFirstChild("Slides"):FindFirstChild("NewSlide")==baked,"reentry reuses baked slide without another decode")
end
do
 local ctx,a,b,slides,lit,lamp,clear,prepare=fresh();local model=ctx.Models[6]
 local item=node("Folder","CanceledSlide",ctx.Storage:FindFirstChild("Level6ArenaSlideSource"))
 item:SetAttribute("Parts",0);item:SetAttribute("Centre",Vector3.zero);ctx.PartDelay=2
 local group={};b.Claim(group);ctx:Advance(.1);model.Parent=ctx.Storage;ctx:Advance(2)
 check(ctx.BakedPart and ctx.BakedPart.Destroyed and not model:FindFirstChild("Slides"):FindFirstChild("CanceledSlide"),"external unmount after engine yield destroys unparented test-owned baked part")
 ctx:Advance(6);check(b.State().phase=="idle" and #ctx.Queue==0,"canceled bake releases job and stops pending retries")
end
do
 local ctx,a,b,slides,lit,lamp,clear,prepare=fresh();local model=ctx.Models[6]
 node("Folder","RetrySlide",ctx.Storage:FindFirstChild("Level6ArenaSlideSource"))
 local first={};b.Claim(first);ctx:Advance(.1);b.LetGo(first);b.Tick()
 local second={};check(b.Claim(second),"empty retry-wait map accepts later party without an actual bake lock")
 ctx:Advance(.1);check(#ctx.Queue==1 and #ctx.Warns==1,"quick remount reuses prior bounded retry owner without spawning another job")
 ctx:Advance(6);check(#ctx.Warns==2,"existing retry owner resumes on the same remounted model")
 b.LetGo(second);b.Tick();ctx:Advance(6)
 check(model.Parent==ctx.Storage and #ctx.Queue==0,"remounted retry owner also stops after map becomes empty and parked")
end
do
 local ctx,a,b,slides,lit,lamp,clear,prepare=fresh();local source=ctx.Storage:FindFirstChild("Level6ArenaSlideSource")
 source.GetChildren=function() error("synthetic source enumeration failure") end
 local group={};b.Claim(group);ctx:Advance(.1);b.LetGo(group);b.Tick()
 check(#ctx.Warns==1 and #ctx.Queue==0 and b.State().phase=="idle","unexpected slide job error releases busy and job ownership")
 check(ctx.Models[6].Parent==ctx.Storage,"unexpected preparation failure leaves no permanent map residency")
end
for _,level in ipairs({5,6})do
 local ctx,a,b,slides,lit,lamp,clear,prepare,makeLive=fresh();local live=makeLive(level)
 local p,q,r=ctx:Player("cohort first"),ctx:Player("cohort late"),ctx:Player("other party")
 live.Add(p,"same");run(ctx,function()live.Launch("same",{p})end)
 local token=live.Party("same").token
 check(type(token)=="string" and ctx.GuidCalls==1,"actual Live Level Server mints one scalar identity for Level "..level)
 check(p:GetAttribute("Level6PlaygroundPreview")==true,"first actual live-server cohort enters Level "..level)
 local originalGroup=level==5 and a.Member(p).group or nil
 live.Add(q,"same");run(ctx,function()live.Launch("same",{q})end)
 check(q:GetAttribute("Level6PlaygroundPreview")==true and live.Party("same").token==token,"late actual live-server cohort passes copied Invoke boundary for Level "..level)
 if level==5 then
  check(a.Member(q).group==originalGroup and originalGroup.total==2,"late Level 5 member preserves canonical group identity and accumulated party statistics")
 else check(b.Hold()==token and ctx.Session:count()==2,"late Level 6 member preserves its original lock and session")end
 live.Add(r,"other");run(ctx,function()live.Launch("other",{r})end,6)
 check(r:GetAttribute("Level6PlaygroundPreview")~=true,"distinct scalar live-party identity cannot steal occupied Level "..level)
 if level==5 then check(originalGroup.total==2 and a.Member(p).group==originalGroup,"rejected other party cannot overwrite canonical Level 5 totals")end
end
do
 local ctx,a,b,slides,lit,lamp,clear,prepare,makeLive=fresh();local live=makeLive(5)
 local p,q=ctx:Player("already continued"),ctx:Player("arrived after unload")
 live.Add(p,"late transfer");run(ctx,function()live.Launch("late transfer",{p})end)
 local token=live.Party("late transfer").token
 run(ctx,function()a.Continue(p)end);a.Tick()
 check(ctx.Models[5].Parent==ctx.Storage and b.Hold()==token,"live cohort continuation reuses its stable cross-level identity after old map unload")
 live.Add(q,"late transfer");run(ctx,function()live.Launch("late transfer",{q})end)
 local newGroup=a.Member(q).group;run(ctx,function()a.Continue(q)end);a.Tick()
 check(newGroup.level6PartyToken==token and not a.Member(q) and ctx.Session:count()==2,"later same-session arrival joins existing Level 6 cohort after a complete Level 5 unload")
 check(ctx.GuidCalls==1 and ctx.Models[5].Parent==ctx.Storage and ctx.Models[6].Parent==ctx.Workspace,"cross-level late cohort uses no permanent group registry or extra GUID")
end
for _,level in ipairs({5,6})do
 local ctx,a,b,slides,lit,lamp,clear,prepare,makeLive=fresh();local live=makeLive(level);local p=ctx:Player("live retry")
 live.Add(p,"retry");ctx.StreamReady=false
 run(ctx,function()live.Launch("retry",{p})end,.1)
 check(live.Party("retry").launching and p:GetAttribute("Level6PlaygroundPreview")~=true,"failed real live launch waits for its bounded retry")
 ctx.StreamReady=true;ctx:Advance(3)
 check(p:GetAttribute("Level6PlaygroundPreview")==true and ctx.GuidCalls==1 and not live.Party("retry").launching,"successful Level "..level.." retry keeps one caller scalar identity")
end
-- Last-member departure must preserve independently accepted late entry attempts.
for _,level in ipairs({5,6})do
 local ctx,a,b=fresh();local api=level==5 and a or b
 local p,q,r=ctx:Player("old member"),ctx:Player("late first"),ctx:Player("late second")
 local token="pending-cohort";local _,canonical=api.Claim(token);api.Join(p,level==5 and canonical or token)
 ctx.StreamDelays={[q]=2,[r]=4}
 local launcher=ctx.Storage:FindFirstChild("Level"..level.."LaunchParty")
 run(ctx,function()launcher:Invoke({q},token)end,.1)
 run(ctx,function()launcher:Invoke({r},token)end,.1)
 api.Leave(p,true);if level==6 then b.Finish()end;api.Tick()
 check(ctx.Models[level].Parent==ctx.Workspace and api.Hold()~=nil,"last Level "..level.." member leaving retains both late-stream leases")
 check(not api.Claim("other-party"),"another party cannot steal a late-stream Level "..level.." reservation")
 ctx:Advance(2.1)
 check(q:GetAttribute("Level6PlaygroundPreview")==true and r:GetAttribute("Level6PlaygroundPreview")~=true,"first parallel Level "..level.." lease joins while second still streams")
 api.Leave(q,true);if level==6 then b.Finish()end;api.Tick()
 check(ctx.Models[level].Parent==ctx.Workspace,"joining and leaving one late Level "..level.." player does not consume another player's lease")
 ctx:Advance(2.1)
 check(r:GetAttribute("Level6PlaygroundPreview")==true,"remaining parallel Level "..level.." lease joins after all old members leave")
 api.Leave(r,true);if level==6 then b.Finish()end;api.Tick()
 check(ctx.Models[level].Parent==ctx.Storage and api.Hold()==nil,"all late Level "..level.." leases and members settle without a permanent hold")
end
for _,level in ipairs({5,6})do
 local ctx,a,b=fresh();local api=level==5 and a or b
 local p,q,r=ctx:Player("existing"),ctx:Player("failed late"),ctx:Player("surviving late")
 local token="failure-cohort";local _,canonical=api.Claim(token);api.Join(p,level==5 and canonical or token)
 ctx.StreamDelays={[q]=1,[r]=3};ctx.StreamResults={[q]=false}
 local launcher=ctx.Storage:FindFirstChild("Level"..level.."LaunchParty")
 run(ctx,function()launcher:Invoke({q},token)end,.1);run(ctx,function()launcher:Invoke({r},token)end,.1)
 api.Leave(p,true);if level==6 then b.Finish()end;ctx:Advance(1.2);api.Tick()
 check(q:GetAttribute("Level6PlaygroundPreview")~=true and ctx.Models[level].Parent==ctx.Workspace,"failed late Level "..level.." stream releases only its own lease")
 ctx:Advance(3)
 check(r:GetAttribute("Level6PlaygroundPreview")==true,"another same-party Level "..level.." pending entry survives a failed cohort")
end
for _,level in ipairs({5,6})do
 local ctx,a,b=fresh();local api=level==5 and a or b;local p,q=ctx:Player("timeout"),ctx:Player("replacement")
 ctx.StreamDelay=100
 run(ctx,function()api.Enter(p,ctx.EntryPrompt)end,.1)
 ctx:Advance(91);api.Tick()
 check(ctx.Models[level].Parent==ctx.Storage,"Level "..level.." per-player 90-second deadline expires while the E stream callback still waits")
 local token={};api.Claim(token);api.Join(q,token);local before=p.Root.Position
 ctx:Advance(10)
 check(p:GetAttribute("Level6PlaygroundPreview")~=true and p.Root.Position==before,"expired Level "..level.." E callback cannot pivot or join after another party takes over")
 check(q:GetAttribute("Level6PlaygroundPreview")==true and api.Hold()==token,"expired Level "..level.." callback cannot release the replacement party")
end
for _,level in ipairs({5,6})do
 local ctx,a,b=fresh();local api=level==5 and a or b;local p=ctx:Player("party timeout")
 ctx.StreamDelay=100;local result
 run(ctx,function()result=ctx.Storage:FindFirstChild("Level"..level.."LaunchParty"):Invoke({p},"timeout")end,.1)
 ctx:Advance(31);api.Tick()
 check(result==false and ctx.Models[level].Parent==ctx.Storage and api.Hold()==nil,"Level "..level.." party timeout releases its lease before an engine stream worker drains")
 ctx:Advance(70);api.Tick()
 check(p:GetAttribute("Level6PlaygroundPreview")~=true and ctx.Models[level].Parent==ctx.Storage,"late Level "..level.." party worker has no join or ownership side effect")
end
for _,level in ipairs({5,6})do
 for _,failure in ipairs({"PrepareThrow","CommitThrow","StreamThrow"})do
  local ctx,a,b=fresh();local api=level==5 and a or b;local p=ctx:Player("queue error")
  ctx[failure]=true;local result
  run(ctx,function()result=ctx.Callbacks[level].launch({Player=p})end)
  api.Tick();if level==6 then b.Finish();api.Tick()end
  check(result==false and api.Hold()==nil and ctx.Models[level].Parent==ctx.Storage,"Level "..level.." queue "..failure.." releases its pending leases")
 end
 local ctx,a,b=fresh();local api=level==5 and a or b;local p,q=ctx:Player("expired queue"),ctx:Player("new queue party")
 ctx.StreamDelay=100;run(ctx,function()ctx.Callbacks[level].launch({Player=p})end,.1)
 ctx:Advance(91);api.Tick();local token={};api.Claim(token);api.Join(q,token);ctx:Advance(10)
 check(p:GetAttribute("Level6PlaygroundPreview")~=true and api.Hold()==token,"expired Level "..level.." queue callback cannot join or clear another party")
end
local function continuing(ctx,name)
 local player=ctx:Player(name);player:SetAttribute("Level5VoidRound",true)
 player:SetAttribute("Level6PlaygroundPreview",true);player:SetAttribute("InRound",true);return player
end
do
 local ctx,a,b=fresh();local p,q=continuing(ctx,"prepared first"),continuing(ctx,"prepared second")
 local enter=ctx.Storage:FindFirstChild("Level6EnterFromLevel");local token="continue-pending"
 local prepared1,prepared2
 run(ctx,function()prepared1=enter:Invoke(p,"prepare",token);prepared2=enter:Invoke(q,"prepare",token)end)
 check(prepared1 and prepared2,"same-GUID continuation retains separate players across the prepare-to-enter gap")
 p:SetAttribute("Level5VoidRound",nil);local joined
 run(ctx,function()joined=enter:Invoke(p,"enter",token)end)
 check(joined and ctx.Session:count()==1,"first prepared continuation consumes its own ticket")
 b.Leave(p,true);b.Finish();b.Tick()
 check(ctx.Models[6].Parent==ctx.Workspace and b.Hold()==token,"last entered continuer leaving cannot release another prepared player")
 q:SetAttribute("Level5VoidRound",nil);run(ctx,function()joined=enter:Invoke(q,"enter",token)end)
 check(joined and ctx.Session:count()==1,"remaining prepared player can enter after the earlier session empties")
 local repeated;run(ctx,function()repeated=enter:Invoke(q,"enter",token)end)
 check(not repeated and ctx.Session:count()==1,"continuation preparation can be consumed only once")
 b.Leave(q,true);b.Finish();b.Tick()
 check(ctx.Models[6].Parent==ctx.Storage and b.Hold()==nil,"consumed continuation tickets do not keep an empty map loaded")
end
do
 local ctx,a,b=fresh();local p,q=continuing(ctx,"deadline first"),continuing(ctx,"deadline later")
 local enter=ctx.Storage:FindFirstChild("Level6EnterFromLevel");local token="individual-deadlines"
 run(ctx,function()enter:Invoke(p,"prepare",token)end);ctx:Advance(60)
 run(ctx,function()enter:Invoke(q,"prepare",token)end);ctx:Advance(31)
 local expired;run(ctx,function()expired=enter:Invoke(p,"enter",token)end)
 check(not expired and ctx.Models[6].Parent==ctx.Workspace,"one continuation ticket expires without expiring a later same-party ticket")
 enter:Invoke(q,"cancel","unrelated-token");b.Tick()
 check(b.Hold()==token and ctx.Models[6].Parent==ctx.Workspace,"another party's cancel cannot consume a prepared player's lease")
 enter:Invoke(q,"cancel",token);b.Tick()
 check(ctx.Models[6].Parent==ctx.Storage and b.Hold()==nil,"cancel releases the last prepared ticket after another ticket expired")
 local calls=ctx.ActivateCalls;run(ctx,function()expired=enter:Invoke(q,"enter",token)end)
 check(not expired and ctx.ActivateCalls==calls,"enter without a current preparation cannot remount an abandoned destination")
end
do
 local ctx,a,b=fresh();local p=continuing(ctx,"cancelled worker");local q=ctx:Player("new owner")
 local enter=ctx.Storage:FindFirstChild("Level6EnterFromLevel");local token="cancelled"
 ctx.StreamDelay=2;local prepared
 run(ctx,function()prepared=enter:Invoke(p,"prepare",token)end,.1)
 enter:Invoke(p,"cancel",token);b.Tick()
 check(ctx.Models[6].Parent==ctx.Storage,"explicit continuation abort releases its lease while stream callback still waits")
 b.Claim("replacement");b.Join(q,"replacement");ctx:Advance(3)
 check(not prepared and b.Hold()=="replacement" and ctx.Session:count()==1,"cancelled prepare completion cannot become ready or release another party")
end
do
 local ctx,a,b=fresh();local p=continuing(ctx,"duplicate preparation")
 local enter=ctx.Storage:FindFirstChild("Level6EnterFromLevel");local token="fixed-deadline"
 ctx.StreamDelay=100;local first,duplicate
 run(ctx,function()first=enter:Invoke(p,"prepare",token)end,.1);ctx:Advance(60)
 run(ctx,function()duplicate=enter:Invoke(p,"prepare",token)end,.1);ctx:Advance(31);b.Tick()
 check(duplicate==false and ctx.Models[6].Parent==ctx.Storage,"rejected duplicate preparation cannot extend the original ticket's 90-second hold")
 ctx:Advance(10)
 local _,deadline=b.Hold()
 check(not first and deadline<=ctx.Now and ctx.Models[6].Parent==ctx.Storage,"expired duplicate-preparation worker leaves no active map hold")
end
do
 local ctx,a,b=fresh();local p=continuing(ctx,"same player retry")
 local enter=ctx.Storage:FindFirstChild("Level6EnterFromLevel");local token="same-player"
 ctx.StreamDelay=100;local oldResult,newResult
 run(ctx,function()oldResult=enter:Invoke(p,"prepare",token)end,.1)
 ctx:Advance(91);b.Tick();ctx.StreamDelay=0
 run(ctx,function()newResult=enter:Invoke(p,"prepare",token)end);ctx:Advance(10);b.Tick()
 check(not oldResult and newResult and b.Hold()==token,"expired same-player callback cannot consume or release a newer same-GUID ticket")
 p:SetAttribute("Level5VoidRound",nil);run(ctx,function()newResult=enter:Invoke(p,"enter",token)end)
 check(newResult and ctx.Session:count()==1,"a newer preparation remains consumable after its stale predecessor settles")
end
do
 local ctx,a,b=fresh();local p,q=continuing(ctx,"disconnect prepared"),continuing(ctx,"still prepared")
 local enter=ctx.Storage:FindFirstChild("Level6EnterFromLevel");local token="disconnect-cohort"
 run(ctx,function()enter:Invoke(p,"prepare",token);enter:Invoke(q,"prepare",token)end)
 ctx.Players.PlayerRemoving:Fire(p);p.Parent=nil;table.remove(ctx.PlayersList,1);b.Tick()
 check(b.Hold()==token and ctx.Models[6].Parent==ctx.Workspace,"disconnect releases only that player's prepared continuation ticket")
 enter:Invoke(q,"cancel",token);b.Tick()
 check(b.Hold()==nil and ctx.Models[6].Parent==ctx.Storage,"remaining prepared ticket can cancel after another player disconnects")
end
do
 local ctx,a,b=fresh();local p=continuing(ctx,"concurrent consume")
 local enter=ctx.Storage:FindFirstChild("Level6EnterFromLevel");local token="consume-once"
 run(ctx,function()enter:Invoke(p,"prepare",token)end);p:SetAttribute("Level5VoidRound",nil);ctx.SuitDelay=2
 local first,duplicate
 run(ctx,function()first=enter:Invoke(p,"enter",token)end,.1)
 run(ctx,function()duplicate=enter:Invoke(p,"enter",token)end,.1)
 check(duplicate==false and ctx.SuitCalls==1,"a yielding continuation body load cannot consume the same preparation concurrently")
 ctx:Advance(3)
 check(first and ctx.Session:count()==1,"the sole continuation consumer keeps ownership until its body load settles")
end
for _,level in ipairs({5,6})do
 local ctx,a,b=fresh();local api=level==5 and a or b;local p=ctx:Player("commit expiry")
 ctx.CommitDelay=100;local result
 run(ctx,function()result=ctx.Callbacks[level].launch({Player=p})end,.1)
 ctx:Advance(91);api.Tick();ctx:Advance(10);if level==6 then b.Finish()end;api.Tick()
 check(result==false and p:GetAttribute("Level6PlaygroundPreview")~=true and api.Hold()==nil,"Level "..level.." Join refuses a ticket that expires while its caller yields before commit")
end
for _,level in ipairs({5,6})do
 local ctx,a,b=fresh();local api=level==5 and a or b;local p=ctx:Player("deadline at pivot")
 local previous=p.Root.Position;ctx.PivotAdvance=91
 run(ctx,function()api.Enter(p,ctx.EntryPrompt)end);api.Tick()
 check(p:GetAttribute("Level6PlaygroundPreview")~=true and p.Root.Position==previous,"Level "..level.." E join rejection restores the original position when deadline crosses at pivot")
end
for _,level in ipairs({5,6})do
 local ctx,a,b=fresh();local api=level==5 and a or b;local p=ctx:Player("old queue rollback")
 local token="new-pending-owner";local prepared
 ctx.AfterCommit=function(entry)
  api.Leave(entry.player,true);if level==6 then b.Finish()end
  -- A later entry owns this player before the old queue calls its rollback.
  if level==5 then
   local _,group=api.Claim(token);check(api.Join(p,group),"replacement Level 5 party joins before old rollback")
  else
   p:SetAttribute("Level5VoidRound",true);p:SetAttribute("Level6PlaygroundPreview",true)
   prepared=ctx.Storage:FindFirstChild("Level6EnterFromLevel"):Invoke(p,"prepare",token)
  end
 end
 local result;run(ctx,function()result=ctx.Callbacks[level].launch({Player=p})end);api.Tick()
 if level==5 then
  check(result==false and a.Member(p) and a.Member(p).group.livePartyToken==token,"old Level 5 queue rollback cannot remove a newer party's same-player membership")
 else
  check(result==false and prepared and b.Hold()==token,"old Level 6 queue rollback cannot cancel a newer party's same-player preparation")
  ctx.Storage:FindFirstChild("Level6EnterFromLevel"):Invoke(p,"cancel",token);b.Tick()
 end
end
do
 local ctx,a,b=fresh();local p=ctx:Player("throwing join");ctx.JoinThrow=true
 run(ctx,function()b.Enter(p,ctx.EntryPrompt)end);b.Tick()
 check(p:GetAttribute("Level6PlaygroundPreview")~=true and b.Hold()==nil,"throwing AddPlayer clears partial preview marker and pending reservation")
 check(ctx.Session:count()==0 and not ctx.Session.active,"throwing AddPlayer interrupts its partial session through RemovePlayer")
 b.Finish();b.Tick()
 check(ctx.Models[6].Parent==ctx.Storage,"partial AddPlayer failure parks only after owned session cleanup")
end
do
 local ctx,a,b=fresh();local p=ctx:Player("leave during continue");local group={}
 a.Claim(group);a.Join(p,group);p:SetAttribute("InRound",true);ctx.StreamDelay=2
 run(ctx,function()a.Continue(p)end,.1);a.Leave(p,true);a.Tick();b.Tick()
 check(ctx.Models[5].Parent==ctx.Storage and ctx.Models[6].Parent==ctx.Storage,"leaving the source level cancels that player's in-flight destination preparation")
 ctx:Advance(3);b.Tick()
 check(not a.Member(p) and b.Hold()==nil and ctx.Models[6].Parent==ctx.Storage,"aborted source Continue callback cannot resurrect either level")
end
print("Live level lifecycle: "..checks.." actual-source checks passed")
'''


def program(s5, s6, game, client, live):
    parts = {
        '__GAME_STATE__': region(game, 'function Game.State()', '\nPlayers.PlayerRemoving'),
        '__GAME_REMOVE__': region(game, 'function Game.RemovePlayer(player)', '\nfunction Game.State'),
        '__SESSION_FINISH__': region(game, 'function Session:finish()', '\n-- ---------------------------------------------------------------------------------------\n-- public API'),
        '__GAME_DISCONNECT__': region(game, 'Players.PlayerRemoving:Connect(function(player) Game.RemovePlayer(player) end)', '\n\n--'),
        '__L5_READY__': region(s5, 'local function readyPreview', '\nlocal function readyPlayer'),
        '__L5_PLAYER__': region(s5, 'local function readyPlayer', '\nlocal function upright'),
        '__L5_RELEASE__': region(s5, 'local function release(player)', '\nlocal function hasFloor'),
        '__L5_FLOOR__': region(s5, 'local function hasFloor', '\nlocal function onReturn'),
        '__L5_CLAIM__': region(s5, '\tlocal finale = {state = "idle"}', '\tfunction Void.Notice'),
        '__L5_JOIN__': region(s5, '\tfunction Void.Join', '\n\tlocal finaleDeath'),
        '__L5_LEAVE__': region(s5, '\tfunction Void.Leave', '\n\t-- LEVEL 5 CLEARED'),
        '__L5_CONTINUE__': region(s5, '\tfunction Void.Continue', '\n\tPlayers.PlayerRemoving'),
        '__L5_DISCONNECT__': region(s5, '\tPlayers.PlayerRemoving:Connect(function(player) members[player]', '\n\t-- PARTY_LOCK'),
        '__L5_ENTER__': region(s5, 'local function onEnter', '\nlocal function ensurePrompt'),
        '__L5_QUEUE__': region(s5, 'do\n local bridge = r3Bridge()', '\n-- LIVE_LEVEL_SERVERS_20261008'),
        '__L5_PARTY__': region(s5, 'do\n\tlocal old = ServerStorage:FindFirstChild("Level5LaunchParty")', '\nlocal function hookDoor'),
        '__L5_LIVE_GUARD__': region(s5, '\t\t\tlocal model = readyPreview(true)\n\t\t\tlocal origin', '\n\t\t\tlocal inSection'),
        '__L5_MEMBER_CLEANUP__': 'for player,record in pairs(members) do\n'+region(s5, '\t\t\t\tif player:GetAttribute(LIVE) ~= true', '\n\t\t\t\tif player:GetAttribute("InRound")')+'\nend',
        '__L5_EMPTY_RESET__': region(s5, '\t\t\t\tif record.locked then', '\n\t\t\t\tlocal radius'),
        '__L5_PARK__': region(s5, '\t\t\t-- Keep the authored instance', '\n\t\tend\n\tend)'),
        '__L6_ENSURE__': region(s6, 'function Runtime.EnsureWorld()', '\n-- The hide-and-seek'),
        '__L6_LEAVE__': region(s6, 'function Runtime.Leave', '\n-- PARTY_LOCK_20261008'),
        '__L6_CLAIM__': region(s6, 'local partyLock = ', '\nlocal function tellBusy'),
        '__L6_DISCONNECT__': region(s6, 'Players.PlayerRemoving:Connect(function(player)', '\nfunction Runtime.Emptied'),
        '__L6_JOIN__': region(s6, 'function Runtime.Join', '\nlocal ENTER'),
        '__L6_PLAYER__': region(s6, 'local function playerReady', '\nlocal function previewReady'),
        '__L6_READY_FLOOR_UPRIGHT__': region(s6, 'local function previewReady', '\ntransport.OnServerEvent'),
        '__L6_RELEASE__': region(s6, 'local function release(player)', '\nlocal onReturn'),
        '__L6_ENTER__': region(s6, 'local function onEnter', '\nonReturn = '),
        '__L6_QUEUE__': region(s6, 'do\n local bridge = r3Bridge()', '\n-- CONTINUE on Level 5'),
        '__L6_CONTINUE_BINDABLE__': region(s6, 'do\n\tlocal old = ServerStorage:FindFirstChild("Level6EnterFromLevel")', '\n-- LIVE_LEVEL_SERVERS_20261008'),
        '__L6_PARTY__': region(s6, 'do\n\tlocal old = ServerStorage:FindFirstChild("Level6LaunchParty")', '\nlocal function hookDoor'),
        '__L6_POLL__': region(s6, '\t\tlocal busy = occupants()', '\n\t\ttask.wait(1)'),
        '__SLIDE_BUILD__': region(game, 'function arenaSlides.build()', '\nlocal function prepareSlides'),
        '__SLIDE_JOB__': region(game, 'local function prepareSlides', '\n\nreturn Game'),
        '__LIVE_PACKET__': region(live, 'local function packetOf(player)', '\nlocal function onPlayer'),
        '__LIVE_ONPLAYER__': region(live, 'local function onPlayer', '\nlocal function standing'),
        '__LIVE_STANDING__': region(live, 'local function standing', '\nlocal function launch'),
        '__LIVE_LAUNCH__': region(live, 'local function launch', '\nlocal function cover'),
        '__CLIENT_CLEAR__': region(client, '\t\tif not model then\n\t\t\t-- Parking removes the replica', '\n\t\tlocal enraged'),
    }
    text = HARNESS
    for token, value in parts.items():
        assert text.count(token) == 1, token
        text = text.replace(token, value)
    return PRIMITIVES+text+TESTS


def run(binary, source, name, fail=False):
    with tempfile.TemporaryDirectory(prefix='live-level-lifecycle-') as directory:
        path = Path(directory)/name
        path.write_text(source,encoding='utf-8')
        result = subprocess.run([binary,str(path)],capture_output=True,text=True,timeout=30)
        if fail:
            assert result.returncode != 0, f'Mutation survived: {name}'
            print('Mutation caught: '+name+': '+result.stderr.splitlines()[0])
        else:
            print(result.stdout,end='')
            if result.returncode:
                print(result.stderr,end='')
                raise SystemExit(result.returncode)


def main():
    parser=argparse.ArgumentParser(description=__doc__)
    parser.add_argument('--candidate',action='store_true')
    parser.add_argument('--mutations',action='store_true')
    parser.add_argument('--luau',default=os.environ.get('LUAU_BIN') or shutil.which('luau'))
    args=parser.parse_args()
    if not args.luau: raise SystemExit('Supply --luau or LUAU_BIN; no tests executed.')
    paths=['ServerScriptService.Level5PreviewAccess','ServerScriptService.Level6PreviewAccess',
           'ServerScriptService.Level 6 Systems.Level 6 Playground Game',
           'StarterPlayer.StarterPlayerScripts.Level 6 Playground Client','ServerScriptService.Live Level Server']
    mirrors=['ServerScriptService/Level5PreviewAccess.Script.lua','ServerScriptService/Level6PreviewAccess.Script.lua',
             'ServerScriptService/Level 6 Systems/Level 6 Playground Game.ModuleScript.lua',
             'StarterPlayer/StarterPlayerScripts/Level 6 Playground Client.LocalScript.lua','ServerScriptService/Live Level Server.Script.lua']
    sources=[]
    for path,mirror in zip(paths,mirrors):
        chosen=ROOT/mirror
        if args.candidate:
            candidate=HERE/'pending-entry-candidates'/(path.replace('.','__')+'.luau')
            if not candidate.exists(): candidate=HERE/'party-identity-candidates'/(path.replace('.','__')+'.luau')
            if not candidate.exists(): candidate=HERE/'candidates'/(path.replace('.','__')+'.luau')
            if candidate.exists(): chosen=candidate
        sources.append(chosen.read_text(encoding='utf-8'))
    run(args.luau,program(*sources),'lifecycle.luau')
    if args.mutations:
        mutations=[
            ('dormant-read-mounts.luau',0,'local model = WorldStorage.Get(5)','local model = WorldStorage.Activate(5)'),
            ('continue-leaks-old-world.luau',0,'members[player], leaving[player] = nil, nil\n\t\t\t\tVoid.LetGo(nil)','members[player], leaving[player] = nil, nil'),
            ('dead-member-world-removed.luau',1,'if player ~= except and inLevel6(player) then count += 1 end','if player ~= except and inLevel6(player) and player.Humanoid.Health > 0 then count += 1 end'),
            ('unfinished-session-parked.luau',1,'not busy and Playground.State().phase == "idle"','not busy'),
            ('fresh-claim-overlaps-old-session.luau',1,'if occupants() == 0 and Playground.State().phase ~= "idle" and partyLock.token ~= token then return false end','-- missing cleanup guard'),
            ('fresh-claim-overlaps-old-finale.luau',0,'if next(members) == nil and finale.state ~= "idle" then return false end','-- missing finale guard'),
            ('late-slides-missing.luau',2,'workspace.ChildAdded:Connect(prepareSlides)','-- missing late-mount trigger'),
            ('retry-wait-retains-empty-map.luau',2,'phase = arenaSlides.busy and "preparing"','phase = arenaSlides.job and "preparing"'),
            ('late-bake-parents-into-parked-map.luau',2,'if model.Parent ~= workspace then part:Destroy(); error("Level 6 was parked during slide bake") end','-- missing post-yield parent guard'),
            ('client-retains-old-replica.luau',3,'table.clear(litBefore)\n\t\t\tif exitLamp.bulb','-- missing clear\n\t\t\tif exitLamp.bulb'),
            ('continue-passes-copied-table.luau',0,'enter:Invoke(player, "prepare", token)','enter:Invoke(player, "prepare", record.group)'),
            ('continue-remints-cohort-identity.luau',0,'group.level6PartyToken or group.livePartyToken or HttpService:GenerateGUID(false)','HttpService:GenerateGUID(false)'),
            ('live-server-copied-party-table.luau',4,'token = HttpService:GenerateGUID(false)','token = {}'),
            ('level5-late-cohort-loses-group.luau',0,'type(hold.token) == "table" and hold.token.livePartyToken == group','false'),
            ('level6-rejects-scalar-live-token.luau',1,'not (type(token) == "table" or (type(token) == "string" and token ~= ""))','type(token) ~= "table"'),
            ('late-transfer-loses-live-identity.luau',0,'group.level6PartyToken or group.livePartyToken or HttpService:GenerateGUID(false)','group.level6PartyToken or HttpService:GenerateGUID(false)'),
            ('level5-pending-last-leave.luau',0,'next(members) ~= nil or pendingEntries() then return end','next(members) ~= nil then return end'),
            ('level6-pending-last-leave.luau',1,'occupants(except) > 0 or pendingEntries() then return end','occupants(except) > 0 then return end'),
            ('level5-unbounded-entry-lease.luau',0,'deadline = os.clock() + 90','deadline = os.clock() + 360'),
            ('level6-unbounded-entry-lease.luau',1,'deadline = os.clock() + 90','deadline = os.clock() + 360'),
            ('level6-expired-enter-without-poll.luau',1,'and os.clock() < lease.deadline and partyLock.token == lease.token','and partyLock.token == lease.token'),
            ('level6-stale-worker-releases-new-ticket.luau',1,'if lease and entryLeases[player] == lease then','if lease then'),
            ('level6-concurrent-consume.luau',1,'or lease.kind ~= "continue" or lease.consuming then','or lease.kind ~= "continue" then'),
            ('level6-other-party-cancels-ticket.luau',1,'lease and lease.token == party and lease.kind == "continue"','lease and lease.kind == "continue"'),
            ('level5-expired-join-after-yield.luau',0,'if lease and not Void.PendingValid(player, lease) then return false, "ENTRY_EXPIRED" end','-- missing join deadline'),
            ('level6-expired-join-after-yield.luau',1,'if lease and not Runtime.PendingValid(player, lease) then return false, "ENTRY_EXPIRED" end','-- missing join deadline'),
            ('level5-late-rollback-removes-new-member.luau',0,'Void.RollbackEntry(entry.player, leases[entry.player])','Void.Leave(entry.player, true)'),
            ('level6-late-rollback-drops-new-ticket.luau',1,'Runtime.RollbackEntry(entry.player, leases[entry.player])','Runtime.Leave(entry.player)'),
            ('level5-rejected-e-leaves-player-over-map.luau',0,'else character:PivotTo(previous) end','else -- missing rejected join rollback\n end'),
            ('level6-duplicate-preparation-extends-hold.luau',1,'if partyLock.token ~= token or not pendingEntries() then partyLock.holdUntil = os.clock() + 90 end','partyLock.holdUntil = os.clock() + 90'),
            ('level6-throwing-join-leaks-marker.luau',1,'local called, ok, reason = pcall(Playground.AddPlayer, player)','local ok, reason = Playground.AddPlayer(player)\n\tlocal called = true'),
        ]
        for name,index,before,after in mutations:
            copy=sources.copy();assert before in copy[index],name
            copy[index]=copy[index].replace(before,after)
            run(args.luau,program(*copy),name,fail=True)


if __name__=='__main__': main()
