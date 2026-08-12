-- Level 2 World Builder
-- Turns a Level 2 layout (variable-size halls + corridors) into geometry.
--
-- Shared with Level 2 on purpose, and nothing else: the tile texture asset and
-- the terrain water appearance. Everything structural here is Level 2's own.
--
-- Design language (reference photos): WATER COVERS THE FLOOR WALL-TO-WALL in
-- every pool hall and corridor — no basins, no dry walkway rings. Bright
-- natural sunlight enters through real skylight slots cut in the ceilings
-- (the outer roof is translucent glass that casts no shadow), tiled columns
-- and arch tunnels rise straight out of the water, and stairs descend into
-- the deeper halls.

local ReplicatedStorage = game:GetService("ReplicatedStorage")
local Terrain = workspace.Terrain

local Configuration = require(script.Parent:WaitForChild("Level 2 Configuration"))

local WorldBuilder = {}
local C = Configuration.Colors

-- The two things Level 2 borrows from Level 2.
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
		texture.Name = "Level 2 Tile Texture"
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

local function surfaceFor(hall, parent, name, cframe, size, tileColor, faces, studs)
	if isKids(hall) then
		return part(parent, name, cframe, size, kidsPalette(hall).Color, Enum.Material.SmoothPlastic)
	end
	return tiledPart(parent, name, cframe, size, tileColor, faces, studs)
end

-- Water depth for a hall, or nil for a genuinely dry room. Water is
-- wall-to-wall: the whole floor is recessed by this amount and flooded.
local function hallWaterDepth(hall)
	if hall.Role == "Kids Area" or hall.Role == "Arrival"
		or hall.Role == "Pump Station" or hall.Role == "Exit" then
		return nil
	end
	if hall.Role == "Slide Hall" then return Configuration.SlidePoolDepth end
	if hall.PoolType == "Deep" then return Configuration.DeepPoolDepth end
	return Configuration.ShallowPoolDepth
end

-- ── walls ───────────────────────────────────────────────────────────────────

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
				-- Door sill below the waterline so the wall still seals the
				-- water column under the doorway threshold.
				if bottomY < -4 then
					surfaceFor(hall, parent, name .. " Sill",
						CFrame.new(positionFor((gapLow + gapHigh) * .5, (bottomY - 4) * .5)),
						sizeFor(span, math.abs(bottomY) - 4), wallColor, nil, 7)
				end
			else
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

local waterRegionsRef -- set per Build

local function addWater(center, size, label)
	local region = {CFrame = CFrame.new(center), Size = size, Label = label}
	Terrain:FillBlock(region.CFrame, region.Size, Enum.Material.Water)
	table.insert(waterRegionsRef, region)
	return region
end

-- Flooded halls: one recessed slab across the WHOLE footprint, water on top of
-- it wall-to-wall. Dry halls: a plain slab at walking height.
local function makeHallFloor(parent, hall)
	local depth = hallWaterDepth(hall)
	if not depth then
		local floorColor = isKids(hall) and kidsPalette(hall).Accent or C.TileWarm
		local slab = surfaceFor(hall, parent, "Level 2 Hall Floor",
			CFrame.new(hall.Center + Vector3.new(0, -.35, 0)),
			Vector3.new(hall.Width, .7, hall.Depth), floorColor, {Enum.NormalId.Top}, 7)
		slab.CanCollide = true
		return nil
	end
	local slab = tiledPart(parent, "Level 2 Hall Water Floor",
		CFrame.new(hall.Center + Vector3.new(0, -depth - .6, 0)),
		Vector3.new(hall.Width, 1.2, hall.Depth), C.TileCool, {Enum.NormalId.Top}, 10)
	slab.CanCollide = true
	local waterHeight = depth + .1
	addWater(hall.Center + Vector3.new(0, .1 - waterHeight * .5, 0),
		Vector3.new(hall.Width - 3, waterHeight, hall.Depth - 3), hall.Id)
	return depth
end

-- Skylight slot layout for a hall — shared by the ceiling builder and the
-- light placer, so a ceiling light can never be built inside a skylight
-- opening (they used to coincide whenever the slot and light grids aligned).
local function skylightSlotsFor(hall)
	if isKids(hall) then return {}, 0 end
	local slots = math.clamp(math.floor(hall.Width / 70), 1, 4)
	local xs = {}
	for slot = 1, slots do
		table.insert(xs, hall.MinX + (slot / (slots + 1)) * hall.Width)
	end
	return xs, 11
end

local function overlapsSkylight(hall, x, width)
	local xs, slotWidth = skylightSlotsFor(hall)
	for _, slotX in ipairs(xs) do
		if math.abs(x - slotX) < (slotWidth + width) * .5 + 1.5 then
			return true
		end
	end
	return false
end

-- Ceilings carry REAL skylight slots: open cuts with translucent glass panes
-- that cast no shadow, so actual sunlight drops into the room and bounces.
local function makeHallCeiling(parent, hall)
	local height = hallHeight(hall)
	local color = isKids(hall) and kidsPalette(hall).Accent or C.TileCool
	if isKids(hall) then
		local slab = part(parent, "Level 2 Hall Ceiling",
			CFrame.new(hall.Center + Vector3.new(0, height + 1, 0)),
			Vector3.new(hall.Width, 2, hall.Depth), color, Enum.Material.SmoothPlastic)
		slab.CanCollide = true
		return
	end

	local xs, slotWidth = skylightSlotsFor(hall)
	table.sort(xs)

	local cursor = hall.MinX
	for _, x in ipairs(xs) do
		local segmentEnd = x - slotWidth * .5
		if segmentEnd - cursor > .5 then
			local slab = tiledPart(parent, "Level 2 Hall Ceiling",
				CFrame.new(Vector3.new((cursor + segmentEnd) * .5, height + 1, hall.Center.Z)),
				Vector3.new(segmentEnd - cursor, 2, hall.Depth), color, {Enum.NormalId.Bottom}, 9)
			slab.CanCollide = true
		end
		-- The glass pane: sunlight passes (CastShadow off), players cannot.
		local pane = part(parent, "Level 2 Skylight Glass",
			CFrame.new(Vector3.new(x, height + 1, hall.Center.Z)),
			Vector3.new(slotWidth, .6, hall.Depth), Color3.fromRGB(248, 246, 236),
			Enum.Material.Glass, .55)
		pane.CanCollide = true
		pane.CastShadow = false
		cursor = x + slotWidth * .5
	end
	if hall.MaxX - cursor > .5 then
		local slab = tiledPart(parent, "Level 2 Hall Ceiling",
			CFrame.new(Vector3.new((cursor + hall.MaxX) * .5, height + 1, hall.Center.Z)),
			Vector3.new(hall.MaxX - cursor, 2, hall.Depth), color, {Enum.NormalId.Bottom}, 9)
		slab.CanCollide = true
	end
end

-- Raised wading pool for the kids wing (water above the floor, no digging).
local function makeRaisedPool(parent, center, width, depth3, palette)
	local wallHeight = 2.4
	local shellBottom = part(parent, "Level 2 Kids Pool Base",
		CFrame.new(center + Vector3.new(0, .15, 0)), Vector3.new(width, .3, depth3),
		palette.Accent, Enum.Material.SmoothPlastic)
	shellBottom.CanCollide = true
	for _, data in ipairs({
		{Vector3.new(-width * .5, wallHeight * .5, 0), Vector3.new(1.2, wallHeight, depth3)},
		{Vector3.new(width * .5, wallHeight * .5, 0), Vector3.new(1.2, wallHeight, depth3)},
		{Vector3.new(0, wallHeight * .5, -depth3 * .5), Vector3.new(width, wallHeight, 1.2)},
		{Vector3.new(0, wallHeight * .5, depth3 * .5), Vector3.new(width, wallHeight, 1.2)},
	}) do
		part(parent, "Level 2 Kids Pool Wall", CFrame.new(center + data[1]), data[2],
			palette.Color, Enum.Material.SmoothPlastic).CanCollide = true
	end
	part(parent, "Level 2 Kids Pool Step",
		CFrame.new(center + Vector3.new(0, .6, depth3 * .5 + 2)), Vector3.new(10, 1.2, 3.4),
		palette.Accent, Enum.Material.SmoothPlastic).CanCollide = true
	addWater(center + Vector3.new(0, wallHeight * .5 + .2, 0),
		Vector3.new(width - 3, wallHeight - .6, depth3 - 3), "Kids Pool")
end

-- ── set pieces ──────────────────────────────────────────────────────────────

local function makeColumn(parent, position, height, radius)
	radius = radius or 6
	local column = tiledPart(parent, "Level 2 Tiled Column",
		CFrame.new(position + Vector3.new(0, height * .5 - 1, 0)) * CFrame.Angles(0, 0, math.pi * .5),
		Vector3.new(height, radius, radius), C.TileWarm, nil, 9)
	column.Shape = Enum.PartType.Cylinder
	column.CanCollide = true
	return column
end

-- Rows of columns rising out of the water — the reference-photo colonnades.
local function makeColonnade(parent, hall, depth, rows)
	local alongX = hall.Width >= hall.Depth
	local long = alongX and hall.Width or hall.Depth
	local short = alongX and hall.Depth or hall.Width
	local count = math.clamp(math.floor(long / 38), 2, 8)
	local height = hallHeight(hall)
	for _, rowOffset in ipairs(rows) do
		local offset = rowOffset * short * .5
		for column = 1, count do
			local along = (column / (count + 1) - .5) * (long - 40)
			local position = alongX
				and hall.Center + Vector3.new(along, -(depth or 0), offset)
				or hall.Center + Vector3.new(offset, -(depth or 0), along)
			makeColumn(parent, position, height + (depth or 0), 5.5)
		end
	end
end

-- An archway: contiguous tangent segments built with lookAt between successive
-- ring points, so the orientation can never be wrong. Classic half arch whose
-- feet run DOWN past the water surface into the floor slab, so it never
-- floats. `acrossZ` = the ring spans across Z; you walk through along X.
local function makeArchSpan(parent, center, acrossZ, index, radius, floorDepth)
	radius = math.max(6, radius)
	floorDepth = floorDepth or 0
	local dip = math.asin(math.clamp((floorDepth + 2.2) / radius, 0, .55))
	local angleFrom, angleTo = -dip, math.pi + dip
	local steps = math.max(14, math.floor(radius * 1.9))
	local arcCenter = center + Vector3.new(0, 1, 0)
	local function pointAt(a)
		if acrossZ then
			return arcCenter + Vector3.new(0, math.sin(a) * radius, math.cos(a) * radius)
		end
		return arcCenter + Vector3.new(math.cos(a) * radius, math.sin(a) * radius, 0)
	end
	for step = 0, steps - 1 do
		local a0 = angleFrom + (angleTo - angleFrom) * step / steps
		local a1 = angleFrom + (angleTo - angleFrom) * (step + 1) / steps
		local from = pointAt(a0)
		local to = pointAt(a1)
		local mid = (from + to) * .5
		local radial = (mid - arcCenter)
		local up = radial.Magnitude > .01 and radial.Unit or Vector3.yAxis
		local rib = part(parent, "Level 2 Arch Rib " .. index,
			CFrame.lookAt(mid, to, up),
			Vector3.new(3.2, 2.2, (to - from).Magnitude + .9), C.TileWarm)
		addTexture(rib, Enum.NormalId:GetEnumItems(), 7)
	end
end

-- The continuous shell that CONNECTS the arch ribs: long tiled strips running
-- the passage's whole length, one per angular step, sitting just behind the
-- ribs — together they form the half cylinder you walk through, its feet
-- submerged like the ribs'.
local function makeBarrelVault(parent, center, acrossZ, index, radius, length, floorDepth)
	radius = math.max(6, radius)
	floorDepth = floorDepth or 0
	local dip = math.asin(math.clamp((floorDepth + 2.2) / radius, 0, .55))
	local angleFrom, angleTo = -dip, math.pi + dip
	local steps = math.max(12, math.floor(radius * 1.5))
	local arcCenter = center + Vector3.new(0, 1, 0)
	local axis = acrossZ and Vector3.new(1, 0, 0) or Vector3.new(0, 0, 1)
	for step = 0, steps - 1 do
		local a0 = angleFrom + (angleTo - angleFrom) * step / steps
		local a1 = angleFrom + (angleTo - angleFrom) * (step + 1) / steps
		local am = (a0 + a1) * .5
		local offset = acrossZ
			and Vector3.new(0, math.sin(am) * radius, math.cos(am) * radius)
			or Vector3.new(math.cos(am) * radius, math.sin(am) * radius, 0)
		local mid = arcCenter + offset
		local up = offset.Magnitude > .01 and offset.Unit or Vector3.yAxis
		local chord = 2 * radius * math.sin((a1 - a0) * .5) + .9
		local strip = part(parent, "Level 2 Vault Strip " .. index,
			CFrame.lookAt(mid, mid + axis, up),
			Vector3.new(chord, 1.6, length), C.TileCool)
		addTexture(strip, {Enum.NormalId.Top, Enum.NormalId.Bottom}, 8)
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

local function makeCeilingPanel(parent, position, index, panelSize, yaw, height)
	local y = (height or Configuration.WallHeight) - .7
	panelSize = panelSize or Vector3.new(30, .55, 9)
	local fixtureCFrame = CFrame.new(position.X, y, position.Z) * CFrame.Angles(0, yaw or 0, 0)
	part(parent, "Level 2 Ceiling Light Frame " .. index, fixtureCFrame, panelSize, C.Metal, Enum.Material.Metal)
	local diffuserSize = Vector3.new(math.max(2, panelSize.X - 3), .18, math.max(2, panelSize.Z - 3))
	local diffuser = part(parent, "Level 2 Ceiling Light Diffuser " .. index,
		fixtureCFrame * CFrame.new(0, -.34, 0), diffuserSize, C.Light, Enum.Material.Neon, .08)
	diffuser.CanCollide = false
	local light = Instance.new("SurfaceLight")
	light.Name = "Level 2 Ceiling Surface Light"
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
	-- Halls with skylights are lit by the SUN alone — no artificial fixtures.
	-- Ceiling panels only exist where there is no skylight: the kids wing
	-- (solid painted ceilings), corridors and the gateway.
	if #skylightSlotsFor(hall) > 0 then return end
	local height = hallHeight(hall)
	local columns = math.clamp(math.floor(hall.Width / 90), 1, 4)
	local rows = math.clamp(math.floor(hall.Depth / 90), 1, 4)
	local panelWidth = math.min(46, hall.Width * .42)
	for cx = 1, columns do
		for cz = 1, rows do
			local x = hall.Center.X - hall.Width * .5 + (cx / (columns + 1)) * hall.Width
			local z = hall.Center.Z - hall.Depth * .5 + (cz / (rows + 1)) * hall.Depth
			makeCeilingPanel(parent, Vector3.new(x, 0, z),
				index .. "." .. cx .. "." .. cz,
				Vector3.new(panelWidth, .55, 9), 0, height)
		end
	end
end

-- ── tubes and slides ────────────────────────────────────────────────────────

-- Tube from an ordered point list — shared by flumes, the exit slide and the
-- helix slides. Orientation is always lookAt-derived, never trig.
local function makeTubeFromPoints(parent, points, radius, color, name, openTop)
	local sides = Configuration.SlideTubeSides
	local arcWidth = 2 * radius * math.sin(math.pi / sides) * 1.18
	for index = 1, #points - 1 do
		local a, b = points[index], points[index + 1]
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

local function makeSlideTube(parent, p0, p1, p2, p3, radius, color, name, segments, openTop)
	segments = segments or Configuration.SlideSegments
	local points = {}
	for segment = 0, segments do
		table.insert(points, bezier(p0, p1, p2, p3, segment / segments))
	end
	makeTubeFromPoints(parent, points, radius, color, name, openTop)
end

-- A slide that WINDS AROUND a column: helix from a deck-level catwalk down
-- into the water.
local function makeHelixSlide(parent, columnPosition, helixRadius, topY, color, name)
	local turns = 2.1
	local segments = 30
	local points = {}
	for segment = 0, segments do
		local t = segment / segments
		local angle = -math.pi * .5 + t * math.pi * 2 * turns
		local y = topY * (1 - t) + 2.2 * t
		table.insert(points, Vector3.new(
			columnPosition.X + math.cos(angle) * helixRadius,
			y,
			columnPosition.Z + math.sin(angle) * helixRadius))
	end
	makeTubeFromPoints(parent, points, 4.6, color, name, true)
	return points[1]
end

-- A slide hall: wall-to-wall deep water, columns to the roof, a top deck on
-- the north edge with straight parallel flume lanes down into the water, a
-- helix slide wrapping the north-east column, spiral stair + catwalk access.
local function makeSlideHall(parent, hall, index)
	local height = hallHeight(hall)
	local center = hall.Center
	local depth = Configuration.SlidePoolDepth
	local hallFolder = folder(parent, "Level 2 Slide Hall " .. index)
	local radius = Configuration.SlideTubeRadius

	local columnOffsetX = math.min(hall.Width * .30, hall.Width * .5 - 16)
	local columnOffsetZ = math.min(hall.Depth * .30, hall.Depth * .5 - 16)
	for _, sx in ipairs({-1, 1}) do
		for _, sz in ipairs({-1, 1}) do
			makeColumn(hallFolder,
				center + Vector3.new(sx * columnOffsetX, -depth, sz * columnOffsetZ),
				height + depth, 9)
		end
	end

	-- Top deck along the north edge.
	local deckY = height - 22
	local deckDepth = math.min(46, hall.Depth * .3)
	local deckZ = hall.MinZ + deckDepth * .5 + 4
	local deckFront = deckZ + deckDepth * .5
	local deck = tiledPart(hallFolder, "Level 2 Slide Hall Deck",
		CFrame.new(Vector3.new(center.X, deckY, deckZ)),
		Vector3.new(hall.Width - 16, 2, deckDepth), C.TileWarm, Enum.NormalId:GetEnumItems(), 8)
	deck.CanCollide = true

	-- Straight parallel flume lanes: one X offset each, kept for the whole run,
	-- so tubes cannot meet. Lanes that will not fit are skipped, never clamped
	-- onto a neighbour.
	local laneStep = math.max(radius * 2 + 10, math.min(34, hall.Width * .18))
	local laneLimit = hall.Width * .5 - radius - 8
	local mouths = {}
	for slide = 1, Configuration.SlidesPerHall do
		local lane = (slide - (Configuration.SlidesPerHall + 1) * .5) * laneStep
		if math.abs(lane) <= laneLimit then
			local color = Configuration.SlideColors[((index + slide - 2) % #Configuration.SlideColors) + 1]
			local laneX = center.X + lane
			local startPoint = Vector3.new(laneX, deckY + radius + 1, deckFront - 2)
			local p1 = Vector3.new(laneX, deckY - 8, deckFront + hall.Depth * .18)
			local p2 = Vector3.new(laneX, 15, center.Z + hall.Depth * .06)
			local endZ = math.min(center.Z + hall.Depth * .26, hall.MaxZ - radius - 8)
			local p3 = Vector3.new(laneX, 2.5, endZ)
			makeSlideTube(hallFolder, startPoint, p1, p2, p3, radius, color,
				"Level 2 Slide Hall " .. index .. " Flume " .. slide, Configuration.SlideSegments, true)
			local mouth = part(hallFolder, "Level 2 Slide Hall " .. index .. " Flume Mouth " .. slide,
				CFrame.lookAt(startPoint, p1), Vector3.new(radius * 2.4, .8, 3), color,
				Enum.Material.Neon, .35)
			mouth.CanCollide = false
			table.insert(mouths, laneX)
		end
	end

	-- Deck-front rail, segmented around the flume mouths.
	table.sort(mouths)
	local railY = deckY + 1
	local cursor = hall.MinX + 10
	local mouthGap = radius + 3
	for _, mouthX in ipairs(mouths) do
		if mouthX - mouthGap - cursor > 3 then
			makeRail(hallFolder,
				Vector3.new(cursor, railY, deckFront),
				Vector3.new(mouthX - mouthGap, railY, deckFront),
				"Level 2 Slide Hall " .. index .. " Deck")
		end
		cursor = mouthX + mouthGap
	end
	if hall.MaxX - 10 - cursor > 3 then
		makeRail(hallFolder,
			Vector3.new(cursor, railY, deckFront),
			Vector3.new(hall.MaxX - 10, railY, deckFront),
			"Level 2 Slide Hall " .. index .. " Deck")
	end

	-- Helix slide wrapping the north-east column, fed by a catwalk off the deck.
	local helixColumn = center + Vector3.new(columnOffsetX, 0, -columnOffsetZ)
	local helixRadius = math.min(16, hall.MaxX - helixColumn.X - 6)
	if helixRadius >= 12 then
		local helixColor = Configuration.SlideColors[((index + 2) % #Configuration.SlideColors) + 1]
		local helixTop = makeHelixSlide(hallFolder, helixColumn, helixRadius, deckY + 5,
			helixColor, "Level 2 Slide Hall " .. index .. " Helix")
		local catwalk = tiledPart(hallFolder, "Level 2 Slide Hall Helix Catwalk",
			CFrame.new(Vector3.new(helixTop.X, deckY, (deckFront + helixTop.Z) * .5)),
			Vector3.new(7, 2, math.max(4, math.abs(helixTop.Z - deckFront))), C.TileWarm,
			Enum.NormalId:GetEnumItems(), 8)
		catwalk.CanCollide = true
		makeRail(hallFolder,
			Vector3.new(helixTop.X - 3.2, railY, deckFront),
			Vector3.new(helixTop.X - 3.2, railY, helixTop.Z),
			"Level 2 Slide Hall " .. index .. " Helix Catwalk")
	end

	-- Spiral stair in the south-east corner + catwalk along the east wall.
	local spiralCenter = Vector3.new(hall.MaxX - 26, 0, hall.MaxZ - 26)
	makeSpiralStair(hallFolder, spiralCenter, -depth + 1, deckY, 12,
		"Level 2 Slide Hall " .. index .. " Spiral")
	local catwalkZ1 = deckFront
	local eastCatwalk = tiledPart(hallFolder, "Level 2 Slide Hall Catwalk",
		CFrame.new(Vector3.new(hall.MaxX - 12, deckY, (hall.MaxZ - 26 + catwalkZ1) * .5)),
		Vector3.new(8, 2, math.abs(hall.MaxZ - 26 - catwalkZ1)), C.TileWarm,
		Enum.NormalId:GetEnumItems(), 8)
	eastCatwalk.CanCollide = true
	makeRail(hallFolder,
		Vector3.new(hall.MaxX - 16, railY, hall.MaxZ - 26),
		Vector3.new(hall.MaxX - 16, railY, catwalkZ1),
		"Level 2 Slide Hall " .. index .. " Catwalk")

	lightHall(hallFolder, hall, "SlideHall" .. index)

	return {Folder = hallFolder, DeckY = deckY, DeckZ = deckZ, DeckDepth = deckDepth}
end

-- Exit flume off the grand hall's top deck, east through matching wall holes,
-- into the sealed Level 3 gateway.
local function makeExitFlume(parent, layout, hall, deck)
	local boundsMaxX = layout.Bounds.MaxX
	local shellX = boundsMaxX + 60
	local startPoint = Vector3.new(hall.MaxX - 14, deck.DeckY + 9, deck.DeckZ)
	local run = (shellX + 34) - startPoint.X
	local p1 = startPoint + Vector3.new(run * .35, -4, 0)
	local p2 = startPoint + Vector3.new(run * .8, -12, 0)
	local p3 = Vector3.new(shellX + 34, 4, deck.DeckZ)

	makeSlideTube(parent, startPoint, p1, p2, p3, 8, C.TileCool, "Level 2 Exit Flume", 30, false)

	local mouth = part(parent, "Level 2 Exit Flume Mouth", CFrame.lookAt(startPoint, p1),
		Vector3.new(20, 20, 1.4), C.Emergency, Enum.Material.Neon, .55)
	mouth.CanCollide = false

	-- Sealed GATEWAY chamber: the placeholder for the Level 3 transition.
	local catchCenter = p3 + Vector3.new(24, 2, 0)
	local catchSize = 48
	local gatewayHeight = 22
	tiledPart(parent, "Level 2 Gateway Floor",
		CFrame.new(catchCenter + Vector3.new(0, -6, 0)),
		Vector3.new(catchSize, 1.5, catchSize), C.TileWarm, {Enum.NormalId.Top}, 9)
	tiledPart(parent, "Level 2 Gateway Ceiling",
		CFrame.new(catchCenter + Vector3.new(0, gatewayHeight - 5, 0)),
		Vector3.new(catchSize, 1.5, catchSize), C.TileCool, {Enum.NormalId.Bottom}, 9)
	for _, data in ipairs({
		{Vector3.new(-catchSize * .5, gatewayHeight * .5 - 6, 0), Vector3.new(1.5, gatewayHeight, catchSize)},
		{Vector3.new(0, gatewayHeight * .5 - 6, -catchSize * .5), Vector3.new(catchSize, gatewayHeight, 1.5)},
		{Vector3.new(0, gatewayHeight * .5 - 6, catchSize * .5), Vector3.new(catchSize, gatewayHeight, 1.5)},
	}) do
		tiledPart(parent, "Level 2 Gateway Wall", CFrame.new(catchCenter + data[1]), data[2],
			C.TileCool, nil, 9)
	end

	tiledPart(parent, "Level 2 Gateway East Wall",
		CFrame.new(catchCenter + Vector3.new(catchSize * .5, gatewayHeight * .5 - 6, 0)),
		Vector3.new(1.5, gatewayHeight, catchSize), C.TileCool, nil, 9)
	local bulkhead = part(parent, "Level 2 Gateway Level 3 Bulkhead",
		CFrame.new(catchCenter + Vector3.new(catchSize * .5 - 1.6, 4, 0)),
		Vector3.new(2, 18, 22), C.Metal, Enum.Material.DiamondPlate)
	bulkhead.CanCollide = true
	local stripe = part(parent, "Level 2 Gateway Bulkhead Stripe",
		bulkhead.CFrame + Vector3.new(-1.2, 7, 0), Vector3.new(.3, 1.4, 20), C.Locked, Enum.Material.Neon)
	stripe.CanCollide = false
	local bulkheadGui = Instance.new("SurfaceGui")
	bulkheadGui.Name = "Level 2 Gateway Sign"
	bulkheadGui.Face = Enum.NormalId.Left
	bulkheadGui.CanvasSize = Vector2.new(560, 420)
	bulkheadGui.Parent = bulkhead
	local bulkheadText = Instance.new("TextLabel")
	bulkheadText.Size = UDim2.fromScale(1, 1)
	bulkheadText.BackgroundTransparency = 1
	bulkheadText.Font = Enum.Font.GothamBold
	bulkheadText.TextScaled = true
	bulkheadText.TextColor3 = Color3.fromRGB(255, 226, 140)
	bulkheadText.Text = "SUBLEVEL 3\nACCESS PENDING\n\nAWAITING PRESSURE\nCERTIFICATION"
	bulkheadText.Parent = bulkheadGui

	makeCeilingPanel(parent, catchCenter, "Gateway", Vector3.new(30, .55, 10), 0, gatewayHeight - 6)

	local safeSpawn = part(parent, "Level 2 Exit Safe Spawn",
		CFrame.new(catchCenter + Vector3.new(0, -4.9, 0)), Vector3.new(7, .4, 7),
		C.Emergency, Enum.Material.Neon, 1)
	safeSpawn.CanCollide = false
	safeSpawn.CanTouch = false

	local trigger = part(parent, "Level 2 Exit Trigger",
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
		HallWallGap = {center = deck.DeckZ, width = 30, bottom = deck.DeckY - 10, top = deck.DeckY + 24},
		ShellGap = {center = deck.DeckZ, width = 40, bottom = -10, top = deck.DeckY + 8},
	}
end

-- ── kids wing ───────────────────────────────────────────────────────────────

local function makeKidsHall(parent, hall, index)
	local palette = kidsPalette(hall)
	local center = hall.Center
	local kidsFolder = folder(parent, "Level 2 Kids Room " .. index .. " " .. palette.Name)
	kidsFolder:SetAttribute("Level2_KidsColor", palette.Name)

	local rng = Random.new(hall.LocalSeed or index)
	local blocks = math.clamp(math.floor(hall.Area / 2600), 5, 14)
	for block = 1, blocks do
		local x = rng:NextNumber(-.32, .32) * hall.Width
		local z = rng:NextNumber(-.32, .32) * hall.Depth
		local blockHeight = rng:NextNumber(3, 8)
		local shade = block % 2 == 0 and palette.Accent or palette.Color
		local pad = part(kidsFolder, "Level 2 Soft Play Block " .. block,
			CFrame.new(center + Vector3.new(x, blockHeight * .5, z)) * CFrame.Angles(0, rng:NextNumber() * math.pi, 0),
			Vector3.new(rng:NextNumber(8, 17), blockHeight, rng:NextNumber(8, 17)), shade,
			Enum.Material.SmoothPlastic)
		pad.CanCollide = true
	end

	local steps = math.clamp(math.floor((hall.Depth * .3 - 8) / 2.3), 6, 15)
	local topY = steps * .78
	local slideTop = center + Vector3.new(-hall.Width * .26, topY + 2.5, -hall.Depth * .2)
	local slideEnd = center + Vector3.new(-hall.Width * .26, 1.5, math.min(hall.Depth * .12, hall.Depth * .5 - 22))
	makeStairFlight(kidsFolder, slideTop + Vector3.new(9, -topY - 2.5, 0), Vector3.new(0, 0, -1), 8, steps,
		"Level 2 Kids Stair " .. index)
	makeSlideTube(kidsFolder, slideTop,
		slideTop + Vector3.new(0, -3, 13),
		slideEnd + Vector3.new(0, 6, -11),
		slideEnd, 4.4,
		Configuration.SlideColors[(index % #Configuration.SlideColors) + 1],
		"Level 2 Kids Slide " .. index, 14, true)

	local pitCenter = center + Vector3.new(-hall.Width * .26, 0, math.min(hall.Depth * .26, hall.Depth * .5 - 20))
	local pit = part(kidsFolder, "Level 2 Ball Pit Basin",
		CFrame.new(pitCenter + Vector3.new(0, .6, 0)), Vector3.new(36, 1.2, 32),
		palette.Accent, Enum.Material.SmoothPlastic)
	pit.CanCollide = true
	for wallIndex, data in ipairs({
		{Vector3.new(-18, 2.5, 0), Vector3.new(1.5, 5, 32)},
		{Vector3.new(18, 2.5, 0), Vector3.new(1.5, 5, 32)},
		{Vector3.new(0, 2.5, -16), Vector3.new(36, 5, 1.5)},
		{Vector3.new(0, 2.5, 16), Vector3.new(36, 5, 1.5)},
	}) do
		part(kidsFolder, "Level 2 Ball Pit Wall " .. wallIndex,
			CFrame.new(pitCenter + data[1]), data[2], palette.Color, Enum.Material.SmoothPlastic)
	end

	if hall.PoolType == "KidsShallow" then
		makeRaisedPool(kidsFolder,
			center + Vector3.new(math.min(hall.Width * .26, hall.Width * .5 - 34), 0, 0),
			math.min(52, hall.Width * .36), math.min(52, hall.Depth * .44), palette)
	end

	lightHall(kidsFolder, hall, "Kids" .. index)
	return kidsFolder
end

-- ── pump stations ───────────────────────────────────────────────────────────

-- Each new generation draws three different handle colors from the same
-- red/blue/green/yellow family as the Level 2 slides.
local LEVEL2_LEVER_HANDLE_COLORS = {
	{Name = "Green", Color = Configuration.SlideColors[1]},
	{Name = "Red", Color = Configuration.SlideColors[2]},
	{Name = "Yellow", Color = Configuration.SlideColors[3]},
	{Name = "Blue", Color = Configuration.SlideColors[4]},
}

local function shuffledLeverHandleColors(seed, generation)
	local palette = {}
	for index, record in ipairs(LEVEL2_LEVER_HANDLE_COLORS) do
		palette[index] = record
	end
	local rawSeed = (tonumber(seed) or 1) + (tonumber(generation) or 0) * 104729
	local mixedSeed = math.floor(math.abs(rawSeed)) % 2147483646
	if mixedSeed < 1 then mixedSeed = 1 end
	local rng = Random.new(mixedSeed)
	for index = #palette, 2, -1 do
		local swapIndex = rng:NextInteger(1, index)
		palette[index], palette[swapIndex] = palette[swapIndex], palette[index]
	end
	return palette
end

local function level2MachineTextureId()
	local assets = ReplicatedStorage:FindFirstChild("Level 2 Assets")
	local slot = assets and assets:FindFirstChild("Level 2 Pump Machinery Texture")
	if not slot or not slot:IsA("StringValue") then return nil end
	local raw = tostring(slot.Value):gsub("%s", "")
	if raw == "" then return nil end
	if raw:match("^%d+$") then return "rbxassetid://" .. raw end
	return raw
end

local function addMachineTexture(object, faces, studsU, studsV)
	local textureId = level2MachineTextureId()
	if not textureId then return end
	for _, face in ipairs(faces) do
		local texture = Instance.new("Texture")
		texture.Name = "Level 2 Pump Machinery Texture " .. face.Name
		texture.Texture = textureId
		texture.Face = face
		texture.StudsPerTileU = studsU
		texture.StudsPerTileV = studsV
		texture.Color3 = Color3.fromRGB(225, 227, 226)
		texture.Transparency = .04
		texture.Parent = object
	end
end

local function leverAttachedPart(assembly, root, name, localCFrame, size, color, material, shape)
	local object = part(assembly, name, root.CFrame * localCFrame, size, color, material)
	if shape then object.Shape = shape end
	object.Anchored = false
	object.CanCollide = false
	object.CanTouch = false
	object.CanQuery = false
	object.Massless = true
	local weld = Instance.new("WeldConstraint")
	weld.Name = "Level 2 Pump Lever Weld " .. name
	weld.Part0 = root
	weld.Part1 = object
	weld.Parent = root
	return object
end

local function makePumpStation(parent, hall, index, handleSpec)
	local center = hall.Center
	local model = Instance.new("Model")
	model.Name = "Level 2 Pump Station " .. index
	model:SetAttribute("Level2_PumpIndex", index)
	model:SetAttribute("Level2_LeverHandleColor", handleSpec.Name)
	model:SetAttribute("Level2_LeverHandleColorValue", handleSpec.Color)
	model.Parent = parent

	local plinth = tiledPart(model, "Level 2 Pump Plinth",
		CFrame.new(center + Vector3.new(0, 2.5, 0)), Vector3.new(25, 5, 17), C.TileWarm, nil, 8)
	plinth.CanCollide = true

	-- Large cabinet silhouette: readable as machinery from across a hall.
	local housing = part(model, "Level 2 Pump Machinery Cabinet",
		CFrame.new(center + Vector3.new(0, 11.2, 0)), Vector3.new(18, 16.2, 9),
		Color3.fromRGB(91, 96, 98), Enum.Material.Metal)
	housing.CanCollide = true
	housing.Reflectance = .12
	addMachineTexture(housing,
		{Enum.NormalId.Left, Enum.NormalId.Right, Enum.NormalId.Front},
		12, 12)

	local upperCap = part(model, "Level 2 Pump Machinery Upper Cap",
		CFrame.new(center + Vector3.new(0, 19.55, 0)), Vector3.new(19.6, .75, 10.2),
		Color3.fromRGB(202, 205, 202), Enum.Material.Metal)
	upperCap.Reflectance = .2
	local lowerCap = part(model, "Level 2 Pump Machinery Lower Cap",
		CFrame.new(center + Vector3.new(0, 3.45, 0)), Vector3.new(19.6, .75, 10.2),
		Color3.fromRGB(58, 62, 64), Enum.Material.Metal)
	lowerCap.Reflectance = .14

	for cornerIndex, offset in ipairs({
		Vector3.new(-8.65, 11.2, -4.25),
		Vector3.new(8.65, 11.2, -4.25),
		Vector3.new(-8.65, 11.2, 4.25),
		Vector3.new(8.65, 11.2, 4.25),
	}) do
		local rail = part(model, "Level 2 Pump Machinery Rounded Corner " .. cornerIndex,
			CFrame.new(center + offset) * CFrame.Angles(0, 0, math.pi * .5),
			Vector3.new(15.7, 1.15, 1.15), Color3.fromRGB(188, 193, 192), Enum.Material.Metal)
		rail.Shape = Enum.PartType.Cylinder
		rail.Reflectance = .22
	end

	for _, sx in ipairs({-1, 1}) do
		local pipe = part(model, "Level 2 Pump Intake Pipe",
			CFrame.new(center + Vector3.new(sx * 11.2, 6, 0)) * CFrame.Angles(0, 0, math.pi * .5),
			Vector3.new(8, 3.8, 3.8), Color3.fromRGB(78, 87, 89), Enum.Material.Metal)
		pipe.Shape = Enum.PartType.Cylinder
		pipe.Reflectance = .16
		pipe.CanCollide = true
		local collar = part(model, "Level 2 Pump Intake Pipe Collar " .. (sx < 0 and "Left" or "Right"),
			CFrame.new(center + Vector3.new(sx * 8.85, 6, 0)) * CFrame.Angles(0, 0, math.pi * .5),
			Vector3.new(1.1, 4.7, 4.7), Color3.fromRGB(174, 182, 182), Enum.Material.Metal)
		collar.Shape = Enum.PartType.Cylinder
		collar.Reflectance = .24
	end

	local panel = part(model, "Level 2 Pump Glossy Control Panel",
		CFrame.new(center + Vector3.new(0, 11.25, 4.82)), Vector3.new(14.6, 11.6, .72),
		Color3.fromRGB(32, 35, 37), Enum.Material.SmoothPlastic)
	panel.Reflectance = .25
	panel.CanCollide = false
	addMachineTexture(panel, {Enum.NormalId.Back}, 14.6, 11.6)

	for frameIndex, data in ipairs({
		{Vector3.new(0, 5.92, 5.22), Vector3.new(15.5, .45, .55)},
		{Vector3.new(0, 16.58, 5.22), Vector3.new(15.5, .45, .55)},
		{Vector3.new(-7.52, 11.25, 5.22), Vector3.new(.45, 11.1, .55)},
		{Vector3.new(7.52, 11.25, 5.22), Vector3.new(.45, 11.1, .55)},
	}) do
		local frame = part(model, "Level 2 Pump Control Panel Frame " .. frameIndex,
			CFrame.new(center + data[1]), data[2], Color3.fromRGB(167, 173, 172), Enum.Material.Metal)
		frame.Reflectance = .22
		frame.CanCollide = false
	end

	local lamp = part(model, "Level 2 Pump Status Lamp",
		CFrame.new(center + Vector3.new(4.75, 15.25, 5.38)), Vector3.new(3.4, 1.25, .35),
		C.Locked, Enum.Material.Neon)
	lamp.CanCollide = false
	local lampGlow = Instance.new("PointLight")
	lampGlow.Name = "Level 2 Pump Status Lamp Glow"
	lampGlow.Color = C.Locked
	lampGlow.Brightness = .42
	lampGlow.Range = 12
	lampGlow.Parent = lamp

	-- Pressure gauge gives the cabinet an unmistakable pump-machine profile.
	local gaugeRim = part(model, "Level 2 Pump Pressure Gauge Rim",
		CFrame.new(center + Vector3.new(-4.8, 14.7, 5.42)) * CFrame.Angles(0, math.pi * .5, 0),
		Vector3.new(.6, 3.55, 3.55), Color3.fromRGB(45, 49, 51), Enum.Material.Metal)
	gaugeRim.Shape = Enum.PartType.Cylinder
	gaugeRim.Reflectance = .2
	gaugeRim.CanCollide = false
	local gaugeFace = part(model, "Level 2 Pump Pressure Gauge Face",
		CFrame.new(center + Vector3.new(-4.8, 14.7, 5.78)) * CFrame.Angles(0, math.pi * .5, 0),
		Vector3.new(.18, 2.85, 2.85), Color3.fromRGB(226, 224, 206), Enum.Material.SmoothPlastic)
	gaugeFace.Shape = Enum.PartType.Cylinder
	gaugeFace.CanCollide = false
	local gaugeNeedle = part(model, "Level 2 Pump Pressure Gauge Needle",
		CFrame.new(center + Vector3.new(-4.8, 14.72, 5.91)) * CFrame.Angles(0, 0, math.rad(-38)),
		Vector3.new(.18, 1.15, .10), C.Locked, Enum.Material.Neon)
	gaugeNeedle.CanCollide = false

	local stationPlate = part(model, "Level 2 Pump Station Number Plate",
		CFrame.new(center + Vector3.new(-3.5, 6.85, 5.4)), Vector3.new(5.4, 1.35, .28),
		Color3.fromRGB(20, 23, 24), Enum.Material.SmoothPlastic)
	stationPlate.CanCollide = false
	local stationGui = Instance.new("SurfaceGui")
	stationGui.Name = "Level 2 Pump Station Number Surface"
	stationGui.Face = Enum.NormalId.Back
	stationGui.LightInfluence = .25
	stationGui.PixelsPerStud = 50
	stationGui.Parent = stationPlate
	local stationText = Instance.new("TextLabel")
	stationText.Name = "Level 2 Pump Station Number Text"
	stationText.BackgroundTransparency = 1
	stationText.Size = UDim2.fromScale(1, 1)
	stationText.Font = Enum.Font.GothamBold
	stationText.Text = string.format("PUMP  %02d", index)
	stationText.TextColor3 = Color3.fromRGB(224, 228, 222)
	stationText.TextScaled = true
	stationText.Parent = stationGui

	-- A raised glossy mount and large pivot make the switch read clearly even
	-- before the colored grip is visible.
	local mountPlate = part(model, "Level 2 Pump Lever Glossy Mounting Plate",
		CFrame.new(center + Vector3.new(2.25, 10.45, 5.45)), Vector3.new(6.1, 7.25, .8),
		Color3.fromRGB(18, 20, 22), Enum.Material.SmoothPlastic)
	mountPlate.Reflectance = .32
	mountPlate.CanCollide = false

	for boltIndex, offset in ipairs({
		Vector3.new(-2.35, 2.9, .48), Vector3.new(2.35, 2.9, .48),
		Vector3.new(-2.35, -2.9, .48), Vector3.new(2.35, -2.9, .48),
	}) do
		local bolt = part(model, "Level 2 Pump Lever Mounting Bolt " .. boltIndex,
			mountPlate.CFrame * CFrame.new(offset), Vector3.new(.42, .42, .24),
			Color3.fromRGB(206, 211, 210), Enum.Material.Metal)
		bolt.Shape = Enum.PartType.Ball
		bolt.Reflectance = .3
		bolt.CanCollide = false
	end

	local pivotCFrame = mountPlate.CFrame * CFrame.new(0, -.75, .72)
	local statusRing = part(model, "Level 2 Pump Lever Status Ring",
		pivotCFrame * CFrame.Angles(0, math.pi * .5, 0),
		Vector3.new(.52, 3.55, 3.55), C.Locked, Enum.Material.Metal)
	statusRing.Shape = Enum.PartType.Cylinder
	statusRing.Reflectance = .22
	statusRing.CanCollide = false

	local leverAssembly = Instance.new("Model")
	leverAssembly.Name = "Level 2 Pump Lever Assembly"
	leverAssembly:SetAttribute("Level2_LeverHandleColor", handleSpec.Name)
	leverAssembly:SetAttribute("Level2_LeverHandleColorValue", handleSpec.Color)
	leverAssembly.Parent = model

	local leverIdleCFrame = pivotCFrame * CFrame.Angles(math.rad(38), 0, 0)
	local lever = part(leverAssembly, "Level 2 Pump Lever Animated Pivot",
		leverIdleCFrame, Vector3.new(.45, .45, .45),
		Color3.new(1, 1, 1), Enum.Material.SmoothPlastic, 1)
	lever.CanCollide = false
	lever.CanTouch = false
	lever.CanQuery = false
	leverAssembly.PrimaryPart = lever

	local pivotHub = leverAttachedPart(leverAssembly, lever, "Level 2 Pump Lever Metallic Pivot Hub",
		CFrame.Angles(0, math.pi * .5, 0), Vector3.new(.72, 2.55, 2.55),
		Color3.fromRGB(54, 58, 60), Enum.Material.Metal, Enum.PartType.Cylinder)
	pivotHub.Reflectance = .3

	local shaft = leverAttachedPart(leverAssembly, lever, "Level 2 Pump Lever Metallic Shaft",
		CFrame.new(0, 2.55, 0) * CFrame.Angles(0, 0, math.pi * .5),
		Vector3.new(5.0, .72, .72), Color3.fromRGB(92, 98, 100),
		Enum.Material.Metal, Enum.PartType.Cylinder)
	shaft.Reflectance = .3

	local yokeBridge = leverAttachedPart(leverAssembly, lever, "Level 2 Pump Lever Yoke Bridge",
		CFrame.new(0, 4.72, 0), Vector3.new(3.05, .48, .62),
		Color3.fromRGB(35, 38, 40), Enum.Material.Metal)
	yokeBridge.Reflectance = .26

	for sideIndex, side in ipairs({-1, 1}) do
		local arm = leverAttachedPart(leverAssembly, lever, "Level 2 Pump Lever Yoke Arm " .. sideIndex,
			CFrame.new(side * 1.3, 5.58, 0) * CFrame.Angles(0, 0, math.pi * .5),
			Vector3.new(1.75, .42, .58), Color3.fromRGB(35, 38, 40),
			Enum.Material.Metal, Enum.PartType.Cylinder)
		arm.Reflectance = .28
	end

	local grip = leverAttachedPart(leverAssembly, lever, "Level 2 Pump Lever Colored Plastic Grip",
		CFrame.new(0, 6.47, 0), Vector3.new(3.75, 1.35, 1.35),
		handleSpec.Color, Enum.Material.SmoothPlastic, Enum.PartType.Cylinder)
	grip.Reflectance = .1
	grip.CanQuery = true

	for sideIndex, side in ipairs({-1, 1}) do
		local collar = leverAttachedPart(leverAssembly, lever, "Level 2 Pump Lever Grip Collar " .. sideIndex,
			CFrame.new(side * 1.92, 6.47, 0), Vector3.new(.34, 1.58, 1.58),
			Color3.fromRGB(48, 52, 54), Enum.Material.Metal, Enum.PartType.Cylinder)
		collar.Reflectance = .3
	end

	local prompt = Instance.new("ProximityPrompt")
	prompt.Name = "Level 2 Pump Prompt"
	prompt.ActionText = "START PUMP"
	prompt.ObjectText = "Pump station " .. index
	prompt.HoldDuration = 1.6
	prompt.MaxActivationDistance = 12
	prompt.RequiresLineOfSight = true
	prompt.Parent = grip

	model.PrimaryPart = plinth
	return {
		Model = model,
		Prompt = prompt,
		Lever = lever,
		LeverAssembly = leverAssembly,
		LeverHandle = grip,
		LeverStatusRing = statusRing,
		LeverRestCFrame = leverIdleCFrame,
		Lamp = lamp,
		LampGlow = lampGlow,
		Housing = housing,
		Index = index,
	}
end

-- ── corridors ───────────────────────────────────────────────────────────────

-- Flooded arch tunnels: full-width water over a recessed floor, dense arch
-- rings overhead. Drainable corridors are deeper, with steps at both ends.
local function makeCorridor(parent, layout, corridor, doorFolder)
	if corridor.Kind == "SharedWall" then
		return nil -- the halls meet wall-to-wall; the doorway lives in the wall
	end

	local width = corridor.Width
	local height = Configuration.CorridorHeight
	local from, to = corridor.From, corridor.To
	local length = math.abs(to - from) + 4
	local mid = (from + to) * .5
	local alongX = corridor.Axis == "X"
	local center = alongX and Vector3.new(mid, 0, corridor.Cross)
		or Vector3.new(corridor.Cross, 0, mid)
	local depth = corridor.DrainGroup and Configuration.DrainableCorridorDepth
		or Configuration.CorridorChannelDepth

	local function oriented(x, z)
		if alongX then return Vector3.new(x, 0, z) end
		return Vector3.new(z, 0, x)
	end
	local function orientedSize(along, y, across)
		if alongX then return Vector3.new(along, y, across) end
		return Vector3.new(across, y, along)
	end

	-- Recessed floor, water wall-to-wall.
	local floorSlab = tiledPart(parent, "Level 2 Corridor Water Floor",
		CFrame.new(center + Vector3.new(0, -depth - .6, 0)),
		orientedSize(length, 1.2, width), C.TileCool, {Enum.NormalId.Top}, 8)
	floorSlab.CanCollide = true

	-- Steps at both ends of deep (drainable) corridors so the drained channel
	-- is walkable end to end.
	if depth > 2.5 then
		local stepRun, stepRise = 1.4, .92
		local stepCount = math.ceil(depth / stepRise)
		for _, endSign in ipairs({-1, 1}) do
			local outward = oriented(endSign, 0)
			local base = center + oriented(endSign * (length * .5 - 2 - stepCount * stepRun), 0)
				+ Vector3.new(0, -depth, 0)
			makeStairFlight(parent, base, outward, width - 6, stepCount,
				"Level 2 Corridor " .. corridor.Index .. " Steps", stepRun, stepRise)
		end
	end

	-- Walls reach below the waterline; ceiling stays solid (tunnels).
	local wallBottom = -depth - 3
	local wallTop = height + 2
	for _, side in ipairs({-1, 1}) do
		local wall = tiledPart(parent, "Level 2 Corridor Wall",
			CFrame.new(center + oriented(0, side * width * .5) + Vector3.new(0, (wallTop + wallBottom) * .5, 0)),
			orientedSize(length, wallTop - wallBottom, Configuration.WallThickness), C.TileCool, nil, 7)
		wall.CanCollide = true
	end
	local ceiling = tiledPart(parent, "Level 2 Corridor Ceiling",
		CFrame.new(center + Vector3.new(0, height + 1, 0)),
		orientedSize(length, 2, width), C.TileCool, {Enum.NormalId.Bottom}, 9)
	ceiling.CanCollide = true

	-- Dense arch rings: the corridor reads as a vaulted arch tunnel.
	local rings = math.max(3, math.floor(length / 11))
	local archRadius = width * .5 - 3
	for ring = 1, rings do
		local t = ring / (rings + 1)
		makeArchSpan(parent, center + oriented(from - mid + (to - from) * t, 0),
			alongX, corridor.Index .. "." .. ring, archRadius, depth)
	end
	-- The ribs connect into one continuous half-cylinder vault.
	makeBarrelVault(parent, center, alongX, corridor.Index, archRadius + 1.4, length - 2, depth)

	makeCeilingPanel(parent, center, "Corridor " .. corridor.Index,
		orientedSize(math.min(length * .55, 40), .55, 6), 0, height)

	-- Water, full width.
	local waterHeight = depth + .1
	local region = addWater(center + Vector3.new(0, .1 - waterHeight * .5, 0),
		alongX and Vector3.new(length - 3, waterHeight, width - 3)
			or Vector3.new(width - 3, waterHeight, length - 3),
		"Corridor " .. corridor.Index)

	local door
	if corridor.Kind == "PressureDoor" then
		local doorCenter = center + oriented(to - mid, 0) + Vector3.new(0, height * .5 - 2, 0)
		door = part(doorFolder, "Level 2 Pressure Door " .. corridor.Index,
			CFrame.new(doorCenter), orientedSize(2.2, height + 4, width), C.Locked,
			Enum.Material.DiamondPlate)
		door.CanCollide = true
		door:SetAttribute("Level2_CorridorIndex", corridor.Index)
		local stripe = part(doorFolder, "Level 2 Pressure Door Stripe " .. corridor.Index,
			CFrame.new(doorCenter + Vector3.new(0, 4, 0)),
			orientedSize(2.4, 1.2, width - 4), C.Locked, Enum.Material.Neon)
		stripe.CanCollide = false
	end

	return {Corridor = corridor, Water = region, Door = door, Center = center}
end

-- ── arrival ─────────────────────────────────────────────────────────────────

local function makeArrivalConcourse(parent, hall)
	local center = hall.Center
	local arrivalFolder = folder(parent, "Level 2 Arrival Concourse")

	local platformHeight = 1.2
	local platform = tiledPart(arrivalFolder, "Level 2 Arrival Platform",
		CFrame.new(center + Vector3.new(0, platformHeight * .5, 0)),
		Vector3.new(26, platformHeight, 26), C.TileWarm, Enum.NormalId:GetEnumItems(), 7)
	platform.CanCollide = true

	local ring = part(arrivalFolder, "Level 2 Arrival Ring",
		CFrame.new(center + Vector3.new(0, platformHeight + .08, 0)),
		Vector3.new(22, .16, 22), C.Emergency, Enum.Material.Neon, .35)
	ring.CanCollide = false

	for _, direction in ipairs({Vector3.new(1, 0, 0), Vector3.new(-1, 0, 0), Vector3.new(0, 0, 1), Vector3.new(0, 0, -1)}) do
		makeStairFlight(arrivalFolder, center + direction * 17.4, -direction, 12, 2,
			"Level 2 Arrival Steps", 2.0, .6)
	end


	-- The arrival hall is skylit like every other hall: sun only, no fixture.
	return platformHeight
end

local function makeCompatibilityArrival(world, arrivalPosition, platformHeight)
	local topY = platformHeight or 0

	local marker = part(world, "Level 2 Arrival Spawn",
		CFrame.new(arrivalPosition + Vector3.new(0, topY + .3, 0)), Vector3.new(9, .4, 9),
		C.Emergency, Enum.Material.Neon, 1)
	marker.CanCollide = false
	marker.CanTouch = false

	local elevator = Instance.new("Model")
	elevator.Name = "Elevator"
	elevator:SetAttribute("Level2_CompatibilityMarker", true)
	elevator.Parent = workspace
	local shell = part(elevator, "Level 2 Arrival Elevator Shell",
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
		object:SetAttribute("Level2_CompatibilityMarker", true)
		return object
	end

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
	world.Name = "Level 2 Generated World"
	world:SetAttribute("Level2_Seed", layout.Seed)
	world:SetAttribute("Level2_Generation", generation)
	world:SetAttribute("Level2_GenerationAttempt", layout.Attempt)
	world:SetAttribute("Level2_Theme", Configuration.Theme)
	world.Parent = workspace

	local geometry = folder(world, "Level 2 Geometry")
	local hallsFolder = folder(geometry, "Level 2 Halls")
	local corridorsFolder = folder(geometry, "Level 2 Corridors")
	local kidsFolder = folder(geometry, "Level 2 Kids Wing")
	local slideFolder = folder(geometry, "Level 2 Slide Halls")
	local containment = folder(geometry, "Level 2 Containment")
	local objectiveFolder = folder(world, "Level 2 Objectives")
	local doorFolder = folder(objectiveFolder, "Level 2 Pressure Doors")
	local lightingFolder = folder(world, "Level 2 Lighting")
	local navigationFolder = folder(world, "Level 2 Navigation")
	local entityFolder = folder(world, "Level 2 Entity Nodes")

	local tallest = Configuration.GrandSlideHallHeight
	local waterRegions = {}
	waterRegionsRef = waterRegions

	local floor = tiledPart(containment, "Level 2 Sealed Foundation",
		CFrame.new(worldCenterX, -36, worldCenterZ),
		Vector3.new(extent + 140, 4, extent + 140), C.DarkGrout, {Enum.NormalId.Top}, 12)
	floor.CanCollide = true

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
	local exit
	local hallDepths = {}
	local built = 0

	for _, hall in ipairs(layout.Halls) do
		local hallModel = Instance.new("Model")
		hallModel.Name = hall.Id .. " " .. (hall.Archetype or "Hall")
		hallModel:SetAttribute("Level2_Role", hall.Role)
		hallModel:SetAttribute("Level2_PoolType", hall.PoolType)
		hallModel:SetAttribute("Level2_Archetype", hall.Archetype)
		hallModel:SetAttribute("Level2_GraphDepth", hall.GraphDepth)
		hallModel:SetAttribute("Level2_Height", hallHeight(hall))
		if hall.KidsColorIndex then
			hallModel:SetAttribute("Level2_KidsColor", kidsPalette(hall).Name)
		end
		hallModel.Parent = hallsFolder

		local depth = makeHallFloor(hallModel, hall)
		hallDepths[hall.Index] = depth
		makeHallCeiling(hallModel, hall)

		if hall.Role == "Kids Area" then
			makeKidsHall(kidsFolder, hall, hall.KidsIndex or hall.Index)
		elseif hall.Role == "Slide Hall" then
			slideDecks[hall.SlideHallIndex] = makeSlideHall(slideFolder, hall, hall.SlideHallIndex)
			if hall.IsGrand then
				exit = makeExitFlume(geometry, layout, hall, slideDecks[hall.SlideHallIndex])
			end
		else
			local archetype = hall.Archetype or ""
			local height = hallHeight(hall)
			if archetype == "Pillar Basin" or archetype == "Diving Well" then
				makeColonnade(hallModel, hall, depth, {-.6, .6})
			elseif archetype == "Column Forest" then
				makeColonnade(hallModel, hall, depth, {-.62, 0, .62})
			elseif archetype == "Curved Gallery" then
				makeColonnade(hallModel, hall, depth, {-.56})
			elseif archetype == "Flooded Gallery" then
				makeColonnade(hallModel, hall, depth, {-.64, .64})
			elseif archetype == "Arch Tunnel" or archetype == "Ring Corridor" then
				local acrossZ = hall.Width >= hall.Depth
				local along = acrossZ and hall.Width or hall.Depth
				local rings = math.clamp(math.floor(along / 26), 3, 9)
				local radius = math.min((acrossZ and hall.Depth or hall.Width) * .5 - 6, height - 5, 19)
				for ring = 1, rings do
					local t = ring / (rings + 1)
					local position = acrossZ
						and Vector3.new(hall.MinX + along * t, 0, hall.Center.Z)
						or Vector3.new(hall.Center.X, 0, hall.MinZ + along * t)
					makeArchSpan(hallModel, position, acrossZ, hall.Index .. "." .. ring, radius, depth or 0)
				end
				makeBarrelVault(hallModel, hall.Center, acrossZ, hall.Index,
					radius + 1.4, along - 14, depth or 0)
			elseif archetype == "Spiral Stair Well" then
				makeSpiralStair(hallModel, hall.Center, -(depth or 1) + .5, height - 12, 13,
					"Level 2 Stair Well " .. hall.Index)
			elseif archetype == "Skylight Hall" then
				-- The real skylight slots already daylight this hall; add columns.
				makeColonnade(hallModel, hall, depth, {-.5, .5})
			elseif archetype == "Porthole Hall" then
				for step = -1, 1 do
					local offset = Vector3.new(step * math.min(30, hall.Width * .25), 9, -hall.Depth * .5 + 3)
					local pane = part(hallModel, "Level 2 Porthole " .. hall.Index .. " " .. step,
						CFrame.new(hall.Center + offset), Vector3.new(10, 15, .6), C.Light,
						Enum.Material.Neon, .1)
					pane.CanCollide = false
					local light = Instance.new("SurfaceLight")
					light.Face = Enum.NormalId.Back
					light.Color = C.Light
					light.Brightness = .7
					light.Range = 26
					light.Angle = 110
					light.Shadows = false
					light.Parent = pane
				end
			end

			-- Deep water: stairs descend from every doorway into the pool.
			if depth and depth > 2.5 then
				local stepRun, stepRise = 1.4, .92
				local stepCount = math.ceil(depth / stepRise)
				local stairWidth = Configuration.DoorWidth - 6
				for _, doorZ in ipairs(doorsByHall[hall.Index].West) do
					makeStairFlight(hallModel,
						Vector3.new(hall.MinX + 2 + stepCount * stepRun, -depth, doorZ),
						Vector3.new(-1, 0, 0), stairWidth, stepCount,
						"Level 2 Hall " .. hall.Index .. " Doorway Steps", stepRun, stepRise)
				end
				for _, doorZ in ipairs(doorsByHall[hall.Index].East) do
					makeStairFlight(hallModel,
						Vector3.new(hall.MaxX - 2 - stepCount * stepRun, -depth, doorZ),
						Vector3.new(1, 0, 0), stairWidth, stepCount,
						"Level 2 Hall " .. hall.Index .. " Doorway Steps", stepRun, stepRise)
				end
				for _, doorX in ipairs(doorsByHall[hall.Index].North) do
					makeStairFlight(hallModel,
						Vector3.new(doorX, -depth, hall.MinZ + 2 + stepCount * stepRun),
						Vector3.new(0, 0, -1), stairWidth, stepCount,
						"Level 2 Hall " .. hall.Index .. " Doorway Steps", stepRun, stepRise)
				end
				for _, doorX in ipairs(doorsByHall[hall.Index].South) do
					makeStairFlight(hallModel,
						Vector3.new(doorX, -depth, hall.MaxZ - 2 - stepCount * stepRun),
						Vector3.new(0, 0, 1), stairWidth, stepCount,
						"Level 2 Hall " .. hall.Index .. " Doorway Steps", stepRun, stepRise)
				end
			end
		end

		if hall.Role ~= "Kids Area" and hall.Role ~= "Slide Hall" then
			lightHall(lightingFolder, hall, hall.Index)
		end

		local node = part(navigationFolder, "Level 2 Navigation Node " .. hall.Index,
			CFrame.new(hall.Center + Vector3.new(0, 1, 0)), Vector3.new(2, .2, 2),
			C.Emergency, Enum.Material.Neon, 1)
		node.CanCollide = false
		node.CanTouch = false
		node:SetAttribute("Level2_HallId", hall.Id)
		node:SetAttribute("Level2_Role", hall.Role)

		for corner, sign in ipairs({
			Vector3.new(-.32, 0, -.32), Vector3.new(.32, 0, -.32),
			Vector3.new(-.32, 0, .32), Vector3.new(.32, 0, .32),
		}) do
			local patrol = part(entityFolder, "Level 2 Entity Patrol Node " .. hall.Index .. "." .. corner,
				CFrame.new(hall.Center + Vector3.new(sign.X * hall.Width, 2, sign.Z * hall.Depth)),
				Vector3.new(1.5, .2, 1.5), C.Emergency, Enum.Material.Neon, 1)
			patrol.CanCollide = false
			patrol.CanTouch = false
			patrol:SetAttribute("Level2_HallId", hall.Id)
		end

		built += 1
		if built % 4 == 0 then task.wait() end
	end

	-- Hall walls, deepened below each hall's waterline.
	for _, hall in ipairs(layout.Halls) do
		local hallModel
		for _, child in ipairs(hallsFolder:GetChildren()) do
			if child.Name:sub(1, #hall.Id) == hall.Id then hallModel = child break end
		end
		local doors = doorsByHall[hall.Index]
		local height = hallHeight(hall)
		local bottomY = -(hallDepths[hall.Index] or 0) - 4
		local eastFlumeGap = (hall.IsGrand and exit) and exit.HallWallGap or nil
		makeWallWithGaps(hallModel, hall, "Level 2 Hall West Wall", "Z", hall.MinX, hall.MinZ, hall.MaxZ, doors.West, height, bottomY)
		makeWallWithGaps(hallModel, hall, "Level 2 Hall East Wall", "Z", hall.MaxX, hall.MinZ, hall.MaxZ, doors.East, height, bottomY, eastFlumeGap)
		makeWallWithGaps(hallModel, hall, "Level 2 Hall North Wall", "X", hall.MinZ, hall.MinX, hall.MaxX, doors.North, height, bottomY)
		makeWallWithGaps(hallModel, hall, "Level 2 Hall South Wall", "X", hall.MaxZ, hall.MinX, hall.MaxX, doors.South, height, bottomY)
	end
	task.wait()

	local corridorRecords = {}
	local drains = {}
	local pressureDoors = {}
	for _, corridor in ipairs(layout.Corridors) do
		local record = makeCorridor(corridorsFolder, layout, corridor, doorFolder)
		if record then
			corridorRecords[corridor.Index] = record
			if corridor.DrainGroup then drains[corridor.DrainGroup] = record end
			if record.Door then table.insert(pressureDoors, record) end
		end
	end
	task.wait()

	local pumps = {}
	local leverHandleColors = shuffledLeverHandleColors(layout.Seed, generation)
	for index, hall in ipairs(layout.PumpHalls) do
		pumps[index] = makePumpStation(objectiveFolder, hall, index, leverHandleColors[index])
		pumps[index].Hall = hall
	end

	local platformHeight = makeArrivalConcourse(geometry, layout.Arrival)
	local arrival = makeCompatibilityArrival(world, layout.Arrival.Center, platformHeight)

	-- RESERVED entity space: two den markers, nothing spawns here yet. See
	-- Configuration.Entities for the profile stubs a future hostile fills in.
	local den = part(entityFolder, "Level 2 Entity Den A Spawn",
		CFrame.new(layout.EntityDen.Center + Vector3.new(0, 3, 0)), Vector3.new(10, .4, 10),
		C.Void, Enum.Material.Neon, 1)
	den.CanCollide = false
	den.CanTouch = false
	den:SetAttribute("Level2_HallId", layout.EntityDen.Id)
	entityFolder:SetAttribute("Level2_DenAPosition", layout.EntityDen.Center)
	if layout.EntityDenB then
		local denB = part(entityFolder, "Level 2 Entity Den B Spawn",
			CFrame.new(layout.EntityDenB.Center + Vector3.new(0, 3, 0)), Vector3.new(10, .4, 10),
			C.Void, Enum.Material.Neon, 1)
		denB.CanCollide = false
		denB.CanTouch = false
		denB:SetAttribute("Level2_HallId", layout.EntityDenB.Id)
		entityFolder:SetAttribute("Level2_DenBPosition", layout.EntityDenB.Center)
	end
	arrival.EntityStart.CFrame = CFrame.new(layout.EntityDen.Center + Vector3.new(0, 4, 0))

	-- Outer shell: four opaque walls, but a TRANSLUCENT GLASS ROOF that casts
	-- no shadow — real sunlight pours through it and down through every
	-- skylight slot in the hall ceilings.
	local shellHalfX = extent * .5 + 60
	local shellHeight = tallest + 12
	local wallTall = shellHeight + 44
	local wallY = shellHeight * .5 - 20
	tiledPart(containment, "Level 2 Outer North Containment Wall",
		CFrame.new(worldCenterX, wallY, worldCenterZ - shellHalfX),
		Vector3.new(extent + 140, wallTall, 8), C.DarkGrout, nil, 12).CanCollide = true
	tiledPart(containment, "Level 2 Outer South Containment Wall",
		CFrame.new(worldCenterX, wallY, worldCenterZ + shellHalfX),
		Vector3.new(extent + 140, wallTall, 8), C.DarkGrout, nil, 12).CanCollide = true
	tiledPart(containment, "Level 2 Outer West Containment Wall",
		CFrame.new(worldCenterX - shellHalfX, wallY, worldCenterZ),
		Vector3.new(8, wallTall, extent + 140), C.DarkGrout, nil, 12).CanCollide = true
	makeWallWithGaps(containment, nil, "Level 2 Outer East Containment Wall", "Z",
		worldCenterX + shellHalfX, worldCenterZ - shellHalfX - 6, worldCenterZ + shellHalfX + 6,
		nil, shellHeight + 24, -36, exit and exit.ShellGap or nil)
	local roof = part(containment, "Level 2 Glass Sky Roof",
		CFrame.new(worldCenterX, shellHeight + 24, worldCenterZ),
		Vector3.new(extent + 150, 4, extent + 150), Color3.fromRGB(250, 247, 235),
		Enum.Material.Glass, .6)
	roof.CanCollide = true
	roof.CastShadow = false

	local terrainCenter = Vector3.new(worldCenterX, -16, worldCenterZ)
	local terrainSize = Vector3.new(extent + 700, 200, extent + 700)
	world:SetAttribute("Level2_TerrainCenter", terrainCenter)
	world:SetAttribute("Level2_TerrainSize", terrainSize)
	world:SetAttribute("Level2_HallCount", #layout.Halls)
	world:SetAttribute("Level2_CorridorCount", #layout.Corridors)
	world:SetAttribute("Level2_KidsRoomCount", #(layout.KidsArea or {}))
	world:SetAttribute("Level2_SlideHallCount", #(layout.SlideHalls or {}))

	waterRegionsRef = nil

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
