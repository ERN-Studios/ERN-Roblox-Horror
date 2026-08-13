-- Level 2 Layout Generator
-- Seeded procedural plan for the Sunken Leisure Complex.
--
-- This is NOT the Level 1 approach. Level 1 is a uniform grid of same-sized
-- cells carved by a DFS maze walk, so every room is identical in footprint and
-- rooms share walls directly with no corridors.
--
-- Level 2 uses recursive binary space partitioning over one large region:
--   * leaves become HALLS of genuinely different sizes (a slide hall can be
--     four times the floor area of a side gallery),
--   * halls are joined by explicit L-shaped CORRIDORS, which is where the
--     arched flooded tunnels live,
--   * the BSP merge order guarantees connectivity without a maze walk, and a
--     second pass adds loops so the complex reads as a building.
--
-- Roles it places: arrival, three pump stations (exactly one inside a
-- contiguous kids block), three slide halls (the largest of which holds the
-- exit flume on its top deck), and an entity den.

local Configuration = require(script.Parent:WaitForChild("Level 2 Configuration"))

local LayoutGenerator = {}

local MAX_SEED = 2147483647
local ATTEMPT_SEED_STRIDE = 104729
local INSET_EPSILON = 0.001

local function rectCenter(rect)
	return Vector3.new((rect.MinX + rect.MaxX) * .5, 0, (rect.MinZ + rect.MaxZ) * .5)
end

local function rectWidth(rect) return rect.MaxX - rect.MinX end
local function rectDepth(rect) return rect.MaxZ - rect.MinZ end

-- Keep the original random rolls whenever they fit. A 150-stud BSP leaf has
-- only five studs of total jitter to spare after margins and MinimumHallSize,
-- while the old code could independently consume fourteen studs on both sides.
-- Scaling only an over-budget pair preserves every formerly successful hall
-- exactly and converts the old "hall collapsed" rejection into a valid hall.
local function fitInsetPair(firstInset, secondInset, available)
	if available < 0 then return nil, nil end
	local total = firstInset + secondInset
	if total <= available then return firstInset, secondInset end
	if total <= 0 then return 0, 0 end
	local fittedAvailable = math.max(0, available - INSET_EPSILON)
	local scale = fittedAvailable / total
	return firstInset * scale, secondInset * scale
end

-- ── binary space partition ──────────────────────────────────────────────────

local function split(rng, rect, depth, leaves)
	local width, depth3 = rectWidth(rect), rectDepth(rect)
	local minLeaf = Configuration.MinimumLeafSize
	local canSplitX = width >= minLeaf * 2 + Configuration.HallMargin
	local canSplitZ = depth3 >= minLeaf * 2 + Configuration.HallMargin

	local maxLeaf = Configuration.MaximumLeafSize or math.huge
	local oversize = width > maxLeaf or depth3 > maxLeaf
	local mustStop = (not canSplitX and not canSplitZ)
		or (depth >= Configuration.MaximumSplitDepth and not oversize)
	-- Stop early sometimes so the plan keeps a few of the LARGEST ALLOWED
	-- rooms — never while the region still exceeds MaximumLeafSize and can
	-- legally split again.
	if not mustStop and not oversize and depth >= Configuration.MinimumSplitDepth
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
		Id = string.format("Level 2 Corridor %02d", #layout.Corridors + 1),
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
local function growBlock(layout, seed, count, blocked, allowsHall)
	local block = {seed}
	local inBlock = {[seed.Index] = true}
	local frontier = {seed}
	while #block < count and #frontier > 0 do
		local hall = table.remove(frontier, 1)
		for _, otherIndex in ipairs(hall.Connections) do
			if #block >= count then break end
			local other = layout.Halls[otherIndex]
			if not inBlock[other.Index] and not blocked[other]
				and (not allowsHall or allowsHall(other))
			then
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
		local minimumHallSize = Configuration.MinimumHallSize
		-- Keep this draw order identical to the original generator so layouts that
		-- already succeeded retain exactly the same geometry and later RNG stream.
		local minXInset = rng:NextNumber(0, jitter)
		local maxXInset = rng:NextNumber(0, jitter)
		local minZInset = rng:NextNumber(0, jitter)
		local maxZInset = rng:NextNumber(0, jitter)
		minXInset, maxXInset = fitInsetPair(
			minXInset,
			maxXInset,
			rectWidth(leaf) - margin * 2 - minimumHallSize
		)
		minZInset, maxZInset = fitInsetPair(
			minZInset,
			maxZInset,
			rectDepth(leaf) - margin * 2 - minimumHallSize
		)
		if not minXInset or not minZInset then
			return nil, "BSP leaf cannot contain the minimum hall size"
		end
		local hall = {
			Index = index,
			Id = string.format("Level 2 Hall %02d", index),
			MinX = leaf.MinX + margin + minXInset,
			MaxX = leaf.MaxX - margin - maxXInset,
			MinZ = leaf.MinZ + margin + minZInset,
			MaxZ = leaf.MaxZ - margin - maxZInset,
			Connections = {},
			Role = "Hall",
			PoolType = "Shallow",
		}
		if rectWidth(hall) + INSET_EPSILON < minimumHallSize
			or rectDepth(hall) + INSET_EPSILON < minimumHallSize then
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

	-- The exit-bearing slide hall must be the easternmost eligible hall, not
	-- merely the easternmost of an area-first subset. This keeps its one-way
	-- flume beside the east shell on every seed; the remaining two slide halls
	-- still prefer the largest rooms and normal separation.
	local bySize = table.clone(layout.Halls)
	table.sort(bySize, function(a, b)
		if a.Area == b.Area then return a.Index < b.Index end
		return a.Area > b.Area
	end)
	-- Slide halls need room for the deck, three flume lanes and the spiral:
	-- anything smaller makes the tubes clip their own furniture.
	local slideCandidates = {}
	for _, hall in ipairs(bySize) do
		if hall ~= arrival and hall.GraphDepth >= 1
			and hall.Width >= 175 and hall.Depth >= 165 then
			table.insert(slideCandidates, hall)
		end
	end
	local eastExitHall = slideCandidates[1]
	for _, hall in ipairs(slideCandidates) do
		if hall.MaxX > eastExitHall.MaxX
			or (hall.MaxX == eastExitHall.MaxX and hall.Index < eastExitHall.Index) then
			eastExitHall = hall
		end
	end
	local exitFirstCandidates = {eastExitHall}
	for _, hall in ipairs(slideCandidates) do
		if hall ~= eastExitHall then table.insert(exitFirstCandidates, hall) end
	end
	local slideHalls = chooseSpread(exitFirstCandidates,
		Configuration.SlideHallCount, Configuration.SlideHallSeparation)
	if #slideHalls < Configuration.SlideHallCount then return nil, "slide halls could not be spread" end
	layout.SlideHalls = slideHalls
	layout.GrandSlideHall = eastExitHall

	local protected = {[arrival] = true}
	for _, hall in ipairs(slideHalls) do protected[hall] = true end

	-- Kids play area: a contiguous run of halls beyond the first rooms after
	-- spawn. This keeps the arrival route neutral before the childlike wing is
	-- discovered, and never lets a depth-one hall become part of Kids Area.
	-- It is selected before the pumps because exactly one objective pump belongs
	-- inside this wing on every generated layout.
	-- Kids rooms must stay cosy: never grow the wing out of big halls, since
	-- the wall-to-wall merge below extends them even further.
	local function kidsSized(hall)
		return math.max(hall.Width, hall.Depth) <= 200
	end
	local kidsSeeds = {}
	for _, hall in ipairs(layout.Halls) do
		if not protected[hall] and hall.GraphDepth >= 2 and kidsSized(hall) then
			table.insert(kidsSeeds, hall)
		end
	end
	table.sort(kidsSeeds, function(a, b)
		if a.GraphDepth == b.GraphDepth then return a.Index < b.Index end
		return a.GraphDepth > b.GraphDepth
	end)
	local kidsBlock
	for _, candidate in ipairs(kidsSeeds) do
		kidsBlock = growBlock(layout, candidate, Configuration.KidsAreaRoomCount, protected,
			function(hall) return hall.GraphDepth >= 2 and kidsSized(hall) end)
		if kidsBlock then break end
	end
	if not kidsBlock then return nil, "kids area block could not be grown" end
	layout.KidsArea = kidsBlock
	for _, hall in ipairs(kidsBlock) do protected[hall] = true end

	-- Reserve one dry Kids Area hall for Pump 1. Never choose the first Kids
	-- hall because that room owns the shallow play pool; the remaining rooms are
	-- dry and leave a clean central machine zone.
	local kidsPumpCandidates = {}
	for index = 2, #kidsBlock do table.insert(kidsPumpCandidates, kidsBlock[index]) end
	table.sort(kidsPumpCandidates, function(a, b)
		if a.Area == b.Area then
			if a.GraphDepth == b.GraphDepth then return a.Index < b.Index end
			return a.GraphDepth > b.GraphDepth
		end
		return a.Area > b.Area
	end)
	local kidsPump = kidsPumpCandidates[1]
	if not kidsPump then return nil, "kids area has no dry hall for its pump" end

	-- The other two pumps remain outside the Kids Area. Sort by distance from
	-- the kids pump, then choose a pair that also respects mutual separation.
	-- All three remain reachable without passing the grand hall pressure door.
	local pumpCandidates = {}
	for _, hall in ipairs(layout.Halls) do
		if not protected[hall] and hall.GraphDepth >= 1
			and separation(hall, kidsPump) >= Configuration.PumpSeparation then
			table.insert(pumpCandidates, hall)
		end
	end
	table.sort(pumpCandidates, function(a, b)
		local aDistance = separation(a, kidsPump)
		local bDistance = separation(b, kidsPump)
		if aDistance == bDistance then
			if a.GraphDepth == b.GraphDepth then return a.Index < b.Index end
			return a.GraphDepth > b.GraphDepth
		end
		return aDistance > bDistance
	end)
	local outsidePumps = chooseSpread(pumpCandidates, 2, Configuration.PumpSeparation)
	if #outsidePumps < 2 then return nil, "outside pump stations could not be spread from the kids pump" end
	local pumps = {kidsPump, outsidePumps[1], outsidePumps[2]}
	layout.PumpHalls = pumps
	for _, hall in ipairs(outsidePumps) do protected[hall] = true end

	-- Merge the kids block wall-to-wall: for each corridor joining two kids
	-- halls, extend both halls to a shared wall with a doorway, provided that
	-- corridor is the only thing on that side of both halls (so the extension
	-- cannot swallow another hall's corridor).
	local kidsSet = {}
	for _, hall in ipairs(kidsBlock) do kidsSet[hall.Index] = true end
	local function corridorsOnSide(hall, axis, positive)
		local count = 0
		for _, corridor in ipairs(layout.Corridors) do
			if corridor.Axis == axis and (corridor.A == hall.Index or corridor.B == hall.Index) then
				local other = layout.Halls[corridor.A == hall.Index and corridor.B or corridor.A]
				if axis == "X" then
					if positive == (other.Center.X > hall.Center.X) then count += 1 end
				else
					if positive == (other.Center.Z > hall.Center.Z) then count += 1 end
				end
			end
		end
		return count
	end
	for _, corridor in ipairs(layout.Corridors) do
		if kidsSet[corridor.A] and kidsSet[corridor.B] and corridor.Kind == "Open" then
			local a, b = layout.Halls[corridor.A], layout.Halls[corridor.B]
			if corridor.Axis == "X" then
				local left = (a.MaxX <= b.MinX) and a or b
				local right = (left == a) and b or a
				if corridorsOnSide(left, "X", true) == 1 and corridorsOnSide(right, "X", false) == 1 then
					local mid = (left.MaxX + right.MinX) * .5
					left.MaxX = mid - 1.75
					right.MinX = mid + 1.75
					corridor.Kind = "SharedWall"
				end
			else
				local north = (a.MaxZ <= b.MinZ) and a or b
				local south = (north == a) and b or a
				if corridorsOnSide(north, "Z", true) == 1 and corridorsOnSide(south, "Z", false) == 1 then
					local mid = (north.MaxZ + south.MinZ) * .5
					north.MaxZ = mid - 1.75
					south.MinZ = mid + 1.75
					corridor.Kind = "SharedWall"
				end
			end
		end
	end
	for _, hall in ipairs(kidsBlock) do
		hall.Center = rectCenter(hall)
		hall.Width = rectWidth(hall)
		hall.Depth = rectDepth(hall)
		hall.Area = hall.Width * hall.Depth
	end

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

	-- Second reserved den, far from the first, for an eventual second hostile.
	layout.EntityDenB = nil
	for index = 2, #denCandidates do
		if separation(denCandidates[index], layout.EntityDen) >= 300 then
			layout.EntityDenB = denCandidates[index]
			break
		end
	end
	layout.EntityDenB = layout.EntityDenB or denCandidates[2]
	if layout.EntityDenB then protected[layout.EntityDenB] = true end

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

	-- Every generic hall is flooded wall-to-wall; only depth and set dressing
	-- vary. There are no dry rooms outside the kids wing and the service rooms.
	for _, hall in ipairs(layout.Halls) do
		if not protected[hall] then
			local roll = rng:NextNumber()
			if roll < .28 then
				hall.PoolType = "Deep"
				hall.Archetype = ({"Diving Well", "Pillar Basin", "Column Forest"})[rng:NextInteger(1, 3)]
			elseif roll < .62 then
				hall.PoolType = "Shallow"
				hall.Archetype = ({"Flooded Gallery", "Curved Gallery", "Skylight Hall", "Column Forest"})[rng:NextInteger(1, 4)]
			else
				hall.PoolType = "Shallow"
				hall.Archetype = ({"Arch Tunnel", "Ring Corridor", "Spiral Stair Well", "Porthole Hall"})[rng:NextInteger(1, 4)]
			end
		end
	end

	-- Named roles last so they always win.
	arrival.Role, arrival.PoolType, arrival.Archetype = "Arrival", "Dry", "Arrival Concourse"
	layout.EntityDen.Role, layout.EntityDen.PoolType, layout.EntityDen.Archetype =
		"Entity Den", "Deep", "Sunken Basin"
	if layout.EntityDenB then
		layout.EntityDenB.Role, layout.EntityDenB.PoolType, layout.EntityDenB.Archetype =
			"Entity Den B", "Shallow", "Column Forest"
	end

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

local function isFiniteNumber(value)
	return type(value) == "number"
		and value == value
		and value > -math.huge
		and value < math.huge
end

local function validateLayout(layout)
	local function invalid(reason)
		return false, reason
	end
	if type(layout) ~= "table" then return invalid("layout is not a table") end
	if type(layout.Halls) ~= "table" or #layout.Halls < Configuration.MinimumHallCount then
		return invalid("minimum hall count was not met")
	end
	if type(layout.Corridors) ~= "table" or #layout.Corridors == 0 then
		return invalid("layout has no corridors")
	end
	if type(layout.CorridorByPair) ~= "table" then
		return invalid("corridor lookup is missing")
	end
	if not isFiniteNumber(layout.Seed) then return invalid("resolved seed is invalid") end

	local function isLayoutHall(hall)
		return type(hall) == "table"
			and type(hall.Index) == "number"
			and layout.Halls[hall.Index] == hall
	end
	if not isLayoutHall(layout.Arrival) then return invalid("arrival hall is missing") end
	if not isLayoutHall(layout.GrandSlideHall) then return invalid("grand slide hall is missing") end
	if not isLayoutHall(layout.EntityDen) then return invalid("entity den is missing") end

	local occupied = {}
	local function reserve(hall, label)
		if not isLayoutHall(hall) then return false, label .. " is not a layout hall" end
		if occupied[hall] then
			return false, label .. " overlaps " .. occupied[hall]
		end
		occupied[hall] = label
		return true
	end

	local ok, reason = reserve(layout.Arrival, "arrival")
	if not ok then return invalid(reason) end
	if type(layout.SlideHalls) ~= "table"
		or #layout.SlideHalls ~= Configuration.SlideHallCount then
		return invalid("slide hall count is invalid")
	end
	local foundGrand = false
	for index, hall in ipairs(layout.SlideHalls) do
		ok, reason = reserve(hall, "slide hall " .. index)
		if not ok then return invalid(reason) end
		if hall == layout.GrandSlideHall then foundGrand = true end
	end
	if not foundGrand or layout.GrandSlideHall.IsGrand ~= true then
		return invalid("grand hall is not a marked slide hall")
	end

	if type(layout.PumpHalls) ~= "table" or #layout.PumpHalls ~= 3 then
		return invalid("pump hall count is invalid")
	end
	local pumpHallSet = {}
	for index, hall in ipairs(layout.PumpHalls) do
		ok, reason = reserve(hall, "pump hall " .. index)
		if not ok then return invalid(reason) end
		pumpHallSet[hall] = true
		if hall.PumpIndex ~= index then
			return invalid("pump hall " .. index .. " has a mismatched pump index")
		end
	end

	if type(layout.KidsArea) ~= "table"
		or #layout.KidsArea ~= Configuration.KidsAreaRoomCount then
		return invalid("kids area count is invalid")
	end
	local kidsPumpCount = 0
	local kidsPumpHall
	for index, hall in ipairs(layout.KidsArea) do
		if pumpHallSet[hall] then
			kidsPumpCount += 1
			kidsPumpHall = hall
		else
			ok, reason = reserve(hall, "kids hall " .. index)
			if not ok then return invalid(reason) end
		end
	end
	if kidsPumpCount ~= 1 then
		return invalid("exactly one pump hall must be inside the kids area")
	end
	if kidsPumpHall ~= layout.PumpHalls[1]
		or kidsPumpHall.KidsIndex == 1
		or kidsPumpHall.PoolType ~= "KidsDry"
		or kidsPumpHall.Role ~= "Kids Area" then
		return invalid("pump 1 must be inside a dry, non-first kids room")
	end
	for index = 2, #layout.PumpHalls do
		if layout.PumpHalls[index].Role ~= "Pump Station" then
			return invalid("outside pump hall " .. index .. " lost its pump-station role")
		end
	end
	for first = 1, #layout.PumpHalls do
		for second = first + 1, #layout.PumpHalls do
			if separation(layout.PumpHalls[first], layout.PumpHalls[second])
				+ INSET_EPSILON < Configuration.PumpSeparation then
				return invalid(string.format(
					"pump halls %d and %d are below final separation",
					first,
					second
				))
			end
		end
	end

	for index, hall in ipairs(layout.Halls) do
		if hall.Index ~= index then return invalid("hall indices are not contiguous") end
		if not isFiniteNumber(hall.MinX) or not isFiniteNumber(hall.MaxX)
			or not isFiniteNumber(hall.MinZ) or not isFiniteNumber(hall.MaxZ) then
			return invalid("hall " .. index .. " has non-finite bounds")
		end
		if rectWidth(hall) + INSET_EPSILON < Configuration.MinimumHallSize
			or rectDepth(hall) + INSET_EPSILON < Configuration.MinimumHallSize then
			return invalid("hall " .. index .. " is below the minimum size")
		end
		if type(hall.Connections) ~= "table" then
			return invalid("hall " .. index .. " has no connection list")
		end
	end

	local pairSet = {}
	local pressureDoors = {}
	local drainGroups = {}
	for index, corridor in ipairs(layout.Corridors) do
		if corridor.Index ~= index then return invalid("corridor indices are not contiguous") end
		if type(corridor.A) ~= "number" or type(corridor.B) ~= "number"
			or corridor.A == corridor.B or not layout.Halls[corridor.A]
			or not layout.Halls[corridor.B] then
			return invalid("corridor " .. index .. " has invalid endpoints")
		end
		if not isFiniteNumber(corridor.Length) or corridor.Length <= 0 then
			return invalid("corridor " .. index .. " has invalid length")
		end
		local pairKey = math.min(corridor.A, corridor.B)
			.. ":" .. math.max(corridor.A, corridor.B)
		if pairSet[pairKey] then return invalid("duplicate corridor pair " .. pairKey) end
		pairSet[pairKey] = corridor
		if layout.CorridorByPair[pairKey] ~= corridor then
			return invalid("corridor lookup mismatch for " .. pairKey)
		end
		if corridor.Kind == "PressureDoor" then
			if corridor.A ~= layout.GrandSlideHall.Index
				and corridor.B ~= layout.GrandSlideHall.Index then
				return invalid("pressure door does not guard the grand hall")
			end
			pressureDoors[index] = true
		end
		if corridor.DrainGroup ~= nil then
			if type(corridor.DrainGroup) ~= "number"
				or corridor.DrainGroup % 1 ~= 0
				or corridor.DrainGroup < 1
				or corridor.DrainGroup > #layout.PumpHalls then
				return invalid("corridor " .. index .. " has an invalid drain group")
			end
			if drainGroups[corridor.DrainGroup] then
				return invalid("drain group " .. corridor.DrainGroup .. " is duplicated")
			end
			drainGroups[corridor.DrainGroup] = true
		end
	end
	if next(pressureDoors) == nil then return invalid("grand hall has no pressure door") end

	for index, hall in ipairs(layout.Halls) do
		local seenConnections = {}
		for _, otherIndex in ipairs(hall.Connections) do
			if type(otherIndex) ~= "number" or otherIndex == index
				or not layout.Halls[otherIndex] then
				return invalid("hall " .. index .. " has an invalid connection endpoint")
			end
			if seenConnections[otherIndex] then
				return invalid("hall " .. index .. " repeats a connection")
			end
			seenConnections[otherIndex] = true
			local pairKey = math.min(index, otherIndex) .. ":" .. math.max(index, otherIndex)
			if not pairSet[pairKey] then
				return invalid("hall " .. index .. " references a missing corridor")
			end
			local reciprocal = false
			for _, candidate in ipairs(layout.Halls[otherIndex].Connections) do
				if candidate == index then reciprocal = true break end
			end
			if not reciprocal then
				return invalid("hall " .. index .. " has a one-way graph connection")
			end
		end
	end

	local allDistances = bfs(layout, layout.Arrival)
	for index = 1, #layout.Halls do
		if allDistances[index] == nil then return invalid("hall graph is disconnected") end
	end
	local openDistances = bfs(layout, layout.Arrival, pressureDoors)
	for _, hall in ipairs(layout.Halls) do
		if hall ~= layout.GrandSlideHall and openDistances[hall.Index] == nil then
			return invalid("pressure doors cut off a required hall")
		end
	end

	if layout.HallCount ~= #layout.Halls or layout.CorridorCount ~= #layout.Corridors then
		return invalid("cached layout counts are stale")
	end
	return true
end

function LayoutGenerator.Validate(layout)
	return validateLayout(layout)
end

local function normalizeSeed(value, useClockFallback)
	local numeric = tonumber(value)
	if not isFiniteNumber(numeric) then
		if not useClockFallback then return nil end
		numeric = DateTime.now().UnixTimestampMillis
	end
	return math.floor(numeric) % MAX_SEED
end

local function configuredAttemptCount(value, defaultValue)
	local numeric = tonumber(value)
	if not isFiniteNumber(numeric) then numeric = defaultValue end
	return math.max(1, math.floor(numeric))
end

function LayoutGenerator.Generate(seed)
	seed = normalizeSeed(seed, true)
	local lastError
	local totalAttempts = 0

	local function trySequence(baseSeed, attemptCount, fallbackBaseSeed)
		for attempt = 0, attemptCount - 1 do
			local attemptSeed = (baseSeed + attempt * ATTEMPT_SEED_STRIDE) % MAX_SEED
			totalAttempts += 1
			local layout, generationError = generateAttempt(attemptSeed)
			if layout then
				local valid, validationError = validateLayout(layout)
				if valid then
					layout.RequestedSeed = seed
					layout.Attempt = totalAttempts
					layout.AttemptWithinSequence = attempt + 1
					layout.FallbackUsed = fallbackBaseSeed ~= nil
					layout.FallbackBaseSeed = fallbackBaseSeed
					return layout
				end
				generationError = "validation failed: " .. tostring(validationError)
			end
			lastError = string.format("seed %d: %s", attemptSeed, tostring(generationError))
		end
		return nil
	end

	local primaryAttempts = configuredAttemptCount(Configuration.GenerationAttempts, 40)
	local layout = trySequence(seed, primaryAttempts, nil)
	if layout then return layout end

	local fallbackAttempts = configuredAttemptCount(
		Configuration.GenerationFallbackAttemptsPerSeed,
		primaryAttempts
	)
	for _, configuredSeed in ipairs(Configuration.GenerationFallbackSeeds or {}) do
		local fallbackSeed = normalizeSeed(configuredSeed, false)
		if fallbackSeed then
			layout = trySequence(fallbackSeed, fallbackAttempts, fallbackSeed)
			if layout then return layout end
		end
	end

	error(string.format(
		"Level 2 layout generation failed after %d validated attempts: %s",
		totalAttempts,
		tostring(lastError)
	))
end

return LayoutGenerator
