-- GameManager (v4 -- lobby queue into the existing elevator round)

local Players = game:GetService("Players")
local RS = game:GetService("ReplicatedStorage")
local TweenService = game:GetService("TweenService")
local TeleportService = game:GetService("TeleportService")
local RunService = game:GetService("RunService")

local remotes = RS:WaitForChild("Remotes")
local status = remotes:WaitForChild("RoundStatus")
local queueConfig = remotes:FindFirstChild("ConfigureQueue")
if not queueConfig then
 queueConfig = Instance.new("RemoteEvent")
 queueConfig.Name = "ConfigureQueue"
 queueConfig.Parent = remotes
end

local QUEUE_TIME = 10
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

local inRound = {}
local roundBusy = false
local worldReady = false
local elevatorApi = nil
local mazeStart, entityStart, entity

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
 local old = workspace:FindFirstChild("ServerLobby")
 if old then old:Destroy() end

 local model = Instance.new("Model")
 model.Name = "ServerLobby"
 model.Parent = workspace

 local WALL_TEXTURE = "rbxassetid://87947439437597"
 local FLOOR_TEXTURE = "rbxassetid://100093931957721"
 local CEILING_TEXTURE = "rbxassetid://91804597609254"
 local WALL_COLOR = Color3.fromRGB(197, 180, 116)
 local FLOOR_COLOR = Color3.fromRGB(158, 144, 96)
 local CEILING_COLOR = Color3.fromRGB(222, 214, 170)
 local TRIM_COLOR = Color3.fromRGB(94, 78, 42)

 local function addTexture(part, asset, faces, tileU, tileV, transparency)
  for _, face in ipairs(faces) do
   local texture = Instance.new("Texture")
   texture.Texture = asset
   texture.Face = face
   texture.StudsPerTileU = tileU
   texture.StudsPerTileV = tileV
   texture.Transparency = transparency or 0
   texture.Parent = part
  end
 end
 local wallFaces = {Enum.NormalId.Front, Enum.NormalId.Back, Enum.NormalId.Left, Enum.NormalId.Right}

 -- One large open Backrooms room: carpet, wallpaper, tiled ceiling, no maze corridors.
 local floor = makePart(model, "Carpet", LOBBY_CENTER + Vector3.new(0, -2, 0),
  Vector3.new(150, 4, 120), FLOOR_COLOR, Enum.Material.Fabric)
 addTexture(floor, FLOOR_TEXTURE, {Enum.NormalId.Top}, 6, 6, 0.08)

 local ceiling = makePart(model, "TiledCeiling", LOBBY_CENTER + Vector3.new(0, 18, 0),
  Vector3.new(150, 1, 120), CEILING_COLOR, Enum.Material.SmoothPlastic)
 addTexture(ceiling, CEILING_TEXTURE, {Enum.NormalId.Bottom}, 4, 4, 0.04)

 local walls = {
  makePart(model, "BackWall", LOBBY_CENTER + Vector3.new(0, 8, -60), Vector3.new(150, 20, 3), WALL_COLOR, Enum.Material.SmoothPlastic),
  makePart(model, "FrontWall", LOBBY_CENTER + Vector3.new(0, 8, 60), Vector3.new(150, 20, 3), WALL_COLOR, Enum.Material.SmoothPlastic),
  makePart(model, "LeftWall", LOBBY_CENTER + Vector3.new(-75, 8, 0), Vector3.new(3, 20, 120), WALL_COLOR, Enum.Material.SmoothPlastic),
  makePart(model, "RightWall", LOBBY_CENTER + Vector3.new(75, 8, 0), Vector3.new(3, 20, 120), WALL_COLOR, Enum.Material.SmoothPlastic),
 }
 for _, wall in ipairs(walls) do addTexture(wall, WALL_TEXTURE, wallFaces, 6, 6, 0.05) end

 -- Faded maintenance notes and crude drawings break up the repeating wallpaper.
 -- They are true wall surfaces, so they stay fixed in the room and inherit its light.
 local function addWallMark(wall, face, name, text, position, size, color, rotation, font)
  local canvas = Instance.new("SurfaceGui")
  canvas.Name = name .. "Canvas"
  canvas.Face = face
  canvas.CanvasSize = Vector2.new(1500, 220)
  canvas.LightInfluence = 1
  canvas.AlwaysOnTop = false
  canvas.Parent = wall

  local mark = Instance.new("TextLabel")
  mark.Name = name
  mark.Position = position
  mark.Size = size
  mark.BackgroundTransparency = 1
  mark.BorderSizePixel = 0
  mark.Font = font or Enum.Font.Code
  mark.Text = text
  mark.TextScaled = true
  mark.TextWrapped = true
  mark.TextColor3 = color
  mark.TextTransparency = 0.24
  mark.TextStrokeColor3 = Color3.fromRGB(42, 33, 20)
  mark.TextStrokeTransparency = 0.86
  mark.Rotation = rotation or 0
  mark.Parent = canvas
 end

 local fadedBrown = Color3.fromRGB(92, 68, 34)
 local fadedRed = Color3.fromRGB(116, 50, 35)
 local fadedGrey = Color3.fromRGB(78, 73, 55)
 addWallMark(walls[1], Enum.NormalId.Back, "NoWayOut", "NO WAY OUT",
  UDim2.fromScale(0.08, 0.25), UDim2.fromScale(0.25, 0.22), fadedRed, -4, Enum.Font.Arcade)
 addWallMark(walls[1], Enum.NormalId.Back, "KeepMoving", "KEEP MOVING  >>>",
  UDim2.fromScale(0.61, 0.57), UDim2.fromScale(0.30, 0.14), fadedBrown, 2, Enum.Font.Code)
 addWallMark(walls[1], Enum.NormalId.Back, "WatchingEye", "--(  O  )--",
  UDim2.fromScale(0.40, 0.18), UDim2.fromScale(0.20, 0.18), fadedGrey, -2, Enum.Font.Code)

 addWallMark(walls[2], Enum.NormalId.Front, "HumWarning", "DO NOT FOLLOW THE HUM",
  UDim2.fromScale(0.08, 0.48), UDim2.fromScale(0.34, 0.15), fadedBrown, 1, Enum.Font.Code)
 addWallMark(walls[2], Enum.NormalId.Front, "Tallies", "////  ////  ///",
  UDim2.fromScale(0.69, 0.31), UDim2.fromScale(0.19, 0.22), fadedRed, -7, Enum.Font.Code)

 addWallMark(walls[3], Enum.NormalId.Right, "ExitQuestion", "<<<  EXIT?",
  UDim2.fromScale(0.20, 0.37), UDim2.fromScale(0.35, 0.18), fadedRed, -3, Enum.Font.Code)
 addWallMark(walls[3], Enum.NormalId.Right, "StickFigure", "  O\n /|\\\n / \\",
  UDim2.fromScale(0.68, 0.22), UDim2.fromScale(0.13, 0.40), fadedGrey, 4, Enum.Font.Code)

 addWallMark(walls[4], Enum.NormalId.Left, "LightWarning", "THE LIGHTS REMEMBER",
  UDim2.fromScale(0.12, 0.25), UDim2.fromScale(0.38, 0.16), fadedBrown, -2, Enum.Font.Code)
 addWallMark(walls[4], Enum.NormalId.Left, "WrongWay", "X     >>>",
  UDim2.fromScale(0.65, 0.55), UDim2.fromScale(0.22, 0.18), fadedRed, 5, Enum.Font.Code)

 -- Welcome/community board directly behind the lobby spawn. It is a physical,
 -- maintenance-style sign rather than a screen-following UI, so it reads naturally
 -- on desktop, phone and tablet when the player turns around.
 local welcomeBoard = makePart(model, "WelcomeCommunityBoard",
  LOBBY_CENTER + Vector3.new(0, 10, -58.1), Vector3.new(52, 14, 0.4),
  Color3.fromRGB(34, 30, 20), Enum.Material.Wood)
 welcomeBoard.CanCollide = false
 local boardTrimColor = Color3.fromRGB(132, 111, 55)
 makePart(model, "WelcomeBoardTrimTop", LOBBY_CENTER + Vector3.new(0, 17.1, -57.95),
  Vector3.new(53, 0.45, 0.55), boardTrimColor, Enum.Material.Metal).CanCollide = false
 makePart(model, "WelcomeBoardTrimBottom", LOBBY_CENTER + Vector3.new(0, 2.9, -57.95),
  Vector3.new(53, 0.45, 0.55), boardTrimColor, Enum.Material.Metal).CanCollide = false
 makePart(model, "WelcomeBoardTrimLeft", LOBBY_CENTER + Vector3.new(-26.25, 10, -57.95),
  Vector3.new(0.45, 14.6, 0.55), boardTrimColor, Enum.Material.Metal).CanCollide = false
 makePart(model, "WelcomeBoardTrimRight", LOBBY_CENTER + Vector3.new(26.25, 10, -57.95),
  Vector3.new(0.45, 14.6, 0.55), boardTrimColor, Enum.Material.Metal).CanCollide = false

 local welcomeGui = Instance.new("SurfaceGui")
 welcomeGui.Name = "WelcomeBoardDisplay"
 welcomeGui.Face = Enum.NormalId.Back
 welcomeGui.CanvasSize = Vector2.new(1600, 430)
 welcomeGui.LightInfluence = 0.25
 welcomeGui.AlwaysOnTop = false
 welcomeGui.Parent = welcomeBoard

 local function boardText(name, text, position, size, textSize, color, font, align)
  local label = Instance.new("TextLabel")
  label.Name = name
  label.Position = position
  label.Size = size
  label.BackgroundTransparency = 1
  label.BorderSizePixel = 0
  label.Font = font or Enum.Font.Code
  label.Text = text
  label.TextColor3 = color
  label.TextSize = textSize
  label.TextWrapped = true
  label.TextXAlignment = align or Enum.TextXAlignment.Left
  label.TextYAlignment = Enum.TextYAlignment.Top
  label.Parent = welcomeGui
  return label
 end

 local headerStrip = Instance.new("Frame")
 headerStrip.Name = "HeaderStrip"
 headerStrip.Size = UDim2.fromScale(1, 0.20)
 headerStrip.BackgroundColor3 = Color3.fromRGB(20, 26, 23)
 headerStrip.BackgroundTransparency = 0.06
 headerStrip.BorderSizePixel = 0
 headerStrip.Parent = welcomeGui
 boardText("MainTitle", "WELCOME TO  BACKROOMS: NO WAY OUT",
  UDim2.fromScale(0.03, 0.035), UDim2.fromScale(0.94, 0.14), 52,
  Color3.fromRGB(112, 255, 202), Enum.Font.Code, Enum.TextXAlignment.Center).TextYAlignment = Enum.TextYAlignment.Center

 local divider = Instance.new("Frame")
 divider.Name = "Divider"
 divider.Position = UDim2.fromScale(0.50, 0.24)
 divider.Size = UDim2.fromScale(0.0025, 0.70)
 divider.BackgroundColor3 = boardTrimColor
 divider.BackgroundTransparency = 0.30
 divider.BorderSizePixel = 0
 divider.Parent = welcomeGui

 boardText("GameHeader", "THE ANOMALY AWAITS",
  UDim2.fromScale(0.035, 0.25), UDim2.fromScale(0.43, 0.10), 34,
  Color3.fromRGB(238, 214, 132), Enum.Font.Code)
 boardText("GameMessage",
  "A new Backrooms experience.\n\nExplore strange levels.\nFace new entities.\nFind a way through.\n\nGOOD LUCK.",
  UDim2.fromScale(0.035, 0.36), UDim2.fromScale(0.43, 0.56), 28,
  Color3.fromRGB(228, 224, 190), Enum.Font.Code)

 boardText("StudioHeader", "A MESSAGE FROM THE STUDIO",
  UDim2.fromScale(0.535, 0.25), UDim2.fromScale(0.43, 0.10), 34,
  Color3.fromRGB(238, 214, 132), Enum.Font.Code)
 boardText("StudioMessage",
  "We're a two-person team building the games we love.\n\nEvery play and every piece of feedback helps us create more levels.\n\nSupport us through our original skins, power-ups or donations.\n\nJOIN THE COMMUNITY  •  SHARE FEEDBACK\nLinks are on the experience page.\n\nTHANK YOU — HAVE FUN.",
  UDim2.fromScale(0.535, 0.36), UDim2.fromScale(0.43, 0.60), 24,
  Color3.fromRGB(228, 224, 190), Enum.Font.Code)

 -- Dark worn trim anchors the wallpaper and makes the room feel deliberately built.
 makePart(model, "BackBaseTrim", LOBBY_CENTER + Vector3.new(0, 0.7, -58.3), Vector3.new(147, 1.2, 0.5), TRIM_COLOR, Enum.Material.Wood)
 makePart(model, "FrontBaseTrim", LOBBY_CENTER + Vector3.new(0, 0.7, 58.3), Vector3.new(147, 1.2, 0.5), TRIM_COLOR, Enum.Material.Wood)
 makePart(model, "LeftBaseTrim", LOBBY_CENTER + Vector3.new(-73.3, 0.7, 0), Vector3.new(0.5, 1.2, 117), TRIM_COLOR, Enum.Material.Wood)
 makePart(model, "RightBaseTrim", LOBBY_CENTER + Vector3.new(73.3, 0.7, 0), Vector3.new(0.5, 1.2, 117), TRIM_COLOR, Enum.Material.Wood)

 -- Sparse pillars give the big room shape without turning it into another maze.
 for _, offset in ipairs({Vector3.new(-52, 8, -25), Vector3.new(52, 8, -25), Vector3.new(-52, 8, 34), Vector3.new(52, 8, 34)}) do
  local column = makePart(model, "WallpaperColumn", LOBBY_CENTER + offset, Vector3.new(5, 18, 5), WALL_COLOR, Enum.Material.SmoothPlastic)
  addTexture(column, WALL_TEXTURE, wallFaces, 6, 6, 0.05)
  makePart(model, "ColumnBase", LOBBY_CENTER + Vector3.new(offset.X, 0.6, offset.Z), Vector3.new(5.6, 1.2, 5.6), TRIM_COLOR, Enum.Material.Wood)
 end

 -- Invisible lobby spawn guide. The carpet beneath it is the actual floor.
 local spawn = makePart(model, "LobbySpawn", LOBBY_CENTER + Vector3.new(0, 0.35, -38),
  Vector3.new(34, 0.4, 18), FLOOR_COLOR, Enum.Material.Fabric, 1)
 spawn.CanCollide = false

 -- Four independent launch stations. Each station is intentionally compact so the
 -- lobby remains readable on phones and no sign follows the player's camera.
 local stations = {}
 local stationOffsets = {
  Vector3.new(-28, 0.18, -2),
  Vector3.new(28, 0.18, -2),
  Vector3.new(-28, 0.18, 31),
  Vector3.new(28, 0.18, 31),
 }
 local stationColors = {
  Color3.fromRGB(90, 255, 180),
  Color3.fromRGB(90, 225, 255),
  Color3.fromRGB(165, 255, 120),
  Color3.fromRGB(115, 205, 255),
 }
 local halfX, halfZ = 12, 11

 for index, offset in ipairs(stationOffsets) do
  local origin = LOBBY_CENTER + offset
  local edgeColor = stationColors[index]
  local zone = makePart(model, "LaunchZone" .. index, origin,
   Vector3.new(halfX * 2, 0.32, halfZ * 2), edgeColor, Enum.Material.Neon, 0.78)
  zone.CanCollide = false
  zone.CanTouch = false
  zone.CanQuery = false

  for _, data in ipairs({
   {Vector3.new(0, 0.42, -halfZ), Vector3.new(halfX * 2 + 1, 0.48, 0.48)},
   {Vector3.new(0, 0.42, halfZ), Vector3.new(halfX * 2 + 1, 0.48, 0.48)},
   {Vector3.new(-halfX, 0.42, 0), Vector3.new(0.48, 0.48, halfZ * 2 + 1)},
   {Vector3.new(halfX, 0.42, 0), Vector3.new(0.48, 0.48, halfZ * 2 + 1)},
   {Vector3.new(0, 4.8, -halfZ), Vector3.new(halfX * 2 + 1, 0.26, 0.26)},
   {Vector3.new(0, 4.8, halfZ), Vector3.new(halfX * 2 + 1, 0.26, 0.26)},
   {Vector3.new(-halfX, 4.8, 0), Vector3.new(0.26, 0.26, halfZ * 2 + 1)},
   {Vector3.new(halfX, 4.8, 0), Vector3.new(0.26, 0.26, halfZ * 2 + 1)},
  }) do
   local rail = makePart(model, "Station" .. index .. "Rail", origin + data[1], data[2], edgeColor, Enum.Material.Neon, 0.14)
   rail.CanCollide = false
   rail.CanTouch = false
   rail.CanQuery = false
  end
  for _, cornerOffset in ipairs({
   Vector3.new(-halfX, 2.55, -halfZ), Vector3.new(halfX, 2.55, -halfZ),
   Vector3.new(-halfX, 2.55, halfZ), Vector3.new(halfX, 2.55, halfZ),
  }) do
   local post = makePart(model, "Station" .. index .. "Post", origin + cornerOffset,
    Vector3.new(0.48, 4.7, 0.48), edgeColor, Enum.Material.Neon, 0.1)
   post.CanCollide = false
   post.CanQuery = false
  end

  -- Fixed world-space sign: small, physical, and perspective-correct on mobile.
  local signPanel = makePart(model, "Station" .. index .. "Sign",
   origin + Vector3.new(0, 7.1, halfZ + 0.9), Vector3.new(13.5, 4.4, 0.45),
   Color3.fromRGB(34, 30, 18), Enum.Material.Metal)
  signPanel.CanCollide = false
  local board = Instance.new("SurfaceGui")
  board.Name = "StationDisplay"
  board.Face = Enum.NormalId.Front
  board.CanvasSize = Vector2.new(540, 176)
  board.LightInfluence = 0
  board.AlwaysOnTop = false
  board.Parent = signPanel

  local title = Instance.new("TextLabel")
  title.Name = "Title"
  title.Size = UDim2.new(1, -18, 0.58, -5)
  title.Position = UDim2.fromOffset(9, 7)
  title.BackgroundTransparency = 1
  title.BorderSizePixel = 0
  title.Font = Enum.Font.GothamBold
  title.TextScaled = true
  title.TextColor3 = edgeColor
  title.Text = "STATION " .. index .. "  •  0/6"
  title.Parent = board

  local sub = Instance.new("TextLabel")
  sub.Name = "Subtitle"
  sub.Position = UDim2.new(0, 9, 0.58, 0)
  sub.Size = UDim2.new(1, -18, 0.32, 0)
  sub.BackgroundTransparency = 1
  sub.BorderSizePixel = 0
  sub.Font = Enum.Font.Code
  sub.TextScaled = true
  sub.TextColor3 = Color3.fromRGB(225, 213, 160)
  sub.Text = "ENTER TO JOIN  •  MAX 6 PLAYERS"
  sub.Parent = board

  local outline = Instance.new("SurfaceGui")
  outline.Name = "BackDisplay"
  outline.Face = Enum.NormalId.Back
  outline.CanvasSize = Vector2.new(540, 176)
  outline.LightInfluence = 0
  outline.Parent = signPanel
  local backText = title:Clone()
  backText.Text = "STATION " .. index .. "  •  MAX 6"
  backText.Size = UDim2.new(1, -18, 1, -14)
  backText.Parent = outline

  stations[index] = {
   index = index,
   zone = zone,
   title = title,
   sub = sub,
   color = edgeColor,
   busy = false,
  }
 end

 -- A regular grid of fluorescent fixtures gives the lobby the familiar office hum.
 for _, x in ipairs({-50, 0, 50}) do
  for _, z in ipairs({-36, 2, 40}) do
   local panel = makePart(model, "FluorescentPanel", LOBBY_CENTER + Vector3.new(x, 17.35, z),
    Vector3.new(13, 0.35, 5), Color3.fromRGB(255, 247, 203), Enum.Material.Neon)
   local light = Instance.new("PointLight")
   light.Color = Color3.fromRGB(255, 235, 175)
   light.Brightness = 1.45
   light.Range = 38
   light.Shadows = true
   light.Parent = panel
  end
 end

 -- Small maintenance counter and waiting benches: enough detail to feel inhabited.
 local counter = makePart(model, "MaintenanceCounter", LOBBY_CENTER + Vector3.new(-52, 2, -48),
  Vector3.new(28, 4, 4), Color3.fromRGB(86, 76, 54), Enum.Material.WoodPlanks)
 makePart(model, "CounterTop", counter.Position + Vector3.new(0, 2.25, 0), Vector3.new(29, 0.5, 5), Color3.fromRGB(45, 43, 36), Enum.Material.Metal)
 for _, z in ipairs({-32, -14}) do
  makePart(model, "BenchSeat", LOBBY_CENTER + Vector3.new(58, 1.5, z), Vector3.new(18, 1, 3), Color3.fromRGB(82, 72, 48), Enum.Material.WoodPlanks)
  makePart(model, "BenchBack", LOBBY_CENTER + Vector3.new(58, 3.2, z + 1.2), Vector3.new(18, 3.5, 0.7), Color3.fromRGB(72, 63, 43), Enum.Material.WoodPlanks)
  -- Two broad pedestals meet the carpet exactly and visibly carry the seat.
  for _, xOffset in ipairs({-6.5, 6.5}) do
   makePart(model, "BenchLeg", LOBBY_CENTER + Vector3.new(58 + xOffset, 0.5, z),
    Vector3.new(1.2, 1, 2.25), Color3.fromRGB(55, 50, 38), Enum.Material.WoodPlanks)
  end
 end


 -- Dedicated Lost & Found bay along the far-left wall. Keeping it against the
 -- perimeter gives it a clear identity and avoids every pillar, spawn pad and queue.
 local lostMat = makePart(model, "LostAndFoundMat",
  LOBBY_CENTER + Vector3.new(-65.5, 0.055, 49), Vector3.new(16, 0.07, 17),
  Color3.fromRGB(63, 57, 39), Enum.Material.Fabric, 0.12)
 lostMat.CanCollide = false

 local lostBackPanel = makePart(model, "LostAndFoundWallPanel",
  LOBBY_CENTER + Vector3.new(-73.05, 8, 49), Vector3.new(0.42, 8, 20),
  Color3.fromRGB(35, 31, 22), Enum.Material.Wood)
 lostBackPanel.CanCollide = false
 local lostTrim = Color3.fromRGB(130, 108, 54)
 makePart(model, "LostPanelTrimTop", LOBBY_CENTER + Vector3.new(-72.78, 12.15, 49),
  Vector3.new(0.55, 0.45, 20.8), lostTrim, Enum.Material.Metal).CanCollide = false
 makePart(model, "LostPanelTrimBottom", LOBBY_CENTER + Vector3.new(-72.78, 3.85, 49),
  Vector3.new(0.55, 0.45, 20.8), lostTrim, Enum.Material.Metal).CanCollide = false
 makePart(model, "LostPanelTrimNear", LOBBY_CENTER + Vector3.new(-72.78, 8, 38.8),
  Vector3.new(0.55, 8.6, 0.45), lostTrim, Enum.Material.Metal).CanCollide = false
 makePart(model, "LostPanelTrimFar", LOBBY_CENTER + Vector3.new(-72.78, 8, 59.0),
  Vector3.new(0.55, 8.6, 0.45), lostTrim, Enum.Material.Metal).CanCollide = false

 local lostGui = Instance.new("SurfaceGui")
 lostGui.Name = "LostAndFoundDisplay"
 lostGui.Face = Enum.NormalId.Right
 lostGui.CanvasSize = Vector2.new(920, 380)
 lostGui.LightInfluence = 0.25
 lostGui.Parent = lostBackPanel
 local lostTitle = Instance.new("TextLabel")
 lostTitle.Position = UDim2.fromScale(0.06, 0.08)
 lostTitle.Size = UDim2.fromScale(0.88, 0.39)
 lostTitle.BackgroundTransparency = 1
 lostTitle.Font = Enum.Font.Code
 lostTitle.Text = "LOST & FOUND"
 lostTitle.TextColor3 = Color3.fromRGB(232, 211, 140)
 lostTitle.TextStrokeTransparency = 0.55
 lostTitle.TextScaled = true
 lostTitle.Parent = lostGui
 local lostSubtitle = Instance.new("TextLabel")
 lostSubtitle.Position = UDim2.fromScale(0.15, 0.48)
 lostSubtitle.Size = UDim2.fromScale(0.70, 0.16)
 lostSubtitle.BackgroundTransparency = 1
 lostSubtitle.Font = Enum.Font.Code
 lostSubtitle.Text = "UNCLAIMED ITEMS"
 lostSubtitle.TextColor3 = Color3.fromRGB(164, 151, 105)
 lostSubtitle.TextScaled = true
 lostSubtitle.Parent = lostGui
 local lostWarning = Instance.new("TextLabel")
 lostWarning.Position = UDim2.fromScale(0.20, 0.67)
 lostWarning.Size = UDim2.fromScale(0.60, 0.13)
 lostWarning.BackgroundTransparency = 1
 lostWarning.Font = Enum.Font.Code
 lostWarning.Text = "TAKE NOTHING."
 lostWarning.TextColor3 = Color3.fromRGB(164, 82, 58)
 lostWarning.TextScaled = true
 lostWarning.Parent = lostGui

 -- Low dividers and a long counter make this read as its own little department.
 for _, boundaryZ in ipairs({40.5, 57.5}) do
  makePart(model, "LostAndFoundDivider", LOBBY_CENTER + Vector3.new(-66, 1.5, boundaryZ),
   Vector3.new(14, 3, 0.55), Color3.fromRGB(73, 62, 42), Enum.Material.WoodPlanks)
 end
 local lostCounter = makePart(model, "LostAndFoundCounter",
  LOBBY_CENTER + Vector3.new(-60.5, 2, 49), Vector3.new(4, 4, 13),
  Color3.fromRGB(75, 64, 43), Enum.Material.WoodPlanks)
 makePart(model, "LostCounterTop", lostCounter.Position + Vector3.new(0, 2.2, 0),
  Vector3.new(4.8, 0.45, 14), Color3.fromRGB(44, 42, 35), Enum.Material.Metal)

 for index, crateInfo in ipairs({
  {Vector3.new(-61.2, 5.05, 45.5), Vector3.new(3.0, 1.7, 3.2), Color3.fromRGB(105, 85, 52)},
  {Vector3.new(-61.1, 4.85, 52.0), Vector3.new(2.7, 1.3, 3.5), Color3.fromRGB(86, 73, 49)},
 }) do
  local crate = makePart(model, "LostCrate" .. index, LOBBY_CENTER + crateInfo[1], crateInfo[2], crateInfo[3], Enum.Material.WoodPlanks)
  crate.CanCollide = false
 end
 local abandonedLight = makePart(model, "AbandonedFlashlight",
  LOBBY_CENTER + Vector3.new(-60.5, 5.0, 49), Vector3.new(3.1, 0.65, 0.65),
  Color3.fromRGB(58, 59, 55), Enum.Material.Metal)
 abandonedLight.Shape = Enum.PartType.Cylinder
 abandonedLight.CanCollide = false
 local abandonedLens = makePart(model, "AbandonedFlashlightLens",
  LOBBY_CENTER + Vector3.new(-58.82, 5.0, 49), Vector3.new(0.28, 0.72, 0.72),
  Color3.fromRGB(246, 224, 154), Enum.Material.Neon)
 abandonedLens.Shape = Enum.PartType.Cylinder
 abandonedLens.CanCollide = false

  -- Footprints cross an empty stretch of carpet and simply stop at the wall.
  -- Their fading opacity suggests whoever made them did not walk back.
  for step = 1, 8 do
   local x = 24 + step * 5.7
   local side = (step % 2 == 0) and 0.46 or -0.46
   local foot = makePart(model, "VanishingFootprint" .. step,
    LOBBY_CENTER + Vector3.new(x, 0.055, -45 + side), Vector3.new(1.25, 0.07, 0.58),
    Color3.fromRGB(65, 56, 36), Enum.Material.Fabric, 0.10 + step * 0.055)
   foot.Shape = Enum.PartType.Ball
   foot.CFrame = CFrame.new(foot.Position) * CFrame.Angles(0, math.rad((step % 2 == 0) and -7 or 7), 0)
   foot.CanCollide = false
  end

 -- A couple of subtle damp carpet patches echo the generated map without clutter.
 for _, stain in ipairs({{Vector3.new(-28, 0.24, -22), Vector3.new(13, 0.08, 8)}, {Vector3.new(38, 0.24, 38), Vector3.new(10, 0.08, 16)}}) do
  local patch = makePart(model, "DampCarpet", LOBBY_CENTER + stain[1], stain[2], Color3.fromRGB(90, 84, 57), Enum.Material.Fabric, 0.3)
  patch.CanCollide = false
 end

 return model, spawn, stations
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
 player.CameraMode = Enum.CameraMode.LockFirstPerson
 task.defer(function()
  if inRound[player] then
   if worldReady then placeSafelyInElevator(player, char) end
  else
   scatterAt(char, lobbySpawn, false)
  end
 end)
 local hum = char:WaitForChild("Humanoid")
 hum.UseJumpPower = true
 hum.JumpPower = 0
 hum.Died:Connect(function()
  player.CameraMode = Enum.CameraMode.Classic
  if not inRound[player] then
   task.delay(3, function()
    if player.Parent and not inRound[player] then player:LoadCharacter() end
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
  if not IS_RESERVED_ROUND_SERVER and not player.Character then player:LoadCharacter() end
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
  "STATION " .. station.index .. "  •  1/" .. station.maxPlayers,
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

local function ensureWorld(group)
 if worldReady then return true end
 workspace:SetAttribute("LoadStage", "GENERATING_WORLD")
 workspace:SetAttribute("GenerateWorld", true)
 local deadline = os.clock() + 180
 while workspace:GetAttribute("WorldGenerated") ~= true and os.clock() < deadline do task.wait(0.25) end
 if workspace:GetAttribute("WorldGenerated") ~= true then
  warn("GameManager: world generation timed out")
  return false
 end
 elevatorApi = connectElevator()
 mazeStart = workspace:WaitForChild("MazeStart", 30)
 entityStart = workspace:WaitForChild("EntityStart", 30)
 entity = workspace:WaitForChild("Entity", 30)
 worldReady = elevatorApi ~= nil and mazeStart ~= nil
 workspace:SetAttribute("LoadStage", worldReady and "READY" or "WORLD_ERROR")
 return worldReady
end

local function returnGroupToLobby(group)
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
  player:LoadCharacter()
  status:FireClient(player, "lobby")
 end
end

local function playRound(participants)
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
 for t = ELEVATOR_TIME, 1, -1 do
  if aliveCount <= 0 then sendWipedPartyHome(); return end
  fireGroup(participants, "elevator", t)
  task.wait(t == 8 and 2 or 1)
 end
 elevatorApi.open()
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
  if ensureWorld(participants) then
   for _, player in ipairs(participants) do
    if player.Parent then
     player:LoadCharacter()
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
  "STATION " .. station.index .. "  •  0/6",
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
    "STATION " .. station.index .. "  •  0/6",
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
     "STATION " .. station.index .. "  •  0/6",
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
    "STATION " .. station.index .. "  •  HOST SETTING UP",
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
    "STATION " .. station.index .. "  •  HOST SETTING UP",
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
  for t = QUEUE_TIME, 1, -1 do
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

  if ensureWorld(participants) then
   for _, player in ipairs(participants) do
    if player.Parent then
     player:LoadCharacter()
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
