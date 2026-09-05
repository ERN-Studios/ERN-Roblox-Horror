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
local LURK_MAX       = 0.34  -- max shake (studs) at point-blank while it lurks
local LURK_CURVE     = 1.6   -- proximity exponent: barely-there at the range edge, strong up close
local CHASE_RANGE    = 75    -- within this while chasing you feel its footfalls
local CHASE_RUMBLE   = 0.26  -- rumble while it hunts, scaled hard by nearness
local CHASE_CURVE    = 1.4   -- proximity exponent for the chase rumble
local CHASE_TARGET_MULT = 2.0 -- extra multiplier when it is chasing YOU specifically
local STOMP_CHASE_INTERVAL = 0.34 -- matches the alternating chase-step audio
local STOMP_TRACK_INTERVAL = 0.53 -- TRACK uses the fast walk cycle/audio
local STOMP_STRENGTH = 0.85  -- camera kick per stomp (studs) at point-blank
local DECAY          = 9     -- how fast a stomp kick fades
local ALERT_SHAKE_DURATION = 1.25 -- first-sight howl camera shock
local ALERT_SHAKE_STRENGTH = 0.48
local ALERT_SHAKE_ATTACK   = 0.08

-- your own MOVEMENT head-bob (subtle, smooth; a little quicker + stronger when
-- running). Lives here because this script owns Humanoid.CameraOffset — a second
-- writer would fight it.
local BOB_WALK_AMP  = 0.05   -- bob size (studs) while walking — keep it subtle
local BOB_RUN_AMP   = 0.09   -- bob size while sprinting (slightly stronger)
local BOB_CROUCH_AMP = 0.025 -- restrained movement while the body stays tucked
local BOB_WALK_FREQ = 6      -- bob pace while walking (rad/s)
local BOB_RUN_FREQ  = 9.5    -- bob pace while sprinting (slightly faster)
local BOB_CROUCH_FREQ = 4.5
local BOB_RUN_WS    = 22     -- WalkSpeed at/above which you count as running
local BOB_SMOOTH    = 6      -- how fast the bob eases in / out (start, stop, gait change)
-- Level 3 Table Hiding Client owns the exact world-space under-table POV.
-- Keep this writer neutral while hidden; it still suppresses locomotion bob.
local HIDDEN_CAMERA_OFFSET = Vector3.zero
-- Matches the canonical crouch pose's Root translation. EntityShakeController
-- remains the sole CameraOffset writer, so normal crouch lowers smoothly without
-- fighting bob/shake or the Level 3 world-space hide camera.
local CROUCH_CAMERA_OFFSET = Vector3.new(0, -0.92, 0.12)
-- ──────────────────────────────────────────────────────────

local impulse = 0     -- decaying footstep-kick amount
local stompTimer = 0
local bobT = 0        -- bob phase
local bobAmp = 0      -- eased bob amplitude (0 when standing)
local alertElapsed = math.huge

local function humanoidNow()
	local char = player.Character
	return char and char:FindFirstChildOfClass("Humanoid"), char
end

-- EntityAI increments this attribute only on the player it has just noticed.
-- This avoids shaking bystanders who merely hear the same positional howl.
player:GetAttributeChangedSignal("Level1EntityAlertSerial"):Connect(function()
	local hum = humanoidNow()
	if workspace:GetAttribute("SelectedLevel") ~= 1
		or workspace:GetAttribute("RoundActive") ~= true
		or player:GetAttribute("InRound") ~= true
		or player:GetAttribute("ReduceCameraShake") == true
		or not hum or hum.Health <= 0 then
		return
	end
	alertElapsed = 0
end)

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
				-- progressive proximity rumble, and the actual chase TARGET gets
				-- it doubled on top — being hunted should feel violent up close
				local prox = 1 - dist / CHASE_RANGE
				local targeted = player:GetAttribute("BeingChased") == true
				ambient = (prox ^ CHASE_CURVE) * CHASE_RUMBLE
					* (targeted and CHASE_TARGET_MULT or 1)
				stompTimer += dt
				local stompInterval = state == "CHASE"
					and STOMP_CHASE_INTERVAL or STOMP_TRACK_INTERVAL
				if stompTimer >= stompInterval then
					stompTimer -= stompInterval
					-- footstep punch — full force for the target, softer for bystanders
					impulse = math.min(1, impulse + prox * (targeted and 1 or 0.65))
				end
			else
				stompTimer = 0
			end
		else
			stompTimer = 0
			if dist < LURK_RANGE then
				-- progressive tremble: grows steadily as it closes the distance
				ambient = ((1 - dist / LURK_RANGE) ^ LURK_CURVE) * LURK_MAX
			end
		end
	end

	impulse = math.max(0, impulse - DECAY * dt)

	-- your own movement head-bob: a smooth figure-eight (side sway + double-time
	-- vertical), eased in and out so starting/stopping never snaps
	local isHidden = player:GetAttribute("Level3_Hiding") == true
	local isCrouching = not isHidden and player:GetAttribute("InRound") == true
		and workspace:GetAttribute("RoundActive") == true
		-- This is the owner's camera, so prediction is the visual truth in both
		-- directions. The server attribute is for remote observers and AI.
		and player:GetAttribute("LocalCrouching") == true
		and char:GetAttribute("Level2_ForcedSliding") ~= true
		and char:GetAttribute("Level2_RagdollServerActive") ~= true
	local bobTargetAmp, bobFreq = 0, BOB_WALK_FREQ
	if not isHidden and myRoot and hum.Health > 0 then
		local vel = myRoot.AssemblyLinearVelocity
		local flat = Vector3.new(vel.X, 0, vel.Z).Magnitude
		if flat > 2 and hum.WalkSpeed > 0.1 then
			local running = hum.WalkSpeed >= BOB_RUN_WS
			if isCrouching then
				bobTargetAmp, bobFreq = BOB_CROUCH_AMP, BOB_CROUCH_FREQ
			else
				bobTargetAmp = running and BOB_RUN_AMP or BOB_WALK_AMP
				bobFreq = running and BOB_RUN_FREQ or BOB_WALK_FREQ
			end
		end
	end
	bobAmp = bobAmp + (bobTargetAmp - bobAmp) * math.clamp(dt * BOB_SMOOTH, 0, 1)
	if bobAmp > 0.002 then bobT += dt * bobFreq end
	local bob = Vector3.new(
		math.sin(bobT) * bobAmp * 0.8,      -- gentle side-to-side sway
		math.sin(bobT * 2) * bobAmp,        -- vertical bounce, one per step
		0)

	-- Target-only first-sight howl shock. It attacks quickly and decays before
	-- chase stomps take over, including when the Entity spots you beyond LURK_RANGE.
	local alertAmp = 0
	if workspace:GetAttribute("SelectedLevel") ~= 1
		or workspace:GetAttribute("RoundActive") ~= true
		or player:GetAttribute("InRound") ~= true
		or player:GetAttribute("ReduceCameraShake") == true
		or hum.Health <= 0 then
		alertElapsed = math.huge
	elseif alertElapsed < ALERT_SHAKE_DURATION then
		alertElapsed += dt
		local attack = math.clamp(alertElapsed / ALERT_SHAKE_ATTACK, 0, 1)
		local release = math.max(1 - alertElapsed / ALERT_SHAKE_DURATION, 0) ^ 1.7
		alertAmp = ALERT_SHAKE_STRENGTH * attack * release
	end

	-- entity shake on top of the bob
	--
	-- ReduceCameraShake covers ALL of it, and this is the one place that can say
	-- so. The flag used to be read in exactly two places -- the alert listener
	-- above and the alertAmp branch -- and both of them only suppressed the
	-- first-sight howl shock, so a player who had asked for no camera shake still
	-- got the proximity tremble (LURK_MAX), the chase rumble (CHASE_RUMBLE,
	-- doubled while targeted) and the per-footstep punch (STOMP_STRENGTH, every
	-- STOMP_CHASE_INTERVAL while chased) at full strength: essentially all of the
	-- motion the setting names. Scaling the SUM is what makes that impossible to
	-- get wrong again -- a future shake source added above this line is covered
	-- by construction rather than by remembering to check the flag.
	--
	-- Head-bob and the crouch/hide offsets are deliberately NOT scaled: they are
	-- pose, not shake, and removing them would change where the camera sits
	-- rather than how much it jitters. The downward stomp dip below rides inside
	-- the same `amp >= 0.001` branch, so it goes with the shake.
	local shakeScale = if player:GetAttribute("ReduceCameraShake") == true then 0 else 1
	local amp = (ambient + impulse * STOMP_STRENGTH + alertAmp) * shakeScale
	local baseOffset = if isHidden then HIDDEN_CAMERA_OFFSET
		elseif isCrouching then CROUCH_CAMERA_OFFSET else Vector3.zero
	local target = baseOffset + bob
	if amp >= 0.001 then
		target = baseOffset + bob + Vector3.new(
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
	alertElapsed = math.huge
	local hum = char:WaitForChild("Humanoid")
	hum.CameraOffset = Vector3.zero
end)
