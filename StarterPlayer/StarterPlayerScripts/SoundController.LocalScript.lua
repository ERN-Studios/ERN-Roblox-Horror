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
local CollectionService = game:GetService("CollectionService")

-- ── audio slots (every sound in the game) ─────────────────
local AMBIENCE_SOUND  = "rbxassetid://92576512092725" -- constant background drone/hum (2D, always playing)
local BREATHING_SOUND = "rbxassetid://74603278311777" -- YOUR OWN winded breathing (2D) — fades in below 50% stamina
local FOOTSTEP_WALK   = "rbxassetid://108141977175862" -- walking loop (the slower-cadence clip)
local FOOTSTEP_RUN    = "rbxassetid://133003345144597" -- running loop (the faster-cadence clip, natural pitch)
local ALERT_SOUND     = "rbxassetid://118863512220494" -- plays while the maze is in ALERT (red lights) mode
local ELEVATOR_SOUND  = "rbxassetid://72303878759145" -- the elevator ride, plays through the pre-round intro (2D)
local FLASHLIGHT_SOUND = "rbxassetid://79013410316837" -- click when YOU toggle the flashlight on/off (2D, only you hear it)
local ENTITY_SOUND    = "rbxassetid://103206085469231" -- looping growl/drone emitted BY the Entity (positional)
local DEATH_SOUND     = "rbxassetid://113822157484898" -- the scream ALIVE players hear when someone dies (positional at the kill)
local JUMPSCARE_SOUND = "rbxassetid://140233243543479" -- the DYING player's OWN jumpscare sound (2D, only they hear it)
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
local BREATH_START      = 0.5   -- stamina fraction at which winded breathing kicks in
local BREATH_VOLUME     = 0.12  -- peak breath volume (turned down more)
local BREATH_SMOOTH     = 2     -- how fast the breathing volume eases up / down
-- The clip is a long continuous breathing track (~11s), so it plays as a LOOP
-- and we just ride its VOLUME with how winded / scared you are — no chopping it
-- into breaths.
-- adrenaline breathing: when the Entity had you and LOSES you, you pant with fright
-- for a while, easing off. EntityAI bumps the local player's "PostChaseBreath"
-- attribute at the moment it gives up the chase.
local SCARE_BREATH_TIME = 9     -- seconds of scared panting after it loses you

local WALK_VOLUME   = 0.44   -- walking loop volume, slightly clearer over ambience
local RUN_VOLUME    = 0.68   -- running loop volume
local WALK_SPEEDUP  = 1.0    -- walk-loop playback speed (keep near 1.0 — speeding up pitches it high)
local RUN_SPEEDUP   = 1.0    -- run-loop playback speed (same: the clip's own cadence is the pace)
local RUN_WALKSPEED = 22     -- your WalkSpeed at/above which it counts as running
local FOOT_FADE     = 6      -- how fast the loop fades in as you move / out as you stop
local FLASHLIGHT_VOLUME = 0.6 -- the flashlight toggle click (2D)

local ENTITY_VOLUME    = 1.0  -- the Entity's growl (positional)
local DEATH_VOLUME     = 1.15  -- loud positional scream heard across the complete map
local JUMPSCARE_VOLUME = 0.82  -- the dying player's own impact sound (2D, intentionally restrained)
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
local STEP_WALK_VOLUME = 0.72  -- entity walk thump
local STEP_RUN_VOLUME  = 1.0   -- entity run thump
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
local breathing = makeLoop(BREATHING_SOUND, 0) -- long continuous loop, volume-ridden
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
	if BREATHING_SOUND ~= "" then breathing:Play() end -- loops silently; volume rides below
end)

-- alert siren: plays whenever the maze enters ALERT (red pulsing) mode
local alert = makeLoop(ALERT_SOUND, 1.4)
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

-- YOUR OWN jumpscare scream (2D): fired on the SAME Jumpscare remote as the
-- face image (JumpscareUI), so the sound and picture land together — no lag,
-- no double. Only the Entity firing this remote triggers it (pit falls don't).
local jumpscareRemote = RS:WaitForChild("Remotes"):WaitForChild("Jumpscare")
jumpscareRemote.OnClientEvent:Connect(function(eventName)
	-- Capture starts silently; the scream lands on the authored fatal impact.
	if eventName ~= "death" then return end
	if JUMPSCARE_SOUND == "" then return end
	local s = Instance.new("Sound")
	s.SoundId = JUMPSCARE_SOUND
	s.Volume = JUMPSCARE_VOLUME
	s.Parent = SoundService -- 2D: only you hear it
	s:Play()
	task.delay(6, function() if s then s:Destroy() end end)
end)

-- death audio: GameManager fires RoundStatus "death" with the victim + kill spot.
-- When someone ELSE dies → the death scream, POSITIONAL at the kill, and only if
-- you're still ALIVE (dead spectators don't hear it). Your own death is handled
-- by the Jumpscare remote above.
local roundStatus = RS:WaitForChild("Remotes"):WaitForChild("RoundStatus")
roundStatus.OnClientEvent:Connect(function(ev, name, pos)
	if ev ~= "death" then return end
	if name == player.Name then return end -- your own scare is on the Jumpscare remote

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
	s.PlaybackSpeed = 0.98 + math.random() * 0.04
	-- Level 1 spans hundreds of studs. Linear falloff keeps the scream directional
	-- while remaining clearly audible to survivors at the far side of the maze.
	s.RollOffMode = Enum.RollOffMode.Linear
	s.RollOffMinDistance = 60
	s.RollOffMaxDistance = 2200
	local eq = Instance.new("EqualizerSoundEffect")
	eq.HighGain = -3
	eq.MidGain = -1
	eq.LowGain = 0
	eq.Parent = s
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
		if st == "ALERT" or st == "CHASE" or st == "YELL" or st == "TRACK" then continue end
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
		local alerting = (st == "ALERT") -- howl already owns the spotted sound
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
		prevEngaged = alerting or chasing or tracking
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

-- FOOTSTEPS: the clips are continuous LOOPS (several seconds), not one-shot thumps
-- — so we run ONE looping sound that only plays while you MOVE and FADES OUT when
-- you stop (never a hard cut, never droning while you stand still). Walking uses
-- the walk loop; running swaps to the run loop at its natural pitch.
local steps = Instance.new("Sound")
steps.Looped = true
steps.Volume = 0
steps.Parent = SoundService
local curStepId = ""
if FOOTSTEP_WALK ~= "" then
	steps.SoundId = FOOTSTEP_WALK
	curStepId = FOOTSTEP_WALK
	steps:Play()
end

local function aliveParts()
	local char = player.Character
	if not char then return end
	local hum = char:FindFirstChildOfClass("Humanoid")
	local root = char:FindFirstChild("HumanoidRootPart")
	if hum and root and hum.Health > 0 then return hum, root end
end

local breathingActive = false -- once winded, stays true until stamina is full again
local breathI = 0     -- eased breathing intensity 0–1

-- adrenaline panting window: opened when EntityAI bumps our PostChaseBreath
-- attribute (it just lost sight of / gave up chasing us)
local scareUntil = 0
player:GetAttributeChangedSignal("PostChaseBreath"):Connect(function()
	scareUntil = os.clock() + SCARE_BREATH_TIME
end)

RunService.Heartbeat:Connect(function(dt)
	local hum, root = aliveParts()

	-- YOUR winded breathing: a continuous loop whose VOLUME rises the more winded
	-- (below BREATH_START stamina, lingering until full) or scared you are. Never
	-- breathes while DEAD / spectating (hum is nil unless you're alive).
	-- NoiseReporter publishes your stamina as the player attribute "Stamina" (0–1).
	if BREATHING_SOUND ~= "" then
		local targetI = 0
		if hum then
			local frac = player:GetAttribute("Stamina")
			if typeof(frac) ~= "number" then frac = 1 end
			if frac < BREATH_START then
				breathingActive = true
			elseif frac >= 1 then
				breathingActive = false
			end
			local staminaI = breathingActive and math.clamp(1 - frac, 0, 1) or 0
			-- scared panting after the Entity gives up on you: starts strong, eases to 0
			local scareI = 0
			if os.clock() < scareUntil then
				scareI = (scareUntil - os.clock()) / SCARE_BREATH_TIME
			end
			targetI = math.clamp(math.max(staminaI, scareI), 0, 1)
		end
		if not hum then
			breathI = 0 -- dead: silence immediately, no fade tail
		else
			breathI = breathI + (targetI - breathI) * math.clamp(dt * BREATH_SMOOTH, 0, 1)
		end
		breathing.Volume = breathI * BREATH_VOLUME
	end

	-- maze ambience: eased toward its target (silent during the elevator ride,
	-- faded in when the round starts) — see the round-event handler above
	if AMBIENCE_SOUND ~= "" then
		ambience.Volume = ambience.Volume
			+ (ambienceTarget - ambience.Volume) * math.clamp(dt / AMBIENCE_FADE, 0, 1)
	end

	-- footsteps: a looping track that only plays while you MOVE and fades out when
	-- you stop (so a long loop never drones on while standing, and never hard-cuts)
	local footTarget, footSpeed = 0, nil
	if hum and root and workspace:GetAttribute("SelectedLevel") ~= 2 then
		local vel = root.AssemblyLinearVelocity
		local flat = Vector3.new(vel.X, 0, vel.Z).Magnitude
		local ws = hum.WalkSpeed
		if flat >= 2 and ws > 10 then
			-- walk uses the walk loop; run uses its OWN clip at natural pitch
			-- (speeding a clip up to fake a run makes it chipmunk-high). Falls back
			-- to the walk loop sped up only if no run clip is set.
			local run = ws >= RUN_WALKSPEED
			local wantId = run and (FOOTSTEP_RUN ~= "" and FOOTSTEP_RUN or FOOTSTEP_WALK) or FOOTSTEP_WALK
			local wantSpeed = run and RUN_SPEEDUP or WALK_SPEEDUP
			local wantVol = run and RUN_VOLUME or WALK_VOLUME
			if wantId ~= "" then
				if curStepId ~= wantId then
					steps.SoundId = wantId; curStepId = wantId; steps:Play()
				end
				footTarget, footSpeed = wantVol, wantSpeed
			end
		end
	end
	if footSpeed then steps.PlaybackSpeed = footSpeed end -- hold last speed while fading out
	steps.Volume = steps.Volume + (footTarget - steps.Volume) * math.clamp(dt * FOOT_FADE, 0, 1)
end)

-- flashlight toggle click: reacts to the replicated FlashlightOn flag flipping.
-- Kept here (the audio hub) so every sound id lives in one place; the tiny
-- round-trip delay is inaudible for a click.
local function hookFlashlightClick(char)
	if FLASHLIGHT_SOUND == "" then return end
	task.spawn(function()
		local flag = char:WaitForChild("FlashlightOn", 10)
		if not flag then return end
		flag.Changed:Connect(function()
			local hum = char:FindFirstChildOfClass("Humanoid")
			if not (hum and hum.Health > 0) then return end -- no click on the forced-off at death
			local s = Instance.new("Sound")
			s.SoundId = FLASHLIGHT_SOUND
			s.Volume = FLASHLIGHT_VOLUME
			s.Parent = SoundService -- 2D: only you hear it
			s:Play()
			s.Ended:Connect(function() s:Destroy() end)
			task.delay(3, function() if s then s:Destroy() end end)
		end)
	end)
end
if player.Character then hookFlashlightClick(player.Character) end
player.CharacterAdded:Connect(hookFlashlightClick)

-- silence Roblox's built-in footstep loop so only our custom thumps play
local function muteDefaultSteps(char)
	task.spawn(function()
		local hrp = char:WaitForChild("HumanoidRootPart", 10)
		if not hrp then return end
		local running = hrp:WaitForChild("Running", 5)
		if not running then return end
		running.Volume = 0
		running:GetPropertyChangedSignal("Volume"):Connect(function()
			if running.Volume ~= 0 then running.Volume = 0 end -- keep it muted no matter what
		end)
	end)
end
if player.Character then muteDefaultSteps(player.Character) end
player.CharacterAdded:Connect(muteDefaultSteps)

-- ── LEVEL 2 SHALLOW-WATER + ENTITY AUDIO ───────────────────────────────────
-- The seven user-owned takes are resolved at runtime. Put their uploaded IDs on
-- ReplicatedStorage, Workspace, PoolroomsLevel2, ReplicatedStorage.Level2Audio,
-- or an individual entity model as Level2WadeStep1..7 / HeavyBootsSplash1..7.
-- This deliberately contains no placeholder asset IDs.
local LEVEL2_WADE_SPECS = {
	{ gain = 1.585, offset = 0.35 },
	{ gain = 0.841, offset = 0.30 },
	{ gain = 1.000, offset = 0.62 },
	{ gain = 0.700, offset = 0.34 },
	{ gain = 1.245, offset = 0.39 },
	{ gain = 0.692, offset = 0.28 },
	{ gain = 2.661, offset = 0.43 },
}

-- One upload can serve every Level 2 SFX. Each boundary is sample-exact in the
-- 48 kHz WAV; 100 ms of silence separates adjacent segments.
local LEVEL2_SFX_SPRITE_SEGMENTS = {
	wade1 = { start = 0.000, duration = 1.186 },
	wade2 = { start = 1.286, duration = 1.236 },
	wade3 = { start = 2.622, duration = 0.916 },
	wade4 = { start = 3.638, duration = 1.196 },
	wade5 = { start = 4.934, duration = 1.146 },
	wade6 = { start = 6.180, duration = 1.256 },
	wade7 = { start = 7.536, duration = 1.106 },
	pipeWalk1 = { start = 8.742, duration = 0.420 },
	pipeWalk2 = { start = 9.262, duration = 0.550 },
	pipeRun = { start = 9.912, duration = 0.700 },
	pipeAttack = { start = 10.712, duration = 1.350 },
	pipeBreathing = { start = 12.162, duration = 2.160 },
}

local function level2SoundId(raw)
	if typeof(raw) == "number" then
		if raw > 0 then return "rbxassetid://" .. tostring(math.floor(raw)) end
		return nil
	end
	if typeof(raw) ~= "string" then return nil end
	local digits = raw:match("^%s*(%d+)%s*$") or raw:match("^%s*rbxassetid://(%d+)%s*$")
	if not digits or tonumber(digits) == 0 then return nil end
	return "rbxassetid://" .. digits
end

local function level2ValueId(source, names)
	if not source then return nil end
	for _, name in ipairs(names) do
		local id = level2SoundId(source:GetAttribute(name))
		if id then return id end
		local value = source:FindFirstChild(name)
		if value and value:IsA("ValueBase") then
			id = level2SoundId(value.Value)
			if id then return id end
		end
	end
	return nil
end

local function level2Sources(model)
	local sources = {}
	local function add(source)
		if source then sources[#sources + 1] = source end
	end
	add(model)
	add(RS:FindFirstChild("Level2Audio"))
	add(workspace:FindFirstChild("PoolroomsLevel2"))
	add(RS)
	add(workspace)
	return sources
end

local function level2SpriteId(model)
	for _, source in ipairs(level2Sources(model)) do
		local id = level2ValueId(source, {
			"Level2SfxSpriteId",
			"PoolPipeSfxSpriteId",
		})
		if id then return id end
	end
	return nil
end

local function level2TakeId(index, model, profile)
	local names = {
		"Level2WadeStep" .. index,
		"Level2WadeStepId" .. index,
		"HeavyBootsSplash" .. index,
		"WadeStep" .. index,
		"ShallowWaterStep" .. index,
	}
	if profile == "pipe" then table.insert(names, 1, "PoolPipeStep" .. index) end
	if profile == "foam" then table.insert(names, 1, "PoolFoamStep" .. index) end
	for _, source in ipairs(level2Sources(model)) do
		local id = level2ValueId(source, names)
		if id then return id end
	end
	return nil
end

local function level2AuxId(model, names)
	for _, source in ipairs(level2Sources(model)) do
		local id = level2ValueId(source, names)
		if id then return id end
	end
	return nil
end

local function shuffleLevel2Bag(indices, previous)
	for i = #indices, 2, -1 do
		local j = math.random(i)
		indices[i], indices[j] = indices[j], indices[i]
	end
	if #indices > 1 and indices[1] == previous then
		indices[1], indices[2] = indices[2], indices[1]
	end
	return indices
end

local function makeLevel2Bank(parent, name, baseVolume, model, profile, positional)
	local bank = {
		voices = {},
		bag = {},
		pipeWalkBag = {},
		cursor = 0,
		lastTake = nil,
		lastPipeWalk = nil,
	}
	for index = 1, #LEVEL2_WADE_SPECS do
		local voice = Instance.new("Sound")
		voice.Name = name .. "Voice" .. index
		voice.Looped = false
		voice.Volume = 0
		if positional then
			voice.RollOffMode = Enum.RollOffMode.InverseTapered
			voice.RollOffMinDistance = profile == "pipe" and 11 or 7
			voice.RollOffMaxDistance = profile == "pipe" and 175 or 115
		end
		if profile == "pipe" then
			local echo = Instance.new("EchoSoundEffect")
			echo.Delay = 0.17
			echo.Feedback = 0.22
			echo.DryLevel = 0
			echo.WetLevel = -13
			echo.Parent = voice
		end
		voice.Parent = parent
		bank.voices[index] = voice
	end

	function bank:nextTake(spriteAvailable)
		if #self.bag == 0 then
			local available = {}
			for index = 1, #LEVEL2_WADE_SPECS do
				if spriteAvailable or level2TakeId(index, model, profile) then
					available[#available + 1] = index
				end
			end
			if #available == 0 then return nil end
			self.bag = shuffleLevel2Bag(available, self.lastTake)
		end
		local take = table.remove(self.bag, 1)
		self.lastTake = take
		return take
	end

	function bank:nextPipeWalk()
		if #self.pipeWalkBag == 0 then
			self.pipeWalkBag = shuffleLevel2Bag({ 1, 2 }, self.lastPipeWalk)
		end
		local take = table.remove(self.pipeWalkBag, 1)
		self.lastPipeWalk = take
		return take
	end

	function bank:play(playbackSpeed, volumeScale, motionVariant)
		local spriteId = level2SpriteId(model)
		local take, id, startAt, duration, gain
		if spriteId then
			id = spriteId
			if profile == "pipe" then
				local segment
				if motionVariant == "run" then
					segment = LEVEL2_SFX_SPRITE_SEGMENTS.pipeRun
				else
					local pipeTake = self:nextPipeWalk()
					segment = pipeTake == 1
						and LEVEL2_SFX_SPRITE_SEGMENTS.pipeWalk1
						or LEVEL2_SFX_SPRITE_SEGMENTS.pipeWalk2
				end
				startAt, duration, gain = segment.start, segment.duration, 1
			else
				take = self:nextTake(true)
				local segment = take and LEVEL2_SFX_SPRITE_SEGMENTS["wade" .. take]
				if not segment then return false end
				startAt, duration, gain = segment.start, segment.duration, LEVEL2_WADE_SPECS[take].gain
			end
		else
			take = self:nextTake(false)
			if not take then return false end
			id = level2TakeId(take, model, profile)
			if not id then
				self.bag = {}
				return false
			end
			local spec = LEVEL2_WADE_SPECS[take]
			startAt, gain = spec.offset, spec.gain
		end

		self.cursor = self.cursor % #self.voices + 1
		local voice = self.voices[self.cursor]
		local speed = playbackSpeed or 1
		local token = (voice:GetAttribute("SpritePlayToken") or 0) + 1
		voice:SetAttribute("SpritePlayToken", token)
		voice:Stop()
		voice.SoundId = id
		voice.Volume = math.clamp(baseVolume * gain * (volumeScale or 1), 0, 2)
		voice.PlaybackSpeed = speed
		voice.TimePosition = startAt
		voice:Play()
		if duration then
			task.delay(duration / speed, function()
				if voice.Parent and voice:GetAttribute("SpritePlayToken") == token then
					voice:Stop()
				end
			end)
		end
		return true
	end

	function bank:destroy()
		for _, voice in ipairs(self.voices) do voice:Destroy() end
	end
	return bank
end

local level2PlayerBank = makeLevel2Bank(SoundService, "Level2PlayerWade", 0.36, nil, "player", false)
local level2WaterRay = RaycastParams.new()
level2WaterRay.FilterType = Enum.RaycastFilterType.Exclude
level2WaterRay.IgnoreWater = false
local level2PlayerLastPosition = nil
local level2PlayerStepClock = 0

local function level2ShallowWater(humanoid, root)
	if workspace:GetAttribute("SelectedLevel") ~= 2 then return false end
	local state = humanoid:GetState()
	if state == Enum.HumanoidStateType.Swimming
		or state == Enum.HumanoidStateType.Freefall
		or state == Enum.HumanoidStateType.Jumping
		or state == Enum.HumanoidStateType.FallingDown
		or state == Enum.HumanoidStateType.Dead
		or state == Enum.HumanoidStateType.Seated then
		return false
	end
	level2WaterRay.FilterDescendantsInstances = { player.Character }
	local hit = workspace:Raycast(root.Position + Vector3.new(0, 1.5, 0), Vector3.new(0, -6.5, 0), level2WaterRay)
	if not hit or hit.Material ~= Enum.Material.Water then return false end
	local rootAboveSurface = root.Position.Y - hit.Position.Y
	return rootAboveSurface >= 0.6 and rootAboveSurface <= 4.25
end

RunService.Heartbeat:Connect(function(dt)
	local hum, root = aliveParts()
	if workspace:GetAttribute("SelectedLevel") ~= 2 or not hum or not root then
		level2PlayerLastPosition = root and root.Position or nil
		level2PlayerStepClock = 0
		return
	end

	local now = root.Position
	if not level2PlayerLastPosition then
		level2PlayerLastPosition = now
		return
	end
	local displacement = Vector3.new(now.X - level2PlayerLastPosition.X, 0, now.Z - level2PlayerLastPosition.Z).Magnitude
	level2PlayerLastPosition = now
	if displacement > 7 then
		level2PlayerStepClock = 0
		return
	end
	local flatSpeed = dt > 0 and displacement / dt or 0
	if flatSpeed < 1.35 or not level2ShallowWater(hum, root) then
		level2PlayerStepClock = math.min(level2PlayerStepClock, 0.12)
		return
	end

	local cadence = math.clamp(0.68 - flatSpeed * 0.015, 0.30, 0.56)
	level2PlayerStepClock += dt
	if level2PlayerStepClock >= cadence then
		level2PlayerStepClock %= cadence
		level2PlayerBank:play(0.97 + math.random() * 0.06, math.clamp(0.88 + flatSpeed / 42, 0.9, 1.18))
	end
end)

workspace:GetAttributeChangedSignal("SelectedLevel"):Connect(function()
	if workspace:GetAttribute("SelectedLevel") == 2 then
		steps.Volume = 0
		level2PlayerStepClock = 0
	end
end)

-- Pool Foam and Pool Pipe use the same seven normalized source takes through
-- positional banks. Model Profile/MotionState/ActionSerial are the primary API;
-- names and CollectionService tags make hand-authored/test rigs work as well.
local level2EntityAudio = {}

local function level2Profile(model)
	local raw = string.lower(tostring(model:GetAttribute("Profile") or ""))
	local name = string.lower(model.Name):gsub("[%s_%-]", "")
	if raw:find("pipe", 1, true) or name:find("poolpipe", 1, true)
		or CollectionService:HasTag(model, "PoolPipeEntity") then
		return "pipe"
	end
	if raw:find("foam", 1, true) or name:find("poolfoam", 1, true)
		or CollectionService:HasTag(model, "PoolFoamEntity") then
		return "foam"
	end
	return nil
end

local function level2EntityRoot(model)
	if model.PrimaryPart then return model.PrimaryPart end
	local named = model:FindFirstChild("HumanoidRootPart", true)
		or model:FindFirstChild("Root", true)
		or model:FindFirstChild("char1", true)
	if named and named:IsA("BasePart") then return named end
	return model:FindFirstChildWhichIsA("BasePart", true)
end

local function addPipeAcoustics(sound)
	local echo = Instance.new("EchoSoundEffect")
	echo.Delay = 0.21
	echo.Feedback = 0.18
	echo.DryLevel = 0
	echo.WetLevel = -15
	echo.Parent = sound
	local eq = Instance.new("EqualizerSoundEffect")
	eq.LowGain = 2
	eq.MidGain = -1
	eq.HighGain = -5
	eq.Parent = sound
end

local function level2PipeAuxSound(root, name, looped, volume, maxDistance)
	local sound = Instance.new("Sound")
	sound.Name = name
	sound.Looped = looped
	sound.Volume = volume
	sound.RollOffMode = Enum.RollOffMode.InverseTapered
	sound.RollOffMinDistance = 11
	sound.RollOffMaxDistance = maxDistance
	addPipeAcoustics(sound)
	sound.Parent = root
	return sound
end

local function refreshPipeBreathing(controller)
	if controller.profile ~= "pipe" then return end
	local sound = controller.breathing
	local spriteId = level2SpriteId(controller.model)
	local id = spriteId or level2AuxId(controller.model, {
		"PoolPipeBreathingSoundId",
		"PoolPipeBreathSoundId",
		"MetalBreathingSoundId",
		"BreathingSoundId",
	})
	local usesSprite = spriteId ~= nil
	controller.breathingUsesSprite = usesSprite
	sound.Looped = not usesSprite
	if (id or "") ~= sound.SoundId then
		sound:Stop()
		sound.SoundId = id or ""
	end
	if workspace:GetAttribute("SelectedLevel") == 2 and id then
		if not sound.IsPlaying then
			if usesSprite then sound.TimePosition = LEVEL2_SFX_SPRITE_SEGMENTS.pipeBreathing.start end
			sound:Play()
		end
	elseif sound.IsPlaying then
		sound:Stop()
	end
end

local function playPipeAttack(controller)
	if controller.profile ~= "pipe" or workspace:GetAttribute("SelectedLevel") ~= 2 then return end
	if os.clock() - controller.lastAttackAt < 0.12 then return end
	controller.lastAttackAt = os.clock()
	local spriteId = level2SpriteId(controller.model)
	local id = spriteId or level2AuxId(controller.model, {
		"PoolPipeAttackSoundId",
		"MetalAttackSoundId",
		"AttackSoundId",
	})
	if not id then return end
	local sound = controller.attack
	local speed = 0.94 + math.random() * 0.08
	local token = (sound:GetAttribute("SpritePlayToken") or 0) + 1
	sound:SetAttribute("SpritePlayToken", token)
	sound:Stop()
	sound.SoundId = id
	sound.PlaybackSpeed = speed
	sound.TimePosition = spriteId and LEVEL2_SFX_SPRITE_SEGMENTS.pipeAttack.start or 0
	sound:Play()
	if spriteId then
		task.delay(LEVEL2_SFX_SPRITE_SEGMENTS.pipeAttack.duration / speed, function()
			if sound.Parent and sound:GetAttribute("SpritePlayToken") == token then sound:Stop() end
		end)
	end
end

local function hookLevel2Entity(model)
	if level2EntityAudio[model] or not model:IsDescendantOf(workspace) then return end
	local profile = level2Profile(model)
	if not profile then return end
	local root = level2EntityRoot(model)
	if not root then
		task.delay(0.25, function() hookLevel2Entity(model) end)
		return
	end

	local controller = {
		model = model,
		root = root,
		profile = profile,
		lastPosition = root.Position,
		stepClock = 0,
		lastActionSerial = model:GetAttribute("ActionSerial"),
		lastMotionState = string.lower(tostring(model:GetAttribute("MotionState") or "")),
		lastAttackAt = -999,
		auxRefreshAt = 0,
	}
	controller.bank = makeLevel2Bank(
		root,
		profile == "pipe" and "PoolPipeStep" or "PoolFoamStep",
		profile == "pipe" and 0.52 or 0.42,
		model,
		profile,
		true
	)
	if profile == "pipe" then
		controller.breathing = level2PipeAuxSound(root, "PoolPipeBreathing", true, 0.18, 145)
		controller.attack = level2PipeAuxSound(root, "PoolPipeAttack", false, 0.95, 190)
		refreshPipeBreathing(controller)
	end
	level2EntityAudio[model] = controller

	controller.actionConnection = model:GetAttributeChangedSignal("ActionSerial"):Connect(function()
		local serial = model:GetAttribute("ActionSerial")
		if serial == controller.lastActionSerial then return end
		controller.lastActionSerial = serial
		playPipeAttack(controller)
	end)
	controller.motionConnection = model:GetAttributeChangedSignal("MotionState"):Connect(function()
		local motion = string.lower(tostring(model:GetAttribute("MotionState") or ""))
		if motion:find("attack", 1, true) and not controller.lastMotionState:find("attack", 1, true) then
			playPipeAttack(controller)
		end
		controller.lastMotionState = motion
	end)
end

local function tryHookLevel2Entity(model)
	task.defer(function()
		if model and model.Parent then hookLevel2Entity(model) end
	end)
end

for _, descendant in ipairs(workspace:GetDescendants()) do
	if descendant:IsA("Model") and level2Profile(descendant) then
		tryHookLevel2Entity(descendant)
	end
end
workspace.DescendantAdded:Connect(function(descendant)
	if descendant:IsA("Model") then
		tryHookLevel2Entity(descendant)
	elseif descendant:IsA("BasePart") and descendant.Parent and descendant.Parent:IsA("Model") then
		tryHookLevel2Entity(descendant.Parent)
	end
end)
for _, tag in ipairs({ "PoolPipeEntity", "PoolFoamEntity" }) do
	CollectionService:GetInstanceAddedSignal(tag):Connect(function(instance)
		if instance:IsA("Model") then tryHookLevel2Entity(instance) end
	end)
end

RunService.Heartbeat:Connect(function(dt)
	local levelTwo = workspace:GetAttribute("SelectedLevel") == 2
	for model, controller in pairs(level2EntityAudio) do
		local root = controller.root
		if not model.Parent or not root.Parent then
			if controller.actionConnection then controller.actionConnection:Disconnect() end
			if controller.motionConnection then controller.motionConnection:Disconnect() end
			controller.bank:destroy()
			if controller.breathing then controller.breathing:Destroy() end
			if controller.attack then controller.attack:Destroy() end
			level2EntityAudio[model] = nil
			continue
		end

		if controller.profile == "pipe" and os.clock() >= controller.auxRefreshAt then
			controller.auxRefreshAt = os.clock() + 0.75
			refreshPipeBreathing(controller)
		end
		if controller.profile == "pipe" and controller.breathingUsesSprite
			and controller.breathing and controller.breathing.IsPlaying then
			local segment = LEVEL2_SFX_SPRITE_SEGMENTS.pipeBreathing
			local segmentEnd = segment.start + segment.duration
			local position = controller.breathing.TimePosition
			if position >= segmentEnd or position < segment.start - 0.03 then
				controller.breathing.TimePosition = segment.start
			end
		end

		local now = root.Position
		local displacement = Vector3.new(now.X - controller.lastPosition.X, 0, now.Z - controller.lastPosition.Z).Magnitude
		controller.lastPosition = now
		if not levelTwo or displacement > 10 then
			controller.stepClock = 0
			continue
		end
		local speed = dt > 0 and displacement / dt or 0
		local motion = string.lower(tostring(model:GetAttribute("MotionState") or ""))
		local movingState = motion == ""
			or motion:find("walk", 1, true)
			or motion:find("wander", 1, true)
			or motion:find("move", 1, true)
			or motion:find("patrol", 1, true)
			or motion:find("search", 1, true)
			or motion:find("chase", 1, true)
			or motion:find("run", 1, true)
			or motion:find("hunt", 1, true)
		if speed < 0.75 or not movingState then
			controller.stepClock = math.min(controller.stepClock, 0.12)
			continue
		end
		local running = motion:find("chase", 1, true)
			or motion:find("run", 1, true)
			or motion:find("hunt", 1, true)
			or speed >= (controller.profile == "pipe" and 12 or 14)
		local cadence
		if controller.profile == "foam" then
			cadence = running and 0.31 or 0.62
		else
			cadence = running and 0.34 or 0.72
		end
		controller.stepClock += dt
		if controller.stepClock >= cadence then
			controller.stepClock %= cadence
			local pitch = controller.profile == "pipe"
				and (running and (0.90 + math.random() * 0.07) or (0.84 + math.random() * 0.07))
				or (0.96 + math.random() * 0.08)
			controller.bank:play(pitch, running and 1.16 or 1, running and "run" or "walk")
		end
	end
end)
