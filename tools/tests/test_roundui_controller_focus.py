"""Controller focus for RoundUI's two choice screens, run offline in Luau.

AUDIT_FIX_20260924 (audit findings 10 and 12). The queue host panel (CREATE
PARTY) and the round-complete CONTINUE / BACK TO LOBBY row gave a gamepad no
selected control, and the panel had no B. The REAL RoundUI blocks are sliced
by string markers and driven against a fake engine: opening, pressing B,
hiding, the deadline expiring. Engine selection rules (what the stick does to
a selected button, whether Active=false drops it) still need a controller in
Studio. Set LUAU_BIN, or put luau on PATH.
"""

from pathlib import Path
import os
import shutil
import subprocess
import tempfile

ROOT = Path(__file__).resolve().parents[2]
round_ui = (ROOT / 'StarterPlayer/StarterPlayerScripts/RoundUI.LocalScript.lua').read_text(encoding='utf-8')


def section(source, start, stop):
    begin = source.index(start)
    return source[begin:source.index(stop, begin + len(start))]


queue_block = section(round_ui, 'do\n local function cancelHostedQueue()', '\nrefreshQueuePanel()\n\n-- RoundUI is the sole cursor-policy owner')
completion_block = section(round_ui, 'function completion.reset()', '-- One handler for both actions.')
expiry_block = section(round_ui, 'do\n\tlocal completionLastDeadline = nil', '\n-- AUDIT_FIX_20260924 (Codex review)')
switch_block = section(round_ui, '-- AUDIT_FIX_20260924 (Codex review)', '\n-- C_ONE_SPECTATE_CAMERA_20260904 -- WHAT SHIPPED BROKEN.')

harness = r'''
local checks = 0
local function expect(value, wanted, message)
    checks += 1
    assert(value == wanted, message .. ': expected ' .. tostring(wanted) .. ', got ' .. tostring(value))
end
local function signal()
    local s = {callbacks = {}}
    function s:Connect(fn) table.insert(self.callbacks, fn); return {Disconnect = function() end} end
    function s:Fire(...) for _, fn in ipairs(self.callbacks) do fn(...) end end
    return s
end
local Enum = {KeyCode = {ButtonB = 'ButtonB'}, UserInputState = {Begin = 'Begin', End = 'End'},
    ContextActionResult = {Pass = 'Pass', Sink = 'Sink'}, ContextActionPriority = {High = {Value = 3000}}}
local GuiService = {MenuIsOpen = false, SelectedObject = nil}
local game = {GetService = function(_, name) assert(name == 'GuiService', name); return GuiService end}
local lastInput = 'Gamepad'
local UIDevice = {LastInput = function() return lastInput end}
local bindings = {}
local ContextActionService = {}
function ContextActionService:BindActionAtPriority(name, fn, touch, priority, key)
    bindings[name] = {Handler = fn, Touch = touch, Priority = priority, Key = key}
end
function ContextActionService:UnbindAction(name) bindings[name] = nil end
local function isDescendantOf(self, p) local a = self.Parent; while a do if a == p then return true end; a = a.Parent end; return false end
local function button(parent) return {Parent = parent, Activated = signal(), IsDescendantOf = isDescendantOf} end
local other = button(nil)

-- ── queue host panel ──────────────────────────────────────────────────
do
local visibleChanged = signal()
local shade = {Visible = false, IsDescendantOf = isDescendantOf,
    GetPropertyChangedSignal = function(_, prop) assert(prop == 'Visible'); return visibleChanged end}
local queueShade = setmetatable({}, {__index = shade, __newindex = function(_, k, v)
    local old = shade[k]; shade[k] = v
    if k == 'Visible' and old ~= v then visibleChanged:Fire() end
end})
local queueSubmit, queueClose = button(queueShade), button(queueShade)
local fired = {}
local queueRemote = {FireServer = function(_, ...) table.insert(fired, {...}) end}
local queueStation, queueSubmitting = nil, false
local function refreshQueuePanel() end
''' + queue_block + r'''
local function open(station) queueStation = station; queueSubmitting = false; queueShade.Visible = true end
open(3)
expect(GuiService.SelectedObject, queueSubmit, 'gamepad opening selects CREATE PARTY')
local b = bindings.QueueHostClose
expect(b ~= nil, true, 'B bound while the panel is up')
expect(b.Key, 'ButtonB', 'close action is on B')
expect(b.Touch, false, 'no duplicate touch button')
expect(b.Priority, 3000, 'B sits above the dispatch stop binding')
GuiService.MenuIsOpen = true
expect(b.Handler('', 'Begin'), 'Pass', 'Roblox menu owns B'); expect(queueShade.Visible, true, 'menu B keeps the panel')
GuiService.MenuIsOpen = false
queueSubmitting = true
expect(b.Handler('', 'Begin'), 'Sink', 'B while creating is swallowed'); expect(#fired, 0, 'no cancel while creating')
queueSubmitting = false
expect(b.Handler('', 'End'), 'Sink', 'release is swallowed'); expect(queueShade.Visible, true, 'release does not cancel')
expect(b.Handler('', 'Begin'), 'Sink', 'B cancels')
expect(queueShade.Visible, false, 'B hides the panel')
expect(#fired, 1, 'B sends exactly one cancel')
expect(fired[1][1], 3, 'cancel names the station'); expect(fired[1][2], 0, 'cancel size'); expect(fired[1][3], 'cancel', 'cancel verb')
expect(bindings.QueueHostClose, nil, 'B unbound once hidden')
expect(GuiService.SelectedObject, nil, 'hide drops the selection inside the panel')
open(4); queueClose.Activated:Fire()
expect(#fired, 2, 'X still cancels'); expect(fired[2][1], 4, 'X cancels its station')
lastInput = 'Keyboard'; open(5)
expect(GuiService.SelectedObject, nil, 'mouse opening does not steal focus')
GuiService.SelectedObject = other; queueShade.Visible = false
expect(GuiService.SelectedObject, other, 'hide leaves focus outside the panel alone')
GuiService.SelectedObject = nil; lastInput = 'Gamepad'
end

-- ── round-complete choice ─────────────────────────────────────────────
do
local function plain() return {Visible = false, Active = false, Selectable = false, TextTransparency = 1, Text = ''} end
local completion = {clearChoices = function() end, applyLayout = function() end}
completion.continueButton, completion.button = plain(), plain()
completion.buttons = {completion.continueButton, completion.button}
local now = 100
local workspace = {GetServerTimeNow = function() return now end}
local TweenService = {Create = function() return {Play = function() end} end}
local TweenInfo = {new = function() return {} end}
local endFrame, endHint = {Visible = true}, {Text = ''}
local function refreshCursor() end
local RunService = {RenderStepped = signal()}
''' + completion_block + expiry_block + r'''
completion.start(now + 15, 2, 7)
expect(GuiService.SelectedObject, completion.continueButton, 'gamepad win selects CONTINUE')
completion.reset()
expect(GuiService.SelectedObject, nil, 'reset drops the result-screen focus')
completion.start(now + 15, nil, 7)
expect(GuiService.SelectedObject, completion.button, 'last level selects BACK TO LOBBY')
completion.reset(); completion.start(now + 15, 2, nil)
expect(GuiService.SelectedObject, nil, 'no serial, no buttons, no focus')
lastInput = 'Keyboard'; completion.start(now + 15, 2, 7)
expect(GuiService.SelectedObject, nil, 'mouse win does not steal focus')
lastInput = 'Gamepad'; completion.start(now + 15, 2, 7)
now += 16; RunService.RenderStepped:Fire()
expect(completion.continueButton.Selectable, false, 'deadline disables the buttons')
expect(GuiService.SelectedObject, nil, 'deadline drops the dead focus')
GuiService.SelectedObject = other; completion.reset()
expect(GuiService.SelectedObject, other, 'reset leaves unrelated focus alone')
end
-- ── a pad picked up while a modal is ALREADY open (Codex review) ───────
do
local lastInputChanged = signal()
local UIS = {LastInputTypeChanged = lastInputChanged}
local queueShade = {Visible = false}
local queueSubmit = button(queueShade)
local endFrame = {Visible = false}
local completion = {continueButton = {Visible = false, Active = false}, button = {Visible = false, Active = false}}
completion.buttons = {completion.continueButton, completion.button}
local pad, keyboard = {Name = 'Gamepad1'}, {Name = 'Keyboard'}
''' + switch_block + r'''
GuiService.SelectedObject, GuiService.MenuIsOpen = nil, false
queueShade.Visible = true
lastInputChanged:Fire(keyboard)
expect(GuiService.SelectedObject, nil, 'keyboard input takes no focus')
lastInputChanged:Fire(pad)
expect(GuiService.SelectedObject, queueSubmit, 'pad picked up with the party panel open selects CREATE PARTY')
local inside = button(queueShade); GuiService.SelectedObject = inside
lastInputChanged:Fire(pad)
expect(GuiService.SelectedObject, inside, 'an existing focus inside the panel is kept')
GuiService.SelectedObject, GuiService.MenuIsOpen = nil, true
lastInputChanged:Fire(pad)
expect(GuiService.SelectedObject, nil, 'Roblox menu open: hands off')
GuiService.MenuIsOpen, queueShade.Visible, endFrame.Visible = false, false, true
completion.continueButton.Visible, completion.continueButton.Active = true, true
completion.button.Visible, completion.button.Active = true, true
lastInputChanged:Fire(pad)
expect(GuiService.SelectedObject, completion.continueButton, 'pad on an open result screen selects CONTINUE')
GuiService.SelectedObject = completion.button
lastInputChanged:Fire(pad)
expect(GuiService.SelectedObject, completion.button, 'a chosen BACK TO LOBBY is kept')
GuiService.SelectedObject, completion.continueButton.Visible = nil, false
lastInputChanged:Fire(pad)
expect(GuiService.SelectedObject, completion.button, 'last level: BACK TO LOBBY')
GuiService.SelectedObject, completion.button.Active = nil, false
lastInputChanged:Fire(pad)
expect(GuiService.SelectedObject, nil, 'expired buttons take no focus')
end
print('RoundUI controller focus: ' .. checks .. ' checks passed (offline Luau; engine selection not exercised)')
'''


def main():
    binary = os.environ.get('LUAU_BIN') or shutil.which('luau')
    if not binary:
        raise SystemExit('Set LUAU_BIN or install luau; no tests were executed.')
    with tempfile.TemporaryDirectory(prefix='roundui-focus-') as directory:
        fixture = Path(directory) / 'roundui_controller_focus.luau'
        fixture.write_text(harness, encoding='utf-8')
        subprocess.run([binary, str(fixture)], check=True, timeout=20)


if __name__ == '__main__':
    main()
