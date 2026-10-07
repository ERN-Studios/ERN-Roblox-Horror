-- The player's whole HUD laid out as on a phone, inside Studio's ordinary viewport, and measured.
--   python3 tools/level6_playground/mobile_audit.py 844 390        (runs this on the Client of a play session)
--
-- Studio's Device Emulator cannot be driven from a session. What can be done: every ScreenGui the player has is
-- COPIED into a frame of the phone's size (scale-anchored things then resolve against the phone's screen, offsets
-- stay offsets, which is what happens on the device), the originals are switched off, and the copies are measured.
-- Scripts that ask UIDevice where things go get the same phone from the Studio fixtures this sets
-- (workspace.ForceTouchUI / UIRegressionViewport, client-side). The copies are a still: run it again for a new moment.
--
-- It reports, in SCREEN pixels of the phone (y 0 = top edge; Roblox's top bar is the first 58):
--   OVERLAP   two things from different panels whose ink crosses
--   THUMB     ink inside a zone the thumbs own (thumbstick, the button cluster, jump)
--   OFF       ink outside the screen
--   SMALL     text under 11 px high
--   CUT       text that does not fit its box
local W, H = __W__, __H__
local MODE = "__MODE__"                                   -- "on" | "off"
local Players = game:GetService("Players")
local pg = Players.LocalPlayer.PlayerGui

local old = pg:FindFirstChild("PhoneEmu")
if old then old:Destroy() end
for _, g in ipairs(pg:GetChildren()) do
	if g:IsA("ScreenGui") and g:GetAttribute("PhoneEmuHidden") then
		g.Enabled = true
		g:SetAttribute("PhoneEmuHidden", nil)
	end
end
if MODE == "off" then
	workspace:SetAttribute("UIRegressionViewport", nil)
	workspace:SetAttribute("ForceTouchUI", nil)
	return "phone view off"
end

workspace:SetAttribute("ForceTouchUI", true)
workspace:SetAttribute("UIRegressionViewport", Vector2.new(W, H))
task.wait(0.6)                                            -- the HUD scripts re-lay themselves out on UIDevice.Changed
local UIDevice = require(game:GetService("ReplicatedStorage").UIDevice)
local L = UIDevice.Layout()
local TOP = 58

local emu = Instance.new("ScreenGui")
emu.Name, emu.IgnoreGuiInset, emu.ResetOnSpawn, emu.DisplayOrder, emu.ZIndexBehavior = "PhoneEmu", true, false, 5000, Enum.ZIndexBehavior.Sibling
local device = Instance.new("Frame")
device.Name, device.Size, device.BackgroundTransparency, device.ClipsDescendants = "Device", UDim2.fromOffset(W, H), 1, true
device.Parent = emu
local guis = {}
for _, g in ipairs(pg:GetChildren()) do
	if g:IsA("ScreenGui") and g.Enabled and g ~= emu then guis[#guis + 1] = g end
end
table.sort(guis, function(a, b) return a.DisplayOrder < b.DisplayOrder end)
local holders = {}
for rank, g in ipairs(guis) do
	local full = g.IgnoreGuiInset or g.ScreenInsets == Enum.ScreenInsets.None or g.ScreenInsets == Enum.ScreenInsets.DeviceSafeInsets
	local holder = Instance.new("Frame")
	-- not the ScreenGui's own name: scripts that look for "<ScreenGui>.<panel>" among PlayerGui's descendants (Round
	-- Exit Client's obstacle watch) would take the copy for the real thing and ask a Frame for `Enabled`
	holder.Name, holder.BackgroundTransparency, holder.ZIndex = "Copy of " .. g.Name, 1, rank
	holder:SetAttribute("Source", g.Name)
	holder.Position, holder.Size = UDim2.fromOffset(0, full and 0 or TOP), UDim2.new(1, 0, 1, full and 0 or -TOP)
	for _, child in ipairs(g:GetChildren()) do
		if not child:IsA("LuaSourceContainer") then
			local ok, copy = pcall(function() return child:Clone() end)
			if ok and copy then
				for _, d in ipairs(copy:GetDescendants()) do
					if d:IsA("LuaSourceContainer") then d:Destroy() end
				end
				copy.Parent = holder
			end
		end
	end
	holder.Parent = device
	holders[#holders + 1] = holder
	g:SetAttribute("PhoneEmuHidden", true)
	g.Enabled = false
end
-- what is not the phone's screen is blacked out, and the thumbs' zones are drawn
local function mask(name, pos, size)
	local m = Instance.new("Frame")
	m.Name, m.Position, m.Size, m.BackgroundColor3, m.BorderSizePixel, m.ZIndex = name, pos, size, Color3.new(0, 0, 0), 0, 9000
	m.Parent = emu
end
mask("OffRight", UDim2.fromOffset(W, 0), UDim2.new(1, -W, 1, 0))
mask("OffBottom", UDim2.fromOffset(0, H), UDim2.new(1, 0, 1, -H))
local zones = {}
for name, z in pairs(L.Zones) do
	zones[name] = {l = z.Left, t = z.Top + TOP, r = z.Right, b = z.Bottom + TOP}
	local f = Instance.new("Frame")
	f.Name, f.Position, f.Size = "Zone" .. name, UDim2.fromOffset(z.Left, z.Top + TOP), UDim2.fromOffset(z.Right - z.Left, z.Bottom - z.Top)
	f.BackgroundTransparency, f.ZIndex = 1, 8000
	local s = Instance.new("UIStroke"); s.Color, s.Thickness, s.Transparency = Color3.fromRGB(0, 200, 255), 1, 0.35; s.Parent = f
	f.Parent = emu
end
emu.Parent = pg
task.wait(0.5)

-- ---- measure ---------------------------------------------------------------------------------------------------------
local function shown(g, holder)
	local at = g
	while at and at ~= holder do
		if at:IsA("GuiObject") and not at.Visible then return false end
		at = at.Parent
	end
	return true
end
local function panelOf(g, holder)                          -- the top-level thing under its ScreenGui that a piece belongs to
	local at = g
	while at.Parent ~= holder do at = at.Parent end
	return at
end
local items = {}
for _, holder in ipairs(holders) do
	for _, g in ipairs(holder:GetDescendants()) do
		if g:IsA("GuiObject") and shown(g, holder) then
			local p, s = g.AbsolutePosition, g.AbsoluteSize
			local l, t, r, b, kind, text
			if (g:IsA("TextLabel") or g:IsA("TextButton")) and g.Text ~= "" and g.TextTransparency < 0.95 then
				local tb = g.TextBounds
				local cx = (g.TextXAlignment == Enum.TextXAlignment.Left and p.X + tb.X / 2) or (g.TextXAlignment == Enum.TextXAlignment.Right and p.X + s.X - tb.X / 2) or p.X + s.X / 2
				local cy = (g.TextYAlignment == Enum.TextYAlignment.Top and p.Y + tb.Y / 2) or (g.TextYAlignment == Enum.TextYAlignment.Bottom and p.Y + s.Y - tb.Y / 2) or p.Y + s.Y / 2
				l, t, r, b, kind, text = cx - tb.X / 2, cy - tb.Y / 2, cx + tb.X / 2, cy + tb.Y / 2, "text", g.Text
				local lines = select(2, string.gsub(g.Text, "\n", "")) + 1
				items[#items + 1] = {l = l, t = t + TOP, r = r, b = b + TOP, kind = kind, text = text, gui = holder:GetAttribute("Source"), panel = panelOf(g, holder), obj = g,
					small = tb.Y / lines < 11, cut = not g.TextFits}
			end
			local solid = (g:IsA("Frame") or g:IsA("TextButton") or g:IsA("ImageButton") or g:IsA("TextLabel")) and g.BackgroundTransparency < 0.6
			local image = (g:IsA("ImageLabel") or g:IsA("ImageButton")) and g.Image ~= "" and g.ImageTransparency < 0.9
			if (solid or image) and s.X > 6 and s.Y > 6 and s.X * s.Y < W * H * 0.7 then
				items[#items + 1] = {l = p.X, t = p.Y + TOP, r = p.X + s.X, b = p.Y + s.Y + TOP, kind = solid and "box" or "image", text = g.Name, gui = holder:GetAttribute("Source"),
					panel = panelOf(g, holder), obj = g}
			end
		end
	end
end
local function describe(i)
	return string.format("%s.%s%s (%.0f,%.0f)-(%.0f,%.0f)", i.gui, i.panel.Name, i.kind == "text" and (" '" .. i.text:gsub("\n", " "):sub(1, 30) .. "'") or (i.obj == i.panel and "" or (" > " .. i.text)), i.l, i.t, i.r, i.b)
end
local report, seen = {}, {}
local function add(line)
	if not seen[line] then seen[line] = true; report[#report + 1] = line end
end
for a = 1, #items do
	local i = items[a]
	if i.kind == "text" then
		if i.small then add("SMALL   " .. describe(i)) end
		if i.cut then add("CUT     " .. describe(i)) end
		-- (wholly outside is how a toast waits its turn: only a piece that is cut by the edge counts)
		local onScreen = i.r > 0 and i.b > 0 and i.l < W and i.t < H
		if onScreen and (i.l < -1 or i.t < -1 or i.r > W + 1 or i.b > H + 1) then add("OFF     " .. describe(i)) end
	end
	-- the zones belong to the game's own buttons (NoiseReporter's cluster in StaminaGui, the torch): they may be there
	if i.gui ~= "TouchGui" and i.gui ~= "StaminaGui" and i.gui ~= "FlashlightPopup" then
		for name, z in pairs(zones) do
			local w, h = math.min(i.r, z.r) - math.max(i.l, z.l), math.min(i.b, z.b) - math.max(i.t, z.t)
			if w > 4 and h > 4 and not i.obj:GetAttribute("PhoneEmuControl") then
				add(string.format("THUMB   %s is %0.fx%.0f px inside the %s zone", describe(i), w, h, name))
			end
		end
	end
	for b = a + 1, #items do
		local j = items[b]
		local both = i.r > 0 and i.b > 0 and i.l < W and i.t < H and j.r > 0 and j.b > 0 and j.l < W and j.t < H
		if both and i.panel ~= j.panel and (i.kind == "text" or j.kind == "text") then
			local w, h = math.min(i.r, j.r) - math.max(i.l, j.l), math.min(i.b, j.b) - math.max(i.t, j.t)
			if w > 5 and h > 5 then
				add(string.format("OVERLAP %s  x  %s  (%.0fx%.0f px)", describe(i), describe(j), w, h))
			end
		end
	end
end
table.sort(report)
local names = {}
for _, h in ipairs(holders) do names[#names + 1] = h:GetAttribute("Source") end
return string.format("phone %dx%d, %d ScreenGuis copied (%s), %d pieces measured, %d findings\n%s", W, H, #holders, table.concat(names, ", "), #items, #report, table.concat(report, "\n"))
