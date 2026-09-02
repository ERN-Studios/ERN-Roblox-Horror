-- Level 2 World Builder
-- Turns a Level 2 layout (variable-size halls + corridors) into geometry.
--
-- Shared with Level 2 on purpose, and nothing else: the tile texture asset and
-- the terrain water appearance. Everything structural here is Level 2's own.
--
-- Design language (reference photos): WATER COVERS THE FLOOR WALL-TO-WALL in
-- every pool hall and corridor — no sunken basins. Raised decks standing in
-- the water are the deliberate exception: pump-room service rings, slim
-- door-aware edge walkways in a seeded share of the plain halls, and a very
-- slim maintenance ledge along one side of every tunnel. Bright
-- natural sunlight enters through real skylight slots cut in the ceilings
-- (the outer roof is translucent glass that casts no shadow), tiled columns
-- and arch tunnels rise straight out of the water, and stairs descend into
-- the deeper halls.

local ReplicatedStorage = game:GetService("ReplicatedStorage")
local ServerStorage = game:GetService("ServerStorage")
local AssetService = game:GetService("AssetService")
local Terrain = workspace.Terrain

local Configuration = require(script.Parent:WaitForChild("Level 2 Configuration"))

local WorldBuilder = {}
local C = Configuration.Colors

-- The two things Level 2 borrows from Level 2.
local TILE_TEXTURE = "rbxassetid://113211706146395"
local TILE_TINT = Color3.fromRGB(248, 242, 218)
local COLUMN_FLARE_MESH = "rbxassetid://90196117593704"
-- A populated MeshPart.TextureID does not composite like a projected Texture.
-- Use the shaft's warm base color and reproduce its tinted tile overlay with a
-- SurfaceAppearance so the two surfaces meet without a hard albedo seam.
local COLUMN_FLARE_COLOR = C.TileWarm
local COLUMN_FLARE_SURFACE_TEMPLATE = "Level 2 Column Tile Surface Template"
local SLIDE_OPEN_SEGMENT_MESH = "rbxassetid://134677774662968"
local SLIDE_OPEN_END_CAP_MESH = "rbxassetid://107012498668441"
local SLIDE_CRADLE_MESH = "rbxassetid://132916619634128"
local SLIDE_CLOSED_END_CAP_MESH = "rbxassetid://107409495820821"

-- Shared top height of every raised walking deck (pump rings, hall edge
-- walkways, corridor ledges): .45 above the nominal Y=0 walk level, so it
-- stands comfortably proud of the Y=.1 water surface.
local WALKWAY_TOP = .45

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

local LEVEL2_KIDS_TILE_TEXTURE_SLOTS = {
	Sun = "Level 2 Kids Sun Tile Texture",
	Coral = "Level 2 Kids Coral Tile Texture",
	Lagoon = "Level 2 Kids Lagoon Tile Texture",
}
local LEVEL2_KIDS_TILE_STUDS = 24
local LEVEL2_KIDS_FOAM_VARIANT = "Level2 Kids Foam Vinyl"
local LEVEL2_KIDS_FLOOR_VARIANT = "Level2 Kids Rubber Floor"
local LEVEL2_KIDS_SLIDE_VARIANT = "Level2 Kids Slide Fiberglass"

local function mutedKidsColor(color, neutralWeight)
	return color:Lerp(Color3.fromRGB(151, 155, 148), neutralWeight or .42)
end

local function useKidsMaterial(object, material, variantName)
	object.Material = material
	object.MaterialVariant = variantName
	return object
end

local function normalizedAssetId(value)
	local raw = tostring(value or ""):gsub("%s", "")
	if raw == "" then return nil end
	if raw:match("^%d+$") then return "rbxassetid://" .. raw end
	return raw
end

local function kidsTileTextureId(hall)
	local palette = kidsPalette(hall)
	local slotName = LEVEL2_KIDS_TILE_TEXTURE_SLOTS[palette.Name]
	local assets = ReplicatedStorage:FindFirstChild("Level 2 Assets")
	local slot = slotName and assets and assets:FindFirstChild(slotName)
	if not slot or not slot:IsA("StringValue") then return nil end
	return normalizedAssetId(slot.Value)
end

local function kidsTextureFaces(size, faces)
	if faces then return faces end
	if size.X <= math.min(size.Y, size.Z) then
		return {Enum.NormalId.Left, Enum.NormalId.Right}
	elseif size.Z <= math.min(size.X, size.Y) then
		return {Enum.NormalId.Front, Enum.NormalId.Back}
	elseif size.Y <= math.min(size.X, size.Z) then
		return {Enum.NormalId.Top, Enum.NormalId.Bottom}
	end
	return Enum.NormalId:GetEnumItems()
end

local function addKidsTileTexture(object, hall, faces, studs)
	local textureId = kidsTileTextureId(hall)
	if not textureId then return object end
	local palette = kidsPalette(hall)
	for _, face in ipairs(kidsTextureFaces(object.Size, faces)) do
		local texture = Instance.new("Texture")
		texture.Name = "Level 2 Kids " .. palette.Name .. " Tile Texture"
		texture.Texture = textureId
		texture.Face = face
		texture.StudsPerTileU = studs or LEVEL2_KIDS_TILE_STUDS
		texture.StudsPerTileV = studs or LEVEL2_KIDS_TILE_STUDS
		texture.Color3 = Color3.new(1, 1, 1)
		texture.Transparency = .08
		texture:SetAttribute("Level2_KidsPalette", palette.Name)
		texture.Parent = object
	end
	return object
end

local function surfaceFor(hall, parent, name, cframe, size, tileColor, faces, studs)
	if isKids(hall) then
		local object = part(parent, name, cframe, size,
			tileColor or kidsPalette(hall).Color, Enum.Material.SmoothPlastic)
		return addKidsTileTexture(object, hall, faces, studs)
	end
	return tiledPart(parent, name, cframe, size, tileColor, faces, studs)
end

-- Water depth for a hall, or nil for a genuinely dry room. Water is
-- wall-to-wall: the whole floor is recessed by this amount and flooded.
local function hallWaterDepth(hall)
	if hall.Role == "Kids Area" or hall.Role == "Arrival"
		or hall.Role == "Exit" then
		return nil
	end
	-- Pump rooms carry shallow water under their raised walkway ring.
	if hall.Role == "Pump Station" then return 1.2 end
	if hall.Role == "Slide Hall" then return Configuration.SlidePoolDepth end
	if hall.PoolType == "Deep" then return Configuration.DeepPoolDepth end
	return Configuration.ShallowPoolDepth
end

-- Kids geometry keeps the global room shell/door height, but its walkable floor
-- sits slightly lower so the .9-stud wading layer shares the corridor surface.
local function hallFloorY(hall)
	if isKids(hall) then
		return -(Configuration.KidsWadingDepth or .8)
	end
	return 0
end

-- ── walls ───────────────────────────────────────────────────────────────────

local function makeWallWithGaps(parent, hall, name, axis, cross, low, high, gaps, height, bottomY, flumeGap)
	height = height or hallHeight(hall)
	bottomY = bottomY or -4
	local thickness = Configuration.WallThickness
	-- Embed wall tops into the existing ceiling slab. A perfectly flush butt
	-- joint lets sunlight/shadow bias reveal a bright line around entire rooms.
	-- Use a deep hidden overlap, not a barely-coplanar seal. The extra height is
	-- entirely buried inside the existing two-stud ceiling/roof slabs.
	local wallTop = height + 1.85
	local fullHeight = wallTop - bottomY
	local centerY = (wallTop + bottomY) * .5
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

	-- Carry both wall ends beyond the nominal room bounds. Perpendicular walls
	-- now overlap on the OUTSIDE of the room instead of relying on a perfectly
	-- flush corner, which is vulnerable to sunlight/shadow bias. Door and flume
	-- openings remain clamped to the authored room span below.
	local geometryLow = low - thickness * .5 - .85
	local geometryHigh = high + thickness * .5 + .85
	local cursor = geometryLow
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
				local lintelHeight = wallTop - doorHeight
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
				if wallTop - opening.top > .1 then
					surfaceFor(hall, parent, name .. " Header",
						CFrame.new(positionFor((gapLow + gapHigh) * .5, (wallTop + opening.top) * .5)),
						sizeFor(span, wallTop - opening.top), wallColor, nil, 7)
				end
			end
		end
		cursor = math.max(cursor, gapHigh)
	end
	if geometryHigh - cursor > .1 then
		surfaceFor(hall, parent, name, CFrame.new(positionFor((cursor + geometryHigh) * .5, centerY)),
			sizeFor(geometryHigh - cursor, fullHeight), wallColor, nil, 7)
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
	if isKids(hall) then
		local depth = Configuration.KidsWadingDepth or .8
		local floorY = -depth
		local slab = surfaceFor(hall, parent, "Level 2 Hall Floor",
			CFrame.new(hall.Center + Vector3.new(0, floorY - .35, 0)),
			Vector3.new(hall.Width, .7, hall.Depth), kidsPalette(hall).Accent,
			{Enum.NormalId.Top}, LEVEL2_KIDS_TILE_STUDS)
		slab.CanCollide = true
		slab:SetAttribute("Level2_EntityGround", true)
		-- Preserve the existing .9-stud film relative to its floor while moving
		-- the whole volume below Y=.1, exactly matching corridor water surfaces.
		local waterHeight = depth + .1
		addWater(hall.Center + Vector3.new(0, .1 - waterHeight * .5, 0),
			Vector3.new(hall.Width + 1.5, waterHeight, hall.Depth + 1.5),
			hall.Id .. " Kids Film")
		return depth
	end
	local depth = hallWaterDepth(hall)
	if not depth then
		local slab = surfaceFor(hall, parent, "Level 2 Hall Floor",
			CFrame.new(hall.Center + Vector3.new(0, -.35, 0)),
			Vector3.new(hall.Width, .7, hall.Depth), C.TileWarm, {Enum.NormalId.Top}, 7)
		slab.CanCollide = true
		slab:SetAttribute("Level2_EntityGround", true)
		return nil
	end
	local slab = tiledPart(parent, "Level 2 Hall Water Floor",
		CFrame.new(hall.Center + Vector3.new(0, -depth - .6, 0)),
		Vector3.new(hall.Width, 1.2, hall.Depth), C.TileCool, {Enum.NormalId.Top}, 10)
	slab.CanCollide = true
	slab:SetAttribute("Level2_EntityGround", true)
	local waterHeight = depth + .1
	-- Overlap slightly INTO the walls so voxel snapping can never leave a
	-- dry strip along the skirting.
	addWater(hall.Center + Vector3.new(0, .1 - waterHeight * .5, 0),
		Vector3.new(hall.Width + 1.5, waterHeight, hall.Depth + 1.5), hall.Id)
	return depth
end

-- Skylight slot layout for a hall — shared by the ceiling builder and the
-- light placer, so a ceiling light can never be built inside a skylight
-- opening (they used to coincide whenever the slot and light grids aligned).
local availableKidsRoundSkylightVariants

local function skylightSlotsFor(hall)
	if isKids(hall) then return {}, 0 end
	-- Arrival is intentionally bright and immediately readable. Keep a
	-- deterministic pair (or more in especially long rooms) of centred
	-- skylights instead of letting the ordinary hall lottery seal the spawn.
	if hall.Role == "Arrival" then
		local axis = hall.Width >= hall.Depth and "X" or "Z"
		local along = axis == "X" and hall.Width or hall.Depth
		local low = axis == "X" and hall.MinX or hall.MinZ
		local count = math.clamp(math.floor(along / 58), 2, 4)
		local slots = {}
		for slot = 1, count do
			table.insert(slots, low + (slot / (count + 1)) * along)
		end
		return slots, 14, axis, "Centre"
	end
	-- Skylights are accents, not the default ceiling of every room. Service,
	-- and entity spaces stay enclosed; one deterministic third of the
	-- ordinary halls does too, giving the route real light/dark rhythm.
	local enclosedRole = hall.Role == "Pump Station"
		or hall.Role == "Entity Den"
		or hall.Role == "Entity Den B"
		or hall.Archetype == "Spiral Stair Well"
	if enclosedRole then return {}, 0 end
	local authoredSkylight = hall.Archetype == "Skylight Hall" or hall.Role == "Slide Hall"
	local hallKey = math.floor(tonumber(hall.LocalSeed) or tonumber(hall.Index) or 0)
	-- Only one ordinary hall in six stays enclosed; sunlight is the default.
	if not authoredSkylight and hallKey % 6 == 0 then return {}, 0 end

	-- Pattern and axis are decided HERE so the ceiling builder and the
	-- column-dodging helpers always agree.
	local roll = Random.new(hallKey + 4177):NextNumber()
	local pattern = (authoredSkylight or roll < .3) and "Lines"
		or roll < .48 and "Dashed"
		or roll < .66 and "Punched"
		or roll < .8 and "Centre"
		or "Round"
	if pattern == "Round" then
		local _, variants = availableKidsRoundSkylightVariants(hall)
		if #variants == 0 then pattern = "Punched" end
	end
	-- Strips may run crosswise only in colonnade-free archetypes, where no
	-- column placement depends on X-band dodging.
	local rotatable = hall.Archetype == "Ring Corridor"
		or hall.Archetype == "Porthole Hall"
		or hall.Archetype == "Spiral Stair Well"
	local axis = (rotatable and pattern ~= "Round" and hallKey % 3 == 1) and "Z" or "X"

	if pattern == "Round" then
		local count = math.clamp(math.floor(hall.Width / 60), 2, 4)
		local xs = {}
		for slot = 1, count do
			table.insert(xs, hall.MinX + (slot / (count + 1)) * hall.Width)
		end
		return xs, 30, "X", pattern
	end
	local along = axis == "X" and hall.Width or hall.Depth
	local low = axis == "X" and hall.MinX or hall.MinZ
	local slots = math.clamp(math.floor(along / 48), 1, 5)
	local slotWidth = 12
	local xs = {}
	for slot = 1, slots do
		table.insert(xs, low + (slot / (slots + 1)) * along)
	end
	if hall.Role == "Slide Hall" and axis == "X" then
		-- The slide hall's two structural column lines are fixed by its deck,
		-- helix, bridge, and stair geometry. Reserve those roof bands instead of
		-- relocating a helix column until its slide no longer fits.
		local offset = math.min(hall.Width * .30, hall.Width * .5 - 16)
		local reserved = {hall.Center.X - offset, hall.Center.X + offset}
		local filtered = {}
		for _, slotX in ipairs(xs) do
			local clear = true
			for _, reservedX in ipairs(reserved) do
				if math.abs(slotX - reservedX) < slotWidth * .5 + 11.5 then
					clear = false
					break
				end
			end
			if clear then table.insert(filtered, slotX) end
		end
		xs = #filtered > 0 and filtered or {hall.Center.X}
	end
	return xs, slotWidth, axis, pattern
end

-- The exact open spans are shared by ceiling construction and column
-- placement. Keeping this in one place prevents a visually solid column from
-- being accepted under a punched/dashed opening (or rejected under solid roof).
local function skylightOpenIntervals(hall, slotWidth, slotAxis, pattern, slotIndex)
	local crossLow = slotAxis == "Z" and hall.MinX or hall.MinZ
	local crossHigh = slotAxis == "Z" and hall.MaxX or hall.MaxZ
	local minC, maxC = crossLow + 2, crossHigh - 2
	local span = maxC - minC
	if pattern == "Lines" then
		return {{minC, maxC}}
	elseif pattern == "Centre" then
		local bandWidth = span * .45
		local mid = (minC + maxC) * .5
		return {{mid - bandWidth * .5, mid + bandWidth * .5}}
	elseif pattern == "Dashed" then
		local count = math.clamp(math.floor(span / 70) + 2, 2, 4)
		local step = span / count
		local opens = {}
		for dash = 1, count do
			local c0 = minC + (dash - 1) * step + step * .16
			table.insert(opens, {c0, c0 + step * .68})
		end
		return opens
	end
	-- Punched: square openings marching down the strip, alternate slots
	-- phase-shifted for a checkerboard.
	local punchSize = slotWidth + 4
	local count = math.clamp(math.floor(span / (punchSize * 2.4)), 2, 6)
	local step = span / count
	local phase = slotIndex % 2 == 0 and step * .5 or 0
	local opens = {}
	for punch = 1, count do
		local mid = minC + (punch - .5) * step + phase
		if mid + punchSize * .5 <= maxC then
			table.insert(opens, {mid - punchSize * .5, mid + punchSize * .5})
		end
	end
	return opens
end

local overlapsSkylight

-- Kids rooms use deterministic round roof openings instead of artificial
-- ceiling panels.  The cutters are kept comfortably inside the room bounds,
-- separated from one another, and covered by almost-clear safety glass so no
-- player can ever escape through the roof.
local LEVEL2_KIDS_ROUND_SKYLIGHT_TEMPLATES = "Level 2 Kids Round Skylight Templates"
local LEVEL2_KIDS_ROUND_SKYLIGHT_VARIANTS = {
	{Name = "Level 2 Kids Round Skylight Module Small", ModuleSize = 22, Radius = 7},
	{Name = "Level 2 Kids Round Skylight Module Medium", ModuleSize = 28, Radius = 10},
	{Name = "Level 2 Kids Round Skylight Module Large", ModuleSize = 36, Radius = 14},
}

function availableKidsRoundSkylightVariants(hall)
	local templateFolder = ServerStorage:FindFirstChild(LEVEL2_KIDS_ROUND_SKYLIGHT_TEMPLATES)
	if not templateFolder then return nil, {} end

	local shortSide = math.min(hall.Width, hall.Depth)
	local variants = {}
	for _, specification in ipairs(LEVEL2_KIDS_ROUND_SKYLIGHT_VARIANTS) do
		local template = templateFolder:FindFirstChild(specification.Name)
		if template and template:IsA("UnionOperation")
			and specification.ModuleSize <= shortSide - 16 then
			table.insert(variants, specification)
		end
	end
	return templateFolder, variants
end

-- Standard round skylights use the largest baked aperture that fits. Return
-- the same centres to both the ceiling builder and the column-clearance test.
local function roundSkylightOpeningsFor(hall, xs)
	local templateFolder, variants = availableKidsRoundSkylightVariants(hall)
	table.sort(variants, function(a, b) return a.ModuleSize > b.ModuleSize end)
	local variant = variants[1]
	if not variant then return {}, nil, templateFolder end
	local zFractions = ({{0}, {-.16, .18}, {-.2, .18, -.02},
		{-.22, .14, -.04, .24}})[#xs] or {0}
	local openings = {}
	for slotIndex, x in ipairs(xs) do
		local half = variant.ModuleSize * .5
		local z = math.clamp(
			hall.Center.Z + (zFractions[slotIndex] or 0) * hall.Depth,
			hall.MinZ + half + 4, hall.MaxZ - half - 4)
		table.insert(openings, {
			X = x,
			Z = z,
			HalfSize = half,
			Radius = variant.Radius,
		})
	end
	return openings, variant, templateFolder
end

-- Two-dimensional aperture test. `width` is the full outside diameter of the
-- object (including a column capital), not merely its shaft. Rectangular and
-- circular skylights are tested against their real opening rather than only
-- their slot's X coordinate.
overlapsSkylight = function(hall, x, z, width)
	local xs, slotWidth, slotAxis, pattern = skylightSlotsFor(hall)
	if #xs == 0 then return false end
	local objectRadius = width * .5 + .45
	if pattern == "Round" then
		local openings = roundSkylightOpeningsFor(hall, xs)
		for _, opening in ipairs(openings) do
			local dx, dz = x - opening.X, z - opening.Z
			if dx * dx + dz * dz
				< (opening.Radius + objectRadius) ^ 2 then
				return true
			end
		end
		return false
	end

	for slotIndex, along in ipairs(xs) do
		for _, interval in ipairs(skylightOpenIntervals(
			hall, slotWidth, slotAxis, pattern, slotIndex)) do
			local minX, maxX, minZ, maxZ
			if slotAxis == "Z" then
				minX, maxX = interval[1], interval[2]
				minZ, maxZ = along - slotWidth * .5, along + slotWidth * .5
			else
				minX, maxX = along - slotWidth * .5, along + slotWidth * .5
				minZ, maxZ = interval[1], interval[2]
			end
			if x + objectRadius > minX and x - objectRadius < maxX
				and z + objectRadius > minZ and z - objectRadius < maxZ then
				return true
			end
		end
	end
	return false
end

local function kidsRoundSkylightPlan(hall, variants)
	local rng = Random.new((hall.LocalSeed or hall.Index or 1) + 728391)
	local area = hall.Area or (hall.Width * hall.Depth)
	-- Kids Area needs a busier, more exposed overhead: start with the largest
	-- baked aperture and pack in substantially more modules than normal halls.
	table.sort(variants, function(a, b) return a.ModuleSize > b.ModuleSize end)
	local targetCount = math.clamp(math.floor(area / 4200) + 2, 4, 7)
	local edgeClearance = 5
	local moduleSpacing = 4
	local openings = {}

	local function clearAt(x, z, halfSize)
		for _, other in ipairs(openings) do
			local overlapsX = math.abs(x - other.X) < halfSize + other.HalfSize + moduleSpacing
			local overlapsZ = math.abs(z - other.Z) < halfSize + other.HalfSize + moduleSpacing
			if overlapsX and overlapsZ then return false end
		end
		return true
	end

	local fallbackPositions = {
		{.25, .25}, {.75, .72}, {.27, .76}, {.72, .27},
		{.50, .50}, {.50, .23}, {.23, .50}, {.77, .50},
	}

	for openingIndex = 1, targetCount do
		local placed = false
		for variantIndex, variant in ipairs(variants) do
			local halfSize = variant.ModuleSize * .5
			local minX = hall.MinX + halfSize + edgeClearance
			local maxX = hall.MaxX - halfSize - edgeClearance
			local minZ = hall.MinZ + halfSize + edgeClearance
			local maxZ = hall.MaxZ - halfSize - edgeClearance

			if minX < maxX and minZ < maxZ then
				for _ = 1, 150 do
					local x = rng:NextNumber(minX, maxX)
					local z = rng:NextNumber(minZ, maxZ)
					if clearAt(x, z, halfSize) then
						table.insert(openings, {
							X = x,
							Z = z,
							Radius = variant.Radius,
							ModuleSize = variant.ModuleSize,
							HalfSize = halfSize,
							TemplateName = variant.Name,
						})
						placed = true
						break
					end
				end

				if not placed then
					for _, normalized in ipairs(fallbackPositions) do
						local x = minX + (maxX - minX) * normalized[1]
						local z = minZ + (maxZ - minZ) * normalized[2]
						if clearAt(x, z, halfSize) then
							table.insert(openings, {
								X = x,
								Z = z,
								Radius = variant.Radius,
								ModuleSize = variant.ModuleSize,
								HalfSize = halfSize,
								TemplateName = variant.Name,
							})
							placed = true
							break
						end
					end
				end
			end
			if placed then break end
		end
		if not placed then break end
	end

	return openings
end

local function makeKidsFallbackSkylight(parent, hall, index, height)
	local radius = math.clamp(math.min(hall.Width, hall.Depth) * .09, 7, 12)
	local pane = part(parent, "Level 2 Kids Round Skylight Fallback " .. index,
		CFrame.new(hall.Center.X, height - .08, hall.Center.Z) * CFrame.Angles(0, 0, math.rad(90)),
		Vector3.new(.16, radius * 2, radius * 2),
		Color3.fromRGB(235, 247, 255), Enum.Material.Neon, .12)
	pane.Shape = Enum.PartType.Cylinder
	pane.CanCollide = false
	pane.CanTouch = false
	pane.CastShadow = false

	local fill = Instance.new("SurfaceLight")
	fill.Name = "Level 2 Kids Skylight Fallback Daylight"
	fill.Face = Enum.NormalId.Left
	fill.Color = Color3.fromRGB(235, 247, 255)
	fill.Brightness = .56
	fill.Range = 42
	fill.Angle = 120
	fill.Shadows = true
	fill.Parent = pane
end

local function makeKidsCeilingSlab(parent, hall, palette, height, x0, x1, z0, z1, index)
	if x1 - x0 <= .08 or z1 - z0 <= .08 then return index end
	index += 1
	local slab = surfaceFor(hall, parent, "Level 2 Kids Ceiling Slab " .. index,
		CFrame.new((x0 + x1) * .5, height + 1, (z0 + z1) * .5),
		Vector3.new(x1 - x0, 2, z1 - z0),
		palette.Accent, {Enum.NormalId.Bottom}, LEVEL2_KIDS_TILE_STUDS)
	slab.CanCollide = true
	slab.CastShadow = true
	slab:SetAttribute("Level2_KidsNaturalSkylightCeiling", true)
	return index
end

local function makeKidsSolidCeilingFallback(parent, hall, palette, height)
	local ceiling = surfaceFor(hall, parent, "Level 2 Kids Ceiling Skylight Fallback",
		CFrame.new(hall.Center + Vector3.new(0, height + 1, 0)),
		Vector3.new(hall.Width, 2, hall.Depth),
		palette.Accent, {Enum.NormalId.Bottom}, LEVEL2_KIDS_TILE_STUDS)
	ceiling.CanCollide = true
	ceiling.CastShadow = true
	makeKidsFallbackSkylight(parent, hall, 1, height)
end

local function makeKidsRoundSkylightCeiling(parent, hall)
	local height = hallHeight(hall)
	local palette = kidsPalette(hall)
	local templateFolder, variants = availableKidsRoundSkylightVariants(hall)
	local openings = kidsRoundSkylightPlan(hall, variants)

	if not templateFolder or #variants == 0 or #openings == 0 then
		warn("[Level 2 World Builder] Baked kids skylight templates unavailable; using safe daylight fallback")
		makeKidsSolidCeilingFallback(parent, hall, palette, height)
		return
	end

	-- Split the ceiling around square baked modules. Each module contains one
	-- true circular aperture; ordinary slabs seal every remaining centimetre.
	local zCuts = {hall.MinZ, hall.MaxZ}
	for _, opening in ipairs(openings) do
		table.insert(zCuts, opening.Z - opening.HalfSize)
		table.insert(zCuts, opening.Z + opening.HalfSize)
	end
	table.sort(zCuts)

	local uniqueZ = {}
	for _, z in ipairs(zCuts) do
		z = math.clamp(z, hall.MinZ, hall.MaxZ)
		if #uniqueZ == 0 or math.abs(z - uniqueZ[#uniqueZ]) > .02 then
			table.insert(uniqueZ, z)
		end
	end

	local slabIndex = 0
	for zIndex = 1, #uniqueZ - 1 do
		local z0, z1 = uniqueZ[zIndex], uniqueZ[zIndex + 1]
		local midpoint = (z0 + z1) * .5
		local blocked = {}
		for _, opening in ipairs(openings) do
			if midpoint > opening.Z - opening.HalfSize - .02
				and midpoint < opening.Z + opening.HalfSize + .02 then
				table.insert(blocked, {
					Minimum = opening.X - opening.HalfSize,
					Maximum = opening.X + opening.HalfSize,
				})
			end
		end
		table.sort(blocked, function(a, b) return a.Minimum < b.Minimum end)

		local cursor = hall.MinX
		for _, interval in ipairs(blocked) do
			local intervalStart = math.clamp(interval.Minimum, hall.MinX, hall.MaxX)
			local intervalEnd = math.clamp(interval.Maximum, hall.MinX, hall.MaxX)
			if intervalStart > cursor then
				slabIndex = makeKidsCeilingSlab(parent, hall, palette, height,
					cursor, intervalStart, z0, z1, slabIndex)
			end
			cursor = math.max(cursor, intervalEnd)
		end
		if cursor < hall.MaxX then
			slabIndex = makeKidsCeilingSlab(parent, hall, palette, height,
				cursor, hall.MaxX, z0, z1, slabIndex)
		end
	end

	for index, opening in ipairs(openings) do
		local template = templateFolder:FindFirstChild(opening.TemplateName)
		if not template or not template:IsA("UnionOperation") then
			warn("[Level 2 World Builder] Missing baked skylight module " .. opening.TemplateName)
			makeKidsCeilingSlab(parent, hall, palette, height,
				opening.X - opening.HalfSize, opening.X + opening.HalfSize,
				opening.Z - opening.HalfSize, opening.Z + opening.HalfSize, slabIndex)
			continue
		end

		local module = template:Clone()
		module.Name = "Level 2 Kids Round Skylight Ceiling Module " .. index
		module.CFrame = CFrame.new(opening.X, height + 1, opening.Z)
		module.Color = palette.Accent
		module.Material = Enum.Material.SmoothPlastic
		module.MaterialVariant = ""
		module.Transparency = 0
		module.Anchored = true
		module.CanCollide = true
		module.CanTouch = true
		module.CanQuery = true
		module.CastShadow = true
		module:SetAttribute("Level2_NaturalSkylight", true)
		module:SetAttribute("Level2_SkylightRadius", opening.Radius)
		module:SetAttribute("Level2_SkylightModuleSize", opening.ModuleSize)
		module:SetAttribute("Level2_SkylightVariant", opening.TemplateName)
		pcall(function() module.UsePartColor = true end)
		module.Parent = parent
		addKidsTileTexture(module, hall, {Enum.NormalId.Bottom}, LEVEL2_KIDS_TILE_STUDS)

		local pane = part(parent, "Level 2 Kids Round Skylight Glass " .. index,
			CFrame.new(opening.X, height + 1.72, opening.Z) * CFrame.Angles(0, 0, math.rad(90)),
			Vector3.new(.32, opening.Radius * 2, opening.Radius * 2),
			Color3.fromRGB(226, 242, 250), Enum.Material.Glass, .82)
		pane.Shape = Enum.PartType.Cylinder
		pane.CanCollide = true
		pane.CanTouch = false
		pane.CanQuery = true
		pane.CastShadow = false
		pane.Reflectance = .04
		pane:SetAttribute("Level2_SkylightRadius", opening.Radius)
		pane:SetAttribute("Level2_NaturalLight", true)
	end
end

-- The visible ceiling slabs stop at each wall centreline. Shadow-map bias could
-- therefore still see past the outer half of a wall at grazing angles, showing
-- a bright perimeter even though the room was mathematically closed. These
-- four opaque, non-interactive strips continue every ceiling well beyond the
-- wall's outer face without covering any skylight or becoming visible indoors.
local CEILING_EDGE_SEAL_OVERHANG = 6
local CEILING_EDGE_SEAL_INSET = .5
local CEILING_EDGE_SEAL_THICKNESS = 3
local CEILING_COVE_DEPTH = 1.25
local CEILING_COVE_DROP = 3
local CEILING_KIDS_COVE_DROP = 1.5
local function makeExteriorCeilingEdgeSeal(parent, hall, color)
	local height = hallHeight(hall)
	local overhang = CEILING_EDGE_SEAL_OVERHANG
	local inset = CEILING_EDGE_SEAL_INSET
	local edgeSpan = overhang + inset
	local edgeOffset = (overhang - inset) * .5
	local sealY = height + CEILING_EDGE_SEAL_THICKNESS * .5
	local pieces = {
		{Vector3.new(hall.Center.X, sealY, hall.MinZ - edgeOffset),
			Vector3.new(hall.Width + overhang * 2, CEILING_EDGE_SEAL_THICKNESS, edgeSpan)},
		{Vector3.new(hall.Center.X, sealY, hall.MaxZ + edgeOffset),
			Vector3.new(hall.Width + overhang * 2, CEILING_EDGE_SEAL_THICKNESS, edgeSpan)},
		{Vector3.new(hall.MinX - edgeOffset, sealY, hall.Center.Z),
			Vector3.new(edgeSpan, CEILING_EDGE_SEAL_THICKNESS, hall.Depth - inset * 2)},
		{Vector3.new(hall.MaxX + edgeOffset, sealY, hall.Center.Z),
			Vector3.new(edgeSpan, CEILING_EDGE_SEAL_THICKNESS, hall.Depth - inset * 2)},
	}
	for index, data in ipairs(pieces) do
		local seal = part(parent, "Level 2 Exterior Light Seal " .. index,
			CFrame.new(data[1]), data[2], color, Enum.Material.SmoothPlastic)
		seal.CanCollide = false
		seal.CanTouch = false
		seal.CanQuery = false
		seal.CastShadow = true
		seal:SetAttribute("Level2_CeilingLightSeal", true)
	end
end

-- Skylight/environment diffuse light can still brighten the uppermost wall
-- even after the exterior joint is fully sealed. A shallow dropped cove masks
-- that lit strip and gives the perimeter an intentional dark shadow reveal.
-- It stays above every doorway and never participates in collision or queries.
local function makeInteriorCeilingCove(parent, hall)
	local height = hallHeight(hall)
	local wallHalf = Configuration.WallThickness * .5
	local depth = CEILING_COVE_DEPTH
	local drop = isKids(hall) and CEILING_KIDS_COVE_DROP or CEILING_COVE_DROP
	local innerWidth = hall.Width - Configuration.WallThickness
	local innerDepth = hall.Depth - Configuration.WallThickness
	local sideRun = math.max(.1, innerDepth - depth * 2)
	local pieces = {
		{Vector3.new(hall.Center.X, height - drop * .5,
			hall.MinZ + wallHalf + depth * .5), Vector3.new(innerWidth, drop, depth)},
		{Vector3.new(hall.Center.X, height - drop * .5,
			hall.MaxZ - wallHalf - depth * .5), Vector3.new(innerWidth, drop, depth)},
		{Vector3.new(hall.MinX + wallHalf + depth * .5,
			height - drop * .5, hall.Center.Z), Vector3.new(depth, drop, sideRun)},
		{Vector3.new(hall.MaxX - wallHalf - depth * .5,
			height - drop * .5, hall.Center.Z), Vector3.new(depth, drop, sideRun)},
	}
	for index, data in ipairs(pieces) do
		local cove = part(parent, "Level 2 Perimeter Shadow Cove " .. index,
			CFrame.new(data[1]), data[2], C.Metal, Enum.Material.SmoothPlastic)
		cove.CanCollide = false
		cove.CanTouch = false
		cove.CanQuery = false
		cove.CastShadow = true
		cove:SetAttribute("Level2_CeilingShadowCove", true)
	end
end

-- Ceilings carry real skylight openings with non-shadow-casting safety glass.
-- Kids rooms use baked circular modules so their geometry replicates reliably.
local function makeHallCeiling(parent, hall)
	local height = hallHeight(hall)
	local color = isKids(hall) and kidsPalette(hall).Accent or C.TileCool
	makeExteriorCeilingEdgeSeal(parent, hall, color)
	makeInteriorCeilingCove(parent, hall)
	if isKids(hall) then
		makeKidsRoundSkylightCeiling(parent, hall)
		return
	end

	local xs, slotWidth, slotAxis, pattern = skylightSlotsFor(hall)
	table.sort(xs)

	if pattern == "Round" then
		-- True circular skylights: the baked round modules (born in the kids
		-- wing) recolored for the tiled halls, sealed with faint safety glass.
		local openings, variant, templateFolder = roundSkylightOpeningsFor(hall, xs)
		local zCuts = {hall.MinZ, hall.MaxZ}
		for _, opening in ipairs(openings) do
			table.insert(zCuts, opening.Z - opening.HalfSize)
			table.insert(zCuts, opening.Z + opening.HalfSize)
		end
		table.sort(zCuts)
		for zIndex = 1, #zCuts - 1 do
			local z0, z1 = zCuts[zIndex], zCuts[zIndex + 1]
			if z1 - z0 > .05 then
				local midpoint = (z0 + z1) * .5
				local cursor = hall.MinX
				for _, opening in ipairs(openings) do
					if midpoint > opening.Z - opening.HalfSize - .02
						and midpoint < opening.Z + opening.HalfSize + .02 then
						if opening.X - opening.HalfSize > cursor + .05 then
							local slab = tiledPart(parent, "Level 2 Hall Ceiling",
								CFrame.new(Vector3.new(
									(cursor + opening.X - opening.HalfSize) * .5,
									height + 1, midpoint)),
								Vector3.new(opening.X - opening.HalfSize - cursor, 2, z1 - z0),
								color, {Enum.NormalId.Bottom}, 9)
							slab.CanCollide = true
						end
						cursor = math.max(cursor, opening.X + opening.HalfSize)
					end
				end
				if hall.MaxX - cursor > .05 then
					local slab = tiledPart(parent, "Level 2 Hall Ceiling",
						CFrame.new(Vector3.new((cursor + hall.MaxX) * .5, height + 1, midpoint)),
						Vector3.new(hall.MaxX - cursor, 2, z1 - z0), color, {Enum.NormalId.Bottom}, 9)
					slab.CanCollide = true
				end
			end
		end
		for index, opening in ipairs(openings) do
			local template = templateFolder and templateFolder:FindFirstChild(variant.Name)
			if template then
				local module = template:Clone()
				module.Name = "Level 2 Round Skylight Module " .. index
				module.CFrame = CFrame.new(opening.X, height + 1, opening.Z)
				module.Color = color
				module.Material = Enum.Material.SmoothPlastic
				module.MaterialVariant = ""
				module.Transparency = 0
				module.Anchored = true
				module.CanCollide = true
				pcall(function() module.UsePartColor = true end)
				module.Parent = parent
				addTexture(module, {Enum.NormalId.Bottom}, 9)
				local pane = part(parent, "Level 2 Frosted Skylight Diffuser",
					CFrame.new(opening.X, height + 1.72, opening.Z) * CFrame.Angles(0, 0, math.rad(90)),
					Vector3.new(.32, variant.Radius * 2, variant.Radius * 2),
					Color3.fromRGB(226, 242, 250), Enum.Material.Glass, .82)
				pane.Shape = Enum.PartType.Cylinder
				pane.CanCollide = true
				pane.CanTouch = false
				pane.CastShadow = false
				pane.Reflectance = .04
			else
				local slab = tiledPart(parent, "Level 2 Hall Ceiling",
					CFrame.new(Vector3.new(opening.X, height + 1, opening.Z)),
					Vector3.new(opening.HalfSize * 2, 2, opening.HalfSize * 2),
					color, {Enum.NormalId.Bottom}, 9)
				slab.CanCollide = true
			end
		end
		return
	end

	-- Strip patterns, axis-neutral: "along" runs down the strip positions,
	-- "cross" runs along each strip's length.
	local axisX = slotAxis ~= "Z"
	local alongLow = axisX and hall.MinX or hall.MinZ
	local alongHigh = axisX and hall.MaxX or hall.MaxZ
	local crossLow = axisX and hall.MinZ or hall.MinX
	local crossHigh = axisX and hall.MaxZ or hall.MaxX
	local crossCenter = (crossLow + crossHigh) * .5

	local function ceilingPiece(alongCenter, alongSize, crossPos, crossSize, isPane)
		local cf, size
		if axisX then
			cf = CFrame.new(Vector3.new(alongCenter, height + 1, crossPos))
			size = Vector3.new(alongSize, isPane and .6 or 2, crossSize)
		else
			cf = CFrame.new(Vector3.new(crossPos, height + 1, alongCenter))
			size = Vector3.new(crossSize, isPane and .6 or 2, alongSize)
		end
		if isPane then
			local pane = part(parent, "Level 2 Frosted Skylight Diffuser", cf, size,
				Color3.fromRGB(218, 231, 226), Enum.Material.SmoothPlastic, 1)
			pane.CanCollide = true
			pane.CanTouch = false
			pane.CastShadow = false
			return pane
		end
		local slab = tiledPart(parent, "Level 2 Hall Ceiling", cf, size,
			color, {Enum.NormalId.Bottom}, 9)
		slab.CanCollide = true
		return slab
	end

	local function openIntervals(slotIndex)
		return skylightOpenIntervals(hall, slotWidth, slotAxis, pattern, slotIndex)
	end

	local cursor = alongLow
	for slotIndex, x in ipairs(xs) do
		local segmentEnd = x - slotWidth * .5
		if segmentEnd - cursor > .5 then
			ceilingPiece((cursor + segmentEnd) * .5, segmentEnd - cursor,
				crossCenter, crossHigh - crossLow, false)
		end
		local cCursor = crossLow
		for _, open in ipairs(openIntervals(slotIndex)) do
			if open[1] - cCursor > .5 then
				ceilingPiece(x, slotWidth, (cCursor + open[1]) * .5, open[1] - cCursor, false)
			end
			ceilingPiece(x, slotWidth, (open[1] + open[2]) * .5, open[2] - open[1], true)
			cCursor = open[2]
		end
		if crossHigh - cCursor > .5 then
			ceilingPiece(x, slotWidth, (cCursor + crossHigh) * .5, crossHigh - cCursor, false)
		end
		cursor = x + slotWidth * .5
	end
	if alongHigh - cursor > .5 then
		ceilingPiece((cursor + alongHigh) * .5, alongHigh - cursor,
			crossCenter, crossHigh - crossLow, false)
	end
end

-- Raised wading pool for the kids wing (water above the floor, no digging).
local function makeRaisedPool(parent, center, width, depth3, hall)
	local palette = kidsPalette(hall)
	local wallHeight = 2.4
	local shellBottom = part(parent, "Level 2 Kids Pool Base",
		CFrame.new(center + Vector3.new(0, .15, 0)), Vector3.new(width, .3, depth3),
		mutedKidsColor(palette.Accent, .35), Enum.Material.Rubber)
	useKidsMaterial(shellBottom, Enum.Material.Rubber, LEVEL2_KIDS_FLOOR_VARIANT)
	shellBottom.CanCollide = true
	for _, data in ipairs({
		{Vector3.new(-width * .5, wallHeight * .5, 0), Vector3.new(1.2, wallHeight, depth3)},
		{Vector3.new(width * .5, wallHeight * .5, 0), Vector3.new(1.2, wallHeight, depth3)},
		{Vector3.new(0, wallHeight * .5, -depth3 * .5), Vector3.new(width, wallHeight, 1.2)},
		{Vector3.new(0, wallHeight * .5, depth3 * .5), Vector3.new(width, wallHeight, 1.2)},
	}) do
		local poolWall = part(parent, "Level 2 Kids Pool Wall", CFrame.new(center + data[1]), data[2],
			palette.Color, Enum.Material.SmoothPlastic)
		addKidsTileTexture(poolWall, hall)
		poolWall.CanCollide = true
	end
	local poolStep = part(parent, "Level 2 Kids Pool Step",
		CFrame.new(center + Vector3.new(0, .6, depth3 * .5 + 2)), Vector3.new(10, 1.2, 3.4),
		mutedKidsColor(palette.Accent, .28), Enum.Material.Rubber)
	useKidsMaterial(poolStep, Enum.Material.Rubber, LEVEL2_KIDS_FLOOR_VARIANT)
	poolStep.CanCollide = true
	-- Terrain water is voxelized in four-stud cells. Keeping a full-size shallow
	-- fill here made the raised pool bleed through its walls and raise the water
	-- around the pool. Retain a deeply inset swimming core and cover the dry rim
	-- with a visual water sheet that cannot affect character state.
	local terrainWidth = width - 12
	local terrainDepth = depth3 - 12
	if terrainWidth >= 4 and terrainDepth >= 4 then
		addWater(center + Vector3.new(0, wallHeight * .5 + .2, 0),
			Vector3.new(terrainWidth, wallHeight - .6, terrainDepth), "Kids Pool")
	end
	local waterTop = center.Y + wallHeight - .1
	local waterVisual = part(parent, "Level 2 Kids Pool Water Surface",
		CFrame.new(center.X, waterTop, center.Z),
		Vector3.new(math.max(1, width - 1.4), .05, math.max(1, depth3 - 1.4)),
		C.Water, Enum.Material.Glass, .34)
	waterVisual.Reflectance = .08
	waterVisual.CanCollide = false
	waterVisual.CanTouch = false
	waterVisual.CanQuery = false
	waterVisual.CastShadow = false
	waterVisual:SetAttribute("Level2_WaterVisual", true)
end

-- ── set pieces ──────────────────────────────────────────────────────────────

-- Every placed column is registered per world so no system can ever build a
-- column inside another one's (colonnades, spiral stairs, kits, islands).
local columnRegistry = setmetatable({}, {__mode = "k"})

local function columnRegistryFor(parent)
	local root = parent
	while root.Parent and root.Name ~= "Level 2 Generated World" do
		root = root.Parent
	end
	local placed = columnRegistry[root]
	if not placed then
		placed = {}
		columnRegistry[root] = placed
	end
	return placed
end

local function columnNear(parent, x, z, range)
	for _, existing in ipairs(columnRegistryFor(parent)) do
		if math.abs(existing.Position.X - x) < range and math.abs(existing.Position.Z - z) < range then
			return true
		end
	end
	return false
end

local columnFlareTemplates = {}
local columnFlareUnavailable = {}
local COLUMN_FLARE_MESHES = {
	[4.5] = "rbxassetid://90304501186271",
	[5.5] = "rbxassetid://118916035196716",
	[9] = "rbxassetid://111134467625970",
}
-- Five nested, floor-origin cylinders trace the reachable half of the authored
-- quarter-cove. Values are exact rows from the flare profile, expressed as
-- world height from the wide floor lip and radius in shaft-diameter units.
local COLUMN_FLARE_COLLISION_BANDS = {
	{Height = .010178566, Radius = 1.0146111},
	{Height = .090368032, Radius = .8507510},
	{Height = .244250417, Radius = .7070836},
	{Height = .459359169, Radius = .5952479},
	{Height = .718267441, Radius = .5243042},
}
-- The render mesh has 40 radial sides. Vertex radii alone would let a true
-- Cylinder protrude between polygon vertices; use the apothem plus tolerance.
local COLUMN_FLARE_COLLISION_INSET = math.cos(math.pi / 40) * .998
local COLUMN_TILE_STUDS = 9

local function columnFlareMeshFor(shaftDiameter)
	for diameter, meshId in pairs(COLUMN_FLARE_MESHES) do
		if math.abs(shaftDiameter - diameter) < .01 then return meshId end
	end
	return COLUMN_FLARE_MESH
end

local function getColumnFlareTemplate(shaftDiameter, flareLength)
	local key = string.format("%.3f:%.3f", shaftDiameter, flareLength)
	local cached = columnFlareTemplates[key]
	if cached and cached.Parent then return cached end
	if columnFlareUnavailable[key] then return nil end

	-- The three owned static assets bake true world-distance UVs for the only
	-- nonessential shaft diameters generated by Level 2. Static delivery keeps
	-- runtime EditableMesh security disabled and adds no scene instances.
	local meshId = columnFlareMeshFor(shaftDiameter)
	-- Adopt the copy this place already holds before building another one.
	--
	-- The Lua cache above is MODULE-LOCAL and dies with the VM, but the MeshPart
	-- it pointed at was parented into ServerStorage and is SAVED WITH THE PLACE.
	-- Every fresh module VM therefore built a new one and left the previous copy
	-- behind for good: by 2026-09-02 ServerStorage held three of each flare
	-- variant and five of each slide template, all identical. Adopting also skips
	-- a redundant CreateMeshPartAsync round trip on every later session.
	local templateName = "Level 2 Column Flare Template " .. key
	local existing = ServerStorage:FindFirstChild(templateName)
	if existing and existing:IsA("MeshPart") and existing.MeshId == meshId then
		-- Re-stamp the attributes rather than trusting a copy an older build
		-- left behind: COLUMN_TILE_STUDS is what the UV scale is derived from.
		existing:SetAttribute("Level2_ColumnFlareShaftDiameter", shaftDiameter)
		existing:SetAttribute("Level2_ColumnFlareTileStuds", COLUMN_TILE_STUDS)
		columnFlareTemplates[key] = existing
		return existing
	end
	local ok, result = pcall(function()
		return AssetService:CreateMeshPartAsync(Content.fromUri(meshId), {
			CollisionFidelity = Enum.CollisionFidelity.Box,
			RenderFidelity = Enum.RenderFidelity.Automatic,
		})
	end)
	if (not ok or not result) and meshId ~= COLUMN_FLARE_MESH then
		-- Geometry remains available if a freshly uploaded UV variant has a
		-- transient delivery problem; the older owned asset is the safe fallback.
		ok, result = pcall(function()
			return AssetService:CreateMeshPartAsync(Content.fromUri(COLUMN_FLARE_MESH), {
				CollisionFidelity = Enum.CollisionFidelity.Box,
				RenderFidelity = Enum.RenderFidelity.Automatic,
			})
		end)
	end
	if not ok or not result then
		columnFlareUnavailable[key] = true
		warn("[Level 2] unable to load smooth column flare: " .. tostring(result))
		return nil
	end

	result.Name = "Level 2 Column Flare Template " .. key
	result.Anchored = true
	result.CanCollide = false
	result.CanTouch = false
	result.CanQuery = false
	result.TextureID = ""
	result.Color = COLUMN_FLARE_COLOR
	result.Material = Enum.Material.SmoothPlastic
	-- ColorMap is PluginSecurity: a live server may clone an authored
	-- SurfaceAppearance, but cannot assign the map itself. Keep that authored
	-- object in ServerStorage and fall back to the direct texture without ever
	-- allowing cosmetic delivery to abort Level 2 generation.
	local surfaceTemplate = ServerStorage:FindFirstChild(COLUMN_FLARE_SURFACE_TEMPLATE)
	local tileSurface
	if surfaceTemplate and surfaceTemplate:IsA("SurfaceAppearance")
		and surfaceTemplate.Archivable then
		local cloned, cloneResult = pcall(function()
			return surfaceTemplate:Clone()
		end)
		if cloned then tileSurface = cloneResult end
	end
	if tileSurface then
		tileSurface.Name = "Level 2 Column Tile Surface"
		tileSurface.Parent = result
	else
		result.TextureID = TILE_TEXTURE
		warn("[Level 2] column tile surface template missing; using direct texture fallback")
	end
	result:SetAttribute("Level2_ColumnFlareShaftDiameter", shaftDiameter)
	result:SetAttribute("Level2_ColumnFlareTileStuds", COLUMN_TILE_STUDS)
	result.Parent = ServerStorage
	columnFlareTemplates[key] = result
	return result
end
-- `essential` columns (spiral stair masts) must exist for their stair to
-- make sense, so they always build and DESTROY any decorative column they
-- would pierce. Decorative columns are skipped instead of overlapping.
local function hiddenColumnSeamYaw(hall, x, z)
	if not hall then return 0 end
	local nearestDistance = math.huge
	local nearestDirection = Vector3.xAxis
	for _, candidate in ipairs({
		{Distance = x - hall.MinX, Direction = -Vector3.xAxis},
		{Distance = hall.MaxX - x, Direction = Vector3.xAxis},
		{Distance = z - hall.MinZ, Direction = -Vector3.zAxis},
		{Distance = hall.MaxZ - z, Direction = Vector3.zAxis},
	}) do
		if candidate.Distance < nearestDistance then
			nearestDistance = candidate.Distance
			nearestDirection = candidate.Direction
		end
	end
	-- The mesh's duplicated 0/2pi UV boundary lies on local +X. Aim that
	-- unavoidable wrap toward the nearest wall instead of the room interior.
	return math.atan2(-nearestDirection.Z, nearestDirection.X)
end

-- The column base's COLLIDABLE shape, built the same way whatever the visual
-- flare turned out to be.
--
-- Roblox discarded most of the open trumpet when generating either Default or
-- precise MeshPart collision, so the base is described by nested primitive
-- cylinders: deterministic, inside every sampled profile row, and they let
-- players contact the complete molded curve instead of clipping through a single
-- low curb to the central shaft.
--
-- It is a FUNCTION rather than an inline block because the fallback path needs
-- exactly the same bands. Before this, a column whose mesh asset arrived got
-- these five bands while a column whose asset delivery failed got five entirely
-- different collidable rings -- different diameters, heights and offsets, and
-- collision on the visual parts themselves. Same seed, different physics and
-- different navmesh, decided by whether an asset download succeeded. That is
-- exactly the non-determinism the seed contract promises does not exist.
local function addColumnBaseFlareCollision(parent, position, radius, flareLength, entry)
	for bandIndex, band in ipairs(COLUMN_FLARE_COLLISION_BANDS) do
		local collisionHeight = flareLength * band.Height
		local collisionDiameter = radius * band.Radius * 2 * COLUMN_FLARE_COLLISION_INSET
		local collision = part(parent,
			string.format("Level 2 Column Base Flare Collision %02d", bandIndex),
			CFrame.new(position + Vector3.new(0, collisionHeight * .5, 0))
				* CFrame.Angles(0, 0, math.pi * .5),
			Vector3.new(collisionHeight, collisionDiameter, collisionDiameter),
			Color3.new(1, 1, 1), Enum.Material.SmoothPlastic, 1)
		collision.Shape = Enum.PartType.Cylinder
		collision.CanCollide = true
		collision.CanTouch = false
		collision.CanQuery = true
		collision.CastShadow = false
		collision:SetAttribute("Level2_ColumnCollision", true)
		-- GROUND, not wall. These five nested cylinders are the column's trumpet
		-- SKIRT, and the outermost of them is 0.076 studs tall -- a lip you would
		-- not notice underfoot. Tagged Level2_NoEntityGround they were absolute
		-- walls at every column base: the Slidemouth's movement-volume test
		-- refuses any collidable hit that is not steppable, so a 16.3-stud body
		-- box could not pass a colonnade whose flares leave a 15.6-stud gap, and
		-- it stopped dead. Measured on a real generated world: 353 of 400 steps
		-- BLOCKED, "movement volume blocked", zero traversals ever reaching their
		-- goal on any of four seeds.
		--
		-- The navigator ALREADY knows which of these is a step and which is a
		-- wall -- `_isSteppable` is `isEntityGround(part) and top <= footY +
		-- MaxStepHeight`. Tagging them as ground hands that decision to the one
		-- place that owns it, instead of duplicating MaxStepHeight over here: the
		-- short outer bands become steps, and the tall inner bands (and the shaft
		-- behind them) stay the walls they should always have been.
		collision:SetAttribute("Level2_EntityGround", true)
		table.insert(entry.Parts, collision)
	end
end

local function makeColumn(parent, position, height, radius, essential, seamYaw)
	radius = radius or 6
	local placed = columnRegistryFor(parent)
	for entryIndex = #placed, 1, -1 do
		local entry = placed[entryIndex]
		if math.abs(entry.Position.X - position.X) < 9
			and math.abs(entry.Position.Z - position.Z) < 9
			and math.abs(entry.Position.Y - position.Y) < 30 then
			if essential and not entry.Essential then
				for _, piece in ipairs(entry.Parts) do
					piece:Destroy()
				end
				table.remove(placed, entryIndex)
			elseif not essential then
				return nil
			end
		end
	end
	local entry = {Position = position, Essential = essential or false, Parts = {}}
	table.insert(placed, entry)
	-- Stay inside the actual room volume. The trumpet itself begins exactly at
	-- the floor, so burying the shaft below it is unnecessary and made the
	-- pillar visible from beneath procedural floors.
	local ceilingInset = .08
	local shaftBottom = 0
	local shaftTop = height - ceilingInset
	local shaftHeight = shaftTop - shaftBottom
	local column = tiledPart(parent, "Level 2 Tiled Column",
		CFrame.new(position + Vector3.new(0, (shaftBottom + shaftTop) * .5, 0))
			* CFrame.Angles(0, 0, math.pi * .5),
		Vector3.new(shaftHeight, radius, radius), C.TileWarm, nil, 9)
	column.Shape = Enum.PartType.Cylinder
	column.CanCollide = true
	table.insert(entry.Parts, column)
	-- One UV-authored surface-of-revolution per end: genuinely smooth and tiled,
	-- with a concave trumpet profile that is vertical at the shaft and horizontal
	-- where it meets the floor/ceiling.  This replaces both the rejected ball and
	-- the expensive stepped-ring prototype (16 Parts + 64 Textures per column).
	if not essential then
		-- A little more vertical run gives the quarter-cove a graceful trumpet
		-- silhouette instead of compressing the curve into a bulb at the slab.
		local flareLength = math.clamp(radius * 1.35, 7.2, 10.2)
		local template = getColumnFlareTemplate(radius, flareLength)
		for _, endpoint in ipairs({
			{Anchor = 0, ShaftDirection = 1},
			{Anchor = height - ceilingInset, ShaftDirection = -1},
		}) do
			if template then
				local flare = template:Clone()
				flare.Name = "Level 2 Column Flare"
				-- A 0.9% radial overscale hides the true-cylinder shaft behind the
				-- 40-sided mesh neck instead of leaving a sawtooth seam at the join.
				flare.Size = Vector3.new(radius * 2.22, flareLength, radius * 2.22)
				-- This mesh is authored from local Y=0 through Y=1 rather than
				-- around the origin. Place its origin one complete flare length
				-- toward the shaft. Treating it as centred put half of every base
				-- below the floor and half of every capital above the ceiling.
				local originY = endpoint.Anchor
					+ endpoint.ShaftDirection * flareLength
				flare.CFrame = CFrame.new(position + Vector3.new(0, originY, 0))
					* CFrame.Angles(0, seamYaw or 0, 0)
				if endpoint.ShaftDirection > 0 then
					-- The authored mesh widens toward local +Y; invert it for bases.
					flare.CFrame = flare.CFrame * CFrame.Angles(math.pi, 0, 0)
				end
				flare.Color = COLUMN_FLARE_COLOR
				flare.CanCollide = false
				flare.CanTouch = false
				flare.CanQuery = false
				flare.Parent = parent
				table.insert(entry.Parts, flare)
				if endpoint.ShaftDirection > 0 then
					addColumnBaseFlareCollision(parent, position, radius, flareLength, entry)
				end
			else
				-- Asset delivery failure must not abort an otherwise valid layout.
				-- A low-detail concave ceramic fallback preserves the silhouette;
				-- normal builds always use the single smooth mesh above.
				for ringIndex = 1, 5 do
					local u = (ringIndex - 1) / 4
					local ringHeight = flareLength / 5
					local scale = 1 + 1.2 * u ^ 2.35
					local offset = ringHeight * .5 + (1 - u) * (flareLength - ringHeight)
					local centerY = endpoint.Anchor
						+ endpoint.ShaftDirection * (offset + .06)
					local flare = part(parent, "Level 2 Column Flare Fallback",
						CFrame.new(position + Vector3.new(0, centerY, 0))
							* CFrame.Angles(0, 0, math.pi * .5),
						Vector3.new(ringHeight + .12, radius * scale, radius * scale),
						COLUMN_FLARE_COLOR, Enum.Material.CeramicTiles)
					flare.Shape = Enum.PartType.Cylinder
					-- DECORATION ONLY, exactly like the mesh flare it stands in for.
					-- These rings used to carry the collision themselves, which is
					-- what made the collidable world depend on asset delivery.
					flare.CanCollide = false
					flare.CanTouch = false
					flare.CanQuery = false
					table.insert(entry.Parts, flare)
				end
				if endpoint.ShaftDirection > 0 then
					-- The same five bands the mesh path builds, so the physical and
					-- navigable world is a pure function of the seed.
					addColumnBaseFlareCollision(parent, position, radius, flareLength, entry)
				end
			end
		end
	end
	return column
end

-- Move a tall object's complete footprint to the nearest roofed position.
-- Earlier code searched X only and returned the unsafe original point when it
-- failed; that allowed both Z-running strips and circular skylights to be
-- pierced. This bounded radial search handles every authored aperture shape
-- and returns nil rather than ever building through glass/open sky.
local function dodgeSkylight(hall, x, z, width)
	if not overlapsSkylight(hall, x, z, width) then return x, z end
	local edgeClearance = width * .5 + 2
	local minX, maxX = hall.MinX + edgeClearance, hall.MaxX - edgeClearance
	local minZ, maxZ = hall.MinZ + edgeClearance, hall.MaxZ - edgeClearance
	local step = math.max(3, width * .25)
	local maxDistance = math.max(hall.Width, hall.Depth) * .55
	local rings = math.ceil(maxDistance / step)
	for ring = 1, rings do
		local distance = ring * step
		local samples = math.max(12, math.ceil(math.pi * 2 * distance / step))
		for sample = 0, samples - 1 do
			local angle = sample / samples * math.pi * 2
			local candidateX = x + math.cos(angle) * distance
			local candidateZ = z + math.sin(angle) * distance
			if candidateX >= minX and candidateX <= maxX
				and candidateZ >= minZ and candidateZ <= maxZ
				and not overlapsSkylight(hall, candidateX, candidateZ, width) then
				return candidateX, candidateZ
			end
		end
	end
	return nil, nil
end

-- True when (x, z) sits in the walk-in strip in front of any doorway of
-- this hall: nothing bulky may block a door or the level exit.
local function nearDoorApproach(hall, doors, x, z, range)
	if not doors then return false end
	-- Vault-tunnel mouths are wider than doors; the strip must cover the
	-- whole opening plus a flared column's radius.
	range = range or 20
	for _, doorX in ipairs(doors.North or {}) do
		if math.abs(x - doorX) < range and z - hall.MinZ < 36 then return true end
	end
	for _, doorX in ipairs(doors.South or {}) do
		if math.abs(x - doorX) < range and hall.MaxZ - z < 36 then return true end
	end
	for _, doorZ in ipairs(doors.West or {}) do
		if math.abs(z - doorZ) < range and x - hall.MinX < 36 then return true end
	end
	for _, doorZ in ipairs(doors.East or {}) do
		if math.abs(z - doorZ) < range and hall.MaxX - x < 36 then return true end
	end
	return false
end

-- The generated graph fallback uses a hub-and-spoke route inside every hall:
-- the two centre axes form the hub, then an axis-aligned spoke reaches each
-- doorway. Reserve that complete route for the Slidemouth's square body while
-- placing structural decoration. Door-mouth clearance alone protects only the
-- first 36 studs; seed 404 still needed nine expensive A* furniture detours in
-- the room interiors and exceeded the strict eight-second planning contract.
local function nearHallNavigationRoute(hall, doors, x, z, range)
	range = range or 16
	if math.abs(x - hall.Center.X) < range
		or math.abs(z - hall.Center.Z) < range then
		return true
	end
	local function nearSegment(ax, az, bx, bz)
		local dx, dz = bx - ax, bz - az
		local denominator = dx * dx + dz * dz
		local projection = denominator > 0 and math.clamp(
			((x - ax) * dx + (z - az) * dz) / denominator, 0, 1) or 0
		local closestX = ax + dx * projection
		local closestZ = az + dz * projection
		local offsetX, offsetZ = x - closestX, z - closestZ
		return offsetX * offsetX + offsetZ * offsetZ < range * range
	end
	for _, doorX in ipairs((doors and doors.North) or {}) do
		if nearSegment(doorX, hall.MinZ, doorX, hall.Center.Z) then return true end
	end
	for _, doorX in ipairs((doors and doors.South) or {}) do
		if nearSegment(doorX, hall.MaxZ, doorX, hall.Center.Z) then return true end
	end
	for _, doorZ in ipairs((doors and doors.West) or {}) do
		if nearSegment(hall.MinX, doorZ, hall.Center.X, doorZ) then return true end
	end
	for _, doorZ in ipairs((doors and doors.East) or {}) do
		if nearSegment(hall.MaxX, doorZ, hall.Center.X, doorZ) then return true end
	end
	return false
end

-- Rows of columns rising out of the water — the reference-photo colonnades.
local function makeColonnade(parent, hall, depth, rows, doors)
	local alongX = hall.Width >= hall.Depth
	local long = alongX and hall.Width or hall.Depth
	local short = alongX and hall.Depth or hall.Width
	local count = math.clamp(math.floor(long / 38), 2, 8)
	local height = hallHeight(hall)
	local placed = {}
	for _, rowOffset in ipairs(rows) do
		local offset = rowOffset * short * .5
		for column = 1, count do
			local along = (column / (count + 1) - .5) * (long - 40)
			local position = alongX
				and hall.Center + Vector3.new(along, -(depth or 0), offset)
				or hall.Center + Vector3.new(offset, -(depth or 0), along)
			local safeX, safeZ = dodgeSkylight(hall, position.X, position.Z, 13)
			if not safeX then continue end
			position = Vector3.new(safeX, position.Y, safeZ)
			if nearDoorApproach(hall, doors, position.X, position.Z, 20)
				or nearHallNavigationRoute(hall, doors, position.X, position.Z, 17) then
				continue
			end
			-- The dodge can push two columns onto the same spot; skip rather
			-- than build them inside each other.
			local tooClose = false
			for _, existing in ipairs(placed) do
				if math.abs(existing.X - position.X) < 12.5
					and math.abs(existing.Z - position.Z) < 12.5 then
					tooClose = true
					break
				end
			end
			if not tooClose then
				table.insert(placed, position)
				makeColumn(parent, position, height + (depth or 0), 5.5, false,
					hiddenColumnSeamYaw(hall, position.X, position.Z))
			end
		end
	end
end

-- An archway: contiguous tangent segments built with lookAt between successive
-- ring points, so the orientation can never be wrong. Classic half arch whose
-- feet run DOWN past the water surface into the floor slab, so it never
-- floats. `acrossZ` = the ring spans across Z; you walk through along X.
local function makeArchSpan(parent, center, acrossZ, index, radius, floorDepth, styleHall, options)
	options = options or {}
	radius = math.max(6, radius)
	floorDepth = floorDepth or 0
	local dip = math.asin(math.clamp((floorDepth + 2.2) / radius, 0, .55))
	local angleFrom, angleTo = -dip, math.pi + dip
	local steps = math.max(options.MinimumSteps or 14,
		math.ceil(radius * (options.Density or 1.9)))
	local axialDepth = options.AxialDepth or 3.2
	local radialDepth = options.RadialDepth or 2.2
	local segmentOverlap = options.SegmentOverlap or .9
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
		local rib
		if styleHall then
			rib = part(parent, "Level 2 Arch Rib " .. index,
				CFrame.lookAt(mid, to, up),
				Vector3.new(axialDepth, radialDepth, (to - from).Magnitude + segmentOverlap),
				kidsPalette(styleHall).Color, Enum.Material.SmoothPlastic)
			addKidsTileTexture(rib, styleHall, options.Faces, options.Studs)
		else
			rib = part(parent, "Level 2 Arch Rib " .. index,
				CFrame.lookAt(mid, to, up),
				Vector3.new(axialDepth, radialDepth, (to - from).Magnitude + segmentOverlap), C.TileWarm)
			addTexture(rib, options.Faces or Enum.NormalId:GetEnumItems(), options.Studs or 7)
		end
		if options.CanCollide == false then
			rib.CanCollide = false
			rib.CanTouch = false
			rib.CanQuery = false
		end
	end
end

-- The continuous shell that CONNECTS the arch ribs: long tiled strips running
-- the passage's whole length, one per angular step, sitting just behind the
-- ribs — together they form the half cylinder you walk through, its feet
-- submerged like the ribs'.
local function makeBarrelVault(parent, center, acrossZ, index, radius, length, floorDepth, styleHall)
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
		local strip
		if styleHall then
			strip = part(parent, "Level 2 Vault Strip " .. index,
				CFrame.lookAt(mid, mid + axis, up),
				Vector3.new(chord, 1.6, length),
				kidsPalette(styleHall).Color, Enum.Material.SmoothPlastic)
			addKidsTileTexture(strip, styleHall)
		else
			strip = part(parent, "Level 2 Vault Strip " .. index,
				CFrame.lookAt(mid, mid + axis, up),
				Vector3.new(chord, 1.6, length), C.TileCool)
			-- Only the local Bottom face is visible from inside the tunnel. The
			-- opposite face is buried outside the continuous vault shell.
			addTexture(strip, {Enum.NormalId.Bottom}, 8)
		end
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

local function makeStairFlight(parent, base, direction, width, steps, name, run, rise, surfaceHall)
	direction = direction.Unit
	run = run or 2.3
	rise = rise or .78
	for index = 1, steps do
		local height = index * rise
		local center = base + direction * ((index - .5) * run) + Vector3.new(0, height * .5, 0)
		local stair
		if isKids(surfaceHall) then
			stair = part(parent, name .. " Step " .. index,
				CFrame.lookAt(center, center + direction), Vector3.new(width, height, run + .12),
				mutedKidsColor(kidsPalette(surfaceHall).Accent, .24), Enum.Material.SmoothPlastic)
			useKidsMaterial(stair, Enum.Material.SmoothPlastic, LEVEL2_KIDS_FOAM_VARIANT)
			stair:SetAttribute("Level2_KidsPaddedStair", true)
		else
			stair = tiledPart(parent, name .. " Step " .. index,
				CFrame.lookAt(center, center + direction), Vector3.new(width, height, run + .12), C.TileWarm,
				{Enum.NormalId.Top, Enum.NormalId.Front, Enum.NormalId.Back}, 7)
		end
		stair.CanCollide = true
		stair:SetAttribute("Level2_EntityGround", true)
	end
	return steps * run, steps * rise
end

-- Sloped handrails flanking a straight stair flight — the railed straight
-- stairs the playtests keep praising.
local function makeStairSideRails(parent, base, direction, width, steps, run, rise, name)
	direction = direction.Unit
	local sideDir = Vector3.new(-direction.Z, 0, direction.X)
	for _, railSide in ipairs({-1, 1}) do
		local offset = sideDir * railSide * (width * .5 + .35)
		makeRail(parent,
			base + direction * (run * .4) + offset + Vector3.new(0, rise, 0),
			base + direction * ((steps - .4) * run) + offset + Vector3.new(0, steps * rise, 0),
			name .. " Stair " .. (railSide < 0 and "L" or "R"))
	end
end

local function makeSpiralStair(parent, center, baseY, topY, radius, name)
	-- Whole turns only: the top tread always points the same way as the
	-- bottom one (+X), so callers can dock a walkway against it. Step count
	-- also follows ARC length, so wide spirals read as a dense overlapping
	-- helix instead of gapped petals.
	local turns = math.max(2, math.floor((topY - baseY) / 34 + .5))
	local steps = math.max(
		math.max(10, math.floor((topY - baseY) / 1.05)),
		math.ceil(turns * math.pi * 2 * radius / 3.2))
	local guardEvery = math.max(2,
		math.floor(steps * 5.5 / (turns * math.pi * 2 * radius) + .5))
	makeColumn(parent, center + Vector3.new(0, baseY, 0), topY - baseY + 5, 8, true)
	local previousGuardTop
	for index = 0, steps do
		local t = index / steps
		-- Negative sweep: ascending, you arrive at the top tread facing
		-- NORTH along the catwalk (toward the deck) instead of off its end.
		local angle = -t * math.pi * 2 * turns
		local y = baseY + t * (topY - baseY)
		local position = center + Vector3.new(math.cos(angle) * radius, y, math.sin(angle) * radius)
		local tread = tiledPart(parent, name .. " Tread " .. index,
			CFrame.new(position) * CFrame.Angles(0, -angle, 0),
			Vector3.new(radius * 1.45, .7, 6.4), C.TileWarm,
			{Enum.NormalId.Top, Enum.NormalId.Front, Enum.NormalId.Back}, 7)
		tread.CanCollide = true
		tread:SetAttribute("Level2_EntityGround", true)
		-- Outer guard rail so nobody walks off the far edge of the stair.
		-- The last stretch stays open so decks stay reachable.
		if index % guardEvery == 0 and t < .86 then
			local outer = radius * 1.62
			local postPos = center + Vector3.new(
				math.cos(angle) * outer, y + 1.6, math.sin(angle) * outer)
			local post = part(parent, name .. " Guard Post " .. index,
				CFrame.new(postPos), Vector3.new(.35, 3.2, .35), C.Rail, Enum.Material.Metal)
			post.CanCollide = true
			local guardTop = postPos + Vector3.new(0, 1.6, 0)
			if previousGuardTop then
				local guardMid = (guardTop + previousGuardTop) * .5
				local guardBar = part(parent, name .. " Guard Rail " .. index,
					CFrame.lookAt(guardMid, guardTop),
					Vector3.new(.3, .3, (guardTop - previousGuardTop).Magnitude + .25),
					C.Rail, Enum.Material.Metal)
				guardBar.CanCollide = true
			end
			previousGuardTop = guardTop
		end
	end
end

-- A spiral built on the room centre makes that centre an attractive but
-- impossible graph waypoint: its column, stacked treads and outer guard rail
-- occupy the exact point every generated-hall fallback route crosses. Keep
-- the FULL 13-stud set piece, but dock it in a proven door-safe quadrant and
-- leave a measured square-body channel through the middle of the hall. Halls
-- that cannot prove that contract are deterministically re-dressed as a
-- Porthole Hall before anything is built; the stair is never silently shrunk,
-- clipped through a wall, or allowed to poison generation.
local function spiralStairPlacement(hall, doors)
	local radius = 13
	local structureRadius = radius * 1.75
	local bodyRouteClearance = 11
	local inflatedRadius = structureRadius + bodyRouteClearance
	local wallMargin = 3
	-- Each axis needs room for the structure at the wall AND its body-inflated
	-- envelope on the two centre lines used by generated graph routes.
	if hall.Width < 2 * (structureRadius + wallMargin + inflatedRadius)
		or hall.Depth < 2 * (structureRadius + wallMargin + inflatedRadius) then
		return nil
	end
	local maximumOffsetX = hall.Width * .5 - structureRadius - wallMargin
	local maximumOffsetZ = hall.Depth * .5 - structureRadius - wallMargin
	local signs = {
		Vector3.new(1, 0, -1), Vector3.new(-1, 0, 1),
		Vector3.new(1, 0, 1), Vector3.new(-1, 0, -1),
	}
	local first = math.floor(tonumber(hall.LocalSeed) or tonumber(hall.Index) or 1)
	first = first % #signs + 1

	local function distanceToSegment(point, a, b)
		local span = b - a
		local denominator = span.X * span.X + span.Z * span.Z
		local projection = denominator > 0 and math.clamp(
			((point.X - a.X) * span.X + (point.Z - a.Z) * span.Z) / denominator,
			0, 1) or 0
		local closest = a + span * projection
		return Vector2.new(point.X - closest.X, point.Z - closest.Z).Magnitude
	end

	local function candidateSafe(candidate)
		if candidate.X - structureRadius < hall.MinX + wallMargin
			or candidate.X + structureRadius > hall.MaxX - wallMargin
			or candidate.Z - structureRadius < hall.MinZ + wallMargin
			or candidate.Z + structureRadius > hall.MaxZ - wallMargin then
			return false
		end
		-- Preserve both centre lines, not merely the centre point. Graph fallback
		-- routes travel from every door to one of these two orthogonal lanes.
		if math.abs(candidate.X - hall.Center.X) < inflatedRadius
			or math.abs(candidate.Z - hall.Center.Z) < inflatedRadius then
			return false
		end
		local function clearDoorRoutes(values, aFor, bFor)
			for _, cross in ipairs(values or {}) do
				if distanceToSegment(candidate, aFor(cross), bFor(cross)) < inflatedRadius then
					return false
				end
			end
			return true
		end
		return clearDoorRoutes(doors and doors.North,
			function(cross) return Vector3.new(cross, 0, hall.MinZ) end,
			function(cross) return Vector3.new(cross, 0, hall.Center.Z) end)
			and clearDoorRoutes(doors and doors.South,
				function(cross) return Vector3.new(cross, 0, hall.MaxZ) end,
				function(cross) return Vector3.new(cross, 0, hall.Center.Z) end)
			and clearDoorRoutes(doors and doors.West,
				function(cross) return Vector3.new(hall.MinX, 0, cross) end,
				function(cross) return Vector3.new(hall.Center.X, 0, cross) end)
			and clearDoorRoutes(doors and doors.East,
				function(cross) return Vector3.new(hall.MaxX, 0, cross) end,
				function(cross) return Vector3.new(hall.Center.X, 0, cross) end)
	end

	local xOffsets = {
		maximumOffsetX,
		(maximumOffsetX + inflatedRadius) * .5,
		inflatedRadius,
	}
	local zOffsets = {
		maximumOffsetZ,
		(maximumOffsetZ + inflatedRadius) * .5,
		inflatedRadius,
	}
	for offset = 0, #signs - 1 do
		local sign = signs[(first + offset - 1) % #signs + 1]
		for _, offsetX in ipairs(xOffsets) do
			for _, offsetZ in ipairs(zOffsets) do
				local candidate = hall.Center
					+ Vector3.new(sign.X * offsetX, 0, sign.Z * offsetZ)
				if candidateSafe(candidate) then
					return candidate, radius, structureRadius
				end
			end
		end
	end
	return nil
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
	-- These panels light sealed rooms, so their contribution must respect the
	-- walls. With Shadows off, light visibly washed through every corner no
	-- matter how much solid geometry overlapped there.
	light.Shadows = true
	light.Parent = diffuser
	return diffuser
end

local function lightHall(parent, hall, index)
	-- Halls with skylights are lit by the SUN alone — no artificial fixtures.
	-- Kids rooms have their own varied round skylights; the rectangular panels
	-- remain only in enclosed corridors and gateway spaces.
	if isKids(hall) or #skylightSlotsFor(hall) > 0 then return end
	local height = hallHeight(hall)
	local columns = math.clamp(math.floor(hall.Width / 130), 1, 2)
	local rows = math.clamp(math.floor(hall.Depth / 130), 1, 2)
	local panelWidth = math.min(46, hall.Width * .42)
	for cx = 1, columns do
		for cz = 1, rows do
			local x = hall.Center.X - hall.Width * .5 + (cx / (columns + 1)) * hall.Width
			local z = hall.Center.Z - hall.Depth * .5 + (cz / (rows + 1)) * hall.Depth
			-- Never run a light panel through a column's capital.
			local blocked = false
			for _, sampleOffset in ipairs({-panelWidth * .35, 0, panelWidth * .35}) do
				if columnNear(parent, x + sampleOffset, z, 12) then
					blocked = true
					break
				end
			end
			if not blocked then
				makeCeilingPanel(parent, Vector3.new(x, 0, z),
					index .. "." .. cx .. "." .. cz,
					Vector3.new(panelWidth, .55, 9), 0, height)
			end
		end
	end
end

-- ── tubes and slides ────────────────────────────────────────────────────────

-- The old panel tube remains as a no-asset fallback. Normal Level 2
-- generation uses the authored 24-sided open shell and 32-sided closed shell below.
local ONE_WAY_DESCENT_EPSILON = .01
local function slideCollisionPhysicalProperties()
	return PhysicalProperties.new(
		.7, Configuration.SlideCollisionFriction or .05, .05,
		Configuration.SlideCollisionFrictionWeight or 1, 1)
end

local function makeLegacyTubeFromPoints(parent, points, radius, color, name, openTop,
	forceOneWay)
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
					local panel = part(parent, name .. " Legacy Panel",
						base * CFrame.new(offset) * CFrame.Angles(0, 0, angle - math.pi * .5),
						Vector3.new(arcWidth, .72, length + 2), color, Enum.Material.SmoothPlastic)
					panel.CustomPhysicalProperties = slideCollisionPhysicalProperties()
					panel.CanCollide = true
					if math.sin(angle) < -.70 then
						panel:SetAttribute("Level2_SlideCollision", true)
						panel:SetAttribute("Level2_SlideFloor", true)
						panel:SetAttribute("Level2_SlideDirection", (b - a).Unit)
						panel:SetAttribute("Level2_NoEntityGround", true)
						if forceOneWay and (b - a).Unit.Y < -ONE_WAY_DESCENT_EPSILON then
							panel:SetAttribute("Level2_OneWayExit", true)
						end
					end
				end
			end
		end
	end
end

local loadedSlideMeshTemplates = {}
local unavailableSlideMeshTemplates = {}
local function loadSlideMeshTemplate(key, meshId, displayName, attributes)
	local cached = loadedSlideMeshTemplates[key]
	if cached and cached.Parent then return cached end
	if unavailableSlideMeshTemplates[key] then return nil end
	-- Same adoption as getColumnFlareTemplate, and for the same reason: the Lua
	-- cache does not survive a module reload, but the MeshPart in ServerStorage
	-- does, so building unconditionally leaked one copy per Studio session.
	local existing = ServerStorage:FindFirstChild(displayName)
	if existing and existing:IsA("MeshPart") and existing.MeshId == meshId then
		for attribute, value in pairs(attributes or {}) do
			existing:SetAttribute(attribute, value)
		end
		loadedSlideMeshTemplates[key] = existing
		return existing
	end
	local ok, result = pcall(function()
		return AssetService:CreateMeshPartAsync(Content.fromUri(meshId), {
			CollisionFidelity = Enum.CollisionFidelity.Box,
			RenderFidelity = Enum.RenderFidelity.Precise,
		})
	end)
	if not ok or not result then
		unavailableSlideMeshTemplates[key] = true
		warn("[Level 2] unable to load " .. displayName .. ": " .. tostring(result))
		return nil
	end
	result.Name = displayName
	result.Anchored = true
	result.CanCollide = false
	result.CanTouch = false
	result.CanQuery = false
	for attribute, value in pairs(attributes or {}) do
		result:SetAttribute(attribute, value)
	end
	result.Parent = ServerStorage
	loadedSlideMeshTemplates[key] = result
	return result
end

-- The supplied closed tube segment has correctly wound inner and outer walls,
-- but its axial ends are intentionally open. Its former "rims" were only
-- enlarged clones of that same open sleeve, so a long view down the flume could
-- still see through the exposed wall thickness. This dedicated hollow annulus
-- closes the fiberglass edge while leaving the rider bore completely open.
local function closedSlideEndCapTemplate()
	return loadSlideMeshTemplate("closedEndCap", SLIDE_CLOSED_END_CAP_MESH,
		"Level 2 Closed Slide End Cap Template", {
			Level2_BaseRadius = 1,
			Level2_InnerRadius = .885,
			Level2_OuterRadius = 1.015,
			Level2_TemplateKind = "ClosedEndCap",
		})
end

local function slideTemplate(openTop)
	if Configuration.SlideUseMeshTemplates == false then return nil end
	if openTop ~= false then
		-- This source-controlled asset closes the four longitudinal shell edges
		-- that remained open in the original template. Axial ends intentionally
		-- stay open so adjacent visual chords can overlap without transverse ribs.
		local sealed = loadSlideMeshTemplate("open", SLIDE_OPEN_SEGMENT_MESH,
			"Level 2 Sealed Open Slide Segment Template", {
				Level2_BaseRadius = 1,
				Level2_BaseLength = 1,
				Level2_CenterYOffset = .28869075,
				Level2_TemplateKind = "Open",
			})
		if sealed then return sealed end
	end
	local assets = ServerStorage:FindFirstChild("Level 2 Slide Assets")
	local templates = assets and assets:FindFirstChild("Level 2 Slide Templates")
	local templateName = openTop == false
		and "Level 2 Slide Closed Segment"
		or "Level 2 Slide Open Segment"
	local template = templates and templates:FindFirstChild(templateName)
	if template and template:IsA("MeshPart") then
		return template
	end
	return nil
end

local function slideOpenEndCapTemplate()
	return loadSlideMeshTemplate("openEndCap", SLIDE_OPEN_END_CAP_MESH,
		"Level 2 Open Slide End Cap Template", {
			Level2_BaseRadius = 1,
			Level2_CenterYOffset = .28869075,
			Level2_TemplateKind = "OpenEndCap",
		})
end

local function slideCradleTemplate()
	return loadSlideMeshTemplate("cradle", SLIDE_CRADLE_MESH,
		"Level 2 Fitted Slide Cradle Template", {
			Level2_BaseRadius = 1,
			Level2_BaseLength = 1,
			-- The continuous U is centred around a circle .31756 studs above the
			-- mesh pivot. Runtime placement removes this offset so its inner curve
			-- fits the slide exactly and its bottom remains buried in the deck.
			Level2_CenterYOffset = .317559956,
			Level2_TemplateKind = "ContinuousGroundedU",
			Level2_InnerRadius = .985,
			Level2_OuterRadius = 1.10,
		})
end

local function smoothedSlideSegmentCount(segments)
	if not slideTemplate() then return segments end
	local multiplier = Configuration.SlideVisualSegmentMultiplier or 1.6
	return math.max(segments, math.floor(segments * multiplier + .5))
end

local function configureSlideVisual(mesh, template, name, base, radius, length, color, overlapOverride)
	local baseRadius = template:GetAttribute("Level2_BaseRadius") or 1
	local centerYOffset = template:GetAttribute("Level2_CenterYOffset") or 0
	local scale = radius / baseRadius
	local overlap = overlapOverride or Configuration.SlideMeshOverlap or .65

	mesh.Name = name
	mesh.Size = Vector3.new(
		template.Size.X * scale,
		template.Size.Y * scale,
		length + overlap)
	mesh.CFrame = base * CFrame.new(0, -centerYOffset * scale, 0)
	mesh.Color = color
	mesh.Material = Enum.Material.SmoothPlastic
	mesh.Reflectance = Configuration.SlideGlossReflectance or .06
	mesh.Transparency = 0
	mesh.Anchored = true
	mesh.CanCollide = false
	mesh.CanTouch = false
	mesh.CanQuery = false
	mesh.CastShadow = true
	mesh:SetAttribute("Level2_SlideVisual", true)
	mesh:SetAttribute("Level2_ClosedTube", template:GetAttribute("Level2_TemplateKind") == "Closed")
end

local function makeSlideOpenEndCap(parent, name, point, towardPoint, radius, color)
	local template = slideOpenEndCapTemplate()
	if not template then return nil end
	local baseRadius = template:GetAttribute("Level2_BaseRadius") or 1
	local centerYOffset = template:GetAttribute("Level2_CenterYOffset") or .28869075
	local scale = radius / baseRadius
	local cap = template:Clone()
	cap.Name = name
	cap.Size = Vector3.new(
		template.Size.X * scale,
		template.Size.Y * scale,
		math.clamp(template.Size.Z * scale, .16, .42))
	cap.CFrame = CFrame.lookAt(point, towardPoint, Vector3.yAxis)
		* CFrame.new(0, -centerYOffset * scale, 0)
	cap.Color = color
	cap.Material = Enum.Material.SmoothPlastic
	cap.Reflectance = Configuration.SlideGlossReflectance or .06
	cap.Transparency = 0
	cap.Anchored = true
	cap.CanCollide = false
	cap.CanTouch = false
	cap.CanQuery = false
	cap.CastShadow = true
	cap.DoubleSided = true
	cap:SetAttribute("Level2_SlideEndCap", true)
	cap.Parent = parent
	return cap
end

local function visualOverlapFor(points, index, radius, minimum, bendPadding)
	local direction = (points[index + 1] - points[index]).Unit
	local turnAngle = 0
	if index > 1 then
		local previousDirection = (points[index] - points[index - 1]).Unit
		turnAngle = math.max(turnAngle,
			math.acos(math.clamp(previousDirection:Dot(direction), -1, 1)))
	end
	if index < #points - 1 then
		local nextDirection = (points[index + 2] - points[index + 1]).Unit
		turnAngle = math.max(turnAngle,
			math.acos(math.clamp(direction:Dot(nextDirection), -1, 1)))
	end
	-- Straight mesh chords need to reach past their shared tangent plane on a
	-- bend. This closes the wedge without stacking a fixed oversized overlap on
	-- already-straight portions of the slide.
	local bendOverlap = 2 * radius * math.tan(math.min(turnAngle, math.rad(60)) * .5)
		+ (bendPadding or .04)
	return math.max(minimum or Configuration.SlideMeshOverlap or .12, bendOverlap)
end

local function makeClosedSlideEndCap(parent, name, point, towardPoint, radius, color)
	local template = closedSlideEndCapTemplate()
	local depth = .28
	if template then
		local cap = template:Clone()
		cap.Name = name
		cap.Size = Vector3.new(
			template.Size.X * radius,
			template.Size.Y * radius,
			depth)
		cap.CFrame = CFrame.lookAt(point, towardPoint, Vector3.yAxis)
		cap.Color = color
		cap.Material = Enum.Material.SmoothPlastic
		cap.Reflectance = Configuration.SlideGlossReflectance or .06
		cap.Transparency = 0
		cap.Anchored = true
		cap.CanCollide = false
		cap.CanTouch = false
		cap.CanQuery = false
		cap.CastShadow = true
		cap.DoubleSided = true
		cap:SetAttribute("Level2_SlideEndCap", true)
		cap.Parent = parent
		return cap
	end

	-- Primitive fallback for experiences where the EditableMesh budget is not
	-- available. These 24 overlapping blocks occupy only the fiberglass annulus;
	-- their inner edge never closes the rider bore.
	local fallback = Instance.new("Model")
	fallback.Name = name
	fallback:SetAttribute("Level2_SlideEndCap", true)
	fallback.Parent = parent
	local axis = towardPoint - point
	if axis.Magnitude < .05 then axis = Vector3.zAxis end
	axis = axis.Unit
	local referenceUp = math.abs(axis:Dot(Vector3.yAxis)) > .98
		and Vector3.zAxis or Vector3.yAxis
	local sideDirection = referenceUp:Cross(axis).Unit
	local upDirection = axis:Cross(sideDirection).Unit
	local sides = 24
	local innerRadius = radius * .885
	local outerRadius = radius * 1.015
	local midRadius = (innerRadius + outerRadius) * .5
	local radialThickness = outerRadius - innerRadius
	local tangentLength = 2 * outerRadius * math.tan(math.pi / sides) + .04
	for segment = 0, sides - 1 do
		local angle = segment * math.pi * 2 / sides
		local radial = sideDirection * math.cos(angle)
			+ upDirection * math.sin(angle)
		local tangent = axis:Cross(radial)
		local band = part(fallback, name .. " Band " .. (segment + 1),
			CFrame.fromMatrix(point + radial * midRadius, axis, radial, tangent),
			Vector3.new(depth, radialThickness, tangentLength),
			color, Enum.Material.SmoothPlastic)
		band.Reflectance = Configuration.SlideGlossReflectance or .06
		band.CanCollide = false
		band.CanTouch = false
		band.CanQuery = false
		band:SetAttribute("Level2_SlideEndCap", true)
	end
	return fallback
end

local function makeSlideCollisionPart(parent, name, base, offset, size)
	local collision = part(parent, name, base * CFrame.new(offset), size,
		Color3.fromRGB(255, 255, 255), Enum.Material.SmoothPlastic, 1)
	collision.CanCollide = true
	collision.CanTouch = false
	collision.CanQuery = true
	collision.CastShadow = false
	collision.CustomPhysicalProperties = slideCollisionPhysicalProperties()
	collision:SetAttribute("Level2_SlideCollision", true)
	return collision
end

-- Tube from an ordered point list — shared by flumes, the exit slide and the
-- helix slides. The visible shell is smooth and lightly glossy; simple hidden
-- collision strips preserve the old slide physics without making the player
-- bump over the visible segment seams.
local function makeTubeFromPoints(parent, points, radius, color, name, openTop,
	visualOverlap, collisionPoints, safetyWallHeight, forceOneWay)
	local tubeModel = Instance.new("Model")
	tubeModel.Name = name
	tubeModel:SetAttribute("Level2_SmoothSlide", true)
	tubeModel:SetAttribute("Level2_OpenTop", openTop == true)
	tubeModel:SetAttribute("Level2_OneWayExit", forceOneWay == true)
	tubeModel.Parent = parent

	local template = slideTemplate(openTop)
	if not template then
		tubeModel:SetAttribute("Level2_UsingLegacyPanels", true)
		makeLegacyTubeFromPoints(tubeModel, points, radius, color, name, openTop,
			forceOneWay)
		return tubeModel
	end

	local visuals = folder(tubeModel, name .. " Visuals")
	local collisions = folder(tubeModel, name .. " Collision")
	local thickness = Configuration.SlideCollisionThickness or .6
	local collisionOverlap = Configuration.SlideCollisionOverlap or 1.5
	local visualStarts, visualEnds = {}, {}

	local function addCollisionSegment(a, b, index, totalSegments)
		local length = (b - a).Magnitude
		if length <= .05 then return end

		local suffix = string.format("%03d", index)
		local base = CFrame.lookAt((a + b) * .5, b, Vector3.yAxis)
		local collisionLength = length + collisionOverlap
		local floorCollision = makeSlideCollisionPart(collisions,
			name .. " Collision Floor " .. suffix, base,
			Vector3.new(0, -radius * .9 - thickness * .5, 0),
			Vector3.new(radius * 1.55, thickness, collisionLength))
		local slideDirection = (b - a).Unit
		floorCollision:SetAttribute("Level2_SlideFloor", true)
		floorCollision:SetAttribute("Level2_SlideDirection", slideDirection)
		floorCollision:SetAttribute("Level2_NoEntityGround", true)
		if forceOneWay and slideDirection.Y < -ONE_WAY_DESCENT_EPSILON then
			floorCollision:SetAttribute("Level2_OneWayExit", true)
		end

		-- Two 45-degree chamfer strips complete the lower quarter of the bore
		-- on both sides, like the legacy octagonal tubes had. The flat floor
		-- plus vertical sides alone left open corner slots (about a stud wide
		-- at flume radius) between the floor edge and each side wall — a
		-- tumbling ragdoll drifts off-centre on any bend, sinks into the
		-- visual shell there, and wedges a limb in the slot.
		for _, chamferSide in ipairs({-1, 1}) do
			local chamferBase = base * CFrame.Angles(0, 0, chamferSide * math.pi * .25)
			local chamfer = makeSlideCollisionPart(collisions,
				name .. " Collision Chamfer " .. (chamferSide < 0 and "L" or "R") .. suffix,
				chamferBase, Vector3.new(0, -radius * .9 - thickness * .5, 0),
				Vector3.new(radius * .8, thickness, collisionLength))
			chamfer:SetAttribute("Level2_SlideFloor", true)
			chamfer:SetAttribute("Level2_SlideDirection", slideDirection)
			chamfer:SetAttribute("Level2_NoEntityGround", true)
			if forceOneWay and slideDirection.Y < -ONE_WAY_DESCENT_EPSILON then
				chamfer:SetAttribute("Level2_OneWayExit", true)
			end
		end

		local sideHeight, sideY
		if openTop then
			-- Keep the authored open fiberglass shell, but extend its hidden side
			-- collision well above jump height so players cannot climb onto the
			-- exterior of elevated flumes or leave the intended route.
			local sideBottom = -radius * .9
			local fullGuard = math.max(safetyWallHeight
				or Configuration.SlideOpenSafetyWallHeight or 14, radius * 1.15)
			local outletGuard = radius * 1.15
			local segmentsFromEnd = math.max(0, totalSegments - index)
			local taper = math.clamp(segmentsFromEnd / 2, 0, 1)
			sideHeight = outletGuard + (fullGuard - outletGuard) * taper
			sideY = sideBottom + sideHeight * .5
		else
			sideHeight = radius * 1.8
			sideY = 0
		end
		local sideX = radius * .9 + thickness * .5
		makeSlideCollisionPart(collisions, name .. " Collision Left " .. suffix, base,
			Vector3.new(-sideX, sideY, 0),
			Vector3.new(thickness, sideHeight, collisionLength))
		makeSlideCollisionPart(collisions, name .. " Collision Right " .. suffix, base,
			Vector3.new(sideX, sideY, 0),
			Vector3.new(thickness, sideHeight, collisionLength))

		if not openTop then
			makeSlideCollisionPart(collisions, name .. " Collision Ceiling " .. suffix, base,
				Vector3.new(0, radius * .9 + thickness * .5, 0),
				Vector3.new(radius * 1.55, thickness, collisionLength))
		end
	end

	for index = 1, #points - 1 do
		local a, b = points[index], points[index + 1]
		local length = (b - a).Magnitude
		if length > .05 then
			local suffix = string.format("%03d", index)
			local direction = (b - a).Unit
			local segmentOverlap = visualOverlapFor(points, index, radius, visualOverlap,
				openTop and .04 or .18)
			local backwardExtension = segmentOverlap * .5
			local forwardExtension = segmentOverlap * .5
			if not openTop and index == 1 then
				backwardExtension = 0
			end
			if not openTop and index == #points - 1 then
				forwardExtension = 0
			end
			local visualCenter = (a + b) * .5
				+ direction * ((forwardExtension - backwardExtension) * .5)
			local base = CFrame.lookAt(
				visualCenter, visualCenter + direction, Vector3.yAxis)
			visualStarts[index] = a - direction * backwardExtension
			visualEnds[index] = b + direction * forwardExtension

			local visual = template:Clone()
			configureSlideVisual(visual, template, name .. " Visual " .. suffix,
				base, radius, length, color, backwardExtension + forwardExtension)
			-- Every shell renders both faces: the playtests kept finding new
			-- see-through angles (mid-tube, underside), so partial coverage
			-- is not worth the saved triangles.
			if visual:IsA("MeshPart") then
				visual.DoubleSided = true
			end
			visual.Parent = visuals

			if not collisionPoints then
				addCollisionSegment(a, b, index, #points - 1)
			end
		end
	end

	if collisionPoints then
		for index = 1, #collisionPoints - 1 do
			addCollisionSegment(collisionPoints[index], collisionPoints[index + 1],
				index, #collisionPoints - 1)
		end
	end

	-- Open slides use their dedicated U-shaped outlet edge. Closed tubes instead
	-- receive hollow annular caps at the actual overlap-extended visual bounds;
	-- those seal the fiberglass wall thickness without covering the rider bore.
	if openTop and #points >= 2 then
		makeSlideOpenEndCap(visuals, name .. " Outlet Edge Cap",
			points[#points], points[#points - 1], radius, color)
	elseif #points >= 2 then
		local firstDirection = (points[2] - points[1]).Unit
		local lastDirection = (points[#points] - points[#points - 1]).Unit
		local firstBoundary = visualStarts[1] or points[1]
		local lastBoundary = visualEnds[#points - 1] or points[#points]
		makeClosedSlideEndCap(visuals, name .. " Entry Edge Cap",
			firstBoundary, firstBoundary + firstDirection, radius, color)
		makeClosedSlideEndCap(visuals, name .. " Outlet Edge Cap",
			lastBoundary, lastBoundary - lastDirection, radius, color)
	end

	return tubeModel
end

local function makeSlideTube(parent, p0, p1, p2, p3, radius, color, name,
	segments, openTop, overlap, collisionSegments, safetyWallHeight)
	segments = smoothedSlideSegmentCount(segments or Configuration.SlideSegments)
	local points = {}
	for segment = 0, segments do
		table.insert(points, bezier(p0, p1, p2, p3, segment / segments))
	end
	local collisionPoints
	if collisionSegments and collisionSegments >= 2 then
		collisionPoints = {}
		for segment = 0, collisionSegments do
			table.insert(collisionPoints, bezier(p0, p1, p2, p3, segment / collisionSegments))
		end
	end
	return makeTubeFromPoints(parent, points, radius, color, name, openTop,
		overlap, collisionPoints, safetyWallHeight)
end

-- A slide that WINDS AROUND a column: helix from a deck-level catwalk down
-- into the water.
local function makeHelixSlide(parent, columnPosition, helixRadius, topY, color, name)
	local turns = 2.1
	local startAngle = math.pi * .5
	local collisionSegments = smoothedSlideSegmentCount(30)
	local visualSegments = math.max(collisionSegments,
		math.floor((Configuration.SlideHelixVisualSegments or 120) + .5))

	local function pointAt(t)
		local angle = startAngle + t * math.pi * 2 * turns
		local y = topY * (1 - t) + 3.4 * t
		return Vector3.new(
			columnPosition.X + math.cos(angle) * helixRadius,
			y,
			columnPosition.Z + math.sin(angle) * helixRadius)
	end

	local visualPoints = {}
	for segment = 0, visualSegments do
		table.insert(visualPoints, pointAt(segment / visualSegments))
	end

	local collisionPoints = {}
	for segment = 0, collisionSegments do
		table.insert(collisionPoints, pointAt(segment / collisionSegments))
	end

	makeTubeFromPoints(parent, visualPoints, 4.6, color, name, true,
		Configuration.SlideHelixVisualOverlap or .56, collisionPoints)
	return visualPoints[1], visualPoints[2]
end

-- A molded entry tub like a REAL water-park slide start (the reference
-- photos): everything in the SLIDE'S OWN colour and material, hugging the
-- shell — tall cheeks beside the mouth stepping down to hip height around
-- the seat, corner fillers closing the round-shell-to-flat-wall gap, and a
-- low back lip. The tube's first stretch hides inside the deck slab, so no
-- angle can see through it — solid geometry, no extra layers.
local function makeEntryTub(parent, mouthPoint, towardPoint, radius, deckTop, color, name,
	collidableSupport, forceEntryRide)
	local flat = Vector3.new(towardPoint.X - mouthPoint.X, 0, towardPoint.Z - mouthPoint.Z)
	if flat.Magnitude < .05 then flat = Vector3.new(0, 0, 1) end
	local direction = flat.Unit
	local sideDirection = Vector3.new(-direction.Z, 0, direction.X)
	local entryLength = math.clamp(radius * 1.35, 5.5, 10)
	local rearPoint = mouthPoint - direction * entryLength
	local template = slideTemplate(true)
	local apron
	if template then
		apron = template:Clone()
		configureSlideVisual(apron, template, name .. " Entry Apron",
			CFrame.lookAt((rearPoint + mouthPoint) * .5, mouthPoint, Vector3.yAxis),
			radius, entryLength, color, .14)
		apron.DoubleSided = true
		apron:SetAttribute("Level2_SlideEntry", true)
		apron.Parent = parent
	else
		apron = part(parent, name .. " Entry Apron",
			CFrame.lookAt((rearPoint + mouthPoint) * .5, mouthPoint, Vector3.yAxis),
			Vector3.new(radius * 1.55, .28, entryLength), color, Enum.Material.SmoothPlastic)
		apron.CanCollide = false
	end
	makeSlideOpenEndCap(parent, name .. " Entry Edge Cap",
		rearPoint, mouthPoint, radius, color)
	if collidableSupport then
		-- The visible apron is intentionally non-colliding. Continue the exact
		-- low-friction rider floor through every cradle so feet never drop onto the
		-- lower decorative plinth before hitting Collision Floor 001.
		local thickness = Configuration.SlideCollisionThickness or .6
		local forwardOverlap = (Configuration.SlideCollisionOverlap or 1.5) * .5
		local collisionEnd = mouthPoint + direction * forwardOverlap
		local collisionCenter = (rearPoint + collisionEnd) * .5
		local floorTop = mouthPoint.Y - radius * .9
		collisionCenter = Vector3.new(
			collisionCenter.X, floorTop - thickness * .5, collisionCenter.Z)
		local collisionBase = CFrame.lookAt(
			collisionCenter, collisionCenter + direction, Vector3.yAxis)
		local entryFloor = makeSlideCollisionPart(parent,
			name .. " Entry Collision Floor", collisionBase, Vector3.zero,
			Vector3.new(radius * 1.55, thickness, entryLength + forwardOverlap))
		entryFloor:SetAttribute("Level2_NoEntityGround", true)
		entryFloor:SetAttribute("Level2_SlideFloor", true)
		entryFloor:SetAttribute("Level2_SlideDirection", direction)
		if forceEntryRide then
			entryFloor:SetAttribute("Level2_OneWayExit", true)
		end
	end

	-- One continuous molded U supports the entire lower shell, matching the
	-- user's front and side references. It spans the launch apron and keys into
	-- a low plinth which is deliberately sunk into the deck, so the cradle can
	-- never look like it is floating.
	local supportLength = entryLength + .35
	local supportCenter = (rearPoint + mouthPoint) * .5
	local supportFrame = CFrame.lookAt(
		supportCenter, mouthPoint, Vector3.yAxis)
	local madeVisibleFallback = false
	local shellBottom = mouthPoint.Y - radius
	local baseTop = math.max(deckTop + .08, shellBottom + .03)
	local baseThickness = math.clamp(radius * .065, .28, .55)
	local basePosition = Vector3.new(
		supportCenter.X, baseTop - baseThickness * .5, supportCenter.Z)
	local baseFrame = CFrame.lookAt(
		basePosition, basePosition + direction, Vector3.yAxis)
	local groundBase = part(parent, name .. " Entry Cradle Ground Base",
		baseFrame, Vector3.new(radius * 2.15, baseThickness, supportLength),
		color, Enum.Material.SmoothPlastic)
	groundBase.Reflectance = Configuration.SlideGlossReflectance or .06
	groundBase.CanCollide = collidableSupport == true
	groundBase.CanTouch = false
	groundBase.CanQuery = collidableSupport == true
	groundBase:SetAttribute("Level2_SlideEntrySupport", true)
	if collidableSupport then
		groundBase.CustomPhysicalProperties = slideCollisionPhysicalProperties()
		groundBase:SetAttribute("Level2_SlideCollision", true)
		groundBase:SetAttribute("Level2_NoEntityGround", true)
	end

	local saddleTemplate = slideCradleTemplate()
	if saddleTemplate then
		-- The old full U is intentionally restored. Its inner annulus embeds only
		-- into the fiberglass thickness; it never enters the rider bore.
		local baseRadius = saddleTemplate:GetAttribute("Level2_BaseRadius") or 1
		local centerYOffset = saddleTemplate:GetAttribute("Level2_CenterYOffset")
			or .317559956
		local scale = radius / baseRadius
		local saddle = saddleTemplate:Clone()
		saddle.Name = name .. " Entry Molded Grounded Cradle"
		saddle.Size = Vector3.new(
			saddleTemplate.Size.X * scale,
			saddleTemplate.Size.Y * scale,
			supportLength)
		saddle.CFrame = supportFrame
			* CFrame.new(0, -centerYOffset * scale, 0)
		saddle.Color = color
		saddle.Material = Enum.Material.SmoothPlastic
		saddle.Reflectance = Configuration.SlideGlossReflectance or .06
		saddle.Transparency = 0
		saddle.Anchored = true
		saddle.CanCollide = false
		saddle.CanTouch = false
		saddle.CanQuery = false
		saddle.CastShadow = true
		saddle.DoubleSided = true
		saddle:SetAttribute("Level2_SlideEntrySupport", true)
		saddle.Parent = parent
	else
		-- Asset-delivery fallback: approximate the same continuous U with tangent
		-- bands instead of silently reverting to the unrelated two-foot shape.
		madeVisibleFallback = true
		local bands = 20
		local startAngle = math.rad(155)
		local endAngle = math.rad(385)
		local angleStep = (endAngle - startAngle) / bands
		local innerRadius = radius * .985
		local outerRadius = radius * 1.10
		local midRadius = (innerRadius + outerRadius) * .5
		local radialThickness = outerRadius - innerRadius
		local tangentLength = 2 * outerRadius * math.sin(angleStep * .5) + .06
		for segment = 1, bands do
			local angle = startAngle + (segment - .5) * angleStep
			local radial = sideDirection * math.cos(angle)
				+ Vector3.yAxis * math.sin(angle)
			local tangent = direction:Cross(radial)
			local band = part(parent,
				name .. " Entry Cradle Fallback Band " .. segment,
				CFrame.fromMatrix(supportCenter + radial * midRadius,
					direction, radial, tangent),
				Vector3.new(supportLength, radialThickness, tangentLength),
				color, Enum.Material.SmoothPlastic)
			band.Reflectance = Configuration.SlideGlossReflectance or .06
			band.CanCollide = collidableSupport == true
			band.CanTouch = false
			band.CanQuery = collidableSupport == true
			band:SetAttribute("Level2_SlideEntrySupport", true)
			if collidableSupport then
				band.CustomPhysicalProperties = slideCollisionPhysicalProperties()
				band:SetAttribute("Level2_SlideCollision", true)
				band:SetAttribute("Level2_NoEntityGround", true)
			end
		end
	end

	-- The fitted MeshPart deliberately keeps Box collision disabled: its box
	-- would seal the bore. Every cradle instead gets a ring of invisible tangent
	-- boxes fully contained by the visible U. The rider bore remains completely
	-- open while the visible support is physically solid.
	if collidableSupport and not madeVisibleFallback then
		local collisionBands = 16
		local startAngle = math.rad(157)
		local endAngle = math.rad(383)
		local angleStep = (endAngle - startAngle) / collisionBands
		local innerRadius = radius
		local outerRadius = radius * 1.085
		local midRadius = (innerRadius + outerRadius) * .5
		local radialThickness = outerRadius - innerRadius
		local tangentLength = 2 * outerRadius * math.sin(angleStep * .5) + .08
		local collisionLength = supportLength - .16
		for segment = 1, collisionBands do
			local angle = startAngle + (segment - .5) * angleStep
			local radial = sideDirection * math.cos(angle)
				+ Vector3.yAxis * math.sin(angle)
			local tangent = direction:Cross(radial)
			local collision = Instance.new("Part")
			collision.Name = name .. " Entry Cradle Collision " .. segment
			collision.Anchored = true
			collision.CFrame = CFrame.fromMatrix(
				supportCenter + radial * midRadius,
				direction, radial, tangent)
			collision.Size = Vector3.new(
				collisionLength, radialThickness, tangentLength)
			collision.Transparency = 1
			collision.CanCollide = true
			collision.CanTouch = false
			collision.CanQuery = true
			collision.CastShadow = false
			collision.CustomPhysicalProperties = slideCollisionPhysicalProperties()
			collision:SetAttribute("Level2_SlideCollision", true)
			collision:SetAttribute("Level2_SlideEntrySupport", true)
			collision:SetAttribute("Level2_NoEntityGround", true)
			collision.Parent = parent
		end
	end

	-- Polished grab handles give the entrance the same readable water-park
	-- language as the references without putting blocks in the rider's lane.
	local function handleBar(pieceName, a, b)
		local length = (b - a).Magnitude
		if length <= .05 then return end
		local bar = part(parent, name .. " " .. pieceName,
			CFrame.lookAt((a + b) * .5, b, Vector3.yAxis)
				* CFrame.Angles(0, math.pi * .5, 0),
			Vector3.new(length, .34, .34), Color3.fromRGB(202, 208, 210), Enum.Material.Metal)
		bar.Shape = Enum.PartType.Cylinder
		bar.CanCollide = false
		bar.CanTouch = false
		bar.CanQuery = false
	end
	for handleSide = -1, 1, 2 do
		local sideOffset = sideDirection * handleSide * (radius + .72)
		local backBase = rearPoint + sideOffset + Vector3.new(0, deckTop - rearPoint.Y + .35, 0)
		local frontBase = mouthPoint - direction * 1.1 + sideOffset
		frontBase = Vector3.new(frontBase.X, deckTop + .35, frontBase.Z)
		local lift = Vector3.new(0, math.clamp(radius * .38, 1.7, 2.8), 0)
		handleBar("Entry Handle Back " .. handleSide, backBase, backBase + lift)
		handleBar("Entry Handle Front " .. handleSide, frontBase, frontBase + lift)
		handleBar("Entry Handle Top " .. handleSide, backBase + lift, frontBase + lift)
	end
	return apron
end

-- Very large slide halls need architectural rhythm or their authored play
-- equipment reads like a handful of prototypes in an empty box.  These high,
-- wall-hugging frames add scale and shadow without entering navigation space.
local function makeSlideHallScaleFrames(parent, hall, height, poolDepth, hallIndex, doors)
	local alongX = hall.Width >= hall.Depth
	local longLength = alongX and hall.Width or hall.Depth
	local shortLength = alongX and hall.Depth or hall.Width
	local frameCount = math.clamp(math.floor(longLength / 70), 3, 9)
	local pilasterBottom = -poolDepth
	-- Piers stop inside the room like the round columns; no decorative frame
	-- may poke through an aperture or become visible from roof level.
	local pilasterTop = height - .08
	local pilasterHeight = math.max(10, pilasterTop - pilasterBottom)
	local pilasterY = (pilasterTop + pilasterBottom) * .5

	for frameIndex = 1, frameCount do
		local alpha = frameIndex / (frameCount + 1)
		local along = (alongX and hall.MinX or hall.MinZ) + longLength * alpha
		local pierPositions = {}
		local frameBlocked = false
		for _, sideSign in ipairs({-1, 1}) do
			local position = alongX
				and Vector3.new(along, pilasterY,
					hall.Center.Z + sideSign * (shortLength * .5 - 6))
				or Vector3.new(
					hall.Center.X + sideSign * (shortLength * .5 - 6),
					pilasterY, along)
			table.insert(pierPositions, position)
			if overlapsSkylight(hall, position.X, position.Z, 7) then
				frameBlocked = true
			end
		end
		if frameBlocked then continue end
		local frameColor = frameIndex % 3 == 0 and C.TileCool or C.TileWarm
		-- Top face exactly on the ceiling plane (y = height): the bar runs
		-- ALONG the ceiling instead of floating below it.
		local beamPosition = alongX
			and Vector3.new(along, height - 1.5, hall.Center.Z)
			or Vector3.new(hall.Center.X, height - 1.5, along)
		local beamSize = alongX
			and Vector3.new(4, 3, math.max(20, shortLength - 16))
			or Vector3.new(math.max(20, shortLength - 16), 3, 4)
		local beam = part(parent,
			string.format("Level 2 Slide Hall %d Scale Frame %02d Beam", hallIndex, frameIndex),
			CFrame.new(beamPosition), beamSize, frameColor, Enum.Material.CeramicTiles)
		beam.CanCollide = false
		beam.CanTouch = false
		beam.CanQuery = false

		for sideIndex, pilasterPosition in ipairs(pierPositions) do
			-- A wall-hugging pier can still sit directly on a doorway's long
			-- hall-centre spoke. Seed 202 did exactly that in Slide Hall 2: frame
			-- 01's west pier occupied the only body-certified 7 -> 10 route and
			-- made every replan return to the same obstruction. Keep the harmless
			-- ceiling beam and opposite pier, but omit any pier that intersects the
			-- same generated hub-and-spoke lane reserved by the other hall dressers.
			if nearHallNavigationRoute(hall, doors,
				pilasterPosition.X, pilasterPosition.Z, 16) then
				continue
			end
			local pilasterSize = alongX
				and Vector3.new(5, pilasterHeight, 6)
				or Vector3.new(6, pilasterHeight, 5)
			local pilaster = part(parent,
				string.format("Level 2 Slide Hall %d Scale Frame %02d Pier %d",
					hallIndex, frameIndex, sideIndex),
				CFrame.new(pilasterPosition), pilasterSize,
				frameColor:Lerp(Color3.fromRGB(118, 119, 108), .18),
				Enum.Material.CeramicTiles)
			-- These read as load-bearing concrete piers and must be physically
			-- solid; their authored wall-hugging placement preserves the route.
			pilaster.CanCollide = true
			pilaster.CanTouch = false
			pilaster.CanQuery = true
		end
	end
end

-- A slide hall: wall-to-wall deep water, columns to the roof, a top deck on
-- the north edge with straight parallel flume lanes down into the water, a
-- helix slide wrapping the north-east column, spiral stair + catwalk access.
local function makeSlideHall(parent, hall, index, doors)
	local height = hallHeight(hall)
	local center = hall.Center
	local depth = Configuration.SlidePoolDepth
	local hallFolder = folder(parent, "Level 2 Slide Hall " .. index)
	local radius = Configuration.SlideTubeRadius

	local columnOffsetX = math.min(hall.Width * .30, hall.Width * .5 - 16)
	local columnOffsetZ = math.min(hall.Depth * .30, hall.Depth * .5 - 16)
	-- The grand hall's exit flume leaves east along the deck line; no
	-- corner column may crowd that path or its mouth.
	local flumeLineZ = hall.MinZ + Configuration.WallThickness * .5
		+ math.min(46, hall.Depth * .3) * .5
	for _, sx in ipairs({-1, 1}) do
		for _, sz in ipairs({-1, 1}) do
			local columnX, columnZ = dodgeSkylight(hall,
				center.X + sx * columnOffsetX, center.Z + sz * columnOffsetZ, 20)
			local blocksFlume = hall.IsGrand and sx == 1
				and columnZ and math.abs(columnZ - flumeLineZ) < 20
			if columnX and not blocksFlume
				and not nearDoorApproach(hall, doors, columnX, columnZ, 20) then
				makeColumn(hallFolder, Vector3.new(columnX, -depth, columnZ), height + depth,
					9, false, hiddenColumnSeamYaw(hall, columnX, columnZ))
			end
		end
	end
	makeSlideHallScaleFrames(hallFolder, hall, height, depth, index, doors)

	-- Top deck along the north edge.
	local deckY = height - 22
	local deckDepth = math.min(46, hall.Depth * .3)
	local deckBack = hall.MinZ + Configuration.WallThickness * .5
	local deckZ = deckBack + deckDepth * .5
	local deckFront = deckBack + deckDepth
	local deckWestX = hall.MinX + 8
	local deckEastX = hall.MaxX - Configuration.WallThickness * .5
	local deck = tiledPart(hallFolder, "Level 2 Slide Hall Deck",
		CFrame.new(Vector3.new((deckWestX + deckEastX) * .5, deckY, deckZ)),
		Vector3.new(deckEastX - deckWestX, 2, deckDepth), C.TileWarm,
		Enum.NormalId:GetEnumItems(), 8)
	deck.CanCollide = true
	deck:SetAttribute("Level2_EntityGround", true)

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
			-- A long, level launch keeps the fiberglass floor visibly above the
			-- deck and moves the first bend completely past its front edge.
			local startPoint = Vector3.new(laneX, deckY + radius + 1.15, deckFront + 1)
			local p1 = Vector3.new(laneX, startPoint.Y, deckFront + 14)
			local p2 = Vector3.new(laneX, 15, center.Z + hall.Depth * .06)
			local endZ = math.min(center.Z + hall.Depth * .26, hall.MaxZ - radius - 8)
			-- The tube's underside must REST on the shallow floor, not stab
			-- through it: end height = radius above the floor level.
			local p3 = Vector3.new(laneX, radius - depth + .4, endZ)
			-- OPEN half-curve slides. Double-sided shells mean a seam can only
			-- ever show slide colour; minimal overlap keeps segment rims from
			-- stacking into visible feathers.
			makeSlideTube(hallFolder, startPoint, p1, p2, p3, radius, color,
				"Level 2 Slide Hall " .. index .. " Flume " .. slide,
				Configuration.SlideSegments * 3, true, .05, 40)
			makeEntryTub(hallFolder, startPoint, p1, radius, deckY + 1, color,
				"Level 2 Slide Hall " .. index .. " Flume " .. slide, true)
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
	-- Leave the full east-catwalk width open at the corner.  The old rail ended
	-- at MaxX-10, squeezing the turn down to the last two studs of deck.
	local eastTurnRailEnd = hall.MaxX - 16
	if eastTurnRailEnd - cursor > 3 then
		makeRail(hallFolder,
			Vector3.new(cursor, railY, deckFront),
			Vector3.new(eastTurnRailEnd, railY, deckFront),
			"Level 2 Slide Hall " .. index .. " Deck")
	end
	makeRail(hallFolder,
		Vector3.new(hall.MinX + 8, railY, deckBack),
		Vector3.new(hall.MinX + 8, railY, deckFront),
		"Level 2 Slide Hall " .. index .. " West Deck Edge")

	-- Helix slide around its OWN dedicated full-height column in the open
	-- south-east water, fed by a short bridge from the east catwalk. Clear of
	-- the deck, the flume lanes and the spiral stair by construction, so the
	-- tube can never pierce any of them.
	local helixBuilt = false
	local helixDockZ
	local helixAnchorX, helixAnchorZ = dodgeSkylight(hall,
		center.X + columnOffsetX, center.Z, 34)
	local helixRadius = helixAnchorX and math.min(16,
		hall.MaxX - 16 - 6.6 - helixAnchorX,
		helixAnchorX - center.X - laneStep - 13) or 0
	if helixRadius >= 12 then
		local helixColor = Configuration.SlideColors[((index + 2) % #Configuration.SlideColors) + 1]
		local helixColumn = Vector3.new(helixAnchorX, 0, helixAnchorZ)
		makeColumn(hallFolder, Vector3.new(helixAnchorX, -depth, helixAnchorZ), height + depth,
			9, false, hiddenColumnSeamYaw(hall, helixAnchorX, helixAnchorZ))
		local helixTop, helixNext = makeHelixSlide(hallFolder, helixColumn, helixRadius,
			deckY + 1 + 4.6 + .15,
			helixColor, "Level 2 Slide Hall " .. index .. " Helix")
		makeEntryTub(hallFolder, helixTop, helixNext, 4.6, deckY + 1,
			helixColor, "Level 2 Slide Hall " .. index .. " Helix", true)
		local helixDirection = Vector3.new(
			helixNext.X - helixTop.X, 0, helixNext.Z - helixTop.Z).Unit
		local entryLength = math.clamp(4.6 * 1.35, 5.5, 10)
		local entryRear = helixTop - helixDirection * entryLength
		local bridgeOuterX = hall.MaxX - 16
		local bridgeEndX = helixTop.X
		local bridgeLength = math.abs(bridgeOuterX - bridgeEndX)
		helixDockZ = entryRear.Z
		local bridge = tiledPart(hallFolder, "Level 2 Slide Hall Helix Catwalk",
			CFrame.new(Vector3.new((bridgeOuterX + bridgeEndX) * .5, deckY, helixDockZ)),
			Vector3.new(math.max(2, bridgeLength), 2, 14), C.TileWarm,
			Enum.NormalId:GetEnumItems(), 8)
		bridge.CanCollide = true
		bridge:SetAttribute("Level2_EntityGround", true)
		for _, railSide in ipairs({-1, 1}) do
			makeRail(hallFolder,
				Vector3.new(bridgeOuterX, railY, helixDockZ + railSide * 6.6),
				Vector3.new(entryRear.X + .3, railY, helixDockZ + railSide * 6.6),
				"Level 2 Slide Hall " .. index .. " Helix Catwalk "
					.. (railSide < 0 and "Left" or "Right"))
		end
		helixBuilt = true
	end

	-- Spiral stair in the south-east corner + catwalk along the east wall.
	local spiralOuterReach = 12 * 1.725
	local spiralCenter = Vector3.new(
		hall.MaxX - Configuration.WallThickness * .5 - spiralOuterReach - .75,
		0, hall.MaxZ - 26)
	-- topY +.65 puts the top tread's surface flush with the catwalk's.
	makeSpiralStair(hallFolder, spiralCenter, -depth + 1, deckY + .65, 12,
		"Level 2 Slide Hall " .. index .. " Spiral")
	local catwalkZ1 = deckFront
	local catwalkOuterX = hall.MaxX - Configuration.WallThickness * .5
	local catwalkInnerX = hall.MaxX - 16
	local catwalkWidth = catwalkOuterX - catwalkInnerX
	local catwalkCenterX = (catwalkOuterX + catwalkInnerX) * .5
	-- The single deck now reaches the wall-side catwalk edge for its full depth.
	-- This removes the residual 6.25 x 31.75 corner void without coplanar infill
	-- pieces, mismatched tile phases, or a hairline seam.
	-- The slab ends just past the docking tread: far enough that the tread
	-- lands fully on the walkway, short enough not to hang over the fan.
	local catwalkEndZ = hall.MaxZ - 22.6
	local eastCatwalk = tiledPart(hallFolder, "Level 2 Slide Hall Catwalk",
		CFrame.new(Vector3.new(catwalkCenterX, deckY, (catwalkEndZ + catwalkZ1) * .5)),
		Vector3.new(catwalkWidth, 2, math.abs(catwalkEndZ - catwalkZ1)), C.TileWarm,
		Enum.NormalId:GetEnumItems(), 8)
	eastCatwalk.CanCollide = true
	eastCatwalk:SetAttribute("Level2_EntityGround", true)
	-- Same-colour backings sit .02 below the walk surface at the two face-only
	-- slab joins. They cannot z-fight, but any sub-pixel raster/physics crack sees
	-- solid tile instead of the room void below.
	local deckJunctionBacking = part(hallFolder,
		"Level 2 Slide Hall Deck Catwalk Seam Backing",
		CFrame.new(catwalkCenterX, deckY + .78, deckFront),
		Vector3.new(catwalkWidth + .4, .4, 1.2), C.TileWarm, Enum.Material.CeramicTiles)
	deckJunctionBacking.CanCollide = false
	deckJunctionBacking.CanTouch = false
	deckJunctionBacking.CanQuery = false
	if helixBuilt then
		local bridgeJunctionBacking = part(hallFolder,
			"Level 2 Slide Hall Bridge Catwalk Seam Backing",
			CFrame.new(catwalkInnerX, deckY + .78, helixDockZ),
			Vector3.new(1.2, .4, 14.4), C.TileWarm, Enum.Material.CeramicTiles)
		bridgeJunctionBacking.CanCollide = false
		bridgeJunctionBacking.CanTouch = false
		bridgeJunctionBacking.CanQuery = false
	end
	if helixBuilt then
		-- Leave the bridge junction open instead of fencing off the slide.
		makeRail(hallFolder,
			Vector3.new(catwalkInnerX, railY, hall.MaxZ - 31),
			Vector3.new(catwalkInnerX, railY, helixDockZ + 7.5),
			"Level 2 Slide Hall " .. index .. " Catwalk S")
		makeRail(hallFolder,
			Vector3.new(catwalkInnerX, railY, helixDockZ - 7.5),
			Vector3.new(catwalkInnerX, railY, catwalkZ1),
			"Level 2 Slide Hall " .. index .. " Catwalk N")
	else
		makeRail(hallFolder,
			Vector3.new(catwalkInnerX, railY, hall.MaxZ - 31),
			Vector3.new(catwalkInnerX, railY, catwalkZ1),
			"Level 2 Slide Hall " .. index .. " Catwalk")
	end

	lightHall(hallFolder, hall, "SlideHall" .. index)

	return {Folder = hallFolder, DeckY = deckY, DeckZ = deckZ, DeckDepth = deckDepth}
end

-- LEVEL2_EXIT_TRANSITION_20260828
-- The exit route is one continuous ride into Level 3, not a short chute into a
-- waiting room. A rider leaves the top deck, takes the authored plunge, crosses
-- an invisible completion sensor, and then keeps sliding down a long enclosed
-- transition helix for the whole 15-second decision window. Nothing about that
-- ride tells the player they have "arrived": there is no visible end, no
-- exposed void, and no teleport out of the tube.
--
-- The former gateway room survives as the EMERGENCY RECOVERY CHAMBER. It is
-- fully sealed now (its west aperture is walled in, because no tube enters it
-- any more) and it is relocated clear of the transition helix. Nothing routes a
-- player there except the objective controller's explicit recovery path.
local function makeExitFlume(parent, layout, hall, deck)
	local radius = 8
	local boundsMaxX = layout.Bounds.MaxX
	local shellX = boundsMaxX + 60
	local startPoint = Vector3.new(hall.MaxX - 14, deck.DeckY + 9.3, deck.DeckZ)

	-- The forced eastern exit hall leaves only a short level lead-in. A densely
	-- sampled monotone Bezier commits the rider once the tube actually begins
	-- descending, then hands off to the transition helix without coarse seams.
	-- ── the genuinely endless continuation ──────────────────────────────────
	-- A straight descending transfer leads into a wide descending helix that the
	-- rider RECYCLES around, so the ride has no time limit at all.
	--
	-- The recycle is exact rather than approximate. This helix is uniform: the
	-- point at turn fraction t+1 is the point at t displaced by exactly
	-- (0, -descentPerTurn, 0), because the angle differs by a whole 2*pi. So
	-- lifting a rider one full turn puts them in a bore of identical shape, at
	-- an identical path tangent, and their velocity needs no adjustment at all.
	-- Nothing outside the tube is visible through a closed sleeve, so there is
	-- no parallax to betray the jump: the ride simply never ends.
	--
	-- That is what makes an arbitrary multiplayer wait survivable without
	-- thousands of parts. A first rider can circle here for minutes while the
	-- rest of the party finishes, and the geometry stays at three turns.
	--
	-- Grade is the other load-bearing number. The Slide Controller drops a
	-- one-way rider into RUNOUT_BRAKING as soon as the floor's downhill
	-- component falls under RELEASE_SLOPE (.12), so every segment from the
	-- plunge's exit tangent onward stays well above it. TRANSITION_GRADE is the
	-- sine of the descent angle along the path.
	local TRANSITION_GRADE = .21
	local TRANSITION_TRANSFER_RUN = 250
	local TRANSITION_HELIX_RADIUS = 96
	-- Three turns is the minimum that gives the recycle a full turn of bore
	-- ABOVE the landing point and a full turn BELOW the trigger. The rider
	-- circles turns one and two forever; turn three exists only so that a client
	-- which somehow fails to recycle still has a whole turn of real tube (about
	-- eleven seconds) before it meets the solid end stop, instead of a void.
	-- The bottom sits near y = -428, comfortably above the -500
	-- FallenPartsDestroyHeight that would otherwise delete a rider outright.
	local TRANSITION_HELIX_TURNS = 3
	-- Visual step is chosen from the helix sagitta: r*(1-cos(theta/2)) stays
	-- under a tenth of a stud, so the bore reads as a smooth curve rather than a
	-- faceted drum.
	local TRANSITION_VISUAL_STEP_DEGREES = 6

	local plungeEnd = Vector3.new(shellX + 41, 4, deck.DeckZ)
	local plungeStart = Vector3.new(plungeEnd.X - 120, startPoint.Y, deck.DeckZ)
	local plungeControl1 = plungeStart + Vector3.new(24, -2, 0)
	-- The plunge used to finish on a HORIZONTAL run-out, because it used to end
	-- in a room. It now hands over to the transition, so its exit tangent has to
	-- match the transition grade: a flat tail would drop a one-way rider into
	-- RUNOUT_BRAKING and stop the ride dead a few studs past completion.
	local plungeExitRise = 34 * TRANSITION_GRADE / math.sqrt(1 - TRANSITION_GRADE ^ 2)
	local plungeControl2 = plungeEnd + Vector3.new(-34, plungeExitRise, 0)
	local tubePoints = {startPoint, plungeStart}
	for segment = 1, 72 do
		table.insert(tubePoints, bezier(plungeStart, plungeControl1,
			plungeControl2, plungeEnd, segment / 72))
	end
	local exitColor = C.TileCool

	local transitionPoints = {}
	local function addTransitionPoint(point)
		local previous = transitionPoints[#transitionPoints] or tubePoints[#tubePoints]
		if (point - previous).Magnitude > .05 then
			table.insert(transitionPoints, point)
		end
	end

	-- Transfer: continue the plunge's heading (+X) while dropping at the
	-- transition grade, so the handover carries no direction discontinuity.
	local transferSteps = 18
	for step = 1, transferSteps do
		local along = TRANSITION_TRANSFER_RUN * step / transferSteps
		addTransitionPoint(Vector3.new(
			plungeEnd.X + along,
			plungeEnd.Y - along * TRANSITION_GRADE,
			plungeEnd.Z))
	end

	-- Helix: entered tangentially at the end of the transfer, winding away from
	-- the recovery chamber. Descent per turn is the grade applied to the arc
	-- length, which keeps the slope identical to the transfer run.
	local helixEntry = transitionPoints[#transitionPoints]
	local helixCenter = Vector3.new(helixEntry.X, helixEntry.Y, helixEntry.Z - TRANSITION_HELIX_RADIUS)
	local helixCircumference = 2 * math.pi * TRANSITION_HELIX_RADIUS
	local descentPerTurn = helixCircumference * TRANSITION_GRADE
	local helixSteps = math.ceil(TRANSITION_HELIX_TURNS * 360 / TRANSITION_VISUAL_STEP_DEGREES)
	for step = 1, helixSteps do
		local turnFraction = TRANSITION_HELIX_TURNS * step / helixSteps
		local angle = math.pi * .5 - turnFraction * math.pi * 2
		addTransitionPoint(Vector3.new(
			helixCenter.X + math.cos(angle) * TRANSITION_HELIX_RADIUS,
			helixEntry.Y - turnFraction * descentPerTurn,
			helixCenter.Z + math.sin(angle) * TRANSITION_HELIX_RADIUS))
	end

	for _, point in ipairs(transitionPoints) do
		table.insert(tubePoints, point)
	end

	-- Collision follows the visual polyline exactly, as every other slide in the
	-- level does. Subsampling it was tried and rejected: on the helix a coarser
	-- stride leaves straight floor segments chording a curve, which opens real
	-- holes between consecutive floors for a rider to drop through.
	local flumeModel = makeTubeFromPoints(parent, tubePoints, radius, exitColor,
		"Level 2 Exit Flume", false, .18, nil, nil, true)

	-- ── recycle + corridor metadata ─────────────────────────────────────────
	-- Published on the flume model so the CLIENT can perform the recycle (it
	-- owns the character's physics; a server PivotTo would fight it and trip the
	-- Slide Controller's own teleport guard), and so the SERVER can test whether
	-- a rider is still on the path analytically instead of with a bounding box.
	--
	-- The rider circles between the end of turn one and the end of turn two.
	-- Crossing the trigger lifts them exactly one turn, back to the landing Y.
	local helixTopY = helixEntry.Y
	local helixBottomY = helixEntry.Y - descentPerTurn * TRANSITION_HELIX_TURNS
	local recycleTriggerY = helixEntry.Y - descentPerTurn * (TRANSITION_HELIX_TURNS - 1)
	flumeModel:SetAttribute("Level2_RecycleActive", true)
	flumeModel:SetAttribute("Level2_RecycleTriggerY", recycleTriggerY)
	flumeModel:SetAttribute("Level2_RecycleDeltaY", descentPerTurn)
	flumeModel:SetAttribute("Level2_HelixCenterX", helixCenter.X)
	flumeModel:SetAttribute("Level2_HelixCenterZ", helixCenter.Z)
	flumeModel:SetAttribute("Level2_HelixRadius", TRANSITION_HELIX_RADIUS)
	flumeModel:SetAttribute("Level2_HelixTopY", helixTopY)
	flumeModel:SetAttribute("Level2_HelixBottomY", helixBottomY)
	flumeModel:SetAttribute("Level2_FlumeBoreRadius", radius)

	-- The closed-tube outlet cap makeTubeFromPoints builds is decorative
	-- (CanCollide false on both its branches), so the last segment's forward
	-- face is open. Level 3's continuation seals its own far end with a solid
	-- part for exactly this reason; the transition gets the same treatment, so
	-- reaching the bottom is a stop rather than an exit into the void.
	local transitionStart = transitionPoints[1]
	local transitionEnd = tubePoints[#tubePoints]
	do
		local tail = tubePoints[#tubePoints - 1]
		local axis = (transitionEnd - tail).Unit
		local up = Vector3.yAxis - axis * axis:Dot(Vector3.yAxis)
		if up.Magnitude < .05 then up = Vector3.zAxis end
		up = up.Unit
		local side = axis:Cross(up).Unit
		local stopThickness = 2
		-- Keep the cap inside the flume model. Besides making ownership/cleanup
		-- explicit, the transition validator (and any streaming consumer) can now
		-- discover the complete physical route from manifest.Exit.FlumeModel.
		local stop = part(flumeModel, "Level 2 Exit Transition End Stop",
			-- Overlap the final tube plane by half a stud. The old cap was centred
			-- four studs beyond it, leaving a 2.65-stud collision gap even though
			-- both parts looked visually adjacent from inside the sleeve.
			CFrame.fromMatrix(transitionEnd + axis * (stopThickness * .25), axis, up, side),
			Vector3.new(stopThickness, radius * 2 + 2, radius * 2 + 2),
			C.TileCool, Enum.Material.SmoothPlastic)
		stop.CanCollide = true
		stop.CanTouch = false
		stop.CanQuery = false
		stop.CastShadow = false
		stop:SetAttribute("Level2_ExitTransitionEndStop", true)
	end
	local transitionLength = 0
	for index = 74, #tubePoints - 1 do
		transitionLength += (tubePoints[index + 1] - tubePoints[index]).Magnitude
	end

	-- An axis-aligned envelope around the entire ride. The objective
	-- controller's recovery watchdog asks "is this rider still inside the
	-- flume?" against this box rather than raycasting for a slide floor every
	-- frame: the server's copy of a client-owned character lags at 100+ studs a
	-- second, and a single missed ray would end the transition on a rider who
	-- was doing nothing wrong.
	local boundsMin = tubePoints[1]
	local boundsMax = tubePoints[1]
	for _, point in ipairs(tubePoints) do
		boundsMin = Vector3.new(math.min(boundsMin.X, point.X),
			math.min(boundsMin.Y, point.Y), math.min(boundsMin.Z, point.Z))
		boundsMax = Vector3.new(math.max(boundsMax.X, point.X),
			math.max(boundsMax.Y, point.Y), math.max(boundsMax.Z, point.Z))
	end
	local boundsPadding = radius + 24
	local flumeBoundsCenter = (boundsMin + boundsMax) * .5
	local flumeBoundsSize = (boundsMax - boundsMin)
		+ Vector3.one * boundsPadding * 2

	local function pathAtX(targetX)
		for pointIndex = 1, #tubePoints - 1 do
			local a, b = tubePoints[pointIndex], tubePoints[pointIndex + 1]
			if targetX >= math.min(a.X, b.X) and targetX <= math.max(a.X, b.X) then
				local dx = b.X - a.X
				local alpha = math.abs(dx) > 1e-4
					and math.clamp((targetX - a.X) / dx, 0, 1) or 0
				return a:Lerp(b, alpha), (b - a).Unit
			end
		end
		local a, b = tubePoints[#tubePoints - 1], tubePoints[#tubePoints]
		return b, (b - a).Unit
	end
	local portalHalfWidth = radius + 1.25
	local hallPortalHalfHeight = radius + 1.25
	local mouth = makeEntryTub(parent, startPoint, tubePoints[2], radius, deck.DeckY + 1,
		exitColor, "Level 2 Exit Flume", true, false)

	-- ── emergency recovery chamber ──────────────────────────────────────────
	-- The old gateway room, sealed and moved clear of the helix. It exists only
	-- as a destination for the objective controller's recovery path (a rider who
	-- dies, is teleported, or otherwise leaves the tube mid-transition). It is
	-- deliberately not on any walkable route.
	local floorTop = plungeEnd.Y - radius * .9
	local catchSize = 78
	local gatewayHeight = 30
	local RECOVERY_CHAMBER_Z_OFFSET = 300
	local recoveryZ = deck.DeckZ + RECOVERY_CHAMBER_Z_OFFSET
	local westWallX = plungeEnd.X - 7
	local catchCenter = Vector3.new(
		westWallX + catchSize * .5,
		floorTop + gatewayHeight * .5,
		recoveryZ
	)

	local function gatewayWall(name, position, size)
		-- Extend upward without moving the authored bottom. The old walls only
		-- touched the ceiling to floating-point precision, which exposed a bright
		-- perimeter line at shadow-map grazing angles.
		local ceilingSeal = .35
		position += Vector3.yAxis * ceilingSeal * .5
		size = Vector3.new(size.X, size.Y + ceilingSeal, size.Z)
		local wall = tiledPart(parent, name, CFrame.new(position), size, C.TileCool, nil, 9)
		wall.CanCollide = true
		return wall
	end

	local floor = tiledPart(parent, "Level 2 Recovery Chamber Floor",
		CFrame.new(catchCenter.X, floorTop - .75, catchCenter.Z),
		Vector3.new(catchSize, 1.5, catchSize), C.TileWarm, {Enum.NormalId.Top}, 9)
	floor.CanCollide = true
	floor:SetAttribute("Level2_EntityGround", true)
	local ceiling = tiledPart(parent, "Level 2 Recovery Chamber Ceiling",
		CFrame.new(catchCenter.X, floorTop + gatewayHeight + .75, catchCenter.Z),
		Vector3.new(catchSize + 1.7, 1.5, catchSize + 1.7),
		C.TileCool, {Enum.NormalId.Bottom}, 9)
	ceiling.CanCollide = true

	-- Every side is sealed. The west wall used to carry a tube-sized aperture;
	-- no tube arrives here any more, so leaving the hole would only expose the
	-- void to a recovered player.
	gatewayWall("Level 2 Recovery Chamber North Wall",
		catchCenter + Vector3.new(0, 0, -catchSize * .5),
		Vector3.new(catchSize, gatewayHeight, 1.5))
	gatewayWall("Level 2 Recovery Chamber South Wall",
		catchCenter + Vector3.new(0, 0, catchSize * .5),
		Vector3.new(catchSize, gatewayHeight, 1.5))
	gatewayWall("Level 2 Recovery Chamber East Wall",
		catchCenter + Vector3.new(catchSize * .5, 0, 0),
		Vector3.new(1.5, gatewayHeight, catchSize))
	gatewayWall("Level 2 Recovery Chamber West Wall",
		Vector3.new(westWallX, catchCenter.Y, catchCenter.Z),
		Vector3.new(1.5, gatewayHeight, catchSize))

	-- The grand hall's east wall is still crossed by the tube, so it still needs
	-- its tube-axis collar; the recovery chamber no longer does.
	local function makeWallCollar(wallX, wallThickness, collarIndex)
		local crossing, direction = pathAtX(wallX)
		local axis = direction.Unit
		local radialZero = Vector3.zAxis
		if math.abs(axis:Dot(radialZero)) > .98 then radialZero = Vector3.yAxis end
		radialZero = (radialZero - axis * axis:Dot(radialZero)).Unit
		local segmentCount = 32
		local innerRadius = radius + .10
		local outerRadius = radius + 7.25
		local middleRadius = (innerRadius + outerRadius) * .5
		local radialThickness = outerRadius - innerRadius
		local tangentLength = 2 * outerRadius * math.tan(math.pi / segmentCount) + .08
		for segment = 0, segmentCount - 1 do
			local angle = (segment + .5) / segmentCount * math.pi * 2
			local radial = CFrame.fromAxisAngle(axis, angle):VectorToWorldSpace(radialZero).Unit
			local tangent = axis:Cross(radial).Unit
			local directionX = math.max(math.abs(axis.X), .2)
			-- Shift every block to the wall plane. At sloped crossings the top and
			-- bottom of a tube-axis ring otherwise sit several studs away from the
			-- wall and leave the rectangular portal exposed.
			local axisShift = -radial.X * middleRadius / axis.X
			local axialLength = wallThickness / directionX
				+ radialThickness * math.abs(radial.X) / directionX
				+ tangentLength * math.abs(tangent.X) / directionX + .5
			local collarPiece = part(parent,
				"Level 2 Exit Flume Wall Collar " .. collarIndex .. "." .. segment,
				CFrame.fromMatrix(crossing + radial * middleRadius + axis * axisShift,
					axis, radial, tangent),
				Vector3.new(axialLength, radialThickness, tangentLength),
				C.TileCool, Enum.Material.SmoothPlastic)
			collarPiece.CanCollide = false
			collarPiece.CanTouch = false
			collarPiece.CanQuery = false
			collarPiece:SetAttribute("Level2_ExitWallCollar", true)
		end
	end
	makeWallCollar(hall.MaxX, Configuration.WallThickness, 1)

	-- The wooden door is centered on the far wall and faces into the chamber.
	-- It is story-facing only and opens onto nothing.
	local outward = Vector3.new(1, 0, 0)
	local doorWidth, doorHeight = 12, 14
	local doorCenter = Vector3.new(
		catchCenter.X + catchSize * .5 - 1.65,
		floorTop + doorHeight * .5,
		catchCenter.Z
	)
	local doorFacing = CFrame.lookAt(doorCenter, doorCenter - outward)
	local wood = Color3.fromRGB(95, 60, 33)
	local woodDark = Color3.fromRGB(55, 34, 20)
	local woodenDoor = part(parent, "Level 2 Exit Room Wooden Door",
		doorFacing, Vector3.new(doorWidth, doorHeight, 1.2), wood, Enum.Material.WoodPlanks)
	woodenDoor.CanCollide = true
	woodenDoor:SetAttribute("Level2_StoryDoor", true)
	for index, data in ipairs({
		{Vector3.new(-doorWidth * .5 - .6, 0, 0), Vector3.new(1.2, doorHeight + 2, 1.55)},
		{Vector3.new(doorWidth * .5 + .6, 0, 0), Vector3.new(1.2, doorHeight + 2, 1.55)},
		{Vector3.new(0, doorHeight * .5 + .6, 0), Vector3.new(doorWidth + 2.4, 1.2, 1.55)},
	}) do
		local framePiece = part(parent, "Level 2 Exit Room Door Frame " .. index,
			doorFacing * CFrame.new(data[1]), data[2], woodDark, Enum.Material.WoodPlanks)
		framePiece.CanCollide = true
	end

	makeCeilingPanel(parent, catchCenter, "Gateway", Vector3.new(44, .55, 13), 0, floorTop + gatewayHeight)

	local safeSpawnPosition = doorCenter - outward * 4 + Vector3.new(0, -doorHeight * .5 + .12, 0)
	local safeSpawn = part(parent, "Level 2 Exit Safe Spawn",
		CFrame.new(safeSpawnPosition), Vector3.new(8, .24, 8),
		C.Emergency, Enum.Material.Neon, 1)
	safeSpawn.CanCollide = false
	safeSpawn.CanTouch = false
	safeSpawn:SetAttribute("Level2_ExitRecoverySpawn", true)

	-- ── completion sensor ───────────────────────────────────────────────────
	-- Permanently invisible: Transparency 1, no lights of any kind, no shadow,
	-- never tweened. The objective controller may only toggle CanTouch. It is
	-- deliberately thick along the tube axis so a rider travelling at the
	-- one-way speed cap cannot tunnel between two physics frames: at the 105
	-- stud/s soft cap a 60 Hz step covers 1.75 studs, and Roblox may coalesce
	-- several steps, so the sensor spans a whole multiple of that.
	local COMPLETION_SENSOR_THICKNESS = 9
	local sensorCenterPoint, sensorDirection = pathAtX(plungeEnd.X - 26)
	local sensorAxis = sensorDirection.Unit
	local sensorUp = Vector3.yAxis - sensorAxis * sensorAxis:Dot(Vector3.yAxis)
	if sensorUp.Magnitude < .05 then sensorUp = Vector3.zAxis end
	sensorUp = sensorUp.Unit
	local sensorSide = sensorAxis:Cross(sensorUp).Unit
	local trigger = part(parent, "Level 2 Exit Completion Beam",
		CFrame.fromMatrix(sensorCenterPoint, sensorAxis, sensorUp, sensorSide),
		Vector3.new(COMPLETION_SENSOR_THICKNESS, radius * 2 + 2, radius * 2 + 2),
		C.TileCool, Enum.Material.SmoothPlastic, 1)
	trigger.CanCollide = false
	trigger.CanTouch = false
	trigger.CanQuery = false
	trigger.CastShadow = false
	trigger:SetAttribute("Level2_ExitCompletionBeam", true)
	trigger:SetAttribute("Level2_ExitCompletionSensorThickness", COMPLETION_SENSOR_THICKNESS)

	-- A second, larger backstop sits one tube-diameter further down the bore.
	-- Touched is the only signal Roblox gives here, and a single sensor that
	-- misses (a rider hugging the chamfer, an unlucky frame) would silently cost
	-- the player the level. The controller treats either sensor as completion.
	local backstopPoint, backstopDirection = pathAtX(plungeEnd.X - 6)
	local backstopAxis = backstopDirection.Unit
	local backstopUp = Vector3.yAxis - backstopAxis * backstopAxis:Dot(Vector3.yAxis)
	if backstopUp.Magnitude < .05 then backstopUp = Vector3.zAxis end
	backstopUp = backstopUp.Unit
	local backstopSide = backstopAxis:Cross(backstopUp).Unit
	local backstop = part(parent, "Level 2 Exit Completion Backstop",
		CFrame.fromMatrix(backstopPoint, backstopAxis, backstopUp, backstopSide),
		Vector3.new(COMPLETION_SENSOR_THICKNESS, radius * 2 + 2, radius * 2 + 2),
		C.TileCool, Enum.Material.SmoothPlastic, 1)
	backstop.CanCollide = false
	backstop.CanTouch = false
	backstop.CanQuery = false
	backstop.CastShadow = false
	backstop:SetAttribute("Level2_ExitCompletionBeam", true)
	backstop:SetAttribute("Level2_ExitCompletionSensorThickness", COMPLETION_SENSOR_THICKNESS)

	return {
		Trigger = trigger,
		Backstop = backstop,
		SafeSpawn = safeSpawn,
		Mouth = mouth,
		EndPosition = doorCenter,
		StartPoint = startPoint,
		RoomEntry = plungeEnd,
		RoomFloorTop = floorTop,
		Door = woodenDoor,
		TransitionStart = transitionStart,
		TransitionEnd = transitionEnd,
		TransitionLength = transitionLength,
		FlumeBoundsCenter = flumeBoundsCenter,
		FlumeBoundsSize = flumeBoundsSize,
		FlumeModel = flumeModel,
		-- The authored path itself. The recovery watchdog measures distance to
		-- THIS rather than to a bounding box: an axis-aligned box around a helix
		-- contains the entire cylinder it sweeps, so a rider falling down the
		-- middle of the drum passes a box test the whole way to the floor.
		PathPoints = tubePoints,
		BoreRadius = radius,
		Recycle = {
			TriggerY = recycleTriggerY,
			DeltaY = descentPerTurn,
			LandingY = recycleTriggerY + descentPerTurn,
			CenterX = helixCenter.X,
			CenterZ = helixCenter.Z,
			Radius = TRANSITION_HELIX_RADIUS,
			TopY = helixTopY,
			BottomY = helixBottomY,
			Turns = TRANSITION_HELIX_TURNS,
		},
		HallWallGap = {
			center = startPoint.Z,
			width = portalHalfWidth * 2,
			bottom = startPoint.Y - hallPortalHalfHeight,
			top = startPoint.Y + hallPortalHalfHeight,
		},
	}
end

-- ── kids wing ───────────────────────────────────────────────────────────────

local KIDS_BALL_COLORS = {
	Color3.fromRGB(198, 77, 69),
	Color3.fromRGB(72, 137, 184),
	Color3.fromRGB(218, 177, 67),
	Color3.fromRGB(76, 156, 112),
	Color3.fromRGB(156, 92, 160),
}

local function makeKidsFoamPart(parent, name, cframe, size, color, shape, collidable)
	local object = part(parent, name, cframe, size, color, Enum.Material.SmoothPlastic)
	if shape then object.Shape = shape end
	useKidsMaterial(object, Enum.Material.SmoothPlastic, LEVEL2_KIDS_FOAM_VARIANT)
	object.Reflectance = 0
	object.CanCollide = collidable ~= false
	object:SetAttribute("Level2_KidsFoam", true)
	return object
end

local function makeKidsFoamWedge(parent, name, cframe, size, color)
	local object = Instance.new("WedgePart")
	object.Name = name
	object.Anchored = true
	object.CFrame = cframe
	object.Size = size
	object.Color = color
	object.Material = Enum.Material.SmoothPlastic
	object.MaterialVariant = LEVEL2_KIDS_FOAM_VARIANT
	object.TopSurface = Enum.SurfaceType.Smooth
	object.BottomSurface = Enum.SurfaceType.Smooth
	object.CanCollide = true
	object:SetAttribute("Level2_KidsFoam", true)
	object.Parent = parent
	return object
end

local function makeKidsFoamCluster(parent, hall, origin, forward, clusterIndex)
	local palette = kidsPalette(hall)
	local side = Vector3.new(-forward.Z, 0, forward.X)
	local baseFrame = CFrame.lookAt(origin, origin + forward)
	makeKidsFoamPart(parent, "Level 2 Padded Mat " .. clusterIndex,
		baseFrame * CFrame.new(0, .45, 0), Vector3.new(11, .9, 9),
		mutedKidsColor(palette.Accent, .18))
	local wedgeCenter = origin + forward * 7 + Vector3.new(0, 2, 0)
	makeKidsFoamWedge(parent, "Level 2 Foam Wedge " .. clusterIndex,
		CFrame.lookAt(wedgeCenter, wedgeCenter + forward),
		Vector3.new(7, 4, 7), mutedKidsColor(palette.Color, .16))
	local rollerCenter = origin - forward * 7 + Vector3.new(0, 2.1, 0)
	local roller = makeKidsFoamPart(parent, "Level 2 Foam Roller " .. clusterIndex,
		CFrame.lookAt(rollerCenter, rollerCenter + side) * CFrame.Angles(0, math.pi * .5, 0),
		Vector3.new(7, 4.2, 4.2), mutedKidsColor(palette.Accent, .10),
		Enum.PartType.Cylinder)
	roller:SetAttribute("Level2_KidsRoller", true)
end

local function makeKidsCrawlFrames(parent, hall, center, forward, label)
	local palette = kidsPalette(hall)
	local side = Vector3.new(-forward.Z, 0, forward.X)
	for frameIndex = -1, 1 do
		local frameCenter = center + forward * frameIndex * 4
		for _, sign in ipairs({-1, 1}) do
			makeKidsFoamPart(parent, label .. " Side " .. frameIndex .. "." .. sign,
				CFrame.new(frameCenter + side * sign * 4 + Vector3.new(0, 3, 0)),
				Vector3.new(2.4, 6, 2.4), mutedKidsColor(palette.Color, .22))
		end
		makeKidsFoamPart(parent, label .. " Top " .. frameIndex,
			CFrame.lookAt(frameCenter + Vector3.new(0, 6.1, 0), frameCenter + Vector3.new(0, 6.1, 0) + forward),
			Vector3.new(10.2, 2.2, 2.4), mutedKidsColor(palette.Accent, .18))
	end
end

local function makeKidsBallPit(parent, hall, center, rng, index, width, depth3)
	local palette = kidsPalette(hall)
	local pitFolder = folder(parent, "Level 2 Filled Ball Pit " .. index)
	width = width or 34
	depth3 = depth3 or 30
	local wallHeight = width < 12 and 2.4 or 3.2
	pitFolder:SetAttribute("Level2_BallPitWidth", width)
	pitFolder:SetAttribute("Level2_BallPitDepth", depth3)
	makeKidsFoamPart(pitFolder, "Level 2 Ball Pit Padded Base",
		CFrame.new(center + Vector3.new(0, .45, 0)), Vector3.new(width, .9, depth3),
		mutedKidsColor(palette.Accent, .30))
	local openingWidth = math.min(10, width * .34)
	local shoulderWidth = (width - openingWidth) * .5
	local shoulderCenter = openingWidth * .5 + shoulderWidth * .5
	for wallIndex, data in ipairs({
		{Vector3.new(-width * .5, wallHeight * .5, 0), Vector3.new(1.6, wallHeight, depth3)},
		{Vector3.new(width * .5, wallHeight * .5, 0), Vector3.new(1.6, wallHeight, depth3)},
		{Vector3.new(0, wallHeight * .5, depth3 * .5), Vector3.new(width, wallHeight, 1.6)},
		{Vector3.new(-shoulderCenter, wallHeight * .5, -depth3 * .5), Vector3.new(shoulderWidth, wallHeight, 1.6)},
		{Vector3.new(shoulderCenter, wallHeight * .5, -depth3 * .5), Vector3.new(shoulderWidth, wallHeight, 1.6)},
	}) do
		makeKidsFoamPart(pitFolder, "Level 2 Ball Pit Padded Wall " .. wallIndex,
			CFrame.new(center + data[1]), data[2], mutedKidsColor(palette.Color, .18))
	end
	makeKidsFoamPart(pitFolder, "Level 2 Ball Pit Entry Step",
		CFrame.new(center + Vector3.new(0, .55, -depth3 * .5 - 2.2)),
		Vector3.new(math.max(3, openingWidth - 1), 1.1, 3.2), mutedKidsColor(palette.Accent, .25))
	-- A hex-packed bed fills the pit completely — no random gaps exposing
	-- the base — with a second layer nestled into the hollows and a light
	-- sprinkle on top.
	local ballIndex = 0
	local function placeBall(x, y, z, jitter)
		ballIndex += 1
		local diameter = rng:NextNumber(1.42, 1.72)
		local ball = part(pitFolder,
			string.format("Level 2 Ball Pit Ball %03d", ballIndex),
			CFrame.new(center + Vector3.new(
				x + rng:NextNumber(-jitter, jitter),
				y + diameter * .5,
				z + rng:NextNumber(-jitter, jitter))),
			Vector3.new(diameter, diameter, diameter),
			KIDS_BALL_COLORS[((ballIndex + index) % #KIDS_BALL_COLORS) + 1],
			Enum.Material.SmoothPlastic)
		ball.Shape = Enum.PartType.Ball
		ball.CanCollide = false
		ball.CanTouch = false
		ball.CanQuery = false
		ball.CastShadow = false
		ball:SetAttribute("Level2_KidsDecorativeBall", true)
	end
	local spacing = 1.58
	local xLimit = width * .5 - 1.95
	local zLimit = depth3 * .5 - 1.95
	local row = 0
	local zCursor = -zLimit
	while zCursor <= zLimit + .01 do
		local xCursor = -xLimit + (row % 2) * spacing * .5
		while xCursor <= xLimit + .01 do
			placeBall(xCursor, .9, zCursor, .1)
			if rng:NextNumber() < .5 then
				placeBall(xCursor + spacing * .5, 2.06, zCursor + spacing * .44, .12)
			end
			if rng:NextNumber() < .1 then
				placeBall(xCursor, 3.2, zCursor, .16)
			end
			xCursor += spacing
		end
		row += 1
		zCursor += spacing * .87
	end
	pitFolder:SetAttribute("Level2_BallCount", ballIndex)
	return pitFolder
end

local function makeKidsSplashToys(parent, center, rng, index, poolWidth, poolDepth)
	local radiusX = math.max(2, poolWidth * .5 - 3)
	local radiusZ = math.max(2, poolDepth * .5 - 3)
	local diameterCap = math.max(1.8, math.min(poolWidth, poolDepth) * .16)
	for toyIndex = 1, 6 do
		local diameter = math.min(rng:NextNumber(2.1, 3.4), diameterCap)
		local angle = (toyIndex / 6) * math.pi * 2
		local toy = part(parent, "Level 2 Splash Ball " .. index .. "." .. toyIndex,
			CFrame.new(center + Vector3.new(math.cos(angle) * radiusX, 2.25,
				math.sin(angle) * radiusZ)),
			Vector3.new(diameter, diameter, diameter),
			KIDS_BALL_COLORS[((toyIndex + index) % #KIDS_BALL_COLORS) + 1],
			Enum.Material.SmoothPlastic)
		toy.Shape = Enum.PartType.Ball
		toy.CanCollide = false
		toy.CanTouch = false
		toy.CanQuery = false
		toy:SetAttribute("Level2_KidsWaterToy", true)
	end
end

local function styleKidsSlide(slideModel)
	for _, object in ipairs(slideModel:GetDescendants()) do
		if object:IsA("MeshPart") and object:GetAttribute("Level2_SlideVisual") == true then
			useKidsMaterial(object, Enum.Material.SmoothPlastic, LEVEL2_KIDS_SLIDE_VARIANT)
			object.Reflectance = .025
			object.CastShadow = false
			object:SetAttribute("Level2_KidsFiberglass", true)
		end
	end
end

local function makeKidsSlideStructure(parent, hall, center, forward, index, longDimension, slideMode)
	local palette = kidsPalette(hall)
	local side = Vector3.new(-forward.Z, 0, forward.X)
	local nano = slideMode == "Nano"
	local micro = nano or slideMode == "Micro"
	local compact = micro or slideMode == "Compact"
	local deckY = nano and 3.8 or (micro and 5.4 or (compact and 7.2 or 8.5))
	local radius = nano and 1.8 or (micro and 2.7 or (compact and 3.5 or 4.1))
	local stepCount = nano and 5 or (micro and 7 or (compact and 10 or 12))
	local stepRun = nano and .8 or (micro and 1.1 or (compact and 1.45 or 1.7))
	local stepRise = deckY / stepCount
	local totalLong = nano and math.min(20, longDimension * .32)
		or (micro and math.min(34, longDimension * .42)
		or (compact and math.min(49, longDimension * .54)
		or math.min(64, longDimension * .62)))
	local slideLength = nano and math.min(10.5, totalLong * .53)
		or (micro and math.min(20, totalLong * .59)
		or (compact and math.min(29, totalLong * .60)
		or math.min(39, totalLong * .62)))
	local deckWidth = nano and 8 or (micro and 12 or (compact and 17 or 20))
	local deckDepth = nano and 5 or (micro and 6 or (compact and 8 or 9))
	local stairWidth = nano and 4 or (micro and 5 or (compact and 6.5 or 7.5))
	local sideOffset = nano and 2.5 or (micro and 3.3 or (compact and 4.7 or 5.4))
	local backExtent = stepCount * stepRun
	local landingForward = nano and 4.5 or (micro and 7 or (compact and 9 or 11))
	local frontExtent = slideLength + landingForward
	local entry = center + forward * ((backExtent - frontExtent) * .5)
		- side * (nano and 2 or (micro and 3 or (compact and 4.2 or 5)))
	local exit = entry + forward * slideLength
	local deckCenter = entry + side * sideOffset + Vector3.new(0, deckY - .4, 0)
	local deckFrame = CFrame.lookAt(deckCenter, deckCenter + forward)
	local deck = makeKidsFoamPart(parent, "Level 2 Kids Slide Landing Deck " .. index,
		deckFrame, Vector3.new(deckWidth, .8, deckDepth), mutedKidsColor(palette.Accent, .20))
	deck:SetAttribute("Level2_EntityGround", true)
	deck:SetAttribute("Level2_KidsSlideMode", slideMode or "Full")
	local supportNear = sideOffset - deckWidth * .5 + 1
	local supportFar = sideOffset + deckWidth * .5 - 1
	local supportRun = deckDepth * .5 - 1
	for supportIndex, offset in ipairs({
		side * supportNear + forward * -supportRun,
		side * supportFar + forward * -supportRun,
		side * supportNear + forward * supportRun,
		side * supportFar + forward * supportRun,
	}) do
		makeKidsFoamPart(parent, "Level 2 Kids Slide Support " .. index .. "." .. supportIndex,
			CFrame.new(entry + offset + Vector3.new(0, deckY * .5, 0)),
			Vector3.new(1.4, deckY, 1.4), mutedKidsColor(palette.Color, .30))
	end
	local stairSide = nano and 4.3 or (micro and 6 or (compact and 8.5 or 10))
	local stairLine = entry + side * stairSide
	local stairBase = stairLine - forward * (stepCount * stepRun)
	makeStairFlight(parent, stairBase, forward, stairWidth, stepCount,
		"Level 2 Kids Connected Stair " .. index, stepRun, stepRise, hall)
	local rearGuardHeight = nano and 2.4 or (micro and 3.2 or 4.2)
	local sideGuardHeight = nano and 2.1 or (micro and 2.8 or 3.4)
	-- The stair lane crosses the deck's rear edge: the guard only covers the
	-- stretch AWAY from the stairs, so nothing walls off the top of the
	-- flight any more.
	local stairInner = stairSide - stairWidth * .5 - .5
	local deckLeft = sideOffset - deckWidth * .5
	local rearGuardWidth = math.max(2.5, stairInner - deckLeft)
	local rearGuardCenter = entry + side * (deckLeft + rearGuardWidth * .5)
		- forward * (deckDepth * .5 - .5)
		+ Vector3.new(0, deckY - .4 + rearGuardHeight * .5 + .3, 0)
	makeKidsFoamPart(parent, "Level 2 Kids Slide Rear Guard " .. index,
		CFrame.lookAt(rearGuardCenter, rearGuardCenter + forward),
		Vector3.new(rearGuardWidth, rearGuardHeight, .8), mutedKidsColor(palette.Color, .28))
	local sideGuardCenter = entry + side * (sideOffset + deckWidth * .5 - .4)
		+ Vector3.new(0, deckY + sideGuardHeight * .5 - .1, 0)
	makeKidsFoamPart(parent, "Level 2 Kids Slide Side Guard " .. index,
		CFrame.lookAt(sideGuardCenter, sideGuardCenter + forward),
		Vector3.new(.8, sideGuardHeight, deckDepth - 1), mutedKidsColor(palette.Color, .28))
	local p0 = entry + Vector3.new(0, deckY + radius + .5, 0)
	local p3 = exit + Vector3.new(0, .58 + radius * .9, 0)
	-- One soft local fill preserves the fiberglass texture in the play tower's
	-- deep shadow without raising exposure for the entire level.
	local fillAnchor = part(parent, "Level 2 Kids Slide Soft Fill Anchor " .. index,
		CFrame.new((p0 + p3) * .5 + Vector3.new(0, 5, 0)),
		Vector3.new(.2, .2, .2), palette.Accent, Enum.Material.SmoothPlastic, 1)
	fillAnchor.CanCollide = false
	fillAnchor.CanTouch = false
	fillAnchor.CanQuery = false
	fillAnchor.CastShadow = false
	local fillLight = Instance.new("PointLight")
	fillLight.Name = "Level 2 Kids Slide Soft Fill"
	fillLight.Color = palette.Accent:Lerp(Color3.new(1, 1, 1), .38)
	fillLight.Brightness = .85
	fillLight.Range = 34
	fillLight.Shadows = true
	fillLight.Parent = fillAnchor

	-- Kids slides wear their own room's colour, so the tube reads as part
	-- of the room instead of imported fiberglass.
	local slideColor = palette.Color:Lerp(Color3.new(1, 1, 1), .22)
	local controlLift = nano and .8 or (micro and 1.4 or 2.2)
	local slideModel = makeSlideTube(parent, p0,
		p0 + forward * (slideLength * .28),
		p3 - forward * (slideLength * .30) + Vector3.new(0, controlLift, 0),
		p3, radius, slideColor, "Level 2 Kids Slide " .. index,
		nano and 16 or (micro and 20 or (compact and 24 or 28)), true, .05,
		10, radius * 1.9)
	slideModel:SetAttribute("Level2_KidsSlideMode", slideMode or "Full")
	styleKidsSlide(slideModel)
	local landingCenter = exit + forward * (nano and 2 or (micro and 3 or (compact and 4 or 5)))
		+ Vector3.new(0, .38, 0)
	makeKidsFoamPart(parent, "Level 2 Kids Slide Landing Mat " .. index,
		CFrame.lookAt(landingCenter, landingCenter + forward),
		nano and Vector3.new(6, .76, 5)
			or (micro and Vector3.new(10, .76, 8)
			or (compact and Vector3.new(12, .76, 10) or Vector3.new(14, .76, 12))),
		mutedKidsColor(palette.Accent, .24))
	return slideModel
end

local function makeKidsHall(parent, hall, index, doors, kidsPumpIndex)
	local palette = kidsPalette(hall)
	local center = hall.Center + Vector3.new(0, hallFloorY(hall), 0)
	local kidsFolder = folder(parent, "Level 2 Kids Room " .. index .. " " .. palette.Name)
	local containsPump = hall.PumpIndex ~= nil
	kidsFolder:SetAttribute("Level2_KidsColor", palette.Name)
	kidsFolder:SetAttribute("Level2_KidsTileTexture", kidsTileTextureId(hall) or "")
	kidsFolder:SetAttribute("Level2_ContainsPump", containsPump)

	local zones = {}
	local edgeMargin = 6
	local function reserve(label, position, width, depth3, spacing)
		spacing = spacing or 3
		if position.X - width * .5 < hall.MinX + edgeMargin
			or position.X + width * .5 > hall.MaxX - edgeMargin
			or position.Z - depth3 * .5 < hall.MinZ + edgeMargin
			or position.Z + depth3 * .5 > hall.MaxZ - edgeMargin then
			return false
		end
		for _, other in ipairs(zones) do
			if math.abs(position.X - other.Position.X) < (width + other.Width) * .5 + spacing
				and math.abs(position.Z - other.Position.Z) < (depth3 + other.Depth) * .5 + spacing then
				return false
			end
		end
		table.insert(zones, {
			Label = label,
			Position = position,
			Width = width,
			Depth = depth3,
		})
		return true
	end
	local function reserveFirst(label, candidates, width, depth3, spacing)
		for _, candidate in ipairs(candidates) do
			if reserve(label, candidate, width, depth3, spacing) then return candidate end
		end
		return nil
	end
	local function placementCandidates(width, depth3)
		local minX = hall.MinX + edgeMargin + width * .5
		local maxX = hall.MaxX - edgeMargin - width * .5
		local minZ = hall.MinZ + edgeMargin + depth3 * .5
		local maxZ = hall.MaxZ - edgeMargin - depth3 * .5
		if minX > maxX or minZ > maxZ then return {} end
		local candidates = {}
		-- Try deliberate quadrant/edge compositions first.
		for _, fraction in ipairs({
			{.75, .75}, {.25, .75}, {.75, .25}, {.25, .25},
			{.5, .75}, {.5, .25}, {.75, .5}, {.25, .5}, {.5, .5},
		}) do
			table.insert(candidates, Vector3.new(
				minX + (maxX - minX) * fraction[1], center.Y,
				minZ + (maxZ - minZ) * fraction[2]))
		end
		-- Then scan every legal pocket at no more than four-stud intervals.
		local xCount = math.max(1, math.ceil((maxX - minX) / 4))
		local zCount = math.max(1, math.ceil((maxZ - minZ) / 4))
		for xIndex = 0, xCount do
			local x = minX + (maxX - minX) * (xIndex / xCount)
			for zIndex = 0, zCount do
				local z = minZ + (maxZ - minZ) * (zIndex / zCount)
				table.insert(candidates, Vector3.new(x, center.Y, z))
			end
		end
		return candidates
	end

	-- Door thresholds deliberately touch the room edge, so they bypass the
	-- interior edge-margin test used for props.  Activity zones still reject
	-- against these first, preserving an 18-stud-wide, 28-stud-deep approach.
	doors = doors or {East = {}, West = {}, North = {}, South = {}}
	local function reserveDoor(label, position, width, depth3)
		table.insert(zones, {
			Label = label,
			Position = position,
			Width = width,
			Depth = depth3,
		})
	end
	local doorwayClearWidth = Configuration.DoorWidth + 8
	for _, doorZ in ipairs(doors.West or {}) do
		reserveDoor("West doorway", Vector3.new(hall.MinX + 16, 0, doorZ), 32, doorwayClearWidth)
	end
	for _, doorZ in ipairs(doors.East or {}) do
		reserveDoor("East doorway", Vector3.new(hall.MaxX - 16, 0, doorZ), 32, doorwayClearWidth)
	end
	for _, doorX in ipairs(doors.North or {}) do
		reserveDoor("North doorway", Vector3.new(doorX, 0, hall.MinZ + 16), doorwayClearWidth, 32)
	end
	for _, doorX in ipairs(doors.South or {}) do
		reserveDoor("South doorway", Vector3.new(doorX, 0, hall.MaxZ - 16), doorwayClearWidth, 32)
	end
	-- Kids set pieces use their own reservation solver and therefore never saw
	-- nearHallNavigationRoute. Reserve the same hub-and-spoke contract as real
	-- AABBs before the ball pit, slide, crawl frames, foam clusters or entity
	-- spawn claim a pocket. Seed 404's ball pit was centred on this lane and made
	-- the otherwise-valid 1 -> 39 route throw its plan away after 798 studs.
	local navigationWidth = 24
	-- The spokes below already reserve every real door-to-centre route.  Keep
	-- only their shared central junction here: reserving two full-room bars as
	-- well double-counted those routes and left seed 202's four-door Kids room
	-- with no legal Slide Tower pocket.
	reserveDoor("Navigation hub", center, navigationWidth, navigationWidth)
	local function reserveVerticalSpoke(label, doorX, edgeZ)
		local midpointZ = (edgeZ + hall.Center.Z) * .5
		reserveDoor(label, Vector3.new(doorX, 0, midpointZ),
			navigationWidth, math.abs(edgeZ - hall.Center.Z))
	end
	local function reserveHorizontalSpoke(label, doorZ, edgeX)
		local midpointX = (edgeX + hall.Center.X) * .5
		reserveDoor(label, Vector3.new(midpointX, 0, doorZ),
			math.abs(edgeX - hall.Center.X), navigationWidth)
	end
	for _, doorX in ipairs(doors.North or {}) do
		reserveVerticalSpoke("North navigation spoke", doorX, hall.MinZ)
	end
	for _, doorX in ipairs(doors.South or {}) do
		reserveVerticalSpoke("South navigation spoke", doorX, hall.MaxZ)
	end
	for _, doorZ in ipairs(doors.West or {}) do
		reserveHorizontalSpoke("West navigation spoke", doorZ, hall.MinX)
	end
	for _, doorZ in ipairs(doors.East or {}) do
		reserveHorizontalSpoke("East navigation spoke", doorZ, hall.MaxX)
	end
	if containsPump then
		table.insert(zones, {
			Label = "Pump interaction",
			Position = center,
			Width = 60,
			Depth = 52,
		})
	end

	-- Reserve final-art clearance before set pieces consume the remaining room.
	-- The rig footprint is about 5.2 x 3.8 studs; this zone plus normal spacing
	-- keeps it out of pumps, door approaches, slides, pits and foam clusters.
	local poolFoamSpawnPosition = reserveFirst("Pool Foam spawn",
		placementCandidates(8, 8), 8, 8, 4)
	assert(poolFoamSpawnPosition,
		string.format("[Level 2] no safe Pool Foam spawn in Kids room %s", tostring(index)))

	local slideIndex = kidsPumpIndex == 3 and 4 or 3
	local ballIndex = kidsPumpIndex == 2 and 5 or 2
	local archetype
	if containsPump then archetype = "Pump Playroom"
	elseif index == 1 then archetype = "Splash Room"
	elseif index == slideIndex then archetype = "Slide Tower"
	elseif index == ballIndex then archetype = "Ball Pit Room"
	else archetype = "Sparse Abandoned Room" end
	kidsFolder:SetAttribute("Level2_PlayArchetype", archetype)

	local rng = Random.new((hall.LocalSeed or index) + 918273)
	local longAlongX = hall.Width >= hall.Depth
	local longAxis = longAlongX and Vector3.new(1, 0, 0) or Vector3.new(0, 0, 1)
	local sideAxis = Vector3.new(-longAxis.Z, 0, longAxis.X)

	local corePlaced = archetype == "Pump Playroom"
	local coreTier = corePlaced and "Pump" or nil
	if archetype == "Splash Room" then
		local preferredWidth = math.max(28, math.min(46, hall.Width * .34))
		local preferredDepth = math.max(26, math.min(40, hall.Depth * .36))
		local poolOptions = {
			{preferredWidth, preferredDepth, "Full"},
			{math.max(24, preferredWidth * .82), math.max(22, preferredDepth * .82), "Compact"},
			{20, 18, "Micro"},
			{14, 12, "Nano"},
			{10, 8, "Tiny"},
		}
		for _, option in ipairs(poolOptions) do
			local zoneWidth, zoneDepth = option[1] + 8, option[2] + 10
			local poolCenter = reserveFirst("Raised splash pool",
				placementCandidates(zoneWidth, zoneDepth), zoneWidth, zoneDepth, 3)
			if poolCenter then
				makeRaisedPool(kidsFolder, poolCenter, option[1], option[2], hall)
				makeKidsSplashToys(kidsFolder, poolCenter, rng, index, option[1], option[2])
				corePlaced, coreTier = true, option[3]
				break
			end
		end
	elseif archetype == "Ball Pit Room" then
		local pitOptions = {
			{34, 30, "Full"},
			{28, 24, "Compact"},
			{22, 18, "Micro"},
			{14, 13, "Nano"},
			{8, 7, "Tiny"},
		}
		for _, option in ipairs(pitOptions) do
			local zoneWidth, zoneDepth = option[1] + 8, option[2] + 9
			local pitCenter = reserveFirst("Filled ball pit",
				placementCandidates(zoneWidth, zoneDepth), zoneWidth, zoneDepth, 3)
			if pitCenter then
				makeKidsBallPit(kidsFolder, hall, pitCenter, rng, index, option[1], option[2])
				corePlaced, coreTier = true, option[3]
				break
			end
		end
		local crawlWidth = math.abs(longAxis.X) > 0 and 20 or 15
		local crawlDepth = math.abs(longAxis.Z) > 0 and 20 or 15
		local crawlCenter = reserveFirst("Crawl frames",
			placementCandidates(crawlWidth, crawlDepth), crawlWidth, crawlDepth, 3)
		if crawlCenter then makeKidsCrawlFrames(kidsFolder, hall, crawlCenter, longAxis,
			"Level 2 Foam Crawl Frame " .. index) end
	elseif archetype == "Slide Tower" then
		local slideOptions = {
			{Long = 76, Short = 28, Mode = "Full"},
			{Long = 58, Short = 26, Mode = "Compact"},
			{Long = 42, Short = 22, Mode = "Micro"},
			{Long = 24, Short = 14, Mode = "Nano"},
		}
		for _, option in ipairs(slideOptions) do
			for _, forward in ipairs({longAxis, sideAxis}) do
				local zoneWidth = math.abs(forward.X) > 0 and option.Long or option.Short
				local zoneDepth = math.abs(forward.Z) > 0 and option.Long or option.Short
				local slideCenter = reserveFirst("Connected slide tower",
					placementCandidates(zoneWidth, zoneDepth), zoneWidth, zoneDepth, 3)
				if slideCenter then
					local directionLength = math.abs(forward.X) > 0 and hall.Width or hall.Depth
					makeKidsSlideStructure(kidsFolder, hall, slideCenter, forward, index,
						directionLength, option.Mode)
					corePlaced, coreTier = true, option.Mode
					break
				end
			end
			if corePlaced then break end
		end
	elseif archetype == "Sparse Abandoned Room" then
		local abandonedOptions = {
			{
				Width = math.abs(longAxis.X) > 0 and 22 or 14,
				Depth = math.abs(longAxis.Z) > 0 and 22 or 14,
				Tier = "Sparse",
			},
			-- Four-door minimum rooms can have no 22x14 pocket even though the
			-- crawl-frame geometry itself fits safely inside a 12x12 footprint.
			{Width = 12, Depth = 12, Tier = "SparseCompact"},
		}
		for _, option in ipairs(abandonedOptions) do
			local crawlCenter = reserveFirst("Abandoned crawl frames",
				placementCandidates(option.Width, option.Depth), option.Width, option.Depth, 3)
			if crawlCenter then
				makeKidsCrawlFrames(kidsFolder, hall, crawlCenter, longAxis,
					"Level 2 Abandoned Foam Frame " .. index)
				for ballIndex = 1, 3 do
					-- Keep the abandoned balls beside the frames and inside both
					-- the normal and compact reservations.
					local offset = sideAxis * (ballIndex - 2) * 4 + longAxis * 4
					local ball = part(kidsFolder, "Level 2 Displaced Ball " .. ballIndex,
						CFrame.new(crawlCenter + offset + Vector3.new(0, 1.15, 0)),
						Vector3.new(2.3, 2.3, 2.3),
						KIDS_BALL_COLORS[((ballIndex + index) % #KIDS_BALL_COLORS) + 1],
						Enum.Material.SmoothPlastic)
					ball.Shape = Enum.PartType.Ball
					ball.CanCollide = false
					ball.CanTouch = false
					ball.CanQuery = false
					ball:SetAttribute("Level2_KidsDisplacedProp", true)
				end
				corePlaced, coreTier = true, option.Tier
				break
			end
		end
		if not corePlaced then
			-- A minimum-size four-door room can legitimately have no prop pocket
			-- beyond the protected creature spawn.  Keep it deliberately bare and
			-- let the waiting Pool Foam rig be this rare room's focal set piece.
			corePlaced, coreTier = true, "SparseEntityOnly"
		end
	end
	kidsFolder:SetAttribute("Level2_CoreSetPiecePlaced", corePlaced)
	kidsFolder:SetAttribute("Level2_CoreSizeTier", coreTier)
	assert(corePlaced, string.format("[Level 2] no safe %s placement in Kids room %s", archetype, tostring(index)))

	-- Deliberate edge-first clusters replace the old field of overlapping
	-- random boxes.  Each orientation reserves its true footprint.
	local desiredClusters = archetype == "Sparse Abandoned Room" and 2
		or archetype == "Pump Playroom" and 2
		or 1
	local placedClusters = 0
	for clusterIndex = 1, desiredClusters do
		local clusterForward = clusterIndex % 2 == 0 and Vector3.new(1, 0, 0)
			or Vector3.new(0, 0, 1)
		local clusterWidth = math.abs(clusterForward.X) > 0 and 30 or 15
		local clusterDepth = math.abs(clusterForward.Z) > 0 and 30 or 15
		local candidate = reserveFirst("Foam cluster",
			placementCandidates(clusterWidth, clusterDepth), clusterWidth, clusterDepth, 3)
		if candidate then
			placedClusters += 1
			makeKidsFoamCluster(kidsFolder, hall, candidate, clusterForward, placedClusters)
		end
	end

	kidsFolder:SetAttribute("Level2_ReservedZoneCount", #zones)
	kidsFolder:SetAttribute("Level2_FoamClusterCount", placedClusters)
	-- Kids rooms remain lit only by the round natural skylights in their ceiling.
	return kidsFolder, poolFoamSpawnPosition
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

local function addMachineTexture(object, faces)
	local textureId = level2MachineTextureId()
	if not textureId then return end
	for _, face in ipairs(faces) do
		-- Decal stretches one complete artwork across the face without the
		-- repetition of Texture or the intermittent blank render of SurfaceGui.
		local artwork = Instance.new("Decal")
		artwork.Name = "Level 2 Pump Machinery Artwork " .. face.Name
		artwork.Face = face
		artwork.Texture = textureId
		artwork.Color3 = Color3.fromRGB(225, 227, 226)
		artwork.Transparency = .04
		artwork.Parent = object
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
	local center = hall.Center + Vector3.new(0, hallFloorY(hall), 0)
	local model = Instance.new("Model")
	model.Name = "Level 2 Pump Station " .. index
	model:SetAttribute("Level2_PumpIndex", index)
	model:SetAttribute("Level2_HallId", hall.Id)
	model:SetAttribute("Level2_InKidsArea", hall.Role == "Kids Area")
	model:SetAttribute("Level2_LeverHandleColor", handleSpec.Name)
	model:SetAttribute("Level2_LeverHandleColorValue", handleSpec.Color)
	model:SetAttribute("Level2_PressurePercent", 0)
	model:SetAttribute("Level2_PressureRestored", false)
	model:SetAttribute("Level2_PumpRunning", false)
	model.Parent = parent

	-- The plinth sits on the walkway island (WALKWAY_TOP above the water).
	local plinth = tiledPart(model, "Level 2 Pump Plinth",
		CFrame.new(center + Vector3.new(0, 2.5, 0)), Vector3.new(25, 5, 17), C.TileWarm, nil, 8)
	plinth.CanCollide = true

	-- Large cabinet silhouette: readable as machinery from across a hall.
	local housing = part(model, "Level 2 Pump Machinery Cabinet",
		CFrame.new(center + Vector3.new(0, 11.2, 0)), Vector3.new(18, 16.2, 9),
		Color3.fromRGB(91, 96, 98), Enum.Material.Metal)
	housing.CanCollide = true
	housing.Reflectance = .12
	-- Keep the cabinet sides as clean modeled metal. Reusing the same
	-- artwork on three faces made the station look tiled and artificial.

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

	-- The approved machinery artwork is square. Give it a square physical inset
	-- so it stays undistorted, with the wider dark panel acting as a clean matte.
	local artworkPanel = part(model, "Level 2 Pump Machinery Artwork Panel",
		CFrame.new(center + Vector3.new(0, 11.25, 5.205)), Vector3.new(11.6, 11.6, .05),
		Color3.fromRGB(32, 35, 37), Enum.Material.SmoothPlastic)
	artworkPanel.Reflectance = .08
	artworkPanel.CastShadow = false
	artworkPanel.CanCollide = false
	artworkPanel.CanTouch = false
	artworkPanel.CanQuery = false
	addMachineTexture(artworkPanel, {Enum.NormalId.Back})

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

	local pressureLockedColor = Color3.fromRGB(235, 72, 58)
	local lamp = part(model, "Level 2 Pump Status Lamp",
		CFrame.new(center + Vector3.new(4.75, 15.25, 5.38)), Vector3.new(3.4, 1.25, .35),
		pressureLockedColor, Enum.Material.Neon)
	lamp.CanCollide = false
	local lampGlow = Instance.new("PointLight")
	lampGlow.Name = "Level 2 Pump Status Lamp Glow"
	lampGlow.Color = pressureLockedColor
	lampGlow.Brightness = .294
	lampGlow.Range = 12
	lampGlow.Shadows = true
	lampGlow.Parent = lamp

	-- Functional pressure gauge. The anchored invisible pivot is the animation
	-- target; its welded needle sweeps linearly from 0 to 100 while the pump runs.
	local gaugeCenter = center + Vector3.new(-4.8, 14.7, 5.91)
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

	local gaugeMarkings = part(model, "Level 2 Pump Pressure Gauge Markings",
		CFrame.new(gaugeCenter), Vector3.new(3.0, 3.0, .03),
		Color3.fromRGB(226, 224, 206), Enum.Material.SmoothPlastic)
	gaugeMarkings.Transparency = 1
	gaugeMarkings.CastShadow = false
	gaugeMarkings.CanCollide = false
	gaugeMarkings.CanTouch = false
	gaugeMarkings.CanQuery = false
	local gaugeGui = Instance.new("SurfaceGui")
	gaugeGui.Name = "Level 2 Pump Pressure Gauge Surface"
	gaugeGui.Face = Enum.NormalId.Back
	gaugeGui.LightInfluence = .2
	gaugeGui.PixelsPerStud = 100
	gaugeGui.Parent = gaugeMarkings
	local function gaugeText(name, text, position, size, color)
		local label = Instance.new("TextLabel")
		label.Name = name
		label.BackgroundTransparency = 1
		label.Position = position
		label.Size = size
		label.Font = Enum.Font.GothamBold
		label.Text = text
		label.TextColor3 = color
		label.TextScaled = true
		label.TextStrokeColor3 = Color3.fromRGB(226, 224, 206)
		label.TextStrokeTransparency = .72
		label.Parent = gaugeGui
		return label
	end
	gaugeText("Level 2 Pump Pressure Zero Label", "0",
		UDim2.fromScale(.04, .56), UDim2.fromScale(.2, .18), Color3.fromRGB(54, 58, 59))
	gaugeText("Level 2 Pump Pressure Hundred Label", "100",
		UDim2.fromScale(.73, .56), UDim2.fromScale(.24, .18), Color3.fromRGB(54, 58, 59))
	gaugeText("Level 2 Pump Pressure Title", "PRESSURE",
		UDim2.fromScale(.25, .76), UDim2.fromScale(.5, .11), Color3.fromRGB(54, 58, 59))
	local gaugePressureText = gaugeText("Level 2 Pump Pressure Percent", "0%",
		UDim2.fromScale(.33, .52), UDim2.fromScale(.34, .17), C.Locked)

	for tickIndex = 0, 10 do
		local alpha = tickIndex / 10
		local angle = math.rad(65 - 130 * alpha)
		local radius = 1.08
		local offset = Vector3.new(-math.sin(angle) * radius, math.cos(angle) * radius, .035)
		local tickLength = (tickIndex == 0 or tickIndex == 5 or tickIndex == 10) and .34 or .23
		local tick = part(model, "Level 2 Pump Pressure Gauge Tick " .. tickIndex,
			CFrame.new(gaugeCenter + offset) * CFrame.Angles(0, 0, angle),
			Vector3.new(.09, tickLength, .07), Color3.fromRGB(62, 66, 66), Enum.Material.Metal)
		tick.CanCollide = false
		tick.CanTouch = false
		tick.CanQuery = false
	end

	local gaugeNeedlePivot = part(model, "Level 2 Pump Pressure Gauge Needle Pivot",
		CFrame.new(gaugeCenter + Vector3.new(0, 0, .08)) * CFrame.Angles(0, 0, math.rad(65)),
		Vector3.new(.12, .12, .08), C.Locked, Enum.Material.Neon)
	gaugeNeedlePivot.Transparency = 1
	gaugeNeedlePivot.CastShadow = false
	gaugeNeedlePivot.CanCollide = false
	gaugeNeedlePivot.CanTouch = false
	gaugeNeedlePivot.CanQuery = false
	local gaugeNeedle = part(model, "Level 2 Pump Pressure Gauge Needle",
		gaugeNeedlePivot.CFrame * CFrame.new(0, .57, 0),
		Vector3.new(.16, 1.14, .10), C.Locked, Enum.Material.Neon)
	gaugeNeedle.Anchored = false
	gaugeNeedle.CanCollide = false
	gaugeNeedle.CanTouch = false
	gaugeNeedle.CanQuery = false
	gaugeNeedle.Massless = true
	local gaugeNeedleWeld = Instance.new("WeldConstraint")
	gaugeNeedleWeld.Name = "Level 2 Pump Pressure Gauge Needle Weld"
	gaugeNeedleWeld.Part0 = gaugeNeedlePivot
	gaugeNeedleWeld.Part1 = gaugeNeedle
	gaugeNeedleWeld.Parent = gaugeNeedlePivot
	local gaugeHub = part(model, "Level 2 Pump Pressure Gauge Center Hub",
		CFrame.new(gaugeCenter + Vector3.new(0, 0, .15)), Vector3.new(.42, .42, .22),
		Color3.fromRGB(51, 55, 56), Enum.Material.Metal)
	gaugeHub.Shape = Enum.PartType.Ball
	gaugeHub.Reflectance = .2
	gaugeHub.CanCollide = false
	gaugeHub.CanTouch = false
	gaugeHub.CanQuery = false

	local gaugePressureValue = Instance.new("NumberValue")
	gaugePressureValue.Name = "Level 2 Pump Pressure Value"
	gaugePressureValue.Value = 0
	gaugePressureValue.Parent = model

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

	-- Match the custom 6.17-stud avatar instead of towering over it. At 34%
	-- the complete station is about 6.78 studs tall; scale around its plinth,
	-- then lower it so the reduced plinth still sits exactly on the floor.
	local stationScale = .34
	model:ScaleTo(stationScale)
	local groundCorrection = (5 - plinth.Size.Y) * .5
	model:PivotTo(model:GetPivot() + Vector3.new(0, -groundCorrection, 0))
	model:SetAttribute("Level2_VisualScale", stationScale)

	-- Scaling and grounding move the animated pivots, so capture their final
	-- world-space endpoints only after the complete model has settled.
	leverIdleCFrame = lever.CFrame
	local gaugeNeedleZeroCFrame = gaugeNeedlePivot.CFrame
	local gaugeNeedleFullCFrame = gaugeNeedleZeroCFrame * CFrame.Angles(0, 0, math.rad(-130))
	prompt.MaxActivationDistance = 10

	return {
		Model = model,
		Prompt = prompt,
		Lever = lever,
		LeverAssembly = leverAssembly,
		LeverHandle = grip,
		LeverStatusRing = statusRing,
		LeverRestCFrame = leverIdleCFrame,
		GaugeNeedlePivot = gaugeNeedlePivot,
		GaugeNeedle = gaugeNeedle,
		GaugeNeedleZeroCFrame = gaugeNeedleZeroCFrame,
		GaugeNeedleFullCFrame = gaugeNeedleFullCFrame,
		GaugePressureValue = gaugePressureValue,
		GaugePressureText = gaugePressureText,
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
		-- The halls meet wall-to-wall; the doorway lives in the wall. Bridge
		-- the footprint gap between the two extended halls so the doorway has
		-- a floor instead of a hole down to the foundation.
		local hallA = layout.Halls[corridor.A]
		local hallB = layout.Halls[corridor.B]
		local gapMid = (corridor.From + corridor.To) * .5
		-- Two flush halves, each wearing its own room's colour, meeting exactly
		-- at the wall line and never wider than the doorway itself.
		local acrossWidth = Configuration.DoorWidth - .4
		local function half(styleHall, offsetSign)
			local floorY = hallFloorY(styleHall)
			local halfCenter = corridor.Axis == "X"
				and Vector3.new(gapMid + offsetSign * 2.25, floorY, corridor.Cross)
				or Vector3.new(corridor.Cross, floorY, gapMid + offsetSign * 2.25)
			local slab = surfaceFor(styleHall, parent, "Level 2 Shared Doorway Threshold",
				CFrame.new(halfCenter + Vector3.new(0, -.35, 0)),
				corridor.Axis == "X" and Vector3.new(4.7, .7, acrossWidth)
					or Vector3.new(acrossWidth, .7, 4.7),
				nil, {Enum.NormalId.Top})
			slab.CanCollide = true
			slab:SetAttribute("Level2_EntityGround", true)
		end
		local aIsLow = corridor.Axis == "X" and hallA.Center.X < hallB.Center.X
			or corridor.Axis ~= "X" and hallA.Center.Z < hallB.Center.Z
		half(aIsLow and hallA or hallB, -1)
		half(aIsLow and hallB or hallA, 1)
		return nil
	end

	local width = corridor.Width
	local height = Configuration.CorridorHeight
	local from, to = corridor.From, corridor.To
	local gapLength = math.abs(to - from)
	local length = gapLength + 4
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

	-- Corridors that touch the kids wing wear the kids tiles end to end.
	local hallA = layout.Halls[corridor.A]
	local hallB = layout.Halls[corridor.B]
	local kidsStyleHall = (isKids(hallA) and hallA) or (isKids(hallB) and hallB) or nil
	local function hallAlong(hall)
		return alongX and hall.Center.X or hall.Center.Z
	end
	local negativeEndHall, positiveEndHall = hallA, hallB
	if hallAlong(negativeEndHall) > hallAlong(positiveEndHall) then
		negativeEndHall, positiveEndHall = positiveEndHall, negativeEndHall
	end
	local function corridorSkin(name, cf, size, normalColor, faces, studs)
		if kidsStyleHall then
			return surfaceFor(kidsStyleHall, parent, name, cf, size, nil, faces, studs)
		end
		return tiledPart(parent, name, cf, size, normalColor, faces, studs)
	end

	-- Recessed floor, water wall-to-wall.
	local floorSlab = corridorSkin("Level 2 Corridor Water Floor",
		CFrame.new(center + Vector3.new(0, -depth - .6, 0)),
		orientedSize(length, 1.2, width), C.TileCool, {Enum.NormalId.Top}, 8)
	floorSlab.CanCollide = true
	floorSlab:SetAttribute("Level2_EntityGround", true)

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

	-- A very slim walkway along one side of the tunnel, just proud of the
	-- water, running wall to water: its slab reaches the corridor wall face
	-- (the arch ribs and vault feet plant themselves INTO its buried outer
	-- band, which reads as arch feet standing on the deck), while the CLEAR
	-- walking line stays 1.9 studs inboard of the rib radius so the whole
	-- player volume threads the vault without brushing a rib. The full-depth
	-- slab keeps the entity navigator's support test valid, and a submerged
	-- curb along its inner edge splits the mount into two easy steps, so the
	-- ledge stays reachable even from a drained 1.8 channel.
	local ledgeWidth = Configuration.CorridorWalkwayWidth or 0
	local ledgeRibRadius = math.min(width * .5 - 3, Configuration.DoorWidth * .5 - 1.8)
	local ledgeInner = ledgeRibRadius - 1.9 - ledgeWidth
	-- Bury the outer edge .15 into the corridor wall so no seam can show, and
	-- run the slab THROUGH both doorways to the halls' interior wall faces:
	-- it reads as a sill through the arch and meets a hall edge walkway with
	-- the same .15 skirting seam the ring keeps against every wall. The
	-- portal caps' outer spandrels and the arch face rings are non-collide
	-- and simply plant into the slab's buried outer band; a closed pressure
	-- door swallows its 2.2-stud stretch and reveals it when it rises.
	local ledgeOuter = width * .5 - Configuration.WallThickness * .5 + .15
	local ledgeLength = gapLength + Configuration.WallThickness
	if ledgeWidth > 0 and ledgeInner > 2 and ledgeLength > 8 then
		local ledgeSide = corridor.Index % 2 == 0 and 1 or -1
		local ledgeHeight = WALKWAY_TOP + depth + .3
		local ledge = corridorSkin("Level 2 Corridor Side Ledge " .. corridor.Index,
			CFrame.new(center + oriented(0, ledgeSide * (ledgeInner + ledgeOuter) * .5)
				+ Vector3.new(0, WALKWAY_TOP - ledgeHeight * .5, 0)),
			orientedSize(ledgeLength, ledgeHeight, ledgeOuter - ledgeInner), C.TileWarm,
			{Enum.NormalId.Top, Enum.NormalId.Front, Enum.NormalId.Back,
				Enum.NormalId.Left, Enum.NormalId.Right}, 7)
		ledge.CanCollide = true
		ledge:SetAttribute("Level2_EntityGround", true)
		local curbTop = -.8
		local curbHeight = curbTop + depth + .3
		if curbHeight > .4 then
			local curb = corridorSkin("Level 2 Corridor Side Ledge Curb " .. corridor.Index,
				CFrame.new(center + oriented(0, ledgeSide * (ledgeInner - .6))
					+ Vector3.new(0, curbTop - curbHeight * .5, 0)),
				orientedSize(ledgeLength, curbHeight, 1.2), C.TileCool,
				{Enum.NormalId.Top, Enum.NormalId.Front, Enum.NormalId.Back,
					Enum.NormalId.Left, Enum.NormalId.Right}, 7)
			curb.CanCollide = true
			curb:SetAttribute("Level2_EntityGround", true)
		end
	end

	-- Walls reach below the waterline; ceiling stays solid (tunnels). Stop the
	-- rectangular shell just behind the hall's outer wall face so it cannot
	-- read as a second box sitting on top of the doorway.
	local wallBottom = -depth - 3
	local wallTop = height + 2
	local wallHalf = Configuration.WallThickness * .5
	local shellLength = gapLength + 2 * (wallHalf - .12)
	for _, side in ipairs({-1, 1}) do
		local wall = corridorSkin("Level 2 Corridor Wall",
			CFrame.new(center + oriented(0, side * width * .5) + Vector3.new(0, (wallTop + wallBottom) * .5, 0)),
			orientedSize(shellLength, wallTop - wallBottom, Configuration.WallThickness), C.TileCool, nil, 7)
		wall.CanCollide = true
	end
	local ceiling = corridorSkin("Level 2 Corridor Ceiling",
		CFrame.new(center + Vector3.new(0, height + 1, 0)),
		orientedSize(shellLength, 2, width), C.TileCool, {Enum.NormalId.Bottom}, 9)
	ceiling.CanCollide = true

	-- Dense arch rings: the corridor reads as a vaulted arch tunnel.
	local rings = math.clamp(math.floor(length / 22), 3, 7)
	-- Keep the outer vault inside the standard doorway shoulders. The old
	-- 15.4-stud shell was wider than the 30-stud opening and visibly clipped.
	local archRadius = math.min(width * .5 - 3, Configuration.DoorWidth * .5 - 1.8)
	for ring = 1, rings do
		local t = ring / (rings + 1)
		-- Standard corridor ribs only expose their two axial ends and the local
		-- Bottom face toward the player. Avoid replicating textures on the buried
		-- outer face and the overlapping segment seams. Kids variants retain their
		-- authored face treatment.
		local ribOptions = kidsStyleHall and nil or {
			Faces = {Enum.NormalId.Left, Enum.NormalId.Right, Enum.NormalId.Bottom},
		}
		makeArchSpan(parent, center + oriented(from - mid + (to - from) * t, 0),
			alongX, corridor.Index .. "." .. ring, archRadius, depth, kidsStyleHall, ribOptions)
	end
	-- The ribs connect into one continuous half-cylinder vault.
	local vaultRadius = math.min(archRadius + 1.4, Configuration.DoorWidth * .5 - .9)
	local portalFaceDepth = .6
	local vaultLength = gapLength + 2 * (wallHalf - portalFaceDepth + .25)
	makeBarrelVault(parent, center, alongX, corridor.Index, vaultRadius, vaultLength, depth, kidsStyleHall)

	-- Integrate each tunnel mouth into the hall's existing 30 x 19 doorway.
	-- A single header keeps the tile field continuous above the crown; narrow
	-- spandrel strips only fill the curved shoulders. The thin, high-resolution
	-- face ring sits at the hall-facing wall surface and hides the final sub-stud
	-- approximation, instead of being recessed behind it.
	local sealMargin = .15
	local capHalfWidth = Configuration.DoorWidth * .5 + sealMargin
	local capTop = Configuration.DoorHeight + sealMargin
	local faceRadialDepth = 1.4
	local faceRadius = math.min(vaultRadius,
		capHalfWidth - faceRadialDepth * .5 - .12)
	local capCurveRadius = math.min(capHalfWidth - .04,
		faceRadius + faceRadialDepth * .5 - .12)
	local capCrown = 1 + capCurveRadius
	local capBottom = -depth - 2.2
	-- Keep the .15-stud sealing flange hidden behind the real hall wall. The
	-- old cap was .02 proud on both faces, exposing a narrow independently tiled
	-- strip whose grout phase visibly reset at every tunnel mouth.
	local capDepth = Configuration.WallThickness - .12
	-- Twenty-four narrow portal slats preserve the curved tiled shoulder at
	-- normal viewing distance while removing thousands of tiny non-collidable
	-- parts and texture instances from a typical generated level.
	local slats = 24
	local slatWidth = (capHalfWidth * 2) / slats
	local capFaces = alongX
		and {Enum.NormalId.Left, Enum.NormalId.Right}
		or {Enum.NormalId.Front, Enum.NormalId.Back}
	for _, endSign in ipairs({-1, 1}) do
		local along = endSign < 0 and (from - mid) or (to - mid)
		local endHall = endSign < 0 and negativeEndHall or positiveEndHall
		local endStyleHall = isKids(endHall) and endHall or nil
		local endWallColor = isKids(endHall) and kidsPalette(endHall).Color or C.TileCool
		local function portalSurface(name, y, tall, across, acrossSize)
			local object = surfaceFor(endHall, parent, name,
				CFrame.new(center + oriented(along, across) + Vector3.new(0, y, 0)),
				orientedSize(capDepth, tall, acrossSize), endWallColor, capFaces, 7)
			object.CanCollide = false
			object.CanTouch = false
			object.CanQuery = false
			return object
		end

		local headerHeight = capTop - capCrown
		portalSurface("Level 2 Corridor Arch Header " .. corridor.Index,
			(capTop + capCrown) * .5, headerHeight, 0, capHalfWidth * 2)

		for slat = 0, slats - 1 do
			local xLocal = -capHalfWidth + (slat + .5) * slatWidth
			local arcY
			local outerEdgeX = math.min(capCurveRadius,
				math.abs(xLocal) + (slatWidth + .07) * .5)
			if math.abs(xLocal) >= capCurveRadius then
				arcY = capBottom
			elseif outerEdgeX < capCurveRadius then
				-- Sample the farthest edge of each rectangular strip, not its centre.
				-- The hidden .08 overlap follows the circular face ring and closes the
				-- tiny triangular wedges that otherwise show between approximations.
				arcY = 1 + math.sqrt(math.max(capCurveRadius ^ 2 - outerEdgeX ^ 2, 0)) - .08
			else
				arcY = 1 - .08
			end
			local spandrelTop = capCrown + .05
			if spandrelTop - arcY > .08 then
				portalSurface("Level 2 Corridor Arch Spandrel " .. corridor.Index,
					(spandrelTop + arcY) * .5, spandrelTop - arcY,
					xLocal, slatWidth + .07)
			end
		end

		local faceAlong = along + endSign * (wallHalf - portalFaceDepth * .5 + .04)
		makeArchSpan(parent, center + oriented(faceAlong, 0),
			alongX, corridor.Index .. ".face" .. endSign, faceRadius, depth, endStyleHall, {
				AxialDepth = portalFaceDepth,
				RadialDepth = faceRadialDepth,
				Density = 2.1,
				MinimumSteps = 28,
				SegmentOverlap = .42,
				Faces = {Enum.NormalId.Left, Enum.NormalId.Right},
				Studs = 7,
				CanCollide = false,
			})
	end

	-- Tunnel light comes from small lamps INSIDE the vault; the old ceiling
	-- bar sat above the shell and glowed over the tunnel from outside.
	for _, lightT in ipairs({-.25, .25}) do
		local emitter = part(parent, "Level 2 Corridor Vault Light " .. corridor.Index,
			CFrame.new(center + oriented(lightT * length, 0) + Vector3.new(0, vaultRadius - 2.2, 0)),
			Vector3.new(1.2, .4, 1.2), C.Light, Enum.Material.Neon, 1)
		emitter.CanCollide = false
		emitter.CanTouch = false
		emitter.CanQuery = false
		emitter.CastShadow = false
		local lamp = Instance.new("PointLight")
		lamp.Color = C.Light
		lamp.Brightness = .7
		lamp.Range = 26
		lamp.Shadows = true
		lamp.Parent = emitter
	end

	-- Water, full width.
	local waterHeight = depth + .1
	local region = addWater(center + Vector3.new(0, .1 - waterHeight * .5, 0),
		alongX and Vector3.new(length - 1, waterHeight, width + 1.5)
			or Vector3.new(width + 1.5, waterHeight, length - 1),
		"Corridor " .. corridor.Index)

	local door, doorStripe
	if corridor.Kind == "PressureDoor" then
		local doorCenter = center + oriented(to - mid, 0) + Vector3.new(0, height * .5 - 2, 0)
		door = part(doorFolder, "Level 2 Pressure Door " .. corridor.Index,
			CFrame.new(doorCenter), orientedSize(2.2, height + 4, width), C.Locked,
			Enum.Material.DiamondPlate)
		door.CanCollide = true
		door:SetAttribute("Level2_CorridorIndex", corridor.Index)
		doorStripe = part(doorFolder, "Level 2 Pressure Door Stripe " .. corridor.Index,
			CFrame.new(doorCenter + Vector3.new(0, 4, 0)),
			orientedSize(2.4, 1.2, width - 4), C.Locked, Enum.Material.Neon)
		doorStripe.CanCollide = false
	end

	return {Corridor = corridor, Water = region, Door = door, Stripe = doorStripe, Center = center}
end

-- Turn a prop into a real floating object: unanchored and lighter than
-- water, so it bobs on the surface and drifts when players wade into it.
local function makeBuoyant(object, density)
	object.Anchored = false
	object.CanCollide = true
	object.CanTouch = true
	object.CustomPhysicalProperties = PhysicalProperties.new(density or .22, .35, .45, 1, 1)
	-- The Slidemouth's soft-shove sweep targets exactly this tag; without it no
	-- floating toy ever reacts to the creature passing through.
	object:SetAttribute("Level2_BuoyantProp", true)
	return object
end

-- Buoyant props wedged inside geometry stand still forever; probe candidate
-- spots and only spawn where the water is genuinely open.
local function freeWaterSpot(hall, rng, size)
	for _ = 1, 8 do
		local position = hall.Center + Vector3.new(
			rng:NextNumber(-.36, .36) * hall.Width, 1.4,
			rng:NextNumber(-.36, .36) * hall.Depth)
		local params = OverlapParams.new()
		params.MaxParts = 8
		local blocked = false
		for _, hit in ipairs(workspace:GetPartBoundsInBox(
			CFrame.new(position), size + Vector3.new(2.5, 2.5, 2.5), params)) do
			if hit:IsA("BasePart") and hit.Anchored and hit.CanCollide
				and not hit.Name:find("Water Floor", 1, true) then
				blocked = true
				break
			end
		end
		if not blocked then
			return Vector3.new(position.X, 0, position.Z)
		end
	end
	return nil
end

-- The life layer: every water hall carries traces of the leisure complex it
-- used to be — parasols (some tipped), loungers sunk in the shallows, beach
-- balls and pool noodles adrift, lifebuoys and a stopped clock on the walls,
-- pennant strings between the columns, and grime at the waterline.
-- Door-aware and deterministic per hall.
local function dressHall(parent, hall, depth, doors, index, density)
	if not depth then return end
	doors = doors or {East = {}, West = {}, North = {}, South = {}}
	local rng = Random.new((hall.LocalSeed or hall.Index or 1) + 29)
	density = density or 1
	local height = hallHeight(hall)
	local faded = function(color) return color:Lerp(Color3.fromRGB(168, 168, 158), .38) end

	local function wallSpotClear(sideList, value)
		for _, doorAt in ipairs(sideList) do
			if math.abs(doorAt - value) < Configuration.DoorWidth * .5 + 8 then return false end
		end
		return true
	end

	-- Loungers sunk in the shallows (skip in deep halls, and in slide halls
	-- where they would land inside the low flume runs).
	if depth <= 2.2 and hall.Role ~= "Slide Hall" then
		local loungers = math.clamp(math.floor(hall.Area / 30000 * density), 1, 3)
		for lounger = 1, loungers do
			local frame
			for _ = 1, 12 do
				local lx = rng:NextNumber(-.36, .36) * hall.Width
				local lz = rng:NextNumber(-.36, .36) * hall.Depth
				local yaw = rng:NextNumber() * math.pi * 2
				local roll = rng:NextNumber() < .35
					and math.rad(rng:NextNumber(30, 70)) or 0
				local position = hall.Center + Vector3.new(lx, -depth + .9, lz)
				-- The solid 6.4-stud seat used to bypass the same route guard every
				-- larger structure obeys. Seed 202 put Lounger 23.1 directly on a
				-- hall-centre spoke, so an otherwise certified 1 -> 29 graph route
				-- repeatedly replanned into the same chair. Reserve the seat's whole
				-- rotated footprint around the authored hub/spokes before placing it.
				if not nearDoorApproach(hall, doors, position.X, position.Z, 22)
					and not nearHallNavigationRoute(hall, doors,
						position.X, position.Z, 21) then
					frame = CFrame.new(position) * CFrame.Angles(0, yaw, roll)
					break
				end
			end
			if not frame then continue end
			local seatColor = faded(Configuration.SlideColors[rng:NextInteger(1, #Configuration.SlideColors)])
			local seat = part(parent, "Level 2 Lounger Seat " .. index .. "." .. lounger,
				frame, Vector3.new(2.6, .5, 6.4), seatColor, Enum.Material.SmoothPlastic)
			seat.CanCollide = true
			local back = part(parent, "Level 2 Lounger Back " .. index .. "." .. lounger,
				frame * CFrame.new(0, 1.4, -2.9) * CFrame.Angles(math.rad(-35), 0, 0),
				Vector3.new(2.6, .4, 3.4), seatColor, Enum.Material.SmoothPlastic)
			back.CanCollide = false
		end
	end

	-- Beach balls and pool noodles adrift on the surface — plenty of them,
	-- and each spawned only where the water is open so none starts wedged.
	for ball = 1, math.clamp(math.floor(hall.Area / 9000 * density), 2, 10) do
		local size = rng:NextNumber(1.6, 2.6)
		local spot = freeWaterSpot(hall, rng, Vector3.new(size, size, size))
		if spot then
			local orb = part(parent, "Level 2 Beach Ball " .. index .. "." .. ball,
				CFrame.new(spot + Vector3.new(0, .1 + size * .28, 0)),
				Vector3.new(size, size, size),
				Configuration.SlideColors[rng:NextInteger(1, #Configuration.SlideColors)],
				Enum.Material.SmoothPlastic)
			orb.Shape = Enum.PartType.Ball
			makeBuoyant(orb, .16)
		end
	end
	for noodle = 1, math.clamp(math.floor(hall.Area / 8000 * density), 3, 12) do
		local spot = freeWaterSpot(hall, rng, Vector3.new(6, 1, 6))
		if spot then
			local pool = part(parent, "Level 2 Pool Noodle " .. index .. "." .. noodle,
				CFrame.new(spot + Vector3.new(0, .5, 0))
					* CFrame.Angles(0, rng:NextNumber() * math.pi, 0),
				Vector3.new(6, .6, .6),
				Configuration.SlideColors[rng:NextInteger(1, #Configuration.SlideColors)],
				Enum.Material.SmoothPlastic)
			makeBuoyant(pool, .14)
		end
	end

	-- A stopped clock on doorless wall stretches (lifebuoys removed on
	-- request).
	local clockX = hall.Center.X + rng:NextNumber(-.25, .25) * hall.Width
	if rng:NextNumber() < .5 and wallSpotClear(doors.South, clockX) then
		local face = part(parent, "Level 2 Stopped Clock " .. index,
			CFrame.new(Vector3.new(clockX, height - 6, hall.MaxZ - 2.75)) * CFrame.Angles(0, math.pi * .5, 0),
			Vector3.new(.5, 4.2, 4.2), Color3.fromRGB(238, 238, 228), Enum.Material.SmoothPlastic)
		face.Shape = Enum.PartType.Cylinder
		face.CanCollide = false
		local hourHand = part(parent, "Level 2 Clock Hand H " .. index,
			CFrame.new(Vector3.new(clockX, height - 6.6, hall.MaxZ - 3.15)),
			Vector3.new(.3, 1.3, .2), C.Void, Enum.Material.SmoothPlastic)
		hourHand.CanCollide = false
		local minuteHand = part(parent, "Level 2 Clock Hand M " .. index,
			CFrame.new(Vector3.new(clockX + .6, height - 6, hall.MaxZ - 3.15)),
			Vector3.new(1.4, .3, .2), C.Void, Enum.Material.SmoothPlastic)
		minuteHand.CanCollide = false
	end

	-- (Waterline grime stains removed on request: they read as dark
	-- see-through blocks on the walls.)
end

-- Diving/jumping board colours, in the requested order.
local BOARD_COLORS = {
	Color3.fromRGB(78, 158, 214), -- blue
	Color3.fromRGB(238, 202, 84), -- yellow
	Color3.fromRGB(224, 96, 84), -- red
	Color3.fromRGB(96, 196, 132), -- green
}

-- A one-piece slide kit: a straight stair climbs the back of a railed
-- platform on legs, and a straight chute runs out the front into the water.
-- Everything hangs off ONE origin and yaw, so the pieces can never drift
-- apart, and the caller pre-checks that both far ends stay clear.
local function makeSlideKit(parent, hall, depth, origin, yaw, padTop, chuteRun, color, index)
	local frame = CFrame.new(origin) * CFrame.Angles(0, yaw, 0)
	local function at(offset)
		return (frame * CFrame.new(offset)).Position
	end
	local pad = tiledPart(parent, "Level 2 Slide Kit Pad " .. index,
		frame * CFrame.new(0, padTop - .4, 0), Vector3.new(8, .8, 8),
		C.TileWarm, Enum.NormalId:GetEnumItems(), 7)
	pad.CanCollide = true
	pad:SetAttribute("Level2_EntityGround", true)
	local legHeight = padTop - .8 + depth
	for legIndex, corner in ipairs({{-3.2, -3.2}, {3.2, -3.2}, {-3.2, 3.2}, {3.2, 3.2}}) do
		local leg = part(parent, "Level 2 Slide Kit Leg " .. index .. "." .. legIndex,
			frame * CFrame.new(corner[1], -depth + legHeight * .5, corner[2]),
			Vector3.new(1.1, legHeight, 1.1), C.Rail, Enum.Material.Metal)
		leg.CanCollide = true
	end
	-- Exact rise: the top step lands flush with the platform surface.
	local stepCount = math.ceil((padTop + depth) / .75)
	local stepRun, stepRise = 1.5, (padTop + depth) / stepCount
	local stairBase = at(Vector3.new(-4 - stepCount * stepRun, -depth, 0))
	local stairDirection = at(Vector3.new(1, 0, 0)) - origin
	makeStairFlight(parent, stairBase, stairDirection, 6, stepCount,
		"Level 2 Slide Kit Steps " .. index, stepRun, stepRise)
	makeStairSideRails(parent, stairBase, stairDirection, 6, stepCount, stepRun, stepRise,
		"Level 2 Slide Kit " .. index)
	for _, railSide in ipairs({-1, 1}) do
		makeRail(parent, at(Vector3.new(-3.8, padTop + .1, railSide * 3.8)),
			at(Vector3.new(3.8, padTop + .1, railSide * 3.8)),
			"Level 2 Slide Kit " .. index .. "." .. (railSide + 2))
	end
	-- A real open fiberglass half-tube replaces the old board-and-lip chute.
	local slideDirection = stairDirection.Unit
	local radius = 2.6
	local p0 = at(Vector3.new(3.6, padTop + radius + .15, 0))
	local p3 = at(Vector3.new(4 + chuteRun, radius - depth + .4, 0))
	local p1Horizontal = p0 + slideDirection * (chuteRun * .3)
	local p1 = Vector3.new(p1Horizontal.X, p0.Y, p1Horizontal.Z)
	local p2 = p3 - slideDirection * (chuteRun * .28)
		+ Vector3.new(0, math.max(1.5, (p0.Y - p3.Y) * .18), 0)
	makeSlideTube(parent, p0, p1, p2, p3, radius, color,
		"Level 2 Slide Kit Chute " .. index, 24, true, .05, 10, radius * 1.9)
	makeEntryTub(parent, p0, p1, radius, padTop, color,
		"Level 2 Slide Kit Chute " .. index, true)
end

-- A diving tower: a slim tiled core carries a railed top platform, one
-- straight stair climbs the back, and jump boards jut out at SEVERAL heights
-- on alternating sides (blue/yellow/red/green), each ledge stepping straight
-- off the stair. Nothing orbits anything, so nothing can interpenetrate.
local function makeDivingTower(parent, hall, depth, origin, yaw, rng, index, boardHeights)
	local frame = CFrame.new(origin) * CFrame.Angles(0, yaw, 0)
	local function at(offset)
		return (frame * CFrame.new(offset)).Position
	end
	local top = boardHeights[#boardHeights]
	local colorOffset = rng:NextInteger(0, #BOARD_COLORS - 1)
	local coreHeight = top - .8 + depth
	local core = tiledPart(parent, "Level 2 Diving Tower Core " .. index,
		frame * CFrame.new(0, -depth + coreHeight * .5, 0), Vector3.new(5, coreHeight, 7),
		C.TileWarm, Enum.NormalId:GetEnumItems(), 7)
	core.CanCollide = true
	local platform = tiledPart(parent, "Level 2 Diving Tower Platform " .. index,
		frame * CFrame.new(0, top - .4, 0), Vector3.new(7.5, .8, 9),
		C.TileWarm, Enum.NormalId:GetEnumItems(), 7)
	platform.CanCollide = true
	for _, railSide in ipairs({-1, 1}) do
		makeRail(parent, at(Vector3.new(-3.6, top + .1, railSide * 4.3)),
			at(Vector3.new(3.6, top + .1, railSide * 4.3)),
			"Level 2 Diving Tower " .. index .. "." .. (railSide + 2))
	end
	local stepCount = math.ceil((top + depth) / .9)
	local stepRun, stepRise = 1.25, (top + depth) / stepCount
	local stairBase = at(Vector3.new(-3.75 - stepCount * stepRun, -depth, 0))
	local stairDirection = at(Vector3.new(1, 0, 0)) - origin
	-- No side rails here: the board ledges hang off both flanks of this
	-- stair, and rails would fence the boards off.
	makeStairFlight(parent, stairBase, stairDirection, 5, stepCount,
		"Level 2 Diving Tower Steps " .. index, stepRun, stepRise)
	for boardIndex, boardHeight in ipairs(boardHeights) do
		local color = BOARD_COLORS[((boardIndex - 1 + colorOffset) % #BOARD_COLORS) + 1]
		if boardIndex == #boardHeights then
			-- The top board dives straight ahead off the platform.
			local board = part(parent, "Level 2 Diving Board " .. index .. "." .. boardIndex,
				frame * CFrame.new(5.9, boardHeight + .2, 0), Vector3.new(5.6, .45, 2.6),
				color, Enum.Material.SmoothPlastic)
			board.CanCollide = true
		else
			-- A ledge hangs off the stair's flank exactly where the stair
			-- passes this height, with its own support post.
			local side = boardIndex % 2 == 0 and 1 or -1
			local landingX = -3.75 - (top - boardHeight) / stepRise * stepRun
			local ledge = tiledPart(parent, "Level 2 Diving Ledge " .. index .. "." .. boardIndex,
				frame * CFrame.new(landingX, boardHeight - .4, side * 4.5), Vector3.new(4.4, .8, 4),
				C.TileWarm, Enum.NormalId:GetEnumItems(), 7)
			ledge.CanCollide = true
			local postHeight = boardHeight - .8 + depth
			local post = part(parent, "Level 2 Diving Ledge Post " .. index .. "." .. boardIndex,
				frame * CFrame.new(landingX, -depth + postHeight * .5, side * 5.6),
				Vector3.new(1, postHeight, 1), C.Rail, Enum.Material.Metal)
			post.CanCollide = true
			local board = part(parent, "Level 2 Diving Board " .. index .. "." .. boardIndex,
				frame * CFrame.new(landingX, boardHeight + .2, side * 8.9), Vector3.new(2.6, .45, 6.4),
				color, Enum.Material.SmoothPlastic)
			board.CanCollide = true
		end
	end
end

-- Pump rooms: a raised WALKWAY ring around the room plus a centre cross to
-- the pump island, standing just above shallow water that fills the rest of
-- the floor (step off the walkway and you wade). No pipes anywhere.
local function decoratePumpHall(parent, hall, index, doors)
	doors = doors or {East = {}, West = {}, North = {}, South = {}}
	local rng = Random.new((hall.LocalSeed or hall.Index or 1) + 13)
	local walkwayWidth = 6.5
	local depth = hallWaterDepth(hall) or 1.2

	local function deck(name, centerPos, sizeX, sizeZ)
		local slabHeight = WALKWAY_TOP + depth + .3
		local slab = tiledPart(parent, name,
			CFrame.new(Vector3.new(centerPos.X, WALKWAY_TOP - slabHeight * .5, centerPos.Z)),
			Vector3.new(sizeX, slabHeight, sizeZ), C.TileWarm,
			{Enum.NormalId.Top, Enum.NormalId.Front, Enum.NormalId.Back,
				Enum.NormalId.Left, Enum.NormalId.Right}, 7)
		slab.CanCollide = true
		slab:SetAttribute("Level2_EntityGround", true)
		return slab
	end

	-- Perimeter ring hugging all four walls.
	local inset = walkwayWidth * .5 + 1.9
	deck("Level 2 Pump Walkway North " .. index,
		Vector3.new(hall.Center.X, 0, hall.MinZ + inset), hall.Width - 3.5, walkwayWidth)
	deck("Level 2 Pump Walkway South " .. index,
		Vector3.new(hall.Center.X, 0, hall.MaxZ - inset), hall.Width - 3.5, walkwayWidth)
	deck("Level 2 Pump Walkway West " .. index,
		Vector3.new(hall.MinX + inset, 0, hall.Center.Z), walkwayWidth, hall.Depth - 3.5)
	deck("Level 2 Pump Walkway East " .. index,
		Vector3.new(hall.MaxX - inset, 0, hall.Center.Z), walkwayWidth, hall.Depth - 3.5)

	-- Centre island under the pump, plus a cross of walkways reaching it.
	deck("Level 2 Pump Island " .. index, Vector3.new(hall.Center.X, 0, hall.Center.Z), 26, 18)
	deck("Level 2 Pump Walkway Cross X " .. index,
		Vector3.new(hall.Center.X, 0, hall.Center.Z), hall.Width - 3.5, walkwayWidth)
	deck("Level 2 Pump Walkway Cross Z " .. index,
		Vector3.new(hall.Center.X, 0, hall.Center.Z), walkwayWidth, hall.Depth - 3.5)

	-- Supply crates ON the walkway in a corner.
	for crate = 1, rng:NextInteger(3, 5) do
		local crateSize = rng:NextNumber(2.6, 4.2)
		local box = part(parent, "Level 2 Pump Room Crate " .. index .. "." .. crate,
			CFrame.new(Vector3.new(
				hall.MinX + inset + rng:NextNumber(-2, 2),
				WALKWAY_TOP + crateSize * .5,
				hall.MinZ + inset + rng:NextNumber(-1.5, 6)))
				* CFrame.Angles(0, rng:NextNumber() * math.pi, 0),
			Vector3.new(crateSize, crateSize, crateSize), C.TileWarm, Enum.Material.WoodPlanks)
		box.CanCollide = true
	end

	-- Gauge board flush on a doorless wall stretch.
	local function clearOfDoors(list, value, clearance)
		for _, doorAt in ipairs(list) do
			if math.abs(doorAt - value) < clearance then return false end
		end
		return true
	end
	for _, candidate in ipairs({
		{list = doors.North, z = hall.MinZ + 2.1, x = hall.Center.X + 9},
		{list = doors.North, z = hall.MinZ + 2.1, x = hall.Center.X - 15},
		{list = doors.South, z = hall.MaxZ - 2.1, x = hall.Center.X + 9},
		{list = doors.South, z = hall.MaxZ - 2.1, x = hall.Center.X - 15},
	}) do
		if clearOfDoors(candidate.list, candidate.x, 22) then
			local boardPos = Vector3.new(candidate.x, 9, candidate.z)
			local board = part(parent, "Level 2 Pump Room Gauge Panel " .. index,
				CFrame.new(boardPos), Vector3.new(9, 5, .8), Color3.fromRGB(168, 176, 172),
				Enum.Material.DiamondPlate)
			board.CanCollide = false
			local inward = candidate.z > hall.Center.Z and -1 or 1
			for dial = -1, 1 do
				local gauge = part(parent, "Level 2 Pump Room Gauge " .. index .. "." .. dial,
					CFrame.new(boardPos + Vector3.new(dial * 2.8, .4, inward * .6))
						* CFrame.Angles(0, 0, math.pi * .5),
					Vector3.new(.4, 1.7, 1.7), C.Light, Enum.Material.Neon)
				gauge.Shape = Enum.PartType.Cylinder
				gauge.CanCollide = false
			end
			break
		end
	end

	-- Jumping boards over the open water quadrant, at three heights. The
	-- 45-degree yaw runs the stair along the quadrant diagonal, clear of
	-- both walkway crosses and the perimeter ring.
	if hall.Width >= 80 and hall.Depth >= 80 then
		makeDivingTower(parent, hall, depth,
			hall.Center + Vector3.new(hall.Width * .25, 0, -hall.Depth * .25),
			math.rad(45), rng, "P" .. index, {3.5, 6, 8.5})
	end

	-- Painted safety border around the pump island's edge.
	for _, stripe in ipairs({
		{Vector3.new(0, WALKWAY_TOP + .05, -8.4), Vector3.new(25, .1, 1.2)},
		{Vector3.new(0, WALKWAY_TOP + .05, 8.4), Vector3.new(25, .1, 1.2)},
		{Vector3.new(-12.4, WALKWAY_TOP + .05, 0), Vector3.new(1.2, .1, 15.6)},
		{Vector3.new(12.4, WALKWAY_TOP + .05, 0), Vector3.new(1.2, .1, 15.6)},
	}) do
		local paint = part(parent, "Level 2 Pump Room Safety Stripe " .. index,
			CFrame.new(hall.Center + stripe[1]), stripe[2],
			Color3.fromRGB(214, 170, 60), Enum.Material.SmoothPlastic)
		paint.CanCollide = false
		paint.CanTouch = false
	end
end

-- A seeded share of the plain flooded halls carry a slim raised walkway
-- hugging the room edge — a dry route around the pool. The ring is
-- CONTINUOUS corner to corner, crossing in front of every doorway (no gaps):
-- waders entering step up onto it from the corridor threshold, the corridor
-- side ledge meets it at the same height, and a submerged curb step along
-- the inner edge keeps the deck mountable from the floor of even the 2-stud
-- Deep pools. Full-depth slabs (centres underwater) keep the entity
-- navigator's support test valid.
local function makeHallEdgeWalkway(parent, hall, depth, index)
	local rng = Random.new((hall.LocalSeed or hall.Index or 1) + 37)
	if rng:NextNumber() >= (Configuration.HallEdgeWalkwayChance or 0) then
		return
	end
	local deckWidth = Configuration.HallEdgeWalkwayWidth or 3
	local curbWidth = 1.2
	-- .15 of open water between the wall face (1.75 inside the rect line) and
	-- the deck, mirroring the pump-room ring's skirting gap.
	local wallGap = 1.9
	local deckHeight = WALKWAY_TOP + depth + .3
	local curbTop = -.8
	local curbHeight = curbTop + depth + .3

	local function slab(name, alongX, alongMid, span, cross, top, height, acrossSize, color)
		local piece = tiledPart(parent, name,
			CFrame.new(alongX and Vector3.new(alongMid, top - height * .5, cross)
				or Vector3.new(cross, top - height * .5, alongMid)),
			alongX and Vector3.new(span, height, acrossSize)
				or Vector3.new(acrossSize, height, span), color,
			{Enum.NormalId.Top, Enum.NormalId.Front, Enum.NormalId.Back,
				Enum.NormalId.Left, Enum.NormalId.Right}, 7)
		piece.CanCollide = true
		piece:SetAttribute("Level2_EntityGround", true)
		return piece
	end

	for _, side in ipairs({
		{Name = "North", AlongX = true, Wall = hall.MinZ, Inward = 1},
		{Name = "South", AlongX = true, Wall = hall.MaxZ, Inward = -1},
		{Name = "West", AlongX = false, Wall = hall.MinX, Inward = 1},
		{Name = "East", AlongX = false, Wall = hall.MaxX, Inward = -1},
	}) do
		local lowLine = side.AlongX and hall.MinX or hall.MinZ
		local highLine = side.AlongX and hall.MaxX or hall.MaxZ
		-- North/south strips run corner to corner; east/west strips butt flush
		-- against them, and the curbs step inward once more, so nothing overlaps.
		local deckInset = side.AlongX and wallGap or wallGap + deckWidth
		local curbInset = wallGap + deckWidth + (side.AlongX and 0 or curbWidth)
		local deckCross = side.Wall + side.Inward * (wallGap + deckWidth * .5)
		local curbCross = side.Wall + side.Inward * (wallGap + deckWidth + curbWidth * .5)
		local a, b = lowLine + deckInset, highLine - deckInset
		slab("Level 2 Hall Edge Walkway " .. side.Name .. " " .. index,
			side.AlongX, (a + b) * .5, b - a, deckCross,
			WALKWAY_TOP, deckHeight, deckWidth, C.TileWarm)
		if curbHeight > .4 then
			local curbA, curbB = lowLine + curbInset, highLine - curbInset
			slab("Level 2 Hall Edge Walkway Curb " .. side.Name .. " " .. index,
				side.AlongX, (curbA + curbB) * .5, curbB - curbA, curbCross,
				curbTop, curbHeight, curbWidth, C.TileCool)
		end
	end
	parent:SetAttribute("Level2_EdgeWalkway", true)
end

-- A play tower kit: deck, spiral, rail and tube flume all hang off one frame
-- (origin + yaw), so the stair can never drift away from its deck again.
local function makePlayTowerKit(parent, hall, depth, origin, yaw, topY, color, name)
	local frame = CFrame.new(origin) * CFrame.Angles(0, yaw, 0)
	local function at(offset)
		return (frame * CFrame.new(offset)).Position
	end
	local deck = tiledPart(parent, name .. " Deck",
		frame * CFrame.new(0, topY - .5, 0), Vector3.new(13, 1, 13),
		C.TileWarm, Enum.NormalId:GetEnumItems(), 7)
	deck.CanCollide = true
	deck:SetAttribute("Level2_EntityGround", true)
	local stepCount = math.ceil((topY + depth) / .85)
	local stepRun, stepRise = 1.5, (topY + depth) / stepCount
	local stairBase = at(Vector3.new(-6.5 - stepCount * stepRun, -depth, 0))
	local stairDirection = at(Vector3.new(1, 0, 0)) - origin
	makeStairFlight(parent, stairBase, stairDirection, 6, stepCount,
		name .. " Steps", stepRun, stepRise)
	makeStairSideRails(parent, stairBase, stairDirection, 6, stepCount, stepRun, stepRise, name)
	makeRail(parent, at(Vector3.new(-6, topY + .1, -6.2)),
		at(Vector3.new(6, topY + .1, -6.2)), name)
	local landingHeight = 4.2 - depth + .4
	makeSlideTube(parent,
		at(Vector3.new(0, topY + 4.4, 6)),
		at(Vector3.new(0, topY + 4.4, 13.5)),
		at(Vector3.new(-2, landingHeight + 5, 17)),
		at(Vector3.new(-6, landingHeight, 26)),
		4.2, color, name .. " Slide", 32, true, .05, 12, 8)
	makeEntryTub(parent, at(Vector3.new(0, topY + 4.4, 6)),
		at(Vector3.new(0, topY + 4.4, 13.5)), 4.2, topY, color, name, true)
end

-- Water halls earn real play furniture, randomized per hall: slide kits,
-- play towers, a multi-board diving tower, a railed overlook, floats, and in
-- the largest halls a centre island. Every structure claims an anchor spot
-- AND verifies its far ends (stair foot, chute tip, flume landing) stay
-- inside the hall, away from columns and away from everything already built.
local function decorateLargeHall(parent, hall, depth, index, doors)
	if not depth or hall.Area < 12000 then return end
	local rng = Random.new((hall.LocalSeed or hall.Index or 1) + 7)
	local sign = rng:NextInteger(0, 1) == 0 and 1 or -1
	local height = hallHeight(hall)
	-- Halls that rolled an edge walkway need a wider wall margin: the deck +
	-- curb envelope reaches wallGap 1.9 + deck + curb 1.2 inside the rect
	-- lines, and extremities are validated as spine POINTS — the widest piece
	-- (overlook stair rails) can reach ~4 studs past its sample at a diagonal
	-- yaw.
	local walkwayEnvelope = 1.9 + (Configuration.HallEdgeWalkwayWidth or 3) + 1.2
	local wallMargin = parent:GetAttribute("Level2_EdgeWalkway")
		and walkwayEnvelope + 4.4 or 5

	local spots = {}
	local function pointClear(x, z, range)
		if columnNear(parent, x, z, 10) then return false end
		for _, spot in ipairs(spots) do
			if math.abs(spot.X - x) < range and math.abs(spot.Z - z) < range then
				return false
			end
		end
		return true
	end
	local function reservePoint(x, z)
		table.insert(spots, Vector3.new(x, 0, z))
	end
	-- claimSpot only CHECKS; reservation happens in fittingYaw once a yaw
	-- actually fits, so a failed structure never poisons its spot — and a
	-- structure's own origin can never veto its own far ends.
	local function claimSpot(fx, fz)
		local x, z = dodgeSkylight(hall,
			hall.Center.X + fx * hall.Width, hall.Center.Z + fz * hall.Depth, 24)
		if not x then return nil end
		if nearDoorApproach(hall, doors, x, z, 20) then return nil end
		if nearHallNavigationRoute(hall, doors, x, z, 17) then return nil end
		if not pointClear(x, z, 26) then return nil end
		return Vector3.new(x, 0, z)
	end
	local spotOptions = {
		{sign * .28, .22}, {-sign * .28, -.24}, {sign * .24, -.28}, {-sign * .22, .28},
		{sign * .31, -.03}, {-sign * .03, .31}, {-sign * .31, .03}, {sign * .03, -.31},
	}
	local nextOption = 0
	local function nextOrigin()
		for _ = 1, #spotOptions do
			nextOption = nextOption % #spotOptions + 1
			local option = spotOptions[nextOption]
			local origin = claimSpot(option[1], option[2])
			if origin then return origin end
		end
		return nil
	end
	-- Try each yaw; accept the first where EVERY listed extremity (chute tip,
	-- stair foot, board tips...) stays clear of the walls, the columns and
	-- everything already reserved — then reserve the origin and the two main
	-- extremities so later structures keep away.
	local function fittingYaw(origin, offsets)
		local base = rng:NextInteger(0, 7) * 45
		for try = 0, 7 do
			local yaw = math.rad(base + try * 45)
			local frame = CFrame.new(origin) * CFrame.Angles(0, yaw, 0)
			local fits = true
			for _, offset in ipairs(offsets) do
				-- Long reaches sample their midsection too: a column beside
				-- the MIDDLE of a chute is just as much of a collision as one
				-- at its tip.
				local samples = offset.Magnitude > 14 and {.45, .75, 1} or {1}
				for _, fraction in ipairs(samples) do
					local point = (frame * CFrame.new(offset * fraction)).Position
					-- The origin was door-safe, but a long chute or stair could rotate
					-- its FAR END straight across that same doorway. Seed 303's Diving
					-- Well did exactly that: the slide kit plus its flanking columns
					-- sealed the east exit for the Slidemouth. Every sampled spine
					-- point must preserve the full-scale body's doorway approach too,
					-- not merely remain inside the hall.
					if nearDoorApproach(hall, doors, point.X, point.Z, 22)
						or nearHallNavigationRoute(hall, doors, point.X, point.Z, 17)
						or not pointClear(point.X, point.Z, 16)
						or math.abs(point.X - hall.Center.X) > hall.Width * .5 - wallMargin
						or math.abs(point.Z - hall.Center.Z) > hall.Depth * .5 - wallMargin then
						fits = false
						break
					end
				end
				if not fits then break end
			end
			if fits then
				reservePoint(origin.X, origin.Z)
				for offsetIndex = 1, math.min(2, #offsets) do
					local point = (frame * CFrame.new(offsets[offsetIndex])).Position
					reservePoint(point.X, point.Z)
				end
				return yaw
			end
		end
		return nil
	end

	-- Diving tower with boards at several heights. It claims FIRST — it is
	-- the signature piece — and its height scales with the room so the back
	-- stair always has space to land.
	if hall.Area >= 15000 then
		local origin = nextOrigin()
		if origin then
			local boardHeights = {4.5, 7.5, 10.5}
			if hall.Area >= 34000 and rng:NextNumber() < .5 then
				table.insert(boardHeights, 13.5)
			end
			local stepCount = math.ceil((boardHeights[#boardHeights] + depth) / .9)
			local yaw = fittingYaw(origin, {
				Vector3.new(10, 0, 0),
				Vector3.new(-(5 + stepCount * 1.25), 0, 0),
				Vector3.new(-8, 0, 12.5),
				Vector3.new(-8, 0, -12.5),
			})
			if yaw then
				makeDivingTower(parent, hall, depth, origin, yaw, rng, index, boardHeights)
				parent:SetAttribute("Level2_DivingOutcome", "built")
			else
				parent:SetAttribute("Level2_DivingOutcome", "no-yaw")
			end
		else
			parent:SetAttribute("Level2_DivingOutcome", "no-origin")
		end
	else
		parent:SetAttribute("Level2_DivingOutcome", "small " .. math.floor(hall.Area or 0))
	end

	-- Slide kits: count, yaw, height, run and colour all vary per hall.
	local kitCount = math.clamp(math.floor(hall.Area / 13000), 1, 4)
	for kit = 1, kitCount do
		local origin = nextOrigin()
		if origin then
			local padTop = rng:NextNumber(4.5, math.min(8, 4.5 + hall.Area / 16000))
			local chuteRun = rng:NextNumber(12, 18)
			local stepCount = math.ceil((padTop + depth) / .75)
			local yaw = fittingYaw(origin, {
				Vector3.new(6 + chuteRun, 0, 0),
				Vector3.new(-(5 + stepCount * 1.5), 0, 0),
			})
			if yaw then
				makeSlideKit(parent, hall, depth, origin, yaw, padTop, chuteRun,
					BOARD_COLORS[rng:NextInteger(1, #BOARD_COLORS)], index .. "." .. kit)
			end
		end
	end

	-- Play tower with a tube flume; the biggest halls get a pair.
	if hall.Area >= 26000 then
		local towerCount = hall.Area >= 52000 and 2 or 1
		for tower = 1, towerCount do
			local origin = nextOrigin()
			if origin then
				local towerTop = math.min(rng:NextNumber(10, 14), height - 9)
				local towerSteps = math.ceil((towerTop + depth) / .85)
				local yaw = fittingYaw(origin, {
					Vector3.new(-6, 0, 27),
					Vector3.new(-(8 + towerSteps * 1.5), 0, 0),
				})
				if yaw then
					local color = Configuration.SlideColors[
						(((tonumber(index) or 1) + tower) % #Configuration.SlideColors) + 1]
					makePlayTowerKit(parent, hall, depth, origin, yaw, towerTop, color,
						"Level 2 Play Tower " .. index .. "." .. tower)
				end
			end
		end
	end

	-- Railed stair overlook.
	if hall.Area >= 28000 then
		local origin = nextOrigin()
		if origin then
			local landingTop = 7
			local stepCount = math.ceil((landingTop + depth) / .78)
			local stepRun, stepRise = 1.5, (landingTop + depth) / stepCount
			local yaw = fittingYaw(origin, {
				Vector3.new(8, 0, 0),
				Vector3.new(-(6 + stepCount * stepRun), 0, 0),
			})
			if yaw then
				local frame = CFrame.new(origin) * CFrame.Angles(0, yaw, 0)
				local function at(offset)
					return (frame * CFrame.new(offset)).Position
				end
				local stairBase = at(Vector3.new(-6 - stepCount * stepRun, -depth, 0))
				local stairDirection = at(Vector3.new(1, 0, 0)) - origin
				makeStairFlight(parent, stairBase, stairDirection, 10, stepCount,
					"Level 2 Overlook Steps " .. index, stepRun, stepRise)
				makeStairSideRails(parent, stairBase, stairDirection, 10, stepCount,
					stepRun, stepRise, "Level 2 Overlook " .. index)
				local landing = tiledPart(parent, "Level 2 Overlook Landing " .. index,
					frame * CFrame.new(0, landingTop - .5, 0), Vector3.new(12, 1, 10),
					C.TileWarm, Enum.NormalId:GetEnumItems(), 7)
				landing.CanCollide = true
				landing:SetAttribute("Level2_EntityGround", true)
				makeRail(parent, at(Vector3.new(6, landingTop, -5)),
					at(Vector3.new(6, landingTop, 5)), "Level 2 Overlook " .. index)
				makeRail(parent, at(Vector3.new(-6, landingTop, 5)),
					at(Vector3.new(6, landingTop, 5)), "Level 2 Overlook Back " .. index)
			end
		end
	end

	-- Rings and rafts adrift on the water: real floating objects, pushed
	-- around by anyone wading into them — spawned only in open water.
	local floatCount = math.clamp(math.floor(hall.Area / 6500), 4, 12)
	for float = 1, floatCount do
		local floatColor = Configuration.SlideColors[rng:NextInteger(1, #Configuration.SlideColors)]
		if float % 3 == 0 then
			local spot = freeWaterSpot(hall, rng, Vector3.new(7.2, 1.5, 7.2))
			if spot then
				local raft = part(parent, "Level 2 Pool Raft " .. index .. "." .. float,
					CFrame.new(spot + Vector3.new(0, .5, 0))
						* CFrame.Angles(0, rng:NextNumber() * math.pi, 0),
					Vector3.new(4, .7, 7.2), floatColor, Enum.Material.SmoothPlastic)
				makeBuoyant(raft, .24)
			end
		else
			local spot = freeWaterSpot(hall, rng, Vector3.new(6.4, 2, 6.4))
			if spot then
				local ring = part(parent, "Level 2 Pool Float Ring " .. index .. "." .. float,
					CFrame.new(spot + Vector3.new(0, .5, 0)) * CFrame.Angles(0, 0, math.pi * .5),
					Vector3.new(.9, 6.4, 6.4), floatColor, Enum.Material.SmoothPlastic)
				ring.Shape = Enum.PartType.Cylinder
				makeBuoyant(ring, .28)
			end
		end
	end

	-- The biggest halls also get a centre island with twin columns.
	if hall.Area >= 48000 then
		local island = tiledPart(parent, "Level 2 Pool Island " .. index,
			CFrame.new(hall.Center + Vector3.new(0, .35, 0)) * CFrame.Angles(0, 0, math.pi * .5),
			Vector3.new(1.3, 19, 19), C.TileWarm, nil, 8)
		island.Shape = Enum.PartType.Cylinder
		island.CanCollide = true
		-- These optional twins belong to the 19-stud island as a rigid assembly;
		-- relocating either one independently can leave its base hanging in the
		-- water. Skip only the conflicting twin instead.
		local islandColumnAX, islandColumnAZ = hall.Center.X + 4, hall.Center.Z
		local islandColumnBX, islandColumnBZ = hall.Center.X - 4, hall.Center.Z
		if not overlapsSkylight(hall, islandColumnAX, islandColumnAZ, 11) then
			makeColumn(parent,
				Vector3.new(islandColumnAX, hall.Center.Y, islandColumnAZ), height, 4.5,
				false, hiddenColumnSeamYaw(hall, islandColumnAX, islandColumnAZ))
		end
		if not overlapsSkylight(hall, islandColumnBX, islandColumnBZ, 11) then
			makeColumn(parent,
				Vector3.new(islandColumnBX, hall.Center.Y, islandColumnBZ), height, 4.5,
				false, hiddenColumnSeamYaw(hall, islandColumnBX, islandColumnBZ))
		end
	end
end

-- ── arrival ─────────────────────────────────────────────────────────────────

local function makeArrivalConcourse(parent, hall, roomDirection)
	local center = hall.Center
	local arrivalFolder = folder(parent, "Level 2 Arrival Concourse")
	roomDirection = roomDirection or Vector3.new(0, 0, 1)
	local sideDirection = Vector3.new(-roomDirection.Z, 0, roomDirection.X)

	-- Players now arrive beside the rear transfer gate on the ordinary tiled
	-- floor. The raised neon display, its two stair flights, and their lights
	-- only cluttered the middle of the room and no longer served a spawn role.
	local platformHeight = 0

	-- Paired piers and lintels give the oversized arrival room a deliberate
	-- procession while preserving a forty-stud clear route into the level.
	local arrivalHeight = hallHeight(hall)
	for frameIndex, distance in ipairs({26, 58, 90}) do
		local frameCenter = center + roomDirection * distance
		if frameCenter.X > hall.MinX + 28 and frameCenter.X < hall.MaxX - 28
			and frameCenter.Z > hall.MinZ + 28 and frameCenter.Z < hall.MaxZ - 28 then
			for sideIndex, sideSign in ipairs({-1, 1}) do
				local pierPosition = frameCenter + sideDirection * sideSign * 22
					+ Vector3.new(0, (arrivalHeight - 4) * .5, 0)
				local pier = part(arrivalFolder,
					string.format("Level 2 Arrival Scale Frame %d Pier %d", frameIndex, sideIndex),
					CFrame.new(pierPosition), Vector3.new(4, arrivalHeight - 4, 4),
					C.TileCool, Enum.Material.CeramicTiles)
				pier.CanCollide = true
				pier.CanTouch = false
				pier.CanQuery = true
			end
			local lintelPosition = frameCenter + Vector3.new(0, arrivalHeight - 6, 0)
			local lintel = part(arrivalFolder,
				"Level 2 Arrival Scale Frame " .. frameIndex .. " Lintel",
				CFrame.lookAt(lintelPosition, lintelPosition + roomDirection),
				Vector3.new(48, 3, 4), C.TileWarm, Enum.Material.CeramicTiles)
			lintel.CanCollide = false
			lintel.CanTouch = false
			lintel.CanQuery = false
		end
	end

	-- Mount the return gate on the REAL tiled rear hall wall.  The previous
	-- fixed 8.2-stud offset built a plain full-width partition through the middle
	-- of every arrival room and left a large inaccessible cavity behind it.
	local rearHalfSpan = math.abs(roomDirection.X) > 0 and hall.Width * .5 or hall.Depth * .5
	local back = center - roomDirection
		* (rearHalfSpan - Configuration.WallThickness * .5 - .05)
	-- Spawn on the dry hall floor just in front of the gate, facing into the
	-- Poolrooms. This keeps the full arrival room usable instead of dropping
	-- players on the unrelated raised centre display.
	local arrivalSpawnPosition = back + roomDirection * 5.5
	local gateFolder = folder(arrivalFolder, "Level 2 Energy Transfer Gate")
	local gateCenter = back + Vector3.new(0, 4.2, 0)
	local gateFacing = CFrame.lookAt(gateCenter, gateCenter + roomDirection)
	local function gatePart(name, localOffset, size, color, material, transparency)
		local object = part(gateFolder, name, gateFacing * CFrame.new(localOffset), size, color, material, transparency or 0)
		object.CanCollide = false
		object.CanTouch = false
		object.CanQuery = false
		object:SetAttribute("Level2_StoryOnly", true)
		return object
	end
	local frame = Color3.fromRGB(20, 28, 25)
	local field = Color3.fromRGB(20, 60, 35)
	local trim = Color3.fromRGB(12, 28, 20)
	local warningRed = Color3.fromRGB(255, 34, 24)
	gatePart("PostL", Vector3.new(-3.75, 2, -.5), Vector3.new(1.05, 12.5, 1.25), frame, Enum.Material.Metal)
	gatePart("PostR", Vector3.new(3.75, 2, -.5), Vector3.new(1.05, 12.5, 1.25), frame, Enum.Material.Metal)
	gatePart("Top", Vector3.new(0, 8.15, -.5), Vector3.new(8.55, 1.15, 1.25), frame, Enum.Material.Metal)
	local energyField = gatePart("Energy Field", Vector3.new(0, 2, -.75), Vector3.new(7, 11, .4), field, Enum.Material.Neon)
	for _, y in ipairs({-1.0, 2.0, 5.0}) do
		gatePart("Reinforcement", Vector3.new(0, y, -1.02), Vector3.new(7.05, .16, .16), trim, Enum.Material.Metal)
	end
	gatePart("CenterSeam", Vector3.new(0, 2, -1.03), Vector3.new(.14, 10.8, .18), trim, Enum.Material.Metal)
	for _, x in ipairs({-3.25, 3.25}) do
		for _, y in ipairs({-1.5, 1.5, 4.5}) do
			local node = gatePart("EnergyNode", Vector3.new(x, y, -1.08), Vector3.new(.45, .85, .28), warningRed, Enum.Material.Neon)
			local glow = Instance.new("PointLight")
			glow.Name = "Energy Node Glow"
			glow.Color = warningRed
			glow.Brightness = .315
			glow.Range = 4
			glow.Shadows = true
			glow.Parent = node
		end
	end
	local header = gatePart("Energy Transfer Header", Vector3.new(0, 7.55, -1.15), Vector3.new(6.4, .72, .2), frame, Enum.Material.Metal)
	local headerGui = Instance.new("SurfaceGui")
	headerGui.Name = "EnergyTransferLabel"
	headerGui.Face = Enum.NormalId.Front
	headerGui.CanvasSize = Vector2.new(520, 70)
	headerGui.LightInfluence = 0
	headerGui.Parent = header
	local headerText = Instance.new("TextLabel")
	headerText.Size = UDim2.fromScale(1, 1)
	headerText.BackgroundTransparency = 1
	headerText.Font = Enum.Font.Code
	headerText.Text = "ANOMALOUS SPACE HAS BEEN LOST"
	headerText.TextColor3 = Color3.fromRGB(90, 255, 135)
	headerText.TextScaled = true
	headerText.Parent = headerGui
	local status = gatePart("Return Lock Status", Vector3.new(0, 6.7, -1.15), Vector3.new(6.4, .38, .18), frame, Enum.Material.Metal)
	local statusGui = Instance.new("SurfaceGui")
	statusGui.Name = "ReturnLockLabel"
	statusGui.Face = Enum.NormalId.Front
	statusGui.CanvasSize = Vector2.new(520, 38)
	statusGui.LightInfluence = 0
	statusGui.Parent = status
	local statusText = Instance.new("TextLabel")
	statusText.Size = UDim2.fromScale(1, 1)
	statusText.BackgroundTransparency = 1
	statusText.Font = Enum.Font.Code
	statusText.Text = "ENTRY LOCKED"
	statusText.TextColor3 = Color3.fromRGB(165, 180, 168)
	statusText.TextScaled = true
	statusText.Parent = statusGui
	energyField:SetAttribute("Level2_StoryOnly", true)
	return platformHeight, roomDirection, arrivalSpawnPosition
end

local function makeCompatibilityArrival(world, arrivalPosition, platformHeight, roomDirection, spawnPosition)
	local topY = platformHeight or 0
	roomDirection = roomDirection or Vector3.new(0, 0, 1)
	spawnPosition = spawnPosition or arrivalPosition - roomDirection * 2
	local floorSpawnPosition = Vector3.new(
		spawnPosition.X, arrivalPosition.Y + .1, spawnPosition.Z)
	local spawnCFrame = CFrame.lookAt(floorSpawnPosition,
		floorSpawnPosition + roomDirection, Vector3.yAxis)

	local marker = part(world, "Level 2 Arrival Spawn",
		spawnCFrame * CFrame.new(0, .2, 0), Vector3.new(9, .4, 9),
		C.Emergency, Enum.Material.Neon, 1)
	marker.CanCollide = false
	marker.CanTouch = false
	marker.CanQuery = false

	local elevator = Instance.new("Model")
	elevator.Name = "Elevator"
	elevator:SetAttribute("Level2_CompatibilityMarker", true)
	elevator.Parent = workspace
	local shell = part(elevator, "Level 2 Arrival Elevator Shell",
		CFrame.new(arrivalPosition + Vector3.new(0, topY + 5, 0)), Vector3.new(18, 10, 18),
		C.TileWarm, Enum.Material.SmoothPlastic, 1)
	shell.CanCollide = false
	shell.CanTouch = false
	shell.CanQuery = false
	local doorLeft = part(elevator, "DoorL",
		CFrame.new(arrivalPosition + Vector3.new(-4.5, topY + 5, 8.8)), Vector3.new(8.5, 10, .6),
		C.Metal, Enum.Material.Metal, 1)
	local doorRight = part(elevator, "DoorR",
		CFrame.new(arrivalPosition + Vector3.new(4.5, topY + 5, 8.8)), Vector3.new(8.5, 10, .6),
		C.Metal, Enum.Material.Metal, 1)
	doorLeft.CanCollide, doorRight.CanCollide = false, false
	doorLeft.CanTouch, doorRight.CanTouch = false, false
	doorLeft.CanQuery, doorRight.CanQuery = false, false
	elevator.PrimaryPart = shell

	local function compatibilityMarker(name, position, size)
		local object = part(workspace, name, CFrame.new(position), size, C.Emergency,
			Enum.Material.Neon, 1)
		object.CanCollide = false
		object.CanTouch = false
		object.CanQuery = false
		object:SetAttribute("Level2_CompatibilityMarker", true)
		return object
	end

	local mazeStart = compatibilityMarker("MazeStart",
		arrivalPosition + Vector3.new(0, topY + .2, 0), Vector3.new(4, .2, 4))
	local elevatorSpawn = compatibilityMarker("ElevatorSpawn",
		floorSpawnPosition, Vector3.new(7, .2, 7))
	elevatorSpawn.CFrame = spawnCFrame
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
	-- These five are GLOBAL Terrain properties, not Level 2's own. Level 2 has
	-- always set them and never given them back, so every other level and the
	-- lobby inherited the poolrooms' water look for the rest of the session --
	-- the first round of Level 2 permanently restyled the whole place.
	--
	-- Capture what was there BEFORE overwriting, and hand it to the manifest so
	-- Adapter.Cleanup can put it back. Captured every Build (not once at load)
	-- because a rebuild after a cleanup must capture the RESTORED values, not
	-- Level 2's own.
	local previousWater = {
		WaterColor = Terrain.WaterColor,
		WaterTransparency = Terrain.WaterTransparency,
		WaterReflectance = Terrain.WaterReflectance,
		WaterWaveSize = Terrain.WaterWaveSize,
		WaterWaveSpeed = Terrain.WaterWaveSpeed,
	}
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
	local objectiveFolder = folder(world, "Level 2 Objectives")
	local doorFolder = folder(objectiveFolder, "Level 2 Pressure Doors")
	local lightingFolder = folder(world, "Level 2 Lighting")
	local navigationFolder = folder(world, "Level 2 Navigation")
	local entityFolder = folder(world, "Level 2 Entity Nodes")

	local waterRegions = {}
	waterRegionsRef = waterRegions

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

	-- Resolve Spiral eligibility before hall names, ceilings, lighting and
	-- dressing read Archetype. An unsuitable roll becomes a deterministic
	-- Porthole Hall; this keeps the generator total and preserves the full-size
	-- stair contract for every hall that actually advertises one.
	local spiralPlacements = {}
	local spiralRolls, spiralRerouted = 0, 0
	for _, hall in ipairs(layout.Halls) do
		if hall.Archetype == "Spiral Stair Well" then
			spiralRolls += 1
			local center, radius, structureRadius =
				spiralStairPlacement(hall, doorsByHall[hall.Index])
			if center then
				spiralPlacements[hall.Index] = {
					Center = center,
					Radius = radius,
					StructureRadius = structureRadius,
				}
				hall.SpiralCenter = center
				hall.SpiralRadius = radius
				hall.SpiralStructureRadius = structureRadius
			else
				spiralRerouted += 1
				hall.Archetype = "Porthole Hall"
				hall.SpiralRerouted = true
			end
		end
	end
	world:SetAttribute("Level2_SpiralRolls", spiralRolls)
	world:SetAttribute("Level2_SpiralsBuilt", spiralRolls - spiralRerouted)
	world:SetAttribute("Level2_SpiralsRerouted", spiralRerouted)

	local slideDecks = {}
	local exit
	local hallDepths = {}
	local built = 0
	local kidsPumpIndex = layout.PumpHalls[1] and layout.PumpHalls[1].KidsIndex or -1

	for _, hall in ipairs(layout.Halls) do
		local hallModel = Instance.new("Model")
		hallModel.Name = hall.Id .. " " .. (hall.Archetype or "Hall")
		hallModel:SetAttribute("Level2_Role", hall.Role)
		hallModel:SetAttribute("Level2_PoolType", hall.PoolType)
		hallModel:SetAttribute("Level2_Archetype", hall.Archetype)
		hallModel:SetAttribute("Level2_GraphDepth", hall.GraphDepth)
		hallModel:SetAttribute("Level2_Height", hallHeight(hall))
		hallModel:SetAttribute("Level2_FloorY", hallFloorY(hall))
		hallModel:SetAttribute("Level2_PumpIndex", hall.PumpIndex or 0)
		if hall.KidsColorIndex then
			hallModel:SetAttribute("Level2_KidsColor", kidsPalette(hall).Name)
		end
		hallModel.Parent = hallsFolder

		local depth = makeHallFloor(hallModel, hall)
		hallDepths[hall.Index] = depth
		makeHallCeiling(hallModel, hall)

		if hall.Role == "Kids Area" then
			local _, poolFoamSpawnPosition = makeKidsHall(kidsFolder, hall,
				hall.KidsIndex or hall.Index, doorsByHall[hall.Index], kidsPumpIndex)
			local poolFoamSpawn = part(entityFolder,
				"Level 2 Pool Foam Spawn " .. hall.Index,
				CFrame.new(poolFoamSpawnPosition + Vector3.new(0, 2, 0)),
				Vector3.new(1.5, .2, 1.5), C.Emergency, Enum.Material.Neon, 1)
			poolFoamSpawn.CanCollide = false
			poolFoamSpawn.CanTouch = false
			poolFoamSpawn.CanQuery = false
			poolFoamSpawn:SetAttribute("Level2_HallId", hall.Id)
			poolFoamSpawn:SetAttribute("Level2_HallIndex", hall.Index)
			poolFoamSpawn:SetAttribute("Level2_KidsIndex", hall.KidsIndex or 0)
			poolFoamSpawn:SetAttribute("Level2_PoolFoamSpawn", true)
		elseif hall.Role == "Slide Hall" then
			slideDecks[hall.SlideHallIndex] = makeSlideHall(slideFolder, hall,
				hall.SlideHallIndex, doorsByHall[hall.Index])
			dressHall(hallModel, hall, hallWaterDepth(hall), doorsByHall[hall.Index], hall.Index, .6)
			if hall.IsGrand then
				exit = makeExitFlume(geometry, layout, hall, slideDecks[hall.SlideHallIndex])
			end
		else
			local archetype = hall.Archetype or ""
			local height = hallHeight(hall)
			if archetype == "Pillar Basin" or archetype == "Diving Well" then
				makeColonnade(hallModel, hall, depth, {-.6, .6}, doorsByHall[hall.Index])
			elseif archetype == "Column Forest" then
				makeColonnade(hallModel, hall, depth, {-.62, 0, .62}, doorsByHall[hall.Index])
			elseif archetype == "Curved Gallery" then
				makeColonnade(hallModel, hall, depth, {-.56}, doorsByHall[hall.Index])
			elseif archetype == "Flooded Gallery" then
				makeColonnade(hallModel, hall, depth, {-.64, .64}, doorsByHall[hall.Index])
			elseif archetype == "Arch Tunnel" then
				-- A room-crossing vault tube read as a giant pipe dropped into the
				-- hall; the vault belongs to real corridors only. These halls are
				-- ordinary flooded galleries now, and the large-hall decoration
				-- pass below gives them their set pieces.
				makeColonnade(hallModel, hall, depth, {-.58, .58}, doorsByHall[hall.Index])
			elseif archetype == "Ring Corridor" then
				local acrossZ = hall.Width >= hall.Depth
				local along = acrossZ and hall.Width or hall.Depth
				local rings = math.clamp(math.floor(along / 38), 3, 7)
				local maximumDoorRadius = math.min(
					Configuration.DoorWidth * .5 - 2,
					Configuration.DoorHeight - 2
				)
				local radius = math.min(
					(acrossZ and hall.Depth or hall.Width) * .5 - 6,
					height - 5,
					maximumDoorRadius
				)
				for ring = 1, rings do
					local t = ring / (rings + 1)
					local position = acrossZ
						and Vector3.new(hall.MinX + along * t, 0, hall.Center.Z)
						or Vector3.new(hall.Center.X, 0, hall.MinZ + along * t)
					makeArchSpan(hallModel, position, acrossZ, hall.Index .. "." .. ring, radius, depth or 0)
				end
			elseif archetype == "Pump Station" then
				decoratePumpHall(hallModel, hall, hall.Index, doorsByHall[hall.Index])
			elseif archetype == "Spiral Stair Well" then
				local placement = assert(spiralPlacements[hall.Index],
					"retained Spiral Stair Well has no proven placement")
				local spiralCenter = placement.Center
				local spiralRadius = placement.Radius
				hallModel:SetAttribute("Level2_SpiralOffsetX", spiralCenter.X - hall.Center.X)
				hallModel:SetAttribute("Level2_SpiralOffsetZ", spiralCenter.Z - hall.Center.Z)
				hallModel:SetAttribute("Level2_SpiralRadius", spiralRadius)
				makeSpiralStair(hallModel, spiralCenter, -(depth or 1) + .5, height - 12, spiralRadius,
					"Level 2 Stair Well " .. hall.Index)
			elseif archetype == "Skylight Hall" then
				-- The real skylight slots already daylight this hall; add columns.
				makeColonnade(hallModel, hall, depth, {-.5, .5}, doorsByHall[hall.Index])
			elseif archetype == "Porthole Hall" then
				for step = -1, 1 do
					local offset = Vector3.new(step * math.min(30, hall.Width * .25), 9, -hall.Depth * .5 + 3)
					-- Skip panes that would hang over a doorway on this wall.
					local paneX = hall.Center.X + offset.X
					local blocked = false
					for _, doorAt in ipairs(doorsByHall[hall.Index].North) do
						if math.abs(doorAt - paneX) < Configuration.DoorWidth * .5 + 7 then
							blocked = true
							break
						end
					end
					if blocked then continue end
					local pane = part(hallModel, "Level 2 Porthole " .. hall.Index .. " " .. step,
						CFrame.new(hall.Center + offset), Vector3.new(10, 15, .6), C.Light,
						Enum.Material.Neon, .1)
					pane.CanCollide = false
					local light = Instance.new("SurfaceLight")
					light.Face = Enum.NormalId.Back
					light.Color = C.Light
					light.Brightness = .49
					light.Range = 26
					light.Angle = 110
					light.Shadows = true
					light.Parent = pane
				end
			end

			-- Edge walkways go in BEFORE the decoration passes so their spot
			-- probes and float spawns see the decks. Pump stations already
			-- carry their own wider service ring.
			if depth and archetype ~= "Pump Station" then
				makeHallEdgeWalkway(hallModel, hall, depth, hall.Index)
			end

			if archetype ~= "Ring Corridor" and archetype ~= "Pump Station" then
				decorateLargeHall(hallModel, hall, depth, hall.Index, doorsByHall[hall.Index])
			end
			dressHall(hallModel, hall, depth, doorsByHall[hall.Index], hall.Index, 1)

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
			CFrame.new(hall.Center + Vector3.new(0, hallFloorY(hall) + 1, 0)), Vector3.new(2, .2, 2),
			C.Emergency, Enum.Material.Neon, 1)
		node.CanCollide = false
		node.CanTouch = false
		node.CanQuery = false
		node.CastShadow = false
		node:SetAttribute("Level2_HallId", hall.Id)
		node:SetAttribute("Level2_Role", hall.Role)

		for corner, sign in ipairs({
			Vector3.new(-.32, 0, -.32), Vector3.new(.32, 0, -.32),
			Vector3.new(-.32, 0, .32), Vector3.new(.32, 0, .32),
		}) do
			local patrol = part(entityFolder, "Level 2 Entity Patrol Node " .. hall.Index .. "." .. corner,
				CFrame.new(hall.Center + Vector3.new(
					sign.X * hall.Width, hallFloorY(hall) + 2, sign.Z * hall.Depth)),
				Vector3.new(1.5, .2, 1.5), C.Emergency, Enum.Material.Neon, 1)
			patrol.CanCollide = false
			patrol.CanTouch = false
			patrol.CanQuery = false
			patrol.CastShadow = false
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
	for corridorBuildIndex, corridor in ipairs(layout.Corridors) do
		local record = makeCorridor(corridorsFolder, layout, corridor, doorFolder)
		if record then
			corridorRecords[corridor.Index] = record
			if corridor.DrainGroup then drains[corridor.DrainGroup] = record end
			if record.Door then table.insert(pressureDoors, record) end
		end
		if corridorBuildIndex % 2 == 0 then task.wait() end
	end
	task.wait()

	local pumps = {}
	local leverHandleColors = shuffledLeverHandleColors(layout.Seed, generation)
	for index, hall in ipairs(layout.PumpHalls) do
		pumps[index] = makePumpStation(objectiveFolder, hall, index, leverHandleColors[index])
		pumps[index].Hall = hall
	end

	local roomDirection = Vector3.new(0, 0, 1)
	for _, corridor in ipairs(layout.Corridors) do
		if corridor.A == layout.Arrival.Index or corridor.B == layout.Arrival.Index then
			local otherIndex = corridor.A == layout.Arrival.Index and corridor.B or corridor.A
			local other = layout.Halls[otherIndex]
			if other and other.Center then
				local delta = other.Center - layout.Arrival.Center
				if math.abs(delta.X) >= math.abs(delta.Z) then
					roomDirection = Vector3.new(delta.X >= 0 and 1 or -1, 0, 0)
				else
					roomDirection = Vector3.new(0, 0, delta.Z >= 0 and 1 or -1)
				end
				break
			end
		end
	end
	local platformHeight, resolvedRoomDirection, spawnPosition = makeArrivalConcourse(geometry, layout.Arrival, roomDirection)
	local arrival = makeCompatibilityArrival(world, layout.Arrival.Center, platformHeight, resolvedRoomDirection, spawnPosition)

	-- Generic navigation anchors only. The World Builder never spawns hostiles.
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

	local terrainCenter = Vector3.new(worldCenterX, -16, worldCenterZ)
	local terrainSize = Vector3.new(extent + 700, 200, extent + 700)
	world:SetAttribute("Level2_TerrainCenter", terrainCenter)
	world:SetAttribute("Level2_TerrainSize", terrainSize)
	world:SetAttribute("Level2_HallCount", #layout.Halls)
	world:SetAttribute("Level2_CorridorCount", #layout.Corridors)
	world:SetAttribute("Level2_KidsRoomCount", #(layout.KidsArea or {}))
	world:SetAttribute("Level2_SlideHallCount", #(layout.SlideHalls or {}))

	waterRegionsRef = nil

	-- No roof is ever navigable. PassThrough must remain false: true tells
	-- PathfindingService that an otherwise solid part may be traversed. The
	-- navigator assigns this label an infinite cost and also rejects these
	-- surfaces during its independent floor validation.
	for _, descendant in ipairs(world:GetDescendants()) do
		if descendant:IsA("BasePart") and (descendant.Name:find("Ceiling", 1, true)
			or descendant.Name:find("Skylight", 1, true)
			or descendant.Name:find("Roof", 1, true)) then
			descendant:SetAttribute("Level2_NoEntityGround", true)
			local modifier = Instance.new("PathfindingModifier")
			modifier.Label = "Level2Roof"
			modifier.PassThrough = false
			modifier.Parent = descendant
		end
	end

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
		-- The per-hall centre nodes. They were built and named for entity use
		-- from the start but never reachable from the manifest, so no consumer
		-- could ever see them.
		Navigation = navigationFolder,
		WaterRegions = waterRegions,
		-- What the global Terrain water looked like before this build touched it.
		PreviousWaterAppearance = previousWater,
		TerrainCenter = terrainCenter,
		TerrainSize = terrainSize,
		Generation = generation,
	}
end

return WorldBuilder
