local Players = game:GetService("Players")
local ReplicatedStorage = game:GetService("ReplicatedStorage")
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
	local y = Configuration.WallHeight - .65
	panelSize = panelSize or Vector3.new(28, .55, 10)
	local fixtureCFrame = CFrame.new(center.X, y, center.Z) * CFrame.Angles(0, yaw or 0, 0)
	local frame = part(parent, "Level 2 Ceiling Light Frame " .. index,
		fixtureCFrame, panelSize, C.Metal, Enum.Material.Metal)
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
	return frame, diffuser
end

local function makeRoomLights(parent, room, center, index)
	local archetype = room.Archetype or ""
	local eastWest = room.Orientation == "EastWest"
	local yaw = eastWest and 0 or math.pi * .5
	if archetype == "Grand Column Hall" or archetype == "Pillar Basin" then
		for row = -1, 1, 2 do
			for column = -1, 1, 2 do
				local offset = eastWest and Vector3.new(column * 20, 0, row * 16) or Vector3.new(row * 16, 0, column * 20)
				makeCeilingPanel(parent, center + offset, index .. " Grand " .. row .. " " .. column, Vector3.new(30, .55, 5), yaw)
			end
		end
	elseif archetype == "Long Gallery" or archetype == "Flooded Gallery" or archetype == "Exit Gallery" then
		local side = eastWest and Vector3.new(0, 0, 15) or Vector3.new(15, 0, 0)
		makeCeilingPanel(parent, center - side, index .. " Gallery A", Vector3.new(42, .55, 5), yaw)
		makeCeilingPanel(parent, center + side, index .. " Gallery B", Vector3.new(42, .55, 5), yaw)
	elseif archetype == "Arch Crypt" or archetype == "Vaulted Passage" then
		for offset = -24, 24, 24 do
			local shift = eastWest and Vector3.new(offset, 0, 0) or Vector3.new(0, 0, offset)
			makeCeilingPanel(parent, center + shift, index .. " Vault " .. offset, Vector3.new(14, .55, 7), yaw)
		end
	else
		local shift = eastWest and Vector3.new(20, 0, 0) or Vector3.new(0, 0, 20)
		makeCeilingPanel(parent, center - shift, index .. " A", Vector3.new(25, .55, 7), yaw)
		makeCeilingPanel(parent, center + shift, index .. " B", Vector3.new(25, .55, 7), yaw)
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

local function makeArch(parent, center, alongX, index)
	local radius = 11
	for step = 0, 12 do
		local angle = math.pi * step / 12
		local side = math.cos(angle) * radius
		local y = 1 + math.sin(angle) * radius
		local position = alongX and center + Vector3.new(0, y, side) or center + Vector3.new(side, y, 0)
		local rib = part(parent, "Level 2 Tiled Arch " .. index, CFrame.new(position),
			alongX and Vector3.new(2.1, 2.1, 3.4) or Vector3.new(3.4, 2.1, 2.1), C.TileWarm)
		addTexture(rib, Enum.NormalId:GetEnumItems(), 7)
	end
	for _, side in ipairs({-radius, radius}) do
		local position = alongX and center + Vector3.new(0, 5.5, side) or center + Vector3.new(side, 5.5, 0)
		local support = tiledPart(parent, "Level 2 Tiled Arch Support " .. index, CFrame.new(position),
			alongX and Vector3.new(3.4, 11, 3.4) or Vector3.new(3.4, 11, 3.4), C.TileWarm, nil, 7)
		support.CanCollide = true
	end
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
		light.Brightness = .55
		light.Range = 20
		light.Angle = 110
		light.Shadows = false
		light.Parent = lightPart
	end
	local fill = Instance.new("PointLight")
	fill.Name = "Level 2 Porthole Fill Light"
	fill.Color = C.Light
	fill.Brightness = .18
	fill.Range = 12
	fill.Shadows = false
	fill.Parent = diffuser
end

local function makeLowSoffit(parent, center, alongX, index)
	local size = alongX and Vector3.new(34, 3, Configuration.CellSize - 18) or Vector3.new(Configuration.CellSize - 18, 3, 34)
	local soffit = tiledPart(parent, "Level 2 Low Ceiling Soffit " .. index,
		CFrame.new(center + Vector3.new(0, Configuration.WallHeight - 4.5, 0)), size, C.TileWarm,
		{Enum.NormalId.Bottom, Enum.NormalId.Front, Enum.NormalId.Back}, 7)
	soffit.CanCollide = true
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
		elseif archetype == "Atrium Landing" or archetype == "Arrival Gallery" then
			for _, offset in ipairs({-20, 20}) do
				local position = eastWest and center + Vector3.new(offset, 0, -21) or center + Vector3.new(-21, 0, offset)
				makeColumn(parent, position, Configuration.WallHeight - 2)
			end
			local a = eastWest and center + Vector3.new(-31, 0, 27) or center + Vector3.new(27, 0, -31)
			local b = eastWest and center + Vector3.new(31, 0, 27) or center + Vector3.new(27, 0, 31)
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
		for _, offset in ipairs({Vector3.new(-22, 0, -20), Vector3.new(22, 0, -20), Vector3.new(-22, 0, 20), Vector3.new(22, 0, 20)}) do
			makeColumn(parent, center + offset, Configuration.WallHeight - 2)
		end
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
	elseif archetype == "Arch Crypt" or archetype == "Vaulted Passage" then
		for index, offset in ipairs({-26, 0, 26}) do
			local position = eastWest and center + Vector3.new(offset, 0, 0) or center + Vector3.new(0, 0, offset)
			makeArch(parent, position, eastWest, room.Id .. " " .. index)
		end
	elseif archetype == "Sunken Pool" or archetype == "Grand Basin" then
		local bridge = makeBridge(parent, center, eastWest, outer, "Level 2 Sunken Pool Safety Walkway")
		local halfLength = outer * .5 - 3
		local a = eastWest and center + Vector3.new(-halfLength, 1, -5) or center + Vector3.new(-5, 1, -halfLength)
		local b = eastWest and center + Vector3.new(halfLength, 1, -5) or center + Vector3.new(-5, 1, halfLength)
		makeRail(parent, a, b, "Level 2 Sunken Pool")
		bridge:SetAttribute("Level2_DeepPoolSafetyRoute", true)
	elseif archetype == "Low Water Hall" then
		makeBridge(parent, center, eastWest, outer, "Level 2 Low Water Hall Walkway")
		makeLowSoffit(parent, center, eastWest, room.Id)
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

local function makeValve(parent, room, index)
	local center = roomCenter(room)
	local model = Instance.new("Model")
	model.Name = "Level 2 Pressure Valve " .. index
	model:SetAttribute("Level2_ValveIndex", index)
	model.Parent = parent
	local pedestal = tiledPart(model, "Level 2 Valve Pedestal", CFrame.new(center + Vector3.new(0, 2.2, 25)),
		Vector3.new(7, 4.4, 5), C.TileWarm, nil, 8)
	local hub = part(model, "Level 2 Valve Hub",
		pedestal.CFrame * CFrame.new(0, 0, -3.2) * CFrame.Angles(math.pi * .5, 0, 0),
		Vector3.new(1.2, 4.2, 4.2), C.Metal, Enum.Material.Metal)
	hub.Shape = Enum.PartType.Cylinder
	local wheel = part(model, "Level 2 Valve Wheel",
		pedestal.CFrame * CFrame.new(0, 0, -4.05) * CFrame.Angles(math.pi * .5, 0, 0),
		Vector3.new(.7, 6, 6), ({C.TileWarm, C.TileCool, Color3.fromRGB(191, 130, 115)})[index], Enum.Material.Metal)
	wheel.Shape = Enum.PartType.Cylinder
	local prompt = Instance.new("ProximityPrompt")
	prompt.Name = "Level 2 Valve Prompt"
	prompt.ActionText = "Turn pressure valve"
	prompt.ObjectText = "Pressure valve " .. index
	prompt.HoldDuration = 1.35
	prompt.MaxActivationDistance = 9
	prompt.RequiresLineOfSight = true
	prompt.Parent = wheel
	model.PrimaryPart = pedestal
	return {Model = model, Prompt = prompt, Wheel = wheel, Index = index}
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
		roomModel.Parent = roomsFolder

		makeRoomFloor(roomModel, room, center)
		makeRoomInterior(poolFolder, room, center)

		local half = Configuration.CellSize * .5
		local northExit = room == layout.Exit and layout.ExitSide == "North"
		local westExit = room == layout.Exit and layout.ExitSide == "West"
		makeGapWall(roomModel, "Level 2 North Room Wall", center + Vector3.new(0, 0, -half),
			Configuration.CellSize, true, room.Connections.North or northExit)
		makeGapWall(roomModel, "Level 2 West Room Wall", center + Vector3.new(-half, 0, 0),
			Configuration.CellSize, false, room.Connections.West or westExit)
		if room.Z == Configuration.GridSize then
			makeGapWall(roomModel, "Level 2 South Boundary Wall", center + Vector3.new(0, 0, half),
				Configuration.CellSize, true, room == layout.Exit and layout.ExitSide == "South")
		end
		if room.X == Configuration.GridSize then
			makeGapWall(roomModel, "Level 2 East Boundary Wall", center + Vector3.new(half, 0, 0),
				Configuration.CellSize, false, room == layout.Exit and layout.ExitSide == "East")
		end

		makeRoomLights(lightingFolder, room, center, roomIndex)
		if roomIndex % 4 == 0 or room.Role ~= "Pool" then makeWallPanel(lightingFolder, center, roomIndex) end
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
