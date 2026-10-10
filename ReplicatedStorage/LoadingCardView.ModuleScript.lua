-- Shared imported loading presentation. Callers own their entry/boot barriers and cover lifetime.
local RS = game:GetService("ReplicatedStorage")
local UIDevice = require(RS:WaitForChild("UIDevice"))
local Hud = require(RS:WaitForChild("RoundHud"))
local Binder = require(RS:WaitForChild("ZyntraShopUI"):WaitForChild("ShopBinder"))

local View = {}
View.__index = View

-- The approved RoundUI registry, shared with the reserved-server loading owner.
View.Palettes = {
	[1] = {Title = Color3.fromRGB(255, 230, 0), Status = Color3.fromRGB(158, 143, 0)},
	[2] = {Title = Color3.fromRGB(77, 163, 255), Status = Color3.fromRGB(48, 101, 158)},
	[3] = {Title = Color3.fromRGB(255, 0, 0), Status = Color3.fromRGB(184, 0, 0)},
	[4] = {Title = Color3.fromRGB(255, 70, 200), Status = Color3.fromRGB(158, 43, 124)},
	[5] = {Title = Color3.fromRGB(212, 220, 232), Status = Color3.fromRGB(131, 136, 144)},
	[6] = {Title = Color3.fromRGB(156, 134, 255), Status = Color3.fromRGB(97, 83, 158)},
}
View.MysteryTitles = {[2] = "UNRECORDED", [5] = "??? WHERE?"}
View.MysteryTitlePool = {"UNRECORDED", "NO FOOTAGE", "TAPE ENDS HERE", "??? WHERE?", "WHERE IS THIS?",
	"UNMAPPED", "BLANK TAPE", "ANYONE THERE?", "??? EXIT?"}
View.MysteryTitleMode = "fixed"
View.Cards = {
	-- LEVER_PATH_20261010 (puzzle-client): the loading steps teach the return trip to the lever.
	[1] = {Eyebrow = "LEVEL 1", Title = "RESTORE THE POWER", Tip = "L1Entity", Steps = {
		"Fill the fuse boxes. Fuses sit in relays under the amber lights.",
		"Then go back along the cable. It leads to the lever.", "Get out through the lit exit door."}},
	[3] = {Eyebrow = "LEVEL 3", Title = "FIND THE CDS", Tip = "L3Manager", Steps = {
		"Find the CDs hidden around the mall.", "Bring the CDs to the player.", "Follow the reader to the exit."}},
	[4] = {Eyebrow = "LEVEL 4 \u{B7} THE LAST SHOW", Title = "RESTORE THE POWER", Tip = "L4Usher", Steps = {
		"Restore the circuit breakers.", "Find the keys and read the order note.", "Open the exit and get out."}},
	[6] = {Eyebrow = "LEVEL 6", Title = "THE PLAYGROUND"},
}

function View.MysteryTitle(level, mode)
	local fixed = View.MysteryTitles[tonumber(level) or 0]
	if fixed == nil or (mode or View.MysteryTitleMode) ~= "random" then return fixed end
	return View.MysteryTitlePool[math.random(#View.MysteryTitlePool)]
end

local function completeImportedCard(root, touch)
	if touch then
		-- The compact import has two18px rows. Reuse its authored row for the registry's third
		-- instruction, retaining row heights and gaps while leaving Status and LevelTrack fixed.
		local steps = Binder.find(root, "Steps")
		local second = steps and steps:FindFirstChild("Step2")
		if second and not steps:FindFirstChild("Step3") then
			local third = second:Clone()
			third.Name = "Step3"
			local number = Binder.find(third, "Num")
			if number then number.Text = "3" end
			third.Parent = steps
		end
		if steps then
			steps.Size = UDim2.new(steps.Size.X.Scale, steps.Size.X.Offset, 66 / 292, 0)
			steps.Position = UDim2.new(steps.Position.X.Scale, steps.Position.X.Offset,
				(80 + steps.AnchorPoint.Y * 66) / 292, 0)
			for i = 1, 3 do
				local row = steps:FindFirstChild("Step" .. i)
				if row then
					row.Size = UDim2.new(row.Size.X.Scale, row.Size.X.Offset, 18 / 66, 0)
					row.Position = UDim2.new(row.Position.X.Scale, row.Position.X.Offset,
						((i - 1) * 24 + row.AnchorPoint.Y * 18) / 66, 0)
				end
			end
		end
		for _, name in ipairs({"Divider", "Tip"}) do
			local node = Binder.find(root, name)
			if node then
				node.Position = UDim2.new(node.Position.X.Scale, node.Position.X.Offset,
					node.Position.Y.Scale + 24 / 292, node.Position.Y.Offset)
			end
		end
	end
	-- Both imports stamped the TIP ink box instead of a full text line. Give the same label
	-- a real line box; TipText keeps its authored start (19.17px compact,31.28px PC).
	local label = Binder.at(root, "Tip/TipLabel")
	if label then
		local height, parentHeight = touch and 18 or 24, touch and 52 or 84
		-- Leave breathing room beside the ink width; fractional import rounding can otherwise clip TIP.
		local width, parentWidth = touch and 32 or 48, touch and 726 or 960
		local widthScale = math.max(label.Size.X.Scale, width / parentWidth)
		local x = label.Position.X.Scale + label.AnchorPoint.X * (widthScale - label.Size.X.Scale)
		label.Size = UDim2.new(widthScale, label.Size.X.Offset, height / parentHeight, 0)
		label.Position = UDim2.new(x, label.Position.X.Offset,
			label.AnchorPoint.Y * height / parentHeight, 0)
	end
end

function View:_paint()
	if self.Destroyed or not self.Root then return end
	local card = View.Cards[self.Level] or View.Cards[1]
	local palette = View.Palettes[self.Level] or View.Palettes[1]
	local mystery = self.MysteryText ~= nil
	self.Title.Text = self.MysteryText or card.Title
	Hud.Paint(self.Root, "LoadingCard", self.Level)
	self.Title.TextColor3 = palette.Title
	for _, name in ipairs({"Eyebrow", "Steps", "Divider", "Tip"}) do
		local node = Binder.find(self.Root, name)
		if node then node.Visible = not mystery and (name ~= "Steps" or card.Steps ~= nil)
			and (name ~= "Tip" and name ~= "Divider" or card.Tip ~= nil) end
	end
	local eyebrow = Binder.find(self.Root, "Eyebrow")
	if eyebrow then eyebrow.Text = card.Eyebrow or "" end
	for i, line in ipairs(card.Steps or {}) do
		local node = Binder.at(self.Root, "Steps/Step" .. i .. "/Line")
		if node then node.Text = line end
	end
	local tip = Binder.find(self.Root, "TipText")
	if tip then
		local ok, advice = pcall(require, RS:FindFirstChild("DeathAdvice"))
		tip.Text = card.Tip and ok and advice.Copy(card.Tip).Tip or ""
	end
	for i = 1, 6 do
		local slot = Binder.at(self.Root, "LevelTrack/Slot" .. i)
		if slot then
			slot.Text = (i == 2 or i == 5) and "?" or tostring(i)
			slot.TextColor3 = i == self.Level and palette.Title or Color3.fromRGB(167, 184, 174)
			slot.TextTransparency = i == self.Level and 0 or 0.55
		end
	end
end

function View:_mount()
	if self.Destroyed then return end
	local layout = UIDevice.Layout()
	local touch = layout.IsTouch or layout.Safe.Height < 620 or layout.Safe.Width < 800
	local name = touch and "LoadingCardTouch" or "LoadingCard"
	local width, height = touch and 726 or 960, touch and 292 or 782
	local scale = math.min(1, (layout.Safe.Width - 24) / width,
		math.max(120, layout.Safe.Height - 24) / height)
	local visible = self.Root == nil or self.Root.Visible
	if self.Status then self.StatusText = self.Status.Text end
	if self.Root then self.Root:Destroy() end
	self.Root = Hud.Mount("HUD_Screens", name, self.Parent,
		{Name = "LoadingCard", Scale = scale, Touch = touch,
			Prepare = function(root) completeImportedCard(root, touch) end})
	self.Title, self.Status, self.Fill = nil, nil, nil
	if not self.Root then return end
	local gui = self.Parent
	while gui and not gui:IsA("ScreenGui") do gui = gui.Parent end
	self.Root.AnchorPoint = Vector2.new(0.5, 0.5)
	self.Root.Position = UIDevice.LocalPosition(gui,
		(layout.Safe.Left + layout.Safe.Right) / 2, (layout.Safe.Top + layout.Safe.Bottom) / 2)
	self.Root.Visible = visible
	for _, node in ipairs(self.Root:GetDescendants()) do
		if node:IsA("GuiObject") then node.ZIndex = 101 end
	end
	self.Title = Binder.find(self.Root, "Title")
	self.Status = Binder.find(self.Root, "StatusLine")
	self.Status.Text, self.Status.TextColor3 = self.StatusText, Color3.fromRGB(167, 184, 174)
	self.Fill = Binder.at(self.Root, "Status/Track/Fill")
	self.Fill.Size = UDim2.fromScale(self.Progress, 1)
	self:_paint()
	if self.OnMount then self.OnMount(self) end
end

function View:SetLevel(level)
	if self.Destroyed then return end
	self.Level = math.clamp(tonumber(level) or 1, 1, 6)
	self.MysteryText = View.MysteryTitle(self.Level, self.MysteryTitleMode)
	self.Progress = 0
	self:_mount()
end

function View:SetStatus(text, fraction)
	if self.Destroyed then return end
	if text ~= nil then
		self.StatusText = tostring(text)
		if self.Status then self.Status.Text = self.StatusText end
	end
	if fraction ~= nil then
		self.Progress = math.clamp(tonumber(fraction) or 0, 0, 1)
		if self.Fill then self.Fill.Size = UDim2.fromScale(self.Progress, 1) end
	end
end

function View:Destroy()
	if self.Destroyed then return end
	self.Destroyed = true
	if self.DeviceConnection then self.DeviceConnection:Disconnect() end
	if self.ParentConnection then self.ParentConnection:Disconnect() end
	if self.Root then self.Root:Destroy() end
	self.Root, self.Title, self.Status, self.Fill = nil, nil, nil, nil
end

function View.new(parentFrame, level, onMount)
	local self = setmetatable({Parent = parentFrame, OnMount = onMount,
		StatusText = "PREPARING YOUR PARTY", Progress = 0,
		MysteryTitleMode = View.MysteryTitleMode}, View)
	self:SetLevel(level)
	self.DeviceConnection = UIDevice.Changed:Connect(function() self:_mount() end)
	self.ParentConnection = parentFrame.Destroying:Connect(function() self:Destroy() end)
	return self
end

return View
