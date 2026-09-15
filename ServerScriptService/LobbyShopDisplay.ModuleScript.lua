-- LobbyShopDisplay
-- The Zyntra SHOP frontage in the transit lobby: a recessed shop built into the
-- RIGHT service ledge between the Level 2 gate and the supply kiosk, with one
-- pedestal per catalogue item, a crate hovering over each, and a floor plate in
-- front of it that opens that item's detail card for the player standing there.
--
-- NOTHING HERE EVER TAKES MONEY. A plate sets ONE player attribute,
-- ZyntraShopFocus; the client draws a card from it; the card's BUY routes back
-- into ZyntraStore's own product-card purchase path. Walking onto a plate can
-- not prompt a purchase and this module never touches MarketplaceService --
-- neither for a prompt nor for a price, because a price read here would be read
-- once per server and could then disagree with the live one the terminal shows.
-- The card fetches the price itself, the same way the terminal's cards do.
--
-- Called by TunnelLobbyBuilder at the end of Builder.Build. The lobby is rebuilt
-- from scratch at every play start, so Build destroys a previous
-- ZyntraShopDisplay first and is safe to call again on the same lobby.

local Players = game:GetService("Players")
local ReplicatedStorage = game:GetService("ReplicatedStorage")
local Config = require(ReplicatedStorage:WaitForChild("ZyntraConfig"))

local LobbyShopDisplay = {}

-- ── texture slots ───────────────────────────────────────────────────────────
-- Codex fills these in (artifacts/trello-20260915/texture-requests.md). An empty
-- string draws the procedural placeholder instead, so the shop is complete and
-- interactive before a single texture exists. Bare numeric ids and full
-- rbxassetid:// urls are both accepted; anything else is ignored rather than
-- rendered as a broken surface.
local SHOP_TEXTURES = {
	SignFace = "rbxassetid://126032557889771",
	SignGlow = "rbxassetid://92494312014031",
	PedestalTop = "rbxassetid://101891958398163",
	PlateTop = "rbxassetid://131434121223604",
	Backdrop = "rbxassetid://124038960784765",
	BoxFallback = "rbxassetid://90558430724311",
	Box = {
		Supporter = "rbxassetid://75534988741783",
		AdvancedEquipment = "rbxassetid://133698774797678",
		CosmeticEquipment = "rbxassetid://95744112613263",
		Tokens4 = "rbxassetid://127956354478910",
		Tokens20 = "rbxassetid://114348157561307",
		EmergencyReentry = "rbxassetid://93091494402773",
	},
}

-- ── palette ─────────────────────────────────────────────────────────────────
-- The lobby's own Zyntra values (TunnelLobbyBuilder.COLORS) and the terminal's
-- (ZyntraStore.COLORS), restated because both are file-locals. Keep them equal
-- to their sources: the shop wall and the card a plate opens have to look like
-- the same brand.
local PALETTE = {
	neon = Color3.fromRGB(73, 245, 204),
	green = Color3.fromRGB(86, 255, 173),
	gold = Color3.fromRGB(255, 203, 79),
	amber = Color3.fromRGB(255, 183, 72),
	red = Color3.fromRGB(244, 95, 82),
	black = Color3.fromRGB(7, 11, 13),
	panel = Color3.fromRGB(20, 29, 33),
	metal = Color3.fromRGB(32, 35, 34),
	metalLight = Color3.fromRGB(62, 66, 62),
	text = Color3.fromRGB(232, 240, 238),
}

-- ── where it stands ─────────────────────────────────────────────────────────
-- Measured against Builder.Build's own geometry, all relative to the lobby
-- centre. The right LowerTunnelWall's inner face is x = +32.9 and the service
-- ledge's top is y = +0.65. The closed wall section here runs z -70 .. -10; the
-- Level 2 doorway's lintel ends at z = -69.5 and the supply kiosk's floor pad
-- starts at z = -44.75, so -68.2 .. -45.8 is the empty stretch between them.
--
-- The height ceiling is NOT the wall: the tunnel's curved shell (inner radius
-- 33.9 about x=0, y=+1) and its reinforcement ribs (inner radius 33.25, one
-- arch at z = -52, inside this span) cut in above roughly y = 9. That is why
-- the sign stands FORWARD of the back panel at x = 31.3 instead of flat on it,
-- and why nothing reaches past y = 10.6.
local AREA_Z = -57          -- centre of the frontage along the tunnel
local AREA_HALF = 11.2      -- so the deck spans z -68.2 .. -45.8
local FLOOR_Y = 0.65        -- top of the right service ledge
local BACK_X = 32.55        -- back panel, just proud of the wall face at 32.9
local PEDESTAL_X = 30.9     -- pedestal centres before the arc's bow
local PEDESTAL_BOW = 0.85   -- how far the middle pedestals lean toward the road
local PLATE_X = 27.5        -- the inspect plates, one pace in front of the arc
local ITEM_SPACING = 3.7
local PLATE_HALF_X, PLATE_HALF_Z = 1.7, 1.7
local PLATE_HYSTERESIS = 0.6 -- the zone a player already inside has to leave
local LATCH_RANGE = 14       -- how far a prompt's focus survives being walked away from
local FOCUS_POLL = 0.2       -- seconds; also the debounce for a plate's edge
local FOCUS_ATTRIBUTE = "ZyntraShopFocus"
local MODEL_NAME = "ZyntraShopDisplay"

-- The terminal's Shop tab order, so the wall reads left to right the way the
-- card list reads top to bottom. Anything in the catalogue that is NOT named
-- here still gets a pedestal (see `catalogue`), with the fallback crate.
local DISPLAY_ORDER = {
	{Key = "Supporter", Kind = "Pass"},
	{Key = "AdvancedEquipment", Kind = "Pass"},
	{Key = "Tokens4", Kind = "Product"},
	{Key = "Tokens20", Kind = "Product"},
	{Key = "EmergencyReentry", Kind = "Product"},
	{Key = "CosmeticEquipment", Kind = "Pass"},
}

local SOURCES = {
	{Kind = "Pass", Table = Config.Passes},
	{Kind = "Product", Table = Config.Products},
}

local function catalogue()
	local list, seen = {}, {}
	for _, entry in ipairs(DISPLAY_ORDER) do
		for _, source in ipairs(SOURCES) do
			local item = entry.Kind == source.Kind and source.Table and source.Table[entry.Key]
			if item then
				seen[entry.Key] = true
				table.insert(list, {Key = entry.Key, Kind = entry.Kind, Item = item})
			end
		end
	end
	-- A product added to ZyntraConfig later appears on the wall by itself rather
	-- than being silently absent from it. Sorted, so two servers build the same
	-- shop from the same catalogue.
	for _, source in ipairs(SOURCES) do
		local extra = {}
		for key in pairs(source.Table or {}) do
			if not seen[key] then table.insert(extra, key) end
		end
		table.sort(extra)
		for _, key in ipairs(extra) do
			table.insert(list, {Key = key, Kind = source.Kind, Item = source.Table[key]})
		end
	end
	return list
end

-- ── small builders ──────────────────────────────────────────────────────────
local function assetUrl(id)
	local text = tostring(id or "")
	if text:match("^%d+$") and text ~= "0" then return "rbxassetid://" .. text end
	if text:match("^rbxassetid://%d+$") then return text end
	return nil
end

local function makePart(parent, name, cf, size, color, material, transparency)
	local part = Instance.new("Part")
	part.Name = name
	part.Anchored = true
	part.CanCollide = false
	part.CanTouch = false
	part.CastShadow = false
	part.Size = size
	part.CFrame = cf
	part.Color = color
	part.Material = material or Enum.Material.SmoothPlastic
	part.Transparency = transparency or 0
	part.TopSurface = Enum.SurfaceType.Smooth
	part.BottomSurface = Enum.SurfaceType.Smooth
	part.Parent = parent
	return part
end

local function addDecal(part, face, slot, id, color)
	local url = assetUrl(id)
	if not url then return nil end
	local decal = Instance.new("Decal")
	decal.Name = "ShopTexture"
	decal.Face = face
	decal.Texture = url
	if color then decal.Color3 = color end
	decal.Parent = part
	part:SetAttribute("ShopTextureSlot", slot)
	return decal
end

-- A flat readable face on a part, sized in canvas pixels so the 100px font cap
-- is not what decides how big the type gets (see the lobby's own signs).
local function addFace(part, face, canvasX, canvasY)
	local gui = Instance.new("SurfaceGui")
	gui.Name = "ShopFace"
	gui.Face = face
	gui.CanvasSize = Vector2.new(canvasX, canvasY)
	gui.LightInfluence = 0
	gui.AlwaysOnTop = false
	gui.Parent = part
	return gui
end

local function addText(parent, name, text, position, size, color, font)
	local label = Instance.new("TextLabel")
	label.Name = name
	label.BackgroundTransparency = 1
	label.Position = position
	label.Size = size
	label.Font = font or Enum.Font.GothamBold
	label.Text = text
	label.TextColor3 = color
	label.TextScaled = true
	label.TextWrapped = true
	label.Parent = parent
	return label
end

function LobbyShopDisplay.Build(lobbyModel, config)
	if typeof(lobbyModel) ~= "Instance" then
		warn("[LobbyShopDisplay] Build needs the lobby model")
		return nil
	end
	config = config or {}
	local center = config.Center or lobbyModel:GetPivot().Position
	local textures = config.Textures or SHOP_TEXTURES

	local previous = lobbyModel:FindFirstChild(MODEL_NAME)
	if previous then previous:Destroy() end

	local model = Instance.new("Model")
	model.Name = MODEL_NAME
	model:SetAttribute("ShopDisplayVersion", 1)
	model:SetAttribute("Placement", "Right service ledge between the Level 2 gate and the supply kiosk")
	model:SetAttribute("FocusAttribute", FOCUS_ATTRIBUTE)
	model.Parent = lobbyModel

	-- Every part faces the road: the part's Front (-Z) points at the tunnel's
	-- centre line, so a size of (width, height, depth) means width ALONG the
	-- wall. The same convention the lobby's signal console uses.
	local function faceCF(x, y, z)
		local position = center + Vector3.new(x, y, AREA_Z + z)
		return CFrame.lookAt(position, center + Vector3.new(0, y, AREA_Z + z))
	end

	-- Shell: deck, back panel, two pilasters and a header. It reads as a recess
	-- cut into the wall because the frame stands proud of a dark back panel --
	-- the tunnel wall itself is never moved or removed.
	local deckWidth = 6.6
	local deck = makePart(model, "ShopDeck",
		faceCF(29.3, FLOOR_Y + 0.075, 0), Vector3.new(AREA_HALF * 2, 0.15, deckWidth),
		Color3.fromRGB(38, 46, 45), Enum.Material.DiamondPlate)
	deck:SetAttribute("ShopArea", true)

	local backdrop = makePart(model, "ShopAlcoveBackdrop",
		faceCF(BACK_X, FLOOR_Y + 5.1, 0), Vector3.new(AREA_HALF * 2, 9.4, 0.2),
		PALETTE.panel, Enum.Material.Metal)
	backdrop.Reflectance = 0.14
	if not addDecal(backdrop, Enum.NormalId.Front, "Backdrop", textures.Backdrop) then
		backdrop:SetAttribute("ShopTextureSlot", "Backdrop")
	end

	for _, side in ipairs({-1, 1}) do
		makePart(model, "ShopPilaster",
			faceCF(30.6, FLOOR_Y + 5.1, side * (AREA_HALF - 0.45)), Vector3.new(0.9, 9.4, 4.6),
			PALETTE.metal, Enum.Material.Metal)
		makePart(model, "ShopPilasterTrim",
			faceCF(28.28, FLOOR_Y + 5.1, side * (AREA_HALF - 0.45)), Vector3.new(0.12, 8.6, 0.14),
			PALETTE.neon, Enum.Material.Neon, 0.05)
	end

	-- 4.0 deep, not the shell's full reach: above y = 10.3 the tunnel's curved
	-- ceiling has already come in past x = 32.4 and a deeper soffit would be
	-- buried in it.
	makePart(model, "ShopHeaderSoffit",
		faceCF(30.0, FLOOR_Y + 9.95, 0), Vector3.new(AREA_HALF * 2, 0.55, 4.0),
		PALETTE.metal, Enum.Material.Metal)

	-- The sign. It stands FORWARD of the back panel so it clears the tunnel's
	-- curved shell, which is also where it reads best from: a player walking up
	-- from the spawn sees the face, not the wall it hangs on.
	local signGlow = makePart(model, "ShopSignGlowPanel",
		faceCF(31.78, FLOOR_Y + 8.15, 0), Vector3.new(16.1, 4.0, 0.12),
		PALETTE.neon, Enum.Material.Neon, 0.62)
	signGlow:SetAttribute("ShopSignGlow", true)
	if not addDecal(signGlow, Enum.NormalId.Front, "SignGlow", textures.SignGlow) then
		signGlow:SetAttribute("ShopTextureSlot", "SignGlow")
	end

	local sign = makePart(model, "ShopSignFace",
		faceCF(31.42, FLOOR_Y + 8.15, 0), Vector3.new(14.4, 3.6, 0.4),
		PALETTE.black, Enum.Material.Metal)
	if not addDecal(sign, Enum.NormalId.Front, "SignFace", textures.SignFace) then
		sign:SetAttribute("ShopTextureSlot", "SignFace")
		-- Procedural stand-in for shop-sign-face.png: the word, in the brand's
		-- own neon, on the sign's own housing.
		local gui = addFace(sign, Enum.NormalId.Front, 1024, 256)
		local title = addText(gui, "SignWord", "SHOP", UDim2.fromScale(0.04, 0.06),
			UDim2.fromScale(0.92, 0.62), PALETTE.neon, Enum.Font.GothamBlack)
		title.TextStrokeTransparency = 0.55
		addText(gui, "SignLine", "ZYNTRA // SUPPLY", UDim2.fromScale(0.04, 0.7),
			UDim2.fromScale(0.92, 0.2), PALETTE.amber, Enum.Font.Code)
	end
	for _, side in ipairs({-1, 1}) do
		makePart(model, "ShopSignTrim",
			faceCF(31.42, FLOOR_Y + 8.15 + side * 2.0, 0), Vector3.new(14.4, 0.14, 0.42),
			side < 0 and PALETTE.amber or PALETTE.neon, Enum.Material.Neon, 0.05)
	end

	-- Restrained light: two wide floods over the pedestals and one on the sign.
	-- No spinning beams, no strobes -- the sign's own pulse is the only motion,
	-- and the client owns it so it can stand down under ReduceFlashing.
	local signLight = Instance.new("SurfaceLight")
	signLight.Name = "ShopSignLight"
	signLight.Face = Enum.NormalId.Front
	signLight.Color = PALETTE.neon
	signLight.Brightness = 1.1
	signLight.Range = 16
	signLight.Angle = 110
	signLight.Shadows = false
	signLight.Parent = sign
	for _, offset in ipairs({-5.6, 5.6}) do
		local flood = makePart(model, "ShopFloodHousing",
			faceCF(30.2, FLOOR_Y + 9.45, offset), Vector3.new(1.6, 0.3, 1.0),
			PALETTE.metalLight, Enum.Material.Metal)
		local light = Instance.new("SpotLight")
		light.Name = "ShopFloodLight"
		light.Face = Enum.NormalId.Bottom
		light.Color = Color3.fromRGB(226, 245, 240)
		light.Brightness = 1.4
		light.Range = 14
		light.Angle = 95
		light.Shadows = false
		light.Parent = flood
	end

	-- ── one pedestal, crate, nameplate and plate per catalogue item ───────────
	local items = catalogue()
	local count = #items
	local plates = {}
	local prompts = {}
	for index, entry in ipairs(items) do
		local offset = (index - (count + 1) * 0.5) * ITEM_SPACING
		local span = math.max(1, (count - 1) * 0.5 * ITEM_SPACING)
		-- A gentle arc: the middle of the row leans a little further toward the
		-- road than its ends, so the row is not a flat shelf.
		local bow = PEDESTAL_BOW * (1 - (offset / span) ^ 2)
		local x = PEDESTAL_X - bow
		local accent = entry.Key == "EmergencyReentry" and PALETTE.red
			or (entry.Kind == "Pass" and PALETTE.neon or PALETTE.gold)

		local stand = Instance.new("Model")
		stand.Name = "ShopStand_" .. entry.Key
		stand:SetAttribute("ShopItemKey", entry.Key)
		stand:SetAttribute("ShopItemKind", entry.Kind)
		stand.Parent = model

		local column = makePart(stand, "ShopPedestal",
			faceCF(x, FLOOR_Y + 1.4, offset), Vector3.new(2.2, 2.6, 2.2),
			PALETTE.metal, Enum.Material.Metal)
		column.CanCollide = true
		column:SetAttribute("ShopItemKey", entry.Key)

		local cap = makePart(stand, "ShopPedestalCap",
			faceCF(x, FLOOR_Y + 2.85, offset), Vector3.new(2.6, 0.3, 2.6),
			PALETTE.black, Enum.Material.Metal)
		cap:SetAttribute("ShopItemKey", entry.Key)
		if not addDecal(cap, Enum.NormalId.Top, "PedestalTop", textures.PedestalTop) then
			cap:SetAttribute("ShopTextureSlot", "PedestalTop")
			makePart(stand, "ShopPedestalRing",
				faceCF(x, FLOOR_Y + 3.02, offset), Vector3.new(1.9, 0.06, 1.9),
				accent, Enum.Material.Neon, 0.1)
		end

		-- The item's own face on the pedestal. Name and kind only: the price is
		-- live and belongs on the card, which reads it the moment it opens. The
		-- canvas matches the 2.2 x 2.6 face it is drawn on, so the type is not
		-- stretched by the surface.
		local plateGui = addFace(column, Enum.NormalId.Front, 340, 400)
		addText(plateGui, "ItemName", tostring(entry.Item.Name or entry.Key),
			UDim2.fromScale(0.06, 0.16), UDim2.fromScale(0.88, 0.42), PALETTE.text)
		addText(plateGui, "ItemKind", entry.Kind == "Pass" and "PERMANENT PASS" or "SUPPLY",
			UDim2.fromScale(0.06, 0.62), UDim2.fromScale(0.88, 0.2), accent, Enum.Font.Code)

		-- The hovering representation. The client bobs and turns it from this
		-- pose; the server never moves it, so nothing here replicates per frame.
		local box = makePart(stand, "ShopItemBox",
			faceCF(x, FLOOR_Y + 4.55, offset), Vector3.new(2, 2, 2),
			PALETTE.panel, Enum.Material.Metal)
		box:SetAttribute("ShopItemKey", entry.Key)
		box:SetAttribute("ShopBobOrigin", box.CFrame)
		box.Reflectance = 0.08
		local boxTexture = textures.Box and textures.Box[entry.Key]
		local faces = {Enum.NormalId.Front, Enum.NormalId.Back, Enum.NormalId.Left, Enum.NormalId.Right}
		if assetUrl(boxTexture) or assetUrl(textures.BoxFallback) then
			local slot = assetUrl(boxTexture) and ("Box:" .. entry.Key) or "BoxFallback"
			local id = assetUrl(boxTexture) and boxTexture or textures.BoxFallback
			for _, face in ipairs(faces) do addDecal(box, face, slot, id) end
		else
			-- Until the crate art lands, the crate wears the item's own live
			-- monetization icon on the face that looks at the road, and its
			-- accent colour everywhere else. Never a blank box.
			box:SetAttribute("ShopTextureSlot", "Box:" .. entry.Key)
			if not addDecal(box, Enum.NormalId.Front, "Box:" .. entry.Key, entry.Item.IconId) then
				local gui = addFace(box, Enum.NormalId.Front, 256, 256)
				addText(gui, "BoxMonogram", tostring(entry.Item.IconText or "Z//"),
					UDim2.fromScale(0.1, 0.28), UDim2.fromScale(0.8, 0.44), accent, Enum.Font.GothamBlack)
			end
			-- One adornment draws the whole neon silhouette, which is what the
			-- crate art will carry as printed edge trim.
			local edge = Instance.new("SelectionBox")
			edge.Name = "ShopBoxEdge"
			edge.Adornee = box
			edge.Color3 = accent
			edge.LineThickness = 0.04
			edge.Transparency = 0.25
			edge.Parent = box
		end

		local glow = Instance.new("PointLight")
		glow.Name = "ShopBoxGlow"
		glow.Color = accent
		glow.Brightness = 0.7
		glow.Range = 8
		glow.Shadows = false
		glow.Parent = box

		-- The deliberate alternative to standing on the plate: one prompt, on
		-- the pedestal, that opens the same card. E on a keyboard, X on a pad,
		-- and a tap on touch -- which is why the plate is not the only way in.
		local prompt = Instance.new("ProximityPrompt")
		prompt.Name = "ShopInspectPrompt"
		prompt.ActionText = "INSPECT"
		prompt.ObjectText = tostring(entry.Item.Name or entry.Key)
		prompt.KeyboardKeyCode = Enum.KeyCode.E
		prompt.GamepadKeyCode = Enum.KeyCode.ButtonX
		prompt.HoldDuration = 0
		prompt.MaxActivationDistance = 9
		prompt.RequiresLineOfSight = false
		prompt.Parent = column
		prompts[entry.Key] = prompt

		local plate = makePart(stand, "ShopInspectPlate",
			faceCF(PLATE_X, FLOOR_Y + 0.21, offset), Vector3.new(PLATE_HALF_Z * 2, 0.12, PLATE_HALF_X * 2),
			PALETTE.metalLight, Enum.Material.DiamondPlate)
		plate:SetAttribute("ShopItemKey", entry.Key)
		if not addDecal(plate, Enum.NormalId.Top, "PlateTop", textures.PlateTop) then
			plate:SetAttribute("ShopTextureSlot", "PlateTop")
			local gui = addFace(plate, Enum.NormalId.Top, 340, 340)
			local hint = addText(gui, "PlateHint", "STEP TO\nINSPECT",
				UDim2.fromScale(0.08, 0.3), UDim2.fromScale(0.84, 0.4), PALETTE.neon, Enum.Font.Code)
			hint.TextTransparency = 0.15
		end
		makePart(stand, "ShopInspectPlateEdge",
			faceCF(PLATE_X, FLOOR_Y + 0.16, offset), Vector3.new(PLATE_HALF_Z * 2 + 0.24, 0.06, PLATE_HALF_X * 2 + 0.24),
			PALETTE.neon, Enum.Material.Neon, 0.35)

		table.insert(plates, {
			Key = entry.Key,
			Plate = plate.Position,
			Pedestal = column.Position,
		})
	end

	model:SetAttribute("ShopItemCount", count)

	-- ── focus ────────────────────────────────────────────────────────────────
	-- One server pass decides, for every player, which item they are looking at:
	-- the plate they are standing on, or the pedestal they last pressed INSPECT
	-- at while they stay near it. Derived every pass rather than latched on a
	-- Touched/TouchEnded pair, so a player who dies, teleports or is moved by
	-- anything else cannot leave a card stuck open behind them. FOCUS_POLL is
	-- the debounce; PLATE_HYSTERESIS keeps a player standing on an edge from
	-- flickering the card.
	-- Keyed by UserId, not by the Player: this loop outlives the players who
	-- leave during it and must not hold a departed one alive.
	local latched = {}

	local function plateUnder(position, current)
		for _, record in ipairs(plates) do
			local slack = record.Key == current and PLATE_HYSTERESIS or 0
			local delta = position - record.Plate
			if math.abs(delta.X) <= PLATE_HALF_X + slack
				and math.abs(delta.Z) <= PLATE_HALF_Z + slack then
				return record.Key
			end
		end
		return nil
	end

	local function pedestalPosition(key)
		for _, record in ipairs(plates) do
			if record.Key == key then return record.Pedestal end
		end
		return nil
	end

	local function focusFor(player)
		if player:GetAttribute("InRound") == true then return nil end
		local character = player.Character
		local root = character and character:FindFirstChild("HumanoidRootPart")
		if not root then return nil end
		local current = player:GetAttribute(FOCUS_ATTRIBUTE)
		local onPlate = plateUnder(root.Position, current)
		if onPlate then
			latched[player.UserId] = nil
			return onPlate
		end
		local key = latched[player.UserId]
		local pedestal = key and pedestalPosition(key)
		if pedestal and (root.Position - pedestal).Magnitude <= LATCH_RANGE then
			return key
		end
		latched[player.UserId] = nil
		return nil
	end

	for key, prompt in pairs(prompts) do
		prompt.Triggered:Connect(function(player)
			-- A second press on the same pedestal closes it again.
			latched[player.UserId] = latched[player.UserId] ~= key and key or nil
			player:SetAttribute(FOCUS_ATTRIBUTE, latched[player.UserId])
		end)
	end

	task.spawn(function()
		while model.Parent do
			for _, player in ipairs(Players:GetPlayers()) do
				local focus = focusFor(player)
				if player:GetAttribute(FOCUS_ATTRIBUTE) ~= focus then
					player:SetAttribute(FOCUS_ATTRIBUTE, focus)
				end
			end
			task.wait(FOCUS_POLL)
		end
		-- The lobby was torn down: nobody is standing in a shop that no longer
		-- exists, and a card left open would have nothing to close it.
		for _, player in ipairs(Players:GetPlayers()) do
			player:SetAttribute(FOCUS_ATTRIBUTE, nil)
		end
	end)

	return model
end

return LobbyShopDisplay
