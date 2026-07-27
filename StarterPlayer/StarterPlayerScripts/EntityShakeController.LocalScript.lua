-- EntityShakeController  (v1)
-- PASTE INTO: StarterPlayer → StarterPlayerScripts → Insert Object → LocalScript → rename to "EntityShakeController"
--
-- Screen shake driven by the Entity:
--   • while it just LURKS nearby, a faint tremble that grows as it closes in
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
-- ──────────────────────────────────────────────────────────

local impulse = 0     -- decaying footstep-kick amount
local stompTimer = 0

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

	local amp = ambient + impulse * STOMP_STRENGTH
	if amp < 0.001 then
		hum.CameraOffset = hum.CameraOffset:Lerp(Vector3.zero, 0.25)
		return
	end
	local ox = (math.random() * 2 - 1) * amp
	local oz = (math.random() * 2 - 1) * amp
	-- a stomp also dips the view downward a touch, like a heavy footfall
	local oy = (math.random() * 2 - 1) * amp - impulse * STOMP_STRENGTH * 0.5
	hum.CameraOffset = hum.CameraOffset:Lerp(Vector3.new(ox, oy, oz), 0.6)
end)

-- clear any residual offset on respawn
player.CharacterAdded:Connect(function(char)
	local hum = char:WaitForChild("Humanoid")
	hum.CameraOffset = Vector3.zero
end)
