-- Level 2 completion announcement.
-- Kept separate from the Level 1 HUD so the existing game interface is untouched.

local Players = game:GetService("Players")
local ReplicatedStorage = game:GetService("ReplicatedStorage")
local UIDevice = require(ReplicatedStorage:WaitForChild("UIDevice"))
local TweenService = game:GetService("TweenService")

local player = Players.LocalPlayer
local event = ReplicatedStorage:WaitForChild("Level2AlertEvent")

local gui = Instance.new("ScreenGui")
gui.Name = "Level2AlertGui"
gui.IgnoreGuiInset = false
gui.ResetOnSpawn = false
gui.DisplayOrder = 80
gui.Parent = player:WaitForChild("PlayerGui")

local function syncDispatchSuppression()
	gui.Enabled = player:GetAttribute("ZyntraDispatchClientActive") ~= true
end
player:GetAttributeChangedSignal("ZyntraDispatchClientActive"):Connect(syncDispatchSuppression)
syncDispatchSuppression()

local shade = Instance.new("Frame")
shade.Size = UDim2.fromScale(1, 1)
shade.BackgroundColor3 = Color3.new(0, 0, 0)
shade.BackgroundTransparency = 1
shade.Visible = false
shade.Parent = gui

local panel = Instance.new("Frame")
-- Compact, inset-aware toast.  Wide screens keep it left of the persistent
-- objective; medium screens use the remaining left column; narrow portrait
-- screens stack it below the objective instead of covering either HUD.
panel.BackgroundColor3 = Color3.fromRGB(5, 13, 16)
panel.BackgroundTransparency = .12
panel.BorderSizePixel = 0
panel.Parent = shade
local panelSize = Instance.new("UISizeConstraint")
-- 104 is taller than the band a landscape phone leaves clear of the movement
-- controls, and a UISizeConstraint MinSize silently overrides the clamp above.
panelSize.MinSize = Vector2.new(180, 56)
panelSize.MaxSize = Vector2.new(560, 140)
panelSize.Parent = panel

local cameraViewportConnection
local function applySafePanelLayout()
	local layout = UIDevice.Layout()
	local viewport = layout.Viewport
	if viewport.X < 600 then
		panel.AnchorPoint = Vector2.new(.5, 0)
		panel.Position = UDim2.new(.5, 0, 0, 158)
		panel.Size = UDim2.new(1, -24, 0, 112)
	elseif viewport.X < 860 then
		panel.AnchorPoint = Vector2.new(0, 0)
		panel.Position = UDim2.fromOffset(12, 70)
		panel.Size = UDim2.fromOffset(math.max(180, viewport.X - 272), 118)
	else
		panel.AnchorPoint = Vector2.new(.5, .5)
		panel.Position = UDim2.fromScale(.43, .24)
		panel.Size = UDim2.new(.56, 0, 0, 132)
	end

	-- On a touch device the panel has to fit the band that is clear of the
	-- movement controls. A phone in landscape leaves only about 65 usable
	-- vertical pixels there, and the authored 118px panel ran straight into the
	-- thumbstick's activation region, so the height is clamped to the band and
	-- the copy scales with it.
	if layout.IsTouch then
		-- Fit the strip that is clear of BOTH movement zones: above the
		-- thumbstick's activation region, and left of the control column. The
		-- authored 118px panel ran into the thumbstick, and a full-width one ran
		-- under the GLOW button.
		local band = layout.TopBand
		panel.AnchorPoint = Vector2.new(0, 0)
		panel.Position = UDim2.fromOffset(band.Left, UIDevice.TopOffsetFor(gui, band.Top))
		panel.Size = UDim2.fromOffset(
			math.max(180, band.Width),
			math.max(56, math.min(panel.Size.Y.Offset, band.Height)))
	end
end

local function bindCurrentCamera()
	if cameraViewportConnection then
		cameraViewportConnection:Disconnect()
		cameraViewportConnection = nil
	end
	local camera = workspace.CurrentCamera
	if camera then
		cameraViewportConnection = camera:GetPropertyChangedSignal("ViewportSize"):Connect(applySafePanelLayout)
	end
	applySafePanelLayout()
end
workspace:GetPropertyChangedSignal("CurrentCamera"):Connect(bindCurrentCamera)
UIDevice.Changed:Connect(applySafePanelLayout)
bindCurrentCamera()

local stroke = Instance.new("UIStroke")
stroke.Color = Color3.fromRGB(54, 210, 221)
stroke.Thickness = 3
stroke.Parent = panel

local first = Instance.new("TextLabel")
first.BackgroundTransparency = 1
first.Position = UDim2.fromScale(.04, .07)
first.Size = UDim2.fromScale(.92, .24)
first.Font = Enum.Font.Code
first.TextColor3 = Color3.fromRGB(126, 224, 235)
first.TextScaled = true
first.TextWrapped = true
first.Parent = panel
local firstSize = Instance.new("UITextSizeConstraint")
firstSize.MinTextSize = 14
firstSize.MaxTextSize = 27
firstSize.Parent = first

local second = first:Clone()
local inheritedSecondSize = second:FindFirstChildOfClass("UITextSizeConstraint")
if inheritedSecondSize then inheritedSecondSize:Destroy() end
second.Position = UDim2.fromScale(.04, .36)
second.Size = UDim2.fromScale(.92, .22)
second.TextColor3 = Color3.fromRGB(231, 218, 145)
second.Parent = panel
local secondSize = Instance.new("UITextSizeConstraint")
secondSize.MinTextSize = 12
secondSize.MaxTextSize = 23
secondSize.Parent = second

local run = Instance.new("TextLabel")
run.Position = UDim2.fromScale(.04, .65)
run.Size = UDim2.fromScale(.92, .24)
run.BackgroundTransparency = 1
run.Font = Enum.Font.Code
run.TextColor3 = Color3.fromRGB(231, 218, 145)
run.TextStrokeColor3 = Color3.fromRGB(35, 28, 12)
run.TextStrokeTransparency = .72
run.TextScaled = true
run.TextWrapped = true
run.Visible = false
run.Parent = panel
local runSize = Instance.new("UITextSizeConstraint")
runSize.MinTextSize = 11
runSize.MaxTextSize = 19
runSize.Parent = run

local valveVisionEnabled = player:GetAttribute("DevEspEnabled") == true
local valveHighlights = {}

local function clearValveHighlights()
	for _, highlight in ipairs(valveHighlights) do
		highlight:Destroy()
	end
	table.clear(valveHighlights)
end

local function refreshValveHighlights()
	clearValveHighlights()
	if not valveVisionEnabled or workspace:GetAttribute("SelectedLevel") ~= 2 then return end
	local world = workspace:FindFirstChild("Level 2 Generated World")
	local objectives = world and world:FindFirstChild("Level 2 Objectives")
	if not objectives then return end
	for _, valve in ipairs(objectives:GetChildren()) do
		if valve:IsA("Model") and valve.Name:match("^Level 2 Pump Station") then
			-- Each station publishes its lever handle colour; use it so the dev
			-- ESP distinguishes the three pumps instead of showing generic green.
			local color = valve:GetAttribute("Level2_LeverHandleColorValue")
				or Color3.fromRGB(80, 220, 180)
			local highlight = Instance.new("Highlight")
			highlight.Name = "ValveVisionHighlight"
			highlight.Adornee = valve
			highlight.DepthMode = Enum.HighlightDepthMode.AlwaysOnTop
			highlight.FillColor = color
			highlight.OutlineColor = color:Lerp(Color3.new(1,1,1), .25)
			highlight.FillTransparency = .58
			highlight.OutlineTransparency = .05
			highlight.Parent = workspace.CurrentCamera
			table.insert(valveHighlights, highlight)
		end
	end
end

-- DevCheats owns B/V consistently in both levels. Valve vision follows B via
-- this local attribute, leaving V exclusively for noclip.
player:GetAttributeChangedSignal("DevEspEnabled"):Connect(function()
	valveVisionEnabled = player:GetAttribute("DevEspEnabled") == true
	refreshValveHighlights()
end)

workspace:GetAttributeChangedSignal("SelectedLevel"):Connect(function()
	refreshValveHighlights()
end)

workspace.ChildAdded:Connect(function(child)
	if child.Name == "Level 2 Generated World" and valveVisionEnabled then
		task.wait(.5)
		refreshValveHighlights()
	end
end)

local announcementSerial = 0
local activeTweens = {}

local function cancelTweens()
	for _, tween in ipairs(activeTweens) do tween:Cancel() end
	table.clear(activeTweens)
end

local function tween(instance, info, properties)
	local created = TweenService:Create(instance, info, properties)
	table.insert(activeTweens, created)
	created:Play()
	return created
end

local function hideAlert()
	announcementSerial += 1
	cancelTweens()
	shade.Visible = false
	panel.Visible = true
	run.Visible = false
end

event.OnClientEvent:Connect(function(line1, line2, finalLine, holdSeconds)
	if workspace:GetAttribute("SelectedLevel") ~= 2 then return end
	if player:GetAttribute("InRound") ~= true then return end

	announcementSerial += 1
	local serial = announcementSerial
	cancelTweens()

	first.Text = tostring(line1 or "")
	second.Text = tostring(line2 or "")
	run.Text = tostring(finalLine or "")
	run.Visible = run.Text ~= ""
	first.TextTransparency = 0
	second.TextTransparency = 0
	run.TextTransparency = 0
	run.TextStrokeTransparency = .72
	panel.BackgroundTransparency = .12
	stroke.Transparency = .15
	panel.Visible = true
	shade.Visible = true
	-- Status messages must never black out the play space or mobile controls.
	shade.BackgroundTransparency = 1

	local hold = math.clamp(typeof(holdSeconds) == "number" and holdSeconds or 1.7, .7, 5)
	task.wait(hold)
	if serial ~= announcementSerial then return end

	tween(panel, TweenInfo.new(.28), {BackgroundTransparency = 1})
	tween(stroke, TweenInfo.new(.28), {Transparency = 1})
	tween(first, TweenInfo.new(.24), {TextTransparency = 1})
	tween(second, TweenInfo.new(.24), {TextTransparency = 1})
	if run.Visible then
		tween(run, TweenInfo.new(.24), {TextTransparency = 1, TextStrokeTransparency = 1})
	end
	task.wait(.32)
	if serial ~= announcementSerial then return end
	shade.Visible = false
end)

workspace:GetAttributeChangedSignal("SelectedLevel"):Connect(function()
	if workspace:GetAttribute("SelectedLevel") ~= 2 then hideAlert() end
end)
player:GetAttributeChangedSignal("InRound"):Connect(function()
	if player:GetAttribute("InRound") ~= true then hideAlert() end
end)
