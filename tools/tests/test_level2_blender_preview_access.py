"""Execute the real preview entry gate in Luau with fake Roblox services.

Checks authorization, exact room/host, living avatar, reach, rate limiting and
GameManager readiness/rejection. Does not claim engine UI or gameplay coverage.

The new-map entry (2026-10-07 owner feedback): the Level2NewMapPreview flag is up
before GameManager loads the round body and never outlives it (death, removal,
failed load, return), RETURN TO LOBBY swaps the lobby avatar back, and the server
zone pass kills inside a KillZone Hazard and returns from the exit slide's tub.
"""
from pathlib import Path
import os
import shutil
import subprocess
import tempfile

ROOT = Path(__file__).resolve().parents[2]
SERVER = (ROOT / "ServerScriptService/Level2BlenderPreviewAccess.Script.lua").read_text(encoding="utf-8")
CLIENT = (ROOT / "StarterPlayer/StarterPlayerScripts/Level2BlenderPreviewButton.LocalScript.lua").read_text(encoding="utf-8")
ACCESS = (ROOT / "ReplicatedStorage/DevAccess.ModuleScript.lua").read_text(encoding="utf-8")


def section(source, start, stop):
    begin = source.index(start)
    return source[begin:source.index(stop, begin)]


PRELUDE = r'''
local checks = 0
local function check(value, message) checks += 1; assert(value, message) end
local function typeof(v) return type(v)=="table" and (v.kind or (v.ClassName and "Instance")) or type(v) end
local DevAccess = (function()
'''

MOCK = r'''
end)()
local now = 10
local os = {clock = function() return now end}
-- the F8 water FX constants are module-scope Vector3s inside the gate section (the lifecycles shadow this)
local Vector3 = {new = function(x, y, z) return {X = x, Y = y, Z = z} end}
local Enum = {HumanoidStateType = {Dead = "Dead"}}
local function instance(class, name)
    local obj = {ClassName = class, Name = name, attrs = {}, children = {}}
    function obj:IsA(c) return c == self.ClassName or c == "BasePart" and self.ClassName == "Part" end
    function obj:GetAttribute(key) return self.attrs[key] end
    function obj:FindFirstChild(key) return self.children[key] end
    return obj
end
local function position(x)
    return setmetatable({x=x}, {__sub=function(a,b) return {Magnitude=math.abs(a.x-b.x)} end})
end
local workspace = instance("Workspace", "Workspace")
local Players = instance("Players", "Players")
local ServerStorage = instance("ServerStorage", "ServerStorage")
local lobby = instance("Model", "ServerLobby"); workspace.children.ServerLobby=lobby
local rooms = instance("Folder", "LevelQueueRooms"); lobby.children.LevelQueueRooms=rooms
local room = instance("Model", "Level2QueueRoom"); rooms.children.Level2QueueRoom=room
room.attrs.LevelNumber=2
local floor=instance("Part", "ChamberFloor"); room.children.ChamberFloor=floor; floor.CanCollide=true
local host=instance("Part", "Level2BlenderPreviewEntry")
host.Parent=room; host.attrs.Level2BlenderPreviewHost=true; host.Anchored=true
host.Transparency=1; host.CanCollide=false; host.CanTouch=false; host.CanQuery=false; host.Position=position(0)
local OWNER, RANGE, COOLDOWN="Level2BlenderPreviewHost",12,2
local hosts={[host]={room=room,floor=floor}}
local nextUse={}
local root=instance("Part", "HumanoidRootPart"); root.Position=position(0); root.Anchored=false
local hum={RootPart=root,Health=100,GetState=function() return "Running" end}
local char=instance("Model", "Character")
function char:IsDescendantOf(target) return target==workspace end
function char:FindFirstChildOfClass(class) return class=="Humanoid" and hum or nil end
local player=instance("Player", "Developer"); player.UserId=40920547; player.Parent=Players; player.Character=char
local calls=0
local launch=instance("BindableFunction", "Level2BlenderPreviewLaunch")
function launch:Invoke(p) calls+=1; check(p==player,"only requesting player is launched"); return true end
ServerStorage.children.Level2BlenderPreviewLaunch=launch
local handler, replies, warnings = nil, {}, {}
local request={OnServerEvent={Connect=function(_,fn) handler=fn end}}
function request:FireClient(p,accepted,reason) table.insert(replies,{accepted=accepted,reason=reason}) end
local function warn(...) table.insert(warnings,{...}) end
'''

CHECKS = r'''
check(activeRoom(nil)==false,"missing room fails closed")
check(readyPlayer(player,host)==char,"owner accepted at real host")
player.UserId=9488575949; check(readyPlayer(player,host)==char,"second shared developer accepted")
for _,id in ipairs({222,11374988579,833029598}) do
    player.UserId=id; handler(player,host); check(calls==0,"unauthorized/Level6 guest denied")
end
player.UserId=40920547
local function denied(message) handler(player,host); check(calls==0,message) end
root.Position=position(12.01); denied("distant request denied"); root.Position=position(0)
root.Anchored=true; denied("anchored avatar denied"); root.Anchored=false
hum.Health=0; denied("dead avatar denied"); hum.Health=100
hum.SeatPart={}; denied("seated avatar denied"); hum.SeatPart=nil
player.attrs.InRound=true; denied("campaign participant denied"); player.attrs.InRound=nil
player.attrs.Level6InRound=true; denied("other preview participant denied"); player.attrs.Level6InRound=nil
workspace.attrs.ReservedRoundServer=true; denied("reserved round entry denied"); workspace.attrs.ReservedRoundServer=nil
room.attrs.LevelNumber=1; denied("wrong room denied"); room.attrs.LevelNumber=2
host.Parent=lobby; denied("moved host denied"); host.Parent=room
host.Transparency=0; denied("visible server host denied"); host.Transparency=1
floor.CanCollide=false; denied("missing colliding floor denied"); floor.CanCollide=true
local fake=instance("Part","Level2BlenderPreviewEntry"); handler(player,fake); check(calls==0,"spoofed host denied")
handler(player,"host"); check(calls==0,"untrusted argument rejected")
ServerStorage.children.Level2BlenderPreviewLaunch=nil
handler(player,host); check(calls==0 and replies[#replies].reason=="PREVIEW_NOT_READY","missing launch rejects")
ServerStorage.children.Level2BlenderPreviewLaunch=launch; now+=3
function launch:Invoke() calls+=1; return false,"PREVIEW_NOT_READY" end
handler(player,host); check(calls==1 and replies[#replies].accepted==false,"asset readiness rejection preserved")
now+=3
function launch:Invoke() calls+=1; return false,"ROUND_BUSY" end
handler(player,host); check(calls==2 and replies[#replies].reason=="ROUND_BUSY","busy round rejection preserved")
now+=3
function launch:Invoke()
    calls+=1
    handler(player,host)
    return true
end
handler(player,host); check(calls==3 and replies[#replies].accepted==true,"authorized launch accepted; yielding invocation locked")
handler(player,host); check(calls==3,"cooldown rejects repeat")
now+=3
function launch:Invoke() calls+=1; error("test failure") end
handler(player,host); check(calls==4 and replies[#replies].reason=="PREVIEW_FAILED","launch errors fail closed")
now+=3
function launch:Invoke() calls+=1; return true end
handler(player,host); check(calls==5,"failed launch releases cooldown")
now+=3
function launch:Invoke() calls+=1; return false,"IN_QUEUE" end
handler(player,host); check(calls==6 and replies[#replies].reason=="IN_QUEUE","station membership rejection reaches client")
print("Level 2 preview access: "..checks.." checks passed")
'''

HOST_LIFECYCLE = r'''
local HOST_NAME = "Level2BlenderPreviewEntry"
local hosts = {}
local created = 0
local Vector3 = {new=function(x,y,z)
    return setmetatable({kind="Vector3",X=x,Y=y,Z=z}, {__add=function(a,b) return {X=a.X+b.X,Y=a.Y+b.Y,Z=a.Z+b.Z} end})
end}
local CFrame = {new=function(p) return {Position=p} end}
floor.Position = Vector3.new(63,29.58,-840)
local Instance = {new=function(class)
    created+=1
    local obj=instance(class, "")
    function obj:SetAttribute(key,value) self.attrs[key]=value end
    local destroyCallback
    obj.Destroying={Once=function(_,callback) destroyCallback=callback end}
    function obj:Destroy()
        if destroyCallback then destroyCallback() end
        if self.Parent then self.Parent.children[self.Name]=nil end
        self.Parent=nil
    end
    return setmetatable(obj,{__newindex=function(self,key,value)
        rawset(self,key,value)
        if key=="Parent" and value then value.children[self.Name]=self end
    end})
end}
'''

HOST_CHECKS = r'''
local before=checks
ensureHost(room, HOST_NAME)
local owned=room:FindFirstChild(HOST_NAME)
check(created==1 and owned~=nil and hosts[owned]~=nil,"new host ownership recorded")
check(owned.CFrame.Position.X==83 and math.abs(owned.CFrame.Position.Y-34)<1e-8
    and owned.CFrame.Position.Z==-848,"old room estimated host clears rear column")
for _=1,80 do ensureHost(room, HOST_NAME) end
check(created==1 and #warnings==0,"repeated room hooks reuse exact registered host")
check(hosts[owned].room==room and hosts[owned].floor==floor,"ownership binds exact live room/floor")
owned:Destroy()
check(hosts[owned]==nil,"destroyed host releases ownership registry")
ensureHost(room, HOST_NAME)
local replacement=room:FindFirstChild(HOST_NAME)
check(created==2 and replacement~=owned and hosts[replacement]~=nil,"replacement is independently registered")
replacement:Destroy()
local foreign=instance("Part",HOST_NAME); room.children[HOST_NAME]=foreign
ensureHost(room, HOST_NAME)
check(created==2 and hosts[foreign]==nil and room.children[HOST_NAME]==foreign and #warnings==1,
    "preexisting unregistered host is rejected and never replaced/adopted")
print("Level 2 preview host lifecycle: "..(checks-before).." checks passed")
'''

HOST_CHECKS += r'''
local preview=instance("Model","LobbyReimaginedPreview"); workspace.children.LobbyReimaginedPreview=preview
preview.attrs.LobbyReimaginedOwned=true; preview.attrs.R3QueueRevision=3; preview.attrs.Ready=true
preview.attrs.PreviewCenter=Vector3.new(220,30,-760)
local pads=instance("Folder","PreviewQueuePads"); preview.children.PreviewQueuePads=pads
local bay=instance("Model","QueueBay_Level2"); pads.children.QueueBay_Level2=bay
local bayFloor=instance("Part","ChamberFloor"); bayFloor.CanCollide=true
bayFloor.Position=Vector3.new(283,30.4,-840); bay.children.ChamberFloor=bayFloor
check(activeRoom(bay),"ready reimagined Level 2 bay active")
for _,attribute in ipairs({"LobbyReimaginedOwned","Ready","R3QueueRevision"}) do
    local value=preview.attrs[attribute]; preview.attrs[attribute]=nil
    check(not activeRoom(bay),"bay fails closed without "..attribute)
    ensureHost(bay, HOST_NAME); check(created==2,"inactive bay creates no host")
    preview.attrs[attribute]=value
end
check(not activeRoom(instance("Model","QueueBay_Level2")),"same-named foreign bay rejected")
preview.attrs.PreviewCenter=nil; ensureHost(bay, HOST_NAME); check(created==2,"missing center creates no host")
preview.attrs.PreviewCenter=Vector3.new(283,30,-760)
ensureHost(bay, HOST_NAME); check(created==2,"ambiguous outward side creates no host")
preview.attrs.PreviewCenter=Vector3.new(220,30,-760)
ensureHost(bay, HOST_NAME)
local east=bay:FindFirstChild(HOST_NAME)
check(created==3 and east.CFrame.Position.X==303 and math.abs(east.CFrame.Position.Y-34.82)<1e-8
    and east.CFrame.Position.Z==-840,"east bay estimate uses outward +X")
east:Destroy(); bayFloor.Position=Vector3.new(157,30.4,-840); ensureHost(bay, HOST_NAME)
local west=bay:FindFirstChild(HOST_NAME)
check(created==4 and west.CFrame.Position.X==137,"bay offset mirrors only X about PreviewCenter")
west:Destroy()
-- The new-map pedestal (owner 2026-10-07) stands beside the kit one: same rules, its own measured shift.
room.children[HOST_NAME]=nil
ensureHost(room, NEW_HOST)
local newOwned=room:FindFirstChild(NEW_HOST)
check(created==5 and hosts[newOwned]~=nil and newOwned.Name==NEW_HOST and newOwned.CFrame.Position.X==86
    and math.abs(newOwned.CFrame.Position.Y-34)<1e-8 and newOwned.CFrame.Position.Z==-836,
    "new-map host in the old room: kit spot + (3, 0, 12)")
ensureHost(bay, NEW_HOST)
local newBay=bay:FindFirstChild(NEW_HOST)
check(created==6 and hosts[newBay]~=nil and newBay.CFrame.Position.X==137
    and newBay.CFrame.Position.Z==-832,"new-map host in the bay: kit spot + (0, 0, 8)")
print("Level 2 host placement/activeness: checks passed; coordinates still require Studio measurement")
'''

NEWMAP_MOCK = r'''
local function signal()
    local s={list={}}
    function s:Connect(fn) local c={on=true}; function c:Disconnect() c.on=false end; table.insert(s.list,{c=c,fn=fn}); return c end
    function s:Once(fn) local c; c=s:Connect(function(...) c:Disconnect(); fn(...) end); return c end
    function s:Fire(...) for _,e in ipairs(s.list) do if e.c.on then e.fn(...) end end end
    return s
end
local vmeta={}
local function V(x,y,z) return setmetatable({X=x,Y=y,Z=z},vmeta) end
vmeta.__index=function(v,k) if k=="Magnitude" then return math.sqrt(v.X*v.X+v.Y*v.Y+v.Z*v.Z) end end
vmeta.__add=function(a,b) return V(a.X+b.X,a.Y+b.Y,a.Z+b.Z) end
vmeta.__sub=function(a,b) return V(a.X-b.X,a.Y-b.Y,a.Z-b.Z) end
vmeta.__mul=function(a,b) if type(b)=="number" then return V(a.X*b,a.Y*b,a.Z*b) end return V(a.X*b.X,a.Y*b.Y,a.Z*b.Z) end
vmeta.__eq=function(a,b) return a.X==b.X and a.Y==b.Y and a.Z==b.Z end
local Vector3={new=V,zero=V(0,0,0),zAxis=V(0,0,1),xAxis=V(1,0,0)}
local cmeta={}
cmeta.__add=function(c,v) return setmetatable({Position=c.Position+v},cmeta) end
local CFrame={lookAt=function(at,target) return setmetatable({Position=at,Target=target},cmeta) end,
    new=function(p) return setmetatable({Position=p},cmeta) end}
Enum.CameraMode={Classic="Classic"}
Enum.PartType={Block="Block",Cylinder="Cylinder"}
local waitHook=nil -- runs inside the next task.wait (a body swap while the entry waits)
local task={wait=function(t) if waitHook then local hook=waitHook; waitHook=nil; hook() end
    now+=(t or 1/60); return t or 1/60 end, spawn=function(fn,...) fn(...) end}
function Players:GetPlayers() return {player} end
local mapModel=instance("Model",NEW_MAP); workspace.children[NEW_MAP]=mapModel
local markers=instance("Folder","Markers"); mapModel.children.Markers=markers
local function marker(name,x)
    local p=instance("Part",name); p.Position=V(x,300,0); p.Size=V(1,1,1); markers.children[name]=p; return p
end
local spawnMarker,footMarker,exitMarker=marker("SPAWN",70000),marker("P0_00",70010),marker("EXIT",70100)
local lobbySpawn=instance("Part","LobbySpawn"); lobbySpawn.Position=V(0,30,0); lobbySpawn.CFrame=CFrame.new(V(0,30,0))
lobby.children.LobbySpawn=lobbySpawn
function player:SetAttribute(k,v) self.attrs[k]=v end
local streams,streamFailAt={},nil
local streamHook=nil -- runs inside the next stream (a marker swap while the entry yields)
function player:RequestStreamAroundAsync(position)
    table.insert(streams,position)
    if streamHook then local hook=streamHook; streamHook=nil; hook() end
    if streamFailAt==#streams then error("stream failed") end
end
root.Position=V(0,0,0); host.Position=V(0,0,0)
char.children.HumanoidRootPart=root
function char:PivotTo(cf) self.pivot=cf end
local newHost=instance("Part",NEW_HOST)
newHost.Parent=room; newHost.attrs.Level2BlenderPreviewHost=true; newHost.Anchored=true
newHost.Transparency=1; newHost.CanCollide=false; newHost.CanTouch=false; newHost.CanQuery=false; newHost.Position=V(0,0,0)
hosts[newHost]={room=room,floor=floor}
local function body(name,health)
    local b=instance("Model",name)
    local h={Health=health,Died=signal()}
    h.RootPart=instance("Part","HumanoidRootPart"); h.RootPart.Position=V(0,30,0)
    b.children.HumanoidRootPart=h.RootPart
    b.AncestryChanged=signal(); b.alive=true; b.Humanoid=h
    function b:IsDescendantOf(target) return self.alive and target==workspace end
    function b:FindFirstChildOfClass(class) return class=="Humanoid" and h or nil end
    function b:PivotTo(cf) self.pivot=cf; h.RootPart.Position=cf.Position end
    return b
end
local function replace(p,new)
    local old=p.Character
    if old and old.AncestryChanged then old.alive=false; old.AncestryChanged:Fire() end
    p.Character=new
end
local loads={gameplay=0,lobby=0}
local gameplayResult,gameplayHealth,flagAtLoad=true,100,nil
local gameplay=instance("BindableFunction","LoadGameplayCharacter")
function gameplay:Invoke(p)
    loads.gameplay+=1; flagAtLoad=p.attrs.Level2NewMapPreview
    if gameplayResult=="throw" then error("load failed") end
    if gameplayResult~=true then return gameplayResult end
    replace(p,body("RoundBody",gameplayHealth)); return true
end
local lobbyResult=true
local lobbyLoad=instance("BindableFunction","LoadLobbyCharacter")
function lobbyLoad:Invoke(p)
    loads.lobby+=1
    if lobbyResult~=true then return lobbyResult end
    replace(p,body("LobbyBody",100)); return true
end
ServerStorage.children.LoadGameplayCharacter=gameplay
ServerStorage.children.LoadLobbyCharacter=lobbyLoad
function workspace:GetServerTimeNow() return now end
local statusEvents={} -- RoundStatus fired to the rider: {event, ...}
local roundStatus=instance("RemoteEvent","RoundStatus")
function roundStatus:FireClient(p,...) check(p==player,"RoundStatus goes to the rider only"); table.insert(statusEvents,{...}) end
local remotesFolder=instance("Folder","Remotes"); remotesFolder.children.RoundStatus=roundStatus
local ReplicatedStorage=instance("ReplicatedStorage","ReplicatedStorage"); ReplicatedStorage.children.Remotes=remotesFolder
'''

NEWMAP_CHECKS = r'''
local before=checks
local function last() return replies[#replies] end
local function lobbyBody() player.Character=char; root.Position=V(0,0,0); hum.Health=100 end

ServerStorage.children.LoadGameplayCharacter=nil
now+=3; handler(player,newHost)
check(last().accepted==false and last().reason=="PREVIEW_NOT_READY" and player.attrs.Level2NewMapPreview==nil
    and loads.gameplay==0,"no round-body load in ServerStorage: refused, no flag")
ServerStorage.children.LoadGameplayCharacter=gameplay

markers.children.SPAWN=nil
now+=3; handler(player,newHost)
check(last().accepted==false and last().reason=="PREVIEW_NOT_READY" and player.attrs.Level2NewMapPreview==nil
    and loads.gameplay==0,"no SPAWN marker (a model built before 2026-10-08): refused, no flag")
markers.children.SPAWN=spawnMarker

now+=3; handler(player,newHost)
local first=player.Character
check(flagAtLoad==true,"the flag is up before GameManager loads the body, so onCharacter sees a preview body")
check(last().accepted==true and last().reason=="NEW_MAP","entry answers NEW_MAP (the client turns its camera)")
check(first.Name=="RoundBody" and player.attrs.Level2NewMapPreview==true and previewBodies[player]==first,
    "the player wears the round body under the flag")
check(first.pivot and first.pivot.Position==V(70000,302,0) and first.pivot.Target==V(70000,302,1),
    "the round body stands at SPAWN (Level 1's door, the top of the stairs), level, facing +Z down the stair core")
check(#streams==2 and streams[1]==spawnMarker.Position and streams[2]==spawnMarker.Position,
    "the start is streamed before the load and again before the move")
check(loads.lobby==0 and #warnings==0,"a good entry loads no lobby body and warns nothing")
first.Humanoid.Health=0; first.Humanoid.Died:Fire()
lobbyBody(); local gameplays=loads.gameplay
streamHook=function() markers.children.SPAWN=marker("SPAWN",70000) end
now+=3; handler(player,newHost)
check(last().accepted==false and last().reason=="ENTRY_CHANGED" and player.attrs.Level2NewMapPreview==nil
    and loads.gameplay==gameplays,"SPAWN replaced while the arrival streams: refused before any load")
markers.children.SPAWN=spawnMarker
check(player.attrs.Level2NewMapPreview==nil and previewBodies[player]==nil,"death clears the flag")

lobbyBody(); now+=3; handler(player,newHost)
local second=player.Character
check(second.Name=="RoundBody" and player.attrs.Level2NewMapPreview==true,"a second entry flags again")
first.alive=false; first.AncestryChanged:Fire()
check(player.attrs.Level2NewMapPreview==true,"an older body leaving never clears the current flag")
second.alive=false; second.AncestryChanged:Fire()
check(player.attrs.Level2NewMapPreview==nil,"the round body leaving the workspace clears the flag")

lobbyBody(); now+=3; handler(player,newHost)
local third=player.Character
local lobbies=loads.lobby
now+=3; returnToLobby(player,spawnMarker)
check(loads.lobby==lobbies+1 and player.Character.Name=="LobbyBody" and player.attrs.Level2NewMapPreview==nil
    and third.pivot.Position==V(70000,302,0),"RETURN TO LOBBY swaps the lobby avatar back (GameManager places it)")
check(streams[#streams]==lobbySpawn.Position,"the lobby is streamed before the swap")

lobbyBody(); now+=3; handler(player,newHost)
local fourth=player.Character
lobbyResult=false; now+=3; returnToLobby(player,spawnMarker)
check(player.attrs.Level2NewMapPreview==nil and player.Character==fourth and fourth.pivot.Position==V(0,34,0)
    and player.CameraMode=="Classic" and player.CameraMaxZoomDistance==18 and player.CameraMinZoomDistance==8,
    "a failed lobby load still clears the flag, moves the body to the lobby and gives the lobby camera")
lobbyResult=true

lobbyBody(); root.Position=V(70000,302,0); lobbies=loads.lobby
now+=3; returnToLobby(player,spawnMarker)
check(loads.lobby==lobbies and char.pivot and char.pivot.Position==V(0,34,0),
    "a personal avatar (no flag) is moved to the lobby, not reloaded")

lobbyBody(); gameplayResult=false; lobbies=loads.lobby; now+=3; handler(player,newHost)
check(last().accepted==false and last().reason=="PREVIEW_FAILED" and player.attrs.Level2NewMapPreview==nil
    and player.Character==char and loads.lobby==lobbies,"a refused load clears the flag and keeps the lobby body")
gameplayResult="throw"; now+=3; handler(player,newHost)
check(last().reason=="PREVIEW_FAILED" and player.attrs.Level2NewMapPreview==nil and player.Character==char,
    "a load error clears the flag")
gameplayResult=true

lobbyBody(); streamFailAt=#streams+2; lobbies=loads.lobby; now+=3; handler(player,newHost)
check(last().reason=="PREVIEW_FAILED" and player.attrs.Level2NewMapPreview==nil and previewBodies[player]==nil
    and loads.lobby==lobbies+1 and player.Character.Name=="LobbyBody",
    "a failure after the body loaded clears the flag and swaps the lobby avatar back")
streamFailAt=nil

lobbyBody(); gameplayHealth=0; lobbies=loads.lobby; now+=3; handler(player,newHost)
check(last().reason=="PREVIEW_FAILED" and player.attrs.Level2NewMapPreview==nil and loads.lobby==lobbies+1,
    "a body that never comes alive (6 s) clears the flag and restores the lobby avatar")
gameplayHealth=100

lobbyBody(); gameplayHealth=0; lobbies=loads.lobby
local intruder=nil
waitHook=function() intruder=body("Intruder",100); replace(player,intruder) end
now+=3; handler(player,newHost)
check(intruder~=nil and intruder.pivot==nil and last().reason=="PREVIEW_FAILED"
    and player.attrs.Level2NewMapPreview==nil and previewBodies[player]==nil and loads.lobby==lobbies+1,
    "a different body replacing the load's body is never adopted: the entry fails and the lobby body comes back")
gameplayHealth=100

lobbyBody(); now+=3; handler(player,newHost)
local diver=player.Character
local hazard=instance("Part","Hazard"); hazard.Parent=mapModel; hazard.Size=V(10,40,10)
hazard.CFrame={PointToObjectSpace=function(_,p) return p-V(70050,250,0) end}
diver.Humanoid.RootPart.Position=V(70050,271,0)
zoneStep({hazard},nil)
check(diver.Humanoid.Health==100,"above a KillZone hazard: alive")
diver.Humanoid.RootPart.Position=V(70054,232,-4)
zoneStep({hazard},nil)
check(diver.Humanoid.Health==0,"inside a KillZone hazard: dead")
diver.Humanoid.Died:Fire()
check(player.attrs.Level2NewMapPreview==nil,"the kill clears the flag through the death hook")
hazard.Parent=nil; lobbyBody(); now+=3; handler(player,newHost)
player.Character.Humanoid.RootPart.Position=V(70054,232,-4); zoneStep({hazard},nil)
check(player.Character.Humanoid.Health==100,"a removed hazard no longer kills")

local rider=player.Character
local since=previewSince[player]
local finish=instance("Part","Exit Slide Finish"); finish.Parent=mapModel; finish.Size=V(14,14.4,12)
finish.Position=V(70120,310,0); finish.CFrame={PointToObjectSpace=function(_,p) return p-finish.Position end}
rider.Humanoid.RootPart.Position=V(70100,310,0); lobbies=loads.lobby
now+=3; zoneStep({},finish)
check(#statusEvents==0 and loads.lobby==lobbies and player.Character==rider,"short of the finish: nothing happens")
check(since~=nil and since<now,"the entry recorded its server time for the card")
local winAt=now
waitHook=function() zoneStep({},finish) end -- the rider is still in the box while the card is up
rider.Humanoid.RootPart.Position=V(70118,306,2); zoneStep({},finish)
local win=statusEvents[1]
check(win and win[1]=="win" and win[2]==winAt-since and win[3]==1 and win[4]==1 and win[5]==winAt+RESULT_SECONDS
    and win[6]==nil and win[7]==nil,
    "the finish: RoundUI's own win (time since the entry, 1/1, the card's deadline; no next level, no serial)")
check(#statusEvents==2 and statusEvents[2][1]=="lobby","one card per ride, then lobby takes it down")
check(loads.lobby==lobbies+1 and player.attrs.Level2NewMapPreview==nil and player.Character.Name=="LobbyBody"
    and finishing[player]==nil,"after the card: the lobby the RETURN TO LOBBY way, the latch cleared")
check(inside(finish,V(70127,317.2,6)) and not inside(finish,V(70127.1,310,0)),"zone test is the box, faces included")
player.Character.Humanoid.RootPart.Position=V(70118,306,2); zoneStep({},finish)
check(#statusEvents==2,"a body without the preview flag (the lobby avatar) gets no card")
local drain=instance("Part","Hazard"); drain.Shape="Cylinder"; drain.Size=V(40,10,10)
drain.CFrame={PointToObjectSpace=function(_,p) return p-V(70300,250,0) end}
check(inside(drain,V(70300,254,0)) and inside(drain,V(70319,250,-5)) and not inside(drain,V(70300,254,4))
    and not inside(drain,V(70321,250,0)),"a Cylinder kill zone is round about its X axis, not its bounding box")
lobbyBody(); now+=3; handler(player,newHost)
local corpse=player.Character; corpse.Humanoid.Health=0; corpse.Humanoid.Died:Fire()
corpse.Humanoid.RootPart.Position=V(70000,302,0); lobbies=loads.lobby; now+=3; returnToLobby(player,spawnMarker)
check(loads.lobby==lobbies and corpse.pivot.Position==V(70000,302,0),"a corpse is not moved or swapped by RETURN TO LOBBY")
-- RETURN TO LOBBY out of reach is refused (only the slide's finish passes no point)
lobbyBody(); now+=3; handler(player,newHost)
local far=player.Character; lobbies=loads.lobby
far.Humanoid.RootPart.Position=V(70000,302,0); now+=3; returnToLobby(player,exitMarker)
check(loads.lobby==lobbies and player.Character==far and player.attrs.Level2NewMapPreview==true,
    "RETURN TO LOBBY from beyond the prompt's reach is refused")
-- a refused return at the finish (a cooldown) is retried; a body never returned keeps the latch
statusEvents={}; far.Humanoid.RootPart.Position=V(70118,306,2); nextUse[player]=now+1000
zoneStep({},finish)
check(#statusEvents==2 and statusEvents[1][1]=="win" and statusEvents[2][1]=="lobby" and loads.lobby==lobbies
    and player.Character==far and finishing[player]==far,
    "a refused return is retried, then the card goes; the latch stays on that body")
zoneStep({},finish)
check(#statusEvents==2,"a latched body gets no second card")
nextUse[player]=nil
print("Level 2 new-map entry, flag lifecycle and zone pass: "..(checks-before).." checks passed")
'''

CLIENT_MOCK = r'''
local checks=0
local function check(ok,label) checks+=1; assert(ok,label) end
local function signal()
    local event={listeners={}}
    function event:Connect(callback)
        local connection={Connected=true}
        function connection:Disconnect() self.Connected=false end
        table.insert(self.listeners,{connection=connection,callback=callback})
        return connection
    end
    function event:Once(callback)
        local connection
        connection=self:Connect(function(...) connection:Disconnect(); callback(...) end)
        return connection
    end
    function event:Fire(...)
        for _,item in ipairs(self.listeners) do if item.connection.Connected then item.callback(...) end end
    end
    function event:ActiveCount()
        local count=0; for _,item in ipairs(self.listeners) do if item.connection.Connected then count+=1 end end
        return count
    end
    return event
end
local created=0
local function instance(class,name)
    local obj={ClassName=class,Name=name or class,children={},attrs={},signals={},Enabled=true,alive=true,
        AncestryChanged=signal(),Destroying=signal(),Triggered=signal()}
    function obj:IsA(kind) return kind==self.ClassName or kind=="BasePart" and self.ClassName=="Part" end
    function obj:GetAttribute(key) return self.attrs[key] end
    function obj:FindFirstChild(key) return self.children[key] end
    function obj:GetAttributeChangedSignal(key)
        self.signals[key]=self.signals[key] or signal(); return self.signals[key]
    end
    function obj:SetAttribute(key,value)
        if self.attrs[key]~=value then self.attrs[key]=value; self:GetAttributeChangedSignal(key):Fire() end
    end
    function obj:IsDescendantOf() return self.alive end
    function obj:Destroy()
        self.Destroying:Fire(); self.Destroyed=true
        if self.Parent then self.Parent.children[self.Name]=nil end
        self.Parent=nil
    end
    return setmetatable(obj,{
        __index=function(self,key) return key=="Parent" and rawget(self,"_parent") or self.children[key] end,
        __newindex=function(self,key,value)
            if key=="Parent" then rawset(self,"_parent",value); if value then value.children[self.Name]=self end
            else rawset(self,key,value) end
        end})
end
local player=instance("Player","Developer"); player.UserId=40920547; player.CharacterRemoving=signal()
local Players={LocalPlayer=player}
local root=instance("Part","HumanoidRootPart"); root.Position={X=20,Y=0,Z=0}; root.CollisionGroup="Default"
local character=instance("Model","Character"); character.children.HumanoidRootPart=root; player.Character=character
local hostA=instance("Part","Level2BlenderPreviewEntry")
hostA.attrs.Level2BlenderPreviewHost=true; hostA.Transparency=1; hostA.Position={X=0,Y=34,Z=0}
local hostB=instance("Part","Level2BlenderPreviewEntry")
hostB.attrs.Level2BlenderPreviewHost=true; hostB.Transparency=1; hostB.Position={X=40,Y=34,Z=0}
local workspace=instance("Workspace","Workspace"); workspace.DescendantAdded=signal(); workspace.DescendantRemoving=signal()
local zone=instance("Part","LaunchZone5"); zone.attrs.QueueDetectorShape="Circle"; zone.attrs.QueueRadius=7.41
zone.Size={X=14.82,Z=14.82}; zone.CFrame={PointToObjectSpace=function(_,p) return p end}
function workspace:GetDescendants() return {hostA,hostB,zone} end
local remote=instance("RemoteEvent","Level2BlenderPreviewRequest"); remote.OnClientEvent=signal()
local calls={}
function remote:FireServer(host) table.insert(calls,host) end
local access={}
local ReplicatedStorage={WaitForChild=function(_,key) return key=="DevAccess" and access or remote end}
local RunService={Heartbeat=signal(),steps={}}
function RunService:BindToRenderStep(name,priority,callback) self.steps[name]={priority=priority,callback=callback} end
local game={GetService=function(_,key) return key=="Players" and Players or key=="RunService" and RunService or ReplicatedStorage end}
local function require(module) assert(module==access); return {IsAllowed=function(p) return p.UserId==40920547 end} end
-- `created` counts prompts; the developer pedestal parts are checked separately.
local Instance={new=function(class) if class=="ProximityPrompt" then created+=1 end; return instance(class) end}
local Enum={RaycastFilterType={Exclude="Exclude"},PartType={Cylinder="Cylinder"},
    Material={SmoothPlastic="SmoothPlastic",Neon="Neon"},Font={GothamBold="GothamBold"},
    RenderPriority={Camera={Value=200}},CameraType={Custom="Custom"}}
local RaycastParams={new=function() return {} end}
local Vector3={new=function(x,y,z) return {X=x,Y=y,Z=z} end}
local frameMeta={__mul=function(a) return a end}
local CFrame={new=function() return setmetatable({},frameMeta) end,Angles=function() return {} end}
local Color3={fromRGB=function() return {} end,new=function() return {} end}
local UDim2={fromOffset=function() return {} end,fromScale=function() return {} end}
function workspace:Raycast() return nil end
local now=10
local os={clock=function() return now end}
local delayed={}
local task={delay=function(_,callback) table.insert(delayed,callback) end}
'''

CLIENT_CHECKS = r'''
local promptA=hostA:FindFirstChild("Level2DeveloperPreviewPrompt")
local promptB=hostB:FindFirstChild("Level2DeveloperPreviewPrompt")
check(created==2 and promptA and promptB,"one native prompt per authorized host")
check(promptA:IsA("ProximityPrompt") and promptA.HoldDuration==0.5 and promptA.MaxActivationDistance==10
    and promptA.RequiresLineOfSight==false and promptA.ObjectText=="LEVEL 2 DEVELOPER PREVIEW"
    and promptA.ActionText=="PLAY OLD KIT ROUND",
    "same native interaction configuration as live Level4-6, named for the kit round (owner 2026-10-07)")
for _=1,80 do workspace.DescendantAdded:Fire(hostA) end
check(created==2,"repeated descendant hooks never duplicate the local prompt")
local pedestalA=hostA:FindFirstChild("Level2PreviewPedestal")
check(pedestalA and hostB:FindFirstChild("Level2PreviewPedestal") and pedestalA:FindFirstChild("Button")
    and pedestalA.Button:FindFirstChild("Label") and pedestalA.Button.Label:FindFirstChild("TextLabel")
    and pedestalA.Button.Label.TextLabel.Text=="LEVEL 2: OLD PREVIEW\nKIT ROUND"
    and pedestalA.Post.CanCollide==false and pedestalA.Button.CanQuery==false,
    "each host shows one visible, non-colliding developer pedestal")
root.Position.X=0; RunService.Heartbeat:Fire(.21)
check(not promptA.Enabled and not promptB.Enabled,"standing on an active launch zone hides prompts")
root.Position.X=20; RunService.Heartbeat:Fire(.21)
check(promptA.Enabled and promptB.Enabled,"stepping off the station restores prompts")
root.CollisionGroup="QueueMember"; RunService.Heartbeat:Fire(.21)
check(not promptA.Enabled and not promptB.Enabled,"admitted party member hides prompts")
root.CollisionGroup="Default"; RunService.Heartbeat:Fire(.21)
check(promptA.Enabled and promptB.Enabled,"released party member restores prompts")
local revised=instance("Part","QueueZone1"); revised.attrs.QueueDetectorShape="Circle"; revised.attrs.QueueRadius=7.41
revised.attrs.R3QueueId=105; revised.Size=zone.Size; revised.CFrame=zone.CFrame
workspace.DescendantAdded:Fire(revised); zone.alive=false; root.Position.X=0; RunService.Heartbeat:Fire(.21)
check(not promptA.Enabled and not promptB.Enabled,"revised lobby station also hides prompts")
workspace.DescendantRemoving:Fire(revised); root.Position.X=20; RunService.Heartbeat:Fire(.21)
check(promptA.Enabled and promptB.Enabled,"removed revised station releases prompt")
promptA.Triggered:Fire(); promptA.Triggered:Fire()
check(#calls==1 and calls[1]==hostA,"native Triggered sends exact host and cooldown rejects duplicate")
player.attrs.InRound=true; player:GetAttributeChangedSignal("InRound"):Fire()
check(not promptA.Enabled and not promptB.Enabled,"round participation hides all prompt UI")
now+=3; promptA.Triggered:Fire(); check(#calls==1,"disabled prompt cannot request entry")
player.attrs.InRound=nil; player:GetAttributeChangedSignal("InRound"):Fire()
check(promptA.Enabled and promptB.Enabled,"prompt returns after round")
hostA.alive=false; hostA.AncestryChanged:Fire()
check(promptA.Destroyed and promptA.Triggered:ActiveCount()==0 and hostA.AncestryChanged:ActiveCount()==0,
    "removed host destroys complete UI and disconnects callbacks")
check(pedestalA.Destroyed,"removed host destroys its pedestal")
hostA.alive=true; workspace.DescendantAdded:Fire(hostA)
local restored=hostA:FindFirstChild("Level2DeveloperPreviewPrompt")
check(created==3 and restored~=promptA and restored.Enabled,"restored host creates one fresh prompt")
hostB.Destroying:Fire()
check(promptB.Destroyed and promptB.Triggered:ActiveCount()==0 and hostB.Destroying:ActiveCount()==0,
    "destroying host cleans local ownership and callbacks")
player.attrs.Level6InRound=true; player:GetAttributeChangedSignal("Level6InRound"):Fire()
check(not restored.Enabled,"other preview disables local prompt")
player.attrs.Level6InRound=nil; player:GetAttributeChangedSignal("Level6InRound"):Fire()
workspace.attrs.ReservedRoundServer=true; workspace:GetAttributeChangedSignal("ReservedRoundServer"):Fire()
check(not restored.Enabled,"reserved server disables local prompt")
workspace.attrs.ReservedRoundServer=nil; workspace:GetAttributeChangedSignal("ReservedRoundServer"):Fire()
remote.OnClientEvent:Fire(false,"ROUND_BUSY")
check(restored.ActionText=="ROUND BUSY · TRY AGAIN","failure feedback uses surviving native prompt")
remote.OnClientEvent:Fire(false,"IN_QUEUE")
check(restored.ActionText=="LEAVE THE QUEUE TO PREVIEW","queue refusal gives actionable feedback")
for _,callback in ipairs(delayed) do callback() end
check(restored.ActionText=="PLAY OLD KIT ROUND","feedback restores preview action")
local clamp=RunService.steps.Level2NewMapCameraClamp
check(clamp and clamp.priority==201 and player.CharacterRemoving:ActiveCount()==1,
    "camera clamp bound one step after the camera module; grade released on CharacterRemoving")
print("Level 2 native client prompt lifecycle: "..checks.." checks passed")
'''

def main():
    artifact_binary = ROOT / "artifacts/hazmat-20260924/luau-0.737/luau.exe"
    binary = os.environ.get("LUAU_BIN") or shutil.which("luau") or (
        str(artifact_binary) if artifact_binary.is_file() else None
    )
    if not binary:
        raise SystemExit("Set LUAU_BIN or put luau on PATH; no checks executed.")
    assert 'game.PrivateServerId ~= "" and game.PrivateServerOwnerId == 0 then return end' in SERVER
    gate = section(SERVER, "local function readyPlayer", "Players.PlayerRemoving:Connect")
    rooms = section(SERVER, "local function activeRoom", "local function ensureHost")
    names = section(SERVER, "local NEW_HOST", "-- Best estimates")
    code = PRELUDE + ACCESS + MOCK + names + rooms + gate + CHECKS
    host_code = (PRELUDE + ACCESS + MOCK + names + rooms + HOST_LIFECYCLE
                 + section(SERVER, "local SERVER_LOBBY_HOST_OFFSET", "-- Instance userdata")
                 + section(SERVER, "local function ensureHost", "local function hookRooms") + HOST_CHECKS)
    newmap_code = PRELUDE + ACCESS + MOCK + names + NEWMAP_MOCK + rooms + gate + NEWMAP_CHECKS
    # Execute the entire real client early return for an ordinary player. No UI
    # factory may be reached, including the special Level 6 guest account.
    client_check = r'''
local player={UserId=11374988579}
local Players={LocalPlayer=player}
local ReplicatedStorage={WaitForChild=function(_,name) assert(name=="DevAccess"); return name end}
local game={GetService=function(_,name) return name=="Players" and Players or ReplicatedStorage end}
local function require() return {IsAllowed=function() return false end} end
local Instance={new=function() error("unauthorized visible UI created") end}
(function()
''' + CLIENT + '\nend)()\nprint("Level 2 preview client: unauthorized account creates no UI")\n'
    client_lifecycle = CLIENT_MOCK + '\n(function()\n' + CLIENT + '\nend)()\n' + CLIENT_CHECKS
    with tempfile.TemporaryDirectory(prefix="level2-preview-gate-") as directory:
        for name, source in (("gate.luau", code), ("host-lifecycle.luau", host_code), ("newmap.luau", newmap_code),
                             ("client-denied.luau", client_check), ("client-lifecycle.luau", client_lifecycle)):
            path = Path(directory) / name
            path.write_text(source, encoding="utf-8")
            subprocess.run([binary, str(path)], check=True)
        compiler = Path(binary).with_name("luau-compile.exe")
        if compiler.exists():
            for name, source in (("server.luau", SERVER), ("client.luau", CLIENT)):
                path = Path(directory) / name
                path.write_text(source, encoding="utf-8")
                subprocess.run([str(compiler), "-O0", str(path)], stdout=subprocess.DEVNULL, check=True)


if __name__ == "__main__":
    main()
