"""Daily playtime accrual, milestone claims, the supply wheel and the Speed Potion.

Runs the REAL blocks out of ZyntraMonetization.Script.lua -- the profile helpers
(newProfile/normalizeProfile/applyReward/rollDaily/dailyPublic), publicProfile,
applyAttributes, mutate, and the whole daily-rewards section -- under the real
Luau interpreter against a fake DataStore, a fake DataModel and a scheduler that
drives the one-second accrual loop.

Set LUAU_BIN to the official Luau executable, or put luau on PATH.
"""
from pathlib import Path
import os
import shutil
import subprocess
import tempfile

ROOT = Path(__file__).resolve().parents[2]
SERVER = (ROOT / "ServerScriptService/ZyntraMonetization.Script.lua").read_text(encoding="utf-8")
CONFIG = (ROOT / "ReplicatedStorage/ZyntraConfig.ModuleScript.lua").read_text(encoding="utf-8")
RESEARCH = (ROOT / "ReplicatedStorage/ZyntraDailyResearch.ModuleScript.lua").read_text(encoding="utf-8")
# ZyntraMonetization requires the challenge ledger since CHALLENGES_20260923.
CHALLENGES = (ROOT / "ReplicatedStorage/ZyntraChallenges.ModuleScript.lua").read_text(encoding="utf-8")
SKINS = (ROOT / "ReplicatedStorage/ZyntraSkins.ModuleScript.lua").read_text(encoding="utf-8")


def section(start, stop):
    begin = SERVER.index(start)
    return SERVER[begin:SERVER.index(stop, begin)]


PRELUDE = r'''
local checks = 0
local function check(value, message)
    checks += 1
    assert(value, message)
end
local function eq(actual, expected, message)
    check(actual == expected,
        message .. ": expected " .. tostring(expected) .. ", got " .. tostring(actual))
end
local function clone(value)
    if type(value) ~= "table" then return value end
    local result = {}
    for key, child in pairs(value) do result[key] = clone(child) end
    return result
end
local function signal()
    local s = {handlers = {}}
    function s:Connect(fn)
        table.insert(self.handlers, fn)
        return {Disconnect = function() end}
    end
    function s:Fire(...)
        for _, fn in ipairs(self.handlers) do fn(...) end
    end
    return s
end
local VectorMeta = {}
local function vec(x, y, z) return setmetatable({X = x, Y = y or 0, Z = z or 0}, VectorMeta) end
VectorMeta.__sub = function(a, b) return vec(a.X - b.X, a.Y - b.Y, a.Z - b.Z) end
VectorMeta.__index = function(t, key)
    if key == "Magnitude" then return math.sqrt(t.X * t.X + t.Y * t.Y + t.Z * t.Z) end
    return nil
end
local Color3 = {fromRGB = function(r, g, b) return {R = r / 255, G = g / 255, B = b / 255} end}
local Config = (function()
'''

WORLD = r'''
end)()
-- The REAL daily research ledger (ZyntraMonetization requires it since the
-- research goals landed); served through the ReplicatedStorage stub below.
local ZyntraDailyResearchModule = (function()
RESEARCH_SOURCE
end)()
local ZyntraChallengesModule = (function()
CHALLENGES_SOURCE
end)()
local ZyntraSkinsModule = (function()
SKINS_SOURCE
end)()

-- Every world gets its own upvalues, so the real blocks below are pasted inside
-- it: one fake DataStore, one fake DataModel, one scheduler.
local function world(opts)
    opts = opts or {}
    local w = {
        now = 0, epoch = 1789516800, day = opts.day or "2026-09-16",
        db = {}, tasks = {}, waiting = {}, pushes = {}, warnings = {},
        calls = 0, callbacks = 0, writes = 0, tagRefreshes = 0,
        studio = opts.studio == true, random = opts.random,
    }
    local function warn(...) table.insert(w.warnings, {...}) end
    local os = {
        time = function() return w.epoch end,
        clock = function() return w.now end,
        date = function() return w.day end,
    }
    local game = {JobId = "job-1"}
    local RunService = {IsStudio = function() return w.studio end}

    local task = {}
    local function enqueue(co, delay)
        table.insert(w.tasks, {co = co, at = w.now + (delay or 0)})
    end
    function task.spawn(fn, ...)
        local args = table.pack(...)
        enqueue(coroutine.create(function() fn(table.unpack(args, 1, args.n)) end))
    end
    task.defer = task.spawn
    function task.delay(delay, fn, ...)
        local args = table.pack(...)
        enqueue(coroutine.create(function() fn(table.unpack(args, 1, args.n)) end), delay)
    end
    function task.wait(delay) return coroutine.yield(delay or 0) end
    -- Runs every task due at or before `deadline`. The accrual loop re-arms
    -- itself one second out, so this is how a stretch of play is simulated.
    function w:runUntil(deadline)
        local steps = 0
        while true do
            table.sort(self.tasks, function(a, b) return a.at < b.at end)
            local item = self.tasks[1]
            if not item or item.at > deadline then break end
            table.remove(self.tasks, 1)
            steps += 1
            assert(steps < 100000, "scheduler did not settle")
            self.now = math.max(self.now, item.at)
            local ok, delay = coroutine.resume(item.co)
            assert(ok, delay)
            if coroutine.status(item.co) ~= "dead" then
                if type(delay) == "string" then table.insert(self.waiting, item.co)
                else enqueue(item.co, delay) end
            end
        end
        self.now = math.max(self.now, deadline)
    end
    function w:run() self:runUntil(self.now) end
    function w:resumeWaiting()
        for _, co in ipairs(self.waiting) do enqueue(co) end
        table.clear(self.waiting)
    end
    function w:tick(seconds) self:runUntil(self.now + seconds) end
    -- Ticking with the character actually moving, which is what a player who is
    -- playing looks like: w:tick alone goes AFK after the grace window.
    function w:play(seconds)
        for _ = 1, seconds do
            local character = self.player and self.player.Character
            local root = character and rawget(character, "HumanoidRootPart")
            if root then root.Position = vec((self.now + 1) * 4, 0, 0) end
            self:runUntil(self.now + 1)
        end
    end

    local workspace = {attributes = {}, signals = {}}
    function workspace:GetAttribute(key) return self.attributes[key] end
    function workspace:GetServerTimeNow() return w.now end
    function workspace:GetAttributeChangedSignal(key)
        local s = self.signals[key]
        if not s then s = signal(); self.signals[key] = s end
        return s
    end
    function workspace:SetAttribute(key, value)
        self.attributes[key] = value
        local s = self.signals[key]
        if s then s:Fire() end
    end

    local Players = {roster = {}, PlayerAdded = signal()}
    function Players:GetPlayers() return self.roster end
    function Players:GetPlayerByUserId(userId)
        for _, p in ipairs(self.roster) do if p.UserId == userId then return p end end
        return nil
    end
    local function typeof(value)
        return type(value) == "table" and value.ClassName and "Instance" or type(value)
    end

    local function makeCharacter(x)
        local humanoid = {ClassName = "Humanoid", Health = 100, Died = signal()}
        function humanoid:IsA(class) return class == "Humanoid" end
        local c = {
            Humanoid = humanoid,
            HumanoidRootPart = {Name = "HumanoidRootPart", Position = vec(x or 0, 0, 0)},
            inWorld = true,
        }
        function c:FindFirstChildOfClass(class)
            return class == "Humanoid" and self.Humanoid or nil
        end
        function c:FindFirstChild(name) return rawget(self, name) end
        function c:IsDescendantOf() return self.inWorld end
        function c:WaitForChild(name) return rawget(self, name) end
        return c
    end
    w.character = makeCharacter

    local function makePlayer(name, userId)
        local p = {Name = name, UserId = userId, ClassName = "Player", Parent = Players,
            attributes = {}, attributeSignals = {}}
        p.CharacterAdded = signal()
        p.CharacterRemoving = signal()
        function p:IsA(class) return class == "Player" end
        function p:GetAttribute(key) return self.attributes[key] end
        function p:SetAttribute(key, value)
            self.attributes[key] = value
            local s = self.attributeSignals[key]
            if s then s:Fire() end
        end
        function p:GetAttributeChangedSignal(key)
            local s = self.attributeSignals[key]
            if not s then s = signal(); self.attributeSignals[key] = s end
            return s
        end
        table.insert(Players.roster, p)
        return p
    end
    local player = makePlayer("Runner", 501)
    local mate = makePlayer("Mate", 502)
    w.player, w.mate = player, mate

    -- A fake DataStore with the three failure shapes that matter: a call that
    -- never reaches the callback, a call that commits and then loses its
    -- response, and a pause that lets a second writer queue behind the lock.
    local store = {}
    function store:UpdateAsync(key, transform)
        w.calls += 1
        if w.pauseStore then coroutine.yield("STORE_WAIT") end
        if w.failBefore then error("Profile write unavailable") end
        w.callbacks += 1
        local result = transform(clone(w.db[key]))
        if w.pauseAfterTransform then coroutine.yield("COMMIT_WAIT") end
        if result then w.db[key] = clone(result); w.writes += 1 end
        if w.failAfter then w.failAfter = false; error("Committed; response lost") end
        return clone(result)
    end

    local sessions, mutationLocks = {}, {}
    local serverClosing = false
    local ACCESSIBILITY_SETTINGS = Config.AccessibilitySettings
    local PERCENT_PER_LEVEL = math.floor(Config.TokenPercentPerLevel * 100 + 0.5)
    local function applyHazmatColor() end
    local function advancedStaminaBonus() return 0 end
    local function reassertPendingAccessibility() end
    local function refreshPlayerTags() w.tagRefreshes += 1 end
    local ReplicatedStorage = {}
    function ReplicatedStorage:WaitForChild(name) return name end
    function ReplicatedStorage:FindFirstChild(_name) return nil end
    local function require(name)
        if name == "ZyntraDailyResearch" then return ZyntraDailyResearchModule end
        if name == "ZyntraChallenges" then return ZyntraChallengesModule end
        if name == "ZyntraSkins" then return ZyntraSkinsModule end
        error("harness has no module " .. tostring(name))
    end
    local ServerStorage = {children = {}}
    function ServerStorage:FindFirstChild(name) return self.children[name] end
    local Instance = {}
    function Instance.new(class)
        local object = {ClassName = class, Name = "", Parent = nil}
        function object:IsA(other) return other == class end
        -- The research-progress BindableEvent the pasted block wires up.
        object.Event = {Connect = function() return {Disconnect = function() end} end}
        return object
    end
    -- xorshift32: good enough that a 20000-sample distribution is a real test of
    -- the weighting rather than a test of a bad generator.
    local Random = {}
    function Random.new()
        local state = 88172645
        local r = {}
        function r:NextNumber()
            if w.random then return w.random(w) end
            state = bit32.bxor(state, bit32.lshift(state, 13))
            state = bit32.bxor(state, bit32.rshift(state, 17))
            state = bit32.bxor(state, bit32.lshift(state, 5))
            return state / 4294967296
        end
        return r
    end
'''

PUSH = r'''
    local function pushProfile(p, message, tone)
        local session = sessions[p]
        table.insert(w.pushes, {player = p, message = message, tone = tone,
            data = session and publicProfile(session.data, p) or nil})
    end
'''

TAIL = r'''
    w.sessions, w.mutationLocks, w.workspace, w.store = sessions, mutationLocks, workspace, store
    w.publicProfile, w.normalize, w.applyReward = publicProfile, normalizeProfile, applyReward
    w.playtime, w.flush, w.pick = playtimeSessions, flushPlaytime, pickWheelPrize
    w.claim, w.spin, w.buy, w.potion = claimPlaytimeReward, spinDailyWheel, buyItem, useSpeedPotion
    w.collect = claimWheelPrize
    w.inventory = inventoryFunction
    function w:seed(profile)
        local key = "u_" .. player.UserId
        self.db[key] = normalizeProfile(profile)
        sessions[player] = {data = normalizeProfile(clone(self.db[key])),
            persistent = not self.studio}
        return self.db[key]
    end
    function w:saved() return self.db["u_" .. player.UserId] end
    function w:live() return sessions[player].data end
    function w:lastPush() return self.pushes[#self.pushes] end
    -- Everything this player has earned today: banked plus not yet flushed.
    function w:total() return publicProfile(sessions[player].data, player).Daily.PlaytimeSeconds end
    function w:enter(character)
        local spawned = character or self.character(0)
        player.Character = spawned
        -- Fired, not just assigned: the real per-player wiring hangs off this.
        player.CharacterAdded:Fire(spawned)
        player:SetAttribute("InRound", true)
        workspace:SetAttribute("RoundActive", true)
        workspace:SetAttribute("RoundLoadingState", "ready")
    end
    -- The REAL line finalizePlayerSessionBody runs before it closes a session.
    function w:leaveFlush()
        local session = sessions[player]
        LEAVE_FLUSH
    end
    return w
end

local function fresh(opts)
    local w = world(opts)
    w:seed({Tokens = 10, Daily = {Day = w.day, PlaytimeSeconds = 0, Claimed = {}}})
    return w
end
'''

TESTS = r'''
-- ---------------------------------------------------------------------------
-- Accrual gates: a second counts only under every one of the contract's rules.
-- ---------------------------------------------------------------------------
do
    local gates = {
        {name = "lobby", setup = function(w) w.player.Character = w.character(0) end, want = 0},
        {name = "in round, alive, moving", setup = function(w) w:enter() end, want = 5},
        {name = "not InRound", setup = function(w)
            w:enter(); w.player:SetAttribute("InRound", false) end, want = 0},
        {name = "RoundActive false", setup = function(w)
            w:enter(); w.workspace:SetAttribute("RoundActive", false) end, want = 0},
        {name = "loading cover up", setup = function(w)
            w:enter(); w.workspace:SetAttribute("RoundLoadingState", "loading") end, want = 0},
        -- SPECTATING COUNTS (owner, 2026-09-17): a participant of an active round
        -- with no living body -- escaped and waiting, dead, or between bodies --
        -- is watching the round, and that time is play time. No AFK gate applies
        -- to them; the round's own end (RoundActive) is what bounds it.
        {name = "escaped (spectating)", setup = function(w)
            w:enter(); w.player:SetAttribute("Escaped", true) end, want = 5},
        {name = "level 2 exit transition", setup = function(w)
            w:enter(); w.player:SetAttribute("Level2_ExitTransition", true) end, want = 0},
        {name = "dead body (spectating)", setup = function(w)
            local c = w.character(0); c.Humanoid.Health = 0; w:enter(c) end, want = 5},
        {name = "no character (between bodies)", setup = function(w)
            w:enter(); w.player.Character = nil end, want = 5},
        {name = "no root part (between bodies)", setup = function(w)
            local c = w.character(0); c.HumanoidRootPart = nil; w:enter(c) end, want = 5},
        {name = "dead but the round is over", setup = function(w)
            local c = w.character(0); c.Humanoid.Health = 0; w:enter(c)
            w.workspace:SetAttribute("RoundActive", false) end, want = 0},
    }
    for _, gate in ipairs(gates) do
        local w = fresh()
        gate.setup(w)
        w:tick(5)
        eq(w.playtime[w.player] and w.playtime[w.player].unflushedSeconds or 0, gate.want,
            gate.name .. " accrual")
        eq(w.player:GetAttribute("ZyntraDailyAccruing"), gate.want > 0,
            gate.name .. " publishes ZyntraDailyAccruing")
    end
end

-- Spectating has no AFK gate: a dead participant cannot move, so the grace
-- window that pauses a living idler must not pause them. 120 s is past the
-- 90 s grace and past one 60 s flush.
do
    local w = fresh()
    local c = w.character(0); c.Humanoid.Health = 0; w:enter(c)
    w:tick(120)
    check(w:total() >= 118, "a dead participant stopped counting past the AFK grace: " .. tostring(w:total()))
    eq(w.player:GetAttribute("ZyntraDailyAccruing"), true, "spectating publishes the accruing hint")
end

-- AFK: standing still pauses after the grace window and movement resumes it.
do
    local w = fresh()
    local character = w.character(0)
    w:enter(character)
    w:tick(10)
    eq(w:total(), 10, "ten seconds of play")
    w:tick(80)
    eq(w:total(), 90, "still inside the 90 s grace")
    w:tick(30)
    local banked = w:total()
    check(banked <= 92, "AFK stops counting within a second of the grace window")
    w:tick(30)
    eq(w:total(), banked, "AFK past the grace stops counting")
    eq(w.player:GetAttribute("ZyntraDailyAccruing"), false, "AFK clears the accruing hint")
    character.HumanoidRootPart.Position = vec(40, 0, 0)
    w:tick(4)
    eq(w:total(), banked + 4, "movement resumes accrual")
    eq(w.player:GetAttribute("ZyntraDailyAccruing"), true, "accruing hint returns")
    check(w:total() >= banked, "accrual never subtracts")
end

-- Sub-threshold drift is not movement.
do
    local w = fresh()
    local character = w.character(0)
    w:enter(character)
    w:tick(5)
    for step = 1, 120 do
        character.HumanoidRootPart.Position = vec(step * 0.0001, 0, 0)
        w:tick(1)
    end
    check(w:total() < 100, "drift under ActivityMinimumStuds does not defeat the AFK pause")
end

-- Hiding under a table is perfectly still and must still count.
do
    local w = fresh()
    w:enter()
    w.player:SetAttribute("Level3_Hiding", true)
    w:tick(200)
    eq(w:total(), 200, "hiding counts for the whole window")
    eq(w.player:GetAttribute("ZyntraDailyAccruing"), true, "hiding is accruing")
end

-- ---------------------------------------------------------------------------
-- Flushing: add a delta, never overwrite; keep it when the write is not known
-- to have landed; add it exactly once when the write committed silently.
-- ---------------------------------------------------------------------------
do
    local w = fresh()
    w:enter()
    w:tick(30)
    -- Another writer advanced the stored copy while this session accrued.
    w.db["u_501"].Daily.PlaytimeSeconds = 100
    eq(w:live().Daily.PlaytimeSeconds, 0, "session copy is older than the store")
    w.flush(w.player)
    eq(w:saved().Daily.PlaytimeSeconds, 130, "flush ADDS the delta to the store's total")
    eq(w.playtime[w.player].unflushedSeconds, 0, "a landed flush clears the delta")
    eq(w:live().Daily.PlaytimeSeconds, 130, "session adopts the committed total")
end

do
    local w = fresh()
    w:enter()
    w:tick(30)
    w.failBefore = true
    w.flush(w.player)
    w.failBefore = false
    eq(w:saved().Daily.PlaytimeSeconds, 0, "a write that never reached the store adds nothing")
    eq(w.playtime[w.player].unflushedSeconds, 30, "the delta is kept for the next attempt")
    w.flush(w.player)
    eq(w:saved().Daily.PlaytimeSeconds, 30, "the retry banks it once")
    eq(w.playtime[w.player].unflushedSeconds, 0, "and clears it")
end

do
    -- Committed, response lost. The seconds are in the store but the session
    -- cannot know that, so they stay pending -- and the retry must recognise its
    -- own flush id and add nothing a second time.
    local w = fresh()
    w:enter()
    w:tick(30)
    w.failAfter = true
    w.flush(w.player)
    eq(w:saved().Daily.PlaytimeSeconds, 30, "the lost write did commit")
    eq(w.playtime[w.player].unflushedSeconds, 30, "the delta stays pending after a lost response")
    w.flush(w.player)
    eq(w:saved().Daily.PlaytimeSeconds, 30, "the retry adds nothing a second time")
    eq(w.playtime[w.player].unflushedSeconds, 0, "the retry clears the now-proven delta")
    eq(w.writes, 1, "one durable write for one flush")
    w:tick(10)
    w.flush(w.player)
    eq(w:saved().Daily.PlaytimeSeconds, 40, "the next flush uses a new id and banks normally")
end

-- Seconds earned while the write yields belong to the NEXT flush.
do
    local w = fresh()
    w:enter()
    w:tick(20)
    eq(w.playtime[w.player].unflushedSeconds, 20, "twenty seconds pending")
    -- Park after the transform computed its delta, before the commit returns.
    w.pauseAfterTransform = true
    local co = coroutine.create(function() w.flush(w.player) end)
    coroutine.resume(co)
    w:tick(5)
    w.pauseAfterTransform = false
    local ok = coroutine.resume(co)
    check(ok, "parked flush resumed")
    eq(w:saved().Daily.PlaytimeSeconds, 20, "only the computed delta was banked")
    eq(w.playtime[w.player].unflushedSeconds, 5, "the seconds earned during the write survive")
end

-- A flush with nothing pending costs no DataStore call at all.
do
    local w = fresh()
    w:enter()
    eq(w.flush(w.player), false, "nothing to flush")
    eq(w.calls, 0, "an empty flush never touches the store")
end

-- ---------------------------------------------------------------------------
-- Day roll.
-- ---------------------------------------------------------------------------
do
    local w = fresh()
    w:seed({Tokens = 10, Daily = {Day = "2026-09-15", PlaytimeSeconds = 2400,
        Claimed = {["5"] = true, ["15"] = true}, WheelDay = "2026-09-15",
        WheelLast = {Day = "2026-09-15", Key = "Token3", Serial = 7}}})
    w:enter()
    w:tick(30)
    w.flush(w.player)
    local saved = w:saved()
    eq(saved.Daily.Day, "2026-09-16", "the roll moves the counters onto today")
    eq(saved.Daily.PlaytimeSeconds, 30, "yesterday's playtime is reset, today's delta stands")
    eq(saved.Daily.Claimed["5"], nil, "yesterday's claims are cleared")
    eq(saved.Daily.Claimed["15"], nil, "every claim is cleared")
    eq(saved.Daily.WheelDay, "2026-09-15", "WheelDay is NOT reset by the roll")
    eq(saved.Daily.WheelLast.Key, "Token3", "the recorded prize survives the roll")
    eq(saved.Daily.WheelLast.Serial, 7, "the prize serial survives the roll")
end

-- The public profile presents the pending roll, and folds in unflushed seconds.
do
    local w = fresh()
    w:seed({Tokens = 1, Daily = {Day = "2026-09-15", PlaytimeSeconds = 2400,
        Claimed = {["5"] = true}}})
    w:enter()
    w:tick(12)
    local public = w.publicProfile(w:live(), w.player)
    eq(public.Daily.Today, "2026-09-16", "Today is the server's UTC day")
    eq(public.Daily.Day, "2026-09-16", "the counters are presented on today")
    eq(public.Daily.PlaytimeSeconds, 12, "yesterday's total is not shown as today's")
    eq(public.Daily.Claimed["5"], nil, "yesterday's claim is not shown as claimable-blocked")
    eq(public.Daily.Accruing, true, "Accruing reports the live state")
    w.epoch = 1789516800 + 3600 * 5 + 61
    eq(w.publicProfile(w:live(), w.player).Daily.SecondsToReset, 86400 - (3600 * 5 + 61),
        "SecondsToReset counts down to the next 00:00 UTC")
end

do
    local w = fresh()
    w:enter()
    w:tick(45)
    local public = w.publicProfile(w:live(), w.player)
    eq(public.Daily.PlaytimeSeconds, 45, "unflushed seconds are included in the payload")
    eq(w:live().Daily.PlaytimeSeconds, 0, "and they are genuinely not in the profile yet")
    w.flush(w.player)
    eq(w.publicProfile(w:live(), w.player).Daily.PlaytimeSeconds, 45,
        "the number never jumps backwards over a flush")
    eq(w.publicProfile(w:live(), nil).Daily.Accruing, false,
        "a profile read without a session reports no session facts")
end

-- ---------------------------------------------------------------------------
-- Milestone claims.
-- ---------------------------------------------------------------------------
do
    local w = fresh()
    w:enter()
    w:play(180)
    w.flush(w.player)
    local writesBefore = w.writes
    w.calls = 0
    w.claim(w.player, {Minutes = 5})
    eq(w.writes, writesBefore, "a claim below the threshold writes nothing")
    eq(w.calls, 0, "a claim below the threshold does not even open a transaction")
    eq(w:lastPush().tone, "error", "and it is refused")
    eq(w:lastPush().message,
        "Play 5 minutes of a round today to claim this. You are at 3 minutes.",
        "the refusal says how far along the player is")
    eq(w:saved().Tokens, 10, "no tokens granted")
end

do
    local w = fresh()
    w:enter()
    w:play(300)
    w.flush(w.player)
    w.claim(w.player, {Minutes = 5})
    eq(w:saved().Tokens, 11, "the 5 minute milestone grants one token")
    eq(w:saved().Daily.Claimed["5"], true, "and records the claim")
    eq(w:lastPush().message, "1 Research Token collected -- 5 minutes of play today.",
        "the claim message names the reward and the milestone")
    eq(w:lastPush().tone, "success", "a granted claim is a success")
    local writes, calls = w.writes, w.calls
    w.claim(w.player, {Minutes = 5})
    eq(w:saved().Tokens, 11, "a second claim grants nothing")
    eq(w.writes, writes, "a second claim writes nothing")
    eq(w.calls, calls, "a second claim is refused in memory")
    eq(w:lastPush().message, "You already claimed the 5 minute reward today.", "and says so")
    w.claim(w.player, {Minutes = 15})
    eq(w:saved().Tokens, 11, "the 15 minute milestone is not reachable at 5 minutes")
    eq(w:saved().Items.SpeedPotion, 0, "and grants no potion")
end

-- A claim folds the seconds that have not been flushed yet, so a claim at
-- exactly 5:00 cannot be refused for the last few seconds.
do
    local w = fresh()
    w:seed({Tokens = 10, Daily = {Day = w.day, PlaytimeSeconds = 299, Claimed = {}}})
    w:enter()
    eq(w:saved().Daily.PlaytimeSeconds, 299, "299 seconds are durable")
    w:play(1)
    eq(w.playtime[w.player].unflushedSeconds, 1, "one second is still pending")
    local refusedAt = w.writes
    w.claim(w.player, {Minutes = 15})
    eq(w.writes, refusedAt, "a milestone that is still out of reach writes nothing")
    w.claim(w.player, {Minutes = 5})
    eq(w:saved().Tokens, 11, "the pending second completes the milestone")
    eq(w:saved().Daily.PlaytimeSeconds, 300, "and is banked by the same transaction")
    eq(w.playtime[w.player].unflushedSeconds, 0, "with nothing left pending")
end

-- Every milestone pays what the config says, once.
do
    local w = fresh()
    w:enter()
    w:play(2100)
    w.flush(w.player)
    w.claim(w.player, {Minutes = 5})
    w.claim(w.player, {Minutes = 15})
    w.claim(w.player, {Minutes = 35})
    local saved = w:saved()
    eq(saved.Tokens, 11, "5 minutes: one token")
    eq(saved.Items.SpeedPotion, 1, "15 minutes: one Speed Potion")
    eq(saved.Protection.Charges, 1, "35 minutes: one Entity Shield charge")
    eq(saved.Daily.Claimed["35"], true, "the last milestone is recorded")
    w.claim(w.player, {Minutes = 35})
    eq(w:saved().Protection.Charges, 1, "and cannot be claimed twice")
    for _, minutes in ipairs({0, 7, 60, -5}) do
        local writes = w.writes
        w.claim(w.player, {Minutes = minutes})
        eq(w.writes, writes, "an unknown milestone (" .. minutes .. ") is ignored")
    end
    for _, payload in ipairs({{}, {Minutes = "5"}, {Minutes = 0 / 0}}) do
        local writes = w.writes
        w.claim(w.player, payload)
        eq(w.writes, writes, "a malformed claim payload is ignored")
    end
end

-- An Entity Shield reward must not disturb the inventory operation identity.
do
    local w = fresh()
    w:seed({Tokens = 0, Daily = {Day = w.day, PlaytimeSeconds = 2100, Claimed = {}},
        Protection = {Charges = 2, Revision = 4, LastOperation = {SessionId = "s1",
            Revision = 4, Kind = "Buy", Status = "Bought"}}})
    w:enter()
    w.claim(w.player, {Minutes = 35})
    local protection = w:saved().Protection
    eq(protection.Charges, 3, "the reward adds a charge")
    eq(protection.Revision, 4, "Revision is untouched")
    eq(protection.LastOperation.SessionId, "s1", "LastOperation keeps its session")
    eq(protection.LastOperation.Status, "Bought", "LastOperation keeps its status")
    eq(protection.LastOperation.Revision, 4, "LastOperation keeps its revision")
end

-- A Protection table that does not validate is left alone for repair.
do
    local w = fresh()
    local seeded = w:seed({Tokens = 0, Daily = {Day = w.day, PlaytimeSeconds = 2100, Claimed = {}}})
    w:live().Protection = {Charges = -3, Revision = 0}
    w.db["u_501"].Protection = {Charges = -3, Revision = 0}
    w:enter()
    w.claim(w.player, {Minutes = 35})
    eq(w:saved().Daily.Claimed["35"], nil, "a reward that cannot be paid is not recorded as claimed")
    eq(w:lastPush().tone, "error", "and the player is told")
end

-- Two claims racing through the mutation lock grant exactly one reward.
do
    local w = fresh()
    w:enter()
    w:play(400)
    w.flush(w.player)
    w.pauseStore = true
    local first = coroutine.create(function() w.claim(w.player, {Minutes = 5}) end)
    local second = coroutine.create(function() w.claim(w.player, {Minutes = 5}) end)
    coroutine.resume(first)
    coroutine.resume(second)
    w.pauseStore = false
    local ok = coroutine.resume(first)
    check(ok, "first claim finished")
    for _ = 1, 50 do
        if coroutine.status(second) == "dead" then break end
        local resumed = coroutine.resume(second)
        check(resumed, "second claim advanced")
    end
    eq(w:saved().Tokens, 11, "two interleaved claims grant one token")
    eq(w:saved().Daily.Claimed["5"], true, "and record one claim")
end

-- ---------------------------------------------------------------------------
-- The supply wheel.
-- ---------------------------------------------------------------------------
do
    local total = 0
    for _, prize in ipairs(Config.DailyRewards.Wheel) do total += prize.Weight end
    eq(total, 100, "the published odds add up to 100")
    eq(#Config.DailyRewards.Wheel, 6, "six distinct prizes")
    eq(Config.DailyRewards.Wheel[1].Weight, 40, "the 1-Token wedge is 40%")
    eq(Config.DailyRewards.Wheel[6].Weight, 5, "the skin wedge is 5%")
end

do
    local w = fresh()
    w.random = function() return 0.0 end
    local spins = 20000
    local counts = {}
    for _ = 1, spins do
        local prize = w.pick()
        counts[prize.Key] = (counts[prize.Key] or 0) + 1
    end
    eq(counts.Token1, spins, "a pinned roll of 0 always lands on the first prize")
    w.random = nil
    local seen = {}
    for _ = 1, spins do
        local prize = w.pick()
        seen[prize.Key] = (seen[prize.Key] or 0) + 1
    end
    for _, prize in ipairs(Config.DailyRewards.Wheel) do
        local share = (seen[prize.Key] or 0) / spins * 100
        check(math.abs(share - prize.Weight) <= 1.5,
            string.format("%s lands %.2f%% of the time, weight says %d%%",
                prize.Key, share, prize.Weight))
    end
end

do
    -- WHEEL_COLLECT_20260922: a spin RECORDS, the claim PAYS, exactly once.
    local w = fresh()
    w.random = function() return 0.0 end
    w:enter()
    w.spin(w.player)
    eq(w:saved().Tokens, 10, "a spin records the prize and pays nothing yet")
    eq(w:saved().Daily.WheelDay, "2026-09-16", "and records the day")
    eq(w:saved().Daily.WheelLast.Key, "Token1", "and the prize")
    eq(w:saved().Daily.WheelLast.Serial, 1, "and a serial")
    eq(w:saved().Daily.WheelLast.Claimed, false, "and that it is still owed")
    eq(w:lastPush().message, "Supply Wheel: 1 Research Token -- collect your prize.", "the reply names the prize")
    eq(w:lastPush().data.Daily.WheelLast.Claimed, false, "the published profile carries the pending flag")
    local writes, calls = w.writes, w.calls
    -- Spinning again while a prize is owed is refused without a write, today or
    -- tomorrow, so a day change can never overwrite an uncollected prize.
    w.random = function() return 0.94 end
    w.spin(w.player)
    eq(w:saved().Daily.WheelLast.Key, "Token1", "a second spin cannot replace a pending prize")
    eq(w.writes, writes, "and writes nothing")
    eq(w.calls, calls, "and opens no transaction")
    eq(w:lastPush().message, "Collect your prize first: 1 Research Token.", "the reply says why")
    w.day = "2026-09-17"
    w.spin(w.player)
    eq(w:saved().Daily.WheelLast.Key, "Token1", "the free spin waits behind the uncollected prize")
    eq(w:saved().Daily.WheelDay, "2026-09-16", "the spin day is untouched")
    eq(w.writes, writes, "still no write")
    -- Collect: one atomic payout.
    w.collect(w.player)
    eq(w:saved().Tokens, 11, "the claim pays the recorded prize")
    eq(w:saved().Daily.WheelLast.Claimed, true, "and marks it collected in the same write")
    eq(w:saved().Daily.WheelLast.Serial, 1, "the serial is the receipt and does not change")
    eq(w:lastPush().message, "1 Research Token collected.", "the confirmation is the server's word")
    writes, calls = w.writes, w.calls
    w.collect(w.player)
    eq(w:saved().Tokens, 11, "a double click pays nothing more")
    eq(w.writes, writes, "and writes nothing")
    eq(w.calls, calls, "and opens no transaction")
    eq(w:lastPush().message, "Nothing to collect.", "the second claim is told there is nothing owed")
    -- A rejoin sees the same recorded, collected outcome.
    w:seed(w:saved())
    w.collect(w.player)
    eq(w:saved().Tokens, 11, "a rejoin cannot collect again")
    -- The day-2 free spin was not lost: it is available now that the prize is in.
    w.random = function() return 0.94 end
    w.spin(w.player)
    eq(w:saved().Daily.WheelDay, "2026-09-17", "the next day's spin is allowed after collection")
    eq(w:saved().Daily.WheelLast.Key, "Shield1", "and records the rolled prize")
    eq(w:saved().Daily.WheelLast.Serial, 2, "the serial advances")
    eq(w:saved().Daily.WheelLast.Claimed, false, "and it is owed")
    eq(w:saved().Protection.Charges, 0, "not paid before the claim")
    w.spin(w.player)
    eq(w:lastPush().message, "Collect your prize first: 1 Entity Shield.", "spent-spin replay while owed")
    w.collect(w.player)
    eq(w:saved().Protection.Charges, 1, "an Entity Shield prize is a stored charge, paid on claim")
    w.spin(w.player)
    eq(w:lastPush().message,
        "Today's spin is done: 1 Entity Shield. Next spin at 00:00 UTC.",
        "after collection the same-day replay re-reports the recorded prize")
end

-- Every result saved before the Claimed field existed was paid at spin time:
-- it normalizes to collected and a claim pays nothing.
do
    local w = fresh()
    w:seed({Tokens = 10, Daily = {Day = w.day, PlaytimeSeconds = 0, Claimed = {},
        WheelDay = w.day, WheelLast = {Day = w.day, Key = "Token3", Serial = 4}}})
    eq(w:saved().Daily.WheelLast.Claimed, true, "a historical result normalizes to claimed")
    local writes = w.writes
    w.collect(w.player)
    eq(w:saved().Tokens, 10, "and is never paid again")
    eq(w.writes, writes, "and the claim writes nothing")
    eq(w:lastPush().message, "Nothing to collect.", "the reply says so")
    eq(w:saved().Daily.WheelLast.Serial, 4, "the serial is kept")
end

-- The outcome is durable before the reply: a spin whose write never lands
-- records nothing and can be spun again; a claim whose write never lands
-- leaves the prize owed and pays once on the retry.
do
    local w = fresh()
    w.random = function() return 0.0 end
    w:enter()
    w.failBefore = true
    w.spin(w.player)
    w.failBefore = false
    eq(w:saved().Daily.WheelDay, nil, "a failed spin records no day")
    eq(w:saved().Tokens, 10, "and pays nothing")
    w.spin(w.player)
    eq(w:saved().Daily.WheelDay, "2026-09-16", "the retry spins for real")
    eq(w:saved().Daily.WheelLast.Claimed, false, "and the prize is owed")
    w.failBefore = true
    w.collect(w.player)
    w.failBefore = false
    eq(w:saved().Tokens, 10, "a failed claim pays nothing")
    eq(w:saved().Daily.WheelLast.Claimed, false, "and the prize is still owed")
    eq(w:lastPush().message, "Could not save that change. Please try again.", "the client is told to retry")
    w.collect(w.player)
    eq(w:saved().Tokens, 11, "the retry pays once")
    eq(w:saved().Daily.WheelLast.Claimed, true, "and closes the prize")
    -- Committed but the response was lost: the retry finds it collected.
    w.day = "2026-09-17"
    w.spin(w.player)
    w.failAfter = true
    w.collect(w.player)
    eq(w:saved().Tokens, 12, "the lost-response claim was committed")
    w.collect(w.player)
    eq(w:saved().Tokens, 12, "and the retry pays nothing more")
end

-- Every wheel prize pays the reward its config declares -- on the claim.
do
    local payouts = {
        Token1 = function(d) return d.Tokens - 10 == 1 end,
        Token3 = function(d) return d.Tokens - 10 == 3 end,
        Potion1 = function(d) return d.Items.SpeedPotion == 1 end,
        Potion2 = function(d) return d.Items.SpeedPotion == 2 end,
        Shield1 = function(d) return d.Protection.Charges == 1 end,
        Skin5 = function(d) return d.Skins.Owned.SuburbSurvey == true end,
    }
    local untouched = function(d) return d.Tokens == 10 and d.Items.SpeedPotion == 0 and d.Protection.Charges == 0 end
    local edge = 0
    for index, prize in ipairs(Config.DailyRewards.Wheel) do
        local w = fresh()
        -- Land exactly inside this prize's slice.
        local pinned = (edge + prize.Weight * 0.5) / 100
        edge += prize.Weight
        w.random = function() return pinned end
        w:enter()
        w.spin(w.player)
        eq(w:saved().Daily.WheelLast.Key, prize.Key, "slice " .. index .. " selects " .. prize.Key)
        check(untouched(w:saved()), prize.Key .. " pays nothing at spin")
        local expectedLabel = prize.Key == "Skin5" and "Suburb Survey hazmat skin" or prize.Label
        eq(w:lastPush().message, "Supply Wheel: " .. expectedLabel .. " -- collect your prize.", prize.Key .. " reply")
        w.collect(w.player)
        check(payouts[prize.Key](w:saved()), prize.Key .. " pays what its config declares on claim")
    end
end

-- The 5% field chooses one exact unowned Token skin at spin time, carries that
-- ID over a rejoin, and grants it only on the first claim.
do
    local w = fresh()
    local rolls, index = {0.97, 0.1}, 0
    w.random = function()
        index += 1
        return rolls[index] or 0.1
    end
    w.spin(w.player)
    local last = w:saved().Daily.WheelLast
    eq(last.Key, "Skin5", "the 5% slice remains the skin sector")
    eq(last.SkinId, "PoolService", "the exact unowned suit is selected at spin")
    eq(last.FallbackTokens, nil, "an available skin does not get a fallback")
    eq(w:saved().Skins.Owned.PoolService, nil, "spinning pays nothing")
    eq(w:lastPush().message, "Supply Wheel: Pool Service hazmat skin -- collect your prize.",
        "the response names the selected suit")
    w:seed(w:saved())
    eq(w:saved().Daily.WheelLast.SkinId, "PoolService", "a rejoin keeps the exact SkinId")
    w.collect(w.player)
    eq(w:saved().Skins.Owned.PoolService, true, "the first claim grants that suit")
    eq(w:saved().Tokens, 10, "claiming a skin does not spend or mint Tokens")
    local writes = w.writes
    w.collect(w.player)
    eq(w.writes, writes, "a repeated skin claim makes no second write")
end

-- Players who own both wheel suits still land on the 5% skin field. The
-- disclosed 3-Token fallback is chosen before the spin record is published.
do
    local w = fresh()
    w:seed({Tokens = 10, Skins = {Owned = {PoolService = true, SuburbSurvey = true}},
        Daily = {Day = w.day, PlaytimeSeconds = 0, Claimed = {}}})
    w.random = function() return 0.99 end
    w.spin(w.player)
    local last = w:saved().Daily.WheelLast
    eq(last.Key, "Skin5", "all-owned still lands on the skin sector")
    eq(last.SkinId, nil, "all-owned does not invent another suit")
    eq(last.FallbackTokens, 3, "the fallback amount is durable at spin")
    w:seed(w:saved())
    eq(w:saved().Daily.WheelLast.FallbackTokens, 3, "the fallback survives rejoin")
    eq(w:lastPush().message, "Supply Wheel: 3 Research Tokens (skin fallback) -- collect your prize.",
        "the actual fallback is disclosed")
    w.collect(w.player)
    eq(w:saved().Tokens, 13, "fallback pays three Tokens exactly once")
    eq(w:saved().Daily.WheelLast.Claimed, true, "fallback claim closes the spin")
    local writes = w.writes
    w.collect(w.player)
    eq(w.writes, writes, "duplicate fallback claim writes nothing")
end

-- A player can buy the selected skin after spinning. They get the fallback on
-- claim, while the original SkinId remains an auditable receipt.
do
    local w = fresh()
    local rolls, index = {0.97, 0.1}, 0
    w.random = function() index += 1; return rolls[index] or 0.1 end
    w.spin(w.player)
    local saved = w:saved()
    saved.Skins.Owned.PoolService = true
    w:seed(saved)
    w.collect(w.player)
    eq(w:saved().Tokens, 13, "a newly owned win pays the fallback")
    eq(w:saved().Daily.WheelLast.SkinId, "PoolService", "the spun ID remains recorded")
    eq(w:saved().Daily.WheelLast.FallbackTokens, 3, "the actual claim outcome is recorded")
    w:seed(w:saved())
    eq(w:saved().Daily.WheelLast.SkinId, "PoolService", "the receipt survives rejoin")
end

-- A pre-upgrade pending prize must still be redeemable under the six-field
-- config, including the old two-Potion wedge that stayed at 5%.
do
    local w = fresh()
    w:seed({Tokens = 10, Daily = {Day = w.day, WheelDay = w.day,
        WheelLast = {Day = w.day, Key = "Potion2", Serial = 42, Claimed = false}}})
    w.spin(w.player)
    eq(w:saved().Daily.WheelLast.Key, "Potion2", "pending old prize cannot be replaced")
    w.collect(w.player)
    eq(w:saved().Items.SpeedPotion, 2, "old pending Potion2 pays both Potions")
    eq(w:saved().Daily.WheelLast.Claimed, true, "and becomes claimed")
end

-- ---------------------------------------------------------------------------
-- BuyItem and the Speed Potion.
-- ---------------------------------------------------------------------------
do
    local w = fresh()
    w.buy(w.player, {Key = "SpeedPotion"})
    eq(w:saved().Tokens, 7, "a potion costs three tokens")
    eq(w:saved().Items.SpeedPotion, 1, "and is stored")
    eq(w:lastPush().message, "Speed Potion stored (1 owned).", "the reply counts what is owned")
    w.buy(w.player, {Key = "SpeedPotion"})
    eq(w:lastPush().message, "Speed Potion stored (2 owned).", "the count grows")
    eq(w:saved().Tokens, 4, "tokens are spent each time")
    w.buy(w.player, {Key = "RouteMarker"})
    eq(w:saved().Items.RouteMarker, 3, "a marker pack is three markers")
    eq(w:saved().Tokens, 2, "and costs two tokens")
    local writes, calls = w.writes, w.calls
    w.buy(w.player, {Key = "SpeedPotion"})
    eq(w:saved().Items.SpeedPotion, 2, "two tokens cannot buy a three token potion")
    eq(w.writes, writes, "a refusal writes nothing")
    eq(w.calls, calls, "a refusal opens no transaction")
    eq(w:lastPush().message, "You need 3 Research Tokens.", "and names the price")
    for _, payload in ipairs({{}, {Key = "EntityShield"}, {Key = 5}, "SpeedPotion"}) do
        local before = w.writes
        w.buy(w.player, payload)
        eq(w.writes, before, "an unknown BuyItem payload is ignored")
    end
end

do
    local uses = {
        {name = "no round", setup = function(w) end,
            message = "Not in a round."},
        {name = "loading", setup = function(w)
            w:enter(); w.workspace:SetAttribute("RoundLoadingState", "loading") end,
            message = "Not in a round."},
        {name = "escaped", setup = function(w)
            w:enter(); w.player:SetAttribute("Escaped", true) end,
            message = "Not in a round."},
        {name = "exit transition", setup = function(w)
            w:enter(); w.player:SetAttribute("Level2_ExitTransition", true) end,
            message = "Not in a round."},
        {name = "dead", setup = function(w)
            local c = w.character(0); c.Humanoid.Health = 0; w:enter(c) end,
            message = "Not in a round."},
        {name = "hiding", setup = function(w)
            w:enter(); w.player:SetAttribute("Level3_Hiding", true) end,
            message = "Not while hiding."},
    }
    for _, case in ipairs(uses) do
        local w = fresh()
        w:seed({Tokens = 0, Items = {SpeedPotion = 2, RouteMarker = 0},
            Daily = {Day = w.day, PlaytimeSeconds = 0, Claimed = {}}})
        case.setup(w)
        local writes = w.writes
        w.potion(w.player)
        eq(w:lastPush().message, case.message, case.name .. " refusal message")
        eq(w:lastPush().tone, "error", case.name .. " is an error")
        eq(w.writes, writes, case.name .. " writes nothing")
        eq(w:saved().Items.SpeedPotion, 2, case.name .. " consumes nothing")
        eq(w.player:GetAttribute("ZyntraSpeedBoostUntil"), 0, case.name .. " sets no boost")
    end
end

do
    local w = fresh()
    w:seed({Tokens = 0, Items = {SpeedPotion = 0, RouteMarker = 0},
        Daily = {Day = w.day, PlaytimeSeconds = 0, Claimed = {}}})
    w:enter()
    local writes = w.writes
    w.potion(w.player)
    eq(w:lastPush().message, "No Speed Potion stored.", "an empty inventory refuses by name")
    eq(w.writes, writes, "and writes nothing")
end

do
    local w = fresh()
    w:seed({Tokens = 0, Items = {SpeedPotion = 2, RouteMarker = 0},
        Daily = {Day = w.day, PlaytimeSeconds = 0, Claimed = {}}})
    w:enter()
    w:tick(3)
    w.potion(w.player)
    eq(w:saved().Items.SpeedPotion, 1, "one potion is consumed")
    eq(w.player:GetAttribute("ZyntraSpeedBoostUntil"), w.now + 6, "the boost ends six seconds out")
    eq(w.player:GetAttribute("ZyntraSpeedBoostMultiplier"), Config.Items.SpeedPotion.SpeedMultiplier,
        "at the configured boost (1.30 since the +30% potion; the old literal 1.1 was stale)")
    eq(w.player:GetAttribute("ZyntraSpeedPotionUsedThisRound"), true, "and the round is marked")
    eq(w.player:GetAttribute("ZyntraSpeedPotions"), 1, "the stored count is republished")
    eq(w:lastPush().message, "Speed Potion: +30% speed for 6 seconds.", "the reply states the effect")
    eq(w.publicProfile(w:live(), w.player).SpeedBoostUntil, w.now + 6,
        "the payload carries the boost deadline")
    -- Second use inside the same round.
    local writes = w.writes
    w.potion(w.player)
    eq(w:saved().Items.SpeedPotion, 1, "a second potion cannot be used in the same round")
    eq(w.writes, writes, "and writes nothing")
    eq(w:lastPush().message, "Already used this round.", "and says why")
    -- Expiry.
    w:tick(7)
    eq(w.player:GetAttribute("ZyntraSpeedBoostUntil"), 0, "the boost expires on its own")
    eq(w.player:GetAttribute("ZyntraSpeedBoostMultiplier"), 1, "and the multiplier returns to 1")
    eq(w.player:GetAttribute("ZyntraSpeedPotionUsedThisRound"), true,
        "but the round is still marked as used")
    -- A new round.
    w.workspace:SetAttribute("RoundActive", false)
    w.workspace:SetAttribute("RoundActive", true)
    eq(w.player:GetAttribute("ZyntraSpeedPotionUsedThisRound"), false, "a new round clears the mark")
    w:enter()
    w.potion(w.player)
    eq(w:saved().Items.SpeedPotion, 0, "and allows one more potion")
    eq(w.player:GetAttribute("ZyntraSpeedBoostMultiplier"), Config.Items.SpeedPotion.SpeedMultiplier, "with the boost applied again")
end

-- Death, leaving the round and the round ending all clear the boost.
do
    local clears = {
        {name = "death", act = function(w) w.player.Character.Humanoid.Died:Fire() end},
        {name = "leaving the round", act = function(w) w.player:SetAttribute("InRound", false) end},
        {name = "round end", act = function(w) w.workspace:SetAttribute("RoundActive", false) end},
        {name = "level change", act = function(w) w.workspace:SetAttribute("SelectedLevel", 3) end},
        {name = "respawn", act = function(w) w.player.CharacterAdded:Fire(w.character(0)) end},
        {name = "character removing", act = function(w) w.player.CharacterRemoving:Fire() end},
    }
    for _, case in ipairs(clears) do
        local w = fresh()
        w:seed({Tokens = 0, Items = {SpeedPotion = 1, RouteMarker = 0},
            Daily = {Day = w.day, PlaytimeSeconds = 0, Claimed = {}}})
        w:enter()
        w.potion(w.player)
        eq(w.player:GetAttribute("ZyntraSpeedBoostMultiplier"), Config.Items.SpeedPotion.SpeedMultiplier, case.name .. ": boost is on")
        case.act(w)
        eq(w.player:GetAttribute("ZyntraSpeedBoostUntil"), 0, case.name .. " clears the deadline")
        eq(w.player:GetAttribute("ZyntraSpeedBoostMultiplier"), 1, case.name .. " clears the multiplier")
    end
end

-- The round boundary also banks the playtime that round earned.
do
    local w = fresh()
    w:enter()
    w:tick(40)
    w.workspace:SetAttribute("RoundActive", false)
    w:run()
    eq(w:saved().Daily.PlaytimeSeconds, 40, "the round end flushes what was played")
    eq(w.playtime[w.player].unflushedSeconds, 0, "with nothing left pending")
end

-- The line finalizePlayerSessionBody runs before it closes the session.
do
    local w = fresh()
    w:enter()
    w:tick(25)
    w:leaveFlush()
    eq(w:saved().Daily.PlaytimeSeconds, 25, "leaving banks the unflushed seconds")
    eq(w.playtime[w.player].unflushedSeconds, 0, "and clears them")
end

-- The periodic flush runs on its own, without anyone asking.
do
    local w = fresh()
    w:enter()
    w:tick(65)
    check(w:saved().Daily.PlaytimeSeconds >= 60,
        "the accrual loop flushes on its own interval")
    check(w.playtime[w.player].unflushedSeconds <= 5, "leaving only the newest seconds pending")
end

-- ---------------------------------------------------------------------------
-- Attributes, schema defaults and the Studio branch.
-- ---------------------------------------------------------------------------
do
    local w = fresh()
    local legacy = w.normalize({Tokens = 4, UnknownLegacy = {kept = true}})
    eq(legacy.Items.SpeedPotion, 0, "a save without Items normalizes to zero")
    eq(legacy.Items.RouteMarker, 0, "both items")
    eq(legacy.Daily.PlaytimeSeconds, 0, "a save without Daily normalizes to zero")
    eq(legacy.Daily.Day, nil, "and belongs to no day until the first transaction")
    eq(legacy.FieldNotes.Serial, 0, "a save without FieldNotes normalizes")
    eq(legacy.Version, 4, "the schema version does not move")
    check(legacy.UnknownLegacy.kept, "unknown keys are preserved")
    for _, bad in ipairs({-1, 1.5, 0 / 0, math.huge, -math.huge, "3", {}, true, 9007199254740992}) do
        local repaired = w.normalize({Items = {SpeedPotion = bad, RouteMarker = bad},
            Daily = {PlaytimeSeconds = bad, Claimed = {["5"] = bad}},
            FieldNotes = {Discovered = {["L1-01"] = bad}, Serial = bad}})
        eq(repaired.Items.SpeedPotion, 0, "a malformed potion count becomes zero")
        eq(repaired.Items.RouteMarker, 0, "a malformed marker count becomes zero")
        eq(repaired.Daily.PlaytimeSeconds, 0, "malformed playtime becomes zero")
        eq(repaired.FieldNotes.Serial, 0, "a malformed note serial becomes zero")
    end
    for _, bad in ipairs({1, "true", 0, {}, "yes"}) do
        local repaired = w.normalize({Daily = {Claimed = {["5"] = bad}},
            FieldNotes = {Discovered = {["L1-01"] = bad}}})
        eq(repaired.Daily.Claimed["5"], nil, "a claim flag that is not true is dropped")
        eq(repaired.FieldNotes.Discovered["L1-01"], nil, "a note flag that is not true is dropped")
    end
    local junk = w.normalize({Items = "nope", Daily = 7, FieldNotes = false,
        Daily2 = nil})
    eq(junk.Items.SpeedPotion, 0, "a malformed Items table is replaced")
    eq(junk.Daily.PlaytimeSeconds, 0, "a malformed Daily table is replaced")
    eq(junk.FieldNotes.Serial, 0, "a malformed FieldNotes table is replaced")
    local unknownMilestone = w.normalize({Daily = {Day = "2026-09-16",
        Claimed = {["5"] = true, ["999"] = true}}})
    eq(unknownMilestone.Daily.Claimed["5"], true, "a known milestone claim survives")
    eq(unknownMilestone.Daily.Claimed["999"], nil, "an unknown milestone claim cannot be injected")
    local badDay = w.normalize({Daily = {Day = "yesterday", WheelDay = 20260916,
        WheelLast = {Key = 7}}})
    eq(badDay.Daily.Day, nil, "a day that is not a date is dropped")
    eq(badDay.Daily.WheelDay, nil, "a wheel day that is not a date is dropped")
    eq(badDay.Daily.WheelLast, nil, "a prize record without a key is dropped")
end

do
    local w = fresh()
    w.buy(w.player, {Key = "RouteMarker"})
    eq(w.player:GetAttribute("ZyntraRouteMarkers"), 3, "markers are published as an attribute")
    eq(w.player:GetAttribute("ZyntraSpeedPotions"), 0, "so are potions")
    eq(w.player:GetAttribute("ZyntraFieldNotesTitle"), nil,
        "FIELD_NOTES_REMOVED_20260922: no completion title is published any more")
    local public = w.publicProfile(w:live(), w.player)
    eq(public.Items.RouteMarker, 3, "the payload carries the inventory")
    eq(public.FieldNotes, nil, "and no field-note collection")
    eq(public.SpeedBoostUntil, 0, "and no boost")
end

-- Studio: no DataStore at all, and every path still works in memory.
do
    local w = fresh({studio = true})
    w:enter()
    w:play(300)
    w.flush(w.player)
    eq(w.calls, 0, "Studio never touches the DataStore")
    eq(w:live().Daily.PlaytimeSeconds, 300, "Studio banks playtime in the session copy")
    w.claim(w.player, {Minutes = 5})
    eq(w:live().Tokens, 11, "Studio grants the milestone")
    w.random = function() return 0.0 end
    w.spin(w.player)
    eq(w:live().Tokens, 11, "Studio spins the wheel and records the prize")
    eq(w:live().Daily.WheelDay, "2026-09-16", "and records it in memory")
    eq(w:live().Daily.WheelLast.Claimed, false, "owed until collected")
    w.collect(w.player)
    eq(w:live().Tokens, 12, "Studio pays the prize on the claim")
    w.spin(w.player)
    eq(w:live().Tokens, 12, "and refuses the second spin the same way")
    w.buy(w.player, {Key = "SpeedPotion"})
    eq(w:live().Items.SpeedPotion, 1, "Studio buys the potion")
    w.potion(w.player)
    eq(w:live().Items.SpeedPotion, 0, "and uses it")
    eq(w.player:GetAttribute("ZyntraSpeedBoostMultiplier"), Config.Items.SpeedPotion.SpeedMultiplier, "with the boost applied")
    eq(w.calls, 0, "still no DataStore access anywhere")
end

-- The actual profile push must not count the just-committed flush twice.
do
    local w = fresh()
    w:enter(); w:tick(30); w.flush(w.player)
    eq(w:lastPush().data.Daily.PlaytimeSeconds, 30, "flush payload counts committed seconds once")
end

-- Midnight expires yesterday's unflushed time before any action or tick.
do
    local w = fresh()
    w:enter(); w:tick(30)
    w.failAfter = true
    w.flush(w.player)
    w:tick(10)
    w.flush(w.player)
    eq(w:saved().Daily.PlaytimeSeconds, 30, "lost-response retry recognises the original fixed delta")
    eq(w.playtime[w.player].unflushedSeconds, 10, "time earned after the lost response survives")
    w.flush(w.player)
    eq(w:saved().Daily.PlaytimeSeconds, 40, "later time lands under its own flush identity")
end

-- Midnight expires yesterday's unflushed time before any action or tick.
do
    local w = fresh()
    w:enter(); w:tick(30)
    w.day = "2026-09-17"
    eq(w:total(), 0, "yesterday's pending time is not today's progress")
    w:tick(5); w.flush(w.player)
    eq(w:saved().Daily.PlaytimeSeconds, 5, "only today's seconds are banked after midnight")
end

-- Rejoining the same job creates a fresh flush identity.
do
    local w = fresh()
    w:enter(); w:tick(30); w.flush(w.player)
    w.playtime[w.player] = nil
    w:tick(10); w.flush(w.player)
    eq(w:saved().Daily.PlaytimeSeconds, 40, "same-server rejoin cannot collide with an earlier flush id")
end

-- A second daily action waits for the existing profile lock, then snapshots.
do
    local w = fresh()
    w:enter(); w:tick(20)
    w.pauseStore = true
    local first = coroutine.create(function() w.flush(w.player) end)
    check(coroutine.resume(first), "first flush started")
    w:tick(5)
    local second = coroutine.create(function() w.flush(w.player) end)
    check(coroutine.resume(second), "second flush waits")
    w.pauseStore = false
    check(coroutine.resume(first), "first flush resumes")
    check(coroutine.resume(second), "second flush resumes")
    eq(w:saved().Daily.PlaytimeSeconds, 25, "queued flush snapshots only after acquiring the lock")
    eq(w.playtime[w.player].unflushedSeconds, 0, "queued flush does not discard later earned seconds")
end

print(string.format("daily rewards: %d checks passed", checks))
'''


def main():
    luau = os.environ.get("LUAU_BIN") or shutil.which("luau")
    if not luau:
        raise SystemExit("Set LUAU_BIN or put luau on PATH")
    leave = next(line.strip() for line in SERVER.splitlines()
                 if "if session and not session.closing then flushPlaytime(player) end" in line)
    pieces = [
        PRELUDE,
        CONFIG,
        WORLD.replace("RESEARCH_SOURCE", RESEARCH).replace("CHALLENGES_SOURCE", CHALLENGES)
             .replace("SKINS_SOURCE", SKINS),
        section("local function colorData", "local function isDispatchPredecessorClosed"),
        section("local function accessibilityValue", "-- The switch a player"),
        section("local function publicProfile", "local tagCharacters"),
        section("local function applyAttributes", "local function enrichedPublicProfile"),
        PUSH,
        section("local function acquireMutation", "-- Developer token gifts"),
        section("-- Daily rewards, stored items and the inventory service",
                "-- Actions that open a DataStore write get a window"),
        TAIL.replace("LEAVE_FLUSH", leave),
        TESTS,
    ]
    with tempfile.TemporaryDirectory(prefix="daily-rewards-") as directory:
        path = Path(directory) / "daily_rewards.luau"
        path.write_text("\n".join(pieces), encoding="utf-8")
        result = subprocess.run([luau, str(path)], capture_output=True, text=True, timeout=180)
    if result.stdout:
        print(result.stdout, end="")
    if result.stderr:
        print(result.stderr, end="")
    raise SystemExit(result.returncode)


if __name__ == "__main__":
    main()
