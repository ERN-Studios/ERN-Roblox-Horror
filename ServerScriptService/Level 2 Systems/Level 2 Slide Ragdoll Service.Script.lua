-- Level 2 Slide Ragdoll Service
--
-- The client that owns a character predicts the ragdoll immediately, while
-- this service validates the slide contact and mirrors the structural joint
-- change so every observer sees the same tumble. The root joint always stays
-- enabled: it is the network-ownership anchor that pulls the loose body down
-- the flume.

local Players = game:GetService("Players")
local ReplicatedStorage = game:GetService("ReplicatedStorage")
local RunService = game:GetService("RunService")
local Workspace = game:GetService("Workspace")

local REMOTE_NAME = "Level2SlideRagdoll"
local MAX_RAGDOLL_SECONDS = 30

local remotes = ReplicatedStorage:FindFirstChild("Remotes")
if not remotes then
	remotes = Instance.new("Folder")
	remotes.Name = "Remotes"
	remotes.Parent = ReplicatedStorage
end

local remote = remotes:FindFirstChild(REMOTE_NAME)
if remote and not remote:IsA("RemoteEvent") then
	remote:Destroy()
	remote = nil
end
if not remote then
	remote = Instance.new("RemoteEvent")
	remote.Name = REMOTE_NAME
	remote.Parent = remotes
end

local sessions = {}
local collisionBaselines = {}
local generations = {}

local LEGACY_ANATOMY = {
	neck = true,
	waist = true,
	leftshoulder = true, rightshoulder = true,
	leftelbow = true, rightelbow = true,
	leftwrist = true, rightwrist = true,
	lefthip = true, righthip = true,
	leftknee = true, rightknee = true,
	leftankle = true, rightankle = true,
}

local function normalizedJointName(name)
	return string.lower(name):gsub("[%s_]", "")
end

local function isLegacyAnatomyMotor(motor)
	return motor:IsA("Motor6D") and LEGACY_ANATOMY[normalizedJointName(motor.Name)] == true
end

local function isRootConnection(name, part0, part1)
	return name == "Root" or name == "RootJoint"
		or (part0 and part0.Name == "HumanoidRootPart")
		or (part1 and part1.Name == "HumanoidRootPart")
end

local function attachmentPart(attachment)
	local current = attachment
	while current and not current:IsA("BasePart") do current = current.Parent end
	return current
end

local function matchingSocket(character, joint)
	local attachment0 = joint.Attachment0
	local attachment1 = joint.Attachment1
	if not (attachment0 and attachment1) then return nil end
	local jointPart0 = attachmentPart(attachment0)
	local jointPart1 = attachmentPart(attachment1)
	for _, descendant in ipairs(character:GetDescendants()) do
		if descendant:IsA("BallSocketConstraint") and descendant.Enabled then
			local socketPart0 = attachmentPart(descendant.Attachment0)
			local socketPart1 = attachmentPart(descendant.Attachment1)
			local sameOrder = socketPart0 == jointPart0 and socketPart1 == jointPart1
			local reverseOrder = socketPart0 == jointPart1 and socketPart1 == jointPart0
			if sameOrder or reverseOrder then return descendant end
		end
	end
	return nil
end

local function limitsFor(name)
	local lower = string.lower(name)
	if string.find(lower, "neck", 1, true) then return 45, -40, 40 end
	if string.find(lower, "waist", 1, true) then return 20, -40, 20 end
	if string.find(lower, "shoulder", 1, true) then return 110, -85, 85 end
	if string.find(lower, "elbow", 1, true) then return 20, 5, 120 end
	if string.find(lower, "hip", 1, true) then return 40, -5, 80 end
	if string.find(lower, "knee", 1, true) then return 5, -120, -5 end
	if string.find(lower, "wrist", 1, true) then return 30, -10, 10 end
	if string.find(lower, "ankle", 1, true) then return 10, -10, 10 end
	return 45, -45, 45
end

-- Older R6/R15 characters use Motor6Ds rather than the current AJU
-- AnimationConstraints. Give those joints permanent, dormant ball sockets;
-- their enabled motors dominate during ordinary play and releasing the motors
-- produces the same structure as the native AJU ragdoll.
local function prepareLegacyRig(character)
	if character:FindFirstChildWhichIsA("AnimationConstraint", true) then return end

	local folder = character:FindFirstChild("Level2SlideLegacyRig")
	if not folder then
		folder = Instance.new("Folder")
		folder.Name = "Level2SlideLegacyRig"
		folder.Parent = character
	end

	local index = 0
	for _, motor in ipairs(character:GetDescendants()) do
		if not isLegacyAnatomyMotor(motor) then continue end
		local part0, part1 = motor.Part0, motor.Part1
		if not (part0 and part1 and part0:IsDescendantOf(character)
			and part1:IsDescendantOf(character)) then continue end
		if isRootConnection(motor.Name, part0, part1) then continue end
		local alreadyPrepared = false
		for _, existing in ipairs(folder:GetChildren()) do
			if existing:IsA("BallSocketConstraint")
				and existing:GetAttribute("Level2SlideMotorName") == motor.Name then
				alreadyPrepared = true
				break
			end
		end
		if alreadyPrepared then continue end

		index += 1
		local attachment0 = Instance.new("Attachment")
		attachment0.Name = "Level2SlideJointA0_" .. index
		attachment0.CFrame = motor.C0
		attachment0:SetAttribute("Level2SlideLegacyAttachment", true)
		attachment0.Parent = part0

		local attachment1 = Instance.new("Attachment")
		attachment1.Name = "Level2SlideJointA1_" .. index
		attachment1.CFrame = motor.C1
		attachment1:SetAttribute("Level2SlideLegacyAttachment", true)
		attachment1.Parent = part1

		local upper, twistLower, twistUpper = limitsFor(motor.Name)
		local socket = Instance.new("BallSocketConstraint")
		socket.Name = "Level2SlideSocket_" .. motor.Name
		socket.Attachment0 = attachment0
		socket.Attachment1 = attachment1
		socket.LimitsEnabled = true
		socket.UpperAngle = upper
		socket.TwistLimitsEnabled = true
		socket.TwistLowerAngle = twistLower
		socket.TwistUpperAngle = twistUpper
		socket.MaxFrictionTorque = 500 * Workspace.Gravity / 196.2
		socket.Enabled = true
		socket:SetAttribute("Level2SlideMotorName", motor.Name)
		socket:SetAttribute("Level2SlideLegacySocket", true)
		socket.Parent = folder

		local noCollision = Instance.new("NoCollisionConstraint")
		noCollision.Name = "Level2SlideNoCollision_" .. motor.Name
		noCollision.Part0 = part0
		noCollision.Part1 = part1
		noCollision.Parent = folder
	end

	local function addExtraNoCollision(name, partName0, partName1)
		if folder:FindFirstChild(name) then return end
		local part0 = character:FindFirstChild(partName0)
		local part1 = character:FindFirstChild(partName1)
		if not (part0 and part1 and part0:IsA("BasePart") and part1:IsA("BasePart")) then
			return
		end
		local constraint = Instance.new("NoCollisionConstraint")
		constraint.Name = name
		constraint.Part0 = part0
		constraint.Part1 = part1
		constraint.Parent = folder
	end
	addExtraNoCollision("Level2SlideNoCollision_Legs", "Left Leg", "Right Leg")
	addExtraNoCollision("Level2SlideNoCollision_HeadLeftArm", "Head", "Left Arm")
	addExtraNoCollision("Level2SlideNoCollision_HeadRightArm", "Head", "Right Arm")
end

local function matchingLegacySocket(character, motor)
	for _, descendant in ipairs(character:GetDescendants()) do
		if descendant:IsA("BallSocketConstraint")
			and descendant.Enabled
			and descendant:GetAttribute("Level2SlideLegacySocket") == true
			and descendant:GetAttribute("Level2SlideMotorName") == motor.Name then
			return descendant
		end
	end
	return nil
end

local function floorUnderPlayer(player, character, humanoid, root)
	local world = Workspace:FindFirstChild("Level 2 Generated World")
	if not world then return nil end
	local exclusions = {character}
	for _, otherPlayer in ipairs(Players:GetPlayers()) do
		if otherPlayer ~= player and otherPlayer.Character then
			table.insert(exclusions, otherPlayer.Character)
		end
	end
	local params = RaycastParams.new()
	params.FilterType = Enum.RaycastFilterType.Exclude
	params.FilterDescendantsInstances = exclusions
	params.IgnoreWater = true
	params.RespectCanCollide = true
	local distance = humanoid.HipHeight + root.Size.Y * .5 + 6
	local result = Workspace:Raycast(
		root.Position + Vector3.yAxis * .5,
		Vector3.new(0, -distance, 0), params)
	local floor = result and result.Instance
	if not floor or not floor:IsDescendantOf(world)
		or floor:GetAttribute("Level2_SlideFloor") ~= true then
		return nil
	end
	local direction = floor:GetAttribute("Level2_SlideDirection")
	if typeof(direction) ~= "Vector3" or direction.Magnitude < .5 then
		direction = floor.CFrame.LookVector
	end
	direction = direction.Unit
	-- Metadata may select stronger exit-tube handling, but it must not allow a
	-- shallow floor to start a ragdoll that the client correctly rejected.
	if -direction.Y < .18 then return nil end
	return floor
end

local function restoreAliveSession(player, session)
	if sessions[player] ~= session then return end
	sessions[player] = nil
	local character = session.Character
	local humanoid = session.Humanoid
	if player.Character ~= character or humanoid.Health <= 0
		or not character.Parent then
		return
	end

	for _, snapshot in ipairs(session.Joints) do
		if snapshot.Joint.Parent then
			snapshot.Joint.Enabled = snapshot.Enabled
		end
	end
	for _, snapshot in ipairs(session.Motors) do
		if snapshot.Motor.Parent then
			snapshot.Motor.Enabled = snapshot.Enabled
		end
	end
	if session.RequiresNeck ~= nil then
		humanoid.RequiresNeck = session.RequiresNeck
	end
	character:SetAttribute("Level2_RagdollServerActive", nil)
	local function restoreCollision()
		if player.Character ~= character or humanoid.Health <= 0
			or sessions[player] ~= nil
			or generations[player] ~= session.Generation then return end
		if session.Root.Parent then session.Root.CanCollide = session.RootCanCollide end
		if session.Head and session.Head.Parent then
			session.Head.CanCollide = session.HeadCanCollide
		end
		collisionBaselines[player] = nil
	end
	-- Leave the root box disabled through the first get-up frames. Restoring it
	-- while the limp body overlaps a floor can launch the player violently.
	if session.Root.Anchored then
		restoreCollision()
	else
		task.delay(.30, restoreCollision)
	end
end

local function dropDeadSession(player, session)
	if sessions[player] ~= session then return end
	sessions[player] = nil
	collisionBaselines[player] = nil
	-- Roblox's death rig uses the same released joints. Do not re-enable them or
	-- restore root/head collision after death; that creates a standing corpse
	-- race when BreakJointsOnDeath is false.
end

local function beginSession(player)
	if sessions[player] then return end
	if Workspace:GetAttribute("SelectedLevel") ~= 2
		or player:GetAttribute("InRound") ~= true
		or player:GetAttribute("Escaped") == true then
		return
	end
	local character = player.Character
	local humanoid = character and character:FindFirstChildOfClass("Humanoid")
	local root = character and character:FindFirstChild("HumanoidRootPart")
	if not (character and humanoid and root) or humanoid.Health <= 0
		or root.Anchored or not floorUnderPlayer(player, character, humanoid, root) then
		return
	end

	prepareLegacyRig(character)
	generations[player] = (generations[player] or 0) + 1
	local baseline = collisionBaselines[player]
	if not baseline or baseline.Character ~= character then
		baseline = {
			Character = character,
			RootCanCollide = root.CanCollide,
			Head = character:FindFirstChild("Head"),
		}
		baseline.HeadCanCollide = baseline.Head and baseline.Head.CanCollide or false
		collisionBaselines[player] = baseline
	end
	local session = {
		Character = character,
		Humanoid = humanoid,
		Root = root,
		Head = baseline.Head,
		StartedAt = os.clock(),
		Generation = generations[player],
		Joints = {},
		Motors = {},
		RootCanCollide = baseline.RootCanCollide,
		HeadCanCollide = baseline.HeadCanCollide,
		RequiresNeck = humanoid.RequiresNeck,
	}
	sessions[player] = session

	local hasAnimationConstraints = character:FindFirstChildWhichIsA(
		"AnimationConstraint", true) ~= nil
	for _, descendant in ipairs(character:GetDescendants()) do
		if descendant:IsA("AnimationConstraint") then
			local attachment0, attachment1 = descendant.Attachment0, descendant.Attachment1
			local part0 = attachmentPart(attachment0)
			local part1 = attachmentPart(attachment1)
			if not isRootConnection(descendant.Name, part0, part1)
				and matchingSocket(character, descendant) then
				table.insert(session.Joints, {
					Joint = descendant,
					Enabled = descendant.Enabled,
				})
				descendant.Enabled = false
			end
		elseif not hasAnimationConstraints and isLegacyAnatomyMotor(descendant) then
			local part0, part1 = descendant.Part0, descendant.Part1
			if part0 and part1 and not isRootConnection(descendant.Name, part0, part1)
				and matchingLegacySocket(character, descendant) then
				table.insert(session.Motors, {
					Motor = descendant,
					Enabled = descendant.Enabled,
				})
			end
		end
	end
	if #session.Motors > 0 then
		humanoid.RequiresNeck = false
		for _, snapshot in ipairs(session.Motors) do
			snapshot.Motor.Enabled = false
		end
		local animator = humanoid:FindFirstChildOfClass("Animator")
		if animator then
			local motors = {}
			for _, snapshot in ipairs(session.Motors) do
				table.insert(motors, snapshot.Motor)
			end
			pcall(function() animator:ApplyJointVelocities(motors) end)
		end
	end

	root.CanCollide = false
	if session.Head then session.Head.CanCollide = true end
	character:SetAttribute("Level2_RagdollServerActive", true)
end

remote.OnServerEvent:Connect(function(player, action)
	if action == "Begin" then
		beginSession(player)
	elseif action == "End" then
		local session = sessions[player]
		if session then restoreAliveSession(player, session) end
	end
end)

local watchdogAccumulator = 0
RunService.Heartbeat:Connect(function(deltaTime)
	watchdogAccumulator += deltaTime
	if watchdogAccumulator < .2 then return end
	watchdogAccumulator = 0
	for player, session in pairs(sessions) do
		local humanoid = session.Humanoid
		local alive = humanoid.Parent and humanoid.Health > 0
		if not alive or player.Character ~= session.Character then
			dropDeadSession(player, session)
		elseif Workspace:GetAttribute("SelectedLevel") ~= 2
			or player:GetAttribute("InRound") ~= true
			or player:GetAttribute("Escaped") == true
			or session.Root.Anchored
			or os.clock() - session.StartedAt > MAX_RAGDOLL_SECONDS then
			restoreAliveSession(player, session)
		end
	end
end)

local function playerAdded(player)
	player.CharacterAdded:Connect(function(character)
		task.defer(prepareLegacyRig, character)
	end)
	if player.Character then task.defer(prepareLegacyRig, player.Character) end
end

Players.PlayerAdded:Connect(playerAdded)
for _, player in ipairs(Players:GetPlayers()) do playerAdded(player) end
Players.PlayerRemoving:Connect(function(player)
	sessions[player] = nil
	collisionBaselines[player] = nil
	generations[player] = nil
end)

-- LEVEL2_WATER_TEXTURES_IMAGEGEN_20260821
-- ImageGen-authored water-prop surface set. Appended here because this existing
-- server runtime survives Team Create and already follows Level 2 lifecycle.
do
	local WATER_TEXTURE_RULES = {
		{Prefix = "Level 2 Lounger Seat ", Texture = "rbxassetid://91296013464877", Role = "Lounger", Tile = 3, Shine = .01},
		{Prefix = "Level 2 Lounger Back ", Texture = "rbxassetid://91296013464877", Role = "Lounger", Tile = 3, Shine = .01},
		{Prefix = "Level 2 Beach Ball ", Texture = "rbxassetid://123196786081916", Role = "BeachBall", Tile = 2.4, Shine = .08},
		{Prefix = "Level 2 Pool Noodle ", Texture = "rbxassetid://78838707014603", Role = "PoolNoodle", Tile = 2, Shine = .015},
		{Prefix = "Level 2 Pool Raft ", Texture = "rbxassetid://119929960740617", Role = "PoolRaft", Tile = 4, Shine = .06},
		{Prefix = "Level 2 Pool Float Ring ", Texture = "rbxassetid://115464842856867", Role = "FloatRing", Tile = 3, Shine = .07},
	}
	local WATER_TEXTURE_PREFIX = "Level2WaterTexture_"

	local function startsWith(value, prefix)
		return string.sub(value, 1, #prefix) == prefix
	end

	local function applyWaterTexture(instance)
		if not instance:IsA("BasePart") then return end
		for _, rule in ipairs(WATER_TEXTURE_RULES) do
			if startsWith(instance.Name, rule.Prefix) then
				for _, child in ipairs(instance:GetChildren()) do
					if child:IsA("Texture") and startsWith(child.Name, WATER_TEXTURE_PREFIX) then
						child:Destroy()
					end
				end
				instance.Material = Enum.Material.SmoothPlastic
				instance.Reflectance = rule.Shine
				for _, face in ipairs(Enum.NormalId:GetEnumItems()) do
					local texture = Instance.new("Texture")
					texture.Name = WATER_TEXTURE_PREFIX .. face.Name
					texture.Texture = rule.Texture
					texture.Face = face
					texture.StudsPerTileU = rule.Tile
					texture.StudsPerTileV = rule.Tile
					texture.Color3 = instance.Color
					texture.Transparency = 0
					texture.ZIndex = 1
					texture.Parent = instance
				end
				instance:SetAttribute("Level2_WaterPropTexture", rule.Texture)
				instance:SetAttribute("Level2_WaterPropTextureRole", rule.Role)
				instance:SetAttribute("Level2_WaterPropTextureSet", "ImageGen 2026-08-21")
				return
			end
		end
	end

	for _, instance in ipairs(Workspace:GetDescendants()) do
		applyWaterTexture(instance)
	end
	Workspace.DescendantAdded:Connect(function(instance)
		task.defer(applyWaterTexture, instance)
	end)
end

