local Configuration = require(script.Parent:WaitForChild("Level 2 Configuration"))

local LayoutGenerator = {}

local DIRECTIONS = {
	{name = "North", dx = 0, dz = -1, opposite = "South"},
	{name = "East", dx = 1, dz = 0, opposite = "West"},
	{name = "South", dx = 0, dz = 1, opposite = "North"},
	{name = "West", dx = -1, dz = 0, opposite = "East"},
}

local function key(x, z)
	return tostring(x) .. ":" .. tostring(z)
end

local function shuffled(rng, source)
	local result = table.clone(source)
	for index = #result, 2, -1 do
		local swap = rng:NextInteger(1, index)
		result[index], result[swap] = result[swap], result[index]
	end
	return result
end

local function bfs(layout, startRoom)
	local distances = {[startRoom.Id] = 0}
	local queue = {startRoom}
	local head = 1
	while head <= #queue do
		local room = queue[head]
		head += 1
		for _, direction in ipairs(DIRECTIONS) do
			if room.Connections[direction.name] then
				local other = layout.RoomByKey[key(room.X + direction.dx, room.Z + direction.dz)]
				if other and distances[other.Id] == nil then
					distances[other.Id] = distances[room.Id] + 1
					table.insert(queue, other)
				end
			end
		end
	end
	return distances
end

local function chooseSeparated(candidates, distances, count)
	local chosen = {}
	for _, candidate in ipairs(candidates) do
		local acceptable = distances[candidate.Id] >= Configuration.MinimumValveDistance
		for _, existing in ipairs(chosen) do
			local separation = math.abs(candidate.X - existing.X) + math.abs(candidate.Z - existing.Z)
			if separation < Configuration.MinimumValveSeparation then
				acceptable = false
				break
			end
		end
		if acceptable then
			table.insert(chosen, candidate)
			if #chosen == count then break end
		end
	end
	return chosen
end

local function connectionCount(room)
	local count = 0
	for _, connected in pairs(room.Connections) do
		if connected then count += 1 end
	end
	return count
end

local function orientationFor(room, rng)
	local eastWest = (room.Connections.East and 1 or 0) + (room.Connections.West and 1 or 0)
	local northSouth = (room.Connections.North and 1 or 0) + (room.Connections.South and 1 or 0)
	if eastWest > northSouth then return "EastWest" end
	if northSouth > eastWest then return "NorthSouth" end
	return rng:NextNumber() < .5 and "EastWest" or "NorthSouth"
end

local function randomArchetype(room, rng)
	if room.PoolType == "Dry" then
		local choices = {"Dry Gallery", "Porthole Hall", "Stair Overlook", "Atrium Landing"}
		return choices[rng:NextInteger(1, #choices)]
	elseif room.PoolType == "Deep" then
		local choices = {"Sunken Pool", "Pillar Basin", "Grand Basin"}
		return choices[rng:NextInteger(1, #choices)]
	elseif room.PoolType == "Arch" then
		return rng:NextNumber() < .55 and "Arch Crypt" or "Vaulted Passage"
	else
		local choices = {"Flooded Gallery", "Channel Junction", "Bright Basin", "Low Water Hall", "Flooded Bend"}
		return choices[rng:NextInteger(1, #choices)]
	end
end

local MANDATORY_ARCHETYPES = {
	{"Flooded Gallery", "Shallow"},
	{"Channel Junction", "Shallow"},
	{"Arch Crypt", "Arch"},
	{"Sunken Pool", "Deep"},
	{"Pillar Basin", "Deep"},
	{"Long Gallery", "Shallow"},
	{"Stair Overlook", "Dry"},
	{"Porthole Hall", "Dry"},
}

local function generateAttempt(seed)
	local rng = Random.new(seed)
	local size = Configuration.GridSize
	local layout = {
		Seed = seed,
		Version = Configuration.Version,
		Rooms = {},
		RoomByKey = {},
	}

	for z = 1, size do
		for x = 1, size do
			local room = {
				Id = string.format("Level 2 Room %02d", #layout.Rooms + 1),
				X = x,
				Z = z,
				Role = "Pool",
				PoolType = "Dry",
				Connections = {North = false, East = false, South = false, West = false},
			}
			table.insert(layout.Rooms, room)
			layout.RoomByKey[key(x, z)] = room
		end
	end

	local visited = {}
	local start = layout.RoomByKey[key(1, 1)]
	local stack = {start}
	visited[start.Id] = true
	while #stack > 0 do
		local current = stack[#stack]
		local choices = {}
		for _, direction in ipairs(shuffled(rng, DIRECTIONS)) do
			local nx, nz = current.X + direction.dx, current.Z + direction.dz
			local neighbor = layout.RoomByKey[key(nx, nz)]
			if neighbor and not visited[neighbor.Id] then
				table.insert(choices, {direction = direction, room = neighbor})
			end
		end
		if #choices == 0 then
			table.remove(stack)
		else
			local choice = choices[1]
			current.Connections[choice.direction.name] = true
			choice.room.Connections[choice.direction.opposite] = true
			visited[choice.room.Id] = true
			table.insert(stack, choice.room)
		end
	end

	for _, room in ipairs(layout.Rooms) do
		for _, direction in ipairs({DIRECTIONS[2], DIRECTIONS[3]}) do
			local neighbor = layout.RoomByKey[key(room.X + direction.dx, room.Z + direction.dz)]
			if neighbor and not room.Connections[direction.name] and rng:NextNumber() < Configuration.ExtraConnectionChance then
				room.Connections[direction.name] = true
				neighbor.Connections[direction.opposite] = true
			end
		end
	end

	layout.Arrival = start
	local distances = bfs(layout, start)
	layout.Distances = distances
	local boundary = {}
	for _, room in ipairs(layout.Rooms) do
		if room.X == 1 or room.X == size or room.Z == 1 or room.Z == size then
			table.insert(boundary, room)
		end
	end
	table.sort(boundary, function(a, b) return distances[a.Id] > distances[b.Id] end)
	layout.Exit = boundary[1]

	local centerCandidates = table.clone(layout.Rooms)
	table.sort(centerCandidates, function(a, b)
		local ac = math.abs(a.X - (size + 1) * .5) + math.abs(a.Z - (size + 1) * .5)
		local bc = math.abs(b.X - (size + 1) * .5) + math.abs(b.Z - (size + 1) * .5)
		if ac == bc then return distances[a.Id] > distances[b.Id] end
		return ac < bc
	end)
	layout.GrandRoom = centerCandidates[1]

	local candidates = {}
	for _, room in ipairs(layout.Rooms) do
		if room ~= start and room ~= layout.Exit and room ~= layout.GrandRoom then
			table.insert(candidates, room)
		end
	end
	table.sort(candidates, function(a, b)
		if distances[a.Id] == distances[b.Id] then return a.Id < b.Id end
		return distances[a.Id] > distances[b.Id]
	end)
	layout.Valves = chooseSeparated(candidates, distances, 3)
	if #layout.Valves < 3 then return nil, "valves could not be separated" end

	for _, room in ipairs(layout.Rooms) do
		local roll = rng:NextNumber()
		room.PoolType = roll < .24 and "Deep" or (roll < .62 and "Shallow" or (roll < .78 and "Arch" or "Dry"))
		room.GraphDepth = distances[room.Id]
		room.LocalSeed = rng:NextInteger(1, 2^30)
		room.ConnectionCount = connectionCount(room)
		room.Orientation = orientationFor(room, rng)
		room.Archetype = randomArchetype(room, rng)
	end

	start.Role, start.PoolType, start.Archetype = "Arrival", "Dry", "Arrival Gallery"
	layout.Exit.Role, layout.Exit.PoolType, layout.Exit.Archetype = "Exit", "Dry", "Exit Gallery"
	layout.GrandRoom.Role, layout.GrandRoom.PoolType, layout.GrandRoom.Archetype = "Grand Pool", "Grand", "Grand Column Hall"
	layout.Valves[1].Role, layout.Valves[1].PoolType, layout.Valves[1].Archetype = "Column Valve", "Column", "Pillar Basin"
	layout.Valves[2].Role, layout.Valves[2].PoolType, layout.Valves[2].Archetype = "Reflection Valve", "Reflection", "Flooded Gallery"
	layout.Valves[3].Role, layout.Valves[3].PoolType, layout.Valves[3].Archetype = "Children Valve", "Children", "Arch Crypt"

	local protected = {
		[start] = true,
		[layout.Exit] = true,
		[layout.GrandRoom] = true,
		[layout.Valves[1]] = true,
		[layout.Valves[2]] = true,
		[layout.Valves[3]] = true,
	}
	local archetypeCandidates = {}
	for _, room in ipairs(candidates) do
		if not protected[room] then table.insert(archetypeCandidates, room) end
	end
	table.sort(archetypeCandidates, function(a, b)
		if a.ConnectionCount == b.ConnectionCount then return a.GraphDepth > b.GraphDepth end
		return a.ConnectionCount > b.ConnectionCount
	end)
	for index, definition in ipairs(MANDATORY_ARCHETYPES) do
		local room = archetypeCandidates[index]
		if room then
			room.Archetype = definition[1]
			room.PoolType = definition[2]
		end
	end

	if layout.Exit.X == size then layout.ExitSide = "East"
	elseif layout.Exit.Z == size then layout.ExitSide = "South"
	elseif layout.Exit.X == 1 then layout.ExitSide = "West"
	else layout.ExitSide = "North" end

	local reached = 0
	for _ in pairs(distances) do reached += 1 end
	if reached ~= #layout.Rooms then return nil, "layout disconnected" end
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
	error("Level 2 layout generation failed: " .. tostring(lastError))
end

return LayoutGenerator
