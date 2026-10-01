-- Offline callback/lifetime tests. Geometry is a mock plane, not a Roblox Play.
local fs = require("@lune/fs")
local luau = require("@lune/luau")
local serde = require("@lune/serde")
local roblox = require("@lune/roblox")
local task = require("@lune/task")
local V3, CF = roblox.Vector3, roblox.CFrame
local source = fs.readFile("tools/lobby_reimagined/r4_candidates/ServerScriptService.LobbyReimaginedPreview.QueueBridge.ModuleScript.candidate.luau")

local function instance(class, name, parent)
 local self = {ClassName=class,Name=name,Parent=parent,attrs={},children={}}
 function self:IsA(wanted) return self.ClassName == wanted or (wanted == "BasePart" and self.ClassName == "Part") end
 function self:IsDescendantOf(ancestor)
  local next = self.Parent
  while next do if next == ancestor then return true end; next=next.Parent end
  return false
 end
 function self:GetAttribute(key) return self.attrs[key] end
 function self:SetAttribute(key,value) self.attrs[key]=value end
 function self:FindFirstChild(name) return self.children[name] end
 function self:FindFirstChildOfClass(name)
  for _,child in pairs(self.children) do if child.ClassName == name then return child end end
  return nil
 end
 if parent then parent.children[name]=self end
 return self
end

local function fixture()
 local workspace = instance("Workspace","Workspace")
 local players = instance("Players","Players")
 function players:GetPlayers()
  local all = {};for _,p in pairs(self.children) do table.insert(all,p) end;return all
 end
 local sss = instance("ServerScriptService","ServerScriptService")
 local controller = instance("Script","Level6PreviewAccess",sss)
 local run = {IsClient=function()return false end}
 local game = {GetService=function(_,key)return ({Players=players,ServerScriptService=sss,RunService=run})[key] end}
 local bridge = luau.load(source,{environment={game=game,workspace=workspace,
  typeof=function(x)return if type(x)=="table" and x.ClassName then "Instance" else typeof(x)end,
  Enum=roblox.Enum, Vector2=roblox.Vector2,Vector3=V3,CFrame=CF,
  RaycastParams={new=function()return{}end},OverlapParams={new=function()return{}end},task=task}})()
 local lobby=instance("Model","LobbyReimaginedPreview",workspace)
 lobby.attrs={LobbyReimaginedOwned=true,R3QueueRevision=3,Ready=true}
 local bay=instance("Model","Level6Bay",lobby)
 local zone=instance("Part","QueueZone",bay)
 zone.attrs={R3QueueId=121,LevelNumber=6,QueueRadius=7.18};zone.CFrame=CF.new(0,0,0)
 local world=instance("Model","PreviewWorld",workspace)
 local exit=instance("Part","Exit",world);exit.CFrame=CF.new(100,3.5,0);exit.Position=exit.CFrame.Position
 function workspace:Raycast(origin) return {Position=V3.new(origin.X,0,origin.Z),Normal=V3.yAxis} end
 function workspace:GetPartBoundsInBox() return {} end
 local cohort={}
 for i=1,2 do
  local player=instance("Player","Player"..i,players);player.attrs={};player.allowed=true
  local char=instance("Model","Character"..i,workspace)
  local root=instance("Part","HumanoidRootPart",char);root.Position=V3.new((i-1)*2,3.5,0);root.Size=V3.new(2,2,1);root.Anchored=false
  local hum=instance("Humanoid","Humanoid",char);hum.RootPart=root;hum.Health=100;hum.HipHeight=2
  function hum:GetState()return roblox.Enum.HumanoidStateType.Running end
  function char:GetPivot()return CF.new(root.Position) end
  function char:PivotTo(frame) root.Position=frame.Position;root.lastFrame=frame;self.moves=(self.moves or 0)+1 end
  player.Character=char;cohort[i]=player
 end
 local station={index=121,level=6,zone=zone,lobbyOwner=lobby,revisionOwned=true,previewQueue=true,busy=true,admissionEpoch=1}
 local nextUse,locks={},{}
 local f={bridge=bridge,cohort=cohort,station=station,world=world,exit=exit,controller=controller,commits=0,rollbacks=0,releases=0}
 function f.register(overrides)
  bridge.RegisterPreviewLauncher(6,controller,{
   allowed=function(p,_,owner)
    local lock=locks[p]
    return p.allowed and (if lock then bridge.ContextOwns(lock,p,owner) else (nextUse[p]or 0)<=os.clock())
   end,
   ready=function()return world,exit end,
   launch=function(context)
    local locked,reason=bridge.LockPreviewController(context,nextUse,locks,function(p)f.releases+=1;nextUse[p]=os.clock()+.02 end)
    if not locked then return false,reason end
    if overrides and overrides.before then overrides.before(f,context)end
    local entries,problem=bridge.PreparePreviewGroup(context,world,exit,function(p)
     if overrides and overrides.stream then return overrides.stream(p,f)end
     task.wait(.03);return true
    end)
    if not entries then return false,problem end
    return bridge.CommitPreviewGroup(context,entries,function(entry)
     f.commits+=1
     if overrides and overrides.commit then return overrides.commit(entry,f)end
     entry.player:SetAttribute("Level6InRound",true);return true
    end,function(entry)f.rollbacks+=1;entry.player:SetAttribute("Level6InRound",nil)end)
   end,
  })
 end
 return f
end

local results={}
local function check(name,callback)
 local ok,err=pcall(callback);table.insert(results,{name=name,passed=ok,error=if ok then nil else tostring(err)})
 if not ok then warn(name,err)end
end

check("exact controller registration rejects unrelated Script",function()
 local f=fixture();local ok=pcall(f.bridge.RegisterPreviewLauncher,6,instance("Script","Other"),{allowed=function()end,ready=function()end,launch=function()end});assert(not ok)
end)
check("unauthorized cohort rejected before movement",function()
 local f=fixture();f.register();f.cohort[2].allowed=false
 assert(f.bridge.LaunchPreviewGroup(f.station,f.cohort)==false);assert(f.commits==0);assert(not f.cohort[1].Character.moves)
end)
check("whole cohort commits separated after successful streams",function()
 local f=fixture();f.register();assert(f.bridge.LaunchPreviewGroup(f.station,f.cohort));assert(f.commits==2);assert(f.releases==2)
 local a=f.cohort[1].Character:FindFirstChild("HumanoidRootPart").Position
 local b=f.cohort[2].Character:FindFirstChild("HumanoidRootPart").Position
 assert((a-b).Magnitude>=4.2);assert(a.X>=90 and b.X>=90)
end)
check("one failed stream moves nobody",function()
 local f=fixture();f.register({stream=function(p)task.wait(.03);return p.Name=="Player1"end})
 assert(f.bridge.LaunchPreviewGroup(f.station,f.cohort)==false);assert(f.commits==0);assert(f.releases==2);assert(not f.cohort[1].Character.moves)
end)
check("character change while streaming revokes all admissions",function()
 local f=fixture();f.register({stream=function(p)task.wait(.03);if p.Name=="Player2"then p.Character=nil end;return true end})
 assert(f.bridge.LaunchPreviewGroup(f.station,f.cohort)==false);assert(f.commits==0)
end)
check("join rejection rolls back every moved member",function()
 local f=fixture();local a=f.cohort[1].Character:GetPivot().Position;local b=f.cohort[2].Character:GetPivot().Position
 f.register({commit=function(entry)entry.player:SetAttribute("Level6InRound",true);return entry.player.Name=="Player1","REJECTED"end})
 assert(f.bridge.LaunchPreviewGroup(f.station,f.cohort)==false);assert(f.rollbacks==2);assert(f.releases==2)
 assert(f.cohort[1].Character:GetPivot().Position==a);assert(f.cohort[2].Character:GetPivot().Position==b)
end)
check("cancelled bounded world preparation cannot ghost-enter or multiply",function()
 local f=fixture();local entered=0
 f.register({before=function()
  entered+=1;task.delay(.03,function()f.station.cancelRequested=true;f.station.admissionEpoch+=1 end);task.wait(.4)
 end})
 local start=os.clock();assert(f.bridge.LaunchPreviewGroup(f.station,f.cohort)==false);assert(os.clock()-start<.35);assert(f.releases==2)
 f.station.cancelRequested=false;f.station.admissionEpoch+=1;task.wait(.03)
 assert(f.bridge.LaunchPreviewGroup(f.station,f.cohort)==false);assert(entered==1)
 task.wait(.5);assert(f.commits==0);assert(not f.cohort[1].Character.moves)
 f.register();assert(f.bridge.LaunchPreviewGroup(f.station,f.cohort));assert(f.commits==2)
end)
check("cancel during yielding Join keeps lock through rollback and preserves explicit departure",function()
 local f=fixture();local departed=V3.new(0,3.5,20)
 local previous=f.cohort[2].Character:GetPivot().Position
 f.register({commit=function(entry)
  entry.player:SetAttribute("Level6InRound",true)
  task.delay(.03,function()
   f.station.cancelRequested=true;f.station.admissionEpoch+=1
   f.cohort[1].Character:PivotTo(CF.new(departed))
  end)
  task.wait(.3);return true
 end})
 assert(f.bridge.LaunchPreviewGroup(f.station,f.cohort)==false);assert(f.releases==2)
 assert(f.rollbacks==1)
 assert(f.cohort[1].Character:GetPivot().Position==departed)
 assert(f.cohort[2].Character:GetPivot().Position==previous)
end)
check("cancel during solo final Join rolls back membership after it returns",function()
 local f=fixture();local departed=V3.new(0,3.5,20)
 f.register({commit=function(entry)
  entry.player:SetAttribute("Level6InRound",true)
  task.delay(.03,function()
   f.station.cancelRequested=true;f.station.admissionEpoch+=1
   entry.character:PivotTo(CF.new(departed))
  end)
  task.wait(.3);return true
 end})
 assert(f.bridge.LaunchPreviewGroup(f.station,{f.cohort[1]})==false);assert(f.releases==1)
 assert(f.rollbacks==1)
 assert(f.cohort[1]:GetAttribute("Level6InRound")==nil)
 assert(f.cohort[1].Character:GetPivot().Position==departed)
end)
local passed=true;for _,r in ipairs(results)do passed=passed and r.passed end
local report={passed=passed,sourceSHA256=serde.hash("sha256",source),tests=results,
 scope="Offline exact QueueBridge lifecycle with mocked services/plane; no Studio, actual geometry, multiplayer, mobile or publication claim"}
fs.writeFile("tools/lobby_reimagined/r4_candidates/mock-lifecycle-receipt-v6.json",serde.encode("json",report,true).."\n")
print(serde.encode("json",report,true));assert(passed,"Offline lifecycle test failed")
