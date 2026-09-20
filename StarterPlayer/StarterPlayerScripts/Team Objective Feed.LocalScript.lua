-- A short team progress feed shared by all levels. No client-supplied progress.
local Players = game:GetService("Players")
local RS = game:GetService("ReplicatedStorage")
local RunService = game:GetService("RunService")
local TextService = game:GetService("TextService")
local player = Players.LocalPlayer
local UIDevice = require(RS:WaitForChild("UIDevice"))
local gui = Instance.new("ScreenGui")
gui.Name = "TeamObjectiveFeed"
gui.ResetOnSpawn = false
gui.ScreenInsets = Enum.ScreenInsets.CoreUISafeInsets
gui.DisplayOrder = 60
gui.Parent = player:WaitForChild("PlayerGui")
local panel = Instance.new("Frame")
panel.Name = "TeamProgress"
panel.BackgroundColor3 = Color3.fromRGB(14, 21, 24)
panel.BackgroundTransparency = .12
panel.BorderSizePixel = 0
panel.Visible = false
panel.Parent = gui
local corner = Instance.new("UICorner")
corner.CornerRadius = UDim.new(0, 7)
corner.Parent = panel
local stroke = Instance.new("UIStroke")
stroke.Color = Color3.fromRGB(68, 221, 196)
stroke.Transparency = .3
stroke.Parent = panel
local label = Instance.new("TextLabel")
label.Name = "Messages"
label.BackgroundTransparency = 1
label.Position = UDim2.fromOffset(10, 6)
label.Size = UDim2.new(1, -20, 1, -12)
label.Font = Enum.Font.GothamMedium
label.TextSize = 13
label.TextColor3 = Color3.fromRGB(231, 238, 233)
label.TextWrapped = true
label.RichText = false
label.TextXAlignment = Enum.TextXAlignment.Left
label.Parent = panel
local entries, lastSerial = {}, 0
local function draw()
	local now = os.clock()
	while entries[1] and entries[1].Until <= now do table.remove(entries, 1) end
	panel.Visible = #entries > 0 and player:GetAttribute("InRound") == true
	if not panel.Visible then return end
	local layout = UIDevice.Layout()
	local safe = layout.Safe
	local width = math.min(380, safe.Right - safe.Left - 24)
	-- Lower centre on desktop; touch stays inside the movement-free modal lane.
	local area = layout.IsTouch and layout.ModalArea or safe
	width = math.min(width, area.Right - area.Left - 16)
	-- A touch screen shows the latest action so bursts cannot cover the compass.
	local lines = {}
	for index = (layout.IsTouch and #entries or 1), #entries do
		lines[#lines + 1] = entries[index].Text
	end
	label.Text = table.concat(lines, "\n")
	local height = TextService:GetTextSize(label.Text, label.TextSize, label.Font, Vector2.new(math.max(100, width - 20), 1000)).Y + 16
	panel.Size = UDim2.fromOffset(math.max(120, width), height)
	panel.Position = UIDevice.LocalPosition(gui, (area.Left + area.Right - width) / 2,
		math.max(area.Top + 8, area.Bottom - height - 18))
end
RS:WaitForChild("Remotes"):WaitForChild("RoundStatus").OnClientEvent:Connect(function(kind, payload)
	if kind ~= "objective" or type(payload) ~= "table" then return end
	if player:GetAttribute("InRound") ~= true or payload.Level ~= workspace:GetAttribute("SelectedLevel") then return end
	if type(payload.Serial) ~= "number" or payload.Serial <= lastSerial then return end
	lastSerial = payload.Serial
	if type(payload.Actor) ~= "string" or type(payload.Detail) ~= "string" then return end
	entries[#entries + 1] = {Text = "@" .. payload.Actor .. "  —  " .. payload.Detail, Until = os.clock() + 5}
	while #entries > 3 do table.remove(entries, 1) end
	draw()
end)
player:GetAttributeChangedSignal("InRound"):Connect(function()
	if player:GetAttribute("InRound") ~= true then table.clear(entries) end
	draw()
end)
UIDevice.Changed:Connect(draw)
local elapsed = 0
RunService.Heartbeat:Connect(function(dt)
	elapsed += dt
	if elapsed >= .2 then elapsed = 0; draw() end
end)
