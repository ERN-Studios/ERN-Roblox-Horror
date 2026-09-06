"""Execute the entire Round Entry Client in offline Luau with a small scheduler.

Mocks only this script's engine boundary: server clock, streamed ground,
PreloadAsync completion, readiness attributes and the remote event. Tests use
the real source, including spawned tasks; no copied readiness implementation.
No network/Studio calls. Set LUAU_BIN to an official Luau interpreter.
"""

import os
from pathlib import Path
import shutil
import subprocess
import tempfile

ROOT = Path(__file__).resolve().parents[2]
SOURCE = ROOT / "StarterPlayer/StarterPlayerScripts/Round Entry Client.LocalScript.lua"

HARNESS = r'''
local checks=0
local function check(value, message) assert(value,message); checks+=1 end
local function signal()
    local listeners={}
    return {Connect=function(_,fn) table.insert(listeners,fn); return {Disconnect=function() end} end,
        Fire=function(_,...) for _,fn in listeners do fn(...) end end}
end
local nodeMethods={}
local function node(class,name,parent)
    local value=setmetatable({Kind="Instance",ClassName=class,Name=name,Parent=parent,Children={},Attributes={}}, {__index=nodeMethods})
    if parent then table.insert(parent.Children,value) end
    return value
end
function nodeMethods:IsA(class)
    return class==self.ClassName or (class=="BasePart" and (self.ClassName=="Part" or self.ClassName=="MeshPart"))
end
function nodeMethods:FindFirstChild(name)
    for _,child in self.Children do if child.Name==name then return child end end
end
function nodeMethods:WaitForChild(name) return assert(self:FindFirstChild(name),name) end
function nodeMethods:FindFirstChildOfClass(class)
    for _,child in self.Children do if child.ClassName==class then return child end end
end
function nodeMethods:GetDescendants()
    local result={}
    local function collect(parent)
        for _,child in parent.Children do table.insert(result,child); collect(child) end
    end
    collect(self); return result
end
function nodeMethods:IsDescendantOf(parent)
    local current=self.Parent
    while current do if current==parent then return true end; current=current.Parent end
    return false
end
function nodeMethods:GetAttribute(key) return self.Attributes[key] end
function nodeMethods:SetAttribute(key,value) self.Attributes[key]=value end
local Vector3={}
local vectorMeta={}
function Vector3.new(x,y,z) return setmetatable({Kind="Vector3",X=x,Y=y,Z=z},vectorMeta) end
vectorMeta.__add=function(a,b) return Vector3.new(a.X+b.X,a.Y+b.Y,a.Z+b.Z) end
vectorMeta.__sub=function(a,b) return Vector3.new(a.X-b.X,a.Y-b.Y,a.Z-b.Z) end
vectorMeta.__mul=function(a,b) return Vector3.new(a.X*b,a.Y*b,a.Z*b) end
vectorMeta.__index=function(a,key) if key=="Magnitude" then return math.sqrt(a.X*a.X+a.Y*a.Y+a.Z*a.Z) end end
Vector3.yAxis=Vector3.new(0,1,0)
local function typeof(value) return type(value)=="table" and value.Kind or type(value) end
local Enum={RaycastFilterType={Include="Include"},AssetFetchStatus={Success="Success",Failure="Failure"}}
local RaycastParams={new=function() return {} end}
local function context()
    local ctx={Now=100,Queue={},Acks={},Loaded=true,AppearanceReady=true,Studio=true,
        StreamDelay=0,AssetsDelay=0,StreamCalls=0,PreloadCalls=0,Preloaded={}}
    ctx.Workspace=node("Workspace","Workspace")
    function ctx.Workspace:GetServerTimeNow() return ctx.Now end
    ctx.Workspace:SetAttribute("SelectedLevel",2)
    ctx.World=node("Model","Level 2 Generated World",ctx.Workspace)
    ctx.Floor=node("Part","EntryFloor",ctx.World); ctx.Floor.CanCollide=true; ctx.Floor.Position=Vector3.new(0,0,0)
    ctx.Hit=ctx.Floor; ctx.Normal=Vector3.yAxis
    function ctx.Workspace:Raycast(origin,direction,params)
        ctx.LastRay=params
        local hit=ctx.Hit
        if not hit then return nil end
        -- Only the flat test surfaces exist. Keep the actual ray's spatial
        -- bounds so a whitelisted but distant compatibility pad cannot pass.
        if hit.Position and (math.abs(hit.Position.X-origin.X)>.5 or math.abs(hit.Position.Z-origin.Z)>.5
            or hit.Position.Y>origin.Y or hit.Position.Y<origin.Y+direction.Y) then return nil end
        for _,allowed in params.FilterDescendantsInstances do
            if hit==allowed or hit:IsDescendantOf(allowed) then
                return {Instance=hit,Normal=ctx.Normal}
            end
        end
    end
    ctx.Player=node("Player","Player")
    ctx.Player.CharacterAdded=signal(); ctx.Player.CharacterAppearanceLoaded=signal()
    function ctx:NewCharacter()
        local character=node("Model","Character",self.Workspace)
        local root=node("Part","HumanoidRootPart",character); root.Position=Vector3.new(0,5,0)
        local hum=node("Humanoid","Humanoid",character); hum.Health=100
        node("MeshPart","BodyMesh",character)
        return character,root,hum
    end
    ctx.Player.Character,ctx.Root,ctx.Humanoid=ctx:NewCharacter()
    ctx.Player:SetAttribute("RoundEntryUIReady",true)
    ctx.Player:SetAttribute("RoundEntryControlsReady",true)
    function ctx.Player:HasAppearanceLoaded() return ctx.AppearanceReady end
    ctx.Remote=node("RemoteEvent","RoundStatus"); ctx.Remote.OnClientEvent=signal()
    function ctx.Remote:FireServer(event,payload) table.insert(ctx.Acks,{Event=event,Payload=payload,Time=ctx.Now}) end
    local storage=node("ReplicatedStorage","ReplicatedStorage")
    local remotes=node("Folder","Remotes",storage)
    table.insert(remotes.Children,ctx.Remote)
    ctx.Task={}
    function ctx.Task.spawn(fn) table.insert(ctx.Queue,{Thread=coroutine.create(fn),At=ctx.Now}) end
    function ctx.Task.wait(delay) return coroutine.yield(delay or .03) end
    function ctx.Player:RequestStreamAroundAsync()
        ctx.StreamCalls+=1
        if ctx.StreamDelay>0 then ctx.Task.wait(ctx.StreamDelay) end
        if ctx.StreamError then error("streaming failed") end
    end
    local content={}
    function content:PreloadAsync(assets,callback)
        ctx.PreloadCalls+=1; table.insert(ctx.Preloaded,assets)
        if ctx.AssetsDelay>0 then ctx.Task.wait(ctx.AssetsDelay) end
        if ctx.PreloadError then error("preload failed") end
        for _ in assets do callback("asset",ctx.RefuseAssets and "Failure" or "Success") end
    end
    local services={Players={LocalPlayer=ctx.Player},ReplicatedStorage=storage,ContentProvider=content,
        RunService={IsStudio=function() return ctx.Studio end}}
    ctx.Game={GetService=function(_,name) return assert(services[name],name) end,
        IsLoaded=function() return ctx.Loaded end}
    function ctx:Advance(delta)
        local target=self.Now+delta
        local steps=0
        while true do
            local index,first=nil,nil
            for i,task in self.Queue do if not first or task.At<first.At then index,first=i,task end end
            if not first or first.At>target then break end
            table.remove(self.Queue,index); self.Now=first.At; steps+=1
            assert(steps<10000,"scheduler runaway")
            local ok,delay=coroutine.resume(first.Thread)
            assert(ok,delay)
            if coroutine.status(first.Thread)~="dead" then
                first.At=self.Now+(delay or .03); table.insert(self.Queue,first)
            end
        end
        self.Now=target
    end
    function ctx:Prepare(overrides)
        local payload={Token="attempt-1",Level=2,Character=self.Player.Character,
            Position=Vector3.new(0,5,0),Deadline=self.Now+5}
        for key,value in overrides or {} do payload[key]=value end
        self.Remote.OnClientEvent:Fire("entryprepare",payload)
        return payload
    end
    return ctx
end
local function boot(ctx)
    local game,workspace,task=ctx.Game,ctx.Workspace,ctx.Task
    local os={clock=function() return ctx.Now end}
'''

TESTS = r'''
end
local function fresh() local ctx=context(); boot(ctx); return ctx end
do
    local ctx=fresh(); ctx:Prepare(); ctx:Advance(.29)
    check(#ctx.Acks==1,"first stable readiness sends one initial ack")
    local ack=ctx.Acks[1]
    check(ack.Event=="entryready" and ack.Payload.Token=="attempt-1" and ack.Payload.Level==2
        and ack.Payload.Character==ctx.Player.Character,"ack binds matching token/level/body")
    check(ctx.Player:GetAttribute("RoundEntryReadyToken")=="attempt-1","local token follows real readiness")
    check(ctx.PreloadCalls==1 and #ctx.Preloaded[1]>=1,"character meshes were actually offered to preload")
    check(ctx.LastRay.FilterType=="Include" and ctx.LastRay.IgnoreWater and ctx.LastRay.RespectCanCollide,
        "ground query uses whitelist, ignores water and respects collision")
    ctx:Advance(1)
    for i=2,#ctx.Acks do check(ctx.Acks[i].Time-ctx.Acks[i-1].Time>=.5,"readiness heartbeat bounded to 2Hz") end
end
for _,level in {1,3} do
    local ctx=fresh(); ctx.World.Name=level==1 and "Maze" or "Level 3 Generated World"
    ctx.Workspace:SetAttribute("SelectedLevel",level); ctx:Prepare({Level=level}); ctx:Advance(.3)
    check(#ctx.Acks==1,"correct level "..level.." entry ground is allowed")
end
for _,position in {Vector3.new(0,0,0),Vector3.new(100,0,0),Vector3.new(0,-30,0)} do
    local ctx=fresh(); local pad=node("Part","ElevatorSpawn",ctx.Workspace)
    pad.CanCollide=true; pad.Position=position; ctx.Hit=pad
    ctx:Prepare(); ctx:Advance(.3)
    check((#ctx.Acks==1)==(position.X==0 and position.Y==0),"compatibility pad must actually intersect entry ray")
end
-- A real Studio L2->L3 continuation held the rig with its sloped bore floor
-- 14.923 studs below the ray origin. Flat-pad depth must not time out that ride.
for _,case in {{Level=3,Depth=14.923,Ready=true},{Level=3,Depth=20.1,Ready=false},
    {Level=2,Depth=14.923,Ready=false}} do
    local ctx=fresh()
    ctx.World.Name="Level "..case.Level.." Generated World"
    ctx.Workspace:SetAttribute("SelectedLevel",case.Level)
    ctx.Floor.Position=Vector3.new(0,ctx.Root.Position.Y+2-case.Depth,0)
    ctx:Prepare({Level=case.Level}); ctx:Advance(.3)
    check((#ctx.Acks==1)==case.Ready,"sloped bore ground is in range; distant floor remains rejected")
end
for _,gate in {"Loaded","UI","Controls","Assets","Level","Ground","Collidable","Normal","Distance","Dead","Parent"} do
    local ctx=fresh()
    if gate=="Loaded" then ctx.Loaded=false
    elseif gate=="UI" then ctx.Player:SetAttribute("RoundEntryUIReady",false)
    elseif gate=="Controls" then ctx.Player:SetAttribute("RoundEntryControlsReady",false)
    elseif gate=="Assets" then ctx.AssetsDelay=2
    elseif gate=="Level" then ctx.Workspace:SetAttribute("SelectedLevel",1)
    elseif gate=="Ground" then ctx.Hit=node("Part","LobbyFloor",ctx.Workspace); ctx.Hit.CanCollide=true
    elseif gate=="Collidable" then ctx.Floor.CanCollide=false
    elseif gate=="Normal" then ctx.Normal=Vector3.new(0,0,1)
    elseif gate=="Distance" then ctx.Root.Position=Vector3.new(50,5,0)
    elseif gate=="Dead" then ctx.Humanoid.Health=0
    elseif gate=="Parent" then ctx.Player.Character.Parent=nil end
    ctx:Prepare(); ctx:Advance(1)
    check(#ctx.Acks==0,"no acknowledgement before "..gate.." readiness")
end
for _,failure in {"RefuseAssets","PreloadError"} do
    local ctx=fresh(); ctx[failure]=true; ctx:Prepare(); ctx:Advance(1)
    check(#ctx.Acks==0,"failed assets cannot claim readiness: "..failure)
end
do
    local ctx=fresh(); ctx.StreamError=true; ctx:Prepare(); ctx:Advance(.3)
    check(#ctx.Acks==1,"stream call failure does not veto independently observed real readiness")
end
do
    local ctx=fresh(); ctx.AssetsDelay=.7
    local original=ctx:Prepare({Deadline=101}); ctx:Advance(.2)
    ctx:Prepare({Deadline=110}); ctx:Advance(.8)
    check(ctx.PreloadCalls==1 and ctx.StreamCalls==1,"duplicate prepare doesn't restart expensive work")
    ctx:Advance(.3)
    check(ctx.Player:GetAttribute("RoundEntryReadyToken")==nil,"duplicate prepare cannot extend original deadline")
end
do
    local ctx=fresh(); ctx.AssetsDelay=.6; ctx:Prepare(); ctx:Advance(.2)
    ctx:Prepare({Token="attempt-2"}); ctx:Advance(1)
    check(#ctx.Acks>0,"replacement token can become ready")
    for _,ack in ctx.Acks do check(ack.Payload.Token=="attempt-2","old task cannot acknowledge replacement token") end
end
do
    local ctx=fresh(); ctx.AssetsDelay=.5; local old=ctx:Prepare(); ctx:Advance(.1)
    ctx.Player.Character,ctx.Root,ctx.Humanoid=ctx:NewCharacter()
    ctx.Player.CharacterAdded:Fire(ctx.Player.Character); ctx:Advance(1)
    check(#ctx.Acks==0,"old character completion is canceled")
    ctx:Prepare({Token="attempt-2"}); ctx:Advance(1)
    check(#ctx.Acks>0 and ctx.Acks[1].Payload.Character~=old.Character,"new body gets its own ack")
end
do
    local ctx=fresh(); ctx:Prepare(); ctx:Advance(.29); local count=#ctx.Acks
    ctx.Hit=nil; ctx:Advance(.8)
    check(#ctx.Acks==count and ctx.Player:GetAttribute("RoundEntryReadyToken")==nil,"lost ground clears token and stops acks")
    ctx.Hit=ctx.Floor; ctx:Advance(.3)
    check(#ctx.Acks>count,"stable ground reacquisition can acknowledge again")
end
for _,event in {"start","loadinggame","entryreleased","entrycancel","loadfailed","lobby"} do
    local ctx=fresh(); ctx:Prepare(); ctx:Advance(.29); local count=#ctx.Acks
    ctx.Remote.OnClientEvent:Fire(event,{Token="attempt-1"}); ctx:Advance(1)
    check(#ctx.Acks==count and ctx.Player:GetAttribute("RoundEntryReadyToken")==nil,event.." stops acks")
end
do
    local ctx=fresh(); ctx.AssetsDelay=.8; ctx:Prepare(); ctx:Advance(.1)
    ctx.Remote.OnClientEvent:Fire("entrycancel",{Token="attempt-1"}); ctx:Advance(1)
    check(#ctx.Acks==0,"late preload completion after cancellation cannot revive request")
end
do
    local ctx=fresh(); ctx:Prepare(); ctx.Remote.OnClientEvent:Fire("entryreleased",{Token="stale"}); ctx:Advance(.29)
    check(#ctx.Acks==1,"stale release cannot cancel current request")
end
for _,studio in {true,false} do
    local ctx=fresh(); ctx.Studio=studio; ctx.Player:SetAttribute("DevHoldEntryReady",true)
    ctx:Prepare(); ctx:Advance(.3)
    check((#ctx.Acks==0)==studio,"DevHoldEntryReady is effective only in Studio")
end
for _,invalid in {
    {Deadline=99},{Deadline=0/0},{Deadline=math.huge},{Token=""},{Token=string.rep("x",129)},
    {Level=1.5},{Level=0/0},{Level=4},{Position=Vector3.new(0/0,5,0)},{Position=Vector3.new(math.huge,5,0)},
} do
    local ctx=fresh(); ctx:Prepare(invalid); ctx:Advance(.3)
    check(ctx.StreamCalls==0 and ctx.PreloadCalls==0 and #ctx.Acks==0,"invalid request rejected before spawning work")
end
do
    local ctx=fresh(); ctx:Prepare({Deadline=100.15}); ctx:Advance(.5)
    check(#ctx.Acks==0 and ctx.Player:GetAttribute("RoundEntryReadyToken")==nil,"deadline expires before insufficient stability")
end
print("Round Entry Client: "..checks.." checks passed (entire actual script, offline Luau)")
'''


def main():
    binary = os.environ.get("LUAU_BIN") or shutil.which("luau")
    if not binary:
        raise SystemExit("Set LUAU_BIN; no tests executed.")
    with tempfile.TemporaryDirectory(prefix="round-entry-client-") as directory:
        path = Path(directory) / "entry_test.luau"
        path.write_text(HARNESS + SOURCE.read_text(encoding="utf-8") + TESTS, encoding="utf-8")
        subprocess.run([binary, str(path)], check=True, timeout=20)


if __name__ == "__main__":
    main()
