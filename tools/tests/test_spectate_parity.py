"""Run SoundController's real spectate-subject logic in offline Luau.

Extracts the production audioSubject() helper, the footstep block out of the
main Heartbeat, and the spectate binding that mutes the watched character's
default Roblox "Running" loop -- no reimplementation -- and drives them against
a stubbed DataModel. Engine mixing, streaming and replication timing still need
a two-player Studio check. Set LUAU_BIN or put luau on PATH.
"""

from pathlib import Path
import os
import shutil
import subprocess
import tempfile

ROOT = Path(__file__).resolve().parents[2]
SOUND = (ROOT / "StarterPlayer/StarterPlayerScripts/SoundController.LocalScript.lua").read_text(encoding="utf-8")


def section(source, start, stop):
    begin = source.index(start)
    return source[begin:source.index(stop, begin)]


PRELUDE = r'''
local checks = 0
local function expect(value, wanted, message)
    checks += 1
    assert(value == wanted, message .. ': expected ' .. tostring(wanted) .. ', got ' .. tostring(value))
end
local Vector3 = {}
function Vector3.new(x, y, z)
    return {X = x, Y = y, Z = z, Magnitude = math.sqrt(x * x + y * y + z * z)}
end
local function signal()
    local s = {callbacks = {}}
    function s:Connect(fn)
        table.insert(self.callbacks, fn)
        local index = #self.callbacks
        return {Disconnect = function() self.callbacks[index] = function() end end}
    end
    function s:Fire(...) for _, fn in ipairs(self.callbacks) do fn(...) end end
    return s
end

-- one character: humanoid + root (+ the default Running loop the card is about)
local function makeCharacter(health, walkSpeed, speed)
    local running = {ClassName = 'Sound', Volume = 0.65}
    function running:IsA(class) return class == 'Sound' end
    local root = {AssemblyLinearVelocity = Vector3.new(speed, 0, 0), Running = running}
    function root:FindFirstChild(name) return if name == 'Running' then self.Running else nil end
    local humanoid = {Health = health, WalkSpeed = walkSpeed}
    local flag = {Value = false, Changed = signal()}
    local character = {Humanoid = humanoid, Root = root, Running = running, Flashlight = flag}
    function character:FindFirstChildOfClass(class) return if class == 'Humanoid' then humanoid else nil end
    function character:FindFirstChild(name)
        if name == 'HumanoidRootPart' then return self.Root end
        if name == 'FlashlightOn' then return flag end
        return nil
    end
    function character:GetAttribute() return nil end
    return character
end

local attributes = {}
local player = {Character = nil}
function player:GetAttribute(key) return attributes[key] end
local Players = {}
local roster = {}
function Players:GetPlayerByUserId(userId) return roster[userId] end

local worldAttributes = {SelectedLevel = 1}
local workspace = {}
function workspace:GetAttribute(key) return worldAttributes[key] end

local steps = {Volume = 0, SoundId = '', PlaybackSpeed = 1, PlayCount = 0}
function steps:Play() self.PlayCount += 1 end
local curStepId = ''
local clicks = 0
local function playFlashlightClick() clicks += 1 end
'''

FOOTSTEP_TICK_HEAD = r'''
local function footstepTick(dt)
    local hum, root, _, spectated = audioSubject()
'''

TESTS = r'''
-- ── alive: your own body drives your own custom steps ────────────────────
local own = makeCharacter(100, 16, 9)
player.Character = own
attributes.InRound = true
footstepTick(1)
expect(steps.SoundId, FOOTSTEP_WALK, 'alive walking uses the custom walk loop')
expect(steps.Volume, WALK_VOLUME, 'alive walking reaches walk volume')
expect(select(4, audioSubject()), false, 'a living player is never the spectate case')

-- An ESCAPED player is alive and still spectating (SpectateController only ever
-- sets the flag once you are dead or out of play), so the watched body wins
-- over your own parked one.
attributes.Spectating = true
attributes.SpectateTargetUserId = 42
local watched = makeCharacter(100, 26, 30)
roster[42] = {Character = watched}
expect(select(4, audioSubject()), true, 'a live escapee still hears the watched player')
footstepTick(1)
expect(steps.SoundId, FOOTSTEP_RUN, "the escapee hears the watched player's sprint")

-- ── dead + spectating: the WATCHED body drives the steps ─────────────────
own.Humanoid.Health = 0
expect(select(4, audioSubject()), true, 'dead spectator resolves the watched subject')
expect(select(2, audioSubject()), watched.Root, 'the watched root is the subject root')
footstepTick(1)
expect(steps.SoundId, FOOTSTEP_RUN, "the watched player's sprint picks the run loop")
expect(steps.Volume, RUN_VOLUME, 'spectator hears the run loop at full volume')

-- ...and their default Roblox "Running" loop is muted locally, which is the
-- wrong footstep sound the card reports.
bindSpectateTarget()
expect(watched.Running.Volume, 0, "the watched character's default Running loop is muted")
watched.Flashlight.Changed:Fire()
expect(clicks, 1, 'the watched flashlight toggle clicks for the spectator')

-- ── the watched player dies: fall back, restore, fade like stopping ──────
watched.Humanoid.Health = 0
expect(audioSubject(), nil, 'a dead subject is no subject')
footstepTick(1)
expect(steps.Volume, 0, 'losing the subject fades the loop out')
bindSpectateTarget()
expect(watched.Running.Volume, 0.65, 'the muted Running volume is handed back')

-- ── no target at all: silence ───────────────────────────────────────────
watched.Humanoid.Health = 100
attributes.SpectateTargetUserId = nil
expect(audioSubject(), nil, 'no target means no subject')
footstepTick(1)
expect(steps.Volume, 0, 'no target is silent')
attributes.Spectating = nil
attributes.SpectateTargetUserId = 42
expect(audioSubject(), nil, 'a target without Spectating is ignored')

print('Spectate parity: ' .. tostring(checks) .. ' checks passed (offline Luau; engine mix and replication not exercised)')
'''


def main():
    binary = os.environ.get("LUAU_BIN") or shutil.which("luau")
    if not binary:
        raise SystemExit("Set LUAU_BIN or install luau; no tests were executed.")
    footsteps = section(SOUND, "\t-- footsteps: a looping track", "\nend)")
    source = "\n".join([
        PRELUDE,
        # the real audio-slot ids and volumes the block keys on
        section(SOUND, "local AMBIENCE_SOUND", "-- ── tuning"),
        section(SOUND, "local AMBIENCE_VOLUME", "local player = Players.LocalPlayer"),
        section(SOUND, "local function audioSubject()", "local function makeLoop"),
        FOOTSTEP_TICK_HEAD, footsteps, "end",
        section(SOUND, "local spectateFlashlightConn", 'player:GetAttributeChangedSignal("SpectateTargetUserId")'),
        TESTS,
    ])
    with tempfile.TemporaryDirectory(prefix="spectate-parity-") as directory:
        fixture = Path(directory) / "spectate_parity.luau"
        fixture.write_text(source, encoding="utf-8")
        subprocess.run([binary, str(fixture)], check=True, timeout=20)


if __name__ == "__main__":
    main()
