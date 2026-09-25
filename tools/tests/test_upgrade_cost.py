"""Escalating Stamina/Battery upgrade price (Trello KF7FDmP1).

UPGRADE_COST_20260924. Runs the REAL ZyntraConfig.UpgradeCost and the REAL
UpgradeStamina/UpgradeBattery branch sliced out of ZyntraMonetization's action
handler, against a fake mutate that applies the transform to a separate
"stored" profile -- so a stale session copy and the profile actually written
can disagree, as they do across servers. Static check: the shop writes the
Spend label before its layout pass measures it. Set LUAU_BIN, or put luau on PATH.
"""

import os
from pathlib import Path
import shutil
import subprocess
import tempfile

ROOT = Path(__file__).resolve().parents[2]
CONFIG = (ROOT / "ReplicatedStorage/ZyntraConfig.ModuleScript.lua").read_text(encoding="utf-8")
SERVER = (ROOT / "ServerScriptService/ZyntraMonetization.Script.lua").read_text(encoding="utf-8")
STORE = (ROOT / "StarterPlayer/StarterPlayerScripts/ZyntraStore.LocalScript.lua").read_text(encoding="utf-8")


def section(source, start, stop):
    begin = source.index(start)
    return source[begin:source.index(stop, begin)]


TESTS = r'''
local checks = 0
local function equal(actual, expected, message)
    assert(actual == expected, message .. ": expected " .. tostring(expected) .. ", got " .. tostring(actual))
    checks += 1
end

equal(Config.UpgradeCost(0), 1, "level 1 still costs 1")
equal(Config.UpgradeCost(9), 10, "level 10 costs 10")
equal(Config.UpgradeCost(-3), 1, "a corrupt negative level never discounts")
equal(Config.UpgradeCost(2.7), 3, "fractional levels floor")

local player = {}
local sessions, stored, pushes, writes = {}, nil, {}, 0
local function pushProfile(_, message, tone) table.insert(pushes, {message, tone}) end
local function mutate(_, transform)
    local copy = table.clone(stored)
    local changed, message, tone = transform(copy)
    if changed then stored = copy writes += 1 end
    sessions[player].data = table.clone(stored)
    table.insert(pushes, {message, tone})
    return changed
end
local PCT = "+5%"
local function press(action)
    if false then
__BRANCH__
    end
end
local function setup(sessionData, storedData)
    sessions[player] = {data = sessionData}
    stored, pushes, writes = storedData, {}, 0
end

setup({Tokens = 1, StaminaLevel = 0, BatteryLevel = 0}, {Tokens = 1, StaminaLevel = 0, BatteryLevel = 0})
press("UpgradeStamina")
equal(stored.StaminaLevel, 1, "first level bought")
equal(stored.Tokens, 0, "for one token")

setup({Tokens = 1, StaminaLevel = 1, BatteryLevel = 0}, {Tokens = 1, StaminaLevel = 1, BatteryLevel = 0})
press("UpgradeStamina")
equal(writes, 0, "one token short: nothing written")
equal(pushes[1][1], "You need 2 Zyntra Research Tokens.", "refusal names the real price")

setup({Tokens = 10, StaminaLevel = 0, BatteryLevel = 9}, {Tokens = 10, StaminaLevel = 0, BatteryLevel = 9})
press("UpgradeBattery")
equal(stored.BatteryLevel, 10, "battery level 10 bought")
equal(stored.Tokens, 0, "for ten tokens")
equal(stored.StaminaLevel, 0, "the other track is untouched")

-- stale session says level 0; the written profile is at level 3
setup({Tokens = 5, StaminaLevel = 0, BatteryLevel = 0}, {Tokens = 5, StaminaLevel = 3, BatteryLevel = 0})
press("UpgradeStamina")
equal(stored.StaminaLevel, 4, "price taken from the profile being written")
equal(stored.Tokens, 1, "charged the level-4 price")

-- stale session looks rich; the written profile cannot pay
setup({Tokens = 9, StaminaLevel = 2, BatteryLevel = 0}, {Tokens = 2, StaminaLevel = 2, BatteryLevel = 0})
press("UpgradeStamina")
equal(writes, 0, "cross-server race: refused inside the transform")
equal(stored.Tokens, 2, "and nothing charged")

print(("upgrade cost: %d checks passed (real Config.UpgradeCost + server branch)"):format(checks))
'''


def main():
    binary = os.environ.get("LUAU_BIN") or shutil.which("luau")
    if not binary:
        raise SystemExit("Set LUAU_BIN or install luau; no tests were executed.")
    branch = section(SERVER, '\telseif action == "UpgradeStamina" or action == "UpgradeBattery" then',
                     '\telseif action == "SetHazmatColor" then')
    refresh = section(STORE, "-- UPGRADE_COST_20260924: written BEFORE", "staminaCard.Current.Text")
    assert "applyTerminalLayout()" in refresh and refresh.index("card.Spend.Text") < refresh.index(
        "applyTerminalLayout()"), "Spend label must be written before the layout pass"
    # ZyntraConfig builds a few Color3 values; nothing here reads them.
    source = ("local Color3 = {fromRGB = function(...) return {...} end, new = function(...) return {...} end}\n"
              "local Config = (function()\n") + CONFIG + "\nend)()\n" + TESTS.replace("__BRANCH__", branch)
    with tempfile.TemporaryDirectory(prefix="upgrade-cost-") as directory:
        path = Path(directory) / "upgrade_cost.luau"
        path.write_text(source, encoding="utf-8")
        subprocess.run([binary, str(path)], check=True, timeout=60)


if __name__ == "__main__":
    main()
