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
	PowerDown = "",
	RoomListeningSong = "rbxassetid://140244948455675",
	MallManagerBlackoutScream = "rbxassetid://125407251695204",
	ScareBalloonPop = "",
	ScareChairScrape = "",
	ScareChildGiggle = "",
	ScarePAWhisper = "",
	ScareRunningSteps = "",
	ExitUnlocked = "",
	Escape = "",
}

local LIBRARY_ALIASES: {[string]: {string}} = {
	FluorescentHum = {"FluorescentHum", "Level 3 Fluorescent Hum"},
	HVAC = {"HVAC", "Level 3 HVAC"},
	PowerDown = {"PowerDown", "Level 3 Power Down"},
	RoomListeningSong = {"RoomListeningSong", "The Room is Listening"},
	MallManagerBlackoutScream = {"MallManagerBlackoutScream", "Mall Manager Walk Blackout Scream"},
	ScareBalloonPop = {"ScareBalloonPop", "Level 3 Scare Balloon Pop"},
	ScareChairScrape = {"ScareChairScrape", "Level 3 Scare Chair Scrape"},
	ScareChildGiggle = {"ScareChildGiggle", "Level 3 Scare Child Giggle"},
	ScarePAWhisper = {"ScarePAWhisper", "Level 3 Scare PA Whisper"},
	ScareRunningSteps = {"ScareRunningSteps", "Level 3 Scare Running Steps"},
	ExitUnlocked = {"ExitUnlocked", "Level 3 Exit Unlocked"},
	Escape = {"Escape", "Level 3 Escape"},
}

type AmbientRecord = {
	Sound: Sound,
	TargetVolume: number,
	Kind: string,
}

local ambience: {AmbientRecord} = {}
local ambienceBySound: {[Sound]: AmbientRecord} = {}
local boundWorld: Model? = nil
local worldAddedConnection: RBXScriptConnection? = nil
local worldRemovingConnection: RBXScriptConnection? = nil
local clientEventConnection: RBXScriptConnection? = nil
local boundClientEvent: RemoteEvent? = nil
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

local lastObservedRoomSongPhase = "STOPPED"
local lastPowerDownAt = -math.huge

local roomSong = Instance.new("Sound")
roomSong.Name = "Level 3 - The Room is Listening"
roomSong.Looped = false
roomSong.Volume = 0
roomSong.PlaybackSpeed = 1
roomSong.Parent = SoundService
local roomSongAsset = ""

type RoomSongVoice = {Sound: Sound, Effect: EqualizerSoundEffect?}
local roomSongSpeakers: {RoomSongVoice} = {}
local roomSongLastStartServerTime: number? = nil
local roomSongLastHardSync: {[Sound]: number} = {}

local BLACKOUT_SCREAM_NAME = "Mall Manager Walk Blackout Scream"
local BLACKOUT_SCREAM_DURATION = 8.071836735
local BLACKOUT_SCREAM_VOLUME = 0.90
local BLACKOUT_SCREAM_MIN_DISTANCE = 22
local BLACKOUT_SCREAM_MAX_DISTANCE = 210
local BLACKOUT_SCREAM_MAX_VOICES = 1
local BLACKOUT_SCREAM_SOURCE_MIN_DISTANCE = 75
local BLACKOUT_SCREAM_SOURCE_PREFERRED_DISTANCE = 115
local BLACKOUT_SCREAM_SOURCE_MAX_DISTANCE = 175
local BLACKOUT_SCREAM_MIN_OCCLUDERS = 2
local BLACKOUT_SCREAM_LOW_GAIN = 0
local BLACKOUT_SCREAM_MID_GAIN = -9
local BLACKOUT_SCREAM_HIGH_GAIN = -24
local BLACKOUT_SCREAM_REVERB_DENSITY = 0.88
local BLACKOUT_SCREAM_REVERB_DIFFUSION = 0.82
local BLACKOUT_SCREAM_REVERB_DECAY = 2.2
local BLACKOUT_SCREAM_REVERB_DRY = -3
local BLACKOUT_SCREAM_REVERB_WET = -10
local blackoutScreamEmitters: {Instance} = {}
local blackoutScreamEmitterSeen: {[Instance]: boolean} = {}
local blackoutScreamVoices: {Sound} = {}
local lastBlackoutScreamSerial = 0
script:SetAttribute("Level3_BlackoutScreamPlaying", false)
script:SetAttribute("Level3_BlackoutScreamVoiceCount", 0)
script:SetAttribute("Level3_BlackoutScreamSerial", 0)
script:SetAttribute("Level3_BlackoutScreamSourceDistance", 0)
script:SetAttribute("Level3_BlackoutScreamStructuralOccluders", 0)
script:SetAttribute("Level3_BlackoutScreamOpeningKey", "")
script:SetAttribute("Level3_RoomSongAudibleVoiceCount", 0)
script:SetAttribute("Level3_RoomSongRunningVoiceCount", 0)
script:SetAttribute("Level3_RoomSongPrimaryDistance", 0)
script:SetAttribute("Level3_RoomSongTargetVolume", 0)

-- Mirrors the server-side MusicSequence tuning. Only two nearby PA speakers
-- contribute volume, preventing 18 synchronized voices from coherently stacking.
local ROOM_SONG_SPEAKER_VOLUME = 0.30
local ROOM_SONG_MIN_DISTANCE = 18
local ROOM_SONG_MAX_DISTANCE = 180
local ROOM_SONG_MAX_AUDIBLE_VOICES = 2
local ROOM_SONG_SECONDARY_VOLUME_SCALE = 0.25
local ROOM_SONG_VOLUME_FADE_SECONDS = 0.85
local ROOM_SONG_HARD_SYNC_TOLERANCE = 0.85
local ROOM_SONG_HARD_SYNC_COOLDOWN = 1.25
local ROOM_SONG_MUFFLE_START = 24
local ROOM_SONG_MUFFLE_RANGE = 136

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

local function emitterWorldPosition(emitter: Instance): Vector3?
	if emitter:IsA("Attachment") then return emitter.WorldPosition end
	if emitter:IsA("Bone") then return emitter.WorldPosition end
	if emitter:IsA("BasePart") then return emitter.Position end
	return nil
end

local function structuralOccluderCount(world: Model, origin: Vector3, target: Vector3): number
	local offset = target - origin
	if offset.Magnitude <= 2.1 then return 0 end
	local direction = offset.Unit
	local params = RaycastParams.new()
	params.FilterType = Enum.RaycastFilterType.Include
	params.FilterDescendantsInstances = {world}
	params.IgnoreWater = true
	params.RespectCanCollide = true
	local cursor = origin
	local count = 0
	for _ = 1, 16 do
		local remaining = target - cursor
		if remaining:Dot(direction) <= 0 or remaining.Magnitude <= 2.1 then break end
		local hit = workspace:Raycast(cursor, remaining, params)
		if not hit then break end
		local lowerName = hit.Instance.Name:lower()
		if lowerName:find("wall", 1, true) or lowerName:find("door", 1, true) then
			count += 1
		end
		-- Level 3 structural walls are 1.5 studs thick. Advancing two studs
		-- prevents counting both faces of the same wall as separate rooms.
		cursor = hit.Position + direction * 2
	end
	return count
end

local function tryAddBlackoutScreamEmitter(instance: Instance)
	if instance:GetAttribute("Level3_MallManagerVoiceEmitter") == true
		and (instance:IsA("Bone") or instance:IsA("Attachment")) then
		-- The Mall Manager's own voice bone is never a corridor scream emitter.
		return
	end
	if instance:GetAttribute("Level3_CorridorOpeningScreamEmitter") ~= true
		or (not instance:IsA("Attachment") and not instance:IsA("Bone"))
		or blackoutScreamEmitterSeen[instance] then
		return
	end
	blackoutScreamEmitterSeen[instance] = true
	table.insert(blackoutScreamEmitters, instance)
end

local function clearBlackoutScream()
	for _, sound in ipairs(blackoutScreamVoices) do
		if sound.Parent then
			if sound.IsPlaying then sound:Stop() end
			sound:Destroy()
		end
	end
	table.clear(blackoutScreamVoices)
	script:SetAttribute("Level3_BlackoutScreamPlaying", false)
	script:SetAttribute("Level3_BlackoutScreamVoiceCount", 0)
	script:SetAttribute("Level3_BlackoutScreamSourceDistance", 0)
	script:SetAttribute("Level3_BlackoutScreamStructuralOccluders", 0)
	script:SetAttribute("Level3_BlackoutScreamOpeningKey", "")
end

local function playBlackoutScream(serial: number, startedAt: number, duration: number): boolean
	clearBlackoutScream()
	local phase = roomSongPhase()
	if not isActive()
		or (phase ~= "BLACKOUT_SONG" and phase ~= "BLACKOUT_HUNT")
		or stateAttribute("Level3_BlackoutActive", "Level3BlackoutActive") ~= true then
		return false
	end
	-- The server replicates the authoritative scream id; the local table is the
	-- fallback so a Configuration.Audio change cannot silently desync clients.
	local id = resolveId("MallManagerBlackoutScream")
	local replicated = normalizeId(stateAttribute("Level3_BlackoutScreamAssetId", nil))
	if replicated and replicated ~= "rbxassetid://0" then id = replicated end
	local world = currentWorld()
	local characterRoot = player.Character and player.Character:FindFirstChild("HumanoidRootPart")
	if not id or not world or not (characterRoot and characterRoot:IsA("BasePart")) then return false end
	local elapsed = math.max(0, workspace:GetServerTimeNow() - startedAt)
	if elapsed >= duration then return false end

	local listenerPosition = characterRoot.Position + Vector3.new(0, 1.2, 0)
	local candidates: {any} = {}
	for index = #blackoutScreamEmitters, 1, -1 do
		local emitter = blackoutScreamEmitters[index]
		local position = emitterWorldPosition(emitter)
		if not emitter.Parent or not emitter:IsDescendantOf(world) or not position then
			blackoutScreamEmitterSeen[emitter] = nil
			table.remove(blackoutScreamEmitters, index)
		else
			local distance = (position - listenerPosition).Magnitude
			local occluders = structuralOccluderCount(world, listenerPosition, position)
			local tier = 3
			if distance >= BLACKOUT_SCREAM_SOURCE_MIN_DISTANCE
				and distance <= BLACKOUT_SCREAM_SOURCE_MAX_DISTANCE
				and occluders >= BLACKOUT_SCREAM_MIN_OCCLUDERS then
				tier = 0
			elseif distance >= 60 and distance <= 190 and occluders >= 1 then
				tier = 1
			elseif distance <= BLACKOUT_SCREAM_MAX_DISTANCE then
				tier = 2
			end
			table.insert(candidates, {
				Emitter = emitter,
				Distance = distance,
				Occluders = occluders,
				Tier = tier,
				Score = math.abs(distance - BLACKOUT_SCREAM_SOURCE_PREFERRED_DISTANCE),
				Key = tostring(emitter:GetAttribute("Level3_CorridorOpeningKey") or emitter.Name),
			})
		end
	end
	if #candidates == 0 then return false end
	table.sort(candidates, function(a, b)
		if a.Tier ~= b.Tier then return a.Tier < b.Tier end
		if math.abs(a.Score - b.Score) > .001 then return a.Score < b.Score end
		if a.Occluders ~= b.Occluders then return a.Occluders > b.Occluders end
		return a.Key < b.Key
	end)
	local topCount = math.min(3, #candidates)
	local selected = candidates[(serial - 1) % topCount + 1]
	local emitter = selected.Emitter :: Instance

	local volumeValue = stateAttribute("Level3_BlackoutScreamVolume", nil)
	local screamVolume = if type(volumeValue) == "number" and volumeValue > 0
		then volumeValue else BLACKOUT_SCREAM_VOLUME
	local sound = Instance.new("Sound")
	sound.Name = BLACKOUT_SCREAM_NAME
	sound.SoundId = id
	sound.Volume = screamVolume
	sound.PlaybackSpeed = 1
	sound.Looped = false
	sound.PlayOnRemove = false
	sound.RollOffMode = Enum.RollOffMode.InverseTapered
	sound.RollOffMinDistance = BLACKOUT_SCREAM_MIN_DISTANCE
	sound.RollOffMaxDistance = BLACKOUT_SCREAM_MAX_DISTANCE
	sound:SetAttribute("Level3_MallManagerBlackoutScream", true)
	sound:SetAttribute("BlackoutSerial", serial)
	sound:SetAttribute("SourceIndex", 1)
	sound:SetAttribute("SourceDistance", selected.Distance)
	sound:SetAttribute("StructuralOccluders", selected.Occluders)

	local equalizer = Instance.new("EqualizerSoundEffect")
	equalizer.Name = "Level 3 Distant Wall Muffle"
	equalizer.LowGain = BLACKOUT_SCREAM_LOW_GAIN
	equalizer.MidGain = BLACKOUT_SCREAM_MID_GAIN
	equalizer.HighGain = BLACKOUT_SCREAM_HIGH_GAIN
	equalizer.Parent = sound
	local reverb = Instance.new("ReverbSoundEffect")
	reverb.Name = "Level 3 Distant Corridor Reverb"
	reverb.Density = BLACKOUT_SCREAM_REVERB_DENSITY
	reverb.Diffusion = BLACKOUT_SCREAM_REVERB_DIFFUSION
	reverb.DecayTime = BLACKOUT_SCREAM_REVERB_DECAY
	reverb.DryLevel = BLACKOUT_SCREAM_REVERB_DRY
	reverb.WetLevel = BLACKOUT_SCREAM_REVERB_WET
	reverb.Parent = sound

	sound.Parent = emitter
	table.insert(blackoutScreamVoices, sound)
	local played = pcall(function()
		sound:Play()
		sound.TimePosition = elapsed
	end)
	if not played then
		clearBlackoutScream()
		return false
	end
	Debris:AddItem(sound, math.max(1, duration - elapsed + 1))
	script:SetAttribute("Level3_BlackoutScreamPlaying", true)
	script:SetAttribute("Level3_BlackoutScreamVoiceCount", math.min(#blackoutScreamVoices, BLACKOUT_SCREAM_MAX_VOICES))
	script:SetAttribute("Level3_BlackoutScreamSerial", serial)
	script:SetAttribute("Level3_BlackoutScreamSourceDistance", selected.Distance)
	script:SetAttribute("Level3_BlackoutScreamStructuralOccluders", selected.Occluders)
	script:SetAttribute("Level3_BlackoutScreamOpeningKey", selected.Key)
	return true
end

local function updateBlackoutScream()
	local serialValue = stateAttribute("Level3_BlackoutSerial", nil)
	local serial = if type(serialValue) == "number" then math.floor(serialValue) else 0
	if serial < lastBlackoutScreamSerial then
		lastBlackoutScreamSerial = serial
		clearBlackoutScream()
	end
	local phase = roomSongPhase()
	if not isActive()
		or (phase ~= "BLACKOUT_SONG" and phase ~= "BLACKOUT_HUNT")
		or stateAttribute("Level3_BlackoutActive", "Level3BlackoutActive") ~= true then
		clearBlackoutScream()
		return
	end
	local startValue = stateAttribute("Level3_BlackoutScreamStartedAtServerTime", nil)
	local durationValue = stateAttribute("Level3_BlackoutScreamDuration", nil)
	local startedAt = if type(startValue) == "number" then startValue else 0
	local duration = if type(durationValue) == "number" and durationValue > 0
		then durationValue else BLACKOUT_SCREAM_DURATION
	local screamElapsed = workspace:GetServerTimeNow() - startedAt
	if startedAt <= 0 or screamElapsed >= duration then
		-- A late join after the one-shot has expired acknowledges the edge instead
		-- of retrying a dead stream ten times per second.
		if serial > lastBlackoutScreamSerial then lastBlackoutScreamSerial = serial end
		clearBlackoutScream()
		return
	end
	if serial > 0 and serial ~= lastBlackoutScreamSerial then
		if playBlackoutScream(serial, startedAt, duration) then
			lastBlackoutScreamSerial = serial
		end
	end
end

local function playPowerDown()
	if not isActive() then return end
	local id = resolveId("PowerDown")
	-- Keep the transition plumbing ready while the replacement asset slot is empty.
	if not id then return end
	local now = os.clock()
	if now - lastPowerDownAt < 1 then return end
	lastPowerDownAt = now
	local cue = Instance.new("Sound")
	cue.Name = "Level 3 Power Down Transition"
	cue.SoundId = id
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

local function stopRoomSong()
	roomSong.Volume = 0
	if roomSong.IsPlaying then roomSong:Stop() end
	for _, voice in ipairs(roomSongSpeakers) do
		if voice.Sound.Parent then
			voice.Sound.Volume = 0
			if voice.Sound.IsPlaying then voice.Sound:Stop() end
		end
	end
	roomSongLastStartServerTime = nil
	table.clear(roomSongLastHardSync)
	script:SetAttribute("Level3_RoomSongAudibleVoiceCount", 0)
	script:SetAttribute("Level3_RoomSongRunningVoiceCount", 0)
	script:SetAttribute("Level3_RoomSongPrimaryDistance", 0)
	script:SetAttribute("Level3_RoomSongTargetVolume", 0)
end

local function updateRoomSong(dt: number)
	local phase = roomSongPhase()
	if not isActive() or (phase ~= "ARMED" and phase ~= "PLAYING"
		and phase ~= "PRE_BLACKOUT" and phase ~= "BLACKOUT_SONG") then
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
		roomSong.SoundId = id
		task.spawn(function()
			pcall(function() ContentProvider:PreloadAsync({roomSong}) end)
		end)
	end
	local startValue = stateAttribute("Level3_RoomSongStartServerTime", nil)
	local durationValue = stateAttribute("Level3_RoomSongDuration", nil)
	if type(startValue) ~= "number" or type(durationValue) ~= "number" then
		stopRoomSong()
		return
	end
	local position = workspace:GetServerTimeNow() - startValue
	local stopValue = stateAttribute("Level3_RoomSongStopSeconds", nil)
	local stopSeconds = if type(stopValue) == "number" then stopValue else durationValue
	if position < 0 or position >= math.min(durationValue, stopSeconds) then
		stopRoomSong()
		return
	end

	-- Rank before touching playback. Only the nearest two PA speakers are allowed
	-- to own decoders; K previously made all 18 compressed streams seek together.
	local timelineChanged = roomSongLastStartServerTime == nil
		or math.abs(startValue - roomSongLastStartServerTime) > .05
	roomSongLastStartServerTime = startValue
	local syncNow = os.clock()
	local root = player.Character and player.Character:FindFirstChild("HumanoidRootPart")
	local ranked: {any} = {}
	for index = #roomSongSpeakers, 1, -1 do
		local voice = roomSongSpeakers[index]
		local sound = voice.Sound
		if not sound.Parent then
			roomSongLastHardSync[sound] = nil
			table.remove(roomSongSpeakers, index)
		else
			if sound.SoundId ~= id then
				sound.Volume = 0
				if sound.IsPlaying then sound:Stop() end
				sound.SoundId = id
				roomSongLastHardSync[sound] = nil
			end
			local parentPart = sound.Parent
			if root and root:IsA("BasePart") and parentPart and parentPart:IsA("BasePart") then
				table.insert(ranked, {Voice=voice, Distance=(root.Position - parentPart.Position).Magnitude})
			end
		end
	end
	table.sort(ranked, function(a, b) return a.Distance < b.Distance end)
	local rankBySound: {[Sound]: number} = {}
	local distanceBySound: {[Sound]: number} = {}
	for rank = 1, math.min(ROOM_SONG_MAX_AUDIBLE_VOICES, #ranked) do
		local record = ranked[rank]
		rankBySound[record.Voice.Sound] = rank
		distanceBySound[record.Voice.Sound] = record.Distance
	end

	local audibleCount = 0
	local runningCount = 0
	local totalTargetVolume = 0
	local blend = math.clamp(dt / ROOM_SONG_VOLUME_FADE_SECONDS, 0, 1)
	for _, voice in ipairs(roomSongSpeakers) do
		local sound = voice.Sound
		local rank = rankBySound[sound]
		if rank then
			local lastSync = roomSongLastHardSync[sound] or -math.huge
			local drifted = sound.IsPlaying and sound.IsLoaded
				and math.abs(sound.TimePosition - position) > ROOM_SONG_HARD_SYNC_TOLERANCE
			local maySync = syncNow - lastSync >= ROOM_SONG_HARD_SYNC_COOLDOWN
			local shouldSync = (not sound.IsPlaying and maySync)
				or (timelineChanged and sound.IsPlaying)
				or (drifted and maySync)
			if shouldSync then
				-- Stamp before touching the stream so a buffering decoder cannot be
				-- hammered by the ten-hertz mixer loop.
				roomSongLastHardSync[sound] = syncNow
				pcall(function()
					if not sound.IsPlaying then
						sound.TimePosition = position
						sound:Play()
					else
						sound.TimePosition = position
					end
				end)
			end
			if sound.IsPlaying then runningCount += 1 end
			local scale = if rank == 1 then 1 else ROOM_SONG_SECONDARY_VOLUME_SCALE
			local targetVolume = ROOM_SONG_SPEAKER_VOLUME * scale
			audibleCount += 1
			totalTargetVolume += targetVolume
			sound.Volume += (targetVolume - sound.Volume) * blend
			if voice.Effect then
				local distance = distanceBySound[sound] or 0
				local far = math.clamp((distance - ROOM_SONG_MUFFLE_START) / ROOM_SONG_MUFFLE_RANGE, 0, 1)
				voice.Effect.HighGain = -17 * far
				voice.Effect.MidGain = -6 * far
				voice.Effect.LowGain = 0
			end
		else
			-- Muted speakers must not continue decoding in the background.
			sound.Volume = 0
			if sound.IsPlaying then sound:Stop() end
			roomSongLastHardSync[sound] = nil
		end
	end
	script:SetAttribute("Level3_RoomSongAudibleVoiceCount", audibleCount)
	script:SetAttribute("Level3_RoomSongRunningVoiceCount", runningCount)
	script:SetAttribute("Level3_RoomSongPrimaryDistance", if #ranked > 0 then ranked[1].Distance else 0)
	script:SetAttribute("Level3_RoomSongTargetVolume", totalTargetVolume)
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
	ScareBalloonPop = {Key="ScareBalloonPop", Volume=0.48, Speed=1.00},
	ScareChairScrape = {Key="ScareChairScrape", Volume=0.52, Speed=0.94},
	ScareChildGiggle = {Key="ScareChildGiggle", Volume=0.42, Speed=1.00},
	ScarePAWhisper = {Key="ScarePAWhisper", Volume=0.46, Speed=1.00},
	ScareRunningSteps = {Key="ScareRunningSteps", Volume=0.50, Speed=1.00},
	ExitUnlocked = {Key="ExitUnlocked", Volume=0.60, Speed=1.00},
	Escape = {Key="Escape", Volume=0.50, Speed=1.00},
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
	instance.RollOffMinDistance = ROOM_SONG_MIN_DISTANCE
	instance.RollOffMaxDistance = ROOM_SONG_MAX_DISTANCE
	table.insert(roomSongSpeakers, {Sound=instance, Effect=effect})
end

local function bindWorld(world: Model?)
	if world == boundWorld then return end
	if worldAddedConnection then worldAddedConnection:Disconnect() end
	if worldRemovingConnection then worldRemovingConnection:Disconnect() end
	worldAddedConnection = nil
	worldRemovingConnection = nil
	clearAmbience()
	clearBlackoutScream()
	table.clear(blackoutScreamEmitters)
	table.clear(blackoutScreamEmitterSeen)
	lastBlackoutScreamSerial = 0
	table.clear(fluorescentDiffusers)
	boundWorld = world
	if not world then return end
	for _, descendant in ipairs(world:GetDescendants()) do
		tryAddAmbience(descendant)
		tryAddRoomSongSpeaker(descendant)
		tryAddBlackoutScreamEmitter(descendant)
		if descendant:IsA("BasePart") and descendant.Name == "Level 3 Fluorescent Diffuser"
			and descendant:FindFirstChild("Level 3 Fluorescent Light") then
			table.insert(fluorescentDiffusers, descendant)
		end
	end
	worldAddedConnection = world.DescendantAdded:Connect(function(descendant)
		task.defer(function()
			if world ~= boundWorld or not descendant:IsDescendantOf(world) then return end
			tryAddAmbience(descendant)
			tryAddRoomSongSpeaker(descendant)
			tryAddBlackoutScreamEmitter(descendant)
			if descendant:IsA("BasePart") and descendant.Name == "Level 3 Fluorescent Diffuser"
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
	-- The reader is visual-only. Calibration, module recovery, and exit unlock
	-- retain their explicit UI feedback, but the directional pulse never beeps.
	nextReaderBeep = now + (if progress == 0 then 8 else math.clamp(5.0 - calibration * 3.2 - signal * 0.55, 1.25, 5))
end

-- Preload the small, allowlisted cue set. Empty/failed assets remain harmless.
task.spawn(function()
	local temporary: {Sound} = {}
	for _, key in ipairs({"FluorescentHum", "PowerDown", "RoomListeningSong",
		"MallManagerBlackoutScream", "ScareBalloonPop", "ScareChairScrape", "ScareChildGiggle", "ScarePAWhisper", "ScareRunningSteps"}) do
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
				elseif sequencePhase == "PRE_BLACKOUT" then .14
				elseif sequencePhase == "BLACKOUT_SONG" then .04 else 1
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
	updateBlackoutScream()
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
	if sequencePhase == "PLAYING" or sequencePhase == "ARMED"
		or sequencePhase == "PRE_BLACKOUT" or sequencePhase == "BLACKOUT_SONG" then
		lastObservedRoomSongPhase = sequencePhase
	elseif sequencePhase == "BLACKOUT_HUNT" then
		if lastObservedRoomSongPhase ~= "BLACKOUT_HUNT" and playing then
			-- Phase replication is the audible edge; the blackout boolean still
			-- owns all fixture/lighting state.
			playPowerDown()
			lastObservedRoomSongPhase = "BLACKOUT_HUNT"
		end
	elseif not blackoutActive then
		lastObservedRoomSongPhase = sequencePhase
	end
	for voiceIndex, voice in ipairs(fluorescentVoices) do
		local candidate = nearestFixtures[voiceIndex]
		if playing and candidate then voice.Emitter.Position = candidate.Part.Position end
		local baseVolumes = {0.12, 0.075, 0.045}
		local humTarget = if playing and candidate
			and sequencePhase ~= "BLACKOUT_SONG" and sequencePhase ~= "BLACKOUT_HUNT"
			then baseVolumes[voiceIndex]
				* ((sequencePhase == "PLAYING" or sequencePhase == "ARMED" or sequencePhase == "PRE_BLACKOUT") and .24 or 1)
			else 0
		voice.Sound.Volume += (humTarget - voice.Sound.Volume) * math.clamp(elapsed / .65, 0, 1)
		if humTarget > 0 and not voice.Sound.IsPlaying then voice.Sound:Play() end
		if humTarget == 0 and voice.Sound.Volume < .003 and voice.Sound.IsPlaying then voice.Sound:Stop() end
	end
end)

bindClientEvent()
refreshWorld()
