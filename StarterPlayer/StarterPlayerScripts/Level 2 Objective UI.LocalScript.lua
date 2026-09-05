-- Level 2 Objective UI
-- Persistent pump-status readout for the Sunken Leisure Complex, styled after
-- Level 1's PuzzleUI panels (dark panel, Code font, green-on-black readout).
--
-- Entirely attribute-driven — the server already publishes everything:
--   workspace.Level2Pumps         pumps started so far
--   workspace.Level2PumpGoal      total pumps this round
--   workspace.Level2ExitPowered   pressure doors open
--   workspace.Level2FoamLethal    the pump that unlocks Pool Foam's attacks has run
--   workspace.Level2_ExitPosition the flume mouth, published when the doors open
-- Tweak the colors/text below freely; nothing else reads this file.

local Players = game:GetService("Players")
local RunService = game:GetService("RunService")
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

local POWERED_HINT = "TAKE TOP-DECK FLUME"

-- LEVEL2_EXIT_BEARING_20260905
-- Level 1 has the detector compass and Level 3 the reader needle. Once the
-- pressure doors open, all Level 2 gave the party for the largest generated
-- space in the game was those three words — during the stretch where Pool Foam
-- is at its Finale speed and separated players have no way to regroup on the
-- exit. Camera-relative, eight-point, in words rather than arrow glyphs so it
-- renders in Code on every device. Falls back to the static hint whenever the
-- server has published no position (older build, or a manifest with no mouth).
local BEARINGS = {"AHEAD", "AHEAD-R", "RIGHT", "BEHIND-R", "BEHIND", "BEHIND-L", "LEFT", "AHEAD-L"}

local function exitBearingText()
	local exitPosition = workspace:GetAttribute("Level2_ExitPosition")
	if typeof(exitPosition) ~= "Vector3" then return nil end
	local character = player.Character
	local root = character and character:FindFirstChild("HumanoidRootPart")
	local camera = workspace.CurrentCamera
	if not root or not camera then return nil end
	local delta = exitPosition - root.Position
	local flat = Vector3.new(delta.X, 0, delta.Z)
	local look = camera.CFrame.LookVector
	local forward = Vector3.new(look.X, 0, look.Z)
	-- Standing under the flume mouth leaves a near-zero flat vector whose bearing
	-- spins with every step. Inside this radius the exit is not something you
	-- navigate to any more, it is something you climb, so hand the line back to
	-- the static instruction.
	if flat.Magnitude < 12 or forward.Magnitude < .01 then return nil end
	flat, forward = flat.Unit, forward.Unit
	-- Positive angle means the exit is to the RIGHT of where the camera looks,
	-- matching PuzzleUI's compass-arrow convention.
	local angle = math.deg(math.atan2(forward.X * flat.Z - forward.Z * flat.X, forward:Dot(flat)))
	local index = math.floor((angle % 360) / 45 + .5) % 8 + 1
	-- The bearing is horizontal; the exit is on the top deck. Keep the one
	-- instruction that matters in the line rather than replacing it — the
	-- completion alert says "CLIMB TO THE TOP DECK" and the panel must not
	-- contradict it.
	return string.format("FLUME %dM %s%s",
		math.floor(delta.Magnitude + .5),
		BEARINGS[index],
		delta.Y > 15 and " - CLIMB" or "")
end

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
		hint.Text = exitBearingText() or POWERED_HINT
		hint.TextColor3 = Color3.fromRGB(140, 255, 180)
		stroke.Color = Color3.fromRGB(120, 255, 170)
	elseif workspace:GetAttribute("Level2FoamLethal") == true then
		-- LEVEL2_LETHAL_PUMP_20260905. The pump that unlocks Pool Foam's attacks
		-- used to read exactly like the one before it. The panel now carries the
		-- danger for the rest of the round; the meter above still says how many
		-- stations are left, so no objective information is lost.
		title.Text = "> PUMP NETWORK"
		title.TextColor3 = Color3.fromRGB(126, 224, 235)
		meter.TextColor3 = Color3.fromRGB(218, 237, 223)
		hint.Text = "WATER NO LONGER SAFE"
		hint.TextColor3 = Color3.fromRGB(255, 138, 120)
		stroke.Color = Color3.fromRGB(255, 116, 96)
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

-- The panel is otherwise entirely signal-driven; the bearing is the one thing
-- that changes while nothing else does, so it gets its own throttled tick at the
-- same 0.22 s cadence Level 1's detector uses. It does nothing at all until the
-- doors are open and the panel is on screen.
local bearingClock = 0
RunService.Heartbeat:Connect(function(deltaTime)
	if not panel.Visible or workspace:GetAttribute("Level2ExitPowered") ~= true then return end
	bearingClock += deltaTime
	if bearingClock < .22 then return end
	bearingClock = 0
	hint.Text = exitBearingText() or POWERED_HINT
end)

for _, attribute in ipairs({"SelectedLevel", "Level2Pumps", "Level2PumpGoal", "Level2ExitPowered",
	"Level2FoamLethal"}) do
	workspace:GetAttributeChangedSignal(attribute):Connect(refresh)
end
player:GetAttributeChangedSignal("InRound"):Connect(refresh)
player:GetAttributeChangedSignal("Level2AlertOwnsBand"):Connect(refresh)
-- A viewport or form-factor change can move the alert from "fits beside" to
-- "owns the band" and back, so the panel's visibility follows the layout too.
UIDevice.Changed:Connect(refresh)
refresh()
