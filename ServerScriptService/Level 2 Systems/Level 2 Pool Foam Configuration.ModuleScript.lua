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
		MaximumCameraOriginError = 22,
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
		-- Legacy statue reveal tuning remains available if FreezeWhileObserved is
		-- enabled again. The Pool Noodle's current mechanic chases while visible.
		RevealOverrunSeconds = 0.50,
		RevealOverrunCooldown = 0.0,
		RequireServerLineOfSight = true,
		ServerLineOfSightInterval = 0.12,
		FreezeWhileObserved = false,
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
		-- While an active Pool Noodle has not yet been looked at, its stalking
		-- speed rises continuously. The first validated look freezes the earned
		-- bonus and changes to Hunt pace; it never toggles with camera-edge noise.
		SpeedRamp = {
			Enabled = true,
			AccelerationPerSecond = 0.65,
			MaximumBonus = 12.0,
			MaximumSpeed = 22.0,
			ChaseMinimumSpeed = 13.0,
			FreezeOnChase = true,
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

	-- Empty IDs are deliberate: gameplay must remain correct without media.
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
