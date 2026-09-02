-- Master Tuning -- the in-game half of the tuning panel.
--
-- Opens with K, for whitelisted developers only. The Studio plugin covers level
-- design in Edit; this covers the things you can only judge while playing --
-- how fast the entity actually feels, whether a hall reads as too big from
-- inside it.
--
-- The client is NEVER the authority. It reads the registry to know what exists
-- and reads the replicated MasterTuning attributes to know what is in force, but
-- every write goes over the DevTuning remote so the server can check DevAccess
-- and re-clamp against the registry's own range. Master.SetOverride refuses to
-- run on a live client by design; this script does not try.

local Players = game:GetService("Players")
local ReplicatedStorage = game:GetService("ReplicatedStorage")
local ContextActionService = game:GetService("ContextActionService")

local DevAccess = require(ReplicatedStorage:WaitForChild("DevAccess"))
local player = Players.LocalPlayer

-- Same boundary as DevCheats: immutable UserIds, never a username. A
-- non-developer never builds any of this.
if not DevAccess.IsAllowed(player) then return end

local Master = require(ReplicatedStorage:WaitForChild("MasterConfiguration"))
local UIDevice = require(ReplicatedStorage:WaitForChild("UIDevice"))
local remotes = ReplicatedStorage:WaitForChild("Remotes")
local devTuning = remotes:WaitForChild("DevTuning")

local TOUCH_TARGET = 44 -- the minimum this project holds every touch control to
local ROW_HEIGHT = 30

-- ------------------------------------------------------------------- the shell

local gui = Instance.new("ScreenGui")
gui.Name = "MasterTuningPanel"
gui.ResetOnSpawn = false
gui.IgnoreGuiInset = true
gui.DisplayOrder = 40
gui.Enabled = false
gui.Parent = player:WaitForChild("PlayerGui")

local panel = Instance.new("Frame")
panel.BackgroundColor3 = Color3.fromRGB(16, 18, 22)
panel.BackgroundTransparency = .06
panel.BorderSizePixel = 0
panel.Parent = gui

local corner = Instance.new("UICorner")
corner.CornerRadius = UDim.new(0, 8)
corner.Parent = panel

local title = Instance.new("TextLabel")
title.Size = UDim2.new(1, -16, 0, 26)
title.Position = UDim2.new(0, 8, 0, 6)
title.BackgroundTransparency = 1
title.Font = Enum.Font.GothamBold
title.TextSize = 15
title.TextXAlignment = Enum.TextXAlignment.Left
title.TextColor3 = Color3.fromRGB(235, 240, 245)
title.Text = "MASTER TUNING"
title.Parent = panel

local status = Instance.new("TextLabel")
status.Size = UDim2.new(1, -16, 0, 30)
status.Position = UDim2.new(0, 8, 0, 30)
status.BackgroundTransparency = 1
status.Font = Enum.Font.Gotham
status.TextSize = 11
status.TextWrapped = true
status.TextXAlignment = Enum.TextXAlignment.Left
status.TextYAlignment = Enum.TextYAlignment.Top
status.TextColor3 = Color3.fromRGB(150, 160, 172)
status.Text = ""
status.Parent = panel

local scroll = Instance.new("ScrollingFrame")
scroll.Position = UDim2.new(0, 8, 0, 62)
scroll.Size = UDim2.new(1, -16, 1, -70)
scroll.BackgroundTransparency = 1
scroll.BorderSizePixel = 0
scroll.ScrollBarThickness = 6
scroll.CanvasSize = UDim2.new()
scroll.AutomaticCanvasSize = Enum.AutomaticSize.Y
scroll.Parent = panel

local list = Instance.new("UIListLayout")
list.SortOrder = Enum.SortOrder.LayoutOrder
list.Padding = UDim.new(0, 3)
list.Parent = scroll

-- --------------------------------------------------------------- placement
--
-- ModalViewport, not the whole screen: it is the rectangle a screen-owning
-- modal may occupy, already clear of the notch, the topbar band and the
-- movement cluster. Recomputed on UIDevice.Changed so a rotation or a device
-- swap does not leave the panel under a thumbstick.

local function place()
	local layout = UIDevice.Layout()
	local area = layout.ModalViewport or layout.Safe
	local width = math.min(400, area.Width - 16)
	local height = math.min(520, area.Height - 16)
	panel.Position = UDim2.fromOffset(
		math.floor(area.Left + (area.Width - width) * .5),
		math.floor(area.Top + (area.Height - height) * .5))
	panel.Size = UDim2.fromOffset(math.floor(width), math.floor(height))
end

UIDevice.Changed:Connect(function()
	if gui.Enabled then place() end
end)

-- ------------------------------------------------------------------ the rows

local order = 0
local function nextOrder(): number
	order += 1
	return order
end

local function header(text: string, dim: boolean?)
	local label = Instance.new("TextLabel")
	label.Size = UDim2.new(1, 0, 0, if dim then 18 else 24)
	label.BackgroundTransparency = 1
	label.Font = if dim then Enum.Font.Gotham else Enum.Font.GothamBold
	label.TextSize = if dim then 11 else 13
	label.TextXAlignment = Enum.TextXAlignment.Left
	label.TextColor3 = if dim then Color3.fromRGB(130, 140, 152) else Color3.fromRGB(120, 200, 255)
	label.Text = text
	label.LayoutOrder = nextOrder()
	label.Parent = scroll
	return label
end

local render -- forward declaration

local function send(key: string, value: number?)
	devTuning:FireServer(key, value)
end

local function button(parent: Frame, text: string, x: number, width: number, enabled: boolean)
	local b = Instance.new("TextButton")
	b.Size = UDim2.new(0, width, 0, TOUCH_TARGET - 8)
	b.Position = UDim2.new(1, x, .5, -(TOUCH_TARGET - 8) / 2)
	b.BackgroundColor3 = Color3.fromRGB(38, 43, 52)
	b.BorderSizePixel = 0
	b.AutoButtonColor = enabled
	b.Active = enabled
	b.Font = Enum.Font.GothamBold
	b.TextSize = 12
	b.TextColor3 = if enabled then Color3.fromRGB(225, 232, 240) else Color3.fromRGB(95, 103, 114)
	b.Text = text
	b.Parent = parent
	local c = Instance.new("UICorner")
	c.CornerRadius = UDim.new(0, 5)
	c.Parent = b
	return b
end

local function row(entry: any)
	local override = Master.GetOverride(entry.Key)
	local default = Master.GetDefault(entry.Key)
	local current = if override ~= nil then override else default
	local overridden = override ~= nil

	local frame = Instance.new("Frame")
	frame.Size = UDim2.new(1, 0, 0, math.max(ROW_HEIGHT, TOUCH_TARGET))
	frame.BackgroundTransparency = 1
	frame.LayoutOrder = nextOrder()
	frame.Parent = scroll

	local label = Instance.new("TextLabel")
	label.Size = UDim2.new(1, -196, 1, 0)
	label.BackgroundTransparency = 1
	label.Font = Enum.Font.Gotham
	label.TextSize = 12
	label.TextXAlignment = Enum.TextXAlignment.Left
	label.TextTruncate = Enum.TextTruncate.AtEnd
	label.TextColor3 = if overridden then Color3.fromRGB(255, 210, 120) else Color3.fromRGB(205, 212, 220)
	label.Text = (if overridden then "\u{25CF} " else "") .. entry.Label
	label.Parent = frame

	local box = Instance.new("TextBox")
	box.Size = UDim2.new(0, 60, 0, TOUCH_TARGET - 8)
	box.Position = UDim2.new(1, -132, .5, -(TOUCH_TARGET - 8) / 2)
	box.BackgroundColor3 = Color3.fromRGB(26, 30, 37)
	box.BorderSizePixel = 0
	box.Font = Enum.Font.Code
	box.TextSize = 12
	box.TextColor3 = Color3.fromRGB(235, 240, 245)
	box.ClearTextOnFocus = false
	box.PlaceholderText = string.format("%s-%s", tostring(entry.Minimum), tostring(entry.Maximum))
	box.Text = tostring(current or "?")
	box.Parent = frame
	local boxCorner = Instance.new("UICorner")
	boxCorner.CornerRadius = UDim.new(0, 5)
	boxCorner.Parent = box

	-- Step buttons exist so this is usable without a keyboard. They are also the
	-- only consumer of the registry's Step, which would otherwise be a field
	-- nothing reads.
	local minus = button(frame, "\u{2212}", -196, 28, true)
	local plus = button(frame, "+", -164, 28, true)
	local reset = button(frame, "Nulstil", -64, 60, overridden)

	local function nudge(direction: number)
		local from = current or entry.Minimum
		local wanted = Master.Coerce(entry.Key, from + direction * entry.Step)
		if wanted ~= nil then send(entry.Key, wanted) end
	end
	minus.MouseButton1Click:Connect(function() nudge(-1) end)
	plus.MouseButton1Click:Connect(function() nudge(1) end)
	reset.MouseButton1Click:Connect(function()
		if overridden then send(entry.Key, nil) end
	end)

	box.FocusLost:Connect(function(enterPressed)
		if not enterPressed then
			render()
			return
		end
		local wanted = Master.Coerce(entry.Key, box.Text)
		if wanted == nil then
			status.Text = string.format("'%s' er ikke et tal.", box.Text)
			render()
			return
		end
		send(entry.Key, wanted)
	end)

	if entry.Note or not entry.Live then
		local note = Instance.new("TextLabel")
		note.Size = UDim2.new(1, -8, 0, 14)
		note.AutomaticSize = Enum.AutomaticSize.Y
		note.BackgroundTransparency = 1
		note.Font = Enum.Font.Gotham
		note.TextSize = 10
		note.TextWrapped = true
		note.TextXAlignment = Enum.TextXAlignment.Left
		note.TextColor3 = Color3.fromRGB(122, 132, 145)
		note.Text = "   " .. (entry.Note or "Træder i kraft ved næste runde-opbygning.")
		note.LayoutOrder = nextOrder()
		note.Parent = scroll
	end
end

function render()
	order = 0
	for _, child in ipairs(scroll:GetChildren()) do
		if not child:IsA("UIListLayout") then child:Destroy() end
	end
	local level, group, overridden = nil, nil, 0
	for _, entry in ipairs(Master.Entries) do
		if entry.Level ~= level then
			level, group = entry.Level, nil
			header(entry.Level)
		end
		if entry.Group ~= group then
			group = entry.Group
			header("  " .. entry.Group, true)
		end
		if Master.GetOverride(entry.Key) ~= nil then overridden += 1 end
		row(entry)
	end
	if status.Text == "" then
		status.Text = string.format("%d værdier, %d overstyret. K lukker.",
			#Master.Entries, overridden)
	end
end

-- ------------------------------------------------------------------ lifecycle

-- Re-render when the server confirms a write, and when anything else changes an
-- override -- the Studio plugin editing the same attributes, or another
-- developer in the same session.
player:GetAttributeChangedSignal("DevTuningSerial"):Connect(function()
	local answer = player:GetAttribute("DevTuningStatus")
	status.Text = if answer == "OK" then "" else ("Afvist: " .. tostring(answer))
	if gui.Enabled then render() end
end)

task.spawn(function()
	local folder = ReplicatedStorage:WaitForChild("MasterTuning", 30)
	if folder then
		folder.AttributeChanged:Connect(function()
			if gui.Enabled then render() end
		end)
	end
end)

local function toggle()
	gui.Enabled = not gui.Enabled
	-- Stand the movement controls down while the panel is up, the same way the
	-- other screen-owning modals do -- otherwise a tap that misses a button
	-- walks the character.
	UIDevice.SuppressTouchMovement(gui.Enabled)
	if gui.Enabled then
		status.Text = ""
		place()
		render()
	end
end

ContextActionService:BindAction("MongoTVMasterTuning", function(_, state)
	if state == Enum.UserInputState.Begin then toggle() end
	return Enum.ContextActionResult.Sink
end, false, Enum.KeyCode.K)
