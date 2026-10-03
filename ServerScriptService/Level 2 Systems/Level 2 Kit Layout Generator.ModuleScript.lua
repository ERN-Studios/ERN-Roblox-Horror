-- Level 2 Blender-kit preview layout. The live generator remains authoritative for live rounds.
local Configuration = require(script.Parent:WaitForChild("Level 2 Configuration"))

local LayoutGenerator = {}

local MAX_SEED = 2147483647
local ATTEMPT_SEED_STRIDE = 104729
local INSET_EPSILON = 0.001

local function rectCenter(rect)
	return Vector3.new((rect.MinX + rect.MaxX) * .5, (rect.FloorY or 0), (rect.MinZ + rect.MaxZ) * .5)
end

local function rectWidth(rect) return rect.MaxX - rect.MinX end
local function rectDepth(rect) return rect.MaxZ - rect.MinZ end

-- Fixed footprints are reserved before role selection; their walls never move afterwards.
local function exitHallMinimums() return 224, 208 end

local SMALL_PREFABS = {
	{Name = "Chamber_A", Width = 48, Depth = 48, Archetype = "Chamber", Ceiling = 15},
	{Name = "Chamber_B", Width = 48, Depth = 64, Archetype = "Chamber", Ceiling = 15},
	{Name = "Chamber_C", Width = 64, Depth = 64, Archetype = "Chamber", Ceiling = 15},
	{Name = "Chamber_D", Width = 40, Depth = 56, Archetype = "Chamber", Ceiling = 15},
}
local HALL_TYPES = {
	{Name = "ColumnHall", Weight = 25}, {Name = "BigPool", Weight = 15},
	{Name = "VaultArcade", Weight = 15}, {Name = "CurvedChannel", Weight = 20},
	{Name = "SpiralWell", Weight = 10}, {Name = "CorridorHall", Weight = 15},
}
local TUNNEL_LENGTHS = {[64] = true, [72] = true, [80] = true}
local PASSAGE_LENGTHS = {[16] = true, [24] = true, [32] = true, [48] = true, [64] = true, [80] = true}
local BAND_SIZES = {176, 184, 192, 200, 208, 216, 224, 232, 240, 248, 256, 264, 272, 280, 288, 296, 304}

local function shuffle(rng, values)
	for i = #values, 2, -1 do
		local j = rng:NextInteger(1, i)
		values[i], values[j] = values[j], values[i]
	end
end

-- A strip BSP keeps fixed-prefab-sized leaves common, rather than relying on
-- two independent continuous cuts landing on an exact footprint by chance.
local function bands(rng, total, reserved)
	local result = table.clone(reserved)
	local remaining = total
	for _, size in ipairs(result) do remaining -= size end
	while #result < 6 do
		local left = 6 - #result - 1
		local choices = {}
		for _, size in ipairs(BAND_SIZES) do
			if remaining - size >= left * 176 and remaining - size <= left * 304 then
				if left > 0 or size == remaining then table.insert(choices, size) end
			end
		end
		if #choices == 0 then return nil end
		local size = choices[rng:NextInteger(1, #choices)]
		table.insert(result, size)
		remaining -= size
	end
	shuffle(rng, result)
	return result
end

local function split(rng, bounds)
	local depthBands = bands(rng, rectDepth(bounds), {
		({272, 280, 288})[rng:NextInteger(1, 3)],
		({240, 248, 256})[rng:NextInteger(1, 3)],
	})
	if not depthBands then return nil end
	local leaves = {}
	local z = bounds.MinZ
	for _, depth in ipairs(depthBands) do
		local widths = bands(rng, rectWidth(bounds), {
			({288, 296, 304})[rng:NextInteger(1, 3)],
			({272, 280, 288})[rng:NextInteger(1, 3)],
		})
		if not widths then return nil end
		-- Keep an exit-capable footprint on the east boundary of the wide strip.
		if depth >= 272 and depth <= 288 then
			for i, width in ipairs(widths) do
				if width >= 288 then widths[i], widths[6] = widths[6], widths[i] break end
			end
		end
		local x = bounds.MinX
		for _, width in ipairs(widths) do
			table.insert(leaves, {MinX = x, MaxX = x + width, MinZ = z, MaxZ = z + depth})
			x += width
		end
		z += depth
	end
	return leaves
end

local function wallSpan(hall, axis)
	if axis == "X" then return hall.MinZ, hall.MaxZ end
	return hall.MinX, hall.MaxX
end

local function facing(a, b)
	if a.MaxX <= b.MinX then return "X", a.MaxX, b.MinX, a, b end
	if b.MaxX <= a.MinX then return "X", b.MaxX, a.MinX, b, a end
	if a.MaxZ <= b.MinZ then return "Z", a.MaxZ, b.MinZ, a, b end
	if b.MaxZ <= a.MinZ then return "Z", b.MaxZ, a.MinZ, b, a end
	return nil
end

local function socket(hall, axis, cross, margin)
	local low, high = wallSpan(hall, axis)
	if cross < low + margin or cross > high - margin or cross % 4 ~= 0 then return false end
	if hall.Role ~= "Small" then return true end
	local offset = math.abs(cross - (low + high) * .5)
	return offset == 0 or (high - low >= 64 and offset == 16)
end

local function corridorRect(c)
	if c.Axis == "X" then
		return {MinX = c.From, MaxX = c.To, MinZ = c.Cross - c.Width / 2, MaxZ = c.Cross + c.Width / 2}
	end
	return {MinX = c.Cross - c.Width / 2, MaxX = c.Cross + c.Width / 2, MinZ = c.From, MaxZ = c.To}
end

local function intersects(a, b, inclusive)
	if inclusive then
		return a.MinX <= b.MaxX and b.MinX <= a.MaxX and a.MinZ <= b.MaxZ and b.MinZ <= a.MaxZ
	end
	return a.MinX < b.MaxX and b.MinX < a.MaxX and a.MinZ < b.MaxZ and b.MinZ < a.MaxZ
end

local function clearCorridor(layout, corridor)
	local rect = corridorRect(corridor)
	for _, hall in ipairs(layout.Halls) do
		if hall.Index ~= corridor.A and hall.Index ~= corridor.B and intersects(rect, hall, true) then return false end
	end
	for _, other in ipairs(layout.Corridors) do
		if intersects(rect, corridorRect(other), true) then return false end
	end
	return true
end

local function connect(layout, a, b, pass)
	local pairKey = math.min(a.Index, b.Index) .. ":" .. math.max(a.Index, b.Index)
	if layout.CorridorByPair[pairKey] then return layout.CorridorByPair[pairKey] end
	local axis, from, to = facing(a, b)
	if not axis then return nil end
	local al, ah = wallSpan(a, axis)
	local bl, bh = wallSpan(b, axis)
	local overlap = math.min(ah, bh) - math.max(al, bl)
	local small = a.Role == "Small" or b.Role == "Small"
	local length = to - from
	local narrow = small or (overlap >= 28 and overlap < 42)
	if narrow then
		if not PASSAGE_LENGTHS[length] or overlap < 12 then return nil end
	elseif overlap < 42 or not TUNNEL_LENGTHS[length] then return nil end
	if (pass == 1 and narrow) or (pass == 2 and not narrow) then return nil end
	if small and (a.Footprint == "GrandSlideHall" or b.Footprint == "GrandSlideHall") then return nil end
	local margin = narrow and 8 or 21
	local low = math.ceil(math.max(al + margin, bl + margin) / 4) * 4
	local high = math.floor(math.min(ah - margin, bh - margin) / 4) * 4
	local choices = {}
	for cross = low, high, 4 do
		if socket(a, axis, cross, margin) and socket(b, axis, cross, margin) then table.insert(choices, cross) end
	end
	table.sort(choices, function(x, y)
		local mid = (low + high) / 2
		if math.abs(x - mid) == math.abs(y - mid) then return x < y end
		return math.abs(x - mid) < math.abs(y - mid)
	end)
	for _, cross in ipairs(choices) do
		local corridor = {
			Index = #layout.Corridors + 1, Id = string.format("Level 2 Corridor %02d", #layout.Corridors + 1),
			A = a.Index, B = b.Index, Axis = axis, From = from, To = to,
			Length = length, Cross = cross, Width = narrow and 12 or 34,
			Kind = narrow and "Narrow" or "Open", PoolType = narrow and "Dry" or "Shallow",
		}
		if clearCorridor(layout, corridor) then
			table.insert(layout.Corridors, corridor)
			layout.CorridorByPair[pairKey] = corridor
			table.insert(a.Connections, b.Index)
			table.insert(b.Connections, a.Index)
			return corridor
		end
	end
	return nil
end

local function addHall(layout, rng, leaf, leafIndex, rect)
	rect.Index = #layout.Halls + 1
	rect.Id = string.format("Level 2 Hall %02d", rect.Index)
	rect.Leaf, rect.LeafIndex = leaf, leafIndex
	rect.Connections = {}
	rect.Role, rect.PoolType = rect.Role or "Hall", rect.PoolType or "Shallow"
	rect.Center = rectCenter(rect)
	rect.Width, rect.Depth = rectWidth(rect), rectDepth(rect)
	rect.Area = rect.Width * rect.Depth
	rect.LocalSeed = rng:NextInteger(1, 2 ^ 30)
	table.insert(layout.Halls, rect)
	if rect.Role == "Small" then table.insert(layout.SmallRooms, rect.Index) end
end

local function fixedInsets(size, target)
	local sum = size - target
	if sum == 64 then return 32, 32 end
	if sum == 72 then return 32, 40 end
	if sum == 80 then return 40, 40 end
	return nil
end

local function bigHall(layout, rng, leaf, leafIndex)
	local insets = {}
	for i = 1, 4 do insets[i] = rng:NextNumber() < .5 and 32 or 40 end
	local tag, rotation
	local left, right = fixedInsets(rectWidth(leaf), 224)
	local north, south = fixedInsets(rectDepth(leaf), 208)
	if left and north and leaf.MaxX == layout.Bounds.MaxX then
		insets = {left, right, north, south}
		tag, rotation = "GrandSlideHall", 0
	end
	addHall(layout, rng, leaf, leafIndex, {
		MinX = leaf.MinX + insets[1], MaxX = leaf.MaxX - insets[2],
		MinZ = leaf.MinZ + insets[3], MaxZ = leaf.MaxZ - insets[4],
		Footprint = tag, Rotation = rotation or 0,
	})
end

local function smallCluster(layout, rng, leaf, leafIndex, anchor, count)
	local axis, _, _, first = facing(leaf, anchor.Leaf)
	if not axis then return false end
	local positive = first == anchor.Leaf
	local normalSize = axis == "X" and rectWidth(leaf) or rectDepth(leaf)
	local crossLow, crossHigh = wallSpan(leaf, axis)
	local anchorLow, anchorHigh = wallSpan(anchor, axis)
	local prefabs, widths, normals = {}, {}, {}
	local rowDepth = ({48, 56, 64})[rng:NextInteger(1, 3)]
	for col = 1, 2 do
		local choices = {}
		-- Matching row depths align adjacent pipe sockets. The 80-stud row
		-- pitch then leaves an authored 16, 24 or 32-stud pipe gap.
		for _, prefab in ipairs(SMALL_PREFABS) do
			if prefab.Depth == rowDepth then table.insert(choices, {Prefab = prefab, Turn = 0}) end
			if prefab.Width == rowDepth and prefab.Width ~= prefab.Depth then
				table.insert(choices, {Prefab = prefab, Turn = 1})
			end
		end
		local choice = choices[rng:NextInteger(1, #choices)]
		local prefab, turn = choice.Prefab, choice.Turn
		prefabs[col] = prefab
		widths[col] = turn == 1 and prefab.Depth or prefab.Width
		normals[col] = turn == 1 and prefab.Width or prefab.Depth
	end
	local totalCross = widths[1] + widths[2] + 16
	local startLow, startHigh = crossLow + 16, crossHigh - totalCross - 16
	local desired = (anchorLow + anchorHigh) / 2 - widths[1] / 2
	local crossStart = math.clamp(math.floor(desired / 4) * 4, startLow, startHigh)
	local socket1 = crossStart + widths[1] / 2
	local socket2 = crossStart + widths[1] + 16 + widths[2] / 2
	if not ((socket1 >= anchorLow + 8 and socket1 <= anchorHigh - 8)
		or (socket2 >= anchorLow + 8 and socket2 <= anchorHigh - 8)) then return false end
	local inset = positive and ((axis == "X" and leaf.MinX or leaf.MinZ)
		- (axis == "X" and anchor.MaxX or anchor.MaxZ))
		or ((axis == "X" and anchor.MinX or anchor.MinZ) - (axis == "X" and leaf.MaxX or leaf.MaxZ))
	if normalSize < inset + 144 then count = 2 end
	for i = 1, count do
		local col, row = (i - 1) % 2 + 1, math.floor((i - 1) / 2)
		local prefab = prefabs[col]
		local w, d = axis == "X" and normals[col] or widths[col], axis == "X" and widths[col] or normals[col]
		local rotation = (prefab.Width == w and prefab.Depth == d) and 0 or 90
		rotation += rng:NextInteger(0, 1) * 180
		local normalLow, normalHigh
		local near = (axis == "X" and leaf.MinX or leaf.MinZ) + inset + row * 80
		local far = (axis == "X" and leaf.MaxX or leaf.MaxZ) - inset - row * 80
		if positive then normalLow, normalHigh = near, near + normals[col]
		else normalLow, normalHigh = far - normals[col], far end
		local cross = crossStart + (col == 2 and widths[1] + 16 or 0)
		local rect = {Role = "Small", PoolType = "Dry", Type = "Chamber", Prefab = prefab.Name,
			Archetype = prefab.Archetype, Rotation = rotation}
		if axis == "X" then rect.MinX, rect.MaxX, rect.MinZ, rect.MaxZ = normalLow, normalHigh, cross, cross + widths[col]
		else rect.MinX, rect.MaxX, rect.MinZ, rect.MaxZ = cross, cross + widths[col], normalLow, normalHigh end
		addHall(layout, rng, leaf, leafIndex, rect)
	end
	return true
end

local function geometry(layout, rng)
	local leaves = split(rng, layout.Bounds)
	if not leaves then return false, "kit BSP cannot fit six lattice bands" end
	local draft = {Bounds = layout.Bounds, Halls = {}, SmallRooms = {}}
	for index, leaf in ipairs(leaves) do bigHall(draft, rng, leaf, index) end
	-- Draw the mix once per plan, then shuffle its pockets. Independent leaf
	-- rolls made the owner-selected hall maze drift into a field of small rooms.
	local candidates = {}
	for i = 2, #leaves do table.insert(candidates, i) end
	shuffle(rng, candidates)
	local clusterCount = rng:NextInteger(6, 7)
	local roomBudget = rng:NextInteger(17, 22)
	local clusters, anchors, capacities = {}, {}, {}
	for i = 1, clusterCount do clusters[candidates[i]] = true end
	local capacity = 0
	for index, leaf in ipairs(leaves) do
		local anchor, bestOverlap = nil, 0
		if clusters[index] then
			for j, other in ipairs(draft.Halls) do
				if not clusters[j] and other.Footprint ~= "GrandSlideHall" then
					local axis, from, to = facing(leaf, other.Leaf)
					if axis and from == to then
						local low, high = wallSpan(leaf, axis)
						local ol, oh = wallSpan(other, axis)
						local overlap = math.min(high, oh) - math.max(low, ol)
						if overlap > bestOverlap then anchor, bestOverlap = other, overlap end
					end
				end
			end
		end
		if anchor then
			local axis, _, _, first = facing(leaf, anchor.Leaf)
			local normalSize = axis == "X" and rectWidth(leaf) or rectDepth(leaf)
			local inset = first == anchor.Leaf and ((axis == "X" and leaf.MinX or leaf.MinZ)
				- (axis == "X" and anchor.MaxX or anchor.MaxZ))
				or ((axis == "X" and anchor.MinX or anchor.MinZ) - (axis == "X" and leaf.MaxX or leaf.MaxZ))
			anchors[index] = anchor
			capacities[index] = normalSize < inset + 144 and 2 or 4
			capacity += capacities[index]
		end
	end
	clusterCount = 0
	for _ in pairs(anchors) do clusterCount += 1 end
	roomBudget = math.clamp(roomBudget, clusterCount * 2, capacity)
	for index, leaf in ipairs(leaves) do
		local anchor, count = anchors[index], nil
		if anchor then
			clusterCount -= 1
			capacity -= capacities[index]
			count = rng:NextInteger(math.max(2, roomBudget - capacity),
				math.min(capacities[index], roomBudget - clusterCount * 2))
			roomBudget -= count
		end
		if not anchor or not smallCluster(layout, rng, leaf, index, anchor, count) then
			local hall = draft.Halls[index]
			addHall(layout, rng, leaf, index, hall)
		end
	end
	-- Tunnels first: optional passages must not consume a tunnel's envelope.
	for pass = 1, 3 do
		for i, a in ipairs(layout.Halls) do
			for j = i + 1, #layout.Halls do
				local b = layout.Halls[j]
				local small = a.Role == "Small" or b.Role == "Small"
				if (pass <= 2 and not small) or (pass == 3 and small) then connect(layout, a, b, pass) end
			end
		end
	end
	return true
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

local function separation(a, b)
	local ac, bc = rectCenter(a), rectCenter(b)
	-- Role spacing remains horizontal when the kit adds floor heights.
	return Vector3.new(ac.X - bc.X, 0, ac.Z - bc.Z).Magnitude
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

local function levelRequired(layout, corridor)
	local a, b = layout.Halls[corridor.A], layout.Halls[corridor.B]
	return corridor.Kind == "PressureDoor" or corridor.DrainGroup ~= nil
		or a.Role == "Kids Area" or b.Role == "Kids Area"
		or a == layout.Arrival or b == layout.Arrival
		or a.PumpIndex ~= nil or b.PumpIndex ~= nil
end

local function allowedHallType(hall, name)
	if name == "BigPool" then return hall.Area >= 24000 end
	if name == "VaultArcade" then
		return hall.Width >= 96 and hall.Depth >= 96
			and (hall.CeilingClass == 34 or hall.CeilingClass == 42)
	end
	if name == "CorridorHall" then
		return math.max(hall.Width, hall.Depth) / math.min(hall.Width, hall.Depth) >= 2.2
	end
	return true
end

local function drawHallType(rng, hall)
	while true do
		local roll = rng:NextInteger(1, 100)
		local total = 0
		for _, entry in ipairs(HALL_TYPES) do
			total += entry.Weight
			if roll <= total then
				if allowedHallType(hall, entry.Name) then return entry.Name end
				break
			end
		end
	end
end

local function decorate(layout)
	local rng = Random.new(layout.Seed + 0x2B1E)
	local typeRng = Random.new(layout.Seed + 0x50A7)
	local parent, heights = {}, {}
	-- Keep the live archetype weights on the separate dressing stream.
	for _, hall in ipairs(layout.Halls) do
		if hall.Role == "Hall" then
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


	local function root(i)
		while parent[i] ~= i do i = parent[i] end
		return i
	end
	local deepMax = math.clamp(Configuration.DeepEndMax or 2.0, 1.6, 3.5)
	for i, hall in ipairs(layout.Halls) do
		parent[i] = i
		heights[i] = rng:NextInteger(-2, 2) * 4
		hall.CeilingClass = ({34, 42, 52})[rng:NextInteger(1, 3)]
		if hall.Role == "Small" then hall.CeilingClass = 15
		elseif hall.Role == "Slide Hall" then hall.CeilingClass = 96 end
		if hall.Role == "Hall" then
			hall.Type = drawHallType(typeRng, hall)
			if hall.Type == "SpiralWell" and hall.CeilingClass == 34 then
				hall.CeilingClass = ({42, 52})[typeRng:NextInteger(1, 2)]
			end
		elseif hall.Role == "Arrival" then hall.Type = "Arrival"
		elseif hall.Role == "Pump Station" then hall.Type = "PumpHall"
		elseif hall.Role == "Kids Area" then hall.Type = "PaddlingRoom"
		elseif hall.Role == "Slide Hall" then hall.Type = "ExitHall"
		elseif hall.Role == "Entity Den" or hall.Role == "Entity Den B" then
			hall.Type = hall.CeilingClass == 52 and "ColumnHall"
				or (typeRng:NextInteger(0, 1) == 0 and "ColumnHall" or "VaultArcade")
		end
		hall.DeepEnd = rng:NextNumber(1.6, deepMax)
		hall.PoolAxis = hall.Width >= hall.Depth and "X" or "Z"
	end
	for _, c in ipairs(layout.Corridors) do
		local flat = levelRequired(layout, c)
		if c.Kind == "Narrow" then
			flat = flat or rng:NextNumber() >= .3
		end
		if flat then parent[root(c.B)] = root(c.A) end
	end
	-- Repair only excessive differences, toward zero. Each repair reduces a
	-- component's absolute height, so this bounded loop always terminates.
	local remaining = #layout.Halls * 2
	while remaining > 0 do
		local changed = false
		for _, c in ipairs(layout.Corridors) do
			local a, b = root(c.A), root(c.B)
			local limit = c.Kind == "Narrow" and 4 or 8
			if math.abs(heights[a] - heights[b]) > limit then
				local target = math.abs(heights[a]) >= math.abs(heights[b]) and a or b
				heights[target] -= math.sign(heights[target]) * 4
				remaining -= 1
				changed = true
			end
		end
		if not changed then break end
	end
	for i, hall in ipairs(layout.Halls) do
		hall.FloorY = heights[root(i)]
		hall.Center = rectCenter(hall)
	end
	layout.NarrowCount, layout.TunnelCount = 0, 0
	for _, c in ipairs(layout.Corridors) do
		local a, b = layout.Halls[c.A], layout.Halls[c.B]
		local first, last = a, b
		if (c.Axis == "X" and a.MinX > b.MinX) or (c.Axis == "Z" and a.MinZ > b.MinZ) then first, last = b, a end
		c.FromY, c.ToY = first.FloorY, last.FloorY
		local dy = math.abs(c.FromY - c.ToY)
		if c.Kind == "Narrow" then
			layout.NarrowCount += 1
			c.Variant = dy == 0 and "Flat" or "Stair4"
			c.PoolType = "Dry"
		else
			layout.TunnelCount += 1
			if dy > 0 then c.Variant, c.PoolType = "Stair" .. dy, "Dry"
			elseif a == layout.Arrival or b == layout.Arrival then c.Variant, c.PoolType = "Dry", "Dry"
			else c.Variant = "Wet" end
		end
	end
end

local function generateAttempt(seed)
	local rng = Random.new(seed)
	local extent = 1400 -- The kit's BSP lattice and fixed slide footprints are authored for this extent; the live generator still uses the configured extent.
	-- The plan is laid out in world coordinates around WorldCenter, which is
	-- shifted away from the persistent tunnel lobby so the two never overlap.
	local cx = Configuration.WorldCenterX or 0
	local cz = Configuration.WorldCenterZ or 0
	local layout = {
		Seed = seed,
		Version = "kit-v1",
		SmallRooms = {},
		Bounds = {
			MinX = cx - extent * .5, MaxX = cx + extent * .5,
			MinZ = cz - extent * .5, MaxZ = cz + extent * .5,
		},
		Halls = {},
		Corridors = {},
		CorridorByPair = {},
	}

	local built, geometryError = geometry(layout, rng)
	if not built then return nil, geometryError end

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
		if hall.Role ~= "Small" and d < bestCorner then bestCorner, arrival = d, hall end
	end
	layout.Arrival = arrival

	local distances = bfs(layout, arrival)
	layout.Distances = distances
	for _, hall in ipairs(layout.Halls) do
		hall.GraphDepth = distances[hall.Index] or 0
		hall.ConnectionCount = #hall.Connections
	end

	-- The easternmost eligible hall owns the exit; the other slides keep their spread.
	local bySize = table.clone(layout.Halls)
	table.sort(bySize, function(a, b)
		if a.Area == b.Area then return a.Index < b.Index end
		return a.Area > b.Area
	end)
	-- Slide halls need room for the deck, three flume lanes and the spiral:
	-- anything smaller makes the tubes clip their own furniture. The exit hall
	-- clears a larger floor again AND has to sit in the easternmost band —
	-- picking a big hall further west would stretch the flume's level lead-in
	-- to the shell into a long flat walk. A plan that cannot satisfy both is
	-- rejected here and the next attempt seed is tried; both rules are
	-- re-checked in validateLayout.
	local maximumShellGap = Configuration.ExitHallMaximumShellGap or math.huge
	local exitCandidates = {}
	for _, hall in ipairs(bySize) do
		if hall ~= arrival and hall.GraphDepth >= 1
			and hall.Footprint == "GrandSlideHall"
			and layout.Bounds.MaxX - hall.MaxX <= maximumShellGap then
			table.insert(exitCandidates, hall)
		end
	end
	if #exitCandidates == 0 then
		return nil, "no eastern hall clears the exit hall minimum size"
	end
	local eastExitHall = exitCandidates[1]
	for _, hall in ipairs(exitCandidates) do
		if hall.MaxX > eastExitHall.MaxX
			or (hall.MaxX == eastExitHall.MaxX and hall.Index < eastExitHall.Index) then
			eastExitHall = hall
		end
	end
	local slideHalls = {eastExitHall}
	layout.SlideHalls = slideHalls
	layout.GrandSlideHall = eastExitHall

	local protected = {[arrival] = true}
	for _, hall in ipairs(layout.Halls) do if hall.Role == "Small" then protected[hall] = true end end
	for _, hall in ipairs(slideHalls) do protected[hall] = true end

	-- Kids play area: a contiguous run of halls beyond the first rooms after
	-- spawn. This keeps the arrival route neutral before the childlike wing is
	-- discovered, and never lets a depth-one hall become part of Kids Area.
	-- It is selected before the pumps because exactly one objective pump belongs
	-- inside this wing on every generated layout.
	-- Kids rooms stay cosy; their quantized tunnel gaps are not merged.
	local function kidsSized(hall)
		return hall.Role ~= "Small" and math.max(hall.Width, hall.Depth) <= 200
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
			if corridor.Kind == "Narrow" then return nil, "grand hall cannot have service passages" end
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
	-- Kids-wing corridors wear the kids tiles end to end and share the kids
	-- rooms' wading-water surface; draining one reads as a broken kids room.
	-- Hall roles are not assigned yet at this point, so kids membership comes
	-- from the grown kids block itself. The visible pump feedback sticks to
	-- plain corridors — the kids-area pump drains its nearest ordinary tunnel.
	local kidsHallIndexes = {}
	for _, hall in ipairs(layout.KidsArea or {}) do
		kidsHallIndexes[hall.Index] = true
	end
	local drainables = {}
	for _, corridor in ipairs(layout.Corridors) do
		if corridor.Kind == "Open" and corridor.Length >= Configuration.MinimumDrainableLength
			and not kidsHallIndexes[corridor.A] and not kidsHallIndexes[corridor.B]
			and corridor.A ~= arrival.Index and corridor.B ~= arrival.Index then
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
		hall.Archetype = "Grand Slide Hall"
		hall.SlideHallIndex = index
		hall.Prefab = "GrandSlideHall"
	end

	for index, hall in ipairs(pumps) do
		hall.Role = "Pump Station"
		hall.PumpIndex = index
		hall.PoolType = "Dry"
		hall.Archetype = "Pump Station"
	end

	-- Three colors total across the kids block, and no
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

	decorate(layout)
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

local function validateKit(layout)
	local function bad(reason) return false, "kit: " .. reason end
	if layout.Version ~= "kit-v1" then return bad("version") end
	local smallSet, leafRooms = {}, {}
	for _, index in ipairs(layout.SmallRooms) do
		if smallSet[index] or not layout.Halls[index] or layout.Halls[index].Role ~= "Small" then return bad("small-room list") end
		smallSet[index] = true
	end
	local named = {layout.Arrival, layout.EntityDen, layout.EntityDenB}
	for _, list in ipairs({layout.SlideHalls, layout.PumpHalls, layout.KidsArea}) do
		for _, hall in ipairs(list) do table.insert(named, hall) end
	end
	if not layout.EntityDenB or layout.EntityDen == layout.EntityDenB then return bad("two distinct dens required") end
	for _, hall in ipairs(named) do
		if layout.Halls[hall.Index] ~= hall or hall.Role == "Small" then return bad("invalid named hall") end
	end
	if layout.Arrival.Role ~= "Arrival" or layout.Arrival.PoolType ~= "Dry" then return bad("arrival role") end
	local denA, denB = layout.EntityDen, layout.EntityDenB
	if denA.Role ~= "Entity Den" or denB.Role ~= "Entity Den B" then return bad("den roles") end
	if #layout.SlideHalls ~= 1 or layout.SlideHalls[1] ~= layout.GrandSlideHall then return bad("slide count") end
	for i, hall in ipairs(layout.SlideHalls) do
		if hall.Role ~= "Slide Hall" or hall.PoolType ~= "Slide" or hall.SlideHallIndex ~= i
			or hall.IsGrand ~= (hall == layout.GrandSlideHall) then return bad("slide role") end
		for j = i + 1, #layout.SlideHalls do
			if separation(hall, layout.SlideHalls[j]) < Configuration.SlideHallSeparation then return bad("slide spacing") end
		end
	end
	local colors = {}
	for i, hall in ipairs(layout.KidsArea) do
		if hall.Role ~= "Kids Area" or hall.KidsIndex ~= i or hall.GraphDepth < 2
			or math.max(hall.Width, hall.Depth) > 200
			or hall.PoolType ~= (i == 1 and "KidsShallow" or "KidsDry") then return bad("kids role") end
		local used = {}
		for _, other in ipairs(hall.Connections) do if colors[other] then used[colors[other]] = true end end
		local expected
		for offset = 0, #Configuration.KidsColors - 1 do
			local color = ((i - 1 + offset) % #Configuration.KidsColors) + 1
			if not used[color] then expected = color break end
		end
		expected = expected or (((i - 1) % #Configuration.KidsColors) + 1)
		if hall.KidsColorIndex ~= expected then return bad("kids color") end
		colors[hall.Index] = expected
	end
	local smallCount = 0
	for i, hall in ipairs(layout.Halls) do
		for _, value in ipairs({hall.MinX, hall.MaxX, hall.MinZ, hall.MaxZ,
			hall.Leaf.MinX, hall.Leaf.MaxX, hall.Leaf.MinZ, hall.Leaf.MaxZ}) do
			if value % 4 ~= 0 then return bad("room/leaf lattice") end
		end
		if hall.MinX < hall.Leaf.MinX or hall.MaxX > hall.Leaf.MaxX
			or hall.MinZ < hall.Leaf.MinZ or hall.MaxZ > hall.Leaf.MaxZ then return bad("room outside leaf") end
		if hall.Leaf.MinX < layout.Bounds.MinX or hall.Leaf.MaxX > layout.Bounds.MaxX
			or hall.Leaf.MinZ < layout.Bounds.MinZ or hall.Leaf.MaxZ > layout.Bounds.MaxZ then return bad("leaf outside bounds") end
		local group = leafRooms[hall.LeafIndex] or {}
		leafRooms[hall.LeafIndex] = group
		table.insert(group, hall)
		if hall.Width ~= rectWidth(hall) or hall.Depth ~= rectDepth(hall)
			or hall.Area ~= hall.Width * hall.Depth or hall.Center.X ~= (hall.MinX + hall.MaxX) / 2
			or hall.Center.Z ~= (hall.MinZ + hall.MaxZ) / 2 or hall.Center.Y ~= hall.FloorY then return bad("cached hall geometry") end
		if not table.find({-8, -4, 0, 4, 8}, hall.FloorY) then return bad("floor class") end
		if hall.DeepEnd < 1.6 or hall.DeepEnd > math.clamp(Configuration.DeepEndMax or 2, 1.6, 3.5) then return bad("deep end") end
		if hall.PoolAxis ~= (hall.Width >= hall.Depth and "X" or "Z") then return bad("pool axis") end
		if hall.Role == "Small" then
			smallCount += 1
			if not smallSet[i] or hall.PoolType ~= "Dry" then return bad("small-room fields") end
			local prefab
			for _, candidate in ipairs(SMALL_PREFABS) do if hall.Prefab == candidate.Name then prefab = candidate break end end
			if not prefab or not table.find({0, 90, 180, 270}, hall.Rotation) then return bad("small prefab/rotation") end
			local w, d = prefab.Width, prefab.Depth
			if hall.Rotation % 180 == 90 then w, d = d, w end
			if hall.Width ~= w or hall.Depth ~= d or hall.Archetype ~= prefab.Archetype
				or hall.Type ~= "Chamber" or hall.CeilingClass ~= prefab.Ceiling then return bad("small footprint") end
		else
			if hall.Width < 96 or hall.Depth < 96 or hall.Width > 272 or hall.Depth > 272 then return bad("big footprint") end
			for _, inset in ipairs({hall.MinX - hall.Leaf.MinX, hall.Leaf.MaxX - hall.MaxX,
				hall.MinZ - hall.Leaf.MinZ, hall.Leaf.MaxZ - hall.MaxZ}) do
				if inset ~= 32 and inset ~= 40 then return bad("big hall inset") end
			end
			if hall.Role == "Slide Hall" then
				if not hall.IsGrand or hall.Prefab ~= "GrandSlideHall" or hall.Width ~= 224 or hall.Depth ~= 208
					or hall.CeilingClass ~= 96 or hall.Type ~= "ExitHall"
					or hall.Leaf.MaxX ~= layout.Bounds.MaxX then return bad("grand prefab") end
			elseif not table.find({34, 42, 52}, hall.CeilingClass) then return bad("ceiling class") end
			if hall.Role == "Hall" then
				local known = false
				for _, entry in ipairs(HALL_TYPES) do if entry.Name == hall.Type then known = true break end end
				if not known or not allowedHallType(hall, hall.Type)
					or (hall.Type == "SpiralWell" and hall.CeilingClass == 34) then return bad("hall type") end
			elseif hall.Role == "Arrival" and hall.Type ~= "Arrival"
				or hall.Role == "Pump Station" and hall.Type ~= "PumpHall"
				or hall.Role == "Kids Area" and hall.Type ~= "PaddlingRoom"
				or (hall.Role == "Entity Den" or hall.Role == "Entity Den B")
					and (hall.Type ~= "ColumnHall" and hall.Type ~= "VaultArcade"
						or not allowedHallType(hall, hall.Type)) then return bad("role type") end
		end
		for j = i + 1, #layout.Halls do
			local other = layout.Halls[j]
			if intersects(hall, other, false) then return bad("overlapping rooms") end
			local dx = math.max(0, hall.MinX - other.MaxX, other.MinX - hall.MaxX)
			local dz = math.max(0, hall.MinZ - other.MaxZ, other.MinZ - hall.MaxZ)
			local pair = i .. ":" .. j
			if not layout.CorridorByPair[pair] and math.sqrt(dx * dx + dz * dz) < 16 then return bad("non-adjacent clearance") end
			if hall.Role ~= "Small" and other.Role ~= "Small" then
				local axis, from, to = facing(hall, other)
				if axis and to - from <= 80 then
					local low, high = wallSpan(hall, axis)
					local ol, oh = wallSpan(other, axis)
					local overlap = math.min(high, oh) - math.max(low, ol)
					if overlap >= 28 and overlap < 42 then
						local c = layout.CorridorByPair[pair]
						if not c or c.Kind ~= "Narrow" then return bad("missing required big-hall passage") end
					end
				end
			end
		end
	end
	if smallCount ~= #layout.SmallRooms then return bad("small count") end
	for _, group in pairs(leafRooms) do
		if group[1].Role == "Small" then
			if #group < 2 or #group > 4 then return bad("cluster size") end
			for _, hall in ipairs(group) do if hall.Role ~= "Small" then return bad("mixed leaf") end end
		elseif #group ~= 1 then return bad("big leaf count") end
	end
	local narrow, tunnel, blocked, drains = 0, 0, {}, {}
	for i, c in ipairs(layout.Corridors) do
		local a, b = layout.Halls[c.A], layout.Halls[c.B]
		local axis, from, to, first, last = facing(a, b)
		if axis ~= c.Axis or from ~= c.From or to ~= c.To or c.Length ~= c.To - c.From or c.Cross % 4 ~= 0 then return bad("corridor gap/lattice") end
		if c.FromY ~= first.FloorY or c.ToY ~= last.FloorY then return bad("corridor endpoint Y") end
		local dy = math.abs(c.FromY - c.ToY)
		if dy > 8 or (levelRequired(layout, c) and dy ~= 0) then return bad("height constraint") end
		local al, ah = wallSpan(a, axis)
		local bl, bh = wallSpan(b, axis)
		local overlap = math.min(ah, bh) - math.max(al, bl)
		local variant
		if c.Kind == "Narrow" then
			narrow += 1
			blocked[i] = true
			if c.Width ~= 12 or not PASSAGE_LENGTHS[c.Length] or c.DrainGroup ~= nil
				or (a.Role ~= "Small" and b.Role ~= "Small" and (overlap < 28 or overlap >= 42))
				or not socket(a, axis, c.Cross, 8) or not socket(b, axis, c.Cross, 8)
				or (dy ~= 0 and dy ~= 4) or c.PoolType ~= "Dry" then return bad("passage envelope/socket") end
			variant = dy == 0 and "Flat" or "Stair4"
		else
			tunnel += 1
			if a.Role == "Small" or b.Role == "Small" or (c.Kind ~= "Open" and c.Kind ~= "PressureDoor")
				or c.Width ~= 34 or overlap < 42 or not TUNNEL_LENGTHS[c.Length]
				or not socket(a, axis, c.Cross, 21) or not socket(b, axis, c.Cross, 21) then return bad("tunnel envelope") end
			if dy > 0 then variant = "Stair" .. dy
			elseif a == layout.Arrival or b == layout.Arrival then variant = "Dry"
			else variant = "Wet" end
		end
		if c.Variant ~= variant or (dy > 0 and c.PoolType ~= "Dry") then return bad("corridor variant") end
		if a == layout.GrandSlideHall or b == layout.GrandSlideHall then
			if c.Kind ~= "PressureDoor" then return bad("unguarded grand corridor") end
		end
		if c.DrainGroup then
			if c.Kind ~= "Open" or a.Role == "Kids Area" or b.Role == "Kids Area"
				or a == layout.Arrival or b == layout.Arrival
				or c.PoolType ~= "Deep" or c.Variant ~= "Wet" then return bad("drain eligibility") end
			drains[c.DrainGroup] = true
		end
		local rect = corridorRect(c)
		for _, hall in ipairs(layout.Halls) do
			if hall ~= a and hall ~= b and intersects(rect, hall, true) then return bad("corridor touches third room") end
		end
		for j = i + 1, #layout.Corridors do
			if intersects(rect, corridorRect(layout.Corridors[j]), true) then return bad("corridor intersection") end
		end
	end
	if narrow ~= layout.NarrowCount or tunnel ~= layout.TunnelCount then return bad("corridor counts") end
	for i = 1, 3 do if not drains[i] then return bad("missing drain") end end
	local allDistances = bfs(layout, layout.Arrival)
	for i, hall in ipairs(layout.Halls) do
		if hall.GraphDepth ~= allDistances[i] or layout.Distances[i] ~= allDistances[i]
			or hall.ConnectionCount ~= #hall.Connections then return bad("cached graph fields") end
	end
	for i, corridor in ipairs(layout.Corridors) do
		if corridor.Kind == "PressureDoor" then blocked[i] = true end
	end
	local bigDistances = bfs(layout, layout.Arrival, blocked)
	for _, hall in ipairs(layout.Halls) do
		if hall.Role ~= "Small" and hall ~= layout.GrandSlideHall and bigDistances[hall.Index] == nil then
			return bad("open tunnel graph disconnected")
		end
	end
	return true
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
		or #layout.SlideHalls ~= 1 then
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
	local exitMinimumWidth, exitMinimumDepth = exitHallMinimums()
	if not isFiniteNumber(layout.GrandSlideHall.Width)
		or not isFiniteNumber(layout.GrandSlideHall.Depth)
		or layout.GrandSlideHall.Width + INSET_EPSILON < exitMinimumWidth
		or layout.GrandSlideHall.Depth + INSET_EPSILON < exitMinimumDepth then
		return invalid("exit hall is below the exit hall minimum size")
	end
	local maximumShellGap = Configuration.ExitHallMaximumShellGap
	if isFiniteNumber(maximumShellGap) and type(layout.Bounds) == "table"
		and isFiniteNumber(layout.Bounds.MaxX)
		and layout.Bounds.MaxX - layout.GrandSlideHall.MaxX
			> maximumShellGap + INSET_EPSILON then
		return invalid("exit hall is too far west of the east shell")
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
		if hall.Role ~= "Small" and (rectWidth(hall) + INSET_EPSILON < 96
			or rectDepth(hall) + INSET_EPSILON < 96) then
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
	return validateKit(layout)
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

-- options.AllowRandomRecovery is set by callers that picked the seed at random
-- (i.e. no manual Level2Seed override). Those rounds get one more independently
-- seeded stride before the checked-in recovery seeds, because those seeds build
-- an IDENTICAL map every time they are reached. A pinned seed deliberately does
-- not get that, so a pinned failure stays reproducible.
function LayoutGenerator.Generate(seed, options)
	seed = normalizeSeed(seed, true)
	local allowRandomRecovery = type(options) == "table"
		and options.AllowRandomRecovery == true
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

	if allowRandomRecovery then
		local recoverySeed = normalizeSeed(
			DateTime.now().UnixTimestampMillis + Random.new():NextInteger(0, MAX_SEED - 1),
			true
		)
		layout = trySequence(recoverySeed, primaryAttempts, nil)
		if layout then
			layout.RandomRecoverySeed = recoverySeed
			return layout
		end
	end

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
