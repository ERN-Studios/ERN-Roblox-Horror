"""Exercise the actual controller handlers in offline Luau with hardware/UI stubs.

Extracts production sprint reconciliation, spectate input, RoundUI bindings
and UIDevice caption/modal helpers; does not reimplement their decisions.
(The Zyntra terminal's focus / ButtonB lane went with the terminal,
RECORDS_SETTINGS_L4_20261007: the L4 shop that replaces it is held to the same
contract by its own harness, artifacts/shop-ui-figma-20261005/roblox-draft/tests:
section 8 ports B passing to an open Roblox menu, a mouse open stealing no focus,
a switch to the controller taking it, and a close leaving other UI's focus alone;
sections 8 and 17 cover focus on open and B closing. Not ported, the L4 window has
no counterpart: B passing during text entry, focus restored to the opener, the
tab bar scrolled to reveal a tab.) Roblox CoreScript routing, GUI geometry and physical disconnection
still require engine/controller tests. Set LUAU_BIN or put luau on PATH.

HUD batch B2 (owner, 2026-10-08; artifacts/hud-final-20261008/b2/B2-DESIGN.md 4 and its critic
findings): NoiseReporter's touch cells. The layout pass (the lobby RUN lift only over Roblox's
jump, C14) runs in the first Luau program; static checks pin the source (no makeTouchButton /
showRunEnabled / "column", the eight-modal predicate, the D14 jump guard, the hoisted RUN toggle,
an ASCII section that never waits for the bundle); and the marked B2 section runs in the HUD
fake engine (tools/tests/hud_harness.luau) over the REAL HUD_Touch import with the real RoundHud
and ShopBinder: the mount, RUN's stamina ring (C6 truth table, C8 width key), SNEAK engaged, POV,
and a place without the bundle or without RoundHud.

HUD batch B3 (owner, 2026-10-08; artifacts/hud-final-20261008/b3/B3-DESIGN.md 4.6 and its critic
findings K1, K4, K5, K10, K12): applySpeed publishes MoveNoise compare-first in the round branch only
(first program); static checks pin the retired bar's names, the one MoveNoise write, and an ASCII
section above the speed-potion slice that never waits and writes Visible only on Winded; and the
marked B3 section runs in the HUD fake engine over the REAL HUD_PC import with the real RoundHud (A's
Fill anchor and opts.Touch): the mount, the DRAIN / WINDED / RECOVER / FULL truth table with its
opacities, placement (PC 1920, PC 1366 beside B1's kit row, spectating, the 844x390 phone corridor at
half size, 667x375's corridor too narrow for it, a flip back), paintWatched's trend (nil-safe, reset
on a target switch), and a place without HUD_PC, without a Winded node or without RoundHud.
"""

from pathlib import Path
import os
import re
import shutil
import subprocess
import sys
import tempfile

ROOT = Path(__file__).resolve().parents[2]
root = ROOT / 'StarterPlayer/StarterPlayerScripts'
noise = (root/'NoiseReporter.LocalScript.lua').read_text(encoding='utf-8')
spectate = (root/'SpectateController.LocalScript.lua').read_text(encoding='utf-8')
round_ui = (root/'RoundUI.LocalScript.lua').read_text(encoding='utf-8')
ui_device = (ROOT/'ReplicatedStorage/UIDevice.ModuleScript.lua').read_text(encoding='utf-8')
sys.path.insert(0, str(Path(__file__).resolve().parent))
import test_round_hud as hud_test  # noqa: E402  the HUD harness helpers (owner, 2026-10-08)

def between(source, start, stop):
    begin = source.index(start) + len(start)
    return source[begin:source.index(stop, begin)]


def section(source, start, stop):
    return start + between(source, start, stop)

common = r'''
local checks = 0
local function expect(value, wanted, message)
    checks += 1
    assert(value == wanted, message .. ': expected ' .. tostring(wanted) .. ', got ' .. tostring(value))
end
local function signal()
    local s = {callbacks = {}}
    function s:Connect(fn) table.insert(self.callbacks, fn); return {Disconnect=function() end} end
    function s:Fire(...) for _, fn in ipairs(self.callbacks) do fn(...) end end
    return s
end
local Enum = {
 KeyCode = {LeftShift='LeftShift', RightShift='RightShift', LeftControl='LeftControl', RightControl='RightControl', ButtonL2='ButtonL2', ButtonB='ButtonB', E='E', Q='Q', DPadLeft='DPadLeft', DPadRight='DPadRight', H='H', M='M', N='N', DPadUp='DPadUp', ButtonL1='ButtonL1'},
 UserInputType = {Touch={Name='Touch'}, Keyboard={Name='Keyboard'}, Gamepad1={Name='Gamepad1'}},
 UserInputState = {Begin='Begin', End='End'}, ContextActionResult={Pass='Pass', Sink='Sink'}, ContextActionPriority={High={Value=3000}}
}
local Vector2 = {new=function(x,y) return {X=x,Y=y} end}
'''

noise_setup = r'''
do
local active, state = true, 'walk'
local sprinting, crouching, exhausted = false, false, false
local shiftSprintHeld, touchSprintHeld, gamepadSprintHeld = false, false, false
local windowFocused, stamina = true, 100
local WALK_SPEED, SPRINT_SPEED, CROUCH_SPEED = 16,26,8
local attrs, charAttrs, keys, pads, padDown = {}, {}, {}, {}, {}
local character = {GetAttribute=function(_,k) return charAttrs[k] end,SetAttribute=function(_,k,v) charAttrs[k]=v end}
local hum = {WalkSpeed=16}
local moveNoiseWrites = 0 -- HUD B3 (D6): the MoveNoise writes applySpeed makes
local player = {GetAttribute=function(_,k) return attrs[k] end,
 SetAttribute=function(_,k,v) attrs[k]=v; if k=='MoveNoise' then moveNoiseWrites+=1 end end}
local function currentChar() return character, hum end
local function inRound() return active end
-- Stubs the current NoiseReporter slice needs: speedBoost() asks inPreview()
-- and the server clock, applySpeed() reads SelectedLevel (Level 4 carry).
local function inPreview() return false end
local workspace = {GetAttribute=function() return nil end, GetServerTimeNow=function() return 0 end}
local focused
local UIS = {WindowFocusReleased=signal(),WindowFocused=signal()}
function UIS:GetFocusedTextBox() return focused end
function UIS:IsKeyDown(k) return keys[k]==true end
function UIS:GetConnectedGamepads() return pads end
function UIS:IsGamepadButtonDown(p,k) return padDown[p]==true end
local RunService = {Heartbeat=signal()}
'''
noise_apply = section(noise, 'local function isHiding()', 'local function isEscaped()')
noise_apply += 'local function applySpeed()' + between(noise, 'local function applySpeed()', 'local function refreshCrouch()')
noise_helpers = 'local function sprintRequested()' + between(noise, 'local function sprintRequested()', 'UIS.InputBegan:Connect')
noise_heartbeat = 'RunService.Heartbeat:Connect(function(dt)' + between(noise, 'RunService.Heartbeat:Connect(function(dt)', '\tif not inRound() then') + 'end)\n'
noise_tests = r'''
local function beat() RunService.Heartbeat:Fire(1/60) end
pads={'Gamepad2'}; padDown.Gamepad2=true; beat()
expect(hum.WalkSpeed,26,'Gamepad2 starts in-round sprint')
pads={}; beat()
expect(hum.WalkSpeed,16,'disconnect without InputEnded stops in-round sprint')
expect(state,'walk','noise/stamina state repaired')
pads={'Gamepad2'}; padDown.Gamepad2=true; beat(); UIS.WindowFocusReleased:Fire(); beat()
expect(hum.WalkSpeed,16,'stale held hardware cannot reassert after focus loss')
padDown.Gamepad2=false; UIS.WindowFocused:Fire(); beat()
expect(hum.WalkSpeed,16,'return after released trigger remains walk')
keys.LeftShift=true; beat(); expect(hum.WalkSpeed,26,'physical Shift starts sprint')
keys.RightShift=true; keys.LeftShift=false; beat(); expect(hum.WalkSpeed,26,'other held Shift preserves sprint')
focused={}; beat(); expect(hum.WalkSpeed,16,'typing suppresses physical Shift')
focused=nil; keys.RightShift=false; touchSprintHeld=true; refreshSprint()
pads={'Gamepad2'}; padDown.Gamepad2=true; beat(); pads={}; beat()
expect(hum.WalkSpeed,26,'disconnect preserves independent touch RUN')
touchSprintHeld=false; refreshSprint(); active=false
pads={'Gamepad2'}; padDown.Gamepad2=true; beat(); expect(hum.WalkSpeed,26,'lobby hardware sprint')
pads={}; beat(); expect(hum.WalkSpeed,16,'lobby disconnect repairs speed')
active=true; attrs.Level3_Hiding=true; hum.WalkSpeed=0; pads={'Gamepad2'}; padDown.Gamepad2=true; beat()
expect(hum.WalkSpeed,0,'repair respects authoritative hiding lock')
expect(charAttrs.Level2_DesiredWalkSpeed,26,'repair updates lock restore target')
-- HUD B3 (D6; owner, 2026-10-08): MoveNoise is the raw state, written compare-first in the round branch
expect(attrs.MoveNoise,'sprint','MoveNoise is written before the hiding early return')
attrs.Level3_Hiding=nil; pads={}; beat()
expect(attrs.MoveNoise,'walk','walking in a round publishes MoveNoise walk')
keys.LeftShift=true; beat()
expect(attrs.MoveNoise,'sprint','Shift publishes sprint')
crouching=true; applySpeed()
expect(attrs.MoveNoise,'crouch','crouching publishes crouch')
crouching=false; exhausted=true; applySpeed()
expect(attrs.MoveNoise,'walk','winded with Shift held publishes walk')
local writes=moveNoiseWrites; applySpeed(); applySpeed()
expect(moveNoiseWrites,writes,'an unchanged state makes no second write')
exhausted=false; active=false; applySpeed()
expect(attrs.MoveNoise,'walk','the lobby branch never writes MoveNoise')
expect(moveNoiseWrites,writes,'no write in the lobby')
keys.LeftShift=false; active=true
end
'''

# B2 layout pass (owner, 2026-10-08). UIDevice's answers are stated (the phone grid of
# GRID_CONTROL_PLAN_20261008 and the engine jump zones the critic measured); the decision is
# NoiseReporter's own placeTouchControl / applyTouchControlLayout.
noise_layout = section(noise, 'local function placeTouchControl(', '\napplyTouchControlLayout()\nUIDevice.Changed')
layout_setup = r'''
do
local active = false
local function inRound() return active end
local function touchControls() return true end
local UDim2 = {new=function(xs,xo,ys,yo) return {XS=xs,XO=xo,YS=ys,YO=yo} end,
 fromOffset=function(x,y) return {XS=0,XO=x,YS=0,YO=y} end}
local screen
local gui = {}
local UIDevice = {Layout=function() return screen.Layout end}
function UIDevice.RightOffsetFor(g,x) assert(g==gui,'measured against StaminaGui'); return math.max(0, screen.Right-x) end
function UIDevice.BottomOffsetFor(g,y) assert(g==gui,'measured against StaminaGui'); return math.max(0, screen.Bottom-y) end
local touchJumpButton, touchRunButton, touchSneakButton, touchPOVButton = {}, {}, {}, {}
local touchGlowButton = nil -- a missing template (D14): skipped, never indexed
'''
layout_tests = r'''
local function slot(r,b) return {Right=r,Bottom=b,Width=52,Height=52} end
local plan = {Mode='grid', Gap=8, Slots={TouchJump=slot(12,12), TouchRunHold=slot(72,12), TouchSneakHold=slot(132,12),
 FlashlightPower=slot(192,12), ProtectionUse=slot(12,72), KitToggle=slot(72,72), TouchDropGlowstick=slot(132,72), TouchPOV=slot(192,72)}}
-- 844x390: the gui ends at the safe edge (797, 369); Roblox's jump is x 749..819, y 300..370.
screen = {Right=797, Bottom=369, Layout={ControlPlan=plan, Zones={Jump={Left=749,Right=819,Top=300,Bottom=370}}}}
applyTouchControlLayout()
expect(touchRunButton.Position.YO,-12,'844x390 lobby: RUN (x 673..725) clears the engine jump and stays in its slot (C14)')
for name,pair in pairs({JUMP={touchJumpButton,'TouchJump'},RUN={touchRunButton,'TouchRunHold'},SNEAK={touchSneakButton,'TouchSneakHold'},POV={touchPOVButton,'TouchPOV'}}) do
 local cell, s = pair[1], plan.Slots[pair[2]]
 expect(cell.AnchorPoint.X==1 and cell.AnchorPoint.Y==1,true,name..' anchors bottom-right')
 expect(cell.Position.XS==1 and cell.Position.XO==-s.Right and cell.Position.YS==1 and cell.Position.YO==-s.Bottom,true,name..' sits at its slot')
 expect(cell.Size.XO==52 and cell.Size.YO==52,true,name..' is sized from its slot')
 expect(cell.TextSize,nil,name..' TextSize is scaleText\'s, never written')
end
-- 667x375, no housing: the gui ends at 667, 375; Roblox's jump is x 572..642, y 285..355.
screen = {Right=667, Bottom=375, Layout={ControlPlan=plan, Zones={Jump={Left=572,Right=642,Top=285,Bottom=355}}}}
applyTouchControlLayout()
expect(touchRunButton.Position.YO,-98,'667x375 lobby: RUN (x 543..595) meets the engine jump and lifts one Gap above it')
expect(touchSneakButton.Position.YO,-12,'SNEAK takes no lift')
active=true; applyTouchControlLayout()
expect(touchRunButton.Position.YO,-12,'in a round our JUMP owns that corner: RUN keeps its slot')
plan.Slots.TouchRunHold=slot(89,15); plan.Slots.TouchRunHold.Width=64; plan.Slots.TouchRunHold.Height=64
applyTouchControlLayout()
expect(touchRunButton.Size.XO,64,'a mounted cell is resized on the next pass (D6)')
end
'''

spectate_setup = r'''
do
local spectating, idx = true, 2
local attrs, focused, modal = {},nil,false
local player={GetAttribute=function(_,k) return attrs[k] end}
local GuiService={MenuIsOpen=false}
local UIDevice={ScreenOwningModalOpen=function() return modal end}
local UIS={InputBegan=signal(),GetFocusedTextBox=function() return focused end}
local function watch(i) idx=((i-1)%3)+1 end
'''
spectate_logic = 'local function cycleAvailable()' + between(spectate,'local function cycleAvailable()','local function livingOthers()')
spectate_logic += 'UIS.InputBegan:Connect(function(input, processed)' + between(spectate,'UIS.InputBegan:Connect(function(input, processed)','-- if the teammate')
spectate_tests = r'''
local function press(k,processed) UIS.InputBegan:Fire({KeyCode=k},processed==true) end
press('DPadRight'); expect(idx,3,'D-pad next')
press('DPadRight'); expect(idx,1,'D-pad wraps')
press('DPadLeft'); expect(idx,3,'D-pad previous wraps')
press('Q'); expect(idx,2,'keyboard previous preserved')
press('E',true); expect(idx,2,'processed input ignored')
modal=true; press('DPadRight'); expect(idx,2,'modal owns directional input'); modal=false
GuiService.SelectedObject={}; press('DPadRight'); expect(idx,2,'selection owns directional input'); GuiService.SelectedObject=nil
GuiService.MenuIsOpen=true; press('DPadRight'); expect(idx,2,'Roblox menu owns input'); GuiService.MenuIsOpen=false
focused={}; press('E'); expect(idx,2,'typing blocks shortcuts'); focused=nil
attrs.PartyDownCardOpen=true; press('DPadRight'); expect(idx,2,'party down owns input'); attrs.PartyDownCardOpen=nil
spectating=false; press('DPadRight'); expect(idx,2,'living player cannot cycle')
end
'''

round_setup = r'''
do
local attributes={InRound=true}
local focused,lastInput,touchFormFactor=nil,Enum.UserInputType.Gamepad1,false
local player={GetAttribute=function(_,k) return attributes[k] end,SetAttribute=function(_,k,v) attributes[k]=v end}
local Players={LocalPlayer=player}
local GuiService={MenuIsOpen=false}
local game={GetService=function() return GuiService end}
local selectedLevel,dead,objectivesAvailable=1,false,true
local workspace={GetAttribute=function(_,k) return k=='SelectedLevel' and selectedLevel or nil end}
local UserInputService={GamepadEnabled=true,KeyboardEnabled=true,GetLastInputType=function() return lastInput end,GetFocusedTextBox=function() return focused end}
local UIS=UserInputService
local UIDevice={IsTouch=function() return touchFormFactor end}
local function suppressesKeyboardGlyphs() return touchFormFactor end
local objectivesPanel={Visible=false}
local objectivesButton={Visible=true,Activated=signal()}
local objectivesClose={Activated=signal()}
local key={Text='H'}
local briefKeycap={Visible=true,FindFirstChild=function(_,name) return name=='Key' and key or nil end}
local calls={Mute=0,Stop=0}
local transmission,toggleAccepted,stopAccepted=true,true,true
local dispatchAudio={hasActiveTransmission=function() return transmission end}
function dispatchAudio.requestToggle() calls.Mute+=1;return toggleAccepted end
function dispatchAudio.requestStop() calls.Stop+=1;return stopAccepted end
local bindings={}
local ContextActionService={}
function ContextActionService:BindAction(name,fn,touch,...)
 bindings[name]={Handler=fn,Keys={...},Touch=touch,Priority=2000}
end
function ContextActionService:BindActionAtPriority(name,fn,touch,priority,...)
 bindings[name]={Handler=fn,Keys={...},Touch=touch,Priority=priority}
end
function ContextActionService:UnbindAction(name) bindings[name]=nil end
'''

round_logic = section(ui_device, 'function UIDevice.IsGamepadOnly()', '-- ---------------------------------------------------------------------------\n-- 3. Layout')
round_logic += section(ui_device, 'local SCREEN_OWNING_MODALS =', '-- Run `callback` whenever that answer can have changed.')
round_logic += section(round_ui, 'function dispatchAudio.inputBlocked()', 'function dispatchAudio.preferenceUnavailable()')
round_logic += section(round_ui, 'ContextActionService:BindAction("ZyntraToggleDispatchMute"', 'dispatchAudio.stopButton = Instance.new')
round_logic += section(round_ui, 'ContextActionService:BindAction("ZyntraStopCurrentDispatch"', 'dispatchAudio.refresh()\n\nlocal levelOneBriefingSound')
round_logic += 'ContextActionService:UnbindAction("ToggleObjectiveHelp")\n'
mute_hint = next(line for line in section(round_ui, 'function dispatchAudio.refresh()', 'function dispatchAudio.requestToggle()').splitlines() if 'local binding = UIDevice.Binding(' in line)
round_logic += '\nlocal function muteHint()\n' + mute_hint + '\nreturn binding\nend\n'

round_tests = r'''
local function bound(name,key)
 local action=bindings[name]
 expect(action~=nil,true,name..' exists')
 expect(table.find(action.Keys,key)~=nil,true,name..' contains '..key)
 expect(action.Touch,false,name..' creates no duplicate touch button')
 return action.Handler
end
expect(bindings.ToggleObjectiveHelp,nil,'retired MISSION BRIEF binding absent')
local mute=bound('ZyntraToggleDispatchMute','ButtonL1');bound('ZyntraToggleDispatchMute','M')
local stop=bound('ZyntraStopCurrentDispatch','ButtonB')
for _,attribute in ipairs({'ZyntraStoreOpen','DevPhoneOpen','ZyntraReentryOpen','QueueModalOpen','PartyDownCardOpen'}) do
 attributes[attribute]=true
 expect(mute('','Begin'),'Pass',attribute..' blocks hidden mute')
 expect(stop('','Begin'),'Pass',attribute..' blocks hidden dispatch B')
 attributes[attribute]=nil
end
GuiService.MenuIsOpen=true;expect(stop('','Begin'),'Pass','Roblox menu B cannot stop dispatch');GuiService.MenuIsOpen=false
GuiService.SelectedObject={};expect(mute('','Begin'),'Pass','selection blocks mute');expect(stop('','Begin'),'Pass','selection blocks stop');GuiService.SelectedObject=nil
focused={};expect(mute('','Begin'),'Pass','typing owns mute');expect(stop('','Begin'),'Pass','typing owns stop');focused=nil
attributes.Level3_Hiding=true;expect(stop('','Begin'),'Pass','table exit owns B');attributes.Level3_Hiding=nil
expect(calls.Stop,0,'blocked B presses never stop transmission')
expect(mute('','Begin'),'Sink','LB requests save');expect(calls.Mute,1,'one begin requests one save')
expect(mute('','End'),'Pass','release does not toggle');expect(calls.Mute,1,'release never saves')
expect(stop('','Begin'),'Sink','free B stops');expect(calls.Stop,1,'normal stop request')
transmission=false;expect(mute('','Begin'),'Pass','no transmission mute');expect(stop('','Begin'),'Pass','no transmission stop');transmission=true
lastInput=Enum.UserInputType.Gamepad1;expect(muteHint(),'[LB]','pad hint')
lastInput=Enum.UserInputType.Keyboard;expect(muteHint(),'[M]','keyboard hint')
touchFormFactor=true;expect(muteHint(),'','touch no key hint')
end
print('Controller input: '..checks..' checks passed (offline Luau; engine routing and hardware not exercised)')

'''


# == B2 touch cells: the marked section in the HUD fake engine (owner, 2026-10-08) ==
B2_START, B2_END = '-- == B2 touch cells (14 A; owner, 2026-10-08) ==', '-- == end B2 touch cells =='
b2_section = section(noise, B2_START, B2_END)
# What the section reads from the script above it: the REAL stamina block, the player, the
# StaminaGui it mounts into, and its own Heartbeat (recorded so the test can step it).
B2_PRELUDE = '''
local RS = game:GetService("ReplicatedStorage")
local player = game:GetService("Players").LocalPlayer
local game = setmetatable({IsLoaded = function() return true end}, {__index = game})
local function inPreview() return false end
local gui = Instance.new("ScreenGui")
gui.Name = "StaminaGui"
gui.Parent = player:WaitForChild("PlayerGui")
local beats = {}
local RunService = {Heartbeat = {Connect = function(_, fn) table.insert(beats, fn) end}}
local touchSprintToggled, touchSneakToggled = false, false
local showSneakEngaged
''' + section(noise, '-- stamina: sprint is limited', '\n-- ADRENALINE') + '\n'
B2_EXPORTS = '''
return {
	Cells = function() return {Jump = touchJumpButton, Run = touchRunButton, Sneak = touchSneakButton,
		Glow = touchGlowButton, POV = touchPOVButton} end,
	PaintRun = paintRun, Sneak = showSneakEngaged, POV = refreshPOVButton, Gui = gui,
	Set = function(toggled, value, winded) touchSprintToggled, stamina, exhausted = toggled, value, winded end,
	SneakToggled = function() return touchSneakToggled end,
	Beat = function() for _, fn in ipairs(beats) do fn(1 / 60) end end, Beats = function() return #beats end,
	Max = staminaMax, Recover = STAMINA_RECOVER,
}
'''
B2_TESTS = r'''
local function setup(opts)
	local ctx = context(opts)
	return ctx, ctx:Require("NoiseCellsSection"), ctx:Require("ShopBinder").Palette
end
local function part(cell, name) return find(cell, name) end
local function stroke(cell) return cell:FindFirstChildOfClass("UIStroke") end

do -- the mount: every client, PC included, once, from the real import
	local ctx, S, P = setup()
	local c = S.Cells()
	local NAMES = {Jump = "TouchJump", Run = "TouchRunHold", Sneak = "TouchSneakHold", Glow = "TouchDropGlowstick", POV = "TouchPOV"}
	for short, key in pairs(NAMES) do
		local cell = c[short]
		check(cell ~= nil and cell.Parent == S.Gui and cell.Name == key, short .. " mounts into StaminaGui as " .. key .. " (PC too)")
		check(cell.ClassName == "TextButton", short .. " is the template's TextButton")
		check(cell.Visible == false and cell.Active == false, short .. " starts hidden and inactive")
		check(cell.Selectable == false and cell.AutoButtonColor == false, short .. " is not selectable and has no auto colour")
		check(cell.Size == UDim2.fromOffset(52, 52), short .. " at the template's 52 px")
		check(stroke(cell).Color == P.Line, short .. ": the template's Line stroke")
		check(part(cell, "Label").TextColor3 == P.Cream and part(cell, "Glyph").TextColor3 == P.Cream, short .. ": Cream text")
	end
	check(#S.Gui:GetChildren() == 5, "five cells and nothing else")
	check(part(c.Jump, "Glyph").Text == "\u{2191}" and part(c.Jump, "Label").Text == "JUMP", "JUMP reads an up arrow over JUMP")
	check(part(c.Sneak, "Glyph").Text == "\u{2193}" and part(c.Sneak, "Label").Text == "SNEAK", "SNEAK reads a down arrow over SNEAK")
	check(part(c.Run, "Glyph").Text == "\u{BB}" and part(c.Run, "Label").Text == "RUN", "RUN keeps the template's copy")
	check(part(c.Glow, "Glyph").Text == "*" and part(c.Glow, "Label").Text == "GLOW", "GLOW keeps the template's copy")
	check(c.Sneak:GetAttribute("SneakEngaged") == false, "SneakEngaged starts false")
	check(part(c.Run, "RingSlot") ~= nil, "RUN's RingSlot stays, empty (D4)")
	check(#ctx.Warnings == 0, "no warnings: " .. table.concat(ctx.Warnings, " | "))
end

do -- RUN's stamina ring (critic C6): Coral winded, else Amber toggled or <= 25 %, else Line
	local ctx, S, P = setup()
	local run = S.Cells().Run
	local ring, glyph, label = stroke(run), part(run, "Glyph"), part(run, "Label")
	local function look(toggled, value, winded, tone, message)
		S.Set(toggled, value, winded)
		S.PaintRun()
		check(ring.Color == P[tone], message .. ": " .. tone .. " stroke, got " .. tostring(ring.Color))
		check(glyph.TextColor3 == P.Cream and label.TextColor3 == P.Cream, message .. ": glyph and label stay Cream")
	end
	look(false, 50, false, "Line", "walking at half stamina")
	look(true, 50, false, "Amber", "the toggle on, standing still")
	look(false, 25, false, "Amber", "stamina at 25 %")
	look(false, 26, false, "Line", "stamina just over 25 %")
	look(false, 0, true, "Coral", "winded")
	look(true, 10, true, "Coral", "winded beats the toggle")
	look(true, 100, false, "Amber", "toggled at full stamina")
	-- a repeat call writes nothing: a sentinel colour survives it
	ring.Color = P.Lime
	S.PaintRun()
	check(ring.Color == P.Lime, "a repeat paint writes nothing")
	-- critic C8: a resize is a new key, so the ring is rewritten at the new size
	run.Size = UDim2.fromOffset(64, 64)
	S.PaintRun()
	check(ring.Color == P.Amber, "a resized cell repaints its ring")
	-- the multiplier: exhaustion clears at the absolute STAMINA_RECOVER, the ring reads the fraction
	ctx.Player:SetAttribute("ZyntraStaminaMultiplier", 2)
	check(S.Max() == 200 and S.Recover / S.Max() == 0.125, "x2 stamina: recovery at 12.5 %")
	look(false, 50, false, "Amber", "x2, 25 %")
	look(false, 51, false, "Line", "x2, over 25 %")
	look(false, 24, true, "Coral", "x2, still winded")
	look(false, S.Recover, false, "Amber", "x2, recovered at 12.5 %: Amber, not Line")
	ctx.Player:SetAttribute("ZyntraStaminaMultiplier", nil)
	-- its own Heartbeat, not the main one (which returns early in the lobby)
	check(S.Beats() == 1, "paintRun has its own Heartbeat connection")
	S.Set(false, 100, false)
	S.Beat()
	check(ring.Color == P.Line, "the Heartbeat repaints from state (the respawn reset needs no writer)")
end

do -- SNEAK engaged, and POV
	local ctx, S, P = setup()
	local c = S.Cells()
	S.Sneak(true)
	check(S.SneakToggled() == true and c.Sneak:GetAttribute("SneakEngaged") == true, "engaged: the toggle and the attribute")
	check(stroke(c.Sneak).Color == P.RailTeal and part(c.Sneak, "Glyph").TextColor3 == P.RailTeal
		and part(c.Sneak, "Label").TextColor3 == P.RailTeal, "engaged: RailTeal stroke, glyph and label")
	S.Sneak(false)
	check(S.SneakToggled() == false and c.Sneak:GetAttribute("SneakEngaged") == false, "off: the toggle and the attribute")
	check(stroke(c.Sneak).Color == P.Line and part(c.Sneak, "Glyph").TextColor3 == P.Cream
		and part(c.Sneak, "Label").TextColor3 == P.Cream, "off: the template look again")
	S.POV()
	check(part(c.POV, "Label").Text == "POV" and part(c.POV, "Glyph").Text == "3RD", "first person: POV over 3RD")
	ctx.Player:SetAttribute("DevCheatThirdPerson", true)
	S.POV()
	check(part(c.POV, "Glyph").Text == "1ST" and stroke(c.POV).Color == P.Line, "third person: 1ST, no colour state")
	check(part(c.Jump, "Label").Text == "JUMP", "relabelling POV leaves JUMP alone")
end

do -- a place without HUD_Touch (D14): warned by path, nothing drawn, nothing throws
	local ctx, S = setup({skip = {HUD_Touch = true}})
	local c = S.Cells()
	check(c.Jump == nil and c.Run == nil and c.Sneak == nil and c.Glow == nil and c.POV == nil, "no template: no cells")
	check(#S.Gui:GetChildren() == 0, "nothing drawn")
	for _, path in ipairs({"Cell_Jump", "Cell_Run", "Cell_Sneak", "Cell_Glow"}) do
		check(ctx:Warned("[RoundHud] missing template: HUD_Touch/TouchCluster/" .. path) == 1, path .. " warned by path, once")
	end
	S.Set(true, 10, true)
	S.PaintRun()
	S.Beat()
	S.POV()
	S.Sneak(true)
	check(S.SneakToggled() == true, "the SNEAK toggle still works without its cell")
end

do -- a place without RoundHud: one warning, no cells, no yield
	local ctx = context()
	ctx.Storage:FindFirstChild("RoundHud"):Destroy()
	local S = ctx:Require("NoiseCellsSection")
	check(S.Cells().Run == nil and #S.Gui:GetChildren() == 0, "no RoundHud: no cells")
	check(ctx:Warned("[NoiseReporter] ReplicatedStorage.RoundHud") == 1, "one warning")
end

print("NoiseReporter B2 touch cells: " .. checks .. " checks passed (real RoundHud, ShopBinder and HUD_Touch import)")
'''


# == B3 stamina bar: the marked section in the HUD fake engine (owner, 2026-10-08) ==
B3_START, B3_END = '-- == B3 stamina bar (10 C; owner, 2026-10-08) ==', '-- == end B3 stamina bar =='
b3_section = section(noise, B3_START, B3_END)
# What the section reads from the script above it: the player, StaminaGui, UIDevice and the B2
# lookup's touchPalette (set only when RoundHud and ShopBinder both exist).
B3_PRELUDE = '''
local RS = game:GetService("ReplicatedStorage")
local player = game:GetService("Players").LocalPlayer
local UIDevice = require(RS:FindFirstChild("UIDevice"))
local gui = Instance.new("ScreenGui")
gui.Name = "StaminaGui"
gui.DisplayOrder = 60
gui.Parent = player:WaitForChild("PlayerGui")
local hudModule, shopUI = RS:FindFirstChild("RoundHud"), RS:FindFirstChild("ZyntraShopUI")
local binderModule = shopUI and shopUI:FindFirstChild("ShopBinder")
local touchPalette = hudModule and binderModule and require(binderModule).Palette or nil
'''
B3_EXPORTS = '''
return {Place = placeBar, Paint = paintBar, Watched = paintWatched, Bar = bar, Gui = gui}
'''
B3_TESTS = r'''
-- Layouts in UIDevice's shape (absolute px). PC rows are the display under a 58 px topbar; the phone
-- is 844x390 with 47 px housings and its real corridor 346..537; 667x375's real corridor is 88 (K3).
local PC = {IsTouch = false, Safe = {Left = 0, Top = 58, Right = 1920, Bottom = 1080}}
local PC1366 = {IsTouch = false, Safe = {Left = 0, Top = 58, Right = 1366, Bottom = 768}}
local PC1280 = {IsTouch = false, Safe = {Left = 0, Top = 58, Right = 1280, Bottom = 720}}
local PC800 = {IsTouch = false, Safe = {Left = 0, Top = 58, Right = 800, Bottom = 600}}
local PC640 = {IsTouch = false, Safe = {Left = 0, Top = 58, Right = 640, Bottom = 480}}
local PHONE = {IsTouch = true, Safe = {Left = 47, Top = 58, Right = 797, Bottom = 369},
	Corridor = {Left = 346, Right = 537, Width = 191}}
local SMALL = {IsTouch = true, Safe = {Left = 44, Top = 36, Right = 623, Bottom = 354},
	Corridor = {Left = 268, Right = 356, Width = 88}}

local function setup(opts)
	opts = opts or {}
	local ctx = context(opts)
	ctx.Layout = opts.layout or PC
	ctx.UIDevice.Layout = function() return ctx.Layout end
	if opts.prepare then opts.prepare(ctx) end
	local S = ctx:Require("NoiseBarSection")
	S.Place()
	return ctx, S, ctx:Require("ShopBinder").Palette
end
local function opacity(root) return if root.Visible then 1 - root.GroupTransparency else 0 end
local function bars(S)
	local count = 0
	for _, child in ipairs(S.Gui:GetChildren()) do if child.Name == "StaminaBar" then count += 1 end end
	return count
end
local function minText(node)
	local limit = node:FindFirstChildOfClass("UITextSizeConstraint")
	return limit and limit.MinTextSize
end

do -- the mount (PC): a hidden CanvasGroup at the template's 320 x 26, no sample showing
	local ctx, S = setup()
	local root = S.Gui:FindFirstChild("StaminaBar")
	check(root ~= nil and root.ClassName == "CanvasGroup" and root == S.Bar.Root, "a CanvasGroup StaminaBar in StaminaGui")
	check(root.Size == UDim2.fromOffset(320, 26), "320 x 26 on PC, got " .. tostring(root.Size))
	check(opacity(root) == 0 and root.Visible == false, "hidden at mount")
	check(S.Bar.Winded.Visible == false, "the template's WINDED sample is hidden before any paint")
	check(S.Bar.Fill.AnchorPoint.X == 0 and near(S.Bar.Fill.Position.X.Scale, 0), "the Fill is anchored on the track's left edge")
	check(minText(S.Bar.Winded) == nil, "PC: no touch text floor")
	check(bars(S) == 1 and #ctx.Warnings == 0, "one bar, no warnings: " .. table.concat(ctx.Warnings, " | "))
end

do -- the truth table (B3-DESIGN 2.4), with the opacity after the clock moves
	local ctx, S, P = setup()
	local root, fill, winded = S.Bar.Root, S.Bar.Fill, S.Bar.Winded
	local function row(frac, isWinded, draining, want, message)
		S.Paint(frac, isWinded, draining)
		ctx:Advance(0.01)
		check(near(opacity(root), want), message .. ": opacity " .. want .. ", got " .. opacity(root))
	end
	row(1, false, false, 0, "full: hidden")
	row(0.6, false, true, 1, "draining")
	check(fill.Size == UDim2.fromScale(0.6, 1) and fill.BackgroundColor3 == P.Cream, "draining: Fill 0.6, Cream")
	check(near(fill.Position.X.Scale, 0) and fill.Position.X.Offset == 0, "the Fill grows from the left edge")
	ctx:Advance(60)
	check(opacity(root) == 1, "draining never dims")
	row(0.25, false, true, 1, "draining at 25 %")
	check(fill.BackgroundColor3 == P.Amber and winded.Visible == false, "25 %: Amber, no WINDED")
	row(0, true, false, 1, "winded")
	check(fill.BackgroundColor3 == P.Coral and winded.Visible == true and fill.Size == UDim2.fromScale(0, 1),
		"winded: Coral, WINDED shown")
	ctx:Advance(60)
	check(opacity(root) == 1, "WINDED never dims")
	row(0.24, true, false, 1, "still winded at 24 %")
	row(0.26, false, false, 0.55, "recovering")
	check(fill.BackgroundColor3 == P.Cream and winded.Visible == false, "recovering: Cream, WINDED hidden")
	row(0.2, false, false, 0.55, "recovering at 20 % (x2 stamina: exhaustion cleared at 12.5 %)")
	check(fill.BackgroundColor3 == P.Amber, "recovering at 20 %: Amber")
	local tweens = #ctx.Tweens
	S.Paint(0.2, false, false)
	S.Paint(0.2, false, false)
	check(#ctx.Tweens == tweens, "a repeated identical call creates no tween")
	row(0.7, false, true, 1, "draining again wakes it")
	row(1, false, false, 0, "full again: hidden")
	ctx:Advance(1)
	check(root.Visible == false, "Attention owns Visible: off after the fade")
	row(nil, nil, nil, 0, "nil is off")
end

do -- placement (D8, K4, D9, D15) and device flips
	local ctx, S = setup()
	local function at(x, y, message)
		local p = S.Bar.Root.Position
		check(math.abs(p.X.Offset - x) <= 1 and p.Y.Offset == y and p.X.Scale == 0 and p.Y.Scale == 0,
			message .. ": expected (" .. x .. ", " .. y .. "), got " .. tostring(p))
	end
	local root = S.Bar.Root
	check(root.AnchorPoint.X == 0.5 and root.AnchorPoint.Y == 1, "anchored bottom-centre")
	at(960, 1080 - 24, "PC 1920: centred on Safe, bottom at Safe.Bottom - 24")
	ctx.Player:SetAttribute("Spectating", true)
	S.Place()
	at(960, 1080 - 116, "spectating: 92 px higher")
	ctx.Player:SetAttribute("Spectating", nil)
	ctx.Layout = PC1366
	S.Place()
	at(544 + 8 + 160, 768 - 24, "PC 1366: right of B1's kit row (K4)")
	ctx.Layout = PC1280
	S.Place()
	at(544 + 8 + 160, 720 - 24, "PC 1280: right of B1's kit row (K4)")
	check(S.Bar.Root.Position.X.Offset - 160 >= 544 + 8, "PC 1280: the bar's left edge clears the kit row by 8")
	check(S.Bar.Root == root, "a PC re-place does not remount")
	for _, layout in ipairs({PC800, PC640}) do
		ctx.Layout = layout
		S.Place()
		S.Paint(0.5, false, true)
		ctx:Advance(0.01)
		at(layout.Safe.Right / 2, layout.Safe.Bottom - 228, "narrow PC: fixed band above active detector")
		check(S.Bar.Room and opacity(S.Bar.Root) == 1, "narrow PC with room remains visible")
		check(S.Bar.Root.Position.X.Offset - 160 >= layout.Safe.Left
			and S.Bar.Root.Position.X.Offset + 160 <= layout.Safe.Right, "narrow PC bar fits Safe horizontally")
		check(S.Bar.Root.Position.Y.Offset <= layout.Safe.Bottom - 220 - 8,
			"narrow PC bar bottom is 8px above detector top")
	end
	ctx.Layout = {IsTouch = false, Safe = {Left = 0, Top = 58, Right = 300, Bottom = 480}}
	S.Place()
	S.Paint(0.5, false, true)
	ctx:Advance(1)
	check(not S.Bar.Room and opacity(S.Bar.Root) == 0, "truly impossible PC width hides bar")
	ctx.Layout = PHONE
	S.Place()
	root = S.Bar.Root
	check(bars(S) == 1 and root.Size == UDim2.fromOffset(160, 13), "touch: one bar, remounted at 160 x 13")
	check(minText(S.Bar.Winded) == 12, "touch: WINDED floored at 12 px")
	check(S.Bar.Winded.Visible == false and root.Visible == false, "the remount starts hidden, its sample off")
	at(441, 369 - 4, "844x390: centred in the corridor (441.5, floored; K12), bottom at Safe.Bottom - 4")
	S.Paint(0.5, false, true)
	ctx:Advance(0.01)
	check(opacity(root) == 1, "the remounted bar paints")
	ctx.Player:SetAttribute("Spectating", true)
	S.Place()
	at(441, 369 - 4 - 92, "touch spectating: 92 px higher")
	ctx.Player:SetAttribute("Spectating", nil)
	ctx.Layout = SMALL
	S.Place()
	S.Paint(0.4, false, true)
	ctx:Advance(1)
	check(opacity(S.Bar.Root) == 0 and S.Bar.Root.Visible == false, "a corridor of 88 (667x375) has no room: hidden")
	ctx.Layout = PC
	S.Place()
	check(bars(S) == 1 and S.Bar.Root.Size == UDim2.fromOffset(320, 26), "a flip back to PC: exactly one bar, 320 x 26")
	check(minText(S.Bar.Winded) == nil, "back on PC: no touch floor")
	S.Paint(0.4, false, true)
	ctx:Advance(0.01)
	check(opacity(S.Bar.Root) == 1, "room again on PC")
end

do -- paintWatched (D15, critic K1)
	local ctx, S, P = setup()
	local root = S.Bar.Root
	local function watch(frac, id, want, message)
		S.Watched(frac, id)
		ctx:Advance(0.01)
		check(near(opacity(root), want), message .. ": opacity " .. want .. ", got " .. opacity(root))
	end
	watch(0.8, 1, 0.55, "a first sample has no trend: RECOVER")
	watch(0.6, 1, 1, "a decrease drains")
	watch(0.6, 1, 1, "an unchanged value keeps the trend")
	watch(0.7, 1, 0.55, "an increase recovers")
	watch(0, 1, 1, "empty drains")
	check(S.Bar.Winded.Visible == false and S.Bar.Fill.BackgroundColor3 == P.Amber, "a watched bar is never WINDED")
	watch(nil, 1, 0, "nil (invalid, or a modal open) does not throw and hides")
	watch(0.5, 1, 0.55, "after nil the next sample is a first sample")
	watch(0.3, 1, 1, "player 1 draining")
	watch(0.9, 2, 0.55, "a switch to player 2 at 0.9")
	check(S.Bar.WatchedId == 2 and S.Bar.WatchedDrain == nil and S.Bar.Watched == 0.9,
		"the switch is a first sample, not a recovery")
	watch(0.5, 1, 0.55, "back to player 1 at 0.5")
	watch(0.4, 1, 1, "player 1 draining")
	watch(0.2, 2, 0.55, "player 2 lower than player 1 is not a drain")
	ctx.Player:SetAttribute("Spectating", true)
	S.Place()
	watch(0.1, 2, 1, "player 2 draining")
	ctx.Player:SetAttribute("Spectating", nil)
	S.Place() -- spectating ends (re-entry); the next spectate of player 2 is a new session
	ctx.Player:SetAttribute("Spectating", true)
	S.Place()
	watch(0.05, 2, 0.55, "re-spectating the same target later is a first sample, not that target's old trend")
end

do -- a place without HUD_PC: one warning by path, nothing drawn, nothing throws
	local ctx, S = setup({skip = {HUD_PC = true}})
	check(S.Bar.Root == nil and bars(S) == 0, "no template: no bar")
	S.Paint(0.5, false, true)
	S.Paint(nil)
	S.Watched(0.5, 1)
	S.Watched(nil, 1)
	ctx.Layout = PHONE
	S.Place()
	ctx.Layout = PC
	S.Place()
	check(ctx:Warned("[RoundHud] missing template: HUD_PC/StaminaBar") == 1, "warned once, by path")
end

do -- a StaminaBar that lost its Winded: warned, not drawn, nothing throws
	local ctx, S = setup({prepare = function(c) find(c.Templates, "HUD_PC/StaminaBar/Winded"):Destroy() end})
	check(S.Bar.Root == nil and bars(S) == 0, "no Winded: no bar")
	check(ctx:Warned("[NoiseReporter] HUD_PC/StaminaBar has no Fill or Winded") == 1, "one warning")
	S.Paint(0.5, false, true)
	S.Watched(0.5, 1)
end

do -- a place without RoundHud: no bar, no throw (the B2 lookup has already warned)
	local ctx = context()
	ctx.Layout = PC
	ctx.UIDevice.Layout = function() return ctx.Layout end
	ctx.Storage:FindFirstChild("RoundHud"):Destroy()
	local S = ctx:Require("NoiseBarSection")
	S.Place()
	S.Paint(0.5, false, true)
	S.Watched(0.5, 1)
	check(S.Bar.Root == nil and bars(S) == 0, "no RoundHud: no bar")
end

print("NoiseReporter B3 stamina bar: " .. checks .. " checks passed (real RoundHud, ShopBinder and HUD_PC import)")
'''


def b3_static_checks():
    """Source pins for B3 (B3-DESIGN 4.6 test 4; critics K1, K4, K5)."""
    for gone in ('staBg', 'staFill', 'barShown', 'BAR_FADE', 'STA_FULL', 'STA_EMPTY', 'applyStaminaLayout',
                 'objectiveReserve', ':Lerp('):
        assert gone not in noise, 'NoiseReporter still carries ' + gone
    assert noise.count('SetAttribute("MoveNoise"') == 1, 'exactly one MoveNoise write (D6)'
    apply = between(noise, 'local function applySpeed()', 'local function refreshCrouch()')
    write = apply.index('SetAttribute("MoveNoise"')
    assert apply.index('if crouching then') < write < apply.index('desiredSpeed *= speedBoost()'), \
        'MoveNoise is written in the round branch, right after the state chain (D6)'
    assert all(ord(ch) < 128 for ch in b3_section), 'the B3 section must be ASCII-only (owner, 2026-10-08)'
    assert 'WaitForChild' not in b3_section and ':Wait()' not in b3_section, 'the B3 section never waits'
    assert noise.index(B3_END) < noise.index('local boostActive = false'), \
        'the B3 section sits above the speed-potion slice (local boostActive = false)'
    visible = re.findall(r'([\w.]+)\.Visible\s*=(?!=)', b3_section)
    assert visible and all(name.endswith('Winded') for name in visible), 'only Winded.Visible is written: %r' % visible
    assert 'local BAR_BOTTOM, BAR_BOTTOM_TOUCH, BAR_TOUCH_SCALE, SPECTATE_LIFT = 24, 4, 0.5, 92' in b3_section
    assert 'local KIT_RIGHT, BAR_HALF = 544, 160' in b3_section, 'KIT_RIGHT is pinned like BAR_BOTTOM (K4)'
    assert 'gui.Name = "StaminaGui"' in noise and 'gui.DisplayOrder = 60' in noise, 'StaminaGui keeps its name and order'
    assert noise.count('RunService.Heartbeat:Connect(function(dt)') == 1, 'still one main Heartbeat'
    beat = between(noise, 'RunService.Heartbeat:Connect(function(dt)', '\nend)\n')
    for call in ('paintWatched(', 'paintBar(nil)', 'lastDrainAt = os.clock()'):
        assert call in beat, 'the main Heartbeat drives the bar: ' + call
    assert 'player:GetAttribute("Level4CardOpen") ~= true' in beat, 'the bar stands down under the L4 keypad (K5)'
    assert 'paintBar(hum and hum.Health > 0 and not isEscaped() and' in beat, 'dead or escaped, the bar stands down (QA 10)'
    assert 'math.clamp(value, 0, 1) or nil, id)' in beat, 'paintWatched gets the target id, so a switch resets (K1)'
    assert 'placeBar()' in between(noise, 'local function updateRoundState()', '\nend\n'), \
        'updateRoundState places the bar (device flip, Spectating, death)'
    assert noise.rstrip().splitlines()[-1] == 'player:SetAttribute("RoundEntryControlsReady", true)', 'readiness stays last'


def b3_program():
    sources = {name: path.read_text(encoding='utf-8') for name, path in hud_test.SOURCES.items()}
    sources['NoiseBarSection'] = B3_PRELUDE + b3_section + B3_EXPORTS
    inject = 'local SOURCES = {\n%s\n}\nlocal TREES = %s\n' % (
        ',\n'.join('%s = %s' % (name, hud_test.long_string(text)) for name, text in sources.items()),
        hud_test.lua(hud_test.trees()))
    harness = hud_test.HARNESS.read_text(encoding='utf-8')
    assert '--@@INJECT@@' in harness
    return harness.replace('--@@INJECT@@', inject, 1) + '\n' + B3_TESTS


def b2_static_checks():
    """Source pins for B2 (B2-DESIGN 4 tests 3-4; critics C2, C3, C14)."""
    assert all(ord(ch) < 128 for ch in b2_section), 'the B2 section must be ASCII-only (owner, 2026-10-08)'
    for gone in ('makeTouchButton', 'showRunEnabled(', '"column"', 'runStroke', 'sneakStroke', 'povStroke'):
        assert gone not in noise, 'NoiseReporter still carries ' + gone
    modal = between(noise, 'local function modalOwnsScreen()', '\nend\n')
    available = between(noise, 'local function controlsAvailable()', '\nend\n')
    assert 'UIDevice.ScreenOwningModalOpen()' in modal, 'modalOwnsScreen is the eight-modal predicate (D13)'
    assert 'not UIDevice.ScreenOwningModalOpen()' in available, 'controlsAvailable stands down under the eight (D13)'
    jump = [line for line in noise.splitlines() if 'UIDevice.SuppressDefaultJump(' in line]
    assert len(jump) == 1 and 'touchJumpButton ~= nil' in jump[0], 'no JUMP cell, no suppression (D14): %r' % jump
    # C2: one declaration, above the section that reads it (paintRun would otherwise read a nil global).
    assert noise.count('local touchSprintToggled') == 1
    assert noise.index('local touchSprintToggled = false') < noise.index(B2_START), 'touchSprintToggled is hoisted (C2)'
    # C3: nothing in the section can stall round entry; the one wait is game.Loaded's.
    assert 'WaitForChild' not in b2_section and 'task.wait' not in b2_section, 'the section never waits for the bundle (C3)'
    assert b2_section.count(':Wait()') == 1 and 'game.Loaded:Wait()' in b2_section
    assert 'RunService.Heartbeat:Connect(paintRun)' in b2_section, 'paintRun has its own Heartbeat (B2-DESIGN 4)'
    assert 'TextSize' not in between(noise, 'local function placeTouchControl(', '\nend\n'), 'TextSize belongs to scaleText'
    # Kept verbatim (B2-DESIGN 2.5): the MOBILE_QA GLOW gate and the grounded jump.
    assert ('UIDevice.SetInteractive(touchGlowButton, usable and not inPreview() and '
            'player:GetAttribute("Level6PlaygroundPreview") ~= true)') in noise
    assert 'TOUCH_JUMP_GROUNDED_20261008' in noise
    assert 'if not FROM[state] or os.clock() - lastJump < 0.4 then return end' in noise
    assert noise.rstrip().splitlines()[-1] == 'player:SetAttribute("RoundEntryControlsReady", true)', 'readiness stays last'


def b2_program():
    sources = {name: path.read_text(encoding='utf-8') for name, path in hud_test.SOURCES.items()}
    sources['NoiseCellsSection'] = B2_PRELUDE + b2_section + B2_EXPORTS
    inject = 'local SOURCES = {\n%s\n}\nlocal TREES = %s\n' % (
        ',\n'.join('%s = %s' % (name, hud_test.long_string(text)) for name, text in sources.items()),
        hud_test.lua(hud_test.trees()))
    harness = hud_test.HARNESS.read_text(encoding='utf-8')
    assert '--@@INJECT@@' in harness
    return harness.replace('--@@INJECT@@', inject, 1) + '\n' + B2_TESTS


def pov_program():
    """Actual allowlist, early UI gates, POV availability write and activation callback.

    Fires the callback even with a forged visible cell, so hiding alone cannot satisfy denial.
    Prefix probes end immediately after the real DevCheats/ZyntraDev gate; they do not claim to
    execute either full camera or phone UI. Real engine input and camera zoom remain native QA.
    """
    dev_access = (ROOT / 'ReplicatedStorage/DevAccess.ModuleScript.lua').read_text(encoding='utf-8')
    dev_cheats = (root / 'DevCheats.LocalScript.lua').read_text(encoding='utf-8')
    dev_ui = (root / 'Zyntra Dev L4.LocalScript.lua').read_text(encoding='utf-8')
    prefixes = [dev_cheats[:dev_cheats.index('local playerScripts =')],
                dev_ui[:dev_ui.index('local playerGui =')]]
    click = section(noise, 'if touchPOVButton then\n\ttouchPOVButton.Activated:',
                    '\nplayer:GetAttributeChangedSignal("DevCheatThirdPerson")')
    availability = next(line for line in noise.splitlines()
                        if 'UIDevice.SetInteractive(touchPOVButton,' in line)
    interactive = section(ui_device, 'local function rememberedFlag(', '\nfunction UIDevice.SetEnabled(')
    interactive += '\n' + section(ui_device, 'function UIDevice.SetInteractive(', '\nend\n') + '\nend\n'
    source = 'local AccessSource = %s\nlocal Prefixes = {%s}\n' % (
        hud_test.long_string(dev_access), ','.join(hud_test.long_string(p + '\nreturn true\n') for p in prefixes))
    source += r'''
local checks = 0
local function check(ok, message) checks += 1; assert(ok, message) end
local function signal()
    local s = {Callbacks = {}}
    function s:Connect(fn) table.insert(self.Callbacks, fn) end
    function s:Fire(...) for _, fn in ipairs(self.Callbacks) do fn(...) end end
    return s
end
local function fakeTypeof(value)
    return type(value) == "table" and value.FakePlayer and "Instance" or typeof(value)
end
local studio = true
local function access()
    local fn = assert(loadstring(AccessSource))
    setfenv(fn, setmetatable({typeof = fakeTypeof,
        game = {GetService = function() return {IsStudio = function() return studio end} end}}, {__index = _G}))
    return fn()
end
local DevAccess = access()
local function member(id)
    return {UserId = id, Name = "mikkelczar", FakePlayer = true, IsA = function(_, class) return class == "Player" end}
end
for _, data in ipairs({{40920547, true}, {9488575949, true}, {11374988579, false}, {-1, false}, {12345, false}}) do
    local player = member(data[1])
    check(DevAccess.IsAllowed(player) == data[2], "actual UserId whitelist: " .. data[1])
    if data[1] == 11374988579 or data[1] < 0 then
        check(DevAccess.IsLevel6PreviewAllowed(player), "preview access does not imply developer: " .. data[1])
    end
    for index, prefix in ipairs(Prefixes) do
        local RS = {WaitForChild = function(_, name) assert(name == "DevAccess"); return name end}
        local game = {GetService = function(_, name)
            return name == "Players" and {LocalPlayer = player} or name == "ReplicatedStorage" and RS or {}
        end}
        local fn = assert(loadstring(prefix))
        setfenv(fn, setmetatable({game = game, require = function() return DevAccess end}, {__index = _G}))
        check((fn() == true) == data[2], "real early gate controls all camera/phone setup: " .. index .. ":" .. data[1])
    end
    for _, active in ipairs({false, true}) do
        for _, usable in ipairs({false, true}) do
            local sent, waited = 0, 0
            local command = {IsA = function(_, class) return class == "BindableEvent" end,
                Fire = function(_, commandName) check(commandName == "thirdPerson", "POV uses canonical command"); sent += 1 end}
            player.WaitForChild = function(_, name)
                waited += 1
                assert(name == "PlayerScripts")
                return {FindFirstChild = function(_, key) assert(key == "DevCheatCommand"); return command end}
            end
            local attributes = {}
            local button = {Activated = signal(), Visible = true, Active = true, Selectable = false, Modal = false,
                IsA = function(_, class) return class == "TextButton" end,
                GetAttribute = function(_, key) return attributes[key] end,
                SetAttribute = function(_, key, value) attributes[key] = value end}
            local UIDevice = {}
            local env = setmetatable({UIDevice = UIDevice, touchPOVButton = button, player = player,
                devAllowed = DevAccess.IsAllowed(player), inRound = function() return active end, usable = usable}, {__index = _G})
'''
    source += '            local fixture = %s\n' % hud_test.long_string(interactive + '\n' + availability + '\n' + click)
    source += r'''
            local fn = assert(loadstring(fixture)); setfenv(fn, env); fn()
            check(button.Visible == (usable and data[2]) and button.Active == (usable and data[2]),
                "POV hidden and inactive for denied/unavailable player: " .. data[1])
            -- Even a manufactured Activated event on an exposed cell must hit the action guard.
            button.Visible, button.Active = true, true
            button.Activated:Fire()
            local allowed = data[2] and active
            check(sent == (allowed and 1 or 0) and waited == (allowed and 1 or 0),
                "POV callback requires developer and round before command lookup: " .. data[1])
        end
    end
end
studio = false
check(not DevAccess.IsAllowed(-1) and not DevAccess.IsLevel6PreviewAllowed(-1), "Studio preview ID gets no live developer rights")
check(not DevAccess.IsAllowed("mikkelczar") and not DevAccess.IsAllowed(nil), "names and missing identity cannot authorize POV")
print("Developer POV gates: " .. checks .. " checks passed (actual source; no native camera/input)")
'''
    return source


def main():
    binary = os.environ.get('LUAU_BIN') or shutil.which('luau')
    if not binary:
        raise SystemExit('Set LUAU_BIN or install luau; no tests were executed.')
    b2_static_checks()
    b3_static_checks()
    source = '\n'.join([
        common, noise_setup, noise_apply, noise_helpers, noise_heartbeat, noise_tests,
        layout_setup, noise_layout, layout_tests,
        spectate_setup, spectate_logic, spectate_tests,
        round_setup, round_logic, round_tests,
    ])
    with tempfile.TemporaryDirectory(prefix='controller-input-') as directory:
        fixture = Path(directory) / 'controller_input_test.luau'
        fixture.write_text(source, encoding='utf-8')
        subprocess.run([binary, str(fixture)], check=True, timeout=20)
        cells = Path(directory) / 'noise_b2_cells_test.luau'
        cells.write_text(b2_program(), encoding='utf-8')
        subprocess.run([binary, str(cells)], check=True, timeout=120)
        stamina = Path(directory) / 'noise_b3_bar_test.luau'
        stamina.write_text(b3_program(), encoding='utf-8')
        subprocess.run([binary, str(stamina)], check=True, timeout=120)
        pov = Path(directory) / 'developer_pov_test.luau'
        pov.write_text(pov_program(), encoding='utf-8')
        subprocess.run([binary, str(pov)], check=True, timeout=20)


if __name__ == '__main__':
    main()
