"""Exercise the whole Friend Boost feature offline: module, payout and chip.

FRIEND_BOOST_20260916 (owner brief section 4). Three real sources run under one
fake DataModel, none of them copied or paraphrased:

  * ServerScriptService/FriendBoost.ModuleScript.lua runs ENTIRELY, against fake
    Players whose IsFriendsWithAsync can throw or yield during roster changes.
  * The completion payout is EXTRACTED from ZyntraMonetization by string
    markers -- the levelCompletedEvent handler, the FriendBoostTenths
    normalisation lines and the achievementApi it unlocks badges through -- so
    the arithmetic under test is the shipping one.
  * StarterPlayerScripts/Friend Boost Client.LocalScript.lua runs entirely, with
    the real UIStyle, ShopBinder and ZyntraConfig modules and a faked
    UIDevice/SocialService and token pill (PlayerGui.ZyntraLobbyPillL4).

The real ReplicatedStorage/ZyntraConfig is loaded once and shared by all three,
so PercentPerFriend is read rather than restated.

What this CANNOT see, and what a Studio pass is for: real Roblox friendships and
their throttling, whether SocialService answers at all on a given platform, font
metrics, and where the chip actually lands on a real device. Set LUAU_BIN, or
put luau on PATH. FRIEND_BOOST_MONETIZATION_SOURCE can select a freshly audited
Studio source file for the payout partition without overwriting the repository.
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
BINDER = (ROOT / "ReplicatedStorage/ZyntraShopUI/ShopBinder.ModuleScript.lua").read_text(encoding="utf-8")
MONETIZATION_PATH = Path(os.environ.get("FRIEND_BOOST_MONETIZATION_SOURCE") or
                         ROOT / "ServerScriptService/ZyntraMonetization.Script.lua")
MONETIZATION = MONETIZATION_PATH.read_text(encoding="utf-8")
CHALLENGES = (ROOT / "ReplicatedStorage/ZyntraChallenges.ModuleScript.lua").read_text(encoding="utf-8")


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
        if not cache[key] then cache[key] = {Kind = kind, Key = key, ToHex = function() return key end} end
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
local Font = {new = function(family, weight) return {Kind = 'Font', Family = family, Weight = weight} end}
local enumItems = {}
local Enum = setmetatable({}, {__index = function(_, group)
    return setmetatable({}, {__index = function(_, item)
        local key = group .. '.' .. item
        if not enumItems[key] then enumItems[key] = {Name = item, Group = group, Key = key} end
        return enumItems[key]
    end})
end})

-- instances
local SIGNALS = {Activated = true, MouseEnter = true, MouseLeave = true, Event = true, ChildAdded = true}
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
            if key == 'Parent' then
                -- Reparenting REMOVES from the old parent, the way the engine
                -- does, so FindFirstChild on the old parent stops finding it.
                local old = fields.Parent
                if old then
                    for index, child in ipairs(old.Children) do
                        if child == proxy then table.remove(old.Children, index) break end
                    end
                end
                if value ~= nil then table.insert(value.Children, proxy) end
            end
            fields[key] = value
            if key == 'Parent' and value ~= nil then value.ChildAdded:Fire(proxy) end
            -- GetPropertyChangedSignal: every write fires, the way a real change does.
            local watcher = fields.Watchers['prop:' .. key]
            if watcher then watcher:Fire() end
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
function methods:IsDescendantOf(ancestor)
    local node = self.Parent
    while node do
        if node == ancestor then return true end
        node = node.Parent
    end
    return false
end
function methods:Watcher(key)
    if not self.Watchers[key] then self.Watchers[key] = signal() end
    return self.Watchers[key]
end
function methods:SetAttribute(key, value)
    self.Attributes[key] = value
    if self.Watchers[key] then self.Watchers[key]:Fire() end
end
function methods:GetAttributeChangedSignal(key) return self:Watcher(key) end
function methods:GetPropertyChangedSignal(property) return self:Watcher('prop:' .. property) end
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
    local w = {friends = {}, failing = {}, failuresRemaining = {}, lookups = 0,
        asyncLookups = 0, legacyLookups = 0, lookupPairs = {}, roster = {},
        attributeWrites = {}, now = 0, timers = {}, waiting = {}}
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
        local function lookup(self, otherId)
            w.lookups += 1
            check(otherId ~= self.UserId, 'a player is never asked about themselves')
            local pair = key(self.UserId, otherId)
            table.insert(w.lookupPairs, pair)
            if w.blockNextLookup then
                w.blockNextLookup = false
                coroutine.yield('friendship lookup')
            end
            if w.failing[pair] then error('HTTP 429 Too Many Requests') end
            if (w.failuresRemaining[pair] or 0) > 0 then
                w.failuresRemaining[pair] -= 1
                error('temporary friendship outage')
            end
            return w.friends[pair] == true
        end
        function p:IsFriendsWithAsync(otherId)
            w.asyncLookups += 1
            return lookup(self, otherId)
        end
        -- Keep the legacy method callable so an old-source regression fails on
        -- missing recovery, not merely because the harness removed its API.
        function p:IsFriendsWith(otherId)
            w.legacyLookups += 1
            return lookup(self, otherId)
        end
        function p:SetAttribute(name, value)
            table.insert(w.attributeWrites, {Player = self, Name = name, Value = value})
            methods.SetAttribute(self, name, value)
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
    local function resume(thread, ...)
        local ok, reason = coroutine.resume(thread, ...)
        assert(ok, tostring(reason))
        if coroutine.status(thread) == 'suspended' then
            equal(reason, 'friendship lookup', 'only the scripted API can suspend a worker')
            table.insert(w.waiting, thread)
        end
    end
    local task = {spawn = function(fn, ...)
        local thread = coroutine.create(fn)
        resume(thread, ...)
        return thread
    end, delay = function(seconds, fn)
        check(seconds > 0, 'retries wait rather than busy-loop')
        table.insert(w.timers, {At = w.now + seconds, Callback = fn})
    end, wait = function() error('the payout count must never wait') end}
    function w.resumeLookup()
        local thread = table.remove(w.waiting, 1)
        check(thread ~= nil, 'a suspended friendship lookup exists')
        resume(thread)
    end
    function w.advance(seconds)
        w.now += seconds
        while true do
            local due
            for index, timer in ipairs(w.timers) do
                if timer.At <= w.now then due = index break end
            end
            if not due then break end
            table.remove(w.timers, due).Callback()
        end
    end
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

do -- An idle lobby recovers +0% without a join, leave, rejoin or round launch.
    local w = server()
    local a, b = w.add('A', 1), w.add('B', 2)
    w.makeFriends(a, b)
    w.failing[w.key(1, 2)] = true
    w.FriendBoost.Start()
    equal(w.count(a), 0, 'an outage starts with the conservative zero count')
    equal(w.count(b), 0, 'both sides start conservatively')
    equal(w.percent(a), 0, 'the visible chip starts at +0%')
    local attempts = w.lookups
    w.failing[w.key(1, 2)] = false
    w.advance(4)
    equal(w.lookups, attempts, 'background recovery waits before another API call')
    w.advance(1)
    equal(w.count(a), 1, 'the idle lobby recovers the friend without a roster event')
    equal(w.count(b), 1, 'the recovered answer is symmetric')
    equal(w.percent(a), PERCENT, 'the chip recovers to +10%')
    equal(w.percent(b), PERCENT, 'both chips receive the repaired percentage')
    equal(w.lookups, attempts + 1, 'one retry resolves the unordered pair')
    equal(w.asyncLookups, w.lookups, 'the current async friendship API is used')
    equal(w.legacyLookups, 0, 'the deprecated API is not used')
    equal(#w.timers, 0, 'a definitive answer stops background retries')
end

do -- A one-off failure cannot leave A at zero while B sees a cached friendship.
    local w = server()
    local a, b = w.add('A', 1), w.add('B', 2)
    w.makeFriends(a, b)
    w.failuresRemaining[w.key(1, 2)] = 1
    w.FriendBoost.Start()
    equal(w.lookups, 1, 'a failed pair is attempted once in the first pass')
    equal(w.count(a), 0, 'the first incomplete answer never invents a boost')
    equal(w.count(b), 0, 'the first incomplete answer is consistent on both sides')
    w.advance(5)
    equal(w.count(a), 1, 'the earlier failed side receives the recovered cache answer')
    equal(w.count(b), 1, 'the second side receives the same recovered cache answer')
    equal(w.percent(a), PERCENT, 'a transient error cannot strand the first chip at zero')
    equal(w.lookups, 2, 'one delayed retry completes this recovery')
end

do -- Persistent failures use one delayed timer, and a departure cancels demand.
    local w = server()
    local a, b = w.add('A', 1), w.add('B', 2)
    w.makeFriends(a, b)
    w.failing[w.key(1, 2)] = true
    w.FriendBoost.Start()
    w.FriendBoost.Start()
    equal(w.lookups, 1, 'Start is idempotent, including an unresolved pair')
    equal(#w.timers, 1, 'one timer covers an unresolved pass')
    w.advance(5)
    equal(w.lookups, 2, 'a persistent outage retries once per interval')
    equal(#w.timers, 1, 'the persistent outage does not multiply timers')
    equal(w.FriendBoost.CountRoundFriends(a, {a, b}), 0, 'an unresolved pair never pays')
    w.remove(b)
    equal(w.count(a), 0, 'leaving during an outage keeps the current lobby at zero')
    local attempts = w.lookups
    w.advance(5)
    equal(w.lookups, attempts, 'the timer snapshots the current roster and skips the leaver')
    equal(#w.timers, 0, 'there is no remaining pair to retry')
end

do -- A successful launch prime repairs previously published zero attributes.
    local w = server()
    local a, b = w.add('A', 1), w.add('B', 2)
    w.makeFriends(a, b)
    w.failing[w.key(1, 2)] = true
    w.FriendBoost.Start()
    equal(w.percent(a), 0, 'the earlier lobby lookup failed')
    w.failing[w.key(1, 2)] = false
    w.FriendBoost.PrimeRoster({a, b})
    equal(w.count(a), 1, 'priming republishes the first lobby count')
    equal(w.count(b), 1, 'priming republishes the second lobby count')
    equal(w.percent(a), PERCENT, 'priming repairs the displayed +0%')
    local attempts = w.lookups
    equal(w.FriendBoost.CountRoundFriends(a, {a, b}), 1, 'the real round roster gets its warmed count')
    equal(w.FriendBoost.CountRoundFriends(a, {a}), 0, 'a friend outside this round still pays nothing')
    equal(w.lookups, attempts, 'completion stays cache-only after recovery')
    w.advance(5)
    equal(w.lookups, attempts, 'an already scheduled timer cannot repeat a definitive lookup')
    equal(#w.timers, 0, 'the recovered prime leaves no retry loop')
end

do -- A suspended lookup is shared by concurrent prime/join/start work.
    local w = server()
    local a, b = w.add('A', 1), w.add('B', 2)
    w.makeFriends(a, b)
    w.blockNextLookup = true
    w.FriendBoost.Start()
    equal(#w.waiting, 1, 'the friendship RPC really suspended the worker')
    equal(w.lookups, 1, 'one pair is currently in flight')
    w.FriendBoost.PrimeRoster({a, b})
    w.FriendBoost.Start()
    equal(w.lookups, 1, 'a simultaneous prime/start does not duplicate the in-flight pair')
    local c = w.add('C', 3)
    w.makeFriends(a, c)
    w.Players.PlayerAdded:Fire(c)
    equal(w.lookups, 1, 'a join queues a fresh snapshot instead of a second worker')
    equal(w.FriendBoost.CountRoundFriends(a, {a, b}), 0, 'a completion does not wait for an in-flight answer')
    w.resumeLookup()
    equal(w.lookups, 3, 'the latest three-player roster resolves each unordered pair once')
    local seen = {}
    for _, pair in ipairs(w.lookupPairs) do
        check(not seen[pair], 'no prime/join pair was looked up twice: ' .. pair)
        seen[pair] = true
    end
    equal(w.count(a), 2, 'the latest joined roster is published')
    equal(w.count(b), 1, 'the first friend shares the repaired result')
    equal(w.count(c), 1, 'the joining friend receives their count')
    equal(#w.waiting, 0, 'the worker finishes its actual yield')
    equal(#w.timers, 0, 'all resolved pairs need no retry')
end

do -- A friend leaving during an RPC never commits a stale +10% snapshot.
    local w = server()
    local a, b = w.add('A', 1), w.add('B', 2)
    w.makeFriends(a, b)
    w.blockNextLookup = true
    w.FriendBoost.Start()
    w.remove(b)
    w.resumeLookup()
    equal(w.count(a), 0, 'the current remaining player has no lobby friends')
    equal(w.percent(a), 0, 'a departed friend cannot leave a displayed boost')
    equal(w.count(b), nil, 'the departed player is not written after the yield')
    for _, write in ipairs(w.attributeWrites) do
        if write.Name == 'FriendBoostFriends' then
            equal(write.Value, 0, 'even an intermediate commit excludes the departed friend')
            check(write.Player == a, 'only the current roster receives attributes')
        end
    end
    equal(w.lookups, 1, 'the departed pair is not resolved a second time')
    equal(#w.timers, 0, 'no departed pair needs background recovery')
end

do -- Coalesced failed prime/join work schedules only one retry for the current lobby.
    local w = server()
    local a, b = w.add('A', 1), w.add('B', 2)
    w.makeFriends(a, b)
    w.failing[w.key(1, 2)] = true
    w.blockNextLookup = true
    w.FriendBoost.Start()
    w.FriendBoost.PrimeRoster({a, b, a})
    w.Players.PlayerAdded:Fire()
    w.resumeLookup()
    equal(w.lookups, 1, 'the same failed pair is not retried inside one queued worker')
    equal(#w.timers, 1, 'all queued requests share one background timer')
    w.failing[w.key(1, 2)] = false
    w.advance(5)
    equal(w.count(a), 1, 'the coalesced failed pass recovers without a roster event')
    equal(w.count(b), 1, 'its symmetric attributes recover too')
    equal(#w.timers, 0, 'the shared timer stops on success')
end

'''

PAYOUT_TESTS = r'''

-- A loaded profile carries these fields once normalizeProfile has run.
local function freshProfile(tenths)
    return {Tokens = 0, CompletedLevels = 0, LevelsCleared = {}, FriendBoostTenths = tenths or 0,
        CompletionIds = {}, Records = {}, Achievements = {},
        Challenges = CHALLENGES_MODULE.NormalizeDone(nil, ZyntraConfig.Challenges)}
end

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
    local data = freshProfile()
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
    local data = freshProfile(8)
    local w = payoutWorld(data, {})
    w.fire(1, 1)
    equal(data.Tokens, BASE + 1, 'a carried 0.8 plus 0.2 pays the whole token at once')
    equal(data.FriendBoostTenths, 0, 'and resets the remainder')
end

do -- with no round id each fire gets a fresh GUID, so a repeat is just another completion
    local data, messages = completions(1, 10)
    equal(data.CompletedLevels, 10, 'ten fires are ten completions')
    equal(data.Tokens, 10 * BASE + 2, 'and pay ten completions worth')
    equal(#messages, 10, 'each one is announced')
    -- The guard against firing twice for ONE clear lives in GameManager, read below.
end

do -- an untrusted or broken friend count can never poison a balance
    for _, bad in ipairs({{nil, 0}, {-1, 0}, {-5, 0}, {1.7, 1}, {0 / 0, 0},
        {math.huge, 0}, {-math.huge, 0}, {1e9, 0}, {'2', 2}}) do
        local data = freshProfile()
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
    local data = freshProfile()
    local w = payoutWorld(data, {})
    w.fireRaw(nil, 1, 1)
    w.fireRaw(w.stranger, 1, 1)
    equal(data.Tokens, 0, 'no player and no session pay nothing')
    w.fire(9, 3, {Seconds = 60, Deaths = 0, Solo = true})
    equal(data.LevelsCleared['9'], nil, 'an out-of-range level is not recorded')
    equal(data.Tokens, BASE, 'but the clear itself still pays, boosted or not')
    equal(#w.badges, 0, 'and awards no badge')
    equal(#w.daily, 0, 'nor counts toward the daily Clear goal')
    equal(next(data.Records), nil, 'nor sets a record, even from a clean run')
    w.fire(2, 0)
    equal(w.badges[1], 'FirstClearLevel2', 'a tracked level still awards its badge')
    equal(w.daily[1], 'Clear', 'and counts toward the daily Clear goal')
end

do -- the saved LevelsCleared set is rebuilt over levels 1-4: Level 4 survives a save, nothing above it
    local data = {LevelsCleared = {['4'] = true, [3] = true, ['5'] = true, ['9'] = true, ['0'] = true}}
    normalizeLevels(data)
    equal(data.LevelsCleared['4'], true, 'a saved Level 4 clear survives normalisation')
    equal(data.LevelsCleared['3'], true, 'an old numeric key is re-saved as a string')
    for _, level in ipairs({'0', '5', '9'}) do
        equal(data.LevelsCleared[level], nil, 'level ' .. level .. ' is not a known clear')
    end
end

do -- LEVEL 4 (the cinema) is a tracked clear like 1-3 since 2026-10-02 (owner decision)
    local settings = ZyntraConfig.Challenges
    local goal = settings.TimeGoalSeconds['4']
    check(type(goal) == 'number', 'Level 4 has a time goal')
    local data, messages = freshProfile(), {}
    local w = payoutWorld(data, messages)
    w.fire(4, 0, {Seconds = goal - 30, Deaths = 0, Solo = true})
    equal(data.LevelsCleared['4'], true, 'a Level 4 clear is recorded in LevelsCleared')
    equal(#w.daily, 1, 'it counts toward daily research once')
    equal(w.daily[1], 'Clear', 'as the Clear goal')
    local record = data.Records[CHALLENGES_MODULE.Key(4, 'solo', 'clean')]
    equal(record and record.Best, goal - 30, 'the run sets a Level 4 solo clean record')
    equal(data.Challenges.NoDeath['4'], true, 'the Level 4 no-death challenge is completed')
    equal(data.Challenges.TimeGoal['4'], true, 'and the Level 4 time goal')
    equal(data.Tokens, BASE + settings.RewardTokens.NoDeath + settings.RewardTokens.TimeGoal,
        'the clear and both Level 4 challenges pay in the same write')
    contains(messages[1], 'Challenge complete: Level 4 without a death.', 'the challenge is announced')
    equal(w.badges[1], 'FirstClearLevel4', 'the Level 4 first-clear badge is attempted')
    equal(#w.badges, 1, 'and nothing else')
end

do -- CampaignComplete names Levels 1-4 since 2026-10-05 (owner decision; was 1-3, so 1-2-3 alone no longer awards it)
    for _, case in ipairs({{{1, 2, 4}, false}, {{1, 2, 3}, false}, {{1, 2, 3, 4}, true}}) do
        local levels, awards = case[1], case[2]
        local data = freshProfile()
        local w = payoutWorld(data, {})
        for _, level in ipairs(levels) do w.fire(level, 0) end
        local label = 'clears of ' .. table.concat(levels, ', ')
        for index, level in ipairs(levels) do
            equal(w.badges[index], 'FirstClearLevel' .. level, label .. ' attempt each first-clear badge')
        end
        equal(table.find(w.badges, 'CampaignComplete') ~= nil, awards,
            label .. (awards and ' award' or ' do not award') .. ' CampaignComplete')
        equal(#w.badges, #levels + (awards and 1 or 0), label .. ' attempt no other badge')
        equal(data.Achievements.CampaignComplete == true, awards,
            label .. (awards and ' record' or ' do not record') .. ' the CampaignComplete achievement')
    end
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
    local shopUI = newInstance('Folder', 'ZyntraShopUI')
    shopUI.Parent = storage
    newInstance('ModuleScript', 'ShopBinder').Parent = shopUI
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
    -- The world the chip reads "lobby" off: a ServerLobby model with the box
    -- measured in Play on 2026-09-17, a character standing on the lobby road,
    -- and a Heartbeat the chip polls the position on.
    ctx.Workspace = newInstance('Workspace', 'Workspace')
    ctx.Lobby = newInstance('Model', 'ServerLobby')
    ctx.Lobby.Parent = ctx.Workspace
    ctx.LobbyPivot = {X = 0.7, Y = 58.4, Z = -760.3}
    ctx.Lobby.GetPivot = function() return {Position = ctx.LobbyPivot} end
    ctx.Lobby.GetBoundingBox = function()
        return {Position = ctx.LobbyPivot}, {X = 186.3, Y = 59.1, Z = 286.8}
    end
    ctx.Character = newInstance('Model', 'Character')
    ctx.Root = newInstance('Part', 'HumanoidRootPart')
    ctx.Root.Position = {X = 1.6, Y = 33.6, Z = -861.3}
    ctx.Root.Parent = ctx.Character
    ctx.Player.Character = ctx.Character
    ctx.Heartbeat = signal()
    ctx.GuiService = {SelectedObject = nil}
    local services = {Players = {LocalPlayer = ctx.Player}, ReplicatedStorage = storage,
        SocialService = ctx.Social, RunService = {Heartbeat = ctx.Heartbeat}, GuiService = ctx.GuiService}
    ctx.Game = {GetService = function(_, name) return assert(services[name], name) end}
    ctx.Task = {spawn = function(fn, ...) fn(...) end,
        wait = function() ctx.Waits += 1 end}
    return ctx
end

local function boot(ctx)
    local game, task, workspace = ctx.Game, ctx.Task, ctx.Workspace
    local UIStyleModule = (function()
'''

UISTYLE_TAIL = r'''
    end)()
    -- the REAL ShopBinder, for the L4 palette the chip is drawn in
    local ShopBinderModule = (function()
'''

BINDER_TAIL = r'''
    end)()
    ctx.Palette = ShopBinderModule.Palette
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
    -- UIDevice.SetInteractive, as the real module applies it since the 23/9
    -- queue-modal fix: Visible, and for a button Active and Selectable with it.
    function UIDeviceFake.SetInteractive(element, visible)
        element.Visible = visible
        if not (element:IsA("TextButton") or element:IsA("ImageButton")) then return end
        element.Active = visible
        element.Selectable = visible
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
        if module.Name == 'ShopBinder' then return ShopBinderModule end
        error('unexpected require: ' .. tostring(module.Name))
    end
'''

CLIENT_TESTS = r'''
end

-- The lobby token pill "Zyntra Shop L4" draws AT the top-right corner: right
-- edge on the safe right edge less the margin, top on the safe top plus it.
local PILL_WIDTH, PILL_HEIGHT = 153, 52
local function addPill(ctx)
    local L = ctx.Layout
    local margin = L.IsTouch and 8 or 18
    local pillGui = newInstance('ScreenGui', 'ZyntraLobbyPillL4')
    pillGui.AbsolutePosition = Vector2.new(L.OriginX, L.OriginY)
    local pill = newInstance('Frame', 'TokenPill')
    pill.AbsolutePosition = Vector2.new(L.SafeRight - margin - PILL_WIDTH, L.SafeTop + margin)
    pill.AbsoluteSize = Vector2.new(PILL_WIDTH, PILL_HEIGHT)
    pill.Parent = pillGui
    pillGui.Parent = ctx.PlayerGui
    return pill
end

local function startClient(layout, invite, friends, withPill)
    local ctx = clientContext(layout, invite == nil and true or invite)
    if friends then
        ctx.Player:SetAttribute('FriendBoostFriends', friends)
        ctx.Player:SetAttribute('FriendBoostPercent', friends * PERCENT)
    end
    if withPill then ctx.Pill = addPill(ctx) end
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
    -- The token pill gui's insets (owner, 2026-10-08), so a pill offset is a chip offset.
    equal(ctx.Gui.ScreenInsets, Enum.ScreenInsets.DeviceSafeInsets, 'and spans the topbar band (DeviceSafeInsets)')
    equal(ctx.Gui.ResetOnSpawn, false, 'and survives a respawn')
    equal(#ctx.Registered, 1, 'the chip registers exactly one control rect')
    equal(ctx.Registered[1].Key, 'FriendBoost', 'under the stated key')
    equal(ctx.Registered[1].Element, ctx.Chip, 'and it is the chip itself')
end

do -- the three copy states
    local zero = startClient(POINTER, true, 0)
    equal(zero.Boost.Text, 'FRIEND BOOST +0%', 'no friends still names the boost')
    -- One short line now (owner, 2026-10-07: compact); the INVITE FRIENDS button
    -- under it says the rest. Was 'INVITE FRIENDS TO EARN +10% PER FRIEND'.
    equal(zero.Detail.Text, '+10% PER FRIEND', 'and says what each friend earns')
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
    equal(ctx.Detail.Text, '+10% PER FRIEND', 'with the per-friend copy')
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
    local line = startClient(PHONE)
    for _, bad in ipairs({-4, 0 / 0, 1.6}) do
        line.Player:SetAttribute('FriendBoostPercent', bad)
        check(string.find(line.Boost.Text, '^FRIENDS %+%d+%%$') ~= nil,
            'and so does the phone line: ' .. line.Boost.Text)
    end
end

do -- lobby only, and out of the way of anything that owns the screen
    local ctx = startClient(POINTER, true, 2)
    equal(ctx.Chip.Visible, true, 'the chip is up in the lobby')
    ctx.Player:SetAttribute('InRound', true)
    equal(ctx.Chip.Visible, false, 'and stands down in a round')
    ctx.Player:SetAttribute('InRound', false)
    equal(ctx.Chip.Visible, true, 'and comes back in the lobby')
    -- LOBBY ONLY is read off the world too (owner, 2026-09-17: never inside a
    -- game). A round flag, a round loading, a body outside the lobby's box, or
    -- no lobby at all each hide it on their own.
    ctx.Workspace:SetAttribute('RoundActive', true)
    equal(ctx.Chip.Visible, false, 'RoundActive hides it even with InRound false')
    ctx.Workspace:SetAttribute('RoundActive', false)
    equal(ctx.Chip.Visible, true, 'and it returns when the round ends')
    ctx.Workspace:SetAttribute('RoundLoadingState', 'loading')
    equal(ctx.Chip.Visible, false, 'a round loading hides it')
    ctx.Workspace:SetAttribute('RoundLoadingState', 'ready')
    equal(ctx.Chip.Visible, true, 'a finished load with no round is the lobby again')
    ctx.Root.Position = {X = -5, Y = 4.6, Z = -14}   -- the Level 1 maze
    ctx.Heartbeat:Fire(0.6)
    equal(ctx.Chip.Visible, false, 'a body outside the lobby box hides it within a poll')
    ctx.Root.Position = {X = 1.6, Y = 33.6, Z = -861.3}
    ctx.Heartbeat:Fire(0.6)
    equal(ctx.Chip.Visible, true, 'and back on the lobby road it returns')
    ctx.Root.Position = {X = 62, Y = 41, Z = -840}     -- inside the Level 2 queue room
    ctx.Heartbeat:Fire(0.6)
    equal(ctx.Chip.Visible, true, 'the queue rooms are still the lobby')
    ctx.Root.Position = {X = 1.6, Y = 33.6, Z = -861.3}
    ctx.Heartbeat:Fire(0.3)
    ctx.Heartbeat:Fire(0.3)
    equal(ctx.Chip.Visible, true, 'two short beats add up to one poll')
    ctx.Lobby.Parent = nil
    ctx.Heartbeat:Fire(0.6)
    equal(ctx.Chip.Visible, false, 'no ServerLobby (a level server) hides it')
    ctx.Lobby.Parent = ctx.Workspace
    ctx.LobbyPivot = {X = 0.7, Y = 58.4, Z = 2000}     -- the lobby parked away for a level
    ctx.Heartbeat:Fire(0.6)
    equal(ctx.Chip.Visible, false, 'a parked lobby is re-measured, and the body is not in it')
    ctx.LobbyPivot = {X = 0.7, Y = 58.4, Z = -760.3}
    ctx.Heartbeat:Fire(0.6)
    equal(ctx.Chip.Visible, true, 'and the lobby put back is the lobby')
    -- This context has NO token pill. The queue host modal and re-entry stand the
    -- chip down outright; over a rail window (owner, 2026-10-08) it stays up only
    -- beside a drawn pill, so with none it still yields rather than sit on Close.
    for _, modal in ipairs({'LuckyWheelOpen', 'DailyRewardsOpen', 'ZyntraStoreOpen',
        'QueueModalOpen', 'DevPhoneOpen', 'ZyntraReentryOpen'}) do
        local why = (modal == 'QueueModalOpen' or modal == 'ZyntraReentryOpen') and ''
            or ' (a rail window with no pill drawn)'
        ctx.Player:SetAttribute(modal, true)
        equal(ctx.Chip.Visible, false, 'the chip yields to ' .. modal .. why)
        equal(ctx.Invite.Active, false, 'and its invite is inert under ' .. modal)
        equal(ctx.Gui.DisplayOrder, 60, 'and its gui stays at 60 under ' .. modal)
        ctx.Player:SetAttribute(modal, false)
        equal(ctx.Chip.Visible, true, 'and returns when ' .. modal .. ' closes')
    end
end

do -- over a rail window WITH the pill drawn (owner, 2026-10-08): up, pressable, at 119
    local ctx = startClient(PHONE, true, 1, true)
    equal(ctx.Gui.DisplayOrder, 60, 'at rest the chip gui is at 60')
    for _, modal in ipairs({'LuckyWheelOpen', 'DailyRewardsOpen', 'ZyntraStoreOpen', 'DevPhoneOpen'}) do
        ctx.Player:SetAttribute(modal, true)
        equal(ctx.Chip.Visible, true, 'the chip stays up over ' .. modal)
        equal(ctx.Invite.Visible and ctx.Invite.Active, true, 'with its invite pressable over ' .. modal)
        equal(ctx.Gui.DisplayOrder, 119, 'raised to 119 over ' .. modal)
        ctx.Player:SetAttribute(modal, false)
        equal(ctx.Chip.Visible, true, 'and still up when ' .. modal .. ' closes')
        equal(ctx.Gui.DisplayOrder, 60, 'back at 60 when ' .. modal .. ' closes')
    end
    for _, modal in ipairs({'QueueModalOpen', 'ZyntraReentryOpen'}) do
        ctx.Player:SetAttribute(modal, true)
        equal(ctx.Chip.Visible, false, 'the pill does not keep the chip up under ' .. modal)
        equal(ctx.Gui.DisplayOrder, 60, 'and its gui stays at 60 under ' .. modal)
        ctx.Player:SetAttribute(modal, false)
    end
    -- The pill hidden over a window (a rail too close, a 36 px band) takes the chip
    -- with it IN THE SAME STEP: its Visible signal refreshes, no poll needed.
    ctx.Player:SetAttribute('DailyRewardsOpen', true)
    local beats = 0
    ctx.Heartbeat:Connect(function() beats += 1 end)
    ctx.Pill.Visible = false
    equal(beats, 0, 'no Heartbeat ran')
    equal(ctx.Chip.Visible, false, 'a pill hidden over a window hides the chip at once')
    equal(ctx.Invite.Active, false, 'and makes its invite inert')
    equal(ctx.Gui.DisplayOrder, 60, 'and drops its gui back to 60')
    ctx.Pill.Visible = true
    equal(ctx.Chip.Visible, true, 'the pill back up brings the chip back over the window')
    equal(ctx.Gui.DisplayOrder, 119, 'at 119')
    -- Gamepad: a pad that moved onto the invite over a window is let go when the
    -- window closes (every window clears only its own focus); focus on the chip
    -- at rest, or on another UI, is left alone.
    ctx.GuiService.SelectedObject = ctx.Invite
    ctx.Heartbeat:Fire(0.6)
    equal(ctx.GuiService.SelectedObject, ctx.Invite, 'pad focus on the invite holds while the window is open')
    ctx.Player:SetAttribute('DailyRewardsOpen', false)
    equal(ctx.GuiService.SelectedObject, nil, 'closing the window takes pad focus off the chip')
    ctx.GuiService.SelectedObject = ctx.Invite
    ctx.Heartbeat:Fire(0.6)
    equal(ctx.GuiService.SelectedObject, ctx.Invite, 'at rest pad focus on the chip is left alone')
    local other = newInstance('TextButton', 'Elsewhere')
    ctx.Player:SetAttribute('DailyRewardsOpen', true)
    ctx.GuiService.SelectedObject = other
    ctx.Player:SetAttribute('DailyRewardsOpen', false)
    equal(ctx.GuiService.SelectedObject, other, 'closing the window leaves focus on another UI alone')
end

do -- docked (owner, 2026-10-08): LEFT of a pill docked in the topbar band, centred on it
    local ctx = startClient(POINTER, true, 1, true)
    local underX, underY, underW, underH = ctx.Chip.Position.OX, ctx.Chip.Position.OY, ctx.Chip.Size.OX, ctx.Chip.Size.OY
    ctx.Pill:SetAttribute('Docked', true)
    local pillLeft = ctx.Pill.AbsolutePosition.X - POINTER.OriginX
    local pillMid = ctx.Pill.AbsolutePosition.Y - POINTER.OriginY + PILL_HEIGHT / 2
    equal(ctx.Chip.Position.OX + ctx.Chip.Size.OX, pillLeft - 6, 'docked: its right edge is 6 px left of the pill')
    equal(ctx.Chip.Position.OY + ctx.Chip.Size.OY / 2, pillMid, 'docked: its vertical centre is the pill centre')
    equal(ctx.Chip.Size.OX, 104, 'docked: the compact line, 104 wide even on PC')
    equal(ctx.Chip.Size.OY, 44, 'docked: and the 44 px tap area tall')
    equal(ctx.Boost.Text, 'FRIENDS +10%', 'docked: the short line copy')
    equal(ctx.Boost.Position.OY, 10, 'docked: the 24 px line is centred in the tap area')
    equal(ctx.Detail.Visible, false, 'docked: no detail line')
    ctx.Pill:SetAttribute('Docked', nil)
    equal(ctx.Chip.Position.OX, underX, 'undocked: back under the pill, x')
    equal(ctx.Chip.Position.OY, underY, 'undocked: and y')
    equal(ctx.Chip.Size.OX, underW, 'undocked: the box width again')
    equal(ctx.Chip.Size.OY, underH, 'undocked: and its height')
    equal(ctx.Boost.Text, 'FRIEND BOOST +10%', 'undocked: the box copy again')
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

do -- geometry (owner, 2026-10-07): the token pill owns the top-right corner and
   -- the chip hangs DIRECTLY UNDER it, right-aligned to it. This replaces the old
   -- rule (the chip itself at the corner, 260 / 220 wide).
    for _, layout in ipairs({POINTER, PHONE}) do
        local margin = layout.IsTouch and 8 or 18
        local right, top = layout.SafeRight - margin, layout.SafeTop + margin
        local kind = layout.IsTouch and 'touch' or 'pointer'
        local ctx = startClient(layout, true, 1, true)
        local width = layout.IsTouch and 104 or PILL_WIDTH
        equal(ctx.Chip.Size.OX, width, kind .. ': the chip is ' .. width .. ' wide')
        equal(ctx.Chip.Position.OX + width, right - layout.OriginX,
            kind .. ': its right edge is the pill right edge')
        equal(ctx.Chip.Position.OY, top + PILL_HEIGHT + 6 - layout.OriginY,
            kind .. ': and it starts 6 px under the pill')
        -- no pill drawn: the corner itself
        local bare = startClient(layout, true, 1)
        local bareWidth = layout.IsTouch and 104 or 160
        equal(bare.Chip.Position.OX, right - bareWidth - layout.OriginX,
            kind .. ': with no pill its right edge is the safe right edge')
        equal(bare.Chip.Position.OY, top - layout.OriginY, kind .. ': and it hangs from the safe top')
        for _, label in ipairs({ctx.Boost, ctx.Detail, ctx.Invite}) do
            check(label.TextSize >= 11, 'no text below 11px: ' .. label.Name)
            check(label.TextScaled ~= true, label.Name .. ' states its own size')
            check(label.FontFace.Family == 'rbxasset://fonts/families/RobotoCondensed.json'
                or label.FontFace.Family == 'rbxasset://fonts/families/Montserrat.json',
                label.Name .. ' is in an L4 face (Montserrat / Roboto Condensed)')
        end
        check(ctx.Chip.Position.OX >= layout.SafeLeft, 'the chip stays inside the safe area')
    end
    missing(CLIENT_SOURCE, 'Gotham', 'no Gotham left in the chip')
end

do -- pointer: a compact box no wider than the pill, in the L4 palette
    local ctx = startClient(POINTER, true, 1, true)
    check(ctx.Chip.Size.OX <= PILL_WIDTH, 'the box is no wider than the pill')
    equal(ctx.Chip.BackgroundColor3, ctx.Palette.Ink, 'the box is the pill Ink')
    equal(ctx.Chip.BackgroundTransparency, 0, 'and opaque')
    equal(ctx.Boost.Text, 'FRIEND BOOST +10%', 'the boost line')
    equal(ctx.Boost.TextColor3, Color3.fromRGB(255, 203, 79), 'stays gold')
    equal(ctx.Detail.Visible, true, 'one detail line under it')
    check(ctx.Detail.TextWrapped ~= true, 'a single line, not wrapped')
    equal(ctx.Detail.Text, '1 FRIEND ON THIS SERVER', 'saying who is here')
    equal(ctx.Invite.Text, 'INVITE FRIENDS', 'a small invite button')
    check(ctx.Invite.Size.OY >= 28 and ctx.Invite.Size.OY <= 30, 'about 28-30 px tall: ' .. ctx.Invite.Size.OY)
    equal(ctx.Invite.BackgroundColor3, ctx.Palette.RailTeal, 'on the rail teal')
    equal(ctx.Invite.TextColor3, ctx.Palette.Tile, 'with Tile text')
    check(ctx.Chip.Size.OY >= ctx.Invite.Position.OY + ctx.Invite.Size.OY + 6,
        'and the chip is tall enough to hold it')
    check(ctx.Invite.Position.OX + ctx.Invite.Size.OX <= ctx.Chip.Size.OX,
        'and the button stays inside the box')
    local no = startClient(POINTER, false, 1, true)
    equal(no.Chip.Size.OY, 8 + 16 + 14 + 8, 'with no invite the box drops the button row')
end

do -- touch (owner, 2026-10-07: "very subtle"): one translucent line, all of it the button
    local ctx = startClient(PHONE, true, 2, true)
    equal(ctx.Boost.Text, 'FRIENDS +20%', 'one short line')
    equal(ctx.Detail.Visible, false, 'no detail line')
    equal(ctx.Boost.Size.OY, 24, 'the line is 24 px tall')
    equal(ctx.Boost.Size.OX, ctx.Chip.Size.OX, 'and as wide as the chip')
    equal(ctx.Boost.Position.OY, 0, 'at the top of the chip')
    check(ctx.Boost.BackgroundTransparency > 0 and ctx.Boost.BackgroundTransparency < 1,
        'a translucent pill: ' .. ctx.Boost.BackgroundTransparency)
    equal(ctx.Chip.BackgroundTransparency, 1, 'with no box drawn around it')
    -- No separate button: the invite target is invisible and covers the line.
    equal(ctx.Invite.Text, '', 'no button copy')
    equal(ctx.Invite.BackgroundTransparency, 1, 'no button face')
    equal(ctx.Invite.Position.OX, 0, 'the tap area starts at the line left edge')
    equal(ctx.Invite.Position.OY, 0, 'and at its top')
    equal(ctx.Invite.Size.OX, ctx.Chip.Size.OX, 'covering its width')
    equal(ctx.Invite.Size.OY, 44, 'and 44 px down from its top')
    equal(ctx.Chip.Size.OY, 44, 'the chip (the registered rect) is the tap area')
    equal(ctx.Registered[1].Element, ctx.Chip, 'and it is still the registered rect')
    equal(ctx.Invite.Visible, true, 'the line is tappable when inviting is allowed')
    ctx.Invite.Activated:Fire()
    equal(ctx.Invites, 1, 'a tap on the line opens Roblox own invite prompt')
    local no = startClient(PHONE, false, 2, true)
    equal(no.Invite.Visible, false, 'a definitive no leaves only the line')
    equal(no.Chip.Size.OY, 24, 'and the chip shrinks to it')
    no.Invite.Activated:Fire()
    equal(no.Invites, 0, 'which cannot prompt')
end

do -- the chip follows the pill: drawn late, moved, hidden, shown, resized
    local ctx = startClient(POINTER, true, 1)
    local bareX = ctx.Chip.Position.OX
    local pill = addPill(ctx) -- the pill gui arrives after the chip booted
    equal(ctx.Chip.Position.OY, POINTER.SafeTop + 18 + PILL_HEIGHT + 6 - POINTER.OriginY,
        'a pill that arrives late pulls the chip under it')
    pill.AbsolutePosition = Vector2.new(pill.AbsolutePosition.X - 40, pill.AbsolutePosition.Y + 10)
    equal(ctx.Chip.Position.OX + ctx.Chip.Size.OX, POINTER.SafeRight - 18 - 40 - POINTER.OriginX,
        'a moved pill takes the chip with it')
    equal(ctx.Chip.Position.OY, POINTER.SafeTop + 18 + 10 + PILL_HEIGHT + 6 - POINTER.OriginY,
        'down as well as across')
    pill.Visible = false
    equal(ctx.Chip.Position.OX, bareX, 'a hidden pill gives the corner back')
    equal(ctx.Chip.Position.OY, POINTER.SafeTop + 18 - POINTER.OriginY, 'top as well')
    pill.Visible = true
    equal(ctx.Chip.Position.OY, POINTER.SafeTop + 18 + 10 + PILL_HEIGHT + 6 - POINTER.OriginY,
        'and showing it again puts the chip back under it')
    pill.AbsoluteSize = Vector2.new(140, PILL_HEIGHT)
    equal(ctx.Chip.Size.OX, 140, 'a narrower pill narrows the box with it')
end

do -- the chip is content-sized: it must NOT shrink to the room above the controls
    for _, layout in ipairs({POINTER, PHONE}) do
        local ctx = clientContext(layout, true)
        -- A cluster measured at the very top -- which is what registering the chip
        -- itself would look like to TopRightPanel -- must not collapse the chip.
        -- Was "the phone chip stays >= 100 tall"; the phone chip is now the 44 px
        -- tap line, so the rule is its exact content height on both devices.
        ctx.Layout.ControlsTop = ctx.Layout.SafeTop + 20
        boot(ctx)
        local chip = descendant(ctx.PlayerGui, 'FriendBoostChip')
        equal(chip.Size.OY, layout.IsTouch and 44 or 8 + 16 + 14 + 6 + 30 + 8,
            'the chip keeps its content height, so it cannot oscillate')
    end
end

do -- a layout change relays it out without losing the copy
    local ctx = startClient(POINTER, true, 2)
    ctx.Layout = table.clone(PHONE)
    ctx.UIDevice.Changed:Fire()
    equal(ctx.Chip.Size.OX, 104, 'a switch to touch re-lays the chip as the line')
    equal(ctx.Boost.Text, 'FRIENDS +20%', 'and re-words it')
    equal(ctx.Detail.Text, '2 FRIENDS ON THIS SERVER', 'and keeps what it was saying')
    ctx.Layout = table.clone(POINTER)
    ctx.UIDevice.Changed:Fire()
    equal(ctx.Boost.Text, 'FRIEND BOOST +20%', 'and back on pointer it is the box again')
    equal(ctx.Detail.Visible, true, 'with its detail line')
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

    handler = section(MONETIZATION, "levelCompletedEvent.Event:Connect(function(player, level, friendCount",
                      "MarketplaceService.PromptGamePassPurchaseFinished")
    tenths = section(MONETIZATION, "\t-- FRIEND_BOOST_20260916. The unpaid fraction",
                     "\t-- Both sets are rebuilt")
    levels = section(MONETIZATION, "\t-- Both sets are rebuilt", "\tlocal awardedBadges")
    achievements = section(MONETIZATION, "achievementApi.award = awardBadge", "do\n\tlocal bindable")
    achievement_counts = section(MONETIZATION, "local MAX_SAFE_SUPPORT =",
                                 "local function normalizedSupportAmount")
    achievement_counts += section(MONETIZATION, "local function wholeCount(value)",
                                  "local function normalizeItems(value)")
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
        # The real challenge ledger: the handler applies the run in the same write.
        "local CHALLENGES_MODULE = (function()", CHALLENGES, "end)()",
        "local CLIENT_SOURCE = " + literal(CLIENT),
        "local function normalizeTenths(data)",
        tenths,
        "end",
        "local function normalizeLevels(data)",
        levels,
        "end",
        # The real handler, wired to a fake completionSaves.settle that normalises
        # the profile on the way in as normalizeProfile does, applies the keyed
        # transform, and runs the after-save callback (badges) once it commits.
        "local function payoutWorld(data, messages)",
        "    local w = {badges = {}, daily = {}}",
        "    local player = newInstance('Player', 'Escapee')",
        "    w.stranger = newInstance('Player', 'Stranger')",
        "    local sessions = {[player] = {data = data, persistent = true}}",
        "    local Config = ZyntraConfig",
        "    local levelCompletedEvent = {Event = signal()}",
        "    local guids = 0",
        "    local HttpService = {GenerateGUID = function() guids += 1 return 'guid-' .. guids end}",
        "    local completionSaves = {}",
        "    function completionSaves.settle(who, id, transform, after)",
        "        check(type(id) == 'string' and #id > 0, 'every clear carries a completion id')",
        "        local profile = sessions[who].data",
        "        normalizeTenths(profile)",
        "        normalizeLevels(profile)",
        "        local ok, message = transform(profile)",
        "        check(ok == true, 'the completion transform always commits')",
        "        table.insert(messages, message)",
        "        after()",
        "    end",
        # Token Earner is KNOWN at 1x (no pass owned): its multiplier has its own
        # suite, and a known tier never defers, so the deferral path must not run.
        "    local tokenEarner = {",
        "        tier = function(who) check(who == player, 'the tier is read for the escapee') return 1, true end,",
        "        stamp = function() return 1 end,",
        "        bonus = function(_, _, tier) equal(tier, 1, 'the 1x tier is what is applied') return 0 end,",
        "        defer = function() error('a known tier never defers its bonus') end,",
        "        proof = function() error('a known tier needs no ownership proof') end,",
        "        settle = function() error('a known tier has nothing to settle') end,",
        "    }",
        "    local function awardBadge(_, badge) table.insert(w.badges, badge) end",
        # ACHIEVEMENTS_20261004: the handler unlocks through the REAL achievementApi,
        # which records the key on the profile and then attempts the badge above.
        "    local task = {spawn = function(fn, ...) fn(...) end}",
        "    local function mutateIdempotent(who, transform) transform(sessions[who].data) return true end",
        "    local achievementApi = {}",
        # The freshly audited Studio unlocker also normalises optional badge
        # gifts. Keep its exact helpers when selecting that foreign source.
        achievement_counts,
        achievements,
        # The daily ledger and the challenge ledger the handler also touches.
        # Daily research only RECORDS the goal it was asked for: this suite
        # measures the boost and the tracked-level gate, and test_daily_rewards.py
        # runs the real ledger against the same write.
        "    local function utcDay() return 20000 end",
        "    local function rollDaily() end",
        "    local DailyResearch = {Complete = function(profile, goal)",
        "        check(profile == data, 'daily research is credited on the profile being written')",
        "        table.insert(w.daily, goal)",
        "        return false, 0",
        "    end}",
        "    local Challenges = CHALLENGES_MODULE",
        handler,
        "    function w.fire(level, friends, run)",
        "        levelCompletedEvent.Event:Fire(player, level, friends, run)",
        "    end",
        "    function w.fireRaw(...) levelCompletedEvent.Event:Fire(...) end",
        "    return w",
        "end",
    ])

    source = "".join([
        HARNESS, CONFIG, CONFIG_TAIL, MODULE, MODULE_TAIL,
        payout, "\n", PAYOUT_TESTS,
        CLIENT_HARNESS, UISTYLE, UISTYLE_TAIL, BINDER, BINDER_TAIL, CLIENT, CLIENT_TESTS,
    ])
    with tempfile.TemporaryDirectory(prefix="friend-boost-") as directory:
        path = Path(directory) / "friend_boost.luau"
        path.write_text(source, encoding="utf-8")
        subprocess.run([binary, str(path)], check=True, timeout=60)


if __name__ == "__main__":
    main()
