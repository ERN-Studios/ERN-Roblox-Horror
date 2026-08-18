--!strict
-- Level 3 Reader Client
-- Compact, mobile-safe Energon Reader and server-authored alert toasts.
-- Direction is calculated locally from replicated state; the server remains the
-- sole authority for module collection, exit unlocks, and completion.

local Players = game:GetService("Players")
local ReplicatedStorage = game:GetService("ReplicatedStorage")
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

local function applyLayout()
	local camera = workspace.CurrentCamera
	local viewport = camera and camera.ViewportSize or Vector2.new(800, 600)
	local narrow = viewport.X < 620
	local mobileControls = viewport.X < 900
	local width = math.floor(math.clamp(viewport.X * (narrow and 0.56 or 0.30), 184, 248))
	-- Roblox's landscape touch controls occupy the right edge.  Put the reader
	-- in the clear upper-left lane on phones/tablets; the flashlight and movement
	-- controls remain lower on that side.
	panel.AnchorPoint = if mobileControls then Vector2.new(0, 0) else Vector2.new(1, 0)
	panel.Position = if mobileControls
		then UDim2.fromOffset(10, 64)
		else UDim2.new(1, -10, 0, 70)
	panel.Size = UDim2.fromOffset(width, 101)
	if mobileControls then
		toggleButton.AnchorPoint = Vector2.new(0, 0)
		toggleButton.Position = UDim2.fromOffset(10, 169)
	else
		toggleButton.AnchorPoint = Vector2.new(1, 0)
		toggleButton.Position = UDim2.new(1, -10, 0, 175)
	end
	toggleButton.Size = UDim2.fromOffset(readerHidden and 190 or 92, 28)

	local toastWidth = math.floor(math.clamp(viewport.X - 40, 260, 410))
	toast.Position = UDim2.new(0.5, 0, 0, 8)
	toast.Size = UDim2.fromOffset(toastWidth, 52)
	title.TextSize = narrow and 14 or 16
	progressLabel.TextSize = narrow and 13 or 15
	signalLabel.TextSize = narrow and 11 or 13
end

local function inputHint(): string
	local last = UserInputService:GetLastInputType()
	if last.Name:find("Gamepad", 1, true) then return "[Y]" end
	if last == Enum.UserInputType.Touch then return "TAP" end
	return "[R]"
end

local function updateTogglePresentation()
	local hint = inputHint()
	toggleButton.Text = if readerHidden
		then "OPEN EXIT READER  " .. hint
		else "CLOSE READER  " .. hint
	toggleButton.TextColor3 = if readerHidden then TEXT else ENERGON
	toggleButton.Size = UDim2.fromOffset(readerHidden and 190 or 92, 28)
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
UserInputService.LastInputTypeChanged:Connect(updateTogglePresentation)
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
	return workspace:GetAttribute("SelectedLevel") == LEVEL
		and player:GetAttribute("InRound") == true
		and player:GetAttribute("Escaped") ~= true
end

local function currentWorld(): Model?
	local world = workspace:FindFirstChild(WORLD_NAME)
	return if world and world:IsA("Model") then world else nil
end

local function exitPosition(): Vector3?
	local value = stateAttribute("Level3_ExitPosition", nil)
	if typeof(value) == "Vector3" then return value :: Vector3 end
	local world = currentWorld()
	local finalDoor = world and world:FindFirstChild("Final Service Door", true)
	if finalDoor and finalDoor:IsA("BasePart") then return finalDoor.Position end
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
		local progress = math.max(0, math.floor(tonumber(payload.Progress) or 0))
		local goal = math.max(1, math.floor(tonumber(payload.Goal) or 5))
		-- The final collection is immediately followed by ExitUnlocked.  Let the
		-- stronger calibrated-reader message own the single compact toast slot.
		if progress >= goal then return end
		local collector = cleanText(payload.CollectorName, "A TEAM MEMBER", 36)
		showToast(
			string.format("CD %02d COLLECTED", math.max(1, math.floor(tonumber(payload.CDIndex or payload.ModuleIndex) or progress))),
			string.format("%s  //  PARTY MUSIC %d/%d", collector, math.min(progress, goal), goal),
			"",
			1.8
		)
	elseif kind == "ExitUnlocked" then
		showToast("ALL CDS COLLECTED", "MUSIC OVERRIDE ACCEPTED  //  FOLLOW EXIT SIGNAL", "", 3.0)
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
	panel.Visible = active and not readerHidden
	toggleButton.Visible = active
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
	progressLabel.Text = string.format("CDS [%s]  %d/%d", table.concat(cells), progress, goal)

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
