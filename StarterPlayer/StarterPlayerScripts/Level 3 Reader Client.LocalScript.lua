--!strict
-- Level 3 Reader Client
-- Compact, mobile-safe Energon Reader and server-authored alert toasts.
-- Direction is calculated locally from replicated state; the server remains the
-- sole authority for module collection, exit unlocks, and completion.

local Players = game:GetService("Players")
local ReplicatedStorage = game:GetService("ReplicatedStorage")
local UIDevice = require(ReplicatedStorage:WaitForChild("UIDevice"))
local RunService = game:GetService("RunService")
local TweenService = game:GetService("TweenService")
local UserInputService = game:GetService("UserInputService")
local ContextActionService = game:GetService("ContextActionService")

local player = Players.LocalPlayer

local LEVEL = 3
local WORLD_NAME = "Level 3 Generated World"
local STATE_FOLDER_NAME = "Level 3 State"
local REMOTES_FOLDER_NAME = "Level 3 Remotes"
local CLIENT_EVENT_NAME = "ClientEvent"

local UPDATE_INTERVAL = 0.10
local MAXIMUM_RANGE = 650
local ACCURACY_DEGREES = {155, 105, 64, 36, 18, 5}
local DISTANCE_NOISE = {0.60, 0.42, 0.27, 0.15, 0.07, 0.0}

local ENERGON = Color3.fromRGB(66, 244, 218)
local PANEL = Color3.fromRGB(6, 13, 15)
local TEXT = Color3.fromRGB(218, 237, 223)
local MUTED = Color3.fromRGB(153, 174, 166)
local AMBER = Color3.fromRGB(231, 218, 145)

local gui = Instance.new("ScreenGui")
gui.Name = "Level3ReaderGui"
gui.ResetOnSpawn = false
gui.IgnoreGuiInset = false
gui.DisplayOrder = 42
gui.ZIndexBehavior = Enum.ZIndexBehavior.Sibling
gui.Parent = player:WaitForChild("PlayerGui")

local panel = Instance.new("Frame")
panel.Name = "ReaderPanel"
panel.AnchorPoint = Vector2.new(1, 0)
panel.BackgroundColor3 = PANEL
panel.BackgroundTransparency = 0.12
panel.BorderSizePixel = 0
panel.Visible = false
panel.Parent = gui

local panelCorner = Instance.new("UICorner")
panelCorner.CornerRadius = UDim.new(0, 6)
panelCorner.Parent = panel

local panelStroke = Instance.new("UIStroke")
panelStroke.Color = ENERGON
panelStroke.Thickness = 2
panelStroke.Transparency = 0.25
panelStroke.Parent = panel

local title = Instance.new("TextLabel")
title.Name = "Title"
title.BackgroundTransparency = 1
title.Position = UDim2.fromOffset(10, 5)
title.Size = UDim2.new(1, -20, 0, 18)
title.Font = Enum.Font.Code
title.Text = "> EXIT DOOR READER"
title.TextColor3 = ENERGON
title.TextSize = 16
title.TextXAlignment = Enum.TextXAlignment.Left
title.Parent = panel

local progressLabel = Instance.new("TextLabel")
progressLabel.Name = "Calibration"
progressLabel.BackgroundTransparency = 1
progressLabel.Position = UDim2.fromOffset(10, 26)
progressLabel.Size = UDim2.new(1, -20, 0, 18)
progressLabel.Font = Enum.Font.Code
progressLabel.Text = "[□□□□□]  0/5"
progressLabel.TextColor3 = TEXT
progressLabel.TextSize = 15
progressLabel.TextXAlignment = Enum.TextXAlignment.Left
progressLabel.Parent = panel

local track = Instance.new("Frame")
track.Name = "DirectionTrack"
track.Position = UDim2.fromOffset(12, 51)
track.Size = UDim2.new(1, -24, 0, 19)
track.BackgroundColor3 = Color3.fromRGB(18, 29, 29)
track.BackgroundTransparency = 0.08
track.BorderSizePixel = 0
track.Parent = panel

local trackCorner = Instance.new("UICorner")
trackCorner.CornerRadius = UDim.new(0, 4)
trackCorner.Parent = track

local centerLine = Instance.new("Frame")
centerLine.Name = "Center"
centerLine.AnchorPoint = Vector2.new(0.5, 0.5)
centerLine.Position = UDim2.fromScale(0.5, 0.5)
centerLine.Size = UDim2.fromOffset(2, 13)
centerLine.BackgroundColor3 = Color3.fromRGB(74, 112, 105)
centerLine.BorderSizePixel = 0
centerLine.Parent = track

local needle = Instance.new("Frame")
needle.Name = "Needle"
needle.AnchorPoint = Vector2.new(0.5, 0.5)
needle.Position = UDim2.fromScale(0.5, 0.5)
needle.Size = UDim2.fromOffset(5, 17)
needle.BackgroundColor3 = ENERGON
needle.BorderSizePixel = 0
needle.Parent = track

local needleCorner = Instance.new("UICorner")
needleCorner.CornerRadius = UDim.new(1, 0)
needleCorner.Parent = needle

local signalLabel = Instance.new("TextLabel")
signalLabel.Name = "Signal"
signalLabel.BackgroundTransparency = 1
signalLabel.Position = UDim2.fromOffset(10, 75)
signalLabel.Size = UDim2.new(1, -20, 0, 19)
signalLabel.Font = Enum.Font.Code
signalLabel.Text = "SIGNAL // NO TRACE"
signalLabel.TextColor3 = AMBER
signalLabel.TextSize = 13
signalLabel.TextTruncate = Enum.TextTruncate.AtEnd
signalLabel.TextXAlignment = Enum.TextXAlignment.Left
signalLabel.Parent = panel

local toggleButton = Instance.new("TextButton")
toggleButton.Name = "ReaderToggle"
toggleButton.AutoButtonColor = true
toggleButton.AnchorPoint = Vector2.new(1, 0)
toggleButton.BackgroundColor3 = PANEL
toggleButton.BackgroundTransparency = 0.10
toggleButton.BorderSizePixel = 0
toggleButton.Font = Enum.Font.Code
toggleButton.Text = "CLOSE READER [R]"
toggleButton.TextColor3 = ENERGON
toggleButton.TextSize = 12
toggleButton.Visible = false
toggleButton.Parent = gui
local toggleCorner = Instance.new("UICorner")
toggleCorner.CornerRadius = UDim.new(0, 5)
toggleCorner.Parent = toggleButton
local toggleStroke = Instance.new("UIStroke")
toggleStroke.Color = ENERGON
toggleStroke.Thickness = 1.5
toggleStroke.Transparency = 0.34
toggleStroke.Parent = toggleButton

local readerHidden = false

local toast = Instance.new("Frame")
toast.Name = "AlertToast"
toast.AnchorPoint = Vector2.new(0.5, 0)
toast.BackgroundColor3 = PANEL
toast.BackgroundTransparency = 0.08
toast.BorderSizePixel = 0
toast.Visible = false
toast.ZIndex = 20
toast.Parent = gui

local toastCorner = Instance.new("UICorner")
toastCorner.CornerRadius = UDim.new(0, 7)
toastCorner.Parent = toast

local toastStroke = Instance.new("UIStroke")
toastStroke.Color = ENERGON
toastStroke.Thickness = 2
toastStroke.Transparency = 0.18
toastStroke.Parent = toast

local toastTitle = Instance.new("TextLabel")
toastTitle.BackgroundTransparency = 1
toastTitle.Position = UDim2.fromOffset(12, 6)
toastTitle.Size = UDim2.new(1, -24, 0, 20)
toastTitle.Font = Enum.Font.Code
toastTitle.TextColor3 = ENERGON
toastTitle.TextSize = 17
toastTitle.TextXAlignment = Enum.TextXAlignment.Left
toastTitle.TextTruncate = Enum.TextTruncate.AtEnd
toastTitle.ZIndex = 21
toastTitle.Parent = toast

local toastBody = Instance.new("TextLabel")
toastBody.BackgroundTransparency = 1
toastBody.Position = UDim2.fromOffset(12, 28)
toastBody.Size = UDim2.new(1, -24, 1, -34)
toastBody.Font = Enum.Font.Code
toastBody.TextColor3 = TEXT
toastBody.TextSize = 13
toastBody.TextWrapped = true
toastBody.TextXAlignment = Enum.TextXAlignment.Left
toastBody.TextYAlignment = Enum.TextYAlignment.Top
toastBody.ZIndex = 21
toastBody.Parent = toast

-- C4_READER_TOUCH_CONTROLS_20260829 -- WHAT SHIPPED BROKEN.
-- The reader's one control was 190x28 on every form factor. 28px is well under
-- a usable tap target, and the STACKED touch arrangement (panel, then toggle
-- 6px under it) was selected whenever panel + toggle did not fit SIDE BY SIDE
-- at the panel's FULL width -- and then simply overflowed the band it was
-- handed. Measured at 568x320 the clear band is 380x69 at (12,66): the stack
-- ran to y=174, i.e. 39px BELOW the band and inside the thumbstick's activation
-- region, so the control was at once too small to hit and sitting on movement
-- input.
--
-- The shape that prevents it:
--   * a touch control is TOUCH_TOGGLE_HEIGHT tall, never less;
--   * side-by-side is reached by NARROWING the panel (never below
--     READER_MIN_WIDTH) instead of falling through to a stack that cannot fit;
--   * stacking is used only when the band genuinely holds
--     READER_PANEL_HEIGHT + READER_GAP + the toggle height;
--   * nothing is ever placed past band.Right or band.Bottom;
--   * OPEN and CLOSE remain ONE control in ONE place -- its size and position
--     are derived from the LAYOUT alone and never from readerHidden, so the
--     button cannot move or resize under the finger that just pressed it.
local TOGGLE_WIDTH = 190
local TOGGLE_HEIGHT = 28
local TOUCH_TOGGLE_WIDTH = 150
local TOUCH_TOGGLE_HEIGHT = 44
local READER_PANEL_HEIGHT = 101
local READER_PANEL_MIN_HEIGHT = 58
local READER_MIN_WIDTH = 150
local READER_GAP = 6

-- The one place the control's footprint is decided. Both states read it, so
-- "OPEN" and "CLOSE" are guaranteed identical in size.
local function toggleMetrics(): (number, number)
	if UIDevice.IsTouch() then return TOUCH_TOGGLE_WIDTH, TOUCH_TOGGLE_HEIGHT end
	return TOGGLE_WIDTH, TOGGLE_HEIGHT
end

local function applyLayout()
	local layoutInfo = UIDevice.Layout()
	local viewport = layoutInfo.Viewport
	local narrow = viewport.X < 620
	local mobileControls = layoutInfo.IsTouch
	local width = math.floor(math.clamp(viewport.X * (narrow and 0.56 or 0.30), 184, 248))
	local panelHeight = READER_PANEL_HEIGHT
	local compactLandscape = false
	local panelLeft, panelTop = 10, 70
	local toggleLeft, toggleTop = 10, 175
	local toggleWidth, toggleHeight = toggleMetrics()

	if mobileControls then
		local band = layoutInfo.TopBand
		width = math.min(width, band.Width)
		panelLeft = band.Left
		panelTop = band.Top
		-- The arrangement is chosen by whether the band can HOLD the stack, not by
		-- whether side-by-side happens to fit at the panel's authored width. That
		-- inversion is what let the old stack run off the bottom of the band.
		if band.Height >= READER_PANEL_HEIGHT + READER_GAP + toggleHeight then
			-- Tall band: portrait phones and every tablet. Stack, as authored.
			panelHeight = READER_PANEL_HEIGHT
			toggleLeft = panelLeft
			toggleTop = panelTop + panelHeight + READER_GAP
		else
			-- Short band: a landscape phone, ~69-75px tall but 380-517px wide. The
			-- PANEL yields the width the 44px control needs; the control is then
			-- centred on the panel and clamped so it cannot pass band.Right or
			-- band.Bottom even on a band shorter than the panel's own minimum.
			compactLandscape = true
			width = math.max(READER_MIN_WIDTH,
				math.min(width, band.Width - toggleWidth - READER_GAP))
			toggleWidth = math.min(toggleWidth,
				math.max(0, band.Right - (panelLeft + width + READER_GAP)))
			-- Floored: the band's own bottom edge is a third of a viewport and comes
			-- through fractional, and a control asserted to the pixel must not.
			panelHeight = math.max(READER_PANEL_MIN_HEIGHT,
				math.min(82, math.floor(band.Height)))
			toggleLeft = panelLeft + width + READER_GAP
			toggleTop = math.min(
				panelTop + math.max(0, math.floor((panelHeight - toggleHeight) * .5)),
				math.max(panelTop, math.floor(band.Bottom) - toggleHeight))
		end
		panel.AnchorPoint = Vector2.new(0, 0)
		panel.Position = UDim2.fromOffset(panelLeft,
			UIDevice.TopOffsetFor(gui, panelTop))
		toggleButton.AnchorPoint = Vector2.new(0, 0)
		toggleButton.Position = UDim2.fromOffset(toggleLeft,
			UIDevice.TopOffsetFor(gui, toggleTop))
	else
		panel.AnchorPoint = Vector2.new(1, 0)
		panel.Position = UDim2.new(1, -10, 0, 70)
		toggleButton.AnchorPoint = Vector2.new(1, 0)
		toggleButton.Position = UDim2.new(1, -10, 0, 175)
	end
	panel.Size = UDim2.fromOffset(width, panelHeight)
	toggleButton.Size = UDim2.fromOffset(toggleWidth, toggleHeight)

	if compactLandscape then
		title.Position = UDim2.fromOffset(8, 2)
		title.Size = UDim2.new(1, -16, 0, 12)
		progressLabel.Position = UDim2.fromOffset(8, 15)
		progressLabel.Size = UDim2.new(1, -16, 0, 12)
		track.Position = UDim2.fromOffset(9, 29)
		track.Size = UDim2.new(1, -18, 0, 11)
		centerLine.Size = UDim2.fromOffset(2, 7)
		needle.Size = UDim2.fromOffset(4, 10)
		signalLabel.Position = UDim2.fromOffset(8, 43)
		signalLabel.Size = UDim2.new(1, -16, 1, -45)
		title.TextSize = 11
		progressLabel.TextSize = 10
		signalLabel.TextSize = 9
	else
		title.Position = UDim2.fromOffset(10, 5)
		title.Size = UDim2.new(1, -20, 0, 18)
		progressLabel.Position = UDim2.fromOffset(10, 26)
		progressLabel.Size = UDim2.new(1, -20, 0, 18)
		track.Position = UDim2.fromOffset(12, 51)
		track.Size = UDim2.new(1, -24, 0, 19)
		centerLine.Size = UDim2.fromOffset(2, 13)
		needle.Size = UDim2.fromOffset(5, 17)
		signalLabel.Position = UDim2.fromOffset(10, 75)
		signalLabel.Size = UDim2.new(1, -20, 0, 19)
		title.TextSize = narrow and 14 or 16
		progressLabel.TextSize = narrow and 13 or 15
		signalLabel.TextSize = narrow and 11 or 13
	end

	local toastWidth = math.floor(math.clamp(viewport.X - 40, 260, 410))
	toast.Position = UDim2.new(0.5, 0, 0, 8)
	toast.Size = UDim2.fromOffset(toastWidth, 52)
end

-- This control used to be sized from its own state (190 open / 92 closed) and
-- captioned from the LAST INPUT TYPE. Both were wrong. The size change made the
-- button jump under the finger every time it was pressed, and last-input meant
-- one stray mouse event on a phone put "[R]" on a device with no R key -- and
-- one screen touch on a desktop replaced "[R]" with "TAP".
--
-- Now: ONE constant width and one anchored position for both states, and the
-- binding comes from UIDevice, which answers on form factor alone.

local function updateTogglePresentation(hiddenOverride: boolean?)
	local presentedHidden = if type(hiddenOverride) == "boolean" then hiddenOverride else readerHidden
	toggleButton.Text = if presentedHidden
		then UIDevice.Caption("OPEN EXIT READER", "[R]", "[Y]")
		else UIDevice.Caption("CLOSE READER", "[R]", "[Y]")
	toggleButton.TextColor3 = if presentedHidden then TEXT else ENERGON
	-- Deliberately NO size write here. The footprint belongs to applyLayout and
	-- to applyLayout only; writing the desktop constants from this state-change
	-- path is what used to shrink a phone's 44px control back to 28px the first
	-- time it was tapped.
end

local function setReaderHidden(hidden: boolean)
	readerHidden = hidden
	updateTogglePresentation()
end

toggleButton.Activated:Connect(function() setReaderHidden(not readerHidden) end)
ContextActionService:BindAction("Level3ToggleExitReader", function(_, inputState)
	if inputState == Enum.UserInputState.Begin
		and UserInputService:GetFocusedTextBox() == nil
		and workspace:GetAttribute("SelectedLevel") == LEVEL
		and player:GetAttribute("InRound") == true
		and player:GetAttribute("Escaped") ~= true then
		setReaderHidden(not readerHidden)
		return Enum.ContextActionResult.Sink
	end
	return Enum.ContextActionResult.Pass
end, false, Enum.KeyCode.R, Enum.KeyCode.ButtonY)
-- Rebuild on UIDevice.Changed, which fires for viewport, inset, form factor,
-- and (on desktop only) last-input changes. On a phone this can never fire for
-- an input flip, which is the whole point.
UIDevice.Changed:Connect(function()
	updateTogglePresentation()
	applyLayout()
end)
updateTogglePresentation()

local viewportConnection: RBXScriptConnection? = nil
local function bindCamera()
	if viewportConnection then viewportConnection:Disconnect() end
	local camera = workspace.CurrentCamera
	if camera then
		viewportConnection = camera:GetPropertyChangedSignal("ViewportSize"):Connect(applyLayout)
	end
	applyLayout()
end
workspace:GetPropertyChangedSignal("CurrentCamera"):Connect(bindCamera)
bindCamera()

local function stateFolder(): Folder?
	local folder = ReplicatedStorage:FindFirstChild(STATE_FOLDER_NAME)
	return if folder and folder:IsA("Folder") then folder else nil
end

local function stateAttribute(name: string, workspaceMirror: string?): any
	local state = stateFolder()
	local value = state and state:GetAttribute(name)
	if value == nil and workspaceMirror then value = workspace:GetAttribute(workspaceMirror) end
	return value
end

local function numberAttribute(name: string, workspaceMirror: string?, fallback: number): number
	local value = stateAttribute(name, workspaceMirror)
	return if type(value) == "number" then value else fallback
end

local function isActive(): boolean
	local levelActive = workspace:GetAttribute("SelectedLevel") == LEVEL
		and player:GetAttribute("InRound") == true
		and player:GetAttribute("Escaped") ~= true
	if RunService:IsStudio()
		and player:GetAttribute("UIRegressionForceLevel3Reader") == true then
		levelActive = true
	end
	return levelActive
		and player:GetAttribute("ZyntraDispatchClientActive") ~= true
		and player:GetAttribute("Level3_Hiding") ~= true
end

local function currentWorld(): Model?
	local world = workspace:FindFirstChild(WORLD_NAME)
	return if world and world:IsA("Model") then world else nil
end

local function exitPosition(): Vector3?
	local value = stateAttribute("Level3_ExitPosition", nil)
	if typeof(value) == "Vector3" then return value :: Vector3 end
	return nil
end

local function generationMatches(payload: {[any]: any}): boolean
	local payloadGeneration = payload.Generation
	if type(payloadGeneration) ~= "number" then return true end
	local world = currentWorld()
	local liveGeneration = world and world:GetAttribute("Level3_Generation")
	return type(liveGeneration) ~= "number" or liveGeneration == payloadGeneration
end

local toastSerial = 0
local function cleanText(value: any, fallback: string, maximum: number): string
	local text = (if type(value) == "string" then value else fallback) :: string
	text = text:gsub("[%c]", " ")
	return text:sub(1, maximum)
end

local function showToast(titleText: any, subtitle: any, instruction: any, duration: any)
	if not isActive() then return end
	toastSerial += 1
	local serial = toastSerial
	toastTitle.Text = cleanText(titleText, "LEVEL 3", 72)
	local first = cleanText(subtitle, "", 110)
	local second = cleanText(instruction, "", 110)
	toastBody.Text = if first ~= "" and second ~= "" then first .. "\n" .. second else first .. second
	toast.BackgroundTransparency = 0.08
	toastTitle.TextTransparency = 0
	toastBody.TextTransparency = 0
	toastStroke.Transparency = 0.18
	toast.Visible = true
	-- The alert owns the same safe top band for its brief lifetime. Do not draw
	-- the reader underneath it; updateReader restores both controls afterwards.
	panel.Visible = false
	toggleButton.Visible = false
	local hold = math.clamp(if type(duration) == "number" then duration else 2.4, 0.8, 6)
	task.delay(hold, function()
		if serial ~= toastSerial or not toast.Parent then return end
		local info = TweenInfo.new(0.28, Enum.EasingStyle.Quad, Enum.EasingDirection.Out)
		TweenService:Create(toast, info, {BackgroundTransparency = 1}):Play()
		TweenService:Create(toastTitle, info, {TextTransparency = 1}):Play()
		TweenService:Create(toastBody, info, {TextTransparency = 1}):Play()
		TweenService:Create(toastStroke, info, {Transparency = 1}):Play()
		task.delay(0.30, function()
			if serial == toastSerial and toast.Parent then toast.Visible = false end
		end)
	end)
end

local function handleClientEvent(payload: any)
	if type(payload) ~= "table" or not generationMatches(payload) then return end
	local kind = payload.Type
	if kind == "Alert" then
		showToast(payload.Title, payload.Subtitle, payload.Instruction, payload.Duration)
	elseif kind == "ModuleCollected" then
		local progress = math.max(0, math.floor(tonumber(payload.CollectedProgress or payload.Progress) or 0))
		local goal = math.max(1, math.floor(tonumber(payload.Goal) or 5))
		local collector = cleanText(payload.CollectorName, "A TEAM MEMBER", 36)
		showToast(
			string.format("CD %02d SECURED", math.max(1, math.floor(tonumber(payload.CDIndex or payload.ModuleIndex) or progress))),
			string.format("%s  //  FOUND %d/%d", collector, math.min(progress, goal), goal),
			if payload.RecoveredDrop == true then "RECOVERED  //  CARRY IT TO THE DISC PLAYER"
				else "CARRY IT TO THE DISC PLAYER",
			2.2
		)
	elseif kind == "CDInserted" then
		local progress = math.max(0, math.floor(tonumber(payload.InsertedCount or payload.Progress) or 0))
		local goal = math.max(1, math.floor(tonumber(payload.Goal) or 5))
		if progress >= goal then return end
		local depositor = cleanText(payload.DepositorName, "A TEAM MEMBER", 36)
		showToast(
			string.format("DISC RELAY %d/%d", math.min(progress, goal), goal),
			string.format("%s INSERTED %d CD%s", depositor,
				math.max(1, math.floor(tonumber(payload.Count) or 1)),
				(if math.floor(tonumber(payload.Count) or 1) == 1 then "" else "S")),
			"OTHER HOLDERS MUST INSERT THEIRS",
			2.3
		)
	elseif kind == "CDDropped" then
		showToast("A CARRIED CD WAS DROPPED", "RECOVER IT AT THE PLAYER'S LAST POSITION", "", 2.4)
	elseif kind == "CDTransferred" and payload.RecipientUserId == player.UserId then
		showToast("TEAM CD TRANSFERRED", "A DEPARTING PLAYER'S CD IS NOW ON YOUR BACK",
			"TAKE IT TO THE DISC PLAYER", 2.8)
	elseif kind == "ExitUnlocked" then
		showToast("ALL CDS INSERTED", "WALL FRAME REVEALED  //  FOLLOW EXIT SIGNAL", "", 3.0)
	end
end

local clientEventConnection: RBXScriptConnection? = nil
local boundClientEvent: RemoteEvent? = nil
local function bindClientEvent()
	local folder = ReplicatedStorage:FindFirstChild(REMOTES_FOLDER_NAME)
	local candidate = folder and folder:FindFirstChild(CLIENT_EVENT_NAME)
	local event = if candidate and candidate:IsA("RemoteEvent") then candidate else nil
	if event == boundClientEvent then return end
	if clientEventConnection then clientEventConnection:Disconnect() end
	clientEventConnection = nil
	boundClientEvent = event
	if event then clientEventConnection = event.OnClientEvent:Connect(handleClientEvent) end
end

ReplicatedStorage.ChildAdded:Connect(bindClientEvent)
ReplicatedStorage.ChildRemoved:Connect(bindClientEvent)
bindClientEvent()

local smoothedNeedle = 0
local smoothedSignal = 0
local accumulated = 0

local function signedPlanarAngle(forward: Vector3, target: Vector3): number
	local a = Vector3.new(forward.X, 0, forward.Z)
	local b = Vector3.new(target.X, 0, target.Z)
	if a.Magnitude < 0.001 or b.Magnitude < 0.001 then return 0 end
	a = a.Unit
	b = b.Unit
	return math.atan2(a.X * b.Z - a.Z * b.X, math.clamp(a:Dot(b), -1, 1))
end

local function updateReader(dt: number)
	local active = isActive()
	local hidden = readerHidden
	if RunService:IsStudio() then
		local forced = player:GetAttribute("UIRegressionForceReaderHidden")
		if type(forced) == "boolean" then hidden = forced end
		-- Keep the test-only presentation in lockstep with the test-only visibility
		-- override. Production input still writes the real readerHidden state.
		updateTogglePresentation(hidden)
	end
	panel.Visible = active and not hidden and not toast.Visible
	toggleButton.Visible = active and not toast.Visible
	if not active then
		toastSerial += 1
		toast.Visible = false
		return
	end

	local goal = math.clamp(math.floor(numberAttribute("Level3_ModuleGoal", "Level3ModuleGoal", 5)), 1, 12)
	local progress = math.clamp(math.floor(numberAttribute("Level3_ModuleProgress", "Level3Modules", 0)), 0, goal)
	local index = math.clamp(progress + 1, 1, #ACCURACY_DEGREES)
	local cells: {string} = {}
	for cell = 1, goal do cells[cell] = if cell <= progress then "■" else "□" end
	progressLabel.Text = string.format("DISC RELAY [%s]  %d/%d", table.concat(cells), progress, goal)

	local character = player.Character
	local root = character and character:FindFirstChild("HumanoidRootPart")
	local target = exitPosition()
	if not (root and root:IsA("BasePart") and target) then
		signalLabel.Text = "SIGNAL // NO TRACE"
		signalLabel.TextColor3 = MUTED
		return
	end

	local offset = target - root.Position
	local distance = Vector3.new(offset.X, 0, offset.Z).Magnitude
	local camera = workspace.CurrentCamera
	local forward = camera and camera.CFrame.LookVector or root.CFrame.LookVector
	local trueAngle = signedPlanarAngle(forward, offset)
	local time = os.clock()
	local angularNoise = math.noise(time * 0.43, progress * 2.71) * math.rad(ACCURACY_DEGREES[index])
	local noisyAngle = trueAngle + angularNoise
	local needleTarget = math.clamp(noisyAngle / math.rad(90), -1, 1)

	local facing = math.clamp((math.cos(noisyAngle) + 1) * 0.5, 0, 1)
	local rangeSignal = 1 - math.clamp(distance / MAXIMUM_RANGE, 0, 1)
	local distanceJitter = math.noise(time * 0.61, 19 + progress) * DISTANCE_NOISE[index]
	local signalTarget = math.clamp(facing * 0.72 + rangeSignal * 0.28 + distanceJitter, 0, 1)
	local response = 1.3 + progress * 0.72
	local alpha = 1 - math.exp(-dt * response)
	smoothedNeedle += (needleTarget - smoothedNeedle) * alpha
	smoothedSignal += (signalTarget - smoothedSignal) * alpha
	needle.Position = UDim2.new(0.5 + smoothedNeedle * 0.43, 0, 0.5, 0)

	local signalBars = math.clamp(math.floor(smoothedSignal * 5 + 0.5), 0, 5)
	local bars = string.rep("▮", signalBars) .. string.rep("□", 5 - signalBars)
	local unlocked = stateAttribute("Level3_ExitUnlocked", "Level3ExitUnlocked") == true
	if unlocked then
		signalLabel.Text = string.format("SIGNAL // %s  %dm", bars, math.floor(distance / 3.571 + 0.5))
		signalLabel.TextColor3 = ENERGON
		panelStroke.Color = ENERGON
	elseif progress == 0 then
		signalLabel.Text = "SIGNAL // UNSTABLE"
		signalLabel.TextColor3 = MUTED
		panelStroke.Color = Color3.fromRGB(75, 122, 116)
	elseif progress < math.ceil(goal * 0.6) then
		signalLabel.Text = "SIGNAL // " .. bars .. "  WEAK"
		signalLabel.TextColor3 = AMBER
		panelStroke.Color = Color3.fromRGB(89, 170, 159)
	else
		signalLabel.Text = "SIGNAL // " .. bars .. "  CALIBRATING"
		signalLabel.TextColor3 = TEXT
		panelStroke.Color = ENERGON
	end
	needle.BackgroundColor3 = if unlocked then Color3.fromRGB(128, 255, 222) else ENERGON
end

RunService.RenderStepped:Connect(function(dt)
	accumulated += dt
	if accumulated < UPDATE_INTERVAL then return end
	local elapsed = accumulated
	accumulated = 0
	bindClientEvent()
	updateReader(elapsed)
end)
