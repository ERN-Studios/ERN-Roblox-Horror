"""Run the whole Level 1 Cable Current LocalScript in offline Luau.

The real script, not a copy of it: a stubbed DataModel supplies one circuit
whose cable parts carry the SegmentIndex / Vertical / BoxBranchEnd attributes
PuzzleManager writes, and the test drives Heartbeat by hand.

Covers: route order and direction taken from the attributes (not from the order
GetChildren happens to return), the reversal toward the lever when the circuit's
box is powered, ReduceFlashing reducing the pulse count and speed without ever
turning anything on and off, the Level 1 / RoundActive / InRound gate, and
teardown at round end.

What still needs Studio: how the bead reads at maze light levels, and the real
per-frame cost. Set LUAU_BIN to a Luau interpreter.
"""

from pathlib import Path
import os
import shutil
import subprocess
import tempfile

ROOT = Path(__file__).resolve().parents[2]
SOURCE = (ROOT / "StarterPlayer/StarterPlayerScripts/Level 1 Cable Current.LocalScript.lua").read_text(encoding="utf-8")

HARNESS = r'''
local checks = 0
local function expect(value, wanted, message)
    checks += 1
    assert(value == wanted, message .. ': expected ' .. tostring(wanted) .. ', got ' .. tostring(value))
end
local function near(value, wanted, message, tolerance)
    checks += 1
    assert(math.abs(value - wanted) <= (tolerance or 0.01),
        message .. ': expected ' .. tostring(wanted) .. ', got ' .. tostring(value))
end

-- ── engine stubs ──
local clock = 1000
os = {clock = function() return clock end}

local Vector3 = {}
local vectorMeta = {}
function Vector3.new(x, y, z)
    return setmetatable({Kind = 'Vector3', X = x, Y = y, Z = z}, vectorMeta)
end
vectorMeta.__add = function(a, b) return Vector3.new(a.X + b.X, a.Y + b.Y, a.Z + b.Z) end
vectorMeta.__sub = function(a, b) return Vector3.new(a.X - b.X, a.Y - b.Y, a.Z - b.Z) end
vectorMeta.__mul = function(a, b) return Vector3.new(a.X * b, a.Y * b, a.Z * b) end
vectorMeta.__index = function(a, key)
    if key == 'Magnitude' then return math.sqrt(a.X * a.X + a.Y * a.Y + a.Z * a.Z) end
    return nil
end
local Color3 = {new = function(r, g, b) return {r, g, b} end}
local Enum = {PartType = {Ball = 'Ball'}, Material = {Neon = 'Neon'}}

local function signal()
    local listeners = {}
    return {
        Connect = function(_, fn)
            table.insert(listeners, fn)
            local index = #listeners
            return {Disconnect = function() listeners[index] = function() end end}
        end,
        Fire = function(_, ...) for _, fn in ipairs(listeners) do fn(...) end end,
    }
end

local writeLog = {}
local createdParts = {}
local createdFolders = {}
local Instance = {}
function Instance.new(class)
    local node = {ClassName = class, Name = class, Attributes = {}, Children = {}}
    function node:GetAttribute(key) return self.Attributes[key] end
    function node:Destroy() rawset(self, 'Destroyed', true) end
    if class == 'Part' then
        setmetatable(node, {__newindex = function(t, key, value)
            table.insert(writeLog, key)
            rawset(t, key, value)
        end})
        table.insert(createdParts, node)
    else
        table.insert(createdFolders, node)
    end
    return node
end

-- One circuit, laid the way PuzzleManager lays it: both halves start at the
-- elevator witness point, the box half first.
local function cable(segmentIndex, from, to, vertical)
    local part = {ClassName = 'Part', Name = 'ObjectiveCable',
        Attributes = {SegmentIndex = segmentIndex, CircuitIndex = 1, Vertical = vertical or nil}}
    function part:GetAttribute(key) return self.Attributes[key] end
    local mid = (from + to) * 0.5
    part.Position = mid
    local span = to - from
    local length = span.Magnitude
    local unit = Vector3.new(span.X / length, span.Y / length, span.Z / length)
    if vertical then
        part.Size = Vector3.new(0.34, length, 0.34)
        part.CFrame = {UpVector = unit, LookVector = Vector3.new(0, 0, 1)}
    else
        part.Size = Vector3.new(0.34, 0.09, length)
        part.CFrame = {LookVector = unit, UpVector = Vector3.new(0, 1, 0)}
    end
    return part
end

local WITNESS = Vector3.new(0, 0, 0)
local BOX_FOOT, BOX_TERMINAL = Vector3.new(30, 0, 0), Vector3.new(30, 5, 0)
local LEVER_FOOT, LEVER_TERMINAL = Vector3.new(0, 0, 40), Vector3.new(0, 5, 40)

local circuit = {ClassName = 'Model', Name = 'CircuitCable_01',
    Attributes = {BoxBranchEnd = 3, SegmentCount = 5, CircuitColor = 'RED'}}
function circuit:GetAttribute(key) return self.Attributes[key] end
function circuit:SetAttribute(key, value) self.Attributes[key] = value end
-- Deliberately OUT of order: the walk must use SegmentIndex, never this order.
local segments = {
    cable(4, WITNESS, LEVER_FOOT),
    cable(2, Vector3.new(20, 0, 0), BOX_FOOT),
    cable(5, LEVER_FOOT, LEVER_TERMINAL, true),
    cable(1, WITNESS, Vector3.new(20, 0, 0)),
    -- laid bottom-to-top, but the route climbs it, so the walk must end at the top
    cable(3, BOX_FOOT, BOX_TERMINAL, true),
}
function circuit:GetChildren() return segments end

local puzzleItems = {ClassName = 'Folder', Name = 'PuzzleItems',
    DescendantAdded = signal()}
function puzzleItems:GetChildren() return {circuit} end

local workspaceAttributes = {SelectedLevel = 1, RoundActive = true}
local workspaceSignals = {}
local workspace = {CurrentCamera = {ClassName = 'Camera'}}
function workspace:GetAttribute(key) return workspaceAttributes[key] end
function workspace:FindFirstChild(name)
    if name == 'PuzzleItems' then return puzzleItems end
    return nil
end
function workspace:GetAttributeChangedSignal(key)
    workspaceSignals[key] = workspaceSignals[key] or signal()
    return workspaceSignals[key]
end

local playerAttributes = {InRound = true}
local playerSignals = {}
local player = {}
function player:GetAttribute(key) return playerAttributes[key] end
function player:GetAttributeChangedSignal(key)
    playerSignals[key] = playerSignals[key] or signal()
    return playerSignals[key]
end

local heartbeat = signal()
local services = {
    Players = {LocalPlayer = player},
    RunService = {Heartbeat = heartbeat},
}
local game = {}
function game:GetService(name) return assert(services[name], name) end

-- ── the production script, whole ──
__SCRIPT__

-- ── drive it ──
local function frame(dt)
    clock += dt
    heartbeat:Fire(dt)
end

local function beads()
    local live = {}
    for _, part in ipairs(createdParts) do
        if rawget(part, 'Name') == 'CableCurrentPulse' then table.insert(live, part) end
    end
    return live
end

-- ═══ 1. the route is built from the attributes, not from child order ═══
frame(1 / 60)
local pulses = beads()
expect(#pulses, 2, 'two pulses in flight on a circuit')
-- The first pulse starts at the witness point; the second is half a route along.
near(pulses[1].Position.X, 0, 'pulse one starts at the elevator witness point')
near(pulses[1].Position.Y, 0, 'on the floor')
near(pulses[2].Position.X, 17.5, 'pulse two starts half the 35-stud box route along')

-- ═══ 2. unpowered, the current runs TOWARD the fuse box ═══
frame(1)
near(pulses[1].Position.X, 26, 'a second at 26 studs/s, 26 studs toward the box')
frame(0.25)
near(pulses[1].Position.X, 30, 'past the wall foot')
near(pulses[1].Position.Y, 2.5, 'and climbing the riser into the box')

-- ═══ 3. powering the box REVERSES the current out toward the lever ═══
circuit:SetAttribute('Powered', true)
frame(1 / 60)
near(pulses[1].Position.X, 30, 'the run restarts at the box it just powered')
near(pulses[1].Position.Y, 5, 'at the box terminal')
frame(1)
near(pulses[1].Position.X, 9, 'back down the box half, toward the elevator')
near(pulses[1].Position.Y, 0, 'on the floor again')
frame(1)
near(pulses[1].Position.X, 0, 'through the witness point')
near(pulses[1].Position.Z, 17, 'and on out to the lever')

-- ═══ 4. nothing blinks: after the beads exist, only Position is ever written ═══
local mark = #writeLog
for _ = 1, 40 do frame(1 / 60) end
for index = mark + 1, #writeLog do
    expect(writeLog[index], 'Position',
        'the animation writes nothing but Position (no brightness or colour toggle)')
end

-- ═══ 5. ReduceFlashing: one slower pulse, still no toggling ═══
-- back to the unpowered half, so the measurement is over the straight run out
-- of the elevator rather than across a corner
circuit:SetAttribute('Powered', nil)
playerAttributes.ReduceFlashing = true
playerSignals.ReduceFlashing:Fire()
table.clear(createdParts)
frame(1 / 60)
local reduced = beads()
expect(#reduced, 1, 'ReduceFlashing drops to a single pulse per circuit')
local before = reduced[1].Position.X
frame(1)
local moved = math.abs(reduced[1].Position.X - before)
near(moved, 13, 'and halves the speed to 13 studs/s', 0.5)
playerAttributes.ReduceFlashing = nil

-- ═══ 6. the gate: not a Level 1 round means nothing at all ═══
table.clear(createdParts)
workspaceAttributes.SelectedLevel = 2
frame(1 / 60)
expect(#beads(), 0, 'no pulses outside Level 1')
workspaceAttributes.SelectedLevel = 1
playerAttributes.InRound = nil
frame(1 / 60)
expect(#beads(), 0, 'and none for a player who is not in the round')
playerAttributes.InRound = true

-- ═══ 7. round end tears the holder down ═══
frame(1 / 60)
expect(#beads(), 2, 're-entering the round rebuilds it')
local holder
for _, node in ipairs(createdFolders) do
    if rawget(node, 'Name') == 'Level1CableCurrent' then holder = node end
end
expect(holder ~= nil, true, 'the pulses live in their own client-only folder')
workspaceAttributes.RoundActive = false
workspaceSignals.RoundActive:Fire()
expect(rawget(holder, 'Destroyed'), true, 'and it is destroyed when the round ends')
local quiet = #writeLog
frame(1 / 60)
expect(#writeLog, quiet, 'nothing is written after the round ends')

print(('cable current ok (%d checks)'):format(checks))
'''


def main():
    binary = os.environ.get("LUAU_BIN") or shutil.which("luau")
    if not binary:
        raise SystemExit("set LUAU_BIN to a Luau interpreter")
    directory = tempfile.mkdtemp()
    path = Path(directory) / "level1_cable_current.luau"
    path.write_text(HARNESS.replace("__SCRIPT__", SOURCE), encoding="utf-8")
    result = subprocess.run([binary, str(path)], capture_output=True, text=True)
    shutil.rmtree(directory, ignore_errors=True)
    if result.returncode != 0:
        raise SystemExit(f"{result.stdout}\n{result.stderr}")
    print(result.stdout.strip())


if __name__ == "__main__":
    main()
