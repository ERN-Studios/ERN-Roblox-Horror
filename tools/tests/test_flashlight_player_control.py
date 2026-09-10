"""Exercise actual flashlight input/lifecycle/battery and complete server sync.

Roblox object, input and frame signals are fakes; the production local toggle,
respawn/death hooks, battery heartbeat, teammate renderer and complete server
script run unchanged. Music timing is covered by test_level3_flashlight_timeline.
"""

import os
from pathlib import Path
import shutil
import subprocess
import tempfile

ROOT = Path(__file__).resolve().parents[2]
CLIENT = ROOT / "StarterPlayer/StarterPlayerScripts/FlashlightController.LocalScript.lua"
SERVER = ROOT / "ServerScriptService/FlashlightSync.Script.lua"


def section(source, start, stop):
    begin = source.index(start)
    return source[begin:source.index(stop, begin)]


HOST = r'''
local checks=0
local function check(value,message) checks+=1;assert(value,message) end
local function equal(actual,expected,message)
    check(actual==expected,message..": expected "..tostring(expected)..", got "..tostring(actual))
end
local function signal()
    local entries={}
    return {Connect=function(_,fn)
        local entry={Connected=true,Fn=fn};table.insert(entries,entry)
        function entry:Disconnect() self.Connected=false end;return entry
    end,Fire=function(_,...) for _,e in ipairs(entries) do if e.Connected then e.Fn(...) end end end,
    Count=function() local count=0;for _,e in ipairs(entries) do if e.Connected then count+=1 end end;return count end}
end
local Vector3={};local vm={}
vm.__index=function(v,k)
    if k=="Magnitude" then return math.sqrt(v.X*v.X+v.Y*v.Y+v.Z*v.Z) end
    if k=="Unit" then return v*(1/v.Magnitude) end
end
function Vector3.new(x,y,z) return setmetatable({X=x,Y=y,Z=z},vm) end
vm.__add=function(a,b) return Vector3.new(a.X+b.X,a.Y+b.Y,a.Z+b.Z) end
vm.__sub=function(a,b) return Vector3.new(a.X-b.X,a.Y-b.Y,a.Z-b.Z) end
vm.__mul=function(a,b) return Vector3.new(a.X*b,a.Y*b,a.Z*b) end
local CFrame={}
function CFrame.lookAt(p,target) return {Kind="CFrame",Position=p,LookVector=(target-p).Unit} end
function CFrame.new(x,y,z) return CFrame.lookAt(Vector3.new(x,y,z),Vector3.new(x,y,z-1)) end
local function typeof(v) return type(v)=="table" and v.Kind or type(v) end
local Color3={fromRGB=function(r,g,b) return {R=r,G=g,B=b,Lerp=function(self) return self end} end}
local Enum={NormalId={Front="Front"},KeyCode={F="F",ButtonR1="ButtonR1",G="G"},
    UserInputType={Touch="Touch",MouseButton1="MouseButton1"}}

local function fresh()
    local ctx={Now=100,Sent={},Popups={}}
    local methods={};local Instance={};local nm={}
    nm.__index=function(self,k)
        if methods[k] then return methods[k] end
        if k=="Position" and self.Data.CFrame then return self.Data.CFrame.Position end
        return self.Data[k]
    end
    nm.__newindex=function(self,k,v)
        if k=="Parent" then
            local old=self.Data.Parent
            if old then local at=table.find(old.Children,self);if at then table.remove(old.Children,at) end end
            if v then table.insert(v.Children,self) end
        end
        self.Data[k]=v
    end
    function Instance.new(class)
        return setmetatable({Data={ClassName=class,Name=class,Children={},Attributes={},Signals={},
            Value=false,Enabled=false,CharacterAdded=signal(),Died=signal(),OnServerEvent=signal()}},nm)
    end
    function methods:IsA(class)
        return self.ClassName==class or (class=="Light" and self.ClassName=="SpotLight")
    end
    function methods:GetChildren() return self.Children end
    function methods:FindFirstChild(name)
        for _,child in ipairs(self.Children) do if child.Name==name then return child end end
    end
    function methods:WaitForChild(name) return assert(self:FindFirstChild(name),name) end
    function methods:FindFirstChildOfClass(class)
        for _,child in ipairs(self.Children) do if child:IsA(class) then return child end end
    end
    function methods:Destroy() self.Parent=nil end
    function methods:GetAttribute(name) return self.Attributes[name] end
    function methods:GetAttributeChangedSignal(name)
        if not self.Signals[name] then self.Signals[name]=signal() end;return self.Signals[name]
    end
    function methods:SetAttribute(name,value)
        if self.Attributes[name]~=value then self.Attributes[name]=value;self:GetAttributeChangedSignal(name):Fire() end
    end
    local function node(class,name,parent)
        local obj=Instance.new(class);obj.Name=name;obj.Parent=parent;return obj
    end
    local workspace=node("Workspace","Workspace")
    workspace:SetAttribute("SelectedLevel",3)
    workspace:SetAttribute("Level3FlashlightsSuppressed",true) -- Saved legacy state must be harmless.
    local players=node("Players","Players");players.PlayerAdded=signal();players.PlayerRemoving=signal()
    local player=node("Player","Tester",players);player.UserId=123;player:SetAttribute("InRound",true)
    function players:GetPlayers() return {player} end
    local function character()
        local char=node("Model","Character",workspace)
        local head=node("Part","Head",char);head.CFrame=CFrame.new(10,5,10)
        local hum=node("Humanoid","Humanoid",char);hum.Health=100
        player.Character=char
        return char,hum,head
    end
    character()
    local rs=node("ReplicatedStorage","ReplicatedStorage")
    local serverRemote=node("RemoteEvent","ToggleFlashlight",node("Folder","Remotes",rs))
    node("ModuleScript","FlashlightProfiles",rs)
    local Profiles={Mount={},Mate={},Current=function() return "BASE" end,Apply=function() end}
    local game={GetService=function(_,name) return name=="Players" and players or rs end}
    local require=function() return Profiles end
    local os={clock=function() return ctx.Now end}
    local task={spawn=function(fn,...) fn(...) end,wait=function() end}
    do __SERVER__ end
    local remote={FireServer=function(_,value,payload)
        table.insert(ctx.Sent,{value,payload});serverRemote.OnServerEvent:Fire(player,value,payload)
    end}
    local RunService={Heartbeat=signal(),IsStudio=function() return true end}
    local UIS={InputBegan=signal()}
    local touchFlashButton={InputBegan=signal()}
    local coreLight,spillLight={Enabled=false},{Enabled=false}
    local lens,lightRays={},{{},{},{}}
    local on=false
    local popupGui,popup={},{}
    local function showPopup(text) table.insert(ctx.Popups,text) end
    local BAT_FULL,BAT_EMPTY=Color3.fromRGB(255,255,255),Color3.fromRGB(235,60,50)
    local batBars={}
    __BATTERY_STATE__
    __CLIENT_CONTROL__
    local observer={core={},spill={}}
    local mateBeams={[player.Character]=observer};local lastMateProfile=nil
    __MATE_HEARTBEAT__
    __BATTERY_HEARTBEAT__
    ctx.Player=player;ctx.Workspace=workspace;ctx.Observer=observer
    function ctx:Advance(seconds) self.Now+=seconds end
    function ctx:Tick(dt) self.Now+=dt;RunService.Heartbeat:Fire(dt) end
    function ctx:Key(key,processed) UIS.InputBegan:Fire({KeyCode=key},processed==true) end
    function ctx:Touch() touchFlashButton.InputBegan:Fire({UserInputType=Enum.UserInputType.Touch}) end
    function ctx:Send(value,payload) serverRemote.OnServerEvent:Fire(player,value,payload) end
    function ctx:SetBattery(value) battery=value end
    function ctx:Battery() return battery end
    function ctx:On() return on end
    function ctx:Flag() return player.Character:FindFirstChild("FlashlightOn").Value end
    function ctx:Mount() return workspace:FindFirstChild("ReplicatedFlashlight_123") end
    function ctx:Lights(expected,message)
        equal(on,expected,message.." user choice");equal(coreLight.Enabled,expected,message.." own core")
        equal(spillLight.Enabled,expected,message.." own spill");equal(self:Flag(),expected,message.." replicated flag")
        local mount=self:Mount()
        if mount then
            equal(mount:FindFirstChild("Core").Enabled,expected,message.." replicated core")
            equal(mount:FindFirstChild("Spill").Enabled,expected,message.." replicated spill")
        end
        RunService.Heartbeat:Fire(0)
        equal(observer.core.Enabled,expected,message.." teammate core")
        equal(observer.spill.Enabled,expected,message.." teammate spill")
    end
    function ctx:Respawn()
        local char=character();mateBeams={ [char]=observer };player.CharacterAdded:Fire(char)
    end
    ctx:Advance(.1)
    return ctx
end

do
    local ctx=fresh();ctx:Key("F");ctx:Lights(true,"F under stale true attribute")
    equal(ctx.Workspace:GetAttributeChangedSignal("Level3FlashlightsSuppressed").Count(),0,"no old suppression listeners")
    for _,elapsed in ipairs({145,150,176.035917,176.9,177.035917,180.035917,208.035917,209.9,210.035917,213.235917}) do
        ctx.Workspace:SetAttribute("Level3BlackoutActive",elapsed>=150 and elapsed<210.035917)
        ctx.Workspace:SetAttribute("Level3MallManagerHuntActive",elapsed>=180.035917 and elapsed<210.035917)
        ctx.Workspace:SetAttribute("Level3FlashlightsSuppressed",false)
        ctx.Workspace:SetAttribute("Level3FlashlightsSuppressed",true)
        ctx:Lights(true,"phase/legacy flag change at "..elapsed)
    end
    ctx:Advance(.1);ctx:Key("ButtonR1");ctx:Lights(false,"gamepad can turn it off")
    ctx:Advance(.3);ctx:Touch();ctx:Lights(true,"touch can turn it on")
    ctx:Key("F",true);ctx:Key("G");ctx:Lights(true,"processed/unrelated keys do nothing")
    ctx.Player:SetAttribute("Level3_Hiding",true)
    ctx:Advance(.1);ctx:Key("F");ctx:Lights(false,"hidden player can turn off")
    ctx:Advance(.1);ctx:Key("F");ctx:Lights(true,"hidden player can turn on")
    equal(ctx.Player:GetAttribute("Level3_Hiding"),true,"toggle preserves hiding")
end
do
    local ctx=fresh();ctx:SetBattery(5);ctx:Key("F");ctx:Lights(false,"empty threshold keeps flashlight off")
    ctx:Tick(1);equal(ctx:Battery(),8,"off battery recharges at normal rate")
    ctx:Key("F");ctx:Lights(true,"recharged flashlight turns on")
    ctx:Tick(10);ctx:Lights(false,"drained battery turns it off")
    equal(ctx:Battery(),0,"battery clamps at zero");equal(#ctx.Popups,1,"battery death warns once")
    ctx:Tick(1);equal(ctx:Battery(),3,"depleted battery begins recharging")
end
do
    local ctx=fresh();ctx:Key("F")
    local hum=ctx.Player.Character:FindFirstChildOfClass("Humanoid")
    hum.Health=0;hum.Died:Fire();ctx:Lights(false,"death wins immediately")
    ctx:Advance(.1);ctx:Key("F");ctx:Lights(false,"dead local player cannot turn on")
    ctx:Send(true);equal(ctx:Flag(),false,"server also rejects a dead on request")
    ctx:Respawn();ctx:Lights(false,"respawn starts with light off")
    equal(ctx:Battery(),100,"respawn refills battery")
    ctx:Advance(.1);ctx:Key("F");ctx.Player:SetAttribute("InRound",false)
    ctx:Lights(false,"round end clears local and replicated beams")
    ctx:Advance(.1);ctx:Key("F");ctx:Send(true);ctx:Lights(false,"lobby cannot turn on")
end
do
    local ctx=fresh();ctx:Key("F");ctx:Lights(true,"initial on")
    ctx:Key("F");ctx:Lights(false,"off bypasses server throttle")
end
do
    local ctx=fresh();ctx:Key("F");ctx:Advance(.1)
    local target=CFrame.lookAt(Vector3.new(11,5,10),Vector3.new(12,5,10))
    ctx:Send("aim",target)
    equal(ctx:Mount().CFrame.Position.X,11,"server accepts aim while legacy flag is true")
    equal(ctx:Mount().CFrame.LookVector.X,1,"server retains aim direction")
    ctx:Advance(.1)
    ctx:Send("aim",CFrame.lookAt(Vector3.new(100,5,10),Vector3.new(101,5,10)))
    equal(ctx:Mount().CFrame.Position.X,10,"distant origin remains clamped to character")
    local old=ctx:Mount().CFrame;ctx:Advance(.1)
    ctx:Send("aim",{Kind="CFrame",Position=Vector3.new(0/0,0,0),LookVector=Vector3.new(1,0,0)})
    equal(ctx:Mount().CFrame,old,"nonfinite aim remains rejected")
    ctx:Advance(.1);ctx:Key("F");ctx:Advance(.1);ctx:Send("aim",target)
    equal(ctx:Mount().CFrame,old,"off flashlight ignores aim packets")
end
print(string.format("Flashlight player control: %d checks passed (actual inputs, battery, lifecycle, server replication, teammate display)",checks))
'''


def main():
    binary = os.environ.get("LUAU_BIN") or shutil.which("luau")
    if not binary:
        raise SystemExit("Set LUAU_BIN or put luau on PATH; no tests executed.")
    client = CLIENT.read_text(encoding="utf-8")
    replacements = {
        "__SERVER__": SERVER.read_text(encoding="utf-8"),
        "__BATTERY_STATE__": section(client, "local BATTERY_BASE", "-- bottom-of-screen pop-up"),
        "__CLIENT_CONTROL__": section(client, "local function setLights(", "-- ── teammates' flashlights"),
        "__MATE_HEARTBEAT__": section(client, "-- drive every mate beam", "-- DevCheats owns"),
        "__BATTERY_HEARTBEAT__": client[client.index("-- DevCheats owns"):],
    }
    host = HOST
    for marker, content in replacements.items():
        host = host.replace(marker, content)
    with tempfile.TemporaryDirectory(prefix="flashlight-control-") as directory:
        path = Path(directory) / "control.luau"
        path.write_text(host, encoding="utf-8")
        subprocess.run([binary, str(path)], check=True, timeout=20)


if __name__ == "__main__":
    main()
