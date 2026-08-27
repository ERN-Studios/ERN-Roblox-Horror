--!strict
-- Level 3 deterministic structural checks. Layout/configuration checks are safe
-- in Edit mode; ValidateWorld consumes a manifest built by the normal round flow.

local Configuration = require(script.Parent:WaitForChild("Level 3 Configuration"))
local LayoutGenerator = require(script.Parent:WaitForChild("Level 3 Layout Generator"))
local HidingController = require(script.Parent:WaitForChild("Level 3 Hiding Controller"))
local CollectionService = game:GetService("CollectionService")
local ReplicatedStorage = game:GetService("ReplicatedStorage")
local RunService = game:GetService("RunService")
local ServerScriptService = game:GetService("ServerScriptService")
local ServerStorage = game:GetService("ServerStorage")
local StarterPlayer = game:GetService("StarterPlayer")
local Players = game:GetService("Players")

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
		and managerTuning.PathAgentRadius == 4
		and managerTuning.PathAgentRadius <= managerTuning.AgentRadius
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
			and state:GetAttribute("Level3_MallManagerSpawnClearanceValidated") == true
			and type(state:GetAttribute("Level3_MallManagerPathValidated")) == "boolean",
			"Mall Manager finale spawn is not on its authored hall marker")
	else
		-- SpawnClearanceValidated is a genuine claim: every scored spawn
		-- candidate passed spawnVolumeFits. Route reachability is proven
		-- asynchronously — Level3_MallManagerPathValidated flips true only after
		-- the authoritative volume sweep accepts a complete route to the resolved
		-- goal, so at spawn time only its type is checked here; behavioral tests
		-- assert it becomes true in bounded time.
		assert(spawnDistance >= Configuration.MallManager.SpawnMinimumDistance
			and spawnDistance <= Configuration.MallManager.SpawnMaximumDistance + 1
			and (state:GetAttribute("Level3_MallManagerSpawnGroupSize") or 0) >= 1
			and state:GetAttribute("Level3_MallManagerSpawnRoomId") ~= "Exit"
			and state:GetAttribute("Level3_MallManagerSpawnVisibleCount") == 0
			and state:GetAttribute("Level3_MallManagerSpawnClearanceValidated") == true
			and type(state:GetAttribute("Level3_MallManagerPathValidated")) == "boolean",
			"Mall Manager grouped runtime spawn is not distant, hidden, and clearance-audited")
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

-- ---------------------------------------------------------------------------
-- LEVEL3_MANAGER_NAV_TESTS_20260827 — behavioral navigation coverage.
-- ValidateNavigationLayouts is pure and Edit-mode safe; the telemetry and
-- furniture checks consume a live play-session hunt (Controller.GetSnapshot()
-- and the generated world) because there are no player mocks.
-- ---------------------------------------------------------------------------

-- Twenty deterministic layouts including every seed the fix contract names.
local NAVIGATION_TEST_SEEDS = {
	1, 2, 17, 101, 7331, 65537, 424242, 987654321, 1900813, 31337,
	555001, 555002, 555003, 555004, 555005, 777101, 777102, 777103, 777104, 777105,
}

-- Mirrors the AI controller's room-bounds classification: distance to the
-- room's floor rectangle, zero inside the bounds.
local function roomRectangleDistance(room: {[string]: any}, x: number, z: number): number
	local dx = math.max(math.abs(x - room.X) - room.W * .5, 0)
	local dz = math.max(math.abs(z - room.Z) - room.D * .5, 0)
	return math.sqrt(dx * dx + dz * dz)
end

local function classifyRoomByBounds(layout: {[string]: any}, x: number, z: number): string
	local bestId = ""
	local bestDistance = math.huge
	for _, room in ipairs(layout.Rooms) do
		local distance = roomRectangleDistance(room, x, z)
		if distance < bestDistance then
			bestDistance = distance
			bestId = room.Id
		end
	end
	return bestId
end

-- Mirrors the world builder's corridor endpoint derivation in layout space.
local function corridorEndpoints(a: {[string]: any}, b: {[string]: any}): (number, number, number, number)
	local horizontal = math.abs(b.X - a.X) > math.abs(b.Z - a.Z)
	if horizontal then
		local direction = if b.X > a.X then 1 else -1
		return a.X + direction * a.W * .5, a.Z, b.X - direction * b.W * .5, b.Z
	end
	local direction = if b.Z > a.Z then 1 else -1
	return a.X, a.Z + direction * a.D * .5, b.X, b.Z - direction * b.D * .5
end

function TestSuite.ValidateNavigationLayouts(): {[string]: any}
	local requiredSeeds = {[101] = false, [7331] = false, [65537] = false, [1900813] = false}
	assert(#NAVIGATION_TEST_SEEDS >= 20, "Navigation layout coverage requires at least 20 seeds")
	for _, seed in ipairs(NAVIGATION_TEST_SEEDS) do
		if requiredSeeds[seed] ~= nil then requiredSeeds[seed] = true end
		local layout = LayoutGenerator.Generate(seed)
		local valid, validationProblem = LayoutGenerator.Validate(layout)
		assert(valid, string.format("Seed %d failed LayoutGenerator.Validate: %s",
			seed, tostring(validationProblem)))
		local roomById = layout.RoomById
		-- Every room centre must classify to its own room.
		for _, room in ipairs(layout.Rooms) do
			assert(classifyRoomByBounds(layout, room.X, room.Z) == room.Id,
				string.format("Seed %d: room %s centre classifies to the wrong room", seed, room.Id))
			assert(roomRectangleDistance(room, room.X, room.Z) <= 0,
				string.format("Seed %d: room %s centre is outside its own bounds", seed, room.Id))
		end
		-- Corridor mouths and midpoints must classify to the rooms they join —
		-- the doorway misclassification that centre-distance produced.
		local hiddenExitCount = 0
		for _, link in ipairs(layout.Links) do
			local a, b = roomById[link.A], roomById[link.B]
			assert(a and b, string.format("Seed %d: link joins unknown rooms", seed))
			local ax, az, bx, bz = corridorEndpoints(a, b)
			if link.Door == "HiddenExit" then
				hiddenExitCount += 1
				assert(link.A == "SignalHall" and link.B == "Exit",
					string.format("Seed %d: HiddenExit must join SignalHall to Exit", seed))
			else
				local startRoom = classifyRoomByBounds(layout, ax, az)
				local finishRoom = classifyRoomByBounds(layout, bx, bz)
				assert(startRoom == link.A,
					string.format("Seed %d: corridor mouth at %s classifies to %s", seed, link.A, startRoom))
				assert(finishRoom == link.B,
					string.format("Seed %d: corridor mouth at %s classifies to %s", seed, link.B, finishRoom))
				local middle = classifyRoomByBounds(layout, (ax + bx) * .5, (az + bz) * .5)
				assert(middle == link.A or middle == link.B,
					string.format("Seed %d: corridor midpoint %s-%s classifies to third room %s",
						seed, link.A, link.B, middle))
			end
		end
		assert(hiddenExitCount == 1,
			string.format("Seed %d: expected exactly one HiddenExit link", seed))
		-- The Manager's strategy graph excludes HiddenExit links: every room
		-- except the sealed Exit must stay reachable from Arrival, and Exit
		-- must not be.
		local adjacency: {[string]: {string}} = {}
		for _, room in ipairs(layout.Rooms) do adjacency[room.Id] = {} end
		for _, link in ipairs(layout.Links) do
			if link.Door ~= "HiddenExit" then
				table.insert(adjacency[link.A], link.B)
				table.insert(adjacency[link.B], link.A)
			end
		end
		local seen: {[string]: boolean} = {Arrival = true}
		local queue = {"Arrival"}
		local cursor = 1
		while cursor <= #queue do
			local roomId = queue[cursor]
			cursor += 1
			for _, neighbour in ipairs(adjacency[roomId]) do
				if not seen[neighbour] then
					seen[neighbour] = true
					table.insert(queue, neighbour)
				end
			end
		end
		for _, room in ipairs(layout.Rooms) do
			if room.Id == "Exit" then
				assert(not seen[room.Id],
					string.format("Seed %d: strategy graph must not reach the sealed Exit", seed))
			else
				assert(seen[room.Id],
					string.format("Seed %d: strategy graph cannot reach room %s", seed, room.Id))
			end
		end
	end
	for seed, covered in pairs(requiredSeeds) do
		assert(covered, string.format("Required navigation seed %d was not exercised", seed))
	end
	return {Seeds = #NAVIGATION_TEST_SEEDS}
end

-- Asserts the live hunt telemetry contract on a Controller.GetSnapshot()
-- table: single-flight computation, the five-per-second blackout request
-- ceiling, state-aware furniture envelopes, honest validation flags, and the
-- no-motionless-chase window.
function TestSuite.ValidateManagerNavigationTelemetry(snapshot: {[string]: any}?,
	requirePathValidated: boolean?): {[string]: any}
	assert(type(snapshot) == "table", "Navigation telemetry requires a live Mall Manager snapshot")
	local tuning = Configuration.MallManager
	assert(type(snapshot.PeakConcurrentPathComputes) == "number"
		and snapshot.PeakConcurrentPathComputes <= 1,
		"Mall Manager ran more than one path computation in flight")
	assert(type(snapshot.PathComputeSerial) == "number"
		and type(snapshot.PathComputesLastSecond) == "number"
		and snapshot.PathComputesLastSecond <= 5,
		"Mall Manager exceeded five path computations in one second")
	assert(type(snapshot.StrategicIndex) == "number" and snapshot.StrategicIndex >= 1
		and type(snapshot.StrategicPointCount) == "number"
		and type(snapshot.StrategicRebuildSerial) == "number"
		and type(snapshot.StrategicGoalRevision) == "number"
		and type(snapshot.StuckRecoveries) == "number"
		and type(snapshot.RecoveryRepaths) == "number"
		and type(snapshot.GenuineProgressSerial) == "number"
		and type(snapshot.OverlapEscapeSearches) == "number",
		"Mall Manager strategic, progress or escape telemetry is missing")
	-- The escape ladder is a bounded state, clamped one step past exhaustion.
	-- Unbounded retry pressure would show up here rather than in the honest
	-- OverlapEscapeSearches total.
	assert(type(snapshot.OverlapEscapeAttempts) == "number"
		and snapshot.OverlapEscapeAttempts >= 0
		and snapshot.OverlapEscapeAttempts <= tuning.ObstructionRecoveryAttempts + 1,
		string.format("Mall Manager overlap escalation ladder is unbounded (%s)",
			tostring(snapshot.OverlapEscapeAttempts)))
	assert(snapshot.SpawnClearanceValidated == true,
		"Mall Manager spawn was not clearance-validated")
	assert(type(snapshot.PathValidated) == "boolean",
		"Mall Manager path validation telemetry is missing")
	if requirePathValidated then
		assert(snapshot.PathValidated == true,
			"Mall Manager never proved a genuine route to its resolved goal")
	end
	local suppressed = workspace:GetAttribute("Level3FurnitureCollisionSuppressed") == true
	if suppressed then
		assert(snapshot.FurnitureNavExclusionsActive == 0,
			"Ghost furniture envelopes are still steering the Mall Manager")
	else
		assert(snapshot.FurnitureNavExclusionsActive == snapshot.FurnitureNavExclusionsTotal,
			"Restored furniture envelopes are not all guarding navigation")
	end
	-- NOTE: no motionless-chase assertion here. A single snapshot's
	-- LastProgressAgeSeconds is rearmed by recovery, so it can look healthy
	-- while the rig has not moved at all. That claim is proven only by
	-- ProbeChaseForwardProgress, which samples position, segment distance and
	-- the route indices over time.
	return {
		PathComputeSerial = snapshot.PathComputeSerial,
		PathComputesLastSecond = snapshot.PathComputesLastSecond,
		PeakConcurrentPathComputes = snapshot.PeakConcurrentPathComputes,
		PathValidated = snapshot.PathValidated,
		FurnitureNavExclusionsActive = snapshot.FurnitureNavExclusionsActive,
		FurnitureNavExclusionsTotal = snapshot.FurnitureNavExclusionsTotal,
		StuckRecoveries = snapshot.StuckRecoveries,
		RecoveryRepaths = snapshot.RecoveryRepaths,
		GenuineProgressSerial = snapshot.GenuineProgressSerial,
		StrategicGoalRevision = snapshot.StrategicGoalRevision,
		OverlapEscapeAttempts = snapshot.OverlapEscapeAttempts,
		OverlapEscapeSearches = snapshot.OverlapEscapeSearches,
	}
end

-- Captures every temporary hunt furniture part's mutable properties, and the
-- visibility of each Decal/Texture the furniture state machine drives, before a
-- blackout cycle so restoration can be proven afterwards. Chair CFrames are
-- deliberately not compared — shiftBlackoutChairs moves three chairs once per
-- session by design.
function TestSuite.CaptureFurnitureBaseline(world: Instance): {[string]: any}
	assert(world and world.Parent == workspace, "Furniture baseline requires the live generated world")
	local records = {}
	local visualCount = 0
	for _, object in ipairs(world:GetDescendants()) do
		if object:IsA("BasePart") and object:GetAttribute("Level3_TemporaryHuntFurniture") == true then
			local visuals = {}
			for _, child in ipairs(object:GetDescendants()) do
				if child:IsA("Decal") or child:IsA("Texture") then
					table.insert(visuals, {
						Object = child,
						Parent = child.Parent,
						Transparency = child.Transparency,
					})
					visualCount += 1
				end
			end
			table.insert(records, {
				Part = object,
				Parent = object.Parent,
				Name = object:GetFullName(),
				Transparency = object.Transparency,
				CanCollide = object.CanCollide,
				CanTouch = object.CanTouch,
				CanQuery = object.CanQuery,
				CastShadow = object.CastShadow,
				Visuals = visuals,
			})
		end
	end
	assert(#records > 0, "Level 3 world has no temporary hunt furniture to audit")
	return {World = world, Records = records, VisualCount = visualCount}
end

function TestSuite.ValidateFurnitureRestored(baseline: {[string]: any}): {[string]: any}
	assert(type(baseline) == "table" and type(baseline.Records) == "table",
		"ValidateFurnitureRestored requires a CaptureFurnitureBaseline result")
	local checked, visualsChecked = 0, 0
	local missing, mismatched, visualMismatched = {}, {}, {}
	for _, record in ipairs(baseline.Records) do
		local part = record.Part
		-- A destroyed or reparented part is a restoration FAILURE, never a
		-- silent skip: losing furniture is exactly the regression this guards.
		if not part or part.Parent ~= record.Parent or not part:IsDescendantOf(baseline.World) then
			table.insert(missing, record.Name)
		else
			checked += 1
			if part.Transparency ~= record.Transparency
				or part.CanCollide ~= record.CanCollide
				or part.CanTouch ~= record.CanTouch
				or part.CanQuery ~= record.CanQuery
				or part.CastShadow ~= record.CastShadow then
				table.insert(mismatched, record.Name)
			end
			for _, visualRecord in ipairs(record.Visuals) do
				local visual = visualRecord.Object
				if not visual or visual.Parent ~= visualRecord.Parent
					or not visual:IsDescendantOf(part) then
					table.insert(missing, record.Name .. " (visual)")
				else
					visualsChecked += 1
					if visual.Transparency ~= visualRecord.Transparency then
						table.insert(visualMismatched, visual:GetFullName())
					end
				end
			end
		end
	end
	assert(#missing == 0, string.format(
		"%d furniture part(s)/visual(s) went missing across the cycle; first: %s",
		#missing, tostring(missing[1])))
	assert(checked == #baseline.Records, string.format(
		"Furniture audit covered %d of %d baseline parts", checked, #baseline.Records))
	assert(#mismatched == 0, string.format(
		"%d furniture part(s) did not restore their original properties; first: %s",
		#mismatched, tostring(mismatched[1])))
	assert(#visualMismatched == 0, string.format(
		"%d furniture decal/texture(s) did not restore visibility; first: %s",
		#visualMismatched, tostring(visualMismatched[1])))
	assert(visualsChecked == (baseline.VisualCount or visualsChecked), string.format(
		"Furniture visual audit covered %d of %d captured decals/textures",
		visualsChecked, tostring(baseline.VisualCount)))
	return {Checked = checked, VisualsChecked = visualsChecked}
end

-- ---------------------------------------------------------------------------
-- Deterministic behavioral navigation probes. Each drives the LIVE controller
-- and returns a time series, so no claim rests on a single self-reported
-- snapshot. All scaffolding parts are destroyed before returning, including on
-- failure. Every probe takes the Mall Manager controller module so the suite
-- never has to require its sibling behind the Edit-mode require cache.
-- ---------------------------------------------------------------------------

local PROBE_BLOCK_HEIGHT = 6
-- Just outside the SweepRadius 5.25 clearance square (whose corners reach 7.42)
-- so the annulus is absent at the centre and present after any 3.5-stud probe.
local PROBE_RING_RADIUS = 8.6

local function assertStudioProbe(name: string)
	assert(RunService:IsStudio(), name .. " is Studio-only")
end

-- The attack probes intentionally exercise the real capture path. Keep the
-- character alive without weakening the controller's attack contract, then
-- put every mutated player/character value back even when an assertion fails.
local function protectPlayer(player: Player): {[string]: any}
	assert(player.Parent == Players, "Probe player is no longer in Players")
	assert(not HidingController.IsHidden(player),
		"Probe player must be exposed; exit the hiding spot before navigation regression")
	local character = assert(player.Character, "Probe requires a live character")
	local humanoid = assert(character:FindFirstChildOfClass("Humanoid"),
		"Probe character has no Humanoid")
	local root = assert(character:FindFirstChild("HumanoidRootPart"),
		"Probe character has no HumanoidRootPart") :: BasePart
	assert(humanoid.Health > 0, "Probe character is already dead")
	local record: {[string]: any} = {
		Player = player,
		Character = character,
		Humanoid = humanoid,
		Root = root,
		Pivot = character:GetPivot(),
		RootAnchored = root.Anchored,
		RootLinearVelocity = root.AssemblyLinearVelocity,
		RootAngularVelocity = root.AssemblyAngularVelocity,
		Health = humanoid.Health,
		BreakJointsOnDeath = humanoid.BreakJointsOnDeath,
		DeadEnabled = humanoid:GetStateEnabled(Enum.HumanoidStateType.Dead),
		InRound = player:GetAttribute("InRound"),
		Escaped = player:GetAttribute("Escaped"),
		KeepingAlive = true,
	}
	player:SetAttribute("InRound", true)
	player:SetAttribute("Escaped", false)
	humanoid.BreakJointsOnDeath = false
	humanoid:SetStateEnabled(Enum.HumanoidStateType.Dead, false)
	root.Anchored = true
	record.HealthConnection = humanoid.HealthChanged:Connect(function(health)
		if record.KeepingAlive and health <= 0 and humanoid.Parent then
			humanoid.Health = math.max(record.Health, 1)
		end
	end)
	return record
end

local function restoreProtectedPlayer(record: {[string]: any})
	local player = record.Player
	local character = record.Character
	local humanoid = record.Humanoid
	local root = record.Root
	local characterIntact = player and player.Parent == Players
		and player.Character == character
		and character and character.Parent
		and humanoid and humanoid.Parent == character
		and root and root.Parent == character
	local restoreOk: boolean, restoreError: any = false,
		"Protected probe character was removed or replaced before restoration"
	if characterIntact then
		restoreOk, restoreError = pcall(function()
			character:PivotTo(record.Pivot)
			root.AssemblyLinearVelocity = record.RootLinearVelocity
			root.AssemblyAngularVelocity = record.RootAngularVelocity
			root.Anchored = record.RootAnchored
			humanoid.BreakJointsOnDeath = record.BreakJointsOnDeath
			humanoid.Health = math.min(record.Health, humanoid.MaxHealth)
			humanoid:SetStateEnabled(Enum.HumanoidStateType.Dead, record.DeadEnabled)
		end)
	end
	if player and player.Parent == Players then
		-- SetAttribute(name, nil) removes the attribute, which restores an
		-- originally absent value instead of silently changing it to false.
		player:SetAttribute("InRound", record.InRound)
		player:SetAttribute("Escaped", record.Escaped)
	end
	record.KeepingAlive = false
	local connection = record.HealthConnection
	if connection then connection:Disconnect() end
	assert(restoreOk, "Failed to restore probe character state: " .. tostring(restoreError))
end

local function quiesceProtectedPlayer(Manager: {[string]: any}, record: {[string]: any})
	local player = record.Player
	if player and player.Parent == Players then
		-- Make any already-scheduled windup fail livingPlayer before removing the
		-- health guard. Otherwise the delayed attack callback can kill the restored
		-- character just after the probe returns.
		player:SetAttribute("InRound", false)
		player:SetAttribute("Escaped", true)
	end
	local tuning = Configuration.MallManager
	local deadline = os.clock() + math.max(
		tonumber(tuning.AttackWindupSeconds) or 0,
		tonumber(tuning.BlackoutAttackWindupSeconds) or 0) + .75
	local lastSnapshot = nil
	repeat
		lastSnapshot = Manager.GetSnapshot and Manager.GetSnapshot() or nil
		if not lastSnapshot
			or (lastSnapshot.Attacking ~= true and (lastSnapshot.TargetUserId or 0) == 0) then break end
		task.wait(.05)
	until os.clock() >= deadline
	assert(not lastSnapshot
		or (lastSnapshot.Attacking ~= true and (lastSnapshot.TargetUserId or 0) == 0),
		"Mall Manager attack/target did not quiesce before player-state restoration")
	task.wait(.1)
end

type CleanupStep = {Name: string, Run: () -> ()}
local function runCleanupSteps(steps: {CleanupStep})
	-- Cleanup is a best-effort transaction: one failed step must not prevent the
	-- remaining player, controller and scaffold state from being restored.
	local failures = {}
	for _, step in ipairs(steps) do
		local ok, cleanupError = pcall(step.Run)
		if not ok then
			table.insert(failures, step.Name .. ": " .. tostring(cleanupError))
		end
	end
	assert(#failures == 0, "Probe cleanup failed: " .. table.concat(failures, " | "))
end

local function probeScaffold()
	assertStudioProbe("Navigation probe scaffolding")
	local parts = {}
	local scaffold = {}
	function scaffold.add(name: string, cframe: CFrame, size: Vector3): BasePart
		local part = Instance.new("Part")
		part.Name = name
		part.Anchored = true
		part.CanCollide = true
		part.Transparency = .55
		part.Size = size
		part.CFrame = cframe
		part.Parent = workspace
		table.insert(parts, part)
		return part
	end
	function scaffold.clear()
		for _, part in ipairs(parts) do
			pcall(function() part:Destroy() end)
		end
		table.clear(parts)
	end
	return scaffold
end

local function sampleSeries(Manager: {[string]: any}, seconds: number, interval: number,
	extra: ((any) -> {[string]: any})?): {any}
	local series = {}
	local startedAt = os.clock()
	while os.clock() - startedAt < seconds do
		local snapshot = Manager.GetSnapshot()
		if snapshot then
			local target = if (snapshot.TargetUserId or 0) > 0
				then Players:GetPlayerByUserId(snapshot.TargetUserId) else nil
			local targetCharacter = target and target.Character
			local targetHumanoid = targetCharacter and targetCharacter:FindFirstChildOfClass("Humanoid")
			local sample = {
				T = os.clock() - startedAt,
				Position = snapshot.Position,
				State = snapshot.State,
				PathStatus = snapshot.PathStatus,
				MovementSpeed = snapshot.MovementSpeed,
				LastActualStepDistance = snapshot.LastActualStepDistance,
				WaypointIndex = snapshot.WaypointIndex,
				WaypointCount = snapshot.WaypointCount,
				StrategicIndex = snapshot.StrategicIndex,
				StrategicRebuildSerial = snapshot.StrategicRebuildSerial,
				StrategicGoalRevision = snapshot.StrategicGoalRevision,
				PathSwapSerial = snapshot.PathSwapSerial,
				GoalDistance = snapshot.GoalDistance,
				GenuineProgressSerial = snapshot.GenuineProgressSerial,
				LastGenuineProgressAgeSeconds = snapshot.LastGenuineProgressAgeSeconds,
				StuckRecoveries = snapshot.StuckRecoveries,
				RecoveryRepaths = snapshot.RecoveryRepaths,
				OverlapEscapeAttempts = snapshot.OverlapEscapeAttempts,
				OverlapEscapeSearches = snapshot.OverlapEscapeSearches,
				OverlapEscapeActive = snapshot.OverlapEscapeActive,
				ConsecutiveObstructions = snapshot.ConsecutiveObstructions,
				PathComputesLastSecond = snapshot.PathComputesLastSecond,
				PeakConcurrentPathComputes = snapshot.PeakConcurrentPathComputes,
				ProgressBestDistance = snapshot.ProgressBestDistance,
				ProgressCreditedDistance = snapshot.ProgressCreditedDistance,
				TargetUserId = snapshot.TargetUserId,
				Generation = snapshot.Generation,
				SpawnSerial = snapshot.SpawnSerial,
				AttackSerial = snapshot.AttackSerial,
				LastCaptureUserId = snapshot.LastCaptureUserId,
				TargetValid = target ~= nil
					and target.Parent == Players
					and target:GetAttribute("InRound") == true
					and target:GetAttribute("Escaped") ~= true
					and targetCharacter ~= nil
					and targetCharacter.Parent ~= nil
					and targetHumanoid ~= nil
					and targetHumanoid.Health > 0,
			}
			if extra then
				for key, value in pairs(extra(snapshot)) do sample[key] = value end
			end
			table.insert(series, sample)
		end
		task.wait(interval)
	end
	return series
end

local function seriesTravel(series: {any}): number
	local travelled = 0
	for index = 2, #series do
		travelled += planarDistance(series[index - 1].Position, series[index].Position)
	end
	return travelled
end

local function maxPerFrameStep(series: {any}): number
	local largest = 0
	for _, sample in ipairs(series) do
		largest = math.max(largest, sample.LastActualStepDistance or 0)
	end
	return largest
end

local function prepareStraightCorridorFixture(Manager: {[string]: any},
	centeredStart: boolean?): {[string]: any}
	local world = assert(workspace:FindFirstChild(Configuration.WorldName),
		"Navigation fixture requires the generated world")
	local corridors = assert(world:FindFirstChild("Corridors"),
		"Navigation fixture requires generated corridors")
	local candidates = {}
	for _, corridor in ipairs(corridors:GetChildren()) do
		if corridor:IsA("Model") and corridor:GetAttribute("Level3_ExitCorridor") ~= true then
			local corridorCFrame, corridorSize = corridor:GetBoundingBox()
			local horizontal = corridorSize.X > corridorSize.Z
			local half = (if horizontal then corridorSize.X else corridorSize.Z) * .5
			local span = math.min(30, half - 8)
			if span >= 18 then
				table.insert(candidates, {
					Model = corridor,
					CFrame = corridorCFrame,
					Axis = if horizontal then corridorCFrame.RightVector else corridorCFrame.LookVector,
					Span = span,
				})
			end
		end
	end
	table.sort(candidates, function(a, b) return a.Span > b.Span end)
	for _, candidate in ipairs(candidates) do
		local startPoint = if centeredStart then candidate.CFrame.Position
			else candidate.CFrame.Position - candidate.Axis * candidate.Span
		local endPoint = candidate.CFrame.Position + candidate.Axis * candidate.Span
		local prepared, snapshot = pcall(
			Manager.DebugPrepareStraightPatrol, startPoint, endPoint)
		if prepared and snapshot then
			return {
				Corridor = candidate.Model.Name,
				Start = startPoint,
				Destination = endPoint,
				Snapshot = snapshot,
			}
		end
	end
	error("No long corridor was accepted by the production sweep", 0)
end

local function prepareOpenRoomFixture(Manager: {[string]: any}): {[string]: any}
	local world = assert(workspace:FindFirstChild(Configuration.WorldName),
		"Navigation fixture requires the generated world")
	local rooms = assert(world:FindFirstChild("Rooms"),
		"Navigation fixture requires generated rooms")
	local candidates = {}
	for _, room in ipairs(rooms:GetChildren()) do
		if room:IsA("Model") and room:GetAttribute("Level3_RoomId") ~= "Exit" then
			local roomCFrame, roomSize = room:GetBoundingBox()
			table.insert(candidates, {
				Model = room,
				CFrame = roomCFrame,
				Area = roomSize.X * roomSize.Z,
			})
		end
	end
	table.sort(candidates, function(a, b) return a.Area > b.Area end)
	for _, candidate in ipairs(candidates) do
		for _, axis in ipairs({
			candidate.CFrame.RightVector,
			-candidate.CFrame.RightVector,
			candidate.CFrame.LookVector,
			-candidate.CFrame.LookVector,
		}) do
			local startPoint = candidate.CFrame.Position
			local endPoint = startPoint + axis * 18
			local prepared, snapshot = pcall(
				Manager.DebugPrepareStraightPatrol, startPoint, endPoint)
			if prepared and snapshot then
				return {
					Room = candidate.Model.Name,
					Start = startPoint,
					Destination = endPoint,
					Snapshot = snapshot,
				}
			end
		end
	end
	error("No open room centre was accepted by the production sweep", 0)
end

-- PROBE 1 — normal-speed movement where every single frame advances less than
-- PROGRESS_DISTANCE_EPSILON. Proves cumulative sub-epsilon gains are credited
-- and do not false-trigger STUCK_REPATH.
function TestSuite.ProbeSlowMovementProgress(Manager: {[string]: any},
	roomId: string, seconds: number?): {[string]: any}
	assertStudioProbe("ProbeSlowMovementProgress")
	assert(type(Manager) == "table" and Manager.DebugForcePatrolRoom
		and Manager.DebugPrepareStraightPatrol
		and Manager.DebugSetBlackout and Manager.GetSnapshot,
		"ProbeSlowMovementProgress requires the Mall Manager controller module")
	assert(type(roomId) == "string" and roomId ~= "",
		"ProbeSlowMovementProgress requires a fallback patrol room id")
	local tuning = Configuration.MallManager
	local before = assert(Manager.GetSnapshot(), "Mall Manager is not running")
	-- PatrolSpeed on the Normal profile is 4.5 studs/second, and
	-- MaximumMovementDeltaSeconds caps a frame at 0.05s, so a frame can advance
	-- at most 4.5 * 0.05 = 0.225 studs — guaranteed below the 0.25 credit
	-- epsilon regardless of frame rate. Players are made ineligible for the
	-- duration so the brain stays in PATROL instead of re-acquiring a chase.
	local restored = {}
	for _, player in ipairs(Players:GetPlayers()) do
		table.insert(restored, {Player = player, InRound = player:GetAttribute("InRound")})
		player:SetAttribute("InRound", false)
	end
	local function restorePlayers()
		for _, record in ipairs(restored) do
			local player = record.Player
			if player.Parent == Players then player:SetAttribute("InRound", record.InRound) end
		end
	end
	local fixtureCorridor: string? = nil
	local ok, series = pcall(function()
		Manager.DebugSetBlackout(false)
		local fixture = prepareStraightCorridorFixture(Manager, false)
		fixtureCorridor = fixture.Corridor
		task.wait(.25)
		return sampleSeries(Manager, seconds or 6, .1)
	end)
	restorePlayers()
	pcall(Manager.DebugSetBlackout, before.Blackout == true)
	if before.TargetUserId == 0
		and (before.State == "PATROL" or before.State == "PATROL_LISTEN")
		and type(before.StrategicGoalRoomId) == "string"
		and before.StrategicGoalRoomId ~= "" and before.StrategicGoalRoomId ~= "Exit" then
		pcall(Manager.DebugForcePatrolRoom, before.StrategicGoalRoomId)
	end
	-- Let the original live target become eligible again before the caller
	-- continues. DebugForcePatrolRoom is intentionally isolated to this probe;
	-- the production brain owns reacquisition after cleanup.
	task.wait(.35)
	if not ok then error(series, 0) end
	assert(#series >= 10, "Slow-movement probe collected too few samples")
	local first, last = series[1], series[#series]
	local travelled = seriesTravel(series)
	local largestStep = maxPerFrameStep(series)
	assert(travelled > 3,
		string.format("Manager did not actually move during the slow probe (%.2f studs)", travelled))
	assert(largestStep > 0 and largestStep < .25, string.format(
		"Slow probe is not exercising the sub-epsilon path: largest frame step %.3f studs",
		largestStep))
	assert(last.GenuineProgressSerial > first.GenuineProgressSerial, string.format(
		"Sub-epsilon movement was never credited as progress (%d -> %d)",
		first.GenuineProgressSerial, last.GenuineProgressSerial))
	assert(last.StuckRecoveries == first.StuckRecoveries, string.format(
		"A steadily moving Manager false-triggered %d stuck repath(s)",
		last.StuckRecoveries - first.StuckRecoveries))
	local worstGenuineAge = 0
	for _, sample in ipairs(series) do
		worstGenuineAge = math.max(worstGenuineAge, sample.LastGenuineProgressAgeSeconds or 0)
	end
	assert(worstGenuineAge <= tuning.StuckSeconds, string.format(
		"Credited progress lapsed for %.2fs while moving (StuckSeconds %.2f)",
		worstGenuineAge, tuning.StuckSeconds))
	return {
		FixtureCorridor = fixtureCorridor,
		Samples = #series,
		TravelledStuds = travelled,
		LargestFrameStep = largestStep,
		GenuineProgressEvents = last.GenuineProgressSerial - first.GenuineProgressSerial,
		StuckRecoveries = last.StuckRecoveries - first.StuckRecoveries,
		WorstGenuineProgressAge = worstGenuineAge,
		Series = series,
	}
end

-- PROBE 2 — total overlap with no initially usable escape direction. Proves the
-- escalation ladder is bounded, survives the obstruction repaths it triggers,
-- and still recovers once the enclosure is removed.
function TestSuite.ProbeTotalOverlapEscalation(Manager: {[string]: any},
	seconds: number?): {[string]: any}
	assertStudioProbe("ProbeTotalOverlapEscalation")
	assert(type(Manager) == "table" and Manager.GetSnapshot and Manager.DebugNavigationProbe
		and Manager.DebugForcePatrolRoom and Manager.DebugPrepareStraightPatrol
		and Manager.DebugSetMovementPaused and Manager.DebugSetBlackout,
		"ProbeTotalOverlapEscalation requires the Mall Manager controller module")
	local tuning = Configuration.MallManager
	local original = assert(Manager.GetSnapshot(), "Mall Manager is not running")
	local originalBlackout = original.Blackout == true
	local playerStates = {}
	for _, player in ipairs(Players:GetPlayers()) do
		table.insert(playerStates, {
			Player = player,
			InRound = player:GetAttribute("InRound"),
			Escaped = player:GetAttribute("Escaped"),
		})
		player:SetAttribute("InRound", false)
		player:SetAttribute("Escaped", true)
	end
	local scaffold = probeScaffold()
	local movementPaused = false
	local ok, result = pcall(function()
		-- Blackout owns a nearest-player target every think tick. Because this
		-- probe intentionally makes every player ineligible, use normal patrol so
		-- DebugForcePatrolRoom remains the movement authority during the trap.
		Manager.DebugSetBlackout(false)
		-- Begin at the centre of a production-clear room. Corridor walls enter the
		-- escape probe volume and make an otherwise symmetric synthetic minimum
		-- depend on test order and the chosen goal direction.
		local fixture = prepareOpenRoomFixture(Manager)
		local start = assert(fixture.Snapshot, "Overlap fixture did not return a live snapshot")
		local centre = Vector3.new(start.Position.X, start.Position.Y, start.Position.Z)
		Manager.DebugSetMovementPaused(true)
		movementPaused = true
		-- Give the released Manager a deterministic, distant goal. Live players
		-- are temporarily ineligible so target reacquisition cannot replace it.
		local world = assert(workspace:FindFirstChild(Configuration.WorldName), "no world")
		local rooms = assert(world:FindFirstChild("Rooms"), "Generated world has no rooms")
		local recoveryRoomId, recoveryDistance = nil, 0
		for _, room in ipairs(rooms:GetChildren()) do
			local roomId = room:GetAttribute("Level3_RoomId")
			if type(roomId) == "string" and roomId ~= "Exit" then
				local roomCFrame = room:GetBoundingBox()
				local roomPoint = Vector3.new(roomCFrame.Position.X, centre.Y, roomCFrame.Position.Z)
				local separation = planarDistance(centre, roomPoint)
				if separation > recoveryDistance
					and Manager.DebugNavigationProbe(roomPoint).VolumeFits then
					recoveryRoomId, recoveryDistance = roomId, separation
				end
			end
		end
		assert(recoveryRoomId and recoveryDistance > 20,
			"Overlap probe found no distant, clear patrol destination")
		-- A blocker-count LOCAL MINIMUM, not a plain shell. overlapEscapeDirection
		-- accepts any candidate that reduces the blocker count, so an evenly
		-- spaced ring is escapable by construction (measured: 12 at the centre,
		-- 7 at every 3.5-stud probe point). Instead: a sparse core just inside
		-- the sweep box so the Manager is genuinely overlapping, plus a dense
		-- annulus just outside it so EVERY probe direction pulls in strictly
		-- more blockers. No candidate direction is usable, which is the only
		-- way the exhaustion branch can be reached.
		for index, lateral in ipairs({-.45, .45}) do
			-- Bias both core blockers east so production's away vector is exactly
			-- west. The assertion below can then evaluate the exact same candidate
			-- basis instead of assuming a global axis for a numerically symmetric sum.
			local coreCentre = centre + Vector3.new(4.9, 3, lateral)
			scaffold.add("ClaudeProbeCore" .. index, CFrame.new(coreCentre),
				Vector3.new(1.5, PROBE_BLOCK_HEIGHT, 1.5))
		end
		for index = 1, 28 do
			local angle = math.rad(index * (360 / 28))
			local direction = Vector3.new(math.cos(angle), 0, math.sin(angle))
			local ringCentre = centre + direction * PROBE_RING_RADIUS + Vector3.new(0, 3, 0)
			scaffold.add("ClaudeProbeAnnulus" .. index, CFrame.new(ringCentre),
				Vector3.new(2.2, PROBE_BLOCK_HEIGHT, 2.2))
		end
		task.wait(.2)
		local enclosed = Manager.DebugNavigationProbe(centre)
		assert(enclosed.PhysicalBlockers == 2 and enclosed.FurnitureBlockers == 0
			and not enclosed.VolumeFits,
			string.format("Overlap fixture expected only two core blockers, got %d physical/%d furniture",
				enclosed.PhysicalBlockers, enclosed.FurnitureBlockers))
		-- Prove the trap really is a local minimum before trusting the result.
		local worstProbe = math.huge
		local productionAway = -Vector3.xAxis
		for _, degrees in ipairs({0, 20, -20, 45, -45, 75, -75, 110, -110, 180}) do
			local direction = CFrame.fromAxisAngle(Vector3.yAxis,
				math.rad(degrees)):VectorToWorldSpace(productionAway)
			worstProbe = math.min(worstProbe,
				Manager.DebugNavigationProbe(centre + direction * tuning.OverlapEscapeProbeDistance)
					.TotalBlockers)
		end
		assert(worstProbe > enclosed.TotalBlockers, string.format(
			"Overlap trap is escapable: centre has %d blockers but some direction has only %d",
			enclosed.TotalBlockers, worstProbe))
		assert(Manager.DebugForcePatrolRoom(recoveryRoomId),
			"Manager did not accept the overlap recovery patrol goal")
		local held = assert(Manager.GetSnapshot(), "Manager vanished before overlap release")
		assert(planarDistance(held.Position, centre) <= .05,
			"Manager moved while the overlap fixture was being assembled")
		Manager.DebugSetMovementPaused(false)
		movementPaused = false
		local trapped = sampleSeries(Manager, seconds or 6, .15)
		assert(#trapped >= 8, "Overlap probe collected too few trapped samples")
		local maxLadder, maxSearches, sawRefusal = 0, 0, false
		local statuses = {}
		for _, sample in ipairs(trapped) do
			maxLadder = math.max(maxLadder, sample.OverlapEscapeAttempts or 0)
			maxSearches = math.max(maxSearches, sample.OverlapEscapeSearches or 0)
			if (sample.OverlapEscapeAttempts or 0) > tuning.ObstructionRecoveryAttempts then
				sawRefusal = true
			end
			statuses[sample.PathStatus] = (statuses[sample.PathStatus] or 0) + 1
		end
		-- The ladder must actually reach the exhausted state (the branch that
		-- was unreachable before) and must stay clamped there.
		assert(sawRefusal, string.format(
			"Overlap escalation never reached exhaustion (ladder peaked at %d, cap %d)",
			maxLadder, tuning.ObstructionRecoveryAttempts))
		assert(maxLadder <= tuning.ObstructionRecoveryAttempts + 1, string.format(
			"Overlap escalation ladder ran away to %d", maxLadder))
		local trappedLast = trapped[#trapped]
		local trappedFirst = trapped[1]
		local windows = math.max(1, trappedLast.T - trappedFirst.T) / tuning.AvoidanceCommitSeconds
		local searchDelta = (trappedLast.OverlapEscapeSearches or 0)
			- (trappedFirst.OverlapEscapeSearches or 0)
		-- Rate-limited retries: at most one new direction search per commit
		-- window once exhausted, plus the initial ladder climb.
		assert(searchDelta <= math.ceil(windows) + 2,
			string.format("Overlap retries were not rate limited (%d searches over %.1fs)",
				searchDelta, trappedLast.T - trappedFirst.T))
		-- Recovery: remove the shell and prove it escapes and resumes.
		scaffold.clear()
		task.wait(.2)
		local freed = sampleSeries(Manager, 4, .15)
		assert(#freed >= 5, "Overlap probe collected too few recovery samples")
		local freedLast = freed[#freed]
		local escapedDistance = planarDistance(freed[1].Position, freedLast.Position)
		local cleared = Manager.DebugNavigationProbe(freedLast.Position)
		assert(freedLast.OverlapEscapeAttempts == 0 and cleared.VolumeFits, string.format(
			"Manager never left the overlap after the shell was removed (ladder %d, fits %s)",
			freedLast.OverlapEscapeAttempts, tostring(cleared.VolumeFits)))
		assert(escapedDistance > 1
			and freedLast.GenuineProgressSerial > trappedLast.GenuineProgressSerial,
			string.format(
			"Manager did not resume moving after recovery (%.2f studs, progress %d -> %d)",
			escapedDistance, trappedLast.GenuineProgressSerial, freedLast.GenuineProgressSerial))
		local statusList = {}
		for status, count in pairs(statuses) do
			table.insert(statusList, status .. "x" .. count)
		end
		table.sort(statusList)
		return {
			TrappedSamples = #trapped,
			RecoverySamples = #freed,
			LadderPeak = maxLadder,
			LadderCap = tuning.ObstructionRecoveryAttempts + 1,
			SearchesWhileTrapped = searchDelta,
			ReachedExhaustion = sawRefusal,
			TrappedStatuses = table.concat(statusList, ", "),
			RecoveryTravelStuds = escapedDistance,
			RecoveryLadder = freedLast.OverlapEscapeAttempts,
			RecoveryRoomId = recoveryRoomId,
			RecoveryGoalDistance = recoveryDistance,
			FixtureRoom = fixture.Room,
			TrappedSeries = trapped,
			RecoverySeries = freed,
		}
	end)
	if movementPaused then pcall(Manager.DebugSetMovementPaused, false) end
	pcall(Manager.DebugSetBlackout, originalBlackout)
	scaffold.clear()
	for _, record in ipairs(playerStates) do
		if record.Player.Parent == Players then
			record.Player:SetAttribute("InRound", record.InRound)
			record.Player:SetAttribute("Escaped", record.Escaped)
		end
	end
	if not ok then error(result, 0) end
	return result
end

-- PROBE 3 — a centreline projection blocked between the original PFS waypoint
-- and its projection. Proves the movement-facing contract keeps the original
-- point instead of stepping onto a blocked centreline.
function TestSuite.ProbeBlockedProjection(Manager: {[string]: any}): {[string]: any}
	assertStudioProbe("ProbeBlockedProjection")
	assert(type(Manager) == "table" and Manager.DebugProjectWaypoint
		and Manager.DebugMovementProjection,
		"ProbeBlockedProjection requires the Mall Manager controller module")
	local world = assert(workspace:FindFirstChild(Configuration.WorldName),
		"ProbeBlockedProjection requires the live generated world")
	local corridors = assert(world:FindFirstChild("Corridors"), "Generated world has no corridors")
	local tuning = Configuration.MallManager
	local scaffold = probeScaffold()
	local ok, result = pcall(function()
		-- Find an accepted centreline projection plus a clear current position at
		-- least 24 studs down the same corridor. That separation lets the blocker
		-- isolate the approach segment without touching either endpoint volume.
		local best = nil
		for _, corridorModel in ipairs(corridors:GetChildren()) do
			if corridorModel:GetAttribute("Level3_ExitCorridor") ~= true then
				local corridorCFrame, corridorSize = corridorModel:GetBoundingBox()
				local horizontal = corridorSize.X > corridorSize.Z
				local half = (if horizontal then corridorSize.X else corridorSize.Z) * .5
				local axis = if horizontal then corridorCFrame.RightVector else corridorCFrame.LookVector
				for _, along in ipairs({-half - 8, -half + 2, 0, half - 2, half + 8}) do
					for step = 1, 14 do
						for _, sign in ipairs({1, -1}) do
							local offset = step * .5 * sign
							local candidate = if horizontal
								then Vector3.new(corridorCFrame.Position.X + along,
									corridorCFrame.Position.Y, corridorCFrame.Position.Z + offset)
								else Vector3.new(corridorCFrame.Position.X + offset,
									corridorCFrame.Position.Y, corridorCFrame.Position.Z + along)
							local report = Manager.DebugProjectWaypoint(candidate)
							if report.Projected and not report.RetainedOriginal then
								for _, distance in ipairs({36, 32, 28, 24}) do
									for _, direction in ipairs({1, -1}) do
										local current = report.UncheckedProjection + axis * distance * direction
										local localCurrent = corridorCFrame:PointToObjectSpace(current)
										local withinLength = math.abs(if horizontal
											then localCurrent.X else localCurrent.Z) <= half + 1
										local baseline = Manager.DebugMovementProjection(current, candidate)
										if withinLength and baseline.UsedProjection
											and not baseline.RetainedOriginal
											and baseline.CurrentEndpointFits
											and baseline.ProjectionEndpointFits
											and baseline.ApproachSegmentClear
											and (not best or distance > best.Distance) then
											best = {
												Distance = distance,
												Current = current,
												Original = report.Original,
												Projection = report.UncheckedProjection,
												Corridor = corridorModel.Name,
											}
										end
									end
								end
							end
						end
					end
				end
			end
		end
		assert(best, "Could not find a clear 24-stud movement projection fixture")
		local current, original, projection = best.Current, best.Original, best.Projection
		local approach = Vector3.new(projection.X - current.X, 0, projection.Z - current.Z)
		assert(approach.Magnitude >= 24, "Projection fixture does not isolate its endpoints")
		local approachUnit = approach.Unit
		local blockerCentre = current + approach * .5
		scaffold.add("ClaudeProbeProjectionBlocker",
			CFrame.lookAt(Vector3.new(blockerCentre.X, blockerCentre.Y + PROBE_BLOCK_HEIGHT * .5, blockerCentre.Z),
				Vector3.new(blockerCentre.X, blockerCentre.Y + PROBE_BLOCK_HEIGHT * .5, blockerCentre.Z)
					+ approachUnit),
			Vector3.new(tuning.SweepRadius * 2 + 2, PROBE_BLOCK_HEIGHT, .8))
		task.wait(.2)
		local blocked = Manager.DebugMovementProjection(current, original)
		assert(blocked.UsedProjection,
			"Probe waypoint stopped qualifying for centreline projection")
		assert(blocked.CurrentEndpointFits and blocked.ProjectionEndpointFits,
			"Approach blocker contaminated an endpoint volume")
		assert(not blocked.ApproachSegmentClear,
			"Probe did not actually block the current-to-projection approach segment")
		assert(blocked.RetainedOriginal, string.format(
			"Blocked movement approach still accepted the projection (approachClear=%s)",
			tostring(blocked.ApproachSegmentClear)))
		scaffold.clear()
		task.wait(.2)
		local restored = Manager.DebugMovementProjection(current, original)
		assert(restored.UsedProjection and restored.ApproachSegmentClear
			and not restored.RetainedOriginal,
			"Movement projection did not resume once the approach blocker was removed")
		return {
			Corridor = best.Corridor,
			CurrentPosition = current,
			OriginalWaypoint = original,
			Projection = projection,
			ApproachDistance = approach.Magnitude,
			SweepRadius = tuning.SweepRadius,
			UsedProjection = blocked.UsedProjection,
			BlockedRetainedOriginal = blocked.RetainedOriginal,
			BlockedApproachSegmentClear = blocked.ApproachSegmentClear,
			CurrentEndpointFits = blocked.CurrentEndpointFits,
			ProjectionEndpointFits = blocked.ProjectionEndpointFits,
			RestoredProjection = not restored.RetainedOriginal,
		}
	end)
	scaffold.clear()
	if not ok then error(result, 0) end
	return result
end

-- A moving target may rebase the final strategic point, but that target motion
-- is not Manager motion. Freeze only the rig transform while leaving the real
-- brain, route and progress tracker live, then move one fixed target twice
-- inside the same room and prove no genuine-progress credit is minted.
function TestSuite.ProbeMovingTargetProgressIsolation(Manager: {[string]: any},
	player: Player): {[string]: any}
	assertStudioProbe("ProbeMovingTargetProgressIsolation")
	assert(type(Manager) == "table" and Manager.GetSnapshot
		and Manager.DebugNavigationProbe and Manager.DebugSetBlackout
		and Manager.DebugSetMovementPaused,
		"ProbeMovingTargetProgressIsolation requires the Mall Manager controller module")
	local original = assert(Manager.GetSnapshot(), "Mall Manager is not running")
	local originalBlackout = original.Blackout == true
	local protected = protectPlayer(player)
	local otherPlayers = {}
	for _, candidate in ipairs(Players:GetPlayers()) do
		if candidate ~= player then
			table.insert(otherPlayers, {
				Player = candidate,
				InRound = candidate:GetAttribute("InRound"),
				Escaped = candidate:GetAttribute("Escaped"),
			})
			candidate:SetAttribute("InRound", false)
			candidate:SetAttribute("Escaped", true)
		end
	end
	local paused = false
	local ok, result = pcall(function()
		local world = assert(workspace:FindFirstChild(Configuration.WorldName),
			"Moving-target probe requires the generated world")
		local rooms = assert(world:FindFirstChild("Rooms"),
			"Moving-target probe requires generated rooms")
		local fixture = nil
		Manager.DebugSetMovementPaused(true)
		paused = true
		-- Build a same-room, production-sweep-approved straight fixture. Thirty
		-- studs remains inside BlackoutDirectPathRange, while moving the target ten
		-- studs toward the frozen Manager would exceed the progress epsilon under
		-- the old constant final-goal key.
		for _, room in ipairs(rooms:GetChildren()) do
			if room:IsA("Model") and room:GetAttribute("Level3_RoomId") ~= "Exit" then
				local roomCFrame = room:GetBoundingBox()
				local start = roomCFrame.Position
				for _, axis in ipairs({
					roomCFrame.RightVector, -roomCFrame.RightVector,
					roomCFrame.LookVector, -roomCFrame.LookVector,
				}) do
					local nearTarget = start + axis * 20
					local farTarget = start + axis * 30
					if Manager.DebugNavigationProbe(start).VolumeFits
						and Manager.DebugNavigationProbe(nearTarget).VolumeFits
						and Manager.DebugNavigationProbe(farTarget).VolumeFits then
						local prepared = pcall(Manager.DebugPrepareStraightPatrol, start, farTarget)
						if prepared then
							fixture = {
								Room = room.Name,
								Start = start,
								NearTarget = nearTarget,
								FarTarget = farTarget,
							}
							break
						end
					end
				end
				if fixture then break end
			end
		end
		assert(fixture, "Moving-target probe found no clear 30-stud direct-goal fixture")

		Manager.DebugSetBlackout(true)
		protected.Character:PivotTo(CFrame.new(Vector3.new(
			fixture.FarTarget.X, protected.Root.Position.Y, fixture.FarTarget.Z)))
		local deadline = os.clock() + 2
		local acquired = nil
		repeat
			task.wait(.05)
			acquired = Manager.GetSnapshot()
		until acquired and acquired.State == "CHASE"
			and acquired.TargetUserId == player.UserId
			and acquired.StrategicIndex > acquired.StrategicPointCount
			and type(acquired.ProgressObjectiveKey) == "string"
			and string.sub(acquired.ProgressObjectiveKey, 1, 5) == "goal:"
			or os.clock() >= deadline
		assert(acquired and acquired.State == "CHASE" and acquired.TargetUserId == player.UserId,
			"Moving-target probe did not acquire its isolated player")
		assert(acquired.StrategicIndex > acquired.StrategicPointCount
			and type(acquired.ProgressObjectiveKey) == "string"
			and string.sub(acquired.ProgressObjectiveKey, 1, 5) == "goal:",
			"Moving-target probe did not enter the direct-goal progress branch")
		task.wait(.1)
		local baseline = assert(Manager.GetSnapshot(), "Manager vanished before target rebase")
		protected.Character:PivotTo(CFrame.new(Vector3.new(
			fixture.NearTarget.X, protected.Root.Position.Y, fixture.NearTarget.Z)))
		task.wait(.4)
		local movedTarget = assert(Manager.GetSnapshot(), "Manager vanished after target rebase")
		local managerDisplacement = planarDistance(baseline.Position, movedTarget.Position)
		assert(movedTarget.StrategicGoalRevision > baseline.StrategicGoalRevision,
			"Moving target did not revise the active strategic goal")
		assert(managerDisplacement <= .05,
			string.format("Paused Manager moved %.3f studs during target-only rebase",
				managerDisplacement))
		assert(movedTarget.StrategicIndex > movedTarget.StrategicPointCount
			and type(movedTarget.ProgressObjectiveKey) == "string"
			and string.sub(movedTarget.ProgressObjectiveKey, 1, 5) == "goal:",
			"Target rebase left the direct-goal progress branch")
		assert(movedTarget.ProgressObjectiveKey ~= baseline.ProgressObjectiveKey,
			"Target rebase did not renew the final-goal progress objective key")
		assert(movedTarget.GenuineProgressSerial == baseline.GenuineProgressSerial,
			string.format("Target-only movement minted genuine progress (%d -> %d)",
				baseline.GenuineProgressSerial, movedTarget.GenuineProgressSerial))
		return {
			FixtureRoom = fixture.Room,
			TargetTravelStuds = planarDistance(fixture.FarTarget, fixture.NearTarget),
			ManagerTravelStuds = managerDisplacement,
			BaselineProgressKey = baseline.ProgressObjectiveKey,
			MovedProgressKey = movedTarget.ProgressObjectiveKey,
			GoalRevisionDelta = movedTarget.StrategicGoalRevision
				- baseline.StrategicGoalRevision,
			GenuineProgressDelta = movedTarget.GenuineProgressSerial
				- baseline.GenuineProgressSerial,
		}
	end)
	local cleanupOk, cleanupError = pcall(function()
		runCleanupSteps({
			{Name = "resume Manager movement", Run = function()
				if paused then Manager.DebugSetMovementPaused(false) end
			end},
			{Name = "quiesce Manager target", Run = function()
				quiesceProtectedPlayer(Manager, protected)
			end},
			{Name = "restore blackout profile", Run = function()
				Manager.DebugSetBlackout(originalBlackout)
			end},
			{Name = "restore other player eligibility", Run = function()
				for _, record in ipairs(otherPlayers) do
					if record.Player.Parent == Players then
						record.Player:SetAttribute("InRound", record.InRound)
						record.Player:SetAttribute("Escaped", record.Escaped)
					end
				end
			end},
			{Name = "restore protected player", Run = function()
				restoreProtectedPlayer(protected)
			end},
		})
	end)
	if not cleanupOk then
		if not ok then
			error(tostring(result) .. "\nMoving-target cleanup also failed: "
				.. tostring(cleanupError), 0)
		end
		error(cleanupError, 0)
	end
	if not ok then error(result, 0) end
	return result
end

-- PROBE 4 — an exposed player hugging a wall. Proves the Manager closes to a
-- range that permits its attack, and that a wall between the two still refuses
-- the attack.
function TestSuite.ProbeWallHugAttack(Manager: {[string]: any}, player: Player,
	seconds: number?): {[string]: any}
	assertStudioProbe("ProbeWallHugAttack")
	assert(type(Manager) == "table" and Manager.DebugAttackProbe and Manager.GetSnapshot
		and Manager.DebugSetBlackout and Manager.DebugPrepareStraightPatrol,
		"ProbeWallHugAttack requires the Mall Manager controller module")
	local tuning = Configuration.MallManager
	local original = assert(Manager.GetSnapshot(), "Mall Manager is not running")
	local originalBlackout = original.Blackout == true
	local protected = protectPlayer(player)
	local character = protected.Character
	local root = assert(character:FindFirstChild("HumanoidRootPart"), "Character has no root")
	local otherPlayers = {}
	for _, candidate in ipairs(Players:GetPlayers()) do
		if candidate ~= player then
			table.insert(otherPlayers, {
				Player = candidate,
				InRound = candidate:GetAttribute("InRound"),
				Escaped = candidate:GetAttribute("Escaped"),
			})
			candidate:SetAttribute("InRound", false)
			candidate:SetAttribute("Escaped", true)
		end
	end
	local scaffold = probeScaffold()
	local ok, result = pcall(function()
		-- Isolate target ownership from LOS while the fixture is being placed.
		-- The assertions below still use the real range/LOS attack gate; blackout
		-- only guarantees this sole eligible player remains the chase target.
		Manager.DebugSetBlackout(true)
		local start = assert(Manager.GetSnapshot(), "Mall Manager is not running")
		local startingAttackSerial = Manager.DebugAttackProbe(player).AttackSerial
		-- Press the player against an authored structural room wall. Selecting
		-- the part by ancestry/name avoids a ray accidentally treating furniture
		-- or a temporary test part as the wall under test.
		local world = assert(workspace:FindFirstChild(Configuration.WorldName), "no world")
		local rooms = assert(world:FindFirstChild("Rooms"), "no rooms")
		local hostRoom, hostWall, inward, hugPoint = nil, nil, nil, nil
		local wallCandidates = {}
		for _, roomModel in ipairs(rooms:GetChildren()) do
			if roomModel:IsA("Model") and roomModel:GetAttribute("Level3_RoomId") ~= "Exit" then
				local roomCFrame = roomModel:GetBoundingBox()
				for _, candidate in ipairs(roomModel:GetDescendants()) do
					if candidate:IsA("BasePart") and candidate.CanCollide
						and candidate.Size.Y >= 6
						and string.find(candidate.Name, " Wall", 1, true) then
						local thinXAxis = candidate.Size.X < candidate.Size.Z
						local candidateInward = if thinXAxis
							then candidate.CFrame.RightVector else candidate.CFrame.LookVector
						if (roomCFrame.Position - candidate.Position):Dot(candidateInward) < 0 then
							candidateInward = -candidateInward
						end
						local halfThickness = (if thinXAxis
							then candidate.Size.X else candidate.Size.Z) * .5
						local face = candidate.Position + candidateInward * halfThickness
						local candidateHug = face + candidateInward * 1.6
						-- A real attack point just inside the room must fit the Manager's
						-- full local sweep. Prefer a wall whose interior is already on the
						-- Manager's side, instead of an arbitrary exterior wall across the room.
						local attackPoint = face + candidateInward * (tuning.SweepRadius + .35)
						local groundedAttackPoint = Vector3.new(
							attackPoint.X, start.Position.Y, attackPoint.Z)
						if Manager.DebugNavigationProbe(groundedAttackPoint).VolumeFits then
							local sameSide = (start.Position - face):Dot(candidateInward) >= 0
							table.insert(wallCandidates, {
								Room = roomModel,
								Wall = candidate,
								Inward = candidateInward,
								HugPoint = candidateHug,
								AttackPoint = groundedAttackPoint,
								Score = planarDistance(start.Position, groundedAttackPoint)
									+ (if sameSide then 0 else 1000),
							})
						end
					end
				end
			end
		end
		table.sort(wallCandidates, function(a, b) return a.Score < b.Score end)
		for _, candidate in ipairs(wallCandidates) do
			for _, approachDistance in ipairs({26, 20, 14}) do
				local approachStart = candidate.AttackPoint
					+ candidate.Inward * approachDistance
				local prepared = pcall(Manager.DebugPrepareStraightPatrol,
					approachStart, candidate.AttackPoint)
				if prepared then
					hostRoom, hostWall = candidate.Room, candidate.Wall
					inward, hugPoint = candidate.Inward, candidate.HugPoint
					break
				end
			end
			if hostWall then break end
		end
		assert(hostRoom and hostWall and inward and hugPoint,
			"no authored wall provided a clear same-room attack approach")
		assert(hostWall:IsDescendantOf(hostRoom), "wall-hug fixture is not owned by its room")
		character:PivotTo(CFrame.new(Vector3.new(hugPoint.X, root.Position.Y, hugPoint.Z)))
		task.wait(.5)
		local acquired = assert(Manager.GetSnapshot(), "Manager vanished at wall-hug target")
		assert(acquired.TargetUserId == player.UserId,
			"Wall-hug probe did not isolate the designated player as its target")
		local series = sampleSeries(Manager, seconds or 10, .2, function()
			local probe = Manager.DebugAttackProbe(player)
			return {
				AttackDistance = probe.Distance,
				WithinAttackRange = probe.WithinAttackRange,
				WithinConfirmRange = probe.WithinConfirmRange,
				LineClearAtConfirmRange = probe.LineClearAtConfirmRange,
				WouldInitiate = probe.WouldInitiate,
				GoalResolvedAway = probe.GoalResolvedAwayFromTarget,
				AttackSerial = probe.AttackSerial,
				TargetUserId = probe.TargetUserId,
				LastCaptureUserId = probe.LastCaptureUserId,
			}
		end)
		assert(#series >= 8, "Wall-hug probe collected too few samples")
		local closest, everInitiated, everInRange = math.huge, false, false
		local greatestAttackSerial = startingAttackSerial
		local completedCaptureUserId = 0
		for _, sample in ipairs(series) do
			closest = math.min(closest, sample.AttackDistance or math.huge)
			if sample.WouldInitiate then everInitiated = true end
			if sample.WithinConfirmRange then everInRange = true end
			if (sample.AttackSerial or 0) > greatestAttackSerial then
				greatestAttackSerial = sample.AttackSerial
				completedCaptureUserId = sample.LastCaptureUserId or 0
			end
		end
		local finalSample = series[#series]
		assert(closest <= tuning.AttackConfirmRange, string.format(
			"Wall-hugging player stayed uncatchable: closest approach %.2f studs (confirm range %.2f)",
			closest, tuning.AttackConfirmRange))
		assert(everInRange and everInitiated, string.format(
			"Manager reached %.2f studs but never satisfied its attack gate", closest))
		assert(greatestAttackSerial > startingAttackSerial, string.format(
			"Wall-hug gate looked open but no real attack completed (serial %d -> %d)",
			startingAttackSerial, greatestAttackSerial))
		assert(completedCaptureUserId == player.UserId, string.format(
			"Attack serial advanced for the wrong player (captured %s, expected %s)",
			tostring(completedCaptureUserId), tostring(player.UserId)))
		-- Now prove the wall still refuses attacks through it: interpose a slab
		-- at a controlled, open, in-range position and re-run the real gate.
		local live = assert(Manager.GetSnapshot(), "Manager vanished mid-probe")
		local openPoint = live.Position + inward * (tuning.AttackRange - .35)
		character:PivotTo(CFrame.new(Vector3.new(openPoint.X, root.Position.Y, openPoint.Z)))
		task.wait(.15)
		-- Rebase once after the teleport, then perform the open/walled/restored
		-- ray checks synchronously in one server turn so Manager movement cannot
		-- turn an out-of-range result into a false LOS success.
		live = assert(Manager.GetSnapshot(), "Manager vanished before controlled LOS fixture")
		openPoint = live.Position + inward * (tuning.AttackRange - .35)
		character:PivotTo(CFrame.new(Vector3.new(openPoint.X, root.Position.Y, openPoint.Z)))
		local openBeforeWall = Manager.DebugAttackProbe(player)
		assert(openBeforeWall.WithinConfirmRange
			and openBeforeWall.LineClearAtConfirmRange and openBeforeWall.WouldInitiate,
			"Controlled unwalled attack fixture did not satisfy the real gate")
		local toPlayer = Vector3.new(root.Position.X - live.Position.X, 0, root.Position.Z - live.Position.Z)
		assert(toPlayer.Magnitude > 2, "Controlled attack fixture is too short for a separating wall")
		local midpoint = Vector3.new(live.Position.X, (live.Position.Y + root.Position.Y) * .5,
			live.Position.Z)
			+ toPlayer.Unit * (toPlayer.Magnitude * .5)
		scaffold.add("ClaudeProbeAttackWall",
			CFrame.lookAt(midpoint, midpoint + toPlayer.Unit),
			Vector3.new(14, 12, 1.5))
		local walled = Manager.DebugAttackProbe(player)
		scaffold.clear()
		local unwalled = Manager.DebugAttackProbe(player)
		assert(walled.WithinConfirmRange
			and not walled.LineClearAtConfirmRange and not walled.WouldInitiate, string.format(
			"A wall between Manager and player did not block the attack (distance %.2f)",
			walled.Distance))
		assert(unwalled.WithinConfirmRange
			and unwalled.LineClearAtConfirmRange and unwalled.WouldInitiate, string.format(
			"Removing the test wall did not restore the open attack gate (distance %.2f)",
			unwalled.Distance))
		return {
			Samples = #series,
			ClosestApproach = closest,
			AttackRange = tuning.AttackRange,
			AttackConfirmRange = tuning.AttackConfirmRange,
			EverWithinConfirmRange = everInRange,
			EverWouldInitiate = everInitiated,
			StartingAttackSerial = startingAttackSerial,
			CompletedAttackSerial = greatestAttackSerial,
			CompletedCaptureUserId = completedCaptureUserId,
			GoalResolvedAway = finalSample.GoalResolvedAway,
			WalledLineClear = walled.LineClearAtConfirmRange,
			WalledWouldInitiate = walled.WouldInitiate,
			WalledDistance = walled.Distance,
			UnwalledLineClear = unwalled.LineClearAtConfirmRange,
			UnwalledWouldInitiate = unwalled.WouldInitiate,
			HostRoom = hostRoom.Name,
			HostWall = hostWall:GetFullName(),
			Series = series,
		}
	end)
	local cleanupOk, cleanupError = pcall(function()
		runCleanupSteps({
			{Name = "remove wall-hug scaffold", Run = scaffold.clear},
			{Name = "quiesce Manager target", Run = function()
				quiesceProtectedPlayer(Manager, protected)
			end},
			{Name = "restore blackout profile", Run = function()
				Manager.DebugSetBlackout(originalBlackout)
			end},
			{Name = "restore protected player", Run = function()
				restoreProtectedPlayer(protected)
			end},
			{Name = "restore other player eligibility", Run = function()
				for _, record in ipairs(otherPlayers) do
					if record.Player.Parent == Players then
						record.Player:SetAttribute("InRound", record.InRound)
						record.Player:SetAttribute("Escaped", record.Escaped)
					end
				end
			end},
		})
	end)
	if not cleanupOk then
		if not ok then
			error(tostring(result) .. "\nWall-hug cleanup also failed: "
				.. tostring(cleanupError), 0)
		end
		error(cleanupError, 0)
	end
	if not ok then error(result, 0) end
	return result
end

-- PROBE 5 — a live chase must make real forward progress over time. This is the
-- time-series replacement for the old single-snapshot age assertion: a recovery
-- timestamp alone cannot satisfy it, because position and route indices are
-- sampled directly.
function TestSuite.ProbeChaseForwardProgress(Manager: {[string]: any}, player: Player,
	seconds: number?): {[string]: any}
	assertStudioProbe("ProbeChaseForwardProgress")
	assert(type(Manager) == "table" and Manager.GetSnapshot and Manager.DebugNavigationProbe
		and Manager.DebugSetBlackout,
		"ProbeChaseForwardProgress requires the Mall Manager controller module")
	local tuning = Configuration.MallManager
	local original = assert(Manager.GetSnapshot(), "Mall Manager is not running")
	local originalBlackout = original.Blackout == true
	local protected = protectPlayer(player)
	local otherPlayers = {}
	for _, candidate in ipairs(Players:GetPlayers()) do
		if candidate ~= player then
			table.insert(otherPlayers, {Player = candidate, InRound = candidate:GetAttribute("InRound")})
			candidate:SetAttribute("InRound", false)
		end
	end
	local function cleanup()
		runCleanupSteps({
			{Name = "quiesce Manager target", Run = function()
				quiesceProtectedPlayer(Manager, protected)
			end},
			{Name = "restore blackout profile", Run = function()
				Manager.DebugSetBlackout(originalBlackout)
			end},
			{Name = "restore other player eligibility", Run = function()
				for _, record in ipairs(otherPlayers) do
					if record.Player.Parent == Players then
						record.Player:SetAttribute("InRound", record.InRound)
					end
				end
			end},
			{Name = "restore protected player", Run = function()
				restoreProtectedPlayer(protected)
			end},
		})
	end
	local ok, result = pcall(function()
		-- Blackout has a deterministic nearest-player target contract independent
		-- of LOS. With every other player ineligible, this keeps the fixed target
		-- in CHASE for the whole high-speed pathfinding probe instead of naturally
		-- degrading to TRACKING when it is placed several rooms away.
		Manager.DebugSetBlackout(true)
		local start = assert(Manager.GetSnapshot(), "Mall Manager is not running")
		local world = assert(workspace:FindFirstChild(Configuration.WorldName),
			"Chase probe requires the live generated world")
		local rooms = assert(world:FindFirstChild("Rooms"), "Generated world has no rooms")
		local root = protected.Root :: BasePart
		local destination, startingSeparation = nil, 0
		for _, room in ipairs(rooms:GetChildren()) do
			if room:GetAttribute("Level3_RoomId") ~= "Exit" then
				local roomCFrame = room:GetBoundingBox()
				local point = Vector3.new(roomCFrame.Position.X, root.Position.Y, roomCFrame.Position.Z)
				local separation = planarDistance(start.Position, point)
				if separation > startingSeparation
					and Manager.DebugNavigationProbe(point).VolumeFits then
					destination, startingSeparation = point, separation
				end
			end
		end
		assert(destination, "Chase probe found no clear authored room centre")
		protected.Character:PivotTo(CFrame.new(destination))
		local acquireDeadline = os.clock() + 3
		repeat
			task.wait(.1)
			local acquired = Manager.GetSnapshot()
			if acquired and acquired.State == "CHASE" and acquired.TargetUserId == player.UserId then break end
		until os.clock() >= acquireDeadline
		local acquired = assert(Manager.GetSnapshot(), "Manager vanished while acquiring chase target")
		assert(acquired.State == "CHASE" and acquired.TargetUserId == player.UserId,
			"Manager did not acquire the fixed chase target")
		local acquiredSeparation = planarDistance(acquired.Position, root.Position)
		local maximumSafeSeconds = (acquiredSeparation - tuning.AttackConfirmRange - 12)
			/ math.max(tuning.Blackout.ChaseSpeed, 1)
		local probeSeconds = math.min(seconds or 6, maximumSafeSeconds)
		assert(probeSeconds >= 4, string.format(
			"Chase fixture is only %.1f studs away after acquisition; cannot run a four-second probe",
			acquiredSeparation))
		local startingAttackSerial = acquired.AttackSerial or 0
		local startingCaptureUserId = acquired.LastCaptureUserId or 0

		local series = sampleSeries(Manager, probeSeconds, .05)
		assert(#series >= 8, "Chase progress probe collected too few samples")
		local first, last = series[1], series[#series]
		local travelled = seriesTravel(series)
		local chaseTravel, chaseSamples, movingSamples = 0, 0, 0
		local maxPerSecond, maxPeak, routeAdvances = 0, 0, 0
		local longestFreeze, freezeStartedAt = 0, nil
		for index, sample in ipairs(series) do
			assert(sample.State == "CHASE", string.format(
				"Fixed-target chase left CHASE at %.2fs (%s)", sample.T, tostring(sample.State)))
			assert(sample.TargetUserId == player.UserId and sample.TargetValid == true,
				"Fixed-target chase lost or invalidated its designated player")
			assert(sample.Generation == acquired.Generation and sample.SpawnSerial == acquired.SpawnSerial,
				"Mall Manager respawned during the fixed-target chase")
			chaseSamples += 1
			if sample.State == "CHASE" and (sample.MovementSpeed or 0) > 1 then movingSamples += 1 end
			maxPerSecond = math.max(maxPerSecond, sample.PathComputesLastSecond or 0)
			maxPeak = math.max(maxPeak, sample.PeakConcurrentPathComputes or 0)
			if index > 1 then
				local previous = series[index - 1]
				if sample.PathSwapSerial == previous.PathSwapSerial
					and sample.WaypointIndex > previous.WaypointIndex then
					routeAdvances += 1
				end
				if sample.StrategicRebuildSerial == previous.StrategicRebuildSerial
					and sample.StrategicIndex > previous.StrategicIndex then
					routeAdvances += 1
				end
				local step = planarDistance(previous.Position, sample.Position)
				chaseTravel += step
				if step <= .05 then
					freezeStartedAt = freezeStartedAt or previous.T
					longestFreeze = math.max(longestFreeze, sample.T - freezeStartedAt)
				else
					freezeStartedAt = nil
				end
			end
		end
		assert(chaseSamples == #series, string.format(
			"Chase was not continuous (%d/%d samples in CHASE)", chaseSamples, #series))
		assert(chaseTravel > 5, string.format(
			"Chasing Manager only travelled %.2f studs during CHASE", chaseTravel))
		assert(longestFreeze <= tuning.StuckSeconds + .25, string.format(
			"Chasing Manager remained motionless for %.2fs (stuck budget %.2fs)",
			longestFreeze, tuning.StuckSeconds))
		assert(last.GenuineProgressSerial > first.GenuineProgressSerial, string.format(
			"Chasing Manager never credited genuine progress (%d -> %d)",
			first.GenuineProgressSerial, last.GenuineProgressSerial))
		assert(maxPeak <= 1, "More than one path computation was in flight during the chase")
		assert(maxPerSecond <= 5, string.format(
			"Chase exceeded five path computations in one second (%d)", maxPerSecond))
		assert(last.AttackSerial == startingAttackSerial
			and last.LastCaptureUserId == startingCaptureUserId,
			"Fixed-target chase entered an attack/capture despite its post-acquisition safety margin")
		assert(maxPerFrameStep(series) <= tuning.Blackout.ChaseSpeed
			* tuning.MaximumMovementDeltaSeconds + .01,
			"Chase step exceeded the configured speed ceiling")
		return {
			Samples = #series,
			ProbeSeconds = probeSeconds,
			FixedTargetUserId = player.UserId,
			FixedTargetDistance = acquiredSeparation,
			TravelledStuds = travelled,
			ChaseTravelStuds = chaseTravel,
			ChaseSamples = chaseSamples,
			MovingChaseSamples = movingSamples,
			LongestFrozenChaseSeconds = longestFreeze,
			RouteAdvances = routeAdvances,
			GenuineProgressEvents = last.GenuineProgressSerial - first.GenuineProgressSerial,
			StuckRecoveries = last.StuckRecoveries - first.StuckRecoveries,
			RecoveryRepaths = last.RecoveryRepaths - first.RecoveryRepaths,
			MaxPathComputesPerSecond = maxPerSecond,
			PeakConcurrentPathComputes = maxPeak,
			Series = series,
		}
	end)
	local cleanupOk, cleanupError = pcall(cleanup)
	if not cleanupOk then
		if not ok then
			error(tostring(result) .. "\nChase cleanup also failed: "
				.. tostring(cleanupError), 0)
		end
		error(cleanupError, 0)
	end
	if not ok then error(result, 0) end
	return result
end

-- Drives the real music-sequence furniture state machine through all three
-- states. A seek across the blackout edge intentionally fires one-way scream
-- and chair events, so this probe is restricted to a disposable Play session.
-- The required callback is always invoked, including when an assertion fails.
function TestSuite.ProbeFurnitureCycle(MusicController: {[string]: any},
	world: Instance, cleanupAfter: (() -> ())?): {[string]: any}
	assertStudioProbe("ProbeFurnitureCycle")
	assert(type(cleanupAfter) == "function",
		"ProbeFurnitureCycle requires an Adapter.Cleanup callback for its disposable session")
	assert(type(MusicController) == "table" and MusicController.GetSnapshot
		and MusicController.DebugSetElapsed,
		"ProbeFurnitureCycle requires the Level 3 music sequence controller")
	assert(world and world.Parent == workspace,
		"ProbeFurnitureCycle requires the live generated world")
	local original = assert(MusicController.GetSnapshot(),
		"Level 3 music sequence is not running")
	assert(type(original.StartServerTime) == "number",
		"Level 3 music sequence has not been armed")
	local music = Configuration.MusicSequence
	local removalStart = music.DurationSeconds - music.BlackoutScreamLeadSeconds
		- music.FurnitureRemovalLeadSeconds
	local finalLockStart = music.CycleEndSeconds - music.HuntFinalFlashlightLockSeconds
	local baseline: any = nil
	local ok, result = pcall(function()
		MusicController.DebugSetElapsed(math.max(0, removalStart - .5))
		task.wait(.15)
		local restoredBefore = assert(MusicController.GetSnapshot(), "music sequence vanished")
		assert(restoredBefore.FurnitureState == "RESTORED",
			"Furniture was not restored before the cycle baseline")
		baseline = TestSuite.CaptureFurnitureBaseline(world)

		MusicController.DebugSetElapsed(removalStart + .1)
		task.wait(.15)
		local removed = assert(MusicController.GetSnapshot(), "music sequence vanished at REMOVED")
		assert(removed.FurnitureState == "REMOVED"
			and workspace:GetAttribute("Level3FurnitureTemporarilyRemoved") == true
			and workspace:GetAttribute("Level3FurnitureCollisionSuppressed") == true,
			"Furniture REMOVED state/attributes are inconsistent")
		for _, record in ipairs(baseline.Records) do
			local part = record.Part
			assert(part.Parent == record.Parent and part:IsDescendantOf(world),
				"Furniture was reparented during REMOVED: " .. record.Name)
			assert(part.Transparency == 1 and part.CastShadow == false
				and part.CanCollide == false and part.CanTouch == false and part.CanQuery == false,
				"Furniture did not become physically absent during REMOVED: " .. record.Name)
			for _, visualRecord in ipairs(record.Visuals) do
				assert(visualRecord.Object.Parent == visualRecord.Parent
					and visualRecord.Object.Transparency == 1,
					"Furniture visual did not disappear during REMOVED: " .. record.Name)
			end
		end

		MusicController.DebugSetElapsed(finalLockStart + .1)
		task.wait(.15)
		local ghost = assert(MusicController.GetSnapshot(), "music sequence vanished at VISIBLE_GHOST")
		assert(ghost.FurnitureState == "VISIBLE_GHOST"
			and workspace:GetAttribute("Level3FurnitureTemporarilyRemoved") == false
			and workspace:GetAttribute("Level3FurnitureCollisionSuppressed") == true,
			"Furniture VISIBLE_GHOST state/attributes are inconsistent")
		for _, record in ipairs(baseline.Records) do
			local part = record.Part
			assert(part.Parent == record.Parent
				and part.Transparency == record.Transparency
				and part.CastShadow == record.CastShadow
				and part.CanCollide == false and part.CanTouch == false and part.CanQuery == false,
				"Furniture ghost visibility/collision contract failed: " .. record.Name)
			for _, visualRecord in ipairs(record.Visuals) do
				assert(visualRecord.Object.Parent == visualRecord.Parent
					and visualRecord.Object.Transparency == visualRecord.Transparency,
					"Furniture visual did not reappear as a ghost: " .. record.Name)
			end
		end

		MusicController.DebugSetElapsed(music.CycleEndSeconds + .1)
		task.wait(.15)
		local restored = assert(MusicController.GetSnapshot(), "music sequence vanished at RESTORED")
		assert(restored.FurnitureState == "RESTORED"
			and workspace:GetAttribute("Level3FurnitureTemporarilyRemoved") == false
			and workspace:GetAttribute("Level3FurnitureCollisionSuppressed") == false,
			"Furniture RESTORED state/attributes are inconsistent")
		local restoredAudit = TestSuite.ValidateFurnitureRestored(baseline)
		return {
			PartsChecked = restoredAudit.Checked,
			VisualsChecked = restoredAudit.VisualsChecked,
			States = {"REMOVED", "VISIBLE_GHOST", "RESTORED"},
			DisposableSessionConsumed = true,
		}
	end)
	local cleanupOk, cleanupError = pcall(cleanupAfter :: () -> ())
	if not cleanupOk then
		if not ok then
			error(tostring(result) .. "\nFurniture cleanup also failed: " .. tostring(cleanupError), 0)
		end
		error("Furniture cleanup failed: " .. tostring(cleanupError), 0)
	end
	if not ok then error(result, 0) end
	return result
end

-- Strict live regression entry point. Missing fixtures are failures rather than
-- "skips", so a green result means every behavioral contract actually ran.
-- Pass {Manager=..., MusicController=..., Player=..., PatrolRoomId=..., World=...}.
function TestSuite.RunNavigationRegression(context: {[string]: any}?): {[string]: any}
	assertStudioProbe("RunNavigationRegression")
	local options = assert(context, "RunNavigationRegression requires a live context")
	assert(options.DisposableSession == true,
		"RunNavigationRegression mutates one-way timeline edges; pass DisposableSession=true")
	assert(type(options.Cleanup) == "function",
		"RunNavigationRegression requires an idempotent Adapter.Cleanup callback")
	local cleanupRan = false
	local function cleanupOnce()
		if cleanupRan then return end
		(options.Cleanup :: () -> ())()
		-- Mark success only after Cleanup returns. If it throws, the runner's
		-- outer finally gets one more chance to dispose the generated session.
		cleanupRan = true
	end

	local ok, payload = pcall(function()
		local results: {[string]: any} = {}
		local ran = {}

		results.Layouts = TestSuite.ValidateNavigationLayouts()
		table.insert(ran, "ValidateNavigationLayouts")

		local Manager = options.Manager
		assert(type(Manager) == "table" and Manager.GetSnapshot,
			"RunNavigationRegression requires the Mall Manager controller")
		local snapshot = assert(Manager.GetSnapshot(), "Mall Manager is not running")
		local player = options.Player
		assert(player and player:IsA("Player") and player.Parent == Players
			and player.Character and player.Character:FindFirstChildOfClass("Humanoid"),
			"RunNavigationRegression requires a live Player character")
		assert(type(options.PatrolRoomId) == "string" and options.PatrolRoomId ~= "",
			"RunNavigationRegression requires PatrolRoomId")
		local MusicController = options.MusicController
		assert(type(MusicController) == "table" and MusicController.GetSnapshot
			and MusicController.DebugSetElapsed,
			"RunNavigationRegression requires the music sequence controller")
		local world = options.World or workspace:FindFirstChild(Configuration.WorldName)
		assert(world and world:IsA("Model") and world.Parent == workspace,
			"RunNavigationRegression requires the live generated world")
		local function renewDisposableHuntWindow()
			-- A complete regression run can outlive the authored 30-second hunt.
			-- Rebase the disposable music timeline before each long live probe so a
			-- Manager disappearing at the natural cycle edge cannot create an
			-- order/timing-dependent failure. Furniture/timeline side effects are
			-- precisely why Cleanup is mandatory for this runner.
			MusicController.DebugSetElapsed(Configuration.MusicSequence.DurationSeconds + .1)
			task.wait(.1)
			assert(Manager.GetSnapshot(),
				"Mall Manager did not remain active after renewing the disposable hunt window")
		end

		results.Telemetry = TestSuite.ValidateManagerNavigationTelemetry(
			snapshot, options.RequirePathValidated ~= false)
		table.insert(ran, "ValidateManagerNavigationTelemetry")

		renewDisposableHuntWindow()
		results.MovingTargetIsolation = TestSuite.ProbeMovingTargetProgressIsolation(
			Manager, player)
		table.insert(ran, "ProbeMovingTargetProgressIsolation")

		renewDisposableHuntWindow()
		results.ChaseProgress = TestSuite.ProbeChaseForwardProgress(
			Manager, player, options.ChaseSeconds)
		table.insert(ran, "ProbeChaseForwardProgress")

		results.BlockedProjection = TestSuite.ProbeBlockedProjection(Manager)
		table.insert(ran, "ProbeBlockedProjection")

		renewDisposableHuntWindow()
		results.SlowMovement = TestSuite.ProbeSlowMovementProgress(
			Manager, options.PatrolRoomId, options.SlowSeconds)
		table.insert(ran, "ProbeSlowMovementProgress")

		renewDisposableHuntWindow()
		results.WallHugAttack = TestSuite.ProbeWallHugAttack(
			Manager, player, options.WallHugSeconds)
		table.insert(ran, "ProbeWallHugAttack")

		-- The overlap probe deliberately makes the live rig escape an artificial
		-- local minimum. Run it only after every navigation probe that needs an
		-- authored starting position; the following furniture probe performs no
		-- Manager movement and then disposes the complete Level 3 session.
		renewDisposableHuntWindow()
		results.TotalOverlap = TestSuite.ProbeTotalOverlapEscalation(Manager, options.OverlapSeconds)
		table.insert(ran, "ProbeTotalOverlapEscalation")

		results.FurnitureCycle = TestSuite.ProbeFurnitureCycle(MusicController, world, cleanupOnce)
		table.insert(ran, "ProbeFurnitureCycle")

		return {Ran = ran, Results = results}
	end)
	local cleanupOk, cleanupError = pcall(cleanupOnce)
	if not cleanupOk then
		if not ok then
			error(tostring(payload) .. "\nRegression cleanup also failed: " .. tostring(cleanupError), 0)
		end
		error("Regression cleanup failed: " .. tostring(cleanupError), 0)
	end
	if not ok then error(payload, 0) end
	return payload
end

return TestSuite
