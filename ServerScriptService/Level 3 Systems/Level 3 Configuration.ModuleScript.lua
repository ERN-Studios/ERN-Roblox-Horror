-- Level 3 Configuration
-- Tunables for the Level 3 "Sunken Leisure Complex".
--
-- Level 3 does not share Level 2's plan. Level 2 is a uniform 6x6 grid of
-- identical 92-stud cells; Level 3 is a binary space partition of one large
-- region into halls of very different sizes joined by real corridors.
--
-- The ONLY things deliberately shared with Level 2 are the tile texture asset
-- and the terrain water appearance, so both levels feel like the same building.

local Configuration = {
	Version = 2,
	Theme = "Sunken Leisure Complex",

	-- ── plan ────────────────────────────────────────────────────────────────
	-- 1400 studs across. Level 2 is 552, so this is roughly 6x the floor area.
	ComplexExtent = 1400,

	-- The complex is shifted north so it can never intersect the persistent
	-- tunnel lobby, which is built at (0, 30, -760) and spans roughly z -910
	-- to -610. With this offset the outer shell runs z -525 .. +1005.
	WorldCenterX = 0,
	WorldCenterZ = 240,

	MinimumLeafSize = 200,
	MinimumSplitDepth = 2,
	MaximumSplitDepth = 5,
	-- Chance a branch stops early, which is what leaves a few enormous halls.
	EarlyStopChance = 0.18,
	-- Gap left around every hall; corridors run through it.
	HallMargin = 30,
	HallInsetJitter = 14,
	MinimumHallSize = 110,
	MinimumHallCount = 16,
	GenerationAttempts = 40,

	CorridorWidth = 34,
	CorridorWalkwayWidth = 8,
	MaximumCorridorLength = 130,
	MinimumDrainableLength = 40,

	SlideHallCount = 3,
	SlideHallSeparation = 320,
	PumpSeparation = 300,
	KidsAreaRoomCount = 5,

	-- ── vertical ────────────────────────────────────────────────────────────
	-- Doorways are generous so a large entity rig fits through everything.
	WallHeight = 34,
	GrandSlideHallHeight = 96,
	SlideHallHeight = 76,
	KidsWallHeight = 21,
	CorridorHeight = 26,
	WallThickness = 3.5,
	DoorWidth = 30,
	DoorHeight = 19,

	-- Water halls keep a dry tiled walkway of this width on every side of the
	-- sunken basin, exactly like the reference photos.
	HallBasinBorder = 20,

	DeepPoolDepth = 24,
	ShallowPoolDepth = 1.6,
	CorridorChannelDepth = 1.5,
	-- Drainable corridors are deep enough that draining them visibly changes
	-- the space: flooded you swim across the surface, drained you walk the
	-- channel floor between the entry and exit steps.
	DrainableCorridorDepth = 6,

	-- ── lighting ────────────────────────────────────────────────────────────
	CeilingPanelBrightness = 1.55,
	CeilingPanelRange = 44,
	WallPanelBrightness = 0.95,
	WallPanelRange = 28,
	SkylightBrightness = 3.1,
	SkylightRange = 95,

	-- ── slides ──────────────────────────────────────────────────────────────
	SlidesPerHall = 3,
	SlideTubeRadius = 7.5,
	SlideSegments = 22,
	SlideTubeSides = 8,
}

Configuration.Colors = {
	Tile = Color3.fromRGB(228, 224, 205),
	TileCool = Color3.fromRGB(206, 221, 212),
	TileWarm = Color3.fromRGB(236, 227, 196),
	Grout = Color3.fromRGB(36, 104, 132),
	DarkGrout = Color3.fromRGB(22, 55, 66),
	Metal = Color3.fromRGB(83, 96, 99),
	Rail = Color3.fromRGB(196, 202, 205),
	Water = Color3.fromRGB(48, 150, 159),
	Light = Color3.fromRGB(255, 247, 210),
	Emergency = Color3.fromRGB(194, 224, 205),
	Locked = Color3.fromRGB(214, 96, 78),
	Void = Color3.fromRGB(7, 15, 18),
}

-- Exactly three colors across the whole kids area, as requested.
Configuration.KidsColors = {
	{Name = "Sun", Color = Color3.fromRGB(240, 198, 78), Accent = Color3.fromRGB(255, 226, 140)},
	{Name = "Coral", Color = Color3.fromRGB(226, 118, 104), Accent = Color3.fromRGB(255, 168, 152)},
	{Name = "Lagoon", Color = Color3.fromRGB(104, 176, 216), Accent = Color3.fromRGB(158, 214, 240)},
}

Configuration.SlideColors = {
	Color3.fromRGB(96, 196, 132),
	Color3.fromRGB(224, 96, 84),
	Color3.fromRGB(238, 202, 84),
	Color3.fromRGB(78, 158, 214),
}

-- Reserved audio slots. No published IDs yet; a future Level 3 sound controller
-- can resolve these by name from attributes exactly as Level 2 does.
Configuration.SoundSlots = {
	{"Level 3 Room Tone", true, "Continuous hollow tiled-pool ambience"},
	{"Level 3 Ventilation Hum", true, "Low mechanical ventilation bed"},
	{"Level 3 Distant Water", true, "Large-room water movement and reverb"},
	{"Level 3 Pump Start", false, "Heavy pump motor spinning up"},
	{"Level 3 Drain Rush", false, "A corridor draining away"},
	{"Level 3 Pressure Door", false, "Pressure door unsealing"},
	{"Level 3 Slide Rush", false, "Water and tile rush inside a flume"},
	{"Level 3 Kids Area Tone", false, "Dead, dry, carpeted-room tone"},
}

return Configuration
