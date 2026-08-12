-- Level 2 Pool Foam Navigator
--
-- Server-owned locomotion for an anchored Model. Roblox pathfinding is used
-- when it returns a route that stays inside the permitted Level 2 halls. The
-- generated hall/corridor graph is the deterministic fallback.

local PathfindingService = game:GetService("PathfindingService")

local Navigator = {}
Navigator.__index = Navigator

local DEFAULTS = table.freeze({
	AgentRadius = 2.5,
	AgentHeight = 6,
	WaypointSpacing = 5,
	WaypointArrivalDistance = 1.25,
	RepathDistance = 5,
	RepathInterval = 0.7,
	FootClearance = 0.08,
	FloorProbeAbove = 12,
	FloorProbeDepth = 80,
})

local function finiteNumber(value)
	return typeof(value) == "number" and value == value and value > -math.huge and value < math.huge
end

local function finiteVector3(value)
	return typeof(value) == "Vector3"
		and finiteNumber(value.X)
		and finiteNumber(value.Y)
		and finiteNumber(value.Z)
end

local function readNumber(source, key, fallback, minimum, maximum)
	local value = source and source[key]
	if not finiteNumber(value) then
		value = fallback
	end
	if minimum then value = math.max(minimum, value) end
	if maximum then value = math.min(maximum, value) end
	return value
end

local function horizontalDistance(a, b)
	local x = a.X - b.X
	local z = a.Z - b.Z
	return math.sqrt(x * x + z * z)
end

local function normalizeAllowed(raw)
	if typeof(raw) ~= "table" then return nil end
	local result = {}
	local count = 0
	for key, value in pairs(raw) do
		local index
		if typeof(key) == "number" and value == true then
			index = key
		elseif typeof(value) == "number" then
			index = value
		end
		if index and not result[index] then
			result[index] = true
			count += 1
		end
	end
	return count > 0 and result or nil
end

local function buildHallIndex(layout)
	local result = {}
	for arrayIndex, hall in ipairs(layout.Halls or {}) do
		if typeof(hall) == "table" then
			result[tonumber(hall.Index) or arrayIndex] = hall
		end
	end
	return result
end

local function hallCenter(hall)
	if finiteVector3(hall and hall.Center) then return hall.Center end
	local minX = tonumber(hall and hall.MinX) or 0
	local maxX = tonumber(hall and hall.MaxX) or minX
	local minZ = tonumber(hall and hall.MinZ) or 0
	local maxZ = tonumber(hall and hall.MaxZ) or minZ
	return Vector3.new((minX + maxX) * 0.5, 0, (minZ + maxZ) * 0.5)
end

local function findHall(layout, hallByIndex, position, allowed)
	local nearest
	local nearestDistance = math.huge
	for index, hall in pairs(hallByIndex) do
		if not allowed or allowed[index] then
			local minX = tonumber(hall.MinX)
			local maxX = tonumber(hall.MaxX)
			local minZ = tonumber(hall.MinZ)
			local maxZ = tonumber(hall.MaxZ)
			if minX and maxX and minZ and maxZ
				and position.X >= minX and position.X <= maxX
				and position.Z >= minZ and position.Z <= maxZ
			then
				return hall, index
			end
			local distance = horizontalDistance(position, hallCenter(hall))
			if distance < nearestDistance then
				nearest = hall
				nearestDistance = distance
			end
		end
	end
	if nearest then
		return nearest, tonumber(nearest.Index)
	end
	return nil, nil
end

local function corridorBetween(layout, aIndex, bIndex)
	local pairKey = tostring(math.min(aIndex, bIndex)) .. ":" .. tostring(math.max(aIndex, bIndex))
	local byPair = layout.CorridorByPair
	if typeof(byPair) == "table" and typeof(byPair[pairKey]) == "table" then
		return byPair[pairKey]
	end
	for _, corridor in ipairs(layout.Corridors or {}) do
		if typeof(corridor) == "table"
			and ((corridor.A == aIndex and corridor.B == bIndex)
				or (corridor.A == bIndex and corridor.B == aIndex))
		then
			return corridor
		end
	end
	return nil
end

local function corridorBlocked(corridor)
	return corridor ~= nil
		and corridor.Kind == "PressureDoor"
		and workspace:GetAttribute("Level2ExitPowered") ~= true
end

local function graphRoute(layout, hallByIndex, allowed, fromPosition, toPosition)
	local fromHall, fromIndex = findHall(layout, hallByIndex, fromPosition, allowed)
	local toHall, toIndex = findHall(layout, hallByIndex, toPosition, allowed)
	if not (fromHall and fromIndex and toHall and toIndex) then return nil end
	if fromIndex == toIndex then return {toPosition} end

	local queue = {fromIndex}
	local head = 1
	local visited = {[fromIndex] = true}
	local previous = {}
	local previousCorridor = {}
	while head <= #queue and not visited[toIndex] do
		local currentIndex = queue[head]
		head += 1
		local currentHall = hallByIndex[currentIndex]
		for _, rawOther in ipairs((currentHall and currentHall.Connections) or {}) do
			local otherIndex = tonumber(rawOther)
			if otherIndex and hallByIndex[otherIndex]
				and (not allowed or allowed[otherIndex])
				and not visited[otherIndex]
			then
				local corridor = corridorBetween(layout, currentIndex, otherIndex)
				if corridor and not corridorBlocked(corridor) then
					visited[otherIndex] = true
					previous[otherIndex] = currentIndex
					previousCorridor[otherIndex] = corridor
					table.insert(queue, otherIndex)
				end
			end
		end
	end
	if not visited[toIndex] then return nil end

	local hallPath = {toIndex}
	local cursor = toIndex
	while cursor ~= fromIndex do
		cursor = previous[cursor]
		if not cursor then return nil end
		table.insert(hallPath, 1, cursor)
	end

	local points = {}
	for pathIndex = 1, #hallPath - 1 do
		local currentIndex = hallPath[pathIndex]
		local nextIndex = hallPath[pathIndex + 1]
		local currentHall = hallByIndex[currentIndex]
		local nextHall = hallByIndex[nextIndex]
		local corridor = previousCorridor[nextIndex]
		if not (currentHall and nextHall and corridor) then return nil end

		local currentCenter = hallCenter(currentHall)
		local nextCenter = hallCenter(nextHall)
		local cross = tonumber(corridor.Cross)
		local from = tonumber(corridor.From)
		local to = tonumber(corridor.To)
		if not (cross and from and to) then return nil end
		if corridor.Axis == "X" then
			table.insert(points, Vector3.new(currentCenter.X, fromPosition.Y, cross))
			if corridor.Kind ~= "SharedWall" then
				table.insert(points, Vector3.new((from + to) * 0.5, fromPosition.Y, cross))
			end
			table.insert(points, Vector3.new(nextCenter.X, fromPosition.Y, cross))
		else
			table.insert(points, Vector3.new(cross, fromPosition.Y, currentCenter.Z))
			if corridor.Kind ~= "SharedWall" then
				table.insert(points, Vector3.new(cross, fromPosition.Y, (from + to) * 0.5))
			end
			table.insert(points, Vector3.new(cross, fromPosition.Y, nextCenter.Z))
		end
	end
	table.insert(points, toPosition)
	return points
end

function Navigator.new(model, manifest, tuning, options)
	assert(model and model:IsA("Model"), "Pool Foam Navigator requires a Model")
	assert(model.PrimaryPart and model.PrimaryPart:IsA("BasePart"), "Pool Foam Navigator model requires a PrimaryPart")
	assert(manifest and manifest.World and typeof(manifest.Layout) == "table", "Pool Foam Navigator requires manifest.World and manifest.Layout")

	tuning = typeof(tuning) == "table" and tuning or {}
	options = typeof(options) == "table" and options or {}
	local pivot = model:GetPivot()
	local boundsCFrame, boundsSize = model:GetBoundingBox()
	local bottomY = boundsCFrame.Position.Y - boundsSize.Y * 0.5

	for _, descendant in ipairs(model:GetDescendants()) do
		if descendant:IsA("BasePart") then
			descendant.Anchored = true
			descendant.AssemblyLinearVelocity = Vector3.zero
			descendant.AssemblyAngularVelocity = Vector3.zero
		end
	end

	local raycastParams = RaycastParams.new()
	raycastParams.FilterType = Enum.RaycastFilterType.Exclude
	-- Ground the rig on the tiled basin floor. Treating Terrain water as the
	-- floor made the proxy skate on the surface instead of wading through it.
	raycastParams.IgnoreWater = true
	local exclusions = {model}
	if manifest.EntityNodes then table.insert(exclusions, manifest.EntityNodes) end
	local navigationFolder = manifest.World:FindFirstChild("Level 2 Navigation", true)
	if navigationFolder then table.insert(exclusions, navigationFolder) end
	local runtimeFolder = options.RuntimeFolder
	if runtimeFolder and runtimeFolder ~= model.Parent then table.insert(exclusions, runtimeFolder) end
	raycastParams.FilterDescendantsInstances = exclusions

	local self = setmetatable({
		Model = model,
		Manifest = manifest,
		Layout = manifest.Layout,
		HallByIndex = buildHallIndex(manifest.Layout),
		AllowedHallIndices = normalizeAllowed(options.AllowedHallIndices),
		Tuning = {
			AgentRadius = readNumber(tuning, "AgentRadius", DEFAULTS.AgentRadius, 0.5, 12),
			AgentHeight = readNumber(tuning, "AgentHeight", DEFAULTS.AgentHeight, 2, 24),
			WaypointSpacing = readNumber(tuning, "WaypointSpacing", DEFAULTS.WaypointSpacing, 1, 24),
			WaypointArrivalDistance = readNumber(tuning, "WaypointArrivalDistance", DEFAULTS.WaypointArrivalDistance, 0.2, 8),
			RepathDistance = readNumber(tuning, "RepathDistance", DEFAULTS.RepathDistance, 0.5, 50),
			RepathInterval = readNumber(tuning, "RepathInterval", DEFAULTS.RepathInterval, 0.1, 10),
			FootClearance = readNumber(tuning, "FootClearance", DEFAULTS.FootClearance, 0, 3),
			FloorProbeAbove = readNumber(tuning, "FloorProbeAbove", DEFAULTS.FloorProbeAbove, 3, 60),
			FloorProbeDepth = readNumber(tuning, "FloorProbeDepth", DEFAULTS.FloorProbeDepth, 20, 300),
		},
		PivotAboveFoot = math.max(0, pivot.Position.Y - bottomY),
		FootPosition = Vector3.new(pivot.Position.X, bottomY, pivot.Position.Z),
		Facing = Vector3.new(pivot.LookVector.X, 0, pivot.LookVector.Z).Magnitude > 0.001
			and Vector3.new(pivot.LookVector.X, 0, pivot.LookVector.Z).Unit
			or Vector3.new(0, 0, -1),
		RaycastParams = raycastParams,
		Waypoints = {},
		WaypointIndex = 1,
		Goal = nil,
		LastRequestedGoal = nil,
		LastPathAt = -math.huge,
		RequestId = 0,
		Computing = false,
		Destroyed = false,
		Status = "IDLE",
		LastFailure = nil,
	}, Navigator)
	return self
end

function Navigator:FindHall(position)
	if not finiteVector3(position) then return nil end
	return findHall(self.Layout, self.HallByIndex, position, self.AllowedHallIndices)
end

function Navigator:_positionAllowed(position)
	if not self.AllowedHallIndices then return true end
	local _, index = findHall(self.Layout, self.HallByIndex, position, nil)
	return index ~= nil and self.AllowedHallIndices[index] == true
end

function Navigator:_surfaceAt(position)
	local origin = position + Vector3.new(0, self.Tuning.FloorProbeAbove, 0)
	local result = workspace:Raycast(origin, Vector3.new(0, -self.Tuning.FloorProbeDepth, 0), self.RaycastParams)
	-- In low-ceilinged rooms (kids wing) the probe origin can start ABOVE the
	-- roof, so the ray lands on the rooftop and the rig snaps on top of the
	-- room. Only accept surfaces near or below the intended position.
	if result and result.Normal.Y > 0.15 and result.Position.Y <= position.Y + 6 then
		return result.Position.Y
	end
	return position.Y
end

function Navigator:_placeFoot(position, facing)
	if self.Destroyed or not (self.Model and self.Model.Parent) then return false end
	local surfaceY = self:_surfaceAt(position)
	local foot = Vector3.new(position.X, surfaceY + self.Tuning.FootClearance, position.Z)
	local flatFacing = facing and Vector3.new(facing.X, 0, facing.Z) or self.Facing
	if flatFacing.Magnitude > 0.001 then self.Facing = flatFacing.Unit end
	local pivotPosition = foot + Vector3.new(0, self.PivotAboveFoot, 0)
	self.Model:PivotTo(CFrame.lookAt(pivotPosition, pivotPosition + self.Facing))
	self.FootPosition = foot
	return true
end

function Navigator:WarpTo(position, facing)
	if not finiteVector3(position) then return false end
	self:Stop()
	return self:_placeFoot(position, facing)
end

function Navigator:_clearDirectLine(fromPosition, toPosition)
	local height = math.clamp(self.PivotAboveFoot * 0.5, 1.5, 5)
	local origin = fromPosition + Vector3.new(0, height, 0)
	local target = Vector3.new(toPosition.X, origin.Y, toPosition.Z)
	local displacement = target - origin
	if displacement.Magnitude < 0.05 then return true end
	return workspace:Raycast(origin, displacement, self.RaycastParams) == nil
end

function Navigator:_fallbackWaypoints(goal)
	local route = graphRoute(self.Layout, self.HallByIndex, self.AllowedHallIndices, self.FootPosition, goal)
	if route and #route > 0 then return route, "GRAPH" end
	if self:_positionAllowed(goal) and self:_clearDirectLine(self.FootPosition, goal) then
		return {goal}, "DIRECT"
	end
	return {}, "NO_PATH"
end

function Navigator:_pathPointsAllowed(points)
	if not self.AllowedHallIndices then return true end
	for _, point in ipairs(points) do
		if not self:_positionAllowed(point) then return false end
	end
	return true
end

function Navigator:_requestPath(goal)
	self.RequestId += 1
	local requestId = self.RequestId
	self.Computing = true
	self.LastPathAt = os.clock()
	self.LastRequestedGoal = goal

	task.spawn(function()
		local path
		local success, failure = pcall(function()
			path = PathfindingService:CreatePath({
				AgentRadius = self.Tuning.AgentRadius,
				AgentHeight = self.Tuning.AgentHeight,
				AgentCanJump = false,
				WaypointSpacing = self.Tuning.WaypointSpacing,
				Costs = {Water = 1},
			})
			path:ComputeAsync(self.FootPosition, goal)
		end)
		if self.Destroyed or requestId ~= self.RequestId then return end

		local points = {}
		local status = "PATH_FAILED"
		if success and path and path.Status == Enum.PathStatus.Success then
			for _, waypoint in ipairs(path:GetWaypoints()) do
				if horizontalDistance(waypoint.Position, self.FootPosition) > self.Tuning.WaypointArrivalDistance then
					table.insert(points, waypoint.Position)
				end
			end
			if #points == 0 or horizontalDistance(points[#points], goal) > 2 then table.insert(points, goal) end
			if self:_pathPointsAllowed(points) then
				status = "PATH"
			else
				points, status = self:_fallbackWaypoints(goal)
				failure = "path left allowed halls"
			end
		else
			points, status = self:_fallbackWaypoints(goal)
		end

		if self.Destroyed or requestId ~= self.RequestId then return end
		self.Waypoints = points
		self.WaypointIndex = 1
		self.Status = status
		self.LastFailure = status == "NO_PATH" and tostring(failure or "no route") or nil
		self.Computing = false
	end)
end

function Navigator:SetGoal(goal, force)
	if self.Destroyed or not finiteVector3(goal) or not self:_positionAllowed(goal) then return false end
	self.Goal = goal
	local now = os.clock()
	local moved = not self.LastRequestedGoal
		or horizontalDistance(goal, self.LastRequestedGoal) >= self.Tuning.RepathDistance
	local stale = now - self.LastPathAt >= self.Tuning.RepathInterval
	if not self.Computing and (force == true or moved or stale or #self.Waypoints == 0) then
		self:_requestPath(goal)
	end
	return true
end

function Navigator:Stop()
	self.Goal = nil
	self.Waypoints = {}
	self.WaypointIndex = 1
	self.Status = "IDLE"
	self.RequestId += 1
	self.Computing = false
end

function Navigator:Step(deltaTime, speed)
	if self.Destroyed or not (self.Model and self.Model.Parent) then return false end
	deltaTime = finiteNumber(deltaTime) and math.clamp(deltaTime, 0, 0.25) or 0
	speed = finiteNumber(speed) and math.max(0, speed) or 0
	local waypoint = self.Waypoints[self.WaypointIndex]
	if not waypoint then
		local reached = self.Goal ~= nil
			and horizontalDistance(self.FootPosition, self.Goal) <= self.Tuning.WaypointArrivalDistance
		if self.Goal and not reached and not self.Computing
			and os.clock() - self.LastPathAt >= self.Tuning.RepathInterval
		then
			self:_requestPath(self.Goal)
		end
		return reached
	end

	local current = self.FootPosition
	local difference = Vector3.new(waypoint.X - current.X, 0, waypoint.Z - current.Z)
	local distance = difference.Magnitude
	if distance <= self.Tuning.WaypointArrivalDistance then
		self.WaypointIndex += 1
		return self.WaypointIndex > #self.Waypoints
	end
	if speed <= 0 or deltaTime <= 0 then return false end
	local direction = difference.Unit
	local travel = math.min(distance, speed * deltaTime)
	self:_placeFoot(current + direction * travel, direction)
	return false
end

function Navigator:GetPosition()
	return self.FootPosition
end

function Navigator:Face(position)
	if finiteVector3(position) then
		self:_placeFoot(self.FootPosition, position - self.FootPosition)
	end
end

function Navigator:GetStatus()
	return self.Status
end

function Navigator:GetDebugSnapshot()
	return {
		Status = self.Status,
		Computing = self.Computing,
		WaypointIndex = self.WaypointIndex,
		WaypointCount = #self.Waypoints,
		Goal = self.Goal,
		Position = self.FootPosition,
		LastFailure = self.LastFailure,
	}
end

function Navigator:Destroy()
	if self.Destroyed then return end
	self:Stop()
	self.Destroyed = true
	self.Model = nil
	self.Manifest = nil
	self.Layout = nil
	self.HallByIndex = nil
	self.RaycastParams = nil
end

return Navigator
