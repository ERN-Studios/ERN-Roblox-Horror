-- Entry to Level 5, the void rooms (tools/level5_void), and the level itself.
-- PUBLIC since 2026-10-04 (DevAccess.IsLevel5Allowed). It runs on the lobby
-- server, outside GameManager, the way Level 6 does: a player in the level is
-- in round state (hazmat body, first person, flashlight, sprint) and carries
-- `Level5VoidRound` next to the shared `Level6PlaygroundPreview` marker that
-- every round feature outside GameManager already keys on.
-- The prompts are UI; every teleport is authorized again on the server.
local Players = game:GetService("Players")
local ReplicatedStorage = game:GetService("ReplicatedStorage")
local ServerStorage = game:GetService("ServerStorage")
local DevAccess = require(ReplicatedStorage:WaitForChild("DevAccess"))
local IN_LEVEL, LIVE = "Level5VoidRound", "Level6PlaygroundPreview"
local Void = {}

local MODEL_NAME = "Level 5 Void"
local EXIT_NAME = "Level5Exit"
local ENTER_PROMPT = "Level5DeveloperPreviewPrompt"
local RETURN_PROMPT = "Level5DeveloperPreviewReturnPrompt"
local COOLDOWN = 2
local nextUse = {}
local hooked = setmetatable({}, { __mode = "k" })

local function liveDoor()
	local lobby = workspace:FindFirstChild("ServerLobby")
	local doorways = lobby and lobby:FindFirstChild("LevelDoorways")
	local door = doorways and doorways:FindFirstChild("Level5SealedDoor")
	return door and door:IsA("BasePart") and door or nil
end

-- R3 additional hosts retain this controller's existing access/stream/launch path.
local function r3Bridge()
 local folder = script.Parent:FindFirstChild("LobbyReimaginedPreview")
 local module = folder and folder:FindFirstChild("QueueBridge")
 return module and module:IsA("ModuleScript") and require(module) or nil
end
local function isR3Entry(door)
 local bridge = r3Bridge()
 return bridge and bridge.IsPreviewEntry(door, 5) or false
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

local function liveSpawn()
	local lobby = workspace:FindFirstChild("ServerLobby")
	local spawn = lobby and lobby:FindFirstChild("LobbySpawn")
	return spawn and spawn:IsA("BasePart") and spawn or nil
end

local function readyPreview()
	local model = workspace:FindFirstChild(MODEL_NAME)
	if not (model and model:IsA("Model") and model:GetAttribute("Level5Preview") == true
		and model:GetAttribute("PreviewOnly") == true
		and model:GetAttribute("Level5PreviewReady") == true) then return nil end
	local exit = model:FindFirstChild(EXIT_NAME, true)
	if not (exit and exit:IsA("BasePart") and exit:IsDescendantOf(model)) then return nil end
	return model, exit
end

local function readyPlayer(player, inLevel)
	if player.Parent ~= Players or not DevAccess.IsLevel5Allowed(player)
		or (player:GetAttribute(IN_LEVEL) == true) ~= (inLevel == true)
		or (not inLevel and (player:GetAttribute("InRound") == true or player:GetAttribute(LIVE) == true))
		or workspace:GetAttribute("ReservedRoundServer") == true then return nil end
	local character = player.Character
	local humanoid = character and character:FindFirstChildOfClass("Humanoid")
	local root = humanoid and humanoid.RootPart
	if not root or not character:IsDescendantOf(workspace) or root.Anchored or humanoid.SeatPart
		or humanoid.Health <= 0 or humanoid:GetState() == Enum.HumanoidStateType.Dead then return nil end
	return character, root
end

local function upright(position, look)
	local flat = Vector3.new(look.X, 0, look.Z)
	return CFrame.lookAt(position, position + (if flat.Magnitude > 0.01 then flat else Vector3.zAxis))
end

local function stream(player, position)
	local ok, err = pcall(function() player:RequestStreamAroundAsync(position, 8) end)
	if not ok then warn("[Level5PreviewAccess] streaming failed:", err) end
	return ok
end

local function release(player)
	nextUse[player] = if player.Parent == Players then os.clock() + COOLDOWN else nil
end

local function hasFloor(model, exit)
	local params = RaycastParams.new()
	params.FilterType = Enum.RaycastFilterType.Include
	params.FilterDescendantsInstances = { model }
	params.RespectCanCollide = true
	local hit = workspace:Raycast(exit.Position, Vector3.new(0, -8, 0), params)
	return hit ~= nil and hit.Normal.Y > 0.7
end

local function onReturn(player, prompt)
	if (nextUse[player] or 0) > os.clock() then return end
	local character, root = readyPlayer(player, true)
	local model, exit = readyPreview()
	if not character or not model or not exit or prompt.Parent ~= exit
		or (root.Position - exit.Position).Magnitude > 12 then return end
	nextUse[player] = os.clock() + COOLDOWN
	Void.Leave(player)
end

local function onEnter(player, prompt)
	if (nextUse[player] or 0) > os.clock() then return end
	local character, root = readyPlayer(player)
	local door = prompt.Parent
	if not character or not door or not door:IsA("BasePart")
  or not (door == liveDoor() or isR3Entry(door)) or (root.Position - door.Position).Magnitude > 14 then return end
	local model, exit = readyPreview()
	local returnPrompt = exit and exit:FindFirstChild(RETURN_PROMPT)
	if not model or not returnPrompt or not returnPrompt:IsA("ProximityPrompt")
		or not returnPrompt.Enabled or not hasFloor(model, exit) then
		warn("[Level5PreviewAccess] ready preview, return prompt or landing floor is missing")
		return
	end
	local group = {}                                            -- PARTY_LOCK_20261008: an E entry is a party of one
	if not (Void.Claim and Void.Claim(group)) then
		if Void.TellBusy then Void.TellBusy(player) end
		nextUse[player] = os.clock() + COOLDOWN
		return
	end
	nextUse[player] = math.huge
 local r3Owner = beginR3Entry(door)
	local ok, err = pcall(function()
		if not stream(player, exit.Position) then return end
		local nowCharacter, nowRoot = readyPlayer(player)
		local nowModel, nowExit = readyPreview()
		if nowCharacter ~= character or nowModel ~= model or nowExit ~= exit
			or prompt.Parent ~= door or not (door == liveDoor() or isR3Entry(door))
			or (nowRoot.Position - door.Position).Magnitude > 14
			or returnPrompt.Parent ~= exit or not returnPrompt.Enabled
			or not hasFloor(model, exit) then return end
		local frame = upright(exit.Position, exit.CFrame.LookVector)
		character:PivotTo(frame)
		if Void.Join(player, group) then task.spawn(Void.Suit, player, frame) end
	end)
 finishR3Entry(r3Owner)
	release(player)
	if player:GetAttribute(IN_LEVEL) ~= true then Void.LetGo(group) end
	if not ok then warn("[Level5PreviewAccess] entry failed:", err) end
end

local function ensurePrompt(parent, name, action, object, callback)
	local prompt = parent:FindFirstChild(name)
	if not prompt then
		prompt = Instance.new("ProximityPrompt")
		prompt.Name = name
		prompt.ActionText = action
		prompt.ObjectText = object
		prompt.HoldDuration = 0.5
		prompt.MaxActivationDistance = 10
		prompt.RequiresLineOfSight = false
		prompt.Parent = parent
	end
	if not prompt:IsA("ProximityPrompt") then return end
	if not hooked[prompt] then
		hooked[prompt] = true
		prompt.Triggered:Connect(function(player) callback(player, prompt) end)
	end
end

-- R4 queue cohorts use the same existing authorized preview/floor/stream
-- helpers as the original E entry. Original door prompts are unchanged.
do
 local bridge = r3Bridge()
 if bridge and bridge.RegisterPreviewLauncher then
  local queueLocks = {}
  local registered, registrationProblem = pcall(bridge.RegisterPreviewLauncher, 5, script, {
   allowed = function(player, _, station)
    local lock = queueLocks[player]
    -- the queue asks again after each member has joined, when that member is already marked as in the level
    return (if lock then bridge.ContextOwns(lock, player, station) else (nextUse[player] or 0) <= os.clock())
     and (readyPlayer(player) ~= nil or (lock ~= nil and readyPlayer(player, true) ~= nil))
   end,
   ready = function()
    local model, exit = readyPreview()
    local prompt = exit and exit:FindFirstChild(RETURN_PROMPT)
    if not model or not prompt or not prompt:IsA("ProximityPrompt") or not prompt.Enabled
     or not hasFloor(model, exit) then return nil end
    return model, exit
   end,
   launch = function(context)
    local locked, reason = bridge.LockPreviewController(context, nextUse, queueLocks, release)
    if not locked then return false, reason end
    -- PARTY_LOCK_20261008: one party in the level at a time
    local group = {}
    if not Void.Claim(group) then
     for player, lock in pairs(queueLocks) do
      if lock == context then Void.TellBusy(player) end
     end
     return false, "LEVEL_IN_USE"
    end
    local model, exit = readyPreview()
    local returnPrompt = exit and exit:FindFirstChild(RETURN_PROMPT)
    if not model or not returnPrompt or not returnPrompt:IsA("ProximityPrompt")
     or not returnPrompt.Enabled or not hasFloor(model, exit) then Void.LetGo(group); return false, "PREVIEW_NOT_READY" end
    local entries, problem = bridge.PreparePreviewGroup(context, model, exit, stream)
    if not entries then Void.LetGo(group); return false, problem end
    local committed, commitProblem = bridge.CommitPreviewGroup(context, entries, function(entry)
     return Void.Join(entry.player, group)
    end, function(entry) Void.Leave(entry.player, true) end)
    if not committed then Void.LetGo(group) end
    -- The queue validates each member's lobby character through the commit, so the round body goes on after it.
    if committed then
     for _, entry in ipairs(entries) do task.spawn(Void.Suit, entry.player, entry.frame) end
    end
    return committed, commitProblem
   end,
  })
  if not registered then warn("[R4 Preview Queue] registration: " .. tostring(registrationProblem)) end
 end
end

-- LIVE_LEVEL_SERVERS_20261008 (ServerStorage.Level5LaunchParty, invoked by "Live Level Server"). A party that was
-- given a server of its own for this level lands in that server's lobby and is taken in here: the same checks,
-- stream and join as the pad's launch, without a pad. `token` is the party's group table; a latecomer of the same
-- party is launched with the same token and joins the party that is already in.
-- Returns whether anybody got in, and how many.
do
	local old = ServerStorage:FindFirstChild("Level5LaunchParty")
	if old then old:Destroy() end
	local launchParty = Instance.new("BindableFunction")
	launchParty.Name = "Level5LaunchParty"
	launchParty.OnInvoke = function(players, token)
		if type(players) ~= "table" or type(token) ~= "table" then return false, 0, "BAD_REQUEST" end
		local model, exit = readyPreview()
		if not model or not hasFloor(model, exit) then return false, 0, "PREVIEW_NOT_READY" end
		if not Void.Claim(token) then
			for _, player in ipairs(players) do Void.TellBusy(player) end
			return false, 0, "LEVEL_IN_USE"
		end
		local party = {}
		for _, player in ipairs(players) do
			if typeof(player) == "Instance" and player:IsA("Player") and (nextUse[player] or 0) <= os.clock()
				and readyPlayer(player) then
				table.insert(party, player)
			end
		end
		local bridge = r3Bridge()
		local frames = bridge and bridge.PartyLandings and bridge.PartyLandings(model, exit, party) or {}
		-- everybody's client has the place before anybody is moved, so the party arrives together
		local streamed, waiting = {}, #party
		for _, player in ipairs(party) do
			nextUse[player] = math.huge
			frames[player] = frames[player] or upright(exit.Position, exit.CFrame.LookVector)
			task.spawn(function()
				local ok, ready = pcall(stream, player, frames[player].Position)
				streamed[player] = ok and ready == true
				waiting -= 1
			end)
		end
		local deadline = os.clock() + 30
		while waiting > 0 and os.clock() < deadline do task.wait(0.1) end
		local joined = 0
		for _, player in ipairs(party) do
			local ok, problem = pcall(function()
				if not streamed[player] then error("streaming did not finish") end
				local character, root = readyPlayer(player)
				local nowModel, nowExit = readyPreview()
				if not character or nowModel ~= model or nowExit ~= exit then error("the player or the level changed") end
				local previous = character:GetPivot()
				root.AssemblyLinearVelocity, root.AssemblyAngularVelocity = Vector3.zero, Vector3.zero
				character:PivotTo(frames[player])
				local entered, reason = Void.Join(player, token)
				if not entered then
					character:PivotTo(previous)
					error("join rejected: " .. tostring(reason))
				end
				joined += 1
				task.spawn(Void.Suit, player, frames[player])
			end)
			if not ok then warn("[Level5PreviewAccess] party launch, " .. player.Name .. ": " .. tostring(problem)) end
			release(player)
		end
		if joined == 0 then Void.LetGo(token) end
		return joined > 0, joined
	end
	launchParty.Parent = ServerStorage
end

local function hookDoor()
	local door = liveDoor()
	if door then ensurePrompt(door, ENTER_PROMPT, "ENTER LEVEL 5", "THE VOID ROOMS", onEnter) end
 local bridge = r3Bridge()
 local model = workspace:FindFirstChild("LobbyReimaginedPreview")
 if bridge then
  for _, host in ipairs(bridge.GetPreviewEntries(model, 5)) do
   ensurePrompt(host, ENTER_PROMPT, "ENTER LEVEL 5", "THE VOID ROOMS", onEnter)
  end
 end
end

local function hookExit()
	local _, exit = readyPreview()
	if exit then ensurePrompt(exit, RETURN_PROMPT, "RETURN TO LOBBY", "LEVEL 5", onReturn) end
end

local watchedModel, readyConnection
local function watchPreview(model)
	if watchedModel ~= model then
		if readyConnection then readyConnection:Disconnect() end
		watchedModel = model
		readyConnection = model and model:GetAttributeChangedSignal("Level5PreviewReady"):Connect(hookExit) or nil
	end
	hookExit()
end

Players.PlayerRemoving:Connect(function(player) nextUse[player] = nil end)
workspace.DescendantAdded:Connect(function(instance)
	local name = instance.Name
	if name == "ServerLobby" or name == "LevelDoorways" or name == "Level5SealedDoor" then
		hookDoor()
	elseif name == MODEL_NAME and instance.Parent == workspace and instance:IsA("Model") then
		watchPreview(instance)
	elseif name == EXIT_NAME then
		hookExit()
	end
end)
hookDoor()
watchPreview(workspace:FindFirstChild(MODEL_NAME))

-- Only a body that came in through the door or a queue belongs in the level.
task.spawn(function()
	local boundedModel, bounds, half
	while task.wait(0.5) do
		local model = readyPreview()
		local spawn = liveSpawn()
		if model and spawn then
			if boundedModel ~= model then
				local size
				bounds, size = model:GetBoundingBox()
				half = size * 0.5 + Vector3.new(8, 20, 8)
				boundedModel = model
			end
			for _, player in ipairs(Players:GetPlayers()) do
				-- (a round body is some level's business: one on its way from this level into the next is not sent home)
				if player:GetAttribute(IN_LEVEL) ~= true and player:GetAttribute("InRound") ~= true and not DevAccess.IsAllowed(player) then
					local character = player.Character
					local humanoid = character and character:FindFirstChildOfClass("Humanoid")
					local root = humanoid and humanoid.RootPart
					if root and humanoid.Health > 0 then
						local p = bounds:PointToObjectSpace(root.Position)
						if math.abs(p.X) <= half.X and math.abs(p.Y) <= half.Y and math.abs(p.Z) <= half.Z then
							character:PivotTo(upright(spawn.Position + Vector3.new(0, 4, 0), spawn.CFrame.LookVector))
						end
					end
				end
			end
		end
	end
end)

-- Observe ready publication/restoration; the original lobby watcher is unchanged.
local r3Watched = setmetatable({}, {__mode = "k"})
local function watchR3Lobby(model)
 if not model or not model:IsA("Model") or model.Name ~= "LobbyReimaginedPreview" or r3Watched[model] then return end
 r3Watched[model] = true
 local ready = model:GetAttributeChangedSignal("Ready"):Connect(hookDoor)
 local ancestry = model.AncestryChanged:Connect(function() if model.Parent == workspace then task.defer(hookDoor) end end)
 local descendants = model.DescendantAdded:Connect(function(part)
  if part:GetAttribute("R3DeveloperPreviewEntry") == 5 then task.defer(hookDoor) end
 end)
 model.Destroying:Once(function() ready:Disconnect(); ancestry:Disconnect(); descendants:Disconnect() end)
 task.defer(hookDoor)
end
workspace.ChildAdded:Connect(watchR3Lobby)
watchR3Lobby(workspace:FindFirstChild("LobbyReimaginedPreview"))


-- LEVEL5_VOID_20261004. The level's own rules (the map is static; tools/level5_void/import_level5.py builds it).
--   ROUND BODY: Void.Join marks the player, Void.Suit loads the hazmat round body after the queue has committed
--   (the queue validates the lobby character through its commit), Void.Leave puts the lobby avatar back.
--   NO CHECKPOINTS (owner, 2026-10-04): A FALL IS A DEATH. A body that drops well below the stretch it was on is
--   killed, and any death (a Reset too) ends that player's run: back to the lobby. The `Checkpoints` list is
--   still read, but only to know which room a player has reached (the plates and the room names need it).
--   PLATES: the door out of a room goes down when every member of a party who has not passed it yet stands on
--   the room's plate, and it STAYS down (owner, 2026-10-05: "it stays down permanently and does not go up
--   again"). It comes back up only when nobody is left in the level, so the next party finds every door shut.
--   A party is one queue launch; members ahead of the door do not count, members behind it do. The plate grows
--   with the number of players in the room, so they all fit.
--   BALLS: loose parts. One that leaves its ledge falls out of sight and is put back on its `Home` later.
--   THE CORRIDOR (owner, 2026-10-05), at the top of the last room's tower. When every member of a party who is
--   still walking stands inside it, a block comes down in the doorway behind them, the gate ahead sinks and the
--   two walls close: about sixteen seconds to the small room at the far end, which the walls do not reach. A
--   body still between them when they meet dies THERE and stays in the level: the party is told ("death", and
--   "partydown" when nobody is left standing), and an Emergency Re-entry stands it up in the small room.
--   THE FINISH: the lit doorway in that room. LEVEL 5 CLEARED with the two choices every other level's ending
--   offers: CONTINUE goes on into Level 6, BACK TO LOBBY goes home, and no choice in time continues.
do
	local HttpService = game:GetService("HttpService")
	local TweenService = game:GetService("TweenService")
	local FALL_MARGIN, GATE_TRAVEL = 40, 13.4
	local BALL_RETURN = 35
	-- the corridor: the walls take CLOSE_SECONDS to come within SHUT_GAP of each other, then shut; a body between
	-- them is dead from KILL_GAP. Walking the 198 studs from the gate takes 12.4 s, a sprint 7.6 s.
	local CLOSE_SECONDS, SHUT_GAP, KILL_GAP = 15.5, 5.0, 3.0
	local REENTRY_WINDOW, CHOICE_SECONDS, NEXT_LEVEL = 15, 15, 6
	-- DEATH_PARITY_20261008 (owner: "no kill cam like all the other maps, you just die and are thrown back to the
	-- lobby; there has to be spectating, buying a re-entry or using a banked one, and you spawn at the start of
	-- the section you have reached. So like the other levels"). EVERY death keeps the player in the level, dead,
	-- the way the last corridor's always did: the party is told ("death"), a dead player watches the others
	-- (SpectateController), nobody left standing is PARTY DOWN with its window, and an Emergency Re-entry (one
	-- paid per run, as in every level; a developer's free one any time) stands the player at the START OF THE
	-- SECTION they had reached. A fall is shown before it is a death: the client's camera lets go and watches
	-- the body drop for FALL_CAM seconds.
	local FALL_CAM = 2.4
	local SECTION = {rose = 1, blue = 2, amber = 3, mint = 4, violet = 5, coral = 6, orange = 7, crimson = 8, teal = 9, ivory = 10}
	local SOUND_IDS = {
		-- filled by tools/level5_void/install_sounds.py (ReplicatedStorage.Level5Void.Sounds carries the same)
	}
	local folder = ReplicatedStorage:FindFirstChild("Level5Void")
	if not folder then
		folder = Instance.new("Folder")
		folder.Name = "Level5Void"
		folder.Parent = ReplicatedStorage
	end
	local event = folder:FindFirstChild("Event")
	if not event then
		event = Instance.new("RemoteEvent")
		event.Name = "Event"
		event.Parent = folder
	end
	local members = {}        -- player -> {cp = checkpoint index, group = table shared by one queue launch}
	local leaving = setmetatable({}, { __mode = "k" })   -- players who have walked out of the exit door
	-- the remote every level's death, spectate, re-entry and round-end UI listens to (GameManager owns it)
	local function tell(player, ...)
		local remotes = ReplicatedStorage:FindFirstChild("Remotes")
		local status = remotes and remotes:FindFirstChild("RoundStatus")
		if status and player.Parent == Players then status:FireClient(player, ...) end
	end
	-- ACHIEVEMENTS_20261004: ZyntraMonetization owns the record; this only reports what happened.
	local function achieve(player, key)
		local bindable = ServerStorage:FindFirstChild("ZyntraAchievement")
		if bindable and player and player.Parent == Players then bindable:Fire(player, key) end
	end

	local cache = setmetatable({}, { __mode = "k" })
	local function checkpoints(model)
		local found = cache[model]
		if found == nil then
			local value = model:FindFirstChild("Checkpoints")
			local ok, decoded = pcall(function() return HttpService:JSONDecode(value.Value) end)
			found = ok and type(decoded) == "table" and #decoded > 0 and decoded or false
			cache[model] = found
		end
		return found or nil
	end
	local function checkpointFrame(model, row)
		local origin = model:GetAttribute("Origin")
		return upright(origin + Vector3.new(row.x, row.y + 3.5, row.z), Vector3.xAxis)
	end
	local function sound(parent, name, volume, looped)
		local template = folder:FindFirstChild("Sounds") and folder.Sounds:FindFirstChild(name)
		local found = parent:FindFirstChild(name)
		if found or not template then return found end
		found = template:Clone()
		found.Volume, found.Looped = volume, looped == true
		found.RollOffMode, found.RollOffMinDistance, found.RollOffMaxDistance = Enum.RollOffMode.InverseTapered, 14, 150
		found.Parent = parent
		return found
	end
	local function play(parent, name, volume)
		local clip = sound(parent, name, volume)
		if clip then clip:Play() end
	end

	-- PARTY_LOCK_20261008 (owner, from the live game, about Level 6: "everyone ends up in the same one ... make sure
	-- it does not happen with Level 5 either"). This level is ONE map per server, and two parties in it shared its
	-- doors and plates. Until a party gets a server of its own, the level takes ONE PARTY AT A TIME: a queue launch
	-- or an E entry is refused while another party is inside or on its way in, and the refused players are told why.
	-- A party is the `group` table of one launch. `entered` tells a party that is inside from one still streaming in,
	-- whose hold has to outlast its streaming.
	local hold = {token = nil, untilClock = 0, entered = false}
	function Void.Claim(group)
		if group == nil then return false end
		if next(members) ~= nil then
			if hold.token ~= group then return false end
		elseif hold.token ~= nil and hold.token ~= group and os.clock() < hold.untilClock then
			return false
		end
		if hold.token ~= group then hold.entered = false end
		hold.token, hold.untilClock = group, os.clock() + 90
		return true
	end
	-- LetGo(group): that party did not get in. LetGo(nil): somebody left; free if that emptied the level.
	function Void.LetGo(group)
		if next(members) ~= nil then return end
		if (group ~= nil and hold.token == group) or (group == nil and hold.entered) then
			hold.token, hold.untilClock, hold.entered = nil, 0, false
		end
	end
	function Void.Notice(player, heading, text)
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
		title.Text = heading
		title.Parent = card
		local body = title:Clone()
		body.Position, body.Size = UDim2.new(0, 14, 0, 42), UDim2.new(1, -28, 0, 52)
		body.Font, body.TextSize, body.TextWrapped, body.TextColor3 = Enum.Font.GothamMedium, 16, true, Color3.fromRGB(242, 242, 236)
		body.Text = text
		body.Parent = card
		card.Parent = gui
		gui.Parent = playerGui
		task.delay(7, function() gui:Destroy() end)
	end
	function Void.TellBusy(player)
		Void.Notice(player, "LEVEL 5 IS IN USE", "Another team is playing in there right now. Try again in a few minutes, or play another level.")
	end
	workspace:SetAttribute("Level5PartyLock", "PARTY_LOCK_20261008")
	-- replicated, for anything that wants to show it (a sign at the gate, a test): somebody is in the level or on the way in
	task.spawn(function()
		while true do
			workspace:SetAttribute("Level5InUse", next(members) ~= nil or (hold.token ~= nil and os.clock() < hold.untilClock))
			task.wait(1)
		end
	end)

	function Void.Join(player, group)
		if player.Parent ~= Players or members[player] then return false, "ALREADY_IN_LEVEL" end
		group = group or {}
		if not Void.Claim(group) then return false, "LEVEL_IN_USE" end
		hold.entered = true
		members[player] = {cp = 1, group = group, began = os.clock()}
		members[player].group.total = (members[player].group.total or 0) + 1
		player:SetAttribute(IN_LEVEL, true)
		player:SetAttribute(LIVE, true)            -- before InRound: the round features read both
		-- DEATH_PARITY_20261008: one paid Emergency Re-entry per run, as in every other level
		player:SetAttribute("ZyntraReentryUsed", false)
		return true
	end

	local finaleDeath = nil    -- set further down: a death in the last corridor has an ending of its own
	local function hookDeath(player, character, humanoid)
		humanoid.Died:Once(function()
			local record = members[player]
			if not record or player.Character ~= character then return end
			-- Loading the next level's body tears this one down, and a body torn down while it is alive reports
			-- a death (measured 2026-10-05: CONTINUE arrived in Level 6 as a corpse). That is not one.
			if record.continuing then return end
			if finaleDeath and finaleDeath(player, record, character) then return end
			event:FireClient(player, "died")
			task.wait(3)
			if members[player] == record and player.Parent == Players and player.Character == character then
				Void.Leave(player)                      -- no second try: the run is over
			end
		end)
	end

	local function loadRoundBody(player, frame)
		local load = ServerStorage:FindFirstChild("LoadGameplayCharacter")
		local previous = player.Character
		local ok, loaded = pcall(function() return load ~= nil and load:Invoke(player) end)
		local character = player.Character
		if player.Parent ~= Players or not members[player] then return end
		if not ok or not loaded or not character or character == previous then
			warn("[Level5PreviewAccess] round character did not load for " .. player.Name .. ": " .. tostring(loaded))
			return
		end
		local humanoid = character:WaitForChild("Humanoid", 5)
		local root = character:WaitForChild("HumanoidRootPart", 5)
		if not humanoid or not root or not members[player] then return end
		root.AssemblyLinearVelocity, root.AssemblyAngularVelocity = Vector3.zero, Vector3.zero
		character:PivotTo(frame)
		event:FireClient(player, "arrive", frame)
		hookDeath(player, character, humanoid)
	end

	function Void.Suit(player, frame)
		if player.Parent ~= Players or not members[player] then return end
		player:SetAttribute("InRound", true)
		loadRoundBody(player, frame)
	end

	function Void.Leave(player, quiet)
		local record = members[player]
		members[player], leaving[player] = nil, nil
		Void.LetGo(nil)                                 -- PARTY_LOCK_20261008: the last one out frees the level
		local live = player:GetAttribute(LIVE) == true
		player:SetAttribute(IN_LEVEL, nil)
		if not record then return end
		player:SetAttribute("ZyntraReentryUsed", false)
		player:SetAttribute(LIVE, nil)
		if player:GetAttribute("InRound") == true then player:SetAttribute("InRound", false) end
		if player.Parent ~= Players or quiet then return end
		if live then
			-- the same word GameManager sends a player it stands back up in the lobby: RoundUI clears its round state on it
			tell(player, "lobby")
			task.spawn(function()
				local load = ServerStorage:FindFirstChild("LoadLobbyCharacter")
				if load then pcall(load.Invoke, load, player) end
			end)
		end
	end

	-- LEVEL 5 CLEARED, with the two choices every other level's ending offers (owner, 2026-10-05). RoundUI draws
	-- them for GameManager's "win" word when it carries a deadline, a next level and a serial, and sends the
	-- choice back on the same remote with that serial.
	local winSerial = 500000                       -- far from GameManager's own
	local function sendWin(player, record)
		winSerial += 1
		record.choice = {serial = winSerial, deadline = workspace:GetServerTimeNow() + CHOICE_SECONDS}
		local group = record.group
		tell(player, "win", os.clock() - (record.began or os.clock()), group.done or 0,
			math.max(group.total or 1, group.done or 0), record.choice.deadline, NEXT_LEVEL, winSerial)
	end

	-- CONTINUE: the same player goes on into Level 6 without the lobby between. Level6PreviewAccess does it in two
	-- steps (stream the place, then take the player), so nobody is released here before the next level is ready.
	function Void.Continue(player)
		local record = members[player]
		if not record or record.continuing then return end
		record.continuing = true
		local enter = ServerStorage:FindFirstChild("Level6EnterFromLevel")
		local ok, ready = pcall(function() return enter ~= nil and enter:Invoke(player, "prepare", record.group) end)
		if ok and ready == true and members[player] == record and player.Parent == Players then
			tell(player, "lobby")                      -- clears LEVEL CLEARED
			-- This level's own marker goes first: its client stands down and the loading cover for Level 6 comes
			-- up while the body is still here. The shared marker and InRound stay set throughout.
			player:SetAttribute(IN_LEVEL, nil)
			local entered
			ok, entered = pcall(function() return enter:Invoke(player, "enter", record.group) end)
			if ok and entered == true then
				members[player], leaving[player] = nil, nil
				return
			end
			if members[player] == record and player.Parent == Players then player:SetAttribute(IN_LEVEL, true) end
		end
		record.continuing = nil
		if members[player] ~= record then return end
		warn("[Level5PreviewAccess] Level 6 did not take " .. player.Name .. "; back to the lobby")
		tell(player, "transitionfailed")
		task.delay(3, function()
			if members[player] == record then Void.Leave(player) end
		end)
	end

	Players.PlayerRemoving:Connect(function(player) members[player] = nil; Void.LetGo(nil) end)
	-- PARTY_LOCK_20261008: with one party at a time, somebody standing in here away from the keyboard would close the
	-- level to the whole server until Roblox's own 20 minutes are up. A living member who has not moved four studs
	-- in five minutes goes back to the lobby. Not while they wait out an ending (the cleared screen, a death in
	-- the last corridor): those have their own clocks.
	task.spawn(function()
		local IDLE_SECONDS = 300
		while true do
			task.wait(5)
			for player, record in pairs(members) do
				local character = player.Character
				local humanoid = character and character:FindFirstChildOfClass("Humanoid")
				local root = humanoid and humanoid.RootPart
				if not root or humanoid.Health <= 0 or record.choice or record.dead or record.continuing or leaving[player] then
					record.idleAt, record.idleSince = nil, nil
				elseif not record.idleAt or (root.Position - record.idleAt).Magnitude > 4 then
					record.idleAt, record.idleSince = root.Position, os.clock()
				elseif os.clock() - record.idleSince > IDLE_SECONDS then
					Void.Notice(player, "BACK IN THE LOBBY", "You did not move for 5 minutes, so the level was opened for the next team.")
					Void.Leave(player)
				end
			end
		end
	end)
	-- Back to lobby from inside the level (the exit chip sends this on the round remote). Level6PreviewAccess
	-- answers the same word for the shared marker; whichever runs first does the work, the other finds it done.
	task.spawn(function()
		local status = ReplicatedStorage:WaitForChild("Remotes"):WaitForChild("RoundStatus")
		status.OnServerEvent:Connect(function(player, message, serial)
			local record = members[player]
			if not record then return end
			if message == "leaveround" then
				if player:GetAttribute(LIVE) == true then status:FireClient(player, "leaveack") end
				Void.Leave(player)
			elseif (message == "continuenow" or message == "returntolobby") and record.choice
				and tonumber(serial) == record.choice.serial and not record.continuing then
				-- the two buttons of LEVEL 5 CLEARED
				if message == "continuenow" then
					Void.Continue(player)
				else
					status:FireClient(player, "returnpending", record.choice.serial)
					Void.Leave(player)
				end
			end
		end)
	end)

	local function living(player)
		local character = player.Character
		local humanoid = character and character:FindFirstChildOfClass("Humanoid")
		local root = humanoid and humanoid.RootPart
		if not root or humanoid.Health <= 0 or not character:IsDescendantOf(workspace) then return nil end
		-- a body's own Health script goes on healing a corpse (measured 2026-10-08: 0, 1, 2, 3 ...), and since
		-- DEATH_PARITY_20261008 a corpse stays in the level: it is the state that says dead
		if humanoid:GetState() == Enum.HumanoidStateType.Dead then return nil end
		return character, root
	end

	-- DEV_FALL_20261005 (owner: "dev button that triggers a fall and scream"). A developer in the level asks; every
	-- player in the level is told where and which, so they all see and hear the same body. Every second one is
	-- aimed at a pillar, when one stands near enough. The list is the Level 6 dev ESP's: the developers and the
	-- owner's own account, who is not on the general cheat list.
	do
		local nextFall = setmetatable({}, { __mode = "k" })
		local serial = 0
		event.OnServerEvent:Connect(function(player, what)
			if what ~= "devfall" or not members[player] or not DevAccess.IsLevel6PreviewAllowed(player) then return end
			if (nextFall[player] or 0) > os.clock() then return end
			nextFall[player] = os.clock() + 1.2
			local _, root = living(player)
			if not root then return end
			serial += 1
			for other in pairs(members) do
				event:FireClient(other, "devfall", root.Position, serial)
			end
		end)
	end

	-- FINALE_20261005: the corridor. The map carries the moving parts under `Finale` and the numbers in
	-- `FinaleData` (tools/level5_void/build_level5.py writes both); positions there are relative to `Origin`.
	local finale = {state = "idle"}
	local function finaleOf(model)
		if finale.model ~= model then
			finale.model, finale.data, finale.state = model, nil, "idle"
			local holder, parts = model:FindFirstChild("FinaleData"), model:FindFirstChild("Finale")
			local ok, data = pcall(function() return HttpService:JSONDecode(holder.Value) end)
			local block = parts and parts:FindFirstChild("CrusherBlock")
			local gate = parts and parts:FindFirstChild("CrusherGate")
			local walls = {}
			for _, part in ipairs(parts and parts:GetChildren() or {}) do
				if part.Name == "CrusherWall" and part:IsA("BasePart") then table.insert(walls, part) end
			end
			if ok and type(data) == "table" and block and gate and #walls == 2 then
				finale.data, finale.block, finale.gate, finale.walls = data, block, gate, walls
				finale.blockUp, finale.gateUp = block.Position, gate.Position
				finale.wallOpen = {walls[1].Position, walls[2].Position}
			end
		end
		return finale.data
	end
	-- `whole` = between the walls anywhere, from the block's face on; without it, past the line that counts as
	-- having walked in (a body that stood in the first five studs was squeezed but never counted as crushed)
	local function inCorridor(data, at, whole)
		return at.X > data.inside_x - (whole and 5.5 or 0) and at.X < data.end_x and math.abs(at.Z - data.z) < data.half + 22
			and at.Y > data.floor - 3 and at.Y < data.floor + data.height + 4
	end
	local function inRoom(data, at)
		return at.X >= data.end_x and at.X < data.room[2] + 5 and math.abs(at.Z - data.z) < data.room[3] + 4
			and at.Y > data.floor - 3 and at.Y < data.floor + data.height + 4
	end
	-- a sound on a part, heard down the corridor; the first of `names` that is installed
	local function noise(parent, names, volume, near, far, looped)
		local library = folder:FindFirstChild("Sounds")
		for _, name in ipairs(names) do
			local template = library and library:FindFirstChild(name)
			if template then
				local clip = parent:FindFirstChild(name) or template:Clone()
				clip.Volume, clip.Looped = volume, looped == true
				clip.RollOffMode, clip.RollOffMinDistance, clip.RollOffMaxDistance = Enum.RollOffMode.InverseTapered, near, far
				clip.Parent = parent
				clip:Play()
				return clip
			end
		end
		return nil
	end
	local function runCrusher(origin, data)
		local block, gate, walls = finale.block, finale.gate, finale.walls
		local function announce(...)
			for player in pairs(members) do event:FireClient(player, "crusher", ...) end
		end
		finale.state = "falling"
		-- nobody under the block: a body still in the doorway is moved on into the corridor
		for player in pairs(members) do
			local character, root = living(player)
			if root then
				local at = root.Position - origin
				if at.X > data.entry_x - 6 and at.X <= data.inside_x and math.abs(at.Z - data.z) < 9
					and math.abs(at.Y - data.floor - 3) < 8 then
					character:PivotTo(character:GetPivot() + Vector3.new(data.inside_x + 3 - at.X, 0, 0))
				end
			end
		end
		TweenService:Create(block, TweenInfo.new(0.42, Enum.EasingStyle.Quad, Enum.EasingDirection.In),
			{Position = finale.blockUp - Vector3.new(0, data.block_drop, 0)}):Play()
		task.wait(0.4)
		noise(block, {"l5_crusher_slam", "l5_gate_close"}, 1.6, 30, 420)
		announce("slam")
		task.wait(0.8)
		noise(gate, {"l5_crusher_groan", "l5_gate_open"}, 1.0, 24, 320)
		TweenService:Create(gate, TweenInfo.new(1.5, Enum.EasingStyle.Sine, Enum.EasingDirection.InOut),
			{Position = finale.gateUp - Vector3.new(0, data.height + 0.3, 0)}):Play()
		task.wait(0.9)
		finale.state = "closing"
		announce("closing", CLOSE_SECONDS)
		local grinds = {}
		for index, wall in ipairs(walls) do
			local open = finale.wallOpen[index]
			local toward = (open.Z - origin.Z > data.z) and -1 or 1
			TweenService:Create(wall, TweenInfo.new(CLOSE_SECONDS, Enum.EasingStyle.Linear),
				{Position = open + Vector3.new(0, 0, toward * (data.wall_travel - SHUT_GAP / 2))}):Play()
			table.insert(grinds, noise(wall, {"l5_crusher_grind", "l5_amb_scrape"}, 0.9, 30, 300, true))
		end
		task.wait(CLOSE_SECONDS)
		for index, wall in ipairs(walls) do                -- the last few studs all at once
			local open = finale.wallOpen[index]
			local toward = (open.Z - origin.Z > data.z) and -1 or 1
			TweenService:Create(wall, TweenInfo.new(0.7, Enum.EasingStyle.Quad, Enum.EasingDirection.In),
				{Position = open + Vector3.new(0, 0, toward * data.wall_travel)}):Play()
		end
		task.wait(0.7)
		for _, grind in ipairs(grinds) do grind:Stop() end
		noise(gate, {"l5_crusher_shut", "l5_gate_close"}, 1.8, 30, 420)
		finale.state = "shut"
		announce("shut")
		task.wait(4)
		-- open again for whoever comes next
		finale.state = "resetting"
		for index, wall in ipairs(walls) do
			TweenService:Create(wall, TweenInfo.new(2.6, Enum.EasingStyle.Sine, Enum.EasingDirection.InOut),
				{Position = finale.wallOpen[index]}):Play()
		end
		TweenService:Create(gate, TweenInfo.new(1.6, Enum.EasingStyle.Sine, Enum.EasingDirection.InOut), {Position = finale.gateUp}):Play()
		TweenService:Create(block, TweenInfo.new(1.4, Enum.EasingStyle.Sine, Enum.EasingDirection.InOut), {Position = finale.blockUp}):Play()
		task.wait(2.8)
		announce("reset")
		finale.state = "idle"
	end
	-- DEATH_PARITY_20261008: ANY death keeps the player in the level, dead (it used to be only a death in the
	-- corridor or the small room): the party is told, the store offers the Emergency Re-entry, and the loop below
	-- decides how it ends. `deadInFinale` remembers a death past the corridor's doorway: that one stands up in
	-- the small room, every other at the start of its section. Always true once the map is there.
	finaleDeath = function(player, record, character)
		if leaving[player] then return true end            -- already out of the door: the ending screen is theirs
		local model = readyPreview()
		local origin = model and model:GetAttribute("Origin")
		local data = model and finaleOf(model)
		local root = character:FindFirstChild("HumanoidRootPart")
		if not model or typeof(origin) ~= "Vector3" then return false end
		local at = root and root.Position - origin
		local crushed = record.crushed == true
		local inFinale = crushed or (data ~= nil and at ~= nil and (inCorridor(data, at, true) or inRoom(data, at)))
		local cause = crushed and "L5Crusher" or ((record.fallingAt or record.fellNow) and "L5Fall" or "Unknown")
		record.dead, record.crushed, record.fallingAt, record.fellNow = true, nil, nil, nil
		record.deadInFinale = inFinale or nil
		record.group.lastDeath, record.group.lastCause = player.Name, cause
		for other, state in pairs(members) do
			if state.group == record.group then
				tell(other, "death", player.Name, root and root.Position or origin, cause)
			end
		end
		event:FireClient(player, crushed and "crushed" or "died", cause)
		return true
	end
	-- Emergency Re-entry (ServerStorage.Level5Reentry; GameManager's ZyntraReentry reaches it through Level 6's,
	-- which hands on every player who carries this level's marker): back in the round body in the small room.
	do
		local old = ServerStorage:FindFirstChild("Level5Reentry")
		if old then old:Destroy() end
		local reentry = Instance.new("BindableFunction")
		reentry.Name = "Level5Reentry"
		-- `forced` = a developer in the level brought this player back (the revive-all cheat): free, whoever they are
		local function reenter(player, free, forced)
			local record = typeof(player) == "Instance" and player:IsA("Player") and members[player] or nil
			if not record or not record.dead or record.reentering then return false, "UNAVAILABLE" end
			if free == true and not forced and not DevAccess.IsAllowed(player) then return false, "UNAVAILABLE" end
			if free ~= true and player:GetAttribute("ZyntraReentryUsed") == true then return false, "UNAVAILABLE" end
			local model = readyPreview()
			local list = model and checkpoints(model)
			-- DEATH_PARITY_20261008: where they stand up. A death past the corridor's doorway: the small room at its
			-- end, as before. Any other: the first checkpoint of the section they had reached.
			local frame, first = nil, nil
			if record.deadInFinale then
				local spot = model and model:FindFirstChild("Level5Reentry")
				if spot and spot:IsA("BasePart") then
					local group = record.group
					group.reentered = (group.reentered or 0) + 1
					-- facing the exit door, each one a little to the side of the last
					frame = upright(spot.Position + Vector3.new(0, 0, ((group.reentered - 1) % 5 - 2) * 3.5), Vector3.xAxis)
				end
			elseif list and list[record.cp] then
				first = record.cp
				while first > 1 and list[first - 1].sec == list[record.cp].sec do first -= 1 end
				frame = checkpointFrame(model, list[first])
			end
			if not frame then return false, "UNAVAILABLE" end
			record.reentering = true
			local load = ServerStorage:FindFirstChild("LoadGameplayCharacter")
			local previous = player.Character
			local ok, loaded = pcall(function() return load ~= nil and load:Invoke(player) end)
			record.reentering = nil
			local character = player.Character
			if not ok or not loaded or not character or character == previous or members[player] ~= record then
				return false, "UNAVAILABLE"
			end
			local humanoid = character:WaitForChild("Humanoid", 5)
			local root = character:WaitForChild("HumanoidRootPart", 5)
			if not humanoid or not root or members[player] ~= record then return false, "UNAVAILABLE" end
			root.AssemblyLinearVelocity, root.AssemblyAngularVelocity = Vector3.zero, Vector3.zero
			-- Back to the section's first checkpoint in the books as well: the fall line is measured from the
			-- checkpoint a player holds, and a later one's would have this body dead where it stands.
			if first then record.cp = first end
			character:PivotTo(frame)
			record.dead, record.crushed, record.deadInFinale, record.fallingAt = nil, nil, nil, nil
			if free ~= true then player:SetAttribute("ZyntraReentryUsed", true) end
			hookDeath(player, character, humanoid)
			local group = record.group
			for other, state in pairs(members) do
				if state.group == group then tell(other, "reentry", player.Name) end
			end
			event:FireClient(player, "reentered")
			return true
		end
		reentry.OnInvoke = function(player, free) return reenter(player, free == true, false) end
		reentry.Parent = ServerStorage
		-- DEV_REVIVE_20261008 (owner: "a dev cheat button that re-enters all dead players in the level with us").
		-- A developer in the level asks (the Level 6 dev ESP's list, which has the owner's own account on it);
		-- everybody in the level who is dead stands up again at the start of their section, free, the asker too.
		local nextRevive = setmetatable({}, { __mode = "k" })
		event.OnServerEvent:Connect(function(player, what)
			if what ~= "devrevive" or not members[player] or not DevAccess.IsLevel6PreviewAllowed(player) then return end
			if (nextRevive[player] or 0) > os.clock() then return end
			nextRevive[player] = os.clock() + 2
			local count = 0
			for other, record in pairs(members) do
				if record.dead and not record.reentering then
					count += 1
					task.spawn(reenter, other, true, true)
				end
			end
			event:FireClient(player, "devrevived", count)
		end)
	end

	-- plates and gates
	local plates = {}
	local function plateRecords(model)
		if plates.model == model then return plates.list end
		plates.model, plates.list = model, {}
		local holder = model:FindFirstChild("Plates")
		for _, item in ipairs(holder and holder:GetChildren() or {}) do
			local plate, gate = item:FindFirstChild("Plate"), item:FindFirstChild("Gate")
			if plate and gate and plate:IsA("BasePart") and gate:IsA("BasePart") then
				local count = gate:FindFirstChild("Count")
				table.insert(plates.list, {
					section = item:GetAttribute("SectionIndex"), folder = item, plate = plate, gate = gate,
					rest = plate:GetAttribute("Rest") or plate.Position, closed = gate:GetAttribute("Closed") or gate.Position,
					text = count and count:FindFirstChild("Text"), radius = 4.1, open = false, locked = false, pressed = false,
				})
			end
		end
		return plates.list
	end
	local function movePlate(record, radius, pressed, complete)
		if math.abs(radius - record.radius) > 0.05 or pressed ~= record.pressed then
			record.radius, record.pressed = radius, pressed
			TweenService:Create(record.plate, TweenInfo.new(0.35, Enum.EasingStyle.Quad, Enum.EasingDirection.Out), {
				Size = Vector3.new(0.5, radius * 2, radius * 2),
				CFrame = CFrame.new(record.rest - Vector3.new(0, pressed and 0.2 or 0, 0)) * CFrame.Angles(0, 0, math.rad(90)),
			}):Play()
			local bed = record.folder:FindFirstChild("PlateBed")
			if bed then bed.Size = Vector3.new(0.12, radius * 2 + 1.2, radius * 2 + 1.2) end
			play(record.plate, pressed and "l5_plate_down" or "l5_plate_up", 0.5)
		end
		if complete ~= record.complete then
			record.complete = complete
			record.plate.Material = complete and Enum.Material.Neon or Enum.Material.SmoothPlastic
			local hum = sound(record.plate, "l5_plate_hum", 0.22, true)
			if hum then if complete then hum:Play() else hum:Stop() end end
		end
	end
	local function moveGate(record, open)
		if record.open == open then return end
		record.open = open
		record.folder:SetAttribute("Open", open)
		local goal = record.closed - Vector3.new(0, open and GATE_TRAVEL or 0, 0)
		TweenService:Create(record.gate, TweenInfo.new(open and 2.6 or 1.8, Enum.EasingStyle.Sine, Enum.EasingDirection.InOut),
			{Position = goal}):Play()
		play(record.gate, open and "l5_gate_open" or "l5_gate_close", 0.6)
	end

	-- balls
	local falling = setmetatable({}, { __mode = "k" })
	local function tendBalls(model)
		local holder = model:FindFirstChild("Balls")
		for _, ball in ipairs(holder and holder:GetChildren() or {}) do
			local home = ball:GetAttribute("Home")
			if ball:IsA("BasePart") and typeof(home) == "Vector3" and not falling[ball]
				and ball.Position.Y < home.Y - 30 then
				falling[ball] = true
				-- whoever stands nearest the ledge it left pushed it
				local nearest, gap = nil, 18
				for player, state in pairs(members) do
					local character = player.Character
					local root = character and character:FindFirstChild("HumanoidRootPart")
					local distance = root and (root.Position - home).Magnitude
					if distance and distance < gap then nearest, gap = player, distance end
				end
				if nearest then
					members[nearest].balls = (members[nearest].balls or 0) + 1
					if members[nearest].balls == 5 then achieve(nearest, "L5Balls") end
				end
				play(ball, "l5_ball_fall", 0.7)
				task.delay(1.6, function()
					if not ball.Parent then return end
					-- Out of sight now (about 500 studs down). It must not keep falling: FallenPartsDestroyHeight
					-- deletes a part for good, and at 5 s it was already past it. Hold it where it is, so the fall
					-- sound stays below, and put it back on its ledge later.
					ball.Anchored, ball.CanCollide, ball.Transparency = true, false, 1
					ball.AssemblyLinearVelocity, ball.AssemblyAngularVelocity = Vector3.zero, Vector3.zero
					task.wait(BALL_RETURN)
					if not ball.Parent then return end
					for _, player in ipairs(Players:GetPlayers()) do      -- never drop it onto someone's head
						local _, root = living(player)
						if root and (root.Position - home).Magnitude < 6 then task.wait(6) break end
					end
					ball.CFrame = CFrame.new(home)
					ball.Transparency, ball.CanCollide, ball.Anchored = 0, true, false
					falling[ball] = nil
				end)
			end
		end
	end

	task.spawn(function()
		while true do
			task.wait(0.15)
			local model = readyPreview()
			local origin = model and model:GetAttribute("Origin")
			local list = model and checkpoints(model)
			local finish = model and model:FindFirstChild("Level5Finish")
			if typeof(origin) ~= "Vector3" or not list then continue end
			local inSection = {}
			for player, record in pairs(members) do
				-- Level6PreviewAccess may have answered a leave for the shared marker: finish it here
				if player:GetAttribute(LIVE) ~= true and player:GetAttribute("InRound") ~= true and record.suited then
					members[player] = nil
					player:SetAttribute(IN_LEVEL, nil)
					continue
				end
				if player:GetAttribute("InRound") == true then record.suited = true end
				-- LEVEL 5 CLEARED is up: no choice in time goes on, as its countdown says
				if record.choice and not record.continuing and workspace:GetServerTimeNow() >= record.choice.deadline then
					task.spawn(Void.Continue, player)
				end
				-- On the way into Level 6 the player is still on this list for a second or two while their new
				-- body already stands THERE, which from here is 500 studs under this level: it is not a fall
				-- (measured 2026-10-05: the fall rule killed every body that continued).
				if record.continuing then continue end
				local character, root = living(player)
				if not character then continue end
				local at = root.Position - origin
				for index = record.cp + 1, #list do
					local row = list[index]
					if math.abs(at.X - row.x) < 11 and math.abs(at.Z - row.z) < 13 and math.abs(at.Y - 3 - row.y) < 7 then
						local newSection = SECTION[row.sec] ~= SECTION[list[record.cp].sec]
						record.cp = index
						if newSection then event:FireClient(player, "checkpoint", index, #list, row.sec, true) end
						if newSection and row.sec == "mint" then achieve(player, "L5Mint") end
						if newSection and row.sec == "coral" then achieve(player, "L5Coral") end
					end
				end
				local row = list[record.cp]
				local section = SECTION[row.sec]
				inSection[section] = (inSection[section] or 0) + 1
				if at.Y < row.low - FALL_MARGIN then
					record.fell = true
					if not record.fallingAt then
						-- DEATH_PARITY_20261008: the fall is shown first (the client's fall camera), then it is a death
						record.fallingAt = os.clock()
						event:FireClient(player, "falling", FALL_CAM)
					elseif os.clock() - record.fallingAt >= FALL_CAM then
						record.fellNow = true
						local humanoid = character:FindFirstChildOfClass("Humanoid")
						if humanoid then humanoid.Health = 0 end   -- the Died hook keeps them in the level, dead
					end
				elseif finish and finish:IsA("BasePart") and (root.Position - finish.Position).Magnitude < 7 and not leaving[player] then
					leaving[player] = true
					event:FireClient(player, "finish")
					achieve(player, "FirstClearLevel5")
					if not record.fell then achieve(player, "L5NoFall") end
					-- The same LEVEL CLEARED screen every other level ends on, with its two choices.
					record.group.done = (record.group.done or 0) + 1
					-- LEVEL_LEADERBOARDS_20261008: this player's own time, from entering the level to their own finish
					do
						local board = ServerStorage:FindFirstChild("LevelTimeReported")
						if board and record.began then board:Fire(player, 5, os.clock() - record.began) end
					end
					sendWin(player, record)
				end
			end
			-- THE CORRIDOR
			local data = finaleOf(model)
			if data then
				if finale.state == "idle" then
					-- every member of a party who is still walking is inside, and one of them came in by the doorway
					local parties = {}
					for player, record in pairs(members) do
						if record.dead or leaving[player] then continue end
						local tally = parties[record.group] or {all = 0, inside = 0, arrived = 0}
						parties[record.group] = tally
						tally.all += 1
						local _, root = living(player)
						local at = root and root.Position - origin
						if at and inCorridor(data, at) then
							tally.inside += 1
							if at.X < data.gate_x then tally.arrived += 1 end
						elseif at and inRoom(data, at) then
							tally.inside += 1
						end
					end
					for group, tally in pairs(parties) do
						if tally.arrived > 0 and tally.inside == tally.all then
							task.spawn(runCrusher, origin, data)
							break
						elseif tally.arrived > 0 and os.clock() >= (group.waitTold or 0) then
							-- somebody stands at the shut gate and the rest are still climbing: say what it is waiting for
							group.waitTold = os.clock() + 7
							for player, record in pairs(members) do
								if record.group == group then event:FireClient(player, "crusher", "waiting", tally.inside, tally.all) end
							end
						end
					end
				elseif finale.state == "closing" or finale.state == "shut" then
					local gap = math.abs(finale.walls[1].Position.Z - finale.walls[2].Position.Z) - finale.walls[1].Size.Z
					for player, record in pairs(members) do
						local character, root = living(player)
						local at = root and root.Position - origin
						-- between the walls when they meet, or already inside one of them
						if at and inCorridor(data, at, true) and (gap < KILL_GAP or math.abs(at.Z - data.z) > gap / 2 + 1.2) then
							record.crushed = true
							local humanoid = character:FindFirstChildOfClass("Humanoid")
							if humanoid then humanoid.Health = 0 end
						end
					end
				end
				-- how it ends for the dead: with somebody of the party still walking they wait (and can re-enter);
				-- when nobody is, they get REENTRY_WINDOW more seconds, then the party's ending
				local parties = {}
				for player, record in pairs(members) do
					local tally = parties[record.group] or {walking = 0, dead = {}}
					parties[record.group] = tally
					if record.dead then
						table.insert(tally.dead, player)
					elseif not leaving[player] then
						tally.walking += 1
					end
				end
				for group, tally in pairs(parties) do
					if #tally.dead == 0 or tally.walking > 0 then
						if group.endAt then
							group.endAt = nil
							if group.wiped then
								group.wiped = nil
								for _, player in ipairs(tally.dead) do tell(player, "partydownclear") end
							end
						end
					elseif not group.endAt then
						group.endAt = os.clock() + REENTRY_WINDOW
						if (group.done or 0) == 0 then               -- nobody made it: the PARTY DOWN card and its countdown
							group.wiped = true
							for _, player in ipairs(tally.dead) do
								tell(player, "partydown", REENTRY_WINDOW, group.lastDeath, group.lastCause or "Unknown")
							end
						end
					elseif os.clock() >= group.endAt then
						group.endAt, group.wiped = nil, nil
						for _, player in ipairs(tally.dead) do
							local record = members[player]
							record.dead = nil
							leaving[player] = true
							if (group.done or 0) > 0 then
								sendWin(player, record)                   -- "THE OTHERS FOUND A WAY OUT", and the same two choices
							else
								tell(player, "lose", os.clock() - (record.began or os.clock()), 0, group.total or 1)
								task.delay(5, function()
									if members[player] == record then Void.Leave(player) end
								end)
							end
						end
					end
				end
			end
			local empty = next(members) == nil
			for _, record in ipairs(plateRecords(model)) do
				if record.locked then
					-- this door has gone down and stays down; the plate stays pressed and lit, its hum fades out
					if empty then
						record.locked, record.quiet = false, nil
						moveGate(record, false)
						movePlate(record, 4.1, false, false)
					elseif not record.quiet and os.clock() - record.lockedAt > 3 then
						record.quiet = true
						local hum = record.plate:FindFirstChild("l5_plate_hum")
						if hum then hum:Stop() end
					end
					continue
				end
				local radius = 3.2 + 0.9 * math.max(1, inSection[record.section] or 0)
				-- who stands on it, and which parties are complete on it
				local standing, need, on = 0, {}, {}
				for player, state in pairs(members) do
					if state.dead then continue end                -- DEATH_PARITY_20261008: the dead are not waited for
					local _, root = living(player)
					local section = SECTION[list[state.cp].sec]
					if section > record.section then continue end
					need[state.group] = (need[state.group] or 0) + 1
					if root and section == record.section then
						local offset = root.Position - record.rest
						if offset.X * offset.X + offset.Z * offset.Z <= radius * radius and offset.Y > 0 and offset.Y < 7 then
							standing += 1
							on[state.group] = (on[state.group] or 0) + 1
						end
					end
				end
				local complete, best, bestNeed = false, 0, 1
				for group, count in pairs(on) do
					if count >= need[group] then complete = true end
					if count > best then best, bestNeed = count, need[group] end
				end
				if record.text then record.text.Text = best .. " / " .. bestNeed end
				record.folder:SetAttribute("On", best)
				record.folder:SetAttribute("Need", bestNeed)
				movePlate(record, radius, complete, complete)      -- the plate only goes down under a whole party (owner, 2026-10-04)
				if complete then
					record.locked, record.lockedAt = true, os.clock()
					moveGate(record, true)
					if standing >= 2 then
						for player, state in pairs(members) do
							local _, root = living(player)
							local offset = root and root.Position - record.rest
							if offset and SECTION[list[state.cp].sec] == record.section
								and offset.X * offset.X + offset.Z * offset.Z <= radius * radius and not state["lift" .. record.section] then
								state["lift" .. record.section] = true
								achieve(player, "L5TeamLift")
							end
						end
					end
				end
			end
			tendBalls(model)
		end
	end)
end
