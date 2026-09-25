"""Completion save: one keyed, retried write per clear (Trello EYpXKa9S).

COMPLETION_SAVE_20260924. Runs the REAL code, extracted from
ServerScriptService/ZyntraMonetization.Script.lua by string markers:
acquireMutation/releaseMutation, mutateIdempotent, the completionSaves block
with the levelCompletedEvent handler, and the CompletionIds normalisation. A
fake DataStore can fail BEFORE a commit, or commit and then lose the response,
and a small virtual-time scheduler lets retries, duplicate events and the
leave-time flush interleave the way server threads do.

TOKEN_EARNER_PENDING_20260924 adds the REAL tokenEarner block (normalize,
defer, owed, apply), tokenEarner.settle, passOwnership, the Token Earner part
of refreshPasses, mutate, dailyMutate and the Fuse/Lever research handler, so
an ownership outage, a rejoin, a later purchase, failed and lost settlement
writes and research earnings all run through production code.

Stubbed on purpose: the daily ledger, Challenges.Apply and badge service calls
(test_daily_rewards.py / test_zyntra_challenges.py run those for real), and
UserOwnsGamePassAsync (a table of answers; nil is an outage). What a Studio
pass must still show: the real DataStore, a real PlayerRemoving order, real
Game Pass reads. Set LUAU_BIN, or put luau on PATH.
"""

import os
from pathlib import Path
import shutil
import subprocess
import tempfile

ROOT = Path(__file__).resolve().parents[2]
SERVER = (ROOT / "ServerScriptService/ZyntraMonetization.Script.lua").read_text(encoding="utf-8")
MANAGER = (ROOT / "ServerScriptService/GameManager.Script.lua").read_text(encoding="utf-8")
CONFIG = (ROOT / "ReplicatedStorage/ZyntraConfig.ModuleScript.lua").read_text(encoding="utf-8")


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

-- virtual-time scheduler: task.wait parks the running coroutine
local now, seq = 0, 0
local sleepers = {}
local task = {}
function task.wait(d)
    seq += 1
    -- like Roblox, a bare task.wait() still waits one frame
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

local warnings, pushes, badges = {}, {}, {}
local function warn(...)
    local parts = {}
    for i = 1, select("#", ...) do parts[i] = tostring((select(i, ...))) end
    table.insert(warnings, table.concat(parts, " "))
end
local RunService = {IsStudio = function() return false end}
local Players = {}
local player = {UserId = 7, Name = "Escapee", Parent = Players, attrs = {}}
function player:IsA(className) return className == "Player" end
function player:GetAttribute(name) return self.attrs[name] end
function player:SetAttribute(name, value) self.attrs[name] = value end
local function typeof(value) return value == player and "Instance" or type(value) end
local MAX_SAFE_SUPPORT = 9007199254740991

-- fake DataStore: a per-call script of outcomes
local stored, commits, plan = {}, 0, {}
local store = {}
function store:UpdateAsync(key, fn)
    local mode = table.remove(plan, 1) or "ok"
    task.wait(0.05)
    if mode == "fail_before" then error("DataStore request failed before commit") end
    local result = fn(deepcopy(stored[key]))
    if result ~= nil then
        stored[key] = deepcopy(result)
        commits += 1
    end
    if mode == "fail_after" then error("response lost after commit") end
    return deepcopy(result)
end

local sessions = {}
local mutationLocks = {}
-- virtual clocks: os.clock drives the tier wait; os.time moves in whole
-- virtual seconds, so events inside one second tie on it
local T0 = 1800000000
local os = {clock = function() return now end, time = function() return T0 + math.floor(now) end}
local game = {JobId = "job-1"}
local Color3 = {fromRGB = function(...) return {...} end, new = function(...) return {...} end}
local RealConfig = (function()
__CONFIG__
end)()
local Config = {LevelCompletionTokens = 2, FriendBoost = {PercentPerFriend = 10}, Challenges = {},
    TokenEarner = RealConfig.TokenEarner}
__SAFE_AMOUNT__
__WHOLE_COUNT__
__TOKEN_EARNER__
local function normalizeIds(data)
__NORMALIZE_IDS__
end
local function normalizeProfile(data)
    data = data or {}
    data.Tokens = data.Tokens or 0
    data.CompletedLevels = data.CompletedLevels or 0
    data.FriendBoostTenths = data.FriendBoostTenths or 0
    data.LevelsCleared = data.LevelsCleared or {}
    data.Daily = data.Daily or {Clears = 0}
    data.Daily.Day = data.Daily.Day or 20000
    data.Daily.Research = data.Daily.Research or {}
    normalizeIds(data)
    return data
end
local function reassertPendingAccessibility() end
local function applyAttributes() end
local function pushProfile(_, message, tone) table.insert(pushes, {message = message, tone = tone, at = now}) end
local function utcDay() return 20000 end
local function rollDaily() end
-- Clear pays nothing here unless a case swaps in a paying ledger; Fuse/Lever
-- pay 1 once a day, like the real ZyntraDailyResearch goals.
local DailyResearch = {}
function DailyResearch.Complete(data, key)
    if key == "Clear" then data.Daily.Clears += 1 return true, 0 end
    if data.Daily.Research[key] then return false, 0 end
    data.Daily.Research[key] = true
    data.Tokens += 1
    return true, 1
end
local Challenges = {Apply = function() return {} end}
local guids = 0
local HttpService = {GenerateGUID = function() guids += 1 return "guid-" .. guids end}
local function awardBadge(_, key)
    table.insert(badges, {key = key, savedTokens = stored["u_7"] and stored["u_7"].Tokens or 0})
end
local listeners = {}
local levelCompletedEvent = {Event = {Connect = function(_, fn) table.insert(listeners, fn) end}}
local function fire(...)
    local args = table.pack(...)
    for _, fn in ipairs(listeners) do task.spawn(fn, table.unpack(args, 1, args.n)) end
end

-- Game Pass reads: `answers[pass.Id]` true/false, nil = Roblox never answered
local answers = {}
local answerDelay = 0 -- seconds each read takes (UserOwnsGamePassAsync retries)
local answerDelays = {} -- per pass id, overriding answerDelay
local passPurchases, passReadFailed = {}, {}
local function ownsPass(_, pass)
    local answer = answers[pass.Id] -- Roblox evaluates the read when it begins
    local delaySeconds = answerDelays[pass.Id] or answerDelay
    if delaySeconds > 0 then task.wait(delaySeconds) end
    return answer
end
-- dailyMutate's playtime bookkeeping and the research bindable
local playtimeSessions, playtimeSessionSequence = {}, 0
local researchListeners = {}
local ServerStorage = {FindFirstChild = function(_, name)
    if name ~= "ZyntraResearchProgress" then return nil end
    return {Event = {Connect = function(_, fn) table.insert(researchListeners, fn) end}}
end}
local function research(key)
    for _, fn in ipairs(researchListeners) do task.spawn(fn, player, key) end
end
'''

TESTS = r'''
local completeDaily, applyChallenges = DailyResearch.Complete, Challenges.Apply
local function reset(profile)
    stored = {u_7 = deepcopy(profile or normalizeProfile({}))}
    sessions[player] = {data = normalizeProfile(deepcopy(stored.u_7)), persistent = true}
    mutationLocks[player] = nil
    completionSaves.pending[player] = nil
    commits, plan, warnings, pushes, badges = 0, {}, {}, {}, {}
    player.Parent = Players
    player.attrs = {ZyntraTokenEarnerMultiplier = 1} -- passes known: 1x
    table.clear(answers); table.clear(passPurchases); table.clear(passReadFailed)
    answerDelay = 0
    table.clear(answerDelays)
    game.JobId = "job-1"
    tokenEarner.snapshots[player] = nil
    tokenEarner.proofs[player] = nil
    playtimeSessions[player] = nil
    DailyResearch.Complete, Challenges.Apply = completeDaily, applyChallenges
    now, sleepers = 0, {}
end
local function saved() return stored.u_7 end
local function lastPush() return pushes[#pushes] end

-- 1. happy path
reset()
fire(player, 1, 0, nil, "round-A")
run()
equal(saved().Tokens, 2, "one clear pays its tokens")
equal(saved().CompletedLevels, 1, "and counts once")
check(saved().LevelsCleared["1"] == true, "and flags the level")
equal(saved().Daily.Clears, 1, "and advances daily Clear once")
equal(saved().CompletionIds[1], "round-A:1", "the id lands in the same write")
equal(#badges, 1, "First Clear badge once")
equal(badges[1].savedTokens, 2, "badge only after the clear is stored")
equal(lastPush().tone, "success", "player told it saved")

-- 2. fails before commit, inner retry succeeds
reset()
plan = {"fail_before", "ok"}
fire(player, 2, 0, nil, "round-B")
run()
equal(saved().Tokens, 2, "failed-before-commit write is retried and pays once")
equal(commits, 1, "one committed write")
equal(#badges, 1, "badge once")

-- 3. commit with lost response: retry must NOT pay again
reset()
plan = {"fail_after"}
fire(player, 1, 0, nil, "round-C")
run()
equal(saved().Tokens, 2, "lost response after commit: no double pay")
equal(saved().CompletedLevels, 1, "and no double count")
equal(commits, 1, "the retry cancels instead of writing")
equal(#badges, 1, "badge awarded once, after the confirmed state")
equal(lastPush().message, "Level clear saved.", "player told the clear is saved")
equal(sessions[player].data.Tokens, 2, "session adopts the committed profile")

-- 4. whole first mutateIdempotent fails; outer backoff retry lands
reset()
plan = {"fail_before", "fail_before", "fail_before", "ok"}
fire(player, 1, 0, nil, "round-D")
run(1.9)
equal(saved().Tokens, 0, "nothing saved yet")
equal(#badges, 0, "no badge before the clear is stored")
equal(lastPush().tone, "error", "player told it is retrying")
run()
equal(saved().Tokens, 2, "backoff retry saves the clear")
equal(#badges, 1, "badge follows the save")

-- 5a. duplicate event while the first is still retrying
reset()
plan = {"fail_before", "fail_before", "fail_before"}
fire(player, 1, 0, nil, "round-E")
fire(player, 1, 0, nil, "round-E")
run()
equal(saved().Tokens, 2, "concurrent duplicate pays once")
equal(#badges, 1, "and badges once")
-- 5b. duplicate event after the first landed
fire(player, 1, 0, nil, "round-E")
run()
equal(saved().Tokens, 2, "late duplicate pays nothing")
equal(commits, 1, "and writes nothing")
equal(lastPush().message, "Level clear saved.", "late duplicate is reported as saved")

-- 6. two legitimate rounds, same level
reset()
fire(player, 1, 0, nil, "round-F")
fire(player, 1, 0, nil, "round-G")
run()
equal(saved().Tokens, 4, "two rounds pay twice")
equal(saved().CompletedLevels, 2, "and count twice")
equal(#saved().CompletionIds, 2, "two ids kept")

-- 7. retry budget exhausted, then the leave-time flush lands it
reset()
for _ = 1, 18 do table.insert(plan, "fail_before") end
fire(player, 3, 0, nil, "round-H")
run()
equal(saved().Tokens, 0, "outage outlasting the budget saves nothing")
equal(#badges, 0, "and awards no badge")
check(string.find(warnings[#warnings], "still pending", 1, true) ~= nil, "exhaustion is logged")
check(completionSaves.pending[player]["round-H:3"] ~= nil, "clear stays queued for the leave-time save")
player.Parent = nil -- PlayerRemoving: the player may already be unparented
task.spawn(completionSaves.flush, player)
run()
equal(saved().Tokens, 2, "leave-time flush saves it even when unparented")
equal(#badges, 1, "badge after the flush save")
check(next(completionSaves.pending[player]) == nil, "queue drained")

-- the finalizer body: flush while open, THEN close
local function leave()
    task.spawn(function()
        completionSaves.flush(player)
        sessions[player].closing = true
    end)
end

-- 8a. flush while the retry sleeps in its backoff: one write, one announcement
reset()
plan = {"fail_before", "fail_before", "fail_before"}
fire(player, 1, 0, nil, "round-I")
run(1.9)
leave()
run()
equal(saved().Tokens, 2, "flush pays once")
equal(commits, 1, "the woken retry does not write again")
equal(#badges, 1, "and does not announce again")

-- 8b. flush arrives while the retry is mid-write holding the profile lock
reset()
plan = {"fail_before", "fail_before", "fail_before", "ok"}
fire(player, 1, 0, nil, "round-I2")
run(3.32)
leave()
run()
equal(saved().Tokens, 2, "retry and flush together pay once")
equal(commits, 1, "the flush cancels instead of writing")
equal(#badges, 1, "one announcement")

-- 9. store still down at leave: logged, not paid later
reset()
for _ = 1, 40 do table.insert(plan, "fail_before") end
fire(player, 1, 0, nil, "round-J")
run(1)
leave()
run()
equal(saved().Tokens, 0, "total outage: not paid")
check(string.find(warnings[#warnings], "FAILED at leave", 1, true) ~= nil, "loss is logged")

-- 10. caller without a round id: stable GUID across its retries
reset()
plan = {"fail_after"}
fire(player, 1, 0, nil, nil)
run()
equal(saved().Tokens, 2, "GUID fallback survives a lost response")
equal(guids, 1, "one GUID for the event")

-- 11. untracked level: tokens once, no badge, no flag
reset()
fire(player, 5, 0, nil, "round-K")
run()
equal(saved().Tokens, 2, "level 5 pays its tokens")
equal(#badges, 0, "no badge for untracked levels")
check(saved().LevelsCleared["5"] == nil, "no level flag")

-- 12. bounded, sanitised id list
reset()
local junk = {CompletionIds = {1, "", string.rep("x", 97)}}
for i = 1, 25 do table.insert(junk.CompletionIds, "id-" .. i) end
normalizeIds(junk)
equal(#junk.CompletionIds, 20, "keeps the newest 20")
equal(junk.CompletionIds[1], "id-6", "drops the oldest")
junk = {CompletionIds = "corrupt"}
normalizeIds(junk)
equal(#junk.CompletionIds, 0, "a corrupt field resets")
for i = 1, 20 do fire(player, 1, 0, nil, "bulk-" .. i) end
fire(player, 1, 0, nil, "bulk-21")
run()
equal(#saved().CompletionIds, 20, "the write keeps the list bounded")

-- 13. Token Earner (TOKEN_EARNER_20260924): the tier multiplies what the clear
-- earned, is read once before the write, and a lost response still pays once.
reset()
player.attrs.ZyntraTokenEarnerMultiplier = 5
plan = {"fail_after"}
fire(player, 1, 0, nil, "earner-A")
player.attrs.ZyntraTokenEarnerMultiplier = 2 -- a mid-save change must not reprice the retry
run()
equal(saved().Tokens, 10, "5x tier: 2 earned tokens pay 10")
equal(commits, 1, "lost response at 5x still pays once")
reset()
player.attrs.ZyntraTokenEarnerMultiplier = 4
fire(player, 1, 0, nil, "earner-B")
run()
equal(saved().Tokens, 2, "an invalid tier value pays 1x")
reset({Tokens = 50, CompletedLevels = 0, FriendBoostTenths = 0, LevelsCleared = {}, Daily = {Clears = 0}, CompletionIds = {}})
player.attrs.ZyntraTokenEarnerMultiplier = 3
fire(player, 1, 0, nil, "earner-C")
run()
equal(saved().Tokens, 56, "3x multiplies only the 2 earned, never the 50 already held")

-- ── TOKEN_EARNER_PENDING_20260924: an ownership outage never finalises 1x ──
local P = Config.TokenEarner.Passes
local function answerAll(owned) -- every pass read answers definitively
    for key, pass in pairs(P) do answers[pass.Id] = owned and owned[key] == true or false end
end
local function outage() table.clear(answers) end
local function except(key) -- every read answers "not owned" except `key`, which fails
    answerAll({}); answers[P[key].Id] = nil
end
-- A new server session: only the stored profile survives.
local function rejoin(jobId)
    player.Parent = Players
    game.JobId = jobId or "job-2"
    tokenEarner.clock = 0 -- a new server's sequence starts again
    sessions[player] = {data = normalizeProfile(deepcopy(stored.u_7)), persistent = true}
    mutationLocks[player] = nil
    completionSaves.pending[player] = nil
    table.clear(passPurchases); table.clear(passReadFailed)
    table.clear(answerDelays); answerDelay = 0
    tokenEarner.snapshots[player] = nil
    tokenEarner.proofs[player] = nil
    player.attrs = {}
end
local function pending() return saved().TokenEarner.Pending end
-- PromptGamePassPurchaseFinished's two lines, verbatim (asserted in main()):
-- the latch and the real tokenEarner.latched, before anything yields.
local function latch(key)
    passPurchases[player] = passPurchases[player] or {}
    local purchases = passPurchases[player]
    purchases[key] = purchases[key] or tokenEarner.stamp()
    tokenEarner.latched(player, key, purchases[key])
end
local function unknownSession(tokens)
    reset(normalizeProfile({Tokens = tokens or 0}))
    player.attrs.ZyntraTokenEarnerMultiplier = nil -- no definitive read this session
    outage()
end

-- 14. outage at the clear: the base and the clear save at once, the bonus
-- pends in the SAME write, and nothing waits a minute to pay 1x
unknownSession()
fire(player, 1, 0, nil, "earner-D")
run()
equal(saved().Tokens, 2, "outage: the clear pays its base at once")
equal(saved().CompletedLevels, 1, "and the clear itself is saved")
equal(#pending(), 1, "the bonus pends in the same write")
equal(pending()[1].Earned, 2, "carrying what the clear earned")
equal(pending()[1].Job, "job-1", "stamped with this server")
equal(commits, 1, "clear + pending bonus are one write")
check(string.find(lastPush().message, "once pass ownership is confirmed", 1, true) ~= nil,
    "player told the bonus follows")
publishEarner(player); run()
equal(player.attrs.ZyntraTokenEarnerMultiplier, nil, "an outage refresh publishes no tier")
equal(commits, 1, "and settles nothing")
fire(player, 1, 0, nil, "earner-D"); run()
equal(pending()[1].Earned, 2, "a duplicate clear queues no second bonus")
equal(saved().Tokens, 2, "and pays nothing")

-- 15. (review 1) an EXISTING 5x owner, never confirmed before the earning:
-- the first confirmation comes after it, on a later join, and still pays
player.Parent = nil
rejoin()
answerAll({TokenEarner5x = true})
publishEarner(player); run()
equal(player.attrs.ZyntraTokenEarnerMultiplier, 5, "rejoin reads 5x")
equal(saved().Tokens, 10, "existing 5x owner: the 2 earned during the outage settle to 10")
equal(#pending(), 0, "removed in the write that paid it")
equal(commits, 2, "one settlement write")
check(string.find(lastPush().message, "+8", 1, true) ~= nil, "player told of the settled bonus")
publishEarner(player); run()
equal(commits, 2, "a later snapshot owes nothing and writes nothing")
fire(player, 1, 0, nil, "earner-D"); run()
equal(saved().Tokens, 10, "replaying the settled clear pays nothing")
-- the same owner confirmed later in the SAME session
unknownSession()
fire(player, 1, 0, nil, "earner-D2"); run()
run(now + 120)
answerAll({TokenEarner5x = true})
publishEarner(player); run()
equal(saved().Tokens, 10, "first confirmation later in the session also settles at 5x")

-- 16. the settlement commits and loses its reply: the retry pays nothing
unknownSession()
fire(player, 1, 0, nil, "earner-L"); run()
answerAll({TokenEarner5x = true})
plan = {"fail_after"}
publishEarner(player); run()
equal(saved().Tokens, 10, "lost settlement reply: paid once")
equal(#pending(), 0, "nothing left pending")
equal(commits, 2, "the retry cancels instead of writing")
equal(sessions[player].data.Tokens, 10, "session adopts the committed profile")

-- 17a. a failed settlement write is retried with backoff
unknownSession()
fire(player, 1, 0, nil, "earner-F"); run()
answerAll({TokenEarner5x = true})
plan = {"fail_before", "fail_before", "fail_before"}
publishEarner(player)
run(now + 4)
equal(saved().Tokens, 2, "first settlement attempt failed: nothing paid yet")
run()
equal(saved().Tokens, 10, "the backoff retry settles it")
equal(commits, 2, "exactly once")
-- 17b. every settlement attempt fails: owed in the profile, settled next join
unknownSession()
fire(player, 1, 0, nil, "earner-G"); run()
answerAll({TokenEarner5x = true})
for _ = 1, 12 do table.insert(plan, "fail_before") end
publishEarner(player); run()
equal(saved().Tokens, 2, "a store outage outlasting the retries pays nothing yet")
equal(#pending(), 1, "the bonus stays owed in the profile")
check(string.find(warnings[#warnings], "settlement still pending", 1, true) ~= nil, "exhaustion is logged")
player.Parent = nil
rejoin()
answerAll({TokenEarner5x = true})
publishEarner(player); run()
equal(saved().Tokens, 10, "the next join settles it at 5x")
equal(#pending(), 0, "and clears it")

-- 18a. a pass bought AFTER the earning never multiplies it (in-session latch)
unknownSession()
fire(player, 1, 0, nil, "earner-P"); run()
run(now + 30)
latch("TokenEarner5x")
answerAll({}) -- reads answer again, still false from Roblox's cache
publishEarner(player); run()
equal(player.attrs.ZyntraTokenEarnerMultiplier, 5, "the purchase counts from now on")
equal(saved().Tokens, 2, "but the clear earned before it stays 1x")
equal(#pending(), 0, "and is settled")
fire(player, 1, 0, nil, "earner-P2"); run()
equal(saved().Tokens, 12, "a clear after the purchase pays 5x")
-- 18b. (review 3) the purchase lands in the SAME os.time second as the earning.
-- The profile lock is held so the handler stamps its earning and then waits
-- for its write; only then is the pass bought, and only then the write runs.
unknownSession()
mutationLocks[player] = true
local clockBefore = tokenEarner.clock
fire(player, 1, 0, nil, "earner-T")
equal(tokenEarner.clock, clockBefore + 1, "the earning is stamped before its write")
equal(commits, 0, "and its write is still blocked")
latch("TokenEarner5x")
check(passPurchases[player].TokenEarner5x > clockBefore + 1, "the purchase is stamped after the earning")
equal(os.time(), T0, "earning and purchase share one os.time second")
mutationLocks[player] = nil
run()
equal(commits, 1, "the earning's write lands after the purchase")
check(pending()[1].Unowned.TokenEarner5x == true, "and records that 5x was bought after it")
answerAll({})
publishEarner(player); run()
equal(player.attrs.ZyntraTokenEarnerMultiplier, 5, "5x counts from the purchase on")
equal(saved().Tokens, 2, "an os.time tie never reprices the earlier earning")
-- and the other order inside one second: bought, then earned
unknownSession()
latch("TokenEarner5x")
fire(player, 1, 0, nil, "earner-T2")
run()
equal(os.time(), T0, "same second")
answerAll({})
publishEarner(player); run()
equal(saved().Tokens, 10, "earned after the purchase in the same second: 5x")
-- 18c. a purchase marked on a pending bonus survives a rejoin
unknownSession()
fire(player, 1, 0, nil, "earner-X"); run()
latch("TokenEarner5x")
publishEarner(player); run() -- outage: marks the bucket, cannot settle
check(pending()[1].Unowned.TokenEarner5x == true, "marked durably in this session")
player.Parent = nil
rejoin()
answerAll({TokenEarner5x = true})
publishEarner(player); run()
equal(saved().Tokens, 2, "the next join still does not reprice it")
-- 18d. bought between sessions after a definitive "not owned" read
unknownSession()
fire(player, 1, 0, nil, "earner-Q"); run()
player.Parent = nil
rejoin("job-2")
except("TokenEarner2x") -- a partial refresh: 5x reads "not owned", 2x fails
publishEarner(player); run()
equal(player.attrs.ZyntraTokenEarnerMultiplier, nil, "partial refresh, still unknown")
check(pending()[1].Unowned.TokenEarner5x == true, "the not-owned read is marked on the older bonus")
player.Parent = nil
rejoin("job-3") -- bought on the website in between
answerAll({TokenEarner5x = true})
publishEarner(player); run()
equal(saved().Tokens, 2, "a pass seen not owned after the earning never reprices it")
-- 18e. the upgrade chain: 2x owned all along, 2->5 bought after the earning
unknownSession()
fire(player, 1, 0, nil, "earner-U"); run()
latch("TokenEarnerUp2to5")
answerAll({TokenEarner2x = true})
publishEarner(player); run()
equal(player.attrs.ZyntraTokenEarnerMultiplier, 5, "2x + 2->5 is 5x from now on")
equal(saved().Tokens, 4, "the earlier clear settles at the 2x owned then")
-- 18f. bought DURING a slow outage refresh, before the earning: counts
unknownSession()
latch("TokenEarner5x")
answerDelay = 5
task.spawn(publishEarner, player)
run(now + 2)
fire(player, 1, 0, nil, "earner-V")
run()
equal(player.attrs.ZyntraTokenEarnerMultiplier, nil, "the outage leaves the tier unknown")
answerDelay = 0
answerAll({})
publishEarner(player); run()
equal(saved().Tokens, 10, "a clear earned after the purchase settles at 5x")

-- 18g. (review 4) a definitive "not owned" read BEGINS between two outage
-- earnings and answers after both are written: the earlier one keeps its proof
unknownSession()
fire(player, 1, 0, nil, "earner-A"); run() -- earning A, written
answers[P.TokenEarner5x.Id] = false        -- only 5x answers, and slowly
answerDelays[P.TokenEarner5x.Id] = 5
task.spawn(publishEarner, player)          -- the 5x read begins after A...
run(now + 1)
fire(player, 1, 0, nil, "earner-B")        -- ...and B is earned while it is open
run(now + 1)
equal(pending()[1].Earned + (pending()[2] and pending()[2].Earned or 0), 4, "both earnings are pending")
equal(#pending(), 2, "an open read between them keeps A and B apart")
run() -- the 5x read answers "not owned"
equal(#pending(), 2, "still two buckets")
local marked = 0
for _, bucket in ipairs(pending()) do if bucket.Unowned.TokenEarner5x then marked += bucket.Earned end end
equal(marked, 2, "only A, earned before the read began, is proven not-5x")
player.Parent = nil
rejoin() -- 5x bought on the website in between
answerAll({TokenEarner5x = true})
publishEarner(player); run()
equal(saved().Tokens, 12, "A stays 1x (2), B is paid as a pre-existing owner (2 + 8)")
-- once the read has answered, later earnings merge again
unknownSession()
fire(player, 1, 0, nil, "earner-M1"); run()
answerDelays[P.TokenEarner5x.Id] = 5
task.spawn(publishEarner, player) -- every read fails: no proof
run(now + 1)
fire(player, 1, 0, nil, "earner-M2"); run(now + 1)
equal(#pending(), 2, "split while the read is open")
run()
fire(player, 1, 0, nil, "earner-M3"); run()
equal(#pending(), 1, "an answer with no proof lets them merge again")
equal(pending()[1].Earned, 6, "holding all three")
-- a bucket from an earlier server absorbs this server's earning: its span now
-- starts before everything here
player.Parent = nil
rejoin("job-9") -- no refresh yet: the tier is unknown
fire(player, 1, 0, nil, "earner-M4"); run()
equal(#pending(), 1, "merged into the earlier server's bucket")
equal(pending()[1].Job, "job-9", "which now belongs to this server")
equal(pending()[1].First, 0, "starting before anything here")

-- 18i. (review 6) concurrent refreshes: refresh #1's slow 5x read begins after
-- earning A and will answer "not owned"; the pass is then bought outside the
-- game and refresh #2 sees it owned, complete, while #1 is still open
unknownSession()
fire(player, 1, 0, nil, "earner-C1"); run()
answers[P.TokenEarner5x.Id] = false
answerDelays[P.TokenEarner5x.Id] = 5
task.spawn(publishEarner, player) -- refresh #1
run(now + 1)
answerAll({TokenEarner5x = true})
answerDelays[P.TokenEarner5x.Id] = nil
publishEarner(player) -- refresh #2, answers at once
run(now + 1)
equal(player.attrs.ZyntraTokenEarnerMultiplier, 5, "the newer refresh publishes 5x")
equal(saved().Tokens, 2, "A is not settled while a read that began after it is open")
equal(#pending(), 1, "A stays pending")
run() -- refresh #1's read answers "not owned"
equal(player.attrs.ZyntraTokenEarnerMultiplier, 5, "the older refresh never lowers the newer tier")
equal(tokenEarner.snapshots[player].Owns.TokenEarner5x, true, "nor replaces the newer snapshot")
equal(saved().Tokens, 2, "A, proven not-5x after it was earned, settles at 1x")
equal(#pending(), 0, "and clears")
fire(player, 1, 0, nil, "earner-C2"); run()
equal(saved().Tokens, 12, "a clear after the refreshes pays 5x")

-- 18h. (review 5) a KNOWN 1x buys 5x; a clear lands while the purchase's
-- refresh is still yielding on its reads: it is paid 5x at once, not 1x
reset()
player.attrs.ZyntraTokenEarnerMultiplier = 1
for key in pairs(P) do player.attrs["ZyntraOwns" .. key] = false end
answerAll({})
answerDelay = 5 -- the purchase refresh's reads are slow
latch("TokenEarner5x")
equal(player.attrs.ZyntraTokenEarnerMultiplier, 5, "the latch raises a known tier before anything yields")
task.spawn(publishEarner, player) -- the callback's task.spawn(refreshPasses)
run(now + 2)
fire(player, 1, 0, nil, "earner-K") -- during the slow refresh
run(now + 1)
equal(saved().Tokens, 10, "a clear during the slow refresh pays the new 5x")
equal(#pending(), 0, "and nothing needs to pend")
run()
equal(player.attrs.ZyntraTokenEarnerMultiplier, 5, "the refresh confirms 5x")
equal(saved().Tokens, 10, "and pays nothing twice")
-- a known 2x buying the 2->5 upgrade is raised the same way
reset()
player.attrs.ZyntraTokenEarnerMultiplier = 2
for key in pairs(P) do player.attrs["ZyntraOwns" .. key] = key == "TokenEarner2x" end
latch("TokenEarnerUp2to5")
equal(player.attrs.ZyntraTokenEarnerMultiplier, 5, "2x + 2->5 is raised to 5x at the latch")
-- an upgrade without its prerequisite raises nothing
reset()
for key in pairs(P) do player.attrs["ZyntraOwns" .. key] = false end
latch("TokenEarnerUp3to5")
equal(player.attrs.ZyntraTokenEarnerMultiplier, 1, "3->5 without 3x stays 1x")
-- an UNKNOWN tier is never invented at the latch: earnings pend instead
unknownSession()
latch("TokenEarner2x")
equal(player.attrs.ZyntraTokenEarnerMultiplier, nil, "an unknown tier stays unknown")

-- 19. Friend Boost, Daily Clear and challenges are all earned; the balance is not
unknownSession(50)
DailyResearch.Complete = function(data, key)
    if key ~= "Clear" then return false, 0 end
    data.Daily.Clears += 1
    data.Tokens += 2
    return true, 2
end
Challenges.Apply = function(data) data.Tokens += 3 return {"Challenge +3."} end
fire(player, 1, 5, {}, "earner-R") -- five friends: +50% of 2 = 1
run()
equal(saved().Tokens, 58, "base 2 + boost 1 + Daily Clear 2 + challenge 3 on top of 50")
equal(pending()[1].Earned, 8, "all 8 are the pended earning, the 50 held are not")
answerAll({TokenEarner5x = true}); publishEarner(player); run()
equal(saved().Tokens, 90, "5x settles on the 8 earned only (+32)")

-- 20. the clear lands AFTER the snapshot settled: its own save triggers settlement
unknownSession()
plan = {"fail_before", "fail_before", "fail_before"}
fire(player, 1, 0, nil, "earner-S")
run(2)
equal(commits, 0, "clear not saved yet")
answerAll({TokenEarner5x = true})
publishEarner(player)
run()
equal(saved().CompletedLevels, 1, "the clear lands on its backoff retry")
equal(saved().Tokens, 10, "and its pended bonus settles in the same session")
equal(#pending(), 0, "nothing left owed")
-- and a purchase BETWEEN the event and its late write still excludes it
unknownSession()
plan = {"fail_before", "fail_before", "fail_before"}
fire(player, 1, 0, nil, "earner-S2")
run(1.5)
latch("TokenEarner5x")
task.spawn(publishEarner, player) -- the purchase callback's refresh, still in the outage
run()
check(pending()[1].Unowned.TokenEarner5x == true, "the late write marks a purchase made after its event")
answerAll({}); publishEarner(player); run()
equal(saved().Tokens, 2, "and settles it at 1x")

-- 21. (review 2) no cap: every outage clear keeps its bonus, in few buckets
unknownSession()
for i = 1, 30 do fire(player, 1, 0, nil, "bulk-earner-" .. i) end
run()
equal(saved().Tokens, 60, "thirty outage clears pay their base")
equal(#pending(), 1, "and merge into one bucket")
equal(pending()[1].Earned, 60, "holding all 60 earned")
equal(pending()[1].Last - pending()[1].First, 29, "its span covers all thirty earnings")
latch("TokenEarner5x") -- bought mid-outage
outage(); publishEarner(player); run()
for i = 31, 45 do fire(player, 1, 0, nil, "bulk-earner-" .. i) end
run()
equal(#pending(), 2, "earnings before and after the purchase stay apart")
answerAll({}); publishEarner(player); run()
equal(saved().Tokens, 90 + 15 * 2 * 4, "the 30 before the purchase stay 1x, the 15 after settle at 5x")
equal(#pending(), 0, "all settled")

-- 22. Fuse/Lever research pends and settles the same way
unknownSession()
research("Fuse"); run()
equal(saved().Tokens, 1, "Fuse pays its base during an outage")
equal(pending()[1].Earned, 1, "and pends its bonus")
research("Fuse"); run()
equal(pending()[1].Earned, 1, "a second Fuse the same day queues nothing")
plan = {"fail_after"}
research("Lever"); run()
equal(saved().Tokens, 2, "Lever paid once despite the lost reply")
equal(pending()[1].Earned, 2, "and pended once")
answerAll({TokenEarner5x = true}); publishEarner(player); run()
equal(saved().Tokens, 10, "both research bonuses settle at 5x")
equal(#pending(), 0, "and clear")
reset()
player.attrs.ZyntraTokenEarnerMultiplier = 3
research("Fuse"); run()
equal(saved().Tokens, 3, "a known 3x pays research multiplied at once")
equal(#pending(), 0, "and pends nothing")

-- 23. normalisation, migration and bounds
equal(#normalizeProfile({}).TokenEarner.Pending, 0, "an old profile migrates to an empty ledger")
local te = tokenEarner.normalize({Since = {TokenEarner5x = 1}, Pending = {
    {Earned = 2, Unowned = {TokenEarner5x = true, Bogus = true}, Job = "a", First = 3, Last = 4},
    {Earned = 5, Unowned = {TokenEarner5x = true}, Job = "b", First = 9, Last = 9},
    {Earned = 0, Unowned = {}}, {Earned = -3}, "junk", {Earned = 1.5},
    {Earned = 4, Unowned = {TokenEarner2x = "yes"}, Job = string.rep("j", 65), First = 7, Last = -1}}})
equal(te.Since, nil, "the retired first-sighting table is not kept")
equal(#te.Pending, 3, "invalid buckets dropped; nothing merged (reads may be in flight)")
equal(te.Pending[1].Unowned.Bogus, nil, "an unknown pass key is dropped")
equal(te.Pending[1].Last, 4, "a span is kept")
equal(te.Pending[3].Unowned.TokenEarner2x, nil, "a malformed flag means not marked")
equal(te.Pending[3].Job, "", "an oversized job id is cleared")
equal(te.Pending[3].Last, 7, "a span never ends before it starts")
equal(#tokenEarner.normalize("corrupt").Pending, 0, "a corrupt field resets")
local many = {Pending = {}}
for i = 1, 200 do table.insert(many.Pending, {Earned = 1, Unowned = {}, Job = "x", First = i, Last = i}) end
many.Pending[1].Unowned = {TokenEarner5x = true}
local folded = tokenEarner.normalize(many)
equal(#folded.Pending, 64, "a hand-edited ledger is bounded to 64 buckets")
local total = 0
for _, bucket in ipairs(folded.Pending) do total += bucket.Earned end
equal(total, 200, "folding keeps every earning")
check(folded.Pending[1].Unowned.TokenEarner5x == true, "and the union of proofs, which can only pay less")
equal(tokenEarner.defer({TokenEarner = tokenEarner.normalize(nil)}, 0, 1, tokenEarner.proof({})), false,
    "nothing earned, nothing queued")

print(("completion save: %d checks passed (real mutateIdempotent + completionSaves + handler, fake DataStore)"):format(checks))
'''


def main():
    binary = os.environ.get("LUAU_BIN") or shutil.which("luau")
    if not binary:
        raise SystemExit("Set LUAU_BIN or install luau; no tests were executed.")

    locks = section(SERVER, "local function acquireMutation(player)", "local function mutate(player, transform)")
    idempotent = section(SERVER, "local IDEMPOTENT_RETRY_DELAYS", "local function sameProtectionCommand")
    completion = section(SERVER, "-- COMPLETION_SAVE_20260924 (Trello EYpXKa9S)",
                         "MarketplaceService.PromptGamePassPurchaseFinished")
    normalize_ids = section(SERVER, "\t-- COMPLETION_SAVE_20260924. Only an in-flight", "\tdata.Records = ")
    assert "local completionSaves" in completion

    # Static wiring the harness cannot execute: the finalizer flushes BEFORE the
    # session closes and drops the queue in cleanup; GameManager names rounds.
    body = section(SERVER, "local function finalizePlayerSessionBody(player)", "local function finalizePlayerSession(player)")
    flush_at = body.index("completionSaves.flush(player)")
    assert flush_at < body.index("if session then session.closing = true end"), "flush must run before closing"
    assert "completionSaves.pending[player] = nil" in section(
        SERVER, "local function finalizePlayerSession(player)", "Players.PlayerRemoving:Connect"), "queue cleanup"
    assert "completionRoundId = game:GetService(\"HttpService\"):GenerateGUID(false)" in MANAGER
    assert "run, completionRoundId)" in MANAGER, "GameManager passes the round id"

    earner = section(SERVER, "-- TOKEN_EARNER_20260924 (Trello EtdsUM4e). The tier", "-- Live playtime accrual")
    assert "data.TokenEarner = tokenEarner.normalize(data.TokenEarner)" in normalize_ids, "ledger normalised with the ids"
    assert "function tokenEarner.settle(player)" in idempotent, "settlement sits after mutateIdempotent"
    # The purchase callback is not run here; latch() in TESTS is its two
    # Token Earner lines verbatim, which must stay ahead of the spawned refresh.
    callback = section(SERVER, "MarketplaceService.PromptGamePassPurchaseFinished", "local productById")
    latch_lines = ["purchases[key] = purchases[key] or tokenEarner.stamp()",
                   "tokenEarner.latched(player, key, purchases[key])", "task.spawn(refreshPasses, player)"]
    positions = [callback.index(line) for line in latch_lines]
    assert positions == sorted(positions), "latch, then latched(), then the refresh"
    assert all(line in TESTS for line in latch_lines[:2]), "latch() mirrors the callback"
    safe_amount = section(SERVER, "local function isSafeSupportAmount(value)", "local function normalizedSupportAmount")
    whole_count = section(SERVER, "local function wholeCount(value)", "-- Rebuilt from the KNOWN key set")
    mutate = section(SERVER, "local function mutate(player, transform)", "-- Developer token gifts")
    ownership = section(SERVER, "local function passOwnership(player, key, pass)", "local function refreshPasses(player)")
    refresh = section(SERVER, "\t-- TOKEN_EARNER_20260924: six passes, one tier.", "\tif supporter then")
    daily = section(SERVER, "local function playtimeState(player)", "-- Only validated server gameplay emits")
    research = section(SERVER, "-- Only validated server gameplay emits", "local function flushPlaytime(player)")
    harness = (HARNESS.replace("__NORMALIZE_IDS__", normalize_ids).replace("__TOKEN_EARNER__", earner)
               .replace("__CONFIG__", CONFIG).replace("__SAFE_AMOUNT__", safe_amount)
               .replace("__WHOLE_COUNT__", whole_count))
    source = "".join([
        harness, locks, "\n", mutate, "\n", idempotent, "\n", ownership, "\n",
        "local function publishEarner(player)\n", refresh, "end\n",
        daily, "\n", research, "\n", completion, "\n", TESTS,
    ])
    with tempfile.TemporaryDirectory(prefix="completion-save-") as directory:
        path = Path(directory) / "completion_save.luau"
        path.write_text(source, encoding="utf-8")
        subprocess.run([binary, str(path)], check=True, timeout=60)


if __name__ == "__main__":
    main()
