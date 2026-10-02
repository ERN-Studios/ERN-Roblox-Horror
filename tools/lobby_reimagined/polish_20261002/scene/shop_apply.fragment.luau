-- Clone-only presentation. The original shop and its purchase/focus writer are never edited.
-- Compose this local function into LobbyPolishScene; call after clone focus plates exist.
local function polishShop(model, state)
	assert(model.Name == "LobbyReimaginedPreview" and model:GetAttribute("LobbyReimaginedOwned") == true, "Wrong preview owner")
	local shop = assert(model:FindFirstChild("R3ShopDisplay"), "Missing cloned shop")
	assert(shop:IsA("Model") and shop:GetAttribute("LobbyReimaginedOwned") == true, "Wrong shop clone")
	local focus = assert(model:FindFirstChild("PreviewShopPressurePlates"), "Missing preview focus plates")
	local preferred = {"Supporter", "AdvancedEquipment", "CosmeticEquipment", "EntityDetector", "Tokens4", "Tokens20", "EmergencyReentry", "ExpeditionPack", "SpeedPotion", "RouteMarker"}
	local rank = {}
	for i, key in ipairs(preferred) do rank[key] = i end
	local records, seen = {}, {}
	local sum = Vector3.zero
	for _, stand in ipairs(shop:GetChildren()) do
		if stand:IsA("Model") and stand:GetAttribute("ShopItemKey") then
			local key = stand:GetAttribute("ShopItemKey")
			assert(not seen[key], "Duplicate shop key " .. tostring(key)); seen[key] = true
			local box = assert(stand:FindFirstChild("ShopHologramBox"), "Missing art for " .. key)
			local plate = assert(stand:FindFirstChild("ShopPressurePlate"), "Missing plate for " .. key)
			local copies = {}
			for _, copy in ipairs(focus:GetChildren()) do
				if copy:IsA("BasePart") and copy:GetAttribute("ShopItemKey") == key then table.insert(copies, copy) end
			end
			assert(#copies == 1 and box:IsA("BasePart") and plate:IsA("BasePart"), "Ambiguous focus/art for " .. key)
			local caption = box:FindFirstChild("ShopHologramCaption")
			local title = caption and caption:FindFirstChild("ShopHologramName")
			assert(title and title:IsA("TextLabel"), "Missing source product title " .. key)
			table.insert(records, {key = key, stand = stand, box = box, plate = plate, copy = copies[1], caption = caption, title = title, kind = stand:GetAttribute("ShopItemKind")})
			sum += box.CFrame.Position
		end
	end
	assert(#records >= 1, "No catalogue cards")
	table.sort(records, function(a, b)
		local ar, br = rank[a.key] or math.huge, rank[b.key] or math.huge
		if ar == br then return a.key < b.key end
		return ar < br
	end)
	local center = CFrame.new(sum / #records) * records[1].box.CFrame.Rotation
	local oldMin, oldMax = math.huge, -math.huge
	for _, record in ipairs(records) do
		local x = center:PointToObjectSpace(record.box.CFrame.Position).X
		oldMin, oldMax = math.min(oldMin, x), math.max(oldMax, x)
	end
	center *= CFrame.new((oldMin + oldMax) / 2, 0, 0)
	-- Ten current products occupy the same end-to-end span. Two wider category gaps.
	-- Unknown future catalogue entries remain present and get a uniform safe pitch.
	local slots = {23.4, 18.4, 13.4, 8.4, 2.5, -2.5, -7.5, -12.5, -18.4, -23.4}
	local span = math.max(oldMax - oldMin, (#records - 1) * 5)
	local standardCatalogue = #records == #preferred
	for _, key in ipairs(preferred) do if not seen[key] then standardCatalogue = false end end
	local width = span + 4.35
	local addedParts, disabledGlows, report = 0, 0, {}
	local function panel(parent, name, cf, size, text, font, textSize)
		local p = parent:FindFirstChild(name)
		if not p then p = Instance.new("Part"); p.Name = name; p.Parent = parent; addedParts += 1 end
		assert(p:IsA("Part"), "Conflicting shop panel")
		p.Size = size; p.CFrame = cf; p.Anchored = true
		p.CanCollide = false; p.CanTouch = false; p.CanQuery = false; p.CastShadow = false
		p.Material = Enum.Material.SmoothPlastic; p.Color = Color3.fromRGB(25, 27, 26); p.Transparency = 0
		p:SetAttribute("LobbyReimaginedOwned", true)
		local gui = p:FindFirstChild("ShopPolishFace")
		if not gui then gui = Instance.new("SurfaceGui"); gui.Name = "ShopPolishFace"; gui.Parent = p end
		gui.Face = Enum.NormalId.Front; gui.SizingMode = Enum.SurfaceGuiSizingMode.FixedSize
		gui.CanvasSize = Vector2.new(math.ceil(size.X * 128), math.ceil(size.Y * 128))
		gui.LightInfluence = 0; gui.Brightness = .85; gui.AlwaysOnTop = false; gui.MaxDistance = 65; gui.Active = false
		local label = gui:FindFirstChild("Label")
		if not label then label = Instance.new("TextLabel"); label.Name = "Label"; label.Parent = gui end
		label.BackgroundTransparency = 1; label.BorderSizePixel = 0
		label.Position = UDim2.fromScale(.045, .08); label.Size = UDim2.fromScale(.91, .84)
		label.Font = font; label.TextSize = textSize; label.TextScaled = false; label.TextWrapped = true
		label.TextColor3 = Color3.fromRGB(231, 231, 219); label.TextStrokeTransparency = 1; label.Text = text; label.Active = false
		return p
	end
	for i, record in ipairs(records) do
		local x = standardCatalogue and slots[i] or (span / 2 - (i - 1) * (span / math.max(1, #records - 1)))
		local oldCF = record.box.CFrame
		local target = center * CFrame.new(x, 0, 0)
		local delta = target * oldCF:Inverse()
		for _, d in ipairs(record.stand:GetDescendants()) do if d:IsA("BasePart") then d.CFrame = delta * d.CFrame end end
		record.copy.CFrame = record.plate.CFrame; record.copy.Size = record.plate.Size
		record.box.Size = Vector3.new(3.7, 3.7, .55)
		record.box.Material = Enum.Material.SmoothPlastic; record.box.Color = Color3.fromRGB(34, 36, 34); record.box.Transparency = 0
		for _, d in ipairs(record.box:GetDescendants()) do
			if d:IsA("SurfaceGui") then d.LightInfluence = 0; d.Brightness = .85; d.MaxDistance = 65 end
			if d:IsA("ImageLabel") then d.ImageColor3 = Color3.fromRGB(242, 242, 233) end
			if d:IsA("SelectionBox") then d.LineThickness = .015; d.Color3 = Color3.fromRGB(114, 120, 111); d.SurfaceTransparency = 1 end
			if d:IsA("Light") and d.Name == "ShopBoxGlow" then d.Enabled = false; disabledGlows += 1 end
		end
		record.caption.Enabled = false
		panel(record.stand, "ShopFixedNamePanel", target * CFrame.new(0, -2.82, -.34), Vector3.new(4.35, 1.12, .08), record.title.Text, Enum.Font.GothamBold, 32)
		table.insert(report, {key = record.key, kind = record.kind, stand = record.stand, box = record.box, plate = record.plate, focusCopy = record.copy})
	end
	local sign = shop:FindFirstChild("SuppliesAndUpgradesSign")
	if sign and sign:IsA("BasePart") then
		sign.Size = Vector3.new(width, 1.52, .16); sign.CFrame = center * CFrame.new(0, 4.77, -.4)
		sign.Material = Enum.Material.SmoothPlastic; sign.Color = Color3.fromRGB(25, 27, 26)
		for _, d in ipairs(sign:GetDescendants()) do
			if d:IsA("SurfaceGui") then d.CanvasSize = Vector2.new(2200, 96); d.Brightness = .85; d.MaxDistance = 90 end
			if d:IsA("TextLabel") then d.TextColor3 = Color3.fromRGB(231, 231, 219); d.TextSize = 64 end
			if d:IsA("UIGradient") then d.Enabled = false end
		end
	end
	for _, d in ipairs(shop:GetChildren()) do
		if d:IsA("BasePart") and d.Name == "SupplySignNeon" then
			d.Material = Enum.Material.SmoothPlastic; d.Color = Color3.fromRGB(113, 116, 100)
			local above = d.CFrame.Position.Y > center.Position.Y + 4.77
			d.CFrame = center * CFrame.new(0, above and 5.58 or 3.96, -.4); d.Size = Vector3.new(width, .04, .1)
		end
	end
	if standardCatalogue then
		panel(shop, "ShopCategoryPasses", center * CFrame.new(15.9, 2.65, -.34), Vector3.new(18.7, .6, .06), "PERMANENT UPGRADES", Enum.Font.GothamMedium, 36)
		panel(shop, "ShopCategoryPacks", center * CFrame.new(-5, 2.65, -.34), Vector3.new(18.7, .6, .06), "RESEARCH & EXPEDITION PACKS", Enum.Font.GothamMedium, 36)
		panel(shop, "ShopCategorySupplies", center * CFrame.new(-20.9, 2.65, -.34), Vector3.new(8.7, .6, .06), "TOKEN SUPPLIES", Enum.Font.GothamMedium, 36)
	end
	panel(shop, "ShopDetailsInstruction", center * CFrame.new(0, -4.37, -.34), Vector3.new(width, .55, .06), "STEP CLOSE TO VIEW DETAILS", Enum.Font.GothamMedium, 38)
	shop:SetAttribute("ShopPolishVersion", 1)
	shop:SetAttribute("ShopPolishAddedTriangles", addedParts * 12)
	return {cards = report, addedParts = addedParts, addedTriangles = addedParts * 12, disabledShopGlows = disabledGlows, rowSpan = span, purchaseRoutesChanged = false}
end
