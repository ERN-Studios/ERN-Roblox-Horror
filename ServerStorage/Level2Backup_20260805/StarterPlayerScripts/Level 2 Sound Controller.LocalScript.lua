local Players = game:GetService("Players")
local ReplicatedStorage = game:GetService("ReplicatedStorage")
local RunService = game:GetService("RunService")
local SoundService = game:GetService("SoundService")
local Debris = game:GetService("Debris")

local player = Players.LocalPlayer
local library = ReplicatedStorage:WaitForChild("Level 2 Sound Library")
local soundEvent = ReplicatedStorage:WaitForChild("Level 2 Sound Event")
local rng = Random.new()

local soundGroup = SoundService:FindFirstChild("Level 2 Sound Group") or Instance.new("SoundGroup")
soundGroup.Name = "Level 2 Sound Group"
soundGroup.Volume = .8
soundGroup.Parent = SoundService

local loops = {}
local stepClock = 0
local swimClock = 0

local function active()
	return workspace:GetAttribute("SelectedLevel") == 2 and player:GetAttribute("InRound") == true
end

local function soundId(slotName)
	local value = library:FindFirstChild(slotName)
	if not value or not value:IsA("StringValue") then return nil end
	local id = tostring(value.Value or ""):match("^%s*(.-)%s*$")
	if id == "" then return nil end
	if id:match("^%d+$") then id = "rbxassetid://" .. id end
	return id
end

local function newSound(name, parent, volume, looped)
	local id = soundId(name)
	if not id then return nil end
	local sound = Instance.new("Sound")
	sound.Name = name
	sound.SoundId = id
	sound.Volume = volume or .4
	sound.Looped = looped == true
	sound.RollOffMode = Enum.RollOffMode.InverseTapered
	sound.RollOffMinDistance = 8
	sound.RollOffMaxDistance = 110
	sound.SoundGroup = soundGroup
	sound.Parent = parent
	return sound
end

local function ensureLoops()
	local parent = SoundService
	for _, data in ipairs({
		{"Level 2 Room Tone", .23},
		{"Level 2 Ventilation Hum", .16},
		{"Level 2 Fluorescent Buzz", .10},
		{"Level 2 Distant Water", .17},
	}) do
		local name, volume = data[1], data[2]
		if not loops[name] then loops[name] = newSound(name, parent, volume, true) end
		local sound = loops[name]
		if sound then
			if active() and not sound.IsPlaying then sound:Play() end
			if not active() and sound.IsPlaying then sound:Stop() end
		end
	end
end

local function positionalOneShot(name, position, volume, pitch)
	local id = soundId(name)
	if not id then return end
	local emitter = Instance.new("Part")
	emitter.Name = "Level 2 Temporary Sound Emitter"
	emitter.Anchored = true
	emitter.CanCollide = false
	emitter.CanTouch = false
	emitter.CanQuery = false
	emitter.Transparency = 1
	emitter.Size = Vector3.new(.2, .2, .2)
	emitter.Position = position
	emitter.Parent = workspace
	local sound = Instance.new("Sound")
	sound.Name = name
	sound.SoundId = id
	sound.Volume = volume or .5
	sound.PlaybackSpeed = pitch or 1
	sound.RollOffMode = Enum.RollOffMode.InverseTapered
	sound.RollOffMinDistance = 5
	sound.RollOffMaxDistance = 130
	sound.SoundGroup = soundGroup
	sound.Parent = emitter
	sound:Play()
	Debris:AddItem(emitter, 14)
end

local function rootPart()
	local character = player.Character
	return character and character:FindFirstChild("HumanoidRootPart")
end

local function humanoid()
	local character = player.Character
	return character and character:FindFirstChildOfClass("Humanoid")
end

local function inTerrainWater(position)
	local region = Region3.new(position - Vector3.new(2, 2, 2), position + Vector3.new(2, 2, 2)):ExpandToGrid(4)
	local ok, materials, occupancy = pcall(function()
		return workspace.Terrain:ReadVoxels(region, 4)
	end)
	if not ok then return false end
	for x = 1, #materials do
		for y = 1, #materials[x] do
			for z = 1, #materials[x][y] do
				if materials[x][y][z] == Enum.Material.Water and occupancy[x][y][z] > .05 then return true end
			end
		end
	end
	return false
end

local function playAtPlayer(slotName, volume, pitch)
	local root = rootPart()
	if root then positionalOneShot(slotName, root.Position, volume, pitch) end
end

soundEvent.OnClientEvent:Connect(function(cue)
	if not active() then return end
	if cue == "Level 2 Valve Turn" then playAtPlayer(cue, .58, rng:NextNumber(.97, 1.03))
	elseif cue == "Level 2 Exit Unlock" then playAtPlayer(cue, .75, 1)
	elseif cue == "Level 2 Slide Rush" then playAtPlayer(cue, .55, 1) end
end)

task.spawn(function()
	local scareSlots = {
		"Level 2 Water Drop",
		"Level 2 Distant Splash",
		"Level 2 Ceramic Knock",
		"Level 2 Drain Gurgle",
		"Level 2 Pipe Groan",
		"Level 2 Underwater Thump",
	}
	while true do
		task.wait(rng:NextNumber(11, 28))
		local root = rootPart()
		if active() and root then
			local angle = rng:NextNumber(0, math.pi * 2)
			local distance = rng:NextNumber(24, 76)
			local vertical = rng:NextNumber(-5, 8)
			local position = root.Position + Vector3.new(math.cos(angle) * distance, vertical, math.sin(angle) * distance)
			local slot = scareSlots[rng:NextInteger(1, #scareSlots)]
			positionalOneShot(slot, position, rng:NextNumber(.28, .58), rng:NextNumber(.91, 1.07))
		end
	end
end)

RunService.Heartbeat:Connect(function(dt)
	ensureLoops()
	if not active() then stepClock, swimClock = 0, 0 return end
	local root = rootPart()
	local human = humanoid()
	if not root or not human or human.Health <= 0 then return end
	local moving = human.MoveDirection.Magnitude > .15
	local swimming = human:GetState() == Enum.HumanoidStateType.Swimming
	if swimming then
		swimClock += dt
		if moving and swimClock >= .82 then
			swimClock = 0
			playAtPlayer("Level 2 Swim Stroke " .. rng:NextInteger(1, 2), .34, rng:NextNumber(.94, 1.06))
		end
		return
	end
	if moving and inTerrainWater(root.Position - Vector3.new(0, 2.4, 0)) then
		stepClock += dt
		local cadence = human.WalkSpeed > 17 and .34 or .48
		if stepClock >= cadence then
			stepClock = 0
			playAtPlayer("Level 2 Shallow Footstep " .. rng:NextInteger(1, 3), .38, rng:NextNumber(.92, 1.08))
		end
	else
		stepClock = 0
	end
end)

workspace:GetAttributeChangedSignal("SelectedLevel"):Connect(ensureLoops)
player:GetAttributeChangedSignal("InRound"):Connect(ensureLoops)
ensureLoops()
