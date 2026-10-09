"""Run the REAL Level 3 layout generator, and the reader's own CD selection.

Two halves, one Luau process:

  * the actual `Level 3 Layout Generator` over 240 seeds -- exactly five CD
    rooms, one of them ALWAYS the room Arrival opens into, all five distinct,
    separated, reachable from Arrival over the generator's own graph, and the
    same layout twice for the same seed;
  * the pure `chooseCDTarget` / `pickableCDs` pair lifted verbatim out of
    `Level 3 Reader Client` between its L3_CD_READER_TARGET markers -- nearest
    pickable disc wins, CARRIED/INSERTED discs are invisible to it, and the
    room indicator answers on room id rather than distance.

The offline host uses a deterministic Park-Miller PRNG, NOT Roblox Random, so
a Studio sweep with the engine Random is still required. No game source,
Studio state, DataStore or live player is touched.

Needs a Luau CLI: set LUAU_BIN (e.g. the 0.737 build in %TEMP%) or put `luau`
on PATH.
"""

import json
import os
import re
from pathlib import Path
import shutil
import subprocess
import tempfile

ROOT = Path(__file__).resolve().parents[2]
SYSTEM = Path("ServerScriptService/Level 3 Systems")
READER = Path("StarterPlayer/StarterPlayerScripts/Level 3 Reader Client.LocalScript.lua")
BUILDER = SYSTEM / "Level 3 World Builder.ModuleScript.lua"

HOST = r'''
local Vector3 = {new=function(x,y,z) return {X=x,Y=y,Z=z} end}
local Color3 = {fromRGB=function(r,g,b) return {R=r/255,G=g/255,B=b/255} end}
local DateTime = {now=function() return {UnixTimestampMillis=1} end}
local Random = {}
function Random.new(seed)
    local state = math.floor(math.abs(seed)) % 2147483646 + 1
    local function nextUnit()
        state = (state * 16807) % 2147483647
        return (state - 1) / 2147483646
    end
    return {
        NextInteger=function(_, low, high) return low + math.floor(nextUnit() * (high-low+1)) end,
        NextNumber=function(_, low, high) return (low or 0) + nextUnit()*((high or 1)-(low or 0)) end,
    }
end
local checks = 0
local function check(value, message)
    checks += 1
    assert(value, message)
end
local function encode(value)
    if type(value) == "number" or type(value) == "boolean" then return tostring(value) end
    if type(value) == "string" then return string.format("%q", value) end
    assert(type(value) == "table", "fixture JSON type")
    local result = {}
    if #value > 0 then
        for _, item in ipairs(value) do table.insert(result, encode(item)) end
        return "[" .. table.concat(result, ",") .. "]"
    end
    for key, item in pairs(value) do table.insert(result, encode(tostring(key)) .. ":" .. encode(item)) end
    table.sort(result)
    return "{" .. table.concat(result, ",") .. "}"
end
'''

GENERATOR_TESTS = r'''
local LayoutGenerator, Configuration = currentGenerator()
local GOAL = Configuration.ModuleGoal
local SEPARATION = LayoutGenerator.Tuning.MinimumModuleSeparation

local decorPool = {}
for _, decor in ipairs(LayoutGenerator.DistrictDefinitions[1].DecorPool) do
    table.insert(decorPool, decor)
end
local entryDecors = {}
for _, decor in ipairs(decorPool) do entryDecors[decor] = true end

local seeds = {1, 2, 101, 7331, 65537, 1900813}
for index = 1, 234 do table.insert(seeds, (index * 2654435761) % 2147483645 + 1) end

local firstRooms, moduleSets, hashes = {}, {}, {}
local maxAttempt, fallbacks = 0, 0
for _, seed in ipairs(seeds) do
    local layout = LayoutGenerator.Generate(seed)
    local valid, problem = LayoutGenerator.Validate(layout)
    check(valid, "the real validator accepts the generated plan: " .. tostring(problem))
    maxAttempt = math.max(maxAttempt, layout.Attempt)
    if layout.UsedFallbackSeed then fallbacks += 1 end

    -- THE ENTRY RELATION, taken from the built graph rather than from a label.
    -- Arrival has exactly one link, the east-facing Entry gateway, so its only
    -- neighbour IS the room a player walks into after the arrival elevator.
    local roles = layout.Roles
    local arrival = layout.RoomById.Arrival
    local neighbours = layout.Adjacency.Arrival
    check(#neighbours == 1 and neighbours[1] == roles.EntryDistrictRoomId,
        "Arrival must open into exactly one room, the entry district room")
    local entryLink = layout.GatewayLinks[1]
    check(entryLink.GatewayKind == "Entry" and entryLink.A == "Arrival"
        and entryLink.B == roles.EntryDistrictRoomId,
        "the first gateway must be Arrival -> entry district room")
    check(roles.FirstCDRoomId == roles.EntryDistrictRoomId,
        "the first CD room must be that same entry room")

    local first = layout.RoomById[roles.FirstCDRoomId]
    check(first ~= nil and first.Module == true, "the entry room must carry a CD")
    check(first.SectionIndex == 1 and first.GridColumn == 1,
        "the entry room is district 1, column 1")
    check(first.X > arrival.X and math.abs(first.Z - arrival.Z) < .001,
        "the entry room sits straight east of Arrival")
    -- A CD is socketed onto the room's FIRST table layout, so the room has to
    -- be a furnished district room with an archetype that authors one.
    check(first.HideSpotCount == 1 and entryDecors[first.Decor] == true,
        "the entry room must be a furnished district room with a table archetype")

    -- Exactly five, no two in the same room, all separated, all reachable.
    local moduleIds, moduleCount = {}, 0
    for _, room in ipairs(layout.Rooms) do
        if room.Module == true then
            check(not moduleIds[room.Id], "two CDs in one room")
            moduleIds[room.Id] = true
            moduleCount += 1
        end
    end
    check(moduleCount == GOAL and #layout.ModuleRooms == GOAL, "exactly five CD rooms")
    check(moduleIds[roles.FirstCDRoomId] == true, "the first CD is one of the five")
    for a = 1, GOAL - 1 do
        for b = a + 1, GOAL do
            local one, other = layout.ModuleRooms[a], layout.ModuleRooms[b]
            local dx, dz = one.X - other.X, one.Z - other.Z
            check(dx * dx + dz * dz >= SEPARATION * SEPARATION - .001,
                "every pair of CD rooms keeps the separation rule")
        end
    end
    local reached, queue, cursor = {Arrival = true}, {"Arrival"}, 1
    while cursor <= #queue do
        local roomId = queue[cursor]
        cursor += 1
        for _, other in ipairs(layout.Adjacency[roomId]) do
            if not reached[other] then
                reached[other] = true
                table.insert(queue, other)
            end
        end
    end
    for _, room in ipairs(layout.ModuleRooms) do
        check(reached[room.Id] == true, "every CD room is reachable from Arrival")
    end

    -- Determinism: the same seed repeats the same plan AND the same five rooms.
    local repeated = LayoutGenerator.Generate(seed)
    check(repeated.LayoutHash == layout.LayoutHash, "same seed must repeat exactly")
    local signature = table.concat(layout.Roles.ModuleRoomIds, ",")
    check(table.concat(repeated.Roles.ModuleRoomIds, ",") == signature,
        "same seed must repeat the same five CD rooms")
    check(repeated.Roles.FirstCDRoomId == roles.FirstCDRoomId,
        "same seed must repeat the same first CD room")

    firstRooms[roles.FirstCDRoomId] = (firstRooms[roles.FirstCDRoomId] or 0) + 1
    moduleSets[signature] = true
    hashes[layout.LayoutHash] = true
end

local function countMap(map)
    local total = 0
    for _ in pairs(map) do total += 1 end
    return total
end
-- The generator SEEDS the entry room's CD; the validator only enforces it. If
-- the seeding is lost, Generate falls back to retrying whole seeds until one
-- happens to satisfy the rule -- every layout still passes, and the map is a
-- different one than the seed asked for. This is the check that notices.
check(maxAttempt == 1 and fallbacks == 0,
    "every seed must still produce its own layout on the first attempt")
local distinctSets, distinctHashes = countMap(moduleSets), countMap(hashes)
check(distinctHashes == #seeds, "every seed keeps a distinct layout")
check(distinctSets >= #seeds * .5, "the other four CDs must still vary across seeds")
check(countMap(firstRooms) >= 2, "the entry room itself still moves with the seed")

-- The guarantee is a VALIDATOR rule, not only a generator habit.
local function rejects(mutate, label)
    local mutated = LayoutGenerator.Generate(101)
    mutate(mutated)
    local valid, problem = LayoutGenerator.Validate(mutated)
    check(not valid and string.find(problem, "first CD", 1, true) ~= nil,
        label .. ": " .. tostring(problem))
end
rejects(function(layout)
    for _, room in ipairs(layout.ModuleRooms) do
        if room.Id ~= layout.Roles.FirstCDRoomId then
            layout.Roles.EntryDistrictRoomId = room.Id
            return
        end
    end
end, "a CD in some other room cannot stand in for the entry room's")
rejects(function(layout)
    for _, room in ipairs(layout.Rooms) do
        if room.SectionIndex == 1 and room.Module ~= true then
            layout.Roles.EntryDistrictRoomId = room.Id
            layout.Roles.FirstCDRoomId = room.Id
            return
        end
    end
end, "an entry room without a CD must be rejected")
rejects(function(layout)
    layout.Roles.EntryDistrictRoomId = "Arrival"
    layout.Roles.FirstCDRoomId = "Arrival"
end, "Arrival itself is not a furnished room and cannot hold the first CD")
'''

READER_TESTS = r'''
local attributes = {}
local function stateAttribute(name)
    return attributes[name]
end
local function typeof(value)
    if type(value) == "table" and value.__vector3 then return "Vector3" end
    return type(value)
end
local function spot(x, z) return {__vector3 = true, X = x, Y = 0, Z = z} end
__READER__

-- Only WORLD and DROPPED discs with a published position are pickable.
attributes["Level3_CD1State"] = "WORLD"
attributes["Level3_CD1Position"] = spot(0, 0)
attributes["Level3_CD1Room"] = "L3_S1_R01"
attributes["Level3_CD2State"] = "CARRIED"
attributes["Level3_CD2Position"] = nil
attributes["Level3_CD2Room"] = ""
attributes["Level3_CD3State"] = "DROPPED"
attributes["Level3_CD3Position"] = spot(10, 0)
attributes["Level3_CD3Room"] = "L3_S2_R04"
attributes["Level3_CD4State"] = "INSERTED"
attributes["Level3_CD4Position"] = nil
attributes["Level3_CD5State"] = "WORLD"
attributes["Level3_CD5Position"] = nil -- published without a live source part
local beacons = pickableCDs(5)
check(#beacons == 2 and beacons[1].Index == 1 and beacons[2].Index == 3,
    "carried, inserted and position-less discs are not reader targets")
check(beacons[2].Room == "L3_S2_R04", "a dropped disc carries the room it landed in")

-- Nearest wins, and it is planar distance from the subject.
local nearest, distance, sameRoom = chooseCDTarget(beacons, 9, 0, "L3_S3_R08")
check(nearest.Index == 3 and math.abs(distance - 1) < .001, "the nearest pickable disc wins")
check(sameRoom == false, "a disc in another room does not light the indicator")
nearest, distance = chooseCDTarget(beacons, 1, 0, "")
check(nearest.Index == 1 and math.abs(distance - 1) < .001, "nearest is re-evaluated as you move")

-- Room membership, never proximity: the adjacent room is still another room.
local _, _, adjacent = chooseCDTarget(beacons, 0, 0, "L3_S1_R02")
check(adjacent == false, "a CD through the wall in the next room must not count")
local _, _, inside = chooseCDTarget(beacons, 400, 400, "L3_S1_R01")
check(inside == true, "the indicator answers on room id even from across the room")
local _, _, faraway = chooseCDTarget(beacons, 0, 0, "L3_S2_R04")
check(faraway == true, "any remaining pickable disc in your room counts, not just the nearest")

-- No subject room (outside every rectangle, e.g. a corridor) never matches.
attributes["Level3_CD3Room"] = ""
local corridor = pickableCDs(5)
local _, _, corridorSame = chooseCDTarget(corridor, 0, 0, "")
check(corridorSame == false, "an unknown room matches nothing, including an unknown CD room")

-- Nothing left to collect: no target, so the panel falls back to the exit.
local empty, emptyDistance, emptySame = chooseCDTarget({}, 0, 0, "L3_S1_R01")
check(empty == nil and emptyDistance == math.huge and emptySame == false,
    "with every CD collected the reader has no CD target at all")
'''

TAIL = r'''
print("RESULT " .. encode({checks=checks, seeds=#seeds, maxAttempt=maxAttempt,
    fallbacks=fallbacks, distinctModuleSets=distinctSets, distinctLayouts=distinctHashes,
    firstRooms=countMap(firstRooms), entryDecorPool=decorPool}))
'''


def between(text, start, end):
    return text[text.index(start):text.index(end, text.index(start))]


def generator_factory(name):
    config = (ROOT / SYSTEM / "Level 3 Configuration.ModuleScript.lua").read_text(encoding="utf-8-sig")
    source = (ROOT / SYSTEM / "Level 3 Layout Generator.ModuleScript.lua").read_text(encoding="utf-8-sig")
    source = "\n".join(line for line in source.splitlines()
                       if not line.startswith("local Configuration = require(")
                       and not line.startswith("local Master = require("))
    return (f"local function {name}(overrides)\nlocal Configuration=(function()\n" + config +
            "\nend)()\nlocal Master={Overlay=function(configured)\nlocal result=table.clone(configured)\n"
            "for key,value in pairs(overrides or {}) do result[key]=value end\nreturn result end}\n"
            "local generator=(function()\n" + source + "\nend)()\nreturn generator,Configuration\nend\n")


def reader_block():
    source = (ROOT / READER).read_text(encoding="utf-8-sig")
    block = between(source, "local function chooseCDTarget", "-- L3_CD_READER_TARGET_END_20260921")
    assert "pickableCDs" in block, "the reader's CD selection markers moved"
    return block


def builder_contract(decor_pool):
    """The socket chain that puts the CD on a table, checked in the real source."""
    builder = (ROOT / BUILDER).read_text(encoding="utf-8-sig")
    for literal in (
        "if room.Module and not moduleSocketCreated then",
        'socket:SetAttribute("Level3_CDTableSocket", true)',
        'local socket = roomModel:FindFirstChild("Level 3 CD Table Socket", true)',
    ):
        assert literal in builder, f"the World Builder no longer socket-mounts CDs: {literal}"
    for decor in decor_pool:
        pattern = r'archetype == "%s" then\s*\n\s*layouts = \{\{' % re.escape(decor)
        assert re.search(pattern, builder), f"entry-room archetype {decor} authors no table"
    return len(decor_pool)


def main():
    binary = os.environ.get("LUAU_BIN") or shutil.which("luau")
    if not binary:
        raise SystemExit("Set LUAU_BIN to the Luau executable")
    script = (HOST + generator_factory("currentGenerator") + GENERATOR_TESTS
              + READER_TESTS.replace("__READER__", reader_block()) + TAIL)
    with tempfile.TemporaryDirectory(prefix="level3-first-cd-") as temp:
        path = Path(temp) / "first_cd.luau"
        path.write_text(script, encoding="utf-8")
        result = subprocess.run([binary, str(path)], text=True, capture_output=True)
        if result.returncode:
            raise SystemExit(result.stdout + result.stderr)
    line = next(line for line in result.stdout.splitlines() if line.startswith("RESULT "))
    report = json.loads(line.removeprefix("RESULT "))
    archetypes = builder_contract(report["entryDecorPool"])
    print(f"L3 first CD: {report['checks']} checks passed; {report['seeds']} seeds; "
          f"max attempt {report['maxAttempt']}; fallbacks {report['fallbacks']}; "
          f"{report['distinctModuleSets']} distinct CD sets; {report['firstRooms']} entry rooms; "
          f"{archetypes} entry archetypes author a table; "
          "native Roblox Random sweep still required")


if __name__ == "__main__":
    main()
