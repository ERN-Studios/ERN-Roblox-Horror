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
		Void.Join(player, {})
		task.spawn(Void.Suit, player, frame)
	end)
 finishR3Entry(r3Owner)
	release(player)
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
    local model, exit = readyPreview()
    local returnPrompt = exit and exit:FindFirstChild(RETURN_PROMPT)
    if not model or not returnPrompt or not returnPrompt:IsA("ProximityPrompt")
     or not returnPrompt.Enabled or not hasFloor(model, exit) then return false, "PREVIEW_NOT_READY" end
    local entries, problem = bridge.PreparePreviewGroup(context, model, exit, stream)
    if not entries then return false, problem end
    local group = {}
    local committed, commitProblem = bridge.CommitPreviewGroup(context, entries, function(entry)
     return Void.Join(entry.player, group)
    end, function(entry) Void.Leave(entry.player, true) end)
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
				if player:GetAttribute(IN_LEVEL) ~= true and not DevAccess.IsAllowed(player) then
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
--   CHECKPOINTS: every wide landing is one (`Checkpoints`, in route order). A FALL IS NOT A DEATH: there is no
--   bottom to land on, so a body that drops well below the stretch after its last checkpoint is stood back up
--   on that checkpoint. A real death (Reset) respawns the round body there too.
--   PLATES: the door out of a room opens while every member of a party who has not passed it yet stands on the
--   room's plate. A party is one queue launch; members ahead of the door do not count, members behind it do.
--   The plate grows with the number of players in the room, so they all fit.
--   BALLS: loose parts. One that leaves its ledge falls out of sight and is put back on its `Home` later.
--   THE FINISH: the lit doorway at the bottom of the last room returns the player to the lobby.
do
	local HttpService = game:GetService("HttpService")
	local TweenService = game:GetService("TweenService")
	local FALL_MARGIN, GATE_TRAVEL, GATE_HOLD = 40, 13.4, 8
	local BALL_RETURN = 35
	local SECTION = {rose = 1, blue = 2, amber = 3, mint = 4, violet = 5}
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

	function Void.Join(player, group)
		if player.Parent ~= Players or members[player] then return false, "ALREADY_IN_LEVEL" end
		members[player] = {cp = 1, group = group or {}}
		player:SetAttribute(IN_LEVEL, true)
		player:SetAttribute(LIVE, true)            -- before InRound: the round features read both
		return true
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
		humanoid.Died:Once(function()
			task.wait(2.5)
			local record = members[player]
			local model = readyPreview()
			local list = model and checkpoints(model)
			if record and list and player.Parent == Players and player.Character == character then
				loadRoundBody(player, checkpointFrame(model, list[record.cp]))
			end
		end)
	end

	function Void.Suit(player, frame)
		if player.Parent ~= Players or not members[player] then return end
		player:SetAttribute("InRound", true)
		loadRoundBody(player, frame)
	end

	function Void.Leave(player, quiet)
		local record = members[player]
		members[player] = nil
		local live = player:GetAttribute(LIVE) == true
		player:SetAttribute(IN_LEVEL, nil)
		if not record then return end
		player:SetAttribute(LIVE, nil)
		if player:GetAttribute("InRound") == true then player:SetAttribute("InRound", false) end
		if player.Parent ~= Players or quiet then return end
		if live then
			-- the same word GameManager sends a player it stands back up in the lobby: RoundUI clears its round state on it
			local remotes = ReplicatedStorage:FindFirstChild("Remotes")
			local status = remotes and remotes:FindFirstChild("RoundStatus")
			if status then status:FireClient(player, "lobby") end
			task.spawn(function()
				local load = ServerStorage:FindFirstChild("LoadLobbyCharacter")
				if load then pcall(load.Invoke, load, player) end
			end)
		end
	end

	Players.PlayerRemoving:Connect(function(player) members[player] = nil end)
	-- Back to lobby from inside the level (the exit chip sends this on the round remote). Level6PreviewAccess
	-- answers the same word for the shared marker; whichever runs first does the work, the other finds it done.
	task.spawn(function()
		local status = ReplicatedStorage:WaitForChild("Remotes"):WaitForChild("RoundStatus")
		status.OnServerEvent:Connect(function(player, message)
			if message ~= "leaveround" or not members[player] then return end
			if player:GetAttribute(LIVE) == true then status:FireClient(player, "leaveack") end
			Void.Leave(player)
		end)
	end)

	local function living(player)
		local character = player.Character
		local humanoid = character and character:FindFirstChildOfClass("Humanoid")
		local root = humanoid and humanoid.RootPart
		if not root or humanoid.Health <= 0 or not character:IsDescendantOf(workspace) then return nil end
		return character, root
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
					text = count and count:FindFirstChild("Text"), radius = 4.1, open = false, openUntil = 0, pressed = false,
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

	local leaving = setmetatable({}, { __mode = "k" })
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
				local character, root = living(player)
				if not character then continue end
				local at = root.Position - origin
				for index = record.cp + 1, #list do
					local row = list[index]
					if math.abs(at.X - row.x) < 11 and math.abs(at.Z - row.z) < 13 and math.abs(at.Y - 3 - row.y) < 7 then
						local newSection = SECTION[row.sec] ~= SECTION[list[record.cp].sec]
						record.cp = index
						event:FireClient(player, "checkpoint", index, #list, row.sec, newSection)
					end
				end
				local row = list[record.cp]
				local section = SECTION[row.sec]
				inSection[section] = (inSection[section] or 0) + 1
				if at.Y < row.low - FALL_MARGIN then
					root.AssemblyLinearVelocity, root.AssemblyAngularVelocity = Vector3.zero, Vector3.zero
					character:PivotTo(checkpointFrame(model, row))
					event:FireClient(player, "fell")
				elseif finish and finish:IsA("BasePart") and (root.Position - finish.Position).Magnitude < 7 and not leaving[player] then
					leaving[player] = true
					event:FireClient(player, "finish")
					task.delay(2.2, function()
						leaving[player] = nil
						if members[player] then Void.Leave(player) end
					end)
				end
			end
			for _, record in ipairs(plateRecords(model)) do
				local radius = 3.2 + 0.9 * math.max(1, inSection[record.section] or 0)
				-- who stands on it, and which parties are complete on it
				local standing, need, on = 0, {}, {}
				for player, state in pairs(members) do
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
				movePlate(record, radius, standing > 0, complete)
				if complete then record.openUntil = os.clock() + GATE_HOLD end
				local wantOpen = os.clock() < record.openUntil
				if not wantOpen and record.open then
					for player in pairs(members) do                  -- never close on a body in the doorway
						local _, root = living(player)
						if root and math.abs(root.Position.X - record.closed.X) < 7 and math.abs(root.Position.Z - record.closed.Z) < 7 then
							wantOpen = true
						end
					end
				end
				moveGate(record, wantOpen)
			end
			tendBalls(model)
		end
	end)
end
