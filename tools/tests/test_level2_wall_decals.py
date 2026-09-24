"""Level 2 wall-depth decal placement (Trello DDqjXkyU).

WALL_DEPTH_DECALS_20260924. Runs the REAL WALL_DECALS table and
placeWallDecals sliced out of the Level 2 World Builder against small fake
layouts and a minimal Vector3/CFrame/Instance stand-in. Checks: only plain
"Hall" rooms (never pump, kids, slide, arrival, exit, den or the grand hall),
the visitor trace in the quietest hall (a dead end first), one decal per hall, never across a
doorway, on the room side of the wall facing in, non-colliding, and the same
seed places the same way. What only Studio shows: how they read in the dark.
Set LUAU_BIN, or put luau on PATH.
"""

import os
from pathlib import Path
import shutil
import subprocess
import tempfile

ROOT = Path(__file__).resolve().parents[2]
BUILDER = (ROOT / "ServerScriptService/Level 2 Systems/Level 2 World Builder.ModuleScript.lua").read_text(encoding="utf-8")


def section(source, start, stop):
    begin = source.index(start)
    return source[begin:source.index(stop, begin)]


PRELUDE = r'''
local checks = 0
local function check(v, m) assert(v, m); checks += 1 end
local V = {}
V.__index = V
local function vec(x, y, z) return setmetatable({X = x, Y = y, Z = z}, V) end
V.__add = function(a, b) return vec(a.X + b.X, a.Y + b.Y, a.Z + b.Z) end
V.__sub = function(a, b) return vec(a.X - b.X, a.Y - b.Y, a.Z - b.Z) end
V.__mul = function(a, k) return vec(a.X * k, a.Y * k, a.Z * k) end
V.__unm = function(a) return vec(-a.X, -a.Y, -a.Z) end
local Vector3 = {new = vec, xAxis = vec(1, 0, 0), zAxis = vec(0, 0, 1)}
local Vector2 = {new = function(x, y) return {X = x, Y = y} end}
local CFrame = {lookAt = function(at, target) return {Position = at, Look = target - at} end}
local Enum = {NormalId = {Front = "Front"}}
local function Random_new(seed)
    local state = seed % 2147483647
    if state <= 0 then state += 2147483646 end
    return {NextInteger = function(_, lo, hi)
        state = (state * 48271) % 2147483647
        return lo + state % (hi - lo + 1)
    end}
end
local Random = {new = Random_new}
local made = {}
local Instance = {new = function(class)
    local obj = {ClassName = class, attrs = {}, children = {}}
    function obj:SetAttribute(k, v) self.attrs[k] = v end
    setmetatable(obj, {__newindex = function(t, k, v)
        if k == "Parent" and v then table.insert(v.children, t) end
        rawset(t, k, v)
    end})
    table.insert(made, obj)
    return obj
end}
local Configuration = {WallThickness = 3.5, DoorWidth = 30}
'''

TESTS = r'''
local function hall(index, role, minX, minZ, size, extra)
    local h = {Index = index, Id = ("Level 2 Hall %02d"):format(index), Role = role,
        MinX = minX, MaxX = minX + size, MinZ = minZ, MaxZ = minZ + size}
    for k, v in pairs(extra or {}) do h[k] = v end
    return h
end
local function doors(w, e, n, s) return {West = w or {}, East = e or {}, North = n or {}, South = s or {}} end
local halls = {
    hall(1, "Arrival", 0, 0, 120), hall(2, "Pump Station", 200, 0, 120), hall(3, "Kids Area", 400, 0, 120),
    hall(4, "Slide Hall", 0, 200, 120), hall(5, "Entity Den", 200, 200, 120), hall(6, "Hall", 400, 200, 120, {IsGrand = true}),
    hall(7, "Hall", 0, 400, 120), hall(8, "Hall", 200, 400, 120), hall(9, "Hall", 400, 400, 120),
}
local doorsBy = {}
for _, h in ipairs(halls) do doorsBy[h.Index] = doors({h.MinZ + 60}, {h.MinZ + 60}, nil, nil) end
doorsBy[9] = doors({409 + 50}) -- hall 9 is a dead end: one doorway only
local function run(seed)
    table.clear(made)
    local world = {children = {}}
    placeWallDecals(world, {Seed = seed, Halls = halls}, doorsBy)
    local folder = world.children[1]
    return folder, folder.children
end
local folder, planes = run(12345)
check(folder.attrs.Level2_WallDecalCount == 3, "three accents: two murals and one trace, got " .. tostring(folder.attrs.Level2_WallDecalCount))
local byName, hallsUsed = {}, {}
for _, plane in ipairs(planes) do
    byName[plane.Name] = (byName[plane.Name] or 0) + 1
    local id = plane.attrs.Level2_HallId
    check(not hallsUsed[id], "one decal per hall")
    hallsUsed[id] = true
    check(id == "Level 2 Hall 07" or id == "Level 2 Hall 08" or id == "Level 2 Hall 09",
        "only plain non-grand halls, got " .. tostring(id))
    check(plane.CanCollide == false and plane.CanQuery == false and plane.CanTouch == false
        and plane.CastShadow == false and plane.Transparency == 1, "decal plane is inert and invisible")
    local decal = plane.children[1]
    check(decal and decal.ClassName == "Decal" and decal.Face == "Front", "decal on the room-facing Front")
    -- on the inner face, facing into the room, never across a doorway
    local h
    for _, x in ipairs(halls) do if x.Id == id then h = x end end
    local p, look = plane.CFrame.Position, plane.CFrame.Look
    local cx, cz = (h.MinX + h.MaxX) / 2, (h.MinZ + h.MaxZ) / 2
    check((cx - p.X) * look.X + (cz - p.Z) * look.Z > 0, "faces into its hall")
    local half = plane.Size.X / 2
    local along = look.X ~= 0 and p.Z or p.X
    local list = look.X > 0 and doorsBy[h.Index].West or look.X < 0 and doorsBy[h.Index].East
        or look.Z > 0 and doorsBy[h.Index].North or doorsBy[h.Index].South
    for _, centre in ipairs(list) do
        check(along + half <= centre - 15 or along - half >= centre + 15, "clear of every doorway")
    end
end
check(byName["Level 2 Wall Decal Maintenance History"] == 2, "two murals")
check(byName["Level 2 Wall Decal Visitor Traces"] == 1, "one visitor trace")
for _, plane in ipairs(planes) do
    if plane.Name == "Level 2 Wall Decal Visitor Traces" then
        check(plane.attrs.Level2_HallId == "Level 2 Hall 09", "the trace sits in the dead end")
        check(plane.Size.X == 8 and plane.Size.Y == 4, "the trace is small")
    end
end
-- determinism
local _, again = run(12345)
for i, plane in ipairs(planes) do
    check(again[i].attrs.Level2_HallId == plane.attrs.Level2_HallId and again[i].Name == plane.Name,
        "same seed, same placement")
end
-- the trace goes to whichever eligible hall has the fewest doorways
doorsBy[9] = doors({459}, {459})
doorsBy[8] = doors({459}, {459}, {259})
doorsBy[7] = doors({459})
local _, noDead = run(777)
local traces = 0
for _, plane in ipairs(noDead) do
    if plane.Name:find("Visitor") then
        traces += 1
        check(plane.attrs.Level2_HallId == "Level 2 Hall 07", "the quietest hall takes the trace")
    end
end
check(traces == 1, "exactly one trace")
print(("Level 2 wall decals: %d checks passed (real placeWallDecals)"):format(checks))
'''


def main():
    binary = os.environ.get("LUAU_BIN") or shutil.which("luau")
    if not binary:
        raise SystemExit("Set LUAU_BIN or install luau; no tests were executed.")
    block = section(BUILDER, "local WALL_DECALS = {", "-- ── walls ─")
    source = PRELUDE + block + TESTS
    with tempfile.TemporaryDirectory(prefix="l2-wall-decals-") as directory:
        path = Path(directory) / "wall_decals.luau"
        path.write_text(source, encoding="utf-8")
        subprocess.run([binary, str(path)], check=True, timeout=60)


if __name__ == "__main__":
    main()
