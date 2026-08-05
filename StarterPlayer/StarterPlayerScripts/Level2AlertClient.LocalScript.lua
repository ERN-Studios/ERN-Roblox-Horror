-- Level 2 completion announcement.
-- Kept separate from the Level 1 HUD so the existing game interface is untouched.

local Players = game:GetService("Players")
local ReplicatedStorage = game:GetService("ReplicatedStorage")
local TweenService = game:GetService("TweenService")

local player = Players.LocalPlayer
local event = ReplicatedStorage:WaitForChild("Level2AlertEvent")

local gui = Instance.new("ScreenGui")
gui.Name = "Level2AlertGui"
gui.IgnoreGuiInset = true
gui.ResetOnSpawn = false
gui.DisplayOrder = 80
gui.Parent = player:WaitForChild("PlayerGui")

local shade = Instance.new("Frame")
shade.Size = UDim2.fromScale(1, 1)
shade.BackgroundColor3 = Color3.new(0, 0, 0)
shade.BackgroundTransparency = 1
shade.Visible = false
shade.Parent = gui

local panel = Instance.new("Frame")
panel.AnchorPoint = Vector2.new(.5, .5)
panel.Position = UDim2.fromScale(.5, .44)
panel.Size = UDim2.fromScale(.68, .25)
panel.BackgroundColor3 = Color3.fromRGB(5, 13, 16)
panel.BackgroundTransparency = .12
panel.BorderSizePixel = 0
panel.Parent = shade

local stroke = Instance.new("UIStroke")
stroke.Color = Color3.fromRGB(54, 210, 221)
stroke.Thickness = 3
stroke.Parent = panel

local first = Instance.new("TextLabel")
first.BackgroundTransparency = 1
first.Position = UDim2.fromScale(.04, .1)
first.Size = UDim2.fromScale(.92, .27)
first.Font = Enum.Font.Code
first.TextColor3 = Color3.fromRGB(126, 224, 235)
first.TextScaled = true
first.Parent = panel

local second = first:Clone()
second.Position = UDim2.fromScale(.04, .48)
second.TextColor3 = Color3.fromRGB(231, 218, 145)
second.Parent = panel

local run = Instance.new("TextLabel")
run.AnchorPoint = Vector2.new(.5, .5)
run.Position = UDim2.fromScale(.5, .58)
run.Size = UDim2.fromScale(.8, .32)
run.BackgroundTransparency = 1
run.Font = Enum.Font.GothamBlack
run.TextColor3 = Color3.fromRGB(255, 38, 38)
run.TextStrokeColor3 = Color3.fromRGB(110, 0, 0)
run.TextStrokeTransparency = .1
run.TextScaled = true
run.Visible = false
run.Parent = shade

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
	local world = workspace:FindFirstChild("PoolroomsLevel2")
	local objectives = world and world:FindFirstChild("Objectives")
	if not objectives then return end
	for _, valve in ipairs(objectives:GetChildren()) do
		if valve:IsA("Model") and valve.Name:match("^PressureValve") then
			local color = valve:GetAttribute("VisionColor") or Color3.fromRGB(80, 220, 180)
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
	if child.Name == "PoolroomsLevel2" and valveVisionEnabled then
		task.wait(.5)
		refreshValveHighlights()
	end
end)

event.OnClientEvent:Connect(function(line1, line2, finalLine)
	if workspace:GetAttribute("SelectedLevel") ~= 2 then return end
	if player:GetAttribute("InRound") ~= true then return end

	first.Text, second.Text, run.Text = line1, line2, finalLine
	run.Visible = false
	panel.Visible = true
	shade.Visible = true
	shade.BackgroundTransparency = 1
	TweenService:Create(shade, TweenInfo.new(.25), {BackgroundTransparency = .46}):Play()

	task.wait(2.5)
	panel.Visible = false
	run.Visible = true

	for _ = 1, 7 do
		run.Visible = not run.Visible
		task.wait(.18)
	end
	run.Visible = true
	task.wait(1.8)

	TweenService:Create(shade, TweenInfo.new(.55), {BackgroundTransparency = 1}):Play()
	task.wait(.6)
	shade.Visible = false
end)
