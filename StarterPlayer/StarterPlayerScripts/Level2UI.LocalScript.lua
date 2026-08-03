local Players = game:GetService("Players")
local player = Players.LocalPlayer

local gui = Instance.new("ScreenGui")
gui.Name = "Level2PoolroomsUI"
gui.ResetOnSpawn = false
gui.IgnoreGuiInset = true
gui.DisplayOrder = 18
gui.Parent = player:WaitForChild("PlayerGui")

local panel = Instance.new("Frame")
panel.AnchorPoint = Vector2.new(1, 1)
panel.Position = UDim2.new(1, -18, 1, -18)
panel.Size = UDim2.new(0, 310, 0, 92)
panel.BackgroundColor3 = Color3.fromRGB(5, 17, 18)
panel.BackgroundTransparency = 0.2
panel.BorderSizePixel = 0
panel.Visible = false
panel.Parent = gui

local corner = Instance.new("UICorner")
corner.CornerRadius = UDim.new(0, 8)
corner.Parent = panel

local stroke = Instance.new("UIStroke")
stroke.Color = Color3.fromRGB(88, 231, 214)
stroke.Transparency = 0.25
stroke.Thickness = 1.4
stroke.Parent = panel

local title = Instance.new("TextLabel")
title.BackgroundTransparency = 1
title.Position = UDim2.new(0, 14, 0, 8)
title.Size = UDim2.new(1, -28, 0, 28)
title.Font = Enum.Font.Code
title.Text = "> FILTRATION CONTROL"
title.TextColor3 = Color3.fromRGB(112, 255, 220)
title.TextSize = 18
title.TextXAlignment = Enum.TextXAlignment.Left
title.Parent = panel

local status = Instance.new("TextLabel")
status.BackgroundTransparency = 1
status.Position = UDim2.new(0, 14, 0, 38)
status.Size = UDim2.new(1, -28, 0, 42)
status.Font = Enum.Font.Code
status.TextColor3 = Color3.fromRGB(218, 237, 229)
status.TextSize = 16
status.TextWrapped = true
status.TextXAlignment = Enum.TextXAlignment.Left
status.TextYAlignment = Enum.TextYAlignment.Top
status.Parent = panel

local function update()
	local levelTwo = workspace:GetAttribute("SelectedLevel") == 2
	local inRound = player:GetAttribute("InRound") == true
	panel.Visible = levelTwo and inRound
	if not panel.Visible then return end
	local active = tonumber(workspace:GetAttribute("Level2Valves")) or 0
	local goal = tonumber(workspace:GetAttribute("Level2ValveGoal")) or 3
	if workspace:GetAttribute("Level2ExitPowered") then
		title.Text = "> EXIT SLIDE POWERED"
		title.TextColor3 = Color3.fromRGB(84, 255, 139)
		status.Text = "[###] Follow the green glow\nEnter the glossy green pool slide"
	else
		title.Text = "> FILTRATION CONTROL"
		title.TextColor3 = Color3.fromRGB(112, 255, 220)
		status.Text = string.format("[%s%s] VALVES %d/%d\nRestore all pressure lines", string.rep("#", active), string.rep("-", math.max(goal - active, 0)), active, goal)
	end
end

for _, attribute in ipairs({"SelectedLevel", "Level2Valves", "Level2ValveGoal", "Level2ExitPowered"}) do
	workspace:GetAttributeChangedSignal(attribute):Connect(update)
end
player:GetAttributeChangedSignal("InRound"):Connect(update)
update()
