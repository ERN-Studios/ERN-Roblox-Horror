local Players = game:GetService("Players")
local ReplicatedStorage = game:GetService("ReplicatedStorage")
local RunService = game:GetService("RunService")
local Debris = game:GetService("Debris")

local player = Players.LocalPlayer
local rng = Random.new()
local state = ReplicatedStorage:WaitForChild("Level 2 State")
local library = ReplicatedStorage:WaitForChild("Level 2 Sound Library")
local assets = ReplicatedStorage:WaitForChild("Level 2 Assets")
local walkSequence = assets:WaitForChild("Level 2 Slidemouth Walk Keyframes")

local MONSTER_SLOTS = {
	"Level 2 Distant Monster-Like Pipe Groan 1",
	"Level 2 Distant Monster-Like Pipe Groan 2",
	"Level 2 Distant Monster-Like Pipe Groan 3",
	"Level 2 Distant Monster-Like Pipe Groan 4",
}

local function resolveId(slotName)
	local slot = library:FindFirstChild(slotName)
	local raw = slot and slot:IsA("StringValue") and slot.Value or ""
	raw = tostring(raw):gsub("%s", "")
	if raw == "" then return nil end
	if raw:match("^%d+$") then return "rbxassetid://" .. raw end
	return raw
end

local function localRoundActive()
	return workspace:GetAttribute("SelectedLevel") == 2
		and workspace:GetAttribute("RoundActive") == true
		and workspace:GetAttribute("WorldGenerated") == true
		and player:GetAttribute("InRound") == true
		and player:GetAttribute("Escaped") ~= true
		and player:GetAttribute("Spectating") ~= true
		and player:GetAttribute("IsSpectating") ~= true
end

local frames = {}
for _, keyframe in ipairs(walkSequence:GetKeyframes()) do
	local poses = {}
	for _, descendant in ipairs(keyframe:GetDescendants()) do
		if descendant:IsA("Pose") then poses[descendant.Name] = descendant.CFrame end
	end
	table.insert(frames, {Time = keyframe.Time, Poses = poses})
end
table.sort(frames, function(a, b) return a.Time < b.Time end)
local clipDuration = #frames > 0 and frames[#frames].Time or 1
local sampleRate = #frames > 1 and (#frames - 1) / math.max(clipDuration, .001) or 1

local currentModel
local currentBones = {}
local animationTime = 0
local animationApplied = false
local monsterBag = {}
local lastMonsterSlot
local lastScreamSerial = tonumber(state:GetAttribute("Level2_SlidemouthScreamSerial")) or 0
local lastWarningSerial = tonumber(state:GetAttribute("Level2_SlidemouthWarningSerial")) or 0
local currentVoice
local warningVoice

local function resetBones()
	for _, bone in pairs(currentBones) do
		if bone.Parent then bone.Transform = CFrame.identity end
	end
	currentBones = {}
	animationApplied = false
end

local function destroyVoice()
	if currentVoice and currentVoice.Parent then currentVoice:Destroy() end
	currentVoice = nil
end

local function locateModel()
	local world = workspace:FindFirstChild("Level 2 Generated World")
	local runtime = world and world:FindFirstChild("Level 2 Slidemouth Runtime")
	local model = runtime and runtime:FindFirstChild("Level 2 Slidemouth")
	return model and model:IsA("Model") and model or nil
end

local function bindModel(model)
	if model == currentModel then return end
	resetBones()
	destroyVoice()
	currentModel = model
	animationTime = 0
	-- Keep one shuffle bag and shared serial baseline across the unseen
	-- warning and the spawned creature so pump responses never replay.
	if not model then return end
	for _, descendant in ipairs(model:GetDescendants()) do
		if descendant:IsA("Bone") then currentBones[descendant.Name] = descendant end
	end
end

local function nextMonsterSlot()
	if #monsterBag == 0 then
		for _, slotName in ipairs(MONSTER_SLOTS) do table.insert(monsterBag, slotName) end
		for index = #monsterBag, 2, -1 do
			local swapIndex = rng:NextInteger(1, index)
			monsterBag[index], monsterBag[swapIndex] = monsterBag[swapIndex], monsterBag[index]
		end
		if #monsterBag > 1 and monsterBag[#monsterBag] == lastMonsterSlot then
			monsterBag[1], monsterBag[#monsterBag] = monsterBag[#monsterBag], monsterBag[1]
		end
	end
	local slotName = table.remove(monsterBag)
	lastMonsterSlot = slotName
	return slotName
end

local function destroyWarningVoice()
	if warningVoice and warningVoice.Parent then
		local emitter = warningVoice.Parent
		warningVoice:Destroy()
		if emitter:IsA("BasePart") then emitter:Destroy() end
	end
	warningVoice = nil
end

local function playWarningScream(position, pumpNumber)
	if not (localRoundActive() and typeof(position) == "Vector3") then return false end
	pumpNumber = math.clamp(math.floor(tonumber(pumpNumber) or 1), 1, 3)
	destroyWarningVoice()
	local slotName = nextMonsterSlot()
	local id = resolveId(slotName)
	if not id then return false end

	local emitter = Instance.new("Part")
	emitter.Name = "Slidemouth Unseen Pump Warning"
	emitter.Anchored = true
	emitter.CanCollide = false
	emitter.CanTouch = false
	emitter.CanQuery = false
	emitter.CastShadow = false
	emitter.Transparency = 1
	emitter.Size = Vector3.new(.2, .2, .2)
	emitter.Position = position
	emitter.Parent = workspace

	local sound = Instance.new("Sound")
	sound.Name = "Slidemouth Pump " .. pumpNumber .. " Response - " .. slotName
	sound.SoundId = id
	sound.Volume = pumpNumber >= 3 and 3.6 or (pumpNumber == 2 and 3.25 or 3.1)
	sound.PlaybackSpeed = rng:NextNumber(.97, 1.03)
	sound.RollOffMode = Enum.RollOffMode.InverseTapered
	sound.RollOffMinDistance = 90
	sound.RollOffMaxDistance = 560
	sound.Parent = emitter
	warningVoice = sound
	sound:Play()
	Debris:AddItem(emitter, 20)
	return true
end

local function updateWarningScream()
	local serial = tonumber(state:GetAttribute("Level2_SlidemouthWarningSerial")) or 0
	if serial < lastWarningSerial then
		lastWarningSerial = serial
		return
	end
	if serial > lastWarningSerial then
		lastWarningSerial = serial
		playWarningScream(
			state:GetAttribute("Level2_SlidemouthWarningPosition"),
			state:GetAttribute("Level2_SlidemouthWarningPump")
		)
	end
	if not localRoundActive() and warningVoice then destroyWarningVoice() end
end

local function playScream(screamKind)
	local model = currentModel
	if not (model and model.Parent and localRoundActive()) then return false end
	local pumpAlert = screamKind == "PUMP_2" or screamKind == "PUMP_3"
	if not pumpAlert then return false end
	if currentVoice and currentVoice.Parent then
		currentVoice:Destroy()
		currentVoice = nil
	end
	local emitter = model:FindFirstChild("SlidemouthAudioEmitter", true)
	if not (emitter and emitter:IsA("Attachment")) then return false end
	local slotName = nextMonsterSlot()
	local id = resolveId(slotName)
	if not id then return false end
	local sound = Instance.new("Sound")
	sound.Name = "Slidemouth Local Chase Scream - " .. slotName
	sound.SoundId = id
	if screamKind == "PUMP_3" then
		sound.Volume = 3.6
	elseif screamKind == "PUMP_2" then
		sound.Volume = 3.25
	else
		return false
	end
	sound.PlaybackSpeed = rng:NextNumber(.97, 1.03)
	sound.RollOffMode = Enum.RollOffMode.InverseTapered
	sound.RollOffMinDistance = 80
	sound.RollOffMaxDistance = 340
	sound.Parent = emitter
	currentVoice = sound
	sound:Play()
	Debris:AddItem(sound, 20)
	return true
end

local function updateAudio()
	updateWarningScream()
	bindModel(locateModel())
	if not localRoundActive() then
		if currentVoice then destroyVoice() end
		return
	end
	local serial = tonumber(state:GetAttribute("Level2_SlidemouthScreamSerial")) or 0
	local screamKind = tostring(state:GetAttribute("Level2_SlidemouthScreamKind") or "")
	if serial < lastScreamSerial then
		lastScreamSerial = serial
	elseif serial > lastScreamSerial then
		lastScreamSerial = serial
		if screamKind == "PUMP_2" or screamKind == "PUMP_3" then
			local pumpNumber = screamKind == "PUMP_3" and 3 or 2
			if not playScream(screamKind) then
				playWarningScream(
					state:GetAttribute("Level2_SlidemouthScreamPosition"),
					pumpNumber
				)
			end
		end
	end
end

local function applyAnimation(deltaTime)
	bindModel(locateModel())
	local model = currentModel
	if not (model and model.Parent and #frames > 0) then return end
	-- Keep the gait alive during a brief graph detour so the creature never
	-- freezes visually while its anti-stuck recovery picks a clear side route.
	-- Freeze on the exact gait pose reached when physical movement stops.
	local moving = model:GetAttribute("Level2_SlidemouthMoving") == true
	local speed = tonumber(model:GetAttribute("Level2_SlidemouthSpeed")) or 0
	if moving then
		animationTime = (animationTime + deltaTime * math.clamp(speed / 12.5, .2, 3.2))
			% math.max(clipDuration, .001)
	end
	if not moving and animationApplied then return end
	local sample = animationTime * sampleRate
	local lowerIndex = math.clamp(math.floor(sample) + 1, 1, #frames)
	local upperIndex = math.min(lowerIndex + 1, #frames)
	local alpha = math.clamp(sample - math.floor(sample), 0, 1)
	local lower = frames[lowerIndex].Poses
	local upper = frames[upperIndex].Poses
	for name, bone in pairs(currentBones) do
		if bone.Parent then
			local from = lower[name] or CFrame.identity
			local to = upper[name] or from
			bone.Transform = from:Lerp(to, alpha)
		end
	end
	animationApplied = true
end

RunService.Heartbeat:Connect(updateAudio)
RunService.PreRender:Connect(applyAnimation)
