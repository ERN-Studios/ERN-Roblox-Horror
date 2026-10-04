-- Level 2 Pool Foam Controller
--
-- Session-owned server runtime for one Pool Foam clone in every Kids Area.
-- Clients submit camera telemetry only; this controller owns observation,
-- anchored movement, lethal contact, effects, cleanup and debug state.

local Players = game:GetService("Players")
local CollectionService = game:GetService("CollectionService")
local Debris = game:GetService("Debris")
local ReplicatedStorage = game:GetService("ReplicatedStorage")
local RunService = game:GetService("RunService")
local ServerStorage = game:GetService("ServerStorage")

local Controller = {}
local activeSession

local PROTOCOL = 1
local MODULE_CONFIGURATION = "Level 2 Pool Foam Configuration"
local MODULE_PROXY_FACTORY = "Level 2 Pool Foam Proxy Factory"
local MODULE_ANIMATION_ADAPTER = "Level 2 Pool Foam Animation Adapter"
local MODULE_NAVIGATOR = "Level 2 Pool Foam Navigator"
local MODULE_OBSERVER = "Level 2 Pool Foam Observer"
local AUDIO_LIBRARY_NAME = "Level 2 Pool Foam Audio"
local SPECIFIC_ENTITY_TAG = "Level2PoolFoamEntity"
local RUNTIME_ENTITY_TAG = "Level2EntityRuntime"
local DECOY_TAG = "Level2EntityDecoy"
local TRAIL_TAG = "Level2EntityTrail"

local CLIENT_EVENT_TYPE = table.freeze({
	Started = "Cue",
	Trail = "Cue",
	MoverChanged = "Cue",
	TemplateResolved = "Cue",
	RevealOverrun = "Reveal",
	AttackHit = "AttackHit",
	Phase = "Phase",
	Decoy = "Decoy",
})

local PHASES = table.freeze({
	Dormant = "Dormant",
	Foreshadow = "Foreshadow",
	Pressure = "Pressure",
	Finale = "Finale",
})

local AUDIO_STATES = {"Idle", "Walk", "Caught", "Hunt", "Attack", "Collapse"}

local function finiteNumber(value)
	return typeof(value) == "number" and value == value and value > -math.huge and value < math.huge
end

local function numberOr(value, fallback, minimum, maximum)
	if not finiteNumber(value) then value = fallback end
	if minimum then value = math.max(minimum, value) end
	if maximum then value = math.min(maximum, value) end
	return value
end

local function vectorTable(value)
	if typeof(value) ~= "Vector3" then return nil end
	return {X = value.X, Y = value.Y, Z = value.Z}
end

local function loadSibling(name, required)
	local child = script.Parent:FindFirstChild(name)
	if not (child and child:IsA("ModuleScript")) then
		local message = ("missing sibling ModuleScript %q"):format(name)
		if required then warn("[Pool Foam] " .. message) end
		return nil, message
	end
	local ok, result = pcall(require, child)
	if not ok then
		local message = ("%s failed to require: %s"):format(name, tostring(result))
		if required then warn("[Pool Foam] " .. message) end
		return nil, message
	end
	return result
end

local function syncAudioLibrary(configuration)
	local folder = ReplicatedStorage:FindFirstChild(AUDIO_LIBRARY_NAME)
	if folder and not folder:IsA("Folder") then
		warn("[Pool Foam] " .. AUDIO_LIBRARY_NAME .. " must be a Folder")
		return nil
	end
	if not folder then
		folder = Instance.new("Folder")
		folder.Name = AUDIO_LIBRARY_NAME
		folder.Parent = ReplicatedStorage
	end
	folder:SetAttribute("ConfigurationVersion", tonumber(configuration.Version) or 1)
	for _, slot in ipairs({"Primary", "Secondary"}) do
		local configured = configuration.AudioIds and configuration.AudioIds[slot] or {}
		for _, stateName in ipairs(AUDIO_STATES) do
			local name = slot .. " " .. stateName
			local value = folder:FindFirstChild(name)
			if value and not value:IsA("StringValue") then
				warn("[Pool Foam] audio slot " .. value:GetFullName() .. " must be a StringValue")
			elseif not value then
				value = Instance.new("StringValue")
				value.Name = name
				value.Parent = folder
			end
			if value then value.Value = tostring(configured[stateName] or "") end
		end
	end
	return folder
end

local function levelState()
	local state = ReplicatedStorage:FindFirstChild("Level 2 State")
	return state and state:IsA("Folder") and state or nil
end

local function setShared(name, value)
	local state = levelState()
	if state and state:GetAttribute(name) ~= value then state:SetAttribute(name, value) end
end

local function publishStopped(reason)
	setShared("Level2_PoolFoamActive", false)
	setShared("Level2_PoolFoamPhase", reason or "Stopped")
	setShared("Level2_PoolFoamGeneration", 0)
	setShared("Level2_PoolFoamActiveMover", "")
end

local function sessionAlive(session)
	if activeSession ~= session or not (session.Manifest.World and session.Manifest.World.Parent) then return false end
	local worldGeneration = session.Manifest.World:GetAttribute("Level2_Generation")
	return worldGeneration == nil or worldGeneration == session.Generation
end

local function roundReady(session)
	return sessionAlive(session)
		and workspace:GetAttribute("SelectedLevel") == 2
		and workspace:GetAttribute("RoundActive") == true
end

local function livingPlayer(session, player)
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
	if not (character and humanoid and humanoid.Health > 0 and root and root:IsA("BasePart")) then return nil end
	return root, humanoid, character
end

local function hallCenter(hall)
	if typeof(hall and hall.Center) == "Vector3" then return hall.Center end
	return Vector3.new(
		((tonumber(hall and hall.MinX) or 0) + (tonumber(hall and hall.MaxX) or 0)) * 0.5,
		0,
		((tonumber(hall and hall.MinZ) or 0) + (tonumber(hall and hall.MaxZ) or 0)) * 0.5
	)
end

local function normalizeKidsArea(layout)
	local halls = {}
	local allowed = {}
	local hallIds = {}
	for _, raw in ipairs(layout.KidsArea or {}) do
		local hall = typeof(raw) == "table" and raw or layout.Halls[tonumber(raw)]
		local index = hall and (tonumber(hall.Index) or table.find(layout.Halls, hall))
		if hall and index and not allowed[index] then
			table.insert(halls, hall)
			allowed[index] = true
			if typeof(hall.Id) == "string" then hallIds[hall.Id] = index end
		end
	end
	table.sort(halls, function(a, b) return (tonumber(a.Index) or 0) < (tonumber(b.Index) or 0) end)
	return halls, allowed, hallIds
end

local function positionInKids(session, position)
	for _, hall in ipairs(session.KidsHalls) do
		local minX = tonumber(hall.MinX)
		local maxX = tonumber(hall.MaxX)
		local minZ = tonumber(hall.MinZ)
		local maxZ = tonumber(hall.MaxZ)
		if minX and maxX and minZ and maxZ
			and position.X >= minX and position.X <= maxX
			and position.Z >= minZ and position.Z <= maxZ
		then
			return true, tonumber(hall.Index)
		end
	end
	return false, nil
end

local function collectNodes(manifest, hallIds, allowed)
	local nodes = {}
	if manifest.EntityNodes then
		for _, child in ipairs(manifest.EntityNodes:GetChildren()) do
			if child:IsA("BasePart") then
				local hallId = child:GetAttribute("Level2_HallId")
				local index = hallIds[hallId] or tonumber(hallId)
				if index and allowed[index] then
					table.insert(nodes, {
						Position = child.Position,
						HallIndex = index,
						Name = child.Name,
						IsPoolFoamSpawn = child:GetAttribute("Level2_PoolFoamSpawn") == true,
					})
				end
			end
		end
	end
	table.sort(nodes, function(a, b) return a.Name < b.Name end)
	return nodes
end

local function positionForHall(session, hall)
	local index = tonumber(hall and hall.Index)
	local choices = {}
	local dedicated = {}
	for _, node in ipairs(session.Nodes) do
		if node.HallIndex == index then
			table.insert(choices, node)
			if node.IsPoolFoamSpawn then table.insert(dedicated, node) end
		end
	end
	local candidates = #dedicated > 0 and dedicated or choices
	if #candidates > 0 then return candidates[1].Position end
	return hallCenter(hall) + Vector3.new(0, 2, 0)
end

local function setModelAttribute(model, name, value)
	if typeof(name) == "string" and name ~= "" and model:GetAttribute(name) ~= value then
		model:SetAttribute(name, value)
	end
end

local function setEntityAnimation(entity, state, force)
	if entity.Animation then
		local ok, failure = pcall(function() entity.Animation:SetState(state, force == true) end)
		if not ok then
			warn("[Pool Foam] animation adapter disabled: " .. tostring(failure))
			pcall(function() entity.Animation:Destroy() end)
			entity.Animation = nil
		end
	end
	local attributes = entity.Session.Configuration.Attributes or {}
	setModelAttribute(entity.Model, attributes.AnimationState or "PoolFoamAnimationState", state)
	setModelAttribute(entity.Model, attributes.MotionState or "MotionState", state)
end

local function setEntityAnimationPaused(entity, value)
	local paused = value == true
	if entity.Animation and entity.AnimationPaused ~= paused then
		local ok, failure = pcall(function() entity.Animation:SetPaused(paused) end)
		if not ok then warn("[Pool Foam] animation pause failed: " .. tostring(failure)) end
	end
	entity.AnimationPaused = paused
	local attributes = entity.Session.Configuration.Attributes or {}
	setModelAttribute(entity.Model, attributes.AnimationPaused or "PoolFoamAnimationPaused", paused)
end

local function configureModel(session, entity, model)
	local attributes = session.Configuration.Attributes or {}
	setModelAttribute(model, attributes.Slot or "PoolFoamSlot", entity.SlotId)
	setModelAttribute(model, attributes.InstanceId or "PoolFoamEntityId", entity.Id)
	setModelAttribute(model, attributes.Profile or "Profile", entity.Slot.Profile or entity.SlotId)
	setModelAttribute(model, "Level2_Generation", session.Generation)
	setModelAttribute(model, "Level2_KidsHallIndex", entity.HallIndex)
	setModelAttribute(model, "Level2_PoolFoamObserved", false)
	setModelAttribute(model, "Level2_PoolFoamActiveMover", false)
	if session.Configuration.GenericHostileTag then
		CollectionService:AddTag(model, session.Configuration.GenericHostileTag)
	end
	CollectionService:AddTag(model, SPECIFIC_ENTITY_TAG)
	CollectionService:AddTag(model, RUNTIME_ENTITY_TAG)
end

local function createAnimation(session, model, slot)
	if not session.AnimationAdapter then return nil end
	local ok, adapter = pcall(function() return session.AnimationAdapter.new(model, slot) end)
	if not ok then
		warn("[Pool Foam] optional animation adapter failed: " .. tostring(adapter))
		return nil
	end
	return adapter
end

local function createEntity(session, id, slotId, spawnPosition, hallIndex, spawnOrdinal)
	local slot = session.Configuration.Slots[slotId]
	if not slot then return nil, "unknown Pool Foam slot " .. tostring(slotId) end
	local spawnCFrame = CFrame.new(spawnPosition)
	local ok, model = pcall(function()
		return session.ProxyFactory.Create(slotId, session.RuntimeFolder, {
			CFrame = spawnCFrame,
			Pivot = spawnCFrame,
			Name = "Level 2 Pool Foam " .. id,
			AssetsFolder = session.AssetsFolder,
		})
	end)
	if not ok or not (model and model:IsA("Model") and model.PrimaryPart) then
		return nil, ("Proxy Factory could not create %s: %s"):format(id, tostring(model))
	end
	local entity = {
		Session = session,
		Id = id,
		SlotId = slotId,
		Slot = slot,
		HallIndex = hallIndex,
		SpawnOrdinal = spawnOrdinal,
		Model = model,
		Animation = nil,
		AnimationPaused = false,
		Navigator = nil,
		Observed = false,
		RawObserved = false,
		LastSeenAt = nil,
		Observers = {},
		ObservedSince = nil,
		RevealUntil = 0,
		NextGoalAt = 0,
		NextTrailAt = 0,
		PatrolPosition = nil,
		Target = nil,
		WasMoving = false,
		Reached = false,
		NoProgressFor = 0,
		RepathAttempts = 0,
		StationaryFor = 0,
		ProgressAnchor = spawnPosition,
		ProgressGoal = nil,
		ProgressGoalDistance = math.huge,
		ProgressTarget = nil,
		UnreachableUntil = {},
		ActionSerial = 0,
	}
	configureModel(session, entity, model)
	entity.Animation = createAnimation(session, model, slotId)
	entity.Navigator = session.Navigator.new(model, session.Manifest, session.Configuration.Movement, {
		RuntimeFolder = session.RuntimeFolder,
	})
	if not entity.Navigator:WarpTo(spawnPosition, nil, true) then
		entity.Navigator:Destroy()
		pcall(function() session.ProxyFactory.Destroy(model) end)
		return nil, "Pool Foam spawn has no validated floor: " .. id
	end
	setEntityAnimation(entity, "Idle", true)
	return entity
end

local function eligibleRecipients(session)
	local result = {}
	for _, player in ipairs(Players:GetPlayers()) do
		if sessionAlive(session)
			and player:GetAttribute("InRound") == true
			and player:GetAttribute("Escaped") ~= true
		then
			table.insert(result, player)
		end
	end
	return result
end

local function fireClientEvent(session, kind, fields, targetPlayer)
	if not sessionAlive(session) or not session.ClientEvent then return end
	session.EventSerial += 1
	local payload = {
		Protocol = PROTOCOL,
		Generation = session.Generation,
		Serial = session.EventSerial,
		Kind = kind,
		Type = CLIENT_EVENT_TYPE[kind] or kind,
		Phase = session.Phase,
	}
	for key, value in pairs(fields or {}) do payload[key] = value end
	if targetPlayer then
		if targetPlayer.Parent == Players then session.ClientEvent:FireClient(targetPlayer, payload) end
		return
	end
	for _, player in ipairs(eligibleRecipients(session)) do session.ClientEvent:FireClient(player, payload) end
end

local function createEffectPart(session, name, position, size, color, transparency, tag, lifetime)
	if not sessionAlive(session) or not session.RuntimeFolder.Parent then return nil end
	local part = Instance.new("Part")
	part.Name = name
	part.Shape = Enum.PartType.Ball
	part.Size = size
	part.CFrame = CFrame.new(position)
	part.Color = color
	part.Material = Enum.Material.SmoothPlastic
	part.Transparency = transparency
	part.Anchored = true
	part.CanCollide = false
	part.CanTouch = false
	part.CanQuery = false
	part.CastShadow = false
	part:SetAttribute("Level2_Generation", session.Generation)
	part.Parent = session.RuntimeFolder
	CollectionService:AddTag(part, tag)
	Debris:AddItem(part, lifetime)
	return part
end

local function createTrail(session, entity, position)
	local color = entity.Id == "Primary" and Color3.fromRGB(156, 220, 220) or Color3.fromRGB(213, 239, 228)
	createEffectPart(session, "Level 2 Foam Trail", position + Vector3.new(0, 0.12, 0),
		Vector3.new(1.8, 0.22, 1.8), color, 0.34, TRAIL_TAG, 5)
end

local function createDecoy(session, entity)
	if #session.Nodes == 0 then return end
	local node = session.Nodes[session.Random:NextInteger(1, #session.Nodes)]
	local observed = session.Observer:IsPositionObserved(node.Position, 2)
	if observed then return end
	local color = entity.Id == "Primary" and Color3.fromRGB(128, 202, 207) or Color3.fromRGB(201, 232, 217)
	local base = createEffectPart(session, "Level 2 Foam Decoy", node.Position + Vector3.new(0, 1.6, 0),
		Vector3.new(2.5, 3.2, 2.5), color, 0.16, DECOY_TAG, 8)
	if base then
		base:SetAttribute("Level2_PoolFoamDecoyFor", entity.Id)
	end
end

local function phaseRecord(session, phase)
	local record = session.Configuration.Phases and session.Configuration.Phases[phase]
	return typeof(record) == "table" and record or {}
end

local function desiredPhase(session, now)
	if session.ForcedPhase then return session.ForcedPhase end
	local pumps = math.max(0, math.floor(tonumber(workspace:GetAttribute("Level2Pumps")) or 0))
	local goal = math.max(3, math.floor(tonumber(workspace:GetAttribute("Level2PumpGoal")) or 3))
	-- The exit/final-pump transition is intentionally authoritative rather than
	-- data-driven: the encounter must not enter its finale before the objective
	-- is actually completable.
	if workspace:GetAttribute("Level2ExitPowered") == true or pumps >= goal then return PHASES.Finale end

	-- Once players have started the objective, resolve non-finale phases from
	-- the authored order and thresholds. This keeps a one-pump round in
	-- Foreshadow and unlocks Pressure at its configured minimum instead of
	-- skipping straight to Pressure.
	if pumps > 0 then
		local selected = PHASES.Dormant
		local order = session.Configuration.PhaseOrder
		if typeof(order) == "table" then
			for _, phase in ipairs(order) do
				if PHASES[phase] and phase ~= PHASES.Finale then
					local minimum = math.max(0, math.floor(numberOr(phaseRecord(session, phase).MinimumPumps, 0, 0, 99)))
					if pumps >= minimum then selected = phase end
				end
			end
		end
		return selected
	end

	-- Preserve the opening wake-up: before any pump has been restored, the
	-- statues may enter Foreshadow only after the configured delay.
	local wakeDelay = numberOr(session.Configuration.WakeDelaySeconds, 15, 0, 300)
	if session.RoundStartedAt and now - session.RoundStartedAt >= wakeDelay then return PHASES.Foreshadow end
	return PHASES.Dormant
end

local function setPhase(session, phase, now)
	if session.Phase == phase then return end
	session.Phase = phase
	session.PhaseChangedAt = now
	setShared("Level2_PoolFoamPhase", phase)
	fireClientEvent(session, "Phase", {Duration = 1.5, Pumps = session.Pumps})
	for _, entity in ipairs(session.Entities) do
		entity.Navigator:Stop()
		entity.NextGoalAt = 0
		if phase == PHASES.Dormant then
			setEntityAnimationPaused(entity, false)
			setEntityAnimation(entity, "Idle")
		elseif entity.Observed then
			setEntityAnimationPaused(entity, true)
		else
			setEntityAnimationPaused(entity, false)
		end
	end
	if session.TargetedPlayer and session.TargetedPlayer.Parent == Players then
		session.TargetedPlayer:SetAttribute("Level2_PoolFoamTargeted", nil)
	end
	session.TargetedPlayer = nil
	if phase ~= PHASES.Dormant then createDecoy(session, session.Entities[1]) end
end

local function setTargeted(session, player)
	if session.TargetedPlayer == player then return end
	if session.TargetedPlayer and session.TargetedPlayer.Parent == Players then
		session.TargetedPlayer:SetAttribute("Level2_PoolFoamTargeted", nil)
	end
	session.TargetedPlayer = player
	if player and player.Parent == Players then player:SetAttribute("Level2_PoolFoamTargeted", true) end
end

local function entityLineOfSight(session, entity, character, targetPosition)
	local origin = entity.Model:GetPivot().Position + Vector3.new(0, 1.8, 0)
	local offset = targetPosition - origin
	if offset.Magnitude < 0.05 then return true end
	local params = RaycastParams.new()
	params.FilterType = Enum.RaycastFilterType.Exclude
	params.IgnoreWater = true
	local exclusions = {entity.Model}
	if session.Manifest.EntityNodes then table.insert(exclusions, session.Manifest.EntityNodes) end
	local navigation = session.Manifest.World:FindFirstChild("Level 2 Navigation", true)
	if navigation then table.insert(exclusions, navigation) end
	params.FilterDescendantsInstances = exclusions
	local result = workspace:Raycast(origin, offset, params)
	return result == nil or result.Instance:IsDescendantOf(character)
end

local function bestTarget(session, entity, now)
	local bestPlayer, bestRoot, bestDistance
	bestDistance = math.huge
	for _, player in ipairs(Players:GetPlayers()) do
		local root = livingPlayer(session, player)
		-- The opening statue trick is confined to the Kids Area. Once a pump is
		-- online, the active entity may stalk through the connected complex.
		local blockedUntil = entity.UnreachableUntil[player] or 0
		if blockedUntil <= now then entity.UnreachableUntil[player] = nil end
		if root and now >= blockedUntil
			and (session.Pumps >= 1 or positionInKids(session, root.Position)) then
			local distance = (root.Position - entity.Navigator:GetPosition()).Magnitude
			if distance < bestDistance then
				bestPlayer, bestRoot, bestDistance = player, root, distance
			end
		end
	end
	return bestPlayer, bestRoot, bestDistance
end

local function usesHuntPace(session)
	local pumps = session.Pumps
	local record = phaseRecord(session, session.Phase)
	local debugUnlock = session.ForcedPhase == PHASES.Pressure or session.ForcedPhase == PHASES.Finale
	return (pumps >= 2 or debugUnlock)
		and session.Phase ~= PHASES.Dormant
		and record.AllowAttacks ~= false
end

local function instantKill(session, entity, player, distance, now)
	local movement = session.Configuration.Movement or {}
	local killDistance = numberOr(movement.KillDistance, 5.5, 1, 20)
	if distance > killDistance then return false end
	-- Looking at the creature remains a reliable defense. The half-second
	-- caught-moving overrun is a visual scare, never a hidden lethal wind-up.
	if entity.Observed or now < entity.RevealUntil then return false end

	-- Revalidate at the instant of contact. This makes a death authoritative,
	-- prevents stale/dead/spectating targets, and blocks kills through walls.
	local liveRoot, humanoid, character = livingPlayer(session, player)
	if not liveRoot or not humanoid or not character then return false end
	local freshDistance = (liveRoot.Position - entity.Navigator:GetPosition()).Magnitude
	if freshDistance > killDistance then return false end
	if not entityLineOfSight(session, entity, character, liveRoot.Position) then return false end

	entity.ActionSerial += 1
	local attackId = tostring(session.Generation) .. ":" .. entity.Id .. ":" .. tostring(entity.ActionSerial)
	entity.Navigator:Stop()
	entity.Navigator:Face(liveRoot.Position)
	setEntityAnimation(entity, "Walk")
	setEntityAnimationPaused(entity, true)
	setModelAttribute(entity.Model,
		(session.Configuration.Attributes or {}).ActionSerial or "ActionSerial", entity.ActionSerial)
	setTargeted(session, player)
	fireClientEvent(session, "AttackHit", {
		EntityId = entity.Id,
		Slot = entity.SlotId,
		TargetUserId = player.UserId,
		AttackId = attackId,
		Position = liveRoot.Position,
		Damage = humanoid.Health,
		InstantKill = true,
		Duration = 0.65,
		AudioState = "Attack",
	}, player)

	-- Direct health assignment is intentional: contact is lethal even through a
	-- spawn ForceField, and setting zero immediately prevents duplicate targeting.
	humanoid.Health = 0
	setTargeted(session, nil)
	return true
end

local function updateObservation(session, entity, now)
	local rawObserved, players = session.Observer:IsModelObserved(entity.Model)
	local wasObserved = entity.Observed
	local observation = session.Configuration.Observation or {}
	local releaseSeconds = numberOr(observation.ReleaseSeconds, 0.24, 0, 1)
	entity.RawObserved = rawObserved
	if rawObserved then
		entity.LastSeenAt = now
		entity.Observed = true
	elseif wasObserved and entity.LastSeenAt and now - entity.LastSeenAt < releaseSeconds then
		-- A short release hold prevents screen-edge/report jitter from repeatedly
		-- granting a fresh half-second movement reveal.
		entity.Observed = true
	else
		entity.Observed = false
	end

	if rawObserved then
		entity.Observers = {}
		for _, player in ipairs(players) do table.insert(entity.Observers, player.UserId) end
	elseif not entity.Observed then
		entity.Observers = {}
	end
	setModelAttribute(entity.Model, "Level2_PoolFoamObserved", entity.Observed)
	if entity.Observed then
		entity.ObservedSince = entity.ObservedSince or now
		if not wasObserved then
			if entity.WasMoving then
				local duration = numberOr(observation.RevealOverrunSeconds, 0.5, 0, 0.75)
				entity.RevealUntil = now + duration
				local revealFields = {
					EntityId = entity.Id,
					Slot = entity.SlotId,
					Position = entity.Navigator:GetPosition(),
					Duration = duration,
					AudioState = "Caught",
				}
				for _, observerPlayer in ipairs(players) do
					fireClientEvent(session, "RevealOverrun", revealFields, observerPlayer)
				end
			else
				entity.RevealUntil = now
			end
		end
	else
		entity.LastSeenAt = nil
		entity.ObservedSince = nil
		entity.RevealUntil = 0
	end
end

local function choosePatrolPosition(session, entity)
	local current = entity.Navigator:GetPosition()
	local candidates = {}
	local localCandidates = {}
	local _, currentHallIndex = entity.Navigator:FindHall(current)
	for _, node in ipairs(session.Nodes) do
		if (node.Position - current).Magnitude > 7
			and (not entity.PatrolPosition or (node.Position - entity.PatrolPosition).Magnitude > 1)
		then
			table.insert(candidates, node.Position)
			if node.HallIndex == currentHallIndex then
				table.insert(localCandidates, node.Position)
			end
		end
	end
	if #localCandidates > 0 then candidates = localCandidates end
	if #candidates == 0 then
		for _, hall in ipairs(session.KidsHalls) do table.insert(candidates, hallCenter(hall)) end
	end
	if #candidates == 0 then return current end
	return candidates[session.Random:NextInteger(1, #candidates)]
end

local function activeCount(session)
	local record = phaseRecord(session, session.Phase)
	local total = #session.Entities
	return math.clamp(math.floor(numberOr(record.MaximumActive, total, 0, total)), 0, total)
end

local function entityIsActive(session, entity)
	return entity.SpawnOrdinal <= activeCount(session)
end

local function movementSpeed(session, hunting)
	local movement = session.Configuration.Movement or {}
	local speeds = movement.Speeds or {}
	local base = hunting and numberOr(speeds.Hunt, 3.0, 0, 40) or numberOr(speeds.Stalk, 3.0, 0, 30)
	local multiplier = numberOr(phaseRecord(session, session.Phase).SpeedMultiplier, 1, 0, 3)
	return base * multiplier
end

local function resetProgressWindow(entity, position, goal, resetAttempts)
	entity.NoProgressFor = 0
	entity.ProgressAnchor = position
	entity.ProgressGoal = goal
	entity.ProgressGoalDistance = goal and (goal - position).Magnitude or math.huge
	if resetAttempts ~= false then entity.RepathAttempts = 0 end
end

local function updateEntity(session, entity, deltaTime, now)
	local active = entityIsActive(session, entity)
	setModelAttribute(entity.Model, "Level2_PoolFoamActiveMover", active)
	if not active or session.Phase == PHASES.Dormant then
		entity.Navigator:Stop()
		entity.WasMoving = false
		entity.StationaryFor = 0
		resetProgressWindow(entity, entity.Navigator:GetPosition(), nil, true)
		if entity.Observed then
			setEntityAnimationPaused(entity, true)
		else
			setEntityAnimationPaused(entity, false)
			setEntityAnimation(entity, "Idle")
		end
		return
	end
	if entity.Observed and now >= entity.RevealUntil then
		-- Do not stop the navigator or change animation state. Holding the active
		-- track at speed zero preserves both its route and exact caught pose.
		entity.WasMoving = false
		setEntityAnimationPaused(entity, true)
		return
	end

	local player, root, distance = bestTarget(session, entity, now)
	local pursuing = player ~= nil
	if entity.ProgressTarget ~= player then
		entity.ProgressTarget = player
		resetProgressWindow(entity, entity.Navigator:GetPosition(), entity.Navigator:GetGoal(), true)
	end
	entity.Target = pursuing and player or nil
	if pursuing and instantKill(session, entity, player, distance, now) then
		entity.WasMoving = false
		return
	end
	local hunting = pursuing and usesHuntPace(session)
	local stopDistance = numberOr((session.Configuration.Movement or {}).TargetStopDistance, 4.5, 1, 20)
	if pursuing and distance <= stopDistance then
		entity.Navigator:Stop()
		entity.WasMoving = false
		entity.StationaryFor = 0
		resetProgressWindow(entity, entity.Navigator:GetPosition(), nil, true)
		setEntityAnimation(entity, "Idle")
		setEntityAnimationPaused(entity, false)
		return
	end
	if now >= entity.NextGoalAt then
		entity.NextGoalAt = now + numberOr((session.Configuration.Movement or {}).UpdateInterval, 0.1, 0.05, 1)
		if pursuing then
			entity.Navigator:SetGoal(root.Position)
		else
			if not entity.PatrolPosition or entity.Reached then entity.PatrolPosition = choosePatrolPosition(session, entity) end
			entity.Navigator:SetGoal(entity.PatrolPosition, entity.Reached)
		end
	end

	local before = entity.Navigator:GetPosition()
	entity.Reached = entity.Navigator:Step(deltaTime, movementSpeed(session, hunting))
	local after = entity.Navigator:GetPosition()
	entity.WasMoving = (after - before).Magnitude > 0.002
	if entity.WasMoving then
		entity.StationaryFor = 0
		-- One authored locomotion clip drives every moving phase; the Hunt state
		-- resolves to the same Walk track at its faster authored playback (and
		-- the hunt proxy tint) without a stop/restart pose snap.
		setEntityAnimation(entity, hunting and "Hunt" or "Walk")
		setEntityAnimationPaused(entity, false)
		if now >= entity.NextTrailAt then
			entity.NextTrailAt = now + 0.7
			createTrail(session, entity, before)
		end
	else
		entity.StationaryFor += deltaTime
		-- Step consumes reached intermediate waypoints in the same frame, so any
		-- remaining zero-motion frame is genuine waiting/blockage and must be Idle.
		setEntityAnimation(entity, "Idle")
		setEntityAnimationPaused(entity, false)
	end

	local currentGoal = entity.Navigator:GetGoal()
	if entity.Reached or not currentGoal then
		resetProgressWindow(entity, after, nil, true)
	else
		if not entity.ProgressGoal or (currentGoal - entity.ProgressGoal).Magnitude > 1 then
			resetProgressWindow(entity, after, currentGoal, true)
		end
		entity.NoProgressFor += deltaTime
		local movement = session.Configuration.Movement or {}
		local stuckSeconds = numberOr(movement.StuckRepathSeconds, 1.1, 0.35, 8)
		if entity.NoProgressFor >= stuckSeconds then
			local netTravel = (after - entity.ProgressAnchor).Magnitude
			local currentDistance = (currentGoal - after).Magnitude
			local goalProgress = entity.ProgressGoalDistance - currentDistance
			if netTravel >= .5 or goalProgress >= .35 then
				entity.RepathAttempts = 0
			else
				entity.RepathAttempts += 1
				if entity.RepathAttempts == 1 then
					entity.Navigator:SetGoal(currentGoal, true)
				else
					if pursuing and player then
						local cooldown = numberOr(movement.UnreachableTargetCooldown, 3, 0.5, 30)
						entity.UnreachableUntil[player] = now + cooldown
						entity.Target = nil
						entity.ProgressTarget = nil
					end
					entity.PatrolPosition = choosePatrolPosition(session, entity)
					entity.Navigator:SetGoal(entity.PatrolPosition, true)
					entity.RepathAttempts = 0
					entity.NextGoalAt = now + numberOr(movement.UpdateInterval, 0.1, 0.05, 1)
				end
			end
			local trackedGoal = entity.Navigator:GetGoal()
			resetProgressWindow(entity, after, trackedGoal, false)
		end
	end
end

local function refreshTemplate(session, entity)
	if not session.ProxyFactory.IsTemporaryProxy(entity.Model) then return end
	local template = session.ProxyFactory.ResolveTemplate(entity.SlotId, session.AssetsFolder)
	if not template then return end
	local oldModel = entity.Model
	local oldNavigator = entity.Navigator
	local oldAnimation = entity.Animation
	local oldFoot = oldNavigator:GetPosition()
	local oldFacing = oldNavigator:GetFacing()
	local oldGoal = oldNavigator:GetGoal()
	local pivot = oldModel:GetPivot()
	local ok, replacement = pcall(function()
		return session.ProxyFactory.Create(entity.SlotId, session.RuntimeFolder, {
			CFrame = pivot,
			Pivot = pivot,
			Name = entity.Model.Name,
			AssetsFolder = session.AssetsFolder,
		})
	end)
	if not ok or not (replacement and replacement:IsA("Model") and replacement.PrimaryPart) then
		warn("[Pool Foam] final template refresh failed for " .. entity.Id .. ": " .. tostring(replacement))
		return
	end
	if session.ProxyFactory.IsTemporaryProxy(replacement) then
		pcall(function() session.ProxyFactory.Destroy(replacement) end)
		warn("[Pool Foam] resolved template remained invalid for " .. entity.Id)
		return
	end
	configureModel(session, entity, replacement)
	local replacementAnimation = createAnimation(session, replacement, entity.SlotId)
	local replacementNavigator = session.Navigator.new(replacement, session.Manifest, session.Configuration.Movement, {
		RuntimeFolder = session.RuntimeFolder,
	})
	if not replacementNavigator:WarpTo(oldFoot, oldFacing) then
		replacementNavigator:Destroy()
		if replacementAnimation then pcall(function() replacementAnimation:Destroy() end) end
		pcall(function() session.ProxyFactory.Destroy(replacement) end)
		warn("[Pool Foam] final template has no validated floor for " .. entity.Id)
		return
	end
	if oldGoal then replacementNavigator:SetGoal(oldGoal, true) end

	entity.Model = replacement
	entity.Navigator = replacementNavigator
	entity.Animation = replacementAnimation
	entity.AnimationPaused = false
	entity.StationaryFor = 0
	resetProgressWindow(entity, replacementNavigator:GetPosition(), oldGoal, true)
	oldNavigator:Destroy()
	if oldAnimation then pcall(function() oldAnimation:Destroy() end) end
	pcall(function() session.ProxyFactory.Destroy(oldModel) end)
	setEntityAnimation(entity, entity.Observed and "Walk" or "Idle", true)
	setEntityAnimationPaused(entity, entity.Observed)
	fireClientEvent(session, "TemplateResolved", {
		EntityId = entity.Id,
		Slot = entity.SlotId,
		Position = replacement:GetPivot().Position,
		Duration = 0,
		Caption = false,
	})
end

local function updateSession(session, deltaTime)
	if not sessionAlive(session) then Controller.Stop() return end
	local now = os.clock()
	if not roundReady(session) then
		for _, entity in ipairs(session.Entities) do
			entity.WasMoving = false
			entity.Navigator:Stop()
			setEntityAnimationPaused(entity, true)
		end
		return
	end
	if workspace:GetAttribute("EntityPaused") == true then
		for _, entity in ipairs(session.Entities) do
			entity.WasMoving = false
			entity.Navigator:Stop()
			setEntityAnimationPaused(entity, true)
		end
		return
	end
	if not session.RoundStartedAt then session.RoundStartedAt = now end
	session.Pumps = math.max(0, math.floor(tonumber(workspace:GetAttribute("Level2Pumps")) or 0))
	setPhase(session, desiredPhase(session, now), now)

	session.ObservationAccumulator += deltaTime
	local observationInterval = numberOr((session.Configuration.Movement or {}).UpdateInterval, 0.1, 0.05, 0.5)
	if session.ObservationAccumulator >= observationInterval then
		session.ObservationAccumulator = 0
		for _, entity in ipairs(session.Entities) do updateObservation(session, entity, now) end
	end
	for _, entity in ipairs(session.Entities) do updateEntity(session, entity, math.min(deltaTime, 0.1), now) end

	if now >= session.NextTemplateRefreshAt then
		session.NextTemplateRefreshAt = now + 3
		for _, entity in ipairs(session.Entities) do refreshTemplate(session, entity) end
	end
end

function Controller.Start(manifest, generation)
	Controller.Stop()
	-- A pause is a session-local debug control. Never carry it into a newly
	-- generated Level 2 round.
	workspace:SetAttribute("EntityPaused", false)
	local configuration, configurationError = loadSibling(MODULE_CONFIGURATION, true)
	if not configuration then publishStopped("ConfigurationError") return nil, configurationError end
	syncAudioLibrary(configuration)
	local enabled = configuration.Enabled == true
		or (RunService:IsStudio() and workspace:GetAttribute("TestLevel2PoolFoamEnabled") == true)
	if not enabled then publishStopped("Disabled") return nil, "Pool Foam is disabled by configuration" end
	if not (manifest and manifest.World and typeof(manifest.Layout) == "table") then
		publishStopped("ManifestError")
		return nil, "Pool Foam requires manifest.World and manifest.Layout"
	end
	if not finiteNumber(generation) then
		publishStopped("GenerationError")
		return nil, "Pool Foam requires a numeric generation"
	end
	local kidsHalls, allowedHalls, hallIds = normalizeKidsArea(manifest.Layout)
	if #kidsHalls < 1 then
		publishStopped("KidsAreaError")
		return nil, "Pool Foam requires at least one Layout.KidsArea hall"
	end

	local proxyFactory, proxyError = loadSibling(MODULE_PROXY_FACTORY, true)
	local navigator, navigatorError = loadSibling(MODULE_NAVIGATOR, true)
	local observerModule, observerError = loadSibling(MODULE_OBSERVER, true)
	if not proxyFactory then publishStopped("ProxyError") return nil, proxyError end
	if not navigator then publishStopped("NavigatorError") return nil, navigatorError end
	if not observerModule then publishStopped("ObserverError") return nil, observerError end
	if typeof(proxyFactory.Create) ~= "function" or typeof(proxyFactory.Destroy) ~= "function"
		or typeof(proxyFactory.IsTemporaryProxy) ~= "function" or typeof(proxyFactory.ResolveTemplate) ~= "function"
	then
		publishStopped("ProxyAPIError")
		return nil, "Pool Foam Proxy Factory API is incomplete"
	end
	local animationAdapter = select(1, loadSibling(MODULE_ANIMATION_ADAPTER, false))

	local existing = manifest.World:FindFirstChild(configuration.RuntimeFolderName)
	if existing then
		warn("[Pool Foam] removing stale session runtime " .. existing:GetFullName())
		existing:Destroy()
	end
	local runtimeFolder = Instance.new("Folder")
	runtimeFolder.Name = configuration.RuntimeFolderName
	runtimeFolder:SetAttribute("Level2_Generation", generation)
	runtimeFolder.Parent = manifest.World

	local remoteFolder, _, clientEvent, remoteError = observerModule.EnsureRemotes()
	if not remoteFolder then
		runtimeFolder:Destroy()
		publishStopped("RemoteError")
		return nil, remoteError
	end
	local observerOk, observer = pcall(function()
		return observerModule.new(manifest, generation, configuration.Observation)
	end)
	if not observerOk then
		runtimeFolder:Destroy()
		publishStopped("ObserverError")
		warn("[Pool Foam] observer failed to start: " .. tostring(observer))
		return nil, tostring(observer)
	end

	local seed = math.floor(tonumber(manifest.Layout.Seed) or 1)
	local session = {
		Manifest = manifest,
		Generation = generation,
		Configuration = configuration,
		ProxyFactory = proxyFactory,
		AnimationAdapter = animationAdapter,
		Navigator = navigator,
		Observer = observer,
		ClientEvent = clientEvent,
		RuntimeFolder = runtimeFolder,
		AssetsFolder = ServerStorage:FindFirstChild(configuration.AssetFolderName),
		KidsHalls = kidsHalls,
		AllowedHalls = allowedHalls,
		Nodes = collectNodes(manifest, hallIds, allowedHalls),
		Entities = {},
		EntityById = {},
		Connections = {},
		Random = Random.new((seed + generation * 7919) % 2147483647),
		Phase = PHASES.Dormant,
		PhaseChangedAt = os.clock(),
		ForcedPhase = nil,
		Pumps = math.max(0, math.floor(tonumber(workspace:GetAttribute("Level2Pumps")) or 0)),
		RoundStartedAt = nil,
		ActiveMoverId = "ALL",
		NextTemplateRefreshAt = os.clock() + 1,
		-- Force a visibility pass before the first movement step.
		ObservationAccumulator = 1,
		EventSerial = 0,
		TargetedPlayer = nil,
	}
	activeSession = session

	-- Every generated Kids Area owns one distinct runtime identity, while every
	-- clone resolves art and animation through the single Primary asset slot.
	for ordinal, hall in ipairs(kidsHalls) do
		local entityId = string.format("Primary_%02d", ordinal)
		local spawnPosition = positionForHall(session, hall)
		local entity, createError = createEntity(session, entityId, "Primary",
			spawnPosition, tonumber(hall.Index), ordinal)
		if not entity then
			warn("[Pool Foam] " .. tostring(createError))
			Controller.Stop()
			publishStopped("CreateError")
			return nil, createError
		end
		table.insert(session.Entities, entity)
		session.EntityById[entity.Id] = entity
	end

	setShared("Level2_PoolFoamActive", true)
	setShared("Level2_PoolFoamGeneration", generation)
	setShared("Level2_PoolFoamPhase", session.Phase)
	setShared("Level2_PoolFoamActiveMover", session.ActiveMoverId)
	table.insert(session.Connections, RunService.Heartbeat:Connect(function(deltaTime)
		updateSession(session, deltaTime)
	end))
	table.insert(session.Connections, Players.PlayerRemoving:Connect(function(player)
		if session.TargetedPlayer == player then session.TargetedPlayer = nil end
	end))
	fireClientEvent(session, "Started", {Duration = 0, EntityCount = #session.Entities})
	return session
end

function Controller.Stop()
	-- A stopped session must not leave the next encounter permanently paused.
	workspace:SetAttribute("EntityPaused", false)
	local session = activeSession
	if not session then publishStopped("Stopped") return end
	activeSession = nil
	if session.TargetedPlayer and session.TargetedPlayer.Parent == Players then
		session.TargetedPlayer:SetAttribute("Level2_PoolFoamTargeted", nil)
	end
	for _, player in ipairs(Players:GetPlayers()) do
		if player:GetAttribute("Level2_PoolFoamTargeted") ~= nil then
			player:SetAttribute("Level2_PoolFoamTargeted", nil)
		end
	end
	for _, connection in ipairs(session.Connections) do connection:Disconnect() end
	for _, entity in ipairs(session.Entities) do
		if entity.Navigator then entity.Navigator:Destroy() end
		if entity.Animation then pcall(function() entity.Animation:Destroy() end) end
	end
	if session.Observer then session.Observer:Destroy() end
	if session.RuntimeFolder and session.RuntimeFolder.Parent then session.RuntimeFolder:Destroy() end
	publishStopped("Stopped")
end

function Controller.IsRunning()
	return activeSession ~= nil and sessionAlive(activeSession)
end

function Controller.SetPaused(value)
	workspace:SetAttribute("EntityPaused", value == true)
	return true
end

function Controller.ForcePhase(phase)
	local session = activeSession
	if not session then return false, "Pool Foam is not running" end
	if phase == nil or phase == "" then
		session.ForcedPhase = nil
		return true
	end
	if not PHASES[phase] then return false, "phase must be Dormant, Foreshadow, Pressure, Finale, or nil" end
	session.ForcedPhase = phase
	setPhase(session, phase, os.clock())
	return true
end

function Controller.GetDebugSnapshot()
	local session = activeSession
	if not session then return {Running = false} end
	local entities = {}
	for _, entity in ipairs(session.Entities) do
		local navigator = entity.Navigator:GetDebugSnapshot()
		navigator.Position = vectorTable(navigator.Position)
		navigator.Goal = vectorTable(navigator.Goal)
		table.insert(entities, {
			Id = entity.Id,
			Position = vectorTable(entity.Navigator:GetPosition()),
			Observed = entity.Observed,
			Observers = table.clone(entity.Observers),
			Active = entityIsActive(session, entity),
			Moving = entity.WasMoving,
			NoProgressFor = entity.NoProgressFor,
			RepathAttempts = entity.RepathAttempts,
			RevealRemaining = math.max(0, entity.RevealUntil - os.clock()),
			Navigator = navigator,
			TemporaryProxy = session.ProxyFactory.IsTemporaryProxy(entity.Model),
		})
	end
	return {
		Running = sessionAlive(session),
		Generation = session.Generation,
		Phase = session.Phase,
		ForcedPhase = session.ForcedPhase,
		Pumps = session.Pumps,
		Elapsed = session.RoundStartedAt and os.clock() - session.RoundStartedAt or 0,
		Paused = workspace:GetAttribute("EntityPaused") == true,
		ActiveMoverId = session.ActiveMoverId,
		Entities = entities,
		Observer = session.Observer:GetDebugSnapshot(),
	}
end

Controller.Protocol = PROTOCOL
Controller.Phases = PHASES

return Controller
