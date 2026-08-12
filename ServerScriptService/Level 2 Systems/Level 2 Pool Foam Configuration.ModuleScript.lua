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
		-- Every genuine look-back gets a short readable movement reveal. Observation
		-- release hysteresis prevents camera-edge flicker from repeatedly granting it.
		RevealOverrunSeconds = 0.50,
		RevealOverrunCooldown = 0.0,
		RequireServerLineOfSight = true,
		ServerLineOfSightInterval = 0.12,
		FreezeWhileObserved = true,
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
		Speeds = {
			Dormant = 0,
			Stalk = 4.5,
			Investigate = 7.0,
			Walk = 7.0,
			Hunt = 4.5,
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
		Walk = { Looped = true, Priority = Enum.AnimationPriority.Movement, Speed = 1.0, Fade = 0.16 },
		Caught = { Looped = true, Priority = Enum.AnimationPriority.Action, Speed = 1.0, Fade = 0.08 },
		Hunt = { Looped = true, Priority = Enum.AnimationPriority.Movement, Speed = 1.12, Fade = 0.10 },
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
