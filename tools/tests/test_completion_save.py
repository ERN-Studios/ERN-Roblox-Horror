"""Completion save: one keyed, retried write per clear (Trello EYpXKa9S).

COMPLETION_SAVE_20260924. Runs the REAL code, extracted from
ServerScriptService/ZyntraMonetization.Script.lua by string markers:
acquireMutation/releaseMutation, mutateIdempotent, the completionSaves block
with the levelCompletedEvent handler, and the CompletionIds normalisation. A
fake DataStore can fail BEFORE a commit, or commit and then lose the response,
and a small virtual-time scheduler lets retries, duplicate events and the
leave-time flush interleave the way server threads do.

Stubbed on purpose: the daily ledger, Challenges.Apply and badge service calls
(test_daily_rewards.py / test_zyntra_challenges.py run those for real). What a
Studio pass must still show: the real DataStore, a real PlayerRemoving order.
Set LUAU_BIN, or put luau on PATH.
"""

import os
from pathlib import Path
import shutil
import subprocess
import tempfile

ROOT = Path(__file__).resolve().parents[2]
SERVER = (ROOT / "ServerScriptService/ZyntraMonetization.Script.lua").read_text(encoding="utf-8")
MANAGER = (ROOT / "ServerScriptService/GameManager.Script.lua").read_text(encoding="utf-8")


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
local player = {UserId = 7, Name = "Escapee", Parent = Players}
function player:IsA(className) return className == "Player" end

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
    normalizeIds(data)
    return data
end
local function reassertPendingAccessibility() end
local function applyAttributes() end
local function pushProfile(_, message, tone) table.insert(pushes, {message = message, tone = tone, at = now}) end
local function utcDay() return 20000 end
local function rollDaily() end
local DailyResearch = {Complete = function(data) data.Daily.Clears += 1 end}
local Challenges = {Apply = function() return {} end}
local Config = {LevelCompletionTokens = 2, FriendBoost = {PercentPerFriend = 10}, Challenges = {}}
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

local sessions = {}
local mutationLocks = {}
'''

TESTS = r'''
local function reset(profile)
    stored = {u_7 = deepcopy(profile or normalizeProfile({}))}
    sessions[player] = {data = normalizeProfile(deepcopy(stored.u_7)), persistent = true}
    mutationLocks[player] = nil
    completionSaves.pending[player] = nil
    commits, plan, warnings, pushes, badges = 0, {}, {}, {}, {}
    player.Parent = Players
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

    source = "".join([
        HARNESS.replace("__NORMALIZE_IDS__", normalize_ids),
        locks, "\n", idempotent, "\n", completion, "\n", TESTS,
    ])
    with tempfile.TemporaryDirectory(prefix="completion-save-") as directory:
        path = Path(directory) / "completion_save.luau"
        path.write_text(source, encoding="utf-8")
        subprocess.run([binary, str(path)], check=True, timeout=60)


if __name__ == "__main__":
    main()
