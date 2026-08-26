--!strict
-- Level 3 Objective Controller
--
-- Server authority for the abandoned mall objective:
--   * five physical party CDs with per-player ownership and death recovery;
--   * a shared five-slot disc relay that reveals the hidden walk-through frame;
--   * final service-exit activation and per-player escape;
--   * replicated progress used by the reader, audio, and HUD clients.
--
-- World construction stays in Level 3 World Builder. This module only consumes
-- its manifest, validates every reference, and owns one disposable round session.

local Players = game:GetService("Players")
local ReplicatedStorage = game:GetService("ReplicatedStorage")
local TweenService = game:GetService("TweenService")
local Debris = game:GetService("Debris")
local RunService = game:GetService("RunService")

local Configuration = require(script.Parent:WaitForChild("Level 3 Configuration"))

type AnyTable = {[any]: any}

local ObjectiveController = {}
local activeSession: AnyTable? = nil

local PROMPT_DISTANCE_ALLOWANCE = 2

local function getOrCreateFolder(parent: Instance, name: string): Folder
	local existing = parent:FindFirstChild(name)
	if existing then
		assert(existing:IsA("Folder"), string.format("%s must be a Folder", existing:GetFullName()))
		return existing
	end
	local created = Instance.new("Folder")
	created.Name = name
	created.Parent = parent
	return created
end

local function getInfrastructure(): (Folder, RemoteEvent)
	local stateFolder = getOrCreateFolder(ReplicatedStorage, Configuration.StateFolderName)
	local remotesFolder = getOrCreateFolder(ReplicatedStorage, Configuration.RemotesFolderName)
	local existingEvent = remotesFolder:FindFirstChild(Configuration.ClientEventName)
	if existingEvent then
		assert(existingEvent:IsA("RemoteEvent"), string.format("%s must be a RemoteEvent", existingEvent:GetFullName()))
		return stateFolder, existingEvent
	end
	local event = Instance.new("RemoteEvent")
	event.Name = Configuration.ClientEventName
	event.Parent = remotesFolder
	return stateFolder, event
end

local function disconnect(connection: RBXScriptConnection?)
	if connection and connection.Connected then
		connection:Disconnect()
	end
end

local function disconnectAll(session: AnyTable)
	for _, connection in ipairs(session.Connections) do
		disconnect(connection)
	end
	table.clear(session.Connections)
end

local function cancelTweens(session: AnyTable)
	local tweens = {}
	for tween in pairs(session.Tweens) do
		table.insert(tweens, tween)
	end
	for _, tween in ipairs(tweens) do
		pcall(function()
			tween:Cancel()
		end)
	end
	table.clear(session.Tweens)
end

local function playTween(session: AnyTable, object: Instance, info: TweenInfo, goals: AnyTable): Tween?
	if not object.Parent then return nil end
	local ok, tween = pcall(function()
		return TweenService:Create(object, info, goals)
	end)
	if not ok or not tween then return nil end
	session.Tweens[tween] = true
	local completedConnection: RBXScriptConnection?
	completedConnection = tween.Completed:Connect(function()
		session.Tweens[tween] = nil
		disconnect(completedConnection)
	end)
	tween:Play()
	return tween
end

local function liveSession(session: AnyTable): boolean
	local manifest = session.Manifest
	local world = manifest and manifest.World
	return activeSession == session
		and world ~= nil
		and world:IsA("Model")
		and world.Parent ~= nil
		and world:GetAttribute("Level3_Generation") == session.Generation
end

local function validSession(session: AnyTable): boolean
	return liveSession(session)
		and workspace:GetAttribute("SelectedLevel") == 3
		and workspace:GetAttribute("RoundActive") == true
end

local function livingCharacter(player: Player): (Model?, Humanoid?, BasePart?)
	local character = player.Character
	local humanoid = character and character:FindFirstChildOfClass("Humanoid")
	local root = character and character:FindFirstChild("HumanoidRootPart")
	if not character or not character.Parent or not humanoid or humanoid.Health <= 0
		or not root or not root:IsA("BasePart") then
		return nil, nil, nil
	end
	return character, humanoid, root
end

local function validPlayer(player: Player, session: AnyTable): boolean
	return validSession(session)
		and player.Parent == Players
		and player:GetAttribute("InRound") == true
		and player:GetAttribute("Escaped") ~= true
end

local function updateFinalHallChase(session: AnyTable)
	if not session.ExitUnlocked or session.FinalHallChaseTriggered
		or session.State:GetAttribute("Level3_RoomSongPhase") ~= "DONE" then
		return
	end
	local hall = session.Manifest.FinalHall
	if type(hall) ~= "table" or not hall.Model or not hall.Model.Parent then return end
	local horizontalForward = Vector3.new(hall.Forward.X, 0, hall.Forward.Z)
	if horizontalForward.Magnitude <= .001 then return end
	horizontalForward = horizontalForward.Unit
	local eligibleCount = 0
	local crossedCount = 0
	for _, player in ipairs(Players:GetPlayers()) do
		if validPlayer(player, session) then
			local character, _, root = livingCharacter(player)
			if character and root then
				eligibleCount += 1
				if session.FinalHallCrossed[player] ~= character then
					local offset = Vector3.new(
						root.Position.X - hall.StartPoint.X, 0, root.Position.Z - hall.StartPoint.Z)
					local along = offset:Dot(horizontalForward)
					local lateral = (offset - horizontalForward * along).Magnitude
					local halfway = hall.Length * (hall.HalfwayProgress or .50)
					local insideHallWidth = lateral <= hall.Width * .5 + 2.5
					local insideHallHeight = math.abs(root.Position.Y - hall.FloorY) <= hall.Height + 6
					if along >= halfway and insideHallWidth and insideHallHeight then
						session.FinalHallCrossed[player] = character
					end
				end
				if session.FinalHallCrossed[player] == character then crossedCount += 1 end
			end
		end
	end
	session.FinalHallEligibleCount = eligibleCount
	session.FinalHallCrossedCount = crossedCount
	session.State:SetAttribute("Level3_FinalHallEligibleCount", eligibleCount)
	session.State:SetAttribute("Level3_FinalHallCrossedCount", crossedCount)
	session.Manifest.World:SetAttribute("Level3_FinalHallEligibleCount", eligibleCount)
	session.Manifest.World:SetAttribute("Level3_FinalHallCrossedCount", crossedCount)
	workspace:SetAttribute("Level3FinalHallEligibleCount", eligibleCount)
	workspace:SetAttribute("Level3FinalHallCrossedCount", crossedCount)
	if eligibleCount == 0 or crossedCount ~= eligibleCount then return end

	session.FinalHallChaseTriggered = true
	session.State:SetAttribute("Level3_FinalHallChaseTriggered", true)
	session.State:SetAttribute("Level3_FinalHallChaseActive", true)
	session.State:SetAttribute("Level3_MallManagerHuntActive", true)
	session.Manifest.World:SetAttribute("Level3_FinalHallChaseTriggered", true)
	session.Manifest.World:SetAttribute("Level3_FinalHallChaseActive", true)
	workspace:SetAttribute("Level3FinalHallChaseTriggered", true)
	-- This must precede HuntActive so the Manager's synchronous Start selects the
	-- authored final-hall reveal rather than the legacy hidden random-room spawn.
	workspace:SetAttribute("Level3FinalHallChaseActive", true)
	workspace:SetAttribute("Level3MallManagerHuntActive", true)
end

local function promptWorldPosition(prompt: ProximityPrompt): Vector3?
	local parent = prompt.Parent
	if parent and parent:IsA("Attachment") then return parent.WorldPosition end
	if parent and parent:IsA("BasePart") then return parent.Position end
	return nil
end

local function canUsePrompt(player: Player, session: AnyTable, prompt: ProximityPrompt, owner: Instance): boolean
	if not validPlayer(player, session) then return false end
	if not prompt.Enabled or not prompt:IsDescendantOf(session.Manifest.World) then return false end
	if not owner.Parent or not owner:IsDescendantOf(session.Manifest.World) then return false end
	local character, _, root = livingCharacter(player)
	local target = promptWorldPosition(prompt)
	if not character or not root or not target then return false end
	if (root.Position - target).Magnitude > prompt.MaxActivationDistance + PROMPT_DISTANCE_ALLOWANCE then
		return false
	end
	if prompt.RequiresLineOfSight then
		local originPart = character:FindFirstChild("Head") or root
		if not originPart:IsA("BasePart") then return false end
		local params = RaycastParams.new()
		params.FilterType = Enum.RaycastFilterType.Exclude
		params.FilterDescendantsInstances = {character}
		params.IgnoreWater = true
		local result = workspace:Raycast(originPart.Position, target - originPart.Position, params)
		if result and result.Instance ~= owner and not result.Instance:IsDescendantOf(owner) then
			return false
		end
	end
	return true
end

local function firePayload(session: AnyTable, payload: AnyTable, target: Player?)
	if not liveSession(session) then return end
	payload.Generation = session.Generation
	if target then
		if target.Parent == Players and target:GetAttribute("InRound") == true then
			session.ClientEvent:FireClient(target, payload)
		end
		return
	end
	for _, player in ipairs(Players:GetPlayers()) do
		if player:GetAttribute("InRound") == true then
			session.ClientEvent:FireClient(player, payload)
		end
	end
end

local function fireAlert(session: AnyTable, title: string, subtitle: string, instruction: string,
	duration: number, target: Player?)
	firePayload(session, {
		Type = "Alert",
		Title = title,
		Subtitle = subtitle,
		Instruction = instruction,
		Duration = duration,
	}, target)
end

local function fireSound(session: AnyTable, cue: string, position: Vector3?, target: Player?)
	firePayload(session, {
		Type = "Sound",
		Cue = cue,
		Position = position,
	}, target)
end

local function playCDCollectedSound(session: AnyTable, position: Vector3)
	if not liveSession(session) then return end
	local id = Configuration.Audio.CDCollected
	if type(id) ~= "string" or id == "" then return end

	-- Server-owned 3D emitter: every nearby player hears the same pickup from the
	-- exact CD position, while inverse rolloff keeps it inside the surrounding room.
	local emitter = Instance.new("Part")
	emitter.Name = "Level 3 CD Collection Audio Emitter"
	emitter.Size = Vector3.new(.05, .05, .05)
	emitter.CFrame = CFrame.new(position)
	emitter.Transparency = 1
	emitter.Anchored = true
	emitter.CanCollide = false
	emitter.CanTouch = false
	emitter.CanQuery = false
	emitter.CastShadow = false
	emitter:SetAttribute("Level3_CDCollectionEmitter", true)
	emitter.Parent = session.Manifest.World

	local sound = Instance.new("Sound")
	sound.Name = "Level 3 CD Collected"
	sound.SoundId = id
	sound.Volume = .58
	sound.PlaybackSpeed = 1
	sound.Looped = false
	sound.PlayOnRemove = false
	sound.RollOffMode = Enum.RollOffMode.InverseTapered
	sound.RollOffMinDistance = 5
	sound.RollOffMaxDistance = 52
	sound:SetAttribute("Level3_CDCollectionSound", true)
	sound.Parent = emitter
	sound.Ended:Once(function()
		if emitter.Parent then emitter:Destroy() end
	end)
	Debris:AddItem(emitter, 8)
	sound:Play()
end

local function fireEscapeStatus(player: Player)
	local remotes = ReplicatedStorage:FindFirstChild("Remotes")
	local roundStatus = remotes and remotes:FindFirstChild("RoundStatus")
	if not roundStatus or not roundStatus:IsA("RemoteEvent") then return end
	for _, recipient in ipairs(Players:GetPlayers()) do
		if recipient:GetAttribute("InRound") == true then
			roundStatus:FireClient(recipient, "escape", player.Name)
		end
	end
end

local function updateSharedState(session: AnyTable)
	if not liveSession(session) then return end
	local exitPosition = session.Manifest.ExitPosition
	local insertedCount = math.max(0, session.InsertedCount or session.ModuleCount or 0)
	local collectedCount = math.max(0, session.CollectedCount or 0)
	local heldCount = math.max(0, session.HeldCount or 0)
	local droppedCount = math.max(0, session.DroppedCount or 0)
	session.ModuleCount = insertedCount
	session.State:SetAttribute("Level3_ModuleProgress", insertedCount)
	session.State:SetAttribute("Level3_ModuleGoal", session.ModuleGoal)
	session.State:SetAttribute("Level3_CDCollectedProgress", collectedCount)
	session.State:SetAttribute("Level3_CDInsertedProgress", insertedCount)
	session.State:SetAttribute("Level3_CDCarriedCount", heldCount)
	session.State:SetAttribute("Level3_CDDroppedCount", droppedCount)
	session.State:SetAttribute("Level3_ExitUnlocked", session.ExitUnlocked)
	session.State:SetAttribute("Level3_ExitGuideActive", false)
	session.State:SetAttribute("Level3_ExitGuideStartRoom", "")
	session.State:SetAttribute("Level3_ExitGuideLampCount", 0)
	session.State:SetAttribute("Level3_CompletionDimDuration", Configuration.MusicSequence.CompletionDimSeconds)
	session.State:SetAttribute("Level3_ExitPosition", exitPosition)
	session.State:SetAttribute("Level3_Phase", session.ExitUnlocked and "EXIT_UNLOCKED" or "SEARCH")
	workspace:SetAttribute("Level3Modules", insertedCount)
	workspace:SetAttribute("Level3ModuleGoal", session.ModuleGoal)
	workspace:SetAttribute("Level3CDsCollected", collectedCount)
	workspace:SetAttribute("Level3CDsCarried", heldCount)
	workspace:SetAttribute("Level3CDsDropped", droppedCount)
	workspace:SetAttribute("Level3ExitUnlocked", session.ExitUnlocked)
	workspace:SetAttribute("Level3ExitGuideActive", false)
end

local function captureModuleOriginals(module: AnyTable): AnyTable
	local originals = {
		PromptEnabled = module.Prompt.Enabled,
		Objects = {},
	}
	for _, object in ipairs(module.Model:GetDescendants()) do
		if object:IsA("BasePart") then
			originals.Objects[object] = {
				Kind = "BasePart",
				Transparency = object.Transparency,
				CanCollide = object.CanCollide,
				CanTouch = object.CanTouch,
				CanQuery = object.CanQuery,
			}
		elseif object:IsA("Light") then
			originals.Objects[object] = {
				Kind = "Light",
				Enabled = object.Enabled,
				Brightness = object.Brightness,
			}
		end
	end
	return originals
end

local function restoreModule(module: AnyTable, originals: AnyTable, enablePrompt: boolean)
	if module.Model.Parent then
		module.Model:SetAttribute("Level3_Collected", false)
		module.Model:SetAttribute("Level3_CDState", "WORLD")
		module.Model:SetAttribute("Level3_CDOwnerUserId", 0)
		module.Model:SetAttribute("Level3_CDSource", true)
	end
	if module.Prompt.Parent then module.Prompt.Enabled = enablePrompt end
	for object, values in pairs(originals.Objects) do
		if object.Parent then
			if values.Kind == "BasePart" and object:IsA("BasePart") then
				object.Transparency = values.Transparency
				object.CanCollide = values.CanCollide
				object.CanTouch = values.CanTouch
				object.CanQuery = values.CanQuery
			elseif values.Kind == "Light" and object:IsA("Light") then
				object.Enabled = values.Enabled
				object.Brightness = values.Brightness
			end
		end
	end
end

local function hideCollectedModule(session: AnyTable, module: AnyTable)
	module.Prompt.Enabled = false
	module.Model:SetAttribute("Level3_Collected", true)
	-- The jewel case and illustrated cover are persistent environmental evidence.
	-- Only the physical disc and hub leave the table when the pickup succeeds.
	local originals = session.ModuleOriginals[module.Index].Objects
	for _, object in ipairs(module.PickupParts) do
		local values = originals[object]
		if object.Parent and values and values.Kind == "BasePart" and object:IsA("BasePart") then
			object.CanCollide = false
			object.CanTouch = false
			object.CanQuery = false
			playTween(session, object, TweenInfo.new(0.32, Enum.EasingStyle.Quad), {Transparency = 1})
		end
	end
end

local unlockExit: any

-- LEVEL3_TEAM_CD_RELAY_20260822
-- Every disc has exactly one authoritative state:
-- WORLD -> CARRIED -> INSERTED, with DROPPED as the recoverable death fallback.
local function heldIndices(session: AnyTable, player: Player): {number}
	local result = {}
	local held = session.HeldByPlayer[player]
	if held then
		for index, isHeld in pairs(held) do
			if isHeld then table.insert(result, index) end
		end
	end
	table.sort(result)
	return result
end

local function updatePlayerHeldAttributes(session: AnyTable, player: Player)
	local indices = heldIndices(session, player)
	local mask = 0
	for _, index in ipairs(indices) do
		mask += 2 ^ (index - 1)
	end
	player:SetAttribute("Level3_HeldCDCount", #indices)
	player:SetAttribute("Level3_HeldCDMask", mask)
end

local function destroyCarryVisual(record: AnyTable)
	local carryVisual = record.CarryVisual
	record.CarryVisual = nil
	if carryVisual and carryVisual.Parent then carryVisual:Destroy() end
end

local function configureRuntimeDiscPart(part: BasePart, anchored: boolean, queryable: boolean)
	part.Anchored = anchored
	part.Massless = not anchored
	part.CanCollide = false
	part.CanTouch = false
	part.CanQuery = queryable
	part.CastShadow = true
	part.Transparency = 0
	for _, object in ipairs(part:GetDescendants()) do
		if object:IsA("ProximityPrompt") or object:IsA("Light") then object:Destroy() end
	end
end

local function cloneDiscPair(record: AnyTable): (BasePart, BasePart)
	local sourceDisc = record.Module.PickupParts[1]
	local sourceHub = record.Module.PickupParts[2]
	assert(sourceDisc and sourceDisc:IsA("BasePart") and sourceHub and sourceHub:IsA("BasePart"),
		"Level 3 CD runtime clone requires the authored disc and hub")
	local disc = sourceDisc:Clone()
	local hub = sourceHub:Clone()
	assert(disc:IsA("BasePart") and hub:IsA("BasePart"), "Level 3 CD runtime clone produced invalid geometry")
	return disc, hub
end

local function refreshPlayerCarryVisuals(session: AnyTable, player: Player)
	for _, record in pairs(session.CDRecords) do
		if record.Owner == player then destroyCarryVisual(record) end
	end
	updatePlayerHeldAttributes(session, player)
	local character, _, _ = livingCharacter(player)
	if not character then return end
	local anchorPart = character:FindFirstChild("UpperTorso")
		or character:FindFirstChild("Torso")
		or character:FindFirstChild("HumanoidRootPart")
	if not anchorPart or not anchorPart:IsA("BasePart") then return end
	local indices = heldIndices(session, player)
	for slot, index in ipairs(indices) do
		local record = session.CDRecords[index]
		if record and record.State == "CARRIED" and record.Owner == player then
			local model = Instance.new("Model")
			model.Name = string.format("Carried Birthday Music CD %02d", index)
			model:SetAttribute("Level3_CDIndex", index)
			model:SetAttribute("Level3_CDState", "CARRIED")
			model:SetAttribute("Level3_CDOwnerUserId", player.UserId)
			model:SetAttribute("Level3_CDCarryVisual", true)
			local disc, hub = cloneDiscPair(record)
			disc.Name = "Carried CD Disc"
			hub.Name = "Carried CD Hub"
			configureRuntimeDiscPart(disc, false, false)
			configureRuntimeDiscPart(hub, false, false)
			local spread = (slot - (#indices + 1) * .5) * .42
			local fan = math.rad((slot - (#indices + 1) * .5) * 10)
			local carryCF = anchorPart.CFrame
				* CFrame.new(spread, .05 + (slot % 2) * .08, anchorPart.Size.Z * .5 + .18 + slot * .018)
				* CFrame.Angles(0, math.rad(90), fan)
			disc.CFrame = carryCF
			hub.CFrame = carryCF
			disc.Parent = model
			hub.Parent = model
			local torsoWeld = Instance.new("WeldConstraint")
			torsoWeld.Name = "Carry Weld"
			torsoWeld.Part0 = anchorPart
			torsoWeld.Part1 = disc
			torsoWeld.Parent = disc
			local hubWeld = Instance.new("WeldConstraint")
			hubWeld.Name = "Hub Weld"
			hubWeld.Part0 = disc
			hubWeld.Part1 = hub
			hubWeld.Parent = hub
			model.PrimaryPart = disc
			model.Parent = character
			record.CarryVisual = model
		end
	end
end

local function setRecordState(record: AnyTable, stateName: string, owner: Player?)
	record.State = stateName
	record.Owner = owner
	local sourceModel = record.Module.Model
	if sourceModel and sourceModel.Parent then
		sourceModel:SetAttribute("Level3_CDState", stateName)
		sourceModel:SetAttribute("Level3_CDOwnerUserId", owner and owner.UserId or 0)
	end
end

local function collectRecord(session: AnyTable, record: AnyTable, player: Player,
	prompt: ProximityPrompt, ownerInstance: Instance)
	if not record or (record.State ~= "WORLD" and record.State ~= "DROPPED") then return end
	if not canUsePrompt(player, session, prompt, ownerInstance) then return end
	local previousState = record.State
	local pickupPosition = promptWorldPosition(prompt)
	if not pickupPosition then
		if ownerInstance:IsA("Model") then
			pickupPosition = ownerInstance:GetPivot().Position
		elseif ownerInstance:IsA("BasePart") then
			pickupPosition = ownerInstance.Position
		else
			pickupPosition = session.Manifest.ExitPosition
		end
	end
	prompt.Enabled = false

	if previousState == "WORLD" then
		hideCollectedModule(session, record.Module)
	else
		session.DroppedCount = math.max(0, session.DroppedCount - 1)
		local droppedModel = record.DropModel
		record.DropModel = nil
		record.DropPrompt = nil
		if droppedModel and droppedModel.Parent then droppedModel:Destroy() end
	end

	if not record.WasCollected then
		record.WasCollected = true
		session.Collected[record.Index] = true
		session.CollectedCount += 1
	end
	setRecordState(record, "CARRIED", player)
	local playerHeld = session.HeldByPlayer[player]
	if not playerHeld then
		playerHeld = {}
		session.HeldByPlayer[player] = playerHeld
	end
	if not playerHeld[record.Index] then
		playerHeld[record.Index] = true
		session.HeldCount += 1
	end
	local _, _, root = livingCharacter(player)
	if root then session.LastKnownPositions[player] = root.Position end
	refreshPlayerCarryVisuals(session, player)
	updateSharedState(session)
	firePayload(session, {
		Type = "ModuleCollected",
		ModuleIndex = record.Index,
		CDIndex = record.Index,
		RoomId = record.Module.RoomId,
		CollectorUserId = player.UserId,
		CollectorName = player.Name,
		Progress = session.CollectedCount,
		CollectedProgress = session.CollectedCount,
		InsertedProgress = session.InsertedCount,
		Goal = session.ModuleGoal,
		RecoveredDrop = previousState == "DROPPED",
	})
	playCDCollectedSound(session, pickupPosition)
end

local function makeDroppedPickup(session: AnyTable, record: AnyTable, position: Vector3)
	local model = Instance.new("Model")
	model.Name = string.format("Dropped Birthday Music CD %02d", record.Index)
	model:SetAttribute("Level3_CDIndex", record.Index)
	model:SetAttribute("Level3_CDState", "DROPPED")
	model:SetAttribute("Level3_CDOwnerUserId", 0)
	model:SetAttribute("Level3_CDDroppedPickup", true)
	local disc, hub = cloneDiscPair(record)
	disc.Name = "Dropped CD Disc"
	hub.Name = "Dropped CD Hub"
	configureRuntimeDiscPart(disc, true, true)
	configureRuntimeDiscPart(hub, true, false)
	local dropCF = CFrame.new(position + Vector3.new(0, .16, 0)) * CFrame.Angles(0, 0, math.rad(90))
	disc.CFrame = dropCF
	hub.CFrame = dropCF
	disc.Parent = model
	hub.Parent = model
	model.PrimaryPart = disc
	model.Parent = session.RuntimeFolder

	local prompt = Instance.new("ProximityPrompt")
	prompt.Name = "CollectPrompt"
	prompt.ActionText = "PICK UP DROPPED CD"
	prompt.ObjectText = string.format("BIRTHDAY MUSIC CD %02d", record.Index)
	prompt.HoldDuration = .25
	prompt.MaxActivationDistance = 9
	prompt.RequiresLineOfSight = false
	prompt.KeyboardKeyCode = Enum.KeyCode.E
	prompt.Parent = disc
	record.DropModel = model
	record.DropPrompt = prompt
	local connection = prompt.Triggered:Connect(function(player)
		collectRecord(session, record, player, prompt, model)
	end)
	table.insert(session.Connections, connection)
end

local function groundedDropPosition(session: AnyTable, player: Player, rawPosition: Vector3): Vector3
	local params = RaycastParams.new()
	params.FilterType = Enum.RaycastFilterType.Exclude
	local filters: {Instance} = {session.RuntimeFolder}
	if player.Character then table.insert(filters, player.Character) end
	params.FilterDescendantsInstances = filters
	params.IgnoreWater = true
	local result = workspace:Raycast(rawPosition + Vector3.new(0, 3, 0), Vector3.new(0, -24, 0), params)
	return result and result.Position or rawPosition
end

local function dropHeldCDs(session: AnyTable, player: Player, rawPosition: Vector3?)
	if not liveSession(session) then return end
	local indices = heldIndices(session, player)
	if #indices == 0 then
		updatePlayerHeldAttributes(session, player)
		return
	end
	local basePosition = groundedDropPosition(session, player,
		rawPosition or session.LastKnownPositions[player] or session.Manifest.ExitPosition)
	for ordinal, index in ipairs(indices) do
		local record = session.CDRecords[index]
		if record and record.State == "CARRIED" and record.Owner == player then
			destroyCarryVisual(record)
			session.HeldCount = math.max(0, session.HeldCount - 1)
			session.DroppedCount += 1
			setRecordState(record, "DROPPED", nil)
			local angle = (ordinal - 1) * (math.pi * 2 / math.max(1, #indices))
			local offset = Vector3.new(math.cos(angle), 0, math.sin(angle)) * math.min(1.5, .45 * (#indices - 1))
			makeDroppedPickup(session, record, basePosition + offset)
		end
	end
	session.HeldByPlayer[player] = nil
	updatePlayerHeldAttributes(session, player)
	updateSharedState(session)
	firePayload(session, {
		Type = "CDDropped",
		PlayerUserId = player.UserId,
		PlayerName = player.Name,
		Count = #indices,
		Position = basePosition,
	})
end

local function transferCandidates(session: AnyTable, leavingPlayer: Player): {Player}
	local living = {}
	local fallback = {}
	for _, candidate in ipairs(Players:GetPlayers()) do
		if candidate ~= leavingPlayer and validPlayer(candidate, session) then
			table.insert(fallback, candidate)
			if livingCharacter(candidate) then table.insert(living, candidate) end
		end
	end
	return if #living > 0 then living else fallback
end

local function transferLeavingCDs(session: AnyTable, leavingPlayer: Player)
	local indices = heldIndices(session, leavingPlayer)
	if #indices == 0 then return end
	local character = leavingPlayer.Character
	local root = character and character:FindFirstChild("HumanoidRootPart")
	local lastPosition = if root and root:IsA("BasePart") then root.Position
		else session.LastKnownPositions[leavingPlayer]
	local candidates = transferCandidates(session, leavingPlayer)
	if #candidates == 0 then
		dropHeldCDs(session, leavingPlayer, lastPosition)
		return
	end

	local refreshed: {[Player]: boolean} = {}
	for _, index in ipairs(indices) do
		local record = session.CDRecords[index]
		if record and record.State == "CARRIED" and record.Owner == leavingPlayer then
			destroyCarryVisual(record)
			local recipient = candidates[session.Random:NextInteger(1, #candidates)]
			local recipientHeld = session.HeldByPlayer[recipient]
			if not recipientHeld then
				recipientHeld = {}
				session.HeldByPlayer[recipient] = recipientHeld
			end
			recipientHeld[index] = true
			setRecordState(record, "CARRIED", recipient)
			refreshed[recipient] = true
			firePayload(session, {
				Type = "CDTransferred",
				CDIndex = index,
				FromUserId = leavingPlayer.UserId,
				FromName = leavingPlayer.Name,
				RecipientUserId = recipient.UserId,
				RecipientName = recipient.Name,
			})
		end
	end
	session.HeldByPlayer[leavingPlayer] = nil
	updatePlayerHeldAttributes(session, leavingPlayer)
	for recipient in pairs(refreshed) do refreshPlayerCarryVisuals(session, recipient) end
	updateSharedState(session)
end

local function bindPlayerLifecycle(session: AnyTable, player: Player)
	local function bindCharacter(character: Model)
		task.defer(function()
			if not liveSession(session) or player.Parent ~= Players or character ~= player.Character then return end
			local humanoid = character:FindFirstChildOfClass("Humanoid")
				or character:WaitForChild("Humanoid", 5)
			if not humanoid or not humanoid:IsA("Humanoid") then return end
			local diedConnection = humanoid.Died:Connect(function()
				local root = character:FindFirstChild("HumanoidRootPart")
				dropHeldCDs(session, player, if root and root:IsA("BasePart") then root.Position else nil)
			end)
			table.insert(session.Connections, diedConnection)
			refreshPlayerCarryVisuals(session, player)
		end)
	end
	local characterConnection = player.CharacterAdded:Connect(bindCharacter)
	table.insert(session.Connections, characterConnection)
	if player.Character then bindCharacter(player.Character) end
	updatePlayerHeldAttributes(session, player)
end

local function updateDiscPlayerVisuals(session: AnyTable, animate: boolean)
	local discPlayer = session.DiscPlayer
	if not discPlayer or not discPlayer.Model or not discPlayer.Model.Parent then return end
	local insertedCount = session.InsertedCount or 0
	discPlayer.Model:SetAttribute("Level3_CDInsertedCount", insertedCount)
	discPlayer.Model:SetAttribute("Level3_CDGoal", session.ModuleGoal)
	if discPlayer.StatusLabel and discPlayer.StatusLabel.Parent then
		discPlayer.StatusLabel.Text = string.format("ZYNTRA TV/VCR RELAY  %d/%d", insertedCount, session.ModuleGoal)
	end
	if discPlayer.InstructionLabel and discPlayer.InstructionLabel.Parent then
		discPlayer.InstructionLabel.Text = if insertedCount >= session.ModuleGoal
			then "EXIT SIGNAL RESTORED" else "INSERT CDS INTO VCR"
	end
	for slotNumber, slot in ipairs(discPlayer.Slots or {}) do
		local active = slotNumber <= insertedCount
		slot.Receiver:SetAttribute("Level3_CDInserted", active)
		slot.Disc:SetAttribute("Level3_CDState", active and "INSERTED" or "EMPTY")
		slot.Disc.Transparency = active and .08 or 1
		slot.Hub.Transparency = active and .04 or 1
		slot.Indicator:SetAttribute("Level3_CDIndicatorOn", active)
		slot.Indicator.Material = active and Enum.Material.Neon or Enum.Material.SmoothPlastic
		slot.Indicator.Color = active and Color3.fromRGB(56, 255, 176) or Color3.fromRGB(20, 37, 35)
		if animate and active then
			playTween(session, slot.Indicator, TweenInfo.new(.28, Enum.EasingStyle.Back, Enum.EasingDirection.Out), {
				Transparency = .02,
			})
		else
			slot.Indicator.Transparency = active and .02 or .18
		end
		slot.Light.Enabled = active
	end
	discPlayer.Prompt.ActionText = insertedCount >= session.ModuleGoal
		and "SIGNAL RESTORED" or "INSERT CDS INTO VCR"
	discPlayer.Prompt.ObjectText = string.format("ZYNTRA TV/VCR RELAY  %d/%d", insertedCount, session.ModuleGoal)
	discPlayer.Prompt.Enabled = insertedCount < session.ModuleGoal
end

local function insertHeldCDs(session: AnyTable, player: Player)
	local discPlayer = session.DiscPlayer
	if not discPlayer or not canUsePrompt(player, session, discPlayer.Prompt, discPlayer.Model) then return end
	local indices = heldIndices(session, player)
	if #indices == 0 then
		fireAlert(session, "NO CD DETECTED", "YOU ARE NOT CARRYING A DISC",
			"FIND A PARTY MIX CD OR RECOVER A DROPPED ONE", 2.2, player)
		return
	end

	local insertedNow = {}
	for _, index in ipairs(indices) do
		local record = session.CDRecords[index]
		if record and record.State == "CARRIED" and record.Owner == player then
			destroyCarryVisual(record)
			setRecordState(record, "INSERTED", nil)
			session.HeldCount = math.max(0, session.HeldCount - 1)
			session.InsertedCount += 1
			session.ModuleCount = session.InsertedCount
			table.insert(insertedNow, index)
		end
	end
	session.HeldByPlayer[player] = nil
	updatePlayerHeldAttributes(session, player)
	updateDiscPlayerVisuals(session, true)
	updateSharedState(session)
	if #insertedNow == 0 then return end
	firePayload(session, {
		Type = "CDInserted",
		Indices = insertedNow,
		Count = #insertedNow,
		DepositorUserId = player.UserId,
		DepositorName = player.Name,
		InsertedCount = session.InsertedCount,
		Progress = session.InsertedCount,
		CollectedProgress = session.CollectedCount,
		Goal = session.ModuleGoal,
	})
	playCDCollectedSound(session, discPlayer.Position)
	if session.InsertedCount >= session.ModuleGoal then
		unlockExit(session, discPlayer.RoomId or "SignalHall")
	end
end


-- LEVEL3_COMPLETION_ESCAPE_GUIDE_DISABLED_20260824
-- The finale is deliberately lightless. These legacy marker helpers remain only
-- so older generated sessions can be normalized during cleanup; no active path calls them.
local function markNearestGuideFixture(container: Instance, target: Vector3): number
	local bestPart: BasePart? = nil
	local bestLight: SurfaceLight? = nil
	local bestDistance = math.huge
	for _, object in ipairs(container:GetDescendants()) do
		if object:IsA("BasePart") and object.Name == "Level 3 Fluorescent Diffuser" then
			local candidate = object:FindFirstChild("Level 3 Fluorescent Light")
			if candidate and candidate:IsA("SurfaceLight") then
				local distance = (object.Position - target).Magnitude
				if distance < bestDistance then
					bestDistance = distance
					bestPart = object
					bestLight = candidate
				end
			end
		end
	end
	if not bestPart or not bestLight then return 0 end
	bestPart:SetAttribute("Level3_ExitGuideLamp", true)
	bestLight:SetAttribute("Level3_ExitGuideLight", true)
	return 1
end

local function markGuideLight(light: Light?): number
	if not light or not light.Parent then return 0 end
	light:SetAttribute("Level3_ExitGuideLight", true)
	local parent = light.Parent
	if parent:IsA("BasePart") then parent:SetAttribute("Level3_ExitGuideLamp", true) end
	return 1
end

local function prepareExitGuide(session: AnyTable, startRoomId: string)
	session.ExitGuideStartRoom = ""
	session.ExitGuideCount = 0
	session.Manifest.World:SetAttribute("Level3_ExitGuideActive", false)
	session.Manifest.World:SetAttribute("Level3_ExitGuideStartRoom", "")
	session.Manifest.World:SetAttribute("Level3_ExitGuideLampCount", 0)
	if false then
		local manifest = session.Manifest
	local layout = manifest.Layout
	local exitRoomId = (layout.Roles and layout.Roles.ExitRoomId) or "Exit"
	local adjacency: {[string]: {string}} = {}
	for _, room in ipairs(layout.Rooms) do adjacency[room.Id] = {} end
	for _, link in ipairs(layout.Links) do
		if adjacency[link.A] and adjacency[link.B] then
			table.insert(adjacency[link.A], link.B)
			table.insert(adjacency[link.B], link.A)
		end
	end
	local queue = {startRoomId}
	local head = 1
	local visited = {[startRoomId] = true}
	local previous: {[string]: string} = {}
	while head <= #queue and not visited[exitRoomId] do
		local roomId = queue[head]
		head += 1
		for _, neighbor in ipairs(adjacency[roomId] or {}) do
			if not visited[neighbor] then
				visited[neighbor] = true
				previous[neighbor] = roomId
				table.insert(queue, neighbor)
			end
		end
	end

	local path = {}
	if visited[exitRoomId] then
		local cursor: string? = exitRoomId
		while cursor do
			table.insert(path, 1, cursor)
			if cursor == startRoomId then break end
			cursor = previous[cursor]
		end
	else
		path = {exitRoomId}
	end

	local guideCount = 0
	for index, roomId in ipairs(path) do
		local roomModel = manifest.Rooms[roomId]
		local nextRoom = path[index + 1] and manifest.Rooms[path[index + 1]] or nil
		local target = if nextRoom then nextRoom:GetPivot().Position else manifest.ExitPosition
		if roomModel then guideCount += markNearestGuideFixture(roomModel, target) end
		if nextRoom then
			for _, corridor in ipairs(manifest.Corridors) do
				local aId = corridor.A and corridor.A.Id
				local bId = corridor.B and corridor.B.Id
				if (aId == roomId and bId == path[index + 1])
					or (bId == roomId and aId == path[index + 1]) then
					guideCount += markNearestGuideFixture(corridor.Model, target)
					break
				end
			end
		end
	end

	guideCount += markGuideLight(manifest.ExitPortal and manifest.ExitPortal.Light or nil)
	local finalExit = manifest.FinalExit
	if finalExit and finalExit.Parent then
		for _, object in ipairs(finalExit:GetDescendants()) do
			if object:IsA("PointLight") and object.Name == "Final Exit Energon Spill" then
				guideCount += markGuideLight(object)
			end
		end
	end
	session.ExitGuideStartRoom = startRoomId
	session.ExitGuideCount = guideCount
	manifest.World:SetAttribute("Level3_ExitGuideActive", true)
	manifest.World:SetAttribute("Level3_ExitGuideStartRoom", startRoomId)
	manifest.World:SetAttribute("Level3_ExitGuideLampCount", guideCount)
	end
end

unlockExit = function(session: AnyTable, startRoomId: string)
	if session.ExitUnlocked or not validSession(session) then return end
	session.ExitUnlocked = true
	local completionStartedAt = workspace:GetServerTimeNow()
	session.State:SetAttribute("Level3_CompletionSongStartServerTime", completionStartedAt)
	session.State:SetAttribute("Level3_CompletionDimStartedAtServerTime", completionStartedAt)
	session.State:SetAttribute("Level3_CompletionDimDuration", Configuration.MusicSequence.CompletionDimSeconds)
	workspace:SetAttribute("Level3CompletionDimStartedAtServerTime", completionStartedAt)
	workspace:SetAttribute("Level3CompletionDimDuration", Configuration.MusicSequence.CompletionDimSeconds)
	session.ExitGuideStartRoom = ""
	session.ExitGuideCount = 0
	session.Manifest.World:SetAttribute("Level3_ExitGuideActive", false)
	session.Manifest.World:SetAttribute("Level3_ExitGuideStartRoom", "")
	session.Manifest.World:SetAttribute("Level3_ExitGuideLampCount", 0)
	updateSharedState(session)

	local portal = session.Manifest.ExitPortal
	portal.Model:SetAttribute("Level3_ExitUnlocked", true)
	if portal.Wall and portal.Wall.Parent then
		portal.Wall.CanCollide = false
		portal.Wall.CanTouch = false
		portal.Wall.CanQuery = true
	end
	for _, framePart in ipairs(portal.FrameParts) do
		if framePart and framePart.Parent then
			playTween(session, framePart, TweenInfo.new(0.60, Enum.EasingStyle.Quad, Enum.EasingDirection.Out), {
				Transparency = 0.08,
			})
		end
	end
	if portal.Light and portal.Light.Parent then
		portal.Light.Enabled = false
	end

	local finalExit = session.Manifest.FinalExit
	if finalExit and finalExit.Parent then
		finalExit:SetAttribute("Level3_ExitPowered", true)
		for _, object in ipairs(finalExit:GetDescendants()) do
			if object:IsA("BasePart") and (object.Name == "Final Exit Energon Rail" or object.Name == "Final Exit Lock Core") then
				playTween(session, object, TweenInfo.new(0.65, Enum.EasingStyle.Quad, Enum.EasingDirection.Out), {
					Transparency = 0.06,
				})
			elseif object:IsA("PointLight") and object.Name == "Final Exit Energon Spill" then
				object.Enabled = false
			end
		end
	end

	local escapePrompt = session.Manifest.EscapePrompt
	escapePrompt.ActionText = "ENTER FREIGHT ELEVATOR"
	escapePrompt.ObjectText = "PARTY AUDIO OVERRIDE ACCEPTED"
	escapePrompt.Enabled = true

	firePayload(session, {
		Type = "ExitUnlocked",
		Progress = session.ModuleCount,
		Goal = session.ModuleGoal,
		ExitPosition = session.Manifest.ExitPosition,
	})
	fireSound(session, "ExitUnlocked", session.Manifest.ExitPosition, nil)
end

local function collectModule(session: AnyTable, module: AnyTable, player: Player)
	local record = session.CDRecords[module.Index]
	if not record then return end
	collectRecord(session, record, player, module.Prompt, module.Model)
end

local function escapePlayer(session: AnyTable, player: Player)
	if not session.ExitUnlocked or session.Escaping[player] then return end
	local prompt = session.Manifest.EscapePrompt
	local owner = prompt.Parent
	if not owner or not canUsePrompt(player, session, prompt, owner) then return end
	local character, _, root = livingCharacter(player)
	if not character or not root then return end

	session.Escaping[player] = true
	session.EscapeOrdinal = (session.EscapeOrdinal or 0) + 1
	player:SetAttribute("Escaped", true)
	root.AssemblyLinearVelocity = Vector3.zero
	root.AssemblyAngularVelocity = Vector3.zero
	local slots = {
		Vector3.new(-6, 3, -4), Vector3.new(0, 3, -4), Vector3.new(6, 3, -4),
		Vector3.new(-6, 3, 4), Vector3.new(0, 3, 4), Vector3.new(6, 3, 4),
	}
	local slot = slots[((session.EscapeOrdinal - 1) % #slots) + 1]
	character:PivotTo(session.Manifest.ExitSafeSpawn.CFrame * CFrame.new(slot))
	fireSound(session, "Escape", session.Manifest.ExitPosition, player)
	fireEscapeStatus(player)
end

local function validateManifest(manifest: AnyTable, generation: number)
	assert(type(manifest) == "table", "Level 3 objective manifest must be a table")
	assert(type(generation) == "number" and generation == generation,
		"Level 3 objective generation must be a valid number")
	assert(manifest.World and manifest.World:IsA("Model") and manifest.World.Parent,
		"Level 3 objective manifest is missing its live World model")
	assert(manifest.Generation == generation,
		"Level 3 objective manifest generation does not match Start generation")
	assert(manifest.World:GetAttribute("Level3_Generation") == generation,
		"Level 3 world generation attribute does not match Start generation")

	assert(type(manifest.Modules) == "table" and #manifest.Modules == Configuration.ModuleGoal,
		string.format("Level 3 objective manifest must contain exactly %d modules", Configuration.ModuleGoal))
	local moduleIndexes: {[number]: boolean} = {}
	local moduleRooms: {[string]: boolean} = {}
	for _, module in ipairs(manifest.Modules) do
		assert(type(module) == "table" and type(module.Index) == "number" and module.Index % 1 == 0,
			"Level 3 objective manifest contains an invalid module record")
		assert(not moduleIndexes[module.Index], "Level 3 objective manifest has a duplicate module index")
		moduleIndexes[module.Index] = true
		assert(type(module.RoomId) == "string" and module.RoomId ~= "" and not moduleRooms[module.RoomId],
			"Level 3 objective modules must occupy unique authored rooms")
		moduleRooms[module.RoomId] = true
		assert(module.Model and module.Model:IsA("Model") and module.Model:IsDescendantOf(manifest.World),
			"Level 3 module model is missing from the generated world")
		assert(module.Prompt and module.Prompt:IsA("ProximityPrompt") and module.Prompt:IsDescendantOf(module.Model),
			"Level 3 module is missing its ProximityPrompt")
		assert(module.Core and module.Core:IsA("BasePart") and module.Core:IsDescendantOf(module.Model),
			"Level 3 CD is missing its jewel case core")
		assert(module.Pedestal and module.Pedestal:IsA("BasePart") and module.Pedestal:IsDescendantOf(module.Model),
			"Level 3 CD is missing its placement marker")
		assert(type(module.PickupParts) == "table" and #module.PickupParts == 2,
			"Level 3 CD must expose exactly the disc and hub as pickup visuals")
		for _, pickupPart in ipairs(module.PickupParts) do
			assert(pickupPart:IsA("BasePart") and pickupPart:IsDescendantOf(module.Model)
				and pickupPart:GetAttribute("Level3_CDPickupVisual") == true,
				"Level 3 CD pickup visual is invalid")
		end
	end

	assert(type(manifest.Doors) == "table",
		"Level 3 objective manifest door records must be a table")
	assert(#manifest.Doors == 0,
		"Level 3 Revision 3 is doorless; unexpected door records in the manifest")
	local portal = manifest.ExitPortal
	assert(type(portal) == "table" and portal.Model and portal.Model:IsA("Model")
		and portal.Model:IsDescendantOf(manifest.World),
		"Level 3 objective manifest is missing its hidden exit portal")
	assert(portal.Wall and portal.Wall:IsA("BasePart") and portal.Wall:IsDescendantOf(portal.Model),
		"Level 3 hidden exit portal is missing its wall")
	assert(portal.Wall.CanCollide == true and portal.Wall.CanQuery == true,
		"Level 3 hidden exit wall must begin solid and ray-queryable")
	assert(type(portal.FrameParts) == "table" and #portal.FrameParts == 8,
		"Level 3 hidden exit portal must contain eight reveal-frame pieces")
	for _, framePart in ipairs(portal.FrameParts) do
		assert(framePart:IsA("BasePart") and framePart:IsDescendantOf(portal.Model)
			and framePart.Material == Enum.Material.Neon and framePart.Transparency >= 0.99,
			"Level 3 hidden exit reveal frame is invalid")
	end
	local discPlayer = manifest.DiscPlayer or portal.DiscPlayer
	assert(type(discPlayer) == "table" and discPlayer.Model and discPlayer.Model:IsA("Model")
		and discPlayer.Model:IsDescendantOf(manifest.World),
		"Level 3 objective manifest is missing its Signal Hall disc player")
	assert(discPlayer.Prompt and discPlayer.Prompt:IsA("ProximityPrompt")
		and discPlayer.Prompt:IsDescendantOf(discPlayer.Model),
		"Level 3 disc player is missing its insert prompt")
	assert(typeof(discPlayer.Position) == "Vector3",
		"Level 3 disc player position must be a Vector3")
	assert(type(discPlayer.Slots) == "table" and #discPlayer.Slots == Configuration.ModuleGoal,
		"Level 3 disc player must expose exactly five receiver slots")
	for expectedIndex, slot in ipairs(discPlayer.Slots) do
		assert(type(slot) == "table" and slot.Index == expectedIndex,
			"Level 3 disc player slot order is invalid")
		assert(slot.Receiver and slot.Receiver:IsA("BasePart") and slot.Receiver:IsDescendantOf(discPlayer.Model),
			"Level 3 disc player receiver is missing")
		assert(slot.Disc and slot.Disc:IsA("BasePart") and slot.Disc:IsDescendantOf(discPlayer.Model)
			and slot.Disc.Transparency >= .99,
			"Level 3 disc player inserted-disc visual must begin hidden")
		assert(slot.Hub and slot.Hub:IsA("BasePart") and slot.Hub:IsDescendantOf(discPlayer.Model)
			and slot.Hub.Transparency >= .99,
			"Level 3 disc player inserted hub must begin hidden")
		assert(slot.Indicator and slot.Indicator:IsA("BasePart")
			and slot.Indicator:IsDescendantOf(discPlayer.Model),
			"Level 3 disc player indicator is missing")
		assert(slot.Light and slot.Light:IsA("Light") and slot.Light:IsDescendantOf(slot.Indicator)
			and not slot.Light.Enabled,
			"Level 3 disc player indicator light must begin off")
	end
	assert(manifest.EscapePrompt and manifest.EscapePrompt:IsA("ProximityPrompt")
		and manifest.EscapePrompt:IsDescendantOf(manifest.World),
		"Level 3 final escape prompt is missing from the generated world")
	assert(manifest.ExitSafeSpawn and manifest.ExitSafeSpawn:IsA("BasePart")
		and manifest.ExitSafeSpawn:IsDescendantOf(manifest.World),
		"Level 3 exit safe spawn is missing from the generated world")
	assert(typeof(manifest.ExitPosition) == "Vector3", "Level 3 exit position must be a Vector3")
	local finalHall = manifest.FinalHall
	assert(type(finalHall) == "table" and finalHall.Model and finalHall.Model:IsA("Model")
		and finalHall.Model:IsDescendantOf(manifest.World),
		"Level 3 objective manifest is missing its final hall")
	assert(typeof(finalHall.StartPoint) == "Vector3" and typeof(finalHall.EndPoint) == "Vector3"
		and typeof(finalHall.Forward) == "Vector3" and type(finalHall.Length) == "number"
		and finalHall.Length >= Configuration.Layout.ExitCorridorLength - .1,
		"Level 3 final hall geometry is invalid")
	assert(finalHall.HalfwayMarker and finalHall.HalfwayMarker:IsA("BasePart")
		and finalHall.HalfwayMarker:GetAttribute("Level3_FinalHallHalfway") == true,
		"Level 3 final hall halfway marker is missing")
	assert(finalHall.SpawnMarker and finalHall.SpawnMarker:IsA("BasePart")
		and finalHall.SpawnMarker:GetAttribute("Level3_MallManagerFinaleSpawn") == true,
		"Level 3 final hall Manager spawn marker is missing")
end

local function scheduleIntro(session: AnyTable)
	local function fireIntro()
		if not validSession(session) then return end
		fireAlert(session, "PARTY MUSIC OVERRIDE REQUIRED",
			string.format("%d PARTY MIX CDS MUST REACH THE RELAY", session.ModuleGoal),
			"CARRY YOUR CDS TO THE DISC PLAYER BESIDE THE FALSE WALL", 3.8, nil)
	end
	if validSession(session) then
		session.IntroScheduled = true
		task.delay(2.0, fireIntro)
		return
	end
	local roundConnection: RBXScriptConnection?
	local levelConnection: RBXScriptConnection?
	local function scheduleWhenReady()
		if session.IntroScheduled or not validSession(session) then return end
		session.IntroScheduled = true
		disconnect(roundConnection)
		disconnect(levelConnection)
		task.delay(3.0, fireIntro)
	end
	roundConnection = workspace:GetAttributeChangedSignal("RoundActive"):Connect(scheduleWhenReady)
	levelConnection = workspace:GetAttributeChangedSignal("SelectedLevel"):Connect(scheduleWhenReady)
	table.insert(session.Connections, roundConnection)
	table.insert(session.Connections, levelConnection)
	scheduleWhenReady()
end

function ObjectiveController.Start(manifest: AnyTable, generation: number): AnyTable
	ObjectiveController.Stop()
	validateManifest(manifest, generation)
	local stateFolder, clientEvent = getInfrastructure()
	local runtimeFolder = Instance.new("Folder")
	runtimeFolder.Name = "Level 3 Runtime CDs"
	runtimeFolder:SetAttribute("Level3_RuntimeCDFolder", true)
	runtimeFolder.Parent = manifest.World
	local session: AnyTable = {
		Manifest = manifest,
		Generation = generation,
		State = stateFolder,
		ClientEvent = clientEvent,
		Connections = {},
		Tweens = {},
		ModuleOriginals = {},
		Collected = {},
		CDRecords = {},
		HeldByPlayer = {},
		LastKnownPositions = {},
		RuntimeFolder = runtimeFolder,
		Random = Random.new(math.floor(math.abs(generation)) % 2147483647),
		CollectedCount = 0,
		InsertedCount = 0,
		HeldCount = 0,
		DroppedCount = 0,
		ModuleCount = 0,
		ModuleGoal = #manifest.Modules,
		ExitUnlocked = false,
		ExitGuideStartRoom = "",
		ExitGuideCount = 0,
		FinalHallCrossed = {},
		FinalHallChaseTriggered = false,
		FinalHallEligibleCount = 0,
		FinalHallCrossedCount = 0,
		FinalHallAccumulator = 0,
		Escaping = {},
		EscapeOrdinal = 0,
		IntroScheduled = false,
	}
	activeSession = session

	for _, module in ipairs(manifest.Modules) do
		session.ModuleOriginals[module.Index] = captureModuleOriginals(module)
		restoreModule(module, session.ModuleOriginals[module.Index], true)
		session.CDRecords[module.Index] = {
			Index = module.Index,
			Module = module,
			State = "WORLD",
			Owner = nil,
			WasCollected = false,
			CarryVisual = nil,
			DropModel = nil,
			DropPrompt = nil,
		}
		local connection = module.Prompt.Triggered:Connect(function(player)
			collectModule(session, module, player)
		end)
		table.insert(session.Connections, connection)
	end

	local portal = manifest.ExitPortal
	session.DiscPlayer = manifest.DiscPlayer or portal.DiscPlayer
	updateDiscPlayerVisuals(session, false)
	local insertConnection = session.DiscPlayer.Prompt.Triggered:Connect(function(player)
		insertHeldCDs(session, player)
	end)
	table.insert(session.Connections, insertConnection)
	for _, player in ipairs(Players:GetPlayers()) do bindPlayerLifecycle(session, player) end
	table.insert(session.Connections, Players.PlayerAdded:Connect(function(player)
		bindPlayerLifecycle(session, player)
	end))
	table.insert(session.Connections, Players.PlayerRemoving:Connect(function(player)
		transferLeavingCDs(session, player)
		session.FinalHallCrossed[player] = nil
	end))
	table.insert(session.Connections, RunService.Heartbeat:Connect(function(dt)
		if not liveSession(session) then return end
		session.FinalHallAccumulator += dt
		if session.FinalHallAccumulator < .10 then return end
		session.FinalHallAccumulator = 0
		updateFinalHallChase(session)
	end))

	session.State:SetAttribute("Level3_FinalHallEligibleCount", 0)
	session.State:SetAttribute("Level3_FinalHallCrossedCount", 0)
	session.State:SetAttribute("Level3_FinalHallChaseTriggered", false)
	session.State:SetAttribute("Level3_FinalHallChaseActive", false)
	manifest.World:SetAttribute("Level3_FinalHallEligibleCount", 0)
	manifest.World:SetAttribute("Level3_FinalHallCrossedCount", 0)
	manifest.World:SetAttribute("Level3_FinalHallChaseTriggered", false)
	manifest.World:SetAttribute("Level3_FinalHallChaseActive", false)
	workspace:SetAttribute("Level3FinalHallEligibleCount", 0)
	workspace:SetAttribute("Level3FinalHallCrossedCount", 0)
	workspace:SetAttribute("Level3FinalHallChaseTriggered", false)
	workspace:SetAttribute("Level3FinalHallChaseActive", false)
	workspace:SetAttribute("Level3CompletionDimStartedAtServerTime", 0)
	workspace:SetAttribute("Level3CompletionDimDuration", Configuration.MusicSequence.CompletionDimSeconds)
	portal.Model:SetAttribute("Level3_ExitUnlocked", false)
	portal.Wall.CanCollide = true
	portal.Wall.CanTouch = false
	portal.Wall.CanQuery = true
	for _, framePart in ipairs(portal.FrameParts) do framePart.Transparency = 1 end
	if portal.Light then portal.Light.Enabled = false end

	local finalExit = manifest.FinalExit
	if finalExit and finalExit.Parent then
		finalExit:SetAttribute("Level3_ExitPowered", false)
		for _, object in ipairs(finalExit:GetDescendants()) do
			if object:IsA("BasePart") and (object.Name == "Final Exit Energon Rail" or object.Name == "Final Exit Lock Core") then
				object.Transparency = 1
			elseif object:IsA("PointLight") and object.Name == "Final Exit Energon Spill" then
				object.Enabled = false
			end
		end
	end
	local escapePrompt = manifest.EscapePrompt
	session.EscapePromptOriginal = {
		Enabled = escapePrompt.Enabled,
		ActionText = escapePrompt.ActionText,
		ObjectText = escapePrompt.ObjectText,
	}
	escapePrompt.Enabled = false
	escapePrompt.ActionText = "CD OVERRIDE REQUIRED"
	escapePrompt.ObjectText = "PARTY AUDIO-LOCKED SERVICE EXIT"
	local escapeConnection = escapePrompt.Triggered:Connect(function(player)
		escapePlayer(session, player)
	end)
	table.insert(session.Connections, escapeConnection)

	session.State:SetAttribute("Level3_CompletionSongStartServerTime", 0)
	updateSharedState(session)
	-- RoundUI owns the full radio briefing and synchronized subtitles.
	-- Keep the persistent CD HUD and all later objective alerts, but do not
	-- overlap the spoken opening with the former timed intro toast.
	return session
end

function ObjectiveController.Stop()
	local session = activeSession
	if not session then return end
	activeSession = nil
	disconnectAll(session)
	cancelTweens(session)

	for _, record in pairs(session.CDRecords or {}) do
		destroyCarryVisual(record)
		if record.DropModel and record.DropModel.Parent then record.DropModel:Destroy() end
	end
	if session.RuntimeFolder and session.RuntimeFolder.Parent then session.RuntimeFolder:Destroy() end
	for _, player in ipairs(Players:GetPlayers()) do
		player:SetAttribute("Level3_HeldCDCount", 0)
		player:SetAttribute("Level3_HeldCDMask", 0)
	end
	session.InsertedCount = 0
	session.ModuleCount = 0
	if session.DiscPlayer and session.DiscPlayer.Model and session.DiscPlayer.Model.Parent then
		updateDiscPlayerVisuals(session, false)
		session.DiscPlayer.Prompt.Enabled = false
	end

	for _, module in ipairs(session.Manifest.Modules) do
		local originals = session.ModuleOriginals[module.Index]
		if originals then restoreModule(module, originals, false) end
	end

	local finalExit = session.Manifest.FinalExit
	if finalExit and finalExit.Parent then
		finalExit:SetAttribute("Level3_ExitPowered", false)
		for _, object in ipairs(finalExit:GetDescendants()) do
			if object:IsA("BasePart") and (object.Name == "Final Exit Energon Rail" or object.Name == "Final Exit Lock Core") then
				object.Transparency = 1
			elseif object:IsA("PointLight") and object.Name == "Final Exit Energon Spill" then
				object.Enabled = false
			end
		end
	end
	local escapePrompt = session.Manifest.EscapePrompt
	if escapePrompt and escapePrompt.Parent then
		escapePrompt.Enabled = session.EscapePromptOriginal.Enabled
		escapePrompt.ActionText = session.EscapePromptOriginal.ActionText
		escapePrompt.ObjectText = session.EscapePromptOriginal.ObjectText
	end

	local portal = session.Manifest.ExitPortal
	if portal then
		if portal.Model and portal.Model.Parent then portal.Model:SetAttribute("Level3_ExitUnlocked", false) end
		if portal.Wall and portal.Wall.Parent then
			portal.Wall.CanCollide = true
			portal.Wall.CanTouch = false
			portal.Wall.CanQuery = true
		end
		for _, framePart in ipairs(portal.FrameParts or {}) do
			if framePart and framePart.Parent then framePart.Transparency = 1 end
		end
		if portal.Light and portal.Light.Parent then portal.Light.Enabled = false end
	end

	for _, object in ipairs(session.Manifest.World:GetDescendants()) do
		if object:GetAttribute("Level3_ExitGuideLight") ~= nil then object:SetAttribute("Level3_ExitGuideLight", nil) end
		if object:GetAttribute("Level3_ExitGuideLamp") ~= nil then object:SetAttribute("Level3_ExitGuideLamp", nil) end
	end
	if session.Manifest.World.Parent then
		session.Manifest.World:SetAttribute("Level3_ExitGuideActive", false)
		session.Manifest.World:SetAttribute("Level3_ExitGuideStartRoom", "")
		session.Manifest.World:SetAttribute("Level3_ExitGuideLampCount", 0)
	end

	if session.State and session.State.Parent then
		session.State:SetAttribute("Level3_ModuleProgress", 0)
		session.State:SetAttribute("Level3_ModuleGoal", 0)
		session.State:SetAttribute("Level3_CDCollectedProgress", 0)
		session.State:SetAttribute("Level3_CDInsertedProgress", 0)
		session.State:SetAttribute("Level3_CDCarriedCount", 0)
		session.State:SetAttribute("Level3_CDDroppedCount", 0)
		session.State:SetAttribute("Level3_ExitUnlocked", false)
		session.State:SetAttribute("Level3_CompletionSongStartServerTime", 0)
		session.State:SetAttribute("Level3_CompletionDimStartedAtServerTime", 0)
		session.State:SetAttribute("Level3_CompletionDimDuration", Configuration.MusicSequence.CompletionDimSeconds)
		session.State:SetAttribute("Level3_FinalHallEligibleCount", 0)
		session.State:SetAttribute("Level3_FinalHallCrossedCount", 0)
		session.State:SetAttribute("Level3_FinalHallChaseTriggered", false)
		session.State:SetAttribute("Level3_FinalHallChaseActive", false)
		session.State:SetAttribute("Level3_MallManagerHuntActive", false)
		session.State:SetAttribute("Level3_ExitGuideActive", false)
		session.State:SetAttribute("Level3_ExitGuideStartRoom", "")
		session.State:SetAttribute("Level3_ExitGuideLampCount", 0)
		session.State:SetAttribute("Level3_ExitPosition", nil)
		session.State:SetAttribute("Level3_Phase", "STOPPED")
	end
	workspace:SetAttribute("Level3Modules", 0)
	workspace:SetAttribute("Level3ModuleGoal", 0)
	workspace:SetAttribute("Level3CDsCollected", 0)
	workspace:SetAttribute("Level3CDsCarried", 0)
	workspace:SetAttribute("Level3CDsDropped", 0)
	workspace:SetAttribute("Level3ExitUnlocked", false)
	workspace:SetAttribute("Level3ExitGuideActive", false)
	workspace:SetAttribute("Level3CompletionDimStartedAtServerTime", 0)
	workspace:SetAttribute("Level3CompletionDimDuration", Configuration.MusicSequence.CompletionDimSeconds)
	workspace:SetAttribute("Level3FinalHallEligibleCount", 0)
	workspace:SetAttribute("Level3FinalHallCrossedCount", 0)
	workspace:SetAttribute("Level3FinalHallChaseTriggered", false)
	workspace:SetAttribute("Level3FinalHallChaseActive", false)
	workspace:SetAttribute("Level3MallManagerHuntActive", false)
end

-- Studio-only deterministic hooks keep multiplayer lifecycle regressions testable
-- without exposing any client RemoteEvent or production bypass.
function ObjectiveController.DebugCollectCD(player: Player, index: number): boolean
	if not RunService:IsStudio() then return false end
	local session = activeSession
	local record = session and session.CDRecords[index]
	if not session or not record then return false end
	local prompt = if record.State == "DROPPED" then record.DropPrompt else record.Module.Prompt
	local owner = if record.State == "DROPPED" then record.DropModel else record.Module.Model
	if not prompt or not owner then return false end
	collectRecord(session, record, player, prompt, owner)
	return record.State == "CARRIED" and record.Owner == player
end

function ObjectiveController.DebugInsertHeldCDs(player: Player): number
	if not RunService:IsStudio() then return 0 end
	local session = activeSession
	if not session then return 0 end
	insertHeldCDs(session, player)
	return session.InsertedCount
end

function ObjectiveController.DebugDropHeldCDs(player: Player, position: Vector3?): number
	if not RunService:IsStudio() then return 0 end
	local session = activeSession
	if not session then return 0 end
	dropHeldCDs(session, player, position)
	return session.DroppedCount
end

function ObjectiveController.DebugEvaluateFinalHallChase(): AnyTable?
	if not RunService:IsStudio() then return nil end
	local session = activeSession
	if not session then return nil end
	updateFinalHallChase(session)
	return ObjectiveController.GetSnapshot()
end

function ObjectiveController.GetSnapshot(): AnyTable?
	local session = activeSession
	if not session then return nil end
	return {
		Generation = session.Generation,
		ModuleProgress = session.InsertedCount,
		ModuleGoal = session.ModuleGoal,
		CollectedProgress = session.CollectedCount,
		InsertedProgress = session.InsertedCount,
		CarriedCount = session.HeldCount,
		DroppedCount = session.DroppedCount,
		ExitUnlocked = session.ExitUnlocked,
		FinalHallEligibleCount = session.FinalHallEligibleCount,
		FinalHallCrossedCount = session.FinalHallCrossedCount,
		FinalHallChaseTriggered = session.FinalHallChaseTriggered,
	}
end

return ObjectiveController