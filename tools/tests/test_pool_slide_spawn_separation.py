"""Pool Slide spawn separation counts shielded / re-entry-graced players.

Slices the REAL livingRecord/livingRecords, spawnPumpPosition, candidates and
distance out of the controller, plus the exact record expressions spawnModel
uses, into a fake engine. A protected player stands next to the best-scoring
anchor; that anchor must be rejected (audit finding 13, 2026-09-24), while
targeting (the plain two-argument call) still skips the protected player.

Run: LUAU_BIN=<path to luau> python tools/tests/test_pool_slide_spawn_separation.py
"""
import os
import re
import shutil
import subprocess
import tempfile
from pathlib import Path

ROOT = Path(__file__).resolve().parents[2]
CONTROLLER = ROOT / "ServerScriptService" / "Level 2 Systems" / "Level 2 Pool Slide Controller.ModuleScript.lua"


def section(source, start, end):
    begin = source.index(start)
    return source[begin:source.index(end, begin)]


def spawn_expression(spawn, pattern):
    match = re.search(pattern, spawn)
    assert match, f"spawnModel no longer contains {pattern!r}"
    return match.group(1)


HARNESS = r'''
local checks = 0
local function expect(actual, wanted, label)
    if actual ~= wanted then error(label .. ": wanted " .. tostring(wanted) .. ", got " .. tostring(actual), 2) end
    checks += 1
end

local V = {}
V.__index = function(self, key) if key == "Magnitude" then return math.sqrt(self.X ^ 2 + self.Y ^ 2 + self.Z ^ 2) end end
V.__add = function(a, b) return setmetatable({X = a.X + b.X, Y = a.Y + b.Y, Z = a.Z + b.Z}, V) end
local Vector3 = {new = function(x, y, z) return setmetatable({X = x, Y = y, Z = z}, V) end}

local Players = {}
local roster = {}
function Players:GetPlayers() return roster end
local function makePlayer(name, x, protected)
    local root = {Position = Vector3.new(x, 0, 0), IsA = function(_, class) return class == "BasePart" end}
    local humanoid = {Health = 100}
    local character = {Parent = true,
        FindFirstChildOfClass = function(_, class) return class == "Humanoid" and humanoid or nil end,
        FindFirstChild = function(_, name) return name == "HumanoidRootPart" and root or nil end}
    local player = {Name = name, UserId = #roster + 1, Parent = Players, Character = character, Protected = protected,
        GetAttribute = function(_, key) return key == "InRound" or nil end}
    table.insert(roster, player)
    return player
end
local PlayerProtection = {IsActive = function(player) return player.Protected == true end}
local function roundReady() return true end
local function stateFolder() return nil end
local function clearLine() return false end
local SPAWN_PUMPS, SPAWN_MINIMUM_DISTANCE = 2, 100

__DISTANCE__
__LIVING__
__CANDIDATES__

local shielded = makePlayer("Shielded", 0, true)
local activator = makePlayer("Activator", 300, false)
local world = {}
local function anchor(name, x)
    return {Name = name, Position = Vector3.new(x, 0, 0), IsDescendantOf = function(_, parent) return parent == world end}
end
local session = {Manifest = {World = world},
    Anchors = {anchor("NextToShielded", 10), anchor("Midway", 150)}}

-- spawnModel's own record expression feeds candidates().
local records = __RECORDS__
local ranked = candidates(session, records)
expect(#ranked, 1, "anchor 10 studs from a shielded player is excluded")
expect(ranked[1].Anchor.Name, "Midway", "only the anchor >= 100 studs from EVERY player survives")
expect(ranked[1].Nearest.Player, shielded, "separation measured against the shielded player")

-- The pre-commit re-check sees the shielded player too.
local latest = __LATEST__
local seen = false
for _, record in ipairs(latest) do if record.Player == shielded then seen = true end end
expect(seen, true, "pre-commit re-check keeps the shielded player")

-- Departure-probe target lookup must not skip a candidate whose nearest is shielded.
local candidate = {Nearest = {Player = shielded}}
local target = __TARGET__
expect(target ~= nil, true, "probe target lookup accepts a shielded nearest player")

-- Targeting (chooseTarget/attackReach/updateModel) still ignores protected players.
local targetable = livingRecords(session)
expect(#targetable, 1, "plain livingRecords excludes the shielded player")
expect(targetable[1].Player, activator, "only the unprotected player is targetable")
expect(livingRecord(session, shielded), nil, "plain livingRecord excludes the shielded player")

print(string.format("Pool Slide spawn separation: %d checks passed (real controller slices)", checks))
'''


def main():
    binary = os.environ.get("LUAU_BIN") or shutil.which("luau")
    if not binary:
        raise SystemExit("Set LUAU_BIN or put luau on PATH; no tests executed.")
    controller = CONTROLLER.read_text(encoding="utf-8")
    spawn = section(controller, "local function spawnModel(session)", "local function requestSpawn(")
    source = HARNESS
    source = source.replace("__DISTANCE__", section(controller, "local function distance(a, b)", "local function stateFolder()"))
    source = source.replace("__LIVING__", section(controller, "local function livingRecord(session", "-- Diagnostics only."))
    source = source.replace("__CANDIDATES__", section(controller, "local function spawnPumpPosition(records)", "local function navigationTuning(model)"))
    source = source.replace("__RECORDS__", spawn_expression(spawn, r"local records = (livingRecords\([^)]*\))"))
    source = source.replace("__LATEST__", spawn_expression(spawn, r"local latest = (livingRecords\([^)]*\))"))
    source = source.replace("__TARGET__", spawn_expression(spawn, r"local target = (livingRecord\(session, candidate\.Nearest\.Player[^)]*\))"))
    with tempfile.TemporaryDirectory(prefix="pool-slide-spawn-separation-") as directory:
        path = Path(directory) / "spawn_separation.luau"
        path.write_text(source, encoding="utf-8")
        subprocess.run([binary, str(path)], check=True, timeout=20)


if __name__ == "__main__":
    main()
