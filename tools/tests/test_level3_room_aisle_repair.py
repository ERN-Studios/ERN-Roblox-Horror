"""Run the real Mall Manager buildRoomAislePath in Luau on the frozen-finale room.

Geometry is the live Studio readout of L3_S2_R05 on seed 1428587057 (24 Sep 2026):
walls, door gaps, four structural columns, two table colliders and the two
inflated furniture envelopes that leave the Manager's centre a 1.7-stud aisle.
volumeFits/volumeClear are modelled as the same contract (5.25 body square
against collidable parts, centre outside every envelope), sampled every quarter
stud. The search, string-pull and doorway logic are the controller's own source.
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
local vectorMeta = {}
function Vector3.new(x, y, z) return setmetatable({X=x, Y=y, Z=z}, vectorMeta) end
function vectorMeta.__index(v, key)
    if key == "Magnitude" then return math.sqrt(v.X*v.X + v.Y*v.Y + v.Z*v.Z) end
end
function vectorMeta.__add(a, b) return Vector3.new(a.X+b.X, a.Y+b.Y, a.Z+b.Z) end
function vectorMeta.__sub(a, b) return Vector3.new(a.X-b.X, a.Y-b.Y, a.Z-b.Z) end
function vectorMeta.__mul(a, b) return Vector3.new(a.X*b, a.Y*b, a.Z*b) end
local Configuration = {WallThickness=1.5}
local Tuning = {SweepRadius=5.25}
local function flat(p, y) return Vector3.new(p.X, y, p.Z) end
local rooms = {
    L3_S2_R05={Id="L3_S2_R05", X=6306, Z=379.5, W=65, D=59},
    L3_S3_R01={Id="L3_S3_R01", X=6306, Z=481.5, W=73, D=57},
}
local function roomDefinition(id) return rooms[id] end
local function roomCenter(id, y) local r = rooms[id] return Vector3.new(r.X, y, r.Z) end
local function nearestRoomId(p)
    local best, bestD = nil, math.huge
    for id, r in pairs(rooms) do
        local dx = math.max(math.abs(p.X - r.X) - r.W * .5, 0)
        local dz = math.max(math.abs(p.Z - r.Z) - r.D * .5, 0)
        local d = math.sqrt(dx*dx + dz*dz)
        if d < bestD then best, bestD = id, d end
    end
    return best
end
local function layoutLinks() return {{A="L3_S2_R05", B="L3_S3_R01", Door="Open"}} end
local function insideFinalHall() return false end
local function navigationOverlapParams() return {} end
-- Collidable parts as axis-aligned rectangles {minX, maxX, minZ, maxZ}.
local solids = {
    {6272.75, 6339.25, 349.25, 350.75},   -- North Wall
    {6272.75, 6274.25, 349.25, 409.75},   -- West Wall
    {6337.75, 6339.25, 349.95, 372.55},   -- East Wall A (door z 372.55..386.45)
    {6337.75, 6339.25, 386.45, 409.05},   -- East Wall B
    {6273.45, 6299.05, 408.25, 409.75},   -- South Wall A (door x 6299.05..6312.95)
    {6312.95, 6338.55, 408.25, 409.75},   -- South Wall B
    {6282.85, 6284.95, 359.57, 361.67}, {6282.85, 6284.95, 397.33, 399.43}, -- columns
    {6327.05, 6329.15, 359.57, 361.67}, {6327.05, 6329.15, 397.33, 399.43},
    {6288.8, 6299.8, 367.395, 371.545},   -- table 1 collider
    {6316.925, 6321.075, 384.25, 395.25}, -- table 2 collider (92 deg)
    {6297.5, 6299.0, 409.75, 453.0}, {6313.0, 6314.5, 409.75, 453.0}, -- gateway corridor walls
}
local envelopes = { -- centre keep-outs, already shrunk by the 0.25 seam tolerance
    {6282.7, 6305.9, 358.07, 380.87},
    {6307.6, 6330.4, 378.15, 401.35},
}
local R = 5.25
local function pointFree(p)
    for _, e in ipairs(envelopes) do
        if p.X > e[1] and p.X < e[2] and p.Z > e[3] and p.Z < e[4] then return false end
    end
    for _, s in ipairs(solids) do
        if p.X > s[1] - R and p.X < s[2] + R and p.Z > s[3] - R and p.Z < s[4] + R then return false end
    end
    return true
end
local fitsCalls = 0
local volumeFits = function(_, p) fitsCalls += 1 return pointFree(p) end
local volumeClear = function(_, a, b)
    local d = b - a
    local n = math.max(1, math.ceil(d.Magnitude / .25))
    for k = 0, n do
        if not pointFree(a + d * (k / n)) then return false end
    end
    return true
end
'''

TESTS = r'''
local doorway = Vector3.new(6337, 24, 379.5)     -- where the finale Manager froze after the reach fix
local gateway = Vector3.new(6306, 24, 481.5)     -- strategic next point: the S3 gateway room
local session = {Root={Position=Vector3.new(doorway.X, 28.1, doorway.Z)}, FloorY=24, FinalHallChase=true}

check(pointFree(doorway), "fixture: the frozen doorway pose itself fits")
check(not volumeClear(nil, doorway, Vector3.new(6306, 24, 402.5)), "fixture: no straight leg from the doorway to the south door")

local path = buildRoomAislePath(session, gateway)
check(path ~= nil and #path >= 2, "the aisle repair finds a route out of the frozen doorway")
local from = doorway
local crossedAisle = false
for i, waypoint in ipairs(path) do
    local p = waypoint.Position
    check(volumeClear(nil, from, p), "leg " .. i .. " passes the full-volume sweep")
    if math.abs(from.Z - p.Z) > 1 then
        local t = (379.5 - from.Z) / (p.Z - from.Z)
        if t >= 0 and t <= 1 then
            local x = from.X + (p.X - from.X) * t
            if x > 6305.9 and x < 6307.6 then crossedAisle = true end
        end
    end
    from = p
end
check(crossedAisle, "the route crosses z 379.5 inside the 1.7-stud centre aisle (x 6305.9..6307.6)")
local doorPoint, into = path[#path - 1].Position, path[#path].Position
check(math.abs(doorPoint.X - 6306) < .01 and math.abs(doorPoint.Z - 402.5) < .01, "it ends on the south door axis at the inset point")
check(math.abs(into.Z - 459.5) < .01 and math.abs(into.X - 6306) < .01, "and continues to the gateway room's inset point")
check(fitsCalls <= 65 * 59, "the search evaluates each one-stud cell at most once")

-- The two live freeze poses (round 2 and round 3, before any fix) also get out.
for _, start in ipairs({Vector3.new(6328.75, 24, 375.40), Vector3.new(6323.1, 24, 376.5)}) do
    session.AisleRepairRetryAt = 0
    session.Root.Position = Vector3.new(start.X, 28.1, start.Z)
    local route = buildRoomAislePath(session, gateway)
    check(route ~= nil, string.format("a route exists from the live freeze pose %.2f,%.2f", start.X, start.Z))
    local p = start
    for i, waypoint in ipairs(route) do
        check(volumeClear(nil, p, waypoint.Position), "every leg from the freeze pose passes the sweep")
        p = waypoint.Position
    end
end
session.Root.Position = Vector3.new(doorway.X, 28.1, doorway.Z)

-- A route that cannot leave through the doorway is refused, like the perimeter repair.
session.AisleRepairRetryAt = 0
table.insert(solids, {6300, 6312, 429, 431}) -- a prop across the gateway corridor
check(buildRoomAislePath(session, gateway) == nil, "a blocked doorway leg yields no route instead of a dead-end install")
table.remove(solids)
session.AisleRepairRetryAt = 0
check(buildRoomAislePath(session, gateway) ~= nil, "the route returns once the corridor is clear")

-- Rate limit: a second search inside the same second is refused (no per-frame BFS).
check(buildRoomAislePath(session, gateway) == nil, "a repeat search within one second is skipped")

check((session.AisleRepairFailures or 0) == 0, "a successful search leaves no failure streak")

-- A truly closed room returns nil instead of looping, and repeated failures back off.
session.AisleRepairRetryAt = 0
envelopes[1][2] = 6309.5 -- widen table 1's envelope across the aisle
check(buildRoomAislePath(session, gateway) == nil, "a sealed room yields no route")
check(session.AisleRepairFailures == 1 and session.AisleRepairRetryAt - os.clock() <= 1.01, "first failure waits one second")
session.AisleRepairRetryAt = 0
check(buildRoomAislePath(session, gateway) == nil, "still sealed")
check(session.AisleRepairFailures == 2 and session.AisleRepairRetryAt - os.clock() > 1.5, "a second failure backs off to two seconds")
envelopes[1][2] = 6305.9
session.AisleRepairRetryAt = 0
check(buildRoomAislePath(session, gateway) ~= nil and session.AisleRepairFailures == 0, "a later success clears the streak")

-- Inside the final hall the repair stands down like the perimeter rings.
session.AisleRepairRetryAt = 0
insideFinalHall = function() return true end
check(buildRoomAislePath(session, gateway) == nil, "no aisle search inside the final hall")

print("Level 3 room aisle repair: " .. checks .. " checks passed (offline Luau; live geometry not exercised)")
'''


def main():
    binary = os.environ.get("LUAU_BIN") or shutil.which("luau")
    if not binary:
        raise SystemExit("Set LUAU_BIN or install luau; no tests were executed.")
    controller = CONTROLLER.read_text(encoding="utf-8")
    begin = controller.index("local function buildRoomAislePath(")
    end = controller.index("local function installRoomPerimeterPath(", begin)
    # insideFinalHall is reassigned by one case, so bind it as a mutable local.
    prelude = PRELUDE.replace("local function insideFinalHall() return false end",
                              "local insideFinalHall = function() return false end")
    source = "\n".join([prelude, controller[begin:end], TESTS])
    with tempfile.TemporaryDirectory(prefix="level3-aisle-") as directory:
        fixture = Path(directory) / "aisle_test.luau"
        fixture.write_text(source, encoding="utf-8")
        subprocess.run([binary, str(fixture)], check=True, timeout=30)


if __name__ == "__main__":
    main()
