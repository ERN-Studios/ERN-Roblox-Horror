"""Drive the REAL Level 4 Neighbour state machine offline, against a fake world.

The brain is pure by construction -- one `sense` table in, one `decision` table
out -- so this loads its actual source and runs it at a fake clock, both as
single transitions and as a scripted scenario where a player is seen, chased,
and breaks contact by walking quietly round a corner.

What this proves: the RULES. Chase is only ever reached through the telegraph,
a distant sighting is a search and not a chase, noise is investigated at the
noise, quiet walking breaks contact roughly three times faster, and no state
can run forever.

What this cannot prove: raycasts, navmesh, the rig's real speed, or whether the
Neighbour can actually be outrun. Those need `Level 4 Test Suite`.RunWorldChecks()
and a Studio playtest.
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
    source = path.read_text(encoding="utf-8-sig")
    source = "\n".join(
        line for line in source.splitlines()
        if not re.match(r"^local \w+ = require\(", line)
    )
    return "local %s = (function()\n%s\nend)()\n" % (name, source)


TESTS = r'''
local CONFIG = Configuration.Neighbour

-- A fake world: a clock, a state, and a sense table refilled in place the way
-- the real controller refills it.
local function newWorld()
    return {
        Now = 100,
        State = Brain.PATROL,
        StateSince = 100,
        Sense = {},
        Trace = {},
    }
end

local function step(world, facts)
    local sense = world.Sense
    table.clear(sense)
    sense.Now = world.Now
    sense.State = world.State
    sense.StateSince = world.StateSince
    for key, value in pairs(facts) do sense[key] = value end
    local decision = Brain.Step(sense, CONFIG)
    if decision.State ~= world.State then
        world.State = decision.State
        world.StateSince = world.Now
        table.insert(world.Trace, decision.State)
    end
    return decision
end

local function advance(world, seconds)
    world.Now += seconds
end

-- 1. CHASE is unreachable except through ALERT, from every other state.
for _, from in ipairs({Brain.PATROL, Brain.INVESTIGATE, Brain.SEARCH, Brain.RETURN}) do
    local world = newWorld()
    world.State = from
    world.StateSince = world.Now
    local decision = step(world, {Visible = true, VisibleDistance = 5})
    check(decision.State == Brain.ALERT, from .. " -> ALERT, never straight to CHASE")
    check(decision.Telegraph == true, "ALERT must telegraph")
    check(decision.TargetUserId == nil or type(decision.TargetUserId) == "number",
        "the target id is a number or nothing")
end

-- 2. A distant sighting is a TRACE. It produces a search at the sighting, and
--    the brain is never handed a live player position for it.
do
    local world = newWorld()
    local decision = step(world, {Visible = true, VisibleDistance = CONFIG.DetectRange + 0.5})
    check(decision.State == Brain.SEARCH, "a sighting beyond DetectRange is not a chase")
    check(decision.GoalKind == Brain.GOAL_SIGHTING, "and it aims at where they were seen")
    decision = step(world, {Visible = true, VisibleDistance = CONFIG.DetectRange - 0.5})
    check(decision.State == Brain.ALERT, "inside DetectRange it escalates")
end

-- 3. The telegraph is a real window: breaking the line during it cancels the
--    chase, and completing it starts one.
do
    local world = newWorld()
    step(world, {Visible = true, VisibleDistance = 5})
    advance(world, CONFIG.AlertSeconds * 0.5)
    local decision = step(world, {Visible = false, ContactLostFor = 0.6})
    check(decision.State == Brain.SEARCH, "breaking the line during the telegraph cancels it")

    world = newWorld()
    step(world, {Visible = true, VisibleDistance = 5})
    advance(world, CONFIG.AlertSeconds + 0.01)
    decision = step(world, {Visible = true, VisibleDistance = 5})
    check(decision.State == Brain.CHASE, "a completed telegraph becomes a chase")
end

-- 4. Quiet walking matters, and broken line of sight is what ends a chase.
do
    local loud = Brain.ContactGrace(CONFIG, false)
    local quiet = Brain.ContactGrace(CONFIG, true)
    check(quiet < loud, "quiet must shorten the grip")
    check(math.abs(quiet - loud * CONFIG.QuietContactMultiplier) < 1e-9,
        "the quiet grace is the configured multiple")

    -- The scripted scenario: seen, telegraphed, chased, then the player
    -- crouches behind a hedge and the chase drains away.
    local world = newWorld()
    step(world, {Visible = true, VisibleDistance = 6})
    advance(world, CONFIG.AlertSeconds + 0.01)
    step(world, {Visible = true, VisibleDistance = 6})
    check(world.State == Brain.CHASE, "the scenario reached a chase")
    local lost = 0
    for _ = 1, 400 do
        advance(world, 0.1)
        lost += 0.1
        step(world, {Visible = false, ContactLostFor = lost, Quiet = true})
        if world.State ~= Brain.CHASE then break end
    end
    check(world.State == Brain.SEARCH, "a quiet player breaks contact")
    check(lost <= quiet + 0.15, ("and does it in about %.2fs, not %.2fs"):format(quiet, lost))

    -- The same escape, run loudly, takes meaningfully longer.
    local loudWorld = newWorld()
    step(loudWorld, {Visible = true, VisibleDistance = 6})
    advance(loudWorld, CONFIG.AlertSeconds + 0.01)
    step(loudWorld, {Visible = true, VisibleDistance = 6})
    local loudLost = 0
    for _ = 1, 400 do
        advance(loudWorld, 0.1)
        loudLost += 0.1
        step(loudWorld, {Visible = false, ContactLostFor = loudLost, Quiet = false})
        if loudWorld.State ~= Brain.CHASE then break end
    end
    check(loudWorld.State == Brain.SEARCH, "a loud player eventually breaks contact too")
    check(loudLost > lost + 0.5, "but it takes them substantially longer")
end

-- 5. Noise is investigated AT THE NOISE, and a fresher noise re-aims it.
do
    local world = newWorld()
    local decision = step(world, {HasNoise = true, NoiseAt = world.Now - 0.2})
    check(decision.State == Brain.INVESTIGATE, "noise starts an investigation")
    check(decision.GoalKind == Brain.GOAL_NOISE, "aimed at the noise, not at a player")
    advance(world, 1)
    decision = step(world, {HasNoise = true, NoiseAt = world.Now - 0.1})
    check(decision.GoalKind == Brain.GOAL_NOISE and decision.State == Brain.INVESTIGATE,
        "a fresher noise re-aims the same investigation")
    decision = step(world, {AtGoal = true})
    check(decision.State == Brain.SEARCH, "arriving at the noise becomes a search")
end

-- 6. Every state is bounded, and RETURN always drains back to PATROL.
do
    local world = newWorld()
    world.State = Brain.INVESTIGATE
    world.StateSince = world.Now
    advance(world, CONFIG.InvestigateSeconds + 0.1)
    check(step(world, {}).State == Brain.RETURN, "an investigation must end")

    world = newWorld()
    world.State = Brain.SEARCH
    world.StateSince = world.Now
    advance(world, CONFIG.SearchSeconds + 0.1)
    check(step(world, {}).State == Brain.RETURN, "a search must end")

    world = newWorld()
    world.State = Brain.RETURN
    world.StateSince = world.Now
    check(step(world, {AtGoal = true}).State == Brain.PATROL, "a return reaches patrol")

    world = newWorld()
    world.State = Brain.RETURN
    world.StateSince = world.Now
    check(step(world, {LegExpired = true}).State == Brain.PATROL,
        "and reaches patrol even if it never arrives")
end

-- 7. Patrol asks for a new leg rather than standing still forever.
do
    local world = newWorld()
    local decision = step(world, {AtGoal = true})
    check(decision.State == Brain.PATROL and decision.NewGoal == true, "patrol picks a new leg")
    decision = step(world, {LegExpired = true})
    check(decision.NewGoal == true, "a patrol watchdog also picks a new leg")
    decision = step(world, {})
    check(decision.NewGoal == nil, "and otherwise keeps walking its current one")
end

-- 8. An unknown state recovers to patrol instead of wedging.
do
    local world = newWorld()
    world.State = "SOMETHING_ELSE"
    local decision = step(world, {})
    check(decision.State == Brain.PATROL, "an unknown state recovers to patrol")
end

-- 9. The brain does not mutate the sense table it was handed.
do
    local world = newWorld()
    local sense = {Now = 100, State = Brain.PATROL, StateSince = 99, HasNoise = true, NoiseAt = 99.5}
    local before = 0
    for _ in pairs(sense) do before += 1 end
    Brain.Step(sense, CONFIG)
    local after = 0
    for _ in pairs(sense) do after += 1 end
    check(before == after, "Brain.Step must not write into the sense table")
    check(world ~= nil, "scenario holder")
end

for _, message in ipairs(failures) do print("FAIL: " .. message) end
assert(#failures == 0, tostring(#failures) .. " of " .. checks .. " Neighbour brain checks failed")
print(("Level 4 Neighbour brain: %d checks passed (offline; raycasts, navmesh and real "
    .. "chase pacing still need a Studio playtest)"):format(checks))
'''


def main():
    binary = os.environ.get("LUAU_BIN") or shutil.which("luau")
    if not binary:
        raise SystemExit("Set LUAU_BIN or install luau; no tests were executed.")

    config = (SYSTEMS / "Level 4 Configuration.ModuleScript.lua").read_text(encoding="utf-8-sig")
    script = "\n".join([
        HOST,
        "local Configuration = (function()\n" + config + "\nend)()\n",
        module(SYSTEMS / "Level 4 Neighbour Brain.ModuleScript.lua", "Brain"),
        TESTS,
    ])
    with tempfile.TemporaryDirectory(prefix="level4-brain-") as directory:
        fixture = Path(directory) / "level4_brain_test.luau"
        fixture.write_text(script, encoding="utf-8")
        subprocess.run([binary, str(fixture)], check=True, timeout=60)


if __name__ == "__main__":
    main()
