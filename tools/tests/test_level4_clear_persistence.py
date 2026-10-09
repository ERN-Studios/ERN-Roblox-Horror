"""Level 4 clears persist (owner decision 2026-10-02).

Runs the REAL profile block out of ZyntraMonetization.Script.lua (colorData ..
normalizeProfile) with the REAL ZyntraConfig, ZyntraDailyResearch, ZyntraSkins
and ZyntraChallenges modules under the Luau interpreter, and checks that a
Level 4 clear, its badge flag and its records/challenges survive a load, while
anything beyond Level 4 is still dropped. Also pins, at source level, the clear
handler's tracked bound and the CampaignComplete condition (1-4 since the
owner decision of 2026-10-05; it was 1-3 before).

Set LUAU_BIN to the official Luau executable, or put luau on PATH.
"""
from pathlib import Path
import os
import re
import shutil
import subprocess
import tempfile

ROOT = Path(__file__).resolve().parents[2]
SERVER = (ROOT / "ServerScriptService/ZyntraMonetization.Script.lua").read_text(encoding="utf-8")
CONFIG = (ROOT / "ReplicatedStorage/ZyntraConfig.ModuleScript.lua").read_text(encoding="utf-8")
RESEARCH = (ROOT / "ReplicatedStorage/ZyntraDailyResearch.ModuleScript.lua").read_text(encoding="utf-8")
SKINS = (ROOT / "ReplicatedStorage/ZyntraSkins.ModuleScript.lua").read_text(encoding="utf-8")
CHALLENGES = (ROOT / "ReplicatedStorage/ZyntraChallenges.ModuleScript.lua").read_text(encoding="utf-8")


def section(start, stop):
    begin = SERVER.index(start)
    return SERVER[begin:SERVER.index(stop, begin)]


def module(source):
    return "(function()\n" + source + "\nend)()"


def source_checks():
    handler = section("levelCompletedEvent.Event:Connect", "MarketplaceService.PromptGamePassPurchaseFinished")
    tracked = re.findall(r"local tracked = (.+)", handler)
    assert tracked == ["cleared >= 1 and cleared <= 4"], f"clear handler tracked bound: {tracked}"
    # ACHIEVEMENTS_20261004: CampaignComplete is unlocked through achievementApi.unlock (was awardBadge).
    campaign = re.search(r"if (levelsCleared and [^\n]*) then\s*\n\s*(?:awardBadge|achievementApi\.unlock)\(player, \"CampaignComplete\"\)", handler)
    assert campaign, "CampaignComplete award not found behind a levelsCleared condition"
    named = re.findall(r'levelsCleared\["([^"]*)"\]', campaign.group(1))
    # Owner 2026-10-05: Level 3 continues to Level 4, so the campaign is Levels 1-4 (was exactly 1,2,3).
    assert named == ["1", "2", "3", "4"], f"CampaignComplete must name exactly 1,2,3,4, got {named}"
    assert "levelsCleared[" not in campaign.group(1).replace('levelsCleared["', ""), \
        "CampaignComplete condition reads a non-literal level key"
    backfill = re.search(r"if (achievements\.FirstClearLevel.*?) then achievements\.CampaignComplete = true end", SERVER, re.S)
    assert backfill, "CampaignComplete profile-load backfill not found"
    filled = re.findall(r"achievements\.FirstClearLevel(\w+)", backfill.group(1))
    assert filled == ["1", "2", "3", "4"], f"CampaignComplete backfill must name FirstClearLevel1..4, got {filled}"
    print("level4 clear persistence: source checks passed (tracked <= 4, CampaignComplete 1-4, backfill 1-4)")


HARNESS = r'''
local checks = 0
local function check(value, message)
    checks += 1
    assert(value, message)
end
local function eq(actual, expected, message)
    check(actual == expected,
        message .. ": expected " .. tostring(expected) .. ", got " .. tostring(actual))
end
local function keys(t)
    local list = {}
    for key in pairs(t) do table.insert(list, tostring(key) .. "=" .. type(key)) end
    table.sort(list)
    return table.concat(list, ",")
end

local Color3 = {fromRGB = function(r, g, b) return {R = r / 255, G = g / 255, B = b / 255} end}
local Config = CONFIG_MODULE
local modules = {
    ZyntraDailyResearch = RESEARCH_MODULE,
    ZyntraSkins = SKINS_MODULE,
    ZyntraChallenges = CHALLENGES_MODULE,
}
local ReplicatedStorage = {}
function ReplicatedStorage:WaitForChild(name) return assert(modules[name], name) end
local function require(value) return value end
local RunService = {IsStudio = function() return false end}
local game = {JobId = "job-1"}
local sessions = {}
local ACCESSIBILITY_SETTINGS = Config.AccessibilitySettings or {}

PROFILE_BLOCK

-- The config this build ships.
check(table.find(Config.Challenges.Levels, 4) ~= nil, "Challenges.Levels includes 4")
eq(Config.Challenges.TimeGoalSeconds["4"], 720, "Level 4 time goal")
check(Config.Badges.FirstClearLevel4 ~= nil, "FirstClearLevel4 is a known badge key")

-- 1. Levels 1-4 as saved string keys all survive.
do
    local data = normalizeProfile({LevelsCleared = {["1"] = true, ["2"] = true, ["3"] = true, ["4"] = true}})
    eq(keys(data.LevelsCleared), "1=string,2=string,3=string,4=string", "levels 1-4 survive normalization")
    data = normalizeProfile(data)
    eq(keys(data.LevelsCleared), "1=string,2=string,3=string,4=string", "and a second load keeps them")
end

-- 2. A numeric 4 from an older write is accepted once and re-saved as "4".
do
    local data = normalizeProfile({LevelsCleared = {[4] = true}})
    eq(data.LevelsCleared["4"], true, "numeric key 4 is accepted")
    eq(data.LevelsCleared[4], nil, "and no numeric key remains")
    eq(keys(data.LevelsCleared), "4=string", "it is re-saved as the string \"4\" only")
end

-- 3. Level 5, out-of-range and junk keys are dropped.
do
    local data = normalizeProfile({LevelsCleared = {
        ["5"] = true, [5] = true, ["0"] = true, [0] = true, junk = true, ["4"] = "yes", ["3"] = 1, ["2"] = true,
    }})
    eq(keys(data.LevelsCleared), "2=string", "only a real true for a known level survives")
end

-- 4. AwardedBadges keeps FirstClearLevel4 (a known key) and drops unknown keys.
do
    local data = normalizeProfile({AwardedBadges = {
        FirstClearLevel1 = true, FirstClearLevel4 = true, CampaignComplete = true,
        FirstClearLevel5 = true, Bogus = true, FirstClearLevel2 = false,
    }})
    -- ACHIEVEMENTS_20261004 made FirstClearLevel5 a known Config.Badges key, so it now survives; Bogus still drops.
    check(Config.Badges.FirstClearLevel5 ~= nil and Config.Badges.Bogus == nil, "FirstClearLevel5 known, Bogus unknown")
    eq(keys(data.AwardedBadges), "CampaignComplete=string,FirstClearLevel1=string,FirstClearLevel4=string,FirstClearLevel5=string",
        "known badge flags survive, unknown and non-true ones are dropped")
end

-- 5. Level 4 records and challenges survive; Level 5 ones are dropped.
do
    local data = normalizeProfile({
        Records = {
            ["4:solo:clean"] = {Best = 300.04, Equipped = true, At = 1789516800},
            ["4:party:assisted"] = {Best = 650, At = 7},
            ["5:solo:clean"] = {Best = 100, At = 1},
        },
        Challenges = {
            NoDeath = {["4"] = true, ["5"] = true},
            TimeGoal = {["4"] = true, ["1"] = true},
        },
    })
    local solo = data.Records["4:solo:clean"]
    check(solo ~= nil, "the Level 4 solo clean record survives")
    eq(solo.Best, 300, "its time keeps tenths")
    eq(solo.Equipped, true, "and its Equipped flag")
    eq(solo.At, 1789516800, "and its timestamp")
    eq(data.Records["4:party:assisted"].Best, 650, "the Level 4 party assisted record survives")
    eq(data.Records["5:solo:clean"], nil, "a Level 5 record is dropped")
    eq(keys(data.Challenges.NoDeath), "4=string", "the Level 4 NoDeath flag survives, Level 5 is dropped")
    eq(keys(data.Challenges.TimeGoal), "1=string,4=string", "the Level 4 TimeGoal flag survives")
    data = normalizeProfile(data)
    eq(data.Records["4:solo:clean"].Best, 300, "a second load keeps the Level 4 record")
    eq(data.Challenges.NoDeath["4"], true, "and the Level 4 challenge")
end

print(string.format("level4 clear persistence: %d checks passed", checks))
'''


def main():
    source_checks()
    luau = os.environ.get("LUAU_BIN") or shutil.which("luau")
    if not luau:
        raise SystemExit("Set LUAU_BIN or put luau on PATH")
    script = (HARNESS
              .replace("CONFIG_MODULE", module(CONFIG))
              .replace("RESEARCH_MODULE", module(RESEARCH))
              .replace("SKINS_MODULE", module(SKINS))
              .replace("CHALLENGES_MODULE", module(CHALLENGES))
              .replace("PROFILE_BLOCK", section("local function colorData", "local function isDispatchPredecessorClosed")))
    with tempfile.TemporaryDirectory(prefix="level4-clear-") as directory:
        path = Path(directory) / "level4_clear_persistence.luau"
        path.write_text(script, encoding="utf-8")
        result = subprocess.run([luau, str(path)], capture_output=True, text=True, timeout=120)
    if result.stdout:
        print(result.stdout, end="")
    if result.stderr:
        print(result.stderr, end="")
    raise SystemExit(result.returncode)


if __name__ == "__main__":
    main()
