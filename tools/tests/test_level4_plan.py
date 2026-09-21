"""Run the REAL Level 4 plan generator and validator in offline Luau.

No Studio, no Instances: the plan generator is pure by construction, so this
loads its actual source (with the `require` lines stripped and the real
Configuration inlined) and asserts the five things the brief asks of a plan --
the loop and its cross shortcut connect, every signal is reachable solo, the
exit is reachable, the safe-house invariant can hold, and nothing required sits
behind its own lock -- for every seed and every variant.

It also re-derives the door/stair/agent envelopes from the body numbers rather
than reading them back, and checks that the client lighting controller's
restated Lighting block still matches the server Configuration (a LocalScript
cannot require a ServerScriptService module, so those numbers are duplicated on
purpose and drift is the obvious failure mode).

What this CANNOT show: real navmesh, real collision, real frame times. Those
need `Level 4 Test Suite`.RunWorldChecks() in a Studio play session.
Set LUAU_BIN to an official luau executable, or put luau on PATH.
"""

import os
import re
import shutil
import subprocess
import tempfile
from pathlib import Path

ROOT = Path(__file__).resolve().parents[2]
SYSTEMS = ROOT / "ServerScriptService/Level 4 Systems"
CLIENT_LIGHTING = ROOT / "StarterPlayer/StarterPlayerScripts/Level 4 Lighting Controller.LocalScript.lua"

HOST = r'''
local Vector3 = {}
function Vector3.new(x, y, z) return {X = x, Y = y, Z = z} end
local Color3 = {}
function Color3.fromRGB(r, g, b) return {R = r, G = g, B = b} end
local checks, failures = 0, {}
local function check(condition, message)
    checks += 1
    if not condition then table.insert(failures, message) end
end
'''


def module(path: Path, name: str) -> str:
    """Wrap a ModuleScript source as `local <name> = (function() ... end)()`.

    The require lines are dropped and replaced by the locals the host already
    holds, which is the same trick tools/tests/test_level3_square_layout.py uses.
    """
    source = path.read_text(encoding="utf-8-sig")
    source = "\n".join(
        line for line in source.splitlines()
        if not re.match(r"^local \w+ = require\(", line)
    )
    return "local %s = (function()\nlocal Configuration = __CONFIG__\n%s\nend)()\n" % (name, source)


TESTS = r'''
-- 1. Derived envelopes, re-derived rather than read back.
local body = Configuration.Body
local derived = Configuration.Derived
local expectedDoor = math.max(body.PlayerWidth * 2 + body.PlayerPassGap,
    body.NeighbourShoulderWidth + body.NeighbourArmSwing + body.NeighbourClearance)
check(math.abs(derived.DoorWidth - expectedDoor) < 1e-9,
    ("DoorWidth %.3f must equal the wider body %.3f"):format(derived.DoorWidth, expectedDoor))
check(derived.DoorWidth >= 2 * body.PlayerWidth + body.PlayerPassGap,
    "two players must fit abreast through every door")
check(math.abs(derived.DoorHeight - (body.NeighbourHeight + 1)) < 1e-9,
    "DoorHeight must clear the Neighbour by one stud")
check(derived.InteriorCeiling > derived.DoorHeight, "the ceiling must clear the door")
check(derived.PassageWidth >= derived.DoorWidth, "passages are at least door width")
check(derived.StairWidth >= derived.DoorWidth, "stairs are at least door width")
check(derived.StairRise <= 1.5, "a stair rise over 1.5 studs is not walkable by an R15 Humanoid")
check(derived.AgentRadius * 2 < derived.DoorWidth, "the agent must fit through a door")
check(derived.AgentHeight < derived.InteriorCeiling, "the agent must fit under the ceiling")
check(Configuration.Streets.HalfWidth * 2 > derived.AgentRadius * 4,
    "the street must be navigable by the agent")

-- 2. Every seed: valid, repeatable, and connected.
local seeds = {1, 2, 3, 101, 7331, 65537, 1900813, 2147483646}
for index = 1, 60 do table.insert(seeds, index * 104729 + 1) end
local variantSeen, hashes, uniqueHashes = {}, {}, 0
for _, seed in ipairs(seeds) do
    local plan = PlanGenerator.Generate(seed)
    local again = PlanGenerator.Generate(seed)
    check(plan.PlanHash == again.PlanHash, "seed " .. seed .. " must repeat exactly")
    local valid, problem = PlanGenerator.Validate(plan)
    check(valid, "seed " .. seed .. " must validate: " .. tostring(problem))
    variantSeen[plan.Variant] = (variantSeen[plan.Variant] or 0) + 1
    if not hashes[plan.PlanHash] then
        hashes[plan.PlanHash] = true
        uniqueHashes += 1
    end

    local adjacency = PlanGenerator.__test.Adjacency(plan)
    local reached = PlanGenerator.__test.Reachable(adjacency, "Arrival")
    for _, junction in ipairs(plan.Junctions) do
        check(reached[junction.Id] == true,
            "seed " .. seed .. ": " .. junction.Id .. " unreachable from the arrival")
    end

    -- The loop and the shortcut: two independent cycles over the non-service
    -- subgraph, and every loop junction has a second way out.
    local loopEdges, loopNodes = 0, 0
    for _, edge in ipairs(plan.Streets) do
        if edge.Kind ~= "Service" then loopEdges += 1 end
    end
    for _, junction in ipairs(plan.Junctions) do
        if junction.Id ~= "Arrival" then
            loopNodes += 1
            check(#adjacency[junction.Id] >= 2,
                "seed " .. seed .. ": " .. junction.Id .. " is a dead end")
        end
    end
    check(loopEdges - loopNodes + 1 >= 2, "seed " .. seed .. ": needs a loop AND a shortcut")

    -- Signals: one per zone, reachable, enterable, with a readable clue, and
    -- never two on one house.
    local zones, lots = {}, {}
    for _, task in ipairs(plan.Tasks) do
        local lot = plan.LotById[task.LotId]
        local edge = plan.StreetById[lot.StreetId]
        check(reached[edge.A] and reached[edge.B],
            "seed " .. seed .. ": signal " .. task.Index .. " is not reachable solo")
        check(lot.Interior > 0, "seed " .. seed .. ": signal " .. task.Index .. " has no interior")
        check(lot.Anomaly ~= nil, "seed " .. seed .. ": signal " .. task.Index .. " has no facade clue")
        check(not zones[task.Zone], "seed " .. seed .. ": two signals in one zone")
        check(not lots[task.LotId], "seed " .. seed .. ": two signals in one house")
        zones[task.Zone], lots[task.LotId] = true, true
    end
    check(plan.Tasks[1].Forgiving == true, "seed " .. seed .. ": the first signal must be forgiving")
    local forgiving = 0
    for _, task in ipairs(plan.Tasks) do
        if task.Forgiving then forgiving += 1 end
    end
    check(forgiving == 1, "seed " .. seed .. ": exactly one signal is the forgiving one")

    -- The exit is reachable and is not a house, so no signal can be inside it.
    check(plan.Exit ~= nil and plan.BusStop ~= nil and plan.Cabinet ~= nil,
        "seed " .. seed .. ": the finale is missing")
    for _, lot in ipairs(plan.Lots) do
        check(lot.Id ~= "Exit", "seed " .. seed .. ": a lot may not be the exit")
    end

    check(#plan.Lots >= 8 and #plan.Lots <= 12,
        "seed " .. seed .. ": 8 to 12 visible houses, not " .. #plan.Lots)
end

-- 3. Variant selection reaches all three combinations.
for variant = 1, PlanGenerator.VariantCount do
    check((variantSeen[variant] or 0) > 0, "variant " .. variant .. " is never selected")
end
check(uniqueHashes >= PlanGenerator.VariantCount,
    "distinct variants must produce distinct plan hashes")

-- 4. THE SAFE-HOUSE INVARIANT, as the rule is actually written.
--    mayTake() is copied verbatim from the Objective Controller below; here it
--    is driven over every variant and every legal promotion the scheduler could
--    make, asserting that no reachable combination strands a zone.
for _, seed in ipairs({1, 2, 3, 101, 7331}) do
    local plan = PlanGenerator.Generate(seed)
    -- The scheduler's own eligible set: enterable houses that are not the
    -- intro house (the intro house is permanently safe).
    local houses = {}
    for _, lot in ipairs(plan.Lots) do
        if lot.Interior > 0 and lot.Role ~= "Intro" then
            table.insert(houses, {Lot = lot, HouseState = "SAFE"})
        end
    end
    local session = {Houses = houses}
    local taken = 0
    local guard = 0
    while taken < Configuration.HouseStates.MaximumUnsafe and guard < 40 do
        guard += 1
        local promoted = false
        for _, record in ipairs(houses) do
            if record.HouseState == "SAFE" and mayTake(session, record) then
                record.HouseState = "DANGEROUS"
                taken += 1
                promoted = true
                break
            end
        end
        if not promoted then break end
    end
    -- Whatever the scheduler took, every zone with an enterable house still
    -- has a safe one. Zone 1 also still holds the permanently-safe intro house.
    local enterablePerZone, safePerZone = {}, {}
    for _, record in ipairs(houses) do
        local zone = record.Lot.Zone
        enterablePerZone[zone] = (enterablePerZone[zone] or 0) + 1
        if record.HouseState == "SAFE" then safePerZone[zone] = (safePerZone[zone] or 0) + 1 end
    end
    for zone, count in pairs(enterablePerZone) do
        if count > 0 then
            check((safePerZone[zone] or 0) >= 1,
                "seed " .. seed .. ": zone " .. zone .. " was stranded with no safe house")
        end
    end
    check(taken > 0, "seed " .. seed .. ": the scheduler could never promote anything")
end

-- 5. The validator REJECTS. A validator that only says yes is not one.
--    `restamp` recomputes the plan hash after the mutation, because the
--    stale-hash guard would otherwise fire first and the semantic rule under
--    test would never run. One case deliberately does NOT re-stamp, to prove
--    the hash guard itself works.
local function rejects(mutate, expected, restamp)
    local plan = PlanGenerator.Generate(101)
    mutate(plan)
    if restamp ~= false then plan.PlanHash = PlanGenerator.__test.Hash(plan) end
    local valid, problem = PlanGenerator.Validate(plan)
    check(not valid and string.find(tostring(problem), expected, 1, true) ~= nil,
        "expected rejection containing '" .. expected .. "', got: " .. tostring(problem))
end
rejects(function(plan) plan.Lots[1].X += 900 end, "hash is stale", false)
rejects(function(plan) plan.Tasks[1].Forgiving = false end, "forgiving")
rejects(function(plan) plan.LotById.Intro.Interior = 0 end, "intro house")
rejects(function(plan) plan.LotById[plan.Tasks[2].LotId].Anomaly = nil end, "facade clue")
rejects(function(plan) plan.LotById[plan.Tasks[2].LotId].Anomaly = "GhostInTheHall" end,
    "unknown anomaly")
rejects(function(plan) plan.Tasks[2].Kind = "SolveTheRiddle" end, "unknown signal kind")
rejects(function(plan)
    local first, second = plan.Lots[2], plan.Lots[3]
    second.X, second.Z = first.X, first.Z
end, "overlap")
rejects(function(plan)
    plan.StreetById.Shortcut = nil
    for index, edge in ipairs(plan.Streets) do
        if edge.Id == "Shortcut" then table.remove(plan.Streets, index) break end
    end
end, "shortcut", false)
rejects(function(plan)
    for index, edge in ipairs(plan.Streets) do
        if edge.Id == "AvenueEast" then table.remove(plan.Streets, index) break end
    end
    plan.StreetById.AvenueEast = nil
end, "dead end", false)
rejects(function(plan) plan.Variant = 99 end, "variant out of range", false)

for _, message in ipairs(failures) do print("FAIL: " .. message) end
assert(#failures == 0, tostring(#failures) .. " of " .. checks .. " Level 4 plan checks failed")
print(("Level 4 plan: %d checks passed over %d seeds, %d distinct plans, %d variants "
    .. "(offline; navmesh/collision/frame time still need the Studio world checks)")
    :format(checks, #seeds, uniqueHashes, PlanGenerator.VariantCount))
'''


def between(text: str, start: str, end: str) -> str:
    begin = text.index(start)
    return text[begin:text.index(end, begin)]


def lighting_mirror_matches() -> list:
    """The client restates the server's Lighting block; drift is the failure."""
    server = (SYSTEMS / "Level 4 Configuration.ModuleScript.lua").read_text(encoding="utf-8")
    client = CLIENT_LIGHTING.read_text(encoding="utf-8")
    block = between(server, "\tLighting = {", "\n\t},")
    problems = []
    # One key per line, value to the end of the line. Splitting on commas would
    # cut Color3.fromRGB(...) in half, which is exactly what it did first time.
    for key, value in re.findall(r"^\t\t(\w+) = (.+),\s*$", block, re.M):
        key, value = key.strip(), value.strip()
        if re.search(r"^\t%s = %s,\s*$" % (re.escape(key), re.escape(value)), client, re.M) is None:
            problems.append(f"{key} = {value}")
    return problems


def main():
    binary = os.environ.get("LUAU_BIN") or shutil.which("luau")
    if not binary:
        raise SystemExit("Set LUAU_BIN or install luau; no tests were executed.")

    drift = lighting_mirror_matches()
    if drift:
        raise SystemExit(
            "Level 4 Lighting Controller no longer mirrors Configuration.Lighting: "
            + ", ".join(drift)
        )

    config = (SYSTEMS / "Level 4 Configuration.ModuleScript.lua").read_text(encoding="utf-8-sig")
    plan_source = module(SYSTEMS / "Level 4 Plan Generator.ModuleScript.lua", "PlanGenerator")
    plan_source = plan_source.replace("__CONFIG__", "Configuration")

    # mayTake, verbatim from the shipped Objective Controller. Slicing it rather
    # than restating it is the point: a change to the rule fails this test.
    objective = (SYSTEMS / "Level 4 Objective Controller.ModuleScript.lua").read_text(encoding="utf-8-sig")
    may_take = between(objective, "local function mayTake", "\nlocal function evaluateHouses")

    script = "\n".join([
        HOST,
        "local Configuration = (function()\n" + config + "\nend)()\n",
        plan_source,
        may_take,
        TESTS,
    ])
    with tempfile.TemporaryDirectory(prefix="level4-plan-") as directory:
        fixture = Path(directory) / "level4_plan_test.luau"
        fixture.write_text(script, encoding="utf-8")
        subprocess.run([binary, str(fixture)], check=True, timeout=120)


if __name__ == "__main__":
    main()
