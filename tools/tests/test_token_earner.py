"""Token Earner tiers, offers and payout (Trello EtdsUM4e).

TOKEN_EARNER_20260924. Runs the REAL ZyntraConfig.TokenEarner (Tier, Offer and
the six pass records) and the REAL applyReward + tokenEarner block sliced out
of ZyntraMonetization. Tier and Offer are checked over all 64 ownership sets
against an independent reference and a brute-force cheapest-pass search.
test_completion_save.py covers the clear payout under a multiplier.
What only Studio/live can show: real Game Pass ownership reads and prompts.
Set LUAU_BIN, or put luau on PATH.
"""

import os
from pathlib import Path
import shutil
import subprocess
import tempfile

ROOT = Path(__file__).resolve().parents[2]
CONFIG = (ROOT / "ReplicatedStorage/ZyntraConfig.ModuleScript.lua").read_text(encoding="utf-8")
SERVER = (ROOT / "ServerScriptService/ZyntraMonetization.Script.lua").read_text(encoding="utf-8")


def section(source, start, stop):
    begin = source.index(start)
    return source[begin:source.index(stop, begin)]


TESTS = r'''
local checks = 0
local function equal(actual, expected, message)
    assert(actual == expected, message .. ": expected " .. tostring(expected) .. ", got " .. tostring(actual))
    checks += 1
end
local E = Config.TokenEarner
local KEYS = {"TokenEarner2x", "TokenEarner3x", "TokenEarner5x", "TokenEarnerUp2to3", "TokenEarnerUp3to5", "TokenEarnerUp2to5"}
equal(E.Passes.TokenEarner2x.Id, 1995218405, "2x pass id")
equal(E.Passes.TokenEarnerUp2to5.Id, 1994252411, "2->5 pass id")
local prices = {TokenEarner2x = 149, TokenEarner3x = 299, TokenEarner5x = 399,
    TokenEarnerUp2to3 = 150, TokenEarnerUp3to5 = 100, TokenEarnerUp2to5 = 250}
for key, price in pairs(prices) do equal(E.Passes[key].Price, price, key .. " approved price") end

-- independent reference: direct tiers, and each upgrade only on its prerequisite
local function reference(o)
    local best = 1
    if o.TokenEarner2x then best = 2 end
    local eff3 = o.TokenEarner3x or (o.TokenEarner2x and o.TokenEarnerUp2to3)
    if eff3 then best = 3 end
    if o.TokenEarner5x or (o.TokenEarner2x and o.TokenEarnerUp2to5) or (eff3 and o.TokenEarnerUp3to5) then best = 5 end
    return best
end
for mask = 0, 63 do
    local owns = {}
    for i, key in ipairs(KEYS) do if bit32.btest(mask, bit32.lshift(1, i - 1)) then owns[key] = true end end
    local tier = E.Tier(owns)
    equal(tier, reference(owns), "tier for set " .. mask)
    for _, target in ipairs({2, 3, 5}) do
        local offer = E.Offer(E.Passes, E.Tier, owns, target)
        if tier >= target then
            equal(offer, nil, "no offer once tier " .. target .. " is reached (set " .. mask .. ")")
        else
            assert(offer and not owns[offer], "offer exists and is never an owned pass (set " .. mask .. ")")
            local trial = table.clone(owns); trial[offer] = true
            assert(E.Tier(trial) >= target, "offer reaches the target")
            for _, key in ipairs(KEYS) do
                if not owns[key] then
                    local t = table.clone(owns); t[key] = true
                    assert(E.Tier(t) < target or E.Passes[key].Price >= E.Passes[offer].Price,
                        "offer is the cheapest single pass (set " .. mask .. ")")
                end
            end
            checks += 3
        end
    end
end
equal(E.Offer(E.Passes, E.Tier, {}, 3), "TokenEarner3x", "new player: direct 3x")
equal(E.Offer(E.Passes, E.Tier, {TokenEarner2x = true}, 3), "TokenEarnerUp2to3", "2x owner: 150 upgrade")
equal(E.Offer(E.Passes, E.Tier, {TokenEarner2x = true}, 5), "TokenEarnerUp2to5", "2x owner: 250 upgrade")
equal(E.Offer(E.Passes, E.Tier, {TokenEarner3x = true}, 5), "TokenEarnerUp3to5", "3x owner: 100 upgrade")
equal(E.Offer(E.Passes, E.Tier, {TokenEarner2x = true, TokenEarnerUp3to5 = true}, 5), "TokenEarnerUp2to3",
    "an early 3->5 upgrade makes 2->3 the way to 5x")
equal(E.Tier({TokenEarnerUp2to5 = true}), 1, "an upgrade alone grants nothing")
equal(E.Tier({TokenEarner2x = true, TokenEarner3x = true}), 3, "tiers do not stack")

-- server payout helpers
local data = {Tokens = 10, Items = {SpeedPotion = 0}}
equal(applyReward(data, {Kind = "Tokens", Amount = 3}, 5), "15 Research Tokens", "wheel/playtime tokens x5")
equal(data.Tokens, 25, "paid 15")
equal(applyReward(data, {Kind = "Tokens", Amount = 1}, 4), "1 Research Token", "invalid tier pays 1x")
equal(applyReward(data, {Kind = "Item", Key = "SpeedPotion", Amount = 2}, 5), "2 Speed Potions", "items are never multiplied")
equal(data.Items.SpeedPotion, 2, "two potions")
local player = {GetAttribute = function(_, name) return name == "ZyntraTokenEarnerMultiplier" and 3 or nil end}
equal(tokenEarner.tier(player), 3, "tier read from the published attribute")
equal(tokenEarner.bonus(data, 2, 3), 4, "3x tops 2 earned up by 4")
equal(tokenEarner.bonus(data, 2, 1), 0, "1x adds nothing")
data.Tokens = MAX_SAFE_SUPPORT - 1
equal(tokenEarner.bonus(data, 2, 5), 0, "never overflows the balance")

print(("token earner: %d checks passed (real Config.TokenEarner + applyReward + tokenEarner)"):format(checks))
'''


def main():
    binary = os.environ.get("LUAU_BIN") or shutil.which("luau")
    if not binary:
        raise SystemExit("Set LUAU_BIN or install luau; no tests were executed.")
    helpers = section(SERVER, "-- `tier` (TOKEN_EARNER_20260924) multiplies", "-- Live playtime accrual")
    stubs = "\n".join([
        "local Color3 = {fromRGB = function(...) return {...} end, new = function(...) return {...} end}",
        "local Config = (function()", CONFIG, "end)()",
        "local MAX_SAFE_SUPPORT = 9007199254740991",
        "local function wholeCount(v) v = tonumber(v) or 0 return v == v and v >= 0 and math.floor(v) or 0 end",
        "local function isSafeSupportAmount(v) return type(v) == 'number' and v >= 0 and v <= MAX_SAFE_SUPPORT end",
        "local function protectionState() return nil end",
        "local ITEM_CONFIG = {SpeedPotion = {Name = 'Speed Potion'}}",
    ])
    source = stubs + "\n" + helpers + "\n" + TESTS
    with tempfile.TemporaryDirectory(prefix="token-earner-") as directory:
        path = Path(directory) / "token_earner.luau"
        path.write_text(source, encoding="utf-8")
        subprocess.run([binary, str(path)], check=True, timeout=60)


if __name__ == "__main__":
    main()
