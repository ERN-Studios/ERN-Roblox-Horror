-- EntityShakeController  (v1)
-- PASTE INTO: StarterPlayer → StarterPlayerScripts → Insert Object → LocalScript → rename to "EntityShakeController"
--
-- Camera feel, all in one place (this script owns Humanoid.CameraOffset):
--   • subtle head-bob while YOU walk, slightly faster + stronger while you run
--   • while the Entity LURKS nearby, a faint tremble that grows as it closes in
--   • while it CHASES, a heavier shake that PUNCHES on every footstep
-- The footstep punch is timed by STOMP_INTERVAL — set that to the seconds
-- between the run animation's/sound's stomps so the shake lands with them.
--
-- Reads workspace attribute "EntityState" (published by EntityAI) + the Entity's
-- live position. Shakes via Humanoid.CameraOffset, so it works in first person
-- and plays nice with the flashlight.

local Players = game:GetService("Players")
local RunService = game:GetService("RunService")
local player = Players.LocalPlayer

-- ── tuning ────────────────────────────────────────────────
local LURK_RANGE     = 42    -- within this (idle/roaming) a faint shake starts
local LURK_MAX       = 0.18  -- max shake (studs) at point-blank while it lurks
local CHASE_RANGE    = 75    -- within this while chasing you feel its footfalls
local CHASE_RUMBLE   = 0.10  -- constant low rumble while chased (scaled by nearness)
local STOMP_INTERVAL = 0.5   -- SECONDS BETWEEN FOOTSTEP STOMPS — match to the run sound/anim
local STOMP_STRENGTH = 0.7   -- camera kick per stomp (studs) at point-blank
local DECAY          = 9     -- how fast a stomp kick fades

-- your own MOVEMENT head-bob (subtle, smooth; a little quicker + stronger when
-- running). Lives here because this script owns Humanoid.CameraOffset — a second
-- writer would fight it.
local BOB_WALK_AMP  = 0.05   -- bob size (studs) while walking — keep it subtle
local BOB_RUN_AMP   = 0.09   -- bob size while sprinting (slightly stronger)
local BOB_WALK_FREQ = 6      -- bob pace while walking (rad/s)
local BOB_RUN_FREQ  = 9.5    -- bob pace while sprinting (slightly faster)
local BOB_RUN_WS    = 22     -- WalkSpeed at/above which you count as running
local BOB_SMOOTH    = 6      -- how fast the bob eases in / out (start, stop, gait change)
-- ──────────────────────────────────────────────────────────

local impulse = 0     -- decaying footstep-kick amount
local stompTimer = 0
local bobT = 0        -- bob phase
local bobAmp = 0      -- eased bob amplitude (0 when standing)

local function humanoidNow()
	local char = player.Character
	return char and char:FindFirstChildOfClass("Humanoid"), char
end

RunService.RenderStepped:Connect(function(dt)
	local hum, char = humanoidNow()
	if not hum then return end

	local cam = workspace.CurrentCamera
	local entity = workspace:FindFirstChild("Entity")
	local eroot = entity and entity:FindFirstChild("HumanoidRootPart")
	local myRoot = char and char:FindFirstChild("HumanoidRootPart")

	local ambient = 0
	if cam and eroot and myRoot and hum.Health > 0 then
		local dist = (eroot.Position - myRoot.Position).Magnitude
		local state = workspace:GetAttribute("EntityState")
		if state == "CHASE" or state == "TRACK" then -- TRACK = chasing you blind, still fast
			if dist < CHASE_RANGE then
				local prox = 1 - dist / CHASE_RANGE
				ambient = prox * CHASE_RUMBLE
				stompTimer += dt
				if stompTimer >= STOMP_INTERVAL then
					stompTimer -= STOMP_INTERVAL
					impulse = math.min(1, impulse + prox) -- footstep punch
				end
			else
				stompTimer = 0
			end
		else
			stompTimer = 0
			if dist < LURK_RANGE then
				ambient = (1 - dist / LURK_RANGE) * LURK_MAX
			end
		end
	end

	impulse = math.max(0, impulse - DECAY * dt)

	-- your own movement head-bob: a smooth figure-eight (side sway + double-time
	-- vertical), eased in and out so starting/stopping never snaps
	local bobTargetAmp, bobFreq = 0, BOB_WALK_FREQ
	if myRoot and hum.Health > 0 then
		local vel = myRoot.AssemblyLinearVelocity
		local flat = Vector3.new(vel.X, 0, vel.Z).Magnitude
		if flat > 2 and hum.WalkSpeed > 0.1 then
			local running = hum.WalkSpeed >= BOB_RUN_WS
			bobTargetAmp = running and BOB_RUN_AMP or BOB_WALK_AMP
			bobFreq = running and BOB_RUN_FREQ or BOB_WALK_FREQ
		end
	end
	bobAmp = bobAmp + (bobTargetAmp - bobAmp) * math.clamp(dt * BOB_SMOOTH, 0, 1)
	if bobAmp > 0.002 then bobT += dt * bobFreq end
	local bob = Vector3.new(
		math.sin(bobT) * bobAmp * 0.8,      -- gentle side-to-side sway
		math.sin(bobT * 2) * bobAmp,        -- vertical bounce, one per step
		0)

	-- entity shake on top of the bob
	local amp = ambient + impulse * STOMP_STRENGTH
	local target = bob
	if amp >= 0.001 then
		target = bob + Vector3.new(
			(math.random() * 2 - 1) * amp,
			-- a stomp also dips the view downward a touch, like a heavy footfall
			(math.random() * 2 - 1) * amp - impulse * STOMP_STRENGTH * 0.5,
			(math.random() * 2 - 1) * amp)
	end

	if target.Magnitude < 0.001 and hum.CameraOffset.Magnitude < 0.001 then
		hum.CameraOffset = Vector3.zero
		return
	end
	-- snappy while shaking (the jolt IS the effect), silky for pure bob
	local alpha = (amp >= 0.001) and 0.6 or math.clamp(dt * 14, 0, 1)
	hum.CameraOffset = hum.CameraOffset:Lerp(target, alpha)
end)

-- clear any residual offset on respawn
player.CharacterAdded:Connect(function(char)
	local hum = char:WaitForChild("Humanoid")
	hum.CameraOffset = Vector3.zero
end)
