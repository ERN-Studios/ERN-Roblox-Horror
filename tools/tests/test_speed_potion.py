"""Exercise NoiseReporter's real speed path against the Speed Potion attributes.

Extracts the production movement blocks -- the speed constants, the stamina
block, movementAvailable, applySpeed/speedBoost and the in-round boost edge --
and runs them over a matrix of movement states and boost attribute values. None
of the decisions are reimplemented here; a copy would only prove itself.

The server writes ZyntraSpeedBoostUntil / ZyntraSpeedBoostMultiplier (A-SERVER,
ZyntraMonetization); this file only proves the client consumes them correctly.
Replication timing and the engine's own WalkSpeed handling need Studio.
Set LUAU_BIN to an official Luau interpreter.
"""

import os
from pathlib import Path
import shutil
import subprocess
import tempfile

ROOT = Path(__file__).resolve().parents[2]
SOURCE = (ROOT / "StarterPlayer/StarterPlayerScripts/NoiseReporter.LocalScript.lua").read_text(
    encoding="utf-8")


def block(start, stop):
    """The real source between two markers, start marker included."""
    begin = SOURCE.index(start)
    return SOURCE[begin:SOURCE.index(stop, begin + len(start))]


def line(marker):
    """The one whole line carrying `marker`."""
    at = SOURCE.index(marker)
    begin = SOURCE.rfind("\n", 0, at) + 1
    return SOURCE[begin:SOURCE.index("\n", at)].strip() + "\n"


HARNESS = r'''
local checks = 0
local function same(value, wanted, message)
    checks += 1
    assert(value == wanted, message .. ": expected " .. tostring(wanted) .. ", got " .. tostring(value))
end
local function near(value, wanted, message)
    checks += 1
    assert(type(value) == "number" and math.abs(value - wanted) < 1e-9,
        message .. ": expected " .. tostring(wanted) .. ", got " .. tostring(value))
end

local now = 1000
local attrs, charAttrs = {}, {}
local attributeSignals = {}
local workspace = {GetServerTimeNow = function() return now end,
    GetAttribute = function(_, key) return nil end}
local player = {}
function player:GetAttribute(key) return attrs[key] end
function player:SetAttribute(key, value)
    if attrs[key] == value then return end
    attrs[key] = value
    local listeners = attributeSignals[key]
    for _, fn in ipairs(listeners or {}) do fn() end
end
function player:GetAttributeChangedSignal(key)
    attributeSignals[key] = attributeSignals[key] or {}
    local listeners = attributeSignals[key]
    return {Connect = function(_, fn) table.insert(listeners, fn) end}
end
local character = {}
function character:GetAttribute(key) return charAttrs[key] end
function character:SetAttribute(key, value) charAttrs[key] = value end
local hum = {WalkSpeed = 16, Health = 100}
local function currentChar() return character, hum end
local state, sprinting, crouching = "walk", false, false
'''

FIXTURE = [
    HARNESS,
    line("local function inRound() return player:GetAttribute"),
    line("local WALK_SPEED, SPRINT_SPEED, CROUCH_SPEED"),
    block("-- stamina: sprint is limited", "\n-- ADRENALINE"),
    block("local function movementAvailable()", "local function crouchAllowed()"),
    block("local speedBoost", "local function refreshCrouch()"),
    block("local boostActive = false", "RunService.Heartbeat:Connect(function(dt)"),
    "local function heartbeatEdge()\n\t" + line("if (speedBoost() > 1) ~= boostActive") + "end\n",
]

TESTS = r'''
-- The potion must not have moved a single stamina number.
same(WALK_SPEED, 16, "walk speed unchanged")
same(SPRINT_SPEED, 26, "sprint speed unchanged")
same(CROUCH_SPEED, 8, "crouch speed unchanged")
same(STAMINA_BASE, 100, "stamina base unchanged")
same(SPRINT_DRAIN, 16, "sprint drain unchanged")
same(STAMINA_RECHARGE, 10, "stamina recharge unchanged")
same(STAMINA_RECOVER, 25, "exhaustion recovery threshold unchanged")
same(staminaMax(), 100, "stamina maximum unchanged")

local function reset()
    now = 1000
    table.clear(attrs)
    table.clear(charAttrs)
    attrs.InRound = true
    state, sprinting, crouching = "walk", false, false
    stamina, exhausted = staminaMax(), false
    hum.WalkSpeed = 16
    boostActive = false
end

-- movementAvailable is the gate the HUD control reads; it must stay blind to
-- the boost and keep answering false for every state that owns the body.
reset()
same(movementAvailable(), true, "a living in-round player may move")
attrs.ZyntraSpeedBoostUntil, attrs.ZyntraSpeedBoostMultiplier = now + 6, 1.10
same(movementAvailable(), true, "a boost does not change movement availability")
attrs.Level3_Hiding = true
same(movementAvailable(), false, "hiding still owns the body")
reset()
attrs.InRound = false
same(movementAvailable(), false, "the lobby is not a movement state")

-- ---------------------------------------------------------------- the matrix
local rows = {
    {Name = "lobby", Speed = 16, Boosts = false, Apply = function() attrs.InRound = false end},
    {Name = "lobby sprint", Speed = 26, Boosts = false,
        Apply = function() attrs.InRound = false; sprinting = true end},
    {Name = "walk", Speed = 16, Apply = function() end},
    {Name = "sprint", Speed = 26, Apply = function() sprinting = true end},
    {Name = "sprint exhausted", Speed = 16,
        Apply = function() sprinting = true; exhausted = true end},
    {Name = "sprint drained", Speed = 16,
        Apply = function() sprinting = true; stamina = 0 end},
    {Name = "crouch", Speed = 8, Apply = function() crouching = true end},
    {Name = "hiding lock", Speed = 16, Locked = true,
        Apply = function() attrs.Level3_Hiding = true end},
    {Name = "slide lock", Speed = 16, Locked = true,
        Apply = function() charAttrs.Level2_ForcedSliding = true end},
    {Name = "ragdoll lock", Speed = 16, Locked = true,
        Apply = function() charAttrs.Level2_RagdollServerActive = true end},
    {Name = "crouched hiding lock", Speed = 8, Locked = true,
        Apply = function() crouching = true; attrs.Level3_Hiding = true end},
}
local columns = {
    {Name = "no boost", Multiplier = 1, Apply = function() end},
    {Name = "boost active", Multiplier = 1.10, Apply = function()
        attrs.ZyntraSpeedBoostUntil, attrs.ZyntraSpeedBoostMultiplier = now + 6, 1.10 end},
    {Name = "boost expiring this frame", Multiplier = 1, Apply = function()
        attrs.ZyntraSpeedBoostUntil, attrs.ZyntraSpeedBoostMultiplier = now, 1.10 end},
    {Name = "boost expired", Multiplier = 1, Apply = function()
        attrs.ZyntraSpeedBoostUntil, attrs.ZyntraSpeedBoostMultiplier = now - 0.5, 1.10 end},
    {Name = "until zero", Multiplier = 1, Apply = function()
        attrs.ZyntraSpeedBoostUntil, attrs.ZyntraSpeedBoostMultiplier = 0, 1.10 end},
    {Name = "until NaN", Multiplier = 1, Apply = function()
        attrs.ZyntraSpeedBoostUntil, attrs.ZyntraSpeedBoostMultiplier = 0 / 0, 1.10 end},
    {Name = "until string", Multiplier = 1, Apply = function()
        attrs.ZyntraSpeedBoostUntil, attrs.ZyntraSpeedBoostMultiplier = "9999", 1.10 end},
    {Name = "multiplier missing", Multiplier = 1, Apply = function()
        attrs.ZyntraSpeedBoostUntil = now + 6 end},
    {Name = "multiplier nine", Multiplier = 1, Apply = function()
        attrs.ZyntraSpeedBoostUntil, attrs.ZyntraSpeedBoostMultiplier = now + 6, 9 end},
    {Name = "multiplier string", Multiplier = 1, Apply = function()
        attrs.ZyntraSpeedBoostUntil, attrs.ZyntraSpeedBoostMultiplier = now + 6, "x" end},
    {Name = "multiplier NaN", Multiplier = 1, Apply = function()
        attrs.ZyntraSpeedBoostUntil, attrs.ZyntraSpeedBoostMultiplier = now + 6, 0 / 0 end},
    {Name = "multiplier below one", Multiplier = 1, Apply = function()
        attrs.ZyntraSpeedBoostUntil, attrs.ZyntraSpeedBoostMultiplier = now + 6, 0.2 end},
    {Name = "multiplier at the cap", Multiplier = 1.5, Apply = function()
        attrs.ZyntraSpeedBoostUntil, attrs.ZyntraSpeedBoostMultiplier = now + 6, 1.5 end},
    {Name = "multiplier over the cap", Multiplier = 1, Apply = function()
        attrs.ZyntraSpeedBoostUntil, attrs.ZyntraSpeedBoostMultiplier = now + 6, 1.51 end},
}
for _, row in ipairs(rows) do
    for _, column in ipairs(columns) do
        reset()
        row.Apply()
        column.Apply()
        local staminaBefore = stamina
        local multiplier = (row.Boosts == false) and 1 or column.Multiplier
        local wanted = row.Speed * multiplier
        local label = row.Name .. " / " .. column.Name
        if row.Locked then hum.WalkSpeed = 0 end
        applySpeed()
        if row.Locked then
            -- The lock owns WalkSpeed; applySpeed may only refresh the target.
            same(hum.WalkSpeed, 0, label .. " leaves the locked WalkSpeed at zero")
        else
            near(hum.WalkSpeed, wanted, label .. " WalkSpeed")
        end
        near(charAttrs.Level2_DesiredWalkSpeed, wanted, label .. " restore target")
        same(stamina, staminaBefore, label .. " does not touch stamina")
    end
end

-- ------------------------------------------------------------- the two edges
reset()
sprinting = true
applySpeed()
near(hum.WalkSpeed, 26, "un-boosted sprint")
-- Start: the server writes the attributes and replication fires the change.
player:SetAttribute("ZyntraSpeedBoostMultiplier", 1.10)
player:SetAttribute("ZyntraSpeedBoostUntil", now + 6)
near(hum.WalkSpeed, 28.6, "the attribute change alone applies the boost")
same(boostActive, true, "the start edge is recorded")
hum.WalkSpeed = 999
heartbeatEdge()
same(hum.WalkSpeed, 999, "an already-applied boost does not reapply every frame")
-- End: nothing fires, the server clock simply passes the deadline.
now += 6.5
same(hum.WalkSpeed, 999, "expiry raises no event of its own")
heartbeatEdge()
near(hum.WalkSpeed, 26, "the first frame after expiry restores the sprint speed")
same(boostActive, false, "the end edge is recorded")
hum.WalkSpeed = 999
heartbeatEdge()
same(hum.WalkSpeed, 999, "expiry is handled once, not every frame afterwards")

for _, case in ipairs({{Name = "walk", Speed = 16}, {Name = "crouch", Speed = 8}}) do
    reset()
    if case.Name == "crouch" then crouching = true end
    player:SetAttribute("ZyntraSpeedBoostMultiplier", 1.10)
    player:SetAttribute("ZyntraSpeedBoostUntil", now + 6)
    near(hum.WalkSpeed, case.Speed * 1.10, case.Name .. " boosts on the attribute change")
    now += 6.001
    heartbeatEdge()
    near(hum.WalkSpeed, case.Speed, case.Name .. " is restored exactly, not approximately")
end

-- A boost that begins while the body is locked must not write WalkSpeed, and
-- must still leave the lock the boosted number to restore to.
reset()
attrs.Level3_Hiding = true
hum.WalkSpeed = 0
player:SetAttribute("ZyntraSpeedBoostMultiplier", 1.10)
player:SetAttribute("ZyntraSpeedBoostUntil", now + 6)
same(hum.WalkSpeed, 0, "a boost cannot break a hiding lock")
near(charAttrs.Level2_DesiredWalkSpeed, 17.6, "the lock's restore target carries the boost")
now += 7
heartbeatEdge()
same(hum.WalkSpeed, 0, "expiry cannot break a hiding lock either")
near(charAttrs.Level2_DesiredWalkSpeed, 16, "expiry restores the lock's target")

-- The lobby is a separate branch and takes no boost at all, however stale the
-- attributes are when a round ends underneath a live potion.
reset()
attrs.ZyntraSpeedBoostUntil, attrs.ZyntraSpeedBoostMultiplier = now + 600, 1.10
attrs.InRound = false
sprinting = true
applySpeed()
near(hum.WalkSpeed, 26, "a stale boost cannot speed up the lobby")
near(charAttrs.Level2_DesiredWalkSpeed, 26, "the lobby restore target is unboosted")
same(speedBoost(), 1, "speedBoost refuses to answer out of a round")

-- Every hostile chase threshold this boost must stay under.
reset()
attrs.ZyntraSpeedBoostUntil, attrs.ZyntraSpeedBoostMultiplier = now + 6, 1.10
applySpeed()
assert(hum.WalkSpeed < 22, "boosted walk stays under the SoundController running threshold")
assert(hum.WalkSpeed < 24, "boosted walk stays under the Mall Manager sprint hearing range")
checks += 2
crouching = true
applySpeed()
assert(hum.WalkSpeed <= 11, "boosted crouch stays inside the quiet band")
checks += 1
crouching = false
sprinting = true
applySpeed()
assert(hum.WalkSpeed < 31.2, "boosted sprint stays under the blackout Mall Manager")
assert(hum.WalkSpeed > 27.2, "boosted sprint DOES out-pace the Level 1 entity")
checks += 2

print("Speed potion: " .. checks .. " checks passed (real NoiseReporter movement blocks, offline Luau)")
'''


def main():
    binary = os.environ.get("LUAU_BIN") or shutil.which("luau")
    if not binary:
        raise SystemExit("Set LUAU_BIN; no tests executed.")
    with tempfile.TemporaryDirectory(prefix="speed-potion-") as directory:
        path = Path(directory) / "speed_potion_test.luau"
        path.write_text("\n".join(FIXTURE) + TESTS, encoding="utf-8")
        subprocess.run([binary, str(path)], check=True, timeout=30)


if __name__ == "__main__":
    main()
