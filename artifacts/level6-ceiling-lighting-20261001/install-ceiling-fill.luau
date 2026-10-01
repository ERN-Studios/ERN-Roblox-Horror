
local R=game:GetService("RunService")
assert(not R:IsRunning(),"Edit required")
assert(game.PlaceId==131311258779917 and game.GameId==10559217407,"Wrong place")
local SES=game:GetService("ScriptEditorService")
local E=game:GetService("EncodingService")
local H=game:GetService("HttpService")
local function sha(s)
 local b=E:ComputeBufferHash(buffer.fromstring(s),Enum.HashAlgorithm.Sha256)
 local chars={} for i=0,buffer.len(b)-1 do chars[#chars+1]=string.format("%02x",buffer.readu8(b,i)) end return table.concat(chars)
end
local rows={}

do
 local instance=game
 for _,name in ipairs({"ServerScriptService","Level 6 Systems","Level 6 World Builder"}) do instance=instance:FindFirstChild(name) assert(instance,"Missing "..name) end
 assert(instance.ClassName=="ModuleScript","Class changed")
 local source=instance.Source
 assert(sha(source)=="248d9254bc9d0c6a836cbb46a2d5481d55a07bcc5a70a9042e7fe465441c7c58","Fresh Source changed: "..instance:GetFullName())
 assert(SES:GetEditorSource(instance)==source,"Source/editor conflict")
 local candidate=[====[--!strict
-- Level 6 World Builder
-- Builds a deliberately authored network of forgotten mall service spaces.

local Configuration = require(script.Parent:WaitForChild("Level 6 Configuration"))
local ReplicatedStorage = game:GetService("ReplicatedStorage")
local ServerStorage = game:GetService("ServerStorage")
local Players = game:GetService("Players")
local RunService = game:GetService("RunService")

local SlideSafety = require(ReplicatedStorage:WaitForChild("SlideContinuationSafety"))
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
	image.Name = "Level 6 Surface Texture"
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
	error("Unknown Level 6 room: " .. id)
end

local function worldPosition(room: {[string]: any}, y: number?): Vector3
	return Configuration.WorldOrigin + Vector3.new(room.X, y or 0, room.Z)
end

local function roomHeight(room: {[string]: any}): number
	-- The Poolrooms hand-off needs the same tall gateway proportions as Level 2.
	-- Other generated rooms keep their authored/randomized mall ceiling heights.
	if room.Id == "Arrival" then return 12 end
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
	-- The bore rises slightly through the wall thickness; clear its top vertex.
	local doorH = poolArrivalOpening and 16.1 or Configuration.CorridorHeight
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
		wallSegment(parent, "Level 6 " .. side .. " Wall", cfAlong(0, h * 0.5),
			wallSize(length + t, h), color, face, wallpaper)
	else
		local sideLength = math.max(0.5, (length - doorW) * 0.5)
		local offset = doorW * 0.5 + sideLength * 0.5
		wallSegment(parent, "Level 6 " .. side .. " Wall A", cfAlong(-offset, h * 0.5),
			wallSize(sideLength + 0.1, h), color, face, wallpaper)
		wallSegment(parent, "Level 6 " .. side .. " Wall B", cfAlong(offset, h * 0.5),
			wallSize(sideLength + 0.1, h), color, face, wallpaper)
		local lintelHeight = h - doorH
		if lintelHeight > .05 then
			wallSegment(parent, "Level 6 " .. side .. " Lintel",
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
		local seam = part(parent, "Level 6 Ceiling Grid", CFrame.new(p + Vector3.new(x, y, 0)),
			Vector3.new(.08, .04, room.D - 1.5), Color3.fromRGB(83, 79, 67), Enum.Material.Metal, .38)
		decorative(seam)
	end
	for z = -room.D * .5 + spacing, room.D * .5 - spacing, spacing do
		local seam = part(parent, "Level 6 Ceiling Grid", CFrame.new(p + Vector3.new(0, y, z)),
			Vector3.new(room.W - 1.5, .04, .08), Color3.fromRGB(83, 79, 67), Enum.Material.Metal, .38)
		decorative(seam)
	end
end

local function makeFixture(parent: Instance, position: Vector3, kind: string, index: number, dead: boolean): BasePart
	local frame = part(parent, "Level 6 Fluorescent Frame", CFrame.new(position),
		Vector3.new(7.5, .32, 2.4), Color3.fromRGB(85, 84, 75), Enum.Material.Metal)
	decorative(frame)
	local diffuser = part(parent, "Level 6 Fluorescent Diffuser", CFrame.new(position - Vector3.new(0, .20, 0)),
		Vector3.new(7.05, .14, 2.05), dead and Color3.fromRGB(92, 88, 72) or lightTone(kind),
		dead and Enum.Material.SmoothPlastic or Enum.Material.Neon, dead and .18 or .03)
	decorative(diffuser)
	if not dead then
		local light = Instance.new("SurfaceLight")
		light.Name = "Level 6 Fluorescent Light"
		light.Face = Enum.NormalId.Bottom
		light.Color = lightTone(kind)
		-- Broad, readable fluorescent spill.  The fixtures remain artificial and
		-- uneven, but the carpet/furniture must not collapse into black silhouettes
		-- on mobile displays.
		light.Brightness = (kind == "Party" or kind == "PartyHall") and 1.95 or 1.85
		light.Range = 42
		light.Angle = 140
		light.Shadows = false
		light.Parent = diffuser
		-- Low-strength reflected fluorescent fill reveals the ceiling's authored
		-- tiles/grid. Keep the existing downward lamp, palette and grade intact.
		-- Parenting through the primary light keeps this anchor with the Blender
		-- diffuser when the visual adapter transfers that light.
		local bounceAnchor = Instance.new("Attachment")
		bounceAnchor.Name = "Level 6 Ceiling Bounce Anchor"
		bounceAnchor.CFrame = CFrame.new(0, -1.2, 0)
		bounceAnchor.Parent = light
		local bounce = Instance.new("PointLight")
		bounce.Name = "Level 6 Ceiling Bounce"
		bounce.Color = light.Color
		bounce.Brightness = .16
		bounce.Range = 28
		bounce.Shadows = false
		bounce:SetAttribute("Level6_CeilingBounce", true)
		bounce:SetAttribute("Level6_PrimaryBrightness", light.Brightness)
		bounce.Parent = bounceAnchor
		-- Roughly one in seven working fixtures receives independent client-side
		-- ballast instability. Timing stays random per client while the selected
		-- fixtures remain stable for the generated layout.
		if index % 7 == 0 then diffuser:SetAttribute("Level6_SubtleFlicker", true) end
	end
	return diffuser
end

local function makeRoomLights(parent: Instance, room: {[string]: any}, roomIndex: number)
	local p = worldPosition(room)
	local area = room.W * room.D
	-- Four working lamps at quarter positions cover the large procedural rooms
	-- even after the outdoor fill is removed. Smaller service/arrival rooms use
	-- at most two; no room can randomly lose its only useful ceiling light.
	local positions: {Vector3}
	if area >= 4500 then
		positions = {
			Vector3.new(-room.W * .25, 0, -room.D * .25),
			Vector3.new(room.W * .25, 0, -room.D * .25),
			Vector3.new(-room.W * .25, 0, room.D * .25),
			Vector3.new(room.W * .25, 0, room.D * .25),
		}
	elseif area >= 2800 then
		positions = {Vector3.new(-room.W * .25, 0, 0), Vector3.new(room.W * .25, 0, 0)}
	else
		positions = {Vector3.zero}
	end
	for index, offset in ipairs(positions) do
		makeFixture(parent, p + offset + Vector3.new(0, roomHeight(room) - .85, 0),
			room.Kind, roomIndex * 10 + index, false)
	end
	-- An occasional failed ballast is still visible as abandoned-mall dressing,
	-- but it never replaces one of the working lights above.
	if area >= 4500 and roomIndex % 7 == 0 then
		makeFixture(parent, p + Vector3.new(0, roomHeight(room) - .85, 0),
			room.Kind, roomIndex * 10 + 5, true)
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

-- The complete table/chair ground footprint is shared by exclusion creation
-- and compact room placement. Body padding is added exactly once.
local TABLE_GROUP_FOOTPRINT = Vector2.new(11.2, 10.8)
local TABLE_GROUP_VISUAL_FOOTPRINT = Vector2.new(11.45, 10.8)

local function makeTable(parent: Instance, cframe: CFrame, party: boolean, chairs: number, styleIndex: number, allowHide: boolean)
	local tableColor = TABLECLOTH_COLORS[(styleIndex - 1) % #TABLECLOTH_COLORS + 1]
	local tableMesh = cloneDecorMesh("FoldingTableTemplate", parent, "Level 6 Vetted Folding Table",
		cframe * CFrame.new(0, 1.72, 0), Vector3.new(11.2, 3.44, 4.35))
	if not tableMesh then
		tableMesh = part(parent, "Level 6 Folding Table", cframe * CFrame.new(0, 3, 0),
			Vector3.new(11.2, .5, 4.35), Color3.fromRGB(201, 198, 185), Enum.Material.SmoothPlastic)
		decorative(tableMesh)
	end
	tableMesh:SetAttribute("Level6_PermanentFurniture", true)
	-- Keep the detailed free mesh decorative, but add one simple invisible
	-- tabletop collider so players cannot walk through the banquet tables.
	local tableCollision = part(parent, "Level 6 Folding Table Collision", cframe * CFrame.new(0, 3.0, 0),
		Vector3.new(11.0, .48, 4.15), Color3.new(), Enum.Material.SmoothPlastic, 1)
	tableCollision:SetAttribute("Level6_TableCollision", true)
	tableCollision:SetAttribute("Level6_PermanentFurniture", true)
	tableCollision.CastShadow = false

	-- LEVEL6_MANAGER_FURNITURE_NAV_20260821
	-- PathfindingService needs the complete table-and-chair footprint, inflated
	-- for the Manager's body, rather than only the thin tabletop collider.
	local furnitureClearance = Configuration.MallManager.AgentRadius
		+ Configuration.MallManager.FurniturePathPadding
	local navExclusion = part(parent, "Level 6 Manager Furniture Nav Exclusion",
		cframe * CFrame.new(0, Configuration.MallManager.AgentHeight * .5, 0),
		Vector3.new(TABLE_GROUP_FOOTPRINT.X + furnitureClearance * 2,
			Configuration.MallManager.AgentHeight,
			TABLE_GROUP_FOOTPRINT.Y + furnitureClearance * 2),
		Color3.new(), Enum.Material.SmoothPlastic, 1)
	decorative(navExclusion)
	-- PathfindingModifier regions must remain queryable when Roblox bakes the nav
	-- mesh. They stay non-collidable, invisible, untouchable, and are ignored by
	-- the Manager's RespectCanCollide physical sweeps.
	navExclusion.CanQuery = true
	navExclusion:SetAttribute("Level6_ManagerFurnitureNavExclusion", true)
	navExclusion:SetAttribute("Level6_PermanentFurniture", true)
	local navModifier = Instance.new("PathfindingModifier")
	navModifier.Name = "Level 6 Manager Furniture Path Modifier"
	navModifier.Label = Configuration.MallManager.FurniturePathLabel
	navModifier.PassThrough = false
	navModifier.Parent = navExclusion

	-- A thin top and four hanging skirts turn the clean folding-table mesh into
	-- a believable disposable party tablecloth without multiplying textures.
	local top = part(parent, "Level 6 Party Tablecloth Top", cframe * CFrame.new(0, 3.48, 0),
		Vector3.new(11.45, .12, 4.62), tableColor, Enum.Material.Fabric)
	decorative(top)
	top:SetAttribute("Level6_PermanentFurniture", true)
	texture(top, TEXTURES.ConfettiTablecloth, Enum.NormalId.Top,
		Configuration.TextureStuds.Tablecloth, Configuration.TextureStuds.Tablecloth, .34)
	if allowHide then
		-- Exactly one table in every generated district room is an authoritative
		-- hiding place. Additional furniture remains visual/collidable without
		-- multiplying prompts, ray occluders, or server occupancy records.
		local hideAnchor = part(parent, "Level 6 Hide Anchor",
			cframe * CFrame.new(0, Configuration.Hiding.HiddenRootHeight, 0),
			Configuration.Hiding.HideVolumeSize, Color3.new(), Enum.Material.SmoothPlastic, 1)
		decorative(hideAnchor)
		hideAnchor:SetAttribute("Level6_HideTableAnchor", true)
		hideAnchor:SetAttribute("Level6_PermanentFurniture", true)
		hideAnchor:SetAttribute("Level6_HideOccupiedUserId", 0)
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

		local sightOccluder = part(parent, "Level 6 Hide Sight Occluder",
			cframe * CFrame.new(0, Configuration.Hiding.SightOccluderSize.Y * .5, 0),
			Configuration.Hiding.SightOccluderSize, Color3.new(), Enum.Material.SmoothPlastic, 1)
		decorative(sightOccluder)
		sightOccluder.CanCollide = false
		sightOccluder.CanTouch = false
		sightOccluder.CanQuery = true
		sightOccluder:SetAttribute("Level6_HideSightOccluder", true)
		sightOccluder:SetAttribute("Level6_PermanentFurniture", true)
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
		local chair = cloneDecorMesh("PlasticPartyChairTemplate", parent, "Level 6 Vetted Plastic Party Chair",
			chairCF, Vector3.new(2.55, 4.3, 2.58), chairColor)
		if chair then
			chair:SetAttribute("Level6_PermanentFurniture", true)
			chair:SetAttribute("Level6_ChairTableTarget", tableTarget)
			chair:SetAttribute("Level6_ChairFacingDot", chair.CFrame.LookVector:Dot((tableTarget - chairPosition).Unit))
		end
		if not chair then
			local seat = part(parent, "Level 6 Party Chair", chairCF,
				Vector3.new(2.4, 4.2, 2.5), chairColor, Enum.Material.SmoothPlastic)
			decorative(seat)
			seat:SetAttribute("Level6_PermanentFurniture", true)
			seat:SetAttribute("Level6_ChairTableTarget", tableTarget)
			seat:SetAttribute("Level6_ChairFacingDot", seat.CFrame.LookVector:Dot((tableTarget - chairPosition).Unit))
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
		local balloon = part(parent, "Level 6 Oval Party Balloon", CFrame.new(p),
			Vector3.new(1.72, 2.36, 1.72), color, Enum.Material.SmoothPlastic, .025)
		balloon.Shape = Enum.PartType.Ball
		balloon.Reflectance = .06
		decorative(balloon)

		local knot = part(parent, "Level 6 Balloon Knot", CFrame.new(p - Vector3.new(0, 1.27, 0))
			* CFrame.Angles(0, 0, math.rad(45)), Vector3.new(.22, .30, .22),
			color:Lerp(Color3.new(0, 0, 0), .12), Enum.Material.SmoothPlastic)
		knot.Shape = Enum.PartType.Ball
		decorative(knot)
		segmentBetween(parent, "Level 6 Balloon String", p - Vector3.new(0, 1.4, 0),
			anchor, .025, Color3.fromRGB(118, 115, 106), .18)
	end
end

local function makeBunting(parent: Instance, room: {[string]: any})
	local p = worldPosition(room)
	local colors = {C.Burgundy, C.MutedBlue, C.FadedGreen, Color3.fromRGB(184, 139, 41), C.DustyPeach}
	local cordY = roomHeight(room) - 1.18
	local z = room.D * .12
	local cord = part(parent, "Level 6 Bunting Cord", CFrame.new(p + Vector3.new(0, cordY, z)),
		Vector3.new(room.W - 7, .035, .035), Color3.fromRGB(75, 68, 59), Enum.Material.SmoothPlastic)
	decorative(cord)
	local halfSpan = room.W * .5 - 4.5
	local flagIndex = 0
	for x = -halfSpan, halfSpan, 6.2 do
		flagIndex += 1
		local normalized = math.abs(x) / math.max(halfSpan, 1)
		local sag = (1 - normalized) * .32
		local flag = Instance.new("WedgePart")
		flag.Name = "Level 6 Triangular Bunting Flag"
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
	paper:SetAttribute("Level6_KidsWallArt", true)
	paper:SetAttribute("Level6_TransparentWallArt", true)
	paper:SetAttribute("Level6_AtlasCell", atlasCell)

	local surface = Instance.new("SurfaceGui")
	surface.Name = "Level 6 Kids Wall Art Surface"
	surface.Face = Enum.NormalId.Front
	surface.AlwaysOnTop = false
	-- Let the room light and wall color show through the crayon pigments.
	surface.LightInfluence = .88
	surface.SizingMode = Enum.SurfaceGuiSizingMode.PixelsPerStud
	surface.PixelsPerStud = 80
	surface.ZOffset = 1
	surface.Parent = paper

	local image = Instance.new("ImageLabel")
	image.Name = "Level 6 Kids Wall Art Image"
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
		paper:SetAttribute("Level6_DrawingMood", cell < 8 and "Wholesome" or "Disturbing")
		paper:SetAttribute("Level6_DrawingLibraryIndex", cell + 1)
	elseif textureId == TEXTURES.KidsDrawingsWholesome25 then
		paper:SetAttribute("Level6_DrawingMood", "Wholesome")
		paper:SetAttribute("Level6_DrawingLibraryIndex", 17 + cell)
	elseif textureId == TEXTURES.KidsDrawingsDisturbing25 then
		paper:SetAttribute("Level6_DrawingMood", "Disturbing")
		paper:SetAttribute("Level6_DrawingLibraryIndex", 42 + cell)
	end
	image.ScaleType = Enum.ScaleType.Fit
	image.Parent = surface

	for tapeIndex, side in ipairs({-1, 1}) do
		local tape = part(parent, "Level 6 Kids Drawing Tape",
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
			isNote and "Level 6 Kids Notes" or "Level 6 Child Drawing",
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
			isNote and "Level 6 Corridor Kids Notes" or "Level 6 Corridor Child Drawing",
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
		local balloon = part(parent, "Level 6 Loose Party Balloon",
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
	model.Name = string.format("Level 6 Room PA Speaker %02d", index)
	model:SetAttribute("Level6_RoomSpeaker", true)
	model:SetAttribute("Level6_RoomId", room.Id)
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
	sound.Name = "Level 6 Room Song Speaker"
	sound.SoundId = Configuration.Audio.RoomListeningSong
	sound.Volume = Configuration.MusicSequence.SpeakerVolume or .30
	sound.Looped = false
	sound.RollOffMode = Enum.RollOffMode.InverseTapered
	sound.RollOffMinDistance = Configuration.MusicSequence.SpeakerMinDistance or 18
	sound.RollOffMaxDistance = Configuration.MusicSequence.SpeakerMaxDistance or 180
	sound.EmitterSize = 3
	sound.Parent = emitter
	local equalizer = Instance.new("EqualizerSoundEffect")
	equalizer.Name = "Level 6 Distance Muffle"
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
	model.Name = string.format("Level 6 Exit Corridor PA Speaker %02d", index)
	model:SetAttribute("Level6_RoomSpeaker", true)
	model:SetAttribute("Level6_ExitCorridorPA", true)
	model:SetAttribute("Level6_RoomId", "ExitCorridor")
	model:SetAttribute("Level6_ExitCorridorPAIndex", index)
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
	sound.Name = "Level 6 Room Song Speaker"
	sound.SoundId = Configuration.Audio.RoomListeningSong
	sound.Volume = Configuration.MusicSequence.SpeakerVolume or .30
	sound.Looped = false
	sound.PlaybackSpeed = 1
	sound.RollOffMode = Enum.RollOffMode.InverseTapered
	sound.RollOffMinDistance = Configuration.MusicSequence.SpeakerMinDistance or 18
	sound.RollOffMaxDistance = Configuration.MusicSequence.SpeakerMaxDistance or 180
	sound.EmitterSize = 3
	sound:SetAttribute("Level6_ExitCorridorPA", true)
	sound:SetAttribute("Level6_ExitCorridorPAIndex", index)
	sound.Parent = emitter

	local equalizer = Instance.new("EqualizerSoundEffect")
	equalizer.Name = "Level 6 Distance Muffle"
	equalizer.LowGain = 0
	equalizer.MidGain = 0
	equalizer.HighGain = 0
	equalizer.Parent = sound
end

-- Generated rooms are smaller than several original decor archetypes. Keep
-- every table/chair group, size and rotation, while reserving a continuous
-- perimeter for the Manager's centre around the FULL inflated exclusions.
local function fitRoomTableLayouts(room: {[string]: any}, layouts: {{number}})
	local manager = Configuration.MallManager
	local physicalWallInset = Configuration.WallThickness * .5 + manager.SweepRadius
	local centreLane = 1
	local padding = manager.AgentRadius + manager.FurniturePathPadding
	local navHalfX, navHalfZ = TABLE_GROUP_FOOTPRINT.X * .5 + padding,
		TABLE_GROUP_FOOTPRINT.Y * .5 + padding
	local placed = {}
	for _, layout in ipairs(layouts) do
		local c, s = math.abs(math.cos(layout[3])), math.abs(math.sin(layout[3]))
		local maxX = room.W * .5 - physicalWallInset - centreLane - (c * navHalfX + s * navHalfZ)
		local maxZ = room.D * .5 - physicalWallInset - centreLane - (s * navHalfX + c * navHalfZ)
		assert(maxX >= 0 and maxZ >= 0,
			"Party room is too small for its furniture and Manager perimeter")
		table.insert(placed, {
			Layout = layout, MaxX = maxX, MaxZ = maxZ,
			X = math.clamp(layout[1] * room.W, -maxX, maxX),
			Z = math.clamp(layout[2] * room.D, -maxZ, maxZ),
			HalfX = (c * TABLE_GROUP_VISUAL_FOOTPRINT.X + s * TABLE_GROUP_VISUAL_FOOTPRINT.Y) * .5,
			HalfZ = (s * TABLE_GROUP_VISUAL_FOOTPRINT.X + c * TABLE_GROUP_VISUAL_FOOTPRINT.Y) * .5,
		})
	end
	local function groupsOverlap()
		for index, a in ipairs(placed) do
			for other = index + 1, #placed do
				local b = placed[other]
				if math.abs(a.X - b.X) < a.HalfX + b.HalfX + .2
					and math.abs(a.Z - b.Z) < a.HalfZ + b.HalfZ + .2 then return true end
			end
		end
		return false
	end
	-- Only when minimum clamping crowds physical furniture: use opposite
	-- corners for a pair, or a triangle for three groups. Keep the authored yaw.
	if groupsOverlap() then
		for index, group in ipairs(placed) do
			group.X = if #placed == 3 and index == 2 then 0
				else (if index == 1 then -group.MaxX else group.MaxX)
			group.Z = if index == 2 then group.MaxZ else -group.MaxZ
		end
	end
	assert(not groupsOverlap(), "Party room cannot separate its table/chair groups")
	for _, group in ipairs(placed) do
		group.Layout[1], group.Layout[2] = group.X / room.W, group.Z / room.D
	end
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

	fitRoomTableLayouts(room, layouts)
	local moduleSocketCreated = false
	for tableIndex, layout in ipairs(layouts) do
		local tableCF = CFrame.new(p + Vector3.new(layout[1] * room.W, 0, layout[2] * room.D))
			* CFrame.Angles(0, layout[3], 0)
		local hideCount = tonumber(room.HideSpotCount)
		local allowHide = if hideCount ~= nil then tableIndex <= hideCount else true
		makeTable(parent, tableCF, true, layout[4], index + tableIndex, allowHide)
		if room.Module and not moduleSocketCreated then
			local socket = part(parent, "Level 6 CD Table Socket", tableCF * CFrame.new(0, 3.62, 0),
				Vector3.new(2.8, .08, 2.8), Color3.new(), Enum.Material.SmoothPlastic, 1)
			decorative(socket)
			socket:SetAttribute("Level6_CDTableSocket", true)
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
			and object:GetAttribute("Level6_TableCollision") ~= true
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
	-- Keep the beam's ceiling attachment while allowing the full authored
	-- Manager height beneath it. Only the lowest rooms need a thinner beam.
	local beamHeight = math.min(1.5, h - Configuration.MallManager.AgentHeight - .1)
	assert(beamHeight > 0, "Party room is too low for its ceiling beams and Manager")
	local color = wallColor(room)
	for _, x in ipairs({-room.W * .34, room.W * .34}) do
		for _, z in ipairs({-room.D * .32, room.D * .32}) do
			local column = part(parent, "Level 6 Structural Column", CFrame.new(p + Vector3.new(x, h * .5, z)),
				Vector3.new(2.1, h, 2.1), color, Enum.Material.Plaster)
			column.CanCollide = true
		end
	end
	for _, z in ipairs({-room.D * .32, room.D * .32}) do
		local beam = part(parent, "Level 6 Ceiling Beam", CFrame.new(p + Vector3.new(0, h - beamHeight * .5, z)),
			Vector3.new(room.W * .68, beamHeight, 1.1), color:Lerp(Color3.new(0, 0, 0), .08), Enum.Material.Plaster)
		beam.CanCollide = true
	end
end

local function makeHiddenExitDiscPlayer(parent: Instance, frameCF: CFrame): {[string]: any}
	local model = Instance.new("Model")
	model.Name = "Level 6 Signal Hall Disc Player"
	model:SetAttribute("Level6_DiscPlayer", true)
	model:SetAttribute("Level6_DiscPlayerVisualRevision", 2)
	model:SetAttribute("Level6_DiscGoal", Configuration.ModuleGoal)
	model:SetAttribute("Level6_DiscInserted", 0)
	model:SetAttribute("Level6_DiscPlayerTextureSlot", "DiscPlayerPanelTexture")
	model:SetAttribute("Level6_DiscPlayerTexture", TEXTURES.DiscPlayerPanel)
	model:SetAttribute("Level6_CRTScreenTexture", TEXTURES.CRTScreen)
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
	baseShelf:SetAttribute("Level6_DiscPlayerStructure", true)

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
			wheel:SetAttribute("Level6_AVCartCaster", true)
		end
	end

	local cabinet = part(model, "AV Cart Locked Cabinet",
		consoleCF * CFrame.new(0, 1.95, 0), Vector3.new(5.12, 2.45, 2.50),
		charcoal, Enum.Material.Metal)
	cabinet.Reflectance = .04
	cabinet:SetAttribute("Level6_DiscPlayerStructure", true)
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
	middleShelf:SetAttribute("Level6_DiscPlayerStructure", true)
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
	vcr:SetAttribute("Level6_VCRDeck", true)
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
	controlPanel:SetAttribute("Level6_DiscPlayerControlPanel", true)

	local topShelf = part(model, "AV Cart Television Shelf",
		consoleCF * CFrame.new(0, 5.48, 0), Vector3.new(5.60, .28, 3.02),
		edge, Enum.Material.Metal)
	topShelf:SetAttribute("Level6_DiscPlayerStructure", true)

	local crtBody = part(model, "ZYNTRA CRT Television",
		consoleCF * CFrame.new(0, 7.25, -.08), Vector3.new(5.15, 3.26, 2.65),
		charcoal, Enum.Material.SmoothPlastic)
	crtBody.Reflectance = .04
	crtBody:SetAttribute("Level6_CRTTelevision", true)
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
	screenGlass:SetAttribute("Level6_CRTScreen", true)
	screenGlass:SetAttribute("Level6_CRTScreenTexture", TEXTURES.CRTScreen)

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
		receiver:SetAttribute("Level6_DiscPlayerSlot", true)
		receiver:SetAttribute("Level6_DiscSlotIndex", slotIndex)
		receiver:SetAttribute("Level6_DiscSlotFilled", false)

		local discCF = consoleCF * CFrame.new(x, 4.28, 1.27) * CFrame.Angles(0, math.pi * .5, 0)
		local insertedDisc = part(model, string.format("Inserted CD Slot Visual %02d", slotIndex),
			discCF, Vector3.new(.10, .56, .56),
			Color3.fromRGB(176, 201, 214), Enum.Material.Metal, 1)
		insertedDisc.Shape = Enum.PartType.Cylinder
		insertedDisc.Reflectance = .32
		decorative(insertedDisc)
		insertedDisc:SetAttribute("Level6_DiscPlayerInsertedVisual", true)
		insertedDisc:SetAttribute("Level6_DiscSlotIndex", slotIndex)

		local insertedHub = part(model, string.format("Inserted CD Slot Hub %02d", slotIndex),
			discCF, Vector3.new(.12, .15, .15),
			Color3.fromRGB(24, 27, 28), Enum.Material.SmoothPlastic, 1)
		insertedHub.Shape = Enum.PartType.Cylinder
		decorative(insertedHub)
		insertedHub:SetAttribute("Level6_DiscPlayerInsertedVisual", true)
		insertedHub:SetAttribute("Level6_DiscSlotIndex", slotIndex)

		local indicator = part(model, string.format("Disc Slot Indicator %02d", slotIndex),
			consoleCF * CFrame.new(x, 3.86, 1.24), Vector3.new(.22, .22, .12),
			offBlue, Enum.Material.SmoothPlastic)
		indicator.Shape = Enum.PartType.Ball
		decorative(indicator)
		indicator:SetAttribute("Level6_DiscSlotIndicator", true)
		indicator:SetAttribute("Level6_DiscSlotIndex", slotIndex)
		indicator:SetAttribute("Level6_DiscSlotFilled", false)

		local indicatorLight = Instance.new("PointLight")
		indicatorLight.Name = string.format("Disc Slot Status Light %02d", slotIndex)
		indicatorLight.Color = relayBlue
		indicatorLight.Brightness = .78
		indicatorLight.Range = 4.5
		indicatorLight.Shadows = false
		indicatorLight.Enabled = false
		indicatorLight:SetAttribute("Level6_DiscSlotIndicatorLight", true)
		indicatorLight:SetAttribute("Level6_DiscSlotIndex", slotIndex)
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
	prompt:SetAttribute("Level6_DiscInsertPrompt", true)
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
	model.Name = "Level 6 Hidden Exit Portal"
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
	wall:SetAttribute("Level6_HiddenExitWall", true)
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
			beam:SetAttribute("Level6_HiddenExitFrame", true)
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
	model:SetAttribute("Level6_ExitUnlocked", false)
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
	-- The story-only Level 2 flume mouth opens behind the Level 6 spawn.
	-- Level 6 arrival has a closed west wall and a dev return prompt.
	return map
end

local function makeRoom(parent: Instance, room: {[string]: any}, openings: {[string]: boolean}, index: number)
	local model = Instance.new("Model")
	model.Name = string.format("%02d %s", index, room.Name)
	model:SetAttribute("Level6_RoomId", room.Id)
	model:SetAttribute("Level6_RoomKind", room.Kind)
	model:SetAttribute("Level6_District", room.SectionIndex or 0)
	model:SetAttribute("Level6_ThemeId", room.ThemeId or "Legacy")
	model:SetAttribute("Level6_DecorArchetype", room.Decor or "Default")
	model:SetAttribute("Level6_CeilingHeight", roomHeight(room))
	model.Parent = parent
	local p = worldPosition(room)
	local color, material, textureId, studs = floorStyle(room.Kind, room.Id, room.ThemeId)
	local floorPart = part(model, "Level 6 Room Floor", CFrame.new(p - Vector3.new(0, .5, 0)),
		Vector3.new(room.W, Configuration.FloorThickness, room.D), color, material)
	if textureId then texture(floorPart, textureId, Enum.NormalId.Top, studs, studs) end
	part(model, "Level 6 Room Ceiling", CFrame.new(p + Vector3.new(0, roomHeight(room), 0)),
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
	model.Name = string.format("Level 6 Corridor %02d %s-%s", index, a.Id, b.Id)
	model:SetAttribute("Level6_TunnelWidth", tunnelWidth)
	model:SetAttribute("Level6_TunnelHeight", tunnelHeight)
	model:SetAttribute("Level6_District", link.SectionIndex or 0)
	model:SetAttribute("Level6_ThemeId", link.ThemeId or a.ThemeId or "Legacy")
	model.Parent = parent

	-- Butt the tunnel kit cleanly against each room opening. The former full
	-- wall-thickness overlap put coplanar lintels/pillars in the same space and
	-- produced visible z-fighting. Floors/ceilings get a microscopic seal while
	-- side walls stop just short of the room shell.
	local corridorTheme = link.ThemeId or a.ThemeId
	local floorColor, floorMaterial, floorTexture, studs = floorStyle("PartyHall", nil, corridorTheme)
	local inserted = link.BlenderRoom
	local segments = {}
	local function addSegment(firstDistance, lastDistance, trimAtA, trimAtB)
		local wallTrim = Configuration.WallThickness * .5 + .04
		local wallFirst = firstDistance + (if trimAtA then wallTrim else .04)
		local wallLast = lastDistance - (if trimAtB then wallTrim else .04)
		assert(wallLast > wallFirst and lastDistance > firstDistance,
			"Level 6 corridor stub is too short for the authored room")
		local segment = {
			StartDistance = firstDistance, EndDistance = lastDistance,
			Center = startPoint + forward * ((firstDistance + lastDistance) * .5),
			Length = lastDistance - firstDistance,
			WallCenter = startPoint + forward * ((wallFirst + wallLast) * .5),
			WallLength = wallLast - wallFirst,
		}
		table.insert(segments, segment)
	end
	if inserted then
		assert(inserted.StartDistance >= 6
			and inserted.StartDistance + inserted.Length <= length - 6,
			"Level 6 authored room must preserve both corridor mouths")
		addSegment(0, inserted.StartDistance, true, false)
		addSegment(inserted.StartDistance + inserted.Length, length, false, true)
	else
		addSegment(0, length, true, true)
	end
	-- Each stub stops at the authored room end face. Splitting the actual floor,
	-- ceiling, and wall colliders keeps its two portals and taller roof clear.
	local floorParts = {}
	for segmentIndex, segment in ipairs(segments) do
		local first = segment.StartDistance + (if inserted and segmentIndex == 2 then .02 else -.02)
		local last = segment.EndDistance + (if inserted and segmentIndex == 1 then -.02 else .02)
		local floorCenter = startPoint + forward * ((first + last) * .5)
		local floorLength = last - first
		local floorSize = horizontal and Vector3.new(floorLength, 1, tunnelWidth)
			or Vector3.new(tunnelWidth, 1, floorLength)
		local floorPart = part(model, "Level 6 Corridor Floor",
			CFrame.new(floorCenter - Vector3.new(0, .5, 0)), floorSize, floorColor, floorMaterial)
		if floorTexture then texture(floorPart, floorTexture, Enum.NormalId.Top, studs, studs) end
		table.insert(floorParts, floorPart)
		local ceilingSize = horizontal and Vector3.new(segment.WallLength, 1, tunnelWidth)
			or Vector3.new(tunnelWidth, 1, segment.WallLength)
		part(model, "Level 6 Corridor Ceiling",
			CFrame.new(segment.WallCenter + Vector3.new(0, tunnelHeight + .5, 0)),
			ceilingSize, C.AgedWhite, Enum.Material.Plaster)
	end

	-- Every physical corridor mouth owns an exact, zero-geometry audio marker.
	-- Clients select their nearest markers during the blackout scream, preserving
	-- spatial direction without decoding fifty simultaneous copies of one asset.
	local screamOpenings = {}
	for openingIndex, entry in ipairs({{Side="A", Point=startPoint}, {Side="B", Point=endPoint}}) do
		local floorPart = floorParts[if openingIndex == 1 then 1 else #floorParts]
		local opening = Instance.new("Attachment")
		opening.Name = "Level 6 Corridor Opening " .. entry.Side
		opening.CFrame = floorPart.CFrame:ToObjectSpace(CFrame.new(entry.Point + Vector3.new(0, 4.2, 0)))
		opening:SetAttribute("Level6_CorridorOpeningScreamEmitter", true)
		opening:SetAttribute("Level6_CorridorIndex", index)
		opening:SetAttribute("Level6_CorridorOpeningSide", entry.Side)
		opening:SetAttribute("Level6_CorridorOpeningKey", string.format("%02d%s", index, entry.Side))
		opening:SetAttribute("Level6_CorridorDoorType", link.Door)
		opening:SetAttribute("Level6_CorridorOpeningOrder", openingIndex)
		opening.Parent = floorPart
		table.insert(screamOpenings, opening)
	end

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
		for _, segment in ipairs(segments) do
			for _, z in ipairs({-wallCenterOffset, wallCenterOffset}) do
				local wall = part(model, "Level 6 Corridor Wall",
					CFrame.new(segment.WallCenter + Vector3.new(0, tunnelHeight * .5, z)),
					Vector3.new(segment.WallLength, tunnelHeight, Configuration.WallThickness),
					wallColorValue, wallMaterial)
				texture(wall, wallTexture, z < 0 and Enum.NormalId.Front or Enum.NormalId.Back,
					wallStuds, wallStuds, wallTransparency)
			end
		end
	else
		for _, segment in ipairs(segments) do
			for _, x in ipairs({-wallCenterOffset, wallCenterOffset}) do
				local wall = part(model, "Level 6 Corridor Wall",
					CFrame.new(segment.WallCenter + Vector3.new(x, tunnelHeight * .5, 0)),
					Vector3.new(Configuration.WallThickness, tunnelHeight, segment.WallLength),
					wallColorValue, wallMaterial)
				texture(wall, wallTexture, x < 0 and Enum.NormalId.Right or Enum.NormalId.Left,
					wallStuds, wallStuds, wallTransparency)
			end
		end
	end
	if not inserted then makeCorridorWallDecor(model, startPoint, endPoint, horizontal, index) end
	local hiddenExit = link.Door == "HiddenExit"
	local speakerCount = if hiddenExit then Configuration.Layout.ExitCorridorSpeakerCount else 0
	if hiddenExit then
		model:SetAttribute("Level6_ExitCorridor", true)
		model:SetAttribute("Level6_ExitCorridorLength", length)
		model:SetAttribute("Level6_ExitCorridorSpeakerCount", speakerCount)
		-- Continuous waist-height service rails visually pull the eye toward the
		-- distant freight door and make the doubled final passage feel intentionally authored.
		for _, side in ipairs({-1, 1}) do
			local railCF = if horizontal
				then CFrame.new(center + Vector3.new(0, 2.25, side * (tunnelWidth * .5 - .08)))
				else CFrame.new(center + Vector3.new(side * (tunnelWidth * .5 - .08), 2.25, 0))
			local railSize = if horizontal then Vector3.new(wallLength, .14, .10)
				else Vector3.new(.10, .14, wallLength)
			local rail = part(model, "Level 6 Exit Corridor Service Rail", railCF, railSize,
				Color3.fromRGB(43, 49, 48), Enum.Material.Metal)
			decorative(rail)
		end
		for speakerIndex = 1, speakerCount do
			local speakerPoint = startPoint:Lerp(endPoint, speakerIndex / (speakerCount + 1))
			local side = if speakerIndex % 2 == 0 then 1 else -1
			makeExitCorridorSpeaker(model, speakerPoint, horizontal, side, speakerIndex)
		end
	end
	local fixtureCount = if inserted then 0
		elseif hiddenExit then Configuration.Layout.ExitCorridorFixtureCount else 1
	for fixtureIndex = 1, fixtureCount do
		local position = startPoint:Lerp(endPoint, fixtureIndex / (fixtureCount + 1))
		makeFixture(model, position + Vector3.new(0, tunnelHeight - .85, 0),
			"Staff", 400 + index * 4 + fixtureIndex, (index + fixtureIndex) % 9 == 0)
	end
	return {Model=model, Center=center, Forward=forward, Length=length, DoorType=link.Door,
		A=a, B=b, DoorPosition=center, StartPoint=startPoint, EndPoint=endPoint,
		Segments=segments, BlenderRoom=inserted,
		ScreamOpenings=screamOpenings,
		WallColor=wallColorValue, Wallpaper=corridorWallpaper, Width=tunnelWidth, Height=tunnelHeight}
end

local function makeModule(parent: Instance, room: {[string]: any}, index: number, roomModel: Instance): {[string]: any}
	local model = Instance.new("Model")
	model.Name = string.format("Birthday Music CD %02d", index)
	model:SetAttribute("Level6_ModuleIndex", index)
	model:SetAttribute("Level6_CDIndex", index)
	model:SetAttribute("Level6_ModuleRoom", room.Id)
	model:SetAttribute("Level6_Collected", false)
	model.Parent = parent
	local socket = roomModel:FindFirstChild("Level 6 CD Table Socket", true)
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
	case:SetAttribute("Level6_CDPersistentDisplay", true)
	local cover = part(model, "CD Cover Insert", baseCF * CFrame.new(0, .10, 0), Vector3.new(2.5, .035, 2.38),
		Color3.fromRGB(231, 224, 195), Enum.Material.SmoothPlastic)
	decorative(cover)
	cover:SetAttribute("Level6_CDPersistentDisplay", true)
	local surface = Instance.new("SurfaceGui")
	surface.Name = "Level 6 CD Cover Surface"
	surface.Face = Enum.NormalId.Top
	surface.SizingMode = Enum.SurfaceGuiSizingMode.PixelsPerStud
	surface.PixelsPerStud = 120
	surface.LightInfluence = .45
	surface.AlwaysOnTop = false
	surface.Parent = cover
	local art = Instance.new("ImageLabel")
	art.Name = "Level 6 CD Cover Art"
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
	disc:SetAttribute("Level6_CDPickupVisual", true)
	local hub = part(model, "Compact Disc Hub", disc.CFrame, Vector3.new(.105, .40, .40),
		Color3.fromRGB(28, 30, 31), Enum.Material.SmoothPlastic)
	hub.Shape = Enum.PartType.Cylinder
	decorative(hub)
	hub:SetAttribute("Level6_CDPickupVisual", true)
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
	-- Preview-owned compatibility markers; the production lobby and Level 2 flume are untouched.
	local p = worldPosition(room)
	local model = Instance.new("Model")
	model.Name = "Level6CompatibilityElevator"
	model:SetAttribute("Level6_CompatibilityMarker", true)
	model.Parent = parent
	local spawnPosition = p + Vector3.new(-room.W * .5 + 16, .25, 0)
	local spawnCF = CFrame.lookAt(spawnPosition, p + Vector3.new(2, .25, 0))
	local spawn = part(parent, "Level6ElevatorSpawn", spawnCF, Vector3.new(8, .5, 8),
		Color3.new(), Enum.Material.SmoothPlastic, 1)
	spawn.CanCollide = false
	spawn.CanQuery = false
	spawn.CanTouch = false
	spawn:SetAttribute("Level6_CompatibilityMarker", true)
	local mazeStart = part(parent, "Level6MazeStart", spawnCF, Vector3.new(2, .3, 2),
		Color3.new(), Enum.Material.SmoothPlastic, 1)
	mazeStart.CanCollide = false
	mazeStart.CanQuery = false
	mazeStart.CanTouch = false
	mazeStart:SetAttribute("Level6_CompatibilityMarker", true)
	return model, spawn, mazeStart
end

local function makeExitSet(parent: Instance, room: {[string]: any}): (BasePart, BasePart, Vector3, Model)
	local model = Instance.new("Model")
	model.Name = "Level 6 Energon Freight Exit"
	model:SetAttribute("Level6_FinalExit", true)
	model:SetAttribute("Level6_ExitPowered", false)
	model.Parent = parent
	local p = worldPosition(room)

	-- A completely flat, uninterrupted approach replaces the old staircase.
	local approachLength = math.max(22, room.W - 10)
	local approach = part(model, "Level 6 Flat Exit Approach",
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
	leftLeaf:SetAttribute("Level6_FinalExitLeaf", "Left")
	rightLeaf:SetAttribute("Level6_FinalExitLeaf", "Right")
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

	-- Reach the exit by running into the freight doorway. The detector stops
	-- inside its jambs and begins just in front of the solid door face, so the
	-- character's root can enter it without opening or removing authored parts.
	local escapeTrigger = part(model, "EscapeTrigger",
		CFrame.new(doorX - 2.4, p.Y + 5, p.Z), Vector3.new(3, 10, 9.5),
		Color3.new(), Enum.Material.SmoothPlastic, 1)
	escapeTrigger.CanCollide = false
	escapeTrigger.CanTouch = false -- Objective Controller owns touch detection for the live session.
	escapeTrigger.CanQuery = false
	escapeTrigger.CastShadow = false
	escapeTrigger:SetAttribute("Level6_ExitTrigger", true)

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
	return escapeTrigger, safeSpawn, lockCore.Position, model
end

local function makeMallManagerSpawn(parent: Instance, spawnRoomId: string): BasePart
	local spawnRoom = roomById(spawnRoomId)
	local floorPosition = worldPosition(spawnRoom)
	local marker = part(parent, "Mall Manager Spawn",
		CFrame.new(floorPosition + Vector3.new(0, .05, 0)), Vector3.new(2, .1, 2),
		Color3.new(0, 0, 0), Enum.Material.SmoothPlastic, 1)
	decorative(marker)
	marker:SetAttribute("Level6_MallManagerSpawn", true)
	marker:SetAttribute("Level6_SpawnRoomId", spawnRoom.Id)
	marker:SetAttribute("Level6_FloorY", floorPosition.Y)
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
		"Level 6 World Builder requires a validated generated layout")
	activeLayout = layout
	drawingSerial = 0
	local existing = workspace:FindFirstChild(Configuration.WorldName)
	if existing then
		assert(existing:GetAttribute("Level6BuildOwned") == true,
			"Refusing to replace an unowned Level 6 workspace world")
		existing:Destroy()
	end
	local stagedExisting = ServerStorage:FindFirstChild(Configuration.WorldName)
	if stagedExisting then
		assert(stagedExisting:GetAttribute("Level6BuildOwned") == true,
			"Refusing to replace an unowned Level 6 staged world")
		stagedExisting:Destroy()
	end
	local world = Instance.new("Model")
	world.Name = Configuration.WorldName
	world:SetAttribute("Level6BuildOwned", true)
	world:SetAttribute("Level6_Generation", generation)
	world:SetAttribute("Level6_VisualRevision", Configuration.Version)
	world:SetAttribute("Level6_Theme", "Three District Abandoned Mall Backrooms")
	world:SetAttribute("Level6_LayoutHash", layout.LayoutHash or "")
	world:SetAttribute("Level6_ResolvedSeed", layout.ResolvedSeed or 0)
	world:SetAttribute("Level6_GeneratorVersion", layout.Version or Configuration.Layout.GeneratorVersion)
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
			local spawnProgress = Configuration.MallManager.FinalHallSpawnProgress or .97
			local halfwayMarker = part(corridor.Model, "Level 6 Final Hall Halfway",
				CFrame.new(corridor.StartPoint:Lerp(corridor.EndPoint, halfwayProgress) + Vector3.new(0, .05, 0)),
				Vector3.new(2, .1, 2), Color3.new(0, 0, 0), Enum.Material.SmoothPlastic, 1)
			decorative(halfwayMarker)
			halfwayMarker:SetAttribute("Level6_FinalHallHalfway", true)
			halfwayMarker:SetAttribute("Level6_FinalHallProgress", halfwayProgress)
			local spawnMarker = part(corridor.Model, "Level 6 Mall Manager Finale Spawn",
				CFrame.new(corridor.StartPoint:Lerp(corridor.EndPoint, spawnProgress) + Vector3.new(0, .05, 0)),
				Vector3.new(2, .1, 2), Color3.new(0, 0, 0), Enum.Material.SmoothPlastic, 1)
			decorative(spawnMarker)
			spawnMarker:SetAttribute("Level6_MallManagerFinaleSpawn", true)
			spawnMarker:SetAttribute("Level6_FinalHallProgress", spawnProgress)
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
	assert(#modules == Configuration.ModuleGoal, "Level 6 CD goal does not match authored CD rooms")
	local roles = layout.Roles or {}
	local arrivalRoom = roomById(roles.ArrivalRoomId or "Arrival")
	local elevator, elevatorSpawn, mazeStart = makeArrivalElevator(world, arrivalRoom)
	local spawnRoomId = roles.MallManagerSpawnRoomId or roles.SignalRoomId or Configuration.MallManager.SpawnRoomId
	local mallManagerSpawn = makeMallManagerSpawn(world, spawnRoomId)
	local escapeTrigger, safeSpawn, exitPosition, finalExit = makeExitSet(world, roomById(roles.ExitRoomId or "Exit"))
	-- Publish the complete hierarchy once, then start spatial ambience.  This
	-- avoids a room-by-room replication burst during procedural construction.
	world.Parent = workspace
	makeAmbientEmitter(ambienceFolder, "Level 6 HVAC Bed", worldPosition(roomById(roles.AmbientHVACRoomId or spawnRoomId), 8),
		Configuration.Audio.HVAC, .10, 150)
	assert(exitPortal, "Level 6 build requires exactly one hidden exit portal")
	assert(finalHall, "Level 6 build requires exactly one final HiddenExit hall")
	world:SetAttribute("Level6_FinalHallLength", finalHall.Length)
	world:SetAttribute("Level6_FinalHallHalfwayProgress", finalHall.HalfwayProgress)
	world:SetAttribute("Level6_FinalHallSpawnProgress", finalHall.SpawnProgress)
	world:SetAttribute("Level6_RoomCount", #layout.Rooms)
	world:SetAttribute("Level6_CorridorCount", #layout.Links)
	world:SetAttribute("Level6_DistrictCount", #(layout.Districts or {}))
	world:SetAttribute("Level6_BlackoutScreamOpeningCount", #blackoutScreamOpenings)
	world:SetAttribute("Level6_ModuleCount", #modules)
	world:SetAttribute("Level6_MallManagerSpawnRoom", spawnRoomId)
	-- Decorative helper calls intentionally strip interaction. Reassert the
	-- tabletop collider, query-only sight cloth, and collect every hide anchor.
	local hideTables = {}
	for _, object in ipairs(world:GetDescendants()) do
		if object:IsA("BasePart") and object:GetAttribute("Level6_TableCollision") == true then
			object.CanCollide = true
			object.CanTouch = false
			object.CanQuery = true
		elseif object:IsA("BasePart") and object:GetAttribute("Level6_HideSightOccluder") == true then
			object.CanCollide = false
			object.CanTouch = false
			object.CanQuery = true
		elseif object:IsA("BasePart") and object:GetAttribute("Level6_HideTableAnchor") == true then
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
		anchor:SetAttribute("Level6_HideTableIndex", index)
		local prompt = anchor:FindFirstChild("HideUnderTablePrompt")
		if prompt and prompt:IsA("ProximityPrompt") then
			prompt.ObjectText = string.format("FOLDING TABLE %02d", index)
		end
	end
	world:SetAttribute("Level6_HideTableCount", #hideTables)
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
		EscapeTrigger=escapeTrigger,
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
]====]
 local compiled,problem=loadstring(candidate)
 assert(compiled,"Syntax: "..tostring(problem))
 rows[#rows+1]={instance=instance,source=source,candidate=candidate,beforeSha256=sha(source)}
end

do
 local instance=game
 for _,name in ipairs({"StarterPlayer","StarterPlayerScripts","Level 6 Lighting Controller"}) do instance=instance:FindFirstChild(name) assert(instance,"Missing "..name) end
 assert(instance.ClassName=="LocalScript","Class changed")
 local source=instance.Source
 assert(sha(source)=="54f9901db65584de073e2f7beda26ee542f48de8b7fc889acc45080bb7784886","Fresh Source changed: "..instance:GetFullName())
 assert(SES:GetEditorSource(instance)==source,"Source/editor conflict")
 local candidate=[====[--!strict
-- Level 6 Lighting Controller
-- A readable, artificial mall/service-space grade with sparse fluorescent
-- instability. All global Lighting properties are captured and restored.

local Players = game:GetService("Players")
local ReplicatedStorage = game:GetService("ReplicatedStorage")
local RunService = game:GetService("RunService")
local Lighting = game:GetService("Lighting")
local TweenService = game:GetService("TweenService")

local player = Players.LocalPlayer
local random = Random.new()

local LEVEL = 6
local WORLD_NAME = "Level 6 Generated World"
local STATE_FOLDER_NAME = "Level 6 State"
local MAX_FLICKER_FIXTURES = 10

type LightingSnapshot = {
	Brightness: number,
	ClockTime: number,
	ExposureCompensation: number,
	Ambient: Color3,
	OutdoorAmbient: Color3,
	ColorShiftTop: Color3,
	ColorShiftBottom: Color3,
	FogColor: Color3,
	FogStart: number,
	FogEnd: number,
	EnvironmentDiffuseScale: number,
	EnvironmentSpecularScale: number,
	ShadowSoftness: number,
	GlobalShadows: boolean,
}

type FixtureRecord = {
	Part: BasePart,
	Light: SurfaceLight,
	Brightness: number,
	Enabled: boolean,
	NextAt: number,
	RestoreAt: number,
	Pulse: number,
	NextPulseAt: number,
}

type SuppressedEffect = {
	Effect: PostEffect,
	Enabled: boolean,
}

type BlackoutLightRecord = {
	Light: Light,
	Enabled: boolean,
	Brightness: number,
}

type BlackoutPartRecord = {
	Part: BasePart,
	Material: Enum.Material,
	Color: Color3,
}

local grade = Lighting:FindFirstChild("Level6ClientColorGrade")
if not (grade and grade:IsA("ColorCorrectionEffect")) then
	assert(grade == nil, "Refusing to replace an unowned Level 6 color grade")
	grade = Instance.new("ColorCorrectionEffect")
	grade.Name = "Level6ClientColorGrade"
	grade.Parent = Lighting
end
local colorGrade = grade :: ColorCorrectionEffect
colorGrade.Enabled = false

local bloomObject = Lighting:FindFirstChild("Level6ClientBloom")
if not (bloomObject and bloomObject:IsA("BloomEffect")) then
	assert(bloomObject == nil, "Refusing to replace an unowned Level 6 bloom")
	bloomObject = Instance.new("BloomEffect")
	bloomObject.Name = "Level6ClientBloom"
	bloomObject.Parent = Lighting
end
local bloom = bloomObject :: BloomEffect
bloom.Enabled = false

local snapshot: LightingSnapshot? = nil
local active = false
local transitionSerial = 0
local tweens: {Tween} = {}
local lastExitUnlocked: boolean? = nil
local suppressedEffects: {SuppressedEffect} = {}

local fixtures: {FixtureRecord} = {}
local fixtureByPart: {[BasePart]: FixtureRecord} = {}
local boundWorld: Model? = nil
local worldAddedConnection: RBXScriptConnection? = nil
local worldRemovingConnection: RBXScriptConnection? = nil
local blackoutApplied = false
local blackoutLights: {BlackoutLightRecord} = {}
local blackoutParts: {BlackoutPartRecord} = {}
local blackoutPartSeen: {[BasePart]: boolean} = {}
-- The Blender diffuser is a tiny carrier with visible MeshPart children.
-- Its server-side visual listeners cannot observe this script's client-local
-- flicker, fade, or blackout writes.
local kitFixtureSeen: {[BasePart]: boolean} = {}
local kitFixtureConnections: {RBXScriptConnection} = {}
local kitVisualVariants: {[MeshPart]: string} = {}
local ceilingBounceSeen: {[PointLight]: boolean} = {}

-- Ceiling fill follows its original ballast through normal flicker, pre-
-- blackout, recovery and the completion fade. It has no independent pulse or
-- blackout baseline entry, so the authored fixture ordering stays unchanged.
local function tryWatchCeilingBounce(instance: Instance)
	if not instance:IsA("PointLight")
		or instance:GetAttribute("Level6_CeilingBounce") ~= true
		or ceilingBounceSeen[instance] then return end
	local anchor = instance.Parent
	local primary = anchor and anchor.Parent
	if not (primary and primary:IsA("SurfaceLight")
		and primary.Name == "Level 6 Fluorescent Light") then return end
	local normalBrightness = instance:GetAttribute("Level6_PrimaryBrightness")
	if type(normalBrightness) ~= "number" or normalBrightness <= 0 then return end
	ceilingBounceSeen[instance] = true
	local function sync()
		if not instance.Parent or not primary.Parent then return end
		instance.Enabled = primary.Enabled
		instance.Brightness = .16 * math.clamp(primary.Brightness / normalBrightness, 0, 1)
		instance.Color = primary.Color
	end
	for _, property in ipairs({"Enabled", "Brightness", "Color"}) do
		table.insert(kitFixtureConnections, primary:GetPropertyChangedSignal(property):Connect(sync))
	end
	sync()
end

local function syncKitFixtureVisuals(carrier: BasePart)
	for _, child in ipairs(carrier:GetChildren()) do
		if child:IsA("MeshPart") and child:GetAttribute("Level6_KitVisualChunk") == true then
			if kitVisualVariants[child] == nil then
				kitVisualVariants[child] = child.MaterialVariant
			end
			child.Material = carrier.Material
			child.Color = carrier.Color
			child.Transparency = carrier.Transparency
			-- Neon and the unlit SmoothPlastic pass must not retain a PBR
			-- variant that can make a locally darkened lamp appear emissive.
			child.MaterialVariant = if carrier.Material == Enum.Material.Neon
				or carrier.Material == Enum.Material.SmoothPlastic
				then "" else kitVisualVariants[child]
		end
	end
end

local function tryWatchKitFixture(instance: Instance)
	if not instance:IsA("BasePart") or kitFixtureSeen[instance]
		or instance:GetAttribute("Level6_KitAsset") ~= "FluorescentDiffuser" then return end
	if not instance:FindFirstChild("Level 6 Fluorescent Light") then return end
	kitFixtureSeen[instance] = true
	table.insert(kitFixtureConnections,
		instance:GetPropertyChangedSignal("Material"):Connect(function()
			syncKitFixtureVisuals(instance)
		end))
	table.insert(kitFixtureConnections,
		instance:GetPropertyChangedSignal("Color"):Connect(function()
			syncKitFixtureVisuals(instance)
		end))
	table.insert(kitFixtureConnections,
		instance:GetPropertyChangedSignal("Transparency"):Connect(function()
			syncKitFixtureVisuals(instance)
		end))
	syncKitFixtureVisuals(instance)
end

local function clearKitFixtureWatchers()
	for _, connection in ipairs(kitFixtureConnections) do connection:Disconnect() end
	table.clear(kitFixtureConnections)
	table.clear(kitFixtureSeen)
	table.clear(kitVisualVariants)
	table.clear(ceilingBounceSeen)
end
-- enforceBlackout used to walk the WHOLE generated mall on every throttled
-- Heartbeat -- 12.5 times a second for the ~52 s of each blackout that is not
-- the scream, and then continuously for the rest of the round once five CDs
-- unlock the exit. It is a sweep, not a tick: nothing changes between passes
-- unless the world does.
--
-- `blackoutSweptUnlocked` holds the exitUnlocked() value the last full sweep
-- ran for, and `nil` means a sweep is due now. Everything on THIS client that
-- can put a lit fixture back -- a fresh baseline, a late-streamed Light, the
-- end of a flicker pass -- writes nil here, so those cases are corrected on the
-- very next tick rather than eventually.
--
-- The interval is what covers the writers this client cannot see coming.
-- `Level 6 Objective Controller` is a SERVER module and it writes Lights inside
-- the same world (`slot.Light.Enabled = active` as CDs go into the VCR, and
-- restoreModule putting a module's Enabled/Brightness back); those arrive as
-- replicated property changes on instances that already exist, so they fire no
-- DescendantAdded and nothing local marks the sweep due. The old code hid that
-- behind brute force. This is still a poll -- deliberately -- but at 2 passes a
-- second instead of 12.5, which is where the cost was.
local BLACKOUT_SWEEP_SAFETY_INTERVAL = 0.5
local blackoutSweptUnlocked: boolean? = nil
local blackoutSweptAt = 0
local blackoutFlickerPulse = -1
local preBlackoutApplied = false
local preBlackoutFlickerPulse = -1
local recoveryFlickerApplied = false
local recoveryFlickerPulse = -1
local BLACKOUT_SCREAM_DURATION = 8.071836735
-- PHOTOSENSITIVITY. updateBlackoutFlicker computes ONE `lit` for the whole mall
-- and applies it to every fixture at once, so each pulse is a full-screen
-- luminance flip. The hash lights ~4 of every 11 pulses plus every 13th -- up
-- to ~0.45 flashes per pulse -- and the published guidance is no more than
-- three flashes a second over a large area, so the interval floor is
-- 0.45 / 3 = 0.15 s. This was 0.085 (about 4.5 flashes a second, over the
-- threshold every blackout and again every 3.5 minutes for the whole level);
-- 0.17 keeps a margin and still reads as a violent stutter rather than a fade.
--
-- The other two passes keep their authored cadence on purpose:
-- updatePreBlackoutFlicker and updateRecoveryFlicker fold the light INDEX into
-- their hash, so they are desynchronised per-fixture flicker and their
-- aggregate luminance is comparatively smooth. What they do gain is the
-- ReduceFlashing floor below.
local BLACKOUT_FLICKER_INTERVAL = 0.17
local PRE_BLACKOUT_FLICKER_INTERVAL = 0.09
local RECOVERY_FLICKER_INTERVAL = 0.085
-- ReduceFlashing does not gate the strobe slower still, it REPLACES it: no
-- fixture is switched off, no material is swapped, and the mall breathes
-- between this floor and full over REDUCED_FLASH_PERIOD seconds. The darkness
-- and the scream timing are untouched; only the on/off edge is gone.
local REDUCED_FLASH_FLOOR = 0.4
local REDUCED_FLASH_PERIOD = 1.1
local DEFAULT_COMPLETION_DIM_DURATION = 5.5
local completionFadeActive = false
local completionFadeEndsAtServerTime = 0
script:SetAttribute("Level6_BlackoutScreamFlickerActive", false)
script:SetAttribute("Level6_BlackoutScreamFlickerPulse", -1)
script:SetAttribute("Level6_PreBlackoutFlickerActive", false)
script:SetAttribute("Level6_PreBlackoutFlickerPulse", -1)
script:SetAttribute("Level6_RecoveryFlickerActive", false)
script:SetAttribute("Level6_RecoveryFlickerPulse", -1)
script:SetAttribute("Level6_CompletionBlackoutActive", false)
script:SetAttribute("Level6_CompletionDimActive", false)
script:SetAttribute("Level6_CompletionDimProgress", 0)
local applyLevelGrade: (boolean) -> ()

local function cancelTweens()
	for _, tween in ipairs(tweens) do tween:Cancel() end
	table.clear(tweens)
end

local function tween(instance: Instance, duration: number, goals: {[string]: any})
	local object = TweenService:Create(instance, TweenInfo.new(duration, Enum.EasingStyle.Quad, Enum.EasingDirection.Out), goals)
	table.insert(tweens, object)
	object:Play()
end

local function captureLighting(): LightingSnapshot
	return {
		Brightness = Lighting.Brightness,
		ClockTime = Lighting.ClockTime,
		ExposureCompensation = Lighting.ExposureCompensation,
		Ambient = Lighting.Ambient,
		OutdoorAmbient = Lighting.OutdoorAmbient,
		ColorShiftTop = Lighting.ColorShift_Top,
		ColorShiftBottom = Lighting.ColorShift_Bottom,
		FogColor = Lighting.FogColor,
		FogStart = Lighting.FogStart,
		FogEnd = Lighting.FogEnd,
		EnvironmentDiffuseScale = Lighting.EnvironmentDiffuseScale,
		EnvironmentSpecularScale = Lighting.EnvironmentSpecularScale,
		ShadowSoftness = Lighting.ShadowSoftness,
		GlobalShadows = Lighting.GlobalShadows,
	}
end

local function suppressInheritedEffects()
	table.clear(suppressedEffects)
	for _, child in ipairs(Lighting:GetChildren()) do
		if child ~= bloom and (child:IsA("BloomEffect") or child:IsA("SunRaysEffect")) then
			table.insert(suppressedEffects, {
				Effect = child,
				Enabled = child.Enabled,
			})
			child.Enabled = false
		end
	end
end

local function restoreInheritedEffects()
	for _, record in ipairs(suppressedEffects) do
		if record.Effect.Parent then record.Effect.Enabled = record.Enabled end
	end
	table.clear(suppressedEffects)
end

local function stateFolder(): Folder?
	local object = ReplicatedStorage:FindFirstChild(STATE_FOLDER_NAME)
	return if object and object:IsA("Folder") then object else nil
end

local function exitUnlocked(): boolean
	local state = stateFolder()
	local value = state and state:GetAttribute("Level6_ExitUnlocked")
	if value == nil then value = workspace:GetAttribute("Level6ExitUnlocked") end
	return value == true
end

-- The player's own accessibility switch, read LIVE rather than cached: the
-- Zyntra terminal writes it mid-round and the very next pulse has to honour it.
local function reduceFlashing(): boolean
	return player:GetAttribute("ReduceFlashing") == true
end

-- LEVEL6_COMPLETION_BLACKOUT_GUIDE_20260821
local function blackoutRequested(): boolean
	local state = stateFolder()
	local value = state and state:GetAttribute("Level6_BlackoutActive")
	if value == nil then value = workspace:GetAttribute("Level6BlackoutActive") end
	-- Five CDs permanently hand lighting ownership to the exit breadcrumb mode;
	-- the normal music timeline may enter DONE, but it cannot relight the mall.
	return value == true or exitUnlocked()
end

local function preBlackoutRequested(): boolean
	local state = stateFolder()
	local value = state and state:GetAttribute("Level6_PreBlackoutActive")
	if value == nil then value = workspace:GetAttribute("Level6PreBlackoutActive") end
	return value == true or (state and state:GetAttribute("Level6_RoomSongPhase") == "PRE_BLACKOUT")
end

local function recoveryFlickerRequested(): boolean
	local state = stateFolder()
	local value = state and state:GetAttribute("Level6_RecoveryFlickerActive")
	if value == nil then value = workspace:GetAttribute("Level6RecoveryFlickerActive") end
	return value == true or (state and state:GetAttribute("Level6_RoomSongPhase") == "RECOVERY_FLICKER")
end

local function captureAuthoredRoomGlow(instance: Instance)
	if not instance:IsA("MeshPart")
		or instance:GetAttribute("Level6_KitVisualChunk") ~= true
		or instance.Name:sub(-6) ~= "__glow" then return end
	local carrier = instance.Parent
	if not (carrier and carrier:IsA("BasePart")
		and carrier:GetAttribute("Level6_BlenderGatewayRoom") == true)
		or blackoutPartSeen[instance] then return end
	blackoutPartSeen[instance] = true
	table.insert(blackoutParts, {
		Part = instance,
		Material = instance.Material,
		Color = instance.Color,
	})
end

local function captureWorldLightBaseline()
	table.clear(blackoutLights)
	table.clear(blackoutParts)
	table.clear(blackoutPartSeen)
	-- A fresh baseline is a fresh world, so the next enforceBlackout sweeps it.
	blackoutSweptUnlocked = nil
	local world = boundWorld
	if not world then return end
	for _, descendant in ipairs(world:GetDescendants()) do
		captureAuthoredRoomGlow(descendant)
		if descendant:IsA("Light") and descendant:GetAttribute("Level6_CeilingBounce") ~= true then
			table.insert(blackoutLights, {
				Light = descendant,
				Enabled = descendant.Enabled,
				Brightness = descendant.Brightness,
			})
			local parent = descendant.Parent
			if parent and parent:IsA("BasePart") and not blackoutPartSeen[parent] then
				blackoutPartSeen[parent] = true
				table.insert(blackoutParts, {
					Part = parent,
					Material = parent.Material,
					Color = parent.Color,
				})
			end
		end
	end
end

local function restoreBlackoutWorld()
	for _, record in ipairs(blackoutLights) do
		if record.Light.Parent then
			record.Light.Enabled = record.Enabled
			record.Light.Brightness = record.Brightness
		end
	end
	for _, record in ipairs(blackoutParts) do
		if record.Part.Parent then
			record.Part.Material = record.Material
			record.Part.Color = record.Color
		end
	end
	table.clear(blackoutLights)
	table.clear(blackoutParts)
	table.clear(blackoutPartSeen)
	blackoutSweptUnlocked = nil
	blackoutFlickerPulse = -1
	preBlackoutFlickerPulse = -1
	recoveryFlickerPulse = -1
	completionFadeActive = false
	completionFadeEndsAtServerTime = 0
	blackoutApplied = false
	preBlackoutApplied = false
	recoveryFlickerApplied = false
	script:SetAttribute("Level6_BlackoutScreamFlickerActive", false)
	script:SetAttribute("Level6_BlackoutScreamFlickerPulse", -1)
	script:SetAttribute("Level6_PreBlackoutFlickerActive", false)
	script:SetAttribute("Level6_PreBlackoutFlickerPulse", -1)
	script:SetAttribute("Level6_RecoveryFlickerActive", false)
	script:SetAttribute("Level6_RecoveryFlickerPulse", -1)
	script:SetAttribute("Level6_CompletionDimActive", false)
	script:SetAttribute("Level6_CompletionDimProgress", 0)
	script:SetAttribute("Level6_CompletionBlackoutActive", false)
end

local function enforceBlackout()
	-- ON CHANGE, or on the safety interval -- never once per throttled frame.
	-- Both non-flicker paths in updateBlackoutFlicker land here every 0.08 s and
	-- everything below is idempotent, so a pass whose inputs have not moved is
	-- pure waste. exitUnlocked() is the guard as well as an input: it is the only
	-- thing the published attributes at the foot of this function vary on, so a
	-- mid-blackout unlock re-sweeps without any extra signal being wired up.
	local unlocked = exitUnlocked()
	-- SERVER TIME, like every other bound in this file's blackout logic. Roblox's
	-- os.clock() is CPU time, not wall time, so a 0.5 s deadline written against
	-- it stretches on a loaded client -- and this deadline is the worst-case
	-- window in which a fixture the SERVER relit (the Objective Controller's VCR
	-- slot indicators) stays visible through the blackout. os.clock is fine at
	-- :763/:987 below, where the drift is a feel value; it is not fine here.
	local now = workspace:GetServerTimeNow()
	if blackoutSweptUnlocked == unlocked
		and now - blackoutSweptAt < BLACKOUT_SWEEP_SAFETY_INTERVAL then
		return
	end
	blackoutSweptUnlocked = unlocked
	blackoutSweptAt = now
	-- Streaming can deliver fixtures after the initial baseline snapshot. Sweep
	-- the authoritative live world so completion can never leave a late light on.
	if boundWorld then
		for _, descendant in ipairs(boundWorld:GetDescendants()) do
			if descendant:IsA("Light") then
				descendant.Enabled = false
				descendant.Brightness = 0
				local parent = descendant.Parent
				if parent and parent:IsA("BasePart") then
					parent.Material = Enum.Material.SmoothPlastic
					parent.Color = Color3.fromRGB(13, 14, 15)
				end
			end
		end
	end
	for _, record in ipairs(blackoutLights) do
		if record.Light.Parent then
			record.Light.Enabled = false
			record.Light.Brightness = 0
		end
	end
	for _, record in ipairs(blackoutParts) do
		if record.Part.Parent then
			record.Part.Material = Enum.Material.SmoothPlastic
			record.Part.Color = Color3.fromRGB(13, 14, 15)
		end
	end
	completionFadeActive = false
	script:SetAttribute("Level6_CompletionDimActive", false)
	script:SetAttribute("Level6_CompletionDimProgress", if unlocked then 1 else 0)
	script:SetAttribute("Level6_CompletionBlackoutActive", unlocked)
	script:SetAttribute("Level6_BlackoutScreamFlickerActive", false)
end

local function completionTiming(): (number, number, number)
	local state = stateFolder()
	local startValue = state and state:GetAttribute("Level6_CompletionDimStartedAtServerTime")
	if type(startValue) ~= "number" or startValue <= 0 then
		startValue = state and state:GetAttribute("Level6_CompletionSongStartServerTime")
	end
	local durationValue = state and state:GetAttribute("Level6_CompletionDimDuration")
	local duration = if type(durationValue) == "number" and durationValue > .1
		then durationValue else DEFAULT_COMPLETION_DIM_DURATION
	local now = workspace:GetServerTimeNow()
	local startedAt = if type(startValue) == "number" and startValue > 0 then startValue else now
	return startedAt, duration, math.clamp((now - startedAt) / duration, 0, 1)
end

local function beginCompletionFade()
	local startedAt, duration, progress = completionTiming()
	local remaining = math.max(0, duration * (1 - progress))
	completionFadeActive = remaining > .04
	completionFadeEndsAtServerTime = startedAt + duration
	script:SetAttribute("Level6_CompletionDimActive", completionFadeActive)
	script:SetAttribute("Level6_CompletionDimProgress", progress)
	script:SetAttribute("Level6_CompletionBlackoutActive", false)

	local dark = Color3.fromRGB(13, 14, 15)
	for _, record in ipairs(blackoutLights) do
		if record.Light.Parent then
			record.Light.Enabled = record.Enabled
			record.Light.Brightness = record.Brightness * (1 - progress)
			if completionFadeActive then tween(record.Light, remaining, {Brightness = 0}) end
		end
	end
	for _, record in ipairs(blackoutParts) do
		if record.Part.Parent then
			record.Part.Material = record.Material
			record.Part.Color = record.Color:Lerp(dark, progress)
			if completionFadeActive then tween(record.Part, remaining, {Color = dark}) end
		end
	end

	colorGrade.Enabled = true
	bloom.Enabled = false
	local targetBrightness = .04
	local targetExposure = -.85
	local targetAmbient = Color3.fromRGB(0, 0, 0)
	local targetFog = Color3.fromRGB(2, 3, 4)
	Lighting.Brightness = Lighting.Brightness + (targetBrightness - Lighting.Brightness) * progress
	Lighting.ExposureCompensation = Lighting.ExposureCompensation
		+ (targetExposure - Lighting.ExposureCompensation) * progress
	Lighting.Ambient = Lighting.Ambient:Lerp(targetAmbient, progress)
	Lighting.OutdoorAmbient = Lighting.OutdoorAmbient:Lerp(targetAmbient, progress)
	Lighting.ColorShift_Top = Lighting.ColorShift_Top:Lerp(Color3.new(0, 0, 0), progress)
	Lighting.ColorShift_Bottom = Lighting.ColorShift_Bottom:Lerp(Color3.new(0, 0, 0), progress)
	Lighting.EnvironmentDiffuseScale *= 1 - progress
	Lighting.EnvironmentSpecularScale += (.02 - Lighting.EnvironmentSpecularScale) * progress
	Lighting.FogColor = Lighting.FogColor:Lerp(targetFog, progress)
	Lighting.FogStart += (14 - Lighting.FogStart) * progress
	Lighting.FogEnd += (115 - Lighting.FogEnd) * progress
	colorGrade.Brightness += (-.08 - colorGrade.Brightness) * progress
	colorGrade.Contrast += (.13 - colorGrade.Contrast) * progress
	colorGrade.Saturation += (-.32 - colorGrade.Saturation) * progress
	colorGrade.TintColor = colorGrade.TintColor:Lerp(Color3.fromRGB(104, 122, 132), progress)
	if completionFadeActive then
		tween(Lighting, remaining, {
			Brightness = targetBrightness,
			ExposureCompensation = targetExposure,
			Ambient = targetAmbient,
			OutdoorAmbient = targetAmbient,
			ColorShift_Top = Color3.new(0, 0, 0),
			ColorShift_Bottom = Color3.new(0, 0, 0),
			EnvironmentDiffuseScale = 0,
			EnvironmentSpecularScale = .02,
			FogColor = targetFog,
			FogStart = 14,
			FogEnd = 115,
		})
		tween(colorGrade, remaining, {
			Brightness = -.08,
			Contrast = .13,
			Saturation = -.32,
			TintColor = Color3.fromRGB(104, 122, 132),
		})
	else
		enforceBlackout()
	end
end

local function updateBlackoutFlicker()
	if not blackoutApplied then return end
	if exitUnlocked() then
		local _, duration, progress = completionTiming()
		script:SetAttribute("Level6_CompletionDimProgress", progress)
		if completionFadeActive
			and workspace:GetServerTimeNow() < completionFadeEndsAtServerTime - .01
			and progress < 1 then
			return
		end
		if duration > 0 then enforceBlackout() end
		return
	end
	local state = stateFolder()
	local startValue = state and state:GetAttribute("Level6_BlackoutScreamStartedAtServerTime")
	local durationValue = state and state:GetAttribute("Level6_BlackoutScreamDuration")
	local serialValue = state and state:GetAttribute("Level6_BlackoutSerial")
	local startedAt = if type(startValue) == "number" then startValue else 0
	local duration = if type(durationValue) == "number" and durationValue > 0
		then durationValue else BLACKOUT_SCREAM_DURATION
	local elapsed = workspace:GetServerTimeNow() - startedAt
	if startedAt <= 0 or elapsed < 0 or elapsed >= duration then
		if blackoutFlickerPulse ~= -1 then
			blackoutFlickerPulse = -1
			-- The pass that just ended left fixtures lit, so the sweep below has
			-- real work to do -- exactly once.
			blackoutSweptUnlocked = nil
			script:SetAttribute("Level6_BlackoutScreamFlickerPulse", -1)
		end
		enforceBlackout()
		return
	end

	local pulse = math.floor(elapsed / BLACKOUT_FLICKER_INTERVAL)
	if reduceFlashing() then
		-- A smooth swell, never a full-scene on/off: every fixture keeps its own
		-- material and colour and none of them reaches zero, so the scream still
		-- lands as a wave of darkness with no strobe edge in it. Written every
		-- throttled frame rather than once per pulse, because the whole point is
		-- that it is continuous.
		local level = REDUCED_FLASH_FLOOR + (1 - REDUCED_FLASH_FLOOR)
			* (.5 - .5 * math.cos(elapsed * (math.pi * 2) / REDUCED_FLASH_PERIOD))
		for _, record in ipairs(blackoutLights) do
			if record.Light.Parent then
				record.Light.Enabled = record.Enabled
				record.Light.Brightness = record.Brightness * level
			end
		end
		for _, record in ipairs(blackoutParts) do
			if record.Part.Parent then
				record.Part.Material = record.Material
				record.Part.Color = Color3.fromRGB(13, 14, 15):Lerp(record.Color, level)
			end
		end
		-- Not -1, so the branch above knows a pass has touched the world and marks
		-- the sweep due when the scream ends.
		blackoutFlickerPulse = pulse
		script:SetAttribute("Level6_BlackoutScreamFlickerActive", true)
		script:SetAttribute("Level6_BlackoutScreamFlickerPulse", pulse)
		return
	end
	if pulse == blackoutFlickerPulse then return end
	blackoutFlickerPulse = pulse
	local serial = if type(serialValue) == "number" then math.floor(serialValue) else 0
	-- Shared server-time hashing gives every client the same violent, irregular
	-- sequence without local waits drifting apart.
	local lit = ((pulse * 37 + serial * 17 + 5) % 11) < 4 or pulse % 13 == 0
	for _, record in ipairs(blackoutLights) do
		if record.Light.Parent then
			record.Light.Enabled = lit and record.Enabled
			record.Light.Brightness = if lit then record.Brightness * 1.4 else 0
		end
	end
	for _, record in ipairs(blackoutParts) do
		if record.Part.Parent then
			record.Part.Material = if lit then record.Material else Enum.Material.SmoothPlastic
			record.Part.Color = if lit then record.Color else Color3.fromRGB(13, 14, 15)
		end
	end
	script:SetAttribute("Level6_BlackoutScreamFlickerActive", true)
	script:SetAttribute("Level6_BlackoutScreamFlickerPulse", pulse)
end

local function normalizeSubtleFixtures()
	for _, record in ipairs(fixtures) do
		if record.Light.Parent then
			record.Light.Brightness = record.Brightness
			record.Light.Enabled = record.Enabled
		end
		if record.Part.Parent then record.Part.Material = Enum.Material.Neon end
		record.RestoreAt = 0
		record.Pulse = 0
		record.NextPulseAt = 0
	end
end

local function beginPreBlackout()
	if preBlackoutApplied or blackoutApplied or recoveryFlickerApplied then return end
	normalizeSubtleFixtures()
	captureWorldLightBaseline()
	preBlackoutApplied = true
	preBlackoutFlickerPulse = -1
	script:SetAttribute("Level6_PreBlackoutFlickerActive", true)
end

local function updatePreBlackoutFlicker()
	if not preBlackoutApplied then return end
	local state = stateFolder()
	local startValue = state and state:GetAttribute("Level6_PreBlackoutStartedAtServerTime")
	local untilValue = state and state:GetAttribute("Level6_PreBlackoutUntilServerTime")
	local serialValue = state and state:GetAttribute("Level6_PreBlackoutSerial")
	local startedAt = if type(startValue) == "number" then startValue else 0
	local untilTime = if type(untilValue) == "number" then untilValue else 0
	local duration = math.max(.1, untilTime - startedAt)
	local elapsed = workspace:GetServerTimeNow() - startedAt
	if startedAt <= 0 or elapsed < 0 or elapsed >= duration then return end
	local pulse = math.floor(elapsed / PRE_BLACKOUT_FLICKER_INTERVAL)
	if pulse == preBlackoutFlickerPulse then return end
	preBlackoutFlickerPulse = pulse
	local progress = math.clamp(elapsed / duration, 0, 1)
	local serial = if type(serialValue) == "number" then math.floor(serialValue) else 0
	local offChance = .10 + progress * .67
	-- This pass is already desynchronised per fixture, so it is not the
	-- whole-screen strobe the scream is. ReduceFlashing still takes the on/off
	-- EDGE out of it: an unlit fixture dips to this fraction of its baseline and
	-- keeps its material instead of snapping to black.
	local dimFloor = if reduceFlashing() then REDUCED_FLASH_FLOOR else 0
	for index, record in ipairs(blackoutLights) do
		if record.Light.Parent then
			local hash = ((pulse * 43 + index * 19 + serial * 11) % 100) / 100
			local surge = (pulse + index * 3) % 17 == 0
			local lit = record.Enabled and (hash > offChance or surge)
			record.Light.Enabled = lit or (dimFloor > 0 and record.Enabled)
			record.Light.Brightness = if lit
				then record.Brightness * (surge and 1.35 or math.max(.28, 1 - progress * .48))
				else record.Brightness * dimFloor
		end
	end
	for index, record in ipairs(blackoutParts) do
		if record.Part.Parent then
			local hash = ((pulse * 31 + index * 23 + serial * 7) % 100) / 100
			local lit = hash > offChance or (pulse + index) % 19 == 0
			record.Part.Material = if lit or dimFloor > 0
				then record.Material else Enum.Material.SmoothPlastic
			record.Part.Color = if lit then record.Color
				else Color3.fromRGB(22, 22, 20):Lerp(record.Color, dimFloor)
		end
	end
	script:SetAttribute("Level6_PreBlackoutFlickerPulse", pulse)
end

local function endPreBlackout(reapplyGrade: boolean)
	if not preBlackoutApplied then return end
	restoreBlackoutWorld()
	if reapplyGrade and active then applyLevelGrade(exitUnlocked()) end
end

local function beginRecoveryFlicker()
	if recoveryFlickerApplied then return end
	if preBlackoutApplied then endPreBlackout(false) end
	if not blackoutApplied and #blackoutLights == 0 then captureWorldLightBaseline() end
	blackoutApplied = false
	recoveryFlickerApplied = true
	recoveryFlickerPulse = -1
	script:SetAttribute("Level6_BlackoutScreamFlickerActive", false)
	script:SetAttribute("Level6_RecoveryFlickerActive", true)
	cancelTweens()
	applyLevelGrade(exitUnlocked())
end

local function updateRecoveryFlicker()
	if not recoveryFlickerApplied then return end
	local state = stateFolder()
	local startValue = state and state:GetAttribute("Level6_RecoveryFlickerStartedAtServerTime")
	local untilValue = state and state:GetAttribute("Level6_RecoveryFlickerUntilServerTime")
	local startedAt = if type(startValue) == "number" then startValue else 0
	local untilTime = if type(untilValue) == "number" then untilValue else 0
	local duration = math.max(.1, untilTime - startedAt)
	local elapsed = workspace:GetServerTimeNow() - startedAt
	if startedAt <= 0 or elapsed < 0 then return end
	local progress = math.clamp(elapsed / duration, 0, 1)
	local pulse = math.floor(math.max(0, elapsed) / RECOVERY_FLICKER_INTERVAL)
	if pulse == recoveryFlickerPulse then return end
	recoveryFlickerPulse = pulse
	-- Same rule as the pre-blackout pass: desynchronised already, so the cadence
	-- stands, but ReduceFlashing removes the snap to black.
	local dimFloor = if reduceFlashing() then REDUCED_FLASH_FLOOR else 0
	for index, record in ipairs(blackoutLights) do
		if record.Light.Parent then
			local turnOnAt = .10 + (((index * 37) % 67) / 100)
			local sputter = ((pulse * 29 + index * 17) % 13) < 3
			local lit = record.Enabled and (progress >= .94 or (progress >= turnOnAt and not sputter))
			record.Light.Enabled = lit or (dimFloor > 0 and record.Enabled)
			record.Light.Brightness = if lit
				then record.Brightness * math.min(1, .55 + progress * .55)
				else record.Brightness * dimFloor
		end
	end
	for index, record in ipairs(blackoutParts) do
		if record.Part.Parent then
			local turnOnAt = .08 + (((index * 41) % 71) / 100)
			local sputter = ((pulse * 23 + index * 13) % 11) < 2
			local lit = progress >= .94 or (progress >= turnOnAt and not sputter)
			record.Part.Material = if lit or dimFloor > 0
				then record.Material else Enum.Material.SmoothPlastic
			record.Part.Color = if lit then record.Color
				else Color3.fromRGB(13, 14, 15):Lerp(record.Color, dimFloor)
		end
	end
	script:SetAttribute("Level6_RecoveryFlickerPulse", pulse)
end

local function endRecoveryFlicker(reapplyGrade: boolean)
	if not recoveryFlickerApplied then return end
	restoreBlackoutWorld()
	if reapplyGrade and active then applyLevelGrade(exitUnlocked()) end
end

local function beginBlackout()
	if blackoutApplied then return end
	if recoveryFlickerApplied then endRecoveryFlicker(false) end
	if preBlackoutApplied then
		-- Keep the clean baseline captured at 2:25; never snapshot a fixture while
		-- the warning flicker has it temporarily dimmed or switched off.
		preBlackoutApplied = false
		preBlackoutFlickerPulse = -1
		script:SetAttribute("Level6_PreBlackoutFlickerActive", false)
		script:SetAttribute("Level6_PreBlackoutFlickerPulse", -1)
	else
		normalizeSubtleFixtures()
		captureWorldLightBaseline()
	end
	blackoutApplied = true
	-- The pre-blackout branch above deliberately keeps its clean baseline, so
	-- captureWorldLightBaseline did not run on that path and nothing else has
	-- marked the sweep due.
	blackoutSweptUnlocked = nil
	cancelTweens()
	if exitUnlocked() then
		beginCompletionFade()
		return
	end
	colorGrade.Enabled = true
	bloom.Enabled = false
	tween(Lighting, .35, {
		-- Keep the unlit world black while allowing a handheld dynamic light to
		-- survive the grade. The previous -1.55 exposure erased ~80% of its beam.
		Brightness = .04,
		ExposureCompensation = -.85,
		Ambient = Color3.fromRGB(0, 0, 0),
		OutdoorAmbient = Color3.fromRGB(0, 0, 0),
		ColorShift_Top = Color3.new(0, 0, 0),
		ColorShift_Bottom = Color3.new(0, 0, 0),
		EnvironmentDiffuseScale = 0,
		EnvironmentSpecularScale = .02,
		FogColor = Color3.fromRGB(2, 3, 4),
		FogStart = 14,
		FogEnd = 115,
	})
	tween(colorGrade, .35, {
		Brightness = -.08,
		Contrast = .13,
		Saturation = -.32,
		TintColor = Color3.fromRGB(104, 122, 132),
	})
	enforceBlackout()
end

local function endBlackout(reapplyGrade: boolean)
	if not blackoutApplied then return end
	restoreBlackoutWorld()
	if reapplyGrade and active then applyLevelGrade(exitUnlocked()) end
end

local function shouldOwnLighting(): boolean
	return workspace:GetAttribute("Level6SelectedLevel") == LEVEL
		and workspace:GetAttribute("Level6LightingOwnedByController") == true
		and player:GetAttribute("Level6InRound") == true
end

local function restoreFixtures()
	for _, record in ipairs(fixtures) do
		if record.Light.Parent then
			record.Light.Brightness = record.Brightness
			record.Light.Enabled = record.Enabled
		end
	end
end

local function clearFixtureRecords()
	restoreFixtures()
	table.clear(fixtures)
	table.clear(fixtureByPart)
end

local function tryAddFixture(instance: Instance)
	if #fixtures >= MAX_FLICKER_FIXTURES or not instance:IsA("BasePart") then return end
	if instance:GetAttribute("Level6_SubtleFlicker") ~= true or fixtureByPart[instance] then return end
	local light = instance:FindFirstChild("Level 6 Fluorescent Light")
	if not (light and light:IsA("SurfaceLight")) then return end
	local record: FixtureRecord = {
		Part = instance,
		Light = light,
		Brightness = light.Brightness,
		Enabled = light.Enabled,
		NextAt = os.clock() + random:NextNumber(4.5, 12),
		RestoreAt = 0,
		Pulse = 0,
		NextPulseAt = 0,
	}
	fixtureByPart[instance] = record
	table.insert(fixtures, record)
end

local function bindWorld(world: Model?)
	if world == boundWorld then return end
	if blackoutApplied or preBlackoutApplied or recoveryFlickerApplied then restoreBlackoutWorld() end
	if worldAddedConnection then worldAddedConnection:Disconnect() end
	if worldRemovingConnection then worldRemovingConnection:Disconnect() end
	worldAddedConnection = nil
	worldRemovingConnection = nil
	clearFixtureRecords()
	clearKitFixtureWatchers()
	boundWorld = world
	if not world then return end

	for _, descendant in ipairs(world:GetDescendants()) do
		tryAddFixture(descendant)
		tryWatchKitFixture(descendant)
		tryWatchCeilingBounce(descendant)
	end
	worldAddedConnection = world.DescendantAdded:Connect(function(descendant)
		-- The builder attaches the flicker attribute immediately after parenting.
		-- Deferring one scheduler turn observes the completed fixture safely.
		task.defer(function()
			if world ~= boundWorld or not descendant:IsDescendantOf(world) then return end
			tryAddFixture(descendant)
			tryWatchKitFixture(descendant)
			tryWatchCeilingBounce(descendant)
			if descendant:IsA("Light") then
				local lightParent = descendant.Parent
				if lightParent then tryWatchKitFixture(lightParent) end
			elseif descendant:IsA("MeshPart")
				and descendant:GetAttribute("Level6_KitVisualChunk") == true then
				local carrier = descendant.Parent
				if carrier and carrier:IsA("BasePart") then
					tryWatchKitFixture(carrier)
					if kitFixtureSeen[carrier] then syncKitFixtureVisuals(carrier) end
				end
			end
			if blackoutApplied or preBlackoutApplied or recoveryFlickerApplied then
				local oldCount = #blackoutParts
				captureAuthoredRoomGlow(descendant)
				if #blackoutParts > oldCount and blackoutApplied then
					if completionFadeActive then
						local _, duration, progress = completionTiming()
						local remaining = duration * (1 - progress)
						local glow = blackoutParts[#blackoutParts]
						local dark = Color3.fromRGB(13, 14, 15)
						glow.Part.Color = glow.Color:Lerp(dark, progress)
						if remaining > .04 then tween(glow.Part, remaining, {Color = dark}) end
					else
						-- The ordinary blackout sweep also darkens a room
						-- lamp whose glow streamed in after the baseline.
						blackoutSweptUnlocked = nil
					end
				end
			end
			if blackoutApplied and descendant:IsA("Light") then
				-- UNGATED, unlike the completion handling below it. A Light that
				-- streams in during an ORDINARY blackout is exactly the case
				-- enforceBlackout's sweep exists for, and marking the sweep due here
				-- is what lets that sweep stop running every frame the rest of the
				-- time. It costs one boolean write per late fixture.
				blackoutSweptUnlocked = nil
			end
			if blackoutApplied and exitUnlocked() and descendant:IsA("Light")
				and descendant:GetAttribute("Level6_CeilingBounce") ~= true then
				local _, duration, progress = completionTiming()
				local remaining = duration * (1 - progress)
				local parent = descendant.Parent
				if completionFadeActive and remaining > .04 then
					local baseline = descendant.Brightness
					descendant.Brightness = baseline * (1 - progress)
					tween(descendant, remaining, {Brightness = 0})
					if parent and parent:IsA("BasePart") then
						local dark = Color3.fromRGB(13, 14, 15)
						parent.Color = parent.Color:Lerp(dark, progress)
						tween(parent, remaining, {Color = dark})
					end
				else
					descendant.Enabled = false
					descendant.Brightness = 0
					if parent and parent:IsA("BasePart") then
						parent.Material = Enum.Material.SmoothPlastic
						parent.Color = Color3.fromRGB(13, 14, 15)
					end
				end
			end
		end)
	end)
	worldRemovingConnection = world.AncestryChanged:Connect(function(_, parent)
		if parent == nil and boundWorld == world then bindWorld(nil) end
	end)
end

local function refreshWorld()
	local object = workspace:FindFirstChild(WORLD_NAME)
	bindWorld(if object and object:IsA("Model") then object else nil)
end

applyLevelGrade = function(unlocked: boolean)
	lastExitUnlocked = unlocked
	cancelTweens()
	colorGrade.Enabled = true
	bloom.Enabled = true
	Lighting.GlobalShadows = true

	local tint = if unlocked then Color3.fromRGB(216, 235, 214) else Color3.fromRGB(232, 219, 184)
	-- Only the ceiling fixtures should illuminate the occupied mall. This
	-- client-owned grade keeps the exterior at night without changing the lobby
	-- or the original Level 3 for players outside this preview.
	local fog = if unlocked then Color3.fromRGB(25, 32, 33) else Color3.fromRGB(25, 24, 22)
	local ambient = if unlocked then Color3.fromRGB(19, 21, 22) else Color3.fromRGB(18, 17, 16)

	tween(Lighting, 0.48, {
		Brightness = 0,
		ClockTime = 0.5,
		ExposureCompensation = if unlocked then 0.04 else 0,
		Ambient = ambient,
		OutdoorAmbient = Color3.new(0, 0, 0),
		-- ColorShift is additive in Roblox; near-white values flatten and wash
		-- out every lit surface.  Keep it near neutral and let the dedicated
		-- color grade provide the abandoned-mall tint.
		ColorShift_Top = if unlocked then Color3.fromRGB(4, 12, 8) else Color3.fromRGB(18, 14, 8),
		ColorShift_Bottom = if unlocked then Color3.fromRGB(0, 5, 6) else Color3.fromRGB(2, 3, 0),
		FogColor = fog,
		FogStart = 72,
		FogEnd = if unlocked then 540 else 460,
		EnvironmentDiffuseScale = 0,
		EnvironmentSpecularScale = 0,
		ShadowSoftness = 0.72,
	})
	tween(colorGrade, 0.48, {
		Brightness = if unlocked then 0.012 else 0.004,
		Contrast = if unlocked then 0.040 else 0.045,
		Saturation = if unlocked then -0.045 else -0.065,
		TintColor = tint,
	})
	tween(bloom, 0.48, {
		Intensity = if unlocked then 0.11 else 0.08,
		Size = 18,
		Threshold = 1.45,
	})

	if not recoveryFlickerApplied then
		for _, record in ipairs(fixtures) do
			if record.Light.Parent then
				record.Light.Enabled = true
				record.Light.Brightness = record.Brightness
			end
		end
	end
end

local function restoreLighting()
	if blackoutApplied or preBlackoutApplied or recoveryFlickerApplied then restoreBlackoutWorld() end
	transitionSerial += 1
	local serial = transitionSerial
	local original = snapshot
	snapshot = nil
	lastExitUnlocked = nil
	cancelTweens()
	restoreFixtures()
	if not original then
		restoreInheritedEffects()
		colorGrade.Enabled = false
		bloom.Enabled = false
		return
	end

	-- Restore immediately on preview exit so the lobby never captures an in-flight grade tween.
	Lighting.GlobalShadows = original.GlobalShadows
	Lighting.Brightness = original.Brightness
	Lighting.ClockTime = original.ClockTime
	Lighting.ExposureCompensation = original.ExposureCompensation
	Lighting.Ambient = original.Ambient
	Lighting.OutdoorAmbient = original.OutdoorAmbient
	Lighting.ColorShift_Top = original.ColorShiftTop
	Lighting.ColorShift_Bottom = original.ColorShiftBottom
	Lighting.FogColor = original.FogColor
	Lighting.FogStart = original.FogStart
	Lighting.FogEnd = original.FogEnd
	Lighting.EnvironmentDiffuseScale = original.EnvironmentDiffuseScale
	Lighting.EnvironmentSpecularScale = original.EnvironmentSpecularScale
	Lighting.ShadowSoftness = original.ShadowSoftness
	restoreInheritedEffects()
	colorGrade.Enabled = false
	bloom.Enabled = false
end

local function refreshOwnership()
	local shouldBeActive = shouldOwnLighting()
	if shouldBeActive and not active then
		active = true
		transitionSerial += 1
		snapshot = captureLighting()
		suppressInheritedEffects()
		refreshWorld()
		applyLevelGrade(exitUnlocked())
	elseif not shouldBeActive and active then
		active = false
		restoreLighting()
	end
end

workspace:GetAttributeChangedSignal("Level6SelectedLevel"):Connect(refreshOwnership)
workspace:GetAttributeChangedSignal("Level6LightingOwnedByController"):Connect(refreshOwnership)
workspace:GetAttributeChangedSignal("Level6ExitUnlocked"):Connect(function()
	if active and not blackoutApplied and not preBlackoutApplied and not recoveryFlickerApplied
		and lastExitUnlocked ~= exitUnlocked() then applyLevelGrade(exitUnlocked()) end
end)
player:GetAttributeChangedSignal("Level6InRound"):Connect(refreshOwnership)
workspace.ChildAdded:Connect(function(child)
	if child.Name == WORLD_NAME then task.defer(refreshWorld) end
end)
workspace.ChildRemoved:Connect(function(child)
	if child == boundWorld then bindWorld(nil) end
end)

local accumulated = 0
RunService.Heartbeat:Connect(function(dt)
	accumulated += dt
	if accumulated < 0.08 then return end
	accumulated = 0

	refreshOwnership()
	if not active then return end
	local wantsBlackout = blackoutRequested()
	local wantsPreBlackout = preBlackoutRequested()
	local wantsRecovery = recoveryFlickerRequested()
	if wantsBlackout then
		if recoveryFlickerApplied then endRecoveryFlicker(false) end
		beginBlackout()
		updateBlackoutFlicker()
	elseif wantsRecovery then
		beginRecoveryFlicker()
		updateRecoveryFlicker()
	elseif wantsPreBlackout then
		if blackoutApplied then endBlackout(true) end
		if recoveryFlickerApplied then endRecoveryFlicker(true) end
		beginPreBlackout()
		updatePreBlackoutFlicker()
	else
		if blackoutApplied then endBlackout(true)
		elseif preBlackoutApplied then endPreBlackout(true)
		elseif recoveryFlickerApplied then endRecoveryFlicker(true) end
	end
	local unlocked = exitUnlocked()
	if not blackoutApplied and not preBlackoutApplied and not recoveryFlickerApplied
		and unlocked ~= lastExitUnlocked then applyLevelGrade(unlocked) end

	local now = os.clock()
	for index = #fixtures, 1, -1 do
		if blackoutApplied or preBlackoutApplied or recoveryFlickerApplied then break end
		local record = fixtures[index]
		if not (record.Part.Parent and record.Light.Parent) then
			fixtureByPart[record.Part] = nil
			table.remove(fixtures, index)
		elseif record.RestoreAt > 0 and now >= record.RestoreAt then
			record.Light.Brightness = record.Brightness
			record.Part.Material = Enum.Material.Neon
			record.RestoreAt = 0
			if record.Pulse > 0 then
				record.NextPulseAt = now + random:NextNumber(0.045, 0.12)
			else
				record.NextAt = now + random:NextNumber(5.5, 16)
			end
		elseif record.RestoreAt == 0 and record.Pulse > 0 and now >= record.NextPulseAt then
			-- A failing ballast gives one or two clearly readable irregular blinks.
			record.Light.Brightness = record.Brightness * random:NextNumber(0.03, 0.18)
			record.Part.Material = Enum.Material.SmoothPlastic
			record.Pulse -= 1
			record.RestoreAt = now + random:NextNumber(0.075, 0.18)
		elseif record.RestoreAt == 0 and record.Pulse == 0 and now >= record.NextAt then
			record.Light.Brightness = record.Brightness * random:NextNumber(0.02, 0.14)
			record.Part.Material = Enum.Material.SmoothPlastic
			record.Pulse = random:NextInteger(0, 2)
			record.RestoreAt = now + random:NextNumber(0.09, 0.24)
		end
	end
end)

refreshWorld()
refreshOwnership()
]====]
 local compiled,problem=loadstring(candidate)
 assert(compiled,"Syntax: "..tostring(problem))
 rows[#rows+1]={instance=instance,source=source,candidate=candidate,beforeSha256=sha(source)}
end

local result={}
for _,row in ipairs(rows) do
 SES:UpdateSourceAsync(row.instance,function(editor)
  assert(editor==row.source and row.instance.Source==row.source,"Baseline changed inside CAS")
  return row.candidate
 end)
 assert(row.instance.Source==row.candidate and SES:GetEditorSource(row.instance)==row.candidate,"Post-write parity failed")
 result[#result+1]={path=row.instance:GetFullName(),class=row.instance.ClassName,beforeSha256=row.beforeSha256,afterSha256=sha(row.candidate),bytes=#row.candidate,editorMatch=true}
end
return H:JSONEncode({placeId=game.PlaceId,universeId=game.GameId,at=DateTime.now():ToIsoDate(),sources=result,scope="Level6 working-fixture ceiling bounce and client ballast synchronization only; no global properties or other levels changed"})
