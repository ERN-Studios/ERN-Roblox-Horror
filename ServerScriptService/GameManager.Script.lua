-- GameManager (v4 -- lobby queue into the existing elevator round)

local Players = game:GetService("Players")
local RS = game:GetService("ReplicatedStorage")
local TweenService = game:GetService("TweenService")
local TeleportService = game:GetService("TeleportService")
local RunService = game:GetService("RunService")
local StarterPlayer = game:GetService("StarterPlayer")
local ServerStorage = game:GetService("ServerStorage")
local Debris = game:GetService("Debris")
local PhysicsService = game:GetService("PhysicsService")
local Lighting = game:GetService("Lighting")
local DevAccess = require(RS:WaitForChild("DevAccess"))

-- Every rule about what a finished level leads to, who the destination is still
-- waiting for and who owns an unfinished transfer lives in ONE module. The
-- completion path below calls Routing.* on every win; nothing here used to
-- require it, so every win could error. The numbers the module owns were also
-- duplicated as locals further down, so a suite could pass against one value
-- while production ran another.
local Routing = require(script.Parent:WaitForChild("Round Completion Routing"))
-- require() caches ONE module table per server, so stamping this host's name
-- into it lets the test suite -- which requires the same ModuleScript and
-- therefore holds the same table -- prove that GameManager really loaded it
-- rather than re-deriving the completion rules inline. The attribute is the
-- same claim in a form the client and the console can see.
Routing.LoadedBy = script:GetFullName()
workspace:SetAttribute(Routing.LoadedAttribute, Routing.Version)
do
	-- A live answering probe rather than a stored value. OnInvoke cannot be
	-- serialised into the place file, and the numbers below are read out of the
	-- module at the moment of the call, so a reply is proof that this running
	-- host both loaded the module and is using it for the completion rules.
	local routingProbe = ServerStorage:FindFirstChild(Routing.ProbeName)
	if not routingProbe or not routingProbe:IsA("BindableFunction") then
		if routingProbe then routingProbe:Destroy() end
		routingProbe = Instance.new("BindableFunction")
		routingProbe.Name = Routing.ProbeName
		routingProbe.Parent = ServerStorage
	end
	routingProbe.OnInvoke = function()
		return {
			Host = script:GetFullName(),
			Version = Routing.Version,
			MaxLevel = Routing.MaxLevel,
			PostWinSeconds = Routing.PostWinSeconds,
			NextAfterOne = Routing.NextLevel(1),
			NextAfterTwo = Routing.NextLevel(2),
			EndsAtThree = Routing.NextLevel(Routing.MaxLevel) == nil,
		}
	end
end

local zyntraLevelCompleted = ServerStorage:FindFirstChild("ZyntraLevelCompleted")
if not zyntraLevelCompleted then
 zyntraLevelCompleted = Instance.new("BindableEvent")
 zyntraLevelCompleted.Name = "ZyntraLevelCompleted"
 zyntraLevelCompleted.Parent = ServerStorage
end
local zyntraReentry = ServerStorage:FindFirstChild("ZyntraReentry")
if not zyntraReentry then
 zyntraReentry = Instance.new("BindableFunction")
 zyntraReentry.Name = "ZyntraReentry"
 zyntraReentry.Parent = ServerStorage
end
zyntraReentry.OnInvoke = function() return false end

local remotes = RS:WaitForChild("Remotes")
local status = remotes:WaitForChild("RoundStatus")
local queueConfig = remotes:FindFirstChild("ConfigureQueue")
if not queueConfig then
 queueConfig = Instance.new("RemoteEvent")
 queueConfig.Name = "ConfigureQueue"
 queueConfig.Parent = remotes
end
local dropGlowstick = remotes:FindFirstChild("DropGlowstick")
if not dropGlowstick then
 dropGlowstick = Instance.new("RemoteEvent")
 dropGlowstick.Name = "DropGlowstick"
 dropGlowstick.Parent = remotes
end

local Master = require(game:GetService("ReplicatedStorage"):WaitForChild("MasterConfiguration"))
local QUEUE_TIME = Master.Effective("Lobby_QueueSeconds", 10)
local FAST_QUEUE_TIME = 3
local MAX_PLAYERS_PER_STATION = 6
local ELEVATOR_TIME = Master.Effective("Lobby_ElevatorSeconds", 19)
local LOBBY_CENTER = Vector3.new(0, 30, -760)

Players.CharacterAutoLoads = false
workspace:SetAttribute("GenerateWorld", false)
workspace:SetAttribute("RoundActive", false)
workspace:SetAttribute("PostWinIntermissionActive", false)

-- A station launch creates a reserved server of this same place. Reserved servers
-- run the maze directly; public servers remain lightweight four-station lobbies.
local IS_RESERVED_ROUND_SERVER = game.PrivateServerId ~= "" and game.PrivateServerOwnerId == 0
local IS_STUDIO = RunService:IsStudio()
workspace:SetAttribute("ReservedRoundServer", IS_RESERVED_ROUND_SERVER)

-- Returning from a reserved level creates a fresh Player/client in the public
-- lobby. GetJoinData is server-trusted, so this marker is the durable distinction
-- between a new arrival (welcome once) and a party returning home (stay silent).
local function isReturnToLobbyArrival(player)
 local ok, joinData = pcall(function() return player:GetJoinData() end)
 local teleportData = ok and joinData and joinData.TeleportData
 return type(teleportData) == "table" and teleportData.ReturnToLobby == true
end

-- Levels that own a world module with a Build/Cleanup surface. Level 1 is the
-- attribute-driven MazeGenerator and is deliberately not listed here.
local LEVEL_GENERATORS = {
 [2] = "Level2Generator",
 [3] = "Level3Generator",
}

-- Always-on server authority for every developer command. Unlike the Level 1
-- entity script, GameManager remains active in both levels.
local devControl = remotes:WaitForChild("DevControl")
local NOCLIP_GROUP = "DevNoclip"
local noclipState = {}
local devControlRate = {}
local DEV_CONTROL_WINDOW = 1
local DEV_CONTROL_LIMIT = 12

local function allowDevControl(player)
 local now = os.clock()
 local bucket = devControlRate[player]
 if not bucket or now - bucket.startedAt >= DEV_CONTROL_WINDOW then
  devControlRate[player] = {startedAt = now, count = 1}
  return true
 end
 if bucket.count >= DEV_CONTROL_LIMIT then return false end
 bucket.count += 1
 return true
end
pcall(function() PhysicsService:RegisterCollisionGroup(NOCLIP_GROUP) end)
for _, group in ipairs(PhysicsService:GetRegisteredCollisionGroups()) do
 pcall(function()
  PhysicsService:CollisionGroupSetCollidable(NOCLIP_GROUP, group.name, false)
 end)
end

local function setServerNoclip(player, enabled)
 local char = player.Character
 if not char then return end
 if enabled then
  if noclipState[player] then return end
  local state = {parts = {}, added = nil}
  noclipState[player] = state
  local function disablePart(part)
   if not part:IsA("BasePart") then return end
   if state.parts[part] == nil then
    state.parts[part] = {group = part.CollisionGroup, collide = part.CanCollide}
   end
   part.CollisionGroup = NOCLIP_GROUP
   part.CanCollide = false
  end
  for _, part in ipairs(char:GetDescendants()) do disablePart(part) end
  state.added = char.DescendantAdded:Connect(disablePart)
 else
  local state = noclipState[player]
  if not state then return end
  noclipState[player] = nil
  if state.added then state.added:Disconnect() end
  for part, original in pairs(state.parts) do
   if part.Parent then
    part.CollisionGroup = original.group
    part.CanCollide = original.collide
   end
  end
 end
end

devControl.OnServerEvent:Connect(function(player, command, enabled)
 if not DevAccess.IsAllowed(player) then return end
 if type(command) ~= "string" or type(enabled) ~= "boolean" then return end
 if not allowDevControl(player) then return end
 if command == "fastQueue" then
  if IS_RESERVED_ROUND_SERVER then return end
  player:SetAttribute("DevFastQueue", enabled == true and true or nil)
  print("[GameManager] 3-second queue", enabled == true and "ON" or "OFF", "for", player.Name)
 elseif command == "pauseEntity" then
  workspace:SetAttribute("EntityPaused", enabled == true)
  print("[GameManager] all entities", enabled == true and "PAUSED" or "resumed", "by", player.Name)
 elseif command == "immunePush" then
  player:SetAttribute("DevPushImmune", enabled == true and true or nil)
  print("[GameManager] yell push-immunity", enabled == true and "ON" or "OFF", "for", player.Name)
 elseif command == "noclip" then
  setServerNoclip(player, enabled == true)
  print("[GameManager] server noclip", enabled == true and "ON" or "OFF", "for", player.Name)
 elseif command == "level2PumpPair" then
  if not enabled then return end
  local systems = script.Parent:FindFirstChild("Level 2 Systems")
  local objective = systems and systems:FindFirstChild("Level 2 Objective Controller")
  local ok = false
  if objective and objective:IsA("ModuleScript") then
   ok = pcall(function() require(objective).DevActivatePumpPair(player) end)
  end
  if not ok then
   player:SetAttribute("DevLevel2PumpBusy", false)
   player:SetAttribute("DevLevel2PumpStatus", "UNAVAILABLE")
   player:SetAttribute("DevLevel2PumpSerial",
    (tonumber(player:GetAttribute("DevLevel2PumpSerial")) or 0) + 1)
  end
 elseif command == "level3PreBlackout" then
  if not DevAccess.IsLevel3TimelineOwner(player) then return end
  local skip = ServerStorage:FindFirstChild("Level3DevSkipToPreBlackout")
  local timelineStatus = "NOT_RUNNING"
  if skip and skip:IsA("BindableFunction") then
   local ok, _, reason = pcall(skip.Invoke, skip)
   if ok and type(reason) == "string" then timelineStatus = reason end
  end
  player:SetAttribute("DevLevel3TimelineStatus", timelineStatus)
  player:SetAttribute("DevLevel3TimelineSerial",
   (tonumber(player:GetAttribute("DevLevel3TimelineSerial")) or 0) + 1)
  print("[GameManager] Level 3 timeline skip:", timelineStatus, "for", player.Name)
 end
end)

-- Numeric developer tuning, on its OWN remote.
--
-- DevControl carries `(command: string, enabled: boolean)` and refuses anything
-- else. Seven commands rest on that check; widening it to also carry numbers
-- would loosen the gate for all of them to serve one new caller. A separate
-- remote keeps its own contract narrow instead, and still shares DevAccess and
-- the same rate bucket.
--
-- The client is never the authority on what is a legal value: Master.SetOverride
-- runs Master.Coerce again here, against the registry's own range.
local devTuning = remotes:WaitForChild("DevTuning")
devTuning.OnServerEvent:Connect(function(player, key, value)
 if not DevAccess.IsAllowed(player) then return end
 if type(key) ~= "string" then return end
 if value ~= nil and type(value) ~= "number" then return end
 if not allowDevControl(player) then return end
 local applied, problem = Master.SetOverride(key, value)
 -- The answer rides back on the player rather than over the remote: the panel
 -- rebuilds itself from the replicated attributes anyway, so a reply channel
 -- would be a second source of truth for the same fact.
 player:SetAttribute("DevTuningStatus", if applied then "OK" else tostring(problem))
 player:SetAttribute("DevTuningSerial",
  (tonumber(player:GetAttribute("DevTuningSerial")) or 0) + 1)
 if applied then
  print(string.format("[GameManager] tuning %s = %s by %s",
   key, tostring(value), player.Name))
 end
end)

local inRound = {}
local roundBusy = false
local worldReady = false
local activeLevel = 1
local postWinSerial = 0
local activePostWin = nil
local pendingTeleports = {}
local elevatorApi = nil
local mazeStart, entityStart, entity

local GLOWSTICK_COOLDOWN = 5
local GLOWSTICK_COLORS = {
 Color3.fromRGB(65, 145, 255),  -- player 1: blue
 Color3.fromRGB(255, 65, 65),   -- player 2: red
 Color3.fromRGB(70, 235, 105),  -- player 3: green
 Color3.fromRGB(255, 220, 55),  -- player 4: yellow
 Color3.fromRGB(190, 90, 255),  -- player 5: purple
 Color3.fromRGB(55, 235, 225),  -- player 6: turquoise
}
local lastGlowstickDrop = {}

local function glowstickFolder()
 local folder = workspace:FindFirstChild("DroppedGlowsticks")
 if not folder then
  folder = Instance.new("Folder")
  folder.Name = "DroppedGlowsticks"
  folder.Parent = workspace
 end
 return folder
end

local function clearGlowsticks()
 local folder = workspace:FindFirstChild("DroppedGlowsticks")
 if folder then folder:Destroy() end
 table.clear(lastGlowstickDrop)
end

local function assignGlowstickSlots(participants, suppliedSlots)
 for index, player in ipairs(participants) do
  local deadline = os.clock() + 10
  while player.Parent and player:GetAttribute("ZyntraProfileLoaded") ~= true and os.clock() < deadline do
   task.wait(0.1)
  end
  local supplied = suppliedSlots and suppliedSlots[tostring(player.UserId)]
  local slot = math.clamp(math.floor(tonumber(supplied) or index), 1, #GLOWSTICK_COLORS)
  local customColor = player:GetAttribute("ZyntraOwnsCosmeticEquipment") == true
   and player:GetAttribute("ZyntraGlowstickColor") or nil
  player:SetAttribute("GlowstickSlot", slot)
  player:SetAttribute("GlowstickColor", typeof(customColor) == "Color3" and customColor or GLOWSTICK_COLORS[slot])
 end
end

dropGlowstick.OnServerEvent:Connect(function(player)
 if not inRound[player] or player:GetAttribute("Escaped") == true then return end
 local now = os.clock()
 if now - (lastGlowstickDrop[player] or -math.huge) < GLOWSTICK_COOLDOWN then return end
 local character = player.Character
 local humanoid = character and character:FindFirstChildOfClass("Humanoid")
 local root = character and character:FindFirstChild("HumanoidRootPart")
 if not (humanoid and humanoid.Health > 0 and root) then return end
 lastGlowstickDrop[player] = now

 local slot = math.clamp(math.floor(tonumber(player:GetAttribute("GlowstickSlot")) or 1),
  1, #GLOWSTICK_COLORS)
 local selectedColor = player:GetAttribute("GlowstickColor")
 local color = typeof(selectedColor) == "Color3" and selectedColor or GLOWSTICK_COLORS[slot]
 local look = Vector3.new(root.CFrame.LookVector.X, 0, root.CFrame.LookVector.Z)
 look = look.Magnitude > 0.01 and look.Unit or Vector3.new(0, 0, -1)
 local position = root.Position + look * 3 + Vector3.new(0, 0.3, 0)

 local stick = Instance.new("Part")
 stick.Name = ("Glowstick_P%d_%s"):format(slot, player.Name)
 stick.Shape = Enum.PartType.Cylinder
 stick.Size = Vector3.new(2.35, 0.34, 0.34)
 stick.Material = Enum.Material.Neon
 stick.Color = color
 stick.Anchored = false
 stick.CanCollide = true
 stick.CanTouch = false
 stick.CanQuery = true
 stick.CustomPhysicalProperties = PhysicalProperties.new(0.5, 0.72, 0.2, 1, 1)
 stick.CFrame = CFrame.lookAt(position, position + look) * CFrame.Angles(0, math.pi / 2, 0)
 stick:SetAttribute("OwnerUserId", player.UserId)
 stick:SetAttribute("GlowstickSlot", slot)
 stick.Parent = glowstickFolder()

 local light = Instance.new("PointLight")
 light.Name = "Glow"
 light.Color = color
 light.Brightness = 1.15
 light.Range = 15
 light.Shadows = false
 light.Parent = stick
 local a0 = Instance.new("Attachment"); a0.Position = Vector3.new(-1.05, 0, 0); a0.Parent = stick
 local a1 = Instance.new("Attachment"); a1.Position = Vector3.new(1.05, 0, 0); a1.Parent = stick
 local trail = Instance.new("Trail")
 trail.Attachment0, trail.Attachment1 = a0, a1
 trail.Color = ColorSequence.new(color)
 trail.Lifetime = 0.18
 trail.MinLength = 0.1
 trail.LightEmission = 1
 trail.Transparency = NumberSequence.new({
  NumberSequenceKeypoint.new(0, 0.35), NumberSequenceKeypoint.new(1, 1),
 })
 trail.Parent = stick

 stick.AssemblyLinearVelocity = look * 8 + Vector3.new(0, 2.5, 0)
 stick.AssemblyAngularVelocity = Vector3.new(math.random(-5, 5), math.random(-8, 8), math.random(-5, 5))
 pcall(function() stick:SetNetworkOwner(nil) end)
 -- Safety cleanup only; ordinary matches end long before this, so sticks remain
 -- useful breadcrumbs for the whole round.
 Debris:AddItem(stick, 20 * 60)
end)

-- StarterPlayer contains the project's gameplay StarterCharacter, so ordinary
-- LoadCharacterAsync spawns that rig. Lobby players instead load from their own
-- current Roblox HumanoidDescription; entering a level deliberately uses the
-- StarterCharacter again.
local lobbyDescriptions = {}
local characterLoadBusy = false

local function beginCharacterLoad()
 while characterLoadBusy do task.wait() end
 characterLoadBusy = true
end

local function finishCharacterLoad()
 characterLoadBusy = false
end

local function loadLobbyCharacter(player)
 if not (player and player.Parent) or inRound[player] then return false end
 local description = lobbyDescriptions[player.UserId]
 if not description then
  local ok, result = pcall(Players.GetHumanoidDescriptionFromUserIdAsync, Players, player.UserId)
  if ok and result then
   description = result
   lobbyDescriptions[player.UserId] = result
  else
   warn("[GameManager] Could not load lobby avatar for " .. player.Name .. ": " .. tostring(result))
  end
 end
 if not (player.Parent and not inRound[player]) then return false end

 -- LoadCharacterWithHumanoidDescriptionAsync still builds on a configured
 -- StarterCharacter. Temporarily park the hazmat gameplay rig while the load is
 -- serialized, otherwise its suit meshes remain underneath the lobby avatar.
 beginCharacterLoad()
 if not (player.Parent and not inRound[player]) then
  finishCharacterLoad()
  return false
 end
 local gameplayRig
 local ok, err = xpcall(function()
  gameplayRig = StarterPlayer:FindFirstChild("StarterCharacter")
  if gameplayRig then gameplayRig.Parent = ServerStorage end
  if description then
   player:LoadCharacterWithHumanoidDescriptionAsync(description:Clone())
  else
   player:LoadCharacterAsync()
  end
 end, debug.traceback)
 -- Always restore the authored gameplay rig and release the global character
 -- load lock, even if cloning/loading a HumanoidDescription throws.
 if gameplayRig and gameplayRig.Parent ~= StarterPlayer then
  local restored, restoreError = pcall(function() gameplayRig.Parent = StarterPlayer end)
  if not restored then warn("[GameManager] Could not restore StarterCharacter:", restoreError) end
 end
 finishCharacterLoad()
 if not ok then warn("[GameManager] Lobby character load failed:", err) end
 return ok
end

local function loadGameplayCharacter(player)
 beginCharacterLoad()
 local ok, err = pcall(player.LoadCharacterAsync, player)
 finishCharacterLoad()
 if not ok then warn("[GameManager] Gameplay character load failed:", err) end
 return ok
end

-- CharacterAutoLoads is off, so a player whose load fails has no Character at
-- all and `player.CharacterAdded:Wait()` never fires -- no timeout, no error.
-- The round-start loops are serial, so ONE failed load used to park the whole
-- thread: playRound never ran, roundBusy never cleared, and everyone else sat
-- behind the loading cover forever. Only Level 2 has a client-side backstop
-- (RoundUI's 35 s absolute cover lift); Levels 1 and 3 have none.
--
-- Everyone still in the server has to make it into the round, so this retries
-- instead of skipping. It gives up only once the player has actually left.
local CHARACTER_LOAD_ATTEMPTS = 4
local CHARACTER_LOAD_TIMEOUT = 6

local function spawnGameplayCharacter(player)
 for attempt = 1, CHARACTER_LOAD_ATTEMPTS do
  if player.Parent ~= Players then return nil end
  loadGameplayCharacter(player)
  -- task.wait returns real elapsed seconds. Do NOT use os.clock here: in the
  -- Studio server datamodel it measures CPU time, not wall time.
  local waited = 0
  while not player.Character and player.Parent == Players and waited < CHARACTER_LOAD_TIMEOUT do
   waited += task.wait()
  end
  if player.Character then return player.Character end
  warn(string.format("[GameManager] No gameplay character for %s (attempt %d/%d)",
   player.Name, attempt, CHARACTER_LOAD_ATTEMPTS))
 end
 return nil
end

local function buildLobby()
 return require(script.Parent:WaitForChild("TunnelLobbyBuilder")).Build(LOBBY_CENTER)
end

-- Recover automatically if a generated world was accidentally saved into the
-- place from Edit mode. Without this, Level 1 builds its maze on top of the
-- saved level while its Entity and puzzle scripts remain stored/disabled.
local function sanitizePersistedLevelState()
 local selected = workspace:GetAttribute("SelectedLevel")
 local stale = {}
 if workspace:FindFirstChild("PoolroomsLevel2") ~= nil
  or workspace:FindFirstChild("Level 2 Generated World") ~= nil
  or ServerStorage:FindFirstChild("StoredLevel1Entity") ~= nil
  or ServerStorage:FindFirstChild("Level 2 Stored Level 1 Entity") ~= nil
  or ServerStorage:FindFirstChild("StoredServerLobby") ~= nil
  or ServerStorage:FindFirstChild("Level 2 Stored Server Lobby") ~= nil
  or selected == 2 then
  stale[#stale + 1] = 2
 end
 if workspace:FindFirstChild("Level 3 Generated World") ~= nil
  or ServerStorage:FindFirstChild("Level 3 Stored Server Lobby") ~= nil
  or ServerStorage:FindFirstChild("Level 3 Stored Level 1 Entity") ~= nil
  or selected == 3 then
  stale[#stale + 1] = 3
 end
 if #stale == 0 then return end

 for _, level in ipairs(stale) do
  local ok, err = pcall(function()
   require(script.Parent:WaitForChild(LEVEL_GENERATORS[level])).Cleanup()
  end)
  if ok then
   warn("[GameManager] Recovered a persisted Level " .. level .. " edit-state before lobby startup")
  else
   warn("[GameManager] Could not recover persisted Level " .. level .. " state: " .. tostring(err))
  end
 end
end

sanitizePersistedLevelState()
local _lobbyModel, lobbySpawn, lobbyStations = buildLobby()

local function setStationDisplay(station, main, secondary, color)
 station.title.Text = main
 station.sub.Text = secondary or ""
 station.title.TextColor3 = color or station.color
end

local function scatterAt(char, pad, randomFacing)
 local hrp = char:WaitForChild("HumanoidRootPart", 8)
 if not (pad and hrp) then return end
 local ox = (math.random() - 0.5) * math.max(pad.Size.X - 4, 1)
 local oz = (math.random() - 0.5) * math.max(pad.Size.Z - 4, 1)
 local facing = randomFacing and math.random() * math.pi * 2 or math.pi -- lobby faces the launch square
 char:PivotTo(CFrame.new(pad.Position + Vector3.new(ox, 3.2, oz)) * CFrame.Angles(0, facing, 0))
end

-- RequestStreamAroundAsync decides whether a character lands on a floor or
-- through one. Start it before moving the character, then await that SAME request
-- before release. Keeping completion and success separate matters: pcall can
-- finish with an error, and an errored request must never be reported as streamed.
-- The wall-clock guard means even a hung engine call cannot anchor a player
-- forever; callers warn and release safely when the request fails or times out.
local STREAM_AROUND_TIMEOUT = 6

local function beginStreamAround(player, position, timeOut)
 local state = {Done = false, Succeeded = false}
 task.spawn(function()
  state.Succeeded = pcall(function()
   player:RequestStreamAroundAsync(position, timeOut)
  end)
  state.Done = true
 end)
 return state
end
local level3SlideStream = remotes:FindFirstChild("Level3SlideStream")
if not level3SlideStream then
 level3SlideStream = Instance.new("RemoteEvent")
 level3SlideStream.Name = "Level3SlideStream"
 level3SlideStream.Parent = remotes
end

local function awaitStreamAround(state, timeOut)
 local deadline = os.clock() + timeOut + 2
 while not state.Done and os.clock() < deadline do task.wait(0.1) end
 return state.Done and state.Succeeded
end

local function placeSafelyInElevator(player, char)
 local pad = workspace:FindFirstChild("ElevatorSpawn")
 local root = char and char:WaitForChild("HumanoidRootPart", 8)
 local hum = char and char:FindFirstChildOfClass("Humanoid")
 if not (pad and root and hum and hum.Health > 0) then return false end

 -- The lobby and maze are far apart. Keep the character server-anchored while
 -- the client streams the elevator region so it cannot fall through an unloaded floor.
 pad.CanCollide = true -- invisible emergency floor inside the cabin
 local streamed = beginStreamAround(player, pad.Position, STREAM_AROUND_TIMEOUT)
 root.Anchored = true
 root.AssemblyLinearVelocity = Vector3.zero
 root.AssemblyAngularVelocity = Vector3.zero
 local ox = (math.random() - 0.5) * math.max(pad.Size.X - 4, 1)
 local oz = (math.random() - 0.5) * math.max(pad.Size.Z - 3, 1)
 local isLevel2Pad = pad:GetAttribute("Level2_CompatibilityMarker") == true
 if isLevel2Pad then
  local forward = Vector3.new(pad.CFrame.LookVector.X, 0, pad.CFrame.LookVector.Z).Unit
  local side = Vector3.new(pad.CFrame.RightVector.X, 0, pad.CFrame.RightVector.Z).Unit
  local position = pad.Position + side * ox + forward * oz + Vector3.new(0, 4, 0)
  char:PivotTo(CFrame.lookAt(position, position + forward))
 else
  local position = pad.Position + Vector3.new(ox, 4, oz)
  char:PivotTo(CFrame.lookAt(position, position + Vector3.new(1, 0, 0)))
 end

 local shield = Instance.new("ForceField")
 shield.Name = "LobbyTransferShield"
 shield.Visible = false
 shield.Parent = char
 task.delay(2.5, function()
  -- Streaming is awaited rather than fired and forgotten, but a timeout is not
  -- a reason to strand anyone: the character stays anchored for the grace below
  -- either way, and an un-streamed release is still better than a permanent one.
  local didStream = awaitStreamAround(streamed, STREAM_AROUND_TIMEOUT)
  if not didStream then
   warn("GameManager: elevator region did not stream in for " .. player.Name)
  end
  -- Level 2's loading cover can outlive this fixed placement grace, and the
  -- cover does not block input (loadingFrame sets neither .Active nor .Modal,
  -- unlike queueShade). Unanchoring on the timer alone would hand back control
  -- while the player is still looking at black, on an arrival deck ringed by
  -- water. Hold until the round is actually live, which by construction is
  -- after every client has dropped its cover. Levels 1 and 3 never enter this
  -- branch: they are already out of the cover and inside the sealed cabin.
  if activeLevel == 2 then
   local deadline = os.clock() + 30
   while workspace:GetAttribute("RoundActive") ~= true and os.clock() < deadline do
    task.wait(0.1)
   end
  end
  if root.Parent and hum.Parent and hum.Health > 0 and inRound[player] then
   root.AssemblyLinearVelocity = Vector3.zero
   root.Anchored = false
  end
  if shield.Parent then shield:Destroy() end
 end)
 return true
end

-- LEVEL2_EXIT_TRANSITION_20260828
-- Level 2's exit is one continuous slide into Level 3. A player who rode it out
-- resumes near the REAR of Level 3's continuation bore, already moving, and
-- physically slides the rest of the way into the mall. The alternative -- the
-- old placeSafelyInElevator -- stands them up on a pad facing away from the
-- tube, which reads as a teleport and throws away the whole transition.
--
-- The resume frame is published by the Level 3 World Builder as attributes on
-- the continuation model, so this function needs no knowledge of its geometry.
-- Every failure path falls through to placeSafelyInElevator: an arrival that
-- cannot find the tube must still put the player somewhere solid.
local LEVEL_TWO_TUBE_ENTRY_MODE = "level2-exit-tube"

-- How the party that playRound is about to run ARRIVED. Set immediately before
-- every playRound call so the level-3 opening can tell a service-elevator
-- descent apart from a party that is already halfway down the continuation bore.
local roundEntryMode = nil

-- onCharacter defers a placeSafelyInElevator for anyone in a round, which is
-- right for a respawn but wrong when the round-entry code is ABOUT to place the
-- character itself. Left alone it would fire a frame after the Level 3 slide
-- resume and drag the rider off the bore onto the spawn pad, silently undoing
-- the whole continuous transition.
local pendingExplicitPlacement = {}

-- A rider placed in Level 3's bore stays anchored until the mall around them is
-- actually live. Holding the release here rather than on a fixed timer is the
-- difference between sliding out into a running level and sliding out into a
-- world whose objective, hiding and music controllers have not been armed yet.
local pendingSlideRelease = {}

-- RequestStreamAroundAsync returning without an exception does not prove that
-- the destination exists on the client. Level 3's bore therefore has a small
-- tokenized client acknowledgement: the client requests the region itself and
-- replies only after a tagged collidable slide part near the resume point is
-- actually present. A stale/forged token cannot release another placement.
local slideStreamSerial = 0
local pendingSlideStream = {}

level3SlideStream.OnServerEvent:Connect(function(player, action, token, ready)
 if action ~= "ack" or type(token) ~= "string" or type(ready) ~= "boolean" then return end
 local state = pendingSlideStream[player]
 if not state or state.Token ~= token or state.Done then return end
 state.Done = true
 state.Ready = ready
end)

local function beginVerifiedBoreStream(player, position)
 slideStreamSerial += 1
 local state = {
  Token = table.concat({game.JobId, tostring(player.UserId), tostring(slideStreamSerial)}, ":"),
  Done = false,
  Ready = false,
 }
 pendingSlideStream[player] = state
 level3SlideStream:FireClient(player, "request", state.Token, position, STREAM_AROUND_TIMEOUT)
 return state
end

local function awaitVerifiedBoreStream(player, state)
 local deadline = os.clock() + STREAM_AROUND_TIMEOUT + 2
 while pendingSlideStream[player] == state and not state.Done
  and os.clock() < deadline do
  task.wait(.05)
 end
 if pendingSlideStream[player] == state then pendingSlideStream[player] = nil end
 return state.Done and state.Ready
end

local function levelThreeSlideResume()
 local world = workspace:FindFirstChild("Level 3 Generated World")
 if not world then return nil end
 for _, object in ipairs(world:GetDescendants()) do
  if object:GetAttribute("Level3_Level2ExitTube") == true then
   local position = object:GetAttribute("Level3_SlideResumePosition")
   local tangent = object:GetAttribute("Level3_SlideResumeTangent")
   local velocity = object:GetAttribute("Level3_SlideResumeVelocity")
   if typeof(position) == "Vector3" and typeof(tangent) == "Vector3"
    and typeof(velocity) == "Vector3" and tangent.Magnitude > .1 then
    return {Position = position, Tangent = tangent.Unit, Velocity = velocity}
   end
   return nil
  end
 end
 return nil
end

local function placeAtLevelThreeSlideResume(player, char)
 local resume = levelThreeSlideResume()
 if not resume then return false end
 local root = char and char:WaitForChild("HumanoidRootPart", 8)
 local hum = char and char:FindFirstChildOfClass("Humanoid")
 if not (root and hum and hum.Health > 0) then return false end

 root.Anchored = true
 root.AssemblyLinearVelocity = Vector3.zero
 root.AssemblyAngularVelocity = Vector3.zero
 char:PivotTo(CFrame.lookAt(resume.Position, resume.Position + resume.Tangent))
 local shield = Instance.new("ForceField")
 shield.Name = "LobbyTransferShield"
 shield.Visible = false
 shield.Parent = char

 -- Stream the bore in before handing the character over; resuming into an
 -- unloaded region drops the rider through the tube floor. This is an actual
 -- local-geometry acknowledgement, not pcall completion from the server API.
 local streamed = beginVerifiedBoreStream(player, resume.Position)

	local released = false
	local preparation = {Started = false, Done = false, Streamed = false}
	local function prepare()
		if not preparation.Started then
			preparation.Started = true
			preparation.Streamed = awaitVerifiedBoreStream(player, streamed)
			preparation.Done = true
		else
			local deadline = os.clock() + STREAM_AROUND_TIMEOUT + 2
			while not preparation.Done and os.clock() < deadline do task.wait(.05) end
		end
		return preparation.Done and preparation.Streamed
	end
	local function release(prepareOnly)
		local didStream = prepare()
		if prepareOnly then return didStream end
		if released then return didStream end
		released = true
		pendingSlideRelease[player] = nil
		if not didStream then
			warn("GameManager: Level 3 bore was not locally ready for " .. player.Name
				.. "; using the solid arrival elevator fallback")
			-- Keep the root anchored while the ordinary placement takes over. Its
			-- emergency cabin floor and bounded release are safer than handing an
			-- unstreamed character to gravity.
			if root.Parent and hum.Parent and hum.Health > 0 and inRound[player] then
				placeSafelyInElevator(player, char)
			end
		elseif root.Parent and hum.Parent and hum.Health > 0 and inRound[player] then
			root.Anchored = false
   -- Hand the ride back with real momentum so the rider continues down the
   -- bore instead of starting from rest on a steep slope.
   root.AssemblyLinearVelocity = resume.Velocity
		end
		if shield.Parent then shield:Destroy() end
		return didStream
	end
	pendingSlideRelease[player] = release
 -- Backstop. Nothing in this file may leave a player anchored forever, however
 -- the round that was supposed to release them ends up failing.
	task.delay(25, function()
		if pendingSlideRelease[player] == release then
			task.spawn(function() release(false) end)
		end
	end)
	return true
end

local function prepareSlideResume(group)
	local remaining = 0
	for _, player in ipairs(group) do
		local release = pendingSlideRelease[player]
		if release then
			remaining += 1
			task.spawn(function()
				release(true)
				remaining -= 1
			end)
		end
	end
	local deadline = os.clock() + STREAM_AROUND_TIMEOUT + 3
	while remaining > 0 and os.clock() < deadline do task.wait(.05) end
	return remaining == 0
end

local function releaseSlideResume(group)
	for _, player in ipairs(group) do
		local release = pendingSlideRelease[player]
		if release then release(false) end
	end
end

-- Every arrival funnels through here so the tube path and the fallback can
-- never diverge between the Studio in-place route and the reserved-server one.
local function placeOnLevelEntry(player, char, useSlideResume)
 -- The latch holds the CHARACTER being placed, not just the player, so a later
 -- respawn still receives its ordinary elevator placement.
 pendingExplicitPlacement[player] = char
 local placed = useSlideResume and placeAtLevelThreeSlideResume(player, char)
 if not placed then placed = placeSafelyInElevator(player, char) end
 -- Released two resumptions later, never in this one. onCharacter's fallback is
 -- deferred, so clearing the latch inline reopens exactly the race it closes.
 task.defer(function()
  task.defer(function()
   if pendingExplicitPlacement[player] == char then pendingExplicitPlacement[player] = nil end
  end)
 end)
 return placed
end

local function onCharacter(player, char)
 if inRound[player] then
  player.CameraMode = Enum.CameraMode.LockFirstPerson
  player.CameraMinZoomDistance = 0.5
  player.CameraMaxZoomDistance = 0.5
 else
  player.CameraMode = Enum.CameraMode.Classic
  player.CameraMinZoomDistance = 8
  player.CameraMaxZoomDistance = 18
 end
 task.defer(function()
  if inRound[player] then
	-- A completed Level 2 rider is placed by the objective controller back
	-- onto the exact helix tangent after a transition respawn. The ordinary
	-- elevator fallback would otherwise race that placement and anchor the
	-- character away from the ride.
	if activeLevel == 2 and player:GetAttribute("Level2_ExitTransition") == true then
		return
	end
   -- Round entry places this character explicitly; do not race it. `true` means
   -- a placement is armed but its character is not known yet.
   local pending = pendingExplicitPlacement[player]
   if worldReady and pending ~= true and pending ~= char then
    placeSafelyInElevator(player, char)
   end
  else
   scatterAt(char, lobbySpawn, false)
  end
 end)
 local hum = char:WaitForChild("Humanoid")
 hum.UseJumpPower = true
 hum.JumpPower = 50 -- normal Roblox jump; kill sequence temporarily disables/restores it
 hum.Died:Connect(function()
  player.CameraMode = Enum.CameraMode.Classic
  player.CameraMinZoomDistance = 8
  player.CameraMaxZoomDistance = 18
  if not inRound[player] then
   task.delay(3, function()
    if player.Parent and not inRound[player] then loadLobbyCharacter(player) end
   end)
  end
 end)
end

local function setupPlayer(player)
 inRound[player] = nil
 player:SetAttribute("InRound", false)
 player:SetAttribute("Escaped", nil)
 player:SetAttribute("Level2_ExitTransition", nil)
 player:SetAttribute("GlowstickSlot", nil)
 player:SetAttribute("GlowstickColor", nil)
 player.CharacterAdded:Connect(function(char) onCharacter(player, char) end)
 task.defer(function()
  if not player.Parent then return end
  if not IS_RESERVED_ROUND_SERVER and not player.Character then loadLobbyCharacter(player) end
  local initialStatus = "lobby"
  if IS_RESERVED_ROUND_SERVER then
   initialStatus = roundBusy and "spectating" or "loadinggame"
  end
  status:FireClient(player, initialStatus)
 end)
end

Players.PlayerAdded:Connect(setupPlayer)
for _, player in ipairs(Players:GetPlayers()) do setupPlayer(player) end
Players.PlayerRemoving:Connect(function(player)
 inRound[player] = nil
 lobbyDescriptions[player.UserId] = nil
 setServerNoclip(player, false)
 noclipState[player] = nil
 devControlRate[player] = nil
 player:SetAttribute("DevPushImmune", nil)
end)

local function playerInsideZone(player, station)
 if inRound[player] or station.busy then return false end
 local char = player.Character
 local hum = char and char:FindFirstChildOfClass("Humanoid")
 local root = char and char:FindFirstChild("HumanoidRootPart")
 if not (hum and hum.Health > 0 and root) then return false end
 local zone = station.zone
 local p = zone.CFrame:PointToObjectSpace(root.Position)
 return math.abs(p.X) <= zone.Size.X / 2
  and math.abs(p.Z) <= zone.Size.Z / 2
  and p.Y > -6 and p.Y < 12
end

local function rawQueuedPlayers(station)
 local result = {}
 local insideNow = {}
 station.entrySeen = station.entrySeen or {}
 for _, player in ipairs(Players:GetPlayers()) do
  if playerInsideZone(player, station) then
   insideNow[player] = true
   if station.entrySeen[player] == nil then station.entrySeen[player] = os.clock() end
   result[#result + 1] = player
  end
 end
 for player in pairs(station.entrySeen) do
  if not insideNow[player] then station.entrySeen[player] = nil end
 end
 table.sort(result, function(a, b)
  local at = station.entrySeen[a] or 0
  local bt = station.entrySeen[b] or 0
  if at == bt then return a.UserId < b.UserId end
  return at < bt
 end)
 return result
end

local function stationAllowsPlayer(station, player)
 if player == station.host or station.privacy == "public" then return true end
 if station.privacy ~= "friends" or not (station.host and station.host.Parent) then return false end
 local cached = station.friendCache[player.UserId]
 if cached ~= nil then return cached end
 local ok, isFriend = pcall(function()
  return player:IsFriendsWith(station.host.UserId)
 end)
 local allowed = ok and isFriend == true
 -- Only a DEFINITIVE answer is worth caching. A throttled or failed web call
 -- returns ok == false, which is indistinguishable here from "not a friend",
 -- and caching that locked a real friend out for the rest of the countdown --
 -- long enough for the party to launch without them. Still fail closed for
 -- this tick; just let the next once-per-second poll retry the call.
 if ok then station.friendCache[player.UserId] = allowed end
 return allowed
end

local function queuedPlayers(station)
 local raw = rawQueuedPlayers(station)
 local accepted, rejected = {}, {}
 if not station.configured or not station.host or not table.find(raw, station.host) then
  return accepted, raw, rejected
 end
 accepted[1] = station.host
 for _, player in ipairs(raw) do
  if player ~= station.host then
   local allowed = stationAllowsPlayer(station, player)
   if allowed and #accepted < station.maxPlayers then
    accepted[#accepted + 1] = player
   else
    rejected[#rejected + 1] = {player = player, reason = allowed and "full" or "private"}
   end
  end
 end
 return accepted, raw, rejected
end

local function fireGroup(group, ...)
 for _, player in ipairs(group) do
  if player.Parent then status:FireClient(player, ...) end
 end
end

-- Level 1 and Level 3 hide their stream-in behind an elevator ride, which holds
-- the round back while the client pulls the world in. Level 2 has no ride, so its
-- clients hold a loading cover instead and report here once the complex is
-- actually around them. The lobby client also announces that its RoundStatus
-- listener exists so its one-shot welcome cannot race the initial status fire.
local entryReady = {}
local lobbyBriefingReady = {}
local handlePostWinReturnRequest
local handlePostWinContinueRequest
status.OnServerEvent:Connect(function(player, message, requestSerial)
 if message == "entryready"
  and entryReady[player] == false
  and roundBusy
  and activeLevel == 2
  and inRound[player] == true
  and player:GetAttribute("InRound") == true then
  entryReady[player] = true
 elseif message == "returntolobby" and handlePostWinReturnRequest then
  handlePostWinReturnRequest(player, requestSerial)
 elseif message == "continuenow" and handlePostWinContinueRequest then
  handlePostWinContinueRequest(player, requestSerial)
 elseif message == "lobbybriefingready"
  and not lobbyBriefingReady[player]
  and not IS_RESERVED_ROUND_SERVER
  and not isReturnToLobbyArrival(player)
  and not inRound[player]
  and player:GetAttribute("InRound") ~= true
  and workspace:FindFirstChild("ServerLobby") then
  -- Latch before firing so retries can never produce overlapping welcomes.
  lobbyBriefingReady[player] = true
  status:FireClient(player, "lobbybriefing")
 end
end)
Players.PlayerRemoving:Connect(function(player)
 pendingExplicitPlacement[player] = nil
 pendingSlideRelease[player] = nil
 pendingSlideStream[player] = nil
 entryReady[player] = nil
 lobbyBriefingReady[player] = nil
 -- The player left, which is what the claim existed to achieve. Resolving it
 -- through Routing -- rather than reaching into the record here -- is what
 -- makes a LATE TeleportInitFailed for the same request a no-op instead of a
 -- second transfer attempt at a ghost.
 Routing.ResolveTransfer(pendingTeleports, player, Routing.Succeeded)
 if activePostWin then
  -- Membership of a result window is FROZEN. Only the decision moves, and only
  -- for somebody who had not already chosen: leaving is how a Continue or a
  -- Back completes, and erasing them here is what made the settlement tell the
  -- destination to expect one fewer player than was really coming.
  Routing.NoteDeparture(activePostWin.Roster, player)
 end
end)

local function armGroupEntry(group)
 for _, player in ipairs(group) do
  if player.Parent then entryReady[player] = false else entryReady[player] = nil end
 end
end

local function waitForGroupEntry(group, timeout)
 local deadline = os.clock() + timeout
 local ready = false
 while os.clock() < deadline do
  local pending = 0
  for _, player in ipairs(group) do
   if player.Parent and not entryReady[player] then pending += 1 end
  end
  if pending == 0 then ready = true break end
  task.wait(0.1)
 end
 for _, player in ipairs(group) do entryReady[player] = nil end
 return ready
end

local function privacyLabel(station)
 return station.privacy == "friends" and "FRIENDS ONLY" or "PUBLIC"
end

queueConfig.OnServerEvent:Connect(function(player, stationIndex, requestedMax, requestedPrivacy)
 if IS_RESERVED_ROUND_SERVER then return end
 stationIndex = math.floor(tonumber(stationIndex) or 0)
 local station = lobbyStations[stationIndex]
 if not station or station.busy then return end
 if station.host ~= player or not station.awaitingConfig then return end

 if requestedPrivacy == "cancel" then
  -- The phone close button genuinely leaves the queue instead of only hiding UI.
  station.cancelRequested = true
  local character = player.Character
  local root = character and character:FindFirstChild("HumanoidRootPart")
  if character and root then
   root.AssemblyLinearVelocity = Vector3.zero
   root.AssemblyAngularVelocity = Vector3.zero
   local exitPosition = (station.zone.CFrame * CFrame.new(0, 3,
    -(station.zone.Size.Z * 0.5 + 5))).Position
   character:PivotTo(CFrame.lookAt(exitPosition, station.zone.Position))
  end
  return
 end

 if not playerInsideZone(player, station) then return end

 station.maxPlayers = math.clamp(math.floor(tonumber(requestedMax) or MAX_PLAYERS_PER_STATION), 1, MAX_PLAYERS_PER_STATION)
 station.privacy = requestedPrivacy == "friends" and "friends" or "public"
 station.friendCache = {}
 station.configured = true
 station.awaitingConfig = false
 setStationDisplay(station,
  "STATION " .. (station.displayIndex or station.index) .. "  •  1/" .. station.maxPlayers,
  privacyLabel(station) .. "  •  COUNTDOWN STARTING",
  station.color)
 status:FireClient(player, "queueconfigured", station.maxPlayers, station.privacy, station.index)
end)

local function connectElevator()
 local model = workspace:WaitForChild("Elevator", 180)
 if not model then return nil end
 local doorL = model:WaitForChild("DoorL")
 local doorR = model:WaitForChild("DoorR")
 local closedL, closedR = doorL.CFrame, doorR.CFrame
 local info = TweenInfo.new(1.5, Enum.EasingStyle.Quad, Enum.EasingDirection.InOut)
 local api = {}
 function api.open()
  local releaseInfo = TweenInfo.new(0.18, Enum.EasingStyle.Quad, Enum.EasingDirection.Out)
  TweenService:Create(doorL, releaseInfo, {CFrame = closedL * CFrame.new(0, 0, -0.14)}):Play()
  TweenService:Create(doorR, releaseInfo, {CFrame = closedR * CFrame.new(0, 0, 0.14)}):Play()
  task.wait(0.2)
  TweenService:Create(doorL, info, {CFrame = closedL * CFrame.new(0, 0, -3.6)}):Play()
  TweenService:Create(doorR, info, {CFrame = closedR * CFrame.new(0, 0, 3.6)}):Play()
 end
 function api.close()
  TweenService:Create(doorL, info, {CFrame = closedL}):Play()
  TweenService:Create(doorR, info, {CFrame = closedR}):Play()
 end
 return api
end

local function ensureWorld(group, requestedLevel)
 local level = Routing.ClampLevel(requestedLevel)
 if worldReady and activeLevel == level then return true end
 activeLevel = level
 workspace:SetAttribute("SelectedLevel", level)
 workspace:SetAttribute("WorldGenerated", false)
 local generatorName = LEVEL_GENERATORS[level]
 if generatorName then
  local levelStages = {
   [2] = "ENTERING_DRY_POOLROOMS",
   [3] = "ENTERING_FORGOTTEN_MALL",
  }
  workspace:SetAttribute("LoadStage", levelStages[level] or "GENERATING_WORLD")
  local ok, err = pcall(function()
   require(script.Parent:WaitForChild(generatorName)).Build()
  end)
  if not ok then
   warn("GameManager: Level " .. level .. " generation failed: " .. tostring(err))
   workspace:SetAttribute("LoadStage", "WORLD_ERROR")
   return false
  end
 else
  workspace:SetAttribute("LoadStage", "GENERATING_WORLD")
  workspace:SetAttribute("GenerateWorld", true)
  local deadline = os.clock() + 180
  while workspace:GetAttribute("WorldGenerated") ~= true and os.clock() < deadline do task.wait(0.25) end
  if workspace:GetAttribute("WorldGenerated") ~= true then
   warn("GameManager: world generation timed out")
   return false
  end
 end
 elevatorApi = connectElevator()
 mazeStart = workspace:WaitForChild("MazeStart", 30)
 entityStart = level == 1 and workspace:WaitForChild("EntityStart", 30) or nil
 entity = level == 1 and workspace:WaitForChild("Entity", 30) or nil
 worldReady = elevatorApi ~= nil and mazeStart ~= nil
 workspace:SetAttribute("LoadStage", worldReady and "READY" or "WORLD_ERROR")
 return worldReady
end

local function cleanupLevelOneWorld()
 workspace:SetAttribute("GenerateWorld", false)
 workspace:SetAttribute("WorldGenerated", false)
 workspace:SetAttribute("DecorReady", false)
 workspace:SetAttribute("EntityPaused", false)
 workspace:SetAttribute("ForcedPlazaCenter", nil)
 workspace:SetAttribute("PlazaHeapCount", nil)
 workspace:SetAttribute("MiniPropPileCount", nil)
 workspace:SetAttribute("EntityObjectiveTarget", nil)
 workspace:SetAttribute("EntityObjectiveStage", nil)
 workspace:SetAttribute("ExitPos", nil)

 for _, name in ipairs({
  "PuzzleItems", "Decor", "PitZones", "Maze", "Elevator",
  "ElevatorSpawn", "MazeStart", "EntityStart",
 }) do
  repeat
   local generated = workspace:FindFirstChild(name)
   if not generated then break end
   generated:Destroy()
  until false
 end

 local grade = Lighting:FindFirstChild("MongoGrade")
 if grade then grade:Destroy() end
 Lighting.Brightness = 2
 Lighting.Ambient = Color3.fromRGB(92, 88, 70)
 Lighting.OutdoorAmbient = Color3.fromRGB(105, 101, 82)
 Lighting.FogStart = 100000
 Lighting.FogEnd = 100000
 Lighting.ClockTime = 14

 worldReady = false
 elevatorApi, mazeStart, entityStart, entity = nil, nil, nil, nil

 -- Re-arm the one-shot generator for Studio/fallback servers. The public game
 -- normally leaves this reserved server after a round, but a failed teleport
 -- must still return to a clean lobby and remain capable of another test.
 -- Recursive: Level 1's runtime scripts moved into a "Level 1 Systems"
 -- folder on 2026-09-02, and a non-recursive lookup would silently return
 -- nil there -- which is exactly how every Level 2/3 round once came to
 -- start Level 1's fuse puzzle server-side. Recursive works from either
 -- layout, so this cannot break again on the next reorganisation.
 local generatorScript = script.Parent:FindFirstChild("MazeGenerator", true)
 local entityScript = script.Parent:FindFirstChild("EntityAI", true)
 if generatorScript and generatorScript:IsA("Script") then generatorScript.Disabled = true end
 if entityScript and entityScript:IsA("Script") then entityScript.Disabled = true end
 task.defer(function()
  if generatorScript and generatorScript.Parent then generatorScript.Disabled = false end
  if entityScript and entityScript.Parent then entityScript.Disabled = false end
 end)
end

local function livePlayers(group)
	local result, seen = {}, {}
	for _, player in ipairs(group or {}) do
		if player and player.Parent == Players and not seen[player] then
			seen[player] = true
			result[#result + 1] = player
		end
	end
	return result
end

local function cleanupActiveWorld()
	clearGlowsticks()
	local cleanupLevel = activeLevel
	local cleanupGenerator = LEVEL_GENERATORS[cleanupLevel]
	if cleanupGenerator then
		local ok, err = pcall(function()
			require(script.Parent:WaitForChild(cleanupGenerator)).Cleanup()
		end)
		if not ok then warn("[GameManager] Level " .. cleanupLevel .. " cleanup failed:", err) end
		worldReady = false
		elevatorApi, mazeStart, entityStart, entity = nil, nil, nil, nil
	else
		cleanupLevelOneWorld()
	end
	activeLevel = 1
	workspace:SetAttribute("SelectedLevel", 1)
	Players.CharacterAutoLoads = false
end

local function returnPlayersToLocalLobby(group)
	for _, player in ipairs(livePlayers(group)) do
		inRound[player] = nil
		player:SetAttribute("InRound", false)
		player:SetAttribute("Escaped", nil)
		player:SetAttribute("Level2_ExitTransition", nil)
		player:SetAttribute("GlowstickSlot", nil)
		player:SetAttribute("GlowstickColor", nil)
		loadLobbyCharacter(player)
		status:FireClient(player, "lobby")
	end
end

-- One authoritative transfer per player, with an EXPLICIT lifecycle. Every path
-- that can send somebody somewhere claims them FIRST; a second path finds them
-- already claimed and leaves them alone. The claim is taken before any yield so
-- a resumed thread cannot slip between the check and the write.
--
-- A claim is PENDING until something resolves it. "TeleportAsync did not throw"
-- is not success: TeleportInitFailed can arrive seconds later. The old code
-- treated an in-flight claim as a finished transfer, closed the result window
-- around it, and had nothing left to recover the player with when the failure
-- finally landed. Routing owns the state machine so those interleavings can be
-- asserted without a real teleport.
local function claimForTransfer(group)
	local claimed = {}
	-- ONE timestamp for the whole batch, taken before the loop: it is the anchor
	-- every bounded thing about these claims is measured from, and a claim that
	-- never reaches an attempt has nothing else to be dated by.
	local at = os.clock()
	for _, player in ipairs(livePlayers(group)) do
		if (Routing.ClaimTransfer(pendingTeleports, player, "claim", at)) then
			claimed[#claimed + 1] = player
		end
	end
	return claimed
end

-- A transfer DESCRIPTOR is everything needed to rebuild an equivalent request:
-- the reservation to join, and the teleport payload minus its attempt id. A
-- retry rebuilds from this under a FRESH id rather than re-sending the options
-- object that already failed -- reusing it would make the retry's failure
-- callback indistinguishable from the original's, which is exactly how a
-- duplicate report used to be counted twice.
local function buildTransferOptions(descriptor, attemptId)
	local options = Instance.new("TeleportOptions")
	if type(descriptor.AccessCode) == "string" and descriptor.AccessCode ~= "" then
		-- Join the reservation the session already made, so a player who pressed
		-- Continue at once and a party member who let the countdown run out arrive
		-- in the SAME next-level server.
		options.ReservedServerAccessCode = descriptor.AccessCode
	elseif descriptor.ReserveServer then
		options.ShouldReserveServer = true
	end
	local payload = table.clone(descriptor.Data)
	payload.TransferAttemptId = attemptId
	options:SetTeleportData(payload)
	return options
end

-- One TeleportAsync call is one attempt. Every player on it is recorded against
-- that id, and the id rides in the teleport data, so TeleportInitFailed can be
-- matched to the attempt that produced it rather than to whatever claim happens
-- to be current when it lands.
-- EVERY pre-dispatch step is inside this, and the attempt is stamped whether or
-- not the request could be built.
--
-- buildTransferOptions used to run outside any protection. Instance.new and
-- SetTeleportData can both throw -- a payload Roblox refuses to serialise is
-- enough -- and the throw propagated out of the spawned continue thread, which
-- simply died. The players it had already CLAIMED were left pending with no
-- attempt id and no attempt stamp: invisible to the watchdog, and re-dated by
-- the settlement on every poll. That was an endpoint waiting forever.
--
-- Now the claim always carries a real attempt, so an unbuildable request is
-- reported as the synchronous failure it is and earns the same retry, fallback
-- and surrender any other refused dispatch does.
local function dispatchTransfer(group, descriptor)
	local attemptId = Routing.NewAttemptId()
	local at = os.clock()
	local built, options = pcall(buildTransferOptions, descriptor, attemptId)
	for _, player in ipairs(group) do
		Routing.BeginAttempt(pendingTeleports, player, descriptor.Kind, attemptId,
			built and options or nil, game.PlaceId, at, descriptor)
	end
	if not built then
		return false, "TELEPORT_REQUEST_UNBUILDABLE: " .. tostring(options), attemptId
	end
	local ok, err = pcall(function()
		TeleportService:TeleportAsync(game.PlaceId, group, options)
	end)
	if ok then
		-- Roblox has taken it. Re-anchor the stale clock to NOW rather than to
		-- before the call: TeleportAsync yields, and on the cohort schedule the
		-- whole budget is six seconds, so charging the yield to the attempt
		-- would re-dispatch underneath a transfer that had just succeeded.
		--
		-- `at` is handed in as the DISPATCH instant so Routing can clamp how far
		-- the re-anchor may travel. Without it the horizon this session already
		-- promised the destination -- deadline + CohortArrivalHorizonSeconds --
		-- was not a bound at all: however long TeleportAsync yielded was added to
		-- the retry's arrival, and the destination had stopped staging by then.
		local acceptedAt = os.clock()
		for _, player in ipairs(group) do
			Routing.RestampAttempt(pendingTeleports, player, attemptId, acceptedAt, at)
		end
	end
	return ok, err, attemptId
end

-- There is NO TeleportService destination on this server at all -- Studio, or a
-- public lobby server that already owns the lobby these players want. Nothing
-- was dispatched and nothing can be retried, so the claim is resolved directly:
-- the settlement sweep may now take the player (a failed claim owns nobody).
--
-- This is the ONLY remaining direct resolution. A rejection of a real dispatch
-- goes through reportDispatchFailure below.
local function releaseUndispatchedClaims(group)
	for _, player in ipairs(group) do
		Routing.ResolveTransfer(pendingTeleports, player, Routing.Failed)
	end
end

local function stillHere(player)
	return player.Parent == Players
end

-- The completed world may only be released once no player who is still on this
-- server holds an unresolved claim. Anything else deletes the ground out from
-- under somebody Roblox has not actually moved yet.
-- Declared here because the watchdog, the settlement wait, the reserved-server
-- teardown guard and the failure recovery all hand players to it.
local finishFailedTeleportLocally

-- THE watchdog. Not one per endpoint, and not a check an endpoint has to
-- remember to run: a single sweep owns every unfinished transfer on this
-- server, whatever path opened it.
--
-- Roblox can produce neither PlayerRemoving nor TeleportInitFailed for a
-- request it silently dropped. Before this, such a claim stayed pending
-- forever: the settlement wait ran its expiry pass five seconds BEFORE anything
-- could be stale, and the Level 3 and loss endpoints waited 1.6 seconds and
-- never ran settlement at all. Every timing below comes from Routing, so the
-- sweep interval, the stale threshold and the endpoint wait cannot drift apart.
-- The sweep, the failure policy and the settlement loop all live in
-- Routing.NewTransferRuntime now, built below once teleportPlayersToLobby
-- exists. Keeping them here is what let the timeout path and the callback path
-- drift into two different policies with nothing able to test either: the suite
-- could reach Routing's pure rules but never the code that ACTED on them.
-- (`transfers` itself is forward-declared above reportDispatchFailure.)

-- A dispatch Roblox refused, or a request that could not be built, reported
-- through THE runtime -- the same door TeleportInitFailed comes through.
--
-- Marking the claim Failed here instead (which is what both wrappers used to
-- do) skipped the entire policy: no retry, no lobby fallback for a refused
-- next-level transfer, no surrender to local recovery. Declared before the
-- wrappers and resolved through the `transfers` upvalue, which is built below.
local transfers
local function reportDispatchFailure(group, attemptId, err)
	for _, player in ipairs(group) do
		transfers:ReportDispatchFailure(player, attemptId, err)
	end
end

local function teleportPlayersToLobby(group)
	local live = claimForTransfer(group)
	if #live == 0 then return true, nil, live end
	if not IS_RESERVED_ROUND_SERVER or IS_STUDIO then
		releaseUndispatchedClaims(live)
		return false, "LOCAL_FALLBACK", live
	end
	local ok, err, attemptId = dispatchTransfer(live, {
		Kind = "lobby",
		Data = {ReturnToLobby = true},
	})
	if not ok then reportDispatchFailure(live, attemptId, err) end
	return ok, err, live
end

-- THE transfer runtime. Everything the completion path does with a failed or
-- silent transfer goes through this object, and the suite builds the SAME
-- object over a fake clock and a scripted dispatcher. That is the point: the
-- previous suite could assert what Routing.RetryPlan SAID and never what
-- GameManager DID with it, so the timeout path quietly grew a second policy.
transfers = Routing.NewTransferRuntime({
	Claims = pendingTeleports,
	Now = os.clock,
	Delay = task.delay,
	Spawn = task.spawn,
	Wait = task.wait,
	Present = stillHere,
	Dispatch = function(player, descriptor)
		return dispatchTransfer({player}, descriptor)
	end,
	LobbyTransfer = function(player)
		local ok, err = teleportPlayersToLobby({player})
		return ok, err
	end,
	Surrender = function(player, reason)
		finishFailedTeleportLocally(player, reason)
	end,
	Notify = function(player, ...)
		status:FireClient(player, ...)
	end,
	Warn = function(text) warn("GameManager: " .. text) end,
	Reserved = IS_RESERVED_ROUND_SERVER,
	Studio = IS_STUDIO,
})

-- THE watchdog. Not one per endpoint, and not a check an endpoint has to
-- remember to run: a single sweep owns every unfinished transfer on this
-- server, whatever path opened it. Roblox can produce neither PlayerRemoving
-- nor TeleportInitFailed for a request it silently dropped.
task.spawn(function()
	while true do
		-- The SHORTEST threshold in play, not the lobby one: a cohort attempt
		-- that has to be retried inside the destination's staging window cannot
		-- wait a full lobby sweep to be noticed.
		task.wait(Routing.SweepIntervalSeconds())
		transfers:Sweep("watchdog")
	end
end)

-- What every endpoint calls before it lets go. Returns (settled, stranded);
-- `settled == false` is NOT advisory and no caller may drop it.
local function awaitTransferSettlement(endpoint)
	return transfers:AwaitSettlement(endpoint)
end

-- A settlement that did not resolve means players on this server are still
-- unaccounted for. In a reserved round server the completed world is the only
-- floor they have, so it is HELD: no cleanup, and the round does not roll on.
-- ForceSettle has already handed every one of them to local recovery, which
-- keeps retrying the lobby, so nobody is merely abandoned here.
local function holdCompletedWorld(stranded, endpoint)
	warn(string.format(
		"GameManager: the %s endpoint could not settle %d transfer(s); holding the completed world",
		tostring(endpoint), #stranded))
	workspace:SetAttribute("CompletionSettlementHeld", true)
	workspace:SetAttribute("CompletionStrandedCount", #stranded)
	return Routing.TeardownPlan({
		Accepted = false,
		Reserved = IS_RESERVED_ROUND_SERVER,
		Studio = IS_STUDIO,
	}) == "keep-world"
end

-- `plan` is the ONE result window this transfer belongs to: its reservation,
-- its session id, its decision deadline and its current head count. Every
-- continuer out of a given win carries the same identity, whether they pressed
-- Continue in the first second or the countdown carried them. Sizing each
-- packet by the players in THAT ONE transfer is what made the first arrival
-- start the round and turned everybody after them into a spectator, so the
-- cohort below is the session's, not this batch's.
local function teleportPlayersToNextLevel(group, plan)
	local live = claimForTransfer(group)
	if #live == 0 then return true, nil, live end
	if IS_STUDIO then
		-- Studio has no TeleportService destination, so nothing was dispatched and
		-- there is nothing to retry: the claims are released directly.
		--
		-- This read `failPendingTeleport(live)` -- a name that no longer exists
		-- anywhere in this file. It was renamed to releaseUndispatchedClaims when
		-- the synchronous-failure path was routed through the transfer runtime,
		-- and this one call site was missed. Luau resolves it as a global, so it
		-- was nil, and every Studio next-level transition raised
		-- "attempt to call a nil value" out of the completion path.
		releaseUndispatchedClaims(live)
		return false, "STUDIO_LOCAL_TRANSITION", live
	end
	-- Building the descriptor is a pre-dispatch step like any other, and it
	-- reads player attributes: it can throw. A throw here used to kill the
	-- calling thread with the claims already taken and no attempt on them.
	local builtDescriptor, descriptor = pcall(function()
	local glowstickSlots = {}
	for index, player in ipairs(live) do
		local slot = math.clamp(math.floor(tonumber(player:GetAttribute("GlowstickSlot")) or index), 1, MAX_PLAYERS_PER_STATION)
		glowstickSlots[tostring(player.UserId)] = slot
	end
	return {
		Kind = "next",
		AccessCode = plan.AccessCode,
		ReserveServer = not (type(plan.AccessCode) == "string" and plan.AccessCode ~= ""),
		Data = Routing.ArrivalPacket({
			Level = plan.NextLevel,
			-- LEVEL2_EXIT_TRANSITION_20260828: the whole continuing party left
			-- Level 2 down the exit flume (the win condition requires every
			-- surviving participant to have escaped), so the next server resumes
			-- them inside Level 3's continuation bore rather than on a spawn pad.
			EntryMode = plan.EntryMode,
			SessionId = plan.SessionId,
			-- Counted from the FROZEN roster, so a continuer who has already
			-- departed and left this server is still counted. The settlement
			-- packet is marked Final and carries the exact head count.
			Expected = plan.Expected,
			Deadline = plan.Deadline,
			Final = plan.Final,
			GlowstickSlots = glowstickSlots,
			LaunchToken = plan.SessionId,
		}),
	}
	end)
	if not builtDescriptor then
		-- Give the claims a real attempt anyway, so the ordinary failure policy
		-- owns them instead of leaving claims nothing will ever report on.
		local ok, err, attemptId = dispatchTransfer(live, {Kind = "next", Data = nil})
		reportDispatchFailure(live, attemptId, "NEXT_DESCRIPTOR_FAILED: " .. tostring(descriptor))
		return false, "NEXT_DESCRIPTOR_FAILED: " .. tostring(descriptor), live
	end
	local ok, err, attemptId = dispatchTransfer(live, descriptor)
	if not ok then reportDispatchFailure(live, attemptId, err) end
	return ok, err, live
end

local function returnGroupToLobby(group)
	-- A late reserved-server arrival is a spectator, but must never be stranded.
	local candidates = IS_RESERVED_ROUND_SERVER and Players:GetPlayers() or group
	local ok, err, live = teleportPlayersToLobby(candidates)
	local plan = Routing.TeardownPlan({
		Accepted = ok,
		Reserved = IS_RESERVED_ROUND_SERVER,
		Studio = IS_STUDIO,
	})
	if plan == "released" then
		-- Keep the completed map intact while Roblox transfers the party. The old
		-- isolated server and its world disappear naturally after the last leave.
		return true
	end
	if err ~= "LOCAL_FALLBACK" and #live > 0 then
		warn("GameManager: return-to-lobby teleport failed: " .. tostring(err))
	end
	if plan == "keep-world" then
		-- No lobby exists here to recover into, so the finished world is the only
		-- floor these players have. Hand each of them to the per-player retry and
		-- leave the map standing.
		--
		-- Except anybody the transfer runtime already owns. A refused dispatch now
		-- earns its retry through Routing rather than being marked failed on the
		-- spot, so a live claim here means an attempt is already scheduled;
		-- surrendering them as well would resolve that claim out from under it.
		for _, player in ipairs(live) do
			if not Routing.ClaimOwns(pendingTeleports[player]) then
				finishFailedTeleportLocally(player, err)
			end
		end
		return false
	end
	cleanupActiveWorld()
	returnPlayersToLocalLobby(live)
	return false
end

local playRound

handlePostWinReturnRequest = function(player, requestSerial)
	local session = activePostWin
	if not session
		or session.Closed
		or type(requestSerial) ~= "number"
		or requestSerial ~= session.Serial
		or workspace:GetServerTimeNow() >= session.Deadline
		or workspace:GetAttribute("RoundActive") == true
		or activeLevel ~= session.Level
		or not Routing.InRoster(session.Roster, player)
		or Routing.DecisionOf(session.Roster, player) ~= Routing.Deciding
		or inRound[player] ~= true
		or player:GetAttribute("InRound") ~= true
		or player.Parent ~= Players then
		return
	end

	-- Latch before any yield/TeleportAsync call; clients cannot choose the
	-- destination, deadline, level, or another party member. RecordDecision is
	-- the only writer, and it refuses a second press by itself.
	if not Routing.RecordDecision(session.Roster, player, Routing.Returning) then return end
	status:FireClient(player, "returnpending", session.Serial)
	if IS_RESERVED_ROUND_SERVER and not IS_STUDIO then
		-- Keep the endless ride authoritative until Roblox accepts the transfer.
		-- Clearing it before TeleportAsync made a transient failure irreversibly
		-- delete the objective's transition record and strand the player.
		task.spawn(function()
			local ok, err = teleportPlayersToLobby({player})
			if not ok and Routing.ClaimOwns(pendingTeleports[player]) then
				-- Refused, and the runtime is retrying it. The decision stands
				-- until that lineage ends; finishFailedTeleportLocally gives the
				-- choice back if it ends badly while the window is still open.
				warn("GameManager: early return-to-lobby was refused for " .. player.Name
					.. "; the transfer runtime is retrying it (" .. tostring(err) .. ")")
			elseif not ok and activePostWin == session and not session.Closed and player.Parent == Players then
				if Routing.ClearDecision(session.Roster, player) then
					status:FireClient(player, "returnfailed", session.Serial)
				end
				warn("GameManager: early return-to-lobby failed for " .. player.Name .. ": " .. tostring(err))
			end
		end)
	else
		-- Studio has no TeleportService destination. Park the opted-out rider in
		-- Level 2's recovery chamber until the local fallback resolves at deadline.
		player:SetAttribute("Level2_ExitTransition", nil)
	end
end

-- The next-level server is reserved ONCE per post-win session, by whoever
-- continues first, and everyone after them joins the same reservation. Without
-- this, an immediate Continue and a timed-out Continue would each reserve their
-- own server and split the party across two of them.
local function reserveNextLevelServer(session)
	if session.NextServerCode then return session.NextServerCode end
	if session.ReservingServer then
		-- Another continuer got here first; wait for their reservation.
		local deadline = os.clock() + 12
		while session.ReservingServer and os.clock() < deadline do task.wait(0.1) end
		return session.NextServerCode
	end
	session.ReservingServer = true
	local ok, code = pcall(function()
		return (TeleportService:ReserveServer(game.PlaceId))
	end)
	session.ReservingServer = false
	if ok and type(code) == "string" and code ~= "" then
		session.NextServerCode = code
		return code
	end
	warn("GameManager: could not reserve the next-level server: " .. tostring(code))
	return nil
end

-- How many players this session should still deliver to the destination.
-- Counted from the FROZEN roster, so a player who pressed Continue, departed
-- and left this server is still counted -- they are on their way there.
local function sessionExpectedContinuers(session)
	return Routing.ExpectedContinuers(session.Roster, stillHere)
end

-- Continue advances THIS player immediately. It never waits on the rest of the
-- party: the fifteen-second countdown is the auto-continue deadline for anyone
-- who has not chosen, not a barrier the early presser has to sit behind. What
-- it does NOT do any more is travel alone: the packet carries the session's
-- reservation, id, deadline and head count, so the destination stages this
-- player until the source's window has closed and then admits the whole cohort
-- into one round.
handlePostWinContinueRequest = function(player, requestSerial)
	local session = activePostWin
	if not session
		or session.Closed
		or session.NextLevel == nil
		or type(requestSerial) ~= "number"
		or requestSerial ~= session.Serial
		or workspace:GetServerTimeNow() >= session.Deadline
		or workspace:GetAttribute("RoundActive") == true
		or activeLevel ~= session.Level
		or not Routing.InRoster(session.Roster, player)
		or Routing.DecisionOf(session.Roster, player) ~= Routing.Deciding
		or inRound[player] ~= true
		or player:GetAttribute("InRound") ~= true
		or player.Parent ~= Players then
		return
	end
	-- Latch before any yield so a repeated press cannot start two transfers.
	-- RecordDecision refuses the second press by itself, so this is also the
	-- guard against a double-click racing its own spawned thread.
	if not Routing.RecordDecision(session.Roster, player, Routing.Continuing) then return end
	if IS_STUDIO then
		-- Studio has no TeleportService destination; the local campaign route
		-- runs once at settlement and carries this player with it.
		return
	end
	task.spawn(function()
		local code = reserveNextLevelServer(session)
		if activePostWin ~= session or session.Aborted or player.Parent ~= Players then return end
		if not code then
			if Routing.ClearDecision(session.Roster, player) then
				status:FireClient(player, "continuefailed", session.Serial)
			end
			return
		end
		local moved, moveError = teleportPlayersToNextLevel({player}, {
			NextLevel = session.NextLevel,
			EntryMode = session.EntryMode,
			AccessCode = code,
			SessionId = session.Id,
			Deadline = session.Deadline,
			Expected = sessionExpectedContinuers(session),
			Final = false,
		})
		if moved then
			-- Terminal. From here the settlement counts them as coming, whether or
			-- not they are still connected to this server a moment from now.
			Routing.MarkDeparted(session.Roster, player)
		elseif Routing.ClaimOwns(pendingTeleports[player]) then
			-- The dispatch was refused, and the runtime took the failure: a retry
			-- (or a lobby fallback) already owns this player. Giving them their
			-- choice back here would let a second press open a competing claim
			-- while the first is still in flight.
			warn("GameManager: immediate Continue was refused for " .. player.Name
				.. "; the transfer runtime is retrying it (" .. tostring(moveError) .. ")")
		else
			if Routing.ClearDecision(session.Roster, player) and player.Parent == Players then
				status:FireClient(player, "continuefailed", session.Serial)
			end
			warn("GameManager: immediate Continue failed for " .. player.Name
				.. ": " .. tostring(moveError))
		end
	end)
end

-- The last resort, after the original transfer, its one retry and (for a
-- next-level transfer) its lobby fallback were all rejected.
--
-- In a RESERVED round server there is no local lobby to recover into: deleting
-- the completed world here would take the ground out from under a player Roblox
-- has refused to move. So the world stays, the client is told, and the lobby
-- transfer keeps being retried on a slow schedule until it takes or the player
-- leaves. Only the public/Studio server, which really does own a lobby, falls
-- back to standing the player up in it.
local LOCAL_RECOVERY_RETRY_SECONDS = 8
local strandedRetryToken = {}

local function retryStrandedLobbyTransfer(player)
	local token = {}
	strandedRetryToken[player] = token
	task.delay(LOCAL_RECOVERY_RETRY_SECONDS, function()
		if strandedRetryToken[player] ~= token or player.Parent ~= Players then return end
		strandedRetryToken[player] = nil
		if Routing.ClaimOwns(pendingTeleports[player]) then return end
		local returned = teleportPlayersToLobby({player})
		if not returned and player.Parent == Players then
			retryStrandedLobbyTransfer(player)
		end
	end)
end

function finishFailedTeleportLocally(player, reason)
	local failedDestination = (Routing.DescriptorOf(pendingTeleports, player) or {}).Kind
	Routing.ResolveTransfer(pendingTeleports, player, Routing.Failed)
	if player.Parent ~= Players then return end
	-- A failed early opt-out is recoverable while the window is still open: keep
	-- this one player on the ride and let them choose again. Never abort the
	-- shared post-win session or remove the completed map before its deadline.
	local livePostWin = activePostWin
	if failedDestination == "lobby"
		and livePostWin and not livePostWin.Closed
		and workspace:GetServerTimeNow() < livePostWin.Deadline
		and Routing.ClearDecision(livePostWin.Roster, player) then
		status:FireClient(player, "returnfailed", livePostWin.Serial)
		warn("GameManager: Return Lobby failed twice; keeping " .. player.Name
			.. " in the campaign (" .. tostring(reason) .. ")")
		return
	end
	warn("GameManager: transfer surrendered for " .. player.Name
		.. " (" .. tostring(reason) .. ")")
	status:FireClient(player, "transitionfailed")

	if IS_RESERVED_ROUND_SERVER and not IS_STUDIO then
		-- Keep the finished world; it is the only floor this player has. The
		-- settlement sweep already skipped them -- a failed claim owns nobody --
		-- so this retry is the single authority they have left.
		retryStrandedLobbyTransfer(player)
		return
	end

	-- A twice-failed early Return-to-Lobby transfer can arrive while the 15-second
	-- post-win loop is still running. Abort that session before cleaning the world;
	-- otherwise its deadline branch can later send the recovered party onward too.
	local interruptedSession = activePostWin
	if interruptedSession and not interruptedSession.Closed then
		interruptedSession.Aborted = true
		interruptedSession.Closed = true
		activePostWin = nil
	end
	-- One cleanup is enough even if several players fail together.
	local recoveryGroup = {player}
	if worldReady then
		recoveryGroup = Players:GetPlayers()
		for _, stranded in ipairs(recoveryGroup) do
			Routing.ReleaseTransfer(pendingTeleports, stranded)
		end
		cleanupActiveWorld()
	end
	returnPlayersToLocalLobby(recoveryGroup)
end

-- Roblox can report the same failed request more than once, and can report one
-- the caller has already given up on -- including a next-level report that
-- lands after the fallback has already opened a fresh LOBBY claim for the same
-- player. The runtime matches the report to the attempt that produced it and
-- does nothing for anything else, so a stale or duplicate report is a no-op
-- instead of a second failure charged to an unrelated claim.
--
-- Acting on the plan lives in Routing.NewTransferRuntime, NOT here, so that the
-- silent-transfer sweep enters exactly the same policy. It used to not: an
-- attempt Roblox merely dropped went straight to local recovery and lost the
-- one next-level retry an identically failed but REPORTED attempt would keep.
TeleportService.TeleportInitFailed:Connect(function(player, teleportResult, errorMessage, placeId, teleportOptions)
	local attemptId = Routing.AttemptIdOf(teleportOptions)
	if transfers:ReportFailure(player, attemptId, teleportOptions, errorMessage) then
		warn("GameManager: teleport initialization failed for", player.Name, teleportResult, errorMessage)
	end
end)

local function runPostWinIntermission(participants, elapsed, escapedCount, entryMode)
	postWinSerial += 1
	local nextLevel = Routing.NextLevel(activeLevel)
	local deadline = workspace:GetServerTimeNow() + Routing.PostWinSeconds
	local roster = Routing.NewRoster((function()
		local members = {}
		for _, player in ipairs(participants) do
			if player.Parent == Players then members[#members + 1] = player end
		end
		return members
	end)())
	local session = {
		Serial = postWinSerial,
		-- One result window is one session. Every continuer out of it travels
		-- under this id, into the reservation this session made, so the
		-- destination can recognise them as one party rather than as a stream of
		-- unrelated parties of one.
		Id = Routing.SessionId(game.JobId, postWinSerial),
		Level = activeLevel,
		Deadline = deadline,
		NextLevel = nextLevel,
		-- FROZEN membership. Decisions move; membership does not. A continuer who
		-- departs and leaves this server stays in the roster, which is what keeps
		-- the head count the destination is told truthful.
		Roster = roster,
		EntryMode = entryMode,
		NextServerCode = nil,
		ReservingServer = false,
		Closed = false,
		Aborted = false,
	}
	activePostWin = session
	fireGroup(participants, "win", elapsed, escapedCount, #participants, deadline, nextLevel, session.Serial)

	-- Settled = every member of the frozen roster has decided, or is no longer
	-- here to decide. A disconnect settles the window instead of holding the rest
	-- of the party at a screen nobody is going to answer.
	local function settled()
		return Routing.Settled(roster, stillHere)
	end
	while activePostWin == session
		and workspace:GetServerTimeNow() < session.Deadline
		and not settled() do
		task.wait(0.1)
	end
	session.Closed = true
	if activePostWin == session then activePostWin = nil end
	if session.Aborted then
		return {Aborted = true, Session = session, Continuing = {}, Returning = {}}
	end

	local continuing, returning, departed, gone = Routing.Partition(roster, stillHere)
	table.sort(continuing, function(a, b) return a.UserId < b.UserId end)
	table.sort(returning, function(a, b) return a.UserId < b.UserId end)
	-- The settlement packet is the authoritative head count for this session, and
	-- it is read off the frozen roster rather than off who is still connected:
	-- everyone who already departed on an immediate Continue, plus everyone the
	-- countdown is carrying now. Counting live players instead is what let a
	-- departed early continuer vanish from the cohort and the destination start
	-- its round before the rest of the party had landed.
	local cohort = Routing.ExpectedContinuers(roster, stillHere)
	print(string.format(
		"[GameManager] result window %d settled: %d continuing, %d departed, %d returning, %d gone -> cohort %d",
		session.Serial, #continuing, #departed, #returning, #gone, cohort))
	return {
		Aborted = false,
		Session = session,
		NextLevel = nextLevel,
		Continuing = continuing,
		Returning = returning,
		Departed = departed,
		Gone = gone,
		AccessCode = session.NextServerCode,
		Cohort = cohort,
	}
end

local function continueStudioCampaign(participants, continuing, returning, nextLevel, entryMode)
	-- Studio cannot teleport. A mixed split cannot coexist with generators that
	-- park the lobby, so an opt-out safely ends this editor-only local session.
	if #returning > 0 or #continuing == 0 then
		returnGroupToLobby(participants)
		return
	end

	armGroupEntry(continuing)
	fireGroup(continuing, "loadinggame", nextLevel)
	cleanupActiveWorld()
	for _, player in ipairs(continuing) do
		inRound[player] = true
		player:SetAttribute("InRound", true)
		player:SetAttribute("Escaped", nil)
		player:SetAttribute("Level2_ExitTransition", nil)
	end
	if not ensureWorld(continuing, nextLevel) then
		fireGroup(continuing, "loadfailed")
		returnGroupToLobby(continuing)
		return
	end
	local useSlideResume = entryMode == LEVEL_TWO_TUBE_ENTRY_MODE and nextLevel == 3
	roundEntryMode = useSlideResume and LEVEL_TWO_TUBE_ENTRY_MODE or nil
	for _, player in ipairs(continuing) do
		if player.Parent then
			pendingExplicitPlacement[player] = true
			local character = spawnGameplayCharacter(player)
			if character then placeOnLevelEntry(player, character, useSlideResume) end
		end
	end
	task.wait(0.6)
	playRound(continuing)
end

playRound = function(participants)
	if LEVEL_GENERATORS[activeLevel] then Players.CharacterAutoLoads = false end
 local alive = {}
 local aliveCount = 0
 local conns = {}
 local participantSet = {}
 local reentryUsed = {}
	local transitionRespawnToken = {}
	local roundLifecycleOpen = true
 -- LEVEL2_EXIT_TRANSITION_20260828
 -- The route the party took out of Level 2 is latched AT the completion event.
 -- Reconstructing it afterwards from player attributes is wrong: by the time the
 -- post-win countdown ends a rider may have died, been recovered to the chamber,
 -- or opted out, and none of that changes how the party left.
 local exitTubeRoute = false

	local function closeRoundLifecycle()
		if not roundLifecycleOpen then return end
		roundLifecycleOpen = false
		table.clear(transitionRespawnToken)
		for _, connection in ipairs(conns) do connection:Disconnect() end
		table.clear(conns)
	end

	local scheduleTransitionRespawn
	local function hookLife(player, hum)
  conns[#conns + 1] = hum.Died:Connect(function()
   if alive[player] then
    alive[player] = nil
    aliveCount -= 1
    local root = player.Character and player.Character:FindFirstChild("HumanoidRootPart")
    fireGroup(participants, "death", player.Name, root and root.Position or nil)
		if scheduleTransitionRespawn then scheduleTransitionRespawn(player) end
   end
  end)
 end

	-- CharacterAutoLoads is intentionally disabled for generated levels, so the
	-- objective controller's CharacterAdded recovery cannot happen by itself.
	-- GameManager owns the reload, while the objective owns the exact ride frame.
	-- Every yield is fenced by one token plus the same round/transition state.
	scheduleTransitionRespawn = function(player)
		if not roundLifecycleOpen or activeLevel ~= 2
			or participantSet[player] ~= true
			or player.Parent ~= Players
			or inRound[player] ~= true
			or player:GetAttribute("InRound") ~= true
			or player:GetAttribute("Level2_ExitTransition") ~= true then
			return
		end
		local token = {}
		transitionRespawnToken[player] = token
		task.spawn(function()
			task.wait(.1)
			if not roundLifecycleOpen or transitionRespawnToken[player] ~= token
				or player.Parent ~= Players or inRound[player] ~= true
				or player:GetAttribute("Level2_ExitTransition") ~= true then return end
			if not loadGameplayCharacter(player) then return end
			local character = player.Character
			local humanoid = character and character:FindFirstChildOfClass("Humanoid")
			local root = character and character:FindFirstChild("HumanoidRootPart")
			if not roundLifecycleOpen or transitionRespawnToken[player] ~= token
				or player.Parent ~= Players or inRound[player] ~= true
				or player:GetAttribute("Level2_ExitTransition") ~= true
				or not humanoid or humanoid.Health <= 0 or not root then return end
			transitionRespawnToken[player] = nil
			if not alive[player] then
				alive[player] = true
				aliveCount += 1
				hookLife(player, humanoid)
			end
		end)
	end

 for _, player in ipairs(participants) do
  participantSet[player] = true
  player:SetAttribute("ZyntraReentryUsed", false)
  if activeLevel == 2 then
   if player:GetAttribute("Level2_ExitTransition") == true then exitTubeRoute = true end
   conns[#conns + 1] = player:GetAttributeChangedSignal("Level2_ExitTransition"):Connect(function()
    if player:GetAttribute("Level2_ExitTransition") == true then exitTubeRoute = true end
   end)
  end
  local char = player.Parent and player.Character
  local hum = char and char:FindFirstChildOfClass("Humanoid")
  local root = char and char:FindFirstChild("HumanoidRootPart")
  if hum and hum.Health > 0 and root then
   alive[player] = true
   aliveCount += 1
   hookLife(player, hum)
  end
 end

 if entity and entity.PrimaryPart and entityStart then
  local bbox, size = entity:GetBoundingBox()
  local pivot = entity:GetPivot()
  local bottomToPivot = pivot.Y - (bbox.Y - size.Y / 2)
  entity:PivotTo(CFrame.new(entityStart.CFrame.X, 0.5 + bottomToPivot, entityStart.CFrame.Z))
 end

 zyntraReentry.OnInvoke = function(player)
  if not participantSet[player] or not player.Parent or alive[player] then return false end
  if workspace:GetAttribute("RoundActive") ~= true or player:GetAttribute("Escaped") == true then return false end
  if reentryUsed[player] or player:GetAttribute("ZyntraReentryUsed") == true then return false end
  reentryUsed[player] = true
  player:SetAttribute("ZyntraReentryUsed", true)
  player:SetAttribute("Escaped", nil)
  player:SetAttribute("Level2_ExitTransition", nil)
  local char = spawnGameplayCharacter(player)
  if not char then
   reentryUsed[player] = nil
   player:SetAttribute("ZyntraReentryUsed", false)
   return false
  end
  local hum = char:FindFirstChildOfClass("Humanoid")
  if not hum or hum.Health <= 0 or not placeSafelyInElevator(player, char) then
   reentryUsed[player] = nil
   player:SetAttribute("ZyntraReentryUsed", false)
   return false
  end
  alive[player] = true
  aliveCount += 1
  hookLife(player, hum)
  fireGroup(participants, "reentry", player.Name)
  return true
 end

 conns[#conns + 1] = Players.PlayerRemoving:Connect(function(player)
  participantSet[player] = nil
	transitionRespawnToken[player] = nil
  if alive[player] then alive[player] = nil; aliveCount -= 1 end
 end)

 -- The party was wiped before the round proper began. This is the Loss endpoint
 -- reached by a different road, and it settles like every other one: it used to
 -- wait a fixed 1.6 seconds and return, so a transfer Roblox merely dropped was
 -- left pending with the completed world torn down around its player and
 -- nobody on this server still answering for them.
 local function sendWipedPartyHome()
  workspace:SetAttribute("PostWinIntermissionActive", false)
  workspace:SetAttribute("RoundActive", false)
  zyntraReentry.OnInvoke = function() return false end
	closeRoundLifecycle()
  fireGroup(participants, "lose", 0, 0, #participants)
  task.wait(5)
  if elevatorApi then elevatorApi.close() end
  returnGroupToLobby(participants)
  local settled, stranded = awaitTransferSettlement(Routing.Endpoints.Loss)
  if not settled then holdCompletedWorld(stranded, Routing.Endpoints.Loss) end
  task.wait(1.6)
 end

 if aliveCount <= 0 then sendWipedPartyHome(); return end
 if activeLevel == 2 then
  -- No elevator ride here, so the loading cover IS the ride: hold the round
  -- until every client reports the complex has streamed in around it. The
  -- timeout sits one second past the client's own 15s cap so a live client
  -- always reports first, and a dead one can still never stall the round.
  fireGroup(participants, "poolaccess")
  waitForGroupEntry(participants, 16)
	elseif activeLevel == 3 and roundEntryMode == LEVEL_TWO_TUBE_ENTRY_MODE then
  -- LEVEL2_EXIT_TRANSITION_20260828
  -- This party is already inside the continuation bore. Replaying the service
  -- elevator would put a descending-lift countdown over a moving slide and,
  -- worse, hold the mall inert for seven seconds underneath them. So the mall is
  -- brought fully live FIRST and only then is the ride handed back: by the time
  -- anyone moves, the objective, hiding and music controllers are all armed.
		-- Placement started streaming while the new world was being prepared. Wait
		-- for every bounded request while riders are still anchored and covered.
		-- Then arm Level 3, give its controllers one heartbeat to observe the
		-- authority change, release everyone together, and only then remove the
		-- loading cover / begin the round timer.
		prepareSlideResume(participants)
		workspace:SetAttribute("PuzzleWon", false)
		workspace:SetAttribute("PostWinIntermissionActive", false)
		workspace:SetAttribute("RoundActive", true)
		RunService.Heartbeat:Wait()
		releaseSlideResume(participants)
		fireGroup(participants, "level3access")
 elseif activeLevel == 3 then
  -- A short service-elevator descent establishes the mall without replaying
  -- Level 1's fuse briefing. Level 3 owns its own objective presentation.
  for t = 7, 1, -1 do
   if aliveCount <= 0 then sendWipedPartyHome(); return end
   fireGroup(participants, "elevator", t)
   task.wait(1)
  end
  elevatorApi.open()
  fireGroup(participants, "level3access")
 else
  -- The party roster is frozen, so the circuit count is already known. Publish
  -- it NOW so the cabin's maintenance poster lists every cable (count + colour)
  -- while the crew rides the elevator, instead of only after the doors open.
  -- PuzzleManager re-asserts the same value when the puzzle actually starts.
  workspace:SetAttribute("Level1ActiveCircuitCount", math.clamp(#participants, 1, 6))
  for t = ELEVATOR_TIME, 1, -1 do
   if aliveCount <= 0 then sendWipedPartyHome(); return end
   fireGroup(participants, "elevator", t)
   task.wait(t == 8 and 2 or 1)
  end
  elevatorApi.open()
 end
  workspace:SetAttribute("PuzzleWon", false)
  workspace:SetAttribute("PostWinIntermissionActive", false)
  workspace:SetAttribute("RoundActive", true)
 local roundStartedAt = os.clock()
 fireGroup(participants, "start")

 local result
 local wipeDeadline
 while true do
  if workspace:GetAttribute("PuzzleWon") then result = "win" break end
  if aliveCount <= 0 then
   wipeDeadline = wipeDeadline or (os.clock() + 15)
   if os.clock() >= wipeDeadline then result = "lose" break end
  else
   wipeDeadline = nil
  end
  local anyEscaped, anyInside = false, false
  for player in pairs(alive) do
   if player:GetAttribute("Escaped") == true then anyEscaped = true else anyInside = true end
  end
  if anyEscaped and not anyInside then result = "win" break end
  task.wait(0.5)
 end

 workspace:SetAttribute("PostWinIntermissionActive", result == "win")
 workspace:SetAttribute("RoundActive", false)
 zyntraReentry.OnInvoke = function() return false end
 if result ~= "win" then
  workspace:SetAttribute("LightMode", "NORMAL")
  workspace:SetAttribute("FlickerBoost", 0)
  workspace:SetAttribute("EntitySpeedMul", 1)
 end
	-- Keep only Level 2's transition lifecycle alive through the 15-second
	-- result window so a rider who dies in the continuing tube is reloaded onto
	-- it. Hazards are already stopped by RoundActive=false.
	if result ~= "win" or activeLevel ~= 2 then closeRoundLifecycle() end

 -- Send consistent end-of-round statistics to every party member so the client
 -- can present the escape as a real payoff instead of a one-line notification.
 local elapsed = math.max(0, os.clock() - roundStartedAt)
 local escapedCount = 0
 for _, participant in ipairs(participants) do
  if participant.Parent and participant:GetAttribute("Escaped") == true then
   escapedCount += 1
   if result == "win" then zyntraLevelCompleted:Fire(participant, activeLevel) end
  end
 end
 if result == "win" then
  -- LEVEL2_EXIT_TRANSITION_20260828: everyone continuing out of Level 2 left
  -- down the exit flume (the win condition requires every surviving participant
  -- to have escaped), so the next server resumes them inside Level 3's
  -- continuation bore rather than on a spawn pad. Decided BEFORE the window
  -- opens: an immediate Continue departs during it and has to arrive exactly
  -- the way a timed-out continuer will. The entry mode describes the ROUTE the
  -- party took, not per-player state, so one straggler recovered to the chamber
  -- must not downgrade everyone else's arrival.
  local entryMode = (activeLevel == 2 and Routing.NextLevel(activeLevel) == 3
   and exitTubeRoute) and LEVEL_TWO_TUBE_ENTRY_MODE or nil
  local outcome = runPostWinIntermission(participants, elapsed, escapedCount, entryMode)
  local nextLevel = outcome.NextLevel
  local continuing, returning = outcome.Continuing, outcome.Returning
	closeRoundLifecycle()
  -- RoundActive still stops hazards immediately, but the completed world and
  -- its solved lighting remain intact for the full result countdown.
  workspace:SetAttribute("PostWinIntermissionActive", false)
  workspace:SetAttribute("LightMode", "NORMAL")
  workspace:SetAttribute("FlickerBoost", 0)
  workspace:SetAttribute("EntitySpeedMul", 1)
  if outcome.Aborted then return end
  if elevatorApi then elevatorApi.close() end

  if nextLevel then
   if IS_STUDIO then
    continueStudioCampaign(participants, continuing, returning, nextLevel, entryMode)
    return
   end
   if #continuing > 0 then
    local moved, moveError = teleportPlayersToNextLevel(continuing, {
     NextLevel = nextLevel,
     EntryMode = entryMode,
     AccessCode = outcome.AccessCode,
     SessionId = outcome.Session.Id,
     Deadline = outcome.Session.Deadline,
     -- Exact now, and marked as such: everybody who left on an immediate
     -- Continue plus everybody the countdown is carrying.
     Expected = outcome.Cohort,
     Final = true,
    })
    if moved then
     -- Everyone who is not progressing belongs in the lobby. This includes
     -- opted-out participants plus late reserved-server arrivals/reconnects
     -- that were never part of the frozen round roster. Anyone already in
     -- flight -- an early Continue, or an early Back to Lobby still resolving
     -- -- holds a live transfer claim and is skipped here and by
     -- claimForTransfer. A FAILED claim owns nobody, so a player whose early
     -- transfer was rejected is swept here rather than left behind.
     local progressing = {}
     for _, player in ipairs(continuing) do progressing[player] = true end
     local lobbyBound = Routing.LobbyBound(Players:GetPlayers(), progressing, pendingTeleports)
     if #lobbyBound > 0 then
      task.spawn(function()
       local returned, returnError, remaining = teleportPlayersToLobby(lobbyBound)
       if not returned and #remaining > 0 then
        warn("GameManager: non-progressing lobby transfer failed: " .. tostring(returnError))
        for _, player in ipairs(remaining) do
         -- Skip anybody the runtime is already retrying; see returnGroupToLobby.
         if not Routing.ClaimOwns(pendingTeleports[player]) then
          finishFailedTeleportLocally(player, returnError)
         end
        end
       end
      end)
     end
     -- Hold the finished world until every claim this session opened has
     -- resolved. An early Back or early Continue can still be in flight, and
     -- if Roblox rejects it now, the recovery path above is the only authority
     -- left for that player -- it must not be standing in a deleted map.
     local settled, stranded = awaitTransferSettlement(Routing.Endpoints.Continuation)
     if not settled then holdCompletedWorld(stranded, Routing.Endpoints.Continuation) end
     return
    end
    warn("GameManager: next-level teleport failed: " .. tostring(moveError))
    fireGroup(continuing, "transitionfailed")
   end
   -- No continuer, or Roblox rejected the fresh reserved-server transition.
   returnGroupToLobby(participants)
   local settled, stranded = awaitTransferSettlement(Routing.Endpoints.Fallback)
   if not settled then holdCompletedWorld(stranded, Routing.Endpoints.Fallback) end
   task.wait(1.6)
   return
  end

  -- Level 3 is the current campaign endpoint. It settles like every other one:
  -- waiting 1.6 seconds and returning left a silently-dropped transfer pending
  -- with nobody left to answer for it.
  returnGroupToLobby(participants)
  local settled, stranded = awaitTransferSettlement(Routing.Endpoints.Level3)
  if not settled then holdCompletedWorld(stranded, Routing.Endpoints.Level3) end
  task.wait(1.6)
  return
 end

 fireGroup(participants, "lose", elapsed, escapedCount, #participants)
 task.wait(5.5)
 if elevatorApi then elevatorApi.close() end
 returnGroupToLobby(participants)
 local settled, stranded = awaitTransferSettlement(Routing.Endpoints.Loss)
 if not settled then holdCompletedWorld(stranded, Routing.Endpoints.Loss) end
 task.wait(1.6)
end

-- Launch one station. Published servers teleport the selected group into a fresh
-- reserved server. Studio cannot test TeleportService, so it runs the same party
-- locally as a practical editor-only fallback.
local function launchStation(station, participants)
 station.busy = true
 setStationDisplay(station, "STARTING PRIVATE WORLD", #participants .. "/" .. (station.maxPlayers or MAX_PLAYERS_PER_STATION) .. " PLAYERS", station.color)
 armGroupEntry(participants)
 fireGroup(participants, "loadinggame", station.level or 1)

 if IS_STUDIO then
  if roundBusy then
   setStationDisplay(station, "STUDIO WORLD BUSY", "WAIT FOR THE ACTIVE TEST", Color3.fromRGB(255, 210, 90))
   task.wait(2)
   station.busy = false
   return
  end

  roundBusy = true
  clearGlowsticks()
  assignGlowstickSlots(participants)
  -- A round started from the lobby is never a continuation, whatever the last
  -- one was; leaving a stale route here would skip Level 3's elevator descent.
  roundEntryMode = nil
  for _, player in ipairs(participants) do
   inRound[player] = true
   player:SetAttribute("InRound", true)
   player:SetAttribute("Escaped", nil)
   player:SetAttribute("Level2_ExitTransition", nil)
  end
  if ensureWorld(participants, station.level or 1) then
   for _, player in ipairs(participants) do
    if player.Parent then
     local char = spawnGameplayCharacter(player)
     if char then placeSafelyInElevator(player, char) end
    end
   end
   task.wait(0.6)
   playRound(participants)
  else
   fireGroup(participants, "loadfailed")
   returnGroupToLobby(participants)
  end
  roundBusy = false
  station.busy = false
  return
 end

 local options = Instance.new("TeleportOptions")
 local glowstickSlots = {}
 for index, player in ipairs(participants) do
  glowstickSlots[tostring(player.UserId)] = index
 end
 options.ShouldReserveServer = true
 -- A station launch is a session too, and a complete one: the whole party
 -- leaves in a single transfer, so the destination is told the exact cohort and
 -- that no more are coming. It admits them as soon as they have all landed.
 local launchToken = game.JobId .. ":station" .. station.index
  .. ":" .. math.floor(os.clock() * 1000)
 local packet = Routing.ArrivalPacket({
  Level = station.level or 1,
  SessionId = launchToken,
  Expected = #participants,
  Final = true,
  GlowstickSlots = glowstickSlots,
  LaunchToken = launchToken,
 })
 packet.Station = station.index
 options:SetTeleportData(packet)
 local ok, err = pcall(function()
  TeleportService:TeleportAsync(game.PlaceId, participants, options)
 end)
 if not ok then
  warn("GameManager: station " .. station.index .. " teleport failed: " .. tostring(err))
  setStationDisplay(station, "TELEPORT FAILED", "STEP OUT AND TRY AGAIN", Color3.fromRGB(255, 105, 95))
  fireGroup(participants, "lobbycancel")
  task.wait(2.5)
 else
  task.wait(7)
 end
 station.busy = false
end

local function resetStation(station, closeHost)
 local oldHost = station.host
 if closeHost and oldHost and oldHost.Parent then
  status:FireClient(oldHost, "queueconfigclosed", station.index)
 end
 for player, stateName in pairs(station.feedback or {}) do
  if player.Parent and stateName ~= "ready" and player ~= oldHost then
   status:FireClient(player, "lobby")
  end
 end
 station.host = nil
 station.configured = false
 station.awaitingConfig = false
 station.cancelRequested = false
 station.maxPlayers = MAX_PLAYERS_PER_STATION
 station.privacy = "public"
 station.entrySeen = {}
 station.friendCache = {}
 station.feedback = {}
 setStationDisplay(station,
  "STATION " .. (station.displayIndex or station.index) .. "  •  0/6",
  "ENTER TO HOST  •  CHOOSE 1-6 PLAYERS",
  station.color)
end

local function syncSetupFeedback(station, raw)
 local nextFeedback = {[station.host] = "host"}
 for _, player in ipairs(raw) do
  if player ~= station.host then
   nextFeedback[player] = "waiting"
   if station.feedback[player] ~= "waiting" then
    status:FireClient(player, "queuewaitinghost", station.index)
   end
  end
 end
 for player, stateName in pairs(station.feedback) do
  if not nextFeedback[player] and player.Parent and stateName ~= "host" then
   status:FireClient(player, "lobby")
  end
 end
 station.feedback = nextFeedback
end

local function syncQueueFeedback(station, raw, accepted, rejected)
 local nextFeedback = {}
 for _, player in ipairs(accepted) do nextFeedback[player] = "ready" end
 for _, info in ipairs(rejected) do
  local stateName = info.reason
  nextFeedback[info.player] = stateName
  if station.feedback[info.player] ~= stateName then
   if stateName == "private" then
    status:FireClient(info.player, "queueprivate", station.index, station.host and station.host.DisplayName or "HOST")
   else
    status:FireClient(info.player, "queuefull", station.index, station.maxPlayers)
   end
  end
 end
 for player in pairs(station.feedback) do
  if not nextFeedback[player] and player.Parent and not inRound[player] then
   status:FireClient(player, "lobby")
  end
 end
 station.feedback = nextFeedback
end

local function runStation(station)
 resetStation(station, false)
 while true do
  if station.busy then task.wait(0.25) continue end
  if IS_STUDIO and roundBusy then
   if station.host then resetStation(station, true) end
   setStationDisplay(station,
    "STATION " .. (station.displayIndex or station.index) .. "  •  0/6",
    "STUDIO TEST ROUND IN PROGRESS",
    Color3.fromRGB(255, 210, 90))
   task.wait(0.5)
   continue
  end

  if station.cancelRequested then
   resetStation(station, true)
   task.wait(0.25)
   continue
  end

  local raw = rawQueuedPlayers(station)
  if #raw == 0 then
   if station.host then resetStation(station, true) else
    setStationDisplay(station,
     "STATION " .. (station.displayIndex or station.index) .. "  •  0/6",
     "ENTER TO HOST  •  CHOOSE 1-6 PLAYERS",
     station.color)
   end
   task.wait(0.25)
   continue
  end

  if not station.host then
   station.host = raw[1]
   station.configured = false
   station.awaitingConfig = true
   station.maxPlayers = MAX_PLAYERS_PER_STATION
   station.privacy = "public"
   station.friendCache = {}
   station.feedback = {[station.host] = "host"}
   setStationDisplay(station,
    "STATION " .. (station.displayIndex or station.index) .. "  •  HOST SETTING UP",
    "1/6 IN ZONE  •  CHOOSE PARTY SETTINGS",
    station.color)
   status:FireClient(station.host, "queuehost", station.index, station.maxPlayers, station.privacy)
   task.wait(0.25)
   continue
  end

  if not playerInsideZone(station.host, station) then
   resetStation(station, true)
   task.wait(0.25)
   continue
  end

  if not station.configured then
   raw = rawQueuedPlayers(station)
   setStationDisplay(station,
    "STATION " .. (station.displayIndex or station.index) .. "  •  HOST SETTING UP",
    #raw .. "/6 IN ZONE  •  WAITING FOR SETTINGS",
    station.color)
   syncSetupFeedback(station, raw)
   task.wait(0.25)
   continue
  end

  local ready, allInside, rejected = queuedPlayers(station)
  if #ready == 0 then
   resetStation(station, true)
   task.wait(0.25)
   continue
  end
  syncQueueFeedback(station, allInside, ready, rejected)

  local cancelled = false
  local lastReady = ready
  local countdownTime = QUEUE_TIME
  for _, player in ipairs(ready) do
   if player:GetAttribute("DevFastQueue") == true then
    countdownTime = FAST_QUEUE_TIME
    break
   end
  end
  for t = countdownTime, 1, -1 do
   if not (station.host and playerInsideZone(station.host, station) and station.configured) then
    cancelled = true
    break
   end
   ready, allInside, rejected = queuedPlayers(station)
   if #ready == 0 then cancelled = true break end
   lastReady = ready
   syncQueueFeedback(station, allInside, ready, rejected)
   local full = #ready >= station.maxPlayers
   setStationDisplay(station,
    "GAME BEGINS IN " .. t,
    #ready .. "/" .. station.maxPlayers .. " READY  •  " .. privacyLabel(station)
     .. (full and "  •  PARTY FULL" or ""),
    station.color)
   fireGroup(ready, "lobbycountdown", t, #ready, station.index, station.maxPlayers, station.privacy)
   task.wait(1)
  end

  if cancelled then
   fireGroup(lastReady, "lobbycancel")
   resetStation(station, false)
   task.wait(1)
   continue
  end

  local participants = queuedPlayers(station)
  if #participants > 0 and participants[1] == station.host then
   station.feedback = {}
   launchStation(station, participants)
  end
  resetStation(station, false)
 end
end

-- Every arrival's OWN packet. Admission is decided from the session each player
-- travelled under, not from whichever packet happened to be read first: an
-- immediate continuer and a timed-out continuer now carry the same session id,
-- and both belong in the same round.
local function arrivalEntries()
 local entries = {}
 for _, player in ipairs(Players:GetPlayers()) do
  local ok, joinData = pcall(function() return player:GetJoinData() end)
  entries[#entries + 1] = {
   Member = player,
   Data = ok and joinData and joinData.TeleportData or nil,
  }
 end
 return entries
end

-- Stage arrivals until the source's decision window has closed (plus a bounded
-- transport grace), or until the session's full cohort is here, then admit
-- everybody who came from that session as ONE party.
--
-- The old code waited for PartySize players and started the round; because each
-- continuer travelled as a party of one, that meant the first arrival started
-- the round and everybody after them -- a later manual Continue, and every
-- player the 15-second countdown carried -- landed into roundBusy and was
-- initialised as a spectator.
local function stageArrivingParty()
 local startedAt = os.clock()
 local firstArrivalAt = nil
 local announced = nil
 while true do
  local group = Routing.SelectArrivalSession(arrivalEntries())
  local arrived = group and #group.Members or 0
  if arrived > 0 and not firstArrivalAt then firstArrivalAt = os.clock() end
  local decision, reason = Routing.ArrivalDecision({
   Now = os.clock(),
   StartedAt = startedAt,
   FirstArrivalAt = firstArrivalAt,
   ServerNow = workspace:GetServerTimeNow(),
   Deadline = group and group.Deadline or nil,
   Arrived = arrived,
   Expected = group and group.Expected or nil,
   CohortHorizon = group and group.CohortHorizon or nil,
   Final = group and group.Final or false,
  })
  if decision ~= "wait" then
   print(string.format("[GameManager] admission: %s (%s) -- %d arrived, expecting %s",
    decision, tostring(reason), arrived, tostring(group and group.Expected)))
   return decision, group
  end
  if announced ~= reason then
   announced = reason
   print(string.format("[GameManager] staging arrivals: %s (%d here, expecting %s)",
    tostring(reason), arrived, tostring(group and group.Expected)))
  end
  task.wait(0.2)
 end
end

if IS_RESERVED_ROUND_SERVER then
 task.spawn(function()
  -- Hold characters behind the loading screen until the source's result window
  -- has closed and the whole cohort has landed, then generate exactly one
  -- isolated world for that group.
  local decision, group = stageArrivingParty()
  if decision ~= "admit" or not group then return end

  local selectedLevel = Routing.ClampLevel(group.Level)
  local participants = {}
  for _, player in ipairs(group.Members) do
   if player.Parent == Players then participants[#participants + 1] = player end
  end
  table.sort(participants, function(a, b) return a.UserId < b.UserId end)
  while #participants > MAX_PLAYERS_PER_STATION do table.remove(participants) end
  if #participants == 0 then return end

  local glowstickSlots = nil
  for _, entry in ipairs(arrivalEntries()) do
   local data = entry.Data
   if type(data) == "table" and data.RoundSessionId == group.SessionId
    and type(data.GlowstickSlots) == "table" then
    glowstickSlots = data.GlowstickSlots
    break
   end
  end

  roundBusy = true
  clearGlowsticks()
  assignGlowstickSlots(participants, glowstickSlots)
  for _, player in ipairs(participants) do
   inRound[player] = true
   player:SetAttribute("InRound", true)
   player:SetAttribute("Escaped", nil)
   player:SetAttribute("Level2_ExitTransition", nil)
  end
  armGroupEntry(participants)
  fireGroup(participants, "loadinggame", selectedLevel)

  local useSlideResume = selectedLevel == 3
   and group.EntryMode == LEVEL_TWO_TUBE_ENTRY_MODE
  roundEntryMode = useSlideResume and LEVEL_TWO_TUBE_ENTRY_MODE or nil
  if ensureWorld(participants, selectedLevel) then
   for _, player in ipairs(participants) do
    if player.Parent then
     pendingExplicitPlacement[player] = true
     local char = spawnGameplayCharacter(player)
     if char then placeOnLevelEntry(player, char, useSlideResume) end
    end
   end
   task.wait(0.6)
   playRound(participants)
  else
   fireGroup(participants, "loadfailed")
   returnGroupToLobby(participants)
  end
  roundBusy = false
 end)
else
 for _, station in ipairs(lobbyStations) do
  task.spawn(function() runStation(station) end)
 end
end
