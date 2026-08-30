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
		and player:GetAttribute("LevelOneGuideObjectivesOpen") ~= true
end
player:GetAttributeChangedSignal("ZyntraDispatchClientActive"):Connect(syncDispatchSuppression)
player:GetAttributeChangedSignal("LevelOneGuideObjectivesOpen"):Connect(syncDispatchSuppression)
syncDispatchSuppression()

-- C1_OBJECTIVES_LOWER_RIGHT_20260829 / C2_OBJECTIVE_ROWS_20260829 -- the whole
-- geometry contract for this HUD, in ONE table, so the layout code and a
-- regression test read the same numbers instead of two sets of magic literals.
--
-- WHAT SHIPPED BROKEN, twice over:
--
--  C1  The objective panel and the exit-energy detector were each authored as a
--      fixed box pinned to its own bottom corner, and nothing ever checked that
--      the corners were far enough apart. Measured at 705x338 the panel held
--      (387,150)-(687,262) and the detector (132,148)-(442,264) -- a 55px
--      horizontal overlap, with the detector's readout printed under the
--      objective rows. They are now laid out as ONE row with an explicit
--      separation rule, so an overlap is not a state the numbers can express.
--
--  C2  The panel was clamped to a 56px minimum height on touch while its rows
--      kept hard-coded offsets y = 34/59/84 at 23px each. Measured on a Galaxy
--      A06 the rows ran to y=257 inside a panel that ended at y=206: the carry
--      and lever rows were drawn OUTSIDE their own panel and on top of the
--      movement band. Rows are now stacked from the top pad downward and the
--      panel's height is DERIVED from the visible rows, so a row cannot land
--      outside the panel by construction.
local LAYOUT = {
	-- C1 corner contract. The TOGGLE is the element pinned to the corner --
	-- deliberately, so it cannot move when the panel it controls changes height
	-- or hides. The panel stacks directly above it, the transient message above
	-- that. Same anchor on desktop and touch; only the reference edge differs.
	Margin = 18,
	ToggleWidth = 140,
	ToggleHeight = 30,
	TouchToggleHeight = 44,      -- this game's tap-target floor
	ToggleGap = 8,
	MessageHeight = 22,
	MessageGap = 4,

	-- C1 reflow. The objectives column and the detector share one row and must
	-- stay ColumnGap apart; applyPuzzleLayout walks the ordered steps.
	ColumnGap = 16,
	ObjectivesWidth = 300,
	ObjectivesMinWidth = 220,
	DetectorWidth = 310,
	DetectorMinWidth = 240,
	DetectorTouchMinWidth = 150,
	DetectorHeight = 116,
	DetectorMinHeight = 44,
	DetectorLeft = 132,          -- the authored desktop inset
	DetectorMargin = 16,
	SafeLeft = 12,
	BottomSafe = 12,
	CorridorMinWidth = 150,      -- the threshold Level 2 Objective UI already uses

	-- C2 row metrics. The NATURAL tier reproduces the authored 300x112 panel
	-- exactly when all four rows are visible (6 + 25 + 2 + 3*23 + 2*2 + 6 = 112);
	-- the COMPACT tier is the stated minimum a row may shrink to.
	PadX = 13, PadTop = 6, PadBottom = 6,
	TitleHeight = 25, RowHeight = 23, RowGap = 2,
	TitleTextSize = 17, RowTextSize = 15,
	CompactPadX = 10, CompactPadTop = 4, CompactPadBottom = 4,
	CompactTitleHeight = 18, CompactRowHeight = 16,
	CompactTitleTextSize = 14, CompactRowTextSize = 12,
}

-- Forward declaration: the row helpers and the visibility helpers below all
-- need to re-place the column when a row appears or disappears, and the
-- placement function itself needs the row helpers. One of the two has to be
-- declared early; this is the one with no dependencies of its own.
local applyPuzzleLayout

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
-- Seeded from the contract; layoutObjectiveRows owns these from here on. (C2)
objectiveTitle.Position = UDim2.new(0, LAYOUT.PadX, 0, LAYOUT.PadTop)
objectiveTitle.Size = UDim2.new(1, -LAYOUT.PadX * 2, 0, LAYOUT.TitleHeight)
objectiveTitle.Font = Enum.Font.Code
objectiveTitle.Text = "> POWER RESTORATION"
objectiveTitle.TextColor3 = Color3.fromRGB(120, 255, 175)
objectiveTitle.TextSize = LAYOUT.TitleTextSize
objectiveTitle.TextXAlignment = Enum.TextXAlignment.Left
objectiveTitle.Parent = objectivePanel

-- C2: a row no longer carries a hard-coded y. It is handed one by
-- layoutObjectiveRows every time the set of VISIBLE rows changes, which is the
-- only way a row's position can stay inside a panel whose height also moves.
local function makeLabel(name)
	local label = Instance.new("TextLabel")
	label.Name = name
	label.Position = UDim2.new(0, LAYOUT.PadX, 0, LAYOUT.PadTop)
	label.Size = UDim2.new(1, -LAYOUT.PadX * 2, 0, LAYOUT.RowHeight)
	label.BackgroundTransparency = 1
	label.BorderSizePixel = 0
	label.Font = Enum.Font.Code
	label.TextSize = LAYOUT.RowTextSize
	label.TextXAlignment = Enum.TextXAlignment.Left
	label.TextColor3 = Color3.fromRGB(218, 237, 223)
	label.Visible = false
	label.Parent = objectivePanel
	return label
end

local boxesLabel = makeLabel("FuseBoxStatus")
local carryLabel = makeLabel("FuseCarryStatus")
local leverLabel = makeLabel("LeverStatus")

-- C1: the objectives TOGGLE. This is the element actually pinned to
-- AnchorPoint (1, 1) / Position (1, -Margin, 1, -Margin) on desktop; the panel
-- hangs above it. The user asked repeatedly for the objectives to live in the
-- LOWER-RIGHT corner, so the corner anchor is written once, here, as a contract
-- rather than rediscovered per branch.
local objectivesToggle = Instance.new("TextButton")
objectivesToggle.Name = "Level1ObjectivesToggle"
objectivesToggle.AnchorPoint = Vector2.new(1, 1)
objectivesToggle.Position = UDim2.new(1, -LAYOUT.Margin, 1, -LAYOUT.Margin)
objectivesToggle.Size = UDim2.fromOffset(LAYOUT.ToggleWidth, LAYOUT.ToggleHeight)
objectivesToggle.BackgroundColor3 = Color3.fromRGB(8, 14, 9)
objectivesToggle.BackgroundTransparency = 0.18
objectivesToggle.BorderSizePixel = 0
objectivesToggle.AutoButtonColor = true
objectivesToggle.Font = Enum.Font.Code
objectivesToggle.Text = "OBJECTIVES  -"
objectivesToggle.TextColor3 = Color3.fromRGB(120, 255, 175)
objectivesToggle.TextSize = 14
objectivesToggle.Visible = false
objectivesToggle.Parent = gui
local objectivesToggleCorner = Instance.new("UICorner")
objectivesToggleCorner.CornerRadius = UDim.new(0, 8)
objectivesToggleCorner.Parent = objectivesToggle
local objectivesToggleStroke = Instance.new("UIStroke")
objectivesToggleStroke.Color = Color3.fromRGB(105, 238, 168)
objectivesToggleStroke.Transparency = 0.27
objectivesToggleStroke.Thickness = 1.4
objectivesToggleStroke.Parent = objectivesToggle

local countersActive = false
local objectivesCollapsed = false
local objectivePanelWidth = LAYOUT.ObjectivesWidth

-- C2: how tall the stack of VISIBLE rows is. Two tiers and no interpolation --
-- natural, and the stated compact minimum -- because a half-scaled Code font
-- reads worse than a smaller one. `available` is the height the placement can
-- spare, or nil for "unconstrained" (desktop).
local function objectiveRowMetrics(available)
	local rows = 0
	if boxesLabel.Visible then rows += 1 end
	if carryLabel.Visible then rows += 1 end
	if leverLabel.Visible then rows += 1 end

	local natural = LAYOUT.PadTop + LAYOUT.TitleHeight + LAYOUT.PadBottom
	if rows > 0 then
		natural += LAYOUT.RowGap + rows * LAYOUT.RowHeight + (rows - 1) * LAYOUT.RowGap
	end
	if available == nil or natural <= available then return natural, false end

	local compact = LAYOUT.CompactPadTop + LAYOUT.CompactTitleHeight + LAYOUT.CompactPadBottom
	if rows > 0 then
		compact += LAYOUT.RowGap + rows * LAYOUT.CompactRowHeight + (rows - 1) * LAYOUT.RowGap
	end
	return compact, true
end

-- C2: stack the visible rows from the top pad down and size the PANEL to the
-- result. The panel's height is never clamped below its own content -- if even
-- the compact stack is taller than the band it was offered, the panel grows
-- UPWARD from its bottom anchor into empty screen, never downward into the
-- movement zones. That is what makes "no child outside the panel" structural
-- rather than a value someone has to keep in sync.
local function layoutObjectiveRows(available)
	local height, compact = objectiveRowMetrics(available)
	local padX = compact and LAYOUT.CompactPadX or LAYOUT.PadX
	local titleHeight = compact and LAYOUT.CompactTitleHeight or LAYOUT.TitleHeight
	local rowHeight = compact and LAYOUT.CompactRowHeight or LAYOUT.RowHeight
	local y = compact and LAYOUT.CompactPadTop or LAYOUT.PadTop

	objectiveTitle.Position = UDim2.new(0, padX, 0, y)
	objectiveTitle.Size = UDim2.new(1, -padX * 2, 0, titleHeight)
	objectiveTitle.TextSize = compact and LAYOUT.CompactTitleTextSize or LAYOUT.TitleTextSize
	y += titleHeight

	for _, row in ipairs({boxesLabel, carryLabel, leverLabel}) do
		if row.Visible then
			y += LAYOUT.RowGap
			row.Position = UDim2.new(0, padX, 0, y)
			row.Size = UDim2.new(1, -padX * 2, 0, rowHeight)
			row.TextSize = compact and LAYOUT.CompactRowTextSize or LAYOUT.RowTextSize
			y += rowHeight
		end
	end

	objectivePanel.Size = UDim2.fromOffset(objectivePanelWidth, height)
	return height
end

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
	-- The message row is positioned relative to the panel it belongs to, so with
	-- the panel collapsed there is nothing for it to sit above; it would float in
	-- the corner on its own. Collapsed means collapsed.
	if objectivesCollapsed then return end
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
local receiverHeight = LAYOUT.DetectorHeight
local receiverNav = false

-- The detector had the same disease as the objective panel: applyPuzzleLayout
-- shrank the FRAME on touch while the header/readout/compass kept the offsets
-- authored for a 116px card, so at 705x338 a 75px detector still drew a readout
-- ending at y=104. Its children are now derived from receiverHeight, and the
-- NAV variant (which used to be written inline at two call sites, twice, with
-- slightly different numbers) is one flag read here.
local function layoutReceiver()
 local compact = receiverHeight < 96
 local padX = compact and 8 or 10
 local headerTop = compact and 3 or 8
 local headerHeight = compact and 15 or 25
 receiverHeader.Position = UDim2.new(0, padX, 0, headerTop)
 receiverHeader.Size = UDim2.new(1, -(padX * 2 + 26), 0, headerHeight)
 receiverHeader.TextSize = compact and 11 or 15
 gammaMark.Position = UDim2.new(1, -(padX - 1), 0, math.max(0, headerTop - 3))
 gammaMark.Size = UDim2.fromOffset(compact and 20 or 30, compact and 20 or 30)
 gammaMark.TextSize = compact and 15 or 22

 local bodyTop = headerTop + headerHeight + (compact and 2 or 5)
 local bodyHeight = math.max(12, receiverHeight - bodyTop - (compact and 4 or 12))
 local arrowWidth = compact and 40 or 66
 compassArrow.Position = UDim2.new(0, padX + 2, 0, bodyTop)
 compassArrow.Size = UDim2.fromOffset(arrowWidth, bodyHeight)
 compassArrow.TextSize = compact and 32 or 54

 local bodyLeft = receiverNav and (padX + arrowWidth + 8) or padX
 receiverReadout.Position = UDim2.new(0, bodyLeft, 0, bodyTop)
 receiverReadout.Size = UDim2.new(1, -(bodyLeft + padX), 0, bodyHeight)
 receiverReadout.TextSize = compact and 12 or 17
end

local function setReceiver(on)
 receiverActive = on
 receiver.Visible = on
 lastExitDistance = nil
 compassMode = false
 compassArrow.Visible = false
 receiverHeader.Text = "> EXIT ENERGY DETECTOR"
 receiverNav = false
 layoutReceiver()
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

-- One place decides what the objectives column shows. The panel is visible only
-- when the round wants counters AND the player has not collapsed it; the toggle
-- follows the round alone, so it never disappears out from under a tap.
local function applyObjectiveVisibility()
	objectivesToggle.Text = objectivesCollapsed and "OBJECTIVES  +" or "OBJECTIVES  -"
	-- SetInteractive rather than .Visible: a hidden-but-Active TextButton keeps
	-- eating taps through its transparent background, and this one sits in the
	-- corner every other lower-right HUD wants.
	UIDevice.SetInteractive(objectivesToggle, countersActive)
	objectivePanel.Visible = countersActive and not objectivesCollapsed
	if not objectivePanel.Visible then msgLabel.Visible = false end
	applyPuzzleLayout()
end

local function showCounters(on)
	countersActive = on
	boxesLabel.Visible = on
	carryLabel.Visible = on
	if not on then
		leverLabel.Visible = false
		msgLabel.Visible = false
	end
	-- The row set just changed, so the panel has to be re-measured, not just
	-- shown: this is the call that used to be missing and left the panel at
	-- whatever height the previous round's rows had wanted. (C2)
	applyObjectiveVisibility()
end

objectivesToggle.Activated:Connect(function()
	objectivesCollapsed = not objectivesCollapsed
	applyObjectiveVisibility()
end)

local function refreshLever()
	if not leverPhase then return end
	-- This runs every RenderStepped, so the relayout is gated on the row actually
	-- APPEARING. Writing Visible = true unconditionally here and re-measuring on
	-- every frame would be the same cost as the bug it replaces.
	if not leverLabel.Visible then
		leverLabel.Visible = true
		applyPuzzleLayout()
	end

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
		receiverNav = true
		layoutReceiver()
		receiverReadout.Text = "EXIT VECTOR LOCKED\nFOLLOW DIRECTION"

	elseif ev == "exit" then
		objectiveTitle.Text = "> EXIT ONLINE"
		objectiveTitle.TextColor3 = Color3.fromRGB(120, 255, 160)
		setReceiver(true)
		compassMode = true
		compassArrow.Visible = true
		receiverHeader.Text = "> EXIT ENERGY DETECTOR // NAV"
		receiverNav = true
		layoutReceiver()
		receiverReadout.Text = "EXIT VECTOR LOCKED\nFOLLOW DIRECTION"
		leverPhase = false
		leverLabel.Visible = true
		leverLabel.Text = "EXIT POWERED — FIND THE DOOR"
		leverLabel.TextColor3 = Color3.fromRGB(120, 255, 160)
		applyPuzzleLayout()
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

-- LEVEL2_EXIT_TRANSITION_20260828 / C1_OBJECTIVES_LOWER_RIGHT_20260829.
-- Placement is ONE row: the objectives column (toggle at the corner, panel
-- above it, transient message above that) owns the bottom-right, and the
-- exit-energy detector owns the space to its LEFT. The two are never allowed
-- within LAYOUT.ColumnGap of each other -- the rule the shipped 705x338 layout
-- broke, where a bottom-right panel and a bottom-left detector simply were not
-- far enough apart on a 705px screen and overlapped by 55px.
--
-- DESKTOP reflow, ordered; the first step that clears wins and the later steps
-- are skipped, so a wide screen keeps the authored composition unchanged:
--   1. authored:       detector at x = 132, 310 wide.
--   2. slide left:     detector to SafeLeft (12).
--   3. narrow column:  objectives down to ObjectivesMinWidth (220) at the least.
--   4. narrow detector: down to DetectorMinWidth (240) at the least.
--   5. stack:          only if 1-4 all fail (a desktop viewport under ~506px
--                      wide). The DETECTOR lifts above the objectives column;
--                      the objectives column never leaves the corner, because
--                      staying in that corner is the whole point of C1.
-- Worked examples a regression test can assert:
--   705x338   -> step 2 wins. detector x 12..322, objectives x 387..687.
--   1920x1080 -> step 1 wins. detector x 132..442, objectives x 1602..1902.
--
-- TOUCH keeps the safe placement and gains the same corner discipline: the
-- column goes in the CORRIDOR between the thumbstick and the control column
-- when that corridor is wide enough to be readable (the 150px threshold Level 2
-- Objective UI already uses), where it has the full screen height and is clear
-- of every movement zone at any height; otherwise -- portrait, where the
-- corridor collapses to nothing -- it goes at the bottom of the top band, which
-- in portrait is ~430px tall. Either way the detector keeps the band and gives
-- way horizontally only when the two would share a vertical range.
function applyPuzzleLayout()
	local layout = UIDevice.Layout()

	if not layout.IsTouch then
		local margin = LAYOUT.Margin
		objectivePanelWidth = LAYOUT.ObjectivesWidth
		local detectorLeft = LAYOUT.DetectorLeft
		local detectorWidth = LAYOUT.DetectorWidth
		local function objectivesLeft()
			return layout.Width - margin - objectivePanelWidth
		end
		local function clears()
			return detectorLeft + detectorWidth + LAYOUT.ColumnGap <= objectivesLeft()
		end
		if not clears() then detectorLeft = LAYOUT.SafeLeft end
		if not clears() then
			objectivePanelWidth = math.max(LAYOUT.ObjectivesMinWidth,
				layout.Width - margin - (detectorLeft + detectorWidth + LAYOUT.ColumnGap))
		end
		if not clears() then
			detectorWidth = math.max(LAYOUT.DetectorMinWidth,
				objectivesLeft() - LAYOUT.ColumnGap - detectorLeft)
		end
		local stacked = not clears()

		objectivesToggle.AnchorPoint = Vector2.new(1, 1)
		objectivesToggle.Size = UDim2.fromOffset(LAYOUT.ToggleWidth, LAYOUT.ToggleHeight)
		objectivesToggle.Position = UDim2.new(1, -margin, 1, -margin)

		-- Unconstrained on desktop: the rows always get their natural tier, so a
		-- four-row panel is exactly the authored 300x112.
		local panelBottom = margin + LAYOUT.ToggleHeight + LAYOUT.ToggleGap
		local panelHeight = layoutObjectiveRows(nil)
		objectivePanel.AnchorPoint = Vector2.new(1, 1)
		objectivePanel.Position = UDim2.new(1, -margin, 1, -panelBottom)

		local messageBottom = panelBottom + panelHeight + LAYOUT.MessageGap
		msgLabel.AnchorPoint = Vector2.new(1, 1)
		msgLabel.Size = UDim2.fromOffset(objectivePanelWidth, LAYOUT.MessageHeight)
		msgLabel.Position = UDim2.new(1, -margin, 1, -messageBottom)

		local detectorBottom = LAYOUT.DetectorMargin
		if stacked then
			-- Step 5. Clear the whole COLUMN, message row included -- clearing only
			-- the panel would put the detector's top-right corner through the
			-- transient message, which is exactly the class of miss that produced
			-- C1 in the first place.
			detectorBottom = math.min(
				messageBottom + LAYOUT.MessageHeight + LAYOUT.ColumnGap,
				math.max(LAYOUT.DetectorMargin,
					layout.Height - LAYOUT.DetectorHeight - LAYOUT.SafeLeft))
		end
		receiverHeight = LAYOUT.DetectorHeight
		receiver.AnchorPoint = Vector2.new(0, 1)
		receiver.Size = UDim2.fromOffset(detectorWidth, receiverHeight)
		receiver.Position = UDim2.new(0, detectorLeft, 1, -detectorBottom)
		layoutReceiver()
		return
	end

	local band = layout.TopBand
	local corridor = layout.Corridor
	local columnRight, columnTop, columnBottom
	if corridor.Width >= LAYOUT.CorridorMinWidth then
		-- Landscape handheld. The corridor is clear of the thumbstick, the control
		-- column AND the jump button at every height, so the column gets the whole
		-- screen and the panel never has to be squeezed into the ~75px band -- which
		-- is what forced the 56px clamp that pushed the rows out of the panel.
		columnRight = corridor.Right
		columnTop = layout.SafeTop
		columnBottom = layout.Height - LAYOUT.BottomSafe
		objectivePanelWidth = math.min(LAYOUT.ObjectivesWidth, corridor.Width)
	else
		-- Portrait. The corridor collapses, but the band is tall; stack up from its
		-- bottom-right instead.
		columnRight = band.Right
		columnTop = band.Top
		columnBottom = band.Bottom
		objectivePanelWidth = math.min(LAYOUT.ObjectivesWidth, band.Width)
	end

	-- Floor once, here. The movement-zone edges UIDevice derives are fractional
	-- (they come from thirds and fifths of the viewport) and a HUD that a
	-- regression test asserts to the pixel must not inherit that.
	columnRight = math.floor(columnRight)
	columnTop = math.floor(columnTop)
	columnBottom = math.floor(columnBottom)
	objectivePanelWidth = math.floor(objectivePanelWidth)

	local toggleHeight = LAYOUT.TouchToggleHeight
	local available = columnBottom - columnTop
		- toggleHeight - LAYOUT.ToggleGap
		- LAYOUT.MessageHeight - LAYOUT.MessageGap
	local panelHeight = layoutObjectiveRows(available)

	local toggleTop = columnBottom - toggleHeight
	local panelTop = toggleTop - LAYOUT.ToggleGap - panelHeight
	local messageTop = panelTop - LAYOUT.MessageGap - LAYOUT.MessageHeight
	local columnLeft = columnRight - objectivePanelWidth

	objectivesToggle.AnchorPoint = Vector2.new(1, 0)
	objectivesToggle.Size = UDim2.fromOffset(LAYOUT.ToggleWidth, toggleHeight)
	-- band/corridor figures are ABSOLUTE screen coordinates and this ScreenGui
	-- sets IgnoreGuiInset, so its own y = 0 is one inset higher. Convert, or every
	-- element lands an inset out in whichever direction the gui is configured.
	objectivesToggle.Position = UDim2.fromOffset(columnRight,
		UIDevice.TopOffsetFor(gui, toggleTop))

	objectivePanel.AnchorPoint = Vector2.new(1, 0)
	objectivePanel.Position = UDim2.fromOffset(columnRight,
		UIDevice.TopOffsetFor(gui, panelTop))

	msgLabel.AnchorPoint = Vector2.new(1, 0)
	msgLabel.Size = UDim2.fromOffset(objectivePanelWidth, LAYOUT.MessageHeight)
	msgLabel.Position = UDim2.fromOffset(columnRight,
		UIDevice.TopOffsetFor(gui, messageTop))

	receiverHeight = math.floor(math.max(LAYOUT.DetectorMinHeight,
		math.min(LAYOUT.DetectorHeight, band.Height)))
	local detectorRight = math.floor(band.Right)
	if band.Top + receiverHeight + LAYOUT.ColumnGap > messageTop then
		-- The two share a vertical range, so they have to separate horizontally.
		-- If there is not enough room beside the column for a legible detector,
		-- separate VERTICALLY instead by shortening it: a short detector is
		-- readable, a 40px-wide one is not.
		local sideRoom = (columnLeft - LAYOUT.ColumnGap) - math.floor(band.Left)
		if sideRoom >= LAYOUT.DetectorTouchMinWidth then
			detectorRight = math.min(detectorRight, columnLeft - LAYOUT.ColumnGap)
		else
			receiverHeight = math.floor(math.max(LAYOUT.DetectorMinHeight,
				messageTop - LAYOUT.ColumnGap - band.Top))
		end
	end
	local detectorWidth = math.floor(math.max(LAYOUT.DetectorTouchMinWidth,
		math.min(LAYOUT.DetectorWidth, detectorRight - band.Left)))
	receiver.AnchorPoint = Vector2.new(0, 0)
	receiver.Size = UDim2.fromOffset(detectorWidth, receiverHeight)
	receiver.Position = UDim2.fromOffset(band.Left,
		UIDevice.TopOffsetFor(gui, band.Top))
	layoutReceiver()
end

applyPuzzleLayout()
UIDevice.Changed:Connect(applyPuzzleLayout)
