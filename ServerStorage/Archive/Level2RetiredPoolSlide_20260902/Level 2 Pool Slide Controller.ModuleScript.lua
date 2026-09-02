-- Second-pump encounter. The large Pool Slide humanoid replaces Slidemouth.
-- Count distinct started pumps, independently of the station index/order.
local Players = game:GetService("Players")
local ReplicatedStorage = game:GetService("ReplicatedStorage")
local ServerStorage = game:GetService("ServerStorage")
local RunService = game:GetService("RunService")
local CollectionService = game:GetService("CollectionService")

local Navigator = require(script.Parent:WaitForChild("Level 2 Pool Foam Navigator"))
local Controller = {}
local activeSession

local TEMPLATE_NAME = "Level 2 Pool Slide Template"
local RUNTIME_NAME = "Level 2 Pool Slide Runtime"
local MODEL_NAME = "Level 2 Pool Slide"
local PREFIX = "Level2_PoolSlide"
local SPAWN_PUMPS = 2
local SPAWN_MINIMUM_DISTANCE = 60
local SPAWN_RETRY_SECONDS = 2
local SPAWN_VALIDATION_SECONDS = 4
-- Matches the authoritative 2026-08-31 Navigator's CENTRING_QUERY_BUDGET.
-- That implementation appends unexamined points on exhaustion: fail closed.
local CENTRING_QUERY_BUDGET = 72000
local WALK_SPEED = 10
local RUN_SPEED = 24
local RUN_DISTANCE = 120
local PATH_REQUEST_TIMEOUT = 8
local ATTACK_DISTANCE = 5.5
local ATTACK_VERTICAL_DISTANCE = 7
local SPAWN_APPROACH_DISTANCE = 24

local function finite(value)
	return type(value) == "number" and value == value and math.abs(value) < math.huge
end

local function distance(a, b)
	return Vector3.new(a.X - b.X, 0, a.Z - b.Z).Magnitude
end

local function stateFolder()
	local state = ReplicatedStorage:FindFirstChild("Level 2 State")
	return state and state:IsA("Folder") and state or nil
end

local function publish(session, suffix, value)
	local name = PREFIX .. suffix
	local state = stateFolder()
	if state and state:GetAttribute(name) ~= value then state:SetAttribute(name, value) end
	local model = session and session.Model
	if model and model.Parent and model:GetAttribute(name) ~= value then
		model:SetAttribute(name, value)
	end
end

local function resetPublished()
	for suffix, value in pairs({
		Active = false, State = "IDLE", Moving = false, Speed = 0,
		AnimationState = "Idle", AnimationStartedAt = 0, Generation = 0,
		TargetUserId = 0, SpawnRequested = false, SpawnCount = 0,
		SpawnDistance = 0, SpawnAnchor = "", SpawnHidden = false,
		SpawnRouteQueries = 0, SpawnRoutePoints = 0,
		PathStatus = "IDLE", LastError = "",
	}) do publish(nil, suffix, value) end
end

local function alive(session)
	return activeSession == session and session.Manifest.World.Parent ~= nil
		and session.Manifest.World:GetAttribute("Level2_Generation") == session.Generation
end

local function roundReady(session)
	return alive(session) and workspace:GetAttribute("SelectedLevel") == 2
		and workspace:GetAttribute("RoundActive") == true
		and workspace:GetAttribute("WorldGenerated") == true
end

local function pumpCount()
	local value = workspace:GetAttribute("Level2Pumps")
	return finite(value) and math.max(0, math.floor(value)) or 0
end

local function livingRecord(session, player)
	if not roundReady(session) or player.Parent ~= Players
		or player:GetAttribute("InRound") ~= true
		or player:GetAttribute("Escaped") == true then return nil end
	local character = player.Character
	local humanoid = character and character:FindFirstChildOfClass("Humanoid")
	local root = character and character:FindFirstChild("HumanoidRootPart")
	if not (character and character.Parent and humanoid and humanoid.Health > 0
		and root and root:IsA("BasePart")) then return nil end
	return {Player = player, Character = character, Humanoid = humanoid, Root = root}
end

local function livingRecords(session)
	local records = {}
	for _, player in ipairs(Players:GetPlayers()) do
		local record = livingRecord(session, player)
		if record then table.insert(records, record) end
	end
	return records
end

local function setTarget(session, player)
	if session.Target == player then return end
	if session.Target and session.Target.Parent == Players then
		session.Target:SetAttribute(PREFIX .. "Chased", nil)
	end
	session.Target = player
	if player and player.Parent == Players then player:SetAttribute(PREFIX .. "Chased", true) end
	-- Keep this encounter's chase marker separate from other level systems.
	publish(session, "TargetUserId", player and player.UserId or 0)
end

local function motion(session, state, moving, speed, animation)
	session.State = state
	publish(session, "State", state)
	publish(session, "Moving", moving)
	publish(session, "Speed", speed)
	if session.AnimationState ~= animation then
		session.AnimationState = animation
		publish(session, "AnimationStartedAt", workspace:GetServerTimeNow())
		publish(session, "AnimationState", animation)
	end
end

local function rayParams(session)
	local exclusions = {session.RuntimeFolder}
	if session.Manifest.EntityNodes then table.insert(exclusions, session.Manifest.EntityNodes) end
	if session.Manifest.BuoyantProps then table.insert(exclusions, session.Manifest.BuoyantProps) end
	for _, player in ipairs(Players:GetPlayers()) do
		if player.Character then table.insert(exclusions, player.Character) end
	end
	local params = RaycastParams.new()
	params.FilterType = Enum.RaycastFilterType.Exclude
	params.FilterDescendantsInstances = exclusions
	params.IgnoreWater = true
	params.RespectCanCollide = true
	return params
end

local function clearLine(session, from, to)
	local displacement = to - from
	return displacement.Magnitude <= .01
		or workspace:Raycast(from, displacement, rayParams(session)) == nil
end

local function collectAnchors(manifest)
	local anchors, seen = {}, {}
	local function consider(part)
		if not (part and part:IsA("BasePart")) or seen[part] then return end
		if not (part.Name:find("Level 2 Entity Den ", 1, true) == 1
			or part.Name:find("Level 2 Entity Patrol Node ", 1, true) == 1
			or part.Name:find("Level 2 Navigation Node ", 1, true) == 1) then return end
		seen[part] = true
		table.insert(anchors, part)
	end
	for _, container in pairs({manifest.EntityNodes, manifest.EntityDen, manifest.Navigation}) do
		consider(container)
		for _, descendant in ipairs(container:GetDescendants()) do consider(descendant) end
	end
	return anchors
end

local function spawnPumpPosition(records)
	local state = stateFolder()
	local userId = state and state:GetAttribute("Level2_PumpActivatorUserId" .. SPAWN_PUMPS)
	for _, record in ipairs(records) do
		if record.Player.UserId == userId then return record.Root.Position end
	end
	local captured = state and state:GetAttribute("Level2_PumpActivatorPosition" .. SPAWN_PUMPS)
	return typeof(captured) == "Vector3" and captured or records[1].Root.Position
end

local function candidates(session, records)
	local result = {}
	local focus = spawnPumpPosition(records)
	for _, anchor in ipairs(session.Anchors) do
		if not anchor:IsDescendantOf(session.Manifest.World) then continue end
		local minimum, nearest = math.huge, nil
		local observed = false
		for _, record in ipairs(records) do
			local separation = distance(anchor.Position, record.Root.Position)
			if separation < minimum then minimum, nearest = separation, record end
			if clearLine(session, record.Root.Position + Vector3.new(0, 2, 0),
				anchor.Position + Vector3.new(0, 6, 0)) then observed = true end
		end
		-- A hard exclusion for EVERY participant, not just the second activator.
		if minimum >= SPAWN_MINIMUM_DISTANCE then
			table.insert(result, {Anchor = anchor, Nearest = nearest,
				Distance = minimum, Hidden = not observed,
				-- Prefer concealment among nearby candidates, but never put every
				-- hidden room ahead of a safe visible anchor in the player's hall.
				-- That can otherwise spend minutes rejecting distant blocked routes.
				Score = (not observed and 30 or 0) - math.abs(distance(anchor.Position, focus) - 100)})
		end
	end
	table.sort(result, function(a, b) return a.Score > b.Score end)
	return result
end

local function navigationTuning(model)
	local _, size = model:GetBoundingBox()
	local radius = model:GetAttribute("AgentRadius")
	local height = model:GetAttribute("AgentHeight")
	if not finite(radius) then radius = math.max(size.X, size.Z) * .5 + .1 end
	if not finite(height) then height = size.Y end
	assert(radius >= .5 and radius <= 12, "Pool Slide AgentRadius must be between .5 and 12")
	assert(height >= 2 and height <= 24, "Pool Slide AgentHeight must be between 2 and 24")
	-- Import the authored rig at approximately 16 studs tall. These values
	-- describe that imported model; never silently shrink its collision volume.
	return {AgentRadius = radius, PathAgentRadius = radius, AgentHeight = height,
		WaypointSpacing = 5, WaypointArrivalDistance = 2, RepathDistance = 6,
		RepathInterval = .65, StableRoutes = true, PathRequestTimeout = PATH_REQUEST_TIMEOUT,
		FootClearance = .08, FloorProbeAbove = 18,
		FloorProbeDepth = 80, MaxStepHeight = 3.5, MaxTravelStep = .9,
		SteerAngles = {20, 35, 50}}
end

local function escapeClear(navigator)
	local foot = navigator:GetPosition()
	local exits = 0
	for _, direction in ipairs({Vector3.new(1, 0, 0), Vector3.new(-1, 0, 0),
		Vector3.new(0, 0, 1), Vector3.new(0, 0, -1)}) do
		if navigator:_clearAdvance(foot + direction * 1.5) then exits += 1 end
	end
	return exits >= 2
end

local function discardPending(session)
	if session.PendingNavigator then session.PendingNavigator:Destroy() end
	if session.PendingModel then session.PendingModel:Destroy() end
	session.PendingNavigator, session.PendingModel = nil, nil
end

local function spawnAllowed(session)
	-- Developer pause freezes the encounter's motion and damage, not its
	-- existence. Second-pump spawns must remain inspectable with developer ESP.
	return roundReady(session) and pumpCount() >= SPAWN_PUMPS and not session.Spawned
end

local function bodyRouteClear(session, navigator, targetPosition, deadline)
	local points, routeStatus = navigator:_fallbackWaypoints(targetPosition)
	if routeStatus == "NO_PATH" or #points == 0 then return false end
	local function shouldAbort()
		return not spawnAllowed(session) or os.clock() >= deadline
	end
	-- This is the same body/step/sweep certification used by the live route
	-- installer, including its yielding repair pass. A plain graph connection
	-- or accepted SetGraphGoal request does NOT establish that this rig fits.
	local centred, stats = navigator:_centreRoute(points, shouldAbort)
	if shouldAbort() or not stats or stats.Aborted
		or stats.Unwalkable ~= 0 or stats.Unresolved ~= 0
		or not finite(stats.Queries) or stats.Queries >= CENTRING_QUERY_BUDGET
		or not centred or #centred == 0 then return false end
	-- A player pulling a lever can stand beside a pump plinth where this large
	-- body cannot fit. A nearby, fully certified approach with clear sight is
	-- enough to begin the encounter; spawning must not require an immediate
	-- kill route. Damage still uses the separate strict 5.5-stud attack gate.
	-- Distant endpoints and approaches across walls remain invalid.
	if stats.GoalFallback then
		local vertical = targetPosition.Y - stats.GoalFallback.Y
		if distance(stats.GoalFallback, targetPosition) > SPAWN_APPROACH_DISTANCE
			or vertical < -1 or vertical > ATTACK_VERTICAL_DISTANCE
			or not clearLine(session, stats.GoalFallback + Vector3.new(0, 3, 0), targetPosition)
			then return false end
	end
	return true, stats, #centred
end

local function spawnModel(session)
	if not spawnAllowed(session) then return false, "spawn cancelled" end
	local records = livingRecords(session)
	if #records == 0 then return false, "no living round participants" end
	local ranked = candidates(session, records)
	if #ranked == 0 then return false, "no safe anchor at least 60 studs from every player" end
	local model = session.Template:Clone()
	assert(model, "Pool Slide template must be Archivable")
	session.PendingModel = model
	model.Name = MODEL_NAME
	for _, descendant in ipairs(model:GetDescendants()) do
		if descendant:IsA("BasePart") then
			descendant.Anchored = true
			descendant.CanCollide = false
			descendant.CanTouch = false
			descendant.CanQuery = false
			descendant.Massless = true
			descendant.AssemblyLinearVelocity = Vector3.zero
			descendant.AssemblyAngularVelocity = Vector3.zero
		elseif descendant:IsA("BaseScript") then descendant.Enabled = false end
	end
	model:SetAttribute("Level2_Generation", session.Generation)
	model:SetAttribute("ControllerManaged", true)
	-- Validate while private. Clients must never see rejected candidates or an
	-- unpositioned clone flash at the template's authored coordinates.
	model.Parent = ServerStorage
	local tuning = navigationTuning(model)
	local options = {
		RuntimeFolder = session.RuntimeFolder,
		ObstacleExclusions = session.Manifest.BuoyantProps and {session.Manifest.BuoyantProps} or {},
	}
	local navigator = Navigator.new(model, session.Manifest, tuning, options)
	session.PendingNavigator = navigator
	local selected
	local deadline = os.clock() + SPAWN_VALIDATION_SECONDS
	local cursor = session.SpawnCandidateCursor or 0
	for offset = 1, math.min(24, #ranked) do
		local index = (cursor + offset - 1) % #ranked + 1
		local candidate = ranked[index]
		if offset % 4 == 0 then task.wait() end -- bound sustained spawn-probe work
		if not spawnAllowed(session) then return false, "spawn cancelled" end
		if os.clock() >= deadline then break end
		session.SpawnCandidateCursor = index -- next retry continues after this candidate
		if navigator.HasGrounded then
			-- WarpTo retains its swept-movement history in the live Navigator.
			-- A rejected private candidate must not make the next room look like
			-- a proposed walk through every wall between the two spawn anchors.
			navigator:Destroy()
			navigator = Navigator.new(model, session.Manifest, tuning, options)
			session.PendingNavigator = navigator
		end
		local position = candidate.Anchor.Position
		local target = livingRecord(session, candidate.Nearest.Player)
		if not target then continue end
		local targetPosition = target.Root.Position
		local routeValid = false
		if navigator:WarpTo(position, targetPosition - position, true) then
			if escapeClear(navigator) then
				local stats, pointCount
				routeValid, stats, pointCount = bodyRouteClear(session, navigator, targetPosition, deadline)
				candidate.RouteStats, candidate.RoutePoints = stats, pointCount
			end
		end
		if routeValid then
			local safe = true
			-- Re-read participants immediately before the commit, including anyone
			-- who moved toward this anchor while a future validation step yielded.
			local latest = livingRecords(session)
			if #latest == 0 then safe = false end
			for _, record in ipairs(latest) do
				if distance(navigator:GetPosition(), record.Root.Position) < SPAWN_MINIMUM_DISTANCE then
					safe = false
					break
				end
			end
			if safe then selected = candidate break end
		end
	end
	if not selected then return false, "no candidate has clear body volume, floor, and hall route" end
	if not spawnAllowed(session) then return false, "spawn cancelled" end
	session.Model, session.Navigator = model, navigator
	session.PendingModel, session.PendingNavigator = nil, nil
	session.Spawned = true -- latch BEFORE replication; never spawn a second clone this round
	session.SpawnCount += 1
	session.ProgressAt = os.clock()
	session.ProgressPosition = navigator:GetPosition()
	publish(session, "Active", true)
	publish(session, "Generation", session.Generation)
	publish(session, "SpawnCount", session.SpawnCount)
	publish(session, "SpawnDistance", selected.Distance)
	publish(session, "SpawnAnchor", selected.Anchor.Name)
	publish(session, "SpawnHidden", selected.Hidden)
	publish(session, "SpawnRouteQueries", selected.RouteStats.Queries)
	publish(session, "SpawnRoutePoints", selected.RoutePoints)
	publish(session, "LastError", "")
	session.AnimationState = nil
	motion(session, workspace:GetAttribute("EntityPaused") == true and "PAUSED" or "IDLE",
		false, 0, "Idle")
	pcall(function() model.ModelStreamingMode = Enum.ModelStreamingMode.Persistent end)
	model.Parent = session.RuntimeFolder
	CollectionService:AddTag(model, "Level2HostileEntity")
	CollectionService:AddTag(model, "Level2PoolSlideEntity")
	return true
end

local function requestSpawn(session)
	if session.Spawning or os.clock() < session.NextSpawnAttempt then return end
	session.Spawning = true -- protects deferred work from later Heartbeats
	motion(session, "SPAWNING", false, 0, "Idle")
	task.defer(function()
		if not alive(session) then return end
		local callOk, spawned, failure = xpcall(function() return spawnModel(session) end, debug.traceback)
		if not callOk then failure, spawned = spawned, false end
		if not spawned then discardPending(session) end
		session.Spawning = false
		if not alive(session) then return end
		if not spawned then
			session.NextSpawnAttempt = os.clock() + SPAWN_RETRY_SECONDS
			motion(session, "SPAWN_RETRY", false, 0, "Idle")
			publish(session, "LastError", tostring(failure))
			if os.clock() >= session.NextWarning then
				session.NextWarning = os.clock() + 10
				warn("[Level 2 Pool Slide] " .. tostring(failure))
			end
		end
	end)
end

local function chooseTarget(session)
	local position = session.Navigator:GetPosition()
	local nearest, minimum = nil, math.huge
	for _, record in ipairs(livingRecords(session)) do
		local separation = distance(position, record.Root.Position)
		if separation < minimum then nearest, minimum = record, separation end
	end
	local current = session.Target and livingRecord(session, session.Target)
	if current and distance(position, current.Root.Position) <= minimum + 15 then return current end
	setTarget(session, nearest and nearest.Player or nil)
	return nearest
end

local function tryAttack(session, record, now)
	local live = livingRecord(session, record.Player)
	if now < session.AttackCooldown or not live or live.Character ~= record.Character then return false end
	local foot = session.Navigator:GetPosition()
	local root = record.Root.Position
	local vertical = root.Y - foot.Y
	if distance(foot, root) > ATTACK_DISTANCE or vertical < -1
		or vertical > ATTACK_VERTICAL_DISTANCE then return false end
	-- Lower-body reach, not an enormous whole-model Touch hitbox. Floors and
	-- walls between the entity and the player block this server-owned attack.
	if not clearLine(session, foot + Vector3.new(0, 3, 0), root) then return false end
	session.AttackCooldown = now + 1
	record.Humanoid.Health = 0
	session.Navigator:Stop()
	setTarget(session, nil)
	motion(session, "ATTACK", false, 0, "Idle")
	return true
end

local function updateModel(session, deltaTime)
	local now = os.clock()
	local navigator = session.Navigator
	if now >= session.NextTargetRefresh then
		chooseTarget(session)
		session.NextTargetRefresh = now + .3
	end
	local record = session.Target and livingRecord(session, session.Target)
	if not record then
		setTarget(session, nil)
		navigator:Stop()
		session.CurrentSpeed = 0
		motion(session, "IDLE", false, 0, "Idle")
		return
	end
	if tryAttack(session, record, now) then return end
	local before = navigator:GetPosition()
	local running = distance(before, record.Root.Position) <= RUN_DISTANCE
	local desiredSpeed = running and RUN_SPEED or WALK_SPEED
	local dt = math.clamp(deltaTime, 0, .1)
	local difference = desiredSpeed - session.CurrentSpeed
	session.CurrentSpeed += math.clamp(difference, -36 * dt, 28 * dt)
	if now < session.GraphRecoveryUntil then
		navigator:SetGraphGoal(record.Root.Position)
	else navigator:SetGoal(record.Root.Position) end
	local reached = navigator:Step(dt, session.CurrentSpeed)
	local moved = distance(before, navigator:GetPosition())
	local navigationState = navigator:GetDebugSnapshot()
	motion(session, navigationState.WaitingForClearance == true and "WAITING"
		or (running and "CHASE" or "APPROACH"), moved > .01,
		dt > 0 and moved / dt or 0, moved > .01 and (running and "Run" or "Walk") or "Idle")
	publish(session, "PathStatus", navigator:GetStatus())
	if tryAttack(session, record, now) then return end
	if now - session.ProgressAt >= 2 then
		local snapshot = navigator:GetDebugSnapshot()
		local requestAge = finite(snapshot.RequestStartedAt)
			and math.max(0, now - snapshot.RequestStartedAt) or math.huge
		local planning = snapshot.Computing == true and requestAge < PATH_REQUEST_TIMEOUT
		if reached == true or snapshot.Reached == true or snapshot.WaitingForClearance == true then
			-- The player's centre may be inside a pump plinth or another place
			-- this body cannot occupy. A certified approach is arrival, not a jam.
			session.GraphRecoveryUntil = 0
		elseif not planning and distance(session.ProgressPosition, navigator:GetPosition()) < 1 then
			-- Body-clearance planning can legitimately outlast this two-second
			-- sample. Do not keep cancelling it before its bounded deadline.
			session.GraphRecoveryUntil = now + 1.5
			navigator:SetGraphGoal(record.Root.Position, true)
		end
		session.ProgressAt = now
		session.ProgressPosition = navigator:GetPosition()
	end
end

local function heartbeat(session, deltaTime)
	if activeSession ~= session then return end
	if not alive(session) then Controller.Stop() return end
	if not roundReady(session) then
		if session.Navigator then session.Navigator:Stop() end
		session.CurrentSpeed = 0
		setTarget(session, nil)
		motion(session, "DORMANT", false, 0, "Idle")
		return
	end
	-- This is the count of distinct started levers, NOT the station's Index.
	-- Heartbeat reads after the objective publishes the full activator payload.
	if not session.Spawned and pumpCount() >= SPAWN_PUMPS then
		publish(session, "SpawnRequested", true)
		requestSpawn(session)
	end
	if not session.Spawned then return end
	if not (session.Model and session.Model.Parent and session.Navigator) then
		setTarget(session, nil)
		publish(session, "Active", false)
		motion(session, "REMOVED", false, 0, "Idle")
		return -- the once-per-round latch deliberately remains set
	end
	-- Spawn eligibility is evaluated above even while paused. A materialized
	-- entity is visible to ESP, but cannot acquire a target, move, or attack.
	if workspace:GetAttribute("EntityPaused") == true then
		session.Navigator:Stop()
		session.CurrentSpeed = 0
		setTarget(session, nil)
		motion(session, "PAUSED", false, 0, "Idle")
		return
	end
	updateModel(session, deltaTime)
end

function Controller.Stop()
	local session = activeSession
	activeSession = nil -- invalidates deferred work and in-flight navigation first
	if session then
		for _, connection in ipairs(session.Connections) do connection:Disconnect() end
		setTarget(session, nil)
		discardPending(session)
		if session.Navigator then session.Navigator:Destroy() end
		if session.RuntimeFolder then session.RuntimeFolder:Destroy() end
	end
	resetPublished()
end

function Controller.Start(manifest, generation)
	Controller.Stop()
	if not (type(manifest) == "table" and manifest.World and manifest.World:IsA("Model")
		and manifest.World.Parent and type(manifest.Layout) == "table" and finite(generation)
		and manifest.World:GetAttribute("Level2_Generation") == generation) then
		return nil, "invalid Level 2 manifest or generation"
	end
	local assets = ServerStorage:FindFirstChild("Level2Assets")
	local template = assets and assets:FindFirstChild(TEMPLATE_NAME)
	if not (template and template:IsA("Model") and template.Archivable and template.PrimaryPart) then
		return nil, "missing imported ServerStorage.Level2Assets." .. TEMPLATE_NAME
	end
	local anchors = collectAnchors(manifest)
	if #anchors == 0 then return nil, "manifest has no entity navigation anchors" end
	local runtime = Instance.new("Folder")
	runtime.Name = RUNTIME_NAME
	runtime:SetAttribute("Level2_Generation", generation)
	runtime.Parent = manifest.World
	local session = {
		Manifest = manifest, Generation = generation, Template = template,
		RuntimeFolder = runtime, Anchors = anchors, Connections = {},
		Spawned = false, Spawning = false, SpawnCount = 0, NextSpawnAttempt = 0,
		NextWarning = 0, CurrentSpeed = 0, NextTargetRefresh = 0,
		AttackCooldown = 0, GraphRecoveryUntil = 0, State = "DORMANT",
	}
	activeSession = session
	publish(session, "Generation", generation)
	motion(session, "DORMANT", false, 0, "Idle")
	table.insert(session.Connections, RunService.Heartbeat:Connect(function(dt) heartbeat(session, dt) end))
	table.insert(session.Connections, Players.PlayerRemoving:Connect(function(player)
		if activeSession == session and session.Target == player then setTarget(session, nil) end
	end))
	return session
end

function Controller.IsRunning()
	return activeSession ~= nil and alive(activeSession)
end

function Controller.GetDebugSnapshot()
	local session = activeSession
	if not session then return {Running = false} end
	return {Running = alive(session), Generation = session.Generation, Pumps = pumpCount(),
		Spawned = session.Spawned, Spawning = session.Spawning, SpawnCount = session.SpawnCount,
		State = session.State, TargetUserId = session.Target and session.Target.UserId or 0,
		Navigation = session.Navigator and session.Navigator:GetDebugSnapshot() or nil}
end

return Controller
