-- Level 4 cinema extension. Geometry is appended to the live preview once.
local Expansion = {}
local ORIGIN = CFrame.new(23000, 24, 0)
local MODEL_NAME = "Level 4 Cinema Preview"
local EXTENSION_NAME = "ExtendedCinema"
local RED = "rbxassetid://92732673815453"
local SWIRL = "rbxassetid://80407060064074"
local RING = "rbxassetid://85044000846144"

local function part(parent, name, size, cf, color, material, canCollide, shape)
	local p = Instance.new("Part")
	p.Name = name
	p.Anchored = true
	p.Size = size
	p.CFrame = ORIGIN * cf
	p.Color = color
	p.Material = material
	p.CanCollide = canCollide ~= false
	p.CanTouch = false
	p.TopSurface = Enum.SurfaceType.Smooth
	p.BottomSurface = Enum.SurfaceType.Smooth
	if shape then p.Shape = shape end
	if material == Enum.Material.Neon then p.CastShadow = false end
	p.Parent = parent
	return p
end

local function box(parent, name, x0, y0, z0, x1, y1, z1, color, material, canCollide)
	local a, b = math.min(x0, x1), math.max(x0, x1)
	local c, d = math.min(y0, y1), math.max(y0, y1)
	local e, f = math.min(z0, z1), math.max(z0, z1)
	return part(parent, name, Vector3.new(b - a, d - c, f - e),
		CFrame.new((a + b) / 2, (c + d) / 2, (e + f) / 2), color, material, canCollide)
end

local function cyl(parent, name, x, y, z, diameter, height, color, material, canCollide)
	return part(parent, name, Vector3.new(height, diameter, diameter),
		CFrame.new(x, y, z) * CFrame.Angles(0, 0, math.rad(90)),
		color, material, canCollide, Enum.PartType.Cylinder)
end

local function glow(parent, name, x0, y0, z0, x1, y1, z1, color, brightness, range)
	local p = box(parent, name, x0, y0, z0, x1, y1, z1, color, Enum.Material.Neon, false)
	local light = Instance.new("PointLight")
	light.Color = color
	light.Brightness = brightness or 0.5
	light.Range = range or 16
	light.Shadows = false
	light.Parent = p
	return p
end

local function carpet(parent, name, x0, z0, x1, z1, id, tile)
	local p = box(parent, name, x0, -0.45, z0, x1, 0, z1,
		Color3.fromRGB(90, 24, 29), Enum.Material.Fabric)
	local t = Instance.new("Texture")
	t.Name = "CarpetPattern"
	t.Face = Enum.NormalId.Top
	t.Texture = id
	t.StudsPerTileU = tile
	t.StudsPerTileV = tile
	t.Parent = p
	return p
end

local function marker(parent, name, eye, target, fov)
	local p = part(parent, name, Vector3.new(1, 1, 1), CFrame.lookAt(eye, target),
		Color3.new(0, 0, 0), Enum.Material.SmoothPlastic, false)
	p.Transparency = 1
	p.CanQuery = false
	p.CastShadow = false
	p:SetAttribute("FieldOfView", fov)
	return p
end

local function counts(model)
	local parts, lights = 0, 0
	for _, d in model:GetDescendants() do
		if d:IsA("BasePart") then parts += 1
		elseif d:IsA("Light") then lights += 1 end
	end
	return parts, lights
end

local function buildConnector(root, ids)
	local folder = Instance.new("Folder")
	folder.Name = "Connector"
	folder.Parent = root
	carpet(folder, "ConnectorCarpet", 608, -10, 640, 10, ids.Red or RED, 12)
	local red = Color3.fromRGB(170, 25, 22)
	box(folder, "ConnectorWall_North", 609, 0, -11, 640, 12, -10, red, Enum.Material.SmoothPlastic)
	box(folder, "ConnectorWall_South", 609, 0, 10, 640, 12, 11, red, Enum.Material.SmoothPlastic)
	box(folder, "ConnectorCeiling", 609, 12, -11, 640, 12.8, 11, Color3.fromRGB(42, 17, 20), Enum.Material.SmoothPlastic)
	glow(folder, "ConnectorCove_North", 610, 11, -10, 639, 11.2, -9.7, Color3.fromRGB(255, 55, 30), 0.25, 10)
	glow(folder, "ConnectorCove_South", 610, 11, 9.7, 639, 11.2, 10, Color3.fromRGB(255, 55, 30), 0.25, 10)
end

local function buildFoyer(root, ids)
	local f = Instance.new("Folder")
	f.Name = "Foyer"
	f.Parent = root
	local H, CX = 18, 705
	local RED, ORANGE, AMBER = Color3.fromRGB(255, 34, 20), Color3.fromRGB(255, 92, 28), Color3.fromRGB(255, 158, 84)
	local WALL, COL, SOFFIT = Color3.fromRGB(126, 24, 17), Color3.fromRGB(150, 22, 18), Color3.fromRGB(52, 12, 10)
	local DARK, CEIL, TOP = Color3.fromRGB(9, 5, 6), Color3.fromRGB(15, 9, 9), Color3.fromRGB(20, 11, 11)
	local CHROME, LEAF, GLASS = Color3.fromRGB(150, 146, 140), Color3.fromRGB(26, 11, 13), Color3.fromRGB(205, 225, 235)
	local SP, NEON, METAL = Enum.Material.SmoothPlastic, Enum.Material.Neon, Enum.Material.Metal
	-- box() with any corner order; hands back the part when the helper returns one
	local function b(name, x0, y0, z0, x1, y1, z1, color, mat, cc)
		return box(f, name, math.min(x0, x1), math.min(y0, y1), math.min(z0, z1), math.max(x0, x1), math.max(y0, y1), math.max(z0, z1), color, mat or SP, cc)
	end
	-- cyl() is given its vertical centre, so every call below reads as a y0..y1 span
	local function round(name, x, z, d, y0, y1, color, mat, cc)
		return cyl(f, name, x, (y0 + y1) / 2, z, d, y1 - y0, color, mat or SP, cc)
	end

	-- shell: loop-pattern red carpet, dark ceiling, solid walls open only at the west entrance and east exit
	carpet(f, "FoyerCarpet", 640, -70, 770, 70, (ids and ids.Red) or "rbxassetid://92732673815453", 12)
	b("FoyerCeiling", 638, H, -72, 772, H + 1, 72, CEIL)
	for _, w in ipairs({
		{ 638, -72, 772, -70, 0, H }, { 638, 70, 772, 72, 0, H }, { 638, -72, 640, -10, 0, H }, { 638, 10, 640, 72, 0, H },
		{ 638, -10, 640, 10, 14, H }, { 770, -72, 772, -12, 0, H }, { 770, 12, 772, 72, 0, H }, { 770, -12, 772, 12, 14, H },
		{ 640, -70, 667, -67, 0, 15.2 }, { 683, -70, 727, -67, 0, 15.2 }, { 743, -70, 770, -67, 0, 15.2 },
		{ 667, -70, 683, -67, 11, 15.2 }, { 727, -70, 743, -67, 11, 15.2 },
	}) do
		b("FoyerWall", w[1], w[5], w[2], w[3], w[6], w[4], WALL)
	end
	for _, e in ipairs({ { 640, 10, 1 }, { 770, 12, -1 } }) do
		for s = -1, 1, 2 do
			b("RouteJamb", e[1], 0, s * e[2], e[1] + e[3] * 0.6, 14, s * (e[2] + 0.6), DARK)
			b("RouteJambGlow", e[1] + e[3] * 0.6, 0.5, s * (e[2] + 0.15), e[1] + e[3] * 0.75, 13.5, s * (e[2] + 0.45), ORANGE, NEON, false)
		end
	end

	-- perimeter drop soffit: lit red neon lip on its inner edge with an orange line above
	for _, s in ipairs({ { 640, -70, 770, -64 }, { 640, 64, 770, 70 }, { 640, -64, 646, 64 }, { 764, -64, 770, 64 } }) do b("CoveSoffit", s[1], 15.2, s[2], s[3], H, s[4], SOFFIT) end
	for i, l in ipairs({ { 646, -64.3, 764, -63.9 }, { 646, 63.9, 764, 64.3 }, { 645.7, -64, 646.1, 64 }, { 763.9, -64, 764.3, 64 } }) do
		b("CoveBand", l[1], 16.4, l[2], l[3], 16.65, l[4], ORANGE, NEON, false)
		for k = 0, 3 do
			local t0, t1 = k / 4, (k + 1) / 4
			if i <= 2 then
				glow(f, "CoveLip", l[1] + (l[3] - l[1]) * t0, 14.9, l[2], l[1] + (l[3] - l[1]) * t1, 15.3, l[4], RED, 0.9, 20)
			else
				glow(f, "CoveLip", l[1], 14.9, l[2] + (l[4] - l[2]) * t0, l[3], 15.3, l[2] + (l[4] - l[2]) * t1, RED, 0.9, 20)
			end
		end
	end

	-- segmented elliptical cove tray: red outer ring, orange inner ring, dark fascia up to the ceiling
	for _, r in ipairs({ { 46, 42, 16.2, RED, 4 }, { 30, 27, 17.1, ORANGE, 7 } }) do
		for i = 0, 27 do
			local a0, a1 = i * math.pi / 14, (i + 1) * math.pi / 14
			local x0, z0, x1, z1 = CX + r[1] * math.cos(a0), r[2] * math.sin(a0), CX + r[1] * math.cos(a1), r[2] * math.sin(a1)
			local mx, mz, dx, dz = (x0 + x1) / 2, (z0 + z1) / 2, x1 - x0, z1 - z0
			local len, rot = math.sqrt(dx * dx + dz * dz) / 2 + 0.15, CFrame.Angles(0, math.atan(-dz, dx), 0)
			local fascia = b("CoveFascia", mx - len, r[3] + 0.35, mz - 0.35, mx + len, H, mz + 0.35, SOFFIT, SP, false)
			local tube = b("CoveTube", mx - len, r[3], mz - 0.2, mx + len, r[3] + 0.35, mz + 0.2, r[4], NEON, false)
			for _, p in ipairs({ fascia, tube }) do p.CFrame = p.CFrame * rot end
			if i % r[5] == 0 then glow(f, "CoveLight", mx - 0.5, r[3] - 0.1, mz - 0.5, mx + 0.5, r[3] + 0.3, mz + 0.5, r[4], 1, 24) end
		end
	end

	-- four thick red columns flanking the clear centre aisle
	for _, x in ipairs({ 680, 730 }) do
		for _, z in ipairs({ -24, 24 }) do
			round("ColumnBase", x, z, 6.8, 0, 1, DARK)
			round("Column", x, z, 5.6, 1, 16.8, COL)
			round("ColumnGlowRing", x, z, 5.9, 13.2, 13.5, ORANGE, NEON, false)
			round("ColumnCap", x, z, 6.8, 16.8, H, SOFFIT)
		end
	end

	-- six tall round standing tables (5.5-stud tops) kept off the aisle, recesses and counter queue
	for _, t in ipairs({ { 656, -40 }, { 705, -36 }, { 752, -40 }, { 658, 38 }, { 705, 36 }, { 752, 38 } }) do
		round("TableFoot", t[1], t[2], 3, 0, 0.3, CHROME, METAL)
		b("TableStem", t[1] - 0.3, 0.3, t[2] - 0.3, t[1] + 0.3, 5.2, t[2] + 0.3, CHROME, METAL)
		round("TableRim", t[1], t[2], 5.7, 5.2, 5.35, COL)
		round("TableTop", t[1], t[2], 5.5, 5.3, 5.6, TOP)
	end

	-- concession on +Z: long blank red counter, dark top, glowing trim, back counter, blank dark boards
	b("Counter", 672, 0, 50, 738, 3.8, 55, COL)
	b("CounterTop", 671.5, 3.8, 49.5, 738.5, 4.2, 55.5, TOP)
	b("CounterTrim", 672, 3.3, 49.8, 738, 3.55, 50, AMBER, NEON, false)
	glow(f, "CounterToeGlow", 672, 0.2, 49.7, 738, 0.5, 50, ORANGE, 0.8, 16)
	b("BackCounter", 666, 0, 66, 744, 3.6, 70, COL)
	b("BackCounterTop", 666, 3.6, 65.6, 744, 3.9, 70, TOP)
	for i = 0, 2 do
		b("BlankBoard", 672 + i * 22.5, 7.5, 69.6, 692 + i * 22.5, 12.5, 70, LEAF)
		b("BlankBoardEdge", 672 + i * 22.5, 12.5, 69.5, 692 + i * 22.5, 12.75, 70, RED, NEON, false)
	end

	-- genuinely empty framed glass popcorn cabinet on the counter: bare deck, hanging kettle, warm lamp
	local x0, x1, z0, z1, y0, y1 = 682, 690, 50.6, 54.8, 5.4, 11
	b("PopperBase", x0, 4.2, z0, x1, y0, z1, COL)
	b("PopperDeck", x0 + 0.3, y0, z0 + 0.3, x1 - 0.3, y0 + 0.1, z1 - 0.3, CHROME, METAL)
	b("PopperRoof", x0 - 0.2, y1, z0 - 0.2, x1 + 0.2, y1 + 0.9, z1 + 0.2, COL)
	for _, c in ipairs({ { x0, z0 }, { x1 - 0.3, z0 }, { x0, z1 - 0.3 }, { x1 - 0.3, z1 - 0.3 } }) do b("PopperPost", c[1], y0, c[2], c[1] + 0.3, y1, c[2] + 0.3, CHROME, METAL) end
	for _, p in ipairs({ { x0 + 0.3, z0, x1 - 0.3, z0 + 0.1 }, { x0 + 0.3, z1 - 0.1, x1 - 0.3, z1 }, { x0, z0 + 0.3, x0 + 0.1, z1 - 0.3 }, { x1 - 0.1, z0 + 0.3, x1, z1 - 0.3 } }) do
		local g = b("PopperGlass", p[1], y0, p[2], p[3], y1, p[4], GLASS, Enum.Material.Glass)
		if g then g.Transparency = 0.75 end
	end
	b("KettleRod", 685.85, 9.4, 52.55, 686.15, y1, 52.85, CHROME, METAL, false)
	round("Kettle", 686, 52.7, 2.2, 8.4, 9.4, CHROME, METAL, false)
	glow(f, "PopperLamp", x0 + 1, y1 - 0.3, z0 + 0.4, x1 - 1, y1 - 0.1, z0 + 0.7, AMBER, 0.7, 10)

	-- two dark auditorium entry recesses in the south facing (decor; the outer wall behind stays solid)
	for _, c in ipairs({ 675, 735 }) do
		b("RecessBack", c - 8, 0, -70, c + 8, 11, -69.8, DARK)
		b("RecessLining", c - 8, 10.7, -70, c + 8, 11, -67, DARK)
		for s = -1, 1, 2 do
			b("RecessJamb", c + s * 7.6, 0, -69.8, c + s * 8, 11, -67, DARK)
			b("RecessLeaf", c + s * 0.15, 0, -69.8, c + s * 6.8, 10, -69.6, LEAF)
		end
		glow(f, "RecessGlow", c - 5, 10.45, -68.9, c + 5, 10.7, -68.5, RED, 0.5, 11)
	end
end

local function buildFork(root, ids)
	local f = Instance.new("Folder")
	f.Name = "Fork"
	f.Parent = root
	local cid = ids and (ids.ForkCarpet or ids.SwirlCarpet)
	if type(cid) == "number" then cid = "rbxassetid://" .. cid end
	if type(cid) ~= "string" or cid == "" then cid = "rbxassetid://80407060064074" end
	local SMOOTH, NEON, METAL = Enum.Material.SmoothPlastic, Enum.Material.Neon, Enum.Material.Metal
	local ORANGE = Color3.fromRGB(206, 92, 30)
	local DIM = Color3.fromRGB(140, 52, 12)
	local DARK = Color3.fromRGB(18, 15, 17)
	local PILLAR = Color3.fromRGB(44, 26, 24)
	local TRIM = Color3.fromRGB(58, 54, 56)
	local WARM = Color3.fromRGB(255, 226, 184)
	local COVE = { Color3.fromRGB(255, 48, 196), Color3.fromRGB(40, 228, 255), Color3.fromRGB(56, 90, 255), WARM }

	-- Walkable swirl carpet: central corridor plus both theater branches (contiguous at z = +/-15).
	carpet(f, "CorridorCarpet", 770, -15, 1045, 15, cid, 18)
	carpet(f, "BranchACarpet", 905, -35, 935, -15, cid, 18)
	carpet(f, "BranchBCarpet", 905, 15, 935, 35, cid, 18)

	-- Flat dark ceiling at y22; stops exactly at the x770 / x1045 / z+/-35 door planes, never across them.
	box(f, "CorridorCeiling", 770, 22, -16, 1045, 23, 16, DARK, SMOOTH)
	box(f, "BranchACeiling", 904, 22, -35, 936, 23, -16, DARK, SMOOTH)
	box(f, "BranchBCeiling", 904, 22, 16, 936, 23, 35, DARK, SMOOTH)

	-- (along, across) spans -> x0, z0, x1, z1 for walls running along x (alongX) or along z.
	local function xz(alongX, a0, a1, b0, b1)
		if alongX then return a0, b0, a1, b1 end
		return b0, a0, b1, a1
	end
	-- Ordered span of depth d starting at face c and extending toward sign s.
	local function span(c, s, d)
		if s > 0 then return c, c + d end
		return c - d, c
	end

	-- Orange wall a0..a1 with inner face at c facing s: baseboard, dim neon band, cove lip and colored cove.
	local function wall(name, alongX, a0, a1, c, s, phase)
		local x0, z0, x1, z1 = xz(alongX, a0, a1, span(c, -s, 1))
		box(f, name, x0, 0, z0, x1, 22, z1, ORANGE, SMOOTH)
		x0, z0, x1, z1 = xz(alongX, a0, a1, span(c, s, 0.2))
		box(f, name .. "Base", x0, 0, z0, x1, 0.8, z1, DARK, SMOOTH, false)
		box(f, name .. "Band", x0, 9, z0, x1, 9.6, z1, DIM, NEON, false)
		x0, z0, x1, z1 = xz(alongX, a0, a1, span(c, s, 1.4))
		box(f, name .. "CoveLip", x0, 18.6, z0, x1, 19, z1, DARK, SMOOTH, false)
		local n = math.max(1, math.floor((a1 - a0) / 27 + 0.5))
		for i = 0, n - 1 do
			x0, z0, x1, z1 = xz(alongX, a0 + (a1 - a0) * i / n, a0 + (a1 - a0) * (i + 1) / n, span(c, s, 0.6))
			glow(f, name .. "Cove" .. i, x0, 19, z0, x1, 19.4, z1, COVE[(i + phase) % #COVE + 1], 1.2, 16)
		end
	end

	-- Corridor walls break at x905..935 for the branches; ends at x770 / x1045 stay fully open.
	for _, w in ipairs({
		{ "WallN1", true, 770, 905, -15, 1, 0 },
		{ "WallN2", true, 935, 1045, -15, 1, 1 },
		{ "WallS1", true, 770, 905, 15, -1, 0 },
		{ "WallS2a", true, 935, 985, 15, -1, 1 },
		{ "WallS2b", true, 997, 1045, 15, -1, 1 },
		{ "BranchAWallW", false, -35, -16, 905, 1, 2 },
		{ "BranchAWallE", false, -35, -16, 935, -1, 3 },
		{ "BranchBWallW", false, 16, 35, 905, 1, 2 },
		{ "BranchBWallE", false, 16, 35, 935, -1, 3 },
	}) do
		wall(table.unpack(w))
	end

	-- Square pillars engaged in the side walls (|z| >= 12.6), flanking the branch mouths, clear of all doors.
	for i, x in ipairs({ 790, 830, 870, 903.7, 936.3, 975, 1015 }) do
		for _, s in ipairs({ -1, 1 }) do
			local tag = "Pillar" .. i .. (s < 0 and "N" or "S")
			local z0, z1 = span(16 * s, -s, 3.4)
			box(f, tag, x - 1.3, 0, z0, x + 1.3, 22, z1, PILLAR, SMOOTH)
			z0, z1 = span(16 * s, -s, 3.5)
			box(f, tag .. "Band", x - 1.4, 9, z0, x + 1.4, 9.6, z1, DIM, NEON, false)
		end
	end

	-- Recessed warm downlights: two rows down the corridor plus one per branch.
	local spots = { { 920, -25 }, { 920, 25 } }
	for x = 785, 1025, 30 do
		table.insert(spots, { x, -7 })
		table.insert(spots, { x, 7 })
	end
	for i, p in ipairs(spots) do
		local x, z = p[1], p[2]
		box(f, "DownlightTrim" .. i, x - 1.3, 21.9, z - 1.3, x + 1.3, 22, z + 1.3, TRIM, METAL, false)
		glow(f, "Downlight" .. i, x - 0.8, 21.85, z - 0.8, x + 0.8, 21.95, z + 0.8, WARM, 1.4, 26)
	end
end

local HALL_ORIGIN = CFrame.new(23000, 24, 0)
local RED_CARPET = "92732673815453"
-- Only the three verified older carpet uploads: { StudsPerTile, fallback colour }.
local APPROVED_CARPETS = {
	[RED_CARPET] = { 12, Color3.fromRGB(128, 20, 16) },
	["80407060064074"] = { 18, Color3.fromRGB(104, 38, 40) },
	["85044000846144"] = { 12, Color3.fromRGB(62, 26, 84) },
}

local function buildAuditorium(root: Instance, spec: { [string]: any }): Folder
	local fx, fz = spec.forwardX, spec.forwardZ
	assert(fx * fz == 0 and math.abs(fx) + math.abs(fz) == 1, "forward must be a cardinal unit vector")
	local W, D = spec.halfWidth or 90, spec.depth or 190
	local wx, wz = -fz, fx -- width axis, perpendicular to forward
	local H, BASE, DOOR, DOOR_H = 30, -8, 12, 14
	local V0, T, STAGE_V = 22, 14, D - 20 -- rear landing depth, tier depth, stage front
	local AISLE = W - 15 -- inner edge of the 14-stud side aisles
	local P = (AISLE - 15) / 6 -- seat pitch: two 6-seat blocks between center and side aisles
	local wall, seat, accent = spec.wallColor, spec.seatColor, spec.accentColor
	local dark, black = wall:Lerp(Color3.new(), 0.55), Color3.fromRGB(14, 11, 13)
	local FABRIC, PLASTIC, NEON = Enum.Material.Fabric, Enum.Material.SmoothPlastic, Enum.Material.Neon

	local cid = tostring(spec.carpetId or ""):match("%d+")
	if not APPROVED_CARPETS[cid] then
		cid = RED_CARPET
	end
	local carpetId, tile, carpetColor = "rbxassetid://" .. cid, APPROVED_CARPETS[cid][1], APPROVED_CARPETS[cid][2]

	local folder = Instance.new("Folder")
	folder.Name = spec.name
	folder.Parent = root

	local function at(u: number, v: number): (number, number)
		return spec.rearX + u * wx + v * fx, spec.rearZ + u * wz + v * fz
	end
	-- Local rectangle -> ORIGIN-local extents for `make` (box or glow); extra args pass through.
	local function rect(make, name: string, u0: number, v0: number, u1: number, v1: number, y0: number, y1: number, ...)
		local ax, az = at(u0, v0)
		local bx, bz = at(u1, v1)
		return make(folder, name, math.min(ax, bx), y0, math.min(az, bz), math.max(ax, bx), y1, math.max(az, bz), ...)
	end
	local function floorStrip(name: string, v0: number, v1: number, top: number)
		local p = rect(box, name, -(W - 1), v0, W - 1, v1, BASE, top, carpetColor, FABRIC)
		local t = Instance.new("Texture")
		t.Texture, t.Face, t.StudsPerTileU, t.StudsPerTileV = carpetId, Enum.NormalId.Top, tile, tile
		t.Parent = p
	end

	-- Shell: side walls, rear wall split around a real Â±DOOR opening, black front wall, ceiling.
	for _, s in { -1, 1 } do
		rect(box, "SideWall", s * (W - 1), 0, s * W, D, BASE, H, wall, FABRIC)
		if spec.name == "AuditoriumB_Teal" and s == -1 then
			rect(box, "RearWall", -DOOR, 0, -59, 1, BASE, H, wall, FABRIC)
			rect(box, "RearWall", -85, 0, -W, 1, BASE, H, wall, FABRIC)
			rect(box, "WindowSill", -85, 0, -59, 1, BASE, 7, wall, FABRIC)
			rect(box, "WindowHeader", -85, 0, -59, 1, 14, H, wall, FABRIC)
			local glass = rect(box, "BoothViewGlass", -85, 0, -59, 1, 7, 14,
				Color3.fromRGB(155, 198, 210), Enum.Material.Glass, false)
			glass.Transparency = 0.65
		else
			rect(box, "RearWall", s * DOOR, 0, s * W, 1, BASE, H, wall, FABRIC)
		end
		rect(box, "DoorJamb", s * DOOR, 1, s * (DOOR + 1.2), 1.3, 0, DOOR_H + 1, dark, Enum.Material.Wood, false)
		if not (spec.name == "AuditoriumB_Teal" and s == -1) then
			rect(box, "RearPanel", s * (DOOR + 6), 1, s * (AISLE - 4), 1.4, 5, 25, wall:Lerp(Color3.new(), 0.3), FABRIC)
		end
		rect(box, "Wainscot", s * (W - 1.4), 1, s * (W - 1), D - 1, BASE, 2, dark, PLASTIC)
		rect(box, "CoveLine", s * (W - 1.6), 1, s * (W - 1), D - 1, 27.6, 28, accent, NEON, false)
		rect(box, "Drape", s * 64, D - 4, s * 74, D - 1.6, -3.5, H, dark, FABRIC)
	end
	rect(box, "DoorHeader", -DOOR, 0, DOOR, 1, DOOR_H, H, wall, FABRIC)
	rect(box, "DoorHeaderTrim", -DOOR - 1.2, 1, DOOR + 1.2, 1.3, DOOR_H, DOOR_H + 1, dark, Enum.Material.Wood, false)
	rect(box, "FrontWall", -W, D - 1, W, D, BASE, H, black, PLASTIC)
	rect(box, "Ceiling", -W, 0, W, D, H, H + 1, Color3.fromRGB(18, 14, 18), PLASTIC)

	-- Rear cross-aisle at y0, flush with the corridor straight through the door opening.
	local lx0, lz0 = at(-(W - 1), 0)
	local lx1, lz1 = at(W - 1, V0)
	carpet(folder, "EntryLanding", math.min(lx0, lx1), math.min(lz0, lz1), math.max(lx0, lx1), math.max(lz0, lz1), carpetId, tile)
	rect(box, "EntryLandingFill", -(W - 1), 0, W - 1, V0, BASE, -0.1, carpetColor, FABRIC)

	-- Ten full-width tier strips stepping DOWN 0.6 toward the screen; the side aisles ride
	-- the same flat steps (accent step lights on each nosing), seats leave center/sides clear.
	for k = 1, 10 do
		local v0, top = V0 + (k - 1) * T, -0.6 * k
		floorStrip("Tier" .. k, v0, if k == 10 then STAGE_V else v0 + T, top)
		for _, s in { -1, 1 } do
			rect(box, "AisleStepLight", s * AISLE, v0 - 0.35, s * (W - 1), v0, top + 0.6, top + 0.66, accent, NEON, false)
			for j = 0, 5 do
				local c = s * (15 + P / 2 + j * P)
				rect(box, "SeatBack", c - 0.38 * P, v0 + 1, c + 0.38 * P, v0 + 2.2, top + 0.8, top + 5.2, seat, FABRIC)
				rect(box, "SeatCushion", c - 0.38 * P, v0 + 2.2, c + 0.38 * P, v0 + 5.6, top + 1.2, top + 2.1, seat, FABRIC)
				rect(box, "SeatArm", c - s * P / 2 - 0.6, v0 + 1, c - s * P / 2 + 0.6, v0 + 5.4, top, top + 3.2, black, PLASTIC)
			end
		end
	end

	-- Acoustic bays: fabric panels between dark pilasters, a warm sconce on each pilaster.
	local bay = (STAGE_V - V0 - 4) / 6
	for i = 0, 6 do
		local v = V0 + 4 + i * bay
		for _, s in { -1, 1 } do
			rect(box, "Pilaster", s * (W - 2.4), v - 1, s * (W - 1), v + 1, BASE, H, dark, PLASTIC)
			rect(glow, "Sconce", s * (W - 3), v - 0.7, s * (W - 2.4), v + 0.7, 14, 16.5, Color3.fromRGB(255, 186, 120))
			if i < 6 then
				rect(box, "AcousticPanel", s * (W - 1.6), v + 1.4, s * (W - 1), v + bay - 1.4, 3.5, 25.5, wall:Lerp(Color3.new(), 0.3), FABRIC)
			end
		end
	end

	-- Sparse ceiling downlights.
	for _, u in { -W / 2, 0, W / 2 } do
		for _, v in { D * 0.34, D * 0.7 } do
			rect(glow, "Downlight", u - 1.2, v - 1.2, u + 1.2, v + 1.2, H - 0.3, H, Color3.fromRGB(255, 220, 170))
		end
	end

	-- Huge blank off-white screen above a low stage that sits below the entrance floor.
	rect(box, "Screen", -64, D - 2, 64, D - 1.6, 0, 27, Color3.fromRGB(236, 232, 220), PLASTIC)
	rect(box, "Stage", -74, STAGE_V, 74, D - 1, BASE, -5.5, Color3.fromRGB(36, 24, 22), Enum.Material.Wood)

	-- Rear-center camera marker looking at the screen.
	local cx, cz = at(0, 4)
	local tx, tz = at(0, D)
	local cam = rect(box, "Camera_" .. spec.name, -0.5, 3.5, 0.5, 4.5, 8.5, 9.5, black, PLASTIC, false)
	cam.Transparency, cam.CanQuery, cam.CanTouch, cam.CastShadow = 1, false, false, false
	cam.CFrame = HALL_ORIGIN * CFrame.lookAt(Vector3.new(cx, 9, cz), Vector3.new(tx, 12, tz))
	return folder
end

local function buildBooth(root, ids)
	local f = Instance.new("Folder")
	f.Name = "ProjectionBooth"
	f.Parent = root
	local dark = Color3.fromRGB(32, 25, 32)
	local trim = Color3.fromRGB(82, 52, 45)
	local glass = Color3.fromRGB(155, 198, 210)
	carpet(f, "BoothCarpet", 975, 15, 1035, 35, ids.Ring or RING, 12)
	box(f, "BoothCeiling", 975, 16, 16, 1035, 16.8, 35, dark, Enum.Material.SmoothPlastic)
	box(f, "BoothWallWest", 975, 0, 16, 976, 16, 35, dark, Enum.Material.SmoothPlastic)
	box(f, "BoothWallEast", 1034, 0, 16, 1035, 16, 35, dark, Enum.Material.SmoothPlastic)
	box(f, "BoothEntryLeft", 975, 0, 16, 985, 16, 17, dark, Enum.Material.SmoothPlastic)
	box(f, "BoothEntryRight", 997, 0, 16, 1035, 16, 17, dark, Enum.Material.SmoothPlastic)
	box(f, "BoothEntryHeader", 985, 11, 16, 997, 16, 17, dark, Enum.Material.SmoothPlastic)
	box(f, "BoothRearLeft", 975, 0, 34, 979, 16, 35, dark, Enum.Material.SmoothPlastic)
	box(f, "BoothRearRight", 1005, 0, 34, 1035, 16, 35, dark, Enum.Material.SmoothPlastic)
	box(f, "BoothWindowSill", 979, 0, 34, 1005, 7, 35, dark, Enum.Material.SmoothPlastic)
	box(f, "BoothWindowHeader", 979, 14, 34, 1005, 16, 35, dark, Enum.Material.SmoothPlastic)
	local window = box(f, "ProjectionWindow", 979, 7, 34.3, 1005, 14, 34.45, glass, Enum.Material.Glass, false)
	window.Transparency = 0.65
	for _, x in {987, 997} do
		box(f, "ProjectorBody", x - 2, 3, 26, x + 2, 6, 30, trim, Enum.Material.Metal)
		box(f, "ProjectorLens", x - 0.8, 4, 30, x + 0.8, 5.4, 31, Color3.fromRGB(230, 208, 150), Enum.Material.Glass, false)
	end
	glow(f, "BoothLamp", 987, 15.5, 23, 990, 15.8, 26, Color3.fromRGB(245, 185, 125), 0.5, 18)
	marker(f, "Camera9_ProjectionBooth", Vector3.new(1018, 6, 23), Vector3.new(992, 10, 35), 68)
end

-- Finish the image reference composition without replacing the existing preview.
local function polishGeometry(extension)
	if extension:GetAttribute("PolishedV2") == true then return end
	local foyer = assert(extension:FindFirstChild("Foyer"), "foyer missing")
	local fork = assert(extension:FindFirstChild("Fork"), "fork missing")
	local halls = {
		{ name = "AuditoriumA_Red", rearX = 920, rearZ = -35, fx = 0, fz = -1,
			seat = Color3.fromRGB(130, 20, 28), accent = Color3.fromRGB(255, 75, 35) },
		{ name = "AuditoriumB_Teal", rearX = 920, rearZ = 35, fx = 0, fz = 1,
			seat = Color3.fromRGB(18, 92, 101), accent = Color3.fromRGB(80, 230, 245) },
		{ name = "AuditoriumC_Burgundy", rearX = 1045, rearZ = 0, fx = 1, fz = 0,
			seat = Color3.fromRGB(92, 25, 48), accent = Color3.fromRGB(255, 170, 60) },
	}
	local oldCenters, newCenters = {20, 30, 40, 50, 60, 70}, {4, 12, 20, 28, 36, 58}
	for _, spec in halls do
		local hall = assert(extension:FindFirstChild(spec.name), spec.name .. " missing")
		local backs, cushions, arms = 0, 0, 0
		for _, p in hall:GetChildren() do
			if p:IsA("BasePart") then
				if p.Name == "SeatBack" then backs += 1 end
				if p.Name == "SeatCushion" then cushions += 1 end
				if p.Name == "SeatArm" then arms += 1 end
			end
		end
		if backs ~= 120 or cushions ~= 120 or arms ~= 120 then
			error(spec.name .. " seat baseline changed")
		end
	end

	for _, spec in halls do
		local hall = extension:FindFirstChild(spec.name)
		local wx, wz = -spec.fz, spec.fx
		local function xy(u, v)
			return spec.rearX + u * wx + v * spec.fx, spec.rearZ + u * wz + v * spec.fz
		end
		local function hallBox(name, u0, v0, u1, v1, y0, y1, color, material, collide)
			local x0, z0 = xy(u0, v0)
			local x1, z1 = xy(u1, v1)
			return box(hall, name, x0, y0, z0, x1, y1, z1, color, material, collide)
		end
		for _, p in hall:GetChildren() do
			if p:IsA("BasePart") and (p.Name == "SeatBack" or p.Name == "SeatCushion" or p.Name == "SeatArm") then
				local pos = ORIGIN:PointToObjectSpace(p.Position)
				local u = (pos.X - spec.rearX) * wx + (pos.Z - spec.rearZ) * wz
				local arm = p.Name == "SeatArm"
				local oldAbs = math.abs(u) + (if arm then 5 else 0)
				local index = math.floor((oldAbs - 20) / 10 + 0.5) + 1
				if not oldCenters[index] or math.abs(oldAbs - oldCenters[index]) > 0.1 then
					error("unexpected " .. p.Name .. " position in " .. spec.name)
				end
				local targetAbs = newCenters[index] + (if arm then 3.4 else 0)
				local delta = (if u < 0 then -1 else 1) * (targetAbs - math.abs(u))
				p.CFrame = p.CFrame + Vector3.new(delta * wx, 0, delta * wz)
			end
		end
		local black = Color3.fromRGB(14, 11, 13)
		for k = 1, 10 do
			local v0, top = 22 + (k - 1) * 14, -0.6 * k
			for _, sign in {-1, 1} do
				for _, absU in {67, 76} do
					local c = sign * absU
					hallBox("SeatBack", c - 3.3, v0 + 1, c + 3.3, v0 + 2.2,
						top + 0.8, top + 5.2, spec.seat, Enum.Material.Fabric)
					hallBox("SeatCushion", c - 3.3, v0 + 2.2, c + 3.3, v0 + 5.6,
						top + 1.2, top + 2.1, spec.seat, Enum.Material.Fabric)
					local armU = sign * (absU + 3.4)
					hallBox("SeatArm", armU - 0.6, v0 + 1, armU + 0.6, v0 + 5.4,
						top, top + 3.2, black, Enum.Material.SmoothPlastic)
				end
				hallBox("AisleInteriorLight", sign * 42, v0 - 0.35, sign * 54, v0,
					top + 0.6, top + 0.66, spec.accent, Enum.Material.Neon, false)
			end
		end
		hallBox("FrontCove", -88, 184, 88, 185, 27.8, 28.2,
			spec.accent, Enum.Material.Neon, false)
		if spec.name == "AuditoriumB_Teal" then
			hallBox("FrontCoveMagenta", -88, 184, 88, 185, 27.2, 27.5,
				Color3.fromRGB(240, 50, 205), Enum.Material.Neon, false)
		end
		local ceiling = hall:FindFirstChild("Ceiling")
		if ceiling then ceiling.Material = Enum.Material.Fabric; ceiling.Color = Color3.fromRGB(8, 5, 8) end
		local screen = hall:FindFirstChild("Screen")
		if screen then screen.Color = Color3.fromRGB(230, 215, 198) end
	end

	for _, p in fork:GetChildren() do
		if p:IsA("BasePart") then
			if p.Name:match("Wall.*Band$") then
				p.Material = Enum.Material.SmoothPlastic
				p.Color = Color3.fromRGB(88, 34, 29)
			elseif p.Name:match("Cove%d+$") and p:FindFirstChildOfClass("PointLight") then
				local inward
				if p.Name:match("^WallN") then inward = Vector3.new(0, 0, 1)
				elseif p.Name:match("^WallS") then inward = Vector3.new(0, 0, -1)
				elseif p.Name:find("WallW", 1, true) then inward = Vector3.new(1, 0, 0)
				else inward = Vector3.new(-1, 0, 0) end
				p.CFrame = p.CFrame + inward * 1.5 + Vector3.new(0, -0.6, 0)
				for j, color in {Color3.fromRGB(255, 45, 200), Color3.fromRGB(35, 225, 245), Color3.fromRGB(225, 215, 255)} do
					local stripe = Instance.new("Part")
					stripe.Name = "CoveStripe" .. j
					stripe.Anchored = true
					stripe.Size = Vector3.new(p.Size.X, 0.13, p.Size.Z)
					stripe.CFrame = p.CFrame * CFrame.new(0, -0.35 * j, 0)
					stripe.Color = color
					stripe.Material = Enum.Material.Neon
					stripe.CanCollide = false
					stripe.CanTouch = false
					stripe.CastShadow = false
					stripe.Parent = fork
				end
			end
		end
	end
	local foyerCeiling = foyer:FindFirstChild("FoyerCeiling")
	if foyerCeiling then foyerCeiling.Material = Enum.Material.Fabric end
	for _, p in foyer:GetChildren() do
		if p:IsA("BasePart") and p.Name == "ColumnGlowRing" then
			local light = Instance.new("PointLight")
			light.Color = Color3.fromRGB(255, 76, 28)
			light.Brightness = 1.4
			light.Range = 30
			light.Shadows = false
			light.Parent = p
		end
	end
	marker(foyer, "Camera5_ExpansionFoyer", Vector3.new(650, 7, 46), Vector3.new(720, 8, -10), 68)
	marker(fork, "Camera6_NeonFork", Vector3.new(785, 7, 0), Vector3.new(925, 7, 0), 70)
	extension:SetAttribute("PolishedV2", true)
end

local function finishLighting(extension)
	if extension:GetAttribute("ColorPolished") == true then return end
	for _, spec in {
		{ name = "AuditoriumA_Red", color = Color3.fromRGB(255, 125, 65), eye = Vector3.new(920, 14, -44), target = Vector3.new(920, 9, -185) },
		{ name = "AuditoriumB_Teal", color = Color3.fromRGB(80, 210, 225), eye = Vector3.new(920, 14, 44), target = Vector3.new(920, 9, 185) },
		{ name = "AuditoriumC_Burgundy", color = Color3.fromRGB(255, 165, 80), eye = Vector3.new(1054, 14, 0), target = Vector3.new(1185, 9, 0) },
	} do
		local hall = assert(extension:FindFirstChild(spec.name))
		for _, p in hall:GetChildren() do
			if p:IsA("BasePart") and p.Name == "Sconce" then
				p.Color = spec.color
				local light = p:FindFirstChildOfClass("PointLight")
				if light then
					light.Color = spec.color
					light.Brightness = 1.1
					light.Range = 25
				end
			end
		end
		local camera = hall:FindFirstChild("Camera_" .. spec.name)
		if camera and camera:IsA("BasePart") then
			camera.CFrame = ORIGIN * CFrame.lookAt(spec.eye, spec.target)
			camera:SetAttribute("FieldOfView", 62)
		end
	end
	extension:SetAttribute("ColorPolished", true)
end

local function exitWall(model)
	local lobby = model:FindFirstChild("TealBoxOfficeLobby")
	local wall = lobby and lobby:FindFirstChild("ExitHall_Back")
	if not (wall and wall:IsA("BasePart")) then return nil end
	if (wall.Position - Vector3.new(23608.5, 29.5, 0)).Magnitude > 0.01
		or (wall.Size - Vector3.new(1, 11, 22)).Magnitude > 0.01 then return nil end
	return wall
end

function Expansion.Polish(model)
	if typeof(model) ~= "Instance" or not model:IsA("Model") or model.Name ~= MODEL_NAME
		or model:GetAttribute("Level4Preview") ~= true or model:GetAttribute("PreviewOnly") ~= true then
		return nil, "not the Level 4 preview"
	end
	local extension = model:FindFirstChild(EXTENSION_NAME)
	local wall = exitWall(model)
	if not (extension and extension:IsA("Model") and extension:GetAttribute("Complete") == true)
		or not wall or wall.Transparency ~= 1 or wall.CanCollide then
		return nil, "preview expansion changed"
	end
	if extension:GetAttribute("PolishedV2") ~= true then
		local ok, err = pcall(polishGeometry, extension)
		if not ok then return nil, tostring(err) end
	end
	if extension:GetAttribute("ColorPolished") ~= true then
		local ok, err = pcall(finishLighting, extension)
		if not ok then return nil, tostring(err) end
	end
	local parts, lights = counts(model)
	if parts > 5000 or lights > 220 then return nil, "polished geometry exceeds budget" end
	model:SetAttribute("PartCount", parts)
	model:SetAttribute("LightCount", lights)
	return extension
end

function Expansion.Append(model, textureIds)
	if typeof(model) ~= "Instance" or not model:IsA("Model") or model.Name ~= MODEL_NAME
		or model:GetAttribute("Level4Preview") ~= true or model:GetAttribute("PreviewOnly") ~= true then
		return nil, "not the Level 4 preview"
	end
	local existing = model:FindFirstChild(EXTENSION_NAME)
	if existing then
		local opened = exitWall(model)
		if existing:IsA("Model") and existing:GetAttribute("Complete") == true
			and opened and opened.Transparency == 1 and not opened.CanCollide then
			return Expansion.Polish(model)
		end
		return nil, "incomplete expansion already exists"
	end
	local wall = exitWall(model)
	if not wall or wall.Transparency ~= 0 or not wall.CanCollide then
		return nil, "ExitHall_Back changed; expansion refused"
	end
	local ids = textureIds or {}
	local extension = Instance.new("Model")
	extension.Name = EXTENSION_NAME
	local ok, err = pcall(function()
		buildConnector(extension, ids)
		buildFoyer(extension, ids)
		buildFork(extension, ids)
		buildAuditorium(extension, {
			name = "AuditoriumA_Red", rearX = 920, rearZ = -35, forwardX = 0, forwardZ = -1,
			halfWidth = 90, depth = 190, wallColor = Color3.fromRGB(100, 18, 22),
			seatColor = Color3.fromRGB(130, 20, 28), accentColor = Color3.fromRGB(255, 75, 35),
			carpetId = ids.Red or RED,
		})
		buildAuditorium(extension, {
			name = "AuditoriumB_Teal", rearX = 920, rearZ = 35, forwardX = 0, forwardZ = 1,
			halfWidth = 90, depth = 190, wallColor = Color3.fromRGB(25, 56, 65),
			seatColor = Color3.fromRGB(18, 92, 101), accentColor = Color3.fromRGB(80, 230, 245),
			carpetId = ids.Ring or RING,
		})
		buildAuditorium(extension, {
			name = "AuditoriumC_Burgundy", rearX = 1045, rearZ = 0, forwardX = 1, forwardZ = 0,
			halfWidth = 90, depth = 190, wallColor = Color3.fromRGB(72, 22, 40),
			seatColor = Color3.fromRGB(92, 25, 48), accentColor = Color3.fromRGB(255, 170, 60),
			carpetId = ids.Swirl or SWIRL,
		})
		buildBooth(extension, ids)
		polishGeometry(extension)
		finishLighting(extension)
	end)
	if not ok then extension:Destroy(); return nil, tostring(err) end
	local addedParts, addedLights = counts(extension)
	local oldParts, oldLights = counts(model)
	if oldParts + addedParts > 5000 or oldLights + addedLights > 220 then
		extension:Destroy()
		return nil, "expansion exceeds part or light budget"
	end
	if model:FindFirstChild(EXTENSION_NAME) or exitWall(model) ~= wall
		or wall.Transparency ~= 0 or not wall.CanCollide then
		extension:Destroy()
		return nil, "preview changed while expansion was building"
	end
	extension:SetAttribute("Complete", true)
	extension.Parent = model
	wall.Transparency = 1
	wall.CanCollide = false
	wall.CastShadow = false
	model:SetAttribute("PartCount", oldParts + addedParts)
	model:SetAttribute("LightCount", oldLights + addedLights)
	return extension
end

function Expansion.SelfCheck(model)
	local issues = {}
	if typeof(model) ~= "Instance" or not model:IsA("Model") then
		return false, {Issues = {"preview model missing"}}
	end
	local extension = model:FindFirstChild(EXTENSION_NAME)
	if not (extension and extension:IsA("Model") and extension:GetAttribute("Complete") == true) then
		table.insert(issues, "completed expansion missing")
	end
	local wall = exitWall(model)
	if not wall or wall.Transparency < 1 or wall.CanCollide then
		table.insert(issues, "ExitHall_Back still blocks the connector")
	end
	local parts, lights = counts(model)
	if parts > 5000 or lights > 220 then table.insert(issues, "geometry budget exceeded") end
	if model:GetAttribute("PartCount") ~= parts or model:GetAttribute("LightCount") ~= lights then
		table.insert(issues, "geometry count attributes are stale")
	end
	if extension then
		if extension:GetAttribute("PolishedV2") ~= true then table.insert(issues, "visual polish missing") end
		if extension:GetAttribute("ColorPolished") ~= true then table.insert(issues, "cinema lighting polish missing") end
		for _, name in {"Connector", "Foyer", "Fork", "AuditoriumA_Red", "AuditoriumB_Teal", "AuditoriumC_Burgundy", "ProjectionBooth"} do
			if not extension:FindFirstChild(name) then table.insert(issues, "missing room " .. name) end
		end
		local tables, screens, seats, popperGlass = 0, 0, 0, 0
		for _, d in extension:GetDescendants() do
			if d:IsA("BasePart") then
				if not d.Anchored then table.insert(issues, "unanchored: " .. d:GetFullName()) end
				if d.Name == "TableTop" then tables += 1 end
				if d.Name == "Screen" then screens += 1 end
				if d.Name == "SeatBack" then seats += 1 end
				if d.Name == "PopperGlass" then popperGlass += 1 end
			end
		end
		if tables ~= 6 or screens ~= 3 or seats ~= 480 or popperGlass ~= 4 then
			table.insert(issues, "foyer or auditorium feature count differs")
		end
		if extension:FindFirstChild("Popcorn", true) then table.insert(issues, "popcorn case is not empty") end
	end
	return #issues == 0, {Issues = issues, PartCount = parts, LightCount = lights}
end

return Expansion
