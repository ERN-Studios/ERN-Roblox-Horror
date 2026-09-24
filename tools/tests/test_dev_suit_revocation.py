"""Developer suit: durable, retried, fail-closed revocation (Trello SYUaXHKQ).

DEV_SUIT_RETRY_20260924. Runs the REAL code, extracted from
ServerScriptService/ZyntraMonetization.Script.lua by string markers: the
profile locks, mutate, mutateIdempotent, the Developer-suit block of
refreshPasses (its retry loop), the EquipSkin action branch and the
ZyntraSkinId gate of applyAttributes, with the REAL ZyntraSkins module. A fake
DataStore can fail before a commit or commit and lose its reply; a small
virtual-time scheduler runs the backoff. DevAccess is a table the cases flip.

"Two viewers" offline means the one replicated attribute every client's view
is built from: HazmatSkinVisuals (server) builds the suit from ZyntraSkinId,
so the owner and a second client can only ever see what it says. A real
two-client round, a real revoke + rejoin and mobile still need Studio/live.
Set LUAU_BIN, or put luau on PATH.
"""

import os
from pathlib import Path
import shutil
import subprocess
import tempfile

ROOT = Path(__file__).resolve().parents[2]
SERVER = (ROOT / "ServerScriptService/ZyntraMonetization.Script.lua").read_text(encoding="utf-8")
SKINS = (ROOT / "ReplicatedStorage/ZyntraSkins.ModuleScript.lua").read_text(encoding="utf-8")
VISUALS = (ROOT / "ServerScriptService/HazmatSkinVisuals.Script.lua").read_text(encoding="utf-8")


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
    check(actual == expected, message .. ": expected " .. tostring(expected) .. ", got " .. tostring(actual))
end

local now, seq, sleepers = 0, 0, {}
local task = {}
function task.wait(d)
    seq += 1
    table.insert(sleepers, {co = coroutine.running(), at = now + ((d and d > 0) and d or 1 / 60), seq = seq})
    coroutine.yield()
    return d
end
function task.spawn(fn, ...)
    local co = coroutine.create(fn)
    local ok, err = coroutine.resume(co, ...)
    if not ok then error(err, 0) end
    return co
end
local function run(untilTime)
    while #sleepers > 0 do
        table.sort(sleepers, function(a, b) if a.at == b.at then return a.seq < b.seq end return a.at < b.at end)
        if untilTime and sleepers[1].at > untilTime then now = untilTime return end
        local s = table.remove(sleepers, 1)
        now = s.at
        local ok, err = coroutine.resume(s.co)
        if not ok then error(err, 0) end
    end
    if untilTime then now = math.max(now, untilTime) end
end
local function deepcopy(v)
    if type(v) ~= "table" then return v end
    local t = {}
    for k, x in pairs(v) do t[k] = deepcopy(x) end
    return t
end

local warnings, pushes = {}, {}
local function warn(...)
    local parts = {}
    for i = 1, select("#", ...) do parts[i] = tostring((select(i, ...))) end
    table.insert(warnings, table.concat(parts, " "))
end
local RunService = {IsStudio = function() return false end}
local Players = {}
local function newPlayer(userId)
    local p = {UserId = userId, Name = "u" .. userId, Parent = Players, attrs = {}, history = {}}
    function p:GetAttribute(name) return self.attrs[name] end
    function p:SetAttribute(name, value)
        self.attrs[name] = value
        if name == "ZyntraSkinId" then table.insert(self.history, value) end
    end
    return p
end
local allowed = {}
local DevAccess = {IsAllowed = function(p) return allowed[p.UserId] == true end}
local Skins = (function()
__SKINS__
end)()

-- fake DataStore: a per-call script of outcomes; `beforeTransform` runs inside
-- UpdateAsync just before the transform, like a change that lands mid-write
local stored, commits, calls, plan, beforeTransform = {}, 0, 0, {}, nil
local store = {}
function store:UpdateAsync(key, fn)
    calls += 1
    local mode = table.remove(plan, 1) or "ok"
    task.wait(0.05)
    if mode == "fail_before" then error("DataStore request failed before commit") end
    if beforeTransform then beforeTransform() end
    local result = fn(deepcopy(stored[key]))
    if result ~= nil then
        stored[key] = deepcopy(result)
        commits += 1
    end
    if mode == "fail_after" then error("response lost after commit") end
    return deepcopy(result)
end
local function normalizeProfile(data)
    data = data or {}
    data.Skins = Skins.Normalize(data.Skins)
    data.Settings = data.Settings or {}
    return data
end
local function reassertPendingAccessibility() end
local function pushProfile(_, message, tone) table.insert(pushes, {message = message, tone = tone}) end
local sessions, mutationLocks = {}, {}
local tokenEarner = {} -- mutateIdempotent's section also defines tokenEarner.settle
local function applyAttributes(player, data)
__APPLY_SKIN__
end
'''

TESTS = r'''
local function syncSuit(player)
__SUIT_BLOCK__
end
local function equipAction(player, payload)
    local action = "EquipSkin"
    if false then
__EQUIP_BRANCH__
    end
end
-- a ZyntraAction remote call runs on its own thread
local function equip(player, payload) task.spawn(equipAction, player, payload) end

local SUIT = "SignalArchitect"
local function devProfile() -- what a developer's saved profile holds
    local profile = normalizeProfile({})
    profile.Skins.Owned[SUIT] = true
    profile.Skins.Equipped = SUIT
    return profile
end
local function load(player, profile)
    stored["u_" .. player.UserId] = deepcopy(profile)
    sessions[player] = {data = normalizeProfile(deepcopy(profile)), persistent = true}
    mutationLocks[player] = nil
    applyAttributes(player, sessions[player].data) -- loadProfile publishes before refreshPasses
end
local function reset()
    stored, commits, calls, plan, warnings, pushes, beforeTransform = {}, 0, 0, {}, {}, {}, nil
    table.clear(allowed); table.clear(sessions); table.clear(mutationLocks)
    now, sleepers = 0, {}
end
local function savedSkins(player) return stored["u_" .. player.UserId].Skins end
local function neverShown(player, message)
    for _, skinId in ipairs(player.history) do
        if skinId == SUIT then check(false, message) end
    end
    check(player.attrs.ZyntraSkinId ~= SUIT, message)
end

-- 1. revoked former developer, first write fails: the retry revokes durably
reset()
local former = newPlayer(1001)
load(former, devProfile())
equal(former.attrs.ZyntraSkinId, Skins.DefaultId, "a revoked suit is never published, even before the write")
plan = {"fail_before", "fail_before", "fail_before"}
syncSuit(former)
run(4)
equal(savedSkins(former).Owned[SUIT], true, "first attempt failed: the store is still stale")
run(7)
equal(savedSkins(former).Owned[SUIT], nil, "the backoff retry revokes ownership")
equal(#sleepers, 0, "and the loop ends with the write that landed")
run()
equal(savedSkins(former).Equipped, Skins.DefaultId, "and unequips it")
equal(commits, 1, "in one write")
neverShown(former, "the suit is never on the replicated skin attribute")

-- 2. lost reply: committed once, the retry finds the profile in sync
reset()
load(former, devProfile())
plan = {"fail_after"}
syncSuit(former); run()
equal(savedSkins(former).Owned[SUIT], nil, "revoked")
equal(commits, 1, "the retry after a lost reply writes nothing")
equal(sessions[former].data.Skins.Owned[SUIT], nil, "and the session adopts the saved profile")

-- 3. every attempt fails: bounded, logged, fail-closed; the next join revokes
reset()
load(former, devProfile())
for _ = 1, 12 do table.insert(plan, "fail_before") end
syncSuit(former); run()
equal(savedSkins(former).Owned[SUIT], true, "a store outage outlasting the retries leaves it stale")
check(string.find(warnings[#warnings], "still unsaved after retries", 1, true) ~= nil, "exhaustion is logged")
equal(#sleepers, 0, "and the retry loop stops")
neverShown(former, "stale in the store, still never shown")
equip(former, SUIT); run()
equal(commits, 0, "a forged equip of the stale suit is refused without a write")
-- the same stale ownership with ANOTHER suit equipped: only the DevAccess gate
-- stands between a forged request and a write
reset()
local stale = devProfile()
stale.Skins.Equipped = Skins.DefaultId
load(former, stale)
for _ = 1, 12 do table.insert(plan, "fail_before") end
syncSuit(former); run()
calls = 0
equip(former, SUIT); run()
equal(calls, 0, "a forged equip of a still-owned revoked suit never reaches the store")
equal(savedSkins(former).Equipped, Skins.DefaultId, "and changes nothing")
-- rejoin: a new session from the stale store
local rejoined = newPlayer(1001)
load(rejoined, stored.u_1001)
equal(rejoined.attrs.ZyntraSkinId, Skins.DefaultId, "the rejoin publishes the default before syncing")
syncSuit(rejoined); run()
equal(savedSkins(rejoined).Owned[SUIT], nil, "the next join revokes it durably")
neverShown(rejoined, "and never shows it")

-- 4. the transform re-reads DevAccess: access restored mid-write is kept
reset()
local dev = newPlayer(2002)
load(dev, devProfile())
beforeTransform = function() allowed[2002] = true end -- restored while the write is in flight
syncSuit(dev); run()
equal(savedSkins(dev).Owned[SUIT], true, "a developer re-allowed mid-write keeps the suit")
equal(savedSkins(dev).Equipped, SUIT, "and it stays equipped")
equal(commits, 0, "the in-sync profile is not rewritten")
-- and revoked mid-write: the transform revokes, not the stale probe
reset()
allowed[2002] = true
load(dev, normalizeProfile({})) -- developer who does not own it yet
beforeTransform = function() allowed[2002] = nil end
syncSuit(dev); run()
equal(savedSkins(dev).Owned[SUIT], nil, "access revoked mid-write grants nothing")

-- 5. genuine developer: granted once, ownership and equip untouched afterwards
reset()
allowed[2002] = true
load(dev, normalizeProfile({}))
syncSuit(dev); run()
equal(savedSkins(dev).Owned[SUIT], true, "a developer is granted the suit")
equal(commits, 1, "once")
equip(dev, SUIT); run()
equal(savedSkins(dev).Equipped, SUIT, "and may equip it")
equal(dev.attrs.ZyntraSkinId, SUIT, "which every viewer then sees")
calls = 0
syncSuit(dev); run()
equal(calls, 0, "an in-sync profile costs no DataStore request")
equal(commits, 2, "a later refresh changes nothing for a genuine developer")
equal(savedSkins(dev).Equipped, SUIT, "not even the equip")

-- 6. two viewers, one revoked mid-session wearer: the only thing either can
-- see is the replicated attribute the server gates
reset()
local wearer, viewer = newPlayer(3003), newPlayer(3004)
load(wearer, devProfile())
load(viewer, normalizeProfile({}))
for _ = 1, 3 do table.insert(plan, "fail_before") end
syncSuit(wearer); run()
equal(viewer.attrs.ZyntraSkinId, Skins.DefaultId, "the second viewer wears the default")
neverShown(wearer, "the viewer can never be shown the wearer's revoked suit")
equip(viewer, SUIT); run()
equal(savedSkins(viewer).Equipped, Skins.DefaultId, "a non-developer's forged equip is refused")

print(("dev suit revocation: %d checks passed (real mutate/mutateIdempotent, suit retry, EquipSkin, skin gate, ZyntraSkins)"):format(checks))
'''


def main():
    binary = os.environ.get("LUAU_BIN") or shutil.which("luau")
    if not binary:
        raise SystemExit("Set LUAU_BIN or install luau; no tests were executed.")
    locks = section(SERVER, "local function acquireMutation(player)", "local function mutate(player, transform)")
    mutate = section(SERVER, "local function mutate(player, transform)", "-- Developer token gifts")
    idempotent = section(SERVER, "local IDEMPOTENT_RETRY_DELAYS", "local function sameProtectionCommand")
    suit = section(SERVER, "\t-- DEV_SUIT_20260924 (SYUaXHKQ): Developer suits", "\t-- TOKEN_EARNER_20260924: six passes, one tier.")
    assert "DevAccess.IsAllowed(player)" in section(suit, "mutateIdempotent(player, function(data)", "end)"), \
        "the transform re-reads DevAccess"
    equip = section(SERVER, "\telseif action == \"EquipSkin\" then", "\telseif action == \"UseSpeedPotion\" then")
    apply_skin = section(SERVER, "\tlocal equipped = Skins.Get(data.Skins.Equipped)", "\tplayer:SetAttribute(\"ZyntraGlowstickColor\"")
    # Every viewer's suit comes from this one server attribute.
    assert 'player:GetAttribute("ZyntraSkinId")' in VISUALS, "HazmatSkinVisuals builds from ZyntraSkinId"
    source = "\n".join([
        HARNESS.replace("__SKINS__", SKINS).replace("__APPLY_SKIN__", apply_skin),
        locks, mutate, idempotent,
        TESTS.replace("__SUIT_BLOCK__", suit).replace("__EQUIP_BRANCH__", equip),
    ])
    with tempfile.TemporaryDirectory(prefix="dev-suit-") as directory:
        path = Path(directory) / "dev_suit.luau"
        path.write_text(source, encoding="utf-8")
        subprocess.run([binary, str(path)], check=True, timeout=60)


if __name__ == "__main__":
    main()
