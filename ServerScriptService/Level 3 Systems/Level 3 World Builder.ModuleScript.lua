--!strict
-- Level 3 World Builder
-- Builds a deliberately authored network of forgotten mall service spaces.

local Configuration = require(script.Parent:WaitForChild("Level 3 Configuration"))
local ReplicatedStorage = game:GetService("ReplicatedStorage")
local ServerStorage = game:GetService("ServerStorage")

local Builder = {}
local C = Configuration.Colors

local function contentTexture(slotName: string, fallback: string): string
	local assets = ReplicatedStorage:FindFirstChild("Level 3 Assets")
	local slot = assets and assets:FindFirstChild(slotName)
	if slot and slot:IsA("StringValue") and slot.Value ~= "" then return slot.Value end
	return fallback
end

local TEXTURES = {
	PartyCarpet = contentTexture("PartyCarpetTexture", Configuration.Textures.PartyCarpet),
	PartyCarpetNeon = contentTexture("PartyCarpetNeonTexture", Configuration.Textures.PartyCarpetNeon),
	PartyCarpetRed = contentTexture("PartyCarpetRedTexture", Configuration.Textures.PartyCarpetRed),
	CityCarpet = contentTexture("CityPlayCarpetTexture", Configuration.Textures.CityCarpet),
	PastelWallpaper = contentTexture("PastelWallpaperTexture", Configuration.Textures.PastelWallpaper),
	OrangeWall = contentTexture("OrangeWallTexture", Configuration.Textures.OrangeWall),
	ConfettiTablecloth = contentTexture("ConfettiTableclothTexture", Configuration.Textures.ConfettiTablecloth),
	StaffDoor = contentTexture("StaffDoorTexture", Configuration.Textures.StaffDoor),
	FinalExitDoor = contentTexture("FinalExitDoorTexture", Configuration.Textures.FinalExitDoor),
	KidsDrawingsAtlas = contentTexture("KidsDrawingsAtlasTexture", Configuration.Textures.KidsDrawingsAtlas),
	KidsNotesAtlas = contentTexture("KidsNotesAtlasTexture", Configuration.Textures.KidsNotesAtlas),
	CDCoversAtlas = contentTexture("CDCoversAtlasTexture", Configuration.Textures.CDCoversAtlas),
}

local function folder(parent: Instance, name: string): Folder
	local object = Instance.new("Folder")
	object.Name = name
	object.Parent = parent
	return object
end

local function part(parent: Instance, name: string, cframe: CFrame, size: Vector3,
	color: Color3, material: Enum.Material?, transparency: number?): Part
	local object = Instance.new("Part")
	object.Name = name
	object.Anchored = true
	object.CFrame = cframe
	object.Size = size
	object.Color = color
	object.Material = material or Enum.Material.SmoothPlastic
	object.Transparency = transparency or 0
	object.CanCollide = true
	object.CanTouch = false
	object.CanQuery = true
	object.TopSurface = Enum.SurfaceType.Smooth
	object.BottomSurface = Enum.SurfaceType.Smooth
	object.CastShadow = true
	object.Parent = parent
	return object
end

local function decorative(object: BasePart)
	object.CanCollide = false
	object.CanTouch = false
	object.CanQuery = false
	object.CastShadow = false
end

local function texture(object: BasePart, textureId: string, face: Enum.NormalId,
	studsU: number, studsV: number?, transparency: number?): Texture
	local image = Instance.new("Texture")
	image.Name = "Level 3 Surface Texture"
	image.Texture = textureId
	image.Face = face
	image.StudsPerTileU = studsU
	image.StudsPerTileV = studsV or studsU
	image.Transparency = transparency or 0
	image.Parent = object
	return image
end

local function roomById(id: string): {[string]: any}
	for _, room in ipairs(Configuration.Rooms) do
		if room.Id == id then return room end
	end
	error("Unknown Level 3 room: " .. id)
end

local function worldPosition(room: {[string]: any}, y: number?): Vector3
	return Configuration.WorldOrigin + Vector3.new(room.X, y or 0, room.Z)
end

local function roomHeight(room: {[string]: any}): number
	return tonumber(room.H) or Configuration.RoomHeight
end

local RED_PARTY_ROOMS = {PartyA = true, Records = true}
local NEON_PARTY_ROOMS = {PartyB = true, UtilityWest = true, CentralHall = true}

local function floorStyle(kind: string, roomId: string?): (Color3, Enum.Material, string?, number)
	if kind == "City" then
		return Color3.fromRGB(190, 188, 166), Enum.Material.Carpet, TEXTURES.CityCarpet, Configuration.TextureStuds.CityCarpet
	elseif kind == "Exit" then
		return Color3.fromRGB(70, 71, 66), Enum.Material.DiamondPlate, nil, 10
	elseif roomId and RED_PARTY_ROOMS[roomId] then
		return Color3.fromRGB(111, 31, 27), Enum.Material.Carpet, TEXTURES.PartyCarpetRed, Configuration.TextureStuds.PartyCarpetRed
	elseif roomId and NEON_PARTY_ROOMS[roomId] then
		return Color3.fromRGB(13, 17, 24), Enum.Material.Carpet, TEXTURES.PartyCarpetNeon, Configuration.TextureStuds.PartyCarpetNeon
	end
	return C.DarkCarpet, Enum.Material.Carpet, TEXTURES.PartyCarpet, Configuration.TextureStuds.PartyCarpet
end

local CITY_ROOMS = {
	BackOffice = true,
	BreakRoom = true,
	Maintenance = true,
	ChairStore = true,
	CityPlay = true,
	LostFound = true,
	Exit = true,
}

local BEIGE_ROOMS = CITY_ROOMS

local function usesWallpaper(room: {[string]: any}): boolean
	return BEIGE_ROOMS[room.Id] == true
end

local function wallColor(room: {[string]: any}): Color3
	return usesWallpaper(room) and Color3.fromRGB(220, 213, 187) or Color3.fromRGB(183, 78, 35)
end

local function lightTone(kind: string): Color3
	if kind == "Party" or kind == "PartyHall" then return Color3.fromRGB(255, 222, 181) end
	if kind == "Utility" or kind == "Maintenance" then return Color3.fromRGB(204, 222, 202) end
	if kind == "Signal" or kind == "Exit" then return Color3.fromRGB(185, 222, 215) end
	return Color3.fromRGB(235, 229, 198)
end

local function wallSegment(parent: Instance, name: string, cframe: CFrame, size: Vector3,
	color: Color3, wallpaperFace: Enum.NormalId?, wallpaper: boolean): BasePart
	local wall = part(parent, name, cframe, size, color,
		wallpaper and Enum.Material.SmoothPlastic or Enum.Material.Plaster)
	if wallpaper then wall.Reflectance = 0.08 end
	if wallpaper and wallpaperFace then
		texture(wall, TEXTURES.PastelWallpaper, wallpaperFace,
			Configuration.TextureStuds.Wallpaper, Configuration.TextureStuds.Wallpaper, 0.08)
	elseif wallpaperFace then
		-- Orange rooms retain their color identity while gaining subtle plaster
		-- wear, roller variation and removed-decoration pinholes.
		texture(wall, TEXTURES.OrangeWall, wallpaperFace,
			Configuration.TextureStuds.OrangeWall, Configuration.TextureStuds.OrangeWall, 0.28)
	end
	return wall
end

local function makeWall(parent: Instance, room: {[string]: any}, side: string, hasOpening: boolean)
	local origin = worldPosition(room)
	local h = roomHeight(room)
	local t = Configuration.WallThickness
	-- The room portal is the complete corridor cross-section. Its width and
	-- height therefore match every tunnel exactly instead of shrinking to an
	-- old door-sized opening at each room boundary.
	local doorW = Configuration.CorridorWidth
	local doorH = Configuration.CorridorHeight
	local color = wallColor(room)
	local wallpaper = usesWallpaper(room)
	local horizontal = side == "North" or side == "South"
	local length = horizontal and room.W or room.D
	local sign = (side == "East" or side == "South") and 1 or -1
	local face = horizontal and (side == "North" and Enum.NormalId.Back or Enum.NormalId.Front)
		or (side == "West" and Enum.NormalId.Right or Enum.NormalId.Left)
	local function cfAlong(offset: number, y: number): CFrame
		if horizontal then
			return CFrame.new(origin + Vector3.new(offset, y, sign * room.D * 0.5))
		end
		return CFrame.new(origin + Vector3.new(sign * room.W * 0.5, y, offset))
	end
	local function wallSize(segmentLength: number, height: number): Vector3
		return horizontal and Vector3.new(segmentLength, height, t) or Vector3.new(t, height, segmentLength)
	end
	if not hasOpening then
		wallSegment(parent, "Level 3 " .. side .. " Wall", cfAlong(0, h * 0.5),
			wallSize(length + t, h), color, face, wallpaper)
	else
		local sideLength = math.max(0.5, (length - doorW) * 0.5)
		local offset = doorW * 0.5 + sideLength * 0.5
		wallSegment(parent, "Level 3 " .. side .. " Wall A", cfAlong(-offset, h * 0.5),
			wallSize(sideLength + 0.1, h), color, face, wallpaper)
		wallSegment(parent, "Level 3 " .. side .. " Wall B", cfAlong(offset, h * 0.5),
			wallSize(sideLength + 0.1, h), color, face, wallpaper)
		local lintelHeight = h - doorH
		if lintelHeight > .05 then
			wallSegment(parent, "Level 3 " .. side .. " Lintel",
				cfAlong(0, doorH + lintelHeight * .5),
				wallSize(doorW, lintelHeight), color, face, wallpaper)
		end
	end
end

local function makeBaseboard(parent: Instance, room: {[string]: any})
	local p = worldPosition(room)
	local y = 0.55
	for _, data in ipairs({
		{CFrame.new(p + Vector3.new(0, y, -room.D * .5 + .7)), Vector3.new(room.W - 1.4, 1.1, .28)},
		{CFrame.new(p + Vector3.new(0, y, room.D * .5 - .7)), Vector3.new(room.W - 1.4, 1.1, .28)},
		{CFrame.new(p + Vector3.new(-room.W * .5 + .7, y, 0)), Vector3.new(.28, 1.1, room.D - 1.4)},
		{CFrame.new(p + Vector3.new(room.W * .5 - .7, y, 0)), Vector3.new(.28, 1.1, room.D - 1.4)},
	}) do
		local trim = part(parent, "Level 3 Baseboard", data[1], data[2], C.Trim, Enum.Material.WoodPlanks)
		decorative(trim)
	end
end

local function makeCeilingGrid(parent: Instance, room: {[string]: any})
	local p = worldPosition(room)
	local y = roomHeight(room) - 0.52
	local spacing = 8
	for x = -room.W * .5 + spacing, room.W * .5 - spacing, spacing do
		local seam = part(parent, "Level 3 Ceiling Grid", CFrame.new(p + Vector3.new(x, y, 0)),
			Vector3.new(.08, .04, room.D - 1.5), Color3.fromRGB(83, 79, 67), Enum.Material.Metal, .38)
		decorative(seam)
	end
	for z = -room.D * .5 + spacing, room.D * .5 - spacing, spacing do
		local seam = part(parent, "Level 3 Ceiling Grid", CFrame.new(p + Vector3.new(0, y, z)),
			Vector3.new(room.W - 1.5, .04, .08), Color3.fromRGB(83, 79, 67), Enum.Material.Metal, .38)
		decorative(seam)
	end
end

local function makeFixture(parent: Instance, position: Vector3, kind: string, index: number, dead: boolean): BasePart
	local frame = part(parent, "Level 3 Fluorescent Frame", CFrame.new(position),
		Vector3.new(7.5, .32, 2.4), Color3.fromRGB(85, 84, 75), Enum.Material.Metal)
	decorative(frame)
	local diffuser = part(parent, "Level 3 Fluorescent Diffuser", CFrame.new(position - Vector3.new(0, .20, 0)),
		Vector3.new(7.05, .14, 2.05), dead and Color3.fromRGB(92, 88, 72) or lightTone(kind),
		dead and Enum.Material.SmoothPlastic or Enum.Material.Neon, dead and .18 or .03)
	decorative(diffuser)
	if not dead then
		local light = Instance.new("SurfaceLight")
		light.Name = "Level 3 Fluorescent Light"
		light.Face = Enum.NormalId.Bottom
		light.Color = lightTone(kind)
		-- Broad, readable fluorescent spill.  The fixtures remain artificial and
		-- uneven, but the carpet/furniture must not collapse into black silhouettes
		-- on mobile displays.
		light.Brightness = (kind == "Party" or kind == "PartyHall") and 1.62 or 1.48
		light.Range = 34
		light.Angle = 128
		light.Shadows = false
		light.Parent = diffuser
		-- Roughly one in seven working fixtures receives independent client-side
		-- ballast instability. Timing stays random per client while the selected
		-- fixtures remain stable for the generated layout.
		if index % 7 == 0 then diffuser:SetAttribute("Level3_SubtleFlicker", true) end
	end
	return diffuser
end

local function makeRoomLights(parent: Instance, room: {[string]: any}, roomIndex: number)
	local p = worldPosition(room)
	local area = room.W * room.D
	local targetCount = math.clamp(math.floor(area / 1800) + 1, 1, 6)
	local columns = math.min(3, math.max(1, math.ceil(targetCount / 2)))
	local rows = math.min(2, math.max(1, math.ceil(targetCount / columns)))
	local n = 0
	for iz = 1, rows do
		for ix = 1, columns do
			if n >= targetCount then break end
			n += 1
			local x = (ix / (columns + 1) - .5) * room.W
			local z = (iz / (rows + 1) - .5) * room.D
			makeFixture(parent, p + Vector3.new(x, roomHeight(room) - .85, z),
				room.Kind, roomIndex * 10 + n, (roomIndex * 7 + n * 3) % 13 == 0)
		end
	end
end

local function furnitureTemplate(name: string): MeshPart?
	local assets = ServerStorage:FindFirstChild("Level3Assets")
	local templates = assets and assets:FindFirstChild("FurnitureTemplates")
	local object = templates and templates:FindFirstChild(name)
	return object and object:IsA("MeshPart") and object or nil
end

local TABLECLOTH_COLORS = {
	Color3.fromRGB(38, 153, 165),
	Color3.fromRGB(55, 130, 87),
	Color3.fromRGB(151, 49, 59),
	Color3.fromRGB(192, 112, 35),
	Color3.fromRGB(71, 72, 137),
}
local CHAIR_COLORS = {
	Color3.fromRGB(57, 87, 140),
	Color3.fromRGB(194, 157, 49),
	Color3.fromRGB(137, 45, 52),
	Color3.fromRGB(73, 129, 86),
	Color3.fromRGB(53, 48, 71),
}

local function cloneDecorMesh(templateName: string, parent: Instance, name: string,
	cframe: CFrame, size: Vector3?, color: Color3?): MeshPart?
	local template = furnitureTemplate(templateName)
	if not template then return nil end
	local object = template:Clone()
	object.Name = name
	object.Anchored = true
	object.CanCollide = false
	object.CanTouch = false
	object.CanQuery = false
	object.CastShadow = true
	if size then object.Size = size end
	if color then object.Color = color end
	object.CFrame = cframe
	object.Parent = parent
	return object
end

local function makeTable(parent: Instance, cframe: CFrame, party: boolean, chairs: number, styleIndex: number)
	local tableColor = TABLECLOTH_COLORS[(styleIndex - 1) % #TABLECLOTH_COLORS + 1]
	local tableMesh = cloneDecorMesh("FoldingTableTemplate", parent, "Level 3 Vetted Folding Table",
		cframe * CFrame.new(0, 1.72, 0), Vector3.new(11.2, 3.44, 4.35))
	if not tableMesh then
		tableMesh = part(parent, "Level 3 Folding Table", cframe * CFrame.new(0, 3, 0),
			Vector3.new(11.2, .5, 4.35), Color3.fromRGB(201, 198, 185), Enum.Material.SmoothPlastic)
		decorative(tableMesh)
	end
	-- Keep the detailed free mesh decorative, but add one simple invisible
	-- tabletop collider so players cannot walk through the banquet tables.
	local tableCollision = part(parent, "Level 3 Folding Table Collision", cframe * CFrame.new(0, 3.0, 0),
		Vector3.new(11.0, .48, 4.15), Color3.new(), Enum.Material.SmoothPlastic, 1)
	tableCollision:SetAttribute("Level3_TableCollision", true)
	tableCollision.CastShadow = false

	-- A thin top and four hanging skirts turn the clean folding-table mesh into
	-- a believable disposable party tablecloth without multiplying textures.
	local top = part(parent, "Level 3 Party Tablecloth Top", cframe * CFrame.new(0, 3.48, 0),
		Vector3.new(11.45, .12, 4.62), tableColor, Enum.Material.Fabric)
	decorative(top)
	texture(top, TEXTURES.ConfettiTablecloth, Enum.NormalId.Top,
		Configuration.TextureStuds.Tablecloth, Configuration.TextureStuds.Tablecloth, .34)
	-- Keep the folding legs and silhouette visible. The former four rigid skirt
	-- panels read as a solid colored box rather than a disposable tablecloth.
	chairs = math.clamp(math.ceil(chairs * .62), 2, 5)
	for chairIndex = 1, chairs do
		local side = chairIndex % 2 == 0 and 1 or -1
		local column = math.floor((chairIndex - 1) / 2)
		local columns = math.max(1, math.ceil(chairs / 2))
		local x = columns == 1 and 0 or (-3.8 + column * (7.6 / math.max(1, columns - 1)))
		-- Aim each chair's authored forward (-Z) at the table instead of relying
		-- on a side-dependent yaw. This remains correct when a whole table group
		-- is rotated or mirrored by the room dressing pass.
		local chairPosition = (cframe * CFrame.new(x, 2.28, side * 4.1)).Position
		local tableTarget = (cframe * CFrame.new(x, 2.28, 0)).Position
		local chairColor = CHAIR_COLORS[(chairIndex + styleIndex - 2) % #CHAIR_COLORS + 1]
		-- The imported chair template's seat/back convention matches Roblox
		-- LookVector. Point -Z directly at the tabletop; the old extra 180-degree
		-- rotation made every chair look away from its table.
		local chairCF = CFrame.lookAt(chairPosition, tableTarget)
		local chair = cloneDecorMesh("PlasticPartyChairTemplate", parent, "Level 3 Vetted Plastic Party Chair",
			chairCF, Vector3.new(2.55, 4.3, 2.58), chairColor)
		if chair then
			chair:SetAttribute("Level3_ChairTableTarget", tableTarget)
			chair:SetAttribute("Level3_ChairFacingDot", chair.CFrame.LookVector:Dot((tableTarget - chairPosition).Unit))
		end
		if not chair then
			local seat = part(parent, "Level 3 Party Chair", chairCF,
				Vector3.new(2.4, 4.2, 2.5), chairColor, Enum.Material.SmoothPlastic)
			decorative(seat)
			seat:SetAttribute("Level3_ChairTableTarget", tableTarget)
			seat:SetAttribute("Level3_ChairFacingDot", seat.CFrame.LookVector:Dot((tableTarget - chairPosition).Unit))
		end
	end
	return top
end

local function makeShelf(parent: Instance, cframe: CFrame, width: number)
	for _, y in ipairs({1.2, 4.1, 7.0}) do
		part(parent, "Level 3 Shelf", cframe * CFrame.new(0, y, 0),
			Vector3.new(width, .35, 2.4), C.Metal, Enum.Material.Metal)
	end
	for _, x in ipairs({-width * .5 + .3, width * .5 - .3}) do
		part(parent, "Level 3 Shelf Upright", cframe * CFrame.new(x, 4.1, 0),
			Vector3.new(.4, 8.2, 2.2), C.Metal, Enum.Material.Metal)
	end
end

local function makeBoxes(parent: Instance, base: CFrame, count: number)
	local colors = {Color3.fromRGB(133, 102, 66), Color3.fromRGB(156, 122, 76), Color3.fromRGB(107, 83, 59)}
	for i = 1, count do
		local row = math.floor((i - 1) / 4)
		local col = (i - 1) % 4
		local size = Vector3.new(2.4 + (i % 2) * .7, 2.1 + (i % 3) * .4, 2.6)
		part(parent, "Level 3 Storage Carton", base * CFrame.new(col * 3.3, size.Y * .5 + row * 2.9, 0),
			size, colors[(i - 1) % #colors + 1], Enum.Material.Cardboard)
	end
end

local function makeDesk(parent: Instance, cframe: CFrame, withCrt: boolean)
	part(parent, "Level 3 Office Desk", cframe * CFrame.new(0, 2.7, 0),
		Vector3.new(9, .6, 4), C.Wood, Enum.Material.WoodPlanks)
	for _, x in ipairs({-4, 4}) do
		part(parent, "Level 3 Desk Pedestal", cframe * CFrame.new(x, 1.35, 0),
			Vector3.new(1, 2.7, 3.4), C.Wood, Enum.Material.WoodPlanks)
	end
	if withCrt then
		part(parent, "Level 3 CRT Monitor", cframe * CFrame.new(1.6, 4.4, 0),
			Vector3.new(3.4, 2.7, 2.6), Color3.fromRGB(91, 87, 73), Enum.Material.SmoothPlastic)
		local screen = part(parent, "Level 3 CRT Screen", cframe * CFrame.new(1.6, 4.45, -1.33),
			Vector3.new(2.5, 1.7, .08), Color3.fromRGB(24, 31, 29), Enum.Material.Glass, .12)
		decorative(screen)
	end
end

local function segmentBetween(parent: Instance, name: string, a: Vector3, b: Vector3,
	thickness: number, color: Color3, transparency: number?): BasePart
	local direction = b - a
	local object = part(parent, name, CFrame.lookAt((a + b) * .5, b) * CFrame.Angles(math.pi * .5, 0, 0),
		Vector3.new(thickness, direction.Magnitude, thickness), color, Enum.Material.SmoothPlastic, transparency)
	decorative(object)
	return object
end

local function makeBalloonCluster(parent: Instance, position: Vector3, colorOffset: number, count: number?)
	local colors = {Color3.fromRGB(187, 42, 52), Color3.fromRGB(40, 104, 169),
		Color3.fromRGB(55, 139, 91), Color3.fromRGB(210, 159, 37), Color3.fromRGB(119, 61, 151),
		Color3.fromRGB(215, 94, 38)}
	local balloonCount = count or 5
	local anchor = position + Vector3.new(0, .35, 0)
	for balloonIndex = 1, balloonCount do
		-- Irrational-looking deterministic offsets keep every bouquet asymmetrical
		-- without relying on global random state.
		local angle = balloonIndex * 2.399963 + colorOffset * .37
		local radius = 1.0 + ((balloonIndex * 17 + colorOffset * 11) % 8) * .12
		local height = 6.4 + ((balloonIndex * 13 + colorOffset * 7) % 9) * .27
		local p = position + Vector3.new(math.cos(angle) * radius, height, math.sin(angle) * radius)
		local color = colors[(balloonIndex + colorOffset - 1) % #colors + 1]
		local balloon = part(parent, "Level 3 Oval Party Balloon", CFrame.new(p),
			Vector3.new(1.72, 2.36, 1.72), color, Enum.Material.SmoothPlastic, .025)
		balloon.Shape = Enum.PartType.Ball
		balloon.Reflectance = .06
		decorative(balloon)

		local knot = part(parent, "Level 3 Balloon Knot", CFrame.new(p - Vector3.new(0, 1.27, 0))
			* CFrame.Angles(0, 0, math.rad(45)), Vector3.new(.22, .30, .22),
			color:Lerp(Color3.new(0, 0, 0), .12), Enum.Material.SmoothPlastic)
		knot.Shape = Enum.PartType.Ball
		decorative(knot)
		segmentBetween(parent, "Level 3 Balloon String", p - Vector3.new(0, 1.4, 0),
			anchor, .025, Color3.fromRGB(118, 115, 106), .18)
	end
end

local function makeBunting(parent: Instance, room: {[string]: any})
	local p = worldPosition(room)
	local colors = {C.Burgundy, C.MutedBlue, C.FadedGreen, Color3.fromRGB(184, 139, 41), C.DustyPeach}
	local cordY = roomHeight(room) - 1.18
	local z = room.D * .12
	local cord = part(parent, "Level 3 Bunting Cord", CFrame.new(p + Vector3.new(0, cordY, z)),
		Vector3.new(room.W - 7, .035, .035), Color3.fromRGB(75, 68, 59), Enum.Material.SmoothPlastic)
	decorative(cord)
	local halfSpan = room.W * .5 - 4.5
	local flagIndex = 0
	for x = -halfSpan, halfSpan, 6.2 do
		flagIndex += 1
		local normalized = math.abs(x) / math.max(halfSpan, 1)
		local sag = (1 - normalized) * .32
		local flag = Instance.new("WedgePart")
		flag.Name = "Level 3 Triangular Bunting Flag"
		flag.Anchored = true
		flag.CFrame = CFrame.new(p + Vector3.new(x, cordY - .72 - sag, z))
			* CFrame.Angles(0, math.rad(90), 0)
		flag.Size = Vector3.new(.055, 1.28, 1.78)
		flag.Color = colors[(flagIndex + math.floor(room.X / 100)) % #colors + 1]
		flag.Material = Enum.Material.Fabric
		flag.TopSurface = Enum.SurfaceType.Smooth
		flag.BottomSurface = Enum.SurfaceType.Smooth
		decorative(flag)
		flag.Parent = parent
	end
end

-- Roblox delivers both atlases at 1024x1024. Drawings V2 is a 4x4 grid
-- (16 unique sheets: eight wholesome, eight subtly disturbing); notes remains 2x2.
local ROOM_ART_COUNTS = {
	BackOffice = 8,
	BreakRoom = 5,
	Maintenance = 9,
	LoadingStore = 5,
	PartyA = 8,
	ChairStore = 6,
	CityPlay = 10,
	LostFound = 5,
	PartyB = 8,
	Records = 6,
}
local BUNTING_ROOMS = {
	BackOffice = true,
	LoadingStore = true,
	PartyA = true,
	CityPlay = true,
	PartyB = true,
}

local function makeKidsWallPaper(parent: Instance, name: string, position: Vector3, inward: Vector3,
	size: Vector2, textureId: string, atlasCell: number, rotation: number, seed: number)
	local paperCF = CFrame.lookAt(position, position + inward) * CFrame.Angles(0, 0, rotation)
	local paperColors = {
		Color3.fromRGB(238, 231, 201),
		Color3.fromRGB(224, 232, 216),
		Color3.fromRGB(233, 216, 188),
		Color3.fromRGB(216, 225, 232),
	}
	local paper = part(parent, name, paperCF, Vector3.new(size.X, size.Y, .026),
		paperColors[seed % #paperColors + 1], Enum.Material.SmoothPlastic)
	decorative(paper)
	paper.CanQuery = true
	paper:SetAttribute("Level3_KidsWallArt", true)
	paper:SetAttribute("Level3_AtlasCell", atlasCell)

	local surface = Instance.new("SurfaceGui")
	surface.Name = "Level 3 Kids Wall Art Surface"
	surface.Face = Enum.NormalId.Front
	surface.AlwaysOnTop = false
	surface.LightInfluence = .72
	surface.SizingMode = Enum.SurfaceGuiSizingMode.PixelsPerStud
	surface.PixelsPerStud = 72
	surface.ZOffset = 1
	surface.Parent = paper

	local image = Instance.new("ImageLabel")
	image.Name = "Level 3 Kids Wall Art Image"
	image.BackgroundTransparency = 1
	image.BorderSizePixel = 0
	image.Size = UDim2.fromScale(1, 1)
	image.Image = textureId
	local gridSize = textureId == TEXTURES.KidsDrawingsAtlas and 4 or 2
	local cellSize = 1024 / gridSize
	image.ImageRectSize = Vector2.new(cellSize, cellSize)
	local cell = (atlasCell - 1) % (gridSize * gridSize)
	image.ImageRectOffset = Vector2.new((cell % gridSize) * cellSize, math.floor(cell / gridSize) * cellSize)
	if textureId == TEXTURES.KidsDrawingsAtlas then
		paper:SetAttribute("Level3_DrawingMood", cell < 8 and "Wholesome" or "Disturbing")
	end
	image.ScaleType = Enum.ScaleType.Fit
	image.Parent = surface

	for tapeIndex, side in ipairs({-1, 1}) do
		local tape = part(parent, "Level 3 Kids Drawing Tape",
			paperCF * CFrame.new(side * size.X * .31, size.Y * .47, -.025)
				* CFrame.Angles(0, 0, math.rad((seed + tapeIndex * 7) % 9 - 4)),
			Vector3.new(math.min(.60, size.X * .22), .11, .014),
			Color3.fromRGB(205, 185, 126), Enum.Material.SmoothPlastic, .13)
		decorative(tape)
	end
end

local function makeRoomWallDecor(parent: Instance, room: {[string]: any},
	openings: {[string]: boolean}, roomIndex: number)
	local count = ROOM_ART_COUNTS[room.Id] or 0
	if count <= 0 then return end
	local p = worldPosition(room)
	local h = roomHeight(room)
	for artIndex = 1, count do
		local sideIndex = (roomIndex * 5 + artIndex * 3) % 4 + 1
		local side = ({"North", "South", "West", "East"})[sideIndex]
		local horizontal = side == "North" or side == "South"
		local span = horizontal and room.W or room.D
		local alongFraction = (((roomIndex * 19 + artIndex * 37) % 61) / 60 - .5) * .64
		if openings[side] and math.abs(alongFraction) < .14 then
			alongFraction = alongFraction < 0 and -.23 or .23
		end
		local along = math.clamp(alongFraction * span, -span * .39, span * .39)
		local y = math.min(h - 2.15, 3.45 + ((roomIndex * 11 + artIndex * 17) % 29) / 29 * 3.3)
		local position: Vector3
		local inward: Vector3
		local wallInset = Configuration.WallThickness * .5 + .015
		if side == "North" then
			position, inward = p + Vector3.new(along, y, -room.D * .5 + wallInset), Vector3.new(0, 0, 1)
		elseif side == "South" then
			position, inward = p + Vector3.new(along, y, room.D * .5 - wallInset), Vector3.new(0, 0, -1)
		elseif side == "West" then
			position, inward = p + Vector3.new(-room.W * .5 + wallInset, y, along), Vector3.new(1, 0, 0)
		else
			position, inward = p + Vector3.new(room.W * .5 - wallInset, y, along), Vector3.new(-1, 0, 0)
		end
		local isNote = (artIndex + roomIndex) % 3 == 0
		local width = isNote and (2.1 + (artIndex % 2) * .35) or (3.15 + (artIndex % 3) * .34)
		local height = isNote and (2.0 + ((artIndex + 1) % 2) * .3) or (2.85 + ((artIndex + 1) % 3) * .28)
		local atlas = isNote and TEXTURES.KidsNotesAtlas or TEXTURES.KidsDrawingsAtlas
		-- Alternate the drawing half deterministically: cells 1-8 are innocent,
		-- cells 9-16 retain a normal childlike style with one unsettling detail.
		local disturbing = (roomIndex + artIndex) % 2 == 0
		local drawingCell = (disturbing and 8 or 0) + ((roomIndex * 3 + artIndex * 5) % 8) + 1
		local atlasCell = isNote and ((roomIndex * 3 + artIndex) % 4 + 1) or drawingCell
		makeKidsWallPaper(parent,
			isNote and "Level 3 Kids Notes" or "Level 3 Child Drawing",
			position, inward, Vector2.new(width, height), atlas,
			atlasCell,
			math.rad(((roomIndex * 13 + artIndex * 7) % 11) - 5),
			roomIndex * 17 + artIndex)
	end
	if BUNTING_ROOMS[room.Id] then makeBunting(parent, room) end
end

local function makeCorridorWallDecor(parent: Instance, startPoint: Vector3, endPoint: Vector3,
	horizontal: boolean, corridorIndex: number)
	if corridorIndex % 3 == 0 then return end
	local count = corridorIndex % 5 == 0 and 2 or 1
	for artIndex = 1, count do
		local alpha = count == 1 and (.30 + ((corridorIndex * 13) % 39) / 100) or (.27 + artIndex * .25)
		local side = ((corridorIndex + artIndex) % 2 == 0) and 1 or -1
		local position = startPoint:Lerp(endPoint, alpha)
		local inward: Vector3
		local wallInset = Configuration.CorridorWidth * .5 - Configuration.WallThickness * .5 - .015
		if horizontal then
			position += Vector3.new(0, 4.15 + ((corridorIndex + artIndex) % 3) * .72, side * wallInset)
			inward = Vector3.new(0, 0, -side)
		else
			position += Vector3.new(side * wallInset, 4.15 + ((corridorIndex + artIndex) % 3) * .72, 0)
			inward = Vector3.new(-side, 0, 0)
		end
		local isNote = (corridorIndex + artIndex) % 3 == 0
		local disturbing = (corridorIndex + artIndex) % 2 == 0
		local drawingCell = (disturbing and 8 or 0) + ((corridorIndex * 5 + artIndex * 3) % 8) + 1
		makeKidsWallPaper(parent,
			isNote and "Level 3 Corridor Kids Notes" or "Level 3 Corridor Child Drawing",
			position, inward,
			isNote and Vector2.new(2.05, 2.15) or Vector2.new(2.7, 2.55),
			isNote and TEXTURES.KidsNotesAtlas or TEXTURES.KidsDrawingsAtlas,
			isNote and ((corridorIndex + artIndex * 2) % 4 + 1) or drawingCell,
			math.rad(((corridorIndex * 9 + artIndex * 5) % 13) - 6),
			corridorIndex * 23 + artIndex)
	end
end

local function makeFakePlant(parent: Instance, position: Vector3)
	part(parent, "Level 3 Plant Pot", CFrame.new(position + Vector3.new(0, 1.1, 0)),
		Vector3.new(2.2, 2.2, 2.2), Color3.fromRGB(104, 69, 50), Enum.Material.ClayRoofTiles)
	for i = 1, 5 do
		local leaf = part(parent, "Level 3 Fake Plant", CFrame.new(position + Vector3.new((i - 3) * .35, 3.2 + (i % 2), 0))
			* CFrame.Angles(0, 0, math.rad((i - 3) * 18)), Vector3.new(.65, 4, 1.2),
			Color3.fromRGB(54, 92, 54), Enum.Material.LeafyGrass)
		decorative(leaf)
	end
end

local function makeLooseBalloons(parent: Instance, center: Vector3, count: number, seed: number)
	local colors = {Color3.fromRGB(187, 42, 52), Color3.fromRGB(40, 104, 169),
		Color3.fromRGB(55, 139, 91), Color3.fromRGB(210, 159, 37), Color3.fromRGB(119, 61, 151)}
	for balloonIndex = 1, count do
		local angle = seed * .71 + balloonIndex * 2.17
		local distance = 2.4 + ((seed * 7 + balloonIndex * 11) % 9) * .48
		local balloon = part(parent, "Level 3 Loose Party Balloon",
			CFrame.new(center + Vector3.new(math.cos(angle) * distance, .42, math.sin(angle) * distance))
				* CFrame.Angles(math.rad(8 + balloonIndex * 7), angle, math.rad(68)),
			Vector3.new(1.65, .72, 1.32), colors[(seed + balloonIndex - 1) % #colors + 1],
			Enum.Material.SmoothPlastic, .035)
		balloon.Shape = Enum.PartType.Ball
		balloon.Reflectance = .05
		decorative(balloon)
	end
end

local function makeRoomSpeaker(parent: Instance, room: {[string]: any}, index: number)
	local p = worldPosition(room)
	local h = roomHeight(room)
	local position = p + Vector3.new(-room.W * .5 + 2.0, math.min(h - 2.1, 8.4), -room.D * .5 + 2.0)
	local facing = CFrame.lookAt(position, Vector3.new(p.X, position.Y - .4, p.Z))
	local model = Instance.new("Model")
	model.Name = string.format("Level 3 Room PA Speaker %02d", index)
	model:SetAttribute("Level3_RoomSpeaker", true)
	model:SetAttribute("Level3_RoomId", room.Id)
	model.Parent = parent
	local housing = part(model, "PA Speaker Housing", facing, Vector3.new(2.65, 1.85, .72),
		Color3.fromRGB(47, 49, 46), Enum.Material.Metal)
	decorative(housing)
	local horn = part(model, "PA Speaker Grille", facing * CFrame.new(0, 0, -.39), Vector3.new(2.25, 1.46, .10),
		Color3.fromRGB(19, 21, 20), Enum.Material.DiamondPlate)
	decorative(horn)
	local bracket = part(model, "PA Speaker Wall Bracket", facing * CFrame.new(0, 0, .52), Vector3.new(.72, .72, .42),
		Color3.fromRGB(67, 67, 60), Enum.Material.Metal)
	decorative(bracket)
	local emitter = part(model, "PA Speaker Emitter", facing * CFrame.new(0, 0, -.52), Vector3.new(.16, .16, .16),
		Color3.new(), Enum.Material.SmoothPlastic, 1)
	decorative(emitter)
	local sound = Instance.new("Sound")
	sound.Name = "Level 3 Room Song Speaker"
	sound.SoundId = Configuration.Audio.RoomListeningSong
	sound.Volume = Configuration.MusicSequence.SpeakerVolume or .62
	sound.Looped = false
	sound.RollOffMode = Enum.RollOffMode.InverseTapered
	sound.RollOffMinDistance = Configuration.MusicSequence.SpeakerMinDistance or 7
	sound.RollOffMaxDistance = Configuration.MusicSequence.SpeakerMaxDistance or 48
	sound.EmitterSize = 3
	sound.Parent = emitter
	local equalizer = Instance.new("EqualizerSoundEffect")
	equalizer.Name = "Level 3 Distance Muffle"
	equalizer.LowGain = 0
	equalizer.MidGain = 0
	equalizer.HighGain = 0
	equalizer.Parent = sound
end

local function makeRoomProps(parent: Instance, room: {[string]: any}, index: number)
	local p = worldPosition(room)
	if room.Kind == "Exit" then
		makeRoomSpeaker(parent, room, index)
		return
	end
	local archetype = room.Decor or "SparseWelcome"
	local layouts = {}

	if archetype == "SparseWelcome" then
		layouts = {{-.24, .16, math.rad(-5), 2}}
	elseif archetype == "KidsCafeteria" then
		layouts = {{-.20, -.16, math.rad(5), 4}, {.15, .18, math.rad(92), 4}}
	elseif archetype == "ForgottenPair" then
		layouts = {{-.18, .13, math.rad(-8), 2}}
	elseif archetype == "WhiteClassroom" then
		layouts = {{-.20, -.12, 0, 4}, {.18, .18, math.rad(90), 4}}
	elseif archetype == "BanquetRows" then
		layouts = {{-.24, -.12, math.rad(3), 6}, {.08, .19, math.rad(-4), 6}}
	elseif archetype == "BirthdayCenter" then
		layouts = {{-.18, -.17, 0, 8}, {.20, .18, math.rad(92), 6}}
	elseif archetype == "CityCafe" then
		layouts = {{-.22, -.15, math.rad(88), 4}, {.18, .19, math.rad(-5), 4}}
	elseif archetype == "KidsCluster" then
		layouts = {{-.24, -.16, math.rad(6), 4}, {-.05, .20, math.rad(92), 6}, {.20, .16, math.rad(-6), 4}}
	elseif archetype == "AfterParty" then
		layouts = {{-.18, .15, math.rad(14), 2}}
	elseif archetype == "GrandBanquet" then
		layouts = {{-.28, -.18, math.rad(2), 8}, {0, .18, math.rad(90), 8}, {.28, .19, math.rad(-3), 8}}
	elseif archetype == "AbandonedCelebration" then
		layouts = {{-.18, .16, math.rad(-11), 4}}
	elseif archetype == "WhiteAtrium" then
		layouts = {{-.22, .20, math.rad(90), 4}}
	elseif archetype == "DanceFloor" then
		layouts = {{-.28, .23, math.rad(4), 4}}
	elseif archetype == "SparseGallery" then
		layouts = {{-.25, .15, math.rad(90), 2}}
	end

	local moduleSocketCreated = false
	for tableIndex, layout in ipairs(layouts) do
		local tableCF = CFrame.new(p + Vector3.new(layout[1] * room.W, 0, layout[2] * room.D))
			* CFrame.Angles(0, layout[3], 0)
		makeTable(parent, tableCF, true, layout[4], index + tableIndex)
		if room.Module and not moduleSocketCreated then
			local socket = part(parent, "Level 3 CD Table Socket", tableCF * CFrame.new(0, 3.62, 0),
				Vector3.new(2.8, .08, 2.8), Color3.new(), Enum.Material.SmoothPlastic, 1)
			decorative(socket)
			socket:SetAttribute("Level3_CDTableSocket", true)
			moduleSocketCreated = true
		end
	end

	local west = p + Vector3.new(-room.W * .5 + 6.5, 0, -room.D * .26)
	local east = p + Vector3.new(room.W * .5 - 6.5, 0, room.D * .24)
	if archetype ~= "EmptyTransition" then
		makeBalloonCluster(parent, west, index, room.Kind == "Party" and 7 or 4)
	end
	if room.W >= 76 and archetype ~= "SparseWelcome" and archetype ~= "SparseGallery"
		and archetype ~= "EmptyTransition" then
		makeBalloonCluster(parent, east, index + 2, room.Kind == "Party" and 6 or 4)
	end
	if archetype == "AfterParty" or archetype == "AbandonedCelebration" then
		makeLooseBalloons(parent, p + Vector3.new(room.W * .12, 0, -room.D * .12), 5, index)
	elseif archetype == "DanceFloor" then
		makeLooseBalloons(parent, p, 3, index)
	end
	-- One deterministic feature room is conspicuously overloaded with balloons,
	-- breaking the otherwise regular decoration rhythm without physics clutter.
	if room.Id == "PartyB" then
		makeBalloonCluster(parent, p + Vector3.new(-room.W * .32, 0, room.D * .27), index + 11, 11)
		makeBalloonCluster(parent, p + Vector3.new(room.W * .31, 0, -room.D * .29), index + 17, 10)
		makeLooseBalloons(parent, p + Vector3.new(0, 0, room.D * .15), 14, index + 23)
	end
	makeRoomSpeaker(parent, room, index)

	for _, object in ipairs(parent:GetDescendants()) do
		if object:IsA("BasePart") and (string.find(object.Name, "Table", 1, true)
			or string.find(object.Name, "Chair", 1, true)) then
			decorative(object)
		end
	end
end

local function makeRoomStructure(parent: Instance, room: {[string]: any})
	if room.Module or (room.Decor ~= "DanceFloor" and room.Decor ~= "BirthdayCenter"
		and room.Decor ~= "WhiteAtrium") then return end
	local p = worldPosition(room)
	local h = roomHeight(room)
	local color = wallColor(room)
	for _, x in ipairs({-room.W * .34, room.W * .34}) do
		for _, z in ipairs({-room.D * .32, room.D * .32}) do
			local column = part(parent, "Level 3 Structural Column", CFrame.new(p + Vector3.new(x, h * .5, z)),
				Vector3.new(2.1, h, 2.1), color, Enum.Material.Plaster)
			column.CanCollide = true
		end
	end
	for _, z in ipairs({-room.D * .32, room.D * .32}) do
		local beam = part(parent, "Level 3 Ceiling Beam", CFrame.new(p + Vector3.new(0, h - .75, z)),
			Vector3.new(room.W * .68, 1.5, 1.1), color:Lerp(Color3.new(0, 0, 0), .08), Enum.Material.Plaster)
		beam.CanCollide = true
	end
end

local function addDoorFrame(parent: Instance, frameCF: CFrame, color: Color3, wallColorValue: Color3, wallpaper: boolean)
	local w, h = Configuration.DoorWidth, Configuration.DoorHeight
	local jambWidth = .58
	for _, x in ipairs({-w * .5 - jambWidth * .5, w * .5 + jambWidth * .5}) do
		part(parent, "Level 3 Door Jamb", frameCF * CFrame.new(x, h * .5, 0),
			Vector3.new(jambWidth, h + .5, .72), color, Enum.Material.Metal)
	end
	part(parent, "Level 3 Door Header", frameCF * CFrame.new(0, h + .25, 0),
		Vector3.new(w + jambWidth * 2, .5, .72), color, Enum.Material.Metal)
	local bulkheadHeight = Configuration.RoomHeight - (h + .5)
	if bulkheadHeight > .05 then
		local bulkhead = part(parent, "Level 3 Door Bulkhead",
			frameCF * CFrame.new(0, h + .5 + bulkheadHeight * .5, 0),
			Vector3.new(Configuration.CorridorWidth, bulkheadHeight, Configuration.WallThickness),
			wallColorValue, Enum.Material.Plaster)
		if wallpaper then
			texture(bulkhead, TEXTURES.PastelWallpaper, Enum.NormalId.Front,
				Configuration.TextureStuds.Wallpaper, Configuration.TextureStuds.Wallpaper, .08)
			texture(bulkhead, TEXTURES.PastelWallpaper, Enum.NormalId.Back,
				Configuration.TextureStuds.Wallpaper, Configuration.TextureStuds.Wallpaper, .08)
		end
	end
	local fillerWidth = math.max(.1, (Configuration.CorridorWidth - (w + jambWidth * 2)) * .5)
	for _, x in ipairs({-(w + jambWidth * 2) * .5 - fillerWidth * .5, (w + jambWidth * 2) * .5 + fillerWidth * .5}) do
		local filler = part(parent, "Level 3 Door Side Filler", frameCF * CFrame.new(x, h * .5, 0),
			Vector3.new(fillerWidth + .05, h + .5, Configuration.WallThickness), wallColorValue, Enum.Material.Plaster)
		if wallpaper then
			texture(filler, TEXTURES.PastelWallpaper, Enum.NormalId.Front,
				Configuration.TextureStuds.Wallpaper, Configuration.TextureStuds.Wallpaper, .08)
			texture(filler, TEXTURES.PastelWallpaper, Enum.NormalId.Back,
				Configuration.TextureStuds.Wallpaper, Configuration.TextureStuds.Wallpaper, .08)
		end
	end
end

local function makeDoor(parent: Instance, id: string, floorPosition: Vector3,
	forward: Vector3, doorType: string, title: string, wallColorValue: Color3?, wallpaper: boolean?): {[string]: any}
	local model = Instance.new("Model")
	model.Name = "Level 3 Door " .. id
	model.Parent = parent
	local w, h = Configuration.DoorWidth, Configuration.DoorHeight
	local frameCF = CFrame.lookAt(floorPosition, floorPosition + forward)
	addDoorFrame(model, frameCF, C.Metal, wallColorValue or C.MutedOrange, wallpaper == true)
	local closed = frameCF * CFrame.new(0, h * .5, 0)
	local leaf = part(model, "Door", closed, Vector3.new(w, h, .55),
		Color3.fromRGB(112, 57, 37), Enum.Material.Metal)
	texture(leaf, TEXTURES.StaffDoor, Enum.NormalId.Front, w, h)
	texture(leaf, TEXTURES.StaffDoor, Enum.NormalId.Back, w, h)
	local hinge = frameCF * CFrame.new(-w * .5, h * .5, 0)
	local open = hinge * CFrame.Angles(0, math.rad(-94), 0) * CFrame.new(w * .5, 0, 0)
	local handle = part(model, "Handle", closed * CFrame.new(w * .34, 0, -.45),
		Vector3.new(.35, .35, .85), Color3.fromRGB(141, 126, 85), Enum.Material.Metal)
	handle.Shape = Enum.PartType.Cylinder
	decorative(handle)
	local prompt = Instance.new("ProximityPrompt")
	prompt.Name = "DoorPrompt"
	prompt.ActionText = "OPEN"
	prompt.ObjectText = title
	prompt.HoldDuration = .15
	prompt.MaxActivationDistance = 7
	prompt.RequiresLineOfSight = true
	prompt.KeyboardKeyCode = Enum.KeyCode.E
	prompt.Parent = leaf
	local movement = Instance.new("Sound")
	movement.Name = "Door Movement"
	movement.SoundId = Configuration.Audio.DoorMovement
	movement.Volume = .32
	movement.RollOffMaxDistance = 38
	movement.Parent = leaf
	model.PrimaryPart = leaf
	model:SetAttribute("Level3_DoorId", id)
	model:SetAttribute("Level3_DoorType", doorType)
	model:SetAttribute("Level3_DoorOpen", false)
	return {Id=id, Model=model, Leaf=leaf, Prompt=prompt, Closed=closed, Open=open, Type=doorType}
end

local function makeLockedDoor(parent: Instance, room: {[string]: any}, side: string, offset: number,
	index: number): {[string]: any}
	local p = worldPosition(room)
	local t = Configuration.WallThickness
	local floorPosition, forward
	if side == "North" then floorPosition = p + Vector3.new(offset, 0, -room.D * .5 + t); forward = Vector3.new(0, 0, 1)
	elseif side == "South" then floorPosition = p + Vector3.new(offset, 0, room.D * .5 - t); forward = Vector3.new(0, 0, -1)
	elseif side == "West" then floorPosition = p + Vector3.new(-room.W * .5 + t, 0, offset); forward = Vector3.new(1, 0, 0)
	else floorPosition = p + Vector3.new(room.W * .5 - t, 0, offset); forward = Vector3.new(-1, 0, 0) end
	local record = makeDoor(parent, room.Id .. "_LOCKED_" .. index, floorPosition, forward, "Locked", "STAFF ACCESS",
		wallColor(room), usesWallpaper(room))
	record.Prompt.ActionText = "TRY HANDLE"
	record.Prompt.HoldDuration = .2
	local rattle = Instance.new("Sound")
	rattle.Name = "Locked Handle Rattle"
	rattle.SoundId = Configuration.Audio.DoorRattle
	rattle.Volume = .38
	rattle.RollOffMaxDistance = 32
	rattle.Parent = record.Leaf
	return record
end

local function makeHiddenExitPortal(parent: Instance, corridor: {[string]: any}): {[string]: any}
	local model = Instance.new("Model")
	model.Name = "Level 3 Hidden Exit Portal"
	model.Parent = parent
	local center = corridor.StartPoint
	local forward = corridor.Forward
	local frameCF = CFrame.lookAt(center, center + forward)
	-- The concealed wall seals the complete standardized tunnel mouth.
	local apertureW = Configuration.CorridorWidth
	local apertureH = Configuration.CorridorHeight
	-- Match the Signal Hall side, not the pale exit corridor beyond it.
	local falseWallColor = wallColor(corridor.A)
	local falseWallWallpaper = usesWallpaper(corridor.A)
	local wall = part(model, "Seamless False Wall", frameCF * CFrame.new(0, apertureH * .5, 0),
		Vector3.new(apertureW, apertureH, Configuration.WallThickness), falseWallColor, Enum.Material.Plaster)
	wall.CanCollide = true
	wall.CanTouch = false
	wall.CanQuery = true
	wall:SetAttribute("Level3_HiddenExitWall", true)
	local falseWallTexture = if falseWallWallpaper then TEXTURES.PastelWallpaper else TEXTURES.OrangeWall
	local falseWallTransparency = if falseWallWallpaper then .08 else .28
	for _, face in ipairs({Enum.NormalId.Front, Enum.NormalId.Back}) do
		texture(wall, falseWallTexture, face,
			Configuration.TextureStuds.Wallpaper, Configuration.TextureStuds.Wallpaper,
			falseWallTransparency)
	end
	local strip = .12
	local frameParts = {}
	for _, side in ipairs({-1, 1}) do
		local z = side * (Configuration.WallThickness * .5 + .06)
		for _, data in ipairs({
			{Vector3.new(-apertureW * .5 + strip * .5, apertureH * .5, z), Vector3.new(strip, apertureH, .08)},
			{Vector3.new(apertureW * .5 - strip * .5, apertureH * .5, z), Vector3.new(strip, apertureH, .08)},
			{Vector3.new(0, strip * .5, z), Vector3.new(apertureW, strip, .08)},
			{Vector3.new(0, apertureH - strip * .5, z), Vector3.new(apertureW, strip, .08)},
		}) do
			local beam = part(model, "Hidden Exit Blue Frame", frameCF * CFrame.new(data[1]), data[2],
				Color3.fromRGB(70, 170, 255), Enum.Material.Neon, 1)
			decorative(beam)
			beam:SetAttribute("Level3_HiddenExitFrame", true)
			table.insert(frameParts, beam)
		end
	end
	local light = Instance.new("PointLight")
	light.Name = "Hidden Exit Blue Spill"
	light.Color = Color3.fromRGB(70, 170, 255)
	light.Brightness = .35
	light.Range = 8
	light.Shadows = false
	light.Enabled = false
	light.Parent = frameParts[1]
	model:SetAttribute("Level3_ExitUnlocked", false)
	return {Model=model, Wall=wall, FrameParts=frameParts, Light=light, Position=center}
end

local function sideBetween(a: {[string]: any}, b: {[string]: any}): string
	local dx, dz = b.X - a.X, b.Z - a.Z
	if math.abs(dx) > math.abs(dz) then return dx > 0 and "East" or "West" end
	return dz > 0 and "South" or "North"
end

local function connectionMap(): {[string]: {[string]: boolean}}
	local map = {}
	for _, room in ipairs(Configuration.Rooms) do map[room.Id] = {} end
	for _, link in ipairs(Configuration.Links) do
		local a, b = roomById(link.A), roomById(link.B)
		map[a.Id][sideBetween(a, b)] = true
		map[b.Id][sideBetween(b, a)] = true
	end
	-- The story-only Level 2 flume mouth opens behind the Level 3 spawn.
	map.Arrival.West = true
	return map
end

local function makeRoom(parent: Instance, room: {[string]: any}, openings: {[string]: boolean}, index: number)
	local model = Instance.new("Model")
	model.Name = string.format("%02d %s", index, room.Name)
	model:SetAttribute("Level3_RoomId", room.Id)
	model:SetAttribute("Level3_RoomKind", room.Kind)
	model:SetAttribute("Level3_DecorArchetype", room.Decor or "Default")
	model:SetAttribute("Level3_CeilingHeight", roomHeight(room))
	model.Parent = parent
	local p = worldPosition(room)
	local color, material, textureId, studs = floorStyle(room.Kind, room.Id)
	local floorPart = part(model, "Level 3 Room Floor", CFrame.new(p - Vector3.new(0, .5, 0)),
		Vector3.new(room.W, Configuration.FloorThickness, room.D), color, material)
	if textureId then texture(floorPart, textureId, Enum.NormalId.Top, studs, studs) end
	part(model, "Level 3 Room Ceiling", CFrame.new(p + Vector3.new(0, roomHeight(room), 0)),
		Vector3.new(room.W, Configuration.CeilingThickness, room.D), C.AgedWhite, Enum.Material.Plaster)
	for _, side in ipairs({"North", "South", "West", "East"}) do
		makeWall(model, room, side, openings[side] == true)
	end
	makeCeilingGrid(model, room)
	makeRoomWallDecor(model, room, openings, index)
	makeRoomLights(model, room, index)
	makeRoomProps(model, room, index)
	makeRoomStructure(model, room)
	return model
end

local function makeCorridor(parent: Instance, link: {[string]: any}, index: number): {[string]: any}
	local a, b = roomById(link.A), roomById(link.B)
	local ap, bp = worldPosition(a), worldPosition(b)
	local horizontal = math.abs(b.X - a.X) > math.abs(b.Z - a.Z)
	local startPoint, endPoint
	if horizontal then
		local direction = b.X > a.X and 1 or -1
		startPoint = ap + Vector3.new(direction * a.W * .5, 0, 0)
		endPoint = bp - Vector3.new(direction * b.W * .5, 0, 0)
	else
		local direction = b.Z > a.Z and 1 or -1
		startPoint = ap + Vector3.new(0, 0, direction * a.D * .5)
		endPoint = bp - Vector3.new(0, 0, direction * b.D * .5)
	end
	local vector = endPoint - startPoint
	local length = vector.Magnitude
	local forward = vector.Unit
	local center = (startPoint + endPoint) * .5
	local tunnelWidth = Configuration.CorridorWidth
	local tunnelHeight = Configuration.CorridorHeight
	local model = Instance.new("Model")
	model.Name = string.format("Level 3 Corridor %02d %s-%s", index, a.Id, b.Id)
	model:SetAttribute("Level3_TunnelWidth", tunnelWidth)
	model:SetAttribute("Level3_TunnelHeight", tunnelHeight)
	model.Parent = parent

	-- Butt the tunnel kit cleanly against each room opening. The former full
	-- wall-thickness overlap put coplanar lintels/pillars in the same space and
	-- produced visible z-fighting. Floors/ceilings get a microscopic seal while
	-- side walls stop just short of the room shell.
	local floorColor, floorMaterial, floorTexture, studs = floorStyle("PartyHall")
	local sealedLength = length + .04
	-- Room shells own the opening jambs/lintel. Stop tunnel walls and ceiling
	-- just before those shell volumes so no coplanar faces can shimmer.
	local wallLength = math.max(.1, length - Configuration.WallThickness - .08)
	local floorSize = horizontal and Vector3.new(sealedLength, 1, tunnelWidth)
		or Vector3.new(tunnelWidth, 1, sealedLength)
	local floorPart = part(model, "Level 3 Corridor Floor", CFrame.new(center - Vector3.new(0, .5, 0)),
		floorSize, floorColor, floorMaterial)
	if floorTexture then texture(floorPart, floorTexture, Enum.NormalId.Top, studs, studs) end
	local ceilingSize = horizontal and Vector3.new(wallLength, 1, tunnelWidth)
		or Vector3.new(tunnelWidth, 1, wallLength)
	part(model, "Level 3 Corridor Ceiling",
		CFrame.new(center + Vector3.new(0, tunnelHeight + .5, 0)),
		ceilingSize, C.AgedWhite, Enum.Material.Plaster)

	local wallColorValue = Color3.fromRGB(183, 78, 35)
	if horizontal then
		for _, z in ipairs({-tunnelWidth * .5, tunnelWidth * .5}) do
			local wall = part(model, "Level 3 Corridor Wall",
				CFrame.new(center + Vector3.new(0, tunnelHeight * .5, z)),
				Vector3.new(wallLength, tunnelHeight, Configuration.WallThickness),
				wallColorValue, Enum.Material.Plaster)
			texture(wall, TEXTURES.OrangeWall, z < 0 and Enum.NormalId.Front or Enum.NormalId.Back,
				Configuration.TextureStuds.OrangeWall, Configuration.TextureStuds.OrangeWall, .28)
		end
	else
		for _, x in ipairs({-tunnelWidth * .5, tunnelWidth * .5}) do
			local wall = part(model, "Level 3 Corridor Wall",
				CFrame.new(center + Vector3.new(x, tunnelHeight * .5, 0)),
				Vector3.new(Configuration.WallThickness, tunnelHeight, wallLength),
				wallColorValue, Enum.Material.Plaster)
			texture(wall, TEXTURES.OrangeWall, x < 0 and Enum.NormalId.Right or Enum.NormalId.Left,
				Configuration.TextureStuds.OrangeWall, Configuration.TextureStuds.OrangeWall, .28)
		end
	end
	makeCorridorWallDecor(model, startPoint, endPoint, horizontal, index)
	local fixtureCount = math.clamp(math.floor(length / 28), 1, 2)
	for fixtureIndex = 1, fixtureCount do
		local position = startPoint:Lerp(endPoint, fixtureIndex / (fixtureCount + 1))
		makeFixture(model, position + Vector3.new(0, tunnelHeight - .85, 0),
			"Staff", 400 + index * 4 + fixtureIndex, (index + fixtureIndex) % 9 == 0)
	end
	return {Model=model, Center=center, Forward=forward, Length=length, DoorType=link.Door,
		A=a, B=b, DoorPosition=center, StartPoint=startPoint, EndPoint=endPoint,
		WallColor=wallColorValue, Wallpaper=false, Width=tunnelWidth, Height=tunnelHeight}
end

local function makeModule(parent: Instance, room: {[string]: any}, index: number, roomModel: Instance): {[string]: any}
	local model = Instance.new("Model")
	model.Name = string.format("Birthday Music CD %02d", index)
	model:SetAttribute("Level3_ModuleIndex", index)
	model:SetAttribute("Level3_CDIndex", index)
	model:SetAttribute("Level3_ModuleRoom", room.Id)
	model:SetAttribute("Level3_Collected", false)
	model.Parent = parent
	local socket = roomModel:FindFirstChild("Level 3 CD Table Socket", true)
	local baseCF = if socket and socket:IsA("BasePart")
		then socket.CFrame * CFrame.new(0, .13, 0) * CFrame.Angles(0, math.rad((index * 17) % 31 - 15), 0)
		else CFrame.new(worldPosition(room) + Vector3.new(0, 3.62, 0))
	local pedestal = part(model, "CD Placement Marker", baseCF, Vector3.new(.1, .1, .1),
		Color3.new(), Enum.Material.SmoothPlastic, 1)
	decorative(pedestal)
	local case = part(model, "Transparent Jewel Case", baseCF, Vector3.new(2.7, .18, 2.58),
		Color3.fromRGB(224, 235, 236), Enum.Material.Glass, .28)
	case.CanCollide = false
	case.CanTouch = false
	case.CanQuery = true
	case.Reflectance = .08
	local cover = part(model, "CD Cover Insert", baseCF * CFrame.new(0, .10, 0), Vector3.new(2.5, .035, 2.38),
		Color3.fromRGB(231, 224, 195), Enum.Material.SmoothPlastic)
	decorative(cover)
	local surface = Instance.new("SurfaceGui")
	surface.Name = "Level 3 CD Cover Surface"
	surface.Face = Enum.NormalId.Top
	surface.SizingMode = Enum.SurfaceGuiSizingMode.PixelsPerStud
	surface.PixelsPerStud = 120
	surface.LightInfluence = .45
	surface.AlwaysOnTop = false
	surface.Parent = cover
	local art = Instance.new("ImageLabel")
	art.Name = "Level 3 CD Cover Art"
	art.BackgroundTransparency = 1
	art.BorderSizePixel = 0
	art.Size = UDim2.fromScale(1, 1)
	art.Image = TEXTURES.CDCoversAtlas
	art.ImageRectSize = Vector2.new(512, 512)
	local artCell = (index - 1) % 4
	art.ImageRectOffset = Vector2.new((artCell % 2) * 512, math.floor(artCell / 2) * 512)
	art.Parent = surface
	local disc = part(model, "Party Mix Compact Disc", baseCF * CFrame.new(1.12, .16, .22)
		* CFrame.Angles(0, 0, math.pi * .5), Vector3.new(.09, 1.72, 1.72),
		Color3.fromRGB(176, 201, 214), Enum.Material.Metal)
	disc.Shape = Enum.PartType.Cylinder
	disc.Reflectance = .32
	decorative(disc)
	local hub = part(model, "Compact Disc Hub", disc.CFrame, Vector3.new(.105, .40, .40),
		Color3.fromRGB(28, 30, 31), Enum.Material.SmoothPlastic)
	hub.Shape = Enum.PartType.Cylinder
	decorative(hub)
	local prompt = Instance.new("ProximityPrompt")
	prompt.Name = "CollectPrompt"
	prompt.ActionText = "COLLECT CD"
	prompt.ObjectText = string.format("PARTY MIX CD %02d", index)
	prompt.HoldDuration = .35
	prompt.MaxActivationDistance = 9
	prompt.RequiresLineOfSight = true
	prompt.KeyboardKeyCode = Enum.KeyCode.E
	prompt.Parent = case
	model.PrimaryPart = case
	return {Index=index, RoomId=room.Id, Model=model, Prompt=prompt, Core=case, Pedestal=pedestal}
end

local function makeArrivalElevator(parent: Instance, room: {[string]: any}): (Model, BasePart, BasePart)
	local p = worldPosition(room)
	local visual = Instance.new("Model")
	visual.Name = "Level 2 Exit Tube Remnant"
	visual:SetAttribute("Level3_Level2ExitTube", true)
	visual.Parent = parent
	local tubeLength, radius, segments = 34, 6.6, 20
	local mouthX = p.X - room.W * .5
	local tubeCenterX = mouthX - tubeLength * .5
	local centerY = p.Y + radius
	for segment = 1, segments do
		local angle = (segment - 1) / segments * math.pi * 2
		local center = Vector3.new(tubeCenterX, centerY + math.sin(angle) * radius, p.Z + math.cos(angle) * radius)
		local panel = part(visual, "Level 2 Exit Tube Shell",
			CFrame.new(center) * CFrame.Angles(angle + math.pi * .5, 0, 0),
			Vector3.new(tubeLength + .08, .48, (math.pi * 2 * radius / segments) + .20),
			Color3.fromRGB(210, 204, 173), Enum.Material.CeramicTiles)
		panel.CanCollide = segment >= 4 and segment <= 18
	end
	local tubeFloor = part(visual, "Level 2 Exit Tube Walkway", CFrame.new(tubeCenterX, p.Y - .44, p.Z),
		Vector3.new(tubeLength + .2, .88, 9.8), Color3.fromRGB(196, 192, 166), Enum.Material.CeramicTiles)
	tubeFloor.CanCollide = true
	local field = part(visual, "One Way Pool Exit Field", CFrame.new(mouthX - tubeLength + .35, centerY, p.Z),
		Vector3.new(.22, 11.5, 11.5), Color3.fromRGB(9, 13, 17), Enum.Material.SmoothPlastic, .08)
	field.CanCollide = true
	local warning = Instance.new("PointLight")
	warning.Name = "Spent Transfer Warning"
	warning.Color = Color3.fromRGB(180, 31, 24)
	warning.Brightness = .65
	warning.Range = 11
	warning.Shadows = true
	warning.Parent = field
	-- Invisible compatibility elevator retained for GameManager choreography.
	local model = Instance.new("Model")
	model.Name = "Elevator"
	model.Parent = workspace
	local compatibilityCF = CFrame.new(mouthX - tubeLength + .6, p.Y + 5, p.Z)
	local doorL = part(model, "DoorL", compatibilityCF, Vector3.new(.2, .2, .2), Color3.new(), Enum.Material.SmoothPlastic, 1)
	local doorR = part(model, "DoorR", compatibilityCF, Vector3.new(.2, .2, .2), Color3.new(), Enum.Material.SmoothPlastic, 1)
	decorative(doorL)
	decorative(doorR)
	model.PrimaryPart = doorL
	local spawnCF = CFrame.lookAt(p + Vector3.new(-room.W * .5 + 7.5, .25, 0), p + Vector3.new(2, .25, 0))
	local spawn = part(parent, "ElevatorSpawn", spawnCF, Vector3.new(10, .5, 10),
		Color3.new(), Enum.Material.SmoothPlastic, 1)
	spawn.CanCollide = true
	spawn:SetAttribute("Level3_CompatibilityMarker", true)
	spawn.Parent = workspace
	local mazeStart = part(parent, "MazeStart", spawn.CFrame, Vector3.new(2, .3, 2),
		Color3.new(), Enum.Material.SmoothPlastic, 1)
	mazeStart.CanCollide = false
	mazeStart:SetAttribute("Level3_CompatibilityMarker", true)
	mazeStart.Parent = workspace
	model:SetAttribute("Level3_CompatibilityMarker", true)
	return model, spawn, mazeStart
end

local function makeExitSet(parent: Instance, room: {[string]: any}): (ProximityPrompt, BasePart, Vector3, Model)
	local model = Instance.new("Model")
	model.Name = "Level 3 Energon Freight Exit"
	model:SetAttribute("Level3_FinalExit", true)
	model:SetAttribute("Level3_ExitPowered", false)
	model.Parent = parent
	local p = worldPosition(room)

	-- A completely flat, uninterrupted approach replaces the old staircase.
	local approachLength = math.max(22, room.W - 10)
	local approach = part(model, "Level 3 Flat Exit Approach",
		CFrame.new(p + Vector3.new(-2, .075, 0)),
		Vector3.new(approachLength, .15, 12), Color3.fromRGB(55, 57, 56), Enum.Material.DiamondPlate)
	approach.CanCollide = true

	local doorX = p.X + room.W * .5 - 1
	local doorCenter = Vector3.new(doorX, p.Y + 6.4, p.Z)
	local frameColor = Color3.fromRGB(19, 23, 24)
	local outerFrame = part(model, "Final Exit Outer Frame", CFrame.new(doorCenter + Vector3.new(.28, 0, 0)),
		Vector3.new(1.2, 13.4, 12.4), frameColor, Enum.Material.Metal)
	outerFrame.CanCollide = true
	local recess = part(model, "Final Exit Recess", CFrame.new(doorCenter + Vector3.new(-.38, 0, 0)),
		Vector3.new(.35, 12.15, 11.2), Color3.fromRGB(7, 9, 10), Enum.Material.Metal)
	recess.CanCollide = true

	local leftLeaf = part(model, "Final Exit Left Leaf", CFrame.new(doorCenter + Vector3.new(-.62, 0, -2.75)),
		Vector3.new(.65, 11.8, 5.45), Color3.fromRGB(113, 47, 23), Enum.Material.Metal)
	local rightLeaf = part(model, "Final Exit Right Leaf", CFrame.new(doorCenter + Vector3.new(-.62, 0, 2.75)),
		Vector3.new(.65, 11.8, 5.45), Color3.fromRGB(113, 47, 23), Enum.Material.Metal)
	leftLeaf:SetAttribute("Level3_FinalExitLeaf", "Left")
	rightLeaf:SetAttribute("Level3_FinalExitLeaf", "Right")
	for _, leaf in ipairs({leftLeaf, rightLeaf}) do
		leaf.CanCollide = true
		texture(leaf, TEXTURES.FinalExitDoor, Enum.NormalId.Right, 11.0, 11.8)
		texture(leaf, TEXTURES.FinalExitDoor, Enum.NormalId.Left, 11.0, 11.8)
	end

	-- Deep black ribs make the doorway feel built, heavy, and unique.
	for _, z in ipairs({-5.7, 5.7}) do
		local jamb = part(model, "Final Exit Reinforced Jamb", CFrame.new(doorCenter + Vector3.new(-.98, 0, z)),
			Vector3.new(1.05, 13.0, .65), frameColor, Enum.Material.DiamondPlate)
		jamb.CanCollide = true
	end
	local header = part(model, "Final Exit Reinforced Header", CFrame.new(doorCenter + Vector3.new(-.98, 6.15, 0)),
		Vector3.new(1.05, .75, 12.0), frameColor, Enum.Material.DiamondPlate)
	header.CanCollide = true
	local threshold = part(model, "Final Exit Reinforced Threshold", CFrame.new(doorCenter + Vector3.new(-1.0, -5.87, 0)),
		Vector3.new(1.1, .28, 11.4), frameColor, Enum.Material.DiamondPlate)
	threshold.CanCollide = true

	local powerParts = {}
	for _, z in ipairs({-5.15, 5.15}) do
		local rail = part(model, "Final Exit Energon Rail", CFrame.new(doorCenter + Vector3.new(-1.36, 0, z)),
			Vector3.new(.13, 10.8, .13), C.Energon, Enum.Material.Neon, 1)
		decorative(rail)
		table.insert(powerParts, rail)
	end
	for _, y in ipairs({-5.15, 5.15}) do
		local rail = part(model, "Final Exit Energon Rail", CFrame.new(doorCenter + Vector3.new(-1.36, y, 0)),
			Vector3.new(.13, .13, 10.4), C.Energon, Enum.Material.Neon, 1)
		decorative(rail)
		table.insert(powerParts, rail)
	end
	for _, y in ipairs({-3.5, -1.75, 1.75, 3.5}) do
		for _, z in ipairs({-5.15, 5.15}) do
			local node = part(model, "Final Exit Energon Node", CFrame.new(doorCenter + Vector3.new(-1.43, y, z)),
				Vector3.new(.16, .58, .58), C.Energon, Enum.Material.Neon, 1)
			decorative(node)
			table.insert(powerParts, node)
		end
	end
	local lockCore = part(model, "Final Exit Lock Core", CFrame.new(doorCenter + Vector3.new(-1.42, .25, 0)),
		Vector3.new(.16, 1.5, 1.5), C.Energon, Enum.Material.Neon, 1)
	decorative(lockCore)
	table.insert(powerParts, lockCore)
	local powerLight = Instance.new("PointLight")
	powerLight.Name = "Final Exit Energon Spill"
	powerLight.Color = C.Energon
	powerLight.Brightness = 1.3
	powerLight.Range = 16
	powerLight.Shadows = false
	powerLight.Enabled = false
	powerLight.Parent = lockCore

	local prompt = Instance.new("ProximityPrompt")
	prompt.Name = "EscapePrompt"
	prompt.ActionText = "LEAVE LEVEL 3"
	prompt.ObjectText = "ENERGON-LOCKED FREIGHT ELEVATOR"
	prompt.HoldDuration = 1.0
	prompt.MaxActivationDistance = 10
	prompt.RequiresLineOfSight = true
	prompt.Enabled = false
	prompt.Parent = lockCore

	local safeRoom = folder(parent, "Escaped Player Waiting Room")
	local safeCenter = p + Vector3.new(0, -36, 0)
	part(safeRoom, "Safe Floor", CFrame.new(safeCenter), Vector3.new(26, 1, 20),
		Color3.fromRGB(41, 43, 42), Enum.Material.Concrete)
	part(safeRoom, "Safe Ceiling", CFrame.new(safeCenter + Vector3.new(0, 12, 0)), Vector3.new(26, 1, 20),
		Color3.fromRGB(41, 43, 42), Enum.Material.Concrete)
	for _, data in ipairs({{Vector3.new(-13,6,0),Vector3.new(1,12,20)}, {Vector3.new(13,6,0),Vector3.new(1,12,20)},
		{Vector3.new(0,6,-10),Vector3.new(26,12,1)}, {Vector3.new(0,6,10),Vector3.new(26,12,1)}}) do
		part(safeRoom, "Safe Wall", CFrame.new(safeCenter + data[1]), data[2], Color3.fromRGB(41,43,42), Enum.Material.Concrete)
	end
	local safeSpawn = part(safeRoom, "ExitSafeSpawn", CFrame.new(safeCenter + Vector3.new(0, 3, 0)),
		Vector3.new(8, .3, 8), Color3.new(0,0,0), Enum.Material.SmoothPlastic, 1)
	safeSpawn.CanCollide = false
	return prompt, safeSpawn, lockCore.Position, model
end

local function makeAmbientEmitter(parent: Instance, name: string, position: Vector3,
	soundId: string, volume: number, maxDistance: number)
	local emitter = part(parent, name, CFrame.new(position), Vector3.new(.2,.2,.2),
		Color3.new(0,0,0), Enum.Material.SmoothPlastic, 1)
	decorative(emitter)
	local sound = Instance.new("Sound")
	sound.Name = name
	sound.SoundId = soundId
	sound.Volume = volume
	sound.Looped = true
	sound.RollOffMode = Enum.RollOffMode.InverseTapered
	sound.RollOffMinDistance = 14
	sound.RollOffMaxDistance = maxDistance
	sound.Parent = emitter
	sound:Play()
end

function Builder.Build(generation: number): {[string]: any}
	local existing = workspace:FindFirstChild(Configuration.WorldName)
	if existing then existing:Destroy() end
	local world = Instance.new("Model")
	world.Name = Configuration.WorldName
	world:SetAttribute("Level3_Generation", generation)
	world:SetAttribute("Level3_VisualRevision", Configuration.Version)
	world:SetAttribute("Level3_Theme", "Abandoned 1990s Mall Service Spaces")
	world.Parent = workspace
	local roomsFolder = folder(world, "Rooms")
	local corridorsFolder = folder(world, "Corridors")
	local doorsFolder = folder(world, "Doors")
	local modulesFolder = folder(world, "Birthday Music CDs")
	local ambienceFolder = folder(world, "Ambient Emitters")
	local openings = connectionMap()
	local manifestRooms = {}
	for index, room in ipairs(Configuration.Rooms) do
		manifestRooms[room.Id] = makeRoom(roomsFolder, room, openings[room.Id], index)
	end
	local doors = {}
	local exitPortal
	for index, link in ipairs(Configuration.Links) do
		local corridor = makeCorridor(corridorsFolder, link, index)
		if link.Door == "HiddenExit" then
			exitPortal = makeHiddenExitPortal(doorsFolder, corridor)
		end
	end
	-- Revision 3 deliberately has no ordinary or fake doors. Every connection
	-- stays open; only the concealed exit portal and final freight door remain.
	local modules = {}
	for _, room in ipairs(Configuration.Rooms) do
		if room.Module then
			table.insert(modules, makeModule(modulesFolder, room, #modules + 1, manifestRooms[room.Id]))
		end
	end
	assert(#modules == Configuration.ModuleGoal, "Level 3 CD goal does not match authored CD rooms")
	local arrivalRoom = roomById("Arrival")
	local elevator, elevatorSpawn, mazeStart = makeArrivalElevator(world, arrivalRoom)
	local escapePrompt, safeSpawn, exitPosition, finalExit = makeExitSet(world, roomById("Exit"))
	makeAmbientEmitter(ambienceFolder, "Level 3 HVAC Bed", worldPosition(roomById("Janitor"), 8),
		Configuration.Audio.HVAC, .10, 150)
	makeAmbientEmitter(ambienceFolder, "Level 3 Distant Drip", worldPosition(roomById("LoadingStore"), 1),
		Configuration.Audio.WaterDrip, .16, 75)
	assert(exitPortal, "Level 3 build requires exactly one hidden exit portal")
	world:SetAttribute("Level3_RoomCount", #Configuration.Rooms)
	world:SetAttribute("Level3_CorridorCount", #Configuration.Links)
	world:SetAttribute("Level3_ModuleCount", #modules)
	-- Decorative helper calls intentionally strip collision. Reassert the one
	-- tagged, low-cost tabletop collider after all room dressing is complete.
	for _, object in ipairs(world:GetDescendants()) do
		if object:IsA("BasePart") and object:GetAttribute("Level3_TableCollision") == true then
			object.CanCollide = true
			object.CanTouch = false
			object.CanQuery = true
		end
	end
	return {
		World=world,
		Rooms=manifestRooms,
		Doors=doors,
		Modules=modules,
		ExitPortal=exitPortal,
		EscapePrompt=escapePrompt,
		ExitSafeSpawn=safeSpawn,
		ExitPosition=exitPosition,
		FinalExit=finalExit,
		Elevator=elevator,
		ElevatorSpawn=elevatorSpawn,
		MazeStart=mazeStart,
		Generation=generation,
	}
end

return Builder
