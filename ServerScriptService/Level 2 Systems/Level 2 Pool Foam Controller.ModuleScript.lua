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
local ServerScriptService = game:GetService("ServerScriptService")
local ServerStorage = game:GetService("ServerStorage")
local PlayerProtection = require(ServerScriptService:WaitForChild("PlayerProtection"))
local DeathAdvice = require(ReplicatedStorage:WaitForChild("DeathAdvice"))

-- Hearing. NoiseRegistry lives in the ServerScriptService ROOT, not in this
-- folder, so it is reached through the service (script.Parent is "Level 2
-- Systems"). A missing or broken module must not stop the encounter: the stub
-- simply leaves Pool Foam deaf, exactly like EntityAI's own fallback.
local NoiseRegistry
do
	local ok, result = pcall(function()
		return require(ServerScriptService:WaitForChild("NoiseRegistry", 10))
	end)
	if ok and type(result) == "table" and result.Add then
		NoiseRegistry = result
	else
		warn("[Pool Foam] NoiseRegistry unavailable; hearing disabled: " .. tostring(result))
		NoiseRegistry = {
			Add = function() end,
			Prune = function() end,
			Clear = function() end,
			GetBest = function() return nil end,
		}
	end
end

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

-- The only noise names a CLIENT may claim, exactly as EntityAI whitelists them
-- for Level 1. Everything else in NoiseRegistry's vocabulary (a fuse relay, a
-- pump motor) is server-authored and must not be spoofable from a report.
local CLIENT_NOISE = table.freeze({walk = true, sprint = true})

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
	-- Separation diagnostics are per round; a stopped encounter must not leave
	-- the previous round's numbers on the state folder for the next one to read.
	setShared("Level2_PoolFoamMinSeparation", 0)
	setShared("Level2_PoolFoamOverlapFrames", 0)
	setShared("Level2_PoolFoamYieldCount", 0)
	setShared("Level2_PoolFoamSeparationMs", 0)
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
	if PlayerProtection.IsActive(player, character) then return nil end
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

-- SEPARATION TUNING BEGIN: the two readers every separation caller shares.
local function separationTuning(configuration)
	local tuning = configuration and configuration.Separation
	return typeof(tuning) == "table" and tuning or {}
end

-- The no-overlap radius of ONE model, measured from the model itself: half the
-- larger horizontal extent of its bounding box. The shipped Bloom proxy answers
-- 3.75 (its root is 7.5 x 4.8 x 6.5); a final template answers its own size, so
-- no radius is ever invented here.
local function separationRadius(configuration, model)
	local tuning = separationTuning(configuration)
	local minimum = numberOr(tuning.MinimumRadius, 1, 0.25, 16)
	local maximum = numberOr(tuning.MaximumRadius, 8, minimum, 32)
	local fallback = math.clamp(numberOr(tuning.FallbackRadius, 3.75, 0.25, 32), minimum, maximum)
	local ok, size = pcall(function() return select(2, model:GetBoundingBox()) end)
	if not ok or typeof(size) ~= "Vector3" then return fallback end
	local radius = math.max(size.X, size.Z) * 0.5
	if not finiteNumber(radius) or radius <= 0 then return fallback end
	return math.clamp(radius, minimum, maximum)
end
-- SEPARATION TUNING END

local function positionForHall(session, hall, used)
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
	-- SPAWN SPACING. Five clones that start inside each other are already
	-- overlapping before the first Heartbeat, and two Kids Areas can offer
	-- neighbouring nodes. The candidate list is already sorted by node name, so
	-- taking the FIRST entry that clears every spawn placed so far keeps the old
	-- deterministic choice whenever it is legal, and only moves when it is not.
	-- Nothing is invented: if no candidate clears the gap the roomiest real node
	-- wins, because an unvalidated position fails the navigator's floor check and
	-- takes the whole encounter down with it.
	local gap = numberOr(separationTuning(session.Configuration).SpawnGap, 9, 0, 120)
	local roomiest, roomiestClearance
	for _, node in ipairs(candidates) do
		local clearance = math.huge
		for _, taken in ipairs(used or {}) do
			clearance = math.min(clearance, (node.Position - taken).Magnitude)
		end
		if clearance >= gap then return node.Position end
		if roomiestClearance == nil or clearance > roomiestClearance then
			roomiest, roomiestClearance = node.Position, clearance
		end
	end
	if roomiest then return roomiest end
	return hallCenter(hall) + Vector3.new(0, 2, 0)
end

local function setModelAttribute(model, name, value)
	if typeof(name) == "string" and name ~= "" and model:GetAttribute(name) ~= value then
		model:SetAttribute(name, value)
	end
end

-- AUDIO RUNTIME BEGIN: one server-owned point source, independent of tracks.
local function normalizedAudioId(value)
	if finiteNumber(value) and value > 0 and value % 1 == 0 then value = tostring(value) end
	if typeof(value) ~= "string" then return nil end
	local digits = value:match("^rbxassetid://(%d+)$") or value:match("^(%d+)$")
	if not digits or not digits:find("[1-9]") then return nil end
	return "rbxassetid://" .. digits
end

local function destroyEntityAudio(entity)
	local audio = entity.Audio
	entity.Audio = nil
	if audio and audio.Attachment then audio.Attachment:Destroy() end
end

local function updateEntityAudio(entity)
	local configuration = entity.Session.Configuration
	local tuning = configuration.Audio or {}
	local state = entity.AudioState or "Idle"
	local ids = configuration.AudioIds and configuration.AudioIds[entity.SlotId] or {}
	local volume = tuning.LoopVolumes and tuning.LoopVolumes[state]
	local assetId = tuning.Enabled ~= false and volume ~= nil and normalizedAudioId(ids[state]) or nil
	local paused = entity.AnimationPaused == true
	local audio = entity.Audio
	if not audio then
		audio = {}
		entity.Audio = audio
	end
	local key = (assetId or "") .. ":" .. state .. ":" .. tostring(paused)
	if audio.Key == key then return end
	audio.Key = key
	-- No yields, loading waits or retries in the AI tick. Blank/invalid IDs stay
	-- silent; an unavailable permitted asset is left to the engine's loader.
	local ok, failure = pcall(function()
		local sound = audio.Sound
		if not assetId or paused then
			if sound and audio.Playing then sound:Pause() end
			audio.Playing = false
			return
		end
		if not sound then
			local root = entity.Model.PrimaryPart
			if not root then return end
			local attachment = Instance.new("Attachment")
			attachment.Name = "PoolFoamAudioEmitter"
			audio.Attachment = attachment
			attachment.Parent = root
			sound = Instance.new("Sound")
			audio.Sound = sound
			sound.Name = "PoolFoamMovement"
			sound.Looped = true
			sound.RollOffMode = Enum.RollOffMode.InverseTapered
			sound.RollOffMinDistance = numberOr(tuning.RollOffMinDistance, 12, 1, 100)
			sound.RollOffMaxDistance = numberOr(tuning.RollOffMaxDistance, 110, sound.RollOffMinDistance + 1, 500)
			sound.Parent = attachment
		end
		sound.Volume = numberOr(volume, 0, 0, 0.5)
		if sound.SoundId ~= assetId then
			sound:Stop()
			sound.SoundId = assetId
			sound:Play()
		elseif not audio.Playing then
			sound:Resume()
		end
		audio.Playing = true
	end)
	if not ok and not audio.Warned then
		audio.Warned = true
		warn("[Pool Foam] movement audio unavailable for " .. entity.Id .. ": " .. tostring(failure))
	end
end
-- AUDIO RUNTIME END

local function setEntityAnimation(entity, state, force)
	entity.AudioState = state
	updateEntityAudio(entity)
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
	updateEntityAudio(entity)
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
	setModelAttribute(model, "Level2_PoolFoamChasing", entity.ChaseTriggered == true)
	setModelAttribute(model, "Level2_PoolFoamRampFrozen", entity.SpeedRampFrozen == true)
	setModelAttribute(model, "Level2_PoolFoamChaseTargetUserId",
		entity.ChaseTarget and entity.ChaseTarget.UserId or 0)
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
		-- Measured from this model, never assumed; re-measured in refreshTemplate
		-- when the final art replaces the proxy.
		BodyRadius = separationRadius(session.Configuration, model),
		-- Mutual separation state (see updateSeparation). Every numeric field
		-- starts real so the per-frame pass compares instead of allocating.
		SeparationActive = false,
		SeparationPushX = 0,
		SeparationPushZ = 0,
		SeparationContact = nil,
		SeparationContactDistance = math.huge,
		SeparationAhead = nil,
		SeparationAheadDistance = math.huge,
		SeparationObstructing = false,
		SeparationClearance = 0,
		SeparationLane = 0,
		SeparationLaneFor = nil,
		SeparationLaneTried = false,
		SeparationHoldUntil = 0,
		SeparationYieldSince = nil,
		SeparationReleaseUntil = 0,
		Animation = nil,
		AnimationPaused = false,
		Navigator = nil,
		Observed = false,
		RawObserved = false,
		LastSeenAt = nil,
		Observers = {},
		ObservedSince = nil,
		RevealUntil = 0,
		ChaseTriggered = false,
		ChaseTriggeredAt = nil,
		ChaseGraceUntil = 0,
		ChaseTarget = nil,
		-- Server-side latch backstop: who this entity has been standing in clear
		-- view of, and since when. Independent of any client report.
		ProximityDwellPlayer = nil,
		ProximityDwellSince = 0,
		-- The loudest sound this entity can hear, refreshed once per think tick
		-- instead of once per Heartbeat per reader.
		HeardNoise = nil,
		SpeedRampBonus = 0,
		SpeedRampFrozen = false,
		LastDesiredSpeed = 0,
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

local function observationFreezes(session)
	return (session.Configuration.Observation or {}).FreezeWhileObserved == true
end

local function activeCount(session)
	local record = phaseRecord(session, session.Phase)
	local total = #session.Entities
	return math.clamp(math.floor(numberOr(record.MaximumActive, total, 0, total)), 0, total)
end

local function entityIsActive(session, entity)
	return entity.SpawnOrdinal <= activeCount(session)
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

-- WHO IS BEING HUNTED (2026-09-04).
--
-- `Level2_PoolFoamTargeted` and `BeingChased` are per-PLAYER marks, but every
-- generated Kids Area owns its own Pool Foam and each of them can hold a chase
-- target at the same time, so the marks are REFERENCE COUNTED: a player carries
-- them while ANY entity is hunting them and loses them only when the last one
-- lets go. The waiting readers are NoiseReporter (adrenaline — triple stamina
-- while chased) and EntityShakeController (camera shake).
--
-- BeingChased is cleared to false rather than nil, matching how Level 3's Mall
-- Manager and Hiding Controller release it; every reader tests `== true`.
local function markChased(session, player, delta)
	if not player then return end
	local count = math.max(0, (session.ChaseMarks[player] or 0) + delta)
	session.ChaseMarks[player] = count > 0 and count or nil
	if player.Parent ~= Players then return end
	if count > 0 then
		player:SetAttribute("Level2_PoolFoamTargeted", true)
		player:SetAttribute("BeingChased", true)
	else
		player:SetAttribute("Level2_PoolFoamTargeted", nil)
		player:SetAttribute("BeingChased", false)
	end
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
		elseif entity.Observed and observationFreezes(session) then
			setEntityAnimationPaused(entity, true)
		else
			setEntityAnimationPaused(entity, false)
		end
	end
	-- The kill marker below is a one-frame flash owned by instantKill. A player
	-- an entity is genuinely hunting holds the same attribute through the
	-- reference count, so releasing the marker must not take theirs with it.
	if session.TargetedPlayer and session.TargetedPlayer.Parent == Players
		and not session.ChaseMarks[session.TargetedPlayer] then
		session.TargetedPlayer:SetAttribute("Level2_PoolFoamTargeted", nil)
	end
	session.TargetedPlayer = nil
	if phase ~= PHASES.Dormant then createDecoy(session, session.Entities[1]) end
end

local function setTargeted(session, player)
	if session.TargetedPlayer == player then return end
	if session.TargetedPlayer and session.TargetedPlayer.Parent == Players
		and not session.ChaseMarks[session.TargetedPlayer] then
		session.TargetedPlayer:SetAttribute("Level2_PoolFoamTargeted", nil)
	end
	session.TargetedPlayer = player
	if player and player.Parent == Players then player:SetAttribute("Level2_PoolFoamTargeted", true) end
end

local function setChaseTarget(entity, player)
	if entity.ChaseTarget == player then return end
	local previous = entity.ChaseTarget
	entity.ChaseTarget = player
	setModelAttribute(entity.Model, "Level2_PoolFoamChaseTargetUserId",
		player and player.Parent == Players and player.UserId or 0)
	-- An entity only ever holds a chase target while it is actually chasing
	-- (every caller either just latched ChaseTriggered or is clearing), so this
	-- transition IS the acquire/release of the player's hunted marks.
	markChased(entity.Session, previous, -1)
	markChased(entity.Session, player, 1)
end

local function resetThreatState(entity)
	entity.ChaseTriggered = false
	entity.ChaseTriggeredAt = nil
	entity.ChaseGraceUntil = 0
	entity.ProximityDwellPlayer = nil
	entity.ProximityDwellSince = 0
	entity.SpeedRampBonus = 0
	entity.SpeedRampFrozen = false
	entity.LastDesiredSpeed = 0
	setChaseTarget(entity, nil)
	setModelAttribute(entity.Model, "Level2_PoolFoamChasing", false)
	setModelAttribute(entity.Model, "Level2_PoolFoamRampFrozen", false)
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
	-- The builder already hands the navigation folder over in the manifest. This
	-- used to be a RECURSIVE FindFirstChild over the finished world, and the
	-- world's first child is the geometry subtree that holds essentially all
	-- ~71,000 of its instances — so every blocked kill attempt walked the whole
	-- level, once per Heartbeat, for as long as the target stayed cornered. The
	-- Navigator and the Observer both read the manifest field; this was the odd
	-- one out.
	local navigation = session.Manifest.Navigation
	if navigation then table.insert(exclusions, navigation) end
	params.FilterDescendantsInstances = exclusions
	local result = workspace:Raycast(origin, offset, params)
	return result == nil or result.Instance:IsDescendantOf(character)
end

-- The loudest recent sound this entity can hear, or nil. NoiseRegistry.GetBest
-- already ranks by loudness over distance AND scales the audible range by
-- loudness, so one call answers both "is anything audible from here" and "which
-- of them is worth walking to". Entries older than the registry's decay are
-- dropped by the Prune in updateSession, so this is always recent.
local function heardNoise(session, entity)
	local hearing = session.Configuration.Hearing or {}
	if hearing.Enabled == false then return nil end
	return NoiseRegistry.GetBest(entity.Navigator:GetPosition(),
		numberOr(hearing.HearingRange, 120, 0, 600))
end

local function bestTarget(session, entity, now)
	-- A direct observer owns the chase until that player is no longer eligible or
	-- the navigator proves them temporarily unreachable. This avoids multiplayer
	-- target thrashing when two cameras cross the entity on adjacent reports.
	local preferredPlayer = entity.ChaseTriggered and entity.ChaseTarget or nil
	if preferredPlayer then
		local preferredRoot = livingPlayer(session, preferredPlayer)
		local blockedUntil = entity.UnreachableUntil[preferredPlayer] or 0
		if blockedUntil <= now then entity.UnreachableUntil[preferredPlayer] = nil end
		if preferredRoot and now >= blockedUntil
			and (session.Pumps >= 1 or positionInKids(session, preferredRoot.Position))
		then
			-- A locked chase is not a hearing decision, and this branch runs for
			-- most of a chase. Without this write the readback below would keep
			-- reporting the last full evaluation's answer — usually a stale
			-- `true` — for as long as the chase lasts.
			setModelAttribute(entity.Model, "Level2_PoolFoamHeardTarget", false)
			return preferredPlayer, preferredRoot,
				(preferredRoot.Position - entity.Navigator:GetPosition()).Magnitude
		end
		setChaseTarget(entity, nil)
	end

	-- Hearing STEERS, distance decides. A player standing where a recent noise
	-- came from counts as nearer than they are, so a sprinter or someone at a
	-- running pump is chosen over a closer, silent teammate. The true distance
	-- is what leaves this function, so stopping and killing are unaffected — and
	-- because the whole choice is remade on every think tick, a noise can never
	-- pin the entity to one player.
	local hearing = session.Configuration.Hearing or {}
	-- Refreshed once per think tick in updateSession, not recomputed here.
	-- bestTarget runs per entity on every Heartbeat, and GetBest is a linear
	-- scan with a Vector3 magnitude per entry over a list that settles around
	-- 150 sounds — six times the scanning for a value that only ever steers a
	-- goal chosen on the 0.1 s boundary.
	local noise = entity.HeardNoise
	local noiseWeight = numberOr(hearing.NoiseWeight, 0.55, 0.05, 1)
	local attribution = numberOr(hearing.AttributionRadius, 35, 0, 300)
	local heardBest = false

	local bestPlayer, bestRoot, bestDistance, bestScore
	bestDistance, bestScore = math.huge, math.huge
	for _, player in ipairs(Players:GetPlayers()) do
		local root = livingPlayer(session, player)
		-- The opening statue trick is confined to the Kids Area. Once a pump is
		-- online, the active entity may stalk through the connected complex.
		local blockedUntil = entity.UnreachableUntil[player] or 0
		if blockedUntil <= now then entity.UnreachableUntil[player] = nil end
		if root and now >= blockedUntil
			and (session.Pumps >= 1 or positionInKids(session, root.Position)) then
			local distance = (root.Position - entity.Navigator:GetPosition()).Magnitude
			local heard = noise ~= nil and (root.Position - noise.pos).Magnitude <= attribution
			local score = heard and distance * noiseWeight or distance
			if score < bestScore then
				bestPlayer, bestRoot, bestDistance, bestScore = player, root, distance, score
				heardBest = heard
			end
		end
	end
	setModelAttribute(entity.Model, "Level2_PoolFoamHeardTarget", heardBest)
	if entity.ChaseTriggered and bestPlayer then setChaseTarget(entity, bestPlayer) end
	return bestPlayer, bestRoot, bestDistance
end

local function instantKill(session, entity, player, distance, now)
	local movement = session.Configuration.Movement or {}
	local killDistance = numberOr(movement.KillDistance, 5.5, 1, 20)
	-- Before the first validated look, this is a stalking encounter: it may close
	-- distance and build speed, but the player has not triggered lethal pursuit.
	if not entity.ChaseTriggered then return false end
	-- Preserve the authored phase boundary as well. A look may reveal/latch the
	-- chase in Foreshadow, but contact only becomes lethal once attacks unlock.
	if phaseRecord(session, session.Phase).AllowAttacks == false then return false end
	if distance > killDistance then return false end
	-- A validated look starts the chase, with a short one-shot grace window so
	-- the transition is readable rather than an instant hit. With
	-- FreezeWhileObserved (the shipped rule since 2026-09-23) looking is also the
	-- defense: a watched foam never reaches this line (updateEntity returns first).
	if now < entity.ChaseGraceUntil then return false end
	if observationFreezes(session) and (entity.Observed or now < entity.RevealUntil) then return false end

	-- Revalidate at the instant of contact. This makes a death authoritative,
	-- prevents stale/dead/spectating targets, and blocks kills through walls.
	local liveRoot, humanoid, character = livingPlayer(session, player)
	if not liveRoot or not humanoid or not character then return false end
	local freshDistance = (liveRoot.Position - entity.Navigator:GetPosition()).Magnitude
	if freshDistance > killDistance then return false end
	if not entityLineOfSight(session, entity, character, liveRoot.Position) then return false end

	-- No fatal feedback or health mutation for a privately protected character.
	if PlayerProtection.IsActive(player, character) then return false end
	entity.ActionSerial += 1
	local attackId = tostring(session.Generation) .. ":" .. entity.Id .. ":" .. tostring(entity.ActionSerial)
	entity.Navigator:Stop()
	entity.Navigator:Face(liveRoot.Position)
	setEntityAnimationPaused(entity, true)
	setEntityAnimation(entity, "Walk")
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
		Volume = (session.Configuration.Audio or {}).Enabled == false and 0
			or numberOr((session.Configuration.Audio or {}).AttackVolume, 0.24, 0, 0.35),
		TargetCharacter = character,
		ServerTime = workspace:GetServerTimeNow(),
	}, player)

	-- Direct health assignment is intentional: contact is lethal even through a
	-- spawn ForceField, and setting zero immediately prevents duplicate targeting.
	DeathAdvice.Mark(player, "L2Foam")
	humanoid.Health = 0
	setTargeted(session, nil)
	return true
end

local function observedChaseTarget(session, entity, players)
	local position = entity.Navigator:GetPosition()
	local bestPlayer, bestDistance
	bestDistance = math.huge
	for _, player in ipairs(players) do
		local root = livingPlayer(session, player)
		if root then
			local separation = (root.Position - position).Magnitude
			if separation < bestDistance
				or (math.abs(separation - bestDistance) <= 0.001
					and bestPlayer and player.UserId < bestPlayer.UserId)
			then
				bestPlayer, bestDistance = player, separation
			end
		end
	end
	return bestPlayer
end

local function triggerChase(session, entity, players, now)
	local target = observedChaseTarget(session, entity, players)
	if not target then return end -- a cached report cannot latch a protected player
	if entity.ChaseTriggered then
		-- Preserve a living chase target. If it vanished between reports, a new
		-- genuine observer can take ownership without clearing the hunt latch.
		if entity.ChaseTarget and livingPlayer(session, entity.ChaseTarget) then return end
	else
		entity.ChaseTriggered = true
		entity.ChaseTriggeredAt = now
		local observation = session.Configuration.Observation or {}
		entity.ChaseGraceUntil = now + numberOr(observation.ChaseGraceSeconds, 0.45, 0, 2)
		local ramp = (session.Configuration.Movement or {}).SpeedRamp or {}
		entity.SpeedRampFrozen = ramp.FreezeOnChase ~= false
		setModelAttribute(entity.Model, "Level2_PoolFoamChasing", true)
		setModelAttribute(entity.Model, "Level2_PoolFoamRampFrozen", entity.SpeedRampFrozen)
		-- Re-plan immediately toward the player who actually caused the reveal.
		entity.NextGoalAt = 0
	end
	setChaseTarget(entity, target)
end

-- SERVER BACKSTOP FOR THE CHASE LATCH (2026-09-05).
--
-- Observation itself stays report-driven — see the Observer's own note, and the
-- ProximityLatch block in the configuration. The problem this closes is narrower
-- than "the client decides what it sees": it is that the client decides whether
-- the entity is ever ALLOWED TO KILL. triggerChase fires only on a validated
-- look, instantKill refuses without the latch, and every payload check in the
-- Observer validates the camera's ORIGIN while validating nothing about its
-- direction. A client that reports honestly-shaped frames pointed away from
-- every foam model is unkillable for the whole round, alone or when the entity
-- is on them and nobody else is looking.
--
-- So: independently of every report, an active entity that keeps one living,
-- targetable, roughly STATIONARY player inside ProximityLatchRadius with a clear
-- server line of sight for ProximityLatchSeconds latches the chase, exactly as a
-- look does. This can only ADD a latch — it never clears one, never shortens the
-- grace window and never touches entity.Observed, so the statue/freeze semantics
-- and the speed ramp are unchanged.
--
-- The two narrow gates matter, and the configuration block explains why: an
-- un-latched entity ALREADY walks up to the nearest eligible player and parks at
-- TargetStopDistance, so a wide radius or a short dwell would latch everybody
-- within seconds of contact and delete the look-reveal beat. A player who is
-- moving is never latched here; one who stands in the open with the foam on them
-- for seconds, never looking, is.
--
-- Cost is one raycast per active entity per think tick (0.1 s): a single
-- candidate is chosen first, and only that one is traced.
local function updateProximityLatch(session, entity, now)
	local observation = session.Configuration.Observation or {}
	if observation.ProximityLatchEnabled == false
		or entity.ChaseTriggered
		or session.Phase == PHASES.Dormant
		or not entityIsActive(session, entity)
	then
		entity.ProximityDwellPlayer = nil
		return
	end

	local radius = numberOr(observation.ProximityLatchRadius, 8, 4, 200)
	local maximumSpeed = numberOr(observation.ProximityLatchMaximumSpeed, 3, 0, 100)
	local position = entity.Navigator:GetPosition()
	local function dwellable(player)
		local root, _, character = livingPlayer(session, player)
		-- The same eligibility the hunt itself uses: before the first pump this
		-- encounter is confined to the Kids Area, so a player it may not chase
		-- must not be able to arm it either.
		if not (root and character
			and (session.Pumps >= 1 or positionInKids(session, root.Position)))
		then
			return nil
		end
		local distance = (root.Position - position).Magnitude
		if distance > radius then return nil end
		local velocity = root.AssemblyLinearVelocity
		if Vector3.new(velocity.X, 0, velocity.Z).Magnitude > maximumSpeed then return nil end
		return root, character, distance
	end

	-- The incumbent keeps the clock. Picking "whoever is nearest THIS tick" meant
	-- any teammate who crossed the radius for a single 0.1 s tick reset a nearly
	-- complete dwell to zero — so two players standing together were immune, which
	-- is exactly the immunity this backstop exists to close.
	local candidate, candidateRoot, candidateCharacter
	if entity.ProximityDwellPlayer then
		local root, character = dwellable(entity.ProximityDwellPlayer)
		if root then
			candidate, candidateRoot, candidateCharacter = entity.ProximityDwellPlayer, root, character
		end
	end
	if not candidate then
		local candidateDistance = math.huge
		for _, player in ipairs(Players:GetPlayers()) do
			local root, character, distance = dwellable(player)
			if root and distance < candidateDistance then
				candidate, candidateRoot, candidateCharacter = player, root, character
				candidateDistance = distance
			end
		end
	end

	if not candidate or not entityLineOfSight(session, entity, candidateCharacter, candidateRoot.Position) then
		entity.ProximityDwellPlayer = nil
		return
	end
	if entity.ProximityDwellPlayer ~= candidate then
		entity.ProximityDwellPlayer = candidate
		entity.ProximityDwellSince = now
		return
	end
	local dwell = numberOr(observation.ProximityLatchSeconds, 7, 0.25, 60)
	if now - entity.ProximityDwellSince < dwell then return end
	entity.ProximityDwellPlayer = nil
	triggerChase(session, entity, {candidate}, now)
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
		if observationFreezes(session) then
			-- Card wdz28z81: a watched foam stands still AND gives back the speed
			-- it earned; looking away restarts the chase from its floor. The
			-- stop itself is updateEntity's freeze branch, so only the bonus is
			-- touched here.
			entity.SpeedRampBonus = 0
		end
		if observation.TriggerChaseOnObserve ~= false
			and rawObserved
			and session.Phase ~= PHASES.Dormant
			and entityIsActive(session, entity)
		then
			triggerChase(session, entity, players, now)
		end
		if not observationFreezes(session) then
			entity.RevealUntil = 0
		elseif not wasObserved then
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
	-- Readback for playtests, at the think rate: the speed the last step asked
	-- for, and 0 while a look holds it still.
	setModelAttribute(entity.Model, "Level2_PoolFoamSpeed", (entity.Observed and observationFreezes(session)) and 0
		or math.floor(entity.LastDesiredSpeed * 10 + 0.5) / 10)
end

local function choosePatrolPosition(session, entity)
	entity.PatrolNoisePlayer = nil
	local current = entity.Navigator:GetPosition()
	-- Investigate before wandering. A pump motor is a noise with nobody standing
	-- at it, and every player can be an invalid target at once (all of them on
	-- the unreachable cooldown, or outside the Kids Area before the first pump),
	-- so walking toward what it heard is strictly better than a random node.
	--
	-- Walk to the nearest PATROL NODE, never to the raw heard position: that is a
	-- player root or a pump model's pivot, and a pump pivot commonly sits inside
	-- the pump body where no path can solve. SetGoal accepts it either way (the
	-- navigator is built without AllowedHallIndices, so _positionAllowed is
	-- unconditional), so an unreachable goal fails silently — and because the
	-- pump re-announces every 2 s the stuck-repath below would hand back the same
	-- dead point for the whole motor run. session.Nodes are the only positions
	-- this encounter knows are standable and inside an allowed hall.
	local noise = entity.HeardNoise
	if noise then
		local nearest, nearestDistance = nil, math.huge
		for _, node in ipairs(session.Nodes) do
			local distance = (node.Position - noise.pos).Magnitude
			if distance < nearestDistance then nearest, nearestDistance = node.Position, distance end
		end
		if nearest and (nearest - current).Magnitude > 7 then
			entity.PatrolNoisePlayer = noise.SourcePlayer
			return nearest
		end
	end
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

local function movementSpeed(session, entity, hunting, rampDeltaTime)
	local movement = session.Configuration.Movement or {}
	local speeds = movement.Speeds or {}
	local base = hunting and numberOr(speeds.Hunt, 3.0, 0, 40) or numberOr(speeds.Stalk, 3.0, 0, 30)
	local multiplier = numberOr(phaseRecord(session, session.Phase).SpeedMultiplier, 1, 0, 3)
	local ramp = movement.SpeedRamp or {}
	if ramp.Enabled ~= false and not entity.SpeedRampFrozen and rampDeltaTime > 0 then
		local acceleration = numberOr(ramp.AccelerationPerSecond, 0.65, 0, 8)
		local maximumBonus = numberOr(ramp.MaximumBonus, 12, 0, 30)
		entity.SpeedRampBonus = math.min(maximumBonus,
			entity.SpeedRampBonus + acceleration * rampDeltaTime)
	end
	local speed = base * multiplier
	if entity.ChaseTriggered then
		-- The chase floor is where every chase (re)starts, and the bonus rides
		-- on top of it, so acceleration shows from the first second of a chase
		-- and a look (which zeroes the bonus) drops it back to exactly this.
		speed = math.max(speed, numberOr(ramp.ChaseMinimumSpeed, 13, 0, 40))
	end
	speed = math.min(speed + entity.SpeedRampBonus, numberOr(ramp.MaximumSpeed, 22, 1, 40))
	entity.LastDesiredSpeed = speed
	return speed
end

local function resetProgressWindow(entity, position, goal, resetAttempts)
	entity.NoProgressFor = 0
	entity.ProgressAnchor = position
	entity.ProgressGoal = goal
	entity.ProgressGoalDistance = goal and (goal - position).Magnitude or math.huge
	if resetAttempts ~= false then entity.RepathAttempts = 0 end
end

local function releaseProtectedPlayer(session, player, character)
	if activeSession ~= session or not PlayerProtection.IsActive(player, character) then return end
	if session.TargetedPlayer == player then setTargeted(session, nil) end
	for _, entity in ipairs(session.Entities) do
		local targeted = entity.ChaseTarget == player or entity.Target == player or entity.ProgressTarget == player
		local noiseRoute = entity.PatrolNoisePlayer == player
		if entity.ChaseTarget == player then setChaseTarget(entity, nil) end
		if entity.Target == player then entity.Target = nil end
		if entity.ProgressTarget == player then entity.ProgressTarget = nil end
		if entity.ProximityDwellPlayer == player then
			entity.ProximityDwellPlayer, entity.ProximityDwellSince = nil, 0
		end
		if entity.HeardNoise and entity.HeardNoise.SourcePlayer == player then entity.HeardNoise = nil end
		if noiseRoute then entity.PatrolPosition, entity.PatrolNoisePlayer = nil, nil end
		if targeted or (noiseRoute and not entity.Target) then
			entity.Navigator:Stop()
			entity.NextGoalAt, entity.WasMoving = 0, false
			resetProgressWindow(entity, entity.Navigator:GetPosition(), nil, true)
		end
		-- Recompute the whole observer result so an eligible teammate keeps its
		-- observation. A protected observer cannot retain the short release hold.
		if table.find(entity.Observers, player.UserId) then
			entity.LastSeenAt = nil
			updateObservation(session, entity, os.clock())
		end
	end
	session.ObservationAccumulator = 1
end

-- NEVER STEP INTO ANOTHER BODY (2026-09-23). updateSeparation corrects AFTER
-- the step with one frame of lookahead, and Studio chase frames run 40+ ms, so
-- a 14-22 stud/s hunter still crossed that lookahead into a held body (head-on
-- in a corridor, 0.1-0.2 studs; 1.3 studs once). This is how far the entity can
-- travel along its heading before its disc touches another's -- a ray against
-- each contact circle ahead of it -- whatever the frame time.
local function separationStepRoom(session, entity)
	local heading = entity.Navigator:GetHeading()
	if not heading then return math.huge end
	local at = entity.Navigator:GetPosition()
	local room = math.huge
	for _, other in ipairs(session.Entities) do
		if other ~= entity then
			local position = other.Navigator:GetPosition()
			local deltaX, deltaZ = position.X - at.X, position.Z - at.Z
			local along = deltaX * heading.X + deltaZ * heading.Z
			local reach = entity.BodyRadius + other.BodyRadius
			local lateral2 = deltaX * deltaX + deltaZ * deltaZ - along * along
			if along > 0 and lateral2 < reach * reach then
				room = math.min(room, math.max(0, along - math.sqrt(reach * reach - lateral2)))
			end
		end
	end
	return room
end

local function updateEntity(session, entity, deltaTime, now)
	local active = entityIsActive(session, entity)
	setModelAttribute(entity.Model, "Level2_PoolFoamActiveMover", active)
	if not active or session.Phase == PHASES.Dormant then
		entity.Navigator:Stop()
		entity.WasMoving = false
		entity.StationaryFor = 0
		resetProgressWindow(entity, entity.Navigator:GetPosition(), nil, true)
		resetThreatState(entity)
		if entity.Observed and observationFreezes(session) then
			setEntityAnimationPaused(entity, true)
		else
			setEntityAnimationPaused(entity, false)
			setEntityAnimation(entity, "Idle")
		end
		return
	end
	if observationFreezes(session) and entity.Observed and now >= entity.RevealUntil then
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
	-- Walk/ramp is the pre-look state. Hunt begins only at the one-way gaze
	-- latch, so pump progression cannot silently skip the encounter's tell.
	local hunting = pursuing and entity.ChaseTriggered
	local stopDistance = numberOr((session.Configuration.Movement or {}).TargetStopDistance, 4.5, 1, 20)
	if pursuing and distance <= stopDistance then
		entity.Navigator:Stop()
		entity.WasMoving = false
		entity.LastDesiredSpeed = 0
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

	-- SEPARATION HOLD. Another entity is inside this one's no-overlap disc (see
	-- updateSeparation). Withhold LOCOMOTION only -- the target choice, the kill
	-- check and the goal above have all already run, and the separation pass
	-- still moves this entity through Navigator:Sidestep -- so the pair cannot
	-- walk through each other while the yielder is eased out or backs off. The
	-- lease is short and refreshed by the pass, so nothing here can strand a
	-- creature; the progress watchdog below is skipped on purpose, because a hold
	-- is not the creature failing to make progress.
	-- A heading with no room left before another body is the same wait.
	local room = separationStepRoom(session, entity)
	if now < (entity.SeparationHoldUntil or 0) or room < 0.01 then
		entity.WasMoving = false
		entity.StationaryFor += deltaTime
		setEntityAnimation(entity, "Idle")
		setEntityAnimationPaused(entity, false)
		return
	end

	local before = entity.Navigator:GetPosition()
	entity.Reached = entity.Navigator:Step(deltaTime, math.min(
		movementSpeed(session, entity, hunting, pursuing and deltaTime or 0), room / math.max(deltaTime, 1e-3)))
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
				local navigation = entity.Navigator:GetDebugSnapshot()
				local requestAge = now - numberOr(navigation.RequestStartedAt, -math.huge)
				local requestTimeout = numberOr(movement.PathRequestTimeout, 8, 2, 30)
				if navigation.Computing and requestAge >= 0 and requestAge < requestTimeout
					and entity.NoProgressFor < requestTimeout then
					-- Certification may outlast the movement watchdog. Bound its
					-- grace by total idle time too, so successive timed-out requests
					-- cannot keep the creature waiting forever.
					return
				end
				entity.RepathAttempts += 1
				if entity.RepathAttempts == 1 then
					entity.Navigator:SetGoal(currentGoal, true)
				else
					if pursuing and player then
						local cooldown = numberOr(movement.UnreachableTargetCooldown, 3, 0.5, 30)
						entity.UnreachableUntil[player] = now + cooldown
						if entity.ChaseTarget == player then setChaseTarget(entity, nil) end
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

	destroyEntityAudio(entity)
	entity.Model = replacement
	-- The final art is a different size from the proxy it replaces, so the
	-- no-overlap radius is re-measured rather than carried over.
	entity.BodyRadius = separationRadius(session.Configuration, replacement)
	entity.Navigator = replacementNavigator
	entity.Animation = replacementAnimation
	entity.AnimationPaused = false
	entity.StationaryFor = 0
	resetProgressWindow(entity, replacementNavigator:GetPosition(), oldGoal, true)
	oldNavigator:Destroy()
	if oldAnimation then pcall(function() oldAnimation:Destroy() end) end
	pcall(function() session.ProxyFactory.Destroy(oldModel) end)
	local freezes = observationFreezes(session) and entity.Observed
	setEntityAnimation(entity, entity.WasMoving and (entity.ChaseTriggered and "Hunt" or "Walk") or "Idle", true)
	setEntityAnimationPaused(entity, freezes)
	fireClientEvent(session, "TemplateResolved", {
		EntityId = entity.Id,
		Slot = entity.SlotId,
		Position = replacement:GetPivot().Position,
		Duration = 0,
		Caption = false,
	})
end

-- SEPARATION BEGIN: the only thing that keeps two Pool Foam models apart.
--
-- Nothing else can. Every part of every clone is anchored with CanCollide
-- false, and the Navigator excludes the entire runtime folder from its own body
-- queries, so one foam has never read as an obstacle to another: they overlap at
-- spawn, cross each other's routes and stack on a shared chase target.
--
-- The rule, run once per Heartbeat after every entity has committed its step:
--
--   * Each model's no-overlap radius is MEASURED from the model (separationRadius
--     above), so the contact distance of a pair is rA + rB -- 7.5 studs for two
--     shipped proxies -- and the pass starts correcting a padding earlier.
--   * Only ONE of a pair ever moves: the YIELDER, deterministically the higher
--     spawn ordinal, except that an entity the phase has not activated cannot
--     move at all and so is never chosen. A symmetric push is how two steering
--     agents end up shoving each other back and forth.
--   * A neighbour AHEAD of the yielder (inside the AheadCosine cone of its own
--     heading) is never answered by pushing it backwards. That is the one
--     geometry where the correction is exactly opposite the route step, so the
--     two cancel and the model shivers at 60 Hz; it is also the geometry where
--     backing up achieves nothing. Instead the yielder is HELD -- updateEntity
--     withholds its locomotion -- and eased LATERALLY around the obstruction,
--     either lane. Holding is the half that matters: a lateral slide alone only
--     redirects the approach, it does not stop it, and five entities steering
--     round one target while still walking into it spiral inward until they are
--     all standing in the same place. Neighbours beside or behind get the
--     ordinary radial push, which is roughly perpendicular to the route and so
--     cannot fight it, and they never hold anything.
--   * Every correction is a single accumulated Navigator:Sidestep: ONE validated
--     placement, clamped to MaximumOffset AND to the distance the creature could
--     have walked in this frame, so separation never moves a body faster than it
--     moves itself. A placement that would leave the walkable space fails and
--     the offset is simply dropped -- the route is never edited and no entity is
--     ever teleported.
--   * Two entities in actual contact are BOTH held, so neither can advance
--     through the other while the yielder is eased out; so is an entity whose
--     yielder is PINNED in front of it, which is the only way to stop a body
--     walking into one that has nowhere to go.
--   * A yielder that is OBSTRUCTING somebody -- an entity with right of way
--     that has a goal, a speed and this yielder standing in the cone it is
--     walking into -- runs a bounded wait; when it expires it backs out along
--     its own trail (Navigator:Retreat, validated placement by placement, and
--     never onto a position another body occupies) and re-plans. That is what
--     resolves a head-on meeting in a corridor too narrow for either of them to
--     step aside: the one with right of way keeps walking through the ground
--     the yielder gives up. Being crowded is NOT obstructing: a ring of arrived
--     hunters round one player wants nothing and runs no clock, which is what
--     makes a converged ring a stable end state rather than a permanent churn
--     of back-outs.
local function separationDirection(from, to, fallbackFacing)
	local offset = Vector3.new(to.X - from.X, 0, to.Z - from.Z)
	if offset.Magnitude > 0.01 then return offset.Unit end
	-- Two bodies at the same point have no "away". Step sideways from the
	-- yielder's own facing instead: deterministic, and never straight backwards
	-- down the route it just walked.
	local facing = typeof(fallbackFacing) == "Vector3" and fallbackFacing or Vector3.new(0, 0, -1)
	local side = Vector3.new(-facing.Z, 0, facing.X)
	if side.Magnitude < 0.01 then return Vector3.new(1, 0, 0) end
	return side.Unit
end

-- Is this entity actually trying to get somewhere? updateEntity PARKS a hunter
-- that has arrived -- Navigator:Stop() (which drops the goal) and desired speed
-- zero -- so a ring of foam converged on one player is made of entities that
-- want nothing, and one standing behind them is not obstructed, it has arrived
-- too. Deliberately NOT tested here: whether the entity is itself under a
-- separation hold. The pinned rule holds the entity with right of way exactly
-- when its yielder cannot step aside, which is the corridor stand-off the
-- bounded wait exists for; testing the hold would freeze that case forever.
local function separationPressing(session, entity, contact)
	-- The GOAL is the signal, not the last desired speed: Stop() already drops
	-- the goal of a parked hunter, while a speed of 0 is also what a parked
	-- hunter still carries after its target left and it was given a new goal but
	-- held before its first step -- which read as "wants nothing" and left its
	-- yielder's wait unarmed for good (Studio 2026-09-23, 0 of 5 moved).
	local goal = entity.Navigator:GetGoal()
	if goal == nil then return false end
	-- ...and it still has somewhere to WALK. Testing the goal alone is not
	-- enough: in a converged ring only the first entity gets inside
	-- TargetStopDistance and parks, while the ones held a body further out keep
	-- both a goal and a speed and would read as pressing forever. A hunter whose
	-- goal is already within one body's reach of where it would park has
	-- arrived, crowd or no crowd -- and in the ring measured in Studio that is
	-- 6.7 studs against a 4.5 + 5.17 = 9.7 reach, so none of the five arms
	-- anything, while a corridor stand-off with a player tens of studs away
	-- still does.
	local at = entity.Navigator:GetPosition()
	local stop = numberOr((session.Configuration.Movement or {}).TargetStopDistance, 4.5, 1, 20)
	local deltaX, deltaZ = goal.X - at.X, goal.Z - at.Z
	local reach = stop + contact
	return deltaX * deltaX + deltaZ * deltaZ > reach * reach
end

-- Is `position` outside every OTHER entity's body? The navigator's own floor
-- and body checks cannot answer this: the runtime folder is excluded from its
-- queries, so one foam is invisible to another's geometry tests.
local function separationFree(session, entity, position)
	for _, other in ipairs(session.Entities) do
		if other ~= entity then
			local at = other.Navigator:GetPosition()
			local deltaX, deltaZ = position.X - at.X, position.Z - at.Z
			local reach = entity.BodyRadius + other.BodyRadius
			if deltaX * deltaX + deltaZ * deltaZ < reach * reach then return false end
		end
	end
	return true
end

-- A correction must never carry a body INTO a third one. The pushes are summed
-- pair by pair, and in a cluster of three that sum walked two bodies into each
-- other (offline replay of the 2026-09-23 Studio cluster). Moving AWAY from a
-- body it already overlaps is always allowed, so this can never pin an overlap.
local function separationTrySidestep(session, entity, offset, travel)
	local at = entity.Navigator:GetPosition()
	for _, other in ipairs(session.Entities) do
		if other ~= entity then
			local position = other.Navigator:GetPosition()
			local reach = entity.BodyRadius + other.BodyRadius
			local beforeX, beforeZ = at.X - position.X, at.Z - position.Z
			local afterX, afterZ = beforeX + offset.X, beforeZ + offset.Z
			local after = afterX * afterX + afterZ * afterZ
			if after < reach * reach and after < beforeX * beforeX + beforeZ * beforeZ then return false end
		end
	end
	return entity.Navigator:Sidestep(offset, travel)
end

local function separationSidestep(session, entity, limit, ahead)
	local push = Vector3.new(entity.SeparationPushX, 0, entity.SeparationPushZ)
	local magnitude = push.Magnitude
	if magnitude < 0.01 then return false end
	local direction = push / magnitude
	local travel = math.min(magnitude, limit)
	if ahead then
		-- The lane is already baked into the push by the pair pass, where it is
		-- committed for as long as the obstruction lasts; nothing re-decides it
		-- here. Re-deciding it every frame is what made a rig slide to one wall
		-- of a corridor, find that lane blocked, take the other, slide back and
		-- repeat forever -- and because it was technically moving it never sat
		-- still long enough for the bounded wait to resolve it either.
		if separationTrySidestep(session, entity, direction * travel, travel) then return true end
		-- The committed lane is walled. Swapping to the other one is allowed
		-- ONCE per obstruction, and backing up is never allowed at all, so a
		-- yielder with both lanes shut is held rather than shuffled.
		if entity.SeparationLaneTried then return false end
		entity.SeparationLaneTried = true
		entity.SeparationLane = -entity.SeparationLane
		return separationTrySidestep(session, entity, direction * -travel, travel)
	end
	if separationTrySidestep(session, entity, direction * travel, travel) then return true end
	-- Nothing is in front, so the push is not fighting the route. Either
	-- perpendicular is a fair escape when straight away is against a wall.
	local side = Vector3.new(-direction.Z, 0, direction.X)
	return separationTrySidestep(session, entity, side * travel, travel)
		or separationTrySidestep(session, entity, side * -travel, travel)
end

local function updateSeparation(session, now, deltaTime)
	local tuning = separationTuning(session.Configuration)
	if tuning.Enabled == false then return end
	local entities = session.Entities
	if #entities < 2 then return end
	local startedAt = os.clock()
	local padding = numberOr(tuning.Padding, 1.5, 0, 12)
	local maximumOffset = numberOr(tuning.MaximumOffset, 0.9, 0.05, 4)
	local aheadCosine = numberOr(tuning.AheadCosine, 0.5, 0, 1)
	-- A correction may never be faster than the creature itself. Without this a
	-- 0.9-stud offset every Heartbeat is 54 studs/s of strafing, which is shoving
	-- with extra steps. A parked entity still has to be movable, so the floor is
	-- the slowest pace the encounter ever walks (Movement.Speeds.Stalk).
	local correctionFloor = numberOr(tuning.MinimumCorrectionSpeed, 7.5, 0.5, 40)
	local frame = numberOr(deltaTime, 1 / 60, 1 / 240, 0.1)

	for _, entity in ipairs(entities) do
		entity.SeparationPushX, entity.SeparationPushZ = 0, 0
		entity.SeparationContact, entity.SeparationContactDistance = nil, math.huge
		entity.SeparationAhead, entity.SeparationAheadDistance = nil, math.huge
		entity.SeparationObstructing, entity.SeparationClearance = false, 0
		-- A watched foam is a statue: nothing, separation included, moves it.
		-- Its moving neighbour yields instead, exactly as for an inactive one.
		entity.SeparationActive = entityIsActive(session, entity)
			and not (entity.Observed and observationFreezes(session))
	end

	-- O(n^2) over five entities is ten distance comparisons; the expensive part
	-- is the placement below, and that only runs for an entity actually crowded.
	local minimum = math.huge
	local overlapping = false
	for index = 1, #entities - 1 do
		local a = entities[index]
		local aPosition = a.Navigator:GetPosition()
		for other = index + 1, #entities do
			local b = entities[other]
			local bPosition = b.Navigator:GetPosition()
			local deltaX, deltaZ = bPosition.X - aPosition.X, bPosition.Z - aPosition.Z
			local distance = math.sqrt(deltaX * deltaX + deltaZ * deltaZ)
			local contact = a.BodyRadius + b.BodyRadius
			if distance < minimum then minimum = distance end
			if distance < contact then overlapping = true end
			if distance < contact + padding then
				local yielder, holder
				if a.SeparationActive and (not b.SeparationActive or a.SpawnOrdinal > b.SpawnOrdinal) then
					yielder, holder = a, b
				elseif b.SeparationActive then
					yielder, holder = b, a
				end
				if yielder then
					local facing = yielder.Navigator:GetFacing()
					local away = separationDirection(holder.Navigator:GetPosition(),
						yielder.Navigator:GetPosition(), facing)
					local intrusion = contact + padding - distance
					if away.X * facing.X + away.Z * facing.Z < -aheadCosine then
						-- Directly in the way: go round it. THE LANE IS COMMITTED on
						-- the first frame of an obstruction and never recomputed
						-- while it lasts. Recomputing it is not stable: the lean it
						-- is derived from passes through zero in a true head-on, so
						-- the preferred side flips with the last bit of the mantissa
						-- and the model shivers between two lanes instead of taking
						-- one. Ordinal parity settles that tie -- stable for the
						-- whole round, and it gives neighbours opposite lanes.
						local side = Vector3.new(-facing.Z, 0, facing.X)
						local lane = yielder.SeparationLane
						if lane == 0 or yielder.SeparationLaneFor ~= holder then
							local lean = side.X * away.X + side.Z * away.Z
							if lean > 0.001 then
								lane = 1
							elseif lean < -0.001 then
								lane = -1
							else
								lane = (yielder.SpawnOrdinal % 2 == 0) and 1 or -1
							end
							yielder.SeparationLane, yielder.SeparationLaneFor = lane, holder
							yielder.SeparationLaneTried = false
						end
						yielder.SeparationPushX += side.X * lane * intrusion
						yielder.SeparationPushZ += side.Z * lane * intrusion
						if distance < yielder.SeparationAheadDistance then
							yielder.SeparationAhead, yielder.SeparationAheadDistance = holder, distance
						end
					else
						yielder.SeparationPushX += away.X * intrusion
						yielder.SeparationPushZ += away.Z * intrusion
					end
					-- THE BOUNDED WAIT IS FOR A STAND-OFF, NOT FOR A CROWD.
					--
					-- Measured in Studio on 2026-09-21, seed 1182081016: five
					-- entities converged on one stationary player and stood in a
					-- ring at padded contact, which is the correct end state -- but
					-- in that ring every entity has a neighbour inside its own cone,
					-- so arming the wait on obstruction alone armed it on all five,
					-- forever. Each expiry then called Retreat on an ARRIVED entity,
					-- whose Navigator:Stop() had already emptied its trail, so the
					-- back-out moved nothing, the release ceiling fired instead, and
					-- for two seconds the pair was free to walk into each other:
					-- Level2_PoolFoamYieldCount +2-3/s without end and
					-- MinSeparation down to 3.2 against a 5.17 contact circle.
					--
					-- The wait now needs the entity with right of way to be GENUINELY
					-- BLOCKED BY THIS ONE: it has somewhere to go, and this yielder
					-- is standing inside the cone it is walking into. A ring of
					-- arrived hunters runs no clock at all and is a stable end state.
					local holderFacing = holder.Navigator:GetFacing()
					if separationPressing(session, holder, contact)
						and away.X * holderFacing.X + away.Z * holderFacing.Z > aheadCosine
					then
						yielder.SeparationObstructing = true
						yielder.SeparationClearance =
							math.max(yielder.SeparationClearance, contact + padding)
					end

					-- The contact circle is DEFENDED, not merely detected. This pass
					-- corrects after the step, so a pair that is already touching
					-- when it first looks has already interpenetrated by whatever it
					-- closed in that frame; the brake therefore engages one frame of
					-- closing early. The floor keeps two parked bodies apart when
					-- neither has a speed to derive it from.
					local brake = math.max(0.25,
						(numberOr(a.LastDesiredSpeed, 0, 0, 40)
							+ numberOr(b.LastDesiredSpeed, 0, 0, 40)) * frame)
					if distance < contact + brake and distance < yielder.SeparationContactDistance then
						yielder.SeparationContact, yielder.SeparationContactDistance = holder, distance
					end
				end
			end
		end
	end

	local holdSeconds = numberOr(tuning.HoldSeconds, 0.15, 0.05, 2)
	local yieldSeconds = numberOr(tuning.YieldSeconds, 1.2, 0.1, 10)
	for _, entity in ipairs(entities) do
		local ahead = entity.SeparationAhead
		local touching = entity.SeparationContact
		local limit = math.min(maximumOffset,
			math.max(correctionFloor, numberOr(entity.LastDesiredSpeed, 0, 0, 40)) * frame)
		if ahead == nil and entity.SeparationLaneFor ~= nil then
			-- Nothing in the way any more: the next obstruction chooses afresh.
			entity.SeparationLane, entity.SeparationLaneFor = 0, nil
			entity.SeparationLaneTried = false
		end
		local moved = separationSidestep(session, entity, limit, ahead ~= nil)
		-- The yielder is held whenever something is in its way, moved or not:
		-- sliding around an obstruction does not stop a route that points through
		-- it. The OTHER entity is held only when it is touching this one or has
		-- it pinned -- an entity with right of way is never stopped by something
		-- merely behind it, which is what keeps a corridor from becoming a queue.
		local blocker = touching
		-- A touching blocker is stopped by ANY step toward this yielder: at
		-- contact even a sideways one closes the gap (Studio 2026-09-23, two foams
		-- stepping past a held third at 60-80 degrees reached 0.6 studs of
		-- overlap). A pinned one only by a step into the cone it is facing.
		local threshold = 0
		if not blocker and ahead ~= nil and not moved then blocker, threshold = ahead, aheadCosine end
		-- EVERY HOLD MUST BE ONE THE BOUNDED WAIT CAN END (Studio 2026-09-23,
		-- seed 1182081016). Five foams settled round a player at contact+padding,
		-- where each correction sits under separationSidestep's 0.01 floor, so
		-- every yielder read as pinned and held the body ahead of it -- including
		-- bodies facing away from it, which the wait above never counts as
		-- obstructed. A held body never steps, so its facing never updated: when
		-- the player walked off, all five stood still for good (YieldCount 0).
		-- So a blocker is held only while it is stepping toward this yielder,
		-- and a held blocker that still wants to go somewhere arms this
		-- yielder's wait, so every such hold is one the wait can end.
		if blocker then
			local from, to = blocker.Navigator:GetPosition(), entity.Navigator:GetPosition()
			local deltaX, deltaZ = to.X - from.X, to.Z - from.Z
			local length = math.sqrt(deltaX * deltaX + deltaZ * deltaZ)
			local facing = blocker.Navigator:GetFacing()
			local reach = entity.BodyRadius + blocker.BodyRadius
			if length > 0.01 and (deltaX * facing.X + deltaZ * facing.Z) / length <= threshold then
				blocker = nil
			elseif separationPressing(session, blocker, reach) then
				entity.SeparationObstructing = true
				entity.SeparationClearance = math.max(entity.SeparationClearance, reach + padding)
			end
		end
		if (ahead ~= nil or touching ~= nil) and now >= entity.SeparationReleaseUntil then
			local leaseUntil = now + holdSeconds
			if leaseUntil > entity.SeparationHoldUntil then entity.SeparationHoldUntil = leaseUntil end
			if blocker and leaseUntil > blocker.SeparationHoldUntil then
				blocker.SeparationHoldUntil = leaseUntil
			end
		end
		-- The wait is measured on OBSTRUCTING somebody who is trying to get past,
		-- never on standing still and never on merely being crowded. A yielder
		-- easing sideways along a wall is moving and getting nowhere, so crediting
		-- that as progress would let two entities stand nose to nose for a whole
		-- round; a yielder that nobody is waiting for has nothing to prove.
		if not entity.SeparationObstructing then
			entity.SeparationYieldSince = nil
		else
			entity.SeparationYieldSince = entity.SeparationYieldSince or now
			if now - entity.SeparationYieldSince >= yieldSeconds then
				entity.SeparationYieldSince = nil
				session.SeparationYields += 1
				-- Back out far enough to clear the body that is waiting and no
				-- further, and never THROUGH a third one: Retreat asks about every
				-- position before it steps there and stops at the first refusal.
				local reach = math.min(numberOr(tuning.RetreatStuds, 8, 0, 48),
					math.max(entity.SeparationClearance, 1))
				local backed = entity.Navigator:Retreat(reach, function(position)
					return separationFree(session, entity, position)
				end)
				entity.PatrolPosition = nil
				entity.NextGoalAt = 0
				entity.SeparationHoldUntil = 0
				if blocker then blocker.SeparationHoldUntil = 0 end
				if backed <= 0 and separationFree(session, entity, entity.Navigator:GetPosition()) then
					-- ponytail: nowhere to back out to and nobody within a body's
					-- reach, so what is blocking the back-out is the WORLD -- a wall
					-- behind, or a trail emptied by a Stop. Only then is the pair
					-- released to pass, because releasing with a neighbour that close
					-- is precisely how five converged entities walked through each
					-- other in the 2026-09-21 Studio round. With one that close the
					-- pair simply stays held: a hold is recoverable the moment either
					-- of them can move, an overlap the owner can see is not. Upgrade
					-- path if a lasting freeze is ever observed: reciprocal velocity
					-- obstacles, or reserving the corridor segment between them.
					entity.SeparationReleaseUntil = now
						+ numberOr(tuning.ReleaseSeconds, 2, 0, 30)
				end
			end
		end
	end

	if minimum < session.SeparationMinimum then session.SeparationMinimum = minimum end
	if overlapping then session.SeparationOverlapFrames += 1 end
	local elapsedMs = (os.clock() - startedAt) * 1000
	session.SeparationCostMs += (elapsedMs - session.SeparationCostMs) * 0.1
	if now >= session.NextSeparationPublishAt then
		session.NextSeparationPublishAt = now + numberOr(tuning.PublishInterval, 0.5, 0.1, 10)
		if session.SeparationMinimum < math.huge then
			setShared("Level2_PoolFoamMinSeparation",
				math.floor(session.SeparationMinimum * 100 + 0.5) / 100)
		end
		setShared("Level2_PoolFoamOverlapFrames", session.SeparationOverlapFrames)
		setShared("Level2_PoolFoamYieldCount", session.SeparationYields)
		setShared("Level2_PoolFoamSeparationMs",
			math.floor(session.SeparationCostMs * 1000 + 0.5) / 1000)
	end
end
-- SEPARATION END

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
	-- Age the shared noise list once per tick, exactly as Level 1's EntityAI
	-- does. Without this nothing ever drops out of it and every sound is "recent"
	-- forever. Level 1's own scripts are disabled for the whole of a Level 2
	-- round, so this session is the only pruner while it is running.
	NoiseRegistry.Prune()

	session.ObservationAccumulator += deltaTime
	local observationInterval = numberOr((session.Configuration.Movement or {}).UpdateInterval, 0.1, 0.05, 0.5)
	if session.ObservationAccumulator >= observationInterval then
		session.ObservationAccumulator = 0
		for _, entity in ipairs(session.Entities) do
			-- One hearing scan per entity per THINK TICK, not per Heartbeat.
			-- bestTarget (every frame) and choosePatrolPosition (already gated on
			-- this same interval) both read the cached value.
			entity.HeardNoise = heardNoise(session, entity)
			updateObservation(session, entity, now)
			-- After the report path, so a genuine look always owns the latch and
			-- the backstop simply finds it already triggered.
			updateProximityLatch(session, entity, now)
		end
	end
	for _, entity in ipairs(session.Entities) do updateEntity(session, entity, math.min(deltaTime, 0.1), now) end
	-- After every entity has committed its position, never between two of them:
	-- a pass that ran mid-loop would measure half the group where it was last
	-- frame. It is also the reason the corrections can be one-sided.
	updateSeparation(session, now, math.min(deltaTime, 0.1))

	if now >= session.NextTemplateRefreshAt then
		session.NextTemplateRefreshAt = now + 3
		for _, entity in ipairs(session.Entities) do refreshTemplate(session, entity) end
	end
end

-- Level 1's EntityAI owns Remotes.ReportNoise during a Level 1 round, and the
-- Round Adapter disables it for the whole of Level 2 (isolateLevelOneRuntime),
-- so nothing was draining the remote here: the client reports were arriving with
-- no listener.
--
-- Connected at MODULE scope, once, for exactly the reason EntityAI documents at
-- its own intake: a RemoteEvent every client fires at 5 Hz with ZERO
-- OnServerEvent connections piles the invocations up until Roblox drops them
-- with "invocation queue exhausted" in the log. Controller.Start returns early
-- on a dozen paths — Configuration.Enabled = false, the dev toggle, every
-- manifest/proxy/navigator/observer error — and a session-scoped connection
-- would leave a whole round undrained on any of them.
--
-- Validation matches EntityAI's: the client says which STATE it is in and the
-- server decides the position, the loudness and whether it is plausible.
do
	local remotes = ReplicatedStorage:FindFirstChild("Remotes")
	local report = remotes and remotes:FindFirstChild("ReportNoise")
	if not (report and report:IsA("RemoteEvent")) then
		warn("[Pool Foam] Remotes.ReportNoise is missing; player noise is not heard")
	else
		local lastReport = {}
		report.OnServerEvent:Connect(function(player, stateName)
			-- With no live session (any other level, or Pool Foam disabled) the
			-- queue is still drained; it is simply heard by nobody.
			local session = activeSession
			if not session or not sessionAlive(session) then return end
			if (session.Configuration.Hearing or {}).Enabled == false then return end
			if type(stateName) ~= "string" or not CLIENT_NOISE[stateName] then return end
			local now = os.clock()
			if lastReport[player] and now - lastReport[player] < 0.15 then return end
			lastReport[player] = now
			local root = livingPlayer(session, player)
			if not root then return end
			local speed = Vector3.new(root.AssemblyLinearVelocity.X, 0,
				root.AssemblyLinearVelocity.Z).Magnitude
			if speed < 2 then return end
			if stateName == "sprint" and speed < 12 then return end
			NoiseRegistry.Add(root.Position, stateName, player)
		end)
		Players.PlayerRemoving:Connect(function(player)
			lastReport[player] = nil
		end)
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
		-- player -> how many entities are currently hunting them (see markChased)
		ChaseMarks = {},
		-- Separation diagnostics for the round, published by updateSeparation.
		SeparationMinimum = math.huge,
		SeparationOverlapFrames = 0,
		SeparationYields = 0,
		SeparationCostMs = 0,
		NextSeparationPublishAt = 0,
	}
	activeSession = session

	-- Every generated Kids Area owns one distinct runtime identity, while every
	-- clone resolves art and animation through the single Primary asset slot.
	local takenSpawns = {}
	for ordinal, hall in ipairs(kidsHalls) do
		local entityId = string.format("Primary_%02d", ordinal)
		local spawnPosition = positionForHall(session, hall, takenSpawns)
		table.insert(takenSpawns, spawnPosition)
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
	table.insert(session.Connections, PlayerProtection.Activated:Connect(function(player, character)
		releaseProtectedPlayer(session, player, character)
	end))
	table.insert(session.Connections, Players.PlayerRemoving:Connect(function(player)
		if session.TargetedPlayer == player then session.TargetedPlayer = nil end
		session.ChaseMarks[player] = nil
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
		-- A hunted player must never carry the mark out of the round: it is worth
		-- triple stamina in NoiseReporter and a permanent camera shake in
		-- EntityShakeController.
		if player:GetAttribute("BeingChased") == true then
			player:SetAttribute("BeingChased", false)
		end
	end
	table.clear(session.ChaseMarks)
	-- The registry is global and this round's footsteps and pump motors must not
	-- be audible in the next one. Only a Level 2 round reaches this function, and
	-- no other level's round is live while it does.
	if NoiseRegistry.Clear then NoiseRegistry.Clear() end
	for _, connection in ipairs(session.Connections) do connection:Disconnect() end
	for _, entity in ipairs(session.Entities) do
		if entity.Navigator then entity.Navigator:Destroy() end
		if entity.Animation then pcall(function() entity.Animation:Destroy() end) end
		destroyEntityAudio(entity)
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
			Chasing = entity.ChaseTriggered,
			ChaseTargetUserId = entity.ChaseTarget and entity.ChaseTarget.UserId or 0,
			ChaseElapsed = entity.ChaseTriggeredAt and os.clock() - entity.ChaseTriggeredAt or 0,
			SpeedRampBonus = entity.SpeedRampBonus,
			SpeedRampFrozen = entity.SpeedRampFrozen,
			DesiredSpeed = entity.LastDesiredSpeed,
			BodyRadius = entity.BodyRadius,
			SeparationHeld = os.clock() < (entity.SeparationHoldUntil or 0),
			SeparationYielding = entity.SeparationYieldSince ~= nil,
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
		MinSeparation = session.SeparationMinimum < math.huge and session.SeparationMinimum or 0,
		OverlapFrames = session.SeparationOverlapFrames,
		YieldCount = session.SeparationYields,
		SeparationMs = session.SeparationCostMs,
		Entities = entities,
		Observer = session.Observer:GetDebugSnapshot(),
	}
end

Controller.Protocol = PROTOCOL
Controller.Phases = PHASES

return Controller
