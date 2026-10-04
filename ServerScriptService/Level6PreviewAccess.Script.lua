-- Developer-only functional preview. Isolated from GameManager and public level progression.
local Players = game:GetService("Players")
local ReplicatedStorage = game:GetService("ReplicatedStorage")
local HttpService = game:GetService("HttpService")
local ServerStorage = game:GetService("ServerStorage")
local DevAccess = require(ReplicatedStorage:WaitForChild("DevAccess"))
local MODEL_NAME, EXIT_NAME = "Level 6 Indoor Playground", "Level6Exit"
-- 2026-10-03: Level 6 is the static Indoor Playground map (tools/level6_playground). The generated
-- Level 3 copy in "Level 6 Systems" is no longer launched from here; its modules are left in place.
local IN_PREVIEW = "Level6PlaygroundPreview"
local Runtime = {}
function Runtime.EnsureWorld()
	local model = workspace:FindFirstChild(MODEL_NAME)
	return model, model and model:FindFirstChild(EXIT_NAME, true)
end
-- The hide-and-seek round (the counting child) lives in "Level 6 Playground Game".
local Playground = require(script.Parent:WaitForChild("Level 6 Systems"):WaitForChild("Level 6 Playground Game"))
function Runtime.Leave(player, died)
	local was = player:GetAttribute(IN_PREVIEW) == true
	player:SetAttribute(IN_PREVIEW, nil)
	if was then player:SetAttribute("InRound", false) end
	Playground.RemovePlayer(player)
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
function Runtime.Join(player)
	player:SetAttribute(IN_PREVIEW, true)
	local ok, reason = Playground.AddPlayer(player)
	if not ok then player:SetAttribute(IN_PREVIEW, nil) end
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
	local model = workspace:FindFirstChild(MODEL_NAME)
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
	nextUse[player] = math.huge
 local r3Owner = beginR3Entry(door)
	local previous = character:GetPivot()
	local ok, err = pcall(function()
		local model, exit = Runtime.EnsureWorld()
		hookExit()
		if not model or not exit or not floorAt(model, exit.Position) then error("Preview landing floor unavailable") end
		if not streamReady(player, exit.Position, MODEL_NAME) then error("Preview streaming confirmation timed out") end
		local currentCharacter, currentRoot = playerReady(player)
		local currentModel, currentExit = previewReady()
		if currentCharacter ~= character or currentModel ~= model or currentExit ~= exit
			or not (door == lobbyPart("Level6SealedDoor") or isR3Entry(door)) or prompt.Parent ~= door
			or (currentRoot.Position - door.Position).Magnitude > 14
			or not floorAt(model, exit.Position) then return end
		root.AssemblyLinearVelocity = Vector3.zero; root.AssemblyAngularVelocity = Vector3.zero
		character:PivotTo(upright(exit.CFrame))
		local joined, reason = Runtime.Join(player)
		if not joined then
			character:PivotTo(previous)
			error("Preview join rejected: " .. tostring(reason))
		end
		-- Orient once only after an authorized, successful Level 6 arrival.
		transport:FireClient(player, "ArrivalFacing", upright(exit.CFrame), MODEL_NAME)
		task.spawn(Runtime.Suit, player, upright(exit.CFrame))
	end)
 finishR3Entry(r3Owner)
	release(player)
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
     or not floorAt(model, exit.Position) then return nil end
    return model, exit
   end,
   launch = function(context)
    local locked, reason = bridge.LockPreviewController(context, nextUse, queueLocks, release)
    if not locked then return false, reason end
    local model, exit = Runtime.EnsureWorld()
    hookExit()
    if not model or not exit or not floorAt(model, exit.Position) then return false, "PREVIEW_NOT_READY" end
    local entries, problem = bridge.PreparePreviewGroup(context, model, exit, function(player, position)
     return streamReady(player, position, MODEL_NAME)
    end)
    if not entries then return false, problem end
    local committed, commitProblem = bridge.CommitPreviewGroup(context, entries, function(entry)
     local joined, reason = Runtime.Join(entry.player)
     if joined then transport:FireClient(entry.player, "ArrivalFacing", entry.frame, MODEL_NAME) end
     return joined, reason
    end, function(entry) Runtime.Leave(entry.player) end)
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
