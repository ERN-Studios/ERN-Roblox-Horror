"""Exercise the production hazmat catalogue's profile and purchase rules in Luau.

Set LUAU_BIN to an official Luau interpreter, or put luau on PATH. The fixture
uses the actual ModuleScript body; no Roblox services or DataStore are needed.
"""

from pathlib import Path
import os
import shutil
import subprocess
import tempfile


ROOT = Path(__file__).resolve().parents[2]
MODULE = ROOT / "ReplicatedStorage" / "ZyntraSkins.ModuleScript.lua"

CHECKS = r'''
local Skins = (function()
__SOURCE__
end)()

local checks = 0
local function expect(value, message)
    checks += 1
    assert(value, message)
end

local fresh = Skins.Normalize(nil)
expect(fresh.Owned.BaselineYellow == true, "baseline must be free")
expect(fresh.Equipped == "BaselineYellow", "baseline must be equipped by default")

local corrupted = Skins.Normalize({
    Owned = {SuburbSurvey = true, FakeAdminSkin = true, StaticWraith = "true"},
    Equipped = "FakeAdminSkin",
})
expect(corrupted.Owned.SuburbSurvey == true, "known grant was lost")
expect(corrupted.Owned.FakeAdminSkin == nil, "unknown ownership survived normalization")
expect(corrupted.Owned.StaticWraith == nil, "non-boolean ownership was accepted")
expect(corrupted.Equipped == "BaselineYellow", "unowned equipped ID survived")

local data = {Tokens = 25, CompletedLevels = 0, Skins = fresh}
local ok = Skins.BuyToken(data, "PoolService")
expect(ok == true and data.Tokens == 0, "exact-price Pool Service buy failed")
expect(data.Skins.Owned.PoolService == true, "successful purchase did not grant")
ok = Skins.BuyToken(data, "PoolService")
expect(ok == false and data.Tokens == 0, "duplicate purchase charged again")
ok = Skins.BuyToken(data, "StaticWraith")
expect(ok == false and data.Skins.Owned.StaticWraith == nil,
    "Robux skin must never be Token-purchasable")

local gated = {Tokens = 300, CompletedLevels = 99, Skins = Skins.Normalize(nil)}
ok = Skins.BuyToken(gated, "BlacksiteDirector")
expect(ok == false and gated.Tokens == 300, "99 clears bypassed Director gate")
gated.CompletedLevels = 100
ok = Skins.BuyToken(gated, "BlacksiteDirector")
expect(ok == true and gated.Tokens == 0 and gated.Skins.Owned.BlacksiteDirector,
    "Director did not unlock at exactly 100 clears and 300 Tokens")

local tooPoor = {Tokens = 74, CompletedLevels = 100, Skins = Skins.Normalize(nil)}
ok = Skins.BuyToken(tooPoor, "SuburbSurvey")
expect(ok == false and tooPoor.Tokens == 74, "insufficient Tokens were spent")

local state = Skins.Normalize(nil)
ok = Skins.Equip(state, "FalseSun")
expect(ok == false and state.Equipped == "BaselineYellow", "unowned skin equipped")
expect(Skins.Grant(state, "FalseSun") == true, "trusted grant failed")
expect(Skins.Grant(state, "FalseSun") == false, "duplicate grant not idempotent")
expect(Skins.Grant(state, "FakeAdminSkin") == false, "unknown skin was granted")
expect(Skins.BuyToken({Tokens = 999, CompletedLevels = 999, Skins = state},
    "FakeAdminSkin") == false, "unknown skin was purchasable")
ok = Skins.Equip(state, "FalseSun")
expect(ok == true and state.Equipped == "FalseSun", "owned skin did not equip")
local rejoined = Skins.Normalize(state)
expect(rejoined.Equipped == "FalseSun" and rejoined.Owned.FalseSun,
    "ownership/equip did not survive normalization")

expect(#Skins.WheelEligible == 2 and Skins.WheelEligible[1] == "PoolService"
    and Skins.WheelEligible[2] == "SuburbSurvey", "wheel pool includes wrong skins")
expect(Skins.ById.StaticWraith.PassId == 1994666374
    and Skins.ById.StaticWraith.RobuxPrice == 99,
    "Static Wraith pass ID or price drifted")
expect(Skins.ById.FalseSun.PassId == 1994816385
    and Skins.ById.FalseSun.RobuxPrice == 149,
    "False Sun pass ID or price drifted")

-- DEV_SUIT_20260924: the Developer suit follows DevAccess only.
do
	local dev = Skins.Normalize(nil)
	expect(not Skins.BuyToken({Tokens = 9999, CompletedLevels = 9999, Skins = dev}, "SignalArchitect"), "no token path to the developer suit")
	expect(Skins.SyncDeveloper(dev, true) and Skins.IsOwned(dev, "SignalArchitect"), "a developer is granted it")
	expect(not Skins.SyncDeveloper(dev, true), "an unchanged developer costs no write")
	expect(Skins.Equip(dev, "SignalArchitect") and dev.Equipped == "SignalArchitect", "and can equip it")
	expect(Skins.SyncDeveloper(dev, false) and not Skins.IsOwned(dev, "SignalArchitect"), "access removed: revoked")
	expect(dev.Equipped == Skins.DefaultId, "and the equipped suit falls back to the default")
	expect(not Skins.SyncDeveloper(Skins.Normalize(nil), false), "an ordinary player never changes")
	expect(not table.find(Skins.WheelEligible, "SignalArchitect"), "never a wheel prize")
end
print("Zyntra skins: " .. tostring(checks) .. " checks passed")
'''


def main():
    luau = os.environ.get("LUAU_BIN") or shutil.which("luau")
    if not luau:
        raise SystemExit("Set LUAU_BIN or put luau on PATH; no tests executed.")
    source = CHECKS.replace("__SOURCE__", MODULE.read_text(encoding="utf-8"))
    with tempfile.TemporaryDirectory(prefix="zyntra-skins-") as directory:
        path = Path(directory) / "skins.luau"
        path.write_text(source, encoding="utf-8")
        result = subprocess.run([luau, str(path)], capture_output=True, text=True, timeout=60)
    if result.stdout:
        print(result.stdout, end="")
    if result.stderr:
        print(result.stderr, end="")
    raise SystemExit(result.returncode)


if __name__ == "__main__":
    main()
