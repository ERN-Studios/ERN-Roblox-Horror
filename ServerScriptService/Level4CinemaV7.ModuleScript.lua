-- Level 4 cinema V7 candidate, based on verified live V6 source.
-- Static architecture only: no entities or objectives, and no dependency on older Level 4 modules.
--
--   local V7 = require(path.to.Level4CinemaV7)
--   local model = V7.Build(CFrame.new(23000, 24, 0)) -- returned unparented
--   model.Parent = workspace
--   print(V7.SelfCheck(model))                       -- needs the model in Workspace
--
-- Local frame in studs: one collidable base slab y[-1,0] under x[-378,378] z[-240,240];
-- north (screens) = -Z; closed glass main entry x[-24,24] y[0,14]; arrival (0,0,226).
--   Halls A1 x[-324,-144], A2 x[-90,90], A3 x[144,324]; z[-240,-20]; roof y[80,81].
--     u = x - hall centre. Deck u[-78,78]: front tiers y2..16, cross aisle z[-140,-120]
--     at y18, rear tiers y21..48, top walk z[-30,-22] at y48. Side aisles u+-[78,88]
--     climb in 1-stud treads. Doors z[-136,-124] y[18,28] in both side walls; front-right
--     exit z[-230,-218] y[0,10]. 18 rows x 22 chairs (banks u=-68+6j, 8+6j). Booth
--     u[-16,16] z[-34,-22], floor y62, roof y75; centered rear booth entry from gallery.
--   Corridors C1..C4 are 54 wide, z[-240,-20], roof y[32,33]. Side stair lanes rise
--     y0 -> y18 into mid-hall doors. Separated return lanes remain at y0.
--   Hidden core x[-354,-324] z[0,98] has one stair flight to gallery y62,
--     x[-376,376] z[-20,0].
--   Concourse x[-378,378] z[-20,100], roof y[36,37], with split roof at the core.
--   South z[102,238]: service x[-376,-122], concessions x[-120,120],
--     arcade x[122,259], compact restrooms x[261,376].

local CollectionService = game:GetService("CollectionService")

local V7 = {}

V7.MODEL_NAME = "Level 4 Cinema Preview"
V7.LAYOUT_VERSION = 4 -- existing developer preview gate requires this contract
V7.MAX_PARTS = 6400
V7.MAX_LIGHTS = 140
V7.CHAIRS_PER_HALL = 396
V7.DOORWAYS = 20 -- V5 openings with the staff inner opening sealed

local FLOOR_TAG = "Level4V4Floor"
local DOOR_TAG = "Level4V4Doorway"
local SEAT_TAG = "Level4V4Seat"
V7.TAGS = { Floor = FLOOR_TAG, Doorway = DOOR_TAG, Seat = SEAT_TAG, Exit = "Level4V4Exit" }

-- Newer materials resolve at runtime so an older engine falls back instead of erroring.
local function material(name, fallback)
	local ok, m = pcall(function()
		return Enum.Material[name]
	end)
	return if ok and m then m else fallback
end

local SP = Enum.Material.SmoothPlastic
local NEON = Enum.Material.Neon
local METAL = Enum.Material.Metal
local GLASS = Enum.Material.Glass
local FABRIC = Enum.Material.Fabric
local WOOD = Enum.Material.Wood
local CONCRETE = Enum.Material.Concrete
local TILE = material("CeramicTiles", SP)

-- Verified V6 imagegen uploads retained for this V7 candidate.
local CARPET = {
	Red = { "rbxassetid://89133343738628", 12, Color3.fromRGB(128, 20, 16) },
	Service = { "rbxassetid://132321859875122", 8, Color3.fromRGB(62, 18, 24) },
	ServiceStair = { "rbxassetid://132321859875122", 8, Color3.fromRGB(190, 68, 58), 0.65 },
	Ring = { "rbxassetid://83035715709261", 12, Color3.fromRGB(92, 26, 49) },
	Blue = { "rbxassetid://124143988203513", 12, Color3.fromRGB(17, 42, 64) },
	HallWarm = { "rbxassetid://95353980397733", 12, Color3.fromRGB(75, 38, 36) },
}
local POSTERS = {
	{ "rbxassetid://90273706821327", "ECLIPSE VOYAGE" },
	{ "rbxassetid://78063750109486", "LAST SHOWING" },
	{ "rbxassetid://98375790871589", "AFTERLIGHT RUN" },
	{ "rbxassetid://70369867264188", "THE GLASS TIDE" },
	{ "rbxassetid://71191268393019", "VIOLET PIER" },
}
local ARCADE_SCREENS = {
	"rbxassetid://88762877843354", -- original vector shooter
	"rbxassetid://116477413027023", -- original night racer
	"rbxassetid://104744627593472", -- original fantasy maze
}
local WALL_BASE = "rbxassetid://93137661811831" -- clean terracotta plaster
local WALL_EDGE = "rbxassetid://72967446639461" -- matching, light corner wear
local RESTROOM_WALL_TILE = "rbxassetid://102932240946376"
local RESTROOM_FLOOR_TILE = "rbxassetid://135552286264828"
local RESTROOM_STALL_FINISH = "rbxassetid://114637357131488"
local RESTROOM_CEILING_PANEL = "rbxassetid://129069567925983"
local BURGUNDY_WALL = "rbxassetid://98590012051623"
local SERVICE_TEAL = "rbxassetid://75722310684409"
local TICKET_FASCIA = "rbxassetid://114100094443350"
local COUNTER_LAMINATE = "rbxassetid://98336445559206"
local TABLE_LAMINATE = "rbxassetid://130628385814119"
local SERVICE_CONCRETE = "rbxassetid://90013106906132"

local PAL = {
	Shell = Color3.fromRGB(24, 18, 20),
	HallWall = Color3.fromRGB(18, 44, 48), -- dark teal acoustic finish
	CorridorWall = Color3.fromRGB(141, 54, 30),
	Partition = Color3.fromRGB(157, 62, 33),
	Ceiling = Color3.fromRGB(10, 8, 9),
	FoyerCeiling = Color3.fromRGB(162, 18, 11),
	LightCeiling = Color3.fromRGB(118, 110, 103),
	Charcoal = Color3.fromRGB(30, 26, 28),
	Aisle = Color3.fromRGB(30, 22, 26),
	Seat = Color3.fromRGB(20, 52, 56),
	SeatBack = Color3.fromRGB(15, 39, 43),
	Screen = Color3.fromRGB(236, 228, 206),
	ScreenGlow = Color3.fromRGB(200, 214, 255),
	Black = Color3.fromRGB(8, 8, 8),
	Frame = Color3.fromRGB(44, 22, 24),
	Booth = Color3.fromRGB(22, 20, 24),
	Metal = Color3.fromRGB(60, 58, 62),
	Chrome = Color3.fromRGB(150, 146, 140),
	Glass = Color3.fromRGB(205, 225, 235),
	TintGlass = Color3.fromRGB(20, 26, 30),
	Turquoise = Color3.fromRGB(22, 172, 166),
	Tan = Color3.fromRGB(199, 154, 102),
	Green = Color3.fromRGB(28, 92, 62),
	Teal = Color3.fromRGB(16, 50, 54),
	TileWhite = Color3.fromRGB(226, 222, 214),
	Counter = Color3.fromRGB(170, 18, 22),
	CounterWhite = Color3.fromRGB(232, 228, 220),
	Board = Color3.fromRGB(26, 11, 13),
	Stall = Color3.fromRGB(34, 62, 60),
	Service = Color3.fromRGB(70, 66, 62),
	Crate = Color3.fromRGB(110, 68, 40),
	Cabinet = Color3.fromRGB(20, 18, 26),
	DarkScreen = Color3.fromRGB(12, 16, 20),
	White = Color3.fromRGB(255, 255, 255),
	Exit = Color3.fromRGB(230, 30, 30),
	NeonRed = Color3.fromRGB(255, 34, 20),
	NeonAmber = Color3.fromRGB(255, 158, 84),
	NeonBlue = Color3.fromRGB(90, 170, 255),
	NeonCyan = Color3.fromRGB(40, 230, 255),
	NeonWarmWhite = Color3.fromRGB(255, 240, 210),
	Warm = Color3.fromRGB(255, 214, 170),
}

local HALLS = { { Id = "A1", X = -234 }, { Id = "A2", X = 0 }, { Id = "A3", X = 234 } }
local HALL_COLORS = {
	{ Wall = Color3.fromRGB(61, 22, 27), Seat = Color3.fromRGB(94, 24, 32),
		Back = Color3.fromRGB(62, 15, 23), Panel = Color3.fromRGB(83, 28, 33),
		Edge = Color3.fromRGB(168, 43, 30), Screen = 0.55 },
	{ Wall = Color3.fromRGB(14, 33, 66), Seat = Color3.fromRGB(20, 54, 106),
		Back = Color3.fromRGB(12, 35, 69), Panel = Color3.fromRGB(19, 44, 81),
		Edge = Color3.fromRGB(50, 128, 194), Screen = 0.55 },
	{ Wall = Color3.fromRGB(22, 29, 28), Seat = Color3.fromRGB(28, 36, 34),
		Back = Color3.fromRGB(17, 24, 23), Panel = Color3.fromRGB(27, 35, 32),
		Edge = Color3.fromRGB(64, 43, 25), Screen = 0.05 },
}
local AISLES = { { -88, -78 }, { 78, 88 } } -- side aisles in hall-local u = x - hall X

-- Span is the corridor's full strip (roof extent); X0..X1 is the clear width between walls.
local CORRIDORS = {
	{ Id = "C1", Span = { -378, -324 }, X0 = -376, X1 = -324, Return = { -376, -339 },
		Separators = { { -339, -338 } }, Stairs = { { "A1West", -338, -324 } } },
	{ Id = "C2", Span = { -144, -90 }, X0 = -144, X1 = -90, Return = { -131, -103 },
		Separators = { { -132, -131 }, { -103, -102 } }, Stairs = { { "A1East", -144, -132 }, { "A2West", -102, -90 } } },
	{ Id = "C3", Span = { 90, 144 }, X0 = 90, X1 = 144, Return = { 103, 131 },
		Separators = { { 102, 103 }, { 131, 132 } }, Stairs = { { "A2East", 90, 102 }, { "A3West", 132, 144 } } },
	{ Id = "C4", Span = { 324, 378 }, X0 = 324, X1 = 376, Return = { 339, 376 },
		Separators = { { 338, 339 } }, Stairs = { { "A3East", 324, 338 } } },
}

-- Concourse wall z[100,102] openings: x0, x1, bottom, top, name, sign.
local SOUTH_OPENINGS = {
	{ -146, -126, 0, 12, "ServiceDoorway", "SERVICE" },
	{ 55, 95, 0, 12, "ConcessionsDoorway", "CONCESSIONS" },
	{ 150, 178, 0, 12, "ArcadeDoorway", "ARCADE" },
	{ 280, 296, 0, 12, "RestroomsDoorway", "RESTROOMS" },
}

V7.HALLS = HALLS
V7.CORRIDORS = CORRIDORS
V7.SOUTH_OPENINGS = SOUTH_OPENINGS

-- Side-aisle walk height at depth z: y0 apron, 1-stud treads every 4 studs to the y18
-- cross aisle, then every 3 studs to the y48 top walk.
local function aisleY(z)
	if z < -208 then
		return 0
	elseif z < -140 then
		return math.floor((z + 212) / 4)
	elseif z < -120 then
		return 18
	elseif z < -30 then
		return 18 + math.floor((z + 123) / 3)
	end
	return 48
end
V7.AisleHeight = aisleY

-- Floor probes { name, x, z, expected walk y } in local coordinates (blueprint acceptance 2).
local PROBES = {}
local function probe(name, x, z, y)
	table.insert(PROBES, { name, x, z, y })
end
for _, h in HALLS do
	for _, p in { { 0, -228, 0 }, { -83, -224, 0 }, { 83, -224, 0 }, { -83, -130, 18 }, { 0, -130, 18 }, { 83, -130, 18 }, { -83, -32, 48 }, { 83, -32, 48 } } do
		probe(string.format("%s u%d z%d", h.Id, p[1], p[2]), h.X + p[1], p[2], p[3])
	end
	for _, u in { -83, 83 } do
		for _, z in { -237, -230, -222, -214, -209 } do
			probe(string.format("%s front side strip u%d z%d", h.Id, u, z), h.X + u, z, 0)
		end
	end
	probe(h.Id .. " booth floor", h.X + 8, -28, 62)
	probe(h.Id .. " booth threshold", h.X, -21, 62)
end
for _, c in CORRIDORS do
	for _, z in { -224, -145, -30, -21 } do
		probe(string.format("%s ground lane z%d", c.Id, z), (c.Return[1] + c.Return[2]) / 2, z, 0)
	end
	for _, st in c.Stairs do
		local x = (st[2] + st[3]) / 2
		probe(c.Id .. " " .. st[1] .. " first tread", x, -32.5, 1)
		probe(c.Id .. " " .. st[1] .. " last tread", x, -112.5, 17)
		probe(c.Id .. " " .. st[1] .. " door landing", x, -130, 18)
	end
end
for _, p in {
	{ "Hidden core entry", -330, 92, 0 },
	{ "East entry connector", -329, 90, 0 },
	{ "South stair landing", -342, 95, 0 },
	{ "East first tread", -342, 89.3387, 1 },
	{ "East midflight", -342, 48.3387, 32 },
	{ "East last tread", -342, 8.6613, 62 },
	{ "North gallery landing left", -350, 6, 62 },
	{ "North gallery landing east", -330, 6, 62 },
	{ "Hidden core gallery threshold", -330, 1, 62 },
	{ "Gallery west", -300, -10, 62 }, { "Gallery middle", 0, -10, 62 },
	{ "Gallery east", 300, -10, 62 },
} do
	probe(p[1], p[2], p[3], p[4])
end
for _, p in {
	{ "Concourse centre", 0, 55 }, { "Concourse east carpet", 250, 40 }, { "Arrival", 0, 226 },
	{ "Concessions passage", 75, 160 }, { "Service", -240, 170 },
	{ "Arcade", 190, 170 }, { "Restroom vestibule", 288, 118 },
} do
	probe(p[1], p[2], p[3], 0)
end
probe("Men's room", 288, 142, 0.05)
probe("Women's room", 331, 142, 0.05)
V7.PROBES = PROBES

local origin = CFrame.identity

local function folder(parent, name)
	local f = Instance.new("Folder")
	f.Name = name
	f.Parent = parent
	return f
end

local function part(parent, name, size, cf, color, mat, collide, shape)
	local p = Instance.new("Part")
	p.Name = name
	p.Anchored = true
	if shape then
		p.Shape = shape
	end
	p.Size = size
	p.CFrame = origin * cf
	if color then
		p.Color = color
	end
	p.Material = mat or SP
	p.TopSurface = Enum.SurfaceType.Smooth
	p.BottomSurface = Enum.SurfaceType.Smooth
	p.CanTouch = false
	if collide == false then
		-- decor and finishes never block a route or a floor/doorway probe
		p.CanCollide = false
		p.CanQuery = false
	end
	if p.Material == NEON then
		p.CastShadow = false
	end
	p.Parent = parent
	return p
end

-- Axis-aligned box between two local corners, in any order.
local function box(parent, name, x0, y0, z0, x1, y1, z1, color, mat, collide)
	return part(parent, name, Vector3.new(math.abs(x1 - x0), math.abs(y1 - y0), math.abs(z1 - z0)),
		CFrame.new((x0 + x1) / 2, (y0 + y1) / 2, (z0 + z1) / 2), color, mat, collide)
end

-- Wall-relative box: `a` runs along `axis` ("X" or "Z"), `d` spans the perpendicular depth.
local function slab(parent, name, axis, a0, a1, y0, y1, d0, d1, color, mat, collide)
	if axis == "X" then
		return box(parent, name, a0, y0, d0, a1, y1, d1, color, mat, collide)
	end
	return box(parent, name, d0, y0, a0, d1, y1, a1, color, mat, collide)
end

-- Vertical cylinder spanning y0..y1.
local function disc(parent, name, x, z, diameter, y0, y1, color, mat, collide)
	return part(parent, name, Vector3.new(y1 - y0, diameter, diameter),
		CFrame.new(x, (y0 + y1) / 2, z) * CFrame.Angles(0, 0, math.rad(90)), color, mat, collide, Enum.PartType.Cylinder)
end

-- Non-colliding floor finish on the base slab: layer 1 is y[0,0.05], layer 2 sits on it.
local function overlay(parent, name, x0, z0, x1, z1, color, mat, layer)
	local y = ((layer or 1) - 1) * 0.05
	return box(parent, name, x0, y, z0, x1, y + 0.05, z1, color, mat, false)
end

local function light(p, class, color, brightness, range, face, angle)
	local l = Instance.new(class)
	l.Color = color
	l.Brightness = brightness
	l.Range = range
	l.Shadows = false
	if face then
		l.Face = face
		l.Angle = angle or 90
	end
	l.Parent = p
	return p
end

local function glow(parent, name, x0, y0, z0, x1, y1, z1, color, brightness, range)
	return light(box(parent, name, x0, y0, z0, x1, y1, z1, color, NEON, false), "PointLight", color, brightness, range)
end

local function tag(p, name)
	CollectionService:AddTag(p, name)
	return p
end

local function carpet(p, key)
	local c = CARPET[key]
	p.Color = c[3]
	p.Material = FABRIC
	local t = Instance.new("Texture")
	t.Name = key .. "Carpet"
	t.Face = Enum.NormalId.Top
	t.Texture = c[1]
	t.StudsPerTileU = c[2]
	t.StudsPerTileV = c[2]
	t.Transparency = c[4] or 0
	t.Parent = p
	return p
end

local function finish(p, face, assetId, tileU, tileV)
	local t = Instance.new("Texture")
	t.Name = "WallFinish"
	t.Face = face
	t.Texture = assetId
	t.StudsPerTileU = tileU
	t.StudsPerTileV = tileV
	t.Parent = p
	return p
end

local function floor(p, key)
	return tag(if key then carpet(p, key) else p, FLOOR_TAG)
end

local function label(p, face, text, color)
	local g = Instance.new("SurfaceGui")
	g.Name = "Label"
	g.Face = face
	g.LightInfluence = 0
	g.SizingMode = Enum.SurfaceGuiSizingMode.PixelsPerStud
	g.PixelsPerStud = 30
	local t = Instance.new("TextLabel")
	t.Size = UDim2.fromScale(1, 1)
	t.BackgroundTransparency = 1
	t.Font = Enum.Font.GothamBlack
	t.TextScaled = true
	t.TextColor3 = color
	t.Text = text
	t.Parent = g
	g.Parent = p
	return p
end

-- Wall along `axis` over a0..a1, depth d0..d1, height y0..y1. `gaps` are sorted
-- { a0, a1, bottom, top } openings; sills and headers close everything else.
local function wall(parent, name, axis, a0, a1, d0, d1, y0, y1, color, mat, gaps)
	local function seg(suffix, s, e, b, t)
		if e - s > 0.01 and t - b > 0.01 then
			slab(parent, name .. suffix, axis, s, e, b, t, d0, d1, color, mat)
		end
	end
	local cursor = a0
	for _, g in gaps or {} do
		seg("", cursor, g[1], y0, y1)
		seg("_Sill", g[1], g[2], y0, g[3])
		seg("_Header", g[1], g[2], g[4], y1)
		cursor = g[2]
	end
	seg("", cursor, a1, y0, y1)
end

-- Dark jambs and a glowing head around an opening, on the wall face at `face` (dir = face normal sign).
local function frame(parent, name, axis, face, dir, a0, a1, y0, y1, headColor)
	local d = face + dir * 0.3
	slab(parent, name .. "_Jamb", axis, a0 - 1, a0, y0, y1 + 1, face, d, PAL.Frame, METAL, false)
	slab(parent, name .. "_Jamb", axis, a1, a1 + 1, y0, y1 + 1, face, d, PAL.Frame, METAL, false)
	slab(parent, name .. "_Head", axis, a0, a1, y1, y1 + 1, face, d, headColor, NEON, false)
end

-- Invisible, non-colliding volume filling a wall opening; SelfCheck casts through it.
local function doorway(parent, name, x0, y0, z0, x1, y1, z1)
	local p = box(parent, name, x0, y0, z0, x1, y1, z1, PAL.Black, SP, false)
	p.Transparency = 1
	return tag(p, DOOR_TAG)
end

-- The three-part visual shell is a sanitized, script-free Creator Store asset
-- kept in ServerStorage. Runtime motion belongs only to this module.
local function doorTemplate()
	local templates = game:GetService("ServerStorage"):FindFirstChild("Level4V7Templates")
	local template = templates and templates:FindFirstChild("Door")
	assert(template and template:IsA("Model")
		and template:FindFirstChild("Leaf") and template.Leaf:IsA("BasePart")
		and template:FindFirstChild("PushBar") and template.PushBar:IsA("BasePart")
		and template:FindFirstChild("PushWord") and template.PushWord:IsA("BasePart"),
		"Missing vetted Level4V7Templates.Door")
	for _, child in template:GetDescendants() do
		assert(not child:IsA("LuaSourceContainer"), "Door template contains a script")
	end
	return template
end

-- hingeCF is the closed hinge edge; its local +X runs across the leaf.
local function swingLeaf(parent, name, hingeCF, width, height, color, openAngle)
	local template = doorTemplate()
	local doors = parent.Parent:FindFirstChild("AutomaticDoors")
	assert(doors, "Missing AutomaticDoors folder")
	local post = part(doors, name .. "_Post", Vector3.new(0.5, height, 0.5),
		hingeCF, PAL.Frame, METAL, false)
	local closedCF = hingeCF * CFrame.new(width / 2, 0, 0)
	local leaf = template.Leaf:Clone()
	leaf.Name = name .. "_Leaf"
	leaf.Size = Vector3.new(width, height, 0.55)
	leaf.CFrame = origin * closedCF
	leaf.Color = color
	leaf.Material = METAL
	leaf.Anchored = false
	leaf.Massless = true
	leaf.CanCollide = true
	leaf.CanQuery = true
	leaf.CanTouch = false
	leaf.CustomPhysicalProperties = PhysicalProperties.new(0.05, 0.25, 0, 1, 1)
	leaf:SetAttribute("AutoDoorLeaf", true)
	leaf.Parent = doors
	if name ~= "SecretPoster" and name ~= "MainEntryWest" and name ~= "MainEntryEast" then
	leaf.Transparency = 1 -- Collision and hinge root; the visible panels leave a real window opening.
	local function detail(suffix, size, offset, tint, material, transparency)
		local item = Instance.new("Part")
		item.Name = name .. suffix
		item.Size = size
		item.CFrame = leaf.CFrame * offset
		item.Color = tint
		item.Material = material
		item.Transparency = transparency or 0
		item.Anchored = false
		item.Massless = true
		item.CanCollide = false
		item.CanQuery = false
		item.CanTouch = false
		item.TopSurface = Enum.SurfaceType.Smooth
		item.BottomSurface = Enum.SurfaceType.Smooth
		item.Parent = doors
		local weld = Instance.new("WeldConstraint")
		weld.Part0, weld.Part1 = leaf, item
		weld.Parent = item
		return item
	end
	for _, x in { -width / 2 + 0.14, width / 2 - 0.14 } do
		detail("_FrameStile", Vector3.new(0.28, height, 0.64),
			CFrame.new(x, 0, 0), PAL.Frame, METAL)
	end
	for _, y in { -height / 2 + 0.13, height / 2 - 0.13 } do
		detail("_FrameRail", Vector3.new(width - 0.34, 0.26, 0.64),
			CFrame.new(0, y, 0), PAL.Frame, METAL)
	end
	local visionX = width * 0.22
	local visionY = height * 0.2
	local visionH = math.min(height * 0.32, 3.2)
	local visionW = math.min(width * 0.17, 1.45)
	local left, right = visionX - visionW / 2, visionX + visionW / 2
	local bottom, top = visionY - visionH / 2, visionY + visionH / 2
	local function enamelPanel(x0, x1, y0, y1)
		local panel = detail("_EnamelPanel", Vector3.new(x1 - x0, y1 - y0, 0.55),
			CFrame.new((x0 + x1) / 2, (y0 + y1) / 2, 0), color, METAL)
		for _, face in { Enum.NormalId.Front, Enum.NormalId.Back } do
			local enamel = Instance.new("Decal")
			enamel.Name = "WornEnamel"
			enamel.Face = face
			enamel.Texture = "rbxassetid://85095148341638"
			enamel.Transparency = 0.12
			enamel.Parent = panel
		end
	end
	enamelPanel(-width / 2, width / 2, -height / 2, bottom)
	enamelPanel(-width / 2, width / 2, top, height / 2)
	enamelPanel(-width / 2, left, bottom, top)
	enamelPanel(right, width / 2, bottom, top)
	detail("_VisionGlass", Vector3.new(visionW, visionH, 0.05),
		CFrame.new(visionX, visionY, 0), Color3.fromRGB(117, 145, 145), GLASS, 0.72)
	for _, face in { -1, 1 } do
		local z = face * 0.34
		for _, x in { visionX - visionW / 2, visionX + visionW / 2 } do
			detail("_VisionSide", Vector3.new(0.12, visionH + 0.2, 0.1),
				CFrame.new(x, visionY, z + face * 0.05), PAL.Chrome, METAL)
		end
		for _, y in { visionY - visionH / 2, visionY + visionH / 2 } do
			detail("_VisionRail", Vector3.new(visionW + 0.2, 0.12, 0.1),
				CFrame.new(visionX, y, z + face * 0.05), PAL.Chrome, METAL)
		end
		detail("_Kickplate", Vector3.new(width - 0.8, math.min(1.4, height * 0.17), 0.08),
			CFrame.new(0, -height / 2 + 1.0, face * 0.35),
			Color3.fromRGB(91, 93, 88), METAL)
	end
	end
	local function hardware(source, suffix, size, offset, tint)
		local item = source:Clone()
		item.Name = name .. suffix
		item.Size = size
		item.CFrame = leaf.CFrame * offset
		item.Color = tint
		if item:IsA("UnionOperation") then item.UsePartColor = true end
		item.Anchored = false
		item.Massless = true
		item.CanCollide = false
		item.CanQuery = false
		item.CanTouch = false
		item.Parent = doors
		local weld = Instance.new("WeldConstraint")
		weld.Part0, weld.Part1 = leaf, item
		weld.Parent = item
	end
	hardware(template.PushBar, "_PushBar", Vector3.new(width - 0.9, 0.5, 0.2),
		CFrame.new(0, -0.6, -0.4), PAL.Chrome)
	hardware(template.PushWord, "_PushWord", Vector3.new(1.1, 0.5, 0.06),
		CFrame.new(width / 2 - 1.2, -0.6, -0.53), PAL.Exit)
	local a0 = Instance.new("Attachment")
	a0.Axis = Vector3.yAxis
	a0.Parent = post
	local a1 = Instance.new("Attachment")
	a1.Position = Vector3.new(-width / 2, 0, 0)
	a1.Axis = Vector3.yAxis
	a1.Parent = leaf
	local hinge = Instance.new("HingeConstraint")
	hinge.Attachment0, hinge.Attachment1 = a0, a1
	hinge.LimitsEnabled = true
	hinge.LowerAngle, hinge.UpperAngle = -110, 110
	hinge.ActuatorType = Enum.ActuatorType.Servo
	hinge.AngularSpeed = 0.65
	hinge.ServoMaxTorque = 30000
	hinge.TargetAngle = 0
	hinge:SetAttribute("OpenAngle", openAngle)
	hinge.Parent = post
	return hinge
end

local function swingZone(parent, name, cf, size, hinges)
	local doors = parent.Parent:FindFirstChild("AutomaticDoors")
	assert(doors, "Missing AutomaticDoors folder")
	local zone = part(doors, name .. "_Zone", size, cf, PAL.Black, SP, false)
	zone.Transparency = 1
	zone:SetAttribute("AutoDoorZone", true)
	for _, hinge in hinges do
		local ref = Instance.new("ObjectValue")
		ref.Name, ref.Value = "DoorHinge", hinge
		ref.Parent = zone
	end
	return zone
end

-- 4-stud-high standing table, 5.7 studs across at the rim.
local function standingTable(parent, name, x, z)
	disc(parent, name .. "Foot", x, z, 3, 0, 0.3, PAL.Chrome, METAL)
	box(parent, name .. "Stem", x - 0.3, 0.3, z - 0.3, x + 0.3, 3.6, z + 0.3, PAL.Chrome, METAL)
	disc(parent, name .. "Rim", x, z, 5.7, 3.6, 3.75, PAL.Counter)
	finish(disc(parent, name .. "Top", x, z, 5.5, 3.7, 4, PAL.Board),
		Enum.NormalId.Right, TABLE_LAMINATE, 5.5, 5.5)
end

local function buildShell(model)
	local f = folder(model, "Shell")
	-- One collidable base slab under the whole footprint, never perforated. Room finishes
	-- live on separate surfaces, so their textures cannot show through each other.
	floor(box(f, "BaseSlab", -378, -1, -240, 378, 0, 240, PAL.Charcoal))
	-- The slab stays dark in narrow finish joints; the old red underlay bled through stair seams.
	for _, c in CORRIDORS do
		for _, gap in c.Separators do
			overlay(f, c.Id .. "_GroundJoint", gap[1], -238, gap[2], -145,
				PAL.Charcoal, FABRIC)
		end
	end
	carpet(overlay(f, "LobbyCarpet", -376, -20, 376, 100), "Red")
	-- Exterior walls rise from y0 to the underside of the roof they meet.
	for _, h in HALLS do
		box(f, "ShellNorth", h.X - 90, 0, -240, h.X + 90, 80, -238, PAL.Shell)
	end
	for _, c in CORRIDORS do
		box(f, "ShellNorth", c.Span[1], 0, -240, c.Span[2], 32, -238, PAL.Shell)
		box(f, "GalleryNorthFascia", c.Span[1], 37, -20, c.Span[2], 62, -19, PAL.CorridorWall)
	end
	for _, s in { -1, 1 } do
		box(f, "ShellSide", s * 378, 0, -238, s * 376, 32, -20, PAL.Shell)
		box(f, "ShellSide", s * 378, 0, -20, s * 376, 36, 102, PAL.Shell)
		box(f, "GallerySideFascia", s * 378, 36, -20, s * 376, 62, 0, PAL.CorridorWall)
		box(f, "ShellSide", s * 378, 0, 102, s * 376, 28, 238, PAL.Partition)
	end
	for _, side in f:GetChildren() do
		if side:IsA("BasePart") and side.Name == "ShellSide"
			and side.Position.X < 0 and side.Position.Z > 100 then
			finish(side, Enum.NormalId.Right, BURGUNDY_WALL, 32, 24)
		end
	end
	-- the x[-24,24] y[0,14] aperture holds the closed glass entry (Concession)
	wall(f, "ShellSouth", "X", -378, 378, 238, 240, 0, 28, PAL.Partition, SP, { { -24, 24, 0, 14 } })
	for _, p in f:GetChildren() do
		if p:IsA("BasePart") and p.Name == "ShellSouth_Header" then
			finish(p, Enum.NormalId.Front, BURGUNDY_WALL, 12, 12)
		end
	end
	-- concourse | south rooms wall: solid above y12 up to the y36 concourse roof
	wall(f, "ConcourseSouthWall", "X", -376, 376, 100, 102, 0, 36, PAL.Partition, SP, SOUTH_OPENINGS)
	for _, p in f:GetChildren() do
		if p:IsA("BasePart") and p.Name == "ConcourseSouthWall_Header" then
			finish(p, Enum.NormalId.Front, WALL_BASE, 44, 28)
		end
	end
	for _, o in SOUTH_OPENINGS do
		doorway(f, o[5], o[1], o[3], 100, o[2], o[4], 102)
		overlay(f, o[5] .. "Threshold", o[1], 100, o[2], 102, PAL.Charcoal, METAL, 2)
	end
	local serviceDivider = finish(box(f, "Divider_ServiceConcessions", -122, 0, 102, -120, 28, 238,
		PAL.Partition), Enum.NormalId.Right, WALL_BASE, 18, 18)
	finish(serviceDivider, Enum.NormalId.Left, BURGUNDY_WALL, 32, 24)
	finish(box(f, "Divider_ConcessionsArcade", 120, 0, 102, 122, 28, 238,
		PAL.Partition), Enum.NormalId.Left, WALL_BASE, 18, 18)
	-- The concealed stair core occupies x[-354,-324] z[0,98]; split the low roof
	-- around it so the 62-stud ascent is not cut in half at y36.
	box(f, "ConcourseRoofWestEdge", -378, 36, -20, -354, 37, 102, PAL.Ceiling)
	box(f, "ConcourseRoofCoreNorth", -354, 36, -20, -324, 37, 0, PAL.Ceiling)
	box(f, "ConcourseRoofCoreSouth", -354, 36, 98, -324, 37, 102, PAL.Ceiling)
	box(f, "ConcourseRoofMain", -324, 36, -20, 378, 37, 102, PAL.Ceiling)
	box(f, "WestServiceRoof", -378, 28, 102, -121, 29, 240, PAL.Ceiling)
	box(f, "ConcessionRoof", -121, 28, 102, 121, 29, 240, PAL.FoyerCeiling)
	box(f, "ArcadeServiceRoof", 121, 28, 102, 378, 29, 240, PAL.Ceiling)
end

local function buildHall(model, hall, index)
	local id, xc = hall.Id, hall.X
	local scheme = HALL_COLORS[index]
	local hallCarpet = if index == 2 then "Blue" else "HallWarm"
	local f = folder(model, id)
	f:SetAttribute("CenterX", xc)
	local function b(name, u0, y0, z0, u1, y1, z1, color, mat, collide)
		return box(f, id .. "_" .. name, xc + u0, y0, z0, xc + u1, y1, z1, color, mat, collide)
	end

	-- Deck. The y0 screen apron z[-238,-204] is the base slab itself.
	carpet(overlay(f, id .. "_FrontApron", xc - 88, -238, xc + 88, -204, nil, nil, 2), hallCarpet)
	for i = 1, 8 do
		floor(b("FrontTier" .. i, -88, 0, -212 + 8 * i, 88, 2 * i, -204 + 8 * i), hallCarpet)
	end
	floor(b("CrossAisle", -88, 0, -140, 88, 18, -120), hallCarpet)
	b("CrossAisleEdge", -78, 18, -120.2, 78, 18.3, -120, scheme.Edge, NEON, false)
	for r = 1, 10 do
		floor(b("RearTier" .. r, -78, 0, -129 + 9 * r, 78, 18 + 3 * r, -120 + 9 * r), hallCarpet)
	end
	floor(b("TopWalk", -88, 0, -30, 88, 48, -22), hallCarpet)

	-- Side aisles climb in 1-stud treads: the raised back half of each front tier, then three
	-- per rear tier. A cyan dot marks every row-level riser.
	for _, s in AISLES do
		local u0, u1 = s[1], s[2]
		local uc = (u0 + u1) / 2
		for i = 0, 8 do
			floor(b("FrontAisleTread", u0, 2 * i, -208 + 8 * i, u1, 2 * i + 1, -204 + 8 * i, PAL.Aisle, FABRIC), hallCarpet)
		end
		for r = 1, 10 do
			for j = 0, 2 do
				local z0 = -129 + 9 * r + 3 * j
				floor(b("RearAisleTread", u0, 0, z0, u1, 16 + 3 * r + j, z0 + 3, PAL.Aisle, FABRIC), hallCarpet)
			end
		end
		for i = 1, 8 do
			b("StepDot", uc - 0.4, 2 * i - 0.35, -212.1 + 8 * i, uc + 0.4, 2 * i - 0.1, -212 + 8 * i, scheme.Edge, NEON, false)
		end
		for r = 1, 10 do
			b("StepDot", uc - 0.4, 17.65 + 3 * r, -123.1 + 9 * r, uc + 0.4, 17.9 + 3 * r, -123 + 9 * r, scheme.Edge, NEON, false)
		end
	end

	-- 18 rows x 22 chairs in two 11-chair banks, each chair (base, back) 4.4 wide and
	-- centred in its tier. The gap between banks is spacing only; the side aisles are the route.
	local function row(t, zm)
		for j = 0, 10 do
			for _, u in { -68 + 6 * j, 8 + 6 * j } do
				local x = xc + u
				tag(box(f, id .. "_ChairSeat", x - 2.2, t, zm - 1.6, x + 2.2, t + 2, zm + 1.6, scheme.Seat, FABRIC), SEAT_TAG)
				box(f, id .. "_ChairBack", x - 2.2, t + 1.2, zm + 1.6, x + 2.2, t + 5, zm + 2.2, scheme.Back, FABRIC)
			end
		end
	end
	for i = 1, 8 do
		row(2 * i, -208 + 8 * i)
	end
	for r = 1, 10 do
		row(18 + 3 * r, -124.5 + 9 * r)
	end

	-- Walls to the y80 roof. Both side walls open onto the cross aisle above a y18 sill;
	-- the east wall also carries the front-right exit at floor level.
	wall(f, id .. "_WallWest", "Z", -238, -22, xc - 90, xc - 88, 0, 80, scheme.Wall, SP, { { -136, -124, 18, 28 } })
	wall(f, id .. "_WallEast", "Z", -238, -22, xc + 88, xc + 90, 0, 80, scheme.Wall, SP,
		{ { -230, -218, 0, 10 }, { -136, -124, 18, 28 } })
	wall(f, id .. "_WallRear", "X", xc - 90, xc + 90, -22, -20, 0, 80, scheme.Wall, SP,
		{ { xc - 5, xc + 5, 62, 72 } })
	b("Roof", -90, 80, -240, 90, 81, -20, PAL.Ceiling)

	for side = -1, 1, 2 do
		local inner, outer = xc + side * 88, xc + side * 90
		doorway(f, id .. (if side < 0 then "_EntryWest" else "_EntryEast"), inner, 18, -136, outer, 28, -124)
		frame(f, id .. "_EntryFrame", "Z", inner, -side, -136, -124, 18, 28, scheme.Edge)
		frame(f, id .. "_EntryFrame", "Z", outer, side, -136, -124, 18, 28, scheme.Edge)
		local sign = box(f, id .. "_EntrySign", outer, 29, -134, outer + side * 0.3, 31, -126, PAL.Black, SP, false)
		label(sign, if side < 0 then Enum.NormalId.Left else Enum.NormalId.Right, "CINEMA " .. index, PAL.NeonAmber)
	end
	doorway(f, id .. "_FrontRightExit", xc + 88, 0, -230, xc + 90, 10, -218)
	frame(f, id .. "_ExitFrame", "Z", xc + 88, -1, -230, -218, 0, 10, PAL.Exit)
	frame(f, id .. "_ExitFrame", "Z", xc + 90, 1, -230, -218, 0, 10, PAL.Exit)
	local exitHinge = swingLeaf(f, id .. "_FrontExit",
		CFrame.new(xc + 89, 5, -229.5) * CFrame.Angles(0, -math.pi / 2, 0),
		11.2, 9.6, scheme.Wall, 95)
	swingZone(f, id .. "_FrontExit", CFrame.new(xc + 89, 5, -224)
		* CFrame.Angles(0, math.pi / 2, 0), Vector3.new(14, 10, 16), { exitHinge })
	label(b("ExitSign", 87.6, 11.5, -227, 88, 13.5, -221, PAL.Exit, NEON, false), Enum.NormalId.Left, "EXIT", PAL.White)
	label(b("ExitSignCorridor", 90, 11.5, -227, 90.4, 13.5, -221, PAL.Exit, NEON, false), Enum.NormalId.Right, "EXIT", PAL.White)

	-- Blank cream screen on the north wall with black masking.
	light(b("Screen", -58, 14, -238, 58, 62, -237.8, if index == 3 then PAL.DarkScreen else PAL.Screen),
		"SurfaceLight", PAL.ScreenGlow, scheme.Screen, 60, Enum.NormalId.Back, 80)
	for _, m in { { -61, 11, -58, 65 }, { 58, 11, 61, 65 }, { -58, 62, 58, 65 }, { -58, 11, 58, 14 } } do
		b("ScreenMask", m[1], m[2], -238, m[3], m[4], -237.6, PAL.Black, SP, false)
	end

	-- A3 is the unlit auditorium. Its screen and aisle markers provide only orientation.
	if index ~= 3 then
		for _, z in { -175, -80 } do
			local y = aisleY(z) + 9
			for side = -1, 1, 2 do
				glow(f, id .. "_Sconce", xc + side * 88, y, z - 1.5, xc + side * 87.6, y + 2, z + 1.5,
					if index == 1 then PAL.NeonAmber else PAL.NeonBlue, 0.4, 18)
			end
		end
		for _, u in { -50, 50 } do
			for _, z in { -190, -80 } do
				local fixture = glow(f, id .. "_CeilingLight", xc + u - 3, 79.4, z - 3,
					xc + u + 3, 80, z + 3, PAL.Warm, 0.45, 60)
				if u == -50 and z == -80 then fixture:SetAttribute("OccasionalFlicker", true) end
			end
		end
	end
	for side = -1, 1, 2 do
		for _, z in { -202, -174, -146, -108, -80, -52 } do
			b("AcousticPanel", side * 87.7, 10, z - 9, side * 87.9, 62, z + 9, scheme.Panel, FABRIC, false)
		end
		if index ~= 3 then
			b("WallCove", side * 87.7, 70, -238, side * 88, 70.4, -22, scheme.Edge, NEON, false)
		end
	end

	-- Projection booth high and centered at the rear, reached from the upper staff gallery.
	b("BoothFloor", -16, 61, -34, 16, 62, -22, PAL.Booth)
	b("BoothRoof", -16, 74, -34, 16, 75, -22, PAL.Booth)
	wall(f, id .. "_BoothNorth", "X", xc - 16, xc + 16, -34, -33, 62, 74, PAL.Booth, SP, { { xc - 10, xc + 10, 65, 70 } })
	wall(f, id .. "_BoothSouth", "X", xc - 16, xc + 16, -23, -22, 62, 74, PAL.Booth, SP,
		{ { xc - 5, xc + 5, 62, 72 } })
	b("BoothWest", -16, 62, -33, -15, 74, -23, PAL.Booth)
	b("BoothEast", 15, 62, -33, 16, 74, -23, PAL.Booth)
	doorway(f, id .. "_BoothDoor", xc - 5, 62, -23, xc + 5, 72, -19)
	frame(f, id .. "_BoothDoorFrame", "X", -23, -1, xc - 5, xc + 5, 62, 72, PAL.Frame)
	local boothHinge = swingLeaf(f, id .. "_BoothAccess",
		CFrame.new(xc - 4.6, 67, -21), 9.2, 9.6, PAL.Booth, -95)
	swingZone(f, id .. "_BoothAccess", CFrame.new(xc, 67, -21),
		Vector3.new(14, 10, 14), { boothHinge })
	b("BoothWindow", -10, 65, -33.7, 10, 70, -33.3, PAL.Glass, GLASS).Transparency = 0.5
	-- A full front support joins the booth to the top walk behind the last seats.
	b("BoothSupportWall", -16, 48, -23, 16, 61, -22, PAL.Booth)
	b("BoothFrontSupport", -16, 48, -34, 16, 61, -33.1, PAL.Booth)
	b("BoothFrontLintel", -16, 59, -34, 16, 61, -32, PAL.Metal, METAL)
	b("ProjectorStand", -9, 62, -30, -7, 65, -27, PAL.Metal, METAL)
	light(b("Projector", -9.8, 65, -32, -6.2, 70, -26, PAL.Metal, METAL), "PointLight",
		PAL.NeonAmber, if index == 3 then 0.05 else 0.6, 14)
	b("ProjectorLens", -8.7, 66.8, -32.4, -7.3, 68.2, -32,
		if index == 3 then scheme.Edge else PAL.Warm, NEON, false)
end

local function buildCorridor(model, c)
	local id = c.Id
	local f = folder(model, id)
	carpet(overlay(f, id .. "_ReturnCarpet", c.Return[1], -238,
		c.Return[2], -20, nil, nil, 2), "HallWarm")
	box(f, id .. "_Roof", c.Span[1], 32, -240, c.Span[2], 33, -20, PAL.Ceiling)
	-- fascia closes the roof step without cutting across the concourse ceiling.
	finish(box(f, id .. "_MouthFascia", c.Span[1], 33, -22, c.Span[2], 36, -19.9,
		PAL.CorridorWall), Enum.NormalId.Back, WALL_BASE, 28, 28)
	-- Thin cladding follows the real wall openings; the hall-facing walls stay dark teal.
	local function cladSide(name, x0, x1, face, frontExit)
		local cuts = { -238, -230, -218, -136, -124, -20 }
		for i = 1, #cuts - 1 do
			local z0, z1 = cuts[i], cuts[i + 1]
			local bands = if z0 == -136 then { { 0, 4, false }, { 4, 18, true }, { 28, 31, true } }
				elseif frontExit and z0 == -230 then { { 10, 31, true } }
				else { { 0, 4, false }, { 4, 31, true } }
			for _, band in bands do
				local p = box(f, name, x0, band[1], z0, x1, band[2], z1,
					if band[3] then PAL.CorridorWall else PAL.Charcoal, SP, false)
				if band[3] then finish(p, face, WALL_BASE, 28, 28) end
			end
		end
	end
	cladSide(id .. "_WestCladding", c.X0, c.X0 + 0.1, Enum.NormalId.Right, id ~= "C1")
	cladSide(id .. "_EastCladding", c.X1 - 0.1, c.X1, Enum.NormalId.Left, false)
	-- These entrance corridors use warm flush lamps and wall sconces instead of lobby neon.
	for _, z in { -183, -91, -35 } do
		box(f, id .. "_CeilingRecess", c.X0 + 16, 31.72, z - 1.5,
			c.X1 - 16, 32, z + 1.5, PAL.Charcoal, METAL, false)
		box(f, id .. "_CeilingLens", c.X0 + 18, 31.62, z - 0.5,
			c.X1 - 18, 31.73, z + 0.5, PAL.Warm, NEON, false)
	end
	-- full-height separators keep stair lanes and the return lane apart from z-145 to the concourse
	for _, s in c.Separators do
		local p = box(f, id .. "_Separator", s[1], 0, -145, s[2], 32, -20, PAL.CorridorWall)
		finish(p, Enum.NormalId.Left, WALL_BASE, 28, 28)
		finish(p, Enum.NormalId.Right, WALL_BASE, 28, 28)
		box(f, id .. "_SeparatorBaseWest", s[1] - 0.06, 0, -145, s[1] - 0.01, 4, -20, PAL.Charcoal, SP, false)
		box(f, id .. "_SeparatorBaseEast", s[2] + 0.01, 0, -145, s[2] + 0.06, 4, -20, PAL.Charcoal, SP, false)
		local dir = if s[2] <= c.Return[1] then 1 else -1
		local x = if dir > 0 then s[2] else s[1]
		local face = if dir > 0 then Enum.NormalId.Right else Enum.NormalId.Left
		box(f, id .. "_ReturnSconceMount", x, 10.8, -107, x + dir * 0.2, 15.2, -105,
			PAL.Black, METAL, false)
		box(f, id .. "_ReturnSconceTube", x + dir * 0.2, 11.2, -106.6,
			x + dir * 0.38, 14.8, -105.4, PAL.NeonAmber, NEON, false)
		box(f, id .. "_ReturnPosterFrame", x, 6, -74, x + dir * 0.12, 22, -64,
			PAL.Black, METAL, false)
		local art = box(f, id .. "_ReturnPosterArt", x + dir * 0.12, 6.7, -73.2,
			x + dir * 0.22, 20.3, -64.8, PAL.Black, SP, false)
		local decal = Instance.new("Decal")
		decal.Name = "MovieArtwork"
		decal.Face = face
		decal.Texture = POSTERS[tonumber(id:sub(2)) + 1][1]
		decal.Parent = art
	end
	-- Sparse sconces and framed artwork leave the twelve-stud auditorium doors clear.
	for _, side in { { c.X0, 1, Enum.NormalId.Right }, { c.X1, -1, Enum.NormalId.Left } } do
		local x, dir, face = side[1], side[2], side[3]
		for _, z in { -208, -92 } do
			box(f, id .. "_SconceMount", x + dir * 0.13, 10.8, z - 1, x + dir * 0.32, 15.2, z + 1,
				PAL.Black, METAL, false)
			box(f, id .. "_SconceTube", x + dir * 0.32, 11.2, z - 0.55, x + dir * 0.5, 14.8, z + 0.55,
				PAL.NeonAmber, NEON, false)
		end
		-- Only the outside return walls have floor clearance; stair-side posters clip treads.
		if (id == "C1" and dir > 0) or (id == "C4" and dir < 0) then
			local z = if dir > 0 then -180 else -76
			local poster = POSTERS[if dir > 0 then 3 else 5]
			box(f, id .. "_PosterFrame", x + dir * 0.13, 6, z - 5.2, x + dir * 0.22, 22, z + 5.2,
				PAL.Black, METAL, false)
			local art = box(f, id .. "_PosterArt", x + dir * 0.22, 6.7, z - 4.4,
				x + dir * 0.32, 20.3, z + 4.4, PAL.Black, SP, false)
			local decal = Instance.new("Decal")
			decal.Name = "MovieArtwork"
			decal.Face = face
			decal.Texture = poster[1]
			decal.Parent = art
			label(box(f, id .. "_PosterTitle", x + dir * 0.22, 4.6, z - 5.2,
				x + dir * 0.32, 6, z + 5.2, PAL.Black, METAL, false), face, poster[2], PAL.NeonAmber)
		end
	end
	for _, st in c.Stairs do
		local name, a, b = id .. "_Stair" .. st[1], st[2], st[3]
		local stairCarpet = if st[1]:find("A2") then "Blue" else "HallWarm"
		carpet(overlay(f, name .. "_GroundCarpet", a, -238, b, -20,
			nil, nil, 2), stairCarpet)
		for k = 1, 17 do
			floor(box(f, name .. "_Tread" .. k, a, 0, -30 - 5 * k, b, k, -25 - 5 * k,
				PAL.Aisle, FABRIC), stairCarpet)
			box(f, name .. "_AmberRiser", a + 0.3, k + 0.025, -25.12 - 5 * k,
				b - 0.3, k + 0.085, -25 - 5 * k,
				Color3.fromRGB(185, 96, 34), NEON, false)
		end
		floor(box(f, name .. "_Landing", a, 0, -145, b, 18, -115), stairCarpet)
		box(f, name .. "_LandingGuard", a, 18, -145, b, 31, -144, PAL.CorridorWall)
		for _, railX in { a + 0.35, b - 0.35 } do
			local foot = Vector3.new(railX, 5, -30)
			local top = Vector3.new(railX, 22, -115)
			part(f, name .. "_Handrail", Vector3.new(0.35, 0.35, (top - foot).Magnitude),
				CFrame.lookAt((foot + top) / 2, top), PAL.Charcoal, METAL, false)
		end
		local doorSide = if st[1]:find("West") then 1 else -1
		box(f, name .. "_LandingRail", if doorSide > 0 then a + 0.25 else b - 0.6,
			22, -141, if doorSide > 0 then a + 0.6 else b - 0.25, 22.35, -115,
			PAL.Charcoal, METAL, false)
		local hallNumber = st[1]:match("A(%d)")
		local turn = if doorSide > 0 then "CINEMA " .. hallNumber .. " >" else "< CINEMA " .. hallNumber
		label(box(f, name .. "_TurnSign", a + 1, 24, -143.9, b - 1, 27, -143.7,
			PAL.Black, METAL, false), Enum.NormalId.Back, turn, PAL.NeonAmber)
		for _, z in { -130, -70 } do
			glow(f, name .. "_Light", a + 2, 31.4, z - 2, b - 2, 32, z + 2, PAL.Warm, 0.7, 24)
		end
	end
	local rc = (c.Return[1] + c.Return[2]) / 2
	for _, z in { -225, -130, -40 } do
		glow(f, id .. "_ReturnLight", rc - 2, 31.4, z - 3, rc + 2, 32, z + 3, PAL.Warm, 0.8, 40)
	end
end

-- Enclosed service circulation: one supported stair flight to y62, then one
-- gallery behind the three rear projection booths.
local function buildHiddenService(model)
	local f = folder(model, "HiddenService")
	carpet(overlay(f, "StaffGroundRunner", -354, 2, -324, 98, nil, nil, 2), "ServiceStair")

	-- This full-height core occupies the hole deliberately left in the y36 concourse roof.
	finish(box(f, "CoreWest", -354, 0, 0, -352, 76, 98, PAL.CorridorWall), Enum.NormalId.Right,
		WALL_BASE, 14, 14)
	wall(f, "CoreEast", "Z", 0, 98, -326, -324, 0, 76, PAL.Teal, SP,
		{ { 86, 96, 0, 12 } })
	-- Fill the six-stud void beside the flight; right-hand lamps mount to its west face.
	box(f, "CoreEastStairInfill", -332, 0, 8, -325.9, 76, 86, PAL.Teal)
	finish(box(f, "CoreSouth", -354, 0, 96, -324, 76, 98, PAL.Teal), Enum.NormalId.Front,
		"rbxassetid://78643712450081", 14, 14)
	wall(f, "CoreNorth", "X", -354, -324, 0, 2, 0, 76, PAL.Teal, SP,
		{ { -334, -326, 62, 72 } })
	box(f, "CoreRoof", -354, 76, 0, -324, 77, 98, PAL.Ceiling)
	doorway(f, "SecretPosterEntry", -326, 0, 86, -324, 12, 96)
	doorway(f, "GalleryStairEntry", -334, 62, 0, -326, 72, 2)
	local posterHinge = swingLeaf(f, "SecretPoster",
		CFrame.new(-325, 6, 86.4) * CFrame.Angles(0, -math.pi / 2, 0),
		9.2, 11.5, PAL.Black, -95)
	posterHinge:SetAttribute("FixedOpenAngle", 95)
	posterHinge:SetAttribute("NonBlockingWhenOpen", true)
	swingZone(f, "SecretPoster", CFrame.new(-325, 6, 91)
		* CFrame.Angles(0, math.pi / 2, 0), Vector3.new(14, 12, 26),
		{ posterHinge })
	local panel = posterHinge.Attachment1.Parent
	panel:SetAttribute("ConcealedEntrance", true)
	local art = Instance.new("Decal")
	art.Name = "LastShowingArt"
	art.Face = Enum.NormalId.Front
	art.Texture = "rbxassetid://78063750109486"
	art.Parent = panel
	frame(f, "ConcealedPosterFrame", "Z", -324, 1, 86, 96, 0, 12, PAL.Frame)
	local galleryHinge = swingLeaf(f, "GalleryStair",
		CFrame.new(-333.8, 67, 1), 7.5, 9.6, PAL.Booth, -95)
	swingZone(f, "GalleryStair", CFrame.new(-330, 67, 1),
		Vector3.new(12, 10, 14), { galleryHinge })
	for _, p in f:GetChildren() do
		if p:IsA("BasePart") then
			if p.Name:find("^CoreEast") then
				finish(p, Enum.NormalId.Left, SERVICE_TEAL, 16, 16)
				finish(p, Enum.NormalId.Right, WALL_BASE, 14, 14)
			elseif p.Name:find("^CoreNorth") then
				finish(p, Enum.NormalId.Back, SERVICE_TEAL, 16, 16)
			end
		end
	end
	for _, z in { 2, 98 } do
		box(f, "CoreBaseboard", -352, 0, z - 0.2, -326, 3, z, PAL.Charcoal, SP, false)
	end

	-- One full-width flight rises from the south vestibule to the gallery.
	-- Every other tread carries an amber nose.
	local eastX0, eastX1 = -352, -332
	local northZ, southZ, run = 8, 90, 82 / 62
	floor(box(f, "EastEntryConnector", -332, -0.1, 86,
		-326, 0, 96), "ServiceStair")
	for k = 1, 62 do
		local z0 = southZ - k * run
		local z1 = z0 + run
		floor(box(f, "EastFlight_Tread" .. k, eastX0, 0, z0,
			eastX1, k, z1), "ServiceStair")
		if k % 2 == 0 then
			box(f, "EastFlight_AmberNosing", eastX0 + 0.3,
				k + 0.025, z0, eastX1 - 0.3, k + 0.085, z0 + 0.14,
				Color3.fromRGB(185, 96, 34), NEON, false)
		end
	end
	floor(box(f, "NorthGalleryLanding", eastX0, 61.4, 2,
		-326, 62, northZ), "ServiceStair")
	local function rail(name, x)
		local a = Vector3.new(x, 3.5, southZ)
		local b = Vector3.new(x, 65.5, northZ)
		part(f, name, Vector3.new(0.75, 0.75, (b - a).Magnitude),
			CFrame.lookAt((a + b) / 2, b), Color3.fromRGB(125, 89, 60), METAL, false)
	end
	rail("WestFlight_WallHandrail", eastX0 + 0.4)
	rail("EastFlight_WallHandrail", eastX1 - 0.4)
	for _, lamp in { { "WestStairLamp", eastX0, 23, 66 },
		{ "EastStairLamp", eastX1, 23, 66 },
		{ "WestMiddleLamp", eastX0, 38, 47 }, { "EastMiddleLamp", eastX1, 38, 47 },
		{ "WestUpperLamp", eastX0, 52, 28 },
		{ "EastUpperLamp", eastX1, 52, 28 } } do
		local wallX = if lamp[2] == eastX0 then eastX0 + 0.1 else eastX1 - 0.4
		local backX = if lamp[2] == eastX0 then wallX - 0.18 else wallX + 0.27
		box(f, lamp[1] .. "Backplate", backX, lamp[3] - 0.35, lamp[4] - 0.35,
			backX + 0.2, lamp[3] + 4.35, lamp[4] + 2.35,
			PAL.Charcoal, METAL, false)
		glow(f, lamp[1], wallX, lamp[3], lamp[4], wallX + 0.3,
			lamp[3] + 4, lamp[4] + 2, PAL.NeonAmber, 0.28, 18)
		local cageX = if lamp[2] == eastX0 then wallX + 0.32 else wallX - 0.12
		for _, z in { lamp[4] - 0.22, lamp[4] + 2.02 } do
			box(f, lamp[1] .. "CageSide", cageX, lamp[3] - 0.2, z,
				cageX + 0.12, lamp[3] + 4.2, z + 0.16, PAL.Charcoal, METAL, false)
		end
		for _, y in { lamp[3] - 0.2, lamp[3] + 2, lamp[3] + 4.04 } do
			box(f, lamp[1] .. "CageEnd", cageX, y, lamp[4] - 0.22,
				cageX + 0.12, y + 0.16, lamp[4] + 2.18, PAL.Charcoal, METAL, false)
		end
	end
	-- Gallery floor touches the booths' aligned y62 rear thresholds. The low public
	-- concourse roof remains directly beneath it, with a closed fascia on its south face.
	floor(box(f, "GalleryFloor", -376, 61, -20, 376, 62, 0), "Service")
	box(f, "GalleryRoof", -376, 75, -20, 376, 76, 0, PAL.Ceiling)
	wall(f, "GalleryNorth", "X", -376, 376, -20, -19, 62, 75, PAL.Teal, SP,
		{ { -239, -229, 62, 72 }, { -5, 5, 62, 72 }, { 229, 239, 62, 72 } })
	finish(box(f, "GallerySouthWest", -376, 62, 0, -354, 75, 2, PAL.Teal),
		Enum.NormalId.Front, "rbxassetid://78643712450081", 14, 14)
	box(f, "GallerySouthWestFascia", -376, 37, 0, -354, 62, 2, PAL.CorridorWall)
	finish(box(f, "GallerySouth", -324, 62, 0, 376, 75, 2, PAL.Teal), Enum.NormalId.Front,
		"rbxassetid://78643712450081", 14, 14)
	box(f, "GallerySouthFascia", -324, 37, 0, 376, 62, 2, PAL.CorridorWall)
	finish(box(f, "GalleryWest", -378, 62, -20, -376, 75, 0, PAL.Teal), Enum.NormalId.Right,
		"rbxassetid://78643712450081", 14, 14)
	finish(box(f, "GalleryEast", 376, 62, -20, 378, 75, 0, PAL.Teal), Enum.NormalId.Left,
		"rbxassetid://78643712450081", 14, 14)
	for _, p in f:GetChildren() do
		if p:IsA("BasePart") and p.Name:find("^GalleryNorth") then
			finish(p, Enum.NormalId.Back, "rbxassetid://78643712450081", 14, 14)
		end
	end
	local coveColor = Color3.fromRGB(150, 100, 58)
	box(f, "GalleryNorthCove", -374, 73.6, -18.5, 374, 74, -18.2, coveColor, NEON, false)
	local function curveZ(x)
		return -4.5 + 2.5 * math.cos(2 * math.pi * x / 234)
	end
	local function curvePart(name, xa, xb, y0, y1, thickness, zOffset, color, mat, collide)
		local a = Vector3.new(xa, (y0 + y1) / 2, curveZ(xa) + zOffset)
		local b = Vector3.new(xb, (y0 + y1) / 2, curveZ(xb) + zOffset)
		return part(f, name, Vector3.new(thickness, y1 - y0, (b - a).Magnitude + 0.08),
			CFrame.lookAt((a + b) / 2, b), color, mat, collide)
	end
	local function curveMount(name, x, y0, y1, width, zOffset, thickness, color, mat)
		local center = Vector3.new(x, (y0 + y1) / 2, curveZ(x) + zOffset)
		local aim = Vector3.new(x + 1, (y0 + y1) / 2, curveZ(x + 1) + zOffset)
		return part(f, name, Vector3.new(thickness, y1 - y0, width),
			CFrame.lookAt(center, aim), color, mat, false)
	end
	-- The old south wall seals the space behind the skin; returns cap both ends.
	for _, endCap in { { -300, Enum.NormalId.Left }, { 352, Enum.NormalId.Right } } do
		local x, face = endCap[1], endCap[2]
		local cap = box(f, "GalleryCurveReturn", x, 62, curveZ(x), x + 1, 75, 0, PAL.Teal)
		finish(cap, face, "rbxassetid://78643712450081", 14, 14)
		local outerX = if x < 0 then x - 0.18 else x + 1.18
		box(f, "GalleryCurveReturnBase", x < 0 and outerX or x + 1, 62, curveZ(x),
			x < 0 and x + 0.02 or outerX, 64, 0, PAL.Charcoal, SP, false)
	end
	for _, landing in { { -324, -300 }, { 352, 376 } } do
		box(f, "GallerySouthSkirting", landing[1], 62, -0.4, landing[2], 64, -0.2,
			PAL.Charcoal, SP, false)
		box(f, "GallerySouthCove", landing[1], 72.4, -0.7, landing[2], 72.8, -0.4,
			coveColor, NEON, false)
	end
	box(f, "GalleryWestCurveCoveReturn", -300.18, 72.4, curveZ(-300) + 0.2,
		-299.94, 72.8, -0.45, coveColor, NEON, false)
	box(f, "GalleryEastCurveCoveReturn", 352.94, 72.4, curveZ(352) + 0.2,
		353.18, 72.8, -0.45, coveColor, NEON, false)
	box(f, "GalleryEastCurveCoveInside", 351.82, 72.4, curveZ(352) + 0.2,
		352.06, 72.8, -0.45, coveColor, NEON, false)
	box(f, "GalleryEastCurveCoveTip", 351.86, 72.4, curveZ(352) - 0.15,
		353.18, 72.8, curveZ(352) + 0.24, coveColor, NEON, false)
	local steps = 24
	for i = 0, steps - 1 do
		local xa = -300 + 652 * i / steps
		local xb = -300 + 652 * (i + 1) / steps
		finish(curvePart("GalleryCurvePanel", xa, xb, 62, 72.2, 1, 0.5,
			PAL.Teal, SP, true), Enum.NormalId.Left, "rbxassetid://78643712450081", 14, 14)
		curvePart("GalleryCurveSkirting", xa, xb, 62, 64, 0.16, -0.05,
			PAL.Charcoal, SP, false)
		curvePart("GalleryCurveBacker", xa, xb, 72.2, 73, 0.4, 0.8,
			PAL.Charcoal, SP, true)
		finish(curvePart("GalleryCurveValence", xa, xb, 73, 75, 1, 0.5,
			PAL.Teal, SP, true), Enum.NormalId.Left, "rbxassetid://78643712450081", 14, 14)
		curvePart("GalleryCurveCove", xa, xb, 72.4, 72.8, 0.4, 0.3,
			coveColor, NEON, false)
		for _, side in { -1, 1 } do
			local a = Vector3.new(xa, 62.035, (curveZ(xa) - 20) / 2 + side * 2.5)
			local b = Vector3.new(xb, 62.035, (curveZ(xb) - 20) / 2 + side * 2.5)
			part(f, "GalleryRunnerEdge", Vector3.new(0.14, 0.06, (b - a).Magnitude + 0.08),
				CFrame.lookAt((a + b) / 2, b), PAL.Metal, METAL, false)
		end
	end
	for i = 0, steps do
		local x = -300 + 652 * i / steps
		part(f, "GalleryCurveCoveJoint", Vector3.new(0.44, 0.44, 0.44),
			CFrame.new(x, 72.6, curveZ(x) + 0.3), coveColor, NEON, false, Enum.PartType.Ball)
	end
	for _, side in { -1, 1 } do
		for _, ends in {
			{ Vector3.new(-374, 62.035, -13.5 + side * 2.5),
				Vector3.new(-300, 62.035, (curveZ(-300) - 20) / 2 + side * 2.5) },
			{ Vector3.new(352, 62.035, (curveZ(352) - 20) / 2 + side * 2.5),
				Vector3.new(374, 62.035, -13.5 + side * 2.5) },
		} do
			local a, b = ends[1], ends[2]
			part(f, "GalleryRunnerLandingEdge", Vector3.new(0.14, 0.06, (b - a).Magnitude + 0.08),
				CFrame.lookAt((a + b) / 2, b), PAL.Metal, METAL, false)
		end
	end
	for _, x in { -330, -270, -210, -150, -90, -30, 30, 90, 150, 210, 270, 330 } do
		glow(f, "GalleryLamp", x - 2, 74.6, -11, x + 2, 75, -9, coveColor, 0.35, 23)
	end
	for _, x in { -312, -270, -210, -150, -90, -30, 30, 90, 150, 210, 270, 330 } do
		local sconce = if x < -300 then box(f, "GallerySconce", x - 0.7, 67, -0.8,
			x + 0.7, 70, -0.55, PAL.Metal, METAL, false)
			else curveMount("GallerySconce", x, 67, 70, 1.4, -0.15, 0.32, PAL.Metal, METAL)
		light(sconce, "PointLight", PAL.NeonAmber, 0.45, 20)
	end
	for index, hall in HALLS do
		frame(f, hall.Id .. "_GalleryBoothFrame", "X", -19, 1, hall.X - 5, hall.X + 5, 62, 72, PAL.Frame)
		local sign = box(f, hall.Id .. "_GallerySign", hall.X + 7, 67, -18.8,
			hall.X + 20, 69.4, -18.55, PAL.Charcoal, METAL, false)
		label(sign, Enum.NormalId.Back, "PROJECTION " .. index, PAL.Warm)
	end
	-- Numbered maintenance doors and vents are closed surface details, not new routes.
	for index, x in { -180, -45, 105, 300 } do
		curveMount("GalleryServicePanel", x, 62.6, 71.5, 8, -0.08, 0.25, PAL.Booth, METAL)
		for _, offset in { -4.15, 4.15 } do
			curveMount("GalleryServiceJamb", x + offset, 62.4, 72.1, 0.5,
				-0.23, 0.4, PAL.Metal, METAL)
		end
		curveMount("GalleryServiceHeader", x, 71.5, 72.1, 8.8, -0.23, 0.4,
			PAL.Metal, METAL)
		label(curveMount("GalleryServiceNumber", x, 69.9, 71.2, 3.3, -0.32, 0.14,
			PAL.Charcoal, METAL), Enum.NormalId.Left, string.format("%02d", index), PAL.Warm)
		label(curveMount("GalleryServiceClosed", x, 64.3, 65.4, 4.8, -0.32, 0.14,
			PAL.Charcoal, METAL), Enum.NormalId.Left, "LOCKED", PAL.Warm)
		curveMount("GalleryServiceLatch", x + 2.8, 66, 67, 0.35, -0.34, 0.18,
			PAL.Chrome, METAL)
	end
	for _, x in { -255, 55, 190 } do
		curveMount("GalleryVentCase", x, 67, 71, 8, -0.14, 0.35, PAL.Metal, METAL)
		for i = 1, 3 do
			curveMount("GalleryVentSlat", x, 67.6 + i, 67.85 + i, 6.8,
				-0.36, 0.13, PAL.Charcoal, METAL)
		end
	end
end

local function buildConcourse(model)
	local f = folder(model, "Concourse")
	-- Public carpet and four south thresholds are one continuous shell finish.
	-- Broad terracotta columns frame the paired views into the auditorium corridors.
	for _, x in { -280, -110, 110, 280 } do
		for _, z in { 30, 70 } do
			disc(f, "ConcourseColumn", x, z, 8, 0, 36, PAL.Charcoal, Enum.Material.Granite)
			disc(f, "ConcourseColumnBase", x, z, 8.6, 0, 3, PAL.Charcoal)
			disc(f, "ConcourseColumnAmberCollar", x, z, 8.3, 34.9, 35.15, PAL.NeonAmber, NEON, false)
			-- Twelve tangent faces keep the stone wear while reading as a round column.
			local radius = 4.05
			local width = 2 * radius * math.tan(math.pi / 12) + 0.03
			for facet = 0, 11 do
				local angle = facet * math.pi / 6
				local outward = Vector3.new(math.cos(angle), 0, math.sin(angle))
				local center = Vector3.new(x, 18.9, z) + outward * radius
				local stone = part(f, "ColumnWornStone", Vector3.new(width, 31.8, 0.12),
					CFrame.lookAt(center, center + outward), PAL.Charcoal, SP, false)
				finish(stone, Enum.NormalId.Front, "rbxassetid://93523123874495", 8, 8)
				local texture = stone:FindFirstChild("WallFinish")
				texture.OffsetStudsU = facet * width
			end
		end
	end
	-- One warm perimeter line leaves cyan for the booth and arcade focal points.
	box(f, "Cove_South", -376, 34.7, 99.75, 376, 34.9, 100, PAL.NeonRed, NEON, false)
	box(f, "Cove_East", 375.75, 34.7, -20, 376, 34.9, 100, PAL.NeonRed, NEON, false)
	box(f, "Cove_Core", -324.25, 34.7, 0, -324, 34.9, 98, PAL.NeonRed, NEON, false)
	box(f, "Cove_WestMouth", -376, 34.7, -20, -375.75, 34.9, 0, PAL.NeonRed, NEON, false)
	for k = 0, 7 do
		for _, z in { 15, 65 } do
			light(disc(f, "Downlight", -280 + 80 * k, z, 5, 35.7, 36, PAL.NeonWarmWhite, NEON, false), "PointLight", PAL.Warm, 0.7, 45)
		end
	end

	-- Terracotta theater blocks and portrait posters face the public concourse.
	for i, hall in HALLS do
		local xc = hall.X
		box(f, hall.Id .. "_RearWainscot", xc - 90, 0, -20, xc + 90, 4, -19.85, PAL.Charcoal, SP, false)
		local rearCuts = { xc - 90, xc - 38, xc + 38, xc + 90 }
		for bay = 1, #rearCuts - 1 do
			finish(box(f, hall.Id .. "_RearPlaster", rearCuts[bay], 4, -20,
				rearCuts[bay + 1], 35.5, -19.85, PAL.CorridorWall, SP, false),
				Enum.NormalId.Back, if bay == 1 then WALL_EDGE else WALL_BASE,
				rearCuts[bay + 1] - rearCuts[bay], 32)
		end
		for _, u in { -88, -38, 38, 88 } do
			box(f, hall.Id .. "_PilasterBase", xc + u - 2, 0, -20, xc + u + 2, 4, -17.7,
				PAL.Charcoal, SP, false)
			finish(box(f, hall.Id .. "_Pilaster", xc + u - 2, 4, -20, xc + u + 2, 32, -17.9,
				PAL.CorridorWall, SP, false), Enum.NormalId.Back, WALL_BASE, 28, 28)
		end
		finish(box(f, hall.Id .. "_ProjectingCornice", xc - 90, 32, -20, xc + 90, 36, -18.1,
			PAL.CorridorWall, SP, false), Enum.NormalId.Back, WALL_BASE, 28, 28)
		box(f, hall.Id .. "_CorniceCove", xc - 90, 34.4, -18.1,
			xc + 90, 34.6, -18, PAL.NeonRed, NEON, false)
		for _, edge in { xc - 90, xc + 90 } do
			box(f, hall.Id .. "_CorniceReturn", edge - 0.1, 34.4, -20,
				edge + 0.1, 34.6, -18.1, PAL.NeonRed, NEON, false)
		end
		for _, x in { xc - 26, xc + 26 } do
			box(f, hall.Id .. "_MarqueeBracket", x - 0.6, 22, -19.85, x + 0.6, 25, -17.7,
				PAL.Metal, METAL, false)
		end
		label(box(f, hall.Id .. "_Marquee", xc - 30, 20, -17.75, xc + 30, 27, -17.45, PAL.Black, SP, false),
			Enum.NormalId.Back, "CINEMA " .. i, PAL.NeonAmber)
		glow(f, hall.Id .. "_MarqueeTrim", xc - 30, 19.4, -17.8, xc + 30, 19.8, -17.4, PAL.NeonRed, 0.8, 20)
		for j, s in { -1, 1 } do
			local x = xc + s * 60
			local poster = POSTERS[((i - 1) * 2 + j - 1) % #POSTERS + 1]
			box(f, hall.Id .. "_PosterFrame", x - 7.6, 4, -19.8, x + 7.6, 24, -19.55, PAL.Black, METAL, false)
			local art = box(f, hall.Id .. "_PosterArt", x - 6.8, 4.7, -19.55, x + 6.8, 23.3, -19.4, PAL.Black, SP, false)
			local decal = Instance.new("Decal")
			decal.Name = "MovieArtwork"
			decal.Face = Enum.NormalId.Back
			decal.Texture = poster[1]
			decal.Parent = art
			label(box(f, hall.Id .. "_PosterTitle", x - 7.6, 2.5, -19.8, x + 7.6, 4, -19.55,
				PAL.Black, METAL, false), Enum.NormalId.Back,
				poster[2], PAL.NeonAmber)
		end
	end

	-- Reserve the matching light-wear variant for the ends of each wall run.
	local panelIndex = 0
	for i, span in { { -376, -146 }, { -126, 55 }, { 95, 150 }, { 178, 280 }, { 296, 376 } } do
		local x0, x1 = span[1], span[2]
		local cuts = { x0 }
		for x = x0 + 28, x1 - 28, 56 do table.insert(cuts, x) end
		table.insert(cuts, x1)
		for n = 1, #cuts - 1 do
			panelIndex += 1
			local asset = if n == 1 or n == #cuts - 1 then WALL_EDGE else WALL_BASE
			local plaster = box(f, "SouthFacadePlaster", cuts[n], 4, 99.72,
				cuts[n + 1], 31.5, 99.94, PAL.CorridorWall, SP, false)
			local texture = finish(plaster, Enum.NormalId.Front, asset, 56, 32)
			texture:FindFirstChild("WallFinish").OffsetStudsU = panelIndex * 11
			for _, band in { { 33.15, 34.6 }, { 35, 36 } } do
				finish(box(f, "SouthFacadeUpperPlaster", cuts[n], band[1], 99.72,
					cuts[n + 1], band[2], 99.94, PAL.CorridorWall, SP, false),
					Enum.NormalId.Front, asset, 56, 32)
			end
		end
		box(f, "SouthFacadeWainscot", x0, 0, 99.55, x1, 4, 99.94, PAL.Charcoal, SP, false)
		box(f, "SouthFacadeCornice", x0, 31.5, 99.5, x1, 33.15, 99.94,
			PAL.Charcoal, METAL, false)
		for x = x0 + 28, x1 - 28, 56 do
			box(f, "SouthPilasterBase", x - 1.6, 0, 98.95, x + 1.6, 4, 99.7,
				PAL.Charcoal, SP, false)
			finish(box(f, "SouthPilaster", x - 1.6, 4, 99.05, x + 1.6, 31.5, 99.7,
				PAL.CorridorWall, SP, false), Enum.NormalId.Front,
				WALL_BASE, 18, 32)
		end
	end
	-- Continue the roofline finish across every signed opening.
	for _, opening in SOUTH_OPENINGS do
		box(f, "SouthFacadeCornice", opening[1] - 0.03, 31.5, 99.5,
			opening[2] + 0.03, 33.15, 99.94, PAL.Charcoal, METAL, false)
		for _, band in { { 33.15, 34.6 }, { 35, 36 } } do
			finish(box(f, "SouthFacadeUpperPlaster", opening[1], band[1], 99.72,
				opening[2], band[2], 99.94, PAL.CorridorWall, SP, false),
				Enum.NormalId.Front, WALL_BASE, 56, 32)
		end
	end
	for _, pair in {
			{ -310, -216, 3, 4 }, { -95, 130, 5, 1 }, { 215, 250, 2, 3 }, { 310, 350, 4, 5 },
		} do
			for i, x in pair do
				if i > 2 then break end
				local poster = POSTERS[pair[i + 2]]
			box(f, "SouthPosterFrame", x - 6, 5, 99.14, x + 6, 25, 99.78,
				PAL.Black, METAL, false)
			local art = box(f, "SouthPosterArt", x - 5.2, 7.3, 98.98, x + 5.2, 24, 99.16,
				PAL.Black, SP, false)
			local decal = Instance.new("Decal")
			decal.Name = "MovieArtwork"
			decal.Face = Enum.NormalId.Front
				decal.Texture = poster[1]
			decal.Parent = art
			label(box(f, "SouthPosterTitle", x - 5.2, 5.25, 98.98, x + 5.2, 7.1, 99.16,
				PAL.Black, METAL, false), Enum.NormalId.Front,
					poster[2], PAL.NeonAmber)
		end
		local middle = (pair[1] + pair[2]) / 2
		box(f, "SouthSconceMount", middle - 1, 12, 99.12, middle + 1, 17, 99.76,
			PAL.Black, METAL, false)
		light(box(f, "SouthSconceTube", middle - 0.32, 12.7, 98.89, middle + 0.32, 16.3, 99.15,
			PAL.NeonAmber, NEON, false), "PointLight", PAL.Warm, 0.28, 14)
	end
	-- Ticket sales share the spawn room's back counter with concessions.
	for _, x in { -98, 66 } do
		box(f, "LobbyBenchSeat", x, 0, 72, x + 32, 2.2, 78, PAL.Seat, FABRIC)
		box(f, "LobbyBenchBack", x, 2.2, 76.5, x + 32, 6.2, 78.5, PAL.SeatBack, FABRIC)
	end
	-- Sparse open-floor tables and low wall seating leave the fork and doors clear.
	for _, spot in { { -250, 55 }, { -175, 55 }, { -50, 55 },
		{ 30, 60 }, { 100, 52 }, { 175, 55 }, { 250, 55 } } do
		standingTable(f, "LobbyTable", spot[1], spot[2])
	end
	box(f, "LobbySofaSeat", 118, 0, 48, 158, 3, 55, PAL.Seat, FABRIC)
	box(f, "LobbySofaBack", 118, 3, 53, 158, 7, 56, PAL.SeatBack, FABRIC)
	for _, x in { 116, 160 } do
		box(f, "LobbySofaArm", x - 2, 0, 48, x + 2, 5, 56, PAL.Charcoal, METAL)
	end
	for _, spot in { { -300, 84 }, { -205, 84 }, { 35, 35 }, { 35, 96 },
		{ 160, -7 }, { 140, 86 }, { 205, 84 }, { 350, 84 } } do
		local x, z = spot[1], spot[2]
		standingTable(f, "WallCafeTable", x, z)
		-- The near-right pair is viewed edge-on if arranged along X.
		local chairs = if x == 350 then { { x, z - 6, 0, -1 }, { x, z + 6, 0, 1 } }
			else { { x - 6, z - 2, -1, 0 }, { x + 6, z - 2, 1, 0 } }
		for _, chair in chairs do
			local chairX, chairZ, backX, backZ = table.unpack(chair)
			local chairSeat = Instance.new("Seat")
			chairSeat.Name = "WallCafeChairSeat"
			chairSeat.Anchored = true
			chairSeat.Size = Vector3.new(4, 0.8, 4)
			chairSeat.CFrame = origin * CFrame.lookAt(
				Vector3.new(chairX, 1.9, chairZ),
				Vector3.new(chairX - backX * 6, 1.9, chairZ - backZ * 6))
			chairSeat.Color = Color3.fromRGB(100, 34, 39)
			chairSeat.Material = FABRIC
			chairSeat.TopSurface = Enum.SurfaceType.Smooth
			chairSeat.BottomSurface = Enum.SurfaceType.Smooth
			chairSeat.Parent = f
			if backX ~= 0 then
				box(f, "WallCafeChairBack", chairX + backX * 1.6, 2.3, chairZ - 2,
					chairX + backX * 2.2, 5.2, chairZ + 2,
					Color3.fromRGB(75, 25, 30), FABRIC)
			else
				box(f, "WallCafeChairBack", chairX - 2, 2.3, chairZ + backZ * 1.6,
					chairX + 2, 5.2, chairZ + backZ * 2.2,
					Color3.fromRGB(75, 25, 30), FABRIC)
			end
			for _, legX in { chairX - 1.6, chairX + 1.6 } do
				for _, legZ in { chairZ - 1.6, chairZ + 1.6 } do
					box(f, "WallCafeChairLeg", legX - 0.14, 0, legZ - 0.14,
						legX + 0.14, 1.5, legZ + 0.14,
						Color3.fromRGB(126, 104, 75), METAL, false)
				end
			end
		end
	end
	-- Framed, signed openings into the south rooms.
	for _, o in SOUTH_OPENINGS do
		frame(f, o[5] .. "Frame", "X", 100, -1, o[1], o[2], 0, 12, PAL.NeonRed)
		box(f, o[5] .. "DeepJamb", o[1] - 1.2, 0, 99.1, o[1], 13.4, 99.95,
			PAL.Charcoal, METAL, false)
		box(f, o[5] .. "DeepJamb", o[2], 0, 99.1, o[2] + 1.2, 13.4, 99.95,
			PAL.Charcoal, METAL, false)
		box(f, o[5] .. "DeepHeader", o[1] - 1.2, 12, 99.1, o[2] + 1.2, 13.4, 99.95,
			PAL.Charcoal, METAL, false)
		label(box(f, o[5] .. "Sign", o[1], 14, 99.6, o[2], 17.5, 100, PAL.Black, SP, false), Enum.NormalId.Front, o[6], PAL.NeonAmber)
	end
end

-- The two public corridors branch around a sealed terracotta theater block.
-- Exact outer vertices and cove lines follow Claude's measured V5 sketch.
local function buildFork(model)
	local f = folder(model, "CentralFork")
	for side, spec in {
		{ "West", Vector2.new(-90, -20), Vector2.new(-10, 40), Vector2.new(0.6, -0.8) },
		{ "East", Vector2.new(90, -20), Vector2.new(10, 40), Vector2.new(-0.6, -0.8) },
	} do
		local name, a, b, inward = spec[1], spec[2], spec[3], spec[4]
		local middle = (a + b) / 2
		local length = (b - a).Magnitude
		local function panel(suffix, y0, y1, depth, thickness, color, mat, collide)
			local center = Vector3.new(middle.X + inward.X * depth, (y0 + y1) / 2,
				middle.Y + inward.Y * depth)
			local aim = Vector3.new(b.X + inward.X * depth, (y0 + y1) / 2,
				b.Y + inward.Y * depth)
			return part(f, name .. suffix, Vector3.new(thickness, y1 - y0, length + 0.1),
				CFrame.lookAt(center, aim), color, mat, collide)
		end
		local base = panel("Plaster", 0, 29.6, 1, 2, PAL.CorridorWall, SP)
		local fascia = panel("Fascia", 32, 36, 1, 2, PAL.CorridorWall, SP)
		panel("CoveBacker", 29.6, 32, 1.5, 1, PAL.Charcoal, SP)
		for _, p in { base, fascia } do
			finish(p, Enum.NormalId.Left, WALL_BASE, 42, 32)
			finish(p, Enum.NormalId.Right, WALL_BASE, 42, 32)
		end
		panel("Wainscot", 0, 3, -0.05, 0.12, PAL.Charcoal, SP, false)
		local along = (b - a).Unit
		local exteriorFace = if name == "West" then Enum.NormalId.Right else Enum.NormalId.Left
		local function mounted(suffix, distance, y0, y1, width, depth, thickness, color, mat)
			local position = a + along * distance + inward * depth
			local center = Vector3.new(position.X, (y0 + y1) / 2, position.Y)
			return part(f, name .. suffix, Vector3.new(thickness, y1 - y0, width),
				CFrame.lookAt(center, center + Vector3.new(along.X, 0, along.Y)), color, mat, false)
		end
		-- Solid plaster remains behind these shallow, visibly boarded cinema portals.
		local portalStation, posterStation = 40, 88
		mounted("Cornice", length / 2, 27.5, 28.8, length, -0.27, 0.6, PAL.Charcoal, METAL)
		mounted("CorniceEdge", length / 2, 28.7, 28.85, length, -0.61, 0.16, PAL.Tan, METAL)
		mounted("ClosedPortalFrame", portalStation, 3, 25.5, 16, -0.18, 0.4, PAL.Black, METAL)
		mounted("ClosedPortalPanel", portalStation, 4, 23.4, 14, -0.43, 0.16, PAL.Frame, WOOD)
		for _, edge in { -7.5, 7.5 } do
			mounted("PortalJamb", portalStation + edge, 3, 25.5, 0.8, -0.57, 0.45, PAL.Charcoal, METAL)
		end
		mounted("PortalLintel", portalStation, 24.7, 25.5, 16, -0.57, 0.45, PAL.Charcoal, METAL)
		for _, y in { 8.2, 16.2 } do
			mounted("BoardedDoor", portalStation, y, y + 1.15, 13.8, -0.63, 0.28, PAL.Crate, WOOD)
		end
		label(mounted("PortalClosedSign", portalStation, 21.8, 24, 9, -0.64, 0.17, PAL.Black, METAL),
			exteriorFace, "CLOSED", PAL.NeonAmber)
		mounted("PosterFrame", posterStation, 5, 25, 11, -0.18, 0.4, PAL.Black, METAL)
		local art = mounted("PosterArt", posterStation, 7.3, 24.1, 9.5, -0.42, 0.16, PAL.Black, SP)
		local decal = Instance.new("Decal")
		decal.Name = "MovieArtwork"
		decal.Face = exteriorFace
		decal.Texture = if name == "West" then "rbxassetid://90273706821327" else "rbxassetid://78063750109486"
		decal.Parent = art
		label(mounted("PosterTitle", posterStation, 5.4, 7.1, 9.5, -0.49, 0.16, PAL.Black, METAL),
			exteriorFace, if name == "West" then "ECLIPSE VOYAGE" else "LAST SHOWING", PAL.NeonAmber)
		mounted("SconceMount", 57, 12, 17, 2.2, -0.175, 0.45, PAL.Black, METAL)
		light(mounted("SconceTube", 57, 12.6, 16.4, 0.75, -0.58, 0.3, PAL.NeonAmber, NEON),
			"PointLight", PAL.Warm, 0.32, 16)
	end
	box(f, "TipPlaster", -10, 0, 38, 10, 29.6, 40, PAL.CorridorWall)
	box(f, "TipBacker", -10, 29.6, 38, 10, 32, 39, PAL.Charcoal)
	box(f, "TipFascia", -10, 32, 38, 10, 36, 40, PAL.CorridorWall)
	box(f, "TipWainscot", -10, 0, 40, 10, 3, 40.12, PAL.Charcoal, SP, false)
	box(f, "TipCornice", -10, 27.5, 40.02, 10, 28.8, 40.45, PAL.Charcoal, METAL, false)
	box(f, "TipCorniceEdge", -10, 28.7, 40.44, 10, 28.85, 40.58, PAL.Tan, METAL, false)
	for _, pier in { { -8.6, 1.2, 40.5 }, { 0, 2.2, 40.75 }, { 8.6, 1.2, 40.5 } } do
		local x, width, depth = pier[1], pier[2], pier[3]
		box(f, "TipPierBase", x - width / 2, 0, 40.02, x + width / 2, 3, depth,
			PAL.Charcoal, SP, false)
		finish(box(f, "TipPier", x - width / 2, 3, 40.02, x + width / 2, 27.5, depth,
			PAL.CorridorWall, SP, false), Enum.NormalId.Back,
			WALL_BASE, 28, 28)
	end
	for _, p in { f.TipPlaster, f.TipFascia } do
		finish(p, Enum.NormalId.Back, WALL_BASE, 20, 32)
	end
	local points = {
		Vector2.new(-90.06, -19.92), Vector2.new(-10.06, 40.08),
		Vector2.new(10.06, 40.08), Vector2.new(90.06, -19.92),
	}
	for _, stripe in { { "Orange", 34.7, PAL.NeonRed } } do
		local name, y, color = stripe[1], stripe[2], stripe[3]
		for i = 1, #points - 1 do
			local a, b = points[i], points[i + 1]
			local va = Vector3.new(a.X, y + 0.09, a.Y)
			local vb = Vector3.new(b.X, y + 0.09, b.Y)
			part(f, name .. "ForkCove", Vector3.new(0.24, 0.18, (vb - va).Magnitude),
				CFrame.lookAt((va + vb) / 2, vb), color, NEON, false)
		end
		for _, x in { -10.06, 10.06 } do
			part(f, name .. "CornerJoint", Vector3.new(0.28, 0.28, 0.28),
				CFrame.new(x, y + 0.09, 40.08), color, NEON, false, Enum.PartType.Ball)
		end
	end
end

local function buildRestrooms(model)
	local f = folder(model, "Restrooms")
	local templates = game:GetService("ServerStorage"):FindFirstChild("Level4V7Templates")
	assert(templates and templates:FindFirstChild("Toilet")
		and templates:FindFirstChild("PublicSink"), "Missing vetted restroom fixtures")
	for _, template in { templates.Toilet, templates.PublicSink } do
		for _, child in template:GetDescendants() do
			assert(not child:IsA("LuaSourceContainer"), "Restroom fixture contains a script")
		end
	end
	local function fixture(name, template, height, position, yaw)
		local item = template:Clone()
		item.Name = name
		local _, originalSize = item:GetBoundingBox()
		item:ScaleTo(item:GetScale() * height / originalSize.Y)
		local itemBox, itemSize = item:GetBoundingBox()
		local offset = itemBox:ToObjectSpace(item:GetPivot())
		item:PivotTo(origin * CFrame.new(position.X, position.Y + itemSize.Y / 2,
			position.Z) * CFrame.Angles(0, yaw, 0) * offset)
		item.Parent = f
	end
	-- The public rooms now occupy only two 32 x 40-stud bays. The rest of the
	-- former service footprint is closed back-of-house, never visible void.
	box(f, "RestroomBackOfHouse", 261, 0, 166, 376, 28, 238, PAL.Teal)
	box(f, "RestroomWestStore", 261, 0, 102, 270, 28, 166, PAL.Teal)
	box(f, "RestroomEastStore", 343, 0, 102, 376, 28, 166, PAL.Teal)
	box(f, "RestroomCoreDivider", 302, 0, 126, 311, 28, 166, PAL.Teal)
	carpet(overlay(f, "RestroomVestibuleCarpet", 270, 102, 343, 124), "Red")
	local vestibuleCeiling = finish(box(f, "RestroomVestibuleCeiling", 270, 17, 102,
		343, 17.5, 124, PAL.LightCeiling), Enum.NormalId.Bottom,
		RESTROOM_CEILING_PANEL, 24, 24)
	vestibuleCeiling.WallFinish.Color3 = Color3.fromRGB(190, 178, 160)
	wall(f, "RestroomEntryWall", "X", 270, 343, 124, 126, 0, 28,
		PAL.CorridorWall, SP,
		{ { 276, 286, 0, 12 }, { 326, 336, 0, 12 } })
	for _, p in f:GetChildren() do
		if p:IsA("BasePart") and p.Name:find("^RestroomEntryWall") then
			p.Color = Color3.fromRGB(106, 32, 28)
			finish(p, Enum.NormalId.Front, BURGUNDY_WALL, 32, 28)
			finish(p, Enum.NormalId.Back, WALL_BASE, 24, 24)
		end
	end
	for _, span in { { 270, 276 }, { 286, 326 }, { 336, 343 } } do
		box(f, "RestroomEntryBaseboard", span[1], 0, 123.72,
			span[2], 0.85, 124.05, PAL.Charcoal, METAL, false)
	end
	local function pushDoor(name, doorX)
		local hinge = swingLeaf(f, name .. "_Restroom",
			CFrame.new(doorX + 0.5, 5.5, 125), 9.2, 10,
			PAL.Stall, -95)
		swingZone(f, name .. "_Restroom",
			CFrame.new(doorX + 5, 5.5, 125),
			Vector3.new(14, 11, 14), { hinge })
	end
	local function agedWallTile(p, face)
		finish(p, face, RESTROOM_WALL_TILE, 8, 8)
		for _, child in p:GetChildren() do
			if child:IsA("Texture") and child.Name == "WallFinish" and child.Face == face then
				child.Color3 = Color3.fromRGB(188, 175, 155)
			end
		end
	end
	for _, r in {
		{ "Men", 270, 302, 276, -1 },
		{ "Women", 311, 343, 326, 1 },
	} do
		local name, x0, x1, doorX, mirrorSide = table.unpack(r)
		finish(floor(box(f, name .. "_Tile", x0, 0, 126, x1, 0.05, 166,
			PAL.Charcoal, TILE)), Enum.NormalId.Top, RESTROOM_FLOOR_TILE, 8, 8)
		finish(floor(box(f, name .. "_ThresholdTile", doorX, 0, 124,
			doorX + 10, 0.05, 126, PAL.Charcoal, TILE)),
			Enum.NormalId.Top, RESTROOM_FLOOR_TILE, 8, 8)
		doorway(f, name .. "Doorway", doorX, 0, 124, doorX + 10, 12, 126)
		for _, edge in { doorX - 0.4, doorX + 9.9 } do
			box(f, name .. "_DoorJamb", edge, 0, 123.7, edge + 0.5, 12.7, 124.1,
				PAL.Frame, METAL, false)
		end
		box(f, name .. "_DoorLintel", doorX - 0.4, 12, 123.7,
			doorX + 10.4, 12.7, 124.1, PAL.Frame, METAL, false)
		local sign = label(box(f, name .. "_Sign", doorX, 13.5, 123.5, doorX + 10, 15.5, 124,
			PAL.Black, METAL, false), Enum.NormalId.Front,
			string.upper(name), PAL.NeonAmber)
		local title = sign.Label:FindFirstChildOfClass("TextLabel")
		title.Size = UDim2.fromScale(0.67, 0.8)
		title.Position = UDim2.fromScale(0.29, 0.1)
		local border = Instance.new("Frame")
		border.Name = "AgedBorder"
		border.Size = UDim2.fromScale(0.98, 0.9)
		border.Position = UDim2.fromScale(0.01, 0.05)
		border.BackgroundTransparency = 1
		border.BorderSizePixel = 2
		border.BorderColor3 = Color3.fromRGB(103, 81, 61)
		border.Parent = sign.Label
		for i, shape in { { 0.125, 0.22, 0.06, 0.23 }, { 0.12, 0.47, 0.07, 0.21 },
			{ 0.095, 0.48, 0.024, 0.18 }, { 0.19, 0.48, 0.024, 0.18 },
			{ 0.125, 0.68, 0.025, 0.2 }, { 0.165, 0.68, 0.025, 0.2 } } do
			local icon = Instance.new("Frame")
			icon.Name = "Person" .. i
			icon.Position = UDim2.fromScale(shape[1], shape[2])
			icon.Size = UDim2.fromScale(shape[3], shape[4])
			icon.BorderSizePixel = 0
			icon.BackgroundColor3 = Color3.fromRGB(201, 179, 143)
			icon.Parent = sign.Label
			if i == 1 then
				local round = Instance.new("UICorner")
				round.CornerRadius = UDim.new(1, 0)
				round.Parent = icon
			end
		end
		pushDoor(name, doorX)
		local roomCeiling = finish(box(f, name .. "_LowerCeiling", x0, 16.5, 126,
			x1, 17, 166, PAL.LightCeiling), Enum.NormalId.Bottom,
			RESTROOM_CEILING_PANEL, 24, 24)
		roomCeiling.WallFinish.Color3 = Color3.fromRGB(180, 170, 153)
		local fluorescent = glow(f, name .. "_Fluorescent", x0 + 5, 16.1, 135,
			x0 + 27, 16.45, 138, PAL.NeonWarmWhite, 1.5, 32)
		fluorescent:SetAttribute("OccasionalFlicker", true)
		for _, x in { x0 + 0.12, x1 - 0.32 } do
			local tileWall = box(f, name .. "_TileWainscot", x, 0.05, 126, x + 0.2, 7.5, 166,
				PAL.TileWhite, TILE, false)
			agedWallTile(tileWall, Enum.NormalId.Left)
			agedWallTile(tileWall, Enum.NormalId.Right)
			box(f, name .. "_TealStripe", x, 7.2, 126, x + 0.22, 8, 166,
				PAL.Teal, TILE, false)
			local worn = box(f, name .. "_UpperPlaster", x, 8, 126,
				x + 0.22, 16.5, 166, PAL.CorridorWall, SP, false)
			finish(worn, Enum.NormalId.Left, WALL_BASE, 16, 12)
			finish(worn, Enum.NormalId.Right, WALL_BASE, 16, 12)
		end
		agedWallTile(box(f, name .. "_BackWainscot", x0, 0.05, 165.8, x1, 7.5, 166,
			PAL.TileWhite, TILE, false), Enum.NormalId.Front)
		box(f, name .. "_BackTealStripe", x0, 7.2, 165.78,
			x1, 8, 166, PAL.Teal, TILE, false)
		finish(box(f, name .. "_BackUpperPlaster", x0, 8, 165.78,
			x1, 16.5, 166, PAL.CorridorWall, SP, false),
			Enum.NormalId.Front, WALL_BASE, 16, 12)
		for _, span in { { x0, doorX }, { doorX + 10, x1 } } do
			agedWallTile(box(f, name .. "_EntryWainscot", span[1], 0.05, 126,
				span[2], 7.5, 126.2, PAL.TileWhite, TILE, false),
				Enum.NormalId.Back)
		end
		local sinkX0 = if mirrorSide < 0 then x0 + 1 else x1 - 6
		for _, z in { 132, 142 } do
			fixture(name .. "_Sink", templates.PublicSink, 4,
				Vector3.new(sinkX0 + 2.5, 0.05, z + 3),
				if mirrorSide < 0 then math.pi / 2 else -math.pi / 2)
		end
		local mirrorX = if mirrorSide < 0 then x0 + 0.3 else x1 - 0.6
		box(f, name .. "_MirrorFrame", mirrorX, 4.5, 130,
			mirrorX + 0.25, 12.5, 151, PAL.Charcoal, METAL, false)
		local mirror = box(f, name .. "_MirrorGlass", mirrorX + 0.25, 5, 130.5,
			mirrorX + 0.4, 12, 150.5, Color3.fromRGB(74, 82, 84), GLASS, false)
		mirror.Reflectance = 0.05
		local mirrorFace = if mirrorSide < 0 then Enum.NormalId.Right else Enum.NormalId.Left
		finish(mirror, mirrorFace, SERVICE_TEAL, 20, 8)
		mirror.WallFinish.Color3 = Color3.fromRGB(106, 102, 93)
		mirror.WallFinish.Transparency = 0.78
		local trashX = if mirrorSide < 0 then x1 - 4 else x0 + 1
		box(f, name .. "_TrashBin", trashX, 0.05, 130,
			trashX + 2.5, 3.5, 132.5, PAL.Charcoal, METAL)
		for _, stallX in { x0 + 3, x0 + 18 } do
			for _, sideX in { stallX, stallX + 11 } do
				local side = box(f, name .. "_StallSide", sideX, 1.2, 151,
					sideX + 0.5, 12.4, 166, PAL.Stall)
				finish(side, Enum.NormalId.Left, RESTROOM_STALL_FINISH, 8, 8)
				finish(side, Enum.NormalId.Right, RESTROOM_STALL_FINISH, 8, 8)
			end
			box(f, name .. "_StallHeader", stallX, 12.2, 151,
				stallX + 11.5, 12.8, 151.5, PAL.Charcoal, METAL)
			local doorCF = CFrame.new(stallX + 0.5, 6.5, 151.4)
				* CFrame.Angles(0, math.rad(-22), 0) * CFrame.new(4.4, 0, 0)
			local stallDoor = part(f, name .. "_StallDoor", Vector3.new(8.8, 9, 0.5),
				doorCF, PAL.Stall, METAL, false)
			finish(stallDoor, Enum.NormalId.Front, RESTROOM_STALL_FINISH, 8, 8)
			finish(stallDoor, Enum.NormalId.Back, RESTROOM_STALL_FINISH, 8, 8)
			for _, hingeY in { -3, 3 } do
				part(f, name .. "_StallHinge", Vector3.new(0.3, 0.7, 0.2),
					doorCF * CFrame.new(-4.2, hingeY, -0.35), PAL.Chrome, METAL, false)
			end
			part(f, name .. "_StallLatch", Vector3.new(0.6, 0.6, 0.6),
				doorCF * CFrame.new(3.5, 0, 0.4), PAL.Chrome, METAL, false)
			fixture(name .. "_Toilet", templates.Toilet, 4,
				Vector3.new(stallX + 5.5, 0.05, 161.5), math.pi / 4)
		end
	end
end
local function buildService(model)
	local f = folder(model, "Service")
	local concrete = finish(overlay(f, "ServiceConcrete", -376, 102, -122, 238,
		Color3.fromRGB(62, 63, 65), CONCRETE), Enum.NormalId.Top, SERVICE_CONCRETE, 12, 12)
	concrete.WallFinish.Color3 = Color3.fromRGB(130, 140, 148)
	box(f, "ServiceSuspendedCeiling", -376, 22.8, 102,
		-122, 23.1, 238, PAL.Ceiling, SP, false)
	local function serviceWall(p, face)
		finish(p, face, BURGUNDY_WALL, 32, 24)
		p.WallFinish.Color3 = Color3.fromRGB(135, 126, 120)
	end
	for _, span in { { -376, -146, 0, 28 }, { -126, -122, 0, 28 },
		{ -146, -126, 12, 28 } } do
		serviceWall(box(f, "ServiceNorthWallFinish", span[1], span[3], 102.02,
			span[2], span[4], 102.04, PAL.Partition, SP, false),
			Enum.NormalId.Back)
	end
	serviceWall(box(f, "ServiceSouthWallFinish", -376, 0, 237.94,
		-122, 28, 237.96, PAL.Partition, SP, false),
		Enum.NormalId.Front)
	serviceWall(box(f, "ServiceWestWallFinish", -375.98, 0, 102,
		-375.94, 28, 238, PAL.Partition, SP, false), Enum.NormalId.Right)
	serviceWall(box(f, "ServiceEastWallFinish", -122.06, 0, 102,
		-122.02, 28, 238, PAL.Partition, SP, false), Enum.NormalId.Left)
	for _, x in { -375.7, -122.3 } do
		box(f, "ServiceBaseboard", x - 0.15, 0.05, 102.1,
			x + 0.15, 0.8, 237.9, PAL.Charcoal, METAL, false)
	end
	box(f, "ServiceBaseboard", -375.7, 0.05, 237.6,
		-122.3, 0.8, 237.9, PAL.Charcoal, METAL, false)
	local leftDoor = swingLeaf(f, "ServiceLeft",
		CFrame.new(-145.5, 5.5, 101), 9.2, 10.5, PAL.Booth, -95)
	local rightDoor = swingLeaf(f, "ServiceRight",
		CFrame.new(-126.5, 5.5, 101) * CFrame.Angles(0, math.pi, 0),
		9.2, 10.5, PAL.Booth, 95)
	swingZone(f, "ServiceEntry", CFrame.new(-136, 5.5, 101),
		Vector3.new(24, 11, 14), { leftDoor, rightDoor })
	local steel = Color3.fromRGB(35, 33, 32)
	local templates = game:GetService("ServerStorage"):FindFirstChild("Level4V7Templates")
	assert(templates and templates:FindFirstChild("Cart") and templates.Cart:IsA("Model")
		and templates:FindFirstChild("Extinguisher") and templates.Extinguisher:IsA("MeshPart")
		and templates:FindFirstChild("StockBox") and templates.StockBox:IsA("Model"),
		"Missing vetted service templates")
	for _, template in { templates.Cart, templates.Extinguisher, templates.StockBox } do
		for _, child in template:GetDescendants() do
			assert(not child:IsA("LuaSourceContainer"), "Service template contains a script")
		end
	end
	assert(templates.StockBox:FindFirstChild("Body")
		and templates.StockBox.Body:IsA("MeshPart"), "Missing service mesh bodies")
	local cardboard = { Color3.fromRGB(65, 52, 41), Color3.fromRGB(76, 60, 45),
		Color3.fromRGB(60, 48, 38) }
	local function carton(x, y, z, width, depth, height, shade)
		local item = templates.StockBox:Clone()
		item.Name = "StockBox"
		local body = item.Body
		body.Size = Vector3.new(width, height, depth)
		body.CFrame = origin * CFrame.new(x + width / 2, y + height / 2,
			z + depth / 2) * (templates.StockBox.Body.CFrame - templates.StockBox.Body.Position)
		body.Color = shade
		body.Material = SP
		body.Anchored = true
		body.CanCollide = false
		body.CanTouch = false
		body.CanQuery = false
		item.Parent = f
		if width >= 7 then
			box(f, "CartonHandSlot", x + width / 2 - 1.05,
				y + height * 0.57, z + depth - 0.05,
				x + width / 2 + 1.05, y + height * 0.57 + 0.3,
				z + depth + 0.02, Color3.fromRGB(33, 27, 23), SP, false)
		end
		if depth >= 7.5 then
			box(f, "CartonPackingTape", x + width / 2 - 0.17,
				y + height, z + 0.2,
				x + width / 2 + 0.17, y + height + 0.03,
				z + depth - 0.2, Color3.fromRGB(117, 98, 72), SP, false)
		end
	end
	local function filmStack(x, y, z)
		for layer = 0, 2 do
			disc(f, "FilmTin", x, z, 4.7, y + layer * 0.7,
				y + layer * 0.7 + 0.6, Color3.fromRGB(106, 104, 101), METAL, false)
		end
	end
	local function bottle(x, y, z, color)
		disc(f, "CleaningBottle", x, z, 1.7, y, y + 2.1, color, SP, false)
		disc(f, "BottleCap", x, z, 0.8, y + 2.1, y + 2.45,
			Color3.fromRGB(41, 45, 42), SP, false)
	end
	local function popcornTub(x, y, z)
		disc(f, "PopcornTub", x, z, 2.5, y, y + 2.6, Color3.fromRGB(115, 30, 29), SP, false)
		disc(f, "PopcornRim", x, z, 2.7, y + 2.5, y + 2.7, Color3.fromRGB(184, 173, 153), SP, false)
		for _, offset in { -0.55, 0.55 } do
			box(f, "PopcornStripe", x + offset - 0.15, y + 0.2, z - 1.26,
				x + offset + 0.15, y + 2.5, z - 1.16, Color3.fromRGB(184, 173, 153), SP, false)
		end
	end
	-- Short bays sit in staggered banks, with a broad clear aisle to the east wall.
	for index, rack in { { -337, 142 }, { -350, 202 }, { -282, 158 },
		{ -227, 138 }, { -282, 201 }, { -227, 181 }, { -275, 116 } } do
		local x, z = rack[1], rack[2]
		for _, edgeX in { x, x + 33.5 } do
			for _, edgeZ in { z, z + 15.5 } do
				box(f, "StorageUpright", edgeX, 0.2, edgeZ,
					edgeX + 0.5, 18, edgeZ + 0.5, steel, METAL)
			end
		end
		for _, y in { 0.7, 4.1, 7.5, 10.9, 14.3 } do
			box(f, "StorageShelf", x, y, z, x + 34, y + 0.28, z + 16, steel, SP)
			for _, edgeZ in { z, z + 15.6 } do
				box(f, "ShelfLip", x, y + 0.28, edgeZ,
					x + 34, y + 0.65, edgeZ + 0.4, steel, SP, false)
			end
		end
		local shade = cardboard[(index - 1) % #cardboard + 1]
		carton(x + 1, 1.05, z + 1.2, 6.5, 6.5, 2.7, shade)
		carton(x + 8.5, 1.05, z + 2, 6, 7, 2.7, cardboard[index % 3 + 1])
		carton(x + 16, 1.05, z + 1.2, 8, 8, 2.8, cardboard[(index + 1) % 3 + 1])
		filmStack(x + 4, 4.45, z + 4)
		filmStack(x + 10, 4.45, z + 4)
		carton(x + 16, 4.45, z + 1.4, 7, 7.5, 2.6, cardboard[3])
		popcornTub(x + 25, 4.45, z + 4)
		carton(x + 1.5, 7.85, z + 1.5, 6.5, 7, 2.5, cardboard[2])
		for j = 0, 3 do
			bottle(x + 10 + j * 2.3, 7.85, z + 4.5,
				if (index + j) % 2 == 0 then Color3.fromRGB(134, 128, 113)
				else Color3.fromRGB(129, 113, 72))
		end
		for j = 0, 2 do
			part(f, "PosterRoll", Vector3.new(5.5, 1, 1),
				CFrame.new(x + 22, 8.25, z + 3 + j * 1.2),
				Color3.fromRGB(127, 118, 102), SP, false, Enum.PartType.Cylinder)
		end
		carton(x + 2, 11.2, z + 1.5, 7, 7, 2.1, shade)
		carton(x + 12, 11.2, z + 3, 7, 7, 2, cardboard[2])
		filmStack(x + 30, 4.45, z + 8)
		carton(x + 2, 14.65, z + 1.5, 6.5, 7, 2.4, cardboard[3])
		filmStack(x + 14, 14.65, z + 5)
		carton(x + 22, 14.65, z + 2, 8, 8, 2.5, shade)
		if index % 2 == 0 then
			filmStack(x + 24, 11.2, z + 7)
			carton(x + 3, 4.45, z + 9, 5, 5, 2.5, cardboard[1])
		else
			popcornTub(x + 23, 11.2, z + 7)
			carton(x + 19, 1.05, z + 10, 6, 4, 2.5, cardboard[2])
		end
	end
	-- The north cleaning station reads from the southwest corner.
	box(f, "ServiceCleaningTop", -346, 3.5, 103, -307, 3.95, 112,
		Color3.fromRGB(82, 79, 74), METAL)
	box(f, "ServiceCleaningShelf", -346, 0.7, 103, -307, 0.98, 112, steel, METAL)
	for _, x in { -345, -308 } do
		for _, z in { 103.4, 111 } do
			box(f, "ServiceCleaningLeg", x, 0.2, z,
				x + 0.6, 3.5, z + 0.6, steel, METAL)
		end
	end
	filmStack(-338, 4.02, 107)
	carton(-329, 4.02, 104, 7, 6, 2.7, cardboard[2])
	for _, x in { -316, -312 } do
		bottle(x, 4.02, 107, Color3.fromRGB(126, 118, 101))
	end
	carton(-343, 1.02, 104, 7, 6, 2.5, cardboard[3])
	carton(-326, 1.02, 104, 8, 6, 2.5, cardboard[1])
	-- The south workbench is in the northeast camera's open left foreground.
	box(f, "ServiceWorkbenchBack", -204, 3.9, 237.4,
		-160, 10.5, 237.75, steel, METAL, false)
	box(f, "ServiceWorkbenchTop", -204, 3.5, 225,
		-160, 3.95, 237.7, Color3.fromRGB(91, 88, 82), METAL)
	box(f, "ServiceWorkbenchShelf", -204, 0.7, 225,
		-160, 0.98, 237.7, steel, METAL)
	box(f, "WorkbenchWallShelf", -204, 10.2, 229,
		-160, 10.5, 237.7, steel, METAL)
	for _, x in { -203, -161 } do
		for _, z in { 225.5, 236.8 } do
			box(f, "ServiceWorkbenchLeg", x, 0.2, z,
				x + 0.6, 3.5, z + 0.6, steel, METAL)
		end
	end
	filmStack(-195, 4.02, 230)
	carton(-186, 4.02, 227, 6, 7, 2.6, cardboard[2])
	for _, x in { -174, -171, -168 } do
		bottle(x, 4.02, 230, Color3.fromRGB(132, 125, 109))
	end
	for _, x in { -197, -184, -170 } do
		bottle(x, 10.52, 233, Color3.fromRGB(142, 133, 111))
	end
	for _, x in { -198, -187 } do
		carton(x, 1.02, 228, 8, 7, 2.3, cardboard[1])
	end
	for _, x in { -198, -188, -178 } do
		part(f, "PosterRoll", Vector3.new(5.5, 1, 1),
			CFrame.new(x, 4.5, 235), Color3.fromRGB(127, 118, 102),
			SP, false, Enum.PartType.Cylinder)
	end
	box(f, "WorkbenchLampStem", -202, 3.95, 227,
		-201.5, 6.5, 227.5, steel, METAL, false)
	box(f, "WorkbenchLampArm", -201.8, 6.1, 227,
		-197, 6.45, 227.6, steel, METAL, false)
	glow(f, "WorkbenchLamp", -198, 5.8, 226.2,
		-195.5, 6.1, 228.7, Color3.fromRGB(255, 214, 155), 0.9, 28)
	local cart = templates.Cart:Clone()
	cart.Name = "JanitorCart"
	local cartBox, cartSize = cart:GetBoundingBox()
	local offset = cartBox:ToObjectSpace(cart:GetPivot())
	cart:PivotTo(origin * CFrame.new(-305, cartSize.Y / 2, 123)
		* CFrame.Angles(0, math.rad(20), 0) * offset)
	cart.Parent = f
	box(f, "MopPole", -310.6, 0.2, 115.1,
		-310.1, 10.5, 115.6, Color3.fromRGB(139, 111, 78), WOOD, false)
	box(f, "MopHead", -311.5, 0.1, 114.5,
		-309.1, 0.8, 116.2, Color3.fromRGB(107, 95, 77), FABRIC, false)
	carton(-298, 0.05, 121, 6.5, 6, 3.2, cardboard[2])
	carton(-297, 3.25, 122, 5, 5, 2.7, cardboard[1])
	-- Each right-hand wall in the opposite corner views is a different wall.
	for _, site in {
		{ "North", -215, 102.1, 1, Enum.NormalId.Back, -198 },
		{ "South", -264, 237.9, -1, Enum.NormalId.Front, -247 },
	} do
		local name, x, z, dir, face, fireX = table.unpack(site)
		local frontZ = z + dir * 1.3
		box(f, name .. "ServicePanel", x, 7, z,
			x + 11, 17, frontZ, PAL.Metal, METAL, false)
		box(f, name .. "ServicePanelDoor", x + 0.5, 7.5, frontZ,
			x + 10.5, 16.5, frontZ + dir * 0.2,
			Color3.fromRGB(55, 53, 51), METAL, false)
		box(f, name .. "ServicePanelHandle", x + 9.4, 11.1, frontZ + dir * 0.2,
			x + 10, 12.3, frontZ + dir * 0.5, PAL.Chrome, METAL, false)
		label(box(f, name .. "ServicePanelMark", x + 1.7, 14.1, frontZ + dir * 0.22,
			x + 8.7, 15.5, frontZ + dir * 0.3, PAL.Charcoal, METAL, false),
			face, "POWER", PAL.CounterWhite)
		for _, conduitX in { x + 3, x + 8 } do
			box(f, name .. "ServiceConduit", conduitX, 17, z + dir * 0.4,
				conduitX + 0.45, 22.8, z + dir * 0.9, PAL.Metal, METAL, false)
		end
		box(f, name .. "ExtinguisherBracket", fireX - 1.8, 2, z,
			fireX + 1.8, 9, z + dir * 0.9, steel, METAL, false)
		local extinguisher = templates.Extinguisher:Clone()
		extinguisher.Name = name .. "ServiceExtinguisher"
		extinguisher.Size *= 2.2
		extinguisher.CFrame = origin * CFrame.new(fireX, 5.5, frontZ + dir * 1.2)
			* CFrame.Angles(0, if dir > 0 then 0 else math.pi, 0)
		extinguisher.Parent = f
	end
	local serviceLampColor = Color3.fromRGB(255, 196, 129)
	for _, x in { -310, -230, -150 } do
		glow(f, "CagedServiceLamp", x - 2.2, 22.1, 161,
			x + 2.2, 22.5, 165, serviceLampColor, 1.5, 70)
		for _, edgeX in { x - 2.6, x + 2.3 } do
			box(f, "ServiceLampCage", edgeX, 21.75, 160.7,
				edgeX + 0.3, 22.55, 165.3, steel, METAL, false)
		end
		for _, edgeZ in { 160.7, 165 } do
			box(f, "ServiceLampCage", x - 2.3, 21.75, edgeZ,
				x + 2.3, 22.55, edgeZ + 0.3, steel, METAL, false)
		end
		for _, offset in { -1.3, 0, 1.3 } do
			box(f, "ServiceLampCage", x + offset - 0.12, 21.55, 160.7,
				x + offset + 0.12, 21.78, 165.3, steel, METAL, false)
		end
	end
end
local function buildConcession(model)
	local f = folder(model, "Concession")
	carpet(overlay(f, "Concession_RedCarpet", -120, 102, 120, 238), "Red")
	-- Glass sidelights frame two closed, self-closing entry leaves.
	box(f, "MainEntry_GlassWest", -24, 0, 238.6, -11.7, 14, 239.4, PAL.TintGlass, GLASS).Reflectance = 0.2
	box(f, "MainEntry_GlassEast", 11.7, 0, 238.6, 24, 14, 239.4, PAL.TintGlass, GLASS).Reflectance = 0.2
	local westEntry = swingLeaf(f, "MainEntryWest",
		CFrame.new(-11.5, 7, 239), 11.2, 13.5, PAL.TintGlass, -95)
	local eastEntry = swingLeaf(f, "MainEntryEast",
		CFrame.new(11.5, 7, 239) * CFrame.Angles(0, math.pi, 0),
		11.2, 13.5, PAL.TintGlass, 95)
	for _, hinge in { westEntry, eastEntry } do
		local leaf = hinge.Attachment1.Parent
		leaf.Material = GLASS
		leaf.Transparency = 0.25
		leaf.Reflectance = 0.2
	end
	swingZone(f, "MainEntry", CFrame.new(0, 7, 239),
		Vector3.new(48, 14, 14), { westEntry, eastEntry })
	frame(f, "MainEntry_Frame", "X", 238, -1, -24, 24, 0, 14, PAL.NeonRed)
	label(box(f, "MainEntry_Sign", -10, 16, 237.6, 10, 19, 238, PAL.Exit, NEON, false), Enum.NormalId.Front, "EXIT", PAL.White)

	-- Preview arrival/exit anchor just inside the doors, centred at (0,3,226), facing north.
	local anchor = box(model, "Level4V4Exit", -2, 2.5, 224, 2, 3.5, 228, PAL.Black, SP, false)
	anchor.Transparency = 1
	anchor:SetAttribute("Zone", "Concessions")
	tag(anchor, V7.TAGS.Exit)

	-- One back-wall counter serves popcorn, tickets, drinks and candy in the spawn room.
	-- Its right edge stops before the existing x[55,95] concourse passage.
	for _, span in { { -120, -64 }, { -64, 0 }, { 0, 55 }, { 95, 120 } } do
		finish(box(f, "SpawnWeatheredBackWall", span[1], 4.5, 102.005,
			span[2], 28, 102.015, PAL.CorridorWall, SP, false),
			Enum.NormalId.Back, BURGUNDY_WALL, 48, 26)
	end
	-- Texture only the solid header above the existing x[55,95] passage.
	finish(box(f, "SpawnPassageHeaderFinish", 55, 12, 102.005,
		95, 28, 102.015, PAL.CorridorWall, SP, false),
		Enum.NormalId.Back, BURGUNDY_WALL, 48, 26)
	box(f, "Counter", -110, 0, 108, 50, 4.1, 125, PAL.Counter)
	local counterTop = finish(box(f, "CounterTop", -110.3, 4.1, 107.7,
		50.3, 4.5, 125.3, Color3.fromRGB(200, 189, 171)),
		Enum.NormalId.Top, COUNTER_LAMINATE, 8, 8)
	counterTop.WallFinish.Transparency = 0
	box(f, "CounterTopWornFrontLip", -110.3, 4.08, 125.22,
		50.3, 4.45, 125.4, Color3.fromRGB(74, 53, 44), METAL, false)
	finish(box(f, "TicketCounterBridge", -55, 4.1, 102.5, 18, 4.5, 108.2,
		Color3.fromRGB(200, 189, 171), SP, false),
		Enum.NormalId.Top, COUNTER_LAMINATE, 8, 8)
	box(f, "CounterTrim", -110, 3.3, 125, 50, 3.6, 125.2, PAL.NeonAmber, NEON, false)
	box(f, "CounterPlinth", -110, 0, 125, 50, 0.7, 125.3, PAL.Black, SP, false)
	for x = -90, 30, 20 do
		box(f, "CounterPanelSeam", x, 0.8, 125.05, x + 0.3, 3.2, 125.25, PAL.Black, SP, false)
	end
	for _, x in { -38, -17 } do
		box(f, "Register", x - 2, 4.5, 117, x + 2, 5.9, 121, PAL.Metal, METAL, false)
	end
	-- Drinks belong under DRINKS, clear of the third ticket window.
	box(f, "SodaFountain", 19, 4.5, 111, 31, 10.5, 121,
		PAL.Charcoal, METAL, false)
	box(f, "SodaFountainFace", 19.4, 6.8, 121,
		30.6, 10.2, 121.18, PAL.Metal, METAL, false)
	box(f, "SodaFountainTop", 18.8, 10.5, 110.8,
		31.2, 10.9, 121.3, PAL.Charcoal, METAL, false)
	box(f, "SodaDripTray", 19.7, 5.1, 121.2,
		30.3, 5.5, 122.5, PAL.Chrome, METAL, false)
	for i, x in { 20, 22.7, 25.4, 28.1 } do
		box(f, "SodaTapHousing", x, 8.6, 121.19,
			x + 1.9, 10.1, 121.5, PAL.Charcoal, METAL, false)
		box(f, "SodaTapButton", x + 0.48, 9.15, 121.5,
			x + 1.35, 9.7, 121.62,
			({ PAL.Counter, PAL.Tan, PAL.Turquoise, PAL.Green })[i], SP, false)
		box(f, "SodaNozzle", x + 0.84, 6.7, 121.23,
			x + 1.05, 8.6, 121.53, PAL.Chrome, METAL, false)
	end
	box(f, "TicketHeaderFrame", -56, 15, 102.5, 18, 21.5, 102.8,
		PAL.Booth, METAL, false)
	for _, sign in { { -104, -66, "POPCORN" }, { -53, 15, "TICKETS" },
		{ 18, 32, "DRINKS" }, { 34, 50, "CANDY" } } do
		local ticket = sign[3] == "TICKETS"
		local board = label(box(f, "MenuBoard", sign[1], 15.5, 102.82,
			sign[2], 20.8, 103.02, Color3.fromRGB(219, 199, 166),
			SP, false), Enum.NormalId.Back, sign[3], PAL.Frame)
		finish(board, Enum.NormalId.Back, TICKET_FASCIA,
			sign[2] - sign[1], 20.8 - 15.5)
		board.WallFinish.Transparency = 0
		if ticket then
			local ticketWord = board.Label:FindFirstChildOfClass("TextLabel")
			ticketWord.Size = UDim2.fromScale(1, 1.18)
			ticketWord.Position = UDim2.fromScale(0, -0.09)
			box(f, "TicketFasciaLowerEdge", sign[1], 15.25, 102.9,
				sign[2], 15.48, 103.2, PAL.Frame, METAL, false)
			for _, edge in { sign[1], sign[2] - 2.2 } do
				box(f, "TicketFasciaSideRib", edge, 15.5, 103.03,
					edge + 2.2, 20.8, 103.28, PAL.Frame, METAL, false)
				for _, y in { 16.7, 18.1, 19.5 } do
					box(f, "TicketFasciaRibStripe", edge + 0.2, y, 103.29,
						edge + 2, y + 0.17, 103.39,
						Color3.fromRGB(156, 45, 31), NEON, false)
				end
			end
		end
		box(f, "MenuBoardEdge", sign[1], 20.8, 102, sign[2], 21.1, 103.05,
			PAL.NeonRed, NEON, false)
	end
	finish(box(f, "TicketSootCanopy", -56, 21.5, 102.1, 18, 24, 102.75,
		PAL.Frame, SP, false), Enum.NormalId.Back, BURGUNDY_WALL, 20, 8)
	for _, x in { -57.5, 18.5 } do
		for _, y in { 17, 18.2, 19.4 } do
			box(f, "TicketHeaderRedRib", x, y, 102.8, x + 1.1,
				y + 0.16, 103.35, Color3.fromRGB(180, 33, 25), NEON, false)
		end
	end
	for _, bay in { { -50, -32 }, { -29, -11 }, { -8, 10 } } do
		finish(box(f, "TicketBayBack", bay[1], 4.6, 102.2,
			bay[2], 14.5, 102.55, PAL.Stall, METAL, false),
			Enum.NormalId.Back, SERVICE_TEAL, 18, 12)
		box(f, "TicketWindow", bay[1] + 0.65, 7.1, 102.58,
			bay[2] - 0.65, 14, 102.7,
			PAL.TintGlass, GLASS, false).Transparency = 0.84
		for _, edge in { bay[1], bay[2] - 0.65 } do
			box(f, "TicketWindowStile", edge, 4.5, 102.55,
				edge + 0.65, 15, 103.15, PAL.Metal, METAL, false)
		end
		box(f, "TicketWindowLintel", bay[1], 14.2, 102.55,
			bay[2], 15, 103.15, PAL.Metal, METAL, false)
		box(f, "TicketServiceHatch", bay[1] + 0.85, 4.7, 102.65,
			bay[2] - 0.85, 7, 103.05, PAL.Metal, METAL, false)
		box(f, "TicketSlot", bay[1] + 3, 6, 103.05,
			bay[2] - 3, 6.25, 103.22, PAL.Chrome, METAL, false)
		local middle = (bay[1] + bay[2]) / 2
		part(f, "TicketPortholeRim", Vector3.new(0.12, 2.1, 2.1),
			CFrame.new(middle, 11.2, 102.88) * CFrame.Angles(0, math.rad(90), 0),
			PAL.Chrome, METAL, false, Enum.PartType.Cylinder)
		part(f, "TicketPortholeGlass", Vector3.new(0.13, 1.55, 1.55),
			CFrame.new(middle, 11.2, 103) * CFrame.Angles(0, math.rad(90), 0),
			PAL.TintGlass, GLASS, false, Enum.PartType.Cylinder)
		box(f, "TicketWindowSill", bay[1], 4.5, 102.5, bay[2], 4.7, 103.3,
			PAL.Chrome, METAL, false)
		box(f, "TicketIntercom", middle - 1, 8.2, 102.76,
			middle + 1, 9.1, 103.15, PAL.Chrome, METAL, false)
		box(f, "TicketNotice", bay[1] + 1.5, 10.3, 102.72,
			bay[1] + 4.4, 12.8, 102.79,
			Color3.fromRGB(183, 167, 132), SP, false)
		for _, y in { 11.8, 11.2 } do
			box(f, "TicketNoticeRule", bay[1] + 1.9, y, 102.8,
				bay[1] + 4, y + 0.07, 102.85, PAL.Frame, SP, false)
		end
	end
	-- Small black-and-cream checker backsplash on the wall behind the counter.
	for ix = 0, 31 do
		for iy = 0, 2 do
			if ix <= 10 or ix >= 26 then
				local color = if ix % 9 == 0 and iy == 1 then PAL.Counter
					else if (ix + iy) % 2 == 0 then PAL.TileWhite else PAL.Black
				box(f, "CheckerBacksplash", -110 + 5 * ix, 5 + 3 * iy, 102.02,
					-105 + 5 * ix, 8 + 3 * iy, 102.08, color, TILE, false)
			end
		end
	end
	for _, x in { -75, 5 } do
		glow(f, "CounterWarmLight", x - 2, 27.6, 119, x + 2, 28, 123, PAL.NeonAmber, 0.55, 22)
	end
	-- black/white/red checker along the counter queue edge
	overlay(f, "Checker_White", -106, 125, 50, 131, PAL.CounterWhite, TILE)
	for k = 0, 24, 2 do
		overlay(f, "Checker_Black", -106 + 6 * k, 125, -100 + 6 * k, 131, PAL.Black, TILE, 2)
	end
	overlay(f, "Checker_Red", -106, 131, 50, 131.6, PAL.Counter, TILE)

	-- Empty framed glass popcorn case on the left counter at x[-101,-81]: bare deck,
	-- hanging kettle and warm lamp, no popcorn fill.
	local popper = Instance.new("Model")
	popper.Name = "PopcornCase"
	popper:SetAttribute("Empty", true)
	popper.Parent = f
	local x0, x1, z0, z1, y0, y1 = -101, -81, 112, 120, 5.5, 12
	box(popper, "CaseBase", x0, 4.5, z0, x1, y0, z1, PAL.Counter)
	box(popper, "CaseDeck", x0 + 0.4, y0, z0 + 0.4, x1 - 0.4, y0 + 0.1, z1 - 0.4, PAL.Chrome, METAL)
	box(popper, "CaseRoof", x0 - 0.2, y1, z0 - 0.2, x1 + 0.2, y1 + 1, z1 + 0.2, PAL.Counter)
	for _, c in { { x0, z0 }, { x1 - 0.4, z0 }, { x0, z1 - 0.4 }, { x1 - 0.4, z1 - 0.4 } } do
		box(popper, "CasePost", c[1], y0, c[2], c[1] + 0.4, y1, c[2] + 0.4, PAL.Chrome, METAL)
	end
	for _, g in { { x0 + 0.4, z0, x1 - 0.4, z0 + 0.1 }, { x0 + 0.4, z1 - 0.1, x1 - 0.4, z1 }, { x0, z0 + 0.4, x0 + 0.1, z1 - 0.4 }, { x1 - 0.1, z0 + 0.4, x1, z1 - 0.4 } } do
		box(popper, "CaseGlass", g[1], y0, g[2], g[3], y1, g[4], PAL.Glass, GLASS).Transparency = 0.84
	end
	box(popper, "EmptyWarmingTray", -99, 5.65, 117.5, -83, 5.85, 119.3,
		PAL.Chrome, METAL, false)
	box(popper, "KettleRod", -91.15, 10.5, 115.85, -90.85, y1, 116.15, PAL.Chrome, METAL, false)
	disc(popper, "Kettle", -91, 116, 3, 9.3, 10.5, PAL.Chrome, METAL, false)
	glow(popper, "CaseLamp", x0 + 1, y1 - 0.3, z0 + 0.6, x1 - 1, y1 - 0.1, z0 + 0.9, PAL.NeonAmber, 0.7, 12)
	label(box(popper, "CaseSign", x0, y1 + 1, z1, x1, y1 + 2.6, z1 + 0.2, PAL.Counter, SP, false), Enum.NormalId.Back, "POPCORN", PAL.NeonAmber)
	-- Compact enclosed candy case beneath CANDY, with the old open shelves removed.
	box(f, "CandyCaseBase", 33, 4.5, 109, 49, 5.2, 119,
		PAL.Charcoal, METAL, false)
	box(f, "CandyCaseRoof", 32.8, 11, 108.8, 49.2, 11.4, 119.1,
		PAL.Charcoal, METAL, false)
	for _, x in { 33, 48.6 } do
		box(f, "CandyCaseFrontPost", x, 5.2, 118.7,
			x + 0.4, 11, 119.1, PAL.Chrome, METAL, false)
	end
	box(f, "CandyCaseFrontGlass", 33.4, 5.2, 118.85,
		48.6, 11, 119, PAL.Glass, GLASS, false).Transparency = 0.68
	for _, x in { 33, 48.85 } do
		box(f, "CandyCaseSideGlass", x, 5.2, 109.3,
			x + 0.15, 11, 118.7, PAL.Glass, GLASS, false).Transparency = 0.72
	end
	glow(f, "CandyCaseWarmStrip", 33.5, 10.7, 118.5,
		48.5, 10.85, 118.75, PAL.NeonAmber, 0.2, 10)
	for _, y in { 5.2, 7, 8.8 } do
		box(f, "CandyShelf", 33.4, y, 109.8,
			48.6, y + 0.2, 118.7, PAL.Charcoal, METAL, false)
		for col, x in { 34.2, 39, 43.8 } do
			box(f, "CandyPack", x, y + 0.2, 111,
				x + 3.5, y + 1.55, 115.2,
				({ Color3.fromRGB(145, 35, 25), Color3.fromRGB(172, 112, 42),
					Color3.fromRGB(100, 61, 66) })[col], SP, false)
			box(f, "CandyWrapper", x + 0.2, y + 0.6, 115.2,
				x + 3.3, y + 1.15, 115.3,
				Color3.fromRGB(218, 188, 126), SP, false)
		end
	end

	-- Six standing tables left of the entry-to-concourse route.
	for _, x in { -80, -30, 20 } do
		for _, z in { 165, 205 } do
			standingTable(f, "StandingTable", x, z)
		end
	end

	-- Curved layered marquee, joined to both partition walls and flush to the ceiling.
	-- Segments overlap slightly so no bright line ends in open space.
	for segment = 1, 16 do
		local xa = -120 + (segment - 1) * 15
		local xb = xa + 15
		local function arcZ(x)
			return 169 + 19 * (x / 120) ^ 2
		end
		local a = Vector3.new(xa, 27.84, arcZ(xa))
		local b = Vector3.new(xb, 27.84, arcZ(xb))
		local cf = CFrame.lookAt((a + b) / 2, b)
		local length = (b - a).Magnitude + 0.45
		part(f, "CurvedMarqueeFascia", Vector3.new(8.4, 1.8, length), cf * CFrame.new(0, -0.9, 0), PAL.Counter, SP, false)
		for _, stripe in { { 0, PAL.NeonRed }, { 5, PAL.NeonCyan } } do
			part(f, "CurvedMarqueeTube", Vector3.new(0.55, 0.3, length), cf * CFrame.new(stripe[1] - 2.5, -1.85, 0), stripe[2], NEON, false)
		end
	end
	for _, x in { -90, -30, 30, 90 } do
		local z = 169 + 19 * (x / 120) ^ 2
		light(box(f, "MarqueeGlow", x - 0.1, 25.8, z - 0.1, x + 0.1, 26, z + 0.1,
			PAL.NeonAmber, NEON, false), "PointLight", PAL.NeonAmber, 1.15, 48)
	end
	for _, x in { -70, 0, 70 } do
		for _, z in { 140, 215 } do
			light(disc(f, "Downlight", x, z, 4, 27.7, 28, PAL.NeonWarmWhite, NEON, false), "PointLight", PAL.Warm, 0.8, 40)
		end
	end
	-- dark charcoal lower wall band on the red walls
	box(f, "LowerBand", -120, 0, 102, -119.8, 4, 238, PAL.Charcoal, SP, false)
	box(f, "LowerBand", 119.8, 0, 102, 120, 4, 238, PAL.Charcoal, SP, false)
	box(f, "LowerBand", -120, 0, 237.8, -25, 4, 238, PAL.Charcoal, SP, false)
	box(f, "LowerBand", 25, 0, 237.8, 120, 4, 238, PAL.Charcoal, SP, false)
	for _, span in { { -120, -24 }, { 24, 120 } } do
		finish(box(f, "WornSouthPlaster", span[1], 4, 237.72, span[2], 27, 237.95,
			PAL.CorridorWall, SP, false), Enum.NormalId.Front,
			WALL_BASE, 18, 18)
	end
end

local function buildArcade(model)
	local f = folder(model, "Arcade")
	carpet(overlay(f, "Arcade_Carpet", 122, 102, 259, 238), "Ring")
	-- The shared service opening is removed: the next bay now holds restrooms.
	local divider = box(f, "ArcadeRestroomDivider", 259, 0, 102, 261, 28, 238,
		PAL.CorridorWall)
	finish(divider, Enum.NormalId.Left, WALL_BASE, 14, 14)
	-- Storage fills the wide shell wings; the played arcade has a 26-stud
	-- clear centre aisle between deep, facing cabinet rows.
	box(f, "ArcadeWestStore", 122, 0, 112, 156, 28, 238, PAL.Teal)
	box(f, "ArcadeEastStore", 228, 0, 112, 259, 28, 238, PAL.Teal)
	local leftWall = box(f, "ArcadeWestWornWall", 156, 4, 112,
		156.2, 28, 238, PAL.CorridorWall, SP, false)
	finish(leftWall, Enum.NormalId.Right, WALL_BASE, 14, 14)
	local rightWall = box(f, "ArcadeEastWornWall", 227.8, 4, 112,
		228, 28, 238, PAL.CorridorWall, SP, false)
	finish(rightWall, Enum.NormalId.Left, WALL_BASE, 14, 14)
	local backWall = box(f, "ArcadeRearWornWall", 156, 4, 237.65,
		228, 28, 237.9, PAL.CorridorWall, SP, false)
	finish(backWall, Enum.NormalId.Front, WALL_BASE, 14, 14)
	-- Fixed sidelights narrow the broad shell aperture to a proportionate double door.
	box(f, "ArcadeSidelight", 150, 0, 100.6, 154, 12, 101.4, PAL.TintGlass, GLASS)
	box(f, "ArcadeSidelight", 174, 0, 100.6, 178, 12, 101.4, PAL.TintGlass, GLASS)
	local arcadeLeft = swingLeaf(f, "ArcadeLeft",
		CFrame.new(154.4, 5.5, 101), 9.2, 10.5, PAL.Counter, -95)
	local arcadeRight = swingLeaf(f, "ArcadeRight",
		CFrame.new(173.6, 5.5, 101) * CFrame.Angles(0, math.pi, 0),
		9.2, 10.5, PAL.Counter, 95)
	swingZone(f, "ArcadeEntry", CFrame.new(164, 5.5, 101),
		Vector3.new(28, 11, 14), { arcadeLeft, arcadeRight })
	local names = { "STAR VECTORS", "NOVA RUN", "SOLAR STRIKE", "NEON DRIFT" }
	local function cabinet(name, x0, x1, z0, faceEast, index)
		local z1 = z0 + 11
		local case = box(f, name .. "_Body", x0, 0, z0, x1, 9.3, z1,
			if index % 3 == 0 then PAL.Teal else PAL.Cabinet)
		case:SetAttribute("ArcadeCabinet", true)
		local screenX = if faceEast then x1 else x0
		local screen = box(f, name .. "_Screen", screenX - 0.1, 4.8, z0 + 1.5,
			screenX + 0.1, 8, z1 - 1.5, PAL.DarkScreen, GLASS, false)
		screen.Reflectance = 0.2
		local gameArt = Instance.new("Decal")
		gameArt.Name = "OriginalGameScreen"
		gameArt.Face = if faceEast then Enum.NormalId.Right else Enum.NormalId.Left
		gameArt.Texture = ARCADE_SCREENS[(index - 1) % #ARCADE_SCREENS + 1]
		gameArt.Parent = screen
		local marquee = box(f, name .. "_Marquee", screenX - 0.16, 8.1, z0 + 0.5,
			screenX + 0.16, 9.1, z1 - 0.5,
			if index % 2 == 0 then PAL.NeonAmber else PAL.NeonCyan, NEON, false)
		label(marquee, if faceEast then Enum.NormalId.Right else Enum.NormalId.Left,
			names[(index - 1) % #names + 1], PAL.White)
		local controlX0 = if faceEast then x1 else x0 - 3
		local controlX1 = controlX0 + 3
		box(f, name .. "_Controls", controlX0, 3.5, z0 + 1.5,
			controlX1, 4.3, z1 - 1.5, PAL.Charcoal, METAL, false)
		disc(f, name .. "_Button", (controlX0 + controlX1) / 2,
			z0 + 4, 0.7, 4.3, 4.7, PAL.NeonRed, NEON, false)
	end
	-- Two facing cabinet rows; unlike V5, the centre is a continuous aisle.
	for i, z in { 119, 133, 147, 161, 175, 189, 203 } do
		if i > 1 then cabinet("ArcadeLeft" .. i, 158, 176, z, true, i) end
		cabinet("ArcadeRight" .. i, 208, 226, z, false, i + 1)
	end
	-- Black worn stone posts frame the prize counter without narrowing the aisle.
	for _, x in { 151, 223 } do
		local p = box(f, "ArcadeStonePier", x, 0, 110, x + 5, 28, 115,
			PAL.Charcoal, SP)
		for _, face in { Enum.NormalId.Front, Enum.NormalId.Back,
			Enum.NormalId.Left, Enum.NormalId.Right } do
			finish(p, face, "rbxassetid://93523123874495", 8, 8)
		end
	end
	box(f, "PrizeCounter", 175, 0, 224, 209, 5, 237, PAL.Charcoal, METAL)
	box(f, "PrizeGlass", 176, 5, 228, 208, 8.5, 236.5, PAL.Glass, GLASS, false).Transparency = 0.4
	for _, y in { 9, 14, 19 } do
		box(f, "PrizeShelf", 174, y, 235, 210, y + 0.5, 237, PAL.Crate, WOOD)
		for _, x in { 177, 184, 191, 198, 205 } do
			box(f, "PrizeBox", x, y + 0.5, 235.3,
				x + 4, y + 4, 236.5, if y == 14 then PAL.NeonBlue else PAL.Counter,
				SP, false)
		end
	end
	box(f, "PrizeSideDoor", 211, 0, 237.4, 225, 13, 237.8,
		PAL.Charcoal, METAL, false)
	box(f, "PrizeDoorHandle", 214, 5, 237.1, 215, 7, 237.4,
		PAL.Chrome, METAL, false)
	for _, z in { 151, 194 } do
		disc(f, "ArcadeStoolSeat", 190, z, 5.2, 4.7, 5.2,
			PAL.Crate, WOOD, false)
		disc(f, "ArcadeStoolStem", 190, z, 0.8, 0, 4.7,
			PAL.Metal, METAL, false)
	end
	-- A single red/cyan ceiling focal rectangle replaces the two full-room tubes.
	for i, strip in {
		{ 172, 159, 209, 159.3, PAL.NeonRed },
		{ 172, 181.7, 209, 182, PAL.NeonRed },
		{ 172, 159, 172.3, 182, PAL.NeonRed },
		{ 208.7, 159, 209, 182, PAL.NeonRed },
		{ 180, 164, 201, 164.3, PAL.NeonCyan },
		{ 180, 176.7, 201, 177, PAL.NeonCyan },
	} do
		local neon = box(f, "ArcadeCeilingNeon", strip[1], 27.5, strip[2],
			strip[3], 27.8, strip[4], strip[5], NEON, false)
		if i == 2 then neon:SetAttribute("OccasionalFlicker", true) end
	end
	local flicker = glow(f, "ArcadeFlickerTube", 156.2, 25.5, 210,
		156.55, 25.8, 219, PAL.NeonCyan, 0.55, 32)
	flicker:SetAttribute("OccasionalFlicker", true)
end
local function census(model)
	local parts, lights = 0, 0
	for _, d in model:GetDescendants() do
		if d:IsA("BasePart") then
			parts += 1
		elseif d:IsA("Light") then
			lights += 1
		end
	end
	return parts, lights
end

function V7.Build(originCFrame)
	origin = originCFrame or CFrame.identity
	local model = Instance.new("Model")
	model.Name = V7.MODEL_NAME
	folder(model, "AutomaticDoors")
	buildShell(model)
	for i, hall in HALLS do
		buildHall(model, hall, i)
	end
	for _, c in CORRIDORS do
		buildCorridor(model, c)
	end
	buildHiddenService(model)
	buildConcourse(model)
	buildFork(model)
	buildRestrooms(model)
	buildService(model)
	buildConcession(model)
	buildArcade(model)
	local doorMotion = Instance.new("Script")
	doorMotion.Name = "AutomaticDoorMotion"
	doorMotion.Source = [[
local Players = game:GetService("Players")
local doorsFolder = script.Parent
local model = doorsFolder.Parent
local doors = {}
for _, zone in doorsFolder:GetChildren() do
	if zone:IsA("BasePart") and zone:GetAttribute("AutoDoorZone") then
		local hinges = {}
		for _, ref in zone:GetChildren() do
			if ref:IsA("ObjectValue") and ref.Name == "DoorHinge"
				and ref.Value and ref.Value:IsA("HingeConstraint") then
				local hinge = ref.Value
				table.insert(hinges, hinge)
				local leaf = hinge.Attachment1 and hinge.Attachment1.Parent
				if leaf and leaf:IsA("BasePart") then
					pcall(function() leaf:SetNetworkOwner(nil) end)
				end
			end
		end
		assert(#hinges > 0, "Auto door has no hinge: " .. zone:GetFullName())
		table.insert(doors, { zone = zone, hinges = hinges, open = false,
			side = 1, lastSeen = -math.huge })
	end
end
local function occupant(zone)
	local half = zone.Size * 0.5
	for _, player in Players:GetPlayers() do
		local character = player.Character
		if character then
			local humanoid = character:FindFirstChildOfClass("Humanoid")
			local root = character:FindFirstChild("HumanoidRootPart")
			if humanoid and humanoid.Health > 0 and root then
				local p = zone.CFrame:PointToObjectSpace(root.Position)
				if math.abs(p.X) <= half.X and math.abs(p.Y) <= half.Y
					and math.abs(p.Z) <= half.Z then
					return true, (if p.Z < 0 then 1 else -1)
				end
			end
		end
	end
	return false, nil
end
local function setOpen(door, open, approachSide)
	if door.open == open then return end
	door.open = open
	if open then door.side = approachSide or 1 end
	for _, hinge in door.hinges do
		if hinge.Parent then
			local leaf = hinge.Attachment1 and hinge.Attachment1.Parent
			if open and hinge:GetAttribute("NonBlockingWhenOpen") and leaf then
				leaf.CanCollide = false
			end
			hinge.AngularSpeed = if open then 3 else 0.65
			hinge.TargetAngle = if open then
				(hinge:GetAttribute("FixedOpenAngle")
					or (hinge:GetAttribute("OpenAngle") or 95) * door.side) else 0
		end
	end
end
while model:IsDescendantOf(workspace) do
	local now = os.clock()
	for _, door in doors do
		local present, side = occupant(door.zone)
		if present then
			door.lastSeen = now
			setOpen(door, true, side)
		elseif door.open and now - door.lastSeen >= 1.4 then
			setOpen(door, false)
		end
		if not door.open then
			for _, hinge in door.hinges do
				if hinge:GetAttribute("NonBlockingWhenOpen")
					and math.abs(hinge.CurrentAngle) < 2 then
					local leaf = hinge.Attachment1 and hinge.Attachment1.Parent
					if leaf then leaf.CanCollide = true end
				end
			end
		end
	end
	task.wait(0.1)
end
]]
	doorMotion.Parent = model.AutomaticDoors
	local flicker = Instance.new("Script")
	flicker.Name = "OccasionalFixtureFlicker"
	flicker.Source = [[
local model = script.Parent
local fixtures = {}
for _, part in model:GetDescendants() do
	if part:IsA("BasePart") and part:GetAttribute("OccasionalFlicker") then
		table.insert(fixtures, part)
	end
end
while model:IsDescendantOf(workspace) and #fixtures > 0 do
	task.wait(math.random(12, 24))
	if not model:IsDescendantOf(workspace) then break end
	local part = fixtures[math.random(1, #fixtures)]
	local point = part:FindFirstChildOfClass("PointLight")
	if part:IsDescendantOf(model) then
		local oldMaterial, oldColor, oldTransparency = part.Material, part.Color, part.Transparency
		local oldLight = point and point.Enabled
		if point then point.Enabled = false end
		part.Material = Enum.Material.SmoothPlastic
		part.Color = oldColor:Lerp(Color3.new(0, 0, 0), 0.8)
		part.Transparency = math.min(0.8, oldTransparency + 0.55)
		task.wait(0.08)
		if part.Parent then
			part.Material, part.Color, part.Transparency = oldMaterial, oldColor, oldTransparency
			if point and point.Parent then point.Enabled = oldLight end
		end
	end
end
]]
	flicker.Parent = model
	model.WorldPivot = origin
	local parts, lights = census(model)
	model:SetAttribute("Level4LayoutVersion", V7.LAYOUT_VERSION)
	model:SetAttribute("Level4Revision", 7)
	model:SetAttribute("Level4PreviewReady", true)
	model:SetAttribute("Level4Preview", true)
	model:SetAttribute("PreviewOnly", true)
	model:SetAttribute("PartCount", parts)
	model:SetAttribute("LightCount", lights)
	return model
end

-- Floor probes, doorway clearance rays, chair/doorway counts and the part/light budget.
-- The model must be in Workspace.
function V7.SelfCheck(model)
	local issues = {}
	local pivot = model.WorldPivot
	local params = RaycastParams.new()
	params.FilterType = Enum.RaycastFilterType.Include
	params.FilterDescendantsInstances = { model }
	-- Moving leaves are closed in the built scene. Test the architectural opening
	-- and floor beneath them here; door collision and motion are checked in Play.
	local movingLeaves = {}
	local automaticDoors = model:FindFirstChild("AutomaticDoors")
	if automaticDoors then
		for _, child in automaticDoors:GetChildren() do
			if child:IsA("BasePart") and child:GetAttribute("AutoDoorLeaf") then
				table.insert(movingLeaves, child)
			end
		end
	end
	params.ExcludeInstances = movingLeaves
	local down = pivot:VectorToWorldSpace(Vector3.new(0, -8, 0))
	for _, p in PROBES do
		local hit = workspace:Raycast(pivot * Vector3.new(p[2], p[4] + 4, p[3]), down, params)
		local y = if hit then pivot:PointToObjectSpace(hit.Position).Y else nil
		if not y or math.abs(y - p[4]) > 0.1 then
			table.insert(issues, string.format("floor %s: expected y%.2f, got %s", p[1], p[4], tostring(y)))
		end
	end
	for _, crossing in {
		{ "south stair vestibule", -330, 93, 3, -350, 93, 3 },
		{ "north gallery landing", -350, 5, 65, -330, 5, 65 },
	} do
		local start = pivot * Vector3.new(crossing[2], crossing[4], crossing[3])
		local direction = pivot:VectorToWorldSpace(Vector3.new(
			crossing[5] - crossing[2], crossing[7] - crossing[4], crossing[6] - crossing[3]))
		local hit = workspace:Raycast(start, direction, params)
		if hit then
			table.insert(issues, crossing[1] .. " blocked by " .. hit.Instance.Name)
		end
	end
	local chairs, doors = 0, 0
	for _, d in model:GetDescendants() do
		if d:IsA("BasePart") then
			local p = pivot:PointToObjectSpace(d.Position)
			if math.abs(p.X) > 400 or p.Y < -5 or p.Y > 90 or math.abs(p.Z) > 250 then
				table.insert(issues, d.Name .. " outside Level 4 shell")
			end
		end
		if d:IsA("BasePart") and CollectionService:HasTag(d, SEAT_TAG) then
			chairs += 1
		elseif d:IsA("BasePart") and CollectionService:HasTag(d, DOOR_TAG) then
			doors += 1
			local cf, size = d.CFrame, d.Size
			local axis = if size.X < size.Z then cf.RightVector else cf.LookVector
			local reach = math.min(size.X, size.Z) / 2 + 1.5
			for _, dy in { 2.5 - size.Y / 2, 0 } do
				local c = cf.Position + cf.UpVector * dy
				local hit = workspace:Raycast(c - axis * reach, axis * reach * 2, params)
				if hit then
					table.insert(issues, d.Name .. " blocked by " .. hit.Instance.Name)
				end
			end
		end
	end
	if chairs ~= #HALLS * V7.CHAIRS_PER_HALL then
		table.insert(issues, string.format("chairs: expected %d, got %d", #HALLS * V7.CHAIRS_PER_HALL, chairs))
	end
	if doors ~= V7.DOORWAYS then
		table.insert(issues, string.format("doorways: expected %d, got %d", V7.DOORWAYS, doors))
	end
	local parts, lights = census(model)
	if parts >= V7.MAX_PARTS or lights >= V7.MAX_LIGHTS then
		table.insert(issues, string.format("over budget: %d parts, %d lights", parts, lights))
	end
	return #issues == 0, { Issues = issues, PartCount = parts, LightCount = lights }
end

return V7
