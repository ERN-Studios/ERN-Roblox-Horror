"""Pool Foam sight rule (Trello wdz28z81), offline.

A validated look stops a foam dead and resets the speed it earned; unseen it
chases from ChaseMinimumSpeed and accelerates. The server only trusts a camera
report the body can be holding (facesBody). Everything under test is extracted
from the shipped Controller/Observer source; the engine is faked.

What this cannot show: real reports, real occlusion, real frame times. Those
need a Studio round with the Level2_PoolFoamObserved/Speed readbacks.
Set LUAU_BIN to an official luau executable, or put luau on PATH.
"""

from pathlib import Path
import os
import re
import shutil
import subprocess
import tempfile

ROOT = Path(__file__).resolve().parents[2]
SYSTEMS = ROOT / "ServerScriptService/Level 2 Systems"
CONTROLLER = (SYSTEMS / "Level 2 Pool Foam Controller.ModuleScript.lua").read_text(encoding="utf-8")
OBSERVER = (SYSTEMS / "Level 2 Pool Foam Observer.ModuleScript.lua").read_text(encoding="utf-8")
CONFIG = (SYSTEMS / "Level 2 Pool Foam Configuration.ModuleScript.lua").read_text(encoding="utf-8")


def section(source, start, end):
    return source[source.index(start):source.index(end)]


PRELUDE = r'''
local failures, checks = {}, 0
local function check(condition, message)
    checks += 1
    if not condition then table.insert(failures, message) end
end
local PHASES = {Dormant = "Dormant", Foreshadow = "Foreshadow", Pressure = "Pressure", Finale = "Finale"}
local attributes = {}
local function setModelAttribute(model, name, value) attributes[name] = value end
local function entityIsActive() return true end
local latched = 0
local function triggerChase(_, entity) latched += 1; entity.ChaseTriggered = true end
local function fireClientEvent() end
local function phaseRecord(session, phase) return session.Configuration.Phases[phase] end
local function lookAt(x, z) return {LookVector = {X = x, Y = 0, Z = z}} end
'''

TESTS = r'''
local seen = false
local session = {
    Phase = "Pressure",
    Observer = {IsModelObserved = function() return seen, seen and {{UserId = 1}} or {} end},
    Configuration = {
        Observation = {ReleaseSeconds = 0.24, TriggerChaseOnObserve = true,
            FreezeWhileObserved = true, RevealOverrunSeconds = 0},
        Movement = {Speeds = {Stalk = 7.5, Hunt = 7.5},
            SpeedRamp = {Enabled = true, AccelerationPerSecond = 0.65, MaximumBonus = 12,
                MaximumSpeed = 22, ChaseMinimumSpeed = 13, FreezeOnChase = false}},
        Phases = {Pressure = {SpeedMultiplier = 1}},
    },
}
local function newEntity()
    return {Model = {}, Navigator = {GetPosition = function() return nil end},
        Observed = false, Observers = {}, RevealUntil = 0, WasMoving = true, ChaseTriggered = true, SpeedRampBonus = 0, SpeedRampFrozen = false, LastDesiredSpeed = 0}
end
local function near(a, b) return math.abs(a - b) < 1e-6 end

-- 1. An unseen chase starts at the floor and accelerates visibly, to the cap.
local entity = newEntity()
check(near(movementSpeed(session, entity, true, 0), 13), "an unseen chase starts at ChaseMinimumSpeed")
for _ = 1, 10 do movementSpeed(session, entity, true, 0.5) end
check(near(entity.LastDesiredSpeed, 16.25), "5 s unseen adds 5 x 0.65 on top of the floor: " .. entity.LastDesiredSpeed)
for _ = 1, 100 do movementSpeed(session, entity, true, 0.5) end
check(near(entity.LastDesiredSpeed, 22), "and it is capped at MaximumSpeed")

-- 2. A validated look stops it and hands back everything it earned.
seen = true
updateObservation(session, entity, 100)
check(entity.Observed == true, "a validated look observes the foam")
check(entity.SpeedRampBonus == 0, "a look zeroes the earned speed bonus")
check(entity.LastDesiredSpeed > 0, "but leaves LastDesiredSpeed: separation reads it as 'still wants to go'")
check(attributes.Level2_PoolFoamSpeed == 0, "the speed readback shows the stop")
check(entity.RevealUntil == 100, "no overrun step: it is frozen on the tick it is seen")
check(observationFreezes(session), "the shipped rule freezes a watched foam")

-- 3. Looking away: held for ReleaseSeconds, then the chase restarts from the floor.
seen = false
updateObservation(session, entity, 100.1)
check(entity.Observed == true, "a 0.1 s gap is inside the release hold")
updateObservation(session, entity, 100.5)
check(entity.Observed == false, "past ReleaseSeconds the look is over")
check(near(movementSpeed(session, entity, true, 0.1), 13 + 0.065), "the chase resumes from the floor, not the old speed")

-- 4. Stalking (not yet latched) ramps from its phase pace and resets the same way.
local stalker = newEntity()
stalker.ChaseTriggered = false
for _ = 1, 4 do movementSpeed(session, stalker, false, 0.5) end
check(near(stalker.LastDesiredSpeed, 7.5 + 1.3), "a stalker ramps from its phase pace")
seen = true
updateObservation(session, stalker, 200)
check(stalker.SpeedRampBonus == 0, "a look resets a stalker too")
check(latched >= 1, "and the first look still latches the chase")

-- 5. The reset belongs to the freeze rule: with it off, a look keeps the bonus.
local legacy = newEntity()
legacy.SpeedRampBonus = 5
session.Configuration.Observation.FreezeWhileObserved = false
updateObservation(session, legacy, 300)
check(legacy.SpeedRampBonus == 5, "without FreezeWhileObserved a look does not reset speed")
session.Configuration.Observation.FreezeWhileObserved = true

-- 6. Only a camera the body can hold is trusted (root faces +X here).
local root = {CFrame = lookAt(1, 0)}
check(facesBody(lookAt(1, 0), root, 60), "a camera straight ahead is trusted")
check(facesBody(lookAt(math.cos(math.rad(59)), math.sin(math.rad(59))), root, 60), "59 degrees off is trusted")
check(not facesBody(lookAt(math.cos(math.rad(61)), math.sin(math.rad(61))), root, 60), "61 degrees off is not")
check(not facesBody(lookAt(-1, 0), root, 60), "a camera aimed behind the body is not")
check(not facesBody({LookVector = {X = 0, Y = -1, Z = 0}}, root, 60), "a straight-down look has no yaw and is not")

if #failures > 0 then
    for _, message in failures do print("FAIL: " .. message) end
    error(("%d of %d checks failed"):format(#failures, checks))
end
print(("Pool Foam sight rule: %d checks passed"):format(checks))
'''


def build_source(controller=CONTROLLER):
    return "\n".join([
        PRELUDE,
        section(controller, "local function finiteNumber", "local function vectorTable"),
        section(controller, "local function observationFreezes", "local function activeCount"),
        section(controller, "local function updateObservation", "local function choosePatrolPosition"),
        section(controller, "local function movementSpeed", "local function resetProgressWindow"),
        section(OBSERVER, "local function facesBody", "-- The params and the filter table"),
        TESTS,
    ])


def run(source):
    binary = os.environ.get("LUAU_BIN") or shutil.which("luau")
    assert binary, "Set LUAU_BIN to an official luau executable, or put luau on PATH."
    with tempfile.TemporaryDirectory() as directory:
        path = Path(directory) / "sight_rule.luau"
        path.write_text(source, encoding="utf-8")
        return subprocess.run([binary, str(path)], capture_output=True, text=True, timeout=60)


def main():
    # The product decision itself, pinned in the shipped configuration.
    for pattern in (r"FreezeWhileObserved = true", r"RevealOverrunSeconds = 0,", r"FreezeOnChase = false"):
        assert re.search(pattern, CONFIG), f"configuration no longer ships {pattern!r}"
    result = run(build_source())
    print(result.stdout.strip())
    assert result.returncode == 0, result.stderr or result.stdout
    # Mutation: a look that forgets the reset must fail the suite.
    broken = CONTROLLER.replace("\t\t\tentity.SpeedRampBonus = 0\n\t\tend", "\t\tend", 1)
    assert broken != CONTROLLER, "mutation anchor moved"
    assert run(build_source(broken)).returncode != 0, "the suite did not notice a look that keeps its speed"


if __name__ == "__main__":
    main()
