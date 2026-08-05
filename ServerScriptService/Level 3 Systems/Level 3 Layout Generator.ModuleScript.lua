-- Level 3 Layout Generator
-- Seeded procedural plan for the Sunken Leisure Complex.
--
-- This is NOT the Level 2 approach. Level 2 is a uniform grid of same-sized
-- cells carved by a DFS maze walk, so every room is identical in footprint and
-- rooms share walls directly with no corridors.
--
-- Level 3 uses recursive binary space partitioning over one large region:
--   * leaves become HALLS of genuinely different sizes (a slide hall can be
--     four times the floor area of a side gallery),
--   * halls are joined by explicit L-shaped CORRIDORS, which is where the
--     arched flooded tunnels live,
--   * the BSP merge order guarantees connectivity without a maze walk, and a
--     second pass adds loops so the complex reads as a building.
--
-- Roles it places: arrival, three pump stations, a contiguous kids block,
-- three slide halls (the largest of which holds the exit flume on its top
-- deck), and an entity den.

local Configuration = require(script.Parent:WaitForChild("Level 3 Configuration"))

local LayoutGenerator = {}

local function rectCenter(rect)
	return Vector3.new((rect.MinX + rect.MaxX) * .5, 0, (rect.MinZ + rect.MaxZ) * .5)
end

local function rectWidth(rect) return rect.MaxX - rect.MinX end
local function rectDepth(rect) return rect.MaxZ - rect.MinZ end

-- ── binary space partition ──────────────────────────────────────────────────

local function split(rng, rect, depth, leaves)
	local width, depth3 = rectWidth(rect), rectDepth(rect)
	local minLeaf = Configuration.MinimumLeafSize
	local canSplitX = width >= minLeaf * 2 + Configuration.HallMargin
	local canSplitZ = depth3 >= minLeaf * 2 + Configuration.HallMargin

	local mustStop = depth >= Configuration.MaximumSplitDepth or (not canSplitX and not canSplitZ)
	-- Stop early sometimes so the plan keeps a few genuinely huge rooms.
	if not mustStop and depth >= Configuration.MinimumSplitDepth
		and rng:NextNumber() < Configuration.EarlyStopChance then
		mustStop = true
	end
	if mustStop then
		table.insert(leaves, rect)
		return
	end

	local horizontal
	if canSplitX and canSplitZ then
		-- Prefer cutting the long axis so halls stay reasonably proportioned.
		if width > depth3 * 1.25 then horizontal = true
		elseif depth3 > width * 1.25 then horizontal = false
		else horizontal = rng:NextNumber() < .5 end
	else
		horizontal = canSplitX
	end

	if horizontal then
		local low = rect.MinX + minLeaf
		local high = rect.MaxX - minLeaf
		local cut = rng:NextNumber(low, high)
		split(rng, {MinX = rect.MinX, MaxX = cut, MinZ = rect.MinZ, MaxZ = rect.MaxZ}, depth + 1, leaves)
		split(rng, {MinX = cut, MaxX = rect.MaxX, MinZ = rect.MinZ, MaxZ = rect.MaxZ}, depth + 1, leaves)
	else
		local low = rect.MinZ + minLeaf
		local high = rect.MaxZ - minLeaf
		local cut = rng:NextNumber(low, high)
		split(rng, {MinX = rect.MinX, MaxX = rect.MaxX, MinZ = rect.MinZ, MaxZ = cut}, depth + 1, leaves)
		split(rng, {MinX = rect.MinX, MaxX = rect.MaxX, MinZ = cut, MaxZ = rect.MaxZ}, depth + 1, leaves)
	end
end

-- ── hall graph ──────────────────────────────────────────────────────────────

local function hallsOverlapOnAxis(a, b, axis)
	if axis == "X" then
		local low = math.max(a.MinX, b.MinX)
		local high = math.min(a.MaxX, b.MaxX)
		return high - low
	end
	local low = math.max(a.MinZ, b.MinZ)
	local high = math.min(a.MaxZ, b.MaxZ)
	return high - low
end

local function gapBetween(a, b)
	-- Straight-line gap if the halls face each other, otherwise nil.
	if hallsOverlapOnAxis(a, b, "X") >= Configuration.CorridorWidth + 8 then
		if a.MaxZ <= b.MinZ then return "Z", b.MinZ - a.MaxZ end
		if b.MaxZ <= a.MinZ then return "Z", a.MinZ - b.MaxZ end
	end
	if hallsOverlapOnAxis(a, b, "Z") >= Configuration.CorridorWidth + 8 then
		if a.MaxX <= b.MinX then return "X", b.MinX - a.MaxX end
		if b.MaxX <= a.MinX then return "X", a.MinX - b.MaxX end
	end
	return nil
end

local function connect(layout, a, b, kind)
	if a == b then return nil end
	local pairKey = math.min(a.Index, b.Index) .. ":" .. math.max(a.Index, b.Index)
	if layout.CorridorByPair[pairKey] then return layout.CorridorByPair[pairKey] end

	local axis, distance = gapBetween(a, b)
	if not axis then return nil end

	local corridor = {
		Index = #layout.Corridors + 1,
		Id = string.format("Level 3 Corridor %02d", #layout.Corridors + 1),
		A = a.Index,
		B = b.Index,
		Axis = axis,
		Length = distance,
		Width = Configuration.CorridorWidth,
		Kind = kind or "Open",
		PoolType = "Shallow",
	}

	-- Corridor runs along the shared overlap, centred on it.
	if axis == "X" then
		local low = math.max(a.MinZ, b.MinZ)
		local high = math.min(a.MaxZ, b.MaxZ)
		corridor.Cross = (low + high) * .5
		corridor.From = math.min(a.MaxX, b.MaxX)
		corridor.To = math.max(a.MinX, b.MinX)
	else
		local low = math.max(a.MinX, b.MinX)
		local high = math.min(a.MaxX, b.MaxX)
		corridor.Cross = (low + high) * .5
		corridor.From = math.min(a.MaxZ, b.MaxZ)
		corridor.To = math.max(a.MinZ, b.MinZ)
	end

	table.insert(layout.Corridors, corridor)
	layout.CorridorByPair[pairKey] = corridor
	table.insert(a.Connections, b.Index)
	table.insert(b.Connections, a.Index)
	return corridor
end

local function bfs(layout, startHall, blockedCorridors)
	local distances = {[startHall.Index] = 0}
	local queue = {startHall}
	local head = 1
	while head <= #queue do
		local hall = queue[head]
		head += 1
		for _, otherIndex in ipairs(hall.Connections) do
			local pairKey = math.min(hall.Index, otherIndex) .. ":" .. math.max(hall.Index, otherIndex)
			local corridor = layout.CorridorByPair[pairKey]
			local blocked = blockedCorridors and corridor and blockedCorridors[corridor.Index]
			if not blocked and distances[otherIndex] == nil then
				distances[otherIndex] = distances[hall.Index] + 1
				table.insert(queue, layout.Halls[otherIndex])
			end
		end
	end
	return distances
end

local function shuffled(rng, source)
	local result = table.clone(source)
	for index = #result, 2, -1 do
		local swap = rng:NextInteger(1, index)
		result[index], result[swap] = result[swap], result[index]
	end
	return result
end

local function area(hall)
	return rectWidth(hall) * rectDepth(hall)
end

local function separation(a, b)
	local ac, bc = rectCenter(a), rectCenter(b)
	return (ac - bc).Magnitude
end

local function chooseSpread(candidates, count, minimumDistance)
	local chosen = {}
	for _, candidate in ipairs(candidates) do
		local ok = true
		for _, existing in ipairs(chosen) do
			if separation(candidate, existing) < minimumDistance then ok = false break end
		end
		if ok then
			table.insert(chosen, candidate)
			if #chosen == count then break end
		end
	end
	return chosen
end

-- Grow a connected run of halls, used for the kids play area so its rooms
-- genuinely sit next to each other.
local function growBlock(layout, seed, count, blocked)
	local block = {seed}
	local inBlock = {[seed.Index] = true}
	local frontier = {seed}
	while #block < count and #frontier > 0 do
		local hall = table.remove(frontier, 1)
		for _, otherIndex in ipairs(hall.Connections) do
			if #block >= count then break end
			local other = layout.Halls[otherIndex]
			if not inBlock[other.Index] and not blocked[other] then
				inBlock[other.Index] = true
				table.insert(block, other)
				table.insert(frontier, other)
			end
		end
	end
	if #block < count then return nil end
	return block
end

-- ── generation ──────────────────────────────────────────────────────────────

local function generateAttempt(seed)
	local rng = Random.new(seed)
	local extent = Configuration.ComplexExtent
	-- The plan is laid out in world coordinates around WorldCenter, which is
	-- shifted away from the persistent tunnel lobby so the two never overlap.
	local cx = Configuration.WorldCenterX or 0
	local cz = Configuration.WorldCenterZ or 0
	local layout = {
		Seed = seed,
		Version = Configuration.Version,
		Bounds = {
			MinX = cx - extent * .5, MaxX = cx + extent * .5,
			MinZ = cz - extent * .5, MaxZ = cz + extent * .5,
		},
		Halls = {},
		Corridors = {},
		CorridorByPair = {},
	}

	local leaves = {}
	split(rng, layout.Bounds, 0, leaves)
	if #leaves < Configuration.MinimumHallCount then return nil, "too few halls" end

	-- Inset each leaf to become a hall, leaving the margin for corridors.
	for index, leaf in ipairs(leaves) do
		local margin = Configuration.HallMargin
		local jitter = Configuration.HallInsetJitter
		local hall = {
			Index = index,
			Id = string.format("Level 3 Hall %02d", index),
			MinX = leaf.MinX + margin + rng:NextNumber(0, jitter),
			MaxX = leaf.MaxX - margin - rng:NextNumber(0, jitter),
			MinZ = leaf.MinZ + margin + rng:NextNumber(0, jitter),
			MaxZ = leaf.MaxZ - margin - rng:NextNumber(0, jitter),
			Connections = {},
			Role = "Hall",
			PoolType = "Shallow",
		}
		if rectWidth(hall) < Configuration.MinimumHallSize or rectDepth(hall) < Configuration.MinimumHallSize then
			return nil, "hall collapsed below minimum size"
		end
		hall.Center = rectCenter(hall)
		hall.Width = rectWidth(hall)
		hall.Depth = rectDepth(hall)
		hall.Area = hall.Width * hall.Depth
		hall.LocalSeed = rng:NextInteger(1, 2 ^ 30)
		table.insert(layout.Halls, hall)
	end

	-- Connect every hall to every facing neighbour that is close enough. This
	-- over-connects on purpose; the loop pass below is what keeps it readable.
	for i = 1, #layout.Halls do
		for j = i + 1, #layout.Halls do
			local a, b = layout.Halls[i], layout.Halls[j]
			local axis, distance = gapBetween(a, b)
			if axis and distance <= Configuration.MaximumCorridorLength then
				connect(layout, a, b, "Open")
			end
		end
	end

	-- Everything must be reachable, or the plan is thrown away and re-seeded.
	local firstDistances = bfs(layout, layout.Halls[1])
	local reached = 0
	for _ in pairs(firstDistances) do reached += 1 end
	if reached ~= #layout.Halls then return nil, "hall graph disconnected" end

	-- Arrival: the hall closest to the south-west corner.
	table.sort(layout.Halls, function(a, b) return a.Index < b.Index end)
	local arrival = layout.Halls[1]
	local bestCorner = math.huge
	for _, hall in ipairs(layout.Halls) do
		local d = (hall.Center - Vector3.new(layout.Bounds.MinX, 0, layout.Bounds.MinZ)).Magnitude
		if d < bestCorner then bestCorner, arrival = d, hall end
	end
	layout.Arrival = arrival

	local distances = bfs(layout, arrival)
	layout.Distances = distances
	for _, hall in ipairs(layout.Halls) do
		hall.GraphDepth = distances[hall.Index] or 0
		hall.ConnectionCount = #hall.Connections
	end

	-- Slide halls: the biggest rooms in the plan, well spread. The largest is
	-- the Grand Slide Hall and carries the exit flume on its top deck.
	local bySize = table.clone(layout.Halls)
	table.sort(bySize, function(a, b)
		if a.Area == b.Area then return a.Index < b.Index end
		return a.Area > b.Area
	end)
	local slideCandidates = {}
	for _, hall in ipairs(bySize) do
		if hall ~= arrival and hall.GraphDepth >= 1 then table.insert(slideCandidates, hall) end
	end
	local slideHalls = chooseSpread(slideCandidates, Configuration.SlideHallCount, Configuration.SlideHallSeparation)
	if #slideHalls < Configuration.SlideHallCount then return nil, "slide halls could not be spread" end
	layout.SlideHalls = slideHalls
	-- The grand hall carries the exit flume, which leaves through the east
	-- shell. Pick the easternmost slide hall so the flume's run stays short and
	-- crosses nothing but the void above the other halls' ceilings.
	local grand = slideHalls[1]
	for _, hall in ipairs(slideHalls) do
		if hall.Center.X > grand.Center.X then grand = hall end
	end
	layout.GrandSlideHall = grand

	local protected = {[arrival] = true}
	for _, hall in ipairs(slideHalls) do protected[hall] = true end

	-- Pump stations: three spread-out halls, all reachable without passing the
	-- grand hall's pressure door (guaranteed because that door is the only
	-- locked corridor and it only guards the grand hall itself).
	local pumpCandidates = {}
	for _, hall in ipairs(layout.Halls) do
		if not protected[hall] and hall.GraphDepth >= 1 then table.insert(pumpCandidates, hall) end
	end
	table.sort(pumpCandidates, function(a, b)
		if a.GraphDepth == b.GraphDepth then return a.Index < b.Index end
		return a.GraphDepth > b.GraphDepth
	end)
	local pumps = chooseSpread(pumpCandidates, 3, Configuration.PumpSeparation)
	if #pumps < 3 then return nil, "pump stations could not be spread" end
	layout.PumpHalls = pumps
	for _, hall in ipairs(pumps) do protected[hall] = true end

	-- Kids play area: a contiguous run of halls away from the arrival.
	local kidsSeeds = {}
	for _, hall in ipairs(layout.Halls) do
		if not protected[hall] and hall.GraphDepth >= 2 then table.insert(kidsSeeds, hall) end
	end
	local kidsBlock
	for _, candidate in ipairs(shuffled(rng, kidsSeeds)) do
		kidsBlock = growBlock(layout, candidate, Configuration.KidsAreaRoomCount, protected)
		if kidsBlock then break end
	end
	if not kidsBlock then return nil, "kids area block could not be grown" end
	layout.KidsArea = kidsBlock
	for _, hall in ipairs(kidsBlock) do protected[hall] = true end

	-- Entity den: deepest remaining hall.
	local denCandidates = {}
	for _, hall in ipairs(layout.Halls) do
		if not protected[hall] then table.insert(denCandidates, hall) end
	end
	table.sort(denCandidates, function(a, b)
		if a.GraphDepth == b.GraphDepth then return a.Index < b.Index end
		return a.GraphDepth > b.GraphDepth
	end)
	layout.EntityDen = denCandidates[1] or pumps[3]
	protected[layout.EntityDen] = true

	-- Lock every corridor into the grand slide hall behind the pressure door,
	-- then verify the rest of the complex is still fully reachable without it.
	local lockedCorridors = {}
	for _, corridor in ipairs(layout.Corridors) do
		if corridor.A == layout.GrandSlideHall.Index or corridor.B == layout.GrandSlideHall.Index then
			corridor.Kind = "PressureDoor"
			lockedCorridors[corridor.Index] = true
		end
	end
	if next(lockedCorridors) == nil then return nil, "grand slide hall has no entrance" end

	local openDistances = bfs(layout, arrival, lockedCorridors)
	for _, hall in ipairs(layout.Halls) do
		if hall ~= layout.GrandSlideHall and openDistances[hall.Index] == nil then
			return nil, "locking the grand hall cut off the complex"
		end
	end

	-- Each pump drains one corridor as visible feedback. Pick corridors that are
	-- NOT the pressure doors and that sit near each pump.
	local drainables = {}
	for _, corridor in ipairs(layout.Corridors) do
		if corridor.Kind == "Open" and corridor.Length >= Configuration.MinimumDrainableLength then
			table.insert(drainables, corridor)
		end
	end
	for pumpIndex, pump in ipairs(pumps) do
		local best, bestDistance = nil, math.huge
		for _, corridor in ipairs(drainables) do
			if not corridor.DrainGroup then
				local a = layout.Halls[corridor.A].Center
				local b = layout.Halls[corridor.B].Center
				local d = math.min((a - pump.Center).Magnitude, (b - pump.Center).Magnitude)
				if d < bestDistance then best, bestDistance = corridor, d end
			end
		end
		if best then
			best.DrainGroup = pumpIndex
			best.PoolType = "Deep"
		end
	end

	-- Pool depth / archetype for everything unclaimed.
	for _, hall in ipairs(layout.Halls) do
		if not protected[hall] then
			local roll = rng:NextNumber()
			if roll < .20 then
				hall.PoolType = "Deep"
				hall.Archetype = ({"Diving Well", "Pillar Basin"})[rng:NextInteger(1, 2)]
			elseif roll < .55 then
				hall.PoolType = "Shallow"
				hall.Archetype = ({"Flooded Gallery", "Curved Gallery", "Skylight Hall"})[rng:NextInteger(1, 3)]
			elseif roll < .78 then
				hall.PoolType = "Arch"
				hall.Archetype = ({"Arch Tunnel", "Ring Corridor"})[rng:NextInteger(1, 2)]
			else
				hall.PoolType = "Dry"
				hall.Archetype = ({"Dry Gallery", "Spiral Stair Well", "Locker Row"})[rng:NextInteger(1, 3)]
			end
		end
	end

	-- Named roles last so they always win.
	arrival.Role, arrival.PoolType, arrival.Archetype = "Arrival", "Dry", "Arrival Concourse"
	layout.EntityDen.Role, layout.EntityDen.PoolType, layout.EntityDen.Archetype =
		"Entity Den", "Deep", "Sunken Basin"

	for index, hall in ipairs(slideHalls) do
		hall.Role = "Slide Hall"
		hall.PoolType = "Slide"
		hall.IsGrand = hall == layout.GrandSlideHall
		hall.Archetype = hall.IsGrand and "Grand Slide Hall" or "Slide Hall"
		hall.SlideHallIndex = index
	end

	for index, hall in ipairs(pumps) do
		hall.Role = "Pump Station"
		hall.PumpIndex = index
		hall.PoolType = "Dry"
		hall.Archetype = "Pump Station"
	end

	-- Kids halls: dry, low, painted. Three colors total across the block, and no
	-- two connected kids halls share a color where the block shape allows.
	local colorCount = #Configuration.KidsColors
	local assigned = {}
	for index, hall in ipairs(kidsBlock) do
		hall.Role = "Kids Area"
		hall.PoolType = index == 1 and "KidsShallow" or "KidsDry"
		hall.Archetype = "Kids Play Room"
		hall.KidsIndex = index
		local used = {}
		for _, otherIndex in ipairs(hall.Connections) do
			if assigned[otherIndex] then used[assigned[otherIndex]] = true end
		end
		local pick
		for offset = 0, colorCount - 1 do
			local candidate = ((index - 1 + offset) % colorCount) + 1
			if not used[candidate] then pick = candidate break end
		end
		pick = pick or (((index - 1) % colorCount) + 1)
		assigned[hall.Index] = pick
		hall.KidsColorIndex = pick
	end

	layout.HallCount = #layout.Halls
	layout.CorridorCount = #layout.Corridors
	return layout
end

function LayoutGenerator.Generate(seed)
	seed = math.floor(tonumber(seed) or DateTime.now().UnixTimestampMillis % 2147483647)
	local lastError
	for attempt = 0, Configuration.GenerationAttempts - 1 do
		local attemptSeed = (seed + attempt * 104729) % 2147483647
		local layout, generationError = generateAttempt(attemptSeed)
		if layout then
			layout.RequestedSeed = seed
			layout.Attempt = attempt + 1
			return layout
		end
		lastError = generationError
	end
	error("Level 3 layout generation failed: " .. tostring(lastError))
end

return LayoutGenerator
