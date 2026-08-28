-- PuzzleUI (v3 — counters plus lever synchronization timer)

local Players = game:GetService("Players")
local RS = game:GetService("ReplicatedStorage")
local UIDevice = require(RS:WaitForChild("UIDevice"))
local RunService = game:GetService("RunService")

local remote = RS:WaitForChild("Remotes"):WaitForChild("PuzzleStatus")
local player = Players.LocalPlayer

local gui = Instance.new("ScreenGui")
gui.Name = "PuzzleGui"
gui.ResetOnSpawn = false
gui.IgnoreGuiInset = true
gui.DisplayOrder = 18

gui.Parent = player:WaitForChild("PlayerGui")

local function syncDispatchSuppression()
	gui.Enabled = player:GetAttribute("ZyntraDispatchClientActive") ~= true
end
player:GetAttributeChangedSignal("ZyntraDispatchClientActive"):Connect(syncDispatchSuppression)
syncDispatchSuppression()

-- Level 1 now uses the same compact terminal-card language as Level 2 instead
-- of three unrelated floating counters.
local objectivePanel = Instance.new("Frame")
objectivePanel.Name = "Level1Objectives"
objectivePanel.AnchorPoint = Vector2.new(1, 1)
objectivePanel.Position = UDim2.new(1, -18, 1, -18)
objectivePanel.Size = UDim2.new(0, 300, 0, 112)
objectivePanel.BackgroundColor3 = Color3.fromRGB(8, 14, 9)
objectivePanel.BackgroundTransparency = 0.18
objectivePanel.BorderSizePixel = 0
objectivePanel.Visible = false
objectivePanel.Parent = gui

local panelCorner = Instance.new("UICorner")
panelCorner.CornerRadius = UDim.new(0, 8)
panelCorner.Parent = objectivePanel
local panelStroke = Instance.new("UIStroke")
panelStroke.Color = Color3.fromRGB(105, 238, 168)
panelStroke.Transparency = 0.27
panelStroke.Thickness = 1.4
panelStroke.Parent = objectivePanel

local objectiveTitle = Instance.new("TextLabel")
objectiveTitle.Name = "ObjectiveTitle"
objectiveTitle.BackgroundTransparency = 1
objectiveTitle.Position = UDim2.new(0, 13, 0, 6)
objectiveTitle.Size = UDim2.new(1, -26, 0, 25)
objectiveTitle.Font = Enum.Font.Code
objectiveTitle.Text = "> POWER RESTORATION"
objectiveTitle.TextColor3 = Color3.fromRGB(120, 255, 175)
objectiveTitle.TextSize = 17
objectiveTitle.TextXAlignment = Enum.TextXAlignment.Left
objectiveTitle.Parent = objectivePanel

local function makeLabel(name, yOffset)
	local label = Instance.new("TextLabel")
	label.Name = name
	label.Position = UDim2.new(0, 13, 0, yOffset)
	label.Size = UDim2.new(1, -26, 0, 23)
	label.BackgroundTransparency = 1
	label.BorderSizePixel = 0
	label.Font = Enum.Font.Code
	label.TextSize = 15
	label.TextXAlignment = Enum.TextXAlignment.Left
	label.TextColor3 = Color3.fromRGB(218, 237, 223)
	label.Visible = false
	label.Parent = objectivePanel
	return label
end

local boxesLabel = makeLabel("FuseBoxStatus", 34)
local carryLabel = makeLabel("FuseCarryStatus", 59)
local leverLabel = makeLabel("LeverStatus", 84)

-- Transient one-line feedback from the server ("Fuse extracted",
-- "You have no fuses"), shown just above the objective panel.
local msgLabel = Instance.new("TextLabel")
msgLabel.Name = "PuzzleMessage"
msgLabel.AnchorPoint = Vector2.new(1, 1)
msgLabel.Position = UDim2.new(1, -18, 1, -136)
msgLabel.Size = UDim2.new(0, 300, 0, 22)
msgLabel.BackgroundTransparency = 1
msgLabel.Font = Enum.Font.Code
msgLabel.TextSize = 15
msgLabel.TextXAlignment = Enum.TextXAlignment.Right
msgLabel.TextColor3 = Color3.fromRGB(235, 220, 150)
msgLabel.Visible = false
msgLabel.Parent = gui

local msgSerial = 0
local function showMessage(text)
	msgSerial += 1
	local serial = msgSerial
	msgLabel.Text = tostring(text)
	msgLabel.Visible = true
	task.delay(1.8, function()
		if msgSerial == serial then msgLabel.Visible = false end
	end)
end

-- Handheld exit-signal receiver
local receiver = Instance.new("Frame")
receiver.Name = "ExitEnergyDetector"
receiver.AnchorPoint = Vector2.new(0, 1)
receiver.Position = UDim2.new(0, 132, 1, -16)
receiver.Size = UDim2.new(0, 310, 0, 116)
receiver.BackgroundColor3 = Color3.fromRGB(5, 12, 7)
receiver.BackgroundTransparency = 0.08
receiver.BorderSizePixel = 0
receiver.Rotation = -1.5
receiver.Visible = false
receiver.Parent = gui

local receiverCorner = Instance.new("UICorner")
receiverCorner.CornerRadius = UDim.new(0, 8)
receiverCorner.Parent = receiver

local receiverStroke = Instance.new("UIStroke")
receiverStroke.Color = Color3.fromRGB(45, 170, 80)
receiverStroke.Thickness = 2
receiverStroke.Transparency = 0.42
receiverStroke.Parent = receiver

local receiverHeader = Instance.new("TextLabel")
receiverHeader.Size = UDim2.new(1, -20, 0, 25)
receiverHeader.Position = UDim2.new(0, 10, 0, 8)
receiverHeader.BackgroundTransparency = 1
receiverHeader.Font = Enum.Font.Code
receiverHeader.TextSize = 15
receiverHeader.TextXAlignment = Enum.TextXAlignment.Left
receiverHeader.TextColor3 = Color3.fromRGB(65, 185, 95)
receiverHeader.Text = "> EXIT ENERGY DETECTOR"
receiverHeader.Parent = receiver

local gammaMark = Instance.new("TextLabel")
gammaMark.AnchorPoint = Vector2.new(1, 0)
gammaMark.Position = UDim2.new(1, -9, 0, 5)
gammaMark.Size = UDim2.new(0, 30, 0, 30)
gammaMark.BackgroundTransparency = 1
gammaMark.Font = Enum.Font.GothamBold
gammaMark.Text = "☢"
gammaMark.TextSize = 22
gammaMark.TextColor3 = Color3.fromRGB(80, 185, 105)
gammaMark.TextTransparency = 0.35
gammaMark.Parent = receiver

local receiverReadout = Instance.new("TextLabel")
receiverReadout.Size = UDim2.new(1, -20, 0, 66)
receiverReadout.Position = UDim2.new(0, 10, 0, 38)
receiverReadout.BackgroundTransparency = 1
receiverReadout.Font = Enum.Font.Code
receiverReadout.TextSize = 17
receiverReadout.TextWrapped = true
receiverReadout.TextXAlignment = Enum.TextXAlignment.Left
receiverReadout.TextYAlignment = Enum.TextYAlignment.Top
receiverReadout.TextColor3 = Color3.fromRGB(78, 178, 105)
receiverReadout.Text = "[■□□□] WEAK SIGNAL\nMove around to improve reception"
receiverReadout.Parent = receiver

local compassArrow = Instance.new("TextLabel")
compassArrow.Position = UDim2.new(0, 12, 0, 36)
compassArrow.Size = UDim2.new(0, 66, 0, 68)
compassArrow.BackgroundTransparency = 1
compassArrow.Font = Enum.Font.Code
compassArrow.Text = "▲"
compassArrow.TextSize = 54
compassArrow.TextColor3 = Color3.fromRGB(75, 210, 110)
compassArrow.TextTransparency = 0.12
compassArrow.Visible = false
compassArrow.Parent = receiver

local receiverActive = false
local compassMode = false
local receiverClock = 0
local lastExitDistance = nil

local function setReceiver(on)
 receiverActive = on
 receiver.Visible = on
 lastExitDistance = nil
 compassMode = false
 compassArrow.Visible = false
 receiverHeader.Text = "> EXIT ENERGY DETECTOR"
 receiverReadout.Position = UDim2.new(0, 10, 0, 38)
 receiverReadout.Size = UDim2.new(1, -20, 0, 66)
 receiverClock = 0
end

local function signalMeter(distance)
 local filled = math.clamp(9 - math.ceil(distance / 42), 1, 8)
 return "[" .. string.rep("■", filled) .. string.rep("□", 8 - filled) .. "]"
end

RunService.Heartbeat:Connect(function(dt)
 if not receiverActive then return end
 receiverClock += dt
 if receiverClock < 0.22 then return end
 receiverClock = 0

 local exitPos = workspace:GetAttribute("ExitPos")
 local character = player.Character
 local root = character and character:FindFirstChild("HumanoidRootPart")
 if typeof(exitPos) ~= "Vector3" or not root then
  receiverReadout.Text = "[□□□□□□□□] SEARCHING...\nMove around to find the signal"
  return
 end

 if compassMode then
  local delta = Vector3.new(exitPos.X - root.Position.X, 0, exitPos.Z - root.Position.Z)
  local camera = workspace.CurrentCamera
  if delta.Magnitude > 0.01 and camera then
   local targetDir = delta.Unit
   local look = camera.CFrame.LookVector
   local forward = Vector3.new(look.X, 0, look.Z)
   if forward.Magnitude > 0.01 then
    forward = forward.Unit
    local dot = math.clamp(forward:Dot(targetDir), -1, 1)
    local cross = forward.X * targetDir.Z - forward.Z * targetDir.X
    compassArrow.Rotation = math.deg(math.atan2(cross, dot))
   end
  end
  receiverReadout.Text = "EXIT VECTOR LOCKED\nFOLLOW DIRECTION"
  return
 end

 local distance = (root.Position - exitPos).Magnitude
 local approaching = lastExitDistance and distance < lastExitDistance - 1
 local fading = lastExitDistance and distance > lastExitDistance + 1
 local meter = signalMeter(distance)
 lastExitDistance = distance

 if distance > 260 then
  receiverReadout.Text = meter .. " WEAK SIGNAL\nMove around to improve reception"
 elseif distance > 150 then
  receiverReadout.Text = approaching
   and meter .. " SIGNAL IMPROVING\nKeep going"
   or (fading
    and meter .. " SIGNAL FADING\nTry a different path"
    or meter .. " FAINT SIGNAL\nSearch for a clearer path")
 elseif distance > 70 then
  receiverReadout.Text = approaching
   and meter .. " STRONG SIGNAL\nContinue this way"
   or (fading
    and meter .. " SIGNAL FADING\nTurn back and search nearby"
    or meter .. " STRONG SIGNAL\nSearch nearby")
 else
  receiverReadout.Text = meter .. " VERY STRONG SIGNAL\nThe powered exit is close"
 end
end)

local leverPhase = false
local leverActive = 0
local leverTotal = 0
local leverEndsAt = 0
local leverLatchMode = false

local function showCounters(on)
	objectivePanel.Visible = on
	boxesLabel.Visible = on
	carryLabel.Visible = on
	if not on then
		leverLabel.Visible = false
		msgLabel.Visible = false
	end
end

local function refreshLever()
	if not leverPhase then return end
	leverLabel.Visible = true

	if leverLatchMode then
		leverLabel.Text = ("Levers: %d/%d  •  NO TIME LIMIT"):format(leverActive, leverTotal)
		leverLabel.TextColor3 = Color3.fromRGB(170, 225, 255)
	elseif leverActive > 0 and leverEndsAt > 0 then
		local remaining = math.max(leverEndsAt - os.clock(), 0)
		leverLabel.Text = ("Levers: %d/%d  •  %.1fs"):format(leverActive, leverTotal, remaining)
		leverLabel.TextColor3 = remaining <= 3
			and Color3.fromRGB(255, 105, 105)
			or Color3.fromRGB(255, 220, 130)
	else
		leverLabel.Text = ("Levers: %d/%d"):format(leverActive, leverTotal)
		leverLabel.TextColor3 = Color3.fromRGB(245, 245, 245)
	end
end

RunService.RenderStepped:Connect(refreshLever)

local function progressMeter(current, total)
	current = math.max(0, math.floor(tonumber(current) or 0))
	total = math.max(1, math.floor(tonumber(total) or 1))
	return "[" .. string.rep("#", math.min(current, total))
		.. string.rep("-", math.max(total - current, 0)) .. "]"
end

remote.OnClientEvent:Connect(function(ev, a, b, c, d)
	-- PuzzleManager broadcasts shared world changes, but lobby spectators must
	-- never inherit the active party's maze HUD.
	if player:GetAttribute("InRound") ~= true then
		setReceiver(false)
		showCounters(false)
		return
	end

	if ev == "begin" then
		setReceiver(false)
		objectiveTitle.Text = "> POWER RESTORATION"
		objectiveTitle.TextColor3 = Color3.fromRGB(120, 255, 175)
		carryLabel.Text = "FUSES HELD  0"
		boxesLabel.Text = ("%s FUSE BOXES  0/%d"):format(progressMeter(0, b), b)
		leverPhase = false
		showCounters(true)

	elseif ev == "carry" then
		carryLabel.Text = "FUSES HELD  " .. a

	elseif ev == "msg" then
		showMessage(a)

	elseif ev == "boxes" then
		boxesLabel.Text = ("%s FUSE BOXES  %d/%d"):format(progressMeter(a, b), a, b)

	elseif ev == "levers" then
		objectiveTitle.Text = "> EXIT CIRCUIT"
		objectiveTitle.TextColor3 = Color3.fromRGB(170, 225, 255)
		leverPhase = true
		leverActive = 0
		leverTotal = a or 0
		leverEndsAt = 0
		leverLatchMode = false
		refreshLever()

	elseif ev == "lever" then
		leverPhase = true
		leverActive = a or 0
		leverTotal = b or leverTotal
		leverLatchMode = d == true
		leverEndsAt = (not leverLatchMode and (c or 0) > 0)
			and (os.clock() + c)
			or 0
		refreshLever()

	elseif ev == "escape" then
		setReceiver(true)
		compassMode = true
		compassArrow.Visible = true
		receiverHeader.Text = "> EXIT ENERGY DETECTOR // NAV"
		receiverReadout.Position = UDim2.new(0, 86, 0, 45)
		receiverReadout.Size = UDim2.new(1, -96, 0, 58)
		receiverReadout.Text = "EXIT VECTOR LOCKED\nFOLLOW DIRECTION"

	elseif ev == "exit" then
		objectiveTitle.Text = "> EXIT ONLINE"
		objectiveTitle.TextColor3 = Color3.fromRGB(120, 255, 160)
		setReceiver(true)
		compassMode = true
		compassArrow.Visible = true
		receiverHeader.Text = "> EXIT ENERGY DETECTOR // NAV"
		receiverReadout.Position = UDim2.new(0, 86, 0, 45)
		receiverReadout.Size = UDim2.new(1, -96, 0, 58)
		receiverReadout.Text = "EXIT VECTOR LOCKED\nFOLLOW DIRECTION"
		leverPhase = false
		leverLabel.Visible = true
		leverLabel.Text = "EXIT POWERED — FIND THE DOOR"
		leverLabel.TextColor3 = Color3.fromRGB(120, 255, 160)
	end
end)

workspace:GetAttributeChangedSignal("RoundActive"):Connect(function()
	if not workspace:GetAttribute("RoundActive") then
		leverPhase = false
		leverActive = 0
		leverTotal = 0
		leverEndsAt = 0
		setReceiver(false)
		showCounters(false)
	end
end)

-- LEVEL2_EXIT_TRANSITION_20260828 sibling change: responsive Level 1 HUD.
-- The objective panel (300x112, bottom-right) and the receiver (310x116,
-- bottom-left+132) were fixed-size and, at 667x375, overlapped each other AND
-- the RUN/JUMP column. Desktop keeps the authored lower-right composition; on
-- touch both panels move into UIDevice's safe content band and shrink to fit.
local function applyPuzzleLayout()
	local layout = UIDevice.Layout()
	local available = layout.SafeRight - layout.SafeLeft
	if layout.IsTouch then
		-- The bottom of a touch screen belongs to the movement controls, so both
		-- panels live in the strip above the thumbstick's activation region. On
		-- a landscape phone that strip is only about 90 pixels tall, which is
		-- the real constraint these two 112/116px panels had never been sized
		-- against; they are fitted to it rather than allowed to overflow.
		local band = layout.TopBand
		local gutter = 12
		local panelWidth = math.min(300, math.floor((band.Width - gutter) * .5))
		local messageHeight = 22
		local panelHeight = math.max(56, math.min(112, band.Height - messageHeight - 6))
		-- band.* are ABSOLUTE screen coordinates; this ScreenGui sets
		-- IgnoreGuiInset, so its own y = 0 is one inset higher. Convert, or every
		-- panel lands an inset off in whichever direction the gui is configured.
		local messageY = UIDevice.TopOffsetFor(gui, band.Top)
		local panelY = UIDevice.TopOffsetFor(gui, band.Top + messageHeight + 4)

		msgLabel.AnchorPoint = Vector2.new(1, 0)
		msgLabel.Size = UDim2.new(0, panelWidth, 0, messageHeight)
		msgLabel.Position = UDim2.fromOffset(band.Right, messageY)

		objectivePanel.AnchorPoint = Vector2.new(1, 0)
		objectivePanel.Size = UDim2.new(0, panelWidth, 0, panelHeight)
		objectivePanel.Position = UDim2.fromOffset(band.Right, panelY)

		receiver.AnchorPoint = Vector2.new(0, 0)
		receiver.Size = UDim2.new(0, panelWidth, 0, panelHeight)
		receiver.Position = UDim2.fromOffset(band.Left, panelY)
	else
		objectivePanel.AnchorPoint = Vector2.new(1, 1)
		objectivePanel.Size = UDim2.new(0, 300, 0, 112)
		objectivePanel.Position = UDim2.new(1, -18, 1, -18)
		msgLabel.AnchorPoint = Vector2.new(1, 1)
		msgLabel.Size = UDim2.new(0, 300, 0, 22)
		msgLabel.Position = UDim2.new(1, -18, 1, -136)
		receiver.AnchorPoint = Vector2.new(0, 1)
		receiver.Size = UDim2.new(0, math.min(310, available - 320), 0, 116)
		receiver.Position = UDim2.new(0, 132, 1, -16)
	end
end

applyPuzzleLayout()
UIDevice.Changed:Connect(applyPuzzleLayout)
