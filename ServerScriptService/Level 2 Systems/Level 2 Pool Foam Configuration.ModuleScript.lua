--!strict
-- Central, asset-agnostic tuning for the Level 2 Pool Foam encounter.
-- This module has no side effects. The proxy encounter is authorized by
-- default; set Enabled false for a one-switch rollback during playtesting.

local Configuration = {
	Version = 2,
	Enabled = true,
	WakeDelaySeconds = 15,

	AssetFolderName = "Level2Assets",
	RuntimeFolderName = "Level 2 Pool Foam Runtime",
	GenericHostileTag = "Level2HostileEntity",
	SpecificTag = "Level2PoolFoamEntity",
	KeepAnchored = true,

	Remotes = {
		FolderName = "Level 2 Pool Foam Remotes",
		ClientReport = "ClientReport",
		ClientEvent = "ClientEvent",
	},

	-- Final art integration changes only these two TemplateName values. Each
	-- named Model is resolved directly beneath ServerStorage.Level2Assets.
	Slots = {
		Primary = {
			Id = "Primary",
			TemplateName = "PoolFoamPrimaryTemplate",
			ProxyStyle = "Bloom",
			Profile = "PoolFoamPrimary",
		},
		Secondary = {
			Id = "Secondary",
			TemplateName = "PoolFoamSecondaryTemplate",
			ProxyStyle = "Spire",
			Profile = "PoolFoamSecondary",
		},
	},
	SlotOrder = { "Primary", "Secondary" },

	Attributes = {
		Slot = "PoolFoamSlot",
		TemporaryProxy = "PoolFoamTemporaryProxy",
		FactoryOwned = "PoolFoamFactoryOwned",
		ProxyVisual = "PoolFoamProxyVisual",
		AnimationState = "PoolFoamAnimationState",
		ResolvedAnimationState = "PoolFoamResolvedAnimationState",
		MotionState = "MotionState",
		ActionSerial = "ActionSerial",
		Profile = "Profile",
		InstanceId = "PoolFoamEntityId",
		AnimationPaused = "PoolFoamAnimationPaused",
	},

	States = { "Idle", "Walk", "Caught", "Hunt", "Attack", "Collapse" },

	Observation = {
		ReportInterval = 0.125,
		MinReportInterval = 0.10,
		ReportTimeout = 0.85,
		MaximumReportDistance = 180,
		-- A look now freezes a foam (FreezeWhileObserved below), so a report has to
		-- be a camera this body can hold. Rounds run LockFirstPerson (zoom 0.5):
		-- 8 studs covers the head offset plus report/replication lag at slide
		-- speed. The yaw bound is checked against the server-known root facing.
		-- A report outside either falls back to the server head view.
		MaximumCameraOriginError = 8,
		MaximumCameraYawError = 60,
		BroadPhaseFovDegrees = 100,
		ObservedFovDegrees = 72,
		AcquireSeconds = 0.10,
		ReleaseSeconds = 0.24,
		NearThreatDistance = 18,
		-- A real, server-validated camera look permanently starts this entity's hunt.
		-- The latch makes the transition immune to report/camera-edge flicker.
		TriggerChaseOnObserve = true,
		ChaseGraceSeconds = 0.45,
		-- SERVER BACKSTOP FOR THE LATCH (2026-09-05).
		--
		-- `Observed` above stays report-driven on purpose: the freeze/statue
		-- semantics need the player's REAL camera, and OR-ing in a server head
		-- view would freeze an entity whose watcher is legitimately looking away.
		-- But the LATCH must not be the client's decision alone. A client that
		-- sends perfectly well-formed reports (right protocol and generation,
		-- increasing sequence, camera origin at its own head) whose look
		-- direction simply never covers a foam model never trips
		-- TriggerChaseOnObserve, and instantKill refuses to fire without the
		-- latch — so that player is permanently unkillable by Level 2's only
		-- hostile.
		--
		-- Independently of every client report, an ACTIVE entity that keeps one
		-- living, targetable player inside ProximityLatchRadius studs with a
		-- clear server line of sight, and BELOW ProximityLatchMaximumSpeed, for
		-- ProximityLatchSeconds latches the chase exactly as a look does.
		-- Nothing here can release a latch or make one harder to earn; it can
		-- only add one.
		--
		-- Read the movement code before retuning these. An un-latched active
		-- entity already pursues the nearest eligible player and PARKS at
		-- Movement.TargetStopDistance (4.5) — so proximity is not something a
		-- player chooses, and a wide radius plus a short dwell would make this
		-- backstop the primary latch and delete the look-reveal beat entirely.
		-- The two gates that do the real work are therefore:
		--   * the radius is barely wider than the entity's own stop distance, so
		--     "inside it" means the thing is standing on you, not in the room;
		--   * the candidate must be roughly STATIONARY. A player who is walking,
		--     fleeing or working is never latched by proximity — only one who
		--     lets the foam sit on them for seconds while never looking at it,
		--     which is the camper and the report-spoofer, not honest play.
		-- Set ProximityLatchEnabled = false for a one-switch rollback.
		ProximityLatchEnabled = true,
		ProximityLatchSeconds = 7,
		ProximityLatchRadius = 8,
		-- Flat (XZ) stud/s. Roblox walk speed is 16, so this is "standing".
		ProximityLatchMaximumSpeed = 3,
		-- LOOKING STOPS IT (owner, card wdz28z81, 2026-09-23): while any living
		-- player holds a validated look on a foam it stands completely still --
		-- no overrun step, no kill -- and the speed it earned chasing is reset.
		-- Looking away resumes the chase from Movement.SpeedRamp.ChaseMinimumSpeed.
		-- The first look still latches the chase (TriggerChaseOnObserve above).
		RevealOverrunSeconds = 0,
		RevealOverrunCooldown = 0.0,
		RequireServerLineOfSight = true,
		ServerLineOfSightInterval = 0.12,
		FreezeWhileObserved = true,
	},

	-- Pool Foam listens to the shared ServerScriptService.NoiseRegistry — the
	-- same list Level 1's Entity hears: player footsteps reported by
	-- NoiseReporter, plus Level 2's pump motors. Hearing only decides WHOM the
	-- entity walks toward and where it patrols. The look-triggered chase latch,
	-- its grace window and the speed ramp are untouched by everything in here.
	Hearing = {
		Enabled = true,
		-- Studs, scaled per sound by that sound's loudness inside
		-- NoiseRegistry.GetBest: a sprint (1.0) is heard this far, a running
		-- pump (2.0) twice as far, a walk (0.45) less than half.
		HearingRange = 120,
		-- A player standing where a heard noise came from counts as this
		-- fraction of their true distance while a target is picked, so a noisy
		-- player 100 studs away is chosen over a silent one at 60. Everyone
		-- unheard keeps plain nearest-distance, and 1.0 turns the preference off
		-- without turning hearing off. The TRUE distance still decides stopping
		-- and killing — this weight never reaches those.
		NoiseWeight = 0.55,
		-- How close a player has to be to the noise for it to count as theirs.
		-- Wider than a room, so a sprinter who has moved on since the report is
		-- still credited; narrow enough that a pump does not brand a bystander
		-- in the next hall.
		AttributionRadius = 35,
		-- Sounds age out after NoiseRegistry's own DECAY (5 s, shared with
		-- Level 1); the controller prunes the list once per session tick. A
		-- heard target is re-picked every tick like a distance target, so noise
		-- can never pin the encounter on one player.
	},

	Movement = {
		UpdateInterval = 0.10,
		RepathInterval = 0.55,
		RepathDistance = 5.0,
		WaypointSpacing = 5.0,
		WaypointArrivalDistance = 1.25,
		WaypointTolerance = 2.5,
		TargetStopDistance = 4.5,
		-- Root-to-root reach distance. A valid unobstructed target dies
		-- immediately when an active entity closes inside this radius.
		KillDistance = 5.5,
		SearchSeconds = 7.0,
		RetreatSeconds = 3.5,
		AgentRadius = 2.2,
		AgentHeight = 6.0,
		AgentCanJump = false,
		FootClearance = 0.08,
		FloorProbeAbove = 12,
		FloorProbeDepth = 80,
		MaxStepHeight = 3.5,
		StuckRepathSeconds = 1.1,
		UnreachableTargetCooldown = 3.0,
		-- Certify only the first 96 studs of a route and fetch the next piece
		-- with 48 left (the Pool Slide's measured values, 2026-09-21). 0 = the
		-- old whole-route certification. See the Navigator's PLAN HORIZON note.
		PlanHorizon = 96,
		PlanHorizonExtend = 48,
		-- An unseen, pursuing Pool Noodle speeds up continuously: stalking from
		-- its phase pace, chasing from ChaseMinimumSpeed, both capped at
		-- MaximumSpeed. Every validated look resets the bonus to zero (card
		-- wdz28z81), so a chase that is watched never keeps what it earned.
		SpeedRamp = {
			Enabled = true,
			AccelerationPerSecond = 0.65,
			MaximumBonus = 12.0,
			MaximumSpeed = 22.0,
			ChaseMinimumSpeed = 13.0,
			FreezeOnChase = false,
		},
		Speeds = {
			Dormant = 0,
			Stalk = 7.5,
			Investigate = 7.0,
			Walk = 7.0,
			Hunt = 7.5,
			Search = 6.0,
			Retreat = 8.5,
		},
	},

	-- NO TWO FOAM MODELS MAY OCCUPY THE SAME SPACE (2026-09-21).
	--
	-- Level 2 runs one clone per generated Kids Area, five on a full map. Every
	-- part of every clone is anchored with CanCollide false, and the Navigator
	-- EXCLUDES the whole runtime folder from its own body queries, so neither the
	-- engine nor the route checks keep two of them apart: they walk through each
	-- other at spawn, on crossing routes and whenever several chase one player.
	-- The controller's separation pass is the only thing that keeps them apart.
	--
	-- Every distance below is DERIVED, not chosen, and the live radius is not in
	-- this table at all: it is measured per model from its bounding box at spawn
	-- and again when a final template replaces a proxy, so nothing here has to be
	-- retuned when the art lands.
	Separation = {
		Enabled = true,
		-- Used only when a model's bounding box cannot be read. Half the larger
		-- horizontal extent of the shipped Bloom proxy root, 7.5 x 4.8 x 6.5
		-- (Proxy Factory, createRoot) -> 7.5 / 2.
		FallbackRadius = 3.75,
		-- Sanity clamp on the measured radius. The floor is half the narrowest
		-- authored proxy (the Spire root is 4.8 wide -> 2.4, rounded down); the
		-- ceiling is far past any authored template and exists so one mis-scaled
		-- import cannot park the whole group.
		MinimumRadius = 1.0,
		MaximumRadius = 8.0,
		-- Studs of clear air kept on top of rA + rB. Two entities can close at
		-- 2 x Movement.SpeedRamp.MaximumSpeed = 44 studs/s, which is 0.73 studs
		-- per 60 Hz frame, so 1.5 gives the pass two frames of warning before the
		-- models actually touch.
		Padding = 1.5,
		-- Longest correction per pass. Equals the Navigator's MaxTravelStep, the
		-- longest horizontal distance it validates in a single placement. It is
		-- a ceiling, not the usual size: a correction is also limited to what the
		-- creature could have WALKED in that frame.
		MaximumOffset = 0.9,
		-- Floor for that per-frame walking limit, so an entity that is parked
		-- (desired speed 0) can still be eased apart. Movement.Speeds.Stalk, the
		-- slowest pace this encounter ever moves at.
		MinimumCorrectionSpeed = 7.5,
		-- How far off its own heading a neighbour still counts as being IN THE
		-- WAY: cos 60 degrees. Inside that cone the correction is lateral (go
		-- round) and a blocked yielder is held, because pushing an entity
		-- backwards along the line its route is pulling it forward on is exactly
		-- the cancellation that makes a separation rule shiver. Outside it the
		-- push is radial, which is roughly perpendicular to the route and cannot
		-- fight it. 1.0 would only treat a dead-on collision as blocking; 0
		-- would treat a neighbour directly behind as blocking too.
		AheadCosine = 0.5,
		-- A stand-off -- nothing fits on any side, a corridor as wide as the body
		-- -- holds BOTH entities under a lease this long, refreshed every pass
		-- while it lasts. It only has to outlive the gap between two passes; the
		-- worst frame ever measured in this place was 13 FPS (0.077 s), so this
		-- covers two of those and expires within a few frames of the cause going.
		HoldSeconds = 0.15,
		-- How long the yielder waits before backing out. Longer than one
		-- Movement.RepathInterval (0.55) so ordinary re-routing gets first
		-- refusal, short enough that a corridor meeting is never a standstill.
		YieldSeconds = 1.2,
		-- How far it then backs out along its own trail: one contact diameter
		-- (2 x 3.75 = 7.5) rounded up, so one retreat clears the other's disc.
		RetreatStuds = 8,
		-- A yielder with nowhere to back out to stops being held for this long,
		-- so a pair that cannot resolve overlaps for a moment instead of standing
		-- frozen against each other for the rest of the round.
		ReleaseSeconds = 2.0,
		-- Minimum distance between two spawn positions: one contact diameter plus
		-- the padding (7.5 + 1.5). The spawn chooser only ever picks between REAL
		-- entity nodes; it never invents a position, because an unvalidated spawn
		-- fails the navigator's floor check and kills the whole encounter.
		SpawnGap = 9.0,
		-- How often the debug readbacks are written to ReplicatedStorage."Level 2
		-- State". They are diagnostics; the pass itself runs every Heartbeat.
		--   Level2_PoolFoamMinSeparation  smallest centre distance seen this round
		--   Level2_PoolFoamOverlapFrames  steps with a pair inside rA + rB
		--   Level2_PoolFoamYieldCount     bounded waits that ended in a back-out
		--   Level2_PoolFoamSeparationMs   moving average cost of the pass
		PublishInterval = 0.5,
	},

	PhaseOrder = { "Dormant", "Foreshadow", "Pressure", "Finale" },
	Phases = {
		Dormant = {
			MinimumPumps = 0,
			MaximumActive = 0,
			AllowAttacks = false,
			SpeedMultiplier = 0,
		},
		Foreshadow = {
			MinimumPumps = 1,
			MaximumActive = 5,
			AllowAttacks = false,
			SpeedMultiplier = 0.75,
		},
		Pressure = {
			MinimumPumps = 2,
			MaximumActive = 5,
			AllowAttacks = true,
			SpeedMultiplier = 1.0,
		},
		Finale = {
			MinimumPumps = 3,
			MaximumActive = 5,
			AllowAttacks = true,
			SpeedMultiplier = 1.12,
		},
	},

	-- One positional movement voice per entity. Idle is optional; Caught,
	-- Collapse and Secondary remain reserved until those cues are authored.
	Audio = {
		Enabled = true,
		RollOffMinDistance = 12,
		RollOffMaxDistance = 110,
		LoopVolumes = { Idle = 0.06, Walk = 0.18, Hunt = 0.24 },
		AttackVolume = 0.24,
	},

	-- Empty IDs are deliberate: gameplay must remain correct without media.
	-- First delivery needs Primary Walk/Hunt loops and a short Attack one-shot.
	-- All currently spawned clones use Primary; do not invent placeholder IDs.
	AudioIds = {
		Primary = {
			Idle = "",
			Walk = "",
			Caught = "",
			Hunt = "",
			Attack = "",
			Collapse = "",
		},
		Secondary = {
			Idle = "",
			Walk = "",
			Caught = "",
			Hunt = "",
			Attack = "",
			Collapse = "",
		},
	},

	AnimationIds = {
		Primary = {
			Idle = "",
			Walk = "rbxassetid://75270256720943",
			Caught = "",
			Hunt = "",
			Attack = "",
			Collapse = "",
		},
		Secondary = {
			Idle = "",
			Walk = "",
			Caught = "",
			Hunt = "",
			Attack = "",
			Collapse = "",
		},
	},

	AnimationTracks = {
		Idle = { Looped = true, Priority = Enum.AnimationPriority.Idle, Speed = 1.0, Fade = 0.18 },
		Walk = { Looped = true, Priority = Enum.AnimationPriority.Movement, Speed = 1.65, Fade = 0.16 },
		Caught = { Looped = true, Priority = Enum.AnimationPriority.Action, Speed = 1.0, Fade = 0.08 },
		Hunt = { Looped = true, Priority = Enum.AnimationPriority.Movement, Speed = 1.85, Fade = 0.10 },
		Attack = { Looped = false, Priority = Enum.AnimationPriority.Action2, Speed = 1.0, Fade = 0.05 },
		Collapse = { Looped = false, Priority = Enum.AnimationPriority.Action4, Speed = 1.0, Fade = 0.10 },
	},

	-- Temporary proxies use only these event-driven color/transparency changes.
	-- No frame loop or visual tween is required for gameplay correctness.
	ProxyVisualStates = {
		Idle = { Tint = Color3.fromRGB(205, 232, 228), Blend = 0.08, TransparencyAdd = 0.00 },
		Walk = { Tint = Color3.fromRGB(151, 218, 221), Blend = 0.18, TransparencyAdd = 0.00 },
		Caught = { Tint = Color3.fromRGB(118, 160, 174), Blend = 0.50, TransparencyAdd = 0.06 },
		Hunt = { Tint = Color3.fromRGB(83, 223, 221), Blend = 0.38, TransparencyAdd = -0.04 },
		Attack = { Tint = Color3.fromRGB(245, 255, 250), Blend = 0.62, TransparencyAdd = -0.08 },
		Collapse = { Tint = Color3.fromRGB(63, 91, 93), Blend = 0.58, TransparencyAdd = 0.35 },
	},
}

local function deepFreeze(value: any)
	if type(value) ~= "table" or table.isfrozen(value) then
		return
	end

	for _, child in pairs(value) do
		deepFreeze(child)
	end
	table.freeze(value)
end

deepFreeze(Configuration)
return Configuration
