-- Level 2 Configuration
-- Tunables for the Level 2 "Sunken Leisure Complex".
--
-- Level 2 does not share Level 1's plan. Level 1 is a uniform 6x6 grid of
-- identical 92-stud cells; Level 2 is a binary space partition of one large
-- region into halls of very different sizes joined by real corridors.
--
-- The ONLY things deliberately shared with Level 2 are the tile texture asset
-- and the terrain water appearance, so both levels feel like the same building.

local Configuration = {
	Version = 4,
	Theme = "Sunken Leisure Complex",

	-- ── plan ────────────────────────────────────────────────────────────────
	-- 1400 studs across. Level 1 is 552, so this is roughly 6x the floor area.
	ComplexExtent = 1400,

	-- The complex is shifted north so it can never intersect the persistent
	-- tunnel lobby, which is built at (0, 30, -760) and spans roughly z -910
	-- to -610. With this offset the outer shell runs z -525 .. +1005.
	WorldCenterX = 0,
	WorldCenterZ = 240,

	MinimumLeafSize = 150,
	-- No leaf may exceed this on either axis: halls top out around 250 studs
	-- (rare 270 from unsplittable 310-330 leaves), never the old giants.
	MaximumLeafSize = 310,
	MinimumSplitDepth = 2,
	MaximumSplitDepth = 6,
	-- Chance a branch stops early, which keeps a few of the largest allowed
	-- rooms (bounded by MaximumLeafSize).
	EarlyStopChance = 0.18,
	-- Gap left around every hall; corridors run through it.
	HallMargin = 30,
	HallInsetJitter = 14,
	MinimumHallSize = 85,
	MinimumHallCount = 16,
	GenerationAttempts = 40,
	-- The requested seed's normal retry stream always runs first. Only a seed that
	-- exhausts it enters this deterministic recovery sequence. Seed 101 is a
	-- checked-in known-good baseline for this exact configuration; keep it in the
	-- generator stress suite whenever plan tunables change.
	GenerationFallbackSeeds = {101},
	GenerationFallbackAttemptsPerSeed = 40,

	CorridorWidth = 34,
	-- Clear walking width of the slim ledge along one side of every tunnel,
	-- measured inboard of the vault's arch ribs (the slab itself continues
	-- outward under the arch feet to the tunnel wall). Keep it narrow: the
	-- rib-free band ends roughly 11.3 studs from the corridor centreline.
	CorridorWalkwayWidth = 2.2,
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

	-- Water covers the floor wall-to-wall in every pool hall, exactly like the
	-- reference photos — no sunken basins. Raised decks standing IN the water
	-- are the one exception: pump rooms always carry their wide service ring,
	-- and a seeded share of the plain halls get a slim dry walkway hugging
	-- their walls (door-aware, with a submerged curb step on its inner edge).
	HallEdgeWalkwayChance = .5,
	HallEdgeWalkwayWidth = 4.5,
	ShallowPoolDepth = 1.6,
	-- Even the "deep" halls stay below the swim threshold: the whole level
	-- is walkable water.
	DeepPoolDepth = 2,
	-- Wading depth everywhere players land and walk; nobody swims in the
	-- slide halls any more.
	SlidePoolDepth = 1.8,
	CorridorChannelDepth = 1.5,
	-- Drainable corridors stay WADING depth: deep enough that a pump visibly
	-- empties them, never deep enough to force swimming in a tunnel.
	DrainableCorridorDepth = 1.8,
	-- Kids rooms keep their existing .9-stud wading layer, but recess it so its
	-- surface meets corridor water at Y=.1 instead of forcing a swim-state step.
	KidsWadingDepth = .8,

	-- ── lighting ────────────────────────────────────────────────────────────
	CeilingPanelBrightness = 1.085,
	CeilingPanelRange = 44,
	WallPanelBrightness = 0.665,
	WallPanelRange = 28,
	SkylightBrightness = 2.17,
	SkylightRange = 95,

	-- ── slides ──────────────────────────────────────────────────────────────
	SlidesPerHall = 3,
	SlideTubeRadius = 7.5,
	SlideSegments = 22,
	SlideTubeSides = 8, -- legacy fallback only
	SlideUseMeshTemplates = true,
	SlideVisualSegmentMultiplier = 1.6,
	-- Tight column spirals use extra visual slices without multiplying collision parts.
	SlideHelixVisualSegments = 120,
	SlideHelixVisualOverlap = .56,
	SlideMeshOverlap = .65,
	SlideGlossReflectance = .06,
	SlideMouthReflectance = .08,
	SlideMouthLength = 2.8,
	SlideCollisionThickness = .6,
	-- Flat and shallow slide sections remain normally walkable. The controller
	-- takes over only once a rider reaches a genuinely steep descent.
	SlideCollisionFriction = .05,
	SlideCollisionFrictionWeight = 1,
	-- Hidden collision may overlap farther than the decorative mesh so curved
	-- flumes cannot open seams, and open slides keep a tall invisible guard lip.
	SlideCollisionOverlap = 1.5,
	SlideOpenSafetyWallHeight = 14,
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

-- Authored slots mirrored by ReplicatedStorage["Level 2 Sound Library"].
-- Looping beds and gameplay cues keep stable names; environmental one-shots are
-- selected contextually by the client sound controller.
Configuration.SoundSlots = {
	{"Level 2 Room Tone", true, "Continuous hollow tiled-pool ambience"},
	{"Level 2 Ventilation Hum", true, "Low mechanical ventilation bed"},
	{"Level 2 Distant Water", true, "Large-room water movement and reverb"},
	{"Level 2 Pump Start", false, "Heavy pump motor spinning up"},
	{"Level 2 Drain Rush", false, "A corridor draining away"},
	{"Level 2 Pressure Door", false, "Heavy vertical steel pressure door opening"},
	{"Level 2 Slide Rush", false, "Water and tile rush inside a flume"},
	{"Level 2 Player Dry Tile Walking Sound", false, "Player footstep on dry poolside tile (no water underfoot)"},
	{"Level 2 Kids Area Tone", false, "Dead, dry, carpeted-room tone"},
	{"Level 2 Water Drop", false, "Close drip from a corridor ceiling"},
	{"Level 2 Distant Splash", false, "Unexplained splash in a distant wet hall"},
	{"Level 2 Drain Gurgle", false, "Drain gurgle near a running pump"},
	{"Level 2 Pipe Groan", false, "Distant building-pressure pipe groan"},
	{"Level 2 Distant Monster-Like Pipe Groan 1", false, "Rare distant pipe groan variation"},
	{"Level 2 Distant Monster-Like Pipe Groan 2", false, "Rare distant pipe groan variation"},
	{"Level 2 Distant Monster-Like Pipe Groan 3", false, "Rare distant pipe groan variation"},
	{"Level 2 Distant Monster-Like Pipe Groan 4", false, "Rare distant pipe groan variation"},
}


return Configuration
