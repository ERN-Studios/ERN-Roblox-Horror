-- PuzzleUI  (v2 — status counters only, no how-to guide)
-- PASTE INTO: StarterPlayer → StarterPlayerScripts → Insert Object → LocalScript → rename to "PuzzleUI"
--
-- Shows only STATUS — fuses you're carrying and how many fuse boxes are on.
-- It does NOT explain the objective; players are told that beforehand and have
-- to figure the rest out themselves.

local Players = game:GetService("Players")
local RS = game:GetService("ReplicatedStorage")

local remote = RS:WaitForChild("Remotes"):WaitForChild("PuzzleStatus")
local player = Players.LocalPlayer

local gui = Instance.new("ScreenGui")
gui.Name = "PuzzleGui"
gui.ResetOnSpawn = false
gui.Parent = player:WaitForChild("PlayerGui")

local function makeLabel(yOffset)
	local l = Instance.new("TextLabel")
	l.AnchorPoint = Vector2.new(1, 1)
	l.Position = UDim2.new(1, -16, 1, yOffset)
	l.Size = UDim2.new(0, 200, 0, 30)
	l.BackgroundColor3 = Color3.new(0, 0, 0)
	l.BackgroundTransparency = 0.82 -- much more see-through
	l.BorderSizePixel = 0
	l.Font = Enum.Font.Gotham -- loads fast (no first-use hitch) + clean B/W look
	l.TextScaled = true
	l.TextColor3 = Color3.fromRGB(245, 245, 245) -- white, black-and-white theme
	l.Visible = false
	l.Parent = gui
	local c = Instance.new("UICorner"); c.CornerRadius = UDim.new(0, 6); c.Parent = l
	return l
end

local boxesLabel = makeLabel(-52)
local carryLabel = makeLabel(-16)

local function show(on)
	boxesLabel.Visible = on
	carryLabel.Visible = on
end

remote.OnClientEvent:Connect(function(ev, a, b)
	if ev == "begin" then
		carryLabel.Text = "Fuses: 0"
		boxesLabel.Text = ("Fuse boxes: 0/%d"):format(b)
		show(true)
	elseif ev == "carry" then
		carryLabel.Text = "Fuses: " .. a
	elseif ev == "boxes" then
		boxesLabel.Text = ("Fuse boxes: %d/%d"):format(a, b)
	end
end)

-- hide the counters between rounds
workspace:GetAttributeChangedSignal("RoundActive"):Connect(function()
	if not workspace:GetAttribute("RoundActive") then show(false) end
end)
