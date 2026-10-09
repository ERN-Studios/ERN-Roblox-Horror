"""Run the actual Level 3 exit builder, guards, entry handlers and cleanup in Luau.

Only Roblox engine objects and unrelated CD/audio/lighting operations are fakes.
This verifies server authority and authored trigger placement; Studio must still
prove physical running, client streaming and multiplayer character collision.
"""

import os
from pathlib import Path
import shutil
import subprocess
import tempfile

ROOT = Path(__file__).resolve().parents[2]
SYSTEMS = ROOT / "ServerScriptService/Level 3 Systems"


def section(source, start, stop):
    begin = source.index(start)
    return source[begin:source.index(stop, begin)]


HARNESS = r'''
type AnyTable = {[any]: any}
local checks = 0
local function check(value, message)
    checks += 1
    assert(value, message)
end
local function equal(actual, wanted, message)
    check(actual == wanted, message .. ": expected " .. tostring(wanted) .. ", got " .. tostring(actual))
end
local Vector3 = {}
local vectorMeta = {}
function Vector3.new(x, y, z) return setmetatable({X=x, Y=y, Z=z}, vectorMeta) end
vectorMeta.__add = function(a,b) return Vector3.new(a.X+b.X,a.Y+b.Y,a.Z+b.Z) end
vectorMeta.__sub = function(a,b) return Vector3.new(a.X-b.X,a.Y-b.Y,a.Z-b.Z) end
vectorMeta.__mul = function(a,b) return Vector3.new(a.X*b,a.Y*b,a.Z*b) end
vectorMeta.__index = function(v,k) if k == "Magnitude" then return math.sqrt(v.X*v.X+v.Y*v.Y+v.Z*v.Z) end end
Vector3.zero = Vector3.new(0,0,0)
local CFrame = {}
local cfMeta = {}
function CFrame.new(x,y,z)
    local p = type(x) == "table" and x or Vector3.new(x or 0,y or 0,z or 0)
    return setmetatable({Position=p, Yaw=0},cfMeta)
end
function cfMeta:PointToObjectSpace(p)
    local d = p-self.Position
    local c,s = math.cos(self.Yaw),math.sin(self.Yaw)
    return Vector3.new(c*d.X+s*d.Z,d.Y,-s*d.X+c*d.Z)
end
function cfMeta:PointToWorldSpace(p)
    local c,s = math.cos(self.Yaw),math.sin(self.Yaw)
    return self.Position+Vector3.new(c*p.X-s*p.Z,p.Y,s*p.X+c*p.Z)
end
cfMeta.__index = cfMeta
cfMeta.__mul = function(a,b) return CFrame.new(a:PointToWorldSpace(b.Position)) end
local Color3 = {new=function(...) return {...} end,fromRGB=function(...) return {...} end}
local Enum = {Material={SmoothPlastic="SmoothPlastic",DiamondPlate="DiamondPlate",Metal="Metal",Neon="Neon",Concrete="Concrete"},
    NormalId={Right="Right",Left="Left"},SurfaceType={Smooth="Smooth"},
    EasingStyle={Quad="Quad"},EasingDirection={Out="Out"}}
local TweenInfo = {new=function(...) return {...} end}
local function signal(owner)
    local entries = {}
    return {
        Connect = function(_,callback)
            -- Mirrors the important engine rule: CanTouch=false cannot listen.
            assert(not owner or owner.CanTouch, "cannot connect Touched while CanTouch=false")
            local connection = {Connected=true,Callback=callback}
            function connection:Disconnect() self.Connected=false end
            table.insert(entries,connection)
            return connection
        end,
        Fire = function(_, ...)
            if owner and not owner.CanTouch then return end
            for _,entry in ipairs(entries) do if entry.Connected then entry.Callback(...) end end
        end,
        Count = function()
            local count=0
            for _,entry in ipairs(entries) do if entry.Connected then count+=1 end end
            return count
        end,
    }
end
local allNodes = {}
local methods = {}
local Instance = {}
function Instance.new(class)
    local value = setmetatable({ClassName=class,Attributes={},AttributeWrites={},Name=class}, {
        __index=function(self,key)
            if key=="Position" then return self.CFrame and self.CFrame.Position end
            return methods[key]
        end,
    })
    if class=="Part" then
        value.CanCollide,value.CanTouch,value.CanQuery=true,true,true
        value.CFrame,value.Size=CFrame.new(),Vector3.new(1,1,1)
        value.Touched=signal(value)
    end
    table.insert(allNodes,value)
    return value
end
function methods:IsA(class)
    return self.ClassName==class or (class=="BasePart" and self.ClassName=="Part")
end
function methods:SetAttribute(key,value)
    self.Attributes[key]=value
    self.AttributeWrites[key]=(self.AttributeWrites[key] or 0)+1
end
function methods:GetAttribute(key) return self.Attributes[key] end
function methods:IsDescendantOf(parent)
    local object=self.Parent
    while object do if object==parent then return true end; object=object.Parent end
    return false
end
function methods:GetDescendants()
    local result={}
    for _,object in ipairs(allNodes) do if object:IsDescendantOf(self) then table.insert(result,object) end end
    return result
end
function methods:FindFirstChild(name, recursive)
    for _,object in ipairs(allNodes) do
        if object.Name==name and (object.Parent==self or (recursive and object:IsDescendantOf(self))) then return object end
    end
end
function methods:FindFirstChildOfClass(class)
    for _,object in ipairs(allNodes) do if object.Parent==self and object:IsA(class) then return object end end
end
function methods:FindFirstAncestorOfClass(class)
    local object=self.Parent
    while object do if object:IsA(class) then return object end; object=object.Parent end
end
function methods:Destroy() self.Parent=nil end
function methods:PivotTo(cf)
    self.LastPivot=cf
    self.PivotCount=(self.PivotCount or 0)+1
    local root=self:FindFirstChild("HumanoidRootPart")
    if root then root.Position=cf.Position end
end
local function folder(parent,name)
    local value=Instance.new("Folder");value.Name=name;value.Parent=parent;return value
end
local function texture() end
local TEXTURES={FinalExitDoor="test"}
local C={Energon=Color3.new()}
local function worldPosition(room) return Vector3.new(room.X,room.Y or 0,room.Z) end
__PART_HELPERS__
__EXIT_BUILDER__

local workspace=Instance.new("Model")
function workspace:GetServerTimeNow() return 42 end
local Players=Instance.new("Players")
local roster={}
function Players:GetPlayers() return roster end
function Players:GetPlayerFromCharacter(character)
    for _,player in ipairs(roster) do if player.Character==character then return player end end
end
local RunService={Heartbeat=signal()}
local Configuration={MusicSequence={CompletionDimSeconds=2}}
local ObjectiveController={}
local activeSession,unlockExit
local function updateSharedState() end
local function updateFinalHallChase() end
local function firePayload(session,payload) session.Payloads[#session.Payloads+1]=payload end
local function fireSound(session,kind,position,player)
    if kind=="Escape" then session.SoundCount+=1 end
end
local function fireEscapeStatus(player) player.EscapeNotices=(player.EscapeNotices or 0)+1 end
local function playTween(_,object,_,goals) for key,value in pairs(goals) do object[key]=value end end
local function restoreModule() end
local function destroyCarryVisual() end
local function updateDiscPlayerVisuals() end
__DISCONNECT_HELPERS__
__PLAYER_GUARDS__
__UNLOCK_EXIT__
__ESCAPE_PLAYER__
__STOP_CONTROLLER__
local function attachHandlers(session)
    local manifest=session.Manifest
    __HEARTBEAT_HANDLER__
    __TOUCH_HANDLER__
end

local function fresh()
    if activeSession then ObjectiveController.Stop() end
    roster={}
    workspace:SetAttribute("SelectedLevel",3)
    workspace:SetAttribute("RoundActive",true)
    local world=Instance.new("Model");world.Parent=workspace;world:SetAttribute("Level3_Generation",7)
    local room={X=100,Y=24,Z=60,W=64}
    local trigger,safeSpawn,position,finalExit=makeExitSet(world,room)
    local portalModel=Instance.new("Model");portalModel.Parent=world
    local wall=Instance.new("Part");wall.Parent=portalModel
    local manifest={World=world,EscapeTrigger=trigger,ExitSafeSpawn=safeSpawn,ExitPosition=position,
        FinalExit=finalExit,Modules={},ExitPortal={Model=portalModel,Wall=wall,FrameParts={}}}
    local state=Instance.new("Folder");state.Parent=workspace
    local session={Manifest=manifest,Generation=7,State=state,Connections={},Tweens={},CDRecords={},
        ModuleOriginals={},Escaping={},ExitUnlocked=false,EscapeOrdinal=0,
        FinalHallAccumulator=0,SoundCount=0,Payloads={}}
    activeSession=session
    attachHandlers(session)
    local ctx={Session=session,World=world,Trigger=trigger,Room=room,Manifest=manifest}
    function ctx:AddPlayer(name,localPosition)
        local player=Instance.new("Player");player.Name=name or "Runner";player.Parent=Players
        player:SetAttribute("InRound",true)
        local character=Instance.new("Model");character.Parent=workspace;player.Character=character
        local root=Instance.new("Part");root.Name="HumanoidRootPart";root.Parent=character
        root.Position=self.Trigger.CFrame:PointToWorldSpace(localPosition or Vector3.zero)
        root.AssemblyLinearVelocity=Vector3.new(30,0,0)
        root.AssemblyAngularVelocity=Vector3.new(0,4,0)
        local humanoid=Instance.new("Humanoid");humanoid.Parent=character;humanoid.Health=100
        table.insert(roster,player)
        return player,character,root,humanoid
    end
    function ctx:Unlock() unlockExit(self.Session,"SignalHall") end
    function ctx:Touch(root) self.Trigger.Touched:Fire(root) end
    function ctx:Tick() RunService.Heartbeat:Fire(.1) end
    return ctx
end

-- Actual builder geometry, including the pre-existing solid door face.
do
    local ctx=fresh()
    local trigger=ctx.Trigger
    equal(trigger.CanCollide,false,"detector never blocks a runner")
    equal(trigger.CanQuery,false,"detector does not obstruct game raycasts")
    equal(trigger.Transparency,1,"detector adds no visible block")
    equal(trigger.Anchored,true,"detector stays with the authored doorway")
    equal(ctx.World:FindFirstChild("EscapePrompt",true),nil,"no exit button prompt exists")
    local front=trigger.Position.X-trigger.Size.X*.5
    local back=trigger.Position.X+trigger.Size.X*.5
    local door=ctx.Manifest.FinalExit:FindFirstChild("Final Exit Left Leaf")
    local doorFront=door.Position.X-door.Size.X*.5
    -- With a one-stud root half-width the door stops a normal character here.
    local stoppedRoot=doorFront-1
    check(stoppedRoot>=front and stoppedRoot<=back,"solid door stops runner inside trigger")
    local jamb=ctx.Manifest.FinalExit:FindFirstChild("Final Exit Reinforced Jamb")
    check(trigger.Size.Z*.5 < math.abs(jamb.Position.Z-trigger.Position.Z)-jamb.Size.Z*.5,
        "trigger fits between jambs and cannot escape through side walls")
    check(ctx.Room.Y+3 >= trigger.Position.Y-trigger.Size.Y*.5
        and ctx.Room.Y+3 <= trigger.Position.Y+trigger.Size.Y*.5,"normal root height intersects trigger")
end

-- Running into an unlocked exit needs neither a prompt nor any client request.
for _,route in ipairs({"touch","heartbeat"}) do
    local ctx=fresh();local player,character,root=ctx:AddPlayer()
    ctx:Unlock()
    if route=="touch" then ctx:Touch(root) else ctx:Tick() end
    equal(player:GetAttribute("Escaped"),true,route.." marks runner escaped")
    equal(character.PivotCount,1,route.." moves runner to safe waiting room")
    equal(root.AssemblyLinearVelocity,Vector3.zero,route.." clears running momentum")
    equal(root.AssemblyAngularVelocity,Vector3.zero,route.." clears angular momentum")
    equal(player.EscapeNotices,1,route.." announces escape once")
    equal(ctx.Session.SoundCount,1,route.." plays escape cue once")
    ctx:Touch(root);ctx:Tick();escapePlayer(ctx.Session,player)
    equal(character.PivotCount,1,route.." repeated contacts cannot teleport twice")
    equal(player.AttributeWrites.Escaped,1,route.." latches escape once")
end

-- A limb can enter first or contact can happen before unlock. Occupancy recovers.
do
    local ctx=fresh();local player,character,root=ctx:AddPlayer(nil,Vector3.new(-4,0,0))
    ctx:Unlock();ctx:Touch(root)
    equal(player:GetAttribute("Escaped"),nil,"remote limb touch cannot bypass root volume")
    root.Position=ctx.Trigger.Position;ctx:Tick()
    equal(player:GetAttribute("Escaped"),true,"root entering after first limb touch still escapes")
end
do
    local ctx=fresh();local player,_,root=ctx:AddPlayer()
    ctx:Touch(root);ctx:Tick()
    equal(player:GetAttribute("Escaped"),nil,"locked exit refuses touch and occupancy")
    ctx:Unlock();ctx:Tick()
    equal(player:GetAttribute("Escaped"),true,"unlock accepts waiting runner without a new touch")
end

local refusals={
    {"not in round",function(c,p) p:SetAttribute("InRound",false) end},
    {"departed",function(c,p) p.Parent=nil end},
    {"already escaped",function(c,p) p:SetAttribute("Escaped",true) end},
    {"dead",function(c,p,ch,r,h) h.Health=0 end},
    {"missing character",function(c,p) p.Character=nil end},
    {"removed character",function(c,p,ch) ch.Parent=nil end},
    {"missing humanoid",function(c,p,ch,r,h) h.Parent=nil end},
    {"missing root",function(c,p,ch,r) r.Parent=nil end},
    {"wrong level",function() workspace:SetAttribute("SelectedLevel",2) end},
    {"inactive round",function() workspace:SetAttribute("RoundActive",false) end},
    {"stale session",function() activeSession={} end},
    {"replaced generation",function(c) c.World:SetAttribute("Level3_Generation",8) end},
    {"removed world",function(c) c.World.Parent=nil end},
    {"removed trigger",function(c) c.Trigger.Parent=nil end},
    {"foreign trigger",function(c) c.Trigger.Parent=workspace end},
    {"disabled trigger",function(c) c.Trigger.CanTouch=false end},
}
for _,case in ipairs(refusals) do
    local ctx=fresh();local p,ch,r,h=ctx:AddPlayer();ctx:Unlock()
    case[2](ctx,p,ch,r,h)
    escapePlayer(ctx.Session,p)
    equal(ch.PivotCount,nil,case[1].." cannot teleport")
    equal(ctx.Session.EscapeOrdinal,0,case[1].." cannot count as an escape")
    equal(ctx.Session.SoundCount,0,case[1].." cannot play escape cue")
    -- Restore the original session only so its actual Stop cleans test listeners.
    activeSession=ctx.Session
end
for _,position in ipairs({Vector3.new(-1.501,0,0),Vector3.new(1.501,0,0),
    Vector3.new(0,-5.001,0),Vector3.new(0,5.001,0),Vector3.new(0,0,-4.751),
    Vector3.new(0,0,4.751),Vector3.new(100,0,0),Vector3.new(0/0,0,0)}) do
    local ctx=fresh();local p,ch,r=ctx:AddPlayer(nil,position);ctx:Unlock()
    ctx:Touch(r);ctx:Tick()
    equal(ch.PivotCount,nil,"outside or non-finite root cannot escape")
end
do
    local ctx=fresh();ctx.Trigger.CFrame.Yaw=math.pi/2
    local p,_,r=ctx:AddPlayer(nil,Vector3.new(0,0,4.5));ctx:Unlock();ctx:Touch(r)
    equal(p:GetAttribute("Escaped"),true,"containment uses trigger orientation")
end
do
    local ctx=fresh();local first=ctx:AddPlayer("First",Vector3.new(0,0,-2))
    local second=ctx:AddPlayer("Second",Vector3.new(0,0,2));ctx:Unlock();ctx:Tick()
    equal(first:GetAttribute("Escaped"),true,"first teammate escapes independently")
    equal(second:GetAttribute("Escaped"),true,"second teammate escapes independently")
    equal(ctx.Session.EscapeOrdinal,2,"both teammates are counted once")
    check((first.Character.LastPivot.Position-second.Character.LastPivot.Position).Magnitude>0,
        "teammates use distinct waiting-room slots")
end
do
    local ctx=fresh();local player,character,root=ctx:AddPlayer();ctx:Unlock()
    ObjectiveController.Stop()
    equal(ctx.Trigger.CanTouch,false,"Stop disables the trigger")
    equal(ctx.Trigger.Touched.Count(),0,"Stop disconnects touch listener")
    equal(RunService.Heartbeat.Count(),0,"Stop disconnects occupancy heartbeat")
    equal(#ctx.Session.Connections,0,"Stop clears session-owned connections")
    ctx:Touch(root);ctx:Tick();escapePlayer(ctx.Session,player)
    equal(character.PivotCount,nil,"late touch/poll/callback cannot revive stopped exit")
end
print(string.format("Level 3 run-in exit: %d checks passed (actual builder, authority, touch, polling, cleanup)",checks))
'''


def main():
    binary = os.environ.get("LUAU_BIN") or shutil.which("luau")
    if not binary:
        raise SystemExit("Set LUAU_BIN or put luau on PATH; no tests executed.")
    objective = (SYSTEMS / "Level 3 Objective Controller.ModuleScript.lua").read_text(encoding="utf-8")
    builder = (SYSTEMS / "Level 3 World Builder.ModuleScript.lua").read_text(encoding="utf-8")
    start = section(objective, "function ObjectiveController.Start(", "function ObjectiveController.Stop()")
    sections = {
        "__PART_HELPERS__": section(builder, "local function part(", "local function texture("),
        "__EXIT_BUILDER__": section(builder, "local function makeExitSet(", "local function makeMallManagerSpawn("),
        "__DISCONNECT_HELPERS__": section(objective, "local function disconnect(", "local function playTween("),
        "__PLAYER_GUARDS__": section(objective, "local function liveSession(", "local function updateFinalHallChase("),
        "__UNLOCK_EXIT__": section(objective, "unlockExit = function(", "local function collectModule("),
        "__ESCAPE_PLAYER__": section(objective, "local function escapePlayer(", "local function validateManifest("),
        "__STOP_CONTROLLER__": section(objective, "function ObjectiveController.Stop()", "-- Studio-only deterministic hooks"),
        "__HEARTBEAT_HANDLER__": section(start, "\ttable.insert(session.Connections, RunService.Heartbeat:Connect(", "\n\tsession.State:SetAttribute(\"Level3_FinalHallEligibleCount\""),
        "__TOUCH_HANDLER__": section(start, "\tlocal escapeTrigger = manifest.EscapeTrigger", "\n\tsession.State:SetAttribute(\"Level3_CompletionSongStartServerTime\""),
    }
    source = HARNESS
    for marker, content in sections.items():
        source = source.replace(marker, content)
    with tempfile.TemporaryDirectory(prefix="level3-run-in-exit-") as directory:
        path = Path(directory) / "exit_test.luau"
        path.write_text(source, encoding="utf-8")
        subprocess.run([binary, str(path)], check=True, timeout=20)


if __name__ == "__main__":
    main()
