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
local Tuning = Configuration.MallManager

local Controller = {}
local activeSession: any = nil
local activeLayout: any = nil
local playChaseScream: (any) -> ()
local stopChaseScream: (any) -> ()

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

local function publishTarget(session: any, player: Player?)
	if player and HidingController.IsHidden(player, session.Generation) then player = nil end
	if session.Target == player then return end
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

local function clearPath(session: any, status: string?)
	session.PathToken += 1
	session.Path = nil
	session.PathObject = nil
	session.WaypointIndex = 1
	session.PathGoal = nil
	session.PathComputing = false
	session.InFlightPathGoal = nil
	session.PendingPathGoal = nil
	session.PendingPathForce = false
	disconnect(session.PathBlockedConnection)
	session.PathBlockedConnection = nil
	if status then publishPathStatus(session, status) end
end

local function clearGoal(session: any)
	session.FinalGoal = nil
	session.StrategicPoints = {}
	session.StrategicIndex = 1
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
	local prototypes = ServerStorage:WaitForChild("Level3Assets")
		:WaitForChild("EntitySounds"):WaitForChild("MallManager")
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
	local prototypes = ServerStorage:WaitForChild("Level3Assets")
		:WaitForChild("EntitySounds"):WaitForChild("MallManagerScreams")
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

local function centerCorridorWaypoint(position: Vector3, floorY: number): Vector3
	local localPosition = position - Configuration.WorldOrigin
	local bestProjection: Vector3? = nil
	local bestLateralDistance = math.huge
	local lateralLimit = Configuration.CorridorWidth * .5 + .25
	for _, link in ipairs(layoutLinks()) do
		if link.Door ~= "HiddenExit" then
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
	return bestProjection or flat(position, floorY)
end

local function nearestRoomId(position: Vector3): string
	local rooms = layoutRooms()
	local firstRoom = assert(rooms[1], "Mall Manager layout must contain at least one room")
	local bestId = firstRoom.Id
	local bestDistance = math.huge
	for _, room in ipairs(rooms) do
		local center = Configuration.WorldOrigin + Vector3.new(room.X, 0, room.Z)
		local distance = planarDistance(position, center)
		if distance < bestDistance then
			bestDistance = distance
			bestId = room.Id
		end
	end
	return bestId
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

local function navigationParams(session: any): RaycastParams
	local params = RaycastParams.new()
	params.FilterType = Enum.RaycastFilterType.Exclude
	params.FilterDescendantsInstances = navigationIgnored(session)
	params.IgnoreWater = true
	params.RespectCanCollide = true
	return params
end

local function navigationOverlapParams(session: any): OverlapParams
	local params = OverlapParams.new()
	params.FilterType = Enum.RaycastFilterType.Exclude
	params.FilterDescendantsInstances = navigationIgnored(session)
	params.RespectCanCollide = true
	params.MaxParts = 1
	return params
end

local function clearanceBox(groundPosition: Vector3): (CFrame, Vector3)
	local castHeight = math.max(2, Tuning.AgentHeight - .6)
	local center = groundPosition + Vector3.new(0, castHeight * .5 + .2, 0)
	local size = Vector3.new(Tuning.SweepRadius * 2, castHeight, Tuning.SweepRadius * 2)
	-- Keep the square aligned to the axis-aligned Level 3 corridors. Rotating a
	-- square sweep at a corner would artificially widen it by sqrt(2).
	return CFrame.new(center), size
end

local function volumeFits(session: any, groundPosition: Vector3, params: OverlapParams?): boolean
	local boxCFrame, size = clearanceBox(groundPosition)
	local overlapParams = params or navigationOverlapParams(session)
	return #workspace:GetPartBoundsInBox(boxCFrame, size, overlapParams) == 0
end

local function volumeClear(session: any, startGround: Vector3, endGround: Vector3): boolean
	local overlapParams = navigationOverlapParams(session)
	if not volumeFits(session, startGround, overlapParams)
		or not volumeFits(session, endGround, overlapParams) then
		return false
	end
	local direction = endGround - startGround
	if direction.Magnitude <= .05 then return true end
	local castCFrame, size = clearanceBox(startGround)
	local hit = workspace:Blockcast(castCFrame, size, direction, navigationParams(session))
	return hit == nil
end

local function rebuildStrategicRoute(session: any)
	local finalGoal = session.FinalGoal
	if not finalGoal then
		session.StrategicPoints = {}
		session.StrategicIndex = 1
		return
	end
	local startId = nearestRoomId(session.Root.Position)
	local goalId = nearestRoomId(finalGoal)
	local route = graphRoute(session, startId, goalId)
	local points = {}
	local function appendPoint(point: Vector3?)
		if point and (#points == 0 or planarDistance(points[#points], point) > .05) then
			table.insert(points, point)
		end
	end
	-- Generated spawns and sensed goals may sit anywhere inside a room. Centre
	-- through the current room and every graph room, including the goal room,
	-- before steering to the exact final position. Without these two endpoint
	-- centres, GRAPH_FALLBACK cuts diagonally into a wall beside the portal and
	-- becomes motionless whenever PathfindingService cannot build a replacement.
	for _, roomId in ipairs(route) do
		appendPoint(roomCenter(roomId, session.FloorY))
	end
	appendPoint(finalGoal)
	session.StrategicPoints = points
	session.StrategicIndex = 1
end

local function setGoal(session: any, goal: Vector3?, force: boolean?)
	if not goal then
		clearGoal(session)
		return
	end
	local grounded = flat(goal, session.FloorY)
	local goalThreshold = if session.Blackout
		then Tuning.BlackoutPathGoalMoveThreshold else Tuning.PathGoalMoveThreshold
	local changed = not session.FinalGoal
		or planarDistance(session.FinalGoal, grounded) >= goalThreshold
	if not changed and not force then return end
	session.FinalGoal = grounded
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
	if not finalGoal then return nil end
	local currentGround = flat(session.Root.Position, session.FloorY)
	if planarDistance(currentGround, finalGoal) <= Tuning.GoalTolerance then return finalGoal end
	local directRange = if session.Blackout then Tuning.BlackoutDirectPathRange else Tuning.DirectPathRange
	if planarDistance(currentGround, finalGoal) <= directRange
		and volumeClear(session, currentGround, finalGoal) then
		return finalGoal
	end
	while session.StrategicIndex <= #session.StrategicPoints do
		local point = session.StrategicPoints[session.StrategicIndex]
		if planarDistance(currentGround, point) <= Tuning.GoalTolerance then
			session.PathFailures = 0
			session.ConsecutiveObstructions = 0
			session.ProgressResetPosition = currentGround
			session.StrategicIndex += 1
		else
			return point
		end
	end
	return finalGoal
end

local function abandonFailedPatrol(session: any)
	if session.PathFailures >= Tuning.MaxPathFailures and session.State == "PATROL" then
		session.PatrolGoal = nil
		clearGoal(session)
	end
end

local function requestPath(session: any, destination: Vector3, force: boolean?)
	if not liveSession(session) then return end
	if session.PathComputing then
		-- Never drop a materially fresher moving-target goal while an older
		-- ComputeAsync is running, but do not enqueue the same goal every frame.
		if not session.InFlightPathGoal
			or planarDistance(session.InFlightPathGoal, destination) >= .05 then
			session.PendingPathGoal = destination
			session.PendingPathForce = session.PendingPathForce == true or force == true
		end
		return
	end
	local now = os.clock()
	local interval = if session.Blackout then Tuning.BlackoutPathRecomputeSeconds else Tuning.PathRecomputeSeconds
	if not force and now - session.LastPathRequest < interval then
		return
	end
	session.LastPathRequest = now
	session.PathComputing = true
	session.InFlightPathGoal = destination
	session.PathToken += 1
	local token = session.PathToken
	local function schedulePending()
		local pending = session.PendingPathGoal
		local pendingForce = session.PendingPathForce == true
		session.PendingPathGoal = nil
		session.PendingPathForce = false
		if pending and planarDistance(pending, destination) >= .05 then
			task.defer(function()
				if liveSession(session) then requestPath(session, pending, pendingForce or true) end
			end)
		end
	end
	-- Pathfinding positions represent the agent's ground contact, not the
	-- custom rig's 4.1-stud pivot. Using the pivot in a low tunnel makes the
	-- 10-stud agent appear to extend through the ceiling and returns NoPath.
	local origin = flat(session.Root.Position, session.FloorY)
		+ Vector3.new(0, Tuning.PathSampleHeight, 0)
	local target = destination + Vector3.new(0, Tuning.PathSampleHeight, 0)
	publishPathStatus(session, "COMPUTING")
	task.spawn(function()
		local path = PathfindingService:CreatePath({
			AgentRadius = Tuning.AgentRadius,
			AgentHeight = Tuning.AgentHeight,
			AgentCanJump = false,
			AgentCanClimb = false,
			WaypointSpacing = Tuning.WaypointSpacing,
		})
		local ok = pcall(function() path:ComputeAsync(origin, target) end)
		if not liveSession(session) or session.PathToken ~= token then return end
		session.PathComputing = false
		session.InFlightPathGoal = nil
		local pending = session.PendingPathGoal
		if pending and planarDistance(pending, destination) >= .05 then
			publishPathStatus(session, "REFRESH_PENDING")
			schedulePending()
			return
		end
		if not ok or path.Status ~= Enum.PathStatus.Success then
			session.PathFailures += 1
			-- A failed refresh is not permission to discard the route currently
			-- carrying the Manager. Authored room-center steering remains available
			-- when no PathfindingService route has ever succeeded.
			publishPathStatus(session, if session.Path then "ROUTE_RETAINED" else "GRAPH_FALLBACK")
			abandonFailedPatrol(session)
			return
		end
		local waypoints = path:GetWaypoints()
		if #waypoints < 2 then
			session.PathFailures += 1
			publishPathStatus(session, if session.Path then "ROUTE_RETAINED" else "GRAPH_FALLBACK")
			abandonFailedPatrol(session)
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
		for index = 2, #waypoints do
			local candidate = centerCorridorWaypoint(
				flat(waypoints[index].Position, session.FloorY), session.FloorY)
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
			local candidate = centerCorridorWaypoint(
				flat(waypoints[index].Position, session.FloorY), session.FloorY)
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
			schedulePending()
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
		schedulePending()
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
				if humanoid.WalkSpeed <= 10.5 then
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

local function choosePatrolGoal(session: any, now: number)
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
	if session.PatrolGoal
		and planarDistance(session.Root.Position, session.PatrolGoal) <= Tuning.GoalTolerance + 1 then
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

local function attackLineClear(session: any, player: Player, maximumRange: number): (boolean, Humanoid?)
	if HidingController.IsHidden(player, session.Generation) then return false, nil end
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
	local clear = attackLineClear(session, player, Tuning.AttackRange)
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
		if volumeClear(session, currentGround, destination) then return destination end
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
		local position = centerCorridorWaypoint(flat(waypoint.Position, session.FloorY), session.FloorY)
		if planarDistance(currentGround, position) <= dynamicReach then
			session.WaypointIndex += 1
		else
			break
		end
	end
	if session.WaypointIndex <= #session.Path then
		-- Small four-stud PFS zigzags made the visual rig twitch. Follow the
		-- furthest clearance-checked point in a short lookahead window instead.
		local bestIndex = session.WaypointIndex
		local bestPosition = centerCorridorWaypoint(
			flat(session.Path[bestIndex].Position, session.FloorY), session.FloorY)
		local lookahead = if session.Blackout
			then Tuning.BlackoutPathLookaheadWaypoints else Tuning.PathLookaheadWaypoints
		local maximumIndex = math.min(#session.Path,
			session.WaypointIndex + lookahead - 1)
		for index = session.WaypointIndex + 1, maximumIndex do
			local candidate = centerCorridorWaypoint(
				flat(session.Path[index].Position, session.FloorY), session.FloorY)
			if volumeClear(session, currentGround, candidate) then
				bestIndex = index
				bestPosition = candidate
			else
				break
			end
		end
		session.WaypointIndex = bestIndex
		return bestPosition
	end
	if volumeClear(session, currentGround, destination) then return destination end
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
	local currentGround = flat(session.Root.Position, session.FloorY)
	session.LastProgressPosition = currentGround
	session.LastProgressAt = now
	session.ProgressResetPosition = currentGround
	session.PathFailures = 0
	session.ConsecutiveObstructions = 0
	publishPathStatus(session, "RECOVERY_REPATH")
end

local AVOIDANCE_ANGLES = {15, -15, 30, -30, 45, -45, 70, -70, 90, -90}
local function clearSteeringStep(session: any, currentGround: Vector3, desired: Vector3,
	distance: number): (Vector3?, Vector3?)
	local straight = currentGround + desired * distance
	if volumeClear(session, currentGround, straight) then return straight, desired end

	local bestPosition: Vector3? = nil
	local bestDirection: Vector3? = nil
	local bestScore = -math.huge
	for _, degrees in ipairs(AVOIDANCE_ANGLES) do
		local candidateDirection = CFrame.fromAxisAngle(
			Vector3.yAxis, math.rad(degrees)):VectorToWorldSpace(desired)
		local candidate = currentGround + candidateDirection * distance
		if volumeClear(session, currentGround, candidate) then
			local score = candidateDirection:Dot(desired) * 2
				+ candidateDirection:Dot(session.Heading) * .35
				- math.abs(degrees) * .001
			if score > bestScore then
				bestScore = score
				bestPosition = candidate
				bestDirection = candidateDirection
			end
		end
	end
	return bestPosition, bestDirection
end

local function updateMovement(session: any, dt: number, now: number)
	if not validRound(session) then
		session.CurrentMoveSpeed = 0
		session.LastActualStepDistance = 0
		setWalk(session, false, 0)
		return
	end
	local desiredSpeed = currentSpeed(session)
	local destination = currentDestination(session)
	if desiredSpeed <= 0 or not destination then
		session.CurrentMoveSpeed = 0
		session.LastActualStepDistance = 0
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
	local movementTarget = movementWaypoint(session, destination, desiredSpeed, dt)
	if not movementTarget then
		session.CurrentMoveSpeed = 0
		session.LastActualStepDistance = 0
		setWalk(session, false, 0)
		return
	end
	local currentGround = flat(session.Root.Position, session.FloorY)
	local offset = movementTarget - currentGround
	if offset.Magnitude <= .05 then
		session.CurrentMoveSpeed = 0
		session.LastActualStepDistance = 0
		setWalk(session, false, 0)
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
		session, currentGround, direction, distance)
	if distance <= .001 or not proposed or not steeredDirection then
		session.ConsecutiveObstructions += 1
		local exhausted = session.ConsecutiveObstructions >= Tuning.ObstructionRecoveryAttempts
		if exhausted then
			clearPath(session, "OBSTRUCTION_REPATH")
			recoverToSafeSample(session, now)
		else
			publishPathStatus(session, "LOCAL_AVOIDANCE_WAIT")
		end
		requestPath(session, destination, true)
		session.LastActualStepDistance = 0
		setWalk(session, false, 0)
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
	session.ConsecutiveObstructions = 0
	session.LastActualStepDistance = distance
	setWalk(session, true, session.CurrentMoveSpeed)
	if planarDistance(session.ProgressResetPosition, proposed) >= Tuning.ProgressResetDistance then
		session.ProgressResetPosition = proposed
		session.PathFailures = 0
		session.ConsecutiveObstructions = 0
	end

	local actualGround = flat(session.Root.Position, session.FloorY)
	if planarDistance(session.LastProgressPosition, actualGround) >= Tuning.StuckDistance then
		session.LastProgressPosition = actualGround
		session.LastProgressAt = now
	elseif now - session.LastProgressAt >= Tuning.StuckSeconds then
		session.LastProgressAt = now
		session.PathFailures += 1
		local exhausted = session.PathFailures >= Tuning.MaxPathFailures
		clearPath(session, "STUCK_REPATH")
		if exhausted then resetBlockedRoute(session, now) end
		requestPath(session, destination, true)
	end
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
	state:SetAttribute("Level3_MallManagerSpeed", 0)
	state:SetAttribute("Level3_MallManagerAwarenessRange", 0)
	state:SetAttribute("Level3_MallManagerSpawnRoomId", Tuning.SpawnRoomId)
	state:SetAttribute("Level3_MallManagerSpawnDistance", 0)
	state:SetAttribute("Level3_MallManagerSpawnVisibleCount", 0)
	state:SetAttribute("Level3_MallManagerSpawnPathValidated", false)
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
	local assets = ServerStorage:WaitForChild("Level3Assets")
	local animations = assets:WaitForChild("EntityAnimations"):WaitForChild("MallManager")
	local walk = animations:WaitForChild("Walk")
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

local function chooseBlackoutSpawn(manifest: any, generation: number): any?
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
	selected.PathValidated = true
	return selected
end

local function cloneManager(manifest: any, spawnPosition: Vector3, facePosition: Vector3,
	spawnRoomId: string): (Model, BasePart, number)
	local assets = ServerStorage:WaitForChild("Level3Assets")
	local templates = assets:WaitForChild("EntityTemplates")
	local template = templates:WaitForChild(Tuning.TemplateName)
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
		FinalGoal = nil,
		StrategicPoints = {},
		StrategicIndex = 1,
		Path = nil,
		PathObject = nil,
		PathGoal = nil,
		PathToken = 0,
		PathComputing = false,
		InFlightPathGoal = nil,
		PendingPathGoal = nil,
		PendingPathForce = false,
		PathBlockedConnection = nil,
		PathStatus = "BOOTING",
		PathFailures = 0,
		PathSwapSerial = 0,
		WaypointIndex = 1,
		LastPathRequest = -math.huge,
		Heading = (function()
			local direction = flat(spawnData.Anchor.Position, floorY) - spawnData.Position
			return if direction.Magnitude > .01 then direction.Unit else Vector3.new(-1, 0, 0)
		end)(),
		CurrentMoveSpeed = 0,
		LastActualStepDistance = 0,
		LastProgressPosition = flat(root.Position, floorY),
		LastProgressAt = os.clock(),
		ProgressResetPosition = flat(root.Position, floorY),
		ConsecutiveObstructions = 0,
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
	state:SetAttribute("Level3_MallManagerSpawnPathValidated", spawnData.PathValidated == true)
	state:SetAttribute("Level3_MallManagerSpawnAnchorUserId", spawnData.Anchor.Player.UserId)
	state:SetAttribute("Level3_MallManagerSpawnGroupSize", spawnData.GroupSize)
	state:SetAttribute("Level3_MallManagerSpawnCycle", spawnData.Cycle)
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
	model:SetAttribute("Level3_MallManagerSpawnPathValidated", spawnData.PathValidated == true)
	model:SetAttribute("Level3_MallManagerSpawnAnchorUserId", spawnData.Anchor.Player.UserId)
	model:SetAttribute("Level3_MallManagerSpawnGroupSize", spawnData.GroupSize)
	model:SetAttribute("Level3_MallManagerSpawnCycle", spawnData.Cycle)
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
			session.LastProgressPosition = flat(root.Position, floorY)
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
	table.insert(session.Connections, workspace:GetAttributeChangedSignal("Level3BlackoutActive"):Connect(function()
		applyBlackout(session, workspace:GetAttribute("Level3BlackoutActive") == true)
	end))
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

	applyBlackout(session, workspace:GetAttribute("Level3BlackoutActive") == true)
	-- Seed only toward an exposed player. Hidden players may still define the dense
	-- spawn group, but the Manager never receives their concealed location.
	local seedPlayer, seedRoot = nearestExposedPlayer(session)
	if seedPlayer and seedRoot then
		session.LastKnownPosition = flat(seedRoot.Position, floorY)
		session.LastSenseAt = os.clock()
		setGoal(session, session.LastKnownPosition, true)
	else
		session.LastKnownPosition = nil
		session.LastSenseAt = -math.huge
	end
	roundChanged()
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
		Blackout = session.Blackout,
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
		GoalDistance = if session.FinalGoal
			then planarDistance(session.Root.Position, session.FinalGoal) else 0,
		PathFailures = session.PathFailures,
		ConsecutiveObstructions = session.ConsecutiveObstructions,
		WaypointIndex = session.WaypointIndex,
		WaypointCount = if session.Path then #session.Path else 0,
	}
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
	session.ProgressResetPosition = flat(session.Root.Position, session.FloorY)
	session.SafeCFrames = {session.Model:GetPivot()}
	publishState(session, "PATROL")
	setGoal(session, destination, true)
	return Controller.GetSnapshot()
end

function Controller.DebugSetBlackout(active: boolean)
	assert(RunService:IsStudio(), "DebugSetBlackout is Studio-only")
	local session = assert(activeSession, "Mall Manager is not running")
	applyBlackout(session, active == true)
	return Controller.GetSnapshot()
end

return Controller
