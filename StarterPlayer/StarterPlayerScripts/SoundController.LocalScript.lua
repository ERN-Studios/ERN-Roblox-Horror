-- SoundController  (v2 — ambience, proximity breathing, thump footsteps)
-- PASTE INTO: StarterPlayer → StarterPlayerScripts → Insert Object → LocalScript → rename to "SoundController"
-- REPLACES the old SoundController — paste over the old contents.
--
-- Paste your own audio asset IDs into the slots below. Any left "" is silent.
-- Footsteps play as discrete THUMPS on a step cadence, so a single carpet-thump
-- sound works naturally for both walking and running.
-- (The Entity's own sound lives on the entity — see ENTITY_SOUND in EntityAI.)

local Players = game:GetService("Players")
local RunService = game:GetService("RunService")
local SoundService = game:GetService("SoundService")

-- ── audio slots ───────────────────────────────────────────
local AMBIENCE_SOUND  = "" -- constant background drone/hum (2D, always playing)
local BREATHING_SOUND = "" -- swells louder the closer the Entity is (2D, no direction)
local FOOTSTEP_WALK   = "" -- one thump per step while walking (e.g. soft carpet step)
local FOOTSTEP_RUN    = "" -- one thump per step while running (heavier carpet thump)
local ALERT_SOUND     = "" -- plays while the maze is in ALERT (red lights) mode

-- ── tuning ────────────────────────────────────────────────
local AMBIENCE_VOLUME   = 0.4
local BREATH_RANGE      = 45   -- studs; within this the breathing fades in
local BREATH_MAX_VOLUME = 1.0

local WALK_VOLUME   = 0.4
local RUN_VOLUME    = 0.7
local WALK_INTERVAL = 0.50    -- seconds between walking thumps
local RUN_INTERVAL  = 0.30    -- seconds between running thumps
-- ──────────────────────────────────────────────────────────

local player = Players.LocalPlayer

local function makeLoop(id, vol)
	local s = Instance.new("Sound")
	s.Looped = true
	s.Volume = vol
	if id ~= "" then s.SoundId = id end
	s.Parent = SoundService
	return s
end

local ambience = makeLoop(AMBIENCE_SOUND, AMBIENCE_VOLUME)
local breathing = makeLoop(BREATHING_SOUND, 0)
if AMBIENCE_SOUND ~= "" then ambience:Play() end
if BREATHING_SOUND ~= "" then breathing:Play() end

-- alert siren: plays whenever the maze enters ALERT (red pulsing) mode
local alert = makeLoop(ALERT_SOUND, 0.8)
local function refreshAlert()
	if ALERT_SOUND == "" then return end
	if workspace:GetAttribute("LightMode") == "ALERT" then
		if not alert.IsPlaying then alert:Play() end
	else
		alert:Stop()
	end
end
workspace:GetAttributeChangedSignal("LightMode"):Connect(refreshAlert)
refreshAlert()

-- single-shot footstep sound, re-triggered each step
local footstep = Instance.new("Sound")
footstep.Parent = SoundService

local function aliveParts()
	local char = player.Character
	if not char then return end
	local hum = char:FindFirstChildOfClass("Humanoid")
	local root = char:FindFirstChild("HumanoidRootPart")
	if hum and root and hum.Health > 0 then return hum, root end
end

local stepClock = 999 -- high so the first step fires immediately on moving

RunService.Heartbeat:Connect(function(dt)
	local hum, root = aliveParts()

	-- breathing swells as the Entity gets close (direction-less — you can't
	-- tell WHERE it is, just that it's near)
	if BREATHING_SOUND ~= "" then
		local vol = 0
		local entity = workspace:FindFirstChild("Entity")
		local er = entity and entity:FindFirstChild("HumanoidRootPart")
		if er and root then
			local d = (er.Position - root.Position).Magnitude
			vol = math.clamp(1 - d / BREATH_RANGE, 0, 1) * BREATH_MAX_VOLUME
		end
		breathing.Volume = vol
	end

	-- footstep thumps on a cadence
	if not (hum and root) then
		stepClock = 999
		return
	end
	local vel = root.AssemblyLinearVelocity
	local flat = Vector3.new(vel.X, 0, vel.Z).Magnitude
	local ws = hum.WalkSpeed

	if flat < 2 or ws <= 10 then
		-- standing still or crouching: silent
		stepClock = 999
		return
	end

	local run = ws >= 22
	local id = run and FOOTSTEP_RUN or FOOTSTEP_WALK
	local interval = run and RUN_INTERVAL or WALK_INTERVAL

	stepClock += dt
	if id ~= "" and stepClock >= interval then
		stepClock = 0
		footstep.SoundId = id
		footstep.Volume = run and RUN_VOLUME or WALK_VOLUME
		footstep.PlaybackSpeed = 0.94 + math.random() * 0.12 -- tiny variation
		footstep:Play()
	end
end)
