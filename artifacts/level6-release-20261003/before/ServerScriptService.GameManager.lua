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
local MemoryStoreService = game:GetService("MemoryStoreService")
local DevAccess = require(RS:WaitForChild("DevAccess"))
-- DEATH_CAUSE_20260921. The kill sites mark the player; this file reads the mark
-- in hum.Died and appends the key to the "death"/"partydown" payloads the
-- clients already receive. Never invents a cause: an unmarked or stale death is
-- DeathAdvice.Unknown and the card says so.
local DeathAdvice = require(RS:WaitForChild("DeathAdvice"))
local PlayerProtection = require(script.Parent:WaitForChild("PlayerProtection"))
local ReentryPlacement = require(script.Parent:WaitForChild("ReentryPlacement"))

-- Every rule about what a finished level leads to, who the destination is still
-- waiting for and who owns an unfinished transfer lives in ONE module. The
-- completion path below calls Routing.* on every win; nothing here used to
-- require it, so every win could error. The numbers the module owns were also
-- duplicated as locals further down, so a suite could pass against one value
-- while production ran another.
local Routing = require(script.Parent:WaitForChild("Round Completion Routing"))
local Loading = require(script.Parent:WaitForChild("Round Loading Runtime"))
local Level3KitWarmup = require(script.Parent:WaitForChild("Level 3 Kit Warmup"))
-- Session-owned Blender meshes warm once in the background; Level 1/2 boot and
-- round deadlines do not wait for this job.
Level3KitWarmup.Start()
-- FRIEND_BOOST_20260916. The module owns the friendship cache and the two lobby
-- attributes; GameManager only tells it when a party launches and hands it the
-- round roster at completion. Start() connects PlayerAdded/PlayerRemoving and
-- runs its first pass in the background, so it never delays boot.
local FriendBoost = require(script.Parent:WaitForChild("FriendBoost"))
FriendBoost.Start()
-- ANALYTICS_20260921. Measurement only: every entry point is a pcall boundary
-- inside the module and none of them yield, so no call here can affect a round.
-- Install ZyntraAnalytics in Studio before pushing GameManager to a place
-- that lacks it -- this WaitForChild has no timeout, exactly like FriendBoost's.
local Analytics = require(script.Parent:WaitForChild("ZyntraAnalytics"))
local activeEntry, loadingRuntime, recoverFailedEntry, cleanupActiveWorld
local failedReservedEntry = false
local characterLoadOwner = {}
local loadingFailures = {}
local destinationArrivalEvidence = {}
workspace:SetAttribute("RoundLoadingRuntimeVersion", Loading.Version)
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
workspace:SetAttribute("Level1BlenderPreviewActive", false)

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
 [4] = "Level4RoundGenerator",
}

-- Rounds stop at Routing.MaxLevel for everyone. Level 4 "Den Sidste
-- Forestilling" (the cinema) is a round for developers only until
-- LEVEL4_PUBLIC is flipped: every member of the party must hold DevAccess.
local LEVEL4_PUBLIC = false

local function groupIsDevelopers(group)
 local any = false
 for _, player in ipairs(group or {}) do
  if typeof(player) == "Instance" and player:IsA("Player") then
   if not DevAccess.IsAllowed(player) then return false end
   any = true
  end
 end
 return any
end

local function devCeiling(group)
 if LEVEL4_PUBLIC or groupIsDevelopers(group) then return Routing.DevMaxLevel end
 return Routing.MaxLevel
end

local function canAccessLevel(requestedLevel, group)
 local level = tonumber(requestedLevel)
 if not level or level ~= level or level % 1 ~= 0 or level < 1 then return false end
 if level <= Routing.MaxLevel then return true end
 return level <= devCeiling(group)
end

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

-- QUEUE_BARRIER_20260914 (card 76). A full party's circle grows a visible wall
-- that non-members collide with. Accepted members' character parts move to
-- QueueMember, which does not collide with QueueBarrier, so they can still
-- leave and come back; the wall disappears the moment capacity frees. The
-- Heartbeat push-out further down stays the authority; the wall is the cue.
local QUEUE_BARRIER_GROUP = "QueueBarrier"
local QUEUE_MEMBER_GROUP = "QueueMember"
pcall(function() PhysicsService:RegisterCollisionGroup(QUEUE_BARRIER_GROUP) end)
pcall(function() PhysicsService:RegisterCollisionGroup(QUEUE_MEMBER_GROUP) end)
for _, pair in ipairs({
 {QUEUE_BARRIER_GROUP, QUEUE_MEMBER_GROUP},
 {QUEUE_BARRIER_GROUP, NOCLIP_GROUP},
 {QUEUE_MEMBER_GROUP, NOCLIP_GROUP},
}) do
 pcall(function() PhysicsService:CollisionGroupSetCollidable(pair[1], pair[2], false) end)
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

-- DEV_FREE_RESPAWN_20260914 (card 64). One request at a time per developer;
-- the shared server-only re-entry endpoint owns membership, death and
-- placement. Free mode never enters Monetization or reserves a credit.
local devRespawnRequests = {}
local function requestDevRespawn(player)
 if not DevAccess.IsAllowed(player) or player.Parent ~= Players or devRespawnRequests[player] then return end
 local request = {}
 devRespawnRequests[player] = request
 player:SetAttribute("DevRespawnBusy", true)
 local ok, accepted, reason = pcall(zyntraReentry.Invoke, zyntraReentry, player, true)
 if devRespawnRequests[player] ~= request then return end
 devRespawnRequests[player] = nil
 if player.Parent ~= Players then return end
 player:SetAttribute("DevRespawnBusy", nil)
 player:SetAttribute("DevRespawnStatus",
  ok and accepted == true and "RESPAWNED" or (ok and tostring(reason or "FAILED") or "UNAVAILABLE"))
 player:SetAttribute("DevRespawnSerial", (tonumber(player:GetAttribute("DevRespawnSerial")) or 0) + 1)
end

-- CHALLENGES_20260923 (Trello FnF49TWk): set by any developer command that
-- changes a round, so a run it touched is never a record or a challenge.
-- playRound clears it when a round opens and folds in whatever developer
-- state is already standing then (paused entities, noclip, tuning overrides).
local runDevTouched = false

devControl.OnServerEvent:Connect(function(player, command, enabled)
 if not DevAccess.IsAllowed(player) then return end
 if type(command) ~= "string" or type(enabled) ~= "boolean" then return end
 if not allowDevControl(player) then return end
 if command ~= "fastQueue" and command ~= "playerEsp" then runDevTouched = true end
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
 elseif command == "playerEsp" then
  -- DEV_PLAYER_ESP_20260914 (card 45): on-demand readback for THIS developer
  -- only. Server positions also cover characters outside the requesting
  -- client's streaming region. Nothing is broadcast and nothing is stored.
  if not enabled then return end
  local snapshot = {At = workspace:GetServerTimeNow(), Players = {}}
  for _, subject in ipairs(Players:GetPlayers()) do
   local character = subject.Character
   local root = character and character:FindFirstChild("HumanoidRootPart")
   local humanoid = character and character:FindFirstChildOfClass("Humanoid")
   if root and root:IsA("BasePart") and character:IsDescendantOf(workspace) then
    snapshot.Players[#snapshot.Players + 1] = {
     UserId = subject.UserId, Position = root.Position,
     Alive = humanoid ~= nil and humanoid.Health > 0,
    }
   end
  end
  devControl:FireClient(player, "playerEsp", snapshot)
 elseif command == "freeRespawn" then
  if enabled then requestDevRespawn(player) end
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
  runDevTouched = true
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
local characterLoads = Loading.NewCharacterGate(task.wait)

local function beginCharacterLoad(allowed)
 return characterLoads:Acquire(allowed)
end

local function finishCharacterLoad(token)
 characterLoads:Release(token)
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
 local loadToken = beginCharacterLoad(function() return player.Parent == Players and not inRound[player] end)
 if not loadToken then return false end
 if not (player.Parent and not inRound[player]) then
   finishCharacterLoad(loadToken)
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
 finishCharacterLoad(loadToken)
 if not ok then warn("[GameManager] Lobby character load failed:", err) end
 return ok
end

local function loadGameplayCharacter(player, allowed, loadRecord)
 local loadToken = beginCharacterLoad(allowed)
 if not loadToken then return false end
 local previous = player.Character
 local ok, err = pcall(player.LoadCharacterAsync, player)
 -- Record this load before releasing the gate, even if its body is incomplete.
 -- A re-entry refusal may discard only this still-current owned Character.
 if loadRecord and player.Character ~= previous then loadRecord.Character = player.Character end
 finishCharacterLoad(loadToken)
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
-- The entry runtime owns the actual sixty-second deadline, INCLUDING this
-- serialized engine call. A timed-out caller never frees another worker's lock.
local CHARACTER_LOAD_ATTEMPTS = 4
local CHARACTER_LOAD_TIMEOUT = 6

local function spawnGameplayCharacter(player, attempt, lifecycleOpen, loadRecord)
 local function allowed()
  return player.Parent == Players and (not attempt or attempt:IsOpen())
   and (not lifecycleOpen or lifecycleOpen())
 end
 for attempt = 1, CHARACTER_LOAD_ATTEMPTS do
  if not allowed() then return nil end
  local previous = player.Character
  local loaded = loadGameplayCharacter(player, allowed, loadRecord)
  local waited = 0
  while allowed() and waited < CHARACTER_LOAD_TIMEOUT do
   local character = player.Character
   local humanoid = character and character:FindFirstChildOfClass("Humanoid")
   local root = character and character:FindFirstChild("HumanoidRootPart")
   if loaded and character and character ~= previous and character.Parent and humanoid
    and humanoid.Health > 0 and root then return character end
   waited += task.wait()
  end
  warn(string.format("[GameManager] No gameplay character for %s (attempt %d/%d)",
   player.Name, attempt, CHARACTER_LOAD_ATTEMPTS))
 end
 return nil
end

local function buildLobby()
 local lobby, spawn, stations = require(script.Parent:WaitForChild("TunnelLobbyBuilder")).Build(LOBBY_CENTER)
 if IS_RESERVED_ROUND_SERVER then return lobby, spawn, stations end
 -- Preserve the canonical pad/reference used by every join, reset and preview return.
 -- No lobby character is loaded until this synchronous startup wrapper returns.
 workspace:SetAttribute("LobbySpawnMigrationReady", false)
 workspace:SetAttribute("LobbySpawnMigrationError", nil)
 local originalSpawn = spawn.CFrame
 local ok, problem = pcall(function()
  local folder = script.Parent:FindFirstChild("LobbyReimaginedPreview")
  local builder = folder and folder:FindFirstChild("Builder")
  assert(builder and builder:IsA("ModuleScript"), "Revised lobby builder is missing")
  -- The original builder starts its shop asynchronously. The clone must wait
  -- for its existing completion marker, not merely the early-parented Model.
  local shop, deadline = nil, os.clock() + 20
  repeat
   shop = lobby:FindFirstChild("ZyntraShopDisplay")
   if shop and shop:IsA("Model") and (tonumber(shop:GetAttribute("ShopItemCount")) or 0) > 0 then break end
   assert(lobby.Parent == workspace, "Lobby changed while waiting for its shop")
   task.wait(.05)
  until os.clock() >= deadline
  assert(shop and shop:IsA("Model") and (tonumber(shop:GetAttribute("ShopItemCount")) or 0) > 0,
   "Original lobby shop did not finish before revised lobby startup")
  local revised = require(builder).Build()
  assert(revised and revised:IsA("Model") and revised.Parent == workspace
   and revised.Name == "LobbyReimaginedPreview" and revised:GetAttribute("LobbyReimaginedOwned") == true
   and revised:GetAttribute("Ready") == true, "Revised lobby is not ready")
  local center = revised:GetAttribute("PreviewCenter")
  assert(center == Vector3.new(220, 30, -760), "Unexpected revised lobby center")
  local position = center + Vector3.new(0, .4, -100)
  local params = RaycastParams.new()
  params.FilterType = Enum.RaycastFilterType.Include
  params.FilterDescendantsInstances = {revised}
  params.RespectCanCollide = true
  -- Cover every possible scatter offset; fail safely before moving the pad.
  for _, dx in ipairs({-2, 0, 2}) do
   for _, dz in ipairs({-2, 0, 2}) do
    local hit = workspace:Raycast(position + Vector3.new(dx, 12, dz), Vector3.new(0, -18, 0), params)
    assert(hit and hit.Instance.CanCollide and hit.Normal.Y > .7
     and math.abs(hit.Position.Y - position.Y) < 2, "Revised lobby spawn floor is incomplete")
   end
  end
  assert(spawn.Parent == lobby and lobby.Parent == workspace, "Canonical lobby spawn changed during startup")
  spawn.CFrame = CFrame.lookAt(position, center + Vector3.new(0, .4, 0))
  spawn:SetAttribute("LobbySpawnFloorModelName", "LobbyReimaginedPreview")
  spawn:SetAttribute("LobbySpawnRevision", 4)
  workspace:SetAttribute("LobbySpawnMigrationReady", true)
 end)
 if not ok then
  spawn.CFrame = originalSpawn
  spawn:SetAttribute("LobbySpawnFloorModelName", nil)
  spawn:SetAttribute("LobbySpawnRevision", nil)
  workspace:SetAttribute("LobbySpawnMigrationError", tostring(problem))
  warn("[GameManager] Revised lobby startup failed; retaining safe original spawn: " .. tostring(problem))
 end
 return lobby, spawn, stations
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
 local cinema = workspace:FindFirstChild("Level 4 Cinema Blender")
 if (cinema and cinema:FindFirstChild("Level 4 Round Runtime") ~= nil)
  or (workspace:FindFirstChild("ElevatorSpawn") and workspace.ElevatorSpawn:GetAttribute("Level4_CompatibilityMarker") == true)
  or selected == 4 then
  stale[#stale + 1] = 4
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

-- Workspace.Entity is saved with the place, and EntityAI, EntityKill and
-- EntityAnimation take it at server start with no round gate -- so the Level 1
-- entity stood in every lobby, able to see, howl and kill on touch. Outside a
-- Level 1 world it lives in ServerStorage with those three scripts disabled,
-- the way the Level 2/3 adapters isolate it for their own rounds; ensureWorld
-- brings it back before GenerateWorld. Disabling a Script also stops one that
-- started before this ran, and re-enabling restarts it clean -- the one-shot
-- re-arm cleanupLevelOneWorld used to do for EntityAI by hand.
local LEVEL_ONE_ENTITY_SCRIPTS = {"EntityAI", "EntityAnimation", "EntityKill"}
local STORED_LEVEL_ONE_ENTITY_NAME = "Lobby Stored Level 1 Entity"

local function setLevelOneEntityActive(active)
 if not active then
  -- Deferred ancestry/Enabled signals cannot release tracks once their Script
  -- is disabled. Dispose this controller synchronously before parking it.
  local animationScript = script.Parent:FindFirstChild("EntityAnimation", true)
  local release = animationScript and animationScript:FindFirstChild("ReleaseAnimations")
  if animationScript and animationScript:IsA("BaseScript") and animationScript.Enabled
   and release and release:IsA("BindableFunction") and release:GetAttribute("OwnerSystem") == "Level1EntityAnimation" then
   local ok, err = pcall(function() release:Invoke() end)
   if not ok then warn("[GameManager] Level 1 animation release failed: " .. tostring(err)) end
  end
 end
 local entity = active and ServerStorage:FindFirstChild(STORED_LEVEL_ONE_ENTITY_NAME)
  or workspace:FindFirstChild("Entity")
 if entity then
  -- Its Studio spot has no floor under it. Anchored, it cannot fall while
  -- EntityAI is off; EntityAI releases it once the maze floor exists.
  local root = entity:FindFirstChild("HumanoidRootPart")
  if root then root.Anchored = true end
  entity.Name = active and "Entity" or STORED_LEVEL_ONE_ENTITY_NAME
  entity.Parent = active and workspace or ServerStorage
 end
 for _, name in ipairs(LEVEL_ONE_ENTITY_SCRIPTS) do
  local object = script.Parent:FindFirstChild(name, true)
  if object and object:IsA("BaseScript") then object.Enabled = active end
 end
end

sanitizePersistedLevelState()
setLevelOneEntityActive(false)
local _lobbyModel, lobbySpawn, lobbyStations = buildLobby()

local function setStationDisplay(station, main, secondary, color)
 -- R3 holograms mirror this engine's true host/reset/launch state only.
 if station.revisionOwned and station.renderOwner and station.renderOwner.Parent then
  station.renderOwner:SetAttribute("QueueActive", station.host ~= nil and (not station.busy or station.previewQueue == true) and not station.revisionRetired)
 end
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

-- Choose against actual characters immediately before PivotTo, without yielding.
-- This also leaves a returning player a free space when a teammate camps spawn.
local function arrivalPointFree(player, position)
 for _, other in ipairs(Players:GetPlayers()) do
  if other ~= player then
   local character = other.Character
   local otherRoot = character and character:FindFirstChild("HumanoidRootPart")
   if otherRoot then
    local offset = otherRoot.Position - position
    if math.abs(offset.Y) < 6 and Vector2.new(offset.X, offset.Z).Magnitude < 3.9 then
     return false
    end
   end
  end
 end
 return true
end

local function freeElevatorFrame(player, pad)
 local levelOne = pad:GetAttribute("Level2_CompatibilityMarker") ~= true
  and pad:GetAttribute("Level3_CompatibilityMarker") ~= true
  and pad:GetAttribute("Level4_CompatibilityMarker") ~= true
 local forward = levelOne and Vector3.xAxis or pad.CFrame.LookVector
 local side = levelOne and Vector3.zAxis or pad.CFrame.RightVector
 local depth = pad.Size.X + 3 -- Level 1's emergency pad is 3 studs shorter than its floor.
 local rows = levelOne and math.max(1, math.floor((depth - 6) / 4) + 1) or 7
 for row = 0, rows - 1 do
  for column = 0, (levelOne and 1 or 3) do
   local across = (column % 2 == 0 and -1 or 1) * (2 + math.floor(column / 2) * 4)
   local along = levelOne and (depth / 2 - 3 - row * 4) or row * 4
   local position = pad.Position + side * across + forward * along + Vector3.new(0, 4, 0)
   if arrivalPointFree(player, position) then
    return CFrame.lookAt(position, position + forward)
   end
  end
 end
 return nil
end

local function placeSafelyInElevator(player, char)
 local entry = activeEntry
 local pad = workspace:FindFirstChild("ElevatorSpawn")
 local root = char and char:WaitForChild("HumanoidRootPart", 8)
 local hum = char and char:FindFirstChildOfClass("Humanoid")
 if player.Character ~= char or (entry and (activeEntry ~= entry or entry.State == "failed")) then return false end
 if not (pad and root and hum and hum.Health > 0) then return false end

 -- The lobby and maze are far apart. Keep the character server-anchored while
 -- the client streams the elevator region so it cannot fall through an unloaded floor.
 pad.CanCollide = true -- invisible emergency floor inside the cabin
 local target = freeElevatorFrame(player, pad)
 if not target then return false end
 root.Anchored = true
 root.AssemblyLinearVelocity = Vector3.zero
 root.AssemblyAngularVelocity = Vector3.zero
 char:PivotTo(target * root.CFrame:ToObjectSpace(char:GetPivot()))
 local streamed = beginStreamAround(player, target.Position, STREAM_AROUND_TIMEOUT)

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
  while entry and entry.State == "loading" do task.wait(.1) end
  if player.Character ~= char or (entry and (activeEntry ~= entry or entry.State == "failed")) then return end
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
local pendingReentryPlacement = {}

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

local function levelThreeSlideResume(player)
 local world = workspace:FindFirstChild("Level 3 Generated World")
 if not world then return nil end
 for _, object in ipairs(world:GetDescendants()) do
  if object:GetAttribute("Level3_Level2ExitTube") == true then
   local position = object:GetAttribute("Level3_SlideResumePosition")
   local tangent = object:GetAttribute("Level3_SlideResumeTangent")
   local velocity = object:GetAttribute("Level3_SlideResumeVelocity")
   if typeof(position) == "Vector3" and typeof(tangent) == "Vector3"
    and typeof(velocity) == "Vector3" and tangent.Magnitude > .1 then
    local mouth = object:GetAttribute("Level3_SlideMouthPosition")
    local length = object:GetAttribute("Level3_SlideLength")
    local rise = object:GetAttribute("Level3_SlideRise")
    if typeof(mouth) ~= "Vector3" or type(length) ~= "number" or length <= 0
     or type(rise) ~= "number" then return nil end
    local startAlpha = (mouth.X - position.X) / length
    for slot = 0, MAX_PLAYERS_PER_STATION - 1 do
     -- Keep each successive actual-root placement farther UP the same bore.
     -- The rear reserve prevents any candidate from crossing its physical cap.
     local alpha = startAlpha + slot * 12 / length
     if alpha <= .025 or (1 - alpha) * length < 12 then break end
     local point = Vector3.new(mouth.X - length * alpha, mouth.Y + rise * alpha * alpha, mouth.Z)
     if arrivalPointFree(player, point) then
      local direction = Vector3.new(length, -2 * rise * alpha, 0).Unit
      return {Position = point, Tangent = direction, Velocity = direction * velocity.Magnitude}
     end
    end
    return nil
   end
   return nil
  end
 end
 return nil
end

local function placeAtLevelThreeSlideResume(player, char)
 local entry = activeEntry
 local root = char and char:WaitForChild("HumanoidRootPart", 8)
 local hum = char and char:FindFirstChildOfClass("Humanoid")
 if player.Character ~= char or (entry and (activeEntry ~= entry or entry.State == "failed")) then return false end
 if not (root and hum and hum.Health > 0) then return false end

 local resume = levelThreeSlideResume(player)
 if not resume then return false end

 root.Anchored = true
 root.AssemblyLinearVelocity = Vector3.zero
 root.AssemblyAngularVelocity = Vector3.zero
 local target = CFrame.lookAt(resume.Position, resume.Position + resume.Tangent)
 char:PivotTo(target * root.CFrame:ToObjectSpace(char:GetPivot()))
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
		if player.Character ~= char or (entry and (activeEntry ~= entry or entry.State == "failed")) then return false end
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
				if not placeSafelyInElevator(player, char) and player.Character == char then
					root.Anchored = false
					hum.Health = 0
				end
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
			if entry and (activeEntry ~= entry or entry.State ~= "ready") then return end
			task.spawn(function() release(false) end)
		end
	end)
	return true
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
  if player.Character ~= char then return end
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
  if player.Character ~= char then return end
  local owner = characterLoadOwner[player]
  if (owner and owner.State == "failed") or (failedReservedEntry and loadingFailures[player]) then
   local root = char:FindFirstChild("HumanoidRootPart")
   if root then root.Anchored = true end
   return
  end
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
   if pendingReentryPlacement[player] then return end
   local pending = pendingExplicitPlacement[player]
   if worldReady and pending ~= true and pending ~= char then
    if not placeSafelyInElevator(player, char) and player.Character == char then
     local humanoid = char:FindFirstChildOfClass("Humanoid")
     if humanoid then humanoid.Health = 0 end
    end
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
 Analytics.Join(player)
 inRound[player] = nil
 player:SetAttribute("InRound", false)
 player:SetAttribute("Escaped", nil)
 player:SetAttribute("Level2_ExitTransition", nil)
 player:SetAttribute("GlowstickSlot", nil)
 player:SetAttribute("GlowstickColor", nil)
 local joined, joinData = pcall(function() return player:GetJoinData() end)
 local packet = joined and joinData and joinData.TeleportData
 if IS_RESERVED_ROUND_SERVER then
  -- PlayerAdded can be followed by PlayerRemoving before the admission loop's
  -- next poll. Retain its own packet as arrival evidence; current presence is
  -- still measured independently, so an old Player instance cannot count twice.
  destinationArrivalEvidence[#destinationArrivalEvidence + 1] = {Member = player, Data = packet}
 end
 if type(packet) == "table" and packet.ReturnToLobby == true
  and type(packet.LoadingError) == "string" then
  player:SetAttribute("RoundLoadingError", packet.LoadingError == "LOADING_TIMEOUT" and "timeout" or "failed")
 end
 -- RETRY_GUIDE_REMOVED_20260922 (owner instruction): a non-escaped return no
 -- longer draws a TRY AGAIN guide, so a RetryLevel in an old lobby packet is
 -- read by nobody -- neither here nor as a player attribute.
 player.CharacterAdded:Connect(function(char) onCharacter(player, char) end)
 task.defer(function()
  if not player.Parent then return end
  if failedReservedEntry then
   status:FireClient(player, "loadfailed", "LOADING_TIMEOUT")
   if recoverFailedEntry then recoverFailedEntry(nil, "LOADING_TIMEOUT", {player}) end
   return
  end
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
 devRespawnRequests[player] = nil
 player:SetAttribute("DevPushImmune", nil)
end)

local function queueRadius(station)
 local zone = station.zone
 if zone:GetAttribute("QueueDetectorShape") == "Circle" then
  local radius = tonumber(zone:GetAttribute("QueueRadius"))
  if radius and radius > 0 and radius == radius then
   return math.min(radius, zone.Size.X * .5, zone.Size.Z * .5)
  end
 end
 return nil
end

-- R4-owned preview queues share the existing station engine. Production
-- routing and the original lobby remain untouched.
local function revisedQueueBridge()
 local folder = script.Parent:FindFirstChild("LobbyReimaginedPreview")
 local module = folder and folder:FindFirstChild("QueueBridge")
 return module and module:IsA("ModuleScript") and require(module) or nil
end

-- LEVEL4_QUEUE_CHOICE_20261002 (owner decision): the new lobby's Level 4 bays (revised-lobby ids 113-116, every
-- level above 3 is previewOnly in QueueBridge) let the host choose the launch: "trial" = the real Level 4 round
-- ("Den Sidste Forestilling", the normal round path: canAccessLevel / devCeiling, reserved server in production) or
-- "preview" = the developer map preview with no entity (QueueBridge -> Level4V4PreviewAccess). Both stay DevAccess-
-- only. The choice flips station.previewQueue for one hosted session; resetStation restores it from previewOnly.
local function isLevel4Choice(station)
 return station.revisionOwned == true and station.previewOnly == true and station.level == 4
end

-- the launches this player may host on a choice bay, in display order ("trial", "preview"); nil elsewhere
local function level4ChoiceModes(station, player)
 if not isLevel4Choice(station) then return nil end
 local modes = {}
 if canAccessLevel(station.level, {player}) then modes[#modes + 1] = "trial" end
 local bridge = revisedQueueBridge()
 if station.previewQueue and bridge and bridge.AllowsPreview(station, player) then modes[#modes + 1] = "preview" end
 return modes
end

local function revisedQueueIdleSubtitle(station)
 if isLevel4Choice(station) and not station.launchMode then
  local bridge = revisedQueueBridge()
  if bridge and bridge.IsPreviewPreparing and bridge.IsPreviewPreparing(station) then
   return "PREPARING PREVIEW WORLD  •  PLEASE WAIT"
  end
  return "TRIAL ROUND OR MAP PREVIEW  •  DEV ACCESS"
 end
 if not station.previewQueue then return "ENTER TO HOST  •  CHOOSE 1-6 PLAYERS" end
 local bridge = revisedQueueBridge()
 if bridge and bridge.IsPreviewPreparing and bridge.IsPreviewPreparing(station) then
  return "PREPARING PREVIEW WORLD  •  PLEASE WAIT"
 end
 return "DEV PARTY QUEUE  •  AUTHORIZED ACCESS"
end

local function playerInsideZone(player, station, includeBusy)
 -- Public revision queues stay open; both unfinished bays require real DEV authorization.
 if station.revisionOwned and station.level >= 5 and not DevAccess.IsLevel6PreviewAllowed(player) then return false end
 if station.previewQueue then
  local bridge = revisedQueueBridge()
  if not (bridge and bridge.AllowsPreview(station, player))
   and not (isLevel4Choice(station) and not station.launchMode and canAccessLevel(station.level, {player})) then
   return false
  end
 elseif station.level > Routing.MaxLevel and not canAccessLevel(station.level, {player}) then return false end
 if inRound[player] or (station.busy and not includeBusy) then return false end
 local char = player.Character
 local hum = char and char:FindFirstChildOfClass("Humanoid")
 local root = char and char:FindFirstChild("HumanoidRootPart")
 if player.Parent ~= Players or not (char and char.Parent and hum and hum.Health > 0
  and root and root:IsA("BasePart")) then return false end
 local zone = station.zone
 if not zone or not zone.Parent then return false end
 local p = zone.CFrame:PointToObjectSpace(root.Position)
 local radius = queueRadius(station)
 local inside = if radius then p.X * p.X + p.Z * p.Z <= radius * radius
  else math.abs(p.X) <= zone.Size.X * .5 and math.abs(p.Z) <= zone.Size.Z * .5
 return inside and p.Y > -6 and p.Y < 12
end

local function rawQueuedPlayers(station, includeBusy)
 local result = {}
 local insideNow = {}
 station.entrySeen = station.entrySeen or {}
 station.entryCharacters = station.entryCharacters or {}
 for _, player in ipairs(Players:GetPlayers()) do
  if playerInsideZone(player, station, includeBusy) then
   insideNow[player] = true
   if station.entrySeen[player] == nil or station.entryCharacters[player] ~= player.Character then
    station.entrySeen[player] = os.clock()
    station.entryCharacters[player] = player.Character
   end
   result[#result + 1] = player
  end
 end
 for player in pairs(station.entrySeen) do
  if not insideNow[player] then
   station.entrySeen[player] = nil
   station.entryCharacters[player] = nil
  end
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
 local host, epoch, character = station.host, station.admissionEpoch, player.Character
 local ok, isFriend = pcall(function()
  return player:IsFriendsWith(host.UserId)
 end)
 if station.host ~= host or station.admissionEpoch ~= epoch or station.privacy ~= "friends"
  or station.cancelRequested or player.Parent ~= Players or player.Character ~= character then return false end
 local allowed = ok and isFriend == true
 -- Only a DEFINITIVE answer is worth caching. A throttled or failed web call
 -- returns ok == false, which is indistinguishable here from "not a friend",
 -- and caching that locked a real friend out for the rest of the countdown --
 -- long enough for the party to launch without them. Still fail closed for
 -- this tick; just let the next once-per-second poll retry the call.
 if ok then station.friendCache[player.UserId] = allowed end
 return allowed
end

-- This pass never yields: physical enforcement must not wait for a friends API.
-- Preserve current accepted characters before considering newly arrived users.
local function selectQueuedPlayers(station, raw)
 local accepted, rejected, nextMembers = {}, {}, {}
 if not station.configured or station.cancelRequested or not station.host
  or not table.find(raw, station.host) then
  station.admittedCharacters = nextMembers
  return accepted, raw, rejected
 end
 local function allowed(player)
  return player == station.host or station.privacy == "public"
   or (station.privacy == "friends" and station.friendCache[player.UserId] == true)
 end
 local function admit(player)
  accepted[#accepted + 1] = player
  nextMembers[player] = player.Character
 end
 admit(station.host)
 local previous = station.admittedCharacters or {}
 for _, player in ipairs(raw) do
  if player ~= station.host and previous[player] == player.Character
   and allowed(player) and #accepted < station.maxPlayers then admit(player) end
 end
 for _, player in ipairs(raw) do
  if not nextMembers[player] then
   local permitted = allowed(player)
   if permitted and #accepted < station.maxPlayers then admit(player)
   else rejected[#rejected + 1] = {player=player, reason=permitted and "full" or "private"} end
  end
 end
 station.admittedCharacters = nextMembers
 return accepted, raw, rejected
end

local function queuedPlayers(station)
 local raw = rawQueuedPlayers(station)
 local host, epoch = station.host, station.admissionEpoch
 if station.configured and host and table.find(raw, host) then
  for _, player in ipairs(raw) do
   if player ~= host then stationAllowsPlayer(station, player) end
   if station.host ~= host or station.admissionEpoch ~= epoch or station.cancelRequested then
    return {}, rawQueuedPlayers(station), {}
   end
  end
 end
 -- Friendship can yield. Never commit the old positions, character identities
 -- or occupancy observed before that call.
 return selectQueuedPlayers(station, rawQueuedPlayers(station))
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
local function publishPostWinChoices(session)
 if activePostWin ~= session or session.Aborted then return end
 local members = {}
 for _, member in ipairs(Routing.RosterMembers(session.Roster)) do
  members[#members + 1] = {
   UserId = member.UserId,
   Name = member.Name,
   Choice = Routing.DecisionOf(session.Roster, member),
  }
 end
 session.ChoiceRevision = (session.ChoiceRevision or 0) + 1
 fireGroup(Routing.RosterMembers(session.Roster), "postwinchoices", {
  Serial = session.Serial,
  Revision = session.ChoiceRevision,
  Closed = session.Closed == true,
  Members = members,
 })
end

-- SPECTATOR_COUNT_20260914 (card 73). Each spectator reports who it watches;
-- the watched player is shown only the NUMBER, published as the replicated
-- attribute SpectatorCount on the watched Player. Only a dead or escaped
-- participant may count, and only towards a living participant.
local spectateTargets = {}
local function validSpectatePair(player, target)
 if target == player or player.Parent ~= Players or target.Parent ~= Players
  or inRound[player] ~= true or inRound[target] ~= true
  or target:GetAttribute("Escaped") == true then return false end
 local ownHumanoid = player.Character and player.Character:FindFirstChildOfClass("Humanoid")
 local targetHumanoid = target.Character and target.Character:FindFirstChildOfClass("Humanoid")
 return (player:GetAttribute("Escaped") == true or not ownHumanoid or ownHumanoid.Health <= 0)
  and targetHumanoid ~= nil and targetHumanoid.Health > 0
end
local function republishSpectatorCounts()
 local counts = {}
 for spectator, target in pairs(spectateTargets) do
  if validSpectatePair(spectator, target) then
   counts[target] = (counts[target] or 0) + 1
  else
   spectateTargets[spectator] = nil
  end
 end
 for _, subject in ipairs(Players:GetPlayers()) do
  if subject:GetAttribute("SpectatorCount") ~= counts[subject] then
   subject:SetAttribute("SpectatorCount", counts[subject])
  end
 end
end
local function setSpectateTarget(player, targetUserId)
 local target = nil
 if type(targetUserId) == "number" and targetUserId == targetUserId
  and math.abs(targetUserId) < 2^53 and targetUserId % 1 == 0 then
  -- Studio's actual multiplayer clients have negative UserIds. Resolve the
  -- current roster instead of assuming positive production account ids.
  target = Players:GetPlayerByUserId(targetUserId)
 end
 if target and not validSpectatePair(player, target) then target = nil end
 if spectateTargets[player] == target then return end
 spectateTargets[player] = target
 republishSpectatorCounts()
end
local function clearSpectatorCounts()
 if next(spectateTargets) == nil then return end
 table.clear(spectateTargets)
 republishSpectatorCounts()
end
-- Clear stale reports even when a client stops reporting after its target dies,
-- leaves, escapes, or the spectator respawns. No names are replicated.
task.spawn(function()
 while task.wait(1) do
  if next(spectateTargets) ~= nil then republishSpectatorCounts() end
 end
end)

local lobbyBriefingReady = {}
-- Presentation only: never read these values for movement, battery drain,
-- protection, purchases or rewards. Each field accepts at most five reports/s.
local spectatorVitalReports = setmetatable({}, {__mode = "k"})
local function receiveSpectatorVital(player, payload)
 if type(payload) ~= "table" or inRound[player] ~= true
  or player:GetAttribute("Escaped") == true then return end
 local key, value = payload.Key, payload.Value
 if (key ~= "Stamina" and key ~= "Battery") or type(value) ~= "number"
  or value ~= value or value < 0 or value > 1 then return end
 local hum = player.Character and player.Character:FindFirstChildOfClass("Humanoid")
 if not hum or hum.Health <= 0 then return end
 local reports = spectatorVitalReports[player] or {}
 local now = os.clock()
 if reports[key] and now - reports[key] < .2 then return end
 reports[key] = now
 spectatorVitalReports[player] = reports
 player:SetAttribute("Spectate" .. key, value)
end
local handlePostWinReturnRequest
local handlePostWinContinueRequest
local handleLeaveRoundRequest
status.OnServerEvent:Connect(function(player, message, requestSerial)
  if message == "entryready" and activeEntry then
   if activeEntry:Acknowledge(player, requestSerial) then Analytics.Ready(player, activeLevel) end
 elseif message == "returntolobby" and handlePostWinReturnRequest then
  handlePostWinReturnRequest(player, requestSerial)
 elseif message == "continuenow" and handlePostWinContinueRequest then
  handlePostWinContinueRequest(player, requestSerial)
 elseif message == "leaveround" and handleLeaveRoundRequest then
  handleLeaveRoundRequest(player)
 elseif message == "spectatetarget" then
  setSpectateTarget(player, requestSerial)
 elseif message == "spectatevital" then
  receiveSpectatorVital(player, requestSerial)
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
 Analytics.Leave(player)
 if spectateTargets[player] then spectateTargets[player] = nil; republishSpectatorCounts() end
 pendingExplicitPlacement[player] = nil
 pendingSlideRelease[player] = nil
 pendingSlideStream[player] = nil
 characterLoadOwner[player] = nil
 loadingFailures[player] = nil
 lobbyBriefingReady[player] = nil
 -- The player left, which is what the claim existed to achieve. Resolving it
 -- through Routing -- rather than reaching into the record here -- is what
 -- makes a LATE TeleportInitFailed for the same request a no-op instead of a
 -- second transfer attempt at a ghost.
 Routing.ResolveTransfer(pendingTeleports, player, Routing.Succeeded)
 if activePostWin then
  -- Membership of a result window is FROZEN. A pre-commit disconnect is
  -- gone; an accepted transfer remains part of its destination cohort.
  -- Before commit, a disconnect is not an accepted transfer. Remove its
  -- provisional choice so the final cohort never waits for a disconnected rider.
  if not activePostWin.Closed and not Routing.ClaimOwns(pendingTeleports[player]) then
   Routing.ClearDecision(activePostWin.Roster, player)
  end
  Routing.NoteDeparture(activePostWin.Roster, player)
  publishPostWinChoices(activePostWin)
 end
end)

local function privacyLabel(station)
 return station.privacy == "friends" and "FRIENDS ONLY" or "PUBLIC"
end

queueConfig.OnServerEvent:Connect(function(player, stationIndex, requestedMax, requestedPrivacy, requestedMode)
 if IS_RESERVED_ROUND_SERVER then return end
 stationIndex = math.floor(tonumber(stationIndex) or 0)
 local station = lobbyStations[stationIndex]
 if not station then return end
 local previewCancel = (station.previewQueue == true or station.kitWarming == true)
  and requestedPrivacy == "cancel" and station.host == player
 if station.busy and not previewCancel then return end
 if station.host ~= player or (not station.awaitingConfig and not previewCancel) then return end

 if requestedPrivacy == "cancel" then
  -- The phone close button genuinely leaves the queue instead of only hiding UI.
  station.cancelRequested = true
  station.admissionEpoch = (station.admissionEpoch or 0) + 1
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

 -- a choice bay takes only a launch this host may run right now; an old client (no mode) keeps the preview.
 -- An explicit choice that is no longer available is refused (never swapped for the other launch) and the host's
 -- panel is re-offered what is available now.
 local modes = level4ChoiceModes(station, player)
 if modes then
  local chosen
  if requestedMode == "trial" or requestedMode == "preview" then
   chosen = table.find(modes, requestedMode) and requestedMode
  else
   chosen = (table.find(modes, "preview") and "preview") or modes[1]
  end
  if not chosen then
   status:FireClient(player, "queuehost", station.index, station.maxPlayers, station.privacy,
    #modes > 0 and table.concat(modes, ",") or nil)
   return
  end
  station.launchMode = chosen
  station.previewQueue = chosen ~= "trial"
 end

 station.admissionEpoch = (station.admissionEpoch or 0) + 1
 station.maxPlayers = math.clamp(math.floor(tonumber(requestedMax) or MAX_PLAYERS_PER_STATION), 1, MAX_PLAYERS_PER_STATION)
 station.privacy = requestedPrivacy == "friends" and "friends" or "public"
 station.friendCache = {}
 station.configured = true
 station.awaitingConfig = false
 setStationDisplay(station,
  "STATION " .. (station.displayIndex or station.index) .. "  •  1/" .. station.maxPlayers,
  privacyLabel(station) .. (station.launchMode == "trial" and "  •  TRIAL ROUND"
   or (station.launchMode == "preview" and "  •  MAP PREVIEW" or "")) .. "  •  COUNTDOWN STARTING",
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

local function ensureWorld(group, requestedLevel, attempt)
 if attempt and not attempt:IsOpen() then return false end
 if not canAccessLevel(requestedLevel, group) then return false end
 -- Access was checked for this exact level. The transport ceiling also
 -- includes the standalone public preview without changing the campaign.
 local level = Routing.ClampLevelTo(requestedLevel, devCeiling(group))
 if worldReady and activeLevel == level then return true end
 activeLevel = level
 workspace:SetAttribute("SelectedLevel", level)
 workspace:SetAttribute("WorldGenerated", false)
 local generatorName = LEVEL_GENERATORS[level]
 if generatorName then
  local levelStages = {
   [2] = "ENTERING_DRY_POOLROOMS",
   [3] = "ENTERING_FORGOTTEN_MALL",
   [4] = "ENTERING_LAST_SHOW",
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
  setLevelOneEntityActive(true)
  workspace:SetAttribute("GenerateWorld", true)
  local deadline = os.clock() + 180
  while workspace:GetAttribute("WorldGenerated") ~= true and os.clock() < deadline
   and (not attempt or attempt:IsOpen()) do task.wait(0.25) end
  if workspace:GetAttribute("WorldGenerated") ~= true then
   warn("GameManager: world generation timed out")
   return false
  end
 end
 if attempt and not attempt:IsOpen() then return false end
 elevatorApi = connectElevator()
 mazeStart = workspace:WaitForChild("MazeStart", 30)
 if attempt and not attempt:IsOpen() then return false end
 entityStart = level == 1 and workspace:WaitForChild("EntityStart", 30) or nil
 if attempt and not attempt:IsOpen() then return false end
 entity = level == 1 and workspace:WaitForChild("Entity", 30) or nil
 if attempt and not attempt:IsOpen() then return false end
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
 workspace:SetAttribute("Level1BlenderPreviewActive", false)
 workspace:SetAttribute("Level1BlenderRoomCount", nil)

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
 if generatorScript and generatorScript:IsA("Script") then generatorScript.Disabled = true end
 task.defer(function()
  if generatorScript and generatorScript.Parent then generatorScript.Disabled = false end
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

cleanupActiveWorld = function()
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
	setLevelOneEntityActive(false)
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
		status:FireClient(player, "lobby")
		if loadingFailures[player] then status:FireClient(player, "loadfailed", loadingFailures[player]) end
		-- UI and a usable existing rig recover before another yielding avatar load.
		local character = player.Character
		local root = character and character:FindFirstChild("HumanoidRootPart")
		if root then root.Anchored = false; scatterAt(character, lobbySpawn, false) end
		task.spawn(function() loadLobbyCharacter(player) end)
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
		Data = {ReturnToLobby = true, LoadingError = loadingFailures[live[1]]},
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
			Ceiling = devCeiling(live),
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

-- Failed entry is terminal. The notice/transfer does not wait for a yielding
-- builder or avatar loader. Studio cleanup waits for the builder's ownership to
-- finish so a late Build cannot put a world back over the recovered lobby.
recoverFailedEntry = function(attempt, reason, arrivals)
 local group = arrivals or (IS_RESERVED_ROUND_SERVER and Players:GetPlayers() or attempt.Members)
 if IS_RESERVED_ROUND_SERVER then failedReservedEntry = true end
 workspace:SetAttribute("RoundActive", false)
 workspace:SetAttribute("RoundLoadingState", "failed")
 workspace:SetAttribute("LoadStage", "WORLD_ERROR")
 zyntraReentry.OnInvoke = function() return false end
 for _, player in ipairs(livePlayers(group)) do
  loadingFailures[player] = reason
  player:SetAttribute("RoundLoadingError", reason == "LOADING_TIMEOUT" and "timeout" or "failed")
  pendingExplicitPlacement[player] = nil
  pendingSlideRelease[player] = nil
  pendingSlideStream[player] = nil
   status:FireClient(player, "entrycancel", {Token = attempt and attempt.Token})
  status:FireClient(player, "loadfailed", reason)
  if IS_STUDIO or not IS_RESERVED_ROUND_SERVER then
   inRound[player] = nil
   player:SetAttribute("InRound", false)
   player.CameraMode = Enum.CameraMode.Classic
   player.CameraMinZoomDistance, player.CameraMaxZoomDistance = 8, 18
   local character = player.Character
   local root = character and character:FindFirstChild("HumanoidRootPart")
   -- If Build is still parking/restoring the lobby, keep the existing rig
   -- protected at its current position. The player is already out of gameplay
   -- and sees the error; restoration below alone may release/reload it.
   if root then
    root.Anchored = true
    root.AssemblyLinearVelocity = Vector3.zero
   end
   status:FireClient(player, "lobby")
  end
 end
 task.spawn(function()
  if IS_RESERVED_ROUND_SERVER and not IS_STUDIO then
   returnGroupToLobby(group)
   local settled, stranded = awaitTransferSettlement(Routing.Endpoints.Fallback)
   if not settled then holdCompletedWorld(stranded, Routing.Endpoints.Fallback) end
   return
  end
  while attempt and attempt.WorldWorkerDone == false do task.wait(.1) end
  returnGroupToLobby(group)
  if not attempt or activeEntry == attempt then roundBusy = false end
 end)
end

loadingRuntime = Loading.New({
 Identity = game.JobId .. ":entry", Now = os.clock,
 Spawn = task.spawn, Delay = task.delay, Wait = task.wait,
 Present = function(player) return player.Parent == Players end,
 Validate = function(player, expected)
  local character = player.Character
  local humanoid = character and character:FindFirstChildOfClass("Humanoid")
  local root = character and character:FindFirstChild("HumanoidRootPart")
  return inRound[player] == true and player:GetAttribute("InRound") == true
   and character == expected.Character and character.Parent ~= nil
   and humanoid ~= nil and humanoid.Health > 0 and root ~= nil
   and (root.Position - expected.Position).Magnitude <= 20
 end,
 Prepare = function(player, attempt, expected)
  status:FireClient(player, "entryprepare", {
   Token = attempt.Token, Level = expected.Level, Character = expected.Character,
   Position = expected.Position, Deadline = workspace:GetServerTimeNow() + attempt:Remaining(),
  })
 end,
 Failed = function(attempt, reason) recoverFailedEntry(attempt, reason) end,
 Warn = function(message) warn("[GameManager] entry worker failed: " .. message) end,
})

local function beginGroupLoading(group, level, warmAllowed, originalDeadline)
 if level == 3 then
  local entryOwner = activeEntry
  if not Level3KitWarmup.Status().Ready then
   workspace:SetAttribute("RoundLoadingState", "warming")
   workspace:SetAttribute("LoadStage", "LEVEL_3_PREPARING_ASSETS")
   workspace:SetAttribute("RoundLoadingDeadline", nil)
   fireGroup(group, "loadinggame", 3)
  end
  local ready, problem = Level3KitWarmup.Await(function()
   return activeEntry == entryOwner and (not warmAllowed or warmAllowed() == true)
  end)
  if not ready then
   -- A replaced caller cannot fail or tear down a newer entry.
   if activeEntry == entryOwner then
    recoverFailedEntry(nil, problem, IS_RESERVED_ROUND_SERVER and Players:GetPlayers() or group)
   end
   return nil
  end
 end
 activeEntry = loadingRuntime:Begin(group)
 -- For reserved Level 1/2, target discovery keeps the original boot deadline.
 if originalDeadline then activeEntry.Deadline = math.min(activeEntry.Deadline, originalDeadline) end
 workspace:SetAttribute("RoundLoadingState", "loading")
 workspace:SetAttribute("RoundLoadingToken", activeEntry.Token)
 w... (truncated)