-- Found Footage HUD -- B6, owner 2026-10-08; Figma via Framewisp (Codex continuation 2026-10-09).
-- This client only renders the engine's visible prompts and the round recording frame.
local Players = game:GetService("Players")
local RS = game:GetService("ReplicatedStorage")
local RunService = game:GetService("RunService")
local ProximityPromptService = game:GetService("ProximityPromptService")
local UserInputService = game:GetService("UserInputService")
local player = Players.LocalPlayer
local playerGui = player:WaitForChild("PlayerGui")
local UIDevice = require(RS:WaitForChild("UIDevice"))
local Hud = require(RS:WaitForChild("RoundHud"))
local Binder = require(RS:WaitForChild("ZyntraShopUI"):WaitForChild("ShopBinder"))
local P = Binder.Palette

local frameGui = Instance.new("ScreenGui")
frameGui.Name = "FoundFootageHUD"
frameGui.ResetOnSpawn = false
frameGui.ScreenInsets = Enum.ScreenInsets.None
frameGui.DisplayOrder = 12
frameGui.Enabled = false
frameGui.Parent = playerGui
local FRAME_SCALE = 0.6
local function softenFrame(root)
	if not root then return end
	for _, node in ipairs(root:GetDescendants()) do
		if node:IsA("TextLabel") or node:IsA("TextButton") or node:IsA("TextBox") then
			node.TextTransparency = math.max(node.TextTransparency, 0.25)
		elseif node:IsA("UIStroke") then
			node.Transparency = math.max(node.Transparency, 0.45)
		elseif node:IsA("GuiObject") and node.BackgroundTransparency < 1 then
			node.BackgroundTransparency = math.max(node.BackgroundTransparency, node.Name == "Dot" and 0.1 or 0.3)
		end
	end
end
local rec = Hud.Mount("HUD_PC", "RecLine", frameGui, {Scale = FRAME_SCALE})
softenFrame(rec)
local timecode = rec and Binder.text(Binder.at(rec, "Time"))
local watching = rec and Binder.text(Binder.at(rec, "Watching"))
local brackets = {}
for index = 1, 4 do
	local bracket = Hud.Mount("HUD_PC", "Bracket", frameGui, {Name = "Bracket" .. index, Scale = FRAME_SCALE})
	if bracket then
		softenFrame(bracket)
		bracket.AnchorPoint = Vector2.new(0.5, 0.5)
		bracket.Rotation = (index - 1) * 90
		table.insert(brackets, bracket)
	end
end

local function formatTimecode(seconds)
	seconds = math.max(0, math.floor(seconds))
	if seconds >= 3600 then
		return string.format("%d:%02d:%02d", math.floor(seconds / 3600),
			math.floor(seconds / 60) % 60, seconds % 60)
	end
	return string.format("%02d:%02d", math.floor(seconds / 60), seconds % 60)
end

local function placeFrame()
	local layout = UIDevice.Layout()
	local safe = layout.Safe
	if rec then
		rec.Visible = not layout.IsTouch
		rec.Position = UIDevice.LocalPosition(frameGui, safe.Left + 72, safe.Top + 16)
	end
	for index, bracket in ipairs(brackets) do
		bracket.Visible = not layout.IsTouch
		local half = bracket.Size.X.Offset / 2
		local right = index == 2 or index == 3
		local bottom = index == 3 or index == 4
		local x = right and safe.Right - 24 - half or safe.Left + 24 + half
		local y = bottom and safe.Bottom - 24 - half or safe.Top + 16 + half
		bracket.Position = UIDevice.LocalPosition(frameGui, x, y)
	end
end

local function frameWanted()
	return player:GetAttribute("InRound") == true
		and workspace:GetAttribute("RoundActive") == true
		and player:GetAttribute("LobbyLoadingOpen") ~= true
		and player:GetAttribute("LuckyWheelOpen") ~= true
end
local function refreshFrame()
	frameGui.Enabled = frameWanted()
	placeFrame()
end
for _, name in ipairs({"InRound", "LobbyLoadingOpen", "LuckyWheelOpen"}) do
	player:GetAttributeChangedSignal(name):Connect(refreshFrame)
end
workspace:GetAttributeChangedSignal("RoundActive"):Connect(refreshFrame)
UIDevice.Changed:Connect(placeFrame)
refreshFrame()
local previousSecond, previousWatchers = nil, nil
RunService.Heartbeat:Connect(function()
	if not frameGui.Enabled or not rec or not rec.Visible then return end
	local started = workspace:GetAttribute("RoundStartedAt")
	local elapsed = type(started) == "number" and math.max(0, workspace:GetServerTimeNow() - started) or 0
	local second = math.floor(elapsed)
	if timecode and second ~= previousSecond then
		previousSecond = second
		timecode.Text = formatTimecode(second)
	end
	local count = math.max(0, tonumber(player:GetAttribute("SpectatorCount")) or 0)
	if watching and count ~= previousWatchers then
		previousWatchers = count
		watching.Text = count > 0 and ("\u{B7} " .. count .. " WATCHING") or ""
		watching.Visible = count > 0
	end
end)

-- One mounted template per visible prompt; hidden boards are reused on the same input layout.
local shown, pools = {}, {HUD_PC = {}, HUD_Touch = {}}
local function acquire(bundle)
	local pool = pools[bundle]
	local cached = table.remove(pool)
	if cached then return cached end
	local board = Instance.new("BillboardGui")
	board.Name = "InteractionPrompt"
	board.AlwaysOnTop = true
	board.Active = true
	board.ResetOnSpawn = false
	local root = Hud.Mount(bundle, bundle == "HUD_Touch" and "PromptPlateTouch" or "PromptPlate", board)
	if not root then board:Destroy() return nil end
	board.Size = root.Size
	local hit = Binder.button(root, "PromptHit")
	hit.Selectable = false
	return {Board = board, Root = root, Hit = hit, Bundle = bundle,
		Object = Binder.text(Binder.at(root, "ObjectLine")),
		Action = Binder.text(Binder.at(root, "ActionLine")),
		Reason = Binder.text(Binder.at(root, "Reason")),
		Key = Binder.at(root, "KeyChip"),
		HoldBar = Binder.at(root, "HoldBar"),
		Fill = Binder.at(root, "HoldBar/Track/Fill"),
		Ring = Binder.at(root, "RingSlot") and Hud.Ring(Binder.at(root, "RingSlot")) or nil}
end

local function setPromptFill(state, fraction)
	if state.Fill then state.Fill.Size = UDim2.fromScale(fraction, 1) end
	if state.Ring then state.Ring(fraction, P.RailTeal) end
end

local function build(prompt)
	local bundle = Hud.Bundle()
	local state = acquire(bundle)
	if not state then return nil end
	state.Connections, state.Held, state.Input = {}, nil, nil
	local board = state.Board
	board.Adornee = prompt.Parent
	board.SizeOffset = Vector2.new(prompt.UIOffset.X / board.Size.X.Offset, prompt.UIOffset.Y / board.Size.Y.Offset)
	board.MaxDistance = prompt.MaxActivationDistance + 8
	local function connect(signal, callback)
		table.insert(state.Connections, signal:Connect(callback))
	end
	local disabled = false
	local function renderText()
		local reason = prompt:GetAttribute("HudDisabledReason")
		disabled = type(reason) == "string" and reason ~= ""
		if state.Object then
			state.Object.Text = string.upper(prompt.ObjectText)
			state.Object.Visible = not disabled
		end
		if state.Reason then
			state.Reason.Text = disabled and string.upper(reason) or ""
			state.Reason.Visible = disabled
			state.Reason.TextColor3 = P.Amber
		end
		if state.Action then
			state.Action.Text = string.upper(prompt.ActionText ~= "" and prompt.ActionText or "Interact")
			state.Action.TextColor3 = disabled and P.Sage or P.Cream
		end
		if state.Key then
			Hud.Keycap(state.Key, prompt.KeyboardKeyCode, prompt.GamepadKeyCode)
			local key = Binder.text(Binder.at(state.Key, "Key"))
			if key then key.TextColor3 = disabled and P.Sage or P.Cream end
		end
		if state.HoldBar then state.HoldBar.Visible = prompt.HoldDuration > 0 end
		if disabled then state.Held = nil setPromptFill(state, 0) end
	end
	renderText()
	setPromptFill(state, 0)
	connect(prompt:GetPropertyChangedSignal("ActionText"), renderText)
	connect(prompt:GetPropertyChangedSignal("ObjectText"), renderText)
	connect(prompt:GetAttributeChangedSignal("HudDisabledReason"), renderText)
	connect(prompt:GetPropertyChangedSignal("HoldDuration"), renderText)
	connect(state.Hit.InputBegan, function(input)
		if not disabled and (input.UserInputType == Enum.UserInputType.Touch
			or input.UserInputType == Enum.UserInputType.MouseButton1) then
			state.Input = input
			prompt:InputHoldBegin()
		end
	end)
	connect(state.Hit.InputEnded, function(input)
		if state.Input == input then state.Input = nil prompt:InputHoldEnd() end
	end)
	connect(UserInputService.InputEnded, function(input)
		if state.Input == input then state.Input = nil prompt:InputHoldEnd() end
	end)
	connect(prompt.PromptButtonHoldBegan, function()
		if not disabled then state.Held = 0 end
	end)
	connect(prompt.PromptButtonHoldEnded, function()
		state.Held = nil
		setPromptFill(state, 0)
	end)
	connect(RunService.RenderStepped, function(dt)
		if state.Held ~= nil and prompt.HoldDuration > 0 then
			state.Held += dt
			setPromptFill(state, math.clamp(state.Held / prompt.HoldDuration, 0, 1))
		end
	end)
	board.Parent = playerGui
	return state
end

local function hide(prompt)
	local state = shown[prompt]
	if not state then return end
	shown[prompt] = nil
	if state.Input then state.Input = nil prompt:InputHoldEnd() end
	for _, connection in ipairs(state.Connections) do connection:Disconnect() end
	state.Held = nil
	setPromptFill(state, 0)
	state.Board.Parent, state.Board.Adornee = nil, nil
	-- Bound the pool: the template owns no live prompt or connections while parked.
	if #pools[state.Bundle] < 8 then
		table.insert(pools[state.Bundle], state)
	else
		state.Board:Destroy()
	end
end
ProximityPromptService.PromptShown:Connect(function(prompt)
	if prompt.Style ~= Enum.ProximityPromptStyle.Custom then return end
	hide(prompt)
	shown[prompt] = build(prompt)
end)
ProximityPromptService.PromptHidden:Connect(hide)
UIDevice.Changed:Connect(function()
	local pending = {}
	for prompt in pairs(shown) do table.insert(pending, prompt) end
	for _, prompt in ipairs(pending) do
		hide(prompt)
		if prompt.Parent then shown[prompt] = build(prompt) end
	end
end)
local function adopt(instance)
	if instance:IsA("ProximityPrompt") then instance.Style = Enum.ProximityPromptStyle.Custom end
end
workspace.DescendantAdded:Connect(adopt)
for _, instance in ipairs(workspace:GetDescendants()) do adopt(instance) end
