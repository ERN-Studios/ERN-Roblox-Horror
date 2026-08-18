-- Level 2 Slide Controller
--
-- A steep flume releases the character's body joints and lets physics carry a
-- genuine ragdoll down the fiberglass. A modest downhill VectorForce keeps the
-- limp body moving through long bends; it does not lock velocity or preserve
-- an upright pose. The exit tube becomes one-way when its descent commits the
-- rider; its flat loading apron remains freely walkable.

local Players = game:GetService("Players")
local ReplicatedStorage = game:GetService("ReplicatedStorage")
local RunService = game:GetService("RunService")
local Workspace = game:GetService("Workspace")

local player = Players.LocalPlayer
local remotes = ReplicatedStorage:WaitForChild("Remotes")
local ragdollRemote = remotes:WaitForChild("Level2SlideRagdoll", 15)

local ENTER_SLOPE = .20
local RELEASE_SLOPE = .12
local SHALLOW_RELEASE_SECONDS = .24
local CONTACT_GRACE_SECONDS = .30
local DIRECTION_RESPONSE = 13
local OPEN_INITIAL_SPEED = 30
local EXIT_INITIAL_SPEED = 36
local OPEN_DRIVE_ACCELERATION = 46
local EXIT_DRIVE_ACCELERATION = 58
local OPEN_SOFT_MAX_SPEED = 88
local EXIT_SOFT_MAX_SPEED = 105
local OVERSPEED_RESPONSE = 5
local EXIT_RUNOUT_DECELERATION = 215
local EXIT_RUNOUT_RECOVERY_SPEED = 32
local COAST_GROUNDED_SECONDS = .15
local COAST_MIN_SECONDS = .35
local COAST_MAX_SECONDS = 2.5
local RECOVERY_LOCK_SECONDS = .30

local raycastParams = RaycastParams.new()
raycastParams.FilterType = Enum.RaycastFilterType.Exclude
raycastParams.IgnoreWater = true
raycastParams.RespectCanCollide = true

local activeSlide
local pendingRestore

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

local function isLegacyAnatomyMotor(motor)
	local normalized = string.lower(motor.Name):gsub("[%s_]", "")
	return motor:IsA("Motor6D") and LEGACY_ANATOMY[normalized] == true
end

local function levelIsActive()
	return Workspace:GetAttribute("SelectedLevel") == 2
		and player:GetAttribute("InRound") == true
		and player:GetAttribute("Escaped") ~= true
end

local function setWalkSpeed(slide, speed)
	if not slide or not slide.Humanoid.Parent then return end
	slide.WritingWalkSpeed = true
	slide.Humanoid.WalkSpeed = speed
	slide.WritingWalkSpeed = false
end

local function desiredWalkSpeed(slide)
	local desired = slide.Character:GetAttribute("Level2_DesiredWalkSpeed")
	if typeof(desired) ~= "number" or desired ~= desired
		or math.abs(desired) == math.huge then
		desired = slide.ResumeWalkSpeed
	end
	return math.max(0, desired)
end

local function clearPendingRestore()
	if not pendingRestore then return end
	for _, connection in ipairs(pendingRestore.Connections) do
		connection:Disconnect()
	end
	pendingRestore = nil
end

local function restoreMovementAndCollision(slide)
	if player.Character ~= slide.Character or slide.Humanoid.Health <= 0
		or not slide.Humanoid.Parent or not slide.Root.Parent then
		return
	end
	for _, snapshot in ipairs(slide.Collisions) do
		if snapshot.Part.Parent then snapshot.Part.CanCollide = snapshot.CanCollide end
	end
	slide.Humanoid.Jump = false
	setWalkSpeed(slide, desiredWalkSpeed(slide))
	slide.Character:SetAttribute("Level2_ForcedSliding", nil)
end

local function scheduleFinalRestore(slide)
	clearPendingRestore()
	local pending = {
		Slide = slide,
		StartedAt = os.clock(),
		Connections = {},
	}
	pendingRestore = pending

	local function cancel()
		if pendingRestore ~= pending then return end
		clearPendingRestore()
	end

	local function update()
		if pendingRestore ~= pending then return end
		if player.Character ~= slide.Character or slide.Humanoid.Health <= 0
			or not slide.Root.Parent then
			cancel()
			return
		end
		-- Cutscenes/dev flight may anchor the root. Keep the recovery pending
		-- until that same live character is released instead of leaving speed 0.
		if slide.Root.Anchored then return end
		setWalkSpeed(slide, 0)
		if os.clock() - pending.StartedAt >= RECOVERY_LOCK_SECONDS then
			restoreMovementAndCollision(slide)
			cancel()
		end
	end

	table.insert(pending.Connections, RunService.Heartbeat:Connect(update))
	table.insert(pending.Connections, slide.Humanoid.Died:Connect(cancel))
	table.insert(pending.Connections, player.CharacterRemoving:Connect(function(character)
		if character == slide.Character then cancel() end
	end))
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

local function mechanismMass(character)
	local total = 0
	for _, descendant in ipairs(character:GetDescendants()) do
		if descendant:IsA("BasePart") and not descendant.Massless then
			total += descendant:GetMass()
		end
	end
	return math.max(total, 1)
end

local function releaseBodyJoints(slide)
	local hasAnimationConstraints = slide.Character:FindFirstChildWhichIsA(
		"AnimationConstraint", true) ~= nil
	for _, descendant in ipairs(slide.Character:GetDescendants()) do
		if descendant:IsA("AnimationConstraint") then
			local attachment0, attachment1 = descendant.Attachment0, descendant.Attachment1
			local part0 = attachmentPart(attachment0)
			local part1 = attachmentPart(attachment1)
			if not isRootConnection(descendant.Name, part0, part1)
				and matchingSocket(slide.Character, descendant) then
				table.insert(slide.Joints, {
					Joint = descendant,
					Enabled = descendant.Enabled,
				})
				descendant.Enabled = false
			end
		end
	end
	if not hasAnimationConstraints then
		slide.RequiresNeck = slide.Humanoid.RequiresNeck
		slide.Humanoid.RequiresNeck = false
		for _, descendant in ipairs(slide.Character:GetDescendants()) do
			if isLegacyAnatomyMotor(descendant)
				and not isRootConnection(descendant.Name, descendant.Part0, descendant.Part1)
				and matchingLegacySocket(slide.Character, descendant) then
				table.insert(slide.Motors, {
					Motor = descendant,
					Enabled = descendant.Enabled,
				})
				descendant.Enabled = false
			end
		end
		local animator = slide.Humanoid:FindFirstChildOfClass("Animator")
		if animator and #slide.Motors > 0 then
			local motors = {}
			for _, snapshot in ipairs(slide.Motors) do
				table.insert(motors, snapshot.Motor)
			end
			pcall(function() animator:ApplyJointVelocities(motors) end)
		end
	end

	table.insert(slide.Collisions, {
		Part = slide.Root,
		CanCollide = slide.Root.CanCollide,
	})
	slide.Root.CanCollide = false
	local head = slide.Character:FindFirstChild("Head")
	if head and head:IsA("BasePart") then
		table.insert(slide.Collisions, {Part = head, CanCollide = head.CanCollide})
		head.CanCollide = true
	end
end

local function restoreBodyJoints(slide, supported)
	for _, snapshot in ipairs(slide.Joints) do
		if snapshot.Joint.Parent then snapshot.Joint.Enabled = snapshot.Enabled end
	end
	for _, snapshot in ipairs(slide.Motors) do
		if snapshot.Motor.Parent then snapshot.Motor.Enabled = snapshot.Enabled end
	end
	if slide.RequiresNeck ~= nil then
		slide.Humanoid.RequiresNeck = slide.RequiresNeck
	end
	slide.Root.AssemblyAngularVelocity = Vector3.zero
	slide.Humanoid.Jump = false
	slide.Humanoid:SetStateEnabled(
		Enum.HumanoidStateType.Jumping, slide.JumpingWasEnabled)
	slide.Humanoid:SetStateEnabled(
		Enum.HumanoidStateType.GettingUp, slide.GettingUpWasEnabled)
	slide.Humanoid.PlatformStand = slide.PlatformStandWasEnabled
	slide.Humanoid.AutoRotate = slide.AutoRotateWasEnabled
	if slide.Humanoid:GetState() == Enum.HumanoidStateType.Swimming then
		slide.Humanoid:ChangeState(Enum.HumanoidStateType.Swimming)
	elseif supported then
		slide.Humanoid:ChangeState(Enum.HumanoidStateType.GettingUp)
	else
		slide.Humanoid:ChangeState(Enum.HumanoidStateType.Freefall)
	end
end

local function destroyForce(slide)
	if slide.Actuator and slide.Actuator.Parent then slide.Actuator:Destroy() end
	if slide.Attachment and slide.Attachment.Parent then slide.Attachment:Destroy() end
	slide.Actuator = nil
	slide.Attachment = nil
end

local function finishSliding(restore, supported)
	local slide = activeSlide
	if not slide then return end
	activeSlide = nil
	for _, connection in ipairs(slide.Connections) do connection:Disconnect() end
	destroyForce(slide)

	if restore and player.Character == slide.Character
		and slide.Humanoid.Health > 0 and slide.Character.Parent then
		restoreBodyJoints(slide, supported)
		if ragdollRemote and ragdollRemote:IsA("RemoteEvent") then
			ragdollRemote:FireServer("End")
		end
		scheduleFinalRestore(slide)
	else
		-- Death owns the released joints. Only remove this controller's force and
		-- marker; re-enabling joints here would make an AJU corpse stand up.
		if slide.Character.Parent then
			slide.Character:SetAttribute("Level2_ForcedSliding", nil)
		end
	end
end

local function startCoasting(slide)
	if slide.Phase == "COASTING" then return end
	destroyForce(slide)
	slide.Phase = "COASTING"
	slide.CoastStarted = os.clock()
	slide.GroundedSince = nil
end

local function startRunoutBraking(slide)
	if slide.Phase == "RUNOUT_BRAKING" then return end
	slide.Phase = "RUNOUT_BRAKING"
	slide.RunoutStarted = os.clock()
	slide.GroundedSince = nil
	slide.ShallowSince = nil
end

local function startSliding(character, humanoid, root, direction, oneWay)
	-- Complete a prior get-up before taking a fresh collision/joint snapshot.
	if pendingRestore then
		local prior = pendingRestore.Slide
		if prior and prior.Character == character and humanoid.Health > 0
			and not root.Anchored then
			restoreMovementAndCollision(prior)
		end
		clearPendingRestore()
	end
	if activeSlide then finishSliding(true, false) end

	local resumeWalkSpeed = character:GetAttribute("Level2_DesiredWalkSpeed")
	if typeof(resumeWalkSpeed) ~= "number" or resumeWalkSpeed ~= resumeWalkSpeed
		or math.abs(resumeWalkSpeed) == math.huge then
		resumeWalkSpeed = humanoid.WalkSpeed
	end
	local slide = {
		Character = character,
		Humanoid = humanoid,
		Root = root,
		Direction = direction,
		OneWay = oneWay,
		Phase = "ACTIVE",
		MechanismMass = mechanismMass(character),
		ResumeWalkSpeed = resumeWalkSpeed,
		JumpingWasEnabled = humanoid:GetStateEnabled(Enum.HumanoidStateType.Jumping),
		GettingUpWasEnabled = humanoid:GetStateEnabled(Enum.HumanoidStateType.GettingUp),
		PlatformStandWasEnabled = humanoid.PlatformStand,
		AutoRotateWasEnabled = humanoid.AutoRotate,
		LastContact = os.clock(),
		LastPosition = root.Position,
		ShallowSince = nil,
		WritingWalkSpeed = false,
		Connections = {},
		Joints = {},
		Motors = {},
		Collisions = {},
	}
	activeSlide = slide
	character:SetAttribute("Level2_ForcedSliding", true)
	humanoid.Jump = false
	humanoid:SetStateEnabled(Enum.HumanoidStateType.Jumping, false)
	humanoid:SetStateEnabled(Enum.HumanoidStateType.GettingUp, false)
	humanoid.AutoRotate = false
	setWalkSpeed(slide, 0)

	-- Commit hard enough to feel like a water-park drop, then release the body.
	-- Applying the impulse before joints separate distributes the launch across
	-- the complete character mass instead of only the root/torso subassembly.
	local initialSpeed = oneWay and EXIT_INITIAL_SPEED or OPEN_INITIAL_SPEED
	local incomingAlong = root.AssemblyLinearVelocity:Dot(direction)
	if incomingAlong < initialSpeed then
		root:ApplyImpulse(direction * slide.MechanismMass * (initialSpeed - incomingAlong))
	end
	local tumbleAxis = direction:Cross(Vector3.yAxis)
	if tumbleAxis.Magnitude < .1 then tumbleAxis = Vector3.xAxis end
	root.AssemblyAngularVelocity += tumbleAxis.Unit * 3.8 + direction * 1.25

	releaseBodyJoints(slide)
	humanoid.PlatformStand = true
	humanoid:ChangeState(Enum.HumanoidStateType.Physics)

	local attachment = Instance.new("Attachment")
	attachment.Name = "Level 2 Ragdoll Slide Force Attachment"
	attachment.Parent = root
	local actuator = Instance.new("VectorForce")
	actuator.Name = "Level 2 Ragdoll Downhill Force"
	actuator.Attachment0 = attachment
	actuator.RelativeTo = Enum.ActuatorRelativeTo.World
	actuator.ApplyAtCenterOfMass = true
	actuator.Force = direction * slide.MechanismMass
		* (oneWay and EXIT_DRIVE_ACCELERATION or OPEN_DRIVE_ACCELERATION)
	actuator.Parent = root
	slide.Attachment = attachment
	slide.Actuator = actuator

	if ragdollRemote and ragdollRemote:IsA("RemoteEvent") then
		ragdollRemote:FireServer("Begin")
	end
	table.insert(slide.Connections,
		humanoid:GetPropertyChangedSignal("WalkSpeed"):Connect(function()
			if activeSlide ~= slide or slide.WritingWalkSpeed then return end
			if humanoid.WalkSpeed > 0 then slide.ResumeWalkSpeed = humanoid.WalkSpeed end
			setWalkSpeed(slide, 0)
		end))
	table.insert(slide.Connections, humanoid.Died:Connect(function()
		if activeSlide == slide then finishSliding(false, false) end
	end))
end

local function exclusionsFor(character)
	local exclusions = {character}
	for _, otherPlayer in ipairs(Players:GetPlayers()) do
		local otherCharacter = otherPlayer.Character
		if otherCharacter and otherCharacter ~= character then
			table.insert(exclusions, otherCharacter)
		end
	end
	return exclusions
end

local function slideFloorUnder(character, humanoid, root)
	raycastParams.FilterDescendantsInstances = exclusionsFor(character)
	local origin = root.Position + Vector3.yAxis * .5
	local distance = humanoid.HipHeight + root.Size.Y * .5 + 4
	local result = Workspace:Raycast(origin, Vector3.new(0, -distance, 0), raycastParams)
	local floor = result and result.Instance
	if not floor or floor:GetAttribute("Level2_SlideFloor") ~= true then return nil end
	local direction = floor:GetAttribute("Level2_SlideDirection")
	if typeof(direction) ~= "Vector3" or direction.Magnitude < .5 then
		direction = floor.CFrame.LookVector
	end
	return direction.Unit, floor:GetAttribute("Level2_OneWayExit") == true, floor
end

local function supportedUnder(character, humanoid, root)
	raycastParams.FilterDescendantsInstances = exclusionsFor(character)
	local distance = humanoid.HipHeight + root.Size.Y * .5 + 5
	local result = Workspace:Raycast(
		root.Position + Vector3.yAxis * .5,
		Vector3.new(0, -distance, 0), raycastParams)
	return result ~= nil and result.Normal.Y >= .60
end

RunService.PreSimulation:Connect(function(deltaTime)
	local character = player.Character
	local humanoid = character and character:FindFirstChildOfClass("Humanoid")
	local root = character and character:FindFirstChild("HumanoidRootPart")
	if not levelIsActive() or not character or not humanoid or not root
		or humanoid.Health <= 0 then
		finishSliding(humanoid ~= nil and humanoid.Health > 0, false)
		return
	end
	if root.Anchored then
		finishSliding(true, false)
		return
	end
	if activeSlide and activeSlide.Character ~= character then finishSliding(false, false) end
	if activeSlide and (root.Position - activeSlide.LastPosition).Magnitude > 20 then
		finishSliding(true, false)
		return
	end

	local direction, oneWay = slideFloorUnder(character, humanoid, root)
	local downhill = direction and math.max(0, -direction.Y) or 0
	local now = os.clock()
	-- Exit-route metadata changes force and reverse protection, but never lets a
	-- flat or shallow section bypass the same steepness gate as every other slide.
	if not activeSlide and direction and downhill >= ENTER_SLOPE then
		startSliding(character, humanoid, root, direction, oneWay)
	end

	local slide = activeSlide
	if not slide then return end
	slide.LastPosition = root.Position
	slide.Humanoid.Jump = false
	slide.Humanoid:Move(Vector3.zero, false)
	slide.Humanoid.AutoRotate = false
	slide.Humanoid.PlatformStand = true
	slide.Humanoid:ChangeState(Enum.HumanoidStateType.Physics)
	setWalkSpeed(slide, 0)

	if slide.Phase == "ACTIVE" then
		if direction then
			slide.LastContact = now
			slide.OneWay = slide.OneWay or oneWay
			if downhill < RELEASE_SLOPE then
				if slide.OneWay then
					-- The exit's shallow runout is too short to stand a full-speed
					-- ragdoll up safely. Brake it first, then recover in the catch room.
					startRunoutBraking(slide)
				else
					slide.ShallowSince = slide.ShallowSince or now
					if now - slide.ShallowSince >= SHALLOW_RELEASE_SECONDS then
						startCoasting(slide)
					end
				end
			else
				slide.ShallowSince = nil
			end
			local alpha = 1 - math.exp(-DIRECTION_RESPONSE * deltaTime)
			local blended = slide.Direction:Lerp(direction, alpha)
			if blended.Magnitude > .1 then slide.Direction = blended.Unit end
		elseif now - slide.LastContact > CONTACT_GRACE_SECONDS then
			startCoasting(slide)
		end

		if slide.Phase == "ACTIVE" and slide.Actuator then
			local along = root.AssemblyLinearVelocity:Dot(slide.Direction)
			local drive = slide.OneWay and EXIT_DRIVE_ACCELERATION
				or OPEN_DRIVE_ACCELERATION
			local softMax = slide.OneWay and EXIT_SOFT_MAX_SPEED
				or OPEN_SOFT_MAX_SPEED
			local acceleration = drive
			if along > softMax then
				acceleration = math.max(-Workspace.Gravity,
					drive - (along - softMax) * OVERSPEED_RESPONSE)
			end
			slide.Actuator.Force = slide.Direction
				* slide.MechanismMass * acceleration
		end
	end

	if slide.Phase == "RUNOUT_BRAKING" then
		if direction then
			slide.LastContact = now
			local alpha = 1 - math.exp(-DIRECTION_RESPONSE * deltaTime)
			local blended = slide.Direction:Lerp(direction, alpha)
			if blended.Magnitude > .1 then slide.Direction = blended.Unit end
		end

		local horizontal = Vector3.new(slide.Direction.X, 0, slide.Direction.Z)
		if horizontal.Magnitude > .1 then horizontal = horizontal.Unit end
		local along = root.AssemblyLinearVelocity:Dot(horizontal)
		local swimming = humanoid:GetState() == Enum.HumanoidStateType.Swimming
		local grounded = swimming or supportedUnder(character, humanoid, root)
		if grounded then
			slide.GroundedSince = slide.GroundedSince or now
		else
			slide.GroundedSince = nil
		end

		if slide.Actuator then
			if along > EXIT_RUNOUT_RECOVERY_SPEED then
				slide.Actuator.Force = -horizontal * slide.MechanismMass
					* EXIT_RUNOUT_DECELERATION
			else
				slide.Actuator.Force = Vector3.zero
			end
		end

		local runoutAge = now - slide.RunoutStarted
		local stable = grounded and slide.GroundedSince
			and now - slide.GroundedSince >= COAST_GROUNDED_SECONDS
			and along <= EXIT_RUNOUT_RECOVERY_SPEED
			and root.AssemblyLinearVelocity.Magnitude <= 40
		if stable then
			finishSliding(true, true)
		elseif runoutAge >= COAST_MAX_SECONDS then
			startCoasting(slide)
		end
	end

	if slide.Phase == "COASTING" then
		local swimming = humanoid:GetState() == Enum.HumanoidStateType.Swimming
		local grounded = swimming or supportedUnder(character, humanoid, root)
		if grounded then
			slide.GroundedSince = slide.GroundedSince or now
		else
			slide.GroundedSince = nil
		end
		local coastAge = now - slide.CoastStarted
		local stable = slide.GroundedSince
			and now - slide.GroundedSince >= COAST_GROUNDED_SECONDS
			and coastAge >= COAST_MIN_SECONDS
			and (root.AssemblyLinearVelocity.Magnitude <= 32 or coastAge >= .85)
		if stable then
			finishSliding(true, true)
		elseif coastAge >= COAST_MAX_SECONDS then
			finishSliding(true, grounded)
		end
	end
end)

player.CharacterRemoving:Connect(function(character)
	if activeSlide and activeSlide.Character == character then
		finishSliding(false, false)
	end
	clearPendingRestore()
end)
