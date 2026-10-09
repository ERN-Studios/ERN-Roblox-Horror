"""Exercise real Mall Manager steering and floor-clearance helpers in Luau.

The geometry stub supplies blocked/clear sweeps so steering deadlines can be
tested deterministically. This does not replace live Roblox geometry testing.
Set LUAU_BIN to an official Luau interpreter, or put luau on PATH.
"""

from pathlib import Path
import os
import shutil
import subprocess
import tempfile

ROOT = Path(__file__).resolve().parents[2]
CONTROLLER = ROOT / "ServerScriptService/Level 3 Systems/Level 3 Mall Manager AI Controller.ModuleScript.lua"


PRELUDE = r'''
local checks = 0
local function check(value, message)
    assert(value, message)
    checks += 1
end
local Vector3 = {}
local vectorMethods = {}
local vectorMeta = {}
function Vector3.new(x, y, z)
    return setmetatable({X=x, Y=y, Z=z}, vectorMeta)
end
function vectorMeta.__index(v, key)
    if key == "Magnitude" then return math.sqrt(v.X*v.X + v.Y*v.Y + v.Z*v.Z) end
    if key == "Unit" then return v / v.Magnitude end
    return vectorMethods[key]
end
function vectorMeta.__add(a, b) return Vector3.new(a.X+b.X, a.Y+b.Y, a.Z+b.Z) end
function vectorMeta.__sub(a, b) return Vector3.new(a.X-b.X, a.Y-b.Y, a.Z-b.Z) end
function vectorMeta.__unm(a) return Vector3.new(-a.X, -a.Y, -a.Z) end
function vectorMeta.__mul(a, b) return Vector3.new(a.X*b, a.Y*b, a.Z*b) end
function vectorMeta.__div(a, b) return Vector3.new(a.X/b, a.Y/b, a.Z/b) end
function vectorMethods:Dot(b) return self.X*b.X + self.Y*b.Y + self.Z*b.Z end
function vectorMethods:Cross(b)
    return Vector3.new(self.Y*b.Z-self.Z*b.Y, self.Z*b.X-self.X*b.Z, self.X*b.Y-self.Y*b.X)
end
Vector3.zero = Vector3.new(0, 0, 0)
Vector3.yAxis = Vector3.new(0, 1, 0)
local CFrame = {}
function CFrame.fromAxisAngle(axis, radians)
    assert(axis.Y == 1)
    return {VectorToWorldSpace=function(_, v)
        return Vector3.new(v.X*math.cos(radians)+v.Z*math.sin(radians), v.Y,
            -v.X*math.sin(radians)+v.Z*math.cos(radians))
    end}
end
local Tuning = {AvoidanceCommitSeconds=1.35, OverlapEscapeProbeDistance=3.5,
    ObstructionRecoveryAttempts=3}
local geometry = "clear"
local function navigationBlockersAt() return {} end
local function volumeClear(_, from, to)
    local offset = to-from
    if geometry == "clear" then return true end
    if geometry == "blocked" then return false end
    if geometry == "turn" then return math.abs(offset.Z) > .04 end
    if geometry == "opposite" then return offset.Z > .04 end
    error("unknown geometry")
end
local function resetOverlapEscapeState() error("fixture should never overlap") end
local function flat(p, y) return Vector3.new(p.X, y, p.Z) end
local function planarDistance(a, b) return (flat(a, 0)-flat(b, 0)).Magnitude end
local function session()
    return {Heading=Vector3.new(1, 0, 0), AvoidanceSign=0, AvoidanceUntil=0,
        OverlapEscapeAttempts=0, SpawnCycle=2, FloorY=0}
end
'''

TESTS = r'''
local desired = Vector3.new(1, 0, 0)
local origin = Vector3.zero
local s = session()
geometry = "turn"
local firstPosition, firstDirection = clearSteeringStep(s, origin, desired, .25, 10)
check(firstPosition ~= nil and math.abs(firstDirection.Z) > .04,
    "a blocked direct step still selects a clear avoidance direction")
check(s.AvoidanceSign ~= 0, "avoidance commits a side at the obstacle")
local firstDeadline = s.AvoidanceUntil
geometry = "clear"
local lastDirection
for frame=1,120 do
    local now = 10 + frame / 60
    local position, direction = clearSteeringStep(s, origin, desired, .25, now)
    check(position ~= nil, "opening the route cannot stop the Manager")
    lastDirection = direction
    if now < firstDeadline then
        check(s.AvoidanceUntil == firstDeadline,
            "repeated steering must not extend an already committed avoidance deadline")
    end
end
check(lastDirection:Dot(desired) > .999999 and s.AvoidanceSign == 0,
    "a clear route resumes straight movement within one avoidance window")

geometry = "clear"
local fresh = session()
local direct, directDirection = clearSteeringStep(fresh, origin, desired, .25, 20)
check(directDirection:Dot(desired) > .999999 and (direct-origin).Magnitude == .25,
    "unobstructed movement preserves its straight direction and full step distance")

geometry = "turn"
local persistent = session()
clearSteeringStep(persistent, origin, desired, .25, 30)
local oldDeadline = persistent.AvoidanceUntil
local continued = clearSteeringStep(persistent, origin, desired, .25, oldDeadline + .01)
check(continued ~= nil and persistent.AvoidanceUntil > oldDeadline,
    "a still blocked route can begin another bounded avoidance attempt")

geometry = "opposite"
local oldSign = persistent.AvoidanceSign
local changed, changedDirection = clearSteeringStep(persistent, origin, desired, .25, oldDeadline + .1)
check(changed ~= nil and changedDirection.Z > 0 and persistent.AvoidanceSign ~= oldSign,
    "a blocked committed side can switch to the only clear side")
check(math.abs(persistent.AvoidanceUntil-(oldDeadline+.1+Tuning.AvoidanceCommitSeconds)) < 1e-6,
    "a forced side change receives its own bounded window")

geometry = "blocked"
local refused, refusedDirection = clearSteeringStep(session(), origin, desired, .25, 40)
check(refused == nil and refusedDirection == nil,
    "fully blocked geometry is refused rather than crossed")
'''


FLOOR_PRELUDE = r'''
do
Tuning.AgentHeight = 10
Tuning.SweepRadius = 5.25
function CFrame.new(position) return {Position=position} end
local worldParts = {}
local lastCastCFrame, lastCastSize
local workspace = {}
local function overlaps(cframe, size, part)
    local delta = cframe.Position-part.Position
    return math.abs(delta.X) < (size.X+part.Size.X)*.5
        and math.abs(delta.Y) < (size.Y+part.Size.Y)*.5
        and math.abs(delta.Z) < (size.Z+part.Size.Z)*.5
end
function workspace:GetPartBoundsInBox(cframe, size)
    local found = {}
    for _, part in worldParts do
        if overlaps(cframe, size, part) then table.insert(found, part) end
    end
    return found
end
function workspace:Blockcast(cframe, size, direction)
    -- Fixtures move along X. For that case the swept AABB is exact.
    assert(direction.Y == 0 and direction.Z == 0)
    lastCastCFrame, lastCastSize = cframe, size
    local midpoint = CFrame.new(cframe.Position+direction*.5)
    local sweptSize = Vector3.new(size.X+math.abs(direction.X), size.Y, size.Z)
    for _, part in worldParts do
        if overlaps(midpoint, sweptSize, part) then return {Instance=part} end
    end
    return nil
end
local function navigationOverlapParams() return {} end
local function navigationParams() return {} end
local function publishPhysicalBlocker() end
local function part(y, height, width)
    return {Position=Vector3.new(0, y, 0), Size=Vector3.new(width or 10, height, 10)}
end
'''

FLOOR_TESTS = r'''
local ground = Vector3.new(0, 24, 0)
local start = Vector3.new(-20, 24, 0)
local finish = Vector3.new(20, 24, 0)
local s = session()
-- Same height and thickness as the seed-7331 Workspace.ElevatorSpawn blocker.
worldParts = {part(23.5, 1, 100), part(24.25, .5)}
check(#overlappingNavigationParts(s, ground) == 0,
    "the half-stud arrival support cannot make a player goal unreachable")
check(spawnVolumeFits(ground, {}), "spawn placement shares the shallow floor-support clearance")
check(physicalVolumeClear(s, start, finish),
    "the full movement sweep crosses the same shallow support as endpoint checks")
local bounds, size = clearanceBox(ground)
check(math.abs(bounds.Position.Y+size.Y*.5-33.6) < 1e-6,
    "step clearance preserves the existing upper body and low-ceiling boundary")
check(size.X == 10.5 and size.Z == 10.5,
    "the full horizontal body clearance is unchanged")
check(math.abs(lastCastSize.Y-size.Y) < 1e-6,
    "physical sweeps use the same body height as endpoint occupancy")

for _, obstacle in {part(24.35, .7), part(27, .48), part(29, 10)} do
    worldParts = {obstacle}
    check(#overlappingNavigationParts(s, ground) > 0 and not spawnVolumeFits(ground, {}),
        "raised obstacles, tabletops and walls still block occupancy and spawn")
    check(not physicalVolumeClear(s, start, finish),
        "a raised obstacle between clear endpoints still blocks the full sweep")
end
worldParts = {part(33.55, .3)}
check(not physicalVolumeClear(s, ground, ground),
    "a ceiling intruding into the previous body top still blocks movement")
worldParts = {part(33.85, .3)}
check(physicalVolumeClear(s, ground, ground),
    "an overhead surface clear of the previous body top remains clear")
end
print("Level 3 navigation: " .. checks .. " checks passed (offline Luau; live geometry not exercised)")
'''


def main():
    binary = os.environ.get("LUAU_BIN") or shutil.which("luau")
    if not binary:
        raise SystemExit("Set LUAU_BIN or install luau; no tests were executed.")
    controller = CONTROLLER.read_text(encoding="utf-8")
    start = controller.index("local AVOIDANCE_MAGNITUDES")
    end = controller.index("-- LEVEL3_MANAGER_PROGRESS_TRACKER_20260827", start)
    def section(start, end):
        begin = controller.index(start)
        return controller[begin:controller.index(end, begin)]

    source = "\n".join([
        PRELUDE, controller[start:end], TESTS, FLOOR_PRELUDE,
        section("local function clearanceBox", "-- LEVEL3_MANAGER_SHARED_FURNITURE_CLEARANCE"),
        section("local function overlappingNavigationParts", "local function publishPhysicalBlocker"),
        section("local function physicalVolumeClear", "local function navigationBlockersAt"),
        section("local function spawnVolumeFits", "local function spawnVisibilityCount"),
        FLOOR_TESTS,
    ])
    with tempfile.TemporaryDirectory(prefix="level3-steering-") as directory:
        fixture = Path(directory) / "steering_test.luau"
        fixture.write_text(source, encoding="utf-8")
        subprocess.run([binary, str(fixture)], check=True, timeout=20)


if __name__ == "__main__":
    main()
