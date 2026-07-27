-- SoundController  (v2 — ambience, proximity breathing, thump footsteps)
-- PASTE INTO: StarterPlayer → StarterPlayerScripts → Insert Object → LocalScript → rename to "SoundController"
-- REPLACES the old SoundController — paste over the old contents.
--
-- ONE PLACE FOR EVERY SOUND ID. Paste your own audio asset IDs into the slots
-- below; any left "" is silent. This script owns ALL of the game's audio —
-- ambience, breathing, footsteps, alert siren, the Entity's growl, and the
-- death scream — so you never have to hunt across scripts for a sound.
-- Footsteps play as discrete THUMPS on a step cadence, so a single carpet-thump
-- sound works naturally for both walking and running.

local Players = game:GetService("Players")
local RunService = game:GetService("RunService")
local SoundService = game:GetService("SoundService")
local TweenService = game:GetService("TweenService")
local RS = game:GetService("ReplicatedStorage")

-- ── audio slots (every sound in the game) ─────────────────
local AMBIENCE_SOUND  = "rbxassetid://92576512092725" -- constant background drone/hum (2D, always playing)
local BREATHING_SOUND = "" -- YOUR OWN winded breathing (2D) — fades in below 50% stamina
local FOOTSTEP_WALK   = "" -- one thump per step while walking (e.g. soft carpet step)
local FOOTSTEP_RUN    = "" -- one thump per step while running (heavier carpet thump)
local ALERT_SOUND     = "" -- plays while the maze is in ALERT (red lights) mode
local ELEVATOR_SOUND  = "rbxassetid://72303878759145" -- the elevator ride, plays through the pre-round intro (2D)
local ENTITY_SOUND    = "rbxassetid://103206085469231" -- looping growl/drone emitted BY the Entity (positional)
local DEATH_SOUND     = "rbxassetid://113822157484898" -- the scream ALIVE players hear when someone dies (positional at the kill)
local JUMPSCARE_SOUND = "" -- the DYING player's OWN jumpscare sound (2D, only they hear it)
local YELL_SOUND      = "rbxassetid://92808749593079" -- the Entity's roar when it shoves you off a pit beam (positional)
local LUNGE_SOUND     = "" -- plays as it winds up a lunge (telegraph, positional)
local ENTITY_STEP_WALK = "rbxassetid://99809246525734" -- the Entity's footstep thump while walking (positional)
local ENTITY_STEP_RUN  = "" -- the Entity's footstep thump while running/chasing (positional)
-- idle vocalisations played at random while the Entity just roams (positional).
-- Fill any of the 3 — it works with just one; empty slots are skipped.
local IDLE_SOUNDS     = { "", "", "" }
local CHASE_SOUND     = "rbxassetid://72818169474421" -- loops while the Entity is actively CHASING you (positional)

-- ── tuning ────────────────────────────────────────────────
local AMBIENCE_VOLUME   = 0.4
local ELEVATOR_VOLUME   = 0.8  -- the elevator door-open / arrival sound (2D)
local BREATH_START      = 0.5  -- stamina fraction at which winded breathing fades IN
local BREATH_MAX_VOLUME = 1.0  -- volume at 0 stamina (loudest gasping)
local BREATH_SMOOTH     = 3    -- how fast the breathing volume eases toward target

local WALK_VOLUME   = 0.4
local RUN_VOLUME    = 0.7
local WALK_INTERVAL = 0.50    -- seconds between walking thumps
local RUN_INTERVAL  = 0.30    -- seconds between running thumps

local ENTITY_VOLUME    = 1.0  -- the Entity's growl (positional)
local DEATH_VOLUME     = 2     -- the death scream others hear (positional)
local JUMPSCARE_VOLUME = 2     -- the dying player's own jumpscare sound (2D)
local YELL_VOLUME      = 1     -- the Entity's roar (positional)
local IDLE_VOLUME      = 0.7   -- the Entity's idle vocalisations (positional)
local IDLE_MIN_GAP     = 6     -- min seconds between idle vocalisations
local IDLE_MAX_GAP     = 14    -- max seconds between them
local CHASE_VOLUME     = 0.85  -- the Entity's chase sound (positional, looping)
local CHASE_FADE       = 0.6   -- seconds to fade the chase loop in / out
local TRACK_FADE       = 5     -- seconds to SLOWLY fade the chase music once it loses
                               -- sight and is only tracking blindly (match TRACK_TIME)
local SPOT_VOLUME      = 1      -- the "spotted you!" sting (reuses YELL_SOUND) fired as a chase begins
local LUNGE_VOLUME     = 1     -- the lunge telegraph (positional)
local STEP_WALK_VOLUME = 0.5   -- entity walk thump
local STEP_RUN_VOLUME  = 0.8   -- entity run thump
local STEP_WALK_INT    = 0.55  -- seconds between entity walk thumps
local STEP_RUN_INT     = 0.32  -- seconds between entity run thumps
local STEP_RUN_SPEED   = 20    -- entity speed at/above which it uses the run thump
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

-- ambience starts SILENT and fades in when the round begins — during the
-- elevator ride you hear the elevator, not the maze. `ambienceTarget` is set by
-- the round events below and eased toward in the main Heartbeat.
local AMBIENCE_FADE = 4      -- ~seconds to ease the ambience in / out
local ambienceTarget = 0
local ambience = makeLoop(AMBIENCE_SOUND, 0)
local breathing = makeLoop(BREATHING_SOUND, 0)
-- PRELOAD the looping sounds before playing them. A loop that isn't fully loaded
-- re-buffers at the loop point, which is the "slight stop" you hear each cycle;
-- preloading makes the ambience loop seamlessly.
task.spawn(function()
	local ContentProvider = game:GetService("ContentProvider")
	local toLoad = {}
	if AMBIENCE_SOUND ~= "" then table.insert(toLoad, ambience) end
	if BREATHING_SOUND ~= "" then table.insert(toLoad, breathing) end
	if #toLoad > 0 then pcall(function() ContentProvider:PreloadAsync(toLoad) end) end
	if AMBIENCE_SOUND ~= "" then ambience:Play() end
	if BREATHING_SOUND ~= "" then breathing:Play() end
end)

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

-- the Entity's own growl: a looping POSITIONAL sound on the entity, so you hear
-- which direction it's coming from (attached client-side from here)
task.spawn(function()
	if ENTITY_SOUND == "" then return end
	local entity = workspace:WaitForChild("Entity", 60)
	local er = entity and entity:WaitForChild("HumanoidRootPart", 15)
	if not er then return end
	local s = Instance.new("Sound")
	s.Name = "EntitySound"
	s.Looped = true
	s.Volume = ENTITY_VOLUME
	s.SoundId = ENTITY_SOUND
	s.RollOffMode = Enum.RollOffMode.InverseTapered
	s.RollOffMinDistance = 8
	s.RollOffMaxDistance = 140
	s.Parent = er
	s:Play()
end)

-- death audio: GameManager fires RoundStatus "death" with the victim + kill spot.
--   • if YOU died → your OWN jumpscare sound (2D, personal)
--   • if someone ELSE died → the death scream, POSITIONAL at the kill, and only
--     if you're still ALIVE (dead spectators don't hear it)
local roundStatus = RS:WaitForChild("Remotes"):WaitForChild("RoundStatus")
roundStatus.OnClientEvent:Connect(function(ev, name, pos)
	if ev ~= "death" then return end

	if name == player.Name then
		if JUMPSCARE_SOUND == "" then return end
		local s = Instance.new("Sound")
		s.SoundId = JUMPSCARE_SOUND
		s.Volume = JUMPSCARE_VOLUME
		s.Parent = SoundService -- 2D: only you hear it
		s:Play()
		task.delay(6, function() if s then s:Destroy() end end)
		return
	end

	if DEATH_SOUND == "" or typeof(pos) ~= "Vector3" then return end
	local hum = player.Character and player.Character:FindFirstChildOfClass("Humanoid")
	if not (hum and hum.Health > 0) then return end -- only the living hear the scream
	local holder = Instance.new("Part")
	holder.Anchored = true
	holder.CanCollide = false
	holder.CanQuery = false
	holder.Transparency = 1
	holder.Size = Vector3.new(1, 1, 1)
	holder.CFrame = CFrame.new(pos)
	holder.Parent = workspace
	local s = Instance.new("Sound")
	s.SoundId = DEATH_SOUND
	s.Volume = DEATH_VOLUME
	s.RollOffMode = Enum.RollOffMode.InverseTapered
	s.RollOffMinDistance = 12   -- full volume near the kill
	s.RollOffMaxDistance = 260  -- still audible far off, just quiet
	s.Parent = holder
	s:Play()
	s.Ended:Connect(function() holder:Destroy() end)
	task.delay(8, function() if holder then holder:Destroy() end end)
end)

-- the elevator sound: a ONE-SHOT that starts with the countdown and plays right
-- through — the doors opening does NOT cut it (make its length match
-- ELEVATOR_TIME, ~19s). It also drives the ambience fade: the maze ambience is
-- silent through the elevator ride and fades in when the round actually starts.
local elevatorSound = Instance.new("Sound")
elevatorSound.Parent = SoundService
roundStatus.OnClientEvent:Connect(function(ev)
	if ev == "elevator" then
		ambienceTarget = 0 -- silent during the ride
		if ELEVATOR_SOUND ~= "" and not elevatorSound.IsPlaying then
			elevatorSound.SoundId = ELEVATOR_SOUND
			elevatorSound.Volume = ELEVATOR_VOLUME
			elevatorSound:Play()
		end
	elseif ev == "start" then
		ambienceTarget = AMBIENCE_VOLUME -- doors open → fade the maze in (elevator keeps playing)
	elseif ev == "win" or ev == "lose" or ev == "waiting" then
		ambienceTarget = 0
		elevatorSound:Stop() -- round over / reset (doors opening does NOT stop it)
	end
end)

-- the Entity's yell/roar: EntityAI bumps the EntityYell attribute each time it
-- shoves a pit player, and we play the roar POSITIONALLY at the entity
if YELL_SOUND ~= "" then
	workspace:GetAttributeChangedSignal("EntityYell"):Connect(function()
		local entity = workspace:FindFirstChild("Entity")
		local er = entity and entity:FindFirstChild("HumanoidRootPart")
		if not er then return end
		local s = Instance.new("Sound")
		s.SoundId = YELL_SOUND
		s.Volume = YELL_VOLUME
		s.RollOffMode = Enum.RollOffMode.InverseTapered
		s.RollOffMinDistance = 10
		s.RollOffMaxDistance = 200
		s.Parent = er
		s:Play()
		s.Ended:Connect(function() s:Destroy() end)
		task.delay(8, function() if s then s:Destroy() end end)
	end)
end

-- the Entity's idle vocalisations: while it's just roaming (EntityState is not
-- CHASE), play a random idle sound POSITIONALLY at the entity every so often
task.spawn(function()
	while true do
		task.wait(math.random(IDLE_MIN_GAP, IDLE_MAX_GAP))
		local ids = {}
		for _, id in ipairs(IDLE_SOUNDS) do
			if id ~= "" then table.insert(ids, id) end
		end
		if #ids == 0 then continue end
		local st = workspace:GetAttribute("EntityState")
		if st == "CHASE" or st == "YELL" or st == "TRACK" then continue end
		local entity = workspace:FindFirstChild("Entity")
		local er = entity and entity:FindFirstChild("HumanoidRootPart")
		if not er then continue end
		local s = Instance.new("Sound")
		s.SoundId = ids[math.random(#ids)]
		s.Volume = IDLE_VOLUME
		s.RollOffMode = Enum.RollOffMode.InverseTapered
		s.RollOffMinDistance = 10
		s.RollOffMaxDistance = 160
		s.Parent = er
		s:Play()
		s.Ended:Connect(function() s:Destroy() end)
		task.delay(12, function() if s then s:Destroy() end end)
	end
end)

-- the chase audio: when the Entity SPOTS you (EntityState → CHASE) it first
-- plays a "spotted you!" sting — the same sound as the yell — then the chase
-- loop fades in beneath it. Leaving CHASE fades the loop back out. Both fade
-- rather than snapping on/off.
task.spawn(function()
	local entity = workspace:WaitForChild("Entity", 60)
	local er = entity and entity:WaitForChild("HumanoidRootPart", 15)
	if not er then return end

	local chase
	if CHASE_SOUND ~= "" then
		chase = Instance.new("Sound")
		chase.Name = "ChaseSound"
		chase.Looped = true
		chase.Volume = 0
		chase.SoundId = CHASE_SOUND
		chase.RollOffMode = Enum.RollOffMode.InverseTapered
		chase.RollOffMinDistance = 10
		chase.RollOffMaxDistance = 200
		chase.Parent = er
	end

	local prevEngaged = false -- was CHASE or TRACK last time
	local lastSpot = -999     -- cooldown so rapid re-acquires don't spam the sting
	local fadeTween
	local function fadeChase(target, dur)
		if not chase then return end
		if not chase.IsPlaying then chase:Play() end
		if fadeTween then fadeTween:Cancel() end
		fadeTween = TweenService:Create(chase, TweenInfo.new(dur, Enum.EasingStyle.Linear), { Volume = target })
		fadeTween:Play()
	end

	local function onState()
		local st = workspace:GetAttribute("EntityState")
		local chasing = (st == "CHASE")   -- actively sees you
		local tracking = (st == "TRACK")  -- lost sight, hunting your last live position

		if chasing then
			-- freshly spotted (wasn't already engaged) → the "spotted you" sting
			if not prevEngaged and YELL_SOUND ~= "" and (os.clock() - lastSpot) > 4 then
				lastSpot = os.clock()
				local spot = Instance.new("Sound")
				spot.SoundId = YELL_SOUND
				spot.Volume = 0
				spot.RollOffMode = Enum.RollOffMode.InverseTapered
				spot.RollOffMinDistance = 10
				spot.RollOffMaxDistance = 200
				spot.Parent = er
				spot:Play()
				TweenService:Create(spot, TweenInfo.new(0.25), { Volume = SPOT_VOLUME }):Play()
				spot.Ended:Connect(function() spot:Destroy() end)
				task.delay(8, function() if spot then spot:Destroy() end end)
			end
			fadeChase(CHASE_VOLUME, CHASE_FADE) -- rise to (or hold) full

		elseif tracking then
			-- lost sight but still coming → SLOWLY fade the music over the window;
			-- if it re-spots you, the CHASE branch snaps it back up
			fadeChase(0, TRACK_FADE)

		elseif chase and chase.IsPlaying then
			-- fully lost → finish the fade out and stop
			fadeChase(0, CHASE_FADE)
			task.delay(CHASE_FADE + 0.1, function()
				local s = workspace:GetAttribute("EntityState")
				if s ~= "CHASE" and s ~= "TRACK" then chase:Stop() end
			end)
		end
		prevEngaged = chasing or tracking
	end
	workspace:GetAttributeChangedSignal("EntityState"):Connect(onState)
	onState()
end)

-- the lunge telegraph: EntityAI bumps EntityLunge when it winds up a pounce, and
-- we play the cue POSITIONALLY at the entity (fires during the wind-up)
if LUNGE_SOUND ~= "" then
	workspace:GetAttributeChangedSignal("EntityLunge"):Connect(function()
		local entity = workspace:FindFirstChild("Entity")
		local er = entity and entity:FindFirstChild("HumanoidRootPart")
		if not er then return end
		local s = Instance.new("Sound")
		s.SoundId = LUNGE_SOUND
		s.Volume = LUNGE_VOLUME
		s.RollOffMode = Enum.RollOffMode.InverseTapered
		s.RollOffMinDistance = 10
		s.RollOffMaxDistance = 200
		s.Parent = er
		s:Play()
		s.Ended:Connect(function() s:Destroy() end)
		task.delay(6, function() if s then s:Destroy() end end)
	end)
end

-- the Entity's own footstep thumps: measured from its velocity, positional at the
-- entity, on a cadence — walk thump when strolling, run thump when chasing
task.spawn(function()
	if ENTITY_STEP_WALK == "" and ENTITY_STEP_RUN == "" then return end
	local entity = workspace:WaitForChild("Entity", 60)
	local er = entity and entity:WaitForChild("HumanoidRootPart", 15)
	if not er then return end
	local step = Instance.new("Sound")
	step.Name = "EntityStep"
	step.RollOffMode = Enum.RollOffMode.InverseTapered
	step.RollOffMinDistance = 8
	step.RollOffMaxDistance = 140
	step.Parent = er
	local clock = 0
	local lastPos = er.Position
	RunService.Heartbeat:Connect(function(dt)
		-- measure ACTUAL translation, not AssemblyLinearVelocity — the chase code
		-- SETS the entity's velocity every frame, so when it's wedged against a
		-- wall the velocity reads high while it isn't really moving. Position
		-- delta is the truth: no real movement → no footstep thumps.
		local now = er.Position
		local moved = Vector3.new(now.X - lastPos.X, 0, now.Z - lastPos.Z).Magnitude
		lastPos = now
		local spd = (dt > 0) and (moved / dt) or 0
		if spd < 3 then clock = 999; return end -- standing still (or stuck): silent
		local run = spd >= STEP_RUN_SPEED
		local id = run and ENTITY_STEP_RUN or ENTITY_STEP_WALK
		local interval = run and STEP_RUN_INT or STEP_WALK_INT
		if id == "" then return end
		clock += dt
		if clock >= interval then
			clock = 0
			step.SoundId = id
			step.Volume = run and STEP_RUN_VOLUME or STEP_WALK_VOLUME
			step.PlaybackSpeed = 0.94 + math.random() * 0.12
			step:Play()
		end
	end)
end)

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
local breathingActive = false -- once winded, stays true until stamina is full again

RunService.Heartbeat:Connect(function(dt)
	local hum, root = aliveParts()

	-- YOUR winded breathing: fades in once stamina drops below BREATH_START and
	-- LINGERS (hysteresis) until stamina is back to full. Louder the lower it is.
	-- NoiseReporter publishes your stamina as the player attribute "Stamina" (0–1).
	if BREATHING_SOUND ~= "" then
		local frac = player:GetAttribute("Stamina")
		if typeof(frac) ~= "number" then frac = 1 end
		if frac < BREATH_START then
			breathingActive = true
		elseif frac >= 1 then
			breathingActive = false
		end
		local target = breathingActive and (math.clamp(1 - frac, 0, 1) * BREATH_MAX_VOLUME) or 0
		breathing.Volume = breathing.Volume
			+ (target - breathing.Volume) * math.clamp(dt * BREATH_SMOOTH, 0, 1)
	end

	-- maze ambience: eased toward its target (silent during the elevator ride,
	-- faded in when the round starts) — see the round-event handler above
	if AMBIENCE_SOUND ~= "" then
		ambience.Volume = ambience.Volume
			+ (ambienceTarget - ambience.Volume) * math.clamp(dt / AMBIENCE_FADE, 0, 1)
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
