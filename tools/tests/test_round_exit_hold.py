"""Run the whole Round Exit Client under offline Luau and hold the chip for real.

HOLD_TO_LEAVE_20260916 (Trello card 74, second pass). The script is not copied,
excerpted or string-matched: the entire LocalScript executes against a fake
DataModel, and every assertion below is made by DRIVING it -- pressing L,
stepping RenderStepped with a stated delta, focusing a text box, killing the
humanoid -- and then reading what the script did to its own instances and to the
RoundStatus remote.

The real ReplicatedStorage/UIStyle module is loaded under the same fake, because
the chip's chrome comes from it. UIDevice is faked, but only where its published
contract is: Binding() returns "" on a touchscreen, SetInteractive writes
Visible/Active, ScreenOwningModalOpen reads the four screen-owning attributes.

What this CANNOT see, and what the native QA pass in the report is for: the real
mouse lock, a real finger (including one that slides off the chip), font metrics
and TextBounds, whether the progress wash reads as progress, and whether the
engine clips the fill to the chip's rounded corner. Set LUAU_BIN, or put luau on
PATH.
"""

import os
from pathlib import Path
import shutil
import subprocess
import tempfile

ROOT = Path(__file__).resolve().parents[2]
SOURCE = ROOT / "StarterPlayer/StarterPlayerScripts/Round Exit Client.LocalScript.lua"
UISTYLE = ROOT / "ReplicatedStorage/UIStyle.ModuleScript.lua"

HARNESS = r'''
local checks = 0
local function check(value, message)
    assert(value, message)
    checks += 1
end

-- ── signals that really disconnect ───────────────────────────────────────
-- RenderStepped is connected and dropped once per hold, so a Disconnect that
-- did not actually remove the listener would let a cancelled hold keep filling.
local function signal()
    local listeners = {}
    local s = {}
    function s:Connect(fn)
        table.insert(listeners, fn)
        local conn = {Connected = true}
        function conn:Disconnect()
            for index, listener in ipairs(listeners) do
                if listener == fn then table.remove(listeners, index) break end
            end
            conn.Connected = false
        end
        return conn
    end
    function s:Fire(...)
        for _, fn in ipairs(table.clone(listeners)) do fn(...) end
    end
    function s:Count() return #listeners end
    return s
end

-- ── value types ──────────────────────────────────────────────────────────
-- Memoised so `==` answers "same value", the way Color3/UDim/EnumItem do.
local function memo(kind)
    local cache = {}
    return function(...)
        local key = kind .. ':' .. table.concat({...}, ',')
        if not cache[key] then cache[key] = {Kind = kind, Key = key} end
        return cache[key]
    end
end
local Color3 = {fromRGB = memo('Color3'), new = memo('Color3n')}
local UDim = {new = memo('UDim')}
local UDim2 = {
    new = function(sx, ox, sy, oy) return {Kind = 'UDim2', SX = sx, OX = ox, SY = sy, OY = oy} end,
    fromOffset = function(x, y) return {Kind = 'UDim2', SX = 0, OX = x, SY = 0, OY = y} end,
    fromScale = function(x, y) return {Kind = 'UDim2', SX = x, OX = 0, SY = y, OY = 0} end,
}
local Vector2 = {new = function(x, y) return {Kind = 'Vector2', X = x, Y = y} end}
local enumItems = {}
local Enum = setmetatable({}, {__index = function(_, group)
    return setmetatable({}, {__index = function(_, item)
        local key = group .. '.' .. item
        if not enumItems[key] then enumItems[key] = {Name = item, Group = group, Key = key} end
        return enumItems[key]
    end})
end})

-- ── instances ────────────────────────────────────────────────────────────
local SIGNALS = {
    InputBegan = true, InputEnded = true, Activated = true, MouseEnter = true,
    MouseLeave = true, Event = true, Died = true, HealthChanged = true,
    CharacterAdded = true, CharacterRemoving = true, OnClientEvent = true,
    RenderStepped = true, WindowFocusReleased = true, TextBoxFocused = true,
    TextBoxFocusReleased = true, Changed = true, DescendantAdded = true,
}
local methods = {}
local function newInstance(class, name)
    local fields = {
        ClassName = class, Name = name or class, Children = {}, Attributes = {},
        Watchers = {}, Visible = true, Active = false, Selectable = false,
        Modal = false, Text = '', TextScaled = false, Parent = nil,
    }
    local proxy
    proxy = setmetatable({}, {
        __index = function(_, key)
            local value = fields[key]
            if value ~= nil then return value end
            if SIGNALS[key] then fields[key] = signal() return fields[key] end
            return methods[key]
        end,
        __newindex = function(_, key, value)
            if key == 'Parent' and value ~= nil then table.insert(value.Children, proxy) end
            fields[key] = value
        end,
    })
    return proxy
end
local Instance = {new = newInstance}

function methods:IsA(class)
    if class == self.ClassName then return true end
    if class == 'GuiObject' then
        return self.ClassName == 'Frame' or self.ClassName == 'TextLabel'
            or self.ClassName == 'TextButton'
    end
    return false
end
function methods:FindFirstChild(name)
    for _, child in ipairs(self.Children) do if child.Name == name then return child end end
    return nil
end
function methods:FindFirstChildOfClass(class)
    for _, child in ipairs(self.Children) do if child.ClassName == class then return child end end
    return nil
end
function methods:GetDescendants()
    local out = {}
    for _, child in ipairs(self.Children) do
        table.insert(out, child)
        for _, nested in ipairs(child:GetDescendants()) do table.insert(out, nested) end
    end
    return out
end
function methods:WaitForChild(name)
    return assert(self:FindFirstChild(name), 'missing fixture child: ' .. name)
end
function methods:GetAttribute(key) return self.Attributes[key] end
function methods:Watcher(key)
    if not self.Watchers[key] then self.Watchers[key] = signal() end
    return self.Watchers[key]
end
function methods:SetAttribute(key, value)
    self.Attributes[key] = value
    if self.Watchers[key] then self.Watchers[key]:Fire() end
end
function methods:GetAttributeChangedSignal(key) return self:Watcher(key) end
function methods:GetPropertyChangedSignal(property) return self:Watcher('@' .. property) end
-- Writing a watched PROPERTY has to go through here: __newindex cannot fire the
-- signal without turning every property write in the script into a broadcast.
function methods:SetProperty(property, value)
    self[property] = value
    if self.Watchers['@' .. property] then self.Watchers['@' .. property]:Fire() end
end
local function descendant(root, name)
    for _, child in ipairs(root.Children) do
        if child.Name == name then return child end
        local found = descendant(child, name)
        if found then return found end
    end
    return nil
end

-- ── the fixture ──────────────────────────────────────────────────────────
local TOUCHSCREEN = {SafeLeft = 0, SafeTop = 36, SafeRight = 390, SafeBottom = 810,
    IsTouch = true, OriginX = 0, OriginY = 36}
local POINTER = {SafeLeft = 0, SafeTop = 36, SafeRight = 1280, SafeBottom = 720,
    IsTouch = false, OriginX = 0, OriginY = 36}

local function context(layout, withPrompt)
    local ctx = {Now = 0, Timers = {}, Sent = {}, FocusedTextBox = nil,
        LastInput = 'Keyboard', Layout = table.clone(layout or POINTER)}

    ctx.Workspace = newInstance('Workspace', 'Workspace')
    ctx.Workspace:SetAttribute('RoundActive', true)

    ctx.Player = newInstance('Player', 'Player')
    ctx.PlayerGui = newInstance('PlayerGui', 'PlayerGui')
    ctx.PlayerGui.Parent = ctx.Player
    ctx.PlayerScripts = newInstance('PlayerScripts', 'PlayerScripts')
    ctx.PlayerScripts.Parent = ctx.Player
    if withPrompt ~= false then
        ctx.Prompt = newInstance('BindableEvent', 'RoundExitPrompt')
        ctx.Prompt.Parent = ctx.PlayerScripts
    end
    ctx.Player:SetAttribute('InRound', true)
    ctx.Player:SetAttribute('RoundEntryControlsReady', true)

    ctx.Character = newInstance('Model', 'Character')
    ctx.Humanoid = newInstance('Humanoid', 'Humanoid')
    ctx.Humanoid.Health = 100
    ctx.Humanoid.Parent = ctx.Character
    ctx.Player.Character = ctx.Character

    ctx.Remote = newInstance('RemoteEvent', 'RoundStatus')
    function ctx.Remote:FireServer(event) table.insert(ctx.Sent, event) end
    local storage = newInstance('ReplicatedStorage', 'ReplicatedStorage')
    local remotes = newInstance('Folder', 'Remotes')
    remotes.Parent = storage
    ctx.Remote.Parent = remotes
    ctx.UIStyleModule = newInstance('ModuleScript', 'UIStyle')
    ctx.UIStyleModule.Parent = storage
    ctx.UIDeviceModule = newInstance('ModuleScript', 'UIDevice')
    ctx.UIDeviceModule.Parent = storage

    ctx.UIS = newInstance('UserInputService', 'UserInputService')
    ctx.UIS.GetFocusedTextBox = function() return ctx.FocusedTextBox end
    ctx.GuiService = newInstance('GuiService', 'GuiService')
    ctx.GuiService.MenuIsOpen = false
    ctx.GuiService.SelectedObject = nil
    ctx.RunService = newInstance('RunService', 'RunService')

    local services = {Players = {LocalPlayer = ctx.Player}, ReplicatedStorage = storage,
        GuiService = ctx.GuiService, RunService = ctx.RunService, UserInputService = ctx.UIS}
    ctx.Game = {GetService = function(_, name) return assert(services[name], name) end}

    ctx.Task = {}
    function ctx.Task.spawn(fn) fn() end
    function ctx.Task.delay(seconds, fn)
        table.insert(ctx.Timers, {At = ctx.Now + seconds, Fn = fn})
    end
    function ctx.Task.wait() end
    function ctx:Advance(seconds)
        local target = self.Now + seconds
        while true do
            local index, due = nil, nil
            for i, timer in ipairs(self.Timers) do
                if not due or timer.At < due.At then index, due = i, timer end
            end
            if not due or due.At > target then break end
            table.remove(self.Timers, index)
            self.Now = due.At
            due.Fn()
        end
        self.Now = target
    end

    -- The chip's own input objects. A touch hold is recognised by OBJECT
    -- identity, so the same table has to come back on release.
    ctx.Key = {KeyCode = Enum.KeyCode.L, UserInputType = Enum.UserInputType.Keyboard,
        UserInputState = Enum.UserInputState.Begin}
    ctx.Touch = {KeyCode = Enum.KeyCode.Unknown, UserInputType = Enum.UserInputType.Touch,
        UserInputState = Enum.UserInputState.Begin}
    return ctx
end

local function boot(ctx)
    local game, workspace, task = ctx.Game, ctx.Workspace, ctx.Task
    local UIStyleModule = (function()
'''

BRIDGE = r'''
    end)()
    -- UIDevice, faked only where its published contract is.
    local MODALS = {'ZyntraStoreOpen', 'DevPhoneOpen', 'ZyntraReentryOpen', 'QueueModalOpen'}
    local UIDeviceFake = {Changed = signal()}
    function UIDeviceFake.Layout() return ctx.Layout end
    function UIDeviceFake.LocalOffset(_, x, y)
        return x - ctx.Layout.OriginX, y - ctx.Layout.OriginY
    end
    function UIDeviceFake.SuppressesKeyboardGlyphs() return ctx.Layout.IsTouch end
    function UIDeviceFake.Binding(keyboard, _)
        if UIDeviceFake.SuppressesKeyboardGlyphs() then return '' end
        return keyboard or ''
    end
    function UIDeviceFake.LastInput() return ctx.LastInput end
    function UIDeviceFake.SetInteractive(element, visible)
        element.Visible = visible
        if element:IsA('TextButton') then
            element.Active = visible
            element.Selectable = visible
        end
    end
    function UIDeviceFake.SetEnabled(element, enabled)
        if element:IsA('TextButton') then element.Active = enabled end
    end
    function UIDeviceFake.ScreenOwningModalOpen()
        for _, attribute in ipairs(MODALS) do
            if ctx.Player:GetAttribute(attribute) == true then return true end
        end
        return false
    end
    function UIDeviceFake.OnScreenOwningModalChanged(callback)
        for _, attribute in ipairs(MODALS) do
            ctx.Player:GetAttributeChangedSignal(attribute):Connect(callback)
        end
    end
    ctx.UIDevice = UIDeviceFake
    local function require(module)
        if module.Name == 'UIDevice' then return UIDeviceFake end
        if module.Name == 'UIStyle' then return UIStyleModule end
        error('unexpected require: ' .. tostring(module.Name))
    end
'''

TESTS = r'''
end

-- ── driving it ───────────────────────────────────────────────────────────
local function start(layout, withPrompt)
    local ctx = context(layout, withPrompt)
    boot(ctx)
    ctx.Gui = descendant(ctx.PlayerGui, 'RoundExitGui')
    ctx.Chip = descendant(ctx.Gui, 'LeaveChip')
    ctx.Fill = descendant(ctx.Chip, 'HoldFill')
    ctx.Hint = descendant(ctx.Gui, 'HoldHint')
    ctx.Shade = descendant(ctx.Gui, 'RoundExitShade')
    ctx.Card = descendant(ctx.Gui, 'RoundExitCard')
    ctx.Confirm = descendant(ctx.Card, 'Confirm')
    ctx.Stay = descendant(ctx.Card, 'Stay')
    ctx.Notice = descendant(ctx.Card, 'Notice')
    return ctx
end
local function pressKey(ctx) ctx.UIS.InputBegan:Fire(ctx.Key, false) end
local function liftKey(ctx) ctx.UIS.InputEnded:Fire(ctx.Key) end
local function touchDown(ctx) ctx.Chip.InputBegan:Fire(ctx.Touch) end
local function touchUp(ctx) ctx.UIS.InputEnded:Fire(ctx.Touch) end
local function run(ctx, seconds, delta)
    delta = delta or 1 / 60
    local frames = math.ceil(seconds / delta)
    for _ = 1, frames do
        ctx.RunService.RenderStepped:Fire(delta)
        ctx:Advance(delta)
    end
end
local function progress(ctx) return ctx.Fill.Size.SX end
local function sent(ctx)
    local count = 0
    for _, event in ipairs(ctx.Sent) do if event == 'leaveround' then count += 1 end end
    return count
end

-- ── it is built, and it is a hold ────────────────────────────────────────
do
    local ctx = start(POINTER)
    check(ctx.Gui ~= nil, 'the ScreenGui is built')
    check(ctx.Chip ~= nil and ctx.Chip.ClassName == 'TextButton', 'the chip is a TextButton')
    check(ctx.Chip.Name == 'LeaveChip', 'the chip keeps the name the layout contracts use')
    check(ctx.Fill ~= nil and ctx.Fill.Parent == ctx.Chip, 'the progress fill lives in the chip')
    check(ctx.Hint ~= nil and ctx.Hint.Visible == false, 'the explanation is hidden at rest')
    check(ctx.Chip.Visible == true, 'an alive in-round player is offered the chip')
    check(ctx.Chip.Text == 'HOLD L • LOBBY', 'a keyboard is told which key to hold')
    check(progress(ctx) == 0, 'the bar starts empty')
    check(sent(ctx) == 0, 'building the UI sends nothing')
end
do
    local ctx = start(TOUCHSCREEN)
    check(ctx.Chip.Text == 'HOLD • LOBBY', 'a touchscreen is never told to press a key')
    check(ctx.Chip.Size.OY == 44, 'the touch chip keeps a 44px tap target')
    check(ctx.Chip.TextSize == 13, 'the touch chip prints one step larger')
end
do
    local ctx = start(POINTER, false)
    check(descendant(ctx.PlayerScripts, 'RoundExitPrompt') ~= nil,
        'the prompt bindable is created when SpectateController has not yet')
    check(ctx.Chip ~= nil, 'a missing prompt does not stop the chip being built')
end

-- ── a tap, a click and a short press leave nothing behind ────────────────
for _, case in ipairs({'key', 'touch'}) do
    local ctx = start(case == 'touch' and TOUCHSCREEN or POINTER)
    if case == 'touch' then touchDown(ctx) else pressKey(ctx) end
    run(ctx, 0.05)
    if case == 'touch' then touchUp(ctx) else liftKey(ctx) end
    run(ctx, 2)
    check(sent(ctx) == 0, case .. ': a tap alone never leaves the round')
    check(progress(ctx) == 0, case .. ': a tap leaves no progress behind')
    check(ctx.Hint.Visible == false, case .. ': a tap leaves no explanation on screen')
end
do
    local ctx = start(POINTER)
    ctx.Chip.Activated:Fire()
    run(ctx, 3)
    check(sent(ctx) == 0, 'clicking the chip does nothing at all -- there is no click path')
    check(ctx.Shade.Visible == false, 'clicking the chip no longer opens the confirm card')
end
do
    local ctx = start(POINTER)
    pressKey(ctx)
    run(ctx, 1.0)
    check(progress(ctx) > 0.6 and progress(ctx) < 0.72, 'the bar is two thirds full at 1.0 s')
    check(ctx.Hint.Visible == true, 'the explanation is shown while holding')
    check(ctx.Hint.Text == 'Leaving ends your run. The others keep playing.',
        'the explanation says the round goes on without them')
    liftKey(ctx)
    check(progress(ctx) == 0, 'releasing at 1.0 s resets the bar to empty immediately')
    check(ctx.Hint.Visible == false, 'releasing takes the explanation away')
    run(ctx, 3)
    check(sent(ctx) == 0, 'a cancelled hold never reaches the server')
    pressKey(ctx)
    run(ctx, 1.4)
    check(sent(ctx) == 0, 'the next hold starts from zero, not from where the last one stopped')
    run(ctx, 0.2)
    check(sent(ctx) == 1, 'and completes on its own full 1.5 s')
end

-- ── a completed hold ─────────────────────────────────────────────────────
do
    local ctx = start(POINTER)
    pressKey(ctx)
    run(ctx, 1.49, 0.01)
    check(sent(ctx) == 0, 'nothing is sent one frame before the hold is complete')
    check(progress(ctx) > 0.98, 'the bar is nearly full one frame before')
    run(ctx, 0.02, 0.01)
    check(sent(ctx) == 1, 'a full 1.5 s hold fires exactly one leaveround')
    check(ctx.Sent[1] == 'leaveround', 'the request is the authoritative one, unchanged')
    check(ctx.Chip.Text == 'RETURNING...', 'the chip says the request is out')
    check(progress(ctx) == 0, 'the bar is cleared once the request is out')
    check(ctx.Hint.Visible == false, 'the explanation goes with it')
    run(ctx, 4)
    check(sent(ctx) == 1, 'holding on past completion cannot send a second request')
    ctx.Remote.OnClientEvent:Fire('leaveack')
    check(ctx.Chip.Text == 'RETURNING TO LOBBY...', 'leaveack is reported on the chip')
    run(ctx, 12)
    check(sent(ctx) == 1, 'an acknowledged request never re-arms the no-answer timer')
    check(ctx.Chip.Text == 'RETURNING TO LOBBY...', 'the chip stays on the answered state')
end

-- ── one request, whatever the player does with the key ───────────────────
do
    local ctx = start(POINTER)
    pressKey(ctx)
    run(ctx, 1.6)
    check(sent(ctx) == 1, 'one hold, one request')
    ctx.Remote.OnClientEvent:Fire('leavefailed')
    check(ctx.Chip.Text == 'NOT AVAILABLE IN THIS TEST ROUND', 'a refusal is shown on the chip')
    -- Still physically held: a stuck key, or a player who never let go.
    pressKey(ctx)
    run(ctx, 2)
    check(sent(ctx) == 1, 'a key that never came up cannot start the next hold')
    liftKey(ctx)
    pressKey(ctx)
    run(ctx, 1.6)
    check(sent(ctx) == 2, 'released and pressed again, a refused request can be retried')
    check(ctx.Chip.Text == 'RETURNING...', 'the retry reports itself the same way')
end
do
    local ctx = start(TOUCHSCREEN)
    touchDown(ctx)
    run(ctx, 1.6)
    check(sent(ctx) == 1, 'a touch hold sends exactly one request')
    ctx.Remote.OnClientEvent:Fire('leavefailed')
    touchDown(ctx)
    run(ctx, 2)
    check(sent(ctx) == 1, 'a finger that never lifted cannot start the next hold')
    touchUp(ctx)
    touchDown(ctx)
    run(ctx, 1.6)
    check(sent(ctx) == 2, 'lifted and pressed again, the finger can retry')
end
do
    local ctx = start(POINTER)
    pressKey(ctx)
    run(ctx, 1.6)
    ctx.Remote.OnClientEvent:Fire('leavefailed')
    -- Losing the window is the only way a held key's release is never reported.
    ctx.UIS.WindowFocusReleased:Fire()
    pressKey(ctx)
    run(ctx, 1.6)
    check(sent(ctx) == 2, 'losing window focus clears the latch a swallowed release left')
end
do
    local ctx = start(POINTER)
    pressKey(ctx)
    run(ctx, 1.6)
    check(sent(ctx) == 1, 'the no-answer window starts with the request')
    run(ctx, 7.0)
    check(ctx.Chip.Text == 'RETURNING...', 'the chip waits out the whole no-answer window')
    run(ctx, 1.0)
    check(ctx.Chip.Text == 'NO ANSWER — HOLD AGAIN', 'silence is reported after 8 s')
    liftKey(ctx)
    pressKey(ctx)
    run(ctx, 1.6)
    check(sent(ctx) == 2, 'the timeout unlatches, so the player can ask again')
    run(ctx, 4)
    check(ctx.Chip.Text ~= 'NO ANSWER — HOLD AGAIN', 'a stale message is replaced, not queued')
end
do
    local ctx = start(POINTER)
    pressKey(ctx)
    run(ctx, 1.6)
    ctx.Remote.OnClientEvent:Fire('leavefailed')
    run(ctx, 2.9)
    check(ctx.Chip.Text == 'NOT AVAILABLE IN THIS TEST ROUND', 'the refusal stays up for 3 s')
    run(ctx, 0.2)
    check(ctx.Chip.Text == 'HOLD L • LOBBY', 'and then the chip goes back to the prompt')
    run(ctx, 10)
    check(ctx.Chip.Text == 'HOLD L • LOBBY', 'the answered request never trips the 8 s timer')
end

-- ── everything that has to cancel a hold in progress ─────────────────────
local function cancellations()
    return {
        {Name = 'a focused text box', Apply = function(ctx)
            ctx.FocusedTextBox = newInstance('TextBox', 'ChatInput')
            ctx.UIS.TextBoxFocused:Fire()
        end, ChipStays = true},
        {Name = 'the Roblox menu', Apply = function(ctx)
            ctx.GuiService:SetProperty('MenuIsOpen', true)
        end},
        {Name = 'the store modal', Apply = function(ctx)
            ctx.Player:SetAttribute('ZyntraStoreOpen', true)
        end},
        {Name = 'the queue modal', Apply = function(ctx)
            ctx.Player:SetAttribute('QueueModalOpen', true)
        end},
        {Name = 'the re-entry modal', Apply = function(ctx)
            ctx.Player:SetAttribute('ZyntraReentryOpen', true)
        end},
        {Name = 'the dispatch briefing', Apply = function(ctx)
            ctx.Player:SetAttribute('DispatchBriefingOpen', true)
        end},
        {Name = 'the Level 1 guide', Apply = function(ctx)
            ctx.Player:SetAttribute('LevelOneGuideObjectivesOpen', true)
        end},
        {Name = 'the PARTY DOWN card', Apply = function(ctx)
            ctx.Player:SetAttribute('PartyDownCardOpen', true)
        end},
        {Name = 'death', Apply = function(ctx)
            ctx.Humanoid.Health = 0
            ctx.Humanoid.Died:Fire()
        end},
        {Name = 'a respawn', Apply = function(ctx)
            ctx.Player.CharacterRemoving:Fire(ctx.Character)
        end},
        {Name = 'leaving the round', Apply = function(ctx)
            ctx.Player:SetAttribute('InRound', false)
        end},
        {Name = 'the round ending', Apply = function(ctx)
            ctx.Workspace:SetAttribute('RoundActive', false)
        end},
        {Name = 'spectating', Apply = function(ctx)
            ctx.Player:SetAttribute('Spectating', true)
        end},
        {Name = 'escaping', Apply = function(ctx)
            ctx.Player:SetAttribute('Escaped', true)
        end},
        {Name = 'the Level 2 exit transition', Apply = function(ctx)
            ctx.Player:SetAttribute('Level2_ExitTransition', true)
        end},
        {Name = 'controls being taken away', Apply = function(ctx)
            ctx.Player:SetAttribute('RoundEntryControlsReady', false)
        end},
        {Name = 'a round teardown event', Apply = function(ctx)
            ctx.Remote.OnClientEvent:Fire('lobby')
        end},
    }
end
for _, case in ipairs(cancellations()) do
    local ctx = start(POINTER)
    pressKey(ctx)
    run(ctx, 1.0)
    check(progress(ctx) > 0, case.Name .. ': the hold was running')
    case.Apply(ctx)
    check(progress(ctx) == 0, case.Name .. ' resets the bar at once')
    check(ctx.Hint.Visible == false, case.Name .. ' takes the explanation away')
    run(ctx, 3)
    check(sent(ctx) == 0, case.Name .. ' means the hold can never complete')
    if case.ChipStays then
        check(ctx.Chip.Visible == true,
            case.Name .. ' hides nothing: the way out stays legible while typing')
    end
end
-- The same list again with NO signal fired at all: the per-frame re-read is the
-- authority, and it is what catches a state nothing told this file about.
for _, silent in ipairs({'ZyntraStoreOpen', 'DispatchBriefingOpen', 'PartyDownCardOpen'}) do
    local ctx = start(POINTER)
    pressKey(ctx)
    run(ctx, 1.0)
    ctx.Player.Attributes[silent] = true -- set behind the signal's back
    run(ctx, 1)
    check(progress(ctx) == 0 and sent(ctx) == 0,
        'the per-frame re-read catches ' .. silent .. ' even with no signal')
end
do
    local ctx = start(POINTER)
    pressKey(ctx)
    run(ctx, 1.0)
    ctx.Humanoid.Health = 0 -- a silent death, no Died, no HealthChanged
    run(ctx, 1)
    check(sent(ctx) == 0, 'a hold cannot outlive the humanoid holding it')
end
do
    local ctx = start(POINTER)
    ctx.FocusedTextBox = newInstance('TextBox', 'ChatInput')
    pressKey(ctx)
    run(ctx, 2)
    check(sent(ctx) == 0, 'typing L into chat never starts a hold')
    check(progress(ctx) == 0, 'and never draws progress')
    ctx.FocusedTextBox = nil
    ctx.UIS.TextBoxFocusReleased:Fire()
    liftKey(ctx)
    pressKey(ctx)
    run(ctx, 1.6)
    check(sent(ctx) == 1, 'once the chat closes, L is the exit key again')
end
do
    local ctx = start(POINTER)
    ctx.UIS.InputBegan:Fire(ctx.Key, true) -- processed by the UI layer
    run(ctx, 2)
    check(sent(ctx) == 0, 'a key event another UI already consumed does not hold')
end
for _, other in ipairs({'K', 'M', 'Q', 'LeftShift'}) do
    local ctx = start(POINTER)
    ctx.UIS.InputBegan:Fire({KeyCode = Enum.KeyCode[other],
        UserInputType = Enum.UserInputType.Keyboard,
        UserInputState = Enum.UserInputState.Begin}, false)
    run(ctx, 2)
    check(sent(ctx) == 0, other .. ' is not the exit key')
end
do
    local ctx = start(POINTER)
    ctx.UIS.InputBegan:Fire({KeyCode = Enum.KeyCode.L,
        UserInputType = Enum.UserInputType.Keyboard,
        UserInputState = Enum.UserInputState.Change}, false)
    run(ctx, 2)
    check(sent(ctx) == 0, 'only a key going DOWN starts a hold')
end
do
    local ctx = start(POINTER)
    pressKey(ctx)
    run(ctx, 1.0)
    ctx.UIS.InputEnded:Fire({KeyCode = Enum.KeyCode.M,
        UserInputType = Enum.UserInputType.Keyboard})
    run(ctx, 0.6)
    check(sent(ctx) == 1, 'releasing a different key does not cancel the hold')
end
do
    local ctx = start(TOUCHSCREEN)
    touchDown(ctx)
    run(ctx, 1.0)
    -- A finger that slides off the chip before lifting: GuiObject.InputEnded is
    -- the signal that reports it, and it carries the same input object.
    ctx.Chip.InputEnded:Fire(ctx.Touch)
    check(progress(ctx) == 0, 'a finger leaving the chip cancels the hold')
    run(ctx, 2)
    check(sent(ctx) == 0, 'and nothing is sent')
end
for _, kind in ipairs({'Keyboard', 'Focus', 'Gamepad2'}) do
    local ctx = start(TOUCHSCREEN)
    ctx.Chip.InputBegan:Fire({KeyCode = Enum.KeyCode.Unknown,
        UserInputType = Enum.UserInputType[kind]})
    run(ctx, 2)
    check(sent(ctx) == 0, 'a ' .. kind .. ' input on the chip is not a hold')
end

-- ── the dead/escaped card still works, and shares the one latch ──────────
do
    local ctx = start(POINTER)
    ctx.Humanoid.Health = 0
    ctx.Player:SetAttribute('Spectating', true)
    ctx.Prompt.Event:Fire()
    check(ctx.Shade.Visible == true, 'the spectate band opens the confirm card')
    check(ctx.Player:GetAttribute('RoundExitPromptOpen') == true,
        'the card publishes the flag SpectateController lays out against')
    check(ctx.Chip.Visible == false, 'the chip stands down while the card is up')
    ctx.Stay.Activated:Fire()
    check(ctx.Shade.Visible == false, 'STAY closes the card')
    check(ctx.Player:GetAttribute('RoundExitPromptOpen') == nil, 'and clears the flag')
    check(sent(ctx) == 0, 'STAY sends nothing')
    ctx.Prompt.Event:Fire()
    ctx.Confirm.Activated:Fire()
    check(sent(ctx) == 1, 'BACK TO LOBBY sends exactly one request')
    check(ctx.Confirm.Text == 'RETURNING...', 'the card reports the request is out')
    check(ctx.Confirm.Active == false, 'and the button stops taking presses')
    ctx.Confirm.Activated:Fire()
    ctx.Confirm.Activated:Fire()
    check(sent(ctx) == 1, 'hammering the button cannot send a second request')
    ctx.Remote.OnClientEvent:Fire('leavefailed')
    check(ctx.Confirm.Text == 'BACK TO LOBBY', 'a refusal restores the button')
    check(ctx.Confirm.Active == true, 'and makes it pressable again')
    check(ctx.Notice.Text == 'Not available in this test round.',
        'the card explains the Studio-only refusal')
    ctx.Confirm.Activated:Fire()
    check(sent(ctx) == 2, 'retry from the card works')
end
do
    local ctx = start(POINTER)
    ctx.Prompt.Event:Fire()
    ctx.Confirm.Activated:Fire()
    run(ctx, 7.9)
    check(ctx.Confirm.Text == 'RETURNING...', 'the card waits out the same 8 s window')
    run(ctx, 0.2)
    check(ctx.Confirm.Text == 'TRY AGAIN', 'silence offers the card a retry too')
    check(ctx.Confirm.Active == true, 'and re-enables it')
end
do
    -- A hold completed, and THEN the player died. The card must show the
    -- request that is already in flight, not offer to send a second one.
    local ctx = start(POINTER)
    pressKey(ctx)
    run(ctx, 1.6)
    check(sent(ctx) == 1, 'the hold sent the request')
    ctx.Humanoid.Health = 0
    ctx.Humanoid.Died:Fire()
    ctx.Prompt.Event:Fire()
    check(ctx.Confirm.Text == 'RETURNING...', 'the card renders the pending request')
    check(ctx.Confirm.Active == false, 'a pending request disables the card button')
    ctx.Confirm.Activated:Fire()
    check(sent(ctx) == 1, 'the card cannot send a second request while one is pending')
end
do
    local ctx = start(POINTER)
    ctx.Prompt.Event:Fire()
    check(ctx.Shade.Visible == true, 'the card is up')
    pressKey(ctx)
    run(ctx, 2)
    check(sent(ctx) == 0, 'the key cannot hold behind an open card')
    check(progress(ctx) == 0, 'and draws no progress behind it')
end
for _, event in ipairs({'lobby', 'loadinggame', 'lose', 'win'}) do
    local ctx = start(POINTER)
    ctx.Prompt.Event:Fire()
    ctx.Confirm.Activated:Fire()
    ctx.Remote.OnClientEvent:Fire(event)
    check(ctx.Shade.Visible == false, event .. ' closes the card')
    check(ctx.Confirm.Text == 'BACK TO LOBBY', event .. ' puts the card back to rest')
    check(ctx.Chip.Text == 'HOLD L • LOBBY', event .. ' puts the chip back to rest')
end
do
    local ctx = start(POINTER)
    ctx.Player:SetAttribute('InRound', false)
    ctx.Prompt.Event:Fire()
    check(ctx.Shade.Visible == false, 'the card refuses to open outside a round')
    ctx.Player:SetAttribute('InRound', true)
    ctx.Workspace:SetAttribute('RoundActive', false)
    ctx.Prompt.Event:Fire()
    check(ctx.Shade.Visible == false, 'and refuses once the round is over')
end

-- ── frame-rate independence ──────────────────────────────────────────────
-- One frame of slack, because a float sum of ninety 1/60ths lands one ulp under
-- 1.5 and the ninety-first frame is 16ms later. What is being asserted is that
-- the hold costs the same WALL TIME at 2 FPS and at 144.
for _, delta in ipairs({0.5, 0.25, 0.03, 1 / 60, 1 / 144}) do
    local ctx = start(POINTER)
    pressKey(ctx)
    local frames = 0
    while sent(ctx) == 0 do
        ctx.RunService.RenderStepped:Fire(delta)
        frames += 1
        assert(frames < 2000, 'frame runaway')
    end
    check(math.abs(frames * delta - 1.5) <= delta + 1e-9,
        ('%d frames of %.4fs is 1.5s of holding, whatever the frame rate'):format(frames, delta))
    check(sent(ctx) == 1, ('a %.4fs frame rate still sends exactly one request'):format(delta))
end
do
    local ctx = start(POINTER)
    pressKey(ctx)
    ctx.RunService.RenderStepped:Fire(0.5)
    ctx.RunService.RenderStepped:Fire(0.5)
    check(sent(ctx) == 0, 'two 0.5s frames are only two thirds of a hold')
    check(math.abs(progress(ctx) - 2 / 3) < 1e-6, 'and the bar says exactly that')
end

-- ── layout: the chip and its explanation stay in the safe rect ───────────
do
    local ctx = start(TOUCHSCREEN)
    local puzzle = newInstance('ScreenGui', 'PuzzleGui')
    puzzle.Enabled = true
    puzzle.Parent = ctx.PlayerGui
    local counter = newInstance('Frame', 'Level1Objectives')
    counter.AbsolutePosition = Vector2.new(82, 44)
    counter.AbsoluteSize = Vector2.new(300, 106)
    counter.Parent = puzzle
    ctx.PlayerGui.DescendantAdded:Fire(counter)
    check(ctx.Chip.Position.OY + ctx.Layout.OriginY == 158,
        'portrait leave chip clears the actual objective bottom by8px')
    counter:SetProperty('AbsoluteSize', Vector2.new(300, 160))
    check(ctx.Chip.Position.OY + ctx.Layout.OriginY == 212,
        'a taller objective message moves the chip immediately')
    local guide = newInstance('ScreenGui', 'LevelOneGuideGui')
    guide.Enabled = true
    guide.Parent = ctx.PlayerGui
    local button = newInstance('TextButton', 'ObjectivesButton')
    button.AbsolutePosition = Vector2.new(12, 212)
    button.AbsoluteSize = Vector2.new(168, 44)
    button.Parent = guide
    ctx.PlayerGui.DescendantAdded:Fire(button)
    check(ctx.Chip.Position.OY + ctx.Layout.OriginY == 264,
        'leave chip also clears Mission Brief after it moves below objectives')
    button:SetProperty('Visible', false)
    check(ctx.Chip.Position.OY + ctx.Layout.OriginY == 212,
        'a hidden brief does not leave a phantom reserved row')
    counter:SetProperty('AbsolutePosition', Vector2.new(460, 44))
    check(ctx.Chip.Position.OY + ctx.Layout.OriginY == ctx.Layout.SafeTop + 12,
        'a landscape objective beside the chip does not push it down')
end
local VIEWPORTS = {
    {Name = 'phone portrait 390x844', IsTouch = true, SafeLeft = 0, SafeTop = 59,
        SafeRight = 390, SafeBottom = 810, OriginX = 0, OriginY = 36},
    {Name = 'phone landscape 844x390', IsTouch = true, SafeLeft = 50, SafeTop = 36,
        SafeRight = 794, SafeBottom = 369, OriginX = 0, OriginY = 36},
    {Name = 'tablet landscape 705x338 with a gui inset', IsTouch = true, SafeLeft = 44,
        SafeTop = 36, SafeRight = 661, SafeBottom = 317, OriginX = 44, OriginY = 36},
    {Name = 'desktop 1280x720', IsTouch = false, SafeLeft = 0, SafeTop = 36,
        SafeRight = 1280, SafeBottom = 720, OriginX = 0, OriginY = 36},
}
for _, viewport in ipairs(VIEWPORTS) do
    local ctx = start(viewport)
    local function rect(element)
        local left = element.Position.OX + viewport.OriginX
        local top = element.Position.OY + viewport.OriginY
        return left, top, left + element.Size.OX, top + element.Size.OY
    end
    local cl, ct, cr, cb = rect(ctx.Chip)
    local hl, ht, hr, hb = rect(ctx.Hint)
    check(cl >= viewport.SafeLeft and cr <= viewport.SafeRight,
        viewport.Name .. ': the chip is inside the safe columns')
    check(ct >= viewport.SafeTop and cb <= viewport.SafeBottom,
        viewport.Name .. ': the chip is inside the safe rows')
    check(hl >= viewport.SafeLeft and hr <= viewport.SafeRight,
        viewport.Name .. ': the explanation is inside the safe columns')
    check(ht >= viewport.SafeTop and hb <= viewport.SafeBottom,
        viewport.Name .. ': the explanation is inside the safe rows')
    check(hl == cl, viewport.Name .. ': the explanation is left-aligned with the chip')
    check(ht >= cb, viewport.Name .. ': the explanation sits UNDER the chip, never over it')
    check(hr <= viewport.SafeRight - 12,
        viewport.Name .. ': the explanation keeps a margin off the safe right edge')
    check(ctx.Chip.Size.OY == (viewport.IsTouch and 44 or 30),
        viewport.Name .. ': the tap target is the device-correct height')
    check(ctx.Chip.Size.OX >= 156, viewport.Name .. ': the chip is wide enough for its copy')
    local width = math.min(340, math.max(240, viewport.SafeRight - viewport.SafeLeft - 24))
    check(ctx.Card.Size.OX == width, viewport.Name .. ': the confirm card keeps its fit')
    -- A landscape phone is the tightest row budget in the game; if the band ever
    -- reached the movement zone this is where it would show up first.
    check(hb <= viewport.SafeBottom - 0, viewport.Name .. ': nothing runs off the bottom')
end
do
    -- A device rotation re-lays the chip out and repaints the binding, because
    -- the glyph is suppressed on one form factor and not the other.
    local ctx = start(POINTER)
    check(ctx.Chip.Text == 'HOLD L • LOBBY', 'desktop prints the key')
    ctx.Layout = table.clone(TOUCHSCREEN)
    ctx.UIDevice.Changed:Fire()
    check(ctx.Chip.Text == 'HOLD • LOBBY', 'becoming a touchscreen drops the glyph')
    check(ctx.Chip.Size.OY == 44, 'and takes the touch tap target')
    ctx.Layout = table.clone(POINTER)
    ctx.UIDevice.Changed:Fire()
    check(ctx.Chip.Text == 'HOLD L • LOBBY', 'and back again')
end
do
    -- A layout change in the middle of a refusal must not wipe the message.
    local ctx = start(POINTER)
    pressKey(ctx)
    run(ctx, 1.6)
    ctx.Remote.OnClientEvent:Fire('leavefailed')
    ctx.UIDevice.Changed:Fire()
    check(ctx.Chip.Text == 'NOT AVAILABLE IN THIS TEST ROUND',
        'a rotation does not wipe the message the player has not read yet')
    run(ctx, 3.2)
    check(ctx.Chip.Text == 'HOLD L • LOBBY', 'and the message still expires on time')
end

-- ── availability ─────────────────────────────────────────────────────────
for _, case in ipairs({
    {Name = 'not in a round', Apply = function(ctx) ctx.Player:SetAttribute('InRound', false) end},
    {Name = 'no active round', Apply = function(ctx) ctx.Workspace:SetAttribute('RoundActive', false) end},
    {Name = 'dead', Apply = function(ctx) ctx.Humanoid.Health = 0 ctx.Humanoid.Died:Fire() end},
    {Name = 'spectating', Apply = function(ctx) ctx.Player:SetAttribute('Spectating', true) end},
    {Name = 'escaped', Apply = function(ctx) ctx.Player:SetAttribute('Escaped', true) end},
    {Name = 'in the Level 2 exit', Apply = function(ctx) ctx.Player:SetAttribute('Level2_ExitTransition', true) end},
    {Name = 'without controls', Apply = function(ctx) ctx.Player:SetAttribute('RoundEntryControlsReady', false) end},
    {Name = 'reading the briefing', Apply = function(ctx) ctx.Player:SetAttribute('DispatchBriefingOpen', true) end},
    {Name = 'reading the guide', Apply = function(ctx) ctx.Player:SetAttribute('LevelOneGuideObjectivesOpen', true) end},
    {Name = 'under PARTY DOWN', Apply = function(ctx) ctx.Player:SetAttribute('PartyDownCardOpen', true) end},
    {Name = 'in the store', Apply = function(ctx) ctx.Player:SetAttribute('ZyntraStoreOpen', true) end},
    {Name = 'in the Roblox menu', Apply = function(ctx) ctx.GuiService:SetProperty('MenuIsOpen', true) end},
}) do
    local ctx = start(POINTER)
    check(ctx.Chip.Visible == true, case.Name .. ': the chip started available')
    case.Apply(ctx)
    check(ctx.Chip.Visible == false, case.Name .. ': the chip stands down')
    check(ctx.Chip.Active == false, case.Name .. ': and stops taking input')
    pressKey(ctx)
    run(ctx, 2)
    check(sent(ctx) == 0, case.Name .. ': and the key cannot leave the round either')
end

print('Round Exit hold: ' .. checks
    .. ' checks passed (entire actual LocalScript, offline Luau;'
    .. ' real cursor lock, real touch and font metrics not exercised)')
'''


def main():
    binary = os.environ.get("LUAU_BIN") or shutil.which("luau")
    if not binary:
        raise SystemExit("Set LUAU_BIN or install luau; no tests were executed.")
    source = "".join([
        HARNESS,
        UISTYLE.read_text(encoding="utf-8"),
        BRIDGE,
        SOURCE.read_text(encoding="utf-8"),
        TESTS,
    ])
    with tempfile.TemporaryDirectory(prefix="round-exit-hold-") as directory:
        path = Path(directory) / "round_exit_hold.luau"
        path.write_text(source, encoding="utf-8")
        subprocess.run([binary, str(path)], check=True, timeout=60)


if __name__ == "__main__":
    main()
