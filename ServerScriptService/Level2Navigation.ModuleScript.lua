--!strict
-- Shared path, floor and collision utilities for Level 2 anchored hostile rigs.
local PathfindingService = game:GetService("PathfindingService")
local Players = game:GetService("Players")

local Navigation = {}

local function exclusions(entity: Model): {Instance}
	local list: {Instance} = {entity}
	for _, player in ipairs(Players:GetPlayers()) do
		if player.Character then
			table.insert(list, player.Character)
		end
	end
	return list
end

local function rayParams(entity: Model, ignoreWater: boolean): RaycastParams
	local params = RaycastParams.new()
	params.FilterType = Enum.RaycastFilterType.Exclude
	params.FilterDescendantsInstances = exclusions(entity)
	params.IgnoreWater = ignoreWater
	params.RespectCanCollide = true
	return params
end

function Navigation.GetRoot(entity: Model): BasePart?
	local root = entity.PrimaryPart
		or entity:FindFirstChild("HumanoidRootPart", true)
		or entity:FindFirstChild("char1", true)
		or entity:FindFirstChildWhichIsA("BasePart", true)
	if root and root:IsA("BasePart") then
		if entity.PrimaryPart ~= root then
			entity.PrimaryPart = root
		end
		return root
	end
	return nil
end

function Navigation.GroundOffset(entity: Model, root: BasePart): number
	local stored = entity:GetAttribute("GroundOffset")
	if type(stored) == "number" and stored > 0 then
		return stored
	end
	local boxCFrame, boxSize = entity:GetBoundingBox()
	local bottomY = boxCFrame.Position.Y - boxSize.Y * 0.5
	local offset = math.max(0.25, root.Position.Y - bottomY)
	entity:SetAttribute("GroundOffset", offset)
	return offset
end

local function physicalFloor(entity: Model, position: Vector3, expectedFloorY: number?, profile)
	local originY = position.Y + math.max(18, profile.AgentHeight + 8)
	local origin = Vector3.new(position.X, originY, position.Z)
	local excluded = exclusions(entity)
	local params = rayParams(entity, true)

	for _ = 1, 14 do
		params.FilterDescendantsInstances = excluded
		local hit = workspace:Raycast(origin, Vector3.new(0, -120, 0), params)
		if not hit then
			return nil
		end
		local collidable = hit.Instance == workspace.Terrain
			or (hit.Instance:IsA("BasePart") and hit.Instance.CanCollide)
		local closeEnough = expectedFloorY == nil
			or math.abs(hit.Position.Y - expectedFloorY) <= profile.MaxFloorDelta
		if collidable and hit.Normal.Y >= 0.57 and hit.Position.Y > -35 and closeEnough then
			return hit
		end
		table.insert(excluded, hit.Instance)
	end
	return nil
end

local function waterDepth(entity: Model, floorPosition: Vector3, profile): number
	local origin = floorPosition + Vector3.new(0, math.max(10, profile.MaxWaterDepth + 5), 0)
	local excluded = exclusions(entity)
	local params = rayParams(entity, false)
	for _ = 1, 10 do
		params.FilterDescendantsInstances = excluded
		local hit = workspace:Raycast(origin, Vector3.new(0, -40, 0), params)
		if not hit then
			return 0
		end
		if hit.Material == Enum.Material.Water then
			return math.max(0, hit.Position.Y - floorPosition.Y)
		end
		if hit.Position.Y <= floorPosition.Y + 0.15 then
			return 0
		end
		table.insert(excluded, hit.Instance)
	end
	return 0
end

function Navigation.ResolveFloor(entity: Model, rootPosition: Vector3, profile, expectedFloorY: number?)
	local floorHit = physicalFloor(entity, rootPosition, expectedFloorY, profile)
	if not floorHit then
		return nil
	end
	local depth = waterDepth(entity, floorHit.Position, profile)
	if depth > profile.MaxWaterDepth then
		return nil
	end
	return floorHit.Position, depth, floorHit.Instance
end

function Navigation.HasLineOfSight(entity: Model, origin: Vector3, targetRoot: BasePart, maxRange: number): boolean
	local direction = targetRoot.Position - origin
	if direction.Magnitude > maxRange then
		return false
	end
	local params = rayParams(entity, true)
	params.RespectCanCollide = false
	-- The target character must remain raycastable, so remove it from exclusions.
	local filtered = {}
	for _, item in ipairs(params.FilterDescendantsInstances) do
		if item ~= targetRoot.Parent then
			table.insert(filtered, item)
		end
	end
	params.FilterDescendantsInstances = filtered
	local hit = workspace:Raycast(origin, direction, params)
	return hit == nil or hit.Instance:IsDescendantOf(targetRoot.Parent)
end

function Navigation.CanAdvance(entity: Model, currentRootPosition: Vector3, nextRootPosition: Vector3, profile, groundOffset: number)
	local flatDirection = Vector3.new(
		nextRootPosition.X - currentRootPosition.X,
		0,
		nextRootPosition.Z - currentRootPosition.Z
	)
	if flatDirection.Magnitude <= 0.02 then
		return true
	end

	local expectedFloorY = currentRootPosition.Y - groundOffset
	local floor, depth = Navigation.ResolveFloor(entity, nextRootPosition, profile, expectedFloorY)
	if not floor then
		return false, nil, nil, "NoFloor"
	end
	if math.abs(floor.Y - expectedFloorY) > profile.MaxStepHeight then
		return false, nil, nil, "StepTooHigh"
	end

	local height = math.max(3, profile.AgentHeight - profile.MoveClearance * 2)
	local size = Vector3.new(
		math.max(1.5, profile.AgentRadius * 2 - profile.MoveClearance),
		height,
		math.max(1.5, profile.AgentRadius * 2 - profile.MoveClearance)
	)
	local castOrigin = CFrame.new(
		currentRootPosition.X,
		expectedFloorY + profile.MoveClearance + height * 0.5,
		currentRootPosition.Z
	)
	local params = rayParams(entity, true)
	local hit = workspace:Blockcast(castOrigin, size, flatDirection, params)
	if hit and hit.Distance < flatDirection.Magnitude - 0.04 then
		return false, nil, nil, "Blocked"
	end

	local resolvedRoot = Vector3.new(nextRootPosition.X, floor.Y + groundOffset, nextRootPosition.Z)
	return true, resolvedRoot, depth
end

function Navigation.CancelPath(state)
	state.ComputeTicket = (state.ComputeTicket or 0) + 1
	state.Computing = false
	if state.PathBlockedConnection then
		state.PathBlockedConnection:Disconnect()
		state.PathBlockedConnection = nil
	end
	state.Path = nil
	state.Waypoints = {}
	state.WaypointIndex = 1
end

function Navigation.ComputePathAsync(state, entity: Model, from: Vector3, destination: Vector3, profile, callback)
	Navigation.CancelPath(state)
	local ticket = state.ComputeTicket
	state.Computing = true
	local path = PathfindingService:CreatePath({
		AgentRadius = profile.AgentRadius,
		AgentHeight = profile.AgentHeight,
		AgentCanJump = false,
		AgentCanClimb = false,
		WaypointSpacing = profile.WaypointSpacing,
		Costs = {
			DivingObstacle = math.huge,
			Water = 32,
		},
	})

	task.spawn(function()
		local ok = pcall(function()
			path:ComputeAsync(from, destination)
		end)
		if state.ComputeTicket ~= ticket or not entity.Parent then
			return
		end
		state.Computing = false
		if not ok or path.Status ~= Enum.PathStatus.Success then
			callback(ticket, nil, "NoPath")
			return
		end

		state.Path = path
		state.PathBlockedConnection = path.Blocked:Connect(function(blockedIndex)
			if state.ComputeTicket == ticket and blockedIndex >= (state.WaypointIndex or 1) then
				state.RepathRequested = true
			end
		end)
		callback(ticket, path:GetWaypoints(), nil)
	end)
	return ticket
end

local function wanderBounds(entity: Model, state, profile)
	local center = state.SpawnPosition
	local halfX = profile.WanderRadiusMax
	local halfZ = profile.WanderRadiusMax

	local centerAttribute = entity:GetAttribute("WanderCenter")
	local sizeAttribute = entity:GetAttribute("WanderSize")
	if typeof(centerAttribute) == "Vector3" then
		center = centerAttribute
	end
	if typeof(sizeAttribute) == "Vector3" then
		halfX = math.max(4, sizeAttribute.X * 0.5)
		halfZ = math.max(4, sizeAttribute.Z * 0.5)
	else
		local centerX = entity:GetAttribute("WanderCenterX")
		local centerZ = entity:GetAttribute("WanderCenterZ")
		local attrHalfX = entity:GetAttribute("WanderHalfSizeX")
		local attrHalfZ = entity:GetAttribute("WanderHalfSizeZ")
		if type(centerX) == "number" and type(centerZ) == "number" then
			center = Vector3.new(centerX, center.Y, centerZ)
		end
		if type(attrHalfX) == "number" then halfX = math.max(4, attrHalfX) end
		if type(attrHalfZ) == "number" then halfZ = math.max(4, attrHalfZ) end
	end

	local world = workspace:FindFirstChild("PoolroomsLevel2")
	local markerName = profile.Name .. "WanderZone"
	local marker = world and world:FindFirstChild(markerName, true)
	if marker and marker:IsA("BasePart") then
		center = marker.Position
		halfX = marker.Size.X * 0.5
		halfZ = marker.Size.Z * 0.5
	end
	return center, halfX, halfZ
end

function Navigation.ChooseWanderDestination(entity: Model, state, profile)
	local root = Navigation.GetRoot(entity)
	if not root then return nil end
	local center, halfX, halfZ = wanderBounds(entity, state, profile)
	for _ = 1, 24 do
		local angle = math.random() * math.pi * 2
		local distance = profile.WanderRadiusMin
			+ math.random() * math.max(0, profile.WanderRadiusMax - profile.WanderRadiusMin)
		local candidate = center + Vector3.new(
			math.clamp(math.cos(angle) * distance, -halfX, halfX),
			root.Position.Y - center.Y,
			math.clamp(math.sin(angle) * distance, -halfZ, halfZ)
		)
		local expectedFloorY = root.Position.Y - state.GroundOffset
		local floor = Navigation.ResolveFloor(entity, candidate, profile, expectedFloorY)
		if floor then
			return floor
		end
	end
	return Navigation.ResolveFloor(entity, root.Position, profile, root.Position.Y - state.GroundOffset)
end

function Navigation.RecoveryStep(entity: Model, state, profile)
	local root = Navigation.GetRoot(entity)
	if not root then return false end
	local forward = root.CFrame.LookVector
	for _, sign in ipairs({1, -1}) do
		local side = Vector3.new(-forward.Z, 0, forward.X) * sign
		local proposed = root.Position + side * (profile.AgentRadius * 1.8 + 1)
		local clear, resolved = Navigation.CanAdvance(entity, root.Position, proposed, profile, state.GroundOffset)
		if clear and resolved then
			entity:PivotTo(CFrame.lookAt(resolved, resolved + side))
			state.LastSafeCFrame = entity:GetPivot()
			return true
		end
	end
	return false
end

return Navigation
