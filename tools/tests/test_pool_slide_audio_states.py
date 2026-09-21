"""Run the actual Level 2 groan state machines in offline Luau.

No Studio, network or asset loading. The REAL blocks are lifted out of the
shipped clients by string markers and driven against stubs:

  * `Level 2 Sound Controller`'s groan session, ownership gate, validity check
    and `updateMonsterGroans` -- the distant pipe-groan scheduler, which must run
    before the first spawn, stand down while the server says a body is alive,
    stay down across a client-side stream-out, and come back on an actual
    despawn.
  * `Level 2 Entity Audio`'s spawn latch -- one mouth groan per BODY, keyed on
    the replicated spawn count, plus the chase-shortened voice interval.

Set LUAU_BIN to an official luau executable, or put luau on PATH.
"""

from pathlib import Path
import os
import shutil
import subprocess
import tempfile

ROOT = Path(__file__).resolve().parents[2]
SOUND = (ROOT / "StarterPlayer/StarterPlayerScripts/Level 2 Sound Controller.LocalScript.lua").read_text(encoding="utf-8")
ENTITY = (ROOT / "StarterPlayer/StarterPlayerScripts/Level 2 Entity Audio.LocalScript.lua").read_text(encoding="utf-8")


def section(source, start, end):
    return source[source.index(start):source.index(end)]


PRELUDE = r'''
local checks = 0
local function check(value, message) assert(value, message); checks += 1 end

local instanceMethods = {}
function instanceMethods:SetAttribute(key, value) self.Attributes[key] = value end
function instanceMethods:GetAttribute(key) return self.Attributes[key] end
function instanceMethods:FindFirstChild(name) return self.Children[name] end
function instanceMethods:Destroy() self.Parent = nil; self.Destroyed = true end
local function holder(name)
    return setmetatable({Name = name, Attributes = {}, Children = {}, Parent = true},
        {__index = instanceMethods})
end

local workspace = holder("Workspace")
local ReplicatedStorage = holder("ReplicatedStorage")
local bankModule = holder("Level 2 Entity Audio Bank")
ReplicatedStorage.Children["Level 2 Entity Audio Bank"] = bankModule
local bank = {Enabled = true}
local require = function(module)
    if module ~= bankModule then error("unexpected require") end
    return bank
end

-- The schedulers read os.clock(); shadow the whole table so time is ours.
local now = 1000
local os = {clock = function() return now end}

local fadeCount, debrisCount = 0, 0
local TweenInfo = {new = function(seconds) return {Time = seconds} end}
local TweenService = {Create = function(_, _, _, goal)
    return {Play = function() fadeCount += 1 end, Goal = goal}
end}
local Debris = {AddItem = function() debrisCount += 1 end}

local rng = {}
-- Deterministic: always the low end of a range, so a scheduled delay is exact.
function rng:NextNumber(low) return low end
'''

SOUND_STUBS = r'''
local ambientWorld = holder("Level 2 Generated World")
ambientWorld:SetAttribute("Level2_Generation", 4)
local player = holder("Player")
local sessionLive = true
local listenerPresent = true
local function syncRandomSession() return sessionLive end
local function randomActive() return sessionLive end
local function rootPart() return listenerPresent and {Position = 0} or nil end
local function spectateSubject() return nil end
local function warn() end
local authoredBusyUntil, ambientBusyUntil = 0, 0
local playCount = 0
local lastEmitter
local function takeMonsterGroanSlot() return "Level 2 Distant Monster-Like Pipe Groan 1" end
local function playMonsterGroan()
    playCount += 1
    lastEmitter = holder("Level 2 Distant Pipe Groan Emitter")
    groanRecord = {Owner = lastEmitter, Sound = holder("Sound"), Started = true,
        ExpiresAt = now + 9, Slot = "slot",
        World = ambientWorld, Generation = groanGeneration}
    nextGroanAt = now + GROAN_DELAY_MIN
    return true
end
'''

SOUND_TESTS = r'''
local function poll(seconds)
    now += seconds or GROAN_POLL_INTERVAL
    nextGroanPollAt = 0
    updateMonsterGroans()
end

-- 1. Before any spawn: the distant scheduler arms itself and speaks.
poll()
check(groanWorld == ambientWorld and nextGroanAt < math.huge,
    "the first poll opens a groan session with a finite delay")
now = nextGroanAt
poll(0)
check(playCount == 1 and groanRecord ~= nil, "distant ambience runs BEFORE the first spawn")

-- 2. The server publishes a live body: the pipes stand down, with a fade.
workspace:SetAttribute("Level2_PoolSlideActive", true)
poll()
check(groanStoodDown and nextGroanAt == math.huge, "an active body stands the distant scheduler down")
check(groanRecord == nil and fadeCount == 1 and debrisCount == 1,
    "the stand-down fades the playing groan instead of cutting it")
check(not lastEmitter.Destroyed, "a faded emitter is handed to Debris, never destroyed mid-clip")
now += 600
poll(0)
check(playCount == 1, "nothing distant plays while the body owns the voice")

-- 3. A client-side STREAM-OUT is not a despawn: the server still says Active.
ambientWorld.Children["Level 2 Pool Slide Runtime"] = nil
poll()
check(nextGroanAt == math.huge and playCount == 1,
    "a stream-out never resumes the distant ambience")

-- 4. An ACTUAL despawn clears Active: the pipes come back after a random pause.
workspace:SetAttribute("Level2_PoolSlideActive", false)
poll()
check(not groanStoodDown and nextGroanAt == now + GROAN_DELAY_MIN,
    "a real despawn reschedules the distant ambience")
check(playCount == 1, "the resume waits out a pause; it does not fire instantly")
now = nextGroanAt
poll(0)
check(playCount == 2, "distant ambience runs again after the despawn")

-- 5. A second spawn in the same round stands it down again.
workspace:SetAttribute("Level2_PoolSlideActive", true)
poll()
check(groanStoodDown and nextGroanAt == math.huge and groanRecord == nil,
    "a second spawn stands the pipes down again")

-- 6. Round end: the real session reset leaves nothing playing and nothing armed.
workspace:SetAttribute("Level2_PoolSlideActive", false)
poll()
now = nextGroanAt
poll(0)
check(playCount == 3 and groanRecord ~= nil, "a groan is in flight going into teardown")
sessionLive = false
resetGroanSession()
check(groanRecord == nil and lastEmitter.Destroyed and nextGroanAt == math.huge
    and groanWorld == nil,
    "round end destroys the emitter and clears every groan timer")
now += 10000
poll(0)
check(playCount == 3, "nothing is scheduled after the round ends")

-- 6b. A teardown that happens MID-encounter must not leave the latch stuck on.
sessionLive = true
workspace:SetAttribute("Level2_PoolSlideActive", true)
poll()
check(groanStoodDown, "the stand-down latch is set going into a mid-encounter teardown")
resetGroanSession()
check(not groanStoodDown, "round end clears the stand-down latch")
sessionLive = false
workspace:SetAttribute("Level2_PoolSlideActive", false)

-- 7. The next round is a fresh world/generation: no leaked timer or latch.
sessionLive = true
ambientWorld = holder("Level 2 Generated World")
ambientWorld:SetAttribute("Level2_Generation", 5)
poll()
check(groanWorld == ambientWorld and groanGeneration == 5 and nextGroanAt < math.huge,
    "a repeated round rebinds the session and re-arms the scheduler")
now = nextGroanAt
poll(0)
check(playCount == 4, "the repeated round's distant ambience runs")

-- 8. A groan bound to the previous generation can never survive into this one.
groanRecord.Generation = 4
check(not groanPlaybackStillValid(groanRecord), "a stale-generation groan is rejected")
groanRecord.Generation = 5
check(groanPlaybackStillValid(groanRecord), "the current generation's groan is valid")
workspace:SetAttribute("Level2_PoolSlideActive", true)
check(not groanPlaybackStillValid(groanRecord), "an active body invalidates a distant groan")

-- 9. The bank's kill switch hands the four groans back to the pipes.
bank.Enabled = false
entityAudioEnabled = nil
check(not entityAudioOwnsBody(), "a disabled entity audio bank never silences the pipes")
bank.Enabled = true
entityAudioEnabled = nil
check(entityAudioOwnsBody(), "an enabled bank plus an active body owns the voice")
'''

ENTITY_PRELUDE = r'''
local stateFolder = holder("Level 2 State")
ReplicatedStorage.Children["Level 2 State"] = stateFolder
stateFolder:SetAttribute("Level2_PoolSlideSpawnCount", 0)
workspace:SetAttribute("Level2_PoolSlideActive", false)
'''

ENTITY_TESTS = r'''
-- A round with no body: nothing to announce.
check(not updateSlideSpawnLatch(now, 4), "no spawn groan without an active body")

-- Spawn: exactly one announcement is armed.
workspace:SetAttribute("Level2_PoolSlideActive", true)
stateFolder:SetAttribute("Level2_PoolSlideSpawnCount", 1)
check(updateSlideSpawnLatch(now, 4), "a spawn arms exactly one mouth groan")
slideSpawnPending = false -- the record fired it
check(not updateSlideSpawnLatch(now + .1, 4), "the spawn groan is not re-armed once fired")

-- Stream-out and back: same generation, same spawn count, so no second groan.
check(not updateSlideSpawnLatch(now + 1, 4), "a stream-out/in does not re-announce the same body")

-- A second spawn in the SAME round does arm a new announcement.
stateFolder:SetAttribute("Level2_PoolSlideSpawnCount", 2)
check(updateSlideSpawnLatch(now + 2, 4), "a second spawn in the same round announces again")

-- It is dropped rather than faked if the rig never replicates in time.
check(not updateSlideSpawnLatch(now + 2 + SPAWN_GROAN_GRACE, 4),
    "an un-replicated rig drops the announcement instead of faking it elsewhere")

-- A despawn disarms; the next round's generation arms a fresh one.
workspace:SetAttribute("Level2_PoolSlideActive", false)
check(not updateSlideSpawnLatch(now + 3, 4), "a despawn leaves nothing armed")
workspace:SetAttribute("Level2_PoolSlideActive", true)
stateFolder:SetAttribute("Level2_PoolSlideSpawnCount", 1)
check(updateSlideSpawnLatch(now + 4, 5), "a repeated round announces its own first spawn")

-- Chase shortens the gap between mouth groans.
check(mouthVoiceDelay(true) == MOUTH_CHASE_MIN and mouthVoiceDelay(false) == MOUTH_IDLE_MIN,
    "the mouth interval has a chase form and an idle form")
check(MOUTH_CHASE_MAX < MOUTH_IDLE_MIN,
    "every chase interval is shorter than every idle interval")

print("Pool Slide audio states: " .. tostring(checks)
    .. " checks passed (offline Luau; engine mix, rolloff and asset loading not exercised)")
'''


def main():
    binary = os.environ.get("LUAU_BIN") or shutil.which("luau")
    if not binary:
        raise SystemExit("Set LUAU_BIN or install luau; no tests were executed.")
    source = "\n".join([
        PRELUDE,
        section(SOUND, "local GROAN_DELAY_MIN", "local RANDOM_AMBIENCE_SLOTS"),
        section(SOUND, "local groanWorld, groanGeneration", "local function disconnectAmbientConnections"),
        SOUND_STUBS,
        section(SOUND, "-- GROAN OWNERSHIP BEGIN", "-- GROAN OWNERSHIP END"),
        section(SOUND, "local function groanPlaybackStillValid", "local function playMonsterGroan"),
        section(SOUND, "local function updateMonsterGroans", "RunService.Heartbeat:Connect(updateMonsterGroans)"),
        SOUND_TESTS,
        ENTITY_PRELUDE,
        section(ENTITY, "-- SLIDE SPAWN LATCH BEGIN", "-- SLIDE SPAWN LATCH END"),
        ENTITY_TESTS,
    ])
    with tempfile.TemporaryDirectory(prefix="pool-slide-audio-") as directory:
        fixture = Path(directory) / "slide_audio_test.luau"
        fixture.write_text(source, encoding="utf-8")
        subprocess.run([binary, str(fixture)], check=True, timeout=20)


if __name__ == "__main__":
    main()
