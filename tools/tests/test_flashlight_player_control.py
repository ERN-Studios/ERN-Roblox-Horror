"""Exercise actual flashlight input/lifecycle/battery and complete server sync.

Roblox object, input and frame signals are fakes; the production local toggle,
respawn/death hooks, battery heartbeat, teammate renderer and complete server
script run unchanged. Music timing is covered by test_level3_flashlight_timeline.
The Level 2 new-map dev preview's round body (Level2NewMapPreview) carries the torch too.

HUD batch B1 (owner, 2026-10-08; artifacts/hud-final-20261008/BUILD-PLAN.md 07): the PC widget.
Program 1 runs the controller's own heartbeat and toggle against a fake RoundHud and checks the
state -> line table (LIGHT, LIGHT OFF, CHARGING, LOW, EMPTY, TOO LOW for 2 s, WIDE, FOCUSED,
THEIR LIGHT while spectating) and that the touch layout never draws the widget. Program 2 runs the
controller's widget section against the REAL RoundHud, ShopBinder and UIStyle and the REAL HUD_PC
import (tools/tests/fixtures/hud/framewisp-dump.HUD_PC.json) in tools/tests/hud_harness.luau:
template paths, design size, bottom-left placement, the F / R1 keycap, palette colours per state,
touch, and a place without the template or without RoundHud.

HUD batch B2 (owner, 2026-10-08; artifacts/hud-final-20261008/b2/B2-DESIGN.md 6): the touch LIGHT cell,
HUD_Touch/TouchCluster/FlashlightPower, replaces the torch button. Program 1 runs the controller's mount,
layout and gate code (between B1's widget and setLights) with its real heartbeat: touch draws and
registers the cell and never the widget, a flip to PC reverses it, the battery and the 2 s refusal show
on the cell, and spectating, a modal or death stand it down. Program 3 runs the cell's two marked blocks
and the gate against the REAL RoundHud, ShopBinder and HUD_Touch import (fixtures/hud/
framewisp-dump.HUD_Touch.json): mount, the phone and tablet slots, every paint state in the real palette,
the eight screen-owning modals from UIDevice's own list, tap / 0.2 s debounce / 0.45 s hold, and a place
without HUD_Touch or RoundHud. Both blocks must be ASCII-only.
"""

import os
from pathlib import Path
import shutil
import subprocess
import sys
import tempfile

ROOT = Path(__file__).resolve().parents[2]
CLIENT = ROOT / "StarterPlayer/StarterPlayerScripts/FlashlightController.LocalScript.lua"
SERVER = ROOT / "ServerScriptService/FlashlightSync.Script.lua"
sys.path.insert(0, str(Path(__file__).resolve().parent))
import test_round_hud as hud_test  # noqa: E402  the HUD harness helpers (owner, 2026-10-08)


def section(source, start, stop):
    begin = source.index(start)
    return source[begin:source.index(stop, begin)]


HOST = r'''
local checks=0
local function check(value,message) checks+=1;assert(value,message) end
local function equal(actual,expected,message)
    check(actual==expected,message..": expected "..tostring(expected)..", got "..tostring(actual))
end
-- The widget after one heartbeat: line text and tone, lit segments (Coral under a Coral line, i.e.
-- TOO LOW; else Amber at <= 2, else Cream; unlit Line) and the battery outline, shell and nub (Coral
-- only at EMPTY: the B tiles, owner 2026-10-08).
local function look(ctx,text,tone,lit,shell,message)
    ctx:Tick(0)
    local w,P=ctx:Widget(),ctx.Palette
    local line=ctx.Find(w,"Line")
    equal(line.Text,text,message..": line")
    equal(line.TextColor3,P[tone],message..": "..tone.." line")
    for i=1,5 do
        equal(ctx.Find(w,"Seg"..i).BackgroundColor3,i>lit and P.Line or (tone=="Coral" and P.Coral or (lit<=2 and P.Amber or P.Cream)),message..": segment "..i)
    end
    equal(ctx.Find(w,"Shell"):FindFirstChildOfClass("UIStroke").Color,P[shell],message..": "..shell.." outline")
    equal(ctx.Find(w,"Nub").BackgroundColor3,P[shell],message..": "..shell.." nub")
    check(w.Visible,message..": drawn")
end
-- The touch LIGHT cell after one heartbeat (B2, 14 A; owner, 2026-10-08): its label and colour, the
-- lit segments in `fill` at the template's 0.1 and the rest Cream at its 0.85, and the outline (Coral
-- only at EMPTY).
local function cellLook(ctx,text,tone,lit,fill,outline,message)
    ctx:Tick(0)
    local cell,P=ctx:Cell(),ctx.Palette
    local label=ctx.Find(cell,"Label")
    equal(label.Text,text,message..": label")
    equal(label.TextColor3,P[tone],message..": "..tone.." label")
    for i=1,5 do
        local seg=ctx.Find(cell,"Seg"..i)
        equal(seg.BackgroundColor3,i>lit and P.Cream or P[fill],message..": segment "..i)
        equal(seg.BackgroundTransparency,i>lit and .85 or .1,message..": segment "..i.." alpha")
    end
    equal(cell:FindFirstChildOfClass("UIStroke").Color,P[outline],message..": "..outline.." outline")
end
local B="\u{B7}"
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
local Enum={NormalId={Front="Front"},Font={GothamBold="GothamBold"},KeyCode={F="F",ButtonR1="ButtonR1",G="G",Y="Y",ButtonR3="ButtonR3"},
    UserInputType={Touch="Touch",MouseButton1="MouseButton1"}}

local function fresh()
    local ctx={Now=100,Sent={},Vitals={}}
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
    -- With a timeout a missing child is nil, as in the engine (the LIGHT cell's queue-shade watch).
    function methods:WaitForChild(name,timeout) local c=self:FindFirstChild(name);if timeout then return c end;return assert(c,name) end
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
    node("PlayerGui","PlayerGui",player)
    function players:GetPlayers() return {player} end
    function players:GetPlayerByUserId(id)
        for _,p in ipairs(players.Children) do if p.UserId==id then return p end end
    end
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
    node("ModuleScript","RoundHud",rs);node("ModuleScript","ShopBinder",node("Folder","ZyntraShopUI",rs))
    local RS,Players=rs,players
    local Profiles={Mount={},Mate={},Current=function() return "BASE" end,Apply=function() end}
    local game={GetService=function(_,name) return name=="Players" and players or rs end,IsLoaded=function() return true end}
    -- The PC widget (07 B): a fake RoundHud mounting the HUD_PC/FlashlightWidget names, and a Binder
    -- whose Palette entries are the colours paintWidget must write. Program 2 uses the real ones.
    local Palette={Cream=Color3.fromRGB(242,235,219),Amber=Color3.fromRGB(232,160,36),
        Coral=Color3.fromRGB(242,112,95),Line=Color3.fromRGB(38,49,52)}
    local function findDeep(root,name)
        for _,child in ipairs(root.Children) do
            if child.Name==name then return child end
            local hit=findDeep(child,name);if hit then return hit end
        end
    end
    local Binder={Palette=Palette,find=findDeep,text=function(n) return n end}
    function Binder.at(root,path) local n=root;for step in string.gmatch(path,"[^/]+") do n=n and findDeep(n,step) end;return n end
    local Hud={Mounts=0,CellMounts=0,Keycaps={}}
    function Hud.Mount(bundle,path,parent,opts)
        if bundle=="HUD_Touch" then
            -- B2 (owner, 2026-10-08): the LIGHT cell, HUD_Touch/TouchCluster/FlashlightPower's names and
            -- template look (Cream segments lit at 0.1, Seg5 unlit at 0.85, a Line outline, a Cream LIGHT).
            -- Program 3 mounts the real import.
            Hud.CellMounts+=1;ctx.CellFrom=bundle.."/"..path
            local cell=node("TextButton",opts and opts.Name or "FlashlightPower")
            cell.Visible=true;cell.Active=true;cell.Selectable=true;cell.AutoButtonColor=true;cell.InputBegan=signal()
            node("UIStroke","UIStroke",cell).Color=Palette.Line
            for i=1,5 do local seg=node("Frame","Seg"..i,cell);seg.BackgroundColor3=Palette.Cream;seg.BackgroundTransparency=i==5 and .85 or .1 end
            local label=node("TextLabel","Label",cell);label.Text="LIGHT";label.TextColor3=Palette.Cream
            cell.Parent=parent
            return cell
        end
        Hud.Mounts+=1;ctx.MountedFrom=bundle.."/"..path
        local root=node("Frame","FlashlightWidget");root.Visible=true
        node("TextLabel","Key",node("Frame","KeyChip",root))
        local battery=node("Frame","Battery",root);node("UIStroke","UIStroke",node("Frame","Shell",battery))
        for i=1,5 do node("Frame","Seg"..i,battery) end;node("Frame","Nub",battery)
        node("TextLabel","Line",root);root.Parent=parent
        return root
    end
    function Hud.Keycap(chip,keyboard,gamepad) table.insert(Hud.Keycaps,{chip,keyboard,gamepad}) end
    local modules={FlashlightProfiles=Profiles,RoundHud=Hud,ShopBinder=Binder}
    local require=function(module) return assert(modules[module.Name],module.Name) end
    local function time() return ctx.Now end
    local os={clock=function() return ctx.Now end}
    local delayed={}
    local task={spawn=function(fn,...) fn(...) end,wait=function() end,delay=function(t,fn) table.insert(delayed,{At=ctx.Now+t,Fn=fn}) end}
    do __SERVER__ end
    local remote={FireServer=function(_,value,payload)
        table.insert(ctx.Sent,{value,payload});serverRemote.OnServerEvent:Fire(player,value,payload)
    end}
    local RunService={Heartbeat=signal(),IsStudio=function() return true end}
    local vitalRemote={FireServer=function(_,kind,payload)
        table.insert(ctx.Vitals,{kind=kind,payload=payload})
    end}
    local lastVitalReport=-math.huge
    local UDim2={new=function(...) return {...} end,fromOffset=function(x,y) return {0,x,0,y} end}
    local Vector2={new=function(x,y) return {X=x,Y=y} end}
    -- ctx.TouchUI is the touch layout (ctx:Touch is the tap). B2 adds the cluster contract the LIGHT
    -- cell reads: Layout().IsTouch and ControlPlan.Slots.FlashlightPower (the phone slot), the control
    -- registry and SetInteractive, which latches Selectable as UIDevice does (owner, 2026-10-08).
    ctx.Registered={}
    local UIDevice={IsTouch=function() return ctx.TouchUI==true end,Changed=signal(),Binding=function(k) return k end,
        ScreenOwningModalOpen=function() return ctx.Modal==true end,
        Layout=function() return {IsTouch=ctx.TouchUI==true,Safe={Left=0,Top=0,Right=1920,Bottom=1080},
            ControlPlan={Slots={FlashlightPower={Right=192,Bottom=12,Width=52,Height=52}}}} end,
        RegisterControlRect=function(key,element) ctx.Registered[element]=key end,
        UnregisterControlRect=function(element) ctx.Registered[element]=nil end,
        SetInteractive=function(element,visible)
            element.Visible=visible;element.Active=visible
            if element:GetAttribute("UIDeviceSelectable")==nil then element:SetAttribute("UIDeviceSelectable",element.Selectable==true) end
            element.Selectable=element:GetAttribute("UIDeviceSelectable") and visible
        end,
        LocalPosition=function(_,x,y) return {X=x,Y=y} end}
    local function isFocused() return player:GetAttribute("ZyntraOwnsAdvancedEquipment")==true and player.Character:GetAttribute("FlashlightFocused")==true end
    local UIS={InputBegan=signal(),InputEnded=signal()}
    local coreLight,spillLight={Enabled=false},{Enabled=false}
    local fillLight={Enabled=false}
    local clickSound={Plays=0,Play=function(self) self.Plays+=1 end}
    local MATE_SHAFT_LENGTH,mateRay=40,{}
    local on=false
    local popupGui=node("ScreenGui","FlashlightPopup")
    __BATTERY_STATE__
    __WIDGET__
    __LIGHT_CELL__
    __CLIENT_CONTROL__
    local observer={core={},spill={}}
    local mateBeams={[player.Character]=observer};local lastMateProfile=nil
    __MATE_HEARTBEAT__
    __BATTERY_HEARTBEAT__
    ctx.Player=player;ctx.Workspace=workspace;ctx.Observer=observer
    ctx.Gui=popupGui;ctx.Hud=Hud;ctx.Palette=Palette;ctx.Find=findDeep
    function ctx:Widget() return popupGui:FindFirstChild("FlashlightWidget") end
    function ctx:Cell() return popupGui:FindFirstChild("FlashlightPower") end
    -- A form-factor flip fires UIDevice.Changed, as UIDevice does.
    function ctx:Device(touch) self.TouchUI=touch;UIDevice.Changed:Fire() end
    function ctx:Mate()
        local mate=node("Player","Mate",players);mate.UserId=456;mate:SetAttribute("InRound",true)
        local char=node("Model","MateCharacter",workspace);local hum=node("Humanoid","Humanoid",char);hum.Health=100
        local flag=node("BoolValue","FlashlightOn",char);flag.Value=false
        mate.Character=char
        return mate,hum,flag
    end
    function ctx:Advance(seconds) self.Now+=seconds;for i=#delayed,1,-1 do if delayed[i].At<=self.Now then local f=table.remove(delayed,i);f.Fn() end end end
    function ctx:Tick(dt) self.Now+=dt;RunService.Heartbeat:Fire(dt) end
    function ctx:Key(key,processed) UIS.InputBegan:Fire({KeyCode=key},processed==true) end
    function ctx:Touch(duration) local i={UserInputType=Enum.UserInputType.Touch};lightCell.InputBegan:Fire(i);if duration then self:Advance(duration) end;UIS.InputEnded:Fire(i) end
    function ctx:Send(value,payload) serverRemote.OnServerEvent:Fire(player,value,payload) end
    function ctx:SetBattery(value) battery=value end
    function ctx:Battery() return battery end
    function ctx:On() return on end
    function ctx:Flag() return player.Character:FindFirstChild("FlashlightOn").Value end
    function ctx:Mount() return workspace:FindFirstChild("ReplicatedFlashlight_123") end
    function ctx:Lights(expected,message)
        equal(on,expected,message.." user choice");equal(coreLight.Enabled,expected,message.." own core")
        equal(spillLight.Enabled,expected,message.." own spill");equal(fillLight.Enabled,expected,message.." own fill");equal(self:Flag(),expected,message.." replicated flag")
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
    equal(ctx:Battery(),0,"battery clamps at zero")
    -- The dead-battery strip ("Flashlight dead") is retired by HUD batch B1; the widget says it.
    look(ctx,"LIGHT "..B.." EMPTY","Coral",0,"Coral","battery death reads EMPTY")
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
do
    local ctx=fresh();ctx:Key("Y");equal(ctx.Player.Character:GetAttribute("FlashlightFocused")==true,false,"nonowner local focus refused")
    ctx:Send("focus",true);equal(ctx.Player.Character:GetAttribute("FlashlightFocused")==true,false,"nonowner server focus refused")
    ctx.Player:SetAttribute("ZyntraOwnsAdvancedEquipment",true);ctx:Advance(.2);ctx:Key("Y")
    equal(ctx.Player.Character:GetAttribute("FlashlightFocused"),true,"owner keyboard focus accepted")
    ctx:Key("F");ctx:Lights(true,"focus does not prevent ordinary toggle")
    ctx:Advance(.2);ctx:Key("ButtonR3");equal(ctx.Player.Character:GetAttribute("FlashlightFocused"),false,"gamepad returns wide")
    ctx:Advance(.3);ctx:Touch(.5);equal(ctx.Player.Character:GetAttribute("FlashlightFocused"),true,"touch hold focuses")
    ctx:Lights(true,"hold leaves on-off choice unchanged")
    ctx:Advance(.3);ctx:Touch(.1);ctx:Lights(false,"short tap still toggles")
    ctx:Advance(.3);ctx:Send("focus","true");equal(ctx.Player.Character:GetAttribute("FlashlightFocused"),true,"malformed focus rejected")
    ctx.Player:SetAttribute("InRound",false);equal(ctx.Player.Character:GetAttribute("FlashlightFocused"),false,"round end clears focus")
    ctx:Advance(.3);ctx:Send("focus",true);equal(ctx.Player.Character:GetAttribute("FlashlightFocused"),false,"lobby focus refused")
end
do
    -- The Level 2 new-map dev preview wears the round body outside a round (Level2NewMapPreview, 2026-10-07).
    local ctx=fresh();ctx.Player:SetAttribute("InRound",false);ctx.Player:SetAttribute("Level2NewMapPreview",true)
    ctx:Advance(.1);ctx:Key("F");ctx:Lights(true,"the preview body carries the round torch")
    ctx:Send("aim",CFrame.lookAt(Vector3.new(11,5,10),Vector3.new(12,5,10)))
    equal(ctx:Mount().CFrame.Position.X,11,"the server aims the preview torch for teammates")
    ctx.Player:SetAttribute("ZyntraOwnsAdvancedEquipment",true);ctx:Advance(.2);ctx:Key("Y")
    equal(ctx.Player.Character:GetAttribute("FlashlightFocused"),true,"the preview body may focus")
    ctx:Advance(.1);ctx.Player:SetAttribute("Level2NewMapPreview",nil)
    ctx:Lights(false,"leaving the preview clears local and replicated beams")
    equal(ctx.Player.Character:GetAttribute("FlashlightFocused"),false,"leaving the preview clears focus")
    ctx:Advance(.1);ctx:Key("F");ctx:Send(true);ctx:Lights(false,"the lobby after the preview cannot turn on")
end
do -- 07 B: the widget mounts at round entry and follows the real heartbeat (owner, 2026-10-08)
    local ctx=fresh();local w=ctx:Widget()
    check(w~=nil and w.Parent==ctx.Gui,"round entry mounts the widget into the flashlight gui")
    equal(ctx.MountedFrom,"HUD_PC/FlashlightWidget","from the HUD_PC template")
    local cap=ctx.Hud.Keycaps[1]
    check(cap~=nil and cap[1]==ctx.Find(w,"KeyChip") and cap[2]=="F" and cap[3]=="ButtonR1","keycap: F, R1 on a gamepad")
    check(w.AnchorPoint.X==0 and w.AnchorPoint.Y==1 and w.Position.X==24 and w.Position.Y==1056,"bottom-left: Safe.Left + 24, bottom - 24")
    look(ctx,"LIGHT OFF","Cream",5,"Cream","off at full: no CHARGING when it is not charging")
    ctx:Key("F");look(ctx,"LIGHT","Cream",5,"Cream","on")
    ctx:SetBattery(41);look(ctx,"LIGHT","Cream",3,"Cream","three segments is not low")
    ctx:SetBattery(40);look(ctx,"LIGHT "..B.." LOW","Amber",2,"Cream","two segments is LOW, in Amber")
    ctx:SetBattery(90);ctx.Player:SetAttribute("ZyntraOwnsAdvancedEquipment",true)
    look(ctx,"LIGHT "..B.." WIDE","Cream",5,"Cream","Advanced Equipment: WIDE")
    ctx:Advance(.2);ctx:Key("Y");look(ctx,"LIGHT "..B.." FOCUSED","Cream",5,"Cream","Advanced Equipment: FOCUSED")
    ctx:SetBattery(30);look(ctx,"LIGHT "..B.." LOW","Amber",2,"Cream","LOW outranks FOCUSED")
    ctx:Key("F");look(ctx,"LIGHT "..B.." LOW","Amber",2,"Cream","off and low still reads LOW")
    ctx:SetBattery(70);look(ctx,"LIGHT OFF "..B.." CHARGING","Cream",4,"Cream","off below full: CHARGING")
    ctx.Player:SetAttribute("InRound",false);equal(ctx.Gui.Enabled,false,"out of a round the gui is off")
    ctx.Player:SetAttribute("InRound",true);equal(ctx.Gui.Enabled,true,"back in a round it is on")
    equal(ctx.Hud.Mounts,1,"the next round reuses the one mount")
end
do -- 07 B: a press below the switch-on floor is no longer silent: TOO LOW for 2 s
    local ctx=fresh();ctx:SetBattery(1)
    look(ctx,"LIGHT "..B.." EMPTY","Coral",0,"Coral","below the switch-on floor: EMPTY")
    ctx:Key("F");ctx:Lights(false,"the refused press leaves it off")
    look(ctx,"LIGHT "..B.." TOO LOW","Coral",1,"Cream","a refused press reads TOO LOW: one Coral segment in a Cream outline, not EMPTY's look")
    ctx:Tick(1.9);look(ctx,"LIGHT "..B.." TOO LOW","Coral",1,"Cream","still TOO LOW inside 2 s, while it recharges past the floor")
    ctx:Tick(.2);look(ctx,"LIGHT "..B.." LOW","Amber",1,"Cream","after 2 s the line is the battery state again")
    ctx:SetBattery(1);ctx:Key("F");look(ctx,"LIGHT "..B.." TOO LOW","Coral",1,"Cream","refused again")
    ctx:SetBattery(50);ctx:Key("F");ctx:Lights(true,"once charged it switches on")
    look(ctx,"LIGHT","Cream",3,"Cream","switching on ends TOO LOW at once")
    ctx:Key("F");look(ctx,"LIGHT OFF "..B.." CHARGING","Cream",3,"Cream","and switching off again does not bring it back")
end
do -- 07 B: spectating draws THEIR LIGHT from the watched teammate's battery
    local ctx=fresh();local mate,hum,flag=ctx:Mate()
    ctx.Player:SetAttribute("Spectating",true);ctx.Player:SetAttribute("SpectateTargetUserId",456)
    mate:SetAttribute("SpectateBattery",.8);look(ctx,"THEIR LIGHT","Cream",4,"Cream","their battery, not yours")
    local cap=ctx.Hud.Keycaps[#ctx.Hud.Keycaps]
    check(cap[1]==ctx.Find(ctx:Widget(),"KeyChip") and cap[2]==nil and cap[3]==nil,"no keycap while spectating: the keys do nothing then")
    mate:SetAttribute("SpectateBattery",.3);look(ctx,"THEIR LIGHT","Cream",2,"Cream","their low battery: Amber segments")
    mate:SetAttribute("SpectateBattery",.02);look(ctx,"THEIR LIGHT","Cream",0,"Coral","their dead torch: Coral outline")
    flag.Value=true;look(ctx,"THEIR LIGHT","Cream",1,"Cream","a lit torch is never EMPTY")
    ctx.Modal=true;ctx:Tick(0);check(not ctx:Widget().Visible,"a screen-owning modal hides it")
    ctx.Modal=false;mate:SetAttribute("Escaped",true);ctx:Tick(0);check(not ctx:Widget().Visible,"an escaped target hides it")
    mate:SetAttribute("Escaped",nil);hum.Health=0;ctx:Tick(0);check(not ctx:Widget().Visible,"a dead target hides it")
    ctx.Player:SetAttribute("Spectating",false)
    look(ctx,"LIGHT OFF","Cream",5,"Cream","after spectating it is your own light again")
    cap=ctx.Hud.Keycaps[#ctx.Hud.Keycaps]
    check(cap[2]=="F" and cap[3]=="ButtonR1","and the F / R1 keycap is back")
end
do -- owner P1 (B2, 14 A): touch draws the LIGHT cell and never the PC widget; PC the reverse
    local ctx=fresh();ctx:Tick(0);local cell=ctx:Cell()
    check(cell~=nil and cell.Parent==ctx.Gui and cell.ClassName=="TextButton","the LIGHT cell is mounted into the flashlight gui at load")
    equal(ctx.CellFrom,"HUD_Touch/TouchCluster/FlashlightPower","from the HUD_Touch template")
    check(ctx:Widget().Visible and cell.Visible==false and cell.Active==false,"PC: the widget, not the cell")
    equal(ctx.Registered[cell],nil,"PC: the cell is no movement control")
    check(cell.Selectable==false and cell.AutoButtonColor==false,"never gamepad-selectable, no engine press tint")
    ctx:Device(true);ctx:Tick(0)
    check(not ctx:Widget().Visible and cell.Visible==true and cell.Active==true,"touch: the LIGHT cell, not the widget")
    equal(ctx.Registered[cell],"FlashlightPower","touch registers the cell as FlashlightPower")
    check(cell.AnchorPoint.X==1 and cell.AnchorPoint.Y==1 and cell.Size[2]==52 and cell.Size[4]==52
        and cell.Position[1]==1 and cell.Position[2]==-192 and cell.Position[3]==1 and cell.Position[4]==-12,"placed from Slots.FlashlightPower")
    check(cell.Selectable==false,"Selectable stays false once shown: latched before the first SetInteractive")
    ctx:SetBattery(1);ctx:Key("F");ctx:Tick(0);check(not ctx:Widget().Visible,"not even for TOO LOW")
    cellLook(ctx,"LOW","Coral",1,"Coral","Line","the refusal shows on the cell instead")
    ctx:Device(false);ctx:Tick(0)
    check(ctx:Widget().Visible and cell.Visible==false and cell.Active==false,"a flip back to PC brings the widget back and hides the cell")
    equal(ctx.Registered[cell],nil,"and unregisters it")
    ctx:Device(true);equal(ctx.Registered[cell],"FlashlightPower","a flip to touch registers it again")
    equal(ctx.Hud.CellMounts,1,"the cell is mounted once and never again")
    equal(ctx.Hud.Mounts,1,"the widget too")
end
do -- B2 LIGHT cell (14 A): your battery from the real heartbeat; LOW for 2 s on a refused press
    local ctx=fresh();ctx:Device(true)
    cellLook(ctx,"LIGHT","Cream",5,"Cream","Line","off at full: on and off are not drawn (D10)")
    ctx:Key("F");cellLook(ctx,"LIGHT","Cream",5,"Cream","Line","on at full")
    ctx:SetBattery(60);cellLook(ctx,"LIGHT","Cream",3,"Cream","Line","three segments")
    ctx:SetBattery(40);cellLook(ctx,"LOW","Amber",2,"Amber","Line","two segments: LOW in Amber")
    ctx:SetBattery(20);cellLook(ctx,"LOW","Amber",1,"Amber","Line","one segment: LOW in Amber")
    ctx.Player:SetAttribute("ZyntraOwnsAdvancedEquipment",true);ctx:Advance(.2);ctx:Key("Y")
    ctx:SetBattery(90);cellLook(ctx,"LIGHT","Cream",5,"Cream","Line","FOCUSED is not drawn (D12)")
    ctx:Key("F");ctx:SetBattery(3);cellLook(ctx,"LIGHT","Cream",0,"Cream","Coral","EMPTY: no segments in a Coral outline")
    ctx:Key("F");ctx:Lights(false,"a press below the floor is refused")
    cellLook(ctx,"LOW","Coral",1,"Coral","Line","refused: LOW in Coral round one Coral segment, outline back to Line")
    ctx:Tick(1.9);cellLook(ctx,"LOW","Coral",1,"Coral","Line","still refused inside 2 s, while it recharges past the floor")
    ctx:Tick(.2);cellLook(ctx,"LOW","Amber",1,"Amber","Line","after 2 s its own case again")
    -- Spectating hides the cell and never paints the watched battery into it (D11).
    ctx:SetBattery(100);ctx:Tick(0)
    local mate=ctx:Mate();ctx.Player:SetAttribute("SpectateTargetUserId",456);ctx.Player:SetAttribute("Spectating",true)
    mate:SetAttribute("SpectateBattery",.02);ctx:Tick(0)
    local cell=ctx:Cell()
    check(not cell.Visible and not cell.Active,"spectating hides the cell and stands it down")
    equal(cell:FindFirstChildOfClass("UIStroke").Color,ctx.Palette.Line,"the watched empty torch is not painted into it")
    ctx.Player:SetAttribute("Spectating",false);check(cell.Visible and cell.Active,"your own light again after spectating")
    ctx.Modal=true;ctx:Device(true);check(not cell.Visible and not cell.Active,"a screen-owning modal hides it")
    ctx.Modal=false;ctx:Device(true);check(cell.Visible and cell.Active,"and gives it back")
    local hum=ctx.Player.Character:FindFirstChildOfClass("Humanoid")
    hum.Health=0;hum.Died:Fire();check(not cell.Visible and not cell.Active,"death stands it down at once")
    ctx:Respawn();check(cell.Visible and cell.Active,"a respawn brings it back")
    ctx.Player:SetAttribute("InRound",false);check(not cell.Visible,"out of a round it is hidden")
end
print(string.format("Flashlight player control: %d checks passed (actual inputs, battery, lifecycle, server replication, teammate display, PC widget)",checks))
'''

WIDGET_START, WIDGET_END = "-- == B flashlight widget", "-- == end B flashlight widget =="

# Program 2: the controller's widget section in the HUD harness, against the real modules and import.
WIDGET_PRELUDE = '''
local RS = game:GetService("ReplicatedStorage")
local UIDevice = require(RS:WaitForChild("UIDevice"))
local player = game:GetService("Players").LocalPlayer
local popupGui = Instance.new("ScreenGui")
popupGui.Name = "FlashlightPopup"
popupGui.Parent = player:WaitForChild("PlayerGui")
'''
WIDGET_EXPORTS = '''
return {Mount = mountWidget, Paint = paintWidget, Gui = popupGui, Widget = function() return widget end}
'''
WIDGET_TESTS = r'''
local B = "\u{B7}"
local function setup(opts)
	local ctx = context(opts)
	return ctx, ctx:Require("FlashlightWidgetSection"), ctx:Require("ShopBinder").Palette
end

do -- the real template: mount, size, placement, keycap
	local ctx, S = setup({safe = {Left = 40, Top = 0, Right = 1880, Bottom = 1000, Width = 1840, Height = 1000}})
	check(S.Widget() == nil, "nothing is mounted before the first round entry")
	S.Mount()
	local w = S.Gui:FindFirstChild("FlashlightWidget")
	check(w ~= nil and w == S.Widget(), "HUD_PC/FlashlightWidget mounts into FlashlightPopup as FlashlightWidget")
	check(not w.Visible, "mounted hidden: the template's sample line never shows before the first paint")
	check(w.Size == UDim2.fromOffset(232, 69), "at the template's design size: " .. tostring(w.Size))
	check(w.AnchorPoint.X == 0 and w.AnchorPoint.Y == 1 and w.Position == UDim2.fromOffset(64, 976),
		"bottom-left at Safe.Left + 24, Safe.Bottom - 24: " .. tostring(w.Position))
	check(find(w, "KeyChip/Key").Text == "F", "the keycap reads F on a keyboard")
	ctx:Device({GamepadEnabled = true, LastInput = "Gamepad"})
	local glyph = find(w, "KeyChip/GlyphSlot"):FindFirstChildWhichIsA("ImageLabel", true)
	check(glyph and glyph.Visible and string.find(glyph.Image, "ButtonR1", 1, true) and find(w, "KeyChip/Key").Text == "",
		"a gamepad shows the R1 glyph")
	ctx:Device({Safe = {Left = 0, Top = 0, Right = 1280, Bottom = 720, Width = 1280, Height = 720}})
	check(w.Position == UDim2.fromOffset(24, 696), "re-placed when the layout changes: " .. tostring(w.Position))
	S.Mount()
	check(#S.Gui:GetChildren() == 1, "mounted once")
	check(#ctx.Warnings == 0, "no warnings: " .. table.concat(ctx.Warnings, " | "))
end

do -- every state on the real nodes, in the real palette
	local ctx, S, P = setup()
	S.Mount()
	local w = S.Widget()
	local line = find(w, "Line")
	local stroke = find(w, "Battery/Shell"):FindFirstChildOfClass("UIStroke")
	local CASES = {
		{"on", {Fraction = 1, On = true}, "LIGHT", "Cream", 5},
		{"off at full", {Fraction = 1}, "LIGHT OFF", "Cream", 5},
		{"off, charging", {Fraction = 0.7, Charging = true}, "LIGHT OFF " .. B .. " CHARGING", "Cream", 4},
		{"on, low", {Fraction = 0.4, On = true}, "LIGHT " .. B .. " LOW", "Amber", 2},
		{"off, low", {Fraction = 0.25, Charging = true}, "LIGHT " .. B .. " LOW", "Amber", 2},
		{"empty", {Fraction = 0.03, Empty = true, Charging = true}, "LIGHT " .. B .. " EMPTY", "Coral", 0, "Coral"},
		{"refused", {Fraction = 0.03, Empty = true, Refused = true}, "LIGHT " .. B .. " TOO LOW", "Coral", 1},
		{"refused, recharged past the floor", {Fraction = 0.08, Charging = true, Refused = true}, "LIGHT " .. B .. " TOO LOW", "Coral", 1},
		{"wide", {Fraction = 0.9, On = true, Advanced = true}, "LIGHT " .. B .. " WIDE", "Cream", 5},
		{"focused", {Fraction = 0.9, On = true, Advanced = true, Focused = true}, "LIGHT " .. B .. " FOCUSED", "Cream", 5},
		{"low beats focused", {Fraction = 0.2, On = true, Advanced = true, Focused = true}, "LIGHT " .. B .. " LOW", "Amber", 1},
		{"spectating", {Fraction = 0.6, Spectating = true}, "THEIR LIGHT", "Cream", 3},
		{"spectating, low", {Fraction = 0.3, Spectating = true}, "THEIR LIGHT", "Cream", 2},
		{"spectating, empty", {Fraction = 0.01, Empty = true, Spectating = true}, "THEIR LIGHT", "Cream", 0, "Coral"},
	}
	for _, case in ipairs(CASES) do
		local name, s, text, tone, lit, outline = case[1], case[2], case[3], case[4], case[5], case[6] or "Cream"
		S.Paint(s, true)
		check(w.Visible, name .. ": drawn")
		check(line.Text == text, name .. ": line " .. line.Text)
		check(line.TextColor3 == P[tone], name .. ": " .. tone .. " line, got " .. tostring(line.TextColor3))
		for i = 1, 5 do
			local want = i > lit and P.Line or (tone == "Coral" and P.Coral or (lit <= 2 and P.Amber or P.Cream))
			local seg = find(w, "Battery/Seg" .. i)
			check(seg.BackgroundColor3 == want, name .. ": segment " .. i)
			-- the template's look: lit at 0.1, unlit opaque (owner, 2026-10-08)
			check(seg.BackgroundTransparency == (i > lit and 0 or 0.1), name .. ": segment " .. i .. " transparency")
		end
		-- the B tiles: only EMPTY (theirs too) has the Coral outline and nub; TOO LOW keeps Cream
		check(stroke.Color == P[outline], name .. ": the " .. outline .. " battery outline")
		check(find(w, "Battery/Nub").BackgroundColor3 == P[outline], name .. ": the " .. outline .. " nub")
	end
end

do -- the caller's gate and the touch layout (owner P1)
	local ctx, S = setup()
	S.Mount()
	local w = S.Widget()
	S.Paint({Fraction = 1}, false)
	check(not w.Visible, "the caller's gate hides it")
	ctx:Device({Touch = true})
	S.Paint({Fraction = 1, On = true}, true)
	check(not w.Visible and not find(w, "KeyChip").Visible, "the touch layout never draws it, nor its keycap")
	ctx:Device({Touch = false})
	S.Paint({Fraction = 1, On = true}, true)
	check(w.Visible and find(w, "KeyChip").Visible, "back on PC it is drawn again")
end

do -- a place without the template: nothing drawn, one warning by path
	local ctx, S = setup({skip = {HUD_PC = true}})
	S.Mount()
	S.Mount()
	S.Paint({Fraction = 0.5, On = true}, true)
	check(S.Widget() == nil and #S.Gui:GetChildren() == 0, "no template: nothing drawn")
	check(ctx:Warned("[RoundHud] missing template: HUD_PC/FlashlightWidget") == 1, "warned by path, once")
end

do -- a place without RoundHud: no widget and no error (the beam does not depend on the HUD)
	local ctx = context()
	ctx.Storage:FindFirstChild("RoundHud"):Destroy()
	local S = ctx:Require("FlashlightWidgetSection")
	S.Mount()
	S.Paint({Fraction = 1}, true)
	check(S.Widget() == nil, "no RoundHud: no widget")
end

print("Flashlight widget: " .. checks .. " checks passed (real RoundHud, real HUD_PC import)")
'''


LIGHT_MOUNT_START, LIGHT_MOUNT_END = "-- == B2 LIGHT cell (mount) ==", "-- == end B2 LIGHT cell (mount) =="
LIGHT_INPUT_START, LIGHT_INPUT_END = "-- == B2 LIGHT cell (input/paint) ==", "-- == end B2 LIGHT cell (input/paint) =="
# The torch button and its hint are gone with B2 (owner, 2026-10-08): none of these may come back.
RETIRED = ("batBody", "touchFlashButton", "TouchFlashlightToggle", "FocusModeHint", "focusCaption",
           "refreshFocusCaption", "lightRays", "batBars", "BAT_FULL", "BAT_EMPTY", "torchScale", "Silhouette")
PRIVATE_MODALS = ("ZyntraStoreOpen", "DevPhoneOpen", "ZyntraReentryOpen", "QueueModalOpen")
UIDEVICE = ROOT / "ReplicatedStorage/UIDevice.ModuleScript.lua"

# Program 3: the LIGHT cell's blocks and gate in the HUD harness, against the real modules and import.
LIGHT_PRELUDE = '''
local game = setmetatable({IsLoaded = function() return true end}, {__index = game})
local Players = game:GetService("Players")
local RS = game:GetService("ReplicatedStorage")
local UIDevice = require(RS:WaitForChild("UIDevice"))
local UIS = game:GetService("UserInputService")
local RunService = game:GetService("RunService")
local player = Players.LocalPlayer
local os = {clock = function() return workspace:GetServerTimeNow() end}
local BATTERY_BASE = 100
local battery = BATTERY_BASE
local function batteryMax() return BATTERY_BASE end
local function roundBody() return player:GetAttribute("InRound") == true end
local popupGui = Instance.new("ScreenGui")
popupGui.Name = "FlashlightPopup"
popupGui.Parent = player:WaitForChild("PlayerGui")
'''
# toggle / toggleFocus are counted here; program 1 runs the real ones.
LIGHT_TOGGLES = '''
local Calls = {Toggle = 0, Focus = 0}
local function toggle() Calls.Toggle += 1 end
local function toggleFocus() Calls.Focus += 1 end
'''
LIGHT_EXPORTS = '''
return {Cell = function() return lightCell end, Paint = paintLight, Calls = Calls, Gui = popupGui}
'''
LIGHT_TESTS = r'''
local MODALS = __MODALS__
-- B2-DESIGN section 0 and C16 (owner, 2026-10-08): what FlashlightController reads beyond the harness's
-- UIDevice fake, added here and not in the harness. Layout carries agent A's contract (the phone slot,
-- ControlPlan.Fan, KitFan, KitFanOpen); SetInteractive latches Selectable on its first value as UIDevice's
-- rememberedFlag does; ScreenOwningModalOpen reads UIDevice's own eight attributes.
local function setup(opts)
	opts = opts or {}
	local ctx = context(opts)
	local U = ctx.UIDevice
	ctx.Registered = {}
	ctx.Slot = {Right = 192, Bottom = 12, Width = 52, Height = 52}
	function U.Layout()
		return {IsTouch = ctx.Touch, Safe = ctx.Safe, KitFanOpen = false,
			KitFan = {Left = 553, Top = 185, Right = 725, Bottom = 237, Width = 172, Height = 52},
			ControlPlan = {Mode = "grid", Edge = 12, Gap = 8, Cell = ctx.Slot.Width,
				Slots = {FlashlightPower = ctx.Slot}, Fan = {Right = 72, Bottom = 132, Width = 172, Height = 52}}}
	end
	function U.RegisterControlRect(key, element) if element then ctx.Registered[key] = element end end
	function U.UnregisterControlRect(element)
		for key, value in pairs(ctx.Registered) do
			if value == element then ctx.Registered[key] = nil end
		end
	end
	function U.SetInteractive(element, visible)
		element.Visible = visible
		element.Active = visible
		if element:GetAttribute("UIDeviceSelectable") == nil then
			element:SetAttribute("UIDeviceSelectable", element.Selectable == true)
		end
		element.Selectable = element:GetAttribute("UIDeviceSelectable") and visible
	end
	function U.ScreenOwningModalOpen()
		for _, name in ipairs(MODALS) do
			if ctx.Player:GetAttribute(name) == true then return true end
		end
		return false
	end
	ctx.UIS.InputEnded = signal()
	ctx.Player.CharacterAdded = signal()
	local character = Instance.new("Model")
	local humanoid = Instance.new("Humanoid")
	humanoid.Health = 100
	humanoid.Died = signal()
	humanoid.Parent = character
	ctx.Player.Character, ctx.Character, ctx.Humanoid = character, character, humanoid
	ctx.Player:SetAttribute("InRound", true)
	if opts.noRoundHud then ctx.Storage:FindFirstChild("RoundHud"):Destroy() end
	local S = ctx:Require("LightCellSection")
	return ctx, S, ctx:Require("ShopBinder").Palette
end

-- Paint `s`, then read the real nodes: the label and its colour, lit segments in `fill` at the
-- template's lit alpha (Seg1, 0.1) and the rest Cream at its unlit alpha (Seg5, 0.85), the outline.
local function look(S, P, s, text, tone, lit, fill, outline, message)
	S.Paint(s)
	local cell = S.Cell()
	local label = find(cell, "Label")
	check(label.Text == text, message .. ": label " .. tostring(label.Text))
	check(label.TextColor3 == P[tone], message .. ": " .. tone .. " label, got " .. tostring(label.TextColor3))
	for i = 1, 5 do
		local seg = find(cell, "Seg" .. i)
		check(seg.BackgroundColor3 == (i > lit and P.Cream or P[fill]), message .. ": segment " .. i .. " colour")
		check(near(seg.BackgroundTransparency, i > lit and 0.85 or 0.1),
			message .. ": segment " .. i .. " alpha " .. tostring(seg.BackgroundTransparency))
	end
	check(cell:FindFirstChildOfClass("UIStroke").Color == P[outline], message .. ": the " .. outline .. " outline")
end

do -- the real template: mounted once at load, hidden, painted before it can show
	local ctx, S = setup()
	local cell = S.Cell()
	check(cell ~= nil and cell == S.Gui:FindFirstChild("FlashlightPower") and cell:IsA("GuiButton"),
		"HUD_Touch/TouchCluster/FlashlightPower mounts into FlashlightPopup as FlashlightPower, a GuiButton")
	check(#S.Gui:GetChildren() == 1, "one root in the gui")
	check(not cell.Visible and not cell.Active, "PC: hidden and inactive from the start")
	check(cell.Selectable == false and cell.AutoButtonColor == false, "not selectable, no engine press tint")
	check(next(ctx.Registered) == nil, "PC: nothing registered")
	check(near(find(cell, "Seg5").BackgroundTransparency, 0.1),
		"painted at load: a full battery lights Seg5, the template's unlit sample never shows")
	check(#ctx.Warnings == 0, "no warnings: " .. table.concat(ctx.Warnings, " | "))
end

do -- placement and registration follow the form factor; the slot resizes the one root (D6, C8)
	local ctx, S, P = setup()
	local cell = S.Cell()
	ctx:Device({Touch = true})
	check(ctx.Registered.FlashlightPower == cell, "touch registers the cell as FlashlightPower")
	check(cell.AnchorPoint.X == 1 and cell.AnchorPoint.Y == 1, "anchored at its bottom-right")
	check(cell.Position == UDim2.new(1, -192, 1, -12) and cell.Size == UDim2.fromOffset(52, 52),
		"the phone slot: " .. tostring(cell.Position) .. " " .. tostring(cell.Size))
	check(cell.Visible and cell.Active, "in a round, alive, on touch: drawn and live")
	check(cell.Selectable == false, "still not selectable once shown: latched before the first SetInteractive")
	local stroke = cell:FindFirstChildOfClass("UIStroke")
	local thickness = stroke.Thickness
	look(S, P, {Fraction = 0.03, Empty = true}, "LIGHT", "Cream", 0, "Cream", "Coral", "empty, at 52 px")
	ctx.Slot = {Right = 237, Bottom = 15, Width = 64, Height = 64}
	ctx:Device({})
	cell:GetPropertyChangedSignal("AbsoluteSize"):Fire() -- the engine's relayout: scaleText re-fits
	ctx:Flush()
	check(S.Cell() == cell and #S.Gui:GetChildren() == 1, "resized, never re-mounted")
	check(cell.Position == UDim2.new(1, -237, 1, -15) and cell.Size == UDim2.fromOffset(64, 64), "the tablet slot")
	check(stroke.Color == P.Coral and stroke.Thickness == thickness,
		"C8: a resize keeps the paint, and the template's ScaledSize thickness is never written")
	ctx:Device({Touch = false})
	check(not cell.Visible and not cell.Active and ctx.Registered.FlashlightPower == nil, "a flip to PC hides and unregisters it")
	ctx:Device({Touch = true})
	check(ctx.Registered.FlashlightPower == cell and cell.Visible and cell.Active, "a flip back draws and registers it again")
end

do -- every state on the real nodes, in the real palette; the outline is Coral only at EMPTY
	local _, S, P = setup({touch = true})
	local CASES = {
		{"full, on", {Fraction = 1, On = true}, "LIGHT", "Cream", 5, "Cream", "Line"},
		{"full, off: on / off is not drawn (D10)", {Fraction = 1}, "LIGHT", "Cream", 5, "Cream", "Line"},
		{"0.6", {Fraction = 0.6, On = true}, "LIGHT", "Cream", 3, "Cream", "Line"},
		{"0.4: LOW in Amber", {Fraction = 0.4, On = true}, "LOW", "Amber", 2, "Amber", "Line"},
		{"0.2: LOW in Amber", {Fraction = 0.2, On = true}, "LOW", "Amber", 1, "Amber", "Line"},
		{"0.2, off and charging", {Fraction = 0.2, Charging = true}, "LOW", "Amber", 1, "Amber", "Line"},
		{"empty", {Fraction = 0.03, Empty = true, Charging = true}, "LIGHT", "Cream", 0, "Cream", "Coral"},
		{"refused", {Fraction = 0.03, Empty = true, Refused = true}, "LOW", "Coral", 1, "Coral", "Line"},
		{"refused, recharged past the floor", {Fraction = 0.08, Charging = true, Refused = true}, "LOW", "Coral", 1, "Coral", "Line"},
		{"the refusal over: its own case again", {Fraction = 0.08, Charging = true}, "LOW", "Amber", 1, "Amber", "Line"},
		{"wide: not drawn (D12)", {Fraction = 0.9, On = true, Advanced = true}, "LIGHT", "Cream", 5, "Cream", "Line"},
		{"focused: not drawn (D12)", {Fraction = 0.9, On = true, Advanced = true, Focused = true}, "LIGHT", "Cream", 5, "Cream", "Line"},
		{"low beats focused", {Fraction = 0.2, On = true, Advanced = true, Focused = true}, "LOW", "Amber", 1, "Amber", "Line"},
		{"full again after empty", {Fraction = 1, On = true}, "LIGHT", "Cream", 5, "Cream", "Line"},
	}
	for _, case in ipairs(CASES) do
		look(S, P, case[2], case[3], case[4], case[5], case[6], case[7], case[1])
	end
end

do -- the gate: hidden and inactive while spectating, under each screen-owning modal, escaped, out of a round, dead
	local ctx, S = setup({touch = true})
	local cell = S.Cell()
	check(cell.Visible and cell.Active, "live to start with")
	local function down(message) check(not cell.Visible and not cell.Active, message .. ": hidden and inactive") end
	local function up(message) check(cell.Visible and cell.Active, message .. ": drawn and live again") end
	ctx.Player:SetAttribute("Spectating", true); down("spectating (D11)")
	ctx.Player:SetAttribute("Spectating", nil); up("spectating over")
	check(#MODALS == 8, "UIDevice lists the eight screen-owning modals")
	for _, name in ipairs(MODALS) do
		-- UIDevice fires Changed (forced) on each of them; the cell listens to nothing else for them (D13)
		ctx.Player:SetAttribute(name, true); ctx:Device({}); down(name)
		ctx.Player:SetAttribute(name, nil); ctx:Device({}); up(name .. " closed")
	end
	ctx.Player:SetAttribute("Escaped", true); down("escaped")
	ctx.Player:SetAttribute("Escaped", nil); up("back")
	ctx.Player:SetAttribute("InRound", false); down("out of a round")
	ctx.Player:SetAttribute("InRound", true); up("a round again")
	ctx.Player.CharacterAdded:Fire(ctx.Character)
	ctx.Humanoid.Health = 0; ctx.Humanoid.Died:Fire(); down("dead")
end

do -- input on the cell: a tap toggles, a second press inside 0.2 s is ignored, a 0.45 s hold focuses
	local ctx, S = setup({touch = true})
	ctx:Advance(1)
	local cell, calls = S.Cell(), S.Calls
	local function press(kind, hold)
		local input = {UserInputType = Enum.UserInputType[kind or "Touch"]}
		cell.InputBegan:Fire(input)
		ctx:Advance(hold or 0.05)
		ctx.UIS.InputEnded:Fire(input)
	end
	press(); check(calls.Toggle == 1 and calls.Focus == 0, "a tap toggles")
	ctx:Advance(0.1); press(); check(calls.Toggle == 1, "a second tap 0.15 s later, inside 0.2 s, is ignored")
	ctx:Advance(0.2); press(); check(calls.Toggle == 2, "after 0.2 s a tap toggles again")
	ctx:Advance(0.3); press("Touch", 0.5)
	check(calls.Toggle == 3 and calls.Focus == 0, "without Advanced Equipment a long hold is a tap")
	ctx.Player:SetAttribute("ZyntraOwnsAdvancedEquipment", true)
	ctx:Advance(0.3); press("Touch", 0.5)
	check(calls.Focus == 1 and calls.Toggle == 3, "with Advanced Equipment a 0.45 s hold focuses and does not toggle")
	ctx:Advance(0.3); press("Touch", 0.3)
	check(calls.Toggle == 4 and calls.Focus == 1, "a shorter press still toggles")
	ctx:Advance(0.3); press("MouseButton1"); check(calls.Toggle == 4, "a mouse click is not a touch")
	ctx.Workspace:SetAttribute("ForceTouchUI", true)
	ctx:Advance(0.3); press("MouseButton1"); check(calls.Toggle == 5, "the Studio ForceTouchUI mouse counts")
end

do -- a place without HUD_Touch: nothing drawn, nothing registered, one warning by path (D14)
	local ctx, S = setup({touch = true, skip = {HUD_Touch = true}})
	ctx:Device({})
	S.Paint({Fraction = 0.5, On = true})
	check(S.Cell() == nil and #S.Gui:GetChildren() == 0, "no template: nothing drawn")
	check(next(ctx.Registered) == nil, "and nothing registered")
	check(ctx:Warned("[RoundHud] missing template: HUD_Touch/TouchCluster/FlashlightPower") == 1, "warned by path, once")
end

do -- a place without RoundHud: no cell and no error (C3: looked up, never waited for)
	local ctx, S = setup({touch = true, noRoundHud = true})
	ctx:Device({})
	S.Paint({Fraction = 1})
	check(S.Cell() == nil and next(ctx.Registered) == nil, "no RoundHud: no cell")
end

print("Flashlight LIGHT cell: " .. checks .. " checks passed (real RoundHud, real HUD_Touch import)")
'''


def static_checks(client):
    for start, stop in ((LIGHT_MOUNT_START, LIGHT_MOUNT_END), (LIGHT_INPUT_START, LIGHT_INPUT_END)):
        block = section(client, start, stop)
        assert all(ord(ch) < 128 for ch in block), "%s must be ASCII-only (owner, 2026-10-08)" % start
    import re
    for name in RETIRED:
        assert not re.search(r"\b%s\b" % name, client), "the retired torch code is back: " + name
    gate = section(client, "local function flashlightTargetAvailable()", "\nend\n")
    assert "UIDevice.ScreenOwningModalOpen()" in gate, "D13: the gate reads UIDevice's one modal predicate"
    for name in PRIVATE_MODALS:
        assert 'GetAttribute("%s")' % name not in gate, "D13: no private modal list in the gate: " + name
    assert "UIDevice.SetInteractive(lightCell" in client, "applyFlashlightTouchTarget writes the cell"
    assert client.index(LIGHT_MOUNT_START) > client.index(WIDGET_END), "the mount block follows B1's widget"
    assert client.index(LIGHT_INPUT_START) > client.index("local function toggleFocus()"), \
        "C2: the input block sees toggle and toggleFocus"
    mount = section(client, LIGHT_MOUNT_START, LIGHT_MOUNT_END)
    assert "WaitForChild" not in mount, "C3: the mount never waits"
    # C3 (owner, 2026-10-08): the lookups run after initial replication, or a slow join finds no
    # RoundHud and silently mounts nothing.
    assert "if not game:IsLoaded() then game.Loaded:Wait() end" in mount \
        and mount.index("game.Loaded:Wait()") < mount.index('RS:FindFirstChild("RoundHud")'), \
        "C3: the mount waits for game.Loaded before its FindFirstChild lookups"


def light_program(client):
    import re
    modals = re.search(r"local SCREEN_OWNING_MODALS = \{(.*?)\}", UIDEVICE.read_text(encoding="utf-8"), re.S)
    assert modals, "UIDevice's SCREEN_OWNING_MODALS"
    names = re.findall(r'"(\w+)"', modals.group(1))
    sources = {name: path.read_text(encoding="utf-8") for name, path in hud_test.SOURCES.items()}
    sources["LightCellSection"] = (LIGHT_PRELUDE + section(client, WIDGET_START, WIDGET_END)
        + section(client, LIGHT_MOUNT_START, "local function setLights(") + LIGHT_TOGGLES
        + section(client, LIGHT_INPUT_START, "UIS.InputBegan:Connect") + LIGHT_EXPORTS)
    inject = "local SOURCES = {\n%s\n}\nlocal TREES = %s\n" % (
        ",\n".join("%s = %s" % (name, hud_test.long_string(text)) for name, text in sources.items()),
        hud_test.lua(hud_test.trees()))
    harness = hud_test.HARNESS.read_text(encoding="utf-8")
    assert "--@@INJECT@@" in harness
    tests = LIGHT_TESTS.replace("__MODALS__", hud_test.lua(names))
    return harness.replace("--@@INJECT@@", inject, 1) + "\n" + tests


def run(binary, program, name):
    with tempfile.TemporaryDirectory(prefix="flashlight-control-") as directory:
        path = Path(directory) / name
        path.write_text(program, encoding="utf-8")
        result = subprocess.run([binary, str(path)], capture_output=True, text=True, timeout=120)
    if result.returncode != 0 or "checks passed" not in result.stdout:
        print(result.stdout.strip()[-4000:])
        print(result.stderr.strip()[-4000:])
        raise SystemExit("test_flashlight_player_control FAILED (%s)" % name)
    print(result.stdout.strip().splitlines()[-1])


def widget_program(client):
    widget = section(client, WIDGET_START, WIDGET_END)
    assert all(ord(ch) < 128 for ch in widget), "the widget section must be ASCII-only (owner, 2026-10-08)"
    sources = {name: path.read_text(encoding="utf-8") for name, path in hud_test.SOURCES.items()}
    sources["FlashlightWidgetSection"] = WIDGET_PRELUDE + widget + WIDGET_EXPORTS
    inject = "local SOURCES = {\n%s\n}\nlocal TREES = %s\n" % (
        ",\n".join("%s = %s" % (name, hud_test.long_string(text)) for name, text in sources.items()),
        hud_test.lua(hud_test.trees()))
    harness = hud_test.HARNESS.read_text(encoding="utf-8")
    assert "--@@INJECT@@" in harness
    return harness.replace("--@@INJECT@@", inject, 1) + "\n" + WIDGET_TESTS


def main():
    binary = os.environ.get("LUAU_BIN") or shutil.which("luau")
    if not binary:
        raise SystemExit("Set LUAU_BIN or put luau on PATH; no tests executed.")
    compiler = os.environ.get("LUAU_COMPILE_BIN") or str(Path(binary).with_name("luau-compile.exe"))
    if Path(compiler).exists():
        subprocess.run([compiler, "--null", str(CLIENT)], check=True, capture_output=True)
    else:
        print("luau-compile not found; compile check skipped.")
    client = CLIENT.read_text(encoding="utf-8")
    replacements = {
        "__SERVER__": SERVER.read_text(encoding="utf-8"),
        "__BATTERY_STATE__": section(client, "local BATTERY_BASE", "-- The flashlight gui."),
        "__WIDGET__": section(client, WIDGET_START, WIDGET_END),
        "__LIGHT_CELL__": section(client, LIGHT_MOUNT_START, "local function setLights("),
        "__CLIENT_CONTROL__": section(client, "local function setLights(", "-- ── teammates' flashlights"),
        "__MATE_HEARTBEAT__": section(client, "-- drive every mate beam", "-- DevCheats owns"),
        "__BATTERY_HEARTBEAT__": client[client.index("-- DevCheats owns"):],
    }
    host = HOST
    for marker, content in replacements.items():
        host = host.replace(marker, content)
    run(binary, host, "control.luau")
    run(binary, widget_program(client), "widget.luau")
    static_checks(client)
    run(binary, light_program(client), "light.luau")


if __name__ == "__main__":
    main()
