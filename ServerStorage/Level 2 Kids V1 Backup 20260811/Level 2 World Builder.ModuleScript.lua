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
local ServerStorage = game:GetService("ServerStorage")
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

local LEVEL2_KIDS_TILE_TEXTURE_SLOTS = {
	Sun = "Level 2 Kids Sun Tile Texture",
	Coral = "Level 2 Kids Coral Tile Texture",
	Lagoon = "Level 2 Kids Lagoon Tile Texture",
}
local LEVEL2_KIDS_TILE_STUDS = 24

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
		texture:SetAttribute("Level2_KidsPalette", palette.Name)
		texture.Parent = object
	end
	return object
end

local function surfaceFor(hall, parent, name, cframe, size, tileColor, faces, studs)
	if isKids(hall) then
		local object = part(parent, name, cframe, size,
			tileColor or kidsPalette(hall).Color, Enum.Material.SmoothPlastic)
		return addKidsTileTexture(object, hall, faces)
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

local function availableKidsRoundSkylightVariants(hall)
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
	fill.Shadows = false
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

-- Ceilings carry real skylight openings with non-shadow-casting safety glass.
-- Kids rooms use baked circular modules so their geometry replicates reliably.
local function makeHallCeiling(parent, hall)
	local height = hallHeight(hall)
	local color = isKids(hall) and kidsPalette(hall).Accent or C.TileCool
	if isKids(hall) then
		makeKidsRoundSkylightCeiling(parent, hall)
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
local function makeRaisedPool(parent, center, width, depth3, hall)
	local palette = kidsPalette(hall)
	local wallHeight = 2.4
	local shellBottom = part(parent, "Level 2 Kids Pool Base",
		CFrame.new(center + Vector3.new(0, .15, 0)), Vector3.new(width, .3, depth3),
		palette.Accent, Enum.Material.SmoothPlastic)
	addKidsTileTexture(shellBottom, hall, {Enum.NormalId.Top})
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
		palette.Accent, Enum.Material.SmoothPlastic)
	addKidsTileTexture(poolStep, hall, {Enum.NormalId.Top, Enum.NormalId.Front, Enum.NormalId.Back})
	poolStep.CanCollide = true
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

local function makeStairFlight(parent, base, direction, width, steps, name, run, rise, surfaceHall)
	direction = direction.Unit
	run = run or 2.3
	rise = rise or .78
	for index = 1, steps do
		local height = index * rise
		local center = base + direction * ((index - .5) * run) + Vector3.new(0, height * .5, 0)
		local stair
		if isKids(surfaceHall) then
			stair = surfaceFor(surfaceHall, parent, name .. " Step " .. index,
				CFrame.lookAt(center, center + direction), Vector3.new(width, height, run + .12), C.TileWarm,
				{Enum.NormalId.Top, Enum.NormalId.Front, Enum.NormalId.Back}, 7)
		else
			stair = tiledPart(parent, name .. " Step " .. index,
				CFrame.lookAt(center, center + direction), Vector3.new(width, height, run + .12), C.TileWarm,
				{Enum.NormalId.Top, Enum.NormalId.Front, Enum.NormalId.Back}, 7)
		end
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
	-- Kids rooms have their own varied round skylights; the rectangular panels
	-- remain only in enclosed corridors and gateway spaces.
	if isKids(hall) or #skylightSlotsFor(hall) > 0 then return end
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

-- The old panel tube remains as a no-asset fallback. Normal Level 2
-- generation uses the authored 24-sided open shell and 32-sided closed shell below.
local function makeLegacyTubeFromPoints(parent, points, radius, color, name, openTop)
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
					panel.CustomPhysicalProperties = PhysicalProperties.new(.7, .05, .05, 1, 1)
					panel.CanCollide = true
				end
			end
		end
	end
end

local function slideTemplate(openTop)
	if Configuration.SlideUseMeshTemplates == false then return nil end
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

local function makeSlideCollisionPart(parent, name, base, offset, size)
	local collision = part(parent, name, base * CFrame.new(offset), size,
		Color3.fromRGB(255, 255, 255), Enum.Material.SmoothPlastic, 1)
	collision.CanCollide = true
	collision.CanTouch = false
	collision.CanQuery = true
	collision.CastShadow = false
	collision.CustomPhysicalProperties = PhysicalProperties.new(
		.7, Configuration.SlideCollisionFriction or .05, .05, 1, 1)
	collision:SetAttribute("Level2_SlideCollision", true)
	return collision
end

-- Tube from an ordered point list — shared by flumes, the exit slide and the
-- helix slides. The visible shell is smooth and lightly glossy; simple hidden
-- collision strips preserve the old slide physics without making the player
-- bump over the visible segment seams.
local function makeTubeFromPoints(parent, points, radius, color, name, openTop, visualOverlap, collisionPoints)
	local tubeModel = Instance.new("Model")
	tubeModel.Name = name
	tubeModel:SetAttribute("Level2_SmoothSlide", true)
	tubeModel:SetAttribute("Level2_OpenTop", openTop == true)
	tubeModel.Parent = parent

	local template = slideTemplate(openTop)
	if not template then
		tubeModel:SetAttribute("Level2_UsingLegacyPanels", true)
		makeLegacyTubeFromPoints(tubeModel, points, radius, color, name, openTop)
		return tubeModel
	end

	local visuals = folder(tubeModel, name .. " Visuals")
	local collisions = folder(tubeModel, name .. " Collision")
	local thickness = Configuration.SlideCollisionThickness or .6
	local collisionOverlap = Configuration.SlideMeshOverlap or .65

	local function addCollisionSegment(a, b, index)
		local length = (b - a).Magnitude
		if length <= .05 then return end

		local suffix = string.format("%03d", index)
		local base = CFrame.lookAt((a + b) * .5, b, Vector3.yAxis)
		local collisionLength = length + collisionOverlap
		makeSlideCollisionPart(collisions, name .. " Collision Floor " .. suffix, base,
			Vector3.new(0, -radius * .9 - thickness * .5, 0),
			Vector3.new(radius * 1.55, thickness, collisionLength))

		local sideHeight = radius * (openTop and 1.35 or 1.8)
		local sideY = openTop and -radius * .25 or 0
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
			local base = CFrame.lookAt((a + b) * .5, b, Vector3.yAxis)

			local visual = template:Clone()
			configureSlideVisual(visual, template, name .. " Visual " .. suffix,
				base, radius, length, color, visualOverlap)
			visual.Parent = visuals

			if not collisionPoints then
				addCollisionSegment(a, b, index)
			end
		end
	end

	if collisionPoints then
		for index = 1, #collisionPoints - 1 do
			addCollisionSegment(collisionPoints[index], collisionPoints[index + 1], index)
		end
	end

	return tubeModel
end

local function makeSlideMouth(parent, name, startPoint, nextPoint, radius, color, transparency)
	local template = slideTemplate(true)
	if not template then
		local fallback = part(parent, name, CFrame.lookAt(startPoint, nextPoint),
			Vector3.new(radius * 2.4, .8, Configuration.SlideMouthLength or 2.8),
			color, Enum.Material.SmoothPlastic, transparency or .08)
		fallback.Reflectance = Configuration.SlideMouthReflectance or .08
		fallback.CanCollide = false
		return fallback
	end

	local baseRadius = template:GetAttribute("Level2_BaseRadius") or 1
	local centerYOffset = template:GetAttribute("Level2_CenterYOffset") or .28869075
	local scale = radius / baseRadius
	local mouth = template:Clone()
	mouth.Name = name
	mouth.Size = Vector3.new(
		template.Size.X * scale * 1.04,
		template.Size.Y * scale * 1.04,
		Configuration.SlideMouthLength or 2.8)
	mouth.CFrame = CFrame.lookAt(startPoint, nextPoint, Vector3.yAxis)
		* CFrame.new(0, -centerYOffset * scale, 0)
	mouth.Color = color
	mouth.Material = Enum.Material.SmoothPlastic
	mouth.Reflectance = Configuration.SlideMouthReflectance or .08
	mouth.Transparency = transparency or .08
	mouth.Anchored = true
	mouth.CanCollide = false
	mouth.CanTouch = false
	mouth.CanQuery = false
	mouth.CastShadow = true
	mouth:SetAttribute("Level2_SlideMouth", true)
	mouth.Parent = parent
	return mouth
end

local function makeSlideTube(parent, p0, p1, p2, p3, radius, color, name, segments, openTop)
	segments = smoothedSlideSegmentCount(segments or Configuration.SlideSegments)
	local points = {}
	for segment = 0, segments do
		table.insert(points, bezier(p0, p1, p2, p3, segment / segments))
	end
	return makeTubeFromPoints(parent, points, radius, color, name, openTop)
end

-- A slide that WINDS AROUND a column: helix from a deck-level catwalk down
-- into the water.
local function makeHelixSlide(parent, columnPosition, helixRadius, topY, color, name)
	local turns = 2.1
	local collisionSegments = smoothedSlideSegmentCount(30)
	local visualSegments = math.max(collisionSegments,
		math.floor((Configuration.SlideHelixVisualSegments or 120) + .5))

	local function pointAt(t)
		local angle = -math.pi * .5 + t * math.pi * 2 * turns
		local y = topY * (1 - t) + 2.2 * t
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
	return visualPoints[1]
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
			makeSlideMouth(hallFolder,
				"Level 2 Slide Hall " .. index .. " Flume Mouth " .. slide,
				startPoint, p1, radius, color, .08)
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

-- A deliberately one-way exit route: a steep, low-grip flume carries players
-- through a real opening and into a room they can physically enter.  The
-- terminal doorway is intentionally at the far end, so completion cannot fire
-- the moment a player merely steps into the tube.
local function makeExitFlume(parent, layout, hall, deck)
	local radius = 8
	local boundsMaxX = layout.Bounds.MaxX
	local shellX = boundsMaxX + 60
	local startPoint = Vector3.new(hall.MaxX - 14, deck.DeckY + 9, deck.DeckZ)

	-- Keep the long procedural span high and clear over the complex, then make
	-- the commitment in the empty east margin: these three fixed segments stay
	-- roughly 39–41 degrees regardless of the selected grand hall's distance
	-- from the shell.  The final 40-stud run-out reaches the unchanged room.
	local roomPenetration = 7
	local roomEntry = Vector3.new(shellX + 34 + roomPenetration, 4, deck.DeckZ)
	local plungeStart = Vector3.new(roomEntry.X - 120, startPoint.Y, deck.DeckZ)
	local tubePoints = {
		startPoint,
		plungeStart,
		plungeStart + Vector3.new(14, -4, 0),
		plungeStart + Vector3.new(36, -24, 0),
		plungeStart + Vector3.new(58, -43, 0),
		plungeStart + Vector3.new(80, -61, 0),
		roomEntry,
	}
	local tube = makeTubeFromPoints(parent, tubePoints, radius, C.TileCool,
		"Level 2 Exit Flume", false)
	tube:SetAttribute("Level2_OneWayExit", true)

	local mouth = makeSlideMouth(parent, "Level 2 Exit Flume Mouth",
		startPoint, tubePoints[2], radius, C.Emergency, .55)

	-- The room floor is aligned to the hidden collision floor of the tube.
	-- That removes the old four-stud ledge at the doorway.
	local floorTop = roomEntry.Y - radius * .9
	local catchSize = 48
	local gatewayHeight = 22
	local westWallX = roomEntry.X - roomPenetration
	local catchCenter = Vector3.new(
		westWallX + catchSize * .5,
		floorTop + gatewayHeight * .5,
		deck.DeckZ
	)

	local function gatewayWall(name, position, size)
		local wall = tiledPart(parent, name, CFrame.new(position), size, C.TileCool, nil, 9)
		wall.CanCollide = true
		return wall
	end

	local floor = tiledPart(parent, "Level 2 Gateway Floor",
		CFrame.new(catchCenter.X, floorTop - .75, catchCenter.Z),
		Vector3.new(catchSize, 1.5, catchSize), C.TileWarm, {Enum.NormalId.Top}, 9)
	floor.CanCollide = true
	local ceiling = tiledPart(parent, "Level 2 Gateway Ceiling",
		CFrame.new(catchCenter.X, floorTop + gatewayHeight + .75, catchCenter.Z),
		Vector3.new(catchSize, 1.5, catchSize), C.TileCool, {Enum.NormalId.Bottom}, 9)
	ceiling.CanCollide = true

	-- North, south, and east stay sealed.  The west wall is deliberately split
	-- into shoulders and a lintel, leaving a centered tube-sized aperture.
	gatewayWall("Level 2 Gateway North Wall",
		catchCenter + Vector3.new(0, 0, -catchSize * .5),
		Vector3.new(catchSize, gatewayHeight, 1.5))
	gatewayWall("Level 2 Gateway South Wall",
		catchCenter + Vector3.new(0, 0, catchSize * .5),
		Vector3.new(catchSize, gatewayHeight, 1.5))
	gatewayWall("Level 2 Gateway East Wall",
		catchCenter + Vector3.new(catchSize * .5, 0, 0),
		Vector3.new(1.5, gatewayHeight, catchSize))

	local apertureWidth = radius * 2 + 3
	local apertureHeight = 18
	local shoulderWidth = (catchSize - apertureWidth) * .5
	local shoulderOffset = apertureWidth * .5 + shoulderWidth * .5
	gatewayWall("Level 2 Gateway West Wall North Shoulder",
		Vector3.new(westWallX, catchCenter.Y, catchCenter.Z - shoulderOffset),
		Vector3.new(1.5, gatewayHeight, shoulderWidth))
	gatewayWall("Level 2 Gateway West Wall South Shoulder",
		Vector3.new(westWallX, catchCenter.Y, catchCenter.Z + shoulderOffset),
		Vector3.new(1.5, gatewayHeight, shoulderWidth))
	gatewayWall("Level 2 Gateway West Wall Lintel",
		Vector3.new(westWallX, floorTop + apertureHeight + (gatewayHeight - apertureHeight) * .5, catchCenter.Z),
		Vector3.new(1.5, gatewayHeight - apertureHeight, apertureWidth))

	-- The wooden door is centered on the far wall and faces the tube exit.
	-- It is story-facing only; the player can always enter the room around it.
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

	makeCeilingPanel(parent, catchCenter, "Gateway", Vector3.new(30, .55, 10), 0, floorTop + gatewayHeight)

	local safeSpawnPosition = doorCenter - outward * 4 + Vector3.new(0, -doorHeight * .5 + .12, 0)
	local safeSpawn = part(parent, "Level 2 Exit Safe Spawn",
		CFrame.new(safeSpawnPosition), Vector3.new(8, .24, 8),
		C.Emergency, Enum.Material.Neon, 1)
	safeSpawn.CanCollide = false
	safeSpawn.CanTouch = false

	-- Completion is deliberately only at the door, after the player has ridden
	-- the whole flume and entered the exit room.
	local trigger = part(parent, "Level 2 Exit Trigger",
		CFrame.new(doorCenter - outward * 3.5 + Vector3.new(0, -1, 0)),
		Vector3.new(4, 12, 14), C.Emergency, Enum.Material.Neon, 1)
	trigger.CanCollide = false
	trigger.CanTouch = true
	trigger.CanQuery = false

	return {
		Trigger = trigger,
		SafeSpawn = safeSpawn,
		Mouth = mouth,
		EndPosition = doorCenter,
		StartPoint = startPoint,
		RoomEntry = roomEntry,
		RoomFloorTop = floorTop,
		Door = woodenDoor,
		HallWallGap = {center = deck.DeckZ, width = 30, bottom = deck.DeckY - 10, top = deck.DeckY + 24},
		ShellGap = {center = deck.DeckZ, width = 40, bottom = -10, top = deck.DeckY + 24},
	}
end

-- ── kids wing ───────────────────────────────────────────────────────────────

local function makeKidsHall(parent, hall, index)
	local palette = kidsPalette(hall)
	local center = hall.Center
	local kidsFolder = folder(parent, "Level 2 Kids Room " .. index .. " " .. palette.Name)
	local containsPump = hall.PumpIndex ~= nil
	kidsFolder:SetAttribute("Level2_KidsColor", palette.Name)
	kidsFolder:SetAttribute("Level2_KidsTileTexture", kidsTileTextureId(hall) or "")
	kidsFolder:SetAttribute("Level2_ContainsPump", containsPump)

	local rng = Random.new(hall.LocalSeed or index)
	local blocks = math.clamp(math.floor(hall.Area / 2600), 5, 14)
	for block = 1, blocks do
		local x, z
		if containsPump then
			-- Pump 1 owns the centre of this room. Re-roll props away from its
			-- 25x17 plinth plus a generous interaction path around the lever.
			for _ = 1, 20 do
				local candidateX = rng:NextNumber(-.32, .32) * hall.Width
				local candidateZ = rng:NextNumber(-.32, .32) * hall.Depth
				if math.abs(candidateX) >= 27 or math.abs(candidateZ) >= 23 then
					x, z = candidateX, candidateZ
					break
				end
			end
			if not x then
				x = (block % 2 == 0 and 1 or -1) * math.min(hall.Width * .32, 34)
				z = 0
			end
		else
			x = rng:NextNumber(-.32, .32) * hall.Width
			z = rng:NextNumber(-.32, .32) * hall.Depth
		end
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
		"Level 2 Kids Stair " .. index, nil, nil, hall)
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
			math.min(52, hall.Width * .36), math.min(52, hall.Depth * .44), hall)
	end

	-- Kids rooms are lit only by the round natural skylights in their ceiling.
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

local function addMachineTexture(object, faces)
	local textureId = level2MachineTextureId()
	if not textureId then return end
	for _, face in ipairs(faces) do
		-- A SurfaceGui stretches one complete artwork across the face. Using a
		-- Texture here made the machinery artwork tile and visibly repeat.
		local surface = Instance.new("SurfaceGui")
		surface.Name = "Level 2 Pump Machinery Artwork " .. face.Name
		surface.Face = face
		surface.LightInfluence = .3
		surface.PixelsPerStud = 40
		surface.ZOffset = .01
		surface.Parent = object

		local artwork = Instance.new("ImageLabel")
		artwork.Name = "Level 2 Pump Machinery Single Artwork"
		artwork.BackgroundTransparency = 1
		artwork.Size = UDim2.fromScale(1, 1)
		artwork.Image = textureId
		artwork.ImageColor3 = Color3.fromRGB(225, 227, 226)
		artwork.ImageTransparency = .04
		artwork.ScaleType = Enum.ScaleType.Stretch
		artwork.Parent = surface
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
	model:SetAttribute("Level2_HallId", hall.Id)
	model:SetAttribute("Level2_InKidsArea", hall.Role == "Kids Area")
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
	addMachineTexture(panel, {Enum.NormalId.Back})

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
	lampGlow.Brightness = .294
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

	-- The original redesign read clearly, but dominated its rooms. Scale the
	-- complete station to 60% (40% smaller) around its plinth, then lower it
	-- so the reduced plinth still sits exactly on the floor.
	local stationScale = .6
	model:ScaleTo(stationScale)
	local groundCorrection = (5 - plinth.Size.Y) * .5
	model:PivotTo(model:GetPivot() + Vector3.new(0, -groundCorrection, 0))
	model:SetAttribute("Level2_VisualScale", stationScale)

	-- Scaling and grounding move the animated pivot, so capture its final
	-- world-space rest pose for the objective controller's pull tween.
	leverIdleCFrame = lever.CFrame
	prompt.MaxActivationDistance = 10

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

local function makeArrivalConcourse(parent, hall, roomDirection)
	local center = hall.Center
	local arrivalFolder = folder(parent, "Level 2 Arrival Concourse")
	roomDirection = roomDirection or Vector3.new(0, 0, 1)
	local sideDirection = Vector3.new(-roomDirection.Z, 0, roomDirection.X)

	local platformHeight = 1.2
	local platform = tiledPart(arrivalFolder, "Level 2 Arrival Platform",
		CFrame.new(center + Vector3.new(0, platformHeight * .5, 0)),
		Vector3.new(20, platformHeight, 20), C.TileWarm, Enum.NormalId:GetEnumItems(), 7)
	platform.CanCollide = true

	local ring = part(arrivalFolder, "Level 2 Arrival Ring",
		CFrame.new(center + Vector3.new(0, platformHeight + .08, 0)),
		Vector3.new(17, .16, 17), C.Emergency, Enum.Material.Neon, .35)
	ring.CanCollide = false

	for _, direction in ipairs({roomDirection, -roomDirection}) do
		makeStairFlight(arrivalFolder, center + direction * 17.4, -direction, 12, 2,
			"Level 2 Arrival Steps", 2.0, .6)
	end

	local vestibuleCenter = center - roomDirection * 2
	local back = center - roomDirection * 8.2
	local function vestibuleWall(name, position, size, material)
		local wall = part(arrivalFolder, name, CFrame.lookAt(position, position + roomDirection),
			size, C.DarkGrout, material or Enum.Material.Concrete)
		wall.CanCollide = true
		return wall
	end
	-- A full-width backing wall overlaps the hall side walls, so the return
	-- gate cannot be bypassed around either edge.  The gate itself remains the
	-- same story-only visual mounted on this sealed rear barrier.
	local crossAxisSpan = math.abs(roomDirection.X) > 0 and hall.Depth or hall.Width
	local barrierWidth = crossAxisSpan + Configuration.WallThickness * 2 + 2
	local barrierHeight = hallHeight(hall)
	local arrivalBackWall = vestibuleWall("Level 2 Arrival Back Wall",
		back - roomDirection * .8 + Vector3.new(0, barrierHeight * .5, 0),
		Vector3.new(barrierWidth, barrierHeight, 1.5), Enum.Material.Concrete)
	arrivalBackWall:SetAttribute("Level2_StoryOnly", true)
	arrivalBackWall.Color = C.TileWarm
	arrivalBackWall.Material = Enum.Material.SmoothPlastic
	local gateFolder = folder(arrivalFolder, "Level 2 Energy Transfer Gate")
	local gateCenter = back + Vector3.new(0, 4.2, 0)
	local gateFacing = CFrame.lookAt(gateCenter, gateCenter + roomDirection)
	local function gatePart(name, localOffset, size, color, material, transparency)
		local object = part(gateFolder, name, gateFacing * CFrame.new(localOffset), size, color, material, transparency or 0)
		object.CanCollide = false
		object.CanTouch = false
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
	return platformHeight, roomDirection, vestibuleCenter
end

local function makeCompatibilityArrival(world, arrivalPosition, platformHeight, roomDirection, spawnPosition)
	local topY = platformHeight or 0
	roomDirection = roomDirection or Vector3.new(0, 0, 1)
	spawnPosition = spawnPosition or arrivalPosition - roomDirection * 2

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
		spawnPosition + Vector3.new(0, topY + .12, 0), Vector3.new(7, .2, 7))
	elevatorSpawn.CFrame = CFrame.lookAt(elevatorSpawn.Position, elevatorSpawn.Position + roomDirection)
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
		hallModel:SetAttribute("Level2_PumpIndex", hall.PumpIndex or 0)
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
					light.Brightness = .49
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
