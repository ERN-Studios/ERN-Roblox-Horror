-- Level 2 Objective UI
-- Persistent pump-status readout for the Sunken Leisure Complex, styled after
-- Level 1's PuzzleUI panels (dark panel, Code font, green-on-black readout).
--
-- Entirely attribute-driven — the server already publishes everything:
--   workspace.Level2Pumps        pumps started so far
--   workspace.Level2PumpGoal     total pumps this round
--   workspace.Level2ExitPowered  pressure doors open
-- Tweak the colors/text below freely; nothing else reads this file.

local Players = game:GetService("Players")

local player = Players.LocalPlayer

local gui = Instance.new("ScreenGui")
gui.Name = "Level2ObjectiveGui"
gui.ResetOnSpawn = false
gui.DisplayOrder = 40
gui.Parent = player:WaitForChild("PlayerGui")

-- Top-right, clear of the RoundUI top bar and the mobile touch cluster.
local panel = Instance.new("Frame")
panel.AnchorPoint = Vector2.new(1, 0)
panel.Position = UDim2.new(1, -14, 0, 64)
panel.Size = UDim2.new(0, 264, 0, 86)
panel.BackgroundColor3 = Color3.fromRGB(6, 13, 15)
panel.BackgroundTransparency = .16
panel.BorderSizePixel = 0
panel.Visible = false
panel.Parent = gui

local corner = Instance.new("UICorner")
corner.CornerRadius = UDim.new(0, 6)
corner.Parent = panel

local stroke = Instance.new("UIStroke")
stroke.Color = Color3.fromRGB(54, 210, 221)
stroke.Thickness = 2
stroke.Transparency = .35
stroke.Parent = panel

local title = Instance.new("TextLabel")
title.BackgroundTransparency = 1
title.Position = UDim2.new(0, 12, 0, 6)
title.Size = UDim2.new(1, -24, 0, 24)
title.Font = Enum.Font.Code
title.TextXAlignment = Enum.TextXAlignment.Left
title.TextScaled = true
title.TextColor3 = Color3.fromRGB(126, 224, 235)
title.Text = "> PRESSURE PUMPS"
title.Parent = panel

local meter = Instance.new("TextLabel")
meter.BackgroundTransparency = 1
meter.Position = UDim2.new(0, 12, 0, 32)
meter.Size = UDim2.new(1, -24, 0, 24)
meter.Font = Enum.Font.Code
meter.TextXAlignment = Enum.TextXAlignment.Left
meter.TextScaled = true
meter.TextColor3 = Color3.fromRGB(218, 237, 223)
meter.Text = "[□□□]  0/3 ONLINE"
meter.Parent = panel

local hint = Instance.new("TextLabel")
hint.BackgroundTransparency = 1
hint.Position = UDim2.new(0, 12, 0, 58)
hint.Size = UDim2.new(1, -24, 0, 20)
hint.Font = Enum.Font.Code
hint.TextXAlignment = Enum.TextXAlignment.Left
hint.TextScaled = true
hint.TextColor3 = Color3.fromRGB(231, 218, 145)
hint.Text = "START EVERY PUMP"
hint.Parent = panel

local function refresh()
	local inLevel = workspace:GetAttribute("SelectedLevel") == 2
		and player:GetAttribute("InRound") == true
	panel.Visible = inLevel
	if not inLevel then return end

	local pumps = tonumber(workspace:GetAttribute("Level2Pumps")) or 0
	local goal = math.max(1, tonumber(workspace:GetAttribute("Level2PumpGoal")) or 3)
	local powered = workspace:GetAttribute("Level2ExitPowered") == true

	local cells = {}
	for index = 1, goal do
		cells[index] = index <= pumps and "■" or "□"
	end
	meter.Text = string.format("[%s]  %d/%d ONLINE", table.concat(cells), pumps, goal)

	if powered then
		title.Text = "> PRESSURE RELEASED"
		title.TextColor3 = Color3.fromRGB(140, 255, 180)
		meter.TextColor3 = Color3.fromRGB(140, 255, 180)
		hint.Text = "RIDE THE FLUME FROM THE TOP DECK"
		hint.TextColor3 = Color3.fromRGB(140, 255, 180)
		stroke.Color = Color3.fromRGB(120, 255, 170)
	else
		title.Text = "> PRESSURE PUMPS"
		title.TextColor3 = Color3.fromRGB(126, 224, 235)
		meter.TextColor3 = Color3.fromRGB(218, 237, 223)
		hint.Text = pumps > 0 and "FIND THE REMAINING PUMPS" or "START EVERY PUMP"
		hint.TextColor3 = Color3.fromRGB(231, 218, 145)
		stroke.Color = Color3.fromRGB(54, 210, 221)
	end
end

for _, attribute in ipairs({"SelectedLevel", "Level2Pumps", "Level2PumpGoal", "Level2ExitPowered"}) do
	workspace:GetAttributeChangedSignal(attribute):Connect(refresh)
end
player:GetAttributeChangedSignal("InRound"):Connect(refresh)
refresh()
