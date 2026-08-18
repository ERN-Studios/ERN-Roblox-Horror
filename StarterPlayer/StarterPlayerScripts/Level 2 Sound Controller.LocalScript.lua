-- Level 2 Sound Controller
-- All audio for the Sunken Leisure Complex lives here, in one small file.
--
-- ══════════════════════ HOW TO TWEAK (read me!) ══════════════════════════
-- 1. Sound IDs live in ReplicatedStorage["Level 2 Sound Library"] as
--    StringValues. Paste a Roblox asset id into a slot's Value (just the
--    number, or the full rbxassetid:// url — both work). Empty = silent.
-- 2. Volumes: change the numbers in AMBIENCE, CUE_VOLUMES, and the random profiles below.
-- 3. The server fires one-shot cues through the "Level 2 Sound Event"
--    RemoteEvent; the cue name is the library slot name. Cues in use today:
--       "Level 2 Pump Start"     — a pump comes online
--       "Level 2 Drain Rush"     — a corridor drains
--       "Level 2 Pressure Door"  — the grand hall unseals
--       "Level 2 Slide Rush"     — riding the exit flume
-- 4. Ambience loops below play while you are in a Level 2 round.
-- ═════════════════════════════════════════════════════════════════════════

local Players = game:GetService("Players")
local ReplicatedStorage = game:GetService("ReplicatedStorage")
local SoundService = game:GetService("SoundService")
local ContentProvider = game:GetService("ContentProvider")
local RunService = game:GetService("RunService")
local Debris = game:GetService("Debris")

local player = Players.LocalPlayer
local rng = Random.new()

-- Looping beds: {library slot name, target volume}
local AMBIENCE = {
	{"Level 2 Room Tone", 0.126},
	{"Level 2 Ventilation Hum", 0.09},
	{"Level 2 Distant Water", 0.15},
}
local CUE_SLOTS = {
	"Level 2 Pump Start",
	"Level 2 Drain Rush",
	"Level 2 Pressure Door",
	"Level 2 Slide Rush",
}
local MONSTER_SLOTS = {
	"Level 2 Distant Monster-Like Pipe Groan 1",
	"Level 2 Distant Monster-Like Pipe Groan 2",
	"Level 2 Distant Monster-Like Pipe Groan 3",
	"Level 2 Distant Monster-Like Pipe Groan 4",
}
local RANDOM_AMBIENCE_SLOTS = {
	"Level 2 Water Drop",
	"Level 2 Distant Splash",
	"Level 2 Drain Gurgle",
	"Level 2 Pipe Groan",
}
local COMMON_AMBIENCE = {
	{Key = "WaterDrop", Slot = "Level 2 Water Drop", Weight = 4,
		Anchor = "Corridor", AnchorMin = 8, AnchorMax = 44,
		VerticalMin = 2, VerticalMax = 9, Volume = .22,
		RollOffMin = 3, RollOffMax = 48, PitchMin = .97, PitchMax = 1.04, BusySeconds = 3},
	{Key = "DistantSplash", Slot = "Level 2 Distant Splash", Weight = 3,
		Anchor = "WetHall", AnchorMin = 45, AnchorMax = 125,
		VerticalMin = -4, VerticalMax = 2, Volume = .30,
		RollOffMin = 6, RollOffMax = 125, PitchMin = .98, PitchMax = 1.02, BusySeconds = 5},
	{Key = "DrainGurgle", Slot = "Level 2 Drain Gurgle", Weight = 2,
		Anchor = "RunningPump", AnchorMin = 0, AnchorMax = 105,
		VerticalMin = -3, VerticalMax = 1, Volume = .28,
		RollOffMin = 5, RollOffMax = 90, PitchMin = .97, PitchMax = 1.03, BusySeconds = 5},
	{Key = "PipeGroan", Slot = "Level 2 Pipe Groan", Weight = 2,
		Anchor = "DistantPipe", AnchorMin = 50, AnchorMax = 145,
		VerticalMin = 4, VerticalMax = 14, Volume = .31,
		RollOffMin = 8, RollOffMax = 145, PitchMin = .98, PitchMax = 1.02, BusySeconds = 7},
}
local PRELOAD_SLOTS = {}
for _, slotName in ipairs(CUE_SLOTS) do table.insert(PRELOAD_SLOTS, slotName) end
for _, slotName in ipairs(RANDOM_AMBIENCE_SLOTS) do table.insert(PRELOAD_SLOTS, slotName) end
-- Slidemouth owns these recordings exclusively; this controller only warms them.
for _, slotName in ipairs(MONSTER_SLOTS) do table.insert(PRELOAD_SLOTS, slotName) end

local DEFAULT_CUE_VOLUME = 0.3
local CUE_VOLUMES = {
    ["Level 2 Pressure Door"] = 1.1,
}
local COMMON_FIRST_DELAY_MIN, COMMON_FIRST_DELAY_MAX = 3, 7
local COMMON_DELAY_MIN, COMMON_DELAY_MAX = 6, 12
local MONSTER_FIRST_DELAY = 30
local MONSTER_DELAY_MIN, MONSTER_DELAY_MAX = 14, 22
local FADE_SECONDS = 1.5
local authoredBusyUntil = 0
local ambientBusyUntil = 0
local authoredCues = {}
local ALLOWED_CUES = {}
for _, slotName in ipairs(CUE_SLOTS) do ALLOWED_CUES[slotName] = true end

local library = ReplicatedStorage:WaitForChild("Level 2 Sound Library")
local event = ReplicatedStorage:WaitForChild("Level 2 Sound Event")

local function resolveId(slotName)
	local slot = library and library:FindFirstChild(slotName)
	local raw = slot and slot:IsA("StringValue") and slot.Value or ""
	raw = tostring(raw):gsub("%s", "")
	if raw == "" then return nil end
	if raw:match("^%d+$") then return "rbxassetid://" .. raw end
	return raw
end

-- Warm the authored one-shot clips while the player is still exploring, so
-- a first-time cue does not get paused at position zero while its asset finishes loading.
task.spawn(function()
	local preloadSounds = {}
	for _, slotName in ipairs(PRELOAD_SLOTS) do
		local id = resolveId(slotName)
		if id then
			local sound = Instance.new("Sound")
			sound.Name = "Level 2 Preload - " .. slotName
			sound.SoundId = id
			sound.Volume = 0
			sound.Parent = SoundService
			table.insert(preloadSounds, sound)
		end
	end

	if #preloadSounds > 0 then
		pcall(function()
			ContentProvider:PreloadAsync(preloadSounds)
		end)
	end

	for _, sound in ipairs(preloadSounds) do
		sound:Destroy()
	end
end)

local function active()
	return workspace:GetAttribute("SelectedLevel") == 2
		and workspace:GetAttribute("RoundActive") == true
		and workspace:GetAttribute("WorldGenerated") == true
		and player:GetAttribute("InRound") == true
		and player:GetAttribute("Escaped") ~= true
		and player:GetAttribute("Spectating") ~= true
		and player:GetAttribute("IsSpectating") ~= true
end

-- Contextual environmental one-shots. These are client-local and spatial so every
-- player gets an unpredictable soundscape without adding replicated emitters.
local ambientFolder
local spatialCueFolder
local ambientWorld
local randomSessionActive = false
local ambientAnchors = {Corridor = {}, WetHall = {}, PumpPipe = {}}
local ambientAnchorSeen = {}
local ambientConnections = {}
local nextCommonAt = math.huge
local nextMonsterAt = math.huge
local lastCommonKey
local monsterBag = {}
local lastMonsterSlot
local lastSlidemouthWarningSerial = 0
local lastSlidemouthScreamSerial = 0
local wasSlidemouthActive = false

local function disconnectAmbientConnections()
	for _, connection in ipairs(ambientConnections) do
		connection:Disconnect()
	end
	ambientConnections = {}
end

local function clearAmbientEmitters()
	if ambientFolder and ambientFolder.Parent then ambientFolder:Destroy() end
	ambientFolder = nil
	ambientBusyUntil = 0
end

local function clearSpatialCueEmitters()
	if spatialCueFolder and spatialCueFolder.Parent then spatialCueFolder:Destroy() end
	spatialCueFolder = nil
end

local function stopRandomSession()
	disconnectAmbientConnections()
	clearAmbientEmitters()
	clearSpatialCueEmitters()
	ambientWorld = nil
	randomSessionActive = false
	ambientAnchors = {Corridor = {}, WetHall = {}, PumpPipe = {}}
	ambientAnchorSeen = {}
	nextCommonAt = math.huge
	nextMonsterAt = math.huge
	lastCommonKey = nil
	monsterBag = {}
	lastMonsterSlot = nil
	lastSlidemouthWarningSerial = 0
	lastSlidemouthScreamSerial = 0
	wasSlidemouthActive = false
	authoredBusyUntil = 0
end

local function classifyAmbientAnchor(instance)
	if not (instance:IsA("BasePart") and not ambientAnchorSeen[instance]) then return end
	local name = instance.Name
	if name:find("Level 2 Corridor Vault Light", 1, true) == 1 then
		ambientAnchorSeen[instance] = true
		table.insert(ambientAnchors.Corridor, instance)
	elseif name:find("Level 2 Navigation Node ", 1, true) == 1
		and instance:GetAttribute("Level2_Role") ~= "Kids Area" then
		ambientAnchorSeen[instance] = true
		table.insert(ambientAnchors.WetHall, instance)
	elseif name == "Level 2 Pump Intake Pipe" then
		ambientAnchorSeen[instance] = true
		table.insert(ambientAnchors.PumpPipe, instance)
	end
end

local function startRandomSession(world)
	stopRandomSession()
	randomSessionActive = true
	ambientWorld = world
	nextCommonAt = os.clock() + rng:NextNumber(COMMON_FIRST_DELAY_MIN, COMMON_FIRST_DELAY_MAX)
	nextMonsterAt = os.clock() + MONSTER_FIRST_DELAY
	local slidemouthState = ReplicatedStorage:FindFirstChild("Level 2 State")
	lastSlidemouthWarningSerial = slidemouthState
		and (tonumber(slidemouthState:GetAttribute("Level2_SlidemouthWarningSerial")) or 0) or 0
	lastSlidemouthScreamSerial = slidemouthState
		and (tonumber(slidemouthState:GetAttribute("Level2_SlidemouthScreamSerial")) or 0) or 0
	wasSlidemouthActive = slidemouthState
		and slidemouthState:GetAttribute("Level2_SlidemouthActive") == true or false
	for _, instance in ipairs(world:GetDescendants()) do
		classifyAmbientAnchor(instance)
	end
	table.insert(ambientConnections, world.DescendantAdded:Connect(classifyAmbientAnchor))
	table.insert(ambientConnections, world.AncestryChanged:Connect(function(_, parent)
		if not parent and ambientWorld == world then stopRandomSession() end
	end))
end

local function randomActive()
	return workspace:GetAttribute("SelectedLevel") == 2
		and workspace:GetAttribute("RoundActive") == true
		and workspace:GetAttribute("WorldGenerated") == true
		and player:GetAttribute("InRound") == true
		and player:GetAttribute("Escaped") ~= true
		and workspace:FindFirstChild("Level 2 Generated World") ~= nil
end

local function syncRandomSession()
	local world = workspace:FindFirstChild("Level 2 Generated World")
	if not randomActive() or not world then
		if randomSessionActive or ambientWorld or ambientFolder or spatialCueFolder then stopRandomSession() end
		return false
	end
	if not randomSessionActive or ambientWorld ~= world then startRandomSession(world) end
	return true
end

local function rootPart()
	local character = player.Character
	local humanoid = character and character:FindFirstChildOfClass("Humanoid")
	local root = character and character:FindFirstChild("HumanoidRootPart")
	if not (humanoid and humanoid.Health > 0 and root) then return nil end
	return root
end

local function pumpPipeIsRunning(pipe)
	local current = pipe.Parent
	while current and current ~= ambientWorld do
		if current:IsA("Model") and current:GetAttribute("Level2_PumpRunning") == true then
			return true
		end
		current = current.Parent
	end
	return false
end

local function hasRunningPumpAnchor()
	for _, pipe in ipairs(ambientAnchors.PumpPipe) do
		if pipe.Parent and ambientWorld and pipe:IsDescendantOf(ambientWorld)
			and pumpPipeIsRunning(pipe) then
			return true
		end
	end
	return false
end

local function chooseAnchor(list, origin, minimumDistance, maximumDistance, predicate)
	local chosen
	local count = 0
	for _, anchor in ipairs(list) do
		if anchor.Parent and ambientWorld and anchor:IsDescendantOf(ambientWorld)
			and (not predicate or predicate(anchor)) then
			local distance = (anchor.Position - origin).Magnitude
			if distance >= minimumDistance and distance <= maximumDistance then
				count += 1
				if rng:NextInteger(1, count) == 1 then chosen = anchor end
			end
		end
	end
	return chosen
end

local function fallbackPosition(origin, profile)
	local angle = rng:NextNumber(0, math.pi * 2)
	local distance = rng:NextNumber(profile.AnchorMin, profile.AnchorMax)
	local vertical = rng:NextNumber(profile.VerticalMin or -3, profile.VerticalMax or 7)
	return origin + Vector3.new(math.cos(angle) * distance, vertical, math.sin(angle) * distance)
end

local function positionForProfile(profile, root)
	local anchor
	if profile.Anchor == "Corridor" or profile.Anchor == "DistantPipe" then
		anchor = chooseAnchor(ambientAnchors.Corridor, root.Position,
			profile.AnchorMin, profile.AnchorMax)
	elseif profile.Anchor == "WetHall" then
		anchor = chooseAnchor(ambientAnchors.WetHall, root.Position,
			profile.AnchorMin, profile.AnchorMax)
	elseif profile.Anchor == "RunningPump" then
		anchor = chooseAnchor(ambientAnchors.PumpPipe, root.Position,
			profile.AnchorMin, profile.AnchorMax, pumpPipeIsRunning)
		if not anchor then return nil end
	end
	if anchor then
		return anchor.Position + Vector3.new(
			rng:NextNumber(-1.5, 1.5),
			rng:NextNumber(-.5, 1.5),
			rng:NextNumber(-1.5, 1.5))
	end
	return fallbackPosition(root.Position, profile)
end

local function ensureAmbientFolder()
	if ambientFolder and ambientFolder.Parent then return ambientFolder end
	ambientFolder = Instance.new("Folder")
	ambientFolder.Name = "Level 2 Temporary Audio"
	ambientFolder:SetAttribute("Level2_ClientOnlyAudio", true)
	ambientFolder.Parent = workspace
	return ambientFolder
end

local function playRandomSound(slotName, profile)
	if not syncRandomSession() then return false end
	local id = resolveId(slotName)
	local root = rootPart()
	if not (id and root) then return false end
	local position = positionForProfile(profile, root)
	if not position then return false end

	local emitter = Instance.new("Part")
	emitter.Name = "Level 2 Random Audio Emitter"
	emitter.Anchored = true
	emitter.CanCollide = false
	emitter.CanTouch = false
	emitter.CanQuery = false
	emitter.CastShadow = false
	emitter.Transparency = 1
	emitter.Size = Vector3.new(.2, .2, .2)
	emitter.Position = position
	emitter.Parent = ensureAmbientFolder()

	local sound = Instance.new("Sound")
	sound.Name = "Level 2 Random - " .. slotName
	sound.SoundId = id
	sound.Volume = profile.Volume
	sound.PlaybackSpeed = rng:NextNumber(profile.PitchMin or .98, profile.PitchMax or 1.02)
	sound.RollOffMode = Enum.RollOffMode.InverseTapered
	sound.RollOffMinDistance = profile.RollOffMin
	sound.RollOffMaxDistance = profile.RollOffMax
	sound.Parent = emitter
	sound:Play()

	ambientBusyUntil = os.clock() + profile.BusySeconds
	Debris:AddItem(emitter, 25)
	return true
end

local function commonProfileEligible(profile)
	return profile.Anchor ~= "RunningPump" or hasRunningPumpAnchor()
end

local function weightedCommonProfile(excludeLast)
	local totalWeight = 0
	for _, profile in ipairs(COMMON_AMBIENCE) do
		if commonProfileEligible(profile)
			and (not excludeLast or profile.Key ~= lastCommonKey) then
			totalWeight += profile.Weight
		end
	end
	if totalWeight <= 0 then return nil end
	local pick = rng:NextNumber(0, totalWeight)
	for _, profile in ipairs(COMMON_AMBIENCE) do
		if commonProfileEligible(profile)
			and (not excludeLast or profile.Key ~= lastCommonKey) then
			pick -= profile.Weight
			if pick <= 0 then return profile end
		end
	end
	return nil
end

local function nextMonsterSlot()
	if #monsterBag == 0 then
		for _, slotName in ipairs(MONSTER_SLOTS) do table.insert(monsterBag, slotName) end
		for index = #monsterBag, 2, -1 do
			local swapIndex = rng:NextInteger(1, index)
			monsterBag[index], monsterBag[swapIndex] = monsterBag[swapIndex], monsterBag[index]
		end
		if #monsterBag > 1 and monsterBag[#monsterBag] == lastMonsterSlot then
			monsterBag[#monsterBag], monsterBag[1] = monsterBag[1], monsterBag[#monsterBag]
		end
	end
	local slotName = table.remove(monsterBag)
	lastMonsterSlot = slotName
	return slotName
end

local MONSTER_PROFILE = {
	Anchor = "DistantPipe", AnchorMin = 85, AnchorMax = 175,
	VerticalMin = 4, VerticalMax = 16,
	Volume = 1.25, RollOffMin = 30, RollOffMax = 240,
	PitchMin = .98, PitchMax = 1.02, BusySeconds = 10,
}

local function slidemouthOwnsMonsterLane()
	-- The four monster recordings are pump responses only. Detached/random
	-- corridor groans are permanently disabled.
	return true
end

local function updateRandomAmbience()
	if not syncRandomSession() then return end
	local now = os.clock()
	local slidemouthState = ReplicatedStorage:FindFirstChild("Level 2 State")
	local warningSerial = slidemouthState
		and (tonumber(slidemouthState:GetAttribute("Level2_SlidemouthWarningSerial")) or 0) or 0
	local screamSerial = slidemouthState
		and (tonumber(slidemouthState:GetAttribute("Level2_SlidemouthScreamSerial")) or 0) or 0
	local slidemouthActive = slidemouthState
		and slidemouthState:GetAttribute("Level2_SlidemouthActive") == true or false
	local forcedScream = warningSerial > lastSlidemouthWarningSerial
		or screamSerial > lastSlidemouthScreamSerial
	if warningSerial < lastSlidemouthWarningSerial then
		lastSlidemouthWarningSerial = warningSerial
	elseif warningSerial > lastSlidemouthWarningSerial then
		lastSlidemouthWarningSerial = warningSerial
	end
	if screamSerial < lastSlidemouthScreamSerial then
		lastSlidemouthScreamSerial = screamSerial
	elseif screamSerial > lastSlidemouthScreamSerial then
		lastSlidemouthScreamSerial = screamSerial
	end
	wasSlidemouthActive = slidemouthActive
	if forcedScream then
		-- Remove any detached fake groan already sounding before the real
		-- creature's pump response starts.
		clearAmbientEmitters()
		ambientBusyUntil = now + 8
		nextMonsterAt = now + 10
	end
	local slidemouthOwnsLane = slidemouthOwnsMonsterLane()
	if slidemouthOwnsLane then
		nextMonsterAt = math.max(nextMonsterAt, now + 2)
	end

	-- Monster groans get priority once due. If another sound is busy, keep them
	-- due so they play as soon as the mix clears instead of losing the event.
	if not slidemouthOwnsLane
		and now >= nextMonsterAt
		and now >= authoredBusyUntil
		and now >= ambientBusyUntil then
		if playRandomSound(nextMonsterSlot(), MONSTER_PROFILE) then
			nextMonsterAt = os.clock() + rng:NextNumber(MONSTER_DELAY_MIN, MONSTER_DELAY_MAX)
		else
			nextMonsterAt = now + 2
		end
	end

	if now >= nextCommonAt
		and now >= authoredBusyUntil
		and now >= ambientBusyUntil then
		local profile = weightedCommonProfile(true) or weightedCommonProfile(false)
		if profile and playRandomSound(profile.Slot, profile) then
			lastCommonKey = profile.Key
			nextCommonAt = os.clock() + rng:NextNumber(COMMON_DELAY_MIN, COMMON_DELAY_MAX)
		else
			nextCommonAt = now + 2
		end
	end
end

RunService.Heartbeat:Connect(updateRandomAmbience)

-- Ambience loops (created lazily so empty slots cost nothing).
local loops = {}
local function ensureLoop(slotName, volume)
	local id = resolveId(slotName)
	if not id then return nil end
	local loop = loops[slotName]
	if not loop then
		loop = Instance.new("Sound")
		loop.Name = "Level 2 Ambience - " .. slotName
		loop.Looped = true
		loop.Volume = 0
		loop.Parent = SoundService
		loops[slotName] = loop
	end
	if loop.SoundId ~= id then loop.SoundId = id end
	if not loop.IsPlaying then loop:Play() end
	return loop, volume
end

RunService.Heartbeat:Connect(function(dt)
	local blend = math.clamp(dt / FADE_SECONDS, 0, 1)
	for _, entry in ipairs(AMBIENCE) do
		local slotName, volume = entry[1], entry[2]
		if active() then
			local loop = ensureLoop(slotName, volume)
			if loop then
				loop.Volume += (volume - loop.Volume) * blend
			end
		else
			local loop = loops[slotName]
			if loop then
				loop.Volume += (0 - loop.Volume) * blend
				if loop.Volume < .01 and loop.IsPlaying then loop:Stop() end
			end
		end
	end
end)

-- Pressure doors use a true world-space origin supplied by the server because
-- StreamingEnabled may keep the distant door parts out of this client's DataModel.
local function ensureSpatialCueFolder()
	if spatialCueFolder and spatialCueFolder.Parent then return spatialCueFolder end
	spatialCueFolder = Instance.new("Folder")
	spatialCueFolder.Name = "Level 2 Temporary Spatial Cues"
	spatialCueFolder:SetAttribute("Level2_ClientOnlyAudio", true)
	spatialCueFolder.Parent = workspace
	return spatialCueFolder
end

local function spatialEmitter(name, position)
	local emitter = Instance.new("Part")
	emitter.Name = name
	emitter.Anchored = true
	emitter.CanCollide = false
	emitter.CanTouch = false
	emitter.CanQuery = false
	emitter.CastShadow = false
	emitter.Transparency = 1
	emitter.Size = Vector3.new(.2, .2, .2)
	emitter.Position = position
	emitter.Parent = ensureSpatialCueFolder()
	return emitter
end

local function nearestDoorPosition(context, root)
	local bestPosition
	local bestDistance = math.huge
	local function consider(position)
		if typeof(position) ~= "Vector3" then return end
		local distance = (root.Position - position).Magnitude
		if distance < bestDistance then
			bestPosition = position
			bestDistance = distance
		end
	end

	if typeof(context) == "table" and typeof(context.DoorPositions) == "table" then
		for _, position in ipairs(context.DoorPositions) do consider(position) end
	end
	if bestPosition then return bestPosition, bestDistance end

	local world = workspace:FindFirstChild("Level 2 Generated World")
	if world then
		for _, descendant in ipairs(world:GetDescendants()) do
			if descendant:IsA("BasePart")
				and descendant.Name:match("^Level 2 Pressure Door %d+$") then
				consider(descendant.Position)
			end
		end
	end
	return bestPosition, bestDistance
end

local function corridorEchoAnchors(origin)
	local nearestByCorridor = {}
	for _, anchor in ipairs(ambientAnchors.Corridor) do
		if anchor and anchor.Parent then
			local distance = (origin - anchor.Position).Magnitude
			if distance <= 600 then
				local existing = nearestByCorridor[anchor.Name]
				if not existing or distance < existing.Distance then
					nearestByCorridor[anchor.Name] = {Part = anchor, Distance = distance}
				end
			end
		end
	end
	local choices = {}
	for _, record in pairs(nearestByCorridor) do table.insert(choices, record) end
	table.sort(choices, function(a, b) return a.Distance < b.Distance end)
	local anchors = {}
	for index = 1, math.min(6, #choices) do
		table.insert(anchors, choices[index].Part)
	end
	return anchors
end

local function playPressureDoorCue(id, context)
	local root = rootPart()
	if not root then return false end
	local doorPosition, doorDistance = nearestDoorPosition(context, root)
	if not doorPosition then return false end

	clearAmbientEmitters()
	clearSpatialCueEmitters()
	local cueFolder = ensureSpatialCueFolder()
	local primaryEmitter = spatialEmitter("Level 2 Pressure Door Primary Emitter", doorPosition)
	local primary = Instance.new("Sound")
	primary.Name = "Level 2 Spatial Cue - Level 2 Pressure Door"
	primary.SoundId = id
	primary.Volume = 2.4
	primary.RollOffMode = Enum.RollOffMode.InverseTapered
	primary.RollOffMinDistance = math.clamp(doorDistance * .85, 120, 900)
	primary.RollOffMaxDistance = math.max(2800, doorDistance + 1000)
	primary.Parent = primaryEmitter

	pcall(function()
		ContentProvider:PreloadAsync({primary})
	end)
	if not primary.Parent or not active() then
		clearSpatialCueEmitters()
		return true
	end

	primary:Play()
	local duration = primary.TimeLength > 0 and primary.TimeLength or 7.1
	local lastEchoDelay = 0
	for index, anchor in ipairs(corridorEchoAnchors(root.Position)) do
		local delaySeconds = .22 + (index - 1) * .12
		lastEchoDelay = delaySeconds
		local emitter = spatialEmitter(
			"Level 2 Pressure Door Corridor Reflection " .. index,
			anchor.Position
		)
		local echo = Instance.new("Sound")
		echo.Name = "Level 2 Pressure Door Hollow Corridor Reflection"
		echo.SoundId = id
		echo.Volume = math.max(.16, .30 - (index - 1) * .025)
		echo.PlaybackSpeed = 1 - (index - 1) * .004
		echo.RollOffMode = Enum.RollOffMode.InverseTapered
		echo.RollOffMinDistance = 35
		echo.RollOffMaxDistance = 550
		echo.Parent = emitter
		local reverb = Instance.new("ReverbSoundEffect")
		reverb.Name = "Level 2 Hollow Corridor Reverb"
		reverb.DecayTime = 4.8
		reverb.Density = .35
		reverb.Diffusion = .25
		reverb.DryLevel = -12
		reverb.WetLevel = -2
		reverb.Parent = echo
		task.delay(delaySeconds, function()
			if echo.Parent and active() then echo:Play() end
		end)
	end

	authoredBusyUntil = math.max(
		authoredBusyUntil,
		os.clock() + duration + lastEchoDelay + 4.8
	)
	task.delay(20, function()
		if spatialCueFolder == cueFolder then
			clearSpatialCueEmitters()
		elseif cueFolder.Parent then
			cueFolder:Destroy()
		end
	end)
	return true
end

-- One-shot cues from the server.
local function playCue(cueName, context)
	if not active() then return end
	if typeof(cueName) ~= "string" or not ALLOWED_CUES[cueName] then return end
	local id = resolveId(cueName)
	if not id then return end
	if cueName == "Level 2 Pressure Door" and playPressureDoorCue(id, context) then
		return
	end

	local cue = Instance.new("Sound")
	authoredCues[cue] = true
	cue.Name = "Level 2 Cue - " .. cueName
	cue.SoundId = id
	cue.Volume = CUE_VOLUMES[cueName] or DEFAULT_CUE_VOLUME
	cue.Parent = SoundService

	-- Initialize this specific Sound instance before Play(). A shared cached asset
	-- may report IsLoaded while a fresh Sound can still pause at position zero.
	pcall(function()
		ContentProvider:PreloadAsync({cue})
	end)
	if not cue.Parent then return end
	if not active() then cue:Destroy(); return end

	clearAmbientEmitters()
	cue:Play()
	local duration = cue.TimeLength > 0 and cue.TimeLength or 12
	authoredBusyUntil = math.max(authoredBusyUntil, os.clock() + duration)

	-- A fixed cleanup is intentionally used instead of Ended here. Some newly
	-- uploaded audio can emit an early Ended transition while its first local
	-- playback initializes, which would destroy the cue before it becomes audible.
	task.delay(20, function()
		authoredCues[cue] = nil
		if cue.Parent then cue:Destroy() end
	end)
end

local function stopAllLevel2Audio()
	stopRandomSession()
	clearSpatialCueEmitters()
	for cue in pairs(authoredCues) do
		authoredCues[cue] = nil
		if cue.Parent then cue:Destroy() end
	end
	for _, loop in pairs(loops) do
		loop.Volume = 0
		if loop.IsPlaying then loop:Stop() end
	end
	authoredBusyUntil = 0
	ambientBusyUntil = 0
end

local function enforceLevel2AudioLifecycle()
	if not active() then stopAllLevel2Audio() end
end

for _, attributeName in ipairs({"SelectedLevel", "RoundActive", "WorldGenerated"}) do
	workspace:GetAttributeChangedSignal(attributeName):Connect(enforceLevel2AudioLifecycle)
end
for _, attributeName in ipairs({"InRound", "Escaped"}) do
	player:GetAttributeChangedSignal(attributeName):Connect(enforceLevel2AudioLifecycle)
end

-- Waiting without a timeout prevents slow joins from silently losing all one-shots.
local cueConnection = event.OnClientEvent:Connect(playCue)
