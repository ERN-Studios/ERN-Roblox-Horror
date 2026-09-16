"""ServerStorage.ZyntraInventory, BuyItem, field notes and the leaderboard columns.

Runs the REAL blocks out of ZyntraMonetization.Script.lua -- the profile helpers,
publicProfile, applyAttributes, refreshPlayerTags, mutate, the daily-rewards
section that owns the inventory BindableFunction, and the support-leaderboard
publisher -- under the real Luau interpreter against a fake DataStore and a fake
DataModel that holds a ZyntraFieldNotes module.

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
local UDim2 = {fromOffset = function() return {} end, fromScale = function() return {} end}
local Vector2 = {new = function() return {} end}
local Vector3 = {new = vec}
local Enum = {Font = {GothamBold = "GothamBold"}}
local Config = (function()
'''

WORLD = r'''
end)()

local NOTES = {
    Notes = {
        {Id = "L1-02", Level = 1, Title = "Wet Return Duct", Body = "b", Stamp = "s"},
        {Id = "L1-01", Level = 1, Title = "Intake Log", Body = "b", Stamp = "s"},
        {Id = "L2-01", Level = 2, Title = "Pump Room Slate", Body = "b", Stamp = "s"},
        {Id = "L3-01", Level = 3, Title = "Mall Manifest", Body = "b", Stamp = "s"},
    },
}

local function world(opts)
    opts = opts or {}
    local w = {
        now = 0, epoch = 1789516800, day = "2026-09-16",
        db = {}, tasks = {}, waiting = {}, pushes = {}, warnings = {},
        calls = 0, writes = 0, tagRefreshes = 0, names = {},
        studio = false, notes = opts.notes,
    }
    local function warn(...) table.insert(w.warnings, {...}) end
    local os = {
        time = function() return w.epoch end,
        clock = function() return w.now end,
        date = function() return w.day end,
    }
    local game = {JobId = "job-1"}
    local RunService = {IsStudio = function() return w.studio end}
    local DevAccess = {IsAllowed = function() return w.developer == true end}

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
    function w:runUntil(deadline)
        local steps = 0
        while true do
            table.sort(self.tasks, function(a, b) return a.at < b.at end)
            local item = self.tasks[1]
            if not item or item.at > deadline then break end
            table.remove(self.tasks, 1)
            steps += 1
            assert(steps < 50000, "scheduler did not settle")
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
    function w:tick(seconds) self:runUntil(self.now + seconds) end

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
    function Players:GetNameFromUserIdAsync(userId) return "Donor" .. userId end
    local function typeof(value)
        return type(value) == "table" and value.ClassName and "Instance" or type(value)
    end

    -- A Roblox-shaped instance: enough of one that the real tag code and the real
    -- leaderboard attribute writes run unchanged.
    local function instance(class, name)
        local object = {ClassName = class, Name = name or "", Parent = nil,
            attributes = {}, children = {}, Value = ""}
        object.ChildAdded = signal()
        function object:IsA(other) return other == class end
        function object:SetAttribute(key, value) self.attributes[key] = value end
        function object:GetAttribute(key) return self.attributes[key] end
        function object:FindFirstChild(childName)
            for _, child in ipairs(self.children) do
                if child.Name == childName then return child end
            end
            return nil
        end
        function object:GetChildren()
            local copy = {}
            for index, child in ipairs(self.children) do copy[index] = child end
            return copy
        end
        function object:Destroy() self.Parent = nil end
        -- Parent is a real property here: the tag code parents a BillboardGui and
        -- then the next refresh has to find it again to clear it.
        return setmetatable(object, {
            __index = function(t, key)
                if key == "Parent" then return rawget(t, "_parent") end
                return nil
            end,
            __newindex = function(t, key, value)
                if key ~= "Parent" then rawset(t, key, value) return end
                local old = rawget(t, "_parent")
                if old then
                    for index, child in ipairs(old.children) do
                        if child == t then table.remove(old.children, index) break end
                    end
                end
                rawset(t, "_parent", value)
                if value then table.insert(value.children, t) end
            end,
        })
    end
    w.instance = instance
    local Instance = {new = function(class) return instance(class) end}

    local ReplicatedStorage = instance("Folder", "ReplicatedStorage")
    if w.notes ~= false then
        local module = instance("ModuleScript", "ZyntraFieldNotes")
        module.content = w.notes or NOTES
        table.insert(ReplicatedStorage.children, module)
    end
    local function require(module) return module.content end

    local ServerStorage = instance("Folder", "ServerStorage")

    local function makeCharacter()
        local humanoid = {ClassName = "Humanoid", Health = 100, Died = signal()}
        function humanoid:IsA(class) return class == "Humanoid" end
        local head = instance("BasePart", "Head")
        local c = {Humanoid = humanoid, Head = head,
            HumanoidRootPart = {Name = "HumanoidRootPart", Position = vec(0, 0, 0)}}
        function c:FindFirstChildOfClass(class)
            return class == "Humanoid" and self.Humanoid or nil
        end
        function c:FindFirstChild(name) return rawget(self, name) end
        function c:IsDescendantOf() return true end
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
    local player = makePlayer("Collector", 701)
    w.player = player
    w.stranger = {Name = "NotAPlayer"}

    local store = {}
    function store:UpdateAsync(key, transform)
        w.calls += 1
        if w.failBefore then error("Profile write unavailable") end
        local result = transform(clone(w.db[key]))
        if result then w.db[key] = clone(result); w.writes += 1 end
        return clone(result)
    end

    local sessions, mutationLocks = {}, {}
    local serverClosing = false
    local ACCESSIBILITY_SETTINGS = Config.AccessibilitySettings
    local PERCENT_PER_LEVEL = math.floor(Config.TokenPercentPerLevel * 100 + 0.5)
    local SUPPORT_LEADERBOARD_SIZE = Config.SupportLeaderboardSize
    local supportStatus = instance("StringValue", "Status")
    local supportRows = {}
    for rank = 1, SUPPORT_LEADERBOARD_SIZE do
        supportRows[rank] = instance("StringValue", string.format("Row%02d", rank))
    end
    local function applyHazmatColor() end
    local function reassertPendingAccessibility() end
    local Random = {new = function() return {NextNumber = function() return 0 end} end}
'''

PUSH = r'''
    local function pushProfile(p, message, tone)
        local session = sessions[p]
        table.insert(w.pushes, {player = p, message = message, tone = tone,
            data = session and publicProfile(session.data, p) or nil})
    end
'''

TAIL = r'''
    w.sessions, w.rows, w.status = sessions, supportRows, supportStatus
    w.publicProfile, w.normalize = publicProfile, normalizeProfile
    w.buy, w.inventory, w.publish = buyItem, inventoryFunction, publishSupportRows
    w.tags = function() return player.Character.Head:GetChildren() end
    function w:seed(profile)
        local key = "u_" .. player.UserId
        self.db[key] = normalizeProfile(profile)
        sessions[player] = {data = normalizeProfile(clone(self.db[key])), persistent = true}
        -- What loadProfile does once the profile is in hand.
        applyAttributes(player, sessions[player].data)
        player.Character = self.character()
        player.CharacterAdded:Fire(player.Character)
        tagCharacters[player] = player.Character
        refreshPlayerTags(player, player.Character)
        return self.db[key]
    end
    function w:saved() return self.db["u_" .. player.UserId] end
    function w:live() return sessions[player].data end
    function w:lastPush() return self.pushes[#self.pushes] end
    function w:refreshTags() refreshPlayerTags(player, player.Character) end
    return w
end

local function fresh(opts)
    local w = world(opts)
    w:seed({Tokens = 10})
    return w
end
'''

TESTS = r'''
-- ---------------------------------------------------------------------------
-- BuyItem: token spend and inventory add in one transaction.
-- ---------------------------------------------------------------------------
do
    local w = fresh()
    eq(w:saved().Items.SpeedPotion, 0, "a new profile owns no potions")
    eq(w:saved().Items.RouteMarker, 0, "and no markers")
    w.buy(w.player, {Key = "SpeedPotion"})
    eq(w:saved().Tokens, 7, "the potion costs three tokens")
    eq(w:saved().Items.SpeedPotion, 1, "and adds one potion")
    eq(w.writes, 1, "in one write")
    w.buy(w.player, {Key = "RouteMarker"})
    eq(w:saved().Tokens, 5, "the pack costs two tokens")
    eq(w:saved().Items.RouteMarker, 3, "and adds three markers")
    eq(w:lastPush().message, "Route Marker Pack stored (3 owned).", "the reply counts markers")
    eq(w.player:GetAttribute("ZyntraRouteMarkers"), 3, "and the attribute is republished")
    eq(w.player:GetAttribute("ZyntraSpeedPotions"), 1, "so is the potion count")
end

do
    local w = fresh()
    w:seed({Tokens = 2})
    local writes, calls = w.writes, w.calls
    w.buy(w.player, {Key = "SpeedPotion"})
    eq(w:saved().Items.SpeedPotion, 0, "two tokens cannot buy a three token potion")
    eq(w:saved().Tokens, 2, "and no tokens are spent")
    eq(w.writes, writes, "a refusal writes nothing")
    eq(w.calls, calls, "a refusal opens no transaction")
    eq(w:lastPush().message, "You need 3 Research Tokens.", "and names the price")
    w.buy(w.player, {Key = "RouteMarker"})
    eq(w:saved().Items.RouteMarker, 3, "two tokens do buy a marker pack")
    eq(w:saved().Tokens, 0, "spending the last token")
    w.buy(w.player, {Key = "RouteMarker"})
    eq(w:saved().Items.RouteMarker, 3, "and an empty balance buys nothing")
    eq(w:lastPush().message, "You need 2 Research Tokens.", "with the pack's own price")
end

-- A buy that never reaches the store grants nothing and spends nothing.
do
    local w = fresh()
    w.failBefore = true
    w.buy(w.player, {Key = "SpeedPotion"})
    w.failBefore = false
    eq(w:saved().Tokens, 10, "a failed write spends no tokens")
    eq(w:saved().Items.SpeedPotion, 0, "and stores no item")
    w.buy(w.player, {Key = "SpeedPotion"})
    eq(w:saved().Items.SpeedPotion, 1, "the retry buys exactly one")
    eq(w:saved().Tokens, 7, "for exactly one price")
end

-- ---------------------------------------------------------------------------
-- ZyntraInventory: Count.
-- ---------------------------------------------------------------------------
do
    local w = fresh()
    w.buy(w.player, {Key = "RouteMarker"})
    eq(w.inventory.OnInvoke("Count", w.player, "RouteMarker"), 3, "Count reads the inventory")
    eq(w.inventory.OnInvoke("Count", w.player, "SpeedPotion"), 0, "including an empty one")
    eq(w.inventory.OnInvoke("Count", w.player, "EntityShield"), 0,
        "a shield is not an item and counts as zero")
    eq(w.inventory.OnInvoke("Count", w.player, "Nonsense"), 0, "an unknown key counts as zero")
    eq(w.inventory.OnInvoke("Count", w.player, 5), 0, "a non-string key counts as zero")
    eq(w.inventory.OnInvoke("Count", w.stranger, "RouteMarker"), 0, "a non-Player counts as zero")
    eq(w.inventory.OnInvoke("Count", nil, "RouteMarker"), 0, "no player counts as zero")
    w.sessions[w.player] = nil
    eq(w.inventory.OnInvoke("Count", w.player, "RouteMarker"), 0,
        "an unloaded profile counts as zero")
end

-- ---------------------------------------------------------------------------
-- ZyntraInventory: Consume.
-- ---------------------------------------------------------------------------
do
    local w = fresh()
    w.buy(w.player, {Key = "RouteMarker"})
    local writes = w.writes
    local ok, message = w.inventory.OnInvoke("Consume", w.player, "RouteMarker", 1)
    eq(ok, true, "Consume spends one marker")
    eq(message, "", "with no refusal message")
    eq(w:saved().Items.RouteMarker, 2, "durably")
    eq(w.writes, writes + 1, "in one write")
    eq(w.player:GetAttribute("ZyntraRouteMarkers"), 2, "and republishes the attribute")
    eq(w.inventory.OnInvoke("Consume", w.player, "RouteMarker", 2), true, "two more")
    eq(w:saved().Items.RouteMarker, 0, "empties the inventory")
    writes = w.writes
    local refused, reason = w.inventory.OnInvoke("Consume", w.player, "RouteMarker", 1)
    eq(refused, false, "an empty inventory refuses")
    eq(reason, "You do not have that item", "with a reason a caller can show")
    eq(w.writes, writes, "and writes nothing")
end

do
    local w = fresh()
    w.buy(w.player, {Key = "RouteMarker"})
    local writes = w.writes
    for _, amount in ipairs({0, -1, 1.5, 0 / 0, math.huge, "1", 9007199254740992}) do
        local ok, reason = w.inventory.OnInvoke("Consume", w.player, "RouteMarker", amount)
        eq(ok, false, "Consume refuses the amount " .. tostring(amount))
        eq(reason, "Invalid amount", "with an amount reason")
    end
    eq(select(1, w.inventory.OnInvoke("Consume", w.player, "RouteMarker", 4)), false,
        "Consume refuses more than is owned")
    eq(select(1, w.inventory.OnInvoke("Consume", w.player, "EntityShield", 1)), false,
        "Consume refuses a key that is not an item")
    eq(select(2, w.inventory.OnInvoke("Consume", w.player, "EntityShield", 1)), "Unknown item",
        "and says so")
    eq(select(1, w.inventory.OnInvoke("Consume", w.stranger, "RouteMarker", 1)), false,
        "Consume refuses a non-Player")
    eq(w.writes, writes, "none of those refusals opened a write")
    eq(w:saved().Items.RouteMarker, 3, "and the inventory is untouched")
    w.sessions[w.player] = nil
    local ok, reason = w.inventory.OnInvoke("Consume", w.player, "RouteMarker", 1)
    eq(ok, false, "an unloaded profile refuses")
    eq(reason, "Your profile is not loaded", "with a loading reason")
end

-- A Consume whose write fails must answer false so the caller does not place
-- a marker that was never paid for.
do
    local w = fresh()
    w.buy(w.player, {Key = "RouteMarker"})
    w.failBefore = true
    local ok, reason = w.inventory.OnInvoke("Consume", w.player, "RouteMarker", 1)
    w.failBefore = false
    eq(ok, false, "a failed Consume answers false")
    eq(reason, "That could not be saved. Try again.", "with a retry reason")
    eq(w:saved().Items.RouteMarker, 3, "and spends nothing")
end

eq(select(1, (function()
    local w = fresh()
    return w.inventory.OnInvoke("Nonsense", w.player)
end)()), false, "an unknown operation answers false")

-- ---------------------------------------------------------------------------
-- ZyntraInventory: DiscoverNote.
-- ---------------------------------------------------------------------------
do
    local w = fresh()
    local changed, noteId, message = w.inventory.OnInvoke("DiscoverNote", w.player, 1)
    eq(changed, true, "the first level 1 note is granted")
    eq(noteId, "L1-01", "sorted by Id, not by table order")
    eq(message, "Field note logged: Intake Log (1 of 4).",
        "and the human message comes back for the client")
    eq(w:saved().FieldNotes.Discovered["L1-01"], true, "durably recorded")
    eq(w:saved().FieldNotes.Serial, 1, "with a serial")
    eq(w:lastPush().message, "Field note logged: Intake Log (1 of 4).",
        "the push reports the progress")
    local second, secondId = w.inventory.OnInvoke("DiscoverNote", w.player, 1)
    eq(second, true, "the next call grants the next note")
    eq(secondId, "L1-02", "in Id order")
    eq(w:saved().FieldNotes.Serial, 2, "the serial advances")
    local writes = w.writes
    local none, noneId, noneMessage = w.inventory.OnInvoke("DiscoverNote", w.player, 1)
    eq(none, false, "a level whose notes are all owned grants nothing")
    eq(noneId, nil, "and names no note")
    eq(noneMessage, "Every note on this level is already in your collection",
        "with the contract's message")
    eq(w.writes, writes, "and writes nothing")
end

do
    local w = fresh()
    for _, level in ipairs({0, 4, -1, 1.5, "1", {}}) do
        local changed, noteId, message = w.inventory.OnInvoke("DiscoverNote", w.player, level)
        eq(changed, false, "level " .. tostring(level) .. " grants nothing")
        eq(noteId, nil, "and names no note")
        check(message == "Field notes unavailable"
            or message == "Every note on this level is already in your collection",
            "with a refusal message")
    end
    eq(w:saved().FieldNotes.Serial, 0, "no note was recorded")
    eq(select(1, w.inventory.OnInvoke("DiscoverNote", w.stranger, 1)), false,
        "a non-Player discovers nothing")
    eq(select(3, w.inventory.OnInvoke("DiscoverNote", w.stranger, 1)),
        "Your profile is not loaded", "with a loading reason")
end

-- No module in the place: the collection is simply unavailable.
do
    local w = fresh({notes = false})
    local changed, noteId, message = w.inventory.OnInvoke("DiscoverNote", w.player, 1)
    eq(changed, false, "with no module nothing is granted")
    eq(noteId, nil, "and no id")
    eq(message, "Field notes unavailable", "with the contract's message")
    local public = w.publicProfile(w:live(), w.player)
    eq(public.FieldNotes.Total, 0, "the payload reports zero notes")
    eq(public.FieldNotes.TitleUnlocked, false, "and no completed collection")
    eq(w.player:GetAttribute("ZyntraFieldNotesTitle"), "", "and awards no title")
end

-- Completion: the title lands with the last note, in the same transaction.
do
    local w = fresh()
    eq(w.publicProfile(w:live(), w.player).FieldNotes.Total, 4, "four notes in the module")
    w.inventory.OnInvoke("DiscoverNote", w.player, 1)
    w.inventory.OnInvoke("DiscoverNote", w.player, 1)
    w.inventory.OnInvoke("DiscoverNote", w.player, 2)
    eq(w.player:GetAttribute("ZyntraFieldNotesTitle"), "",
        "three of four is not a completed collection")
    eq(w.publicProfile(w:live(), w.player).FieldNotes.Count, 3, "and the payload agrees")
    eq(w.publicProfile(w:live(), w.player).FieldNotes.TitleUnlocked, false, "no title yet")
    local changed, noteId, note4 = w.inventory.OnInvoke("DiscoverNote", w.player, 3)
    eq(changed, true, "the last note is granted")
    eq(noteId, "L3-01", "and named")
    eq(note4, "Field note logged: Mall Manifest. Collection complete.",
        "with the completion message")
    eq(w.player:GetAttribute("ZyntraFieldNotesTitle"), Config.FieldNotes.CompletionTitle,
        "completion publishes the title attribute")
    eq(w.publicProfile(w:live(), w.player).FieldNotes.TitleUnlocked, true,
        "and the payload reports it unlocked")
    eq(w.publicProfile(w:live(), w.player).FieldNotes.Count, 4, "with every note counted")
    eq(w:lastPush().message, "Field note logged: Mall Manifest. Collection complete.",
        "and the push says the collection is complete")
    w:run()
    w:refreshTags()
    local rows = w.tags()
    local titles = 0
    for _, tag in ipairs(rows) do
        if tag.Name == "ZyntraTitleTag" then titles += 1 end
    end
    eq(titles, 1, "a single title tag row is drawn")
    eq(#rows, 1, "and nothing else, for a player with no pass and no dev access")
end

-- The title row stacks under the Supporter tag rather than replacing it.
do
    local w = fresh()
    w.player:SetAttribute("ZyntraOwnsSupporter", true)
    for _, level in ipairs({1, 1, 2, 3}) do
        w.inventory.OnInvoke("DiscoverNote", w.player, level)
    end
    w:refreshTags()
    local names = {}
    for _, tag in ipairs(w.tags()) do names[tag.Name] = true end
    check(names.ZyntraSupporterTag, "the Supporter tag is still drawn")
    check(names.ZyntraTitleTag, "and the title tag as well")
    w.player:SetAttribute("InRound", true)
    w:refreshTags()
    eq(#w.tags(), 0, "both are lobby badges and are cleared in a round")
end

-- A discovery whose write fails records nothing and keeps the note available.
do
    local w = fresh()
    w.failBefore = true
    local changed, noteId, message = w.inventory.OnInvoke("DiscoverNote", w.player, 1)
    w.failBefore = false
    eq(changed, false, "a failed discovery answers false")
    eq(noteId, nil, "with no id")
    eq(message, "That could not be saved. Try again.", "and a retry reason")
    eq(w:saved().FieldNotes.Serial, 0, "nothing recorded")
    eq(select(2, w.inventory.OnInvoke("DiscoverNote", w.player, 1)), "L1-01",
        "the same note is still the next one")
end

-- A save that already holds a note is not granted it again.
do
    local w = fresh()
    w:seed({Tokens = 0, FieldNotes = {Discovered = {["L1-01"] = true}, Serial = 1}})
    eq(select(2, w.inventory.OnInvoke("DiscoverNote", w.player, 1)), "L1-02",
        "an already-owned note is skipped")
    eq(w:saved().FieldNotes.Serial, 2, "and the serial continues from the save")
    local public = w.publicProfile(w:live(), w.player)
    eq(public.FieldNotes.Count, 2, "the payload counts both")
    eq(public.FieldNotes.Discovered["L1-01"], true, "and carries the set")
end

-- ---------------------------------------------------------------------------
-- Support leaderboard columns (#100).
-- ---------------------------------------------------------------------------
do
    local w = fresh()
    w.publish({{UserId = 701, Value = 1500}, {UserId = 9002, Value = 250}})
    eq(w.rows[1]:GetAttribute("Rank"), 1, "rank is published as a number")
    eq(w.rows[1]:GetAttribute("Name"), "COLLECTOR", "name is published upper-cased")
    eq(w.rows[1]:GetAttribute("Robux"), 1500, "amount is published as a number")
    eq(w.rows[1].Value, "01   COLLECTOR   •   1500 R$", "and the existing string is unchanged")
    eq(w.rows[2]:GetAttribute("Rank"), 2, "the second row is ranked")
    eq(w.rows[2]:GetAttribute("Name"), "DONOR9002", "and named")
    eq(w.rows[2]:GetAttribute("Robux"), 250, "and carries its amount")
    eq(w.rows[3]:GetAttribute("Rank"), nil, "an empty row clears its rank")
    eq(w.rows[3]:GetAttribute("Name"), nil, "and its name")
    eq(w.rows[3]:GetAttribute("Robux"), nil, "and its amount")
    eq(w.rows[3].Value, "", "and its string")
    w.publish({})
    eq(w.rows[1]:GetAttribute("Rank"), nil, "a board that empties clears row one too")
    eq(w.rows[1].Value, "NO SUPPORT RECORDED YET", "and shows the placeholder")
    eq(w.status.Value, "RECORDED ROBUX: PRODUCTS, PASSES & DONATIONS", "the status line is unchanged")
end

print(string.format("item inventory: %d checks passed", checks))
'''


def main():
    luau = os.environ.get("LUAU_BIN") or shutil.which("luau")
    if not luau:
        raise SystemExit("Set LUAU_BIN or put luau on PATH")
    pieces = [
        PRELUDE,
        CONFIG,
        WORLD,
        section("local function colorData", "local function isDispatchPredecessorClosed"),
        section("local function accessibilityValue", "-- The switch a player"),
        section("local function publicProfile", "local function applyHazmatColor"),
        section("local function applyAttributes", "local function enrichedPublicProfile"),
        PUSH,
        section("local function acquireMutation", "-- Developer token gifts"),
        section("local supportNameCache", "local function studioSupportEntries"),
        section("-- Daily rewards, stored items and the inventory service",
                "-- Actions that open a DataStore write get a window"),
        TAIL,
        TESTS,
    ]
    with tempfile.TemporaryDirectory(prefix="item-inventory-") as directory:
        path = Path(directory) / "item_inventory.luau"
        path.write_text("\n".join(pieces), encoding="utf-8")
        result = subprocess.run([luau, str(path)], capture_output=True, text=True, timeout=120)
    if result.stdout:
        print(result.stdout, end="")
    if result.stderr:
        print(result.stderr, end="")
    raise SystemExit(result.returncode)


if __name__ == "__main__":
    main()
