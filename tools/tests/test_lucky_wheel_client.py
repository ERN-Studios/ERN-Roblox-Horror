"""Run the whole Lucky Wheel Client under offline Luau and spin it for real.

LUCKY_WHEEL_TAKEOVER_20260916. The LocalScript is not copied, excerpted or
string-matched: the entire file executes against a fake DataModel, and every
assertion below is made by DRIVING it -- firing the open bindable, pressing the
hub, pushing a profile with a new WheelLast.Serial, stepping Heartbeat, rotating
the device, parenting a foreign ScreenGui into PlayerGui while the wheel is open
-- and then reading what the script did to its own instances, to the other guis,
to the ZyntraAction remote and to the tween it asked for.

The REAL ReplicatedStorage/UIStyle and ReplicatedStorage/ZyntraConfig modules
are loaded under the same fake, so the five fields, their copy and their odds
strings are built from the SERVER'S OWN weights rather than from numbers this
test made up. UIDevice is faked, but only where its published contract is:
Layout() answers a stated Display/Safe pair, ScreenOwningModalOpen() reads the
modal attribute list, SetEnabled/SetInteractive write Active/Visible,
SuppressTouchMovement records the caller's intent. TweenService is faked so the
test can read the goal the script asked for and finish or cancel it on demand.

What this CANNOT see, and what the Studio QA pass in the report is for: whether
rbxassetid://86770264881525 actually loads and how its rim lines up with the
pointer, real font metrics and TextBounds (so whether "1 SPEED POTION" fits a
335px disc's field), the real 4.2 s Quint feel, and whether a landscape phone's
topbar clips the top of a disc centred on the whole display.

Set LUAU_BIN, or put luau on PATH.
"""

import os
from pathlib import Path
import shutil
import subprocess
import tempfile

ROOT = Path(__file__).resolve().parents[2]
SOURCE = ROOT / "StarterPlayer/StarterPlayerScripts/Lucky Wheel Client.LocalScript.lua"
UISTYLE = ROOT / "ReplicatedStorage/UIStyle.ModuleScript.lua"
CONFIG = ROOT / "ReplicatedStorage/ZyntraConfig.ModuleScript.lua"

HARNESS = r'''
local checks = 0
local function check(value, message)
    assert(value, message)
    checks += 1
end

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
-- Memoised so `==` answers "same value", the way the engine's do. Color3 keeps
-- R/G/B in 0..1; it offers NO operators, so an edit that tried to do arithmetic
-- on a Color3 would fail here rather than at runtime in Studio.
local colorCache = {}
local Color3 = {}
function Color3.fromRGB(r, g, b)
    r, g, b = math.floor(r + 0.5), math.floor(g + 0.5), math.floor(b + 0.5)
    local key = ('%d,%d,%d'):format(r, g, b)
    if not colorCache[key] then
        colorCache[key] = {Kind = 'Color3', Key = key, R = r / 255, G = g / 255, B = b / 255}
    end
    return colorCache[key]
end
function Color3.new(r, g, b)
    return Color3.fromRGB((r or 0) * 255, (g or 0) * 255, (b or 0) * 255)
end

-- Omitted components are ZERO, exactly as the engine's constructors are:
-- UDim2.new() is (0,0,0,0), not four nils, and a test that let them be nil
-- would silently pass a comparison the engine would fail.
local UDim = {new = function(s, o) return {Kind = 'UDim', S = s or 0, O = o or 0} end}
local UDim2 = {
    new = function(sx, ox, sy, oy)
        return {Kind = 'UDim2', SX = sx or 0, OX = ox or 0, SY = sy or 0, OY = oy or 0}
    end,
    fromOffset = function(x, y) return {Kind = 'UDim2', SX = 0, OX = x, SY = 0, OY = y} end,
    fromScale = function(x, y) return {Kind = 'UDim2', SX = x, OX = 0, SY = y, OY = 0} end,
}
local Vector2 = {new = function(x, y) return {Kind = 'Vector2', X = x, Y = y} end}
local TweenInfo = {new = function(time, style, direction)
    return {Kind = 'TweenInfo', Time = time, Style = style, Direction = direction}
end}
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
    MouseLeave = true, Event = true, OnClientEvent = true, Heartbeat = true,
    Changed = true, DescendantAdded = true, ChildAdded = true, Completed = true,
    CharacterAdded = true,
}
local methods = {}
local function newInstance(class, name)
    local fields = {
        ClassName = class, Name = name or class, Children = {}, Attributes = {},
        Watchers = {}, Visible = true, Active = false, Selectable = false,
        Modal = false, Text = '', TextScaled = false, Rotation = 0, Parent = nil,
        ZIndex = 1,
    }
    -- The three classes whose non-default properties this file reads back.
    if class == 'ScreenGui' then fields.Enabled = true end
    if class == 'ImageLabel' or class == 'ImageButton' then
        fields.Image = ''
        fields.ScaleType = Enum.ScaleType.Stretch
        fields.ImageColor3 = Color3.new(1, 1, 1)
        fields.IsLoaded = false
    end
    local proxy
    proxy = setmetatable({}, {
        __index = function(_, key)
            local value = fields[key]
            if value ~= nil then return value end
            if SIGNALS[key] then fields[key] = signal() return fields[key] end
            return methods[key]
        end,
        __newindex = function(_, key, value)
            -- Reparenting REMOVES from the old parent, the way the engine does,
            -- and the new parent's ChildAdded fires AFTER .Parent is already the
            -- new one -- which is what the wheel's takeover listener relies on.
            if key == 'Parent' then
                local old = fields.Parent
                if old then
                    for index, child in ipairs(old.Children) do
                        if child == proxy then table.remove(old.Children, index) break end
                    end
                end
                fields.Parent = value
                if value ~= nil then
                    table.insert(value.Children, proxy)
                    value.ChildAdded:Fire(proxy)
                end
                return
            end
            fields[key] = value
            -- A property write fires its GetPropertyChangedSignal watcher, the
            -- way the engine does; the takeover's Enabled watcher relies on it.
            local watcher = fields.Watchers and fields.Watchers['@' .. key]
            if watcher then watcher:Fire() end
        end,
    })
    return proxy
end
local Instance = {new = newInstance}

function methods:IsA(class)
    if class == self.ClassName then return true end
    if class == 'GuiObject' then
        return self.ClassName == 'Frame' or self.ClassName == 'TextLabel'
            or self.ClassName == 'TextButton' or self.ClassName == 'ImageLabel'
            or self.ClassName == 'ImageButton' or self.ClassName == 'ScrollingFrame'
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
function methods:GetChildren() return table.clone(self.Children) end
function methods:GetDescendants()
    local out = {}
    for _, child in ipairs(self.Children) do
        table.insert(out, child)
        for _, nested in ipairs(child:GetDescendants()) do table.insert(out, nested) end
    end
    return out
end
function methods:Destroy() self.Parent = nil end
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

local function descendant(root, name)
    for _, child in ipairs(root.Children) do
        if child.Name == name then return child end
        local found = descendant(child, name)
        if found then return found end
    end
    return nil
end

-- ── stated viewports ─────────────────────────────────────────────────────
-- Each row states the DISPLAY (the whole screen) and the SAFE rectangle inside
-- it. SAFE is what both the disc and the X are measured against: the gui uses
-- CoreUISafeInsets, so its origin IS the safe top-left, which is what
-- LocalOffset subtracts below, and a disc sized off the whole display would put
-- its pointer under the topbar on a landscape phone.
local function viewport(width, height, touch, insets)
    insets = insets or {}
    local display = {Left = 0, Top = 0, Right = width, Bottom = height}
    local safe = {
        Left = display.Left + (insets.Left or 0),
        Top = display.Top + (insets.Top or 0),
        Right = display.Right - (insets.Right or 0),
        Bottom = display.Bottom - (insets.Bottom or 0),
    }
    return {IsTouch = touch, Display = display, Safe = safe,
        OriginX = safe.Left, OriginY = safe.Top, W = width, H = height,
        SW = safe.Right - safe.Left, SH = safe.Bottom - safe.Top}
end
-- Every row carries the 58px topbar band the contract's worked examples assume
-- (measured on an iPhone 16 Pro Max; a desktop Studio window reports 36, which
-- only makes the disc BIGGER, so 58 is the conservative row). The two landscape
-- phones also carry that device's measured 62px housing on each side.
local POINTER = viewport(1280, 720, false, {Top = 58})
local PHONE_PORTRAIT = viewport(390, 844, true, {Top = 58})
local PHONE_LANDSCAPE = viewport(844, 390, true, {Top = 58, Left = 62, Right = 62})
local TABLET = viewport(1024, 768, true, {Top = 58})
local SHORT_LANDSCAPE = viewport(705, 338, true, {Top = 58})
local EMULATOR = viewport(749, 368, true, {Top = 58, Left = 62, Right = 62})

-- ── the fixture ──────────────────────────────────────────────────────────
local function context(layout)
    local ctx = {Now = 1000, Timers = {}, Sent = {}, Tweens = {}, Suppress = {},
        Invokes = 0, ProfileAnswer = nil, LastInput = 'Keyboard', IsStudio = false,
        Bound = {}, Layout = layout or POINTER}

    ctx.Workspace = newInstance('Workspace', 'Workspace')
    ctx.Workspace.GetServerTimeNow = function() return ctx.Now end

    ctx.Player = newInstance('Player', 'Player')
    ctx.PlayerGui = newInstance('PlayerGui', 'PlayerGui')
    ctx.PlayerGui.Parent = ctx.Player
    ctx.PlayerScripts = newInstance('PlayerScripts', 'PlayerScripts')
    ctx.PlayerScripts.Parent = ctx.Player

    local storage = newInstance('ReplicatedStorage', 'ReplicatedStorage')
    ctx.UIStyleModule = newInstance('ModuleScript', 'UIStyle')
    ctx.UIStyleModule.Parent = storage
    ctx.UIDeviceModule = newInstance('ModuleScript', 'UIDevice')
    ctx.UIDeviceModule.Parent = storage
    ctx.ConfigModule = newInstance('ModuleScript', 'ZyntraConfig')
    ctx.ConfigModule.Parent = storage

    local remotes = newInstance('Folder', 'Remotes')
    remotes.Parent = storage
    ctx.Action = newInstance('RemoteEvent', 'ZyntraAction')
    ctx.Action.FireServer = function(_, action, payload)
        table.insert(ctx.Sent, {Action = action, Payload = payload})
    end
    ctx.Action.Parent = remotes
    ctx.GetProfile = newInstance('RemoteFunction', 'ZyntraGetProfile')
    ctx.GetProfile.InvokeServer = function()
        ctx.Invokes += 1
        return ctx.ProfileAnswer
    end
    ctx.GetProfile.Parent = remotes
    ctx.Pushes = newInstance('RemoteEvent', 'ZyntraProfileChanged')
    ctx.Pushes.Parent = remotes

    ctx.UIS = newInstance('UserInputService', 'UserInputService')
    ctx.GuiService = newInstance('GuiService', 'GuiService')
    ctx.GuiService.MenuIsOpen = false
    ctx.GuiService.SelectedObject = nil
    ctx.RunService = newInstance('RunService', 'RunService')
    ctx.RunService.IsStudio = function() return ctx.IsStudio end

    -- TweenService, recorded rather than run: the test reads the GOAL the
    -- script asked for and decides itself when the tween ends.
    ctx.TweenService = newInstance('TweenService', 'TweenService')
    ctx.TweenService.Create = function(_, instance, info, goal)
        local tween = {Instance = instance, Info = info, Goal = goal,
            Played = false, Cancelled = false, Finished = false}
        tween.Completed = signal()
        function tween:Play() self.Played = true end
        function tween:Cancel()
            self.Cancelled = true
            self.Completed:Fire(Enum.PlaybackState.Cancelled)
        end
        function tween:Finish()
            self.Finished = true
            for key, value in pairs(self.Goal) do self.Instance[key] = value end
            self.Completed:Fire(Enum.PlaybackState.Completed)
        end
        table.insert(ctx.Tweens, tween)
        return tween
    end

    ctx.CAS = newInstance('ContextActionService', 'ContextActionService')
    ctx.CAS.BindActionAtPriority = function(_, name, handler)
        ctx.Bound[name] = handler
    end
    ctx.CAS.UnbindAction = function(_, name) ctx.Bound[name] = nil end

    local services = {Players = {LocalPlayer = ctx.Player}, ReplicatedStorage = storage,
        GuiService = ctx.GuiService, RunService = ctx.RunService,
        UserInputService = ctx.UIS, TweenService = ctx.TweenService,
        ContextActionService = ctx.CAS}
    ctx.Game = {GetService = function(_, name) return assert(services[name], name) end}

    ctx.Task = {}
    function ctx.Task.spawn(fn) fn() end
    function ctx.Task.defer(fn) fn() end
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
    return ctx
end

local function boot(ctx)
    local game, workspace, task = ctx.Game, ctx.Workspace, ctx.Task
    local UIStyleModule = (function()
'''

BRIDGE_CONFIG = r'''
    end)()
    local ConfigModule = (function()
'''

BRIDGE = r'''
    end)()
    -- UIDevice, faked only where its published contract is. The modal list is
    -- the shipped one: the wheel's own flag is in it, which is what makes
    -- SuppressTouchMovement(ScreenOwningModalOpen()) true on open.
    local MODALS = {'ZyntraStoreOpen', 'DevPhoneOpen', 'ZyntraReentryOpen',
        'QueueModalOpen', 'LuckyWheelOpen', 'DailyRewardsOpen'}
    local UIDeviceFake = {Changed = signal()}
    function UIDeviceFake.Layout() return ctx.Layout end
    function UIDeviceFake.LocalOffset(_, x, y)
        return x - ctx.Layout.OriginX, y - ctx.Layout.OriginY
    end
    function UIDeviceFake.LocalPosition(gui, x, y)
        local lx, ly = UIDeviceFake.LocalOffset(gui, x, y)
        return UDim2.fromOffset(math.floor(lx), math.floor(ly))
    end
    function UIDeviceFake.SuppressesKeyboardGlyphs() return ctx.Layout.IsTouch end
    function UIDeviceFake.LastInput() return ctx.LastInput end
    function UIDeviceFake.SuppressTouchMovement(active)
        table.insert(ctx.Suppress, active == true)
    end
    function UIDeviceFake.SetEnabled(element, enabled)
        if element:IsA('TextButton') then
            element.Active = enabled
            element.Selectable = enabled
        end
    end
    function UIDeviceFake.SetInteractive(element, visible)
        element.Visible = visible
        if element:IsA('TextButton') then
            element.Active = visible
            element.Selectable = visible
        end
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
    ctx.Config = ConfigModule
    local function require(module)
        if module.Name == 'UIDevice' then return UIDeviceFake end
        if module.Name == 'UIStyle' then return UIStyleModule end
        if module.Name == 'ZyntraConfig' then return ConfigModule end
        error('unexpected require: ' .. tostring(module.Name))
    end
'''

TESTS = r'''
end

-- ── driving it ───────────────────────────────────────────────────────────
local TODAY = '2026-09-16'
local DISC_IMAGE = 'rbxassetid://86770264881525'

local function start(layout, options)
    options = options or {}
    local ctx = context(layout)
    ctx.IsStudio = options.Studio == true
    ctx.LastInput = options.LastInput or 'Keyboard'
    if options.Prompt ~= false then
        ctx.OpenEvent = newInstance('BindableEvent', 'OpenLuckyWheel')
        ctx.OpenEvent.Parent = ctx.PlayerScripts
    end
    boot(ctx)
    ctx.OpenEvent = descendant(ctx.PlayerScripts, 'OpenLuckyWheel')
    ctx.Gui = descendant(ctx.PlayerGui, 'LuckyWheelGui')
    ctx.Shade = descendant(ctx.Gui, 'WheelShade')
    ctx.Holder = descendant(ctx.Shade, 'WheelHolder')
    ctx.Disc = descendant(ctx.Holder, 'WheelDisc')
    ctx.Pointer = descendant(ctx.Holder, 'WheelPointer')
    ctx.Hub = descendant(ctx.Holder, 'HubButton')
    ctx.Close = descendant(ctx.Shade, 'CloseButton')
    return ctx
end

local function open(ctx) ctx.OpenEvent.Event:Fire() end
local function tick(ctx, seconds)
    local step = 1 / 30
    for _ = 1, math.ceil(seconds / step) do
        ctx.RunService.Heartbeat:Fire(step)
        ctx.Now += step
    end
end
-- A foreign HUD: the rail, the currency chip, the objectives panel -- anything
-- the takeover has to stand down and put back.
local function addGui(ctx, name, enabled)
    local other = newInstance('ScreenGui', name)
    if enabled ~= nil then other.Enabled = enabled end
    other.Parent = ctx.PlayerGui
    return other
end

-- A profile as ZyntraMonetization publishes it: the Daily block and nothing the
-- client is allowed to invent.
local function daily(options)
    options = options or {}
    local block = {
        Day = TODAY, Today = TODAY, PlaytimeSeconds = options.Played or 0,
        Claimed = {}, SecondsToReset = options.Reset or 3600, Accruing = false,
    }
    if options.Key then
        block.WheelDay = options.Day or TODAY
        block.WheelLast = {Day = options.Day or TODAY, Key = options.Key, Serial = options.Serial or 1,
            -- WHEEL_COLLECT_20260922: a spin records, the claim pays. Omitted =
            -- an old, already-paid result (the server normalizes it to true).
            Claimed = options.Claimed}
    end
    return {Daily = block, Tokens = 0}
end
local function push(ctx, profile) ctx.Pushes.OnClientEvent:Fire(profile) end

-- The five prizes, read off the REAL config, with the EQUAL field each one owns.
local WHEEL = {}
local FIELD = 0
do
    local ctx = start(POINTER)
    local total = 0
    for _, entry in ipairs(ctx.Config.DailyRewards.Wheel) do total += entry.Weight end
    FIELD = 360 / #ctx.Config.DailyRewards.Wheel
    for order, entry in ipairs(ctx.Config.DailyRewards.Wheel) do
        table.insert(WHEEL, {Order = order, Key = entry.Key, Label = entry.Label,
            Weight = entry.Weight, Angle = FIELD * (order - 1),
            Odds = tostring(math.floor(entry.Weight / total * 100 + 0.5)) .. '%'})
    end
    check(#WHEEL == 5, 'the shipped config has five prizes')
    check(total == 100, 'the shipped weights total 100, so a weight IS a percent')
    check(FIELD == 72, 'five equal fields are 72 degrees each')
end
-- The copy the fields carry, long and short. Derived here the same way the
-- script does, so a config edit moves both together.
local LONG = {'1 TOKEN', '3 TOKENS', '1 SPEED POTION', '2 SPEED POTIONS', '1 ENTITY SHIELD'}
local SHORT = {'1 TOKEN', '3 TOKENS', '1 POTION', '2 POTIONS', '1 SHIELD'}

-- Where the stationary pointer at 12 o'clock is looking, given a Rotation.
local function pointerAngle(rotation) return (-rotation) % 360 end
-- How far INTO field `order` that angle is: [0, 72) means it is inside, and the
-- modulo is what carries field 1, whose wedge straddles 0 as [324, 360)+[0,36).
local function into(angle, order)
    return (angle - (FIELD * (order - 1) - FIELD / 2)) % 360
end
local function fieldOf(angle)
    for _, prize in ipairs(WHEEL) do
        if into(angle, prize.Order) < FIELD then return prize end
    end
    return nil
end

-- ── it is built, and it is the disc and nothing else ─────────────────────
do
    local ctx = start(POINTER)
    check(ctx.Gui ~= nil and ctx.Gui.ClassName == 'ScreenGui', 'the ScreenGui is built')
    check(ctx.Gui.Name == 'LuckyWheelGui', 'it carries the contracted name')
    check(ctx.Gui.DisplayOrder == 118, 'DisplayOrder 118, as the contract fixes it')
    check(ctx.Gui.ResetOnSpawn == false, 'it survives a respawn')
    check(ctx.Gui.ScreenInsets == Enum.ScreenInsets.CoreUISafeInsets,
        'it lives in the terminal\'s inset space')
    check(ctx.Shade ~= nil and ctx.Shade.Active == true,
        'the shade is Active, so a tap past the disc reaches nothing behind it')
    check(ctx.Shade.BackgroundTransparency == 0.35, 'the dimming is discreet, not opaque')
    check(ctx.Shade.Size.SX == 1 and ctx.Shade.Size.SY == 1, 'and it covers the screen')
    check(ctx.Shade.Visible == false, 'nothing is drawn until the rail asks for it')

    check(ctx.Disc.ClassName == 'ImageLabel', 'the disc is an ImageLabel, not 180 frames')
    check(ctx.Disc.Image == DISC_IMAGE, 'and it is the uploaded wheel texture')
    check(ctx.Disc.ScaleType == Enum.ScaleType.Fit,
        'Fit, so a non-square holder could never squash it into an ellipse')
    check(ctx.Disc.BackgroundTransparency == 1, 'the art carries its own background')
    check(ctx.Disc.Size.SX == 1 and ctx.Disc.Size.SY == 1
        and ctx.Disc.Size.OX == 0 and ctx.Disc.Size.OY == 0,
        'the disc fills the holder by scale, so one number sizes the wheel')
    check(ctx.Disc.AnchorPoint.X == 0.5 and ctx.Disc.AnchorPoint.Y == 0.5
        and ctx.Disc.Position.SX == 0.5 and ctx.Disc.Position.SY == 0.5,
        'and it is centred in it, which is the pivot Rotation turns about')
    check(ctx.Holder.AnchorPoint.X == 0.5 and ctx.Holder.AnchorPoint.Y == 0.5,
        'the holder is centred on its own position')

    check(ctx.Pointer.Parent == ctx.Holder,
        'the pointer is NOT a child of the disc, so it never turns with it')
    check(ctx.Hub.Parent == ctx.Holder, 'and neither is the hub')
    check(ctx.Hub.ClassName == 'TextButton', 'the hub IS the button; there is no other')
    check(ctx.Hub:FindFirstChildOfClass('UICorner').CornerRadius.S == 1,
        'and it is a circle at any diameter')
    check(ctx.Close.Parent == ctx.Shade and ctx.Close.Text == 'X',
        'one X, and it is not on the wheel')

    -- THE WHOLE POINT OF THE REWRITE: no container, no legend, no footer.
    for _, name in ipairs({'LuckyWheelPanel', 'WheelBody', 'WheelLegend', 'ResultBanner',
        'SpinButton', 'SkipButton', 'Eyebrow', 'Title', 'NoteLine', 'StatusLine',
        'DiscHolder', 'WheelRim', 'WheelHub', 'Arm1', 'Spoke1', 'LegendRow1'}) do
        check(descendant(ctx.Gui, name) == nil, 'nothing named ' .. name .. ' is drawn')
    end
    local scrollers, frames = 0, {}
    for _, object in ipairs(ctx.Gui:GetDescendants()) do
        if object.ClassName == 'ScrollingFrame' then scrollers += 1 end
        if object.ClassName == 'Frame' then table.insert(frames, object.Name) end
    end
    check(scrollers == 0, 'nothing scrolls: the wheel is the whole screen')
    table.sort(frames)
    check(table.concat(frames, ',') == 'WheelHolder,WheelPointer,WheelShade',
        'the only frames in the whole gui are the shade, the holder and the pointer')
    local shadeKids = {}
    for _, child in ipairs(ctx.Shade.Children) do table.insert(shadeKids, child.Name) end
    table.sort(shadeKids)
    check(table.concat(shadeKids, ',') == 'CloseButton,WheelHolder',
        'and the shade carries only the wheel and the way out')
end

-- ── five equal fields, with the real odds inside them ────────────────────
do
    local ctx = start(POINTER)
    for _, prize in ipairs(WHEEL) do
        local label = descendant(ctx.Disc, 'FieldLabel' .. tostring(prize.Order))
        local odds = descendant(ctx.Disc, 'FieldOdds' .. tostring(prize.Order))
        check(label ~= nil and label.Parent == ctx.Disc,
            prize.Key .. ': its name rides ON the disc, so it turns with the field')
        check(odds ~= nil and odds.Parent == ctx.Disc, prize.Key .. ': and so do its odds')
        check(label.Text == LONG[prize.Order],
            prize.Key .. ': the field prints "' .. LONG[prize.Order] .. '"')
        check(odds.Text == prize.Odds,
            prize.Key .. ': and its REAL chance, ' .. prize.Odds
            .. ' -- equal art must not be read as equal odds')
        check(label.Rotation == prize.Angle and odds.Rotation == prize.Angle,
            prize.Key .. ': both are turned to ' .. prize.Angle .. ' degrees')
        -- THE NAME MAY NOT OVERFLOW ITS FIELD. Nothing in the LocalScript knows
        -- a font's TextBounds, so the engine shrinks the copy instead -- between
        -- the project's 11px floor and the size applyLayout derives.
        check(label.TextScaled == true,
            prize.Key .. ': the name is TextScaled, so it can never spill its field')
        local limit = label:FindFirstChildOfClass('UITextSizeConstraint')
        check(limit ~= nil, prize.Key .. ': bounded by a UITextSizeConstraint')
        check(limit.MinTextSize == 11,
            prize.Key .. ': whose floor is the project\'s 11px, never smaller')
        check(limit.MaxTextSize >= 11 and limit.MaxTextSize >= limit.MinTextSize,
            prize.Key .. ': and whose ceiling is a real size at or above it')
        check(odds.TextScaled == false and odds.TextSize >= 11,
            prize.Key .. ': the odds are a fixed size, and it is 11px or larger')
        check(label:FindFirstChildOfClass('UIStroke').ApplyStrokeMode
            == Enum.ApplyStrokeMode.Contextual,
            prize.Key .. ': the stroke outlines the GLYPHS, not a pill behind them')
        -- Polar placement: 0.80 R for the name, 0.36 R for the odds, on the
        -- field's own radius. In scale terms that is 0.40 and 0.18 from centre.
        local a = math.rad(prize.Angle)
        local wantX = 0.5 + 0.40 * math.sin(a)
        local wantY = 0.5 - 0.40 * math.cos(a)
        check(math.abs(label.Position.SX - wantX) < 1e-9
            and math.abs(label.Position.SY - wantY) < 1e-9,
            prize.Key .. ': the name sits at 0.80 of the radius on its own bearing')
        check(math.abs(odds.Position.SX - (0.5 + 0.18 * math.sin(a))) < 1e-9
            and math.abs(odds.Position.SY - (0.5 - 0.18 * math.cos(a))) < 1e-9,
            prize.Key .. ': and the odds sit at 0.36, inside the same field')
    end
    check(descendant(ctx.Disc, 'FieldLabel6') == nil, 'there is no sixth field')
    -- The field at 12 o'clock is the one the pointer is over at Rotation 0, and
    -- it is the 45% token: that is the orientation the PNG was checked against.
    check(WHEEL[1].Angle == 0 and WHEEL[1].Key == 'Token1',
        'field 1 is centred at 12 o\'clock, matching the texture')
    check(fieldOf(pointerAngle(0)).Key == 'Token1',
        'so an unturned disc has the pointer over the gold token field')
end
for _, case in ipairs({
    -- Shrinking "2 SPEED POTIONS" towards 11px is not the same as reading it,
    -- so every phone-sized disc prints the short form outright.
    {Name = 'phone portrait', Layout = PHONE_PORTRAIT},
    {Name = 'phone landscape', Layout = PHONE_LANDSCAPE},
    {Name = 'short landscape', Layout = SHORT_LANDSCAPE},
    {Name = 'emulator', Layout = EMULATOR},
}) do
    local ctx = start(case.Layout)
    local side = ctx.Holder.Size.OX
    check(side < 400, case.Name .. ': its disc is under the short-copy threshold')
    local shortOk, maxOk = true, true
    for _, prize in ipairs(WHEEL) do
        local label = descendant(ctx.Disc, 'FieldLabel' .. tostring(prize.Order))
        if label.Text ~= SHORT[prize.Order] then shortOk = false end
        if label:FindFirstChildOfClass('UITextSizeConstraint').MaxTextSize
            ~= math.max(11, math.floor(side * 0.040)) then maxOk = false end
    end
    check(shortOk, case.Name .. ': all five fields print the short prize names')
    check(maxOk, case.Name .. ': and their ceiling is the size derived from the disc')
end
do
    -- A disc with the room for them keeps the full names.
    local ctx = start(POINTER)
    check(ctx.Holder.Size.OX >= 400, 'a desktop disc is over the threshold')
    for _, prize in ipairs(WHEEL) do
        check(descendant(ctx.Disc, 'FieldLabel' .. tostring(prize.Order)).Text
            == LONG[prize.Order],
            prize.Key .. ': and prints "' .. LONG[prize.Order] .. '" in full')
    end
end

-- ── nothing that is not the wheel is written on it ───────────────────────
for _, case in ipairs({
    {Name = 'desktop', Layout = POINTER}, {Name = 'phone', Layout = PHONE_PORTRAIT},
    {Name = 'emulator', Layout = EMULATOR},
}) do
    local ctx = start(case.Layout)
    open(ctx)
    push(ctx, daily({Key = 'Shield1', Serial = 7}))
    local clean, sized, drawn = true, true, 0
    for _, object in ipairs(ctx.Gui:GetDescendants()) do
        local text = object.Text
        if type(text) == 'string' and text ~= '' then
            drawn += 1
            local upper = text:upper()
            if upper:find('SUPPLY') or upper:find('ZYNTRA') then clean = false end
            -- A TextScaled label's own TextSize is ignored by the engine, so
            -- its floor is its UITextSizeConstraint's MinTextSize instead.
            local floorSize
            if object.TextScaled == true then
                local limit = object:FindFirstChildOfClass('UITextSizeConstraint')
                floorSize = limit and limit.MinTextSize or nil
            else
                floorSize = object.TextSize
            end
            if type(floorSize) ~= 'number' or floorSize < 11 then sized = false end
        end
    end
    check(clean, case.Name .. ': no "SUPPLY" and no "ZYNTRA" is drawn anywhere')
    check(sized, case.Name .. ': every drawn string prints at 11px or larger')
    check(drawn >= 12, case.Name .. ': and the wheel, its odds and the hub are drawn')
end

-- ── the disc fits, the targets are big enough ────────────────────────────
for _, case in ipairs({
    {Name = 'desktop 1280x720', Layout = POINTER, Side = 569},
    {Name = 'phone portrait 390x844', Layout = PHONE_PORTRAIT, Side = 335},
    {Name = 'phone landscape 844x390', Layout = PHONE_LANDSCAPE, Side = 285},
    {Name = 'tablet 1024x768', Layout = TABLET, Side = 610},
    {Name = 'short landscape 705x338', Layout = SHORT_LANDSCAPE, Side = 240},
    {Name = 'emulator 749x368', Layout = EMULATOR, Side = 266},
}) do
    local ctx = start(case.Layout)
    open(ctx)
    local layout = case.Layout
    local side = ctx.Holder.Size.OX
    check(side == case.Side, case.Name .. ': the disc is ' .. case.Side .. ' studs of screen')
    check(ctx.Holder.Size.OY == side, case.Name .. ': and it is square')
    check(side <= math.min(layout.SW, layout.SH),
        case.Name .. ': which fits inside the short axis of the SAFE area')
    check(side >= 220 or side == math.min(layout.SW, layout.SH),
        case.Name .. ': and is never smaller than the 220 floor unless the screen is')
    -- Centred on the SAFE rectangle, converted into the gui's own offsets. The
    -- pointer sits on the disc's top edge, so a disc centred on the whole
    -- display would push that pointer under Roblox's topbar in landscape.
    local centreX = ctx.Holder.Position.OX + layout.OriginX
    local centreY = ctx.Holder.Position.OY + layout.OriginY
    check(math.abs(centreX - (layout.Safe.Left + layout.Safe.Right) / 2) <= 1
        and math.abs(centreY - (layout.Safe.Top + layout.Safe.Bottom) / 2) <= 1,
        case.Name .. ': the disc is centred on the safe area, not on a panel')
    check(centreY - side / 2 >= layout.Safe.Top - 0.5,
        case.Name .. ': so the pointer on its top edge clears the topbar band')
    check(centreY + side / 2 <= layout.Safe.Bottom + 0.5,
        case.Name .. ': and the whole disc is inside the safe area vertically')

    check(ctx.Hub.Size.OX >= 56 and ctx.Hub.Size.OY == ctx.Hub.Size.OX,
        case.Name .. ': the hub is a circle of at least 56px')
    check(ctx.Hub.Size.OX == math.max(56, math.floor(side * 0.26)),
        case.Name .. ': sized from the disc, not from a tier table')
    check(ctx.Close.Size.OX >= 48 and ctx.Close.Size.OY >= 48,
        case.Name .. ': the X is at least 48px square')
    -- The X is pinned to the SAFE area: a notch or the topbar must never sit on
    -- top of the only way out.
    local left = ctx.Close.Position.OX + layout.OriginX
    local top = ctx.Close.Position.OY + layout.OriginY
    check(left >= layout.Safe.Left and top >= layout.Safe.Top
        and left + ctx.Close.Size.OX <= layout.Safe.Right
        and top + ctx.Close.Size.OY <= layout.Safe.Bottom,
        case.Name .. ': and it is inside the safe area, top-right')
    check(layout.Safe.Right - (left + ctx.Close.Size.OX) == 8,
        case.Name .. ': with the stated 8px margin')
    check(ctx.Pointer.Size.OX >= 18 and ctx.Pointer.Size.OY == ctx.Pointer.Size.OX,
        case.Name .. ': the pointer is at least 18px')
    check(ctx.Pointer.Position.SX == 0.5 and ctx.Pointer.Position.SY == 0,
        case.Name .. ': and straddles the rim at 12 o\'clock')
    check(ctx.Hub.ZIndex > ctx.Disc.ZIndex and ctx.Pointer.ZIndex > ctx.Disc.ZIndex,
        case.Name .. ': both sit above the art rather than under it')
end
do
    -- Rotating the device re-lays it out rather than leaving it describing the
    -- screen the player used to be holding.
    local ctx = start(PHONE_PORTRAIT)
    open(ctx)
    local portrait = ctx.Holder.Size.OX
    ctx.Layout = SHORT_LANDSCAPE
    ctx.UIDevice.Changed:Fire()
    check(ctx.Holder.Size.OX == 240, 'rotating the phone resizes the disc')
    check(ctx.Hub.Size.OX == math.max(56, math.floor(240 * 0.26)),
        'and the hub with it')
    check(descendant(ctx.Disc, 'FieldLabel1'):FindFirstChildOfClass(
        'UITextSizeConstraint').MaxTextSize == math.max(11, math.floor(240 * 0.040)),
        'and the field copy\'s ceiling follows the new diameter')
    ctx.Layout = PHONE_PORTRAIT
    ctx.UIDevice.Changed:Fire()
    check(ctx.Holder.Size.OX == portrait, 'and back again')
end

-- ── the server's result decides where it lands ───────────────────────────
do
    -- Every prize, at twenty different Serials, on one disc that keeps turning.
    local ctx = start(POINTER)
    open(ctx)
    push(ctx, daily({}))
    local seen = 0
    for _, prize in ipairs(WHEEL) do
        for serial = 1, 20 do
            local before = #ctx.Tweens
            local rotationBefore = ctx.Disc.Rotation
            push(ctx, daily({Key = prize.Key, Serial = serial}))
            local tween = ctx.Tweens[#ctx.Tweens]
            local landed = fieldOf(pointerAngle(tween.Goal.Rotation))
            local ok = #ctx.Tweens == before + 1
                and tween.Played
                and tween.Instance == ctx.Disc
                and tween.Goal.Rotation > rotationBefore
                and landed ~= nil and landed.Key == prize.Key
            check(ok, prize.Key .. ' at Serial ' .. serial
                .. ': one forward tween landing the pointer in its own field')
            seen += 1
            ctx.Hub.Activated:Fire()
        end
    end
    check(seen == 100, 'a hundred recorded results were replayed')
    check(#ctx.Tweens == 100, 'each of them asked for exactly one tween')
end
do
    -- The landing keeps 6 degrees clear of both edges, so a result never looks
    -- like a near miss of the field next to it.
    local ctx = start(POINTER)
    open(ctx)
    push(ctx, daily({}))
    local clear, low, high = true, 90, 0
    for _, prize in ipairs(WHEEL) do
        for serial = 1, 40 do
            push(ctx, daily({Key = prize.Key, Serial = serial}))
            local depth = into(pointerAngle(ctx.Tweens[#ctx.Tweens].Goal.Rotation), prize.Order)
            if depth < 6 or depth > 66 then clear = false end
            low, high = math.min(low, depth), math.max(high, depth)
            ctx.Hub.Activated:Fire()
        end
    end
    check(clear, 'all 200 landings sit in [6, 66] degrees of their own 72-degree field')
    check(low < 20 and high > 50, 'and they use the width of it rather than one spot')
end
do
    -- ReduceFlashing turns ONCE, and one turn is exactly where the old
    -- `current - current % 360 + target` goal could travel backwards.
    for _, reduced in ipairs({false, true}) do
        local ctx = start(POINTER)
        if reduced then ctx.Player:SetAttribute('ReduceFlashing', true) end
        open(ctx)
        push(ctx, daily({}))
        local forward, minTravel, maxTravel = true, math.huge, 0
        for _, prize in ipairs(WHEEL) do
            for serial = 1, 20 do
                local before = ctx.Disc.Rotation
                push(ctx, daily({Key = prize.Key, Serial = serial}))
                local travel = ctx.Tweens[#ctx.Tweens].Goal.Rotation - before
                if travel <= 0 then forward = false end
                minTravel, maxTravel = math.min(minTravel, travel), math.max(maxTravel, travel)
                ctx.Hub.Activated:Fire()
            end
        end
        local label = reduced and 'reduced flashing' or 'the full spin'
        check(forward, label .. ': every one of the 100 landings travels FORWARD')
        check(minTravel >= 360, label .. ': and always at least one whole turn')
        if reduced then
            check(maxTravel <= 720, 'reduced flashing turns about once, never five times')
            check(ctx.Tweens[1].Info.Time == 1.4, 'over 1.4 seconds')
            check(ctx.Tweens[1].Info.Style == Enum.EasingStyle.Sine, 'on a Sine curve')
        else
            check(minTravel > 1800, 'the full spin turns at least five times')
            check(ctx.Tweens[1].Info.Time == 4.2, 'over 4.2 seconds')
            check(ctx.Tweens[1].Info.Style == Enum.EasingStyle.Quint, 'on a Quint curve')
            check(ctx.Tweens[1].Info.Direction == Enum.EasingDirection.Out,
                'decelerating into the result')
        end
    end
end
do
    -- The same Serial is the same degree, on every client and every replay.
    local a = start(POINTER)
    open(a)
    push(a, daily({}))
    push(a, daily({Key = 'Potion1', Serial = 12}))
    local first = pointerAngle(a.Tweens[1].Goal.Rotation)
    local b = start(POINTER)
    open(b)
    push(b, daily({}))
    push(b, daily({Key = 'Potion1', Serial = 12}))
    check(math.abs(first - pointerAngle(b.Tweens[1].Goal.Rotation)) < 1e-9,
        'the jitter is derived from the Serial, so two clients land identically')
    -- And a REJOIN parks on that same degree without animating.
    local c = start(POINTER)
    open(c)
    push(c, daily({Key = 'Potion1', Serial = 12}))
    check(#c.Tweens == 0, 'a rejoin never animates a result from earlier today')
    check(math.abs(pointerAngle(c.Disc.Rotation) - first) < 1e-9,
        'and parks the pointer on exactly the degree the spin would have reached')
end

-- ── the hub is the only control ──────────────────────────────────────────
do
    local ctx = start(POINTER)
    open(ctx)
    push(ctx, daily({}))
    check(ctx.Hub.Text == 'SPIN', 'an unspent day offers the spin, in the hub')
    check(ctx.Hub.Active == true, 'and the hub takes input')
    ctx.Hub.Activated:Fire()
    check(#ctx.Sent == 1, 'the hub asks the server exactly once')
    check(ctx.Sent[1].Action == 'SpinDailyWheel', 'and it asks for SpinDailyWheel')
    check(ctx.Sent[1].Payload == nil, 'with no payload for the server to trust')
    check(ctx.Hub.Text == 'SPINNING', 'the hub says so')
    check(ctx.Hub.Active == false, 'and stops taking input while the request is in flight')
    ctx.Hub.Activated:Fire()
    ctx.Hub.Activated:Fire()
    check(#ctx.Sent == 1, 'a double press cannot become a second request')
    check(#ctx.Tweens == 0, 'and nothing spins before the server has answered')
end
do
    -- 6 s of silence: RETRY, and a RE-READ. Never a local grant.
    local ctx = start(POINTER)
    open(ctx)
    push(ctx, daily({}))
    local invokes = ctx.Invokes
    ctx.Hub.Activated:Fire()
    ctx:Advance(5.5)
    check(ctx.Hub.Text == 'SPINNING', 'five and a half seconds is not yet a failure')
    ctx:Advance(1)
    check(ctx.Hub.Text == 'RETRY', 'six seconds of silence turns the hub into RETRY')
    check(ctx.Hub.Active == true, 'which the player may press')
    check(ctx.Invokes == invokes + 1, 'the recovery is a RE-READ of the profile')
    check(#ctx.Tweens == 0, 'and the client still never picked a prize')
    ctx.Hub.Activated:Fire()
    check(#ctx.Sent == 2, 'RETRY asks again')
    check(ctx.Hub.Text == 'SPINNING', 'and goes back to waiting')
end
do
    -- An answer that arrives makes the armed timeout stale.
    local ctx = start(POINTER)
    open(ctx)
    push(ctx, daily({}))
    ctx.Hub.Activated:Fire()
    push(ctx, daily({Key = 'Token1', Serial = 1}))
    ctx.Hub.Activated:Fire()
    ctx:Advance(8)
    check(ctx.Hub.Text ~= 'RETRY', 'an answered request never reports a timeout later')
    check(#ctx.Tweens == 1, 'and never starts a second spin')
end
do
    -- A TAP ON THE HUB WHILE IT TURNS IS THE SKIP. There is no SKIP button.
    local ctx = start(POINTER)
    open(ctx)
    push(ctx, daily({}))
    push(ctx, daily({Key = 'Shield1', Serial = 3}))
    local tween = ctx.Tweens[1]
    check(ctx.Hub.Active == true,
        'the hub keeps taking input while the disc turns -- that IS the skip')
    check(ctx.Hub.Text == 'SPINNING', 'while saying what is happening')
    ctx.Hub.Activated:Fire()
    check(ctx.Disc.Rotation == tween.Goal.Rotation, 'a tap jumps straight to the result')
    check(tween.Cancelled == true, 'and stops the tween rather than leaving it running')
    check(#ctx.Tweens == 1, 'a skip never starts a second spin')
    check(ctx.Hub.Text == '1\nSHIELD',
        'and the hub carries the prize the SERVER recorded')
    check(ctx.Hub.Active == false, 'with no way to spin again today')
    check(fieldOf(pointerAngle(ctx.Disc.Rotation)).Key == 'Shield1',
        'the pointer is sitting in the field the server picked')
    -- Tapping again during the prize window must not re-ask or re-finish.
    ctx.Hub.Activated:Fire()
    check(#ctx.Sent == 0 and #ctx.Tweens == 1,
        'and a second tap on the landed hub does nothing at all')
    ctx:Advance(3.5)
    check(ctx.Hub.Text:sub(1, 4) == 'SPUN',
        'after 3.5 seconds the prize gives way to the countdown')
end
do
    -- THE PRIZE WINDOW IS KEYED ON ITS OWN SERIAL. Two landings in one session
    -- arm two 3.5 s timers, and the older one must not close the newer one's
    -- window early -- which is what an unkeyed boolean would do.
    local ctx = start(POINTER)
    open(ctx)
    push(ctx, daily({}))
    push(ctx, daily({Key = 'Token1', Serial = 1}))
    ctx.Hub.Activated:Fire()
    check(ctx.Hub.Text == '1\nTOKEN', 'the first landing shows its prize')
    ctx:Advance(2)
    push(ctx, daily({Key = 'Token3', Serial = 2}))
    ctx.Hub.Activated:Fire()
    check(ctx.Hub.Text == '3\nTOKENS', 'the second landing replaces it')
    ctx:Advance(1.6)
    check(ctx.Hub.Text == '3\nTOKENS',
        'and the FIRST landing\'s timer, now due, does not cut it short')
    ctx:Advance(2)
    check(ctx.Hub.Text:sub(1, 4) == 'SPUN', 'its own timer still does')
end
do
    -- The hub's copy is sized off the diameter, and the long states take the
    -- smaller face: eight characters at 0.30 of the circle do not fit in it.
    local ctx = start(POINTER)
    open(ctx)
    push(ctx, daily({}))
    local diameter = ctx.Hub.Size.OX
    check(ctx.Hub.TextScaled == false, 'the hub is not TextScaled')
    check(ctx.Hub.Text == 'SPIN'
        and ctx.Hub.TextSize == math.max(12, math.floor(diameter * 0.30)),
        'SPIN takes the big face')
    ctx.Hub.Activated:Fire()
    check(ctx.Hub.Text == 'SPINNING'
        and ctx.Hub.TextSize == math.max(11, math.floor(diameter * 0.19)),
        'SPINNING takes the small one, because it would not fit the big one')
    check(ctx.Hub.TextSize >= 11, 'and is still legible')
    ctx:Advance(6)
    check(ctx.Hub.Text == 'RETRY'
        and ctx.Hub.TextSize == math.max(12, math.floor(diameter * 0.30)),
        'RETRY is short enough for the big face again')
end
do
    -- Nothing else rides on the disc: ten labels, and no controls.
    local ctx = start(POINTER)
    local labels, others = 0, 0
    for _, child in ipairs(ctx.Disc.Children) do
        if child.ClassName == 'TextLabel' then labels += 1 else others += 1 end
    end
    check(labels == 10, 'the disc carries exactly five names and five odds')
    check(others == 0, 'and nothing else -- no button ever turns with it')
end
do
    -- Letting it run to the end is the same landing, and finishes once.
    local ctx = start(POINTER)
    open(ctx)
    push(ctx, daily({}))
    push(ctx, daily({Key = 'Potion2', Serial = 9}))
    ctx.Tweens[1]:Finish()
    check(ctx.Hub.Text == '2\nPOTIONS', 'a tween that completes announces the prize')
    check(fieldOf(pointerAngle(ctx.Disc.Rotation)).Key == 'Potion2',
        'and leaves the pointer in the 5% field it actually won')
    ctx.Hub.Activated:Fire()
    check(#ctx.Tweens == 1, 'and a tap afterwards cannot finish it a second time')
end
do
    -- Closing mid-spin ends the replay: the prize was banked before it started.
    local ctx = start(POINTER)
    open(ctx)
    push(ctx, daily({}))
    push(ctx, daily({Key = 'Token1', Serial = 2}))
    ctx.Close.Activated:Fire()
    check(ctx.Disc.Rotation == ctx.Tweens[1].Goal.Rotation,
        'closing finishes the replay rather than freezing it mid-turn')
    open(ctx)
    check(#ctx.Tweens == 1, 'and reopening does not replay it')
    check(fieldOf(pointerAngle(ctx.Disc.Rotation)).Key == 'Token1',
        'the disc is still parked on the prize')
end

-- ── COLLECT PRIZE: the server records, the claim pays, the hub confirms ──
do
    local ctx = start(POINTER)
    open(ctx)
    push(ctx, daily({}))
    ctx.Hub.Activated:Fire()
    check(ctx.Sent[1].Action == 'SpinDailyWheel', 'the spin is asked for')
    push(ctx, daily({Key = 'Token1', Serial = 1, Claimed = false}))
    check(#ctx.Tweens == 1, 'the recorded result lands')
    ctx.Hub.Activated:Fire() -- skip
    check(ctx.Hub.Text == 'COLLECT\nPRIZE', 'an owed prize makes the hub COLLECT PRIZE straight after landing')
    check(ctx.Hub.Active == true, 'and it takes input')
    check(fieldOf(pointerAngle(ctx.Disc.Rotation)).Key == 'Token1', 'with the pointer on the prize')
    ctx.Hub.Activated:Fire()
    check(#ctx.Sent == 2 and ctx.Sent[2].Action == 'ClaimWheelPrize', 'COLLECT asks the server for ClaimWheelPrize')
    check(ctx.Sent[2].Payload == nil, 'with no payload for the server to trust')
    check(ctx.Hub.Text == 'COLLECTING' and ctx.Hub.Active == false, 'and waits, taking no input')
    ctx.Hub.Activated:Fire()
    ctx.Hub.Activated:Fire()
    check(#ctx.Sent == 2, 'a double press cannot become a second claim')
    -- The server's word: Claimed == true for the serial that was asked for.
    push(ctx, daily({Key = 'Token1', Serial = 1, Claimed = true}))
    check(ctx.Hub.Text == '1 TOKEN\nCOLLECTED', 'the confirmation appears only once the pushed profile says Claimed')
    check(ctx.Hub.Active == false, 'and is not a button')
    ctx:Advance(3.6)
    check(ctx.Hub.Text:sub(1, 4) == 'SPUN', 'then the hub becomes the countdown for the spent day')
    ctx.Hub.Activated:Fire()
    check(#ctx.Sent == 2, 'nothing more is asked for')
end
do
    -- A push that does NOT confirm (write failed, Claimed still false) is not
    -- success: the hub goes back to COLLECT PRIZE and no confirmation is shown.
    local ctx = start(POINTER)
    open(ctx)
    push(ctx, daily({Key = 'Potion2', Serial = 4, Claimed = false}))
    check(#ctx.Tweens == 0, 'the first profile is a seed: parked, not replayed')
    check(ctx.Hub.Text == 'COLLECT\nPRIZE', 'owed')
    ctx.Hub.Activated:Fire()
    check(ctx.Sent[1].Action == 'ClaimWheelPrize', 'asked')
    push(ctx, daily({Key = 'Potion2', Serial = 4, Claimed = false}))
    check(ctx.Hub.Text == 'COLLECT\nPRIZE', 'a refused or failed claim leaves the prize owed and the button back')
    check(ctx.Hub.Active == true, 'ready to try again')
    ctx.Hub.Activated:Fire()
    check(#ctx.Sent == 2, 'the retry asks again')
    push(ctx, daily({Key = 'Potion2', Serial = 4, Claimed = true}))
    check(ctx.Hub.Text == '2 POTIONS\nCOLLECTED', 'and the confirmation names the real item and count')
end
do
    -- Silence for 6 s: RETRY, a RE-READ, and RETRY re-asks for the CLAIM (the
    -- prize is still owed), never for a spin.
    local ctx = start(POINTER)
    open(ctx)
    push(ctx, daily({Key = 'Shield1', Serial = 2, Claimed = false}))
    check(ctx.Hub.Text == 'COLLECT\nPRIZE', 'owed on arrival')
    local invokes = ctx.Invokes
    ctx.Hub.Activated:Fire() -- collect
    ctx:Advance(5.5)
    check(ctx.Hub.Text == 'COLLECTING', 'five and a half seconds is not yet a failure')
    ctx:Advance(1)
    check(ctx.Hub.Text == 'COLLECT\nPRIZE' and ctx.Hub.Active == true,
        'six seconds of silence hands the button back (the prize is still owed, so it says COLLECT, not RETRY)')
    check(ctx.Invokes == invokes + 1, 'the recovery is a RE-READ of the profile')
    ctx.Hub.Activated:Fire()
    check(#ctx.Sent == 2 and ctx.Sent[2].Action == 'ClaimWheelPrize', 'and pressing it re-asks for the claim, not a spin')
end
do
    -- A REJOIN with an uncollected prize from YESTERDAY: parked, not replayed,
    -- and the hub is COLLECT PRIZE -- the day change did not lose it, and the
    -- free spin waits behind it (the server refuses a spin until it is in).
    local ctx = start(POINTER)
    open(ctx)
    push(ctx, daily({Key = 'Token3', Serial = 7, Claimed = false, Day = '2026-09-15'}))
    check(#ctx.Tweens == 0, 'the first profile of the session is a seed, never a replay')
    check(fieldOf(pointerAngle(ctx.Disc.Rotation)).Key == 'Token3', 'the disc is parked on the owed prize')
    check(ctx.Hub.Text == 'COLLECT\nPRIZE' and ctx.Hub.Active == true, 'and the hub offers to collect it')
    ctx.Hub.Activated:Fire()
    check(ctx.Sent[1].Action == 'ClaimWheelPrize', 'collecting, not spinning')
    push(ctx, daily({Key = 'Token3', Serial = 7, Claimed = true, Day = '2026-09-15'}))
    check(ctx.Hub.Text == '3 TOKENS\nCOLLECTED', 'confirmed')
    ctx:Advance(3.6)
    check(ctx.Hub.Text == 'SPIN' and ctx.Hub.Active == true, "yesterday's result collected, today's free spin is offered")
end
do
    -- A historical result (no Claimed field) is an already-paid one: the hub
    -- shows the prize and the countdown exactly as before, never COLLECT.
    local ctx = start(POINTER)
    open(ctx)
    push(ctx, daily({}))
    push(ctx, daily({Key = 'Token1', Serial = 1}))
    ctx.Hub.Activated:Fire()
    check(ctx.Hub.Text == '1\nTOKEN', 'an old result shows the prize')
    ctx:Advance(3.6)
    check(ctx.Hub.Text:sub(1, 4) == 'SPUN', 'and then the countdown, with nothing to collect')
end

-- ── a replay is not a spin ───────────────────────────────────────────────
do
    -- THE FIRST PROFILE IS A SEED. A player who spun this morning and rejoined
    -- at lunch is shown the countdown, not made to watch it land again.
    local ctx = start(POINTER)
    open(ctx)
    push(ctx, daily({Key = 'Potion1', Serial = 6, Reset = 3600}))
    check(#ctx.Tweens == 0, 'a rejoin animates nothing')
    check(ctx.Hub.Text == 'SPUN\n01:00:00', 'the hub shows the day as spent')
    check(ctx.Hub.Active == false, 'and refuses another spin')
    ctx.Hub.Activated:Fire()
    check(#ctx.Sent == 0, 'a press on a spent hub sends nothing')
end
do
    local ctx = start(POINTER)
    open(ctx)
    push(ctx, daily({}))
    push(ctx, daily({Key = 'Token1', Serial = 5}))
    ctx.Hub.Activated:Fire()
    local rotation = ctx.Disc.Rotation
    push(ctx, daily({Key = 'Token1', Serial = 5}))
    check(#ctx.Tweens == 1, 'a push carrying the SAME Serial animates nothing')
    check(ctx.Disc.Rotation == rotation, 'and does not move the disc')
    push(ctx, daily({Key = 'Token1', Serial = 5}))
    push(ctx, daily({Key = 'Token1', Serial = 5}))
    check(#ctx.Tweens == 1, 'however many times the server repeats itself')
    check(ctx.Disc.Rotation == rotation, 'and the disc stays exactly where it landed')
end
do
    -- A result recorded on a PREVIOUS day is not today's result.
    local ctx = start(POINTER)
    open(ctx)
    local profile = daily({Key = 'Token1', Serial = 1})
    profile.Daily.WheelLast.Day = '2026-09-15'
    profile.Daily.WheelDay = '2026-09-15'
    push(ctx, profile)
    check(#ctx.Tweens == 0, 'yesterday\'s prize does not animate')
    check(ctx.Hub.Text == 'SPIN', 'today\'s spin is still free')
    check(ctx.Hub.Active == true, 'and the hub takes input')
end

-- ── the countdown ────────────────────────────────────────────────────────
do
    local ctx = start(POINTER)
    open(ctx)
    push(ctx, daily({Key = 'Token1', Serial = 1, Reset = 3661}))
    check(ctx.Hub.Text == 'SPUN\n01:01:01',
        'the hub is SPUN over an HH:MM:SS countdown to the UTC reset')
    tick(ctx, 61)
    check(ctx.Hub.Text == 'SPUN\n01:00:00', 'and it ticks in real time')
    check(#ctx.Hub.Text:split('\n') == 2, 'on two lines, because a circle is not a row')
end
do
    -- Ticking behind a closed wheel is 60 wasted string builds a second.
    local ctx = start(POINTER)
    open(ctx)
    push(ctx, daily({Key = 'Token1', Serial = 1, Reset = 3600}))
    local text = ctx.Hub.Text
    ctx.Close.Activated:Fire()
    tick(ctx, 120)
    check(ctx.Hub.Text == text, 'a closed wheel does not redraw its countdown')
    open(ctx)
    check(ctx.Hub.Text ~= text, 'and reopening catches it back up')
end
do
    -- Midnight: the server owns the new counters, so the client asks for them.
    local ctx = start(POINTER)
    open(ctx)
    push(ctx, daily({Key = 'Token1', Serial = 1, Reset = 2}))
    local invokes = ctx.Invokes
    tick(ctx, 4)
    check(ctx.Invokes == invokes + 1, 'the UTC roll triggers exactly one re-read')
    check(ctx.Hub.Text == 'SPUN\n00:00:00', 'and the countdown floors at zero')
    tick(ctx, 10)
    check(ctx.Invokes == invokes + 1, 'and not one per second afterwards')
end

-- ── the takeover ─────────────────────────────────────────────────────────
do
    local ctx = start(POINTER)
    local rail = addGui(ctx, 'ZyntraRailGui')
    local hud = addGui(ctx, 'ProtectionHUD')
    local off = addGui(ctx, 'AlreadyOffGui', false)
    local notGui = newInstance('Folder', 'SomeFolder')
    notGui.Parent = ctx.PlayerGui
    open(ctx)
    check(rail.Enabled == false and hud.Enabled == false,
        'opening the wheel disables every other ScreenGui in PlayerGui')
    check(ctx.Gui.Enabled == true, 'and leaves its own alone')
    check(off.Enabled == false, 'a gui that was already off stays off')
    ctx.Close.Activated:Fire()
    check(rail.Enabled == true and hud.Enabled == true,
        'closing restores exactly the ones it turned off')
    check(off.Enabled == false,
        'and does NOT switch on something the game had deliberately disabled')
end
do
    -- A gui that re-enables ITSELF while the wheel is up (NoiseReporter's
    -- StaminaGui does, on every layout pass, and it holds the touch RUN button)
    -- is switched off again for as long as the wheel is open, and because it
    -- asked to be on it comes back on close.
    local ctx = start(POINTER)
    local rail = addGui(ctx, 'ZyntraRailGui')
    local stubborn = addGui(ctx, 'StaminaGui')
    local quiet = addGui(ctx, 'QuietGui', false)
    open(ctx)
    stubborn.Enabled = true
    check(stubborn.Enabled == false, 'a gui that re-enabled itself while open is hidden again')
    quiet.Enabled = true
    check(quiet.Enabled == false, 'even one that was off when the wheel opened')
    ctx.Close.Activated:Fire()
    check(stubborn.Enabled == true, 'and it comes back on close because it asked to be on')
    check(quiet.Enabled == true, 'so does the one that switched itself on meanwhile')
    check(rail.Enabled == true, 'and the rest are still restored')
    stubborn.Enabled = false
    stubborn.Enabled = true
    check(stubborn.Enabled == true, 'after close the wheel no longer interferes with anyone')
end
do
    -- A ResetOnSpawn clone parents itself in while the wheel is open.
    local ctx = start(POINTER)
    open(ctx)
    local late = addGui(ctx, 'LateGui')
    check(late.Enabled == false, 'a gui added while open is disabled too')
    local gone = addGui(ctx, 'DoomedGui')
    gone:Destroy()
    ctx.Close.Activated:Fire()
    check(late.Enabled == true, 'and restored on close')
    check(gone.Enabled == false, 'a gui destroyed while hidden is not resurrected')
end
do
    -- Respawning: the takeover ends before PlayerGui is rebuilt under it.
    local ctx = start(POINTER)
    local rail = addGui(ctx, 'ZyntraRailGui')
    open(ctx)
    check(rail.Enabled == false, 'it was hidden')
    ctx.Player.CharacterAdded:Fire()
    check(ctx.Shade.Visible == false, 'a respawn closes the wheel')
    check(rail.Enabled == true, 'and hands the HUD back')
    check(ctx.Player:GetAttribute('LuckyWheelOpen') == nil, 'and clears the modal flag')
end
do
    -- Closing twice, and opening twice, must not double-record anything.
    local ctx = start(POINTER)
    local rail = addGui(ctx, 'ZyntraRailGui')
    open(ctx)
    open(ctx)
    check(rail.Enabled == false, 'a second open on an open wheel changes nothing')
    ctx.Close.Activated:Fire()
    ctx.Close.Activated:Fire()
    check(rail.Enabled == true, 'and a second close does not re-hide it')
    open(ctx)
    check(rail.Enabled == false, 'reopening takes the screen again')
    ctx.Close.Activated:Fire()
    check(rail.Enabled == true, 'and gives it back')
end

-- ── opening, refusing, and every way out ─────────────────────────────────
do
    local ctx = start(POINTER)
    check(#ctx.Suppress == 0, 'building the UI suppresses nothing')
    open(ctx)
    check(ctx.Shade.Visible == true, 'the rail button opens the wheel')
    check(ctx.Player:GetAttribute('LuckyWheelOpen') == true,
        'and publishes the modal attribute')
    check(ctx.Suppress[#ctx.Suppress] == true,
        'and stands the touch movement cluster down')
    check(ctx.Close.Active == true, 'the way out is interactive the moment it is drawn')
    local invokes = ctx.Invokes
    open(ctx)
    check(ctx.Invokes == invokes, 'a second open on an open wheel does nothing at all')
end
do
    local ctx = start(POINTER, {Prompt = false})
    check(ctx.OpenEvent ~= nil and ctx.OpenEvent.ClassName == 'BindableEvent',
        'OpenLuckyWheel is created when the rail has not made it yet')
    open(ctx)
    check(ctx.Shade.Visible == true, 'and it opens the wheel')
end
for _, case in ipairs({
    {Name = 'in a round', Attribute = 'InRound'},
    {Name = 'with the terminal open', Attribute = 'ZyntraStoreOpen'},
    {Name = 'with the re-entry modal open', Attribute = 'ZyntraReentryOpen'},
    {Name = 'with the daily rewards modal open', Attribute = 'DailyRewardsOpen'},
    {Name = 'in the queue modal', Attribute = 'QueueModalOpen'},
}) do
    local ctx = start(POINTER)
    local rail = addGui(ctx, 'ZyntraRailGui')
    ctx.Player:SetAttribute(case.Attribute, true)
    open(ctx)
    check(ctx.Shade.Visible == false, case.Name .. ': the wheel refuses to open')
    check(ctx.Player:GetAttribute('LuckyWheelOpen') == nil,
        case.Name .. ': and publishes nothing')
    check(rail.Enabled == true, case.Name .. ': and takes nobody\'s screen away')
end
for _, case in ipairs({
    {Name = 'the X', Apply = function(ctx) ctx.Close.Activated:Fire() end},
    {Name = 'Escape', Apply = function(ctx)
        ctx.UIS.InputBegan:Fire({KeyCode = Enum.KeyCode.Escape}, false)
    end},
    {Name = 'ButtonB', Apply = function(ctx)
        ctx.Bound.LuckyWheelClose(nil, Enum.UserInputState.Begin)
    end},
    {Name = 'entering a round', Apply = function(ctx)
        ctx.Player:SetAttribute('InRound', true)
    end},
    {Name = 'a round going live', Apply = function(ctx)
        ctx.Workspace:SetAttribute('RoundActive', true)
    end},
    -- The queue modal is itself screen-owning, so the cluster stays down for
    -- IT after this one closes. Suppression is derived from the whole published
    -- set, never from the last caller.
    {Name = 'the queue modal opening', Still = true, Apply = function(ctx)
        ctx.Player:SetAttribute('QueueModalOpen', true)
    end},
}) do
    local ctx = start(POINTER)
    local rail = addGui(ctx, 'ZyntraRailGui')
    open(ctx)
    check(ctx.Shade.Visible == true, case.Name .. ': it was open first')
    case.Apply(ctx)
    check(ctx.Shade.Visible == false, case.Name .. ' closes the wheel')
    check(ctx.Player:GetAttribute('LuckyWheelOpen') == nil,
        case.Name .. ': and clears the modal attribute')
    check(rail.Enabled == true, case.Name .. ': and gives the rest of the UI back')
    check(ctx.Suppress[#ctx.Suppress] == (case.Still == true),
        case.Name .. ': and the movement cluster is left as the OTHER modals need it')
end
do
    -- Escape while the wheel is closed must not reach anything.
    local ctx = start(POINTER)
    ctx.UIS.InputBegan:Fire({KeyCode = Enum.KeyCode.Escape}, false)
    check(#ctx.Suppress == 0, 'Escape does nothing while the wheel is shut')
    check(ctx.Bound.LuckyWheelClose == nil, 'and no gamepad action is left bound')
end

-- ── gamepad, and the Studio-only probe ───────────────────────────────────
do
    local ctx = start(POINTER, {LastInput = 'Gamepad'})
    open(ctx)
    check(ctx.GuiService.SelectedObject == ctx.Hub,
        'a gamepad lands on the hub, which is the only thing to press')
    ctx.Close.Activated:Fire()
    check(ctx.GuiService.SelectedObject == nil, 'and closing hands selection back')
end
do
    local ctx = start(POINTER, {LastInput = 'Gamepad'})
    open(ctx)
    push(ctx, daily({Key = 'Token1', Serial = 1}))
    check(ctx.Hub.Active == false, 'with the day spent the hub is not selectable')
    check(ctx.GuiService.SelectedObject ~= nil, 'but a pad still has the X to reach')
end
do
    local ctx = start(POINTER)
    open(ctx)
    check(ctx.GuiService.SelectedObject == nil,
        'a keyboard is never given a forced selection')
end
do
    local ctx = start(POINTER, {Studio = true})
    local probe = descendant(ctx.Gui, 'UIRegressionLuckyWheelProbe')
    check(probe ~= nil, 'Studio gets the regression probe')
    check(probe.ClassName == 'BindableFunction', 'as a BindableFunction')
    check(probe.OnInvoke('state') == false, 'which reports the wheel shut')
    check(probe.OnInvoke('open') == true, 'opens it')
    check(probe.OnInvoke('state') == true, 'and says so')
    check(probe.OnInvoke('close') == false, 'and closes it again')
end
do
    local ctx = start(POINTER, {Studio = false})
    check(descendant(ctx.Gui, 'UIRegressionLuckyWheelProbe') == nil,
        'a live server ships no probe')
end

-- ── the pointer and the hub never turn ───────────────────────────────────
do
    local ctx = start(POINTER)
    open(ctx)
    push(ctx, daily({}))
    local pointerRotation, hubRotation = ctx.Pointer.Rotation, ctx.Hub.Rotation
    local closeRotation = ctx.Close.Rotation
    for _, prize in ipairs(WHEEL) do
        push(ctx, daily({Key = prize.Key, Serial = prize.Order * 7}))
        check(ctx.Pointer.Rotation == pointerRotation,
            prize.Key .. ': the pointer does not move while the disc turns')
        check(ctx.Hub.Rotation == hubRotation, prize.Key .. ': nor does the hub')
        check(ctx.Close.Rotation == closeRotation, prize.Key .. ': nor the X')
        ctx.Hub.Activated:Fire()
        check(ctx.Pointer.Rotation == pointerRotation,
            prize.Key .. ': and none of them move when it lands either')
    end
    check(ctx.Disc.Rotation ~= 0, 'while the disc itself has turned a long way')
end

print('Lucky Wheel client: ' .. checks
    .. ' checks passed (entire actual LocalScript + real UIStyle and ZyntraConfig,'
    .. ' offline Luau; asset loading, fonts, TextBounds and tween feel not exercised)')
'''


def main():
    binary = os.environ.get("LUAU_BIN") or shutil.which("luau")
    if not binary:
        raise SystemExit("Set LUAU_BIN or install luau; no tests were executed.")
    source = "".join([
        HARNESS,
        UISTYLE.read_text(encoding="utf-8"),
        BRIDGE_CONFIG,
        CONFIG.read_text(encoding="utf-8"),
        BRIDGE,
        SOURCE.read_text(encoding="utf-8"),
        TESTS,
    ])
    with tempfile.TemporaryDirectory(prefix="lucky-wheel-") as directory:
        path = Path(directory) / "lucky_wheel_client.luau"
        path.write_text(source, encoding="utf-8")
        subprocess.run([binary, str(path)], check=True, timeout=180)


if __name__ == "__main__":
    main()
