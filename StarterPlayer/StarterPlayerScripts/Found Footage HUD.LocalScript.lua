-- Found Footage HUD (UI concepts, direction B, 2026-10-03).
--
-- Two things, both additive and both drawn BENEATH every existing HUD panel:
--   1. the camcorder frame of a round: corner brackets on every device, and on a
--      pointer device a REC mark with the round's running timecode;
--   2. the interaction prompt, drawn next to the object it belongs to as a dark
--      plate with the key, the action and a hold ring round the key, instead of Roblox's default.
--
-- Nothing here owns game state. The frame follows `InRound`; the prompt renderer
-- only draws prompts the engine has already decided to show, so a script that
-- disables a prompt or turns ProximityPromptService off is obeyed as before.
local Players = game:GetService("Players")
local ReplicatedStorage = game:GetService("ReplicatedStorage")
local RunService = game:GetService("RunService")
local ProximityPromptService = game:GetService("ProximityPromptService")

local player = Players.LocalPlayer
local playerGui = player:WaitForChild("PlayerGui")
local UIDevice = require(ReplicatedStorage:WaitForChild("UIDevice"))

local PAPER = Color3.fromRGB(236, 232, 218)      -- off-white type
local INK = Color3.fromRGB(10, 10, 9)            -- near-black plates
local MUSTARD = Color3.fromRGB(214, 176, 72)     -- the backrooms wallpaper accent
local RED = Color3.fromRGB(226, 52, 44)

---------------------------------------------------------------------------
-- 1. The frame
---------------------------------------------------------------------------
local frameGui = Instance.new("ScreenGui")
frameGui.Name = "FoundFootageHUD"
frameGui.ResetOnSpawn = false
frameGui.IgnoreGuiInset = true
frameGui.DisplayOrder = 4          -- under every panel, cover and modal
frameGui.Enabled = false
frameGui.Parent = playerGui

local brackets = {}
for _, corner in ipairs({ { 0, 0 }, { 1, 0 }, { 0, 1 }, { 1, 1 } }) do
	for _, horizontal in ipairs({ true, false }) do
		local bar = Instance.new("Frame")
		bar.Name = "Bracket"
		bar.BackgroundColor3 = PAPER
		bar.BackgroundTransparency = 0.3
		bar.BorderSizePixel = 0
		bar.AnchorPoint = Vector2.new(corner[1], corner[2])
		bar.Parent = frameGui
		table.insert(brackets, { Bar = bar, X = corner[1], Y = corner[2], Horizontal = horizontal })
	end
end

local rec = Instance.new("Frame")
rec.Name = "Rec"
rec.BackgroundTransparency = 1
rec.Size = UDim2.fromOffset(150, 20)
rec.Parent = frameGui
local dot = Instance.new("Frame")
dot.Name = "Dot"
dot.Size = UDim2.fromOffset(10, 10)
dot.Position = UDim2.fromOffset(0, 5)
dot.BackgroundColor3 = RED
dot.BorderSizePixel = 0
dot.Parent = rec
local dotCorner = Instance.new("UICorner")
dotCorner.CornerRadius = UDim.new(1, 0)
dotCorner.Parent = dot
local timecode = Instance.new("TextLabel")
timecode.Name = "Timecode"
timecode.BackgroundTransparency = 1
timecode.Position = UDim2.fromOffset(18, 0)
timecode.Size = UDim2.fromOffset(132, 20)
timecode.Font = Enum.Font.RobotoMono
timecode.TextSize = 14
timecode.TextColor3 = PAPER
timecode.TextTransparency = 0.15
timecode.TextXAlignment = Enum.TextXAlignment.Left
timecode.Text = "REC 00:00:00"
timecode.Parent = rec

local roundStarted = 0
local function placeFrame()
	local layout = UIDevice.Layout()
	local safe = layout.Safe
	local arm = layout.IsTouch and 18 or 26
	-- HAIRLINES, 4px in from the safe edge: outside the torch gauge's 12px margin
	-- and every panel's own, so the frame never crosses a control. One pixel is
	-- also what UIRegression treats as a rule rather than a panel -- its overlap
	-- scan measures rectangles more than 1px in both directions.
	local inset = 4
	for _, item in ipairs(brackets) do
		local x = item.X == 0 and (safe.Left + inset) or (safe.Right - inset)
		local y = item.Y == 0 and (safe.Top + inset) or (safe.Bottom - inset)
		item.Bar.Size = item.Horizontal and UDim2.fromOffset(arm, 1) or UDim2.fromOffset(1, arm)
		item.Bar.Position = UDim2.fromOffset(x, y)
	end
	-- The REC mark is pointer-only: a phone's top edge already belongs to the
	-- exit chip, the objectives and the engine's own buttons.
	rec.Visible = not layout.IsTouch
	rec.Position = UDim2.fromOffset(safe.Left + inset + 6, safe.Top + inset + 46)
end

local function frameWanted()
	return player:GetAttribute("InRound") == true
		and player:GetAttribute("LobbyLoadingOpen") ~= true
		and player:GetAttribute("LuckyWheelOpen") ~= true
end

local function refreshFrame()
	local wanted = frameWanted()
	if wanted and not frameGui.Enabled then
		roundStarted = os.clock()
		placeFrame()
	end
	frameGui.Enabled = wanted
end
for _, attribute in ipairs({ "InRound", "LobbyLoadingOpen", "LuckyWheelOpen" }) do
	player:GetAttributeChangedSignal(attribute):Connect(refreshFrame)
end
UIDevice.Changed:Connect(function()
	if frameGui.Enabled then placeFrame() end
end)
refreshFrame()

task.spawn(function()
	while true do
		task.wait(0.1)
		if frameGui.Enabled and rec.Visible then
			local elapsed = os.clock() - roundStarted
			timecode.Text = string.format("REC %02d:%02d:%02d", math.floor(elapsed / 3600) % 100,
				math.floor(elapsed / 60) % 60, math.floor(elapsed) % 60)
			-- one blink a second; steady for anyone who asked for less flashing
			dot.Visible = player:GetAttribute("ReduceFlashing") == true or elapsed % 1 < 0.6
		end
	end
end)

---------------------------------------------------------------------------
-- 2. The interaction prompt, next to the object
---------------------------------------------------------------------------
local KEY_NAMES = {
	[Enum.KeyCode.ButtonX] = "X", [Enum.KeyCode.ButtonY] = "Y", [Enum.KeyCode.ButtonA] = "A",
	[Enum.KeyCode.ButtonB] = "B", [Enum.KeyCode.ButtonR1] = "RB", [Enum.KeyCode.ButtonL1] = "LB",
	[Enum.KeyCode.ButtonR2] = "RT", [Enum.KeyCode.ButtonL2] = "LT",
}
local function keyName(code)
	return KEY_NAMES[code] or code.Name
end

local shown = {}

local function build(prompt)
	local layout = UIDevice.Layout()
	local touch = layout.IsTouch
	local binding = UIDevice.Binding(keyName(prompt.KeyboardKeyCode), keyName(prompt.GamepadKeyCode))
	local keyText = binding ~= "" and binding or "TAP"
	local action = string.upper(prompt.ActionText ~= "" and prompt.ActionText or "Interact")
	local object = string.upper(prompt.ObjectText)
	local actionSize = touch and 17 or 15
	-- HOLD_RING_20261004 (owner: the 3px bar under the plate was nearly invisible). The key is a round badge and
	-- a hold fills a ring round it, clockwise from the top.
	local RING, GAP = 4, 2
	local keyWidth = math.clamp(math.max(touch and 40 or 30, #keyText * 9 + 12), 30, 50)   -- the badge's diameter
	keyWidth += keyWidth % 2          -- even, so the ring's two halves meet on a whole pixel (an odd size leaves a seam)
	local ringSize = keyWidth + 2 * (GAP + RING)
	local textWidth = math.max(#action * (actionSize * 0.62), #object * 7) + 8
	local height = ringSize + 8
	local width = math.clamp(6 + ringSize + 10 + textWidth + 12, 120, 340)

	local board = Instance.new("BillboardGui")
	board.Name = "InteractionPrompt"
	board.Adornee = prompt.Parent
	board.AlwaysOnTop = true
	board.Active = true
	board.ResetOnSpawn = false
	board.Size = UDim2.fromOffset(width, height)
	board.SizeOffset = Vector2.new(prompt.UIOffset.X / width, prompt.UIOffset.Y / height)
	board.MaxDistance = prompt.MaxActivationDistance + 8

	local plate = Instance.new("TextButton")
	plate.Name = "Plate"
	plate.Text = ""
	plate.AutoButtonColor = false
	plate.Size = UDim2.new(1, 0, 0, height)
	plate.BackgroundColor3 = INK
	plate.BackgroundTransparency = 0.12
	plate.BorderSizePixel = 0
	plate.Parent = board
	local plateCorner = Instance.new("UICorner")
	plateCorner.CornerRadius = UDim.new(0, 5)
	plateCorner.Parent = plate
	local stroke = Instance.new("UIStroke")
	stroke.Color = PAPER
	stroke.Transparency = 0.45
	stroke.ApplyStrokeMode = Enum.ApplyStrokeMode.Border
	stroke.Parent = plate

	local key = Instance.new("TextLabel")
	key.Name = "Key"
	key.Size = UDim2.fromOffset(keyWidth, keyWidth)
	key.Position = UDim2.fromOffset(4 + GAP + RING, 4 + GAP + RING)
	key.BackgroundColor3 = PAPER
	key.BorderSizePixel = 0
	key.Font = Enum.Font.RobotoMono
	key.Text = keyText
	key.TextSize = #keyText > 3 and 11 or (touch and 15 or 16)
	key.TextColor3 = INK
	key.Parent = plate
	local keyCorner = Instance.new("UICorner")
	keyCorner.CornerRadius = UDim.new(1, 0)
	keyCorner.Parent = key

	local left = 4 + ringSize + 9
	local actionLabel = Instance.new("TextLabel")
	actionLabel.Name = "Action"
	actionLabel.BackgroundTransparency = 1
	actionLabel.Font = Enum.Font.GothamBold
	actionLabel.Text = action
	actionLabel.TextSize = actionSize
	actionLabel.TextColor3 = PAPER
	actionLabel.TextXAlignment = Enum.TextXAlignment.Left
	actionLabel.TextTruncate = Enum.TextTruncate.AtEnd
	actionLabel.Size = UDim2.new(1, -(left + 8), 0, actionSize + 4)
	actionLabel.Parent = plate
	if object ~= "" then
		local objectLabel = Instance.new("TextLabel")
		objectLabel.Name = "Object"
		objectLabel.BackgroundTransparency = 1
		objectLabel.Font = Enum.Font.RobotoMono
		objectLabel.Text = object
		objectLabel.TextSize = 11
		objectLabel.TextColor3 = MUSTARD
		objectLabel.TextXAlignment = Enum.TextXAlignment.Left
		objectLabel.TextTruncate = Enum.TextTruncate.AtEnd
		objectLabel.Position = UDim2.fromOffset(left, math.floor(height / 2) - 17)
		objectLabel.Size = UDim2.new(1, -(left + 8), 0, 13)
		objectLabel.Parent = plate
		actionLabel.Position = UDim2.fromOffset(left, math.floor(height / 2) - 2)
	else
		actionLabel.Position = UDim2.fromOffset(left, math.floor((height - actionSize - 4) / 2))
	end

	-- the ring: a dim full circle, and over it two half-windows whose stroke a rotating gradient uncovers
	local hold = Instance.new("Frame")
	hold.Name = "Hold"
	hold.Position = UDim2.fromOffset(4, 4)
	hold.Size = UDim2.fromOffset(ringSize, ringSize)
	hold.BackgroundTransparency = 1
	hold.Visible = prompt.HoldDuration > 0
	hold.Parent = plate
	local function circle(parent, x, colour, transparency)
		local disc = Instance.new("Frame")
		disc.BackgroundTransparency = 1
		disc.BorderSizePixel = 0
		disc.Position = UDim2.fromOffset(x, RING)
		disc.Size = UDim2.fromOffset(ringSize - 2 * RING, ringSize - 2 * RING)
		disc.Parent = parent
		local round = Instance.new("UICorner")
		round.CornerRadius = UDim.new(1, 0)
		round.Parent = disc
		local line = Instance.new("UIStroke")
		line.Thickness = RING
		line.Color = colour
		line.Transparency = transparency
		line.ApplyStrokeMode = Enum.ApplyStrokeMode.Border
		line.Parent = disc
		return line
	end
	circle(hold, RING, PAPER, 0.78)
	local function half(name, right)
		local window = Instance.new("Frame")
		window.Name = name
		window.BackgroundTransparency = 1
		window.ClipsDescendants = true
		window.Position = UDim2.fromOffset(right and ringSize / 2 or 0, 0)
		window.Size = UDim2.fromOffset(ringSize / 2, ringSize)
		window.Parent = hold
		local sweep = Instance.new("UIGradient")
		sweep.Transparency = NumberSequence.new({
			NumberSequenceKeypoint.new(0, 0), NumberSequenceKeypoint.new(0.5, 0),
			NumberSequenceKeypoint.new(0.501, 1), NumberSequenceKeypoint.new(1, 1),
		})
		sweep.Rotation = right and 0 or 180        -- nothing of this half shows yet
		sweep.Parent = circle(window, right and RING - ringSize / 2 or RING, MUSTARD, 0)
		return sweep
	end
	local first, second = half("First", true), half("Second", false)
	local function setFill(share)
		first.Rotation = math.clamp(share, 0, 0.5) * 360
		second.Rotation = 180 + math.clamp(share - 0.5, 0, 0.5) * 360
		key.BackgroundColor3 = share > 0 and MUSTARD or PAPER
	end

	local state = { Board = board, Connections = {}, Holding = nil }
	local function connect(signal, callback)
		table.insert(state.Connections, signal:Connect(callback))
	end
	-- A press on the plate is a press of the prompt: touch has no key to hold.
	connect(plate.InputBegan, function(input)
		if input.UserInputType == Enum.UserInputType.Touch
			or input.UserInputType == Enum.UserInputType.MouseButton1 then
			prompt:InputHoldBegin()
		end
	end)
	connect(plate.InputEnded, function(input)
		if input.UserInputType == Enum.UserInputType.Touch
			or input.UserInputType == Enum.UserInputType.MouseButton1 then
			prompt:InputHoldEnd()
		end
	end)
	connect(prompt.PromptButtonHoldBegan, function()
		state.Holding = os.clock()
	end)
	connect(prompt.PromptButtonHoldEnded, function()
		state.Holding = nil
		setFill(0)
	end)
	connect(RunService.RenderStepped, function()
		if state.Holding and prompt.HoldDuration > 0 then
			setFill(math.clamp((os.clock() - state.Holding) / prompt.HoldDuration, 0, 1))
		end
	end)
	board.Parent = playerGui
	return state
end

local function hide(prompt)
	local state = shown[prompt]
	if not state then return end
	shown[prompt] = nil
	for _, connection in ipairs(state.Connections) do connection:Disconnect() end
	state.Board:Destroy()
end

ProximityPromptService.PromptShown:Connect(function(prompt)
	if prompt.Style ~= Enum.ProximityPromptStyle.Custom then return end
	hide(prompt)
	shown[prompt] = build(prompt)
end)
ProximityPromptService.PromptHidden:Connect(hide)
UIDevice.Changed:Connect(function()
	-- the key hint follows the live input: rebuild what is on screen
	for prompt in pairs(shown) do
		hide(prompt)
		if prompt.Parent then shown[prompt] = build(prompt) end
	end
end)

-- Every prompt is drawn this way. The style is a client-side choice, so it is
-- set here rather than on each of the scripts that create prompts.
local function adopt(instance)
	if instance:IsA("ProximityPrompt") then instance.Style = Enum.ProximityPromptStyle.Custom end
end
workspace.DescendantAdded:Connect(adopt)
for _, instance in ipairs(workspace:GetDescendants()) do adopt(instance) end
