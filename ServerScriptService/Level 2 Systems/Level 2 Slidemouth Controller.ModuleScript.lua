local Players = game:GetService("Players")
local ReplicatedStorage = game:GetService("ReplicatedStorage")
local ServerStorage = game:GetService("ServerStorage")
local RunService = game:GetService("RunService")
local CollectionService = game:GetService("CollectionService")

local Navigator = require(script.Parent:WaitForChild("Level 2 Pool Foam Navigator"))

local Controller = {}
local activeSession

local TEMPLATE_NAME = "Level 2 Slidemouth Template"
local RUNTIME_NAME = "Level 2 Slidemouth Runtime"
local MODEL_NAME = "Level 2 Slidemouth"
local SPAWN_PUMPS = 2
local FAST_PUMPS = 3
local PUMP_TWO_SPEED = 24 -- exactly 150% of the normal 16-stud WalkSpeed
local PUMP_THREE_SPEED = 36
local ACCELERATION = 32
local DECELERATION = 40
local TARGET_REFRESH = .2
local ATTACK_DISTANCE = 5.25
local ATTACK_COOLDOWN = 1.1
local PUMP_ONE_GROAN_DELAY = 1.25
local SPAWN_GROAN_DELAY = .35
local PROGRESS_WINDOW = .75
local BUOYANT_SHOVE_COOLDOWN = .16
local BUOYANT_SHOVE_MIN_SPEED = 28
local BUOYANT_SHOVE_MAX_SPEED = 46

local MOVEMENT = {
	-- Match the real 15.9-stud body. A 10.5 radius made Roblox treat it
	-- as a 21-stud cylinder, too wide for the upper curve of vaulted portals.
	AgentRadius = 8.25,
	PathAgentRadius = 8,
	AgentHeight = 11,
	WaypointSpacing = 5,
	WaypointArrivalDistance = 2.25,
	RepathDistance = 7,
	RepathInterval = .45,
	FootClearance = .08,
	FloorProbeAbove = 16,
	FloorProbeDepth = 80,
	MaxStepHeight = 3.5,
	MaxTravelStep = .9,
	TurnResponsiveness = 9,
	-- Never steer backward around an obstacle; >90-degree probes caused
	-- the creature to moonwalk and rapidly reverse around columns.
	SteerAngles = {20, 35, 50},
}

local function finiteNumber(value)
	return typeof(value) == "number" and value == value and value > -math.huge and value < math.huge
end

local function stateFolder()
	local state = ReplicatedStorage:FindFirstChild("Level 2 State")
	return state and state:IsA("Folder") and state or nil
end

local function publish(name, value)
	local state = stateFolder()
	if state and state:GetAttribute(name) ~= value then
		state:SetAttribute(name, value)
	end
end

local function publishStopped(reason)
	publish("Level2_SlidemouthActive", false)
	publish("Level2_SlidemouthState", reason or "IDLE")
	publish("Level2_SlidemouthGeneration", 0)
	publish("Level2_SlidemouthTargetUserId", 0)
	publish("Level2_SlidemouthSpeed", 0)
	publish("Level2_SlidemouthPathStatus", "IDLE")
	publish("Level2_SlidemouthScreamSerial", 0)
	publish("Level2_SlidemouthScreamKind", "")
	publish("Level2_SlidemouthScreamPosition", Vector3.zero)
	publish("Level2_SlidemouthWarningSerial", 0)
	publish("Level2_SlidemouthWarningPosition", Vector3.zero)
	publish("Level2_SlidemouthWarningPump", 0)
	publish("Level2_SlidemouthScreamBusyUntil", 0)
	publish("Level2_SlidemouthSpawnDistance", 0)
	publish("Level2_SlidemouthSpawnHidden", false)
	publish("Level2_SlidemouthSpawnAnchor", "")
end

local function sessionAlive(session)
	if activeSession ~= session then return false end
	local world = session.Manifest and session.Manifest.World
	if not (world and world.Parent) then return false end
	local worldGeneration = world:GetAttribute("Level2_Generation")
	return worldGeneration == nil or worldGeneration == session.Generation
end

local function roundReady(session)
	return sessionAlive(session)
		and workspace:GetAttribute("SelectedLevel") == 2
		and workspace:GetAttribute("RoundActive") == true
		and workspace:GetAttribute("WorldGenerated") == true
end

local function livingRecord(session, player)
	if not roundReady(session)
		or player.Parent ~= Players
		or player:GetAttribute("InRound") ~= true
		or player:GetAttribute("Escaped") == true
	then
		return nil
	end
	local character = player.Character
	local humanoid = character and character:FindFirstChildOfClass("Humanoid")
	local root = character and character:FindFirstChild("HumanoidRootPart")
	if not (character and humanoid and humanoid.Health > 0 and root and root:IsA("BasePart")) then
		return nil
	end
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

local function horizontalDistance(a, b)
	return (Vector3.new(a.X, 0, a.Z) - Vector3.new(b.X, 0, b.Z)).Magnitude
end

local function makeRayParams(session)
	local exclusions = {session.RuntimeFolder}
	if session.Manifest.EntityNodes then table.insert(exclusions, session.Manifest.EntityNodes) end
	for _, object in ipairs(session.BuoyantProps or {}) do
		if object.Parent then table.insert(exclusions, object) end
	end
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

local function clearLine(session, fromPosition, toPosition)
	local displacement = toPosition - fromPosition
	if displacement.Magnitude <= .05 then return true end
	return workspace:Raycast(fromPosition, displacement, makeRayParams(session)) == nil
end

local function positionObserved(session, position, records)
	local target = position + Vector3.new(0, 4.5, 0)
	for _, record in ipairs(records) do
		local origin = record.Root.Position + Vector3.new(0, 2.2, 0)
		if clearLine(session, origin, target) then return true end
	end
	return false
end

local function positionBehindPlayers(position, records)
	for _, record in ipairs(records) do
		local offset = Vector3.new(position.X - record.Root.Position.X, 0,
			position.Z - record.Root.Position.Z)
		local look = record.Root.CFrame.LookVector
		local forward = Vector3.new(look.X, 0, look.Z)
		if offset.Magnitude > .05 and forward.Magnitude > .05
			and offset.Unit:Dot(forward.Unit) > .15 then
			return false
		end
	end
	return #records > 0
end

local function collectAnchors(manifest)
	local anchors = {}
	local seen = {}
	local function consider(instance)
		if not (instance and instance:IsA("BasePart")) or seen[instance] then return end
		local name = instance.Name
		local useful = name:find("Level 2 Entity Den ", 1, true) == 1
			or name:find("Level 2 Entity Patrol Node ", 1, true) == 1
			or name:find("Level 2 Navigation Node ", 1, true) == 1
		if not useful then return end
		seen[instance] = true
		table.insert(anchors, {
			Part = instance,
			Name = name,
			Position = instance.Position,
			IsDen = name:find("Level 2 Entity Den ", 1, true) == 1,
			IsCenter = name:find("Level 2 Navigation Node ", 1, true) == 1
				or name:find("Level 2 Entity Den ", 1, true) == 1,
		})
	end
	local function scan(container)
		if not container then return end
		consider(container)
		for _, descendant in ipairs(container:GetDescendants()) do consider(descendant) end
	end
	scan(manifest.EntityNodes)
	scan(manifest.EntityDen)
	return anchors
end

local function pumpActivatorPosition(pumpNumber)
	local state = stateFolder()
	if not state then return nil end
	local userId = tonumber(state:GetAttribute("Level2_PumpActivatorUserId" .. tostring(pumpNumber)))
	if userId and userId > 0 then
		local player = Players:GetPlayerByUserId(userId)
		local character = player and player.Character
		local root = character and character:FindFirstChild("HumanoidRootPart")
		if root and root:IsA("BasePart") then return root.Position end
	end
	local captured = state:GetAttribute("Level2_PumpActivatorPosition" .. tostring(pumpNumber))
	return typeof(captured) == "Vector3" and captured or nil
end

local function rankedSpawnCandidates(session, records, recovery, focusPosition)
	local candidates = {}
	for _, anchor in ipairs(session.Anchors) do
		if anchor.Part.Parent then
			local minimum = math.huge
			if not recovery and typeof(focusPosition) == "Vector3" then
				minimum = horizontalDistance(anchor.Position, focusPosition)
			else
				for _, record in ipairs(records) do
					minimum = math.min(minimum, horizontalDistance(anchor.Position, record.Root.Position))
				end
			end
			if minimum == math.huge then minimum = 185 end
			local hidden = not positionObserved(session, anchor.Position, records)
			local category
			if recovery then
				category = hidden and minimum >= 40 and minimum <= 180 and 4
					or hidden and minimum >= 25 and 3
					or minimum >= 40 and minimum <= 180 and 2
					or 1
			elseif typeof(focusPosition) == "Vector3" then
				-- Roughly two authored rooms from the player who pulled Pump 2.
				category = hidden and minimum >= 95 and minimum <= 220 and 5
					or hidden and minimum >= 70 and minimum <= 280 and 4
					or minimum >= 95 and minimum <= 220 and 3
					or hidden and 2
					or 1
			else
				category = hidden and minimum >= 140 and minimum <= 260 and 5
					or hidden and minimum >= 120 and minimum <= 320 and 4
					or minimum >= 140 and minimum <= 260 and 3
					or hidden and 2
					or 1
			end
			local ideal = recovery and 90 or (typeof(focusPosition) == "Vector3" and 150 or 185)
			local score = category * 10000 - math.abs(minimum - ideal)
			if anchor.IsCenter and not recovery then score += 500 end
			if anchor.IsDen and not recovery then score += 25 end
			table.insert(candidates, {
				Anchor = anchor,
				Distance = minimum,
				Hidden = hidden,
				Score = score,
			})
		end
	end
	table.sort(candidates, function(a, b) return a.Score > b.Score end)
	return candidates
end

local function facingTowardNearest(position, records)
	local bestDirection
	local bestDistance = math.huge
	for _, record in ipairs(records) do
		local direction = record.Root.Position - position
		local distance = horizontalDistance(record.Root.Position, position)
		if distance < bestDistance then
			bestDirection = direction
			bestDistance = distance
		end
	end
	return bestDirection or Vector3.new(0, 0, -1)
end

local function nearestRecord(position, records)
	local best
	local bestDistance = math.huge
	for _, record in ipairs(records) do
		local distance = horizontalDistance(position, record.Root.Position)
		if distance < bestDistance then
			best = record
			bestDistance = distance
		end
	end
	return best, bestDistance
end

local function setModelAndShared(session, name, value)
	publish(name, value)
	if session.Model and session.Model.Parent then
		session.Model:SetAttribute(name, value)
	end
end

local function setState(session, value)
	if session.State == value then return end
	session.State = value
	setModelAndShared(session, "Level2_SlidemouthState", value)
end

local function clearOwnedChaseMarker(player)
	if player and player.Parent == Players and player:GetAttribute("Level2_SlidemouthChased") == true then
		player:SetAttribute("Level2_SlidemouthChased", nil)
		player:SetAttribute("BeingChased", false)
	end
end

local function setTarget(session, player)
	if session.Target == player then return end
	clearOwnedChaseMarker(session.Target)
	session.Target = player
	if player and player.Parent == Players then
		player:SetAttribute("Level2_SlidemouthChased", true)
		player:SetAttribute("BeingChased", true)
	end
	local userId = player and player.UserId or 0
	setModelAndShared(session, "Level2_SlidemouthTargetUserId", userId)
end

local function cloneModel(session)
	local model = session.Template:Clone()
	if not model:IsA("Model") then
		model:Destroy()
		return nil, "template is not a Model"
	end
	local primary = model.PrimaryPart or model:FindFirstChildWhichIsA("MeshPart", true)
		or model:FindFirstChildWhichIsA("BasePart", true)
	if not primary then
		model:Destroy()
		return nil, "template has no BasePart"
	end
	model.Name = MODEL_NAME
	model.PrimaryPart = primary
	for _, descendant in ipairs(model:GetDescendants()) do
		if descendant:IsA("BasePart") then
			descendant.Anchored = true
			descendant.CanCollide = false
			descendant.CanTouch = false
			descendant.CanQuery = false
			descendant.Massless = true
			descendant.AssemblyLinearVelocity = Vector3.zero
			descendant.AssemblyAngularVelocity = Vector3.zero
		end
	end
	model:SetAttribute("Level2_Generation", session.Generation)
	model:SetAttribute("Level2_SlidemouthActive", true)
	model:SetAttribute("Level2_SlidemouthState", "SPAWNING")
	model:SetAttribute("Level2_SlidemouthSpeed", 0)
	model:SetAttribute("Level2_SlidemouthMoving", false)
	model:SetAttribute("Level2_SlidemouthScreamSerial", 0)
	model:SetAttribute("Level2_SlidemouthScreamKind", "")
	model:SetAttribute("Level2_SlidemouthTargetUserId", 0)
	model:SetAttribute("Level2_SlidemouthAnimationStartedAt", workspace:GetServerTimeNow())
	pcall(function() model.ModelStreamingMode = Enum.ModelStreamingMode.Persistent end)
	model.Parent = session.RuntimeFolder
	CollectionService:AddTag(model, "Level2HostileEntity")
	CollectionService:AddTag(model, "Level2SlidemouthEntity")
	return model
end

local function spawnHasEscapeClearance(navigator, facing)
	-- WarpTo validates the resting volume. Probe a small fan in the intended
	-- direction too; corridor nodes legitimately have two exits, not four.
	local foot = navigator:GetPosition()
	local flatFacing = Vector3.new(facing.X, 0, facing.Z)
	local forwardClear = flatFacing.Magnitude <= .01
	if flatFacing.Magnitude > .01 then
		for _, angle in ipairs({0, math.rad(38), math.rad(-38)}) do
			local direction = CFrame.fromAxisAngle(Vector3.yAxis, angle):VectorToWorldSpace(flatFacing.Unit)
			if navigator:_clearAdvance(foot + direction * 1.5) then
				forwardClear = true
				break
			end
		end
	end
	if not forwardClear then return false end
	local clearCardinals = 0
	for _, direction in ipairs({
		Vector3.new(1, 0, 0), Vector3.new(-1, 0, 0),
		Vector3.new(0, 0, 1), Vector3.new(0, 0, -1),
	}) do
		if navigator:_clearAdvance(foot + direction * 1.5) then clearCardinals += 1 end
	end
	return clearCardinals >= 2
end

local function spawnEntity(session)
	local records = livingRecords(session)
	local candidates = rankedSpawnCandidates(session, records, false, pumpActivatorPosition(2))
	if #candidates == 0 then return nil, "no Level 2 entity navigation anchors" end
	local model, modelError = cloneModel(session)
	if not model then return nil, modelError end
	local navigator = Navigator.new(model, session.Manifest, MOVEMENT, {
		RuntimeFolder = session.RuntimeFolder,
		ObstacleExclusions = session.Manifest.BuoyantProps
			and {session.Manifest.BuoyantProps} or nil,
	})
	local chosen
	local fallback
	for candidateIndex, candidate in ipairs(candidates) do
		if candidateIndex > 16 then break end
		local facing = facingTowardNearest(candidate.Anchor.Position, records)
		if navigator:WarpTo(candidate.Anchor.Position, facing, true) then
			local routeValid = true
			local nearest = nearestRecord(candidate.Anchor.Position, records)
			if nearest then
				local _, routeStatus = navigator:_fallbackWaypoints(nearest.Root.Position)
				routeValid = routeStatus ~= "NO_PATH"
			end
			if routeValid then
				fallback = fallback or candidate
				if spawnHasEscapeClearance(navigator, facing) then
					chosen = candidate
					break
				end
			end
		end
	end
	if not chosen and fallback then
		local facing = facingTowardNearest(fallback.Anchor.Position, records)
		if navigator:WarpTo(fallback.Anchor.Position, facing, true) then chosen = fallback end
	end
	if not chosen then
		navigator:Destroy()
		model:Destroy()
		return nil, "no spawn anchor has enough validated floor and body clearance"
	end
	session.Model = model
	session.Navigator = navigator
	session.Spawned = true
	session.CurrentSpeed = 0
	session.LastPosition = navigator:GetPosition()
	session.ProgressPosition = navigator:GetPosition()
	session.ProgressGoalDistance = math.huge
	session.ProgressAt = os.clock()
	session.RecoveryStage = 0
	session.SpawnRetryAt = math.huge
	setState(session, "HUNTING")
	setModelAndShared(session, "Level2_SlidemouthActive", true)
	setModelAndShared(session, "Level2_SlidemouthGeneration", session.Generation)
	setModelAndShared(session, "Level2_SlidemouthSpawnDistance", chosen.Distance)
	setModelAndShared(session, "Level2_SlidemouthSpawnHidden", chosen.Hidden)
	setModelAndShared(session, "Level2_SlidemouthSpawnAnchor", chosen.Anchor.Name)
	return true
end

local function chooseTarget(session, now)
	local records = livingRecords(session)
	local position = session.Navigator and session.Navigator:GetPosition()
	local currentRecord
	for _, record in ipairs(records) do
		if record.Player == session.Target then currentRecord = record break end
	end

	-- Nearby players in one hall behave as a group. The group attracts
	-- Slidemouth, but its actual goal remains a real player on valid ground.
	local remaining = {}
	for index = 1, #records do remaining[index] = true end
	local bestRecord
	local bestScore = math.huge
	for seed = 1, #records do
		if not remaining[seed] then continue end
		local group = {}
		local queue = {seed}
		remaining[seed] = nil
		local head = 1
		while head <= #queue do
			local index = queue[head]
			head += 1
			local member = records[index]
			table.insert(group, member)
			local memberHall = session.Navigator:FindHall(member.Root.Position)
			local memberHallId = memberHall and (memberHall.Index or memberHall.Id)
			for candidateIndex, available in pairs(remaining) do
				if available then
					local candidate = records[candidateIndex]
					local candidateHall = session.Navigator:FindHall(candidate.Root.Position)
					local candidateHallId = candidateHall and (candidateHall.Index or candidateHall.Id)
					if tostring(candidateHallId) == tostring(memberHallId)
						and horizontalDistance(member.Root.Position, candidate.Root.Position) <= 70 then
						remaining[candidateIndex] = nil
						table.insert(queue, candidateIndex)
					end
				end
			end
		end

		local centroid = Vector3.zero
		for _, member in ipairs(group) do centroid += member.Root.Position end
		centroid /= #group
		local representative
		local representativeDistance = math.huge
		local closeToGroup = position and horizontalDistance(position, centroid) <= 45
		for _, member in ipairs(group) do
			local distance = horizontalDistance(closeToGroup and position or centroid, member.Root.Position)
			if distance < representativeDistance then
				representative = member
				representativeDistance = distance
			end
		end
		local score = (position and horizontalDistance(position, centroid) or math.huge)
			- math.min(54, (#group - 1) * 18)
		if score < bestScore then
			bestScore = score
			bestRecord = representative
		end
	end

	if currentRecord then
		local currentDistance = horizontalDistance(position, currentRecord.Root.Position)
		local bestDistance = bestRecord and horizontalDistance(position, bestRecord.Root.Position) or math.huge
		if now < session.NextTargetSwitchAt
			or not bestRecord
			or bestRecord.Player == currentRecord.Player
			or bestDistance + 25 >= currentDistance then
			return currentRecord
		end
	end
	local nextPlayer = bestRecord and bestRecord.Player or nil
	if nextPlayer ~= session.Target then
		setTarget(session, nextPlayer)
		session.NextTargetSwitchAt = now + 1
	end
	return bestRecord
end

local function currentTargetRecord(session)
	return session.Target and livingRecord(session, session.Target) or nil
end

local function mouthAttachment(session)
	local model = session.Model
	if not model then return nil end
	local attachment = model:FindFirstChild("SlidemouthAudioEmitter", true)
	return attachment and attachment:IsA("Attachment") and attachment or nil
end

local function tryAttack(session, record, now)
	if now < session.AttackCooldownUntil then return false end
	local mouth = mouthAttachment(session)
	if not mouth then return false end
	local displacement = record.Root.Position - mouth.WorldPosition
	if displacement.Magnitude > ATTACK_DISTANCE then return false end
	local flat = Vector3.new(displacement.X, 0, displacement.Z)
	if flat.Magnitude > .05 then
		local facing = session.Navigator:GetFacing()
		if facing:Dot(flat.Unit) < -.15 then return false end
	end
	if not clearLine(session, mouth.WorldPosition, record.Root.Position) then return false end
	setState(session, "ATTACK")
	session.Navigator:Face(record.Root.Position)
	record.Humanoid.Health = 0
	session.AttackCooldownUntil = now + ATTACK_COOLDOWN
	setTarget(session, nil)
	return true
end

local function recoveryAnchor(session, records, requireHidden)
	local current = session.Navigator:GetPosition()
	local best
	local bestDistance = math.huge
	for _, candidate in ipairs(rankedSpawnCandidates(session, records, true)) do
		local distance = horizontalDistance(current, candidate.Anchor.Position)
		local direction = candidate.Anchor.Position - current
		local escapeClear = direction.Magnitude > .01
			and session.Navigator:_clearAdvance(current + direction.Unit * 1.5)
		local _, routeStatus = session.Navigator:_fallbackWaypoints(candidate.Anchor.Position)
		if distance >= 16 and distance <= 180
			and escapeClear
			and routeStatus ~= "NO_PATH"
			and (not requireHidden or candidate.Hidden)
			and distance < bestDistance then
			best = candidate
			bestDistance = distance
		end
	end
	return best
end

local function updateWatchdog(session, record, now)
	if now - session.ProgressAt < PROGRESS_WINDOW then return end
	local snapshot = session.Navigator:GetDebugSnapshot()
	if snapshot.Computing and now - session.ProgressAt < PROGRESS_WINDOW * 2 then return end
	local position = session.Navigator:GetPosition()
	local goal = session.Navigator:GetGoal()
	local goalDistance = goal and horizontalDistance(position, goal) or math.huge
	local travel = horizontalDistance(position, session.ProgressPosition)
	local goalProgress = finiteNumber(session.ProgressGoalDistance)
		and finiteNumber(goalDistance) and session.ProgressGoalDistance - goalDistance or 0
	-- A valid graph route can initially move sideways—or even away from the
	-- player's straight-line distance—to clear a hall or doorway. Net travel is
	-- therefore sufficient progress; requiring goalProgress >= 0 caused a forced
	-- route reversal every PROGRESS_WINDOW seconds.
	local expected = math.max(1.5, session.CurrentSpeed * (now - session.ProgressAt) * .3)
	if travel >= expected or goalProgress >= .8 or not record then
		session.RecoveryStage = 0
		session.RecoveryGoal = nil
		session.RecoveryUntil = 0
		session.GraphRecoveryUntil = 0
	else
		session.RecoveryStage += 1
		if session.RecoveryStage == 1 and goal then
			session.GraphRecoveryUntil = now + 1.5
			session.Navigator:SetGraphGoal(goal, true)
		elseif session.RecoveryStage == 2 then
			session.GraphRecoveryUntil = 0
			local candidate = recoveryAnchor(session, livingRecords(session), false)
			if candidate then
				session.RecoveryGoal = candidate.Anchor.Position
				session.RecoveryUntil = now + 2
				session.Navigator:SetGoal(session.RecoveryGoal, true)
			else
				session.Navigator:SetGraphGoal(record.Root.Position, true)
			end
		else
			local records = livingRecords(session)
			local candidate = recoveryAnchor(session, records, true)
			if candidate and session.Navigator:WarpTo(candidate.Anchor.Position,
				facingTowardNearest(candidate.Anchor.Position, records), true) then
				session.RecoveryStage = 0
				session.RecoveryGoal = nil
				session.RecoveryUntil = 0
				session.GraphRecoveryUntil = 0
			else
				session.RecoveryStage = 1
				if goal then session.Navigator:SetGraphGoal(goal, true) end
			end
		end
	end
	session.ProgressPosition = session.Navigator:GetPosition()
	session.ProgressGoalDistance = session.Navigator:GetGoal()
		and horizontalDistance(session.ProgressPosition, session.Navigator:GetGoal()) or math.huge
	session.ProgressAt = now
end

local function minimumPlayerDistance(position, records)
	local minimum = math.huge
	for _, record in ipairs(records) do
		minimum = math.min(minimum, horizontalDistance(position, record.Root.Position))
	end
	return minimum
end

local function chooseHiddenAnchor(session, records, minimumDistance, maximumDistance, idealDistance)
	local best
	local bestScore = -math.huge
	for _, anchor in ipairs(session.Anchors) do
		if anchor.Part.Parent then
			local distance = minimumPlayerDistance(anchor.Position, records)
			if distance == math.huge then distance = idealDistance end
			if distance >= minimumDistance and distance <= maximumDistance
				and not positionObserved(session, anchor.Position, records) then
				local score = -math.abs(distance - idealDistance)
				if anchor.IsCenter then score += 12 end
				if score > bestScore then
					best = {Anchor = anchor, Distance = distance, Hidden = true}
					bestScore = score
				end
			end
		end
	end
	return best
end

local function choosePumpScreamPosition(session)
	local records = livingRecords(session)
	local chosen = chooseHiddenAnchor(session, records, 85, 160, 120)
		or chooseHiddenAnchor(session, records, 45, 240, 120)
	if not chosen then
		local ranked = rankedSpawnCandidates(session, records, true)
		chosen = ranked[1]
	end
	return chosen and chosen.Anchor.Position + Vector3.new(0, 4.5, 0)
		or (records[1] and records[1].Root.Position + Vector3.new(0, 5, -120))
		or Vector3.new(0, 5, 0)
end

local function publishPositionalPumpScream(session, pumpNumber, position)
	session.WarningSerial += 1
	publish("Level2_SlidemouthWarningPosition", position)
	publish("Level2_SlidemouthWarningPump", pumpNumber)
	publish("Level2_SlidemouthScreamBusyUntil", workspace:GetServerTimeNow() + 14)
	-- Serial is deliberately last so clients see the completed event payload.
	publish("Level2_SlidemouthWarningSerial", session.WarningSerial)
end

local function forceMouthScream(session, pumpNumber)
	if not (session.Model and session.Model.Parent) then return false end
	local mouth = mouthAttachment(session)
	local position = mouth and mouth.WorldPosition
		or (session.Model.PrimaryPart and session.Model.PrimaryPart.Position)
		or session.Model:GetPivot().Position
	session.ScreamSerial += 1
	setModelAndShared(session, "Level2_SlidemouthScreamKind", "PUMP_" .. tostring(pumpNumber))
	publish("Level2_SlidemouthScreamPosition", position)
	publish("Level2_SlidemouthScreamBusyUntil", workspace:GetServerTimeNow() + 14)
	setModelAndShared(session, "Level2_SlidemouthScreamSerial", session.ScreamSerial)
	return true
end

local function schedulePumpScream(session, pumpNumber)
	if session.PumpScreamScheduled[pumpNumber] then return end
	local state = stateFolder()
	local startedAt = state
		and tonumber(state:GetAttribute("Level2_PumpStartedAt" .. tostring(pumpNumber))) or nil
	if not finiteNumber(startedAt) or startedAt <= 0 then
		startedAt = workspace:GetServerTimeNow()
	end
	local groanDelay = pumpNumber == 1 and PUMP_ONE_GROAN_DELAY or SPAWN_GROAN_DELAY
	local dueAt = startedAt + groanDelay
	session.PumpScreamScheduled[pumpNumber] = dueAt
	local capturedPosition = pumpNumber == 1 and choosePumpScreamPosition(session) or nil
	task.spawn(function()
		local remaining = dueAt - workspace:GetServerTimeNow()
		if remaining > 0 then task.wait(remaining) end
		if not sessionAlive(session) or not roundReady(session)
			or (tonumber(workspace:GetAttribute("Level2Pumps")) or 0) < pumpNumber
			or session.PumpScreamPlayed[pumpNumber] then
			return
		end
		session.PumpScreamPlayed[pumpNumber] = true
		if pumpNumber >= SPAWN_PUMPS and forceMouthScream(session, pumpNumber) then return end
		publishPositionalPumpScream(
			session,
			pumpNumber,
			capturedPosition or choosePumpScreamPosition(session)
		)
	end)
end

local function relocateForThirdPump(session)
	if not (session.Navigator and session.Model and session.Model.Parent) then return false end
	setModelAndShared(session, "Level2_SlidemouthEscalationPhase", "SCANNING")
	local records = livingRecords(session)
	if #records == 0 then return false end
	local current = session.Navigator:GetPosition()
	local currentFacing = session.Navigator:GetFacing()
	local candidates = {}
	for _, anchor in ipairs(session.Anchors) do
		if anchor.Part.Parent and horizontalDistance(current, anchor.Position) >= 25 then
			local distance = minimumPlayerDistance(anchor.Position, records)
			local hiddenByGeometry = not positionObserved(session, anchor.Position, records)
			local behindPlayers = positionBehindPlayers(anchor.Position, records)
			-- Prefer a close out-of-view anchor. If hall spacing leaves no anchor
			-- inside 170 studs, a geometry-hidden fallback may reach 260 studs.
			local eligible = distance >= 45
				and ((distance <= 170 and (hiddenByGeometry or behindPlayers))
					or (distance <= 260 and hiddenByGeometry))
			if eligible then
				table.insert(candidates, {
					Anchor = anchor,
					Distance = distance,
					Score = -math.abs(distance - 78) * 20
						+ (hiddenByGeometry and 600 or 0)
						+ (behindPlayers and 300 or 0)
						+ (anchor.IsCenter and 20 or 0),
				})
			end
		end
	end
	table.sort(candidates, function(a, b) return a.Score > b.Score end)
	setModelAndShared(session, "Level2_SlidemouthEscalationCandidates", #candidates)
	for candidateIndex, candidate in ipairs(candidates) do
		if candidateIndex > 3 then break end
		setModelAndShared(session, "Level2_SlidemouthEscalationPhase", "VALIDATING_" .. candidateIndex)
		local facing = facingTowardNearest(candidate.Anchor.Position, records)
		-- WarpTo already validates the complete 16-by-11-stud body volume.
		-- The stricter spawn fan is useful for the first appearance, but here it
		-- rejected safe near-player patrol nodes and defeated the escalation.
		if session.Navigator:WarpTo(candidate.Anchor.Position, facing, true) then
			local nearest = nearestRecord(candidate.Anchor.Position, records)
			local routeStatus = "NO_PATH"
			if nearest then
				local _
				_, routeStatus = session.Navigator:_fallbackWaypoints(nearest.Root.Position)
			end
			if routeStatus ~= "NO_PATH" then
				session.ProgressPosition = session.Navigator:GetPosition()
				session.ProgressGoalDistance = math.huge
				session.ProgressAt = os.clock()
				session.RecoveryStage = 0
				session.RecoveryGoal = nil
				session.RecoveryUntil = 0
				setModelAndShared(session, "Level2_SlidemouthEscalationDistance", candidate.Distance)
				setModelAndShared(session, "Level2_SlidemouthEscalationAnchor", candidate.Anchor.Name)
				setModelAndShared(session, "Level2_SlidemouthEscalationPhase", "RELOCATED")
				return true
			end
		end
	end
	session.Navigator:WarpTo(current, currentFacing, true)
	setModelAndShared(session, "Level2_SlidemouthEscalationPhase", "KEPT_POSITION")
	return false
end

local function chooseWanderGoal(session)
	local current = session.Navigator:GetPosition()
	local currentHall = session.Navigator:FindHall(current)
	local currentHallId = currentHall and (currentHall.Index or currentHall.Id)
	local candidates = {}
	for _, anchor in ipairs(session.Anchors) do
		if anchor.Part.Parent and anchor.Name ~= session.LastWanderAnchor then
			local distance = horizontalDistance(current, anchor.Position)
			local anchorHall = session.Navigator:FindHall(anchor.Position)
			local anchorHallId = anchorHall and (anchorHall.Index or anchorHall.Id)
			local _, routeStatus = session.Navigator:_fallbackWaypoints(anchor.Position)
			if distance >= 70 and distance <= 280 and routeStatus ~= "NO_PATH" then
				local differentHall = tostring(anchorHallId) ~= tostring(currentHallId)
				table.insert(candidates, {
					Anchor = anchor,
					Score = (differentHall and 1000 or 0)
						- math.abs(distance - 150) + session.Random:NextNumber(0, 25),
				})
			end
		end
	end
	table.sort(candidates, function(a, b) return a.Score > b.Score end)
	return candidates[1] and candidates[1].Anchor or nil
end

local function updateWander(session, now, dt)
	setState(session, "WANDER")
	local position = session.Navigator:GetPosition()
	local needsGoal = not session.WanderGoal
		or now >= session.WanderGoalUntil
		or horizontalDistance(position, session.WanderGoal) <= MOVEMENT.WaypointArrivalDistance + 1
		or (session.Navigator:GetStatus() == "BLOCKED" and now >= session.WanderMoveDeadline)
		or session.Navigator:GetStatus() == "NO_FLOOR"
		or session.Navigator:GetStatus() == "NO_PATH"
	if needsGoal then
		local anchor = chooseWanderGoal(session)
		if anchor then
			session.WanderGoal = anchor.Position
			session.WanderGoalUntil = now + session.Random:NextNumber(8, 13)
			session.WanderMoveDeadline = now + 1
			session.LastWanderAnchor = anchor.Name
			session.Navigator:SetGoal(session.WanderGoal, true)
		else
			session.WanderGoal = nil
			session.Navigator:Stop()
		end
	end
	local before = session.Navigator:GetPosition()
	if session.WanderGoal then
		session.Navigator:SetGoal(session.WanderGoal)
		session.Navigator:Step(math.min(dt, .1), session.CurrentSpeed)
	end
	local moved = horizontalDistance(before, session.Navigator:GetPosition()) > .01
	if moved then session.WanderMoveDeadline = now + 1 end
	setModelAndShared(session, "Level2_SlidemouthMoving", moved)
	setModelAndShared(session, "Level2_SlidemouthSpeed", session.CurrentSpeed)
	setModelAndShared(session, "Level2_SlidemouthPathStatus", session.Navigator:GetStatus())
end

local function processPumpTransition(session, pumpNumber)
	if pumpNumber == 1 then return true end
	if not session.Spawned then
		local ok, failure = spawnEntity(session)
		if not ok then return false, failure end
	end
	if pumpNumber >= FAST_PUMPS then
		local relocated, relocationResult = pcall(relocateForThirdPump, session)
		if not relocated then
			warn("[Level 2 Slidemouth] escalation relocation failed: " .. tostring(relocationResult))
			setModelAndShared(session, "Level2_SlidemouthEscalationPhase", "ERROR")
		end
	end
	setModelAndShared(session, "Level2_SlidemouthEscalationPhase",
		pumpNumber >= FAST_PUMPS and "SCREAMED" or "PUMP_2_SCREAMED")
	return true
end

local function updateEntity(session, dt)
	local now = os.clock()
	local pumps = tonumber(workspace:GetAttribute("Level2Pumps")) or 0
	local desiredSpeed = pumps >= FAST_PUMPS and PUMP_THREE_SPEED or PUMP_TWO_SPEED
	local difference = desiredSpeed - session.CurrentSpeed
	local rate = difference >= 0 and ACCELERATION or DECELERATION
	session.CurrentSpeed += math.clamp(difference, -rate * dt, rate * dt)
	if session.Escalating then
		setModelAndShared(session, "Level2_SlidemouthMoving", false)
		setModelAndShared(session, "Level2_SlidemouthSpeed", session.CurrentSpeed)
		setModelAndShared(session, "Level2_SlidemouthPumps", pumps)
		return
	end

	if now >= session.NextTargetRefreshAt then
		chooseTarget(session, now)
		session.NextTargetRefreshAt = now + TARGET_REFRESH
	end
	local record = currentTargetRecord(session)
	if not record then
		setTarget(session, nil)
		updateWander(session, now, dt)
		return
	end
	session.WanderGoal = nil
	setState(session, "CHASE")
	if tryAttack(session, record, now) then return end

	local targetPosition = record.Root.Position
	local goal = targetPosition
	if session.RecoveryGoal and now < session.RecoveryUntil then goal = session.RecoveryGoal else session.RecoveryGoal = nil end
	-- Keep a graph recovery alive long enough to clear a centered portal.
	-- Otherwise use obstacle-aware PFS, now sized to the real creature.
	if now < session.GraphRecoveryUntil then
		session.Navigator:SetGraphGoal(goal)
	else
		session.Navigator:SetGoal(goal)
	end
	local before = session.Navigator:GetPosition()
	session.Navigator:Step(math.min(dt, .1), session.CurrentSpeed)
	local after = session.Navigator:GetPosition()
	local moved = horizontalDistance(before, after) > .01
	setModelAndShared(session, "Level2_SlidemouthMoving", moved)
	setModelAndShared(session, "Level2_SlidemouthSpeed", session.CurrentSpeed)
	setModelAndShared(session, "Level2_SlidemouthPumps", pumps)
	setModelAndShared(session, "Level2_SlidemouthPathStatus", session.Navigator:GetStatus())
	tryAttack(session, record, now)
	updateWatchdog(session, record, now)
end

local function shoveBuoyantProps(session, before, after, now)
	local params = session.SoftObstacleParams
	local buoyantProps = session.BuoyantProps
	if not (params and buoyantProps and #buoyantProps > 0
		and session.Model and session.Model.PrimaryPart) then return end

	local travel = Vector3.new(after.X - before.X, 0, after.Z - before.Z)
	local direction
	if travel.Magnitude > .05 then
		direction = travel.Unit
	else
		local look = session.Model.PrimaryPart.CFrame.LookVector
		direction = Vector3.new(look.X, 0, look.Z)
		if direction.Magnitude <= .001 then return end
		direction = direction.Unit
	end
	local height = math.max(8, MOVEMENT.AgentHeight - .5)
	local footCenter = (before + after) * .5
	local boxCenter = Vector3.new(footCenter.X,
		math.max(before.Y, after.Y) + height * .5, footCenter.Z)
	local bodyLength = 21.5 + travel.Magnitude
	local boxCFrame = CFrame.lookAt(boxCenter, boxCenter + direction)
	local boxSize = Vector3.new(MOVEMENT.AgentRadius * 2 + 1.5, height, bodyLength)

	for _, object in ipairs(workspace:GetPartBoundsInBox(boxCFrame, boxSize, params)) do
		if not (object:IsA("BasePart")
			and object:GetAttribute("Level2_BuoyantProp") == true
			and not object.Anchored
			and object:IsDescendantOf(session.Manifest.World)) then continue end
		local previousShove = session.SoftShoveTimes[object]
		if previousShove and now - previousShove < BUOYANT_SHOVE_COOLDOWN then continue end
		session.SoftShoveTimes[object] = now

		local offset = Vector3.new(object.Position.X - after.X, 0, object.Position.Z - after.Z)
		local lateral = offset - direction * offset:Dot(direction)
		local shoveDirection = direction
		if lateral.Magnitude > .05 then
			shoveDirection = (direction + lateral.Unit * .55).Unit
		end
		local shoveSpeed = math.clamp(session.CurrentSpeed + 8,
			BUOYANT_SHOVE_MIN_SPEED, BUOYANT_SHOVE_MAX_SPEED)
		local currentVelocity = object.AssemblyLinearVelocity
		local desiredVelocity = shoveDirection * shoveSpeed
			+ Vector3.new(0, math.max(2.5, currentVelocity.Y), 0)
		local velocityChange = desiredVelocity - currentVelocity
		if velocityChange.Magnitude > 55 then velocityChange = velocityChange.Unit * 55 end
		local mass = math.max(.01, object.AssemblyMass)
		local sideSign = lateral:Dot(session.Model.PrimaryPart.CFrame.RightVector) >= 0 and 1 or -1
		pcall(function()
			object:ApplyImpulse(velocityChange * mass)
			object:ApplyAngularImpulse(Vector3.new(0, sideSign * mass * 4, 0))
		end)
		session.ShovedProps += 1
		session.Model:SetAttribute("Level2_SlidemouthShovedProps", session.ShovedProps)
		session.Model:SetAttribute("Level2_SlidemouthLastShovedProp", object.Name)
	end
end

local function heartbeat(session, dt)
	if not sessionAlive(session) then Controller.Stop(); return end
	if not roundReady(session) then
		if session.Navigator then session.Navigator:Stop() end
		setTarget(session, nil)
		setModelAndShared(session, "Level2_SlidemouthMoving", false)
		return
	end
	if workspace:GetAttribute("EntityPaused") == true then
		if session.Navigator then session.Navigator:Stop() end
		setState(session, "PAUSED")
		setModelAndShared(session, "Level2_SlidemouthMoving", false)
		return
	end
	local pumps = math.max(0, math.floor(tonumber(workspace:GetAttribute("Level2Pumps")) or 0))
	while session.LastPumps < pumps do
		local nextPump = session.LastPumps + 1
		schedulePumpScream(session, nextPump)
		if nextPump >= SPAWN_PUMPS and not session.Spawned
			and os.clock() < session.SpawnRetryAt then return end
		if nextPump >= FAST_PUMPS then
			-- Mark the edge before doing the hidden relocation so Heartbeat can
			-- keep driving speed/state without launching duplicate searches.
			session.LastPumps = nextPump
			session.Escalating = true
			setModelAndShared(session, "Level2_SlidemouthEscalationPhase", "QUEUED")
			task.spawn(function()
				local callOk, transitionOk, failure = pcall(processPumpTransition, session, nextPump)
				if not callOk then
					failure = transitionOk
					transitionOk = false
				end
				if sessionAlive(session) and not transitionOk then
					warn("[Level 2 Slidemouth] escalation failed: " .. tostring(failure))
					setModelAndShared(session, "Level2_SlidemouthEscalationPhase", "ERROR")
				end
				if activeSession == session then session.Escalating = false end
			end)
			break
		end
		local callOk, ok, failure = pcall(processPumpTransition, session, nextPump)
		if not callOk then
			failure = ok
			ok = false
		end
		if not ok then
			session.SpawnRetryAt = os.clock() + 2
			publish("Level2_SlidemouthState", "SPAWN_RETRY")
			publish("Level2_SlidemouthPathStatus", tostring(failure))
			warn("[Level 2 Slidemouth] pump transition retry: " .. tostring(failure))
			return
		end
		session.LastPumps = nextPump
	end
	if pumps < SPAWN_PUMPS then return end
	if session.Model and session.Model.Parent and session.Navigator then
		local before = session.Navigator:GetPosition()
		updateEntity(session, math.min(dt, .1))
		shoveBuoyantProps(session, before, session.Navigator:GetPosition(), os.clock())
	end
end

function Controller.Stop()
	local session = activeSession
	activeSession = nil
	if session then
		for _, connection in ipairs(session.Connections) do connection:Disconnect() end
		setTarget(session, nil)
		if session.Navigator then session.Navigator:Destroy() end
		if session.Model and session.Model.Parent then session.Model:Destroy() end
		if session.RuntimeFolder and session.RuntimeFolder.Parent then session.RuntimeFolder:Destroy() end
	end
	publishStopped("IDLE")
end

function Controller.Start(manifest, generation)
	Controller.Stop()
	if not (manifest and manifest.World and manifest.World.Parent and typeof(manifest.Layout) == "table") then
		return nil, "invalid Level 2 manifest"
	end
	if not finiteNumber(generation) then return nil, "invalid generation" end
	local assets = ServerStorage:FindFirstChild("Level2Assets")
	local template = assets and assets:FindFirstChild(TEMPLATE_NAME)
	if not (template and template:IsA("Model") and template.PrimaryPart) then
		return nil, "missing ServerStorage.Level2Assets." .. TEMPLATE_NAME
	end
	local runtimeFolder = Instance.new("Folder")
	runtimeFolder.Name = RUNTIME_NAME
	runtimeFolder:SetAttribute("Level2_Generation", generation)
	runtimeFolder.Parent = manifest.World
	local session = {
		Manifest = manifest,
		Generation = generation,
		Template = template,
		RuntimeFolder = runtimeFolder,
		Anchors = collectAnchors(manifest),
		Connections = {},
		Random = Random.new(),
		Spawned = false,
		SpawnRetryAt = 0,
		CurrentSpeed = 0,
		State = "DORMANT",
		Target = nil,
		NextTargetRefreshAt = 0,
		NextTargetSwitchAt = 0,
		ScreamSerial = 0,
		WarningSerial = 0,
		PumpScreamScheduled = {},
		PumpScreamPlayed = {},
		LastPumps = 0,
		Escalating = false,
		AttackCooldownUntil = 0,
		RecoveryGoal = nil,
		RecoveryUntil = 0,
		GraphRecoveryUntil = 0,
		WanderGoal = nil,
		WanderGoalUntil = 0,
		WanderMoveDeadline = 0,
		LastWanderAnchor = nil,
		SoftObstacleParams = nil,
		BuoyantProps = {},
		SoftShoveTimes = setmetatable({}, {__mode = "k"}),
		ShovedProps = 0,
	}
	for _, descendant in ipairs(manifest.World:GetDescendants()) do
		if descendant:IsA("BasePart") and descendant:GetAttribute("Level2_BuoyantProp") == true then
			table.insert(session.BuoyantProps, descendant)
		end
	end
	if #session.BuoyantProps > 0 then
		local softParams = OverlapParams.new()
		softParams.FilterType = Enum.RaycastFilterType.Include
		softParams.FilterDescendantsInstances = session.BuoyantProps
		softParams.MaxParts = 64
		softParams.RespectCanCollide = false
		session.SoftObstacleParams = softParams
	end
	if #session.Anchors == 0 then
		runtimeFolder:Destroy()
		return nil, "manifest contains no entity navigation anchors"
	end
	activeSession = session
	publish("Level2_SlidemouthGeneration", generation)
	publish("Level2_SlidemouthActive", false)
	publish("Level2_SlidemouthState", session.State)
	publish("Level2_SlidemouthTargetUserId", 0)
	publish("Level2_SlidemouthSpeed", 0)
	publish("Level2_SlidemouthPathStatus", "IDLE")
	publish("Level2_SlidemouthScreamSerial", 0)
	table.insert(session.Connections, RunService.Heartbeat:Connect(function(dt)
		heartbeat(session, dt)
	end))
	table.insert(session.Connections, Players.PlayerRemoving:Connect(function(player)
		if session.Target == player then setTarget(session, nil) end
	end))
	return session
end

function Controller.IsRunning()
	return activeSession ~= nil and sessionAlive(activeSession)
end

local function vectorTable(value)
	return value and {X = value.X, Y = value.Y, Z = value.Z} or nil
end

function Controller.GetDebugSnapshot()
	local session = activeSession
	if not session then return {Running = false} end
	local navigation = session.Navigator and session.Navigator:GetDebugSnapshot() or nil
	if navigation then
		navigation.Position = vectorTable(navigation.Position)
		navigation.Goal = vectorTable(navigation.Goal)
	end
	return {
		Running = sessionAlive(session),
		Generation = session.Generation,
		State = session.State,
		Spawned = session.Spawned,
		Pumps = tonumber(workspace:GetAttribute("Level2Pumps")) or 0,
		Speed = session.CurrentSpeed,
		TargetUserId = session.Target and session.Target.UserId or 0,
		RecoveryStage = session.RecoveryStage or 0,
		ScreamSerial = session.ScreamSerial,
		WarningSerial = session.WarningSerial,
		ProcessedPumps = session.LastPumps,
		WanderGoal = vectorTable(session.WanderGoal),
		Position = session.Navigator and vectorTable(session.Navigator:GetPosition()) or nil,
		Navigation = navigation,
	}
end

return Controller
