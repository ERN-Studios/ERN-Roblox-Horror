--!strict
-- Level 3 Configuration
-- Production tuning for the abandoned 1990s mall service-space level.
-- Level 3 owns one dedicated hostile: the Mall Manager. Its custom bone rig,
-- navigation, awareness, attacks, and lifecycle are isolated from Level 1.

local Configuration = {
	Version = 26,
	WorldName = "Level 3 Generated World",
	StateFolderName = "Level 3 State",
	RemotesFolderName = "Level 3 Remotes",
	ClientEventName = "ClientEvent",
	MallManagerMotionEventName = "MallManagerMotion",
	HideRequestEventName = "Level3HideRequest",
	WorldOrigin = Vector3.new(6200, 24, 0),
	RoomHeight = 14,
	WallThickness = 1.5,
	FloorThickness = 1,
	CeilingThickness = 1,
	-- Every link uses one continuous, human-scale tunnel cross-section.
	-- Room openings consume these exact outer dimensions so neither the ceiling
	-- nor side walls step inward at a room boundary.
	CorridorWidth = 14,
	CorridorHeight = 10.5,
	ModuleGoal = 5,
	-- Seeded topology is generated only when a Level 3 party launches.  The
	-- bounded district plan is larger than the former authored graph while still
	-- keeping each six-player reserved server within a predictable build budget.
	Layout = {
		GeneratorVersion = 1,
		DistrictCount = 3,
		RoomsPerDistrict = 8,
		GenerationAttempts = 32,
		RetryStride = 104729,
		FallbackSeeds = {101, 7331, 65537, 1900813},
		MinimumRoomWidth = 60,
		MaximumRoomWidth = 78,
		MinimumRoomDepth = 52,
		MaximumRoomDepth = 68,
		MinimumRoomHeight = 11,
		MaximumRoomHeight = 13,
		MinimumInternalGap = 24,
		MaximumInternalGap = 34,
		MinimumGatewayGap = 38,
		MaximumGatewayGap = 48,
		MinimumCorridorLength = 18,
		RowHalfSpacing = 90,
		ExtraLinksPerDistrict = 2,
		MinimumModuleSeparation = 105,
		BuildYieldEveryRooms = 3,
		BuildYieldEveryCorridors = 2,
		HideTableCount = 24,
	},
	TextureStuds = {
		PartyCarpet = 28,
		PartyCarpetNeon = 22,
		PartyCarpetRed = 30,
		CityCarpet = 52,
		Wallpaper = 18,
		OrangeWall = 22,
		Tablecloth = 10,
	},
	Textures = {
		PartyCarpet = "rbxassetid://92795890253148",
		PartyCarpetNeon = "rbxassetid://110230144446272",
		PartyCarpetRed = "rbxassetid://108064770913201",
		CityCarpet = "rbxassetid://75635502248205",
		PastelWallpaper = "rbxassetid://96252806287644",
		OrangeWall = "rbxassetid://128270554927663",
		ConfettiTablecloth = "rbxassetid://103412925025303",
		FinalExitDoor = "rbxassetid://120063024460642",
		KidsDrawingsAtlas = "rbxassetid://136455642832077",
		KidsDrawingsWholesome25 = "rbxassetid://128767366284181",
		KidsDrawingsDisturbing25 = "rbxassetid://132144680342985",
		KidsNotesAtlas = "rbxassetid://81550568434150",
		CDCoversAtlas = "rbxassetid://88160214591687",
	},
	Audio = {
		FluorescentHum = "rbxassetid://92576512092725",
		HVAC = "rbxassetid://9125446543",
		DoorRattle = "rbxassetid://9118901593",
		DoorMovement = "rbxassetid://9119631915",
		-- Reserved for the replacement lights-out cue.
		PowerDown = "",
		-- Group-owned song uploaded specifically for the synchronized Level 3 sequence.
		RoomListeningSong = "rbxassetid://140244948455675",
		-- Reserved Level 3 scare slots. Add group-owned IDs when the sounds are ready.
		ScareBalloonPop = "",
		ScareChairScrape = "",
		ScareChildGiggle = "",
		ScarePAWhisper = "",
		ScareRunningSteps = "",
		-- Reserved cues fired by the Objective Controller (exit unseal + escape).
		ExitUnlocked = "",
		Escape = "",
		-- Exact group-owned Mall Manager walk uploads. Their names are preserved
		-- verbatim in the saved Sound prototypes and runtime emitter.
		["Mall Manager Walk Sound 1"] = "rbxassetid://86969848436282",
		["Mall Manager Walk Sound 2"] = "rbxassetid://125163405380423",
		["Mall Manager Walk Sound 3"] = "rbxassetid://131363472955449",
		["Mall Manager Walk Sound 4"] = "rbxassetid://128260682244977",
		-- Group-owned Mall Manager vocals. Blackout is reproduced spatially from
		-- corridor-opening markers; chase remains attached to the balloon head.
		MallManagerBalloonScream = "rbxassetid://105088070261380",
		MallManagerAlert = "",
		MallManagerCapture = "",
		MallManagerBlackout = "rbxassetid://125407251695204",
	},
	MusicSequence = {
		DurationSeconds = 180.035917,
		-- Every fixture visibly dies for five seconds before the exact 2:30 blackout.
		-- The song keeps playing in darkness. Its distant scream begins during the
		-- final three song seconds; the song end still starts the 30-second hunt.
		BlackoutStartSeconds = 150,
		PreBlackoutFlickerSeconds = 5,
		BlackoutScreamLeadSeconds = 3,
		PostSongBlackoutSeconds = 30,
		BlackoutSeconds = 60.035917,
		CycleEndSeconds = 210.035917,
		RecoveryFlickerSeconds = 3.2,
		PreloadLeadSeconds = 1.5,
		RoomVolume = 0.48,
		CorridorVolume = 0.045,
		RoomFadeDistance = 18,
		VolumeFadeSeconds = 1.15,
		TimelineDriftTolerance = 0.32,
		-- Only the two nearest synchronized PA speakers contribute to the local
		-- mix. This prevents coherent stacking while preserving coverage in the
		-- largest rooms and a faint bleed from the next room.
		SpeakerVolume = 0.30,
		SpeakerMinDistance = 18,
		SpeakerMaxDistance = 180,
		SpeakerMaxAudibleVoices = 2,
		SpeakerSecondaryVolumeScale = 0.25,
	},
	MallManager = {
		TemplateName = "MallManagerTemplate",
		RuntimeName = "Mall Manager",
		-- Signal Hall remains an authored emergency fallback only. Every real blackout
		-- spawn is selected near a random member of the densest living player group.
		SpawnRoomId = "SignalHall",
		SpawnMinimumDistance = 90,
		SpawnPreferredDistance = 125,
		SpawnMaximumDistance = 180,
		SpawnGroupRadius = 75,
		SpawnRoomMargin = 10,
		-- Radius 5 matches the animated root-relative body sway. The slightly
		-- larger local sweep preserves a visible buffer from walls and corners.
		AgentRadius = 5,
		SweepRadius = 5.25,
		AgentHeight = 10,
		WaypointSpacing = 4,
		WaypointReachDistance = 1.25,
		PathLookaheadWaypoints = 4,
		BlackoutPathLookaheadWaypoints = 7,
		PathSampleHeight = 0.5,
		CorridorCenteringLead = 12,
		DirectPathRange = 32,
		BlackoutDirectPathRange = 48,
		GoalTolerance = 3.2,
		PathGoalMoveThreshold = 7,
		BlackoutPathGoalMoveThreshold = 5,
		PathRecomputeSeconds = 0.45,
		BlackoutPathRecomputeSeconds = 0.25,
		ThinkIntervalSeconds = 0.12,
		BlackoutThinkIntervalSeconds = 0.10,
		StuckSeconds = 0.85,
		StuckDistance = 0.65,
		MaxPathFailures = 3,
		ObstructionRecoveryAttempts = 3,
		ProgressResetDistance = 8,
		MovementAcceleration = 48,
		MovementDeceleration = 72,
		BlackoutMovementAcceleration = 96,
		BlackoutMovementDeceleration = 120,
		TurnResponsiveness = 9,
		BlackoutTurnResponsiveness = 18,
		MaximumMovementDeltaSeconds = 0.05,
		MotionSnapshotRate = 30,
		MotionInterpolationDelaySeconds = 0.065,
		MotionBufferSamples = 8,
		MotionLongGapSeconds = 0.30,
		ChaseVisualLossGraceSeconds = 1.25,
		BlackoutTargetLeadSeconds = 0.25,
		BlackoutTargetLeadMaximumDistance = 8,
		AttackRange = 4.4,
		AttackConfirmRange = 5.4,
		VerticalAttackTolerance = 6,
		AttackWindupSeconds = 0.40,
		BlackoutAttackWindupSeconds = 0.22,
		AttackRecoverySeconds = 0.65,
		BlackoutAttackRecoverySeconds = 0.40,
		RetargetDistanceAdvantage = 28,
		-- The blackout-only Manager begins moving on the reveal frame and never idles at patrol goals.
		SpawnGraceSeconds = 0,
		PatrolPauseSeconds = 0,
		NoiseLifetimeSeconds = 4,
		CrouchHearingMultiplier = 0.18,
		SearchPointRadius = 18,
		WalkReferenceSpeed = 13,
		AnimationFadeSeconds = 0.18,
		MinimumAnimationSpeed = 0.30,
		MaximumAnimationSpeed = 2.6,
		ContinuousAnimationPlaybackSpeed = 0.65,
		-- Four real touchdown phases measured from the published 2.9-second limp.
		-- Phase-following keeps audio locked to the feet at every playback speed.
		FootstepSoundNames = {
			"Mall Manager Walk Sound 1",
			"Mall Manager Walk Sound 2",
			"Mall Manager Walk Sound 3",
			"Mall Manager Walk Sound 4",
		},
		FootstepAnimationTimes = {0.8, 1.2, 2.266667, 2.666667},
		FootstepEmitterHeight = 0.18,
		-- Strong at close range, with a shorter tail so it does not fill the whole mall.
		FootstepVolume = 2.0,
		FootstepRollOffMinDistance = 20,
		FootstepRollOffMaxDistance = 90,
		BlackoutScreamSoundName = "Mall Manager Walk Blackout Scream",
		BlackoutScreamDurationSeconds = 8.071836735,
		-- The blackout vocal is one distant corridor source, never a copy on the
		-- nearby Manager. Structural occlusion plus filtering makes it read as
		-- several rooms away instead of eight synchronized screams at once.
		BlackoutScreamVolume = 0.90,
		BlackoutScreamRollOffMinDistance = 22,
		BlackoutScreamRollOffMaxDistance = 210,
		BlackoutScreamMaxLocalVoices = 1,
		BlackoutScreamSourceMinimumDistance = 75,
		BlackoutScreamSourcePreferredDistance = 115,
		BlackoutScreamSourceMaximumDistance = 175,
		BlackoutScreamMinimumStructuralOccluders = 2,
		BlackoutScreamLowGain = 0,
		BlackoutScreamMidGain = -9,
		BlackoutScreamHighGain = -24,
		BlackoutScreamReverbDensity = 0.88,
		BlackoutScreamReverbDiffusion = 0.82,
		BlackoutScreamReverbDecayTime = 2.2,
		BlackoutScreamReverbDryLevel = -3,
		BlackoutScreamReverbWetLevel = -10,
		ChaseScreamSoundName = "Mall Manager Chase Scream 1",
		ChaseScreamDurationSeconds = 22.569795918,
		ChaseScreamVolume = 1.25,
		ChaseScreamRollOffMinDistance = 18,
		ChaseScreamRollOffMaxDistance = 260,
		-- The clip is 22.57 seconds; a longer cooldown prevents state-flap stacking.
		ChaseScreamCooldownSeconds = 25,
		Normal = {
			-- Neutral wandering is intentionally slow and uses the limping walk.
			PatrolSpeed = 4.5,
			InvestigateSpeed = 13,
			SearchSpeed = 15,
			ChaseSpeed = 22,
			VisionRange = 115,
			FieldOfViewDegrees = 120,
			ProximitySenseRange = 12,
			HearingWalkRange = 65,
			HearingSprintRange = 120,
			OccludedHearingMultiplier = 0.58,
			FlashlightVisibilityMultiplier = 1.40,
			AcquireSeconds = 0.40,
			SuspicionDecaySeconds = 0.80,
			AlertSeconds = 0.30,
			MemorySeconds = 6,
			SearchSeconds = 10,
		},
		Blackout = {
			-- Exact 30% reduction across every blackout movement state. Scaling the
			-- whole profile preserves its escalation and prevents SEARCH outrunning CHASE.
			PatrolSpeed = 5.25,
			InvestigateSpeed = 12.6,
			SearchSpeed = 15.4,
			-- Player RUN is 26; 20.3 remains threatening but is now escapable on foot.
			ChaseSpeed = 20.3,
			VisionRange = 280,
			FieldOfViewDegrees = 280,
			ProximitySenseRange = 28,
			HearingWalkRange = 170,
			HearingSprintRange = 270,
			OccludedHearingMultiplier = 0.72,
			FlashlightVisibilityMultiplier = 1.20,
			AcquireSeconds = 0.08,
			SuspicionDecaySeconds = 0.25,
			AlertSeconds = 0.10,
			MemorySeconds = 32,
			SearchSeconds = 20,
		},
	},
	Hiding = {
		PromptHoldDuration = 0,
		PromptMaxDistance = 8,
		ServerDistanceSlack = 3,
		ActionCooldownSeconds = 0.25,
		HiddenRootHeight = 2.2,
		HideVolumeSize = Vector3.new(8.6, 2.5, 3.0),
		SightOccluderSize = Vector3.new(11.1, 3.35, 4.3),
		ExitOffsetZ = 5.8,
		ExitVerticalOffset = 1.0,
	},
	Colors = {
		AgedWhite = Color3.fromRGB(218, 211, 184),
		DustyPeach = Color3.fromRGB(176, 99, 74),
		MutedBlue = Color3.fromRGB(66, 83, 124),
		FadedGreen = Color3.fromRGB(91, 126, 83),
		Burgundy = Color3.fromRGB(92, 43, 49),
		DarkCarpet = Color3.fromRGB(18, 18, 22),
		Energon = Color3.fromRGB(66, 244, 218),
	},
	Rooms = {
		{Id="Arrival", Name="Receiving Vestibule", Kind="PartyHall", Decor="SparseWelcome", X=0, Z=0, W=70, D=52, H=12.5},
		{Id="StaffJunction", Name="Service Junction A", Kind="PartyHall", Decor="EmptyTransition", X=100, Z=0, W=56, D=36, H=11.5},
		{Id="BackOffice", Name="Vacant Leasing Office", Kind="City", Decor="KidsCafeteria", X=195, Z=0, W=78, D=48, H=12},
		{Id="BreakRoom", Name="Employee Break Room", Kind="City", Decor="ForgottenPair", X=100, Z=-105, W=60, D=50, H=10.5, Module=true},
		{Id="UtilityWest", Name="West Party Annex", Kind="PartyHall", Decor="DanceFloor", X=100, Z=105, W=80, D=70, H=16},
		{Id="PartySpine", Name="Party Service Gallery", Kind="PartyHall", Decor="SparseGallery", X=300, Z=0, W=98, D=40, H=13},
		{Id="Maintenance", Name="White Celebration Room", Kind="City", Decor="WhiteClassroom", X=195, Z=-105, W=68, D=64, H=11},
		{Id="LoadingStore", Name="Orange Banquet Annex", Kind="Party", Decor="BanquetRows", X=195, Z=105, W=88, D=74, H=15, Module=true},
		{Id="PartyA", Name="Party Room 03", Kind="Party", Decor="BirthdayCenter", X=300, Z=-105, W=108, D=78, H=16},
		{Id="ChairStore", Name="White City Hall", Kind="City", Decor="CityCafe", X=300, Z=105, W=76, D=60, H=12.5},
		{Id="CentralHall", Name="Parallel Party Gallery", Kind="PartyHall", Decor="SparseGallery", X=440, Z=0, W=76, D=44, H=12},
		{Id="CityPlay", Name="Little Streets Room", Kind="City", Decor="KidsCluster", X=440, Z=-105, W=112, D=84, H=15, Module=true},
		{Id="Janitor", Name="Orange Function Room", Kind="Party", Decor="AfterParty", X=440, Z=105, W=66, D=50, H=11.5},
		{Id="LostFound", Name="White Atrium", Kind="City", Decor="WhiteAtrium", X=570, Z=0, W=88, D=62, H=16},
		{Id="PartyB", Name="Abandoned Banquet Hall 07", Kind="Party", Decor="GrandBanquet", X=570, Z=-105, W=126, D=96, H=18, Module=true},
		{Id="Records", Name="Orange Celebration Room", Kind="Party", Decor="AbandonedCelebration", X=570, Z=105, W=84, D=70, H=14, Module=true},
		{Id="SignalHall", Name="East Party Passage", Kind="PartyHall", Decor="EmptyTransition", X=710, Z=0, W=78, D=40, H=11.5},
		{Id="Exit", Name="Freight Elevator Chamber", Kind="Exit", Decor="Exit", X=820, Z=0, W=58, D=52, H=14},
	},
	Links = {
		{A="Arrival", B="StaffJunction", Door="Open"},
		{A="StaffJunction", B="BackOffice", Door="Open"},
		{A="BackOffice", B="PartySpine", Door="Open"},
		{A="PartySpine", B="CentralHall", Door="Open"},
		{A="CentralHall", B="LostFound", Door="Open"},
		{A="LostFound", B="SignalHall", Door="Open"},
		{A="SignalHall", B="Exit", Door="HiddenExit"},
		{A="StaffJunction", B="BreakRoom", Door="Open"},
		{A="BreakRoom", B="Maintenance", Door="Open"},
		{A="Maintenance", B="PartyA", Door="Open"},
		{A="PartyA", B="CityPlay", Door="Open"},
		{A="CityPlay", B="PartyB", Door="Open"},
		{A="PartyB", B="LostFound", Door="Open"},
		{A="StaffJunction", B="UtilityWest", Door="Open"},
		{A="UtilityWest", B="LoadingStore", Door="Open"},
		{A="LoadingStore", B="ChairStore", Door="Open"},
		{A="ChairStore", B="Janitor", Door="Open"},
		{A="Janitor", B="Records", Door="Open"},
		{A="Records", B="LostFound", Door="Open"},
		{A="BackOffice", B="Maintenance", Door="Open"},
		{A="BackOffice", B="LoadingStore", Door="Open"},
		{A="PartySpine", B="PartyA", Door="Open"},
		{A="PartySpine", B="ChairStore", Door="Open"},
		{A="CentralHall", B="CityPlay", Door="Open"},
		{A="CentralHall", B="Janitor", Door="Open"},
	},
}

table.freeze(Configuration.Layout)
table.freeze(Configuration.TextureStuds)
table.freeze(Configuration.Textures)
table.freeze(Configuration.Audio)
table.freeze(Configuration.MusicSequence)
table.freeze(Configuration.MallManager.FootstepSoundNames)
table.freeze(Configuration.MallManager.FootstepAnimationTimes)
table.freeze(Configuration.MallManager.Normal)
table.freeze(Configuration.MallManager.Blackout)
table.freeze(Configuration.MallManager)
table.freeze(Configuration.Hiding)
table.freeze(Configuration.Colors)
for _, room in ipairs(Configuration.Rooms) do table.freeze(room) end
for _, link in ipairs(Configuration.Links) do table.freeze(link) end
table.freeze(Configuration.Rooms)
table.freeze(Configuration.Links)
table.freeze(Configuration)

return Configuration
