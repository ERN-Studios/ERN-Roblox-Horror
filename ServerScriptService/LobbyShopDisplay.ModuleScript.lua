-- LobbyShopDisplay
-- The Zyntra SHOP frontage in the transit lobby: a recessed shop built into the
-- RIGHT service ledge between the Level 2 gate and the supply kiosk. Every
-- catalogue item is a HOLOGRAM -- a translucent product box floating in the
-- beam of a projector disc on the deck -- with an INVISIBLE pressure plate on
-- the floor in front of it that opens that item's detail card for whoever is
-- standing there.
--
-- There is no pedestal to walk into and no prompt to press (Trello #105):
-- walking up IS the interaction, the row is walk-through from the curb to the
-- wall, and the only prompt left on the frontage is the DAILY REWARDS plaque's.
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
-- PedestalTop (101891958398163) and PlateTop (131434121223604) were retired
-- with the pedestal cap and the visible floor plate; both surfaces are gone,
-- so the ids are recorded in assets/shop/README.md rather than kept as config
-- for parts that no longer exist.
local SHOP_TEXTURES = {
	SignFace = "rbxassetid://126032557889771",
	SignGlow = "rbxassetid://92494312014031",
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
-- The main display plates stop at x = 26.08 and the kiosk's at x = 22.80, both
-- east of the 25.78 / 22.6 limits the 2026-09-16 frontage left behind, so the
-- walk lane and the curb face at x = 17.8 are untouched. The road keeps its
-- full 33-stud width (x -16.5 .. +16.5).
--
-- THE HOLOGRAM'S CEILING IS A SIGHTLINE, NOT A COLLISION. The boxes stand at
-- x 28.90 .. 31.90, which is BEHIND the canopy fascia (x 28.20 .. 28.64), so
-- the thing they could actually hit is the soffit at y 8.90 -- 1.50 studs of
-- headroom above where they are. What rules the row is what the fascia HIDES:
-- from the far lane of the road, eye at about (x 16, y 4.5), the line that
-- grazes the fascia's inner bottom corner (28.64, 7.60) has reached y 7.66 by
-- the time it is over the front face of a box, and 8.40 by its rear face.
-- Anything higher has its front corner cut off by the fascia for every player
-- who has not walked up to it yet.
--
-- That is what rejects the obvious "one row low, one row high" pair at
-- y 4.6 / 6.4: the high box would top out at 8.25 with its bob and lose its
-- top half-stud behind the fascia from across the road. The pair that reads
-- from everywhere is 4.40 / 5.55, and the arithmetic it is solved against,
-- bottom up:
--
--   projector disc ... 0.80 .. 1.00   rests on the deck
--   nameplate ....... 1.25 .. 2.35   0.25 over the disc, 1.10 tall not 1.43
--   low box ......... 2.55 .. 6.25   at full bob either way (centre 4.40)
--   high box ........ 3.70 .. 7.40   centre 5.55; 0.26 under the 7.66 sightline
--                                    and 1.50 under the soffit it could hit
--
-- Corner radii, r(x, y) = sqrt(x^2 + (y - 1)^2), worst corner of each new part
-- (the boxes reach x 31.90 at the rear and the rib limit is 33.05 because two
-- slots cross the arch at z -52.36 .. -51.64):
--   high box rear top (31.90, 7.40) r = 32.536  ->  0.514 clear of the ribs
--   low  box rear top (31.90, 6.25) r = 32.329  ->  0.721
--   projector disc    (31.70, 1.00) r = 31.700  ->  1.350
--   nameplate         (29.20, 2.35) r = 29.223  ->  3.827
-- and at the kiosk bays, which are at z -40.7 / -35.0 and so answer only to the
-- shell's 33.70:
--   bay box rear top  (31.30, 9.25) r = 32.372  ->  1.328 clear of the shell
local AREA_Z = -57          -- centre of the frontage along the tunnel
local AREA_HALF = 11.2      -- so the deck spans z -68.2 .. -45.8
local FLOOR_Y = 0.65        -- top of the right service ledge
local DECK_TOP = 0.80       -- top of the shop's own deck plate
local BACK_X = 32.45        -- back panel centre, clear of the wall face at 32.9
local HOLOGRAM_X = 30.40    -- projector and box centres; the box's rear reaches 31.90
local PLATE_X = 27.78       -- the pressure plates, 0.40 further in than the 2026-09-16 row
local ITEM_SPACING = 3.15   -- 7 slots (6 items + the rewards plaque) in 22.4
local PLATE_HALF_X, PLATE_HALF_Z = 1.70, 1.55
local PLATE_HYSTERESIS = 0.6 -- the zone a player already inside has to leave
local FOCUS_POLL = 0.2       -- seconds; also the debounce for a plate's edge

-- The hologram kit. One set of numbers for the frontage row and one for the two
-- kiosk bays, which have no canopy over them and can afford a bigger box.
local BOX_SIZE = 3.00               -- was a 2.20 crate: 1.86x the face, 2.5x the volume
local BOX_Y_LOW, BOX_Y_HIGH = 4.40, 5.55
local BAY_BOX_SIZE = 3.20
local BAY_BOX_X, BAY_BOX_Y = 29.70, 7.30 -- clear of the bay shelf, recess and info card
local BAY_BASE_Y = 4.52             -- disc bottom, 0.06 over the bay shelf top at 4.46
local BAY_PLATE_X = 24.50           -- road edge 22.80, clear of the counter's bottom glow
local PROJECTOR_WIDE = 2.60
local PROJECTOR_THICK = 0.20
local BEAM_WIDE = 0.50
local HOLOGRAM_TRANSPARENCY = 0.35
local BEAM_TRANSPARENCY = 0.85
local BOB_CLEARANCE = 0.35  -- Shop Display Client's BOB_HEIGHT, so the beam reaches the top of it
local NAMEPLATE_Y = 1.80
local FOCUS_ATTRIBUTE = "ZyntraShopFocus"
local MODEL_NAME = "ZyntraShopDisplay"
local REWARDS_PROMPT_NAME = "ZyntraShopPrompt"  -- the name ZyntraStore already binds
local REWARDS_PROMPT_FLAG = "ShopRewardsPrompt" -- how the client tells it apart

-- The terminal's Shop tab order, so the wall reads left to right the way the
-- card list reads top to bottom. Anything in the catalogue that is NOT named
-- here still gets a hologram (see `catalogue`), with the fallback art.
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
	-- Stated rather than left to the default: a Decal inherits nothing from its
	-- part, and the hologram boxes it goes on are 0.35 transparent on purpose.
	-- The product art is the one thing on them that has to stay solid.
	decal.Transparency = 0
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
	model:SetAttribute("ShopDisplayVersion", 3)
	model:SetAttribute("Placement", "Right service ledge between the Level 2 gate and the supply kiosk")
	model:SetAttribute("FocusAttribute", FOCUS_ATTRIBUTE)
	-- The envelope this build was solved against, so a Studio probe can check the
	-- geometry without reading the source.
	model:SetAttribute("ShellInnerRadius", 33.9)
	model:SetAttribute("RibInnerRadius", 33.25)
	model:SetAttribute("FrontmostX", BAY_PLATE_X - PLATE_HALF_X)
	model:SetAttribute("CanopyClearanceY", 7.60)
	model.Parent = lobbyModel

	-- Every part faces the road: the part's Front (-Z) points at the tunnel's
	-- centre line, so a size of (width, height, depth) means width ALONG the
	-- wall. The same convention the lobby's signal console uses.
	local function faceCF(x, y, z)
		local position = center + Vector3.new(x, y, AREA_Z + z)
		return CFrame.lookAt(position, center + Vector3.new(0, y, AREA_Z + z))
	end

	-- ── one hologram fixture ──────────────────────────────────────────────────
	-- A projector disc standing on `baseY`, the beam it throws, and the product
	-- box floating in it. The frontage row and the two kiosk bays build the same
	-- three parts at two sizes, so the shop reads as one kit and not as two.
	--
	-- The disc is a CylinderMesh on an ordinary Part rather than a Cylinder-
	-- shaped part: a Cylinder part's axis is +X and would have to be rolled 90
	-- degrees to lie flat, which puts a rotation into geometry whose every other
	-- corner is checked against a radius. CylinderMesh's axis is already +Y.
	local function addHologram(stand, key, accent, x, offset, baseY, boxY, boxSize, textureId, item)
		local disc = makePart(stand, "ShopProjectorDisc",
			faceCF(x, baseY + PROJECTOR_THICK * 0.5, offset),
			Vector3.new(PROJECTOR_WIDE, PROJECTOR_THICK, PROJECTOR_WIDE),
			accent, Enum.Material.Neon, 0.2)
		disc:SetAttribute("ShopItemKey", key)
		local mesh = Instance.new("CylinderMesh")
		mesh.Name = "ShopProjectorDiscMesh"
		mesh.Parent = disc

		-- The beam is fixed and the box moves, so the beam reaches the box's
		-- HIGHEST bob: an overlap inside a 0.35-transparent box is invisible,
		-- a 0.35-stud gap at the top of a light beam reads as a fault.
		local beamBottom = baseY + PROJECTOR_THICK
		local beamTop = boxY - boxSize * 0.5 + BOB_CLEARANCE
		local beam = makePart(stand, "ShopProjectorBeam",
			faceCF(x, (beamBottom + beamTop) * 0.5, offset),
			Vector3.new(BEAM_WIDE, beamTop - beamBottom, BEAM_WIDE),
			accent, Enum.Material.Neon, BEAM_TRANSPARENCY)
		beam.CanQuery = false
		beam:SetAttribute("ShopItemKey", key)

		local box = makePart(stand, "ShopHologramBox",
			faceCF(x, boxY, offset), Vector3.new(boxSize, boxSize, boxSize),
			accent, Enum.Material.ForceField, HOLOGRAM_TRANSPARENCY)
		box:SetAttribute("ShopItemKey", key)
		box:SetAttribute("ShopBobOrigin", box.CFrame)
		box:SetAttribute("ShopTextureSlot", "Box:" .. key)
		-- The product art goes on the ONE face that looks at the road and stays
		-- fully opaque there: a Decal inherits nothing from its part's
		-- transparency, so the item reads solid inside a box that does not. The
		-- other five faces are the accent's own glass. Nothing turns the box --
		-- see Shop Display Client -- because a turning box hides the art it
		-- exists to show.
		local hasArt = assetUrl(textureId) and addDecal(box, Enum.NormalId.Front, "Box:" .. key, textureId)
		if not hasArt then
			hasArt = addDecal(box, Enum.NormalId.Front, "BoxFallback", textures.BoxFallback)
		end
		if not hasArt then
			hasArt = addDecal(box, Enum.NormalId.Front, "Box:" .. key, item and item.IconId)
		end
		if not hasArt then
			-- Never a blank box: the item's own monogram until an id exists.
			local gui = addFace(box, Enum.NormalId.Front, 256, 256)
			addText(gui, "BoxMonogram", tostring((item and item.IconText) or "Z//"),
				UDim2.fromScale(0.1, 0.28), UDim2.fromScale(0.8, 0.44), accent, Enum.Font.GothamBlack)
		end

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
	local function addPlate(stand, key, x, offset, y)
		local plate = makePart(stand, "ShopPressurePlate",
			faceCF(x, y, offset), Vector3.new(PLATE_HALF_Z * 2, 0.12, PLATE_HALF_X * 2),
			PALETTE.metalLight, Enum.Material.SmoothPlastic, 1)
		plate.CanQuery = false
		plate:SetAttribute("ShopItemKey", key)
		return plate
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
		-- stud inside the shell, and they clipped the outer slots.
		makePart(model, "ShopPilaster",
			faceCF(32.12, (1.05 + 9.34) * 0.5, side * (AREA_HALF - 0.45)), Vector3.new(0.90, 9.34 - 1.05, 0.44),
			PALETTE.metal, Enum.Material.Metal)
		makePart(model, "ShopPilasterTrim",
			faceCF(28.26, (1.05 + 7.40) * 0.5, side * (AREA_HALF - 0.45)), Vector3.new(0.14, 7.40 - 1.05, 0.12),
			PALETTE.neon, Enum.Material.Neon, 0.05)
	end

	-- ── canopy: a lit fascia the walk reads, and the soffit it hangs from ─────
	-- The fascia's bottom edge is y 7.60. It is the CEILING the hologram row is
	-- solved against: the high box tops out at 7.40 with its bob, so there is
	-- 0.20 of air under the fascia at the top of the bob.
	local fascia = makePart(model, "ShopCanopyFascia",
		faceCF(28.42, 8.25, 0), Vector3.new(21.80, 1.30, 0.44),
		PALETTE.metal, Enum.Material.Metal)
	if not addTexture(fascia, Enum.NormalId.Front, "CanopyFascia", textures.CanopyFascia, 2.60, 1.30) then
		fascia:SetAttribute("ShopTextureSlot", "CanopyFascia")
	end
	do
		-- 21.80 x 1.30 studs of face at 436 x 26 canvas = 20.0 px/stud, so the
		-- 22 px band of type is 1.10 studs tall in the world -- three times the
		-- 2026-09-15 slot caption, and the widest single line the shop has.
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

	-- ── one hologram, nameplate and pressure plate per catalogue item ─────────
	-- Seven slots across the 22.4 studs: six items and the DAILY REWARDS plaque
	-- at the kiosk end. At 3.15 studs the widest part of a slot is now the
	-- pressure plate at 3.10 along the wall, which leaves 0.05 between zones --
	-- a gap PLATE_HYSTERESIS covers, so a player walking the row never falls
	-- between two cards. The 3.00 boxes leave 0.15 between them at any height.
	local items = catalogue()
	local count = #items
	local slots = count + 1
	local function slotOffset(index)
		return (index - (slots + 1) * 0.5) * ITEM_SPACING
	end
	local plates = {}
	for index, entry in ipairs(items) do
		local offset = slotOffset(index)
		local accent = entry.Key == "EmergencyReentry" and PALETTE.red
			or (entry.Kind == "Pass" and PALETTE.neon or PALETTE.gold)

		local stand = Instance.new("Model")
		stand.Name = "ShopStand_" .. entry.Key
		stand:SetAttribute("ShopItemKey", entry.Key)
		stand:SetAttribute("ShopItemKind", entry.Kind)
		stand.Parent = model

		-- Alternating hover heights. Nothing turns, so 3.00 boxes at a 3.15
		-- pitch clear each other by 0.15 at any height -- but a single-height
		-- row occludes itself the moment the walk reads it from down the
		-- tunnel rather than square on. 1.15 studs of stagger opens a sightline
		-- to both rows from the same place.
		local boxY = (index % 2 == 1) and BOX_Y_LOW or BOX_Y_HIGH
		addHologram(stand, entry.Key, accent, HOLOGRAM_X, offset, DECK_TOP, boxY,
			BOX_SIZE, textures.Box and textures.Box[entry.Key], entry.Item)

		-- The nameplate lost the column it was bolted to and now floats in the
		-- beam under the box, in front of it rather than behind it, so nothing
		-- translucent sits between the name and the road. 1.10 tall instead of
		-- 1.43 is what puts its top at 2.35, a clear 0.20 under the low box's
		-- deepest bob. Physical type size is the plaque's WIDTH over the
		-- characters on a line, and 2.86 studs is unchanged, so the name reads
		-- exactly as large as it did; the canvas is 143 x 55 = 50 px/stud on a
		-- 2.6:1 face that matches the plaque, so nothing is stretched.
		local plaque = makePart(stand, "ShopNamePlate",
			faceCF(HOLOGRAM_X - 1.26, NAMEPLATE_Y, offset), Vector3.new(2.86, 1.10, 0.12),
			PALETTE.panel, Enum.Material.Metal)
		plaque:SetAttribute("ShopItemKey", entry.Key)
		if not addDecal(plaque, Enum.NormalId.Front, "NamePlate", textures.NamePlate) then
			plaque:SetAttribute("ShopTextureSlot", "NamePlate")
		end
		local plaqueGui = addFace(plaque, Enum.NormalId.Front, 143, 55)
		-- Price-free by contract: the eyebrow says what KIND of thing this is and
		-- the card says what it costs, because the price is live and this is not.
		addText(plaqueGui, "ItemKind", entry.Kind == "Pass" and "PASS" or "PRODUCT",
			UDim2.fromOffset(4, 3), UDim2.fromOffset(135, 13), accent, Enum.Font.Code)
		addText(plaqueGui, "ItemName", tostring(entry.Item.Name or entry.Key),
			UDim2.fromOffset(4, 18), UDim2.fromOffset(135, 34), PALETTE.text)

		local plate = addPlate(stand, entry.Key, PLATE_X, offset, DECK_TOP + 0.06)
		table.insert(plates, {Key = entry.Key, Plate = plate.Position})
	end

	-- Token supplies occupy the existing kiosk's first two merchandise bays.
	-- The counter stays solid and the pressure plates sit in front of it, so the
	-- larger frontage stays readable without squeezing nine slots into one row.
	--
	-- The bay hologram is 3.20 rather than 3.00 because nothing hangs over it,
	-- and it sits at (29.70, 7.30) rather than the crate's old (30.75, 6.00):
	-- a 3.20 box at the old pose would have cut the bay shelf at y 4.46 on the
	-- down-bob and the bay's info card at y 7.56 on the up-bob. Its projector
	-- disc floats 0.06 over the shelf lip instead of resting on it -- a disc on
	-- the deck below would be hidden by the counter top at y 4.22.
	for _, bay in ipairs({{Key = "SpeedPotion", Offset = 16.3}, {Key = "RouteMarker", Offset = 22}}) do
		local item = Config.Items and Config.Items[bay.Key]
		if item then
			local stand = Instance.new("Model")
			stand.Name = "ShopStand_" .. bay.Key
			stand:SetAttribute("ShopItemKey", bay.Key)
			stand:SetAttribute("ShopItemKind", "Item")
			stand:SetAttribute("ShopSupplyBay", true)
			stand.Parent = model
			addHologram(stand, bay.Key, PALETTE.gold, BAY_BOX_X, bay.Offset, BAY_BASE_Y,
				BAY_BOX_Y, BAY_BOX_SIZE, textures.Box and textures.Box[bay.Key], item)
			local plate = addPlate(stand, bay.Key, BAY_PLATE_X, bay.Offset, FLOOR_Y + 0.06)
			table.insert(plates, {Key = bay.Key, Plate = plate.Position})
			count += 1
		end
	end
	model:SetAttribute("ShopItemCount", count)

	-- ── the seventh slot: DAILY REWARDS ──────────────────────────────────────
	-- A reach-in, not a shop item: it has no pressure plate, it never publishes
	-- ZyntraShopFocus, and it grants NOTHING. It is also the ONLY prompt left on
	-- the frontage. It keeps the name ZyntraStore has always bound
	-- (ZyntraShopPrompt) and the ShopRewardsPrompt attribute that tells it apart
	-- from the kiosk's own terminal prompt, so whatever the client binds that
	-- attribute to -- the terminal's Rewards tab before this batch, the
	-- standalone Daily Rewards modal after it -- keeps working unchanged.
	do
		local offset = slotOffset(slots)
		local stand = Instance.new("Model")
		stand.Name = "ShopStand_DailyRewards"
		stand:SetAttribute("ShopRewardsStand", true)
		stand.Parent = model

		local plinth = makePart(stand, "ShopRewardsPlinth",
			faceCF(HOLOGRAM_X, (DECK_TOP + 2.60) * 0.5, offset), Vector3.new(2.70, 2.60 - DECK_TOP, 2.40),
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
		addText(gui, "RewardsLine", "PLAY TO EARN", UDim2.fromOffset(6, 80),
			UDim2.fromOffset(100, 14), PALETTE.text, Enum.Font.Code)
		addText(gui, "RewardsFoot", "PRESS E TO OPEN", UDim2.fromOffset(6, 106),
			UDim2.fromOffset(100, 16), PALETTE.muted, Enum.Font.Code)
		addPointLight(plaque, "ShopRewardsGlow", PALETTE.gold, 0.9, 10)

		local prompt = Instance.new("ProximityPrompt")
		prompt.Name = REWARDS_PROMPT_NAME
		prompt.ActionText = "DAILY REWARDS"
		prompt.ObjectText = "Daily Rewards"
		prompt.KeyboardKeyCode = Enum.KeyCode.E
		prompt.GamepadKeyCode = Enum.KeyCode.ButtonX
		prompt.HoldDuration = 0
		prompt.MaxActivationDistance = 9
		prompt.RequiresLineOfSight = false
		prompt:SetAttribute(REWARDS_PROMPT_FLAG, true)
		prompt.Parent = plaque
	end

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
		-- always beats a neighbour's raw zone: at a 3.15 pitch the zones are
		-- 0.05 apart and the slack reaches into the next one, and without this
		-- the answer at a boundary would depend on the order the row was built.
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
