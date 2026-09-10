-- DRAFT ONLY: v1767 integration; not imported, tested or approved for publish.
-- New v10 giant. Preserve Pool Foam and the shared Navigator's source/behavior.
-- Honest preverified fit, bounded spawn probes, same-instance escalation,
-- server-owned windup/hit/recovery and existing audio/ESP attribute contract.
local Players = game:GetService("Players")
local ReplicatedStorage = game:GetService("ReplicatedStorage")
local ServerStorage = game:GetService("ServerStorage")
local RunService = game:GetService("RunService")
local CollectionService = game:GetService("CollectionService")
local PlayerProtection = require(game:GetService("ServerScriptService"):WaitForChild("PlayerProtection"))

local Navigator = require(script.Parent:WaitForChild("Level 2 Pool Slide Navigator"))
local Configuration = require(script.Parent:WaitForChild("Level 2 Pool Slide Configuration"))
local RigAdapter = require(script.Parent:WaitForChild("Level 2 Pool Slide Rig Adapter"))
local Controller = {}
local activeSession

local TEMPLATE_NAME = "Level 2 Pool Slide Template"
local RUNTIME_NAME = "Level 2 Pool Slide Runtime"
local MODEL_NAME = "Level 2 Pool Slide"
local PREFIX = "Level2_PoolSlide"
local SPAWN_PUMPS = 2
local ENRAGE_PUMPS = 3
local SPAWN_MINIMUM_DISTANCE = 100
local SPAWN_RETRY_SECONDS = 5
local SPAWN_MAX_PROBES_PER_PASS = 24
local SPAWN_PROBE_INTERVAL = .05
local PATH_REQUEST_TIMEOUT = 3
local TARGET_REFRESH_SECONDS = .25
local GOAL_REFRESH_SECONDS = .15
local WATCHDOG_SECONDS = 3
local WATCHDOG_COOLDOWN = 8
-- The accepted 14.8-stud navigation body stops outside walls/corners.
-- Cover its ~9.02-stud corner clearance plus the existing 1.4 arrival margin;
-- retain the windup, facing arc, height and physical line-of-sight checks.
local ATTACK_DISTANCE = 10.5
local ATTACK_VERTICAL_DISTANCE = 7
local SPAWN_APPROACH_DISTANCE = 8

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
	-- The client audio transition also watches this workspace contract before
	-- the complete model has replicated. Stop/reset owns clearing the same flag.
	if suffix == "Active" and workspace:GetAttribute(name) ~= value then
		workspace:SetAttribute(name, value)
	end
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
		PathStatus = "IDLE", LastError = "", Phase = "DORMANT",
		Enraged = false, AttackSerial = 0, SpawnProbeCount = 0, ValidationOnly = false,
		SpawnNavigatorBuilds = 0,
		NavigationContextReady = false, NavigationContextError = "", NavigationContextMaxSlice = 0,
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
		or player:GetAttribute("Escaped") == true
		or player:GetAttribute("Level2_ExitTransition") == true then return nil end
	local character = player.Character
	local humanoid = character and character:FindFirstChildOfClass("Humanoid")
	local root = character and character:FindFirstChild("HumanoidRootPart")
	if not (character and character.Parent and humanoid and humanoid.Health > 0
		and root and root:IsA("BasePart")) then return nil end
	if PlayerProtection.IsActive(player, character) then return nil end
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
	if session.Driver then session.Driver:Motion(animation, speed) end
end

local function setPhase(session, count)
	-- Objective counter represents distinct valid started pumps, not station index.
	session.MaximumPumps = math.max(session.MaximumPumps, count)
	local desired = session.MaximumPumps >= ENRAGE_PUMPS and "ENRAGED"
		or session.MaximumPumps >= SPAWN_PUMPS and "ACTIVE" or "DORMANT"
	if desired == session.Phase then return end
	session.Phase = desired
	publish(session, "Phase", desired)
	publish(session, "Enraged", desired == "ENRAGED")
	-- Per-instance tuning preserves current route and Pool Foam.
	if session.Navigator then
		session.Navigator.Tuning.RepathInterval = desired == "ENRAGED" and .45 or .75
		session.Navigator.Tuning.RepathDistance = desired == "ENRAGED" and 4 or 6
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
		if typeof(container) == "Instance" then
			consider(container)
			for _, descendant in ipairs(container:GetDescendants()) do consider(descendant) end
		end
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
				Score = (not observed and 30 or 0) - math.abs(distance(anchor.Position, focus) - 140)})
		end
	end
	table.sort(result, function(a, b) return a.Score > b.Score end)
	return result
end

local function navigationTuning(model)
	local validationOnly = Configuration.StudioValidationMode == true and RunService:IsStudio()
	assert(validationOnly or model:GetAttribute("Level2_PoolSlideRigVerified") == true,
		"new rig/animations require full-cycle validation before enabling")
	assert(validationOnly or model:GetAttribute("Level2_PoolSlideCorridorFitVerified") == true,
		"three layouts and tightest animated corridor envelope not verified")
	local bounds, size = model:GetBoundingBox()
	local pivot = model:GetPivot()
	assert(pivot.UpVector:Dot(Vector3.yAxis) >= .999,
		"rig pivot must be upright before navigation; normalize imported bind orientation")
	local radius, height = model:GetAttribute("AgentRadius"), model:GetAttribute("AgentHeight")
	local animatedRadius = model:GetAttribute("AnimatedEnvelopeRadius")
	local animatedHeight = model:GetAttribute("AnimatedEnvelopeHeight")
	local groundOffset = model:GetAttribute("GroundOffset")
	assert(finite(groundOffset) and groundOffset >= 0 and groundOffset <= 24,
		"missing or invalid measured GroundOffset (pivot-to-sole distance)")
	local legacyOffset = model:GetAttribute("PoolFoamGroundOffset")
	assert(legacyOffset == nil or (finite(legacyOffset) and math.abs(legacyOffset - groundOffset) <= .001),
		"legacy PoolFoamGroundOffset would override the new rig's GroundOffset")
	assert(finite(animatedRadius) and finite(animatedHeight), "missing measured animated envelope")
	assert(finite(radius) and finite(height), "missing measured navigation envelope")
	-- Both the body box and PivotTo are centred on the PIVOT, not the bounding
	-- box centre. Include imported-root offsets and every yaw angle, otherwise
	-- the probe can be clear while an off-centre mesh clips a wall or floor.
	local staticRadius, lowestY, highestY = 0, math.huge, -math.huge
	for _, x in ipairs({-1, 1}) do
		for _, y in ipairs({-1, 1}) do
			for _, z in ipairs({-1, 1}) do
				local corner = bounds:PointToWorldSpace(Vector3.new(size.X * x, size.Y * y, size.Z * z) * .5)
				local fromPivot = corner - pivot.Position
				staticRadius = math.max(staticRadius, Vector2.new(fromPivot.X, fromPivot.Z).Magnitude)
				lowestY, highestY = math.min(lowestY, corner.Y), math.max(highestY, corner.Y)
			end
		end
	end
	local staticHeight = highestY - lowestY
	local measuredOffset = pivot.Position.Y - lowestY
	assert(math.abs(groundOffset - measuredOffset) <= .12,
		"GroundOffset disagrees with the prepared rig's measured pivot-to-sole distance")
	assert(animatedRadius + .001 >= staticRadius and animatedHeight + .001 >= staticHeight,
		"measured animated envelope excludes the prepared rest pose or pivot offset")
	assert(radius >= math.max(staticRadius, animatedRadius) + .1,
		"AgentRadius understates static/animated swept body")
	assert(height >= math.max(staticHeight, animatedHeight) + .3,
		"AgentHeight understates static/animated swept body")
	assert(radius <= 12 and height <= 24, "envelope exceeds navigator limits")
	return {AgentRadius = radius, PathAgentRadius = radius, AgentHeight = height,
		WaypointSpacing = 5, WaypointArrivalDistance = 1.4, RepathDistance = 6,
		-- Walk to the certified final approach; a 1.4-stud early stop can miss melee reach.
		GoalArrivalDistance = .2,
		RepathInterval = .75, StableRoutes = true, PathRequestTimeout = PATH_REQUEST_TIMEOUT,
		FootClearance = .08, FloorProbeAbove = 18,
		FloorProbeDepth = 80, MaxStepHeight = 3.5, MaxTravelStep = .6,
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
	-- A driver may have attached successfully but failed its first Motion/Pause
	-- before the spawn was committed. Always clean that pending driver too.
	if session.PendingDriver then
		local ok, failure = pcall(function() session.PendingDriver:Destroy() end)
		if not ok then warn("[Level 2 Pool Slide] pending driver cleanup: " .. tostring(failure)) end
	end
	if session.PendingNavigator then session.PendingNavigator:Destroy() end
	if session.PendingModel then session.PendingModel:Destroy() end
	session.PendingDriver, session.PendingNavigator, session.PendingModel = nil, nil, nil
end

local function rollbackFailedSpawn(session)
	-- Pending ownership is retained through every fallible commit step. An
	-- exception must not leave Spawned=true with an invisible ServerStorage rig.
	if session.PendingModel and session.Model == session.PendingModel then
		session.Driver, session.Model, session.Navigator = nil, nil, nil
		session.Spawned = false
		session.SpawnCount = session.SpawnCountBeforeCommit or 0
		session.AnimationState, session.PauseRecord = nil, nil
		publish(session, "Active", false)
		publish(session, "SpawnCount", session.SpawnCount)
	end
	session.SpawnCountBeforeCommit = nil
	discardPending(session)
end

local function resetPrivateSpawnProbe(session, navigator, model)
	-- This is NOT a teleport/recovery API. Only an uncommitted clone directly
	-- inside ServerStorage may bypass the sweep between candidate spawn rooms.
	assert(not session.Spawned and session.PendingModel == model
		and session.PendingNavigator == navigator and navigator.Model == model
		and model.Parent == ServerStorage and not navigator.Destroyed,
		"spawn-probe reset is restricted to the owned private pending model")
	navigator:Stop()
	navigator.HasGrounded = false
	navigator.LastSafeFoot, navigator.LastSafeFacing = nil, nil
end

local function spawnAllowed(session)
	-- Developer pause freezes the encounter's motion and damage, not its
	-- existence. Second-pump spawns must remain inspectable with developer ESP.
	return roundReady(session) and pumpCount() >= SPAWN_PUMPS and not session.Spawned
end

local function localDepartureClear(navigator, targetPosition)
	-- Do NOT repeat retired 72,000-query whole-route scans on spawn candidates.
	-- Prevalidated fit is an acceptance requirement. This bounded runtime check
	-- proves graph connectivity and the local departure, not whole-route fit.
	local points, status = navigator:_fallbackWaypoints(targetPosition)
	if status == "NO_PATH" or #points == 0 then return false end
	local from = navigator:GetPosition()
	for _, point in ipairs(points) do
		local delta = Vector3.new(point.X - from.X, 0, point.Z - from.Z)
		if delta.Magnitude > .1 then
			local endpoint = from + delta.Unit * math.min(SPAWN_APPROACH_DISTANCE, delta.Magnitude)
			local pass = navigator:_walkingEdgeClear(from, endpoint)
			return pass, #points
		end
	end
	return false
end

local function spawnModel(session)
	if not spawnAllowed(session) then return false, "spawn cancelled" end
	local records = livingRecords(session)
	if #records == 0 then return false, "no living round participants" end
	local ranked = candidates(session, records)
	if #ranked == 0 then return false, "no safe anchor at least " .. tostring(SPAWN_MINIMUM_DISTANCE) .. " studs from every player" end
	local model = session.Template:Clone()
	assert(model, "Pool Slide template must be Archivable")
	session.PendingModel = model
	model.Name = MODEL_NAME
	for _, descendant in ipairs(model:GetDescendants()) do
		if descendant:IsA("BasePart") then
			-- The imported rig adapter owns anchoring/joints. Anchoring every
			-- Motor6D-driven limb would freeze it despite a playing animation.
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
	assert(RigAdapter.PrepareModel(model, Configuration), "new rig physics/joints not prepared")
	local tuning = navigationTuning(model)
	local options = {
		RuntimeFolder = session.RuntimeFolder,
		PreparedContext = assert(session.NavigationContext, "navigation context not ready"),
		ObstacleExclusions = session.Manifest.BuoyantProps and {session.Manifest.BuoyantProps} or {},
	}
	local navigator = Navigator.new(model, session.Manifest, tuning, options)
	session.SpawnNavigatorBuilds += 1
	publish(session, "SpawnNavigatorBuilds", session.SpawnNavigatorBuilds)
	session.PendingNavigator = navigator
	local selected
	local cursor = session.SpawnCandidateCursor or 0
	for offset = 1, math.min(SPAWN_MAX_PROBES_PER_PASS, #ranked) do
		local index = (cursor + offset - 1) % #ranked + 1
		local candidate = ranked[index]
		task.wait(SPAWN_PROBE_INTERVAL) -- only one candidate per interval
		if not spawnAllowed(session) then return false, "spawn cancelled" end
		session.SpawnCandidateCursor = index -- next retry continues after this candidate
		-- Reuse ONE private Navigator per pass. Its generation-bound prepared
		-- query context is also shared across later passes; no full-world scans
		-- occur in this pump-triggered constructor or candidate loop.
		resetPrivateSpawnProbe(session, navigator, model)
		session.SpawnProbeCount += 1
		publish(session, "SpawnProbeCount", session.SpawnProbeCount)
		local position = candidate.Anchor.Position
		local target = livingRecord(session, candidate.Nearest.Player)
		if not target then continue end
		local targetPosition = target.Root.Position
		local routeValid = false
		if navigator:WarpTo(position, targetPosition - position, true) then
			if escapeClear(navigator) then
				local pointCount
				routeValid, pointCount = localDepartureClear(navigator, targetPosition)
				candidate.RoutePoints = pointCount
			end
		end
		if routeValid then
			local safe = true
			-- Re-read participants immediately before the no-yield commit. Check the
			-- actual grounded position and publish only these fresh measurements.
			local spawnPosition = navigator:GetPosition()
			local minimum, observed = math.huge, false
			local latest = livingRecords(session)
			if #latest == 0 then safe = false end
			for _, record in ipairs(latest) do
				local playerPosition = record.Root.Position
				local separation = distance(spawnPosition, playerPosition)
				minimum = math.min(minimum, separation)
				if separation < SPAWN_MINIMUM_DISTANCE then
					safe = false
					break
				end
				if clearLine(session, playerPosition + Vector3.new(0, 2, 0),
					spawnPosition + Vector3.new(0, 6, 0)) then observed = true end
			end
			if safe then
				candidate.Distance, candidate.Hidden = minimum, not observed
				selected = candidate
				break
			end
		end
	end
	if not selected then return false, "no safe floor/body/local departure with connected hall route" end
	if not spawnAllowed(session) then return false, "spawn cancelled" end
	-- Animator:LoadAnimation requires Workspace ancestry. Publish ONLY the final
	-- grounded candidate, then attach/start/commit without yielding. Rejected
	-- candidate probes stay private; rollback owns this pending model throughout.
	-- Attach/Motion/Pause must not yield and Attach must undo its own partial
	-- resources if it throws before returning a driver.
	pcall(function() model.ModelStreamingMode = Enum.ModelStreamingMode.Persistent end)
	model.Parent = session.RuntimeFolder
	local driver = RigAdapter.Attach(model, Configuration)
	assert(driver, "new rig animation driver did not attach")
	session.PendingDriver = driver
	if not spawnAllowed(session) then
		return false, "round changed while attaching animation driver"
	end
	-- Driver startup is transactional; the spawn latch stays clear until startup
	-- succeeds. The Spawning flag protects this no-yield commit from duplicates.
	if session.Suspended or workspace:GetAttribute("EntityPaused") == true then driver:Pause(true) end
	driver:Motion("Idle", 0)
	if not spawnAllowed(session) then return false, "round changed while initializing animation driver" end
	CollectionService:AddTag(model, "Level2HostileEntity")
	CollectionService:AddTag(model, "Level2PoolSlideEntity")
	session.SpawnCountBeforeCommit = session.SpawnCount
	session.Driver = driver
	session.Model, session.Navigator = model, navigator
	if session.Suspended then
		session.PauseRecord = navigator:Pause()
		driver:Pause(true)
	end
	session.Spawned = true -- once-per-round latch; still rollback-owned until commit completes
	session.SpawnCount += 1
	session.ProgressAt = os.clock()
	session.ProgressPosition = navigator:GetPosition()
	publish(session, "Active", true)
	publish(session, "Generation", session.Generation)
	publish(session, "ValidationOnly", session.ValidationOnly)
	publish(session, "SpawnCount", session.SpawnCount)
	publish(session, "SpawnDistance", selected.Distance)
	publish(session, "SpawnAnchor", selected.Anchor.Name)
	publish(session, "SpawnHidden", selected.Hidden)
	publish(session, "SpawnRouteQueries", 0) -- no whole-route spawn scan
	publish(session, "SpawnRoutePoints", selected.RoutePoints)
	publish(session, "LastError", "")
	publish(session, "Phase", session.Phase)
	publish(session, "Enraged", session.Phase == "ENRAGED")
	if session.Phase == "ENRAGED" then
		navigator.Tuning.RepathInterval, navigator.Tuning.RepathDistance = .45, 4
	end
	session.AnimationState = nil
	motion(session, workspace:GetAttribute("EntityPaused") == true and "PAUSED" or "IDLE",
		false, 0, "Idle")
	-- Only release pending ownership after the last fallible startup/metadata
	-- step. Earlier failures remove the candidate and restore latch/count.
	session.PendingDriver, session.PendingModel, session.PendingNavigator = nil, nil, nil
	session.SpawnCountBeforeCommit = nil
	return true
end

local function requestSpawn(session)
	if not session.NavigationContext then return end -- built once, before pump2, not per spawn
	if session.Spawning or os.clock() < session.NextSpawnAttempt then return end
	session.Spawning = true -- protects deferred work from later Heartbeats
	motion(session, "SPAWNING", false, 0, "Idle")
	task.defer(function()
		if not alive(session) then return end
		local callOk, spawned, failure = xpcall(function() return spawnModel(session) end, debug.traceback)
		if not callOk then failure, spawned = spawned, false end
		if not spawned then rollbackFailedSpawn(session) end
		session.Spawning = false
		if not alive(session) then return end
		if not spawned then
			session.FailedSpawnPasses += 1
			local delay = session.FailedSpawnPasses >= 3 and 30 or SPAWN_RETRY_SECONDS
			session.NextSpawnAttempt = os.clock() + delay
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

local function attackReach(session, record)
	local live = livingRecord(session, record.Player)
	if not live or live.Character ~= record.Character then return false end
	local foot, root = session.Navigator:GetPosition(), live.Root.Position
	local vertical = root.Y - foot.Y
	local relative = Vector3.new(root.X - foot.X, 0, root.Z - foot.Z)
	-- Windup fixes the facing; circling behind a visible swing avoids its hit.
	if session.Attack and relative.Magnitude > .01
		and session.Navigator:GetFacing():Dot(relative.Unit)
			< math.cos(math.rad(Configuration.AttackArcDegrees * .5)) then return false end
	return distance(foot, root) <= ATTACK_DISTANCE and vertical >= -1
		and vertical <= ATTACK_VERTICAL_DISTANCE
		and clearLine(session, foot + Vector3.new(0, 3, 0), root)
end

local function beginAttack(session, record, now)
	if session.Attack or now < session.AttackCooldown or not attackReach(session, record) then return false end
	session.AttackSerial += 1
	session.Attack = {Record = record, HitAt = now + Configuration.AttackWindup,
		EndsAt = now + Configuration.AttackWindup + Configuration.AttackRecovery, HitChecked = false}
	session.AttackCooldown = now + Configuration.AttackCooldown
	session.Navigator:Stop()
	session.Navigator:Face(record.Root.Position)
	session.CurrentSpeed = 0
	publish(session, "AttackSerial", session.AttackSerial)
	motion(session, "ATTACK", false, 0, "Attack")
	session.Driver:Attack(session.AttackSerial)
	return true
end

local function releaseProtectedPlayer(session, player, character)
	if activeSession ~= session or not PlayerProtection.IsActive(player, character) then return false end
	local attack = session.Attack
	local attacking = attack and attack.Record.Player == player and attack.Record.Character == character
	if session.Target ~= player and not attacking then return false end
	if attacking then session.Attack = nil end
	if session.Target == player then setTarget(session, nil) end
	if session.Navigator then session.Navigator:Stop() end
	session.PauseRecord = nil
	session.CurrentSpeed, session.NextTargetRefresh, session.NextGoalRefresh = 0, 0, 0
	-- Motion stops the old Attack track; retain its cooldown and monotonic serial.
	motion(session, "IDLE", false, 0, "Idle")
	return true
end

local function updateAttack(session, now)
	local attack = session.Attack
	if not attack then return false end
	if releaseProtectedPlayer(session, attack.Record.Player, attack.Record.Character) then return false end
	if now >= attack.HitAt and not attack.HitChecked then
		attack.HitChecked = true
		-- One server evaluation after visible windup. No delayed task survives reset.
		if attackReach(session, attack.Record)
			and not PlayerProtection.IsActive(attack.Record.Player, attack.Record.Character) then
			attack.Record.Humanoid:TakeDamage(Configuration.AttackDamage)
		end
	end
	if now >= attack.EndsAt then
		session.Attack = nil
		motion(session, "RECOVER", false, 0, "Idle")
		return false
	end
	return true
end

local function updateModel(session, deltaTime)
	local now, navigator = os.clock(), session.Navigator
	if updateAttack(session, now) then return end
	if now >= session.NextTargetRefresh then
		chooseTarget(session)
		session.NextTargetRefresh = now + TARGET_REFRESH_SECONDS
	end
	local record = session.Target and livingRecord(session, session.Target)
	if not record then
		setTarget(session, nil)
		if session.State ~= "IDLE" then navigator:Stop() end
		session.CurrentSpeed = 0
		motion(session, "IDLE", false, 0, "Idle")
		return
	end
	if beginAttack(session, record, now) then return end
	local before = navigator:GetPosition()
	local enraged = session.Phase == "ENRAGED"
	local running = enraged or distance(before, record.Root.Position) < Configuration.RunDistance
	local desiredSpeed = enraged and Configuration.EnragedSpeed
		or running and Configuration.NormalRunSpeed or Configuration.WalkSpeed
	local dt = math.clamp(deltaTime, 0, .1)
	session.CurrentSpeed += math.clamp(desiredSpeed - session.CurrentSpeed,
		-Configuration.Deceleration * dt, Configuration.Acceleration * dt)
	-- Bounded goal cadence; never force route replacement because pump 3 changed.
	if now >= session.NextGoalRefresh then
		navigator:SetGoal(record.Root.Position)
		session.NextGoalRefresh = now + GOAL_REFRESH_SECONDS
	end
	local reached = navigator:Step(dt, session.CurrentSpeed)
	local moved = distance(before, navigator:GetPosition())
	local nav = navigator:GetDebugSnapshot()
	motion(session, nav.WaitingForClearance and "WAITING" or (enraged and "ENRAGED" or "CHASE"),
		moved > .01, dt > 0 and moved / dt or 0, moved > .01 and (running and "Run" or "Walk") or "Idle")
	publish(session, "PathStatus", navigator:GetStatus())
	if beginAttack(session, record, now) then return end
	if now - session.ProgressAt >= WATCHDOG_SECONDS then
		local planning = nav.Computing and now - nav.RequestStartedAt < PATH_REQUEST_TIMEOUT
		local progressed = distance(session.ProgressPosition, navigator:GetPosition()) >= 1
		if not reached and not nav.Reached and not nav.WaitingForClearance
			and not planning and not progressed and now >= session.NextRecovery then
			session.NextRecovery = now + WATCHDOG_COOLDOWN
			navigator:SetGraphGoal(record.Root.Position, true)
		end
		session.ProgressAt, session.ProgressPosition = now, navigator:GetPosition()
	end
end

local function suspend(session)
	if session.Suspended then return end
	session.Suspended = true
	session.Attack = nil
	session.AttackCooldown = os.clock() + Configuration.AttackCooldown
	session.CurrentSpeed = 0
	if session.Navigator then session.PauseRecord = session.Navigator:Pause() end
	if session.Driver then session.Driver:Pause(true) end
	setTarget(session, nil)
end

local function resume(session)
	if not session.Suspended then return end
	session.Suspended = false
	if session.Navigator and session.PauseRecord then
		local restored = session.Navigator:Resume(session.PauseRecord)
		if not restored then session.Navigator:Stop() end
	end
	session.PauseRecord = nil
	if session.Driver then session.Driver:Pause(false) end
	session.NextTargetRefresh, session.NextGoalRefresh = 0, 0
	session.ProgressAt = os.clock()
	if session.Navigator then session.ProgressPosition = session.Navigator:GetPosition() end
end

local function heartbeat(session, deltaTime)
	if activeSession ~= session then return end
	if not alive(session) then Controller.Stop() return end
	if not roundReady(session) then
		suspend(session)
		motion(session, "DORMANT", false, 0, "Idle")
		return
	end
	-- This is the count of distinct started levers, NOT the station's Index.
	-- Heartbeat reads after the objective publishes the full activator payload.
	setPhase(session, pumpCount())
	if not session.Spawned and session.MaximumPumps >= SPAWN_PUMPS then
		publish(session, "SpawnRequested", true)
		requestSpawn(session)
	end
	if not session.Spawned then return end
	if not (session.Model and session.Model:IsDescendantOf(session.RuntimeFolder) and session.Navigator) then
		setTarget(session, nil)
		publish(session, "Active", false)
		if session.Driver then session.Driver:Destroy(); session.Driver = nil end
		if session.Navigator then session.Navigator:Destroy(); session.Navigator = nil end
		motion(session, "REMOVED", false, 0, "Idle")
		return -- the once-per-round latch deliberately remains set
	end
	-- Spawn eligibility is evaluated above even while paused. A materialized
	-- entity is visible to ESP, but cannot acquire a target, move, or attack.
	if workspace:GetAttribute("EntityPaused") == true then
		suspend(session)
		motion(session, "PAUSED", false, 0, "Idle")
		return
	end
	resume(session)
	updateModel(session, deltaTime)
end

function Controller.Stop()
	local session = activeSession
	activeSession = nil -- invalidates deferred work and in-flight navigation first
	if session then
		for _, connection in ipairs(session.Connections) do connection:Disconnect() end
		setTarget(session, nil)
		discardPending(session)
		if session.Driver then session.Driver:Destroy() end
		if session.Navigator then session.Navigator:Destroy() end
		if session.RuntimeFolder then session.RuntimeFolder:Destroy() end
	end
	resetPublished()
end

function Controller.Start(manifest, generation)
	Controller.Stop()
	if Configuration.Enabled ~= true then return nil, "new Pool Slide draft is disabled until verified" end
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
	local tuningOk, tuningError = pcall(navigationTuning, template)
	if not tuningOk then return nil, tostring(tuningError) end
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
		AttackCooldown = 0, AttackSerial = 0, State = "DORMANT",
		MaximumPumps = 0, Phase = "DORMANT", NextGoalRefresh = 0, NextRecovery = 0,
		SpawnProbeCount = 0, SpawnNavigatorBuilds = 0, FailedSpawnPasses = 0,
		ValidationOnly = Configuration.StudioValidationMode == true and RunService:IsStudio(),
	}
	activeSession = session
	-- One immutable generated-world context. Its builder yields in small slices
	-- and stops if this session/world is replaced; later spawn retries reuse it.
	task.defer(function()
		if not alive(session) then return end
		local ok, context, failure = pcall(Navigator.PrepareContext, manifest,
			function() return not alive(session) end)
		if not alive(session) then return end
		if not ok then failure, context = context, nil end
		session.NavigationContext = context
		publish(session, "NavigationContextReady", context ~= nil)
		publish(session, "NavigationContextError", context and "" or tostring(failure))
		publish(session, "NavigationContextMaxSlice", context and context.MaxSlice or 0)
		if not context then warn("[Level 2 Pool Slide] navigation preparation failed: " .. tostring(failure)) end
	end)
	publish(session, "Generation", generation)
	publish(session, "ValidationOnly", session.ValidationOnly)
	if session.ValidationOnly then warn("[Level 2 Pool Slide] STUDIO VALIDATION ONLY: rig/fit acceptance flags are bypassed; do not publish") end
	motion(session, "DORMANT", false, 0, "Idle")
	table.insert(session.Connections, RunService.Heartbeat:Connect(function(dt) heartbeat(session, dt) end))
	table.insert(session.Connections, PlayerProtection.Activated:Connect(function(player, character)
		releaseProtectedPlayer(session, player, character)
	end))
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
		State = session.State, Phase = session.Phase, MaximumPumps = session.MaximumPumps,
		SpawnProbes = session.SpawnProbeCount, FailedSpawnPasses = session.FailedSpawnPasses,
		SpawnNavigatorBuilds = session.SpawnNavigatorBuilds,
		AttackSerial = session.AttackSerial, TargetUserId = session.Target and session.Target.UserId or 0,
		Navigation = session.Navigator and session.Navigator:GetDebugSnapshot() or nil}
end

return Controller
