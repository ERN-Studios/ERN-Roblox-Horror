-- EntityKill
-- Server-authoritative cinematic kill. The hazmat entity grabs the victim,
-- performs the Blender finger-grab / ground-pin animation, then death and sound
-- land on the knockout punch. The old image scare remains in JumpscareUI.

local Players = game:GetService("Players")
local RS = game:GetService("ReplicatedStorage")
local TweenService = game:GetService("TweenService")

local remote = RS:WaitForChild("Remotes"):WaitForChild("Jumpscare")
local entity = workspace:WaitForChild("Entity")
local entityHumanoid = entity:WaitForChild("Humanoid")
local entityRoot = entity:WaitForChild("HumanoidRootPart")

local KILL_DURATION = 5.0
local DEATH_AT = 124 / 30 -- PUNCH marker in ENT_KILL_GroundPinPunch_IP_v002
local CAPTURE_DISTANCE = 3.7

local playerDebounce = {}
local sequenceBusy = false

local function findPlayer(hit)
	local node = hit
	while node and node ~= workspace do
		if node:IsA("Model") then
			local player = Players:GetPlayerFromCharacter(node)
			if player then return player, node end
		end
		node = node.Parent
	end
	return nil, nil
end

local function runKill(player, char)
	local hum = char and char:FindFirstChildOfClass("Humanoid")
	local playerRoot = char and char:FindFirstChild("HumanoidRootPart")
	if not (hum and playerRoot and hum.Health > 0) then
		sequenceBusy = false
		return
	end

	sequenceBusy = true
	playerDebounce[player] = os.clock()
	workspace:SetAttribute("EntityKillActive", true)
	workspace:SetAttribute("EntityIsLunging", false)

	local saved = {
		entityAnchored = entityRoot.Anchored,
		entityWalkSpeed = entityHumanoid.WalkSpeed,
		playerAnchored = playerRoot.Anchored,
		walkSpeed = hum.WalkSpeed,
		jumpPower = hum.JumpPower,
		autoRotate = hum.AutoRotate,
		breakJoints = hum.BreakJointsOnDeath,
		platformStand = hum.PlatformStand,
	}

	entityRoot.AssemblyLinearVelocity = Vector3.zero
	entityRoot.AssemblyAngularVelocity = Vector3.zero
	entityHumanoid.WalkSpeed = 0
	entityRoot.Anchored = true

	-- Face the caught player, then pull them to the exact first-person staging
	-- mark. The player faces back toward the visor and cannot rotate away.
	local entityPos = entityRoot.Position
	local targetFlat = Vector3.new(playerRoot.Position.X, entityPos.Y, playerRoot.Position.Z)
	if (targetFlat - entityPos).Magnitude > 0.01 then
		entity:PivotTo(CFrame.lookAt(entity:GetPivot().Position, targetFlat))
	end
	local killBaseCFrame = entityRoot.CFrame
	entityPos = entityRoot.Position
	local capturePos = entityPos + entityRoot.CFrame.LookVector * CAPTURE_DISTANCE
	capturePos = Vector3.new(capturePos.X, playerRoot.Position.Y, capturePos.Z)
	playerRoot.CFrame = CFrame.lookAt(capturePos,
		Vector3.new(entityPos.X, capturePos.Y, entityPos.Z))
	playerRoot.AssemblyLinearVelocity = Vector3.zero
	playerRoot.AssemblyAngularVelocity = Vector3.zero
	playerRoot.Anchored = true
	hum.WalkSpeed = 0
	hum.JumpPower = 0
	hum.AutoRotate = false
		hum.PlatformStand = false
	hum.BreakJointsOnDeath = false

	remote:FireClient(player, "capture", entity, KILL_DURATION, DEATH_AT)
	local playKill = entity:FindFirstChild("PlayKill")
	if playKill and playKill:IsA("BindableEvent") then playKill:Fire() end

	-- The authored Bone motion bends the torso, but the imported Hips/root has no
	-- downward translation. Lower and advance the anchored rig during the pin so
	-- its weight is visibly over the victim instead of standing upright nearby.
	task.delay(1.05, function()
		if not (entityRoot.Parent and workspace:GetAttribute("EntityKillActive")) then return end
		local crouchCF = killBaseCFrame
			+ killBaseCFrame.LookVector * 0.25
			- Vector3.new(0, 1.45, 0)
		TweenService:Create(entityRoot,
			TweenInfo.new(0.68, Enum.EasingStyle.Quart, Enum.EasingDirection.Out),
			{ CFrame = crouchCF }):Play()
	end)

	-- Match the victim to the authored beats: hands close, the entity pulls the
	-- player inward, then lays them flat directly beneath its grounded pin.
	task.spawn(function()
		task.wait(0.72)
		if not (playerRoot.Parent and hum.Health > 0) then return end
		local closePos = entityRoot.Position + entityRoot.CFrame.LookVector * 2.45
		closePos = Vector3.new(closePos.X, playerRoot.Position.Y, closePos.Z)
		local closeCF = CFrame.lookAt(closePos,
			Vector3.new(entityRoot.Position.X, closePos.Y, entityRoot.Position.Z))
		local pull = TweenService:Create(playerRoot,
			TweenInfo.new(0.38, Enum.EasingStyle.Quad, Enum.EasingDirection.In),
			{ CFrame = closeCF })
		pull:Play(); pull.Completed:Wait()

		task.wait(0.38)
		if not (playerRoot.Parent and hum.Health > 0) then return end
		local params = RaycastParams.new()
		params.FilterType = Enum.RaycastFilterType.Exclude
		local floorFilter = { entity, char }
		for _, name in ipairs({ "Decor", "PuzzleItems" }) do
			local instance = workspace:FindFirstChild(name)
			if instance then table.insert(floorFilter, instance) end
		end
		params.FilterDescendantsInstances = floorFilter
		local pinXZ = entityRoot.Position + entityRoot.CFrame.LookVector * 1.35
		-- Resolve the floor from directly beneath the grounded Entity, then only
		-- accept a pin-position sample near that same plane. The old ray began eight
		-- studs above the victim and could select a prop/ceiling surface, which sent
		-- the anchored character and its first-person camera onto the maze roof.
		local entityFloorHit = workspace:Raycast(
			entityRoot.Position + Vector3.new(0, 0.5, 0), Vector3.new(0, -12, 0), params)
		local fallbackFloorY = entityRoot.Position.Y
			- math.max(entityHumanoid.HipHeight + entityRoot.Size.Y * 0.5, 2.5)
		local floorY = entityFloorHit and entityFloorHit.Normal.Y > 0.7
			and entityFloorHit.Position.Y or fallbackFloorY
		local pinFloorHit = workspace:Raycast(
			Vector3.new(pinXZ.X, floorY + 2.5, pinXZ.Z), Vector3.new(0, -5, 0), params)
		if pinFloorHit and pinFloorHit.Normal.Y > 0.7
			and math.abs(pinFloorHit.Position.Y - floorY) <= 0.75 then
			floorY = pinFloorHit.Position.Y
		end
		local sidewaysRootClearance = playerRoot.Size.Z * 0.5 + 0.1
		local groundPos = Vector3.new(pinXZ.X, floorY + sidewaysRootClearance, pinXZ.Z)
		local faceEntity = CFrame.lookAt(groundPos,
			Vector3.new(entityRoot.Position.X, groundPos.Y, entityRoot.Position.Z))
		local groundCF = faceEntity * CFrame.Angles(math.rad(90), 0, 0)
		hum.PlatformStand = true
		playerRoot.AssemblyLinearVelocity = Vector3.zero
		playerRoot.AssemblyAngularVelocity = Vector3.zero
		local takedown = TweenService:Create(playerRoot,
			TweenInfo.new(0.72, Enum.EasingStyle.Quart, Enum.EasingDirection.InOut),
			{ CFrame = groundCF })
		takedown:Play()
	end)

	task.wait(DEATH_AT)
	if hum.Parent and hum.Health > 0 then
		-- Sound and health land together on the authored fist impact.
		remote:FireClient(player, "death")
		hum.Health = 0
	end

	task.wait(math.max(0, KILL_DURATION - DEATH_AT))
	if entityRoot.Parent then
		entityRoot.CFrame = killBaseCFrame
		entityRoot.Anchored = saved.entityAnchored
		entityHumanoid.WalkSpeed = saved.entityWalkSpeed
		entityRoot.AssemblyLinearVelocity = Vector3.zero
		pcall(function() entityRoot:SetNetworkOwner(nil) end)
	end
	if hum.Parent and hum.Health > 0 then
		playerRoot.Anchored = saved.playerAnchored
		hum.WalkSpeed = saved.walkSpeed
		hum.JumpPower = saved.jumpPower
		hum.AutoRotate = saved.autoRotate
		hum.BreakJointsOnDeath = saved.breakJoints
		hum.PlatformStand = saved.platformStand
	end
	workspace:SetAttribute("EntityKillActive", false)
	sequenceBusy = false
end

local function onTouched(hit)
	if sequenceBusy then return end
	local player, char = findPlayer(hit)
	if not player then return end
	if player:GetAttribute("Escaped") == true then return end
	local last = playerDebounce[player]
	if last and os.clock() - last < KILL_DURATION + 1 then return end
	sequenceBusy = true -- reserve immediately; Touched can fire many times per frame
	task.spawn(runKill, player, char)
end

local function connectPart(part)
	if part:IsA("BasePart") then part.Touched:Connect(onTouched) end
end
for _, descendant in ipairs(entity:GetDescendants()) do connectPart(descendant) end
entity.DescendantAdded:Connect(connectPart)

Players.PlayerRemoving:Connect(function(player)
	playerDebounce[player] = nil
end)

print("[EntityKill] Cinematic ground-pin knockout sequence active")
