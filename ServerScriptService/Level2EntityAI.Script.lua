-- Pool Foam Entity movement for Level 2.
-- The imported Meshy rig stays anchored and is moved along Roblox paths so it
-- can use its skinned animation without relying on a Humanoid rig.

local Players = game:GetService("Players")
local PathfindingService = game:GetService("PathfindingService")
local RunService = game:GetService("RunService")

local ENTITY_NAME = "PoolFoamEntity"
local WANDER_SPEED = 7.5
local CHASE_SPEED = 18
local SIGHT_RANGE = 105
local GIVE_UP_RANGE = 145
local MAX_FLOOR_DELTA = 2.75

local activeToken = 0

local function livingRoot(player)
	if player:GetAttribute("InRound") ~= true or player:GetAttribute("Escaped") == true then return nil end
	local character = player.Character
	local humanoid = character and character:FindFirstChildOfClass("Humanoid")
	local root = character and character:FindFirstChild("HumanoidRootPart")
	if humanoid and humanoid.Health > 0 and root then return root end
	return nil
end

local function canSee(entity, targetRoot)
	local root = entity.PrimaryPart
	if not root then return false end
	local origin = root.Position + Vector3.new(0, 2.5, 0)
	local direction = targetRoot.Position - origin
	if direction.Magnitude > SIGHT_RANGE then return false end
	local params = RaycastParams.new()
	params.FilterType = Enum.RaycastFilterType.Exclude
	params.FilterDescendantsInstances = {entity}
	params.IgnoreWater = true
	local hit = workspace:Raycast(origin, direction, params)
	return not hit or hit.Instance:IsDescendantOf(targetRoot.Parent)
end

local function nearestVisible(entity)
	local best, bestDistance
	for _, player in ipairs(Players:GetPlayers()) do
		local root = livingRoot(player)
		if root then
			local distance = (root.Position - entity.PrimaryPart.Position).Magnitude
			if (not bestDistance or distance < bestDistance) and canSee(entity, root) then
				best, bestDistance = root, distance
			end
		end
	end
	return best, bestDistance
end

local function safeFloor(position, entity)
	local root = entity.PrimaryPart
	if not root then return nil end
	local expectedFloorY = position.Y - root.Size.Y * .5
	local params = RaycastParams.new()
	params.FilterType = Enum.RaycastFilterType.Exclude
	params.IgnoreWater = true
	local excluded = {entity}
	-- Search through overhead diving boards instead of treating them as ground.
	-- This keeps the wide probe reliable while preventing upward snapping.
	local origin = Vector3.new(position.X, expectedFloorY + 32, position.Z)
	for _ = 1, 10 do
		params.FilterDescendantsInstances = excluded
		local hit = workspace:Raycast(origin, Vector3.new(0, -80, 0), params)
		if not hit then return nil end
		if hit.Normal.Y > .55
			and hit.Position.Y > -4
			and math.abs(hit.Position.Y - expectedFloorY) <= MAX_FLOOR_DELTA then
			return hit.Position
		end
		table.insert(excluded, hit.Instance)
	end
	return nil
end

local function makePath(from, destination)
	local path = PathfindingService:CreatePath({
		AgentRadius = 2.4,
		AgentHeight = 9,
		AgentCanJump = false,
		AgentCanClimb = false,
		WaypointSpacing = 7,
		Costs = {DivingObstacle = math.huge},
	})
	local ok = pcall(function() path:ComputeAsync(from, destination) end)
	if ok and path.Status == Enum.PathStatus.Success then return path:GetWaypoints() end
	return nil
end

local function chooseWanderPoint(entity)
	local origin = entity.PrimaryPart.Position
	for _ = 1, 18 do
		local angle = math.random() * math.pi * 2
		local distance = math.random(28, 75)
		local candidate = origin + Vector3.new(math.cos(angle) * distance, 0, math.sin(angle) * distance)
		local floor = safeFloor(candidate, entity)
		if floor then return floor end
	end
	return origin
end

local function bindEntity(entity)
	activeToken += 1
	local token = activeToken
	local root = entity.PrimaryPart or entity:FindFirstChild("char1", true) or entity:FindFirstChildWhichIsA("BasePart", true)
	if not root then return end
	entity.PrimaryPart = root

	local targetRoot
	local wanderGoal = chooseWanderPoint(entity)
	local waypoints = {}
	local waypointIndex = 1
	local nextPathAt = 0
	local nextSightAt = 0

	local connection
	connection = RunService.Heartbeat:Connect(function(dt)
		if token ~= activeToken or not entity.Parent or workspace:GetAttribute("SelectedLevel") ~= 2 then
			connection:Disconnect()
			return
		end

		local now = os.clock()
		if now >= nextSightAt then
			nextSightAt = now + .18
			local seen = nearestVisible(entity)
			if seen then
				targetRoot = seen
				nextPathAt = 0
			elseif targetRoot and ((not targetRoot.Parent) or (targetRoot.Position - root.Position).Magnitude > GIVE_UP_RANGE) then
				targetRoot = nil
				wanderGoal = chooseWanderPoint(entity)
				nextPathAt = 0
			end
		end

		local chasing = targetRoot and targetRoot.Parent ~= nil
		local destination = chasing and targetRoot.Position or wanderGoal
		if not destination then
			wanderGoal = chooseWanderPoint(entity)
			destination = wanderGoal
		end

		if now >= nextPathAt or waypointIndex > #waypoints then
			waypoints = makePath(root.Position, destination) or {}
			waypointIndex = (#waypoints > 1) and 2 or 1
			nextPathAt = now + (chasing and .7 or 4.5)
			if #waypoints == 0 and not chasing then
				wanderGoal = chooseWanderPoint(entity)
			end
		end

		local waypoint = waypoints[waypointIndex]
		if not waypoint then
			entity:SetAttribute("MotionState", "Idle")
			entity:SetAttribute("MoveSpeed", 0)
			return
		end

		local current = root.Position
		local flatDelta = Vector3.new(waypoint.Position.X - current.X, 0, waypoint.Position.Z - current.Z)
		if flatDelta.Magnitude < 2.2 then
			waypointIndex += 1
			if waypointIndex > #waypoints and not chasing then wanderGoal = chooseWanderPoint(entity) end
			return
		end

		local speed = chasing and CHASE_SPEED or WANDER_SPEED
		local step = math.min(speed * dt, flatDelta.Magnitude)
		-- Preserve the root's vertical coordinate.  Setting this to zero made the
		-- floor validator compare the deck against a point below the entity.
		local nextFlat = Vector3.new(current.X, current.Y, current.Z) + flatDelta.Unit * step
		local floor = safeFloor(nextFlat, entity)
		if not floor then
			waypoints = {}
			nextPathAt = 0
			return
		end

		local nextPosition = Vector3.new(nextFlat.X, floor.Y + root.Size.Y * .5, nextFlat.Z)
		local lookAt = nextPosition + flatDelta.Unit
		entity:PivotTo(CFrame.lookAt(nextPosition, lookAt))
		entity:SetAttribute("MotionState", chasing and "Chase" or "Walk")
		entity:SetAttribute("MoveSpeed", speed)
	end)
end

local function consider(object)
	if object.Name == ENTITY_NAME and object:IsA("Model") then task.defer(bindEntity, object) end
end

workspace.ChildAdded:Connect(consider)
local existing = workspace:FindFirstChild(ENTITY_NAME)
if existing then consider(existing) end
