--!strict
-- Level 3 Objective Controller
--
-- Server authority for the abandoned mall objective:
--   * five shared Energon Resonance Modules;
--   * every interactive, locked, and final-access door;
--   * final service-exit activation and per-player escape;
--   * replicated progress used by the reader, audio, and HUD clients.
--
-- World construction stays in Level 3 World Builder. This module only consumes
-- its manifest, validates every reference, and owns one disposable round session.

local Players = game:GetService("Players")
local ReplicatedStorage = game:GetService("ReplicatedStorage")
local TweenService = game:GetService("TweenService")

local Configuration = require(script.Parent:WaitForChild("Level 3 Configuration"))

type AnyTable = {[any]: any}

local ObjectiveController = {}
local activeSession: AnyTable? = nil

local DOOR_MOVE_TIME = 0.55
local DOOR_LOCK_COOLDOWN = 0.8
local DOOR_BLOCK_DEPTH = 4.5
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
	for _, runtime in pairs(session.DoorRuntime) do
		disconnect(runtime.CompletionConnection)
		runtime.CompletionConnection = nil
	end
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
	session.State:SetAttribute("Level3_ModuleProgress", session.ModuleCount)
	session.State:SetAttribute("Level3_ModuleGoal", session.ModuleGoal)
	session.State:SetAttribute("Level3_ExitUnlocked", session.ExitUnlocked)
	session.State:SetAttribute("Level3_ExitPosition", exitPosition)
	session.State:SetAttribute("Level3_Phase", session.ExitUnlocked and "EXIT_UNLOCKED" or "SEARCH")
	workspace:SetAttribute("Level3Modules", session.ModuleCount)
	workspace:SetAttribute("Level3ModuleGoal", session.ModuleGoal)
	workspace:SetAttribute("Level3ExitUnlocked", session.ExitUnlocked)
end

local function findDoorHandle(record: AnyTable): BasePart?
	local handle = record.Model:FindFirstChild("Handle", true)
	return if handle and handle:IsA("BasePart") then handle else nil
end

local function setDoorPrompt(runtime: AnyTable)
	local record = runtime.Record
	local prompt = record.Prompt
	if record.Type == "Locked" then
		prompt.ActionText = "TRY HANDLE"
	else
		prompt.ActionText = runtime.IsOpen and "CLOSE" or "OPEN"
	end
end

local function playEmbeddedSound(record: AnyTable, soundName: string): boolean
	local sound = record.Leaf:FindFirstChild(soundName)
	if sound and sound:IsA("Sound") then
		sound:Stop()
		sound.TimePosition = 0
		sound:Play()
		return true
	end
	return false
end

local function doorwayOccupied(record: AnyTable): boolean
	local params = OverlapParams.new()
	params.FilterType = Enum.RaycastFilterType.Exclude
	params.FilterDescendantsInstances = {record.Model}
	params.MaxParts = 100
	local size = Vector3.new(
		Configuration.DoorWidth + 2,
		Configuration.DoorHeight + 2,
		DOOR_BLOCK_DEPTH
	)
	for _, hit in ipairs(workspace:GetPartBoundsInBox(record.Closed, size, params)) do
		local character = hit:FindFirstAncestorOfClass("Model")
		local player = character and Players:GetPlayerFromCharacter(character)
		if player then
			local liveCharacter = livingCharacter(player)
			if liveCharacter == character then return true end
		end
	end
	return false
end

local function completeDoorMovement(session: AnyTable, runtime: AnyTable, token: number, opened: boolean)
	if not liveSession(session) or runtime.MoveToken ~= token then return end
	local record = runtime.Record
	-- A player may enter during the tween. Re-open instead of letting a closing
	-- collidable leaf intersect their character.
	if not opened and doorwayOccupied(record) then
		runtime.IsOpen = true
		runtime.Busy = false
		record.Leaf.CFrame = record.Open
		if runtime.Handle and runtime.Handle.Parent then
			runtime.Handle.CFrame = record.Open * runtime.HandleLocal
		end
		record.Leaf.CanCollide = false
		record.Model:SetAttribute("Level3_DoorOpen", true)
		record.Model:SetAttribute("Level3_DoorState", "OPEN")
		setDoorPrompt(runtime)
		record.Prompt.Enabled = true
		return
	end
	runtime.IsOpen = opened
	runtime.Busy = false
	record.Leaf.CanCollide = if opened then false else runtime.LeafCanCollide
	record.Model:SetAttribute("Level3_DoorOpen", opened)
	record.Model:SetAttribute("Level3_DoorState", opened and "OPEN" or "CLOSED")
	setDoorPrompt(runtime)
	record.Prompt.Enabled = true
end

local function moveDoor(session: AnyTable, runtime: AnyTable, player: Player)
	if runtime.Busy then return end
	local record = runtime.Record
	local opening = not runtime.IsOpen
	if not opening and doorwayOccupied(record) then
		fireAlert(session, "DOORWAY BLOCKED", "CLEAR THE SERVICE DOOR", "MOVE AWAY BEFORE CLOSING", 1.2, player)
		return
	end
	runtime.Busy = true
	runtime.MoveToken += 1
	local token = runtime.MoveToken
	record.Prompt.Enabled = false
	-- Leaves are non-colliding while animated so they cannot wedge a player.
	record.Leaf.CanCollide = false
	record.Model:SetAttribute("Level3_DoorState", "MOVING")
	playEmbeddedSound(record, "Door Movement")
	local target = opening and record.Open or record.Closed
	local info = TweenInfo.new(DOOR_MOVE_TIME, Enum.EasingStyle.Quad, Enum.EasingDirection.InOut)
	local leafTween = playTween(session, record.Leaf, info, {CFrame = target})
	if runtime.Handle and runtime.Handle.Parent then
		playTween(session, runtime.Handle, info, {CFrame = target * runtime.HandleLocal})
	end
	disconnect(runtime.CompletionConnection)
	if not leafTween then
		completeDoorMovement(session, runtime, token, opening)
		return
	end
	runtime.CompletionConnection = leafTween.Completed:Connect(function(playbackState)
		disconnect(runtime.CompletionConnection)
		runtime.CompletionConnection = nil
		if playbackState == Enum.PlaybackState.Completed then
			completeDoorMovement(session, runtime, token, opening)
		elseif liveSession(session) and runtime.MoveToken == token then
			runtime.Busy = false
			record.Leaf.CanCollide = if runtime.IsOpen then false else runtime.LeafCanCollide
			setDoorPrompt(runtime)
			record.Prompt.Enabled = true
		end
	end)
end

local function lockedDoorFeedback(session: AnyTable, runtime: AnyTable, player: Player)
	local now = os.clock()
	local previous = runtime.LastLockedAt[player] or -math.huge
	if runtime.Busy or now - previous < DOOR_LOCK_COOLDOWN then return end
	runtime.LastLockedAt[player] = now
	runtime.Busy = true
	runtime.MoveToken += 1
	local token = runtime.MoveToken
	local record = runtime.Record
	record.Prompt.Enabled = false
	record.Model:SetAttribute("Level3_DoorState", "LOCKED_RESPONSE")
	if not playEmbeddedSound(record, "Locked Handle Rattle") then
		fireSound(session, "DoorLocked", record.Leaf.Position, player)
	end
	local shake = record.Closed * CFrame.new(0, 0, -0.10) * CFrame.Angles(0, math.rad(1.4), 0)
	local outInfo = TweenInfo.new(0.075, Enum.EasingStyle.Quad, Enum.EasingDirection.Out)
	playTween(session, record.Leaf, outInfo, {CFrame = shake})
	if runtime.Handle and runtime.Handle.Parent then
		playTween(session, runtime.Handle, outInfo, {CFrame = shake * runtime.HandleLocal * CFrame.Angles(0, 0, math.rad(14))})
	end

	fireAlert(session, "STAFF ACCESS", "LOCKED FROM THE OTHER SIDE", "FIND ANOTHER ROUTE", 1.25, player)

	task.delay(0.09, function()
		if not liveSession(session) or runtime.MoveToken ~= token then return end
		local backInfo = TweenInfo.new(0.12, Enum.EasingStyle.Quad, Enum.EasingDirection.InOut)
		playTween(session, record.Leaf, backInfo, {CFrame = record.Closed})
		if runtime.Handle and runtime.Handle.Parent then
			playTween(session, runtime.Handle, backInfo, {CFrame = record.Closed * runtime.HandleLocal})
		end
		task.delay(0.13, function()
			if not liveSession(session) or runtime.MoveToken ~= token then return end
			runtime.Busy = false
			record.Model:SetAttribute("Level3_DoorState", "LOCKED")
			setDoorPrompt(runtime)
			record.Prompt.Enabled = true
		end)
	end)
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
	if module.Model.Parent then module.Model:SetAttribute("Level3_Collected", false) end
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
	for object, values in pairs(session.ModuleOriginals[module.Index].Objects) do
		if object.Parent then
			if values.Kind == "BasePart" and object:IsA("BasePart") and object ~= module.Pedestal then
				object.CanCollide = false
				object.CanTouch = false
				object.CanQuery = false
				playTween(session, object, TweenInfo.new(0.32, Enum.EasingStyle.Quad), {Transparency = 1})
			elseif values.Kind == "Light" and object:IsA("Light") then
				playTween(session, object, TweenInfo.new(0.24, Enum.EasingStyle.Quad), {Brightness = 0})
				task.delay(0.25, function()
					if liveSession(session) and object.Parent and object:IsA("Light") then object.Enabled = false end
				end)
			end
		end
	end
end

local function unlockExit(session: AnyTable)
	if session.ExitUnlocked or not validSession(session) then return end
	session.ExitUnlocked = true
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
		portal.Light.Enabled = true
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
				object.Enabled = true
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
	if session.Collected[module.Index] then return end
	if not canUsePrompt(player, session, module.Prompt, module.Model) then return end

	-- This assignment is the one-shot lock. Prompt callbacks cannot increment the
	-- shared count twice even if several players finish the hold simultaneously.
	session.Collected[module.Index] = true
	session.ModuleCount += 1
	hideCollectedModule(session, module)
	updateSharedState(session)

	firePayload(session, {
		Type = "ModuleCollected",
		ModuleIndex = module.Index,
		CDIndex = module.Index,
		RoomId = module.RoomId,
		CollectorUserId = player.UserId,
		CollectorName = player.Name,
		Progress = session.ModuleCount,
		Goal = session.ModuleGoal,
	})

	if session.ModuleCount >= session.ModuleGoal then
		unlockExit(session)
	end
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
	end

	assert(type(manifest.Doors) == "table",
		"Level 3 objective manifest door records must be a table")
	local doorIds: {[string]: boolean} = {}
	for _, record in ipairs(manifest.Doors) do
		assert(type(record) == "table" and type(record.Id) == "string" and record.Id ~= "",
			"Level 3 objective manifest contains an invalid door record")
		assert(not doorIds[record.Id], "Level 3 objective manifest has a duplicate door id")
		doorIds[record.Id] = true
		assert(record.Type == "Openable" or record.Type == "Locked",
			"Level 3 door record has an unsupported type: " .. tostring(record.Type))
		assert(record.Model and record.Model:IsA("Model") and record.Model:IsDescendantOf(manifest.World),
			"Level 3 door model is missing from the generated world")
		assert(record.Leaf and record.Leaf:IsA("BasePart") and record.Leaf:IsDescendantOf(record.Model),
			"Level 3 door is missing its leaf")
		assert(record.Prompt and record.Prompt:IsA("ProximityPrompt") and record.Prompt:IsDescendantOf(record.Model),
			"Level 3 door is missing its ProximityPrompt")
		assert(typeof(record.Closed) == "CFrame" and typeof(record.Open) == "CFrame",
			"Level 3 door is missing closed/open transforms")
	end
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
	assert(manifest.EscapePrompt and manifest.EscapePrompt:IsA("ProximityPrompt")
		and manifest.EscapePrompt:IsDescendantOf(manifest.World),
		"Level 3 final escape prompt is missing from the generated world")
	assert(manifest.ExitSafeSpawn and manifest.ExitSafeSpawn:IsA("BasePart")
		and manifest.ExitSafeSpawn:IsDescendantOf(manifest.World),
		"Level 3 exit safe spawn is missing from the generated world")
	assert(typeof(manifest.ExitPosition) == "Vector3", "Level 3 exit position must be a Vector3")
end

local function scheduleIntro(session: AnyTable)
	local function fireIntro()
		if not validSession(session) then return end
		fireAlert(session, "PARTY MUSIC OVERRIDE REQUIRED",
			string.format("%d PARTY MIX CDS STILL PLAYING", session.ModuleGoal),
			"COLLECT EVERY CD TO STOP THE LOOP AND REVEAL THE EXIT", 3.4, nil)
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
	local session: AnyTable = {
		Manifest = manifest,
		Generation = generation,
		State = stateFolder,
		ClientEvent = clientEvent,
		Connections = {},
		Tweens = {},
		DoorRuntime = {},
		ModuleOriginals = {},
		Collected = {},
		ModuleCount = 0,
		ModuleGoal = #manifest.Modules,
		ExitUnlocked = false,
		Escaping = {},
		EscapeOrdinal = 0,
		IntroScheduled = false,
	}
	activeSession = session

	for _, record in ipairs(manifest.Doors) do
		local handle = findDoorHandle(record)
		local runtime: AnyTable = {
			Session = session,
			Record = record,
			Handle = handle,
			HandleLocal = if handle then record.Closed:ToObjectSpace(handle.CFrame) else CFrame.identity,
			LeafColor = record.Leaf.Color,
			LeafMaterial = record.Leaf.Material,
			LeafCanCollide = record.Leaf.CanCollide,
			IsOpen = false,
			Busy = false,
			MoveToken = 0,
			LastLockedAt = setmetatable({}, {__mode = "k"}),
			CompletionConnection = nil,
		}
		session.DoorRuntime[record.Id] = runtime
		record.Leaf.CFrame = record.Closed
		if handle then handle.CFrame = record.Closed * runtime.HandleLocal end
		record.Model:SetAttribute("Level3_DoorOpen", false)
		record.Model:SetAttribute("Level3_DoorState", record.Type == "Locked" and "LOCKED" or "CLOSED")
		setDoorPrompt(runtime)
		record.Prompt.Enabled = true
		local connection = record.Prompt.Triggered:Connect(function(player)
			if not canUsePrompt(player, session, record.Prompt, record.Model) then return end
			if record.Type == "Locked" then
				lockedDoorFeedback(session, runtime, player)
			else
				moveDoor(session, runtime, player)
			end
		end)
		table.insert(session.Connections, connection)
	end

	for _, module in ipairs(manifest.Modules) do
		session.ModuleOriginals[module.Index] = captureModuleOriginals(module)
		restoreModule(module, session.ModuleOriginals[module.Index], true)
		local connection = module.Prompt.Triggered:Connect(function(player)
			collectModule(session, module, player)
		end)
		table.insert(session.Connections, connection)
	end

	local portal = manifest.ExitPortal
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

	updateSharedState(session)
	scheduleIntro(session)
	return session
end

function ObjectiveController.Stop()
	local session = activeSession
	if not session then return end
	activeSession = nil
	disconnectAll(session)
	cancelTweens(session)

	for _, runtime in pairs(session.DoorRuntime) do
		local record = runtime.Record
		if record.Leaf and record.Leaf.Parent then
			record.Leaf.CFrame = record.Closed
			record.Leaf.Color = runtime.LeafColor
			record.Leaf.Material = runtime.LeafMaterial
			record.Leaf.CanCollide = runtime.LeafCanCollide
		end
		if runtime.Handle and runtime.Handle.Parent then
			runtime.Handle.CFrame = record.Closed * runtime.HandleLocal
		end
		if record.Prompt and record.Prompt.Parent then record.Prompt.Enabled = false end
		if record.Model and record.Model.Parent then
			record.Model:SetAttribute("Level3_DoorOpen", false)
			record.Model:SetAttribute("Level3_DoorState", "INACTIVE")
		end
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

	if session.State and session.State.Parent then
		session.State:SetAttribute("Level3_ModuleProgress", 0)
		session.State:SetAttribute("Level3_ModuleGoal", 0)
		session.State:SetAttribute("Level3_ExitUnlocked", false)
		session.State:SetAttribute("Level3_ExitPosition", nil)
		session.State:SetAttribute("Level3_Phase", "STOPPED")
	end
	workspace:SetAttribute("Level3Modules", 0)
	workspace:SetAttribute("Level3ModuleGoal", 0)
	workspace:SetAttribute("Level3ExitUnlocked", false)
end

function ObjectiveController.GetSnapshot(): AnyTable?
	local session = activeSession
	if not session then return nil end
	return {
		Generation = session.Generation,
		ModuleProgress = session.ModuleCount,
		ModuleGoal = session.ModuleGoal,
		ExitUnlocked = session.ExitUnlocked,
	}
end

return ObjectiveController
