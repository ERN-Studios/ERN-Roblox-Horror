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
-- Codex fills these in (artifacts/trello-20260916/texture-requests.md). An empty
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
		SpeedPotion = "rbxassetid://73457681182843",
		RouteMarker = "rbxassetid://100856675462356",
	},
	-- Requested 2026-09-16 for the enlarged frontage. Empty until Codex uploads;
	-- each one already has a lit, readable procedural stand-in below.
	CanopyFascia = "rbxassetid://104212668736693",
	NamePlate = "rbxassetid://87848253712756",
	RewardsPlaque = "rbxassetid://79807587818348",
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
	muted = Color3.fromRGB(150, 168, 164),
}

-- ── where it stands, and what the envelope is ───────────────────────────────
-- Every number below is measured against Builder.Build's own geometry and is
-- relative to the lobby centre. x grows toward the wall, z runs along it.
--
--   right LowerTunnelWall inner face ....... x = +32.9
--   right RaisedServiceLedge top ........... y = +0.65   (FLOOR_Y)
--   road surface / curb road-side face ..... y =  0.00, x = +16.4
--   Level 2 EntranceLintelWall ends ........ z = -69.5
--   ZyntraSupplyKiosk ShopFloorPad starts .. z = -44.75  (side wing at -44.91)
--
-- so z -68.2 .. -45.8 is the empty stretch and 22.4 studs is all there is.
--
-- THE HEIGHT CEILING IS NOT THE WALL. The tunnel's curved concrete shell is a
-- half-circle of outer radius 35 and thickness 2.2 about (x=0, y=+1), so its
-- INNER surface sits at radius 33.9; the reinforcement rib arches (radius-1.2
-- centres, 1.1 thick) put their inner surface at 33.25, and one of those arches
-- crosses this frontage at z = -52 (0.72 deep, z -52.36 .. -51.64).
--
-- Every corner of every part therefore has to satisfy
--     r(x, y) = sqrt(x^2 + (y - 1)^2) <= 33.90 - 0.20 = 33.70
-- and everything that crosses the rib band and stands proud of the wall also
--     r(x, y) <= 33.25 - 0.20 = 33.05.
--
-- That second rule is what decides how tall the sign can be, and it trades
-- height against depth. Solving 1 + sqrt(33.05^2 - x^2) for the sign's REAR
-- face x:
--     x = 31.62 (the 2026-09-15 sign) -> top y <= 10.62   <- the old ceiling
--     x = 30.60                       -> top y <= 13.49
--     x = 29.62 (this sign's glow)    -> top y <= 15.85
-- so the sign was moved 2.0 studs toward the road and grew from 14.40 x 3.60 to
-- 16.00 x 6.00 (1.85x the area) with its top at y = 15.49 instead of 10.60.
-- Measured clearances at the worst corner of each rib-crossing part:
--     ShopSignGlowPanel (29.62, 15.64) r = 33.045  ->  0.205 clear of the ribs
--     ShopSignFace      (29.50, 15.49) r = 32.868  ->  0.382
--     ShopCanopySoffit  (31.86,  9.34) r = 32.934  ->  0.316
-- and of the two parts that are flat wall dressing rather than proud of it:
--     ShopAlcoveBackdrop (32.56, 9.34) r = 33.612  ->  0.288 clear of the SHELL
--     ShopPilaster       (32.34, 9.34) r = 33.398  ->  0.502
-- The backdrop and the pilasters sit behind the rib line on purpose -- the rib
-- arch crosses in front of them at z = -52 and reads as structure, which is the
-- same acceptance the 2026-09-15 build made. Both were 34.23 and 33.99 then,
-- i.e. INSIDE the concrete shell; this build pulls them back out of it.
--
-- The main display plates stop at x = 25.78. The adjacent supply kiosk's
-- token-item plates stop at x = 22.6, leaving 4.8 studs between their neon edge
-- and the curb face at x = 17.8. The road keeps its full 33-stud width
-- (x -16.5 .. +16.5). These two bays use the existing kiosk shelves.
local AREA_Z = -57          -- centre of the frontage along the tunnel
local AREA_HALF = 11.2      -- so the deck spans z -68.2 .. -45.8
local FLOOR_Y = 0.65        -- top of the right service ledge
local DECK_TOP = 0.80       -- top of the shop's own deck plate
local BACK_X = 32.45        -- back panel centre, clear of the wall face at 32.9
local PEDESTAL_X = 30.40    -- pedestal centres; the cap's rear reaches 31.80
local PLATE_X = 27.38       -- the inspect plates, one pace in front of the row
local ITEM_SPACING = 3.15   -- 7 slots (6 items + the rewards plaque) in 22.4
local PLATE_HALF_X, PLATE_HALF_Z = 1.50, 1.43
local PLATE_HYSTERESIS = 0.6 -- the zone a player already inside has to leave
local LATCH_RANGE = 14       -- how far a prompt's focus survives being walked away from
local FOCUS_POLL = 0.2       -- seconds; also the debounce for a plate's edge
local FOCUS_ATTRIBUTE = "ZyntraShopFocus"
local MODEL_NAME = "ZyntraShopDisplay"
local REWARDS_PROMPT_NAME = "ZyntraShopPrompt"  -- the name ZyntraStore already binds
local REWARDS_PROMPT_FLAG = "ShopRewardsPrompt" -- how the client tells it apart

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

-- A tiling surface, for the one texture that repeats along the wall instead of
-- filling a face once. Studs per tile is stated in world units, so the image's
-- aspect and the part's aspect never have to agree.
local function addTexture(part, face, slot, id, studsU, studsV)
	local url = assetUrl(id)
	if not url then return nil end
	local texture = Instance.new("Texture")
	texture.Name = "ShopTexture"
	texture.Face = face
	texture.Texture = url
	texture.StudsPerTileU = studsU
	texture.StudsPerTileV = studsV
	texture.Parent = part
	part:SetAttribute("ShopTextureSlot", slot)
	return texture
end

-- A flat readable face on a part. CanvasSize is the ONLY lever on physical type
-- size once Roblox's 100 px font cap bites (see the leaderboard's comment in
-- TunnelLobbyBuilder), so every call below states its px-per-stud and keeps the
-- canvas aspect equal to the face's aspect -- a stretched canvas stretches the
-- letterforms with it.
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
	model:SetAttribute("ShopDisplayVersion", 2)
	model:SetAttribute("Placement", "Right service ledge between the Level 2 gate and the supply kiosk")
	model:SetAttribute("FocusAttribute", FOCUS_ATTRIBUTE)
	-- The envelope this build was solved against, so a Studio probe can check the
	-- geometry without reading the source.
	model:SetAttribute("ShellInnerRadius", 33.9)
	model:SetAttribute("RibInnerRadius", 33.25)
	model:SetAttribute("FrontmostX", 24.2 - PLATE_HALF_X - 0.10)
	model.Parent = lobbyModel

	-- Every part faces the road: the part's Front (-Z) points at the tunnel's
	-- centre line, so a size of (width, height, depth) means width ALONG the
	-- wall. The same convention the lobby's signal console uses.
	local function faceCF(x, y, z)
		local position = center + Vector3.new(x, y, AREA_Z + z)
		return CFrame.lookAt(position, center + Vector3.new(0, y, AREA_Z + z))
	end

	-- ── shell: deck, back panel, two pilasters ────────────────────────────────
	-- It reads as a recess cut into the wall because the frame stands proud of a
	-- dark back panel; the tunnel wall itself is never moved or removed.
	local deck = makePart(model, "ShopDeck",
		faceCF(29.30, (FLOOR_Y + DECK_TOP) * 0.5, 0), Vector3.new(AREA_HALF * 2, DECK_TOP - FLOOR_Y, 6.60),
		Color3.fromRGB(38, 46, 45), Enum.Material.DiamondPlate)
	deck:SetAttribute("ShopArea", true)

	-- 0.22 thick at x 32.34..32.56, top y 9.34: r = 33.612, inside the shell's
	-- 33.70 with 0.09 to spare. The 2026-09-15 panel reached y 10.45 at x 32.65,
	-- r = 33.99, which was 0.09 INSIDE the concrete.
	local backdrop = makePart(model, "ShopAlcoveBackdrop",
		faceCF(BACK_X, (DECK_TOP + 9.34) * 0.5, 0), Vector3.new(AREA_HALF * 2, 9.34 - DECK_TOP, 0.22),
		PALETTE.panel, Enum.Material.Metal)
	backdrop.Reflectance = 0.14
	if not addTexture(backdrop, Enum.NormalId.Front, "Backdrop", textures.Backdrop, 6, 6) then
		backdrop:SetAttribute("ShopTextureSlot", "Backdrop")
	end

	for _, side in ipairs({-1, 1}) do
		-- Blades on the backdrop rather than the 2026-09-15 full-depth columns:
		-- at 4.6 studs deep their rear corner measured r = 34.23, a third of a
		-- stud inside the shell, and they clipped the outer pedestal caps.
		makePart(model, "ShopPilaster",
			faceCF(32.12, (1.05 + 9.34) * 0.5, side * (AREA_HALF - 0.45)), Vector3.new(0.90, 9.34 - 1.05, 0.44),
			PALETTE.metal, Enum.Material.Metal)
		makePart(model, "ShopPilasterTrim",
			faceCF(28.26, (1.05 + 7.40) * 0.5, side * (AREA_HALF - 0.45)), Vector3.new(0.14, 7.40 - 1.05, 0.12),
			PALETTE.neon, Enum.Material.Neon, 0.05)
	end

	-- ── canopy: a lit fascia the walk reads, and the soffit it hangs from ─────
	-- The fascia's bottom edge is y 7.60 and the crates top out at 6.95 plus
	-- 0.35 of bob, so there is 0.30 of air under it at the top of the bob.
	local fascia = makePart(model, "ShopCanopyFascia",
		faceCF(28.42, 8.25, 0), Vector3.new(21.80, 1.30, 0.44),
		PALETTE.metal, Enum.Material.Metal)
	if not addTexture(fascia, Enum.NormalId.Front, "CanopyFascia", textures.CanopyFascia, 2.60, 1.30) then
		fascia:SetAttribute("ShopTextureSlot", "CanopyFascia")
	end
	do
		-- 21.80 x 1.30 studs of face at 436 x 26 canvas = 20.0 px/stud, so the
		-- 22 px band of type is 1.10 studs tall in the world -- three times the
		-- 2026-09-15 pedestal caption, and the widest single line the shop has.
		local gui = addFace(fascia, Enum.NormalId.Front, 436, 26)
		addText(gui, "CanopyWord", "ZYNTRA  //  SUPPLY", UDim2.fromOffset(8, 2),
			UDim2.fromOffset(420, 22), PALETTE.amber, Enum.Font.Code)
	end
	local fasciaLight = Instance.new("SurfaceLight")
	fasciaLight.Name = "ShopCanopyLight"
	fasciaLight.Face = Enum.NormalId.Front
	fasciaLight.Color = PALETTE.amber
	fasciaLight.Brightness = 1.0
	fasciaLight.Range = 14
	fasciaLight.Angle = 120
	fasciaLight.Shadows = false
	fasciaLight.Parent = fascia

	-- 3.66 deep, stopping at x 31.86: at y 9.34 the rib arch is already inside
	-- x 31.91, and a deeper soffit would be buried in it at z = -52.
	makePart(model, "ShopCanopySoffit",
		faceCF(30.03, 9.12, 0), Vector3.new(21.80, 0.44, 3.66),
		PALETTE.metal, Enum.Material.Metal)

	-- Three floods instead of two, tucked into the soffit's underside. Brighter
	-- and wider than the 2026-09-15 pair, and still nothing that moves.
	for _, offset in ipairs({-6.3, 0, 6.3}) do
		local flood = makePart(model, "ShopFloodHousing",
			faceCF(30.20, 8.75, offset), Vector3.new(1.00, 0.30, 1.60),
			PALETTE.metalLight, Enum.Material.Metal)
		local light = Instance.new("SpotLight")
		light.Name = "ShopFloodLight"
		light.Face = Enum.NormalId.Bottom
		light.Color = Color3.fromRGB(226, 245, 240)
		light.Brightness = 1.8
		light.Range = 16
		light.Angle = 95
		light.Shadows = false
		light.Parent = flood
	end

	-- ── the sign ──────────────────────────────────────────────────────────────
	-- Face and glow are both 8:3 and concentric (centre y 12.49, z = AREA_Z), so
	-- shop-sign-face.png and shop-sign-glow.png put their glyphs in the same
	-- place; the glow spills 0.40 studs past the face along the wall and 0.15
	-- above and below it. The glow sits BEHIND the face, which is the 2026-09-15
	-- native correction -- in front of it, it washed out the lettering.
	local signGlow = makePart(model, "ShopSignGlowPanel",
		faceCF(29.56, 12.49, 0), Vector3.new(16.80, 6.30, 0.12),
		PALETTE.neon, Enum.Material.Neon, 0.62)
	signGlow:SetAttribute("ShopSignGlow", true)
	if not addDecal(signGlow, Enum.NormalId.Front, "SignGlow", textures.SignGlow) then
		signGlow:SetAttribute("ShopTextureSlot", "SignGlow")
	end

	local sign = makePart(model, "ShopSignFace",
		faceCF(29.28, 12.49, 0), Vector3.new(16.00, 6.00, 0.44),
		PALETTE.black, Enum.Material.Metal)
	if not addDecal(sign, Enum.NormalId.Front, "SignFace", textures.SignFace) then
		sign:SetAttribute("ShopTextureSlot", "SignFace")
		-- Procedural stand-in for shop-sign-face.png: the word, in the brand's
		-- own neon, on the sign's own housing. 16.00 x 6.00 studs at 512 x 192
		-- canvas = 32 px/stud, and 8:3 so the canvas matches the face exactly.
		local gui = addFace(sign, Enum.NormalId.Front, 512, 192)
		local title = addText(gui, "SignWord", "SHOP", UDim2.fromOffset(20, 14),
			UDim2.fromOffset(472, 124), PALETTE.neon, Enum.Font.GothamBlack)
		title.TextStrokeTransparency = 0.55
		addText(gui, "SignLine", "ZYNTRA // SUPPLY", UDim2.fromOffset(20, 146),
			UDim2.fromOffset(472, 32), PALETTE.amber, Enum.Font.Code)
	end
	for _, side in ipairs({-1, 1}) do
		makePart(model, "ShopSignTrim",
			faceCF(29.28, 12.49 + side * 3.00, 0), Vector3.new(16.00, 0.18, 0.48),
			side < 0 and PALETTE.amber or PALETTE.neon, Enum.Material.Neon, 0.05)
	end

	local signLight = Instance.new("SurfaceLight")
	signLight.Name = "ShopSignLight"
	signLight.Face = Enum.NormalId.Front
	signLight.Color = PALETTE.neon
	signLight.Brightness = 1.6
	signLight.Range = 22
	signLight.Angle = 110
	signLight.Shadows = false
	signLight.Parent = sign

	-- ── one pedestal, crate, nameplate and plate per catalogue item ───────────
	-- Seven slots across the 22.4 studs: six items and the DAILY REWARDS plaque
	-- at the kiosk end. At 3.15 studs the widest part of a slot (the plate's
	-- neon edge, 3.06) leaves 0.09 between slots and 0.22 at each end of the
	-- frontage. The 2026-09-15 row used 3.70 for six slots and had no room for a
	-- seventh; nothing on the wall can be spaced wider and still fit the plaque.
	local items = catalogue()
	local count = #items
	local slots = count + 1
	local function slotOffset(index)
		return (index - (slots + 1) * 0.5) * ITEM_SPACING
	end
	local plates = {}
	local prompts = {}
	for index, entry in ipairs(items) do
		local offset = slotOffset(index)
		local accent = entry.Key == "EmergencyReentry" and PALETTE.red
			or (entry.Kind == "Pass" and PALETTE.neon or PALETTE.gold)

		local stand = Instance.new("Model")
		stand.Name = "ShopStand_" .. entry.Key
		stand:SetAttribute("ShopItemKey", entry.Key)
		stand:SetAttribute("ShopItemKind", entry.Kind)
		stand.Parent = model

		-- 3.20 tall instead of 2.60, and the row no longer bows toward the road:
		-- the 2026-09-15 arc pushed the middle columns 0.85 studs forward, where
		-- their front face cut 0.25 studs into their own inspect plate.
		local column = makePart(stand, "ShopPedestal",
			faceCF(PEDESTAL_X, (DECK_TOP + 4.00) * 0.5, offset), Vector3.new(2.70, 4.00 - DECK_TOP, 2.40),
			PALETTE.metal, Enum.Material.Metal)
		column.CanCollide = true
		column:SetAttribute("ShopItemKey", entry.Key)

		local cap = makePart(stand, "ShopPedestalCap",
			faceCF(PEDESTAL_X, 4.16, offset), Vector3.new(2.86, 0.32, 2.80),
			PALETTE.black, Enum.Material.Metal)
		cap:SetAttribute("ShopItemKey", entry.Key)
		if not addDecal(cap, Enum.NormalId.Top, "PedestalTop", textures.PedestalTop) then
			cap:SetAttribute("ShopTextureSlot", "PedestalTop")
			makePart(stand, "ShopPedestalRing",
				faceCF(PEDESTAL_X, 4.35, offset), Vector3.new(2.10, 0.06, 2.10),
				accent, Enum.Material.Neon, 0.1)
		end

		-- The nameplate is its own 2.86 x 1.43 plaque on the column's front, not
		-- a caption on the 2.20-stud column face it used to share with the kind
		-- line. Physical type size is set by the plaque's WIDTH divided by the
		-- characters on a line, not by the canvas: 2.86 studs over ten characters
		-- is 0.52 studs of glyph height against 0.39 before, and the canvas is
		-- 144 x 72 = 50.35 px/stud on a 2:1 face so nothing is stretched.
		local plaque = makePart(stand, "ShopNamePlate",
			faceCF(PEDESTAL_X - 1.26, 3.20, offset), Vector3.new(2.86, 1.43, 0.12),
			PALETTE.panel, Enum.Material.Metal)
		plaque:SetAttribute("ShopItemKey", entry.Key)
		if not addDecal(plaque, Enum.NormalId.Front, "NamePlate", textures.NamePlate) then
			plaque:SetAttribute("ShopTextureSlot", "NamePlate")
		end
		local plaqueGui = addFace(plaque, Enum.NormalId.Front, 144, 72)
		-- Price-free by contract: the eyebrow says what KIND of thing this is and
		-- the card says what it costs, because the price is live and this is not.
		addText(plaqueGui, "ItemKind", entry.Kind == "Pass" and "PASS" or "PRODUCT",
			UDim2.fromOffset(8, 4), UDim2.fromOffset(128, 16), accent, Enum.Font.Code)
		addText(plaqueGui, "ItemName", tostring(entry.Item.Name or entry.Key),
			UDim2.fromOffset(6, 22), UDim2.fromOffset(132, 44), PALETTE.text)

		-- The hovering representation. The client bobs and turns it from this
		-- pose; the server never moves it, so nothing here replicates per frame.
		local box = makePart(stand, "ShopItemBox",
			faceCF(PEDESTAL_X, 5.85, offset), Vector3.new(2.20, 2.20, 2.20),
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

		addPointLight(box, "ShopBoxGlow", accent, 0.9, 9)

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
			faceCF(PLATE_X, DECK_TOP + 0.06, offset), Vector3.new(PLATE_HALF_Z * 2, 0.12, PLATE_HALF_X * 2),
			PALETTE.metalLight, Enum.Material.DiamondPlate)
		plate:SetAttribute("ShopItemKey", entry.Key)
		if not addDecal(plate, Enum.NormalId.Top, "PlateTop", textures.PlateTop) then
			plate:SetAttribute("ShopTextureSlot", "PlateTop")
			local gui = addFace(plate, Enum.NormalId.Top, 286, 300)
			local hint = addText(gui, "PlateHint", "STEP TO\nINSPECT",
				UDim2.fromOffset(24, 90), UDim2.fromOffset(238, 120), PALETTE.neon, Enum.Font.Code)
			hint.TextTransparency = 0.15
		end
		makePart(stand, "ShopInspectPlateEdge",
			faceCF(PLATE_X, DECK_TOP + 0.01, offset), Vector3.new(PLATE_HALF_Z * 2 + 0.20, 0.06, PLATE_HALF_X * 2 + 0.20),
			PALETTE.neon, Enum.Material.Neon, 0.35)

		table.insert(plates, {
			Key = entry.Key,
			Plate = plate.Position,
			Pedestal = column.Position,
		})
	end

	-- Token supplies occupy the existing kiosk's first two merchandise bays.
	-- The counter stays solid; inspect plates sit in front of it. This keeps
	-- the larger frontage readable without squeezing nine stands into one row.
	for _, bay in ipairs({{Key = "SpeedPotion", Offset = 16.3}, {Key = "RouteMarker", Offset = 22}}) do
		local item = Config.Items and Config.Items[bay.Key]
		if item then
			local stand = Instance.new("Model")
			stand.Name = "ShopStand_" .. bay.Key
			stand:SetAttribute("ShopItemKey", bay.Key)
			stand:SetAttribute("ShopItemKind", "Item")
			stand:SetAttribute("ShopSupplyBay", true)
			stand.Parent = model
			local box = makePart(stand, "ShopItemBox", faceCF(30.75, 6.0, bay.Offset),
				Vector3.new(2.2, 2.2, 2.2), PALETTE.panel, Enum.Material.Metal)
			box:SetAttribute("ShopItemKey", bay.Key)
			box:SetAttribute("ShopBobOrigin", box.CFrame)
			for _, face in ipairs({Enum.NormalId.Front, Enum.NormalId.Back, Enum.NormalId.Left, Enum.NormalId.Right}) do
				addDecal(box, face, "Box:" .. bay.Key, textures.Box and textures.Box[bay.Key] or item.IconId)
			end
			addPointLight(box, "ShopBoxGlow", PALETTE.gold, 0.6, 7)
			local prompt = Instance.new("ProximityPrompt")
			prompt.Name = "ShopInspectPrompt"
			prompt.ActionText = "INSPECT"
			prompt.ObjectText = item.Name
			prompt.KeyboardKeyCode = Enum.KeyCode.E
			prompt.GamepadKeyCode = Enum.KeyCode.ButtonX
			prompt.HoldDuration = 0
			prompt.MaxActivationDistance = 10
			prompt.RequiresLineOfSight = false
			prompt.Parent = box
			prompts[bay.Key] = prompt
			local plate = makePart(stand, "ShopInspectPlate", faceCF(24.2, FLOOR_Y + 0.06, bay.Offset),
				Vector3.new(PLATE_HALF_Z * 2, 0.12, PLATE_HALF_X * 2), PALETTE.metalLight, Enum.Material.DiamondPlate)
			plate:SetAttribute("ShopItemKey", bay.Key)
			addDecal(plate, Enum.NormalId.Top, "PlateTop", textures.PlateTop)
			makePart(stand, "ShopInspectPlateEdge", faceCF(24.2, FLOOR_Y + 0.01, bay.Offset),
				Vector3.new(PLATE_HALF_Z * 2 + 0.2, 0.06, PLATE_HALF_X * 2 + 0.2), PALETTE.gold, Enum.Material.Neon, 0.35)
			table.insert(plates, {Key = bay.Key, Plate = plate.Position, Pedestal = box.Position})
			count += 1
		end
	end
	model:SetAttribute("ShopItemCount", count)

	-- ── the seventh slot: DAILY REWARDS ──────────────────────────────────────
	-- A reach-in, not a shop item: it has no inspect plate, it never publishes
	-- ZyntraShopFocus, and it grants NOTHING. Its prompt opens the Zyntra
	-- terminal. The prompt keeps the name ZyntraStore has always bound
	-- (ZyntraShopPrompt), so if the Rewards tab is not in this build the
	-- terminal still opens on Shop; Shop Display Client recognises it by the
	-- ShopRewardsPrompt attribute and asks for the Rewards tab on top of that.
	do
		local offset = slotOffset(slots)
		local stand = Instance.new("Model")
		stand.Name = "ShopStand_DailyRewards"
		stand:SetAttribute("ShopRewardsStand", true)
		stand.Parent = model

		local plinth = makePart(stand, "ShopRewardsPlinth",
			faceCF(PEDESTAL_X, (DECK_TOP + 2.60) * 0.5, offset), Vector3.new(2.70, 2.60 - DECK_TOP, 2.40),
			PALETTE.metal, Enum.Material.Metal)
		plinth.CanCollide = true

		makePart(stand, "ShopRewardsFrame",
			faceCF(30.61, 4.50, offset), Vector3.new(3.00, 3.80, 0.12),
			PALETTE.gold, Enum.Material.Neon, 0.15)

		local plaque = makePart(stand, "DailyRewardsPlaque",
			faceCF(30.40, 4.50, offset), Vector3.new(2.80, 3.50, 0.30),
			PALETTE.black, Enum.Material.Metal)
		plaque:SetAttribute("ShopRewardsPlaque", true)
		if not addDecal(plaque, Enum.NormalId.Front, "RewardsPlaque", textures.RewardsPlaque) then
			plaque:SetAttribute("ShopTextureSlot", "RewardsPlaque")
		end
		-- 2.80 x 3.50 studs of face at 112 x 140 canvas = 40 px/stud on a 4:5
		-- canvas that matches the face, so the two 28 px words are 0.70 studs
		-- tall in the world -- larger than any other lettering below the sign.
		local gui = addFace(plaque, Enum.NormalId.Front, 112, 140)
		addText(gui, "RewardsTitle", "DAILY", UDim2.fromOffset(6, 18),
			UDim2.fromOffset(100, 28), PALETTE.gold, Enum.Font.GothamBlack)
		addText(gui, "RewardsTitle2", "REWARDS", UDim2.fromOffset(6, 46),
			UDim2.fromOffset(100, 28), PALETTE.gold, Enum.Font.GothamBlack)
		addText(gui, "RewardsLine", "FREE DAILY SPIN", UDim2.fromOffset(6, 80),
			UDim2.fromOffset(100, 14), PALETTE.text, Enum.Font.Code)
		addText(gui, "RewardsFoot", "ZYNTRA TERMINAL", UDim2.fromOffset(6, 106),
			UDim2.fromOffset(100, 16), PALETTE.muted, Enum.Font.Code)
		addPointLight(plaque, "ShopRewardsGlow", PALETTE.gold, 0.9, 10)

		local prompt = Instance.new("ProximityPrompt")
		prompt.Name = REWARDS_PROMPT_NAME
		prompt.ActionText = "DAILY REWARDS"
		prompt.ObjectText = "Zyntra Terminal"
		prompt.KeyboardKeyCode = Enum.KeyCode.E
		prompt.GamepadKeyCode = Enum.KeyCode.ButtonX
		prompt.HoldDuration = 0
		prompt.MaxActivationDistance = 9
		prompt.RequiresLineOfSight = false
		prompt:SetAttribute(REWARDS_PROMPT_FLAG, true)
		prompt.Parent = plaque
	end

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
