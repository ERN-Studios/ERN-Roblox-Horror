"""Voluntary challenges and personal records (Trello FnF49TWk, CHALLENGES_20260923).

Runs the REAL ReplicatedStorage.ZyntraChallenges module with the REAL
ZyntraConfig.Challenges block in offline Luau and checks the card's acceptance:
records land on the right level and rule set, a challenge is rewarded once and
only once, assisted and developer runs cannot set a clean record or earn a
challenge, and a hand-edited save cannot smuggle in an impossible record.
Set LUAU_BIN to an official luau executable, or put luau on PATH.
"""

import os
import re
import shutil
import subprocess
import tempfile
from pathlib import Path

ROOT = Path(__file__).resolve().parents[2]
MODULE = (ROOT / "ReplicatedStorage/ZyntraChallenges.ModuleScript.lua").read_text(encoding="utf-8-sig")
CONFIG = (ROOT / "ReplicatedStorage/ZyntraConfig.ModuleScript.lua").read_text(encoding="utf-8-sig")

TESTS = r'''
local failures, checks = {}, 0
local function check(ok, message) checks += 1; if not ok then table.insert(failures, message) end end
local settings = Config.Challenges
local function profile()
    return {Tokens = 10, Records = C.NormalizeRecords(nil, settings), Challenges = C.NormalizeDone(nil, settings)}
end
local clean = {Seconds = 300.04, Deaths = 0, Revived = false, Aided = false, Equipped = false, Solo = true}
local function run(overrides)
    local r = table.clone(clean)
    for k, v in pairs(overrides or {}) do r[k] = v end
    return r
end

-- 1. A clean solo clear under the goal: record + both challenges, paid once.
local data = profile()
local messages = C.Apply(data, 1, run(), settings, 1000)
check(data.Records["1:solo:clean"] and data.Records["1:solo:clean"].Best == 300, "clean solo record at 300.0 s")
check(data.Challenges.NoDeath["1"] == true and data.Challenges.TimeGoal["1"] == true, "both challenges done")
check(data.Tokens == 10 + settings.RewardTokens.NoDeath + settings.RewardTokens.TimeGoal, "both rewards paid")
check(#messages == 3, "record + two challenge messages, got " .. #messages)
-- ...and a second identical clear pays nothing and keeps the record.
local before = data.Tokens
messages = C.Apply(data, 1, run({Seconds = 310}), settings, 2000)
check(data.Tokens == before, "a challenge is never paid twice")
check(#messages == 0, "a slower clear is not a record and earns nothing")
check(data.Records["1:solo:clean"].Best == 300, "the best time is kept")
-- A faster one replaces the record, still without paying again.
C.Apply(data, 1, run({Seconds = 250}), settings, 3000)
check(data.Records["1:solo:clean"].Best == 250 and data.Records["1:solo:clean"].At == 3000, "a faster clean clear replaces the record")
check(data.Tokens == before, "a new record pays nothing")

-- 2. Right level and rule set.
data = profile()
C.Apply(data, 2, run({Solo = false}), settings, 1)
check(data.Records["2:party:clean"] ~= nil and data.Records["2:solo:clean"] == nil, "a party clear is a party record")
check(data.Records["1:party:clean"] == nil, "and belongs to its own level")
C.Apply(data, 3, run({Aided = true, Seconds = 100}), settings, 1)
check(data.Records["3:solo:assisted"] and data.Records["3:solo:clean"] == nil, "an aided clear is an assisted record")
check(not data.Challenges.NoDeath["3"] and not data.Challenges.TimeGoal["3"], "an aided clear earns no challenge")
C.Apply(data, 3, run({Revived = true, Deaths = 1, Seconds = 90}), settings, 1)
check(data.Records["3:solo:assisted"].Best == 90, "a revived clear is assisted too")
check(not data.Challenges.NoDeath["3"], "a revive can never count as no deaths")
C.Apply(data, 1, run({Equipped = true}), settings, 1)
check(data.Records["1:solo:clean"].Equipped == true, "an upgraded run is marked Equipped")

-- 3. Goal edges.
data = profile()
local goal = settings.TimeGoalSeconds["2"]
C.Apply(data, 2, run({Seconds = goal + 0.1}), settings, 1)
check(not data.Challenges.TimeGoal["2"], "a clear over the goal misses it")
check(data.Challenges.NoDeath["2"], "but a deathless clean clear still counts")
C.Apply(data, 2, run({Seconds = goal}), settings, 1)
check(data.Challenges.TimeGoal["2"], "exactly the goal is a pass")
data = profile()
C.Apply(data, 1, run({Deaths = 2}), settings, 1)
check(not data.Challenges.NoDeath["1"] and data.Challenges.TimeGoal["1"], "deaths block only the no-death challenge")

-- 3b. Level 4 (the cinema, LEVEL4_QUEUE_CHOICE_20261002) is a tracked level like 1-3.
-- The shipped numbers are written down here, not read back from the config.
check(table.find(settings.Levels, 4) ~= nil and #settings.Levels == 4, "Levels is {1, 2, 3, 4}")
check(settings.TimeGoalSeconds["4"] == 720, "Level 4's goal is 12:00")
data = profile()
messages = C.Apply(data, 4, run({Seconds = 650}), settings, 7)
check(data.Records["4:solo:clean"] and data.Records["4:solo:clean"].Best == 650, "a clean solo Level 4 clear is a Level 4 record")
check(data.Records["1:solo:clean"] == nil, "and only a Level 4 one")
check(data.Challenges.NoDeath["4"] == true and data.Challenges.TimeGoal["4"] == true, "both Level 4 challenges done")
check(data.Tokens == 10 + settings.RewardTokens.NoDeath + settings.RewardTokens.TimeGoal, "both Level 4 rewards paid")
check(#messages == 3, "record + two Level 4 challenge messages, got " .. #messages)
check(string.find(messages[3], "under 12:00", 1, true) ~= nil, "the time goal message names 12:00: " .. tostring(messages[3]))
before = data.Tokens
C.Apply(data, 4, run({Seconds = 600}), settings, 8)
check(data.Tokens == before and data.Records["4:solo:clean"].Best == 600, "a faster Level 4 clear is a record, never paid twice")
data = profile()
C.Apply(data, 4, run({Seconds = 720.1, Solo = false}), settings, 1)
check(data.Records["4:party:clean"] ~= nil, "a Level 4 party clear is a party record")
check(not data.Challenges.TimeGoal["4"] and data.Challenges.NoDeath["4"], "over 12:00 misses the goal, still no deaths")
C.Apply(data, 4, run({Seconds = 720, Solo = false}), settings, 1)
check(data.Challenges.TimeGoal["4"], "exactly 12:00 is a pass")
data = profile()
C.Apply(data, 4, run({Seconds = 100, Deaths = 1, Revived = true}), settings, 1)
check(data.Records["4:solo:assisted"] and data.Records["4:solo:clean"] == nil, "a revived Level 4 clear is assisted")
check(not data.Challenges.NoDeath["4"] and not data.Challenges.TimeGoal["4"], "and earns no Level 4 challenge")

-- 4. Nothing is recorded for a developer run, a bad time or an unknown level.
data = profile()
local t0 = data.Tokens
for _, bad in ipairs({
    {1, run({DevTouched = true})}, {1, run({Seconds = 0})}, {1, run({Seconds = -5})},
    {1, run({Seconds = 0/0})}, {1, run({Seconds = math.huge})}, {1, run({Seconds = "fast"})},
    {5, run()}, {0, run()}, {1, nil},
}) do
    local m = C.Apply(data, bad[1], bad[2], settings, 1)
    check(#m == 0, "a rejected run returns no messages")
end
check(next(data.Records) == nil and data.Tokens == t0, "nothing recorded, nothing paid")
check(next(data.Challenges.NoDeath) == nil and next(data.Challenges.TimeGoal) == nil, "no challenge set")

-- 5. A token balance at the ceiling is not overflowed.
data = profile()
data.Tokens = 9007199254740991
C.Apply(data, 1, run(), settings, 1)
check(data.Tokens == 9007199254740991, "a full balance is left alone")
check(data.Challenges.NoDeath["1"], "the challenge still counts as done")

-- 6. Normalization keeps only known keys and sane values.
local records = C.NormalizeRecords({
    ["1:solo:clean"] = {Best = 123.456, Equipped = true, At = 5},
    ["2:party:assisted"] = {Best = 0/0}, ["3:solo:clean"] = {Best = -1},
    ["9:solo:clean"] = {Best = 10}, ["1:duo:clean"] = {Best = 10}, junk = 1,
    ["2:solo:clean"] = {Best = 99999999},
    ["4:party:assisted"] = {Best = 700.04, At = 6}, ["5:solo:clean"] = {Best = 10},
}, settings)
check(records["1:solo:clean"] and records["1:solo:clean"].Best == 123.5 and records["1:solo:clean"].Equipped, "a valid record survives, in tenths")
check(records["4:party:assisted"] and records["4:party:assisted"].Best == 700, "a Level 4 record survives")
check(records["5:solo:clean"] == nil, "level 5 is unknown")
local n = 0 for _ in pairs(records) do n += 1 end
check(n == 2, "invalid or unknown records are dropped, kept " .. n)
local done = C.NormalizeDone({NoDeath = {["1"] = true, ["7"] = true, ["2"] = "yes", ["4"] = true, ["5"] = true}, TimeGoal = 5, Extra = {}}, settings)
check(done.NoDeath["1"] and not done.NoDeath["7"] and not done.NoDeath["2"], "only known levels and true flags survive")
check(done.NoDeath["4"] == true and done.NoDeath["5"] == nil, "Level 4 is known, level 5 is not")
check(type(done.TimeGoal) == "table" and next(done.TimeGoal) == nil and done.Extra == nil, "garbage is rebuilt empty")

-- 7. Rows for the RECORDS page.
data = profile()
C.Apply(data, 1, run(), settings, 1)
local rows = C.Rows(data.Records, data.Challenges, settings)
check(#rows == #settings.Levels and rows[1].Level == 1, "one row per level")
check(rows[1].Records["solo:clean"].Best == 300 and rows[1].NoDeath and rows[1].TimeGoalDone, "row 1 carries the record and both ticks")
check(rows[2].Records["solo:clean"] == nil and not rows[2].NoDeath, "row 2 is empty")
check(#rows == 4 and rows[4].Level == 4 and rows[4].TimeGoal == 720, "row 4 is Level 4 with its 12:00 goal")
check(rows[4].Records["solo:clean"] == nil and not rows[4].NoDeath and not rows[4].TimeGoalDone, "and empty until played")
check(C.FormatTime(300) == "5:00" and C.FormatTime(59.6) == "1:00" and C.FormatTime(605) == "10:05", "m:ss formatting")
check(C.Rows(nil, nil, settings)[1].Records["solo:clean"] == nil, "rows survive a profile without records")

for _, message in ipairs(failures) do print("FAIL: " .. message) end
assert(#failures == 0, #failures .. " of " .. checks .. " challenge checks failed")
print(("ZyntraChallenges: %d checks passed (real module, real Config.Challenges)"):format(checks))
'''


def main():
    binary = os.environ.get("LUAU_BIN") or shutil.which("luau")
    if not binary:
        raise SystemExit("Set LUAU_BIN or install luau; no tests were executed.")
    assert "Challenges = {" in CONFIG, "ZyntraConfig has no Challenges block"
    script = "\n".join([
        # ZyntraConfig carries colours; nothing in the ledger reads them.
        "local Color3 = {fromRGB = function(r, g, b) return {R = r, G = g, B = b} end,"
        " new = function(r, g, b) return {R = r, G = g, B = b} end}",
        "local Config = (function()\n" + CONFIG + "\nend)()",
        "local C = (function()\n" + MODULE + "\nend)()",
        TESTS,
    ])
    with tempfile.TemporaryDirectory(prefix="challenges-") as directory:
        fixture = Path(directory) / "challenges.luau"
        fixture.write_text(script, encoding="utf-8")
        subprocess.run([binary, str(fixture)], check=True, timeout=60)


if __name__ == "__main__":
    main()
