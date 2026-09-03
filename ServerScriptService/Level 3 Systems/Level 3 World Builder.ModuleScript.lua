--!strict
-- Level 3 World Builder
-- Builds a deliberately authored network of forgotten mall service spaces.

local Configuration = require(script.Parent:WaitForChild("Level 3 Configuration"))
local ReplicatedStorage = game:GetService("ReplicatedStorage")
local ServerStorage = game:GetService("ServerStorage")
local Players = game:GetService("Players")
local RunService = game:GetService("RunService")

local Builder = {}
local C = Configuration.Colors

-- Build-scoped layout authority.  The generated manifest supplies this table;
-- Configuration.Rooms/Links remain only as a recovery fallback for old callers.
local activeLayout: {[string]: any}? = nil

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
	FinalExitDoor = contentTexture("FinalExitDoorTexture", Configuration.Textures.FinalExitDoor),
	KidsDrawingsAtlas = contentTexture("KidsDrawingsAtlasTexture", Configuration.Textures.KidsDrawingsAtlas),
	KidsDrawingsWholesome25 = contentTexture("KidsDrawingsWholesome25Texture", Configuration.Textures.KidsDrawingsWholesome25),
	KidsDrawingsDisturbing25 = contentTexture("KidsDrawingsDisturbing25Texture", Configuration.Textures.KidsDrawingsDisturbing25),
	KidsNotesAtlas = contentTexture("KidsNotesAtlasTexture", Configuration.Textures.KidsNotesAtlas),
	CDCoversAtlas = contentTexture("CDCoversAtlasTexture", Configuration.Textures.CDCoversAtlas),
	DiscPlayerPanel = contentTexture("DiscPlayerPanelTexture", Configuration.Textures.DiskPlayerSurface),
	CRTScreen = contentTexture("CRTScreenTexture", Configuration.Textures.CRTScreenSurface),
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
	local layout = activeLayout
	if layout and layout.RoomById and layout.RoomById[id] then return layout.RoomById[id] end
	local rooms = layout and layout.Rooms or Configuration.Rooms
	for _, room in ipairs(rooms) do
		if room.Id == id then return room end
	end
	error("Unknown Level 3 room: " .. id)
end

local function worldPosition(room: {[string]: any}, y: number?): Vector3
	return Configuration.WorldOrigin + Vector3.new(room.X, y or 0, room.Z)
end

local function roomHeight(room: {[string]: any}): number
	-- The Poolrooms hand-off needs the same tall gateway proportions as Level 2.
	-- Other generated rooms keep their authored/randomized mall ceiling heights.
	if room.Id == "Arrival" then return 30 end
	return tonumber(room.H) or Configuration.RoomHeight
end

local RED_PARTY_ROOMS = {PartyA = true, Records = true}
local NEON_PARTY_ROOMS = {PartyB = true, UtilityWest = true, CentralHall = true}
local CITY_ROOMS = {
	BackOffice = true, BreakRoom = true, Maintenance = true, ChairStore = true,
	CityPlay = true, LostFound = true, Exit = true,
}

local function floorStyle(kind: string, roomId: string?, themeId: string?): (Color3, Enum.Material, string?, number)
	if kind == "Exit" then
		return Color3.fromRGB(70, 71, 66), Enum.Material.DiamondPlate, nil, 10
	elseif (themeId == "City" or themeId == "CityPlay") or (not themeId and kind == "City") then
		return Color3.fromRGB(190, 188, 166), Enum.Material.Carpet, TEXTURES.CityCarpet, Configuration.TextureStuds.CityCarpet
	elseif (themeId == "RedParty" or themeId == "RedCelebration") or (not themeId and roomId and RED_PARTY_ROOMS[roomId]) then
		return Color3.fromRGB(111, 31, 27), Enum.Material.Carpet, TEXTURES.PartyCarpetRed, Configuration.TextureStuds.PartyCarpetRed
	elseif (themeId == "OrangeBlackParty" or themeId == "OrangeParty") or (not themeId and roomId and NEON_PARTY_ROOMS[roomId]) then
		return Color3.fromRGB(13, 17, 24), Enum.Material.Carpet, TEXTURES.PartyCarpetNeon, Configuration.TextureStuds.PartyCarpetNeon
	end
	return C.DarkCarpet, Enum.Material.Carpet, TEXTURES.PartyCarpet, Configuration.TextureStuds.PartyCarpet
end

local function usesWallpaper(room: {[string]: any}): boolean
	if room.WallStyle ~= nil then return room.WallStyle == "PastelWallpaper" end
	if room.ThemeId ~= nil then return (room.ThemeId == "City" or room.ThemeId == "CityPlay") end
	return CITY_ROOMS[room.Id] == true
end

local function wallColor(room: {[string]: any}): Color3
	if usesWallpaper(room) then return Color3.fromRGB(220, 213, 187) end
	if (room.ThemeId == "RedParty" or room.ThemeId == "RedCelebration") then return Color3.fromRGB(145, 58, 48) end
	return Color3.fromRGB(183, 78, 35)
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
	local poolArrivalOpening = room.Id == "Arrival" and side == "West"
	local doorW = poolArrivalOpening and 16.0 or Configuration.CorridorWidth
	local doorH = poolArrivalOpening and 16.0 or Configuration.CorridorHeight
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
	-- Procedural rooms stay readable without allowing the larger map to multiply
	-- dynamic lights beyond the six-player server budget.
	local targetCount = math.clamp(math.floor(area / 2200) + 1, 1, 4)
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

local function makeTable(parent: Instance, cframe: CFrame, party: boolean, chairs: number, styleIndex: number, allowHide: boolean)
	local tableColor = TABLECLOTH_COLORS[(styleIndex - 1) % #TABLECLOTH_COLORS + 1]
	local tableMesh = cloneDecorMesh("FoldingTableTemplate", parent, "Level 3 Vetted Folding Table",
		cframe * CFrame.new(0, 1.72, 0), Vector3.new(11.2, 3.44, 4.35))
	if not tableMesh then
		tableMesh = part(parent, "Level 3 Folding Table", cframe * CFrame.new(0, 3, 0),
			Vector3.new(11.2, .5, 4.35), Color3.fromRGB(201, 198, 185), Enum.Material.SmoothPlastic)
		decorative(tableMesh)
	end
	tableMesh:SetAttribute("Level3_PermanentFurniture", true)
	-- Keep the detailed free mesh decorative, but add one simple invisible
	-- tabletop collider so players cannot walk through the banquet tables.
	local tableCollision = part(parent, "Level 3 Folding Table Collision", cframe * CFrame.new(0, 3.0, 0),
		Vector3.new(11.0, .48, 4.15), Color3.new(), Enum.Material.SmoothPlastic, 1)
	tableCollision:SetAttribute("Level3_TableCollision", true)
	tableCollision:SetAttribute("Level3_PermanentFurniture", true)
	tableCollision.CastShadow = false

	-- LEVEL3_MANAGER_FURNITURE_NAV_20260821
	-- PathfindingService needs the complete table-and-chair footprint, inflated
	-- for the Manager's body, rather than only the thin tabletop collider.
	local furnitureClearance = Configuration.MallManager.AgentRadius
		+ Configuration.MallManager.FurniturePathPadding
	local navExclusion = part(parent, "Level 3 Manager Furniture Nav Exclusion",
		cframe * CFrame.new(0, Configuration.MallManager.AgentHeight * .5, 0),
		Vector3.new(11.2 + furnitureClearance * 2,
			Configuration.MallManager.AgentHeight,
			10.8 + furnitureClearance * 2),
		Color3.new(), Enum.Material.SmoothPlastic, 1)
	decorative(navExclusion)
	-- PathfindingModifier regions must remain queryable when Roblox bakes the nav
	-- mesh. They stay non-collidable, invisible, untouchable, and are ignored by
	-- the Manager's RespectCanCollide physical sweeps.
	navExclusion.CanQuery = true
	navExclusion:SetAttribute("Level3_ManagerFurnitureNavExclusion", true)
	navExclusion:SetAttribute("Level3_PermanentFurniture", true)
	local navModifier = Instance.new("PathfindingModifier")
	navModifier.Name = "Level 3 Manager Furniture Path Modifier"
	navModifier.Label = Configuration.MallManager.FurniturePathLabel
	navModifier.PassThrough = false
	navModifier.Parent = navExclusion

	-- A thin top and four hanging skirts turn the clean folding-table mesh into
	-- a believable disposable party tablecloth without multiplying textures.
	local top = part(parent, "Level 3 Party Tablecloth Top", cframe * CFrame.new(0, 3.48, 0),
		Vector3.new(11.45, .12, 4.62), tableColor, Enum.Material.Fabric)
	decorative(top)
	top:SetAttribute("Level3_PermanentFurniture", true)
	texture(top, TEXTURES.ConfettiTablecloth, Enum.NormalId.Top,
		Configuration.TextureStuds.Tablecloth, Configuration.TextureStuds.Tablecloth, .34)
	if allowHide then
		-- Exactly one table in every generated district room is an authoritative
		-- hiding place. Additional furniture remains visual/collidable without
		-- multiplying prompts, ray occluders, or server occupancy records.
		local hideAnchor = part(parent, "Level 3 Hide Anchor",
			cframe * CFrame.new(0, Configuration.Hiding.HiddenRootHeight, 0),
			Configuration.Hiding.HideVolumeSize, Color3.new(), Enum.Material.SmoothPlastic, 1)
		decorative(hideAnchor)
		hideAnchor:SetAttribute("Level3_HideTableAnchor", true)
		hideAnchor:SetAttribute("Level3_PermanentFurniture", true)
		hideAnchor:SetAttribute("Level3_HideOccupiedUserId", 0)
		local hidePrompt = Instance.new("ProximityPrompt")
		hidePrompt.Name = "HideUnderTablePrompt"
		hidePrompt.ActionText = "HIDE UNDER TABLE"
		hidePrompt.ObjectText = "FOLDING TABLE"
		hidePrompt.HoldDuration = Configuration.Hiding.PromptHoldDuration
		hidePrompt.MaxActivationDistance = Configuration.Hiding.PromptMaxDistance
		hidePrompt.RequiresLineOfSight = false
		hidePrompt.KeyboardKeyCode = Enum.KeyCode.E
		hidePrompt.GamepadKeyCode = Enum.KeyCode.ButtonX
		hidePrompt.Enabled = false
		hidePrompt.Parent = hideAnchor

		local sightOccluder = part(parent, "Level 3 Hide Sight Occluder",
			cframe * CFrame.new(0, Configuration.Hiding.SightOccluderSize.Y * .5, 0),
			Configuration.Hiding.SightOccluderSize, Color3.new(), Enum.Material.SmoothPlastic, 1)
		decorative(sightOccluder)
		sightOccluder.CanCollide = false
		sightOccluder.CanTouch = false
		sightOccluder.CanQuery = true
		sightOccluder:SetAttribute("Level3_HideSightOccluder", true)
		sightOccluder:SetAttribute("Level3_PermanentFurniture", true)
	end

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
			chair:SetAttribute("Level3_PermanentFurniture", true)
			chair:SetAttribute("Level3_ChairTableTarget", tableTarget)
			chair:SetAttribute("Level3_ChairFacingDot", chair.CFrame.LookVector:Dot((tableTarget - chairPosition).Unit))
		end
		if not chair then
			local seat = part(parent, "Level 3 Party Chair", chairCF,
				Vector3.new(2.4, 4.2, 2.5), chairColor, Enum.Material.SmoothPlastic)
			decorative(seat)
			seat:SetAttribute("Level3_PermanentFurniture", true)
			seat:SetAttribute("Level3_ChairTableTarget", tableTarget)
			seat:SetAttribute("Level3_ChairFacingDot", seat.CFrame.LookVector:Dot((tableTarget - chairPosition).Unit))
		end
	end
	return top
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

-- The drawing library contains the original 16-cell atlas plus two new
-- 25-cell transparent atlases: exactly 25 wholesome and 25 disturbing variants.
-- Density is intentionally uneven.  Three rooms become unnerving clusters,
-- several contain only one to four pieces, and every unlisted room has none.
local ROOM_ART_COUNTS = {
	BackOffice = 4,
	BreakRoom = 1,
	Maintenance = 22,
	LoadingStore = 3,
	PartyA = 12,
	CityPlay = 24,
	LostFound = 2,
	PartyB = 20,
	Records = 14,
}

local drawingSerial = 0

local function nextDrawingVariant(): (string, number)
	drawingSerial += 1
	local sequence = (drawingSerial - 1) % 66 + 1
	-- The first 50 placements exhaust every new variant once.  Odd/even
	-- sequencing interleaves innocent and disturbing art instead of grouping
	-- an entire room into a single obvious horror category.
	if sequence <= 50 then
		local cell = math.floor((sequence - 1) / 2) + 1
		if sequence % 2 == 1 then
			return TEXTURES.KidsDrawingsWholesome25, cell
		end
		return TEXTURES.KidsDrawingsDisturbing25, cell
	end
	return TEXTURES.KidsDrawingsAtlas, sequence - 50
end
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
	-- The image atlas carries true alpha.  This part is only a SurfaceGui carrier:
	-- it must never read as a framed sheet glued over the underlying wall.
	local paper = part(parent, name, paperCF, Vector3.new(size.X, size.Y, .008),
		Color3.new(), Enum.Material.SmoothPlastic, 1)
	decorative(paper)
	paper.Transparency = 1
	paper.CanQuery = false
	paper:SetAttribute("Level3_KidsWallArt", true)
	paper:SetAttribute("Level3_TransparentWallArt", true)
	paper:SetAttribute("Level3_AtlasCell", atlasCell)

	local surface = Instance.new("SurfaceGui")
	surface.Name = "Level 3 Kids Wall Art Surface"
	surface.Face = Enum.NormalId.Front
	surface.AlwaysOnTop = false
	-- Let the room light and wall color show through the crayon pigments.
	surface.LightInfluence = .88
	surface.SizingMode = Enum.SurfaceGuiSizingMode.PixelsPerStud
	surface.PixelsPerStud = 80
	surface.ZOffset = 1
	surface.Parent = paper

	local image = Instance.new("ImageLabel")
	image.Name = "Level 3 Kids Wall Art Image"
	image.BackgroundTransparency = 1
	image.BorderSizePixel = 0
	image.Size = UDim2.fromScale(1, 1)
	image.Image = textureId
	local gridSize = 2
	if textureId == TEXTURES.KidsDrawingsAtlas then
		gridSize = 4
	elseif textureId == TEXTURES.KidsDrawingsWholesome25
		or textureId == TEXTURES.KidsDrawingsDisturbing25 then
		gridSize = 5
	end
	local cellSize = 1024 / gridSize
	image.ImageRectSize = Vector2.new(cellSize, cellSize)
	local cell = (atlasCell - 1) % (gridSize * gridSize)
	image.ImageRectOffset = Vector2.new((cell % gridSize) * cellSize, math.floor(cell / gridSize) * cellSize)
	if textureId == TEXTURES.KidsDrawingsAtlas then
		paper:SetAttribute("Level3_DrawingMood", cell < 8 and "Wholesome" or "Disturbing")
		paper:SetAttribute("Level3_DrawingLibraryIndex", cell + 1)
	elseif textureId == TEXTURES.KidsDrawingsWholesome25 then
		paper:SetAttribute("Level3_DrawingMood", "Wholesome")
		paper:SetAttribute("Level3_DrawingLibraryIndex", 17 + cell)
	elseif textureId == TEXTURES.KidsDrawingsDisturbing25 then
		paper:SetAttribute("Level3_DrawingMood", "Disturbing")
		paper:SetAttribute("Level3_DrawingLibraryIndex", 42 + cell)
	end
	image.ScaleType = Enum.ScaleType.Fit
	image.Parent = surface

	for tapeIndex, side in ipairs({-1, 1}) do
		local tape = part(parent, "Level 3 Kids Drawing Tape",
			paperCF * CFrame.new(side * size.X * .31, size.Y * .47, -.013)
				* CFrame.Angles(0, 0, math.rad((seed + tapeIndex * 7) % 9 - 4)),
			Vector3.new(math.min(.48, size.X * .18), .075, .008),
			Color3.fromRGB(205, 185, 126), Enum.Material.SmoothPlastic, .28)
		decorative(tape)
	end
end

local function makeRoomWallDecor(parent: Instance, room: {[string]: any},
	openings: {[string]: boolean}, roomIndex: number)
	local count = ROOM_ART_COUNTS[room.Id] or 0
	if count <= 0 then return end
	local p = worldPosition(room)
	local h = roomHeight(room)
	local sides = {"North", "South", "West", "East"}
	local openSlots = {-0.39, -0.26, -0.16, 0.16, 0.26, 0.39}
	local closedSlots = {-0.39, -0.26, -0.13, 0, 0.13, 0.26, 0.39}
	for artIndex = 1, count do
		local sideIndex = (roomIndex + artIndex - 2) % 4 + 1
		local side = sides[sideIndex]
		local horizontal = side == "North" or side == "South"
		local span = horizontal and room.W or room.D
		local sideOrdinal = math.floor((artIndex - 1) / 4)
		local slots = openings[side] and openSlots or closedSlots
		local alongFraction = slots[sideOrdinal % #slots + 1]
		local along = alongFraction * span
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
		local drawingAtlas, drawingCell = TEXTURES.KidsDrawingsAtlas, 1
		if not isNote then drawingAtlas, drawingCell = nextDrawingVariant() end
		local atlas = isNote and TEXTURES.KidsNotesAtlas or drawingAtlas
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
		local wallInset = Configuration.CorridorWidth * .5 - .015
		if horizontal then
			position += Vector3.new(0, 4.15 + ((corridorIndex + artIndex) % 3) * .72, side * wallInset)
			inward = Vector3.new(0, 0, -side)
		else
			position += Vector3.new(side * wallInset, 4.15 + ((corridorIndex + artIndex) % 3) * .72, 0)
			inward = Vector3.new(-side, 0, 0)
		end
		local isNote = (corridorIndex + artIndex) % 3 == 0
		local drawingAtlas, drawingCell = TEXTURES.KidsDrawingsAtlas, 1
		if not isNote then drawingAtlas, drawingCell = nextDrawingVariant() end
		makeKidsWallPaper(parent,
			isNote and "Level 3 Corridor Kids Notes" or "Level 3 Corridor Child Drawing",
			position, inward,
			isNote and Vector2.new(2.05, 2.15) or Vector2.new(2.7, 2.55),
			isNote and TEXTURES.KidsNotesAtlas or drawingAtlas,
			isNote and ((corridorIndex + artIndex * 2) % 4 + 1) or drawingCell,
			math.rad(((corridorIndex * 9 + artIndex * 5) % 13) - 6),
			corridorIndex * 23 + artIndex)
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
	local speakerY = room.Id == "Arrival" and h - 3.0 or math.min(h - 2.1, 8.4)
	local position = p + Vector3.new(-room.W * .5 + 2.0, speakerY, -room.D * .5 + 2.0)
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
	sound.Volume = Configuration.MusicSequence.SpeakerVolume or .30
	sound.Looped = false
	sound.RollOffMode = Enum.RollOffMode.InverseTapered
	sound.RollOffMinDistance = Configuration.MusicSequence.SpeakerMinDistance or 18
	sound.RollOffMaxDistance = Configuration.MusicSequence.SpeakerMaxDistance or 180
	sound.EmitterSize = 3
	sound.Parent = emitter
	local equalizer = Instance.new("EqualizerSoundEffect")
	equalizer.Name = "Level 3 Distance Muffle"
	equalizer.LowGain = 0
	equalizer.MidGain = 0
	equalizer.HighGain = 0
	equalizer.Parent = sound
end


local function makeExitCorridorSpeaker(parent: Instance, centerPoint: Vector3,
	horizontal: boolean, side: number, index: number)
	local wallInset = Configuration.CorridorWidth * .5 - .40
	local y = Configuration.CorridorHeight - 2.15
	local offset = if horizontal then Vector3.new(0, y, side * wallInset)
		else Vector3.new(side * wallInset, y, 0)
	local inward = if horizontal then Vector3.new(0, -.35, -side)
		else Vector3.new(-side, -.35, 0)
	local position = centerPoint + offset
	local facing = CFrame.lookAt(position, position + inward)

	local model = Instance.new("Model")
	model.Name = string.format("Level 3 Exit Corridor PA Speaker %02d", index)
	model:SetAttribute("Level3_RoomSpeaker", true)
	model:SetAttribute("Level3_ExitCorridorPA", true)
	model:SetAttribute("Level3_RoomId", "ExitCorridor")
	model:SetAttribute("Level3_ExitCorridorPAIndex", index)
	model.Parent = parent

	local housing = part(model, "PA Speaker Housing", facing, Vector3.new(2.65, 1.85, .72),
		Color3.fromRGB(42, 44, 42), Enum.Material.Metal)
	decorative(housing)
	local grille = part(model, "PA Speaker Grille", facing * CFrame.new(0, 0, -.39),
		Vector3.new(2.25, 1.46, .10), Color3.fromRGB(14, 16, 15), Enum.Material.DiamondPlate)
	decorative(grille)
	local bracket = part(model, "PA Speaker Wall Bracket", facing * CFrame.new(0, 0, .52),
		Vector3.new(.72, .72, .42), Color3.fromRGB(61, 61, 55), Enum.Material.Metal)
	decorative(bracket)
	local emitter = part(model, "PA Speaker Emitter", facing * CFrame.new(0, 0, -.52),
		Vector3.new(.16, .16, .16), Color3.new(), Enum.Material.SmoothPlastic, 1)
	decorative(emitter)

	local sound = Instance.new("Sound")
	sound.Name = "Level 3 Room Song Speaker"
	sound.SoundId = Configuration.Audio.RoomListeningSong
	sound.Volume = Configuration.MusicSequence.SpeakerVolume or .30
	sound.Looped = false
	sound.PlaybackSpeed = 1
	sound.RollOffMode = Enum.RollOffMode.InverseTapered
	sound.RollOffMinDistance = Configuration.MusicSequence.SpeakerMinDistance or 18
	sound.RollOffMaxDistance = Configuration.MusicSequence.SpeakerMaxDistance or 180
	sound.EmitterSize = 3
	sound:SetAttribute("Level3_ExitCorridorPA", true)
	sound:SetAttribute("Level3_ExitCorridorPAIndex", index)
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
	if room.Id == "Arrival" then
		-- Keep the direct slide-to-mall sightline open without a separate transfer bay.
		makeRoomSpeaker(parent, room, index)
		return
	elseif room.Kind == "Exit" then
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
		local hideCount = tonumber(room.HideSpotCount)
		local allowHide = if hideCount ~= nil then tableIndex <= hideCount else true
		makeTable(parent, tableCF, true, layout[4], index + tableIndex, allowHide)
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
	if room.HeroRoom == true or room.Id == "PartyB" then
		makeBalloonCluster(parent, p + Vector3.new(-room.W * .32, 0, room.D * .27), index + 11, 11)
		makeBalloonCluster(parent, p + Vector3.new(room.W * .31, 0, -room.D * .29), index + 17, 10)
		makeLooseBalloons(parent, p + Vector3.new(0, 0, room.D * .15), 14, index + 23)
	end
	makeRoomSpeaker(parent, room, index)

	for _, object in ipairs(parent:GetDescendants()) do
		-- The detailed meshes are decorative, but the explicitly tagged invisible
		-- tabletop is gameplay collision. Never let this broad name sweep strip it.
		if object:IsA("BasePart")
			and object:GetAttribute("Level3_TableCollision") ~= true
			and (string.find(object.Name, "Table", 1, true)
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

local function makeHiddenExitDiscPlayer(parent: Instance, frameCF: CFrame): {[string]: any}
	local model = Instance.new("Model")
	model.Name = "Level 3 Signal Hall Disc Player"
	model:SetAttribute("Level3_DiscPlayer", true)
	model:SetAttribute("Level3_DiscPlayerVisualRevision", 2)
	model:SetAttribute("Level3_DiscGoal", Configuration.ModuleGoal)
	model:SetAttribute("Level3_DiscInserted", 0)
	model:SetAttribute("Level3_DiscPlayerTextureSlot", "DiscPlayerPanelTexture")
	model:SetAttribute("Level3_DiscPlayerTexture", TEXTURES.DiscPlayerPanel)
	model:SetAttribute("Level3_CRTScreenTexture", TEXTURES.CRTScreen)
	model.Parent = parent

	-- A battered school AV cart replaces the flat relay cabinet. frameCF looks
	-- toward the concealed corridor, so local +Z is the player-facing side.
	local consoleCF = frameCF * CFrame.new(-10.25, 0, 2.35)
	local charcoal = Color3.fromRGB(24, 27, 28)
	local edge = Color3.fromRGB(61, 65, 64)
	local panel = Color3.fromRGB(9, 12, 13)
	local rubber = Color3.fromRGB(13, 14, 14)
	local offBlue = Color3.fromRGB(10, 27, 34)
	local relayBlue = Color3.fromRGB(70, 170, 255)

	local baseShelf = part(model, "AV Cart Lower Base",
		consoleCF * CFrame.new(0, .72, 0), Vector3.new(5.55, .25, 2.92),
		edge, Enum.Material.Metal)
	baseShelf:SetAttribute("Level3_DiscPlayerStructure", true)

	for _, x in ipairs({-2.25, 2.25}) do
		for _, z in ipairs({-1.08, 1.08}) do
			local fork = part(model, "AV Cart Caster Fork",
				consoleCF * CFrame.new(x, .47, z), Vector3.new(.22, .50, .34),
				edge, Enum.Material.Metal)
			decorative(fork)
			local wheel = part(model, "AV Cart Caster Wheel",
				consoleCF * CFrame.new(x, .25, z), Vector3.new(.34, .70, .70),
				rubber, Enum.Material.Rubber)
			wheel.Shape = Enum.PartType.Cylinder
			wheel.Reflectance = .02
			decorative(wheel)
			wheel:SetAttribute("Level3_AVCartCaster", true)
		end
	end

	local cabinet = part(model, "AV Cart Locked Cabinet",
		consoleCF * CFrame.new(0, 1.95, 0), Vector3.new(5.12, 2.45, 2.50),
		charcoal, Enum.Material.Metal)
	cabinet.Reflectance = .04
	cabinet:SetAttribute("Level3_DiscPlayerStructure", true)
	if TEXTURES.DiscPlayerPanel ~= "" then
		for _, face in ipairs({Enum.NormalId.Left, Enum.NormalId.Right, Enum.NormalId.Top}) do
			local skin = texture(cabinet, TEXTURES.DiscPlayerPanel, face, 3.0, 3.0, .38)
			skin.Name = "AV Cart Generated Cabinet Texture"
		end
	end

	for _, x in ipairs({-1.30, 1.30}) do
		local door = part(model, "AV Cart Cabinet Door",
			consoleCF * CFrame.new(x, 1.95, 1.29), Vector3.new(2.43, 2.15, .12),
			Color3.fromRGB(31, 34, 34), Enum.Material.Metal)
		decorative(door)
		if TEXTURES.DiscPlayerPanel ~= "" then
			local skin = texture(door, TEXTURES.DiscPlayerPanel, Enum.NormalId.Back, 2.4, 2.15, .35)
			skin.Name = "AV Cart Generated Door Texture"
		end
	end
	for _, x in ipairs({-.34, .34}) do
		local handle = part(model, "AV Cart Recessed Handle",
			consoleCF * CFrame.new(x, 1.95, 1.38), Vector3.new(.16, .92, .12),
			Color3.fromRGB(8, 9, 9), Enum.Material.Metal)
		decorative(handle)
	end
	local cabinetLock = part(model, "AV Cart Cabinet Lock",
		consoleCF * CFrame.new(.62, 2.32, 1.39), Vector3.new(.22, .22, .12),
		Color3.fromRGB(177, 164, 113), Enum.Material.Metal)
	cabinetLock.Shape = Enum.PartType.Ball
	decorative(cabinetLock)

	local middleShelf = part(model, "AV Cart VCR Shelf",
		consoleCF * CFrame.new(0, 3.32, 0), Vector3.new(5.55, .24, 2.92),
		edge, Enum.Material.Metal)
	middleShelf:SetAttribute("Level3_DiscPlayerStructure", true)
	for _, x in ipairs({-2.48, 2.48}) do
		local upright = part(model, "AV Cart Upright",
			consoleCF * CFrame.new(x, 4.55, 0), Vector3.new(.20, 2.42, .20),
			edge, Enum.Material.Metal)
		decorative(upright)
	end

	local vcr = part(model, "ZYNTRA VCR CD Relay Deck",
		consoleCF * CFrame.new(0, 4.15, 0), Vector3.new(4.55, 1.10, 2.10),
		charcoal, Enum.Material.Metal)
	vcr.Reflectance = .05
	vcr:SetAttribute("Level3_VCRDeck", true)
	if TEXTURES.DiscPlayerPanel ~= "" then
		for _, face in ipairs({Enum.NormalId.Top, Enum.NormalId.Left, Enum.NormalId.Right}) do
			local skin = texture(vcr, TEXTURES.DiscPlayerPanel, face, 2.4, 2.4, .34)
			skin.Name = "VCR Generated Body Texture"
		end
	end

	local controlPanel = part(model, "Disc Player Control Panel",
		consoleCF * CFrame.new(0, 4.15, 1.11), Vector3.new(4.28, .80, .12),
		panel, Enum.Material.Metal)
	controlPanel.CanCollide = false
	controlPanel.CanTouch = false
	controlPanel.CanQuery = true
	controlPanel:SetAttribute("Level3_DiscPlayerControlPanel", true)

	local topShelf = part(model, "AV Cart Television Shelf",
		consoleCF * CFrame.new(0, 5.48, 0), Vector3.new(5.60, .28, 3.02),
		edge, Enum.Material.Metal)
	topShelf:SetAttribute("Level3_DiscPlayerStructure", true)

	local crtBody = part(model, "ZYNTRA CRT Television",
		consoleCF * CFrame.new(0, 7.25, -.08), Vector3.new(5.15, 3.26, 2.65),
		charcoal, Enum.Material.SmoothPlastic)
	crtBody.Reflectance = .04
	crtBody:SetAttribute("Level3_CRTTelevision", true)
	if TEXTURES.DiscPlayerPanel ~= "" then
		for _, face in ipairs({Enum.NormalId.Top, Enum.NormalId.Left, Enum.NormalId.Right}) do
			local skin = texture(crtBody, TEXTURES.DiscPlayerPanel, face, 3.0, 3.0, .40)
			skin.Name = "CRT Generated Body Texture"
		end
	end

	local crtBezel = part(model, "CRT Thick Front Bezel",
		consoleCF * CFrame.new(-.28, 7.35, 1.30), Vector3.new(4.35, 2.72, .22),
		Color3.fromRGB(12, 15, 16), Enum.Material.SmoothPlastic)
	decorative(crtBezel)
	local screenGlass = part(model, "CRT Phosphor Screen",
		consoleCF * CFrame.new(-.43, 7.40, 1.44), Vector3.new(3.58, 2.25, .12),
		Color3.fromRGB(5, 11, 10), Enum.Material.Glass, .04)
	screenGlass.Reflectance = .08
	decorative(screenGlass)
	screenGlass:SetAttribute("Level3_CRTScreen", true)
	screenGlass:SetAttribute("Level3_CRTScreenTexture", TEXTURES.CRTScreen)

	local screenGui = Instance.new("SurfaceGui")
	screenGui.Name = "CRT Status Screen Surface"
	screenGui.Face = Enum.NormalId.Back
	screenGui.SizingMode = Enum.SurfaceGuiSizingMode.FixedSize
	screenGui.CanvasSize = Vector2.new(800, 600)
	screenGui.LightInfluence = .12
	screenGui.AlwaysOnTop = false
	screenGui.Parent = screenGlass

	local staticImage = Instance.new("ImageLabel")
	staticImage.Name = "CRT Generated Static"
	staticImage.BackgroundColor3 = Color3.fromRGB(3, 7, 6)
	staticImage.BorderSizePixel = 0
	staticImage.Size = UDim2.fromScale(1, 1)
	staticImage.Image = TEXTURES.CRTScreen
	staticImage.ImageColor3 = Color3.fromRGB(181, 201, 187)
	staticImage.ScaleType = Enum.ScaleType.Stretch
	staticImage.ZIndex = 1
	staticImage.Parent = screenGui

	local statusLabel = Instance.new("TextLabel")
	statusLabel.Name = "Disc Player Status Label"
	statusLabel.BackgroundColor3 = Color3.fromRGB(1, 8, 9)
	statusLabel.BackgroundTransparency = .20
	statusLabel.BorderSizePixel = 0
	statusLabel.Position = UDim2.fromScale(.04, .05)
	statusLabel.Size = UDim2.fromScale(.92, .20)
	statusLabel.Font = Enum.Font.Code
	statusLabel.Text = string.format("ZYNTRA TV/VCR RELAY  %d/%d", 0, Configuration.ModuleGoal)
	statusLabel.TextColor3 = Color3.fromRGB(102, 241, 216)
	statusLabel.TextStrokeColor3 = Color3.fromRGB(2, 7, 8)
	statusLabel.TextStrokeTransparency = .40
	statusLabel.TextScaled = true
	statusLabel.ZIndex = 3
	statusLabel.Parent = screenGui

	local instructionLabel = Instance.new("TextLabel")
	instructionLabel.Name = "Disc Player Instruction Label"
	instructionLabel.BackgroundColor3 = Color3.fromRGB(1, 6, 7)
	instructionLabel.BackgroundTransparency = .28
	instructionLabel.BorderSizePixel = 0
	instructionLabel.Position = UDim2.fromScale(.07, .75)
	instructionLabel.Size = UDim2.fromScale(.86, .17)
	instructionLabel.Font = Enum.Font.Code
	instructionLabel.Text = "INSERT CARRIED CDS INTO VCR"
	instructionLabel.TextColor3 = Color3.fromRGB(219, 211, 177)
	instructionLabel.TextStrokeColor3 = Color3.fromRGB(2, 6, 6)
	instructionLabel.TextStrokeTransparency = .42
	instructionLabel.TextScaled = true
	instructionLabel.ZIndex = 3
	instructionLabel.Parent = screenGui

	local controlColumn = part(model, "CRT Side Control Column",
		consoleCF * CFrame.new(1.93, 7.32, 1.43), Vector3.new(.35, 2.30, .13),
		Color3.fromRGB(18, 21, 21), Enum.Material.SmoothPlastic)
	decorative(controlColumn)
	for buttonIndex = 1, 3 do
		local button = part(model, "CRT Channel Button",
			consoleCF * CFrame.new(1.93, 7.86 - buttonIndex * .36, 1.51),
			Vector3.new(.15, .15, .08), Color3.fromRGB(68, 72, 69), Enum.Material.SmoothPlastic)
		button.Shape = Enum.PartType.Ball
		decorative(button)
	end
	local powerLED = part(model, "CRT Power LED",
		consoleCF * CFrame.new(1.93, 6.47, 1.51), Vector3.new(.12, .12, .08),
		Color3.fromRGB(67, 176, 139), Enum.Material.Neon)
	powerLED.Shape = Enum.PartType.Ball
	decorative(powerLED)

	local slots = {}
	local slotSpacing = .78
	for slotIndex = 1, Configuration.ModuleGoal do
		local x = (slotIndex - (Configuration.ModuleGoal + 1) * .5) * slotSpacing
		local receiver = part(model, string.format("Disc Player Slot %02d", slotIndex),
			consoleCF * CFrame.new(x, 4.28, 1.20), Vector3.new(.62, .16, .10),
			Color3.fromRGB(1, 3, 4), Enum.Material.Metal)
		decorative(receiver)
		receiver:SetAttribute("Level3_DiscPlayerSlot", true)
		receiver:SetAttribute("Level3_DiscSlotIndex", slotIndex)
		receiver:SetAttribute("Level3_DiscSlotFilled", false)

		local discCF = consoleCF * CFrame.new(x, 4.28, 1.27) * CFrame.Angles(0, math.pi * .5, 0)
		local insertedDisc = part(model, string.format("Inserted CD Slot Visual %02d", slotIndex),
			discCF, Vector3.new(.10, .56, .56),
			Color3.fromRGB(176, 201, 214), Enum.Material.Metal, 1)
		insertedDisc.Shape = Enum.PartType.Cylinder
		insertedDisc.Reflectance = .32
		decorative(insertedDisc)
		insertedDisc:SetAttribute("Level3_DiscPlayerInsertedVisual", true)
		insertedDisc:SetAttribute("Level3_DiscSlotIndex", slotIndex)

		local insertedHub = part(model, string.format("Inserted CD Slot Hub %02d", slotIndex),
			discCF, Vector3.new(.12, .15, .15),
			Color3.fromRGB(24, 27, 28), Enum.Material.SmoothPlastic, 1)
		insertedHub.Shape = Enum.PartType.Cylinder
		decorative(insertedHub)
		insertedHub:SetAttribute("Level3_DiscPlayerInsertedVisual", true)
		insertedHub:SetAttribute("Level3_DiscSlotIndex", slotIndex)

		local indicator = part(model, string.format("Disc Slot Indicator %02d", slotIndex),
			consoleCF * CFrame.new(x, 3.86, 1.24), Vector3.new(.22, .22, .12),
			offBlue, Enum.Material.SmoothPlastic)
		indicator.Shape = Enum.PartType.Ball
		decorative(indicator)
		indicator:SetAttribute("Level3_DiscSlotIndicator", true)
		indicator:SetAttribute("Level3_DiscSlotIndex", slotIndex)
		indicator:SetAttribute("Level3_DiscSlotFilled", false)

		local indicatorLight = Instance.new("PointLight")
		indicatorLight.Name = string.format("Disc Slot Status Light %02d", slotIndex)
		indicatorLight.Color = relayBlue
		indicatorLight.Brightness = .78
		indicatorLight.Range = 4.5
		indicatorLight.Shadows = false
		indicatorLight.Enabled = false
		indicatorLight:SetAttribute("Level3_DiscSlotIndicatorLight", true)
		indicatorLight:SetAttribute("Level3_DiscSlotIndex", slotIndex)
		indicatorLight.Parent = indicator

		table.insert(slots, {
			Index = slotIndex,
			Receiver = receiver,
			Disc = insertedDisc,
			Hub = insertedHub,
			Indicator = indicator,
			Light = indicatorLight,
		})
	end

	local vcrDisplay = part(model, "VCR Clock Display",
		consoleCF * CFrame.new(-1.58, 3.86, 1.24), Vector3.new(.58, .17, .08),
		Color3.fromRGB(11, 44, 43), Enum.Material.Glass)
	decorative(vcrDisplay)
	local ejectButton = part(model, "VCR Eject Button",
		consoleCF * CFrame.new(1.73, 3.88, 1.24), Vector3.new(.25, .18, .09),
		Color3.fromRGB(75, 77, 73), Enum.Material.SmoothPlastic)
	decorative(ejectButton)

	local prompt = Instance.new("ProximityPrompt")
	prompt.Name = "InsertCDPrompt"
	prompt.ActionText = "INSERT CARRIED CD"
	prompt.ObjectText = string.format("ZYNTRA TV/VCR RELAY  %d/%d", 0, Configuration.ModuleGoal)
	prompt.HoldDuration = .55
	prompt.MaxActivationDistance = 9
	prompt.RequiresLineOfSight = true
	prompt.KeyboardKeyCode = Enum.KeyCode.E
	prompt:SetAttribute("Level3_DiscInsertPrompt", true)
	prompt.Parent = controlPanel

	-- A loose cable makes the mobile cart feel jury-rigged rather than built into the wall.
	for segmentIndex = 1, 3 do
		local cable = part(model, "AV Cart Trailing Power Cable",
			consoleCF * CFrame.new(2.55 + segmentIndex * .16, 1.00 + segmentIndex * .45, -.72 - segmentIndex * .18)
				* CFrame.Angles(0, 0, math.rad(-18)),
			Vector3.new(.58, .10, .10), Color3.fromRGB(8, 9, 9), Enum.Material.Rubber)
		cable.Shape = Enum.PartType.Cylinder
		decorative(cable)
	end

	model.PrimaryPart = cabinet
	return {
		Model = model,
		Prompt = prompt,
		Slots = slots,
		StatusLabel = statusLabel,
		InstructionLabel = instructionLabel,
		Position = controlPanel.Position,
		ControlPanel = controlPanel,
		TextureSlot = "DiscPlayerPanelTexture",
	}
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
	local discPlayer = makeHiddenExitDiscPlayer(model, frameCF)
	model:SetAttribute("Level3_ExitUnlocked", false)
	return {Model=model, Wall=wall, FrameParts=frameParts, Light=light, Position=center, DiscPlayer=discPlayer}
end

local function sideBetween(a: {[string]: any}, b: {[string]: any}): string
	local dx, dz = b.X - a.X, b.Z - a.Z
	if math.abs(dx) > math.abs(dz) then return dx > 0 and "East" or "West" end
	return dz > 0 and "South" or "North"
end

local function connectionMap(): {[string]: {[string]: boolean}}
	local layout = activeLayout
	local rooms = layout and layout.Rooms or Configuration.Rooms
	local links = layout and layout.Links or Configuration.Links
	local map = {}
	for _, room in ipairs(rooms) do map[room.Id] = {} end
	for _, link in ipairs(links) do
		local a, b = roomById(link.A), roomById(link.B)
		map[a.Id][sideBetween(a, b)] = true
		map[b.Id][sideBetween(b, a)] = true
	end
	-- The story-only Level 2 flume mouth opens behind the Level 3 spawn.
	if map.Arrival then map.Arrival.West = true end
	return map
end

local function makeRoom(parent: Instance, room: {[string]: any}, openings: {[string]: boolean}, index: number)
	local model = Instance.new("Model")
	model.Name = string.format("%02d %s", index, room.Name)
	model:SetAttribute("Level3_RoomId", room.Id)
	model:SetAttribute("Level3_RoomKind", room.Kind)
	model:SetAttribute("Level3_District", room.SectionIndex or 0)
	model:SetAttribute("Level3_ThemeId", room.ThemeId or "Legacy")
	model:SetAttribute("Level3_DecorArchetype", room.Decor or "Default")
	model:SetAttribute("Level3_CeilingHeight", roomHeight(room))
	model.Parent = parent
	local p = worldPosition(room)
	local color, material, textureId, studs = floorStyle(room.Kind, room.Id, room.ThemeId)
	local floorPart = part(model, "Level 3 Room Floor", CFrame.new(p - Vector3.new(0, .5, 0)),
		Vector3.new(room.W, Configuration.FloorThickness, room.D), color, material)
	if textureId then texture(floorPart, textureId, Enum.NormalId.Top, studs, studs) end
	part(model, "Level 3 Room Ceiling", CFrame.new(p + Vector3.new(0, roomHeight(room), 0)),
		Vector3.new(room.W, Configuration.CeilingThickness, room.D),
		C.AgedWhite, Enum.Material.Plaster)
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
	model:SetAttribute("Level3_District", link.SectionIndex or 0)
	model:SetAttribute("Level3_ThemeId", link.ThemeId or a.ThemeId or "Legacy")
	model.Parent = parent

	-- Butt the tunnel kit cleanly against each room opening. The former full
	-- wall-thickness overlap put coplanar lintels/pillars in the same space and
	-- produced visible z-fighting. Floors/ceilings get a microscopic seal while
	-- side walls stop just short of the room shell.
	local corridorTheme = link.ThemeId or a.ThemeId
	local floorColor, floorMaterial, floorTexture, studs = floorStyle("PartyHall", nil, corridorTheme)
	local sealedLength = length + .04
	-- Room shells own the opening jambs/lintel. Stop tunnel walls and ceiling
	-- just before those shell volumes so no coplanar faces can shimmer.
	local wallLength = math.max(.1, length - Configuration.WallThickness - .08)
	local floorSize = horizontal and Vector3.new(sealedLength, 1, tunnelWidth)
		or Vector3.new(tunnelWidth, 1, sealedLength)
	local floorPart = part(model, "Level 3 Corridor Floor", CFrame.new(center - Vector3.new(0, .5, 0)),
		floorSize, floorColor, floorMaterial)
	if floorTexture then texture(floorPart, floorTexture, Enum.NormalId.Top, studs, studs) end

	-- Every physical corridor mouth owns an exact, zero-geometry audio marker.
	-- Clients select their nearest markers during the blackout scream, preserving
	-- spatial direction without decoding fifty simultaneous copies of one asset.
	local screamOpenings = {}
	for openingIndex, entry in ipairs({{Side="A", Point=startPoint}, {Side="B", Point=endPoint}}) do
		local opening = Instance.new("Attachment")
		opening.Name = "Level 3 Corridor Opening " .. entry.Side
		opening.CFrame = floorPart.CFrame:ToObjectSpace(CFrame.new(entry.Point + Vector3.new(0, 4.2, 0)))
		opening:SetAttribute("Level3_CorridorOpeningScreamEmitter", true)
		opening:SetAttribute("Level3_CorridorIndex", index)
		opening:SetAttribute("Level3_CorridorOpeningSide", entry.Side)
		opening:SetAttribute("Level3_CorridorOpeningKey", string.format("%02d%s", index, entry.Side))
		opening:SetAttribute("Level3_CorridorDoorType", link.Door)
		opening:SetAttribute("Level3_CorridorOpeningOrder", openingIndex)
		opening.Parent = floorPart
		table.insert(screamOpenings, opening)
	end
	local ceilingSize = horizontal and Vector3.new(wallLength, 1, tunnelWidth)
		or Vector3.new(tunnelWidth, 1, wallLength)
	part(model, "Level 3 Corridor Ceiling",
		CFrame.new(center + Vector3.new(0, tunnelHeight + .5, 0)),
		ceilingSize, C.AgedWhite, Enum.Material.Plaster)

	local corridorStyle = {
		Id = "Corridor", ThemeId = corridorTheme,
		WallStyle = link.WallStyle or a.WallStyle,
	}
	local corridorWallpaper = usesWallpaper(corridorStyle)
	local wallColorValue = wallColor(corridorStyle)
	local wallTexture = corridorWallpaper and TEXTURES.PastelWallpaper or TEXTURES.OrangeWall
	local wallStuds = corridorWallpaper and Configuration.TextureStuds.Wallpaper or Configuration.TextureStuds.OrangeWall
	local wallTransparency = corridorWallpaper and .08 or .28
	local wallMaterial = corridorWallpaper and Enum.Material.SmoothPlastic or Enum.Material.Plaster
	-- CorridorWidth is the clear interior width. Keep each inner wall face
	-- flush with the 14-stud floor/ceiling and the matching room opening.
	local wallCenterOffset = tunnelWidth * .5 + Configuration.WallThickness * .5
	if horizontal then
		for _, z in ipairs({-wallCenterOffset, wallCenterOffset}) do
			local wall = part(model, "Level 3 Corridor Wall",
				CFrame.new(center + Vector3.new(0, tunnelHeight * .5, z)),
				Vector3.new(wallLength, tunnelHeight, Configuration.WallThickness),
				wallColorValue, wallMaterial)
			texture(wall, wallTexture, z < 0 and Enum.NormalId.Front or Enum.NormalId.Back,
				wallStuds, wallStuds, wallTransparency)
		end
	else
		for _, x in ipairs({-wallCenterOffset, wallCenterOffset}) do
			local wall = part(model, "Level 3 Corridor Wall",
				CFrame.new(center + Vector3.new(x, tunnelHeight * .5, 0)),
				Vector3.new(Configuration.WallThickness, tunnelHeight, wallLength),
				wallColorValue, wallMaterial)
			texture(wall, wallTexture, x < 0 and Enum.NormalId.Right or Enum.NormalId.Left,
				wallStuds, wallStuds, wallTransparency)
		end
	end
	makeCorridorWallDecor(model, startPoint, endPoint, horizontal, index)
	local hiddenExit = link.Door == "HiddenExit"
	local speakerCount = if hiddenExit then Configuration.Layout.ExitCorridorSpeakerCount else 0
	if hiddenExit then
		model:SetAttribute("Level3_ExitCorridor", true)
		model:SetAttribute("Level3_ExitCorridorLength", length)
		model:SetAttribute("Level3_ExitCorridorSpeakerCount", speakerCount)
		-- Continuous waist-height service rails visually pull the eye toward the
		-- distant freight door and make the doubled final passage feel intentionally authored.
		for _, side in ipairs({-1, 1}) do
			local railCF = if horizontal
				then CFrame.new(center + Vector3.new(0, 2.25, side * (tunnelWidth * .5 - .08)))
				else CFrame.new(center + Vector3.new(side * (tunnelWidth * .5 - .08), 2.25, 0))
			local railSize = if horizontal then Vector3.new(wallLength, .14, .10)
				else Vector3.new(.10, .14, wallLength)
			local rail = part(model, "Level 3 Exit Corridor Service Rail", railCF, railSize,
				Color3.fromRGB(43, 49, 48), Enum.Material.Metal)
			decorative(rail)
		end
		for speakerIndex = 1, speakerCount do
			local speakerPoint = startPoint:Lerp(endPoint, speakerIndex / (speakerCount + 1))
			local side = if speakerIndex % 2 == 0 then 1 else -1
			makeExitCorridorSpeaker(model, speakerPoint, horizontal, side, speakerIndex)
		end
	end
	local fixtureCount = if hiddenExit then Configuration.Layout.ExitCorridorFixtureCount else 1
	for fixtureIndex = 1, fixtureCount do
		local position = startPoint:Lerp(endPoint, fixtureIndex / (fixtureCount + 1))
		makeFixture(model, position + Vector3.new(0, tunnelHeight - .85, 0),
			"Staff", 400 + index * 4 + fixtureIndex, (index + fixtureIndex) % 9 == 0)
	end
	return {Model=model, Center=center, Forward=forward, Length=length, DoorType=link.Door,
		A=a, B=b, DoorPosition=center, StartPoint=startPoint, EndPoint=endPoint,
		ScreamOpenings=screamOpenings,
		WallColor=wallColorValue, Wallpaper=corridorWallpaper, Width=tunnelWidth, Height=tunnelHeight}
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
	case:SetAttribute("Level3_CDPersistentDisplay", true)
	local cover = part(model, "CD Cover Insert", baseCF * CFrame.new(0, .10, 0), Vector3.new(2.5, .035, 2.38),
		Color3.fromRGB(231, 224, 195), Enum.Material.SmoothPlastic)
	decorative(cover)
	cover:SetAttribute("Level3_CDPersistentDisplay", true)
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
	disc:SetAttribute("Level3_CDPickupVisual", true)
	local hub = part(model, "Compact Disc Hub", disc.CFrame, Vector3.new(.105, .40, .40),
		Color3.fromRGB(28, 30, 31), Enum.Material.SmoothPlastic)
	hub.Shape = Enum.PartType.Cylinder
	decorative(hub)
	hub:SetAttribute("Level3_CDPickupVisual", true)
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
	return {Index=index, RoomId=room.Id, Model=model, Prompt=prompt, Core=case, Pedestal=pedestal,
		PickupParts={disc, hub}}
end

local function makeArrivalElevator(parent: Instance, room: {[string]: any}): (Model, BasePart, BasePart)
	local p = worldPosition(room)
	local visual = Instance.new("Model")
	visual.Name = "Level 2 Exit Slide Continuation"
	visual:SetAttribute("Level3_Level2ExitTube", true)
	visual:SetAttribute("Level3_ProgressionLandmark", true)
	visual.Parent = parent

	-- LEVEL2_EXIT_TRANSITION_20260828
	-- This is the far end of Level 2's exit flume, not a decorative stub. A
	-- player who chose to continue resumes near the REAR of this bore, still
	-- moving, and physically slides the rest of the way out into the mall. That
	-- requires a real run: enough length for the arrival to read as the tail of
	-- one long ride, and enough rise that the resume point is genuinely downhill.
	-- The bore still finishes level with the landing-room floor so the outlet is
	-- a slide mouth rather than a drop.
	local tubeLength, rise, radius = 230, 66, 8
	-- This curve changes slope gradually; 32 longitudinal sections keep each
	-- collision span under eight studs, while a 20-sided bore is already visually
	-- round at this radius. The former 44x40 tessellation created 1,760 shell
	-- colliders for this one prop and pushed the whole level past both its part
	-- and collision budgets without improving the ride.
	local pathSections, shellSegments = 32, 20
	local wallX = p.X - room.W * .5
	local mouthX = wallX + Configuration.WallThickness * .5 + .12
	local centerY = p.Y + radius + .05
	visual:SetAttribute("Level3_SlideMouthPosition", Vector3.new(mouthX, centerY, p.Z))
	visual:SetAttribute("Level3_DirectMallArrival", true)
	local shellColor = Color3.fromRGB(218, 226, 211)
	local shellShadow = Color3.fromRGB(193, 207, 197)
	local slipperyPhysics = PhysicalProperties.new(.7, .02, 0, 100, 1)
	local pathPoints: {Vector3} = {}
	for section = 0, pathSections do
		local alpha = section / pathSections
		table.insert(pathPoints, Vector3.new(
			mouthX - tubeLength * alpha,
			centerY + rise * alpha * alpha,
			p.Z
		))
	end
	for section = 1, pathSections do
		local a, b = pathPoints[section], pathPoints[section + 1]
		local segmentAxis = (b - a).Unit
		local segmentCenter = (a + b) * .5
		local segmentLength = (b - a).Magnitude
		local radialZero = Vector3.zAxis
		for shellIndex = 0, shellSegments - 1 do
			local angle = (shellIndex + .5) / shellSegments * math.pi * 2
			local radial = CFrame.fromAxisAngle(segmentAxis, angle)
				:VectorToWorldSpace(radialZero).Unit
			local tangent = segmentAxis:Cross(radial).Unit
			local panel = part(visual, "Level 2 Exit Slide Fiberglass Shell",
				CFrame.fromMatrix(segmentCenter + radial * radius, segmentAxis, radial, tangent),
				Vector3.new(segmentLength + .14, .30,
					2 * radius * math.tan(math.pi / shellSegments) + .06),
				shellColor, Enum.Material.SmoothPlastic)
			panel.CanCollide = true
			panel.CanTouch = false
			panel.CastShadow = false
			panel.Reflectance = .025
			panel.CustomPhysicalProperties = slipperyPhysics
			panel:SetAttribute("Level3_ProgressionSlide", true)
		end

		local downSeed = -Vector3.yAxis
		local radialDown = (downSeed - segmentAxis * downSeed:Dot(segmentAxis)).Unit
		local floorTangent = segmentAxis:Cross(radialDown).Unit
		local runout = part(visual, "Level 2 Exit Slide Runout",
			CFrame.fromMatrix(segmentCenter + radialDown * (radius + .30),
				segmentAxis, radialDown, floorTangent),
			Vector3.new(segmentLength + .16, .60, 11.8),
			shellShadow, Enum.Material.SmoothPlastic)
		runout.CanCollide = true
		runout.CastShadow = false
		runout.Reflectance = .02
		runout.CustomPhysicalProperties = slipperyPhysics
		runout:SetAttribute("Level3_ProgressionSlide", true)
		-- Keep the mouth visually clean; the wear rails begin one section inside.
		if section > 1 then
			for _, zOffset in ipairs({-3.7, 3.7}) do
				local guide = part(visual, "Level 2 Exit Slide Wear Guide",
					CFrame.fromMatrix(segmentCenter + radialDown * (radius - .10)
						+ floorTangent * zOffset, segmentAxis, radialDown, floorTangent),
					Vector3.new(segmentLength + .10, .10, .30),
					Color3.fromRGB(71, 88, 85), Enum.Material.SmoothPlastic, .05)
				decorative(guide)
			end
		end
	end
	visual:SetAttribute("Level3_SlideRise", rise)
	visual:SetAttribute("Level3_SlideSlipback", true)
	visual:SetAttribute("Level3_SlideLength", tubeLength)

	-- The resume frame: where a continuing Level 2 rider re-enters the world.
	-- It sits just inside the rear safety cap, on the bore axis, with the
	-- tangent pointing down the slide toward the mall. GameManager places the
	-- character here and gives it this velocity, so the ride continues instead
	-- of restarting as a stand-up spawn somewhere else.
	local RESUME_ALPHA = .93
	local RESUME_SPEED = 62
	local resumePosition = Vector3.new(
		mouthX - tubeLength * RESUME_ALPHA,
		centerY + rise * RESUME_ALPHA * RESUME_ALPHA,
		p.Z)
	-- Direction of TRAVEL, which is -d/dalpha: the path is
	-- x = mouthX - tubeLength*alpha, so riding toward the mouth means alpha
	-- decreasing and x increasing. Negating only the Y term (as an earlier
	-- version did) points the rider back up the bore; the slip loop then
	-- silently corrected their velocity while they faced the wrong way.
	local resumeTangent = Vector3.new(tubeLength, -2 * rise * RESUME_ALPHA, 0).Unit
	visual:SetAttribute("Level3_SlideResumePosition", resumePosition)
	visual:SetAttribute("Level3_SlideResumeTangent", resumeTangent)
	visual:SetAttribute("Level3_SlideResumeVelocity", resumeTangent * RESUME_SPEED)
	visual:SetAttribute("Level3_SlideResumeSpeed", RESUME_SPEED)
	local rearPoint = pathPoints[#pathPoints]
	local rearAxis = (rearPoint - pathPoints[#pathPoints - 1]).Unit

	-- Fill only the four square aperture corners with wall-aligned slices.
	-- The ordinary orange plaster finish continues around the slide mouth; the
	-- tube's leading shell edge hides the sub-stud stepped inner boundary.
	local sealCenter = Vector3.new(wallX, centerY, p.Z)
	local sealHalfOpening = radius + .12
	local sealOuterRadius = radius + .15
	-- The leading shell edge hides the stepped inner boundary. Twenty rows keep
	-- every step below one stud without spending 192 decorative parts on a wall
	-- aperture the player only sees while moving at slide speed.
	local sealRows = 20
	local sealRowHeight = sealHalfOpening * 2 / sealRows
	local sealOuterZ = sealHalfOpening + .08
	local sealDepth = Configuration.WallThickness - .02
	for rowIndex = 0, sealRows - 1 do
		local y0 = -sealHalfOpening + rowIndex * sealRowHeight
		local y1 = y0 + sealRowHeight
		local yOffset = (y0 + y1) * .5
		local farY = math.max(math.abs(y0), math.abs(y1))
		local circleHalfWidth = math.sqrt(math.max(0,
			sealOuterRadius * sealOuterRadius - farY * farY))
		local innerZ = math.max(0, circleHalfWidth - .01)
		local stripWidth = sealOuterZ - innerZ
		local zOffset = (innerZ + sealOuterZ) * .5
		for _, side in ipairs({-1, 1}) do
			local sideName = side < 0 and "Left" or "Right"
			local seal = part(visual,
				"Level 3 West Wall Circular Aperture Fill " .. sideName,
				CFrame.new(sealCenter + Vector3.new(0, yOffset, side * zOffset)),
				Vector3.new(sealDepth, sealRowHeight + .03, stripWidth),
				wallColor(room), Enum.Material.Plaster)
			decorative(seal)
			seal.CastShadow = false
			seal:SetAttribute("Level3_TransitionWallSeal", true)
		end
	end

	-- The physical safety stop sits far beyond the upward bend. A muted pale
	-- shadow cap prevents outdoor sky from leaking through without reading as a portal.
	local rearUp = (Vector3.yAxis - rearAxis * Vector3.yAxis:Dot(rearAxis)).Unit
	local rearTangent = rearAxis:Cross(rearUp).Unit
	local field = part(visual, "One Way Pool Exit Field",
		CFrame.fromMatrix(rearPoint, rearAxis, rearUp, rearTangent),
		Vector3.new(.42, 14.8, 14.8),
		Color3.fromRGB(142, 153, 147), Enum.Material.SmoothPlastic, .02)
	field.CanCollide = true
	field.CastShadow = true
	field:SetAttribute("Level3_ReturnPathSealed", true)

	local mouthLightAnchor = part(visual, "Poolrooms Slide Mouth Light Anchor",
		CFrame.new(mouthX + 1.2, centerY + 1.0, p.Z),
		Vector3.new(.2, .2, .2), Color3.new(), Enum.Material.SmoothPlastic, 1)
	decorative(mouthLightAnchor)
	local mouthGlow = Instance.new("PointLight")
	mouthGlow.Name = "Poolrooms Slide Mouth Fill"
	mouthGlow.Color = Color3.fromRGB(226, 235, 214)
	mouthGlow.Brightness = .82
	mouthGlow.Range = 30
	mouthGlow.Shadows = false
	mouthGlow.Parent = mouthLightAnchor

	local depthLightAnchor = part(visual, "Poolrooms Slide Depth Light Anchor",
		CFrame.new(pathPoints[math.floor(#pathPoints * .56)]),
		Vector3.new(.2, .2, .2), Color3.new(), Enum.Material.SmoothPlastic, 1)
	decorative(depthLightAnchor)
	local depthGlow = Instance.new("PointLight")
	depthGlow.Name = "Poolrooms Slide Indirect Depth Fill"
	depthGlow.Color = Color3.fromRGB(194, 210, 201)
	depthGlow.Brightness = .48
	depthGlow.Range = 38
	depthGlow.Shadows = false
	depthGlow.Parent = depthLightAnchor

	-- Low-friction parts communicate the material; this lightweight server loop
	-- makes the one-way behavior deterministic for every avatar controller.
	-- Fast enough to read as the tail of a long slide; slow enough that the
	-- arrival into the mall is survivable and controllable.
	local SLIDE_MINIMUM_SPEED = 48
	local slipAccumulator = 0
	local slipConnection: RBXScriptConnection?
	slipConnection = RunService.Heartbeat:Connect(function(deltaTime)
		if not visual:IsDescendantOf(workspace) then
			if slipConnection then slipConnection:Disconnect() end
			-- The world can be torn down with a rider still in the bore. Release
			-- every PlatformStand this loop set, or that player stays a ragdoll
			-- for the rest of their session.
			for _, player in ipairs(Players:GetPlayers()) do
				local character = player.Character
				local humanoid = character and character:FindFirstChildOfClass("Humanoid")
				if humanoid and character:GetAttribute("Level3_ProgressionSliding") == true then
					humanoid.PlatformStand = false
					character:SetAttribute("Level3_ProgressionSliding", nil)
				end
			end
			return
		end
		slipAccumulator += deltaTime
		if slipAccumulator < .08 then return end
		slipAccumulator = 0
		for _, player in ipairs(Players:GetPlayers()) do
			local character = player.Character
			local humanoid = character and character:FindFirstChildOfClass("Humanoid")
			local root = character and character:FindFirstChild("HumanoidRootPart")
			if humanoid and humanoid.Health > 0 and root and root:IsA("BasePart") then
				local alpha = (mouthX - root.Position.X) / tubeLength
				local pathY = centerY + rise * alpha * alpha
				local insideBore = alpha > .025 and alpha < .99
					and math.abs(root.Position.Z - p.Z) < radius - .8
					and math.abs(root.Position.Y - pathY) < radius + 2
				if insideBore then
					-- LEVEL2_EXIT_TRANSITION_20260828
					-- This is the tail of Level 2's flume, so it has to ride like
					-- one. PlatformStand takes the humanoid controller out of the
					-- way: without it the character stays in Running, resists the
					-- imposed velocity and WALKS the bore at about 16 studs/s,
					-- which reads as a corridor rather than the end of a slide.
					if not humanoid.PlatformStand then
						humanoid.PlatformStand = true
						character:SetAttribute("Level3_ProgressionSliding", true)
					end
					-- Push along the live path tangent rather than world +X, so
					-- the steep rear section drives the rider forward instead of
					-- straight down into the shell.
					local tangent = Vector3.new(tubeLength, -2 * rise * alpha, 0).Unit
					-- The shared slide controller owns production client physics and
					-- releases the actual body joints. Keep this velocity write only as
					-- a server fallback until its replicated ragdoll session is live.
					if character:GetAttribute("Level2_RagdollServerActive") ~= true then
						local velocity = root.AssemblyLinearVelocity
						local along = velocity:Dot(tangent)
						local lateral = velocity - tangent * along
						root.AssemblyLinearVelocity = tangent * math.max(along, SLIDE_MINIMUM_SPEED)
							+ lateral * .35
					end
				elseif character:GetAttribute("Level3_ProgressionSliding") == true then
					-- Out of the bore: hand control straight back. Leaving
					-- PlatformStand set would drop the arriving player onto the
					-- mall floor as an inert ragdoll.
					-- If the shared ragdoll service is still live, let its client End
					-- restore joints and humanoid state atomically instead of racing it.
					if character:GetAttribute("Level2_RagdollServerActive") ~= true then
						humanoid.PlatformStand = false
						character:SetAttribute("Level3_ProgressionSliding", nil)
					end
				end
			end
		end
	end)

	-- Invisible compatibility elevator retained for GameManager choreography.
	local model = Instance.new("Model")
	model.Name = "Elevator"
	model.Parent = workspace
	local compatibilityCF = CFrame.new(rearPoint)
	local doorL = part(model, "DoorL", compatibilityCF, Vector3.new(.2, .2, .2), Color3.new(), Enum.Material.SmoothPlastic, 1)
	local doorR = part(model, "DoorR", compatibilityCF, Vector3.new(.2, .2, .2), Color3.new(), Enum.Material.SmoothPlastic, 1)
	decorative(doorL)
	decorative(doorR)
	model.PrimaryPart = doorL

	-- Twenty-six studs of reveal distance frame the clean tube mouth on narrow
	-- mobile screens while the forward vector still leads naturally into Level 3.
	local spawnPosition = p + Vector3.new(-room.W * .5 + 26, .25, 0)
	local spawnCF = CFrame.lookAt(spawnPosition, p + Vector3.new(2, .25, 0))
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

local function makeMallManagerSpawn(parent: Instance, spawnRoomId: string): BasePart
	local spawnRoom = roomById(spawnRoomId)
	local floorPosition = worldPosition(spawnRoom)
	local marker = part(parent, "Mall Manager Spawn",
		CFrame.new(floorPosition + Vector3.new(0, .05, 0)), Vector3.new(2, .1, 2),
		Color3.new(0, 0, 0), Enum.Material.SmoothPlastic, 1)
	decorative(marker)
	marker:SetAttribute("Level3_MallManagerSpawn", true)
	marker:SetAttribute("Level3_SpawnRoomId", spawnRoom.Id)
	marker:SetAttribute("Level3_FloorY", floorPosition.Y)
	return marker
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

function Builder.Build(layout: {[string]: any}, generation: number): {[string]: any}
	assert(type(layout) == "table" and type(layout.Rooms) == "table" and type(layout.Links) == "table",
		"Level 3 World Builder requires a validated generated layout")
	activeLayout = layout
	drawingSerial = 0
	local existing = workspace:FindFirstChild(Configuration.WorldName)
	if existing then existing:Destroy() end
	local stagedExisting = ServerStorage:FindFirstChild(Configuration.WorldName)
	if stagedExisting then stagedExisting:Destroy() end
	local world = Instance.new("Model")
	world.Name = Configuration.WorldName
	world:SetAttribute("Level3_Generation", generation)
	world:SetAttribute("Level3_VisualRevision", Configuration.Version)
	world:SetAttribute("Level3_Theme", "Three District Abandoned Mall Backrooms")
	world:SetAttribute("Level3_LayoutHash", layout.LayoutHash or "")
	world:SetAttribute("Level3_ResolvedSeed", layout.ResolvedSeed or 0)
	world:SetAttribute("Level3_GeneratorVersion", layout.Version or Configuration.Layout.GeneratorVersion)
	-- Build away from Workspace so clients never stream a half-built maze.  The
	-- loading screen remains authoritative until the completed model is published.
	world.Parent = ServerStorage
	local roomsFolder = folder(world, "Rooms")
	local corridorsFolder = folder(world, "Corridors")
	local doorsFolder = folder(world, "Doors")
	local modulesFolder = folder(world, "Birthday Music CDs")
	local ambienceFolder = folder(world, "Ambient Emitters")
	local mallManagerRuntime = folder(world, "Mall Manager Runtime")
	local openings = connectionMap()
	local manifestRooms = {}
	for index, room in ipairs(layout.Rooms) do
		manifestRooms[room.Id] = makeRoom(roomsFolder, room, openings[room.Id], index)
		if index % Configuration.Layout.BuildYieldEveryRooms == 0 then task.wait() end
	end
	local doors = {}
	local corridors = {}
	local blackoutScreamOpenings = {}
	local exitPortal
	local finalHall
	for index, link in ipairs(layout.Links) do
		local corridor = makeCorridor(corridorsFolder, link, index)
		table.insert(corridors, corridor)
		for _, opening in ipairs(corridor.ScreamOpenings) do
			table.insert(blackoutScreamOpenings, opening)
		end
		if link.Door == "HiddenExit" then
			exitPortal = makeHiddenExitPortal(doorsFolder, corridor)
			local halfwayProgress = Configuration.Layout.FinalHallHalfwayProgress or .50
			local spawnProgress = Configuration.MallManager.FinalHallSpawnProgress or .40
			local halfwayMarker = part(corridor.Model, "Level 3 Final Hall Halfway",
				CFrame.new(corridor.StartPoint:Lerp(corridor.EndPoint, halfwayProgress) + Vector3.new(0, .05, 0)),
				Vector3.new(2, .1, 2), Color3.new(0, 0, 0), Enum.Material.SmoothPlastic, 1)
			decorative(halfwayMarker)
			halfwayMarker:SetAttribute("Level3_FinalHallHalfway", true)
			halfwayMarker:SetAttribute("Level3_FinalHallProgress", halfwayProgress)
			local spawnMarker = part(corridor.Model, "Level 3 Mall Manager Finale Spawn",
				CFrame.new(corridor.StartPoint:Lerp(corridor.EndPoint, spawnProgress) + Vector3.new(0, .05, 0)),
				Vector3.new(2, .1, 2), Color3.new(0, 0, 0), Enum.Material.SmoothPlastic, 1)
			decorative(spawnMarker)
			spawnMarker:SetAttribute("Level3_MallManagerFinaleSpawn", true)
			spawnMarker:SetAttribute("Level3_FinalHallProgress", spawnProgress)
			finalHall = {
				Corridor = corridor,
				Model = corridor.Model,
				StartPoint = corridor.StartPoint,
				EndPoint = corridor.EndPoint,
				Forward = corridor.Forward,
				Length = corridor.Length,
				Width = corridor.Width,
				Height = corridor.Height,
				FloorY = corridor.StartPoint.Y,
				HalfwayProgress = halfwayProgress,
				SpawnProgress = spawnProgress,
				HalfwayMarker = halfwayMarker,
				SpawnMarker = spawnMarker,
			}
		end
		if index % Configuration.Layout.BuildYieldEveryCorridors == 0 then task.wait() end
	end
	-- Revision 3 deliberately has no ordinary or fake doors. Every connection
	-- stays open; only the concealed exit portal and final freight door remain.
	local modules = {}
	for _, room in ipairs(layout.Rooms) do
		if room.Module then
			table.insert(modules, makeModule(modulesFolder, room, #modules + 1, manifestRooms[room.Id]))
		end
	end
	assert(#modules == Configuration.ModuleGoal, "Level 3 CD goal does not match authored CD rooms")
	local roles = layout.Roles or {}
	local arrivalRoom = roomById(roles.ArrivalRoomId or "Arrival")
	local elevator, elevatorSpawn, mazeStart = makeArrivalElevator(world, arrivalRoom)
	local spawnRoomId = roles.MallManagerSpawnRoomId or roles.SignalRoomId or Configuration.MallManager.SpawnRoomId
	local mallManagerSpawn = makeMallManagerSpawn(world, spawnRoomId)
	local escapePrompt, safeSpawn, exitPosition, finalExit = makeExitSet(world, roomById(roles.ExitRoomId or "Exit"))
	-- Publish the complete hierarchy once, then start spatial ambience.  This
	-- avoids a room-by-room replication burst during procedural construction.
	world.Parent = workspace
	makeAmbientEmitter(ambienceFolder, "Level 3 HVAC Bed", worldPosition(roomById(roles.AmbientHVACRoomId or spawnRoomId), 8),
		Configuration.Audio.HVAC, .10, 150)
	assert(exitPortal, "Level 3 build requires exactly one hidden exit portal")
	assert(finalHall, "Level 3 build requires exactly one final HiddenExit hall")
	world:SetAttribute("Level3_FinalHallLength", finalHall.Length)
	world:SetAttribute("Level3_FinalHallHalfwayProgress", finalHall.HalfwayProgress)
	world:SetAttribute("Level3_FinalHallSpawnProgress", finalHall.SpawnProgress)
	world:SetAttribute("Level3_RoomCount", #layout.Rooms)
	world:SetAttribute("Level3_CorridorCount", #layout.Links)
	world:SetAttribute("Level3_DistrictCount", #(layout.Districts or {}))
	world:SetAttribute("Level3_BlackoutScreamOpeningCount", #blackoutScreamOpenings)
	world:SetAttribute("Level3_ModuleCount", #modules)
	world:SetAttribute("Level3_MallManagerSpawnRoom", spawnRoomId)
	-- Decorative helper calls intentionally strip interaction. Reassert the
	-- tabletop collider, query-only sight cloth, and collect every hide anchor.
	local hideTables = {}
	for _, object in ipairs(world:GetDescendants()) do
		if object:IsA("BasePart") and object:GetAttribute("Level3_TableCollision") == true then
			object.CanCollide = true
			object.CanTouch = false
			object.CanQuery = true
		elseif object:IsA("BasePart") and object:GetAttribute("Level3_HideSightOccluder") == true then
			object.CanCollide = false
			object.CanTouch = false
			object.CanQuery = true
		elseif object:IsA("BasePart") and object:GetAttribute("Level3_HideTableAnchor") == true then
			object.CanCollide = false
			object.CanTouch = false
			object.CanQuery = false
			table.insert(hideTables, object)
		end
	end
	table.sort(hideTables, function(a, b)
		if a.Position.X ~= b.Position.X then return a.Position.X < b.Position.X end
		return a.Position.Z < b.Position.Z
	end)
	for index, anchor in ipairs(hideTables) do
		anchor:SetAttribute("Level3_HideTableIndex", index)
		local prompt = anchor:FindFirstChild("HideUnderTablePrompt")
		if prompt and prompt:IsA("ProximityPrompt") then
			prompt.ObjectText = string.format("FOLDING TABLE %02d", index)
		end
	end
	world:SetAttribute("Level3_HideTableCount", #hideTables)
	return {
		World=world,
		Layout=layout,
		Rooms=manifestRooms,
		Corridors=corridors,
		BlackoutScreamOpenings=blackoutScreamOpenings,
		Doors=doors,
		Modules=modules,
		MallManagerSpawn=mallManagerSpawn,
		MallManagerRuntime=mallManagerRuntime,
		HideTables=hideTables,
		ExitPortal=exitPortal,
		DiscPlayer=exitPortal and exitPortal.DiscPlayer or nil,
		EscapePrompt=escapePrompt,
		ExitSafeSpawn=safeSpawn,
		ExitPosition=exitPosition,
		FinalExit=finalExit,
		FinalHall=finalHall,
		Elevator=elevator,
		ElevatorSpawn=elevatorSpawn,
		MazeStart=mazeStart,
		Generation=generation,
	}
end

return Builder
