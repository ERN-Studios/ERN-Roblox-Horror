--!strict
-- Level 3 Sound Controller
-- Quiet mall ambience, server-authorized interaction cues, and a restrained
-- reader cadence. This controller contains environmental and interface audio only.

local Players = game:GetService("Players")
local ReplicatedStorage = game:GetService("ReplicatedStorage")
local RunService = game:GetService("RunService")
local SoundService = game:GetService("SoundService")
local ContentProvider = game:GetService("ContentProvider")
local Debris = game:GetService("Debris")

local player = Players.LocalPlayer
local random = Random.new()

local LEVEL = 3
local WORLD_NAME = "Level 3 Generated World"
local STATE_FOLDER_NAME = "Level 3 State"
local REMOTES_FOLDER_NAME = "Level 3 Remotes"
local CLIENT_EVENT_NAME = "ClientEvent"
local LIBRARY_NAME = "Level 3 Sound Library"

local DEFAULT_AUDIO: {[string]: string} = {
	FluorescentHum = "rbxassetid://92576512092725",
	HVAC = "rbxassetid://9125446543",
	DoorRattle = "rbxassetid://9118901593",
	DoorMovement = "rbxassetid://9119631915",
	WaterDrip = "rbxassetid://9126193223",
	PowerDown = "rbxassetid://75561087895749",
	RoomListeningSong = "rbxassetid://140244948455675",
	ScareBalloonPop = "",
	ScareChairScrape = "",
	ScareChildGiggle = "",
	ScarePAWhisper = "",
	ScareRunningSteps = "",
}

local LIBRARY_ALIASES: {[string]: {string}} = {
	FluorescentHum = {"FluorescentHum", "Level 3 Fluorescent Hum"},
	HVAC = {"HVAC", "Level 3 HVAC"},
	DoorRattle = {"DoorRattle", "Level 3 Door Rattle"},
	DoorMovement = {"DoorMovement", "Level 3 Door Movement"},
	WaterDrip = {"WaterDrip", "Level 3 Water Drip"},
	PowerDown = {"PowerDown", "Level 3 Power Down"},
	RoomListeningSong = {"RoomListeningSong", "The Room is Listening"},
	ScareBalloonPop = {"ScareBalloonPop", "Level 3 Scare Balloon Pop"},
	ScareChairScrape = {"ScareChairScrape", "Level 3 Scare Chair Scrape"},
	ScareChildGiggle = {"ScareChildGiggle", "Level 3 Scare Child Giggle"},
	ScarePAWhisper = {"ScarePAWhisper", "Level 3 Scare PA Whisper"},
	ScareRunningSteps = {"ScareRunningSteps", "Level 3 Scare Running Steps"},
}

type AmbientRecord = {
	Sound: Sound,
	TargetVolume: number,
	Kind: string,
}

type RoomRegion = {
	Part: BasePart,
	HalfX: number,
	HalfZ: number,
}

local ambience: {AmbientRecord} = {}
local ambienceBySound: {[Sound]: AmbientRecord} = {}
local boundWorld: Model? = nil
local worldAddedConnection: RBXScriptConnection? = nil
local worldRemovingConnection: RBXScriptConnection? = nil
local clientEventConnection: RBXScriptConnection? = nil
local boundClientEvent: RemoteEvent? = nil
local roomRegions: {RoomRegion} = {}
local fluorescentDiffusers: {BasePart} = {}

type FluorescentVoice = {Emitter: BasePart, Sound: Sound}
local fluorescentVoices: {FluorescentVoice} = {}
for voiceIndex = 1, 3 do
	local emitter = Instance.new("Part")
	emitter.Name = "Level 3 Local Fluorescent Emitter " .. voiceIndex
	emitter.Size = Vector3.new(0.05, 0.05, 0.05)
	emitter.Transparency = 1
	emitter.Anchored = true
	emitter.CanCollide = false
	emitter.CanTouch = false
	emitter.CanQuery = false
	emitter.CastShadow = false
	emitter.Parent = workspace
	local hum = Instance.new("Sound")
	hum.Name = "Level 3 Local Fluorescent Hum " .. voiceIndex
	hum.SoundId = DEFAULT_AUDIO.FluorescentHum
	hum.Looped = true
	hum.Volume = 0
	hum.RollOffMode = Enum.RollOffMode.InverseTapered
	hum.RollOffMinDistance = 3
	hum.RollOffMaxDistance = 34
	hum.Parent = emitter
	table.insert(fluorescentVoices, {Emitter=emitter, Sound=hum})
end

local lastBlackoutActive = false
local lastObservedRoomSongPhase = "STOPPED"
local lastPowerDownAt = -math.huge

local roomSong = Instance.new("Sound")
roomSong.Name = "Level 3 - The Room is Listening"
roomSong.Looped = false
roomSong.Volume = 0
roomSong.PlaybackSpeed = 1
roomSong.Parent = SoundService
local roomSongAsset = ""
local roomSongPreloaded = false

type RoomSongVoice = {Sound: Sound, Effect: EqualizerSoundEffect?}
local roomSongSpeakers: {RoomSongVoice} = {}

local liveOneShots = 0
local windowStarted = os.clock()
local windowCount = 0
local recentCue: {[string]: number} = {}
local nextReaderBeep = os.clock() + random:NextNumber(4, 7)

local function normalizeId(raw: any): string?
	if type(raw) ~= "string" then return nil end
	local compact = (raw :: string):gsub("%s", "")
	if compact == "" then return nil end
	if compact:match("^%d+$") then return "rbxassetid://" .. compact end
	return compact
end

local function resolveId(key: string): string?
	local library = ReplicatedStorage:FindFirstChild(LIBRARY_NAME)
	if library then
		local aliases = LIBRARY_ALIASES[key]
		if aliases then
			for _, name in ipairs(aliases) do
				local slot = library:FindFirstChild(name)
				if slot and slot:IsA("StringValue") then
					local resolved = normalizeId(slot.Value)
					if resolved then return resolved end
				end
			end
		end
	end
	return normalizeId(DEFAULT_AUDIO[key])
end

local function stateFolder(): Folder?
	local object = ReplicatedStorage:FindFirstChild(STATE_FOLDER_NAME)
	return if object and object:IsA("Folder") then object else nil
end

local function stateAttribute(name: string, workspaceMirror: string?): any
	local state = stateFolder()
	local value = state and state:GetAttribute(name)
	if value == nil and workspaceMirror then value = workspace:GetAttribute(workspaceMirror) end
	return value
end

local function isActive(): boolean
	local state = stateFolder()
	return workspace:GetAttribute("SelectedLevel") == LEVEL
		and player:GetAttribute("InRound") == true
		and player:GetAttribute("Escaped") ~= true
		and (not state or state:GetAttribute("Level3_Phase") ~= "STOPPED")
end

local roomSongPhase: () -> string

local function currentWorld(): Model?
	local object = workspace:FindFirstChild(WORLD_NAME)
	return if object and object:IsA("Model") then object else nil
end

local function playPowerDown()
	if not isActive() then return end
	local now = os.clock()
	if now - lastPowerDownAt < 1 then return end
	lastPowerDownAt = now
	local cue = Instance.new("Sound")
	cue.Name = "Level 3 Power Down Transition"
	cue.SoundId = resolveId("PowerDown") or DEFAULT_AUDIO.PowerDown
	cue.Volume = 1
	cue.Looped = false
	cue.Parent = SoundService
	cue.Ended:Once(function() if cue.Parent then cue:Destroy() end end)
	Debris:AddItem(cue, 8)
	task.spawn(function()
		pcall(function() ContentProvider:PreloadAsync({cue}) end)
		if cue.Parent and isActive() then cue:Play() end
	end)
end

local function bindBlackoutSignal()
	-- Blackout is sampled with the rest of the replicated Level 3 state below.
	-- Keeping it in the central 10 Hz mixer makes rebuild/state-folder swaps safe.
end

roomSongPhase = function(): string
	local value = stateAttribute("Level3_RoomSongPhase", nil)
	return if type(value) == "string" then value else "STOPPED"
end

local function songAssetId(): string?
	local stateValue = stateAttribute("Level3_RoomSongAssetId", nil)
	local normalized = normalizeId(stateValue)
	if normalized and normalized ~= "rbxassetid://0" then return normalized end
	local resolved = resolveId("RoomListeningSong")
	return if resolved ~= "rbxassetid://0" then resolved else nil
end

local function distanceFromRoom(position: Vector3): number
	local closest = math.huge
	for index = #roomRegions, 1, -1 do
		local region = roomRegions[index]
		if not region.Part.Parent then
			table.remove(roomRegions, index)
		else
			local localPosition = region.Part.CFrame:PointToObjectSpace(position)
			local dx = math.max(math.abs(localPosition.X) - region.HalfX, 0)
			local dz = math.max(math.abs(localPosition.Z) - region.HalfZ, 0)
			closest = math.min(closest, math.sqrt(dx * dx + dz * dz))
		end
	end
	return closest
end

local function targetSongVolume(): number
	local character = player.Character
	local root = character and character:FindFirstChild("HumanoidRootPart")
	if not (root and root:IsA("BasePart")) then return 0 end
	local distance = distanceFromRoom(root.Position)
	local fadeDistance = 18
	local roomVolume, corridorVolume = .48, .045
	local alpha = 1 - math.clamp(distance / fadeDistance, 0, 1)
	return corridorVolume + (roomVolume - corridorVolume) * alpha
end

local function stopRoomSong()
	roomSong.Volume = 0
	if roomSong.IsPlaying then roomSong:Stop() end
	for _, voice in ipairs(roomSongSpeakers) do
		if voice.Sound.Parent then
			voice.Sound.Volume = 0
			if voice.Sound.IsPlaying then voice.Sound:Stop() end
		end
	end
end

local function updateRoomSong(_dt: number)
	local phase = roomSongPhase()
	if not isActive() or (phase ~= "ARMED" and phase ~= "PLAYING") then
		stopRoomSong()
		return
	end
	local id = songAssetId()
	if not id then
		stopRoomSong()
		return
	end
	if id ~= roomSongAsset then
		roomSongAsset = id
		roomSongPreloaded = false
		roomSong.SoundId = id
		task.spawn(function()
			pcall(function() ContentProvider:PreloadAsync({roomSong}) end)
			if roomSong.SoundId == id then roomSongPreloaded = true end
		end)
	end
	local startValue = stateAttribute("Level3_RoomSongStartServerTime", nil)
	local durationValue = stateAttribute("Level3_RoomSongDuration", nil)
	if type(startValue) ~= "number" or type(durationValue) ~= "number" then
		stopRoomSong()
		return
	end
	local position = workspace:GetServerTimeNow() - startValue
	if position < 0 or position >= durationValue then
		stopRoomSong()
		return
	end

	-- Every room speaker follows the same server-time playhead. Roblox's 3D
	-- rolloff provides the room-to-corridor fade, while the equalizer removes
	-- highs at distance so the music sounds physically muffled through walls.
	local root = player.Character and player.Character:FindFirstChild("HumanoidRootPart")
	for index = #roomSongSpeakers, 1, -1 do
		local voice = roomSongSpeakers[index]
		local sound = voice.Sound
		if not sound.Parent then
			table.remove(roomSongSpeakers, index)
		else
			if sound.SoundId ~= id then sound.SoundId = id end
			if not sound.IsPlaying then
				pcall(function() sound.TimePosition = position end)
				sound:Play()
			elseif math.abs(sound.TimePosition - position) > .32 then
				pcall(function() sound.TimePosition = position end)
			end
			sound.Volume = 0.62
			local distance = 0
			local parentPart = sound.Parent
			if root and root:IsA("BasePart") and parentPart and parentPart:IsA("BasePart") then
				distance = (root.Position - parentPart.Position).Magnitude
			end
			if voice.Effect then
				local far = math.clamp((distance - 9) / 38, 0, 1)
				voice.Effect.HighGain = -17 * far
				voice.Effect.MidGain = -6 * far
				voice.Effect.LowGain = 0
			end
		end
	end
end

local function generationMatches(payload: {[any]: any}): boolean
	local payloadGeneration = payload.Generation
	if type(payloadGeneration) ~= "number" then return true end
	local world = currentWorld()
	local liveGeneration = world and world:GetAttribute("Level3_Generation")
	return type(liveGeneration) ~= "number" or liveGeneration == payloadGeneration
end

local function cueAllowed(cue: string): boolean
	local now = os.clock()
	if now - windowStarted >= 2 then
		windowStarted = now
		windowCount = 0
	end
	if windowCount >= 14 then return false end
	local minimumGap = if cue == "DoorLocked" then 0.14 else 0.09
	if now - (recentCue[cue] or 0) < minimumGap then return false end
	recentCue[cue] = now
	windowCount += 1
	return true
end

local function playOneShot(key: string, cue: string, position: Vector3?, volume: number, playbackSpeed: number)
	if not isActive() or liveOneShots >= 10 or not cueAllowed(cue) then return end
	local id = resolveId(key)
	if not id then return end

	liveOneShots += 1
	local cleaned = false
	local emitter: BasePart? = nil
	local sound = Instance.new("Sound")
	sound.Name = "Level 3 Cue - " .. cue
	sound.SoundId = id
	sound.Volume = math.clamp(volume, 0, 0.65)
	sound.PlaybackSpeed = math.clamp(playbackSpeed, 0.65, 1.4)
	sound.RollOffMode = Enum.RollOffMode.InverseTapered
	sound.RollOffMinDistance = 5
	sound.RollOffMaxDistance = 52

	local function cleanup()
		if cleaned then return end
		cleaned = true
		liveOneShots = math.max(0, liveOneShots - 1)
		if emitter and emitter.Parent then emitter:Destroy()
		elseif sound.Parent then sound:Destroy() end
	end

	if position then
		local part = Instance.new("Part")
		part.Name = "Level 3 Local Audio Emitter"
		part.Size = Vector3.new(0.05, 0.05, 0.05)
		part.CFrame = CFrame.new(position)
		part.Transparency = 1
		part.Anchored = true
		part.CanCollide = false
		part.CanTouch = false
		part.CanQuery = false
		part.CastShadow = false
		part.Parent = workspace
		emitter = part
		sound.Parent = part
	else
		sound.Parent = SoundService
	end
	sound.Ended:Connect(cleanup)
	Debris:AddItem(if emitter then emitter else sound, 8)
	task.delay(8.1, cleanup)
	sound:Play()
end

type CueSpec = {Key: string, Volume: number, Speed: number}
local CUES: {[string]: CueSpec} = {
	DoorMovement = {Key="DoorMovement", Volume=0.34, Speed=1.00},
	DoorLocked = {Key="DoorRattle", Volume=0.38, Speed=0.88},
	PowerDown = {Key="PowerDown", Volume=0.92, Speed=1.00},
	ScareBalloonPop = {Key="ScareBalloonPop", Volume=0.48, Speed=1.00},
	ScareChairScrape = {Key="ScareChairScrape", Volume=0.52, Speed=0.94},
	ScareChildGiggle = {Key="ScareChildGiggle", Volume=0.42, Speed=1.00},
	ScarePAWhisper = {Key="ScarePAWhisper", Volume=0.46, Speed=1.00},
	ScareRunningSteps = {Key="ScareRunningSteps", Volume=0.50, Speed=1.00},
}

local function playCue(cueValue: any, positionValue: any)
	if type(cueValue) ~= "string" then return end
	local spec = CUES[cueValue]
	if not spec then return end
	local position = if typeof(positionValue) == "Vector3" then positionValue :: Vector3 else nil
	playOneShot(spec.Key, cueValue, position, spec.Volume, spec.Speed)
end

local function handleClientEvent(payload: any)
	if type(payload) ~= "table" then return end
	-- PowerDown is tied to the authoritative blackout edge itself. Let it
	-- through before normal objective-generation filtering, which can be one
	-- replication frame behind during the transition.
	if payload.Type == "Sound" and payload.Cue == "PowerDown" then
		if workspace:GetAttribute("SelectedLevel") == LEVEL
			and player:GetAttribute("InRound") == true
			and player:GetAttribute("Escaped") ~= true then
			playPowerDown()
		end
		return
	end
	if not isActive() or not generationMatches(payload) then return end
	if payload.Type == "Sound" then
		playCue(payload.Cue, payload.Position)
	end
end

local function bindClientEvent()
	local folder = ReplicatedStorage:FindFirstChild(REMOTES_FOLDER_NAME)
	local candidate = folder and folder:FindFirstChild(CLIENT_EVENT_NAME)
	local event = if candidate and candidate:IsA("RemoteEvent") then candidate else nil
	if event == boundClientEvent and clientEventConnection and clientEventConnection.Connected then
		-- The generated remotes folder is rebuilt between Studio rounds; keep
		-- the current live connection instead of churning it every mixer tick.
		return
	end
	if clientEventConnection then clientEventConnection:Disconnect() end
	clientEventConnection = nil
	boundClientEvent = event
	if event then clientEventConnection = event.OnClientEvent:Connect(handleClientEvent) end
end

local function ambientKind(sound: Sound): string
	local lower = sound.Name:lower()
	if lower:find("fluorescent", 1, true) then return "FluorescentHum" end
	if lower:find("hvac", 1, true) then return "HVAC" end
	if lower:find("drip", 1, true) then return "WaterDrip" end
	return "Other"
end

local function tryAddAmbience(instance: Instance)
	if #ambience >= 6 or not instance:IsA("Sound") or ambienceBySound[instance] then return end
	local world = boundWorld
	if not world or not instance:IsDescendantOf(world) then return end
	local folder = world:FindFirstChild("Ambient Emitters")
	if not folder or not instance:IsDescendantOf(folder) or not instance.Looped then return end
	local record: AmbientRecord = {
		Sound = instance,
		TargetVolume = math.clamp(instance.Volume, 0, 0.22),
		Kind = ambientKind(instance),
	}
	ambienceBySound[instance] = record
	table.insert(ambience, record)
	instance.Volume = 0
	if isActive() and not instance.IsPlaying then instance:Play() end
end

local function clearAmbience()
	for _, record in ipairs(ambience) do
		if record.Sound.Parent then
			record.Sound.Volume = 0
			record.Sound:Stop()
		end
	end
	table.clear(ambience)
	table.clear(ambienceBySound)
	stopRoomSong()
	table.clear(roomSongSpeakers)
end

local function tryAddRoomSongSpeaker(instance: Instance)
	if not instance:IsA("Sound") or instance.Name ~= "Level 3 Room Song Speaker" then return end
	for _, voice in ipairs(roomSongSpeakers) do
		if voice.Sound == instance then return end
	end
	local effect = instance:FindFirstChildOfClass("EqualizerSoundEffect")
	instance.Volume = 0
	instance.Looped = false
	instance.RollOffMode = Enum.RollOffMode.InverseTapered
	instance.RollOffMinDistance = 7
	instance.RollOffMaxDistance = 48
	table.insert(roomSongSpeakers, {Sound=instance, Effect=effect})
end

local function bindWorld(world: Model?)
	if world == boundWorld then return end
	if worldAddedConnection then worldAddedConnection:Disconnect() end
	if worldRemovingConnection then worldRemovingConnection:Disconnect() end
	worldAddedConnection = nil
	worldRemovingConnection = nil
	clearAmbience()
	table.clear(roomRegions)
	table.clear(fluorescentDiffusers)
	boundWorld = world
	if not world then return end
	for _, descendant in ipairs(world:GetDescendants()) do
		tryAddAmbience(descendant)
		tryAddRoomSongSpeaker(descendant)
		if descendant:IsA("BasePart") and descendant.Name == "Level 3 Room Floor" then
			table.insert(roomRegions, {
				Part = descendant,
				HalfX = descendant.Size.X * .5,
				HalfZ = descendant.Size.Z * .5,
			})
		elseif descendant:IsA("BasePart") and descendant.Name == "Level 3 Fluorescent Diffuser"
			and descendant:FindFirstChild("Level 3 Fluorescent Light") then
			table.insert(fluorescentDiffusers, descendant)
		end
	end
	worldAddedConnection = world.DescendantAdded:Connect(function(descendant)
		task.defer(function()
			if world ~= boundWorld or not descendant:IsDescendantOf(world) then return end
			tryAddAmbience(descendant)
			tryAddRoomSongSpeaker(descendant)
			if descendant:IsA("BasePart") and descendant.Name == "Level 3 Room Floor" then
				table.insert(roomRegions, {
					Part = descendant,
					HalfX = descendant.Size.X * .5,
					HalfZ = descendant.Size.Z * .5,
				})
			elseif descendant:IsA("BasePart") and descendant.Name == "Level 3 Fluorescent Diffuser"
				and descendant:FindFirstChild("Level 3 Fluorescent Light") then
				table.insert(fluorescentDiffusers, descendant)
			end
		end)
	end)
	worldRemovingConnection = world.AncestryChanged:Connect(function(_, parent)
		if parent == nil and boundWorld == world then bindWorld(nil) end
	end)
end

local function refreshWorld()
	bindWorld(currentWorld())
end

local function currentReaderData(): (number, number, Vector3?)
	local progressValue = stateAttribute("Level3_ModuleProgress", "Level3Modules")
	local goalValue = stateAttribute("Level3_ModuleGoal", "Level3ModuleGoal")
	local exitValue = stateAttribute("Level3_ExitPosition", nil)
	local progress = math.max(0, math.floor(if type(progressValue) == "number" then progressValue else 0))
	local goal = math.max(1, math.floor(if type(goalValue) == "number" then goalValue else 5))
	return math.min(progress, goal), goal,
		if typeof(exitValue) == "Vector3" then exitValue :: Vector3 else nil
end

local function updateReaderCadence(now: number)
	if not isActive() or now < nextReaderBeep then return end
	local progress, goal, exit = currentReaderData()
	local character = player.Character
	local root = character and character:FindFirstChild("HumanoidRootPart")
	if not (root and root:IsA("BasePart") and exit) then
		nextReaderBeep = now + 3
		return
	end

	local offset = exit - root.Position
	local flat = Vector3.new(offset.X, 0, offset.Z)
	if flat.Magnitude < 0.1 then
		nextReaderBeep = now + 1
		return
	end
	local forward = Vector3.new(root.CFrame.LookVector.X, 0, root.CFrame.LookVector.Z)
	local facing = if forward.Magnitude > 0.01 then math.clamp((forward.Unit:Dot(flat.Unit) + 1) * 0.5, 0, 1) else 0
	local range = 1 - math.clamp(flat.Magnitude / 650, 0, 1)
	local calibration = progress / goal
	local signal = math.clamp(facing * 0.68 + range * 0.32, 0, 1)
	local unlocked = stateAttribute("Level3_ExitUnlocked", "Level3ExitUnlocked") == true

	-- The reader is visual-only. Calibration, module recovery, and exit unlock
	-- retain their explicit UI feedback, but the directional pulse never beeps.
	nextReaderBeep = now + (if progress == 0 then 8 else math.clamp(5.0 - calibration * 3.2 - signal * 0.55, 1.25, 5))
end

-- Preload the small, allowlisted cue set. Empty/failed assets remain harmless.
task.spawn(function()
	local temporary: {Sound} = {}
	for _, key in ipairs({"DoorRattle", "DoorMovement", "FluorescentHum", "PowerDown", "RoomListeningSong",
		"ScareBalloonPop", "ScareChairScrape", "ScareChildGiggle", "ScarePAWhisper", "ScareRunningSteps"}) do
		local id = resolveId(key)
		if id then
			local sound = Instance.new("Sound")
			sound.Name = "Level 3 Preload - " .. key
			sound.SoundId = id
			sound.Volume = 0
			sound.Parent = SoundService
			table.insert(temporary, sound)
		end
	end
	if #temporary > 0 then pcall(function() ContentProvider:PreloadAsync(temporary) end) end
	for _, sound in ipairs(temporary) do sound:Destroy() end
end)

ReplicatedStorage.ChildAdded:Connect(bindClientEvent)
ReplicatedStorage.ChildRemoved:Connect(bindClientEvent)
workspace.ChildAdded:Connect(function(child)
	if child.Name == WORLD_NAME then task.defer(refreshWorld) end
end)
workspace.ChildRemoved:Connect(function(child)
	if child == boundWorld then bindWorld(nil) end
end)
player:GetAttributeChangedSignal("InRound"):Connect(function()
	if isActive() then nextReaderBeep = os.clock() + 2.5 end
end)

local accumulated = 0
RunService.Heartbeat:Connect(function(dt)
	accumulated += dt
	if accumulated < 0.10 then return end
	local elapsed = accumulated
	accumulated = 0
	bindClientEvent()
	refreshWorld()

	local playing = isActive()
	local now = os.clock()
	for index = #ambience, 1, -1 do
		local record = ambience[index]
		local sound = record.Sound
		if not sound.Parent then
			ambienceBySound[sound] = nil
			table.remove(ambience, index)
		else
				local sequencePhase = roomSongPhase()
			local sequenceDuck = if sequencePhase == "PLAYING" or sequencePhase == "ARMED" then .20
				elseif sequencePhase == "BLACKOUT" then .04 else 1
			local target = if playing then record.TargetVolume * sequenceDuck else 0
			if playing and record.Kind == "FluorescentHum" then
				-- Slow ballast variation adds life without audible strobing.
				target *= 0.96 + math.noise(now * 0.17, 7) * 0.04
			end
			local blend = math.clamp(elapsed / 1.5, 0, 1)
			sound.Volume += (target - sound.Volume) * blend
			if playing and not sound.IsPlaying then sound:Play() end
			if not playing and sound.Volume < 0.004 and sound.IsPlaying then sound:Stop() end
		end
	end
	updateRoomSong(elapsed)
	updateReaderCadence(now)

	local root = player.Character and player.Character:FindFirstChild("HumanoidRootPart")
	local nearestFixtures: {{Part: BasePart, Distance: number}} = {}
	if root and root:IsA("BasePart") then
		for index = #fluorescentDiffusers, 1, -1 do
			local fixture = fluorescentDiffusers[index]
			if not fixture.Parent then
				table.remove(fluorescentDiffusers, index)
			else
				local candidate = {Part=fixture, Distance=(fixture.Position - root.Position).Magnitude}
				local inserted = false
				for slot = 1, #nearestFixtures do
					if candidate.Distance < nearestFixtures[slot].Distance then
						table.insert(nearestFixtures, slot, candidate)
						inserted = true
						break
					end
				end
				if not inserted then table.insert(nearestFixtures, candidate) end
				if #nearestFixtures > #fluorescentVoices then table.remove(nearestFixtures) end
			end
		end
	end
	local sequencePhase = roomSongPhase()
	local blackoutActive = stateAttribute("Level3_BlackoutActive", "Level3BlackoutActive") == true
	if sequencePhase == "PLAYING" or sequencePhase == "ARMED" then
		lastObservedRoomSongPhase = sequencePhase
		lastBlackoutActive = false
	elseif sequencePhase == "BLACKOUT" then
		if lastObservedRoomSongPhase ~= "BLACKOUT" and playing then
			-- Phase replication is the audible edge; the blackout boolean still
			-- owns all fixture/lighting state.
			playPowerDown()
			lastObservedRoomSongPhase = "BLACKOUT"
		end
		-- If the player/round attributes arrive one frame after blackout,
		-- leave the cue armed so the next mixer pass can still play it.
		lastBlackoutActive = true
	elseif not blackoutActive then
		lastObservedRoomSongPhase = sequencePhase
		lastBlackoutActive = false
	end
	for voiceIndex, voice in ipairs(fluorescentVoices) do
		local candidate = nearestFixtures[voiceIndex]
		if playing and candidate then voice.Emitter.Position = candidate.Part.Position end
		local baseVolumes = {0.12, 0.075, 0.045}
		local humTarget = if playing and candidate and sequencePhase ~= "BLACKOUT"
			then baseVolumes[voiceIndex] * ((sequencePhase == "PLAYING" or sequencePhase == "ARMED") and .24 or 1)
			else 0
		voice.Sound.Volume += (humTarget - voice.Sound.Volume) * math.clamp(elapsed / .65, 0, 1)
		if humTarget > 0 and not voice.Sound.IsPlaying then voice.Sound:Play() end
		if humTarget == 0 and voice.Sound.Volume < .003 and voice.Sound.IsPlaying then voice.Sound:Stop() end
	end

	bindBlackoutSignal()
end)

bindClientEvent()
bindBlackoutSignal()
refreshWorld()
