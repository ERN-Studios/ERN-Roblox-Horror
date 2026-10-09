"""Execute UIRegression's real shared-HUD borrow/restore/residue and error cleanup.

The production RoundHud runs against the actual Framewisp PC/touch imports. The
borrowed-state code and TouchTargetMatrix body are extracted unchanged, rather
than reimplemented. Engine font/rendering and native input remain Studio checks.
"""

import os
from pathlib import Path
import shutil
import subprocess
import tempfile

from test_round_hud import HARNESS, ROOT, SOURCES, long_string, lua, trees

REGRESSION = ROOT / "ReplicatedStorage/UIRegression.ModuleScript.lua"


def section(text, start, end):
    begin = text.index(start)
    return text[begin:text.index(end, begin)]


def extracted():
    source = REGRESSION.read_text(encoding="utf-8")
    return r'''
local Players = game:GetService("Players")
local UIDevice = require(game:GetService("ReplicatedStorage"):WaitForChild("UIDevice"))
local Hud = require(game:GetService("ReplicatedStorage"):WaitForChild("RoundHud"))
local Fit, UIRegression = {Compact = true}, {}
local GuiService = {GetInsetArea=function() return {Min=Vector2.zero,Max=Vector2.new(1920,1080)} end}
local ENGINE_LAID_OUT = {}
local LONG_DISPATCH_CUE = "TEST CAPTION"
function Fit.beat() end
function Fit.takeStolenNote() return nil end
local function touchTargetProblems() return {} end
''' + section(source, "local ENGINE_GUIS =", "-- Panels whose INTERNAL") + section(
        source, "local function isOverlay", "-- Collect every visible top-level") + section(
        source, "function UIRegression.Scan()", "-- Flatten a panel") + section(
        source, "local INTERNAL_PANELS =", "-- Patterns that name a key") + section(
        source, "function Fit.compassBearing", "local function rectsOverlap") + section(
        source, "local function rectsOverlap", "-- Kept as a non-mutating") + section(
        source, "function UIRegression.PassiveReaderCaptionSafe()", "function UIRegression.Check()") + section(
        source, "local function playerGui()", "-- `inRound` hides") + section(
        source, "local function resetScenario", "local function revealGui") + section(
        source, "local function revealGui", "local LONG_DISPATCH_CUE") + section(
        source, "function UIRegression.Scenarios()", "-- What the completion overlay") + section(
        source, "function Fit.hudProbe()", "function Fit.bodyCompletionContract()") + section(
        source, "local REQUIRED_GUIS =", "-- Responsive-layout matrices") + section(
        source, "local BORROWED_WORKSPACE_ATTRIBUTES", "-- Apply a device AND WAIT") + section(
        source, "function UIRegression.ScreenGuiFrame", "-- Every queue-modal row") + section(
        source, "local TOUCH_DEVICES =", "function UIRegression.TouchTargetMatrix") + r'''
function Fit.anchorProblems() return {} end
function UIRegression.Check()
    return {Rects={},Groups={},KeyboardBindings={},Passed=true,Offscreen={},Overlaps={},MovementZoneHits={},InternalOverlaps={}}
end
return {Fit=Fit,UIRegression=UIRegression,Reset=resetScenario,Overlap=rectsOverlap}
'''


TESTS = r'''
local function start(opts)
    local ctx=context(opts)
    ctx.Player:SetAttribute("InRound",true)
    local character=newInstance("Model","Character")
    local hum=newInstance("Humanoid","Humanoid"); hum.Health,hum.Parent=100,character
    local hrp=newInstance("Part","HumanoidRootPart"); hrp.Position,hrp.Parent=Vector3.new(),character
    ctx.Player.Character=character
    ctx.Workspace:SetAttribute("RoundActive",true)
    ctx.Workspace:SetAttribute("SelectedLevel",3)
    ctx.Workspace.CurrentCamera={CFrame={LookVector=Vector3.new(0,0,-1)}}
    local Hud=ctx:Require("RoundHud")
    local probe=newInstance("BindableFunction","UIRegressionRoundHudProbe")
    probe.Invoke=function(_,op,data)
        if op=="capture" then return Hud.CaptureTestState()
        elseif op=="restore" then return Hud.RestoreTestState(data)
        elseif op=="snapshot" then return Hud.LastObjective()
        elseif op=="setobjective" then return Hud.SetObjective(data)
        elseif op=="feed" then return Hud.Feed(data)
        elseif op=="caption" then return Hud.Caption(data,"test cue") end
    end
    probe.Parent=Hud.Gui()
    local extracted=ctx:Require("RegressionSharedSection")
    local defaultLayout=ctx.UIDevice.Layout
    ctx.UIDevice.Layout=function()
        local layout=defaultLayout()
        local viewport=ctx.Workspace:GetAttribute("UIRegressionViewport") or ctx.Viewport
        layout.Width,layout.Height,layout.Viewport=viewport.X,viewport.Y,viewport
        layout.IsTouch=ctx.Workspace:GetAttribute("ForceTouchUI")==true
        layout.Class,layout.Inset="test",Vector2.zero
        return layout
    end
    return ctx,Hud,extracted.Fit,extracted.UIRegression,extracted.Reset
end
local function state(count)
    return {Level=3,Title="REAL ORIGINAL",Count=count or 2,Goal=5,Tag="CDS",Lines={"Original advice."}}
end
local function clean(Fit,saved,label)
    local problems=Fit.residue(saved)
    check(#problems==0,label..": "..table.concat(problems,"; "))
end
local function bad(Fit,saved,fragment,label)
    local problems=Fit.residue(saved)
    local found=false
    for _,problem in ipairs(problems) do if problem:find(fragment,1,true) then found=true end end
    check(found,label..": "..table.concat(problems,"; "))
end

do -- nil is a captured semantic state, not permission to leave a test counter.
    local ctx,Hud,Fit=start()
    local saved=Fit.borrow()
    check(saved.HudState.LastObjective==nil,"empty LastObjective captured")
    Hud.SetObjective(state(99)); ctx:Flush()
    bad(Fit,saved,"LastObjective","nil snapshot detects leftover fixture")
    Fit.restore(saved); ctx:Flush()
    check(Hud.LastObjective()==nil,"restore clears fixture LastObjective")
    clean(Fit,saved,"nil state restored")
end

do -- immutable snapshot equality, named-root remeasurement and caller-owned state.
    local ctx,Hud,Fit=start()
    Hud.SetObjective(state()); ctx:Flush()
    local oldRoot=Hud.Gui():FindFirstChild("ObjectiveCard")
    local sentinel=newInstance("TextButton","CallerOwned"); sentinel.Parent=Hud.Gui()
    sentinel.Size=UDim2.fromOffset(44,44)
    local saved=Fit.borrow()
    check(saved.Guis.RoundHud.Children[oldRoot]==nil,"shared roots excluded from stale identity snapshot")
    check(saved.Guis.RoundHud.Children[sentinel]~=nil,"caller-owned roots stay fully borrowed")
    Hud.SetObjective(state(4)); sentinel.Visible,sentinel.Active=false,false
    Fit.restore(saved); ctx:Flush()
    local rebuilt=Hud.Gui():FindFirstChild("ObjectiveCard")
    check(rebuilt~=oldRoot and not oldRoot.Parent,"real restore remounts objective")
    check(Hud.LastObjective()~=saved.HudState.LastObjective,"semantic comparison permits copied table identity")
    clean(Fit,saved,"copied original state and remounted geometry")
    rebuilt.AbsolutePosition=Vector2.new(12,0)
    bad(Fit,saved,".Left geometry","actual new-root geometry drift detected")
    rebuilt.AbsolutePosition=Vector2.zero
    rebuilt.Visible=false
    bad(Fit,saved,".Visible","actual new-root visibility drift detected")
    rebuilt.Visible=true
    Hud.SetObjective(state(4)); ctx:Flush()
    bad(Fit,saved,"LastObjective","changed Counter detected semantically")
    Fit.restore(saved); ctx:Flush()
    clean(Fit,saved,"corrupt fixture removed")
end

do -- original absolute lifetimes expire during a lane; restore never revives them.
    local ctx,Hud,Fit=start({touch=true,viewport=Vector2.new(956,440),safe={Left=0,Top=0,Right=956,Bottom=440}})
    Hud.SetObjective(state()); Hud.Feed({Kind="TEAM",Detail="original",Key="original"})
    Hud.Caption("COMMAND CENTER","Original cue",3.5)
    Hud.Detector({Proximity="HIGH",Range=10},ctx.Now+3)
    ctx:Flush()
    local saved=Fit.borrow()
    Hud.SetObjective(state(99)); Hud.Feed({Kind="TEAM",Detail="fixture",Key="fixture"})
    ctx:Advance(7); ctx.RunService.Heartbeat:Fire(7); ctx:Flush()
    Fit.restore(saved); ctx:Flush()
    clean(Fit,saved,"expired lanes and touch collapse are legitimate")
    local capture=Hud.CaptureTestState()
    check(#capture.Feed.Entries==0 and capture.Caption.Text==nil,"expired feed/caption not restarted")
    local caption=Hud.Gui():FindFirstChild("Caption")
    check(not caption or not caption.Visible,"expired caption cannot reappear")
    check(Hud.Gui():FindFirstChild("ObjectiveCard").Size.Y.Offset==44,"expired expansion remains collapsed")
end

do -- both TouchTarget sweeps fail after mutations; the actual lane still restores everything.
    local ctx,Hud,Fit,UIRegression=start()
    Hud.SetObjective(state()); ctx:Flush()
    local screen=newInstance("ScreenGui","ZyntraShopL4"); screen.Parent=ctx.PlayerGui
    local button=newInstance("TextButton","BorrowedButton"); button.Parent=screen
    local scroll=newInstance("ScrollingFrame","BorrowedScroll"); scroll.CanvasPosition=Vector2.zero; scroll.Parent=screen
    ctx.Workspace:SetAttribute("ForceTouchUI",false)
    ctx.Player:SetAttribute("DevPartyDown",nil)
    local saved=Fit.borrow()
    local setups=0
    -- Real task.wait settles queued Stack reflow before the lane's residue
    -- assertion. The stock manual-clock harness deliberately leaves wait inert.
    ctx.Task.wait=function() ctx:Flush() end
    UIRegression.Scenarios=function()
        return {{Name="forced-error",TouchTargets={"BorrowedButton"},Setup=function()
            setups+=1
            ctx.Workspace:SetAttribute("SelectedLevel",4)
            ctx.Player:SetAttribute("DevPartyDown",15)
            ctx.Player:SetAttribute("ZyntraStoreOpen",true)
            screen.Enabled=false; button.Visible=false; button.Active=false
            scroll.CanvasPosition=Vector2.new(0,45)
            error("intentional scenario failure")
        end}}
    end
    local report,failures=Fit.bodyTouchTargetMatrix()
    ctx:Flush()
    check(setups==2,"error occurred in both real matrix sweeps")
    check(failures==2 and report:find("intentional scenario failure",1,true),"lane reports both failed sweeps: "..report)
    clean(Fit,saved,"TouchTarget fullscope error cleanup")
    check(Hud.LastObjective().Counter.Current==2,"TouchTarget restores real preexisting counter")
    check(screen.Enabled and button.Visible and button.Active and scroll.CanvasPosition==Vector2.zero,
        "TouchTarget restores nested GUI flags, interactivity and scrolling")
end

do -- Same-name CanvasGroup + imported clone is one panel, with faded ancestors excluded.
    local ctx,Hud,Fit,UIRegression=start()
    local outer=newInstance("CanvasGroup","ResultsWindow"); outer.Parent=Hud.Gui()
    local inner=newInstance("Frame","ResultsWindow"); inner.Size=UDim2.fromOffset(360,120); inner.Parent=outer
    local label=newInstance("TextLabel","Ink"); label.Text="Visible ink"; label.Size=UDim2.fromOffset(80,20); label.Parent=inner
    local groups=UIRegression.Children()
    check(#groups==1 and #groups[1].Children==1,"same-name imported panel measured once")
    outer.GroupTransparency=1
    check(#UIRegression.Children()==0,"fully faded CanvasGroup excludes nested imported panel")
    check(UIRegression.PassiveReaderCaptionSafe()==false,"retired reader/caption pair grants no movement-zone exemption")
end

do -- The actual scenario reset must not disable the shared owner or blank callers' mounts.
    local ctx,Hud,Fit,UIRegression,reset=start()
    ctx.Task.wait=function() ctx:Flush() end
    local marker=newInstance("Frame","NoiseMarker"); marker.Size=UDim2.fromOffset(20,20); marker.Parent=Hud.Gui()
    Hud.SetObjective(state()); Hud.Feed({Kind="TEAM",Detail="previous row"}); ctx:Flush()
    reset(true); ctx:Flush()
    check(Hud.Gui().Enabled and marker.Visible and marker.Parent==Hud.Gui(),"real reset preserves shared GUI and caller-owned marker")
    check(Hud.Gui():FindFirstChild("ObjectiveCard")==nil,"real reset clears preceding objective fixture")
    check(#Hud.CaptureTestState().Feed.Entries==0,"real reset clears preceding feed fixture")
    Fit.stageRoundObjective(3,true,true); ctx:Flush()
    local measured={}
    for _,rect in ipairs(UIRegression.Scan().Rects) do measured[rect.Path]=true end
    check(measured["RoundHud.ObjectiveCard"] and measured["RoundHud.Caption"],"real stage/scan measures actual objective and caption")
    check(measured["RoundHud.NoiseMarker"],"scan measures caller-owned B3 marker after reset")
end

do -- MissingGuis tests current owner scripts; the retired per-level surfaces are absent by design.
    local ctx,Hud,Fit,UIRegression=start()
    for _,name in ipairs({"RoundGui","LevelOneGuideGui","StaminaGui","FlashlightPopup","SpectateGui","ZyntraStore",
        "Level3TableHideUI","RoundHudThreat","FoundFootageHUD","RoundExitGui","ZyntraShopL4"}) do
        newInstance("ScreenGui",name).Parent=ctx.PlayerGui
    end
    check(#UIRegression.MissingGuis()==0,"retired objective/alert GUIs not required")
    Hud.Gui().Parent=nil
    check(table.find(UIRegression.MissingGuis(),"RoundHud")~=nil,"missing actual shared HUD owner is a startup failure")
end

do -- Fixture layout policy and native engine parity use their own frames, including Scale=1.
    local ctx,Hud,Fit,UIRegression=start()
    local gui=Hud.Gui(); gui.AbsolutePosition=Vector2.new(0,-58)
    local root=newInstance("Frame","OffsetFixture"); root.Position=UDim2.fromOffset(500,76)
    root.Size=UDim2.fromOffset(360,100); root.Parent=gui
    local synthetic=UIRegression.ResolveRect(root,Vector2.new(705,338),0,{Left=0,Top=-36,Width=705,Height=338})
    local native=Fit.engineRect(root)
    check(synthetic.Top==40 and native.Top==18,"fixture/native origins remain independent")
    root.AbsolutePosition=Vector2.new(500,18)
    check(native.Left==root.AbsolutePosition.X and native.Top==root.AbsolutePosition.Y,"native parity compares engine origin")
    local cover=newInstance("Frame","ScaleCover"); cover.Size=UDim2.fromScale(1,1); cover.Parent=gui
    local child=newInstance("Frame","Centred"); child.Size=UDim2.fromOffset(100,40)
    child.Position=UDim2.fromScale(.5,.5); child.AnchorPoint=Vector2.new(.5,.5); child.Parent=cover
    local nativeChild=Fit.engineRect(child)
    local fixtureChild=UIRegression.ResolveRect(child,Vector2.new(705,338),0,{Left=0,Top=-36,Width=705,Height=338})
    check(nativeChild.Left==ctx.Viewport.X/2-50 and nativeChild.Top==-58+ctx.Viewport.Y/2-20,
        "Scale=1 native ancestry resolves at actual rendered size")
    check(fixtureChild.Left==302.5 and fixtureChild.Top==113,"fixture ancestry retains stated dimensions")
end

do -- Transparent label padding may overlap; actual ink overlap still fails the unchanged predicate.
    local ctx,Hud,Fit,UIRegression=start()
    local overlap=ctx:Require("RegressionSharedSection").Overlap
    local label=newInstance("TextLabel","Countdown"); label.Text="NEXT LEVEL BEGINS IN"; label.TextSize=14
    label.Parent=Hud.Gui()
    label.BackgroundTransparency=1; label.Size=UDim2.fromOffset(260,24); label.AbsolutePosition=Vector2.zero
    label.TextXAlignment,label.TextYAlignment=Enum.TextXAlignment.Left,Enum.TextYAlignment.Center
    local number=newInstance("TextLabel","CountNum"); number.Text="10"; number.TextSize=28
    number.Parent=Hud.Gui()
    number.BackgroundTransparency=1; number.Size=UDim2.fromOffset(60,42); number.AbsolutePosition=Vector2.new(232,0)
    number.TextXAlignment,number.TextYAlignment=Enum.TextXAlignment.Center,Enum.TextYAlignment.Center
    local ink=Fit.drawnRect(label)
    check(not overlap(ink,Fit.drawnRect(number)),"non-overlapping ink in overlapping text boxes passes")
    number.AbsolutePosition=Vector2.new(80,0)
    check(overlap(ink,Fit.drawnRect(number)),"real overlapping glyph bounds still fail")
    local button=newInstance("TextButton","Action"); button.Size=UDim2.fromOffset(260,52); button.Text="GO"
    button.Parent=Hud.Gui()
    button.BackgroundTransparency=1
    check(Fit.drawnRect(button).Right==260,"interactive button keeps full hit bounds")
    label.BackgroundTransparency=0
    check(Fit.drawnRect(label).Right==260,"opaque text surface keeps full bounds")
    label.BackgroundTransparency=1
    local stroke=newInstance("UIStroke","UIStroke"); stroke.Transparency=0; stroke.Parent=label
    check(Fit.drawnRect(label).Right==260,"stroked text surface keeps full bounds")
end

do -- Lobby-only chip contracts never falsify server round authority or move a body into a lobby.
    local ctx,Hud,Fit=start()
    local lobby=newInstance("Model","ServerLobby")
    lobby.GetBoundingBox=function() return {Position=Vector3.new()},Vector3.new(20,20,20) end
    lobby.Parent=ctx.Workspace
    check(not Fit.liveLobbyEligible(false),"real active round cannot masquerade as lobby")
    ctx.Workspace:SetAttribute("RoundActive",false)
    check(not Fit.liveLobbyEligible(true),"original InRound prevents lobby admission")
    check(Fit.liveLobbyEligible(false),"physical lobby body with no round is admitted")
    ctx.Workspace:SetAttribute("RoundLoadingState","loading")
    check(not Fit.liveLobbyEligible(false),"real loading blocks lobby admission")
    ctx.Workspace:SetAttribute("RoundLoadingState",nil)
    ctx.Player.Character.HumanoidRootPart.Position=Vector3.new(100,0,0)
    check(not Fit.liveLobbyEligible(false),"body outside lobby cannot force chip contract")
    local spawn=newInstance("SpawnLocation","LobbySpawn"); spawn.Parent=lobby
    spawn:SetAttribute("LobbySpawnFloorModelName","LobbyReimaginedPreview")
    local revised=newInstance("Model","LobbyReimaginedPreview"); revised.Parent=ctx.Workspace
    revised:SetAttribute("LobbyReimaginedOwned",true); revised:SetAttribute("Ready",true)
    revised.GetBoundingBox=function() return {Position=Vector3.new(100,0,0)},Vector3.new(20,20,20) end
    check(Fit.liveLobbyEligible(false),"server-selected ready lobby determines physical admission")
end

do -- The compass bearing is one joined graphic; its union still must clear the metre readout.
    local ctx,Hud,Fit,UIRegression=start()
    local original=state(); original.Compass={State="locked",Target=Vector3.new(0,0,-35.71)}
    Hud.SetObjective(original); ctx:Flush()
    local root=Hud.Gui():FindFirstChild("ObjectiveCard")
    local readout=find(root,"Compass/Readout"); readout.AbsolutePosition=Vector2.new(250,0)
    local groups=UIRegression.Children()
    local bearing,metres,count
    count=0
    for _,child in ipairs(groups[1].Children) do
        if child.Name=="Bearing" then bearing=child; count+=1 end
        if child.Name=="Readout" then metres=child end
        check(not child.Path:find(".Ticks.",1,true) and child.Name~="Centre" and child.Name~="Chevron" and child.Name~="Baseline",
            "joined compass marks are not independent collision controls")
    end
    local overlap=ctx:Require("RegressionSharedSection").Overlap
    check(count==1 and metres~=nil,"one actual bearing union and a separate readout measured")
    check(not overlap(bearing,metres),"separate compass graphic and metre ink pass")
    readout.AbsolutePosition=Vector2.zero
    groups=UIRegression.Children()
    for _,child in ipairs(groups[1].Children) do if child.Name=="Readout" then metres=child end end
    check(overlap(bearing,metres),"real bearing/readout ink collision still fails")
end

do -- Passive shared copy may cross activation space, but active input and drawn controls may not.
    local ctx,Hud,Fit,UIRegression=start()
    local row=newInstance("Frame","Caption"); row.Active=false; row.Parent=Hud.Gui()
    row.Size=UDim2.fromOffset(100,44); row.AbsolutePosition=Vector2.new(20,100)
    local label=newInstance("TextLabel","Text"); label.Active=false; label.Text="Command center"; label.Parent=row
    check(Fit.passiveSharedRow(row,"RoundHud"),"shared passive row is admitted")
    local zones={Thumbstick={Left=0,Top=80,Right=260,Bottom=374},
        Controls={Left=500,Top=220,Right=666,Bottom=374},Jump={Left=550,Top=280,Right=620,Bottom=350}}
    ctx.UIDevice.Layout=function() return {Zones=zones} end
    ctx.UIDevice.OverlapsMovementZone=function() return "Thumbstick" end
    local rect={Left=20,Top=100,Right=120,Bottom=144,PassiveThumbstick=true}
    check(Fit.movementZoneHit(rect)==nil,"passive caption clears activation-only collision")
    rect.Right=550; rect.Bottom=250
    check(Fit.movementZoneHit(rect)=="Controls","passive row still fails drawn control region")
    zones.Controls={Left=666,Top=374,Right=666,Bottom=374}; rect.Right=600; rect.Bottom=310
    check(Fit.movementZoneHit(rect)=="Jump","passive row still fails jump region")
    row.Active=true
    check(not Fit.passiveSharedRow(row,"RoundHud"),"Active input shield receives no exemption")
    row.Active=false
    local button=newInstance("TextButton","UnexpectedAction"); button.Parent=row
    check(not Fit.passiveSharedRow(row,"RoundHud"),"interactive descendant receives no exemption")
    button.Parent=nil; row.Name="LeaveHiding"
    check(not Fit.passiveSharedRow(row,"RoundHud"),"hiding action cannot inherit caption exemption")
    row.Name="Caption"
    check(not Fit.passiveSharedRow(row,"SpectateGui"),"spectate cannot inherit caption exemption")
    rect.PassiveThumbstick=false
    check(Fit.movementZoneHit(rect)=="Thumbstick","actual interactive targets retain activation collision")
end

do -- Gameplay retains a physical living round; lobby, dead, escaped and watched states cannot fake one.
    local ctx,Hud,Fit,UIRegression=start()
    ctx.Task.wait=function() ctx:Flush() end
    local store=newInstance("ScreenGui","ZyntraStore"); store.Parent=ctx.PlayerGui
    local opener=newInstance("TextButton","ZyntraOpenButton"); opener.Parent=store
    local function gameplay()
        for _,scenario in ipairs(UIRegression.Scenarios()) do if scenario.Name=="gameplay" then scenario.Setup(); return end end
        error("gameplay scenario missing")
    end
    check(Fit.liveRoundEligible(true,false,false),"physical living round admitted")
    gameplay(); ctx:Flush()
    check(ctx.Player:GetAttribute("InRound")==true and not opener.Visible,"live gameplay preserves round and hides lobby rail")
    check(ctx.Workspace:GetAttribute("RoundActive")==true,"gameplay never changes server round authority")
    ctx.Player:SetAttribute("InRound",false); gameplay(); ctx:Flush()
    check(ctx.Player:GetAttribute("InRound")==nil and opener.Visible,"nonparticipant gameplay keeps lobby composition")
    ctx.Player.Character.Humanoid.Health=0
    check(not Fit.liveRoundEligible(true,false,false),"dead body rejected")
    ctx.Player.Character.Humanoid.Health=100
    check(not Fit.liveRoundEligible(true,true,false) and not Fit.liveRoundEligible(true,false,true),"spectating and escaped rejected")
    ctx.Player.Character.HumanoidRootPart.Parent=nil
    check(not Fit.liveRoundEligible(true,false,false),"round attributes without a physical root rejected")
end

do -- An in-round reset never lends lobby-only polls a false context at its Store yield.
    local ctx,Hud,Fit,UIRegression,reset=start()
    local store=newInstance("ScreenGui","ZyntraStore"); store.Parent=ctx.PlayerGui
    local opener=newInstance("TextButton","ZyntraOpenButton"); opener.Parent=store
    local contexts={}
    ctx.Player:GetAttributeChangedSignal("InRound"):Connect(function()
        table.insert(contexts,ctx.Player:GetAttribute("InRound")==true)
    end)
    local yields=0
    ctx.Task.wait=function()
        yields+=1; table.insert(contexts,ctx.Player:GetAttribute("InRound")==true); ctx:Flush()
    end
    reset(true); ctx:Flush()
    check(yields>=2,"actual reset includes dispatch and Store signal yields")
    local remained=true
    for _,context in ipairs(contexts) do if not context then remained=false end end
    check(remained and ctx.Player:GetAttribute("InRound")==true,"live reset preserves round context across every observed mutation/yield")
    reset(); ctx:Flush()
    check(ctx.Player:GetAttribute("InRound")==nil and opener.Visible,"lobby reset still clears round context and restores rail")
end

do -- Actual results modal output is borrowed and cleared with the staged result owner.
    local ctx,Hud,Fit,UIRegression,reset=start()
    ctx.Task.wait=function() ctx:Flush() end
    ctx.Player:SetAttribute("RoundEndingOpen",true)
    local saved=Fit.borrow()
    check(saved.Player.RoundEndingOpen==true,"actual result modal is captured")
    reset(true); ctx:Flush()
    check(ctx.Player:GetAttribute("RoundEndingOpen")==false,"scenario reset clears staged result suppression")
    Fit.restore(saved); ctx:Flush()
    check(ctx.Player:GetAttribute("RoundEndingOpen")==true,"original result modal output is restored")
end

do -- Wheel circular ink clears its X while true rim/pointer collisions remain failures.
    local ctx,Hud,Fit,UIRegression=start()
    local screen=newInstance("ScreenGui","LuckyWheelGui"); screen.Parent=ctx.PlayerGui
    local shade=newInstance("Frame","WheelShade"); shade.Size=UDim2.fromScale(1,1); shade.BackgroundTransparency=1; shade.Parent=screen
    local holder=newInstance("Frame","WheelHolder"); holder.Size=UDim2.fromOffset(200,200)
    holder.BackgroundTransparency=1; holder.AbsolutePosition=Vector2.new(100,0); holder.Parent=shade
    local disc=newInstance("ImageLabel","WheelDisc"); disc.Size=UDim2.fromScale(1,1)
    disc.AbsolutePosition=holder.AbsolutePosition
    disc.BackgroundTransparency,disc.ImageTransparency=1,0; disc.Image="authored round wheel"; disc.ScaleType=Enum.ScaleType.Fit; disc.Parent=holder
    local pointer=newInstance("Frame","WheelPointer"); pointer.Size=UDim2.fromOffset(20,20)
    pointer.AbsolutePosition=Vector2.new(190,-10); pointer.Rotation=45; pointer.Parent=holder
    local close=newInstance("TextButton","CloseButton"); close.Size=UDim2.fromOffset(44,44)
    close.AbsolutePosition=Vector2.new(285,0); close.Parent=shade
    local function rectangles()
        local wheel,x
        for _,rect in ipairs(UIRegression.Scan().Rects) do
            if rect.Name=="WheelHolder" then wheel=rect elseif rect.Name=="CloseButton" then x=rect end
        end
        return wheel,x
    end
    local wheel,x=rectangles()
    local overlap=ctx:Require("RegressionSharedSection").Overlap
    check(wheel.Shape=="Circle" and #wheel.Adornments>0,"actual circular disc and protruding rotated pointer measured")
    check(x.Interactive and x.Active and x.Right-x.Left==44 and x.Bottom-x.Top==44,"wheel Close keeps complete44px hit bounds")
    check(not overlap(wheel,x),"X beyond rim passes despite overlap with empty square corner")
    close.AbsolutePosition=Vector2.new(270,20); wheel,x=rectangles()
    check(overlap(wheel,x),"actual X/circle rim collision fails")
    local pointerCollision={Left=198,Top=-14,Right=242,Bottom=-10}
    check(overlap(wheel,pointerCollision),"protruding rotated pointer ink cannot be ignored")
    disc.AbsolutePosition=Vector2.new(120,0)
    wheel,x=rectangles()
    check(wheel.Shape==nil,"misaligned disc cannot inherit holder circle geometry")
    disc.AbsolutePosition=holder.AbsolutePosition
    holder.BackgroundTransparency=0
    wheel,x=rectangles()
    check(wheel.Shape==nil,"opaque square holder receives no circular-mask shortcut")
end

do -- The real hiding fixture publishes the real InRound and Level3_Hiding gates.
    local ctx,Hud,Fit,UIRegression=start()
    local screen=newInstance("ScreenGui","Level3TableHideUI"); screen.Enabled=false; screen.Parent=ctx.PlayerGui
    ctx.Task.wait=function() ctx:Flush() end
    local hiding
    for _,scenario in ipairs(UIRegression.Scenarios()) do if scenario.Name=="hiding" then hiding=scenario end end
    hiding.Setup(); ctx:Flush()
    check(ctx.Player:GetAttribute("InRound")==true and ctx.Player:GetAttribute("Level3_Hiding")==true,
        "hiding fixture cannot mix hidden in-round UI with a lobby body")
    check(screen.Enabled and ctx.Player:GetAttribute("UIRegressionForceHiding")==true,"actual hiding UI seam remains staged")
end

print("UIRegression shared restore: "..checks.." checks passed (production seam + real imported fixtures)")
'''


def program():
    modules = {name: path.read_text(encoding="utf-8") for name, path in SOURCES.items()}
    modules["RegressionSharedSection"] = extracted()
    inject = "local SOURCES = {\n%s\n}\nlocal TREES = %s\n" % (
        ",\n".join("%s = %s" % (name, long_string(value)) for name, value in modules.items()), lua(trees()))
    harness = HARNESS.read_text(encoding="utf-8").replace("--@@INJECT@@", inject, 1)
    harness = harness.replace("fields.TextScaled = false", "fields.TextTransparency = 0\n\t\tfields.TextScaled = false", 1)
    return harness + "\n" + TESTS


def main():
    binary = os.environ.get("LUAU_BIN") or shutil.which("luau")
    if not binary:
        raise SystemExit("Set LUAU_BIN; no checks executed")
    compiler = os.environ.get("LUAU_COMPILE_BIN") or str(Path(binary).with_name("luau-compile.exe"))
    subprocess.run([compiler, "-O0", "--null", str(REGRESSION)], check=True, capture_output=True, timeout=30)
    with tempfile.TemporaryDirectory(prefix="ui-regression-shared-") as directory:
        path = Path(directory) / "checks.luau"
        path.write_text(program(), encoding="utf-8")
        result = subprocess.run([binary, str(path)], capture_output=True, text=True, timeout=120)
        if result.returncode or "checks passed" not in result.stdout:
            print(result.stdout[-3000:])
            print(result.stderr[-6000:])
            raise SystemExit("UIRegression shared restore FAILED")
        print(result.stdout.strip().splitlines()[-1])


if __name__ == "__main__":
    main()
