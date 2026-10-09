-- Level 4 "Den Sidste Forestilling": every tuning number for the cinema round in one place.
-- Owner design (2026-10-02): start in total darkness, turn the power on (the whole cinema lights up), then the
-- lights start failing; three film reels go into the three booth projectors while someone holds the main breaker
-- (solo: a fuse holds it for a minute); the Usher lives in the dark and comes for noise; the finale runs out through
-- Cinema 2's screen. Contracts (tags, attributes, remotes) are listed in tools/level4_blender/README.md "Level 4 round".
local Configuration = {}

Configuration.Level = 4
Configuration.ModelName = "Level 4 Cinema Blender"
Configuration.RuntimeName = "Level 4 Round Runtime"
Configuration.StateName = "Level 4 State"
Configuration.RemotesName = "Level 4 Remotes"
Configuration.TemplatesName = "Level 4 Templates"

-- Power-up sequence (the note) and the wow moment
Configuration.Sequence = {
	Length = 4,                  -- switches in the order on the note
	NoteMaxDistance = 40,        -- the note spawns on a spot within this many studs of an entry spawn
	WrongResetSeconds = 1.2,     -- sparks, then every switch drops back
	PowerUpWaveSeconds = 4.5,    -- zones switch on in a wave ordered by distance from the service room
	FullyLitSeconds = 15,        -- "woooow": everything on before the failing starts
	-- each switch's prompt sits at eye height in front of its cabinet, 3.5 studs apart (Objective placeSwitchAnchor)
	SwitchPromptDistance = 7,
	-- FINDABILITY_20261003 (owner: the note must be easier to find and readable by clicking it): the paper is scaled up,
	-- glints, and carries a "Read" prompt that opens the note on screen
	NoteScale = 2.5,
	NotePromptDistance = 10,
	-- owner 2026-10-04: the note lies somewhere in the service room (random each round), where POWER A/B are
	NoteSpots = { "Note_Workbench", "Note_ServiceShelf" },
	-- a small warm light just in front of the sheet: the note is needed while the cinema is dark (Lift = studs off the
	-- written face)
	NoteGlow = { Range = 9, Brightness = 1.3, Lift = 1.2, Color = Color3.fromRGB(255, 226, 170) },
}

-- Per-spot placement tweaks (marker name -> Offset in the marker's frame, Tilt degrees toward -Z, Yaw degrees turning a
-- note's sheet in its own plane, Scale for a loose reel there). The service shelf tray (7.8 studs up) also carries a
-- poster-roll bin: the note stands at the deck's front edge so it shows above the shelf beam from the aisle (Studio QA
-- 2026-10-04: seen from 39 of 43 standing spots within reach; leaning on the bin it was 5 of 39), turned so its writing
-- reads upright; the reel sits in front of the bin at template size.
Configuration.SpotTweaks = {
	Note_ServiceShelf = { Offset = Vector3.new(0, 0, -1.8), Tilt = 80, Yaw = 90 },
	Reel_ServiceShelf = { Offset = Vector3.new(0, 0, -0.9), Scale = 1 },
}

-- Light failing (escalates with each reel loaded: index = reels loaded + 1)
Configuration.Failing = {
	BlinkEvery = { 7, 5, 3.6, 2.6 },        -- seconds between blink starts somewhere in the cinema
	OffSeconds = { { 3, 7 }, { 4, 9 }, { 5, 11 }, { 6, 13 } },
	MaxDarkFraction = { 0.25, 0.32, 0.4, 0.5 },   -- never more of the zones dark at once (dead zones included)
	DeadZones = 3,                          -- zones that stay dark for the whole Failing phase (the Usher's homes)
	AvoidPlayerZoneChance = 0.35,           -- blinks prefer zones without players at first...
}

Configuration.Reels = {
	Goal = 3,
	CarrySpeedFactor = 0.88,     -- per reel carried
	MinSpeedFactor = 0.7,
	RunNoiseSpeed = 18,          -- moving faster than this with reels rattles them ("reel" noise)
	PromptDistance = 10,         -- the highest spot (service shelf) is 7 studs from the nearest standing root
	Scale = 1.6,                 -- the film can template is scaled up so a reel reads from across a room
	-- FINDABILITY_20261003 (owner: "the reels are hidden too well"): at most MaxHard of these spots per round (above eye
	-- level, behind a seat back, at the far end of the gallery, or locked in the prize case)
	HardSpots = { "Reel_Cinema1", "Reel_Gallery", "Reel_Popcorn", "Reel_ServiceShelf", "Reel_Prize" },
	MaxHard = 1,
	-- REEL_ROOMS_20261008: the room each reel spot is shown as in the objective panel ("Reels: Cafe, Arcade")
	RoomNames = {
		Reel_BackCounter = "Concessions", Reel_Popcorn = "Concessions", Reel_TicketBooth = "Ticket booth",
		Reel_Cafe = "Cafe", Reel_Cinema1 = "Cinema 1", Reel_Gallery = "Gallery", Reel_Prize = "Arcade",
		Reel_ServiceShelf = "Service room", Reel_Men = "Men's room", Reel_Women = "Women's room",
	},
}

Configuration.Projectors = {
	ThreadSeconds = 5,
	NoiseEvery = 1,              -- "projector" noise pulse while threading and for a few seconds after
	RunNoiseSeconds = 6,
	PromptDistance = 8,
}

Configuration.Breaker = {
	HoldDistance = 7,            -- the holder must stay this close to the lever
	FuseSeconds = 60,
	FuseCooldownSeconds = 4,
	-- co-op: the fuse also works once nobody has held the lever this long after someone asked for the fuse
	CoopFuseAfterSeconds = 45,
	PromptDistance = 8,
}

Configuration.Bonus = {
	CodeLength = 4,
	KeypadDistance = 10,
	BatteryRefill = 1,           -- fraction of the battery restored by the battery pack
}

Configuration.Hiding = {
	RequireCrouch = true,
	MaxSpeed = 9,                -- hidden only while moving slower than this
}

Configuration.Usher = {
	Height = 7.6,
	ActivateGraceSeconds = 8,     -- after Failing starts
	ThinkSeconds = 0.1,
	StalkSpeed = 9,
	ChaseSpeed = 17,
	FinaleSpeed = 21,
	HopCooldownSeconds = { 6, 11 },
	HopMinPlayerDistance = 28,    -- a hop never lands closer than this to any player
	HopMaxTargetDistance = 70,    -- ...and lands within this of its target when it has one
	HearingRange = 110,
	SightRange = 70,
	AttackRange = 6.5,
	ShushSeconds = 1.25,          -- the "shhh" warning before the grab
	CaptureSeconds = 2.2,         -- jumpscare camera duration
	DeathAt = 1.6,
	StunSeconds = 2.6,            -- flashlight in the face
	StunCooldownSeconds = 1.2,
	FlashlightRange = 46,
	FlashlightConeDegrees = 17,
	FlashlightDrainBonus = 3,     -- extra battery drain per second while lighting it (client applies)
	LitRetreat = true,            -- if its spot becomes lit it vanishes and hops away
	MotionHz = 20,
}

-- Noise loudness for NoiseRegistry (names must exist in NoiseRegistry.LOUDNESS)
Configuration.Noise = {
	Reel = "reel",
	Projector = "projector",
	Breaker = "breaker",
	Door = "door",
}

-- Sound asset ids (0 = silent). Server-side one-shots; the client carries its own ambience.
Configuration.Audio = {
	Switch = 9119717286,       -- ProSoundEffects "Switch Circuit Breaker Clicks 9"
	Wrong = 9119583974,        -- ProSoundEffects "Static Many Various Length Bursts 23"
	Reel = 138294283280319,    -- "metal_canister_impact_soft2"
	Breaker = 9119727134,      -- ProSoundEffects "Switch Impact On Flip Up Large Metal 2"
	Projector = 17671632366,   -- "Projector Film"
	Prize = 9113808387,        -- ProSoundEffects "Circuit Breaker Door 2"
	Shush = 9126213995,        -- ProSoundEffects "Whisper Bursts Unintelligible Eerie Evil Ghost"
}

-- Required world anchors (tag -> minimum count); Build refuses a cinema without them.
Configuration.Required = {
	L4EntrySpawn = 1, L4Breaker = 4, L4MainBreaker = 1, L4FuseSocket = 1, L4ReelSpot = 3,
	L4Projector = 3, L4Screen = 3, L4ExitScreen = 1, L4ExitSafeSpawn = 1,
}

return Configuration
