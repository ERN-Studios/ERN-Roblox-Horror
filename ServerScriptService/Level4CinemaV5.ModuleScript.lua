-- Level 4 cinema, approved V5 public corridors and concealed projection route.
-- Static architecture only: no entities or objectives, and no dependency on older Level 4 modules.
--
--   local V5 = require(path.to.Level4CinemaV5)
--   local model = V5.Build(CFrame.new(23000, 24, 0)) -- returned unparented
--   model.Parent = workspace
--   print(V5.SelfCheck(model))                       -- needs the model in Workspace
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
--   Hidden core x[-376,-324] z[0,98] ascends to gallery y62, x[-376,376] z[-20,0].
--   Concourse x[-378,378] z[-20,100], roof y[36,37], with split roof at the core.
--   South z[102,238]: restrooms x[-376,-122], concessions x[-120,120], arcade/service x[122,376].

local CollectionService = game:GetService("CollectionService")

local V5 = {}

V5.MODEL_NAME = "Level 4 Cinema Preview"
V5.LAYOUT_VERSION = 4
V5.MAX_PARTS = 5000
V5.MAX_LIGHTS = 140
V5.CHAIRS_PER_HALL = 396
V5.DOORWAYS = 21 -- V4's 19 openings plus concealed staff entry and upper-gallery entry

local FLOOR_TAG = "Level4V4Floor"
local DOOR_TAG = "Level4V4Doorway"
local SEAT_TAG = "Level4V4Seat"
V5.TAGS = { Floor = FLOOR_TAG, Doorway = DOOR_TAG, Seat = SEAT_TAG, Exit = "Level4V4Exit" }

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

-- Verified Level 4 imagegen carpet uploads (assets/level4/v5/TEXTURE_ASSETS.md).
local CARPET = {
	Red = { "rbxassetid://92732673815453", 12, Color3.fromRGB(128, 20, 16) },
	Swirl = { "rbxassetid://127784354194812", 72, Color3.fromRGB(104, 38, 40) },
	Service = { "rbxassetid://132321859875122", 8, Color3.fromRGB(62, 18, 24) },
	Ring = { "rbxassetid://85044000846144", 12, Color3.fromRGB(62, 26, 84) },
}
local POSTERS = {
	{ "rbxassetid://90273706821327", "ECLIPSE VOYAGE" },
	{ "rbxassetid://78063750109486", "LAST SHOWING" },
	{ "rbxassetid://98375790871589", "AFTERLIGHT RUN" },
	{ "rbxassetid://70369867264188", "THE GLASS TIDE" },
	{ "rbxassetid://71191268393019", "VIOLET PIER" },
}

local PAL = {
	Shell = Color3.fromRGB(24, 18, 20),
	HallWall = Color3.fromRGB(18, 44, 48), -- dark teal acoustic finish
	CorridorWall = Color3.fromRGB(141, 54, 30),
	Partition = Color3.fromRGB(157, 62, 33),
	Ceiling = Color3.fromRGB(10, 8, 9),
	FoyerCeiling = Color3.fromRGB(162, 18, 11),
	LightCeiling = Color3.fromRGB(200, 200, 196),
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
	Stall = Color3.fromRGB(28, 92, 88),
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
	NeonMagenta = Color3.fromRGB(255, 40, 200),
	NeonViolet = Color3.fromRGB(150, 60, 255),
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
	{ -146, -126, 0, 12, "RestroomsDoorway", "RESTROOMS" },
	{ 55, 95, 0, 12, "ConcessionsDoorway", "CONCESSIONS" },
	{ 150, 178, 0, 12, "ArcadeDoorway", "ARCADE" },
	{ 280, 296, 0, 12, "ServiceDoorway", "SERVICE" },
}

V5.HALLS = HALLS
V5.CORRIDORS = CORRIDORS
V5.SOUTH_OPENINGS = SOUTH_OPENINGS

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
V5.AisleHeight = aisleY

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
	{ "Hidden core ground", -330, 92, 0 },
	{ "Staff approach bend", -349, 91, 0 }, { "Staff approach stair foot", -370, 87, 0 },
	{ "Hidden flight 1 start", -370, 83.5, 1 }, { "Hidden flight 1 end", -370, 50.5, 12 },
	{ "Hidden landing 12", -365, 48, 12 },
	{ "Hidden flight 2 start", -360, 50.5, 13 }, { "Hidden flight 2 end", -360, 83.5, 24 },
	{ "Hidden landing 24", -355, 86, 24 },
	{ "Hidden flight 3 start", -350, 83.5, 25 }, { "Hidden flight 3 end", -350, 50.5, 36 },
	{ "Hidden landing 36", -345, 48, 36 },
	{ "Hidden flight 4 start", -340, 50.5, 37 }, { "Hidden flight 4 end", -340, 86.5, 49 },
	{ "Hidden landing 49", -335, 89, 49 },
	{ "Hidden flight 5 start", -330, 86.5, 50 }, { "Hidden flight 5 end", -330, 50.5, 62 },
	{ "Hidden core upper walk", -330, 30, 62 }, { "Hidden core gallery threshold", -330, 1, 62 },
	{ "Gallery west", -300, -10, 62 }, { "Gallery middle", 0, -10, 62 },
	{ "Gallery east", 300, -10, 62 },
} do
	probe(p[1], p[2], p[3], p[4])
end
for _, p in {
	{ "Concourse centre", 0, 55 }, { "Concourse east carpet", 250, 40 }, { "Arrival", 0, 226 },
	{ "Concessions passage", 75, 160 }, { "Restroom vestibule", -135, 170 },
	{ "Arcade", 190, 170 }, { "Service", 300, 150 },
} do
	probe(p[1], p[2], p[3], 0)
end
probe("Men's room", -240, 140, 0.2)
probe("Women's room", -240, 200, 0.2)
V5.PROBES = PROBES

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

-- 4-stud-high standing table, 5.7 studs across at the rim.
local function standingTable(parent, name, x, z)
	disc(parent, name .. "Foot", x, z, 3, 0, 0.3, PAL.Chrome, METAL)
	box(parent, name .. "Stem", x - 0.3, 0.3, z - 0.3, x + 0.3, 3.6, z + 0.3, PAL.Chrome, METAL)
	disc(parent, name .. "Rim", x, z, 5.7, 3.6, 3.75, PAL.Counter)
	disc(parent, name .. "Top", x, z, 5.5, 3.7, 4, PAL.Board)
end

local function buildShell(model)
	local f = folder(model, "Shell")
	-- One collidable base slab under the whole footprint, never perforated. Room finishes
	-- live on separate surfaces, so their textures cannot show through each other.
	floor(box(f, "BaseSlab", -378, -1, -240, 378, 0, 240, PAL.Charcoal))
	-- One public carpet surface keeps the swirl phase continuous through all four corridors.
	carpet(overlay(f, "PublicSwirl", -376, -238, 376, 100), "Swirl")
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
	box(f, "CoreOuterFascia", -378, 36, 0, -376, 76, 98, PAL.CorridorWall)
	-- the x[-24,24] y[0,14] aperture holds the closed glass entry (Concession)
	wall(f, "ShellSouth", "X", -378, 378, 238, 240, 0, 28, PAL.Partition, SP, { { -24, 24, 0, 14 } })
	-- concourse | south rooms wall: solid above y12 up to the y36 concourse roof
	wall(f, "ConcourseSouthWall", "X", -376, 376, 100, 102, 0, 36, PAL.Partition, SP, SOUTH_OPENINGS)
	for _, o in SOUTH_OPENINGS do
		doorway(f, o[5], o[1], o[3], 100, o[2], o[4], 102)
		overlay(f, o[5] .. "Threshold", o[1], 100, o[2], 102, PAL.Charcoal, METAL, 2)
	end
	box(f, "Divider_RestroomsConcessions", -122, 0, 102, -120, 28, 238, PAL.Partition)
	box(f, "Divider_ConcessionsArcade", 120, 0, 102, 122, 28, 238, PAL.Partition)
	-- The concealed stair core occupies x[-376,-324] z[0,98]; split the low roof
	-- around it so the 62-stud ascent is not cut in half at y36.
	box(f, "ConcourseRoofWestEdge", -378, 36, -20, -376, 37, 102, PAL.Ceiling)
	box(f, "ConcourseRoofCoreNorth", -376, 36, -20, -324, 37, 0, PAL.Ceiling)
	box(f, "ConcourseRoofCoreSouth", -376, 36, 98, -324, 37, 102, PAL.Ceiling)
	box(f, "ConcourseRoofMain", -324, 36, -20, 378, 37, 102, PAL.Ceiling)
	box(f, "RestroomRoof", -378, 28, 102, -121, 29, 240, PAL.LightCeiling)
	box(f, "ConcessionRoof", -121, 28, 102, 121, 29, 240, PAL.FoyerCeiling)
	box(f, "ArcadeServiceRoof", 121, 28, 102, 378, 29, 240, PAL.Ceiling)
end

local function buildHall(model, hall, index)
	local id, xc = hall.Id, hall.X
	local scheme = HALL_COLORS[index]
	local f = folder(model, id)
	f:SetAttribute("CenterX", xc)
	local function b(name, u0, y0, z0, u1, y1, z1, color, mat, collide)
		return box(f, id .. "_" .. name, xc + u0, y0, z0, xc + u1, y1, z1, color, mat, collide)
	end

	-- Deck. The y0 screen apron z[-238,-204] is the base slab itself.
	carpet(overlay(f, id .. "_FrontApron", xc - 88, -238, xc + 88, -204, nil, nil, 2), "Red")
	for i = 1, 8 do
		floor(b("FrontTier" .. i, -88, 0, -212 + 8 * i, 88, 2 * i, -204 + 8 * i), "Red")
	end
	floor(b("CrossAisle", -88, 0, -140, 88, 18, -120), "Swirl")
	b("CrossAisleEdge", -78, 18, -120.2, 78, 18.3, -120, scheme.Edge, NEON, false)
	for r = 1, 10 do
		floor(b("RearTier" .. r, -78, 0, -129 + 9 * r, 78, 18 + 3 * r, -120 + 9 * r), "Red")
	end
	floor(b("TopWalk", -88, 0, -30, 88, 48, -22), "Swirl")

	-- Side aisles climb in 1-stud treads: the raised back half of each front tier, then three
	-- per rear tier. A cyan dot marks every row-level riser.
	for _, s in AISLES do
		local u0, u1 = s[1], s[2]
		local uc = (u0 + u1) / 2
		for i = 0, 8 do
			floor(b("FrontAisleTread", u0, 2 * i, -208 + 8 * i, u1, 2 * i + 1, -204 + 8 * i, PAL.Aisle, FABRIC))
		end
		for r = 1, 10 do
			for j = 0, 2 do
				local z0 = -129 + 9 * r + 3 * j
				floor(b("RearAisleTread", u0, 0, z0, u1, 16 + 3 * r + j, z0 + 3, PAL.Aisle, FABRIC))
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
	b("BoothWindow", -10, 65, -33.7, 10, 70, -33.3, PAL.Glass, GLASS).Transparency = 0.5
	-- A full front support joins the booth to the top walk behind the last seats.
	b("BoothSupportWall", -16, 48, -23, 16, 61, -22, PAL.Booth)
	b("BoothFrontSupport", -16, 48, -34, 16, 61, -33.1, PAL.Booth)
	b("BoothFrontLintel", -16, 59, -34, 16, 61, -32, PAL.Metal, METAL)
	b("ProjectorStand", -1, 62, -30, 1, 65, -27, PAL.Metal, METAL)
	light(b("Projector", -1.8, 65, -32, 1.8, 70, -26, PAL.Metal, METAL), "PointLight",
		PAL.NeonAmber, if index == 3 then 0.05 else 0.6, 14)
	b("ProjectorLens", -0.7, 66.8, -32.4, 0.7, 68.2, -32,
		if index == 3 then scheme.Edge else PAL.Warm, NEON, false)
end

local function buildCorridor(model, c)
	local id = c.Id
	local f = folder(model, id)
	box(f, id .. "_Roof", c.Span[1], 32, -240, c.Span[2], 33, -20, PAL.Ceiling)
	-- fascia closes the roof step without cutting across the concourse ceiling.
	finish(box(f, id .. "_MouthFascia", c.Span[1], 33, -22, c.Span[2], 36, -19.9,
		PAL.CorridorWall), Enum.NormalId.Back, "rbxassetid://93137661811831", 28, 28)
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
				if band[3] then finish(p, face, "rbxassetid://93137661811831", 28, 28) end
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
		finish(p, Enum.NormalId.Left, "rbxassetid://93137661811831", 28, 28)
		finish(p, Enum.NormalId.Right, "rbxassetid://93137661811831", 28, 28)
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
		for k = 1, 17 do
			floor(box(f, name .. "_Tread" .. k, a, 0, -30 - 5 * k, b, k, -25 - 5 * k, PAL.Aisle, FABRIC))
		end
		local landing = floor(box(f, name .. "_Landing", a, 0, -145, b, 18, -115), "Swirl")
		landing.SwirlCarpet.StudsPerTileU = 72
		landing.SwirlCarpet.StudsPerTileV = 72
		box(f, name .. "_LandingGuard", a, 18, -145, b, 31, -144, PAL.CorridorWall)
		for _, z in { -130, -70 } do
			glow(f, name .. "_Light", a + 2, 31.4, z - 2, b - 2, 32, z + 2, PAL.Warm, 0.7, 24)
		end
	end
	local rc = (c.Return[1] + c.Return[2]) / 2
	for _, z in { -225, -130, -40 } do
		glow(f, id .. "_ReturnLight", rc - 2, 31.4, z - 3, rc + 2, 32, z + 3, PAL.Warm, 0.8, 40)
	end
end

-- Enclosed service circulation: one hidden ground entrance, five protected switchback
-- flights to y62, then one gallery behind the three rear projection booths.
local function buildHiddenService(model)
	local f = folder(model, "HiddenService")
	carpet(overlay(f, "StaffGroundRunner", -376, 2, -324, 98, nil, nil, 2), "Service")

	-- This full-height core occupies the hole deliberately left in the y36 concourse roof.
	finish(box(f, "CoreWest", -376, 0, 0, -374, 76, 98, PAL.Teal), Enum.NormalId.Right,
		"rbxassetid://78643712450081", 14, 14)
	wall(f, "CoreEast", "Z", 0, 98, -326, -324, 0, 76, PAL.Teal, SP,
		{ { 86, 96, 0, 12 } })
	finish(box(f, "CoreSouth", -376, 0, 96, -324, 76, 98, PAL.Teal), Enum.NormalId.Front,
		"rbxassetid://78643712450081", 14, 14)
	wall(f, "CoreNorth", "X", -376, -324, 0, 2, 0, 76, PAL.Teal, SP,
		{ { -334, -326, 62, 72 } })
	box(f, "CoreRoof", -376, 76, 0, -324, 77, 98, PAL.Ceiling)
	doorway(f, "SecretPosterEntry", -326, 0, 86, -324, 12, 96)
	doorway(f, "GalleryStairEntry", -334, 62, 0, -326, 72, 2)
	-- The poster panel rests open against the jamb. Its art is attached during polish.
	local panel = part(f, "SecretPosterPanel", Vector3.new(0.5, 14, 10),
		CFrame.new(-322.8, 7, 85.5) * CFrame.Angles(0, math.rad(-65), 0), PAL.Black, METAL, false)
	panel:SetAttribute("ConcealedEntrance", true)
	local art = Instance.new("Decal")
	art.Name = "LastShowingArt"
	art.Face = Enum.NormalId.Right
	art.Texture = "rbxassetid://78063750109486"
	art.Parent = panel
	frame(f, "ConcealedPosterFrame", "Z", -324, 1, 86, 96, 0, 12, PAL.Frame)
	for _, p in f:GetChildren() do
		if p:IsA("BasePart") then
			if p.Name:find("^CoreEast") then
				finish(p, Enum.NormalId.Left, "rbxassetid://78643712450081", 14, 14)
				finish(p, Enum.NormalId.Right, "rbxassetid://93137661811831", 14, 14)
			elseif p.Name:find("^CoreNorth") then
				finish(p, Enum.NormalId.Back, "rbxassetid://78643712450081", 14, 14)
			end
		end
	end
	for _, z in { 2, 98 } do
		box(f, "CoreBaseboard", -374, 0, z - 0.2, -326, 3, z, PAL.Charcoal, SP, false)
	end

	local flights = {
		{ "Flight1", -374, -366, 85, -1, 12, 0 },
		{ "Flight2", -364, -356, 49, 1, 12, 12 },
		{ "Flight3", -354, -346, 85, -1, 12, 24 },
		{ "Flight4", -344, -336, 49, 1, 13, 36 },
		{ "Flight5", -334, -326, 88, -1, 13, 49 },
	}
	for _, flight in flights do
		local name, x0, x1, startZ, direction, steps, baseY = table.unpack(flight)
		if baseY > 0 then
			local support = box(f, name .. "_Understructure", x0, 0, 49, x1, baseY, 80, PAL.Teal)
			finish(support, Enum.NormalId.Left, "rbxassetid://78643712450081", 14, 14)
			finish(support, Enum.NormalId.Right, "rbxassetid://78643712450081", 14, 14)
			if baseY > 12 then
				box(f, name .. "_LandingBracket", x0, 12.5, 82, x1, baseY, 85,
					PAL.Charcoal)
			end
		end
		for k = 1, steps do
			local z0 = if direction < 0 then startZ - 3 * k else startZ + 3 * (k - 1)
			floor(box(f, name .. "_Tread" .. k, x0, baseY, z0, x1, baseY + k, z0 + 3), "Service")
		end
		for _, railX in { x0 + 0.35, x1 - 0.35 } do
			local a = Vector3.new(railX, baseY + 4, startZ)
			local b = Vector3.new(railX, baseY + steps + 4, startZ + direction * steps * 3)
			part(f, name .. "_Handrail", Vector3.new(0.25, 0.25, (b - a).Magnitude),
				CFrame.lookAt((a + b) / 2, b), PAL.Chrome, METAL, false)
		end
	end
	for _, landing in {
		{ "Landing12", -374, -356, 47, 49, 12 },
		{ "Landing24", -364, -346, 85, 87, 24 },
		{ "Landing36", -354, -336, 47, 49, 36 },
		{ "Landing49", -344, -326, 88, 90, 49 },
	} do
		floor(box(f, landing[1], landing[2], landing[6] - 1, landing[4], landing[3], landing[6], landing[5]), "Service")
	end
	-- The poster opens into a low, curved staff return. Thin upper landings leave
	-- this ground passage clear; its end turns into the first protected stair.
	box(f, "StaffApproachSoffit", -366, 12.5, 82, -326, 13, 96, PAL.Ceiling)
	local bend = { { -326, 85 }, { -336, 83.4 }, { -346, 82.7 }, { -356, 83.2 }, { -366, 85 } }
	for i = 1, #bend - 1 do
		local a = Vector3.new(bend[i][1], 0, bend[i][2])
		local b = Vector3.new(bend[i + 1][1], 0, bend[i + 1][2])
		local cf = CFrame.lookAt((a + b) / 2 + Vector3.new(0, 6.2, 0), b + Vector3.new(0, 6.2, 0))
		local curveWall = part(f, "StaffCurveWall", Vector3.new(1.3, 12.4, (b - a).Magnitude + 0.3),
			cf, PAL.Teal)
		finish(curveWall, Enum.NormalId.Left, "rbxassetid://78643712450081", 12, 12)
		finish(curveWall, Enum.NormalId.Right, "rbxassetid://78643712450081", 12, 12)
		part(f, "StaffCurveCove", Vector3.new(0.22, 0.3, (b - a).Magnitude + 0.3),
			cf + Vector3.new(0, 5.7, 0.8), PAL.NeonWarmWhite, NEON, false)
	end
	for _, x in { -332, -347, -361 } do
		box(f, "StaffApproachLampHousing", x - 1.6, 12.1, 88.5, x + 1.6, 12.5, 91.5,
			PAL.Charcoal, METAL, false)
		light(box(f, "StaffApproachLampLens", x - 1.15, 12.04, 89.05, x + 1.15, 12.13, 90.95,
			PAL.NeonAmber, NEON, false), "PointLight", PAL.Warm, 0.22, 12)
	end
	for _, dividerX in { -366, -356, -346, -336 } do
		box(f, "StairGuard", dividerX, 0, 52, dividerX + 2, 75, 82, PAL.Charcoal)
	end
	floor(box(f, "UpperCoreWalk", -334, 61, 2, -326, 62, 49), "Service")
	for _, z in { 22, 60, 92 } do
		glow(f, "CoreLamp", -374, 72, z - 1, -373.6, 74, z + 1, PAL.NeonAmber, 0.5, 32)
	end
	for _, p in { { -371, 9, 78 }, { -360, 21, 55 }, { -350, 33, 78 },
		{ -340, 45, 55 }, { -329, 58, 78 } } do
		glow(f, "StairSconce", p[1] - 0.4, p[2], p[3] - 1, p[1], p[2] + 2, p[3] + 1,
			PAL.NeonAmber, 0.4, 18)
	end

	-- Gallery floor touches the booths' aligned y62 rear thresholds. The low public
	-- concourse roof remains directly beneath it, with a closed fascia on its south face.
	floor(box(f, "GalleryFloor", -376, 61, -20, 376, 62, 0), "Service")
	box(f, "GalleryRoof", -376, 75, -20, 376, 76, 0, PAL.Ceiling)
	wall(f, "GalleryNorth", "X", -376, 376, -20, -19, 62, 75, PAL.Teal, SP,
		{ { -239, -229, 62, 72 }, { -5, 5, 62, 72 }, { 229, 239, 62, 72 } })
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
			disc(f, "ConcourseColumn", x, z, 8, 0, 36, PAL.Partition)
			disc(f, "ConcourseColumnBase", x, z, 8.6, 0, 3, PAL.Charcoal)
			disc(f, "ConcourseColumnAmberCollar", x, z, 8.3, 34.9, 35.15, PAL.NeonAmber, NEON, false)
		end
	end
	-- Continuous three-colour cove paths follow every visible concourse edge.
	for _, stripe in {
		{ 33.8, PAL.NeonMagenta }, { 34.55, PAL.NeonBlue }, { 35.3, PAL.NeonWarmWhite },
	} do
		local y, color = stripe[1], stripe[2]
		box(f, "Cove_South", -376, y, 99.75, 376, y + 0.18, 100, color, NEON, false)
		box(f, "Cove_East", 375.75, y, -20, 376, y + 0.18, 100, color, NEON, false)
		box(f, "Cove_Core", -324.25, y, 0, -324, y + 0.18, 98, color, NEON, false)
		box(f, "Cove_WestMouth", -376, y, -20, -375.75, y + 0.18, 0, color, NEON, false)
	end
	for k = 0, 7 do
		for _, z in { 15, 65 } do
			light(disc(f, "Downlight", -280 + 80 * k, z, 5, 35.7, 36, PAL.NeonWarmWhite, NEON, false), "PointLight", PAL.Warm, 0.7, 45)
		end
	end

	-- Terracotta theater blocks and portrait posters face the public concourse.
	for i, hall in HALLS do
		local xc = hall.X
		box(f, hall.Id .. "_RearWainscot", xc - 90, 0, -20, xc + 90, 4, -19.85, PAL.Charcoal, SP, false)
		finish(box(f, hall.Id .. "_RearPlaster", xc - 90, 4, -20, xc + 90, 35.5, -19.85,
			PAL.CorridorWall, SP, false), Enum.NormalId.Back, "rbxassetid://93137661811831", 28, 28)
		for _, u in { -88, -38, 38, 88 } do
			box(f, hall.Id .. "_PilasterBase", xc + u - 2, 0, -20, xc + u + 2, 4, -17.7,
				PAL.Charcoal, SP, false)
			finish(box(f, hall.Id .. "_Pilaster", xc + u - 2, 4, -20, xc + u + 2, 32, -17.9,
				PAL.CorridorWall, SP, false), Enum.NormalId.Back, "rbxassetid://93137661811831", 28, 28)
		end
		finish(box(f, hall.Id .. "_ProjectingCornice", xc - 90, 32, -20, xc + 90, 36, -18.1,
			PAL.CorridorWall, SP, false), Enum.NormalId.Back, "rbxassetid://93137661811831", 28, 28)
		for _, stripe in {
			{ 33.8, PAL.NeonMagenta }, { 34.55, PAL.NeonBlue }, { 35.3, PAL.NeonWarmWhite },
		} do
			local y, color = stripe[1], stripe[2]
			box(f, hall.Id .. "_CorniceCove", xc - 90, y, -18.1, xc + 90, y + 0.18, -18,
				color, NEON, false)
			for _, edge in { xc - 90, xc + 90 } do
				box(f, hall.Id .. "_CorniceReturn", edge - 0.1, y, -20, edge + 0.1, y + 0.18, -18.1,
					color, NEON, false)
			end
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

	-- The long south facade needs the same textured plaster, base and relief as the theater blocks.
	for _, span in { { -376, -146 }, { -126, 55 }, { 95, 150 }, { 178, 280 }, { 296, 376 } } do
		local x0, x1 = span[1], span[2]
		local plaster = box(f, "SouthFacadePlaster", x0, 4, 99.72, x1, 31.5, 99.94,
			PAL.CorridorWall, SP, false)
		finish(plaster, Enum.NormalId.Front, "rbxassetid://93137661811831", 28, 28)
		box(f, "SouthFacadeWainscot", x0, 0, 99.55, x1, 4, 99.94, PAL.Charcoal, SP, false)
		box(f, "SouthFacadeCornice", x0, 31.5, 99.5, x1, 33.15, 99.94,
			PAL.Charcoal, METAL, false)
		for x = x0 + 28, x1 - 28, 56 do
			box(f, "SouthPilasterBase", x - 1.6, 0, 98.95, x + 1.6, 4, 99.7,
				PAL.Charcoal, SP, false)
			finish(box(f, "SouthPilaster", x - 1.6, 4, 99.05, x + 1.6, 31.5, 99.7,
				PAL.CorridorWall, SP, false), Enum.NormalId.Front,
				"rbxassetid://93137661811831", 28, 28)
		end
	end
	for _, pair in {
			{ -310, -216, 3, 4 }, { -83, 29, 5, 1 }, { 215, 250, 2, 3 }, { 310, 350, 4, 5 },
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
			finish(p, Enum.NormalId.Left, "rbxassetid://93137661811831", 28, 28)
			finish(p, Enum.NormalId.Right, "rbxassetid://93137661811831", 28, 28)
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
			"rbxassetid://93137661811831", 28, 28)
	end
	for _, p in { f.TipPlaster, f.TipFascia } do
		finish(p, Enum.NormalId.Back, "rbxassetid://93137661811831", 28, 28)
	end
	local points = {
		Vector2.new(-90.06, -19.92), Vector2.new(-10.06, 40.08),
		Vector2.new(10.06, 40.08), Vector2.new(90.06, -19.92),
	}
	for _, stripe in {
		{ "Magenta", 33.8, PAL.NeonMagenta },
		{ "Blue", 34.55, PAL.NeonBlue },
		{ "Warm", 35.3, PAL.NeonWarmWhite },
	} do
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
	carpet(overlay(f, "Restroom_VestibuleCarpet", -148, 102, -122, 238), "Red")
	-- Solid tile plates keep the room finish above the slab at any viewing distance.
	floor(box(f, "Men_Tile", -376, 0, 102, -150, 0.2, 169, PAL.TileWhite, TILE))
	floor(box(f, "Women_Tile", -376, 0, 171, -150, 0.2, 238, PAL.TileWhite, TILE))
	-- Shared carpeted vestibule x[-148,-122] opens into two screened rooms.
	wall(f, "Restroom_VestibuleWall", "Z", 102, 238, -150, -148, 0, 28, PAL.Teal, SP, { { 126, 138, 0, 12 }, { 196, 208, 0, 12 } })
	box(f, "Restroom_DividingWall", -376, 0, 169, -148, 28, 171, PAL.Teal)
	glow(f, "Vestibule_Light", -139, 27.6, 166, -131, 28, 174, PAL.Warm, 0.8, 40)
	-- A free-swinging native hinge makes each light entry leaf easy to push through.
	local function pushDoor(name, z)
		local hingePos = Vector3.new(-149, 6, z + 0.7)
		local post = box(f, name .. "_HingePost", -149.5, 0, z + 0.2,
			-148.5, 12, z + 1.2, PAL.Chrome, METAL)
		local leaf = part(f, name .. "_PushDoor", Vector3.new(0.5, 10, 9.5),
			CFrame.new(hingePos) * CFrame.Angles(0, math.rad(-50), 0) * CFrame.new(0, 0, 4.75),
			PAL.Stall, WOOD)
		leaf.Anchored = false
		leaf.Massless = true
		leaf.CustomPhysicalProperties = PhysicalProperties.new(0.05, 0.25, 0, 1, 1)
		leaf.CanTouch = true
		leaf.CanCollide = false -- the swing responds to walking through, without blocking navigation
		leaf.CanQuery = false
		local a0 = Instance.new("Attachment")
		a0.Axis = Vector3.yAxis
		a0.Parent = post
		local a1 = Instance.new("Attachment")
		a1.Position = Vector3.new(0, 0, -4.75)
		a1.Axis = Vector3.yAxis
		a1.Parent = leaf
		local hinge = Instance.new("HingeConstraint")
		hinge.Attachment0 = a0
		hinge.Attachment1 = a1
		hinge.LimitsEnabled = true
		hinge.LowerAngle = -110
		hinge.UpperAngle = -50
		hinge.ActuatorType = Enum.ActuatorType.Servo
		hinge.AngularSpeed = 3
		hinge.ServoMaxTorque = 100
		hinge.TargetAngle = -50
		hinge.Parent = post
		local trigger = box(f, name .. "_DoorTrigger", -154, 0, z + 1,
			-147, 10, z + 11, PAL.Black, SP, false)
		trigger.Transparency = 1
		trigger.CanTouch = true
	end
	-- name, door z0, first stall z, dividing-wall face z, counter direction from that face
	for _, r in { { "Men", 126, 106, 169, -1 }, { "Women", 196, 175, 171, 1 } } do
		local name, door, stall0, wz, dir = r[1], r[2], r[3], r[4], r[5]
		doorway(f, name .. "Doorway", -150, 0, door, -148, 12, door + 12)
		label(box(f, name .. "_Sign", -148, 13, door + 1, -147.7, 15, door + 11, PAL.Black, SP, false), Enum.NormalId.Right, string.upper(name), PAL.NeonAmber)
		pushDoor(name, door)
		-- A privacy baffle hides the west-wall stall bank from the shared entrance.
		box(f, name .. "_PrivacyScreen", -164, 0, door - 10, -162, 14, door + 20, PAL.Teal)
		box(f, name .. "_PrivacyCap", -164.2, 14, door - 10.2, -161.8, 14.3, door + 20.2,
			PAL.Chrome, METAL, false)
		-- The sink gallery turns into a lower, screened stall room through one side opening.
		local roomZ0 = if dir < 0 then 102 else 171
		local roomZ1 = if dir < 0 then 169 else 238
		local partitionZ0 = if dir < 0 then 102 else 195
		local partitionZ1 = if dir < 0 then 145 else 238
		local openingZ0 = if dir < 0 then 145 else 171
		local openingZ1 = if dir < 0 then 169 else 195
		box(f, name .. "_StallLobbyWall", -302, 0.2, partitionZ0,
			-300, 28, partitionZ1, PAL.Teal, SP)
		box(f, name .. "_StallLobbyHeader", -302, 14, openingZ0,
			-300, 28, openingZ1, PAL.Stall, WOOD)
		box(f, name .. "_StallCeiling", -376, 17, roomZ0,
			-302, 17.5, roomZ1, PAL.LightCeiling, SP, false)
		for _, edgeZ in { roomZ0 + 0.1, roomZ1 - 0.4 } do
			box(f, name .. "_TileDado", -374, 0.2, edgeZ,
				-302, 7, edgeZ + 0.3, PAL.TileWhite, TILE, false)
		end
		glow(f, name .. "_StallLight", -342, 16.5, stall0 + 24,
			-334, 17, stall0 + 30, PAL.Warm, 0.55, 30)
		box(f, name .. "_StallBack", -376, 0, stall0, -374, 12, stall0 + 54, PAL.Stall)
		box(f, name .. "_StallHeader", -348.5, 10, stall0, -348, 12, stall0 + 54,
			PAL.Charcoal, METAL)
		for k = 0, 6 do
			box(f, name .. "_StallDivider", -374, 0.2, stall0 + 9 * k,
				-348, 12, stall0 + 9 * k + 0.5, PAL.Stall)
		end
		for k = 0, 5 do
			local z = stall0 + 9 * k
			local doorCF = CFrame.new(-347.5, 5.7, z + 0.8)
				* CFrame.Angles(0, math.rad(-28), 0) * CFrame.new(0, 0, 3.5)
			part(f, name .. "_StallDoor", Vector3.new(0.5, 8.5, 7),
				doorCF, PAL.Stall, WOOD, false)
			part(f, name .. "_StallLatch", Vector3.new(0.9, 0.5, 0.7),
				doorCF * CFrame.new(0.6, 0, 2.4), PAL.Chrome, METAL, false)
			box(f, name .. "_ToiletTank", -374, 2.1, z + 3.1, -370, 4.2, z + 6.3,
				PAL.TileWhite, TILE)
			box(f, name .. "_ToiletBowl", -370, 0.2, z + 2.7, -365, 2.3, z + 6.7,
				PAL.TileWhite, TILE)
		end
		-- sink counter, basins and mirror on the dividing wall
		box(f, name .. "_SinkCounter", -240, 0, wz, -190, 3.4, wz + dir * 6, PAL.Charcoal)
		for k = 0, 3 do
			local x = -234 + 12 * k
			box(f, name .. "_Basin", x - 2, 3.4, wz + dir * 1.5, x + 2, 3.7, wz + dir * 4.5, PAL.TileWhite, SP, false)
		end
		box(f, name .. "_Mirror", -238, 5, wz, -192, 11, wz + dir * 0.2, PAL.Glass, GLASS, false).Reflectance = 0.35
		local zc = if dir < 0 then 135 else 205
		for _, x in { -290, -200 } do
			glow(f, name .. "_Light", x - 4, 27.6, zc - 3, x + 4, 28, zc + 3, PAL.Warm, 0.8, 50)
		end
	end
end

local function buildConcession(model)
	local f = folder(model, "Concession")
	carpet(overlay(f, "Concession_RedCarpet", -120, 102, 120, 238), "Red")
	-- Closed, collidable double-glass main entry in the south wall aperture x[-24,24] y[0,14].
	box(f, "MainEntry_GlassWest", -24, 0, 238.6, -0.2, 14, 239.4, PAL.TintGlass, GLASS).Reflectance = 0.2
	box(f, "MainEntry_GlassEast", 0.2, 0, 238.6, 24, 14, 239.4, PAL.TintGlass, GLASS).Reflectance = 0.2
	box(f, "MainEntry_Mullion", -0.2, 0, 238.4, 0.2, 14, 239.6, PAL.Chrome, METAL)
	for _, s in { -1, 1 } do
		box(f, "MainEntry_Handle", s * 1.2, 5, 238.2, s * 1.6, 8, 238.6, PAL.Chrome, METAL, false)
	end
	frame(f, "MainEntry_Frame", "X", 238, -1, -24, 24, 0, 14, PAL.NeonRed)
	label(box(f, "MainEntry_Sign", -10, 16, 237.6, 10, 19, 238, PAL.Exit, NEON, false), Enum.NormalId.Front, "EXIT", PAL.White)

	-- Preview arrival/exit anchor just inside the doors, centred at (0,3,226), facing north.
	local anchor = box(model, "Level4V4Exit", -2, 2.5, 224, 2, 3.5, 228, PAL.Black, SP, false)
	anchor.Transparency = 1
	anchor:SetAttribute("Zone", "Concessions")
	tag(anchor, V5.TAGS.Exit)

	-- Red/white counter x[-110,35] z[108,125], top y4.5. Staff stand on its concourse-wall side;
	-- the passage x>35 to the concourse opening x[55,95] stays clear.
	box(f, "Counter", -110, 0, 108, 35, 4.1, 125, PAL.Counter)
	box(f, "CounterTop", -110.3, 4.1, 107.7, 35.3, 4.5, 125.3, PAL.CounterWhite)
	box(f, "CounterTrim", -110, 3.3, 125, 35, 3.6, 125.2, PAL.NeonAmber, NEON, false)
	box(f, "CounterPlinth", -110, 0, 125, 35, 0.7, 125.3, PAL.Black, SP, false)
	for x = -90, 30, 20 do
		box(f, "CounterPanelSeam", x, 0.8, 125.05, x + 0.3, 3.2, 125.25, PAL.Black, SP, false)
	end
	for _, x in { -28, 2 } do
		box(f, "Register", x - 2, 4.5, 117, x + 2, 5.9, 121, PAL.Metal, METAL, false)
	end
	box(f, "SodaFountain", 15, 4.5, 110, 27, 10, 116, PAL.Metal, METAL)
	box(f, "SodaFountainPanel", 15.5, 7.5, 116, 26.5, 9.5, 116.2, PAL.NeonCyan, NEON, false)
	box(f, "SodaDripTray", 15.5, 4.5, 116, 26.5, 4.9, 117, PAL.Chrome, METAL, false)
	for k, text in { "POPCORN", "DRINKS", "CANDY" } do
		local a = -100 + 34 * (k - 1)
		label(box(f, "MenuBoard", a, 14, 102, a + 26, 22, 102.4, PAL.Board, SP, false), Enum.NormalId.Back, text, PAL.NeonAmber)
		box(f, "MenuBoardEdge", a, 22, 102, a + 26, 22.3, 102.5, PAL.NeonRed, NEON, false)
	end
	-- Small black-and-cream checker backsplash on the wall behind the counter.
	for ix = 0, 28 do
		for iy = 0, 2 do
			local color = if ix % 9 == 0 and iy == 1 then PAL.Counter
				else if (ix + iy) % 2 == 0 then PAL.TileWhite else PAL.Black
			box(f, "CheckerBacksplash", -110 + 5 * ix, 5 + 3 * iy, 102.02,
				-105 + 5 * ix, 8 + 3 * iy, 102.08, color, TILE, false)
		end
	end
	for _, x in { -75, 5 } do
		glow(f, "CounterWarmLight", x - 2, 27.6, 119, x + 2, 28, 123, PAL.NeonAmber, 0.55, 22)
	end
	-- black/white/red checker along the counter queue edge
	overlay(f, "Checker_White", -106, 125, 32, 131, PAL.CounterWhite, TILE)
	for k = 0, 22, 2 do
		overlay(f, "Checker_Black", -106 + 6 * k, 125, -100 + 6 * k, 131, PAL.Black, TILE, 2)
	end
	overlay(f, "Checker_Red", -106, 131, 32, 131.6, PAL.Counter, TILE)

	-- Empty framed glass popcorn case on the counter at x[-70,-50] z[112,120]: bare deck,
	-- hanging kettle and warm lamp, no popcorn fill.
	local popper = Instance.new("Model")
	popper.Name = "PopcornCase"
	popper:SetAttribute("Empty", true)
	popper.Parent = f
	local x0, x1, z0, z1, y0, y1 = -70, -50, 112, 120, 5.5, 12
	box(popper, "CaseBase", x0, 4.5, z0, x1, y0, z1, PAL.Counter)
	box(popper, "CaseDeck", x0 + 0.4, y0, z0 + 0.4, x1 - 0.4, y0 + 0.1, z1 - 0.4, PAL.Chrome, METAL)
	box(popper, "CaseRoof", x0 - 0.2, y1, z0 - 0.2, x1 + 0.2, y1 + 1, z1 + 0.2, PAL.Counter)
	for _, c in { { x0, z0 }, { x1 - 0.4, z0 }, { x0, z1 - 0.4 }, { x1 - 0.4, z1 - 0.4 } } do
		box(popper, "CasePost", c[1], y0, c[2], c[1] + 0.4, y1, c[2] + 0.4, PAL.Chrome, METAL)
	end
	for _, g in { { x0 + 0.4, z0, x1 - 0.4, z0 + 0.1 }, { x0 + 0.4, z1 - 0.1, x1 - 0.4, z1 }, { x0, z0 + 0.4, x0 + 0.1, z1 - 0.4 }, { x1 - 0.1, z0 + 0.4, x1, z1 - 0.4 } } do
		box(popper, "CaseGlass", g[1], y0, g[2], g[3], y1, g[4], PAL.Glass, GLASS).Transparency = 0.75
	end
	box(popper, "KettleRod", -60.15, 10.5, 115.85, -59.85, y1, 116.15, PAL.Chrome, METAL, false)
	disc(popper, "Kettle", -60, 116, 3, 9.3, 10.5, PAL.Chrome, METAL, false)
	glow(popper, "CaseLamp", x0 + 1, y1 - 0.3, z0 + 0.6, x1 - 1, y1 - 0.1, z0 + 0.9, PAL.NeonAmber, 0.7, 12)
	label(box(popper, "CaseSign", x0, y1 + 1, z1, x1, y1 + 2.6, z1 + 0.2, PAL.Counter, SP, false), Enum.NormalId.Back, "POPCORN", PAL.NeonAmber)

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
		for _, stripe in { { 0, PAL.NeonAmber }, { 2.5, PAL.NeonWarmWhite }, { 5, PAL.NeonBlue } } do
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
end

local function buildArcade(model)
	local f = folder(model, "Arcade")
	carpet(overlay(f, "Arcade_Carpet", 122, 100, 259, 238), "Ring")
	overlay(f, "Service_Floor", 261, 100, 376, 238, PAL.Service, CONCRETE)
	-- Arcade | service divider with the interior service opening z[174,186].
	wall(f, "ArcadeServiceDivider", "Z", 102, 238, 259, 261, 0, 28, PAL.Service, SP, { { 174, 186, 0, 12 } })
	doorway(f, "ServiceInnerDoorway", 259, 0, 174, 261, 12, 186)
	label(box(f, "ServiceInnerSign", 258.7, 13, 176, 259, 15, 184, PAL.Black, SP, false), Enum.NormalId.Left, "STAFF ONLY", PAL.NeonAmber)

	-- Quiet cabinet banks along both sides and two inner rows; clear routes remain between them.
	for _, z in { 112, 128, 144, 160, 176, 192, 208, 224 } do
		box(f, "Cabinet", 122, 0, z - 2.5, 136, 8, z + 2.5, PAL.Cabinet)
		box(f, "CabinetScreen", 136, 4, z - 2, 136.1, 7, z + 2, PAL.DarkScreen, GLASS, false)
		box(f, "CabinetMarquee", 136, 7.2, z - 2, 136.15, 8, z + 2, PAL.NeonMagenta, NEON, false)
	end
	for _, z in { 112, 128, 144, 160, 200, 216, 232 } do
		box(f, "Cabinet", 245, 0, z - 2.5, 259, 8, z + 2.5, PAL.Cabinet)
		box(f, "CabinetScreen", 244.9, 4, z - 2, 245, 7, z + 2, PAL.DarkScreen, GLASS, false)
		box(f, "CabinetMarquee", 244.85, 7.2, z - 2, 245, 8, z + 2, PAL.NeonCyan, NEON, false)
	end
	for _, x in { 180, 211 } do
		for _, z in { 140, 164, 196, 220 } do
			box(f, "IslandCabinet", x, 0, z - 3, x + 7, 8, z + 3, PAL.Cabinet)
			box(f, "IslandScreen", x - 0.1, 4, z - 2, x, 7, z + 2, PAL.DarkScreen, GLASS, false)
			box(f, "IslandScreen", x + 7, 4, z - 2, x + 7.1, 7, z + 2, PAL.DarkScreen, GLASS, false)
			box(f, "IslandMarquee", x - 0.15, 7.2, z - 2, x, 8, z + 2, PAL.NeonViolet, NEON, false)
			box(f, "IslandMarquee", x + 7, 7.2, z - 2, x + 7.15, 8, z + 2, PAL.NeonViolet, NEON, false)
		end
	end
	for i, z in { 150, 210 } do
		glow(f, "Arcade_Tube", 122, 27.7, z - 0.2, 259, 28, z + 0.2, if i == 1 then PAL.NeonViolet else PAL.NeonCyan, 1, 60)
	end

	-- Service store for utility and booth supplies, kept clear of both entrances.
	box(f, "Service_Shelf", 370, 0, 120, 376, 10, 230, PAL.Metal, METAL)
	box(f, "Service_Shelf", 270, 0, 232, 310, 8, 238, PAL.Metal, METAL)
	box(f, "Service_BoothLampCrate", 300, 0, 200, 306, 4, 206, PAL.Crate, WOOD)
	box(f, "Service_BoothLampCrate", 310, 0, 150, 316, 5, 156, PAL.Crate, WOOD)
	glow(f, "Service_Light", 290, 27.6, 166, 298, 28, 174, PAL.Warm, 0.6, 45)
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

function V5.Build(originCFrame)
	origin = originCFrame or CFrame.identity
	local model = Instance.new("Model")
	model.Name = V5.MODEL_NAME
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
	buildConcession(model)
	buildArcade(model)
	local doorMotion = Instance.new("Script")
	doorMotion.Name = "RestroomDoorMotion"
	doorMotion.Source = [[
local rest = script.Parent:WaitForChild("Restrooms")
for _, name in { "Men", "Women" } do
	local trigger = rest:WaitForChild(name .. "_DoorTrigger")
	local hinge = rest:WaitForChild(name .. "_HingePost"):FindFirstChildOfClass("HingeConstraint")
	local lastTouch = 0
	trigger.Touched:Connect(function(hit)
		local character = hit:FindFirstAncestorOfClass("Model")
		if not character or not character:FindFirstChildOfClass("Humanoid") then return end
		if os.clock() - lastTouch < 1.5 then return end
		lastTouch = os.clock()
		hinge.TargetAngle = -105
		task.delay(1.2, function()
			if hinge.Parent then hinge.TargetAngle = -50 end
		end)
	end)
end
]]
	doorMotion.Parent = model
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
	local part = fixtures[math.random(1, #fixtures)]
	local point = part:FindFirstChildOfClass("PointLight")
	if point and part:IsDescendantOf(workspace) then
		point.Enabled = false
		part.Material = Enum.Material.SmoothPlastic
		task.wait(0.08)
		point.Enabled = true
		part.Material = Enum.Material.Neon
	end
end
]]
	flicker.Parent = model
	model.WorldPivot = origin
	local parts, lights = census(model)
	model:SetAttribute("Level4LayoutVersion", V5.LAYOUT_VERSION)
	model:SetAttribute("Level4PreviewReady", true)
	model:SetAttribute("Level4Preview", true)
	model:SetAttribute("PreviewOnly", true)
	model:SetAttribute("PartCount", parts)
	model:SetAttribute("LightCount", lights)
	return model
end

-- Floor probes, doorway clearance rays, chair/doorway counts and the part/light budget.
-- The model must be in Workspace.
function V5.SelfCheck(model)
	local issues = {}
	local pivot = model.WorldPivot
	local params = RaycastParams.new()
	params.FilterType = Enum.RaycastFilterType.Include
	params.FilterDescendantsInstances = { model }
	local down = pivot:VectorToWorldSpace(Vector3.new(0, -8, 0))
	for _, p in PROBES do
		local hit = workspace:Raycast(pivot * Vector3.new(p[2], p[4] + 4, p[3]), down, params)
		local y = if hit then pivot:PointToObjectSpace(hit.Position).Y else nil
		if not y or math.abs(y - p[4]) > 0.1 then
			table.insert(issues, string.format("floor %s: expected y%d, got %s", p[1], p[4], tostring(y)))
		end
	end
	local chairs, doors = 0, 0
	for _, d in model:GetDescendants() do
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
	if chairs ~= #HALLS * V5.CHAIRS_PER_HALL then
		table.insert(issues, string.format("chairs: expected %d, got %d", #HALLS * V5.CHAIRS_PER_HALL, chairs))
	end
	if doors ~= V5.DOORWAYS then
		table.insert(issues, string.format("doorways: expected %d, got %d", V5.DOORWAYS, doors))
	end
	local parts, lights = census(model)
	if parts >= V5.MAX_PARTS or lights >= V5.MAX_LIGHTS then
		table.insert(issues, string.format("over budget: %d parts, %d lights", parts, lights))
	end
	return #issues == 0, { Issues = issues, PartCount = parts, LightCount = lights }
end

return V5
