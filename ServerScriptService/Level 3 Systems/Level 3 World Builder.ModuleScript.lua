-- Level 3 World Builder
-- Turns a Level 3 layout (variable-size halls + corridors) into geometry.
--
-- Shared with Level 2 on purpose, and nothing else: the tile texture asset and
-- the terrain water appearance. Everything structural here is Level 3's own —
-- halls of different footprints, real corridors between them, per-hall ceiling
-- heights, drainable corridors, pump stations, a kids wing, and slide halls
-- whose top decks carry the flumes.

local Terrain = workspace.Terrain

local Configuration = require(script.Parent:WaitForChild("Level 3 Configuration"))

local WorldBuilder = {}
local C = Configuration.Colors

-- The two things Level 3 borrows from Level 2.
local TILE_TEXTURE = "rbxassetid://113211706146395"
local TILE_TINT = Color3.fromRGB(248, 242, 218)

-- ── primitives ──────────────────────────────────────────────────────────────

local function part(parent, name, cframe, size, color, material, transparency)
	local object = Instance.new("Part")
	object.Name = name
	object.Anchored = true
	object.CFrame = cframe
	object.Size = size
	object.Color = color or C.Tile
	object.Material = material or Enum.Material.SmoothPlastic
	object.Transparency = transparency or 0
	object.TopSurface = Enum.SurfaceType.Smooth
	object.BottomSurface = Enum.SurfaceType.Smooth
	object.Parent = parent
	return object
end

local function addTexture(object, faces, studs)
	for _, face in ipairs(faces) do
		local texture = Instance.new("Texture")
		texture.Name = "Level 3 Tile Texture"
		texture.Texture = TILE_TEXTURE
		texture.Face = face
		texture.StudsPerTileU = studs or 7
		texture.StudsPerTileV = studs or 7
		texture.Color3 = TILE_TINT
		texture.Parent = object
	end
	return object
end

local function tiledPart(parent, name, cframe, size, color, faces, studs)
	local object = part(parent, name, cframe, size, color or C.Tile)
	addTexture(object, faces or Enum.NormalId:GetEnumItems(), studs)
	return object
end

local function folder(parent, name)
	local object = Instance.new("Folder")
	object.Name = name
	object.Parent = parent
	return object
end

local function bezier(p0, p1, p2, p3, t)
	local u = 1 - t
	return p0 * (u ^ 3) + p1 * (3 * u * u * t) + p2 * (3 * u * t * t) + p3 * (t ^ 3)
end

local function hallHeight(hall)
	if not hall then return Configuration.WallHeight end
	if hall.IsGrand then return Configuration.GrandSlideHallHeight end
	if hall.Role == "Slide Hall" then return Configuration.SlideHallHeight end
	if hall.Role == "Kids Area" then return Configuration.KidsWallHeight end
	return Configuration.WallHeight
end

local function isKids(hall)
	return hall and hall.Role == "Kids Area"
end

local function kidsPalette(hall)
	local index = hall and hall.KidsColorIndex or 1
	return Configuration.KidsColors[index] or Configuration.KidsColors[1]
end

-- Kids halls are painted, not tiled — that is the "different walls and
-- textures" the design calls for, and it reads instantly on entry.
local function surfaceFor(hall, parent, name, cframe, size, tileColor, faces, studs)
	if isKids(hall) then
		return part(parent, name, cframe, size, kidsPalette(hall).Color, Enum.Material.SmoothPlastic)
	end
	return tiledPart(parent, name, cframe, size, tileColor, faces, studs)
end

-- ── walls ───────────────────────────────────────────────────────────────────

-- A straight wall from `low` to `high` along `axis` at fixed `cross`, with any
-- number of doorway gaps punched through it (one per corridor that lands here).
local function makeWallWithGaps(parent, hall, name, axis, cross, low, high, gaps, height)
	height = height or hallHeight(hall)
	local thickness = Configuration.WallThickness
	local bottomY = -4
	local fullHeight = height - bottomY
	local centerY = (height + bottomY) * .5
	local gapWidth = Configuration.DoorWidth
	local doorHeight = Configuration.DoorHeight
	local wallColor = isKids(hall) and kidsPalette(hall).Color or C.TileCool

	local sorted = table.clone(gaps or {})
	table.sort(sorted)

	local function positionFor(along, y)
		if axis == "X" then return Vector3.new(along, y, cross) end
		return Vector3.new(cross, y, along)
	end
	local function sizeFor(length, tall)
		if axis == "X" then return Vector3.new(length, tall, thickness) end
		return Vector3.new(thickness, tall, length)
	end

	local cursor = low
	for _, gapCenter in ipairs(sorted) do
		local gapLow = math.clamp(gapCenter - gapWidth * .5, low, high)
		local gapHigh = math.clamp(gapCenter + gapWidth * .5, low, high)
		if gapLow - cursor > .1 then
			surfaceFor(hall, parent, name, CFrame.new(positionFor((cursor + gapLow) * .5, centerY)),
				sizeFor(gapLow - cursor, fullHeight), wallColor, nil, 7)
		end
		-- Lintel over the doorway.
		local lintelHeight = height - doorHeight
		if lintelHeight > 0 and gapHigh - gapLow > .1 then
			surfaceFor(hall, parent, name .. " Lintel",
				CFrame.new(positionFor((gapLow + gapHigh) * .5, doorHeight + lintelHeight * .5)),
				sizeFor(gapHigh - gapLow, lintelHeight), wallColor, nil, 7)
		end
		cursor = math.max(cursor, gapHigh)
	end
	if high - cursor > .1 then
		surfaceFor(hall, parent, name, CFrame.new(positionFor((cursor + high) * .5, centerY)),
			sizeFor(high - cursor, fullHeight), wallColor, nil, 7)
	end
end

-- ── floors, ceilings, water ─────────────────────────────────────────────────

local function makeHallFloor(parent, hall)
	local floorColor = isKids(hall) and kidsPalette(hall).Accent or C.TileWarm
	local slab = surfaceFor(hall, parent, "Level 3 Hall Floor",
		CFrame.new(hall.Center + Vector3.new(0, -.35, 0)),
		Vector3.new(hall.Width, .7, hall.Depth), floorColor, {Enum.NormalId.Top}, 7)
	slab.CanCollide = true
	return slab
end

local function makeHallCeiling(parent, hall)
	local height = hallHeight(hall)
	local color = isKids(hall) and kidsPalette(hall).Accent or C.TileCool
	local slab = surfaceFor(hall, parent, "Level 3 Hall Ceiling",
		CFrame.new(hall.Center + Vector3.new(0, height + 1, 0)),
		Vector3.new(hall.Width, 2, hall.Depth), color, {Enum.NormalId.Bottom}, 9)
	slab.CanCollide = true
	return slab
end

-- A sunken tiled basin inside a hall, filled with terrain water.
-- Returns the water block so it can be drained again later.
local function makeBasin(parent, center, width, depth3, poolDepth, label)
	local wallThickness = 4
	local bottomY = -poolDepth
	local wallTop = 1.25
	local wallHeight = wallTop - bottomY
	local wallCenterY = bottomY + wallHeight * .5

	local bottom = tiledPart(parent, "Level 3 " .. label .. " Basin Floor",
		CFrame.new(center + Vector3.new(0, bottomY - .75, 0)),
		Vector3.new(width, 1.5, depth3), C.TileCool, {Enum.NormalId.Top}, 10)
	bottom.CanCollide = true

	for _, data in ipairs({
		{Vector3.new(-width * .5, wallCenterY, 0), Vector3.new(wallThickness, wallHeight, depth3)},
		{Vector3.new(width * .5, wallCenterY, 0), Vector3.new(wallThickness, wallHeight, depth3)},
		{Vector3.new(0, wallCenterY, -depth3 * .5), Vector3.new(width, wallHeight, wallThickness)},
		{Vector3.new(0, wallCenterY, depth3 * .5), Vector3.new(width, wallHeight, wallThickness)},
	}) do
		local wall = tiledPart(parent, "Level 3 " .. label .. " Basin Wall",
			CFrame.new(center + data[1]), data[2], C.TileCool, nil, 10)
		wall.CanCollide = true
	end

	local waterWidth = math.max(4, width - wallThickness * 2 - 2)
	local waterDepth = math.max(4, depth3 - wallThickness * 2 - 2)
	local waterHeight = math.max(.8, poolDepth - .35)
	local waterCFrame = CFrame.new(center + Vector3.new(0, -waterHeight * .5 + .1, 0))
	local waterSize = Vector3.new(waterWidth, waterHeight, waterDepth)
	Terrain:FillBlock(waterCFrame, waterSize, Enum.Material.Water)
	return {CFrame = waterCFrame, Size = waterSize}
end

-- ── set pieces ──────────────────────────────────────────────────────────────

local function makeColumn(parent, position, height, radius)
	radius = radius or 6
	local column = tiledPart(parent, "Level 3 Tiled Column",
		CFrame.new(position + Vector3.new(0, height * .5 - 1, 0)) * CFrame.Angles(0, 0, math.pi * .5),
		Vector3.new(height, radius, radius), C.TileWarm, nil, 9)
	column.Shape = Enum.PartType.Cylinder
	column.CanCollide = true
	return column
end

local function makeArchRing(parent, center, alongX, index, radius)
	radius = radius or 14
	for step = 0, 14 do
		local angle = math.pi * step / 14
		local side = math.cos(angle) * radius
		local y = 1 + math.sin(angle) * radius
		local position = alongX and center + Vector3.new(0, y, side) or center + Vector3.new(side, y, 0)
		local rib = part(parent, "Level 3 Arch Rib " .. index, CFrame.new(position),
			alongX and Vector3.new(2.2, 2.2, 3.6) or Vector3.new(3.6, 2.2, 2.2), C.TileWarm)
		addTexture(rib, Enum.NormalId:GetEnumItems(), 7)
	end
end

local function makeRail(parent, a, b, name)
	local delta = b - a
	local length = delta.Magnitude
	if length < 1 then return end
	local direction = delta.Unit
	local height = 4.2
	local bar = part(parent, name .. " Handrail",
		CFrame.lookAt((a + b) * .5 + Vector3.new(0, height, 0), b + Vector3.new(0, height, 0)),
		Vector3.new(.42, .42, length), C.Rail, Enum.Material.Metal)
	bar.CanCollide = true
	local posts = math.max(2, math.floor(length / 9))
	for index = 0, posts do
		local position = a + direction * (length * index / posts)
		part(parent, name .. " Post " .. index,
			CFrame.new(position + Vector3.new(0, height * .5, 0)),
			Vector3.new(.34, height, .34), C.Rail, Enum.Material.Metal)
	end
end

local function makeStairFlight(parent, base, direction, width, steps, name)
	direction = direction.Unit
	local run = 2.3
	local rise = .78
	for index = 1, steps do
		local height = index * rise
		local center = base + direction * ((index - .5) * run) + Vector3.new(0, height * .5, 0)
		local stair = tiledPart(parent, name .. " Step " .. index,
			CFrame.lookAt(center, center + direction), Vector3.new(width, height, run + .12), C.TileWarm,
			{Enum.NormalId.Top, Enum.NormalId.Front, Enum.NormalId.Back}, 7)
		stair.CanCollide = true
	end
	return steps * run, steps * rise
end

local function makeSpiralStair(parent, center, baseY, topY, radius, name)
	local rise = 1.05
	local steps = math.max(10, math.floor((topY - baseY) / rise))
	local turns = math.max(1.6, (topY - baseY) / 34)
	makeColumn(parent, center + Vector3.new(0, baseY, 0), topY - baseY + 5, 8)
	for index = 0, steps do
		local t = index / steps
		local angle = t * math.pi * 2 * turns
		local y = baseY + t * (topY - baseY)
		local position = center + Vector3.new(math.cos(angle) * radius, y, math.sin(angle) * radius)
		local tread = tiledPart(parent, name .. " Tread " .. index,
			CFrame.new(position) * CFrame.Angles(0, -angle, 0),
			Vector3.new(radius * 1.45, .7, 5.4), C.TileWarm,
			{Enum.NormalId.Top, Enum.NormalId.Front, Enum.NormalId.Back}, 7)
		tread.CanCollide = true
	end
end

local function makeSkylight(parent, center, width, depth3, index, height)
	local slots = math.max(2, math.floor(width / 60))
	for slot = 1, slots do
		local x = -width * .5 + (slot / (slots + 1)) * width
		local pane = part(parent, "Level 3 Skylight Pane " .. index .. " " .. slot,
			CFrame.new(center + Vector3.new(x, height - 1.4, 0)),
			Vector3.new(14, .5, math.max(20, depth3 * .62)), C.Light, Enum.Material.Neon, .05)
		pane.CanCollide = false
		local light = Instance.new("SurfaceLight")
		light.Name = "Level 3 Skylight Surface Light"
		light.Face = Enum.NormalId.Bottom
		light.Color = C.Light
		light.Brightness = Configuration.SkylightBrightness
		light.Range = Configuration.SkylightRange
		light.Angle = 92
		light.Shadows = true
		light.Parent = pane
	end
end

local function makeCeilingPanel(parent, position, index, panelSize, yaw, height)
	local y = (height or Configuration.WallHeight) - .7
	panelSize = panelSize or Vector3.new(30, .55, 9)
	local fixtureCFrame = CFrame.new(position.X, y, position.Z) * CFrame.Angles(0, yaw or 0, 0)
	part(parent, "Level 3 Ceiling Light Frame " .. index, fixtureCFrame, panelSize, C.Metal, Enum.Material.Metal)
	local diffuserSize = Vector3.new(math.max(2, panelSize.X - 3), .18, math.max(2, panelSize.Z - 3))
	local diffuser = part(parent, "Level 3 Ceiling Light Diffuser " .. index,
		fixtureCFrame * CFrame.new(0, -.34, 0), diffuserSize, C.Light, Enum.Material.Neon, .08)
	diffuser.CanCollide = false
	local light = Instance.new("SurfaceLight")
	light.Name = "Level 3 Ceiling Surface Light"
	light.Face = Enum.NormalId.Bottom
	light.Color = C.Light
	light.Brightness = Configuration.CeilingPanelBrightness
	light.Range = Configuration.CeilingPanelRange
	light.Angle = 115
	light.Shadows = false
	light.Parent = diffuser
	return diffuser
end

local function lightHall(parent, hall, index)
	local height = hallHeight(hall)
	local columns = math.clamp(math.floor(hall.Width / 90), 1, 4)
	local rows = math.clamp(math.floor(hall.Depth / 90), 1, 4)
	for cx = 1, columns do
		for cz = 1, rows do
			local x = hall.Center.X - hall.Width * .5 + (cx / (columns + 1)) * hall.Width
			local z = hall.Center.Z - hall.Depth * .5 + (cz / (rows + 1)) * hall.Depth
			makeCeilingPanel(parent, Vector3.new(x, 0, z),
				index .. "." .. cx .. "." .. cz,
				Vector3.new(math.min(46, hall.Width * .42), .55, 9), 0, height)
		end
	end
end

-- ── slides ──────────────────────────────────────────────────────────────────

-- Extruded cubic-bezier flume. `openTop` omits the panels straight overhead so
-- the tube reads as an open water slide from the walkways.
local function makeSlideTube(parent, p0, p1, p2, p3, radius, color, name, segments, openTop)
	segments = segments or Configuration.SlideSegments
	local sides = Configuration.SlideTubeSides
	local arcWidth = 2 * radius * math.sin(math.pi / sides) * 1.18
	for segment = 1, segments do
		local t0, t1 = (segment - 1) / segments, segment / segments
		local a, b = bezier(p0, p1, p2, p3, t0), bezier(p0, p1, p2, p3, t1)
		local length = (b - a).Magnitude
		if length > .05 then
			local base = CFrame.lookAt((a + b) * .5, b, Vector3.yAxis)
			for sideIndex = 0, sides - 1 do
				local angle = sideIndex * math.pi * 2 / sides
				local overhead = math.sin(angle) > .70
				if not (openTop and overhead) then
					local offset = Vector3.new(math.cos(angle) * radius, math.sin(angle) * radius, 0)
					local panel = part(parent, name .. " Panel",
						base * CFrame.new(offset) * CFrame.Angles(0, 0, angle - math.pi * .5),
						Vector3.new(arcWidth, .72, length + 2), color, Enum.Material.SmoothPlastic)
					panel.CustomPhysicalProperties = PhysicalProperties.new(.7, .05, .05, 1, 1)
					panel.CanCollide = true
				end
			end
		end
	end
end

-- A slide hall: deep basin, columns to the roof, a top deck near the ceiling
-- reached by a spiral stair, and colored flumes curving back down to the water.
-- The grand slide hall additionally carries the exit flume.
local function makeSlideHall(parent, hall, index)
	local height = hallHeight(hall)
	local center = hall.Center
	local hallFolder = folder(parent, "Level 3 Slide Hall " .. index)

	local basinWidth = hall.Width - 44
	local basinDepth = hall.Depth - 44
	makeBasin(hallFolder, center, basinWidth, basinDepth, Configuration.DeepPoolDepth, "Slide Hall")

	for _, sx in ipairs({-1, 1}) do
		for _, sz in ipairs({-1, 1}) do
			makeColumn(hallFolder,
				center + Vector3.new(sx * hall.Width * .30, -Configuration.DeepPoolDepth, sz * hall.Depth * .30),
				height + Configuration.DeepPoolDepth, 9)
		end
	end

	-- Top deck along the north edge, up near the ceiling.
	local deckY = height - 22
	local deckDepth = math.min(46, hall.Depth * .3)
	local deckZ = center.Z - hall.Depth * .5 + deckDepth * .5 + 4
	local deck = tiledPart(hallFolder, "Level 3 Slide Hall Deck",
		CFrame.new(Vector3.new(center.X, deckY, deckZ)),
		Vector3.new(hall.Width - 20, 2, deckDepth), C.TileWarm, Enum.NormalId:GetEnumItems(), 8)
	deck.CanCollide = true
	makeRail(hallFolder,
		Vector3.new(center.X - (hall.Width - 24) * .5, deckY + 1, deckZ + deckDepth * .5),
		Vector3.new(center.X + (hall.Width - 24) * .5, deckY + 1, deckZ + deckDepth * .5),
		"Level 3 Slide Hall " .. index .. " Deck")

	makeSpiralStair(hallFolder,
		Vector3.new(center.X + hall.Width * .34, 0, center.Z + hall.Depth * .30),
		-1, deckY, 12, "Level 3 Slide Hall " .. index .. " Spiral")

	for slide = 1, Configuration.SlidesPerHall do
		local spread = (slide - (Configuration.SlidesPerHall + 1) * .5) * math.min(34, hall.Width * .22)
		local color = Configuration.SlideColors[((index + slide - 2) % #Configuration.SlideColors) + 1]
		local start = Vector3.new(center.X + spread, deckY + 4, deckZ + deckDepth * .4)
		local p1 = start + Vector3.new(spread * .4, -14, hall.Depth * .22)
		local p2 = center + Vector3.new(-spread * 1.1, 18, hall.Depth * .06)
		local p3 = center + Vector3.new(spread * .5, 2.5, hall.Depth * .26)
		makeSlideTube(hallFolder, start, p1, p2, p3, Configuration.SlideTubeRadius, color,
			"Level 3 Slide Hall " .. index .. " Flume " .. slide, Configuration.SlideSegments, true)
		local mouth = part(hallFolder, "Level 3 Slide Hall " .. index .. " Flume Mouth " .. slide,
			CFrame.lookAt(start, p1), Vector3.new(Configuration.SlideTubeRadius * 2.4, .8, 3),
			color, Enum.Material.Neon, .35)
		mouth.CanCollide = false
	end

	lightHall(hallFolder, hall, "SlideHall" .. index)
	makeSkylight(hallFolder, center, hall.Width, hall.Depth, "SlideHall" .. index, height)

	return {Folder = hallFolder, DeckY = deckY, DeckZ = deckZ, DeckDepth = deckDepth}
end

-- The exit: a flume leaving the grand slide hall's top deck, running out beyond
-- the complex wall and down into a sealed catch room.
local function makeExitFlume(parent, hall, deck)
	local center = hall.Center
	local outward = Vector3.new(1, 0, 0)
	local start = Vector3.new(center.X + hall.Width * .5 - 14, deck.DeckY + 5, deck.DeckZ)
	local p1 = start + outward * 60 + Vector3.new(0, -6, 0)
	local p2 = start + outward * 140 + Vector3.new(0, -34, 0)
	local p3 = start + outward * 210 + Vector3.new(0, -56, 0)

	makeSlideTube(parent, start, p1, p2, p3, 8, C.TileCool, "Level 3 Exit Flume", 30, false)

	local mouth = part(parent, "Level 3 Exit Flume Mouth", CFrame.lookAt(start, p1),
		Vector3.new(20, 20, 1.4), C.Emergency, Enum.Material.Neon, .55)
	mouth.CanCollide = false

	local catchCenter = p3 + outward * 22 + Vector3.new(0, 6, 0)
	local catchSize = 44
	tiledPart(parent, "Level 3 Exit Catch Floor",
		CFrame.new(catchCenter + Vector3.new(0, -6, 0)),
		Vector3.new(catchSize, 1.5, catchSize), C.TileWarm, {Enum.NormalId.Top}, 9)
	tiledPart(parent, "Level 3 Exit Catch Ceiling",
		CFrame.new(catchCenter + Vector3.new(0, 17, 0)),
		Vector3.new(catchSize, 1.5, catchSize), C.TileCool, {Enum.NormalId.Bottom}, 9)
	for _, data in ipairs({
		{Vector3.new(-catchSize * .5, 5, 0), Vector3.new(1.5, 22, catchSize)},
		{Vector3.new(catchSize * .5, 5, 0), Vector3.new(1.5, 22, catchSize)},
		{Vector3.new(0, 5, -catchSize * .5), Vector3.new(catchSize, 22, 1.5)},
		{Vector3.new(0, 5, catchSize * .5), Vector3.new(catchSize, 22, 1.5)},
	}) do
		tiledPart(parent, "Level 3 Exit Catch Wall", CFrame.new(catchCenter + data[1]), data[2],
			C.TileCool, nil, 9)
	end

	local safeSpawn = part(parent, "Level 3 Exit Safe Spawn",
		CFrame.new(catchCenter + Vector3.new(0, -4, 0)), Vector3.new(7, .4, 7),
		C.Emergency, Enum.Material.Neon, 1)
	safeSpawn.CanCollide = false
	safeSpawn.CanTouch = false

	local trigger = part(parent, "Level 3 Exit Trigger",
		CFrame.new(start + outward * 8), Vector3.new(18, 18, 5),
		C.Emergency, Enum.Material.Neon, 1)
	trigger.CanCollide = false
	trigger.CanTouch = true

	return {Trigger = trigger, SafeSpawn = safeSpawn, Mouth = mouth, EndPosition = catchCenter}
end

-- ── kids wing ───────────────────────────────────────────────────────────────

local function makeKidsHall(parent, hall, index)
	local palette = kidsPalette(hall)
	local center = hall.Center
	local kidsFolder = folder(parent, "Level 3 Kids Room " .. index .. " " .. palette.Name)
	kidsFolder:SetAttribute("Level3_KidsColor", palette.Name)

	local rng = Random.new(hall.LocalSeed or index)
	local blocks = math.clamp(math.floor(hall.Area / 2600), 5, 14)
	for block = 1, blocks do
		local x = rng:NextNumber(-.34, .34) * hall.Width
		local z = rng:NextNumber(-.34, .34) * hall.Depth
		local blockHeight = rng:NextNumber(3, 8)
		local shade = block % 2 == 0 and palette.Accent or palette.Color
		local pad = part(kidsFolder, "Level 3 Soft Play Block " .. block,
			CFrame.new(center + Vector3.new(x, blockHeight * .5, z)) * CFrame.Angles(0, rng:NextNumber() * math.pi, 0),
			Vector3.new(rng:NextNumber(8, 17), blockHeight, rng:NextNumber(8, 17)), shade,
			Enum.Material.SmoothPlastic)
		pad.CanCollide = true
	end

	-- A small kids flume into a ball-pit basin.
	local slideTop = center + Vector3.new(-hall.Width * .26, 12, -hall.Depth * .2)
	local slideEnd = center + Vector3.new(-hall.Width * .26, 1.5, hall.Depth * .1)
	makeStairFlight(kidsFolder, slideTop + Vector3.new(10, -12, 0), Vector3.new(0, 0, -1), 8, 15,
		"Level 3 Kids Stair " .. index)
	makeSlideTube(kidsFolder, slideTop,
		slideTop + Vector3.new(0, -3, 15),
		slideEnd + Vector3.new(0, 6, -12),
		slideEnd, 4.4,
		Configuration.SlideColors[(index % #Configuration.SlideColors) + 1],
		"Level 3 Kids Slide " .. index, 14, true)

	local pitCenter = center + Vector3.new(-hall.Width * .26, 0, hall.Depth * .22)
	local pit = part(kidsFolder, "Level 3 Ball Pit Basin",
		CFrame.new(pitCenter + Vector3.new(0, .6, 0)), Vector3.new(36, 1.2, 32),
		palette.Accent, Enum.Material.SmoothPlastic)
	pit.CanCollide = true
	for wallIndex, data in ipairs({
		{Vector3.new(-18, 2.5, 0), Vector3.new(1.5, 5, 32)},
		{Vector3.new(18, 2.5, 0), Vector3.new(1.5, 5, 32)},
		{Vector3.new(0, 2.5, -16), Vector3.new(36, 5, 1.5)},
		{Vector3.new(0, 2.5, 16), Vector3.new(36, 5, 1.5)},
	}) do
		part(kidsFolder, "Level 3 Ball Pit Wall " .. wallIndex,
			CFrame.new(pitCenter + data[1]), data[2], palette.Color, Enum.Material.SmoothPlastic)
	end

	if hall.PoolType == "KidsShallow" then
		makeBasin(kidsFolder, center + Vector3.new(hall.Width * .26, 0, 0),
			math.min(60, hall.Width * .38), math.min(60, hall.Depth * .5),
			Configuration.ShallowPoolDepth, "Kids Paddling")
	end

	lightHall(kidsFolder, hall, "Kids" .. index)
	return kidsFolder
end

-- ── pump stations ───────────────────────────────────────────────────────────

local function makePumpStation(parent, hall, index)
	local center = hall.Center
	local model = Instance.new("Model")
	model.Name = "Level 3 Pump Station " .. index
	model:SetAttribute("Level3_PumpIndex", index)
	model.Parent = parent

	local plinth = tiledPart(model, "Level 3 Pump Plinth",
		CFrame.new(center + Vector3.new(0, 2.5, 0)), Vector3.new(22, 5, 14), C.TileWarm, nil, 8)
	plinth.CanCollide = true

	local housing = part(model, "Level 3 Pump Housing",
		CFrame.new(center + Vector3.new(0, 8.5, 0)) * CFrame.Angles(0, 0, math.pi * .5),
		Vector3.new(16, 9, 9), C.Metal, Enum.Material.Metal)
	housing.Shape = Enum.PartType.Cylinder
	housing.CanCollide = true

	local panel = part(model, "Level 3 Pump Panel",
		CFrame.new(center + Vector3.new(0, 8, 8)), Vector3.new(9, 7, 1.2), C.Metal, Enum.Material.DiamondPlate)
	local lamp = part(model, "Level 3 Pump Lamp",
		panel.CFrame * CFrame.new(0, 2, .8), Vector3.new(3, 1.4, .3), C.Locked, Enum.Material.Neon)
	lamp.CanCollide = false

	local lever = part(model, "Level 3 Pump Lever",
		panel.CFrame * CFrame.new(0, -1.4, 1.1) * CFrame.Angles(math.rad(-38), 0, 0),
		Vector3.new(1, 4.6, 1), C.Locked, Enum.Material.Metal)
	lever.CanCollide = false

	local prompt = Instance.new("ProximityPrompt")
	prompt.Name = "Level 3 Pump Prompt"
	prompt.ActionText = "Start pump"
	prompt.ObjectText = "Pump station " .. index
	prompt.HoldDuration = 1.6
	prompt.MaxActivationDistance = 10
	prompt.RequiresLineOfSight = true
	prompt.Parent = lever

	model.PrimaryPart = plinth
	return {Model = model, Prompt = prompt, Lever = lever, Lamp = lamp, Housing = housing, Index = index}
end

-- ── corridors ───────────────────────────────────────────────────────────────

local function makeCorridor(parent, layout, corridor, doorFolder)
	local width = corridor.Width
	local height = Configuration.CorridorHeight
	local from, to = corridor.From, corridor.To
	local length = math.abs(to - from) + 4
	local mid = (from + to) * .5
	local center
	if corridor.Axis == "X" then
		center = Vector3.new(mid, 0, corridor.Cross)
	else
		center = Vector3.new(corridor.Cross, 0, mid)
	end

	local alongX = corridor.Axis == "X"
	local floorSize = alongX and Vector3.new(length, .7, width) or Vector3.new(width, .7, length)
	local floor = tiledPart(parent, "Level 3 Corridor Floor",
		CFrame.new(center + Vector3.new(0, -.35, 0)), floorSize, C.TileWarm, {Enum.NormalId.Top}, 7)
	floor.CanCollide = true

	local ceilingSize = alongX and Vector3.new(length, 2, width) or Vector3.new(width, 2, length)
	local ceiling = tiledPart(parent, "Level 3 Corridor Ceiling",
		CFrame.new(center + Vector3.new(0, height + 1, 0)), ceilingSize, C.TileCool,
		{Enum.NormalId.Bottom}, 9)
	ceiling.CanCollide = true

	for _, sign in ipairs({-1, 1}) do
		local offset = alongX and Vector3.new(0, height * .5 - 2, sign * width * .5)
			or Vector3.new(sign * width * .5, height * .5 - 2, 0)
		local size = alongX and Vector3.new(length, height + 4, Configuration.WallThickness)
			or Vector3.new(Configuration.WallThickness, height + 4, length)
		local wall = tiledPart(parent, "Level 3 Corridor Wall",
			CFrame.new(center + offset), size, C.TileCool, nil, 7)
		wall.CanCollide = true
	end

	-- Arched ribs give the flooded tunnels their shape.
	local ribs = math.max(2, math.floor(length / 26))
	for rib = 1, ribs do
		local t = rib / (ribs + 1)
		local position = alongX
			and Vector3.new(from + (to - from) * t, 0, corridor.Cross)
			or Vector3.new(corridor.Cross, 0, from + (to - from) * t)
		makeArchRing(parent, position, not alongX, corridor.Index .. "." .. rib, width * .5)
	end

	makeCeilingPanel(parent, center, "Corridor " .. corridor.Index,
		alongX and Vector3.new(length * .55, .55, 6) or Vector3.new(6, .55, length * .55),
		0, height)

	-- Water. Drainable corridors are deep enough that draining them visibly
	-- changes the space; ordinary corridors carry a shallow film.
	local water
	if corridor.DrainGroup then
		local basinWidth = alongX and length - 6 or width - 6
		local basinDepth = alongX and width - 6 or length - 6
		water = makeBasin(parent, center, alongX and length - 6 or width - 6,
			alongX and width - 6 or length - 6, Configuration.DrainableCorridorDepth,
			"Corridor " .. corridor.Index)
	else
		local waterSize = alongX
			and Vector3.new(length - 4, Configuration.CorridorPoolDepth, width - 8)
			or Vector3.new(width - 8, Configuration.CorridorPoolDepth, length - 4)
		local waterCFrame = CFrame.new(center + Vector3.new(0, -Configuration.CorridorPoolDepth * .5 + .1, 0))
		Terrain:FillBlock(waterCFrame, waterSize, Enum.Material.Water)
		water = {CFrame = waterCFrame, Size = waterSize}
	end

	-- Pressure doors seal the grand slide hall until every pump is running.
	local door
	if corridor.Kind == "PressureDoor" then
		local doorSize = alongX and Vector3.new(2.2, height, width)
			or Vector3.new(width, height, 2.2)
		local doorCenter = alongX and Vector3.new(to, height * .5 - 2, corridor.Cross)
			or Vector3.new(corridor.Cross, height * .5 - 2, to)
		door = part(doorFolder, "Level 3 Pressure Door " .. corridor.Index,
			CFrame.new(doorCenter), doorSize, C.Locked, Enum.Material.DiamondPlate)
		door.CanCollide = true
		door:SetAttribute("Level3_CorridorIndex", corridor.Index)
	end

	return {Corridor = corridor, Water = water, Door = door, Center = center}
end

-- ── compatibility markers ───────────────────────────────────────────────────

-- GameManager and the Level 1 scripts still look for these by name. They are
-- NOT optional: connectElevator does WaitForChild("DoorL") with no timeout, so
-- an Elevator model without DoorL/DoorR hangs the round thread forever;
-- ElevatorSpawn must be a BasePart because placeSafelyInElevator reads .Size
-- and writes .CanCollide; a missing MazeStart leaves worldReady false; and a
-- missing EntityStart costs a silent 30 second stall.
local function makeCompatibilityArrival(world, arrivalPosition)
	local marker = part(world, "Level 3 Arrival Spawn",
		CFrame.new(arrivalPosition + Vector3.new(0, 3, 0)), Vector3.new(9, .4, 9),
		C.Emergency, Enum.Material.Neon, 1)
	marker.CanCollide = false
	marker.CanTouch = false

	local elevator = Instance.new("Model")
	elevator.Name = "Elevator"
	elevator:SetAttribute("Level3_CompatibilityMarker", true)
	elevator.Parent = workspace
	local shell = part(elevator, "Level 3 Arrival Elevator Shell",
		CFrame.new(arrivalPosition + Vector3.new(0, 5, 0)), Vector3.new(18, 10, 18),
		C.TileWarm, Enum.Material.SmoothPlastic, 1)
	shell.CanCollide = false
	shell.CanTouch = false
	local doorLeft = part(elevator, "DoorL",
		CFrame.new(arrivalPosition + Vector3.new(-4.5, 5, 8.8)), Vector3.new(8.5, 10, .6),
		C.Metal, Enum.Material.Metal, 1)
	local doorRight = part(elevator, "DoorR",
		CFrame.new(arrivalPosition + Vector3.new(4.5, 5, 8.8)), Vector3.new(8.5, 10, .6),
		C.Metal, Enum.Material.Metal, 1)
	doorLeft.CanCollide, doorRight.CanCollide = false, false
	doorLeft.CanTouch, doorRight.CanTouch = false, false
	elevator.PrimaryPart = shell

	local function compatibilityMarker(name, position, size)
		local object = part(workspace, name, CFrame.new(position), size, C.Emergency,
			Enum.Material.Neon, 1)
		object.CanCollide = false
		object.CanTouch = false
		object:SetAttribute("Level3_CompatibilityMarker", true)
		return object
	end

	local mazeStart = compatibilityMarker("MazeStart", arrivalPosition + Vector3.new(0, 3, 0), Vector3.new(4, .2, 4))
	local elevatorSpawn = compatibilityMarker("ElevatorSpawn", arrivalPosition + Vector3.new(0, 3, 0), Vector3.new(11, .2, 11))
	local entityStart = compatibilityMarker("EntityStart", arrivalPosition + Vector3.new(0, -40, 0), Vector3.new(4, .2, 4))

	return {
		ArrivalSpawn = marker,
		Elevator = elevator,
		MazeStart = mazeStart,
		ElevatorSpawn = elevatorSpawn,
		EntityStart = entityStart,
	}
end

-- ── build ───────────────────────────────────────────────────────────────────

function WorldBuilder.Build(layout, generation)
	-- Same water look as Level 2, on purpose.
	Terrain.WaterColor = C.Water
	Terrain.WaterTransparency = .24
	Terrain.WaterReflectance = .08
	Terrain.WaterWaveSize = .035
	Terrain.WaterWaveSpeed = 1.65

	local world = Instance.new("Model")
	world.Name = "Level 3 Generated World"
	world:SetAttribute("Level3_Seed", layout.Seed)
	world:SetAttribute("Level3_Generation", generation)
	world:SetAttribute("Level3_GenerationAttempt", layout.Attempt)
	world:SetAttribute("Level3_Theme", Configuration.Theme)
	world.Parent = workspace

	local geometry = folder(world, "Level 3 Geometry")
	local hallsFolder = folder(geometry, "Level 3 Halls")
	local corridorsFolder = folder(geometry, "Level 3 Corridors")
	local kidsFolder = folder(geometry, "Level 3 Kids Wing")
	local slideFolder = folder(geometry, "Level 3 Slide Halls")
	local containment = folder(geometry, "Level 3 Containment")
	local objectiveFolder = folder(world, "Level 3 Objectives")
	local doorFolder = folder(objectiveFolder, "Level 3 Pressure Doors")
	local lightingFolder = folder(world, "Level 3 Lighting")
	local navigationFolder = folder(world, "Level 3 Navigation")
	local entityFolder = folder(world, "Level 3 Entity Nodes")

	local extent = Configuration.ComplexExtent
	local tallest = Configuration.GrandSlideHallHeight

	local floor = tiledPart(containment, "Level 3 Sealed Foundation", CFrame.new(0, -36, 0),
		Vector3.new(extent + 120, 4, extent + 120), C.DarkGrout, {Enum.NormalId.Top}, 12)
	floor.CanCollide = true

	-- Work out where each corridor punches through each hall wall.
	local doorsByHall = {}
	for _, hall in ipairs(layout.Halls) do
		doorsByHall[hall.Index] = {East = {}, West = {}, North = {}, South = {}}
	end
	for _, corridor in ipairs(layout.Corridors) do
		local a, b = layout.Halls[corridor.A], layout.Halls[corridor.B]
		if corridor.Axis == "X" then
			local left = (a.MaxX <= b.MinX) and a or b
			local right = (left == a) and b or a
			table.insert(doorsByHall[left.Index].East, corridor.Cross)
			table.insert(doorsByHall[right.Index].West, corridor.Cross)
		else
			local north = (a.MaxZ <= b.MinZ) and a or b
			local south = (north == a) and b or a
			table.insert(doorsByHall[north.Index].South, corridor.Cross)
			table.insert(doorsByHall[south.Index].North, corridor.Cross)
		end
	end

	local slideDecks = {}
	local built = 0

	for _, hall in ipairs(layout.Halls) do
		local hallModel = Instance.new("Model")
		hallModel.Name = hall.Id .. " " .. (hall.Archetype or "Hall")
		hallModel:SetAttribute("Level3_Role", hall.Role)
		hallModel:SetAttribute("Level3_PoolType", hall.PoolType)
		hallModel:SetAttribute("Level3_Archetype", hall.Archetype)
		hallModel:SetAttribute("Level3_GraphDepth", hall.GraphDepth)
		hallModel:SetAttribute("Level3_Height", hallHeight(hall))
		hallModel:SetAttribute("Level3_Width", hall.Width)
		hallModel:SetAttribute("Level3_Depth", hall.Depth)
		if hall.KidsColorIndex then
			hallModel:SetAttribute("Level3_KidsColor", kidsPalette(hall).Name)
		end
		hallModel.Parent = hallsFolder

		makeHallFloor(hallModel, hall)
		makeHallCeiling(hallModel, hall)

		local doors = doorsByHall[hall.Index]
		local height = hallHeight(hall)
		makeWallWithGaps(hallModel, hall, "Level 3 Hall West Wall", "Z", hall.MinX, hall.MinZ, hall.MaxZ, doors.West, height)
		makeWallWithGaps(hallModel, hall, "Level 3 Hall East Wall", "Z", hall.MaxX, hall.MinZ, hall.MaxZ, doors.East, height)
		makeWallWithGaps(hallModel, hall, "Level 3 Hall North Wall", "X", hall.MinZ, hall.MinX, hall.MaxX, doors.North, height)
		makeWallWithGaps(hallModel, hall, "Level 3 Hall South Wall", "X", hall.MaxZ, hall.MinX, hall.MaxX, doors.South, height)

		if hall.Role == "Kids Area" then
			makeKidsHall(kidsFolder, hall, hall.KidsIndex or hall.Index)
		elseif hall.Role == "Slide Hall" then
			slideDecks[hall.SlideHallIndex] = makeSlideHall(slideFolder, hall, hall.SlideHallIndex)
		else
			-- Ordinary halls: water plus whatever the archetype calls for.
			local basinWidth = hall.Width - 40
			local basinDepth = hall.Depth - 40
			if hall.PoolType == "Deep" then
				makeBasin(hallModel, hall.Center, basinWidth, basinDepth, Configuration.DeepPoolDepth, "Deep")
			elseif hall.PoolType == "Shallow" or hall.PoolType == "Arch" then
				makeBasin(hallModel, hall.Center, basinWidth, basinDepth, Configuration.ShallowPoolDepth, "Shallow")
			end

			local archetype = hall.Archetype or ""
			if archetype == "Pillar Basin" or archetype == "Diving Well" then
				for _, sx in ipairs({-1, 1}) do
					for _, sz in ipairs({-1, 1}) do
						makeColumn(hallModel, hall.Center + Vector3.new(sx * hall.Width * .26, -Configuration.DeepPoolDepth, sz * hall.Depth * .26),
							height + Configuration.DeepPoolDepth, 7)
					end
				end
			elseif archetype == "Arch Tunnel" or archetype == "Ring Corridor" then
				local rings = math.max(2, math.floor(hall.Width / 40))
				for ring = 1, rings do
					local x = hall.Center.X - hall.Width * .5 + (ring / (rings + 1)) * hall.Width
					makeArchRing(hallModel, Vector3.new(x, 0, hall.Center.Z), false, hall.Index .. "." .. ring,
						math.min(18, hall.Depth * .22))
				end
			elseif archetype == "Spiral Stair Well" then
				makeSpiralStair(hallModel, hall.Center, -1, height - 12, 13, "Level 3 Stair Well " .. hall.Index)
			elseif archetype == "Skylight Hall" then
				makeSkylight(hallModel, hall.Center, hall.Width, hall.Depth, hall.Index, height)
			elseif archetype == "Curved Gallery" then
				local count = math.max(3, math.floor(hall.Width / 46))
				for column = 1, count do
					local x = hall.Center.X - hall.Width * .5 + (column / (count + 1)) * hall.Width
					makeColumn(hallModel, Vector3.new(x, 0, hall.Center.Z - hall.Depth * .28), height, 6)
				end
			elseif archetype == "Arrival Concourse" then
				makeStairFlight(hallModel, hall.Center + Vector3.new(-hall.Width * .3, 0, 0),
					Vector3.new(1, 0, 0), 24, 10, "Level 3 Arrival Stair")
			end
		end

		if hall.Role ~= "Kids Area" and hall.Role ~= "Slide Hall" then
			lightHall(lightingFolder, hall, hall.Index)
		end

		local node = part(navigationFolder, "Level 3 Navigation Node " .. hall.Index,
			CFrame.new(hall.Center + Vector3.new(0, 1, 0)), Vector3.new(2, .2, 2),
			C.Emergency, Enum.Material.Neon, 1)
		node.CanCollide = false
		node.CanTouch = false
		node:SetAttribute("Level3_HallId", hall.Id)
		node:SetAttribute("Level3_Role", hall.Role)

		-- Patrol nodes give a future entity a ready-made wander graph.
		for corner, sign in ipairs({
			Vector3.new(-.3, 0, -.3), Vector3.new(.3, 0, -.3),
			Vector3.new(-.3, 0, .3), Vector3.new(.3, 0, .3),
		}) do
			local patrol = part(entityFolder, "Level 3 Entity Patrol Node " .. hall.Index .. "." .. corner,
				CFrame.new(hall.Center + Vector3.new(sign.X * hall.Width, 2, sign.Z * hall.Depth)),
				Vector3.new(1.5, .2, 1.5), C.Emergency, Enum.Material.Neon, 1)
			patrol.CanCollide = false
			patrol.CanTouch = false
			patrol:SetAttribute("Level3_HallId", hall.Id)
		end

		built += 1
		if built % 4 == 0 then task.wait() end
	end

	-- Corridors.
	local corridorRecords = {}
	local drains = {}
	local pressureDoors = {}
	for _, corridor in ipairs(layout.Corridors) do
		local record = makeCorridor(corridorsFolder, layout, corridor, doorFolder)
		corridorRecords[corridor.Index] = record
		if corridor.DrainGroup then drains[corridor.DrainGroup] = record end
		if record.Door then table.insert(pressureDoors, record) end
	end
	task.wait()

	-- Pump stations.
	local pumps = {}
	for index, hall in ipairs(layout.PumpHalls) do
		pumps[index] = makePumpStation(objectiveFolder, hall, index)
		pumps[index].Hall = hall
	end

	-- Exit flume off the grand slide hall's top deck.
	local grand = layout.GrandSlideHall
	local exit = makeExitFlume(geometry, grand, slideDecks[grand.SlideHallIndex])

	local arrival = makeCompatibilityArrival(world, layout.Arrival.Center)

	-- Entity den marker: reserved space, nothing spawns here yet.
	local den = part(entityFolder, "Level 3 Entity Den Spawn",
		CFrame.new(layout.EntityDen.Center + Vector3.new(0, 3, 0)), Vector3.new(10, .4, 10),
		C.Void, Enum.Material.Neon, 1)
	den.CanCollide = false
	den.CanTouch = false
	den:SetAttribute("Level3_HallId", layout.EntityDen.Id)
	entityFolder:SetAttribute("Level3_DenPosition", layout.EntityDen.Center)
	arrival.EntityStart.CFrame = CFrame.new(layout.EntityDen.Center + Vector3.new(0, 4, 0))

	-- Outer shell, big enough to contain the exit flume's run.
	local shellHalf = extent * .5 + 60
	local shellHeight = tallest + 12
	for _, data in ipairs({
		{Vector3.new(0, shellHeight * .5 - 20, -shellHalf), Vector3.new(extent + 130, shellHeight + 40, 8)},
		{Vector3.new(0, shellHeight * .5 - 20, shellHalf), Vector3.new(extent + 130, shellHeight + 40, 8)},
		{Vector3.new(-shellHalf, shellHeight * .5 - 20, 0), Vector3.new(8, shellHeight + 40, extent + 130)},
	}) do
		local wall = tiledPart(containment, "Level 3 Outer Containment Wall",
			CFrame.new(data[1]), data[2], C.DarkGrout, nil, 12)
		wall.CanCollide = true
	end
	local roof = tiledPart(containment, "Level 3 Sealed Ceiling", CFrame.new(0, shellHeight + 22, 0),
		Vector3.new(extent + 130, 4, extent + 130), C.DarkGrout, {Enum.NormalId.Bottom}, 12)
	roof.CanCollide = true

	local terrainCenter = Vector3.new(0, -16, 0)
	local terrainSize = Vector3.new(extent + 700, 160, extent + 700)
	world:SetAttribute("Level3_TerrainCenter", terrainCenter)
	world:SetAttribute("Level3_TerrainSize", terrainSize)
	world:SetAttribute("Level3_HallCount", #layout.Halls)
	world:SetAttribute("Level3_CorridorCount", #layout.Corridors)
	world:SetAttribute("Level3_KidsRoomCount", #(layout.KidsArea or {}))
	world:SetAttribute("Level3_SlideHallCount", #(layout.SlideHalls or {}))

	return {
		World = world,
		Layout = layout,
		Pumps = pumps,
		PressureDoors = pressureDoors,
		Drains = drains,
		Corridors = corridorRecords,
		Exit = exit,
		Arrival = arrival,
		EntityDen = den,
		EntityNodes = entityFolder,
		TerrainCenter = terrainCenter,
		TerrainSize = terrainSize,
		Generation = generation,
	}
end

return WorldBuilder
