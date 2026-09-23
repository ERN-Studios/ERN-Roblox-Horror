"""Execute the entire First Entry Guide LocalScript in offline Luau.

Fakes only this script's engine boundary: the lobby's Level 1 bay with its four
launch pads, the two profile attributes ZyntraMonetization publishes, a
PathfindingService with a scripted waypoint list, Heartbeat, and the RoundStatus
remote. Tests run the real source; nothing is reimplemented here. No Studio.
Set LUAU_BIN to an official Luau interpreter.
"""

import os
from pathlib import Path
import shutil
import subprocess
import tempfile

ROOT = Path(__file__).resolve().parents[2]
SOURCE = ROOT / "StarterPlayer/StarterPlayerScripts/First Entry Guide.LocalScript.lua"
UISTYLE = ROOT / "ReplicatedStorage/UIStyle.ModuleScript.lua"

HARNESS = r'''
local checks=0
local function check(value,message) assert(value,message); checks+=1 end
local function signal()
    local listeners={}
    return {
        Connect=function(_,fn)
            local entry={fn=fn}
            table.insert(listeners,entry)
            return {Disconnect=function()
                for index,item in listeners do
                    if item==entry then table.remove(listeners,index) return end
                end
            end}
        end,
        Fire=function(_,...)
            local snapshot={}
            for index,item in listeners do snapshot[index]=item end
            for _,item in snapshot do item.fn(...) end
        end,
    }
end

-- Instances: one flat registry, parenthood is just a field. Enough for a script
-- that only walks down from workspace and destroys one subtree.
local ALL={}
local nodeMethods={}
local function node(class,name,parent)
    local value=setmetatable({ClassName=class,Name=name,Parent=parent,Attributes={},Signals={}},
        {__index=nodeMethods})
    table.insert(ALL,value)
    return value
end
function nodeMethods:GetChildren()
    local result={}
    for _,candidate in ALL do if candidate.Parent==self then table.insert(result,candidate) end end
    return result
end
function nodeMethods:FindFirstChild(name)
    for _,candidate in ALL do
        if candidate.Parent==self and candidate.Name==name then return candidate end
    end
end
function nodeMethods:FindFirstChildOfClass(class)
    for _,candidate in ALL do
        if candidate.Parent==self and candidate.ClassName==class then return candidate end
    end
end
function nodeMethods:WaitForChild(name) return assert(self:FindFirstChild(name),name) end
function nodeMethods:IsA(class)
    return class==self.ClassName or (class=="BasePart" and self.ClassName=="Part")
end
function nodeMethods:GetAttribute(key) return self.Attributes[key] end
function nodeMethods:SetAttribute(key,value)
    self.Attributes[key]=value
    if self.Signals[key] then self.Signals[key]:Fire() end
end
function nodeMethods:GetAttributeChangedSignal(key)
    self.Signals[key]=self.Signals[key] or signal()
    return self.Signals[key]
end
function nodeMethods:Destroy()
    self.Parent=nil
    for _,candidate in ALL do if candidate.Parent==self then candidate:Destroy() end end
end

local Vector3={}
local vectorMeta={}
function Vector3.new(x,y,z) return setmetatable({Kind="Vector3",X=x,Y=y,Z=z},vectorMeta) end
vectorMeta.__add=function(a,b) return Vector3.new(a.X+b.X,a.Y+b.Y,a.Z+b.Z) end
vectorMeta.__sub=function(a,b) return Vector3.new(a.X-b.X,a.Y-b.Y,a.Z-b.Z) end
vectorMeta.__index=function(a,key)
    if key=="Magnitude" then return math.sqrt(a.X*a.X+a.Y*a.Y+a.Z*a.Z) end
end
local Color3={fromRGB=function(r,g,b) return {Kind="Color3",R=r,G=g,B=b} end}
local ColorSequence={new=function(value) return {Kind="ColorSequence",Value=value} end}
local NumberSequence={new=function(value) return {Kind="NumberSequence",Value=value} end}
local UDim2={
    new=function(sx,ox,sy,oy) return {Kind="UDim2",SX=sx,OX=ox,SY=sy,OY=oy} end,
    fromOffset=function(x,y) return {Kind="UDim2",SX=0,OX=x,SY=0,OY=y} end,
    fromScale=function(x,y) return {Kind="UDim2",SX=x,OX=0,SY=y,OY=0} end,
}
local UDim={new=function(scale,offset) return {Kind="UDim",S=scale,O=offset} end}
local Enum={Font={GothamBold="GothamBold",GothamMedium="GothamMedium",Code="Code"},
    ApplyStrokeMode={Border="Border",Contextual="Contextual"},
    PathStatus={Success="Success",NoPath="NoPath"}}
local Instance={new=function(class) return node(class,class,nil) end}

-- UI_STYLE_20260915: the guide's marker now wears the shared card chrome, so
-- the REAL module is loaded here rather than stubbed -- a token that stops
-- existing has to fail this suite, not silently draw nothing.
local UIStyle=(function()
--[[UISTYLE_SOURCE]]
end)()

local PAD_OFFSETS={Vector3.new(-9,.18,-13.2),Vector3.new(9,.18,-13.2),
    Vector3.new(-9,.18,13.2),Vector3.new(9,.18,13.2)}

local function context()
    local ctx={Now=100,Computes=0,PathsCreated=0,PathStatus="Success"}
    ctx.Workspace=node("Workspace","Workspace")
    ctx.Script=node("LocalScript","First Entry Guide")
    ctx.Script.Destroying=signal()
    ctx.Heartbeat=signal()

    -- Lobby exactly as TunnelLobbyBuilder builds it: bay centre (-63,30,-840),
    -- four pads at centre + (+/-9, .18, +/-13.2), circular detectors r=7.41.
    local lobby=node("Model","ServerLobby",ctx.Workspace)
    local rooms=node("Folder","LevelQueueRooms",lobby)
    ctx.Room=node("Model","Level1QueueRoom",rooms)
    ctx.Room:SetAttribute("LevelNumber",1)
    ctx.Room:SetAttribute("LevelEnabled",true)
    ctx.Room:SetAttribute("CircularBayDiameter",56)
    ctx.Pads={}
    for index,offset in PAD_OFFSETS do
        local pad=node("Part","LaunchZone"..index,ctx.Room)
        pad.Position=Vector3.new(-63,30,-840)+offset
        pad:SetAttribute("QueueDetectorShape","Circle")
        pad:SetAttribute("QueueRadius",7.41)
        ctx.Pads[index]=pad
    end
    -- A Level 2 pad the guide must never pick, in its own bay.
    local otherRoom=node("Model","Level2QueueRoom",rooms)
    otherRoom:SetAttribute("LevelEnabled",true)
    local otherPad=node("Part","LaunchZone5",otherRoom)
    otherPad.Position=Vector3.new(63,30,-853.2)
    otherPad:SetAttribute("QueueRadius",7.41)

    ctx.Player=node("Player","Player")
    -- ZyntraMonetization publishes ZyntraFirstLogin strictly before ProfileLoaded.
    ctx.Player:SetAttribute("ZyntraFirstLogin",true)
    ctx.Player:SetAttribute("ZyntraProfileLoaded",true)
    function ctx:NewCharacter()
        local character=node("Model","Character",self.Workspace)
        local root=node("Part","HumanoidRootPart",character)
        root.Position=Vector3.new(0,30.4,-860)   -- the lobby spawn
        self.Player.Character=character
        self.Root=root
    end
    ctx:NewCharacter()

    local storage=node("ReplicatedStorage","ReplicatedStorage")
    node("ModuleScript","UIStyle",storage)
    local remotes=node("Folder","Remotes",storage)
    ctx.Remote=node("RemoteEvent","RoundStatus",remotes)
    ctx.Remote.OnClientEvent=signal()

    ctx.Waypoints={Vector3.new(0,30,-860),Vector3.new(-30,30,-855),Vector3.new(-54,30,-853.2)}
    local pathfinding={CreatePath=function(_,agent)
        ctx.PathsCreated+=1
        ctx.Agent=agent
        local path={}
        function path:ComputeAsync(origin,target)
            ctx.Computes+=1
            ctx.LastOrigin,ctx.LastTarget=origin,target
            if ctx.ComputeError then error("no navmesh") end
            self.Status=ctx.PathStatus
        end
        function path:GetWaypoints()
            local result={}
            for _,point in ctx.Waypoints do table.insert(result,{Position=point}) end
            return result
        end
        return path
    end}
    local services={Players={LocalPlayer=ctx.Player},ReplicatedStorage=storage,
        PathfindingService=pathfinding,RunService={Heartbeat=ctx.Heartbeat}}
    ctx.Game={GetService=function(_,name) return assert(services[name],name) end}
    function ctx:Step(delta)
        delta=delta or .03
        self.Now+=delta
        self.Heartbeat:Fire(delta)
    end
    function ctx:Guide() return self.Workspace:FindFirstChild("FirstEntryGuide") end
    function ctx:Kids(class)
        local guide,result=self:Guide(),{}
        if not guide then return result end
        for _,child in guide:GetChildren() do
            if child.ClassName==class then table.insert(result,child) end
        end
        return result
    end
    function ctx:EnabledBeams()
        local total=0
        for _,beam in self:Kids("Beam") do if beam.Enabled then total+=1 end end
        return total
    end
    return ctx
end

local function boot(ctx)
    local game,workspace,script=ctx.Game,ctx.Workspace,ctx.Script
    local task={spawn=function(fn,...) fn(...) end}
    local os={clock=function() return ctx.Now end}
    local require=function(module) return assert(module.Name=="UIStyle" and UIStyle,module.Name) end
'''

TESTS = r'''
end
local function fresh(setup)
    local ctx=context()
    if setup then setup(ctx) end
    boot(ctx)
    return ctx
end

do  -- (1) returning player: the server says this is not a first login
    local ctx=fresh(function(c) c.Player:SetAttribute("ZyntraFirstLogin",false) end)
    ctx:Step(.1)
    check(ctx:Guide()==nil,"a returning player never gets the guide")
end
do  -- (1b) a load that failed to commit publishes nothing at all
    local ctx=fresh(function(c) c.Player:SetAttribute("ZyntraFirstLogin",nil) end)
    ctx:Step(.1)
    check(ctx:Guide()==nil,"a missing first-login attribute shows nothing")
end
do  -- (2) first login, and a later attribute change must not kill it
    local ctx=fresh()
    ctx:Step(.1)
    check(ctx:Guide()~=nil,"a brand-new profile gets the guide")
    local beams=ctx:EnabledBeams()
    ctx.Player:SetAttribute("ZyntraFirstLogin",false)
    ctx:Step(.1)
    check(ctx:Guide()~=nil and ctx:EnabledBeams()==beams,
        "the latch is taken at load: a later flip does not tear the guide down")
end
do  -- (2b) the latch is one-shot the other way too
    local ctx=fresh(function(c) c.Player:SetAttribute("ZyntraFirstLogin",false) end)
    ctx:Step(.1)
    ctx.Player:SetAttribute("ZyntraFirstLogin",true)
    ctx.Player:SetAttribute("ZyntraProfileLoaded",true)
    ctx:Step(.1)
    check(ctx:Guide()==nil,"flipping first-login true after the latch starts nothing")
end
do  -- (3) no profile, no guide -- and the deferred load still starts it
    local ctx=fresh(function(c) c.Player:SetAttribute("ZyntraProfileLoaded",false) end)
    ctx:Step(.1)
    check(ctx:Guide()==nil,"an unloaded profile shows nothing")
    ctx.Player:SetAttribute("ZyntraProfileLoaded",true)
    ctx:Step(.1)
    check(ctx:Guide()~=nil,"a profile that loads late still starts the guide")
end
do  -- (4) reserved round servers have no lobby to guide anyone through
    local ctx=fresh(function(c) c.Workspace:SetAttribute("ReservedRoundServer",true) end)
    ctx:Step(.1)
    check(ctx:Guide()==nil,"no guide on a reserved round server")
end
do  -- (4b) a player already in a round
    local ctx=fresh(function(c) c.Player:SetAttribute("InRound",true) end)
    ctx:Step(.1)
    check(ctx:Guide()==nil,"no guide for a player already in a round")
end
do  -- (5) the chain is the scripted path, pooled and repositioned
    local ctx=fresh()
    ctx:Step(.1)
    check(ctx.Computes==1 and ctx.PathsCreated==1,"one path object, one compute on the first frame")
    check(ctx.Agent.AgentRadius==2 and ctx.Agent.AgentHeight==5 and ctx.Agent.AgentCanJump==false,
        "agent params match a walking player")
    -- LaunchZone2 (-54,30.18,-853.2) is the nearest of the four Level 1 pads.
    check(ctx.LastTarget.X==-54 and ctx.LastTarget.Z==-853.2,"targets the nearest Level 1 pad")
    local attachments,beams=ctx:Kids("Attachment"),ctx:Kids("Beam")
    check(#attachments==3 and #beams==2,"three waypoints become three attachments and two beams")
    check(attachments[1].WorldPosition.X==0 and attachments[1].WorldPosition.Y==30.35,
        "waypoints hover .35 studs above the floor")
    check(beams[1].Attachment0==attachments[1] and beams[1].Attachment1==attachments[2]
        and ctx:EnabledBeams()==2,"beams chain consecutive waypoints")
    check(#ctx:Kids("BillboardGui")==1,"one marker billboard")

    ctx.Root.Position=Vector3.new(-20,30.4,-858)
    ctx:Step(.1)
    check(ctx.Computes==1,"recompute stays behind the .75s interval")
    ctx.Waypoints={Vector3.new(-20,30,-858),Vector3.new(-35,30,-856),
        Vector3.new(-48,30,-854),Vector3.new(-54,30,-853.2)}
    ctx:Step(.7)
    check(ctx.Computes==2,"moving further than three studs recomputes")
    attachments,beams=ctx:Kids("Attachment"),ctx:Kids("Beam")
    check(#attachments==4 and #beams==3 and attachments[1].WorldPosition.X==-20,
        "the new path repositions attachment one and extends the pool")
    ctx.Root.Position=Vector3.new(-21,30.4,-858)
    ctx:Step(1)
    check(ctx.Computes==2,"a one-stud shuffle does not recompute")
    ctx.Waypoints={Vector3.new(-40,30,-856),Vector3.new(-54,30,-853.2)}
    ctx.Root.Position=Vector3.new(-40,30.4,-856)
    ctx:Step(1)
    check(#ctx:Kids("Attachment")==4 and #ctx:Kids("Beam")==3 and ctx:EnabledBeams()==1,
        "a shorter path reuses the pool and leaves the spare beams off")
end
do  -- failed pathfinding falls back to a straight line and retries
    local ctx=fresh(function(c) c.PathStatus="NoPath" end)
    ctx:Step(.1)
    local attachments=ctx:Kids("Attachment")
    check(#attachments==2 and attachments[2].WorldPosition.X==-54,
        "a failed path still draws a straight line to the pad")
    ctx:Step(1)
    check(ctx.Computes==2,"a failed path retries without waiting for the player to move")
    ctx.ComputeError=true
    ctx:Step(1)
    check(ctx.Computes==3 and ctx:Guide()~=nil,"a throwing ComputeAsync does not kill the guide")
end
do  -- no root: pause, then re-bind to the respawned character
    local ctx=fresh()
    ctx:Step(.1)
    ctx.Player.Character=nil
    ctx:Step(.1)
    check(ctx:Guide()~=nil and ctx:EnabledBeams()==0,"a dead player pauses the guide")
    ctx:NewCharacter()
    ctx:Step(.1)
    check(ctx:EnabledBeams()>0,"respawning in the lobby re-binds instead of ending")
end
do  -- (6) arriving on a pad ends it for good
    local ctx=fresh()
    ctx:Step(.1)
    ctx.Root.Position=Vector3.new(-54+7,30.4,-853.2)   -- inside r=7.41
    ctx:Step(.1)
    check(ctx:Guide()==nil,"standing on a Level 1 pad ends the guide")
    -- (8) nothing comes back afterwards
    ctx.Root.Position=Vector3.new(0,30.4,-860)
    ctx.Player:SetAttribute("ZyntraProfileLoaded",false)
    ctx.Player:SetAttribute("ZyntraProfileLoaded",true)
    ctx:Step(1)
    check(ctx:Guide()==nil and ctx.Computes==1,"nothing is recreated after the guide ends")
end
do  -- (7) queue and load events end it
    for _,event in {"queuehost","queueconfigured","lobbycountdown","loadinggame"} do
        local ctx=fresh()
        ctx:Step(.1)
        ctx.Remote.OnClientEvent:Fire(event)
        check(ctx:Guide()==nil,event.." ends the guide")
        ctx:Step(1)
        check(ctx:Guide()==nil,"still gone one second after "..event)
    end
    local ctx=fresh()
    ctx:Step(.1)
    ctx.Remote.OnClientEvent:Fire("lobbycancel")
    check(ctx:Guide()~=nil,"an unrelated round status does not end the guide")
    ctx.Player:SetAttribute("InRound",true)
    check(ctx:Guide()==nil,"entering a round ends the guide")
end
do  -- script teardown cleans the world up
    local ctx=fresh()
    ctx:Step(.1)
    ctx.Script.Destroying:Fire()
    check(ctx:Guide()==nil,"script teardown destroys the guide")
end
print("First Entry Guide: "..checks.." checks passed (entire actual script, offline Luau)")
'''


def main():
    binary = os.environ.get("LUAU_BIN") or shutil.which("luau")
    if not binary:
        raise SystemExit("Set LUAU_BIN; no tests executed.")
    with tempfile.TemporaryDirectory(prefix="first-entry-guide-") as directory:
        path = Path(directory) / "guide_test.luau"
        harness = HARNESS.replace("--[[UISTYLE_SOURCE]]",
                                  UISTYLE.read_text(encoding="utf-8"))
        path.write_text(harness + SOURCE.read_text(encoding="utf-8") + TESTS, encoding="utf-8")
        subprocess.run([binary, str(path)], check=True, timeout=20)


if __name__ == "__main__":
    main()
