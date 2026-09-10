-- Draft native-Animator adapter. Requires actual imported rig and published clips.
-- No fallback to a different skeleton or a silent static mesh.
local RunService = game:GetService("RunService")
local RigAdapter = {}
local NAMES = {"Idle", "Walk", "Run", "Attack"}

local function finitePositive(value)
	return type(value) == "number" and value == value and value > 0 and value < math.huge
end

local function destroyTracks(tracks)
	-- Teardown must continue even if an externally removed Animator makes one
	-- Stop/Destroy fail; otherwise Controller.Stop could abandon the entire world.
	local firstFailure
	for _, name in ipairs(NAMES) do
		local track = tracks[name]
		tracks[name] = nil
		if track then
			local stopOk, stopFailure = pcall(function() track:Stop(0) end)
			local destroyOk, destroyFailure = pcall(function() track:Destroy() end)
			if not stopOk then firstFailure = firstFailure or stopFailure end
			if not destroyOk then firstFailure = firstFailure or destroyFailure end
		end
	end
	if firstFailure then warn("[Level 2 Pool Slide] animation cleanup: " .. tostring(firstFailure)) end
end

function RigAdapter.PrepareModel(model)
	assert(model:IsA("Model") and model.PrimaryPart, "missing rig root")
	local root = model.PrimaryPart
	assert(root.Name == "RootPart", "root must be normalized before integration")
	local linkedMeshes = {}
	-- Studio's Custom importer uses one shared Bone tree under invisible RootPart,
	-- with static root-to-skinned-mesh Motor6Ds. Keep these bind links intact. They
	-- are not animated limb joints; arbitrary Motor6D character rigs still fail.
	for _, object in ipairs(model:GetDescendants()) do
		if object:IsA("Motor6D") then
			local mesh = object.Part1
			assert(object.Part0 == root and mesh and mesh:IsA("MeshPart")
				and mesh:IsDescendantOf(model) and mesh ~= root and not linkedMeshes[mesh],
				"only one static RootPart-to-MeshPart bind link is allowed per mesh")
			local _, transformAngle = object.Transform:ToAxisAngle()
			assert(object.Transform.Position.Magnitude < 1e-5 and math.abs(transformAngle) < 1e-5,
				"static mesh bind link has an animated Transform")
			local closure = (root.CFrame * object.C0):ToObjectSpace(mesh.CFrame * object.C1)
			local _, closureAngle = closure:ToAxisAngle()
			assert(closure.Position.Magnitude < 0.005 and math.abs(closureAngle) < 1e-4,
				"static mesh bind link does not match imported rest placement")
			linkedMeshes[mesh] = true
		end
	end
	for _, object in ipairs(model:GetDescendants()) do
		if object:IsA("BasePart") then
			object.CanCollide, object.CanTouch, object.CanQuery = false, false, false
			object.Massless = true
			-- Skinned MeshParts may be anchored; bone deformation still animates.
			-- Static importer bind links remain intact; bones provide articulation.
			object.Anchored = true
		elseif object:IsA("BaseScript") then
			object.Enabled = false
		end
	end
	assert(model:FindFirstChildWhichIsA("Bone", true), "expected this Meshy skinned-bone rig")
	return model
end

function RigAdapter.Attach(model, configuration)
	assert(RunService:IsServer(), "Pool Slide NPC animations must load and start on the server")
	assert(model:IsDescendantOf(workspace), "Animator load requires the validated positioned rig in Workspace")
	assert(finitePositive(configuration.WalkAnimationReferenceSpeed),
		"missing measured walk animation reference speed")
	assert(finitePositive(configuration.RunAnimationReferenceSpeed),
		"missing measured run animation reference speed")
	local controller = model:FindFirstChildOfClass("AnimationController")
	assert(controller, "missing AnimationController on imported rig")
	local animator = controller:FindFirstChildOfClass("Animator")
	assert(animator, "Animator must be created on server before replication")
	local clips = model:FindFirstChild("Animations")
	assert(clips, "missing rig-specific Animations folder")
	local tracks = {}
	local ok, problem = pcall(function()
		for _, name in ipairs(NAMES) do
			local clip = clips:FindFirstChild(name)
			local assetId = clip and clip:IsA("Animation") and clip.AnimationId:match("^rbxassetid://(%d+)$")
			assert(assetId and finitePositive(tonumber(assetId)),
				"missing published " .. name .. " animation for this rig")
			local track = animator:LoadAnimation(clip)
			tracks[name] = track
			track.Looped = name ~= "Attack"
			track.Priority = name == "Attack" and Enum.AnimationPriority.Action
				or name == "Idle" and Enum.AnimationPriority.Idle or Enum.AnimationPriority.Movement
		end
	end)
	if not ok then
		destroyTracks(tracks)
		error(problem)
	end
	local driver = {State = nil, Paused = false, Destroyed = false, AttackSerial = 0, Rate = 1, LastRateAt = 0, AppliedRate = nil}
	local function rateFor(name, speed)
		if name == "Walk" then
			return math.clamp(speed / configuration.WalkAnimationReferenceSpeed, .05, 2.5)
		elseif name == "Run" then
			return math.clamp(speed / configuration.RunAnimationReferenceSpeed, .05, 2.5)
		end
		return 1
	end
	function driver:Motion(name, speed)
		if self.Destroyed then return end
		assert(tracks[name], "unknown rig animation: " .. tostring(name))
		assert(type(speed) == "number" and speed == speed and speed >= 0 and speed < math.huge,
			"invalid measured animation movement speed")
		local changed = self.State ~= name
		self.Rate = rateFor(name, speed)
		local applied = self.Paused and 0 or self.Rate
		if changed then
			for other, track in pairs(tracks) do
				if other ~= name and track.IsPlaying then track:Stop(.16) end
			end
			self.State = name
			-- Attack starts only through its monotonic server serial below.
			if name ~= "Attack" then tracks[name]:Play(.16, 1, applied) end
		end
		if name ~= "Attack" and (changed or (os.clock() - self.LastRateAt >= .1
			and (self.AppliedRate == nil or math.abs(applied - self.AppliedRate) >= .02))) then
			tracks[name]:AdjustSpeed(applied)
			self.LastRateAt, self.AppliedRate = os.clock(), applied
		end
	end
	function driver:Attack(serial)
		if self.Destroyed then return end
		assert(finitePositive(serial) and serial % 1 == 0, "invalid server attack serial")
		if serial <= self.AttackSerial then return end
		self.AttackSerial = serial
		self.State, self.Rate = "Attack", 1
		for name, track in pairs(tracks) do
			if name ~= "Attack" and track.IsPlaying then track:Stop(.12) end
		end
		tracks.Attack:Play(.12, 1, self.Paused and 0 or 1)
	end
	function driver:Pause(paused)
		if self.Destroyed then return end
		self.Paused = paused
		if self.State and tracks[self.State].IsPlaying then
			self.AppliedRate = paused and 0 or self.Rate
			tracks[self.State]:AdjustSpeed(self.AppliedRate)
		end
	end
	function driver:Destroy()
		if self.Destroyed then return end
		self.Destroyed = true
		if self.DestroyingConnection then
			local disconnected, failure = pcall(function() self.DestroyingConnection:Disconnect() end)
			if not disconnected then warn("[Level 2 Pool Slide] animation signal cleanup: " .. tostring(failure)) end
		end
		self.DestroyingConnection = nil
		destroyTracks(tracks)
		self.State, self.AppliedRate = nil, nil
	end
	local connected, connectionOrFailure = pcall(function()
		return model.Destroying:Connect(function() driver:Destroy() end)
	end)
	if not connected then driver:Destroy(); error(connectionOrFailure) end
	driver.DestroyingConnection = connectionOrFailure
	return driver
end

return RigAdapter
