--!strict
-- Level 4 cinema visual preview. Static, unhooked groundwork only: no round
-- routing, no lobby queue, no Lighting edits, no per-frame work. Builds
-- `Workspace.Level 4 Cinema Preview` (or into a supplied parent) at X~23000,
-- far east of Level 5 (bounds end near X=17287).
--
-- Usage:
--   local L6 = require(ServerScriptService.Level4Generator)
--   local model, err = L6.BuildPreview(workspace)
--   local ok, report = L6.SelfCheck(model)
--
-- Zones along +X (floor top at Y=24):
--   RedConcessionLobby  X 0..96    photo 1 + 2 (checker edge, curved neon soffit)
--   RedTheaterCorridor  X 96..256  photo 2 (tan ceiling, red soffit, orange tubes, doors)
--   NeonCoveCorridor    X 256..400 photo 3 (orange walls, bays, multi-line cove)
--   TealBoxOfficeLobby  X 400..580 photo 4 (downlight grid, turquoise route, box office)

local Level4Generator = {}

local MODEL_NAME = "Level 4 Cinema Preview"
local ORIGIN = CFrame.new(23000, 24, 0)
local LEVEL5_MAX_X = 17287
local MAX_PARTS = 5000
local MAX_LIGHTS = 220
local WALL_T = 1

Level4Generator.MODEL_NAME = MODEL_NAME
Level4Generator.ORIGIN = ORIGIN
Level4Generator.MAX_PARTS = MAX_PARTS

-- Uploaded Level 4 carpet assets; BuildPreview can override each ID.
local FLOOR_TEXTURES = {
	RedCarpet = {
		File = "red-carpet.png",
		DefaultId = "rbxassetid://92732673815453",
		StudsPerTile = 12,
		Fallback = Color3.fromRGB(128, 20, 16),
	},
	SwirlCarpet = {
		File = "swirl-carpet.png",
		DefaultId = "rbxassetid://80407060064074",
		StudsPerTile = 18,
		Fallback = Color3.fromRGB(104, 38, 40),
	},
	RingCarpet = {
		File = "ring-carpet.png",
		DefaultId = "rbxassetid://85044000846144",
		StudsPerTile = 12,
		Fallback = Color3.fromRGB(62, 26, 84),
	},
}
Level4Generator.FLOOR_TEXTURES = FLOOR_TEXTURES

local MAT = {
	Carpet = Enum.Material.Fabric,
	Wall = Enum.Material.SmoothPlastic,
	Tile = Enum.Material.SmoothPlastic,
	Neon = Enum.Material.Neon,
	Metal = Enum.Material.Metal,
	Glass = Enum.Material.Glass,
	Wood = Enum.Material.Wood,
}

local PAL = {
	-- red lobby / corridor
	BloodRed = Color3.fromRGB(210, 4, 8),
	LobbyRed = Color3.fromRGB(215, 8, 8),
	Charcoal = Color3.fromRGB(30, 26, 28),
	SoffitRed = Color3.fromRGB(240, 16, 10),
	MouthOrange = Color3.fromRGB(250, 68, 15),
	TileWhite = Color3.fromRGB(226, 222, 214),
	TileBlack = Color3.fromRGB(20, 18, 18),
	TileRed = Color3.fromRGB(160, 16, 20),
	NeonOrange = Color3.fromRGB(255, 110, 24),
	NeonAmber = Color3.fromRGB(255, 150, 40),
	NeonYellow = Color3.fromRGB(255, 196, 70),
	NeonBlue = Color3.fromRGB(90, 170, 255),
	CanBlack = Color3.fromRGB(34, 30, 30),
	CounterWhite = Color3.fromRGB(232, 228, 220),
	CounterRed = Color3.fromRGB(170, 18, 22),
	MenuGlow = Color3.fromRGB(150, 96, 58),
	PopcornGlow = Color3.fromRGB(255, 214, 120),
	GlassTint = Color3.fromRGB(220, 235, 240),
	SpotWarm = Color3.fromRGB(255, 214, 170),
	CorridorRed = Color3.fromRGB(180, 9, 10),
	CeilingTan = Color3.fromRGB(190, 130, 70),
	DoorFrame = Color3.fromRGB(44, 22, 24),
	DoorLeaf = Color3.fromRGB(20, 12, 14),
	Black = Color3.fromRGB(8, 8, 8),
	PlaqueAmber = Color3.fromRGB(170, 110, 40),
	-- neon cove corridor
	NeonWallOrange = Color3.fromRGB(196, 58, 24),
	Burgundy = Color3.fromRGB(62, 14, 22),
	PilasterOrange = Color3.fromRGB(214, 80, 32),
	RecessDark = Color3.fromRGB(40, 12, 18),
	RecessFloor = Color3.fromRGB(34, 14, 22),
	CeilingDark = Color3.fromRGB(16, 10, 20),
	CoveBody = Color3.fromRGB(28, 16, 32),
	NeonMagenta = Color3.fromRGB(255, 40, 200),
	NeonCyan = Color3.fromRGB(40, 230, 255),
	NeonCobalt = Color3.fromRGB(60, 90, 255),
	NeonWhite = Color3.fromRGB(236, 240, 255),
	NeonViolet = Color3.fromRGB(150, 60, 255),
	LampWarm = Color3.fromRGB(255, 232, 196),
	-- teal lobby
	TealCeiling = Color3.fromRGB(10, 13, 15),
	TealWall = Color3.fromRGB(16, 50, 54),
	GreenLower = Color3.fromRGB(28, 92, 62),
	ColumnGreen = Color3.fromRGB(32, 112, 74),
	RouteTurquoise = Color3.fromRGB(22, 172, 166),
	RouteBand = Color3.fromRGB(136, 94, 58),
	RecessTeal = Color3.fromRGB(14, 30, 34),
	HallDark = Color3.fromRGB(12, 12, 14),
	ExitRed = Color3.fromRGB(200, 20, 20),
	DownlightWhite = Color3.fromRGB(246, 248, 255),
	CounterWood = Color3.fromRGB(110, 68, 40),
	FasciaCream = Color3.fromRGB(226, 218, 200),
	BoxOfficeGlow = Color3.fromRGB(255, 236, 196),
	NeonWarmWhite = Color3.fromRGB(255, 240, 210),
	SignRed = Color3.fromRGB(230, 40, 40),
}

local POSTER_COLORS = {
	Color3.fromRGB(150, 40, 28),
	Color3.fromRGB(40, 96, 150),
	Color3.fromRGB(160, 124, 40),
	Color3.fromRGB(100, 40, 140),
	Color3.fromRGB(28, 124, 84),
	Color3.fromRGB(160, 60, 104),
	Color3.fromRGB(140, 140, 148),
}

local ZONES = { "RedConcessionLobby", "RedTheaterCorridor", "NeonCoveCorridor", "TealBoxOfficeLobby" }

-- Reference photo viewpoints, in local coordinates relative to ORIGIN.
local CAMERA_MARKERS = {
	{ Name = "Camera1_RedConcession", Photo = 1, Eye = Vector3.new(6, 6, 36), Target = Vector3.new(84, 10, -8), Fov = 62 },
	{ Name = "Camera2_RedCorridorView", Photo = 2, Eye = Vector3.new(50, 5.5, 6), Target = Vector3.new(150, 7, 20), Fov = 66 },
	{ Name = "Camera3_NeonCoveCorridor", Photo = 3, Eye = Vector3.new(272, 5.5, 12), Target = Vector3.new(342, 12, 65), Fov = 72 },
	{ Name = "Camera4_TealBoxOffice", Photo = 4, Eye = Vector3.new(408, 6, 10), Target = Vector3.new(575, 4, 25), Fov = 70 },
}
Level4Generator.CAMERA_MARKERS = CAMERA_MARKERS

type PartOpts = {
	collide: boolean?,
	shadow: boolean?,
	reflectance: number?,
	transparency: number?,
	shape: Enum.PartType?,
}

local EMPTY: PartOpts = {}
local NEON: PartOpts = { collide = false, shadow = false }
local FIXTURE: PartOpts = { collide = false }

local partCount = 0
local lightCount = 0

local function newPart(parent: Instance, name: string, size: Vector3, cf: CFrame, color: Color3, material: Enum.Material, opts: PartOpts?): Part
	local o = opts or EMPTY
	local p = Instance.new("Part")
	p.Name = name
	p.Anchored = true
	if o.shape then
		p.Shape = o.shape
	end
	p.Size = size
	p.CFrame = ORIGIN * cf
	p.Color = color
	p.Material = material
	p.TopSurface = Enum.SurfaceType.Smooth
	p.BottomSurface = Enum.SurfaceType.Smooth
	p.CanCollide = o.collide ~= false
	p.CanTouch = false
	p.CastShadow = o.shadow ~= false
	if o.reflectance then
		p.Reflectance = o.reflectance
	end
	if o.transparency then
		p.Transparency = o.transparency
	end
	p.Parent = parent
	partCount += 1
	return p
end

-- Axis-aligned box between two local corners.
local function box(parent: Instance, name: string, x0: number, y0: number, z0: number, x1: number, y1: number, z1: number, color: Color3, material: Enum.Material, opts: PartOpts?): Part
	local ax, bx = math.min(x0, x1), math.max(x0, x1)
	local ay, by = math.min(y0, y1), math.max(y0, y1)
	local az, bz = math.min(z0, z1), math.max(z0, z1)
	return newPart(parent, name, Vector3.new(bx - ax, by - ay, bz - az), CFrame.new((ax + bx) / 2, (ay + by) / 2, (az + bz) / 2), color, material, opts)
end

-- Wall-relative box: `axis` is the axis the wall runs along, `a` spans that
-- axis and `d` spans the perpendicular (depth) axis.
local function slab(parent: Instance, name: string, axis: string, a0: number, a1: number, y0: number, y1: number, d0: number, d1: number, color: Color3, material: Enum.Material, opts: PartOpts?): Part
	if axis == "X" then
		return box(parent, name, a0, y0, d0, a1, y1, d1, color, material, opts)
	end
	return box(parent, name, d0, y0, a0, d1, y1, a1, color, material, opts)
end

-- Horizontal ring segments on a circle in the XZ plane (angles in degrees).
local function arc(parent: Instance, name: string, cx: number, cz: number, r: number, a0: number, a1: number, n: number, radialW: number, y0: number, y1: number, color: Color3, material: Enum.Material, opts: PartOpts?): { Part }
	local parts = {}
	local step = math.rad(a1 - a0) / n
	local len = 2 * (r + radialW / 2) * math.sin(math.abs(step) / 2) + 0.05
	for i = 0, n - 1 do
		local m = math.rad(a0) + step * (i + 0.5)
		local pos = Vector3.new(cx + r * math.cos(m), (y0 + y1) / 2, cz + r * math.sin(m))
		local tangent = Vector3.new(-math.sin(m), 0, math.cos(m))
		table.insert(parts, newPart(parent, name, Vector3.new(radialW, y1 - y0, len), CFrame.lookAt(pos, pos + tangent), color, material, opts))
	end
	return parts
end

-- Flat ceiling disc; its downward face is NormalId.Left.
local function disc(parent: Instance, name: string, x: number, y: number, z: number, diameter: number, color: Color3, material: Enum.Material): Part
	return newPart(parent, name, Vector3.new(0.2, diameter, diameter), CFrame.new(x, y, z) * CFrame.Angles(0, 0, math.rad(90)), color, material, { collide = false, shadow = false, shape = Enum.PartType.Cylinder })
end

local function spot(part: BasePart, face: Enum.NormalId, color: Color3, brightness: number, range: number, angle: number)
	local l = Instance.new("SpotLight")
	l.Face = face
	l.Color = color
	l.Brightness = brightness
	l.Range = range
	l.Angle = angle
	l.Shadows = false
	l.Parent = part
	lightCount += 1
end

local function surface(part: BasePart, face: Enum.NormalId, color: Color3, brightness: number, range: number, angle: number)
	local l = Instance.new("SurfaceLight")
	l.Face = face
	l.Color = color
	l.Brightness = brightness
	l.Range = range
	l.Angle = angle
	l.Shadows = false
	l.Parent = part
	lightCount += 1
end

local function point(part: BasePart, color: Color3, brightness: number, range: number)
	local l = Instance.new("PointLight")
	l.Color = color
	l.Brightness = brightness
	l.Range = range
	l.Shadows = false
	l.Parent = part
	lightCount += 1
end

-- Wall of thickness WALL_T whose interior face sits at `face`, extending
-- outward by `out` (+1/-1). Gaps are sorted {from, to, openingTop}.
local function wall(parent: Instance, name: string, axis: string, a0: number, a1: number, face: number, out: number, height: number, bandH: number, upper: Color3, band: Color3, gaps: { { number } }?)
	local d0, d1 = face, face + out * WALL_T
	local cursor = a0
	local function solid(s: number, e: number)
		if e - s <= 0.01 then
			return
		end
		if bandH > 0 then
			slab(parent, name .. "_Band", axis, s, e, 0, bandH, d0, d1, band, MAT.Wall)
		end
		slab(parent, name, axis, s, e, bandH, height, d0, d1, upper, MAT.Wall)
	end
	for _, g in gaps or {} do
		solid(cursor, g[1])
		if g[3] < height then
			slab(parent, name .. "_Header", axis, g[1], g[2], g[3], height, d0, d1, upper, MAT.Wall)
		end
		cursor = g[2]
	end
	solid(cursor, a1)
end

-- Box recess behind a wall gap. Returns the depth coordinate of its back face.
local function recess(parent: Instance, name: string, axis: string, center: number, width: number, face: number, out: number, depth: number, height: number, wallColor: Color3, floorColor: Color3): number
	local a0, a1 = center - width / 2, center + width / 2
	local back = face + out * depth
	local inner = face + out * WALL_T
	slab(parent, name .. "_Floor", axis, a0, a1, -1, 0, face, back, floorColor, MAT.Carpet)
	slab(parent, name .. "_Back", axis, a0 - WALL_T, a1 + WALL_T, 0, height + WALL_T, back, back + out * WALL_T, wallColor, MAT.Wall)
	slab(parent, name .. "_Side", axis, a0 - WALL_T, a0, 0, height, inner, back, wallColor, MAT.Wall)
	slab(parent, name .. "_Side", axis, a1, a1 + WALL_T, 0, height, inner, back, wallColor, MAT.Wall)
	slab(parent, name .. "_Ceiling", axis, a0 - WALL_T, a1 + WALL_T, height, height + WALL_T, inner, back + out * WALL_T, wallColor, MAT.Wall)
	return back
end

local function door(parent: Instance, name: string, axis: string, center: number, face: number, inward: number, width: number, height: number)
	slab(parent, name .. "_Frame", axis, center - width / 2 - 0.6, center + width / 2 + 0.6, 0, height + 0.6, face, face + inward * 0.2, PAL.DoorFrame, MAT.Wall)
	slab(parent, name .. "_Leaf", axis, center - width / 2, center + width / 2, 0, height, face, face + inward * 0.35, PAL.DoorLeaf, MAT.Wall)
	slab(parent, name .. "_Split", axis, center - 0.06, center + 0.06, 0.2, height - 0.2, face, face + inward * 0.4, PAL.Black, MAT.Metal)
	slab(parent, name .. "_Plaque", axis, center - 0.8, center + 0.8, height + 1, height + 1.6, face, face + inward * 0.15, PAL.PlaqueAmber, MAT.Neon, NEON)
end

local function poster(parent: Instance, name: string, axis: string, center: number, width: number, y0: number, y1: number, face: number, inward: number, color: Color3): Part
	slab(parent, name .. "_Frame", axis, center - width / 2 - 0.4, center + width / 2 + 0.4, y0 - 0.4, y1 + 0.4, face, face + inward * 0.35, PAL.Black, MAT.Metal, FIXTURE)
	local art = slab(parent, name .. "_Art", axis, center - width / 2, center + width / 2, y0, y1, face, face + inward * 0.45, color, MAT.Wall, FIXTURE)
	slab(parent, name .. "_Shadow", axis, center - width / 2 + 0.3, center + width / 2 - 0.3, y1 - 1.3, y1 - 0.2, face + inward * 0.45, face + inward * 0.5, PAL.RecessDark, MAT.Wall, FIXTURE)
	slab(parent, name .. "_Figure", axis, center - width / 5, center + width / 5, y0 + 1.1, y1 - 1.6, face + inward * 0.46, face + inward * 0.51, PAL.DoorLeaf, MAT.Wall, FIXTURE)
	slab(parent, name .. "_Caption", axis, center - width / 2 + 0.5, center + width / 2 - 1, y0 + 0.4, y0 + 0.55, face + inward * 0.5, face + inward * 0.55, PAL.CounterWhite, MAT.Neon, NEON)
	return art
end

local function resolveTextureId(value: any): string?
	if type(value) == "number" then
		return if value > 0 then "rbxassetid://" .. tostring(math.floor(value)) else nil
	end
	if type(value) == "string" then
		if value:match("^%d+$") then
			return "rbxassetid://" .. value
		end
		if value:match("^rbxassetid://%d+$") or value:match("^rbxasset") or value:match("^https?://") then
			return value
		end
	end
	return nil
end

local function applyFloorTexture(floor: Part, key: string, textureIds: { [string]: any })
	local spec = FLOOR_TEXTURES[key]
	local stem = spec.File:gsub("%.png$", "")
	local id = resolveTextureId(textureIds[key]) or resolveTextureId(textureIds[stem]) or resolveTextureId(spec.DefaultId)
	floor.Color = spec.Fallback
	floor:SetAttribute("FloorTextureKey", key)
	floor:SetAttribute("FloorTextureId", id or "")
	if id then
		local t = Instance.new("Texture")
		t.Name = key .. "Texture"
		t.Face = Enum.NormalId.Top
		t.Texture = id
		t.StudsPerTileU = spec.StudsPerTile
		t.StudsPerTileV = spec.StudsPerTile
		t.Parent = floor
	end
end

-- Photos 1 + 2: red concession lobby.
local function buildRedLobby(folder: Instance, textureIds: { [string]: any })
	local H = 22
	local floor = box(folder, "Floor_RedCarpet", 0, -1, -44, 96, 0, 44, FLOOR_TEXTURES.RedCarpet.Fallback, MAT.Carpet)
	applyFloorTexture(floor, "RedCarpet", textureIds)
	box(folder, "Ceiling", -1, H, -45, 97, H + 1, 45, PAL.BloodRed, MAT.Wall)
	wall(folder, "WallWest", "Z", -45, 45, 0, -1, H, 4, PAL.LobbyRed, PAL.Charcoal)
	wall(folder, "WallEast", "Z", -45, 45, 96, 1, H, 4, PAL.LobbyRed, PAL.Charcoal, { { 8, 32, 14 } })
	wall(folder, "WallConcession", "X", 0, 96, -44, -1, H, 4, PAL.LobbyRed, PAL.Charcoal)
	wall(folder, "WallSouth", "X", 0, 96, 44, 1, H, 4, PAL.LobbyRed, PAL.Charcoal)

	-- orange-red corridor mouth, back right of photo 1
	box(folder, "MouthJamb", 95.2, 0, 6.5, 96, 14, 8, PAL.MouthOrange, MAT.Wall)
	box(folder, "MouthJamb", 95.2, 0, 32, 96, 14, 33.5, PAL.MouthOrange, MAT.Wall)
	box(folder, "MouthLintel", 95.2, 14, 6.5, 96, 15, 33.5, PAL.MouthOrange, MAT.Wall)

	-- The tile hugs the concession and tapers into a curved wedge at the near left.
	local cx, cz, rx, rz = 0, -44, 85, 70
	for zs = -44, 25 do
		local dz = (zs + 1 - cz) / rz
		local edge = rx * math.sqrt(math.max(0, 1 - dz * dz))
		if edge > 0.5 then
			box(folder, "CheckerBase", 0.5, 0, zs, edge, 0.1, zs + 1, PAL.TileWhite, MAT.Tile)
		end
	end
	local function inside(x: number, z: number): boolean
		return ((x - cx) / rx) ^ 2 + ((z - cz) / rz) ^ 2 <= 1
	end
	for i = 0, 20 do
		for j = 0, 17 do
			local x0, z0 = i * 4, -44 + j * 4
			local x1, z1 = x0 + 4, z0 + 4
			if (i + j) % 2 == 0 and x1 <= 95.5 and inside(x1, z0) and inside(x1, z1) then
				local color = if i % 3 == 0 and j % 2 == 0 then PAL.TileRed else PAL.TileBlack
				box(folder, "CheckerTile", math.max(x0, 0.5), 0.1, z0, x1, 0.13, z1, color, MAT.Tile)
			end
		end
	end
	for i = 0, 27 do
		local a0, a1 = math.rad(i * 90 / 28), math.rad((i + 1) * 90 / 28)
		local p0 = Vector3.new(rx * math.cos(a0), 0.19, cz + rz * math.sin(a0))
		local p1 = Vector3.new(rx * math.cos(a1), 0.19, cz + rz * math.sin(a1))
		newPart(folder, "CheckerEdge", Vector3.new(0.8, 0.12, (p1 - p0).Magnitude + 0.05), CFrame.lookAt((p0 + p1) / 2, p1), PAL.TileBlack, MAT.Tile, FIXTURE)
	end

	-- curved soffit tracing across the ceiling, multi-stripe neon underside
	arc(folder, "Soffit", 48, 70, 80, -127, -53, 26, 10, 18.5, H, PAL.SoffitRed, MAT.Wall, FIXTURE)
	local stripes = {
		{ 76.4, PAL.NeonOrange },
		{ 78.8, PAL.NeonAmber },
		{ 81.2, PAL.NeonYellow },
		{ 83.6, PAL.NeonOrange },
	}
	for k, s in stripes do
		local parts = arc(folder, "SoffitNeon", 48, 70, s[1] :: number, -127, -53, 26, 0.7, 18.25, 18.5, s[2] :: Color3, MAT.Neon, NEON)
		if k == 2 then
			for idx, p in parts do
				if idx % 5 == 3 then
					point(p, PAL.NeonAmber, 1.4, 22)
				end
			end
		end
	end
	arc(folder, "SoffitBlueLine", 48, 70, 74.9, -127, -53, 26, 0.2, 19.2, 19.45, PAL.NeonBlue, MAT.Neon, NEON)
	-- Thin off-centre white S-line visible against the bare red ceiling.
	local whiteLine = {
		Vector3.new(4, 21.8, 8), Vector3.new(14, 21.8, 13), Vector3.new(24, 21.8, 12),
		Vector3.new(34, 21.8, 7), Vector3.new(44, 21.8, -1), Vector3.new(53, 21.8, -7),
		Vector3.new(63, 21.8, -8), Vector3.new(72, 21.8, -4), Vector3.new(82, 21.8, 3),
	}
	for i = 1, #whiteLine - 1 do
		local a, b = whiteLine[i], whiteLine[i + 1]
		local tube = newPart(folder, "WhiteCeilingLine", Vector3.new(0.26, 0.2, (b - a).Magnitude + 0.08), CFrame.lookAt((a + b) / 2, b), PAL.NeonWhite, MAT.Neon, NEON)
		if i == 3 or i == 7 then point(tube, PAL.NeonWhite, 0.6, 12) end
	end

	-- concession: white/red counter, checker backsplash, menu boards
	box(folder, "Counter", 22, 0, -38, 74, 3, -34, PAL.CounterRed, MAT.Wall)
	box(folder, "CounterStripe", 22, 3, -38, 74, 3.6, -34, PAL.CounterWhite, MAT.Wall)
	box(folder, "CounterTop", 21.6, 3.6, -38.4, 74.4, 3.9, -33.6, PAL.CounterWhite, MAT.Wall)
	box(folder, "BackCounter", 22, 0, -44, 74, 3, -41.5, PAL.CounterRed, MAT.Wall)
	box(folder, "BackCounterTop", 22, 3, -44, 74, 3.2, -41.3, PAL.CounterWhite, MAT.Wall)
	box(folder, "Backsplash", 22, 4, -44, 74, 10, -43.85, PAL.TileWhite, MAT.Tile)
	for i = 0, 25 do
		for j = 0, 2 do
			if (i + j) % 2 == 0 then
				box(folder, "BacksplashTile", 22 + i * 2, 4 + j * 2, -43.85, 24 + i * 2, 6 + j * 2, -43.8, PAL.TileBlack, MAT.Tile)
			end
		end
	end
	for _, span in { { 25, 40 }, { 41, 56 }, { 57, 72 } } do
		box(folder, "MenuFrame", span[1], 11, -44, span[2], 15, -43.6, PAL.Black, MAT.Metal, FIXTURE)
		box(folder, "MenuBoard", span[1] + 0.4, 11.4, -43.6, span[2] - 0.4, 14.6, -43.5, PAL.CanBlack, MAT.Wall, FIXTURE)
		for row = 0, 3 do
			box(folder, "MenuLine", span[1] + 1, 12 + row * 0.55, -43.49, span[2] - 3 - row % 2, 12.1 + row * 0.55, -43.46, PAL.MenuGlow, MAT.Neon, NEON)
		end
	end
	box(folder, "PopcornCase", 28, 3.2, -43.5, 33, 8, -41.8, PAL.GlassTint, MAT.Glass, { transparency = 0.55, shadow = false })
	-- The closed display is empty; keep this legacy part invisible for saved previews.
	box(folder, "Popcorn", 28.2, 3.2, -43.3, 32.8, 4.8, -42, PAL.PopcornGlow, MAT.Neon, { collide = false, shadow = false, transparency = 1 })

	for i, x in { 20, 48, 76 } do
		poster(folder, "Poster", "X", x, 6, 3, 11, 44, -1, POSTER_COLORS[i])
	end
	for _, p in { { 14, 30 }, { 48, 34 }, { 82, 30 }, { 32, -36 }, { 48, -36 }, { 64, -36 }, { 20, -22 }, { 76, -22 } } do
		local can = disc(folder, "SpotCan", p[1], H - 0.1, p[2], 1.4, PAL.CanBlack, MAT.Metal)
		spot(can, Enum.NormalId.Left, PAL.SpotWarm, 1.6, 24, 50)
	end
end

-- Photo 2: long red theatre corridor.
local function buildRedCorridor(folder: Instance, textureIds: { [string]: any })
	local H = 14
	local floor = box(folder, "Floor_RedCarpetCorridor", 96, -1, 8, 256, 0, 32, FLOOR_TEXTURES.RedCarpet.Fallback, MAT.Carpet)
	applyFloorTexture(floor, "RedCarpet", textureIds)
	wall(folder, "WallNorth", "X", 96, 256, 8, -1, H, 3.5, PAL.CorridorRed, PAL.Charcoal)
	wall(folder, "WallSouth", "X", 96, 256, 32, 1, H, 3.5, PAL.CorridorRed, PAL.Charcoal)
	box(folder, "CeilingTan", 96, H, 7, 256, H + 1, 33, PAL.CeilingTan, MAT.Wall)
	box(folder, "Soffit", 96, 12, 14, 130, H, 26, PAL.SoffitRed, MAT.Wall, FIXTURE)
	for k, z in { 16, 20, 24 } do
		local tube = box(folder, "NeonTube", 96, 11.6, z - 0.25, 130, 12, z + 0.25, PAL.NeonOrange, MAT.Neon, NEON)
		if k == 2 then
			surface(tube, Enum.NormalId.Bottom, PAL.NeonOrange, 1.6, 14, 120)
		end
	end
	box(folder, "BlueAccentLine", 96, 12.3, 13.8, 130, 12.5, 14, PAL.NeonBlue, MAT.Neon, NEON)
	for i = 0, 4 do
		local x = 132 + 28 * i
		door(folder, "TheaterDoor", "X", x, 8, 1, 6, 8)
		door(folder, "TheaterDoor", "X", x, 32, -1, 6, 8)
		for _, z in { 11, 29 } do
			local can = disc(folder, "SpotCan", x, H - 0.1, z, 1.2, PAL.CanBlack, MAT.Metal)
			spot(can, Enum.NormalId.Left, PAL.SpotWarm, 1.2, 16, 55)
		end
	end
end

-- Photo 3: orange/violet corridor with perimeter neon cove.
local function buildNeonCorridor(folder: Instance, textureIds: { [string]: any })
	local H, WALL_H, BAY_TOP = 13, 14, 9
	local floor = box(folder, "Floor_SwirlCarpet", 256, -1, 0, 400, 0, 40, FLOOR_TEXTURES.SwirlCarpet.Fallback, MAT.Carpet)
	applyFloorTexture(floor, "SwirlCarpet", textureIds)
	wall(folder, "WallWest", "Z", -1, 41, 256, -1, 15, 2.5, PAL.NeonWallOrange, PAL.Burgundy, { { 8, 32, 11 } })

	local gaps = {}
	for i = 0, 5 do
		local c = 268 + 24 * i
		table.insert(gaps, { c - 7, c + 7, BAY_TOP })
	end
	local sides = { { face = 0, out = -1 }, { face = 40, out = 1 } }
	for s, side in sides do
		local inward = -side.out
		if s == 1 then
			wall(folder, "WallSide", "X", 256, 400, side.face, side.out, WALL_H, 2.5, PAL.NeonWallOrange, PAL.Burgundy, gaps)
			for i = 0, 5 do
				local c = 268 + 24 * i
				local back = recess(folder, "Bay", "X", c, 14, side.face, side.out, 5, BAY_TOP, PAL.RecessDark, PAL.RecessFloor)
				if i % 2 == 0 then
					door(folder, "BayDoor", "X", c, back, inward, 7, 7.4)
				else
					poster(folder, "BayPoster", "X", c, 5, 1.6, 8, back, inward, POSTER_COLORS[(i % #POSTER_COLORS) + 1])
				end
			end
			for i = 1, 5 do
				local x = 256 + 24 * i
				slab(folder, "Pilaster", "X", x - 2, x + 2, 0, 11.2, side.face, side.face + inward * 0.8, PAL.PilasterOrange, MAT.Wall)
			end
		else
			wall(folder, "JunctionOpening", "X", 256, 400, 40, 1, WALL_H, 2.5, PAL.NeonWallOrange, PAL.Burgundy, { { 300, 390, 13 } })
			for _, x in { 300, 390 } do
				box(folder, "JunctionColumn", x - 2, 0, 39, x + 2, 13, 43, PAL.PilasterOrange, MAT.Wall)
			end
		end
	end

	box(folder, "CeilingDark", 256, H, -1, 400, H + 1, 41, PAL.CeilingDark, MAT.Wall)
	-- The reference turns into a broad orange junction, not a symmetric tunnel.
	local wing = box(folder, "JunctionFloor", 300, -1, 40, 400, 0, 80, FLOOR_TEXTURES.SwirlCarpet.Fallback, MAT.Carpet)
	applyFloorTexture(wing, "SwirlCarpet", textureIds)
	box(folder, "JunctionCeiling", 300, H, 40, 400, H + 1, 80, PAL.CeilingDark, MAT.Wall)
	wall(folder, "JunctionOuterWall", "X", 300, 400, 80, 1, WALL_H, 2.5, PAL.NeonWallOrange, PAL.Burgundy)
	wall(folder, "JunctionWestWall", "Z", 40, 80, 300, -1, WALL_H, 2.5, PAL.NeonWallOrange, PAL.Burgundy)
	wall(folder, "JunctionEastWall", "Z", 40, 80, 400, 1, WALL_H, 2.5, PAL.NeonWallOrange, PAL.Burgundy)
	for _, x in { 320, 360 } do
		poster(folder, "JunctionPoster", "X", x, 5, 2, 9, 80, -1, POSTER_COLORS[(x / 40) % #POSTER_COLORS + 1])
	end
	-- perimeter cove band that dominates the composition
	box(folder, "Cove", 256, 11.2, 0, 400, H, 5, PAL.CoveBody, MAT.Wall, FIXTURE)
	box(folder, "Cove", 256, 11.2, 35, 400, H, 40, PAL.CoveBody, MAT.Wall, FIXTURE)
	box(folder, "Cove", 256, 11.2, 5, 261, H, 35, PAL.CoveBody, MAT.Wall, FIXTURE)
	box(folder, "Cove", 395, 11.2, 5, 400, H, 35, PAL.CoveBody, MAT.Wall, FIXTURE)
	local faceColors = { PAL.NeonMagenta, PAL.NeonCyan, PAL.NeonCobalt, PAL.NeonWhite }
	for k, color in faceColors do
		local y0 = 11.34 + 0.42 * (k - 1)
		local y1 = y0 + 0.22
		local strips = {
			{ box(folder, "CoveNeon", 261, y0, 5, 395, y1, 5.12, color, MAT.Neon, NEON), Enum.NormalId.Back },
			{ box(folder, "CoveNeon", 261, y0, 34.88, 395, y1, 35, color, MAT.Neon, NEON), Enum.NormalId.Front },
			{ box(folder, "CoveNeon", 261, y0, 5, 261.12, y1, 35, color, MAT.Neon, NEON), Enum.NormalId.Right },
			{ box(folder, "CoveNeon", 394.88, y0, 5, 395, y1, 35, color, MAT.Neon, NEON), Enum.NormalId.Left },
		}
		if k <= 2 then
			for _, st in strips do
				surface(st[1] :: Part, st[2] :: Enum.NormalId, color, 2.2, 16, 110)
			end
		end
	end
	-- Continue the colored cove around the junction corner.
	for k, color in faceColors do
		local y0 = 11.34 + 0.42 * (k - 1)
		local far = box(folder, "JunctionCoveNeon", 304, y0, 75, 396, y0 + 0.22, 75.15, color, MAT.Neon, NEON)
		box(folder, "JunctionCoveNeon", 304, y0, 40, 304.15, y0 + 0.22, 75, color, MAT.Neon, NEON)
		box(folder, "JunctionCoveNeon", 395.85, y0, 40, 396, y0 + 0.22, 75, color, MAT.Neon, NEON)
		if k <= 2 then surface(far, Enum.NormalId.Back, color, 1.5, 14, 110) end
	end
	for _, loop in { { 1.6, PAL.NeonMagenta }, { 3.4, PAL.NeonViolet } } do
		local d, color = loop[1] :: number, loop[2] :: Color3
		box(folder, "CoveUnderNeon", 256 + d, 11.05, d - 0.15, 400 - d, 11.2, d + 0.15, color, MAT.Neon, NEON)
		box(folder, "CoveUnderNeon", 256 + d, 11.05, 40 - d - 0.15, 400 - d, 11.2, 40 - d + 0.15, color, MAT.Neon, NEON)
		box(folder, "CoveUnderNeon", 256 + d - 0.15, 11.05, d, 256 + d + 0.15, 11.2, 40 - d, color, MAT.Neon, NEON)
		box(folder, "CoveUnderNeon", 400 - d - 0.15, 11.05, d, 400 - d + 0.15, 11.2, 40 - d, color, MAT.Neon, NEON)
	end
	for i = 0, 6 do
		local x = 268 + 20 * i
		for _, z in { 13, 27 } do
			local lamp = disc(folder, "RecessedLamp", x, H - 0.1, z, 1.8, PAL.LampWarm, MAT.Neon)
			if i % 2 == 0 and z == 13 then
				spot(lamp, Enum.NormalId.Left, PAL.LampWarm, 1.4, 16, 70)
			end
		end
	end
end

-- Photo 4: dark teal box-office lobby.
local function buildTealLobby(folder: Instance, textureIds: { [string]: any })
	local H = 16
	local floor = box(folder, "Floor_RingCarpet", 400, -1, -70, 580, 0, 70, FLOOR_TEXTURES.RingCarpet.Fallback, MAT.Carpet)
	applyFloorTexture(floor, "RingCarpet", textureIds)
	box(folder, "Ceiling", 399, H, -71, 581, H + 1, 71, PAL.TealCeiling, MAT.Wall)
	wall(folder, "WallWest", "Z", -71, 71, 400, -1, H, 5, PAL.TealWall, PAL.GreenLower, { { 0, 40, 13 } })
	wall(folder, "WallEast", "Z", -71, 71, 580, 1, H, 5, PAL.TealWall, PAL.GreenLower, { { -10, 10, 10 } })
	wall(folder, "WallSouth", "X", 400, 580, 70, 1, H, 5, PAL.TealWall, PAL.GreenLower)

	-- left side: arcade recesses alternating with lit poster cases
	local gaps = {}
	for i = 0, 7 do
		local c = 420 + 20 * i
		table.insert(gaps, { c - 5, c + 5, 10 })
	end
	wall(folder, "WallNorth", "X", 400, 580, -70, -1, H, 5, PAL.TealWall, PAL.GreenLower, gaps)
	for i = 0, 7 do
		local c = 420 + 20 * i
		local back = recess(folder, "Arcade", "X", c, 10, -70, -1, 8, 10, PAL.RecessTeal, PAL.HallDark)
		local glow = slab(folder, "ArcadeGlow", "X", c - 4, c + 4, 9.5, 9.8, back, back + 1.2, PAL.PlaqueAmber, MAT.Neon, NEON)
		point(glow, PAL.PlaqueAmber, 0.7, 10)
	end
	for i = 0, 6 do
		poster(folder, "PosterCase", "X", 430 + 20 * i, 6, 1.8, 10, -70, 1, POSTER_COLORS[i + 1])
	end

	-- distant exit hallway for the vanishing point
	local back = recess(folder, "ExitHall", "Z", 0, 20, 580, 1, 28, 10, PAL.HallDark, PAL.HallDark)
	local sign = slab(folder, "ExitSign", "Z", -2, 2, 8, 9, back, back - 0.2, PAL.ExitRed, MAT.Neon, NEON)
	point(sign, PAL.ExitRed, 0.8, 12)

	-- A broad tiled field continues toward the ticket counter; one tan sweep
	-- divides it from the purple carpet.
	local function routeEdge(x: number): number
		return 13 + 47 * math.exp(-(x - 400) / 45)
	end
	for x = 400, 576, 4 do
		local z0, z1 = routeEdge(x), routeEdge(x + 4)
		box(folder, "RouteBase", x, 0, math.min(z0, z1), x + 4, 0.11, 70, PAL.RouteTurquoise, MAT.Tile, { reflectance = 0.16 })
		for z = math.ceil(math.max(z0, z1) / 4) * 4, 66, 4 do
			local tile = if (x / 4 + z / 4) % 2 == 0 then PAL.RouteTurquoise else Color3.fromRGB(28, 154, 151)
			box(folder, "RouteTile", x + 0.06, 0.11, z + 0.06, x + 3.94, 0.16, z + 3.94, tile, MAT.Tile, { reflectance = 0.18 })
		end
		local a, b = Vector3.new(x, 0.2, z0), Vector3.new(x + 4, 0.2, z1)
		newPart(folder, "RouteBand", Vector3.new(2.4, 0.16, (b - a).Magnitude + 0.1), CFrame.lookAt((a + b) / 2, b), PAL.RouteBand, MAT.Tile, FIXTURE)
	end

	for _, p in { { 450, -30 }, { 500, -30 }, { 550, -30 }, { 520, 20 }, { 560, 20 } } do
		local x, z = p[1], p[2]
		box(folder, "Column", x - 1.5, 0, z - 1.5, x + 1.5, 14.5, z + 1.5, PAL.ColumnGreen, MAT.Wall)
		box(folder, "ColumnCap", x - 1.7, 14.5, z - 1.7, x + 1.7, H, z + 1.7, PAL.TealWall, MAT.Wall)
	end

	-- neat rows of circular white downlights
	for i = 0, 11 do
		for j = 0, 7 do
			local x, z = 414 + 14 * i, -54 + 16 * j
			if not (x > 466 and x < 554 and z >= 58) then
				local d = disc(folder, "Downlight", x, H - 0.1, z, 2.4, PAL.DownlightWhite, MAT.Neon)
				if i % 3 == 1 and j % 3 == 1 then
					spot(d, Enum.NormalId.Left, PAL.DownlightWhite, 1.2, 18, 70)
				end
			end
		end
	end

	-- bright box office on the right
	local glow = box(folder, "BoxOfficeGlow", 472, 5, 69.6, 548, 10.6, 70, PAL.BoxOfficeGlow, MAT.Neon, NEON)
	surface(glow, Enum.NormalId.Front, PAL.BoxOfficeGlow, 1.5, 22, 120)
	for _, x in { 491, 510, 529 } do
		box(folder, "BoxOfficeMullion", x - 0.3, 5, 69.4, x + 0.3, 10.6, 69.6, PAL.Black, MAT.Metal, FIXTURE)
	end
	box(folder, "BoxOfficeCounter", 470, 0, 62, 550, 3.8, 65, PAL.CounterWhite, MAT.Wall)
	box(folder, "BoxOfficeStripe", 470, 2.6, 61.85, 550, 3.1, 62, PAL.RouteTurquoise, MAT.Wall)
	box(folder, "BoxOfficeTop", 469.6, 3.8, 61.6, 550.4, 4.1, 65.4, PAL.CounterWood, MAT.Wood)
	box(folder, "BoxOfficeGlass", 470, 4.1, 63.3, 550, 9.2, 63.5, PAL.GlassTint, MAT.Glass, { transparency = 0.75, shadow = false })
	box(folder, "BoxOfficeReturn", 468, 0, 60, 470, 11, 70, PAL.CounterWhite, MAT.Wall)
	box(folder, "BoxOfficeReturn", 550, 0, 60, 552, 11, 70, PAL.CounterWhite, MAT.Wall)
	box(folder, "BoxOfficeFascia", 468, 11, 60, 552, 14, 70, PAL.FasciaCream, MAT.Wall)
	local under = box(folder, "BoxOfficeUnderglow", 468.5, 10.85, 60.4, 551.5, 11, 61, PAL.NeonWarmWhite, MAT.Neon, NEON)
	surface(under, Enum.NormalId.Bottom, PAL.NeonWarmWhite, 1.8, 14, 100)
	box(folder, "BoxOfficeSign", 490, 12, 59.8, 530, 13.2, 60, PAL.SignRed, MAT.Neon, NEON)
end

local function buildCameraMarkers(folder: Instance)
	for _, m in CAMERA_MARKERS do
		local p = newPart(folder, m.Name, Vector3.new(1, 1, 1), CFrame.lookAt(m.Eye, m.Target), PAL.Black, MAT.Wall, { collide = false, shadow = false, transparency = 1 })
		p.CanQuery = false
		p:SetAttribute("ReferencePhoto", m.Photo)
		p:SetAttribute("FieldOfView", m.Fov)
	end
end

-- Builds the preview into `parent` (default workspace). Refuses, returning
-- nil plus a reason, if a model with MODEL_NAME already exists there.
function Level4Generator.BuildPreview(parent: Instance?, textureIds: { [string]: any }?): (Model?, string?)
	local target = parent or workspace
	if target:FindFirstChild(MODEL_NAME) then
		return nil, `{MODEL_NAME} already exists under {target:GetFullName()}; refusing to replace it`
	end
	local ids = textureIds or {}
	partCount, lightCount = 0, 0

	local model = Instance.new("Model")
	model.Name = MODEL_NAME
	local builders = { buildRedLobby, buildRedCorridor, buildNeonCorridor, buildTealLobby }
	for i, zone in ZONES do
		local folder = Instance.new("Folder")
		folder.Name = zone
		folder.Parent = model
		builders[i](folder, ids)
	end
	local markers = Instance.new("Folder")
	markers.Name = "CameraMarkers"
	markers.Parent = model
	buildCameraMarkers(markers)

	model.WorldPivot = ORIGIN
	model:SetAttribute("Level4Preview", true)
	model:SetAttribute("PreviewOnly", true)
	model:SetAttribute("PartCount", partCount)
	model:SetAttribute("LightCount", lightCount)
	model.Parent = target
	return model, nil
end

-- Structural self-check. Returns ok plus a report with any issues.
function Level4Generator.SelfCheck(model: Instance?): (boolean, { [string]: any })
	local issues: { string } = {}
	local report: { [string]: any } = { Issues = issues }
	if not model or not model:IsA("Model") or model.Name ~= MODEL_NAME then
		table.insert(issues, "missing or misnamed preview model")
		return false, report
	end
	local m = model :: Model
	if m:GetAttribute("Level4Preview") ~= true then
		table.insert(issues, "Level4Preview attribute missing")
	end
	for _, name in ZONES do
		if not m:FindFirstChild(name) then
			table.insert(issues, "missing zone " .. name)
		end
	end

	local markers = m:FindFirstChild("CameraMarkers")
	for _, spec in CAMERA_MARKERS do
		local p = markers and markers:FindFirstChild(spec.Name)
		if not (p and p:IsA("BasePart")) then
			table.insert(issues, "missing camera marker " .. spec.Name)
		elseif p.Transparency < 1 or p.CanCollide then
			table.insert(issues, "camera marker not invisible/non-collidable: " .. spec.Name)
		end
	end

	local parts, lights, unanchored = 0, 0, 0
	local floorKeys: { [string]: boolean } = {}
	for _, d in m:GetDescendants() do
		if d:IsA("BasePart") then
			parts += 1
			if not d.Anchored then
				unanchored += 1
			end
			local key = d:GetAttribute("FloorTextureKey")
			if type(key) == "string" then
				floorKeys[key] = true
				local id = d:GetAttribute("FloorTextureId")
				if type(id) == "string" and id ~= "" then
					local tex = d:FindFirstChildOfClass("Texture")
					if not tex or tex.Texture ~= id then
						table.insert(issues, "floor texture not applied on " .. d:GetFullName())
					end
				end
				if math.abs(d.Position.Y + d.Size.Y / 2 - ORIGIN.Y) > 0.01 then
					table.insert(issues, "floor top off baseline: " .. d:GetFullName())
				end
			end
		elseif d:IsA("Light") then
			lights += 1
		elseif d:IsA("LuaSourceContainer") then
			table.insert(issues, "script found inside preview: " .. d:GetFullName())
		end
	end
	for key in FLOOR_TEXTURES do
		if not floorKeys[key] then
			table.insert(issues, "no floor uses " .. key)
		end
	end
	if unanchored > 0 then
		table.insert(issues, `{unanchored} unanchored parts`)
	end
	if parts > MAX_PARTS then
		table.insert(issues, `part count {parts} exceeds {MAX_PARTS}`)
	end
	if lights > MAX_LIGHTS then
		table.insert(issues, `light count {lights} exceeds {MAX_LIGHTS}`)
	end

	local cf, size = m:GetBoundingBox()
	local minX = cf.Position.X - size.X / 2
	if minX <= LEVEL5_MAX_X + 1000 then
		table.insert(issues, `preview min X {math.floor(minX)} too close to Level 5 (max X {LEVEL5_MAX_X})`)
	end

	report.PartCount = parts
	report.LightCount = lights
	report.MinX = minX
	report.BoundsSize = size
	return #issues == 0, report
end

return Level4Generator
