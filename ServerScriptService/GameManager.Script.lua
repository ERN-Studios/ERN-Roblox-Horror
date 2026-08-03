-- GameManager (v4 -- lobby queue into the existing elevator round)

local Players = game:GetService("Players")
local RS = game:GetService("ReplicatedStorage")
local TweenService = game:GetService("TweenService")
local TeleportService = game:GetService("TeleportService")
local RunService = game:GetService("RunService")
local StarterPlayer = game:GetService("StarterPlayer")
local ServerStorage = game:GetService("ServerStorage")

local remotes = RS:WaitForChild("Remotes")
local status = remotes:WaitForChild("RoundStatus")
local queueConfig = remotes:FindFirstChild("ConfigureQueue")
if not queueConfig then
 queueConfig = Instance.new("RemoteEvent")
 queueConfig.Name = "ConfigureQueue"
 queueConfig.Parent = remotes
end

local QUEUE_TIME = 10
local FAST_QUEUE_TIME = 3
local DEV_QUEUE_NAMES = {mikkelczar = true, LaverSneglen = true}
local MAX_PLAYERS_PER_STATION = 6
local ELEVATOR_TIME = 19
local LOBBY_CENTER = Vector3.new(0, 30, -760)

Players.CharacterAutoLoads = false
workspace:SetAttribute("GenerateWorld", false)
workspace:SetAttribute("RoundActive", false)

-- A station launch creates a reserved server of this same place. Reserved servers
-- run the maze directly; public servers remain lightweight four-station lobbies.
local IS_RESERVED_ROUND_SERVER = game.PrivateServerId ~= "" and game.PrivateServerOwnerId == 0
local IS_STUDIO = RunService:IsStudio()

-- B keeps its existing ESP toggle on the client and also sends this
-- server-authoritative queue-speed toggle for whitelisted developers.
local devControl = remotes:WaitForChild("DevControl")
devControl.OnServerEvent:Connect(function(player, command, enabled)
 if IS_RESERVED_ROUND_SERVER or command ~= "fastQueue" then return end
 if not DEV_QUEUE_NAMES[player.Name] then return end
 player:SetAttribute("DevFastQueue", enabled == true and true or nil)
 print("[GameManager] 3-second queue", enabled == true and "ON" or "OFF", "for", player.Name)
end)

local inRound = {}
local roundBusy = false
local worldReady = false
local activeLevel = 1
local elevatorApi = nil
local mazeStart, entityStart, entity

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
 local gameplayRig = StarterPlayer:FindFirstChild("StarterCharacter")
 if gameplayRig then gameplayRig.Parent = ServerStorage end
 local ok, err
 if description then
  ok, err = pcall(player.LoadCharacterWithHumanoidDescriptionAsync, player, description:Clone())
 else
  ok, err = pcall(player.LoadCharacterAsync, player)
 end
 if gameplayRig then gameplayRig.Parent = StarterPlayer end
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

-- Simple isolated server lobby with a large glowing launch square.
local function makePart(parent, name, position, size, color, material, transparency)
 local part = Instance.new("Part")
 part.Name = name
 part.Anchored = true
 part.Size = size
 part.Position = position
 part.Color = color
 part.Material = material or Enum.Material.SmoothPlastic
 part.Transparency = transparency or 0
 part.TopSurface = Enum.SurfaceType.Smooth
 part.BottomSurface = Enum.SurfaceType.Smooth
 part.Parent = parent
 return part
end

local function buildLobby()
 return require(script.Parent:WaitForChild("TunnelLobbyBuilder")).Build(LOBBY_CENTER)
end

local lobbyModel, lobbySpawn, lobbyStations = buildLobby()

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
 local position = pad.Position + Vector3.new(ox, 4, oz)
 char:PivotTo(CFrame.lookAt(position, position + Vector3.new(1, 0, 0)))

 local shield = Instance.new("ForceField")
 shield.Name = "LobbyTransferShield"
 shield.Visible = false
 shield.Parent = char
 task.delay(2.5, function()
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
 player.CharacterAdded:Connect(function(char) onCharacter(player, char) end)
 task.defer(function()
  if not player.Parent then return end
  if not IS_RESERVED_ROUND_SERVER and not player.Character then loadLobbyCharacter(player) end
  status:FireClient(player, IS_RESERVED_ROUND_SERVER and "loadinggame" or "lobby")
 end)
end

Players.PlayerAdded:Connect(setupPlayer)
for _, player in ipairs(Players:GetPlayers()) do setupPlayer(player) end
Players.PlayerRemoving:Connect(function(player) inRound[player] = nil end)

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
 local level = math.clamp(math.floor(tonumber(requestedLevel) or 1), 1, 2)
 if worldReady and activeLevel == level then return true end
 activeLevel = level
 workspace:SetAttribute("SelectedLevel", level)
 workspace:SetAttribute("WorldGenerated", false)
 if level == 2 then
  workspace:SetAttribute("LoadStage", "ENTERING_DRY_POOLROOMS")
  local ok, err = pcall(function()
   require(script.Parent:WaitForChild("Level2Generator")).Build()
  end)
  if not ok then
   warn("GameManager: Level 2 generation failed: " .. tostring(err))
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
 entityStart = workspace:WaitForChild("EntityStart", 30)
 entity = level == 1 and workspace:WaitForChild("Entity", 30) or nil
 worldReady = elevatorApi ~= nil and mazeStart ~= nil
 workspace:SetAttribute("LoadStage", worldReady and "READY" or "WORLD_ERROR")
 return worldReady
end
local function returnGroupToLobby(group)
	-- LEVEL2 ROUND CLEANUP: restore the persistent lobby and release generated geometry.
	if activeLevel == 2 then
		Players.CharacterAutoLoads = true
		local ok, err = pcall(function() require(script.Parent:WaitForChild("Level2Generator")).Cleanup() end)
		if not ok then warn("[GameManager] Level 2 cleanup failed:", err) end
		worldReady = false
		activeLevel = 1
		elevatorApi, mazeStart, entityStart, entity = nil, nil, nil, nil
	end
 local live = {}
 for _, player in ipairs(group) do
  if player.Parent then live[#live + 1] = player end
 end

 -- Completed private rounds return to ordinary public matchmaking. If Roblox
 -- rejects a teleport, the local lobby remains a safe fallback.
 if IS_RESERVED_ROUND_SERVER and not IS_STUDIO and #live > 0 then
  local options = Instance.new("TeleportOptions")
  options:SetTeleportData({ReturnToLobby = true})
  local ok, err = pcall(function()
   TeleportService:TeleportAsync(game.PlaceId, live, options)
  end)
  if ok then return end
  warn("GameManager: return-to-lobby teleport failed: " .. tostring(err))
 end

 for _, player in ipairs(live) do
  inRound[player] = nil
  player:SetAttribute("InRound", false)
  player:SetAttribute("Escaped", nil)
  loadLobbyCharacter(player)
  status:FireClient(player, "lobby")
 end
end

local function playRound(participants)
	if activeLevel == 2 then Players.CharacterAutoLoads = false end
 local alive = {}
 local aliveCount = 0
 local conns = {}
 for _, player in ipairs(participants) do
  local char = player.Parent and player.Character
  local hum = char and char:FindFirstChildOfClass("Humanoid")
  local root = char and char:FindFirstChild("HumanoidRootPart")
  if hum and hum.Health > 0 and root then
   alive[player] = true
   aliveCount += 1
  end
 end

 if entity and entity.PrimaryPart and entityStart then
  local bbox, size = entity:GetBoundingBox()
  local pivot = entity:GetPivot()
  local bottomToPivot = pivot.Y - (bbox.Y - size.Y / 2)
  entity:PivotTo(CFrame.new(entityStart.CFrame.X, 0.5 + bottomToPivot, entityStart.CFrame.Z))
 end

 for _, player in ipairs(participants) do
  local hum = player.Character and player.Character:FindFirstChildOfClass("Humanoid")
  if hum then
   conns[#conns + 1] = hum.Died:Connect(function()
    if alive[player] then
     alive[player] = nil
     aliveCount -= 1
     local root = player.Character and player.Character:FindFirstChild("HumanoidRootPart")
     fireGroup(participants, "death", player.Name, root and root.Position or nil)
    end
   end)
  end
 end
 conns[#conns + 1] = Players.PlayerRemoving:Connect(function(player)
  if alive[player] then alive[player] = nil; aliveCount -= 1 end
 end)

 local function sendWipedPartyHome()
  workspace:SetAttribute("RoundActive", false)
  for _, connection in ipairs(conns) do connection:Disconnect() end
  fireGroup(participants, "lose", 0, 0, #participants)
  task.wait(5)
  elevatorApi.close()
  returnGroupToLobby(participants)
  task.wait(1.6)
 end

 if aliveCount <= 0 then sendWipedPartyHome(); return end
 if activeLevel == 2 then
  fireGroup(participants, "poolaccess")
  task.wait(1.25)
 else
  for t = ELEVATOR_TIME, 1, -1 do
   if aliveCount <= 0 then sendWipedPartyHome(); return end
   fireGroup(participants, "elevator", t)
   task.wait(t == 8 and 2 or 1)
  end
  elevatorApi.open()
 end
 workspace:SetAttribute("PuzzleWon", false)
 workspace:SetAttribute("RoundActive", true)
 local roundStartedAt = os.clock()
 fireGroup(participants, "start")

 local result
 while true do
  if workspace:GetAttribute("PuzzleWon") then result = "win" break end
  if aliveCount <= 0 then result = "lose" break end
  local anyEscaped, anyInside = false, false
  for player in pairs(alive) do
   if player:GetAttribute("Escaped") == true then anyEscaped = true else anyInside = true end
  end
  if anyEscaped and not anyInside then result = "win" break end
  task.wait(0.5)
 end

 workspace:SetAttribute("RoundActive", false)
 workspace:SetAttribute("LightMode", "NORMAL")
 workspace:SetAttribute("FlickerBoost", 0)
 workspace:SetAttribute("EntitySpeedMul", 1)
 for _, connection in ipairs(conns) do connection:Disconnect() end

 -- Send consistent end-of-round statistics to every party member so the client
 -- can present the escape as a real payoff instead of a one-line notification.
 local elapsed = math.max(0, os.clock() - roundStartedAt)
 local escapedCount = 0
 for _, participant in ipairs(participants) do
  if participant.Parent and participant:GetAttribute("Escaped") == true then
   escapedCount += 1
  end
 end
 fireGroup(participants, result, elapsed, escapedCount, #participants)
 task.wait(5.5)
 elevatorApi.close()
 returnGroupToLobby(participants)
 task.wait(1.6)
end

-- Launch one station. Published servers teleport the selected group into a fresh
-- reserved server. Studio cannot test TeleportService, so it runs the same party
-- locally as a practical editor-only fallback.
local function launchStation(station, participants)
 station.busy = true
 setStationDisplay(station, "STARTING PRIVATE WORLD", #participants .. "/" .. (station.maxPlayers or MAX_PLAYERS_PER_STATION) .. " PLAYERS", station.color)
 fireGroup(participants, "loadinggame")

 if IS_STUDIO then
  if roundBusy then
   setStationDisplay(station, "STUDIO WORLD BUSY", "WAIT FOR THE ACTIVE TEST", Color3.fromRGB(255, 210, 90))
   task.wait(2)
   station.busy = false
   return
  end

  roundBusy = true
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
 options.ShouldReserveServer = true
 options:SetTeleportData({
  BackroomsRound = true,
  PartySize = #participants,
  Station = station.index,
   Level = station.level or 1,
  LaunchToken = game.JobId .. ":" .. station.index .. ":" .. math.floor(os.clock() * 1000),
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
  local selectedLevel = math.clamp(math.floor(tonumber(data and data.Level) or 1), 1, 2)
  local expected = math.clamp(tonumber(data and data.PartySize) or 1, 1, MAX_PLAYERS_PER_STATION)
  local partyDeadline = os.clock() + 12
  while #Players:GetPlayers() < expected and os.clock() < partyDeadline do task.wait(0.2) end

  local participants = Players:GetPlayers()
  table.sort(participants, function(a, b) return a.UserId < b.UserId end)
  while #participants > MAX_PLAYERS_PER_STATION do table.remove(participants) end
  if #participants == 0 then return end

  roundBusy = true
  for _, player in ipairs(participants) do
   inRound[player] = true
   player:SetAttribute("InRound", true)
   player:SetAttribute("Escaped", nil)
  end
  fireGroup(participants, "loadinggame")

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
