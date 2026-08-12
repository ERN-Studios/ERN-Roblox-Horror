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
	FluorescentHum = "rbxassetid://9112889325",
	HVAC = "rbxassetid://9125446543",
	DoorRattle = "rbxassetid://9118901593",
	DoorMovement = "rbxassetid://9119631915",
	ReaderBeep = "rbxassetid://9119103325",
	WaterDrip = "rbxassetid://9126193223",
}

local LIBRARY_ALIASES: {[string]: {string}} = {
	FluorescentHum = {"FluorescentHum", "Level 3 Fluorescent Hum"},
	HVAC = {"HVAC", "Level 3 HVAC"},
	DoorRattle = {"DoorRattle", "Level 3 Door Rattle"},
	DoorMovement = {"DoorMovement", "Level 3 Door Movement"},
	ReaderBeep = {"ReaderBeep", "Level 3 Reader Beep"},
	WaterDrip = {"WaterDrip", "Level 3 Water Drip"},
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

local function currentWorld(): Model?
	local object = workspace:FindFirstChild(WORLD_NAME)
	return if object and object:IsA("Model") then object else nil
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
	ModuleCollected = {Key="ReaderBeep", Volume=0.31, Speed=1.06},
	DoorMovement = {Key="DoorMovement", Volume=0.34, Speed=1.00},
	DoorLocked = {Key="DoorRattle", Volume=0.38, Speed=0.88},
	ExitUnlocked = {Key="ReaderBeep", Volume=0.42, Speed=1.20},
	Escape = {Key="ReaderBeep", Volume=0.30, Speed=1.32},
}

local function playCue(cueValue: any, positionValue: any)
	if type(cueValue) ~= "string" then return end
	local spec = CUES[cueValue]
	if not spec then return end
	local position = if typeof(positionValue) == "Vector3" then positionValue :: Vector3 else nil
	playOneShot(spec.Key, cueValue, position, spec.Volume, spec.Speed)
	if cueValue == "ExitUnlocked" then
		-- A quiet two-note confirmation, not a horror sting.
		task.delay(0.18, function()
			playOneShot("ReaderBeep", "ExitUnlockedSecond", nil, 0.27, 1.34)
		end)
	end
end

local function handleClientEvent(payload: any)
	if type(payload) ~= "table" or not isActive() or not generationMatches(payload) then return end
	if payload.Type == "Sound" then
		playCue(payload.Cue, payload.Position)
	end
end

local function bindClientEvent()
	local folder = ReplicatedStorage:FindFirstChild(REMOTES_FOLDER_NAME)
	local candidate = folder and folder:FindFirstChild(CLIENT_EVENT_NAME)
	local event = if candidate and candidate:IsA("RemoteEvent") then candidate else nil
	if event == boundClientEvent then return end
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
end

local function bindWorld(world: Model?)
	if world == boundWorld then return end
	if worldAddedConnection then worldAddedConnection:Disconnect() end
	if worldRemovingConnection then worldRemovingConnection:Disconnect() end
	worldAddedConnection = nil
	worldRemovingConnection = nil
	clearAmbience()
	boundWorld = world
	if not world then return end
	for _, descendant in ipairs(world:GetDescendants()) do tryAddAmbience(descendant) end
	worldAddedConnection = world.DescendantAdded:Connect(function(descendant)
		task.defer(function()
			if world == boundWorld and descendant:IsDescendantOf(world) then tryAddAmbience(descendant) end
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

	if progress == 0 then
		playOneShot("ReaderBeep", "ReaderPulse", nil, 0.10, 0.76 + random:NextNumber(-0.04, 0.04))
		nextReaderBeep = now + random:NextNumber(6.5, 9.5)
		return
	end

	local interval = 5.0 - calibration * 3.2 - signal * (unlocked and 1.05 or 0.55)
	interval = math.clamp(interval, unlocked and 0.72 or 1.25, 5)
	local volume = 0.10 + calibration * 0.08 + signal * 0.05
	local speed = 0.78 + calibration * 0.11 + signal * 0.13
	playOneShot("ReaderBeep", "ReaderPulse", nil, volume, speed)
	nextReaderBeep = now + interval
end

-- Preload the small, allowlisted cue set. Empty/failed assets remain harmless.
task.spawn(function()
	local temporary: {Sound} = {}
	for _, key in ipairs({"DoorRattle", "DoorMovement", "ReaderBeep"}) do
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
			local target = if playing then record.TargetVolume else 0
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
	updateReaderCadence(now)
end)

bindClientEvent()
refreshWorld()
