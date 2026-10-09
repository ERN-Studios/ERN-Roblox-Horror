-- Developer-only functional preview. Isolated from GameManager and public level progression.
local Players = game:GetService("Players")
local ReplicatedStorage = game:GetService("ReplicatedStorage")
local HttpService = game:GetService("HttpService")
local ServerStorage = game:GetService("ServerStorage")
local WorldStorage = require(script.Parent:WaitForChild("LevelWorldStorage"))
local DevAccess = require(ReplicatedStorage:WaitForChild("DevAccess"))
local MODEL_NAME, EXIT_NAME = "Level 6 Indoor Playground", "Level6Exit"
-- 2026-10-03: Level 6 is the static Indoor Playground map (tools/level6_playground). The generated
-- Level 3 copy in "Level 6 Systems" is no longer launched from here; its modules are left in place.
local IN_PREVIEW = "Level6PlaygroundPreview"
local Runtime = {}
function Runtime.EnsureWorld()
	local model = WorldStorage.Get(6)
	return model, model and model:FindFirstChild(EXIT_NAME, true)
end
-- The hide-and-seek round (the counting child) lives in "Level 6 Playground Game".
local Playground = require(script.Parent:WaitForChild("Level 6 Systems"):WaitForChild("Level 6 Playground Game"))
function Runtime.Leave(player, died)
	local was = player:GetAttribute(IN_PREVIEW) == true
	if Runtime.DropEntry then Runtime.DropEntry(player) end
	player:SetAttribute(IN_PREVIEW, nil)
	if was then player:SetAttribute("InRound", false) end
	Playground.RemovePlayer(player)
	if Runtime.Emptied then Runtime.Emptied() end              -- PARTY_LOCK_20261008: the last one out frees the level
	if was and player.Parent == Players then
		-- the same word GameManager sends a player it stands back up in the lobby: RoundUI clears its round state on it
		local remotes = ReplicatedStorage:FindFirstChild("Remotes")
		local status = remotes and remotes:FindFirstChild("RoundStatus")
		if status then status:FireClient(player, "lobby") end
	end
	if was and not died and player.Parent == Players then
		-- Back into the player's own avatar at the lobby spawn. A death is respawned by GameManager.
		task.spawn(function()
			local load = ServerStorage:FindFirstChild("LoadLobbyCharacter")
			if load then pcall(load.Invoke, load, player) end
		end)
	end
end
-- PARTY_LOCK_20261008 (owner, from the live game: "everyone ends up in the same Level 6: one queues with at most 2
-- and another queues later with 3 and they all join the same one"). This level is ONE map with ONE session per
-- server, and the game module puts every later arrival into the session that is already running. Until a party
-- gets a server of its own, the level takes ONE PARTY AT A TIME: a queue launch, an E entry or a CONTINUE from
-- Level 5 is refused while another party is inside or on its way in, and the refused players are told why.
-- A party is whatever token its entry path hands over: the queue's context, Level 5's group, or a fresh table.
-- `entered` tells a party that is inside (or was: the level is free the moment it is empty) from one that is still
-- streaming in, whose hold has to outlast its streaming whoever else comes and goes meanwhile.
local partyLock = {token = nil, holdUntil = 0, entered = false}
local letGo
local entryLeases, joinedEntries = {}, {}
local function pendingEntries()
 local busy = false
 for player, lease in pairs(entryLeases) do
  if player.Parent ~= Players or os.clock() >= lease.deadline or lease.token ~= partyLock.token then
   entryLeases[player] = nil
  else busy = true end
 end
 return busy
end
function Runtime.PendingValid(player, lease)
 return lease ~= nil and entryLeases[player] == lease and player.Parent == Players
  and os.clock() < lease.deadline and partyLock.token == lease.token
end
function Runtime.BeginEntry(player, token, kind)
 pendingEntries()
 if player.Parent ~= Players or partyLock.token ~= token or entryLeases[player] then return nil end
 local lease = {token = token, deadline = os.clock() + 90, kind = kind}
 partyLock.holdUntil = math.max(partyLock.holdUntil, lease.deadline)
 entryLeases[player] = lease
 return lease
end
function Runtime.EndEntry(player, lease)
 if lease and entryLeases[player] == lease then
  entryLeases[player] = nil
  letGo(lease.token)
 end
end
function Runtime.DropEntry(player)
 joinedEntries[player] = nil
 Runtime.EndEntry(player, entryLeases[player])
end
function Runtime.RollbackEntry(player, lease)
 if lease and (joinedEntries[player] == lease or Runtime.PendingValid(player, lease)) then Runtime.Leave(player) end
end
local function inLevel6(player)
	return player:GetAttribute(IN_PREVIEW) == true and player:GetAttribute("Level5VoidRound") ~= true
end
local function occupants(except)
	local count = 0
	for _, player in ipairs(Players:GetPlayers()) do
		if player ~= except and inLevel6(player) then count += 1 end
	end
	return count
end
local function claim(token)
	if token == nil then return false end
	if occupants() == 0 and Playground.State().phase ~= "idle" and partyLock.token ~= token then return false end
	if occupants() > 0 then
		if partyLock.token ~= token then return false end         -- in use: only its own party may add to it
	elseif partyLock.token ~= nil and partyLock.token ~= token and (os.clock() < partyLock.holdUntil or pendingEntries()) then
		return false                                              -- another party is streaming in right now
	end
	if partyLock.token ~= token then partyLock.entered = false end
	if partyLock.token ~= token or not pendingEntries() then partyLock.holdUntil = os.clock() + 90 end
	partyLock.token = token
	if not WorldStorage.Activate(6) then
		partyLock.token, partyLock.holdUntil, partyLock.entered = nil, 0, false
		return false
	end
	return true
end
-- letGo(token): that party did not get in and gives the level back. letGo(nil): somebody left; the level is free
-- if that emptied it (a party still on its way in keeps its hold).
letGo = function(token, except)
	if occupants(except) > 0 or pendingEntries() then return end
	if (token ~= nil and partyLock.token == token) or (token == nil and partyLock.entered) then
		partyLock.token, partyLock.holdUntil, partyLock.entered = nil, 0, false
	end
end
local function tellBusy(player)
	if typeof(player) ~= "Instance" or not player:IsA("Player") or player.Parent ~= Players then return end
	local playerGui = player:FindFirstChildOfClass("PlayerGui")
	if not playerGui then return end
	local old = playerGui:FindFirstChild("LiveLevelBusyNotice")
	if old then old:Destroy() end
	local gui = Instance.new("ScreenGui")
	gui.Name, gui.ResetOnSpawn, gui.DisplayOrder = "LiveLevelBusyNotice", false, 60
	local card = Instance.new("Frame")
	card.AnchorPoint, card.Position, card.Size = Vector2.new(0.5, 0), UDim2.fromScale(0.5, 0.16), UDim2.new(0.9, 0, 0, 104)
	card.BackgroundColor3, card.BackgroundTransparency, card.BorderSizePixel = Color3.fromRGB(17, 19, 22), 0.08, 0
	local limit = Instance.new("UISizeConstraint"); limit.MaxSize = Vector2.new(560, 104); limit.Parent = card
	local corner = Instance.new("UICorner"); corner.CornerRadius = UDim.new(0, 10); corner.Parent = card
	local edge = Instance.new("UIStroke"); edge.Color, edge.Thickness = Color3.fromRGB(255, 191, 41), 2; edge.Parent = card
	local title = Instance.new("TextLabel")
	title.BackgroundTransparency, title.Position, title.Size = 1, UDim2.new(0, 14, 0, 10), UDim2.new(1, -28, 0, 30)
	title.Font, title.TextSize, title.TextColor3 = Enum.Font.GothamBold, 22, Color3.fromRGB(255, 191, 41)
	title.Text = "LEVEL 6 IS IN USE"
	title.Parent = card
	local body = title:Clone()
	body.Position, body.Size = UDim2.new(0, 14, 0, 42), UDim2.new(1, -28, 0, 52)
	body.Font, body.TextSize, body.TextWrapped, body.TextColor3 = Enum.Font.GothamMedium, 16, true, Color3.fromRGB(242, 242, 236)
	body.Text = "Another team is playing in there right now. Try again in a few minutes, or play another level."
	body.Parent = card
	card.Parent = gui
	gui.Parent = playerGui
	task.delay(7, function() gui:Destroy() end)
end
Players.PlayerRemoving:Connect(function(player) Runtime.DropEntry(player); letGo(nil, player) end)
function Runtime.Emptied() letGo(nil) end
workspace:SetAttribute("Level6PartyLock", "PARTY_LOCK_20261008")
-- replicated, for anything that wants to show it (a sign at the gate, a test): somebody is in the level or on the way in
task.spawn(function()
	while true do
		local busy = occupants() > 0 or pendingEntries() or (partyLock.token ~= nil and os.clock() < partyLock.holdUntil)
		workspace:SetAttribute("Level6InUse", busy)
		-- RemovePlayer interrupts first; finish owns the doll, kill cam and finale cleanup.
		if not busy and Playground.State().phase == "idle" then WorldStorage.Deactivate(6) end
		task.wait(1)
	end
end)

function Runtime.Join(player, party, lease)
	if lease and not Runtime.PendingValid(player, lease) then return false, "ENTRY_EXPIRED" end
	if not claim(party) then return false, "LEVEL_IN_USE" end
	player:SetAttribute(IN_PREVIEW, true)
	local called, ok, reason = pcall(Playground.AddPlayer, player)
	if not called then
		pcall(Playground.RemovePlayer, player) -- AddPlayer may have installed partial session state
		reason, ok = ok, false
	end
	if ok then partyLock.entered = true; joinedEntries[player] = lease else player:SetAttribute(IN_PREVIEW, nil); letGo(party) end
	return ok, reason
end
local ENTER, RETURN = "Level6DeveloperPreviewPrompt", "Level6DeveloperPreviewReturnPrompt"
local RETURN_ANCHOR = "Level6DeveloperPreviewReturnAnchor"
local RETURN_OWNER = "Level6PreviewReturnOwned"
local RETURN_OFFSET = Vector3.new(1, 1.5, -4)
local transport = ReplicatedStorage:FindFirstChild("Level6PreviewTransport")
if not transport then
	transport = Instance.new("RemoteEvent")
	transport.Name = "Level6PreviewTransport"
	transport.Parent = ReplicatedStorage
end
assert(transport:IsA("RemoteEvent"), "Level6PreviewTransport has wrong class")
-- Back to lobby from inside the level (the exit chip and the spectate band's button send this on the round
-- remote; GameManager only answers it inside its own rounds).
do
	local status = ReplicatedStorage:WaitForChild("Remotes"):WaitForChild("RoundStatus")
	status.OnServerEvent:Connect(function(player, message)
		if message == "leaveround" and player:GetAttribute(IN_PREVIEW) == true then
			status:FireClient(player, "leaveack")
			Runtime.Leave(player)
		end
	end)
end
-- A live level is played in the round body: the hazmat StarterCharacter with InRound set, which is what
-- the first-person camera and its C toggle, the flashlight, sprint and the hidden lobby HUD all key on.
function Runtime.Suit(player, frame)
	if player.Parent ~= Players or player:GetAttribute(IN_PREVIEW) ~= true then return end
	player:SetAttribute("InRound", true)
	local load = ServerStorage:FindFirstChild("LoadGameplayCharacter")
	local previous = player.Character
	local ok, loaded = pcall(function() return load ~= nil and load:Invoke(player) end)
	local character = player.Character
	if player.Parent ~= Players or player:GetAttribute(IN_PREVIEW) ~= true then return end
	if not ok or not loaded or not character or character == previous then
		warn("[Level6PreviewAccess] round character did not load for " .. player.Name .. ": " .. tostring(loaded))
		return
	end
	local humanoid = character:WaitForChild("Humanoid", 5)
	local root = character:WaitForChild("HumanoidRootPart", 5)
	if not humanoid or not root or player:GetAttribute(IN_PREVIEW) ~= true then return end
	root.AssemblyLinearVelocity = Vector3.zero; root.AssemblyAngularVelocity = Vector3.zero
	character:PivotTo(frame)
	transport:FireClient(player, "ArrivalFacing", frame, MODEL_NAME)
end
local pending, nextUse = {}, {}
local hooked = setmetatable({}, {__mode = "k"})

local function lobbyPart(name)
	local lobby = workspace:FindFirstChild("ServerLobby")
	if not lobby then return nil end
	if name == "LobbySpawn" then return lobby:FindFirstChild(name) end
	local doors = lobby:FindFirstChild("LevelDoorways")
	return doors and doors:FindFirstChild(name)
end
-- R3 additional hosts retain this controller's existing access/stream/launch path.
local function r3Bridge()
 local folder = script.Parent:FindFirstChild("LobbyReimaginedPreview")
 local module = folder and folder:FindFirstChild("QueueBridge")
 return module and module:IsA("ModuleScript") and require(module) or nil
end
local function isR3Entry(door)
 local bridge = r3Bridge()
 return bridge and bridge.IsPreviewEntry(door, 6) or false
end
local r3Inflight = setmetatable({}, {__mode = "k"})
local function beginR3Entry(door)
 if not isR3Entry(door) then return nil end
 local ref = door:FindFirstChild("QueueRenderOwner")
 local owner = ref and ref:IsA("ObjectValue") and ref.Value
 if not owner or not owner:IsA("Model") or not owner:IsDescendantOf(door:FindFirstAncestor("LobbyReimaginedPreview")) then return nil end
 r3Inflight[owner] = (r3Inflight[owner] or 0) + 1
 owner:SetAttribute("QueueActive", true)
 return owner
end
local function finishR3Entry(owner)
 if not owner then return end
 local count = math.max(0, (r3Inflight[owner] or 1) - 1)
 r3Inflight[owner] = count > 0 and count or nil
 if owner.Parent then owner:SetAttribute("QueueActive", count > 0) end
end

local function playerReady(player)
	if player.Parent ~= Players or not DevAccess.IsLevel6Allowed(player)
		or (player:GetAttribute("InRound") == true and player:GetAttribute(IN_PREVIEW) ~= true)
		or workspace:GetAttribute("ReservedRoundServer") == true then return nil end
	local character = player.Character
	local humanoid = character and character:FindFirstChildOfClass("Humanoid")
	local root = humanoid and humanoid.RootPart
	if not root or not character:IsDescendantOf(workspace) or root.Anchored
		or humanoid.SeatPart or humanoid.Health <= 0 then return nil end
	return character, root
end
local function previewReady()
	local model = WorldStorage.Get(6)
	if not model or not model:IsA("Model") or model:GetAttribute("Level6Preview") ~= true
		or model:GetAttribute("PreviewOnly") ~= true or model:GetAttribute("Level6PreviewReady") ~= true then return nil end
	local exit = model:FindFirstChild(EXIT_NAME, true)
	if not exit or not exit:IsA("BasePart") then return nil end
	return model, exit
end
local function floorAt(model, point)
	local params = RaycastParams.new()
	params.FilterType = Enum.RaycastFilterType.Include
	params.FilterDescendantsInstances = {model}
	params.RespectCanCollide = true
	local hit = workspace:Raycast(point, Vector3.new(0, -10, 0), params)
	return hit ~= nil and hit.Normal.Y > 0.7
end
local function upright(cf)
	local flat = Vector3.new(cf.LookVector.X, 0, cf.LookVector.Z)
	return CFrame.lookAt(cf.Position, cf.Position + (if flat.Magnitude > .01 then flat else Vector3.zAxis))
end
transport.OnServerEvent:Connect(function(player, nonce, ready)
	local token = pending[player]
	if token and nonce == token.nonce and ready == true and os.clock() <= token.expires
		and DevAccess.IsLevel6Allowed(player) then token.ready = true end
end)
local function streamReady(player, target, modelName)
	local token = {nonce = HttpService:GenerateGUID(false), expires = os.clock() + 22, ready = false}
	pending[player] = token
	local ok = pcall(function() player:RequestStreamAroundAsync(target, 8) end)
	if ok and player.Parent == Players then
		transport:FireClient(player, token.nonce, target, modelName)
		while pending[player] == token and not token.ready and os.clock() < token.expires
			and player.Parent == Players do task.wait(.1) end
	end
	if pending[player] == token then pending[player] = nil end
	return ok and token.ready
end
local function release(player)
	nextUse[player] = if player.Parent == Players then os.clock() + 2 else nil
end

local onReturn
local function ensurePrompt(parent, name, action, callback)
	local prompt = parent:FindFirstChild(name)
	if not prompt then
		prompt = Instance.new("ProximityPrompt")
		prompt.Name = name; prompt.ActionText = action; prompt.ObjectText = "LEVEL 6 · DEV PREVIEW"
		prompt.HoldDuration = .5; prompt.MaxActivationDistance = 10; prompt.RequiresLineOfSight = false
		prompt.Parent = parent
	end
	if prompt:IsA("ProximityPrompt") then prompt.ObjectText = "LEVEL 6" end
	if prompt:IsA("ProximityPrompt") and not hooked[prompt] then
		hooked[prompt] = prompt.Triggered:Connect(function(player) callback(player, prompt) end)
	end
	return prompt
end
-- The tube landing is underfoot. Mount only this RETURN prompt ahead of
-- the arrival view; the exit-relative distance/auth/stream guards stay intact.
local function validReturnAnchor(anchor, exit)
	return anchor ~= nil and anchor:IsA("Attachment") and anchor.Name == RETURN_ANCHOR
		and anchor.Parent == exit and anchor:GetAttribute(RETURN_OWNER) == true
		and anchor.Position == RETURN_OFFSET
end
local function validReturnPrompt(prompt, exit)
	if not prompt or not prompt:IsA("ProximityPrompt") or prompt.Name ~= RETURN then return false end
	-- Compatibility for an existing direct exit prompt before hookExit mounts it.
	return prompt.Parent == exit or validReturnAnchor(prompt.Parent, exit)
end
local function returnPrompt(exit)
	if not exit then return nil end
	local anchor = exit:FindFirstChild(RETURN_ANCHOR)
	local prompt = if anchor then (if validReturnAnchor(anchor, exit) then anchor:FindFirstChild(RETURN) else nil)
		else exit:FindFirstChild(RETURN)
	return if validReturnPrompt(prompt, exit) then prompt else nil
end
local function hookExit()
	local _, exit = previewReady()
	if not exit then return end
	local anchor = exit:FindFirstChild(RETURN_ANCHOR)
	local legacy = exit:FindFirstChild(RETURN)
	if (anchor and not validReturnAnchor(anchor, exit))
		or (legacy and not validReturnPrompt(legacy, exit)) then
		warn("[Level6PreviewAccess] RETURN mount conflicts with an existing instance")
		return
	end
	local mounted = anchor and anchor:FindFirstChild(RETURN)
	if mounted and (not validReturnPrompt(mounted, exit) or legacy) then
		warn("[Level6PreviewAccess] RETURN mount has a conflicting prompt")
		return
	end
	if not anchor then
		anchor = Instance.new("Attachment")
		anchor.Name = RETURN_ANCHOR
		anchor.Position = RETURN_OFFSET
		anchor:SetAttribute(RETURN_OWNER, true)
		anchor.Parent = exit
	end
	if legacy then legacy.Parent = anchor end
	local prompt = ensurePrompt(anchor, RETURN, "RETURN TO LOBBY", onReturn)
	if validReturnPrompt(prompt, exit) then prompt.MaxActivationDistance = 7.5 end
	-- Owner, 2026-10-04: no RETURN TO LOBBY at the start of the level. The prompt instance stays (the queue's
	-- `ready` check and the mount validation look for it) but it can never be shown or triggered; leaving the
	-- level is the round exit chip's job.
	if prompt then prompt.MaxActivationDistance = 0 end
end

local function onEnter(player, prompt)
	if (nextUse[player] or 0) > os.clock() or player:GetAttribute(IN_PREVIEW) == true then return end
	local character, root = playerReady(player)
	local door = prompt.Parent
	if not character or not door or not door:IsA("BasePart")
  or not (door == lobbyPart("Level6SealedDoor") or isR3Entry(door)) or (root.Position - door.Position).Magnitude > 14 then return end
	local party = {}                                            -- PARTY_LOCK_20261008: an E entry is a party of one
	if not claim(party) then
		tellBusy(player)
		nextUse[player] = os.clock() + 2
		return
	end
	local lease = Runtime.BeginEntry(player, party)
	if not lease then letGo(party); return end
	nextUse[player] = math.huge
 local r3Owner = beginR3Entry(door)
	local previous = character:GetPivot()
	local ok, err = pcall(function()
		local model, exit = Runtime.EnsureWorld()
		hookExit()
		if not model or not exit or not floorAt(model, exit.Position) then error("Preview landing floor unavailable") end
		if not streamReady(player, exit.Position, MODEL_NAME) or not Runtime.PendingValid(player, lease) then error("Preview streaming confirmation timed out") end
		local currentCharacter, currentRoot = playerReady(player)
		local currentModel, currentExit = previewReady()
		if currentCharacter ~= character or currentModel ~= model or currentExit ~= exit
			or not (door == lobbyPart("Level6SealedDoor") or isR3Entry(door)) or prompt.Parent ~= door
			or (currentRoot.Position - door.Position).Magnitude > 14
			or not floorAt(model, exit.Position) then return end
		root.AssemblyLinearVelocity = Vector3.zero; root.AssemblyAngularVelocity = Vector3.zero
		character:PivotTo(upright(exit.CFrame))
		local joined, reason = Runtime.Join(player, party, lease)
		if not joined then
			character:PivotTo(previous)
			error("Preview join rejected: " .. tostring(reason))
		end
		-- Orient once only after an authorized, successful Level 6 arrival.
		transport:FireClient(player, "ArrivalFacing", upright(exit.CFrame), MODEL_NAME)
		task.spawn(Runtime.Suit, player, upright(exit.CFrame))
	end)
 finishR3Entry(r3Owner)
	Runtime.EndEntry(player, lease)
	release(player)
	if player:GetAttribute(IN_PREVIEW) ~= true then letGo(party) end
	if not ok then warn("[Level6PreviewAccess] " .. tostring(err)) end
end
onReturn = function(player, prompt)
	if (nextUse[player] or 0) > os.clock() then return end
	local character, root = playerReady(player)
	local model, exit = previewReady()
	local spawn = lobbyPart("LobbySpawn")
	if not character or not model or not exit or not spawn or player:GetAttribute(IN_PREVIEW) ~= true
		or not validReturnPrompt(prompt, exit) or (root.Position - exit.Position).Magnitude > 12 then return end
	nextUse[player] = math.huge
	local ok, err = pcall(function()
		local landing = spawn.Position + Vector3.new(0, 4, 0)
		local floorModelName = if spawn:GetAttribute("LobbySpawnFloorModelName") == "LobbyReimaginedPreview" then "LobbyReimaginedPreview" else "ServerLobby"
		if not streamReady(player, landing, floorModelName) then error("Lobby streaming confirmation timed out") end
		local currentCharacter, currentRoot = playerReady(player)
		if currentCharacter ~= character or not exit.Parent or not validReturnPrompt(prompt, exit)
			or (currentRoot.Position - exit.Position).Magnitude > 12 or lobbyPart("LobbySpawn") ~= spawn then return end
		Runtime.Leave(player)
		root.AssemblyLinearVelocity = Vector3.zero; root.AssemblyAngularVelocity = Vector3.zero
		character:PivotTo(upright(spawn.CFrame + Vector3.new(0, 4, 0)))
	end)
	release(player)
	if not ok then warn("[Level6PreviewAccess] " .. tostring(err)) end
end
-- Caught and escaped players go home through the same lobby landing as RETURN TO LOBBY.
Playground.SetReturnHandler(function(player)
	local character = player.Character
	local humanoid = character and character:FindFirstChildOfClass("Humanoid")
	local root = humanoid and humanoid.RootPart
	local spawn = lobbyPart("LobbySpawn")
	Runtime.Leave(player)
	if not root or not spawn then return end
	local ok, err = pcall(function()
		local landing = spawn.Position + Vector3.new(0, 4, 0)
		local floorModelName = if spawn:GetAttribute("LobbySpawnFloorModelName") == "LobbyReimaginedPreview" then "LobbyReimaginedPreview" else "ServerLobby"
		streamReady(player, landing, floorModelName)
		if player.Character ~= character or not root.Parent then return end
		root.AssemblyLinearVelocity = Vector3.zero; root.AssemblyAngularVelocity = Vector3.zero
		character:PivotTo(upright(spawn.CFrame + Vector3.new(0, 4, 0)))
	end)
	if not ok then warn("[Level6PreviewAccess] return: " .. tostring(err)) end
end)
-- R4 queue cohorts keep the existing Level6 allowlist, floor/stream
-- confirmation and Runtime.Join path. No campaign routing is changed.
do
 local bridge = r3Bridge()
 if bridge and bridge.RegisterPreviewLauncher then
  local queueLocks = {}
  local registered, registrationProblem = pcall(bridge.RegisterPreviewLauncher, 6, script, {
   allowed = function(player, _, station)
    local lock = queueLocks[player]
    return (if lock then bridge.ContextOwns(lock, player, station) else (nextUse[player] or 0) <= os.clock())
     and playerReady(player) ~= nil
   end,
   ready = function()
    local model, exit = previewReady()
    local prompt = returnPrompt(exit)
    if not model or not prompt or not prompt:IsA("ProximityPrompt") or not prompt.Enabled
     then return nil end
    return model, exit
   end,
   launch = function(context)
    local locked, reason = bridge.LockPreviewController(context, nextUse, queueLocks, release)
    if not locked then return false, reason end
    -- PARTY_LOCK_20261008: one party in the level at a time; the queue's context is this party
    if not claim(context) then
     for player, lock in pairs(queueLocks) do
      if lock == context then tellBusy(player) end
     end
     return false, "LEVEL_IN_USE"
    end
    local model, exit = Runtime.EnsureWorld()
    hookExit()
    if not model or not exit or not floorAt(model, exit.Position) then letGo(context); return false, "PREVIEW_NOT_READY" end
    local leases = {}
    for player, lock in pairs(queueLocks) do
     if lock == context then
      local lease = Runtime.BeginEntry(player, context)
      if not lease then
       for owner, owned in pairs(leases) do Runtime.EndEntry(owner, owned) end
       letGo(context); return false, "ENTRY_PENDING"
      end
      leases[player] = lease
     end
    end
    local ok, committed, commitProblem, entries = pcall(function()
     local entries, problem = bridge.PreparePreviewGroup(context, model, exit, function(player, position)
      return Runtime.PendingValid(player, leases[player]) and streamReady(player, position, MODEL_NAME) == true
       and Runtime.PendingValid(player, leases[player])
     end)
     if not entries then return false, problem end
     local joined, why = bridge.CommitPreviewGroup(context, entries, function(entry)
      local entered, reason = Runtime.Join(entry.player, context, leases[entry.player])
      if entered then transport:FireClient(entry.player, "ArrivalFacing", entry.frame, MODEL_NAME) end
      return entered, reason
     end, function(entry) Runtime.RollbackEntry(entry.player, leases[entry.player]) end)
     return joined, why, entries
    end)
    -- Keep the leases through the whole cohort commit, including yielding callbacks.
    for player, lease in pairs(leases) do Runtime.EndEntry(player, lease) end
    if not ok then letGo(context); return false, tostring(committed) end
    if not committed then letGo(context) end
    -- The queue validates each member's lobby character through the commit, so the round body goes on after it.
    if committed then
     for _, entry in ipairs(entries) do task.spawn(Runtime.Suit, entry.player, entry.frame) end
    end
    return committed, commitProblem
   end,
  })
  if not registered then warn("[R4 Preview Queue] registration: " .. tostring(registrationProblem)) end
 end
end

-- CONTINUE on Level 5's ending (ServerStorage.Level6EnterFromLevel, called by Level5PreviewAccess): the same
-- player comes on into this level in the round state they already have. Two steps, so the level they are
-- leaving does not let go of them before this one is ready: "prepare" streams the place to the client,
-- "enter" takes the player and loads a round body at the arrival.
do
	local old = ServerStorage:FindFirstChild("Level6EnterFromLevel")
	if old then old:Destroy() end
	local enter = Instance.new("BindableFunction")
	enter.Name = "Level6EnterFromLevel"
	enter.OnInvoke = function(player, step, party)
		if typeof(player) ~= "Instance" or not player:IsA("Player") then return false end
		party = if party ~= nil then party else player
		local lease = entryLeases[player]
		if step == "cancel" then
			if lease and lease.token == party and lease.kind == "continue" then Runtime.EndEntry(player, lease) end
			return true
		end
		if player.Parent ~= Players or not DevAccess.IsLevel6Allowed(player)
			or workspace:GetAttribute("ReservedRoundServer") == true then return false end
		if step ~= "prepare" and step ~= "enter" then return false end
		-- A preparation is retained across Invoke calls, and enter consumes it once.
		if step == "enter" then
			if not Runtime.PendingValid(player, lease) or lease.token ~= party
				or lease.kind ~= "continue" or lease.consuming then return false end
			lease.consuming = true
		else
			if not claim(party) then tellBusy(player); return false end
			lease = Runtime.BeginEntry(player, party, "continue")
			if not lease then return false end
		end
		local ok, result = pcall(function()
			local model, exit = Runtime.EnsureWorld()
			hookExit()
			if not model or not exit or model.Parent ~= workspace or not floorAt(model, exit.Position) then return false end
			if step == "prepare" then
				return streamReady(player, exit.Position, MODEL_NAME) == true and Runtime.PendingValid(player, lease)
			end
			-- Load the destination body before AddPlayer installs its life watcher.
			local frame = upright(exit.CFrame)
			Runtime.Suit(player, frame)
			local character = player.Character
			local root = character and character:FindFirstChild("HumanoidRootPart")
			local humanoid = character and character:FindFirstChildOfClass("Humanoid")
			if not Runtime.PendingValid(player, lease) or not root or not humanoid or humanoid.Health <= 0
				or (root.Position - frame.Position).Magnitude > 60 then return false end
			local joined, reason = Runtime.Join(player, party, lease)
			if not joined then
				player:SetAttribute(IN_PREVIEW, true) -- the source level still owns the shared marker
				warn("[Level6PreviewAccess] continue rejected: " .. tostring(reason))
			end
			return joined == true
		end)
		if step == "enter" or not ok or result ~= true then Runtime.EndEntry(player, lease) end
		if not ok then warn("[Level6PreviewAccess] continue: " .. tostring(result)) end
		return ok and result == true
	end
	enter.Parent = ServerStorage
end

-- LIVE_LEVEL_SERVERS_20261008 (ServerStorage.Level6LaunchParty, invoked by "Live Level Server"). A party that was
-- given a server of its own for this level lands in that server's lobby and is taken in here: the same checks,
-- streaming handshake, join and round body as the pad's launch, without a pad. `token` is the party; a latecomer
-- of the same party is launched with the same token and joins the round that is already running.
-- Returns whether anybody got in, and how many.
do
	local old = ServerStorage:FindFirstChild("Level6LaunchParty")
	if old then old:Destroy() end
	local launchParty = Instance.new("BindableFunction")
	launchParty.Name = "Level6LaunchParty"
	launchParty.OnInvoke = function(players, token)
		if type(players) ~= "table" or not (type(token) == "table" or (type(token) == "string" and token ~= "")) then return false, 0, "BAD_REQUEST" end
		local model, exit = Runtime.EnsureWorld()
		hookExit()
		if not model or not exit or not previewReady() then return false, 0, "PREVIEW_NOT_READY" end
		if not claim(token) then
			for _, player in ipairs(players) do tellBusy(player) end
			return false, 0, "LEVEL_IN_USE"
		end
		if not floorAt(model, exit.Position) then letGo(token); return false, 0, "PREVIEW_NOT_READY" end
		local party, selected = {}, {}
		for _, player in ipairs(players) do
			if typeof(player) == "Instance" and player:IsA("Player") and (nextUse[player] or 0) <= os.clock()
				and player:GetAttribute(IN_PREVIEW) ~= true and playerReady(player) then
				if not selected[player] then table.insert(party, player); selected[player] = true end
			end
		end
		local bridge = r3Bridge()
		local frames = bridge and bridge.PartyLandings and bridge.PartyLandings(model, exit, party) or {}
		-- everybody's client has the place before anybody is moved, so the party arrives together
		local leases = {}
		for _, player in ipairs(party) do
			local lease = Runtime.BeginEntry(player, token)
			if not lease then
				for owner, owned in pairs(leases) do Runtime.EndEntry(owner, owned) end
				letGo(token); return false, 0, "ENTRY_PENDING"
			end
			leases[player] = lease
		end
		local streamed, waiting = {}, #party
		for _, player in ipairs(party) do
			nextUse[player] = math.huge
			frames[player] = frames[player] or upright(exit.CFrame)
			task.spawn(function()
				local ok, ready = pcall(streamReady, player, frames[player].Position, MODEL_NAME)
				streamed[player] = ok and ready == true
				waiting -= 1
			end)
		end
		local deadline = os.clock() + 30
		while waiting > 0 and os.clock() < deadline do task.wait(.1) end
		local joined = 0
		for _, player in ipairs(party) do
			local ok, problem = pcall(function()
				if not Runtime.PendingValid(player, leases[player]) then error("entry expired") end
				if not streamed[player] then error("streaming confirmation timed out") end
				local character, root = playerReady(player)
				local nowModel, nowExit = previewReady()
				if not character or nowModel ~= model or nowExit ~= exit then error("the player or the level changed") end
				local previous = character:GetPivot()
				root.AssemblyLinearVelocity = Vector3.zero; root.AssemblyAngularVelocity = Vector3.zero
				character:PivotTo(frames[player])
				local entered, reason = Runtime.Join(player, token, leases[player])
				if not entered then
					character:PivotTo(previous)
					error("join rejected: " .. tostring(reason))
				end
				joined += 1
				transport:FireClient(player, "ArrivalFacing", frames[player], MODEL_NAME)
				task.spawn(Runtime.Suit, player, frames[player])
			end)
			if not ok then warn("[Level6PreviewAccess] party launch, " .. player.Name .. ": " .. tostring(problem)) end
			Runtime.EndEntry(player, leases[player])
			release(player)
		end
		if joined == 0 then letGo(token) end
		return joined > 0, joined
	end
	launchParty.Parent = ServerStorage
end

local function hookDoor()
	local door = lobbyPart("Level6SealedDoor")
	if door and door:IsA("BasePart") then ensurePrompt(door, ENTER, "ENTER INDOOR PLAYGROUND", onEnter) end
 local bridge = r3Bridge()
 local model = workspace:FindFirstChild("LobbyReimaginedPreview")
 if bridge then
  for _, host in ipairs(bridge.GetPreviewEntries(model, 6)) do
   ensurePrompt(host, ENTER, "ENTER INDOOR PLAYGROUND", onEnter)
  end
 end
end
local watchedModel, readyConnection
local function watchModel(model)
	if watchedModel ~= model then
		if readyConnection then readyConnection:Disconnect() end
		watchedModel = model
		readyConnection = model and model:GetAttributeChangedSignal("Level6PreviewReady"):Connect(hookExit) or nil
	end
	hookExit()
end
Players.PlayerRemoving:Connect(function(player) pending[player] = nil; nextUse[player] = nil end)
workspace.DescendantAdded:Connect(function(instance)
	if instance.Name == "ServerLobby" or instance.Name == "LevelDoorways" or instance.Name == "Level6SealedDoor" then hookDoor()
	elseif instance.Name == MODEL_NAME and instance.Parent == workspace and instance:IsA("Model") then watchModel(instance)
	elseif instance.Name == EXIT_NAME then hookExit() end
end)
hookDoor(); watchModel(workspace:FindFirstChild(MODEL_NAME))

-- Observe ready publication/restoration; the original lobby watcher is unchanged.
local r3Watched = setmetatable({}, {__mode = "k"})
local function watchR3Lobby(model)
 if not model or not model:IsA("Model") or model.Name ~= "LobbyReimaginedPreview" or r3Watched[model] then return end
 r3Watched[model] = true
 local ready = model:GetAttributeChangedSignal("Ready"):Connect(hookDoor)
 local ancestry = model.AncestryChanged:Connect(function() if model.Parent == workspace then task.defer(hookDoor) end end)
 local descendants = model.DescendantAdded:Connect(function(part)
  if part:GetAttribute("R3DeveloperPreviewEntry") == 6 then task.defer(hookDoor) end
 end)
 model.Destroying:Once(function() ready:Disconnect(); ancestry:Disconnect(); descendants:Disconnect() end)
 task.defer(hookDoor)
end
workspace.ChildAdded:Connect(watchR3Lobby)
watchR3Lobby(workspace:FindFirstChild("LobbyReimaginedPreview"))
