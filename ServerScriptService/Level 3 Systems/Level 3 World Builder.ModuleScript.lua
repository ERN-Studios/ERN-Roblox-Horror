-- Level 3 World Builder
-- Turns a Level 3 layout (variable-size halls + corridors) into geometry.
--
-- Shared with Level 2 on purpose, and nothing else: the tile texture asset and
-- the terrain water appearance. Everything structural here is Level 3's own.
--
-- Reference-photo language this builder aims for: warm off-white tiled rooms
-- with tiled ceilings, dry tiled walkways around sunken turquoise basins,
-- arched flooded tunnels, round tiled columns rising out of the water, spiral
-- stairs, daylight-slot skylights, and chrome rails/ladders at the pool edges.

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

-- Which basin (if any) a hall carries: width, depth, water depth. The basin is
-- always centred, with a dry HallBasinBorder walkway all the way around.
local function basinFor(hall)
	local border = Configuration.HallBasinBorder
	local width = hall.Width - border * 2
	local depth = hall.Depth - border * 2
	if width < 24 or depth < 24 then return nil end
	if hall.Role == "Slide Hall" then
		return width, depth, Configuration.DeepPoolDepth
	end
	if hall.PoolType == "Deep" then
		return width, depth, Configuration.DeepPoolDepth
	end
	if hall.PoolType == "Shallow" or hall.PoolType == "Arch" then
		return width, depth, Configuration.ShallowPoolDepth
	end
	return nil
end

-- ── walls ───────────────────────────────────────────────────────────────────

-- A straight wall from `low` to `high` along `axis` at fixed `cross`, with any
-- number of floor-level doorway gaps, plus an optional raised rectangular hole
-- (used where the exit flume passes through a wall).
local function makeWallWithGaps(parent, hall, name, axis, cross, low, high, gaps, height, bottomY, flumeGap)
	height = height or hallHeight(hall)
	bottomY = bottomY or -4
	local thickness = Configuration.WallThickness
	local fullHeight = height - bottomY
	local centerY = (height + bottomY) * .5
	local doorWidth = Configuration.DoorWidth
	local doorHeight = Configuration.DoorHeight
	local wallColor = isKids(hall) and kidsPalette(hall).Color or C.TileCool

	local openings = {}
	for _, gapCenter in ipairs(gaps or {}) do
		table.insert(openings, {center = gapCenter, width = doorWidth, kind = "door"})
	end
	if flumeGap then
		table.insert(openings, {
			center = flumeGap.center, width = flumeGap.width, kind = "flume",
			bottom = flumeGap.bottom, top = flumeGap.top,
		})
	end
	table.sort(openings, function(a, b) return a.center < b.center end)

	local function positionFor(along, y)
		if axis == "X" then return Vector3.new(along, y, cross) end
		return Vector3.new(cross, y, along)
	end
	local function sizeFor(length, tall)
		if axis == "X" then return Vector3.new(length, tall, thickness) end
		return Vector3.new(thickness, tall, length)
	end

	local cursor = low
	for _, opening in ipairs(openings) do
		local gapLow = math.clamp(opening.center - opening.width * .5, low, high)
		local gapHigh = math.clamp(opening.center + opening.width * .5, low, high)
		if gapLow - cursor > .1 then
			surfaceFor(hall, parent, name, CFrame.new(positionFor((cursor + gapLow) * .5, centerY)),
				sizeFor(gapLow - cursor, fullHeight), wallColor, nil, 7)
		end
		local span = gapHigh - gapLow
		if span > .1 then
			if opening.kind == "door" then
				local lintelHeight = height - doorHeight
				if lintelHeight > 0 then
					surfaceFor(hall, parent, name .. " Lintel",
						CFrame.new(positionFor((gapLow + gapHigh) * .5, doorHeight + lintelHeight * .5)),
						sizeFor(span, lintelHeight), wallColor, nil, 7)
				end
			else
				-- Raised hole: fill below and above it.
				if opening.bottom - bottomY > .1 then
					surfaceFor(hall, parent, name .. " Sill",
						CFrame.new(positionFor((gapLow + gapHigh) * .5, (opening.bottom + bottomY) * .5)),
						sizeFor(span, opening.bottom - bottomY), wallColor, nil, 7)
				end
				if height - opening.top > .1 then
					surfaceFor(hall, parent, name .. " Header",
						CFrame.new(positionFor((gapLow + gapHigh) * .5, (height + opening.top) * .5)),
						sizeFor(span, height - opening.top), wallColor, nil, 7)
				end
			end
		end
		cursor = math.max(cursor, gapHigh)
	end
	if high - cursor > .1 then
		surfaceFor(hall, parent, name, CFrame.new(positionFor((cursor + high) * .5, centerY)),
			sizeFor(high - cursor, fullHeight), wallColor, nil, 7)
	end
end

-- ── floors, ceilings, water ─────────────────────────────────────────────────

-- Water halls get a dry tiled walkway ring around the basin opening — the
-- floor is genuinely open over the water, never a slab underneath it.
local function makeHallFloor(parent, hall)
	local floorColor = isKids(hall) and kidsPalette(hall).Accent or C.TileWarm
	local basinWidth, basinDepth = basinFor(hall)
	if not basinWidth then
		local slab = surfaceFor(hall, parent, "Level 3 Hall Floor",
			CFrame.new(hall.Center + Vector3.new(0, -.35, 0)),
			Vector3.new(hall.Width, .7, hall.Depth), floorColor, {Enum.NormalId.Top}, 7)
		slab.CanCollide = true
		return
	end

	local border = (hall.Width - basinWidth) * .5
	local borderZ = (hall.Depth - basinDepth) * .5
	for _, data in ipairs({
		{Vector3.new(0, -.35, -(hall.Depth - borderZ) * .5), Vector3.new(hall.Width, .7, borderZ)},
		{Vector3.new(0, -.35, (hall.Depth - borderZ) * .5), Vector3.new(hall.Width, .7, borderZ)},
		{Vector3.new(-(hall.Width - border) * .5, -.35, 0), Vector3.new(border, .7, hall.Depth - borderZ * 2)},
		{Vector3.new((hall.Width - border) * .5, -.35, 0), Vector3.new(border, .7, hall.Depth - borderZ * 2)},
	}) do
		local strip = surfaceFor(hall, parent, "Level 3 Hall Walkway",
			CFrame.new(hall.Center + data[1]), data[2], floorColor, {Enum.NormalId.Top}, 7)
		strip.CanCollide = true
	end
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

-- A sunken tiled basin filled with terrain water. Registers the water block in
-- `waterRegions` so validation and draining can find it. Returns the region.
local function makeBasin(parent, waterRegions, center, width, depth3, poolDepth, label)
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

	-- Chrome pool ladder on the north wall for deep basins (reference photos).
	if poolDepth > 4 then
		local ladderX = center.X - width * .25
		local ladderZ = center.Z - depth3 * .5 + 1.2
		local railTop = 2.6
		local railBottom = -poolDepth * .5
		local railHeight = railTop - railBottom
		for _, offset in ipairs({-1.4, 1.4}) do
			part(parent, "Level 3 Pool Ladder Rail",
				CFrame.new(ladderX + offset, (railTop + railBottom) * .5, ladderZ),
				Vector3.new(.34, railHeight, .34), C.Rail, Enum.Material.Metal)
		end
		for rung = 0, 4 do
			part(parent, "Level 3 Pool Ladder Rung",
				CFrame.new(ladderX, railTop - 1.2 - rung * ((railHeight - 1.6) / 4), ladderZ),
				Vector3.new(3.1, .3, .3), C.Rail, Enum.Material.Metal)
		end
	end

	local waterWidth = math.max(4, width - wallThickness * 2 - 2)
	local waterDepth = math.max(4, depth3 - wallThickness * 2 - 2)
	local waterHeight = math.max(.8, poolDepth - .35)
	local region = {
		CFrame = CFrame.new(center + Vector3.new(0, -waterHeight * .5 + .1, 0)),
		Size = Vector3.new(waterWidth, waterHeight, waterDepth),
		Label = label,
	}
	Terrain:FillBlock(region.CFrame, region.Size, Enum.Material.Water)
	table.insert(waterRegions, region)
	return region
end

-- A raised wading pool that sits ON the floor (kids rooms). No digging, so the
-- floor slab underneath stays honest.
local function makeRaisedPool(parent, waterRegions, center, width, depth3, palette)
	local wallHeight = 2.4
	local shellBottom = part(parent, "Level 3 Kids Pool Base",
		CFrame.new(center + Vector3.new(0, .15, 0)), Vector3.new(width, .3, depth3),
		palette.Accent, Enum.Material.SmoothPlastic)
	shellBottom.CanCollide = true
	for _, data in ipairs({
		{Vector3.new(-width * .5, wallHeight * .5, 0), Vector3.new(1.2, wallHeight, depth3)},
		{Vector3.new(width * .5, wallHeight * .5, 0), Vector3.new(1.2, wallHeight, depth3)},
		{Vector3.new(0, wallHeight * .5, -depth3 * .5), Vector3.new(width, wallHeight, 1.2)},
		{Vector3.new(0, wallHeight * .5, depth3 * .5), Vector3.new(width, wallHeight, 1.2)},
	}) do
		part(parent, "Level 3 Kids Pool Wall", CFrame.new(center + data[1]), data[2],
			palette.Color, Enum.Material.SmoothPlastic).CanCollide = true
	end
	-- Step block so small legs can climb in.
	part(parent, "Level 3 Kids Pool Step",
		CFrame.new(center + Vector3.new(0, .6, depth3 * .5 + 2)), Vector3.new(10, 1.2, 3.4),
		palette.Accent, Enum.Material.SmoothPlastic).CanCollide = true

	local region = {
		CFrame = CFrame.new(center + Vector3.new(0, wallHeight * .5 + .2, 0)),
		Size = Vector3.new(width - 3, wallHeight - .6, depth3 - 3),
		Label = "Kids Pool",
	}
	Terrain:FillBlock(region.CFrame, region.Size, Enum.Material.Water)
	table.insert(waterRegions, region)
	return region
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

-- A proper archway: a contiguous half-ring of tangent-rotated tiled segments,
-- grounded at both ends. `acrossZ` picks which vertical plane the arch lives
-- in: true = the ring spans across Z (you walk through it travelling along X).
local function makeArchRing(parent, center, acrossZ, index, radius)
	radius = math.max(6, radius)
	local steps = math.max(12, math.floor(radius * 1.6))
	local segmentLength = (math.pi * radius) / steps + .8
	for step = 0, steps do
		local a = math.pi * step / steps
		local side = math.cos(a) * radius
		local y = 1 + math.sin(a) * radius
		local position, orientation
		if acrossZ then
			position = center + Vector3.new(0, y, side)
			orientation = CFrame.Angles(math.pi * .5 - a, 0, 0)
		else
			position = center + Vector3.new(side, y, 0)
			orientation = CFrame.Angles(0, 0, a - math.pi * .5)
		end
		local rib = part(parent, "Level 3 Arch Rib " .. index,
			CFrame.new(position) * orientation,
			acrossZ and Vector3.new(3.2, 2.0, segmentLength) or Vector3.new(segmentLength, 2.0, 3.2),
			C.TileWarm)
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

local function makeStairFlight(parent, base, direction, width, steps, name, run, rise)
	direction = direction.Unit
	run = run or 2.3
	rise = rise or .78
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

-- A slide hall: sunken basin with walkways, columns to the roof, a top deck on
-- the north edge reached by a spiral stair plus a catwalk, and flumes that
-- each stay in their own straight lane down into the water — lanes never
-- cross, and every lane is clamped inside the basin.
local function makeSlideHall(parent, waterRegions, hall, index)
	local height = hallHeight(hall)
	local center = hall.Center
	local hallFolder = folder(parent, "Level 3 Slide Hall " .. index)

	local basinWidth, basinDepth, poolDepth = basinFor(hall)
	makeBasin(hallFolder, waterRegions, center, basinWidth, basinDepth, poolDepth, "Slide Hall " .. index)

	-- Columns clamped inside the basin so they rise from the water, not walls.
	local columnOffsetX = math.min(hall.Width * .30, basinWidth * .5 - 12)
	local columnOffsetZ = math.min(hall.Depth * .30, basinDepth * .5 - 12)
	for _, sx in ipairs({-1, 1}) do
		for _, sz in ipairs({-1, 1}) do
			makeColumn(hallFolder,
				center + Vector3.new(sx * columnOffsetX, -poolDepth, sz * columnOffsetZ),
				height + poolDepth, 9)
		end
	end

	-- Top deck along the north edge.
	local deckY = height - 22
	local deckDepth = math.min(46, hall.Depth * .3)
	local deckZ = hall.MinZ + deckDepth * .5 + 4
	local deck = tiledPart(hallFolder, "Level 3 Slide Hall Deck",
		CFrame.new(Vector3.new(center.X, deckY, deckZ)),
		Vector3.new(hall.Width - 16, 2, deckDepth), C.TileWarm, Enum.NormalId:GetEnumItems(), 8)
	deck.CanCollide = true
	makeRail(hallFolder,
		Vector3.new(hall.MinX + 10, deckY + 1, deckZ + deckDepth * .5),
		Vector3.new(hall.MaxX - 10, deckY + 1, deckZ + deckDepth * .5),
		"Level 3 Slide Hall " .. index .. " Deck")

	-- Spiral stair in the south-east corner, then a catwalk along the east wall
	-- up to the deck, so the climb is actually connected.
	local spiralCenter = Vector3.new(hall.MaxX - 26, 0, hall.MaxZ - 26)
	makeSpiralStair(hallFolder, spiralCenter, -1, deckY, 12,
		"Level 3 Slide Hall " .. index .. " Spiral")
	local catwalkZ0 = hall.MaxZ - 26
	local catwalkZ1 = deckZ + deckDepth * .5
	local catwalk = tiledPart(hallFolder, "Level 3 Slide Hall Catwalk",
		CFrame.new(Vector3.new(hall.MaxX - 12, deckY, (catwalkZ0 + catwalkZ1) * .5)),
		Vector3.new(8, 2, math.abs(catwalkZ0 - catwalkZ1)), C.TileWarm,
		Enum.NormalId:GetEnumItems(), 8)
	catwalk.CanCollide = true
	makeRail(hallFolder,
		Vector3.new(hall.MaxX - 16, deckY + 1, catwalkZ0),
		Vector3.new(hall.MaxX - 16, deckY + 1, catwalkZ1),
		"Level 3 Slide Hall " .. index .. " Catwalk")

	-- Flumes: each lane keeps one X offset all the way down — no sign flips, so
	-- tubes can never cross. Lane spacing beats tube diameter by a margin.
	local radius = Configuration.SlideTubeRadius
	local laneStep = math.max(radius * 2 + 9, math.min(34, hall.Width * .18))
	for slide = 1, Configuration.SlidesPerHall do
		local lane = (slide - (Configuration.SlidesPerHall + 1) * .5) * laneStep
		lane = math.clamp(lane, -basinWidth * .5 + radius + 4, basinWidth * .5 - radius - 4)
		local color = Configuration.SlideColors[((index + slide - 2) % #Configuration.SlideColors) + 1]
		local startPoint = Vector3.new(center.X + lane, deckY + 4, deckZ + deckDepth * .4)
		local p1 = Vector3.new(center.X + lane, deckY - 10, deckZ + deckDepth * .4 + hall.Depth * .18)
		local p2 = Vector3.new(center.X + lane * .9, 14, center.Z + hall.Depth * .08)
		local endZ = math.min(center.Z + hall.Depth * .26, center.Z + basinDepth * .5 - radius - 4)
		local p3 = Vector3.new(center.X + lane * .8, 2.5, endZ)
		makeSlideTube(hallFolder, startPoint, p1, p2, p3, radius, color,
			"Level 3 Slide Hall " .. index .. " Flume " .. slide, Configuration.SlideSegments, true)
		local mouth = part(hallFolder, "Level 3 Slide Hall " .. index .. " Flume Mouth " .. slide,
			CFrame.lookAt(startPoint, p1), Vector3.new(radius * 2.4, .8, 3), color,
			Enum.Material.Neon, .35)
		mouth.CanCollide = false
	end

	lightHall(hallFolder, hall, "SlideHall" .. index)
	makeSkylight(hallFolder, center, hall.Width, hall.Depth, "SlideHall" .. index, height)

	return {Folder = hallFolder, DeckY = deckY, DeckZ = deckZ, DeckDepth = deckDepth}
end

-- The exit flume leaves the grand hall's top deck heading east, stays high in
-- the void above the other halls' ceilings, and only dives once it is past the
-- outer shell. Both the grand hall's east wall and the shell get a matching
-- pass-through hole, so nothing solid ever crosses the tube's interior.
local function makeExitFlume(parent, layout, hall, deck)
	local boundsMaxX = layout.Bounds.MaxX
	local shellX = boundsMaxX + 60
	local startPoint = Vector3.new(hall.MaxX - 14, deck.DeckY + 5, deck.DeckZ)
	local run = (shellX + 34) - startPoint.X
	local p1 = startPoint + Vector3.new(run * .35, -4, 0)
	local p2 = startPoint + Vector3.new(run * .8, -12, 0)
	local p3 = Vector3.new(shellX + 34, 4, deck.DeckZ)

	makeSlideTube(parent, startPoint, p1, p2, p3, 8, C.TileCool, "Level 3 Exit Flume", 30, false)

	local mouth = part(parent, "Level 3 Exit Flume Mouth", CFrame.lookAt(startPoint, p1),
		Vector3.new(20, 20, 1.4), C.Emergency, Enum.Material.Neon, .55)
	mouth.CanCollide = false

	-- Sealed catch room past the shell.
	local catchCenter = p3 + Vector3.new(24, 2, 0)
	local catchSize = 44
	tiledPart(parent, "Level 3 Exit Catch Floor",
		CFrame.new(catchCenter + Vector3.new(0, -6, 0)),
		Vector3.new(catchSize, 1.5, catchSize), C.TileWarm, {Enum.NormalId.Top}, 9)
	tiledPart(parent, "Level 3 Exit Catch Ceiling",
		CFrame.new(catchCenter + Vector3.new(0, 18, 0)),
		Vector3.new(catchSize, 1.5, catchSize), C.TileCool, {Enum.NormalId.Bottom}, 9)
	for _, data in ipairs({
		{Vector3.new(-catchSize * .5, 6, 0), Vector3.new(1.5, 24, catchSize)},
		{Vector3.new(catchSize * .5, 6, 0), Vector3.new(1.5, 24, catchSize)},
		{Vector3.new(0, 6, -catchSize * .5), Vector3.new(catchSize, 24, 1.5)},
		{Vector3.new(0, 6, catchSize * .5), Vector3.new(catchSize, 24, 1.5)},
	}) do
		tiledPart(parent, "Level 3 Exit Catch Wall", CFrame.new(catchCenter + data[1]), data[2],
			C.TileCool, nil, 9)
	end

	local safeSpawn = part(parent, "Level 3 Exit Safe Spawn",
		CFrame.new(catchCenter + Vector3.new(0, -4.9, 0)), Vector3.new(7, .4, 7),
		C.Emergency, Enum.Material.Neon, 1)
	safeSpawn.CanCollide = false
	safeSpawn.CanTouch = false

	local trigger = part(parent, "Level 3 Exit Trigger",
		CFrame.new(startPoint + Vector3.new(9, 0, 0)), Vector3.new(6, 18, 18),
		C.Emergency, Enum.Material.Neon, 1)
	trigger.CanCollide = false
	trigger.CanTouch = true

	return {
		Trigger = trigger,
		SafeSpawn = safeSpawn,
		Mouth = mouth,
		EndPosition = catchCenter,
		StartPoint = startPoint,
		HallWallGap = {center = deck.DeckZ, width = 30, bottom = deck.DeckY - 14, top = deck.DeckY + 20},
		ShellGap = {center = deck.DeckZ, width = 40, bottom = -10, top = deck.DeckY + 4},
	}
end

-- ── kids wing ───────────────────────────────────────────────────────────────

local function makeKidsHall(parent, waterRegions, hall, index)
	local palette = kidsPalette(hall)
	local center = hall.Center
	local kidsFolder = folder(parent, "Level 3 Kids Room " .. index .. " " .. palette.Name)
	kidsFolder:SetAttribute("Level3_KidsColor", palette.Name)

	local rng = Random.new(hall.LocalSeed or index)
	local blocks = math.clamp(math.floor(hall.Area / 2600), 5, 14)
	for block = 1, blocks do
		local x = rng:NextNumber(-.32, .32) * hall.Width
		local z = rng:NextNumber(-.32, .32) * hall.Depth
		local blockHeight = rng:NextNumber(3, 8)
		local shade = block % 2 == 0 and palette.Accent or palette.Color
		local pad = part(kidsFolder, "Level 3 Soft Play Block " .. block,
			CFrame.new(center + Vector3.new(x, blockHeight * .5, z)) * CFrame.Angles(0, rng:NextNumber() * math.pi, 0),
			Vector3.new(rng:NextNumber(8, 17), blockHeight, rng:NextNumber(8, 17)), shade,
			Enum.Material.SmoothPlastic)
		pad.CanCollide = true
	end

	-- Kids flume: stair count and run clamped to the room so nothing pokes
	-- through a wall.
	local steps = math.clamp(math.floor((hall.Depth * .3 - 8) / 2.3), 6, 15)
	local topY = steps * .78
	local slideTop = center + Vector3.new(-hall.Width * .26, topY + 2.5, -hall.Depth * .2)
	local slideEnd = center + Vector3.new(-hall.Width * .26, 1.5, math.min(hall.Depth * .12, hall.Depth * .5 - 22))
	makeStairFlight(kidsFolder, slideTop + Vector3.new(9, -topY - 2.5, 0), Vector3.new(0, 0, -1), 8, steps,
		"Level 3 Kids Stair " .. index)
	makeSlideTube(kidsFolder, slideTop,
		slideTop + Vector3.new(0, -3, 13),
		slideEnd + Vector3.new(0, 6, -11),
		slideEnd, 4.4,
		Configuration.SlideColors[(index % #Configuration.SlideColors) + 1],
		"Level 3 Kids Slide " .. index, 14, true)

	-- Ball pit basin (dry, plastic).
	local pitCenter = center + Vector3.new(-hall.Width * .26, 0, math.min(hall.Depth * .26, hall.Depth * .5 - 20))
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

	-- Raised paddling pool: water above the floor, so no digging and no
	-- walking-on-water artefacts.
	if hall.PoolType == "KidsShallow" then
		makeRaisedPool(kidsFolder, waterRegions,
			center + Vector3.new(math.min(hall.Width * .26, hall.Width * .5 - 34), 0, 0),
			math.min(52, hall.Width * .36), math.min(52, hall.Depth * .44), palette)
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

	-- Fat intake pipes running from the pump into the floor.
	for _, sx in ipairs({-1, 1}) do
		local pipe = part(model, "Level 3 Pump Intake Pipe",
			CFrame.new(center + Vector3.new(sx * 9.5, 4, 0)) * CFrame.Angles(0, 0, math.pi * .5),
			Vector3.new(8, 3.4, 3.4), C.Metal, Enum.Material.Metal)
		pipe.Shape = Enum.PartType.Cylinder
	end

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

-- A corridor is two dry side walkways with a recessed water channel between
-- them — you wade the channel or keep your feet dry on the walkways, exactly
-- like the reference photos. Drainable corridors are deeper: flooded you swim
-- across the surface, drained you take the steps down and walk the channel.
local function makeCorridor(parent, waterRegions, layout, corridor, doorFolder)
	local width = corridor.Width
	local walkway = Configuration.CorridorWalkwayWidth
	local channelWidth = width - walkway * 2
	local height = Configuration.CorridorHeight
	local from, to = corridor.From, corridor.To
	local length = math.abs(to - from) + 4
	local mid = (from + to) * .5
	local alongX = corridor.Axis == "X"
	local center = alongX and Vector3.new(mid, 0, corridor.Cross)
		or Vector3.new(corridor.Cross, 0, mid)
	local channelDepth = corridor.DrainGroup and Configuration.DrainableCorridorDepth
		or Configuration.CorridorChannelDepth

	local function oriented(x, z)
		-- x = along the corridor, z = across it.
		if alongX then return Vector3.new(x, 0, z) end
		return Vector3.new(z, 0, x)
	end
	local function orientedSize(along, y, across)
		if alongX then return Vector3.new(along, y, across) end
		return Vector3.new(across, y, along)
	end

	-- Side walkways at floor level.
	for _, side in ipairs({-1, 1}) do
		local strip = tiledPart(parent, "Level 3 Corridor Walkway",
			CFrame.new(center + oriented(0, side * (width - walkway) * .5) + Vector3.new(0, -.35, 0)),
			orientedSize(length, .7, walkway), C.TileWarm, {Enum.NormalId.Top}, 7)
		strip.CanCollide = true
		-- Channel lip under the walkway's inner edge, down to the channel floor.
		local lip = tiledPart(parent, "Level 3 Corridor Channel Lip",
			CFrame.new(center + oriented(0, side * channelWidth * .5)
				+ Vector3.new(0, -channelDepth * .5, 0)),
			orientedSize(length, channelDepth, 1.4), C.TileCool, nil, 8)
		lip.CanCollide = true
	end

	-- Channel floor.
	local channelFloor = tiledPart(parent, "Level 3 Corridor Channel Floor",
		CFrame.new(center + Vector3.new(0, -channelDepth - .6, 0)),
		orientedSize(length, 1.2, channelWidth), C.TileCool, {Enum.NormalId.Top}, 8)
	channelFloor.CanCollide = true

	-- Steps into the channel at both ends so a drained corridor is walkable
	-- end to end (and a flooded shallow one is easy to wade out of).
	if channelDepth > 2 then
		local stepRun, stepRise = 1.4, .92
		local stepCount = math.ceil(channelDepth / stepRise)
		for _, endSign in ipairs({-1, 1}) do
			local outward = oriented(endSign, 0)
			local base = center + oriented(endSign * (length * .5 - 2 - stepCount * stepRun), 0)
				+ Vector3.new(0, -channelDepth, 0)
			makeStairFlight(parent, base, outward, channelWidth - 4, stepCount,
				"Level 3 Corridor " .. corridor.Index .. " Channel Steps", stepRun, stepRise)
		end
	end

	-- Walls and ceiling.
	for _, side in ipairs({-1, 1}) do
		local wall = tiledPart(parent, "Level 3 Corridor Wall",
			CFrame.new(center + oriented(0, side * width * .5) + Vector3.new(0, height * .5 - 2, 0)),
			orientedSize(length, height + 4, Configuration.WallThickness), C.TileCool, nil, 7)
		wall.CanCollide = true
	end
	local ceiling = tiledPart(parent, "Level 3 Corridor Ceiling",
		CFrame.new(center + Vector3.new(0, height + 1, 0)),
		orientedSize(length, 2, width), C.TileCool, {Enum.NormalId.Bottom}, 9)
	ceiling.CanCollide = true

	-- Arches spanning ACROSS the corridor (you walk through them), grounded on
	-- the walkways, sized to clear the walls.
	local ribs = math.max(2, math.floor(length / 30))
	local archRadius = width * .5 - 3.5
	for rib = 1, ribs do
		local t = rib / (ribs + 1)
		makeArchRing(parent, center + oriented(from - mid + (to - from) * t, 0),
			alongX, corridor.Index .. "." .. rib, archRadius)
	end

	makeCeilingPanel(parent, center, "Corridor " .. corridor.Index,
		orientedSize(math.min(length * .55, 40), .55, 6), 0, height)

	-- Channel water.
	local surfaceY = .1
	local waterHeight = channelDepth + surfaceY - .15
	local region = {
		CFrame = CFrame.new(center + Vector3.new(0, surfaceY - waterHeight * .5, 0)),
		Size = alongX and Vector3.new(length - 4, waterHeight, channelWidth - 3)
			or Vector3.new(channelWidth - 3, waterHeight, length - 4),
		Label = "Corridor " .. corridor.Index,
	}
	Terrain:FillBlock(region.CFrame, region.Size, Enum.Material.Water)
	table.insert(waterRegions, region)

	-- Pressure doors seal the grand slide hall until every pump runs.
	local door
	if corridor.Kind == "PressureDoor" then
		local doorCenter = center + oriented(to - mid, 0) + Vector3.new(0, height * .5 - 2, 0)
		door = part(doorFolder, "Level 3 Pressure Door " .. corridor.Index,
			CFrame.new(doorCenter), orientedSize(2.2, height + 4, width), C.Locked,
			Enum.Material.DiamondPlate)
		door.CanCollide = true
		door:SetAttribute("Level3_CorridorIndex", corridor.Index)
		local stripe = part(doorFolder, "Level 3 Pressure Door Stripe " .. corridor.Index,
			CFrame.new(doorCenter + Vector3.new(0, 4, 0)),
			orientedSize(2.4, 1.2, width - 4), C.Locked, Enum.Material.Neon)
		stripe.CanCollide = false
	end

	return {Corridor = corridor, Water = region, Door = door, Center = center}
end

-- ── arrival ─────────────────────────────────────────────────────────────────

-- A real arrival: raised tiled platform, glowing ring, signage, and steps down
-- into the concourse. The spawn markers sit flush on the platform so the
-- collidable ElevatorSpawn plate never floats in the air.
local function makeArrivalConcourse(parent, hall)
	local center = hall.Center
	local arrivalFolder = folder(parent, "Level 3 Arrival Concourse")

	local platformHeight = 1.2
	local platform = tiledPart(arrivalFolder, "Level 3 Arrival Platform",
		CFrame.new(center + Vector3.new(0, platformHeight * .5, 0)),
		Vector3.new(26, platformHeight, 26), C.TileWarm, Enum.NormalId:GetEnumItems(), 7)
	platform.CanCollide = true

	local ring = part(arrivalFolder, "Level 3 Arrival Ring",
		CFrame.new(center + Vector3.new(0, platformHeight + .08, 0)),
		Vector3.new(22, .16, 22), C.Emergency, Enum.Material.Neon, .35)
	ring.CanCollide = false

	for _, direction in ipairs({Vector3.new(1, 0, 0), Vector3.new(-1, 0, 0), Vector3.new(0, 0, 1), Vector3.new(0, 0, -1)}) do
		makeStairFlight(arrivalFolder, center + direction * 17.4, -direction, 12, 2,
			"Level 3 Arrival Steps", 2.0, .6)
	end

	-- Signage wall on the north side.
	local sign = tiledPart(arrivalFolder, "Level 3 Arrival Sign Wall",
		CFrame.new(Vector3.new(center.X, 9, hall.MinZ + 4)),
		Vector3.new(34, 14, 1.6), C.TileCool, nil, 7)
	sign.CanCollide = true
	local signGui = Instance.new("SurfaceGui")
	signGui.Name = "Level 3 Arrival Sign"
	signGui.Face = Enum.NormalId.Back
	signGui.CanvasSize = Vector2.new(680, 280)
	signGui.Parent = sign
	local signText = Instance.new("TextLabel")
	signText.Size = UDim2.fromScale(1, 1)
	signText.BackgroundTransparency = 1
	signText.Font = Enum.Font.GothamBold
	signText.TextScaled = true
	signText.TextColor3 = Color3.fromRGB(36, 104, 132)
	signText.Text = "ZYNTRA AQUATICS  •  SUBLEVEL 3\nSUNKEN LEISURE COMPLEX"
	signText.Parent = signGui

	makeCeilingPanel(arrivalFolder, center, "Arrival", Vector3.new(30, .55, 12), 0, hallHeight(hall))
	return platformHeight
end

-- GameManager still requires these named objects. The elevator stub is
-- mandatory: connectElevator blocks forever on a missing DoorL/DoorR.
local function makeCompatibilityArrival(world, arrivalPosition, platformHeight)
	local topY = platformHeight or 0

	local marker = part(world, "Level 3 Arrival Spawn",
		CFrame.new(arrivalPosition + Vector3.new(0, topY + .3, 0)), Vector3.new(9, .4, 9),
		C.Emergency, Enum.Material.Neon, 1)
	marker.CanCollide = false
	marker.CanTouch = false

	local elevator = Instance.new("Model")
	elevator.Name = "Elevator"
	elevator:SetAttribute("Level3_CompatibilityMarker", true)
	elevator.Parent = workspace
	local shell = part(elevator, "Level 3 Arrival Elevator Shell",
		CFrame.new(arrivalPosition + Vector3.new(0, topY + 5, 0)), Vector3.new(18, 10, 18),
		C.TileWarm, Enum.Material.SmoothPlastic, 1)
	shell.CanCollide = false
	shell.CanTouch = false
	local doorLeft = part(elevator, "DoorL",
		CFrame.new(arrivalPosition + Vector3.new(-4.5, topY + 5, 8.8)), Vector3.new(8.5, 10, .6),
		C.Metal, Enum.Material.Metal, 1)
	local doorRight = part(elevator, "DoorR",
		CFrame.new(arrivalPosition + Vector3.new(4.5, topY + 5, 8.8)), Vector3.new(8.5, 10, .6),
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

	-- placeSafelyInElevator writes CanCollide = true onto ElevatorSpawn, so it
	-- sits flush on the platform where an invisible plate cannot be felt.
	local mazeStart = compatibilityMarker("MazeStart",
		arrivalPosition + Vector3.new(0, topY + .2, 0), Vector3.new(4, .2, 4))
	local elevatorSpawn = compatibilityMarker("ElevatorSpawn",
		arrivalPosition + Vector3.new(0, topY + .12, 0), Vector3.new(11, .2, 11))
	local entityStart = compatibilityMarker("EntityStart",
		arrivalPosition + Vector3.new(0, -40, 0), Vector3.new(4, .2, 4))

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

	local bounds = layout.Bounds
	local worldCenterX = (bounds.MinX + bounds.MaxX) * .5
	local worldCenterZ = (bounds.MinZ + bounds.MaxZ) * .5
	local extent = Configuration.ComplexExtent

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

	local tallest = Configuration.GrandSlideHallHeight
	local waterRegions = {}

	local floor = tiledPart(containment, "Level 3 Sealed Foundation",
		CFrame.new(worldCenterX, -36, worldCenterZ),
		Vector3.new(extent + 140, 4, extent + 140), C.DarkGrout, {Enum.NormalId.Top}, 12)
	floor.CanCollide = true

	-- Corridor doorways through hall walls.
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

	-- The grand hall's slide-deck data is needed before its walls are built,
	-- because the exit flume punches a hole through its east wall.
	local slideDecks = {}
	local exit
	local grand = layout.GrandSlideHall

	local built = 0
	for _, hall in ipairs(layout.Halls) do
		local hallModel = Instance.new("Model")
		hallModel.Name = hall.Id .. " " .. (hall.Archetype or "Hall")
		hallModel:SetAttribute("Level3_Role", hall.Role)
		hallModel:SetAttribute("Level3_PoolType", hall.PoolType)
		hallModel:SetAttribute("Level3_Archetype", hall.Archetype)
		hallModel:SetAttribute("Level3_GraphDepth", hall.GraphDepth)
		hallModel:SetAttribute("Level3_Height", hallHeight(hall))
		if hall.KidsColorIndex then
			hallModel:SetAttribute("Level3_KidsColor", kidsPalette(hall).Name)
		end
		hallModel.Parent = hallsFolder

		makeHallFloor(hallModel, hall)
		makeHallCeiling(hallModel, hall)

		if hall.Role == "Kids Area" then
			makeKidsHall(kidsFolder, waterRegions, hall, hall.KidsIndex or hall.Index)
		elseif hall.Role == "Slide Hall" then
			slideDecks[hall.SlideHallIndex] = makeSlideHall(slideFolder, waterRegions, hall, hall.SlideHallIndex)
			if hall.IsGrand then
				exit = makeExitFlume(geometry, layout, hall, slideDecks[hall.SlideHallIndex])
			end
		else
			local basinWidth, basinDepth, poolDepth = basinFor(hall)
			if basinWidth then
				makeBasin(hallModel, waterRegions, hall.Center, basinWidth, basinDepth, poolDepth,
					hall.PoolType)
			end

			local archetype = hall.Archetype or ""
			local height = hallHeight(hall)
			if archetype == "Pillar Basin" or archetype == "Diving Well" then
				local offsetX = math.min(hall.Width * .26, (basinWidth or hall.Width) * .5 - 11)
				local offsetZ = math.min(hall.Depth * .26, (basinDepth or hall.Depth) * .5 - 11)
				for _, sx in ipairs({-1, 1}) do
					for _, sz in ipairs({-1, 1}) do
						makeColumn(hallModel,
							hall.Center + Vector3.new(sx * offsetX, -(poolDepth or 0), sz * offsetZ),
							height + (poolDepth or 0), 7)
					end
				end
			elseif archetype == "Arch Tunnel" or archetype == "Ring Corridor" then
				local acrossZ = hall.Width >= hall.Depth
				local along = acrossZ and hall.Width or hall.Depth
				local rings = math.clamp(math.floor(along / 44), 2, 5)
				local radius = math.min((acrossZ and hall.Depth or hall.Width) * .5 - 8, height - 6, 20)
				for ring = 1, rings do
					local t = ring / (rings + 1)
					local position = acrossZ
						and Vector3.new(hall.MinX + along * t, 0, hall.Center.Z)
						or Vector3.new(hall.Center.X, 0, hall.MinZ + along * t)
					makeArchRing(hallModel, position, acrossZ, hall.Index .. "." .. ring, radius)
				end
			elseif archetype == "Spiral Stair Well" then
				makeSpiralStair(hallModel, hall.Center, -1, height - 12, 13, "Level 3 Stair Well " .. hall.Index)
			elseif archetype == "Skylight Hall" then
				makeSkylight(hallModel, hall.Center, hall.Width, hall.Depth, hall.Index, height)
			elseif archetype == "Curved Gallery" then
				local count = math.clamp(math.floor(hall.Width / 46), 3, 7)
				local rowZ = hall.Center.Z - math.min(hall.Depth * .28, (basinDepth or hall.Depth) * .5 - 10)
				for column = 1, count do
					local x = hall.Center.X - hall.Width * .5 + (column / (count + 1)) * hall.Width
					makeColumn(hallModel, Vector3.new(x, -(poolDepth or 0), rowZ),
						height + (poolDepth or 0), 6)
				end
			elseif archetype == "Pump Station" then
				-- geometry handled by makePumpStation below
			elseif archetype == "Arrival Concourse" then
				-- geometry handled by makeArrivalConcourse below
			elseif archetype == "Locker Row" or archetype == "Dry Gallery" then
				for bench = -1, 1 do
					local benchPart = tiledPart(hallModel, "Level 3 Tiled Bench",
						CFrame.new(hall.Center + Vector3.new(bench * math.min(30, hall.Width * .25), 1.1, 0)),
						Vector3.new(math.min(22, hall.Width * .2), 2.2, 5), C.TileWarm, nil, 7)
					benchPart.CanCollide = true
				end
			elseif basinWidth and (archetype == "Channel Junction" or archetype == "Flooded Gallery"
				or archetype == "Bright Basin" or archetype == "Low Water Hall") then
				-- A bridge across the water, clamped inside the basin.
				local alongX2 = hall.Orientation ~= "NorthSouth"
				local span = alongX2 and basinWidth or basinDepth
				local bridge = tiledPart(hallModel, "Level 3 Basin Bridge",
					CFrame.new(hall.Center + Vector3.new(0, .5, 0)),
					alongX2 and Vector3.new(span + 8, 1.1, 9) or Vector3.new(9, 1.1, span + 8),
					C.TileWarm, Enum.NormalId:GetEnumItems(), 9)
				bridge.CanCollide = true
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

		for corner, sign in ipairs({
			Vector3.new(-.32, 0, -.32), Vector3.new(.32, 0, -.32),
			Vector3.new(-.32, 0, .32), Vector3.new(.32, 0, .32),
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

	-- Hall walls. Built after the exit flume exists so the grand hall's east
	-- wall can take the flume pass-through hole.
	for _, hall in ipairs(layout.Halls) do
		local hallModel
		for _, child in ipairs(hallsFolder:GetChildren()) do
			if child.Name:sub(1, #hall.Id) == hall.Id then hallModel = child break end
		end
		local doors = doorsByHall[hall.Index]
		local height = hallHeight(hall)
		local eastFlumeGap = (hall.IsGrand and exit) and exit.HallWallGap or nil
		makeWallWithGaps(hallModel, hall, "Level 3 Hall West Wall", "Z", hall.MinX, hall.MinZ, hall.MaxZ, doors.West, height)
		makeWallWithGaps(hallModel, hall, "Level 3 Hall East Wall", "Z", hall.MaxX, hall.MinZ, hall.MaxZ, doors.East, height, nil, eastFlumeGap)
		makeWallWithGaps(hallModel, hall, "Level 3 Hall North Wall", "X", hall.MinZ, hall.MinX, hall.MaxX, doors.North, height)
		makeWallWithGaps(hallModel, hall, "Level 3 Hall South Wall", "X", hall.MaxZ, hall.MinX, hall.MaxX, doors.South, height)
	end
	task.wait()

	-- Corridors.
	local corridorRecords = {}
	local drains = {}
	local pressureDoors = {}
	for _, corridor in ipairs(layout.Corridors) do
		local record = makeCorridor(corridorsFolder, waterRegions, layout, corridor, doorFolder)
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

	-- Arrival.
	local platformHeight = makeArrivalConcourse(geometry, layout.Arrival)
	local arrival = makeCompatibilityArrival(world, layout.Arrival.Center, platformHeight)

	-- Entity den marker: reserved space, nothing spawns here yet.
	local den = part(entityFolder, "Level 3 Entity Den Spawn",
		CFrame.new(layout.EntityDen.Center + Vector3.new(0, 3, 0)), Vector3.new(10, .4, 10),
		C.Void, Enum.Material.Neon, 1)
	den.CanCollide = false
	den.CanTouch = false
	den:SetAttribute("Level3_HallId", layout.EntityDen.Id)
	entityFolder:SetAttribute("Level3_DenPosition", layout.EntityDen.Center)
	arrival.EntityStart.CFrame = CFrame.new(layout.EntityDen.Center + Vector3.new(0, 4, 0))

	-- Outer shell: four full walls (east takes the flume pass-through), a roof
	-- and the foundation. Fully sealed — no daylight anywhere inside.
	local shellHalfX = extent * .5 + 60
	local shellHeight = tallest + 12
	local wallTall = shellHeight + 44
	local wallY = shellHeight * .5 - 20
	tiledPart(containment, "Level 3 Outer North Containment Wall",
		CFrame.new(worldCenterX, wallY, worldCenterZ - shellHalfX),
		Vector3.new(extent + 140, wallTall, 8), C.DarkGrout, nil, 12).CanCollide = true
	tiledPart(containment, "Level 3 Outer South Containment Wall",
		CFrame.new(worldCenterX, wallY, worldCenterZ + shellHalfX),
		Vector3.new(extent + 140, wallTall, 8), C.DarkGrout, nil, 12).CanCollide = true
	tiledPart(containment, "Level 3 Outer West Containment Wall",
		CFrame.new(worldCenterX - shellHalfX, wallY, worldCenterZ),
		Vector3.new(8, wallTall, extent + 140), C.DarkGrout, nil, 12).CanCollide = true
	makeWallWithGaps(containment, nil, "Level 3 Outer East Containment Wall", "Z",
		worldCenterX + shellHalfX, worldCenterZ - shellHalfX - 6, worldCenterZ + shellHalfX + 6,
		nil, shellHeight + 24, -36, exit and exit.ShellGap or nil)
	local roof = tiledPart(containment, "Level 3 Sealed Ceiling",
		CFrame.new(worldCenterX, shellHeight + 24, worldCenterZ),
		Vector3.new(extent + 150, 4, extent + 150), C.DarkGrout, {Enum.NormalId.Bottom}, 12)
	roof.CanCollide = true

	-- Backdrop box shields the flume hole from the void; the catch room sits
	-- just past it under its own sealed roof.
	if exit then
		local backdrop = tiledPart(containment, "Level 3 Exit Duct Backdrop",
			CFrame.new(exit.EndPosition.X + 26, 24, exit.EndPosition.Z),
			Vector3.new(4, 130, 96), C.DarkGrout, nil, 12)
		backdrop.CanCollide = true
		local ductRoof = tiledPart(containment, "Level 3 Exit Duct Roof",
			CFrame.new(worldCenterX + shellHalfX + 24, 90, exit.EndPosition.Z),
			Vector3.new(52, 4, 96), C.DarkGrout, {Enum.NormalId.Bottom}, 12)
		ductRoof.CanCollide = true
	end

	local terrainCenter = Vector3.new(worldCenterX, -16, worldCenterZ)
	local terrainSize = Vector3.new(extent + 700, 200, extent + 700)
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
		WaterRegions = waterRegions,
		TerrainCenter = terrainCenter,
		TerrainSize = terrainSize,
		Generation = generation,
	}
end

return WorldBuilder
