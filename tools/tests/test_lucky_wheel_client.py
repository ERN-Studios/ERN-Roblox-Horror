"""Run the whole Lucky Wheel Client under offline Luau and spin it for real.

LUCKY_WHEEL_20260916 (Trello card 103). The LocalScript is not copied,
excerpted or string-matched: the entire file executes against a fake DataModel,
and every assertion below is made by DRIVING it -- firing the open bindable,
pressing SPIN, pushing a profile with a new WheelLast.Serial, stepping
Heartbeat, rotating the device -- and then reading what the script did to its
own instances, to the ZyntraAction remote and to the tween it asked for.

The REAL ReplicatedStorage/UIStyle and ReplicatedStorage/ZyntraConfig modules
are loaded under the same fake, so the wedges, the legend and the odds strings
are built from the SERVER'S OWN weights rather than from numbers this test made
up. UIDevice is faked, but only where its published contract is: Layout()
answers a stated ModalViewport, ScreenOwningModalOpen() reads the modal
attribute list (including the two the follow-up adds), SetEnabled/SetInteractive
write Active/Visible, SuppressTouchMovement records the caller's intent.
TweenService is faked so the test can read the goal the script asked for and
finish or cancel the tween on demand.

What this CANNOT see, and what the Studio QA pass in the report is for: whether
180 rotated frames actually render as a disc, font metrics and TextBounds,
whether the diamond pointer reads as a pointer, the real 4.2 s Quint feel, and
whether the wedge colours are distinguishable to a human eye on a real screen.
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
-- R/G/B in 0..1 because the script reads them to build its darker wedge step;
-- it never does ARITHMETIC on a Color3, and this fake offers no operators, so
-- an edit that tried to would fail here rather than at runtime.
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

local function memo(kind)
    local cache = {}
    return function(...)
        local key = kind .. ':' .. table.concat({...}, ',')
        if not cache[key] then cache[key] = {Kind = kind, Key = key} end
        return cache[key]
    end
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
    Changed = true, DescendantAdded = true, Completed = true,
}
local methods = {}
local function newInstance(class, name)
    local fields = {
        ClassName = class, Name = name or class, Children = {}, Attributes = {},
        Watchers = {}, Visible = true, Active = false, Selectable = false,
        Modal = false, Text = '', TextScaled = false, Rotation = 0, Parent = nil,
        ZIndex = 1,
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
            -- Reparenting REMOVES from the old parent, the way the engine does.
            -- Without it a control that moves between the panel and the body on
            -- a layout change would be found in both, and an assertion about
            -- where it lives could pass against a stale copy.
            if key == 'Parent' then
                local old = fields.Parent
                if old then
                    for index, child in ipairs(old.Children) do
                        if child == proxy then table.remove(old.Children, index) break end
                    end
                end
                if value ~= nil then table.insert(value.Children, proxy) end
            end
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
            or self.ClassName == 'TextButton' or self.ClassName == 'ScrollingFrame'
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
-- Each row IS the ModalViewport the script is measured against, so the fixture
-- states the number rather than re-deriving UIDevice's gutters.
local function viewport(width, height, touch, left, top)
    left, top = left or 0, top or 0
    return {
        IsTouch = touch, OriginX = 0, OriginY = 0,
        ModalViewport = {Left = left, Top = top, Right = left + width,
            Bottom = top + height, Width = width, Height = height, Fits = true},
    }
end
local POINTER = viewport(1280, 720, false)
local PHONE_PORTRAIT = viewport(390, 844, true)
local PHONE_LANDSCAPE = viewport(844, 390, true)
local TABLET = viewport(1024, 768, true)
local PHONE_SHORT = viewport(705, 338, true)
local OFFSET_POINTER = viewport(1280, 720, false, 24, 40)

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
    -- the one the follow-up ships: the wheel's own flag is in it, which is what
    -- makes SuppressTouchMovement(ScreenOwningModalOpen()) true on open.
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
    ctx.Shade = descendant(ctx.Gui, 'LuckyWheelShade')
    ctx.Panel = descendant(ctx.Shade, 'LuckyWheelPanel')
    ctx.Close = descendant(ctx.Panel, 'CloseButton')
    ctx.Status = descendant(ctx.Panel, 'StatusLine')
    ctx.Body = descendant(ctx.Panel, 'WheelBody')
    ctx.Holder = descendant(ctx.Body, 'DiscHolder')
    ctx.Disc = descendant(ctx.Holder, 'WheelDisc')
    ctx.Rim = descendant(ctx.Holder, 'WheelRim')
    ctx.Hub = descendant(ctx.Holder, 'WheelHub')
    ctx.Pointer = descendant(ctx.Holder, 'WheelPointer')
    ctx.Legend = descendant(ctx.Body, 'WheelLegend')
    -- SPIN and SKIP move between the body and the panel footer with the tier,
    -- so they are looked up from the panel, which contains both.
    ctx.Spin = descendant(ctx.Panel, 'SpinButton')
    ctx.Skip = descendant(ctx.Panel, 'SkipButton')
    ctx.Banner = descendant(ctx.Body, 'ResultBanner')
    ctx.BannerText = descendant(ctx.Banner, 'ResultText')
    ctx.Note = descendant(ctx.Body, 'NoteLine')
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

-- A profile as ZyntraMonetization publishes it: the Daily block and nothing the
-- client is allowed to invent.
local function daily(options)
    options = options or {}
    local block = {
        Day = TODAY, Today = TODAY, PlaytimeSeconds = options.Played or 0,
        Claimed = {}, SecondsToReset = options.Reset or 3600, Accruing = false,
    }
    if options.Key then
        block.WheelDay = TODAY
        block.WheelLast = {Day = TODAY, Key = options.Key, Serial = options.Serial or 1}
    end
    return {Daily = block, Tokens = 0}
end
local function push(ctx, profile) ctx.Pushes.OnClientEvent:Fire(profile) end

-- The five prizes, read off the REAL config, with the wedge each one owns.
local WHEEL = {}
do
    local ctx = start(POINTER)
    local total = 0
    for _, entry in ipairs(ctx.Config.DailyRewards.Wheel) do total += entry.Weight end
    local cumulative = 0
    for order, entry in ipairs(ctx.Config.DailyRewards.Wheel) do
        local start = cumulative / total * 360
        cumulative += entry.Weight
        table.insert(WHEEL, {Order = order, Key = entry.Key, Label = entry.Label,
            Weight = entry.Weight, Start = start, Width = entry.Weight / total * 360,
            Odds = tostring(math.floor(entry.Weight / total * 100 + 0.5)) .. '%'})
    end
    check(#WHEEL == 5, 'the shipped config has five prizes')
    check(total == 100, 'the shipped weights total 100, so a weight IS a percent')
end

-- Where the stationary pointer at 12 o'clock is looking, given a Rotation.
local function pointerAngle(rotation) return (-rotation) % 360 end
local function sectorAt(angle)
    for _, prize in ipairs(WHEEL) do
        if angle >= prize.Start and angle < prize.Start + prize.Width then return prize end
    end
    return nil
end

-- ── it is built, and it is a wheel ───────────────────────────────────────
do
    local ctx = start(POINTER)
    check(ctx.Gui ~= nil and ctx.Gui.ClassName == 'ScreenGui', 'the ScreenGui is built')
    check(ctx.Gui.Name == 'LuckyWheelGui', 'it carries the contracted name')
    check(ctx.Gui.DisplayOrder == 118, 'DisplayOrder 118, as the contract fixes it')
    check(ctx.Gui.ResetOnSpawn == false, 'it survives a respawn')
    check(ctx.Gui.ScreenInsets == Enum.ScreenInsets.CoreUISafeInsets,
        'it lives in the terminal\'s inset space')
    check(ctx.Shade ~= nil and ctx.Shade.Active == true,
        'the shade is Active, so a tap behind the panel reaches nothing')
    check(ctx.Shade.Visible == false, 'nothing is drawn until the rail asks for it')
    check(ctx.Panel ~= nil, 'the panel is built')
    check(ctx.Body ~= nil and ctx.Body.ClassName == 'ScrollingFrame',
        'the content is a ScrollingFrame, so a short screen scrolls instead of clipping')
    check(ctx.Disc ~= nil and ctx.Rim ~= nil and ctx.Hub ~= nil and ctx.Pointer ~= nil,
        'disc, rim, hub and pointer all exist')
    check(ctx.Pointer.Rotation == 45, 'the pointer is a 45-degree marker')
    check(ctx.Pointer.Parent == ctx.Holder,
        'the pointer is NOT a child of the disc, so it never turns with it')
    check(ctx.Rim.Parent == ctx.Holder, 'the rim does not turn either')
    check(ctx.Rim:FindFirstChildOfClass('UICorner').CornerRadius.S == 1,
        'the rim is a circle')
    check(ctx.Rim:FindFirstChildOfClass('UIStroke').Thickness >= 2,
        'the rim is drawn by a thick stroke, not by an image')
    check(ctx.Hub:FindFirstChildOfClass('UICorner').CornerRadius.S == 1, 'the hub is a circle')

    -- THE ARMS. Roblox rotates a GuiObject about the centre of its own
    -- rectangle, NOT about its AnchorPoint, so what rotates has to be a frame
    -- whose own centre IS the disc's centre: a full-diameter transparent arm
    -- carrying the coloured top half. A half-length frame anchored on the hub
    -- would pivot radius/2 too high and draw a flower ring instead of a disc.
    local arms, spokes = {}, {}
    for _, child in ipairs(ctx.Disc.Children) do
        if child.Name:sub(1, 3) == 'Arm' then
            table.insert(arms, child)
            table.insert(spokes, descendant(child, 'Spoke' .. child.Name:sub(4)))
        end
    end
    check(#arms == 180, 'the disc is 180 rotating arms')
    check(#spokes == 180, 'each arm carries exactly one coloured spoke')
    local rotationsOk, centredOk, zeroOk = true, true, false
    local topHalfOk, clearArmOk, spokePlacedOk = true, true, true
    local discSize = ctx.Holder.Size.OX
    local fullLengthOk = true
    for index, arm in ipairs(arms) do
        if arm.Rotation ~= (index - 1) * 2 then rotationsOk = false end
        -- Centred on the hub AND the full diameter: both are needed, because
        -- the pivot is the rectangle's centre, not the anchor.
        if arm.AnchorPoint.X ~= 0.5 or arm.AnchorPoint.Y ~= 0.5 then centredOk = false end
        if arm.Position.SX ~= 0.5 or arm.Position.SY ~= 0.5
            or arm.Position.OX ~= 0 or arm.Position.OY ~= 0 then centredOk = false end
        if arm.Size.OY ~= discSize then fullLengthOk = false end
        if arm.BackgroundTransparency ~= 1 then clearArmOk = false end
        if index == 1 and arm.Rotation == 0 then zeroOk = true end
        local spoke = spokes[index]
        -- The TOP half only, by scale, so a resize of the arm carries it.
        if spoke.Size.SX ~= 1 or spoke.Size.SY ~= 0.5
            or spoke.Size.OX ~= 0 or spoke.Size.OY ~= 0 then topHalfOk = false end
        if spoke.Position.SX ~= 0 or spoke.Position.SY ~= 0
            or spoke.Position.OX ~= 0 or spoke.Position.OY ~= 0 then spokePlacedOk = false end
    end
    check(rotationsOk, 'every arm sits two degrees from the last')
    check(centredOk, 'every arm is centred on the hub, so it pivots about the hub')
    check(fullLengthOk, 'every arm is the FULL diameter, so its own centre is the hub')
    check(clearArmOk, 'the arm itself paints nothing; only its top half is coloured')
    check(topHalfOk, 'the coloured spoke is the top half of the arm, sized by scale')
    check(spokePlacedOk, 'and it sits at the arm\'s origin, reaching the rim')
    check(zeroOk, 'the first arm points at 12 o\'clock, where the pointer is')
    check(arms[1].Size.OX >= 1 and arms[1].Size.OX <= 12,
        'the arm is about one 180th of the circumference wide')

    -- WEDGE SIZE IS THE ODDS. 45/20/20/5/10 -> 81/36/36/9/18 spokes.
    local counts, colors = {}, {}
    for index, spoke in ipairs(spokes) do
        local key = spoke.BackgroundColor3.Key
        counts[key] = (counts[key] or 0) + 1
        colors[index] = key
    end
    local distinct = 0
    for _ in pairs(counts) do distinct += 1 end
    check(distinct == 5, 'five prizes are five distinguishable wedge colours')
    -- Each wedge is one contiguous run of one colour, in config order.
    local at = 1
    for _, prize in ipairs(WHEEL) do
        local want = math.floor(prize.Weight * 1.8 + 0.5)
        local color = colors[at]
        local run = 0
        while colors[at + run] == color do run += 1 end
        check(run == want, prize.Key .. ': ' .. want
            .. ' of the 180 spokes, which is exactly its ' .. prize.Odds)
        at += run
    end
    check(at == 181, 'the five runs account for the whole disc with nothing left over')

    -- Adjacent wedges must never share a colour, or two prizes read as one --
    -- which is the "equal sectors, unequal odds" failure inverted.
    local adjacentOk = true
    local runColors = {}
    at = 1
    for _ in ipairs(WHEEL) do
        local color = colors[at]
        table.insert(runColors, color)
        local run = 0
        while colors[at + run] == color do run += 1 end
        at += run
    end
    for index, color in ipairs(runColors) do
        local neighbour = runColors[index % #runColors + 1]
        if color == neighbour then adjacentOk = false end
    end
    check(adjacentOk, 'no wedge shares a colour with the wedge next to it')
end

-- ── the legend prints the real odds ──────────────────────────────────────
do
    local ctx = start(POINTER)
    local rows = 0
    for _, child in ipairs(ctx.Legend.Children) do
        if child.Name:sub(1, 9) == 'LegendRow' then rows += 1 end
    end
    check(rows == 5, 'the legend has one row per prize')
    for _, prize in ipairs(WHEEL) do
        local row = descendant(ctx.Legend, 'LegendRow' .. tostring(prize.Order))
        local label = descendant(row, 'LegendLabel')
        local odds = descendant(row, 'LegendOdds')
        local swatch = descendant(row, 'Swatch')
        check(label.Text == prize.Label, prize.Key .. ': the legend prints the config label')
        check(odds.Text == prize.Odds, prize.Key .. ': the legend prints ' .. prize.Odds)
        check(swatch ~= nil, prize.Key .. ': the legend row carries a colour swatch')
    end
    -- The 5% wedge is only 18 degrees: too narrow for a label, which is exactly
    -- why the legend is not optional.
    check(descendant(ctx.Disc, 'SectorLabel1') ~= nil, 'the 162-degree wedge is labelled')
    check(descendant(ctx.Disc, 'SectorLabel2') ~= nil, 'the first 72-degree wedge is labelled')
    check(descendant(ctx.Disc, 'SectorLabel3') ~= nil, 'the second 72-degree wedge is labelled')
    check(descendant(ctx.Disc, 'SectorLabel4') == nil,
        'the 18-degree wedge carries no label it could not fit')
    check(descendant(ctx.Disc, 'SectorLabel5') ~= nil, 'the 36-degree wedge is labelled')
    check(descendant(ctx.Disc, 'SectorLabel1').Text == '1 TOKEN',
        'the wedge carries the short form, the legend the long one')
end

-- ── the open bindable is created when the rail has not ───────────────────
do
    local ctx = start(POINTER, {Prompt = false})
    check(ctx.OpenEvent ~= nil and ctx.OpenEvent.ClassName == 'BindableEvent',
        'OpenLuckyWheel is created when the rail has not made it yet')
    open(ctx)
    check(ctx.Shade.Visible == true, 'and it opens the panel')
end

-- ── opening and refusing ─────────────────────────────────────────────────
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
    check(ctx.Invokes == invokes, 'a second open on an open panel does nothing at all')
end
for _, case in ipairs({
    {Name = 'in a round', Attribute = 'InRound'},
    {Name = 'with the terminal open', Attribute = 'ZyntraStoreOpen'},
    {Name = 'with the re-entry modal open', Attribute = 'ZyntraReentryOpen'},
    {Name = 'with the daily rewards modal open', Attribute = 'DailyRewardsOpen'},
    {Name = 'in the queue modal', Attribute = 'QueueModalOpen'},
}) do
    local ctx = start(POINTER)
    ctx.Player:SetAttribute(case.Attribute, true)
    open(ctx)
    check(ctx.Shade.Visible == false, case.Name .. ': the wheel refuses to open')
    check(ctx.Player:GetAttribute('LuckyWheelOpen') == nil,
        case.Name .. ': and publishes nothing')
end

-- ── every way out ────────────────────────────────────────────────────────
for _, case in ipairs({
    {Name = 'CLOSE', Apply = function(ctx) ctx.Close.Activated:Fire() end},
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
    open(ctx)
    check(ctx.Shade.Visible == true, case.Name .. ': it was open first')
    case.Apply(ctx)
    check(ctx.Shade.Visible == false, case.Name .. ' closes the wheel')
    check(ctx.Player:GetAttribute('LuckyWheelOpen') == nil,
        case.Name .. ': and clears the modal attribute')
    check(ctx.Suppress[#ctx.Suppress] == (case.Still == true),
        case.Name .. ': and the movement cluster is left as the OTHER modals need it')
end
do
    -- Escape while the panel is closed must not reach anything.
    local ctx = start(POINTER)
    ctx.UIS.InputBegan:Fire({KeyCode = Enum.KeyCode.Escape}, false)
    check(#ctx.Suppress == 0, 'Escape does nothing while the wheel is shut')
    check(ctx.Bound.LuckyWheelClose == nil, 'and no gamepad action is left bound')
end

-- ── asking for the spin ──────────────────────────────────────────────────
do
    local ctx = start(POINTER)
    open(ctx)
    push(ctx, daily({}))
    check(ctx.Spin.Text == 'FREE SPIN', 'an unspent day offers the free spin')
    check(ctx.Spin.Active == true, 'and the button takes input')
    ctx.Spin.Activated:Fire()
    check(#ctx.Sent == 1, 'SPIN asks the server exactly once')
    check(ctx.Sent[1].Action == 'SpinDailyWheel', 'and it asks for SpinDailyWheel')
    check(ctx.Sent[1].Payload == nil, 'with no payload for the server to trust')
    check(ctx.Spin.Text == 'SPINNING...', 'the button says so')
    check(ctx.Spin.Active == false, 'and locks')
    ctx.Spin.Activated:Fire()
    ctx.Spin.Activated:Fire()
    check(#ctx.Sent == 1, 'a double press cannot become a second request')
    check(#ctx.Tweens == 0, 'and nothing spins before the server has answered')
end
do
    -- 6 s of silence: re-enable, say so, and RE-READ. Never a local grant.
    local ctx = start(POINTER)
    open(ctx)
    push(ctx, daily({}))
    local invokes = ctx.Invokes
    ctx.Spin.Activated:Fire()
    ctx:Advance(5.5)
    check(ctx.Spin.Active == false, 'five and a half seconds is not yet a failure')
    ctx:Advance(1)
    check(ctx.Status.Text == 'No answer yet. Try again.',
        'six seconds of silence is reported in the status line')
    check(ctx.Spin.Active == true, 'and the player may ask again')
    check(ctx.Spin.Text == 'FREE SPIN', 'with the button back to its resting copy')
    check(ctx.Invokes == invokes + 1, 'the recovery is a RE-READ of the profile')
    check(#ctx.Tweens == 0, 'and the client still never picked a prize')
end
do
    -- An answer that arrives makes the armed timeout stale.
    local ctx = start(POINTER)
    open(ctx)
    push(ctx, daily({}))
    ctx.Spin.Activated:Fire()
    push(ctx, daily({Key = 'Token1', Serial = 1}))
    ctx.Skip.Activated:Fire()
    local text = ctx.Status.Text
    ctx:Advance(8)
    check(ctx.Status.Text == text, 'an answered request never reports a timeout later')
    check(#ctx.Tweens == 1, 'and never starts a second spin')
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
            local landed = sectorAt(pointerAngle(tween.Goal.Rotation))
            local ok = #ctx.Tweens == before + 1
                and tween.Played
                and tween.Instance == ctx.Disc
                and tween.Goal.Rotation > rotationBefore
                and landed ~= nil and landed.Key == prize.Key
            check(ok, prize.Key .. ' at Serial ' .. serial
                .. ': one forward tween landing the pointer in its own wedge')
            seen += 1
            ctx.Skip.Activated:Fire()
        end
    end
    check(seen == 100, 'a hundred recorded results were replayed')
    check(#ctx.Tweens == 100, 'each of them asked for exactly one tween')
end
do
    -- The landing keeps clear of the boundaries, so a result never looks like a
    -- near miss of the wedge next to it.
    local ctx = start(POINTER)
    open(ctx)
    push(ctx, daily({}))
    local clear = true
    for _, prize in ipairs(WHEEL) do
        for serial = 1, 20 do
            push(ctx, daily({Key = prize.Key, Serial = serial}))
            local angle = pointerAngle(ctx.Tweens[#ctx.Tweens].Goal.Rotation)
            local into = angle - prize.Start
            if into < 3.9 or into > prize.Width - 3.9 then clear = false end
            ctx.Skip.Activated:Fire()
        end
    end
    check(clear, 'every landing is at least four degrees inside its own wedge')
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
    local second = pointerAngle(b.Tweens[1].Goal.Rotation)
    check(math.abs(first - second) < 1e-9,
        'the jitter is derived from the Serial, so two clients land identically')
    check(math.abs(first - pointerAngle(a.Tweens[1].Goal.Rotation)) < 1e-9,
        'and it does not move when it is read again')
end

-- ── the animation, and the ways out of it ────────────────────────────────
do
    local ctx = start(POINTER)
    open(ctx)
    push(ctx, daily({}))
    push(ctx, daily({Key = 'Shield1', Serial = 3}))
    local tween = ctx.Tweens[1]
    check(tween.Info.Time == 4.2, 'the full spin runs 4.2 seconds')
    check(tween.Info.Style == Enum.EasingStyle.Quint, 'on a Quint curve')
    check(tween.Info.Direction == Enum.EasingDirection.Out, 'decelerating into the result')
    check(tween.Goal.Rotation - ctx.Disc.Rotation > 1080,
        'and it turns at least three whole times before it lands')
    check(ctx.Skip.Visible == true, 'SKIP appears only while a result is replaying')
    check(ctx.Banner.Visible == false, 'the result is not announced before it lands')
    check(ctx.Spin.Text == 'SPINNING...', 'and the spin button says what is happening')
    ctx.Skip.Activated:Fire()
    check(ctx.Disc.Rotation == tween.Goal.Rotation, 'SKIP jumps straight to the result')
    check(tween.Cancelled == true, 'and stops the tween rather than leaving it running')
    check(ctx.Skip.Visible == false, 'SKIP goes away with the animation')
    check(ctx.Banner.Visible == true, 'and the result is announced')
    check(ctx.BannerText.Text == 'YOU RECEIVED: 1 Entity Shield',
        'with the prize the SERVER recorded, spelled its way')
    check(ctx.Spin.Text == 'SPUN TODAY', 'and today\'s free spin is spent')
    check(ctx.Spin.Active == false, 'so the button stops taking input')
    check(sectorAt(pointerAngle(ctx.Disc.Rotation)).Key == 'Shield1',
        'the pointer is sitting in the wedge the server picked')
end
do
    -- Letting it run to the end is the same landing.
    local ctx = start(POINTER)
    open(ctx)
    push(ctx, daily({}))
    push(ctx, daily({Key = 'Potion2', Serial = 9}))
    ctx.Tweens[1]:Finish()
    check(ctx.Banner.Visible == true, 'a tween that completes announces the result')
    check(ctx.BannerText.Text == 'YOU RECEIVED: 2 Speed Potions', 'and names the prize')
    check(sectorAt(pointerAngle(ctx.Disc.Rotation)).Key == 'Potion2',
        'and leaves the pointer in the 5% wedge it actually won')
    check(#ctx.Tweens == 1, 'completing a tween does not start another')
end
do
    -- ReduceFlashing: one slow turn, no five-turn blur.
    local ctx = start(POINTER)
    ctx.Player:SetAttribute('ReduceFlashing', true)
    open(ctx)
    push(ctx, daily({}))
    push(ctx, daily({Key = 'Token3', Serial = 4}))
    local tween = ctx.Tweens[1]
    check(tween.Info.Time == 1.4, 'reduced flashing runs 1.4 seconds')
    check(tween.Info.Style == Enum.EasingStyle.Sine, 'on a Sine curve')
    local travel = tween.Goal.Rotation - ctx.Disc.Rotation
    check(travel > 0, 'and never jerks backwards')
    check(travel <= 720, 'and turns about once rather than five times')
    check(sectorAt(pointerAngle(tween.Goal.Rotation)).Key == 'Token3',
        'and still lands on the recorded prize')
end
do
    -- Closing the panel mid-spin ends the replay: the prize was banked first.
    local ctx = start(POINTER)
    open(ctx)
    push(ctx, daily({}))
    push(ctx, daily({Key = 'Token1', Serial = 2}))
    check(ctx.Skip.Visible == true, 'it is spinning')
    ctx.Close.Activated:Fire()
    check(ctx.Disc.Rotation == ctx.Tweens[1].Goal.Rotation,
        'closing finishes the replay rather than freezing it mid-turn')
    open(ctx)
    check(ctx.Banner.Visible == true, 'reopening shows the landed result')
    check(#ctx.Tweens == 1, 'and does not replay it')
end

-- ── a replay is not a spin ───────────────────────────────────────────────
do
    -- THE FIRST PROFILE IS A SEED. A player who spun this morning and rejoined
    -- at lunch is shown the prize, not made to watch it land again.
    local ctx = start(POINTER)
    open(ctx)
    push(ctx, daily({Key = 'Potion1', Serial = 6}))
    check(#ctx.Tweens == 0, 'a rejoin never animates a result from earlier today')
    check(ctx.Banner.Visible == true, 'it is shown as already landed')
    check(ctx.BannerText.Text == 'YOU RECEIVED: 1 Speed Potion', 'with the right prize')
    check(sectorAt(pointerAngle(ctx.Disc.Rotation)).Key == 'Potion1',
        'and the disc is PARKED with the pointer in that wedge')
    check(ctx.Spin.Text == 'SPUN TODAY', 'and the day is spent')
end
do
    local ctx = start(POINTER)
    open(ctx)
    push(ctx, daily({}))
    push(ctx, daily({Key = 'Token1', Serial = 5}))
    ctx.Skip.Activated:Fire()
    local rotation = ctx.Disc.Rotation
    push(ctx, daily({Key = 'Token1', Serial = 5}))
    check(#ctx.Tweens == 1, 'a push carrying the SAME Serial animates nothing')
    check(ctx.Disc.Rotation == rotation, 'and does not move the disc')
    check(ctx.Banner.Visible == true, 'the landed result stays on screen')
    push(ctx, daily({Key = 'Token1', Serial = 5}))
    push(ctx, daily({Key = 'Token1', Serial = 5}))
    check(#ctx.Tweens == 1, 'however many times the server repeats itself')
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
    check(ctx.Banner.Visible == false, 'and is not announced as today\'s')
    check(ctx.Spin.Text == 'FREE SPIN', 'today\'s spin is still free')
end

-- ── the countdown ────────────────────────────────────────────────────────
do
    local ctx = start(POINTER)
    open(ctx)
    push(ctx, daily({}))
    check(ctx.Note.Text == 'One free spin a day. Resets 00:00 UTC.',
        'an unspent day states the rule and nothing else')
    push(ctx, daily({Key = 'Token1', Serial = 1, Reset = 3600}))
    ctx.Skip.Activated:Fire()
    check(ctx.Note.Text == 'One free spin a day. Resets 00:00 UTC.  Next spin in 01:00:00',
        'a spent day counts down to the UTC reset')
    tick(ctx, 61)
    check(ctx.Note.Text == 'One free spin a day. Resets 00:00 UTC.  Next spin in 00:58:59',
        'and the countdown ticks in real time')
end
do
    -- Ticking behind a closed panel is 60 wasted string builds a second.
    local ctx = start(POINTER)
    open(ctx)
    push(ctx, daily({Key = 'Token1', Serial = 1, Reset = 3600}))
    local text = ctx.Note.Text
    ctx.Close.Activated:Fire()
    tick(ctx, 120)
    check(ctx.Note.Text == text, 'a closed wheel does not redraw its countdown')
    open(ctx)
    check(ctx.Note.Text ~= text, 'and reopening catches it back up')
end
do
    -- Midnight: the server owns the new counters, so the client asks for them.
    local ctx = start(POINTER)
    open(ctx)
    push(ctx, daily({Key = 'Token1', Serial = 1, Reset = 2}))
    local invokes = ctx.Invokes
    tick(ctx, 4)
    check(ctx.Invokes == invokes + 1, 'the UTC roll triggers exactly one re-read')
    tick(ctx, 10)
    check(ctx.Invokes == invokes + 1, 'and not one per second afterwards')
end

-- ── layout, at four stated viewports ─────────────────────────────────────
local function rect(object, offsetX, offsetY)
    return {L = offsetX + object.Position.OX, T = offsetY + object.Position.OY,
        R = offsetX + object.Position.OX + object.Size.OX,
        B = offsetY + object.Position.OY + object.Size.OY}
end
local function inside(child, parent)
    return child.L >= parent.L - 0.001 and child.T >= parent.T - 0.001
        and child.R <= parent.R + 0.001 and child.B <= parent.B + 0.001
end
for _, case in ipairs({
    {Name = 'desktop 1280x720', Layout = POINTER, Touch = false},
    {Name = 'phone portrait 390x844', Layout = PHONE_PORTRAIT, Touch = true},
    {Name = 'phone landscape 844x390', Layout = PHONE_LANDSCAPE, Touch = true},
    {Name = 'tablet 1024x768', Layout = TABLET, Touch = true},
    {Name = 'short landscape 705x338', Layout = PHONE_SHORT, Touch = true},
    {Name = 'an inset desktop', Layout = OFFSET_POINTER, Touch = false},
}) do
    local ctx = start(case.Layout)
    open(ctx)
    push(ctx, daily({Key = 'Token1', Serial = 1}))
    local area = case.Layout.ModalViewport
    local panel = rect(ctx.Panel, case.Layout.OriginX, case.Layout.OriginY)
    check(inside(panel, {L = area.Left, T = area.Top, R = area.Right, B = area.Bottom}),
        case.Name .. ': the panel is inside the modal viewport')
    check(ctx.Panel.Size.OX > 0 and ctx.Panel.Size.OY > 0,
        case.Name .. ': and it has a real rectangle')
    for _, name in ipairs({'CloseButton', 'Eyebrow', 'Title', 'StatusLine', 'WheelBody'}) do
        local child = descendant(ctx.Panel, name)
        check(inside(rect(child, panel.L, panel.T), panel),
            case.Name .. ': ' .. name .. ' is inside the panel')
    end
    local body = rect(ctx.Body, panel.L, panel.T)
    for _, name in ipairs({'DiscHolder', 'WheelLegend', 'NoteLine'}) do
        local child = descendant(ctx.Body, name)
        local box = rect(child, body.L, body.T)
        check(box.L >= body.L - 0.001 and box.R <= body.R + 0.001,
            case.Name .. ': ' .. name .. ' fits the content width')
    end
    -- Vertical overflow is legitimate, but only because it scrolls.
    local note = rect(descendant(ctx.Body, 'NoteLine'), body.L, body.T)
    check(body.T + ctx.Body.CanvasSize.OY >= note.B - 0.001,
        case.Name .. ': the canvas covers everything the content reaches')
    if case.Touch then
        -- FIX 2. The one control that matters must not be under the fold.
        check(ctx.Spin.Parent == ctx.Panel,
            case.Name .. ': SPIN is a fixed footer control, not a scrolling one')
        check(ctx.Skip.Parent == ctx.Panel, case.Name .. ': and so is SKIP')
        local status = rect(ctx.Status, panel.L, panel.T)
        local spinBox = rect(ctx.Spin, panel.L, panel.T)
        check(inside(spinBox, panel), case.Name .. ': the footer is inside the panel')
        check(spinBox.B <= status.T + 0.001,
            case.Name .. ': the footer sits above the status line')
        check(spinBox.T >= body.B - 0.001,
            case.Name .. ': and below the scrolling body, never over it')
        check(ctx.Holder.Position.OY + ctx.Holder.Size.OY <= ctx.Body.Size.OY + 0.001,
            case.Name .. ': the whole disc is visible without scrolling at all')
        check(ctx.Holder.Size.OX >= 140,
            case.Name .. ': and it is still big enough to read')
        check(ctx.Close.Size.OY >= 44, case.Name .. ': CLOSE is a 44px tap target')
        check(ctx.Spin.Size.OY >= 44, case.Name .. ': SPIN is a 44px tap target')
        check(ctx.Skip.Size.OY >= 44, case.Name .. ': SKIP is a 44px tap target')
        check(ctx.Holder.Size.OX <= 260,
            case.Name .. ': the disc takes the width a hand can reach across')
    else
        check(ctx.Spin.Parent == ctx.Body,
            case.Name .. ': SPIN scrolls with the legend on a pointer tier')
        check(ctx.Skip.Parent == ctx.Body, case.Name .. ': and so does SKIP')
        check(ctx.Holder.Size.OX >= 160,
            case.Name .. ': a pointer device gets a disc worth looking at')
    end
    -- The layout pass resizes the ARMS, not the coloured halves: an arm that is
    -- not the full diameter no longer pivots about the hub.
    local arm = descendant(ctx.Disc, 'Arm1')
    check(arm.Size.OY == ctx.Holder.Size.OX,
        case.Name .. ': every arm is resized to the full diameter')
    check(descendant(arm, 'Spoke1').Size.SY == 0.5,
        case.Name .. ': and the coloured half follows it by scale, unwritten')
    for _, name in ipairs({'Eyebrow', 'Title', 'StatusLine', 'NoteLine', 'CloseButton',
        'SpinButton', 'SkipButton'}) do
        local object = descendant(ctx.Panel, name)
        check(object.TextSize >= 11, case.Name .. ': ' .. name .. ' prints at 11px or larger')
    end
    for order in ipairs(WHEEL) do
        local row = descendant(ctx.Legend, 'LegendRow' .. tostring(order))
        check(descendant(row, 'LegendLabel').TextSize >= 11
            and descendant(row, 'LegendOdds').TextSize >= 11,
            case.Name .. ': legend row ' .. order .. ' prints at 11px or larger')
    end
    check(ctx.Close.Text == 'CLOSE' and not ctx.Close.Text:find('%['),
        case.Name .. ': no keyboard glyph is printed on any device')
end
for _, case in ipairs({
    {Name = 'phone portrait', Layout = PHONE_PORTRAIT},
    {Name = 'phone landscape', Layout = PHONE_LANDSCAPE},
    {Name = 'short landscape', Layout = PHONE_SHORT},
    {Name = 'tablet', Layout = TABLET},
}) do
    -- FIX 2, the footer while a replay is running: SKIP takes a fixed strip on
    -- the right and SPIN the rest. Both stay thumb-sized and both stay inside.
    local ctx = start(case.Layout)
    open(ctx)
    push(ctx, daily({}))
    local wide = ctx.Spin.Size.OX
    local restingTop = ctx.Spin.Position.OY
    ctx.Spin.Activated:Fire()
    push(ctx, daily({Key = 'Token1', Serial = 1}))
    check(ctx.Skip.Visible == true, case.Name .. ': SKIP is drawn during the replay')
    check(ctx.Skip.Parent == ctx.Panel, case.Name .. ': in the footer, not the scroll')
    check(ctx.Skip.Size.OX >= 92, case.Name .. ': SKIP keeps a 92px strip')
    check(ctx.Skip.Size.OY >= 44 and ctx.Spin.Size.OY >= 44,
        case.Name .. ': and both footer controls stay 44px tall')
    check(ctx.Spin.Size.OX < wide, case.Name .. ': SPIN gives up the width SKIP took')
    check(ctx.Spin.Size.OX >= 100, case.Name .. ': but stays a real button')
    check(ctx.Spin.Position.OY == restingTop and ctx.Skip.Position.OY == restingTop,
        case.Name .. ': the footer row does not move when SKIP appears')
    check(ctx.Spin.Position.OX + ctx.Spin.Size.OX <= ctx.Skip.Position.OX,
        case.Name .. ': and the two never overlap')
    check(ctx.Skip.Position.OX + ctx.Skip.Size.OX <= ctx.Panel.Size.OX,
        case.Name .. ': SKIP stays inside the panel')
    ctx.Skip.Activated:Fire()
    check(ctx.Spin.Size.OX == wide, case.Name .. ': and SPIN takes the row back after')
end
do
    -- A rotation re-lays the panel out rather than leaving it describing the
    -- screen the player used to be holding.
    local ctx = start(PHONE_PORTRAIT)
    open(ctx)
    local portrait = ctx.Panel.Size.OY
    ctx.Layout = PHONE_LANDSCAPE
    ctx.UIDevice.Changed:Fire()
    check(ctx.Panel.Size.OY ~= portrait, 'rotating the phone resizes the panel')
    check(ctx.Panel.Size.OY <= 390, 'and keeps it inside the shorter viewport')
    ctx.Layout = PHONE_PORTRAIT
    ctx.UIDevice.Changed:Fire()
    check(ctx.Panel.Size.OY == portrait, 'and back again')
end

-- ── gamepad, and the Studio-only probe ───────────────────────────────────
do
    local ctx = start(POINTER, {LastInput = 'Gamepad'})
    open(ctx)
    check(ctx.GuiService.SelectedObject ~= nil, 'a gamepad is given something to select')
    ctx.Close.Activated:Fire()
    check(ctx.GuiService.SelectedObject == nil, 'and closing hands selection back')
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
    check(probe.OnInvoke('state') == false, 'which reports the panel shut')
    check(probe.OnInvoke('open') == true, 'opens it')
    check(probe.OnInvoke('state') == true, 'and says so')
    check(probe.OnInvoke('close') == false, 'and closes it again')
end
do
    local ctx = start(POINTER, {Studio = false})
    check(descendant(ctx.Gui, 'UIRegressionLuckyWheelProbe') == nil,
        'a live server ships no probe')
end

print('Lucky Wheel client: ' .. checks
    .. ' checks passed (entire actual LocalScript + real UIStyle and ZyntraConfig,'
    .. ' offline Luau; real rendering, fonts and tween timing not exercised)')
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
