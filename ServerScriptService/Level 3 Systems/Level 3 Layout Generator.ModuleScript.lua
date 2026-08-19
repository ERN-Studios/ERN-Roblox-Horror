--!strict
-- Level 3 Layout Generator
-- Deterministic, server-side plan generation for the Mall Backrooms Party.
--
-- The generator deliberately emits only straight, axis-aligned connections and
-- reserves at most one connection on each side of every room. That contract lets
-- the current Level 3 World Builder cut one centered opening per side without
-- overlapping doors or producing diagonal corridors.

local Configuration = require(script.Parent:WaitForChild("Level 3 Configuration"))

local LayoutGenerator = {}

local VERSION = 1
local DISTRICT_COUNT = 3
local ROOMS_PER_DISTRICT = 8
local GRID_ROWS = 2
local GRID_COLUMNS = 4
local MODULE_GOAL = 5
local ENTRY_AND_GATEWAY_LINKS = 4
local MAX_SEED = 2147483646

-- The district sizing is structural: ROOMS_PER_DISTRICT is the 2x4 room grid.
-- Configuration.Layout advertises the same numbers to the test suite and world
-- builder, so a config edit that the generator cannot honor must fail loudly
-- instead of silently generating the old shape.
assert(Configuration.Layout.DistrictCount == DISTRICT_COUNT
	and Configuration.Layout.RoomsPerDistrict == ROOMS_PER_DISTRICT
	and ROOMS_PER_DISTRICT == GRID_ROWS * GRID_COLUMNS
	and Configuration.Layout.GeneratorVersion == VERSION,
	"Level 3 Configuration.Layout district sizing drifted from the generator's fixed grid")

local DEFAULTS = {
	GenerationAttempts = 24,
	RetryStride = 104729,
	FallbackSeeds = {101, 7331, 65537, 1900813},
	MinimumRoomWidth = 60,
	MaximumRoomWidth = 78,
	MinimumRoomDepth = 48,
	MaximumRoomDepth = 62,
	MinimumRoomHeight = 11,
	MaximumRoomHeight = 13,
	MinimumInternalGap = 24,
	MaximumInternalGap = 34,
	MinimumGatewayGap = 38,
	MaximumGatewayGap = 48,
	MinimumCorridorLength = 18,
	RowHalfSpacing = 62,
	ExtraLinksPerDistrict = 2,
	MinimumModuleSeparation = 105,
	ArrivalWidth = 64,
	ArrivalDepth = 54,
	ExitWidth = 58,
	ExitDepth = 52,
}

local configuredLayout = if type((Configuration :: any).Layout) == "table"
	then (Configuration :: any).Layout else {}

local function integerSetting(name, defaultValue, minimum, maximum)
	local value = tonumber(configuredLayout[name])
	if value == nil then value = defaultValue end
	value = math.floor(value)
	return math.clamp(value, minimum, maximum)
end

local function numberSetting(name, defaultValue, minimum, maximum)
	local value = tonumber(configuredLayout[name])
	if value == nil then value = defaultValue end
	return math.clamp(value, minimum, maximum)
end

local fallbackSeeds = {}
if type(configuredLayout.FallbackSeeds) == "table" then
	for _, value in ipairs(configuredLayout.FallbackSeeds) do
		local numeric = tonumber(value)
		if numeric then table.insert(fallbackSeeds, math.floor(math.abs(numeric)) % MAX_SEED) end
	end
end
if #fallbackSeeds == 0 then fallbackSeeds = table.clone(DEFAULTS.FallbackSeeds) end

local Tuning = {
	GenerationAttempts = integerSetting("GenerationAttempts", DEFAULTS.GenerationAttempts, 1, 100),
	RetryStride = integerSetting("RetryStride", DEFAULTS.RetryStride, 1, MAX_SEED - 1),
	FallbackSeeds = fallbackSeeds,
	MinimumRoomWidth = integerSetting("MinimumRoomWidth", DEFAULTS.MinimumRoomWidth, 48, 100),
	MaximumRoomWidth = integerSetting("MaximumRoomWidth", DEFAULTS.MaximumRoomWidth, 48, 120),
	MinimumRoomDepth = integerSetting("MinimumRoomDepth", DEFAULTS.MinimumRoomDepth, 40, 90),
	MaximumRoomDepth = integerSetting("MaximumRoomDepth", DEFAULTS.MaximumRoomDepth, 40, 100),
	MinimumRoomHeight = integerSetting("MinimumRoomHeight", DEFAULTS.MinimumRoomHeight, 10, 16),
	MaximumRoomHeight = integerSetting("MaximumRoomHeight", DEFAULTS.MaximumRoomHeight, 10, 18),
	MinimumInternalGap = integerSetting("MinimumInternalGap", DEFAULTS.MinimumInternalGap, 18, 60),
	MaximumInternalGap = integerSetting("MaximumInternalGap", DEFAULTS.MaximumInternalGap, 18, 70),
	MinimumGatewayGap = integerSetting("MinimumGatewayGap", DEFAULTS.MinimumGatewayGap, 24, 80),
	MaximumGatewayGap = integerSetting("MaximumGatewayGap", DEFAULTS.MaximumGatewayGap, 24, 90),
	MinimumCorridorLength = numberSetting("MinimumCorridorLength", DEFAULTS.MinimumCorridorLength, 12, 40),
	RowHalfSpacing = integerSetting("RowHalfSpacing", DEFAULTS.RowHalfSpacing, 48, 100),
	ExtraLinksPerDistrict = integerSetting("ExtraLinksPerDistrict", DEFAULTS.ExtraLinksPerDistrict, 0, 3),
	MinimumModuleSeparation = numberSetting("MinimumModuleSeparation", DEFAULTS.MinimumModuleSeparation, 60, 220),
	ArrivalWidth = integerSetting("ArrivalWidth", DEFAULTS.ArrivalWidth, 52, 90),
	ArrivalDepth = integerSetting("ArrivalDepth", DEFAULTS.ArrivalDepth, 44, 80),
	ExitWidth = integerSetting("ExitWidth", DEFAULTS.ExitWidth, 48, 80),
	ExitDepth = integerSetting("ExitDepth", DEFAULTS.ExitDepth, 44, 76),
}

if Tuning.MinimumRoomWidth > Tuning.MaximumRoomWidth then
	Tuning.MinimumRoomWidth, Tuning.MaximumRoomWidth = Tuning.MaximumRoomWidth, Tuning.MinimumRoomWidth
end
if Tuning.MinimumRoomDepth > Tuning.MaximumRoomDepth then
	Tuning.MinimumRoomDepth, Tuning.MaximumRoomDepth = Tuning.MaximumRoomDepth, Tuning.MinimumRoomDepth
end
if Tuning.MinimumRoomHeight > Tuning.MaximumRoomHeight then
	Tuning.MinimumRoomHeight, Tuning.MaximumRoomHeight = Tuning.MaximumRoomHeight, Tuning.MinimumRoomHeight
end
if Tuning.MinimumInternalGap > Tuning.MaximumInternalGap then
	Tuning.MinimumInternalGap, Tuning.MaximumInternalGap = Tuning.MaximumInternalGap, Tuning.MinimumInternalGap
end
if Tuning.MinimumGatewayGap > Tuning.MaximumGatewayGap then
	Tuning.MinimumGatewayGap, Tuning.MaximumGatewayGap = Tuning.MaximumGatewayGap, Tuning.MinimumGatewayGap
end

local DISTRICT_DEFINITIONS = {
	{
		Id = "CITY",
		Name = "Beige City Party Rooms",
		ThemeId = "City",
		Kind = "City",
		DecorPool = {
			"KidsCafeteria", "ForgottenPair", "WhiteClassroom", "CityCafe",
			"KidsCluster", "WhiteAtrium", "SparseGallery", "SparseWelcome",
		},
	},
	{
		Id = "ORANGE_BLACK",
		Name = "Orange and Black Party Rooms",
		ThemeId = "OrangeBlackParty",
		Kind = "PartyHall",
		DecorPool = {
			"SparseWelcome", "DanceFloor", "SparseGallery", "BanquetRows",
			"BirthdayCenter", "AfterParty", "AbandonedCelebration", "GrandBanquet",
		},
	},
	{
		Id = "RED_PARTY",
		Name = "Red Carpet Party Rooms",
		ThemeId = "RedParty",
		Kind = "Party",
		DecorPool = {
			"BanquetRows", "BirthdayCenter", "AfterParty", "GrandBanquet",
			"AbandonedCelebration", "DanceFloor", "SparseGallery", "SparseWelcome",
		},
	},
}

local function copyArray(source)
	local result = {}
	for index, value in ipairs(source) do result[index] = value end
	return result
end

local function shuffled(rng, source)
	local result = copyArray(source)
	for index = #result, 2, -1 do
		local swapIndex = rng:NextInteger(1, index)
		result[index], result[swapIndex] = result[swapIndex], result[index]
	end
	return result
end

local function normalizeSeed(value)
	local numeric = tonumber(value)
	if numeric == nil then
		numeric = DateTime.now().UnixTimestampMillis
	end
	numeric = math.floor(math.abs(numeric)) % MAX_SEED
	if numeric == 0 then numeric = 1 end
	return numeric
end

local function pairKey(a, b)
	if a < b then return a .. "|" .. b end
	return b .. "|" .. a
end

local function gridIndex(row, column)
	return (row - 1) * GRID_COLUMNS + column
end

local function cardinalSide(a, b)
	local dx, dz = b.X - a.X, b.Z - a.Z
	if math.abs(dz) < 0.001 and math.abs(dx) >= 0.001 then
		return if dx > 0 then "East" else "West"
	end
	if math.abs(dx) < 0.001 and math.abs(dz) >= 0.001 then
		return if dz > 0 then "South" else "North"
	end
	return nil
end

local OPPOSITE_SIDE = {
	North = "South",
	South = "North",
	East = "West",
	West = "East",
}

local function planarDistance(a, b)
	local dx, dz = a.X - b.X, a.Z - b.Z
	return math.sqrt(dx * dx + dz * dz)
end

local function makeHash(layout)
	local pieces = {
		tostring(VERSION),
		tostring(layout.Seed),
		tostring(layout.Attempt),
	}
	for _, room in ipairs(layout.Rooms) do
		table.insert(pieces, string.format(
			"R:%s:%d:%d:%d:%d:%d:%s:%s:%s:%d:%d:%d",
			room.Id, room.X, room.Z, room.W, room.D, room.H,
			room.Kind, room.Decor, room.ThemeId, room.SectionIndex,
			if room.Module then 1 else 0, room.LocalSeed
		))
	end
	for _, link in ipairs(layout.Links) do
		table.insert(pieces, string.format(
			"L:%s:%s:%s:%s:%s:%d:%d",
			link.Id, link.A, link.B, link.Door, link.ThemeId,
			link.SectionIndex, if link.Gateway then 1 else 0
		))
	end
	local text = table.concat(pieces, ";")
	local hash = 5381
	for index = 1, #text do
		hash = (hash * 33 + string.byte(text, index)) % 4294967296
	end
	return string.format("L3-%d-%08x", VERSION, hash)
end

local function generateAttempt(seed, requestedSeed, attempt, usedFallback)
	local rng = Random.new(seed)
	local rowZ = {-Tuning.RowHalfSpacing, Tuning.RowHalfSpacing}
	local entryRow = rng:NextInteger(1, GRID_ROWS)
	local firstGatewayRow = rng:NextInteger(1, GRID_ROWS)
	local secondGatewayRow = rng:NextInteger(1, GRID_ROWS)
	local exitRow = rng:NextInteger(1, GRID_ROWS)

	local layout = {
		Version = VERSION,
		RequestedSeed = requestedSeed,
		Seed = seed,
		ResolvedSeed = seed,
		Attempt = attempt,
		UsedFallbackSeed = usedFallback == true,
		Rooms = {},
		Links = {},
		RoomById = {},
		LinkById = {},
		Adjacency = {},
		Districts = {},
		DistrictById = {},
		GatewayLinks = {},
		ModuleRooms = {},
		Roles = {},
	}

	local function addRoom(room)
		if layout.RoomById[room.Id] then return nil, "duplicate room id " .. room.Id end
		table.insert(layout.Rooms, room)
		layout.RoomById[room.Id] = room
		layout.Adjacency[room.Id] = {}
		return room
	end

	local arrival = addRoom({
		Id = "Arrival",
		Name = "Level 3 Arrival",
		X = 0,
		Z = rowZ[entryRow],
		W = Tuning.ArrivalWidth,
		D = Tuning.ArrivalDepth,
		H = 12,
		Kind = "PartyHall",
		Decor = "SparseWelcome",
		Module = false,
		ThemeId = "ArrivalTransition",
		SectionIndex = 0,
		DistrictId = "ARRIVAL",
		Role = "Arrival",
		HideSpotCount = 0,
		LocalSeed = rng:NextInteger(1, 2 ^ 30),
		GridRow = entryRow,
		GridColumn = 0,
	})
	if not arrival then return nil, "arrival could not be created" end

	local sectionLeft = arrival.X + arrival.W * 0.5
		+ rng:NextInteger(Tuning.MinimumGatewayGap, Tuning.MaximumGatewayGap)
	local slots = {}

	for sectionIndex, definition in ipairs(DISTRICT_DEFINITIONS) do
		local widths = {}
		local depths = {
			rng:NextInteger(Tuning.MinimumRoomDepth, Tuning.MaximumRoomDepth),
			rng:NextInteger(Tuning.MinimumRoomDepth, Tuning.MaximumRoomDepth),
		}
		for column = 1, GRID_COLUMNS do
			widths[column] = rng:NextInteger(Tuning.MinimumRoomWidth, Tuning.MaximumRoomWidth)
		end
		local gaps = {}
		for column = 1, GRID_COLUMNS - 1 do
			gaps[column] = rng:NextInteger(Tuning.MinimumInternalGap, Tuning.MaximumInternalGap)
		end
		local decors = shuffled(rng, definition.DecorPool)
		local columnCenters = {}
		local cursor = sectionLeft
		for column = 1, GRID_COLUMNS do
			columnCenters[column] = cursor + widths[column] * 0.5
			cursor += widths[column]
			if column < GRID_COLUMNS then cursor += gaps[column] end
		end
		local sectionRight = cursor
		local district = {
			Index = sectionIndex,
			Id = definition.Id,
			Name = definition.Name,
			ThemeId = definition.ThemeId,
			Kind = definition.Kind,
			RoomIds = {},
			Rooms = {},
			IncomingGatewayLinkId = "",
			OutgoingGatewayLinkId = "",
			Bounds = {
				MinX = sectionLeft,
				MaxX = sectionRight,
				MinZ = rowZ[1] - depths[1] * 0.5,
				MaxZ = rowZ[2] + depths[2] * 0.5,
			},
		}
		layout.Districts[sectionIndex] = district
		layout.DistrictById[district.Id] = district
		slots[sectionIndex] = {{}, {}}

		for row = 1, GRID_ROWS do
			for column = 1, GRID_COLUMNS do
				local slotNumber = gridIndex(row, column)
				local isSignal = sectionIndex == DISTRICT_COUNT
					and column == GRID_COLUMNS and row == exitRow
				local id = if isSignal then "SignalHall"
					else string.format("L3_S%d_R%02d", sectionIndex, slotNumber)
				local room = {
					Id = id,
					Name = if isSignal then "Signal Hall"
						else string.format("%s %02d", definition.Name, slotNumber),
					X = columnCenters[column],
					Z = rowZ[row],
					W = widths[column],
					D = depths[row],
					H = rng:NextInteger(Tuning.MinimumRoomHeight, Tuning.MaximumRoomHeight),
					Kind = definition.Kind,
					Decor = decors[slotNumber],
					Module = false,
					ThemeId = definition.ThemeId,
					SectionIndex = sectionIndex,
					DistrictId = definition.Id,
					Role = if isSignal then "SignalHall" else "Room",
					HideSpotCount = 1,
					LocalSeed = rng:NextInteger(1, 2 ^ 30),
					GridRow = row,
					GridColumn = column,
				}
				local inserted, roomError = addRoom(room)
				if not inserted then return nil, roomError end
				slots[sectionIndex][row][column] = room
				table.insert(district.Rooms, room)
				table.insert(district.RoomIds, room.Id)
			end
		end

		if sectionIndex < DISTRICT_COUNT then
			sectionLeft = sectionRight
				+ rng:NextInteger(Tuning.MinimumGatewayGap, Tuning.MaximumGatewayGap)
		end
	end

	local signalHall = layout.RoomById.SignalHall
	if not signalHall then return nil, "SignalHall was not assigned" end
	local exitGap = rng:NextInteger(Tuning.MinimumGatewayGap, Tuning.MaximumGatewayGap)
	local exitRoom = addRoom({
		Id = "Exit",
		Name = "Level 3 Exit",
		X = signalHall.X + signalHall.W * 0.5 + exitGap + Tuning.ExitWidth * 0.5,
		Z = signalHall.Z,
		W = Tuning.ExitWidth,
		D = Tuning.ExitDepth,
		H = 12,
		Kind = "Exit",
		Decor = "EmptyTransition",
		Module = false,
		ThemeId = DISTRICT_DEFINITIONS[DISTRICT_COUNT].ThemeId,
		SectionIndex = DISTRICT_COUNT + 1,
		DistrictId = "EXIT",
		Role = "Exit",
		HideSpotCount = 0,
		LocalSeed = rng:NextInteger(1, 2 ^ 30),
		GridRow = exitRow,
		GridColumn = GRID_COLUMNS + 1,
	})
	if not exitRoom then return nil, "exit could not be created" end

	local selectedPairs = {}
	local function addLink(a, b, properties)
		local key = pairKey(a.Id, b.Id)
		if selectedPairs[key] then return nil, "duplicate link " .. key end
		local side = cardinalSide(a, b)
		if not side then return nil, "non-axis-aligned link " .. key end
		local link = {
			Id = string.format("Level3_Link_%02d", #layout.Links + 1),
			A = a.Id,
			B = b.Id,
			Door = properties.Door or "Open",
			ThemeId = properties.ThemeId,
			SectionIndex = properties.SectionIndex,
			LinkType = properties.LinkType or "Internal",
			Gateway = properties.Gateway == true,
			GatewayKind = properties.GatewayKind,
			FromSection = properties.FromSection,
			ToSection = properties.ToSection,
			FromThemeId = properties.FromThemeId,
			ToThemeId = properties.ToThemeId,
		}
		selectedPairs[key] = true
		table.insert(layout.Links, link)
		layout.LinkById[link.Id] = link
		table.insert(layout.Adjacency[a.Id], b.Id)
		table.insert(layout.Adjacency[b.Id], a.Id)
		if link.Gateway then table.insert(layout.GatewayLinks, link) end
		return link
	end

	local function neighbourSlots(sectionIndex, row, column)
		local result = {}
		if row > 1 then table.insert(result, slots[sectionIndex][row - 1][column]) end
		if row < GRID_ROWS then table.insert(result, slots[sectionIndex][row + 1][column]) end
		if column > 1 then table.insert(result, slots[sectionIndex][row][column - 1]) end
		if column < GRID_COLUMNS then table.insert(result, slots[sectionIndex][row][column + 1]) end
		return result
	end

	for sectionIndex, definition in ipairs(DISTRICT_DEFINITIONS) do
		local startRow = if sectionIndex == 1 then entryRow
			elseif sectionIndex == 2 then firstGatewayRow else secondGatewayRow
		local start = slots[sectionIndex][startRow][1]
		local visited = {[start.Id] = true}
		local stack = {start}
		local visitedCount = 1
		while #stack > 0 do
			local current = stack[#stack]
			local options = {}
			for _, other in ipairs(neighbourSlots(sectionIndex, current.GridRow, current.GridColumn)) do
				if not visited[other.Id] then table.insert(options, other) end
			end
			if #options == 0 then
				table.remove(stack)
			else
				local nextRoom = options[rng:NextInteger(1, #options)]
				local link, linkError = addLink(current, nextRoom, {
					ThemeId = definition.ThemeId,
					SectionIndex = sectionIndex,
					LinkType = "Internal",
				})
				if not link then return nil, linkError end
				visited[nextRoom.Id] = true
				visitedCount += 1
				table.insert(stack, nextRoom)
			end
		end
		if visitedCount ~= ROOMS_PER_DISTRICT then
			return nil, "district spanning tree did not visit every room"
		end

		local unused = {}
		for row = 1, GRID_ROWS do
			for column = 1, GRID_COLUMNS do
				local room = slots[sectionIndex][row][column]
				if column < GRID_COLUMNS then
					local other = slots[sectionIndex][row][column + 1]
					if not selectedPairs[pairKey(room.Id, other.Id)] then
						table.insert(unused, {room, other})
					end
				end
				if row < GRID_ROWS then
					local other = slots[sectionIndex][row + 1][column]
					if not selectedPairs[pairKey(room.Id, other.Id)] then
						table.insert(unused, {room, other})
					end
				end
			end
		end
		unused = shuffled(rng, unused)
		if #unused < Tuning.ExtraLinksPerDistrict then
			return nil, "not enough unused grid edges for district loops"
		end
		for index = 1, Tuning.ExtraLinksPerDistrict do
			local edge = unused[index]
			local link, linkError = addLink(edge[1], edge[2], {
				ThemeId = definition.ThemeId,
				SectionIndex = sectionIndex,
				LinkType = "InternalLoop",
			})
			if not link then return nil, linkError end
		end
	end

	local gatewayRows = {entryRow, firstGatewayRow, secondGatewayRow, exitRow}
	local gatewaySpecs = {
		{
			A = arrival,
			B = slots[1][entryRow][1],
			Kind = "Entry",
			FromSection = 0,
			ToSection = 1,
			FromThemeId = arrival.ThemeId,
			ToThemeId = DISTRICT_DEFINITIONS[1].ThemeId,
		},
		{
			A = slots[1][firstGatewayRow][GRID_COLUMNS],
			B = slots[2][firstGatewayRow][1],
			Kind = "District",
			FromSection = 1,
			ToSection = 2,
			FromThemeId = DISTRICT_DEFINITIONS[1].ThemeId,
			ToThemeId = DISTRICT_DEFINITIONS[2].ThemeId,
		},
		{
			A = slots[2][secondGatewayRow][GRID_COLUMNS],
			B = slots[3][secondGatewayRow][1],
			Kind = "District",
			FromSection = 2,
			ToSection = 3,
			FromThemeId = DISTRICT_DEFINITIONS[2].ThemeId,
			ToThemeId = DISTRICT_DEFINITIONS[3].ThemeId,
		},
		{
			A = signalHall,
			B = exitRoom,
			Kind = "Exit",
			FromSection = 3,
			ToSection = 4,
			FromThemeId = DISTRICT_DEFINITIONS[3].ThemeId,
			ToThemeId = exitRoom.ThemeId,
			Door = "HiddenExit",
		},
	}
	for index, spec in ipairs(gatewaySpecs) do
		local destinationSection = math.clamp(spec.ToSection, 1, DISTRICT_COUNT)
		local link, linkError = addLink(spec.A, spec.B, {
			Door = spec.Door or "Open",
			ThemeId = DISTRICT_DEFINITIONS[destinationSection].ThemeId,
			SectionIndex = destinationSection,
			LinkType = "Gateway",
			Gateway = true,
			GatewayKind = spec.Kind,
			FromSection = spec.FromSection,
			ToSection = spec.ToSection,
			FromThemeId = spec.FromThemeId,
			ToThemeId = spec.ToThemeId,
		})
		if not link then return nil, linkError end
		if index == 1 then
			layout.Districts[1].IncomingGatewayLinkId = link.Id
		elseif index == 2 then
			layout.Districts[1].OutgoingGatewayLinkId = link.Id
			layout.Districts[2].IncomingGatewayLinkId = link.Id
		elseif index == 3 then
			layout.Districts[2].OutgoingGatewayLinkId = link.Id
			layout.Districts[3].IncomingGatewayLinkId = link.Id
		else
			layout.Districts[3].OutgoingGatewayLinkId = link.Id
		end
	end

	local chosenModules = {}
	local chosenSet = {}
	local function addModule(room)
		if chosenSet[room.Id] then return end
		chosenSet[room.Id] = true
		room.Module = true
		if room.Role == "Room" then room.Role = "ModuleRoom" end
		table.insert(chosenModules, room)
	end

	for sectionIndex = 1, DISTRICT_COUNT do
		local candidates = {}
		for _, room in ipairs(layout.Districts[sectionIndex].Rooms) do
			if room.Id ~= "SignalHall" and (room.GridColumn == 2 or room.GridColumn == 3) then
				table.insert(candidates, room)
			end
		end
		addModule(candidates[rng:NextInteger(1, #candidates)])
	end

	while #chosenModules < MODULE_GOAL do
		local best = nil
		local bestScore = -math.huge
		for sectionIndex = 1, DISTRICT_COUNT do
			for _, room in ipairs(layout.Districts[sectionIndex].Rooms) do
				if not chosenSet[room.Id] and room.Id ~= "SignalHall" then
					local minimumDistance = math.huge
					for _, existing in ipairs(chosenModules) do
						minimumDistance = math.min(minimumDistance, planarDistance(room, existing))
					end
					if minimumDistance >= Tuning.MinimumModuleSeparation then
						local score = minimumDistance + rng:NextNumber(0, 0.01)
						if score > bestScore then
							best = room
							bestScore = score
						end
					end
				end
			end
		end
		if not best then return nil, "five sufficiently separated module rooms could not be selected" end
		addModule(best)
	end

	table.sort(chosenModules, function(a, b)
		if a.SectionIndex == b.SectionIndex then return a.Id < b.Id end
		return a.SectionIndex < b.SectionIndex
	end)
	layout.ModuleRooms = chosenModules

	for _, neighbours in pairs(layout.Adjacency) do table.sort(neighbours) end

	local minX, maxX, minZ, maxZ = math.huge, -math.huge, math.huge, -math.huge
	for _, room in ipairs(layout.Rooms) do
		minX = math.min(minX, room.X - room.W * 0.5)
		maxX = math.max(maxX, room.X + room.W * 0.5)
		minZ = math.min(minZ, room.Z - room.D * 0.5)
		maxZ = math.max(maxZ, room.Z + room.D * 0.5)
	end
	layout.Bounds = {
		MinX = minX,
		MaxX = maxX,
		MinZ = minZ,
		MaxZ = maxZ,
		Width = maxX - minX,
		Depth = maxZ - minZ,
	}
	layout.RoomCount = #layout.Rooms
	layout.LinkCount = #layout.Links
	layout.DistrictCount = #layout.Districts
	layout.ModuleCount = #layout.ModuleRooms
	layout.HideSpotCount = DISTRICT_COUNT * ROOMS_PER_DISTRICT
	layout.CyclomaticLoops = #layout.Links - #layout.Rooms + 1
	layout.GatewayRows = gatewayRows
	layout.Roles = {
		ArrivalRoomId = "Arrival",
		ExitRoomId = "Exit",
		SignalRoomId = "SignalHall",
		MallManagerSpawnRoomId = "SignalHall",
		EntryDistrictRoomId = gatewaySpecs[1].B.Id,
		ModuleRoomIds = (function()
			local ids = {}
			for _, room in ipairs(chosenModules) do table.insert(ids, room.Id) end
			return ids
		end)(),
		GatewayLinkIds = (function()
			local ids = {}
			for _, link in ipairs(layout.GatewayLinks) do table.insert(ids, link.Id) end
			return ids
		end)(),
		AmbientHVACRoomId = slots[1][3 - entryRow][GRID_COLUMNS].Id,
	}
	layout.LayoutHash = makeHash(layout)
	return layout
end

local function fail(message)
	return false, message
end

function LayoutGenerator.Validate(layout)
	if type(layout) ~= "table" then return fail("layout is not a table") end
	if type(layout.Rooms) ~= "table" or #layout.Rooms ~= DISTRICT_COUNT * ROOMS_PER_DISTRICT + 2 then
		return fail("layout must contain exactly 26 rooms")
	end
	local expectedLinks = DISTRICT_COUNT
		* ((ROOMS_PER_DISTRICT - 1) + Tuning.ExtraLinksPerDistrict)
		+ ENTRY_AND_GATEWAY_LINKS
	if type(layout.Links) ~= "table" or #layout.Links ~= expectedLinks then
		return fail(string.format("layout must contain exactly %d links", expectedLinks))
	end
	if type(layout.Districts) ~= "table" or #layout.Districts ~= DISTRICT_COUNT then
		return fail("layout must contain exactly three districts")
	end
	if type(layout.RoomById) ~= "table" or type(layout.Adjacency) ~= "table" then
		return fail("layout lookup tables are missing")
	end

	local seenRooms = {}
	local sectionCounts = {0, 0, 0}
	local moduleCounts = {0, 0, 0}
	local moduleTotal = 0
	local hideSpotTotal = 0
	for _, room in ipairs(layout.Rooms) do
		if type(room.Id) ~= "string" or room.Id == "" or seenRooms[room.Id] then
			return fail("room ids must be non-empty and unique")
		end
		seenRooms[room.Id] = true
		if layout.RoomById[room.Id] ~= room then return fail("RoomById is inconsistent for " .. room.Id) end
		if type(room.X) ~= "number" or type(room.Z) ~= "number"
			or type(room.W) ~= "number" or type(room.D) ~= "number" or type(room.H) ~= "number"
			or room.W <= 0 or room.D <= 0 or room.H <= 0 then
			return fail("room dimensions are invalid for " .. room.Id)
		end
		if room.Id == "Arrival" or room.Id == "Exit" then
			if room.HideSpotCount ~= 0 or room.Module == true then
				return fail(room.Id .. " must not have hide spots or a module")
			end
		else
			if room.SectionIndex < 1 or room.SectionIndex > DISTRICT_COUNT then
				return fail("district room has invalid section: " .. room.Id)
			end
			if room.HideSpotCount ~= 1 then
				return fail("each district room must request exactly one hide spot")
			end
			hideSpotTotal += room.HideSpotCount
			sectionCounts[room.SectionIndex] += 1
			local definition = DISTRICT_DEFINITIONS[room.SectionIndex]
			if room.ThemeId ~= definition.ThemeId or room.Kind ~= definition.Kind
				or room.DistrictId ~= definition.Id then
				return fail("district theme metadata is inconsistent for " .. room.Id)
			end
			if room.Module == true then
				moduleTotal += 1
				moduleCounts[room.SectionIndex] += 1
			end
		end
	end
	if not seenRooms.Arrival or not seenRooms.Exit or not seenRooms.SignalHall then
		return fail("Arrival, SignalHall, and Exit are required")
	end
	for sectionIndex = 1, DISTRICT_COUNT do
		if sectionCounts[sectionIndex] ~= ROOMS_PER_DISTRICT then
			return fail("every district must contain exactly eight rooms")
		end
		if moduleCounts[sectionIndex] < 1 then
			return fail("every district must contain at least one module")
		end
	end
	if moduleTotal ~= MODULE_GOAL or type(layout.ModuleRooms) ~= "table"
		or #layout.ModuleRooms ~= MODULE_GOAL then
		return fail("layout must contain exactly five module rooms")
	end
	if hideSpotTotal ~= DISTRICT_COUNT * ROOMS_PER_DISTRICT then
		return fail("layout must request exactly 24 evenly distributed hide spots")
	end

	for index = 1, #layout.Rooms - 1 do
		local a = layout.Rooms[index]
		for otherIndex = index + 1, #layout.Rooms do
			local b = layout.Rooms[otherIndex]
			local overlapX = (a.W + b.W) * 0.5 - math.abs(a.X - b.X)
			local overlapZ = (a.D + b.D) * 0.5 - math.abs(a.Z - b.Z)
			if overlapX > 0.001 and overlapZ > 0.001 then
				return fail("rooms overlap: " .. a.Id .. " and " .. b.Id)
			end
		end
	end

	local ports = {}
	local seenPairs = {}
	local hiddenCount = 0
	local gatewayCount = 0
	local rebuiltAdjacency = {}
	for roomId in pairs(seenRooms) do
		ports[roomId] = {}
		rebuiltAdjacency[roomId] = {}
	end
	for _, link in ipairs(layout.Links) do
		local a, b = layout.RoomById[link.A], layout.RoomById[link.B]
		if not a or not b or a == b then return fail("link endpoint is invalid") end
		local key = pairKey(a.Id, b.Id)
		if seenPairs[key] then return fail("duplicate room pair " .. key) end
		seenPairs[key] = true
		local sideA = cardinalSide(a, b)
		if not sideA then return fail("link is not straight and axis-aligned: " .. key) end
		local sideB = OPPOSITE_SIDE[sideA]
		if ports[a.Id][sideA] or ports[b.Id][sideB] then
			return fail("more than one connection uses the same room side: " .. key)
		end
		ports[a.Id][sideA] = link.Id
		ports[b.Id][sideB] = link.Id
		local gap
		if sideA == "East" or sideA == "West" then
			gap = math.abs(a.X - b.X) - (a.W + b.W) * 0.5
		else
			gap = math.abs(a.Z - b.Z) - (a.D + b.D) * 0.5
		end
		if gap < Tuning.MinimumCorridorLength - 0.001 then
			return fail("corridor is shorter than the configured minimum: " .. key)
		end
		table.insert(rebuiltAdjacency[a.Id], b.Id)
		table.insert(rebuiltAdjacency[b.Id], a.Id)
		if link.Door == "HiddenExit" then
			hiddenCount += 1
			if not (link.A == "SignalHall" and link.B == "Exit") then
				return fail("the only hidden link must be SignalHall to Exit")
			end
		end
		if link.Gateway == true then gatewayCount += 1 end
		if a.SectionIndex == b.SectionIndex and a.SectionIndex >= 1
			and a.SectionIndex <= DISTRICT_COUNT then
			local definition = DISTRICT_DEFINITIONS[a.SectionIndex]
			if link.ThemeId ~= definition.ThemeId or link.SectionIndex ~= a.SectionIndex then
				return fail("internal link theme does not match its district")
			end
		end
	end
	if hiddenCount ~= 1 then return fail("layout must contain one hidden exit link") end
	if gatewayCount ~= ENTRY_AND_GATEWAY_LINKS
		or type(layout.GatewayLinks) ~= "table"
		or #layout.GatewayLinks ~= ENTRY_AND_GATEWAY_LINKS then
		return fail("layout must contain four explicit gateway links")
	end

	for roomId, expected in pairs(rebuiltAdjacency) do
		table.sort(expected)
		local actual = layout.Adjacency[roomId]
		if type(actual) ~= "table" or #actual ~= #expected then
			return fail("Adjacency is inconsistent for " .. roomId)
		end
		for index, otherId in ipairs(expected) do
			if actual[index] ~= otherId then return fail("Adjacency is inconsistent for " .. roomId) end
		end
	end

	local reached = {Arrival = true}
	local queue = {"Arrival"}
	local cursor = 1
	while cursor <= #queue do
		local roomId = queue[cursor]
		cursor += 1
		for _, otherId in ipairs(layout.Adjacency[roomId]) do
			if not reached[otherId] then
				reached[otherId] = true
				table.insert(queue, otherId)
			end
		end
	end
	for roomId in pairs(seenRooms) do
		if not reached[roomId] then return fail("whole graph is disconnected at " .. roomId) end
	end

	for sectionIndex = 1, DISTRICT_COUNT do
		local district = layout.Districts[sectionIndex]
		if district.Index ~= sectionIndex or district.Id ~= DISTRICT_DEFINITIONS[sectionIndex].Id
			or district.ThemeId ~= DISTRICT_DEFINITIONS[sectionIndex].ThemeId
			or type(district.RoomIds) ~= "table" or #district.RoomIds ~= ROOMS_PER_DISTRICT then
			return fail("district metadata is inconsistent")
		end
		local startId = district.RoomIds[1]
		local sectionReached = {[startId] = true}
		local sectionQueue = {startId}
		local sectionCursor = 1
		while sectionCursor <= #sectionQueue do
			local roomId = sectionQueue[sectionCursor]
			sectionCursor += 1
			for _, otherId in ipairs(layout.Adjacency[roomId]) do
				local other = layout.RoomById[otherId]
				if other and other.SectionIndex == sectionIndex and not sectionReached[otherId] then
					sectionReached[otherId] = true
					table.insert(sectionQueue, otherId)
				end
			end
		end
		local count = 0
		for _ in pairs(sectionReached) do count += 1 end
		if count ~= ROOMS_PER_DISTRICT then
			return fail("district graph is not internally contiguous")
		end
	end

	for index = 1, #layout.ModuleRooms - 1 do
		for otherIndex = index + 1, #layout.ModuleRooms do
			if planarDistance(layout.ModuleRooms[index], layout.ModuleRooms[otherIndex])
				< Tuning.MinimumModuleSeparation - 0.001 then
				return fail("module rooms are not sufficiently separated")
			end
		end
	end
	if type(layout.Roles) ~= "table"
		or layout.Roles.ArrivalRoomId ~= "Arrival"
		or layout.Roles.ExitRoomId ~= "Exit"
		or layout.Roles.SignalRoomId ~= "SignalHall"
		or layout.Roles.MallManagerSpawnRoomId ~= "SignalHall" then
		return fail("role metadata is incomplete")
	end
	if layout.LayoutHash ~= makeHash(layout) then return fail("layout hash is inconsistent") end
	return true, "OK"
end

function LayoutGenerator.Generate(requestedSeed)
	local normalizedRequested = normalizeSeed(requestedSeed)
	local failures = {}
	for attempt = 1, Tuning.GenerationAttempts do
		local seed = (normalizedRequested + (attempt - 1) * Tuning.RetryStride) % MAX_SEED
		if seed == 0 then seed = 1 end
		local layout, generationError = generateAttempt(seed, normalizedRequested, attempt, false)
		if layout then
			local valid, validationError = LayoutGenerator.Validate(layout)
			if valid then
				layout.GenerationFailures = failures
				return layout
			end
			generationError = validationError
		end
		table.insert(failures, string.format("seed %d: %s", seed, tostring(generationError)))
	end
	for fallbackIndex, fallbackValue in ipairs(Tuning.FallbackSeeds) do
		local seed = normalizeSeed(fallbackValue)
		local layout, generationError = generateAttempt(
			seed,
			normalizedRequested,
			Tuning.GenerationAttempts + fallbackIndex,
			true
		)
		if layout then
			layout.FallbackSeed = seed
			local valid, validationError = LayoutGenerator.Validate(layout)
			if valid then
				layout.GenerationFailures = failures
				return layout
			end
			generationError = validationError
		end
		table.insert(failures, string.format("fallback seed %d: %s", seed, tostring(generationError)))
	end
	error("Level 3 layout generation failed: " .. table.concat(failures, " | "))
end

LayoutGenerator.Tuning = Tuning
LayoutGenerator.DistrictDefinitions = DISTRICT_DEFINITIONS
LayoutGenerator.Version = VERSION

return LayoutGenerator
