--!strict
-- Level 3 Hiding Controller
-- Server-authoritative under-table hiding with prompt validation, occupancy,
-- character restoration, and lifecycle cleanup.

local Players = game:GetService("Players")
local ReplicatedStorage = game:GetService("ReplicatedStorage")
local RunService = game:GetService("RunService")

local Configuration = require(script.Parent:WaitForChild("Level 3 Configuration"))
local Tuning = Configuration.Hiding

local Controller = {}
local activeSession: any = nil

local function disconnect(connection: RBXScriptConnection?)
	if connection and connection.Connected then connection:Disconnect() end
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

-- Hiding is available for the whole Level 3 round. The blackout and the Mall
-- Manager hunt deliberately do NOT suspend it: furniture is permanent, so a
-- player who is under a table stays under that table through the hunt, which is
-- the point of hiding. The old SetFurnitureSuspended entry point ejected every
-- hidden player and disabled the prompts exactly when they mattered most.
local function roundAllowsHiding(session: any): boolean
	return liveSession(session)
		and workspace:GetAttribute("SelectedLevel") == 3
		and workspace:GetAttribute("RoundActive") == true
end

local function promptFor(anchor: BasePart): ProximityPrompt?
	local prompt = anchor:FindFirstChild("HideUnderTablePrompt")
	return if prompt and prompt:IsA("ProximityPrompt") then prompt else nil
end

local function characterState(player: Player): (Model?, Humanoid?, BasePart?)
	local character = player.Character
	local humanoid = character and character:FindFirstChildOfClass("Humanoid")
	local root = character and character:FindFirstChild("HumanoidRootPart")
	if not character or not character.Parent or not humanoid or humanoid.Health <= 0
		or not root or not root:IsA("BasePart") then
		return nil, nil, nil
	end
	return character, humanoid, root
end

local function eligible(player: Player, session: any): (Model?, Humanoid?, BasePart?)
	if not roundAllowsHiding(session)
		or player.Parent ~= Players
		or player:GetAttribute("InRound") ~= true
		or player:GetAttribute("Escaped") == true then
		return nil, nil, nil
	end
	return characterState(player)
end

local function updateHiddenCount(session: any)
	local count = 0
	for _ in pairs(session.HiddenPlayers) do count += 1 end
	local state = ReplicatedStorage:FindFirstChild(Configuration.StateFolderName)
	if state and state:IsA("Folder") then state:SetAttribute("Level3_HiddenPlayers", count) end
	workspace:SetAttribute("Level3HiddenPlayers", count)
end

local function refreshPrompt(session: any, anchor: BasePart)
	local prompt = promptFor(anchor)
	if not prompt then return end
	local occupied = session.Occupants[anchor] ~= nil
	anchor:SetAttribute("Level3_HideOccupiedUserId",
		if occupied then (session.Occupants[anchor] :: Player).UserId else 0)
	prompt.Enabled = roundAllowsHiding(session) and not occupied
end

local function refreshPrompts(session: any)
	for _, anchor in ipairs(session.Anchors) do
		if anchor.Parent then refreshPrompt(session, anchor) end
	end
end

local function captureAppearance(character: Model): {any}
	local saved = {}
	for _, object in ipairs(character:GetDescendants()) do
		if object:IsA("BasePart") then
			table.insert(saved, {
				Object=object, Kind="BasePart", Transparency=object.Transparency,
				CanCollide=object.CanCollide, CanTouch=object.CanTouch, CanQuery=object.CanQuery,
			})
		elseif object:IsA("Decal") or object:IsA("Texture") then
			table.insert(saved, {Object=object, Kind="Transparency", Transparency=object.Transparency})
		elseif object:IsA("Light") or object:IsA("ParticleEmitter")
			or object:IsA("Trail") or object:IsA("Beam") then
			table.insert(saved, {Object=object, Kind="Enabled", Enabled=object.Enabled})
		end
	end
	return saved
end

local function concealAppearance(saved: {any})
	for _, record in ipairs(saved) do
		local object = record.Object
		if object and object.Parent then
			if record.Kind == "BasePart" and object:IsA("BasePart") then
				object.Transparency = 1
				object.CanCollide = false
				object.CanTouch = false
				object.CanQuery = false
			elseif record.Kind == "Transparency"
				and (object:IsA("Decal") or object:IsA("Texture")) then
				object.Transparency = 1
			elseif record.Kind == "Enabled"
				and (object:IsA("Light") or object:IsA("ParticleEmitter")
					or object:IsA("Trail") or object:IsA("Beam")) then
				object.Enabled = false
			end
		end
	end
end

local function restoreAppearance(saved: {any})
	for _, record in ipairs(saved) do
		local object = record.Object
		if object and object.Parent then
			if record.Kind == "BasePart" and object:IsA("BasePart") then
				object.Transparency = record.Transparency
				object.CanCollide = record.CanCollide
				object.CanTouch = record.CanTouch
				object.CanQuery = record.CanQuery
			elseif record.Kind == "Transparency"
				and (object:IsA("Decal") or object:IsA("Texture")) then
				object.Transparency = record.Transparency
			elseif record.Kind == "Enabled"
				and (object:IsA("Light") or object:IsA("ParticleEmitter")
					or object:IsA("Trail") or object:IsA("Beam")) then
				object.Enabled = record.Enabled
			end
		end
	end
end

local function releasePlayer(session: any, player: Player, moveOutside: boolean): boolean
	local record = session.HiddenPlayers[player]
	if not record then
		if player.Parent == Players then
			player:SetAttribute("Level3_Hiding", false)
			player:SetAttribute("Level3_HideTableIndex", 0)
		end
		return false
	end

	local character = record.Character
	local humanoid = record.Humanoid
	local root = record.Root
	if moveOutside and character and character.Parent and root and root.Parent then
		character:PivotTo(record.ExitCFrame)
		root.AssemblyLinearVelocity = Vector3.zero
		root.AssemblyAngularVelocity = Vector3.zero
	end

	restoreAppearance(record.Appearance)
	if humanoid and humanoid.Parent then
		humanoid.AutoRotate = record.AutoRotate
		humanoid.WalkSpeed = record.WalkSpeed
		humanoid.JumpPower = record.JumpPower
		humanoid.JumpHeight = record.JumpHeight
		humanoid.DisplayDistanceType = record.DisplayDistanceType
	end
	if root and root.Parent then
		root.Anchored = record.RootAnchored
		root.AssemblyLinearVelocity = Vector3.zero
		root.AssemblyAngularVelocity = Vector3.zero
	end

	session.HiddenPlayers[player] = nil
	if session.Occupants[record.Anchor] == player then session.Occupants[record.Anchor] = nil end
	if player.Parent == Players then
		player:SetAttribute("Level3_Hiding", false)
		player:SetAttribute("Level3_HideTableIndex", 0)
		player:SetAttribute("Level3_HideGeneration", 0)
	end
	if record.Anchor and record.Anchor.Parent then refreshPrompt(session, record.Anchor) end
	updateHiddenCount(session)
	return true
end

local function releaseAll(session: any, moveOutside: boolean)
	local players = {}
	for player in pairs(session.HiddenPlayers) do table.insert(players, player) end
	for _, player in ipairs(players) do releasePlayer(session, player, moveOutside) end
end

local function tryEnter(session: any, player: Player, anchor: BasePart): (boolean, string)
	if not roundAllowsHiding(session) then return false, "ROUND_INACTIVE" end
	if not session.AnchorSet[anchor] or not anchor.Parent or not anchor:IsDescendantOf(session.World) then
		return false, "INVALID_TABLE"
	end
	if session.HiddenPlayers[player] then return false, "ALREADY_HIDDEN" end
	if session.Occupants[anchor] then return false, "OCCUPIED" end
	local now = os.clock()
	if now - (session.LastAction[player] or -math.huge) < Tuning.ActionCooldownSeconds then
		return false, "COOLDOWN"
	end
	local character, humanoid, root = eligible(player, session)
	if not character or not humanoid or not root then return false, "INELIGIBLE" end
	if (root.Position - anchor.Position).Magnitude > Tuning.PromptMaxDistance + Tuning.ServerDistanceSlack then
		return false, "TOO_FAR"
	end

	session.LastAction[player] = now
	local localPosition = anchor.CFrame:PointToObjectSpace(root.Position)
	local exitSide = if localPosition.Z >= 0 then 1 else -1
	local exitCFrame = anchor.CFrame * CFrame.new(0, Tuning.ExitVerticalOffset, exitSide * Tuning.ExitOffsetZ)
	local appearance = captureAppearance(character)
	local record = {
		Player=player, Character=character, Humanoid=humanoid, Root=root, Anchor=anchor,
		Generation=session.Generation, ExitCFrame=exitCFrame, Appearance=appearance,
		AutoRotate=humanoid.AutoRotate, WalkSpeed=humanoid.WalkSpeed,
		JumpPower=humanoid.JumpPower, JumpHeight=humanoid.JumpHeight,
		DisplayDistanceType=humanoid.DisplayDistanceType, RootAnchored=root.Anchored,
	}
	-- Reserve first; no yield occurs between reservation and the replicated state edge.
	session.HiddenPlayers[player] = record
	session.Occupants[anchor] = player
	refreshPrompt(session, anchor)

	character:PivotTo(anchor.CFrame)
	root.AssemblyLinearVelocity = Vector3.zero
	root.AssemblyAngularVelocity = Vector3.zero
	root.Anchored = true
	humanoid.AutoRotate = false
	humanoid.WalkSpeed = 0
	humanoid.JumpPower = 0
	humanoid.JumpHeight = 0
	humanoid.DisplayDistanceType = Enum.HumanoidDisplayDistanceType.None
	concealAppearance(appearance)

	player:SetAttribute("BeingChased", false)
	player:SetAttribute("Level3_HideGeneration", session.Generation)
	player:SetAttribute("Level3_HideTableIndex",
		tonumber(anchor:GetAttribute("Level3_HideTableIndex")) or 0)
	player:SetAttribute("Level3_Hiding", true)
	updateHiddenCount(session)
	return true, "HIDDEN"
end

local function bindPlayer(session: any, player: Player)
	player:SetAttribute("Level3_Hiding", false)
	player:SetAttribute("Level3_HideTableIndex", 0)
	player:SetAttribute("Level3_HideGeneration", 0)
	table.insert(session.Connections, player.CharacterRemoving:Connect(function(character)
		local record = session.HiddenPlayers[player]
		if record and record.Character == character then releasePlayer(session, player, false) end
	end))
	table.insert(session.Connections, player.CharacterAdded:Connect(function(character)
		if not liveSession(session) then return end
		player:SetAttribute("Level3_Hiding", false)
		player:SetAttribute("Level3_HideTableIndex", 0)
		player:SetAttribute("Level3_HideGeneration", 0)
		local humanoid = character:FindFirstChildOfClass("Humanoid")
		if humanoid then
			table.insert(session.Connections, humanoid.Died:Connect(function()
				releasePlayer(session, player, false)
			end))
		end
	end))
	table.insert(session.Connections, player:GetAttributeChangedSignal("Escaped"):Connect(function()
		if player:GetAttribute("Escaped") == true then releasePlayer(session, player, false) end
	end))
	table.insert(session.Connections, player:GetAttributeChangedSignal("InRound"):Connect(function()
		if player:GetAttribute("InRound") ~= true then releasePlayer(session, player, false) end
	end))
	local character = player.Character
	local humanoid = character and character:FindFirstChildOfClass("Humanoid")
	if humanoid then
		table.insert(session.Connections, humanoid.Died:Connect(function()
			releasePlayer(session, player, false)
		end))
	end
end

function Controller.IsHidden(player: Player, generation: number?): boolean
	local session = activeSession
	if not session or not liveSession(session) then return false end
	if generation ~= nil and session.Generation ~= generation then return false end
	local record = session.HiddenPlayers[player]
	return record ~= nil
		and record.Generation == session.Generation
		and record.Character == player.Character
		and record.Anchor ~= nil
		and record.Anchor.Parent ~= nil
		and player:GetAttribute("Level3_Hiding") == true
end

function Controller.Stop()
	local session = activeSession
	if not session then
		for _, player in ipairs(Players:GetPlayers()) do
			player:SetAttribute("Level3_Hiding", false)
			player:SetAttribute("Level3_HideTableIndex", 0)
			player:SetAttribute("Level3_HideGeneration", 0)
		end
		workspace:SetAttribute("Level3HiddenPlayers", 0)
		return
	end
	activeSession = nil
	session.Active = false
	releaseAll(session, true)
	for _, connection in ipairs(session.Connections) do disconnect(connection) end
	for _, anchor in ipairs(session.Anchors) do
		if anchor.Parent then
			local prompt = promptFor(anchor)
			if prompt then prompt.Enabled = false end
			anchor:SetAttribute("Level3_HideOccupiedUserId", 0)
		end
	end
	local state = ReplicatedStorage:FindFirstChild(Configuration.StateFolderName)
	if state and state:IsA("Folder") then state:SetAttribute("Level3_HiddenPlayers", 0) end
	workspace:SetAttribute("Level3HiddenPlayers", 0)
end

function Controller.Start(manifest: any, generation: number)
	Controller.Stop()
	assert(type(manifest) == "table" and manifest.World and manifest.World:IsA("Model")
		and manifest.World.Parent == workspace, "Level 3 hiding requires a live world")
	assert(manifest.World:GetAttribute("Level3_Generation") == generation,
		"Level 3 hiding generation mismatch")
	assert(type(manifest.HideTables) == "table" and #manifest.HideTables > 0,
		"Level 3 hiding requires authored table anchors")

	local remotes = ReplicatedStorage:WaitForChild(Configuration.RemotesFolderName)
	local request = remotes:WaitForChild(Configuration.HideRequestEventName)
	assert(request:IsA("RemoteEvent"), "Level 3 hide request remote is missing")

	local session: any = {
		Active=true, Generation=generation, Manifest=manifest, World=manifest.World,
		Anchors={}, AnchorSet={}, Occupants={}, HiddenPlayers={}, LastAction={}, Connections={},
	}
	activeSession = session
	for _, anchor in ipairs(manifest.HideTables) do
		assert(anchor:IsA("BasePart") and anchor:IsDescendantOf(manifest.World)
			and anchor:GetAttribute("Level3_HideTableAnchor") == true,
			"Level 3 hide table anchor is invalid")
		local prompt = promptFor(anchor)
		assert(prompt, "Level 3 hide table is missing its prompt")
		table.insert(session.Anchors, anchor)
		session.AnchorSet[anchor] = true
		table.insert(session.Connections, (prompt :: ProximityPrompt).Triggered:Connect(function(player)
			tryEnter(session, player, anchor)
		end))
	end

	table.insert(session.Connections, (request :: RemoteEvent).OnServerEvent:Connect(function(player, command)
		if command ~= "EXIT" then return end
		local now = os.clock()
		if now - (session.LastAction[player] or -math.huge) < Tuning.ActionCooldownSeconds then return end
		session.LastAction[player] = now
		releasePlayer(session, player, true)
	end))
	table.insert(session.Connections, workspace:GetAttributeChangedSignal("RoundActive"):Connect(function()
		if workspace:GetAttribute("RoundActive") ~= true then releaseAll(session, true) end
		refreshPrompts(session)
	end))
	table.insert(session.Connections, workspace:GetAttributeChangedSignal("SelectedLevel"):Connect(function()
		if workspace:GetAttribute("SelectedLevel") ~= 3 then releaseAll(session, true) end
		refreshPrompts(session)
	end))
	table.insert(session.Connections, Players.PlayerAdded:Connect(function(player) bindPlayer(session, player) end))
	table.insert(session.Connections, Players.PlayerRemoving:Connect(function(player)
		releasePlayer(session, player, false)
		session.LastAction[player] = nil
	end))
	for _, player in ipairs(Players:GetPlayers()) do bindPlayer(session, player) end
	refreshPrompts(session)
	updateHiddenCount(session)
	return session
end

function Controller.GetSnapshot()
	local session = activeSession
	if not session then return nil end
	local occupied = 0
	for _ in pairs(session.Occupants) do occupied += 1 end
	return {
		Generation=session.Generation,
		HiddenCount=(function()
			local count = 0
			for _ in pairs(session.HiddenPlayers) do count += 1 end
			return count
		end)(),
		TableCount=#session.Anchors,
		OccupiedCount=occupied,
	}
end

function Controller.DebugEnter(player: Player, anchor: BasePart): (boolean, string)
	assert(RunService:IsStudio(), "DebugEnter is Studio-only")
	local session = activeSession
	if not session then return false, "NOT_RUNNING" end
	return tryEnter(session, player, anchor)
end

function Controller.DebugExit(player: Player): boolean
	assert(RunService:IsStudio(), "DebugExit is Studio-only")
	local session = activeSession
	return session ~= nil and releasePlayer(session, player, true)
end

return Controller
