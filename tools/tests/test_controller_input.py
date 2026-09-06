"""Exercise the actual controller handlers in offline Luau with hardware/UI stubs.

Extracts production sprint reconciliation, spectate input, terminal focus,
RoundUI bindings and UIDevice caption/modal helpers; does not reimplement their
decisions. Roblox CoreScript routing, GUI geometry and physical disconnection
still require engine/controller tests. Set LUAU_BIN or put luau on PATH.
"""

from pathlib import Path
import os
import shutil
import subprocess
import tempfile

ROOT = Path(__file__).resolve().parents[2]
root = ROOT / 'StarterPlayer/StarterPlayerScripts'
noise = (root/'NoiseReporter.LocalScript.lua').read_text(encoding='utf-8')
spectate = (root/'SpectateController.LocalScript.lua').read_text(encoding='utf-8')
store = (root/'ZyntraStore.LocalScript.lua').read_text(encoding='utf-8')
round_ui = (root/'RoundUI.LocalScript.lua').read_text(encoding='utf-8')
ui_device = (ROOT/'ReplicatedStorage/UIDevice.ModuleScript.lua').read_text(encoding='utf-8')

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
local player = {GetAttribute=function(_,k) return attrs[k] end}
local function currentChar() return character, hum end
local function inRound() return active end
local focused
local UIS = {WindowFocusReleased=signal(),WindowFocused=signal()}
function UIS:GetFocusedTextBox() return focused end
function UIS:IsKeyDown(k) return keys[k]==true end
function UIS:GetConnectedGamepads() return pads end
function UIS:IsGamepadButtonDown(p,k) return padDown[p]==true end
local RunService = {Heartbeat=signal()}
'''
noise_apply = 'local function applySpeed()' + between(noise, 'local function applySpeed()', 'local function refreshCrouch()')
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

store_setup = r'''
do
local function object(class,parent)
 local o={Class=class,Parent=parent,Visible=true,Enabled=true,Selectable=true,Active=true,AbsolutePosition={X=0},AbsoluteSize={X=100},CanvasPosition={X=0,Y=0}}
 function o:IsA(c) return self.Class==c or (c=='GuiObject' and self.Class~='PlayerGui' and self.Class~='ScreenGui') end
 function o:IsDescendantOf(p) local a=self.Parent; while a do if a==p then return true end; a=a.Parent end; return false end
 return o
end
local playerGui=object('PlayerGui')
local gui=object('ScreenGui',playerGui)
local main=object('Frame',gui); main.Visible=false
local tabBar=object('ScrollingFrame',main); tabBar.AbsoluteSize.X=200
local closeButton=object('TextButton',main)
local opener=object('TextButton',gui)
local other=object('TextButton',gui)
local tabButtons={Shop=object('TextButton',tabBar),Dev=object('TextButton',tabBar)}
tabButtons.Dev.AbsolutePosition.X=400
local currentTab='Shop'
local GuiService={MenuIsOpen=false,SelectedObject=opener}
local bindings={}
local ContextActionService={}
function ContextActionService:BindActionAtPriority(name,fn,_,priority,key) bindings[name]=fn end
function ContextActionService:UnbindAction(name) bindings[name]=nil end
local focused,lastInput,blocked=nil,'Gamepad',false
local UserInputService={LastInputTypeChanged=signal(),GetFocusedTextBox=function() return focused end}
local UIDevice={LastInput=function() return lastInput end,SuppressTouchMovement=function() end,ScreenOwningModalOpen=function() return main.Visible end,SetInteractive=function() end}
local game={GetService=function(_,name) if name=='GuiService' then return GuiService else return ContextActionService end end}
local queue={}
local task={defer=function(fn) table.insert(queue,fn) end}
local function flush() local pending=queue;queue={}; for _,fn in ipairs(pending) do fn() end end
local player={SetAttribute=function() end}
local devAllowed=false
local function modalBlocksStore() return blocked end
'''
store_logic = 'local updateVisibility\n' + between(store,'local updateVisibility\n','function updateVisibility()')
store_tests = r'''
updateVisibility=function() opener.Visible=not main.Visible; opener.Selectable=not main.Visible end
setMainVisible(true); flush()
expect(GuiService.SelectedObject,tabButtons.Shop,'kiosk selects current Shop tab')
expect(bindings.ZyntraCloseTerminal~=nil,true,'B bound while open')
local close=bindings.ZyntraCloseTerminal
GuiService.MenuIsOpen=true; expect(close('', 'Begin'),'Pass','B passes to Roblox menu'); expect(main.Visible,true,'menu B keeps terminal'); GuiService.MenuIsOpen=false
focused={}; expect(close('','Begin'),'Pass','B passes during text entry'); focused=nil
expect(close('','Begin'),'Sink','B close consumes event'); flush()
expect(main.Visible,false,'B closes terminal'); expect(bindings.ZyntraCloseTerminal,nil,'B unbound on close')
expect(GuiService.SelectedObject,opener,'close restores visible opener')
currentTab='Dev'; setMainVisible(true); flush()
expect(GuiService.SelectedObject,tabButtons.Dev,'Dev opening preserves selected tab')
expect(tabBar.CanvasPosition.X,300,'offscreen selected tab revealed')
GuiService.SelectedObject=other; setMainVisible(false);flush();expect(GuiService.SelectedObject,other,'close leaves another UI focus intact')
GuiService.SelectedObject=opener; setMainVisible(true);flush();opener.Parent=nil;setMainVisible(false);flush()
expect(GuiService.SelectedObject,nil,'removed opener is not restored');opener.Parent=gui
blocked=true;setMainVisible(true);flush();expect(main.Visible,false,'blocked opening has no controller binding');expect(bindings.ZyntraCloseTerminal,nil,'blocked terminal does not bind B');blocked=false
lastInput='Keyboard';GuiService.SelectedObject=nil;setMainVisible(true);flush();expect(GuiService.SelectedObject,nil,'mouse opening does not steal focus')
lastInput='Gamepad';UserInputService.LastInputTypeChanged:Fire();flush();expect(GuiService.SelectedObject,tabButtons.Dev,'switching to controller acquires terminal focus')
setMainVisible(false);setMainVisible(true);flush();expect(GuiService.SelectedObject,tabButtons.Dev,'stale close restore cannot override reopened terminal')
setMainVisible(false);flush()
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
round_logic += section(round_ui, 'local function isLevelOneParticipant()', '-- The one rule for whether the OBJECTIVES button is on screen.')
round_logic += section(round_ui, 'local function refreshObjectivesButton()', 'UIDevice.OnScreenOwningModalChanged(function()')
round_logic += section(round_ui, 'local function setObjectivesAvailable(available)', 'local function setSubtitle(text)')
round_logic += section(round_ui, 'ContextActionService:BindAction("ZyntraToggleDispatchMute"', 'dispatchAudio.stopButton = Instance.new')
round_logic += section(round_ui, 'ContextActionService:BindAction("ZyntraStopCurrentDispatch"', 'dispatchAudio.refresh()\n\nlocal objectivesButton')
round_logic += section(round_ui, 'local function toggleObjectives()', '-- The longest line the dispatch panel')
round_layout = section(round_ui, 'local function updateLevelOneGuideLayout()', '\n\tif touch then\n')
# Only the production keycap block is exercised; the surrounding geometry needs Studio.
round_logic += '\nlocal function refreshKeycap()\n' + round_layout[round_layout.index('\tif briefKeycap then\n'):] + '\nend\n'
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
local objective=bound('ToggleObjectiveHelp','DPadUp')
bound('ToggleObjectiveHelp','H')
local mute=bound('ZyntraToggleDispatchMute','ButtonL1')
bound('ZyntraToggleDispatchMute','M')
local stop=bound('ZyntraStopCurrentDispatch','ButtonB')
expect(table.find(bindings.ToggleObjectiveHelp.Keys,'ButtonSelect'),nil,'Select remains Roblox navigation')
expect(table.find(bindings.ToggleObjectiveHelp.Keys,'ButtonY'),nil,'Y remains Level 3 reader')
expect(bindings.ToggleObjectiveHelp.Priority,3000,'objectives uses intended action priority')
expect(objective('','Begin'),'Sink','D-pad up opens objectives')
expect(objectivesPanel.Visible,true,'mission panel opens')
expect(attributes.LevelOneGuideObjectivesOpen,true,'mission panel publishes open flag')
expect(UIDevice.ScreenOwningModalOpen(),false,'own objectives flag does not block its close shortcut')
expect(GuiService.SelectedObject,nil,'shortcut does not enter GUI selection mode')
expect(objectivesButton.Visible,false,'opener stands down while mission panel is open')
expect(objective('','Begin'),'Sink','D-pad up closes its own open panel')
expect(objectivesPanel.Visible,false,'mission panel closes')
expect(attributes.LevelOneGuideObjectivesOpen,nil,'mission panel clears published flag')
expect(objectivesButton.Visible,true,'opener returns after closing')
expect(objective('','End'),'Pass','release does not toggle objectives')
for _,attribute in ipairs({'ZyntraStoreOpen','DevPhoneOpen','ZyntraReentryOpen','QueueModalOpen','PartyDownCardOpen'}) do
 attributes[attribute]=true
 expect(objective('','Begin'),'Pass',attribute..' blocks objectives')
 expect(mute('','Begin'),'Pass',attribute..' blocks hidden mute')
 expect(stop('','Begin'),'Pass',attribute..' blocks hidden dispatch B')
 attributes[attribute]=nil
end
expect(calls.Mute,0,'modal input never attempts a dispatch save')
expect(calls.Stop,0,'modal B never stops a transmission')
GuiService.MenuIsOpen=true
expect(objective('','Begin'),'Pass','Roblox menu owns D-pad up')
expect(stop('','Begin'),'Pass','Roblox menu B cannot stop dispatch')
expect(calls.Stop,0,'menu B has no dispatch side effect')
GuiService.MenuIsOpen=false
GuiService.SelectedObject={}
expect(objective('','Begin'),'Pass','GUI selection owns D-pad up')
expect(mute('','Begin'),'Pass','GUI selection blocks dispatch shortcut')
expect(stop('','Begin'),'Pass','GUI selection B cannot stop dispatch')
GuiService.SelectedObject=nil
focused={};expect(objective('','Begin'),'Pass','typing owns objectives input');expect(mute('','Begin'),'Pass','typing owns mute');expect(stop('','Begin'),'Pass','typing owns stop');focused=nil
attributes.Level3_Hiding=true;expect(stop('','Begin'),'Pass','table exit owns B');attributes.Level3_Hiding=nil
expect(calls.Stop,0,'all blocked B presses leave transmission running')
expect(mute('','Begin'),'Sink','LB requests one mute toggle')
expect(calls.Mute,1,'one begin requests one save')
expect(mute('','End'),'Pass','LB release does not toggle')
expect(calls.Mute,1,'LB release does not request another save')
expect(stop('','Begin'),'Sink','B outside modals stops dispatch')
expect(calls.Stop,1,'normal B requests one stop')
transmission=false;expect(mute('','Begin'),'Pass','no transmission cannot mute');expect(stop('','Begin'),'Pass','no transmission cannot stop');transmission=true
toggleAccepted=false;expect(mute('','Begin'),'Pass','unavailable save is not falsely consumed')
setObjectivesAvailable(false);expect(objective('','Begin'),'Pass','unavailable mission panel leaves input alone');setObjectivesAvailable(true)
selectedLevel=2;objective('','Begin');expect(objectivesPanel.Visible,false,'Level 1 brief is not enabled on Level 2');selectedLevel=1
dead=true;objective('','Begin');expect(objectivesPanel.Visible,false,'dead player cannot open mission brief');dead=false
lastInput=Enum.UserInputType.Gamepad1;refreshKeycap();expect(key.Text,'↑','gamepad keycap shows D-pad up');expect(briefKeycap.Visible,true,'gamepad hint visible');expect(muteHint(),'[LB]','mute caption matches actual LB binding')
lastInput=Enum.UserInputType.Keyboard;refreshKeycap();expect(key.Text,'H','switching to keyboard restores H');expect(muteHint(),'[M]','keyboard mute hint')
lastInput=Enum.UserInputType.Gamepad1;refreshKeycap();expect(key.Text,'↑','switching back to gamepad refreshes keycap')
touchFormFactor=true;refreshKeycap();expect(briefKeycap.Visible,false,'touch suppresses keycap even with connected gamepad');expect(muteHint(),'','touch suppresses mute binding')
touchFormFactor=false;UserInputService.KeyboardEnabled=false;lastInput=Enum.UserInputType.Keyboard;refreshKeycap();expect(briefKeycap.Visible,false,'gamepad-only device never falls back to unavailable H')
end
print('Controller input: '..checks..' checks passed (offline Luau; engine routing and hardware not exercised)')
'''


def main():
    binary = os.environ.get('LUAU_BIN') or shutil.which('luau')
    if not binary:
        raise SystemExit('Set LUAU_BIN or install luau; no tests were executed.')
    source = '\n'.join([
        common, noise_setup, noise_apply, noise_helpers, noise_heartbeat, noise_tests,
        spectate_setup, spectate_logic, spectate_tests,
        store_setup, store_logic, store_tests, round_setup, round_logic, round_tests,
    ])
    with tempfile.TemporaryDirectory(prefix='controller-input-') as directory:
        fixture = Path(directory) / 'controller_input_test.luau'
        fixture.write_text(source, encoding='utf-8')
        subprocess.run([binary, str(fixture)], check=True, timeout=20)


if __name__ == '__main__':
    main()
