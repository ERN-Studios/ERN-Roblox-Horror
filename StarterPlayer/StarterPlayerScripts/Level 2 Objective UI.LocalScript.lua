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
local UserInputService = game:GetService("UserInputService")
local UIDevice = require(game:GetService("ReplicatedStorage"):WaitForChild("UIDevice"))

local player = Players.LocalPlayer

local gui = Instance.new("ScreenGui")
gui.Name = "Level2ObjectiveGui"
gui.ResetOnSpawn = false
gui.DisplayOrder = 40
gui.Parent = player:WaitForChild("PlayerGui")

local function syncDispatchSuppression()
	gui.Enabled = player:GetAttribute("ZyntraDispatchClientActive") ~= true
		and not UIDevice.ScreenOwningModalOpen()
end
player:GetAttributeChangedSignal("ZyntraDispatchClientActive"):Connect(syncDispatchSuppression)
UIDevice.OnScreenOwningModalChanged(syncDispatchSuppression)
syncDispatchSuppression()

-- Desktop uses the lower-right corner. Touch-only devices keep the original
-- top-right placement so the panel cannot cover movement/action controls.
local panel = Instance.new("Frame")
panel.Name = "Level2ObjectivePanel"
panel.Size = UDim2.new(0, 236, 0, 78)
panel.BackgroundColor3 = Color3.fromRGB(6, 13, 15)
panel.BackgroundTransparency = .16
panel.BorderSizePixel = 0
panel.Visible = false
panel.Parent = gui

-- This file already had the correct three-way form-factor test; it just never
-- re-ran it. Placement now comes from the shared helper and refreshes whenever
-- the viewport, inset or form factor changes.
-- Declared BEFORE the placement function that writes it: a UISizeConstraint
-- states the same numbers the placement chose, so it cannot clamp the panel to
-- a size nothing was measured against.
local panelSize = Instance.new("UISizeConstraint")
panelSize.MinSize = Vector2.new(150, 72)
panelSize.MaxSize = Vector2.new(236, 86)
panelSize.Parent = panel

-- C_OBJECTIVES_UPPER_RIGHT_20260830 -- WHAT SHIPPED BROKEN.
-- On a landscape handheld this panel was CENTRED IN THE CORRIDOR between the
-- two movement zones and anchored 40px off the bottom -- i.e. bottom-centre,
-- directly between the player's thumbs -- and in portrait it sat at the bottom
-- of the top band. Neither is the upper right, and neither agreed with Level 1
-- or Level 3, which had their own two different answers.
--
-- All three now share UIDevice.TopRightPanel: top of the TRUE safe area (past
-- the topbar AND past a landscape sensor housing), right-aligned to the
-- highest movement-safe right edge, and given back the height that actually
-- fits. Desktop keeps its authored lower-right composition unchanged.
local function updatePanelPlacement()
	local layout = UIDevice.Layout()
	if layout.IsTouch then
		local column = UIDevice.ObjectiveColumn(2)
		panel.AnchorPoint = Vector2.new(0, 0)
		-- The constraint has to state the same numbers the placement used, or it
		-- silently clamps the panel to a size nothing was measured against.
		panelSize.MinSize = Vector2.new(column.Width, column.Height)
		panelSize.MaxSize = Vector2.new(column.Width, column.Height)
		panel.Size = UDim2.fromOffset(column.Width, column.Height)
		-- Absolute -> this gui's local offsets, in BOTH axes.
		panel.Position = UIDevice.LocalPosition(gui, column.Left, column.Top)
	else
		panel.AnchorPoint = Vector2.new(1, 1)
		panelSize.MinSize = Vector2.new(150, 72)
		panelSize.MaxSize = Vector2.new(236, 86)
		panel.Size = UDim2.new(0, 236, 0, 78)
		panel.Position = UDim2.new(1, -18, 1, -18)
	end
end
updatePanelPlacement()
UIDevice.Changed:Connect(updatePanelPlacement)

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
title.Position = UDim2.new(0, 10, 0, 4)
title.Size = UDim2.new(1, -20, 0, 20)
title.Font = Enum.Font.Code
title.TextXAlignment = Enum.TextXAlignment.Left
title.TextScaled = true
title.TextWrapped = true
title.TextColor3 = Color3.fromRGB(126, 224, 235)
title.Text = "> PUMP NETWORK"
title.Parent = panel
local titleSize = Instance.new("UITextSizeConstraint")
titleSize.MinTextSize = 11
titleSize.MaxTextSize = 18
titleSize.Parent = title

local meter = Instance.new("TextLabel")
meter.BackgroundTransparency = 1
meter.Position = UDim2.new(0, 10, 0, 27)
meter.Size = UDim2.new(1, -20, 0, 20)
meter.Font = Enum.Font.Code
meter.TextXAlignment = Enum.TextXAlignment.Left
meter.TextScaled = true
meter.TextWrapped = true
meter.TextColor3 = Color3.fromRGB(218, 237, 223)
meter.Text = "[□□□]  0/3"
meter.Parent = panel
local meterSize = Instance.new("UITextSizeConstraint")
meterSize.MinTextSize = 11
meterSize.MaxTextSize = 18
meterSize.Parent = meter

local hint = Instance.new("TextLabel")
hint.BackgroundTransparency = 1
hint.Position = UDim2.new(0, 10, 0, 51)
hint.Size = UDim2.new(1, -20, 0, 18)
hint.Font = Enum.Font.Code
hint.TextXAlignment = Enum.TextXAlignment.Left
hint.TextScaled = true
hint.TextWrapped = true
hint.TextColor3 = Color3.fromRGB(231, 218, 145)
hint.Text = "ACTIVATE 3 STATIONS"
hint.Parent = panel
local hintSize = Instance.new("UITextSizeConstraint")
hintSize.MinTextSize = 9
hintSize.MaxTextSize = 14
hintSize.Parent = hint

local function refresh()
	local inLevel = workspace:GetAttribute("SelectedLevel") == 2
		and player:GetAttribute("InRound") == true
	-- The completion announcement is the one panel that shares this band, and
	-- on a phone whose band is too narrow to hold both it says so rather than
	-- drawing across the objective column. It is transient (five seconds at
	-- most) and restates this very state, so standing down is the right yield.
	-- Where there IS room -- tablets, roomy landscape phones -- the attribute is
	-- never set and both stay on screen, reflowed side by side.
	local alertOwnsBand = player:GetAttribute("Level2AlertOwnsBand") == true
	panel.Visible = inLevel and not alertOwnsBand
	if not inLevel then return end

	local goal = math.clamp(math.floor(tonumber(workspace:GetAttribute("Level2PumpGoal")) or 3), 1, 12)
	local pumps = math.clamp(math.floor(tonumber(workspace:GetAttribute("Level2Pumps")) or 0), 0, goal)
	local powered = workspace:GetAttribute("Level2ExitPowered") == true

	local cells = {}
	for index = 1, goal do
		cells[index] = index <= pumps and "■" or "□"
	end
	meter.Text = string.format("[%s]  %d/%d", table.concat(cells), pumps, goal)

	if powered then
		title.Text = "> EXIT ROUTE"
		title.TextColor3 = Color3.fromRGB(140, 255, 180)
		meter.Text = "PRESSURE RELEASED"
		meter.TextColor3 = Color3.fromRGB(140, 255, 180)
		hint.Text = "TAKE TOP-DECK FLUME"
		hint.TextColor3 = Color3.fromRGB(140, 255, 180)
		stroke.Color = Color3.fromRGB(120, 255, 170)
	else
		title.Text = "> PUMP NETWORK"
		title.TextColor3 = Color3.fromRGB(126, 224, 235)
		meter.TextColor3 = Color3.fromRGB(218, 237, 223)
		local remaining = goal - pumps
		if pumps == 0 then
			hint.Text = string.format("ACTIVATE %d STATIONS", goal)
		elseif remaining == 1 then
			hint.Text = "1 STATION REMAINS"
		else
			hint.Text = string.format("%d STATIONS REMAIN", remaining)
		end
		hint.TextColor3 = Color3.fromRGB(231, 218, 145)
		stroke.Color = Color3.fromRGB(54, 210, 221)
	end
end

for _, attribute in ipairs({"SelectedLevel", "Level2Pumps", "Level2PumpGoal", "Level2ExitPowered"}) do
	workspace:GetAttributeChangedSignal(attribute):Connect(refresh)
end
player:GetAttributeChangedSignal("InRound"):Connect(refresh)
player:GetAttributeChangedSignal("Level2AlertOwnsBand"):Connect(refresh)
-- A viewport or form-factor change can move the alert from "fits beside" to
-- "owns the band" and back, so the panel's visibility follows the layout too.
UIDevice.Changed:Connect(refresh)
refresh()
