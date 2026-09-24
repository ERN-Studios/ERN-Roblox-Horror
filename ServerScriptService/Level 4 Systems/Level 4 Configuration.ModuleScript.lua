--!strict
-- Level 4 Configuration
--
-- THE QUIET SUBURBS -- Zyntra Residential Test Site. Milestones 1 and 2 only:
-- a walkable blockout plus one end-to-end prototype of house / task / entity.
-- Everything here is a number, a name or a colour; no behaviour lives in this
-- file, so the art and audio passes can retune it without reading the systems.
--
-- LEVEL 4 IS DEV-ONLY. Nothing in the shipping campaign routes here: the lobby
-- gate stays "coming soon" and Round Completion Routing still ends at its
-- MaxLevel unless workspace.Level4DevEnabled is true AND every participant
-- passes DevAccess. See docs/LEVEL4_CONTRACTS_2026-09-21.md.
--
-- EVERY VISUAL IS A PLACEHOLDER. Parts, WedgeParts and stock materials only --
-- no invented asset ids anywhere in Level 4. Each generated instance that the
-- art pass is expected to replace carries the attribute Level4_Placeholder.

local Configuration = {
	Version = 1,

	WorldName = "Level 4 Generated World",
	StateFolderName = "Level 4 State",
	RemotesFolderName = "Level 4 Remotes",
	ClientEventName = "ClientEvent",

	-- Far from Level 2's and Level 3's origins (Level 3 sits at x = 6200) so a
	-- half-torn-down world can never intersect this one.
	WorldOrigin = Vector3.new(12400, 24, 0),

	-- ---------------------------------------------------------------------
	-- Body envelopes. Every door, stair and passage width below is DERIVED
	-- from these, and the derivation is written out so the art pass can check
	-- a replacement model against the same arithmetic.
	-- ---------------------------------------------------------------------
	Body = {
		-- Roblox R15 at default scale: ~5 studs tall, ~2 studs across the hips.
		PlayerHeight = 5,
		PlayerWidth = 2,
		-- Two players abreast must fit any door or interior passage, with a gap
		-- wide enough that neither is shoved into a wall by the other's collider.
		PlayerPassGap = 2,

		-- The Neighbour. Deliberately just under twice a player's height: tall
		-- enough to read as wrong from the far end of the street, short enough
		-- that a believable suburban door still admits it.
		NeighbourHeight = 9.5,
		NeighbourShoulderWidth = 3.4,
		-- The too-long forearms swing outside the shoulders.
		NeighbourArmSwing = 0.8,
		-- Slack between the widest point of the rig and a door jamb. The rig is
		-- moved by CFrame, not by a Humanoid, so this is the only thing keeping
		-- it off the frame.
		NeighbourClearance = 1.2,
	},

	-- ---------------------------------------------------------------------
	-- Street and lot geometry, in PLAN coordinates (x east, z south, y up),
	-- all relative to WorldOrigin. The Plan Generator works purely in these.
	-- ---------------------------------------------------------------------
	Streets = {
		-- The loop is a rectangle: Main Street along z = 0, Back Lane along
		-- z = -BlockDepth, joined by West Avenue and East Avenue -- plus ONE
		-- cross shortcut through the middle of the block. Seven edges over six
		-- junctions, so the plan carries two independent loops and no dead end.
		Length = 420,
		BlockDepth = 220,
		HalfWidth = 12,
		SidewalkWidth = 6,
		-- The short service passage the party arrives through, west of the
		-- south-west junction.
		ServicePassageLength = 74,
		ServicePassageHalfWidth = 9,
		KerbHeight = 0.4,
	},

	Lots = {
		HouseWidth = 30,
		HouseDepth = 34,
		-- Wall height of the ground storey shell. The interior ceiling is
		-- derived from the door height in Derived below and must not exceed it.
		StoreyHeight = 13,
		RoofHeight = 7,
		FrontYardDepth = 18,
		HedgeHeight = 3.2,
		HedgeThickness = 1.6,
		FenceHeight = 2.4,
		MailboxHeight = 4.2,
		-- FACADE_POLISH_20260922 (Codex' facade reference). Eaves overhang past
		-- the wall, fascia board depth, and the window unit: pane plus a
		-- surrounding frame and a sill, all standing PROUD of the outer wall face
		-- so they read from the pavement. Contract sizes (footprint, wall, roof,
		-- door) are unchanged; these only dress the shell.
		EavesOverhang = 1.4,
		FasciaDepth = 0.5,
		-- Two units per side of the door, centred at 0.3 and 0.7 of the 12-stud
		-- side panel: 2.1 studs of bare wall at the door and at the corner, 1.8
		-- between the units. The door-side bands carry the porch signal (left,
		-- seen from the street) and the house number (right).
		WindowWidth = 3.0,
		WindowHeight = 4.4,
		WindowFrame = 0.35,
		WindowProud = 0.3,
		FittingHeight = 8.6,
		-- Seeded jitter applied to each lot's along-street position. Small: the
		-- neighbourhood has to read as machine-laid, not organic.
		PositionJitter = 6,
	},

	-- Faded cream, dusty yellow, blue-grey; dark roofs. Three body colours and
	-- one roof colour is the whole exterior palette of the blockout.
	Colors = {
		FadedCream = Color3.fromRGB(226, 216, 190),
		DustyYellow = Color3.fromRGB(214, 194, 132),
		BlueGrey = Color3.fromRGB(163, 176, 184),
		DarkRoof = Color3.fromRGB(56, 56, 62),
		-- FACADE_POLISH_20260922: shared trim palette. Off-white window frames
		-- and fascia, frosted panes, graphite fittings, galvanised mailbox.
		Trim = Color3.fromRGB(232, 228, 214),
		Fascia = Color3.fromRGB(204, 198, 182),
		Pane = Color3.fromRGB(176, 190, 196),
		Graphite = Color3.fromRGB(58, 62, 66),
		MailboxMetal = Color3.fromRGB(168, 172, 176),
		MailboxFlag = Color3.fromRGB(196, 62, 54),
		Curtain = Color3.fromRGB(190, 176, 158),
		Hedge = Color3.fromRGB(78, 112, 68),
		-- Unnaturally uniform: every lawn is this exact green.
		Lawn = Color3.fromRGB(104, 156, 88),
		Asphalt = Color3.fromRGB(64, 66, 70),
		Kerb = Color3.fromRGB(196, 194, 188),
		Concrete = Color3.fromRGB(178, 176, 170),
		Timber = Color3.fromRGB(150, 128, 100),
		Hill = Color3.fromRGB(96, 134, 86),
		Interior = Color3.fromRGB(206, 198, 180),
		InteriorFloor = Color3.fromRGB(122, 98, 74),
		-- The few restrained Zyntra markings. Test equipment only, never the
		-- whole neighbourhood.
		Zyntra = Color3.fromRGB(66, 244, 218),
		ZyntraCabinet = Color3.fromRGB(48, 54, 58),
		-- Porch signal states.
		SignalSafe = Color3.fromRGB(96, 214, 128),
		SignalWarned = Color3.fromRGB(244, 186, 74),
		SignalDangerous = Color3.fromRGB(214, 78, 66),
	},

	-- ---------------------------------------------------------------------
	-- The three signal investigations. Free order; the zone-1 task is the
	-- forgiving one. No task may require hearing: each carries a VISUAL clue
	-- part as well as whatever audio the polish pass adds.
	-- ---------------------------------------------------------------------
	Objectives = {
		SignalGoal = 3,
		BriefingLine = "Investigate three residential signals. Restore the extraction beacon. Stay quiet.",
		-- The forgiving first task: no hold, a generous reach, and it reports no
		-- gameplay noise, so a first-timer cannot summon the Neighbour with it.
		ForgivingHoldSeconds = 0,
		ForgivingPromptDistance = 16,
		StandardHoldSeconds = 1.2,
		StandardPromptDistance = 10,
		-- Slack added to the prompt distance before the SERVER refuses a use.
		-- Same allowance Level 3's canUsePrompt applies.
		PromptDistanceAllowance = 6,
		-- The noise a non-forgiving investigation makes, in NoiseRegistry terms.
		InvestigationNoiseState = "relay",
		-- The finale: three short controls around the bus-stop cabinet, in
		-- order, all doable by one player walking from one to the next.
		CabinetControlCount = 3,
		CabinetControlHoldSeconds = 1.5,
		CabinetControlPromptDistance = 9,
		-- The clear warning between the last control and the exit opening.
		ExitWarningSeconds = 6,
	},

	-- ---------------------------------------------------------------------
	-- House states: safe / warned / dangerous.
	-- A state change is a routing problem, never a trap: nothing here can kill
	-- or lock a player, and the scheduler is forbidden from taking the last
	-- safe house in the active zone (Objective Controller enforces it).
	-- ---------------------------------------------------------------------
	HouseStates = {
		-- CALM_ARRIVAL_20260922. The scheduler's clock starts when the round is
		-- actually live (RoundActive after the arrival), never at build time,
		-- and the first house may not be warned before this many seconds of
		-- quiet street. Codex reproduced the old behaviour: danger lighting and
		-- an unstable house before the party had taken a step.
		CalmLeadSeconds = 24,
		-- How often the scheduler considers promoting one house.
		EvaluateIntervalSeconds = 9,
		-- Forewarning: the porch light turns amber and the HUD says so this
		-- long before the house actually becomes dangerous.
		WarnSeconds = 12,
		-- A dangerous house cools back to safe after this.
		DangerousSeconds = 35,
		-- Never more than this many non-safe houses at once, whatever the
		-- schedule says.
		MaximumUnsafe = 2,
		-- A house cannot be chosen again until this has passed.
		CooldownSeconds = 30,
		-- Placeholder tone slot. Empty string: no invented asset id. The art /
		-- audio pass fills this, and the Objective Controller only emits a cue
		-- name, never a sound, so an empty id is simply silent.
		WarnCueName = "HouseWarned",
		DangerCueName = "HouseDangerous",
	},

	-- ---------------------------------------------------------------------
	-- The Neighbour. Server-owned; the rig is a Part placeholder moved by
	-- CFrame along PathfindingService waypoints.
	-- ---------------------------------------------------------------------
	Neighbour = {
		RuntimeName = "The Neighbour",
		-- Detector extension point (ZyntraDetectorSensing): tag a live Model
		-- with a PrimaryPart and set its level. No detector change is needed.
		DetectorTag = "ZyntraDetectableEntity",
		DetectorLevel = 4,

		-- Movement speeds, studs/second. NoiseReporter defines the player
		-- sprint at 26; CHASE is deliberately SLOWER than that, because Level 4
		-- is decided by route and observation, not by a race that cannot be won.
		PatrolSpeed = 7,
		InvestigateSpeed = 13,
		SearchSpeed = 15,
		ChaseSpeed = 24,
		ReturnSpeed = 11,
		-- How fast the rig may turn, radians/second.
		TurnRate = 3.2,

		-- Detection. CHASE needs BOTH line of sight and this distance -- there
		-- is no omniscient targeting anywhere in the controller.
		VisionRange = 78,
		FieldOfViewDegrees = 110,
		-- Close range. Beyond this a seen player is noticed (ALERT) but the
		-- chase does not begin.
		DetectRange = 42,
		-- The telegraphed warning. The rig stops, straightens and publishes
		-- ALERT for this long before CHASE begins, so there is always a moment
		-- to break the line.
		AlertSeconds = 1.1,
		-- Broken line of sight for this long ends the chase.
		LoseContactSeconds = 3.5,
		-- Walking quietly (crouched) multiplies both hearing range and the
		-- chase's grip: a quiet player breaks contact in a third of the time.
		QuietContactMultiplier = 0.34,

		-- Hearing. Gameplay noise only, read from NoiseRegistry, and the
		-- Neighbour investigates the NOISE POSITION -- never the player's real
		-- position.
		HearingRange = 110,
		NoiseLifetimeSeconds = 4,

		-- How long it searches around a lost trail before returning.
		SearchSeconds = 14,
		-- Investigation gives up if the noise position is never reached.
		InvestigateSeconds = 18,
		-- How long a patrol leg may take before the watchdog picks a new one.
		PatrolLegSeconds = 26,
		PatrolPauseSeconds = 1.6,

		-- Attack. Never through a wall, never on a player inside a safe house.
		AttackRange = 5.2,
		AttackWindupSeconds = 0.5,
		AttackRecoverySeconds = 1.2,
		-- A player flushed or freshly placed is immune for this long, so no
		-- state change is ever an instant kill.
		GraceSeconds = 1.5,

		-- Navigation. Bounded recompute cadence plus a watchdog: the think loop
		-- runs on a timer, not per frame, and allocates nothing per frame.
		ThinkIntervalSeconds = 0.14,
		PathRecomputeSeconds = 0.6,
		ChasePathRecomputeSeconds = 0.35,
		PathGoalMoveThreshold = 6,
		WaypointSpacing = 4,
		WaypointReachDistance = 2.5,
		StuckSeconds = 1.6,
		MaxPathFailures = 4,
		-- A door may delay it, never deadlock it: after this the Neighbour
		-- opens or paths around whatever is in the way.
		DoorWaitSeconds = 2.5,
		-- Hard ceiling on one movement frame's delta, so a hitch cannot
		-- teleport the rig through a wall or onto a player.
		MaximumMovementDeltaSeconds = 0.05,
		MaximumStepStuds = 2.2,
	},

	-- ---------------------------------------------------------------------
	-- Performance budget. The World Builder COUNTS what it makes and the
	-- adapter asserts the count, because "a few dynamic lights" is not a rule
	-- anybody can keep by eye.
	-- ---------------------------------------------------------------------
	Performance = {
		-- Porch signals, the cabinet and the bus stop. Nothing decorative gets
		-- a light, and no light in Level 4 casts a shadow.
		MaximumDynamicLights = 12,
		-- Yield to the scheduler this often while building, so a big lot list
		-- cannot stall the server past the loading cover.
		BuildYieldEveryLots = 2,
		-- The blockout's own ceiling. A build that exceeds it is a bug, not a
		-- level: the adapter raises rather than shipping a frame-rate problem.
		MaximumWorldDescendants = 12000,
	},

	-- ---------------------------------------------------------------------
	-- ARRIVAL_SLICE_20260923 (docs/LEVEL4_VIDEO_DIRECTION_2026-09-22.md): the
	-- first measured section of the indoor-suburb direction. Two tall facade
	-- groups turn the service passage into a canyon, one bridge crosses it,
	-- and an artificial ceiling closes the whole neighbourhood. Plan
	-- coordinates. Each block's core is solid; everything on its faces is
	-- dressing that no ray stops on. No gameplay object moves for any of it.
	-- ---------------------------------------------------------------------
	Megastructure = {
		CeilingHeight = 300,
		CeilingThickness = 4,
		-- Light panels are emissive faces, not lights: none of them counts
		-- against MaximumDynamicLights.
		PanelSize = Vector3.new(20, 1, 36),
		PanelRowsZ = {110, 0, -110, -220, -330},
		PanelFromX = -140,
		PanelToX = 700,
		PanelPitchX = 64,
		CeilingColor = Color3.fromRGB(168, 164, 134),
		-- Four walls on the slab's edges, so the horizon is haze, not sky.
		FarWallColor = Color3.fromRGB(196, 190, 146),
		-- One residential module per 24 studs of face and 13 of storey. Near
		-- storeys keep full depth, mid storeys keep the silhouette with fewer
		-- parts, and everything above is one window band per module.
		ModuleWidth = 24,
		NearStoreys = 3,
		MidStoreys = 10,
		-- Every Nth module column is a stacked bay with a small gable; the rest
		-- are balconies. One window in LitEvery is lit.
		BayEvery = 3,
		LitEvery = 7,
		-- Faces are named by their outward normal. From/To trim a face along
		-- its length; SkipStoreys leaves the bottom storeys bare (the arrival
		-- door stands in front of that wall).
		Groups = {
			{
				Name = "South",
				Blocks = {
					{Name = "SouthCanyon", MinX = -160, MaxX = -24, MinZ = 24, MaxZ = 170,
						ColorKey = "DustyYellow", Faces = {{Outward = "-Z"}, {Outward = "+X", To = 128}}},
					{Name = "SouthTerrace", MinX = -24, MaxX = 340, MinZ = 128, MaxZ = 170,
						ColorKey = "FadedCream", Faces = {{Outward = "-Z"}}},
				},
			},
			{
				Name = "North",
				Blocks = {
					{Name = "NorthCanyon", MinX = -160, MaxX = -24, MinZ = -360, MaxZ = -24,
						ColorKey = "FadedCream", Faces = {{Outward = "+Z"}, {Outward = "+X"}}},
					{Name = "ArrivalWall", MinX = -100, MaxX = -84, MinZ = -24, MaxZ = 24,
						ColorKey = "DustyYellow", Faces = {{Outward = "+X", SkipStoreys = 1}}},
				},
			},
		},
		-- The one bridge: across the canyon near its mouth, deck on this storey.
		Bridge = {X = -34, Width = 16, Storey = 3, MinZ = -24, MaxZ = 24},
	},

	-- ---------------------------------------------------------------------
	-- Client lighting. ARRIVAL_SLICE_20260923: one enormous indoor room -- a
	-- high, even light and a long yellow-green haze, so the facades read all
	-- the way up to the ceiling. Colder and hazier under danger, and NEVER
	-- near-black: the minimum brightness below is what keeps the level
	-- readable on a phone in daylight.
	-- ---------------------------------------------------------------------
	Lighting = {
		CalmClockTime = 13.2,
		CalmBrightness = 2.2,
		CalmAmbient = Color3.fromRGB(132, 128, 100),
		CalmOutdoorAmbient = Color3.fromRGB(160, 158, 122),
		CalmFogColor = Color3.fromRGB(198, 196, 158),
		CalmFogStart = 160,
		CalmFogEnd = 1100,
		-- ARRIVAL_SLICE_20260923. While Lighting holds an Atmosphere the Fog
		-- values above do nothing, and the stock atmosphere hazes the ceiling
		-- into the sky. The controller grades the Atmosphere too.
		CalmAtmosphereDensity = 0.27,
		CalmAtmosphereHaze = 2.6,
		CalmAtmosphereColor = Color3.fromRGB(204, 198, 140),
		CalmAtmosphereDecay = Color3.fromRGB(186, 176, 112),

		DangerClockTime = 14.2,
		DangerBrightness = 1.8,
		DangerAmbient = Color3.fromRGB(100, 108, 104),
		DangerOutdoorAmbient = Color3.fromRGB(118, 128, 120),
		DangerFogColor = Color3.fromRGB(150, 160, 146),
		DangerFogStart = 60,
		DangerFogEnd = 420,
		DangerAtmosphereDensity = 0.31,
		DangerAtmosphereHaze = 2.2,
		DangerAtmosphereColor = Color3.fromRGB(162, 172, 158),
		DangerAtmosphereDecay = Color3.fromRGB(118, 130, 122),
		-- Offset 0 keeps the haze off the ceiling when looking straight up.
		AtmosphereOffset = 0,
		AtmosphereGlare = 0,

		-- Readability floor. Nothing in Level 4 may drive Lighting.Brightness
		-- below this, on any device, in any state.
		MinimumBrightness = 1.6,
		TransitionSeconds = 3.5,
	},
}

-- ---------------------------------------------------------------------------
-- Derived envelopes. These are the numbers the World Builder actually builds
-- with, and they exist so nobody has to guess whether a door fits: they are
-- computed from Body above, and the Test Suite re-derives them independently.
-- ---------------------------------------------------------------------------
local body = Configuration.Body

-- Two players abreast: 2 x 2.0 + 2.0 = 6.0 studs.
local playerPassWidth = body.PlayerWidth * 2 + body.PlayerPassGap
-- The Neighbour with its arm swing and jamb clearance: 3.4 + 0.8 + 1.2 = 5.4.
local neighbourPassWidth = body.NeighbourShoulderWidth + body.NeighbourArmSwing + body.NeighbourClearance

Configuration.Derived = {
	PlayerPassWidth = playerPassWidth,
	NeighbourPassWidth = neighbourPassWidth,
	-- Whichever body needs more room decides every opening in the level: 6.0.
	DoorWidth = math.max(playerPassWidth, neighbourPassWidth),
	-- Head clearance over the entity: 9.5 + 1.0 = 10.5.
	DoorHeight = body.NeighbourHeight + 1,
	-- Interior passages are exactly as wide as the doors, so the widest thing
	-- that gets through a door can always get back out.
	PassageWidth = math.max(playerPassWidth, neighbourPassWidth),
	-- The ceiling has to clear the door it contains.
	InteriorCeiling = Configuration.Lots.StoreyHeight,
	-- Stairs: tread deep enough to walk, rise under the Humanoid's 2-stud
	-- MaxSlopeAngle-free step, and exactly as wide as a door.
	StairWidth = math.max(playerPassWidth, neighbourPassWidth),
	StairRise = 0.9,
	StairRun = 1.6,
	-- PathfindingService agent. Radius covers half the widest point plus
	-- clearance; height covers the rig plus a little.
	AgentRadius = (body.NeighbourShoulderWidth + body.NeighbourArmSwing) / 2 + body.NeighbourClearance / 2,
	AgentHeight = body.NeighbourHeight + 0.5,
}

assert(Configuration.Derived.InteriorCeiling > Configuration.Derived.DoorHeight,
	"Level 4: the interior ceiling must clear the door height it contains")
assert(Configuration.Streets.HalfWidth * 2 > Configuration.Derived.AgentRadius * 4,
	"Level 4: the street must be navigable by the configured agent")

table.freeze(Configuration.Body)
table.freeze(Configuration.Streets)
table.freeze(Configuration.Lots)
table.freeze(Configuration.Colors)
table.freeze(Configuration.Objectives)
table.freeze(Configuration.HouseStates)
table.freeze(Configuration.Neighbour)
table.freeze(Configuration.Performance)
table.freeze(Configuration.Lighting)
table.freeze(Configuration.Derived)
table.freeze(Configuration)

return Configuration
