local Players = game:GetService("Players")
local ReplicatedStorage = game:GetService("ReplicatedStorage")
local CollectionService = game:GetService("CollectionService")
local Terrain = workspace.Terrain

local Configuration = require(script.Parent:WaitForChild("Level 2 Configuration"))

local WorldBuilder = {}
local C = Configuration.Colors
local TILE_TEXTURE = "rbxassetid://113211706146395"

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
		texture.Color3 = Color3.fromRGB(248, 242, 218)
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

local function roomCenter(room)
	local size = Configuration.GridSize
	local cell = Configuration.CellSize
	return Vector3.new((room.X - (size + 1) * .5) * cell, 0, (room.Z - (size + 1) * .5) * cell)
end

local function makeGapWall(parent, name, center, length, alongX, hasOpening, height, thickness, gapCenter, bottomOverride)
	height = height or Configuration.WallHeight
	thickness = thickness or Configuration.WallThickness
	local bottomY = bottomOverride or -3
	local fullHeight = height - bottomY
	local centerY = (height + bottomY) * .5
	local gapWidth = Configuration.DoorWidth
	local doorHeight = Configuration.DoorHeight
	if not hasOpening then
		local size = alongX and Vector3.new(length, fullHeight, thickness) or Vector3.new(thickness, fullHeight, length)
		return {tiledPart(parent, name, CFrame.new(center + Vector3.new(0, centerY, 0)), size, C.TileCool, nil, 7)}
	end

	local offset = gapCenter or 0
	local lower = -length * .5
	local upper = length * .5
	local gapLow = math.clamp(offset - gapWidth * .5, lower, upper)
	local gapHigh = math.clamp(offset + gapWidth * .5, lower, upper)
	local objects = {}
	local function segment(segmentCenter, segmentLength)
		if segmentLength <= .1 then return end
		local position = alongX and center + Vector3.new(segmentCenter, centerY, 0)
			or center + Vector3.new(0, centerY, segmentCenter)
		local size = alongX and Vector3.new(segmentLength, fullHeight, thickness)
			or Vector3.new(thickness, fullHeight, segmentLength)
		table.insert(objects, tiledPart(parent, name, CFrame.new(position), size, C.TileCool, nil, 7))
	end
	segment((lower + gapLow) * .5, gapLow - lower)
	segment((gapHigh + upper) * .5, upper - gapHigh)
	local lintelHeight = height - doorHeight
	if lintelHeight > 0 then
		local position = alongX and center + Vector3.new(offset, doorHeight + lintelHeight * .5, 0)
			or center + Vector3.new(0, doorHeight + lintelHeight * .5, offset)
		local size = alongX and Vector3.new(gapWidth, lintelHeight, thickness)
			or Vector3.new(thickness, lintelHeight, gapWidth)
		table.insert(objects, tiledPart(parent, name .. " Lintel", CFrame.new(position), size, C.TileCool, nil, 7))
	end
	return objects
end

local function makeCeilingPanel(parent, center, index, panelSize, yaw)
	panelSize = panelSize or Vector3.new(28, .55, 10)
	local fixtureCFrame = CFrame.new(center.X, Configuration.WallHeight - .18, center.Z)
		* CFrame.Angles(0, yaw or 0, 0)
	local fixture = Instance.new("Model")
	fixture.Name = "Level 2 Recessed Diffused Ceiling Light " .. index
	fixture:SetAttribute("Level2_DiffusedCeilingPanel", true)
	fixture.Parent = parent

	local tray = part(fixture, "Level 2 Recessed Light Dark Backing", fixtureCFrame,
		Vector3.new(panelSize.X, .36, panelSize.Z), Color3.fromRGB(78, 82, 75), Enum.Material.Metal)
	tray.CanCollide = false

	local trimWidth = .72
	local trimY = -.29
	for _, data in ipairs({
		{Vector3.new(0, trimY, -(panelSize.Z - trimWidth) * .5), Vector3.new(panelSize.X, .22, trimWidth)},
		{Vector3.new(0, trimY, (panelSize.Z - trimWidth) * .5), Vector3.new(panelSize.X, .22, trimWidth)},
		{Vector3.new(-(panelSize.X - trimWidth) * .5, trimY, 0), Vector3.new(trimWidth, .22, panelSize.Z - trimWidth * 2)},
		{Vector3.new((panelSize.X - trimWidth) * .5, trimY, 0), Vector3.new(trimWidth, .22, panelSize.Z - trimWidth * 2)},
	}) do
		local trim = part(fixture, "Level 2 Recessed Light Trim", fixtureCFrame * CFrame.new(data[1]),
			data[2], C.TileWarm, Enum.Material.SmoothPlastic)
		trim.CanCollide = false
	end

	local diffuserSize = Vector3.new(
		math.max(2, panelSize.X - trimWidth * 2.5),
		.12,
		math.max(2, panelSize.Z - trimWidth * 2.5)
	)
	local emitter = part(fixture, "Level 2 Recessed Light Hidden Emitter",
		fixtureCFrame * CFrame.new(0, -.31, 0), Vector3.new(diffuserSize.X - .4, .08, diffuserSize.Z - .4),
		C.Light, Enum.Material.Neon, .42)
	emitter.CanCollide = false
	emitter.CanTouch = false
	emitter.CanQuery = false

	local diffuser = part(fixture, "Level 2 Recessed Opal Diffuser",
		fixtureCFrame * CFrame.new(0, -.39, 0), diffuserSize, Color3.fromRGB(255, 243, 216),
		Enum.Material.Glass, Configuration.CeilingDiffuserTransparency)
	diffuser.CanCollide = false
	diffuser.CanTouch = false
	diffuser.CanQuery = false

	local light = Instance.new("SurfaceLight")
	light.Name = "Level 2 Muffled Ceiling Surface Light"
	light.Face = Enum.NormalId.Bottom
	light.Color = Color3.fromRGB(255, 238, 205)
	light.Brightness = Configuration.CeilingPanelBrightness
	light.Range = Configuration.CeilingPanelRange
	light.Angle = Configuration.CeilingPanelAngle
	light.Shadows = false
	light.Parent = diffuser

	local fill = Instance.new("PointLight")
	fill.Name = "Level 2 Recessed Light Soft Fill"
	fill.Color = Color3.fromRGB(255, 238, 211)
	fill.Brightness = .09
	fill.Range = 14
	fill.Shadows = false
	fill.Parent = emitter
	return fixture, diffuser
end

local function makeRoomLights(parent, room, center, index)
	local archetype = room.Archetype or ""
	local eastWest = room.Orientation == "EastWest"
	local yaw = eastWest and 0 or math.pi * .5
	local cell = Configuration.CellSize
	local spaceType = room.SpaceType or "Standard"
	local offsets = {}
	local panelSize = Vector3.new(34, .55, 7)

	if spaceType == "Grand Open Hall" or archetype == "Grand Column Hall" then
		panelSize = Vector3.new(40, .55, 8)
		for x = -1, 1, 2 do
			for z = -1, 1, 2 do table.insert(offsets, Vector3.new(x * cell * .23, 0, z * cell * .23)) end
		end
	elseif spaceType ~= "Standard" or archetype == "Pillar Basin" or archetype == "Column Reservoir" then
		panelSize = Vector3.new(36, .55, 8)
		for x = -1, 1, 2 do
			for z = -1, 1, 2 do table.insert(offsets, Vector3.new(x * cell * .22, 0, z * cell * .22)) end
		end
	elseif archetype == "Long Gallery" or archetype == "Long Canal" or archetype == "Flooded Gallery" or archetype == "Exit Gallery" then
		panelSize = Vector3.new(44, .55, 7)
		for offset = -1, 1 do
			table.insert(offsets, eastWest and Vector3.new(offset * cell * .27, 0, 0) or Vector3.new(0, 0, offset * cell * .27))
		end
		table.insert(offsets, Vector3.zero)
	else
		for offset = -1, 1 do
			table.insert(offsets, eastWest and Vector3.new(offset * cell * .25, 0, 0) or Vector3.new(0, 0, offset * cell * .25))
		end
		table.insert(offsets, Vector3.zero)
	end

	for lightIndex, offset in ipairs(offsets) do
		makeCeilingPanel(parent, center + offset, index .. " Panel " .. lightIndex, panelSize, yaw)
	end
end

local function makeWallPanel(parent, center, index)
	local frame = part(parent, "Level 2 Wall Light Frame " .. index,
		CFrame.new(center.X + 24, 8, center.Z - Configuration.CellSize * .5 + 1.75),
		Vector3.new(17, 7, .5), C.Metal, Enum.Material.Metal)
	local diffuser = part(parent, "Level 2 Wall Light Diffuser " .. index,
		frame.CFrame * CFrame.new(0, 0, .32), Vector3.new(14, 5, .16), C.Light, Enum.Material.Neon, .16)
	diffuser.CanCollide = false
	local light = Instance.new("SurfaceLight")
	light.Name = "Level 2 Wall Surface Light"
	light.Face = Enum.NormalId.Back
	light.Color = C.Light
	light.Brightness = Configuration.WallPanelBrightness
	light.Range = Configuration.WallPanelRange
	light.Angle = 105
	light.Shadows = false
	light.Parent = diffuser
	return frame, diffuser
end

local function makePoolShell(parent, center, depth, poolType)
	local cell = Configuration.CellSize
	local walkway = Configuration.WalkwayWidth
	local outer = cell - walkway * 2
	local wallThickness = 4
	local bottomY = -depth
	local wallTop = 1.25
	local wallHeight = wallTop - bottomY
	local wallCenterY = bottomY + wallHeight * .5

	local bottom = tiledPart(parent, "Level 2 " .. poolType .. " Pool Bottom",
		CFrame.new(center + Vector3.new(0, bottomY - .75, 0)), Vector3.new(outer, 1.5, outer), C.TileCool,
		{Enum.NormalId.Top}, 10)
	bottom.CanCollide = true

	for _, data in ipairs({
		{Vector3.new(-outer * .5, wallCenterY, 0), Vector3.new(wallThickness, wallHeight, outer)},
		{Vector3.new(outer * .5, wallCenterY, 0), Vector3.new(wallThickness, wallHeight, outer)},
		{Vector3.new(0, wallCenterY, -outer * .5), Vector3.new(outer, wallHeight, wallThickness)},
		{Vector3.new(0, wallCenterY, outer * .5), Vector3.new(outer, wallHeight, wallThickness)},
	}) do
		local wall = tiledPart(parent, "Level 2 " .. poolType .. " Pool Wall", CFrame.new(center + data[1]), data[2], C.TileCool, nil, 10)
		wall.CanCollide = true
		wall:SetAttribute("Level2_SealedPoolWall", true)
	end

	local waterWidth = outer - wallThickness * 2 - 2
	local waterHeight = math.max(.8, depth - .35)
	Terrain:FillBlock(
		CFrame.new(center + Vector3.new(0, -waterHeight * .5 + .1, 0)),
		Vector3.new(waterWidth, waterHeight, waterWidth),
		Enum.Material.Water
	)
	return outer
end

local function makeBridge(parent, center, alongX, length, name)
	local size = alongX and Vector3.new(length, 1.25, 9) or Vector3.new(9, 1.25, length)
	local bridge = tiledPart(parent, name, CFrame.new(center + Vector3.new(0, .45, 0)), size, C.TileWarm,
		{Enum.NormalId.Top, Enum.NormalId.Left, Enum.NormalId.Right, Enum.NormalId.Front, Enum.NormalId.Back}, 9)
	bridge.CanCollide = true
	return bridge
end

local function makeColumn(parent, position, height)
	local column = tiledPart(parent, "Level 2 Tiled Pool Column",
		CFrame.new(position + Vector3.new(0, height * .5 - 1, 0)) * CFrame.Angles(0, 0, math.pi * .5),
		Vector3.new(height, 5, 5), C.TileWarm, nil, 9)
	column.Shape = Enum.PartType.Cylinder
	return column
end

local function makeRail(parent, a, b, name)
	local delta = b - a
	local length = delta.Magnitude
	if length < 1 then return end
	local direction = delta.Unit
	local height = 4.2
	local bar = part(parent, name .. " Handrail", CFrame.lookAt((a + b) * .5 + Vector3.new(0, height, 0), b + Vector3.new(0, height, 0)),
		Vector3.new(.42, .42, length), C.Metal, Enum.Material.Metal)
	bar.CanCollide = true
	local posts = math.max(2, math.floor(length / 8))
	for index = 0, posts do
		local position = a + direction * (length * index / posts)
		part(parent, name .. " Post " .. index, CFrame.new(position + Vector3.new(0, height * .5, 0)),
			Vector3.new(.34, height, .34), C.Metal, Enum.Material.Metal)
	end
end

local function makeStairFlight(parent, base, direction, width, steps, name)
	direction = direction.Unit
	local run = 2.25
	local rise = .72
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

local function makeTallGlowPanel(parent, position, yaw, index)
	local frameCFrame = CFrame.new(position + Vector3.new(0, 8, 0)) * CFrame.Angles(0, yaw, 0)
	part(parent, "Level 2 Porthole Light Frame " .. index, frameCFrame, Vector3.new(9, 17, .7), C.TileWarm)
	local diffuser = part(parent, "Level 2 Porthole Light Diffuser " .. index,
		frameCFrame * CFrame.new(0, -1.2, .42), Vector3.new(6.6, 12.3, .18), C.Light, Enum.Material.Neon, .08)
	diffuser.CanCollide = false
	local cap = part(parent, "Level 2 Porthole Light Rounded Cap " .. index,
		frameCFrame * CFrame.new(0, 5.1, .42) * CFrame.Angles(0, math.pi * .5, 0),
		Vector3.new(.18, 6.6, 6.6), C.Light, Enum.Material.Neon, .08)
	cap.Shape = Enum.PartType.Cylinder
	cap.CanCollide = false
	for _, lightPart in ipairs({diffuser, cap}) do
		local light = Instance.new("SurfaceLight")
		light.Name = "Level 2 Porthole Surface Light"
		light.Face = Enum.NormalId.Back
		light.Color = C.Light
		light.Brightness = .65
		light.Range = 26
		light.Angle = 110
		light.Shadows = false
		light.Parent = lightPart
	end
	local fill = Instance.new("PointLight")
	fill.Name = "Level 2 Porthole Fill Light"
	fill.Color = C.Light
	fill.Brightness = .2
	fill.Range = 16
	fill.Shadows = false
	fill.Parent = diffuser
end

local function makeDryIsland(parent, position, size, name)
	local island = tiledPart(parent, name, CFrame.new(position + Vector3.new(0, .55, 0)),
		Vector3.new(size.X, 1.4, size.Z), C.TileWarm, Enum.NormalId:GetEnumItems(), 7)
	island.CanCollide = true
	return island
end

local function makeRoomInterior(parent, room, center)
	local poolType = room.PoolType
	local archetype = room.Archetype or "Dry Gallery"
	local eastWest = room.Orientation == "EastWest"
	local isWater = poolType ~= "Dry"
	if not isWater then
		local inset = Configuration.CellSize - 20
		tiledPart(parent, "Level 2 Dry Tiled Floor Detail", CFrame.new(center + Vector3.new(0, .05, 0)),
			Vector3.new(inset, .2, inset), C.TileWarm, {Enum.NormalId.Top}, 7)

		if archetype == "Stair Overlook" then
			local side = eastWest and Vector3.new(0, 0, -1) or Vector3.new(-1, 0, 0)
			local platformCenter = center + side * 27 + Vector3.new(0, 2.5, 0)
			local platformSize = eastWest and Vector3.new(58, 5, 22) or Vector3.new(22, 5, 58)
			tiledPart(parent, "Level 2 Stair Overlook Platform", CFrame.new(platformCenter), platformSize, C.TileWarm,
				Enum.NormalId:GetEnumItems(), 7)
			local base = center + side * 4
			makeStairFlight(parent, base, side, 17, 7, "Level 2 Stair Overlook")
			local edgeA = eastWest and center + Vector3.new(-28, 5, -16) or center + Vector3.new(-16, 5, -28)
			local edgeB = eastWest and center + Vector3.new(28, 5, -16) or center + Vector3.new(-16, 5, 28)
			makeRail(parent, edgeA, edgeB, "Level 2 Stair Overlook")
		elseif archetype == "Porthole Hall" then
			if eastWest then
				for index, offset in ipairs({-24, 0, 24}) do makeTallGlowPanel(parent, center + Vector3.new(offset, 0, -39), 0, room.Id .. " " .. index) end
			else
				for index, offset in ipairs({-24, 0, 24}) do makeTallGlowPanel(parent, center + Vector3.new(-39, 0, offset), math.pi * .5, room.Id .. " " .. index) end
			end
		elseif archetype == "Dry Column Atrium" then
			for _, offset in ipairs({
				Vector3.new(-32, 0, -28), Vector3.new(0, 0, -28), Vector3.new(32, 0, -28),
				Vector3.new(-32, 0, 28), Vector3.new(0, 0, 28), Vector3.new(32, 0, 28),
			}) do
				makeColumn(parent, center + offset, Configuration.WallHeight - 2)
			end
		elseif archetype == "Atrium Landing" or archetype == "Arrival Gallery" then
			for _, offset in ipairs({-28, 28}) do
				local position = eastWest and center + Vector3.new(offset, 0, -29) or center + Vector3.new(-29, 0, offset)
				makeColumn(parent, position, Configuration.WallHeight - 2)
			end
			local a = eastWest and center + Vector3.new(-42, 0, 38) or center + Vector3.new(38, 0, -42)
			local b = eastWest and center + Vector3.new(42, 0, 38) or center + Vector3.new(38, 0, 42)
			makeRail(parent, a, b, "Level 2 Atrium Landing")
		end
		return
	end

	local deep = poolType == "Deep" or poolType == "Grand" or poolType == "Column" or poolType == "Reflection"
	local depth = deep and Configuration.DeepPoolDepth or Configuration.ShallowPoolDepth
	local outer = makePoolShell(parent, center, depth, poolType)

	if archetype == "Grand Column Hall" then
		makeBridge(parent, center, true, outer, "Level 2 Grand Pool Cross Bridge")
		makeBridge(parent, center, false, outer, "Level 2 Grand Pool Cross Bridge")
		for _, offset in ipairs({Vector3.new(-24, 0, -24), Vector3.new(0, 0, -24), Vector3.new(24, 0, -24), Vector3.new(-24, 0, 24), Vector3.new(0, 0, 24), Vector3.new(24, 0, 24)}) do
			makeColumn(parent, center + offset, Configuration.WallHeight - 2)
		end
	elseif archetype == "Pillar Basin" then
		makeBridge(parent, center, eastWest, outer, "Level 2 Pillar Basin Bridge")
		for _, offset in ipairs({Vector3.new(-30, 0, -27), Vector3.new(30, 0, -27), Vector3.new(-30, 0, 27), Vector3.new(30, 0, 27)}) do
			makeColumn(parent, center + offset, Configuration.WallHeight - 2)
		end
	elseif archetype == "Column Reservoir" then
		makeBridge(parent, center, eastWest, outer, "Level 2 Column Reservoir Route")
		for x = -1, 1 do
			for z = -1, 1 do
				if x ~= 0 or z ~= 0 then
					makeColumn(parent, center + Vector3.new(x * 31, 0, z * 31), Configuration.WallHeight - 2)
				end
			end
		end
	elseif archetype == "Long Canal" then
		local side = eastWest and Vector3.new(0, 0, 26) or Vector3.new(26, 0, 0)
		makeBridge(parent, center - side, eastWest, outer, "Level 2 Long Canal Walkway")
		makeBridge(parent, center + side, eastWest, outer, "Level 2 Long Canal Walkway")
	elseif archetype == "Flooded Gallery" or archetype == "Long Gallery" then
		local side = eastWest and Vector3.new(0, 0, 20) or Vector3.new(20, 0, 0)
		makeBridge(parent, center - side, eastWest, outer, "Level 2 Flooded Gallery Walkway")
		makeBridge(parent, center + side, eastWest, outer, "Level 2 Flooded Gallery Walkway")
		if eastWest then
			for index, offset in ipairs({-24, 0, 24}) do makeTallGlowPanel(parent, center + Vector3.new(offset, 0, -38), 0, room.Id .. " Gallery " .. index) end
		else
			for index, offset in ipairs({-24, 0, 24}) do makeTallGlowPanel(parent, center + Vector3.new(-38, 0, offset), math.pi * .5, room.Id .. " Gallery " .. index) end
		end
	elseif archetype == "Channel Junction" then
		makeBridge(parent, center, true, outer, "Level 2 Channel Junction Walkway")
		makeBridge(parent, center, false, outer, "Level 2 Channel Junction Walkway")
		for _, offset in ipairs({Vector3.new(-23, 0, -23), Vector3.new(23, 0, -23), Vector3.new(-23, 0, 23), Vector3.new(23, 0, 23)}) do
			makeDryIsland(parent, center + offset, Vector3.new(16, 0, 16), "Level 2 Channel Junction Island")
		end
	elseif archetype == "Open Reflection Hall" then
		makeBridge(parent, center, eastWest, outer, "Level 2 Reflection Hall Walkway")
		for _, offset in ipairs({
			Vector3.new(-30, 0, -30), Vector3.new(30, 0, -30),
			Vector3.new(-30, 0, 30), Vector3.new(30, 0, 30),
		}) do
			makeColumn(parent, center + offset, Configuration.WallHeight - 2)
		end
		if eastWest then
			for index, offset in ipairs({-34, 0, 34}) do
				makeTallGlowPanel(parent, center + Vector3.new(offset, 0, -55), 0, room.Id .. " Reflection " .. index)
			end
		else
			for index, offset in ipairs({-34, 0, 34}) do
				makeTallGlowPanel(parent, center + Vector3.new(-55, 0, offset), math.pi * .5, room.Id .. " Reflection " .. index)
			end
		end
	elseif archetype == "Split-Level Basin" then
		makeBridge(parent, center, eastWest, outer, "Level 2 Split-Level Basin Route")
		local side = eastWest and Vector3.new(0, 0, 1) or Vector3.new(1, 0, 0)
		local platformCenter = center + side * 34 + Vector3.new(0, 2.2, 0)
		local platformSize = eastWest and Vector3.new(48, 4.4, 30) or Vector3.new(30, 4.4, 48)
		tiledPart(parent, "Level 2 Split-Level Basin Platform", CFrame.new(platformCenter), platformSize, C.TileWarm,
			Enum.NormalId:GetEnumItems(), 7)
		makeStairFlight(parent, center + side * 4, side, 18, 6, "Level 2 Split-Level Basin")
	elseif archetype == "Sunken Pool" or archetype == "Grand Basin" then
		local bridge = makeBridge(parent, center, eastWest, outer, "Level 2 Sunken Pool Safety Walkway")
		local halfLength = outer * .5 - 3
		local a = eastWest and center + Vector3.new(-halfLength, 1, -5) or center + Vector3.new(-5, 1, -halfLength)
		local b = eastWest and center + Vector3.new(halfLength, 1, -5) or center + Vector3.new(-5, 1, halfLength)
		makeRail(parent, a, b, "Level 2 Sunken Pool")
		bridge:SetAttribute("Level2_DeepPoolSafetyRoute", true)
	elseif archetype == "Low Water Hall" then
		makeBridge(parent, center, eastWest, outer, "Level 2 Low Water Hall Walkway")
	elseif archetype == "Flooded Bend" then
		makeBridge(parent, center + (eastWest and Vector3.new(-18, 0, 0) or Vector3.new(0, 0, -18)), true, outer * .62, "Level 2 Flooded Bend Walkway")
		makeBridge(parent, center + (eastWest and Vector3.new(0, 0, 18) or Vector3.new(18, 0, 0)), false, outer * .62, "Level 2 Flooded Bend Walkway")
	elseif archetype == "Bright Basin" then
		for _, offset in ipairs({Vector3.new(-21, 0, -21), Vector3.new(21, 0, 21)}) do
			makeColumn(parent, center + offset, Configuration.WallHeight - 2)
		end
		makeBridge(parent, center, eastWest, outer, "Level 2 Bright Basin Walkway")
	else
		makeBridge(parent, center, eastWest, outer, "Level 2 Pool Safety Walkway")
	end

	if poolType == "Reflection" then
		part(parent, "Level 2 Reflection Dark Mirror", CFrame.new(center + Vector3.new(0, 10, Configuration.CellSize * .5 - 2)),
			Vector3.new(38, 14, .35), Color3.fromRGB(25, 42, 45), Enum.Material.Glass, .18)
	end
end

local function makeRoomFloor(parent, room, center)
	local cell = Configuration.CellSize
	local walkway = Configuration.WalkwayWidth
	local poolRoom = room.PoolType ~= "Dry"
		and room.PoolType ~= "Exit"
		and room.PoolType ~= "Arrival"
	if not poolRoom then
		local floorTile = tiledPart(parent, "Level 2 Full Room Floor",
			CFrame.new(center + Vector3.new(0, -.3, 0)), Vector3.new(cell, .65, cell),
			C.TileWarm, {Enum.NormalId.Top}, 7)
		floorTile.CanCollide = true
		return
	end
	for _, data in ipairs({
		{Vector3.new(0, -.3, -(cell - walkway) * .5), Vector3.new(cell, .65, walkway)},
		{Vector3.new(0, -.3, (cell - walkway) * .5), Vector3.new(cell, .65, walkway)},
		{Vector3.new(-(cell - walkway) * .5, -.3, 0), Vector3.new(walkway, .65, cell - walkway * 2)},
		{Vector3.new((cell - walkway) * .5, -.3, 0), Vector3.new(walkway, .65, cell - walkway * 2)},
	}) do
		local strip = tiledPart(parent, "Level 2 Pool Perimeter Walkway",
			CFrame.new(center + data[1]), data[2], C.TileWarm, {Enum.NormalId.Top}, 7)
		strip.CanCollide = true
	end
end

local function tintTileTextures(object, tint)
	for _, descendant in ipairs(object:GetDescendants()) do
		if descendant:IsA("Texture") then
			descendant.Color3 = tint
		end
	end
end

local function slideBezier(p0, p1, p2, p3, t)
	local u = 1 - t
	return p0 * (u ^ 3) + p1 * (3 * u * u * t) + p2 * (3 * u * t * t) + p3 * (t ^ 3)
end

local function makeDecorativeSlideTube(parent, name, points, definition, radius)
	local slideModel = Instance.new("Model")
	slideModel.Name = name
	slideModel:SetAttribute("Level2_DecorativeSlide", true)
	slideModel:SetAttribute("Level2_SlideColor", definition.Name)
	slideModel.Parent = parent

	local sides = 8
	local arcWidth = 2 * radius * math.sin(math.pi / sides) * 1.13
	for segment = 1, #points - 1 do
		local a, b = points[segment], points[segment + 1]
		local delta = b - a
		local length = delta.Magnitude
		if length > .05 then
			local base = CFrame.lookAt((a + b) * .5, b, Vector3.yAxis)
			for sideIndex = 0, sides - 1 do
				local angle = sideIndex * math.pi * 2 / sides
				local offset = Vector3.new(math.cos(angle) * radius, math.sin(angle) * radius, 0)
				local panel = part(slideModel, "Level 2 Decorative Slide Shell Panel",
					base * CFrame.new(offset) * CFrame.Angles(0, 0, angle - math.pi * .5),
					Vector3.new(arcWidth, .34, length + .45), definition.Color, Enum.Material.SmoothPlastic)
				panel.CanCollide = false
				panel.CanTouch = false
				panel.CanQuery = false
				panel.Reflectance = .06
				panel:SetAttribute("Level2_UnreachableDecoration", true)
			end
		end
	end
	return slideModel
end

local function makeKidsPoolroomLandmark(parent, room, center)
	local rng = Random.new(room.LandmarkSeed or room.LocalSeed or 1)
	local landmark = Instance.new("Model")
	landmark.Name = "Level 2 Kids Pool Slide Landmark"
	landmark:SetAttribute("Level2_KidsLandmark", true)
	landmark:SetAttribute("Level2_LandmarkSeed", room.LandmarkSeed or room.LocalSeed or 1)
	landmark:SetAttribute("Level2_SlideCount", room.SlideCount or 2)
	landmark.Parent = parent

	-- A different, softly colored tile field makes this room readable as the children's pool.
	local kidsBottom = tiledPart(landmark, "Level 2 Kids Pool Mosaic Floor",
		CFrame.new(center + Vector3.new(0, -2.16, 0)), Vector3.new(72, .2, 72),
		Color3.fromRGB(214, 226, 211), {Enum.NormalId.Top}, 5.5)
	kidsBottom.CanCollide = true
	kidsBottom:SetAttribute("Level2_KidsTile", true)
	tintTileTextures(kidsBottom, Color3.fromRGB(219, 234, 216))

	local kidsDeck = tiledPart(landmark, "Level 2 Kids Pool Dry Mosaic Deck",
		CFrame.new(center + Vector3.new(0, .12, 54)), Vector3.new(58, .36, 14),
		Color3.fromRGB(229, 224, 196), {Enum.NormalId.Top}, 5.5)
	kidsDeck.CanCollide = true
	kidsDeck:SetAttribute("Level2_KidsTile", true)
	tintTileTextures(kidsDeck, Color3.fromRGB(241, 232, 201))

	local palette = table.clone(Configuration.SlideColors)
	for index = #palette, 2, -1 do
		local swap = rng:NextInteger(1, index)
		palette[index], palette[swap] = palette[swap], palette[index]
	end
	for index, definition in ipairs(Configuration.SlideColors) do
		local inlay = part(landmark, "Level 2 Kids Mosaic " .. definition.Name .. " Tile Inlay",
			CFrame.new(center + Vector3.new(-21 + (index - 1) * 14, .34, 54)),
			Vector3.new(9.5, .08, 2.6), definition.Color:Lerp(C.TileWarm, .42), Enum.Material.SmoothPlastic)
		inlay.CanCollide = false
		inlay.CanTouch = false
		inlay.CanQuery = false
	end

	local signPosition = center + Vector3.new(-20, 7.2, 58)
	local signCFrame = CFrame.lookAt(signPosition, center + Vector3.new(-20, 7.2, 0))
	local sign = part(landmark, "Level 2 Kids Pool Landmark Sign", signCFrame,
		Vector3.new(18, 5.4, .5), Color3.fromRGB(70, 92, 94), Enum.Material.Metal)
	sign.CanCollide = false
	local surface = Instance.new("SurfaceGui")
	surface.Name = "Level 2 Kids Pool Sign Surface"
	surface.Face = Enum.NormalId.Front
	surface.CanvasSize = Vector2.new(720, 220)
	surface.Parent = sign
	local label = Instance.new("TextLabel")
	label.Name = "Level 2 Kids Pool Sign Text"
	label.Size = UDim2.fromScale(1, 1)
	label.BackgroundTransparency = 1
	label.Text = "CHILDREN'S POOL  •  SLIDE TOWER"
	label.TextColor3 = Color3.fromRGB(245, 238, 208)
	label.TextStrokeColor3 = Color3.fromRGB(30, 49, 54)
	label.TextStrokeTransparency = .35
	label.TextScaled = true
	label.Font = Enum.Font.GothamBold
	label.Parent = surface

	local signDirection = room.KidsAnchorSign or 1
	local columnCenter = center + Vector3.new(23 * signDirection, 0, -23)
	local column = makeColumn(landmark, columnCenter, Configuration.WallHeight - 2)
	column.Name = "Level 2 Kids Spiral Slide Tiled Column"
	column:SetAttribute("Level2_SlideColumn", true)

	local helixPoints = {}
	local helixTurns = 2.3 + rng:NextNumber() * .35
	local startAngle = rng:NextNumber() * math.pi * 2
	for step = 0, 48 do
		local t = step / 48
		local angle = startAngle + t * helixTurns * math.pi * 2
		table.insert(helixPoints, columnCenter + Vector3.new(
			math.cos(angle) * 10.5,
			36 - t * 14,
			math.sin(angle) * 10.5
		))
	end
	makeDecorativeSlideTube(landmark,
		"Level 2 Kids Spiral " .. palette[1].Name .. " Slide",
		helixPoints, palette[1], 2.8)

	local wallX = -58 * signDirection
	local wallZ = 28
	local wallSlidePoints = {}
	local wallP0 = center + Vector3.new(wallX, 34, wallZ)
	local wallP1 = center + Vector3.new(wallX * .78, 33, wallZ)
	local wallP2 = center + Vector3.new(wallX * .52, 28, wallZ - 2)
	local wallP3 = center + Vector3.new(wallX * .28, 24, wallZ - 6)
	for step = 0, 18 do
		table.insert(wallSlidePoints, slideBezier(wallP0, wallP1, wallP2, wallP3, step / 18))
	end
	makeDecorativeSlideTube(landmark,
		"Level 2 Kids Suspended " .. palette[2].Name .. " Wall Slide",
		wallSlidePoints, palette[2], 3)

	if (room.SlideCount or 2) >= 3 then
		local ceilingSlidePoints = {}
		local ceilingP0 = center + Vector3.new(-20 * signDirection, 35, -59)
		local ceilingP1 = center + Vector3.new(-20 * signDirection, 34, -46)
		local ceilingP2 = center + Vector3.new(-16 * signDirection, 28, -31)
		local ceilingP3 = center + Vector3.new(-10 * signDirection, 23.5, -18)
		for step = 0, 18 do
			table.insert(ceilingSlidePoints, slideBezier(ceilingP0, ceilingP1, ceilingP2, ceilingP3, step / 18))
		end
		makeDecorativeSlideTube(landmark,
			"Level 2 Kids Hanging " .. palette[3].Name .. " Ceiling Slide",
			ceilingSlidePoints, palette[3], 2.7)
	end
	return landmark
end

local function makeValve(parent, room, index)
	local center = roomCenter(room)
	local model = Instance.new("Model")
	model.Name = "Level 2 Pressure Valve " .. index
	model:SetAttribute("Level2_ValveIndex", index)
	model:SetAttribute("Level2_ValveRoomId", room.Id)
	model:SetAttribute("Level2_ValveRoomRole", room.Role)
	model:SetAttribute("Level2_ValveOnDryPerimeter", true)
	model:SetAttribute("Level2_ValveActivated", false)
	model.Parent = parent

	-- Every room has a sealed dry perimeter at local Z = 54. This keeps the valve
	-- reachable regardless of the water depth or the room's authored pool geometry.
	local anchor = center + Vector3.new(0, 0, 54)
	local baseCFrame = CFrame.lookAt(anchor, center)
	local platform = tiledPart(model, "Level 2 Valve Dry Service Platform",
		baseCFrame * CFrame.new(0, .65, 0), Vector3.new(20, 1.3, 12),
		C.TileWarm, Enum.NormalId:GetEnumItems(), 7)
	platform.CanCollide = true
	platform:SetAttribute("Level2_ValveSafePlatform", true)

	local riser = part(model, "Level 2 Valve Industrial Riser",
		baseCFrame * CFrame.new(0, 7.8, .8) * CFrame.Angles(0, 0, math.pi * .5),
		Vector3.new(13.5, 3.1, 3.1), Color3.fromRGB(88, 103, 104), Enum.Material.Metal)
	riser.Shape = Enum.PartType.Cylinder
	riser.Reflectance = .08

	local crossPipe = part(model, "Level 2 Valve Pressure Cross Pipe",
		baseCFrame * CFrame.new(0, 14.1, .8), Vector3.new(11.5, 2.5, 2.5),
		Color3.fromRGB(88, 103, 104), Enum.Material.Metal)
	crossPipe.Shape = Enum.PartType.Cylinder
	crossPipe.Reflectance = .08

	for sideIndex, side in ipairs({-1, 1}) do
		local collar = part(model, "Level 2 Valve Pipe Collar " .. sideIndex,
			baseCFrame * CFrame.new(side * 5.15, 14.1, .8),
			Vector3.new(.72, 3.45, 3.45), Color3.fromRGB(59, 71, 72), Enum.Material.Metal)
		collar.Shape = Enum.PartType.Cylinder
	end

	local hub = part(model, "Level 2 Valve Wheel Hub",
		baseCFrame * CFrame.new(0, 8.8, -2.35) * CFrame.Angles(0, math.pi * .5, 0),
		Vector3.new(2.8, 4.7, 4.7), Color3.fromRGB(72, 84, 85), Enum.Material.Metal)
	hub.Shape = Enum.PartType.Cylinder
	hub.Reflectance = .1

	local wheelAssembly = Instance.new("Model")
	wheelAssembly.Name = "Level 2 Valve Spinning Wheel Assembly"
	wheelAssembly:SetAttribute("Level2_ValveWheelAssembly", true)
	wheelAssembly.Parent = model
	local wheelCenter = baseCFrame * CFrame.new(0, 8.8, -4.25)
	local pivot = part(wheelAssembly, "Level 2 Valve Wheel Pivot", wheelCenter,
		Vector3.new(.35, .35, .35), C.Void, Enum.Material.SmoothPlastic, 1)
	pivot.CanCollide = false
	pivot.CanTouch = false
	pivot.CanQuery = false
	wheelAssembly.PrimaryPart = pivot

	local wheelColor = Color3.fromRGB(169, 61, 48)
	local wheelRadius = 5.25
	local rimSegments = 16
	local rimLength = (math.pi * 2 * wheelRadius / rimSegments) * 1.08
	for segment = 0, rimSegments - 1 do
		local angle = segment * math.pi * 2 / rimSegments
		local rim = part(wheelAssembly, "Level 2 Valve Wheel Rim Segment " .. (segment + 1),
			wheelCenter * CFrame.new(math.cos(angle) * wheelRadius, math.sin(angle) * wheelRadius, 0)
				* CFrame.Angles(0, 0, angle + math.pi * .5),
			Vector3.new(rimLength, .78, .78), wheelColor, Enum.Material.Metal)
		rim.CanCollide = false
		rim.CanTouch = false
		rim:SetAttribute("Level2_ValveWheelVisual", true)
	end
	for spokeIndex = 0, 5 do
		local angle = spokeIndex * math.pi / 3
		local spoke = part(wheelAssembly, "Level 2 Valve Wheel Spoke " .. (spokeIndex + 1),
			wheelCenter * CFrame.Angles(0, 0, angle) * CFrame.new(wheelRadius * .43, 0, 0),
			Vector3.new(wheelRadius * 1.72, .64, .64), wheelColor, Enum.Material.Metal)
		spoke.CanCollide = false
		spoke.CanTouch = false
		spoke:SetAttribute("Level2_ValveWheelVisual", true)
	end
	local cap = part(wheelAssembly, "Level 2 Valve Wheel Center Cap", wheelCenter,
		Vector3.new(2.15, 2.15, 2.15), Color3.fromRGB(196, 79, 59), Enum.Material.Metal)
	cap.Shape = Enum.PartType.Ball
	cap.CanCollide = false
	cap.CanTouch = false
	cap:SetAttribute("Level2_ValveWheelVisual", true)

	local gaugeCFrame = baseCFrame * CFrame.new(4.75, 11.1, -.8) * CFrame.Angles(0, math.pi * .5, 0)
	local gaugeRim = part(model, "Level 2 Valve Pressure Gauge Rim", gaugeCFrame,
		Vector3.new(.75, 3.8, 3.8), Color3.fromRGB(55, 66, 67), Enum.Material.Metal)
	gaugeRim.Shape = Enum.PartType.Cylinder
	local gaugeFace = part(model, "Level 2 Valve Pressure Gauge Face",
		gaugeCFrame * CFrame.new(-.42, 0, 0), Vector3.new(.18, 3.1, 3.1),
		Color3.fromRGB(224, 219, 190), Enum.Material.SmoothPlastic)
	gaugeFace.Shape = Enum.PartType.Cylinder
	gaugeFace.CanCollide = false
	local needle = part(model, "Level 2 Valve Pressure Gauge Needle",
		baseCFrame * CFrame.new(4.75, 11.1, -1.32) * CFrame.Angles(0, 0, -.58),
		Vector3.new(.22, 1.65, .22), Color3.fromRGB(108, 29, 25), Enum.Material.Metal)
	needle.CanCollide = false

	local statusLight = part(model, "Level 2 Valve Amber Status Lamp",
		baseCFrame * CFrame.new(-4.8, 14.15, -.7), Vector3.new(1.55, 1.55, 1.55),
		Color3.fromRGB(236, 178, 72), Enum.Material.Neon)
	statusLight.Shape = Enum.PartType.Ball
	statusLight.CanCollide = false
	local statusGlow = Instance.new("PointLight")
	statusGlow.Name = "Level 2 Valve Status Beacon"
	statusGlow.Color = statusLight.Color
	statusGlow.Brightness = .9
	statusGlow.Range = 22
	statusGlow.Shadows = false
	statusGlow.Parent = statusLight

	local signCFrame = baseCFrame * CFrame.new(0, 18.1, .25)
	local sign = part(model, "Level 2 Valve Number Sign", signCFrame,
		Vector3.new(13.5, 4.2, .55), Color3.fromRGB(43, 62, 65), Enum.Material.Metal)
	sign.CanCollide = false
	local signGui = Instance.new("SurfaceGui")
	signGui.Name = "Level 2 Valve Number Sign Surface"
	signGui.Face = Enum.NormalId.Front
	signGui.CanvasSize = Vector2.new(650, 200)
	signGui.Parent = sign
	local signText = Instance.new("TextLabel")
	signText.Name = "Level 2 Valve Number Text"
	signText.Size = UDim2.fromScale(1, 1)
	signText.BackgroundTransparency = 1
	signText.Text = string.format("PRESSURE VALVE  %d", index)
	signText.TextColor3 = Color3.fromRGB(244, 236, 202)
	signText.TextStrokeColor3 = Color3.fromRGB(16, 30, 33)
	signText.TextStrokeTransparency = .3
	signText.TextScaled = true
	signText.Font = Enum.Font.GothamBold
	signText.Parent = signGui

	local promptMount = part(model, "Level 2 Valve Interaction Point",
		wheelCenter * CFrame.new(0, 0, -1.45), Vector3.new(1.4, 1.4, 1.4),
		C.Void, Enum.Material.SmoothPlastic, 1)
	promptMount.CanCollide = false
	promptMount.CanTouch = false
	promptMount.CanQuery = false
	local prompt = Instance.new("ProximityPrompt")
	prompt.Name = "Level 2 Valve Prompt"
	prompt.ActionText = "TURN PRESSURE VALVE"
	prompt.ObjectText = "Pressure valve " .. index
	prompt.HoldDuration = Configuration.ValveHoldDuration
	prompt.MaxActivationDistance = Configuration.ValvePromptDistance
	prompt.RequiresLineOfSight = false
	prompt.KeyboardKeyCode = Enum.KeyCode.E
	prompt.Parent = promptMount

	model.PrimaryPart = platform
	CollectionService:AddTag(model, "Level2Valve")
	return {
		Model = model,
		Prompt = prompt,
		Wheel = pivot,
		WheelAssembly = wheelAssembly,
		StatusLight = statusLight,
		StatusGlow = statusGlow,
		Index = index,
	}
end

local function directionVector(side)
	if side == "North" then return Vector3.new(0, 0, -1) end
	if side == "South" then return Vector3.new(0, 0, 1) end
	if side == "West" then return Vector3.new(-1, 0, 0) end
	return Vector3.new(1, 0, 0)
end

local function bezier(p0, p1, p2, p3, t)
	local u = 1 - t
	return p0 * (u ^ 3) + p1 * (3 * u * u * t) + p2 * (3 * u * t * t) + p3 * (t ^ 3)
end

local function makeExitTube(parent, exitRoom, side)
	local center = roomCenter(exitRoom)
	local outward = directionVector(side)
	for step = 1, 7 do
		local position = center + outward * (step * 3 - 10) + Vector3.new(0, step * 1.1 - .5, 0)
		local size = math.abs(outward.X) > 0 and Vector3.new(4, 1, 15) or Vector3.new(15, 1, 4)
		tiledPart(parent, "Level 2 Exit Slide Entry Step", CFrame.new(position), size, C.TileWarm,
			{Enum.NormalId.Top}, 8)
	end

	local p0 = center + outward * (Configuration.CellSize * .42) + Vector3.new(0, 9, 0)
	local p1 = p0 + outward * 44 + Vector3.new(0, 1, 0)
	local p2 = p0 + outward * 94 + Vector3.new(0, -13, 0)
	local p3 = p0 + outward * 142 + Vector3.new(0, -27, 0)
	local radius = 7.25
	local sides = 10
	local segments = 32
	local arcWidth = 2 * radius * math.sin(math.pi / sides) * 1.16

	for segment = 1, segments do
		local t0, t1 = (segment - 1) / segments, segment / segments
		local a, b = bezier(p0, p1, p2, p3, t0), bezier(p0, p1, p2, p3, t1)
		local middle = (a + b) * .5
		local length = (b - a).Magnitude
		local base = CFrame.lookAt(middle, b, Vector3.yAxis)
		for sideIndex = 0, sides - 1 do
			local angle = sideIndex * math.pi * 2 / sides
			local offset = Vector3.new(math.cos(angle) * radius, math.sin(angle) * radius, 0)
			local panelCFrame = base * CFrame.new(offset) * CFrame.Angles(0, 0, angle - math.pi * .5)
			local panel = part(parent, "Level 2 Exit Slide Tube Panel", panelCFrame,
				Vector3.new(arcWidth, .72, length + 2), C.TileCool, Enum.Material.SmoothPlastic)
			panel.CustomPhysicalProperties = PhysicalProperties.new(.7, .08, .05, 1, 1)
			addTexture(panel, {Enum.NormalId.Top, Enum.NormalId.Bottom}, 8)
		end
	end

	local gateDirection = (p1 - p0).Unit
	local gate = part(parent, "Level 2 Exit Slide Locked Gate", CFrame.lookAt(p0, p0 + gateDirection),
		Vector3.new(radius * 1.85, radius * 1.85, 1.2), C.DarkGrout, Enum.Material.Metal, .08)
	gate.CanCollide = true
	local gateLight = part(parent, "Level 2 Exit Slide Status Light", gate.CFrame * CFrame.new(0, radius + 1.5, -1),
		Vector3.new(8, 1, 1), C.TileWarm, Enum.Material.Neon)
	gateLight.CanCollide = false

	local catchCenter = p3 + outward * 16 + Vector3.new(0, 4, 0)
	local catchSize = 34
	tiledPart(parent, "Level 2 Exit Catch Floor", CFrame.new(catchCenter + Vector3.new(0, -5, 0)),
		Vector3.new(catchSize, 1.5, catchSize), C.TileWarm, {Enum.NormalId.Top}, 9)
	tiledPart(parent, "Level 2 Exit Catch Ceiling", CFrame.new(catchCenter + Vector3.new(0, 13, 0)),
		Vector3.new(catchSize, 1.5, catchSize), C.TileCool, {Enum.NormalId.Bottom}, 9)
	for _, data in ipairs({
		{Vector3.new(-catchSize * .5, 4, 0), Vector3.new(1.5, 18, catchSize)},
		{Vector3.new(catchSize * .5, 4, 0), Vector3.new(1.5, 18, catchSize)},
		{Vector3.new(0, 4, -catchSize * .5), Vector3.new(catchSize, 18, 1.5)},
		{Vector3.new(0, 4, catchSize * .5), Vector3.new(catchSize, 18, 1.5)},
	}) do
		tiledPart(parent, "Level 2 Exit Catch Wall", CFrame.new(catchCenter + data[1]), data[2], C.TileCool, nil, 9)
	end

	local trigger = part(parent, "Level 2 Exit Completion Trigger", CFrame.new(catchCenter),
		Vector3.new(22, 12, 22), C.Emergency, Enum.Material.ForceField, 1)
	trigger.CanCollide = false
	trigger.CanTouch = true
	local safeSpawn = part(parent, "Level 2 Escaped Player Safe Spawn", CFrame.new(catchCenter + Vector3.new(0, -3.5, 0)),
		Vector3.new(4, .2, 4), C.Emergency, Enum.Material.Neon, 1)
	safeSpawn.CanCollide = false
	return {Gate = gate, GateLight = gateLight, Trigger = trigger, SafeSpawn = safeSpawn, EndPosition = catchCenter}
end

local function makeCompatibilityArrival(parent, arrivalPosition)
	local marker = part(parent, "Level 2 Arrival Spawn", CFrame.new(arrivalPosition + Vector3.new(0, 3, 0)),
		Vector3.new(5, .2, 5), C.TileWarm, Enum.Material.Neon, 1)
	marker.CanCollide = false
	marker.CanTouch = false

	local elevator = Instance.new("Model")
	elevator.Name = "Elevator"
	elevator.Parent = workspace
	local shell = tiledPart(elevator, "Level 2 Arrival Elevator Shell", CFrame.new(arrivalPosition + Vector3.new(0, 5, 0)),
		Vector3.new(18, 10, 18), C.TileWarm, nil, 9)
	shell.Transparency = 1
	shell.CanCollide = false
	local doorLeft = part(elevator, "DoorL", CFrame.new(arrivalPosition + Vector3.new(-4.5, 5, 8.8)),
		Vector3.new(8.5, 10, .6), C.Metal, Enum.Material.Metal, 1)
	local doorRight = part(elevator, "DoorR", CFrame.new(arrivalPosition + Vector3.new(4.5, 5, 8.8)),
		Vector3.new(8.5, 10, .6), C.Metal, Enum.Material.Metal, 1)
	doorLeft.CanCollide, doorRight.CanCollide = false, false
	elevator.PrimaryPart = shell

	local function compatibilityMarker(name, position)
		local object = part(workspace, name, CFrame.new(position), Vector3.new(4, .2, 4), C.TileWarm, Enum.Material.Neon, 1)
		object.CanCollide = false
		object.CanTouch = false
		object:SetAttribute("Level2_CompatibilityMarker", true)
		return object
	end
	local mazeStart = compatibilityMarker("MazeStart", arrivalPosition + Vector3.new(0, 3, 0))
	local elevatorSpawn = compatibilityMarker("ElevatorSpawn", arrivalPosition + Vector3.new(0, 3, 0))
	local entityStart = compatibilityMarker("EntityStart", arrivalPosition + Vector3.new(0, -40, 0))
	return {ArrivalSpawn = marker, Elevator = elevator, MazeStart = mazeStart, ElevatorSpawn = elevatorSpawn, EntityStart = entityStart}
end

function WorldBuilder.Build(layout, generation)
	Terrain.WaterColor = C.Water
	Terrain.WaterTransparency = .24
	Terrain.WaterReflectance = .08
	Terrain.WaterWaveSize = .035
	Terrain.WaterWaveSpeed = 1.65

	local world = Instance.new("Model")
	world.Name = "Level 2 Generated World"
	world:SetAttribute("Level2_Seed", layout.Seed)
	world:SetAttribute("Level2_Generation", generation)
	world:SetAttribute("Level2_GenerationAttempt", layout.Attempt)
	world:SetAttribute("Level2_Theme", Configuration.Theme)
	world:SetAttribute("Level2_OpenZoneCount", layout.OpenZoneCount or 0)
	world.Parent = workspace

	local geometry = folder(world, "Level 2 Geometry")
	local roomsFolder = folder(geometry, "Level 2 Rooms")
	local poolFolder = folder(geometry, "Level 2 Pools")
	local containment = folder(geometry, "Level 2 Containment")
	local objectiveFolder = folder(world, "Level 2 Objectives")
	local lightingFolder = folder(world, "Level 2 Lighting")
	local navigationFolder = folder(world, "Level 2 Navigation")
	local soundPointsFolder = folder(world, "Level 2 Sound Points")

	local mapSize = Configuration.GridSize * Configuration.CellSize
	local floor = tiledPart(containment, "Level 2 Sealed Foundation", CFrame.new(0, -27, 0),
		Vector3.new(mapSize + 10, 4, mapSize + 10), C.DarkGrout, {Enum.NormalId.Top}, 12)
	floor.CanCollide = true
	local roof = tiledPart(containment, "Level 2 Sealed Ceiling", CFrame.new(0, Configuration.WallHeight + 2, 0),
		Vector3.new(mapSize + 10, 4, mapSize + 10), C.TileCool, {Enum.NormalId.Bottom}, 12)
	roof.CanCollide = true

	for roomIndex, room in ipairs(layout.Rooms) do
		local center = roomCenter(room)
		local roomModel = Instance.new("Model")
		roomModel.Name = room.Id .. " " .. room.Archetype
		roomModel:SetAttribute("Level2_RoomRole", room.Role)
		roomModel:SetAttribute("Level2_PoolType", room.PoolType)
		roomModel:SetAttribute("Level2_Archetype", room.Archetype)
		roomModel:SetAttribute("Level2_Orientation", room.Orientation)
		roomModel:SetAttribute("Level2_ConnectionCount", room.ConnectionCount)
		roomModel:SetAttribute("Level2_GraphDepth", room.GraphDepth)
		roomModel:SetAttribute("Level2_SpaceType", room.SpaceType or "Standard")
		roomModel:SetAttribute("Level2_ZoneId", room.ZoneId or 0)
		roomModel:SetAttribute("Level2_LandmarkKind", room.LandmarkKind or "")
		roomModel:SetAttribute("Level2_LandmarkSeed", room.LandmarkSeed or 0)
		roomModel:SetAttribute("Level2_SlideCount", room.SlideCount or 0)
		roomModel:SetAttribute("Level2_OpenNorth", room.OpenSides and room.OpenSides.North or false)
		roomModel:SetAttribute("Level2_OpenEast", room.OpenSides and room.OpenSides.East or false)
		roomModel:SetAttribute("Level2_OpenSouth", room.OpenSides and room.OpenSides.South or false)
		roomModel:SetAttribute("Level2_OpenWest", room.OpenSides and room.OpenSides.West or false)
		roomModel.Parent = roomsFolder

		makeRoomFloor(roomModel, room, center)
		makeRoomInterior(poolFolder, room, center)
		if room.PoolType == "Children" then
			makeKidsPoolroomLandmark(roomModel, room, center)
		end

		local half = Configuration.CellSize * .5
		local northExit = room == layout.Exit and layout.ExitSide == "North"
		local westExit = room == layout.Exit and layout.ExitSide == "West"
		if not (room.OpenSides and room.OpenSides.North) then
			makeGapWall(roomModel, "Level 2 North Room Wall", center + Vector3.new(0, 0, -half),
				Configuration.CellSize, true, room.Connections.North or northExit)
		end
		if not (room.OpenSides and room.OpenSides.West) then
			makeGapWall(roomModel, "Level 2 West Room Wall", center + Vector3.new(-half, 0, 0),
				Configuration.CellSize, false, room.Connections.West or westExit)
		end
		if room.Z == Configuration.GridSize then
			makeGapWall(roomModel, "Level 2 South Boundary Wall", center + Vector3.new(0, 0, half),
				Configuration.CellSize, true, room == layout.Exit and layout.ExitSide == "South")
		end
		if room.X == Configuration.GridSize then
			makeGapWall(roomModel, "Level 2 East Boundary Wall", center + Vector3.new(half, 0, 0),
				Configuration.CellSize, false, room == layout.Exit and layout.ExitSide == "East")
		end

		makeRoomLights(lightingFolder, room, center, roomIndex)
		if not (room.OpenSides and room.OpenSides.North) and (roomIndex % 3 == 0 or room.Role ~= "Pool") then
			makeWallPanel(lightingFolder, center, roomIndex)
		end
		local node = part(navigationFolder, "Level 2 Navigation Node " .. roomIndex,
			CFrame.new(center + Vector3.new(0, 1, 0)), Vector3.new(2, .2, 2), C.Emergency, Enum.Material.Neon, 1)
		node.CanCollide = false
		node.CanTouch = false
		node:SetAttribute("Level2_RoomId", room.Id)
		local soundPoint = part(soundPointsFolder, "Level 2 Ambient Sound Point " .. roomIndex,
			CFrame.new(center + Vector3.new(0, 7, 0)), Vector3.new(.2, .2, .2), C.Void, Enum.Material.SmoothPlastic, 1)
		soundPoint.CanCollide = false
		soundPoint.CanTouch = false
	end

	local exitCenter = roomCenter(layout.Exit)
	local outerHalf = mapSize * .5 + 4
	local exitOffset = math.abs(directionVector(layout.ExitSide).X) > 0 and exitCenter.Z or exitCenter.X
	makeGapWall(containment, "Level 2 Outer North Containment Wall", Vector3.new(0, 0, -outerHalf),
		mapSize + 16, true, layout.ExitSide == "North", Configuration.WallHeight + 8, 8, exitOffset, -29)
	makeGapWall(containment, "Level 2 Outer South Containment Wall", Vector3.new(0, 0, outerHalf),
		mapSize + 16, true, layout.ExitSide == "South", Configuration.WallHeight + 8, 8, exitOffset, -29)
	makeGapWall(containment, "Level 2 Outer West Containment Wall", Vector3.new(-outerHalf, 0, 0),
		mapSize + 16, false, layout.ExitSide == "West", Configuration.WallHeight + 8, 8, exitOffset, -29)
	makeGapWall(containment, "Level 2 Outer East Containment Wall", Vector3.new(outerHalf, 0, 0),
		mapSize + 16, false, layout.ExitSide == "East", Configuration.WallHeight + 8, 8, exitOffset, -29)

	local valves = {}
	for index, room in ipairs(layout.Valves) do valves[index] = makeValve(objectiveFolder, room, index) end
	local exit = makeExitTube(geometry, layout.Exit, layout.ExitSide)
	local arrival = makeCompatibilityArrival(world, roomCenter(layout.Arrival))

	local slideReach = Configuration.GridSize * Configuration.CellSize * .5 + 210
	local terrainSize = Vector3.new(mapSize + 430, 90, mapSize + 430)
	local terrainCenter = Vector3.new(0, -8, 0)
	world:SetAttribute("Level2_TerrainCenter", terrainCenter)
	world:SetAttribute("Level2_TerrainSize", terrainSize)
	world:SetAttribute("Level2_BoundsRadius", slideReach)

	return {
		World = world,
		Layout = layout,
		Valves = valves,
		Exit = exit,
		Arrival = arrival,
		TerrainCenter = terrainCenter,
		TerrainSize = terrainSize,
		Generation = generation,
	}
end

return WorldBuilder
