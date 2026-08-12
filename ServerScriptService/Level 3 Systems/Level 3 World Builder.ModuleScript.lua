--!strict
-- Level 3 World Builder
-- Builds a deliberately authored network of forgotten mall service spaces.

local Configuration = require(script.Parent:WaitForChild("Level 3 Configuration"))
local ReplicatedStorage = game:GetService("ReplicatedStorage")

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
	CityCarpet = contentTexture("CityPlayCarpetTexture", Configuration.Textures.CityCarpet),
	PastelWallpaper = contentTexture("PastelWallpaperTexture", Configuration.Textures.PastelWallpaper),
	ConfettiTablecloth = contentTexture("ConfettiTableclothTexture", Configuration.Textures.ConfettiTablecloth),
	StaffDoor = contentTexture("StaffDoorTexture", Configuration.Textures.StaffDoor),
	FinalExitDoor = contentTexture("FinalExitDoorTexture", Configuration.Textures.FinalExitDoor),
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
	object.CanTouch = false
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

local function floorStyle(kind: string): (Color3, Enum.Material, string?, number)
	if kind == "City" then
		return Color3.fromRGB(190, 188, 166), Enum.Material.Carpet, TEXTURES.CityCarpet, Configuration.TextureStuds.CityCarpet
	elseif kind == "Exit" then
		return Color3.fromRGB(70, 71, 66), Enum.Material.DiamondPlate, nil, 10
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
	end
	return wall
end

local function makeWall(parent: Instance, room: {[string]: any}, side: string, hasOpening: boolean)
	local origin = worldPosition(room)
	local h = Configuration.RoomHeight
	local t = Configuration.WallThickness
	local doorW = Configuration.DoorWidth + 1
	local doorH = Configuration.DoorHeight + 0.5
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
		wallSegment(parent, "Level 3 " .. side .. " Lintel", cfAlong(0, doorH + (h - doorH) * 0.5),
			wallSize(doorW, h - doorH), color, face, wallpaper)
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
	local y = Configuration.RoomHeight - 0.52
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
		light.Brightness = (kind == "Party" or kind == "PartyHall") and 1.50 or 1.35
		light.Range = 30
		light.Angle = 128
		light.Shadows = false
		light.Parent = diffuser
		if index % 11 == 0 then diffuser:SetAttribute("Level3_SubtleFlicker", true) end
	end
	return diffuser
end

local function makeRoomLights(parent: Instance, room: {[string]: any}, roomIndex: number)
	local p = worldPosition(room)
	local columns = math.clamp(math.floor(room.W / 34), 1, 2)
	local rows = math.clamp(math.floor(room.D / 34), 1, 2)
	local n = 0
	for ix = 1, columns do
		for iz = 1, rows do
			n += 1
			local x = (ix / (columns + 1) - .5) * room.W
			local z = (iz / (rows + 1) - .5) * room.D
			makeFixture(parent, p + Vector3.new(x, Configuration.RoomHeight - .85, z),
				room.Kind, roomIndex * 10 + n, (roomIndex * 7 + n * 3) % 13 == 0)
		end
	end
end

local function makeTable(parent: Instance, cframe: CFrame, party: boolean, chairs: number)
	local top = part(parent, "Level 3 Folding Table", cframe * CFrame.new(0, 3, 0),
		Vector3.new(12, .55, 4.5), party and Color3.fromRGB(218, 211, 190) or Color3.fromRGB(133, 116, 91),
		party and Enum.Material.SmoothPlastic or Enum.Material.WoodPlanks)
	if party then texture(top, TEXTURES.ConfettiTablecloth, Enum.NormalId.Top,
		Configuration.TextureStuds.Tablecloth, Configuration.TextureStuds.Tablecloth) end
	for _, x in ipairs({-5, 5}) do
		for _, z in ipairs({-1.6, 1.6}) do
			part(parent, "Level 3 Table Leg", cframe * CFrame.new(x, 1.45, z),
				Vector3.new(.35, 2.9, .35), C.Metal, Enum.Material.Metal)
		end
	end
	for i = 1, chairs do
		local side = i % 2 == 0 and 1 or -1
		local column = math.floor((i - 1) / 2)
		local chairCF = cframe * CFrame.new(-4 + column * 4, 0, side * 4.2)
		local chairColor = party and ({C.MutedBlue, C.FadedGreen, C.Burgundy})[(i - 1) % 3 + 1]
			or Color3.fromRGB(80, 76, 68)
		part(parent, "Level 3 Chair Seat", chairCF * CFrame.new(0, 2.2, 0),
			Vector3.new(2.5, .45, 2.5), chairColor, Enum.Material.SmoothPlastic)
		part(parent, "Level 3 Chair Back", chairCF * CFrame.new(0, 4.1, side * 1.05),
			Vector3.new(2.5, 3.4, .4), chairColor, Enum.Material.SmoothPlastic)
		for _, legX in ipairs({-1, 1}) do
			for _, legZ in ipairs({-.95, .95}) do
				part(parent, "Level 3 Chair Leg", chairCF * CFrame.new(legX, 1, legZ),
					Vector3.new(.22, 2, .22), C.Metal, Enum.Material.Metal)
			end
		end
	end
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

local function makeBalloonCluster(parent: Instance, position: Vector3, colorOffset: number)
	local colors = {Color3.fromRGB(178, 45, 53), Color3.fromRGB(49, 101, 153),
		Color3.fromRGB(67, 133, 88), Color3.fromRGB(184, 139, 41), Color3.fromRGB(107, 62, 132)}
	for i = 1, 5 do
		local angle = (i / 5) * math.pi * 2
		local p = position + Vector3.new(math.cos(angle) * 1.5, 7 + (i % 2) * 1.2, math.sin(angle) * 1.5)
		local balloon = part(parent, "Level 3 Faded Balloon", CFrame.new(p), Vector3.new(2.2, 2.8, 2.2),
			colors[(i + colorOffset) % #colors + 1], Enum.Material.SmoothPlastic, .05)
		balloon.Shape = Enum.PartType.Ball
		decorative(balloon)
		local stringPart = part(parent, "Level 3 Balloon String", CFrame.new((p + position + Vector3.new(0, 2, 0)) * .5),
			Vector3.new(.035, (p - (position + Vector3.new(0, 2, 0))).Magnitude, .035),
			Color3.fromRGB(92, 90, 82), Enum.Material.SmoothPlastic, .15)
		decorative(stringPart)
	end
end

local function makeBunting(parent: Instance, room: {[string]: any})
	local p = worldPosition(room)
	local colors = {C.Burgundy, C.MutedBlue, C.FadedGreen, Color3.fromRGB(184, 139, 41), C.DustyPeach}
	for row = -1, 1, 2 do
		local z = row * room.D * .22
		local cord = part(parent, "Level 3 Bunting Cord", CFrame.new(p + Vector3.new(0, 11.8, z)),
			Vector3.new(room.W - 5, .04, .04), Color3.fromRGB(75, 68, 59), Enum.Material.SmoothPlastic)
		decorative(cord)
		for x = -room.W * .5 + 4, room.W * .5 - 4, 4 do
			local flag = part(parent, "Level 3 Bunting Flag", CFrame.new(p + Vector3.new(x, 11.05, z)),
				Vector3.new(2.2, 1.45, .08), colors[(math.floor(x / 4) + row + 20) % #colors + 1], Enum.Material.Fabric)
			decorative(flag)
		end
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

local function makeRoomProps(parent: Instance, room: {[string]: any}, index: number)
	local p = worldPosition(room)
	if room.Kind == "Exit" then return end

	-- Revision 3 uses one restricted prop language: party tables, folding
	-- chairs and balloons. No boxes, shelving, desks, cabinets, plants,
	-- utility pipes or other storage clutter are generated.
	local tableCount
	if room.W >= 110 then
		tableCount = 6
	elseif room.W >= 85 or room.D >= 68 then
		tableCount = 4
	elseif room.W >= 65 then
		tableCount = 3
	else
		tableCount = 2
	end
	if room.Id == "Arrival" then tableCount = 1 end

	local columns = math.max(1, math.ceil(tableCount / 2))
	local xSpan = math.min(room.W * .55, columns * 18)
	for tableIndex = 1, tableCount do
		local row = (tableIndex - 1) % 2
		local column = math.floor((tableIndex - 1) / 2)
		local x = columns == 1 and 0 or (-xSpan * .5 + (column / math.max(1, columns - 1)) * xSpan)
		local z = (row == 0 and -1 or 1) * math.min(9, room.D * .18)
		makeTable(parent, CFrame.new(p + Vector3.new(x, 0, z)), true, room.W >= 80 and 6 or 4)
	end

	local west = p + Vector3.new(-room.W * .5 + 7, 0, -room.D * .25)
	local east = p + Vector3.new(room.W * .5 - 7, 0, room.D * .25)
	makeBalloonCluster(parent, west, index)
	if room.W >= 65 then makeBalloonCluster(parent, east, index + 2) end

	-- Furniture is visual set dressing, not a navigation obstacle. This keeps
	-- the enlarged rooms multiplayer-safe and cuts collision cost sharply.
	for _, object in ipairs(parent:GetDescendants()) do
		if object:IsA("BasePart") and (string.find(object.Name, "Table", 1, true)
			or string.find(object.Name, "Chair", 1, true)) then
			decorative(object)
		end
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
	local apertureW = Configuration.CorridorWidth
	local apertureH = Configuration.RoomHeight
	-- Match the Signal Hall side, not the pale exit corridor beyond it.
	local falseWallColor = wallColor(corridor.A)
	local falseWallWallpaper = usesWallpaper(corridor.A)
	local wall = part(model, "Seamless False Wall", frameCF * CFrame.new(0, apertureH * .5, 0),
		Vector3.new(apertureW, apertureH, Configuration.WallThickness), falseWallColor, Enum.Material.Plaster)
	wall.CanCollide = false
	wall.CanTouch = false
	wall.CanQuery = true
	wall:SetAttribute("Level3_HiddenExitWall", true)
	if falseWallWallpaper then
		for _, face in ipairs({Enum.NormalId.Front, Enum.NormalId.Back}) do
			texture(wall, TEXTURES.PastelWallpaper, face,
				Configuration.TextureStuds.Wallpaper, Configuration.TextureStuds.Wallpaper, .08)
		end
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
	return map
end

local function makeRoom(parent: Instance, room: {[string]: any}, openings: {[string]: boolean}, index: number)
	local model = Instance.new("Model")
	model.Name = string.format("%02d %s", index, room.Name)
	model:SetAttribute("Level3_RoomId", room.Id)
	model:SetAttribute("Level3_RoomKind", room.Kind)
	model.Parent = parent
	local p = worldPosition(room)
	local color, material, textureId, studs = floorStyle(room.Kind)
	local floorPart = part(model, "Level 3 Room Floor", CFrame.new(p - Vector3.new(0, .5, 0)),
		Vector3.new(room.W, Configuration.FloorThickness, room.D), color, material)
	if textureId then texture(floorPart, textureId, Enum.NormalId.Top, studs, studs) end
	part(model, "Level 3 Room Ceiling", CFrame.new(p + Vector3.new(0, Configuration.RoomHeight, 0)),
		Vector3.new(room.W, Configuration.CeilingThickness, room.D), C.AgedWhite, Enum.Material.Plaster)
	for _, side in ipairs({"North", "South", "West", "East"}) do
		makeWall(model, room, side, openings[side] == true)
	end
	makeCeilingGrid(model, room)
	makeRoomLights(model, room, index)
	makeRoomProps(model, room, index)
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
	local model = Instance.new("Model")
	model.Name = string.format("Level 3 Corridor %02d %s-%s", index, a.Id, b.Id)
	model.Parent = parent
	-- Only the room inside the final stairwell is hard-surface; every approach
	-- corridor stays on the black party carpet.
	local floorColor, floorMaterial, floorTexture, studs = floorStyle("PartyHall")
	local floorSize = horizontal and Vector3.new(length + 1, 1, Configuration.CorridorWidth)
		or Vector3.new(Configuration.CorridorWidth, 1, length + 1)
	local floorPart = part(model, "Level 3 Corridor Floor", CFrame.new(center - Vector3.new(0, .5, 0)),
		floorSize, floorColor, floorMaterial)
	if floorTexture then texture(floorPart, floorTexture, Enum.NormalId.Top, studs, studs) end
	part(model, "Level 3 Corridor Ceiling", CFrame.new(center + Vector3.new(0, Configuration.RoomHeight, 0)),
		horizontal and Vector3.new(length + 1, 1, Configuration.CorridorWidth)
			or Vector3.new(Configuration.CorridorWidth, 1, length + 1), C.AgedWhite, Enum.Material.Plaster)
	local corridorWallpaper = false
	local wallColorValue = Color3.fromRGB(183, 78, 35)
	if horizontal then
		for _, z in ipairs({-Configuration.CorridorWidth * .5, Configuration.CorridorWidth * .5}) do
			local wall = part(model, "Level 3 Corridor Wall", CFrame.new(center + Vector3.new(0, Configuration.RoomHeight * .5, z)),
				Vector3.new(length + 1, Configuration.RoomHeight, Configuration.WallThickness), wallColorValue, Enum.Material.Plaster)
			if corridorWallpaper then
				texture(wall, TEXTURES.PastelWallpaper, z < 0 and Enum.NormalId.Front or Enum.NormalId.Back,
					Configuration.TextureStuds.Wallpaper, Configuration.TextureStuds.Wallpaper, .08)
			end
		end
	else
		for _, x in ipairs({-Configuration.CorridorWidth * .5, Configuration.CorridorWidth * .5}) do
			local wall = part(model, "Level 3 Corridor Wall", CFrame.new(center + Vector3.new(x, Configuration.RoomHeight * .5, 0)),
				Vector3.new(Configuration.WallThickness, Configuration.RoomHeight, length + 1), wallColorValue, Enum.Material.Plaster)
			if corridorWallpaper then
				texture(wall, TEXTURES.PastelWallpaper, x < 0 and Enum.NormalId.Right or Enum.NormalId.Left,
					Configuration.TextureStuds.Wallpaper, Configuration.TextureStuds.Wallpaper, .08)
			end
		end
	end
	local fixtureCount = math.clamp(math.floor(length / 28), 1, 2)
	for fixtureIndex = 1, fixtureCount do
		local position = startPoint:Lerp(endPoint, fixtureIndex / (fixtureCount + 1))
		makeFixture(model, position + Vector3.new(0, Configuration.RoomHeight - .85, 0),
			"Staff", 400 + index * 4 + fixtureIndex, (index + fixtureIndex) % 9 == 0)
	end
	return {Model=model, Center=center, Forward=forward, Length=length, DoorType=link.Door,
		A=a, B=b, DoorPosition=center, StartPoint=startPoint, EndPoint=endPoint,
		WallColor=wallColorValue, Wallpaper=corridorWallpaper}
end

local function makeModule(parent: Instance, room: {[string]: any}, index: number): {[string]: any}
	local model = Instance.new("Model")
	model.Name = string.format("Energon Resonance Module %02d", index)
	model:SetAttribute("Level3_ModuleIndex", index)
	model:SetAttribute("Level3_ModuleRoom", room.Id)
	model:SetAttribute("Level3_Collected", false)
	model.Parent = parent
	local p = worldPosition(room) + Vector3.new(room.W * .27, 0, -room.D * .27)
	local pedestal = part(model, "Pedestal", CFrame.new(p + Vector3.new(0, 1.5, 0)),
		Vector3.new(3.8, 3, 3.2), Color3.fromRGB(57, 59, 55), Enum.Material.Metal)
	local body = part(model, "Module Body", CFrame.new(p + Vector3.new(0, 3.7, 0)),
		Vector3.new(2.8, 1.5, 2.1), Color3.fromRGB(61, 67, 65), Enum.Material.Metal)
	local core = part(model, "Energon Core", CFrame.new(p + Vector3.new(0, 3.75, -1.12)),
		Vector3.new(1.25, .72, .12), C.Energon, Enum.Material.Neon, .04)
	decorative(core)
	local rearCore = part(model, "Energon Core Rear", CFrame.new(p + Vector3.new(0, 3.75, 1.12)),
		Vector3.new(1.25, .72, .12), C.Energon, Enum.Material.Neon, .04)
	decorative(rearCore)
	for _, x in ipairs({-1.34, 1.34}) do
		local marker = part(model, "Energon Side Marker", CFrame.new(p + Vector3.new(x, 3.7, 0)),
			Vector3.new(.12, 1.1, 1.7), C.Energon, Enum.Material.Neon, .12)
		decorative(marker)
	end
	for _, x in ipairs({-.9, .9}) do
		local antenna = part(model, "Antenna", CFrame.new(p + Vector3.new(x, 5.1, 0)),
			Vector3.new(.16, 2.2, .16), Color3.fromRGB(94, 96, 89), Enum.Material.Metal)
		decorative(antenna)
	end
	local glow = Instance.new("PointLight")
	glow.Name = "Energon Glow"
	glow.Color = C.Energon
	glow.Brightness = .8
	glow.Range = 12
	glow.Shadows = false
	glow.Parent = core
	local prompt = Instance.new("ProximityPrompt")
	prompt.Name = "CollectPrompt"
	prompt.ActionText = "RECOVER MODULE"
	prompt.ObjectText = "ENERGON RESONANCE MODULE"
	prompt.HoldDuration = .45
	prompt.MaxActivationDistance = 10
	prompt.RequiresLineOfSight = true
	prompt.KeyboardKeyCode = Enum.KeyCode.E
	prompt.Parent = body
	model.PrimaryPart = body
	return {Index=index, RoomId=room.Id, Model=model, Prompt=prompt, Core=core, Pedestal=pedestal}
end

local function makeArrivalElevator(parent: Instance, room: {[string]: any}): (Model, BasePart, BasePart)
	local p = worldPosition(room)
	local model = Instance.new("Model")
	model.Name = "Elevator"
	model.Parent = workspace
	part(model, "CabinBack", CFrame.new(p + Vector3.new(-room.W * .5 - 5, 6, 0)),
		Vector3.new(1, 12, 14), C.Metal, Enum.Material.Metal)
	part(model, "CabinFloor", CFrame.new(p + Vector3.new(-room.W * .5 - 1.8, -.35, 0)),
		Vector3.new(7, .7, 14), Color3.fromRGB(72, 72, 67), Enum.Material.DiamondPlate)
	for _, z in ipairs({-7, 7}) do
		part(model, "CabinSide", CFrame.new(p + Vector3.new(-room.W * .5 - 1.8, 6, z)),
			Vector3.new(7, 12, .8), C.Metal, Enum.Material.Metal)
	end
	local doorX = p.X - room.W * .5 + .25
	local doorL = part(model, "DoorL", CFrame.new(doorX, p.Y + 5, p.Z - 2.25),
		Vector3.new(.6, 10, 4.5), Color3.fromRGB(80, 83, 80), Enum.Material.Metal)
	local doorR = part(model, "DoorR", CFrame.new(doorX, p.Y + 5, p.Z + 2.25),
		Vector3.new(.6, 10, 4.5), Color3.fromRGB(80, 83, 80), Enum.Material.Metal)
	model.PrimaryPart = doorL
	local spawn = part(parent, "ElevatorSpawn", CFrame.lookAt(p + Vector3.new(-14, .25, 0), p + Vector3.new(1, .25, 0)),
		Vector3.new(11, .5, 10), Color3.new(0,0,0), Enum.Material.SmoothPlastic, 1)
	spawn.CanCollide = true
	spawn:SetAttribute("Level3_CompatibilityMarker", true)
	spawn.Parent = workspace
	local mazeStart = part(parent, "MazeStart", spawn.CFrame, Vector3.new(2, .3, 2),
		Color3.new(0,0,0), Enum.Material.SmoothPlastic, 1)
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
	local modulesFolder = folder(world, "Energon Resonance Modules")
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
		if room.Module then table.insert(modules, makeModule(modulesFolder, room, #modules + 1)) end
	end
	assert(#modules == Configuration.ModuleGoal, "Level 3 module goal does not match authored module rooms")
	local arrivalRoom = roomById("Arrival")
	local elevator, elevatorSpawn, mazeStart = makeArrivalElevator(world, arrivalRoom)
	local escapePrompt, safeSpawn, exitPosition, finalExit = makeExitSet(world, roomById("Exit"))
	makeAmbientEmitter(ambienceFolder, "Level 3 Fluorescent Bed", worldPosition(roomById("CentralHall"), 9),
		Configuration.Audio.FluorescentHum, .12, 190)
	makeAmbientEmitter(ambienceFolder, "Level 3 HVAC Bed", worldPosition(roomById("Janitor"), 8),
		Configuration.Audio.HVAC, .10, 150)
	makeAmbientEmitter(ambienceFolder, "Level 3 Distant Drip", worldPosition(roomById("LoadingStore"), 1),
		Configuration.Audio.WaterDrip, .16, 75)
	assert(exitPortal, "Level 3 build requires exactly one hidden exit portal")
	world:SetAttribute("Level3_RoomCount", #Configuration.Rooms)
	world:SetAttribute("Level3_CorridorCount", #Configuration.Links)
	world:SetAttribute("Level3_ModuleCount", #modules)
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
