-- RoundUI
-- Top-of-screen status bar plus the opening objective sequence.

local Players = game:GetService("Players")
local RS = game:GetService("ReplicatedStorage")
local RunService = game:GetService("RunService")
local UIS = game:GetService("UserInputService")
local Lighting = game:GetService("Lighting")
local TweenService = game:GetService("TweenService")

local remotes = RS:WaitForChild("Remotes")
local remote = remotes:WaitForChild("RoundStatus")
local queueRemote = remotes:WaitForChild("ConfigureQueue")
local player = Players.LocalPlayer
local dead = false

-- Lighting is global on the server, but lobby players can coexist with a party
-- inside the dark maze. This local pass keeps the lobby warm and readable while
-- preserving the exact horror grade for active participants.
local lobbyGrade = Lighting:FindFirstChild("LobbyLocalGrade") or Instance.new("ColorCorrectionEffect")
lobbyGrade.Name = "LobbyLocalGrade"
lobbyGrade.Saturation = -0.08
lobbyGrade.Contrast = 0.04
lobbyGrade.Brightness = 0.02
lobbyGrade.TintColor = Color3.fromRGB(255, 242, 188)
lobbyGrade.Parent = Lighting

local function applyPlayerLighting()
 local inMaze = player:GetAttribute("InRound") == true
 local mazeGrade = Lighting:FindFirstChild("MongoGrade")
 local levelTwoWorld = workspace:FindFirstChild("Level 2 Generated World") or workspace:FindFirstChild("PoolroomsLevel2")
 local isLevelTwo = levelTwoWorld ~= nil and (workspace:GetAttribute("SelectedLevel") == 2 or inMaze)

 if isLevelTwo and workspace:GetAttribute("Level2LightingOwnedByController") == true then
  lobbyGrade.Enabled = false
  if mazeGrade then mazeGrade.Enabled = false end
  return
 end


 if isLevelTwo then
  lobbyGrade.Enabled = false
  if mazeGrade then mazeGrade.Enabled = false end
  Lighting.ClockTime = 14
  Lighting.FogColor = Color3.fromRGB(216, 217, 195)
  Lighting.FogStart = 100000
  Lighting.FogEnd = 100000

  if levelTwoWorld:GetAttribute("ValveColorWashActive") == true then
   local valveColor = levelTwoWorld:GetAttribute("ValveColorWashColor")
   if typeof(valveColor) == "Color3" then
    Lighting.Brightness = 1.95
    Lighting.Ambient = Color3.fromRGB(92, 90, 78):Lerp(valveColor, .30)
    Lighting.OutdoorAmbient = Color3.fromRGB(102, 100, 88):Lerp(valveColor, .22)
    Lighting.ColorShift_Top = Color3.new(1, 1, 1):Lerp(valveColor, .42)
    Lighting.ColorShift_Bottom = valveColor:Lerp(Color3.new(0, 0, 0), .76)
    return
   end
  end

  Lighting.Ambient = Color3.fromRGB(92, 90, 78)
  Lighting.OutdoorAmbient = Color3.fromRGB(102, 100, 88)
  Lighting.Brightness = 1.75
  Lighting.ColorShift_Top = Color3.fromRGB(255, 246, 220)
  Lighting.ColorShift_Bottom = Color3.fromRGB(20, 29, 28)
  return
 end

 Lighting.ColorShift_Top = Color3.new(0, 0, 0)
 Lighting.ColorShift_Bottom = Color3.new(0, 0, 0)
 if inMaze then
  Lighting.Ambient = Color3.fromRGB(4, 4, 3)
  Lighting.OutdoorAmbient = Color3.fromRGB(0, 0, 0)
  Lighting.Brightness = 0.3
  Lighting.ClockTime = 0
  Lighting.FogColor = Color3.fromRGB(16, 14, 9)
  Lighting.FogStart = 30
  Lighting.FogEnd = 220
  lobbyGrade.Enabled = false
  if mazeGrade then mazeGrade.Enabled = true end
 else
  Lighting.Ambient = Color3.fromRGB(76, 69, 45)
  Lighting.OutdoorAmbient = Color3.fromRGB(48, 43, 28)
  Lighting.Brightness = 1.35
  Lighting.ClockTime = 14
  Lighting.FogColor = Color3.fromRGB(205, 190, 125)
  Lighting.FogStart = 0
  Lighting.FogEnd = 100000
  lobbyGrade.Enabled = true
  if mazeGrade then mazeGrade.Enabled = false end
 end
end

player:GetAttributeChangedSignal("InRound"):Connect(applyPlayerLighting)
task.spawn(function()
 while true do
  applyPlayerLighting() -- reassert after server-side maze lighting changes
  task.wait(0.5)
 end
end)
applyPlayerLighting()

local gui = Instance.new("ScreenGui")
gui.Name = "RoundGui"
gui.ResetOnSpawn = false
gui.IgnoreGuiInset = true
gui.DisplayOrder = 100
gui.Parent = player:WaitForChild("PlayerGui")

local label = Instance.new("TextLabel")
label.AnchorPoint = Vector2.new(0.5, 0)
label.Position = UDim2.new(0.5, 0, 0, 18)
label.Size = UDim2.new(0, 700, 0, 180)
label.BackgroundColor3 = Color3.new(0, 0, 0)
label.BackgroundTransparency = 0.72
label.BorderSizePixel = 0
label.Font = Enum.Font.GothamMedium
label.TextScaled = false
label.TextSize = 26
label.TextWrapped = true
label.TextYAlignment = Enum.TextYAlignment.Center
label.TextColor3 = Color3.fromRGB(235, 232, 222)
label.Text = ""
label.Visible = false
label.Parent = gui

local corner = Instance.new("UICorner")
corner.CornerRadius = UDim.new(0, 6)
corner.Parent = label

-- Host-only queue setup. The first player inside an empty station sees this panel;
-- the server remains authoritative over host identity, capacity and privacy.
local queueShade = Instance.new("Frame")
queueShade.Name = "QueueHostShade"
queueShade.Size = UDim2.fromScale(1, 1)
queueShade.BackgroundColor3 = Color3.new(0, 0, 0)
queueShade.BackgroundTransparency = 0.38
queueShade.BorderSizePixel = 0
queueShade.Active = true
queueShade.Visible = false
queueShade.ZIndex = 50
queueShade.Parent = gui

local queuePanel = Instance.new("Frame")
queuePanel.Name = "QueueHostPanel"
queuePanel.AnchorPoint = Vector2.new(0.5, 0.5)
queuePanel.Position = UDim2.fromScale(0.5, 0.5)
queuePanel.Size = UDim2.fromScale(0.86, 0.82)
queuePanel.BackgroundColor3 = Color3.fromRGB(16, 19, 17)
queuePanel.BackgroundTransparency = 0.04
queuePanel.BorderSizePixel = 0
queuePanel.ZIndex = 51
queuePanel.Active = true
queuePanel.Parent = queueShade
local queueConstraint = Instance.new("UISizeConstraint")
queueConstraint.MinSize = Vector2.new(320, 330)
queueConstraint.MaxSize = Vector2.new(470, 370)
queueConstraint.Parent = queuePanel
local queueCorner = Instance.new("UICorner")
queueCorner.CornerRadius = UDim.new(0, 12)
queueCorner.Parent = queuePanel
local queueStroke = Instance.new("UIStroke")
queueStroke.Color = Color3.fromRGB(105, 238, 168)
queueStroke.Transparency = 0.30
queueStroke.Thickness = 2
queueStroke.Parent = queuePanel

local function queueText(name, text, position, size, textSize, color)
 local item = Instance.new("TextLabel")
 item.Name = name
 item.Position = position
 item.Size = size
 item.BackgroundTransparency = 1
 item.BorderSizePixel = 0
 item.Font = Enum.Font.Code
 item.Text = text
 item.TextColor3 = color or Color3.fromRGB(225, 228, 213)
 item.TextSize = textSize
 item.TextWrapped = true
 item.ZIndex = 52
 item.Parent = queuePanel
 return item
end

local function queueButton(name, text, position, size)
 local button = Instance.new("TextButton")
 button.Name = name
 button.Position = position
 button.Size = size
 button.BackgroundColor3 = Color3.fromRGB(31, 38, 33)
 button.BackgroundTransparency = 0.06
 button.BorderSizePixel = 0
 button.AutoButtonColor = true
 button.Font = Enum.Font.GothamBold
 button.Text = text
 button.TextColor3 = Color3.fromRGB(225, 235, 224)
 button.TextSize = 21
 button.ZIndex = 53
 button.Parent = queuePanel
 local buttonCorner = Instance.new("UICorner")
 buttonCorner.CornerRadius = UDim.new(0, 8)
 buttonCorner.Parent = button
 local buttonStroke = Instance.new("UIStroke")
 buttonStroke.Color = Color3.fromRGB(120, 170, 137)
 buttonStroke.Transparency = 0.45
 buttonStroke.Thickness = 1.4
 buttonStroke.Parent = button
 return button, buttonStroke
end

local queueTitle = queueText("HostTitle", "CREATE YOUR PARTY", UDim2.new(0.06, 0, 0, 16), UDim2.new(0.88, 0, 0, 38), 31, Color3.fromRGB(116, 255, 178))
queueTitle.TextXAlignment = Enum.TextXAlignment.Center
local queueStationLabel = queueText("StationLabel", "STATION", UDim2.new(0.10, 0, 0, 57), UDim2.new(0.80, 0, 0, 24), 18, Color3.fromRGB(151, 171, 155))
queueStationLabel.TextXAlignment = Enum.TextXAlignment.Center
local queueSizeCaption = queueText("SizeCaption", "MAXIMUM PLAYERS", UDim2.new(0.08, 0, 0, 94), UDim2.new(0.84, 0, 0, 24), 19, Color3.fromRGB(218, 207, 153))
local queueMinus = queueButton("DecreasePlayers", "−", UDim2.new(0.10, 0, 0, 124), UDim2.new(0.20, 0, 0, 52))
local queueCount = queueText("PlayerCount", "6", UDim2.new(0.37, 0, 0, 122), UDim2.new(0.26, 0, 0, 56), 44, Color3.fromRGB(235, 240, 225))
queueCount.TextXAlignment = Enum.TextXAlignment.Center
queueCount.TextYAlignment = Enum.TextYAlignment.Center
local queuePlus = queueButton("IncreasePlayers", "+", UDim2.new(0.70, 0, 0, 124), UDim2.new(0.20, 0, 0, 52))
local queuePrivacyCaption = queueText("PrivacyCaption", "WHO CAN JOIN?", UDim2.new(0.08, 0, 0, 194), UDim2.new(0.84, 0, 0, 24), 19, Color3.fromRGB(218, 207, 153))
local queuePrivacyButton, queuePrivacyStroke = queueButton("PrivacyToggle", "PUBLIC  •  EVERYONE", UDim2.new(0.10, 0, 0, 224), UDim2.new(0.80, 0, 0, 48))
queuePrivacyButton.TextSize = 18
local queueSubmit, queueSubmitStroke = queueButton("CreateParty", "CREATE PARTY", UDim2.new(0.10, 0, 1, -78), UDim2.new(0.80, 0, 0, 50))
queueSubmit.Modal = true -- releases first-person mouse lock while this visible button is on screen
queueSubmit.BackgroundColor3 = Color3.fromRGB(42, 105, 70)
queueSubmitStroke.Color = Color3.fromRGB(120, 255, 175)
local queueClose, queueCloseStroke = queueButton("CloseQueue", "×", UDim2.new(1, -46, 0, 10), UDim2.fromOffset(34, 34))
queueClose.Modal = true
queueClose.ZIndex = 54
queueClose.TextSize = 24
queueClose.BackgroundColor3 = Color3.fromRGB(76, 38, 38)
queueCloseStroke.Color = Color3.fromRGB(255, 125, 125)
queueCloseStroke.Transparency = 0.35
local queueHint = queueText("CancelHint", "STEP OUT OF THE SQUARE TO CANCEL", UDim2.new(0.08, 0, 1, -23), UDim2.new(0.84, 0, 0, 16), 14, Color3.fromRGB(125, 137, 126))
queueHint.TextXAlignment = Enum.TextXAlignment.Center

local function applyQueueDeviceLayout()
 if UIS.TouchEnabled then
  -- Phones and tablets get their own compact landscape-safe arrangement.
  queuePanel.Size = UDim2.fromScale(0.78, 0.74)
  queueConstraint.MinSize = Vector2.new(300, 280)
  queueConstraint.MaxSize = Vector2.new(380, 286)
  -- Do not place a full-screen input-catching box over the mobile controls.
  queueShade.BackgroundTransparency = 1
  queueShade.Active = false

  queueClose.Position = UDim2.new(1, -39, 0, 7)
  queueClose.Size = UDim2.fromOffset(32, 32)
  queueClose.TextSize = 20
  queueTitle.Position = UDim2.new(0.06, 0, 0, 10)
  queueTitle.Size = UDim2.new(0.88, 0, 0, 32)
  queueTitle.TextSize = 22
  queueStationLabel.Position = UDim2.new(0.10, 0, 0, 43)
  queueStationLabel.Size = UDim2.new(0.80, 0, 0, 19)
  queueStationLabel.TextSize = 12

  queueSizeCaption.Position = UDim2.new(0.08, 0, 0, 70)
  queueSizeCaption.Size = UDim2.new(0.84, 0, 0, 18)
  queueSizeCaption.TextSize = 13
  queueMinus.Position = UDim2.new(0.12, 0, 0, 92)
  queueMinus.Size = UDim2.new(0.18, 0, 0, 40)
  queueMinus.TextSize = 18
  queueCount.Position = UDim2.new(0.36, 0, 0, 89)
  queueCount.Size = UDim2.new(0.28, 0, 0, 46)
  queueCount.TextSize = 32
  queuePlus.Position = UDim2.new(0.70, 0, 0, 92)
  queuePlus.Size = UDim2.new(0.18, 0, 0, 40)
  queuePlus.TextSize = 18

  queuePrivacyCaption.Position = UDim2.new(0.08, 0, 0, 143)
  queuePrivacyCaption.Size = UDim2.new(0.84, 0, 0, 18)
  queuePrivacyCaption.TextSize = 13
  queuePrivacyButton.Position = UDim2.new(0.10, 0, 0, 164)
  queuePrivacyButton.Size = UDim2.new(0.80, 0, 0, 38)
  queuePrivacyButton.TextSize = 14
  queueSubmit.Position = UDim2.new(0.10, 0, 0, 216)
  queueSubmit.Size = UDim2.new(0.80, 0, 0, 42)
  queueSubmit.TextSize = 16
  queueHint.Position = UDim2.new(0.08, 0, 0, 265)
  queueHint.Size = UDim2.new(0.84, 0, 0, 14)
  queueHint.TextSize = 10
  queueHint.Text = "WALK OUT OR TAP × TO CANCEL"
 else
  -- Preserve the existing desktop proportions exactly.
  queuePanel.Size = UDim2.fromScale(0.86, 0.82)
  queueConstraint.MaxSize = Vector2.new(470, 370)
  queueConstraint.MinSize = Vector2.new(320, 330)
  queueShade.BackgroundTransparency = 0.38
  queueShade.Active = true
  queueClose.Position = UDim2.new(1, -46, 0, 10)
  queueClose.Size = UDim2.fromOffset(34, 34)
  queueClose.TextSize = 24
  queueHint.Text = "STEP OUT OF THE SQUARE TO CANCEL"
 end
end
applyQueueDeviceLayout()

local queueStation = nil
local queueSizeValue = 6
local queuePrivacyValue = "public"
local queueSubmitting = false

local function refreshQueuePanel()
 queueCount.Text = tostring(queueSizeValue)
 local friendsOnly = queuePrivacyValue == "friends"
 queuePrivacyButton.Text = friendsOnly and "FRIENDS ONLY" or "PUBLIC  •  EVERYONE"
 queuePrivacyButton.TextColor3 = friendsOnly and Color3.fromRGB(255, 218, 125) or Color3.fromRGB(125, 255, 178)
 queuePrivacyStroke.Color = friendsOnly and Color3.fromRGB(255, 202, 95) or Color3.fromRGB(120, 255, 175)
 queueStationLabel.Text = queueStation and ("STATION " .. queueStation .. "  •  YOU ARE THE HOST") or "YOU ARE THE HOST"
 queueSubmit.Text = queueSubmitting and "CREATING PARTY..." or "CREATE PARTY"
 queueSubmit.Active = not queueSubmitting
 queueSubmit.AutoButtonColor = not queueSubmitting
 queueSubmit.BackgroundColor3 = queueSubmitting and Color3.fromRGB(42, 50, 44) or Color3.fromRGB(42, 105, 70)
end

queueMinus.Activated:Connect(function()
 if queueSubmitting then return end
 queueSizeValue = math.max(1, queueSizeValue - 1)
 refreshQueuePanel()
end)
queuePlus.Activated:Connect(function()
 if queueSubmitting then return end
 queueSizeValue = math.min(6, queueSizeValue + 1)
 refreshQueuePanel()
end)
queuePrivacyButton.Activated:Connect(function()
 if queueSubmitting then return end
 queuePrivacyValue = queuePrivacyValue == "public" and "friends" or "public"
 refreshQueuePanel()
end)
queueSubmit.Activated:Connect(function()
 if queueSubmitting or not queueStation then return end
 queueSubmitting = true
 refreshQueuePanel()
 queueRemote:FireServer(queueStation, queueSizeValue, queuePrivacyValue)
 task.delay(3, function()
  if queueShade.Visible and queueSubmitting then
   queueSubmitting = false
   refreshQueuePanel()
  end
 end)
end)
queueClose.Activated:Connect(function()
 if queueSubmitting or not queueStation then return end
 local stationToCancel = queueStation
 queueShade.Visible = false
 queueStation = nil
 queueSubmitting = false
 refreshQueuePanel()
 queueRemote:FireServer(stationToCancel, 0, "cancel")
end)
refreshQueuePanel()

-- RoundUI is the sole cursor-policy owner. Lobby players need the mouse for the
-- queue phone and Zyntra store; gameplay hides it unless a modal is open.
local function shouldShowCursor()
 return player:GetAttribute("InRound") ~= true
  or queueShade.Visible
  or player:GetAttribute("DevPhoneOpen") == true
end

local function refreshCursor()
 if not UIS.MouseEnabled then return end
 local visible = shouldShowCursor()
 if visible then UIS.MouseBehavior = Enum.MouseBehavior.Default end
 UIS.MouseIconEnabled = visible
end

queueShade:GetPropertyChangedSignal("Visible"):Connect(refreshCursor)
player:GetAttributeChangedSignal("InRound"):Connect(refreshCursor)
player:GetAttributeChangedSignal("DevPhoneOpen"):Connect(refreshCursor)
refreshCursor()

-- An open modal must keep the pointer free. Ordinary lobby play deliberately
-- does not touch MouseBehavior here: Roblox uses its temporary right-button
-- lock to rotate the Classic camera while RMB is held.
RunService.RenderStepped:Connect(function()
 if UIS.MouseEnabled and (queueShade.Visible or player:GetAttribute("DevPhoneOpen") == true) then
  UIS.MouseBehavior = Enum.MouseBehavior.Default
  UIS.MouseIconEnabled = true
 end
end)

-- Immediate startup cover: the player sees this before a character or maze exists.
local loadingFrame = Instance.new("Frame")
loadingFrame.Name = "LevelLoading"
loadingFrame.Size = UDim2.fromScale(1, 1)
loadingFrame.BackgroundColor3 = Color3.fromRGB(3, 5, 4)
loadingFrame.BorderSizePixel = 0
loadingFrame.ZIndex = 100
loadingFrame.Visible = false -- the server lobby is visible first
loadingFrame.Parent = gui

local loadingTitle = Instance.new("TextLabel")
loadingTitle.AnchorPoint = Vector2.new(0.5, 0.5)
loadingTitle.Position = UDim2.new(0.5, 0, 0.46, 0)
loadingTitle.Size = UDim2.new(0.9, 0, 0, 78)
loadingTitle.BackgroundTransparency = 1
loadingTitle.Font = Enum.Font.Code
loadingTitle.TextSize = 45
loadingTitle.TextXAlignment = Enum.TextXAlignment.Center
loadingTitle.TextYAlignment = Enum.TextYAlignment.Center
loadingTitle.TextColor3 = Color3.fromRGB(105, 230, 135)
loadingTitle.Text = "> ENTERING LEVEL"
loadingTitle.ZIndex = 101
loadingTitle.Parent = loadingFrame

local loadingStatus = Instance.new("TextLabel")
loadingStatus.AnchorPoint = Vector2.new(0.5, 0.5)
loadingStatus.Position = UDim2.new(0.5, 0, 0.53, 0)
loadingStatus.Size = UDim2.new(0.9, 0, 0, 54)
loadingStatus.BackgroundTransparency = 1
loadingStatus.Font = Enum.Font.Code
loadingStatus.TextSize = 27
loadingStatus.TextXAlignment = Enum.TextXAlignment.Center
loadingStatus.TextYAlignment = Enum.TextYAlignment.Center
loadingStatus.TextColor3 = Color3.fromRGB(65, 165, 90)
loadingStatus.Text = "GENERATING LEVEL"
loadingStatus.ZIndex = 101
loadingStatus.Parent = loadingFrame

-- Full-screen round payoff. It is intentionally separate from the objective bar so
-- it scales cleanly on desktop, phone and tablet.
local endFrame = Instance.new("Frame")
endFrame.Name = "RoundEnding"
endFrame.Size = UDim2.fromScale(1, 1)
endFrame.BackgroundColor3 = Color3.fromRGB(3, 6, 4)
endFrame.BackgroundTransparency = 1
endFrame.BorderSizePixel = 0
endFrame.Active = true
endFrame.Visible = false
endFrame.ZIndex = 120
endFrame.Parent = gui

local endFlash = Instance.new("Frame")
endFlash.Name = "SignalFlash"
endFlash.Size = UDim2.fromScale(1, 1)
endFlash.BackgroundColor3 = Color3.fromRGB(105, 255, 165)
endFlash.BackgroundTransparency = 1
endFlash.BorderSizePixel = 0
endFlash.ZIndex = 121
endFlash.Parent = endFrame

local endLine = Instance.new("Frame")
endLine.Name = "SignalLine"
endLine.AnchorPoint = Vector2.new(0.5, 0.5)
endLine.Position = UDim2.fromScale(0.5, 0.56)
endLine.Size = UDim2.new(0, 0, 0, 2)
endLine.BackgroundColor3 = Color3.fromRGB(105, 255, 165)
endLine.BorderSizePixel = 0
endLine.ZIndex = 122
endLine.Parent = endFrame

local endTitle = Instance.new("TextLabel")
endTitle.Name = "EndingTitle"
endTitle.AnchorPoint = Vector2.new(0.5, 0.5)
endTitle.Position = UDim2.fromScale(0.5, 0.43)
endTitle.Size = UDim2.new(0.88, 0, 0.18, 0)
endTitle.BackgroundTransparency = 1
endTitle.Font = Enum.Font.GothamBlack
endTitle.Text = ("LEVEL " .. tostring(workspace:GetAttribute("SelectedLevel") or 1) .. " CLEARED")
endTitle.TextColor3 = Color3.fromRGB(115, 255, 170)
endTitle.TextScaled = true
endTitle.TextStrokeColor3 = Color3.new(0, 0, 0)
endTitle.TextStrokeTransparency = 0.35
endTitle.TextTransparency = 1
endTitle.TextWrapped = true
endTitle.ZIndex = 123
endTitle.Parent = endFrame
local endTitleSize = Instance.new("UITextSizeConstraint")
endTitleSize.MinTextSize = 24
endTitleSize.MaxTextSize = 62
endTitleSize.Parent = endTitle

local endStats = Instance.new("TextLabel")
endStats.Name = "EndingStats"
endStats.AnchorPoint = Vector2.new(0.5, 0.5)
endStats.Position = UDim2.fromScale(0.5, 0.63)
endStats.Size = UDim2.new(0.86, 0, 0, 44)
endStats.BackgroundTransparency = 1
endStats.Font = Enum.Font.Code
endStats.Text = "TIME 00:00  •  SURVIVORS 1/1"
endStats.TextColor3 = Color3.fromRGB(205, 235, 210)
endStats.TextSize = 25
endStats.TextTransparency = 1
endStats.TextWrapped = true
endStats.ZIndex = 123
endStats.Parent = endFrame

local endHint = Instance.new("TextLabel")
endHint.Name = "EndingHint"
endHint.AnchorPoint = Vector2.new(0.5, 0.5)
endHint.Position = UDim2.fromScale(0.5, 0.72)
endHint.Size = UDim2.new(0.86, 0, 0, 32)
endHint.BackgroundTransparency = 1
endHint.Font = Enum.Font.Code
endHint.Text = "RETURNING TO BASE"
endHint.TextColor3 = Color3.fromRGB(112, 145, 120)
endHint.TextSize = 17
endHint.TextTransparency = 1
endHint.TextWrapped = true
endHint.ZIndex = 123
endHint.Parent = endFrame

local spectateBanner = Instance.new("TextLabel")
spectateBanner.Name = "SpectateBanner"
spectateBanner.AnchorPoint = Vector2.new(0.5, 1)
spectateBanner.Position = UDim2.new(0.5, 0, 1, -28)
spectateBanner.Size = UDim2.new(0.72, 0, 0, 42)
spectateBanner.BackgroundColor3 = Color3.fromRGB(3, 7, 5)
spectateBanner.BackgroundTransparency = 0.30
spectateBanner.BorderSizePixel = 0
spectateBanner.Font = Enum.Font.Code
spectateBanner.Text = "SPECTATING  •  SEARCHING FOR SIGNAL"
spectateBanner.TextColor3 = Color3.fromRGB(115, 255, 170)
spectateBanner.TextSize = 20
spectateBanner.TextWrapped = true
spectateBanner.Visible = false
spectateBanner.ZIndex = 118
spectateBanner.Parent = gui
local spectateCorner = Instance.new("UICorner")
spectateCorner.CornerRadius = UDim.new(0, 7)
spectateCorner.Parent = spectateBanner

local exitThud = Instance.new("Sound")
exitThud.Name = "ExitThresholdThud"
exitThud.SoundId = "rbxasset://sounds/bass.wav"
exitThud.Volume = 0.9
exitThud.PlaybackSpeed = 0.62
exitThud.Parent = gui
local exitChime = Instance.new("Sound")
exitChime.Name = "ExitSignalChime"
exitChime.SoundId = "rbxasset://sounds/electronicpingshort.wav"
exitChime.Volume = 0.52
exitChime.PlaybackSpeed = 0.78
exitChime.Parent = gui

local endingSerial = 0
local spectating = false
local spectateTarget = nil
local spectateClock = 0

local function formatRoundTime(seconds)
 local total = math.max(0, math.floor(tonumber(seconds) or 0))
 return string.format("%02d:%02d", math.floor(total / 60), total % 60)
end

local function validSpectateTarget(candidate)
 if not candidate or candidate == player or candidate.Parent ~= Players then return false end
 if candidate:GetAttribute("InRound") ~= true or candidate:GetAttribute("Escaped") == true then return false end
 local character = candidate.Character
 local humanoid = character and character:FindFirstChildOfClass("Humanoid")
 return humanoid ~= nil and humanoid.Health > 0
end

local function chooseSpectateTarget()
 for _, candidate in ipairs(Players:GetPlayers()) do
  if validSpectateTarget(candidate) then return candidate end
 end
 return nil
end

local function updateSpectating()
 if not spectating then return end
 if not validSpectateTarget(spectateTarget) then spectateTarget = chooseSpectateTarget() end
 local camera = workspace.CurrentCamera
 if spectateTarget and camera then
  local humanoid = spectateTarget.Character and spectateTarget.Character:FindFirstChildOfClass("Humanoid")
  if humanoid then
   camera.CameraType = Enum.CameraType.Custom
   camera.CameraSubject = humanoid
   spectateBanner.Text = "SPECTATING  •  " .. string.upper(spectateTarget.DisplayName)
  end
 else
  spectateBanner.Text = "SPECTATING  •  NO SURVIVING SIGNAL"
 end
end

local function startSpectating()
 spectating = true
 spectateTarget = nil
 spectateBanner.Visible = true
 updateSpectating()
end

local function stopSpectating()
 spectating = false
 spectateTarget = nil
 spectateBanner.Visible = false
 local camera = workspace.CurrentCamera
 local character = player.Character
 local humanoid = character and character:FindFirstChildOfClass("Humanoid")
 if camera then
  camera.CameraType = Enum.CameraType.Custom
  if humanoid then camera.CameraSubject = humanoid end
 end
end

RunService.RenderStepped:Connect(function(dt)
 if not spectating then return end
 spectateClock += dt
 if spectateClock >= 0.35 then
  spectateClock = 0
  updateSpectating()
 end
end)

local function hideRoundEnding(immediate)
 endingSerial += 1
 local token = endingSerial
 if immediate then
  endFrame.Visible = false
  endFrame.BackgroundTransparency = 1
  endFlash.BackgroundTransparency = 1
  return
 end
 TweenService:Create(endFrame, TweenInfo.new(0.42), {BackgroundTransparency = 1}):Play()
 TweenService:Create(endTitle, TweenInfo.new(0.28), {TextTransparency = 1, TextStrokeTransparency = 1}):Play()
 TweenService:Create(endStats, TweenInfo.new(0.25), {TextTransparency = 1}):Play()
 TweenService:Create(endHint, TweenInfo.new(0.25), {TextTransparency = 1}):Play()
 TweenService:Create(endLine, TweenInfo.new(0.3), {BackgroundTransparency = 1}):Play()
 task.delay(0.46, function()
  if endingSerial == token then endFrame.Visible = false end
 end)
end

local function showRoundEnding(title, stats, hint, color, temporary)
 endingSerial += 1
 local token = endingSerial
 color = color or Color3.fromRGB(115, 255, 170)
 loadingFrame.Visible = false
 queueShade.Visible = false
 label.Visible = false
 endFrame.Visible = true
 endFrame.BackgroundTransparency = 1
 endFlash.BackgroundColor3 = color
 endFlash.BackgroundTransparency = 0.08
 endTitle.Text = title
 endTitle.TextColor3 = color
 endTitle.TextTransparency = 1
 endTitle.TextStrokeTransparency = 1
 endStats.Text = stats or ""
 endStats.TextColor3 = color:Lerp(Color3.new(1, 1, 1), 0.68)
 endStats.TextTransparency = 1
 endHint.Text = hint or ""
 endHint.TextTransparency = 1
 endLine.BackgroundColor3 = color
 endLine.BackgroundTransparency = 0
 endLine.Size = UDim2.new(0, 0, 0, 2)

 exitThud:Stop()
 exitChime:Stop()
 exitThud.TimePosition = 0
 exitChime.TimePosition = 0
 exitThud:Play()
 task.delay(0.12, function() if endFrame.Visible then exitChime:Play() end end)
 TweenService:Create(endFlash, TweenInfo.new(0.7, Enum.EasingStyle.Quad), {BackgroundTransparency = 1}):Play()
 TweenService:Create(endFrame, TweenInfo.new(0.42, Enum.EasingStyle.Quad), {BackgroundTransparency = 0.08}):Play()
 TweenService:Create(endTitle, TweenInfo.new(0.48), {TextTransparency = 0, TextStrokeTransparency = 0.35}):Play()
 TweenService:Create(endStats, TweenInfo.new(0.42), {TextTransparency = 0}):Play()
 TweenService:Create(endHint, TweenInfo.new(0.55), {TextTransparency = 0}):Play()
 TweenService:Create(endLine, TweenInfo.new(0.55, Enum.EasingStyle.Quart), {Size = UDim2.new(0.70, 0, 0, 2)}):Play()

 if temporary then
  task.delay(2.75, function()
   if endingSerial ~= token then return end
   hideRoundEnding(false)
   task.delay(0.5, function()
    if player:GetAttribute("InRound") == true and (dead or player:GetAttribute("Escaped") == true) then
     startSpectating()
    end
   end)
  end)
 end
end

if RunService:IsStudio() then
 player:GetAttributeChangedSignal("DevRoundEnding"):Connect(function()
  local mode = tostring(player:GetAttribute("DevRoundEnding") or ""):lower()
  if mode:find("escape", 1, true) then
   showRoundEnding(("LEVEL " .. tostring(workspace:GetAttribute("SelectedLevel") or 1) .. " CLEARED"), "SIGNAL LOST", "WAITING FOR THE OTHERS", Color3.fromRGB(115, 255, 170), true)
  elseif mode:find("win", 1, true) then
   showRoundEnding(("LEVEL " .. tostring(workspace:GetAttribute("SelectedLevel") or 1) .. " CLEARED"), "TIME 03:42  •  SURVIVORS 2/3", "RETURNING TO BASE", Color3.fromRGB(115, 255, 170), false)
  elseif mode:find("lose", 1, true) then
   showRoundEnding("NO ONE FOUND A WAY OUT", "TIME 04:17  •  SURVIVORS 0/3", "RETURNING TO BASE", Color3.fromRGB(255, 82, 72), false)
  elseif mode:find("hide", 1, true) then
   hideRoundEnding(true)
  end
 end)
end

local loadingSequenceFinished = false
local serverReadyForEntry = false
local loadingClock = 0
local loadingBaseText = "LOCATING ANOMALOUS SPACE"

RunService.RenderStepped:Connect(function(dt)
	if not loadingFrame.Visible then return end
	loadingClock += dt
	local dots = string.rep(".", math.floor(loadingClock * 2) % 4)
	loadingStatus.Text = loadingBaseText .. dots
end)

local function finishLoadingWhenReady()
	if loadingSequenceFinished and serverReadyForEntry then
		loadingFrame.Visible = false
	end
end

task.spawn(function()
	local stages = {
		"LOCATING ANOMALOUS SPACE",
		"ESTABLISHING ENTRY VECTOR",
		"STABILIZING ENTRY ENERGY",
		"VERIFYING CONTAINMENT",
	}
	for _, stage in ipairs(stages) do
		loadingBaseText = stage
		loadingClock = 0
		task.wait(1.35)
	end

	loadingTitle.Text = "> ENTRY STABILIZED SUCCESSFULLY"
	loadingTitle.TextColor3 = Color3.fromRGB(125, 255, 155)
	loadingBaseText = "MISSION IS A GO"
	loadingClock = 0
	task.wait(1.6)
	loadingSequenceFinished = true
	finishLoadingWhenReady()
end)

-- Quiet built-in terminal key click; no uploaded audio asset required.
local typeSound = Instance.new("Sound")
typeSound.Name = "TerminalType"
typeSound.SoundId = "rbxasset://sounds/clickfast.wav"
typeSound.Volume = 0.12
typeSound.PlaybackSpeed = 1.35
typeSound.Parent = gui

local DEFAULT_TEXT = Color3.fromRGB(235, 232, 222)
local DEFAULT_SIZE = 26
local DEFAULT_FONT = Enum.Font.GothamMedium
local COMPACT_SIZE = UDim2.new(0, 620, 0, 48)
local OBJECTIVE_SIZE = UDim2.new(0, 600, 0, 154)

local function setMsg(text, color)
	label.TextSize = DEFAULT_SIZE
	label.Font = DEFAULT_FONT
	label.TextTransparency = 0
	label.TextStrokeTransparency = 1
	label.Size = COMPACT_SIZE
	label.BackgroundTransparency = 0.85
	label.Text = text or ""
	label.TextColor3 = color or DEFAULT_TEXT
	label.Visible = text ~= nil and text ~= ""
end

local objectiveRun = 0
local elevatorBriefingStarted = false

local function playObjective()
	objectiveRun += 1
	local run = objectiveRun

	task.spawn(function()
		setMsg("")
		label.TextColor3 = DEFAULT_TEXT
		label.Size = OBJECTIVE_SIZE
		label.BackgroundTransparency = 0.72
		label.Visible = true

		local function alive()
			return run == objectiveRun
		end

		local function keyClick(speed)
			typeSound:Stop()
			typeSound.TimePosition = 0
			typeSound.PlaybackSpeed = speed or (1.25 + math.random() * 0.2)
			typeSound:Play()
		end

		local function typeInto(base, text, speed)
			for i = 1, #text do
				if not alive() then return nil end
				label.Text = base .. text:sub(1, i) .. "."
				keyClick()
				task.wait(speed or 0.03)
			end
			label.Text = base .. text
			return base .. text
		end

		if workspace:GetAttribute("SelectedLevel") == 2 then
			-- Level 2 (Sunken Leisure Complex) runs its own alert-based intro
			-- from its objective controller; no typewriter here.
			return
		end
			local built = typeInto("", "Find ZYNTRA power relays", 0.03)
		if not built then return end
		task.wait(0.6)

		built = typeInto(built .. string.char(10), "Extract fuses and power every fuse box", 0.03)
		if not built then return end
		task.wait(0.6)

		built = typeInto(built .. string.char(10), "Pull all levers to power the exit door", 0.03)
		if not built then return end
		task.wait(0.5)

		built = typeInto(built .. string.char(10), "Then escape", 0.03)
		if not built then return end

		-- Blink a terminal-style dot for about three seconds.
		for _ = 1, 4 do
			if not alive() then return end
			label.Text = built .. "."
			task.wait(0.15)
			label.Text = built
			task.wait(0.15)
		end

		if not alive() then return end
		label.Text = ""

		local warning = typeInto("", "If you hear it...", 0.035)
		if not warning then return end
		task.wait(0.6)

		warning = typeInto(warning .. string.char(10), "Or even worse...", 0.035)
		if not warning then return end
		task.wait(0.6)

		warning = typeInto(warning .. " ", "see it...", 0.035)
		if not warning then return end
		task.wait(0.8)

		if not alive() then return end
		label.Text = ""
		label.TextColor3 = Color3.fromRGB(255, 25, 25)
		label.TextSize = 96
		label.Font = Enum.Font.GothamBlack
		label.TextStrokeColor3 = Color3.fromRGB(255, 0, 0)
		label.TextStrokeTransparency = 0.08

		for i = 1, 3 do
			if not alive() then return end
			label.Text = ("RUN"):sub(1, i)
			keyClick(0.9)
			task.wait(0.12)
		end

		-- RUN stays visible while the exclamation points and glow blink.
		for _ = 1, 2 do
			if not alive() then return end
			label.Text = "! RUN !"
			label.TextTransparency = 0
			label.TextStrokeTransparency = 0.06
			task.wait(0.12)
			label.Text = "  RUN  "
			label.TextTransparency = 0.08
			label.TextStrokeTransparency = 0.4
			task.wait(0.12)
		end

		-- Give RUN the same short readable beat as the other briefing lines. The
		-- sequence still starts only on an elevator countdown event, but it no
		-- longer hangs on screen until the doors open.
		if not alive() then return end
		label.Text = "! RUN !"
		task.wait(0.55)
		if alive() then setMsg("") end
	end)
end

-- Old, unstable elevator camera motion. It peaks after the one-second
-- startup delay, then decays smoothly for ten seconds without moving the player.
local SHAKE_BIND = "UnstableElevatorCamera"
local SHAKE_DURATION = 10
local SETTLE_DURATION = 1
local shakeSequence = 0
local shakeScheduled = false

local function scheduleElevatorShake()
	if shakeScheduled then return end
	shakeScheduled = true
	shakeSequence += 1
	local token = shakeSequence

	task.delay(1, function()
		if token ~= shakeSequence then return end
		local started = os.clock()
		local elevator = workspace:FindFirstChild("Elevator")
		local cabinLights = {}
		local doorBases = {}

		if elevator then
			for _, item in ipairs(elevator:GetDescendants()) do
				if item:IsA("PointLight") then
					cabinLights[#cabinLights + 1] = {
						light = item, brightness = item.Brightness, range = item.Range,
						enabled = item.Enabled, panel = item.Parent,
						panelColor = item.Parent:IsA("BasePart") and item.Parent.Color or nil,
					}
				end
			end
			for _, name in ipairs({ "DoorL", "DoorR" }) do
				local door = elevator:FindFirstChild(name)
				if door and door:IsA("BasePart") then
					doorBases[#doorBases + 1] = { part = door, cf = door.CFrame }
				end
			end
		end

		local restored = false
		local function restoreCabin()
			if restored then return end
			restored = true
			for _, data in ipairs(cabinLights) do
				if data.light.Parent then
					data.light.Brightness = data.brightness
					data.light.Range = data.range
					data.light.Enabled = data.enabled
					if data.panelColor and data.panel:IsA("BasePart") then data.panel.Color = data.panelColor end
				end
			end
			for _, data in ipairs(doorBases) do
				if data.part.Parent then data.part.CFrame = data.cf end
			end
		end

		RunService:UnbindFromRenderStep(SHAKE_BIND)
		RunService:BindToRenderStep(SHAKE_BIND, Enum.RenderPriority.Camera.Value + 2, function()
			local elapsed = os.clock() - started
			if elapsed >= SHAKE_DURATION + SETTLE_DURATION or token ~= shakeSequence then
				restoreCabin()
				RunService:UnbindFromRenderStep(SHAKE_BIND)
				return
			end

			local camera = workspace.CurrentCamera
			if not camera then return end
			local settling = elapsed >= SHAKE_DURATION
			local settleProgress = math.clamp(elapsed - SHAKE_DURATION, 0, SETTLE_DURATION) / SETTLE_DURATION
			local fade = math.max(1 - elapsed / SHAKE_DURATION, 0) ^ 1.35
			local t = os.clock()

			-- Layered noise: low mechanical sway plus a restrained high-frequency rattle.
			local side = (math.noise(t * 3.2, 0) * 0.055 + math.noise(t * 11.0, 5) * 0.018) * fade
			local lift = (math.noise(0, t * 4.0) * 0.075 + math.noise(8, t * 13.0) * 0.022) * fade
			local roll = math.rad(math.noise(t * 2.7, 14) * 0.22 * fade)
			local pitch = math.rad(math.noise(21, t * 3.0) * 0.12 * fade)

			if settling then
				-- One firm but controlled downward stop, followed by a soft recovery.
				local joltPhase = math.clamp(settleProgress / 0.62, 0, 1)
				lift = -math.sin(joltPhase * math.pi) * 0.16
				side = 0
				roll = 0
				pitch = math.rad(math.sin(joltPhase * math.pi) * 0.28)
			end

			camera.CFrame = camera.CFrame
				* CFrame.new(side, lift, 0)
				* CFrame.Angles(pitch, 0, roll)

			-- Cabin lamp follows the machinery load, with two brief early brownouts.
			local brownout = (elapsed > 1.15 and elapsed < 1.28)
				or (elapsed > 2.45 and elapsed < 2.58)
			local lampWave = 1 + math.noise(t * 3.5, 40) * 0.14 * fade
			if settling then
				-- Dim on impact, then stabilize cleanly through the one-second pause.
				local smooth = settleProgress * settleProgress * (3 - 2 * settleProgress)
				lampWave = 0.42 + 0.58 * smooth
				brownout = false
			end
			for _, data in ipairs(cabinLights) do
				if data.light.Parent then
					data.light.Enabled = data.enabled
					data.light.Brightness = data.brightness * (brownout and 0.12 or lampWave)
					data.light.Range = data.range * (brownout and 0.72 or (1 + 0.03 * fade))
					if data.panelColor and data.panel:IsA("BasePart") then
						data.panel.Color = brownout and Color3.fromRGB(75, 72, 64)
							or data.panelColor:Lerp(Color3.fromRGB(255, 244, 220), 0.08 * fade)
					end
				end
			end

			-- Tiny local door rattle; the original CFrames are restored exactly.
			for index, data in ipairs(doorBases) do
				if data.part.Parent then
					if settling then
						data.part.CFrame = data.cf
					else
						local direction = index == 1 and -1 or 1
						local dx = math.noise(t * 14, index * 7) * 0.025 * fade
						local dy = math.noise(index * 9, t * 12) * 0.018 * fade
						local dz = direction * math.noise(t * 10, index * 13) * 0.035 * fade
						data.part.CFrame = data.cf * CFrame.new(dx, dy, dz)
					end
				end
			end
		end)
	end)
end
-- dead is declared with the player state above so the ending and spectate UI share it.

remote.OnClientEvent:Connect(function(ev, a, b, c, d, e)
	-- GameManager emits an elevator countdown tick every second. Those ticks must
	-- not invalidate the objective coroutine that is meant to fill the ride.
	if ev ~= "start" and ev ~= "elevator" then
		objectiveRun += 1
	end

	if ev == "lobby" then
		hideRoundEnding(true)
		stopSpectating()
		dead = false
		loadingFrame.Visible = false
		queueShade.Visible = false
		queueStation = nil
		queueSubmitting = false
		setMsg("") -- the in-world sign carries the idle lobby instruction

	elseif ev == "queuehost" then
		loadingFrame.Visible = false
		queueStation = tonumber(a)
		queueSizeValue = math.clamp(math.floor(tonumber(b) or 6), 1, 6)
		queuePrivacyValue = c == "friends" and "friends" or "public"
		queueSubmitting = false
		refreshQueuePanel()
		queueShade.Visible = true
		setMsg("")

	elseif ev == "queueconfigured" then
		queueShade.Visible = false
		queueSubmitting = false
		local maximum = math.clamp(math.floor(tonumber(a) or 6), 1, 6)
		local privacyText = b == "friends" and "FRIENDS ONLY" or "PUBLIC"
		local stationNumber = tonumber(c)
		local stationText = stationNumber and ("STATION " .. stationNumber .. "  •  ") or ""
		setMsg(stationText .. "PARTY OPEN  •  MAX " .. maximum .. "  •  " .. privacyText, Color3.fromRGB(120, 255, 175))
		label.Size = UDim2.new(0, 700, 0, 68)

	elseif ev == "queueconfigclosed" then
		queueShade.Visible = false
		queueStation = nil
		queueSubmitting = false
		setMsg("")

	elseif ev == "queuewaitinghost" then
		queueShade.Visible = false
		local stationNumber = tonumber(a)
		setMsg((stationNumber and ("STATION " .. stationNumber .. "  •  ") or "") .. "HOST CHOOSING PARTY SETTINGS", Color3.fromRGB(220, 210, 155))
		label.Size = UDim2.new(0, 700, 0, 68)

	elseif ev == "queueprivate" then
		queueShade.Visible = false
		local stationNumber = tonumber(a)
		local hostName = tostring(b or "HOST")
		setMsg((stationNumber and ("STATION " .. stationNumber .. "  •  ") or "") .. "FRIENDS ONLY" .. string.char(10) .. "ONLY FRIENDS OF " .. string.upper(hostName) .. " CAN JOIN", Color3.fromRGB(255, 205, 110))
		label.Size = UDim2.new(0, 700, 0, 92)

	elseif ev == "queuefull" then
		queueShade.Visible = false
		local stationNumber = tonumber(a)
		local maximum = math.clamp(math.floor(tonumber(b) or 6), 1, 6)
		setMsg((stationNumber and ("STATION " .. stationNumber .. "  •  ") or "") .. "PARTY FULL  •  " .. maximum .. "/" .. maximum, Color3.fromRGB(255, 205, 110))
		label.Size = UDim2.new(0, 700, 0, 68)

	elseif ev == "lobbycountdown" then
		loadingFrame.Visible = false
		local count = b or 0
		local stationNumber = tonumber(c)
		local maximum = math.clamp(math.floor(tonumber(d) or 6), 1, 6)
		local privacyText = e == "friends" and "FRIENDS ONLY" or "PUBLIC"
		local stationText = stationNumber and ("STATION " .. stationNumber .. "  •  ") or ""
		setMsg(stationText .. "GAME BEGINS IN " .. tostring(a) .. string.char(10)
			.. count .. "/" .. maximum .. " READY  •  " .. privacyText, Color3.fromRGB(120, 255, 175))
		label.Size = UDim2.new(0, 700, 0, 92)

	elseif ev == "lobbycancel" then
		loadingFrame.Visible = false
		queueShade.Visible = false
		queueStation = nil
		queueSubmitting = false
		setMsg("COUNTDOWN CANCELLED — ENTER THE SQUARE TO TRY AGAIN", Color3.fromRGB(210, 230, 225))

	elseif ev == "spectating" then
		loadingFrame.Visible = false
		queueShade.Visible = false
		setMsg("GAME IN PROGRESS — WAIT FOR THE NEXT GROUP", Color3.fromRGB(255, 215, 120))

	elseif ev == "loadinggame" then
		objectiveRun += 1
		elevatorBriefingStarted = false
		hideRoundEnding(true)
		stopSpectating()
		dead = false
		queueShade.Visible = false
		queueStation = nil
		queueSubmitting = false
		setMsg("")
		loadingTitle.Text = "> ENTERING ANOMALOUS SPACE"
		loadingTitle.TextColor3 = Color3.fromRGB(105, 230, 135)
		loadingBaseText = "GENERATING WORLD"
		loadingClock = 0
		loadingFrame.Visible = true

	elseif ev == "loadfailed" then
		loadingFrame.Visible = false
		setMsg("WORLD GENERATION FAILED — RETURNING TO LOBBY", Color3.fromRGB(255, 100, 100))

	elseif ev == "waiting" then
		elevatorBriefingStarted = false
		setMsg("Waiting for players…")

	elseif ev == "poolaccess" then
		loadingFrame.Visible = false
		serverReadyForEntry = true
		finishLoadingWhenReady()
		dead = false
		setMsg("POOL ACCESS READY", Color3.fromRGB(105, 230, 210))

	elseif ev == "elevator" then
		loadingFrame.Visible = false
		serverReadyForEntry = true
		finishLoadingWhenReady()
		scheduleElevatorShake()
		dead = false
		if not elevatorBriefingStarted then
			elevatorBriefingStarted = true
			playObjective()
		end

	elseif ev == "start" then
		hideRoundEnding(true)
		stopSpectating()
		shakeScheduled = false
		serverReadyForEntry = true
		finishLoadingWhenReady()
		dead = false
		objectiveRun += 1
		setMsg("")

	elseif ev == "death" then
		if a == player.Name then
			dead = true
			task.delay(0.85, function()
				if dead and player:GetAttribute("InRound") == true then startSpectating() end
			end)
		elseif spectating and spectateTarget and a == spectateTarget.Name then
			spectateTarget = nil
		end

	elseif ev == "escape" then
		if a == player.Name then
			showRoundEnding(
				("LEVEL " .. tostring(workspace:GetAttribute("SelectedLevel") or 1) .. " CLEARED"),
				"SIGNAL LOST",
				"WAITING FOR THE OTHERS",
				Color3.fromRGB(115, 255, 170),
				true
			)
		elseif player:GetAttribute("Escaped") ~= true then
			local msg = "One player has successfully escaped. Follow the green lights to safety."
			setMsg(msg, Color3.fromRGB(150, 235, 175))
			task.delay(8, function()
				if label.Text == msg then setMsg("") end
			end)
		end

	elseif ev == "lose" then
		stopSpectating()
		local totalPlayers = math.max(1, math.floor(tonumber(c) or 1))
		showRoundEnding(
			"NO ONE FOUND A WAY OUT",
			"TIME " .. formatRoundTime(a) .. "  •  SURVIVORS 0/" .. totalPlayers,
			"RETURNING TO BASE",
			Color3.fromRGB(255, 82, 72),
			false
		)

	elseif ev == "win" then
		stopSpectating()
		local survivors = math.max(0, math.floor(tonumber(b) or 0))
		local totalPlayers = math.max(1, math.floor(tonumber(c) or math.max(1, survivors)))
		showRoundEnding(
			dead and "THE OTHERS FOUND A WAY OUT" or ("LEVEL " .. tostring(workspace:GetAttribute("SelectedLevel") or 1) .. " CLEARED"),
			"TIME " .. formatRoundTime(a) .. "  •  SURVIVORS " .. survivors .. "/" .. totalPlayers,
			"RETURNING TO BASE",
			Color3.fromRGB(115, 255, 170),
			false
		)
	end
end)

-- Responsive objective layout verified in play test.


-- ── MIMIC APPARITION ───────────────────────────────────────────────────────
-- Client-only: only the isolated target sees or hears this social scare.
local MimicPathfinding = game:GetService("PathfindingService")
local MimicTweenService = game:GetService("TweenService")

local MIMIC_ISOLATION_RADIUS = 70
local MIMIC_FOLLOW_DISTANCE = 10
local MIMIC_FLEE_TRIGGER = 10
local MIMIC_DESPAWN_DISTANCE = 110
local activeMimic = nil
local mimicSerial = 0
local nextMimicChance = os.clock() + math.random(35, 65)

local function mimicLocalAlive()
 local char = player.Character
 local hum = char and char:FindFirstChildOfClass("Humanoid")
 local root = char and char:FindFirstChild("HumanoidRootPart")
 return char, hum, root, hum and hum.Health > 0 and root ~= nil
end

local function mimicTeammateNearby(root)
 for _, other in ipairs(Players:GetPlayers()) do
  if other ~= player and other:GetAttribute("Escaped") ~= true then
   local char = other.Character
   local hum = char and char:FindFirstChildOfClass("Humanoid")
   local otherRoot = char and char:FindFirstChild("HumanoidRootPart")
   if hum and hum.Health > 0 and otherRoot
    and (otherRoot.Position - root.Position).Magnitude < MIMIC_ISOLATION_RADIUS then
    return true
   end
  end
 end
 return false
end

local function mimicAppearanceSource()
 local choices = {}
 for _, other in ipairs(Players:GetPlayers()) do
  if other ~= player then
   local char = other.Character
   local hum = char and char:FindFirstChildOfClass("Humanoid")
   if char and hum and hum.Health > 0 then choices[#choices + 1] = other end
  end
 end
 return #choices > 0 and choices[math.random(#choices)] or player
end

local function mimicVisible(model)
 local camera = workspace.CurrentCamera
 local target = model and (model:FindFirstChild("Head") or model:FindFirstChild("HumanoidRootPart"))
 if not camera or not target then return false end
 local screen, onScreen = camera:WorldToViewportPoint(target.Position)
 if not onScreen or screen.Z <= 0 then return false end
 local delta = target.Position - camera.CFrame.Position
 if delta.Magnitude > 90 or camera.CFrame.LookVector:Dot(delta.Unit) < 0.5 then return false end
 local rp = RaycastParams.new()
 rp.FilterType = Enum.RaycastFilterType.Exclude
 local exclude = { model }
 if player.Character then exclude[#exclude + 1] = player.Character end
 rp.FilterDescendantsInstances = exclude
 return workspace:Raycast(camera.CFrame.Position, delta, rp) == nil
end

local function mimicSpawnBehind(root)
 local maze = workspace:FindFirstChild("Maze")
 if not maze then return nil end
 local down = RaycastParams.new()
 down.FilterType = Enum.RaycastFilterType.Include
 down.FilterDescendantsInstances = { maze }
 for _ = 1, 12 do
  local guess = root.Position - root.CFrame.LookVector * math.random(16, 22)
   + root.CFrame.RightVector * math.random(-6, 6)
  local hit = workspace:Raycast(guess + Vector3.new(0, 3, 0), Vector3.new(0, -12, 0), down)
  if hit and hit.Normal.Y > 0.6 then
   local pos = hit.Position + Vector3.new(0, 3, 0)
   local toSpawn = pos - root.Position
   if toSpawn.Magnitude > 1 and root.CFrame.LookVector:Dot(toSpawn.Unit) < -0.25 then
    local path = MimicPathfinding:CreatePath({AgentRadius=2, AgentHeight=5, AgentCanJump=false})
    local ok = pcall(function() path:ComputeAsync(pos, root.Position) end)
    if ok and path.Status == Enum.PathStatus.Success then return pos end
   end
  end
 end
 return nil
end

local function mimicFade(model)
 if not model or not model.Parent then return end
 for _, item in ipairs(model:GetDescendants()) do
  if item:IsA("BasePart") or item:IsA("Decal") then
   MimicTweenService:Create(item, TweenInfo.new(0.1), {Transparency=1}):Play()
  elseif item:IsA("Sound") then
   MimicTweenService:Create(item, TweenInfo.new(0.08), {Volume=0}):Play()
  end
 end
 task.delay(0.12, function() if model then model:Destroy() end end)
end

local function mimicAnimationId(character, keyword)
 for _, item in ipairs(character:GetDescendants()) do
  if item:IsA("Animation") and item.Name:lower():find(keyword, 1, true)
   and item.AnimationId ~= "" then return item.AnimationId end
 end
 return nil
end

local function mimicBuild(sourcePlayer, spawnPos)
 local sourceChar = sourcePlayer.Character
 if not sourceChar then return nil end
 local rigIsR15 = sourceChar:FindFirstChild("UpperTorso") ~= nil
 local walkId = mimicAnimationId(sourceChar, "walk") or (rigIsR15 and "rbxassetid://507777826" or "rbxassetid://180426354")
 local runId = mimicAnimationId(sourceChar, "run") or (rigIsR15 and "rbxassetid://507767714" or "rbxassetid://180426354")
 local wasArchivable = sourceChar.Archivable
 sourceChar.Archivable = true
 local model = sourceChar:Clone()
 sourceChar.Archivable = wasArchivable
 if not model then return nil end
 model.Name = "MimicApparition"

 for _, item in ipairs(model:GetDescendants()) do
  if item:IsA("LuaSourceContainer") or item:IsA("Tool") or item:IsA("ForceField") or item:IsA("Sound") then
   item:Destroy()
  elseif item:IsA("BasePart") then
   item.Anchored = false
   item.CanCollide = false
   item.CanTouch = false
   item.CanQuery = false
   item.Massless = true
  end
 end

 local hum = model:FindFirstChildOfClass("Humanoid")
 local root = model:FindFirstChild("HumanoidRootPart")
 if not hum or not root then model:Destroy() return nil end
 hum.DisplayDistanceType = Enum.HumanoidDisplayDistanceType.None
 hum.HealthDisplayType = Enum.HumanoidHealthDisplayType.AlwaysOff
 hum.JumpPower = 0
 hum.AutoRotate = true
 model.PrimaryPart = root
 model.Parent = workspace
 model:PivotTo(CFrame.new(spawnPos))

 local animator = hum:FindFirstChildOfClass("Animator") or Instance.new("Animator", hum)
 local function loadTrack(id)
  if not id then return nil end
  local anim = Instance.new("Animation")
  anim.AnimationId = id
  local ok, track = pcall(function() return animator:LoadAnimation(anim) end)
  anim:Destroy()
  if ok and track then
   track.Looped = true
   track.Priority = Enum.AnimationPriority.Movement
   return track
  end
  return nil
 end
 local walkTrack = loadTrack(walkId)
 local runTrack = loadTrack(runId)
 local steps = Instance.new("Sound")
 steps.Name = "MimicFootsteps"
 steps.SoundId = "rbxasset://sounds/action_footsteps_plastic.mp3"
 steps.Volume = 0.27 -- 50% louder than before
 local mimicStepSpeed = 0.78 + math.random() * 0.10
 steps.PlaybackSpeed = mimicStepSpeed
 steps.Looped = true
 steps.RollOffMinDistance = 5
 steps.RollOffMaxDistance = 46
 steps.Parent = root

 local rightShoulder = model:FindFirstChild("RightShoulder", true) or model:FindFirstChild("Right Shoulder", true)
 local leftShoulder = model:FindFirstChild("LeftShoulder", true) or model:FindFirstChild("Left Shoulder", true)
 local rightElbow = model:FindFirstChild("RightElbow", true)
 local leftElbow = model:FindFirstChild("LeftElbow", true)
 local neck = model:FindFirstChild("Neck", true)
 local waist = model:FindFirstChild("Waist", true)
 local poseMotors = {rightShoulder, leftShoulder, rightElbow, leftElbow, neck, waist}

 local function clearStillPose()
  for _, motor in ipairs(poseMotors) do
   if motor and motor:IsA("Motor6D") then motor.Transform = CFrame.identity end
  end
 end

 local function applyStillPose()
  -- Deliberately simple: arms hanging beside the torso, shoulders slightly
  -- lowered and the head subtly dipped. No borrowed idle animation or swaying.
  if rightShoulder and rightShoulder:IsA("Motor6D") then
   rightShoulder.Transform = CFrame.Angles(math.rad(7), 0, math.rad(82))
  end
  if leftShoulder and leftShoulder:IsA("Motor6D") then
   leftShoulder.Transform = CFrame.Angles(math.rad(7), 0, math.rad(-82))
  end
  if rightElbow and rightElbow:IsA("Motor6D") then
   rightElbow.Transform = CFrame.Angles(math.rad(-7), 0, 0)
  end
  if leftElbow and leftElbow:IsA("Motor6D") then
   leftElbow.Transform = CFrame.Angles(math.rad(-7), 0, 0)
  end
  if neck and neck:IsA("Motor6D") then
   neck.Transform = CFrame.Angles(math.rad(6), 0, 0)
  end
  if waist and waist:IsA("Motor6D") then
   waist.Transform = CFrame.Angles(math.rad(-3), 0, 0)
  end
 end

 local moving, fast = nil, nil
 local function setMoving(on, sprinting)
  if moving == on and fast == sprinting then return end
  moving, fast = on, sprinting
  if on then clearStillPose() end
  if walkTrack then
   if on and not sprinting then walkTrack:Play(0.12) else walkTrack:Stop(0.08) end
  end
  if runTrack then
   if on and sprinting then runTrack:Play(0.06) else runTrack:Stop(0.08) end
  end
  if not on then
   applyStillPose()
   task.delay(0.1, function()
    if model.Parent and moving == false then applyStillPose() end
   end)
  end
  if on then
   steps.PlaybackSpeed = sprinting and 1.23 or mimicStepSpeed
   if not steps.IsPlaying then
    -- A random phase and delayed start keep these steps unmistakably separate
    -- from the local player's own walking loop.
    local startToken = os.clock()
    steps:SetAttribute("StartToken", startToken)
    task.delay(0.25 + math.random() * 0.45, function()
     if workspace:GetAttribute("SelectedLevel") ~= 2
      and model.Parent and moving == true and steps:GetAttribute("StartToken") == startToken then
      steps.TimePosition = math.random() * 0.28
      steps:Play()
     end
    end)
   end
  else
   steps:SetAttribute("StartToken", os.clock())
   steps:Stop()
  end
 end
 setMoving(false, false)
 return {model=model, hum=hum, root=root, setMoving=setMoving}
end

local function mimicGuide(mimic, goal)
 local path = MimicPathfinding:CreatePath({AgentRadius=2, AgentHeight=5, AgentCanJump=false})
 local ok = pcall(function() path:ComputeAsync(mimic.root.Position, goal) end)
 if ok and path.Status == Enum.PathStatus.Success then
  local points = path:GetWaypoints()
  local point = points[math.min(3, #points)]
  if point then mimic.hum:MoveTo(point.Position) return end
 end
 mimic.hum:MoveTo(goal)
end

local function mimicRun(spawnPos, devForced)
 mimicSerial += 1
 local token = mimicSerial
 local mimic = mimicBuild(mimicAppearanceSource(), spawnPos)
 if not mimic then return end
 activeMimic = mimic
 local noticed, fleeing = false, false
 local lookedFor, lastPath = 0, 0
 local unseenSince = nil

 task.spawn(function()
  while activeMimic == mimic and mimic.model.Parent and token == mimicSerial do
   local dt = task.wait(0.08)
   local _, playerHum, playerRoot, alive = mimicLocalAlive()
   if (not workspace:GetAttribute("RoundActive") and not devForced) or not alive
    or (player:GetAttribute("Escaped") == true and not devForced) then break end
   local distance = (mimic.root.Position - playerRoot.Position).Magnitude

   if mimicVisible(mimic.model) then
    lookedFor += dt
    unseenSince = nil
   else
    lookedFor = 0
    if fleeing then unseenSince = unseenSince or os.clock() end
   end
   -- The instant the player gets a clear look, the Mimic bolts.
   if not noticed and lookedFor >= 0.1 then
    noticed = true
    fleeing = true
    mimic.hum.WalkSpeed = math.max(playerHum.WalkSpeed * 3.5, 56)
    mimic.setMoving(true, true)
   end

   if fleeing then
    mimic.setMoving(true, true)
    if os.clock() - lastPath > 0.22 then
     lastPath = os.clock()
     local away = mimic.root.Position - playerRoot.Position
     away = Vector3.new(away.X, 0, away.Z)
     if away.Magnitude < 1 then away = -playerRoot.CFrame.LookVector end
     local lateral = Vector3.new(-away.Z, 0, away.X).Unit * math.random(-12, 12)
     mimicGuide(mimic, mimic.root.Position + away.Unit * 82 + lateral)
    end
    if distance >= MIMIC_DESPAWN_DISTANCE
     or (unseenSince and os.clock() - unseenSince > 0.3) then break end
   elseif not noticed then
    mimic.hum.WalkSpeed = math.max(playerHum.WalkSpeed * 0.9, 8)
    local goal = playerRoot.Position - playerRoot.CFrame.LookVector * MIMIC_FOLLOW_DISTANCE
    if distance > MIMIC_FOLLOW_DISTANCE + 3 then
     mimic.setMoving(true, false)
     if os.clock() - lastPath > 0.8 then lastPath=os.clock(); mimicGuide(mimic, goal) end
    else
     mimic.setMoving(false, false)
     mimic.hum:MoveTo(mimic.root.Position)
    end
   else
    mimic.setMoving(false, false)
   end
  end
  mimic.setMoving(false, false)
  if activeMimic == mimic then activeMimic = nil end
  mimicFade(mimic.model)
 end)
end

-- Studio-only Mimic test command. The close-spawn search starts below the
-- ceiling, checks for a clear floor and sightline, and never silently drops the command.
local lastMimicDevSpawn = 0
local function mimicDevSpawnBehind(root, character)
 local forward = Vector3.new(root.CFrame.LookVector.X, 0, root.CFrame.LookVector.Z)
 local right = Vector3.new(root.CFrame.RightVector.X, 0, root.CFrame.RightVector.Z)
 if forward.Magnitude < 0.01 then forward = Vector3.new(0, 0, -1) else forward = forward.Unit end
 if right.Magnitude < 0.01 then right = Vector3.new(1, 0, 0) else right = right.Unit end

 local rayParams = RaycastParams.new()
 rayParams.FilterType = Enum.RaycastFilterType.Exclude
 rayParams.FilterDescendantsInstances = { character }
 rayParams.IgnoreWater = true
 local overlapParams = OverlapParams.new()
 overlapParams.FilterType = Enum.RaycastFilterType.Exclude
 overlapParams.FilterDescendantsInstances = { character }
 overlapParams.MaxParts = 20

 for _ = 1, 18 do
  local guess = root.Position - forward * math.random(8, 11) + right * math.random(-3, 3)
  -- Start below the maze ceiling so the ceiling can never be mistaken for the floor.
  local hit = workspace:Raycast(guess + Vector3.new(0, 3, 0), Vector3.new(0, -12, 0), rayParams)
  if hit and hit.Normal.Y > 0.65 and math.abs(hit.Position.Y - root.Position.Y) <= 6 then
   local spawnPos = hit.Position + Vector3.new(0, 3, 0)
   local blocked = false
   for _, part in ipairs(workspace:GetPartBoundsInBox(CFrame.new(spawnPos), Vector3.new(3, 5, 3), overlapParams)) do
    if part:IsA("BasePart") and part.CanCollide then blocked = true break end
   end
   local eye = spawnPos + Vector3.new(0, 1.5, 0)
   local target = root.Position + Vector3.new(0, 1.5, 0)
   local wall = workspace:Raycast(eye, target - eye, rayParams)
   if not blocked and not wall then return spawnPos end
  end
 end
 return nil
end

local function devSpawnMimicNow()
 if not RunService:IsStudio() or os.clock() - lastMimicDevSpawn < 0.6 then return end
 lastMimicDevSpawn = os.clock()
 local char, _, root, alive = mimicLocalAlive()
 if not alive then warn("[Mimic Dev] Player is not alive") return end

 if activeMimic then
  mimicSerial += 1
  local previous = activeMimic
  activeMimic = nil
  mimicFade(previous.model)
 end

 local spawnPos = mimicDevSpawnBehind(root, char)
 if not spawnPos then
  warn("[Mimic Dev] No clear floor 8-11 studs behind the player — move away from the wall and retry")
  return
 end

 nextMimicChance = os.clock() + 120
 mimicRun(spawnPos, true)
 print(string.format("[Mimic Dev] Spawned %.1f studs behind %s", (spawnPos - root.Position).Magnitude, player.Name))
end

if RunService:IsStudio() then
 local TextChatService = game:GetService("TextChatService")
 local existingCommand = TextChatService:FindFirstChild("DevSpawnMimic")
 if existingCommand then existingCommand:Destroy() end
 local devCommand = Instance.new("TextChatCommand")
 devCommand.Name = "DevSpawnMimic"
 devCommand.PrimaryAlias = "/spawn"
 devCommand.SecondaryAlias = "/spawnmimic"
 devCommand.AutocompleteVisible = true
 devCommand.Parent = TextChatService
 -- Roblox may pass either the full text or only the arguments here. Because this
 -- command exists only in Studio, either alias always means "spawn the Mimic".
 devCommand.Triggered:Connect(function()
  devSpawnMimicNow()
 end)

 player.Chatted:Connect(function(message)
  message = message:lower():gsub("%s+", " ")
  if message == "/spawn mimic" or message == "/spawnmimic" or message == "/mimic" then
   devSpawnMimicNow()
  end
 end)
 player:GetAttributeChangedSignal("DevSpawnMimic"):Connect(devSpawnMimicNow)
end

task.spawn(function()
 while true do
  task.wait(5)
  if activeMimic and (not activeMimic.model or not activeMimic.model.Parent) then activeMimic=nil end
  local _, _, root, alive = mimicLocalAlive()
  if not activeMimic and workspace:GetAttribute("RoundActive") and alive
   and player:GetAttribute("Escaped") ~= true and not mimicTeammateNearby(root)
   and os.clock() >= nextMimicChance then
   nextMimicChance = os.clock() + math.random(15, 28)
   if math.random() < 0.45 then
    local spawnPos = mimicSpawnBehind(root)
    if spawnPos then
     nextMimicChance = os.clock() + math.random(100, 180)
     mimicRun(spawnPos)
    end
   end
  end
 end
end)

workspace:GetAttributeChangedSignal("RoundActive"):Connect(function()
 if not workspace:GetAttribute("RoundActive") and activeMimic then
  mimicSerial += 1
  local old = activeMimic
  activeMimic = nil
  mimicFade(old.model)
 end
end)


-- ── AMBIENT SCARE DIRECTOR ────────────────────────────────────────────────
-- Client-only, non-lethal scares. The pace rises sharply once lever power
-- is committed, and every effect stays private to the targeted player.
local AmbientTweenService = game:GetService("TweenService")
local AmbientDebris = game:GetService("Debris")
local ambientBusy = false
local ambientLastKind = nil
local ambientNextAt = os.clock() + math.random(14, 22)
local ambientLeverPressureUntil = 0

local function ambientCharacter()
 local character = player.Character
 local humanoid = character and character:FindFirstChildOfClass("Humanoid")
 local root = character and character:FindFirstChild("HumanoidRootPart")
 return character, humanoid, root, humanoid and humanoid.Health > 0 and root ~= nil
end

local function ambientCanScare()
 local _, _, _, alive = ambientCharacter()
 return alive
  and workspace:GetAttribute("RoundActive") == true
  and player:GetAttribute("InRound") == true
  and player:GetAttribute("Escaped") ~= true
end

local function ambientFlatUnit(vector, fallback)
 local flat = Vector3.new(vector.X, 0, vector.Z)
 if flat.Magnitude < 0.01 then return fallback or Vector3.new(0, 0, -1) end
 return flat.Unit
end

local function ambientEmitter(name, position, lifetime)
 local emitter = Instance.new("Part")
 emitter.Name = name
 emitter.Size = Vector3.new(0.2, 0.2, 0.2)
 emitter.CFrame = CFrame.new(position)
 emitter.Transparency = 1
 emitter.Anchored = true
 emitter.CanCollide = false
 emitter.CanTouch = false
 emitter.CanQuery = false
 emitter.CastShadow = false
 emitter.Parent = workspace
 AmbientDebris:AddItem(emitter, lifetime or 4)
 return emitter
end

local function ambientFootsteps()
 -- Level 2 owns its real shallow-water/entity step mix in SoundController.
 -- Do not layer the dry plastic fake-footstep scare over that soundscape.
 if workspace:GetAttribute("SelectedLevel") == 2 then return false end
 local _, _, root, alive = ambientCharacter()
 if not alive then return false end
 local backward = -ambientFlatUnit(root.CFrame.LookVector)
 local right = ambientFlatUnit(root.CFrame.RightVector, Vector3.new(1, 0, 0))
 local startPosition = root.Position + backward * math.random(11, 17)
  + right * math.random(-6, 6) + Vector3.new(0, 1.1, 0)
 local emitter = ambientEmitter("DistantFootsteps", startPosition, 4.2)
 local sound = Instance.new("Sound")
 sound.Name = "Footsteps"
 sound.SoundId = "rbxasset://sounds/action_footsteps_plastic.mp3"
 sound.Volume = 0.33 -- 50% louder than before
 sound.PlaybackSpeed = 0.78 + math.random() * 0.10
 sound.Looped = true
 sound.RollOffMinDistance = 6
 sound.RollOffMaxDistance = 48
 sound.Parent = emitter

 local startDelay = 0.25 + math.random() * 0.45
 local drift = backward * math.random(6, 10) + right * math.random(-4, 4)
 task.delay(startDelay, function()
  if not emitter.Parent then return end
  -- The separate start delay, phase and speed prevent synchronization with
  -- the player's own footsteps.
  sound.TimePosition = math.random() * 0.28
  sound:Play()
  AmbientTweenService:Create(emitter, TweenInfo.new(2.45, Enum.EasingStyle.Linear), {
   CFrame = emitter.CFrame + drift,
  }):Play()
 end)
 task.delay(startDelay + 1.95, function()
  if sound.Parent then
   AmbientTweenService:Create(sound, TweenInfo.new(0.52), {Volume = 0}):Play()
  end
 end)
 return true
end

local function ambientKnocks()
 -- Level 2 owns its own soundscape; keep the Level 1 wall-knock scare out.
 if workspace:GetAttribute("SelectedLevel") == 2 then return false end
 local _, _, root, alive = ambientCharacter()
 if not alive then return false end
 local forward = ambientFlatUnit(root.CFrame.LookVector)
 local right = ambientFlatUnit(root.CFrame.RightVector, Vector3.new(1, 0, 0))
 local side = math.random(0, 1) == 0 and -1 or 1
 local position = root.Position + right * side * math.random(13, 20)
  + forward * math.random(-7, 7) + Vector3.new(0, 2.7, 0)
 local emitter = ambientEmitter("DistantWallKnock", position, 3)
 local knock = Instance.new("Sound")
 knock.Name = "Knock"
 knock.SoundId = "rbxasset://sounds/clickfast.wav"
 knock.Volume = 0.50
 knock.PlaybackSpeed = 0.34 + math.random() * 0.08
 knock.RollOffMinDistance = 6
 knock.RollOffMaxDistance = 38
 knock.Parent = emitter

 local knocks = math.random(2, 3)
 for index = 1, knocks do
  if not ambientCanScare() then break end
  knock:Stop()
  knock.TimePosition = 0
  knock:Play()
  task.wait(index == 1 and 0.22 or 0.48)
 end
 task.delay(0.55, function()
  if knock.Parent then AmbientTweenService:Create(knock, TweenInfo.new(0.3), {Volume = 0}):Play() end
 end)
 return true
end

local function ambientLightDrop()
 local _, _, root, alive = ambientCharacter()
 local maze = workspace:FindFirstChild("Maze")
 if not alive or not maze then return false end
 local backward = -ambientFlatUnit(root.CFrame.LookVector)
 local candidates = {}
 for _, item in ipairs(maze:GetDescendants()) do
  if item:IsA("Light") and item.Enabled and item.Brightness > 0.1
   and item.Parent and item.Parent:IsA("BasePart") then
   local delta = item.Parent.Position - root.Position
   local flat = Vector3.new(delta.X, 0, delta.Z)
   if flat.Magnitude > 2 and flat.Magnitude < 50 and backward:Dot(flat.Unit) > 0.05 then
    candidates[#candidates + 1] = {light = item, distance = flat.Magnitude}
   end
  end
 end
 table.sort(candidates, function(a, b) return a.distance < b.distance end)
 if #candidates == 0 then return false end

 local affected = {}
 for index = 1, math.min(4, #candidates) do
  local light = candidates[index].light
  affected[#affected + 1] = {light = light, brightness = light.Brightness}
  AmbientTweenService:Create(light, TweenInfo.new(0.13, Enum.EasingStyle.Quad), {Brightness = 0}):Play()
 end
 task.wait(1.35)
 for _, data in ipairs(affected) do
  local light = data.light
  -- If another game system changed or disabled it, that newer state wins.
  if light.Parent and light.Brightness <= 0.05 then
   AmbientTweenService:Create(light, TweenInfo.new(0.75, Enum.EasingStyle.Quad), {
    Brightness = data.brightness,
   }):Play()
  end
 end
 return true
end

local function ambientShadow()
 if workspace:FindFirstChild("MimicApparition") then return false end
 local character, _, root, alive = ambientCharacter()
 local camera = workspace.CurrentCamera
 if not alive or not camera then return false end
 local forward = ambientFlatUnit(camera.CFrame.LookVector, ambientFlatUnit(root.CFrame.LookVector))
 local right = ambientFlatUnit(camera.CFrame.RightVector, Vector3.new(1, 0, 0))
 local floorParams = RaycastParams.new()
 floorParams.FilterType = Enum.RaycastFilterType.Exclude
 floorParams.FilterDescendantsInstances = {character}
 floorParams.IgnoreWater = true

 local base, chosenSide
 for _ = 1, 10 do
  local side = math.random(0, 1) == 0 and -1 or 1
  local guess = root.Position + forward * math.random(10, 16) + right * side * math.random(4, 7)
  local floorHit = workspace:Raycast(guess + Vector3.new(0, 3, 0), Vector3.new(0, -12, 0), floorParams)
  if floorHit and floorHit.Normal.Y >= 0.65 and math.abs(floorHit.Position.Y - root.Position.Y) <= 7 then
   local candidateBase = floorHit.Position
   local target = candidateBase + Vector3.new(0, 4, 0)
   local screenPoint, onScreen = camera:WorldToViewportPoint(target)
   local sight = workspace:Raycast(camera.CFrame.Position, target - camera.CFrame.Position, floorParams)
   if onScreen and screenPoint.Z > 0 and (not sight or (sight.Position - target).Magnitude <= 2) then
    base = candidateBase
    chosenSide = side
    break
   end
  end
 end
 if not base then return false end

 local model = Instance.new("Model")
 model.Name = "AmbientShadowGlimpse"
 model.Parent = workspace
 local origin = Vector3.new(base.X, base.Y, base.Z)
 local facingTarget = Vector3.new(root.Position.X, base.Y, root.Position.Z)
 local facing = CFrame.lookAt(origin, facingTarget)
 local parts = {}
 local function shadowPart(name, size, offset, shape)
  local part = Instance.new("Part")
  part.Name = name
  part.Size = size
  part.Shape = shape or Enum.PartType.Block
  part.Color = Color3.fromRGB(2, 2, 2)
  part.Material = Enum.Material.SmoothPlastic
  part.Transparency = 0.12
  part.Anchored = true
  part.CanCollide = false
  part.CanTouch = false
  part.CanQuery = false
  part.CastShadow = false
  part.CFrame = facing * CFrame.new(offset)
  part.Parent = model
  parts[#parts + 1] = part
 end
 shadowPart("Torso", Vector3.new(2.1, 3.3, 0.75), Vector3.new(0, 3.35, 0))
 shadowPart("Head", Vector3.new(1.45, 1.45, 1.45), Vector3.new(0, 5.65, 0), Enum.PartType.Ball)
 shadowPart("LeftLeg", Vector3.new(0.65, 2.7, 0.65), Vector3.new(-0.48, 1.35, 0))
 shadowPart("RightLeg", Vector3.new(0.65, 2.7, 0.65), Vector3.new(0.48, 1.35, 0))
 shadowPart("LeftArm", Vector3.new(0.5, 3.0, 0.5), Vector3.new(-1.28, 3.25, 0))
 shadowPart("RightArm", Vector3.new(0.5, 3.0, 0.5), Vector3.new(1.28, 3.25, 0))

 local movement = right * (-chosenSide) * 7
 for _, part in ipairs(parts) do
  AmbientTweenService:Create(part, TweenInfo.new(0.58, Enum.EasingStyle.Quad, Enum.EasingDirection.In), {
   CFrame = part.CFrame + movement,
   Transparency = 0.88,
  }):Play()
 end
 task.delay(0.32, function()
  for _, part in ipairs(parts) do
   if part.Parent then AmbientTweenService:Create(part, TweenInfo.new(0.22), {Transparency = 1}):Play() end
  end
 end)
 AmbientDebris:AddItem(model, 0.65)
 return true
end
local ambientScares = {
 footsteps = ambientFootsteps,
 knocks = ambientKnocks,
 lights = ambientLightDrop,
}

local function ambientChooseKind()
 local roll = math.random(1, 100)
 local kind = roll <= 34 and "footsteps"
  or roll <= 54 and "knocks"
  or roll <= 81 and "lights"
  or "footsteps"
 if kind == ambientLastKind then
  local alternatives = {"footsteps", "knocks", "lights"}
  table.remove(alternatives, table.find(alternatives, kind))
  kind = alternatives[math.random(1, #alternatives)]
 end
 return kind
end

local function ambientTrigger(kind)
 if ambientBusy or not ambientCanScare() then return false end
 local scare = ambientScares[kind]
 if not scare then return false end
 ambientBusy = true
 local ok, started = pcall(scare)
 if not ok then warn("[Ambient Scare] " .. kind .. " failed: " .. tostring(started)) end
 if ok and started then ambientLastKind = kind end
 if (not ok or not started) and kind ~= "footsteps" and ambientCanScare() then
  pcall(ambientFootsteps)
  ambientLastKind = "footsteps"
 end
 ambientBusy = false
 return ok and started == true
end

local function ambientHighPressure()
 local mode = workspace:GetAttribute("LightMode")
 return mode == "POWERDOWN" or mode == "ESCAPE" or os.clock() < ambientLeverPressureUntil
end

workspace:GetAttributeChangedSignal("LightMode"):Connect(function()
 if ambientHighPressure() and ambientCanScare() then
  ambientNextAt = math.min(ambientNextAt, os.clock() + math.random(2, 4))
 end
end)

local ambientPuzzleStatus = remotes:FindFirstChild("PuzzleStatus")
if ambientPuzzleStatus and ambientPuzzleStatus:IsA("RemoteEvent") then
 ambientPuzzleStatus.OnClientEvent:Connect(function(kind, active)
  if kind == "lever" and (tonumber(active) or 0) > 0 then
   ambientLeverPressureUntil = os.clock() + 12
   if ambientCanScare() then
    ambientNextAt = math.min(ambientNextAt, os.clock() + math.random(2, 4))
   end
  elseif kind == "exit" then
   ambientLeverPressureUntil = os.clock() + 20
  end
 end)
end

-- Studio test hook: set the local player's DevAmbientScare attribute to
-- footsteps, knocks, lights or shadow (append any suffix to repeat one type).
if RunService:IsStudio() then
 player:GetAttributeChangedSignal("DevAmbientScare"):Connect(function()
  local raw = tostring(player:GetAttribute("DevAmbientScare") or ""):lower()
  local kind = raw:match("^(%a+)")
  if ambientScares[kind] then task.spawn(ambientTrigger, kind) end
 end)
end

task.spawn(function()
 while true do
  task.wait(0.75)
  if not ambientCanScare() then
   ambientNextAt = os.clock() + math.random(14, 22)
  elseif os.clock() >= ambientNextAt then
   ambientTrigger(ambientChooseKind())
   ambientNextAt = os.clock() + (ambientHighPressure() and math.random(7, 12) or math.random(22, 38))
  end
 end
end)
