--!strict
-- Level 3 deterministic structural checks. Layout/configuration checks are safe
-- in Edit mode; ValidateWorld consumes a manifest built by the normal round flow.

local Configuration = require(script.Parent:WaitForChild("Level 3 Configuration"))
local LayoutGenerator = require(script.Parent:WaitForChild("Level 3 Layout Generator"))
local CollectionService = game:GetService("CollectionService")
local ReplicatedStorage = game:GetService("ReplicatedStorage")
local ServerScriptService = game:GetService("ServerScriptService")
local ServerStorage = game:GetService("ServerStorage")
local StarterPlayer = game:GetService("StarterPlayer")

local TestSuite = {}

local FORBIDDEN_NAME_FRAGMENTS = {"entity", "monster", "hostile", "npc", "chase"}
local SIGN_NAME_FRAGMENTS = {"level 3 sign", "room plaque", "birthday banner", "intro directory"}
local DISTRICT_THEME_IDS = {
	City = true,
	OrangeBlackParty = true,
	RedParty = true,
}
local GENERATOR_TEST_SEEDS = {1, 2, 17, 101, 7331, 65537, 424242, 1900813, 987654321}
local LEVEL_ONE_RUNTIME_SCRIPTS = {"EntityAI", "EntityAnimation", "EntityKill", "PuzzleManager"}

local function countMap(values: {[any]: any}): number
	local count = 0
	for _ in pairs(values) do count += 1 end
	return count
end

local function approx(a: number, b: number, tolerance: number?): boolean
	return math.abs(a - b) <= (tolerance or 0.001)
end

local function containsArtifactFragment(name: string, fragment: string): boolean
	local startIndex = string.find(name, fragment, 1, true)
	if not startIndex then return false end
	if fragment == "level 3 sign" then
		local nextCharacter = string.sub(name, startIndex + #fragment, startIndex + #fragment)
		return nextCharacter == "" or string.match(nextCharacter, "%a") == nil
	end
	return true
end

local function planarDistance(a: Vector3, b: Vector3): number
	return (Vector3.new(a.X, 0, a.Z) - Vector3.new(b.X, 0, b.Z)).Magnitude
end

local function assertPart(record: {[string]: any}, key: string, root: Instance): BasePart
	local object = record[key]
	assert(object and object:IsA("BasePart") and object:IsDescendantOf(root),
		"Level 3 manifest ExitPortal." .. key .. " is missing or outside the generated world")
	return object
end

function TestSuite.ValidateGeneratedLayouts(): {[string]: any}
	assert(Configuration.Layout.DistrictCount == 3
		and Configuration.Layout.RoomsPerDistrict >= 8
		and Configuration.Layout.HideTableCount == Configuration.Layout.DistrictCount
			* Configuration.Layout.RoomsPerDistrict,
		"Level 3 procedural district sizing or hide-table contract is invalid")
	local expectedRooms = Configuration.Layout.DistrictCount * Configuration.Layout.RoomsPerDistrict + 2
	local layoutHashes = {}
	local firstLayout = nil
	for _, requestedSeed in ipairs(GENERATOR_TEST_SEEDS) do
		local layout = LayoutGenerator.Generate(requestedSeed)
		local repeated = LayoutGenerator.Generate(requestedSeed)
		local valid, validationError = LayoutGenerator.Validate(layout)
		assert(valid, string.format("Level 3 seed %d failed validation: %s",
			requestedSeed, tostring(validationError)))
		assert(layout.LayoutHash == repeated.LayoutHash
			and layout.ResolvedSeed == repeated.ResolvedSeed
			and layout.Attempt == repeated.Attempt
			and layout.UsedFallbackSeed == repeated.UsedFallbackSeed,
			"Level 3 generation must be deterministic for seed " .. requestedSeed)
		assert(layout.RequestedSeed == requestedSeed
			and layout.Version == LayoutGenerator.Version,
			"Level 3 generator seed/version diagnostics are stale")
		assert(#layout.Rooms == expectedRooms
			and #layout.Districts == Configuration.Layout.DistrictCount
			and #layout.ModuleRooms == Configuration.ModuleGoal
			and #layout.Links - #layout.Rooms + 1 >= 3,
			"Level 3 generated count/loop contract failed for seed " .. requestedSeed)

		local hideSpots, modules, hiddenExits = 0, 0, 0
		local seenThemes = {}
		for _, room in ipairs(layout.Rooms) do
			hideSpots += tonumber(room.HideSpotCount) or 0
			if room.Module == true then modules += 1 end
		end
		for _, district in ipairs(layout.Districts) do
			assert(DISTRICT_THEME_IDS[district.ThemeId] == true
				and not seenThemes[district.ThemeId]
				and #district.RoomIds == Configuration.Layout.RoomsPerDistrict,
				"Level 3 generated district themes are missing, duplicated, or uneven")
			seenThemes[district.ThemeId] = true
		end
		for _, link in ipairs(layout.Links) do
			if link.Door == "HiddenExit" then hiddenExits += 1 end
		end
		assert(hideSpots == Configuration.Layout.HideTableCount
			and modules == Configuration.ModuleGoal
			and hiddenExits == 1
			and countMap(seenThemes) == Configuration.Layout.DistrictCount,
			"Level 3 generated objectives, hiding, or theme distribution is invalid")
		assert(layout.RoomById[layout.Roles.ArrivalRoomId] ~= nil
			and layout.RoomById[layout.Roles.ExitRoomId] ~= nil
			and layout.RoomById[layout.Roles.SignalRoomId] ~= nil
			and layout.RoomById[layout.Roles.MallManagerSpawnRoomId] ~= nil
			and layout.Roles.SignalRoomId == layout.Roles.MallManagerSpawnRoomId
			and layout.Roles.MallManagerSpawnRoomId ~= layout.Roles.ExitRoomId,
			"Level 3 generated role metadata is incomplete or unsafe")
		layoutHashes[layout.LayoutHash] = true
		if firstLayout == nil then firstLayout = layout end
	end
	assert(countMap(layoutHashes) >= 4,
		"Level 3 deterministic seed suite did not produce enough layout diversity")
	local summaryLayout = firstLayout :: any
	return {
		Seeds = #GENERATOR_TEST_SEEDS,
		UniqueLayouts = countMap(layoutHashes),
		Rooms = #summaryLayout.Rooms,
		Links = #summaryLayout.Links,
		Modules = #summaryLayout.ModuleRooms,
		Loops = #summaryLayout.Links - #summaryLayout.Rooms + 1,
		HiddenExitLinks = 1,
		GeneratorVersion = LayoutGenerator.Version,
	}
end

function TestSuite.ValidateConfiguration(): {[string]: any}
	assert(Configuration.Version >= 26, "Level 3 scream-lead and reduced-speed revision must be at least 26")
	local devAccess = require(ReplicatedStorage:WaitForChild("DevAccess"))
	assert(devAccess.IsLevel3TimelineOwner(9488575949)
		and not devAccess.IsLevel3TimelineOwner(40920547)
		and not devAccess.IsLevel3TimelineOwner(833029598),
		"Level 3 timeline skip must remain exclusive to LaverSneglen")
	assert(Configuration.Textures.KidsDrawingsAtlas == "rbxassetid://136455642832077"
		and Configuration.Textures.KidsDrawingsWholesome25 == "rbxassetid://128767366284181"
		and Configuration.Textures.KidsDrawingsDisturbing25 == "rbxassetid://132144680342985",
		"Level 3 must use the original 16 plus both approved 25-cell transparent drawing atlases")
	assert(Configuration.Textures.CDCoversAtlas == "rbxassetid://88160214591687",
		"Level 3 must use the authored CD-cover atlas")
	assert(Configuration.Version >= 43
		and Configuration.Textures.CRTScreenSurface == "rbxassetid://106602270400755",
		"Level 3 revision 43 must use the generated CRT phosphor screen")
	assert(Configuration.Version >= 45,
		"Level 3 revision 45 must use the doubled all-player finale hall")
	assert(Configuration.Layout.ExitCorridorLength == 560
		and Configuration.Layout.FinalHallHalfwayProgress == .50
		and Configuration.Layout.ExitCorridorSpeakerCount == 7
		and Configuration.Layout.ExitCorridorFixtureCount == 9
		and Configuration.MallManager.FinalHallSpawnProgress == .40
		and Configuration.MusicSequence.CompletionDimSeconds == 5.5,
		"Level 3 must preserve the authored 560-stud finale geometry and fade tuning")
	assert(Configuration.CorridorWidth == 14 and Configuration.CorridorHeight == 10.5,
		"Level 3 corridors must remain one 14 x 10.5 stud tunnel cross-section")
	assert(Configuration.ModuleGoal == 5, "Level 3 must require exactly five modules")
	assert(Configuration.MusicSequence.DurationSeconds == 180.035917
		and Configuration.MusicSequence.BlackoutStartSeconds == 150
		and Configuration.MusicSequence.PreBlackoutFlickerSeconds == 5
		and Configuration.MusicSequence.BlackoutScreamLeadSeconds == 3
		and Configuration.MusicSequence.BlackoutScreamLeadSeconds > 0
		and Configuration.MusicSequence.BlackoutScreamLeadSeconds
			< Configuration.MusicSequence.DurationSeconds - Configuration.MusicSequence.BlackoutStartSeconds
		and Configuration.MusicSequence.PostSongBlackoutSeconds == 30
		and approx(Configuration.MusicSequence.CycleEndSeconds,
			Configuration.MusicSequence.DurationSeconds + Configuration.MusicSequence.PostSongBlackoutSeconds)
		and approx(Configuration.MusicSequence.BlackoutSeconds,
			Configuration.MusicSequence.CycleEndSeconds - Configuration.MusicSequence.BlackoutStartSeconds)
		and Configuration.MusicSequence.RecoveryFlickerSeconds >= 3,
		"Level 3 must warn at 2:25, black out at 2:30, scream during the final three song seconds, then hunt for 30 seconds")
	assert(Configuration.MusicSequence.CorridorVolume < Configuration.MusicSequence.RoomVolume
		and approx(Configuration.MusicSequence.SpeakerVolume, .30, .000001)
		and approx(Configuration.MusicSequence.SpeakerMinDistance, 18, .000001)
		and approx(Configuration.MusicSequence.SpeakerMaxDistance, 180, .000001)
		and Configuration.MusicSequence.SpeakerMaxAudibleVoices == 2
		and approx(Configuration.MusicSequence.SpeakerSecondaryVolumeScale, .25, .000001),
		"Level 3 PA mix must cap synchronized speaker stacking at a restrained level")
	local managerTuning = Configuration.MallManager
	assert(type(managerTuning.SpawnRoomId) == "string"
		and managerTuning.SpawnRoomId ~= ""
		and managerTuning.SpawnRoomId ~= "Exit"
		and managerTuning.SpawnMinimumDistance == 90
		and managerTuning.SpawnPreferredDistance == 125
		and managerTuning.SpawnMaximumDistance == 180
		and managerTuning.SpawnGroupRadius >= 60,
		"Mall Manager must spawn 90-180 studs from the densest player group")
	assert(managerTuning.AgentRadius == 5
		and managerTuning.SweepRadius == 5.25
		and managerTuning.AgentRadius * 2 + 2 <= Configuration.CorridorWidth
		and managerTuning.SweepRadius * 2 + 1 <= Configuration.CorridorWidth
		and managerTuning.AgentHeight + .5 <= Configuration.CorridorHeight
		and managerTuning.WaypointReachDistance <= managerTuning.AgentRadius * .25
		and managerTuning.PathLookaheadWaypoints >= 3
		and managerTuning.BlackoutPathLookaheadWaypoints > managerTuning.PathLookaheadWaypoints
		and managerTuning.PathSampleHeight >= .25 and managerTuning.PathSampleHeight <= 1
		and managerTuning.CorridorCenteringLead >= managerTuning.SweepRadius
		and managerTuning.DirectPathRange <= 32
		and managerTuning.BlackoutDirectPathRange > managerTuning.DirectPathRange
		and managerTuning.MaxPathFailures == 3
		and managerTuning.ObstructionRecoveryAttempts == 3
		and managerTuning.ProgressResetDistance >= 8,

		"Mall Manager wall-clearance envelope does not safely fit the Level 3 corridors")
	assert(managerTuning.MovementAcceleration >= 40
		and managerTuning.MovementDeceleration > managerTuning.MovementAcceleration
		and managerTuning.MaximumMovementDeltaSeconds <= .05
		and managerTuning.TurnResponsiveness > 0
		and managerTuning.BlackoutTurnResponsiveness > managerTuning.TurnResponsiveness
		and managerTuning.ChaseVisualLossGraceSeconds >= .4
		and managerTuning.ChaseVisualLossGraceSeconds <= 1.5
		and managerTuning.MinimumAnimationSpeed <= managerTuning.Normal.PatrolSpeed / managerTuning.WalkReferenceSpeed
		and managerTuning.PathRecomputeSeconds > managerTuning.BlackoutPathRecomputeSeconds
		and managerTuning.BlackoutPathGoalMoveThreshold < managerTuning.PathGoalMoveThreshold
		and managerTuning.BlackoutMovementAcceleration > managerTuning.MovementAcceleration
		and managerTuning.BlackoutMovementDeceleration > managerTuning.MovementDeceleration
		and managerTuning.MotionSnapshotRate >= 20
		and managerTuning.MotionSnapshotRate <= 30
		and managerTuning.MotionInterpolationDelaySeconds >= .05
		and managerTuning.MotionInterpolationDelaySeconds <= .1
		and managerTuning.MotionBufferSamples >= 6
		and managerTuning.MotionBufferSamples <= 10
		and managerTuning.MotionLongGapSeconds >= .25
		and managerTuning.ContinuousAnimationPlaybackSpeed > 0
		and managerTuning.SpawnGraceSeconds == 0
		and managerTuning.PatrolPauseSeconds == 0,
		"Mall Manager smoothing, continuous locomotion, or background-repath tuning is invalid")
	assert(managerTuning.Blackout.VisionRange >= managerTuning.Normal.VisionRange * 2
		and managerTuning.Blackout.HearingWalkRange >= managerTuning.Normal.HearingWalkRange * 2,
		"Mall Manager blackout awareness must remain substantially increased")
	assert(approx(managerTuning.Blackout.PatrolSpeed, 5.25, .000001)
		and approx(managerTuning.Blackout.InvestigateSpeed, 12.6, .000001)
		and approx(managerTuning.Blackout.SearchSpeed, 15.4, .000001)
		and approx(managerTuning.PlayerRunSpeedReference, 26, .000001)
		and approx(managerTuning.ChaseSpeedMultiplier, 1.20, .000001)
		and approx(managerTuning.Blackout.ChaseSpeed,
			managerTuning.PlayerRunSpeedReference * managerTuning.ChaseSpeedMultiplier, .000001)
		and managerTuning.MaximumAnimationSpeed >= managerTuning.Blackout.ChaseSpeed / managerTuning.WalkReferenceSpeed,
		"Mall Manager blackout chase must remain exactly 20 percent faster than player RUN with matched animation")
	assert(managerTuning.Normal.PatrolSpeed == 4.5
		and managerTuning.Blackout.PatrolSpeed > managerTuning.Normal.PatrolSpeed,
		"Mall Manager blackout wandering must remain deliberate and slower than a chase")
	assert(managerTuning.Normal.PatrolSpeed < managerTuning.Normal.InvestigateSpeed
		and managerTuning.Normal.InvestigateSpeed < managerTuning.Normal.SearchSpeed
		and managerTuning.Normal.SearchSpeed < managerTuning.Normal.ChaseSpeed
		and managerTuning.Blackout.PatrolSpeed < managerTuning.Blackout.InvestigateSpeed
		and managerTuning.Blackout.InvestigateSpeed < managerTuning.Blackout.SearchSpeed
		and managerTuning.Blackout.SearchSpeed < managerTuning.Blackout.ChaseSpeed,
		"Mall Manager locomotion states must escalate from slow walk to chase")
	local expectedFootsteps = {
		{Name = "Mall Manager Walk Sound 1", Id = "rbxassetid://86969848436282", Time = 0.8},
		{Name = "Mall Manager Walk Sound 2", Id = "rbxassetid://125163405380423", Time = 1.2},
		{Name = "Mall Manager Walk Sound 3", Id = "rbxassetid://131363472955449", Time = 2.266667},
		{Name = "Mall Manager Walk Sound 4", Id = "rbxassetid://128260682244977", Time = 2.666667},
	}
	assert(#managerTuning.FootstepSoundNames == 4 and #managerTuning.FootstepAnimationTimes == 4,
		"Mall Manager must own exactly four walk sounds and four touchdown phases")
	for index, expected in ipairs(expectedFootsteps) do
		assert(managerTuning.FootstepSoundNames[index] == expected.Name
			and Configuration.Audio[expected.Name] == expected.Id
			and approx(managerTuning.FootstepAnimationTimes[index], expected.Time, .0001),
			"Mall Manager footstep name, ID, or touchdown phase is stale at index " .. index)
		if index > 1 then
			assert(managerTuning.FootstepAnimationTimes[index] > managerTuning.FootstepAnimationTimes[index - 1],
				"Mall Manager touchdown phases must be strictly increasing")
		end
	end
	assert(managerTuning.FootstepAnimationTimes[4] < 2.9
		and approx(managerTuning.FootstepVolume, 2.0, .000001)
		and approx(managerTuning.FootstepRollOffMinDistance, 20, .000001)
		and approx(managerTuning.FootstepRollOffMaxDistance, 90, .000001)
		and managerTuning.FootstepRollOffMaxDistance > managerTuning.FootstepRollOffMinDistance,
		"Mall Manager footstep spatial-audio tuning is invalid")
	assert(Configuration.Audio.MallManagerBlackout == "rbxassetid://125407251695204"
		and managerTuning.BlackoutScreamSoundName == "Mall Manager Walk Blackout Scream"
		and approx(managerTuning.BlackoutScreamDurationSeconds, 8.071836735, .000001)
		and approx(managerTuning.BlackoutScreamVolume, .90, .000001)
		and approx(managerTuning.BlackoutScreamRollOffMinDistance, 22, .000001)
		and approx(managerTuning.BlackoutScreamRollOffMaxDistance, 210, .000001)
		and managerTuning.BlackoutScreamMaxLocalVoices == 1
		and managerTuning.BlackoutScreamSourceMinimumDistance == 75
		and managerTuning.BlackoutScreamSourcePreferredDistance == 115
		and managerTuning.BlackoutScreamSourceMaximumDistance == 175
		and managerTuning.BlackoutScreamMinimumStructuralOccluders == 2
		and managerTuning.BlackoutScreamLowGain == 0
		and managerTuning.BlackoutScreamMidGain == -9
		and managerTuning.BlackoutScreamHighGain == -24,
		"Mall Manager blackout scream must be one distant, structurally muffled corridor voice")
	assert(Configuration.Audio.MallManagerBalloonScream == "rbxassetid://105088070261380"
		and managerTuning.ChaseScreamSoundName == "Mall Manager Chase Scream 1"
		and approx(managerTuning.ChaseScreamDurationSeconds, 22.569795918, .000001)
		and managerTuning.ChaseScreamCooldownSeconds >= managerTuning.ChaseScreamDurationSeconds
		and managerTuning.ChaseScreamRollOffMaxDistance > managerTuning.ChaseScreamRollOffMinDistance,
		"Mall Manager chase scream tuning is stale or permits overlapping restarts")
	assert(Configuration.Textures.PartyCarpetNeon == "rbxassetid://110230144446272"
		and Configuration.Textures.PartyCarpetRed == "rbxassetid://108064770913201"
		and Configuration.Textures.OrangeWall == "rbxassetid://128270554927663",
		"Level 3 Revision 4 generated texture IDs are missing or stale")
	local assets = ServerStorage:FindFirstChild("Level3Assets")
	local furniture = assets and assets:FindFirstChild("FurnitureTemplates")
	assert(furniture and furniture:IsA("Folder"), "Level 3 vetted furniture templates are missing")
	local entityTemplates = assets and assets:FindFirstChild("EntityTemplates")
	local managerTemplate = entityTemplates and entityTemplates:FindFirstChild(managerTuning.TemplateName)
	assert(managerTemplate and managerTemplate:IsA("Model")
		and managerTemplate.PrimaryPart and managerTemplate.PrimaryPart.Name == "HumanoidRootPart"
		and managerTemplate:GetAttribute("RuntimeReady") == true
		and (tonumber(managerTemplate:GetAttribute("RuntimeRevision")) or 0) >= 24,
		"Mall Manager runtime-ready custom rig template is missing or stale")
	local visualSmoother = StarterPlayer.StarterPlayerScripts:FindFirstChild("Level 3 Mall Manager Visual Smoother")
	assert(visualSmoother and visualSmoother:IsA("LocalScript") and visualSmoother.Enabled,
		"Mall Manager client visual smoother is missing or disabled")
	local level3Remotes = ReplicatedStorage:FindFirstChild(Configuration.RemotesFolderName)
	local motionRemote = level3Remotes and level3Remotes:FindFirstChild(Configuration.MallManagerMotionEventName)
	assert(motionRemote and motionRemote:IsA("UnreliableRemoteEvent"),
		"Mall Manager buffered-motion remote is missing or has the wrong class")
	local hideRemote = level3Remotes and level3Remotes:FindFirstChild(Configuration.HideRequestEventName)
	local hideClient = StarterPlayer.StarterPlayerScripts:FindFirstChild("Level 3 Table Hiding Client")
	local hideController = ServerScriptService:FindFirstChild("Level 3 Systems")
		and ServerScriptService["Level 3 Systems"]:FindFirstChild("Level 3 Hiding Controller")
	assert(hideRemote and hideRemote:IsA("RemoteEvent")
		and hideClient and hideClient:IsA("LocalScript") and hideClient.Enabled
		and hideController and hideController:IsA("ModuleScript"),
		"Level 3 cross-device hiding controllers or remote are missing")
	assert(Configuration.Hiding.PromptHoldDuration == 0
		and Configuration.Hiding.PromptMaxDistance >= 7
		and Configuration.Hiding.HiddenRootHeight > 0
		and Configuration.Hiding.SightOccluderSize.Y >= 3,
		"Level 3 table-hiding interaction tuning is unsafe")
	assert(managerTemplate:FindFirstChildOfClass("AnimationController")
		and managerTemplate:FindFirstChildOfClass("AnimationController"):FindFirstChildOfClass("Animator"),
		"Mall Manager template is missing AnimationController.Animator")
	for _, object in ipairs(managerTemplate:GetDescendants()) do
		assert(not object:IsA("Humanoid") and not object:IsA("BaseScript"),
			"Mall Manager template must remain a scriptless custom bone rig")
	end
	local entityAnimations = assets and assets:FindFirstChild("EntityAnimations")
	local managerAnimations = entityAnimations and entityAnimations:FindFirstChild("MallManager")
	local walk = managerAnimations and managerAnimations:FindFirstChild("Walk")
	assert(walk and walk:IsA("Animation") and walk.AnimationId == "rbxassetid://123012476898232",
		"Mall Manager published walk reference is missing or stale")
	local entitySounds = assets and assets:FindFirstChild("EntitySounds")
	local managerSounds = entitySounds and entitySounds:FindFirstChild("MallManager")
	assert(managerSounds and managerSounds:IsA("Folder") and #managerSounds:GetChildren() == 4,
		"Mall Manager saved footstep prototypes are missing or duplicated")
	for index, expected in ipairs(expectedFootsteps) do
		local sound = managerSounds:FindFirstChild(expected.Name)
		assert(sound and sound:IsA("Sound") and sound.SoundId == expected.Id
			and sound.Looped == false and sound.PlayOnRemove == false
			and approx(sound.PlaybackSpeed, 1) and approx(sound.Volume, managerTuning.FootstepVolume)
			and sound.RollOffMode == Enum.RollOffMode.InverseTapered
			and approx(sound.RollOffMinDistance, managerTuning.FootstepRollOffMinDistance)
			and approx(sound.RollOffMaxDistance, managerTuning.FootstepRollOffMaxDistance)
			and sound:GetAttribute("FootstepIndex") == index
			and approx(tonumber(sound:GetAttribute("AnimationTime")) or -1, expected.Time, .0001),
			"Saved Mall Manager footstep prototype is stale: " .. expected.Name)
	end
	local screamFolder = entitySounds and entitySounds:FindFirstChild("MallManagerScreams")
	assert(screamFolder and screamFolder:IsA("Folder") and #screamFolder:GetChildren() == 2,
		"Mall Manager saved scream prototypes are missing or duplicated")
	local expectedScreams = {
		{Name=managerTuning.BlackoutScreamSoundName, Id=Configuration.Audio.MallManagerBlackout,
			Volume=managerTuning.BlackoutScreamVolume, Min=managerTuning.BlackoutScreamRollOffMinDistance,
			Max=managerTuning.BlackoutScreamRollOffMaxDistance, Duration=managerTuning.BlackoutScreamDurationSeconds,
			Muffled=true},
		{Name=managerTuning.ChaseScreamSoundName, Id=Configuration.Audio.MallManagerBalloonScream,
			Volume=managerTuning.ChaseScreamVolume, Min=managerTuning.ChaseScreamRollOffMinDistance,
			Max=managerTuning.ChaseScreamRollOffMaxDistance, Duration=managerTuning.ChaseScreamDurationSeconds},
	}
	for _, expected in ipairs(expectedScreams) do
		local sound = screamFolder:FindFirstChild(expected.Name)
		assert(sound and sound:IsA("Sound") and sound.SoundId == expected.Id
			and sound.Looped == false and sound.PlayOnRemove == false
			and approx(sound.PlaybackSpeed, 1) and approx(sound.Volume, expected.Volume)
			and sound.RollOffMode == Enum.RollOffMode.InverseTapered
			and approx(sound.RollOffMinDistance, expected.Min)
			and approx(sound.RollOffMaxDistance, expected.Max)
			and sound:GetAttribute("Level3_MallManagerScreamPrototype") == true
			and approx(tonumber(sound:GetAttribute("DurationSeconds")) or -1, expected.Duration, .000001),
			"Saved Mall Manager scream prototype is stale: " .. expected.Name)
		if expected.Muffled then
			local equalizer = sound:FindFirstChildOfClass("EqualizerSoundEffect")
			local reverb = sound:FindFirstChildOfClass("ReverbSoundEffect")
			assert(equalizer and equalizer.LowGain == managerTuning.BlackoutScreamLowGain
				and equalizer.MidGain == managerTuning.BlackoutScreamMidGain
				and equalizer.HighGain == managerTuning.BlackoutScreamHighGain
				and reverb and approx(reverb.Density, managerTuning.BlackoutScreamReverbDensity)
				and approx(reverb.Diffusion, managerTuning.BlackoutScreamReverbDiffusion)
				and approx(reverb.DecayTime, managerTuning.BlackoutScreamReverbDecayTime)
				and approx(reverb.DryLevel, managerTuning.BlackoutScreamReverbDryLevel)
				and approx(reverb.WetLevel, managerTuning.BlackoutScreamReverbWetLevel),
				"Saved blackout scream is missing its distant wall-muffle effects")
		end
	end
	for _, templateName in ipairs({"PlasticPartyChairTemplate", "FoldingTableTemplate"}) do
		local template = furniture:FindFirstChild(templateName)
		assert(template and template:IsA("MeshPart") and template:GetAttribute("Level3_VettedTemplate") == true,
			"Missing vetted Level 3 furniture template: " .. templateName)
		for _, object in ipairs(template:GetDescendants()) do
			assert(not object:IsA("BaseScript"), "Vetted Level 3 furniture contains a script: " .. object:GetFullName())
		end
	end

	return TestSuite.ValidateGeneratedLayouts()
end

function TestSuite.ValidateWorld(manifest: {[string]: any}): {[string]: any}
	assert(type(manifest) == "table" and manifest.World and manifest.World:IsA("Model")
		and manifest.World.Parent == workspace, "Level 3 manifest must point at its live world")
	local world = manifest.World :: Model
	local layout = manifest.Layout
	assert(type(layout) == "table", "Level 3 manifest is missing its generated layout")
	local layoutValid, layoutError = LayoutGenerator.Validate(layout)
	assert(layoutValid, "Level 3 manifest layout is invalid: " .. tostring(layoutError))
	assert(world.Name == Configuration.WorldName, "Level 3 world has the wrong generation name")
	local liveWorlds = 0
	for _, child in ipairs(workspace:GetChildren()) do
		if child.Name == Configuration.WorldName then liveWorlds += 1 end
	end
	assert(liveWorlds == 1, "Level 3 rebuild left duplicate generated worlds")
	assert(world:GetAttribute("Level3_Generation") == manifest.Generation,
		"Level 3 world/manifest generations do not match")
	assert(world:GetAttribute("Level3_VisualRevision") == Configuration.Version,
		"Level 3 world is missing the current visual revision stamp")
	local expectedHideTables = 0
	for _, room in ipairs(layout.Rooms) do
		expectedHideTables += tonumber(room.HideSpotCount) or 0
	end
	assert(world:GetAttribute("Level3_LayoutHash") == layout.LayoutHash
		and world:GetAttribute("Level3_ResolvedSeed") == layout.ResolvedSeed
		and world:GetAttribute("Level3_GeneratorVersion")
			== (layout.Version or Configuration.Layout.GeneratorVersion),
		"Level 3 world is missing procedural seed/hash diagnostics")
	assert(world:GetAttribute("Level3_RoomCount") == #layout.Rooms
		and world:GetAttribute("Level3_CorridorCount") == #layout.Links
		and world:GetAttribute("Level3_DistrictCount") == #layout.Districts,
		"Level 3 world procedural count attributes are stale")
	assert(countMap(manifest.Rooms) == #layout.Rooms, "Level 3 built room count mismatch")
	assert(#manifest.Modules == #layout.ModuleRooms
		and #manifest.Modules == Configuration.ModuleGoal,
		"Level 3 built module count mismatch")
	assert(type(manifest.Corridors) == "table" and #manifest.Corridors == #layout.Links,
		"Level 3 built corridor manifest count mismatch")
	assert(type(manifest.HideTables) == "table" and #manifest.HideTables == expectedHideTables
		and world:GetAttribute("Level3_HideTableCount") == expectedHideTables,
		"Level 3 must build the generated layout's complete hiding-place set")
	local hideIndices = {}
	for index, anchor in ipairs(manifest.HideTables) do
		local prompt = anchor:FindFirstChild("HideUnderTablePrompt")
		assert(anchor:IsA("BasePart") and anchor:IsDescendantOf(world)
			and anchor:GetAttribute("Level3_HideTableAnchor") == true
			and anchor:GetAttribute("Level3_HideTableIndex") == index
			and not hideIndices[index]
			and prompt and prompt:IsA("ProximityPrompt")
			and prompt.ActionText == "HIDE UNDER TABLE"
			and prompt.KeyboardKeyCode == Enum.KeyCode.E
			and prompt.GamepadKeyCode == Enum.KeyCode.ButtonX
			and prompt.HoldDuration == Configuration.Hiding.PromptHoldDuration
			and prompt.MaxActivationDistance == Configuration.Hiding.PromptMaxDistance,
			"Level 3 hide table anchor/prompt is stale at index " .. index)
		hideIndices[index] = true
	end
	local sightOccluders = 0
	for _, object in ipairs(world:GetDescendants()) do
		if object:IsA("BasePart") and object:GetAttribute("Level3_HideSightOccluder") == true then
			sightOccluders += 1
			assert(not object.CanCollide and not object.CanTouch and object.CanQuery and object.Transparency == 1,
				"Level 3 hide sight occluder must be invisible, query-only, and nonblocking")
		end
	end
	assert(sightOccluders == #manifest.HideTables,
		"Level 3 must build one sight occluder per generated hiding table")
	assert(type(manifest.BlackoutScreamOpenings) == "table"
		and #manifest.BlackoutScreamOpenings == #layout.Links * 2
		and world:GetAttribute("Level3_BlackoutScreamOpeningCount") == #layout.Links * 2,
		"Level 3 must own exactly two blackout scream markers per generated corridor")
	local openingKeys = {}
	for index, corridor in ipairs(manifest.Corridors) do
		assert(type(corridor.ScreamOpenings) == "table" and #corridor.ScreamOpenings == 2,
			"Level 3 corridor is missing its two scream openings at index " .. index)
		for openingIndex, opening in ipairs(corridor.ScreamOpenings) do
			local side = if openingIndex == 1 then "A" else "B"
			local expectedPoint = (if side == "A" then corridor.StartPoint else corridor.EndPoint)
				+ Vector3.new(0, 4.2, 0)
			local key = string.format("%02d%s", index, side)
			assert(opening:IsA("Attachment") and opening:IsDescendantOf(corridor.Model)
				and opening:GetAttribute("Level3_CorridorOpeningScreamEmitter") == true
				and opening:GetAttribute("Level3_CorridorOpeningKey") == key
				and (opening.WorldPosition - expectedPoint).Magnitude <= .02
				and not openingKeys[key],
				"Level 3 corridor scream opening is missing, duplicated, or misplaced: " .. key)
			openingKeys[key] = true
		end
	end
	assert(manifest.ExitGateway == nil, "Legacy ExitGateway must not survive the hidden-exit rebuild")
	assert(type(manifest.ExitPortal) == "table", "Level 3 manifest is missing ExitPortal")
	assert(manifest.EscapePrompt and manifest.EscapePrompt:IsA("ProximityPrompt")
		and manifest.EscapePrompt:IsDescendantOf(world), "Level 3 escape prompt is incomplete")
	assert(manifest.ExitSafeSpawn and manifest.ExitSafeSpawn:IsA("BasePart")
		and manifest.ExitSafeSpawn:IsDescendantOf(world), "Level 3 exit safe spawn is incomplete")
	assert(typeof(manifest.ExitPosition) == "Vector3", "Level 3 ExitPosition must be a Vector3")
	assert(manifest.MallManagerSpawn and manifest.MallManagerSpawn:IsA("BasePart")
		and manifest.MallManagerSpawn:IsDescendantOf(world)
		and manifest.MallManagerSpawn:GetAttribute("Level3_MallManagerSpawn") == true
		and manifest.MallManagerSpawn:GetAttribute("Level3_SpawnRoomId")
			== layout.Roles.MallManagerSpawnRoomId,
		"Level 3 Mall Manager spawn marker is missing or invalid")
	assert(manifest.MallManagerRuntime and manifest.MallManagerRuntime:IsA("Folder")
		and manifest.MallManagerRuntime:IsDescendantOf(world),
		"Level 3 Mall Manager runtime folder is missing")
	assert(not manifest.MallManagerSpawn.CanCollide and not manifest.MallManagerSpawn.CanTouch
		and not manifest.MallManagerSpawn.CanQuery and manifest.MallManagerSpawn.Transparency == 1,
		"Mall Manager spawn marker must remain invisible and noninteractive")
	assert(planarDistance(manifest.MallManagerSpawn.Position, manifest.ElevatorSpawn.Position)
		>= Configuration.MallManager.SpawnMinimumDistance,
		"Mall Manager spawn marker is too close to player arrival")
	assert(manifest.Elevator and manifest.ElevatorSpawn and manifest.MazeStart,
		"Level 3 compatibility arrival is incomplete")
	for _, marker in ipairs({manifest.Elevator, manifest.ElevatorSpawn, manifest.MazeStart}) do
		assert(marker.Parent == workspace and marker:GetAttribute("Level3_CompatibilityMarker") == true,
			"Level 3 compatibility arrival marker is invalid")
	end
	for _, markerName in ipairs({"Elevator", "ElevatorSpawn", "MazeStart"}) do
		local markerCount = 0
		for _, child in ipairs(workspace:GetChildren()) do
			if child.Name == markerName and child:GetAttribute("Level3_CompatibilityMarker") == true then
				markerCount += 1
			end
		end
		assert(markerCount == 1, "Level 3 rebuild left duplicate " .. markerName .. " markers")
	end
	local slide = world:FindFirstChild("Level 2 Exit Slide Continuation")
	local arrivalPlan = layout.RoomById[layout.Roles.ArrivalRoomId]
	local expectedMouth = Configuration.WorldOrigin + Vector3.new(
		arrivalPlan.X - arrivalPlan.W * .5 + Configuration.WallThickness * .5 + .12,
		8.05, arrivalPlan.Z)
	local slideMouth = slide and slide:GetAttribute("Level3_SlideMouthPosition")
	assert(slide and slide:IsA("Model")
		and slide:GetAttribute("Level3_Level2ExitTube") == true
		and slide:GetAttribute("Level3_DirectMallArrival") == true
		and typeof(slideMouth) == "Vector3"
		and ((slideMouth :: Vector3) - expectedMouth).Magnitude <= .02,
		"Level 2 slide mouth must terminate directly at the Level 3 mall arrival wall")
	local transitionSeals = 0
	for _, object in ipairs(slide:GetDescendants()) do
		if object:IsA("BasePart") and object:GetAttribute("Level3_TransitionWallSeal") == true then
			transitionSeals += 1
			assert(object.Material == Enum.Material.Plaster
				and object.Color == Color3.fromRGB(183, 78, 35),
				"Slide mouth seal must continue the Level 3 orange plaster wall")
		end
	end
	assert(transitionSeals > 0, "Level 3 slide mouth is missing its mall-finished wall seal")
	assert(workspace:FindFirstChild("EntityStart") == nil,
		"Level 3 must never create the restricted EntityStart marker")

	local portal = manifest.ExitPortal
	assert(portal.Model and portal.Model:IsA("Model") and portal.Model:IsDescendantOf(world),
		"Level 3 ExitPortal model is missing")
	local hiddenWall = assertPart(portal, "Wall", world)
	local hiddenExitLink = nil
	for _, link in ipairs(layout.Links) do
		if link.Door == "HiddenExit" then
			hiddenExitLink = link
			break
		end
	end
	assert(hiddenExitLink and DISTRICT_THEME_IDS[hiddenExitLink.ThemeId] == true,
		"Generated Level 3 layout is missing a themed HiddenExit link")
	local hiddenExitCorridor = nil
	for _, corridor in ipairs(manifest.Corridors) do
		if corridor.DoorType == "HiddenExit" then
			hiddenExitCorridor = corridor
			break
		end
	end
	assert(hiddenExitCorridor and hiddenExitCorridor.Model:IsA("Model")
		and math.abs(hiddenExitCorridor.Length - Configuration.Layout.ExitCorridorLength) <= .1
		and hiddenExitCorridor.Model:GetAttribute("Level3_ExitCorridor") == true,
		"Hidden exit must be the exact authored 560-stud PA corridor")
	local finalHall = manifest.FinalHall
	assert(type(finalHall) == "table" and finalHall.Corridor == hiddenExitCorridor
		and finalHall.Model == hiddenExitCorridor.Model
		and finalHall.HalfwayMarker:GetAttribute("Level3_FinalHallHalfway") == true
		and finalHall.SpawnMarker:GetAttribute("Level3_MallManagerFinaleSpawn") == true
		and (finalHall.HalfwayMarker.Position
			- finalHall.StartPoint:Lerp(finalHall.EndPoint, .50)).Magnitude <= .11
		and (finalHall.SpawnMarker.Position
			- finalHall.StartPoint:Lerp(finalHall.EndPoint, .40)).Magnitude <= .11
		and finalHall.HalfwayMarker.Transparency == 1
		and not finalHall.HalfwayMarker.CanCollide and not finalHall.HalfwayMarker.CanTouch
		and not finalHall.HalfwayMarker.CanQuery
		and finalHall.SpawnMarker.Transparency == 1
		and not finalHall.SpawnMarker.CanCollide and not finalHall.SpawnMarker.CanTouch
		and not finalHall.SpawnMarker.CanQuery,
		"Final hall markers or normalized geometry are invalid")
	local exitPASounds = 0
	for _, object in ipairs(hiddenExitCorridor.Model:GetDescendants()) do
		if object:IsA("Sound") and object.Name == "Level 3 Room Song Speaker"
			and object:GetAttribute("Level3_ExitCorridorPA") == true then
			exitPASounds += 1
			assert(object:FindFirstChildOfClass("EqualizerSoundEffect"),
				"Exit corridor PA speaker is missing its distance muffle")
		end
	end
	assert(exitPASounds == Configuration.Layout.ExitCorridorSpeakerCount,
		"Hidden exit corridor has the wrong PA speaker count")
	local expectedHiddenWallColor = if hiddenExitLink.ThemeId == "City"
		then Color3.fromRGB(220, 213, 187)
		elseif hiddenExitLink.ThemeId == "RedParty" then Color3.fromRGB(145, 58, 48)
		else Color3.fromRGB(183, 78, 35)
	assert(hiddenWall:GetAttribute("Level3_HiddenExitWall") == true,
		"ExitPortal wall is missing Level3_HiddenExitWall")
	assert(hiddenWall.Transparency == 0 and hiddenWall.CanCollide and hiddenWall.CanQuery
		and not hiddenWall.CanTouch,
		"Hidden exit wall must begin opaque, locked, queryable, and non-touching")
	assert(hiddenWall.Material == Enum.Material.Plaster
		and hiddenWall.Color == expectedHiddenWallColor
		and hiddenWall.Size == Vector3.new(Configuration.CorridorWidth,
			Configuration.CorridorHeight, Configuration.WallThickness),
		"Hidden exit wall must seal the complete standardized tunnel portal")
	assert(typeof(portal.Position) == "Vector3" and (portal.Position - hiddenWall.Position).Magnitude <= Configuration.RoomHeight,
		"ExitPortal position is invalid or detached from the wall")
	assert(type(portal.FrameParts) == "table" and #portal.FrameParts == 8,
		"ExitPortal must have exactly 8 reveal-frame parts (four edges on both faces)")
	local uniqueFrameParts = {}
	for index, framePart in ipairs(portal.FrameParts) do
		assert(framePart:IsA("BasePart") and framePart:IsDescendantOf(portal.Model),
			"ExitPortal frame part is missing at index " .. index)
		assert(not uniqueFrameParts[framePart], "ExitPortal repeats a frame part at index " .. index)
		uniqueFrameParts[framePart] = true
		assert(framePart:GetAttribute("Level3_HiddenExitFrame") == true,
			"ExitPortal frame part is missing its marker attribute")
		assert(framePart.Material == Enum.Material.Neon and framePart.Transparency == 1
			and not framePart.CanCollide and not framePart.CanQuery,
			"ExitPortal reveal frame must start invisible and nonblocking")
	end
	assert(portal.Light and portal.Light:IsA("Light") and portal.Light:IsDescendantOf(portal.Model)
		and not portal.Light.Enabled, "ExitPortal light must exist and start disabled")
	assert(portal.Model:GetAttribute("Level3_ExitUnlocked") == false,
		"ExitPortal must begin locked")
	local authoredDiscPlayer = portal.DiscPlayer
	assert(type(authoredDiscPlayer) == "table" and authoredDiscPlayer.Model:IsA("Model")
		and authoredDiscPlayer.Model:GetAttribute("Level3_DiscPlayerVisualRevision") == 2,
		"Signal Hall disc player must use the CRT/VCR cart revision")
	local crtScreen = authoredDiscPlayer.Model:FindFirstChild("CRT Phosphor Screen", true)
	local crtStatic = authoredDiscPlayer.Model:FindFirstChild("CRT Generated Static", true)
	assert(crtScreen and crtScreen:IsA("BasePart") and crtScreen:GetAttribute("Level3_CRTScreen") == true
		and crtStatic and crtStatic:IsA("ImageLabel")
		and crtStatic.Image == Configuration.Textures.CRTScreenSurface,
		"CRT/VCR cart is missing its generated phosphor screen")

	local stats = {
		BaseParts = 0,
		Collidable = 0,
		Lights = 0,
		ShadowLights = 0,
		Prompts = 0,
		Textures = 0,
		OrangeRooms = 0,
		BeigeRooms = 0,
		RoomFloors = 0,
		ArrivalMallFloors = 0,
		PartyFloors = 0,
		RedPartyFloors = 0,
		NeonPartyFloors = 0,
		OrangeWallTextures = 0,
		CityFloors = 0,
		ExitFloors = 0,
		CorridorFloors = 0,
	}

	assert(type(manifest.Doors) == "table" and #manifest.Doors == 0,
		"Revision 3 must not generate ordinary or fake doors")

	for _, module in ipairs(manifest.Modules) do
		assert(module.Model.Parent and module.Prompt.Enabled and module.Prompt.Parent,
			"Level 3 CD record is incomplete")
		assert(module.Prompt.ActionText == "COLLECT CD"
			and string.find(module.Prompt.ObjectText, "PARTY MIX CD", 1, true),
			"Level 3 objective must be presented as a birthday music CD")
		assert(module.Model:FindFirstChild("Transparent Jewel Case", true)
			and module.Model:FindFirstChild("Party Mix Compact Disc", true)
			and module.Model:FindFirstChild("Level 3 CD Cover Surface", true),
			"Level 3 CD collectible is missing its authored jewel-case visuals")
		assert(type(module.PickupParts) == "table" and #module.PickupParts == 2,
			"Level 3 CD must identify exactly two removable pickup parts")
		for _, pickupPart in ipairs(module.PickupParts) do
			assert(pickupPart:IsA("BasePart") and pickupPart:IsDescendantOf(module.Model)
				and pickupPart:GetAttribute("Level3_CDPickupVisual") == true,
				"Level 3 CD pickup-part manifest is stale")
		end
	end

	for _, instance in ipairs(world:GetDescendants()) do
		if instance:IsA("BasePart") then
			stats.BaseParts += 1
			if instance.CanCollide then stats.Collidable += 1 end
			if instance:GetAttribute("Level3_ManagerFurnitureNavExclusion") == true then
				local modifier = instance:FindFirstChildOfClass("PathfindingModifier")
				assert(instance.Anchored and not instance.CanCollide and instance.CanQuery
					and modifier and modifier.Label == Configuration.MallManager.FurniturePathLabel
					and modifier.PassThrough == false,
					"Manager furniture exclusion must remain queryable and carry its blocking path label")
			end
		elseif instance:IsA("Light") then
			stats.Lights += 1
			if instance.Shadows then stats.ShadowLights += 1 end
			if instance.Name == "Level 3 Fluorescent Light" then
				assert(instance.Brightness <= 1.65 and instance.Range <= 34,
					"Level 3 fluorescent fixture exceeds the readable-atmosphere target")
			end
		elseif instance:IsA("ProximityPrompt") then
			stats.Prompts += 1
		elseif instance:IsA("Texture") or instance:IsA("Decal") then
			stats.Textures += 1
		end
		if instance:IsA("SurfaceGui") then
			local allowedDrawing = instance.Name == "Level 3 Kids Wall Art Surface"
				and instance.Parent and instance.Parent:GetAttribute("Level3_KidsWallArt") == true
			local allowedCD = instance.Name == "Level 3 CD Cover Surface"
				and instance.Parent and instance.Parent.Name == "CD Cover Insert"
			local allowedCRT = instance.Name == "CRT Status Screen Surface"
				and instance.Parent and instance.Parent:GetAttribute("Level3_CRTScreen") == true
				and instance:IsDescendantOf(manifest.DiscPlayer.Model)
			assert(allowedDrawing or allowedCD or allowedCRT,
				"Generated Level 3 SurfaceGui/sign is forbidden: " .. instance:GetFullName())
		end
		local allowedDiscPlayerText = instance:IsA("TextLabel")
			and instance:IsDescendantOf(manifest.DiscPlayer.Model)
		assert(allowedDiscPlayerText
			or (not instance:IsA("TextLabel") and not instance:IsA("TextBox") and not instance:IsA("TextButton")),
			"Generated Level 3 text UI is forbidden: " .. instance:GetFullName())
		assert(not instance:IsA("Humanoid"),
			"Level 3 generated content may not embed Humanoid-driven rigs")
		assert(not instance:IsA("BaseScript"), "Level 3 world may not contain per-instance scripts")
		local lowerName = string.lower(instance.Name)
		local allowedNamedChaseVocal = instance:IsA("Sound")
			and instance:GetAttribute("Level3_MallManagerChaseScream") == true
			and instance:IsDescendantOf(manifest.MallManagerRuntime)
		for _, fragment in ipairs(FORBIDDEN_NAME_FRAGMENTS) do
			local allowed = fragment == "chase" and allowedNamedChaseVocal
			assert(allowed or not string.find(lowerName, fragment, 1, true),
				"Forbidden Level 3 runtime name: " .. instance:GetFullName())
		end
		for _, fragment in ipairs(SIGN_NAME_FRAGMENTS) do
			assert(not containsArtifactFragment(lowerName, fragment),
				"Obsolete Level 3 sign artifact: " .. instance:GetFullName())
		end
	end

	local expectedRoomThemes = {City=0, OrangeBlackParty=0, RedParty=0}
	local expectedFloorThemes = {City=0, OrangeBlackParty=0, RedParty=0}
	for _, room in ipairs(layout.Rooms) do
		if expectedRoomThemes[room.ThemeId] ~= nil then
			expectedRoomThemes[room.ThemeId] += 1
			if room.Id ~= layout.Roles.ExitRoomId
				and room.Id ~= layout.Roles.ArrivalRoomId then
				expectedFloorThemes[room.ThemeId] += 1
			end
		end
	end
	local observedRoomThemes = {City=0, OrangeBlackParty=0, RedParty=0}
	for _, room in ipairs(layout.Rooms) do
		local roomModel = manifest.Rooms[room.Id]
		assert(roomModel and roomModel:IsA("Model"), "Level 3 room is missing: " .. room.Id)
		assert(roomModel:GetAttribute("Level3_RoomId") == room.Id
			and roomModel:GetAttribute("Level3_ThemeId") == room.ThemeId
			and roomModel:GetAttribute("Level3_District") == (room.SectionIndex or 0),
			"Level 3 room procedural metadata is stale: " .. room.Id)
		local floorPart = roomModel:FindFirstChild("Level 3 Room Floor")
		assert(floorPart and floorPart:IsA("BasePart"), "Level 3 room floor is missing: " .. room.Id)
		stats.RoomFloors += 1
		local floorTexture = floorPart:FindFirstChild("Level 3 Surface Texture")
		local arrivalMall = room.Id == layout.Roles.ArrivalRoomId
		if arrivalMall then
			assert(floorPart.Material == Enum.Material.Carpet
				and floorTexture and floorTexture:IsA("Texture")
				and floorTexture.Texture == Configuration.Textures.PartyCarpet,
				"Arrival must use the original Level 3 mall party carpet")
			stats.ArrivalMallFloors += 1
		elseif room.Id == layout.Roles.ExitRoomId then
			assert(floorPart.Material == Enum.Material.DiamondPlate and floorTexture == nil,
				"Exit room must keep its explicit DiamondPlate floor exception")
			stats.ExitFloors += 1
		elseif room.ThemeId == "City" then
			assert(floorPart.Material == Enum.Material.Carpet
				and floorTexture and floorTexture:IsA("Texture")
				and floorTexture.Texture == Configuration.Textures.CityCarpet,
				"City district room has the wrong carpet: " .. room.Id)
			stats.CityFloors += 1
		elseif room.ThemeId == "RedParty" then
			assert(floorPart.Material == Enum.Material.Carpet
				and floorTexture and floorTexture:IsA("Texture")
				and floorTexture.Texture == Configuration.Textures.PartyCarpetRed,
				"Red party district room has the wrong carpet: " .. room.Id)
			stats.PartyFloors += 1
			stats.RedPartyFloors += 1
		elseif room.ThemeId == "OrangeBlackParty" then
			assert(floorPart.Material == Enum.Material.Carpet
				and floorTexture and floorTexture:IsA("Texture")
				and floorTexture.Texture == Configuration.Textures.PartyCarpetNeon,
				"Orange/black district room has the wrong carpet: " .. room.Id)
			stats.PartyFloors += 1
			stats.NeonPartyFloors += 1
		else
			error("Unknown generated Level 3 floor theme: " .. tostring(room.ThemeId))
		end

		local ceilingPart = roomModel:FindFirstChild("Level 3 Room Ceiling")
		assert(ceilingPart and ceilingPart:IsA("BasePart"),
			"Level 3 room ceiling is missing: " .. room.Id)
		if arrivalMall then
			assert(ceilingPart.Material == Enum.Material.Plaster
				and ceilingPart.Color == Configuration.Colors.AgedWhite
				and ceilingPart:FindFirstChild("Level 3 Surface Texture") == nil,
				"Arrival must use the Level 3 mall plaster ceiling")
		end

		local expectedWallColor = if room.ThemeId == "City" then Color3.fromRGB(220, 213, 187)
			elseif room.ThemeId == "RedParty" then Color3.fromRGB(145, 58, 48)
			else Color3.fromRGB(183, 78, 35)
		local expectedWallTexture = if room.ThemeId == "City"
			then Configuration.Textures.PastelWallpaper else Configuration.Textures.OrangeWall
		local structuralWalls, wallTextures = 0, 0
		for _, descendant in ipairs(roomModel:GetDescendants()) do
			if descendant:IsA("BasePart") and (
				string.find(descendant.Name, "Level 3 North Wall", 1, true)
				or string.find(descendant.Name, "Level 3 South Wall", 1, true)
				or string.find(descendant.Name, "Level 3 East Wall", 1, true)
				or string.find(descendant.Name, "Level 3 West Wall", 1, true)
				or string.find(descendant.Name, "Level 3 East Lintel", 1, true)
				or string.find(descendant.Name, "Level 3 West Lintel", 1, true)
				or string.find(descendant.Name, "Level 3 North Lintel", 1, true)
				or string.find(descendant.Name, "Level 3 South Lintel", 1, true)
			) then
				structuralWalls += 1
				assert(descendant.Color == expectedWallColor,
					"Wrong generated wall palette in room " .. room.Id .. ": " .. descendant:GetFullName())
				if arrivalMall then
					assert(descendant.Material == Enum.Material.Plaster,
						"Arrival wall must use the Level 3 mall plaster finish: " .. descendant:GetFullName())
				end
				for _, child in ipairs(descendant:GetChildren()) do
					if child:IsA("Texture") then
						wallTextures += 1
						assert(expectedWallTexture ~= nil and child.Texture == expectedWallTexture,
							"Generated wall texture does not match room theme " .. room.ThemeId)
						if child.Texture == Configuration.Textures.OrangeWall then
							stats.OrangeWallTextures += 1
						end
					end
				end
			end
		end
		assert(structuralWalls > 0 and wallTextures > 0,
			"Level 3 generated room is missing or leaking themed wall surfaces: " .. room.Id)
		if observedRoomThemes[room.ThemeId] ~= nil then
			observedRoomThemes[room.ThemeId] += 1
		end
		if room.ThemeId == "City" then
			stats.BeigeRooms += 1
		else
			stats.OrangeRooms += 1
		end
	end
	for themeId, expected in pairs(expectedRoomThemes) do
		assert(observedRoomThemes[themeId] == expected,
			"Level 3 generated room theme count mismatch for " .. themeId)
	end
	assert(stats.RoomFloors == #layout.Rooms
		and stats.ArrivalMallFloors == 1
		and stats.ExitFloors == 1
		and stats.CityFloors == expectedFloorThemes.City
		and stats.RedPartyFloors == expectedFloorThemes.RedParty
		and stats.NeonPartyFloors == expectedFloorThemes.OrangeBlackParty,
		"Level 3 procedural room floor palette is inconsistent")
	assert(stats.OrangeWallTextures > 0,
		"Level 3 non-city rooms are missing their worn-wall finish")

	local expectedCorridorThemes = {City=0, OrangeBlackParty=0, RedParty=0}
	for _, link in ipairs(layout.Links) do
		assert(expectedCorridorThemes[link.ThemeId] ~= nil,
			"Generated Level 3 corridor has an unknown theme: " .. tostring(link.ThemeId))
		expectedCorridorThemes[link.ThemeId] += 1
	end
	local observedCorridorThemes = {City=0, OrangeBlackParty=0, RedParty=0}
	local corridors = world:FindFirstChild("Corridors")
	assert(corridors and corridors:IsA("Folder"), "Level 3 Corridors folder is missing")
	assert(#corridors:GetChildren() == #layout.Links, "Level 3 generated corridor model count mismatch")
	for _, corridorModel in ipairs(corridors:GetChildren()) do
		local themeId = corridorModel:GetAttribute("Level3_ThemeId")
		assert(corridorModel:IsA("Model")
			and expectedCorridorThemes[themeId] ~= nil
			and corridorModel:GetAttribute("Level3_TunnelWidth") == Configuration.CorridorWidth
			and corridorModel:GetAttribute("Level3_TunnelHeight") == Configuration.CorridorHeight,
			"Level 3 corridor profile or procedural theme metadata is invalid: " .. corridorModel:GetFullName())
		observedCorridorThemes[themeId] += 1
		local floorPart = corridorModel:FindFirstChild("Level 3 Corridor Floor")
		local ceilingPart = corridorModel:FindFirstChild("Level 3 Corridor Ceiling")
		assert(floorPart and floorPart:IsA("BasePart")
			and ceilingPart and ceilingPart:IsA("BasePart"),
			"Level 3 tunnel is missing a continuous floor or ceiling: " .. corridorModel:GetFullName())
		assert(approx(ceilingPart.Position.Y - ceilingPart.Size.Y * .5,
			Configuration.WorldOrigin.Y + Configuration.CorridorHeight),
			"Level 3 tunnel has inconsistent ceiling clearance: " .. corridorModel:GetFullName())
		local expectedFloorTexture = if themeId == "City" then Configuration.Textures.CityCarpet
			elseif themeId == "RedParty" then Configuration.Textures.PartyCarpetRed
			else Configuration.Textures.PartyCarpetNeon
		local floorTexture = floorPart:FindFirstChild("Level 3 Surface Texture")
		assert(floorPart.Material == Enum.Material.Carpet
			and floorTexture and floorTexture:IsA("Texture")
			and floorTexture.Texture == expectedFloorTexture,
			"Level 3 corridor floor does not match its generated district theme")
		stats.CorridorFloors += 1

		local expectedWallColor = if themeId == "City" then Color3.fromRGB(220, 213, 187)
			elseif themeId == "RedParty" then Color3.fromRGB(145, 58, 48)
			else Color3.fromRGB(183, 78, 35)
		local expectedWallTexture = if themeId == "City"
			then Configuration.Textures.PastelWallpaper else Configuration.Textures.OrangeWall
		local wallCount, wallTextureCount = 0, 0
		for _, object in ipairs(corridorModel:GetChildren()) do
			if object:IsA("BasePart") and object.Name == "Level 3 Corridor Wall" then
				wallCount += 1
				assert(approx(object.Size.Y, Configuration.CorridorHeight)
					and object.Color == expectedWallColor,
					"Level 3 corridor wall height/palette is inconsistent: " .. corridorModel:GetFullName())
				local horizontal = approx(floorPart.Size.Z, Configuration.CorridorWidth)
				local centerOffset = if horizontal
					then math.abs(object.Position.Z - floorPart.Position.Z)
					else math.abs(object.Position.X - floorPart.Position.X)
				local innerFaceOffset = centerOffset - Configuration.WallThickness * .5
				assert(approx(innerFaceOffset, Configuration.CorridorWidth * .5, .03),
					"Level 3 tunnel wall protrudes into the clear corridor opening: "
						.. corridorModel:GetFullName())
				for _, child in ipairs(object:GetChildren()) do
					if child:IsA("Texture") then
						wallTextureCount += 1
						assert(child.Texture == expectedWallTexture,
							"Level 3 corridor wall finish does not match its generated district")
					end
				end
			end
		end
		assert(wallCount == 2 and wallTextureCount == 2,
			"Level 3 tunnel must have exactly two continuously themed side walls")
	end
	for themeId, expected in pairs(expectedCorridorThemes) do
		assert(observedCorridorThemes[themeId] == expected,
			"Level 3 generated corridor theme count mismatch for " .. themeId)
	end
	assert(stats.CorridorFloors == #layout.Links, "Level 3 generated corridor floor count mismatch")

	local forbiddenDecor = {"Baseboard", "Shelf", "Carton", "Box", "Desk", "CRT", "Plant", "Utility Pipe"}
	for _, instance in ipairs(world:GetDescendants()) do
		local intentionalDiscPlayerAssembly = manifest.DiscPlayer and manifest.DiscPlayer.Model
			and (instance == manifest.DiscPlayer.Model or instance:IsDescendantOf(manifest.DiscPlayer.Model))
		for _, fragment in ipairs(forbiddenDecor) do
			assert(intentionalDiscPlayerAssembly
				or not string.find(instance.Name, fragment, 1, true),
				"Revision 5 contains forbidden clutter: " .. instance:GetFullName())
		end
	end

	assert(stats.BaseParts <= 3500, "Level 3 exceeded its procedural BasePart budget")
	assert(stats.Collidable <= 1250, "Level 3 exceeded its collision budget")
	assert(stats.Lights <= 120 and stats.ShadowLights <= 6, "Level 3 exceeded its procedural lighting budget")
	assert(stats.Prompts <= 32, "Level 3 exceeded its procedural interaction budget")
	return stats
end

function TestSuite.CaptureLifecycleState(): {[string]: any}
	local scripts = {}
	for _, name in ipairs(LEVEL_ONE_RUNTIME_SCRIPTS) do
		local object = ServerScriptService:FindFirstChild(name)
		if object and object:IsA("BaseScript") then scripts[object] = object.Enabled end
	end
	return {
		Lobby = workspace:FindFirstChild("ServerLobby"),
		Entity = workspace:FindFirstChild("Entity"),
		Scripts = scripts,
	}
end

function TestSuite.ValidateMallManagerRuntime(expectedPresent: boolean): {[string]: any}
	assert(type(expectedPresent) == "boolean", "Mall Manager runtime test requires a presence boolean")
	local world = workspace:FindFirstChild(Configuration.WorldName)
	assert(world and world:IsA("Model"), "Mall Manager runtime test requires a live Level 3 world")
	local state = ReplicatedStorage:FindFirstChild(Configuration.StateFolderName)
	assert(state and state:IsA("Folder"), "Mall Manager runtime test requires Level 3 state")
	local runtime = world:FindFirstChild("Mall Manager Runtime")
	assert(runtime and runtime:IsA("Folder"), "Mall Manager runtime folder is missing")
	local managers = {}
	for _, object in ipairs(runtime:GetChildren()) do
		if object:IsA("Model") and object:GetAttribute("Level3_MallManagerRuntime") == true then
			table.insert(managers, object)
		end
	end
	if not expectedPresent then
		assert(#managers == 0, "Mall Manager must not exist before or after the post-song hunt")
		assert(state:GetAttribute("Level3_MallManagerActive") == false
			and workspace:GetAttribute("Level3MallManagerActive") == false,
			"Mall Manager inactive state is not replicated")
		return {State="OFF", Blackout=state:GetAttribute("Level3_BlackoutActive") == true, Parts=0, Bones=0}
	end
	assert(#managers == 1, "Level 3 hunt must own exactly one runtime Mall Manager")
	local expectedBlackout = true
	local manager = managers[1]
	local root = manager:FindFirstChild("HumanoidRootPart")
	local animationController = manager:FindFirstChildOfClass("AnimationController")
	assert(manager.Name == Configuration.MallManager.RuntimeName
		and manager.PrimaryPart == root and root and root:IsA("BasePart") and root.Anchored
		and manager:GetAttribute("Level3_Generation") == world:GetAttribute("Level3_Generation")
		and type(manager:GetAttribute("Level3_MallManagerSpawnSerial")) == "number",
		"Mall Manager runtime root/pivot contract is invalid")
	assert(animationController and animationController:FindFirstChildOfClass("Animator"),
		"Mall Manager runtime animator is missing")
	assert(manager:FindFirstChild("InitialPoses") == nil and manager:FindFirstChild("AnimSaves") == nil,
		"Mall Manager runtime retained authoring-only data")
	local footstepEmitter = root and root:FindFirstChild("Mall Manager Footstep Emitter")
	assert(footstepEmitter and footstepEmitter:IsA("Attachment")
		and footstepEmitter:GetAttribute("Level3_MallManagerFootstepEmitter") == true,
		"Mall Manager runtime foot-height emitter is missing")
	assert(#footstepEmitter:GetChildren() == 4,
		"Mall Manager runtime must own exactly four walk Sound voices")
	for index, name in ipairs(Configuration.MallManager.FootstepSoundNames) do
		local sound = footstepEmitter:FindFirstChild(name)
		assert(sound and sound:IsA("Sound") and sound.SoundId == Configuration.Audio[name]
			and sound.Looped == false and sound.PlayOnRemove == false
			and approx(sound.PlaybackSpeed, 1)
			and approx(sound.Volume, Configuration.MallManager.FootstepVolume)
			and sound.RollOffMode == Enum.RollOffMode.InverseTapered
			and approx(sound.RollOffMinDistance, Configuration.MallManager.FootstepRollOffMinDistance)
			and approx(sound.RollOffMaxDistance, Configuration.MallManager.FootstepRollOffMaxDistance)
			and sound:GetAttribute("FootstepIndex") == index,
			"Mall Manager runtime footstep voice is stale: " .. name)
	end
	local voiceEmitter = manager:FindFirstChild("Head", true)
	assert(voiceEmitter and voiceEmitter:IsA("Bone")
		and voiceEmitter:GetAttribute("Level3_MallManagerVoiceEmitter") == true,
		"Mall Manager balloon-head voice emitter is missing")
	local chaseScream = voiceEmitter:FindFirstChild(Configuration.MallManager.ChaseScreamSoundName)
	assert(chaseScream and chaseScream:IsA("Sound")
		and chaseScream.SoundId == Configuration.Audio.MallManagerBalloonScream
		and chaseScream:GetAttribute("Level3_MallManagerChaseScream") == true
		and chaseScream.Looped == false and chaseScream.PlayOnRemove == false
		and approx(chaseScream.Volume, Configuration.MallManager.ChaseScreamVolume)
		and approx(chaseScream.RollOffMinDistance, Configuration.MallManager.ChaseScreamRollOffMinDistance)
		and approx(chaseScream.RollOffMaxDistance, Configuration.MallManager.ChaseScreamRollOffMaxDistance),
		"Mall Manager runtime chase scream voice is stale")
	local parts, bones = 0, 0
	for _, object in ipairs(manager:GetDescendants()) do
		if object:IsA("BasePart") then
			parts += 1
			assert(not object.CanCollide and not object.CanTouch and not object.CanQuery,
				"Mall Manager runtime part is physically interactive: " .. object:GetFullName())
		elseif object:IsA("Bone") then
			bones += 1
		end
		assert(not object:IsA("Humanoid") and not object:IsA("BaseScript"),
			"Mall Manager runtime must remain a scriptless custom bone rig")
	end
	assert(parts == 2 and bones == 22, "Mall Manager runtime rig topology is stale")
	assert(CollectionService:HasTag(manager, "Level3HostileEntity"),
		"Mall Manager runtime is missing its hostile collection tag")
	assert(state:GetAttribute("Level3_MallManagerActive") == true
		and workspace:GetAttribute("Level3MallManagerActive") == true,
		"Mall Manager active state is not replicated")
	assert(state:GetAttribute("Level3_MallManagerBlackoutBoosted") == expectedBlackout
		and manager:GetAttribute("Level3_MallManagerBlackoutBoosted") == expectedBlackout,
		"Mall Manager blackout profile is stale")
	local expectedRange = if expectedBlackout
		then Configuration.MallManager.Blackout.VisionRange else Configuration.MallManager.Normal.VisionRange
	assert(state:GetAttribute("Level3_MallManagerAwarenessRange") == expectedRange,
		"Mall Manager awareness range does not match the active lighting profile")
	local spawnDistance = state:GetAttribute("Level3_MallManagerSpawnDistance") or 0
	local finaleSpawn = state:GetAttribute("Level3_FinalHallChaseActive") == true
	if finaleSpawn then
		local marker = world:FindFirstChild("Level 3 Mall Manager Finale Spawn", true)
		local authoredSpawn = state:GetAttribute("Level3_MallManagerSpawnPosition")
		assert(marker and marker:IsA("BasePart") and typeof(authoredSpawn) == "Vector3"
			and (Vector3.new(authoredSpawn.X, 0, authoredSpawn.Z)
				- Vector3.new(marker.Position.X, 0, marker.Position.Z)).Magnitude <= 1.5
			and manager:GetAttribute("Level3_MallManagerFinaleSpawn") == true
			and state:GetAttribute("Level3_MallManagerFinaleSpawn") == true
			and (state:GetAttribute("Level3_MallManagerSpawnGroupSize") or 0) >= 1
			and state:GetAttribute("Level3_MallManagerSpawnPathValidated") == true,
			"Mall Manager finale spawn is not on its authored hall marker")
	else
		assert(spawnDistance >= Configuration.MallManager.SpawnMinimumDistance
			and spawnDistance <= Configuration.MallManager.SpawnMaximumDistance + 1
			and (state:GetAttribute("Level3_MallManagerSpawnGroupSize") or 0) >= 1
			and state:GetAttribute("Level3_MallManagerSpawnRoomId") ~= "Exit"
			and state:GetAttribute("Level3_MallManagerSpawnVisibleCount") == 0
			and type(state:GetAttribute("Level3_MallManagerSpawnPathValidated")) == "boolean",
			"Mall Manager grouped runtime spawn is not distant, hidden, and route-audited")
	end
	assert(type(state:GetAttribute("Level3_MallManagerFootstepSerial")) == "number"
		and (state:GetAttribute("Level3_MallManagerFootstepSerial") or 0) >= 0
		and type(state:GetAttribute("Level3_MallManagerLastFootstepName")) == "string",
		"Mall Manager footstep diagnostics are missing")
	assert(type(state:GetAttribute("Level3_MallManagerChaseScreamSerial")) == "number"
		and (state:GetAttribute("Level3_MallManagerChaseScreamSerial") or 0) >= 0
		and type(state:GetAttribute("Level3_MallManagerChaseScreamPlaying")) == "boolean"
		and type(state:GetAttribute("Level3_MallManagerLastChaseScreamName")) == "string",
		"Mall Manager chase scream diagnostics are missing")
	local runtimeCorridors = world:FindFirstChild("Corridors")
	assert(runtimeCorridors and runtimeCorridors:IsA("Folder"),
		"Mall Manager runtime test requires generated corridor metadata")
	local expectedOpeningCount = #runtimeCorridors:GetChildren() * 2
	assert(state:GetAttribute("Level3_BlackoutScreamAssetId") == Configuration.Audio.MallManagerBlackout
		and approx(state:GetAttribute("Level3_BlackoutScreamDuration") or 0,
			Configuration.MallManager.BlackoutScreamDurationSeconds, .000001)
		and state:GetAttribute("Level3_BlackoutScreamOpeningCount") == expectedOpeningCount,
		"Level 3 blackout scream state is missing or stale")
	return {
		State = state:GetAttribute("Level3_MallManagerState"),
		Blackout = expectedBlackout,
		AwarenessRange = expectedRange,
		Parts = parts,
		Bones = bones,
	}
end

function TestSuite.ValidateRuntime(expectedProgress: number): {[string]: any}
	assert(expectedProgress % 1 == 0 and expectedProgress >= 0
		and expectedProgress <= Configuration.ModuleGoal,
		"ValidateRuntime progress must be an integer from 0 through ModuleGoal")
	local world = workspace:FindFirstChild(Configuration.WorldName)
	assert(world and world:IsA("Model"), "ValidateRuntime requires a live Level 3 world")
	local state = ReplicatedStorage:FindFirstChild(Configuration.StateFolderName)
	assert(state and state:IsA("Folder"), "ValidateRuntime requires Level 3 replicated state")
	local unlocked = expectedProgress == Configuration.ModuleGoal
	assert(state:GetAttribute("Level3_ModuleProgress") == expectedProgress
		and state:GetAttribute("Level3_ModuleGoal") == Configuration.ModuleGoal
		and state:GetAttribute("Level3_ExitUnlocked") == unlocked
		and state:GetAttribute("Level3_Phase") == (if unlocked then "EXIT_UNLOCKED" else "SEARCH"),
		"Replicated Level 3 progress does not match the expected runtime phase")
	assert(workspace:GetAttribute("Level3Modules") == expectedProgress
		and workspace:GetAttribute("Level3ModuleGoal") == Configuration.ModuleGoal
		and workspace:GetAttribute("Level3ExitUnlocked") == unlocked,
		"Workspace Level 3 progress mirrors are stale")
	local managerReport = TestSuite.ValidateMallManagerRuntime(
		state:GetAttribute("Level3_MallManagerHuntActive") == true)

	local portalModel = world:FindFirstChild("Level 3 Hidden Exit Portal", true)
	assert(portalModel and portalModel:IsA("Model"), "Live Level 3 hidden exit portal is missing")
	local hiddenWall: BasePart? = nil
	local frameParts = {}
	local portalLight: Light? = nil
	for _, instance in ipairs(portalModel:GetDescendants()) do
		if instance:IsA("BasePart") and instance:GetAttribute("Level3_HiddenExitWall") == true then
			hiddenWall = instance
		elseif instance:IsA("BasePart") and instance:GetAttribute("Level3_HiddenExitFrame") == true then
			table.insert(frameParts, instance)
		elseif instance:IsA("Light") and instance.Name == "Hidden Exit Blue Spill" then
			portalLight = instance
		end
	end
	assert(hiddenWall and hiddenWall.Transparency == 0
		and hiddenWall.CanCollide == (not unlocked)
		and hiddenWall.CanQuery and not hiddenWall.CanTouch,
		"Hidden exit wall collision/reveal state does not match objective progress")
	assert(#frameParts == 8 and portalLight,
		"Hidden exit runtime reveal objects are incomplete")
	assert(portalModel:GetAttribute("Level3_ExitUnlocked") == unlocked,
		"Hidden exit model unlock attribute is stale")
	for _, framePart in ipairs(frameParts) do
		if unlocked then
			assert(framePart.Transparency <= 0.10,
				"Unlocked hidden-exit frame did not complete its reveal tween")
		else
			assert(framePart.Transparency >= 0.99,
				"Hidden-exit frame became visible before 5/5 modules")
		end
	end
	assert(portalLight.Enabled == false,
		"Hidden-exit blue spill must remain off during the lightless finale")
	assert(state:GetAttribute("Level3_ExitGuideActive") == false
		and state:GetAttribute("Level3_ExitGuideLampCount") == 0
		and workspace:GetAttribute("Level3ExitGuideActive") == false,
		"Exit breadcrumb lighting must remain disabled")
	for _, object in ipairs(world:GetDescendants()) do
		assert(object:GetAttribute("Level3_ExitGuideLight") ~= true
			and object:GetAttribute("Level3_ExitGuideLamp") ~= true,
			"Level 3 retained a forbidden exit-guide light tag")
	end

	local discPlayer = world:FindFirstChild("Level 3 Signal Hall Disc Player", true)
	assert(discPlayer and discPlayer:IsA("Model"), "Live Level 3 Signal Hall disc player is missing")
	assert(discPlayer:GetAttribute("Level3_CDInsertedCount") == expectedProgress
		and discPlayer:GetAttribute("Level3_CDGoal") == Configuration.ModuleGoal,
		"Disc player progress attributes are stale")
	local insertPrompt = discPlayer:FindFirstChild("InsertCDPrompt", true)
	assert(insertPrompt and insertPrompt:IsA("ProximityPrompt") and insertPrompt.Enabled == (not unlocked),
		"Disc player insert prompt enabled state does not match inserted progress")
	local indicatorCount, litIndicators, insertedVisuals = 0, 0, 0
	for _, object in ipairs(discPlayer:GetDescendants()) do
		if object:IsA("BasePart") and object:GetAttribute("Level3_CDIndicatorOn") ~= nil then
			indicatorCount += 1
			if object:GetAttribute("Level3_CDIndicatorOn") == true then litIndicators += 1 end
		elseif object:IsA("BasePart") and object:GetAttribute("Level3_CDState") == "INSERTED" then
			insertedVisuals += 1
			assert(object.Transparency < .99, "Inserted CD visual remained hidden")
		end
	end
	assert(indicatorCount == Configuration.ModuleGoal and litIndicators == expectedProgress
		and insertedVisuals == expectedProgress,
		"Disc player lights or inserted-disc visuals do not match inserted progress")

	local escapePrompt = world:FindFirstChild("EscapePrompt", true)
	assert(escapePrompt and escapePrompt:IsA("ProximityPrompt") and escapePrompt.Enabled == unlocked,
		"Final escape prompt enabled state does not match module progress")

	local collectedModules = 0
	for _, model in ipairs(world:GetDescendants()) do
		if model:IsA("Model") and model:GetAttribute("Level3_ModuleIndex") ~= nil then
			local collected = model:GetAttribute("Level3_Collected") == true
			if collected then collectedModules += 1 end
			local prompt = model:FindFirstChild("CollectPrompt", true)
			assert(prompt and prompt:IsA("ProximityPrompt") and prompt.Enabled ~= collected,
				"Module prompt/collected state mismatch: " .. model:GetFullName())
			local pickupVisuals, persistentDisplays = 0, 0
			for _, object in ipairs(model:GetDescendants()) do
				if object:IsA("BasePart") and object:GetAttribute("Level3_CDPickupVisual") == true then
					pickupVisuals += 1
					if collected then
						assert(object.Transparency >= .99 and not object.CanCollide
							and not object.CanTouch and not object.CanQuery,
							"Collected CD disc/hub remains interactable or visible: " .. object:GetFullName())
					end
				elseif object:IsA("BasePart") and object:GetAttribute("Level3_CDPersistentDisplay") == true then
					persistentDisplays += 1
					assert(object.Transparency < .99,
						"CD jewel case or illustrated cover disappeared: " .. object:GetFullName())
				end
			end
			assert(pickupVisuals == 2 and persistentDisplays == 2,
				"CD pickup/display ownership markers are incomplete: " .. model:GetFullName())
		end
	end
	local collectedProgress = state:GetAttribute("Level3_CDCollectedProgress")
	assert(type(collectedProgress) == "number" and collectedProgress >= expectedProgress
		and collectedProgress <= Configuration.ModuleGoal,
		"Collected CD progress is missing or lower than inserted progress")
	assert(collectedModules == collectedProgress,
		"Collected source-CD model count does not match replicated collected progress")
	assert(state:GetAttribute("Level3_CDInsertedProgress") == expectedProgress,
		"Explicit inserted CD progress is stale")

	local stableDoors = 0
	for _, model in ipairs(world:GetDescendants()) do
		if model:IsA("Model") and model:GetAttribute("Level3_DoorId") ~= nil then
			stableDoors += 1
		end
	end
	assert(stableDoors == 0, "Revision 5 must not restore ordinary interactive Level 3 doors")
	return {Progress = expectedProgress, Frames = #frameParts, Doors = stableDoors,
		MallManager = managerReport}
end

function TestSuite.ValidateCleanup(snapshot: {[string]: any}): {[string]: any}
	assert(type(snapshot) == "table" and type(snapshot.Scripts) == "table",
		"ValidateCleanup requires a CaptureLifecycleState snapshot")
	assert(workspace:FindFirstChild(Configuration.WorldName) == nil,
		"Level 3 generated world survived cleanup")
	assert(workspace:FindFirstChild("EntityStart") == nil,
		"Restricted EntityStart marker survived Level 3 cleanup")
	for _, child in ipairs(workspace:GetChildren()) do
		assert(child:GetAttribute("Level3_CompatibilityMarker") ~= true,
			"Level 3 compatibility marker survived cleanup: " .. child:GetFullName())
	end
	if snapshot.Lobby then
		assert(snapshot.Lobby.Parent == workspace and snapshot.Lobby.Name == "ServerLobby",
			"Cleanup did not restore the original ServerLobby instance")
	end
	if snapshot.Entity then
		assert(snapshot.Entity.Parent == workspace and snapshot.Entity.Name == "Entity",
			"Cleanup did not restore the original Level 1 Entity instance")
	end
	for object, wasEnabled in pairs(snapshot.Scripts) do
		assert(object.Parent and object.Enabled == wasEnabled,
			"Cleanup did not restore Level 1 script state: " .. object.Name)
	end
	assert(ServerStorage:FindFirstChild("Level 3 Stored Server Lobby") == nil,
		"Cleanup left a parked Level 3 lobby in ServerStorage")
	assert(ServerStorage:FindFirstChild("Level 3 Stored Level 1 Entity") == nil,
		"Cleanup left a parked Level 1 entity in ServerStorage")

	assert(workspace:GetAttribute("WorldGenerated") == false
		and workspace:GetAttribute("SelectedLevel") ~= 3
		and workspace:GetAttribute("Level3Modules") == 0
		and workspace:GetAttribute("Level3ModuleGoal") == 0
		and workspace:GetAttribute("Level3ExitUnlocked") == false
		and workspace:GetAttribute("Level3LightingOwnedByController") == false
		and workspace:GetAttribute("Level3PreBlackoutActive") == false
		and workspace:GetAttribute("Level3BlackoutActive") == false
		and workspace:GetAttribute("Level3MallManagerHuntActive") == false
		and workspace:GetAttribute("Level3RecoveryFlickerActive") == false
		and workspace:GetAttribute("Level3MallManagerActive") == false
		and workspace:GetAttribute("Level3MallManagerState") == "OFF"
		and workspace:GetAttribute("Level3MallManagerBlackoutBoosted") == false
		and workspace:GetAttribute("Level3HiddenPlayers") == 0,
		"Cleanup did not reset Level 3 workspace state")
	assert(#CollectionService:GetTagged("Level3HostileEntity") == 0,
		"Cleanup left a tagged Mall Manager runtime behind")
	for _, legacyName in ipairs({"Level3Pumps", "Level3PumpGoal", "Level3ExitPowered"}) do
		assert(workspace:GetAttribute(legacyName) == nil,
			"Cleanup retained legacy workspace attribute " .. legacyName)
	end
	local state = ReplicatedStorage:FindFirstChild(Configuration.StateFolderName)
	assert(state and state:IsA("Folder"), "Cleanup removed the Level 3 state folder")
	assert(state:GetAttribute("Level3_Phase") == "IDLE"
		and state:GetAttribute("Level3_ModuleProgress") == 0
		and state:GetAttribute("Level3_ModuleGoal") == 0
		and state:GetAttribute("Level3_ExitUnlocked") == false
		and state:GetAttribute("Level3_ExitPosition") == nil
		and state:GetAttribute("Level3_LightingMode") == "OFF"
		and state:GetAttribute("Level3_PreBlackoutActive") == false
		and state:GetAttribute("Level3_BlackoutActive") == false
		and state:GetAttribute("Level3_MallManagerHuntActive") == false
		and state:GetAttribute("Level3_RecoveryFlickerActive") == false
		and state:GetAttribute("Level3_MallManagerActive") == false
		and state:GetAttribute("Level3_MallManagerState") == "OFF"
		and state:GetAttribute("Level3_MallManagerBlackoutBoosted") == false
		and state:GetAttribute("Level3_MallManagerTargetUserId") == 0
		and state:GetAttribute("Level3_MallManagerSpeed") == 0
		and state:GetAttribute("Level3_MallManagerAwarenessRange") == 0
		and state:GetAttribute("Level3_MallManagerFootstepSerial") == 0
		and state:GetAttribute("Level3_MallManagerLastFootstepIndex") == 0
		and state:GetAttribute("Level3_MallManagerLastFootstepName") == ""
		and state:GetAttribute("Level3_MallManagerLastFootstepPhase") == 0
		and state:GetAttribute("Level3_MallManagerChaseScreamSerial") == 0
		and state:GetAttribute("Level3_MallManagerChaseScreamPlaying") == false
		and state:GetAttribute("Level3_MallManagerLastChaseScreamAtServerTime") == 0
		and state:GetAttribute("Level3_MallManagerLastChaseScreamName") == ""
		and state:GetAttribute("Level3_BlackoutScreamOpeningCount") == 0
		and state:GetAttribute("Level3_BlackoutScreamStartedAtServerTime") == 0
		and state:GetAttribute("Level3_HiddenPlayers") == 0
		and state:GetAttribute("Level3_MallManagerSpawnAnchorUserId") == 0
		and state:GetAttribute("Level3_MallManagerSpawnGroupSize") == 0
		and state:GetAttribute("Level3_MallManagerSpawnCycle") == 0
		and state:GetAttribute("Level3_MallManagerSpawnSerial") == 0
		and approx(state:GetAttribute("Level3_BlackoutScreamDuration") or 0,
			Configuration.MallManager.BlackoutScreamDurationSeconds, .000001)
		and state:GetAttribute("Level3_Error") == nil,
		"Cleanup did not reset replicated Level 3 state")
	for _, player in ipairs(game:GetService("Players"):GetPlayers()) do
		assert(player:GetAttribute("Level3_Hiding") ~= true
			and (player:GetAttribute("Level3_HideTableIndex") or 0) == 0,
			"Cleanup left a player hidden under a destroyed table")
	end
	return {RestoredScripts = countMap(snapshot.Scripts)}
end

return TestSuite
