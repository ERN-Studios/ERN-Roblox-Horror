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

local QUEUE_TIME = 10
local FAST_QUEUE_TIME = 3
local MAX_PLAYERS_PER_STATION = 6
local ELEVATOR_TIME = 19
local POST_WIN_SECONDS = 15
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
local MAX_LEVEL = 3

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

local function placeSafelyInElevator(player, char)
 local pad = workspace:FindFirstChild("ElevatorSpawn")
 local root = char and char:WaitForChild("HumanoidRootPart", 8)
 local hum = char and char:FindFirstChildOfClass("Humanoid")
 if not (pad and root and hum and hum.Health > 0) then return false end

 -- The lobby and maze are far apart. Keep the character server-anchored while
 -- the client streams the elevator region so it cannot fall through an unloaded floor.
 pad.CanCollide = true -- invisible emergency floor inside the cabin
 task.spawn(function()
  pcall(function() player:RequestStreamAroundAsync(pad.Position, 6) end)
 end)
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
   if worldReady then placeSafelyInElevator(player, char) end
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
 station.friendCache[player.UserId] = allowed
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
 entryReady[player] = nil
 lobbyBriefingReady[player] = nil
 pendingTeleports[player] = nil
 if activePostWin then
  activePostWin.Eligible[player] = nil
  activePostWin.Returning[player] = nil
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
 local level = math.clamp(math.floor(tonumber(requestedLevel) or 1), 1, MAX_LEVEL)
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
 local generatorScript = script.Parent:FindFirstChild("MazeGenerator")
 local entityScript = script.Parent:FindFirstChild("EntityAI")
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
		player:SetAttribute("GlowstickSlot", nil)
		player:SetAttribute("GlowstickColor", nil)
		loadLobbyCharacter(player)
		status:FireClient(player, "lobby")
	end
end

local function registerPendingTeleport(group, destination, options, nextLevel)
	for _, player in ipairs(group) do
		pendingTeleports[player] = {
			Destination = destination,
			Options = options,
			NextLevel = nextLevel,
			Failures = 0,
		}
	end
end

local function clearPendingTeleport(group)
	for _, player in ipairs(group) do pendingTeleports[player] = nil end
end

local function teleportPlayersToLobby(group)
	local live = livePlayers(group)
	if #live == 0 then return true, nil, live end
	if not IS_RESERVED_ROUND_SERVER or IS_STUDIO then return false, "LOCAL_FALLBACK", live end
	local options = Instance.new("TeleportOptions")
	options:SetTeleportData({ReturnToLobby = true})
	registerPendingTeleport(live, "lobby", options, nil)
	local ok, err = pcall(function()
		TeleportService:TeleportAsync(game.PlaceId, live, options)
	end)
	if not ok then clearPendingTeleport(live) end
	return ok, err, live
end

local function teleportPlayersToNextLevel(group, nextLevel)
	local live = livePlayers(group)
	if #live == 0 then return true, nil, live end
	if IS_STUDIO then return false, "STUDIO_LOCAL_TRANSITION", live end
	local glowstickSlots = {}
	for index, player in ipairs(live) do
		local slot = math.clamp(math.floor(tonumber(player:GetAttribute("GlowstickSlot")) or index), 1, MAX_PLAYERS_PER_STATION)
		glowstickSlots[tostring(player.UserId)] = slot
	end
	local options = Instance.new("TeleportOptions")
	options.ShouldReserveServer = true
	options:SetTeleportData({
		BackroomsRound = true,
		PartySize = #live,
		Level = nextLevel,
		LaunchToken = game.JobId .. ":progress:" .. tostring(nextLevel) .. ":" .. tostring(math.floor(os.clock() * 1000)),
		GlowstickSlots = glowstickSlots,
	})
	registerPendingTeleport(live, "next", options, nextLevel)
	local ok, err = pcall(function()
		TeleportService:TeleportAsync(game.PlaceId, live, options)
	end)
	if not ok then clearPendingTeleport(live) end
	return ok, err, live
end

local function returnGroupToLobby(group)
	-- A late reserved-server arrival is a spectator, but must never be stranded.
	local candidates = IS_RESERVED_ROUND_SERVER and Players:GetPlayers() or group
	local ok, err, live = teleportPlayersToLobby(candidates)
	if ok and IS_RESERVED_ROUND_SERVER and not IS_STUDIO then
		-- Keep the completed map intact while Roblox transfers the party. The old
		-- isolated server and its world disappear naturally after the last leave.
		return true
	end
	if err ~= "LOCAL_FALLBACK" and #live > 0 then
		warn("GameManager: return-to-lobby teleport failed: " .. tostring(err))
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
		or session.Eligible[player] ~= true
		or session.Returning[player] == true
		or inRound[player] ~= true
		or player:GetAttribute("InRound") ~= true
		or player.Parent ~= Players then
		return
	end

	-- Latch before any yield/TeleportAsync call; clients cannot choose the
	-- destination, deadline, level, or another party member.
	session.Returning[player] = true
	status:FireClient(player, "returnpending", session.Serial)
	if IS_RESERVED_ROUND_SERVER and not IS_STUDIO then
		task.spawn(function()
			local ok, err = teleportPlayersToLobby({player})
			if not ok and activePostWin == session and not session.Closed and player.Parent == Players then
				session.Returning[player] = nil
				status:FireClient(player, "returnfailed", session.Serial)
				warn("GameManager: early return-to-lobby failed for " .. player.Name .. ": " .. tostring(err))
			end
		end)
	end
end

local function finishFailedTeleportLocally(player, reason)
	pendingTeleports[player] = nil
	if player.Parent ~= Players then return end
	warn("GameManager: recovering stranded player in the local lobby: " .. player.Name .. " (" .. tostring(reason) .. ")")
	status:FireClient(player, "transitionfailed")
	-- A twice-failed early Return-to-Lobby transfer can arrive while the 15-second
	-- post-win loop is still running. Abort that session before cleaning the world;
	-- otherwise its deadline branch can later send the recovered party onward too.
	local interruptedSession = activePostWin
	if interruptedSession and not interruptedSession.Closed then
		interruptedSession.Aborted = true
		interruptedSession.Closed = true
		activePostWin = nil
	end
	-- This is the final safety net after both the original transfer and its retry
	-- were rejected. One cleanup is enough even if several players fail together.
	local recoveryGroup = {player}
	if worldReady then
		recoveryGroup = Players:GetPlayers()
		for _, stranded in ipairs(recoveryGroup) do pendingTeleports[stranded] = nil end
		cleanupActiveWorld()
	end
	returnPlayersToLocalLobby(recoveryGroup)
end

local recoverFailedTeleport
recoverFailedTeleport = function(player, record, placeId, failedOptions, reason)
	if player.Parent ~= Players or pendingTeleports[player] ~= record then return end
	if record.Failures < 1 then
		record.Failures += 1
		task.delay(1, function()
			if player.Parent ~= Players or pendingTeleports[player] ~= record then return end
			local options = failedOptions or record.Options
			local destinationPlaceId = tonumber(placeId) or game.PlaceId
			local ok, retryError = pcall(function()
				TeleportService:TeleportAsync(destinationPlaceId, {player}, options)
			end)
			if not ok then
				recoverFailedTeleport(player, record, destinationPlaceId, options, retryError)
			end
		end)
		return
	end

	if record.Destination == "next" then
		-- A player who cannot enter the next reserved server must still escape the
		-- completed server. Fall back to a fresh lobby transfer with its own retry.
		pendingTeleports[player] = nil
		status:FireClient(player, "transitionfailed")
		task.spawn(function()
			local returned, returnError = teleportPlayersToLobby({player})
			if not returned then finishFailedTeleportLocally(player, returnError) end
		end)
	else
		task.spawn(finishFailedTeleportLocally, player, reason)
	end
end

TeleportService.TeleportInitFailed:Connect(function(player, teleportResult, errorMessage, placeId, teleportOptions)
	local record = pendingTeleports[player]
	if not record then return end
	warn("GameManager: teleport initialization failed for", player.Name, teleportResult, errorMessage)
	recoverFailedTeleport(player, record, placeId, teleportOptions, errorMessage)
end)

local function runPostWinIntermission(participants, elapsed, escapedCount)
	postWinSerial += 1
	local nextLevel = activeLevel < MAX_LEVEL and activeLevel + 1 or nil
	local deadline = workspace:GetServerTimeNow() + POST_WIN_SECONDS
	local session = {
		Serial = postWinSerial,
		Level = activeLevel,
		Deadline = deadline,
		NextLevel = nextLevel,
		Eligible = {},
		Returning = {},
		Closed = false,
		Aborted = false,
	}
	for _, player in ipairs(participants) do
		if player.Parent == Players then session.Eligible[player] = true end
	end
	activePostWin = session
	fireGroup(participants, "win", elapsed, escapedCount, #participants, deadline, nextLevel, session.Serial)

	while activePostWin == session and workspace:GetServerTimeNow() < deadline do
		task.wait(0.1)
	end
	session.Closed = true
	if activePostWin == session then activePostWin = nil end
	if session.Aborted then
		return nil, {}, {}, true
	end

	local continuing, returning = {}, {}
	for player in pairs(session.Eligible) do
		if player.Parent == Players then
			if session.Returning[player] then
				returning[#returning + 1] = player
			else
				continuing[#continuing + 1] = player
			end
		end
	end
	table.sort(continuing, function(a, b) return a.UserId < b.UserId end)
	table.sort(returning, function(a, b) return a.UserId < b.UserId end)
	return nextLevel, continuing, returning, false
end

local function continueStudioCampaign(participants, continuing, returning, nextLevel)
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
	end
	if not ensureWorld(continuing, nextLevel) then
		fireGroup(continuing, "loadfailed")
		returnGroupToLobby(continuing)
		return
	end
	for _, player in ipairs(continuing) do
		if player.Parent then
			loadGameplayCharacter(player)
			local character = player.Character or player.CharacterAdded:Wait()
			placeSafelyInElevator(player, character)
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

 local function hookLife(player, hum)
  conns[#conns + 1] = hum.Died:Connect(function()
   if alive[player] then
    alive[player] = nil
    aliveCount -= 1
    local root = player.Character and player.Character:FindFirstChild("HumanoidRootPart")
    fireGroup(participants, "death", player.Name, root and root.Position or nil)
   end
  end)
 end

 for _, player in ipairs(participants) do
  participantSet[player] = true
  player:SetAttribute("ZyntraReentryUsed", false)
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
  if not loadGameplayCharacter(player) then
   reentryUsed[player] = nil
   player:SetAttribute("ZyntraReentryUsed", false)
   return false
  end
  local char = player.Character or player.CharacterAdded:Wait()
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
  if alive[player] then alive[player] = nil; aliveCount -= 1 end
 end)

 local function sendWipedPartyHome()
  workspace:SetAttribute("PostWinIntermissionActive", false)
  workspace:SetAttribute("RoundActive", false)
  zyntraReentry.OnInvoke = function() return false end
  for _, connection in ipairs(conns) do connection:Disconnect() end
  fireGroup(participants, "lose", 0, 0, #participants)
  task.wait(5)
  elevatorApi.close()
  returnGroupToLobby(participants)
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
 for _, connection in ipairs(conns) do connection:Disconnect() end

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
  local nextLevel, continuing, returning, postWinAborted = runPostWinIntermission(participants, elapsed, escapedCount)
  -- RoundActive still stops hazards immediately, but the completed world and
  -- its solved lighting remain intact for the full result countdown.
  workspace:SetAttribute("PostWinIntermissionActive", false)
  workspace:SetAttribute("LightMode", "NORMAL")
  workspace:SetAttribute("FlickerBoost", 0)
  workspace:SetAttribute("EntitySpeedMul", 1)
  if postWinAborted then return end
  if elevatorApi then elevatorApi.close() end

  if nextLevel then
   if IS_STUDIO then
    continueStudioCampaign(participants, continuing, returning, nextLevel)
    return
   end
   if #continuing > 0 then
    local moved, moveError = teleportPlayersToNextLevel(continuing, nextLevel)
    if moved then
     -- Everyone who is not progressing belongs in the lobby. This includes
     -- opted-out participants plus late reserved-server arrivals/reconnects
     -- that were never part of the frozen round roster.
     local progressing = {}
     for _, player in ipairs(continuing) do progressing[player] = true end
     local lobbyBound = {}
     for _, player in ipairs(Players:GetPlayers()) do
      if not progressing[player] then lobbyBound[#lobbyBound + 1] = player end
     end
     if #lobbyBound > 0 then
      task.spawn(function()
       local returned, returnError, stillHere = teleportPlayersToLobby(lobbyBound)
       if not returned and #stillHere > 0 then
        warn("GameManager: non-progressing lobby transfer failed: " .. tostring(returnError))
        cleanupActiveWorld()
        returnPlayersToLocalLobby(stillHere)
       end
      end)
     end
     return
    end
    warn("GameManager: next-level teleport failed: " .. tostring(moveError))
    fireGroup(continuing, "transitionfailed")
   end
   -- No continuer, or Roblox rejected the fresh reserved-server transition.
   returnGroupToLobby(participants)
   task.wait(1.6)
   return
  end

  -- Level 3 is the current campaign endpoint.
  returnGroupToLobby(participants)
  task.wait(1.6)
  return
 end

 fireGroup(participants, "lose", elapsed, escapedCount, #participants)
 task.wait(5.5)
 if elevatorApi then elevatorApi.close() end
 returnGroupToLobby(participants)
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
  for _, player in ipairs(participants) do
   inRound[player] = true
   player:SetAttribute("InRound", true)
   player:SetAttribute("Escaped", nil)
  end
  if ensureWorld(participants, station.level or 1) then
   for _, player in ipairs(participants) do
    if player.Parent then
     loadGameplayCharacter(player)
     local char = player.Character or player.CharacterAdded:Wait()
     placeSafelyInElevator(player, char)
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
 options:SetTeleportData({
  BackroomsRound = true,
  PartySize = #participants,
  Station = station.index,
   Level = station.level or 1,
  LaunchToken = game.JobId .. ":" .. station.index .. ":" .. math.floor(os.clock() * 1000),
  GlowstickSlots = glowstickSlots,
 })
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

local function roundTeleportData()
 for _, player in ipairs(Players:GetPlayers()) do
  local ok, joinData = pcall(function() return player:GetJoinData() end)
  local data = ok and joinData and joinData.TeleportData
  if type(data) == "table" and data.BackroomsRound == true then return data end
 end
 return nil
end

if IS_RESERVED_ROUND_SERVER then
 task.spawn(function()
  -- Hold characters behind the loading screen until the whole teleported party
  -- has arrived, then generate exactly one isolated world for that group.
  local arrivalDeadline = os.clock() + 30
  while #Players:GetPlayers() == 0 and os.clock() < arrivalDeadline do task.wait(0.2) end

  local data = roundTeleportData()
  local selectedLevel = math.clamp(math.floor(tonumber(data and data.Level) or 1), 1, MAX_LEVEL)
  local expected = math.clamp(tonumber(data and data.PartySize) or 1, 1, MAX_PLAYERS_PER_STATION)
  local partyDeadline = os.clock() + 12
  while #Players:GetPlayers() < expected and os.clock() < partyDeadline do task.wait(0.2) end

  local participants = Players:GetPlayers()
  table.sort(participants, function(a, b) return a.UserId < b.UserId end)
  while #participants > MAX_PLAYERS_PER_STATION do table.remove(participants) end
  if #participants == 0 then return end

  roundBusy = true
  clearGlowsticks()
  assignGlowstickSlots(participants, data and data.GlowstickSlots)
  for _, player in ipairs(participants) do
   inRound[player] = true
   player:SetAttribute("InRound", true)
   player:SetAttribute("Escaped", nil)
  end
  armGroupEntry(participants)
  fireGroup(participants, "loadinggame", selectedLevel)

  if ensureWorld(participants, selectedLevel) then
   for _, player in ipairs(participants) do
    if player.Parent then
     loadGameplayCharacter(player)
     local char = player.Character or player.CharacterAdded:Wait()
     placeSafelyInElevator(player, char)
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
