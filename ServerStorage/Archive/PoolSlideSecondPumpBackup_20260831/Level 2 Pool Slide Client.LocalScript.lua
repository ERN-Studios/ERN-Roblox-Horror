-- Level 2 Pool Slide Client
-- Local presentation only. The server owns the third-pump spawn, movement,
-- target selection and damage. This script publishes no assets or audio.
--
-- Supports one shared 24-bone skeleton under RootPart, or an importer that
-- duplicates it across material-split meshes. A name maps to every Bone copy.

local ReplicatedStorage = game:GetService("ReplicatedStorage")
local RunService = game:GetService("RunService")

local ASSETS_NAME = "Level 2 Assets"
local WORLD_NAME = "Level 2 Generated World"
local RUNTIME_NAME = "Level 2 Pool Slide Runtime"
local MODEL_NAME = "Level 2 Pool Slide"
local DISCOVERY_INTERVAL = 0.5
local TRANSITION_DURATION = 0.18
local WALK_REFERENCE_SPEED = 10
local RUN_REFERENCE_SPEED = 24
local RUN_ENTER_SPEED = 17.5
local RUN_EXIT_SPEED = 14.5

local clipSources = {
	Idle = {Name = "Level 2 Pool Slide Idle Keyframes", Connections = {}},
	Walk = {Name = "Level 2 Pool Slide Walk Keyframes", Connections = {}},
	Run = {Name = "Level 2 Pool Slide Run Keyframes", Connections = {}},
}

local currentModel
local bonesByName = {}
local boneNames = {}
local modelConnections = {}
local currentClip
local currentClipName
local clipTime = 0
local transitionTime = TRANSITION_DURATION
local transitionFrom = {}
local displayedPose = {}
local animationApplied = false
local locomotionName = "Walk"
local discoveryTime = DISCOVERY_INTERVAL
local stopped = false

local function finiteNumber(value, fallback)
	if typeof(value) == "number" and value == value and math.abs(value) < math.huge then
		return value
	end
	return fallback
end

local function disconnectAll(connections)
	for _, connection in ipairs(connections) do connection:Disconnect() end
	table.clear(connections)
end

local function unregisterBone(bone)
	local name = boneNames[bone]
	if not name then return end
	if bone.Parent then bone.Transform = CFrame.identity end
	boneNames[bone] = nil
	local copies = bonesByName[name]
	if not copies then return end
	for index = #copies, 1, -1 do
		if copies[index] == bone then table.remove(copies, index) end
	end
	if #copies == 0 then bonesByName[name] = nil end
end

local function registerBone(descendant)
	if not descendant:IsA("Bone") or boneNames[descendant] then return end
	local name = descendant.Name
	local copies = bonesByName[name]
	if not copies then
		copies = {}
		bonesByName[name] = copies
	end
	boneNames[descendant] = name
	table.insert(copies, descendant)
	-- A MeshPart can stream in after its siblings are already animating.
	descendant.Transform = displayedPose[name] or CFrame.identity
end

local function bindModel(model)
	if model == currentModel then return end
	disconnectAll(modelConnections)
	for bone in pairs(boneNames) do
		if bone.Parent then bone.Transform = CFrame.identity end
	end
	table.clear(bonesByName)
	table.clear(boneNames)
	table.clear(displayedPose)
	table.clear(transitionFrom)
	currentModel = model
	currentClip = nil
	currentClipName = nil
	clipTime = 0
	transitionTime = TRANSITION_DURATION
	animationApplied = false
	locomotionName = "Walk"
	if not model then return end
	-- Connect before scanning so late-arriving descendants cannot be missed.
	table.insert(modelConnections, model.DescendantAdded:Connect(registerBone))
	table.insert(modelConnections, model.DescendantRemoving:Connect(function(descendant)
		if descendant:IsA("Bone") then unregisterBone(descendant) end
	end))
	for _, descendant in ipairs(model:GetDescendants()) do registerBone(descendant) end
end

local function locateModel()
	local world = workspace:FindFirstChild(WORLD_NAME)
	local runtime = world and world:FindFirstChild(RUNTIME_NAME)
	local model = runtime and runtime:FindFirstChild(MODEL_NAME)
	return model and model:IsA("Model") and model or nil
end

local function compileClip(sequence)
	local frames = sequence:GetKeyframes()
	if #frames == 0 then return nil end
	table.sort(frames, function(a, b) return a.Time < b.Time end)
	local startTime = frames[1].Time
	local duration = math.max(0, frames[#frames].Time - startTime)
	local tracks = {}
	for _, frame in ipairs(frames) do
		local time = frame.Time - startTime
		for _, pose in ipairs(frame:GetDescendants()) do
			if pose:IsA("Pose") then
				local track = tracks[pose.Name]
				if not track then
					track = {}
					tracks[pose.Name] = track
				end
				local sample = {Time = time, Transform = pose.CFrame}
				-- Do not divide by zero if an imported sequence repeats a timestamp.
				if #track > 0 and track[#track].Time == time then
					track[#track] = sample
				else
					table.insert(track, sample)
				end
			end
		end
	end
	if next(tracks) == nil then return nil end
	return {Duration = duration, Tracks = tracks}
end

local function refreshClips()
	-- FindFirstChild + bounded polling intentionally replaces WaitForChild:
	-- missing/late-streamed assets never block this client indefinitely.
	local assets = ReplicatedStorage:FindFirstChild(ASSETS_NAME)
	for _, source in pairs(clipSources) do
		local candidate = assets and assets:FindFirstChild(source.Name)
		if not (candidate and candidate:IsA("KeyframeSequence")) then candidate = nil end
		if candidate ~= source.Sequence then
			disconnectAll(source.Connections)
			source.Sequence = candidate
			source.Clip = nil
			source.Dirty = true
			if candidate then
				local function markDirty() source.Dirty = true end
				table.insert(source.Connections, candidate.DescendantAdded:Connect(markDirty))
				table.insert(source.Connections, candidate.DescendantRemoving:Connect(markDirty))
			end
		end
		if source.Dirty then
			source.Clip = candidate and compileClip(candidate) or nil
			source.Dirty = false
		end
	end
end

local function sampleTrack(track, time)
	if not track or #track == 0 then return CFrame.identity end
	if #track == 1 or time <= track[1].Time then return track[1].Transform end
	if time >= track[#track].Time then return track[#track].Transform end
	-- Keyframe samples need not be uniformly spaced. Search the actual times
	-- independently for each bone, including sparsely keyed imported tracks.
	local lowerIndex, upperIndex = 1, #track
	while upperIndex - lowerIndex > 1 do
		local middleIndex = math.floor((lowerIndex + upperIndex) / 2)
		if track[middleIndex].Time <= time then
			lowerIndex = middleIndex
		else
			upperIndex = middleIndex
		end
	end
	local lower, upper = track[lowerIndex], track[upperIndex]
	local interval = upper.Time - lower.Time
	local alpha = interval > 0 and math.clamp((time - lower.Time) / interval, 0, 1) or 0
	return lower.Transform:Lerp(upper.Transform, alpha)
end

local function chooseClip(moving, speed)
	if not moving or speed <= 0.1 then
		return "Idle", clipSources.Idle.Clip
	end
	if locomotionName == "Run" then
		if speed < RUN_EXIT_SPEED then locomotionName = "Walk" end
	elseif speed > RUN_ENTER_SPEED then
		locomotionName = "Run"
	end
	if clipSources[locomotionName].Clip then
		return locomotionName, clipSources[locomotionName].Clip
	end
	-- A single missing clip does not freeze the whole character. At rest only
	-- the real Idle clip (or neutral bind pose) is used, never a walking pose.
	local alternate = locomotionName == "Run" and "Walk" or "Run"
	if clipSources[alternate].Clip then return alternate, clipSources[alternate].Clip end
	return "Idle", clipSources.Idle.Clip
end

local function selectClip(name, clip)
	if name == currentClipName and clip == currentClip then return end
	local oldClip, oldName, oldTime = currentClip, currentClipName, clipTime
	transitionFrom = {}
	for boneName, transform in pairs(displayedPose) do transitionFrom[boneName] = transform end
	currentClipName = name
	currentClip = clip
	clipTime = 0
	-- Keep footfall phase when switching between locomotion clips; blend the
	-- actual displayed pose for 180 ms so speed threshold crossings do not pop.
	if oldClip and clip and oldClip.Duration > 0 and clip.Duration > 0
		and oldName ~= "Idle" and name ~= "Idle" then
		clipTime = (oldTime / oldClip.Duration) * clip.Duration
	end
	transitionTime = animationApplied and 0 or TRANSITION_DURATION
end

local function applyAnimation(deltaTime)
	if stopped then return end
	deltaTime = math.max(0, finiteNumber(deltaTime, 0))
	discoveryTime = discoveryTime + deltaTime
	if discoveryTime >= DISCOVERY_INTERVAL then
		discoveryTime = 0
		refreshClips()
	end
	bindModel(locateModel())
	local model = currentModel
	if not (model and model.Parent) then return end
	local paused = model:GetAttribute("Level2_PoolSlideState") == "PAUSED"
	-- Freeze the exact displayed pose while the authoritative controller is
	-- paused. A newly streamed paused model gets one idle pose, not a T-pose.
	if paused and animationApplied and currentClip then return end
	local speed = math.max(0, finiteNumber(model:GetAttribute("Level2_PoolSlideSpeed"), 0))
	local moving = not paused and model:GetAttribute("Level2_PoolSlideMoving") == true
	local name, clip = chooseClip(moving, speed)
	selectClip(name, clip)
	local step = paused and 0 or deltaTime
	if currentClip and currentClip.Duration > 0 then
		local rate = 1
		if currentClipName == "Walk" then
			rate = math.clamp(speed / WALK_REFERENCE_SPEED, 0.2, 2.5)
		elseif currentClipName == "Run" then
			rate = math.clamp(speed / RUN_REFERENCE_SPEED, 0.2, 2.0)
		end
		clipTime = (clipTime + step * rate) % currentClip.Duration
	end
	transitionTime = math.min(TRANSITION_DURATION, transitionTime + step)
	local alpha = transitionTime / TRANSITION_DURATION
	alpha = alpha * alpha * (3 - 2 * alpha)
	for boneName, copies in pairs(bonesByName) do
		local track = currentClip and currentClip.Tracks[boneName]
		local target = sampleTrack(track, clipTime)
		local from = transitionFrom[boneName] or CFrame.identity
		local transform = alpha < 1 and from:Lerp(target, alpha) or target
		displayedPose[boneName] = transform
		for _, bone in ipairs(copies) do
			if bone.Parent then bone.Transform = transform end
		end
	end
	animationApplied = true
end

local animationConnection = RunService.PreSimulation:Connect(applyAnimation)
script.Destroying:Connect(function()
	stopped = true
	animationConnection:Disconnect()
	bindModel(nil)
	for _, source in pairs(clipSources) do disconnectAll(source.Connections) end
end)
