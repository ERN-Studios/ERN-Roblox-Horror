"""Lobby rail notification dots and the one-time rewards intro (Trello MsEn2mya), offline Luau.

Runs the REAL predicates sliced out of ZyntraStore.LocalScript.lua by their
markers (RAIL_DOTS_20260922 / REWARDS_INTRO_20260922) against the REAL
ZyntraConfig: when the REWARDS dot and the WHEEL dot are due, and when the
intro is wanted. The profile shapes are the ones ZyntraMonetization.dailyPublic
publishes (Today, PlaytimeSeconds, Claimed, WheelDay, WheelLast).

What still needs Studio: the dot's pixels on the rail, the card's placement on
a phone, and the quiet-moment timing against a real win/Return. Set LUAU_BIN.
"""

from pathlib import Path
import os
import subprocess
import tempfile

ROOT = Path(__file__).resolve().parents[2]
STORE = (ROOT / "StarterPlayer/StarterPlayerScripts/ZyntraStore.LocalScript.lua").read_text(encoding="utf-8")
CONFIG = (ROOT / "ReplicatedStorage/ZyntraConfig.ModuleScript.lua").read_text(encoding="utf-8")


def section(source, start, stop):
    begin = source.index(start)
    return source[begin:source.index(stop, begin)]


DOTS = section(STORE, "-- RAIL_DOTS_20260922 BEGIN", "-- RAIL_DOTS_20260922 END")
INTRO = section(STORE, "-- REWARDS_INTRO_20260922 BEGIN", "-- REWARDS_INTRO_20260922 END")

SCRIPT = r'''
local checks = 0
local function expect(value, wanted, message)
    checks += 1
    assert(value == wanted, message .. ': expected ' .. tostring(wanted) .. ', got ' .. tostring(value))
end
local Color3 = {fromRGB = function(r, g, b) return {R = r, G = g, B = b} end, new = function() return {} end}
local Config = (function()
''' + CONFIG + r'''
end)()
''' + DOTS + INTRO + r'''

local TODAY = "2026-09-22"
local function daily(fields)
    local block = {Day = TODAY, Today = TODAY, PlaytimeSeconds = 0, Claimed = {}, SecondsToReset = 3600}
    for k, v in pairs(fields or {}) do block[k] = v end
    return {Daily = block, CompletedLevels = 0}
end

-- REWARDS: a milestone reached and unclaimed
expect(rewardsClaimable(nil), false, "no profile -> no dot")
expect(rewardsClaimable({}), false, "no Daily -> no dot")
expect(rewardsClaimable(daily({PlaytimeSeconds = 299})), false, "under the first milestone -> no dot")
expect(rewardsClaimable(daily({PlaytimeSeconds = 300})), true, "five minutes reached -> dot")
expect(rewardsClaimable(daily({PlaytimeSeconds = 300, Claimed = {["5"] = true}})), false, "claimed -> no dot")
expect(rewardsClaimable(daily({PlaytimeSeconds = 900, Claimed = {["5"] = true}})), true, "the next milestone reached -> dot again")
expect(rewardsClaimable(daily({PlaytimeSeconds = 99999, Claimed = {["5"] = true, ["15"] = true, ["35"] = true}})), false, "everything claimed -> no dot")

-- WHEEL: a free spin, or a prize still owed
expect(wheelClaimable(nil), false, "no profile -> no dot")
expect(wheelClaimable(daily({})), true, "never spun today -> free spin -> dot")
expect(wheelClaimable(daily({WheelDay = "2026-09-21", WheelLast = {Day = "2026-09-21", Key = "Token1", Serial = 3, Claimed = true}})), true, "spun yesterday and collected -> today's spin is free -> dot")
expect(wheelClaimable(daily({WheelDay = TODAY, WheelLast = {Day = TODAY, Key = "Token1", Serial = 4, Claimed = true}})), false, "spun today and collected -> no dot")
expect(wheelClaimable(daily({WheelDay = TODAY, WheelLast = {Day = TODAY, Key = "Token1", Serial = 4, Claimed = false}})), true, "spun today, prize owed -> dot")
expect(wheelClaimable(daily({WheelDay = "2026-09-21", WheelLast = {Day = "2026-09-21", Key = "Potion2", Serial = 2, Claimed = false}})), true, "yesterday's prize still owed -> dot")
expect(wheelClaimable(daily({WheelDay = TODAY, WheelLast = {Day = TODAY, Key = "Token1", Serial = 4}})), false, "a historical result (no Claimed field) counts as collected")
expect(wheelClaimable(daily({Today = ""})), false, "no day published -> no dot rather than a guess")

-- INTRO: after the first real completion, until seen
expect(introWanted(nil), false, "no profile -> no intro")
expect(introWanted({CompletedLevels = 0}), false, "no completion -> no intro")
expect(introWanted({CompletedLevels = 1}), true, "first completion -> intro")
expect(introWanted({CompletedLevels = 1, RewardsIntroSeen = true}), false, "seen -> never again")
expect(introWanted({CompletedLevels = 7, RewardsIntroSeen = false}), true, "a veteran who never saw it sees it once")

print('rail dots + intro: ' .. checks .. ' checks passed (offline; pixels, phone placement and quiet-moment timing need Studio)')
'''


def main():
    luau = os.environ.get("LUAU_BIN")
    if not luau:
        raise SystemExit("set LUAU_BIN to a Luau interpreter")
    with tempfile.TemporaryDirectory() as tmp:
        path = Path(tmp) / "rail_dots.luau"
        path.write_text(SCRIPT, encoding="utf-8")
        result = subprocess.run([luau, str(path)], capture_output=True, text=True)
        print(result.stdout.strip())
        if result.returncode != 0:
            raise SystemExit(result.stderr.strip() or result.stdout.strip() or "luau failed")


if __name__ == "__main__":
    main()
