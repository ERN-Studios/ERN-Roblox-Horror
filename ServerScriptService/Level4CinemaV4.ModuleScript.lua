-- Level 4 cinema, layout V4, built 1:1 from assets/level4/v4/METRIC_BLUEPRINT.md and
-- metric-blueprint.svg. Static groundwork only: no entities, objectives, routing or
-- Lighting edits, and no dependency on the older Level 4 modules.
--
--   local V4 = require(path.to.Level4CinemaV4)
--   local model = V4.Build(CFrame.new(23000, 24, 0)) -- returned unparented
--   model.Parent = workspace
--   print(V4.SelfCheck(model))                       -- needs the model in Workspace
--
-- Local frame in studs: one collidable base slab y[-1,0] under x[-330,330] z[-240,240];
-- north (screens) = -Z; closed glass main entry x[-24,24] y[0,14]; arrival (0,0,226).
--   Halls A1 x[-300,-120], A2 x[-90,90], A3 x[120,300]; z[-240,-20]; roof y[80,81].
--     u = x - hall centre. Deck u[-78,78]: front tiers y2..16, cross aisle z[-140,-120]
--     at y18, rear tiers y21..48, top walk z[-30,-22] at y48. Side aisles u+-[78,88]
--     climb in 1-stud treads. Doors z[-136,-124] y[18,28] in both side walls; front-right
--     exit z[-230,-218] y[0,10]. 18 rows x 22 chairs (banks u=-68+6j, 8+6j). Booth
--     u[-16,16] z[-34,-22], floor y62, roof y75, 14 one-stud treads along u[-30,-16].
--   Corridors C1..C4 z[-240,-20], roof y[32,33]: stair lanes rise y0 -> y18 over
--     z[-115,-30] to landings z[-145,-115]; separators z[-145,-20]; return lanes stay y0.
--   Concourse x[-330,330] z[-20,100], roof y[36,37]; wall z[100,102] with four openings to y12.
--   South z[102,238], roofs y[28,29]: restrooms + vestibule x[-328,-122], concessions
--     x[-120,120], arcade x[122,259], service x[261,328].

local CollectionService = game:GetService("CollectionService")

local V4 = {}

V4.MODEL_NAME = "Level 4 Cinema Preview"
V4.LAYOUT_VERSION = 4
V4.MAX_PARTS = 5000
V4.MAX_LIGHTS = 140
V4.CHAIRS_PER_HALL = 396
V4.DOORWAYS = 19 -- 3 halls x (2 side doors, front exit, booth door) + 4 concourse + 2 restroom + 1 service

local FLOOR_TAG = "Level4V4Floor"
local DOOR_TAG = "Level4V4Doorway"
local SEAT_TAG = "Level4V4Seat"
V4.TAGS = { Floor = FLOOR_TAG, Doorway = DOOR_TAG, Seat = SEAT_TAG, Exit = "Level4V4Exit" }

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

-- Verified Level 4 carpet uploads (assets/level4/ASSETS.md): id, studs per tile, fallback colour.
local CARPET = {
	Red = { "rbxassetid://92732673815453", 12, Color3.fromRGB(128, 20, 16) },
	Swirl = { "rbxassetid://80407060064074", 18, Color3.fromRGB(104, 38, 40) },
	Ring = { "rbxassetid://85044000846144", 12, Color3.fromRGB(62, 26, 84) },
}

local PAL = {
	Shell = Color3.fromRGB(24, 18, 20),
	HallWall = Color3.fromRGB(18, 44, 48), -- dark teal acoustic finish
	CorridorWall = Color3.fromRGB(62, 14, 22),
	Partition = Color3.fromRGB(150, 26, 18),
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

local POSTERS = {
	Color3.fromRGB(150, 40, 28),
	Color3.fromRGB(40, 96, 150),
	Color3.fromRGB(160, 124, 40),
	Color3.fromRGB(100, 40, 140),
	Color3.fromRGB(28, 124, 84),
	Color3.fromRGB(160, 60, 104),
}

local HALLS = { { Id = "A1", X = -210 }, { Id = "A2", X = 0 }, { Id = "A3", X = 210 } }
local AISLES = { { -88, -78 }, { 78, 88 } } -- side aisles in hall-local u = x - hall X

-- Span is the corridor's full strip (roof extent); X0..X1 is the clear width between walls.
local CORRIDORS = {
	{ Id = "C1", Span = { -330, -300 }, X0 = -328, X1 = -300, Return = { -328, -310 },
		Separators = { { -310, -309 } }, Stairs = { { "A1West", -309, -300 } } },
	{ Id = "C2", Span = { -120, -90 }, X0 = -120, X1 = -90, Return = { -110, -100 },
		Separators = { { -111, -110 }, { -100, -99 } }, Stairs = { { "A1East", -120, -111 }, { "A2West", -99, -90 } } },
	{ Id = "C3", Span = { 90, 120 }, X0 = 90, X1 = 120, Return = { 100, 110 },
		Separators = { { 99, 100 }, { 110, 111 } }, Stairs = { { "A2East", 90, 99 }, { "A3West", 111, 120 } } },
	{ Id = "C4", Span = { 300, 330 }, X0 = 300, X1 = 328, Return = { 310, 328 },
		Separators = { { 309, 310 } }, Stairs = { { "A3East", 300, 309 } } },
}

-- Concourse wall z[100,102] openings: x0, x1, bottom, top, name, sign.
local SOUTH_OPENINGS = {
	{ -146, -126, 0, 12, "RestroomsDoorway", "RESTROOMS" },
	{ 55, 95, 0, 12, "ConcessionsDoorway", "CONCESSIONS" },
	{ 150, 178, 0, 12, "ArcadeDoorway", "ARCADE" },
	{ 280, 296, 0, 12, "ServiceDoorway", "SERVICE" },
}

-- Tan 6-stud border of the concourse east-wing tile; turquoise tile lies east of it.
local TILE_EDGE = { { 155, -20 }, { 135, 0 }, { 120, 20 }, { 110, 40 }, { 115, 60 }, { 130, 80 }, { 155, 100 } }

V4.HALLS = HALLS
V4.CORRIDORS = CORRIDORS
V4.SOUTH_OPENINGS = SOUTH_OPENINGS

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
V4.AisleHeight = aisleY

local function tileEdgeX(z)
	for i = 1, #TILE_EDGE - 1 do
		local a, b = TILE_EDGE[i], TILE_EDGE[i + 1]
		if z <= b[2] then
			return a[1] + (b[1] - a[1]) * (z - a[2]) / (b[2] - a[2])
		end
	end
	return TILE_EDGE[#TILE_EDGE][1]
end

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
	probe(h.Id .. " booth stair tread 7", h.X - 23.5, -27, 55)
	probe(h.Id .. " booth floor", h.X + 8, -28, 62)
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
	{ "Concourse centre", 0, 40 }, { "Concourse east tile", 250, 40 }, { "Arrival", 0, 226 },
	{ "Concessions passage", 75, 160 }, { "Restroom vestibule", -135, 170 }, { "Men's room", -240, 140 },
	{ "Women's room", -240, 200 }, { "Arcade", 190, 170 }, { "Service", 300, 150 },
} do
	probe(p[1], p[2], p[3], 0)
end
V4.PROBES = PROBES

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
	-- One collidable base slab under the whole footprint, never perforated.
	floor(box(f, "BaseSlab", -330, -1, -240, 330, 0, 240), "Red")
	-- Exterior walls rise from y0 to the underside of the roof they meet.
	for _, h in HALLS do
		box(f, "ShellNorth", h.X - 90, 0, -240, h.X + 90, 80, -238, PAL.Shell)
	end
	for _, c in CORRIDORS do
		box(f, "ShellNorth", c.Span[1], 0, -240, c.Span[2], 32, -238, PAL.Shell)
	end
	for _, s in { -1, 1 } do
		box(f, "ShellSide", s * 330, 0, -238, s * 328, 32, -20, PAL.Shell)
		box(f, "ShellSide", s * 330, 0, -20, s * 328, 36, 102, PAL.Shell)
		box(f, "ShellSide", s * 330, 0, 102, s * 328, 28, 238, PAL.Partition)
	end
	-- the x[-24,24] y[0,14] aperture holds the closed glass entry (Concession)
	wall(f, "ShellSouth", "X", -330, 330, 238, 240, 0, 28, PAL.Partition, SP, { { -24, 24, 0, 14 } })
	-- concourse | south rooms wall: solid above y12 up to the y36 concourse roof
	wall(f, "ConcourseSouthWall", "X", -328, 328, 100, 102, 0, 36, PAL.Partition, SP, SOUTH_OPENINGS)
	for _, o in SOUTH_OPENINGS do
		doorway(f, o[5], o[1], o[3], 100, o[2], o[4], 102)
	end
	box(f, "Divider_RestroomsConcessions", -122, 0, 102, -120, 28, 238, PAL.Partition)
	box(f, "Divider_ConcessionsArcade", 120, 0, 102, 122, 28, 238, PAL.Partition)
	box(f, "ConcourseRoof", -330, 36, -20, 330, 37, 102, PAL.Ceiling)
	box(f, "RestroomRoof", -330, 28, 102, -121, 29, 240, PAL.LightCeiling)
	box(f, "ConcessionRoof", -121, 28, 102, 121, 29, 240, PAL.FoyerCeiling)
	box(f, "ArcadeServiceRoof", 121, 28, 102, 330, 29, 240, PAL.Ceiling)
end

local function buildHall(model, hall, index)
	local id, xc = hall.Id, hall.X
	local f = folder(model, id)
	f:SetAttribute("CenterX", xc)
	local function b(name, u0, y0, z0, u1, y1, z1, color, mat, collide)
		return box(f, id .. "_" .. name, xc + u0, y0, z0, xc + u1, y1, z1, color, mat, collide)
	end

	-- Deck. The y0 screen apron z[-238,-204] is the base slab itself.
	for i = 1, 8 do
		floor(b("FrontTier" .. i, -88, 0, -212 + 8 * i, 88, 2 * i, -204 + 8 * i), "Red")
	end
	floor(b("CrossAisle", -88, 0, -140, 88, 18, -120), "Swirl")
	b("CrossAisleEdge", -78, 18, -120.2, 78, 18.3, -120, PAL.NeonCyan, NEON, false)
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
			b("StepDot", uc - 0.4, 2 * i - 0.35, -212.1 + 8 * i, uc + 0.4, 2 * i - 0.1, -212 + 8 * i, PAL.NeonCyan, NEON, false)
		end
		for r = 1, 10 do
			b("StepDot", uc - 0.4, 17.65 + 3 * r, -123.1 + 9 * r, uc + 0.4, 17.9 + 3 * r, -123 + 9 * r, PAL.NeonCyan, NEON, false)
		end
	end

	-- 18 rows x 22 chairs in two 11-chair banks, each chair (base, back) 4.4 wide and
	-- centred in its tier. The gap between banks is spacing only; the side aisles are the route.
	local function row(t, zm)
		for j = 0, 10 do
			for _, u in { -68 + 6 * j, 8 + 6 * j } do
				local x = xc + u
				tag(box(f, id .. "_ChairSeat", x - 2.2, t, zm - 1.6, x + 2.2, t + 2, zm + 1.6, PAL.Seat, FABRIC), SEAT_TAG)
				box(f, id .. "_ChairBack", x - 2.2, t + 1.2, zm + 1.6, x + 2.2, t + 5, zm + 2.2, PAL.SeatBack, FABRIC)
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
	wall(f, id .. "_WallWest", "Z", -238, -22, xc - 90, xc - 88, 0, 80, PAL.HallWall, SP, { { -136, -124, 18, 28 } })
	wall(f, id .. "_WallEast", "Z", -238, -22, xc + 88, xc + 90, 0, 80, PAL.HallWall, SP,
		{ { -230, -218, 0, 10 }, { -136, -124, 18, 28 } })
	b("WallRear", -90, 0, -22, 90, 80, -20, PAL.HallWall)
	b("Roof", -90, 80, -240, 90, 81, -20, PAL.Ceiling)

	for side = -1, 1, 2 do
		local inner, outer = xc + side * 88, xc + side * 90
		doorway(f, id .. (if side < 0 then "_EntryWest" else "_EntryEast"), inner, 18, -136, outer, 28, -124)
		frame(f, id .. "_EntryFrame", "Z", inner, -side, -136, -124, 18, 28, PAL.NeonRed)
		frame(f, id .. "_EntryFrame", "Z", outer, side, -136, -124, 18, 28, PAL.NeonRed)
		local sign = box(f, id .. "_EntrySign", outer, 29, -134, outer + side * 0.3, 31, -126, PAL.Black, SP, false)
		label(sign, if side < 0 then Enum.NormalId.Left else Enum.NormalId.Right, "CINEMA " .. index, PAL.NeonAmber)
	end
	doorway(f, id .. "_FrontRightExit", xc + 88, 0, -230, xc + 90, 10, -218)
	frame(f, id .. "_ExitFrame", "Z", xc + 88, -1, -230, -218, 0, 10, PAL.Exit)
	frame(f, id .. "_ExitFrame", "Z", xc + 90, 1, -230, -218, 0, 10, PAL.Exit)
	label(b("ExitSign", 87.6, 11.5, -227, 88, 13.5, -221, PAL.Exit, NEON, false), Enum.NormalId.Left, "EXIT", PAL.White)
	label(b("ExitSignCorridor", 90, 11.5, -227, 90.4, 13.5, -221, PAL.Exit, NEON, false), Enum.NormalId.Right, "EXIT", PAL.White)

	-- Blank cream screen on the north wall with black masking.
	light(b("Screen", -58, 14, -238, 58, 62, -237.8, PAL.Screen), "SurfaceLight", PAL.ScreenGlow, 0.6, 60, Enum.NormalId.Back, 80)
	for _, m in { { -61, 11, -58, 65 }, { 58, 11, 61, 65 }, { -58, 62, 58, 65 }, { -58, 11, 58, 14 } } do
		b("ScreenMask", m[1], m[2], -238, m[3], m[4], -237.6, PAL.Black, SP, false)
	end

	-- A few restrained sconces 9 above the aisle, flush ceiling lights, and a wall cove line
	-- running from the screen wall to the rear wall.
	for _, z in { -175, -80 } do
		local y = aisleY(z) + 9
		for side = -1, 1, 2 do
			glow(f, id .. "_Sconce", xc + side * 88, y, z - 1.5, xc + side * 87.6, y + 2, z + 1.5, PAL.NeonAmber, 0.5, 18)
		end
	end
	for _, u in { -50, 50 } do
		for _, z in { -190, -80 } do
			glow(f, id .. "_CeilingLight", xc + u - 3, 79.4, z - 3, xc + u + 3, 80, z + 3, PAL.Warm, 0.5, 60)
		end
	end
	for side = -1, 1, 2 do
		for _, z in { -202, -174, -146, -108, -80, -52 } do
			b("AcousticPanel", side * 87.7, 10, z - 9, side * 87.9, 62, z + 9, PAL.Teal, FABRIC, false)
		end
		b("WallCove", side * 87.7, 70, -238, side * 88, 70.4, -22, PAL.NeonCyan, NEON, false)
	end

	-- Projection booth u[-16,16] z[-34,-22]: floor y[61,62], roof y[74,75], walls y62..74,
	-- screen-facing window u[-10,10] y[65,70], west access door z[-30,-24] y[62,70].
	b("BoothFloor", -16, 61, -34, 16, 62, -22, PAL.Booth)
	b("BoothRoof", -16, 74, -34, 16, 75, -22, PAL.Booth)
	wall(f, id .. "_BoothNorth", "X", xc - 16, xc + 16, -34, -33, 62, 74, PAL.Booth, SP, { { xc - 10, xc + 10, 65, 70 } })
	b("BoothSouth", -16, 62, -23, 16, 74, -22, PAL.Booth)
	wall(f, id .. "_BoothWest", "Z", -33, -23, xc - 16, xc - 15, 62, 74, PAL.Booth, SP, { { -30, -24, 62, 70 } })
	b("BoothEast", 15, 62, -33, 16, 74, -23, PAL.Booth)
	doorway(f, id .. "_BoothDoor", xc - 16, 62, -30, xc - 15, 70, -24)
	b("BoothWindow", -10, 65, -33.7, 10, 70, -33.3, PAL.Glass, GLASS).Transparency = 0.5
	-- A full front support joins the booth to the top walk behind the last seats.
	b("BoothSupportWall", -16, 48, -23, 16, 61, -22, PAL.Booth)
	b("BoothFrontSupport", -16, 48, -34, 16, 61, -33.1, PAL.Booth)
	b("BoothFrontLintel", -16, 59, -34, 16, 61, -32, PAL.Metal, METAL)
	-- Service stair: fourteen 1-stud treads along u[-30,-16] at z[-30,-24], y48 walk -> y62 door,
	-- with glass guards on both sides.
	for n = 1, 14 do
		floor(b("BoothStairTread" .. n, -31 + n, 48, -30, -30 + n, 48 + n, -24, PAL.Aisle, FABRIC))
	end
	for _, z in { -30, -24.2 } do
		b("BoothStairGuard", -30, 48, z, -16, 66, z + 0.2, PAL.Glass, GLASS).Transparency = 0.6
	end
	b("ProjectorStand", -1, 62, -30, 1, 65, -27, PAL.Metal, METAL)
	light(b("Projector", -1.8, 65, -32, 1.8, 70, -26, PAL.Metal, METAL), "PointLight", PAL.NeonAmber, 0.6, 14)
	b("ProjectorLens", -0.7, 66.8, -32.4, 0.7, 68.2, -32, PAL.Warm, NEON, false)
end

local function buildCorridor(model, c)
	local id = c.Id
	local f = folder(model, id)
	carpet(overlay(f, id .. "_Carpet", c.X0, -238, c.X1, -20), "Swirl")
	box(f, id .. "_Roof", c.Span[1], 32, -240, c.Span[2], 33, -20, PAL.Ceiling)
	-- fascia closing the step from the y33 corridor roof to the y37 concourse roof
	box(f, id .. "_MouthFascia", c.Span[1], 33, -22, c.Span[2], 37, -20, PAL.Shell)
	-- wall-mounted coves flush under the roof, turning the north corners and ending at the mouth
	box(f, id .. "_CoveWest", c.X0, 31.6, -238, c.X0 + 0.3, 32, -20, PAL.NeonMagenta, NEON, false)
	box(f, id .. "_CoveNorth", c.X0, 31.6, -238, c.X1, 32, -237.7, PAL.NeonWarmWhite, NEON, false)
	box(f, id .. "_CoveEast", c.X1 - 0.3, 31.6, -238, c.X1, 32, -20, PAL.NeonCyan, NEON, false)
	-- full-height separators keep stair lanes and the return lane apart from z-145 to the concourse
	for _, s in c.Separators do
		box(f, id .. "_Separator", s[1], 0, -145, s[2], 32, -20, PAL.CorridorWall)
	end
	for _, st in c.Stairs do
		local name, a, b = id .. "_Stair" .. st[1], st[2], st[3]
		for k = 1, 17 do
			floor(box(f, name .. "_Tread" .. k, a, 0, -30 - 5 * k, b, k, -25 - 5 * k, PAL.Aisle, FABRIC))
		end
		floor(box(f, name .. "_Landing", a, 0, -145, b, 18, -115), "Swirl")
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

local function buildConcourse(model)
	local f = folder(model, "Concourse")
	-- Low green columns echo the larger real-cinema concourse without changing its room grid.
	for _, x in { -280, -110, 110, 280 } do
		for _, z in { 30, 70 } do
			box(f, "ConcourseColumn", x - 3, 0, z - 3, x + 3, 36, z + 3, PAL.Green)
			box(f, "ConcourseColumnBase", x - 3.3, 0, z - 3.3, x + 3.3, 3, z + 3.3, PAL.Charcoal)
		end
	end
	-- East wing: glossy turquoise tile east of the measured curve (4-stud slices, hidden under
	-- the 6-stud tan border), green lower-wall bands. The west part is the red base carpet.
	overlay(f, "EastTile", 155, -20, 328, 100, PAL.Turquoise, TILE).Reflectance = 0.15
	for s = 0, 29 do
		local z0 = -20 + 4 * s
		overlay(f, "EastTile", tileEdgeX(z0 + 2), z0, 155, z0 + 4, PAL.Turquoise, TILE).Reflectance = 0.15
	end
	local n = #TILE_EDGE - 1
	for i = 1, n do
		local a = Vector3.new(TILE_EDGE[i][1], 0.075, TILE_EDGE[i][2])
		local b = Vector3.new(TILE_EDGE[i + 1][1], 0.075, TILE_EDGE[i + 1][2])
		part(f, "EastTileBorder", Vector3.new(6, 0.05, (b - a).Magnitude), CFrame.lookAt((a + b) / 2, b), PAL.Tan, TILE, false)
		if i < n then
			-- Raised joint covers the miter gap without two border tops fighting at the same height.
			disc(f, "EastTileBorderJoint", TILE_EDGE[i + 1][1], TILE_EDGE[i + 1][2], 6, 0.10, 0.12, PAL.Tan, TILE, false)
		end
	end
	box(f, "EastWallGreenBand", 327.8, 0, -20, 328, 4, 100, PAL.Green, SP, false)
	box(f, "A3RearGreenBand", 155, 0, -20, 300, 4, -19.8, PAL.Green, SP, false)

	-- Red coves flush under the y36 roof on all four sides; recessed warm-white downlights.
	box(f, "Cove_North", -328, 35.6, -20, 328, 36, -19.7, PAL.NeonRed, NEON, false)
	box(f, "Cove_South", -328, 35.6, 99.7, 328, 36, 100, PAL.NeonRed, NEON, false)
	box(f, "Cove_West", -328, 35.6, -20, -327.7, 36, 100, PAL.NeonRed, NEON, false)
	box(f, "Cove_East", 327.7, 35.6, -20, 328, 36, 100, PAL.NeonRed, NEON, false)
	for k = 0, 7 do
		for _, z in { 15, 65 } do
			light(disc(f, "Downlight", -280 + 80 * k, z, 5, 35.7, 36, PAL.NeonWarmWhite, NEON, false), "PointLight", PAL.Warm, 0.7, 45)
		end
	end

	-- Marquee and two posters on each hall's rear wall.
	for i, hall in HALLS do
		local xc = hall.X
		label(box(f, hall.Id .. "_Marquee", xc - 30, 20, -20, xc + 30, 27, -19.4, PAL.Black, SP, false),
			Enum.NormalId.Back, "CINEMA " .. i, PAL.NeonAmber)
		glow(f, hall.Id .. "_MarqueeTrim", xc - 30, 19.4, -20, xc + 30, 19.8, -19.2, PAL.NeonRed, 0.8, 20)
		for j, s in { -1, 1 } do
			local x = xc + s * 60
			box(f, hall.Id .. "_PosterFrame", x - 11, 5, -20, x + 11, 19, -19.6, PAL.Black, METAL, false)
			box(f, hall.Id .. "_Poster", x - 10, 6, -19.6, x + 10, 18, -19.4, POSTERS[(i - 1) * 2 + j], SP, false)
		end
	end

	-- Framed, signed openings into the south rooms.
	for _, o in SOUTH_OPENINGS do
		frame(f, o[5] .. "Frame", "X", 100, -1, o[1], o[2], 0, 12, PAL.NeonRed)
		label(box(f, o[5] .. "Sign", o[1], 14, 99.6, o[2], 17.5, 100, PAL.Black, SP, false), Enum.NormalId.Front, o[6], PAL.NeonAmber)
	end
end

local function buildRestrooms(model)
	local f = folder(model, "Restrooms")
	overlay(f, "Restroom_Tile", -328, 100, -122, 238, PAL.TileWhite, TILE)
	-- Shared vestibule x[-150,-122]; its room-side wall opens into the men's and women's rooms.
	wall(f, "Restroom_VestibuleWall", "Z", 102, 238, -150, -148, 0, 28, PAL.Teal, SP, { { 126, 138, 0, 12 }, { 196, 208, 0, 12 } })
	box(f, "Restroom_DividingWall", -328, 0, 169, -148, 28, 171, PAL.Teal)
	glow(f, "Vestibule_Light", -139, 27.6, 166, -131, 28, 174, PAL.Warm, 0.8, 40)
	-- name, door z0, first stall panel z, dividing-wall face z, counter direction from that face
	for _, r in { { "Men", 126, 106, 169, -1 }, { "Women", 196, 178, 171, 1 } } do
		local name, door, stall0, wz, dir = r[1], r[2], r[3], r[4], r[5]
		doorway(f, name .. "Doorway", -150, 0, door, -148, 12, door + 12)
		label(box(f, name .. "_Sign", -148, 13, door + 1, -147.7, 15, door + 11, PAL.Black, SP, false), Enum.NormalId.Right, string.upper(name), PAL.NeonAmber)
		-- Two stall banks give the large rooms the density of a real multiplex.
		for _, x in { -328, -280 } do
			for k = 0, 6 do
				box(f, name .. "_StallPanel", x, 0, stall0 + 9 * k, x + 12, 9, stall0 + 9 * k + 0.5, PAL.Stall)
			end
			for k = 0, 5 do
				box(f, name .. "_StallDoor", x + 11.6, 1, stall0 + 9 * k + 0.8, x + 12, 8.5, stall0 + 9 * k + 8.7, PAL.Teal)
			end
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
	tag(anchor, V4.TAGS.Exit)

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
	overlay(f, "Service_Floor", 261, 100, 328, 238, PAL.Service, CONCRETE)
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
	box(f, "Service_Shelf", 322, 0, 120, 328, 10, 230, PAL.Metal, METAL)
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

function V4.Build(originCFrame)
	origin = originCFrame or CFrame.identity
	local model = Instance.new("Model")
	model.Name = V4.MODEL_NAME
	buildShell(model)
	for i, hall in HALLS do
		buildHall(model, hall, i)
	end
	for _, c in CORRIDORS do
		buildCorridor(model, c)
	end
	buildConcourse(model)
	buildRestrooms(model)
	buildConcession(model)
	buildArcade(model)
	model.WorldPivot = origin
	local parts, lights = census(model)
	model:SetAttribute("Level4LayoutVersion", V4.LAYOUT_VERSION)
	model:SetAttribute("Level4PreviewReady", true)
	model:SetAttribute("Level4Preview", true)
	model:SetAttribute("PreviewOnly", true)
	model:SetAttribute("PartCount", parts)
	model:SetAttribute("LightCount", lights)
	return model
end

-- Floor probes, doorway clearance rays, chair/doorway counts and the part/light budget.
-- The model must be in Workspace.
function V4.SelfCheck(model)
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
	if chairs ~= #HALLS * V4.CHAIRS_PER_HALL then
		table.insert(issues, string.format("chairs: expected %d, got %d", #HALLS * V4.CHAIRS_PER_HALL, chairs))
	end
	if doors ~= V4.DOORWAYS then
		table.insert(issues, string.format("doorways: expected %d, got %d", V4.DOORWAYS, doors))
	end
	local parts, lights = census(model)
	if parts >= V4.MAX_PARTS or lights >= V4.MAX_LIGHTS then
		table.insert(issues, string.format("over budget: %d parts, %d lights", parts, lights))
	end
	return #issues == 0, { Issues = issues, PartCount = parts, LightCount = lights }
end

return V4
