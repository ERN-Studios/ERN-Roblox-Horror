-- LobbyShopDisplay
-- The lobby SHOP: eight floating product holograms strung along the RIGHT
-- tunnel wall between the Level 2 gate and the Level 4 gate, each with an
-- INVISIBLE pressure plate on the ledge under it that opens that item's detail
-- card for whoever walks up to it.
--
-- v4 (2026-09-16) is a DELETION, not an addition. v3 was a 22-stud alcove --
-- deck, backdrop, pilasters, canopy, an overhead SHOP sign, nameplates,
-- projector discs, beams and a DAILY REWARDS plaque -- standing right next to
-- TunnelLobbyBuilder's ZyntraSupplyKiosk, which was a SECOND shop with its own
-- sign, fascia, counter, shopkeeper and terminal prompt. Two shops, 12 studs
-- apart, both saying SHOP. The owner's brief was one shop and no shopfront, so
-- the furniture is gone on both sides and what is left is the merchandise: one
-- box per product, wearing the product art on all six faces, floating over a
-- walkway that is now clear from gate to gate.
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
-- One uploaded product image per catalogue key, and one shared fallback. Bare
-- numeric ids and full rbxassetid:// urls are both accepted; anything else is
-- ignored rather than rendered as a broken surface.
--
-- SignFace, SignGlow, Backdrop, CanopyFascia, NamePlate and RewardsPlaque went
-- with the parts they dressed (v4). Their ids are recorded in
-- assets/shop/README.md rather than kept as config for surfaces that no longer
-- exist. PedestalTop and PlateTop were retired the same way in v3.
local SHOP_TEXTURES = {
	BoxFallback = "rbxassetid://90558430724311",
	Box = {
		Supporter = "rbxassetid://75534988741783",
		AdvancedEquipment = "rbxassetid://133698774797678",
		CosmeticEquipment = "rbxassetid://95744112613263",
		Tokens4 = "rbxassetid://127956354478910",
		Tokens20 = "rbxassetid://114348157561307",
		EmergencyReentry = "rbxassetid://93091494402773",
		SpeedPotion = "rbxassetid://73457681182843",
		RouteMarker = "rbxassetid://100856675462356",
	},
}

-- ── palette ─────────────────────────────────────────────────────────────────
-- The lobby's own Zyntra values (TunnelLobbyBuilder.COLORS) and the terminal's
-- (ZyntraStore.COLORS), restated because both are file-locals. Keep them equal
-- to their sources: a box on the wall and the card it opens have to look like
-- the same brand.
local PALETTE = {
	neon = Color3.fromRGB(73, 245, 204),
	gold = Color3.fromRGB(255, 203, 79),
	red = Color3.fromRGB(244, 95, 82),
}

-- ── where it stands, and what the envelope is ───────────────────────────────
-- Measured in the running place on 2026-09-16 (Server datamodel). Every number
-- is RELATIVE to the builder's lobby centre, which is (0, 30, -760) absolute;
-- x grows toward the right wall, z runs along the tunnel.
--
--   right LowerTunnelWall inner face ....... x = 32.9  (wall centre 34.0, 2.2 thick)
--   RaisedServiceLedge ..................... x 16.8 .. 33.2, top y = 0.65,
--                                            z -140 .. +140; road edge x 22.8
--   Level 2 gate (abs z -840) .............. posts abs -849.8 / -830.2, 1.5 thick,
--                                            so the post edge facing the shop
--                                            wall is abs -829.45 = rel -69.45
--   Level 4 gate (abs z -760, sealed) ...... posts abs -769.8 / -750.2, so the
--                                            post edge facing the shop wall is
--                                            abs -770.55 = rel -10.55
--
-- 58.9 studs of usable wall, rel z -69.45 .. -10.55. The row keeps 3.45 studs
-- between an end box's CENTRE and the post edge next to it (1.75 from the box
-- face), so both gate openings and the ledge in front of them stay walkable:
-- box centres run z -66.0 .. -14.0 and the eight of them sit 52/7 = 7.43 apart.
-- A 3.40 box therefore has ~4.03 studs of air on each side; v3's row had 0.15.
--
-- THE HEIGHT CEILING IS NOT THE WALL. The tunnel's curved concrete shell is a
-- half-circle of outer radius 35 and thickness 2.2 about (x = 0, y = +1), so its
-- INNER surface sits at radius 33.9; the reinforcement rib arches put their
-- inner surface at 33.25, and one of those arches crosses this stretch at
-- z -52.36 .. -51.64 -- which slot i = 2 (centre z -51.14) reaches into.
--
-- Every corner of every part therefore has to satisfy
--     r(x, y) = sqrt(x^2 + (y - 1)^2) <= 33.90 - 0.20 = 33.70
-- and anything crossing the rib band also
--     r(x, y) <= 33.25 - 0.20 = 33.05.
--
-- The worst corner in the whole build is a box's rear top:
--     resting  (31.90, 8.70) -> r = sqrt(31.90^2 + 7.70^2) = 32.816
--     top of the client's 0.35 bob (31.90, 9.05) -> r = 32.900
-- which clears the rib limit by 0.150 even at the peak of the bob, so the same
-- row can be built at every slot instead of ducking under the arch at one.
--
-- The boxes hang at y 5.30 .. 8.70, i.e. 4.65 studs of headroom over the ledge
-- top at 0.65: a player walks UNDER the merchandise, which is what lets the row
-- span the whole wall without narrowing the walkway. Nothing in this module is
-- collidable or query-able, so there is nothing to walk into either way.
local Z_FIRST = -66.0       -- centre of the first box, 3.45 clear of the Level 2 post edge
local Z_LAST = -14.0        -- centre of the last box, 3.45 clear of the Level 4 post edge
local FLOOR_Y = 0.65        -- top of the right service ledge
local BOX_SIZE = 3.40       -- was 3.00 in v3; the brief asked for bigger boxes
local BOX_X = 30.20         -- rear face reaches 31.90
local BOX_Y = 7.00          -- bottom 5.30, top 8.70 (9.05 at the top of the client's bob)
local PLATE_X = 27.78
local PLATE_HALF_X, PLATE_HALF_Z = 1.60, 1.70 -- 3.20 deep x 3.40 along the wall
local PLATE_HYSTERESIS = 0.6 -- the zone a player already inside has to leave
local FOCUS_POLL = 0.2       -- seconds; also the debounce for a plate's edge
local HOLOGRAM_TRANSPARENCY = 0.35
local FOCUS_ATTRIBUTE = "ZyntraShopFocus"
local MODEL_NAME = "ZyntraShopDisplay"

-- All six, because the brief asks for product art on every face of the box.
local BOX_FACES = {
	Enum.NormalId.Front, Enum.NormalId.Back,
	Enum.NormalId.Left, Enum.NormalId.Right,
	Enum.NormalId.Top, Enum.NormalId.Bottom,
}

-- The terminal's Shop tab order, so the wall reads gate to gate the way the
-- card list reads top to bottom: the six Robux items first, then the two token
-- items, which are ordinary wall boxes now that the kiosk bays are gone.
-- Anything in the catalogue that is NOT named here still gets a hologram (see
-- `catalogue`), with the fallback art.
local DISPLAY_ORDER = {
	{Key = "Supporter", Kind = "Pass"},
	{Key = "AdvancedEquipment", Kind = "Pass"},
	{Key = "Tokens4", Kind = "Product"},
	{Key = "Tokens20", Kind = "Product"},
	{Key = "EmergencyReentry", Kind = "Product"},
	{Key = "CosmeticEquipment", Kind = "Pass"},
	{Key = "SpeedPotion", Kind = "Item"},
	{Key = "RouteMarker", Kind = "Item"},
}

local SOURCES = {
	{Kind = "Pass", Table = Config.Passes},
	{Kind = "Product", Table = Config.Products},
	{Kind = "Item", Table = Config.Items},
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
	part.CanQuery = false
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

local function addDecal(part, face, url)
	local decal = Instance.new("Decal")
	decal.Name = "ShopTexture"
	decal.Face = face
	decal.Texture = url
	-- Stated rather than left to the default: a Decal inherits nothing from its
	-- part, and the hologram boxes it goes on are 0.35 transparent on purpose.
	-- The product art is the one thing on them that has to stay solid.
	decal.Transparency = 0
	decal.Parent = part
	return decal
end

local function addPointLight(parent, name, color, brightness, range)
	local light = Instance.new("PointLight")
	light.Name = name
	light.Color = color
	light.Brightness = brightness
	light.Range = range
	light.Shadows = false
	light.Parent = parent
	return light
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
	model:SetAttribute("ShopDisplayVersion", 4)
	model:SetAttribute("Placement", "Right wall between the Level 2 and Level 4 gates")
	model:SetAttribute("FocusAttribute", FOCUS_ATTRIBUTE)
	-- The envelope this build was solved against, so a Studio probe can check the
	-- geometry without reading the source.
	model:SetAttribute("ShellInnerRadius", 33.9)
	model:SetAttribute("RibInnerRadius", 33.25)
	model:SetAttribute("FrontmostX", PLATE_X - PLATE_HALF_X)
	model.Parent = lobbyModel

	-- Every part faces the road: the part's Front (-Z) points at the tunnel's
	-- centre line, so a size of (width, height, depth) means width ALONG the
	-- wall. The same convention the lobby's signal console uses. z is relative to
	-- the lobby centre, which is the frame every measurement above is in.
	local function faceCF(x, y, z)
		local position = center + Vector3.new(x, y, z)
		return CFrame.lookAt(position, center + Vector3.new(0, y, z))
	end

	-- ── one hologram box ──────────────────────────────────────────────────────
	-- Translucent, lit at the edge, and wearing the product art on ALL SIX faces
	-- so it reads as that product from anywhere on the road rather than only from
	-- square in front of it. Non-collidable, non-query and non-touch: the box
	-- hangs over the walkway and must be invisible to every raycast, prompt and
	-- Touched handler in the game. The focus pass below is the only thing that
	-- knows where it is, and it works off the plate, not the box.
	local function addBox(stand, key, accent, z, phase, textureId, item)
		local box = makePart(stand, "ShopHologramBox",
			faceCF(BOX_X, BOX_Y, z), Vector3.new(BOX_SIZE, BOX_SIZE, BOX_SIZE),
			accent, Enum.Material.ForceField, HOLOGRAM_TRANSPARENCY)
		box:SetAttribute("ShopItemKey", key)
		box:SetAttribute("ShopBobOrigin", box.CFrame)
		box:SetAttribute("ShopBobPhase", phase)

		-- ONE id for all six faces, resolved once: the product's own art, then
		-- the shared fallback texture, then the catalogue icon the terminal
		-- already draws. Every shipped key has art at the first rung; the other
		-- two exist so a product added to ZyntraConfig without a SHOP_TEXTURES
		-- entry is never a blank box.
		local url = assetUrl(textureId) or assetUrl(textures.BoxFallback)
			or assetUrl(item and item.IconId)
		if url then
			box:SetAttribute("ShopTextureSlot", "Box:" .. key)
			for _, face in ipairs(BOX_FACES) do
				addDecal(box, face, url)
			end
		else
			warn("[LobbyShopDisplay] no product art for " .. tostring(key))
		end

		-- Owner, 2026-09-17: a very short caption OVER each box saying what it is
		-- -- the product's own name and nothing more. A BillboardGui sized in
		-- studs, so it reads the same from anywhere on the road, rides the bob
		-- with the box it is adorned to, and draws in the box's accent so it
		-- reads as part of the hologram rather than a sign hung over it.
		local caption = Instance.new("BillboardGui")
		caption.Name = "ShopHologramCaption"
		caption.Adornee = box
		caption.Size = UDim2.fromScale(7, 0.9)
		caption.StudsOffset = Vector3.new(0, BOX_SIZE * 0.5 + 0.75, 0)
		caption.MaxDistance = 90
		caption.AlwaysOnTop = false
		caption.LightInfluence = 0
		caption.ResetOnSpawn = false
		caption.Parent = box
		local captionText = Instance.new("TextLabel")
		captionText.Name = "ShopHologramName"
		captionText.BackgroundTransparency = 1
		captionText.BorderSizePixel = 0
		captionText.Size = UDim2.fromScale(1, 1)
		captionText.Font = Enum.Font.GothamBlack
		captionText.TextScaled = true
		captionText.TextColor3 = accent
		captionText.TextTransparency = 0.05
		captionText.Text = string.upper(tostring((item and item.Name) or key))
		captionText.Parent = caption
		local captionStroke = Instance.new("UIStroke")
		captionStroke.Color = Color3.fromRGB(8, 14, 12)
		captionStroke.Thickness = 1.5
		captionStroke.Transparency = 0.3
		captionStroke.Parent = captionText

		local edge = Instance.new("SelectionBox")
		edge.Name = "ShopBoxEdge"
		edge.Adornee = box
		edge.Color3 = accent
		edge.LineThickness = 0.05
		edge.Transparency = 0.2
		edge.Parent = box
		addPointLight(box, "ShopBoxGlow", accent, 1.1, 11)
		return box
	end

	-- ── one pressure plate ────────────────────────────────────────────────────
	-- INVISIBLE by contract (#105): the player sees the hologram, not the floor
	-- it is keyed to. Non-query and non-touch as well as non-collidable, so no
	-- raycast, prompt or Touched handler anywhere in the game can see it either;
	-- the focus pass below is the only thing that knows it is there.
	local function addPlate(stand, key, z)
		local plate = makePart(stand, "ShopPressurePlate",
			faceCF(PLATE_X, FLOOR_Y + 0.06, z),
			Vector3.new(PLATE_HALF_Z * 2, 0.12, PLATE_HALF_X * 2),
			PALETTE.neon, Enum.Material.SmoothPlastic, 1)
		plate:SetAttribute("ShopItemKey", key)
		return plate
	end

	-- ── one box and one plate per catalogue item, evenly along the wall ───────
	-- Eight slots over 52 studs is a 7.43 pitch, so two plate zones are 4.03
	-- studs apart edge to edge -- wider than PLATE_HYSTERESIS can reach, which
	-- is what stops a player walking the row from switching product by accident.
	local items = catalogue()
	local count = #items
	local pitch = count > 1 and (Z_LAST - Z_FIRST) / (count - 1) or 0
	local plates = {}
	for index, entry in ipairs(items) do
		local slot = index - 1
		local z = Z_FIRST + pitch * slot
		local accent = entry.Key == "EmergencyReentry" and PALETTE.red
			or (entry.Kind == "Pass" and PALETTE.neon or PALETTE.gold)

		local stand = Instance.new("Model")
		stand.Name = "ShopStand_" .. entry.Key
		stand:SetAttribute("ShopItemKey", entry.Key)
		stand:SetAttribute("ShopItemKind", entry.Kind)
		stand.Parent = model

		-- Phases spread over one full cycle, so the row never pumps in unison.
		addBox(stand, entry.Key, accent, z, slot * (math.pi * 2 / count),
			textures.Box and textures.Box[entry.Key], entry.Item)
		local plate = addPlate(stand, entry.Key, z)
		table.insert(plates, {Key = entry.Key, Plate = plate.Position})
	end
	model:SetAttribute("ShopItemCount", count)

	-- ── focus ────────────────────────────────────────────────────────────────
	-- One server pass decides, for every player, which item they are standing in
	-- front of. Derived from the player's position every pass rather than
	-- latched on a Touched/TouchEnded pair, so a player who dies, teleports or
	-- is moved by anything else cannot leave a card stuck open behind them, and
	-- so there is no state to get out of step with where they actually are.
	--
	-- The three behaviours #105 asks for all fall out of this one pass:
	--   DEBOUNCE ....... FOCUS_POLL. A zone edge can only change the answer five
	--                    times a second, and the attribute is written only when
	--                    the answer CHANGES, so standing still writes nothing.
	--   SWITCHING ...... stepping into the next zone returns the next key.
	--   LEAVING ........ no zone means nil, which closes the card. There is no
	--                    timer and nothing to expire, so there is no state in
	--                    which walking away can reopen anything.
	local function plateUnder(position, current)
		-- The zone the player already holds is tested FIRST, so its hysteresis
		-- always beats a neighbour's raw zone. With a 7.43 pitch the zones no
		-- longer touch at all, but the order still decides the answer inside the
		-- slack, and an order that depends on how the row was built is a bug
		-- waiting for the next reshuffle of DISPLAY_ORDER.
		for _, record in ipairs(plates) do
			if record.Key == current then
				local delta = position - record.Plate
				if math.abs(delta.X) <= PLATE_HALF_X + PLATE_HYSTERESIS
					and math.abs(delta.Z) <= PLATE_HALF_Z + PLATE_HYSTERESIS then
					return current
				end
				break
			end
		end
		for _, record in ipairs(plates) do
			local delta = position - record.Plate
			if math.abs(delta.X) <= PLATE_HALF_X and math.abs(delta.Z) <= PLATE_HALF_Z then
				return record.Key
			end
		end
		return nil
	end

	local function focusFor(player)
		if player:GetAttribute("InRound") == true then return nil end
		local character = player.Character
		local root = character and character:FindFirstChild("HumanoidRootPart")
		if not root then return nil end
		return plateUnder(root.Position, player:GetAttribute(FOCUS_ATTRIBUTE))
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
