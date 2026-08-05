--!strict
-- Independent Level 2 hostile-entity brains. Movement, pursuit and combat are
-- centralized here so every tagged model owns its own navigation tickets/state.
local Players = game:GetService("Players")
local RunService = game:GetService("RunService")
local ServerScriptService = game:GetService("ServerScriptService")

local Profiles = require(ServerScriptService:WaitForChild("Level2EntityProfiles"))
local Navigation = require(ServerScriptService:WaitForChild("Level2Navigation"))

local Controller = {}
local states = setmetatable({}, {__mode = "k"})
local combatEnabled = true

local function setAttribute(entity, key, value)
	if entity:GetAttribute(key) ~= value then
		entity:SetAttribute(key, value)
	end
end

local function setMotion(state, motion, speed)
	setAttribute(state.Entity, "MotionState", motion)
	setAttribute(state.Entity, "MoveSpeed", speed)
end

local function livingCharacter(player)
	if player:GetAttribute("Escaped") == true then
		return nil
	end
	local character = player.Character
	local humanoid = character and character:FindFirstChildOfClass("Humanoid")
	local root = character and character:FindFirstChild("HumanoidRootPart")
	if not (humanoid and humanoid.Health > 0 and root and root:IsA("BasePart")) then
		return nil
	end

	-- The rebuilt Level 2 entry can finish spawning a character before the
	-- legacy round flag replicates.  Treat a living character physically inside
	-- the generated Poolrooms as active so the entity never ignores the player.
	local inRound = player:GetAttribute("InRound") == true
	local levelTwoWorld = workspace:FindFirstChild("PoolroomsLevel2")
	local inLevelTwoBounds = workspace:GetAttribute("SelectedLevel") == 2
		and levelTwoWorld ~= nil
		and math.abs(root.Position.X) <= 430
		and math.abs(root.Position.Z) <= 430
		and root.Position.Y > -35
		and root.Position.Y < 160
	if not inRound and not inLevelTwoBounds then
		return nil
	end
	return root, humanoid
end

local function blackoutState()
	local world = workspace:FindFirstChild("PoolroomsLevel2")
	if not world then
		return false, 0
	end
	return world:GetAttribute("ValveBlackoutActive") == true,
		tonumber(world:GetAttribute("ValveBlackoutGeneration")) or 0
end

local function eyePosition(state)
	return state.Root.Position + Vector3.new(0, math.min(state.Profile.AgentHeight * 0.32, 4.5), 0)
end

local function visibleTo(state, targetRoot, range)
	return Navigation.HasLineOfSight(state.Entity, eyePosition(state), targetRoot, range)
end

local function clearTarget(state, retainMemory)
	state.TargetRoot = nil
	state.TargetHumanoid = nil
	state.TargetPlayer = nil
	state.TargetVisible = false
	setAttribute(state.Entity, "TargetUserId", 0)
	if not retainMemory then
		state.LastSeenPosition = nil
		state.LastSeenAt = 0
	end
end

local function scanTargets(state, now)
	local profile = state.Profile
	local blackout, generation = blackoutState()
	state.BlackoutActive = blackout
	if generation ~= state.BlackoutGeneration then
		state.BlackoutGeneration = generation
		state.RepathRequested = true
	end

	if profile.BlackoutOnlyAggro and not blackout then
		clearTarget(state, false)
		setAttribute(state.Entity, "BlackoutPhase", "Dormant")
		return
	end

	local bestPlayer, bestRoot, bestHumanoid, bestDistance, bestVisible
	for _, player in ipairs(Players:GetPlayers()) do
		local targetRoot, humanoid = livingCharacter(player)
		if targetRoot then
			local distance = (targetRoot.Position - state.Root.Position).Magnitude
			local canSee = distance <= profile.SightRange and visibleTo(state, targetRoot, profile.SightRange)
			local canHear = distance <= profile.HearingRange
			local supernaturalBlackoutSense = blackout and profile.BlackoutBurstSpeed > 0
			if canSee or canHear or supernaturalBlackoutSense then
				local score = distance - (canSee and 35 or 0)
				- (supernaturalBlackoutSense and 10 or 0)
				if not bestDistance or score < bestDistance then
					bestPlayer, bestRoot, bestHumanoid = player, targetRoot, humanoid
					bestDistance, bestVisible = score, canSee
				end
			end
		end
	end

	if bestRoot then
		local changed = state.TargetRoot ~= bestRoot
		state.TargetPlayer = bestPlayer
		state.TargetRoot = bestRoot
		state.TargetHumanoid = bestHumanoid
		state.TargetVisible = bestVisible
		if bestVisible or (blackout and profile.BlackoutBurstSpeed > 0) then
			state.LastSeenPosition = bestRoot.Position
			state.LastSeenAt = now
		end
		setAttribute(state.Entity, "TargetUserId", bestPlayer.UserId)
		if changed then
			state.RepathRequested = true
		end
		return
	end

	local targetRoot = state.TargetRoot
	if targetRoot and targetRoot.Parent then
		local distance = (targetRoot.Position - state.Root.Position).Magnitude
		local canSee = distance <= profile.SightRange and visibleTo(state, targetRoot, profile.SightRange)
		if canSee then
			state.TargetVisible = true
			state.LastSeenPosition = targetRoot.Position
			state.LastSeenAt = now
			return
		end
		state.TargetVisible = false
		if distance <= profile.GiveUpRange and now - state.LastSeenAt <= profile.LastSeenSeconds then
			return
		end
	end
	clearTarget(state, true)
end

local function destinationFor(state, now)
	local profile = state.Profile
	if state.TargetRoot and state.TargetRoot.Parent then
		local distance = (state.TargetRoot.Position - state.Root.Position).Magnitude
		if state.BlackoutActive and profile.BlackoutBurstSpeed > 0 then
			return state.TargetRoot.Position, true
		end
		if distance <= profile.GiveUpRange then
			if state.TargetVisible then
				return state.TargetRoot.Position, true
			end
			if state.LastSeenPosition and now - state.LastSeenAt <= profile.LastSeenSeconds then
				return state.LastSeenPosition, true
			end
		end
	end
	if state.LastSeenPosition and now - state.LastSeenAt <= profile.LastSeenSeconds then
		return state.LastSeenPosition, true
	end

	if now < state.WanderPauseUntil then
		return nil, false
	end
	if not state.WanderGoal then
		state.WanderGoal = Navigation.ChooseWanderDestination(state.Entity, state, profile)
	end
	return state.WanderGoal, false
end

local function attackLineValid(state, targetRoot)
	local profile = state.Profile
	local delta = targetRoot.Position - state.Root.Position
	if delta.Magnitude > profile.AttackHitRange then
		return false
	end
	if not visibleTo(state, targetRoot, profile.AttackHitRange + 3) then
		return false
	end
	local flat = Vector3.new(delta.X, 0, delta.Z)
	if flat.Magnitude <= 0.05 then
		return true
	end
	local forward = Vector3.new(state.Root.CFrame.LookVector.X, 0, state.Root.CFrame.LookVector.Z)
	if forward.Magnitude <= 0.05 then
		return false
	end
	local minimumDot = math.cos(math.rad(profile.AttackConeDegrees * 0.5))
	return forward.Unit:Dot(flat.Unit) >= minimumDot
end

local function startAttack(state, now)
	if not combatEnabled or state.Attacking or now < state.NextAttackAt then
		return false
	end
	local targetRoot = state.TargetRoot
	local humanoid = state.TargetHumanoid
	if not targetRoot or not targetRoot.Parent or not humanoid or humanoid.Health <= 0 then
		return false
	end
	local delta = targetRoot.Position - state.Root.Position
	if delta.Magnitude > state.Profile.AttackRange then
		return false
	end
	if not visibleTo(state, targetRoot, state.Profile.AttackRange + 3) then
		return false
	end

	local flat = Vector3.new(delta.X, 0, delta.Z)
	if flat.Magnitude > 0.05 then
		local position = state.Root.Position
		state.Entity:PivotTo(CFrame.lookAt(position, position + flat.Unit))
	end
	if not attackLineValid(state, targetRoot) then
		return false
	end

	state.Attacking = true
	state.AttackToken += 1
	local token = state.AttackToken
	local attackTargetRoot = targetRoot
	local attackTargetHumanoid = humanoid
	setAttribute(state.Entity, "AttackTargetUserId", state.TargetPlayer and state.TargetPlayer.UserId or 0)
	state.NextAttackAt = now + state.Profile.AttackCooldown
	Navigation.CancelPath(state)
	setMotion(state, "Attack", 0)
	setAttribute(state.Entity, "AttackStage", "Windup")
	setAttribute(state.Entity, "ActionName", "Attack")
	setAttribute(state.Entity, "ActionSerial", (state.Entity:GetAttribute("ActionSerial") or 0) + 1)

	task.delay(state.Profile.AttackWindup, function()
		if not state.Active or state.AttackToken ~= token or not state.Entity.Parent then
			return
		end
		local hit = attackTargetRoot and attackTargetRoot.Parent
			and attackTargetHumanoid and attackTargetHumanoid.Health > 0
			and attackLineValid(state, attackTargetRoot)
		if hit then
			setAttribute(state.Entity, "AttackStage", "Impact")
			setAttribute(state.Entity, "ImpactSerial", (state.Entity:GetAttribute("ImpactSerial") or 0) + 1)
			local damage = state.Profile.AttackDamage
			if damage == math.huge or damage >= attackTargetHumanoid.MaxHealth then
				attackTargetHumanoid.Health = 0
			else
				attackTargetHumanoid:TakeDamage(damage)
			end
		else
			setAttribute(state.Entity, "AttackStage", "Miss")
		end

		task.delay(0.12, function()
			if state.Active and state.AttackToken == token then
				setAttribute(state.Entity, "AttackStage", "Recovery")
				setMotion(state, "Recover", 0)
			end
		end)
		task.delay(state.Profile.AttackRecovery, function()
			if state.Active and state.AttackToken == token then
				state.Attacking = false
				setAttribute(state.Entity, "AttackStage", "Ready")
				setAttribute(state.Entity, "ActionName", "")
				setAttribute(state.Entity, "AttackTargetUserId", 0)
				state.RepathRequested = true
			end
		end)
	end)
	return true
end

local function requestPath(state, destination, chasing, now)
	if state.Computing then
		return
	end
	state.RepathRequested = false
	local refresh = chasing and state.Profile.PathRefreshChase or state.Profile.PathRefreshWander
	state.NextPathAt = now + refresh
	Navigation.ComputePathAsync(
		state,
		state.Entity,
		state.Root.Position,
		destination,
		state.Profile,
		function(ticket, waypoints)
			if not state.Active or state.ComputeTicket ~= ticket then
				return
			end
			if not waypoints or #waypoints == 0 then
				state.PathFailures += 1
				state.NextPathAt = os.clock() + math.min(1.2, 0.18 * state.PathFailures)
				if not chasing then
					state.WanderGoal = nil
				end
				return
			end
			state.PathFailures = 0
			state.Waypoints = waypoints
			state.WaypointIndex = (#waypoints > 1) and 2 or 1
		end
	)
end

local function noteProgress(state, moving, now)
	local distance = (state.Root.Position - state.LastProgressPosition).Magnitude
	if distance >= state.Profile.StuckDistance then
		state.LastProgressPosition = state.Root.Position
		state.LastProgressAt = now
		state.StuckCount = 0
		if now >= state.NextSafeAnchorAt then
			state.LastSafeCFrame = state.Entity:GetPivot()
			state.NextSafeAnchorAt = now + 3
		end
		return
	end
	if not moving then
		state.LastProgressAt = now
		return
	end
	if now - state.LastProgressAt < state.Profile.StuckSeconds then
		return
	end

	state.StuckCount += 1
	state.LastProgressAt = now
	state.RepathRequested = true
	Navigation.CancelPath(state)
	if Navigation.RecoveryStep(state.Entity, state, state.Profile) then
		state.LastProgressPosition = state.Root.Position
	elseif state.StuckCount >= 4 and state.LastSafeCFrame then
		local anchorDistance = (state.LastSafeCFrame.Position - state.Root.Position).Magnitude
		if anchorDistance <= 24 then
			state.Entity:PivotTo(state.LastSafeCFrame)
		end
		state.StuckCount = 0
	end
end

local function stepState(state, dt, now)
	if not state.Active or not state.Entity.Parent or not state.Root.Parent then
		Controller.Stop(state.Entity)
		return
	end
	if workspace:GetAttribute("SelectedLevel") ~= 2 then
		setMotion(state, "Idle", 0)
		state.LastProgressAt = now
		return
	end
	if workspace:GetAttribute("EntityPaused") == true then
		if not state.DevPaused then
			state.DevPaused = true
			state.AttackToken += 1
			state.Attacking = false
			Navigation.CancelPath(state)
			state.Root.AssemblyLinearVelocity = Vector3.zero
			state.Root.AssemblyAngularVelocity = Vector3.zero
			setAttribute(state.Entity, "AttackStage", "Ready")
			setAttribute(state.Entity, "ActionName", "")
			setAttribute(state.Entity, "AttackTargetUserId", 0)
			setMotion(state, "Idle", 0)
		end
		state.LastProgressAt = now
		return
	elseif state.DevPaused then
		state.DevPaused = false
		state.RepathRequested = true
		state.NextScanAt = 0
	end

	if now >= state.NextScanAt then
		state.NextScanAt = now + 0.17
		scanTargets(state, now)
	end
	if state.Attacking then
		noteProgress(state, false, now)
		return
	end
	if startAttack(state, now) then
		return
	end

	local destination, chasing = destinationFor(state, now)
	if not destination then
		setMotion(state, "Idle", 0)
		noteProgress(state, false, now)
		return
	end

	if state.RepathRequested or now >= state.NextPathAt
		or state.WaypointIndex > #state.Waypoints then
		requestPath(state, destination, chasing, now)
	end

	local waypoint = state.Waypoints[state.WaypointIndex]
	if not waypoint and chasing and state.TargetVisible then
		-- Pathfinding can briefly return no path on shallow tiled water.  A visible
		-- target is safe to pursue directly while the next full path is computed.
		waypoint = {Position = destination}
		setAttribute(state.Entity, "NavigationMode", "DirectVisiblePursuit")
	elseif waypoint then
		setAttribute(state.Entity, "NavigationMode", chasing and "PathPursuit" or "PathWander")
	end
	if not waypoint then
		setMotion(state, "Idle", 0)
		noteProgress(state, state.Computing, now)
		return
	end

	local current = state.Root.Position
	local flatDelta = Vector3.new(waypoint.Position.X - current.X, 0, waypoint.Position.Z - current.Z)
	if flatDelta.Magnitude < state.Profile.WaypointReach then
		state.WaypointIndex += 1
		if state.WaypointIndex > #state.Waypoints and not chasing then
			state.WanderGoal = nil
			state.WanderPauseUntil = now + state.Profile.WanderPauseMin
				+ math.random() * (state.Profile.WanderPauseMax - state.Profile.WanderPauseMin)
		end
		return
	end

	local burst = false
	if chasing and state.BlackoutActive and state.Profile.BlackoutBurstSpeed > 0 and state.TargetRoot then
		local targetDistance = (state.TargetRoot.Position - current).Magnitude
		burst = targetDistance > state.Profile.BurstStopDistance and not state.TargetVisible
	end
	local speed = burst and state.Profile.BlackoutBurstSpeed
		or (chasing and state.Profile.ChaseSpeed or state.Profile.WanderSpeed)
	local motion = burst and "Burst" or (chasing and "Chase" or "Walk")
	setAttribute(state.Entity, "BlackoutPhase", burst and "Burst"
		or (chasing and "Hunt" or "Wander"))

	local stepDistance = math.min(speed * dt, flatDelta.Magnitude)
	local proposed = current + flatDelta.Unit * stepDistance
	local clear, resolved = Navigation.CanAdvance(
		state.Entity,
		current,
		proposed,
		state.Profile,
		state.GroundOffset
	)
	if not clear or not resolved then
		state.RepathRequested = true
		state.NextPathAt = 0
		setMotion(state, "Idle", 0)
		noteProgress(state, true, now)
		return
	end

	state.Entity:PivotTo(CFrame.lookAt(resolved, resolved + flatDelta.Unit))
	setMotion(state, motion, speed)
	noteProgress(state, true, now)
end

function Controller.Start(entity)
	if not entity:IsA("Model") or states[entity] then
		return states[entity]
	end
	local root = Navigation.GetRoot(entity)
	if not root then
		warn("[Level2EntityController] No root part for", entity:GetFullName())
		return nil
	end
	local profile = Profiles.Resolve(entity)
	local groundOffset = Navigation.GroundOffset(entity, root)
	local state = {
		Entity = entity,
		Root = root,
		Profile = profile,
		GroundOffset = groundOffset,
		SpawnPosition = root.Position,
		Active = true,
		ComputeTicket = 0,
		Computing = false,
		Path = nil,
		PathBlockedConnection = nil,
		Waypoints = {},
		WaypointIndex = 1,
		PathFailures = 0,
		RepathRequested = true,
		NextPathAt = 0,
		NextScanAt = 0,
		TargetRoot = nil,
		TargetHumanoid = nil,
		TargetPlayer = nil,
		TargetVisible = false,
		LastSeenPosition = nil,
		LastSeenAt = 0,
		WanderGoal = nil,
		WanderPauseUntil = os.clock() + math.random() * 1.2,
		BlackoutActive = false,
		BlackoutGeneration = -1,
		Attacking = false,
		AttackToken = 0,
		NextAttackAt = 0,
		LastProgressPosition = root.Position,
		LastProgressAt = os.clock(),
		StuckCount = 0,
		LastSafeCFrame = entity:GetPivot(),
		NextSafeAnchorAt = os.clock() + 3,
		DevPaused = false,
	}
	states[entity] = state

	setAttribute(entity, "EntityProfile", profile.Name)
	setAttribute(entity, "MotionState", "Idle")
	setAttribute(entity, "MoveSpeed", 0)
	setAttribute(entity, "ActionSerial", entity:GetAttribute("ActionSerial") or 0)
	setAttribute(entity, "ImpactSerial", entity:GetAttribute("ImpactSerial") or 0)
	setAttribute(entity, "AttackStage", "Ready")
	setAttribute(entity, "TargetUserId", 0)
	setAttribute(entity, "AttackTargetUserId", 0)
	setAttribute(entity, "ControllerManaged", true)
	setAttribute(entity, "NavigationMode", "Starting")
	return state
end

function Controller.Stop(entity)
	local state = states[entity]
	if not state then return end
	state.Active = false
	state.AttackToken += 1
	Navigation.CancelPath(state)
	setAttribute(entity, "MotionState", "Idle")
	setAttribute(entity, "MoveSpeed", 0)
	setAttribute(entity, "AttackStage", "Ready")
	setAttribute(entity, "AttackTargetUserId", 0)
	states[entity] = nil
end

function Controller.SetCombatEnabled(enabled)
	combatEnabled = enabled == true
end

function Controller.IsManaged(entity)
	return states[entity] ~= nil
end

function Controller.Count()
	local count = 0
	for _ in pairs(states) do count += 1 end
	return count
end

RunService.Heartbeat:Connect(function(dt)
	local now = os.clock()
	for _, state in pairs(states) do
		local ok, message = xpcall(stepState, debug.traceback, state, math.min(dt, 0.1), now)
		if not ok then
			warn("[Level2EntityController]", state.Entity:GetFullName(), message)
			setMotion(state, "Idle", 0)
			state.RepathRequested = true
		end
	end
end)

return Controller
