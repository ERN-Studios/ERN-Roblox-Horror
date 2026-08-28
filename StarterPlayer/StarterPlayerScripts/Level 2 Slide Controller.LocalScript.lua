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
local level3SlideStream = remotes:WaitForChild("Level3SlideStream", 15)

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

-- GameManager keeps a Level 2 continuer anchored and covered until this client
-- can see real Level 3 bore collision. RequestStreamAroundAsync completion by
-- itself is not treated as readiness; a nearby tagged BasePart must exist too.
if level3SlideStream and level3SlideStream:IsA("RemoteEvent") then
	level3SlideStream.OnClientEvent:Connect(function(action, token, position, timeout)
		if action ~= "request" or type(token) ~= "string"
			or typeof(position) ~= "Vector3" then return end
		task.spawn(function()
			local budget = math.clamp(tonumber(timeout) or 6, 1, 12)
			pcall(function() player:RequestStreamAroundAsync(position, budget) end)
			local ready = false
			local deadline = os.clock() + budget
			repeat
				local world = Workspace:FindFirstChild("Level 3 Generated World")
				local tube = world and world:FindFirstChild("Level 2 Exit Slide Continuation", true)
				if tube and tube:GetAttribute("Level3_Level2ExitTube") == true then
					for _, object in ipairs(tube:GetDescendants()) do
						if object:IsA("BasePart") and object.CanCollide
							and object:GetAttribute("Level3_ProgressionSlide") == true
							and (object.Position - position).Magnitude <= 28 then
							ready = true
							break
						end
					end
				end
				if not ready then task.wait(.05) end
			until ready or os.clock() >= deadline
			level3SlideStream:FireServer("ack", token, ready)
		end)
	end)
end

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

-- LEVEL2_EXIT_TRANSITION_20260828
-- Escaping normally ends the ride. The exit transition is the one case where it
-- must not: after crossing the completion sensor the rider is Escaped but still
-- physically sliding down the tube for the whole 15-second decision window, so
-- the slide stays live until the server clears Level2_ExitTransition.
local function levelIsActive()
	local selectedLevel = Workspace:GetAttribute("SelectedLevel")
	if player:GetAttribute("InRound") ~= true then return false end
	if selectedLevel == 2 then
		return player:GetAttribute("Escaped") ~= true
			or player:GetAttribute("Level2_ExitTransition") == true
	end
	-- Level 3's arrival bore is the physical continuation of this same slide.
	-- Reuse the real joint-releasing controller instead of making the freshly
	-- loaded character a rigid PlatformStand mannequin at the server seam.
	return selectedLevel == 3 and player:GetAttribute("Escaped") ~= true
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

	-- Avatar packages are not consistent about limb collision. The current
	-- R15 body, for example, arrives with every arm, leg and torso collidable;
	-- releasing those joints inside a 16-stud bore makes the rig brace across
	-- the tube and absorb a 105 stud/s launch. Snapshot the complete body and
	-- use one rounded contact (the head) while sliding. This keeps the tumble
	-- physical without letting custom player models wedge themselves in place.
	for _, descendant in ipairs(slide.Character:GetDescendants()) do
		if descendant:IsA("BasePart") then
			table.insert(slide.Collisions, {
				Part = descendant,
				CanCollide = descendant.CanCollide,
			})
			descendant.CanCollide = false
		end
	end
	local head = slide.Character:FindFirstChild("Head")
	if head and head:IsA("BasePart") then
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

local function exitTransitionOwnsSlide(slide)
	return slide and slide.OneWay
		and Workspace:GetAttribute("SelectedLevel") == 2
		and player:GetAttribute("InRound") == true
		and player:GetAttribute("Level2_ExitTransition") == true
end

local function installDriveForce(slide)
	destroyForce(slide)
	if not slide.Root.Parent then return false end
	local attachment = Instance.new("Attachment")
	attachment.Name = "Level 2 Ragdoll Slide Force Attachment"
	attachment.Parent = slide.Root
	local actuator = Instance.new("VectorForce")
	actuator.Name = "Level 2 Ragdoll Downhill Force"
	actuator.Attachment0 = attachment
	actuator.RelativeTo = Enum.ActuatorRelativeTo.World
	actuator.ApplyAtCenterOfMass = true
	actuator.Force = slide.Direction * slide.MechanismMass
		* (slide.OneWay and EXIT_DRIVE_ACCELERATION or OPEN_DRIVE_ACCELERATION)
	actuator.Parent = slide.Root
	slide.Attachment = attachment
	slide.Actuator = actuator
	return true
end

-- A server recovery is an authoritative correction back onto the endless
-- helix. The client may already have entered COASTING and destroyed its force
-- during the server's off-path grace, so rebasing LastPosition alone is not
-- enough: rebuild the actuator and re-arm every contact timer as one operation.
local function resumeExitDrive(slide, direction)
	if not exitTransitionOwnsSlide(slide) then return false end
	if typeof(direction) == "Vector3" and direction.Magnitude > .1 then
		slide.Direction = direction.Unit
	end
	slide.Phase = "ACTIVE"
	slide.LastContact = os.clock()
	slide.ShallowSince = nil
	slide.GroundedSince = nil
	slide.CoastStarted = nil
	slide.RunoutStarted = nil
	return installDriveForce(slide)
end

local function finishSliding(restore, supported)
	local slide = activeSlide
	if not slide then return end
	-- During the completed Level 2 ride the server owns the lifecycle. Lost
	-- floor contact, a temporary anchor, or a forged/local End must not stand the
	-- rider up inside the continuation tube. Return Lobby/level transfer clears
	-- the transition first, after which the ordinary cleanup path is available.
	if restore and exitTransitionOwnsSlide(slide) then return end
	activeSlide = nil
	if slide.Character and slide.Character.Parent then
		slide.Character:SetAttribute("Level2_ExitRecycleCount", nil)
	end
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

	installDriveForce(slide)

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
	if not floor then return nil end
	if floor:GetAttribute("Level3_ProgressionSlide") == true then
		-- Continuation panels use local X from mouth to rear; travel is the
		-- inverse, downhill toward the mall.
		return -floor.CFrame.RightVector, true, floor
	end
	if floor:GetAttribute("Level2_SlideFloor") ~= true then return nil end
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

-- LEVEL2_EXIT_RECYCLE_20260828
-- The exit transition has to last an arbitrary multiplayer wait: a first rider
-- can be circling for minutes while the rest of the party finishes Level 2. A
-- tube long enough for that in static geometry would be tens of thousands of
-- parts, so instead the rider RECYCLES around three turns of helix.
--
-- The lift is exact, not a blend. The helix is uniform, so the bore one full
-- turn up is the same shape at the same path tangent, and the rider's velocity
-- carries over untouched. The tube is a closed sleeve, so there is nothing
-- outside it to parallax against and give the jump away.
--
-- This runs on the CLIENT because the client owns the character's physics; a
-- server PivotTo would be fought by client prediction and would look like a
-- rubber-band. It also has to update the slide's own LastPosition, or the
-- teleport guard immediately below would read the lift as an external teleport
-- and end the ride.
local recycleModel = nil
local function exitRecycleModel()
	if recycleModel and recycleModel.Parent then return recycleModel end
	recycleModel = nil
	local world = Workspace:FindFirstChild("Level 2 Generated World")
	if not world then return nil end
	for _, object in ipairs(world:GetDescendants()) do
		if object:GetAttribute("Level2_RecycleActive") == true then
			recycleModel = object
			break
		end
	end
	return recycleModel
end

local function applyExitRecycle(slide, character, root)
	if not slide or not slide.OneWay then return false end
	if player:GetAttribute("Level2_ExitTransition") ~= true then return false end
	local model = exitRecycleModel()
	if not model then return false end
	local triggerY = model:GetAttribute("Level2_RecycleTriggerY")
	local deltaY = model:GetAttribute("Level2_RecycleDeltaY")
	if type(triggerY) ~= "number" or type(deltaY) ~= "number" or deltaY <= 0 then
		return false
	end
	if root.Position.Y > triggerY then return false end
	-- Only lift a rider who is actually inside the drum wall. Someone who has
	-- fallen down the middle must be recovered by the server, not looped.
	local centerX = model:GetAttribute("Level2_HelixCenterX")
	local centerZ = model:GetAttribute("Level2_HelixCenterZ")
	local helixRadius = model:GetAttribute("Level2_HelixRadius")
	local bore = model:GetAttribute("Level2_FlumeBoreRadius") or 8
	if type(centerX) == "number" and type(centerZ) == "number" and type(helixRadius) == "number" then
		local offset = Vector2.new(root.Position.X - centerX, root.Position.Z - centerZ)
		if math.abs(offset.Magnitude - helixRadius) > bore + 4 then return false end
	end
	local lift = Vector3.new(0, deltaY, 0)
	local velocity = root.AssemblyLinearVelocity
	local spin = root.AssemblyAngularVelocity
	character:PivotTo(character:GetPivot() + lift)
	root.AssemblyLinearVelocity = velocity
	root.AssemblyAngularVelocity = spin
	-- Keep the guard below consistent with the lift we just performed.
	slide.LastPosition = root.Position
	slide.RecycleCount = (slide.RecycleCount or 0) + 1
	character:SetAttribute("Level2_ExitRecycleCount", slide.RecycleCount)
	return true
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
		if activeSlide and exitTransitionOwnsSlide(activeSlide) then
			activeSlide.LastPosition = root.Position
			return
		end
		finishSliding(true, false)
		return
	end
	if activeSlide and activeSlide.Character ~= character then finishSliding(false, false) end
	if activeSlide then applyExitRecycle(activeSlide, character, root) end
	if activeSlide and (root.Position - activeSlide.LastPosition).Magnitude > 20 then
		if activeSlide.OneWay
			and player:GetAttribute("Level2_ExitTransition") == true then
			-- The server recovery backstop may put an escaped rider back on the
			-- authored helix. Treat that authoritative correction exactly like the
			-- client recycle: keep the ragdoll session and rebase the teleport guard.
			-- Return Lobby clears the transition first, so real route changes still
			-- finish and send End normally.
			activeSlide.LastPosition = root.Position
			resumeExitDrive(activeSlide)
		else
			finishSliding(true, false)
			return
		end
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
	-- The authoritative transition can outlive a short loss of contact. If this
	-- client coasted before the server correction replicated, make the state
	-- self-healing even when the correction was shorter than the teleport guard.
	if exitTransitionOwnsSlide(slide)
		and (slide.Phase ~= "ACTIVE" or not slide.Actuator) then
		resumeExitDrive(slide, direction)
	end
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
				if exitTransitionOwnsSlide(slide) then
					-- Completion has committed the endless descent. A shallow or
					-- delayed contact sample is replication jitter, not a runout.
					slide.LastContact = now
				elseif slide.OneWay then
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
			if exitTransitionOwnsSlide(slide) then
				-- Keep driving until the server recovery watchdog places the rider
				-- back on the authored helix; do not destroy the force meanwhile.
				slide.LastContact = now
			else
				startCoasting(slide)
			end
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
