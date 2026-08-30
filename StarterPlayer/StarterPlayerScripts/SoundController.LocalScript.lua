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
local ContentProvider = game:GetService("ContentProvider")

-- ── audio slots (every sound in the game) ─────────────────
local AMBIENCE_SOUND  = "rbxassetid://92576512092725" -- fluorescent hum, played FROM each lit ceiling panel (positional; off/dead panels are silent)
local BREATHING_SOUND = "" -- YOUR OWN winded breathing (2D) — fades in below 20% stamina
local FOOTSTEP_WALK   = "rbxassetid://108141977175862" -- walking loop (the slower-cadence clip)
local LOBBY_FOOTSTEP_SOUND = "" -- LOBBY-ONLY steps. Roblox's default loop and the
-- round clips both read as squeaky in the tunnel, so the lobby ships silent;
-- paste any clean footstep-loop id here and lobby walk/sprint use it.
local FOOTSTEP_RUN    = "rbxassetid://133003345144597" -- running loop (the faster-cadence clip, natural pitch)
local ALERT_SOUND     = "rbxassetid://118863512220494" -- plays while the maze is in ALERT (red lights) mode
local ELEVATOR_SOUND  = "rbxassetid://72303878759145" -- the elevator ride, plays through the pre-round intro (2D)
local FLASHLIGHT_SOUND = "rbxassetid://79013410316837" -- click when YOU toggle the flashlight on/off (2D, only you hear it)
local ENTITY_SOUND    = "rbxassetid://103206085469231" -- looping growl/drone emitted BY the Entity (positional)
local DEATH_SOUND     = "rbxassetid://113822157484898" -- the scream ALIVE players hear when someone dies (positional at the kill)
local JUMPSCARE_SOUND = "rbxassetid://140233243543479" -- the DYING player's OWN jumpscare sound (2D, only they hear it)
local YELL_SOUND      = "rbxassetid://92808749593079" -- the Entity's roar when it shoves you off a pit beam (positional)
local SPOT_SOUND      = "rbxassetid://82272419363488" -- the "spotted you!" scream when it first sees someone (positional)
local LUNGE_SOUND     = "" -- plays as it winds up a lunge (telegraph, positional)
local ENTITY_STEP_SOUNDS = { -- alternating left/right Entity steps (positional)
	"rbxassetid://130932521095399", -- first step
	"rbxassetid://95916241222632",  -- second step
}
-- Skip each file's leading silence so both impacts land at the same perceived time.
local ENTITY_STEP_STARTS = {0.70, 0.23}
-- idle vocalisations played at random while the Entity just roams (positional).
-- Fill any of the 3 — it works with just one; empty slots are skipped.
local IDLE_SOUNDS     = { "", "", "" }
local CHASE_SOUND     = "rbxassetid://79246919959914" -- loops while the Entity is actively CHASING you (positional)
-- distant entity screams, heard by EVERYONE on the server at the same moment,
-- 3D from wherever the Entity is. EntityAI picks the timing and the take and
-- publishes them (EntityScream / EntityScreamIndex attributes) so every player
-- hears the SAME scream. Fill any of the 4; empty slots stay silent.
local SCREAM_SOUNDS   = {
	"", -- Level 1 Distant Entity Scream 1
	"", -- Level 1 Distant Entity Scream 2
	"", -- Level 1 Distant Entity Scream 3
	"", -- Level 1 Distant Entity Scream 4
}

-- ── tuning ────────────────────────────────────────────────
local AMBIENCE_VOLUME   = 0.17 -- peak per-light hum volume (was 0.29; another ~40% down)
local HUM_MIN_DISTANCE  = 6    -- full hum volume this close to a lit panel
local HUM_MAX_DISTANCE  = 45   -- a panel is inaudible beyond this (panels sit ~48 studs apart)
local HUM_POOL_SIZE     = 10   -- at most this many nearby panels carry a live hum Sound
local HUM_RESCAN        = 0.35 -- seconds between "which panels are nearest" rescans
local ELEVATOR_VOLUME   = 0.8  -- the elevator ride's normal 2D volume
local ELEVATOR_BRIEFING_VOLUME = 0.52 -- gently duck the ride while Command Center speaks
local ELEVATOR_DUCK_IN  = 0.25 -- quick fade so the first spoken word stays clear
local ELEVATOR_DUCK_OUT = 0.65 -- softer return after the briefing
local BREATH_START      = 0.2   -- stamina fraction at which winded breathing kicks in
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
local SCREAM_VOLUME    = 0.95  -- distant entity screams (positional at the Entity, map-wide)
local CHASE_FADE       = 0.6   -- seconds to fade the chase loop in / out
local TRACK_FADE       = 5     -- seconds to SLOWLY fade the chase music once it loses
-- sight and is only tracking blindly (match TRACK_TIME)
local SPOT_VOLUME      = 1      -- the "spotted you!" sting (SPOT_SOUND) fired as a chase begins
local LUNGE_VOLUME     = 1     -- the lunge telegraph (positional)
local STEP_WALK_VOLUME = 1.014 -- entity walk impact (30% louder)
local STEP_RUN_VOLUME  = 1.30  -- entity chase impact (30% louder)
local STEP_WALK_INT    = 0.53  -- seconds between alternating steps at the 8 stud/s walk
local STEP_RUN_INT     = 0.34  -- seconds between alternating steps at the 27.2 stud/s chase
local STEP_WALK_PLAYBACK = 0.98 -- weighty natural pitch while roaming/searching
local STEP_RUN_PLAYBACK  = 1.09 -- tighter, more urgent attack while chasing
local STEP_CADENCE_JITTER = 0.015
local STEP_PITCH_JITTER   = 0.015
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

-- ── fluorescent hum: one positional loop per LIT ceiling panel ────────────
-- The hum lives on the ceiling lights themselves: the closer you are to a lit
-- panel, the louder THAT panel hums, and a panel that is off — broken from the
-- start, mid-flicker, blacked out, powered down — is silent, so your ears tell
-- you which nearby fixtures are live. Only the HUM_POOL_SIZE nearest panels
-- within HUM_MAX_DISTANCE carry a Sound at any moment; the pool follows you.
-- The hum starts SILENT and fades in when the round begins — during the
-- elevator ride you hear the elevator, not the maze. `ambienceTarget` (0 or 1)
-- is set by the round events below and eased toward in the main Heartbeat.
local AMBIENCE_FADE = 4      -- ~seconds to ease the hums in / out
local ambienceTarget = 0
local humMaster = 0          -- eased 0..1 master gain applied to every pooled hum
local humCandidates = {}     -- SurfaceLight -> panel BasePart (every panel in the maze)
local humPool = {}           -- SurfaceLight -> { panel, sound } (the nearest few)
local breathing = makeLoop(BREATHING_SOUND, 0) -- long continuous loop, volume-ridden
-- PRELOAD the looping sounds before playing them. A loop that isn't fully loaded
-- re-buffers at the loop point, which is the "slight stop" you hear each cycle;
-- preloading makes the hum copies and the breathing loop seamless.
task.spawn(function()
	local ContentProvider = game:GetService("ContentProvider")
	local toLoad = {}
	if AMBIENCE_SOUND ~= "" then
		-- warm the hum asset once so pooled copies start without a buffering gap
		local warm = Instance.new("Sound")
		warm.SoundId = AMBIENCE_SOUND
		warm.Parent = SoundService
		table.insert(toLoad, warm)
		task.delay(20, function() warm:Destroy() end)
	end
	if BREATHING_SOUND ~= "" then table.insert(toLoad, breathing) end
	if #toLoad > 0 then pcall(function() ContentProvider:PreloadAsync(toLoad) end) end
	if BREATHING_SOUND ~= "" then breathing:Play() end -- loops silently; volume rides below
end)

local function humDropAll()
	for _, entry in pairs(humPool) do entry.sound:Destroy() end
	table.clear(humPool)
	table.clear(humCandidates)
end

-- track the HUMMING light panels in the maze: MazeGenerator marks about half
-- of the working fixtures with the HumSource attribute (plus the guaranteed
-- lamps by the elevator) — only those buzz at all; the rest are silent even
-- while lit. Streaming adds/removes panels at any time, so watch descendants
-- rather than scanning once.
local function humWatchMaze(maze)
	humDropAll()
	local function tryAdd(inst)
		if inst:IsA("SurfaceLight") and inst.Parent and inst.Parent:IsA("BasePart")
			and inst.Parent:GetAttribute("HumSource") == true then
			humCandidates[inst] = inst.Parent
		end
	end
	for _, inst in ipairs(maze:GetDescendants()) do tryAdd(inst) end
	local addedConn = maze.DescendantAdded:Connect(tryAdd)
	local removedConn = maze.DescendantRemoving:Connect(function(inst)
		if humCandidates[inst] then
			humCandidates[inst] = nil
			local pooled = humPool[inst]
			if pooled then
				pooled.sound:Destroy()
				humPool[inst] = nil
			end
		end
	end)
	maze.AncestryChanged:Connect(function(_, parent)
		if parent == nil then -- round over, maze destroyed
			addedConn:Disconnect()
			removedConn:Disconnect()
			humDropAll()
		end
	end)
end

workspace.ChildAdded:Connect(function(child)
	if child.Name == "Maze" and child:IsA("Model") then humWatchMaze(child) end
end)
do
	local maze = workspace:FindFirstChild("Maze")
	if maze and maze:IsA("Model") then humWatchMaze(maze) end
end

-- keep the pool holding the nearest panels. Sounds are created/destroyed here;
-- their volumes ride in the main Heartbeat so flicker cuts land frame-exact.
task.spawn(function()
	while true do
		task.wait(HUM_RESCAN)
		if AMBIENCE_SOUND == "" then continue end
		local char = player.Character
		local root = char and char:FindFirstChild("HumanoidRootPart")
		local camera = workspace.CurrentCamera
		local here = root and root.Position or (camera and camera.CFrame.Position)
		if not here or next(humCandidates) == nil then
			for light, entry in pairs(humPool) do
				entry.sound:Destroy()
				humPool[light] = nil
			end
			continue
		end
		local nearest = {}
		for light, panel in pairs(humCandidates) do
			if panel.Parent then
				local d = (panel.Position - here).Magnitude
				if d <= HUM_MAX_DISTANCE then
					nearest[#nearest + 1] = { light = light, panel = panel, d = d }
				end
			end
		end
		table.sort(nearest, function(a, b) return a.d < b.d end)
		local keep = {}
		for i = 1, math.min(#nearest, HUM_POOL_SIZE) do
			keep[nearest[i].light] = nearest[i].panel
		end
		for light, entry in pairs(humPool) do
			if not keep[light] then
				entry.sound:Destroy()
				humPool[light] = nil
			end
		end
		for light, panel in pairs(keep) do
			if not humPool[light] then
				local s = Instance.new("Sound")
				s.Name = "FluorescentHum"
				s.Looped = true
				s.Volume = 0
				s.SoundId = AMBIENCE_SOUND
				s.RollOffMode = Enum.RollOffMode.InverseTapered
				s.RollOffMinDistance = HUM_MIN_DISTANCE
				s.RollOffMaxDistance = HUM_MAX_DISTANCE
				s.PlaybackSpeed = 0.97 + math.random() * 0.06 -- decohere identical copies
				s.Parent = panel
				s:Play()
				humPool[light] = { panel = panel, sound = s }
			end
		end
	end
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
-- face image (JumpscareUI). The scream starts the INSTANT the Entity captures
-- you ("capture" fires only to the caught player, the moment the grab lands);
-- the face image and the fatal impact still land later in the cinematic.
local jumpscareRemote = RS:WaitForChild("Remotes"):WaitForChild("Jumpscare")
jumpscareRemote.OnClientEvent:Connect(function(eventName)
	if eventName ~= "capture" then return end
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
elevatorSound.Name = "LevelOneElevatorRide"
elevatorSound.Volume = ELEVATOR_VOLUME
elevatorSound.Parent = SoundService

local elevatorVolumeTween = nil
local function refreshElevatorBriefingVolume()
	if elevatorVolumeTween then elevatorVolumeTween:Cancel() end
	local briefingActive = player:GetAttribute("LevelOneBriefingActive") == true
	local target = briefingActive and ELEVATOR_BRIEFING_VOLUME or ELEVATOR_VOLUME
	local duration = briefingActive and ELEVATOR_DUCK_IN or ELEVATOR_DUCK_OUT
	elevatorVolumeTween = TweenService:Create(
		elevatorSound,
		TweenInfo.new(duration, Enum.EasingStyle.Quad, Enum.EasingDirection.Out),
		{Volume = target}
	)
	elevatorVolumeTween:Play()
end
player:GetAttributeChangedSignal("LevelOneBriefingActive"):Connect(refreshElevatorBriefingVolume)
refreshElevatorBriefingVolume()

roundStatus.OnClientEvent:Connect(function(ev)
	if ev == "elevator" then
		ambienceTarget = 0 -- silent during the ride
		-- This is Level 1's authored elevator one-shot. Level 3 has its own entry
		-- soundscape and must never inherit the old office-level introduction.
		if workspace:GetAttribute("SelectedLevel") ~= 1 then
			elevatorSound:Stop()
			return
		end
		if ELEVATOR_SOUND ~= "" and not elevatorSound.IsPlaying then
			elevatorSound.SoundId = ELEVATOR_SOUND
			refreshElevatorBriefingVolume()
			elevatorSound:Play()
		end
	elseif ev == "start" then
		-- The office fluorescent hum belongs to level 1 only. Level 2 stays
		-- silent until its dedicated hollow poolroom ambience asset is supplied.
		ambienceTarget = workspace:GetAttribute("SelectedLevel") == 1 and 1 or 0
	elseif ev == "win" or ev == "lose" then
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

-- the "spotted you!" scream: EntityAI bumps EntitySpotScream the moment it
-- first SEES a player (the stationary first-sight howl), and everyone hears
-- SPOT_SOUND positionally at the entity — a different voice from the pit roar
if SPOT_SOUND ~= "" then
	workspace:GetAttributeChangedSignal("EntitySpotScream"):Connect(function()
		local entity = workspace:FindFirstChild("Entity")
		local er = entity and entity:FindFirstChild("HumanoidRootPart")
		if not er then return end
		local s = Instance.new("Sound")
		s.Name = "SpotScream"
		s.SoundId = SPOT_SOUND
		s.Volume = SPOT_VOLUME
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

-- distant entity screams: EntityAI publishes EntityScreamIndex then bumps the
-- EntityScream counter at a random cadence. Every client plays the SAME take
-- positionally at the Entity, so the whole server shares one scream from the
-- Entity's direction — audible clear across the maze, pushed "far away" in the
-- mix by the same Linear-falloff + EQ recipe as the death scream.
workspace:GetAttributeChangedSignal("EntityScream"):Connect(function()
	local idx = workspace:GetAttribute("EntityScreamIndex")
	local id = typeof(idx) == "number" and SCREAM_SOUNDS[idx] or nil
	if not id or id == "" then return end
	local entity = workspace:FindFirstChild("Entity")
	local er = entity and entity:FindFirstChild("HumanoidRootPart")
	if not er then return end
	local s = Instance.new("Sound")
	s.Name = "DistantScream"
	s.SoundId = id
	s.Volume = SCREAM_VOLUME
	s.PlaybackSpeed = 0.97 + math.random() * 0.06
	s.RollOffMode = Enum.RollOffMode.Linear
	s.RollOffMinDistance = 60
	s.RollOffMaxDistance = 2200
	local eq = Instance.new("EqualizerSoundEffect")
	eq.HighGain = -6
	eq.MidGain = -2
	eq.LowGain = 0
	eq.Parent = s
	s.Parent = er
	s:Play()
	s.Ended:Connect(function() s:Destroy() end)
	task.delay(12, function() if s then s:Destroy() end end)
end)

-- the chase audio: when the Entity SPOTS someone (EntityState → CHASE) it
-- first plays a "spotted you!" sting, then the positional chase loop fades in.
-- Level 1 can begin after a long lobby wait and can rebuild its Entity between
-- rounds, so this binding follows every replacement instead of timing out once.
local chaseEntity
local chase
local chaseFadeTween
local chaseBindSerial = 0
local chasePrevEngaged = false
local chaseLastSpot = -999

local function chaseActive()
	return workspace:GetAttribute("SelectedLevel") == 1
		and workspace:GetAttribute("RoundActive") == true
		and player:GetAttribute("InRound") == true
		and player:GetAttribute("Escaped") ~= true
end

local function fadeChase(target, duration)
	if not chase or not chase.Parent then return end
	if not chase.IsPlaying then chase:Play() end
	if chaseFadeTween then chaseFadeTween:Cancel() end
	chaseFadeTween = TweenService:Create(
		chase,
		TweenInfo.new(duration, Enum.EasingStyle.Linear),
		{Volume = target}
	)
	chaseFadeTween:Play()
end

local function refreshChase()
	local st = workspace:GetAttribute("EntityState")
	local eligible = chaseActive()
	local alerting = eligible and st == "ALERT"
	local chasing = eligible and st == "CHASE"
	local tracking = eligible and st == "TRACK"

	if chasing then
		-- Freshly spotted (wasn't already engaged) → the positional sting.
		local er = chase and chase.Parent
		if not chasePrevEngaged and SPOT_SOUND ~= "" and (os.clock() - chaseLastSpot) > 4
			and er and er:IsA("BasePart") then
			chaseLastSpot = os.clock()
			local spot = Instance.new("Sound")
			spot.SoundId = SPOT_SOUND
			spot.Volume = 0
			spot.RollOffMode = Enum.RollOffMode.InverseTapered
			spot.RollOffMinDistance = 10
			spot.RollOffMaxDistance = 200
			spot.Parent = er
			spot:Play()
			TweenService:Create(spot, TweenInfo.new(0.25), {Volume = SPOT_VOLUME}):Play()
			spot.Ended:Connect(function() spot:Destroy() end)
			task.delay(8, function() if spot.Parent then spot:Destroy() end end)
		end
		fadeChase(CHASE_VOLUME, CHASE_FADE)
	elseif tracking then
		-- Lost sight but still tracking → slowly withdraw the chase loop.
		fadeChase(0, TRACK_FADE)
	elseif chase and chase.IsPlaying then
		local boundSound = chase
		fadeChase(0, CHASE_FADE)
		task.delay(CHASE_FADE + 0.1, function()
			if chase ~= boundSound or not boundSound.Parent then return end
			local stateNow = workspace:GetAttribute("EntityState")
			if not chaseActive() or (stateNow ~= "CHASE" and stateNow ~= "TRACK") then
				boundSound:Stop()
			end
		end)
	end
	chasePrevEngaged = alerting or chasing or tracking
end

local function unbindChaseEntity()
	chaseBindSerial += 1
	if chaseFadeTween then
		chaseFadeTween:Cancel()
		chaseFadeTween = nil
	end
	if chase then
		chase:Destroy()
		chase = nil
	end
	chaseEntity = nil
	chasePrevEngaged = false
end

local function bindChaseEntity(entity)
	if not (entity and entity:IsA("Model") and entity.Name == "Entity") then return end
	if chaseEntity == entity and chase and chase.Parent then return end
	unbindChaseEntity()
	chaseEntity = entity
	chaseBindSerial += 1
	local serial = chaseBindSerial

	task.spawn(function()
		local er = entity:FindFirstChild("HumanoidRootPart") or entity:WaitForChild("HumanoidRootPart", 15)
		if serial ~= chaseBindSerial or chaseEntity ~= entity or not (er and er:IsA("BasePart")) then return end
		if CHASE_SOUND == "" then return end

		local newChase = Instance.new("Sound")
		newChase.Name = "ChaseSound"
		newChase.Looped = true
		newChase.Volume = 0
		newChase.SoundId = CHASE_SOUND
		newChase.RollOffMode = Enum.RollOffMode.InverseTapered
		newChase.RollOffMinDistance = 10
		newChase.RollOffMaxDistance = 200
		newChase.Parent = er
		chase = newChase

		-- Warm the 31-second chase take before first contact so Play() is immediate.
		task.spawn(function()
			pcall(function()
				game:GetService("ContentProvider"):PreloadAsync({newChase})
			end)
		end)
		refreshChase()
	end)
end

workspace:GetAttributeChangedSignal("EntityState"):Connect(refreshChase)
workspace:GetAttributeChangedSignal("SelectedLevel"):Connect(refreshChase)
workspace:GetAttributeChangedSignal("RoundActive"):Connect(refreshChase)
player:GetAttributeChangedSignal("InRound"):Connect(refreshChase)
player:GetAttributeChangedSignal("Escaped"):Connect(refreshChase)
workspace.ChildAdded:Connect(function(child)
	if child.Name == "Entity" then bindChaseEntity(child) end
end)
workspace.ChildRemoved:Connect(function(child)
	if child == chaseEntity then unbindChaseEntity() end
end)

local existingChaseEntity = workspace:FindFirstChild("Entity")
if existingChaseEntity then bindChaseEntity(existingChaseEntity) end

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

-- The Entity's two alternating steps. Both supplied clips are one-shot impacts
-- with long tails and different leading silence, so each foot gets its own voice.
-- Actual position delta suppresses fake stomps while the Entity is stuck.
task.spawn(function()
	if ENTITY_STEP_SOUNDS[1] == "" and ENTITY_STEP_SOUNDS[2] == "" then return end
	local entity = workspace:WaitForChild("Entity", 60)
	local er = entity and entity:WaitForChild("HumanoidRootPart", 15)
	if not er then return end

	local voices = {}
	for index, id in ipairs(ENTITY_STEP_SOUNDS) do
		local step = Instance.new("Sound")
		step.Name = "EntityStep" .. index
		step.SoundId = id
		step.RollOffMode = Enum.RollOffMode.InverseTapered
		step.RollOffMinDistance = 8
		step.RollOffMaxDistance = 140
		step.Parent = er
		voices[index] = step
	end
	pcall(function()
		ContentProvider:PreloadAsync(voices)
	end)

	local clock = math.huge -- land a step immediately when real movement begins
	local nextInterval = STEP_WALK_INT
	local nextFoot = 1
	local lastPos = er.Position
	local movementGrace = 0
	RunService.Heartbeat:Connect(function(dt)
		local now = er.Position
		local moved = Vector3.new(now.X - lastPos.X, 0, now.Z - lastPos.Z).Magnitude
		lastPos = now
		local spd = (dt > 0) and (moved / dt) or 0
		if spd >= 3 then
			-- Physics replication can arrive in tiny bursts. Hold the moving state
			-- briefly between packets so one real stride never becomes many first steps.
			movementGrace = 0.14
		else
			movementGrace = math.max(0, movementGrace - dt)
		end
		if movementGrace <= 0 then
			clock = math.huge
			return
		end

		-- EntityAnimation uses Run only in CHASE. TRACK/SEARCH deliberately keeps
		-- the walk cycle even when it moves faster, so key the gait to the same state.
		local chasing = workspace:GetAttribute("EntityState") == "CHASE"
		-- Use animation state for cadence rather than raw per-frame speed: networked
		-- physics can arrive in bursts even while the visual movement is smooth.
		local cadence = chasing and STEP_RUN_INT or STEP_WALK_INT

		clock += dt
		if clock < nextInterval then return end
		clock = 0

		local step = voices[nextFoot]
		if step then
			step:Stop()
			step.TimePosition = ENTITY_STEP_STARTS[nextFoot]
			step.Volume = chasing and STEP_RUN_VOLUME or STEP_WALK_VOLUME
			local basePlayback = chasing and STEP_RUN_PLAYBACK or STEP_WALK_PLAYBACK
			step.PlaybackSpeed = basePlayback
				+ ((math.random() * 2 - 1) * STEP_PITCH_JITTER)
			step:Play()
		end
		nextFoot = nextFoot == #voices and 1 or nextFoot + 1
		nextInterval = math.max(0.1, cadence
			+ ((math.random() * 2 - 1) * STEP_CADENCE_JITTER))
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
			if frac <= BREATH_START then
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

	-- fluorescent hum: ease the round-driven master, then let each pooled panel
	-- hum only while its light is actually ON (a mid-flicker or blacked-out
	-- panel goes silent the same frame). Level 2/3 have no maze; the per-frame
	-- SelectedLevel gate also silences the hum on a direct dev teleport.
	if AMBIENCE_SOUND ~= "" then
		local target = workspace:GetAttribute("SelectedLevel") == 1 and ambienceTarget or 0
		humMaster = humMaster + (target - humMaster) * math.clamp(dt / AMBIENCE_FADE, 0, 1)
		for light, entry in pairs(humPool) do
			entry.sound.Volume = (light.Enabled and entry.panel.Material == Enum.Material.Neon)
				and AMBIENCE_VOLUME * humMaster or 0
		end
	end

	-- footsteps: a looping track that only plays while you MOVE and fades out when
	-- you stop (so a long loop never drones on while standing, and never hard-cuts)
	local footTarget, footSpeed = 0, nil
	local inRound = player:GetAttribute("InRound") == true
	local lobbySteps = not inRound and LOBBY_FOOTSTEP_SOUND ~= ""
	if hum and root and (lobbySteps
		or (inRound and workspace:GetAttribute("SelectedLevel") ~= 2)) then
		local vel = root.AssemblyLinearVelocity
		local flat = Vector3.new(vel.X, 0, vel.Z).Magnitude
		local ws = hum.WalkSpeed
		if flat >= 2 and ws > 10 then
			-- walk uses the walk loop; run uses its OWN clip at natural pitch
			-- (speeding a clip up to fake a run makes it chipmunk-high). Falls back
			-- to the walk loop sped up only if no run clip is set.
			local run = ws >= RUN_WALKSPEED
			local wantId, wantSpeed, wantVol
			if lobbySteps then
				wantId = LOBBY_FOOTSTEP_SOUND
				wantSpeed = run and RUN_SPEEDUP or WALK_SPEEDUP
				wantVol = (run and RUN_VOLUME or WALK_VOLUME) * .8
			else
				wantId = run and (FOOTSTEP_RUN ~= "" and FOOTSTEP_RUN or FOOTSTEP_WALK) or FOOTSTEP_WALK
				wantSpeed = run and RUN_SPEEDUP or WALK_SPEEDUP
				wantVol = run and RUN_VOLUME or WALK_VOLUME
			end
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

-- Roblox's own character footstep loop is muted EVERYWHERE, lobby included —
-- the lobby uses the LOBBY_FOOTSTEP_SOUND slot above and rounds use this
-- controller's custom carpet/water sounds, so the default loop may never layer
-- over either. Re-asserted whenever anything else writes the Volume back up.
local function configureDefaultSteps(char)
	task.spawn(function()
		local hrp = char:WaitForChild("HumanoidRootPart", 10)
		if not hrp then return end

		local destroyed = false
		local soundRecords = {}
		local function disconnectRunning(sound)
			local record = soundRecords[sound]
			if not record then return end
			soundRecords[sound] = nil
			for _, connection in ipairs(record.connections) do connection:Disconnect() end
		end
		local function bind(candidate)
			if destroyed or not (candidate and candidate:IsA("Sound"))
				or candidate.Name ~= "Running" or soundRecords[candidate] then return end
			local record = { changing = false, connections = {} }
			soundRecords[candidate] = record
			local function refresh()
				if destroyed or not candidate.Parent or record.changing then return end
				if candidate.Volume ~= 0 then
					record.changing = true
					candidate.Volume = 0
					record.changing = false
				end
			end
			record.connections[#record.connections + 1] = candidate:GetPropertyChangedSignal("Volume"):Connect(refresh)
			record.connections[#record.connections + 1] = candidate.Destroying:Connect(function()
				disconnectRunning(candidate)
			end)
			record.connections[#record.connections + 1] = candidate.AncestryChanged:Connect(function()
				if candidate.Parent and candidate:IsDescendantOf(hrp) then return end
				disconnectRunning(candidate)
			end)
			refresh()
		end

		-- Roblox can create or replace Running well after the old five-second
		-- timeout (especially after avatar/sound-system rebuilds). Keep listening
		-- for the lifetime of this character so its default steps can never layer.
		local descendantConnection = hrp.DescendantAdded:Connect(bind)
		for _, descendant in ipairs(hrp:GetDescendants()) do bind(descendant) end
		char.Destroying:Once(function()
			destroyed = true
			descendantConnection:Disconnect()
			local sounds = {}
			for sound in pairs(soundRecords) do sounds[#sounds + 1] = sound end
			for _, sound in ipairs(sounds) do disconnectRunning(sound) end
		end)
	end)
end
if player.Character then configureDefaultSteps(player.Character) end
player.CharacterAdded:Connect(configureDefaultSteps)

-- ── LEVEL 2 KNEE-DEEP WADE AUDIO ────────────────────────────────────────────
-- The three uploads are complete multi-step phrases with different leading
-- silence and loudness. Playing each at zero made the audible onset drift by
-- almost a second, which sounded like missing strides. Measured windows below
-- isolate and level one heavy wade from each phrase. Five rotating voices launch
-- a take per real stride, while a low resistance loop supplies the continuous
-- knee-deep body as the player pushes through the water.
--
-- Runtime attributes/ValueBases remain useful for live tuning. Put overrides on
-- ReplicatedStorage, Workspace, or ReplicatedStorage.Level2Audio as
-- Level2WadeCore1..3 (the old Level2WadeStep1..3 aliases still work) and
-- Level2WadeResistance. Fallbacks are provenance-clean ProSoundEffects Creator
-- Store assets which were runtime-preloaded in this experience before use.
local LEVEL2_WADE_CORE_SPECS = {
	-- These uploads are multi-second phrases, not sample-tight one-shots. Start
	-- each at its measured first wade and stop before a later phrase/quiet tail.
	{ id = "rbxassetid://9120609652", duration = 2.368, startOffset = 0.43, stopOffset = 1.08, fadeSource = 0.12, gain = 1.00 },
	{ id = "rbxassetid://9120609628", duration = 2.869333, startOffset = 1.28, stopOffset = 1.78, fadeSource = 0.10, gain = 0.74 },
	{ id = "rbxassetid://9120609739", duration = 2.965333, startOffset = 0.55, stopOffset = 0.98, fadeSource = 0.10, gain = 2.60 },
}
local LEVEL2_WADE_RESISTANCE_SPEC = {
	id = "rbxassetid://9120348019",
	duration = 1.431083,
	gain = 1.00,
}
local LEVEL2_WADE_CORE_VOLUME = 0.49
local LEVEL2_WADE_RESISTANCE_VOLUME = 0.095
local LEVEL2_WADE_CORE_VOICE_COUNT = 5
-- Brief direction changes in knee-deep water can drive measured horizontal
-- speed below the movement threshold for a few frames. Keep the cadence phase
-- alive across that physical deceleration; resetting it made the next footfall
-- wait a whole fresh stride and produced an otherwise unexplained ~0.8s hole.
local LEVEL2_WADE_RELEASE_GRACE = 0.30
local LEVEL2_WADE_RELEASE_FADE = 0.16
local LEVEL2_WADE_SURFACE_CHANGE_FADE = 0.08

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
	add(RS)
	add(workspace)
	return sources
end

local function level2CoreId(index, model)
	local names = {
		"Level2WadeCore" .. index,
		"Level2WadeCoreId" .. index,
		"Level2WadeStep" .. index,
		"Level2WadeStepId" .. index,
		"HeavyBootsSplash" .. index,
		"WadeStep" .. index,
		"ShallowWaterStep" .. index,
	}
	for _, source in ipairs(level2Sources(model)) do
		local id = level2ValueId(source, names)
		if id then return id end
	end
	local spec = LEVEL2_WADE_CORE_SPECS[index]
	return spec and spec.id or nil
end

local function level2ResistanceId(model)
	for _, source in ipairs(level2Sources(model)) do
		local id = level2ValueId(source, {
			"Level2WadeResistance",
			"Level2WadeResistanceId",
			"Level2UnderwaterMovement",
		})
		if id then return id end
	end
	return LEVEL2_WADE_RESISTANCE_SPEC.id
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

local function makeLevel2WadeBank(parent, model)
	local bank = {
		bag = {},
		lastTake = nil,
		-- Voices are permanently grouped by take. Reassigning SoundId on every
		-- stride can force a fresh streaming/decode wait even after a nominal
		-- preload, which turns a 0.44-second cadence into audible 0.8-0.9-second
		-- holes. Two voices for the common takes (and one for the shortest take)
		-- are enough to overlap their trimmed windows without ever rebinding the
		-- bundled assets during movement.
		coresByTake = {},
		takeCursors = {},
		playToken = 0,
		resistanceTween = nil,
	}
	bank.cores = {}
	bank.coreTokens = {}
	bank.coreTweens = {}
	for index = 1, LEVEL2_WADE_CORE_VOICE_COUNT do
		local takeIndex = (index - 1) % #LEVEL2_WADE_CORE_SPECS + 1
		local core = Instance.new("Sound")
		core.Name = "Level2PlayerWadeCore" .. index
		core.Looped = false
		core.Volume = 0
		core.SoundId = level2CoreId(takeIndex, model) or ""
		core.Parent = parent
		bank.cores[index] = core
		bank.coreTokens[index] = 0
		bank.coresByTake[takeIndex] = bank.coresByTake[takeIndex] or {}
		table.insert(bank.coresByTake[takeIndex], index)
	end

	local resistance = Instance.new("Sound")
	resistance.Name = "Level2PlayerWadeResistance"
	resistance.Looped = true
	resistance.Volume = 0
	resistance.SoundId = level2ResistanceId(model) or ""
	resistance.Parent = parent
	bank.resistance = resistance

	function bank:nextTake()
		if #self.bag == 0 then
			local available = {}
			for index = 1, #LEVEL2_WADE_CORE_SPECS do
				if level2CoreId(index, model) then
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

	function bank:play(playbackSpeed, volumeScale)
		local take = self:nextTake()
		local spec = take and LEVEL2_WADE_CORE_SPECS[take]
		local id = take and level2CoreId(take, model)
		if not (spec and id) then
			self.bag = {}
			return false
		end

		local speed = playbackSpeed or 1
		local scale = volumeScale or 1
		local pool = self.coresByTake[take]
		if not pool or #pool == 0 then return false end
		self.takeCursors[take] = (self.takeCursors[take] or 0) % #pool + 1
		local coreIndex = pool[self.takeCursors[take]]
		local core = self.cores[coreIndex]
		self.coreTokens[coreIndex] += 1
		local coreToken = self.coreTokens[coreIndex]
		if self.coreTweens[coreIndex] then
			self.coreTweens[coreIndex]:Cancel()
			self.coreTweens[coreIndex] = nil
		end
		self.playToken += 1
		core:Stop()
		-- Runtime overrides are still honoured, but the bundled path (normal live
		-- play) is already bound and preloaded, so this branch never churns IDs.
		if core.SoundId ~= id then core.SoundId = id end
		local usesBundledTake = id == spec.id
		local takeGain = usesBundledTake and spec.gain or 1
		core.Volume = math.clamp(LEVEL2_WADE_CORE_VOLUME * takeGain * scale, 0, 1.2)
		core.PlaybackSpeed = speed
		local startOffset = usesBundledTake and spec.startOffset or 0
		core.TimePosition = math.clamp(startOffset or 0, 0, math.max(0, spec.duration - 0.05))
		core:Play()

		-- Only retain the single useful wade from each longer recording. Aligning
		-- these measured onsets removes the perceived missing stride; the short
		-- fade prevents both hard cuts and a second splash leaking into dry steps.
		-- Unknown runtime overrides retain their full authored take because these
		-- waveform offsets are valid only for the bundled fallback IDs.
		local windowSeconds = usesBundledTake
			and math.max(0.18, (spec.stopOffset - spec.startOffset) / math.max(speed, 0.05))
		local fadeSeconds = usesBundledTake
			and math.min(windowSeconds * 0.35, spec.fadeSource / math.max(speed, 0.05))
		if windowSeconds and fadeSeconds then task.delay(math.max(0.04, windowSeconds - fadeSeconds), function()
			if self.coreTokens[coreIndex] ~= coreToken or not core.Parent or not core.IsPlaying then return end
			local tween = TweenService:Create(
				core,
				TweenInfo.new(fadeSeconds, Enum.EasingStyle.Linear),
				{Volume = 0}
			)
			self.coreTweens[coreIndex] = tween
			tween:Play()
			task.delay(fadeSeconds, function()
				if self.coreTokens[coreIndex] ~= coreToken then return end
				core:Stop()
				self.coreTweens[coreIndex] = nil
			end)
		end) end

		local resistanceId = level2ResistanceId(model)
		if resistanceId then
			if self.resistanceTween then
				self.resistanceTween:Cancel()
				self.resistanceTween = nil
			end
			if self.resistance.SoundId ~= resistanceId then
				self.resistance:Stop()
				self.resistance.SoundId = resistanceId
			end
			self.resistance.Volume = math.clamp(
				LEVEL2_WADE_RESISTANCE_VOLUME * LEVEL2_WADE_RESISTANCE_SPEC.gain * scale,
				0,
				0.2
			)
			self.resistance.PlaybackSpeed = math.clamp(speed * 0.98, 0.86, 0.98)
			if not self.resistance.IsPlaying then
				self.resistance.TimePosition = 0
				self.resistance:Play()
			end
		end
		return true
	end

	function bank:fadeCores(fadeSeconds)
		fadeSeconds = math.max(0.01, tonumber(fadeSeconds) or LEVEL2_WADE_SURFACE_CHANGE_FADE)
		for index, core in ipairs(self.cores) do
			self.coreTokens[index] += 1
			local token = self.coreTokens[index]
			if self.coreTweens[index] then
				self.coreTweens[index]:Cancel()
				self.coreTweens[index] = nil
			end
			if core.IsPlaying and core.Volume > 0 then
				local tween = TweenService:Create(
					core,
					TweenInfo.new(fadeSeconds, Enum.EasingStyle.Linear),
					{Volume = 0}
				)
				self.coreTweens[index] = tween
				tween:Play()
				task.delay(fadeSeconds, function()
					if self.coreTokens[index] ~= token then return end
					core:Stop()
					self.coreTweens[index] = nil
				end)
			else
				core:Stop()
			end
		end
	end

	function bank:release(stopCoreVoices)
		if stopCoreVoices then self:fadeCores(LEVEL2_WADE_SURFACE_CHANGE_FADE) end
		if not self.resistance.IsPlaying or self.resistanceTween then return end
		self.playToken += 1
		local token = self.playToken
		self.resistanceTween = TweenService:Create(
			self.resistance,
			TweenInfo.new(LEVEL2_WADE_RELEASE_FADE, Enum.EasingStyle.Linear),
			{Volume = 0}
		)
		self.resistanceTween:Play()
		task.delay(LEVEL2_WADE_RELEASE_FADE, function()
			if self.playToken ~= token then return end
			self.resistance:Stop()
			self.resistanceTween = nil
		end)
	end

	function bank:stop()
		self.bag = {}
		self.playToken += 1
		if self.resistanceTween then
			self.resistanceTween:Cancel()
			self.resistanceTween = nil
		end
		for index, core in ipairs(self.cores) do
			self.coreTokens[index] += 1
			if self.coreTweens[index] then
				self.coreTweens[index]:Cancel()
				self.coreTweens[index] = nil
			end
			core.Volume = 0
			core:Stop()
		end
		self.resistance.Volume = 0
		self.resistance:Stop()
	end

	return bank
end

local level2PlayerBank = makeLevel2WadeBank(SoundService, nil)
task.spawn(function()
	-- Preload the exact persistent instances that will play. A disposable warmer
	-- proves an asset can load, but it does not guarantee that a different Sound
	-- which rebinds that id on the stride frame can begin immediately.
	local sounds = table.clone(level2PlayerBank.cores)
	table.insert(sounds, level2PlayerBank.resistance)
	pcall(function() ContentProvider:PreloadAsync(sounds) end)
end)
local level2WaterRay = RaycastParams.new()
level2WaterRay.FilterType = Enum.RaycastFilterType.Exclude
level2WaterRay.IgnoreWater = false
local level2PlayerLastPosition = nil
local level2PlayerStepClock = 0
local level2WadeMovingUntil = 0
local level2PlayerWasWet = false

-- Dry-tile footsteps: the poolside sound for walking where there is NO water
-- underfoot. An authored library id still overrides this, while an empty slot
-- falls back to Roblox's bundled plastic/tile footstep loop so dry walkways can
-- never become silent merely because no uploaded asset was configured.
local LEVEL2_DRY_SLOT = "Level 2 Player Dry Tile Walking Sound"
local LEVEL2_DRY_FALLBACK_ID = "rbxasset://sounds/action_footsteps_plastic.mp3"
local LEVEL2_DRY_VOLUME = 0.34
local level2DryTileId = LEVEL2_DRY_FALLBACK_ID
local level2DryUsesFallback = true
local level2DryLoop = Instance.new("Sound")
level2DryLoop.Name = "Level2PlayerDryTileLoop"
level2DryLoop.Looped = true
level2DryLoop.Volume = 0
level2DryLoop.SoundId = level2DryTileId
level2DryLoop.Parent = SoundService
local level2DryVoices = {}
local level2DryCursor = 0
for index = 1, 4 do
	local voice = Instance.new("Sound")
	voice.Name = "Level2PlayerDryTileVoice" .. index
	voice.Looped = false
	voice.Volume = 0
	voice.Parent = SoundService
	level2DryVoices[index] = voice
end
task.spawn(function()
	local library = RS:WaitForChild("Level 2 Sound Library", 30)
	if not library then return end
	local slot = library:WaitForChild(LEVEL2_DRY_SLOT, 30)
	if not (slot and slot:IsA("ValueBase")) then return end
	local function refresh()
		local configured = level2SoundId(slot.Value)
		local replacement = configured or LEVEL2_DRY_FALLBACK_ID
		local usesFallback = configured == nil
		if replacement == level2DryTileId and usesFallback == level2DryUsesFallback then return end
		level2DryLoop:Stop()
		for _, voice in ipairs(level2DryVoices) do voice:Stop() end
		level2DryTileId = replacement
		level2DryUsesFallback = usesFallback
		level2DryLoop.SoundId = replacement
	end
	slot.Changed:Connect(refresh)
	refresh()
end)

local function level2PlayDryStep(flatSpeed)
	if not level2DryTileId then return end
	local volume = LEVEL2_DRY_VOLUME * math.clamp(0.84 + flatSpeed / 44, 0.9, 1.18)
	if level2DryUsesFallback then
		if level2DryLoop.SoundId ~= level2DryTileId then
			level2DryLoop:Stop()
			level2DryLoop.SoundId = level2DryTileId
		end
		level2DryLoop.Volume = volume
		level2DryLoop.PlaybackSpeed = math.clamp(0.82 + flatSpeed / 34, 0.9, 1.35)
		if not level2DryLoop.IsPlaying then level2DryLoop:Play() end
		return
	end

	-- Authored slot overrides preserve the original one-shot contract and launch
	-- once per cadence instead of being forced into an arbitrary loop.
	level2DryLoop:Stop()
	level2DryCursor = level2DryCursor % #level2DryVoices + 1
	local voice = level2DryVoices[level2DryCursor]
	voice:Stop()
	voice.SoundId = level2DryTileId
	voice.Volume = volume
	voice.PlaybackSpeed = 0.96 + math.random() * 0.08
	voice.TimePosition = 0
	voice:Play()
end

local function level2StopDrySteps()
	level2DryLoop.Volume = 0
	level2DryLoop:Stop()
	for _, voice in ipairs(level2DryVoices) do voice:Stop() end
end

-- footing states in which NEITHER wet nor dry steps may play: slide rides have
-- their own audio ("Level 2 Slide Rush"), and airborne/seated/dead make no
-- footfalls of any kind
local function level2FootingBlocked(humanoid)
	if player.Character
		and player.Character:GetAttribute("Level2_ForcedSliding") == true then
		return true
	end
	local state = humanoid:GetState()
	return state == Enum.HumanoidStateType.Swimming
		or state == Enum.HumanoidStateType.Freefall
		or state == Enum.HumanoidStateType.Jumping
		or state == Enum.HumanoidStateType.FallingDown
		or state == Enum.HumanoidStateType.Dead
		or state == Enum.HumanoidStateType.Seated
end

local function level2WaterAt(position, rootY)
	local hit = workspace:Raycast(position + Vector3.new(0, 1.5, 0), Vector3.new(0, -6.5, 0), level2WaterRay)
	if not hit or hit.Material ~= Enum.Material.Water then return false end
	local rootAboveSurface = rootY - hit.Position.Y
	return rootAboveSurface >= 0.6 and rootAboveSurface <= 4.25
end

local function level2ShallowWater(root)
	local character = player.Character
	level2WaterRay.FilterDescendantsInstances = { character }

	-- Sample the actual feet first. A root-only ray misclassified the narrow dry
	-- ledges in Level 2 when the player's centre stayed over the ledge but a boot
	-- landed in the water. R6 names are included for avatar compatibility.
	local sampledFoot = false
	if character then
		for _, name in ipairs({ "LeftFoot", "RightFoot", "Left Leg", "Right Leg" }) do
			local foot = character:FindFirstChild(name)
			if foot and foot:IsA("BasePart") then
				sampledFoot = true
				if level2WaterAt(foot.Position, root.Position.Y) then return true end
			end
		end
	end
	if sampledFoot then return false end
	return level2WaterAt(root.Position, root.Position.Y)
end

local function level2WadeVolumeScale(humanoid)
	local character = player.Character
	local intendedSpeed = character and character:GetAttribute("Level2_DesiredWalkSpeed")
	if typeof(intendedSpeed) ~= "number" then intendedSpeed = humanoid.WalkSpeed end
	if intendedSpeed <= 10.5 then return 0.68 end -- crouch
	if intendedSpeed >= 22 then return 1.18 end -- sprint
	return 0.94 -- walk
end

local function level2WadePlaybackSpeed(flatSpeed)
	-- Keep pitch movement narrow and below natural speed for heavier boots. The
	-- player's pace still nudges the authored phrase faster while sprinting.
	local variation = (math.random() - 0.5) * 0.024
	return math.clamp(0.88 + flatSpeed * 0.0035 + variation, 0.88, 0.98)
end

RunService.Heartbeat:Connect(function(dt)
	local hum, root = aliveParts()
	if player:GetAttribute("InRound") ~= true
		or workspace:GetAttribute("SelectedLevel") ~= 2 or not hum or not root then
		level2PlayerLastPosition = root and root.Position or nil
		level2PlayerStepClock = 0
		level2WadeMovingUntil = 0
		level2PlayerBank:release(level2PlayerWasWet)
		level2PlayerWasWet = false
		level2StopDrySteps()
		return
	end

	local now = root.Position
	if not level2PlayerLastPosition then
		level2PlayerLastPosition = now
		return
	end
	local displacement = Vector3.new(now.X - level2PlayerLastPosition.X, 0, now.Z - level2PlayerLastPosition.Z).Magnitude
	level2PlayerLastPosition = now
	local intendedSpeed = player.Character and player.Character:GetAttribute("Level2_DesiredWalkSpeed")
	if typeof(intendedSpeed) ~= "number" then intendedSpeed = 0 end
	-- A fixed seven-stud threshold treated a normal low-FPS sprint frame as a
	-- teleport. Scale the allowance with elapsed time so long render stalls
	-- cannot manufacture a teleport reset.
	-- At ordinary frame times a real relocation still clears immediately.
	local teleportThreshold = math.max(
		7,
		2 + math.max(26, hum.WalkSpeed, intendedSpeed) * math.max(dt, 0) * 1.75
	)
	if displacement > teleportThreshold then
		level2PlayerStepClock = 0
		level2WadeMovingUntil = 0
		level2PlayerBank:stop()
		level2PlayerWasWet = false
		level2StopDrySteps()
		return
	end
	local flatSpeed = dt > 0 and displacement / dt or 0
	local footingBlocked = level2FootingBlocked(hum)
	if flatSpeed < 1.35 or footingBlocked then
		if footingBlocked then
			level2PlayerStepClock = 0
			level2WadeMovingUntil = 0
			level2PlayerBank:release(level2PlayerWasWet)
			level2PlayerWasWet = false
		elseif os.clock() >= level2WadeMovingUntil then
			level2PlayerStepClock = 0
			level2PlayerBank:release()
		end
		-- During the short release grace, deliberately retain the accumulated
		-- cadence phase. If movement resumes, the next real displacement completes
		-- the stride instead of starting from zero; no sound is emitted while the
		-- player is actually stationary.
		level2StopDrySteps()
		return
	end
	local wet = level2ShallowWater(root)
	if not wet and hum.FloorMaterial == Enum.Material.Air then
		-- nothing underfoot at all (running off a deck edge): no steps
		level2PlayerStepClock = math.min(level2PlayerStepClock, 0.12)
		level2WadeMovingUntil = 0
		level2PlayerBank:release(level2PlayerWasWet)
		level2PlayerWasWet = false
		level2StopDrySteps()
		return
	end
	if wet then
		level2PlayerWasWet = true
		level2WadeMovingUntil = os.clock() + LEVEL2_WADE_RELEASE_GRACE
		level2StopDrySteps()
	else
		level2WadeMovingUntil = 0
		level2PlayerBank:release(level2PlayerWasWet)
		level2PlayerWasWet = false
	end

	local cadence = math.clamp(0.68 - flatSpeed * 0.015, 0.30, 0.56)
	level2PlayerStepClock += dt
	if level2PlayerStepClock >= cadence then
		level2PlayerStepClock %= cadence
		if wet then
			-- Every stride launches a take on the next voice; long silent file tails
			-- never suppress the following audible footfall.
			level2PlayerBank:play(
				level2WadePlaybackSpeed(flatSpeed),
				level2WadeVolumeScale(hum)
			)
		else
			-- dry tile: same cadence clock, the dedicated dry-tile take
			level2PlayDryStep(flatSpeed)
		end
	end
end)

workspace:GetAttributeChangedSignal("SelectedLevel"):Connect(function()
	if workspace:GetAttribute("SelectedLevel") ~= 1 then elevatorSound:Stop() end
	if workspace:GetAttribute("SelectedLevel") == 2 then
		steps.Volume = 0
		level2PlayerStepClock = 0
	else
		level2WadeMovingUntil = 0
		level2PlayerBank:stop()
		level2PlayerWasWet = false
		level2StopDrySteps()
	end
end)

player:GetAttributeChangedSignal("InRound"):Connect(function()
	if player:GetAttribute("InRound") ~= true then
		-- Do not let a custom fade or a water one-shot overlap the lobby's
		-- footstep handling.
		steps.Volume = 0
		level2PlayerBank:stop()
		level2StopDrySteps()
		level2PlayerLastPosition = nil
		level2PlayerStepClock = 0
		level2WadeMovingUntil = 0
		level2PlayerWasWet = false
	end
end)
