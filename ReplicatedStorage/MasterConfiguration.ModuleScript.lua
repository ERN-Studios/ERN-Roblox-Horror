--!strict
-- Master Configuration -- one registry for everything a developer may tune.
--
-- IT DOES NOT HOLD THE VALUES. The level configuration modules stay the single
-- source of truth. This describes what MAY be overridden, inside what range,
-- and whether the change takes effect live or only on the next round build.
--
-- That distinction is the whole point. A registry that copied the numbers would
-- be a second source of truth, and this project already knows what that costs:
-- Level 3's music mix drifted between Configuration.MusicSequence and the sound
-- controller's own constants (0.85 vs 1.15 fade), and the layout generator's
-- DEFAULTS table drifted from Configuration.Layout in four places. Both are
-- still live discrepancies. Nothing here repeats that mistake: an entry names
-- the field, never its value.
--
-- Storage is two attribute folders under ReplicatedStorage:
--
--   MasterTuning            an attribute per key = the OVERRIDE. Absent means
--                           "use whatever the configuration module says".
--   MasterTuning.Defaults   an attribute per key = the value the configuration
--                           module actually holds, republished by the server on
--                           every round build so a panel can show what it is
--                           about to change and what "reset" returns to.
--
-- Attributes rather than a table because they replicate to every client for
-- free, survive a place save, and are readable from a Studio plugin without
-- running the game. Level2Seed has always worked this way; this is the same
-- mechanism, made general.

local ReplicatedStorage = game:GetService("ReplicatedStorage")
local RunService = game:GetService("RunService")

local Master = {}

Master.FolderName = "MasterTuning"
Master.DefaultsFolderName = "Defaults"

export type Entry = {
	Key: string,       -- attribute name; [A-Za-z0-9_] only, Roblox rejects dots
	Label: string,
	Level: string,     -- which tab a panel puts it under
	Group: string,
	Source: string,    -- which configuration table it belongs to
	Path: string,      -- the field name inside that table
	Minimum: number,
	Maximum: number,
	Step: number,
	Integer: boolean?,
	Live: boolean,     -- false: takes effect on the NEXT round build, not now
	Note: string?,
}

-- ---------------------------------------------------------------- the registry
--
-- Deliberately curated rather than exhaustive. Level 3's configuration alone
-- holds about 200 numbers; a panel listing all of them is not a tool, it is a
-- wall. These are the ones that change how a level plays or how big it is.
-- Adding another is one row -- as long as its Source has a resolution point
-- wired up (see "Wiring" at the bottom).

Master.Entries = {
	-- ---- Lobby ------------------------------------------------------------
	{Key = "Lobby_QueueSeconds", Label = "Kø-tid", Level = "Lobby", Group = "Timing",
	 Source = "Lobby", Path = "QUEUE_TIME", Minimum = 3, Maximum = 60, Step = 1,
	 Integer = true, Live = false},
	{Key = "Lobby_ElevatorSeconds", Label = "Elevatortur", Level = "Lobby", Group = "Timing",
	 Source = "Lobby", Path = "ELEVATOR_TIME", Minimum = 2, Maximum = 40, Step = 1,
	 Integer = true, Live = false,
	 Note = "Produktionsværdien 19 matcher elevatorlyden. 2 er testværdien."},

	-- ---- Level 1: størrelse ------------------------------------------------
	{Key = "L1_Grid", Label = "Labyrint-gitter", Level = "Level 1", Group = "Størrelse",
	 Source = "L1Maze", Path = "GRID", Minimum = 8, Maximum = 60, Step = 1,
	 Integer = true, Live = false,
	 Note = "40 i produktion, 10 til test. Arealet vokser kvadratisk."},
	{Key = "L1_Cell", Label = "Cellestørrelse", Level = "Level 1", Group = "Størrelse",
	 Source = "L1Maze", Path = "CELL", Minimum = 12, Maximum = 48, Step = 1,
	 Integer = true, Live = false},
	{Key = "L1_Openness", Label = "Åbenhed", Level = "Level 1", Group = "Størrelse",
	 Source = "L1Maze", Path = "OPENNESS", Minimum = 0, Maximum = 1, Step = .01, Live = false,
	 Note = "Hvor mange vægge der fjernes efter labyrinten er gravet."},
	{Key = "L1_PitZones", Label = "Antal pit-zoner", Level = "Level 1", Group = "Størrelse",
	 Source = "L1Maze", Path = "PIT_ZONES", Minimum = 0, Maximum = 8, Step = 1,
	 Integer = true, Live = false},

	-- ---- Level 1: mål ------------------------------------------------------
	{Key = "L1_FuseSpawnMultiplier", Label = "Relæer pr. sikring", Level = "Level 1", Group = "Mål",
	 Source = "L1Puzzle", Path = "SPAWN_MULT", Minimum = 1, Maximum = 5, Step = 1,
	 Integer = true, Live = false},
	{Key = "L1_LeverWindowSeconds", Label = "Håndtags-vindue", Level = "Level 1", Group = "Mål",
	 Source = "L1Puzzle", Path = "LEVER_WINDOW", Minimum = 2, Maximum = 60, Step = 1, Live = false},
	{Key = "L1_SpeedPerFuse", Label = "Fartøgning pr. sikring", Level = "Level 1", Group = "Mål",
	 Source = "L1Puzzle", Path = "SPEED_PER_FUSE", Minimum = 0, Maximum = .3, Step = .01, Live = false},

	-- ---- Level 1: entiteten ------------------------------------------------
	{Key = "L1_EntityChaseSpeed", Label = "Jagtfart", Level = "Level 1", Group = "Entitet",
	 Source = "L1Entity", Path = "SPEED_CHASE", Minimum = 8, Maximum = 60, Step = .1, Live = false,
	 Note = "Spillerens sprint er 26. Under det kan entiteten aldrig indhente nogen."},
	{Key = "L1_EntityLurkSpeed", Label = "Patruljefart", Level = "Level 1", Group = "Entitet",
	 Source = "L1Entity", Path = "SPEED_LURK", Minimum = 2, Maximum = 30, Step = .1, Live = false},
	{Key = "L1_EntitySightRange", Label = "Synsvidde", Level = "Level 1", Group = "Entitet",
	 Source = "L1Entity", Path = "SIGHT_RANGE", Minimum = 50, Maximum = 2000, Step = 10, Live = false},
	{Key = "L1_EntitySightRangeLit", Label = "Synsvidde mod lygte", Level = "Level 1", Group = "Entitet",
	 Source = "L1Entity", Path = "SIGHT_RANGE_LIT", Minimum = 50, Maximum = 3000, Step = 10, Live = false},
	{Key = "L1_EntityHearRange", Label = "Hørevidde", Level = "Level 1", Group = "Entitet",
	 Source = "L1Entity", Path = "HEAR_RANGE", Minimum = 20, Maximum = 1000, Step = 10, Live = false},
	{Key = "L1_EntityTrackSeconds", Label = "Husker position i", Level = "Level 1", Group = "Entitet",
	 Source = "L1Entity", Path = "TRACK_TIME", Minimum = 0, Maximum = 30, Step = .5, Live = false},
	{Key = "L1_EntityLungeChance", Label = "Lunge-sandsynlighed", Level = "Level 1", Group = "Entitet",
	 Source = "L1Entity", Path = "LUNGE_CHANCE", Minimum = 0, Maximum = 1, Step = .05, Live = false},

	-- ---- Level 2: størrelse ------------------------------------------------
	{Key = "L2_ComplexExtent", Label = "Kompleksets bredde", Level = "Level 2", Group = "Størrelse",
	 Source = "L2", Path = "ComplexExtent", Minimum = 600, Maximum = 2400, Step = 50,
	 Integer = true, Live = false},
	{Key = "L2_MinimumLeafSize", Label = "Mindste hal", Level = "Level 2", Group = "Størrelse",
	 Source = "L2", Path = "MinimumLeafSize", Minimum = 90, Maximum = 400, Step = 5,
	 Integer = true, Live = false},
	{Key = "L2_MaximumLeafSize", Label = "Største hal", Level = "Level 2", Group = "Størrelse",
	 Source = "L2", Path = "MaximumLeafSize", Minimum = 120, Maximum = 600, Step = 5,
	 Integer = true, Live = false},
	{Key = "L2_MinimumHallCount", Label = "Mindste antal haller", Level = "Level 2", Group = "Størrelse",
	 Source = "L2", Path = "MinimumHallCount", Minimum = 4, Maximum = 60, Step = 1,
	 Integer = true, Live = false},
	{Key = "L2_CorridorWidth", Label = "Korridorbredde", Level = "Level 2", Group = "Størrelse",
	 Source = "L2", Path = "CorridorWidth", Minimum = 12, Maximum = 80, Step = 1, Live = false},
	{Key = "L2_WallHeight", Label = "Væghøjde", Level = "Level 2", Group = "Størrelse",
	 Source = "L2", Path = "WallHeight", Minimum = 12, Maximum = 90, Step = 1, Live = false},

	-- ---- Level 2: indhold --------------------------------------------------
	{Key = "L2_SlideHallCount", Label = "Antal rutsjehaller", Level = "Level 2", Group = "Indhold",
	 Source = "L2", Path = "SlideHallCount", Minimum = 0, Maximum = 8, Step = 1,
	 Integer = true, Live = false},
	{Key = "L2_SlidesPerHall", Label = "Rutsjebaner pr. hal", Level = "Level 2", Group = "Indhold",
	 Source = "L2", Path = "SlidesPerHall", Minimum = 1, Maximum = 8, Step = 1,
	 Integer = true, Live = false},
	{Key = "L2_KidsAreaRoomCount", Label = "Rum i børnefløjen", Level = "Level 2", Group = "Indhold",
	 Source = "L2", Path = "KidsAreaRoomCount", Minimum = 0, Maximum = 12, Step = 1,
	 Integer = true, Live = false},
	{Key = "L2_ShallowPoolDepth", Label = "Lav vanddybde", Level = "Level 2", Group = "Indhold",
	 Source = "L2", Path = "ShallowPoolDepth", Minimum = .4, Maximum = 4, Step = .1, Live = false},
	{Key = "L2_DeepPoolDepth", Label = "Dyb vanddybde", Level = "Level 2", Group = "Indhold",
	 Source = "L2", Path = "DeepPoolDepth", Minimum = .4, Maximum = 6, Step = .1, Live = false,
	 Note = "Over vadedybde begynder spillere at svømme, hvilket niveauet ikke er bygget til."},
	{Key = "L2_CeilingPanelBrightness", Label = "Loftslysstyrke", Level = "Level 2", Group = "Indhold",
	 Source = "L2", Path = "CeilingPanelBrightness", Minimum = 0, Maximum = 5, Step = .05, Live = false},

	-- ---- Level 3: størrelse ------------------------------------------------
	-- Configuration.ModuleGoal (the CD count) is deliberately NOT here. It is
	-- read straight off the frozen configuration by the round adapter, the world
	-- builder and validateManifest, with no single resolution point to overlay,
	-- and the Signal Hall disc player is built with exactly five slots. A control
	-- that silently did nothing would be worse than no control, so it waits for
	-- the disc player to take a variable slot count.
	{Key = "L3_MinimumRoomWidth", Label = "Mindste rumbredde", Level = "Level 3", Group = "Størrelse",
	 Source = "L3Layout", Path = "MinimumRoomWidth", Minimum = 30, Maximum = 120, Step = 1,
	 Integer = true, Live = false},
	{Key = "L3_MaximumRoomWidth", Label = "Største rumbredde", Level = "Level 3", Group = "Størrelse",
	 Source = "L3Layout", Path = "MaximumRoomWidth", Minimum = 30, Maximum = 160, Step = 1,
	 Integer = true, Live = false},
	{Key = "L3_MinimumRoomDepth", Label = "Mindste rumdybde", Level = "Level 3", Group = "Størrelse",
	 Source = "L3Layout", Path = "MinimumRoomDepth", Minimum = 30, Maximum = 120, Step = 1,
	 Integer = true, Live = false},
	{Key = "L3_MaximumRoomDepth", Label = "Største rumdybde", Level = "Level 3", Group = "Størrelse",
	 Source = "L3Layout", Path = "MaximumRoomDepth", Minimum = 30, Maximum = 160, Step = 1,
	 Integer = true, Live = false},
	{Key = "L3_RowHalfSpacing", Label = "Rækkeafstand", Level = "Level 3", Group = "Størrelse",
	 Source = "L3Layout", Path = "RowHalfSpacing", Minimum = 30, Maximum = 200, Step = 1,
	 Integer = true, Live = false},
	{Key = "L3_ExitCorridorLength", Label = "Længde på sidste hal", Level = "Level 3", Group = "Størrelse",
	 Source = "L3Layout", Path = "ExitCorridorLength", Minimum = 100, Maximum = 1200, Step = 10,
	 Integer = true, Live = false},
	{Key = "L3_ExtraLinksPerDistrict", Label = "Ekstra forbindelser", Level = "Level 3", Group = "Størrelse",
	 Source = "L3Layout", Path = "ExtraLinksPerDistrict", Minimum = 0, Maximum = 6, Step = 1,
	 Integer = true, Live = false},

	-- ---- Level 3: Mall Manager --------------------------------------------
	{Key = "L3_ManagerPatrolSpeed", Label = "Patruljefart", Level = "Level 3", Group = "Mall Manager",
	 Source = "L3Manager", Path = "PatrolSpeed", Minimum = 1, Maximum = 30, Step = .25, Live = true},
	{Key = "L3_ManagerChaseSpeed", Label = "Jagtfart", Level = "Level 3", Group = "Mall Manager",
	 Source = "L3Manager", Path = "ChaseSpeed", Minimum = 4, Maximum = 60, Step = .1, Live = true,
	 Note = "Spillerens sprint er 26."},
	{Key = "L3_ManagerVisionRange", Label = "Synsvidde", Level = "Level 3", Group = "Mall Manager",
	 Source = "L3Manager", Path = "VisionRange", Minimum = 10, Maximum = 600, Step = 5, Live = true},
	{Key = "L3_ManagerMemorySeconds", Label = "Hukommelse", Level = "Level 3", Group = "Mall Manager",
	 Source = "L3Manager", Path = "MemorySeconds", Minimum = 0, Maximum = 90, Step = .5, Live = true},

	-- ---- Level 3: Mall Manager under blackout -----------------------------
	{Key = "L3_BlackoutChaseSpeed", Label = "Jagtfart (blackout)", Level = "Level 3", Group = "Blackout",
	 Source = "L3ManagerBlackout", Path = "ChaseSpeed", Minimum = 4, Maximum = 70, Step = .1, Live = true},
	{Key = "L3_BlackoutVisionRange", Label = "Synsvidde (blackout)", Level = "Level 3", Group = "Blackout",
	 Source = "L3ManagerBlackout", Path = "VisionRange", Minimum = 10, Maximum = 900, Step = 5, Live = true},
	{Key = "L3_BlackoutMemorySeconds", Label = "Hukommelse (blackout)", Level = "Level 3", Group = "Blackout",
	 Source = "L3ManagerBlackout", Path = "MemorySeconds", Minimum = 0, Maximum = 180, Step = 1, Live = true},
} :: {Entry}

Master.ByKey = {} :: {[string]: Entry}
for _, entry in ipairs(Master.Entries) do
	assert(Master.ByKey[entry.Key] == nil, "duplicate Master tuning key: " .. entry.Key)
	assert(entry.Key:match("^[A-Za-z0-9_]+$") ~= nil,
		"tuning key must be attribute-safe (no dots): " .. entry.Key)
	assert(entry.Minimum < entry.Maximum, "empty range for " .. entry.Key)
	Master.ByKey[entry.Key] = entry
end

-- ------------------------------------------------------------------- storage

local function child(parent: Instance, name: string): Folder
	local existing = parent:FindFirstChild(name)
	if existing and existing:IsA("Folder") then return existing end
	if existing then existing:Destroy() end
	local created = Instance.new("Folder")
	created.Name = name
	created.Parent = parent
	return created
end

--- May this context create or write the tuning folders?
--
-- Yes for the running server, and yes in Edit mode where no simulation exists --
-- that second case is the Studio plugin, which has to be able to set an override
-- without starting the game, and is the whole reason this is not a plain
-- IsServer() check. In Edit, RunService reports IsServer=false and IsClient=true,
-- so IsServer() alone locks the plugin out of its own tool.
--
-- Never a LIVE client: a folder a client creates does not replicate, so it would
-- silently shadow the real one for that player and for nobody else -- the kind
-- of bug that looks like "it works on my machine" forever.
local function mayWrite(): boolean
	return RunService:IsServer() or not RunService:IsRunning()
end

Master.MayWrite = mayWrite

function Master.Overrides(): Folder?
	if mayWrite() then return child(ReplicatedStorage, Master.FolderName) end
	local existing = ReplicatedStorage:FindFirstChild(Master.FolderName)
	return if existing and existing:IsA("Folder") then existing else nil
end

function Master.Defaults(): Folder?
	local root = Master.Overrides()
	if not root then return nil end
	if mayWrite() then return child(root, Master.DefaultsFolderName) end
	local existing = root:FindFirstChild(Master.DefaultsFolderName)
	return if existing and existing:IsA("Folder") then existing else nil
end

-- ---------------------------------------------------------------- validation

--- Coerce a proposed value onto the entry's contract, or nil if it cannot be.
-- Every caller runs this, including the server handler: a panel is a
-- convenience, never the authority on what is a legal value.
function Master.Coerce(key: string, value: any): number?
	local entry = Master.ByKey[key]
	if not entry then return nil end
	local numeric = tonumber(value)
	if numeric == nil then return nil end
	if numeric ~= numeric or math.abs(numeric) == math.huge then return nil end -- NaN, inf
	numeric = math.clamp(numeric, entry.Minimum, entry.Maximum)
	if entry.Integer then numeric = math.floor(numeric + .5) end
	return numeric
end

-- The configuration's OWN value for a key, remembered the first time this VM
-- ever saw it.
--
-- ApplyInto writes into a live table, so after one override the table no longer
-- holds the configuration's value -- and without this, publishing "the default"
-- would publish the override, and CLEARING an override would leave the last
-- override in place forever because there would be nothing left to restore to.
-- Module-local is exactly the right lifetime: a fresh VM also reloads the
-- configuration module, so the first value seen is the authored one again.
local pristine: {[string]: number} = {}

local function baseline(key: string, current: any): any
	local numeric = tonumber(current)
	if pristine[key] == nil and numeric ~= nil then pristine[key] = numeric end
	local remembered = pristine[key]
	return if remembered ~= nil then remembered else current
end

local function publishDefault(key: string, value: any)
	if not mayWrite() then return end
	local folder = Master.Defaults()
	if folder and tonumber(value) then folder:SetAttribute(key, value) end
end

-- -------------------------------------------------------------- read / write

--- The override for `key`, or nil when none is set.
function Master.GetOverride(key: string): number?
	local folder = Master.Overrides()
	if not folder then return nil end
	-- Coerce on READ as well as write: the attribute is editable by hand in the
	-- Studio properties pane, where nothing enforces the range.
	return Master.Coerce(key, folder:GetAttribute(key))
end

--- What the configuration module itself holds, as last published by the server.
function Master.GetDefault(key: string): number?
	local folder = Master.Defaults()
	return if folder then tonumber(folder:GetAttribute(key)) else nil
end

--- The value that is actually in force, given what the code itself declares.
-- For the Level 1 systems, which have no configuration module at all and keep
-- their numbers as plain top-of-file constants, this IS the resolution point.
-- It remembers and publishes the authored value like ApplyInto does, so a panel
-- can still show what an override is replacing.
function Master.Effective(key: string, authored: number): number
	local base = baseline(key, authored)
	publishDefault(key, base)
	local override = Master.GetOverride(key)
	return if override ~= nil then override else base
end

--- Authoritative setter. `value = nil` clears the override.
-- Callable from the running server and from Edit mode (the Studio plugin);
-- refused on a live client, which must go through the DevTuning remote so the
-- server can check DevAccess before anything is written.
function Master.SetOverride(key: string, value: any): (boolean, string?)
	if not mayWrite() then return false, "not writable from a live client" end
	local entry = Master.ByKey[key]
	if not entry then return false, "unknown key" end
	local folder = Master.Overrides()
	if not folder then return false, "no tuning folder" end
	if value == nil then
		folder:SetAttribute(key, nil)
		return true
	end
	local coerced = Master.Coerce(key, value)
	if coerced == nil then return false, "value is not a finite number" end
	folder:SetAttribute(key, coerced)
	return true
end

-- --------------------------------------------------------------------- wiring
--
-- Two resolution helpers, one per shape of configuration table this project has.
--
--   ApplyInto  a MUTABLE config table, written in place before a build.
--              Level 2 Configuration is the only one not frozen.
--   Overlay    a FROZEN config table. Returns a NEW table carrying the same
--              fields with overrides applied, leaving the original untouched --
--              Level 3 Configuration is frozen in seventeen places on purpose
--              and this must not be the thing that unfreezes it.
--
-- Both also publish what the configuration held, so a panel can show the value
-- an override is replacing and what clearing it returns to.

--- Write overrides into a MUTABLE configuration table, in place.
-- Always writes: the override when one is set, the authored value when not, so
-- clearing an override restores rather than freezing the last value written.
function Master.ApplyInto(target: {[string]: any}, source: string): number
	local applied = 0
	for _, entry in ipairs(Master.Entries) do
		if entry.Source == source then
			local base = baseline(entry.Key, target[entry.Path])
			publishDefault(entry.Key, base)
			local override = Master.GetOverride(entry.Key)
			local wanted = if override ~= nil then override else base
			if target[entry.Path] ~= wanted then
				target[entry.Path] = wanted
				if override ~= nil then applied += 1 end
			end
		end
	end
	return applied
end

--- Copy a FROZEN configuration table with overrides applied.
-- The original is never touched: Level 3 Configuration is frozen in seventeen
-- places deliberately, and this must not be what unfreezes it.
function Master.Overlay(source_table: {[string]: any}, source: string): {[string]: any}
	local result = {}
	for field, value in pairs(source_table) do result[field] = value end
	for _, entry in ipairs(Master.Entries) do
		if entry.Source == source then
			local base = baseline(entry.Key, source_table[entry.Path])
			publishDefault(entry.Key, base)
			local override = Master.GetOverride(entry.Key)
			if override ~= nil then result[entry.Path] = override end
		end
	end
	return result
end

return Master
