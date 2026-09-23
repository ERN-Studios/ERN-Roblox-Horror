--!strict
-- Level 4 Plan Generator
--
-- PURE. No Roblox service, no Instance, no yielding call: given a seed it
-- returns a plain table describing the whole neighbourhood, and Validate()
-- answers whether that table is playable. That is what lets the offline suite
-- in tools/tests/test_level4_plan.py run the REAL generator without Studio.
--
-- The plan is deliberately not random architecture. The street skeleton is
-- fixed -- a rectangular LOOP with one cross SHORTCUT, entered through a short
-- service passage -- because a chase has to be legible, and a maze of similar
-- rooms is the exact failure the brief forbids. What the seed chooses is the
-- VARIANT: which of each zone's candidate houses carries that zone's signal,
-- and which facade anomalies are showing. Every player in a round sees the same
-- variant; the server picks it once.
--
--   junction layout (plan coordinates, +x east, -z north)
--
--     NW --------- MidN --------- NE        Back Lane      z = -BlockDepth
--      |            |              |
--      |          (cross)          |        West/East Avenue
--      |            |              |
--   SW --------- MidS --------- SE          Main Street    z = 0
--    |
--   Arrival (service passage, the one permitted dead end)

local Configuration = require(script.Parent:WaitForChild("Level 4 Configuration"))

local PlanGenerator = {}

PlanGenerator.Version = 1
PlanGenerator.VariantCount = 3
local MAX_SEED = 2147483647

-- Junction ids. Order is load-bearing only in that the hash walks it.
local SW, MIDS, SE, NE, MIDN, NW, ARRIVAL = "SW", "MidS", "SE", "NE", "MidN", "NW", "Arrival"

-- Zones are thirds of the street length, west to east. Each has at least two
-- candidate houses, so no variant can leave a zone with a single option.
local ZONE_COUNT = 3

local ANOMALY_KINDS = {"ExtraWindow", "WrongNumber", "ReversedMailbox", "DrawnCurtains"}

-- The three investigation kinds. Each carries a VISUAL clue part as well as
-- whatever audio the polish pass adds, so no task can require hearing.
local TASK_KINDS = {"FacadeCompare", "Broadcast", "Sample"}

-- The authored lot table, before seeded jitter. `Side` is which side of its
-- street the house sits on: -1 is the -z / -x side, +1 the other. `Role` is
-- Intro (the safe briefing house), Candidate (may carry a signal) or Decor.
-- Interior 0 means a shell with no inside; 1..3 select a reusable module.
local LOT_TABLE = {
	{Id = "Intro", Street = "MainWest", Along = 40, Side = 1, Zone = 1, Role = "Intro", Interior = 1},
	{Id = "A1", Street = "MainWest", Along = 128, Side = 1, Zone = 1, Role = "Candidate", Interior = 2},
	{Id = "A2", Street = "MainWest", Along = 92, Side = -1, Zone = 1, Role = "Candidate", Interior = 3},
	{Id = "B1", Street = "MainEast", Along = 252, Side = 1, Zone = 2, Role = "Candidate", Interior = 3},
	{Id = "B2", Street = "MainEast", Along = 272, Side = -1, Zone = 2, Role = "Candidate", Interior = 1},
	{Id = "C1", Street = "MainEast", Along = 370, Side = 1, Zone = 3, Role = "Candidate", Interior = 2},
	{Id = "C2", Street = "MainEast", Along = 344, Side = -1, Zone = 3, Role = "Candidate", Interior = 3},
	{Id = "D1", Street = "LaneWest", Along = 102, Side = -1, Zone = 1, Role = "Decor", Interior = 0},
	{Id = "D2", Street = "LaneEast", Along = 268, Side = -1, Zone = 2, Role = "Decor", Interior = 0},
	{Id = "D3", Street = "LaneEast", Along = 356, Side = -1, Zone = 3, Role = "Decor", Interior = 0},
	{Id = "D4", Street = "LaneWest", Along = 154, Side = 1, Zone = 2, Role = "Decor", Interior = 0},
}

-- Which candidate each variant selects per zone, and which anomaly each zone's
-- chosen house shows. Three controlled combinations, authored rather than
-- rolled, so every one of them can be walked and signed off.
local VARIANTS = {
	{
		Name = "TERRACE",
		Choice = {A = "A1", B = "B1", C = "C1"},
		Anomaly = {"ExtraWindow", "WrongNumber", "DrawnCurtains"},
		-- Extra anomalies on houses that hold nothing: the red herrings that
		-- make "find the changed house" a reading exercise rather than a
		-- highlight hunt.
		Decoys = {D1 = "DrawnCurtains", D3 = "ReversedMailbox"},
	},
	{
		Name = "CRESCENT",
		Choice = {A = "A2", B = "B2", C = "C2"},
		Anomaly = {"ReversedMailbox", "DrawnCurtains", "WrongNumber"},
		Decoys = {D2 = "ExtraWindow", D4 = "WrongNumber"},
	},
	{
		Name = "CLOSE",
		Choice = {A = "A1", B = "B2", C = "C2"},
		Anomaly = {"DrawnCurtains", "ExtraWindow", "ReversedMailbox"},
		Decoys = {D1 = "WrongNumber", D2 = "ReversedMailbox", D4 = "DrawnCurtains"},
	},
}

-- ---------------------------------------------------------------------------
-- Deterministic arithmetic
-- ---------------------------------------------------------------------------

-- A Park-Miller stream. Deliberately NOT Roblox's Random: this module has to
-- produce byte-identical plans in the offline Luau host and in Studio, and the
-- engine's generator is not specified to match anything.
local function stream(seed: number)
	local state = math.floor(math.abs(seed)) % 2147483646 + 1
	local function nextUnit(): number
		state = (state * 16807) % MAX_SEED
		return (state - 1) / 2147483646
	end
	-- WARM-UP, and it is not cosmetic. Park-Miller's first output for a small
	-- seed is tiny -- seed * 16807 is nowhere near the modulus -- so every seed
	-- under about 400 produced a first draw below 0.004 and therefore ALWAYS
	-- variant 1. Production seeds are milliseconds and never hit it, but a
	-- pinned Level4Seed of 7 is exactly the case a tester reaches for. Three
	-- discards are enough for the state to have wrapped the modulus.
	nextUnit()
	nextUnit()
	nextUnit()
	return nextUnit
end

local function roundTo(value: number, places: number): number
	local scale = 10 ^ places
	return math.floor(value * scale + 0.5) / scale
end

-- FNV-1a over the plan's own numbers. Two plans with the same hash describe the
-- same neighbourhood; the World Builder stamps it on the world so a manifest
-- can be proved to belong to the layout it claims.
local function hashOf(plan: any): string
	-- bit32, not Lua 5.3's `~`: Luau has no integer XOR operator.
	local digest = 2166136261
	local function mix(text: string)
		for index = 1, #text do
			digest = bit32.bxor(digest, string.byte(text, index))
			digest = (digest * 16777619) % 4294967296
		end
	end
	mix(tostring(plan.Version) .. "|" .. tostring(plan.ResolvedSeed) .. "|" .. tostring(plan.Variant))
	for _, lot in ipairs(plan.Lots) do
		mix(("|%s:%0.2f:%0.2f:%d:%s:%s"):format(lot.Id, lot.X, lot.Z, lot.Interior, lot.Role,
			lot.Anomaly or "-"))
	end
	for _, task in ipairs(plan.Tasks) do
		mix(("|T%s:%s:%s"):format(task.LotId, task.Kind, tostring(task.Forgiving)))
	end
	return ("%08x"):format(digest)
end

-- ---------------------------------------------------------------------------
-- Generation
-- ---------------------------------------------------------------------------

local function junctions(streets: any): {[string]: any}
	local length, depth = streets.Length, streets.BlockDepth
	return {
		[SW] = {Id = SW, X = 0, Z = 0},
		[MIDS] = {Id = MIDS, X = length / 2, Z = 0},
		[SE] = {Id = SE, X = length, Z = 0},
		[NE] = {Id = NE, X = length, Z = -depth},
		[MIDN] = {Id = MIDN, X = length / 2, Z = -depth},
		[NW] = {Id = NW, X = 0, Z = -depth},
		-- The one permitted dead end: the service passage the party arrives
		-- through. Everything beyond it is a loop.
		[ARRIVAL] = {Id = ARRIVAL, X = -streets.ServicePassageLength, Z = 0},
	}
end

local function streetEdges(): {any}
	return {
		{Id = "Service", A = ARRIVAL, B = SW, Kind = "Service", Axis = "X"},
		{Id = "MainWest", A = SW, B = MIDS, Kind = "Main", Axis = "X"},
		{Id = "MainEast", A = MIDS, B = SE, Kind = "Main", Axis = "X"},
		{Id = "AvenueEast", A = SE, B = NE, Kind = "Avenue", Axis = "Z"},
		{Id = "LaneEast", A = NE, B = MIDN, Kind = "Lane", Axis = "X"},
		{Id = "LaneWest", A = MIDN, B = NW, Kind = "Lane", Axis = "X"},
		{Id = "AvenueWest", A = NW, B = SW, Kind = "Avenue", Axis = "Z"},
		-- The cross shortcut. This is the edge that makes a chase survivable:
		-- it gives the loop a second independent cycle, so no stretch of road
		-- can be cut off by one body standing in it.
		{Id = "Shortcut", A = MIDS, B = MIDN, Kind = "Shortcut", Axis = "Z"},
	}
end

-- Degrees of freedom the seed actually has: the variant, and a few studs of
-- along-street jitter per lot. Nothing structural moves.
local function placeLots(plan: any, nextUnit: () -> number)
	local streets, lots = Configuration.Streets, Configuration.Lots
	-- Distance from a street centreline to a lot centre: half the carriageway,
	-- the pavement, the front yard, then half the house.
	local offset = streets.HalfWidth + streets.SidewalkWidth + lots.FrontYardDepth + lots.HouseDepth / 2
	local variant = VARIANTS[plan.Variant]

	local chosen = {}
	for _, id in pairs(variant.Choice) do chosen[id] = true end

	for _, template in ipairs(LOT_TABLE) do
		local edge = plan.StreetById[template.Street]
		assert(edge, "Level 4 lot " .. template.Id .. " names a street that does not exist")
		local jitter = (nextUnit() * 2 - 1) * lots.PositionJitter
		local along = roundTo(template.Along + jitter, 2)
		local laneZ = plan.JunctionById[edge.A].Z
		local lot = {
			Id = template.Id,
			StreetId = template.Street,
			Zone = template.Zone,
			Role = template.Role,
			Interior = template.Interior,
			X = along,
			Z = roundTo(laneZ + template.Side * offset, 2),
			-- Houses face the street they sit on: a lot on the +z side looks
			-- back towards -z.
			FacingZ = -template.Side,
			Side = template.Side,
			ColorKey = ({"FadedCream", "DustyYellow", "BlueGrey"})[(#plan.Lots % 3) + 1],
			Anomaly = nil :: string?,
			Selected = chosen[template.Id] == true,
		}
		table.insert(plan.Lots, lot)
		plan.LotById[lot.Id] = lot
	end

	-- Anomalies: one per selected house (the readable "this one changed" tell
	-- and the FacadeCompare clue), plus the variant's decoys.
	for zone = 1, ZONE_COUNT do
		local key = ({"A", "B", "C"})[zone]
		local lot = plan.LotById[variant.Choice[key]]
		assert(lot, "Level 4 variant names a lot that does not exist: " .. tostring(variant.Choice[key]))
		lot.Anomaly = variant.Anomaly[zone]
	end
	for id, anomaly in pairs(variant.Decoys) do
		local lot = plan.LotById[id]
		if lot and not lot.Anomaly then lot.Anomaly = anomaly end
	end
end

local function placeTasks(plan: any)
	local variant = VARIANTS[plan.Variant]
	for zone = 1, ZONE_COUNT do
		local key = ({"A", "B", "C"})[zone]
		local lotId = variant.Choice[key]
		table.insert(plan.Tasks, {
			Index = zone,
			Zone = zone,
			LotId = lotId,
			-- Rotating the kind by variant keeps all three task types in play
			-- across the three combinations without a second roll.
			Kind = TASK_KINDS[((zone + plan.Variant - 2) % #TASK_KINDS) + 1],
			-- Zone 1 is the forgiving first success: generous reach, no hold,
			-- and it reports no gameplay noise.
			Forgiving = zone == 1,
		})
	end
end

local function placeLandmarks(plan: any)
	local streets = Configuration.Streets
	local length, depth = streets.Length, streets.BlockDepth
	-- The small central green sits inside the block, west of the shortcut, so
	-- it has a clear sightline east down the cross walk to the tower.
	plan.Green = {X = roundTo(length / 2 - 72, 2), Z = roundTo(-depth / 2, 2), W = 92, D = 80}
	-- The water/signal tower: the one landmark visible from the whole street.
	plan.Tower = {X = length + 64, Z = roundTo(-depth * 0.5, 2), Height = 92, LegSpread = 22}
	-- The finale sits on East Avenue beside the tower: seen from early on,
	-- inert until all three signals are in.
	plan.BusStop = {X = length + 17, Z = roundTo(-depth * 0.36, 2)}
	plan.Cabinet = {X = length + 17, Z = roundTo(-depth * 0.36 + 13, 2)}
	plan.Exit = {X = length + 26, Z = roundTo(-depth * 0.36 - 9, 2)}
	plan.ArrivalSpawn = {X = roundTo(-streets.ServicePassageLength + 16, 2), Z = 0}

	-- The boundary: repeated facade rows and hills. These are pure decoration
	-- with an invisible blocker behind them, and they are what makes the
	-- gameplay edge look like a neighbourhood rather than a wall.
	plan.Boundary = {
		FacadeRows = {
			{X = roundTo(length / 2, 2), Z = roundTo(-depth - 150, 2), Width = length + 240, Facing = 1},
			{X = roundTo(length / 2, 2), Z = 150, Width = length + 240, Facing = -1},
			{X = -150, Z = roundTo(-depth / 2, 2), Width = depth + 240, Facing = 1, Axis = "Z"},
		},
		Hills = {
			{X = roundTo(length / 2, 2), Z = roundTo(-depth - 300, 2), W = length + 700, D = 240, H = 74},
			{X = roundTo(length / 2, 2), Z = 300, W = length + 700, D = 240, H = 62},
			{X = -300, Z = roundTo(-depth / 2, 2), W = 240, D = depth + 760, H = 68},
			{X = length + 320, Z = roundTo(-depth / 2, 2), W = 240, D = depth + 760, H = 70},
		},
		-- Play area, in plan coordinates. The invisible blockers stand on it.
		Bounds = {MinX = -streets.ServicePassageLength - 26, MaxX = length + 150,
			MinZ = -depth - 120, MaxZ = 120},
	}
end

function PlanGenerator.Generate(seed: number): any
	local resolved = math.floor(tonumber(seed) or 1)
	if resolved ~= resolved or resolved < 1 or resolved >= MAX_SEED then resolved = 1 end
	local nextUnit = stream(resolved)

	local plan = {
		Version = PlanGenerator.Version,
		ResolvedSeed = resolved,
		Attempt = 1,
		Junctions = {},
		JunctionById = junctions(Configuration.Streets),
		Streets = streetEdges(),
		StreetById = {},
		Lots = {},
		LotById = {},
		Tasks = {},
		ZoneCount = ZONE_COUNT,
	}
	for _, junction in pairs(plan.JunctionById) do table.insert(plan.Junctions, junction) end
	table.sort(plan.Junctions, function(a, b) return a.Id < b.Id end)
	for _, edge in ipairs(plan.Streets) do plan.StreetById[edge.Id] = edge end

	-- The variant is the first draw off the stream, so the same seed always
	-- picks the same combination whatever is added to placement later.
	plan.Variant = math.min(PlanGenerator.VariantCount,
		math.floor(nextUnit() * PlanGenerator.VariantCount) + 1)
	plan.VariantName = VARIANTS[plan.Variant].Name

	placeLots(plan, nextUnit)
	placeTasks(plan)
	placeLandmarks(plan)
	plan.PlanHash = hashOf(plan)
	return plan
end

-- ---------------------------------------------------------------------------
-- Validation
--
-- This is what the Round Adapter refuses to build past, and what the in-Studio
-- Test Suite runs against every variant. It answers the five questions the
-- brief asks of a plan: the loop and shortcut connect, every task spot is
-- reachable solo, the exit is reachable, the safe-house invariant can hold,
-- and nothing required sits behind its own lock.
-- ---------------------------------------------------------------------------

local function adjacency(plan: any): {[string]: {string}}
	local map = {}
	for _, junction in ipairs(plan.Junctions) do map[junction.Id] = {} end
	for _, edge in ipairs(plan.Streets) do
		if not map[edge.A] or not map[edge.B] then return map end
		table.insert(map[edge.A], edge.B)
		table.insert(map[edge.B], edge.A)
	end
	return map
end

local function reachable(map: {[string]: {string}}, from: string): {[string]: boolean}
	local seen, queue, head = {[from] = true}, {from}, 1
	while head <= #queue do
		local node = queue[head]
		head += 1
		for _, neighbour in ipairs(map[node] or {}) do
			if not seen[neighbour] then
				seen[neighbour] = true
				table.insert(queue, neighbour)
			end
		end
	end
	return seen
end

function PlanGenerator.Validate(plan: any): (boolean, string?)
	if type(plan) ~= "table" then return false, "plan is not a table" end
	if plan.Version ~= PlanGenerator.Version then return false, "plan version mismatch" end
	if type(plan.Variant) ~= "number" or plan.Variant < 1
		or plan.Variant > PlanGenerator.VariantCount then return false, "variant out of range" end
	if plan.PlanHash ~= hashOf(plan) then return false, "plan hash is stale" end

	local map = adjacency(plan)
	for _, edge in ipairs(plan.Streets) do
		if not plan.JunctionById[edge.A] or not plan.JunctionById[edge.B] then
			return false, "street " .. tostring(edge.Id) .. " names a junction that does not exist"
		end
	end

	-- Every junction on the loop must have at least two ways out; the service
	-- terminus is the one permitted dead end and it is the arrival, not a
	-- corner a chase can be cornered in.
	for _, junction in ipairs(plan.Junctions) do
		local degree = #(map[junction.Id] or {})
		if junction.Id == ARRIVAL then
			if degree ~= 1 then return false, "the service passage must be the only dead end" end
		elseif degree < 2 then
			return false, "junction " .. junction.Id .. " is a dead end"
		end
	end

	-- Two independent cycles: the ring, plus the cross shortcut. E - V + 1 over
	-- the loop-only subgraph (the service passage is a tree edge and its
	-- terminus a tree node, so both drop out).
	local loopEdges, loopNodes = 0, 0
	for _, edge in ipairs(plan.Streets) do
		if edge.Kind ~= "Service" then loopEdges += 1 end
	end
	for _, junction in ipairs(plan.Junctions) do
		if junction.Id ~= ARRIVAL then loopNodes += 1 end
	end
	local cycles = loopEdges - loopNodes + 1
	if cycles < 2 then return false, "the plan needs a loop AND a cross shortcut" end
	if not plan.StreetById.Shortcut or plan.StreetById.Shortcut.Kind ~= "Shortcut" then
		return false, "the cross shortcut is missing"
	end

	local seen = reachable(map, ARRIVAL)
	for _, junction in ipairs(plan.Junctions) do
		if not seen[junction.Id] then
			return false, "junction " .. junction.Id .. " is unreachable from the arrival"
		end
	end

	-- Lots. Every one attaches to a reachable street, every zone keeps at least
	-- two enterable houses (the safe-house invariant needs somewhere to fall
	-- back to), and the intro house exists and is enterable.
	local enterablePerZone, selected = {}, {}
	local intro = nil
	for _, lot in ipairs(plan.Lots) do
		local edge = plan.StreetById[lot.StreetId]
		if not edge then return false, "lot " .. lot.Id .. " has no street" end
		if not (seen[edge.A] and seen[edge.B]) then
			return false, "lot " .. lot.Id .. " sits on an unreachable street"
		end
		if lot.Interior > 0 then
			enterablePerZone[lot.Zone] = (enterablePerZone[lot.Zone] or 0) + 1
		end
		if lot.Role == "Intro" then intro = lot end
		if lot.Selected then selected[lot.Id] = true end
		if lot.Anomaly ~= nil and not table.find(ANOMALY_KINDS, lot.Anomaly) then
			return false, "lot " .. lot.Id .. " shows an unknown anomaly: " .. tostring(lot.Anomaly)
		end
	end
	if not intro or intro.Interior <= 0 then return false, "the intro house must be enterable" end
	for zone = 1, ZONE_COUNT do
		if (enterablePerZone[zone] or 0) < 2 then
			return false, "zone " .. zone .. " needs at least two enterable houses"
		end
	end

	-- Tasks. One per zone, on a distinct enterable lot, and the zone-1 task is
	-- the forgiving one. A task on the exit lot, or two tasks on one house,
	-- would make a required clue depend on another required clue.
	if #plan.Tasks ~= Configuration.Objectives.SignalGoal then
		return false, "the plan must carry exactly " .. Configuration.Objectives.SignalGoal .. " signals"
	end
	local usedLots, usedZones, forgiving = {}, {}, 0
	for _, task in ipairs(plan.Tasks) do
		local lot = plan.LotById[task.LotId]
		if not lot then return false, "signal " .. task.Index .. " names a lot that does not exist" end
		if lot.Interior <= 0 then return false, "signal " .. task.Index .. " is not in an enterable house" end
		if not lot.Selected then return false, "signal " .. task.Index .. " is not on the variant's own house" end
		if usedLots[task.LotId] then return false, "two signals share one house" end
		if usedZones[task.Zone] then return false, "two signals share one zone" end
		if not lot.Anomaly then return false, "signal " .. task.Index .. " has no readable facade clue" end
		if not table.find(TASK_KINDS, task.Kind) then return false, "unknown signal kind" end
		usedLots[task.LotId] = true
		usedZones[task.Zone] = true
		if task.Forgiving then forgiving += 1 end
	end
	if forgiving ~= 1 then return false, "exactly one signal must be the forgiving first success" end
	if not plan.Tasks[1].Forgiving then return false, "the forgiving signal must be the zone-1 one" end

	-- The finale is the only lock, and it opens on the three signals alone.
	for _, landmark in ipairs({"Green", "Tower", "BusStop", "Cabinet", "Exit", "ArrivalSpawn"}) do
		local value = plan[landmark]
		if type(value) ~= "table" or type(value.X) ~= "number" or type(value.Z) ~= "number" then
			return false, "landmark " .. landmark .. " is missing"
		end
	end
	local bounds = plan.Boundary and plan.Boundary.Bounds
	if type(bounds) ~= "table" then return false, "the play bounds are missing" end
	for _, lot in ipairs(plan.Lots) do
		if lot.X < bounds.MinX or lot.X > bounds.MaxX or lot.Z < bounds.MinZ or lot.Z > bounds.MaxZ then
			return false, "lot " .. lot.Id .. " sits outside the play bounds"
		end
	end
	-- Houses must not overlap: the blockout has to be walkable between them.
	local pitch = Configuration.Lots.HouseWidth + 8
	for first = 1, #plan.Lots - 1 do
		for second = first + 1, #plan.Lots do
			local a, b = plan.Lots[first], plan.Lots[second]
			if math.abs(a.X - b.X) < pitch and math.abs(a.Z - b.Z) < Configuration.Lots.HouseDepth + 6 then
				return false, "lots " .. a.Id .. " and " .. b.Id .. " overlap"
			end
		end
	end
	return true, nil
end

-- Read-only view of the authored tables, for the Test Suite and the offline
-- tests. Nothing in the runtime reads these.
PlanGenerator.__test = {
	Variants = VARIANTS,
	LotTable = LOT_TABLE,
	TaskKinds = TASK_KINDS,
	AnomalyKinds = ANOMALY_KINDS,
	Adjacency = adjacency,
	Reachable = reachable,
	-- Exposed so a test can RE-STAMP a deliberately broken plan. Without it the
	-- stale-hash guard fires first on every mutation and the semantic rules
	-- below it are never actually exercised.
	Hash = hashOf,
}

return PlanGenerator
