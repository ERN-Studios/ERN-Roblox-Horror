-- Level 2 Pool Foam Navigator
--
-- Server-owned locomotion for an anchored Model. Roblox pathfinding is used
-- when it returns a route that stays inside the permitted Level 2 halls. The
-- generated hall/corridor graph is the deterministic fallback.

local PathfindingService = game:GetService("PathfindingService")
local Players = game:GetService("Players")

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
	MaxStepHeight = 3.5,
	-- Longest horizontal distance the foot may cross in ONE validated placement.
	-- Mirrors the Slidemouth controller's authored MOVEMENT.MaxTravelStep.
	MaxTravelStep = 0.9,
})

-- How many step-height ledges the horizontal sweep may cast past before it
-- gives up. Exhausting it is a FAILURE, not a pass: at that point the sweep has
-- proved nothing about whatever is still in front of the rig.
local SWEEP_EXCLUSION_BUDGET = 6
-- Hard ceiling on validated placements per Step call, so a pathological
-- deltaTime or speed can never spin an unbounded raycast loop inside one frame.
--
-- WHAT SHIPPED BROKEN: Step advanced the whole of `speed * deltaTime` in a
-- SINGLE _placeFoot and validated only the endpoint. The controller's authored
-- MaxTravelStep = .9 was never read by this module at all, so at the live top
-- speed of 36 a 0.1s controller frame moved the foot 3.6 studs in one go -- and
-- the public API's own deltaTime ceiling of .25 allows 9.0. The authored
-- geometry the creature has to negotiate is far smaller than that: 1.2 / 1.4 /
-- 0.8-stud pool and stair features and 0.70-0.80 curbs. A stride that long
-- straddles them completely: the start is on the low slab, the endpoint is on
-- the low slab, and the riser in between is never sampled. That is the reported
-- "cannot walk over small edges" -- not a failure to climb, a failure to LOOK.
--
-- Step now walks the stride in <= MaxTravelStep pieces and runs the full floor
-- + body validation on every one. This cap bounds that loop. At the authored
-- .9 it covers 10.8 studs of travel per call, which is more than the worst
-- stride any legal (deltaTime <= .25, speed <= 36) pair can ask for, so it does
-- not bind in play; it exists only so an absurd input fails CLOSED -- the rig
-- stops early having validated every stud it crossed -- instead of falling back
-- to one unvalidated leap.
local MAX_TRAVEL_SUBSTEPS = 12
-- How many distance-LOSING sidesteps toward clearance may happen between two
-- steps that actually make progress. The budget refills ONLY on a progressing
-- placement, so this cannot become an orbit: a rig that can do nothing but
-- sidestep exhausts it and is reported blocked.
local MAX_CLEARANCE_SEEKS = 8
-- How many individual waypoints a route may skip before it is re-planned. A
-- single unreachable point in a long route is not a reason to discard the rest;
-- a route where every point is unreachable is.
local MAX_WAYPOINT_SKIPS = 6
-- Consecutive frames in which nothing at all could be placed before the route
-- is thrown away and re-planned.
local ROUTE_ABANDON_FAILURES = 4
-- How far a wedged rig backs out along its own trail before re-planning, and
-- how many times it may do so WITHOUT ever getting closer to its goal.
local ROUTE_RETREAT_STUDS = 16
local MAX_ROUTE_RETREATS = 5
-- Recheck a proved obstruction cheaply; never rebuild the whole blocked route
-- just because time passed. Doors can open while the player stands still.
local CLEARANCE_RECHECK_INTERVAL = 3
-- Validated positions kept for the retreat recovery, and the furthest it may
-- ever walk back along them.
local TRAIL_LIMIT = 48
local TRAIL_SPACING = .6

local function finiteNumber(value)
	return typeof(value) == "number" and value == value and value > -math.huge and value < math.huge
end

local function finiteVector3(value)
	return typeof(value) == "Vector3"
		and finiteNumber(value.X)
		and finiteNumber(value.Y)
		and finiteNumber(value.Z)
end

-- The authored steer ladder, sanitised. Degrees, ascending, never backward:
-- a probe past 90 degrees makes the rig moonwalk around obstacles, which is the
-- behaviour the controller's own comment says was removed once already.
local DEFAULT_STEER_ANGLES = {20, 35, 50}

local function readSteerAngles(tuning)
	local source = tuning and tuning.SteerAngles
	if type(source) ~= "table" then return DEFAULT_STEER_ANGLES end
	local angles = {}
	for _, value in ipairs(source) do
		local degrees = tonumber(value)
		if degrees and degrees == degrees and degrees > 0 and degrees < 90 then
			angles[#angles + 1] = degrees
		end
	end
	if #angles == 0 then return DEFAULT_STEER_ANGLES end
	table.sort(angles)
	return angles
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

-- World-space top of a part's axis-aligned bound, correct for rotated parts.
-- `part.Position` is the CENTRE, which for an authored riser or a curb sits far
-- below its walking surface; using it to decide "is this below my feet" is what
-- made every small floor edge read as a wall.
local function partTopY(part)
	local cframe = part.CFrame
	local size = part.Size
	return cframe.Position.Y
		+ math.abs(cframe.RightVector.Y) * size.X * .5
		+ math.abs(cframe.UpVector.Y) * size.Y * .5
		+ math.abs(cframe.LookVector.Y) * size.Z * .5
end

local function isEntityGround(part)
	return part:GetAttribute("Level2_EntityGround") == true
		and part:GetAttribute("Level2_NoEntityGround") ~= true
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
		-- Route through the generated hall hub before and after every doorway.
		-- The world builder reserves these centre axes and door spokes for the
		-- square body. The old graph route connected consecutive door-alignment
		-- points diagonally across arbitrary furniture; seed 404 consequently
		-- needed nine local A* detours and exceeded the strict planning deadline
		-- despite having a valid authored route.
		table.insert(points,
			Vector3.new(currentCenter.X, fromPosition.Y, currentCenter.Z))
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
		table.insert(points, Vector3.new(nextCenter.X, fromPosition.Y, nextCenter.Z))
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
	local authoredGroundOffset = model:GetAttribute("PoolFoamGroundOffset")
	if not finiteNumber(authoredGroundOffset) or authoredGroundOffset < 0 then
		authoredGroundOffset = model:GetAttribute("GroundOffset")
	end
	if not finiteNumber(authoredGroundOffset) or authoredGroundOffset < 0 then
		authoredGroundOffset = math.max(0, pivot.Position.Y - bottomY)
	end
	authoredGroundOffset = math.clamp(authoredGroundOffset, 0, 24)

	for _, descendant in ipairs(model:GetDescendants()) do
		if descendant:IsA("BasePart") then
			descendant.AssemblyLinearVelocity = Vector3.zero
			descendant.AssemblyAngularVelocity = Vector3.zero
		end
	end
	model.PrimaryPart.Anchored = true

	local raycastParams = RaycastParams.new()
	raycastParams.FilterType = Enum.RaycastFilterType.Exclude
	-- Ground the rig on the tiled basin floor. Treating Terrain water as the
	-- floor made the proxy skate on the surface instead of wading through it.
	raycastParams.IgnoreWater = true
	raycastParams.RespectCanCollide = true
	local exclusions = {model}
	local exclusionSet = {[model] = true}
	local function addExclusion(instance)
		if typeof(instance) ~= "Instance" or exclusionSet[instance] then return end
		exclusionSet[instance] = true
		table.insert(exclusions, instance)
	end
	addExclusion(manifest.EntityNodes)
	local navigationFolder = manifest.World:FindFirstChild("Level 2 Navigation", true)
	addExclusion(navigationFolder)
	local runtimeFolder = options.RuntimeFolder
	addExclusion(runtimeFolder)
	for _, instance in ipairs(options.ObstacleExclusions or {}) do addExclusion(instance) end
	-- Loose rafts, rings, noodles, balls and floaties are intentionally soft
	-- props. They may be shoved by the creature, but never invalidate a route
	-- or make its body sweep oscillate at a doorway.
	for _, descendant in ipairs(manifest.World:GetDescendants()) do
		if descendant:GetAttribute("Level2_BuoyantProp") == true then addExclusion(descendant) end
	end
	raycastParams.FilterDescendantsInstances = exclusions
	local overlapParams = OverlapParams.new()
	overlapParams.FilterType = Enum.RaycastFilterType.Exclude
	overlapParams.FilterDescendantsInstances = exclusions
	overlapParams.MaxParts = 64
	-- Ignore decorative/noncollidable query hits inside the capped result set;
	-- otherwise 64 cosmetic pieces can hide the real wall behind them.
	overlapParams.RespectCanCollide = true

	local groundParts = {}
	for _, descendant in ipairs(manifest.World:GetDescendants()) do
		if descendant:IsA("BasePart")
			and descendant.CanCollide
			and descendant:GetAttribute("Level2_EntityGround") == true
		then
			table.insert(groundParts, descendant)
		end
	end
	local floorRaycastParams
	if #groundParts > 0 then
		floorRaycastParams = RaycastParams.new()
		floorRaycastParams.FilterType = Enum.RaycastFilterType.Include
		floorRaycastParams.FilterDescendantsInstances = groundParts
		floorRaycastParams.IgnoreWater = true
		floorRaycastParams.RespectCanCollide = true
	end

	local self = setmetatable({
		Model = model,
		Manifest = manifest,
		Layout = manifest.Layout,
		HallByIndex = buildHallIndex(manifest.Layout),
		AllowedHallIndices = normalizeAllowed(options.AllowedHallIndices),
		Tuning = {
			AgentRadius = readNumber(tuning, "AgentRadius", DEFAULTS.AgentRadius, 0.5, 12),
			PathAgentRadius = readNumber(tuning, "PathAgentRadius",
				readNumber(tuning, "AgentRadius", DEFAULTS.AgentRadius, 0.5, 12), 0.5, 12),
			AgentHeight = readNumber(tuning, "AgentHeight", DEFAULTS.AgentHeight, 2, 24),
			WaypointSpacing = readNumber(tuning, "WaypointSpacing", DEFAULTS.WaypointSpacing, 1, 24),
			WaypointArrivalDistance = readNumber(tuning, "WaypointArrivalDistance", DEFAULTS.WaypointArrivalDistance, 0.2, 8),
			RepathDistance = readNumber(tuning, "RepathDistance", DEFAULTS.RepathDistance, 0.5, 50),
			RepathInterval = readNumber(tuning, "RepathInterval", DEFAULTS.RepathInterval, 0.1, 10),
			-- Opt-in route policy. The Pool Slide was its only user and was removed
			-- on 2026-09-02, so this is now always false and every StableRoutes
			-- branch below takes its else path -- which is Pool Foam's own tested
			-- behaviour. Left in place deliberately: removing the branches is a
			-- large diff through tuned navigation for no runtime gain.
			StableRoutes = tuning.StableRoutes == true,
			PathRequestTimeout = readNumber(tuning, "PathRequestTimeout", 8, 2, 30),
			FootClearance = readNumber(tuning, "FootClearance", DEFAULTS.FootClearance, 0, 3),
			FloorProbeAbove = readNumber(tuning, "FloorProbeAbove", DEFAULTS.FloorProbeAbove, 3, 60),
			FloorProbeDepth = readNumber(tuning, "FloorProbeDepth", DEFAULTS.FloorProbeDepth, 20, 300),
			MaxStepHeight = readNumber(tuning, "MaxStepHeight", DEFAULTS.MaxStepHeight, 0.5, 12),
			-- Read through the same path as every other key so the controller's
			-- authored .9 actually ARRIVES here. It was declared in MOVEMENT and
			-- silently dropped on the floor for the whole of the shipped build.
			MaxTravelStep = readNumber(tuning, "MaxTravelStep", DEFAULTS.MaxTravelStep, 0.1, 12),
			-- The authored steer ladder, finally read. It has sat in the
			-- Slidemouth's MOVEMENT table since the feature was written and
			-- nothing ever consumed it.
			SteerAngles = readSteerAngles(tuning),
		},
		PivotAboveFoot = authoredGroundOffset,
		FootPosition = Vector3.new(pivot.Position.X, bottomY, pivot.Position.Z),
		Facing = Vector3.new(pivot.LookVector.X, 0, pivot.LookVector.Z).Magnitude > 0.001
			and Vector3.new(pivot.LookVector.X, 0, pivot.LookVector.Z).Unit
			or Vector3.new(0, 0, -1),
		RaycastParams = raycastParams,
		OverlapParams = overlapParams,
		BaseExclusions = exclusions,
		FloorRaycastParams = floorRaycastParams,
		Waypoints = {},
		WaypointIndex = 1,
		Goal = nil,
		LastRequestedGoal = nil,
		LastPathAt = -math.huge,
		RequestId = 0,
		Computing = false,
		RouteInstallCount = 0,
		RouteRejectedCount = 0,
		RoutePrefixSkips = 0,
		InstalledGoal = nil,
		BlockedGoalApproach = nil,
		BlockedProbeFrom = nil,
		BlockedProbeTarget = nil,
		NextClearanceProbeAt = 0,
		BlockedConnection = nil,
		-- The Path the connection above belongs to. Recorded because a pause has
		-- to be able to REBUILD the binding, and a connection alone cannot be
		-- rebuilt -- the signal it came from has to be reachable.
		BlockedPath = nil,
		Destroyed = false,
		Status = "IDLE",
		LastFailure = nil,
		HasGrounded = false,
		LastSafeFoot = nil,
		LastSafeFacing = nil,
		LastBlockedBy = nil,
		-- Recently occupied, already validated foot positions, oldest first.
		Trail = {},
		TrailFrozen = false,
		ClearanceSeeks = 0,
		GoalApproach = nil,
		RouteRetreats = 0,
		BestGoalDistance = math.huge,
		WaypointSkips = 0,
		RouteFailures = 0,
		-- Set by Step when a stride wanted more than MAX_TRAVEL_SUBSTEPS pieces
		-- and was shortened rather than coarsened. Purely a diagnostic, and
		-- rewritten by every Step that reaches the travel block, so it is
		-- deliberately NOT in NAVIGATOR_PAUSE_FIELDS and NOT in
		-- GetFullDebugSnapshot: there is no state here worth carrying across a
		-- borrow, and putting a field the pause contract does not restore into
		-- the snapshot the pause-drift assertion compares would invent drift.
		TravelClamped = false,
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

function Navigator:_refreshObstacleFilters()
	local exclusions = table.clone(self.BaseExclusions)
	for _, player in ipairs(Players:GetPlayers()) do
		if player.Character then table.insert(exclusions, player.Character) end
	end
	self.RaycastParams.FilterDescendantsInstances = exclusions
	self.OverlapParams.FilterDescendantsInstances = exclusions
end

function Navigator:_surfaceAt(position, allowLargeStep, expectedFootY)
	local origin = position + Vector3.new(0, self.Tuning.FloorProbeAbove, 0)
	local params = self.FloorRaycastParams or self.RaycastParams
	local expectedFloorY
	if finiteNumber(expectedFootY) then
		expectedFloorY = expectedFootY - self.Tuning.FootClearance
	else
		expectedFloorY = self.HasGrounded
			and self.FootPosition.Y - self.Tuning.FootClearance
			or position.Y - self.Tuning.FootClearance
	end
	local bestY
	local bestDelta = math.huge
	local remaining = self.Tuning.FloorProbeDepth
	local rayOrigin = origin
	for _ = 1, 16 do
		if remaining <= .05 then break end
		local result = workspace:Raycast(rayOrigin, Vector3.new(0, -remaining, 0), params)
		if not result then break end
		local delta = math.abs(result.Position.Y - expectedFloorY)
		local valid = result.Instance.CanCollide
			and result.Normal.Y >= .57
			and result.Instance:GetAttribute("Level2_EntityGround") == true
			and result.Instance:GetAttribute("Level2_NoEntityGround") ~= true
			and (allowLargeStep == true or delta <= self.Tuning.MaxStepHeight)
		if valid then
			if allowLargeStep == true then
				-- A warp resolves to the surface nearest the requested height.
				if delta < bestDelta then
					bestY = result.Position.Y
					bestDelta = delta
				end
			elseif bestY == nil or result.Position.Y > bestY then
				-- Walking resolves to the HIGHEST reachable surface. Preferring the
				-- surface nearest the current foot made every authored step
				-- invisible: the slab beneath a .78-stud stair riser is always the
				-- closer match, so the rig stayed at floor height and then jammed
				-- its body against the riser it was standing inside.
				bestY = result.Position.Y
			end
		end
		local travelled = math.max(.05, rayOrigin.Y - result.Position.Y + .05)
		remaining -= travelled
		rayOrigin = result.Position - Vector3.new(0, .05, 0)
	end
	return bestY
end

-- Authored geometry whose TOP surface is within one step of the destination
-- foot is a floor feature, not an obstruction: a .78-stud stair riser, a
-- corridor curb, a pool-deck ledge. A Roblox Humanoid ignores those through
-- HipHeight; a server-owned rig has to classify them explicitly.
function Navigator:_isSteppable(part, footY)
	return isEntityGround(part)
		and partTopY(part) <= footY + self.Tuning.MaxStepHeight + .05
end

-- The body volume, as one number pair, so every caller measures the SAME box.
-- _clearAdvance, the route-centring pass and any test all read it from here;
-- a second literal copy is how a probe starts silently testing a different
-- creature from the one that walks.
function Navigator:_bodyVolume(): (Vector3, number)
	local height = math.max(2, self.Tuning.AgentHeight - .3)
	return Vector3.new(
		math.max(1, self.Tuning.AgentRadius * 2 - .2), height,
		math.max(1, self.Tuning.AgentRadius * 2 - .2)), height
end

-- HALF ONE of _clearAdvance: is the body volume clear AT a resolved foot.
--
-- Split out unchanged so the route-centring pass can ask the question without
-- the sweep, which needs a previous foot it does not have. _clearAdvance still
-- calls this and then the sweep, in that order, so nothing about the walking
-- contract moved -- this is a rename with a seam in it, not a relaxation.
function Navigator:_bodyBoxClear(targetFoot): boolean
	self:_refreshObstacleFilters()
	local size, height = self:_bodyVolume()
	local targetBox = CFrame.new(targetFoot + Vector3.new(0, height * .5 + .18, 0))
	for _, hit in ipairs(workspace:GetPartBoundsInBox(targetBox, size, self.OverlapParams)) do
		if hit.CanCollide and not self:_isSteppable(hit, targetFoot.Y) then
			self.LastBlockedBy = hit.Name
			return false
		end
	end
	self.LastBlockedBy = nil
	return true
end

-- HALF TWO: the horizontal sweep from `fromFoot` to `targetFoot`. Same box,
-- same step-height re-cast, same fail-closed budget as before.
function Navigator:_bodySweepClear(fromFoot, targetFoot): boolean
	self:_refreshObstacleFilters()
	local size, height = self:_bodyVolume()
	local displacement = Vector3.new(
		targetFoot.X - fromFoot.X, 0, targetFoot.Z - fromFoot.Z)
	if displacement.Magnitude <= .02 then
		self.LastBlockedBy = nil
		return true
	end
	local bottomY = math.max(fromFoot.Y, targetFoot.Y) + .18
	local origin = CFrame.new(fromFoot.X, bottomY + height * .5, fromFoot.Z)
	local sweepParams = self.RaycastParams
	local sweepFilter
	for _ = 1, SWEEP_EXCLUSION_BUDGET do
		local result = workspace:Blockcast(origin, size, displacement, sweepParams)
		if not result or result.Distance >= displacement.Magnitude - .03 then
			self.LastBlockedBy = nil
			return true
		end
		if not self:_isSteppable(result.Instance, targetFoot.Y) then
			self.LastBlockedBy = result.Instance.Name
			return false
		end
		if not sweepFilter then
			sweepFilter = self.RaycastParams.FilterDescendantsInstances
			sweepParams = RaycastParams.new()
			sweepParams.FilterType = Enum.RaycastFilterType.Exclude
			sweepParams.IgnoreWater = true
			sweepParams.RespectCanCollide = true
		end
		table.insert(sweepFilter, result.Instance)
		sweepParams.FilterDescendantsInstances = sweepFilter
	end
	-- The budget ran out with hits still unresolved. Nothing here has been
	-- shown to be passable, so refuse rather than assume.
	self.LastBlockedBy = "unresolved sweep after "
		.. SWEEP_EXCLUSION_BUDGET .. " step-height exclusions"
	return false
end

-- Certify an edge with the same floor/body semantics the live Step uses.
-- `_bodySweepClear` alone is not enough: it proves the horizontal volume at a
-- chosen pair of Y values, while `_placeFoot` resolves the highest reachable
-- authored floor at EVERY MaxTravelStep-sized piece.  Beside the seed-303
-- slide kit that distinction matters -- a cylinder route looked clear at the
-- pool floor, then the real step selected the stair pad and lifted the body
-- into its handrail.  The route pass called that segment walkable and every
-- replan handed the rig straight back to the same rail.
--
-- This helper is read-only. It walks a local `previous` foot through the exact
-- sampling contract without moving the model or mutating FootPosition. The
-- third return value is the number of high-level spatial predicates consumed,
-- so the caller can charge it to the existing finite/yielding route budget.
function Navigator:_walkingEdgeClear(fromFoot, targetFoot)
	local displacement = Vector3.new(
		targetFoot.X - fromFoot.X, 0, targetFoot.Z - fromFoot.Z)
	local distance = displacement.Magnitude
	if distance <= .02 then return true, fromFoot, 0 end
	local pieces = math.max(1, math.ceil(distance / self.Tuning.MaxTravelStep))
	local previous = fromFoot
	local queries = 0
	for index = 1, pieces do
		local alpha = index / pieces
		local x = fromFoot.X + displacement.X * alpha
		local z = fromFoot.Z + displacement.Z * alpha
		-- Step passes a horizontal candidate at the current foot height. Do the
		-- same here; using the authored waypoint Y would let a route preselect a
		-- floor the live walker has not climbed to yet.
		local probe = Vector3.new(x, previous.Y, z)
		local surfaceY = self:_surfaceAt(probe, false, previous.Y)
		queries += 1
		if surfaceY == nil then return false, previous, queries end
		local foot = Vector3.new(x, surfaceY + self.Tuning.FootClearance, z)
		queries += 1
		if not self:_bodyBoxClear(foot) then return false, previous, queries end
		queries += 1
		if not self:_bodySweepClear(previous, foot) then return false, previous, queries end
		previous = foot
	end
	return true, previous, queries
end

function Navigator:_clearAdvance(targetFoot)
	-- Unchanged in behaviour, and now expressed as its two halves so that the
	-- route-centring pass measures the SAME body against the SAME geometry. The
	-- destination box first, then the horizontal sweep -- in that order, because
	-- a destination that is already occupied should be refused before anything
	-- is swept toward it.
	--
	-- Validate the complete body volume at the resolved destination. The old
	-- test asked whether a hit's CENTRE was at or below the foot, which no riser
	-- ever satisfies: a .78-stud step is authored as a block reaching down to
	-- the slab, so its centre is .39 ABOVE the floor it is standing on.
	if not self:_bodyBoxClear(targetFoot) then return false end

	-- A destination-only test can miss a thin wall crossed on the way in, so the
	-- horizontal sweep stays as a second, independent check. A blockcast reports
	-- only its first hit, so step-height ledges are re-cast past rather than
	-- accepted blindly. It needs a previous foot, so it runs only once the rig
	-- has actually stood somewhere.
	if self.HasGrounded and not self:_bodySweepClear(self.FootPosition, targetFoot) then
		return false
	end
	self.LastBlockedBy = nil
	return true
end

-- Breadcrumbs for the retreat recovery. Only spaced-out positions are kept, so
-- the trail covers real ground rather than a frame's worth of jitter.
function Navigator:_recordTrail(foot)
	if self.TrailFrozen or not self.HasGrounded then return end
	local last = self.Trail[#self.Trail]
	if last and horizontalDistance(last, foot) < TRAIL_SPACING then return end
	table.insert(self.Trail, foot)
	while #self.Trail > TRAIL_LIMIT do table.remove(self.Trail, 1) end
end

function Navigator:_placeFoot(position, facing, allowLargeStep)
	if self.Destroyed or not (self.Model and self.Model.Parent) then return false end
	local surfaceY = self:_surfaceAt(position, allowLargeStep)
	if surfaceY == nil then
		self.Status = "NO_FLOOR"
		self.LastFailure = "no validated Level 2 floor"
		return false
	end
	local foot = Vector3.new(position.X, surfaceY + self.Tuning.FootClearance, position.Z)
	if not self:_clearAdvance(foot) then
		self.Status = "BLOCKED"
		self.LastFailure = "movement volume blocked"
		return false
	end
	local flatFacing = facing and Vector3.new(facing.X, 0, facing.Z) or self.Facing
	if flatFacing.Magnitude > 0.001 then self.Facing = flatFacing.Unit end
	local pivotPosition = foot + Vector3.new(0, self.PivotAboveFoot, 0)
	self.Model:PivotTo(CFrame.lookAt(pivotPosition, pivotPosition + self.Facing))
	self:_recordTrail(foot)
	self.FootPosition = foot
	self.HasGrounded = true
	self.LastSafeFoot = foot
	self.LastSafeFacing = self.Facing
	self.Status = "MOVING"
	self.LastFailure = nil
	return true
end

function Navigator:WarpTo(position, facing, allowLargeStep)
	if not finiteVector3(position) then return false end
	self:Stop()
	return self:_placeFoot(position, facing, allowLargeStep == true)
end

function Navigator:_clearDirectLine(fromPosition, toPosition)
	self:_refreshObstacleFilters()
	local height = math.clamp(self.PivotAboveFoot * 0.5, 1.5, 5)
	local origin = fromPosition + Vector3.new(0, height, 0)
	local target = Vector3.new(toPosition.X, origin.Y, toPosition.Z)
	local displacement = target - origin
	if displacement.Magnitude < 0.05 then return true end
	return workspace:Raycast(origin, displacement, self.RaycastParams) == nil
end

-- ---------------------------------------------------------------------------
-- Clearance-aware route centring
-- ---------------------------------------------------------------------------
--
-- WHAT SHIPPED BROKEN: the route and the body disagreed about what "fits".
--
-- PathfindingService plans for a CYLINDER of PathAgentRadius (8.25 at the
-- authored full scale). The body this navigator actually walks is a 16.3-stud
-- SQUARE box, whose corners reach about 11.53 studs from centre. So PFS may
-- legally route within 8.25 studs of a
-- column, an arch rib or a hall lintel, and the box then does not fit there.
-- The graph fallback is no better: it aims at hall centres and corridor
-- centres, which are fine, but it interpolates nothing in between and says
-- nothing about the doorway lintels at either end.
--
-- Measured on seed 101, over the four routes that were failing: of 180 route
-- points, 180 put the body volume inside collidable geometry. NONE of them had
-- to. Every one of the 180 had a clear standing position nearby -- 166 by
-- sliding sideways (143 of those within 5 studs) and the remaining 14 by a
-- short 2D search. Zero were unrescuable. The creature was not too big for the
-- level; it was being routed down the edge of it.
--
-- So this pass takes the route that was planned and moves each point to a
-- position the BODY can actually occupy, using the very predicate the walk
-- uses (_bodyBoxClear), then proves each surviving segment with the very sweep
-- the walk uses (_bodySweepClear) and subdivides any segment that fails.
--
-- What it deliberately does NOT do:
--   * it never moves the GOAL. The goal is a player or a node and moving it
--     would mean arriving somewhere else. A blocked goal gets a clear APPROACH
--     point inserted before it instead, and the goal stays last.
--   * it never invents a point the body cannot stand on -- every candidate it
--     accepts has passed _bodyBoxClear and _positionAllowed.
--   * it never widens, shrinks or bypasses the body test. If nothing near a
--     point is clear, the original point is kept and the walk fails there
--     exactly as it did before. This pass can only ever improve a route.
--
-- Cost is paid ONCE per path request, inside the request thread that already
-- yields on ComputeAsync -- never per Step. It is budgeted and it yields.
local CENTRING_LATERAL_STEP = 1
local CENTRING_MAX_LATERAL = 20
local CENTRING_RING_STEP = 2
local CENTRING_MAX_RING = 20
local CENTRING_RING_ANGLES = 18
-- Hard ceiling on spatial queries for one route.  The old 12,000 ceiling was
-- enough for ordinary corridors, but it cut the two longest seed-101 routes
-- off with one segment still unproved; the traversal suite then correctly
-- reported an empty-list stall while a replacement route was still computing.
-- A 72,000 ceiling also covers the floor-resolved edge certification used by
-- the route pass (one production-style floor/body sample is three predicates)
-- while keeping a finite cap. Work still yields every
-- CENTRING_YIELD_EVERY predicates and a
-- superseded request aborts between chunks, so this cannot monopolise a frame
-- or install an obsolete player target.
local CENTRING_QUERY_BUDGET = 72000
-- Predicates between yields, so a long route cannot hold the frame. A walking
-- sample charges its floor resolve, body box and sweep separately; 600 is at
-- most 200 such samples before the request yields and rechecks cancellation.
local CENTRING_YIELD_EVERY = 600
-- A segment longer than this is swept in pieces, so one blockcast cannot span
-- a whole corridor and miss a doorway.
local CENTRING_MAX_SEGMENT = 24
-- How many repair points one segment may take before it is left alone.
local CENTRING_MAX_INSERTS = 3
-- Minimum spacing kept between route points before centring, and the turn
-- (as a dot product) sharp enough that a point is kept regardless.
local CENTRING_MIN_SPACING = 9
local CENTRING_KEEP_TURN = .92

-- A blocked segment occasionally needs to go AROUND furniture instead of
-- merely moving its midpoint.  Seed 101's long routes expose the important
-- case: two tiled columns plus a lounger leave no body-wide passage on the
-- direct line, although there is a broad clear lane around their left side.
-- PathfindingService routes a cylinder through the narrow gap; repeatedly
-- centring that same line can never make the square body fit.
--
-- The detour search is deliberately local and bounded.  It explores a
-- clearance-tested lattice around only the failed segment, and every accepted
-- node and edge uses the same body predicates as Step. Sixty-four studs reaches
-- around the full Diving-Well slide cluster without turning this into a
-- second whole-map pathfinder.  The hard node cap and the shared centring query
-- budget keep a malformed world from monopolising the request thread.
local DETOUR_GRID_STEP = 8
local DETOUR_FINE_GRID_STEP = 4
local DETOUR_MARGIN = 64
local DETOUR_MAX_EXPANDED = 1800
local DETOUR_GOAL_PROBE_DISTANCE = 18
-- One early prop cluster may not consume the whole route's allowance and leave
-- later rooms unexamined. The scale-85 hall-11 aperture needs about 9,000
-- predicates across the coarse+fine searches; 18,000 covers it plus the wider
-- Diving-Well flank with headroom
-- and still reserves work for the next obstacle on a multi-room chase.
local DETOUR_QUERY_CAP = 18000
local DETOUR_NEIGHBOURS = {
	{1, 0}, {-1, 0}, {0, 1}, {0, -1},
	{1, 1}, {1, -1}, {-1, 1}, {-1, -1},
}

-- The corridor a point is inside, and the signed distance from its centre
-- line. `Cross` IS the centre line -- verified against the layout: hall 1's
-- centre Z equals corridor 1's Cross exactly. Used only as a SEED for the
-- search, never as an answer: the analytic centre is tried first because it is
-- free and usually right, and then it is proved with the same body test as
-- every other candidate.
-- How far BEYOND a corridor's own span its centre line still has to be held.
--
-- The vault overhangs the corridor proper by about 1.4 studs, and the body box
-- is 8.15 studs deep from its centre to its leading face -- so the box is
-- already under the arch about 9.6 studs before the foot reaches the corridor
-- mouth. A seed that only covered [From, To] left exactly the approach where
-- the box first meets a rib uncentred, which is the one place it must not be.
local CORRIDOR_APPROACH_REACH = 11

local function corridorCentreSeed(layout, position)
	for _, corridor in ipairs((layout and layout.Corridors) or {}) do
		local cross = tonumber(corridor.Cross)
		local from = tonumber(corridor.From)
		local to = tonumber(corridor.To)
		local width = tonumber(corridor.Width) or 34
		if cross and from and to then
			local lo = math.min(from, to) - CORRIDOR_APPROACH_REACH
			local hi = math.max(from, to) + CORRIDOR_APPROACH_REACH
			if corridor.Axis == "X" then
				if position.X >= lo and position.X <= hi
					and math.abs(position.Z - cross) <= width * .5 + 2 then
					return Vector3.new(position.X, position.Y, cross), corridor
				end
			elseif position.Z >= lo and position.Z <= hi
				and math.abs(position.X - cross) <= width * .5 + 2 then
				return Vector3.new(cross, position.Y, position.Z), corridor
			end
		end
	end
	return nil
end

-- The corridor a point is inside, or nil. Same test corridorCentreSeed uses.
local function corridorContaining(layout, position)
	for _, corridor in ipairs((layout and layout.Corridors) or {}) do
		local cross = tonumber(corridor.Cross)
		local from = tonumber(corridor.From)
		local to = tonumber(corridor.To)
		local width = tonumber(corridor.Width) or 34
		if cross and from and to then
			local lo, hi = math.min(from, to), math.max(from, to)
			if corridor.Axis == "X" then
				if position.X >= lo - 2 and position.X <= hi + 2
					and math.abs(position.Z - cross) <= width * .5 + 2 then
					return corridor
				end
			elseif position.Z >= lo - 2 and position.Z <= hi + 2
				and math.abs(position.X - cross) <= width * .5 + 2 then
				return corridor
			end
		end
	end
	return nil
end

-- The point on a corridor's centre line at whichever END is nearer `approach`.
-- Used to line the body up BEFORE it enters, so it does not cut the mouth
-- diagonally and clip an arch rib on the way in. Half a stud of lateral error
-- is enough to jam here, so entering square matters more than it sounds.
local function corridorEntryPoint(corridor, approach, y)
	local cross = tonumber(corridor.Cross)
	local from = tonumber(corridor.From)
	local to = tonumber(corridor.To)
	if not (cross and from and to) then return nil end
	local lo, hi = math.min(from, to), math.max(from, to)
	if corridor.Axis == "X" then
		local edge = math.abs(approach.X - lo) <= math.abs(approach.X - hi) and lo or hi
		return Vector3.new(edge, y, cross)
	end
	local edge = math.abs(approach.Z - lo) <= math.abs(approach.Z - hi) and lo or hi
	return Vector3.new(cross, y, edge)
end

-- Resolve the floor under an ARBITRARY position and ask whether the body fits
-- standing there. allowLargeStep is true because a candidate is not a step
-- from the current foot -- it is a place to route THROUGH, and the walk will
-- still have to climb to it one MaxStepHeight at a time.
function Navigator:_standableAt(position)
	local surfaceY = self:_surfaceAt(position, true)
	if surfaceY == nil then return false, nil end
	local foot = Vector3.new(position.X, surfaceY + self.Tuning.FootClearance, position.Z)
	if not self:_bodyBoxClear(foot) then return false, foot end
	return true, foot
end

-- The nearest position to `point` at which the body fits, searched outward so
-- the route is disturbed as little as possible. Returns nil when nothing
-- within the caps qualifies -- and nil means KEEP THE ORIGINAL, never "make
-- something up".
function Navigator:_centredWaypoint(point, along, budget)
	-- THE CORRIDOR CENTRE LINE IS TAKEN UNCONDITIONALLY, not merely when the
	-- planned point happens to fail the body test. This is the difference
	-- between "the route touches clear ground" and "the route is walkable",
	-- and the authored geometry says it has to be this way.
	--
	-- Every corridor is spanned by a barrel vault and by arch ribs, both struck
	-- about an arc centre 1 stud above the corridor floor. Clear half-width at
	-- a height y is sqrt(R^2 - (y - 1)^2). At authored full scale the body
	-- probe is 16.3 studs wide and 10.7 studs tall. The live centring suite
	-- derives the exact clearance from current tuning and generated geometry;
	-- it is deliberately not copied here as another stale constant.
	--
	-- The ribs repeat closely enough along a corridor that the 16.3-stud
	-- navigation box is nearly always overlapping one. That is still less than
	-- half a body radius of lateral freedom inside a corridor 34 studs wide, so
	-- the route must stay centred. The live centring suite derives these values
	-- from the current tuning and checks them against the generated geometry.
	--
	-- A point sitting at u = 1.5 therefore passes the body test where it stands
	-- and jams a few studs later at the next rib. Snapping it to u = 0 while it
	-- still looks fine is the whole point.
	local seed = corridorCentreSeed(self.Layout, point)
	if seed and horizontalDistance(seed, point) > .02 then
		if self:_positionAllowed(seed) then
			local seedOk, seedFoot = self:_standableAt(seed)
			budget.Used += 1
			if seedOk then
				return Vector3.new(seed.X, seedFoot.Y, seed.Z), seedFoot,
					horizontalDistance(seed, point)
			end
		end
	end

	local standable, foot = self:_standableAt(point)
	budget.Used += 1
	if standable then return point, foot, 0 end

	local direction = along
	if not (direction and direction.Magnitude > .05) then direction = Vector3.xAxis end
	direction = Vector3.new(direction.X, 0, direction.Z)
	if direction.Magnitude < .05 then direction = Vector3.xAxis end
	direction = direction.Unit
	local side = Vector3.new(-direction.Z, 0, direction.X)

	local function try(candidate)
		if budget.Used >= budget.Cap then return nil end
		if not self:_positionAllowed(candidate) then
			budget.Used += 1
			return nil
		end
		local ok, candidateFoot = self:_standableAt(candidate)
		budget.Used += 1
		if ok then return candidateFoot end
		return nil
	end

	-- Sideways, nearest first, alternating sides so neither is preferred.
	local shift = CENTRING_LATERAL_STEP
	while shift <= CENTRING_MAX_LATERAL do
		for _, sign in ipairs({1, -1}) do
			local candidate = point + side * (shift * sign)
			local candidateFoot = try(candidate)
			if candidateFoot then
				return Vector3.new(candidate.X, candidateFoot.Y, candidate.Z),
					candidateFoot, shift
			end
		end
		shift += CENTRING_LATERAL_STEP
		if budget.Used >= budget.Cap then return nil end
	end

	-- Still nothing: widen to a full ring, which also moves ALONG the route.
	-- This is what recovers an arch rib -- the aperture is ahead of or behind
	-- the planned point, not beside it.
	local radius = CENTRING_RING_STEP
	while radius <= CENTRING_MAX_RING do
		for step = 0, CENTRING_RING_ANGLES - 1 do
			local angle = (2 * math.pi / CENTRING_RING_ANGLES) * step
			local offset = (side * math.cos(angle) + direction * math.sin(angle)) * radius
			local candidate = point + offset
			local candidateFoot = try(candidate)
			if candidateFoot then
				return Vector3.new(candidate.X, candidateFoot.Y, candidate.Z),
					candidateFoot, radius
			end
		end
		radius += CENTRING_RING_STEP
		if budget.Used >= budget.Cap then return nil end
	end
	return nil
end

-- Find a body-clear route around one segment that the straight sweep cannot
-- traverse.  Returns INTERMEDIATE feet only; the final edge to `toFoot` has
-- already been proved clear when a result is returned.
function Navigator:_clearanceDetourAtStep(fromFoot, toFoot, budget, shouldAbort, step)
	if budget.Used >= budget.Cap then return nil, false end

	local minX = math.min(fromFoot.X, toFoot.X) - DETOUR_MARGIN
	local maxX = math.max(fromFoot.X, toFoot.X) + DETOUR_MARGIN
	local minZ = math.min(fromFoot.Z, toFoot.Z) - DETOUR_MARGIN
	local maxZ = math.max(fromFoot.Z, toFoot.Z) + DETOUR_MARGIN
	local minIX = math.floor((minX - fromFoot.X) / step)
	local maxIX = math.ceil((maxX - fromFoot.X) / step)
	local minIZ = math.floor((minZ - fromFoot.Z) / step)
	local maxIZ = math.ceil((maxZ - fromFoot.Z) / step)

	local function key(ix, iz)
		return tostring(ix) .. ":" .. tostring(iz)
	end
	local startKey = key(0, 0)
	local closed = {}
	local gScore = {[startKey] = 0}
	local parent = {}
	local feet = {[startKey] = fromFoot}
	local indices = {[startKey] = {0, 0}}
	local function heuristic(foot)
		return horizontalDistance(foot, toFoot)
	end

	-- Binary min-heap for the A* frontier. The previous implementation scanned
	-- every open node to find the lowest f-score on every expansion: O(n^2) over
	-- as many as 1,800 nodes, on top of the spatial queries themselves. Duplicate
	-- heap entries are intentional decrease-key records; pop discards an entry
	-- whose captured g-score is no longer current.
	local frontier = {}
	local frontierSerial = 0
	local function before(a, b)
		if a.F ~= b.F then return a.F < b.F end
		if a.H ~= b.H then return a.H < b.H end
		return a.Serial < b.Serial
	end
	local function pushFrontier(nodeKey, g, foot)
		frontierSerial += 1
		local h = heuristic(foot)
		local entry = {Key = nodeKey, G = g, H = h, F = g + h, Serial = frontierSerial}
		local index = #frontier + 1
		frontier[index] = entry
		while index > 1 do
			local parentIndex = math.floor(index * .5)
			if not before(entry, frontier[parentIndex]) then break end
			frontier[index] = frontier[parentIndex]
			index = parentIndex
		end
		frontier[index] = entry
	end
	local function popFrontier()
		while #frontier > 0 do
			local first = frontier[1]
			local last = table.remove(frontier)
			if #frontier > 0 then
				local index = 1
				while true do
					local left = index * 2
					if left > #frontier then break end
					local right = left + 1
					local child = right <= #frontier and before(frontier[right], frontier[left])
						and right or left
					if not before(frontier[child], last) then break end
					frontier[index] = frontier[child]
					index = child
				end
				frontier[index] = last
			end
			if not closed[first.Key] and gScore[first.Key] == first.G then
				return first.Key
			end
		end
		return nil
	end
	pushFrontier(startKey, 0, fromFoot)
	-- A lattice node's standing clearance is independent of which neighbour
	-- reached it, and a directed edge is independent of the A* score.  The old
	-- search repeated both expensive world queries every time an open node was
	-- reconsidered from another parent (up to eight times on a dense patch).
	-- Cache the proved result for this one bounded search.  Nothing survives the
	-- call, so a door or other dynamic obstacle can never inherit stale data on
	-- the next route request.
	local standableCache = {}
	local edgeCache = {}
	local yieldedAt = budget.Used

	local function account(count)
		budget.Used += count
		if budget.Used - yieldedAt >= CENTRING_YIELD_EVERY then
			yieldedAt = budget.Used
			task.wait()
			if shouldAbort and shouldAbort() then return false end
		end
		return budget.Used < budget.Cap
	end

	local function reconstruct(lastKey)
		local reversed = {}
		local cursor = lastKey
		while cursor and cursor ~= startKey do
			table.insert(reversed, feet[cursor])
			cursor = parent[cursor]
		end
		local result = {}
		for index = #reversed, 1, -1 do
			table.insert(result, reversed[index])
		end
		return result
	end

	local expanded = 0
	while #frontier > 0 and expanded < DETOUR_MAX_EXPANDED
		and budget.Used < budget.Cap do
		local currentKey = popFrontier()
		if currentKey == nil then break end
		closed[currentKey] = true
		expanded += 1

		local currentFoot = feet[currentKey]
		-- Far nodes do not need an expensive goal sweep yet.  Near nodes do, and
		-- a successful sweep is the certificate that completes the detour.
		if horizontalDistance(currentFoot, toFoot) <= DETOUR_GOAL_PROBE_DISTANCE then
			local reachesGoal, _, goalQueries = self:_walkingEdgeClear(currentFoot, toFoot)
			if not account(goalQueries) then
				return nil, shouldAbort and shouldAbort() == true
			end
			if reachesGoal then return reconstruct(currentKey), false end
		end

		local currentIndices = indices[currentKey]
		for _, offset in ipairs(DETOUR_NEIGHBOURS) do
			local ix = currentIndices[1] + offset[1]
			local iz = currentIndices[2] + offset[2]
			if ix >= minIX and ix <= maxIX and iz >= minIZ and iz <= maxIZ then
				local candidateKey = key(ix, iz)
				if not closed[candidateKey] then
					local raw = Vector3.new(
						fromFoot.X + ix * step,
						fromFoot.Y,
						fromFoot.Z + iz * step)
					-- A four-stud lattice can miss the half-stud channel under an
					-- arch.  Whenever a lattice point is in or approaching a
					-- corridor, use its authored centre line before testing it.
					local corridorSeed = corridorCentreSeed(self.Layout, raw)
					if corridorSeed then
						raw = Vector3.new(corridorSeed.X, raw.Y, corridorSeed.Z)
					end
					if self:_positionAllowed(raw) then
						local cachedStandable = standableCache[candidateKey]
						if cachedStandable == nil then
							local standable, candidateFoot = self:_standableAt(raw)
							cachedStandable = {Ok = standable, Foot = candidateFoot}
							standableCache[candidateKey] = cachedStandable
							if not account(1) then
								return nil, shouldAbort and shouldAbort() == true
							end
						end
						if cachedStandable.Ok then
							local candidateFoot = cachedStandable.Foot
							local edgeKey = currentKey .. ">" .. candidateKey
							local edgeResult = edgeCache[edgeKey]
							if edgeResult == nil then
								local edgeClear, resolvedFoot, edgeQueries =
									self:_walkingEdgeClear(currentFoot, candidateFoot)
								edgeResult = {Ok = edgeClear, Foot = resolvedFoot}
								edgeCache[edgeKey] = edgeResult
								if not account(edgeQueries) then
									return nil, shouldAbort and shouldAbort() == true
								end
							end
							if edgeResult.Ok then
								candidateFoot = edgeResult.Foot
								local tentative = (gScore[currentKey] or 0)
									+ horizontalDistance(currentFoot, candidateFoot)
								if tentative < (gScore[candidateKey] or math.huge) then
									gScore[candidateKey] = tentative
									parent[candidateKey] = currentKey
									feet[candidateKey] = candidateFoot
									indices[candidateKey] = {ix, iz}
									pushFrontier(candidateKey, tentative, candidateFoot)
								end
							end
						end
					end
			end
		end
	end
	end
	return nil, false
end

function Navigator:_clearanceDetour(fromFoot, toFoot, budget, shouldAbort)
	local routeCap = budget.Cap
	budget.Cap = math.min(routeCap, budget.Used + DETOUR_QUERY_CAP)
	local detour, aborted = self:_clearanceDetourAtStep(
		fromFoot, toFoot, budget, shouldAbort, DETOUR_GRID_STEP)
	if detour or aborted or budget.Used >= budget.Cap then
		budget.Cap = routeCap
		return detour, aborted
	end
	-- Eight studs keeps ordinary prop avoidance cheap.  A doorway or staggered
	-- furniture edge can sit between those samples, so only a failed segment is
	-- retried at four studs.  The expensive resolution is therefore exceptional,
	-- not the cost of every player-driven repath.
	detour, aborted = self:_clearanceDetourAtStep(
		fromFoot, toFoot, budget, shouldAbort, DETOUR_FINE_GRID_STEP)
	budget.Cap = routeCap
	return detour, aborted
end

-- Rewrite a planned route into one the body can walk. Returns the new point
-- list and a stats table; the caller installs the list exactly as before.
--
-- `shouldAbort` is asked between chunks so a superseded path request stops
-- paying for a route nobody will use.
function Navigator:_centreRoute(points, shouldAbort, startPosition)
	-- A request can yield while the incumbent keeps walking. All passes must
	-- certify from ONE origin; the finished plan is joined to the live foot.
	local routeOrigin = startPosition
	local stats = {
		Points = #points, Moved = 0, Kept = 0, Inserted = 0,
		Unresolved = 0, Queries = 0, WorstShift = 0, Aborted = false,
		Detours = 0, DetourAttempts = 0, DetourPoints = 0,
		-- Segments the body still cannot sweep through after every repair this
		-- pass knows how to make. A route with any of these is NOT walkable, and
		-- the caller uses that to choose a different route rather than sending
		-- the creature down this one to fail.
		Unwalkable = 0,
	}
	if #points == 0 then return points, stats end
	local budget = {Used = 0, Cap = CENTRING_QUERY_BUDGET}
	local lastYield = 0

	-- DECIMATE FIRST. PathfindingService emits a point every WaypointSpacing
	-- (5) studs; the full-scale body probe is 16.3 studs across. Validating every one of them
	-- costs three or four times what it needs to and buys nothing -- consecutive
	-- points 5 studs apart are the same body position twice over. Points closer
	-- together than CENTRING_MIN_SPACING are dropped, EXCEPT where the route
	-- turns by more than CENTRING_KEEP_TURN, which is exactly where the shape of
	-- the route matters. The first and last points are always kept, and pass 2
	-- then sweeps every surviving segment, so nothing is skipped unvalidated.
	if #points > 2 then
		local thinned = {}
		local anchor = routeOrigin or self.FootPosition
		for index = 1, #points do
			local point = points[index]
			local keep = index == #points
			if not keep then
				if horizontalDistance(point, anchor) >= CENTRING_MIN_SPACING then
					keep = true
				else
					local following = points[index + 1]
					if following then
						local a = Vector3.new(point.X - anchor.X, 0, point.Z - anchor.Z)
						local b = Vector3.new(following.X - point.X, 0, following.Z - point.Z)
						if a.Magnitude > .05 and b.Magnitude > .05
							and a.Unit:Dot(b.Unit) < CENTRING_KEEP_TURN then
							keep = true
						end
					end
				end
			end
			if keep then
				table.insert(thinned, point)
				anchor = point
			end
		end
		stats.Thinned = #points - #thinned
		points = thinned
	end

	local function maybeYield()
		if budget.Used - lastYield >= CENTRING_YIELD_EVERY then
			lastYield = budget.Used
			task.wait()
			return true
		end
		return false
	end

	-- Pass 1: every point except the goal is moved to somewhere the body fits.
	local centred = {}
	local centredFeet = {}
	local previous = routeOrigin or self.FootPosition
	local goalStandableForRoute = true
	for index = 1, #points do
		local point = points[index]
		if index == #points then
			-- The goal is never moved. If the body cannot stand on it, a clear
			-- APPROACH point goes in front of it and the goal stays last, so
			-- arrival still means "reached the target", not "reached near it".
			local standable = self:_standableAt(point)
			goalStandableForRoute = standable == true
			budget.Used += 1
			if not standable then
				local along = Vector3.new(point.X - previous.X, 0, point.Z - previous.Z)
				local approach = self:_centredWaypoint(point, along, budget)
				if approach and horizontalDistance(approach, point) > .05 then
					table.insert(centred, approach)
					stats.Inserted += 1
				end
			end
			table.insert(centred, point)
		else
			local nextPoint = points[index + 1]
			local along = Vector3.new(nextPoint.X - previous.X, 0, nextPoint.Z - previous.Z)

			-- Entering a corridor: put a point on its centre line AT THE MOUTH
			-- first, so the body arrives square instead of crossing the
			-- threshold on a diagonal. With a rib channel of about half a stud
			-- either side of centre, a diagonal entry is the difference between
			-- walking through and wedging in the opening.
			local corridor = corridorContaining(self.Layout, point)
			if corridor and corridorContaining(self.Layout, previous) == nil then
				local entry = corridorEntryPoint(corridor, previous, point.Y)
				if entry and horizontalDistance(entry, previous) > 1
					and self:_positionAllowed(entry) then
					local entryOk, entryFoot = self:_standableAt(entry)
					budget.Used += 1
					if entryOk then
						local entryPoint = Vector3.new(entry.X, entryFoot.Y, entry.Z)
						table.insert(centred, entryPoint)
						centredFeet[entryPoint] = entryFoot
						stats.Inserted += 1
						previous = entry
					end
				end
			end

			local moved, movedFoot, shift = self:_centredWaypoint(point, along, budget)
			if moved == nil then
				stats.Unresolved += 1
				table.insert(centred, point)
				previous = point
			else
				if shift and shift > 0 then
					stats.Moved += 1
					stats.WorstShift = math.max(stats.WorstShift, shift)
				else
					stats.Kept += 1
				end
				table.insert(centred, moved)
				centredFeet[moved] = movedFoot
				previous = moved
			end
		end
		if maybeYield() and shouldAbort and shouldAbort() then
			stats.Aborted = true
			stats.Queries = budget.Used
			return points, stats
		end
		if budget.Used >= budget.Cap then break end
	end
	-- The budget ran out part way: everything after the break is unexamined, so
	-- it is appended untouched rather than dropped. A shorter route would be a
	-- silent truncation.
	for index = #centred + 1, #points do table.insert(centred, points[index]) end

	-- Pass 2: prove every segment with the SAME sweep the walk uses, and repair
	-- the ones that fail. A pair of clear standing positions does not by itself
	-- mean the body can get from one to the other.
	local repaired = {}
	local cursorFoot = routeOrigin or self.FootPosition
	for index = 1, #centred do
		local point = centred[index]
		-- A generated navigation node can itself sit inside decoration (seed
		-- 303's hall-33 node is at the centre of a spiral stair). The raw goal
		-- remains last for DebugCentreRoute's inspection contract, but the live
		-- route stops at the body-certified approach immediately before it.
		if index == #centred and not goalStandableForRoute then
			stats.GoalFallback = cursorFoot
			table.insert(repaired, point)
			break
		end
		-- Pass 1 already resolved a foot for this point; re-resolving it here
		-- doubled the floor probing for no new information.
		local targetFoot = centredFeet[point] or point
		local span = horizontalDistance(cursorFoot, targetFoot)
		local inserts = 0
		local walkable = false
		local terminalGoalApproach = index == #centred - 1 and not goalStandableForRoute
		local segmentStart = cursorFoot
		local furthestReachable = cursorFoot
		while inserts < CENTRING_MAX_INSERTS and budget.Used < budget.Cap do
			local swept, resolvedTarget, edgeQueries =
				self:_walkingEdgeClear(cursorFoot, targetFoot)
			budget.Used += edgeQueries
			if resolvedTarget
				and horizontalDistance(segmentStart, resolvedTarget)
					> horizontalDistance(segmentStart, furthestReachable) then
				furthestReachable = resolvedTarget
			end
			if swept and resolvedTarget then targetFoot = resolvedTarget end
			if swept and span <= CENTRING_MAX_SEGMENT then walkable = true break end
			if swept then walkable = true end
			-- The authored goal itself is solid (for example seed 303's hall-33
			-- node inside a spiral stair). If its standable approach is not reachable
			-- on the direct production sweep, do not spend up to three 18k-query A*
			-- searches trying to walk around scenery merely to get closer to a point
			-- the body can never occupy. The sweep has already returned the furthest
			-- certified foot; the terminal fallback below installs that strict,
			-- reachable approach. Measured 31 -> 33: 56,188 queries / 8.45 s before,
			-- while a four-seed sweep timed out at 8 s with an empty waypoint list.
			if not swept and terminalGoalApproach then break end
			if swept and span > CENTRING_MAX_SEGMENT then
				-- Long but clear: still split it, so the walk gets an
				-- intermediate anchor rather than one unbroken commitment.
				local middle = cursorFoot:Lerp(targetFoot, .5)
				local centre = self:_centredWaypoint(middle,
					Vector3.new(targetFoot.X - cursorFoot.X, 0, targetFoot.Z - cursorFoot.Z),
					budget)
				if centre == nil then break end
				table.insert(repaired, centre)
				stats.Inserted += 1
				local _, midFoot = self:_standableAt(centre)
				budget.Used += 1
				cursorFoot = midFoot or centre
				span = horizontalDistance(cursorFoot, targetFoot)
				inserts += 1
			else
				-- A midpoint cannot repair a segment whose direct lane is
				-- physically narrower than the body (the column + lounger pocket
				-- on seed 101 is the production example).  Search a bounded local
				-- lattice for a route AROUND the cluster first.  Every returned
				-- node and edge has already passed the same body checks as Step.
				-- A successful midpoint changes the remaining segment, so a later
				-- iteration may legitimately need another bounded detour. The frontier
				-- is a binary heap now; repeated searches no longer pay the old O(n^2)
				-- open-set scan that pushed a valid seed-303 route past eight seconds.
				stats.DetourAttempts += 1
				local detour, aborted = self:_clearanceDetour(
					cursorFoot, targetFoot, budget, shouldAbort)
				if aborted then
					stats.Aborted = true
					stats.Queries = budget.Used
					return points, stats
				end
				if detour and #detour > 0 then
					for _, detourFoot in ipairs(detour) do
						table.insert(repaired, detourFoot)
					end
					stats.Detours += 1
					stats.DetourPoints += #detour
					stats.Inserted += #detour
					walkable = true
					break
				end

				-- Small seams still benefit from the old cheap midpoint repair,
				-- so retain it as the bounded fallback when no real detour exists.
				local middle = cursorFoot:Lerp(targetFoot, .5)
				local centre = self:_centredWaypoint(middle,
					Vector3.new(targetFoot.X - cursorFoot.X, 0, targetFoot.Z - cursorFoot.Z),
					budget)
				if centre == nil then break end
				table.insert(repaired, centre)
				stats.Inserted += 1
				local _, midFoot = self:_standableAt(centre)
				budget.Used += 1
				local middleClear, resolvedMiddle, middleQueries =
					self:_walkingEdgeClear(cursorFoot, midFoot or centre)
				budget.Used += middleQueries
				if not middleClear then
					table.remove(repaired, #repaired)
					stats.Inserted -= 1
					break
				end
				cursorFoot = resolvedMiddle or midFoot or centre
				span = horizontalDistance(cursorFoot, targetFoot)
				inserts += 1
			end
		end
		if not walkable and terminalGoalApproach then
			-- Pass 1's nearest standable goal candidate is not necessarily
			-- reachable (a point just inside a spiral stair is the production
			-- case). Keep the furthest body-certified point on that approach
			-- instead; the request installer removes the raw goal after it and
			-- applies the unchanged strict arrival tolerance to this point.
			if horizontalDistance(cursorFoot, furthestReachable) > .05 then
				table.insert(repaired, furthestReachable)
				stats.Inserted += 1
			end
			cursorFoot = furthestReachable
			stats.GoalFallback = cursorFoot
			stats.GoalApproachRejected = (stats.GoalApproachRejected or 0) + 1
		else
			if not walkable then stats.Unwalkable += 1 end
			table.insert(repaired, point)
			cursorFoot = targetFoot
		end
		if maybeYield() and shouldAbort and shouldAbort() then
			stats.Aborted = true
			stats.Queries = budget.Used
			return points, stats
		end
		if budget.Used >= budget.Cap then
			for rest = index + 1, #centred do table.insert(repaired, centred[rest]) end
			break
		end
	end

	stats.Queries = budget.Used
	stats.Result = #repaired
	return repaired, stats
end

-- Test surface. Runs the real pass over a caller-supplied point list against
-- the live world, so a suite can assert what centring did without having to
-- race a path request.
function Navigator:DebugCentreRoute(points)
	return self:_centreRoute(points, nil)
end

function Navigator:_fallbackWaypoints(goal, startPosition)
	local origin = startPosition or self.FootPosition
	local route = graphRoute(self.Layout, self.HallByIndex, self.AllowedHallIndices, origin, goal)
	if route and #route > 0 then return route, "GRAPH" end
	if self:_positionAllowed(goal) and self:_clearDirectLine(origin, goal) then
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

-- Drop the Path.Blocked binding AND the Path it belongs to, together, always.
-- Six separate sites used to clear only the connection. That was survivable
-- while nothing read the Path back, but a resume that rebinds from a recorded
-- BlockedPath would happily reattach to a route the navigator abandoned three
-- requests ago -- so the two fields are now cleared by one call that cannot
-- forget half the job.
function Navigator:_clearBlocked()
	if self.BlockedConnection then
		self.BlockedConnection:Disconnect()
		self.BlockedConnection = nil
	end
	self.BlockedPath = nil
end

-- The ONLY place a Path.Blocked connection is created. It used to be written
-- inline in the request thread, which is why a pause could RECORD
-- HadBlockedConnection and never act on it: the Path was a local in a spawned
-- closure and nothing outside that closure could ever bind to it again.
--
-- The handler guards on the request id CURRENT AT BIND TIME, captured here
-- rather than passed in. That is what makes a REBIND safe: a binding restored
-- (or replaced) under a newer id is judged against that newer id, so an older
-- request's Blocked signal can never wipe the plan a later request installed.
function Navigator:_bindBlocked(path)
	self:_clearBlocked()
	local requestId = self.RequestId
	self.BlockedPath = path
	self.BlockedConnection = path.Blocked:Connect(function(blockedIndex)
		if self.Destroyed or requestId ~= self.RequestId then return end
		if blockedIndex < self.WaypointIndex then return end

		-- `path` is the cylinder route returned by PathfindingService, but the
		-- installed route has since been centred, split and locally detoured for
		-- the real square body.  Its waypoint indices no longer correspond to the
		-- Path.Blocked indices.  Clearing the installed route from that mismatched
		-- number produced false replans whenever a soft prop invalidated the raw
		-- cylinder path, even though the body-certified detour was still clear.
		-- Treat the signal as a prompt to revalidate the route we are ACTUALLY
		-- walking.  A real obstruction on the current segment still clears it;
		-- future segments remain guarded by every `_placeFoot` and will be
		-- revalidated when they become current.
		local target = self.Waypoints[self.WaypointIndex]
		local targetOk, targetFoot
		if target then targetOk, targetFoot = self:_standableAt(target) end
		if targetOk and self:_bodySweepClear(self.FootPosition, targetFoot) then
			return
		end
		self.Waypoints = {}
		self.WaypointIndex = 1
		self.Status = "BLOCKED"
		self.LastFailure = "installed body route became blocked"
		self.LastPathAt = -math.huge
	end)
end

-- The single source of truth for "is a Blocked binding live right now".
-- GetFullDebugSnapshot reports it through this, so a caller and the snapshot can
-- never disagree about it.
function Navigator:HasBlockedConnection(): boolean
	return self.BlockedConnection ~= nil
end

function Navigator:_reachedGoal()
	if not self.Goal then return false end
	local target = self.Goal
	-- An approach belongs to the goal it was certified for, not to a player
	-- who has since walked away from that pump/column.
	local approachGoal = self.InstalledGoal or self.LastRequestedGoal
	if self.GoalApproach and approachGoal
		and horizontalDistance(self.Goal, approachGoal) <= self.Tuning.WaypointArrivalDistance
		and math.abs(self.Goal.Y-approachGoal.Y) < self.Tuning.MaxStepHeight then
		target = self.GoalApproach
	end
	return horizontalDistance(self.FootPosition, target) <= self.Tuning.WaypointArrivalDistance
		and math.abs(self.FootPosition.Y-target.Y) <= 7
end

local function fullyCertified(stats)
	return type(stats) == "table" and stats.Aborted == false
		and stats.Unwalkable == 0 and stats.Unresolved == 0
		and finiteNumber(stats.Queries) and stats.Queries < CENTRING_QUERY_BUDGET
end

function Navigator:_waitingForClearance()
	return self.Tuning.StableRoutes and self.BlockedGoalApproach ~= nil
		and self.InstalledGoal ~= nil and self.Goal ~= nil
		and horizontalDistance(self.Goal,self.InstalledGoal) < self.Tuning.RepathDistance
		and math.abs(self.Goal.Y-self.InstalledGoal.Y) < self.Tuning.MaxStepHeight
		and horizontalDistance(self.FootPosition,self.BlockedGoalApproach) <= self.Tuning.WaypointArrivalDistance
end

function Navigator:_probeBlockedClearance()
	if not self:_waitingForClearance() or self.Computing
		or os.clock() < self.NextClearanceProbeAt then return false end
	self.NextClearanceProbeAt = os.clock() + CLEARANCE_RECHECK_INTERVAL
	local from, target = self.BlockedProbeFrom, self.BlockedProbeTarget
	if not finiteVector3(from) or not finiteVector3(target)
		or horizontalDistance(from,target) > 256 then return false end
	-- These are the actual last-safe foot and obstructed endpoint recorded by
	-- the prefix walk. Probe the same floor/step/body contract without moving.
	if not self:_walkingEdgeClear(from,target) then return false end
	self.BlockedGoalApproach = nil
	self.BlockedProbeFrom = nil
	self.BlockedProbeTarget = nil
	self.NextClearanceProbeAt = 0
	self.LastPathAt = -math.huge
	return true
end

function Navigator:_stableNeedsPath(goal, force)
	local age = os.clock() - self.LastPathAt
	if self.Computing and age >= self.Tuning.PathRequestTimeout then
		-- A hung async calculation cannot own navigation forever. Late results
		-- are invalidated without deleting a route that is still being walked.
		self.RequestId += 1
		self.Computing = false
	end
	if self.Computing then return false end
	if force == true then return true end
	if self:_probeBlockedClearance() then return true end
	if age < self.Tuning.RepathInterval then return false end
	local moved = not self.LastRequestedGoal
		or horizontalDistance(goal, self.LastRequestedGoal) >= self.Tuning.RepathDistance
		or math.abs(goal.Y - self.LastRequestedGoal.Y) >= self.Tuning.MaxStepHeight
	return moved or (not self.Waypoints[self.WaypointIndex]
		and not self:_reachedGoal() and not self:_waitingForClearance())
end

-- Some authored vault ribs are lower than the unchanged 16-stud giant.
-- Follow only the independently certified prefix to that opening, then wait
-- for a reachable target instead of repeatedly running into it or clipping.
function Navigator:_reachablePrefix(points, origin, goal, deadline)
	local prefix, foot, queries = {}, origin, 0
	local blocked = false
	local blockedFrom, blockedTarget
	for index = 1, math.min(#points,16) do
		if os.clock() >= deadline or queries >= 4096 then break end
		local point = points[index]
		local span = horizontalDistance(foot,point)
		if span > 256 then break end
		local clear, reached, used = self:_walkingEdgeClear(foot,point)
		queries += used or 0
		if reached and horizontalDistance(foot,reached) > .05 then
			table.insert(prefix,reached)
			foot = reached
		end
		if not clear then
			blocked, blockedFrom, blockedTarget = true, foot, point
			break
		end
	end
	if blocked and #prefix > 0 and horizontalDistance(origin,foot) >= 2
		and horizontalDistance(foot,goal) < horizontalDistance(origin,goal)-1 then
		return prefix, foot, blockedFrom, blockedTarget
	end
	if blocked and self:_bodyBoxClear(origin) then
		-- Already at the last safe standing position. Waiting here must not
		-- become another zero-length route/recovery loop.
		return {origin}, origin, blockedFrom, blockedTarget
	end
	return nil
end

-- Centring can add several individually safe detours whose combined polyline
-- doubles back on itself. String-pull that certified route before installing
-- it: remove a bend only when the entire replacement edge satisfies the same
-- floor, step and full-body checks as walking. Necessary wall detours survive.
-- The original certified suffix remains usable if the extra work budget ends.
function Navigator:_smoothStableRoute(points, origin, deadline)
	local result, from, first, queries = {}, origin, 1, 0
	while first <= #points do
		if queries >= 8192 or os.clock() >= deadline then
			for rest=first,#points do table.insert(result,points[rest]) end
			break
		end
		local chosen = first
		for index=math.min(#points,first+15),first+1,-1 do
			if queries >= 8192 or os.clock() >= deadline then break end
			if horizontalDistance(from,points[index]) <= 128 then
				local clear, reached, used = self:_walkingEdgeClear(from,points[index])
				queries += used or 0
				if clear and reached and math.abs(reached.Y-points[index].Y) <= self.Tuning.MaxStepHeight then
					chosen = index
					break
				end
			end
		end
		table.insert(result,points[chosen])
		from, first = points[chosen], chosen+1
	end
	return result
end

-- Splice a new certified route to where the entity is NOW. Prefer the furthest
-- reachable prefix point, so graph routes do not send it back to a hall hub it
-- already passed. Every shortcut uses the full floor/step/body contract, never
-- line of sight alone. Bounds keep this non-yielding commit small and atomic.
function Navigator:_joinStableRoute(points, requestStart)
	local from = self.FootPosition
	local segmentStart, nearestPoint = requestStart, requestStart
	local nearestIndex, minimum = 1, math.huge
	-- Find current progress on the polyline even after a long async delay.
	-- Scanning only the first N points can still choose a point already behind.
	for index, point in ipairs(points) do
		local edge = Vector3.new(point.X-segmentStart.X, 0, point.Z-segmentStart.Z)
		local offset = Vector3.new(from.X-segmentStart.X, 0, from.Z-segmentStart.Z)
		local alpha = edge.Magnitude > .001 and math.clamp(offset:Dot(edge)/edge:Dot(edge),0,1) or 1
		local projected = segmentStart:Lerp(point, alpha)
		local separation = horizontalDistance(from, projected)
		if separation <= minimum + .001 then
			minimum, nearestIndex, nearestPoint = separation, index, projected
		end
		segmentStart = point
	end
	for index = math.min(#points, nearestIndex + 15), nearestIndex, -1 do
		local candidate = points[index]
		if horizontalDistance(from, candidate) <= 128 then
			local clear = self:_walkingEdgeClear(from, candidate)
			if clear then
				local joined = {}
				for rest = index, #points do table.insert(joined, points[rest]) end
				return joined, index - 1
			end
		end
	end
	-- A long certified segment may end outside the join budget. Join a short
	-- distance ahead of its projection instead of rewinding to its old start.
	local endpoint = points[nearestIndex]
	if endpoint then
		local span = horizontalDistance(nearestPoint, endpoint)
		local ahead = span > .001 and nearestPoint:Lerp(endpoint, math.min(1,12/span)) or endpoint
		if horizontalDistance(from,ahead) <= 128 and self:_walkingEdgeClear(from,ahead) then
			local joined = {ahead}
			for rest=nearestIndex,#points do table.insert(joined,points[rest]) end
			return joined, nearestIndex-1
		end
	end
	return nil, 0
end

function Navigator:_rejectStableRoute(reason)
	self.RouteRejectedCount += 1
	self.LastFailure = reason
	self.Computing = false
	local nextPoint = self.Waypoints[self.WaypointIndex]
	-- Keep a healthy incumbent or a certified arrival. An invalid replacement
	-- must not erase useful progress or send the rig onto an unverified route.
	if (nextPoint and self:_walkingEdgeClear(self.FootPosition, nextPoint))
		or self:_reachedGoal() then return end
	self.Waypoints = {}
	self.WaypointIndex = 1
	self.GoalApproach = nil
	self.Status = "NO_PATH"
end

function Navigator:_requestPath(goal, graphOnly)
	self.RequestId += 1
	local requestId = self.RequestId
	local stable = self.Tuning.StableRoutes
	local requestStart = self.FootPosition
	local previousBlockedPath = self.BlockedPath
	self:_clearBlocked()
	self.Computing = true
	self.LastPathAt = os.clock()
	self.LastRequestedGoal = goal
	local deadline = self.LastPathAt + self.Tuning.PathRequestTimeout

	task.spawn(function()
		local path
		local success = false
		local failure
		if graphOnly then
			failure = "forced generated-hall graph route"
		else
			success, failure = pcall(function()
				path = PathfindingService:CreatePath({
					AgentRadius = self.Tuning.PathAgentRadius,
					AgentHeight = self.Tuning.AgentHeight,
					AgentCanJump = false,
					AgentCanClimb = false,
					WaypointSpacing = self.Tuning.WaypointSpacing,
					Costs = {Water = 1, Level2Roof = math.huge},
				})
				path:ComputeAsync(stable and requestStart or self.FootPosition, goal)
			end)
		end
		if self.Destroyed or requestId ~= self.RequestId then return end

		local points = {}
		local status = "PATH_FAILED"
		if success and path and path.Status == Enum.PathStatus.Success then
			for _, waypoint in ipairs(path:GetWaypoints()) do
				if horizontalDistance(waypoint.Position, stable and requestStart or self.FootPosition) > self.Tuning.WaypointArrivalDistance then
					table.insert(points, waypoint.Position)
				end
			end
			if #points == 0 or horizontalDistance(points[#points], goal) > 2 then table.insert(points, goal) end
			if self:_pathPointsAllowed(points) then
				status = "PATH"
			else
				points, status = self:_fallbackWaypoints(goal, stable and requestStart or nil)
				failure = "path left allowed halls"
			end
		else
			points, status = self:_fallbackWaypoints(goal, stable and requestStart or nil)
		end

		if self.Destroyed or requestId ~= self.RequestId then return end

		-- CLEARANCE-AWARE CENTRING. This is the one place a route is installed,
		-- from either source, so it is the one place the route has to be made
		-- walkable by the actual body. PathfindingService planned for a cylinder
		-- of PathAgentRadius; the graph fallback planned for nothing at all. See
		-- _centreRoute for the measurement that motivated it.
		--
		-- Runs HERE, in the request thread, after ComputeAsync has already
		-- yielded -- never on a Step. It is budgeted, it yields, and it aborts
		-- the moment a newer request supersedes this one.
		local proposedApproach
		local blockedApproach
		local blockedProbeFrom, blockedProbeTarget
		if #points > 0 then
			local shouldAbort = function()
				return self.Destroyed or requestId ~= self.RequestId
					or (stable and os.clock() >= deadline)
			end
			local centred, centringStats = self:_centreRoute(points, shouldAbort, stable and requestStart or nil)
			if self.Destroyed or requestId ~= self.RequestId then return end
			if stable and type(centringStats) ~= "table" then
				self:_rejectStableRoute("route certification missing")
				return
			end
			self.LastCentring = centringStats
			if not centringStats.Aborted then points = centred end

			-- IF THE PLANNED ROUTE STILL CANNOT BE WALKED, TAKE A DIFFERENT ONE.
			--
			-- PathfindingService plans for a cylinder of PathAgentRadius; the
			-- body is a square box whose corners reach about 11.53 studs at the
			-- authored full scale. Between a
			-- tiled column and a lounger there are gaps that admit the cylinder
			-- and refuse the box, and no amount of moving waypoints sideways
			-- helps -- the whole passage is too narrow, so the route has to go
			-- another way.
			--
			-- Measured on seed 101, node 1 to node 32: 520 frames of near-perfect
			-- progress, then a tiled column, then the rig backed out along its
			-- trail five times, re-planned each time, and was handed the same
			-- impassable route back every time. Retreating cannot fix a route
			-- that is wrong.
			--
			-- The room graph does not have this problem: it routes hall centre
			-- to corridor centre to hall centre, all of which this pass has just
			-- proved the body can occupy. So when the computed route has any
			-- segment the body cannot sweep through, the graph route is centred
			-- too and whichever is actually walkable wins. Ties go to the
			-- computed route, which is the better-shaped one.
			if (stable and not fullyCertified(centringStats) and not graphOnly
				and status ~= "GRAPH" and not shouldAbort())
				or (not stable and centringStats.Unwalkable and centringStats.Unwalkable > 0
					and not centringStats.Aborted) then
				local graphPoints, graphStatus = self:_fallbackWaypoints(goal, stable and requestStart or nil)
				if #graphPoints > 0 then
					local graphCentred, graphStats = self:_centreRoute(graphPoints, shouldAbort, stable and requestStart or nil)
					if self.Destroyed or requestId ~= self.RequestId then return end
					if (stable and fullyCertified(graphStats))
						or (not stable and not graphStats.Aborted
							and graphStats.Unwalkable < centringStats.Unwalkable) then
						points = graphCentred
						status = graphStatus
						self.LastCentring = graphStats
						path = nil
					end
				end
			end

			-- AN UNOCCUPIABLE GOAL IS NOT AN UNREACHED ONE.
			--
			-- WHAT SHIPPED BROKEN: arrival was `the foot is within
			-- WaypointArrivalDistance (2.25) of the goal`. This body's full-scale
			-- navigation probe is 16.3
			-- studs across, so that asks its CENTRE to sit almost exactly on the
			-- goal point -- and a third of this level's navigation anchors are
			-- points no body can occupy. Measured on seed 101: 12 of 38 nodes
			-- have a Tiled Column, a Pump Plinth, a Lounger or a slide floor
			-- standing on them, with the nearest room 1 to 20 studs away.
			--
			-- Asked to walk to the middle of a column, the creature got as close
			-- as it could, failed the last placement, threw the route away,
			-- re-planned, and did it again: measured at 20 repaths in 900 frames
			-- while sitting 5 studs from its goal. That is the "circling" the
			-- owner reported, and no amount of route centring fixes it, because
			-- the destination itself is inside a solid object.
			--
			-- So when the goal cannot be stood on, the LAST point of the centred
			-- route -- which the centring pass has already proved standable and
			-- placed adjacent to the goal -- becomes what arrival is measured
			-- against. The tolerance is NOT loosened: it is still 2.25 studs, of
			-- a place the body can actually be. A goal that IS occupiable is
			-- unaffected, and this can never let the rig stop early, because the
			-- stand-in is by construction the closest standable point the pass
			-- could find to the goal.
			if not stable then self.GoalApproach = nil end
			local goalStandable = self:_standableAt(goal)
			if not goalStandable then
				local approachIndex
				for index = #points - 1, 1, -1 do
					local candidate = points[index]
					if self:_standableAt(candidate) then
						proposedApproach = candidate
						if not stable then self.GoalApproach = candidate end
						approachIndex = index
						break
					end
				end
				-- DebugCentreRoute keeps the authored goal last so its contract can
				-- be inspected.  The INSTALLED walk must stop at the stand-in,
				-- however: leaving the known-unoccupiable goal after it made Step
				-- walk straight into the column and never reach the no-waypoint
				-- arrival check that reads GoalApproach.
				if approachIndex then
					for index = #points, approachIndex + 1, -1 do
						table.remove(points, index)
					end
				end
			end
		end

		if stable then
			local latestGoal = self.Goal
			local plannedDirection = Vector3.new(goal.X-self.FootPosition.X,0,goal.Z-self.FootPosition.Z)
			local latestDirection = latestGoal and Vector3.new(latestGoal.X-self.FootPosition.X,0,latestGoal.Z-self.FootPosition.Z)
			if latestDirection and horizontalDistance(goal,latestGoal) >= self.Tuning.RepathDistance
				and (plannedDirection:Dot(latestDirection) < 0
					or horizontalDistance(goal,latestGoal) > math.max(24,latestDirection.Magnitude*.5)) then
				-- Do not install an obsolete chase in the opposite direction. Small
				-- target movement is handled by the normal throttled next request.
				self.Waypoints = {}
				self.GoalApproach = nil
				self:_rejectStableRoute("target changed direction during planning")
				return
			end
			local stats = self.LastCentring
			local valid = #points > 0 and fullyCertified(stats) and os.clock() < deadline
			-- A partial candidate never displaces a healthy incumbent. Only build
			-- one when there is no route left, and validate every step anew.
			if not valid and #points > 0 and not self.Waypoints[self.WaypointIndex]
				and type(stats) == "table" and stats.Aborted == false
				and stats.Unwalkable and stats.Unwalkable > 0
				and os.clock() < deadline then
				local prefix, endpoint, probeFrom, probeTarget =
					self:_reachablePrefix(points,requestStart,goal,deadline)
				if prefix then
					points, blockedApproach, proposedApproach = prefix, endpoint, nil
					blockedProbeFrom, blockedProbeTarget = probeFrom, probeTarget
					status, valid = "PARTIAL", true
				end
			end
			local joined, skipped
			if valid then
				if not blockedApproach then points = self:_smoothStableRoute(points,requestStart,deadline) end
				joined, skipped = self:_joinStableRoute(points, requestStart)
			end
			if not joined then
				self:_rejectStableRoute(valid and "new route cannot join current foot safely"
					or "replacement route incomplete, blocked, or timed out")
				if previousBlockedPath and self.Waypoints[self.WaypointIndex] then
					self:_bindBlocked(previousBlockedPath)
				end
				return
			end
			points = joined
			self.GoalApproach = proposedApproach
			self.InstalledGoal = goal
			self.BlockedGoalApproach = blockedApproach
			self.BlockedProbeFrom = blockedProbeFrom
			self.BlockedProbeTarget = blockedProbeTarget
			self.NextClearanceProbeAt = blockedApproach
				and os.clock() + CLEARANCE_RECHECK_INTERVAL or 0
			self.RouteInstallCount += 1
			self.RoutePrefixSkips += skipped
		end
		self.Waypoints = points
		self.WaypointIndex = 1
		-- A fresh route gets fresh allowances. Carrying a spent skip budget into
		-- a new plan would make the second route give up sooner than the first.
		self.ClearanceSeeks = 0
		self.WaypointSkips = 0
		self.RouteFailures = 0
		self.Status = status
		self.LastFailure = status == "NO_PATH" and tostring(failure or "no route") or nil
		if status == "PATH" and path then
			self:_bindBlocked(path)
		end
		self.Computing = false
	end)
end

function Navigator:SetGraphGoal(goal, force)
	if self.Destroyed or not finiteVector3(goal) or not self:_positionAllowed(goal) then return false end
	self.Goal = goal
	if self.Tuning.StableRoutes and force ~= true then
		if self:_stableNeedsPath(goal, false) then self:_requestPath(goal, true) end
		return true
	end
	if force == true and self.Computing then
		self.RequestId += 1
		self.Computing = false
		if not self.Tuning.StableRoutes then
			self.Waypoints = {}
			self.WaypointIndex = 1
		end
		self:_clearBlocked()
	end
	local now = os.clock()
	local moved = not self.LastRequestedGoal
		or horizontalDistance(goal, self.LastRequestedGoal) >= self.Tuning.RepathDistance
	local stale = now - self.LastPathAt >= self.Tuning.RepathInterval
	if not self.Computing and (force == true or moved or stale or #self.Waypoints == 0) then
		-- The old recovery path installed raw room-centre waypoints synchronously,
		-- bypassing the body-clearance centring and goal-approach contract used by
		-- every normal route. Force the graph as the route SOURCE, but send it
		-- through the same asynchronous, budgeted installer as PathfindingService.
		self:_requestPath(goal, true)
	end
	return true
end

function Navigator:SetGoal(goal, force)
	if self.Destroyed or not finiteVector3(goal) or not self:_positionAllowed(goal) then return false end
	self.Goal = goal
	if self.Tuning.StableRoutes and force ~= true then
		if self:_stableNeedsPath(goal, false) then self:_requestPath(goal) end
		return true
	end
	if force == true and self.Computing then
		-- Invalidate the in-flight request so a watchdog retry is a real retry,
		-- not a no-op that advances the controller's recovery stage.
		self.RequestId += 1
		self.Computing = false
		if not self.Tuning.StableRoutes then
			self.Waypoints = {}
			self.WaypointIndex = 1
		end
		self:_clearBlocked()
	end
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
	self.Trail = {}
	self.Status = "IDLE"
	self.RequestId += 1
	self.Computing = false
	self.ClearanceSeeks = 0
	self.WaypointSkips = 0
	self.RouteFailures = 0
	self.RouteRetreats = 0
	self.BestGoalDistance = math.huge
	self.GoalApproach = nil
	self:_clearBlocked()
	self.InstalledGoal = nil
	self.BlockedGoalApproach = nil
	self.BlockedProbeFrom = nil
	self.BlockedProbeTarget = nil
	self.NextClearanceProbeAt = 0
end

-- Where to sidestep when the straight stride and the progress-guarded steer
-- ladder have both failed. Returns a candidate foot position, or nil.
--
-- It prefers the authored corridor CENTRE LINE when there is one, because that
-- is where a barrel-vaulted corridor is tallest and it is a stable target that
-- does not depend on which way the rig happens to be facing. Otherwise it takes
-- the clear sidestep that loses the least ground.
--
-- Every candidate is a FULL _placeFoot at the call site, so this can only ever
-- propose somewhere a normal step could legally have gone. It never proposes a
-- candidate that moves AWAY from the waypoint by more than
-- CLEARANCE_SEEK_TOLERANCE, so progress is bounded-monotonic rather than free.
local CLEARANCE_SEEK_TOLERANCE = 1.25

function Navigator:_clearanceSeekTarget(from, waypoint, direction, pieceLength)
	local side = Vector3.new(-direction.Z, 0, direction.X)
	local baseDistance = horizontalDistance(from, waypoint)

	-- The authored centre line first, when the rig is inside a corridor.
	local centre = corridorCentreSeed(self.Layout, from)
	local candidates = {}
	if centre then
		local toCentre = Vector3.new(centre.X - from.X, 0, centre.Z - from.Z)
		if toCentre.Magnitude > .1 then
			table.insert(candidates, from + toCentre.Unit * math.min(pieceLength,
				toCentre.Magnitude))
		end
	end
	-- Then pure sidesteps, nearest first, both ways.
	for _, sign in ipairs({1, -1}) do
		table.insert(candidates, from + side * (pieceLength * sign))
	end
	-- And a shallow diagonal, so a rig in a doorway can ease across rather than
	-- having to move purely sideways in a space that is barely wider than it is.
	for _, sign in ipairs({1, -1}) do
		table.insert(candidates,
			from + (side * sign + direction).Unit * pieceLength)
	end

	local best, bestDistance
	for _, candidate in ipairs(candidates) do
		local distance = horizontalDistance(candidate, waypoint)
		if distance <= baseDistance + CLEARANCE_SEEK_TOLERANCE then
			local surfaceY = self:_surfaceAt(candidate, false)
			if surfaceY ~= nil then
				local foot = Vector3.new(candidate.X,
					surfaceY + self.Tuning.FootClearance, candidate.Z)
				if self:_bodyBoxClear(foot) and self:_bodySweepClear(from, foot) then
					if bestDistance == nil or distance < bestDistance then
						best, bestDistance = candidate, distance
					end
				end
			end
		end
	end
	return best
end

function Navigator:Step(deltaTime, speed)
	if self.Destroyed or not (self.Model and self.Model.Parent) then return false end
	deltaTime = finiteNumber(deltaTime) and math.clamp(deltaTime, 0, 0.25) or 0
	speed = finiteNumber(speed) and math.max(0, speed) or 0
	local waypoint = self.Waypoints[self.WaypointIndex]
	while waypoint do
		local difference = Vector3.new(
			waypoint.X - self.FootPosition.X, 0, waypoint.Z - self.FootPosition.Z)
		if difference.Magnitude > self.Tuning.WaypointArrivalDistance then break end
		self.WaypointIndex += 1
		waypoint = self.Waypoints[self.WaypointIndex]
	end
	if not waypoint then
		-- GoalApproach is the standable stand-in for a goal the body cannot
		-- occupy; it is nil whenever the goal itself can be stood on, which is
		-- the ordinary case. Same tolerance either way.
		local arrivalTarget = self.GoalApproach or self.Goal
		local reached = self.Tuning.StableRoutes and self:_reachedGoal()
			or (not self.Tuning.StableRoutes and self.Goal ~= nil
				and horizontalDistance(self.FootPosition, arrivalTarget) <= self.Tuning.WaypointArrivalDistance)
		if self:_waitingForClearance() and not self:_probeBlockedClearance() then
			self.Status = "WAITING_FOR_CLEARANCE"
			return false
		end
		if self.Tuning.StableRoutes and reached then self.Status = "ARRIVED" end
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
	if speed <= 0 or deltaTime <= 0 then return false end
	local direction = difference.Unit
	local travel = math.min(distance, speed * deltaTime)

	-- WHAT SHIPPED BROKEN: this was ONE _placeFoot to `current + direction *
	-- travel`. _placeFoot validates a POINT -- _surfaceAt resolves the floor
	-- under it and _clearAdvance tests the body volume there -- so a stride only
	-- ever proved something about where it LANDED. Everything crossed on the way
	-- was assumed. At 36 studs/s and the controller's .1s frame that assumed 3.6
	-- studs at a time, against authored features of 1.2 / 1.4 / 0.8 studs and
	-- 0.70-0.80 curbs. Both ends of such a stride sit on the low slab, so the
	-- riser between them never appeared in any query and the rig glided over
	-- edges it should have had to climb -- or jammed against ones it had already
	-- passed the near face of.
	--
	-- _clearAdvance's horizontal Blockcast is NOT a substitute: it sweeps a box
	-- whose bottom is at max(startY, endY) + .18, so a 0.8-stud step between two
	-- equal-height slabs passes under it, and its whole purpose is walls, not
	-- floor discontinuities. Only re-running _surfaceAt at intermediate points
	-- can see a floor that changed mid-stride.
	--
	-- So the stride is now walked in pieces no longer than MaxTravelStep, and
	-- EVERY piece is the same full _placeFoot the single step used -- same floor
	-- resolve, same body volume test, same MaxStepHeight ceiling. Nothing is
	-- teleported and nothing is skipped: the loop only ever moves the foot to a
	-- position that passed exactly the checks one step passed before, just more
	-- often. The final piece lands on the identical endpoint the old single call
	-- aimed at, so waypoint arrival, goal distance and repath timing are
	-- untouched.
	local substeps = math.max(1, math.ceil(travel / self.Tuning.MaxTravelStep))
	if substeps > MAX_TRAVEL_SUBSTEPS then
		-- FAIL CLOSED. deltaTime is already clamped to .25 above and live speed
		-- tops out at 36, so no legal pair reaches this; if something absurd
		-- does, cover only what the cap can validate and leave the rest for the
		-- next call. The alternative -- widening the piece to fit -- is the very
		-- unvalidated leap this rewrite exists to remove.
		substeps = MAX_TRAVEL_SUBSTEPS
		travel = MAX_TRAVEL_SUBSTEPS * self.Tuning.MaxTravelStep
		self.TravelClamped = true
	else
		self.TravelClamped = false
	end
	local pieceLength = travel / substeps

	for _ = 1, substeps do
		local from = self.FootPosition
		if self:_placeFoot(from + direction * pieceLength, direction) then
			-- A straight stride landed: this is real progress, so the sidestep
			-- and skip allowances are handed back. They are spent only between
			-- two such moments, which is what bounds them.
			self.ClearanceSeeks = 0
			self.RouteFailures = 0
			-- The RETREAT allowance is refilled on a stricter test: the rig has
			-- to be nearer its goal than it has ever been. Walking about is not
			-- progress; closing on the target is.
			if self.Goal then
				local distance = horizontalDistance(self.FootPosition, self.Goal)
				if distance < self.BestGoalDistance - 1 then
					self.BestGoalDistance = distance
					self.RouteRetreats = 0
				end
			end
		else
			-- Tightly bounded small-step recovery: same heading, shorter stride,
			-- once. A full stride can land in the seam between two floor slabs and
			-- report NO_FLOOR where a shorter one is still supported. It is never
			-- longer than the stride already attempted, so it can neither skip
			-- geometry nor act as a teleport.
			--
			-- Unchanged in shape, only rescoped: it now shortens the failed PIECE
			-- rather than the whole stride, which keeps it strictly shorter than
			-- the placement that just failed. Either way the stride ends here --
			-- whatever rejected the piece is still in front of the rig, so
			-- continuing the loop would only re-attempt into the same geometry.
			-- STEER before surrendering the stride.
			--
			-- WHAT SHIPPED BROKEN: the only recovery was one shorter step on the
			-- SAME heading. Anything the rig could not walk through -- a lounger,
			-- a pump plinth, a vault strip, a column skirt -- ended the stride,
			-- and the next frame re-attempted the identical heading into the
			-- identical obstacle. Measured on a real generated world: 353 of 400
			-- steps BLOCKED against one prop, and zero traversals ever reaching a
			-- goal on any of four seeds. That is the "shuffles at an edge and
			-- gives up" the owner reported.
			--
			-- The ladder is authored (SteerAngles, 20/35/50 degrees) and was inert.
			-- Each candidate is a FULL _placeFoot -- same floor resolve, same body
			-- volume, same step ceiling -- so steering can only reach somewhere a
			-- straight step could legally have gone. Bounded: at most two probes
			-- per rung, tried nearest-first, and the stride still ends the moment
			-- none of them fits.
			-- A sidestep is only allowed if it is PROGRESS.
			--
			-- The first cut of this accepted any steered placement that fit, and
			-- that is strictly worse than being blocked: a rig against a wall
			-- found +20 degrees walkable every single frame, reported MOVING, and
			-- wandered along the wall forever. Measured: 600 moving steps, zero
			-- blocks, and it finished exactly as far from its goal as it started.
			-- Requiring each candidate to close the distance to the CURRENT
			-- WAYPOINT makes progress monotonic -- the rig either gets there or
			-- runs out of angles and is honestly blocked, and it can never orbit.
			local steered = false
			local baseDistance = horizontalDistance(from, waypoint)
			-- THE LADDER IS A LATERAL-DRIFT GENERATOR, and inside a corridor
			-- that is fatal. Its only gate is "this candidate closes the
			-- distance to the waypoint". Against a waypoint 40 studs away a
			-- 50-degree steered piece of .9 studs moves the body .69 studs
			-- SIDEWAYS and still closes the distance by .58, so the gate is
			-- satisfied over and over. Fifteen of them put the body 10 studs off
			-- the centre line -- which is exactly where the jams were measured:
			-- rib soffit 9.97 studs above the foot, vault soffits 8.09 and 8.16.
			--
			-- So inside a corridor (and its approach), a steered candidate may
			-- not increase the distance to the centre line. It can still steer
			-- -- toward the middle, or straight along it -- it simply cannot
			-- drift outward. In open halls the gate is unchanged.
			local centreNow = corridorCentreSeed(self.Layout, from)
			local lateralNow = centreNow and horizontalDistance(from, centreNow) or nil
			for _, degrees in ipairs(self.Tuning.SteerAngles) do
				local radians = math.rad(degrees)
				for _, sign in ipairs({1, -1}) do
					local turned = CFrame.Angles(0, radians * sign, 0):VectorToWorldSpace(direction)
					local candidate = from + turned * pieceLength
					local driftOk = true
					if lateralNow then
						local centreThere = corridorCentreSeed(self.Layout, candidate)
						if centreThere then
							driftOk = horizontalDistance(candidate, centreThere)
								<= lateralNow + .02
						end
					end
					if driftOk
						and horizontalDistance(candidate, waypoint) < baseDistance - .05
						and self:_placeFoot(candidate, turned)
					then
						steered = true
						break
					end
				end
				if steered then break end
			end
			if steered then
				-- The route still describes where the rig is going; it is only the
				-- approach that bent. Forcing a repath here instead made the rig
				-- rebuild its path on every single avoided prop, which thrashed
				-- PathfindingService and lost the route it was already following.
				return false
			end
			if self:_placeFoot(from + direction * (pieceLength * .45), direction) then
				return false
			end

			-- CLEARANCE SEEK. The steer ladder above only accepts a sidestep
			-- that CLOSES the distance to the waypoint, which is what stops the
			-- rig orbiting a wall. But a corridor's clear channel for this body
			-- is narrow -- measured at +/-2 studs either side of the centre line
			-- on seed 101, inside a 34-stud corridor -- so a rig that has
			-- drifted to the edge needs to move SIDEWAYS to the middle, and
			-- that briefly costs distance. Refusing it is what left the creature
			-- shuffling at a vault springing with clear floor two studs away.
			--
			-- So a bounded number of distance-LOSING sidesteps is allowed, and
			-- only toward more clearance. The budget refills only when a real
			-- progressing step succeeds, so a rig that can only ever sidestep
			-- runs out and is honestly blocked. It cannot orbit: at most
			-- MAX_CLEARANCE_SEEKS of them may happen between two steps that
			-- actually make progress.
			if self.ClearanceSeeks < MAX_CLEARANCE_SEEKS then
				local seekTarget = self:_clearanceSeekTarget(from, waypoint, direction,
					pieceLength)
				if seekTarget and self:_placeFoot(seekTarget, direction) then
					self.ClearanceSeeks += 1
					return false
				end
			end

			-- The current waypoint cannot be reached from here. Before throwing
			-- the whole route away, see whether the NEXT one can be: a single
			-- unreachable point in a long route is not a reason to re-plan the
			-- other four hundred.
			--
			-- WHAT SHIPPED BROKEN: one failed placement did
			-- `self.Waypoints = {}` and forced an immediate repath. On a route
			-- of 427 points that discarded the entire plan on the first awkward
			-- stride, recomputed it, got the same plan back, and failed at the
			-- same place -- a loop that spent its whole time computing and
			-- almost none of it walking. Measured: the rig covered 127 of 2174
			-- studs and then stalled with an EMPTY waypoint list, which reads as
			-- "blocked by geometry" and is nothing of the sort.
			local skipped = self.Waypoints[self.WaypointIndex + 1]
			if skipped and self.WaypointSkips < MAX_WAYPOINT_SKIPS then
				local surfaceY = self:_surfaceAt(skipped, false)
				if surfaceY ~= nil then
					local skipFoot = Vector3.new(skipped.X,
						surfaceY + self.Tuning.FootClearance, skipped.Z)
					if self:_bodyBoxClear(skipFoot)
						and self:_bodySweepClear(from, skipFoot) then
						self.WaypointIndex += 1
						self.WaypointSkips += 1
						return false
					end
				end
			end

			-- Nothing worked this frame. The route is abandoned only after
			-- several consecutive frames like this, so a transient block costs a
			-- few frames instead of a full re-plan.
			self.RouteFailures += 1
			if self.RouteFailures >= ROUTE_ABANDON_FAILURES then
				self.RouteFailures = 0
				-- BACK OUT BEFORE RE-PLANNING.
				--
				-- WHAT SHIPPED BROKEN: a rig that walked into a pocket it could
				-- not leave forwards threw its route away, asked for a new one
				-- FROM THE SAME SPOT, got a route with the same first move, and
				-- failed again. Measured on seed 101 walking node 1 to node 32:
				-- 520 frames of near-perfect progress (1129 studs at 2.17 of a
				-- possible 2.4 per frame), then a Tiled Column and a lounger,
				-- then 36 re-plans and 69% of the remaining frames standing
				-- still, with the goal distance frozen at 726 studs. Every
				-- recovery Step had -- the steer ladder, the shorter stride, the
				-- clearance seek, the waypoint skip -- requires moving FORWARD,
				-- and forward was solid.
				--
				-- Retreat is the one recovery that goes the other way, and it
				-- was reachable only from the controller, never from Step. It
				-- walks back along positions the rig has ALREADY STOOD ON, one
				-- validated placement at a time, so it cannot cross a wall, gain
				-- height it did not climb or jump a gap -- and it re-plans from
				-- there, where there is room.
				--
				-- Bounded by progress, not by a timer: the allowance is refilled
				-- only when the rig gets meaningfully CLOSER to its goal than it
				-- has ever been on this goal. A rig that backs out, tries again
				-- and ends up no nearer runs out and is honestly stuck, so this
				-- cannot become a shuffle.
				if self.RouteRetreats < MAX_ROUTE_RETREATS and #self.Trail > 0 then
					self.RouteRetreats += 1
					-- Retreat happens inside this Step call, so its total movement is
					-- part of the same frame budget as forward travel.  The previous
					-- 16-stud request could move 11+ studs in one Step despite a
					-- 2.4-stud stride contract.  Back out progressively instead; the
					-- controller's slower recovery-stage Retreat remains a separate
					-- explicitly bounded action.
					if self:Retreat(math.min(ROUTE_RETREAT_STUDS, travel)) > 0 then
						return false
					end
				end
				self.Waypoints = {}
				self.WaypointIndex = 1
				self.LastPathAt = -math.huge
			end
			return false
		end
	end
	return false
end

-- Bounded, route-aware unstick. It walks BACK along positions the rig has
-- already stood on, one validated step at a time -- every step runs the same
-- floor and body checks as forward motion, so it cannot cross a wall, gain
-- height it did not climb, or jump a gap. It is a walk, not a teleport: the
-- distance is capped and the rig stops the instant a step fails.
function Navigator:Retreat(maxDistance)
	if self.Destroyed or not (self.Model and self.Model.Parent) then return 0 end
	maxDistance = finiteNumber(maxDistance) and math.clamp(maxDistance, 0, 48) or 0
	if maxDistance <= 0 or #self.Trail == 0 then return 0 end
	self.TrailFrozen = true
	local travelled = 0
	while travelled < maxDistance and #self.Trail > 0 do
		local target = table.remove(self.Trail)
		local step = horizontalDistance(self.FootPosition, target)
		if step > .05 then
			if travelled + step > maxDistance then break end
			local direction = Vector3.new(
				target.X - self.FootPosition.X, 0, target.Z - self.FootPosition.Z)
			if not self:_placeFoot(target, direction) then break end
			travelled += step
		end
	end
	self.TrailFrozen = false
	if travelled > 0 then
		-- The route that led here is the one that failed; force a fresh plan.
		self.Waypoints = {}
		self.WaypointIndex = 1
		self.LastPathAt = -math.huge
	end
	return travelled
end

function Navigator:GetTrailLength()
	return #self.Trail
end

function Navigator:GetPosition()
	return self.FootPosition
end

function Navigator:GetFacing()
	return self.Facing
end

function Navigator:GetGoal()
	return self.Goal
end

function Navigator:Face(position)
	if finiteVector3(position) then
		self:_placeFoot(self.FootPosition, position - self.FootPosition)
	end
end

function Navigator:GetStatus()
	return self.Status
end

-- ---------------------------------------------------------------------------
-- Pause / resume: borrowing a live navigator without corrupting it
-- ---------------------------------------------------------------------------
--
-- A test that wants the world to itself has to be able to put a running
-- creature down and pick it up again. Disconnecting the controller's heartbeat
-- is not enough: a ComputeAsync started before the pause lands DURING it, writes
-- fresh Waypoints and a fresh Status over the plan the incumbent had, and
-- installs a Blocked connection that outlives the borrow. The incumbent then
-- resumes onto a route it never asked for.
--
-- Pause invalidates in-flight work the same way a forced SetGoal already does --
-- by bumping RequestId, which every one of the three guards in the request
-- thread and the Blocked handler tests -- and keeps the OLD id dead forever by
-- never restoring it. Timing is stored as an AGE, not an absolute clock reading,
-- so a navigator that had just repathed still has just repathed on resume.

local NAVIGATOR_PAUSE_FIELDS = {
	"Waypoints", "WaypointIndex", "Goal", "LastRequestedGoal", "Status",
	"LastFailure", "LastBlockedBy", "Facing", "FootPosition", "HasGrounded",
	"LastSafeFoot", "LastSafeFacing", "TrailFrozen", "PivotAboveFoot", "Trail",
}

function Navigator:IsPaused(): boolean
	return self.Paused == true
end

-- The FIELD half of a pause record, and nothing else: no RequestId bump, no
-- disconnect, no Paused flag. A probe that only wants to be able to put the
-- navigator back the way it found it -- the controller's pause-test arming does
-- -- must not invalidate the very in-flight request it is arming.
--
-- Pause builds its own record through this, so the two can never drift: a name
-- added to NAVIGATOR_PAUSE_FIELDS is captured by both or by neither. While they
-- were two hand-written loops, a field added to one was silently missing from
-- the other and a restore quietly left it holding the borrower's value.
function Navigator:Snapshot()
	local record = {Fields = {}}
	for _, name in ipairs(NAVIGATOR_PAUSE_FIELDS) do
		local value = self[name]
		-- Copy, never alias: the incumbent keeps using these tables while the
		-- borrower runs, and a shared reference would restore whatever the
		-- borrower left behind.
		record.Fields[name] = typeof(value) == "table" and table.clone(value) or value
	end
	-- LastPathAt is captured ABSOLUTE here. Pause additionally stores it as an
	-- AGE, because a pause spans real time and a reading that survives one has
	-- to be re-based; a snapshot goes back onto the same clock it came off.
	record.LastPathAt = self.LastPathAt
	record.Computing = self.Computing == true
	return record
end

-- The exact inverse of Snapshot, with the same absence of side effects: it does
-- not stop, pause, disconnect or invalidate anything. NOTE that a request the
-- caller left in flight is therefore STILL in flight and can land after this
-- returns, overwriting Waypoints/Status/LastFailure with its own result. A
-- caller that needs a quiescent navigator has to Pause/Resume it instead.
function Navigator:Restore(record): (boolean, string?)
	if self.Destroyed then return false, "navigator destroyed" end
	if type(record) ~= "table" or type(record.Fields) ~= "table" then
		return false, "not a navigator snapshot"
	end
	if record.LastPathAt ~= nil
		and not (type(record.LastPathAt) == "number" and record.LastPathAt == record.LastPathAt)
	then
		return false, "snapshot LastPathAt is not a number"
	end
	for _, name in ipairs(NAVIGATOR_PAUSE_FIELDS) do
		local value = record.Fields[name]
		self[name] = typeof(value) == "table" and table.clone(value) or value
	end
	if record.LastPathAt ~= nil then self.LastPathAt = record.LastPathAt end
	if record.Computing ~= nil then self.Computing = record.Computing == true end
	return true
end

function Navigator:Pause()
	if self.Destroyed then return nil end
	local record = self:Snapshot()
	record.Paused = true
	record.HadBlockedConnection = self.BlockedConnection ~= nil
	-- The Path itself, not merely the fact that there was one. Recording only
	-- the boolean is why HadBlockedConnection sat unread for its whole life:
	-- there was nothing a resume could have rebound to.
	record.BlockedPath = self.BlockedPath
	record.WasComputing = self.Computing == true
	record.LastPathAge = (self.LastPathAt == -math.huge) and -math.huge
		or (os.clock() - self.LastPathAt)

	-- Kill anything in flight. The bumped id is deliberately NOT restored.
	self.RequestId += 1
	self.Computing = false
	self:_clearBlocked()
	self.Paused = true
	return record
end

-- What a resume owes the two flags Pause records. Both were written and neither
-- was ever read, so a resumed navigator came back with no Blocked binding and a
-- Computing flag forced to false while a request it still believed in had been
-- killed by the pause -- silently, with nothing saying so.
--
-- HadBlockedConnection: the pause disconnected the binding, so it is REBUILT
-- here from the recorded Path. The rebind is pcall'ed because the Path is an
-- ordinary object the borrower may have dropped or destroyed; a resume must not
-- fail over a route hint.
--
-- WasComputing: the pause bumped RequestId, so the computation that was in
-- flight can NEVER commit -- all three guards in the request thread and the one
-- in the Blocked handler test that id. The navigator therefore does not get to
-- pretend the request is still live. It either RESTARTS it (there is a goal to
-- ask for again) or SETTLES it explicitly (there is not): Computing goes false,
-- LastFailure says why, and LastPathAt becomes the module's "repath
-- immediately" sentinel so the next Step re-plans instead of waiting out a
-- RepathInterval measured from a request that no longer exists.
--
-- Order matters. The restart happens AFTER self.Paused = false, and
-- _requestPath clears the Blocked binding at its head -- so a restored binding
-- is DELIBERATELY superseded by the new request's own binding. BlockedRestored
-- reports what this call restored, not what survived the restart.
function Navigator:Resume(record, resumedAt: number?): (boolean, string?, {[string]: boolean}?)
	if self.Destroyed then return false, "navigator destroyed" end
	if type(record) ~= "table" or type(record.Fields) ~= "table" then
		return false, "not a pause record"
	end
	-- Validated BEFORE a single field is written. `now - record.LastPathAge`
	-- used to be evaluated on whatever the caller handed over, so a record
	-- missing LastPathAge threw "attempt to perform arithmetic on a nil value"
	-- with every field already restored -- a half-resumed navigator plus an
	-- error string, instead of a clean refusal that changed nothing.
	local age = record.LastPathAge
	if not (type(age) == "number" and age == age) then
		return false, "pause record has an invalid LastPathAge"
	end

	local restored, restoreError = self:Restore(record)
	if not restored then return false, restoreError end

	local now = tonumber(resumedAt) or os.clock()
	self.LastPathAt = (age == -math.huge) and -math.huge or (now - age)

	local outcome = {BlockedRestored = false, RequestRestarted = false, RequestSettled = false}
	if record.HadBlockedConnection and record.BlockedPath then
		local bound = pcall(function() self:_bindBlocked(record.BlockedPath) end)
		if bound and self.BlockedConnection then
			outcome.BlockedRestored = true
		else
			-- A half-built binding is worse than none: clear whatever the failed
			-- attempt left behind so HasBlockedConnection stays truthful.
			self:_clearBlocked()
		end
	end

	self.Paused = false

	if record.WasComputing then
		if finiteVector3(self.LastRequestedGoal) then
			self:_requestPath(self.LastRequestedGoal)
			outcome.RequestRestarted = true
		else
			self.Computing = false
			self.LastFailure = "the in-flight path request was invalidated by a pause"
			self.LastPathAt = -math.huge
			outcome.RequestSettled = true
		end
	else
		self.Computing = false
	end

	return true, nil, outcome
end

-- The whole comparable surface, for a test that has to prove an incumbent came
-- back unchanged. GetDebugSnapshot below reports COUNTS, which cannot tell a
-- restored trail from a different trail of the same length.
function Navigator:GetFullDebugSnapshot()
	local snapshot = {
		Status = self.Status,
		Computing = self.Computing,
		Paused = self.Paused == true,
		RequestId = self.RequestId,
		WaypointIndex = self.WaypointIndex,
		Goal = self.Goal,
		LastRequestedGoal = self.LastRequestedGoal,
		FootPosition = self.FootPosition,
		Facing = self.Facing,
		LastFailure = self.LastFailure,
		LastBlockedBy = self.LastBlockedBy,
		HasGrounded = self.HasGrounded,
		LastSafeFoot = self.LastSafeFoot,
		LastSafeFacing = self.LastSafeFacing,
		TrailFrozen = self.TrailFrozen,
		PivotAboveFoot = self.PivotAboveFoot,
		HasBlockedConnection = self:HasBlockedConnection(),
		Waypoints = table.clone(self.Waypoints or {}),
		Trail = table.clone(self.Trail or {}),
	}
	return snapshot
end

function Navigator:GetDebugSnapshot()
	return {
		Status = self.Status,
		Computing = self.Computing,
		-- The controller watchdog uses this to distinguish a bounded, yielding
		-- route installation from a creature that has stopped making progress.
		-- LastPathAt is written at the start of every current request.
		RequestStartedAt = self.LastPathAt,
		RequestId = self.RequestId,
		Reached = self:_reachedGoal(),
		WaitingForClearance = self:_waitingForClearance(),
		RouteInstalls = self.RouteInstallCount,
		RejectedRoutes = self.RouteRejectedCount,
		PrefixSkips = self.RoutePrefixSkips,
		NextWaypoint = self.Waypoints[self.WaypointIndex],
		WaypointIndex = self.WaypointIndex,
		WaypointCount = #self.Waypoints,
		Goal = self.Goal,
		Position = self.FootPosition,
		LastFailure = self.LastFailure,
		LastBlockedBy = self.LastBlockedBy,
		TrailLength = #self.Trail,
		TravelClamped = self.TravelClamped == true,
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
	self.OverlapParams = nil
	self.BaseExclusions = nil
	self.FloorRaycastParams = nil
end

return Navigator
