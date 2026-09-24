"""Compare Level 3's structural eye-level sightlines with the pre-maze map.

The ray calculation follows the real builder's centered door openings and
solid room/corridor wall geometry. Furniture can only shorten these clear
structural rays; the separate Studio probe measures the fully built world.
"""

import os
from pathlib import Path
import shutil
import subprocess
import tempfile

from test_level3_square_layout import HOST, generator_factory


ROOT = Path(__file__).resolve().parents[2]
SYSTEM = Path("ServerScriptService/Level 3 Systems")
BASELINE_REV = "b607011"

TEST = r'''
local baseline = baselineGenerator()
local current = currentGenerator()
local seeds = {101, 7331, 65537, 1900813}
for index = 1, 36 do table.insert(seeds, 104729 * index + 1) end

-- The builder cuts one centered opening per linked room side and centers every
-- 14-stud corridor on that side. At eye level a straight ray travels from the
-- first room's outer wall to the last room's outer wall through those openings.
local opposite = {East="West", West="East", North="South", South="North"}
local function structuralRays(layout)
    local ports = {}
    for _, room in ipairs(layout.Rooms) do ports[room.Id] = {} end
    for _, link in ipairs(layout.Links) do
        if link.Door ~= "HiddenExit" then
            local a,b = layout.RoomById[link.A],layout.RoomById[link.B]
            local side
            if a.Z == b.Z then side = if a.X < b.X then "East" else "West"
            else side = if a.Z < b.Z then "South" else "North" end
            ports[a.Id][side] = b.Id
            ports[b.Id][opposite[side]] = a.Id
        end
    end
    local longest, longestLinks, rayCount = 0, 0, 0
    for _, room in ipairs(layout.Rooms) do
        for _, side in ipairs({"East", "South"}) do
            if ports[room.Id][side] and not ports[room.Id][opposite[side]] then
                local last, links = room, 0
                while ports[last.Id][side] do
                    last = layout.RoomById[ports[last.Id][side]]
                    links += 1
                end
                local distance = if side == "East"
                    then (last.X + last.W / 2) - (room.X - room.W / 2)
                    else (last.Z + last.D / 2) - (room.Z - room.D / 2)
                longest = math.max(longest, distance)
                longestLinks = math.max(longestLinks, links)
                rayCount += 1
            end
        end
    end
    return longest, longestLinks, rayCount
end

local records = {}
local maxBefore, maxAfter, maxLinks, improved = 0, 0, 0, 0
local baselineArea, currentArea = 0, 0
for _, seed in ipairs(seeds) do
    local old, new = baseline.Generate(seed), current.Generate(seed)
    local valid, issue = current.Validate(new)
    check(valid, "new layout validates: "..tostring(issue))
    check(new.Attempt == 1 and not new.UsedFallbackSeed and not new.StraightRunRelaxed,
        "ordinary seeds require no retry or relaxed sightline rule")
    check(#new.Rooms == 26 and #new.Links == 31 and new.CyclomaticLoops == 6,
        "five CDs and six cycles keep the original graph budget")
    check(#new.ModuleRooms == 5 and new.HideSpotCount == 24, "objectives and hiding")
    local before, beforeLinks = structuralRays(old)
    local after, afterLinks, rayCount = structuralRays(new)
    local oldArea, newArea = 0, 0
    for _, room in ipairs(old.Rooms) do
        if room.SectionIndex >= 1 and room.SectionIndex <= 3 then oldArea += room.W * room.D end
    end
    for _, room in ipairs(new.Rooms) do
        if room.SectionIndex >= 1 and room.SectionIndex <= 3 then newArea += room.W * room.D end
    end
    baselineArea += oldArea
    currentArea += newArea
    check(afterLinks <= 3 and new.MaximumStraightRun == afterLinks,
        "no long collinear chain through the core")
    if after < before then improved += 1 end
    if #records < 4 then
        check(after < before, "each named acceptance seed shortens its longest ray")
    end
    local oldHall, oldExit = old.RoomById.SignalHall, old.RoomById.Exit
    local hall, exit = new.RoomById.SignalHall, new.RoomById.Exit
    check(exit.X - hall.X - (hall.W + exit.W) / 2 == 560
        and oldExit.X - oldHall.X - (oldHall.W + oldExit.W) / 2 == 560,
        "scripted finale corridor stays 560 studs")
    maxBefore, maxAfter = math.max(maxBefore, before), math.max(maxAfter, after)
    maxLinks = math.max(maxLinks, afterLinks)
    if #records < 4 then
        table.insert(records, {seed=seed, before=before, after=after,
            beforeLinks=beforeLinks, afterLinks=afterLinks, rays=rayCount,
            oldCoreWidth=old.CoreBounds.Width, oldCoreDepth=old.CoreBounds.Depth,
            coreWidth=new.CoreBounds.Width, coreDepth=new.CoreBounds.Depth,
            roomAreaRatio=newArea/oldArea})
    end
end
check(improved >= 36, "at least 90 percent of sampled seeds improve")
check(maxAfter <= 450 and maxAfter < maxBefore * .6,
    "new core removes the former 500-814 stud long views")
check(currentArea / baselineArea > 1.10 and currentArea / baselineArea < 1.25,
    "room floor area grows modestly without expanding the room count")
print("RESULT "..encode({checks=checks, seeds=#seeds, records=records,
    maxBefore=maxBefore, maxAfter=maxAfter, maxLinks=maxLinks, improved=improved,
    roomAreaRatio=currentArea/baselineArea}))
'''


def main():
    binary = os.environ.get("LUAU_BIN") or shutil.which("luau")
    if not binary:
        raise SystemExit("Set LUAU_BIN to the Luau executable")
    with tempfile.TemporaryDirectory(prefix="level3-maze-rays-") as directory:
        temporary = Path(directory)
        baseline_system = temporary / SYSTEM
        baseline_system.mkdir(parents=True)
        for name in ("Level 3 Configuration.ModuleScript.lua",
                     "Level 3 Layout Generator.ModuleScript.lua"):
            relative = SYSTEM / name
            source = subprocess.check_output(
                ["git", "show", f"{BASELINE_REV}:{relative.as_posix()}"],
                cwd=ROOT,
            )
            (baseline_system / name).write_bytes(source)
        fixture = temporary / "sightlines.luau"
        fixture.write_text(HOST + generator_factory(temporary, "baselineGenerator")
                           + generator_factory(ROOT, "currentGenerator") + TEST,
                           encoding="utf-8")
        result = subprocess.run([binary, str(fixture)], text=True, capture_output=True)
        if result.returncode:
            raise SystemExit(result.stdout + result.stderr)
        print(next(line for line in result.stdout.splitlines() if line.startswith("RESULT ")))


if __name__ == "__main__":
    main()
