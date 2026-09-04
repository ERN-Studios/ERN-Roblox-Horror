--!strict
-- Level 3 Hiding Controller
-- Server-authoritative under-table hiding with prompt validation, occupancy,
-- character restoration, and lifecycle cleanup.

local Players = game:GetService("Players")
local ReplicatedStorage = game:GetService("ReplicatedStorage")
local RunService = game:GetService("RunService")

local Configuration = require(script.Parent:WaitForChild("Level 3 Configuration"))
local Tuning = Configuration.Hiding
local TableCheckTuning = Configuration.TableCheck

local Controller = {}
local activeSession: any = nil

-- Slot 1 sits on the anchor's -X side, slot 2 on +X, both inside the 8.6-stud
-- hide volume. Body pose, camera point and exit lane all use the same number so
-- two occupants never share a spot.
-- ponytail: two lanes hard-coded, matching HideOccupantCap = 2. A larger cap
-- needs a real lane layout here, not another sign flip.
local function slotLateral(slot: number): number
	return (if slot % 2 == 1 then -1 else 1) * Tuning.HideOccupantLateralOffset
end

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

local function roundAllowsHiding(session: any): boolean
	return liveSession(session)
		and session.FurnitureSuspended ~= true
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

-- Level3_HideOccupiedUserId names the FIRST occupant and stays the only
-- occupancy attribute on the anchor: hide anchors are Level3_PermanentFurniture
-- and the furniture audit treats every other attribute on them as identity, so
-- a second one would read as furniture being tampered with. Anything the
-- clients need beyond "someone is under there" is published in the state folder.
local function occupantsOf(session: any, anchor: BasePart): {Player}
	return session.Occupants[anchor] or {}
end

local function refreshPrompt(session: any, anchor: BasePart)
	local prompt = promptFor(anchor)
	if not prompt then return end
	local occupants = occupantsOf(session, anchor)
	anchor:SetAttribute("Level3_HideOccupiedUserId",
		if #occupants > 0 then (occupants[1] :: Player).UserId else 0)
	prompt.Enabled = roundAllowsHiding(session) and #occupants < Tuning.HideOccupantCap
end

local function refreshPrompts(session: any)
	for _, anchor in ipairs(session.Anchors) do
		if anchor.Parent then refreshPrompt(session, anchor) end
	end
end

-- The hidden character stays replicated and visible. Only physical collision is
-- suppressed while its anchored rig is folded inside the table; transparency,
-- textures, particles, and lights are deliberately untouched.
local function captureCollisionState(character: Model): {any}
	local saved = {}
	for _, object in ipairs(character:GetDescendants()) do
		if object:IsA("BasePart") then
			table.insert(saved, {
				Object=object,
				CanCollide=object.CanCollide,
				CanTouch=object.CanTouch,
				CanQuery=object.CanQuery,
			})
		end
	end
	return saved
end

local function suppressCollision(saved: {any})
	for _, record in ipairs(saved) do
		local object = record.Object
		if object and object.Parent and object:IsA("BasePart") then
			object.CanCollide = false
			object.CanTouch = false
			object.CanQuery = false
		end
	end
end

local function restoreCollision(saved: {any})
	for _, record in ipairs(saved) do
		local object = record.Object
		if object and object.Parent and object:IsA("BasePart") then
			object.CanCollide = record.CanCollide
			object.CanTouch = record.CanTouch
			object.CanQuery = record.CanQuery
		end
	end
end

local function releasePlayer(session: any, player: Player, moveOutside: boolean): boolean
	local record = session.HiddenPlayers[player]
	if not record then
		if player.Parent == Players then
			player:SetAttribute("Level3_Hiding", false)
			player:SetAttribute("Level3_HideTableIndex", 0)
			player:SetAttribute("Level3_HideCameraPosition", nil)
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

	restoreCollision(record.CollisionState)
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
	local occupants = session.Occupants[record.Anchor]
	if occupants then
		local index = table.find(occupants, player)
		if index then table.remove(occupants, index) end
	end
	if player.Parent == Players then
		player:SetAttribute("Level3_Hiding", false)
		player:SetAttribute("Level3_HideTableIndex", 0)
		player:SetAttribute("Level3_HideGeneration", 0)
		player:SetAttribute("Level3_HideCameraPosition", nil)
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
	local occupants = session.Occupants[anchor]
	if not occupants then return false, "INVALID_TABLE" end
	if #occupants >= Tuning.HideOccupantCap then return false, "OCCUPIED" end
	local now = os.clock()
	if now - (session.LastAction[player] or -math.huge) < Tuning.ActionCooldownSeconds then
		return false, "COOLDOWN"
	end
	local character, humanoid, root = eligible(player, session)
	if not character or not humanoid or not root then return false, "INELIGIBLE" end
	if (root.Position - anchor.Position).Magnitude > Tuning.PromptMaxDistance + Tuning.ServerDistanceSlack then
		return false, "TOO_FAR"
	end

	-- Lowest free lane, so a released occupant's slot is reused rather than
	-- leaving a permanent gap under a table that still looks half empty.
	local usedSlots: {[number]: boolean} = {}
	for _, occupant in ipairs(occupants) do
		local occupantRecord = session.HiddenPlayers[occupant]
		if occupantRecord then usedSlots[occupantRecord.Slot] = true end
	end
	local slot: number? = nil
	for candidate = 1, Tuning.HideOccupantCap do
		if not usedSlots[candidate] then slot = candidate break end
	end
	if not slot then return false, "OCCUPIED" end

	session.LastAction[player] = now
	local lateral = slotLateral(slot)
	local localPosition = anchor.CFrame:PointToObjectSpace(root.Position)
	local exitSide = if localPosition.Z >= 0 then 1 else -1
	local sideRotation = CFrame.Angles(0, if exitSide > 0 then math.pi else 0, 0)
	local exitCFrame = anchor.CFrame
		* CFrame.new(lateral, Tuning.ExitVerticalOffset, exitSide * Tuning.ExitOffsetZ)
		* sideRotation
	-- The lateral offset is applied in ANCHOR space, before the facing rotation,
	-- so slot 1 is always the same physical side of the table no matter which
	-- way the player crawled in from.
	local hiddenCFrame = anchor.CFrame * CFrame.new(lateral, 0, 0) * sideRotation
	local cameraPosition = anchor.CFrame:PointToWorldSpace(Vector3.new(lateral, -0.45, 0))
	local collisionState = captureCollisionState(character)
	local record = {
		Player=player, Character=character, Humanoid=humanoid, Root=root, Anchor=anchor,
		Slot=slot,
		Generation=session.Generation, ExitCFrame=exitCFrame, CollisionState=collisionState,
		AutoRotate=humanoid.AutoRotate, WalkSpeed=humanoid.WalkSpeed,
		JumpPower=humanoid.JumpPower, JumpHeight=humanoid.JumpHeight,
		DisplayDistanceType=humanoid.DisplayDistanceType, RootAnchored=root.Anchored,
	}
	-- Reserve first; no yield occurs between reservation and the replicated state edge.
	session.HiddenPlayers[player] = record
	table.insert(occupants, player)
	refreshPrompt(session, anchor)

	character:PivotTo(hiddenCFrame)
	root.AssemblyLinearVelocity = Vector3.zero
	root.AssemblyAngularVelocity = Vector3.zero
	root.Anchored = true
	humanoid.AutoRotate = false
	humanoid.WalkSpeed = 0
	humanoid.JumpPower = 0
	humanoid.JumpHeight = 0
	humanoid.DisplayDistanceType = Enum.HumanoidDisplayDistanceType.None
	suppressCollision(collisionState)

	player:SetAttribute("BeingChased", false)
	player:SetAttribute("Level3_HideGeneration", session.Generation)
	player:SetAttribute("Level3_HideTableIndex",
		tonumber(anchor:GetAttribute("Level3_HideTableIndex")) or 0)
	-- Replicated before the state edge so the local camera cannot spend one
	-- visible frame above the tabletop.
	player:SetAttribute("Level3_HideCameraPosition", cameraPosition)
	player:SetAttribute("Level3_Hiding", true)
	updateHiddenCount(session)
	return true, "HIDDEN"
end

local function bindPlayer(session: any, player: Player)
	player:SetAttribute("Level3_Hiding", false)
	player:SetAttribute("Level3_HideTableIndex", 0)
	player:SetAttribute("Level3_HideGeneration", 0)
	player:SetAttribute("Level3_HideCameraPosition", nil)
	table.insert(session.Connections, player.CharacterRemoving:Connect(function(character)
		local record = session.HiddenPlayers[player]
		if record and record.Character == character then releasePlayer(session, player, false) end
	end))
	table.insert(session.Connections, player.CharacterAdded:Connect(function(character)
		if not liveSession(session) then return end
		player:SetAttribute("Level3_Hiding", false)
		player:SetAttribute("Level3_HideTableIndex", 0)
		player:SetAttribute("Level3_HideGeneration", 0)
		player:SetAttribute("Level3_HideCameraPosition", nil)
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

function Controller.SetFurnitureSuspended(active: boolean): boolean
	local session = activeSession
	if not session or not liveSession(session) then return false end
	session.FurnitureSuspended = active == true
	if session.FurnitureSuspended then releaseAll(session, true) end
	refreshPrompts(session)
	return true
end

function Controller.Stop()
	local session = activeSession
	if not session then
		for _, player in ipairs(Players:GetPlayers()) do
			player:SetAttribute("Level3_Hiding", false)
			player:SetAttribute("Level3_HideTableIndex", 0)
			player:SetAttribute("Level3_HideGeneration", 0)
			player:SetAttribute("Level3_HideCameraPosition", nil)
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
		FurnitureSuspended=false,
		Anchors={}, AnchorSet={}, Occupants={}, HiddenPlayers={}, LastAction={}, Connections={},
		-- Set by FlushAnchor. A flushed player is refused by the Mall Manager's
		-- attack checks until this clock, so being found is a head start.
		FlushImmuneUntil={},
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
		-- Every valid anchor owns a list from the start, so "no list" means
		-- "not one of ours" everywhere below instead of "empty".
		session.Occupants[anchor] = {}
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
		session.FlushImmuneUntil[player] = nil
	end))
	for _, player in ipairs(Players:GetPlayers()) do bindPlayer(session, player) end
	refreshPrompts(session)
	updateHiddenCount(session)
	return session
end

-- How many players are under one anchor right now. 0 also covers "not a live
-- anchor of the running session", which is what every caller wants.
function Controller.OccupantCount(anchor: BasePart): number
	local session = activeSession
	if not session or not liveSession(session) then return 0 end
	return #occupantsOf(session, anchor)
end

-- Anchors holding at least one hidden player, in authored anchor order so the
-- Mall Manager's candidate list is deterministic for a given seed.
function Controller.GetOccupiedAnchors(generation: number?): {BasePart}
	local result = {}
	local session = activeSession
	if not session or not liveSession(session) then return result end
	if generation ~= nil and session.Generation ~= generation then return result end
	for _, anchor in ipairs(session.Anchors) do
		if anchor.Parent and #occupantsOf(session, anchor) > 0 then
			table.insert(result, anchor)
		end
	end
	return result
end

-- The end of the Mall Manager's table check. Reuses releasePlayer's exact
-- restore path with moveOutside; the only differences are the exit lane, forced
-- to the side of the table AWAY from `awayFrom`, and the short immunity every
-- flushed player carries out with them. Returns who was actually ejected.
function Controller.FlushAnchor(anchor: BasePart, awayFrom: Vector3?): {Player}
	local flushed = {}
	local session = activeSession
	if not session or not liveSession(session) then return flushed end
	local occupants = session.Occupants[anchor]
	if not occupants or #occupants == 0 or not anchor.Parent then return flushed end
	-- Server time, not os.clock: os.clock is CPU time in the server datamodel and
	-- runs materially behind the wall clock, so a 1.5 "second" head start measured
	-- on it is not 1.5 seconds of running. The Manager's reaction window is on the
	-- same clock, so the promise the player is shown is the promise enforced.
	-- LastAction and the anchor cooldowns stay on os.clock: nobody is shown those.
	local now = workspace:GetServerTimeNow()
	-- releasePlayer mutates the list, so iterate a copy.
	for _, player in ipairs(table.clone(occupants)) do
		local record = session.HiddenPlayers[player]
		if record then
			if awayFrom then
				local localPosition = anchor.CFrame:PointToObjectSpace(awayFrom)
				local exitSide = if localPosition.Z >= 0 then -1 else 1
				local sideRotation = CFrame.Angles(0, if exitSide > 0 then math.pi else 0, 0)
				record.ExitCFrame = anchor.CFrame
					* CFrame.new(slotLateral(record.Slot or 1), Tuning.ExitVerticalOffset,
						exitSide * Tuning.ExitOffsetZ)
					* sideRotation
			end
			session.FlushImmuneUntil[player] = now + TableCheckTuning.FlushImmunitySeconds
			if releasePlayer(session, player, true) then table.insert(flushed, player) end
		end
	end
	return flushed
end

function Controller.IsFlushImmune(player: Player): boolean
	local session = activeSession
	if not session or not liveSession(session) then return false end
	local expiry = session.FlushImmuneUntil[player]
	return expiry ~= nil and workspace:GetServerTimeNow() < expiry
end

function Controller.GetSnapshot()
	local session = activeSession
	if not session then return nil end
	local occupied = 0
	for _, occupants in pairs(session.Occupants) do
		if #occupants > 0 then occupied += 1 end
	end
	return {
		Generation=session.Generation,
		HiddenCount=(function()
			local count = 0
			for _ in pairs(session.HiddenPlayers) do count += 1 end
			return count
		end)(),
		TableCount=#session.Anchors,
		OccupiedCount=occupied,
		OccupantCap=Tuning.HideOccupantCap,
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
