"""Exercise the whole Friend Boost feature offline: module, payout and chip.

FRIEND_BOOST_20260916 (owner brief section 4). Three real sources run under one
fake DataModel, none of them copied or paraphrased:

  * ServerScriptService/FriendBoost.ModuleScript.lua runs ENTIRELY, against fake
    Players whose IsFriendsWith is scripted and can throw.
  * The completion payout is EXTRACTED from ZyntraMonetization by string
    markers -- the levelCompletedEvent handler and the FriendBoostTenths
    normalisation lines -- so the arithmetic under test is the shipping one.
  * StarterPlayerScripts/Friend Boost Client.LocalScript.lua runs entirely, with
    the real UIStyle and ZyntraConfig modules and a faked UIDevice/SocialService.

The real ReplicatedStorage/ZyntraConfig is loaded once and shared by all three,
so PercentPerFriend is read rather than restated.

What this CANNOT see, and what a Studio pass is for: real Roblox friendships and
their throttling, whether SocialService answers at all on a given platform, font
metrics, and where the chip actually lands on a real device. Set LUAU_BIN, or
put luau on PATH.
"""

import os
from pathlib import Path
import shutil
import subprocess
import tempfile

ROOT = Path(__file__).resolve().parents[2]
CONFIG = (ROOT / "ReplicatedStorage/ZyntraConfig.ModuleScript.lua").read_text(encoding="utf-8")
UISTYLE = (ROOT / "ReplicatedStorage/UIStyle.ModuleScript.lua").read_text(encoding="utf-8")
MODULE = (ROOT / "ServerScriptService/FriendBoost.ModuleScript.lua").read_text(encoding="utf-8")
CLIENT = (ROOT / "StarterPlayer/StarterPlayerScripts/Friend Boost Client.LocalScript.lua").read_text(encoding="utf-8")
MONETIZATION = (ROOT / "ServerScriptService/ZyntraMonetization.Script.lua").read_text(encoding="utf-8")


def section(source, start, stop):
    begin = source.index(start)
    return source[begin:source.index(stop, begin)]


HARNESS = r'''
local checks = 0
local function check(value, message)
    assert(value, message)
    checks += 1
end
local function equal(actual, expected, message)
    check(actual == expected, message .. ": expected " .. tostring(expected)
        .. ", got " .. tostring(actual))
end
local function contains(actual, expected, message)
    check(type(actual) == "string" and string.find(actual, expected, 1, true) ~= nil,
        message .. ": " .. tostring(actual))
end
local function missing(actual, expected, message)
    check(type(actual) == "string" and string.find(actual, expected, 1, true) == nil,
        message .. ": " .. tostring(actual))
end

-- signals that really disconnect
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
    return s
end

-- value types, memoised so `==` answers "same value" the way the engine's do
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

-- instances
local SIGNALS = {Activated = true, MouseEnter = true, MouseLeave = true, Event = true}
local methods = {}
local function newInstance(class, name)
    local fields = {ClassName = class, Name = name or class, Children = {}, Attributes = {},
        Watchers = {}, Visible = true, Text = '', TextScaled = false, Parent = nil}
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
function methods:IsA(class) return class == self.ClassName end
function methods:FindFirstChild(name)
    for _, child in ipairs(self.Children) do if child.Name == name then return child end end
    return nil
end
function methods:FindFirstChildOfClass(class)
    for _, child in ipairs(self.Children) do if child.ClassName == class then return child end end
    return nil
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
local function descendant(root, name)
    for _, child in ipairs(root.Children) do
        if child.Name == name then return child end
        local found = descendant(child, name)
        if found then return found end
    end
    return nil
end

-- the REAL ZyntraConfig, so PercentPerFriend is read and not restated
local ZyntraConfig = (function()
'''

CONFIG_TAIL = r'''
end)()
check(type(ZyntraConfig.FriendBoost) == "table", "ZyntraConfig declares a FriendBoost table")
equal(ZyntraConfig.FriendBoost.PercentPerFriend, 10, "the boost is +10% per friend")
equal(ZyntraConfig.LevelCompletionTokens, 2, "the completion payout is still 2 tokens")
local PERCENT = ZyntraConfig.FriendBoost.PercentPerFriend
local BASE = ZyntraConfig.LevelCompletionTokens

-- ════════════════════════════════════════════════════════════════════════
-- 1. THE MODULE
-- ════════════════════════════════════════════════════════════════════════

local function server()
    local w = {friends = {}, failing = {}, lookups = 0, roster = {}}
    local function key(a, b)
        if a > b then a, b = b, a end
        return a .. ':' .. b
    end
    w.key = key
    local Players = newInstance('Players', 'Players')
    Players.PlayerAdded = signal()
    Players.PlayerRemoving = signal()
    function Players:GetPlayers() return table.clone(w.roster) end
    function w.add(name, userId)
        local p = newInstance('Player', name)
        p.UserId = userId
        p.Parent = Players
        function p:IsFriendsWith(otherId)
            w.lookups += 1
            check(otherId ~= self.UserId, 'a player is never asked about themselves')
            if w.failing[key(self.UserId, otherId)] then error('HTTP 429 Too Many Requests') end
            return w.friends[key(self.UserId, otherId)] == true
        end
        table.insert(w.roster, p)
        return p
    end
    function w.remove(p)
        -- PlayerRemoving fires while the leaver is STILL in GetPlayers(), which
        -- is the whole reason the module snapshots its roster synchronously.
        Players.PlayerRemoving:Fire(p)
        for index, other in ipairs(w.roster) do
            if other == p then table.remove(w.roster, index) break end
        end
        p.Parent = nil
    end
    function w.makeFriends(a, b) w.friends[key(a.UserId, b.UserId)] = true end
    function w.count(p) return p:GetAttribute('FriendBoostFriends') end
    function w.percent(p) return p:GetAttribute('FriendBoostPercent') end
    w.Players = Players

    local ReplicatedStorage = newInstance('ReplicatedStorage', 'ReplicatedStorage')
    local configModule = newInstance('ModuleScript', 'ZyntraConfig')
    configModule.Parent = ReplicatedStorage
    local services = {Players = Players, ReplicatedStorage = ReplicatedStorage}
    local game = {GetService = function(_, name) return assert(services[name], name) end}
    local task = {spawn = function(fn, ...) fn(...) end, wait = function() end}
    local function require(module)
        assert(module.Name == 'ZyntraConfig', 'the module requires only ZyntraConfig')
        return ZyntraConfig
    end
    w.FriendBoost = (function()
'''

MODULE_TAIL = r'''
    end)()
    return w
end

do -- 0 friends: everybody present, nobody related
    local w = server()
    local a, b, c = w.add('A', 1), w.add('B', 2), w.add('C', 3)
    w.FriendBoost.Start()
    for _, p in ipairs({a, b, c}) do
        equal(w.count(p), 0, 'a stranger counts no friends')
        equal(w.percent(p), 0, 'and earns no boost')
    end
end

do -- 1 friend, and the boost is the config percent
    local w = server()
    local a, b, c = w.add('A', 1), w.add('B', 2), w.add('C', 3)
    w.makeFriends(a, b)
    w.FriendBoost.Start()
    equal(w.count(a), 1, 'one friend on the server counts once')
    equal(w.percent(a), PERCENT, 'one friend is +10%')
    equal(w.count(b), 1, 'friendship is symmetric')
    equal(w.count(c), 0, 'an unrelated player is unaffected')
end

do -- 3 friends is additive and uncapped, and the player never counts themselves
    local w = server()
    local a = w.add('A', 1)
    local others = {w.add('B', 2), w.add('C', 3), w.add('D', 4), w.add('E', 5)}
    for index = 1, 3 do w.makeFriends(a, others[index]) end
    w.FriendBoost.Start()
    equal(w.count(a), 3, 'three friends count three')
    equal(w.percent(a), 3 * PERCENT, 'three friends is +30%')
    equal(w.count(others[4]), 0, 'the fifth player is nobody\'s friend')
end

do -- the unordered pair cache: A about B and B about A is ONE web call
    local w = server()
    local a, b = w.add('A', 1), w.add('B', 2)
    w.makeFriends(a, b)
    w.FriendBoost.Start()
    equal(w.lookups, 1, 'a pair is resolved once for both directions')
    w.add('C', 3)
    w.Players.PlayerAdded:Fire()
    equal(w.lookups, 3, 'a join resolves only the two NEW pairs')
end

do -- join and leave both republish
    local w = server()
    local a, b = w.add('A', 1), w.add('B', 2)
    w.makeFriends(a, b)
    w.FriendBoost.Start()
    equal(w.count(a), 1, 'a friend is counted at start')
    local c = w.add('C', 3)
    w.makeFriends(a, c)
    w.Players.PlayerAdded:Fire(c)
    equal(w.count(a), 2, 'a joining friend raises the count')
    equal(w.percent(a), 2 * PERCENT, 'and the published percent')
    w.remove(c)
    equal(w.count(a), 1, 'a leaving friend lowers it again')
    equal(w.percent(a), PERCENT, 'and the percent follows')
    w.remove(b)
    equal(w.count(a), 0, 'the last friend leaving clears the boost')
end

do -- a failed lookup counts 0 NOW, is not cached, and resolves on the next pass
    local w = server()
    local a, b = w.add('A', 1), w.add('B', 2)
    w.makeFriends(a, b)
    w.failing[w.key(1, 2)] = true
    w.FriendBoost.Start()
    equal(w.count(a), 0, 'a throttled lookup counts as no friend for this pass')
    equal(w.count(b), 0, 'for both sides')
    equal(w.FriendBoost.CountRoundFriends(a, {a, b}), 0,
        'and a failed lookup never pays a boost')
    local before = w.lookups
    w.failing[w.key(1, 2)] = false
    w.Players.PlayerAdded:Fire()
    check(w.lookups > before, 'the failure was NOT cached; the next pass retries it')
    equal(w.count(a), 1, 'and a definitive answer republishes the boost')
    local settled = w.lookups
    w.Players.PlayerAdded:Fire()
    equal(w.lookups, settled, 'a definitive answer IS cached; no second web call')
end

do -- CountRoundFriends: the ROSTER decides, not the server population
    local w = server()
    local a, b, c = w.add('A', 1), w.add('B', 2), w.add('C', 3)
    w.makeFriends(a, b)
    w.makeFriends(a, c)
    w.FriendBoost.Start()
    equal(w.count(a), 2, 'both friends are on the server')
    local before = w.lookups
    equal(w.FriendBoost.CountRoundFriends(a, {a, b}), 1,
        'a friend on the server but NOT in the round pays nothing')
    equal(w.FriendBoost.CountRoundFriends(a, {a}), 0, 'a solo round pays nothing')
    equal(w.FriendBoost.CountRoundFriends(a, {a, b, c}), 2, 'both in the round pay 2')
    equal(w.FriendBoost.CountRoundFriends(a, {b, b, c, c}), 2,
        'the same friend listed twice counts once')
    equal(w.FriendBoost.CountRoundFriends(a, {a, a, b}), 1, 'and the player never counts themselves')
    equal(w.lookups, before, 'the payout count reads the cache only: no web call, so no yield')
    equal(w.FriendBoost.CountRoundFriends(a, nil), 0, 'a missing roster pays nothing')
    equal(w.FriendBoost.CountRoundFriends(nil, {a, b}), 0, 'a missing player pays nothing')
end

do -- PrimeRoster warms exactly the pairs of a launching party
    local w = server()
    local a, b, c = w.add('A', 1), w.add('B', 2), w.add('C', 3)
    w.makeFriends(a, b)
    equal(w.FriendBoost.CountRoundFriends(a, {a, b}), 0, 'a cold cache pays nothing')
    w.FriendBoost.PrimeRoster({a, b, c})
    equal(w.lookups, 3, 'a party of three resolves three pairs')
    equal(w.FriendBoost.CountRoundFriends(a, {a, b, c}), 1, 'and the payout is ready at completion')
    w.FriendBoost.PrimeRoster({a, b, c})
    equal(w.lookups, 3, 'a second prime costs nothing')
    w.FriendBoost.PrimeRoster(nil)
    equal(w.lookups, 3, 'a missing roster is ignored')
end

'''

PAYOUT_TESTS = r'''

check(string.find(NEW_PROFILE, 'FriendBoostTenths = 0', 1, true) ~= nil,
    'a new profile starts with no unpaid remainder')
check(string.find(SNAPSHOT, 'FriendBoostTenths = data.FriendBoostTenths', 1, true) ~= nil,
    'the remainder is in the snapshot pushed to the client')

do -- the real normalisation lines, run over what a DataStore can actually hold
    for _, case in ipairs({
        {nil, 0}, {0, 0}, {5, 5}, {9, 9}, {10, 0}, {-1, 0}, {999, 0},
        {'4', 4}, {'nonsense', 0}, {4.7, 4}, {0 / 0, 0}, {math.huge, 0},
    }) do
        local data = {FriendBoostTenths = case[1]}
        normalizeTenths(data)
        equal(data.FriendBoostTenths, case[2],
            'saved remainder ' .. tostring(case[1]) .. ' normalises')
    end
end

local function completions(friendCount, clears)
    local data = {Tokens = 0, CompletedLevels = 0, LevelsCleared = {}, FriendBoostTenths = 0}
    local messages = {}
    local w = payoutWorld(data, messages)
    for _ = 1, clears do w.fire(1, friendCount) end
    return data, messages
end

do -- no friends: the payout and its wording are exactly what shipped
    local data, messages = completions(0, 3)
    equal(data.Tokens, 3 * BASE, 'a solo clear still pays the base 2 tokens')
    equal(data.FriendBoostTenths, 0, 'and accrues no remainder')
    equal(data.CompletedLevels, 3, 'every clear is still counted')
    equal(data.LevelsCleared['1'], true, 'and the level is recorded')
    equal(messages[1], '+2 Zyntra Research Tokens for completing the level.',
        'the no-friends message is unchanged')
    missing(messages[1], 'Friend Boost', 'and says nothing about a boost')
end

do -- ONE friend: 0.2 of a token per clear, paid whole on the fifth
    local data, messages = completions(1, 5)
    equal(data.Tokens, 5 * BASE + 1, 'five clears with one friend pay one extra token')
    equal(data.FriendBoostTenths, 0, 'and the remainder is spent exactly')
    equal(messages[1], '+2 Zyntra Research Tokens for completing the level (Friend Boost +10%).',
        'the boost is named on every clear, even before it pays')
    equal(messages[5], '+3 Zyntra Research Tokens for completing the level (Friend Boost +10%).',
        'and the fifth clear announces the whole token it paid')
    for clear = 1, 4 do
        local partial = select(1, completions(1, clear))
        equal(partial.Tokens, clear * BASE, 'clear ' .. clear .. ' pays no bonus yet')
        equal(partial.FriendBoostTenths, clear * 2, 'but carries ' .. (clear * 2) .. ' tenths')
    end
end

do -- the whole ladder: N friends over 5 clears is exactly N*10% of the base
    for _, friends in ipairs({0, 1, 2, 3, 5, 7}) do
        local data = select(1, completions(friends, 5))
        local basePaid = 5 * BASE
        local expected = math.floor(basePaid * friends * PERCENT / 100)
        equal(data.Tokens, basePaid + expected,
            friends .. ' friends over five clears pay +' .. friends * PERCENT .. '%')
        equal(data.FriendBoostTenths, (basePaid * friends * PERCENT / 10) % 10,
            friends .. ' friends leave the right remainder')
    end
end

do -- five friends is +100%: a whole extra token EVERY clear, no remainder ever
    local data = select(1, completions(5, 4))
    equal(data.Tokens, 4 * (BASE + 1), 'five friends double every completion')
    equal(data.FriendBoostTenths, 0, 'with nothing left over')
end

do -- the remainder survives a session: it is read back off the profile
    local data = {Tokens = 0, CompletedLevels = 0, LevelsCleared = {}, FriendBoostTenths = 8}
    local w = payoutWorld(data, {})
    w.fire(1, 1)
    equal(data.Tokens, BASE + 1, 'a carried 0.8 plus 0.2 pays the whole token at once')
    equal(data.FriendBoostTenths, 0, 'and resets the remainder')
end

do -- a repeated completion is just another completion; nothing is idempotent here
    local data, messages = completions(1, 10)
    equal(data.CompletedLevels, 10, 'ten fires are ten completions')
    equal(data.Tokens, 10 * BASE + 2, 'and pay ten completions worth')
    equal(#messages, 10, 'each one is announced')
    -- The guard against firing twice for ONE clear lives in GameManager, read below.
end

do -- an untrusted or broken friend count can never poison a balance
    for _, bad in ipairs({{nil, 0}, {-1, 0}, {-5, 0}, {1.7, 1}, {0 / 0, 0},
        {math.huge, 0}, {-math.huge, 0}, {1e9, 0}, {'2', 2}}) do
        local data = {Tokens = 0, CompletedLevels = 0, LevelsCleared = {}, FriendBoostTenths = 0}
        local w = payoutWorld(data, {})
        w.fire(1, bad[1])
        local expectedTenths = BASE * bad[2] * PERCENT / 10
        equal(data.Tokens, BASE + math.floor(expectedTenths / 10),
            'friend count ' .. tostring(bad[1]) .. ' pays a finite, sane amount')
        equal(data.FriendBoostTenths, expectedTenths % 10,
            'friend count ' .. tostring(bad[1]) .. ' leaves a sane remainder')
    end
end

do -- the handler still refuses what it always refused
    local data = {Tokens = 0, CompletedLevels = 0, LevelsCleared = {}, FriendBoostTenths = 0}
    local w = payoutWorld(data, {})
    w.fireRaw(nil, 1, 1)
    w.fireRaw(w.stranger, 1, 1)
    equal(data.Tokens, 0, 'no player and no session pay nothing')
    w.fire(9, 3)
    equal(data.LevelsCleared['9'], nil, 'an out-of-range level is not recorded')
    equal(data.Tokens, BASE, 'but the clear itself still pays, boosted or not')
    equal(#w.badges, 0, 'and awards no badge')
    w.fire(2, 0)
    equal(w.badges[1], 'FirstClearLevel2', 'a tracked level still awards its badge')
end

-- GameManager's own once-per-escapee guard, read from the shipping source.
check(string.find(WIN_LOOP, 'CountRoundFriends(participant, participants)', 1, true) ~= nil,
    'GameManager counts the boost from the round roster at the win')
check(string.find(WIN_LOOP, 'if participant.Parent and participant:GetAttribute("Escaped") == true then',
    1, true) ~= nil, 'and fires once per escaped participant, inside one pass over the roster')

'''

CLIENT_HARNESS = r'''

local POINTER = {SafeLeft = 0, SafeTop = 36, SafeRight = 1280, SafeBottom = 720,
    IsTouch = false, Narrow = false, OriginX = 0, OriginY = 36}
local PHONE = {SafeLeft = 0, SafeTop = 36, SafeRight = 390, SafeBottom = 810,
    IsTouch = true, Narrow = true, OriginX = 0, OriginY = 36}

local function clientContext(layout, invite)
    local ctx = {Layout = table.clone(layout or POINTER), Invites = 0, Registered = {},
        CanInvite = invite, InviteCalls = 0, Waits = 0}
    ctx.Player = newInstance('Player', 'Player')
    ctx.PlayerGui = newInstance('PlayerGui', 'PlayerGui')
    ctx.PlayerGui.Parent = ctx.Player

    local storage = newInstance('ReplicatedStorage', 'ReplicatedStorage')
    for _, name in ipairs({'UIDevice', 'UIStyle', 'ZyntraConfig'}) do
        local module = newInstance('ModuleScript', name)
        module.Parent = storage
    end
    ctx.Social = newInstance('SocialService', 'SocialService')
    function ctx.Social:CanSendGameInviteAsync(who)
        ctx.InviteCalls += 1
        check(who == ctx.Player, 'the invite check asks about the local player')
        if ctx.CanInvite == 'error' then error('SocialService unavailable') end
        return ctx.CanInvite
    end
    function ctx.Social:PromptGameInvite(who)
        check(who == ctx.Player, 'the invite prompt is for the local player')
        ctx.Invites += 1
    end
    local services = {Players = {LocalPlayer = ctx.Player}, ReplicatedStorage = storage,
        SocialService = ctx.Social}
    ctx.Game = {GetService = function(_, name) return assert(services[name], name) end}
    ctx.Task = {spawn = function(fn, ...) fn(...) end,
        wait = function() ctx.Waits += 1 end}
    return ctx
end

local function boot(ctx)
    local game, task = ctx.Game, ctx.Task
    local UIStyleModule = (function()
'''

UISTYLE_TAIL = r'''
    end)()
    local MODALS = {'ZyntraStoreOpen', 'DevPhoneOpen', 'ZyntraReentryOpen', 'QueueModalOpen',
        'LuckyWheelOpen', 'DailyRewardsOpen'}
    local UIDeviceFake = {Changed = signal()}
    function UIDeviceFake.Layout() return ctx.Layout end
    function UIDeviceFake.LocalOffset(_, x, y)
        return x - ctx.Layout.OriginX, y - ctx.Layout.OriginY
    end
    -- The published TopRightPanel contract: the right edge is ALWAYS the safe
    -- right edge less the margin, and what gives is height.
    function UIDeviceFake.TopRightPanel(desiredWidth, desiredHeight)
        local L = ctx.Layout
        local margin = L.IsTouch and 8 or 18
        local right, top = L.SafeRight - margin, L.SafeTop + margin
        local width = math.min(desiredWidth, math.max(0, right - (L.SafeLeft + margin)))
        local limit = (L.ControlsTop or L.SafeBottom) - (L.IsTouch and 8 or margin)
        local height = math.min(desiredHeight, math.max(0, limit - top))
        return {Left = right - width, Top = top, Right = right, Bottom = top + height,
            Width = width, Height = height, UsesScreenEdge = true}
    end
    function UIDeviceFake.RegisterControlRect(key, element)
        table.insert(ctx.Registered, {Key = key, Element = element})
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
        if module.Name == 'ZyntraConfig' then return ZyntraConfig end
        error('unexpected require: ' .. tostring(module.Name))
    end
'''

CLIENT_TESTS = r'''
end

local function startClient(layout, invite, friends)
    local ctx = clientContext(layout, invite == nil and true or invite)
    if friends then
        ctx.Player:SetAttribute('FriendBoostFriends', friends)
        ctx.Player:SetAttribute('FriendBoostPercent', friends * PERCENT)
    end
    boot(ctx)
    ctx.Gui = descendant(ctx.PlayerGui, 'FriendBoostGui')
    ctx.Chip = descendant(ctx.Gui, 'FriendBoostChip')
    ctx.Boost = descendant(ctx.Chip, 'BoostLabel')
    ctx.Detail = descendant(ctx.Chip, 'FriendsLabel')
    ctx.Invite = descendant(ctx.Chip, 'InviteButton')
    return ctx
end

do -- the gui's own identity, fixed by the contract
    local ctx = startClient(POINTER)
    equal(ctx.Gui.DisplayOrder, 60, 'the chip gui sits at DisplayOrder 60')
    equal(ctx.Gui.ResetOnSpawn, false, 'and survives a respawn')
    equal(#ctx.Registered, 1, 'the chip registers exactly one control rect')
    equal(ctx.Registered[1].Key, 'FriendBoost', 'under the stated key')
    equal(ctx.Registered[1].Element, ctx.Chip, 'and it is the chip itself')
end

do -- the three copy states
    local zero = startClient(POINTER, true, 0)
    equal(zero.Boost.Text, 'FRIEND BOOST +0%', 'no friends still names the boost')
    equal(zero.Detail.Text, 'INVITE FRIENDS TO EARN +10% PER FRIEND',
        'and explains how to earn it')
    local one = startClient(POINTER, true, 1)
    equal(one.Boost.Text, 'FRIEND BOOST +10%', 'one friend is +10%')
    equal(one.Detail.Text, '1 FRIEND ON THIS SERVER', 'and reads in the singular')
    local two = startClient(POINTER, true, 2)
    equal(two.Boost.Text, 'FRIEND BOOST +20%', 'two friends is +20%')
    equal(two.Detail.Text, '2 FRIENDS ON THIS SERVER', 'and reads in the plural')
end

do -- a chip with no attributes at all still draws something sane
    local ctx = startClient(POINTER)
    equal(ctx.Boost.Text, 'FRIEND BOOST +0%', 'a missing attribute reads as zero')
    equal(ctx.Detail.Text, 'INVITE FRIENDS TO EARN +10% PER FRIEND', 'with the invite copy')
    ctx.Player:SetAttribute('FriendBoostFriends', 3)
    ctx.Player:SetAttribute('FriendBoostPercent', 30)
    equal(ctx.Boost.Text, 'FRIEND BOOST +30%', 'a published attribute repaints the chip live')
    equal(ctx.Detail.Text, '3 FRIENDS ON THIS SERVER', 'and its friend line')
end

do -- the client never trusts a hostile attribute into nonsense
    local ctx = startClient(POINTER)
    for _, bad in ipairs({-4, 0 / 0, 1.6}) do
        ctx.Player:SetAttribute('FriendBoostFriends', bad)
        ctx.Player:SetAttribute('FriendBoostPercent', bad)
        check(string.find(ctx.Boost.Text, '^FRIEND BOOST %+%d+%%$') ~= nil,
            'a rewritten attribute still renders a plain percentage: ' .. ctx.Boost.Text)
    end
end

do -- lobby only, and out of the way of anything that owns the screen
    local ctx = startClient(POINTER, true, 2)
    equal(ctx.Chip.Visible, true, 'the chip is up in the lobby')
    ctx.Player:SetAttribute('InRound', true)
    equal(ctx.Chip.Visible, false, 'and stands down in a round')
    ctx.Player:SetAttribute('InRound', false)
    equal(ctx.Chip.Visible, true, 'and comes back in the lobby')
    for _, modal in ipairs({'LuckyWheelOpen', 'DailyRewardsOpen', 'ZyntraStoreOpen',
        'QueueModalOpen', 'DevPhoneOpen', 'ZyntraReentryOpen'}) do
        ctx.Player:SetAttribute(modal, true)
        equal(ctx.Chip.Visible, false, 'the chip yields to ' .. modal)
        ctx.Player:SetAttribute(modal, false)
        equal(ctx.Chip.Visible, true, 'and returns when ' .. modal .. ' closes')
    end
end

do -- invite gating: definitive yes, definitive no, and a throwing service
    local yes = startClient(POINTER, true, 0)
    equal(yes.Invite.Visible, true, 'a definitive yes shows the invite button')
    equal(yes.Invites, 0, 'and nothing is invited automatically')
    yes.Invite.Activated:Fire()
    equal(yes.Invites, 1, 'pressing it opens Roblox own invite prompt')
    yes.Invite.Activated:Fire()
    equal(yes.Invites, 2, 'and it can be pressed again')

    local no = startClient(POINTER, false, 0)
    equal(no.Invite.Visible, false, 'a definitive no hides the button')
    no.Invite.Activated:Fire()
    equal(no.Invites, 0, 'and a stray activation cannot prompt anyway')

    local broken = startClient(POINTER, 'error', 0)
    equal(broken.Invite.Visible, false, 'a throwing service hides the button')
    equal(broken.InviteCalls, 3, 'after retrying, because a throw is not a no')
    equal(broken.Waits, 2, 'with a wait between the attempts')
    broken.Invite.Activated:Fire()
    equal(broken.Invites, 0, 'and it still cannot prompt')
end

do -- geometry: the safe top-right corner, tappable, legible, on both device kinds
    for _, case in ipairs({{POINTER, 260, 30}, {PHONE, 220, 44}}) do
        local layout, width, tap = case[1], case[2], case[3]
        local ctx = startClient(layout, true, 1)
        local margin = layout.IsTouch and 8 or 18
        equal(ctx.Chip.Size.OX, width, 'the chip is ' .. width .. ' wide on this device')
        equal(ctx.Chip.Position.OX, layout.SafeRight - margin - width - layout.OriginX,
            'its right edge is the safe right edge')
        equal(ctx.Chip.Position.OY, layout.SafeTop + margin - layout.OriginY,
            'and it hangs from the top of the safe area')
        equal(ctx.Invite.Size.OY, tap, 'the invite target is ' .. tap .. ' tall')
        check(ctx.Chip.Size.OY >= ctx.Invite.Position.OY + tap + 6,
            'and the chip is tall enough to hold it')
        for _, label in ipairs({ctx.Boost, ctx.Detail, ctx.Invite}) do
            check(label.TextSize >= 11, 'no text below 11px: ' .. label.Name)
            check(label.TextScaled ~= true, label.Name .. ' states its own size')
        end
        check(ctx.Chip.Position.OX >= layout.SafeLeft, 'the chip stays inside the safe area')
    end
end

do -- the chip is content-sized: it must NOT shrink to the room above the controls
    local ctx = clientContext(PHONE, true)
    -- A cluster measured at the very top -- which is what registering the chip
    -- itself would look like to TopRightPanel -- must not collapse the chip.
    ctx.Layout.ControlsTop = ctx.Layout.SafeTop + 20
    boot(ctx)
    local chip = descendant(ctx.PlayerGui, 'FriendBoostChip')
    check(chip.Size.OY >= 100, 'the chip keeps its content height, so it cannot oscillate')
end

do -- a layout change relays it out without losing the copy
    local ctx = startClient(POINTER, true, 2)
    ctx.Layout = table.clone(PHONE)
    ctx.UIDevice.Changed:Fire()
    equal(ctx.Chip.Size.OX, 220, 'a rotation re-lays the chip')
    equal(ctx.Detail.Text, '2 FRIENDS ON THIS SERVER', 'and keeps what it was saying')
end

do -- nothing about the chip reaches the server
    local ctx = startClient(POINTER, true, 2)
    missing(CLIENT_SOURCE, 'FireServer', 'the chip fires no remote')
    missing(CLIENT_SOURCE, 'InvokeServer', 'and invokes none')
    missing(CLIENT_SOURCE, 'SetAttribute', 'and publishes no attribute of its own')
    equal(ctx.Invites, 0, 'and invites nobody without a press')
end

print(('friend boost: %d checks passed (module, payout and chip under offline Luau;'
    .. ' real friendships, SocialService and device metrics not exercised)'):format(checks))
'''


def main():
    binary = os.environ.get("LUAU_BIN") or shutil.which("luau")
    if not binary:
        raise SystemExit("Set LUAU_BIN or install luau; no tests were executed.")

    handler = section(MONETIZATION, "levelCompletedEvent.Event:Connect(function(player, level, friendCount)",
                      "MarketplaceService.PromptGamePassPurchaseFinished")
    tenths = section(MONETIZATION, "\t-- FRIEND_BOOST_20260916. The unpaid fraction",
                     "\t-- Both sets are rebuilt")
    new_profile = section(MONETIZATION, "local function newProfile()", "local function normalizeProfile")
    snapshot = section(MONETIZATION, "local function publicProfile(data, player)", "\treturn result")
    win_loop = section(
        (ROOT / "ServerScriptService/GameManager.Script.lua").read_text(encoding="utf-8"),
        " for _, participant in ipairs(participants) do", " if result == \"win\" then\n  --")

    def literal(text):
        assert "]==]" not in text
        return "[==[\n" + text + "]==]"

    payout = "\n".join([
        "local NEW_PROFILE = " + literal(new_profile),
        "local SNAPSHOT = " + literal(snapshot),
        "local WIN_LOOP = " + literal(win_loop),
        "local CLIENT_SOURCE = " + literal(CLIENT),
        "local function normalizeTenths(data)",
        tenths,
        "end",
        # The real handler, wired to a fake mutate that normalises the profile on
        # the way in exactly as the production mutate does.
        "local function payoutWorld(data, messages)",
        "    local w = {badges = {}}",
        "    local player = newInstance('Player', 'Escapee')",
        "    w.stranger = newInstance('Player', 'Stranger')",
        "    local sessions = {[player] = {data = data, persistent = true}}",
        "    local Config = ZyntraConfig",
        "    local levelCompletedEvent = {Event = signal()}",
        "    local function mutate(who, transform)",
        "        local profile = sessions[who].data",
        "        normalizeTenths(profile)",
        "        local ok, message = transform(profile)",
        "        check(ok == true, 'the completion transform always commits')",
        "        table.insert(messages, message)",
        "    end",
        "    local function awardBadge(_, badge) table.insert(w.badges, badge) end",
        handler,
        "    function w.fire(level, friends) levelCompletedEvent.Event:Fire(player, level, friends) end",
        "    function w.fireRaw(...) levelCompletedEvent.Event:Fire(...) end",
        "    return w",
        "end",
    ])

    source = "".join([
        HARNESS, CONFIG, CONFIG_TAIL, MODULE, MODULE_TAIL,
        payout, "\n", PAYOUT_TESTS,
        CLIENT_HARNESS, UISTYLE, UISTYLE_TAIL, CLIENT, CLIENT_TESTS,
    ])
    with tempfile.TemporaryDirectory(prefix="friend-boost-") as directory:
        path = Path(directory) / "friend_boost.luau"
        path.write_text(source, encoding="utf-8")
        subprocess.run([binary, str(path)], check=True, timeout=60)


if __name__ == "__main__":
    main()
