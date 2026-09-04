--!strict
-- Level 3 Mall Manager AI Controller
--
-- One server-authoritative, kinematic custom-rig enemy for Level 3. The Manager
-- uses multi-ray perception, server-inferred hearing, sticky multiplayer
-- targeting, last-known-position memory, authored-room strategic routing,
-- PathfindingService waypoints, obstruction checks, stuck recovery, fair
-- line-of-sight attacks, and an immediate blackout profile swap.

local CollectionService = game:GetService("CollectionService")
local ContentProvider = game:GetService("ContentProvider")
local PathfindingService = game:GetService("PathfindingService")
local Players = game:GetService("Players")
local ReplicatedStorage = game:GetService("ReplicatedStorage")
local RunService = game:GetService("RunService")
local ServerStorage = game:GetService("ServerStorage")

local Configuration = require(script.Parent:WaitForChild("Level 3 Configuration"))
local HidingController = require(script.Parent:WaitForChild("Level 3 Hiding Controller"))
local Master = require(game:GetService("ReplicatedStorage"):WaitForChild("MasterConfiguration"))

-- Re-resolved on every Start so a master-panel change reaches the next hunt
-- rather than waiting for a server restart. Configuration.MallManager and both
-- of its profiles are frozen on purpose, so this overlays COPIES; the frozen
-- originals are never written to and stay the record of what was authored.
local function resolveTuning()
	local merged = table.clone(Configuration.MallManager)
	merged.Normal = Master.Overlay(Configuration.MallManager.Normal, "L3Manager")
	merged.Blackout = Master.Overlay(Configuration.MallManager.Blackout, "L3ManagerBlackout")
	return merged
end

local Tuning = resolveTuning()
-- Table-check tuning is deliberately NOT master-overlaid: it is a fairness
-- contract (warning window, immunity, cooldowns), not a difficulty dial.
local TableCheckTuning = Configuration.TableCheck

local Controller = {}
local activeSession: any = nil
local activeLayout: any = nil
-- Studio probes only (DebugSetTableChecksEnabled). Module-level rather than
-- per-session so a probe can suspend checks BEFORE the hunt spawns its Manager,
-- and so Controller.Start does not silently undo the probe's own setup.
local debugTableChecksSuspended = false
local playChaseScream: (any) -> ()
local stopChaseScream: (any) -> ()
-- Forward declaration: corridor waypoint revalidation needs the shared
-- full-segment clearance contract, which is defined with the navigation
-- filters below.
local volumeClear: (any, Vector3, Vector3) -> boolean

-- ServerStorage assets can be absent from a place file, and WaitForChild with
-- no timeout yields instead of erroring. Every caller below is reached from
-- Controller.Start, which Level 3 Round Adapter's sync() runs inside a pcall,
-- so an unbounded yield means that pcall NEVER returns: the hunt silently
-- never spawns, the adapter's own "Mall Manager hunt spawn failed" warn never
-- prints, and every later hunt edge parks another thread. Fail loudly.
local ASSET_WAIT = 10

local function requireAsset(root: Instance, ...: string): Instance
	local node: Instance = root
	for _, name in ipairs({ ... }) do
		local found = node:WaitForChild(name, ASSET_WAIT)
		if not found then
			error(string.format("Mall Manager assets: %s.%s missing after %d s",
				node:GetFullName(), name, ASSET_WAIT), 0)
		end
		node = found
	end
	return node
end

local function stateFolder(): Folder
	local existing = ReplicatedStorage:FindFirstChild(Configuration.StateFolderName)
	if existing and existing:IsA("Folder") then return existing end
	if existing then existing:Destroy() end
	local created = Instance.new("Folder")
	created.Name = Configuration.StateFolderName
	created.Parent = ReplicatedStorage
	return created
end

local function disconnect(connection: RBXScriptConnection?)
	if connection and connection.Connected then connection:Disconnect() end
end

local function flat(position: Vector3, y: number): Vector3
	return Vector3.new(position.X, y, position.Z)
end

local function planarDistance(a: Vector3, b: Vector3): number
	return (Vector3.new(a.X, 0, a.Z) - Vector3.new(b.X, 0, b.Z)).Magnitude
end

local function liveSession(session: any): boolean
	local world = session and session.World
	return activeSession == session
		and session.Active == true
		and world ~= nil
		and world:IsA("Model")
		and world.Parent == workspace
		and world:GetAttribute("Level3_Generation") == session.Generation
end

local function validRound(session: any): boolean
	return liveSession(session)
		and workspace:GetAttribute("SelectedLevel") == 3
		and workspace:GetAttribute("RoundActive") == true
		and workspace:GetAttribute("Level3MallManagerHuntActive") == true
		and workspace:GetAttribute("EntityPaused") ~= true
end

local function blackoutProfileRequested(): boolean
	return workspace:GetAttribute("Level3BlackoutActive") == true
		or workspace:GetAttribute("Level3FinalHallChaseActive") == true
end

local function publishMotion(session: any, dt: number, hardSnap: boolean?)
	if not session.MotionRemote or not session.Model or not session.Model.Parent then return end
	local interval = 1 / math.max(1, Tuning.MotionSnapshotRate)
	session.MotionAccumulator += dt
	if not hardSnap and session.MotionAccumulator < interval then return end
	session.MotionAccumulator = if hardSnap then 0 else session.MotionAccumulator % interval
	session.MotionSequence += 1
	session.MotionRemote:FireAllClients(
		session.Model,
		session.Generation,
		session.SpawnSerial,
		session.MotionSequence,
		workspace:GetServerTimeNow(),
		session.Root.CFrame,
		hardSnap == true
	)
end

local function livingPlayer(player: Player, session: any): (Model?, Humanoid?, BasePart?)
	if not validRound(session)
		or player.Parent ~= Players
		or player:GetAttribute("InRound") ~= true
		or player:GetAttribute("Escaped") == true
		or HidingController.IsHidden(player, session.Generation) then
		return nil, nil, nil
	end
	local character = player.Character
	local humanoid = character and character:FindFirstChildOfClass("Humanoid")
	local root = character and character:FindFirstChild("HumanoidRootPart")
	if not character or not character.Parent or not humanoid or humanoid.Health <= 0
		or not root or not root:IsA("BasePart") then
		return nil, nil, nil
	end
	return character, humanoid, root
end

local function profile(session: any): any
	return if session.Blackout then Tuning.Blackout else Tuning.Normal
end

local function goalMoveThreshold(session: any): number
	return if session.Blackout
		then Tuning.BlackoutPathGoalMoveThreshold else Tuning.PathGoalMoveThreshold
end

-- The hard floor between ComputeAsync starts. In blackout this is
-- BlackoutPathRecomputeSeconds = 0.20, i.e. at most five requests per second;
-- forced recovery requests queue behind it instead of bypassing it.
local function pathRequestInterval(session: any): number
	return if session.Blackout then Tuning.BlackoutPathRecomputeSeconds else Tuning.PathRecomputeSeconds
end

local function currentSpeed(session: any): number
	local stateName = session.State
	local activeProfile = profile(session)
	if stateName == "PATROL" or stateName == "PATROL_LISTEN" or stateName == "AWAKENING" then
		return activeProfile.PatrolSpeed
	end
	if stateName == "INVESTIGATE" or stateName == "ALERT" or stateName == "RECOVER" then
		return activeProfile.InvestigateSpeed
	end
	if stateName == "SEARCH" or stateName == "TRACKING" then return activeProfile.SearchSpeed end
	if stateName == "CHASE" then return activeProfile.ChaseSpeed end
	if stateName == "ATTACK_WINDUP" then return activeProfile.PatrolSpeed end
	return 0
end

local function publishPathStatus(session: any, value: string)
	if session.PathStatus == value then return end
	session.PathStatus = value
	if session.Model and session.Model.Parent then
		session.Model:SetAttribute("Level3_MallManagerPathStatus", value)
	end
	session.StateFolder:SetAttribute("Level3_MallManagerPathStatus", value)
end

-- LEVEL3_MANAGER_GENUINE_PATH_VALIDATION_20260827
-- Spawn selection only proves the spawn volume is clear. Reachability is
-- published only after the authoritative 5.25-stud volume contract accepts a
-- complete route (or a direct segment reaches the goal); a coarse PFS success
-- using PathAgentRadius can never make this telemetry true by itself.
local function markPathValidated(session: any)
	if session.PathValidated then return end
	session.PathValidated = true
	session.StateFolder:SetAttribute("Level3_MallManagerPathValidated", true)
	if session.Model and session.Model.Parent then
		session.Model:SetAttribute("Level3_MallManagerPathValidated", true)
	end
end

local function publishTargetTelemetry(session: any, mode: string, distance: number,
	position: Vector3?)
	session.StateFolder:SetAttribute("Level3_MallManagerTargetMode", mode)
	session.StateFolder:SetAttribute("Level3_MallManagerTargetDistance", distance)
	session.StateFolder:SetAttribute("Level3_MallManagerTargetPosition", position)
	if session.Model and session.Model.Parent then
		session.Model:SetAttribute("Level3_MallManagerTargetMode", mode)
		session.Model:SetAttribute("Level3_MallManagerTargetDistance", distance)
		session.Model:SetAttribute("Level3_MallManagerTargetPosition", position)
	end
end

local function publishTarget(session: any, player: Player?)
	if player and HidingController.IsHidden(player, session.Generation) then player = nil end
	if session.Target == player then
		-- Nil is also a telemetry state. Re-publish it even when the target field is
		-- already nil so an old mode/position can never survive a dormant edge.
		if not player then publishTargetTelemetry(session, "NONE", -1, nil) end
		return
	end
	local old = session.Target
	session.Target = player
	if not player then stopChaseScream(session) end
	if old and old.Parent == Players and old:GetAttribute("BeingChased") == true then
		old:SetAttribute("BeingChased", false)
	end
	if player and player.Parent == Players then
		player:SetAttribute("BeingChased", true)
	end
	local userId = if player then player.UserId else 0
	session.StateFolder:SetAttribute("Level3_MallManagerTargetUserId", userId)
	if session.Model and session.Model.Parent then
		session.Model:SetAttribute("Level3_MallManagerTargetUserId", userId)
	end
	if not player then publishTargetTelemetry(session, "NONE", -1, nil) end
end

local function publishState(session: any, stateName: string)
	if session.State == stateName then return end
	local oldState = session.State
	session.State = stateName
	local speed = currentSpeed(session)
	session.StateFolder:SetAttribute("Level3_MallManagerState", stateName)
	session.StateFolder:SetAttribute("Level3_MallManagerSpeed", speed)
	workspace:SetAttribute("Level3MallManagerState", stateName)
	if session.Model and session.Model.Parent then
		session.Model:SetAttribute("Level3_MallManagerState", stateName)
		session.Model:SetAttribute("Level3_MallManagerSpeed", speed)
	end
	if stateName == "CHASE" and oldState ~= "CHASE" then playChaseScream(session) end
end

local function publishProfile(session: any)
	local activeProfile = profile(session)
	session.StateFolder:SetAttribute("Level3_MallManagerBlackoutBoosted", session.Blackout)
	session.StateFolder:SetAttribute("Level3_MallManagerAwarenessRange", activeProfile.VisionRange)
	session.StateFolder:SetAttribute("Level3_MallManagerSpeed", currentSpeed(session))
	workspace:SetAttribute("Level3MallManagerBlackoutBoosted", session.Blackout)
	if session.Model and session.Model.Parent then
		session.Model:SetAttribute("Level3_MallManagerBlackoutBoosted", session.Blackout)
		session.Model:SetAttribute("Level3_MallManagerAwarenessRange", activeProfile.VisionRange)
		session.Model:SetAttribute("Level3_MallManagerSpeed", currentSpeed(session))
	end
end

-- LEVEL3_MANAGER_TABLE_CHECK_20260904
-- What the clients need to render a table check: which hiding table the Manager
-- is kneeling at (its Level3_HideTableIndex, 0 for none) and when the reaction
-- window closes, in workspace:GetServerTimeNow() terms so a client can compare
-- it directly. Nothing is written onto the anchor itself -- hide anchors are
-- Level3_PermanentFurniture and the furniture audit reads new attributes on
-- them as tampering.
local function publishTableCheck(session: any, anchor: BasePart?, endsAtServerTime: number)
	local index = if anchor then (tonumber(anchor:GetAttribute("Level3_HideTableIndex")) or 0) else 0
	session.StateFolder:SetAttribute("Level3_MallManagerTableCheckIndex", index)
	session.StateFolder:SetAttribute("Level3_MallManagerTableCheckEndsAt", endsAtServerTime)
end

local function clearPath(session: any, status: string?)
	session.PathToken += 1
	session.Path = nil
	session.PathObject = nil
	session.WaypointIndex = 1
	session.PathGoal = nil
	-- PathComputing/InFlightPathGoal are owned exclusively by the compute task
	-- so at most one ComputeAsync can ever be in flight; the bumped token makes
	-- the running task discard its result.
	session.PendingPathGoal = nil
	session.PendingPathForce = false
	disconnect(session.PathBlockedConnection)
	session.PathBlockedConnection = nil
	if status then publishPathStatus(session, status) end
end

local function resetOverlapEscapeState(session: any)
	session.OverlapEscapeActive = false
	session.OverlapEscapeDirection = nil
	session.OverlapEscapeStartedAt = 0
	session.OverlapEscapeBaselineBlockers = 0
	session.OverlapEscapeBaselineGoalPoint = nil
	session.OverlapEscapeBaselineGoalDistance = math.huge
	session.OverlapEscapeNextRetryAt = 0
	session.OverlapEscapeAttempts = 0
	session.AvoidanceSign = 0
	session.AvoidanceUntil = 0
	if session.Model and session.Model.Parent then
		session.Model:SetAttribute("Level3_MallManagerAvoidanceSign", 0)
		session.Model:SetAttribute("Level3_MallManagerOverlapEscapeActive", false)
	end
end

local function clearGoal(session: any)
	session.FinalGoal = nil
	session.ResolvedFinalGoal = nil
	session.StrategicPoints = {}
	session.StrategicRooms = {}
	session.StrategicIndex = 1
	session.StrategicStartRoomId = nil
	session.StrategicGoalRoomId = nil
	resetOverlapEscapeState(session)
	clearPath(session, "IDLE")
end

local function stopWalkForCleanup(session: any)
	local track = session.WalkTrack
	if track and track.IsPlaying then
		pcall(function() track:Stop(Tuning.AnimationFadeSeconds) end)
	end
	for _, sound in ipairs(session.FootstepSounds or {}) do
		pcall(function() sound:Stop() end)
	end
	session.WalkMoving = false
	session.WalkPoseHeld = false
	session.WalkPlaybackSpeed = 0
	session.FootstepWasMoving = false
end

local function holdWalkPose(session: any)
	local track = session.WalkTrack
	if not track then return end
	if session.WalkPoseHeld and track.IsPlaying then return end
	local ok = pcall(function()
		if not track.IsPlaying then
			-- Prime frame zero at full weight before freezing it. Frame zero is a
			-- real keyed walk pose, so initial waiting never exposes the A-pose.
			track:Play(Tuning.AnimationFadeSeconds, 1, 1)
			track.TimePosition = 0
		else
			track:AdjustWeight(1, Tuning.AnimationFadeSeconds)
		end
		track:AdjustSpeed(0)
	end)
	if ok then
		session.WalkMoving = false
		session.WalkPoseHeld = true
		session.WalkPlaybackSpeed = 0
	end
end

local function setWalk(session: any, moving: boolean, speed: number)
	local track = session.WalkTrack
	if not track then return end
	-- While the blackout-only Manager exists, its limp is always alive. Temporary
	-- path/attack frames may suppress footstep audio, but never freeze the visible rig.
	local playback = if moving
		then math.max(Tuning.ContinuousAnimationPlaybackSpeed,
			math.clamp(speed / Tuning.WalkReferenceSpeed,
				Tuning.MinimumAnimationSpeed, Tuning.MaximumAnimationSpeed))
		else Tuning.ContinuousAnimationPlaybackSpeed
	local ok = pcall(function()
		if not track.IsPlaying then
			track:Play(Tuning.AnimationFadeSeconds, 1, playback)
		elseif session.WalkPoseHeld
			or math.abs((session.WalkPlaybackSpeed or 0) - playback) > .001 then
			track:AdjustWeight(1, Tuning.AnimationFadeSeconds)
			track:AdjustSpeed(playback)
		end
	end)
	if ok then
		session.WalkMoving = moving
		session.WalkPoseHeld = false
		session.WalkPlaybackSpeed = playback
	end
end

local function loadFootstepSounds(root: BasePart, groundOffset: number): (Attachment, {Sound})
	local prototypes = requireAsset(ServerStorage, "Level3Assets", "EntitySounds", "MallManager")
	local emitter = Instance.new("Attachment")
	emitter.Name = "Mall Manager Footstep Emitter"
	emitter.Position = Vector3.new(0, -groundOffset + Tuning.FootstepEmitterHeight, 0)
	emitter:SetAttribute("Level3_MallManagerFootstepEmitter", true)
	emitter.Parent = root

	local sounds = {}
	for index, name in ipairs(Tuning.FootstepSoundNames) do
		local prototype = prototypes:FindFirstChild(name)
		local expectedId = Configuration.Audio[name]
		assert(prototype and prototype:IsA("Sound"), "Missing Mall Manager footstep prototype: " .. name)
		assert(type(expectedId) == "string" and expectedId ~= "" and prototype.SoundId == expectedId,
			"Mall Manager footstep prototype ID is stale: " .. name)
		local sound = prototype:Clone()
		sound.Name = name
		sound.SoundId = expectedId
		sound.Volume = Tuning.FootstepVolume
		sound.PlaybackSpeed = 1
		sound.Looped = false
		sound.PlayOnRemove = false
		sound.RollOffMode = Enum.RollOffMode.InverseTapered
		sound.RollOffMinDistance = Tuning.FootstepRollOffMinDistance
		sound.RollOffMaxDistance = Tuning.FootstepRollOffMaxDistance
		sound:SetAttribute("Level3_MallManagerFootstep", true)
		sound:SetAttribute("FootstepIndex", index)
		sound:SetAttribute("AnimationTime", Tuning.FootstepAnimationTimes[index])
		sound.Parent = emitter
		table.insert(sounds, sound)
	end
	task.defer(function()
		local ok, err = pcall(function() ContentProvider:PreloadAsync(sounds) end)
		if not ok and emitter.Parent then
			warn("[Level 3 Mall Manager] Footstep preload failed: " .. tostring(err))
		end
	end)
	return emitter, sounds
end

local function loadChaseScream(model: Model): (Bone, Sound)
	local prototypes = requireAsset(ServerStorage, "Level3Assets", "EntitySounds", "MallManagerScreams")
	local headObject = model:FindFirstChild("Head", true)
	assert(headObject and headObject:IsA("Bone"), "Mall Manager rig is missing its balloon Head bone")
	local head = headObject :: Bone
	head:SetAttribute("Level3_MallManagerVoiceEmitter", true)
	local prototype = prototypes:FindFirstChild(Tuning.ChaseScreamSoundName)
	assert(prototype and prototype:IsA("Sound"), "Missing Mall Manager chase scream prototype")
	assert(prototype.SoundId == Configuration.Audio.MallManagerBalloonScream,
		"Mall Manager chase scream prototype ID is stale")
	local sound = prototype:Clone()
	sound.Name = Tuning.ChaseScreamSoundName
	sound.SoundId = Configuration.Audio.MallManagerBalloonScream
	sound.Volume = Tuning.ChaseScreamVolume
	sound.PlaybackSpeed = 1
	sound.Looped = false
	sound.PlayOnRemove = false
	sound.RollOffMode = Enum.RollOffMode.InverseTapered
	sound.RollOffMinDistance = Tuning.ChaseScreamRollOffMinDistance
	sound.RollOffMaxDistance = Tuning.ChaseScreamRollOffMaxDistance
	sound:SetAttribute("Level3_MallManagerChaseScream", true)
	sound.Parent = head
	task.defer(function()
		local ok, err = pcall(function() ContentProvider:PreloadAsync({sound}) end)
		if not ok and sound.Parent then
			warn("[Level 3 Mall Manager] Chase scream preload failed: " .. tostring(err))
		end
	end)
	return head, sound
end

stopChaseScream = function(session: any)
	local sound = session.ChaseScream
	if sound and sound:IsA("Sound") and sound.IsPlaying then pcall(function() sound:Stop() end) end
	session.ChaseScreamPlaying = false
	if session.StateFolder then
		session.StateFolder:SetAttribute("Level3_MallManagerChaseScreamPlaying", false)
	end
	if session.Model and session.Model.Parent then
		session.Model:SetAttribute("Level3_MallManagerChaseScreamPlaying", false)
	end
end

playChaseScream = function(session: any)
	if not validRound(session) or session.State ~= "CHASE" or not session.Target then return end
	local sound = session.ChaseScream
	if not sound or not sound:IsA("Sound") or not sound.Parent or sound.IsPlaying then return end
	local now = workspace:GetServerTimeNow()
	if now < session.NextChaseScreamAt then return end
	local ok = pcall(function()
		sound.TimePosition = 0
		sound:Play()
	end)
	if not ok then return end
	session.NextChaseScreamAt = now + Tuning.ChaseScreamCooldownSeconds
	session.ChaseScreamSerial += 1
	session.ChaseScreamPlaying = true
	session.LastChaseScreamAtServerTime = now
	session.StateFolder:SetAttribute("Level3_MallManagerChaseScreamSerial", session.ChaseScreamSerial)
	session.StateFolder:SetAttribute("Level3_MallManagerChaseScreamPlaying", true)
	session.StateFolder:SetAttribute("Level3_MallManagerLastChaseScreamAtServerTime", now)
	session.StateFolder:SetAttribute("Level3_MallManagerLastChaseScreamName", sound.Name)
	if session.Model and session.Model.Parent then
		session.Model:SetAttribute("Level3_MallManagerChaseScreamSerial", session.ChaseScreamSerial)
		session.Model:SetAttribute("Level3_MallManagerChaseScreamPlaying", true)
		session.Model:SetAttribute("Level3_MallManagerLastChaseScreamAtServerTime", now)
		session.Model:SetAttribute("Level3_MallManagerLastChaseScreamName", sound.Name)
	end
end

local function playFootstep(session: any, index: number, phase: number)
	if not validRound(session) or not session.WalkMoving then return end
	local sound = session.FootstepSounds[index]
	if not sound or not sound:IsA("Sound") or not sound.Parent then return end
	local ok = pcall(function()
		if sound.IsPlaying then sound:Stop() end
		sound.TimePosition = 0
		sound:Play()
	end)
	if not ok then return end
	session.FootstepSerial += 1
	session.LastFootstepIndex = index
	session.LastFootstepName = sound.Name
	session.LastFootstepPhase = phase
	session.StateFolder:SetAttribute("Level3_MallManagerFootstepSerial", session.FootstepSerial)
	session.StateFolder:SetAttribute("Level3_MallManagerLastFootstepIndex", index)
	session.StateFolder:SetAttribute("Level3_MallManagerLastFootstepName", sound.Name)
	session.StateFolder:SetAttribute("Level3_MallManagerLastFootstepPhase", phase)
	if session.Model and session.Model.Parent then
		session.Model:SetAttribute("Level3_MallManagerFootstepSerial", session.FootstepSerial)
		session.Model:SetAttribute("Level3_MallManagerLastFootstepIndex", index)
		session.Model:SetAttribute("Level3_MallManagerLastFootstepName", sound.Name)
		session.Model:SetAttribute("Level3_MallManagerLastFootstepPhase", phase)
	end
end

local function updateFootsteps(session: any)
	local track = session.WalkTrack
	if not track then return end
	local current = track.TimePosition
	local duration = track.Length
	if duration <= 0 or not session.WalkMoving or not track.IsPlaying
		or session.WalkPlaybackSpeed <= 0 or not validRound(session) then
		session.FootstepWasMoving = false
		session.LastWalkTimePosition = current
		return
	end
	if not session.FootstepWasMoving then
		session.FootstepWasMoving = true
		session.LastWalkTimePosition = current
		return
	end

	local previous = session.LastWalkTimePosition
	local phases = Tuning.FootstepAnimationTimes
	if current >= previous then
		for index, phase in ipairs(phases) do
			if phase > previous and phase <= current then playFootstep(session, index, phase) end
		end
	else
		-- Preserve chronological order when the 2.9-second animation loops.
		for index, phase in ipairs(phases) do
			if phase > previous and phase <= duration then playFootstep(session, index, phase) end
		end
		for index, phase in ipairs(phases) do
			if phase <= current then playFootstep(session, index, phase) end
		end
	end
	session.LastWalkTimePosition = current
end

local function layoutRooms(): {any}
	if type(activeLayout) == "table" and type(activeLayout.Rooms) == "table" then
		return activeLayout.Rooms
	end
	return Configuration.Rooms
end

local function layoutLinks(): {any}
	if type(activeLayout) == "table" and type(activeLayout.Links) == "table" then
		return activeLayout.Links
	end
	return Configuration.Links
end

local function roomDefinition(id: string): any
	for _, room in ipairs(layoutRooms()) do
		if room.Id == id then return room end
	end
	return nil
end

local function roomCenter(id: string, floorY: number): Vector3?
	local room = roomDefinition(id)
	if not room then return nil end
	return Configuration.WorldOrigin + Vector3.new(room.X, floorY - Configuration.WorldOrigin.Y, room.Z)
end

local function centerCorridorWaypoint(session: any, position: Vector3,
	floorY: number, revalidate: boolean?): Vector3
	local localPosition = position - Configuration.WorldOrigin
	local bestProjection: Vector3? = nil
	local bestLateralDistance = math.huge
	local lateralLimit = Configuration.CorridorWidth * .5 + .25
	for _, link in ipairs(layoutLinks()) do
		if link.Door ~= "HiddenExit"
			or workspace:GetAttribute("Level3FinalHallChaseActive") == true then
			local a, b = roomDefinition(link.A), roomDefinition(link.B)
			if a and b then
				local horizontal = math.abs(b.X - a.X) > math.abs(b.Z - a.Z)
				if horizontal then
					local direction = if b.X > a.X then 1 else -1
					local startAlong = a.X + direction * a.W * .5
					local endAlong = b.X - direction * b.W * .5
					local minimum, maximum = math.min(startAlong, endAlong), math.max(startAlong, endAlong)
					local lateralDistance = math.abs(localPosition.Z - a.Z)
					if localPosition.X >= minimum - Tuning.CorridorCenteringLead
						and localPosition.X <= maximum + Tuning.CorridorCenteringLead
						and lateralDistance <= lateralLimit and lateralDistance < bestLateralDistance then
						bestLateralDistance = lateralDistance
						bestProjection = Vector3.new(position.X, floorY, Configuration.WorldOrigin.Z + a.Z)
					end
				else
					local direction = if b.Z > a.Z then 1 else -1
					local startAlong = a.Z + direction * a.D * .5
					local endAlong = b.Z - direction * b.D * .5
					local minimum, maximum = math.min(startAlong, endAlong), math.max(startAlong, endAlong)
					local lateralDistance = math.abs(localPosition.X - a.X)
					if localPosition.Z >= minimum - Tuning.CorridorCenteringLead
						and localPosition.Z <= maximum + Tuning.CorridorCenteringLead
						and lateralDistance <= lateralLimit and lateralDistance < bestLateralDistance then
						bestLateralDistance = lateralDistance
						bestProjection = Vector3.new(Configuration.WorldOrigin.X + a.X, floorY, position.Z)
					end
				end
			end
		end
	end
	local original = flat(position, floorY)
	if not bestProjection then return original end
	-- LEVEL3_MANAGER_WAYPOINT_REVALIDATION_20260827
	-- The centreline is a preference, not a truth. A projection may only
	-- replace its PFS waypoint when the whole lateral hop from the original
	-- point to the projection passes the shared furniture-aware full-segment
	-- clearance contract — endpoint occupancy alone can hide a blocker sitting
	-- between the two. Otherwise the original waypoint stands, so a blocked
	-- centreline can never replace or prematurely consume a valid PFS point.
	if revalidate and planarDistance(bestProjection, original) > .05
		and not volumeClear(session, original, bestProjection) then
		return original
	end
	return bestProjection
end

-- Apply the second half of the projection contract used by live movement. The
-- lateral PFS-point -> centreline hop is checked by centerCorridorWaypoint;
-- this check covers the Manager's actual current position -> projected target
-- segment. Keeping it in one helper prevents consumption, first-waypoint
-- steering and the Studio regression probe from drifting apart.
local function movementProjectedWaypoint(session: any, currentGround: Vector3,
	originalPosition: Vector3): (Vector3, boolean, boolean)
	local original = flat(originalPosition, session.FloorY)
	local projected = centerCorridorWaypoint(session, original, session.FloorY, true)
	local usedProjection = planarDistance(original, projected) > .05
	local approachClear = not usedProjection or volumeClear(session, currentGround, projected)
	if usedProjection and not approachClear then
		return original, true, false
	end
	return projected, usedProjection, true
end

-- Planar distance from a position to the room's floor rectangle: zero inside
-- the bounds, otherwise the distance to the nearest edge. Rooms never overlap,
-- so containment is unambiguous; corridor positions resolve to whichever mouth
-- is closer. Room-centre distance used to misclassify doorway positions beside
-- large rooms.
local function roomBoundsDistance(room: any, position: Vector3): number
	local localX = position.X - Configuration.WorldOrigin.X
	local localZ = position.Z - Configuration.WorldOrigin.Z
	local dx = math.max(math.abs(localX - room.X) - room.W * .5, 0)
	local dz = math.max(math.abs(localZ - room.Z) - room.D * .5, 0)
	return math.sqrt(dx * dx + dz * dz)
end

local function nearestRoomId(position: Vector3): string
	local rooms = layoutRooms()
	local firstRoom = assert(rooms[1], "Mall Manager layout must contain at least one room")
	local bestId = firstRoom.Id
	local bestDistance = math.huge
	for _, room in ipairs(rooms) do
		local distance = roomBoundsDistance(room, position)
		if distance < bestDistance then
			bestDistance = distance
			bestId = room.Id
			if distance <= 0 then break end
		end
	end
	return bestId
end

local function roomIdContaining(position: Vector3): string?
	for _, room in ipairs(layoutRooms()) do
		if roomBoundsDistance(room, position) <= 0 then return room.Id end
	end
	return nil
end

local function buildAdjacency(): {[string]: {string}}
	local adjacency: {[string]: {string}} = {}
	for _, room in ipairs(layoutRooms()) do adjacency[room.Id] = {} end
	for _, link in ipairs(layoutLinks()) do
		if link.Door ~= "HiddenExit" then
			table.insert(adjacency[link.A], link.B)
			table.insert(adjacency[link.B], link.A)
		end
	end
	return adjacency
end

local function graphRoute(session: any, startId: string, goalId: string): {string}
	if startId == goalId then return {startId} end
	local queue = {startId}
	local cursor = 1
	local parent: {[string]: string} = {}
	local seen = {[startId] = true}
	while cursor <= #queue do
		local roomId = queue[cursor]
		cursor += 1
		for _, neighbour in ipairs(session.Adjacency[roomId] or {}) do
			if not seen[neighbour] then
				seen[neighbour] = true
				parent[neighbour] = roomId
				table.insert(queue, neighbour)
				if neighbour == goalId then
					cursor = #queue + 1
					break
				end
			end
		end
	end
	if not seen[goalId] then return {startId} end
	local reversed = {goalId}
	local current = goalId
	while current ~= startId do
		current = parent[current]
		table.insert(reversed, current)
	end
	local route = {}
	for index = #reversed, 1, -1 do table.insert(route, reversed[index]) end
	return route
end

local function navigationIgnored(session: any): {Instance}
	local ignored: {Instance} = {session.Model}
	for _, player in ipairs(Players:GetPlayers()) do
		if player.Character then table.insert(ignored, player.Character) end
	end
	return ignored
end

-- Filter params are rebuilt at most once per Heartbeat: the ignore list only
-- changes when a character (re)spawns, while a single movement step can probe
-- dozens of volumes (straight step + 10 avoidance angles + path lookahead).
local function refreshNavigationFilters(session: any)
	local ignored = navigationIgnored(session)
	local raycast = RaycastParams.new()
	raycast.FilterType = Enum.RaycastFilterType.Exclude
	raycast.FilterDescendantsInstances = ignored
	raycast.IgnoreWater = true
	raycast.RespectCanCollide = true
	session.NavigationRaycastParams = raycast
	local overlap = OverlapParams.new()
	overlap.FilterType = Enum.RaycastFilterType.Exclude
	overlap.FilterDescendantsInstances = ignored
	overlap.RespectCanCollide = true
	overlap.MaxParts = 16
	session.NavigationOverlapParams = overlap
end

local function navigationParams(session: any): RaycastParams
	if not session.NavigationRaycastParams then refreshNavigationFilters(session) end
	return session.NavigationRaycastParams
end

local function navigationOverlapParams(session: any): OverlapParams
	if not session.NavigationOverlapParams then refreshNavigationFilters(session) end
	return session.NavigationOverlapParams
end

local function clearanceBox(groundPosition: Vector3): (CFrame, Vector3)
	local castHeight = math.max(2, Tuning.AgentHeight - .6)
	local center = groundPosition + Vector3.new(0, castHeight * .5 + .2, 0)
	local size = Vector3.new(Tuning.SweepRadius * 2, castHeight, Tuning.SweepRadius * 2)
	-- Keep the square aligned to the axis-aligned Level 3 corridors. Rotating a
	-- square sweep at a corner would artificially widen it by sqrt(2).
	return CFrame.new(center), size
end

-- LEVEL3_MANAGER_SHARED_FURNITURE_CLEARANCE_20260821
-- Pathfinding, direct-path shortcuts, waypoint lookahead, and local steering must
-- agree on the same inflated table-and-chair envelopes. These parts are
-- deliberately non-collidable, so physics overlap queries alone cannot see them.
-- PFS may return points exactly on a modifier boundary. Keep a small seam tolerance
-- inside the authored 1.25-stud padding so tangent motion is not misread as overlap.
local FURNITURE_CLEARANCE_EPSILON = .25

local function collectFurnitureNavExclusions(world: Model): {BasePart}
	local exclusions = {}
	for _, object in ipairs(world:GetDescendants()) do
		if object:IsA("BasePart")
			and object:GetAttribute("Level3_ManagerFurnitureNavExclusion") == true then
			table.insert(exclusions, object)
		end
	end
	return exclusions
end

-- LEVEL3_PERMANENT_FURNITURE_20260828
-- Furniture is permanent scene topology. It is never stripped, ghosted or made
-- collisionless, so every exclusion envelope guards physically present
-- furniture for the whole round and the Manager plans around all of it,
-- blackout and hunt included. The predicate is kept (rather than inlined as
-- `true`) because an envelope can still legitimately leave the world when its
-- generation is torn down mid-frame; CanQuery is asserted rather than merely
-- read, so a regression that silently un-queries an envelope shows up here
-- instead of quietly shrinking the navigation topology.
local function furnitureNavExclusionActive(exclusion: BasePart): boolean
	return exclusion.Parent ~= nil and exclusion.CanQuery == true
end

local function activeFurnitureNavExclusionCount(session: any): number
	local count = 0
	for _, exclusion in ipairs(session.FurnitureNavExclusions or {}) do
		if furnitureNavExclusionActive(exclusion) then count += 1 end
	end
	return count
end

local function furnitureNavExclusionsAt(session: any, groundPosition: Vector3): {BasePart}
	local blockers = {}
	for _, exclusion in ipairs(session.FurnitureNavExclusions or {}) do
		if furnitureNavExclusionActive(exclusion) then
			local sample = Vector3.new(groundPosition.X, exclusion.Position.Y, groundPosition.Z)
			local localPoint = exclusion.CFrame:PointToObjectSpace(sample)
			if math.abs(localPoint.X) < exclusion.Size.X * .5 - FURNITURE_CLEARANCE_EPSILON
				and math.abs(localPoint.Z) < exclusion.Size.Z * .5 - FURNITURE_CLEARANCE_EPSILON then
				table.insert(blockers, exclusion)
			end
		end
	end
	return blockers
end

local function furnitureNavExclusionOnSegment(session: any,
	startGround: Vector3, endGround: Vector3): BasePart?
	for _, exclusion in ipairs(session.FurnitureNavExclusions or {}) do
		if furnitureNavExclusionActive(exclusion) then
			local sampleY = exclusion.Position.Y
			local localStart = exclusion.CFrame:PointToObjectSpace(
				Vector3.new(startGround.X, sampleY, startGround.Z))
			local localFinish = exclusion.CFrame:PointToObjectSpace(
				Vector3.new(endGround.X, sampleY, endGround.Z))
			local delta = localFinish - localStart
			local tMin = 0
			local tMax = 1

			local function clipAxis(origin: number, change: number, halfExtent: number): boolean
				if math.abs(change) <= 1e-5 then
					return math.abs(origin) < halfExtent
				end
				local enter = (-halfExtent - origin) / change
				local leave = (halfExtent - origin) / change
				if enter > leave then enter, leave = leave, enter end
				tMin = math.max(tMin, enter)
				tMax = math.min(tMax, leave)
				return tMin < tMax
			end

			if clipAxis(localStart.X, delta.X,
				math.max(.05, exclusion.Size.X * .5 - FURNITURE_CLEARANCE_EPSILON))
				and clipAxis(localStart.Z, delta.Z,
					math.max(.05, exclusion.Size.Z * .5 - FURNITURE_CLEARANCE_EPSILON)) then
				return exclusion
			end
		end
	end
	return nil
end

local function segmentIntersectsFurnitureNavExclusion(session: any,
	startGround: Vector3, endGround: Vector3): boolean
	return furnitureNavExclusionOnSegment(session, startGround, endGround) ~= nil
end

local function overlappingNavigationParts(session: any, groundPosition: Vector3,
	params: OverlapParams?): {BasePart}
	local boxCFrame, size = clearanceBox(groundPosition)
	local overlapParams = params or navigationOverlapParams(session)
	return workspace:GetPartBoundsInBox(boxCFrame, size, overlapParams)
end

local function publishPhysicalBlocker(session: any, blocker: BasePart, phase: string)
	if session.Model and session.Model.Parent then
		session.Model:SetAttribute("Level3_MallManagerLastPhysicalBlocker", blocker:GetFullName())
		session.Model:SetAttribute("Level3_MallManagerLastPhysicalBlockerPhase", phase)
	end
end

local function physicalVolumeClear(session: any, startGround: Vector3, endGround: Vector3): boolean
	local overlapParams = navigationOverlapParams(session)
	local startBlockers = overlappingNavigationParts(session, startGround, overlapParams)
	if #startBlockers > 0 then
		publishPhysicalBlocker(session, startBlockers[1], "START_OVERLAP")
		return false
	end
	local endBlockers = overlappingNavigationParts(session, endGround, overlapParams)
	if #endBlockers > 0 then
		publishPhysicalBlocker(session, endBlockers[1], "END_OVERLAP")
		return false
	end
	local direction = endGround - startGround
	if direction.Magnitude <= .05 then return true end
	-- Roblox rejects shape casts beyond 1,024 studs. A player can briefly be
	-- teleported back to the distant lobby before their round flags settle, so
	-- treat that impossible direct segment as blocked and let routing/retargeting
	-- handle the next tick instead of emitting an error every Heartbeat.
	if direction.Magnitude > 1000 then return false end
	local castCFrame, size = clearanceBox(startGround)
	local hit = workspace:Blockcast(castCFrame, size, direction, navigationParams(session))
	if hit then
		publishPhysicalBlocker(session, hit.Instance, "BLOCKCAST")
		return false
	end
	return true
end

local function navigationBlockersAt(session: any, groundPosition: Vector3,
	params: OverlapParams?): {BasePart}
	local blockers = overlappingNavigationParts(session, groundPosition, params)
	for _, exclusion in ipairs(furnitureNavExclusionsAt(session, groundPosition)) do
		table.insert(blockers, exclusion)
	end
	return blockers
end

local function volumeFits(session: any, groundPosition: Vector3, params: OverlapParams?): boolean
	return #navigationBlockersAt(session, groundPosition, params) == 0
end

volumeClear = function(session: any, startGround: Vector3, endGround: Vector3): boolean
	local overlapParams = navigationOverlapParams(session)
	if not volumeFits(session, startGround, overlapParams)
		or not volumeFits(session, endGround, overlapParams) then
		return false
	end
	local direction = endGround - startGround
	if direction.Magnitude <= .05 then return true end
	if segmentIntersectsFurnitureNavExclusion(session, startGround, endGround) then
		return false
	end
	return physicalVolumeClear(session, startGround, endGround)
end

-- LEVEL3_MANAGER_SAFE_GOAL_20260821
-- Room centers and sensed targets may land inside a banquet table's inflated
-- navigation envelope. Resolve them to the nearest reachable point on the
-- approach side so the graph fallback never orders the Manager back into the
-- obstacle it just escaped.
local function navigationPointClear(session: any, groundPosition: Vector3): boolean
	return volumeFits(session, groundPosition)
end

-- A clearance-resolved chase goal must stay on the target's reachable side of
-- a wall. Without this visibility gate, the cheapest ring point can be on the
-- Manager's side of the wall: it arrives, cannot attack through the wall, and
-- then waits there forever instead of asking PFS to route around. Horizontal
-- rays at torso/head heights ignore characters through navigationParams while
-- still respecting the live collidable world. Physical furniture remains part
-- of that world; its larger invisible navigation envelope is steering-only.
local function navigationGoalLineClear(session: any, fromGround: Vector3,
	toGround: Vector3): boolean
	for _, height in ipairs({2.2, 4.2, 6}) do
		local origin = fromGround + Vector3.new(0, height, 0)
		local target = toGround + Vector3.new(0, height, 0)
		if not workspace:Raycast(origin, target - origin, navigationParams(session)) then
			return true
		end
	end
	return false
end

-- LEVEL3_MANAGER_WALL_HUG_GOAL_20260827
-- The near rings keep a wall-hugging exposed player catchable. 4.2 sits inside
-- AttackRange (4.4) and clears the wall whenever the target root is >= ~1.05
-- studs from the face; 4.75 clears at the deepest physically possible hug
-- (root half-depth keeps centres >= ~0.5 from a face, and 4.75 + 0.5 >= the
-- 5.25 sweep half-extent) while staying inside AttackConfirmRange (5.4), which
-- beginAttack uses for initiation whenever the goal had to resolve away from
-- the target. Every candidate is still clearance-checked, so nothing here can
-- push the rig into a wall.
local SAFE_GOAL_RADII = {4.2, 4.75, 5.5, 7, 10, 13, 16, 20, 24}
local SAFE_GOAL_ANGLES = {
	0, 30, -30, 45, -45, 60, -60, 90, -90,
	120, -120, 135, -135, 150, -150, 180,
}
local function resolveNavigationGoal(session: any, desired: Vector3, reference: Vector3): Vector3
	if navigationPointClear(session, desired) then return desired end
	local approach = reference - desired
	if approach.Magnitude <= .05 then approach = -session.Heading end
	approach = approach.Unit
	local best: Vector3? = nil
	local bestScore = math.huge
	for _, radius in ipairs(SAFE_GOAL_RADII) do
		for _, degrees in ipairs(SAFE_GOAL_ANGLES) do
			local direction = CFrame.fromAxisAngle(
				Vector3.yAxis, math.rad(degrees)):VectorToWorldSpace(approach)
			local candidate = desired + direction * radius
			if navigationPointClear(session, candidate)
				and navigationGoalLineClear(session, candidate, desired) then
				local score = radius + planarDistance(reference, candidate) * .015
					+ math.abs(degrees) * .0005
				if volumeClear(session, reference, candidate) then score -= 1.5 end
				if score < bestScore then
					bestScore = score
					best = candidate
				end
			end
		end
		if best then break end
	end
	return best or desired
end

local function rebuildStrategicRoute(session: any, forceRebuild: boolean?)
	local finalGoal = session.FinalGoal
	local navigationGoal = session.ResolvedFinalGoal or finalGoal
	if not finalGoal or not navigationGoal then
		session.StrategicPoints = {}
		session.StrategicRooms = {}
		session.StrategicIndex = 1
		session.StrategicStartRoomId = nil
		session.StrategicGoalRoomId = nil
		return
	end
	if session.FinalHallChase then
		-- The finale is one straight, opened tunnel. Never route back through the
		-- Signal Hall room center before following the moving players.
		local previousGoal = session.StrategicPoints[1]
		if not previousGoal or planarDistance(previousGoal, navigationGoal) > .05 then
			session.StrategicGoalRevision += 1
		end
		session.StrategicPoints = {navigationGoal}
		session.StrategicRooms = {}
		session.StrategicIndex = 1
		session.StrategicStartRoomId = nil
		session.StrategicGoalRoomId = nil
		return
	end
	local startId = nearestRoomId(session.Root.Position)
	local goalId = nearestRoomId(finalGoal)
	-- LEVEL3_MANAGER_STRATEGIC_CACHE_20260827
	-- While the goal room is unchanged and the Manager is still on the cached
	-- room sequence, a moving target only replaces the final point; progress
	-- through the sequence never resets because the player moved inside their
	-- room.
	if not forceRebuild
		and session.StrategicGoalRoomId == goalId
		and #session.StrategicPoints > 0
		and session.StrategicIndex <= #session.StrategicPoints then
		local onRoute = startId == session.StrategicStartRoomId or startId == goalId
		if not onRoute then
			for _, roomId in ipairs(session.StrategicRooms) do
				if roomId == startId then
					onRoute = true
					break
				end
			end
		end
		if onRoute then
			local lastIndex = #session.StrategicPoints
			if planarDistance(session.StrategicPoints[lastIndex], navigationGoal) > .05 then
				session.StrategicGoalRevision += 1
			end
			session.StrategicPoints[lastIndex] = navigationGoal
			return
		end
	end
	session.StrategicRebuildSerial += 1
	session.StrategicGoalRevision += 1
	session.StrategicStartRoomId = startId
	session.StrategicGoalRoomId = goalId
	if startId == goalId then
		-- Same-room targets are chased directly from the current position; the
		-- room centre would only add a detour and reset progress.
		session.StrategicPoints = {navigationGoal}
		session.StrategicRooms = {goalId}
		session.StrategicIndex = 1
		return
	end
	local route = graphRoute(session, startId, goalId)
	local points = {}
	local pointRooms = {}
	local reference = flat(session.Root.Position, session.FloorY)
	local function appendPoint(point: Vector3?, roomId: string)
		if point and (#points == 0 or planarDistance(points[#points], point) > .05) then
			table.insert(points, point)
			table.insert(pointRooms, roomId)
			reference = point
		end
	end
	-- Route from the current position: the current room's own centre is
	-- skipped so a rebuild never orders the Manager backwards. Generated
	-- spawns and sensed goals may sit anywhere inside a room, so a blocked
	-- room center resolves to a clear point on the approach side.
	for index = 2, #route do
		local roomId = route[index]
		local center = roomCenter(roomId, session.FloorY)
		if center then
			appendPoint(resolveNavigationGoal(session, center, reference), roomId)
		end
	end
	appendPoint(navigationGoal, goalId)
	session.StrategicPoints = points
	session.StrategicRooms = pointRooms
	session.StrategicIndex = 1
end

-- Where the Manager will actually STOP for the current goal.
--
-- `FinalGoal` is what the brain asked for; `ResolvedFinalGoal` is where
-- navigation could legally stand, which `resolveNavigationGoal` displaces onto a
-- ring of up to 24 studs when the raw point is inside a wall or a furniture
-- exclusion. Every mover and the arrival test in `trackNavigationProgress` use
-- the resolved point, so anything asking "have we arrived?" has to use it too.
-- Comparing against the raw point instead is a silent freeze: the Manager parks
-- on the resolved point, the raw point stays several studs away, the goal is
-- never retired and no new one is ever chosen.
local function arrivalGoal(session: any): Vector3?
	return session.ResolvedFinalGoal or session.FinalGoal
end

local function setGoal(session: any, goal: Vector3?, force: boolean?)
	if not goal then
		clearGoal(session)
		return
	end
	local grounded = flat(goal, session.FloorY)
	local changed = not session.FinalGoal
		or planarDistance(session.FinalGoal, grounded) >= goalMoveThreshold(session)
	if not changed and not force then return end
	session.FinalGoal = grounded
	session.ResolvedFinalGoal = resolveNavigationGoal(
		session, grounded, flat(session.Root.Position, session.FloorY))
	rebuildStrategicRoute(session)
	-- A moving chase target must never tear down a route that is still safe to
	-- follow. Keep walking it while PathfindingService prepares a replacement,
	-- then swap the new route atomically.
	if session.Path or session.PathComputing then
		publishPathStatus(session, "REFRESH_PENDING")
	else
		clearPath(session, "DIRTY")
	end
end

local function currentDestination(session: any): Vector3?
	local finalGoal = session.FinalGoal
	local navigationGoal = session.ResolvedFinalGoal or finalGoal
	if not finalGoal or not navigationGoal then return nil end
	local currentGround = flat(session.Root.Position, session.FloorY)
	if planarDistance(currentGround, navigationGoal) <= Tuning.GoalTolerance then
		markPathValidated(session)
		return navigationGoal
	end
	local directRange = if session.Blackout then Tuning.BlackoutDirectPathRange else Tuning.DirectPathRange
	if planarDistance(currentGround, navigationGoal) <= directRange
		and volumeClear(session, currentGround, navigationGoal) then
		-- This clear segment bypasses the cached room-centre route. Retire those
		-- stale strategic objectives so progress is measured against the target we
		-- actually move toward, not a room centre now behind the Manager.
		session.StrategicIndex = #session.StrategicPoints + 1
		markPathValidated(session)
		return navigationGoal
	end
	-- Entering a routed room proves that room's centre point served its
	-- purpose; jump the strategic index forward so progress stays monotonic
	-- even when the Manager cuts a corner without touching the centre.
	if #session.StrategicPoints > 1 and session.StrategicIndex <= #session.StrategicPoints then
		local currentRoomId = roomIdContaining(currentGround)
		if currentRoomId then
			for index = #session.StrategicPoints, session.StrategicIndex, -1 do
				if session.StrategicRooms[index] == currentRoomId then
					local advanced = if index < #session.StrategicPoints then index + 1 else index
					session.StrategicIndex = math.max(session.StrategicIndex, advanced)
					break
				end
			end
		end
	end
	while session.StrategicIndex <= #session.StrategicPoints do
		local point = session.StrategicPoints[session.StrategicIndex]
		if planarDistance(currentGround, point) <= Tuning.GoalTolerance then
			session.PathFailures = 0
			session.ConsecutiveObstructions = 0
			session.StrategicIndex += 1
		else
			return point
		end
	end
	return navigationGoal
end

local function abandonFailedPatrol(session: any)
	if session.PathFailures >= Tuning.MaxPathFailures and session.State == "PATROL" then
		session.PatrolGoal = nil
		clearGoal(session)
	end
end

-- LEVEL3_MANAGER_PATH_PIPELINE_20260827
-- One ComputeAsync in flight, ever; a hard request floor that applies to
-- forced recovery callers too (blackout: 0.20s, at most five requests per
-- second); and coalesced moving-goal updates. A successful route is always
-- installed first — the freshest materially different goal then schedules
-- exactly one replacement computation instead of discarding the result.
local requestPath: (any, Vector3, boolean?) -> ()

-- Boundary slack for the half-open one-second request-rate window, so a burst
-- spaced exactly at the 0.20s floor cannot report a phantom sixth request from
-- os.clock rounding.
local PATH_RATE_CLOCK_TOLERANCE = 1e-3

local function schedulePathDispatch(session: any, delaySeconds: number)
	if session.PathDispatchScheduled then return end
	session.PathDispatchScheduled = true
	task.delay(math.max(delaySeconds, 0), function()
		session.PathDispatchScheduled = false
		if not liveSession(session) then return end
		local pending = session.PendingPathGoal
		if pending then
			requestPath(session, pending, session.PendingPathForce == true)
		end
	end)
end

local function dispatchPendingPath(session: any, computedDestination: Vector3)
	local pending = session.PendingPathGoal
	if not pending then return end
	if session.PendingPathForce ~= true
		and planarDistance(pending, computedDestination) < goalMoveThreshold(session) then
		-- The route just computed already serves this goal well enough; the
		-- movement loop re-requests once the target drifts a material amount.
		session.PendingPathGoal = nil
		session.PendingPathForce = false
		return
	end
	schedulePathDispatch(session,
		session.LastPathRequest + pathRequestInterval(session) - os.clock())
end

requestPath = function(session: any, destination: Vector3, force: boolean?)
	if not liveSession(session) then return end
	if session.PathComputing then
		-- Coalesce: keep only the newest goal while the single in-flight
		-- ComputeAsync finishes; it dispatches after the result installs.
		session.PendingPathGoal = destination
		session.PendingPathForce = session.PendingPathForce == true or force == true
		return
	end
	local now = os.clock()
	local interval = pathRequestInterval(session)
	local elapsed = now - session.LastPathRequest
	if elapsed < interval then
		-- The floor is the hard request-rate contract, so it binds forced
		-- recovery requests as well; the goal is queued, never dropped.
		session.PendingPathGoal = destination
		session.PendingPathForce = session.PendingPathForce == true or force == true
		schedulePathDispatch(session, interval - elapsed)
		return
	end
	if not force and session.Path and session.PathGoal
		and planarDistance(session.PathGoal, destination) < goalMoveThreshold(session) then
		return
	end
	session.PendingPathGoal = nil
	session.PendingPathForce = false
	session.LastPathRequest = now
	session.PathComputing = true
	session.InFlightPathGoal = destination
	session.PathComputeSerial += 1
	table.insert(session.PathComputeTimes, now)
	while #session.PathComputeTimes > 0 and now - session.PathComputeTimes[1] > 2 do
		table.remove(session.PathComputeTimes, 1)
	end
	session.PathToken += 1
	local token = session.PathToken
	-- Pathfinding positions represent the agent's ground contact, not the
	-- custom rig's 4.1-stud pivot. Using the pivot in a low tunnel makes the
	-- 10-stud agent appear to extend through the ceiling and returns NoPath.
	local origin = flat(session.Root.Position, session.FloorY)
		+ Vector3.new(0, Tuning.PathSampleHeight, 0)
	local target = destination + Vector3.new(0, Tuning.PathSampleHeight, 0)
	publishPathStatus(session, "COMPUTING")
	task.spawn(function()
		session.ActiveComputeCount += 1
		session.PeakComputeCount = math.max(session.PeakComputeCount, session.ActiveComputeCount)
		-- Furniture is physically present for the entire round, so its envelopes
		-- always participate in PathfindingService. This is unconditional now:
		-- the old Level3FurnitureCollisionSuppressed read let the planner route
		-- straight through tables during the hunt, which the shared 5.25-stud
		-- physical sweep then refused — the Manager stalled against furniture it
		-- had been told was not there.
		local furnitureCosts: {[string]: number} = {[Tuning.FurniturePathLabel] = math.huge}
		local path = PathfindingService:CreatePath({
			-- PFS is only the coarse planner. The shared 5.25-stud sweep remains
			-- authoritative; four studs avoids voxel-rounding NoPath in 14-stud halls.
			AgentRadius = Tuning.PathAgentRadius,
			AgentHeight = Tuning.AgentHeight,
			AgentCanJump = false,
			AgentCanClimb = false,
			WaypointSpacing = Tuning.WaypointSpacing,
			Costs = furnitureCosts,
		})
		local ok = pcall(function() path:ComputeAsync(origin, target) end)
		session.ActiveComputeCount -= 1
		session.PathComputing = false
		session.InFlightPathGoal = nil
		if not liveSession(session) or session.PathToken ~= token then
			if liveSession(session) and session.PendingPathGoal then
				schedulePathDispatch(session,
					session.LastPathRequest + pathRequestInterval(session) - os.clock())
			end
			return
		end
		if not ok or path.Status ~= Enum.PathStatus.Success then
			session.PathFailures += 1
			-- A failed refresh is not permission to discard the route currently
			-- carrying the Manager. Authored room-center steering remains available
			-- when no PathfindingService route has ever succeeded.
			publishPathStatus(session, if session.Path then "ROUTE_RETAINED" else "GRAPH_FALLBACK")
			abandonFailedPatrol(session)
			dispatchPendingPath(session, destination)
			return
		end
		local waypoints = path:GetWaypoints()
		if #waypoints < 2 then
			session.PathFailures += 1
			publishPathStatus(session, if session.Path then "ROUTE_RETAINED" else "GRAPH_FALLBACK")
			abandonFailedPatrol(session)
			dispatchPendingPath(session, destination)
			return
		end
		-- The old route continued during ComputeAsync. Find its nearest point across
		-- the complete replacement route, then accept only same/forward headings.
		-- This prevents a late path from sending the Manager back to its old origin.
		local currentGround = flat(session.Root.Position, session.FloorY)
		local goalDisplacement = destination - currentGround
		local destinationRequiresTurnaround = goalDisplacement.Magnitude > .05
			and goalDisplacement.Unit:Dot(session.Heading) < -.05
		local nearestIndex = 2
		local nearestDistance = math.huge
		-- Distance heuristic only: rank the raw PFS waypoints. Centreline
		-- projection (with full-segment revalidation) happens in the
		-- forward-accept loop below, so an invalid projection can never skew
		-- which waypoint counts as nearest.
		for index = 2, #waypoints do
			local candidate = flat(waypoints[index].Position, session.FloorY)
			local distanceToCandidate = planarDistance(currentGround, candidate)
			if distanceToCandidate < nearestDistance then
				nearestDistance = distanceToCandidate
				nearestIndex = index
			end
		end
		if nearestDistance <= Tuning.WaypointReachDistance * 1.5 and nearestIndex < #waypoints then
			nearestIndex += 1
		end
		local initialIndex: number? = nil
		local rebaseLookahead = if session.Blackout
			then Tuning.BlackoutPathLookaheadWaypoints else Tuning.PathLookaheadWaypoints
		local finalProbe = math.min(#waypoints, nearestIndex + rebaseLookahead - 1)
		for index = nearestIndex, finalProbe do
			local candidate = centerCorridorWaypoint(session,
				flat(waypoints[index].Position, session.FloorY), session.FloorY, true)
			local displacement = candidate - currentGround
			local forward = displacement.Magnitude <= Tuning.WaypointReachDistance * 1.5
				or session.CurrentMoveSpeed <= .5
				or destinationRequiresTurnaround
				or displacement.Unit:Dot(session.Heading) >= -.05
			if forward and volumeClear(session, currentGround, candidate) then
				initialIndex = index
			end
		end
		if not initialIndex and session.Path then
			publishPathStatus(session, "ROUTE_RETAINED")
			dispatchPendingPath(session, destination)
			return
		end
		initialIndex = initialIndex or nearestIndex
		disconnect(session.PathBlockedConnection)
		session.PathObject = path
		session.Path = waypoints
		session.WaypointIndex = initialIndex
		session.PathGoal = destination
		session.PathFailures = 0
		session.PathSwapSerial += 1
		local resolvedGoal = session.ResolvedFinalGoal or session.FinalGoal
		if not session.PathValidated and resolvedGoal
			and planarDistance(destination, resolvedGoal) <= Tuning.GoalTolerance then
			-- PFS deliberately plans with the slightly smaller PathAgentRadius to
			-- avoid voxel-rounding NoPath in authored halls. Before calling the
			-- route genuinely validated, replay every accepted segment through the
			-- exact production sweep used by local steering, including the final
			-- endpoint. This is performed only until validation succeeds.
			local authoritativeRouteClear = true
			local routePosition = currentGround
			for index = initialIndex, #waypoints do
				local routePoint = centerCorridorWaypoint(session,
					flat(waypoints[index].Position, session.FloorY), session.FloorY, true)
				if not volumeClear(session, routePosition, routePoint) then
					authoritativeRouteClear = false
					break
				end
				routePosition = routePoint
			end
			if authoritativeRouteClear and volumeClear(session, routePosition, destination) then
				markPathValidated(session)
			end
		end
		session.PathBlockedConnection = path.Blocked:Connect(function(blockedIndex)
			if liveSession(session) and blockedIndex >= session.WaypointIndex then
				session.PathFailures += 1
				publishPathStatus(session, "BLOCKED_REFRESH")
				local replacementGoal = currentDestination(session)
				if replacementGoal then requestPath(session, replacementGoal, true) end
				abandonFailedPatrol(session)
			end
		end)
		publishPathStatus(session, "READY")
		dispatchPendingPath(session, destination)
	end)
end

local function sightParams(session: any, targetCharacter: Model): RaycastParams
	local params = RaycastParams.new()
	params.FilterType = Enum.RaycastFilterType.Exclude
	local ignored: {Instance} = {session.Model}
	for _, player in ipairs(Players:GetPlayers()) do
		local character = player.Character
		if character and character ~= targetCharacter then table.insert(ignored, character) end
	end
	-- Navigation envelopes are invisible steering metadata, not physical sight
	-- blockers. The real furniture parts remain queryable and still block LOS.
	for _, exclusion in ipairs(session.FurnitureNavExclusions or {}) do
		table.insert(ignored, exclusion)
	end
	params.FilterDescendantsInstances = ignored
	params.IgnoreWater = true
	return params
end

local function hasSightRay(session: any, character: Model, targetRoot: BasePart): boolean
	local origin = session.Root.Position + Vector3.new(0, 3.35, 0)
	local head = character:FindFirstChild("Head")
	local targets = {
		if head and head:IsA("BasePart") then head.Position else targetRoot.Position + Vector3.new(0, 1.8, 0),
		targetRoot.Position,
		targetRoot.Position - Vector3.new(0, 2.1, 0),
	}
	local params = sightParams(session, character)
	for _, target in ipairs(targets) do
		local result = workspace:Raycast(origin, target - origin, params)
		if not result or result.Instance:IsDescendantOf(character) then return true end
	end
	return false
end

local function flashlightOn(character: Model): boolean
	local flag = character:FindFirstChild("FlashlightOn")
	return flag ~= nil and flag:IsA("BoolValue") and flag.Value
end

local function visionGeometry(session: any, player: Player): (boolean, number, BasePart?)
	local character, _, root = livingPlayer(player, session)
	if not character or not root then return false, math.huge, nil end
	local activeProfile = profile(session)
	local distance = planarDistance(session.Root.Position, root.Position)
	local range = activeProfile.VisionRange
	if flashlightOn(character) then range *= activeProfile.FlashlightVisibilityMultiplier end
	if distance > range then return false, distance, root end
	if distance > activeProfile.ProximitySenseRange then
		local offset = Vector3.new(root.Position.X - session.Root.Position.X, 0,
			root.Position.Z - session.Root.Position.Z)
		if offset.Magnitude <= .01 then return true, distance, root end
		local facing = session.Heading
		local minimumDot = math.cos(math.rad(activeProfile.FieldOfViewDegrees * .5))
		if facing:Dot(offset.Unit) < minimumDot then return false, distance, root end
	end
	return hasSightRay(session, character, root), distance, root
end

local function acquireVisibleTarget(session: any, dt: number): (Player?, BasePart?)
	local bestPlayer: Player? = nil
	local bestRoot: BasePart? = nil
	local bestScore = math.huge
	local activeProfile = profile(session)
	local present: {[Player]: boolean} = {}
	for _, player in ipairs(Players:GetPlayers()) do
		local character, _, root = livingPlayer(player, session)
		if character and root then
			present[player] = true
			local visible, distance = visionGeometry(session, player)
			local suspicion = session.Suspicion[player] or 0
			if visible then
				local lightBonus = if flashlightOn(character) then 1.35 else 1
				local distanceBonus = 1 + math.clamp(1 - distance / activeProfile.VisionRange, 0, 1) * .45
				suspicion = math.clamp(suspicion
					+ dt / activeProfile.AcquireSeconds * lightBonus * distanceBonus, 0, 1)
			else
				suspicion = math.max(0, suspicion - dt / activeProfile.SuspicionDecaySeconds)
			end
			session.Suspicion[player] = suspicion
			local acquired = visible and (
				player == session.Target
				or suspicion >= 1
				or distance <= activeProfile.ProximitySenseRange
			)
			if acquired then
				local score = distance
				- (if player == session.Target then Tuning.RetargetDistanceAdvantage else 0)
				- (if flashlightOn(character) then 8 else 0)
				- suspicion * 4
				+ player.UserId * 1e-8
				if score < bestScore then
					bestScore = score
					bestPlayer = player
					bestRoot = root
				end
			end
		end
	end
	for player in pairs(session.Suspicion) do
		if not present[player] then session.Suspicion[player] = nil end
	end
	return bestPlayer, bestRoot
end

local function soundOccluded(session: any, character: Model, targetRoot: BasePart): boolean
	local origin = session.Root.Position + Vector3.new(0, 2.4, 0)
	local result = workspace:Raycast(origin, targetRoot.Position - origin, sightParams(session, character))
	return result ~= nil and not result.Instance:IsDescendantOf(character)
end

local function acquireHeardTarget(session: any): (Player?, BasePart?)
	local activeProfile = profile(session)
	local bestPlayer: Player? = nil
	local bestRoot: BasePart? = nil
	local bestScore = math.huge
	for _, player in ipairs(Players:GetPlayers()) do
		local character, humanoid, root = livingPlayer(player, session)
		if character and humanoid and root then
			local velocity = Vector3.new(root.AssemblyLinearVelocity.X, 0, root.AssemblyLinearVelocity.Z).Magnitude
			if velocity >= 2 then
				local hearingRange: number
				-- WalkSpeed is authored by the owning client for responsive movement and
				-- does not reliably mirror back to the server. Crouch State Server owns
				-- this replicated attribute, so hearing uses the same validated state
				-- that every client uses to render the crouched player.
				-- Measured speed is the anti-spoof backstop: a client cannot keep
				-- crouch-range hearing while actually sprinting at a forged speed.
				if player:GetAttribute("Crouching") == true and velocity <= 11 then
					hearingRange = activeProfile.HearingWalkRange * Tuning.CrouchHearingMultiplier
				elseif velocity >= 20 or humanoid.WalkSpeed >= 24 then
					hearingRange = activeProfile.HearingSprintRange
				else
					hearingRange = activeProfile.HearingWalkRange
				end
				if soundOccluded(session, character, root) then
					hearingRange *= activeProfile.OccludedHearingMultiplier
				end
				local distance = planarDistance(session.Root.Position, root.Position)
				if distance <= hearingRange then
					local score = distance / math.max(hearingRange, 1)
						- (if player == session.Target then .18 else 0)
						+ player.UserId * 1e-10
					if score < bestScore then
						bestScore = score
						bestPlayer = player
						bestRoot = root
					end
				end
			end
		end
	end
	return bestPlayer, bestRoot
end

local function chooseWorldNoise(session: any, now: number): Vector3?
	local record = session.WorldNoise
	if not record or now - record.Time > Tuning.NoiseLifetimeSeconds then return nil end
	local activeProfile = profile(session)
	local range = activeProfile.HearingSprintRange * record.Strength
	if planarDistance(session.Root.Position, record.Position) <= range then return record.Position end
	return nil
end

local function clampSearchPoint(session: any, position: Vector3): Vector3
	local roomId = nearestRoomId(position)
	local room = roomDefinition(roomId)
	if not room then return flat(position, session.FloorY) end
	local center = roomCenter(roomId, session.FloorY) :: Vector3
	local margin = Tuning.AgentRadius + 2
	local minX, maxX = center.X - room.W * .5 + margin, center.X + room.W * .5 - margin
	local minZ, maxZ = center.Z - room.D * .5 + margin, center.Z + room.D * .5 - margin
	return Vector3.new(math.clamp(position.X, minX, maxX), session.FloorY,
		math.clamp(position.Z, minZ, maxZ))
end

local function chooseSearchGoal(session: any, now: number)
	local base = session.LastKnownPosition or flat(session.Root.Position, session.FloorY)
	local angle = session.Random:NextNumber(0, math.pi * 2)
	local radius = session.Random:NextNumber(5, Tuning.SearchPointRadius)
	local candidate = base + Vector3.new(math.cos(angle) * radius, 0, math.sin(angle) * radius)
	session.SearchNextAt = now + session.Random:NextNumber(1.8, 3.1)
	setGoal(session, clampSearchPoint(session, candidate), true)
end

local function blackoutSweepLegDuration(distance: number): number
	local directTravelSeconds = math.max(0, distance)
		/ math.max(Tuning.Blackout.PatrolSpeed, .1)
	return math.max(Tuning.BlackoutSweepLegSeconds,
		directTravelSeconds * Tuning.BlackoutSweepDistanceFactor
			+ Tuning.BlackoutSweepSlackSeconds)
end

-- Which occupied table, if any, this sweep leg should aim at. Three independent
-- gates keep the Manager from being omniscient: table checks can be off, the
-- global interval has to have elapsed, and the bias only wins a coin flip
-- (TableCheck.SweepBiasChance). A table on per-anchor cooldown is never a
-- candidate, so the same hiding place is not farmed.
local function chooseTableCheckAnchor(session: any, now: number): BasePart?
	if debugTableChecksSuspended then return nil end
	-- Nothing may be aimed at before the spawn grace has elapsed; the Manager is
	-- still being revealed, and Controller.Start seeds a route on that frame.
	if now < session.ActivatedAt then return nil end
	if now < session.NextTableCheckAt then return nil end
	local candidates = {}
	for _, anchor in ipairs(HidingController.GetOccupiedAnchors(session.Generation)) do
		if now >= (session.AnchorCheckCooldown[anchor] or 0) then
			table.insert(candidates, anchor)
		end
	end
	-- The coin flip is drawn only when there is something to bias toward, so a
	-- round where nobody hides consumes exactly the RNG stream it always did.
	if #candidates == 0 then return nil end
	if session.Random:NextNumber() > TableCheckTuning.SweepBiasChance then return nil end
	return candidates[session.Random:NextInteger(1, #candidates)]
end

-- A leg aimed at a table that never arrived still costs that table its cooldown.
-- Only beginTableCheck clears TargetAnchor on success, so a TargetAnchor still
-- set when the next goal is chosen means the last attempt was abandoned -- the
-- leg timed out, or the chase reclaimed the Manager. Without charging it here,
-- the very next draw can pick the same unreachable anchor (the global interval
-- is only consumed by an actual check), and the sweep ping-pongs at one table
-- instead of covering the mall. Charged BEFORE the next draw, so that draw
-- filters it out; charging at selection time would make updateTableCheck reject
-- the anchor it had just chosen.
local function abandonTableCheckTarget(session: any, now: number)
	local anchor = session.TableCheckTargetAnchor
	if not anchor then return end
	session.TableCheckTargetAnchor = nil
	session.AnchorCheckCooldown[anchor] = now + TableCheckTuning.AnchorCooldownSeconds
end

local function choosePatrolGoal(session: any, now: number)
	abandonTableCheckTarget(session, now)
	local checkAnchor = chooseTableCheckAnchor(session, now)
	if checkAnchor then
		-- Same sweep-leg bookkeeping as an ordinary room goal, so the distance
		-- and leg-timeout escapes below still rescue a table the Manager cannot
		-- actually reach.
		session.TableCheckTargetAnchor = checkAnchor
		session.PatrolGoal = flat(checkAnchor.Position, session.FloorY)
		session.PatrolWaitUntil = nil
		session.PatrolLegUntil = now + blackoutSweepLegDuration(
			planarDistance(session.Root.Position, session.PatrolGoal))
		setGoal(session, session.PatrolGoal, true)
		publishState(session, "PATROL")
		return
	end
	local candidates = {}
	for _, room in ipairs(layoutRooms()) do
		if room.Id ~= "Arrival" and room.Id ~= "Exit" then
			local recentlyUsed = false
			for _, recentId in ipairs(session.RecentPatrolRooms) do
				if recentId == room.Id then recentlyUsed = true break end
			end
			if not recentlyUsed then table.insert(candidates, room.Id) end
		end
	end
	if #candidates == 0 then
		table.clear(session.RecentPatrolRooms)
		return choosePatrolGoal(session, now)
	end
	local roomId = candidates[session.Random:NextInteger(1, #candidates)]
	table.insert(session.RecentPatrolRooms, roomId)
	while #session.RecentPatrolRooms > 4 do table.remove(session.RecentPatrolRooms, 1) end
	local room = roomDefinition(roomId)
	local center = roomCenter(roomId, session.FloorY) :: Vector3
	local rangeX = math.min(12, room.W * .18)
	local rangeZ = math.min(12, room.D * .18)
	session.PatrolGoal = Vector3.new(
		center.X + session.Random:NextNumber(-rangeX, rangeX),
		session.FloorY,
		center.Z + session.Random:NextNumber(-rangeZ, rangeZ)
	)
	session.PatrolWaitUntil = nil
	session.PatrolLegUntil = now + blackoutSweepLegDuration(
		planarDistance(session.Root.Position, session.PatrolGoal))
	setGoal(session, session.PatrolGoal, true)
	publishState(session, "PATROL")
end

local function nearestExposedPlayer(session: any): (Player?, BasePart?)
	local selected: Player? = nil
	local selectedRoot: BasePart? = nil
	local bestDistance = math.huge
	for _, candidate in ipairs(Players:GetPlayers()) do
		local _, _, candidateRoot = livingPlayer(candidate, session)
		if candidateRoot then
			local distance = planarDistance(session.Root.Position, candidateRoot.Position)
			if distance < bestDistance - .001
				or (math.abs(distance - bestDistance) <= .001
					and (not selected or candidate.UserId < selected.UserId)) then
				selected = candidate
				selectedRoot = candidateRoot
				bestDistance = distance
			end
		end
	end
	return selected, selectedRoot
end

-- LEVEL3_MANAGER_TABLE_CHECK_20260904
-- The hunt is co-extensive with the blackout, and the blackout branch of the
-- brain returns before the whole patrol half, so choosePatrolGoal's sweep bias
-- only ever runs in a round where EVERY living player is hidden. One teammate
-- still out running would otherwise make hiding perfectly safe for everyone
-- else -- the feature would be inert in exactly the case it exists for. This is
-- the same leg, taken mid-hunt.
--
-- It is only ever taken toward a table that is CLOSER than the nearest exposed
-- player, so the Manager never turns away from a chase it is about to win, and
-- the detour is dropped the moment that stops being true. Note the coin flip in
-- chooseTableCheckAnchor only staggers the start here (a failed draw is retried
-- on the next think tick); the rate limits that make hiding a real tactic are
-- TableCheck.GlobalIntervalSeconds and the per-anchor cooldown.
local function tableCheckDetour(session: any, now: number, exposedDistance: number): boolean
	local anchor = session.TableCheckTargetAnchor
	if anchor then
		if anchor.Parent
			and HidingController.OccupantCount(anchor) > 0
			and (session.PatrolLegUntil == nil or now < session.PatrolLegUntil)
			and planarDistance(session.Root.Position, anchor.Position) < exposedDistance then
			-- Steering already owns the goal; only the state has to be held.
			publishState(session, "PATROL")
			return true
		end
		abandonTableCheckTarget(session, now)
		session.PatrolGoal = nil
		return false
	end
	if session.Attacking then return false end
	anchor = chooseTableCheckAnchor(session, now)
	if not anchor
		or planarDistance(session.Root.Position, anchor.Position) >= exposedDistance then
		return false
	end
	session.TableCheckTargetAnchor = anchor
	session.PatrolGoal = flat(anchor.Position, session.FloorY)
	session.PatrolWaitUntil = nil
	session.PatrolLegUntil = now + blackoutSweepLegDuration(
		planarDistance(session.Root.Position, session.PatrolGoal))
	publishTarget(session, nil)
	setGoal(session, session.PatrolGoal, true)
	publishState(session, "PATROL")
	publishTargetTelemetry(session, "TABLE_CHECK_DETOUR", exposedDistance, session.PatrolGoal)
	return true
end

local function trackNearestBlackoutPlayer(session: any, now: number): boolean
	local nearestPlayer, nearestRoot = nearestExposedPlayer(session)
	if not nearestPlayer or not nearestRoot then
		if session.Attacking then
			session.AttackToken += 1
			session.Attacking = false
			session.AttackCooldownUntil = now
		end
		publishTarget(session, nil)
		session.LastKnownPosition = nil
		session.LastSenseAt = -math.huge
		session.SearchUntil = nil
		-- LEVEL3_FURNITURE_PERMANENCE_20260828
		-- Everyone is hidden. This used to clearGoal() and publish the STRING
		-- "SEARCH" while holding no destination, so the Manager stood on the spot
		-- with a walk animation playing until somebody came out -- and because the
		-- blackout branch returns before the whole patrol/search half of the brain,
		-- nothing downstream could ever give it one. It now sweeps the mall for
		-- real: hidden players stay excluded from targeting and from attacks (that
		-- is `nearestExposedPlayer` above and `attackLineClear` below, both
		-- unchanged), but the hunt keeps moving over them.
		local sweepGoal = arrivalGoal(session)
		if session.PatrolGoal and (not sweepGoal
			or planarDistance(session.Root.Position, sweepGoal) <= Tuning.GoalTolerance + 1) then
			session.PatrolGoal = nil
		end
		-- Second, independent reason to move on: a sweep leg that has taken longer
		-- than any honest walk across the mall is stuck, whether or not the
		-- distance test agrees. Without this the hunt can still stall on a goal
		-- navigation quietly gave up on.
		if session.PatrolGoal and session.PatrolLegUntil and now >= session.PatrolLegUntil then
			session.PatrolGoal = nil
		end
		if not session.PatrolGoal then
			choosePatrolGoal(session, now)
		else
			publishState(session, "PATROL")
		end
		publishTargetTelemetry(session, "NO_EXPOSED_PLAYER", -1, nil)
		return false
	end

	local exposedDistance = planarDistance(session.Root.Position, nearestRoot.Position)
	-- Somebody is still out there, but a table with people under it is nearer:
	-- take the check on the way. Re-evaluated every think tick, so the chase
	-- reclaims the Manager as soon as the runner is the closer of the two.
	if tableCheckDetour(session, now, exposedDistance) then return false end

	local switchedTarget = session.Target ~= nearestPlayer
	if switchedTarget and session.Attacking then
		-- A nearer player owns the chase immediately. Cancel the old windup so the
		-- Manager never attacks a player it is no longer pursuing.
		session.AttackToken += 1
		session.Attacking = false
		session.AttackCooldownUntil = now
	end
	publishTarget(session, nearestPlayer)

	local targetPosition = flat(nearestRoot.Position, session.FloorY)
	local velocity = Vector3.new(nearestRoot.AssemblyLinearVelocity.X, 0,
		nearestRoot.AssemblyLinearVelocity.Z)
	local lead = velocity * Tuning.BlackoutTargetLeadSeconds
	if lead.Magnitude > Tuning.BlackoutTargetLeadMaximumDistance then
		lead = lead.Unit * Tuning.BlackoutTargetLeadMaximumDistance
	end
	local predicted = targetPosition + lead
	if volumeFits(session, predicted) then targetPosition = predicted end

	session.LastKnownPosition = targetPosition
	session.LastSenseAt = now
	session.LastVisualAt = now
	session.SearchUntil = nil
	session.PatrolGoal = nil
	session.AlertUntil = 0
	setGoal(session, targetPosition, switchedTarget)

	publishTargetTelemetry(session, "NEAREST_PLAYER", exposedDistance, targetPosition)
	if not session.Attacking then publishState(session, "CHASE") end
	return true
end

local function redirectHiddenTarget(session: any, hiddenPlayer: Player, now: number)
	session.Suspicion[hiddenPlayer] = nil
	session.AttackToken += 1
	session.Attacking = false
	session.AttackCooldownUntil = now
	publishTarget(session, nil)
	session.LastKnownPosition = nil
	session.LastSenseAt = -math.huge
	session.LastVisualAt = -math.huge
	session.SearchUntil = nil
	session.PatrolGoal = nil
	local replacement, replacementRoot = nearestExposedPlayer(session)
	if replacement and replacementRoot then
		publishTarget(session, replacement)
		session.LastKnownPosition = flat(replacementRoot.Position, session.FloorY)
		session.LastSenseAt = now
		session.LastVisualAt = now
		publishState(session, "CHASE")
		setGoal(session, session.LastKnownPosition, true)
	else
		choosePatrolGoal(session, now)
	end
end

local function beginSearch(session: any, now: number)
	publishTarget(session, nil)
	session.SearchUntil = now + profile(session).SearchSeconds
	session.SearchNextAt = 0
	publishState(session, "SEARCH")
	chooseSearchGoal(session, now)
end

local function dormant(session: any, stateName: string)
	publishTarget(session, nil)
	session.LastKnownPosition = nil
	session.LastSenseAt = -math.huge
	session.AlertUntil = 0
	session.SearchUntil = nil
	session.PatrolGoal = nil
	session.CurrentMoveSpeed = 0
	session.LastActualStepDistance = 0
	clearGoal(session)
	publishState(session, stateName)
	if stateName == "PAUSED" then
		holdWalkPose(session)
	else
		setWalk(session, false, 0)
	end
end

local function updateBrain(session: any, now: number, dt: number)
	if not validRound(session) then
		dormant(session, if workspace:GetAttribute("EntityPaused") == true then "PAUSED" else "WAITING")
		return
	end
	if now < session.ActivatedAt then
		publishTarget(session, nil)
		clearGoal(session)
		publishState(session, "AWAKENING")
		return
	end
	-- During the blackout hunt the Manager is supernatural: every think tick it
	-- chooses the nearest eligible player and feeds that moving position straight
	-- into the existing strategic/PFS route system. Normal non-blackout behavior
	-- still uses sight, suspicion, hearing, memory, and search below.
	if session.Blackout then
		trackNearestBlackoutPlayer(session, now)
		return
	end
	if session.Target and HidingController.IsHidden(session.Target, session.Generation) then
		redirectHiddenTarget(session, session.Target, now)
		return
	end
	if session.Attacking then return end

	local seenPlayer, seenRoot = acquireVisibleTarget(session, dt)
	if seenPlayer and seenRoot then
		local newlyAcquired = session.Target ~= seenPlayer
		local wasPursuing = session.Target ~= nil and (
			session.State == "CHASE" or session.State == "TRACKING" or session.State == "INVESTIGATE")
		publishTarget(session, seenPlayer)
		local sensedPosition = flat(seenRoot.Position, session.FloorY)
		if session.Blackout then
			local velocity = Vector3.new(seenRoot.AssemblyLinearVelocity.X, 0, seenRoot.AssemblyLinearVelocity.Z)
			local lead = velocity * Tuning.BlackoutTargetLeadSeconds
			if lead.Magnitude > Tuning.BlackoutTargetLeadMaximumDistance then
				lead = lead.Unit * Tuning.BlackoutTargetLeadMaximumDistance
			end
			local predicted = sensedPosition + lead
			if volumeFits(session, predicted) then sensedPosition = predicted end
		end
		session.LastKnownPosition = sensedPosition
		session.LastSenseAt = now
		session.LastVisualAt = now
		session.SearchUntil = nil
		session.PatrolGoal = nil
		if newlyAcquired and not wasPursuing then
			session.AlertUntil = now + profile(session).AlertSeconds
		elseif wasPursuing then
			session.AlertUntil = 0
		end
		if now < session.AlertUntil then
			clearGoal(session)
			publishState(session, "ALERT")
		else
			publishState(session, "CHASE")
			setGoal(session, session.LastKnownPosition)
		end
		return
	end

	local heardPlayer, heardRoot = acquireHeardTarget(session)
	if heardPlayer and heardRoot then
		local preserveChase = session.State == "CHASE" and session.Target == heardPlayer
			and now - session.LastVisualAt <= Tuning.ChaseVisualLossGraceSeconds
		publishTarget(session, heardPlayer)
		session.LastKnownPosition = flat(heardRoot.Position, session.FloorY)
		session.LastSenseAt = now
		session.SearchUntil = nil
		session.PatrolGoal = nil
		publishState(session, if preserveChase then "CHASE" else "INVESTIGATE")
		setGoal(session, session.LastKnownPosition)
		return
	end

	-- Door frames and sharp corners can hide a target for one or two perception
	-- ticks. Continue the established chase toward only the last genuinely seen
	-- point for a short grace window instead of oscillating between speed states.
	if session.State == "CHASE" and session.Target and session.LastKnownPosition
		and now - session.LastVisualAt <= Tuning.ChaseVisualLossGraceSeconds then
		publishState(session, "CHASE")
		setGoal(session, session.LastKnownPosition)
		return
	end

	local worldNoise = chooseWorldNoise(session, now)
	if worldNoise then
		publishTarget(session, nil)
		session.LastKnownPosition = flat(worldNoise, session.FloorY)
		session.LastSenseAt = session.WorldNoise.Time
		session.SearchUntil = nil
		session.PatrolGoal = nil
		publishState(session, "INVESTIGATE")
		setGoal(session, session.LastKnownPosition)
		return
	end

	if session.LastKnownPosition and now - session.LastSenseAt <= profile(session).MemorySeconds then
		if planarDistance(session.Root.Position, session.LastKnownPosition) <= Tuning.GoalTolerance + 1 then
			beginSearch(session, now)
		else
			publishState(session, "TRACKING")
			setGoal(session, session.LastKnownPosition)
		end
		return
	end

	if session.LastKnownPosition then
		if not session.SearchUntil then beginSearch(session, now) end
		if session.SearchUntil and now < session.SearchUntil then
			publishState(session, "SEARCH")
			if now >= session.SearchNextAt
				or not session.FinalGoal
				or planarDistance(session.Root.Position, session.FinalGoal) <= Tuning.GoalTolerance then
				chooseSearchGoal(session, now)
			end
			return
		end
		session.LastKnownPosition = nil
		session.SearchUntil = nil
	end

	publishTarget(session, nil)
	local reachedPatrol = arrivalGoal(session)
	if session.PatrolGoal and (not reachedPatrol
		or planarDistance(session.Root.Position, reachedPatrol) <= Tuning.GoalTolerance + 1) then
		if not session.PatrolWaitUntil then
			session.PatrolWaitUntil = now + Tuning.PatrolPauseSeconds
			clearGoal(session)
		end
		if now < session.PatrolWaitUntil then
			publishState(session, "PATROL_LISTEN")
			return
		end
		session.PatrolGoal = nil
	end
	if not session.PatrolGoal then choosePatrolGoal(session, now) end
end

local function facePosition(session: any, position: Vector3)
	if not session.Model.Parent then return end
	local current = session.Root.Position
	local direction = Vector3.new(position.X - current.X, 0, position.Z - current.Z)
	if direction.Magnitude <= .01 then return end
	session.Heading = direction.Unit
	session.Root.CFrame = CFrame.lookAt(current, current + session.Heading)
end

local function endTableCheck(session: any, flush: boolean)
	local anchor = session.TableCheckAnchor
	session.TableCheckAnchor = nil
	session.TableCheckEndsAt = 0
	if session.TableCheckSound then
		session.TableCheckSound:Destroy()
		session.TableCheckSound = nil
	end
	publishTableCheck(session, nil, 0)
	if not anchor then return end
	session.AnchorCheckCooldown[anchor] = os.clock() + TableCheckTuning.AnchorCooldownSeconds
	if flush and anchor.Parent then
		-- Everyone still under the table comes out on the far side, with the
		-- immunity the Hiding Controller grants them. Leaving during the window
		-- was the safe option; this is the consequence of not taking it.
		HidingController.FlushAnchor(anchor, session.Root.Position)
	end
end

local function beginTableCheck(session: any, anchor: BasePart, now: number)
	session.TableCheckAnchor = anchor
	-- The reaction window is the one clock a player is SHOWN -- the client counts
	-- its banner down against this exact number -- and os.clock is CPU time in the
	-- server datamodel, materially behind the wall clock. Measuring the window on
	-- os.clock while publishing a server-time deadline would show a 2.0 s promise
	-- and enforce something else. The internal rate limits stay on os.clock, like
	-- every other cooldown in this file: nobody is shown those.
	session.TableCheckEndsAt = workspace:GetServerTimeNow()
		+ TableCheckTuning.ReactionWindowSeconds
	session.NextTableCheckAt = now + TableCheckTuning.GlobalIntervalSeconds
	session.TableCheckTargetAnchor = nil
	clearGoal(session)
	facePosition(session, anchor.Position)
	-- currentSpeed() returns 0 for TABLE_CHECK, so updateMovement holds the rig
	-- still and stops the walk cycle for the whole window. That stationary beat
	-- IS the crouch; the client smoother has no animation hook to drive.
	publishState(session, "TABLE_CHECK")
	publishTableCheck(session, anchor, session.TableCheckEndsAt)
	local soundId = Configuration.Audio[TableCheckTuning.SoundName]
	if type(soundId) == "string" and soundId ~= "" then
		local cue = Instance.new("Sound")
		cue.Name = "Level3MallManagerTableCheck"
		cue.SoundId = soundId
		cue.Volume = TableCheckTuning.SoundVolume
		cue.Looped = false
		cue.RollOffMode = Enum.RollOffMode.InverseTapered
		cue.RollOffMinDistance = TableCheckTuning.SoundRollOffMinDistance
		cue.RollOffMaxDistance = TableCheckTuning.SoundRollOffMaxDistance
		cue.Parent = anchor
		cue:Play()
		session.TableCheckSound = cue
	end
end

-- Returns true while a check owns the Manager: the brain, the attack test and
-- ordinary steering all stand down for the reaction window.
local function updateTableCheck(session: any, now: number): boolean
	if session.TableCheckAnchor then
		if not validRound(session) or not session.TableCheckAnchor.Parent then
			endTableCheck(session, false)
			return false
		end
		-- Server time: TableCheckEndsAt is the value the occupants' banner counts
		-- down against, so the flush lands when the warning says it will.
		if workspace:GetServerTimeNow() < session.TableCheckEndsAt then return true end
		endTableCheck(session, true)
		return false
	end
	if debugTableChecksSuspended or not validRound(session) then return false end
	if now < session.ActivatedAt then return false end
	-- Only a sweep may turn into a check. A chase or an attack is never
	-- interrupted by a table the Manager happens to walk past.
	if session.State ~= "PATROL" and session.State ~= "PATROL_LISTEN" then return false end
	local anchor = session.TableCheckTargetAnchor
	if not anchor or not anchor.Parent
		or HidingController.OccupantCount(anchor) <= 0
		or now < (session.AnchorCheckCooldown[anchor] or 0) then
		session.TableCheckTargetAnchor = nil
		return false
	end
	if planarDistance(session.Root.Position, anchor.Position) > TableCheckTuning.StartRange then
		return false
	end
	beginTableCheck(session, anchor, now)
	return true
end

local function attackLineClear(session: any, player: Player, maximumRange: number): (boolean, Humanoid?)
	if HidingController.IsHidden(player, session.Generation) then return false, nil end
	-- A flushed player gets a head start, never an instant kill: the Manager can
	-- chase and be right on top of them, but the attack itself is refused.
	if HidingController.IsFlushImmune(player) then return false, nil end
	local character, humanoid, root = livingPlayer(player, session)
	if not character or not humanoid or not root then return false, nil end
	if planarDistance(session.Root.Position, root.Position) > maximumRange
		or math.abs(session.Root.Position.Y - root.Position.Y) > Tuning.VerticalAttackTolerance then
		return false, humanoid
	end
	return hasSightRay(session, character, root), humanoid
end

local function beginAttack(session: any, player: Player)
	if session.Attacking or os.clock() < session.AttackCooldownUntil then return end
	-- LEVEL3_MANAGER_WALL_HUG_ATTACK_20260827
	-- When the chase goal had to resolve away from the target (the target's
	-- own clearance volume is blocked — pressed against a wall), the Manager
	-- legitimately parks up to one resolved ring outside AttackRange. Initiate
	-- from the existing AttackConfirmRange in that case; the confirm range,
	-- windup, and line-of-sight ray still gate the actual kill, so a wall
	-- between the two continues to block attacks.
	local initiationRange = Tuning.AttackRange
	if session.FinalGoal and session.ResolvedFinalGoal
		and planarDistance(session.FinalGoal, session.ResolvedFinalGoal) > 1 then
		initiationRange = Tuning.AttackConfirmRange
	end
	local clear = attackLineClear(session, player, initiationRange)
	if not clear then return end
	session.Attacking = true
	session.AttackToken += 1
	local attackToken = session.AttackToken
	publishState(session, "ATTACK_WINDUP")
	local _, _, targetRoot = livingPlayer(player, session)
	if targetRoot then facePosition(session, targetRoot.Position) end
	local windup = if session.Blackout then Tuning.BlackoutAttackWindupSeconds else Tuning.AttackWindupSeconds
	task.delay(windup, function()
		if not liveSession(session) or session.AttackToken ~= attackToken then return end
		local confirmed, humanoid = attackLineClear(session, player, Tuning.AttackConfirmRange)
		if confirmed and humanoid and humanoid.Health > 0 then
			session.AttackSerial += 1
			session.StateFolder:SetAttribute("Level3_MallManagerAttackSerial", session.AttackSerial)
			session.StateFolder:SetAttribute("Level3_MallManagerLastCaptureUserId", player.UserId)
			if session.Model.Parent then
				session.Model:SetAttribute("Level3_MallManagerAttackSerial", session.AttackSerial)
				session.Model:SetAttribute("Level3_MallManagerLastCaptureUserId", player.UserId)
			end
			humanoid.Health = 0
			session.LastKnownPosition = nil
			session.LastSenseAt = -math.huge
			publishTarget(session, nil)
		end
		session.Attacking = false
		local recovery = if session.Blackout
			then Tuning.BlackoutAttackRecoverySeconds else Tuning.AttackRecoverySeconds
		session.AttackCooldownUntil = os.clock() + recovery
		if validRound(session) then
			publishState(session, if confirmed then "SEARCH" else "RECOVER")
		else
			dormant(session, "WAITING")
		end
	end)
end

local function movementWaypoint(session: any, destination: Vector3, speed: number, dt: number): Vector3?
	local currentGround = flat(session.Root.Position, session.FloorY)
	if not session.Path or not session.PathObject then
		-- Strategic destinations are adjacent authored room centers. A full-volume
		-- clear sweep is a real centerline fallback even when the segment is long.
		if volumeClear(session, currentGround, destination) then
			local resolvedGoal = session.ResolvedFinalGoal or session.FinalGoal
			if resolvedGoal and planarDistance(destination, resolvedGoal)
				<= Tuning.GoalTolerance then
				markPathValidated(session)
			end
			return destination
		end
		requestPath(session, destination)
		-- Keep advancing only through a verified short clear segment while the
		-- first route computes; this removes the visible path-acquisition pause.
		local offset = destination - currentGround
		if offset.Magnitude > .05 then
			local probeDistance = math.min(offset.Magnitude,
				math.max(2, speed * math.min(dt, Tuning.MaximumMovementDeltaSeconds) * 3))
			local probe = currentGround + offset.Unit * probeDistance
			if volumeClear(session, currentGround, probe) then return probe end
		end
		return nil
	end

	local dynamicReach = math.max(Tuning.WaypointReachDistance,
		speed * math.min(dt, Tuning.MaximumMovementDeltaSeconds) * 1.5)
	while session.WaypointIndex <= #session.Path do
		local waypoint = session.Path[session.WaypointIndex]
		-- Consumption must revalidate too: an invalid centreline projection
		-- falls back to the original PFS point, so a blocked projection can
		-- never make a still-distant waypoint look reached.
		local originalPosition = flat(waypoint.Position, session.FloorY)
		local position = movementProjectedWaypoint(session, currentGround, originalPosition)
		-- A projected point may only make a PFS waypoint look reached when the
		-- Manager's actual approach segment to that projection is clear as well.
		-- Retained/original waypoints keep the normal PFS consumption behavior;
		-- this extra check is specifically for the lateral centering preference.
		if planarDistance(currentGround, position) <= dynamicReach then
			session.WaypointIndex += 1
		else
			break
		end
	end
	if session.WaypointIndex <= #session.Path then
		-- Small four-stud PFS zigzags made the visual rig twitch. Follow the
		-- furthest clearance-checked point in a short lookahead window instead.
		-- Every candidate runs the one shared clearance contract (physical
		-- sweep plus state-aware furniture envelopes) and keeps its original
		-- PFS waypoint when the centreline projection is blocked.
		local bestIndex = session.WaypointIndex
		local originalBestPosition = flat(session.Path[bestIndex].Position, session.FloorY)
		local bestPosition = movementProjectedWaypoint(
			session, currentGround, originalBestPosition)
		local lookahead = if session.Blackout
			then Tuning.BlackoutPathLookaheadWaypoints else Tuning.PathLookaheadWaypoints
		local maximumIndex = math.min(#session.Path,
			session.WaypointIndex + lookahead - 1)
		for index = session.WaypointIndex + 1, maximumIndex do
			local candidate = centerCorridorWaypoint(session,
				flat(session.Path[index].Position, session.FloorY), session.FloorY, true)
			if volumeClear(session, currentGround, candidate) then
				bestIndex = index
				bestPosition = candidate
			else
				break
			end
		end
		session.WaypointIndex = bestIndex
		if session.Model and session.Model.Parent then
			session.Model:SetAttribute("Level3_MallManagerWaypointTarget", bestPosition)
		end
		return bestPosition
	end
	if volumeClear(session, currentGround, destination) then
		local resolvedGoal = session.ResolvedFinalGoal or session.FinalGoal
		if resolvedGoal and planarDistance(destination, resolvedGoal)
			<= Tuning.GoalTolerance then
			markPathValidated(session)
		end
		return destination
	end
	if session.PathComputing then
		publishPathStatus(session, "WAITING_FOR_REPLACEMENT")
		return nil
	end
	clearPath(session, "FINAL_SEGMENT_BLOCKED")
	requestPath(session, destination, true)
	return nil
end

local function resetBlockedRoute(session: any, now: number)
	-- Navigation recovery only resets progress bookkeeping. It never rewinds,
	-- teleports, or changes the rendered transform.
	--
	-- LEVEL3_MANAGER_ESCALATION_SURVIVES_RECOVERY_20260827
	-- This deliberately does NOT clear OverlapEscapeAttempts. Recovery fires
	-- after ObstructionRecoveryAttempts refused steering frames — the very
	-- frames the overlap ladder uses to escalate — so clearing it here made the
	-- exhausted branch unreachable and produced an endless reset/repath loop.
	-- The ladder now resets only where genuine improvement is proven: standing
	-- clear of the overlap, a renewal backed by a measurable blocker or
	-- goal-distance gain.
	--
	-- LastProgressAt is the stuck-timer baseline and is intentionally rearmed
	-- so recovery gets a fresh window; LastGenuineProgressAt is left untouched
	-- so recovery can never masquerade as movement in telemetry.
	session.LastProgressAt = now
	session.ProgressObjectiveKey = nil
	session.ProgressBestDistance = math.huge
	session.ProgressCreditedDistance = math.huge
	session.PathFailures = 0
	session.ConsecutiveObstructions = 0
	session.RecoveryRepaths += 1
	publishPathStatus(session, "RECOVERY_REPATH")
end

-- LEVEL3_MANAGER_FURNITURE_NAV_20260821
-- LEVEL3_MANAGER_OVERLAP_COMMIT_20260821
-- LEVEL3_MANAGER_OVERLAP_LIFETIME_20260827
-- Commit to one side of a wide obstacle and explicitly walk out of an already
-- overlapping clearance volume. Every escape attempt has a fixed
-- AvoidanceCommitSeconds deadline and must earn a measurable blocker-count or
-- goal-distance improvement to be renewed; otherwise a new clearance-checked
-- direction is chosen. Once ObstructionRecoveryAttempts directions have been
-- replaced without a reduction, further local retries are rate-limited to one
-- per commit window while the refused steps drive obstruction recovery
-- repaths. The escalation ladder survives those recovery repaths — it resets
-- only when the Manager stands fully outside the overlap or a renewal proves
-- a real blocker/goal-distance reduction — so route-index bookkeeping can
-- never silently defeat the escalation it is meant to trigger.
local AVOIDANCE_MAGNITUDES = {15, 30, 45, 70, 90, 120}

-- Shared minimum credited gain for both the escape ladder's goal-distance
-- baseline and the stuck tracker's cumulative distance checkpoint.
local PROGRESS_DISTANCE_EPSILON = .25

local function setAvoidanceTelemetry(session: any, overlapEscape: boolean)
	session.OverlapEscapeActive = overlapEscape
	if session.Model and session.Model.Parent then
		session.Model:SetAttribute("Level3_MallManagerAvoidanceSign", session.AvoidanceSign)
		session.Model:SetAttribute("Level3_MallManagerOverlapEscapeActive", overlapEscape)
	end
end

local function avoidanceOrder(session: any, desired: Vector3, now: number): {number}
	local committed = session.AvoidanceSign ~= 0 and now < session.AvoidanceUntil
	local preferredSign = session.AvoidanceSign
	if not committed then
		local cross = session.Heading:Cross(desired).Y
		if math.abs(cross) > .04 then
			preferredSign = if cross >= 0 then 1 else -1
		else
			preferredSign = if session.SpawnCycle % 2 == 0 then 1 else -1
		end
	end
	local ordered = {}
	for _, magnitude in ipairs(AVOIDANCE_MAGNITUDES) do
		table.insert(ordered, preferredSign * magnitude)
		table.insert(ordered, -preferredSign * magnitude)
	end
	return ordered
end

-- An escape direction is usable while its probe strictly reduces the blocker
-- count, or holds it while genuinely moving toward the goal. Blocker counts
-- come from the shared contract, so non-collidable furniture envelopes count
-- exactly when their furniture is physically present.
local function escapeDirectionUsable(session: any, currentGround: Vector3, direction: Vector3,
	desired: Vector3, probeDistance: number, blockerCount: number): boolean
	local remaining = #navigationBlockersAt(session, currentGround + direction * probeDistance)
	if remaining < blockerCount then return true end
	return remaining <= blockerCount and direction:Dot(desired) > .25
end

local function overlapEscapeDirection(session: any, currentGround: Vector3, desired: Vector3,
	distance: number, blockers: {BasePart}, now: number): Vector3?
	local away = Vector3.zero
	for _, blocker in ipairs(blockers) do
		local delta = currentGround - flat(blocker.Position, session.FloorY)
		if delta.Magnitude > .05 then away += delta.Unit end
	end
	if away.Magnitude <= .05 then away = -desired end
	away = away.Unit
	local probeDistance = math.max(distance, Tuning.OverlapEscapeProbeDistance)
	local bestDirection: Vector3? = nil
	local bestScore = -math.huge
	local candidates = {0, 20, -20, 45, -45, 75, -75, 110, -110, 180}
	for _, degrees in ipairs(candidates) do
		local direction = CFrame.fromAxisAngle(
			Vector3.yAxis, math.rad(degrees)):VectorToWorldSpace(away)
		local probe = currentGround + direction * probeDistance
		local remaining = #navigationBlockersAt(session, probe)
		local acceptable = remaining < #blockers
			or (remaining <= #blockers and direction:Dot(desired) > .25)
		if acceptable then
			local score = (#blockers - remaining) * 25
				+ direction:Dot(away) * 4
				+ direction:Dot(desired) * .30
				+ direction:Dot(session.Heading) * .15
			if score > bestScore then
				bestScore = score
				bestDirection = direction
			end
		end
	end
	if bestDirection then
		local cross = desired:Cross(bestDirection).Y
		session.AvoidanceSign = if cross >= 0 then 1 else -1
		session.AvoidanceUntil = now + Tuning.AvoidanceCommitSeconds
		setAvoidanceTelemetry(session, true)
	end
	return bestDirection
end

local function clearSteeringStep(session: any, currentGround: Vector3, desired: Vector3,
	distance: number, now: number): (Vector3?, Vector3?)
	local blockers = navigationBlockersAt(session, currentGround)
	if #blockers > 0 then
		local probeDistance = math.max(distance, Tuning.OverlapEscapeProbeDistance)
		local goalPoint = session.ResolvedFinalGoal or session.FinalGoal
		-- Freeze the goal for one escape attempt. Measuring against the live
		-- player position lets a player moving toward an embedded, motionless
		-- Manager look like successful escape progress and reset the ladder.
		local baselineGoalPoint = session.OverlapEscapeBaselineGoalPoint or goalPoint
		local goalDistance = if baselineGoalPoint
			then planarDistance(currentGround, baselineGoalPoint) else math.huge
		local escapeDirection = session.OverlapEscapeDirection
		if escapeDirection then
			-- Fixed deadline per attempt, then a measurable-improvement test.
			local expired = now - session.OverlapEscapeStartedAt >= Tuning.AvoidanceCommitSeconds
			local reducedBlockers = #blockers < session.OverlapEscapeBaselineBlockers
			local closedOnGoal = goalDistance
				<= session.OverlapEscapeBaselineGoalDistance - PROGRESS_DISTANCE_EPSILON
			if not escapeDirectionUsable(session, currentGround, escapeDirection,
				desired, probeDistance, #blockers) then
				escapeDirection = nil
			elseif expired then
				if reducedBlockers or closedOnGoal then
					-- The attempt earned its deadline: renew it as a fresh bounded
					-- attempt against the current baselines. A direction that keeps
					-- delivering measurable gains also clears the ladder.
					session.OverlapEscapeStartedAt = now
					session.OverlapEscapeBaselineBlockers = #blockers
					session.OverlapEscapeBaselineGoalPoint = goalPoint
					session.OverlapEscapeBaselineGoalDistance = if goalPoint
						then planarDistance(currentGround, goalPoint) else math.huge
					session.OverlapEscapeAttempts = 0
				else
					-- Deadline hit with nothing measurable to show for it.
					escapeDirection = nil
				end
			end
		end
		if not escapeDirection then
			if session.OverlapEscapeAttempts > Tuning.ObstructionRecoveryAttempts
				and now < session.OverlapEscapeNextRetryAt then
				-- Escalation exhausted. Refuse the step so obstruction recovery
				-- repaths, and rate-limit further direction searches to one per
				-- commit window. This stays bounded while still recovering on its
				-- own if the geometry later opens up.
				session.OverlapEscapeDirection = nil
				setAvoidanceTelemetry(session, false)
				return nil, nil
			end
			-- The ladder state is clamped one step past exhaustion so telemetry
			-- stays bounded; OverlapEscapeSearches carries the honest total.
			session.OverlapEscapeAttempts = math.min(session.OverlapEscapeAttempts + 1,
				Tuning.ObstructionRecoveryAttempts + 1)
			session.OverlapEscapeSearches += 1
			session.OverlapEscapeNextRetryAt = now + Tuning.AvoidanceCommitSeconds
			escapeDirection = overlapEscapeDirection(
				session, currentGround, desired, distance, blockers, now)
			if escapeDirection then
				session.OverlapEscapeStartedAt = now
				session.OverlapEscapeBaselineBlockers = #blockers
				session.OverlapEscapeBaselineGoalPoint = goalPoint
				session.OverlapEscapeBaselineGoalDistance = if goalPoint
					then planarDistance(currentGround, goalPoint) else math.huge
			elseif session.OverlapEscapeAttempts >= Tuning.ObstructionRecoveryAttempts then
				-- The Nth failed search is itself exhaustion. Do not wait for an
				-- (N+1)th steering frame: obstruction recovery clears the current
				-- route on this same frame, so there may be no movement target left
				-- to call clearSteeringStep again. Publish the bounded exhausted
				-- sentinel immediately; later retries remain commit-window limited.
				session.OverlapEscapeAttempts = Tuning.ObstructionRecoveryAttempts + 1
			end
		end
		if escapeDirection then
			session.OverlapEscapeDirection = escapeDirection
			setAvoidanceTelemetry(session, true)
			return currentGround + escapeDirection * distance, escapeDirection
		end
		setAvoidanceTelemetry(session, false)
		return nil, nil
	end

	if session.OverlapEscapeDirection or session.OverlapEscapeAttempts > 0 then
		-- Standing fully clear of the overlap is the primary proof the ladder
		-- is done: end the attempt and hand control back to goal-directed
		-- steering. Productive attempts reset at their measured deadline above;
		-- ordinary progress bookkeeping and obstruction repaths leave it standing.
		resetOverlapEscapeState(session)
	end
	setAvoidanceTelemetry(session, false)

	local committed = session.AvoidanceSign ~= 0 and now < session.AvoidanceUntil
	local straight = currentGround + desired * distance
	local straightClear = volumeClear(session, currentGround, straight)
	if straightClear and not committed then
		session.AvoidanceSign = 0
		return straight, desired
	end

	local bestPosition: Vector3? = if straightClear then straight else nil
	local bestDirection: Vector3? = if straightClear then desired else nil
	local bestDegrees = 0
	local bestScore = if straightClear then 2 + desired:Dot(session.Heading) * .35 else -math.huge
	for _, degrees in ipairs(avoidanceOrder(session, desired, now)) do
		local candidateDirection = CFrame.fromAxisAngle(
			Vector3.yAxis, math.rad(degrees)):VectorToWorldSpace(desired)
		local candidate = currentGround + candidateDirection * distance
		if volumeClear(session, currentGround, candidate) then
			local sameCommittedSide = committed
				and math.sign(degrees) == session.AvoidanceSign
			local score = candidateDirection:Dot(desired) * 2
				+ candidateDirection:Dot(session.Heading) * .35
				- math.abs(degrees) * .001
				+ (if sameCommittedSide then .55 else 0)
			if score > bestScore then
				bestScore = score
				bestPosition = candidate
				bestDirection = candidateDirection
				bestDegrees = degrees
			end
		end
	end
	if bestDirection and bestDegrees ~= 0 then
		session.AvoidanceSign = math.sign(bestDegrees)
		session.AvoidanceUntil = now + Tuning.AvoidanceCommitSeconds
		setAvoidanceTelemetry(session, false)
	elseif not committed then
		session.AvoidanceSign = 0
	end
	return bestPosition, bestDirection
end

-- LEVEL3_MANAGER_PROGRESS_TRACKER_20260827
-- Stuck detection runs on every movement branch — waiting on a path, missing
-- waypoint, obstruction recovery and normal stepping alike. Progress means
-- route consumption (waypoint or strategic index advancing on the same route)
-- or genuinely closing on the active movement objective; raw displacement is
-- deliberately not a signal, so lateral circling cannot feed it.
--
-- LEVEL3_MANAGER_CUMULATIVE_PROGRESS_20260827
-- Distance progress is measured with two fields, never one. ProgressBestDistance
-- is the raw closest approach to the current objective; ProgressCreditedDistance
-- is a checkpoint that only moves when a gain is actually credited. A single
-- field silently swallowed every sub-epsilon frame: at PatrolSpeed 4.5 (~0.075
-- studs per 60 Hz frame) or InvestigateSpeed 13 (~0.217) no frame ever clears
-- 0.25 on its own, so the baseline crept along with the rig and a genuinely
-- moving Manager false-triggered STUCK_REPATH every StuckSeconds. Holding the
-- checkpoint until cumulative gain reaches the epsilon credits that motion.
local function progressObjective(session: any, destination: Vector3): (string, Vector3)
	if session.Path and session.WaypointIndex <= #session.Path then
		return string.format("waypoint:%d:%d", session.PathSwapSerial, session.WaypointIndex),
			flat(session.Path[session.WaypointIndex].Position, session.FloorY)
	end
	if session.StrategicIndex <= #session.StrategicPoints then
		-- The cached route deliberately follows a moving player by replacing its
		-- final point. Include that point's revision only while it is the active
		-- objective: target motion then rebases the checkpoint instead of being
		-- misreported as Manager movement, while intermediate room points remain
		-- stable and continue accumulating sub-epsilon progress normally.
		local goalRevision = if session.StrategicIndex == #session.StrategicPoints
			then session.StrategicGoalRevision else 0
		return string.format("strategic:%d:%d:%d",
			session.StrategicRebuildSerial, session.StrategicIndex, goalRevision),
			session.StrategicPoints[session.StrategicIndex]
	end
	-- Direct-clear routing retires the cached strategic points and falls through
	-- here. Include the final-goal revision as well: otherwise a player moving
	-- toward a motionless Manager lowers distance under the constant "goal" key
	-- and is falsely credited as Manager movement.
	return string.format("goal:%d", session.StrategicGoalRevision), destination
end

-- Genuine movement progress, and the only place that says so. Recovery
-- bookkeeping rearms LastProgressAt (the stuck-timer baseline) but can never
-- reach LastGenuineProgressAt or GenuineProgressSerial, so telemetry and tests
-- can tell a moving Manager from one that merely repathed on the spot.
local function noteNavigationProgress(session: any, now: number)
	session.LastProgressAt = now
	session.LastGenuineProgressAt = now
	session.GenuineProgressSerial += 1
	session.PathFailures = 0
	session.ConsecutiveObstructions = 0
	-- Do not reset the overlap ladder here. Route/waypoint consumption is valid
	-- navigation progress but can occur without physical motion when PFS rebases
	-- a trapped rig. Escape state is cleared only by the exact overlap contract:
	-- a free volume, or a deadline renewal backed by measurable improvement.
end

local function trackNavigationProgress(session: any, now: number, destination: Vector3)
	local currentGround = flat(session.Root.Position, session.FloorY)
	local navigationGoal = session.ResolvedFinalGoal or session.FinalGoal
	if navigationGoal and planarDistance(currentGround, navigationGoal) <= Tuning.GoalTolerance then
		-- Arrived at the resolved navigation goal. Holding position here is the
		-- brain's decision (attack range, search cadence, moving-goal refresh),
		-- not a navigation failure for the stuck ladder to fight.
		session.LastProgressAt = now
		session.ProgressObjectiveKey = nil
		session.ProgressBestDistance = math.huge
		session.ProgressCreditedDistance = math.huge
		return
	end
	local progressed = false
	if session.PathSwapSerial == session.ProgressLastPathSwapSerial
		and session.WaypointIndex > session.ProgressLastWaypointIndex then
		progressed = true
	end
	if session.StrategicRebuildSerial == session.ProgressLastStrategicRebuildSerial
		and session.StrategicIndex > session.ProgressLastStrategicIndex then
		progressed = true
	end
	session.ProgressLastPathSwapSerial = session.PathSwapSerial
	session.ProgressLastWaypointIndex = session.WaypointIndex
	session.ProgressLastStrategicRebuildSerial = session.StrategicRebuildSerial
	session.ProgressLastStrategicIndex = session.StrategicIndex

	local key, target = progressObjective(session, destination)
	local distance = planarDistance(currentGround, target)
	if key ~= session.ProgressObjectiveKey then
		-- A deliberate rebase: the objective itself changed (new route, next
		-- waypoint, moved target), and advancing onto it was already credited
		-- through the index signals above.
		session.ProgressObjectiveKey = key
		session.ProgressBestDistance = distance
		session.ProgressCreditedDistance = distance
	else
		-- Raw best tracks the closest approach; the credited checkpoint holds
		-- still until the accumulated gain against it clears the epsilon, so a
		-- run of sub-epsilon frames adds up instead of being discarded.
		if distance < session.ProgressBestDistance then
			session.ProgressBestDistance = distance
		end
		if session.ProgressCreditedDistance - session.ProgressBestDistance
			>= PROGRESS_DISTANCE_EPSILON then
			session.ProgressCreditedDistance = session.ProgressBestDistance
			progressed = true
		end
	end

	if progressed then
		noteNavigationProgress(session, now)
		return
	end
	if now - session.LastProgressAt < Tuning.StuckSeconds then return end
	-- No genuine progress across a whole stuck interval: repath, escalating to
	-- a full recovery with a fresh strategic route when failures pile up.
	session.LastProgressAt = now
	session.StuckRecoveries += 1
	session.PathFailures += 1
	local exhausted = session.PathFailures >= Tuning.MaxPathFailures
	clearPath(session, "STUCK_REPATH")
	if exhausted then
		resetBlockedRoute(session, now)
		rebuildStrategicRoute(session, true)
	end
	requestPath(session, destination, true)
end

local function updateMovement(session: any, dt: number, now: number)
	if session.DebugMovementPaused == true then
		session.CurrentMoveSpeed = 0
		session.LastActualStepDistance = 0
		setWalk(session, false, 0)
		-- Studio regression fixtures freeze only the transform. Keep the real
		-- destination/progress bookkeeping alive so a moving target cannot receive
		-- an unearned progress credit merely because the test paused locomotion.
		local pausedDestination = currentDestination(session)
		if pausedDestination then
			trackNavigationProgress(session, now, pausedDestination)
		end
		return
	end
	if not validRound(session) then
		session.CurrentMoveSpeed = 0
		session.LastActualStepDistance = 0
		setWalk(session, false, 0)
		return
	end
	local desiredSpeed = currentSpeed(session)
	local destination = currentDestination(session)
	if desiredSpeed <= 0 or not destination then
		-- Nothing to move toward: hold the stuck timer open rather than
		-- accusing a deliberately idle Manager of being stuck.
		session.CurrentMoveSpeed = 0
		session.LastActualStepDistance = 0
		session.LastProgressAt = now
		session.ProgressObjectiveKey = nil
		session.ProgressBestDistance = math.huge
		session.ProgressCreditedDistance = math.huge
		setWalk(session, false, 0)
		return
	end

	-- Refresh a moving target's route in the background. requestPath leaves the
	-- current route intact until the replacement succeeds.
	local goalMoveThreshold = if session.Blackout
		then Tuning.BlackoutPathGoalMoveThreshold else Tuning.PathGoalMoveThreshold
	if session.PathGoal and planarDistance(session.PathGoal, destination) >= goalMoveThreshold then
		requestPath(session, destination)
	end
	local currentGround = flat(session.Root.Position, session.FloorY)
	local currentBlockers = navigationBlockersAt(session, currentGround)
	if #currentBlockers == 0
		and (session.OverlapEscapeDirection or session.OverlapEscapeAttempts > 0) then
		-- Clear the ladder as soon as the actual occupied volume is free. This
		-- cannot live only inside clearSteeringStep: when the resolved goal is
		-- already within the tiny-target cutoff, updateMovement returns before
		-- steering and would otherwise leave exhausted telemetry/state latched.
		resetOverlapEscapeState(session)
	end
	local movementTarget: Vector3?
	if #currentBlockers > 0 then
		-- Overlap escape must run even while PFS is pending, returned no usable
		-- waypoint, or consumed a tiny first waypoint at the current position.
		-- Previously those branches returned before clearSteeringStep, producing an
		-- endless COMPUTING/READY/FINAL_SEGMENT_BLOCKED loop without one escape
		-- search. Give steering a goal-facing direction (or the current heading
		-- when already at the resolved goal); its overlap logic chooses the actual
		-- clearance-improving direction and owns bounded escalation.
		movementTarget = destination
		if planarDistance(currentGround, movementTarget) <= .05 then
			movementTarget = currentGround + session.Heading
				* math.max(1, Tuning.OverlapEscapeProbeDistance)
		end
	else
		movementTarget = movementWaypoint(session, destination, desiredSpeed, dt)
	end
	if not movementTarget then
		session.CurrentMoveSpeed = 0
		session.LastActualStepDistance = 0
		setWalk(session, false, 0)
		trackNavigationProgress(session, now, destination)
		return
	end
	local offset = movementTarget - currentGround
	if offset.Magnitude <= .05 then
		session.CurrentMoveSpeed = 0
		session.LastActualStepDistance = 0
		setWalk(session, false, 0)
		trackNavigationProgress(session, now, destination)
		return
	end

	local motionDt = math.min(dt, Tuning.MaximumMovementDeltaSeconds)
	local currentMoveSpeed = session.CurrentMoveSpeed
	local acceleration = if session.Blackout then Tuning.BlackoutMovementAcceleration else Tuning.MovementAcceleration
	local deceleration = if session.Blackout then Tuning.BlackoutMovementDeceleration else Tuning.MovementDeceleration
	local rate = if desiredSpeed >= currentMoveSpeed then acceleration else deceleration
	local maximumChange = rate * motionDt
	currentMoveSpeed += math.clamp(desiredSpeed - currentMoveSpeed, -maximumChange, maximumChange)
	session.CurrentMoveSpeed = math.max(0, currentMoveSpeed)

	local direction = offset.Unit
	local distance = math.min(offset.Magnitude, session.CurrentMoveSpeed * motionDt)
	local proposed, steeredDirection = clearSteeringStep(
		session, currentGround, direction, distance, now)
	if distance <= .001 or not proposed or not steeredDirection then
		session.ConsecutiveObstructions += 1
		local exhausted = session.ConsecutiveObstructions >= Tuning.ObstructionRecoveryAttempts
		if exhausted then
			clearPath(session, "OBSTRUCTION_REPATH")
			resetBlockedRoute(session, now)
		else
			publishPathStatus(session, "LOCAL_AVOIDANCE_WAIT")
		end
		requestPath(session, destination, true)
		session.LastActualStepDistance = 0
		setWalk(session, false, 0)
		trackNavigationProgress(session, now, destination)
		return
	end
	direction = steeredDirection

	local turnRate = if session.Blackout
		then Tuning.BlackoutTurnResponsiveness else Tuning.TurnResponsiveness
	local blend = math.clamp(1 - math.exp(-turnRate * motionDt), 0, 1)
	local heading = session.Heading
	local signedAngle = math.atan2(heading:Cross(direction).Y,
		math.clamp(heading:Dot(direction), -1, 1))
	local rotated = CFrame.fromAxisAngle(Vector3.yAxis, signedAngle * blend):VectorToWorldSpace(heading)
	session.Heading = if rotated.Magnitude > .01 then rotated.Unit else direction

	local rootPosition = proposed + Vector3.new(0, session.GroundOffset, 0)
	session.Root.CFrame = CFrame.lookAt(rootPosition, rootPosition + session.Heading)
	session.LastActualStepDistance = distance
	setWalk(session, true, session.CurrentMoveSpeed)
	-- The tracker owns every escalation-counter reset: a step that merely
	-- displaces the rig sideways no longer counts as progress.
	trackNavigationProgress(session, now, destination)
end

local function applyBlackout(session: any, active: boolean)
	if not liveSession(session) or session.Blackout == active then
		if liveSession(session) then publishProfile(session) end
		return
	end
	session.Blackout = active
	-- Speed and awareness swap immediately, but the geometry and agent size do
	-- not. Preserve the current route so the blackout edge cannot cause a hitch.
	if session.Path then publishPathStatus(session, "PROFILE_CHANGED_CONTINUING") end
	publishProfile(session)
	publishState(session, session.State)
end

local function resetPublishedState()
	local state = stateFolder()
	state:SetAttribute("Level3_MallManagerActive", false)
	state:SetAttribute("Level3_MallManagerState", "OFF")
	state:SetAttribute("Level3_MallManagerBlackoutBoosted", false)
	state:SetAttribute("Level3_MallManagerTargetUserId", 0)
	state:SetAttribute("Level3_MallManagerTargetMode", "NONE")
	state:SetAttribute("Level3_MallManagerTargetDistance", -1)
	state:SetAttribute("Level3_MallManagerTargetPosition", nil)
	state:SetAttribute("Level3_MallManagerSpeed", 0)
	state:SetAttribute("Level3_MallManagerAwarenessRange", 0)
	state:SetAttribute("Level3_MallManagerSpawnRoomId", Tuning.SpawnRoomId)
	state:SetAttribute("Level3_MallManagerSpawnDistance", 0)
	state:SetAttribute("Level3_MallManagerSpawnVisibleCount", 0)
	state:SetAttribute("Level3_MallManagerSpawnClearanceValidated", false)
	state:SetAttribute("Level3_MallManagerPathValidated", false)
	state:SetAttribute("Level3_MallManagerFinaleSpawn", false)
	state:SetAttribute("Level3_MallManagerSpawnPosition", nil)
	state:SetAttribute("Level3_MallManagerPathStatus", "OFF")
	state:SetAttribute("Level3_MallManagerAttackSerial", 0)
	state:SetAttribute("Level3_MallManagerLastCaptureUserId", 0)
	state:SetAttribute("Level3_MallManagerFootstepSerial", 0)
	state:SetAttribute("Level3_MallManagerLastFootstepIndex", 0)
	state:SetAttribute("Level3_MallManagerLastFootstepName", "")
	state:SetAttribute("Level3_MallManagerLastFootstepPhase", 0)
	state:SetAttribute("Level3_MallManagerChaseScreamSerial", 0)
	state:SetAttribute("Level3_MallManagerChaseScreamPlaying", false)
	state:SetAttribute("Level3_MallManagerLastChaseScreamAtServerTime", 0)
	state:SetAttribute("Level3_MallManagerLastChaseScreamName", "")
	state:SetAttribute("Level3_MallManagerTableCheckIndex", 0)
	state:SetAttribute("Level3_MallManagerTableCheckEndsAt", 0)
	workspace:SetAttribute("Level3MallManagerActive", false)
	workspace:SetAttribute("Level3MallManagerState", "OFF")
	workspace:SetAttribute("Level3MallManagerBlackoutBoosted", false)
end

function Controller.Stop()
	local session = activeSession
	activeSession = nil
	activeLayout = nil
	if session then
		session.Active = false
		session.PathToken += 1
		session.AttackToken += 1
		for _, connection in ipairs(session.Connections) do disconnect(connection) end
		table.clear(session.Connections)
		disconnect(session.PathBlockedConnection)
		session.PathBlockedConnection = nil
		if session.Target and session.Target.Parent == Players
			and session.Target:GetAttribute("BeingChased") == true then
			session.Target:SetAttribute("BeingChased", false)
		end
		stopChaseScream(session)
		stopWalkForCleanup(session)
		-- An in-flight table check dies with the round: no flush, no lingering
		-- cue at a table that is about to be destroyed.
		if session.TableCheckSound then
			session.TableCheckSound:Destroy()
			session.TableCheckSound = nil
		end
		session.TableCheckAnchor = nil
		session.TableCheckTargetAnchor = nil
		session.TableCheckEndsAt = 0
		if session.AnchorCheckCooldown then table.clear(session.AnchorCheckCooldown) end
		if session.Model and session.Model.Parent then
			CollectionService:RemoveTag(session.Model, "Level3HostileEntity")
			session.Model:Destroy()
		end
	end
	for _, player in ipairs(Players:GetPlayers()) do
		if player:GetAttribute("BeingChased") == true
			and workspace:GetAttribute("SelectedLevel") == 3 then
			player:SetAttribute("BeingChased", false)
		end
	end
	resetPublishedState()
end

local function loadWalk(model: Model): AnimationTrack?
	local controller = model:FindFirstChildOfClass("AnimationController")
	local animator = controller and controller:FindFirstChildOfClass("Animator")
	local animations = requireAsset(ServerStorage, "Level3Assets", "EntityAnimations", "MallManager")
	local walk = requireAsset(animations, "Walk")
	assert(animator and animator:IsA("Animator"), "Mall Manager template is missing AnimationController.Animator")
	assert(walk:IsA("Animation") and walk.AnimationId ~= "", "Mall Manager Walk animation reference is missing")
	local ok, result = pcall(function() return animator:LoadAnimation(walk) end)
	if not ok then
		warn("[Level 3 Mall Manager] Walk animation failed to load: " .. tostring(result))
		return nil
	end
	local track = result :: AnimationTrack
	track.Looped = true
	track.Priority = Enum.AnimationPriority.Movement
	return track
end

local function eligibleSpawnPlayers(): {any}
	local records = {}
	if workspace:GetAttribute("SelectedLevel") ~= 3 or workspace:GetAttribute("RoundActive") ~= true then
		return records
	end
	for _, player in ipairs(Players:GetPlayers()) do
		if player:GetAttribute("InRound") == true and player:GetAttribute("Escaped") ~= true then
			local character = player.Character
			local humanoid = character and character:FindFirstChildOfClass("Humanoid")
			local root = character and character:FindFirstChild("HumanoidRootPart")
			if character and character.Parent and humanoid and humanoid.Health > 0
				and root and root:IsA("BasePart") then
				table.insert(records, {Player=player, Character=character, Root=root, Position=root.Position})
			end
		end
	end
	return records
end

local function chooseDenseGroup(records: {any}, random: Random): ({any}, any, Vector3)
	local bestMembers = {}
	local bestTotal = math.huge
	for _, seed in ipairs(records) do
		local members = {}
		local total = 0
		for _, candidate in ipairs(records) do
			local distance = planarDistance(seed.Position, candidate.Position)
			if distance <= Tuning.SpawnGroupRadius then
				table.insert(members, candidate)
				total += distance
			end
		end
		if #members > #bestMembers or (#members == #bestMembers and total < bestTotal) then
			bestMembers = members
			bestTotal = total
		end
	end
	table.sort(bestMembers, function(a, b) return a.Player.UserId < b.Player.UserId end)
	local anchor = bestMembers[random:NextInteger(1, #bestMembers)]
	local centroid = Vector3.zero
	for _, member in ipairs(bestMembers) do centroid += member.Position end
	centroid /= #bestMembers
	return bestMembers, anchor, centroid
end

local function spawnOverlapParams(records: {any}): OverlapParams
	local params = OverlapParams.new()
	params.FilterType = Enum.RaycastFilterType.Exclude
	local ignored = {}
	for _, record in ipairs(records) do table.insert(ignored, record.Character) end
	params.FilterDescendantsInstances = ignored
	params.RespectCanCollide = true
	params.MaxParts = 1
	return params
end

local function spawnVolumeFits(position: Vector3, params: OverlapParams): boolean
	local castHeight = math.max(2, Tuning.AgentHeight - .6)
	local center = position + Vector3.new(0, castHeight * .5 + .2, 0)
	local size = Vector3.new(Tuning.SweepRadius * 2, castHeight, Tuning.SweepRadius * 2)
	return #workspace:GetPartBoundsInBox(CFrame.new(center), size, params) == 0
end

local function spawnVisibilityCount(position: Vector3, records: {any}): number
	local params = RaycastParams.new()
	params.FilterType = Enum.RaycastFilterType.Exclude
	local ignored = {}
	for _, record in ipairs(records) do table.insert(ignored, record.Character) end
	params.FilterDescendantsInstances = ignored
	params.IgnoreWater = true
	params.RespectCanCollide = true
	local target = position + Vector3.new(0, 4.2, 0)
	local visible = 0
	for _, record in ipairs(records) do
		local head = record.Character:FindFirstChild("Head")
		local origin = if head and head:IsA("BasePart") then head.Position else record.Position + Vector3.new(0, 2.5, 0)
		if not workspace:Raycast(origin, target - origin, params) then visible += 1 end
	end
	return visible
end

local function chooseFinalHallSpawn(manifest: any, generation: number): any?
	local records = eligibleSpawnPlayers()
	if #records == 0 then return nil end
	local hall = manifest.FinalHall
	if type(hall) ~= "table" or not hall.SpawnMarker or not hall.SpawnMarker.Parent then return nil end
	local state = stateFolder()
	local cycle = math.floor(tonumber(state:GetAttribute("Level3_RoomSongCycle")) or 0)
	local random = Random.new(generation * 7919 + cycle * 104729 + 20260824)
	local position = Vector3.new(hall.SpawnMarker.Position.X, hall.FloorY, hall.SpawnMarker.Position.Z)
	if not spawnVolumeFits(position, spawnOverlapParams(records)) then
		warn("[Level 3 Mall Manager] authored final-hall spawn volume is blocked")
		return nil
	end
	table.sort(records, function(a, b)
		local aDistance = planarDistance(position, a.Position)
		local bDistance = planarDistance(position, b.Position)
		if math.abs(aDistance - bDistance) > .001 then return aDistance < bDistance end
		return a.Player.UserId < b.Player.UserId
	end)
	local anchor = records[1]
	local centroid = Vector3.zero
	local nearestDistance = math.huge
	for _, record in ipairs(records) do
		centroid += record.Position
		nearestDistance = math.min(nearestDistance, planarDistance(position, record.Position))
	end
	centroid /= #records
	return {
		Position = position,
		Anchor = anchor,
		GroupSize = #records,
		Centroid = centroid,
		Cycle = cycle,
		RoomId = nearestRoomId(position),
		Random = random,
		-- The spawn volume was genuinely swept clear above; route reachability is
		-- proven later by the authoritative full-route sweep (markPathValidated).
		SpawnClearanceValidated = true,
		Visibility = spawnVisibilityCount(position, records),
		NearestDistance = nearestDistance,
		AnchorDistance = planarDistance(position, anchor.Position),
		FinalHallChase = true,
	}
end

local function chooseBlackoutSpawn(manifest: any, generation: number): any?
	if workspace:GetAttribute("Level3FinalHallChaseActive") == true then
		return chooseFinalHallSpawn(manifest, generation)
	end
	local records = eligibleSpawnPlayers()
	if #records == 0 then return nil end
	local state = stateFolder()
	local cycle = math.floor(tonumber(state:GetAttribute("Level3_RoomSongCycle")) or 0)
	local random = Random.new(generation * 7919 + cycle * 104729 + 311)
	local group, anchor, centroid = chooseDenseGroup(records, random)
	local floorY = tonumber(manifest.MallManagerSpawn:GetAttribute("Level3_FloorY"))
		or Configuration.WorldOrigin.Y
	local candidates = {}
	local seen = {}
	local function addCandidate(raw: Vector3)
		local position = Vector3.new(raw.X, floorY, raw.Z)
		local key = string.format("%d:%d", math.floor(position.X * 2 + .5), math.floor(position.Z * 2 + .5))
		if seen[key] then return end
		seen[key] = true
		table.insert(candidates, position)
	end
	for _, room in ipairs(layoutRooms()) do
		if room.Id ~= "Exit" then
			local center = Configuration.WorldOrigin + Vector3.new(room.X, 0, room.Z)
			local maxX = math.max(0, room.W * .5 - Tuning.SpawnRoomMargin - Tuning.SweepRadius)
			local maxZ = math.max(0, room.D * .5 - Tuning.SpawnRoomMargin - Tuning.SweepRadius)
			local xStep = math.min(24, maxX * .72)
			local zStep = math.min(24, maxZ * .72)
			for _, x in ipairs({0, -xStep, xStep}) do
				for _, z in ipairs({0, -zStep, zStep}) do addCandidate(center + Vector3.new(x, 0, z)) end
			end
		end
	end
	for _, corridor in ipairs(manifest.Corridors or {}) do
		if corridor.DoorType ~= "HiddenExit" then
			for _, alpha in ipairs({.18, .32, .5, .68, .82}) do
				addCandidate(corridor.StartPoint:Lerp(corridor.EndPoint, alpha))
			end
		end
	end

	local overlap = spawnOverlapParams(records)
	local scored: {any} = {}
	for _, position in ipairs(candidates) do
		local anchorDistance = planarDistance(position, anchor.Position)
		local nearestDistance = math.huge
		for _, record in ipairs(records) do
			nearestDistance = math.min(nearestDistance, planarDistance(position, record.Position))
		end
		if nearestDistance >= Tuning.SpawnMinimumDistance
			and anchorDistance <= Tuning.SpawnMaximumDistance
			and spawnVolumeFits(position, overlap) then
			local visibility = spawnVisibilityCount(position, records)
			table.insert(scored, {
				Position = position,
				Tier = if visibility == 0 then 0 else 1,
				Visibility = visibility,
				Score = math.abs(nearestDistance - Tuning.SpawnPreferredDistance)
					+ math.abs(anchorDistance - Tuning.SpawnPreferredDistance) * .12
					+ planarDistance(position, centroid) * .05 + random:NextNumber(0, .25),
				NearestDistance = nearestDistance,
				AnchorDistance = anchorDistance,
			})
		end
	end
	if #scored == 0 then return nil end
	table.sort(scored, function(a, b)
		if a.Tier ~= b.Tier then return a.Tier < b.Tier end
		return a.Score < b.Score
	end)

	-- Every candidate comes from a non-exit authored room or an open corridor in
	-- the already-validated connected graph. Selecting that route immediately
	-- keeps the reveal on the song-end beat; the AI's background PFS/graph hybrid
	-- owns all movement after spawn without blocking the scream edge.
	local selected = scored[1]
	if not selected then return nil end
	selected.Anchor = anchor
	selected.GroupSize = #group
	selected.Centroid = centroid
	selected.Cycle = cycle
	selected.RoomId = nearestRoomId(selected.Position)
	selected.Random = random
	-- spawnVolumeFits gated every scored candidate; reachability is proven
	-- later by the authoritative full-route sweep (markPathValidated).
	selected.SpawnClearanceValidated = true
	return selected
end

local function cloneManager(manifest: any, spawnPosition: Vector3, facePosition: Vector3,
	spawnRoomId: string): (Model, BasePart, number)
	local template = requireAsset(ServerStorage, "Level3Assets", "EntityTemplates", Tuning.TemplateName)
	assert(template:IsA("Model") and template.PrimaryPart, "Mall Manager template must be a Model with PrimaryPart")
	assert(template:GetAttribute("RuntimeReady") == true, "Mall Manager template has not passed runtime validation")
	local model = template:Clone()
	model.Name = Tuning.RuntimeName
	model.ModelStreamingMode = Enum.ModelStreamingMode.Persistent
	for _, authoringName in ipairs({"InitialPoses", "AnimSaves"}) do
		local authoring = model:FindFirstChild(authoringName)
		if authoring then authoring:Destroy() end
	end
	local root = model:FindFirstChild("HumanoidRootPart")
	assert(root and root:IsA("BasePart") and model.PrimaryPart == root,
		"Mall Manager clone requires HumanoidRootPart as PrimaryPart")
	local mesh = model:FindFirstChild("char1")
	assert(mesh and mesh:IsA("BasePart"), "Mall Manager clone is missing its skinned char1 mesh")
	local templateConstraint = root:FindFirstChild("MallManagerRootWeld")
	if templateConstraint and templateConstraint:IsA("WeldConstraint") then
		local runtimeWeld = Instance.new("Weld")
		runtimeWeld.Name = "MallManagerRootWeld"
		runtimeWeld.Part0 = root
		runtimeWeld.Part1 = mesh
		runtimeWeld.C0 = root.CFrame:ToObjectSpace(mesh.CFrame)
		runtimeWeld.C1 = CFrame.identity
		runtimeWeld.Parent = root
		templateConstraint:Destroy()
	end
	local runtimeRootWeld = root:FindFirstChild("MallManagerRootWeld")
	assert(runtimeRootWeld and runtimeRootWeld:IsA("Weld"),
		"Mall Manager runtime clone requires an interpolatable root Weld")
	for _, object in ipairs(model:GetDescendants()) do
		if object:IsA("BasePart") then
			object.Anchored = object == root
			object.CanCollide = false
			object.CanTouch = false
			object.CanQuery = false
			if object ~= root then object.Massless = true end
		end
	end
	root.Anchored = true
	model:SetAttribute("RuntimeReady", true)
	model:SetAttribute("Level3_MallManagerRuntime", true)
	model:SetAttribute("Level3_Generation", manifest.Generation)
	model:SetAttribute("Level3_MallManagerSpawnRoomId", spawnRoomId)

	local boundingCFrame, boundingSize = model:GetBoundingBox()
	local pivot = model:GetPivot()
	local groundOffset = pivot.Position.Y - (boundingCFrame.Position.Y - boundingSize.Y * .5)
	local rootPosition = spawnPosition + Vector3.new(0, groundOffset, 0)
	local target = Vector3.new(facePosition.X, rootPosition.Y, facePosition.Z)
	model:PivotTo(CFrame.lookAt(rootPosition, target))
	model.Parent = manifest.MallManagerRuntime
	CollectionService:AddTag(model, "Level3HostileEntity")
	return model, root, groundOffset
end

function Controller.Start(manifest: any, generation: number)
	Controller.Stop()
	Tuning = resolveTuning()
	assert(type(manifest) == "table" and manifest.World and manifest.World:IsA("Model")
		and manifest.World.Parent == workspace, "Mall Manager requires a live Level 3 manifest")
	assert(manifest.World:GetAttribute("Level3_Generation") == generation,
		"Mall Manager generation does not match the Level 3 world")
	assert(manifest.MallManagerSpawn and manifest.MallManagerSpawn:IsA("BasePart")
		and manifest.MallManagerSpawn:IsDescendantOf(manifest.World),
		"Level 3 manifest is missing Mall Manager Spawn")
	assert(manifest.MallManagerRuntime and manifest.MallManagerRuntime:IsA("Folder")
		and manifest.MallManagerRuntime:IsDescendantOf(manifest.World),
		"Level 3 manifest is missing Mall Manager Runtime")
	activeLayout = if type(manifest.Layout) == "table" then manifest.Layout else nil
	if workspace:GetAttribute("Level3MallManagerHuntActive") ~= true then
		activeLayout = nil
		resetPublishedState()
		return nil
	end
	local spawnData = chooseBlackoutSpawn(manifest, generation)
	if not spawnData then
		activeLayout = nil
		resetPublishedState()
		warn("[Level 3 Mall Manager] hunt edge has no eligible living player spawn yet")
		return nil
	end

	for _, player in ipairs(Players:GetPlayers()) do
		if player:GetAttribute("BeingChased") == true then player:SetAttribute("BeingChased", false) end
	end
	local spawnDistance = spawnData.NearestDistance
	local model, root, groundOffset = cloneManager(manifest, spawnData.Position,
		spawnData.Anchor.Position, spawnData.RoomId)
	local walkTrack = loadWalk(model)
	local footstepEmitter, footstepSounds = loadFootstepSounds(root, groundOffset)
	local voiceEmitter, chaseScream = loadChaseScream(model)
	local state = stateFolder()
	local motionObject = ReplicatedStorage:WaitForChild(Configuration.RemotesFolderName)
		:WaitForChild(Configuration.MallManagerMotionEventName)
	assert(motionObject:IsA("UnreliableRemoteEvent"), "Level 3 Mall Manager motion remote is missing")
	local motionRemote = motionObject :: UnreliableRemoteEvent
	local floorY = spawnData.Position.Y
	local session: any = {
		Active = true,
		Generation = generation,
		Manifest = manifest,
		World = manifest.World,
		FurnitureNavExclusions = collectFurnitureNavExclusions(manifest.World),
		Model = model,
		Root = root,
		GroundOffset = groundOffset,
		FloorY = floorY,
		StateFolder = state,
		State = "BOOTING",
		Blackout = false,
		Target = nil,
		Suspicion = {},
		LastKnownPosition = nil,
		LastSenseAt = -math.huge,
		LastVisualAt = -math.huge,
		AlertUntil = 0,
		SearchUntil = nil,
		SearchNextAt = 0,
		PatrolGoal = nil,
		PatrolWaitUntil = nil,
		RecentPatrolRooms = {spawnData.RoomId},
		Random = spawnData.Random,
		SpawnAnchor = spawnData.Anchor.Player,
		SpawnGroupSize = spawnData.GroupSize,
		SpawnCycle = spawnData.Cycle,
		SpawnRoomId = spawnData.RoomId,
		Adjacency = buildAdjacency(),
		FinalHallChase = spawnData.FinalHallChase == true,
		FinalGoal = nil,
		ResolvedFinalGoal = nil,
		StrategicPoints = {},
		StrategicRooms = {},
		StrategicIndex = 1,
		StrategicStartRoomId = nil,
		StrategicGoalRoomId = nil,
		StrategicRebuildSerial = 0,
		StrategicGoalRevision = 0,
		Path = nil,
		PathObject = nil,
		PathGoal = nil,
		PathToken = 0,
		PathComputing = false,
		InFlightPathGoal = nil,
		PendingPathGoal = nil,
		PendingPathForce = false,
		PathDispatchScheduled = false,
		PathBlockedConnection = nil,
		PathStatus = "BOOTING",
		PathFailures = 0,
		PathSwapSerial = 0,
		PathComputeSerial = 0,
		PathComputeTimes = {},
		ActiveComputeCount = 0,
		PeakComputeCount = 0,
		PathValidated = false,
		WaypointIndex = 1,
		LastPathRequest = -math.huge,
		Heading = (function()
			local direction = flat(spawnData.Anchor.Position, floorY) - spawnData.Position
			return if direction.Magnitude > .01 then direction.Unit else Vector3.new(-1, 0, 0)
		end)(),
		CurrentMoveSpeed = 0,
		LastActualStepDistance = 0,
		LastProgressAt = os.clock(),
		LastGenuineProgressAt = os.clock(),
		GenuineProgressSerial = 0,
		ProgressObjectiveKey = nil,
		ProgressBestDistance = math.huge,
		ProgressCreditedDistance = math.huge,
		ProgressLastPathSwapSerial = 0,
		ProgressLastWaypointIndex = 1,
		ProgressLastStrategicRebuildSerial = 0,
		ProgressLastStrategicIndex = 1,
		StuckRecoveries = 0,
		RecoveryRepaths = 0,
		ConsecutiveObstructions = 0,
		AvoidanceSign = 0,
		AvoidanceUntil = 0,
		OverlapEscapeActive = false,
		OverlapEscapeDirection = nil,
		OverlapEscapeStartedAt = 0,
		OverlapEscapeBaselineBlockers = 0,
		OverlapEscapeBaselineGoalPoint = nil,
		OverlapEscapeBaselineGoalDistance = math.huge,
		OverlapEscapeNextRetryAt = 0,
		OverlapEscapeSearches = 0,
		OverlapEscapeAttempts = 0,
		DebugMovementPaused = false,
		WalkTrack = walkTrack,
		WalkMoving = false,
		WalkPoseHeld = false,
		WalkPlaybackSpeed = 0,
		FootstepEmitter = footstepEmitter,
		FootstepSounds = footstepSounds,
		FootstepWasMoving = false,
		LastWalkTimePosition = if walkTrack then walkTrack.TimePosition else 0,
		FootstepSerial = 0,
		LastFootstepIndex = 0,
		LastFootstepName = "",
		LastFootstepPhase = 0,
		VoiceEmitter = voiceEmitter,
		ChaseScream = chaseScream,
		ChaseScreamSerial = 0,
		ChaseScreamPlaying = false,
		LastChaseScreamAtServerTime = 0,
		NextChaseScreamAt = 0,
		Connections = {},
		ThinkAccumulator = 0,
		ActivatedAt = math.huge,
		Attacking = false,
		AttackToken = 0,
		AttackCooldownUntil = 0,
		AttackSerial = 0,
		-- Table check (LEVEL3_MANAGER_TABLE_CHECK_20260904). TargetAnchor is the
		-- table this sweep leg is aimed at; Anchor is the one being checked right
		-- now. Both are cleared by Controller.Stop, along with the cue and the
		-- replicated state, so nothing survives a round.
		TableCheckAnchor = nil,
		TableCheckTargetAnchor = nil,
		TableCheckEndsAt = 0,
		TableCheckSound = nil,
		NextTableCheckAt = 0,
		AnchorCheckCooldown = {},
		WorldNoise = nil,
		MotionRemote = motionRemote,
		MotionSequence = 0,
		MotionAccumulator = 0,
		SpawnSerial = 0,
	}
	activeSession = session
	table.insert(session.Connections, chaseScream.Ended:Connect(function()
		if activeSession ~= session then return end
		session.ChaseScreamPlaying = false
		state:SetAttribute("Level3_MallManagerChaseScreamPlaying", false)
		if model.Parent then model:SetAttribute("Level3_MallManagerChaseScreamPlaying", false) end
	end))
	setWalk(session, false, 0)

	local spawnSerial = math.floor(tonumber(state:GetAttribute("Level3_MallManagerSpawnSerial")) or 0) + 1
	session.SpawnSerial = spawnSerial
	model:SetAttribute("Level3_Generation", generation)
	state:SetAttribute("Level3_MallManagerActive", true)
	state:SetAttribute("Level3_MallManagerSpawnRoomId", spawnData.RoomId)
	state:SetAttribute("Level3_MallManagerSpawnDistance", spawnDistance)
	state:SetAttribute("Level3_MallManagerSpawnVisibleCount", spawnData.Visibility)
	state:SetAttribute("Level3_MallManagerSpawnClearanceValidated", spawnData.SpawnClearanceValidated == true)
	state:SetAttribute("Level3_MallManagerPathValidated", false)
	state:SetAttribute("Level3_MallManagerSpawnAnchorUserId", spawnData.Anchor.Player.UserId)
	state:SetAttribute("Level3_MallManagerSpawnGroupSize", spawnData.GroupSize)
	state:SetAttribute("Level3_MallManagerSpawnCycle", spawnData.Cycle)
	state:SetAttribute("Level3_MallManagerFinaleSpawn", session.FinalHallChase)
	state:SetAttribute("Level3_MallManagerSpawnPosition", spawnData.Position)
	state:SetAttribute("Level3_MallManagerSpawnSerial", spawnSerial)
	state:SetAttribute("Level3_MallManagerAttackSerial", 0)
	state:SetAttribute("Level3_MallManagerLastCaptureUserId", 0)
	state:SetAttribute("Level3_MallManagerFootstepSerial", 0)
	state:SetAttribute("Level3_MallManagerLastFootstepIndex", 0)
	state:SetAttribute("Level3_MallManagerLastFootstepName", "")
	state:SetAttribute("Level3_MallManagerLastFootstepPhase", 0)
	state:SetAttribute("Level3_MallManagerChaseScreamSerial", 0)
	state:SetAttribute("Level3_MallManagerChaseScreamPlaying", false)
	state:SetAttribute("Level3_MallManagerLastChaseScreamAtServerTime", 0)
	state:SetAttribute("Level3_MallManagerLastChaseScreamName", "")
	workspace:SetAttribute("Level3MallManagerActive", true)
	model:SetAttribute("Level3_MallManagerSpawnDistance", spawnDistance)
	model:SetAttribute("Level3_MallManagerSpawnVisibleCount", spawnData.Visibility)
	model:SetAttribute("Level3_MallManagerSpawnClearanceValidated", spawnData.SpawnClearanceValidated == true)
	model:SetAttribute("Level3_MallManagerPathValidated", false)
	model:SetAttribute("Level3_MallManagerSpawnAnchorUserId", spawnData.Anchor.Player.UserId)
	model:SetAttribute("Level3_MallManagerSpawnGroupSize", spawnData.GroupSize)
	model:SetAttribute("Level3_MallManagerSpawnCycle", spawnData.Cycle)
	model:SetAttribute("Level3_MallManagerFinaleSpawn", session.FinalHallChase)
	model:SetAttribute("Level3_MallManagerSpawnPosition", spawnData.Position)
	model:SetAttribute("Level3_MallManagerSpawnSerial", spawnSerial)
	model:SetAttribute("Level3_MallManagerAttackSerial", 0)
	model:SetAttribute("Level3_MallManagerFootstepSerial", 0)
	model:SetAttribute("Level3_MallManagerLastFootstepIndex", 0)
	model:SetAttribute("Level3_MallManagerLastFootstepName", "")
	model:SetAttribute("Level3_MallManagerLastFootstepPhase", 0)
	model:SetAttribute("Level3_MallManagerChaseScreamSerial", 0)
	model:SetAttribute("Level3_MallManagerChaseScreamPlaying", false)
	model:SetAttribute("Level3_MallManagerLastChaseScreamAtServerTime", 0)
	model:SetAttribute("Level3_MallManagerLastChaseScreamName", "")
	publishPathStatus(session, "IDLE")
	publishTarget(session, nil)

	local function roundChanged()
		if not liveSession(session) then return end
		if workspace:GetAttribute("RoundActive") == true
			and workspace:GetAttribute("SelectedLevel") == 3
			and workspace:GetAttribute("Level3MallManagerHuntActive") == true then
			session.ActivatedAt = os.clock() + Tuning.SpawnGraceSeconds
			session.LastProgressAt = os.clock()
			session.LastGenuineProgressAt = os.clock()
			session.ProgressObjectiveKey = nil
			session.ProgressBestDistance = math.huge
			session.ProgressCreditedDistance = math.huge
			publishState(session, "AWAKENING")
		else
			session.ActivatedAt = math.huge
			dormant(session, "WAITING")
		end
	end
	table.insert(session.Connections, workspace:GetAttributeChangedSignal("RoundActive"):Connect(roundChanged))
	table.insert(session.Connections, workspace:GetAttributeChangedSignal("EntityPaused"):Connect(function()
		if workspace:GetAttribute("EntityPaused") == true then dormant(session, "PAUSED") end
	end))
	local function refreshBlackoutProfile()
		applyBlackout(session, blackoutProfileRequested())
	end
	table.insert(session.Connections, workspace:GetAttributeChangedSignal("Level3BlackoutActive"):Connect(refreshBlackoutProfile))
	table.insert(session.Connections,
		workspace:GetAttributeChangedSignal("Level3FinalHallChaseActive"):Connect(refreshBlackoutProfile))
	local function bindHideTarget(player: Player)
		table.insert(session.Connections, player:GetAttributeChangedSignal("Level3_Hiding"):Connect(function()
			if liveSession(session) and player:GetAttribute("Level3_Hiding") == true
				and session.Target == player then
				redirectHiddenTarget(session, player, os.clock())
			end
		end))
	end
	for _, player in ipairs(Players:GetPlayers()) do bindHideTarget(player) end
	table.insert(session.Connections, Players.PlayerAdded:Connect(bindHideTarget))
	table.insert(session.Connections, Players.PlayerRemoving:Connect(function(player)
		session.Suspicion[player] = nil
		if session.Target == player then
			publishTarget(session, nil)
			session.LastKnownPosition = nil
		end
	end))
	for _, module in ipairs(manifest.Modules) do
		if module.Model and module.Model:IsA("Model") then
			table.insert(session.Connections, module.Model:GetAttributeChangedSignal("Level3_Collected"):Connect(function()
				if liveSession(session) and module.Model:GetAttribute("Level3_Collected") == true then
					session.WorldNoise = {
						Position = module.Model:GetPivot().Position,
						Time = os.clock(),
						Strength = 1.2,
					}
				end
			end))
		end
	end

	table.insert(session.Connections, RunService.Heartbeat:Connect(function(dt)
		if not liveSession(session) then return end
		local now = os.clock()
		refreshNavigationFilters(session)
		if updateTableCheck(session, now) then
			-- Kneeling at a table. Speed is 0 for TABLE_CHECK so updateMovement
			-- holds position and parks the walk cycle; perception and attacks are
			-- skipped entirely for the reaction window.
			updateMovement(session, dt, now)
			publishMotion(session, dt, false)
			updateFootsteps(session)
			return
		end
		session.ThinkAccumulator += dt
		local thinkInterval = if session.Blackout
			then Tuning.BlackoutThinkIntervalSeconds else Tuning.ThinkIntervalSeconds
		if session.ThinkAccumulator >= thinkInterval then
			local senseDt = session.ThinkAccumulator
			session.ThinkAccumulator = 0
			updateBrain(session, now, senseDt)
		end
		if validRound(session) and session.State == "CHASE" and session.Target then
			beginAttack(session, session.Target)
		end
		updateMovement(session, dt, now)
		publishMotion(session, dt, false)
		updateFootsteps(session)
	end))

	applyBlackout(session, blackoutProfileRequested())
	roundChanged()
	-- Acquire before the first Heartbeat so the spawned Manager already exposes
	-- its target and begins the nearest-player route on the reveal frame.
	if session.Blackout and validRound(session) then
		trackNearestBlackoutPlayer(session, os.clock())
	else
		local seedPlayer, seedRoot = nearestExposedPlayer(session)
		if seedPlayer and seedRoot then
			session.LastKnownPosition = flat(seedRoot.Position, floorY)
			session.LastSenseAt = os.clock()
			setGoal(session, session.LastKnownPosition, true)
		else
			session.LastKnownPosition = nil
			session.LastSenseAt = -math.huge
		end
	end
	publishMotion(session, 0, true)
	print(string.format("[Level 3 Mall Manager] hunt spawn %.1f studs from nearest player; group %d, room %s, blackout chase %.1f",
		spawnDistance, spawnData.GroupSize, spawnData.RoomId, Tuning.Blackout.ChaseSpeed))
	return session
end

function Controller.GetSnapshot()
	local session = activeSession
	if not session then return nil end
	return {
		Generation = session.Generation,
		Model = session.Model,
		State = session.State,
		TargetUserId = if session.Target then session.Target.UserId else 0,
		TargetMode = session.StateFolder:GetAttribute("Level3_MallManagerTargetMode"),
		TargetDistance = session.StateFolder:GetAttribute("Level3_MallManagerTargetDistance"),
		TargetPosition = session.StateFolder:GetAttribute("Level3_MallManagerTargetPosition"),
		LastCaptureUserId = tonumber(session.StateFolder:GetAttribute(
			"Level3_MallManagerLastCaptureUserId")) or 0,
		Blackout = session.Blackout,
		FinalHallChase = session.FinalHallChase,
		Speed = currentSpeed(session),
		DesiredSpeed = currentSpeed(session),
		MovementSpeed = session.CurrentMoveSpeed,
		LastActualStepDistance = session.LastActualStepDistance,
		Heading = session.Heading,
		AwarenessRange = profile(session).VisionRange,
		PathStatus = session.PathStatus,
		PathComputing = session.PathComputing,
		PathSwapSerial = session.PathSwapSerial,
		MotionSequence = session.MotionSequence,
		SpawnSerial = session.SpawnSerial,
		SpawnRoomId = session.SpawnRoomId,
		SpawnDistance = session.StateFolder:GetAttribute("Level3_MallManagerSpawnDistance"),
		SpawnAnchorUserId = session.StateFolder:GetAttribute("Level3_MallManagerSpawnAnchorUserId"),
		SpawnGroupSize = session.SpawnGroupSize,
		SpawnCycle = session.SpawnCycle,
		Attacking = session.Attacking,
		AttackSerial = session.AttackSerial,
		TableCheckActive = session.TableCheckAnchor ~= nil,
		TableCheckIndex = if session.TableCheckAnchor
			then (tonumber(session.TableCheckAnchor:GetAttribute("Level3_HideTableIndex")) or 0)
			else 0,
		TableCheckTargetIndex = if session.TableCheckTargetAnchor
			then (tonumber(session.TableCheckTargetAnchor:GetAttribute("Level3_HideTableIndex")) or 0)
			else 0,
		TableChecksSuspended = debugTableChecksSuspended,
		WalkMoving = session.WalkMoving,
		WalkPoseHeld = session.WalkPoseHeld,
		WalkPlaybackSpeed = session.WalkPlaybackSpeed,
		WalkTrackPlaying = session.WalkTrack ~= nil and session.WalkTrack.IsPlaying,
		WalkTimePosition = if session.WalkTrack then session.WalkTrack.TimePosition else 0,
		FootstepSerial = session.FootstepSerial,
		LastFootstepIndex = session.LastFootstepIndex,
		LastFootstepName = session.LastFootstepName,
		LastFootstepPhase = session.LastFootstepPhase,
		FootstepPlayingCount = (function()
			local count = 0
			for _, sound in ipairs(session.FootstepSounds) do
				if sound.IsPlaying then count += 1 end
			end
			return count
		end)(),
		ChaseScreamSerial = session.ChaseScreamSerial,
		ChaseScreamPlaying = session.ChaseScreamPlaying and session.ChaseScream.IsPlaying,
		ChaseScreamTimePosition = session.ChaseScream.TimePosition,
		LastChaseScreamAtServerTime = session.LastChaseScreamAtServerTime,
		Position = session.Root.Position,
		FinalGoal = session.FinalGoal,
		ResolvedFinalGoal = session.ResolvedFinalGoal,
		GoalDistance = if session.FinalGoal
			then planarDistance(session.Root.Position, session.FinalGoal) else 0,
		PathFailures = session.PathFailures,
		ConsecutiveObstructions = session.ConsecutiveObstructions,
		AvoidanceSign = session.AvoidanceSign,
		OverlapEscapeActive = session.OverlapEscapeActive,
		OverlapEscapeAttempts = session.OverlapEscapeAttempts,
		OverlapEscapeSearches = session.OverlapEscapeSearches,
		OverlapEscapeBaselineGoalPoint = session.OverlapEscapeBaselineGoalPoint,
		OverlapEscapeBaselineGoalDistance = session.OverlapEscapeBaselineGoalDistance,
		DebugMovementPaused = session.DebugMovementPaused == true,
		WaypointIndex = session.WaypointIndex,
		WaypointCount = if session.Path then #session.Path else 0,
		PathComputeSerial = session.PathComputeSerial,
		-- Half-open window: a request whose age has reached one second has left
		-- it. The closed form counted six starts at 0/.2/.4/.6/.8/1.0 as one
		-- second's worth; the tolerance absorbs os.clock jitter at the boundary
		-- so an exactly-spaced burst cannot report a phantom sixth request.
		PathComputesLastSecond = (function()
			local now = os.clock()
			local count = 0
			for _, startedAt in ipairs(session.PathComputeTimes) do
				if now - startedAt < 1 - PATH_RATE_CLOCK_TOLERANCE then count += 1 end
			end
			return count
		end)(),
		PeakConcurrentPathComputes = session.PeakComputeCount,
		PathValidated = session.PathValidated == true,
		SpawnClearanceValidated = session.StateFolder:GetAttribute(
			"Level3_MallManagerSpawnClearanceValidated") == true,
		StrategicIndex = session.StrategicIndex,
		StrategicPointCount = #session.StrategicPoints,
		StrategicGoalRoomId = session.StrategicGoalRoomId,
		StrategicRebuildSerial = session.StrategicRebuildSerial,
		StrategicGoalRevision = session.StrategicGoalRevision,
		StuckRecoveries = session.StuckRecoveries,
		RecoveryRepaths = session.RecoveryRepaths,
		FurnitureNavExclusionsActive = activeFurnitureNavExclusionCount(session),
		FurnitureNavExclusionsTotal = #(session.FurnitureNavExclusions or {}),
		LastProgressAgeSeconds = os.clock() - session.LastProgressAt,
		-- Only credited movement moves these two. Recovery rearms the stuck
		-- timer above but cannot touch them, so a motionless Manager cannot
		-- launder a repath into apparent progress.
		LastGenuineProgressAgeSeconds = os.clock() - session.LastGenuineProgressAt,
		GenuineProgressSerial = session.GenuineProgressSerial,
		ProgressObjectiveKey = session.ProgressObjectiveKey,
		ProgressBestDistance = session.ProgressBestDistance,
		ProgressCreditedDistance = session.ProgressCreditedDistance,
	}
end

-- Studio probes use the exact production budget function so a future tuning
-- change cannot make the test and the controller agree on different formulas.
function Controller.DebugBlackoutSweepLegSeconds(distance: number): number
	assert(RunService:IsStudio(), "DebugBlackoutSweepLegSeconds is Studio-only")
	return blackoutSweepLegDuration(tonumber(distance) or 0)
end

function Controller.DebugForcePatrolRoom(roomId: string)
	assert(RunService:IsStudio(), "DebugForcePatrolRoom is Studio-only")
	local session = assert(activeSession, "Mall Manager is not running")
	assert(roomId ~= "Exit", "Mall Manager debug routing cannot enter the sealed Exit")
	local destination = assert(roomCenter(roomId, session.FloorY), "Unknown Level 3 room id")
	publishTarget(session, nil)
	table.clear(session.Suspicion)
	session.LastKnownPosition = nil
	session.LastSenseAt = -math.huge
	session.WorldNoise = nil
	session.SearchUntil = nil
	session.PatrolGoal = destination
	session.PatrolWaitUntil = nil
	session.ActivatedAt = 0
	session.PathFailures = 0
	session.ConsecutiveObstructions = 0
	session.LastPathRequest = -math.huge
	session.LastProgressAt = os.clock()
	session.LastGenuineProgressAt = os.clock()
	session.ProgressObjectiveKey = nil
	session.ProgressBestDistance = math.huge
	session.ProgressCreditedDistance = math.huge
	resetOverlapEscapeState(session)
	publishState(session, "PATROL")
	setGoal(session, destination, true)
	return Controller.GetSnapshot()
end

-- Studio-only deterministic movement fixture. It relocates the live rig to
-- one end of a segment already accepted by the exact production clearance
-- contract, then makes the other end its patrol goal. Behavioral tests can
-- therefore isolate movement/progress rules without inheriting a wall, stale
-- route, or recovery state from an earlier destructive probe.
function Controller.DebugPrepareStraightPatrol(startPosition: Vector3, destination: Vector3)
	assert(RunService:IsStudio(), "DebugPrepareStraightPatrol is Studio-only")
	assert(typeof(startPosition) == "Vector3" and typeof(destination) == "Vector3",
		"DebugPrepareStraightPatrol requires two Vector3 positions")
	local session = assert(activeSession, "Mall Manager is not running")
	local startGround = flat(startPosition, session.FloorY)
	local destinationGround = flat(destination, session.FloorY)
	local displacement = destinationGround - startGround
	assert(displacement.Magnitude >= 12,
		"DebugPrepareStraightPatrol requires a segment at least 12 studs long")
	assert(volumeFits(session, startGround), "Debug straight-patrol start volume is blocked")
	assert(volumeFits(session, destinationGround), "Debug straight-patrol destination is blocked")
	assert(volumeClear(session, startGround, destinationGround),
		"Debug straight-patrol segment is not clear under the production sweep")

	publishTarget(session, nil)
	table.clear(session.Suspicion)
	session.LastKnownPosition = nil
	session.LastSenseAt = -math.huge
	session.WorldNoise = nil
	session.SearchUntil = nil
	session.PatrolGoal = destinationGround
	session.PatrolWaitUntil = nil
	session.ActivatedAt = 0
	session.PathFailures = 0
	session.ConsecutiveObstructions = 0
	session.LastPathRequest = -math.huge
	session.CurrentMoveSpeed = 0
	session.LastActualStepDistance = 0
	resetOverlapEscapeState(session)
	clearPath(session, "DEBUG_STRAIGHT_PATROL")

	local direction = displacement.Unit
	session.Heading = direction
	local rootPosition = startGround + Vector3.new(0, session.GroundOffset, 0)
	session.Root.CFrame = CFrame.lookAt(rootPosition, rootPosition + direction)
	publishState(session, "PATROL")
	setGoal(session, destinationGround, true)
	local now = os.clock()
	session.LastProgressAt = now
	session.LastGenuineProgressAt = now
	session.ProgressObjectiveKey = nil
	session.ProgressBestDistance = math.huge
	session.ProgressCreditedDistance = math.huge
	session.ProgressLastPathSwapSerial = session.PathSwapSerial
	session.ProgressLastWaypointIndex = session.WaypointIndex
	session.ProgressLastStrategicRebuildSerial = session.StrategicRebuildSerial
	session.ProgressLastStrategicIndex = session.StrategicIndex
	publishMotion(session, 0, true)
	return Controller.GetSnapshot()
end

function Controller.DebugSetMovementPaused(paused: boolean)
	assert(RunService:IsStudio(), "DebugSetMovementPaused is Studio-only")
	local session = assert(activeSession, "Mall Manager is not running")
	session.DebugMovementPaused = paused == true
	if session.DebugMovementPaused then
		session.CurrentMoveSpeed = 0
		session.LastActualStepDistance = 0
		setWalk(session, false, 0)
	end
	return Controller.GetSnapshot()
end

-- Studio-only. Probes that park a player under a table to observe something
-- ELSE (furniture permanence, the all-hidden sweep) would otherwise have that
-- player found and flushed mid-assertion. Suspending checks ends any in flight
-- without flushing; re-enabling restores production behaviour.
function Controller.DebugSetTableChecksEnabled(enabled: boolean)
	assert(RunService:IsStudio(), "DebugSetTableChecksEnabled is Studio-only")
	debugTableChecksSuspended = enabled ~= true
	local session = activeSession
	if debugTableChecksSuspended and session and session.Active == true then
		if session.TableCheckAnchor then endTableCheck(session, false) end
		session.TableCheckTargetAnchor = nil
	end
	return Controller.GetSnapshot()
end

-- Studio-only clearance probe for behavioral navigation tests: reports how the
-- live session's shared clearance contract classifies one ground position.
function Controller.DebugNavigationProbe(position: Vector3)
	assert(RunService:IsStudio(), "DebugNavigationProbe is Studio-only")
	local session = assert(activeSession, "Mall Manager is not running")
	local ground = flat(position, session.FloorY)
	local physical = overlappingNavigationParts(session, ground)
	local furniture = furnitureNavExclusionsAt(session, ground)
	return {
		PhysicalBlockers = #physical,
		FurnitureBlockers = #furniture,
		TotalBlockers = #physical + #furniture,
		ActiveExclusions = activeFurnitureNavExclusionCount(session),
		TotalExclusions = #(session.FurnitureNavExclusions or {}),
		VolumeFits = volumeFits(session, ground),
	}
end

-- Studio-only projection probe. Reports what the corridor-centreing rule wants
-- for a raw PFS waypoint and what the revalidated movement-facing contract
-- actually accepts, so a test can prove a blocked lateral segment retains the
-- original waypoint instead of moving onto a blocked centreline.
function Controller.DebugProjectWaypoint(position: Vector3)
	assert(RunService:IsStudio(), "DebugProjectWaypoint is Studio-only")
	local session = assert(activeSession, "Mall Manager is not running")
	local original = flat(position, session.FloorY)
	local unchecked = centerCorridorWaypoint(session, original, session.FloorY, false)
	local revalidated = centerCorridorWaypoint(session, original, session.FloorY, true)
	local projected = planarDistance(unchecked, original) > .05
	return {
		Original = original,
		Projected = projected,
		UncheckedProjection = unchecked,
		Revalidated = revalidated,
		RetainedOriginal = planarDistance(revalidated, original) <= .05,
		LateralSegmentClear = if projected
			then volumeClear(session, original, unchecked) else true,
		ProjectionEndpointFits = if projected then volumeFits(session, unchecked) else true,
	}
end

-- Studio-only probe for the exact helper used by waypoint consumption and the
-- first active movement target. Unlike DebugProjectWaypoint, the supplied
-- current position can be far enough from the projected target to isolate a
-- blocker in the approach segment while both endpoint volumes remain clear.
function Controller.DebugMovementProjection(currentPosition: Vector3, position: Vector3)
	assert(RunService:IsStudio(), "DebugMovementProjection is Studio-only")
	local session = assert(activeSession, "Mall Manager is not running")
	local currentGround = flat(currentPosition, session.FloorY)
	local original = flat(position, session.FloorY)
	local unchecked = centerCorridorWaypoint(session, original, session.FloorY, false)
	local accepted, usedProjection, approachClear = movementProjectedWaypoint(
		session, currentGround, original)
	return {
		Current = currentGround,
		Original = original,
		UncheckedProjection = unchecked,
		Accepted = accepted,
		UsedProjection = usedProjection,
		ApproachSegmentClear = approachClear,
		CurrentEndpointFits = volumeFits(session, currentGround),
		ProjectionEndpointFits = volumeFits(session, unchecked),
		RetainedOriginal = planarDistance(accepted, original) <= .05,
	}
end

-- Studio-only attack-gate probe. Runs the real attackLineClear contract so a
-- test can show both halves of the wall-hug rule: the Manager closes to within
-- the ranges that permit an attack, and a wall between the two still refuses it.
function Controller.DebugAttackProbe(player: Player)
	assert(RunService:IsStudio(), "DebugAttackProbe is Studio-only")
	local session = assert(activeSession, "Mall Manager is not running")
	local _, _, root = livingPlayer(player, session)
	local distance = if root then planarDistance(session.Root.Position, root.Position) else math.huge
	local confirmClear = attackLineClear(session, player, Tuning.AttackConfirmRange)
	local rangeClear = attackLineClear(session, player, Tuning.AttackRange)
	local goalResolvedAway = session.FinalGoal ~= nil and session.ResolvedFinalGoal ~= nil
		and planarDistance(session.FinalGoal, session.ResolvedFinalGoal) > 1
	return {
		Distance = distance,
		AttackRange = Tuning.AttackRange,
		AttackConfirmRange = Tuning.AttackConfirmRange,
		WithinAttackRange = distance <= Tuning.AttackRange,
		WithinConfirmRange = distance <= Tuning.AttackConfirmRange,
		LineClearAtAttackRange = rangeClear,
		LineClearAtConfirmRange = confirmClear,
		GoalResolvedAwayFromTarget = goalResolvedAway,
		InitiationRange = if goalResolvedAway then Tuning.AttackConfirmRange else Tuning.AttackRange,
		WouldInitiate = if goalResolvedAway then confirmClear else rangeClear,
		Attacking = session.Attacking == true,
		AttackSerial = session.AttackSerial,
		TargetUserId = if session.Target then session.Target.UserId else 0,
		LastCaptureUserId = tonumber(session.StateFolder:GetAttribute(
			"Level3_MallManagerLastCaptureUserId")) or 0,
	}
end

function Controller.DebugSetBlackout(active: boolean)
	assert(RunService:IsStudio(), "DebugSetBlackout is Studio-only")
	local session = assert(activeSession, "Mall Manager is not running")
	applyBlackout(session, active == true)
	return Controller.GetSnapshot()
end

return Controller
