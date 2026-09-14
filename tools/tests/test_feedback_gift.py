"""Feedback thank-you gift (Trello #71): the real profile mutation plus the real
gift block from ZyntraMonetization.refreshPasses, under a fake DataStore.

Covers: only UserId 10152463945 is touched; the first successful load grants
+1 StaminaLevel, +1 BatteryLevel and +10 Tokens once; a repeat is a no-op that
cancels the UpdateAsync write; a DataStore failure leaves no marker and the
next load retries; receipts and pass ownership are untouched; Studio sessions
never write; and normalizeProfile keeps the marker (it never rebuilds Grants
from a fixed key set). No Studio, no network. Set LUAU_BIN.
"""

from pathlib import Path
import os
import re
import shutil
import subprocess
import tempfile

ROOT = Path(__file__).resolve().parents[2]
SERVER = (ROOT / "ServerScriptService/ZyntraMonetization.Script.lua").read_text(encoding="utf-8")


def section(start, stop):
    begin = SERVER.index(start)
    return SERVER[begin:SERVER.index(stop, begin)]


def gift_block():
    block = section("\t-- FEEDBACK_GIFT_20260914", "\tpassReadFailed[player] = nil")
    return "local function grantFeedbackGift(player)\n" + block + "end\n"


PRELUDE = r'''
local checks = 0
local function check(value, message) checks += 1; assert(value, message) end
local function equal(actual, expected, message)
    check(actual == expected, message .. ": expected " .. tostring(expected) .. ", got " .. tostring(actual))
end
local function clone(value)
    if type(value) ~= "table" then return value end
    local result = {}
    for key, child in pairs(value) do result[key] = clone(child) end
    return result
end
local PCT = "5%"
local function world(studio)
    local w = {now = 10, studio = studio == true, pushes = {}, warnings = {}, committed = {}, storeCalls = 0, callbackCalls = 0, attributeCalls = 0}
    local os = {clock = function() return w.now end}
    local function warn(...) table.insert(w.warnings, {...}) end
    local task = {wait = function() coroutine.yield("LOCK_WAIT") end}
    local Players = {roster = {}}
    local function player(name, userId)
        local p = {Name = name, UserId = userId, Parent = Players, ClassName = "Player"}
        table.insert(Players.roster, p)
        return p
    end
    w.gifted = player("Kecoalmutt", 10152463945)
    w.other = player("OrdinaryPlayer", 111)
    local sessions, mutationLocks = {}, {}
    for _, p in ipairs(Players.roster) do
        local data = {Tokens = 2, BatteryLevel = 7, StaminaLevel = 3, CompletedLevels = 3,
            DonationRobux = 75, ReentryCredits = 2, ReceiptIds = {"kept"},
            Grants = {Supporter = false, AdvancedEquipment = false}, Settings = {MuteDispatch = true}}
        sessions[p] = {data = clone(data), persistent = true}
        w.committed["u_" .. p.UserId] = clone(data)
    end
    local RunService = {IsStudio = function() return w.studio end}
    local function normalizeProfile(data) return data end
    local function reassertPendingAccessibility() end
    local function applyAttributes() w.attributeCalls += 1 end
    local function pushProfile(p, message, tone)
        table.insert(w.pushes, {player = p, message = message, tone = tone, data = clone(sessions[p].data)})
    end
    local store = {}
    function store:UpdateAsync(key, transform)
        w.storeCalls += 1
        if w.failBeforeCommit then error("DataStore unavailable") end
        w.callbackCalls += 1
        local result = transform(clone(w.committed[key]))
        if result then w.committed[key] = clone(result) end
        return clone(result)
    end
'''

TAIL = r'''
    w.sessions, w.players = sessions, Players
    w.grant = grantFeedbackGift
    function w:saved(p) return self.committed["u_" .. (p or self.gifted).UserId] end
    function w:live(p) return sessions[p or self.gifted].data end
    return w
end

-- Only the named account is touched.
do
    local w = world()
    w.grant(w.other)
    equal(w.storeCalls, 0, "an ordinary player triggers no write")
    equal(w:live(w.other).Tokens, 2, "an ordinary player keeps their tokens")
end

-- First load: one committed grant, correct amounts, marker set, message pushed.
do
    local w = world()
    w.grant(w.gifted)
    equal(w.storeCalls, 1, "one DataStore write for the gift")
    local saved = w:saved()
    equal(saved.Tokens, 12, "+10 tokens committed")
    equal(saved.StaminaLevel, 4, "+1 stamina level committed")
    equal(saved.BatteryLevel, 8, "+1 battery level committed")
    equal(saved.Grants.FeedbackThanks20260914, true, "grant marker persisted")
    equal(saved.Grants.AdvancedEquipment, false, "pass ownership not faked")
    equal(saved.ReceiptIds[1], "kept", "receipts untouched")
    equal(#saved.ReceiptIds, 1, "no receipt invented")
    equal(w:live().Tokens, 12, "session copy adopts the committed profile")
    local push = w.pushes[#w.pushes]
    check(push and push.tone == "success" and string.find(push.message, "Thanks for your feedback", 1, true), "player is told why")
    check(string.find(push.message, "5%", 1, true) and string.find(push.message, "10 Research Tokens", 1, true), "message names the package and tokens")

    -- Repeat loads are no-ops that cancel the write.
    w.grant(w.gifted); w.grant(w.gifted)
    equal(w.storeCalls, 3, "each repeat still reads through UpdateAsync")
    equal(w:saved().Tokens, 12, "repeat never grants again")
    equal(w:saved().StaminaLevel, 4, "repeat never re-levels stamina")
    equal(w:saved().BatteryLevel, 8, "repeat never re-levels battery")
end

-- A failed write leaves nothing behind; the next load retries and lands once.
do
    local w = world()
    w.failBeforeCommit = true
    w.grant(w.gifted)
    equal(w:saved().Tokens, 2, "failed write commits nothing")
    equal(w:saved().Grants.FeedbackThanks20260914, nil, "failed write sets no marker")
    equal(w:live().Grants.FeedbackThanks20260914, nil, "session copy holds no marker after failure")
    check(#w.warnings >= 1, "the failure is warned, not swallowed")
    w.failBeforeCommit = false
    w.grant(w.gifted)
    equal(w:saved().Tokens, 12, "retry on the next load delivers the gift once")
    w.grant(w.gifted)
    equal(w:saved().Tokens, 12, "and only once")
end

-- Studio: in-memory only, never a DataStore write.
do
    local w = world(true)
    w.sessions[w.gifted].persistent = false
    w.grant(w.gifted)
    equal(w.storeCalls, 0, "Studio never writes the DataStore")
    equal(w:live().Tokens, 12, "Studio session copy still shows the gift")
    equal(w:saved().Tokens, 2, "saved profile untouched in Studio")
end

print(string.format("feedback gift: %d checks passed (actual mutate + gift block; fake DataStore)", checks))
'''


def check_normalize_keeps_marker():
    body = section("local function normalizeProfile(data)", "\nlocal function ")
    grants = [line for line in body.splitlines() if "data.Grants" in line]
    assert grants, "normalizeProfile no longer touches Grants at all?"
    rebuilt = [line for line in grants if re.search(r"data\.Grants\s*=\s*\{\}", line)]
    assert not rebuilt, "normalizeProfile rebuilds Grants from scratch; the gift marker would be lost: " + "; ".join(rebuilt)
    assert any("data.Grants or {}" in line for line in grants), "normalizeProfile must keep an existing Grants table"
    return len(grants)


def main():
    luau = os.environ.get("LUAU_BIN") or shutil.which("luau")
    if not luau:
        raise SystemExit("Set LUAU_BIN or put luau on PATH")
    lines = check_normalize_keeps_marker()
    mutation = section("local function acquireMutation(player)", "-- Developer token gifts")
    source = "\n".join((PRELUDE, mutation, gift_block(), TAIL))
    with tempfile.TemporaryDirectory(prefix="feedback-gift-") as directory:
        path = Path(directory) / "feedback_gift.luau"
        path.write_text(source, encoding="utf-8")
        result = subprocess.run([luau, str(path)], capture_output=True, text=True, timeout=60)
    if result.stdout:
        print(result.stdout, end="")
    if result.stderr:
        print(result.stderr, end="")
    if result.returncode == 0:
        print(f"normalizeProfile keeps unknown Grants keys ({lines} Grants lines inspected)")
    raise SystemExit(result.returncode)


if __name__ == "__main__":
    main()
