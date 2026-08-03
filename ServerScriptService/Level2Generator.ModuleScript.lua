-- Level2Generator
-- Bright, dry Poolrooms: spacious tiled chambers, shallow basins,
-- wall-mounted filtration valves, open-sky ceiling voids and a powered exit tube.

local Players = game:GetService("Players")
local ServerStorage = game:GetService("ServerStorage")
local Lighting = game:GetService("Lighting")
local ReplicatedStorage = game:GetService("ReplicatedStorage")
local TweenService = game:GetService("TweenService")
local CollectionService = game:GetService("CollectionService")

local Generator = {}

local GRID, ROOM, WALL_H = 5, 160, 28
local WORLD = GRID * ROOM
local TILE_TEXTURE = "rbxassetid://113211706146395"

local C = {
	tile = Color3.fromRGB(226, 230, 222),
	tileBlue = Color3.fromRGB(190, 219, 224),
	groutBlue = Color3.fromRGB(31, 113, 172),
	dark = Color3.fromRGB(20, 27, 29),
	metal = Color3.fromRGB(83, 93, 96),
	red = Color3.fromRGB(231, 64, 49),
	yellow = Color3.fromRGB(251, 205, 56),
	blue = Color3.fromRGB(50, 132, 231),
	green = Color3.fromRGB(66, 255, 151),
	sky = Color3.fromRGB(63, 164, 235),
}

local function part(parent, name, cf, size, color, material, transparency)
	local p = Instance.new("Part")
	p.Name, p.Anchored, p.CFrame, p.Size = name, true, cf, size
	p.Color, p.Material, p.Transparency = color, material or Enum.Material.SmoothPlastic, transparency or 0
	p.TopSurface, p.BottomSurface, p.Parent = Enum.SurfaceType.Smooth, Enum.SurfaceType.Smooth, parent
	return p
end

local function texture(object, faces, studs)
	for _, face in ipairs(faces or Enum.NormalId:GetEnumItems()) do
		local t = Instance.new("Texture")
		t.Name, t.Texture, t.Face = "PoolTileTexture", TILE_TEXTURE, face
		t.StudsPerTileU, t.StudsPerTileV = studs or 16, studs or 16
		t.Color3 = Color3.fromRGB(232, 239, 239)
		t.Parent = object
	end
end

local function tiledPart(parent, name, cf, size, color, faces, studs)
	local p = part(parent, name, cf, size, color or C.tile)
	texture(p, faces, studs or 16)
	return p
end

local function label(object, face, top, bottom, color)
	local gui = Instance.new("SurfaceGui")
	gui.Face, gui.CanvasSize, gui.LightInfluence, gui.Parent = face or Enum.NormalId.Front, Vector2.new(700, 260), 0, object
	local bg = Instance.new("Frame")
	bg.Size, bg.BackgroundColor3, bg.BackgroundTransparency, bg.BorderSizePixel, bg.Parent =
		UDim2.fromScale(1, 1), C.dark, 0.08, 0, gui
	local title = Instance.new("TextLabel")
	title.Name, title.BackgroundTransparency, title.Position, title.Size = "Title", 1, UDim2.fromScale(.04,.07), UDim2.fromScale(.92,.54)
	title.Font, title.Text, title.TextColor3, title.TextScaled, title.Parent =
		Enum.Font.GothamBold, top, color or C.tile, true, bg
	local sub = Instance.new("TextLabel")
	sub.Name, sub.BackgroundTransparency, sub.Position, sub.Size = "Subtitle", 1, UDim2.fromScale(.04,.68), UDim2.fromScale(.92,.2)
	sub.Font, sub.Text, sub.TextColor3, sub.TextScaled, sub.Parent =
		Enum.Font.Code, bottom or "", Color3.fromRGB(220,226,216), true, bg
	return title, sub
end

local function lightPanel(parent, position, size)
	local lamp = part(parent, "PoolCeilingLight", CFrame.new(position), size or Vector3.new(26,.3,5),
		Color3.fromRGB(232,255,250), Enum.Material.Neon)
	lamp.CanCollide = false
	local l = Instance.new("SurfaceLight")
	l.Face, l.Color, l.Brightness, l.Range, l.Angle, l.Shadows, l.Parent =
		Enum.NormalId.Bottom, Color3.fromRGB(220,245,240), 2.5, 62, 125, false, lamp
end

local function loreBoard(parent, position)
	local board = part(parent, "PoolroomsWarningBoard", CFrame.new(position),
		Vector3.new(15, 9, .35), C.dark, Enum.Material.Metal)
	local gui = Instance.new("SurfaceGui")
	gui.Name, gui.Face, gui.CanvasSize, gui.LightInfluence, gui.Parent =
		"WarningDisplay", Enum.NormalId.Back, Vector2.new(900, 540), 0, board

	local bg = Instance.new("Frame")
	bg.Size, bg.BackgroundColor3, bg.BorderSizePixel, bg.Parent =
		UDim2.fromScale(1, 1), Color3.fromRGB(13, 22, 27), 0, gui
	local stroke = Instance.new("UIStroke")
	stroke.Thickness, stroke.Color, stroke.Parent = 5, C.groutBlue, bg

	local heading = Instance.new("TextLabel")
	heading.BackgroundTransparency, heading.Position, heading.Size =
		1, UDim2.fromScale(.04, .045), UDim2.fromScale(.92, .12)
	heading.Font, heading.Text, heading.TextColor3, heading.TextScaled, heading.Parent =
		Enum.Font.Code, "DRY FILTRATION NOTICE", C.tileBlue, true, bg

	local sketch = Instance.new("Frame")
	sketch.BackgroundTransparency, sketch.Position, sketch.Size, sketch.Parent =
		1, UDim2.fromScale(.04, .2), UDim2.fromScale(.31, .68), bg

	local function noodle(name, pos, size, rotation, color)
		local f = Instance.new("Frame")
		f.Name, f.Position, f.Size, f.Rotation, f.BackgroundColor3, f.BorderSizePixel, f.Parent =
			name, pos, size, rotation, color, 0, sketch
		local corner = Instance.new("UICorner")
		corner.CornerRadius, corner.Parent = UDim.new(.5, 0), f
		return f
	end
	noodle("ConeHead", UDim2.fromScale(.39, .02), UDim2.fromScale(.22, .22), 0, C.yellow)
	noodle("TorsoRed", UDim2.fromScale(.38, .23), UDim2.fromScale(.10, .37), -4, C.red)
	noodle("TorsoBlue", UDim2.fromScale(.50, .23), UDim2.fromScale(.10, .37), 5, C.blue)
	noodle("LeftArm", UDim2.fromScale(.18, .29), UDim2.fromScale(.09, .43), 23, C.yellow)
	noodle("RightArm", UDim2.fromScale(.72, .29), UDim2.fromScale(.09, .43), -23, C.red)
	noodle("LeftLeg", UDim2.fromScale(.32, .57), UDim2.fromScale(.10, .38), 7, C.blue)
	noodle("RightLeg", UDim2.fromScale(.57, .57), UDim2.fromScale(.10, .38), -7, C.yellow)

	local sketchText = Instance.new("TextLabel")
	sketchText.BackgroundTransparency, sketchText.Position, sketchText.Size =
		1, UDim2.fromScale(.02, .89), UDim2.fromScale(.96, .1)
	sketchText.Font, sketchText.Text, sketchText.TextColor3, sketchText.TextScaled, sketchText.Parent =
		Enum.Font.Code, "POOL FOAM ENTITY", Color3.fromRGB(153, 190, 199), true, sketch

	local copy = Instance.new("TextLabel")
	copy.BackgroundTransparency, copy.Position, copy.Size =
		1, UDim2.fromScale(.39, .21), UDim2.fromScale(.56, .63)
	copy.Font, copy.Text, copy.TextColor3, copy.TextSize, copy.TextWrapped, copy.TextXAlignment, copy.TextYAlignment, copy.Parent =
		Enum.Font.Code,
		"BUILT FROM FLOTATION FOAM.\nSTARVED OF WATER.\n\nIT CAN SENSE THE WATER\nINSIDE YOUR BODY.\n\nOPEN ALL 3 PRESSURE VALVES\nTO UNSEAL THE EXIT TUBE.",
		Color3.fromRGB(221, 228, 218), 31, true,
		Enum.TextXAlignment.Left, Enum.TextYAlignment.Top, bg

	local warning = Instance.new("TextLabel")
	warning.BackgroundColor3, warning.BackgroundTransparency, warning.Position, warning.Size =
		Color3.fromRGB(67, 13, 17), .08, UDim2.fromScale(.38, .82), UDim2.fromScale(.57, .12)
	warning.Font, warning.Text, warning.TextColor3, warning.TextScaled, warning.Parent =
		Enum.Font.GothamBold, "IT WILL NOT STOP UNTIL EVERY DROP IS GONE", C.red, true, bg
	return board
end

local function blueGroutFloor(parent)
	part(parent, "BlueGroutFoundation", CFrame.new(0,-.55,0), Vector3.new(WORLD,1.1,WORLD), C.groutBlue)
	local floor = tiledPart(parent, "WorldFloor", CFrame.new(0,-.06,0), Vector3.new(WORLD,.12,WORLD), C.tileBlue, {Enum.NormalId.Top}, 18)
	floor.CanCollide = true
end

local function tiledSlab(parent, name, cf, size, color, studs)
	local foundation = part(parent, name.."Grout", cf * CFrame.new(0, -.42, 0),
		Vector3.new(size.X, .85, size.Z), C.groutBlue)
	foundation.CanCollide = true
	local tile = tiledPart(parent, name, cf, Vector3.new(size.X, .12, size.Z),
		color or C.tileBlue, {Enum.NormalId.Top}, studs or 16)
	tile.CanCollide = true
	return tile
end

local function lethalDepth(parent)
	local death = part(parent, "DeepPoolKillPlane", CFrame.new(0, -31, 0),
		Vector3.new(WORLD, 1, WORLD), Color3.fromRGB(0, 0, 0), Enum.Material.SmoothPlastic, 1)
	death.CanCollide = false
	death.Touched:Connect(function(hit)
		local humanoid = hit.Parent and hit.Parent:FindFirstChildOfClass("Humanoid")
		if not humanoid then
			local character = hit:FindFirstAncestorOfClass("Model")
			humanoid = character and character:FindFirstChildOfClass("Humanoid")
		end
		if humanoid then humanoid.Health = 0 end
	end)
end

local function deepPool(parent, center, poolW, poolD, bridgeMode)
	local ledge = 20
	local roomW = ROOM
	local roomD = ROOM
	for _, info in ipairs({
		{Vector3.new(0, 0, -(roomD-ledge)*.5), Vector3.new(roomW, .12, ledge)},
		{Vector3.new(0, 0, (roomD-ledge)*.5), Vector3.new(roomW, .12, ledge)},
		{Vector3.new(-(roomW-ledge)*.5, 0, 0), Vector3.new(ledge, .12, roomD-ledge*2)},
		{Vector3.new((roomW-ledge)*.5, 0, 0), Vector3.new(ledge, .12, roomD-ledge*2)},
	}) do
		tiledSlab(parent, "PoolPerimeterLedge", CFrame.new(center + info[1]), info[2], C.tileBlue, 15)
	end

	local depth = 45
	for _, info in ipairs({
		{Vector3.new(-poolW*.5, -depth*.5, 0), Vector3.new(1, depth, poolD)},
		{Vector3.new(poolW*.5, -depth*.5, 0), Vector3.new(1, depth, poolD)},
		{Vector3.new(0, -depth*.5, -poolD*.5), Vector3.new(poolW, depth, 1)},
		{Vector3.new(0, -depth*.5, poolD*.5), Vector3.new(poolW, depth, 1)},
	}) do
		tiledPart(parent, "DeepPoolWall", CFrame.new(center + info[1]), info[2],
			Color3.fromRGB(166, 207, 211), nil, 14)
	end
	tiledPart(parent, "DeepPoolBottom", CFrame.new(center + Vector3.new(0, -depth, 0)),
		Vector3.new(poolW, .8, poolD), Color3.fromRGB(30, 69, 82), {Enum.NormalId.Top}, 16)

	local function bridge(offset, size)
		tiledSlab(parent, "NarrowPoolBridge", CFrame.new(center + offset), size, C.tile, 14)
	end
	if bridgeMode == "cross" then
		bridge(Vector3.zero, Vector3.new(12, .12, poolD))
		bridge(Vector3.zero, Vector3.new(poolW, .12, 12))
	elseif bridgeMode == "singleX" then
		bridge(Vector3.zero, Vector3.new(poolW, .12, 13))
	elseif bridgeMode == "singleZ" then
		bridge(Vector3.zero, Vector3.new(13, .12, poolD))
	elseif bridgeMode == "offset" then
		bridge(Vector3.new(0, 0, -25), Vector3.new(poolW, .12, 11))
	end
end

local function fullRoomFloor(parent, center)
	tiledSlab(parent, "TiledRoomFloor", CFrame.new(center), Vector3.new(ROOM, .12, ROOM), C.tileBlue, 15)
end

local function poolRail(parent, center, alongX, length)
	local metal = Color3.fromRGB(120, 132, 135)
	local count = math.max(2, math.floor(length / 12))
	for i = 0, count do
		local alpha = i / count - .5
		local offset = alongX and Vector3.new(alpha*length, 1.7, 0) or Vector3.new(0, 1.7, alpha*length)
		part(parent, "PoolRailPost", CFrame.new(center + offset), Vector3.new(.35, 3.4, .35), metal, Enum.Material.Metal)
	end
	local railSize = alongX and Vector3.new(length, .35, .35) or Vector3.new(.35, .35, length)
	part(parent, "PoolHandrail", CFrame.new(center + Vector3.new(0, 3.25, 0)), railSize, metal, Enum.Material.Metal)
end

local function tiledColumn(parent, position, radius, height)
	local poolDepth = 45
	local totalHeight = height + poolDepth
	local centerY = (height - poolDepth) * .5
	local column = part(parent, "TiledPoolColumn",
		CFrame.new(position + Vector3.new(0, centerY, 0)) * CFrame.Angles(0, 0, math.pi/2),
		Vector3.new(totalHeight, radius*2, radius*2), C.tile, Enum.Material.SmoothPlastic)
	column.Shape = Enum.PartType.Cylinder
	texture(column, Enum.NormalId:GetEnumItems(), 13)
	for _, y in ipairs({-poolDepth+.45, height-.45}) do
		local ring = part(parent, "ColumnRing",
			CFrame.new(position + Vector3.new(0, y, 0)) * CFrame.Angles(0, 0, math.pi/2),
			Vector3.new(.7, radius*2.25, radius*2.25), C.groutBlue, Enum.Material.Metal)
		ring.Shape = Enum.PartType.Cylinder
	end
	return column
end

local function divingPlatform(parent, roomCenter, lateralOffset, height, edge, labelText)
	-- Put every tower on a pool ledge and aim its board inward over the empty
	-- basin.  The edge can change per room so boards never point along a bridge.
	local inward, sideAxis, anchor, boardSize, railSize, markerFace
	if edge == "west" then
		inward, sideAxis = Vector3.xAxis, Vector3.zAxis
		anchor = roomCenter + Vector3.new(-70, 0, lateralOffset)
		boardSize, railSize, markerFace = Vector3.new(20,.45,5), Vector3.new(7,3.4,.3), Enum.NormalId.Left
	elseif edge == "east" then
		inward, sideAxis = -Vector3.xAxis, Vector3.zAxis
		anchor = roomCenter + Vector3.new(70, 0, lateralOffset)
		boardSize, railSize, markerFace = Vector3.new(20,.45,5), Vector3.new(7,3.4,.3), Enum.NormalId.Right
	elseif edge == "north" then
		inward, sideAxis = Vector3.zAxis, Vector3.xAxis
		anchor = roomCenter + Vector3.new(lateralOffset, 0, -70)
		boardSize, railSize, markerFace = Vector3.new(5,.45,20), Vector3.new(.3,3.4,7), Enum.NormalId.Back
	else -- south
		inward, sideAxis = -Vector3.zAxis, Vector3.xAxis
		anchor = roomCenter + Vector3.new(lateralOffset, 0, 70)
		boardSize, railSize, markerFace = Vector3.new(5,.45,20), Vector3.new(.3,3.4,7), Enum.NormalId.Front
	end
	local metal = Color3.fromRGB(82, 95, 99)
	local supportHeight = math.max(2.5, height)
	part(parent,"DivingTowerSupport",CFrame.new(anchor+Vector3.new(0,supportHeight*.5,0)),
		Vector3.new(2.2,supportHeight,2.2),metal,Enum.Material.Metal)
	part(parent,"DivingTowerFoot",CFrame.new(anchor+Vector3.new(0,.3,0)),
		Vector3.new(6,.6,6),C.groutBlue,Enum.Material.Metal)

	local ladder=Instance.new("TrussPart")
	ladder.Name="DivingTowerLadder"; ladder.Anchored=true
	ladder.Size = (edge == "west" or edge == "east") and Vector3.new(1,supportHeight,3) or Vector3.new(3,supportHeight,1)
	ladder.CFrame=CFrame.new(anchor+Vector3.new(0,supportHeight*.5,0)-inward*2.2)
	ladder.Color=metal; ladder.Material=Enum.Material.Metal; ladder.Parent=parent

	local top=anchor+Vector3.new(0,height,0)
	part(parent,"DivingTowerPlatform",CFrame.new(top),Vector3.new(8,.65,8),C.tile,Enum.Material.SmoothPlastic)
	local boardCenter=top+Vector3.new(0,.45,0)+inward*10
	-- The springboard is manufactured pool equipment, not tiled architecture.
	-- Keep it a clean, solid light blue so it reads instantly as a diving board.
	local board=part(parent,"DivingBoard_"..labelText,CFrame.new(boardCenter),
		boardSize,Color3.fromRGB(116, 205, 235),Enum.Material.SmoothPlastic)
	board:SetAttribute("DivingHeight",labelText)

	for _,side in ipairs({-3.25,3.25}) do
		part(parent,"DivingPlatformRail",CFrame.new(top+Vector3.new(0,1.8,0)+sideAxis*side),
			railSize,metal,Enum.Material.Metal)
	end
	local marker=part(parent,"DivingHeightMarker",CFrame.new(anchor+Vector3.new(0,math.max(2,height-.8),0)-inward*1.25),
		Vector3.new(3.8,1.4,.25),C.dark,Enum.Material.Metal)
	if edge == "west" or edge == "east" then
		marker.Size = Vector3.new(.25,1.4,3.8)
	end
	label(marker,markerFace,labelText,"DIVING PLATFORM",C.tileBlue)
end

local function addDivingPlatforms(parent, roomCenter, gx, gz, kind, bridgeMode)
	local pattern=(gx*3+gz)%4
	-- If the room's bridge runs north/south, use the west ledge and aim east.
	-- Otherwise use the south ledge and aim north. Either way the board projects
	-- into open pool space instead of above a walkway.
	local edge = bridgeMode == "singleZ" and "west" or "south"
	if kind=="sun" then
		divingPlatform(parent,roomCenter,-42,3.5,"south","1 M")
		divingPlatform(parent,roomCenter,26,13,"south","5 M")
		divingPlatform(parent,roomCenter,46,24,"south","10 M")
	elseif kind=="deep" then
		if pattern==0 then divingPlatform(parent,roomCenter,32,3.5,edge,"1 M")
		elseif pattern==1 then divingPlatform(parent,roomCenter,32,13,edge,"5 M")
		elseif pattern==2 then divingPlatform(parent,roomCenter,32,24,edge,"10 M")
		else
			divingPlatform(parent,roomCenter,-42,3.5,edge,"1 M")
			divingPlatform(parent,roomCenter,26,13,edge,"5 M")
			divingPlatform(parent,roomCenter,46,24,edge,"10 M")
		end
	elseif kind=="pillars" and pattern==1 then
		divingPlatform(parent,roomCenter,-34,3.5,"south","1 M")
		divingPlatform(parent,roomCenter,34,13,"south","5 M")
	end
end

local function archGallery(parent, lights, center, alongX)
	local radius = 12
	for lane = -2, 2 do
		local distance = lane * 27
		for i = 0, 24 do
			local angle = i * math.pi / 24
			local side = math.cos(angle) * radius
			local y = 1 + math.sin(angle) * radius
			local tangent = Vector3.new(0, math.cos(angle), -math.sin(angle))
			local pos
			if alongX then
				pos = center + Vector3.new(distance, y, side)
			else
				pos = center + Vector3.new(side, y, distance)
				tangent = Vector3.new(-math.sin(angle), math.cos(angle), 0)
			end
			local rib = part(parent, "TiledArchRib", CFrame.lookAt(pos, pos+tangent),
				Vector3.new(.72, .85, 3.2), C.tile, Enum.Material.SmoothPlastic)
			rib.CanCollide = false
			texture(rib, Enum.NormalId:GetEnumItems(), 8)
		end
	end
	local wallSize = alongX and Vector3.new(118,14,2) or Vector3.new(2,14,118)
	local roofSize = alongX and Vector3.new(118,1,32) or Vector3.new(32,1,118)
	local sideA = alongX and Vector3.new(0,7,-16) or Vector3.new(-16,7,0)
	local sideB = alongX and Vector3.new(0,7,16) or Vector3.new(16,7,0)
	tiledPart(parent,"ArchPassageWall",CFrame.new(center+sideA),wallSize,C.tile,nil,13)
	tiledPart(parent,"ArchPassageWall",CFrame.new(center+sideB),wallSize,C.tile,nil,13)
	tiledPart(parent,"ArchPassageRoof",CFrame.new(center+Vector3.new(0,14.5,0)),roofSize,C.tile,nil,13)
	for i=-1,1 do
		local offset=alongX and Vector3.new(i*35,14,0) or Vector3.new(0,14,i*35)
		local lampSize=alongX and Vector3.new(14,.25,3.5) or Vector3.new(3.5,.25,14)
		lightPanel(lights,center+offset,lampSize)
	end
end

local function zigzagPartitions(parent, center, rotate)
	for i = -2, 2 do
		local shift = i*27
		local side = (i%2==0) and -32 or 32
		local pos = rotate and center+Vector3.new(side, 7, shift) or center+Vector3.new(shift, 7, side)
		local size = rotate and Vector3.new(72, 14, 2) or Vector3.new(2, 14, 72)
		tiledPart(parent, "NarrowPassageWall", CFrame.new(pos), size, C.tile, nil, 14)
	end
end

local function lowCeiling(parent, lights, center)
	tiledPart(parent, "LowPassageCeiling", CFrame.new(center+Vector3.new(0, 14.5, 0)),
		Vector3.new(ROOM, 1, ROOM), C.tile, nil, 15)
	for _, offset in ipairs({
		Vector3.new(-45,14,-45), Vector3.new(45,14,-45),
		Vector3.new(-45,14,45), Vector3.new(45,14,45),
	}) do lightPanel(lights, center+offset, Vector3.new(18,.25,4)) end
end

local function openSkyCeiling(parent, lights, center, gap)
	local border = (ROOM-gap)*.5
	for _, info in ipairs({
		{Vector3.new(0,WALL_H+.6,-(gap+border)*.5),Vector3.new(ROOM,1.2,border)},
		{Vector3.new(0,WALL_H+.6,(gap+border)*.5),Vector3.new(ROOM,1.2,border)},
		{Vector3.new(-(gap+border)*.5,WALL_H+.6,0),Vector3.new(border,1.2,gap)},
		{Vector3.new((gap+border)*.5,WALL_H+.6,0),Vector3.new(border,1.2,gap)},
	}) do tiledPart(parent,"HighPoolCeiling",CFrame.new(center+info[1]),info[2],C.tile,nil,16) end
	local sky = part(parent,"ImpossibleBlueSky",CFrame.new(center+Vector3.new(0,WALL_H+8,0)),
		Vector3.new(gap,1,gap),C.sky,Enum.Material.Neon)
	sky.CanCollide = false
	local glow = Instance.new("SurfaceLight")
	glow.Face,glow.Color,glow.Brightness,glow.Range,glow.Angle,glow.Shadows,glow.Parent =
		Enum.NormalId.Bottom,C.sky,1.25,55,150,false,sky
end

local function normalCeiling(parent, lights, center, dense)
	tiledPart(parent, "PoolCeiling", CFrame.new(center+Vector3.new(0,WALL_H+.6,0)),
		Vector3.new(ROOM,1.2,ROOM), C.tile, nil, 16)
	local offsets = dense and {
		Vector3.new(-52,WALL_H,-52), Vector3.new(0,WALL_H,-52), Vector3.new(52,WALL_H,-52),
		Vector3.new(-52,WALL_H,0), Vector3.new(0,WALL_H,0), Vector3.new(52,WALL_H,0),
		Vector3.new(-52,WALL_H,52), Vector3.new(0,WALL_H,52), Vector3.new(52,WALL_H,52),
	} or {
		Vector3.new(-42,WALL_H,-42), Vector3.new(42,WALL_H,-42),
		Vector3.new(-42,WALL_H,42), Vector3.new(42,WALL_H,42),
	}
	for _, offset in ipairs(offsets) do lightPanel(lights, center+offset, Vector3.new(20,.28,4.5)) end
end

local function boundaryWall(parent, center, horizontal, opened)
	local length, thickness = ROOM, 2
	if not opened then
		local size = horizontal and Vector3.new(length,WALL_H,thickness) or Vector3.new(thickness,WALL_H,length)
		tiledPart(parent,"SealedPoolWall",CFrame.new(center+Vector3.new(0,WALL_H*.5,0)),size,C.tile,nil,15)
		return
	end
	local doorW, doorH = 20, 13
	local side = (length-doorW)*.5
	local axis = horizontal and Vector3.xAxis or Vector3.zAxis
	local sideSize = horizontal and Vector3.new(side,WALL_H,thickness) or Vector3.new(thickness,WALL_H,side)
	tiledPart(parent,"PoolDoorWall",CFrame.new(center-axis*(doorW*.5+side*.5)+Vector3.new(0,WALL_H*.5,0)),sideSize,C.tile,nil,15)
	tiledPart(parent,"PoolDoorWall",CFrame.new(center+axis*(doorW*.5+side*.5)+Vector3.new(0,WALL_H*.5,0)),sideSize,C.tile,nil,15)
	local lintelSize = horizontal and Vector3.new(doorW,WALL_H-doorH,thickness) or Vector3.new(thickness,WALL_H-doorH,doorW)
	tiledPart(parent,"LowDoorLintel",CFrame.new(center+Vector3.new(0,doorH+(WALL_H-doorH)*.5,0)),lintelSize,C.tile,nil,14)
end

local function buildConnections()
	local rng = Random.new(23071998)
	local visited, links = {}, {}
	local function id(x,z) return x..","..z end
	local function connect(ax,az,bx,bz)
		links[id(ax,az).."|"..id(bx,bz)] = true
		links[id(bx,bz).."|"..id(ax,az)] = true
	end
	local stack = {{0,0}}
	visited[id(0,0)] = true
	while #stack > 0 do
		local current = stack[#stack]
		local x,z = current[1],current[2]
		local candidates = {}
		for _,d in ipairs({{1,0},{-1,0},{0,1},{0,-1}}) do
			local nx,nz=x+d[1],z+d[2]
			if nx>=0 and nx<GRID and nz>=0 and nz<GRID and not visited[id(nx,nz)] then
				table.insert(candidates,{nx,nz})
			end
		end
		if #candidates==0 then
			table.remove(stack)
		else
			local nextCell=candidates[rng:NextInteger(1,#candidates)]
			connect(x,z,nextCell[1],nextCell[2])
			visited[id(nextCell[1],nextCell[2])] = true
			table.insert(stack,nextCell)
		end
	end
	for x=0,GRID-1 do for z=0,GRID-1 do
		for _,d in ipairs({{1,0},{0,1}}) do
			local nx,nz=x+d[1],z+d[2]
			if nx<GRID and nz<GRID and rng:NextNumber()<.24 then connect(x,z,nx,nz) end
		end
	end end
	return function(ax,az,bx,bz) return links[id(ax,az).."|"..id(bx,bz)]==true end
end

local ROOM_TYPES = {
	{"arrival","corridor","deep","arches","pillars"},
	{"deep","pillars","corridor","split","deep"},
	{"arches","deep","sun","corridor","pillars"},
	{"split","corridor","deep","arches","steps"},
	{"deep","pillars","corridor","deep","exit"},
}

local function buildRoom(parent, lights, gx, gz, center)
	local kind = ROOM_TYPES[gz+1][gx+1]
	if kind=="arrival" or kind=="exit" then
		fullRoomFloor(parent,center)
		normalCeiling(parent,lights,center,false)
	elseif kind=="corridor" then
		fullRoomFloor(parent,center)
		zigzagPartitions(parent,center,(gx+gz)%2==0)
		lowCeiling(parent,lights,center)
	elseif kind=="arches" then
		fullRoomFloor(parent,center)
		archGallery(parent,lights,center,(gx+gz)%2==0)
		normalCeiling(parent,lights,center,false)
	elseif kind=="deep" then
		local bridgeMode=((gx+gz)%2==0) and "singleX" or "singleZ"
		deepPool(parent,center,120,120,bridgeMode)
		addDivingPlatforms(parent,center,gx,gz,kind,bridgeMode)
		normalCeiling(parent,lights,center,false)
		if (gx+gz)%2==0 then
			poolRail(parent,center+Vector3.new(0,0,-61),true,68)
		else
			poolRail(parent,center+Vector3.new(-61,0,0),false,68)
		end
	elseif kind=="split" then
		deepPool(parent,center,120,120,"offset")
		tiledColumn(parent,center+Vector3.new(-48,0,-48),7,20)
		tiledColumn(parent,center+Vector3.new(48,0,48),7,20)
		normalCeiling(parent,lights,center,false)
	elseif kind=="pillars" then
		deepPool(parent,center,120,120,"cross")
		addDivingPlatforms(parent,center,gx,gz,kind,"cross")
		for _,off in ipairs({
			Vector3.new(-49,0,-49),Vector3.new(49,0,-49),
			Vector3.new(-49,0,49),Vector3.new(49,0,49),
		}) do tiledColumn(parent,center+off,6.5,24) end
		normalCeiling(parent,lights,center,false)
	elseif kind=="sun" then
		deepPool(parent,center,120,120,"cross")
		addDivingPlatforms(parent,center,gx,gz,kind,"cross")
		tiledColumn(parent,center+Vector3.new(-48,0,0),8,26)
		tiledColumn(parent,center+Vector3.new(48,0,0),8,26)
		openSkyCeiling(parent,lights,center,104)
	elseif kind=="steps" then
		deepPool(parent,center,116,116,"singleZ")
		for i=0,4 do
			local stepY=-i*.9
			local stepPos=center+Vector3.new(-39+i*8,stepY,-42)
			tiledSlab(parent,"PoolStep",CFrame.new(stepPos),
				Vector3.new(12,.12,24),C.tile,13)
			local supportHeight=stepY+45
			tiledPart(parent,"PoolStepSupport",CFrame.new(center+Vector3.new(-39+i*8,(stepY-45)*.5,-42)),
				Vector3.new(7,supportHeight,16),C.tile,nil,13)
		end
		normalCeiling(parent,lights,center,true)
	end
	return kind
end

local function basin(parent, center, width, depth)
	local lip = 14
	for _, d in ipairs({
		{Vector3.new(0,.55,-depth/2+lip/2),Vector3.new(width,1.1,lip)},
		{Vector3.new(0,.55,depth/2-lip/2),Vector3.new(width,1.1,lip)},
		{Vector3.new(-width/2+lip/2,.55,0),Vector3.new(lip,1.1,depth-lip*2)},
		{Vector3.new(width/2-lip/2,.55,0),Vector3.new(lip,1.1,depth-lip*2)},
	}) do tiledPart(parent,"DryPoolLedge",CFrame.new(center+d[1]),d[2],C.tile,nil,16) end
	local base = part(parent,"BasinBlueGrout",CFrame.new(center+Vector3.new(0,.08,0)),
		Vector3.new(width-lip*2,.16,depth-lip*2),C.groutBlue)
	local basinFloor = tiledPart(parent,"ShallowDryBasin",CFrame.new(center+Vector3.new(0,.18,0)),
		Vector3.new(width-lip*2-.6,.12,depth-lip*2-.6),C.tileBlue,{Enum.NormalId.Top},17)
	base.CanCollide = true
	basinFloor:SetAttribute("DryPoolBasin",true)
end

local function wallWithDoor(parent, center, horizontal, totalLength, seed)
	local door, offset = 36, ((seed%3)-1)*38
	local a = math.max(18,(totalLength-door)*.5+offset)
	local b = totalLength-door-a
	if b<18 then b,a=18,totalLength-door-18 end
	local axis = horizontal and Vector3.xAxis or Vector3.zAxis
	local sa = horizontal and Vector3.new(a,WALL_H,2) or Vector3.new(2,WALL_H,a)
	local sb = horizontal and Vector3.new(b,WALL_H,2) or Vector3.new(2,WALL_H,b)
	tiledPart(parent,"PoolMazeWall",CFrame.new(center-axis*(totalLength*.5-a*.5)+Vector3.new(0,WALL_H*.5,0)),sa,C.tile,nil,16)
	tiledPart(parent,"PoolMazeWall",CFrame.new(center+axis*(totalLength*.5-b*.5)+Vector3.new(0,WALL_H*.5,0)),sb,C.tile,nil,16)
end

local function ceilingCell(parent, lights, center, opening)
	if not opening then
		tiledPart(parent,"PoolCeiling",CFrame.new(center+Vector3.new(0,WALL_H+.6,0)),Vector3.new(ROOM,1.2,ROOM),C.tile,nil,18)
		return
	end
	local gap = opening
	local border = (ROOM-gap)*.5
	for _,d in ipairs({
		{Vector3.new(0,WALL_H+.6,-(gap+border)*.5),Vector3.new(ROOM,1.2,border)},
		{Vector3.new(0,WALL_H+.6,(gap+border)*.5),Vector3.new(ROOM,1.2,border)},
		{Vector3.new(-(gap+border)*.5,WALL_H+.6,0),Vector3.new(border,1.2,gap)},
		{Vector3.new((gap+border)*.5,WALL_H+.6,0),Vector3.new(border,1.2,gap)},
	}) do tiledPart(parent,"CeilingCutoutBorder",CFrame.new(center+d[1]),d[2],C.tile,nil,18) end
	local sky = part(parent,"ImpossibleBlueSky",CFrame.new(center+Vector3.new(0,WALL_H+8,0)),
		Vector3.new(gap,1,gap),C.sky,Enum.Material.Neon)
	sky.CanCollide = false
	local glow = Instance.new("SurfaceLight")
	glow.Face,glow.Color,glow.Brightness,glow.Range,glow.Angle,glow.Shadows,glow.Parent =
		Enum.NormalId.Bottom,C.sky,1.1,50,150,false,sky
	for _,d in ipairs({
		{Vector3.new(0,WALL_H+1,-gap*.5),Vector3.new(gap,.8,.8)},
		{Vector3.new(0,WALL_H+1,gap*.5),Vector3.new(gap,.8,.8)},
		{Vector3.new(-gap*.5,WALL_H+1,0),Vector3.new(.8,.8,gap)},
		{Vector3.new(gap*.5,WALL_H+1,0),Vector3.new(.8,.8,gap)},
	}) do part(lights,"SkyCutoutFrame",CFrame.new(center+d[1]),d[2],C.groutBlue,Enum.Material.Metal) end
end

local function makeArrival(position)
	local model = Instance.new("Model")
	model.Name, model.Parent = "Elevator", workspace -- compatibility name; this is not an elevator
	local floor = tiledPart(model,"ArrivalFloor",CFrame.new(position+Vector3.new(0,.3,0)),Vector3.new(30,.6,24),C.tile,nil,16)
	model.PrimaryPart = floor
	for _,d in ipairs({
		{Vector3.new(-14.5,7,0),Vector3.new(1,14,24)},
		{Vector3.new(0,7,-11.5),Vector3.new(30,14,1)},
		{Vector3.new(0,14,0),Vector3.new(30,1,24)},
	}) do tiledPart(model,"ArrivalWall",CFrame.new(position+d[1]),d[2],C.tile,nil,16) end
	local header = part(model,"ArrivalHeader",CFrame.new(position+Vector3.new(14.6,11,0)),Vector3.new(.8,4,24),C.dark,Enum.Material.Metal)
	label(header,Enum.NormalId.Right,"POOL ACCESS","FILTRATION SECTOR 02",C.blue)
	-- Arrival is intentionally environmental: no entity/valve instruction board here.
	-- Invisible compatibility doors keep the shared round manager happy without
	-- visually or physically turning this Poolrooms arrival bay into an elevator.
	local doorL = part(model,"DoorL",CFrame.new(position+Vector3.new(14.5,5,-5)),Vector3.new(.2,10,10),C.tile,Enum.Material.SmoothPlastic,1)
	local doorR = part(model,"DoorR",CFrame.new(position+Vector3.new(14.5,5,5)),Vector3.new(.2,10,10),C.tile,Enum.Material.SmoothPlastic,1)
	doorL.CanCollide, doorR.CanCollide = false, false
	local ramp = tiledPart(model,"ArrivalRamp",CFrame.new(position+Vector3.new(18,.2,0)),Vector3.new(8,.4,20),C.tile,nil,16)
	local start = part(workspace,"MazeStart",CFrame.new(position+Vector3.new(27,2.5,0)),Vector3.new(4,1,4),C.green,Enum.Material.Neon,1)
	start.CanCollide=false
	local spawn = part(workspace,"ElevatorSpawn",CFrame.new(position+Vector3.new(0,1.25,0)),Vector3.new(18,1,14),C.green,Enum.Material.Neon,1)
	spawn.CanCollide=true
end

local HOSTILE_TAG = "Level2HostileEntity"
local LEVEL2_ENTITY_SCRIPT_NAMES = {
	"Level2EntityAI",
	"Level2EntityAnimation",
	"Level2EntityKill",
	"Level2EntityAudio",
	"Level2HostileEntityController",
	"Level2PipeEntityController",
}

local function entityMarker(parent, name, position, size, markerType)
	local marker = part(parent, name, CFrame.new(position), size or Vector3.new(2, .2, 2), C.red, Enum.Material.SmoothPlastic, 1)
	marker.CanCollide = false
	marker.CanTouch = false
	marker.CanQuery = false
	marker.CastShadow = false
	marker:SetAttribute("MarkerType", markerType or "EntityMarker")
	return marker
end

local function entityNodeFolder(markers, name, profile, positions, markerType)
	local folder = Instance.new("Folder")
	folder.Name = name
	folder.Parent = markers
	folder:SetAttribute("EntityProfile", profile)
	for index, position in ipairs(positions) do
		local node = entityMarker(folder, string.format("%s%02d", name:gsub("Nodes$", "Node"), index), position, Vector3.new(1.5, .2, 1.5), markerType)
		node:SetAttribute("NodeIndex", index)
	end
	return folder
end

local function createLevel2EntityMarkers(entities, buildGeneration)
	local markers = Instance.new("Folder")
	markers.Name = "Markers"
	markers.Parent = entities
	markers:SetAttribute("BuildGeneration", buildGeneration)

	local foamBoundsMin = Vector3.new(304, -2, -172)
	local foamBoundsMax = Vector3.new(384, 24, 130)
	local foamStart = entityMarker(markers, "PoolFoamStart", Vector3.new(340, -.08, -90), Vector3.new(2, .2, 2), "Spawn")
	foamStart:SetAttribute("EntityProfile", "PoolFoam")
	local foamZone = entityMarker(markers, "PoolFoamWanderZone", Vector3.new(344, .15, -21), Vector3.new(80, .3, 302), "WanderZone")
	foamZone:SetAttribute("EntityProfile", "PoolFoam")
	foamZone:SetAttribute("WanderBoundsMin", foamBoundsMin)
	foamZone:SetAttribute("WanderBoundsMax", foamBoundsMax)
	foamZone:SetAttribute("AreaName", "Valve3District")
	entityNodeFolder(markers, "PoolFoamWanderNodes", "PoolFoam", {
		Vector3.new(331, -.08, -160),
		Vector3.new(355, -.08, -145),
		Vector3.new(340, -.08, -90),
		Vector3.new(365, -.08, -40),
		Vector3.new(335, -.08, 8),
		Vector3.new(360, -.08, 55),
		Vector3.new(330, -.08, 105),
	}, "WanderNode")

	-- Pool Pipe begins on the connected south perimeter of the huge slide hall,
	-- never on the isolated Sunken Gallery island.  Its route follows the full
	-- perimeter plus both central bridges so it can leave the spawn point and hunt.
	local pipeBoundsMin = Vector3.new(-124, -8, -202)
	local pipeBoundsMax = Vector3.new(124, 76, 10)
	local pipeStart = entityMarker(markers, "PoolPipeStart", Vector3.new(-104, 1.15, -5), Vector3.new(2, .2, 2), "Spawn")
	pipeStart:SetAttribute("EntityProfile", "PoolPipe")
	local pipeZone = entityMarker(markers, "PoolPipeWanderZone", Vector3.new(0, 1.15, -96), Vector3.new(248, .3, 212), "WanderZone")
	pipeZone:SetAttribute("EntityProfile", "PoolPipe")
	pipeZone:SetAttribute("WanderBoundsMin", pipeBoundsMin)
	pipeZone:SetAttribute("WanderBoundsMax", pipeBoundsMax)
	pipeZone:SetAttribute("AreaName", "GrandPoolSlideHall")
	entityNodeFolder(markers, "PoolPipeWanderNodes", "PoolPipe", {
		Vector3.new(-104, 1.15, -5),
		Vector3.new(-55, 1.15, -5),
		Vector3.new(0, 1.15, -5),
		Vector3.new(55, 1.15, -5),
		Vector3.new(104, 1.15, -5),
		Vector3.new(118, 1.15, -50),
		Vector3.new(118, 1.15, -100),
		Vector3.new(118, 1.15, -150),
		Vector3.new(104, 1.15, -195),
		Vector3.new(50, 1.15, -195),
		Vector3.new(0, 1.15, -195),
		Vector3.new(-50, 1.15, -195),
		Vector3.new(-104, 1.15, -195),
		Vector3.new(-118, 1.15, -150),
		Vector3.new(-118, 1.15, -100),
		Vector3.new(-118, 1.15, -50),
		Vector3.new(-72, 1.15, -100),
		Vector3.new(0, 1.15, -100),
		Vector3.new(72, 1.15, -100),
	}, "WanderNode")
	entityNodeFolder(markers, "PoolPipeRecoveryNodes", "PoolPipe", {
		Vector3.new(-104, 1.15, -5),
		Vector3.new(104, 1.15, -5),
		Vector3.new(118, 1.15, -195),
		Vector3.new(-118, 1.15, -195),
		Vector3.new(-118, 1.15, -100),
		Vector3.new(118, 1.15, -100),
		Vector3.new(0, 1.15, -100),
	}, "RecoveryNode")

	-- Retain the shared round manager's legacy marker without using it as an
	-- entity parent or movement profile.
	local legacyStart = entityMarker(workspace, "EntityStart", Vector3.new(340, 2.5, -90), Vector3.new(4, 1, 4), "CompatibilitySpawn")
	legacyStart:SetAttribute("CompatibilityOnly", true)
	legacyStart:SetAttribute("BuildGeneration", buildGeneration)

	return markers
end

local function spawnLevel2Hostile(entities, markers, spec)
	local assets = ServerStorage:FindFirstChild("Level2Assets")
	local template = assets and assets:FindFirstChild(spec.templateName)
	local start = markers:FindFirstChild(spec.startMarker, true)
	if not template then
		warn(string.format("[Level2] %s is missing; %s marker/profile hooks remain ready", spec.templateName, spec.entityName))
		return nil
	end
	if not start or not start:IsA("BasePart") then
		warn(string.format("[Level2] %s start marker is missing", spec.entityName))
		return nil
	end

	local clone = template:Clone()
	local entity
	if clone:IsA("Model") then
		entity = clone
	else
		entity = Instance.new("Model")
		clone.Parent = entity
	end
	entity.Name = spec.entityName
	entity.Parent = entities

	local root = entity.PrimaryPart
	if not root then
		for _, rootName in ipairs(spec.rootNames or {}) do
			local candidate = entity:FindFirstChild(rootName, true)
			if candidate and candidate:IsA("BasePart") then
				root = candidate
				break
			end
		end
	end
	root = root or entity:FindFirstChild("HumanoidRootPart", true) or entity:FindFirstChildWhichIsA("BasePart", true)
	if not root then
		entity:Destroy()
		warn(string.format("[Level2] %s has no root part", spec.entityName))
		return nil
	end
	entity.PrimaryPart = root

	for _, object in ipairs(entity:GetDescendants()) do
		if object:IsA("BasePart") then
			object.Anchored = true
			object.CanCollide = false
			object.CanTouch = false
			object.CanQuery = true
			object.Massless = true
		end
	end

	local pivot = entity:GetPivot()
	local boundsCF, boundsSize = entity:GetBoundingBox()
	local bottomToPivot = pivot.Position.Y - (boundsCF.Position.Y - boundsSize.Y * .5)
	entity:PivotTo(start.CFrame * CFrame.new(0, bottomToPivot + .05, 0))
	entity:SetAttribute("MotionState", "Idle")
	entity:SetAttribute("MoveSpeed", 0)
	entity:SetAttribute("EntityProfile", spec.profile)
	entity:SetAttribute("Profile", spec.profile)
	entity:SetAttribute("Level2Hostile", true)
	entity:SetAttribute("BuildGeneration", entities:GetAttribute("BuildGeneration"))
	entity:SetAttribute("SpawnMarker", spec.startMarker)
	entity:SetAttribute("SpawnMarkerPath", start:GetFullName())
	entity:SetAttribute("WanderZone", spec.wanderZone)
	entity:SetAttribute("WanderNodesFolder", spec.wanderNodes)
	entity:SetAttribute("RecoveryNodesFolder", spec.recoveryNodes or spec.wanderNodes)
	entity:SetAttribute("WanderBoundsMin", spec.boundsMin)
	entity:SetAttribute("WanderBoundsMax", spec.boundsMax)
	for attribute, value in pairs(spec.attributes or {}) do
		entity:SetAttribute(attribute, value)
	end
	CollectionService:AddTag(entity, HOSTILE_TAG)
	return entity
end

local function spawnLevel2Hostiles(entities, markers)
	local foam = spawnLevel2Hostile(entities, markers, {
		templateName = "PoolFoamEntityTemplate",
		entityName = "PoolFoamEntity",
		profile = "PoolFoam",
		startMarker = "PoolFoamStart",
		wanderZone = "PoolFoamWanderZone",
		wanderNodes = "PoolFoamWanderNodes",
		boundsMin = Vector3.new(304, -2, -172),
		boundsMax = Vector3.new(384, 24, 130),
		rootNames = {"char1"},
		attributes = {
			AllowedArea = "Valve3District",
			WadesInShallowWater = true,
			ShallowWaterDepth = .8,
		},
	})
	local pipe = spawnLevel2Hostile(entities, markers, {
		templateName = "PoolPipeEntityTemplate",
		entityName = "PoolPipeEntity",
		profile = "PoolPipe",
		startMarker = "PoolPipeStart",
		wanderZone = "PoolPipeWanderZone",
		wanderNodes = "PoolPipeWanderNodes",
		recoveryNodes = "PoolPipeRecoveryNodes",
		boundsMin = Vector3.new(-124, -8, -202),
		boundsMax = Vector3.new(124, 76, 10),
		rootNames = {"HumanoidRootPart", "Root", "root"},
		attributes = {
			HomeArea = "GrandPoolSlideHall",
			BlackoutHunter = true,
		},
	})
	return foam, pipe
end

local function wallValve(parent, position, normal, color, number, onActivated)
	local model=Instance.new("Model")
	model.Name="PressureValve"..number
	model.Parent=parent
	model:SetAttribute("VisionColor",color)
	model:SetAttribute("ValveState","OFFLINE")
	model:SetAttribute("AnimationStyle","TweenedChromeHandwheel")

	local up=Vector3.yAxis
	local right=normal:Cross(up).Unit
	local chromeDark=Color3.fromRGB(57,66,69)
	local chromeMid=Color3.fromRGB(132,143,147)
	local chrome=Color3.fromRGB(198,207,209)
	local chromeBright=Color3.fromRGB(229,234,235)
	local gasketColor=Color3.fromRGB(24,29,30)

	local function finishMetal(object,reflectance,canCollide)
		object.Reflectance=reflectance or .2
		object.CanCollide=canCollide==true
		object.CanTouch=false
		object.CanQuery=false
		return object
	end

	local function disc(container,name,centerPoint,diameter,depth,tone,material,reflectance)
		local object=part(container,name,
			CFrame.fromMatrix(centerPoint,normal,up,right),
			Vector3.new(depth,diameter,diameter),
			tone,material or Enum.Material.Metal)
		object.Shape=Enum.PartType.Cylinder
		return finishMetal(object,reflectance,false)
	end

	local function cylinderBetween(container,name,a,b,diameter,tone,material,reflectance)
		local delta=b-a
		local axis=delta.Unit
		local object=part(container,name,
			CFrame.fromMatrix((a+b)*.5,axis,normal,axis:Cross(normal)),
			Vector3.new(delta.Magnitude,diameter,diameter),
			tone,material or Enum.Material.Metal)
		object.Shape=Enum.PartType.Cylinder
		return finishMetal(object,reflectance,false)
	end

	local function polishedBall(container,name,centerPoint,diameter,tone,reflectance)
		local object=part(container,name,CFrame.new(centerPoint),
			Vector3.new(diameter,diameter,diameter),tone,Enum.Material.Metal)
		object.Shape=Enum.PartType.Ball
		return finishMetal(object,reflectance,false)
	end

	-- Layered circular flange: dark rubber seal, stepped chrome bevels, and
	-- a textured metal inset read like real pool filtration hardware.
	disc(model,"ValveWallGasket",position+normal*.08,6.45,.18,gasketColor,Enum.Material.Rubber,0)
	disc(model,"ValveRearFlange",position+normal*.36,6.15,.58,chromeDark,Enum.Material.Metal,.18)
	disc(model,"ValveOuterBevel",position+normal*.67,5.82,.18,chromeMid,Enum.Material.Metal,.3)
	disc(model,"ValveFacePlate",position+normal*.80,5.34,.14,chrome,Enum.Material.Metal,.4)
	disc(model,"ValveBonnetRecess",position+normal*.90,3.15,.10,chromeDark,Enum.Material.DiamondPlate,.16)

	for index=0,7 do
		local angle=index*math.pi/4
		local radial=right*math.cos(angle)+up*math.sin(angle)
		disc(model,"ValveBoltWasher",position+radial*2.42+normal*.91,.44,.06,
			gasketColor,Enum.Material.Metal,.08)
		disc(model,"ValveFlangeBolt",position+radial*2.42+normal*.99,.32,.16,
			index%2==0 and chromeBright or chrome,Enum.Material.Metal,.48)
	end

	disc(model,"ValveBonnet",position+normal*1.28,1.86,1.0,
		Color3.fromRGB(83,94,97),Enum.Material.Metal,.23)
	disc(model,"ValveBonnetCollar",position+normal*1.72,2.05,.24,
		chrome,Enum.Material.Metal,.43)
	cylinderBetween(model,"ValveStem",position+normal*1.72,position+normal*2.18,.34,
		chromeBright,Enum.Material.Metal,.5)

	local wheelCenter=position+normal*2.23
	local rotorFrame=CFrame.fromMatrix(wheelCenter,right,up,-normal)
	local rotor=Instance.new("Model")
	rotor.Name="ValveRotor"
	rotor.Parent=model
	local pivot=part(rotor,"RotorPivot",rotorFrame,Vector3.new(.05,.05,.05),
		chrome,Enum.Material.SmoothPlastic,1)
	pivot.CanCollide=false
	pivot.CanTouch=false
	pivot.CanQuery=false
	pivot.CastShadow=false
	rotor.PrimaryPart=pivot

	local wheelRadius=2.3
	local wheelSegments=20
	for index=0,wheelSegments-1 do
		local a=index*math.pi*2/wheelSegments
		local b=(index+1)*math.pi*2/wheelSegments
		local p1=wheelCenter+right*(math.cos(a)*wheelRadius)+up*(math.sin(a)*wheelRadius)
		local p2=wheelCenter+right*(math.cos(b)*wheelRadius)+up*(math.sin(b)*wheelRadius)
		cylinderBetween(rotor,"ChromeWheelRim",p1,p2,.36,
			index%5==0 and chromeBright or chrome,Enum.Material.Metal,index%5==0 and .48 or .36)
	end
	for index=0,4 do
		local angle=index*math.pi*2/5
		local radial=right*math.cos(angle)+up*math.sin(angle)
		cylinderBetween(rotor,"ChromeWheelSpoke",
			wheelCenter+radial*.46,wheelCenter+radial*2.12,.25,
			chrome,Enum.Material.Metal,.38)
	end
	disc(rotor,"ChromeWheelHub",wheelCenter,1.12,.54,
		chromeBright,Enum.Material.Metal,.46)
	local hubCap=disc(rotor,"ChromeWheelHubCap",wheelCenter+normal*.35,.69,.18,
		chromeDark,Enum.Material.Metal,.28)

	local spinnerAngle=math.rad(-35)
	local spinnerRadial=right*math.cos(spinnerAngle)+up*math.sin(spinnerAngle)
	local spinnerBase=wheelCenter+spinnerRadial*1.72
	cylinderBetween(rotor,"ChromeSpinnerStem",
		spinnerBase+normal*.08,spinnerBase+normal*.78,.28,
		chromeBright,Enum.Material.Metal,.5)
	cylinderBetween(rotor,"SpinnerGrip",
		spinnerBase+normal*.70,spinnerBase+normal*1.32,.48,
		Color3.fromRGB(36,42,43),Enum.Material.Rubber,.02)
	local spinnerCap=disc(rotor,"ValveColorKey",
		spinnerBase+normal*1.37,.40,.12,color,Enum.Material.Metal,.25)

	local indicatorRadial=right*1.82+up*1.86
	local indicatorLens=disc(model,"ValveIndicatorLens",
		position+indicatorRadial+normal*1.05,.48,.18,
		color:Lerp(gasketColor,.58),Enum.Material.Glass,.08)
	indicatorLens.Transparency=.08
	local glow=Instance.new("PointLight")
	glow.Color=color
	glow.Brightness=.12
	glow.Range=7
	glow.Shadows=false
	glow.Parent=indicatorLens

	local signCenter=position+up*4.15+normal*.40
	local signFrame=part(model,"ValveStatusBezel",
		CFrame.lookAt(signCenter,signCenter+normal,up),
		Vector3.new(5.9,1.65,.34),chrome,Enum.Material.Metal)
	finishMetal(signFrame,.38,false)
	local sign=part(model,"ValveStatus",
		CFrame.lookAt(signCenter+normal*.20,signCenter+normal,up),
		Vector3.new(5.38,1.22,.16),C.dark,Enum.Material.SmoothPlastic)
	finishMetal(sign,.04,false)
	for _,horizontal in ipairs({-1,1}) do
		for _,vertical in ipairs({-.52,.52}) do
			polishedBall(model,"ValveStatusScrew",
				signCenter+right*(horizontal*2.73)+up*vertical+normal*.23,
				.17,chromeBright,.5)
		end
	end
	local title,sub=label(sign,Enum.NormalId.Front,"VALVE "..number,"OFFLINE",color)

	local prompt=Instance.new("ProximityPrompt")
	prompt.ActionText="TURN VALVE"
	prompt.ObjectText="FILTRATION LINE "..number
	prompt.HoldDuration=1.1
	prompt.MaxActivationDistance=10
	prompt.RequiresLineOfSight=false
	prompt.Parent=hubCap

	local targetAngle=-math.rad(540)
	local angleDriver=Instance.new("NumberValue")
	angleDriver.Name="MechanicalTurnAngle"
	angleDriver.Value=0
	angleDriver.Parent=model
	local angleConnection=angleDriver:GetPropertyChangedSignal("Value"):Connect(function()
		if not rotor.Parent then return end
		local progress=math.clamp(math.abs(angleDriver.Value)/math.abs(targetAngle),0,1)
		local stemLift=.16*progress
		rotor:PivotTo(rotorFrame
			*CFrame.new(0,0,-stemLift)
			*CFrame.Angles(0,0,angleDriver.Value))
	end)

	local callbackFired=false
	local turnTween
	local function finishActivation(player)
		if callbackFired or not model.Parent then return end
		callbackFired=true
		angleDriver.Value=targetAngle
		if angleConnection then angleConnection:Disconnect() end
		model:SetAttribute("ValveState","ACTIVE")
		title.Text="VALVE "..number.." ACTIVE"
		sub.Text="PRESSURE RESTORED"
		indicatorLens.Material=Enum.Material.Neon
		indicatorLens.Color=color
		spinnerCap.Color=color:Lerp(Color3.new(1,1,1),.12)
		glow.Brightness=1.7
		glow.Range=11
		onActivated(player,number)
	end

	prompt.Triggered:Connect(function(player)
		if model:GetAttribute("Activated") then return end
		model:SetAttribute("Activated",true)
		model:SetAttribute("ValveState","TURNING")
		prompt.Enabled=false
		sub.Text="TURNING  /  RELEASING PRESSURE"
		glow.Brightness=.55
		task.spawn(function()
			turnTween=TweenService:Create(angleDriver,
				TweenInfo.new(1.65,Enum.EasingStyle.Quart,Enum.EasingDirection.InOut),
				{Value=targetAngle})
			turnTween:Play()
			local playbackState=turnTween.Completed:Wait()
			if playbackState==Enum.PlaybackState.Completed then
				finishActivation(player)
			end
		end)
		task.delay(2.4,function()
			if callbackFired or not model.Parent then return end
			if turnTween then turnTween:Cancel() end
			finishActivation(player)
		end)
	end)
	return model
end

local function exitTube(parent, position)
	local model=Instance.new("Model"); model.Name="ExitTube"; model.Parent=parent
	model:SetAttribute("PlayableSlide",true)
	model:SetAttribute("DecorativePoolSlide",false)
	model:SetAttribute("WallIntegrated",true)
	local slideGreen=Color3.fromRGB(20,170,112)
	local slideLight=Color3.fromRGB(92,226,166)
	local slideDark=Color3.fromRGB(5,49,37)
	local warmTile=Color3.fromRGB(218,226,210)
	local waterColor=Color3.fromRGB(70,205,197)
	local black=Color3.fromRGB(0,0,0)
	local radius,segments=4.75,24
	local wallX=position.X+78
	local centerZ=position.Z
	local mouth=Vector3.new(wallX-.35,6.05,centerZ)

	-- Replace the solid east wall with tiled sections that leave one real circular opening.
	local world=parent.Parent
	local oldWall=world and world:FindFirstChild("ExitChamberEastWall",true)
	if oldWall and oldWall:IsA("BasePart") then
		oldWall.Transparency=1
		oldWall.CanCollide=false
	end
	local oldScreen=world and world:FindFirstChild("ExitChamberScreen",true)
	if oldScreen and oldScreen:IsA("BasePart") then
		oldScreen.Transparency=1
		oldScreen.CanCollide=false
	end
	tiledPart(model,"ExitWallNorth",CFrame.new(wallX,11,centerZ-28),
		Vector3.new(1,26,44),warmTile,nil,10)
	tiledPart(model,"ExitWallSouth",CFrame.new(wallX,11,centerZ+28),
		Vector3.new(1,26,44),warmTile,nil,10)
	tiledPart(model,"ExitWallHeader",CFrame.new(wallX,18.05,centerZ),
		Vector3.new(1,11.9,12),warmTile,nil,10)
	tiledPart(model,"ExitWallLowerNorth",CFrame.new(wallX,1.1,centerZ-7.7),
		Vector3.new(1,4.2,3.4),warmTile,nil,10)
	tiledPart(model,"ExitWallLowerSouth",CFrame.new(wallX,1.1,centerZ+7.7),
		Vector3.new(1,4.2,3.4),warmTile,nil,10)

	-- A small shallow holding basin for the bather ring, inspired by real slide stations.
	local basinCenter=Vector3.new(wallX-31.5,.28,centerZ)
	local basinBottom=tiledPart(model,"RingBasinFloor",CFrame.new(basinCenter),
		Vector3.new(27,.34,23),Color3.fromRGB(181,224,218),{Enum.NormalId.Top},8)
	basinBottom.Reflectance=.05
	local basinWater=part(model,"RingBasinWater",CFrame.new(basinCenter+Vector3.new(0,.62,0)),
		Vector3.new(25.6,1.05,21.6),waterColor,Enum.Material.Glass,.34)
	basinWater.CanCollide=false
	basinWater.CastShadow=false
	for _,zOffset in ipairs({-12.1,12.1}) do
		local coping=tiledPart(model,"RingBasinCoping",CFrame.new(basinCenter+Vector3.new(0,1.02,zOffset)),
			Vector3.new(29,1.7,1.25),warmTile,nil,7)
		coping.Reflectance=.06
	end
	local frontCoping=tiledPart(model,"RingBasinFrontCoping",
		CFrame.new(basinCenter+Vector3.new(-14.1,1.02,0)),Vector3.new(1.25,1.7,25.4),warmTile,nil,7)
	frontCoping.Reflectance=.06

	-- This raised tiled weir visibly stops the basin water before the dry slide entrance.
	local waterStopX=wallX-17.2
	local waterStop=tiledPart(model,"DryWaterStopLedge",CFrame.new(waterStopX,1.3,centerZ),
		Vector3.new(1.7,2.6,25.4),warmTile,nil,7)
	waterStop.Reflectance=.07
	local step=tiledPart(model,"BoardingStep",CFrame.new(wallX-15.2,1.05,centerZ),
		Vector3.new(2.4,2.1,13),warmTile,nil,7)
	local dryDeck=tiledPart(model,"DryBoardingDeck",CFrame.new(wallX-8.1,1.6,centerZ),
		Vector3.new(12.2,3.2,13),warmTile,nil,7)
	step.Reflectance=.06
	dryDeck.Reflectance=.06
	for _,zOffset in ipairs({-6.35,6.35}) do
		local trim=part(model,"BoardingDeckGreenTrim",CFrame.new(wallX-8.1,3.25,centerZ+zOffset),
			Vector3.new(12.4,.18,.28),slideGreen,Enum.Material.SmoothPlastic)
		trim.Reflectance=.18
	end

	-- Only the glossy green mouth is exposed to the room; the tube itself is behind the wall.
	local arcWidth=(math.pi*2*(radius+.28)/segments)+.08
	local rimLight
	for i=0,segments-1 do
		local a=(i+.5)*math.pi*2/segments
		local cf=CFrame.new(mouth)*CFrame.Angles(a,0,0)*CFrame.new(0,radius+.28,0)
		local shade=(i%4==0) and slideLight or slideGreen
		local rim=part(model,"WallSlideEntranceLip",cf,Vector3.new(1.05,.42,arcWidth),
			shade,Enum.Material.SmoothPlastic)
		rim.Reflectance=.24
		if not rimLight then
			rimLight=Instance.new("PointLight")
			rimLight.Color,rimLight.Brightness,rimLight.Range,rimLight.Parent=
				slideLight,.8,16,rim
		end
	end
	local throat=part(model,"DarkSlideThroat",CFrame.new(wallX+.28,mouth.Y,centerZ),
		Vector3.new(1.6,radius*1.84,radius*1.84),slideDark,Enum.Material.SmoothPlastic)
	throat.Shape=Enum.PartType.Cylinder
	throat.Reflectance=.08
	throat.CanCollide=false

	-- The green seal preserves the existing three-valve unlock contract.
	local portal=part(model,"ExitPlasma",CFrame.new(wallX+.7,mouth.Y,centerZ),
		Vector3.new(.55,radius*1.7,radius*1.7),slideDark,Enum.Material.SmoothPlastic,0)
	portal.Shape=Enum.PartType.Cylinder
	portal.Reflectance=.12
	portal.CanCollide=true
	local light=Instance.new("PointLight")
	light.Color,light.Brightness,light.Range,light.Parent=C.green,0,30,portal

	-- A hidden moulded tube descends behind the wall, then becomes steep enough to drop the rider.
	local path={
		Vector3.new(wallX+.8,mouth.Y,centerZ),
		Vector3.new(wallX+6.2,mouth.Y-.35,centerZ),
		Vector3.new(wallX+11.2,mouth.Y-2.0,centerZ),
		Vector3.new(wallX+16.1,mouth.Y-6.1,centerZ),
		Vector3.new(wallX+21.2,mouth.Y-13.6,centerZ),
		Vector3.new(wallX+25.5,mouth.Y-22.0,centerZ),
	}
	local tubeRadius=4.35
	local tubeArc=(math.pi*2*tubeRadius/segments)+.1
	for segmentIndex=1,#path-1 do
		local aPos,bPos=path[segmentIndex],path[segmentIndex+1]
		local length=(bPos-aPos).Magnitude
		local frame=CFrame.lookAt((aPos+bPos)*.5,bPos)
		for i=0,segments-1 do
			local angle=(i+.5)*math.pi*2/segments
			-- The last drop has an open lower quarter, so the rider genuinely begins to fall.
			local isOpenDrop=segmentIndex==#path-1 and math.sin(angle)<-.15
			if not isOpenDrop then
				local shellCf=frame*CFrame.Angles(0,0,angle)*CFrame.new(0,tubeRadius,0)
				local shade=(i%5==0) and slideLight:Lerp(slideGreen,.35) or slideGreen
				local panel=part(model,"HiddenGlossySlideShell",shellCf,
					Vector3.new(tubeArc,.38,length+.25),shade,Enum.Material.SmoothPlastic)
				panel.Reflectance=.18
			end
		end
		if segmentIndex<#path-1 then
			local bed=part(model,"HiddenSlideBed",
				frame*CFrame.new(0,-tubeRadius+.38,0),
				Vector3.new(6.4,.5,length+.2),slideLight:Lerp(slideGreen,.45),Enum.Material.SmoothPlastic)
			bed.Reflectance=.2
		end
	end

	-- A pure black portal catches the brief fall and completes the level.
	local finalDirection=(path[#path]-path[#path-1]).Unit
	local finalFrame=CFrame.lookAt(path[#path],path[#path]+finalDirection)
	local blackPortal=part(model,"BlackCompletionPortal",
		finalFrame*CFrame.Angles(0,math.rad(90),0),
		Vector3.new(.7,tubeRadius*1.95,tubeRadius*1.95),black,Enum.Material.Neon,0)
	blackPortal.Shape=Enum.PartType.Cylinder
	blackPortal.CanCollide=false
	local portalHalo=Instance.new("PointLight")
	portalHalo.Color=Color3.fromRGB(13,46,38)
	portalHalo.Brightness=.45
	portalHalo.Range=12
	portalHalo.Parent=blackPortal
	local trigger=part(model,"ExitTrigger",
		finalFrame*CFrame.new(0,0,-.55),
		Vector3.new(tubeRadius*1.65,tubeRadius*1.65,2.2),black,Enum.Material.SmoothPlastic,1)
	trigger.CanCollide,trigger.CanTouch=false,false
	return {model=model,portal=portal,light=light,trigger=trigger}
end

local function triggerValveBlackout(world, lamps, onRecovered)
	local previousGeneration = world:GetAttribute("ValveBlackoutGeneration") or 0
	local generation = previousGeneration + 1
	world:SetAttribute("ValveBlackoutGeneration", generation)
	world:SetAttribute("ValveBlackoutActive", true)
	world:SetAttribute("ValveBlackoutEndsAt", workspace:GetServerTimeNow() + 30)
	world:SetAttribute("FiltrationAlarm", false)

	if world:GetAttribute("ValveOriginalBrightness") == nil then
		world:SetAttribute("ValveOriginalBrightness", Lighting.Brightness)
		world:SetAttribute("ValveOriginalAmbient", Lighting.Ambient)
		world:SetAttribute("ValveOriginalOutdoorAmbient", Lighting.OutdoorAmbient)
	end

	for _, object in ipairs(world:GetDescendants()) do
		if object:IsA("SurfaceLight") or object:IsA("PointLight") or object:IsA("SpotLight") then
			if object:GetAttribute("ValveOriginalBrightness") == nil then
				object:SetAttribute("ValveOriginalBrightness", object.Brightness)
				object:SetAttribute("ValveOriginalColor", object.Color)
				object:SetAttribute("ValveOriginalEnabled", object.Enabled)
			end
			object.Enabled = false
			object.Brightness = 0
		elseif object:IsA("BasePart") and object.Material == Enum.Material.Neon then
			if object:GetAttribute("ValveOriginalColor") == nil then
				object:SetAttribute("ValveOriginalColor", object.Color)
				object:SetAttribute("ValveOriginalMaterial", object.Material.Name)
			end
			object.Material = Enum.Material.SmoothPlastic
			object.Color = Color3.fromRGB(3, 5, 7)
		end
	end
	Lighting.Brightness = 0
	Lighting.Ambient = Color3.new(0, 0, 0)
	Lighting.OutdoorAmbient = Color3.new(0, 0, 0)

	task.spawn(function()
		task.wait(30)
		if not world.Parent or world:GetAttribute("ValveBlackoutGeneration") ~= generation then return end

		local originalBrightness = world:GetAttribute("ValveOriginalBrightness") or 1.8
		local originalAmbient = world:GetAttribute("ValveOriginalAmbient") or Color3.fromRGB(88, 92, 88)
		local originalOutdoor = world:GetAttribute("ValveOriginalOutdoorAmbient") or Color3.fromRGB(100, 102, 98)
		local rng = Random.new(generation * 7919)

		for pulse = 1, 22 do
			if not world.Parent or world:GetAttribute("ValveBlackoutGeneration") ~= generation then return end
			local progress = pulse / 22
			local onChance = .18 + progress * .78
			for _, object in ipairs(world:GetDescendants()) do
				if object:IsA("SurfaceLight") or object:IsA("PointLight") or object:IsA("SpotLight") then
					local isOn = rng:NextNumber() < onChance
					local brightness = object:GetAttribute("ValveOriginalBrightness") or 0
					object.Enabled = isOn
					object.Brightness = isOn and brightness or 0
					local color = object:GetAttribute("ValveOriginalColor")
					if color then object.Color = color end
				elseif object:IsA("BasePart") and object:GetAttribute("ValveOriginalMaterial") then
					local isOn = rng:NextNumber() < onChance
					local color = object:GetAttribute("ValveOriginalColor")
					object.Material = isOn and Enum.Material.Neon or Enum.Material.SmoothPlastic
					object.Color = isOn and (color or Color3.fromRGB(232,255,250)) or Color3.fromRGB(3,5,7)
				end
			end
			Lighting.Brightness = originalBrightness * (.08 + progress * .92)
			Lighting.Ambient = Color3.new(0,0,0):Lerp(originalAmbient, progress)
			Lighting.OutdoorAmbient = Color3.new(0,0,0):Lerp(originalOutdoor, progress)
			task.wait(rng:NextNumber(.16, .38))
		end

		if not world.Parent or world:GetAttribute("ValveBlackoutGeneration") ~= generation then return end
		for _, object in ipairs(world:GetDescendants()) do
			if object:IsA("SurfaceLight") or object:IsA("PointLight") or object:IsA("SpotLight") then
				local enabled = object:GetAttribute("ValveOriginalEnabled")
				if enabled == nil then enabled = true end
				object.Enabled = enabled
				object.Brightness = object:GetAttribute("ValveOriginalBrightness") or object.Brightness
				local color = object:GetAttribute("ValveOriginalColor")
				if color then object.Color = color end
			elseif object:IsA("BasePart") and object:GetAttribute("ValveOriginalMaterial") then
				local materialName = object:GetAttribute("ValveOriginalMaterial")
				object.Material = Enum.Material[materialName] or Enum.Material.Neon
				local color = object:GetAttribute("ValveOriginalColor")
				if color then object.Color = color end
			end
		end
		Lighting.Brightness = originalBrightness
		Lighting.Ambient = originalAmbient
		Lighting.OutdoorAmbient = originalOutdoor
		world:SetAttribute("ValveBlackoutActive", false)
		world:SetAttribute("ValveBlackoutEndsAt", nil)
		task.wait(1.2)
		if onRecovered and world.Parent and world:GetAttribute("ValveBlackoutGeneration") == generation then
			onRecovered()
		end
	end)
end

local function beginFiltrationAlarm(world, lamps)
	world:SetAttribute("FiltrationAlarm", true)
	local colors = {C.blue, C.red, C.yellow}
	task.spawn(function()
		local index = 1
		while world.Parent and world:GetAttribute("FiltrationAlarm") do
			local color = colors[index]
			index = index % #colors + 1
			for _, object in ipairs(lamps:GetDescendants()) do
				if object:IsA("SurfaceLight") or object:IsA("PointLight") then
					object.Color, object.Brightness = color, math.max(object.Brightness, 2.7)
				elseif object:IsA("BasePart") and object.Material == Enum.Material.Neon then
					object.Color = color
				end
			end
			Lighting.Ambient = color:Lerp(Color3.fromRGB(125, 135, 140), .58)
			task.wait(.32)
		end
	end)
end

local function buildReferencePoolrooms(parent, lamps)
    local terrain=workspace.Terrain
    local wallLightColor=Color3.fromRGB(255,250,226)
    local softTile=Color3.fromRGB(224,224,210)
    local function floorRect(name,cx,cz,w,d,y,color)
        return tiledSlab(parent,name,CFrame.new(cx,(y or 0)-.19,cz),Vector3.new(w,.5,d),color or C.tile,14)
    end
    local function ceilingRect(name,cx,cz,w,d,h,muted)
        return tiledPart(parent,name,CFrame.new(cx,h,cz),Vector3.new(w,.8,d),muted and softTile or C.tile,{Enum.NormalId.Bottom},15)
    end
    local function wallX(name,cx,cz,len,h,color)
        return tiledPart(parent,name,CFrame.new(cx,(h-2)*.5,cz),Vector3.new(len,h+2,1),color or C.tile,nil,15)
    end
    local function wallZ(name,cx,cz,len,h,color)
        return tiledPart(parent,name,CFrame.new(cx,(h-2)*.5,cz),Vector3.new(1,h+2,len),color or C.tile,nil,15)
    end
    local function gapWallX(name,cx,cz,len,h,gapX,gapW,color)
        if not gapX then wallX(name,cx,cz,len,h,color) return end
        local left,right=cx-len*.5,cx+len*.5
        local a,b=gapX-gapW*.5,gapX+gapW*.5
        if a-left>1 then wallX(name,left+(a-left)*.5,cz,a-left,h,color) end
        if right-b>1 then wallX(name,b+(right-b)*.5,cz,right-b,h,color) end
        if h>13 then tiledPart(parent,name.."Lintel",CFrame.new(gapX,(h+12)*.5,cz),Vector3.new(gapW,h-12,1),color or C.tile,nil,15) end
    end
    local function gapWallZ(name,cx,cz,len,h,gapZ,gapW,color)
        if not gapZ then wallZ(name,cx,cz,len,h,color) return end
        local low,high=cz-len*.5,cz+len*.5
        local a,b=gapZ-gapW*.5,gapZ+gapW*.5
        if a-low>1 then wallZ(name,cx,low+(a-low)*.5,a-low,h,color) end
        if high-b>1 then wallZ(name,cx,b+(high-b)*.5,high-b,h,color) end
        if h>13 then tiledPart(parent,name.."Lintel",CFrame.new(cx,(h+12)*.5,gapZ),Vector3.new(1,h-12,gapW),color or C.tile,nil,15) end
    end
    local function sealedPoolPerimeter(name,cx,cz,w,d)
        -- Real indoor pools always have a solid tiled apron between the water and
        -- the room shell. These overlapping slabs hide every world-void seam.
        local apron=6
        local deckY=.02
        local deckHeight=2.1
        tiledPart(parent,name.."NorthPerimeterDeck",
            CFrame.new(cx,deckY,cz-d*.5+apron*.5),Vector3.new(w,deckHeight,apron),C.tile,nil,12)
        tiledPart(parent,name.."SouthPerimeterDeck",
            CFrame.new(cx,deckY,cz+d*.5-apron*.5),Vector3.new(w,deckHeight,apron),C.tile,nil,12)
        if d>apron*2 then
            tiledPart(parent,name.."WestPerimeterDeck",
                CFrame.new(cx-w*.5+apron*.5,deckY,cz),Vector3.new(apron,deckHeight,d-apron*2),C.tile,nil,12)
            tiledPart(parent,name.."EastPerimeterDeck",
                CFrame.new(cx+w*.5-apron*.5,deckY,cz),Vector3.new(apron,deckHeight,d-apron*2),C.tile,nil,12)
        end

        -- Raised coping sits above the .7-stud waterline. Besides looking
        -- believable, it makes each pool read as a contained basin at doorways.
        local curbY,curbH,curbT=.55,1.25,.72
        local innerW=math.max(4,w-apron*2)
        local innerD=math.max(4,d-apron*2)
        tiledPart(parent,name.."NorthWaterCoping",
            CFrame.new(cx,curbY,cz-d*.5+apron),Vector3.new(innerW,curbH,curbT),C.tile,nil,9)
        tiledPart(parent,name.."SouthWaterCoping",
            CFrame.new(cx,curbY,cz+d*.5-apron),Vector3.new(innerW,curbH,curbT),C.tile,nil,9)
        tiledPart(parent,name.."WestWaterCoping",
            CFrame.new(cx-w*.5+apron,curbY,cz),Vector3.new(curbT,curbH,innerD),C.tile,nil,9)
        tiledPart(parent,name.."EastWaterCoping",
            CFrame.new(cx+w*.5-apron,curbY,cz),Vector3.new(curbT,curbH,innerD),C.tile,nil,9)
    end
    local function room(name,cx,cz,w,d,h,doors,muted,noFloor)
        if noFloor then
            sealedPoolPerimeter(name,cx,cz,w,d)
        else
            floorRect(name.."Floor",cx,cz,w,d,0,C.tile)
        end
        ceilingRect(name.."Ceiling",cx,cz,w,d,h,muted)
        gapWallX(name.."NorthWall",cx,cz-d*.5,w,h,doors and doors.n,doors and doors.nw or 22,C.tile)
        gapWallX(name.."SouthWall",cx,cz+d*.5,w,h,doors and doors.s,doors and doors.sw or 22,C.tile)
        gapWallZ(name.."WestWall",cx-w*.5,cz,d,h,doors and doors.w,doors and doors.ww or 22,C.tile)
        gapWallZ(name.."EastWall",cx+w*.5,cz,d,h,doors and doors.e,doors and doors.ew or 22,C.tile)
        if noFloor and doors then
            -- Terrain water rounds to four-stud voxels and can otherwise peek
            -- through the dry side of an opening.  These solid tiled seals sit
            -- just above the waterline and overlap each doorpost by four studs.
            local function sealX(label,gapX,z,gapW)
                if not gapX then return end
                local seal=tiledPart(parent,name..label,CFrame.new(gapX,-.15,z),
                    Vector3.new((gapW or 22)+8,2.4,8),C.tile,nil,10)
                seal:SetAttribute("PoolDoorSeal",true)
                seal:SetAttribute("WaterStopFoundation",true)
            end
            local function sealZ(label,x,gapZ,gapW)
                if not gapZ then return end
                local seal=tiledPart(parent,name..label,CFrame.new(x,-.15,gapZ),
                    Vector3.new(8,2.4,(gapW or 22)+8),C.tile,nil,10)
                seal:SetAttribute("PoolDoorSeal",true)
                seal:SetAttribute("WaterStopFoundation",true)
            end
            sealX("NorthDoorSeal",doors.n,cz-d*.5,doors.nw)
            sealX("SouthDoorSeal",doors.s,cz+d*.5,doors.sw)
            sealZ("WestDoorSeal",cx-w*.5,doors.w,doors.ww)
            sealZ("EastDoorSeal",cx+w*.5,doors.e,doors.ew)
        end
    end
    local function flooded(name,cx,cz,w,d,depth)
        depth=depth or 3 if depth<1 then depth=1.4 end
        tiledPart(parent,name.."PoolBottom",CFrame.new(cx,-depth,cz),Vector3.new(w,.45,d),Color3.fromRGB(157,194,194),{Enum.NormalId.Top},14)
        terrain:FillBlock(CFrame.new(cx,-depth*.5+.35,cz),Vector3.new(math.max(4,w+.6),depth+.7,math.max(4,d+.6)),Enum.Material.Water)
    end
    local function dryLedge(name,cx,cz,w,d,y)
        tiledPart(parent,name,CFrame.new(cx,(y or .9)-1.05,cz),Vector3.new(w,2.2,d),C.tile,nil,14)
    end
    local function waterStopX(name,x,cz,d)
        -- Terrain water snaps to four-stud voxels, so a thin curb can leave a
        -- visible strip on the dry side.  This tiled foundation covers that
        -- spill, reaches below the basin floor, and overlaps both side walls.
        local span=d+8
        local foundation=tiledPart(parent,name.."Foundation",CFrame.new(x,-.3,cz),
            Vector3.new(6,2.2,span),C.tile,nil,9)
        foundation:SetAttribute("WaterRetainingCurb",true)
        foundation:SetAttribute("WaterStopFoundation",true)
        local curb=tiledPart(parent,name,CFrame.new(x,1.05,cz),
            Vector3.new(1.25,.55,span),C.tile,nil,9)
        curb:SetAttribute("WaterRetainingCurb",true)
        return curb
    end
    local function waterStopZ(name,cx,z,w)
        local span=w+8
        local foundation=tiledPart(parent,name.."Foundation",CFrame.new(cx,-.3,z),
            Vector3.new(span,2.2,6),C.tile,nil,9)
        foundation:SetAttribute("WaterRetainingCurb",true)
        foundation:SetAttribute("WaterStopFoundation",true)
        local curb=tiledPart(parent,name,CFrame.new(cx,1.05,z),
            Vector3.new(span,.55,1.25),C.tile,nil,9)
        curb:SetAttribute("WaterRetainingCurb",true)
        return curb
    end
    local function linkX(name,cx,cz,w,d,h,shallow)
        ceilingRect(name.."Ceiling",cx,cz,w,d,h,false)
        wallX(name.."NorthWall",cx,cz-d*.5,w,h,C.tile)
        wallX(name.."SouthWall",cx,cz+d*.5,w,h,C.tile)
        if shallow then
            flooded(name.."Basin",cx,cz,w,d,1.4)
            tiledPart(parent,name.."OverlapThreshold",CFrame.new(cx,-1.05,cz),
                Vector3.new(w+4,.8,d+4),C.tile,nil,14)
            waterStopX(name.."WestWaterStop",cx-w*.5,cz,d)
            waterStopX(name.."EastWaterStop",cx+w*.5,cz,d)
        else
            floorRect(name.."Floor",cx,cz,w,d,0,C.tile)
        end
    end
    local function linkZ(name,cx,cz,w,d,h,shallow)
        ceilingRect(name.."Ceiling",cx,cz,w,d,h,false)
        wallZ(name.."WestWall",cx-w*.5,cz,d,h,C.tile)
        wallZ(name.."EastWall",cx+w*.5,cz,d,h,C.tile)
        if shallow then
            flooded(name.."Basin",cx,cz,w,d,1.4)
            tiledPart(parent,name.."OverlapThreshold",CFrame.new(cx,-1.05,cz),
                Vector3.new(w+4,.8,d+4),C.tile,nil,14)
            waterStopZ(name.."NorthWaterStop",cx,cz-d*.5,w)
            waterStopZ(name.."SouthWaterStop",cx,cz+d*.5,w)
        else
            floorRect(name.."Floor",cx,cz,w,d,0,C.tile)
        end
    end
    local fineReferenceTile=Color3.fromRGB(226,230,216)
    local fineReferencePoolTile=Color3.fromRGB(166,205,199)

    local function submergedWallX(name,cx,cz,len,h,depth,thickness)
        local totalHeight=h+depth+1
        local wall=tiledPart(parent,name,CFrame.new(cx,(h-depth)*.5,cz),
            Vector3.new(len,totalHeight,thickness or 2),fineReferenceTile,nil,8)
        wall:SetAttribute("ReferenceFloodedArchitecture",true)
        return wall
    end

    local function submergedWallZ(name,cx,cz,len,h,depth,thickness)
        local totalHeight=h+depth+1
        local wall=tiledPart(parent,name,CFrame.new(cx,(h-depth)*.5,cz),
            Vector3.new(thickness or 2,totalHeight,len),fineReferenceTile,nil,8)
        wall:SetAttribute("ReferenceFloodedArchitecture",true)
        return wall
    end

    local function fineGapWallX(name,cx,cz,len,h,depth,gapX,gapW)
        if not gapX then
            submergedWallX(name,cx,cz,len,h,depth,2)
            return
        end
        local left,right=cx-len*.5,cx+len*.5
        local a,b=gapX-gapW*.5,gapX+gapW*.5
        if a-left>.05 then submergedWallX(name.."Left",left+(a-left)*.5,cz,a-left,h,depth,2) end
        if right-b>.05 then submergedWallX(name.."Right",b+(right-b)*.5,cz,right-b,h,depth,2) end
        local openHeight=13
        if h>openHeight then
            tiledPart(parent,name.."Lintel",CFrame.new(gapX,(h+openHeight)*.5,cz),
                Vector3.new(gapW,h-openHeight+.4,2),fineReferenceTile,nil,8)
        end
    end

    local function fineGapWallZ(name,cx,cz,len,h,depth,gapZ,gapW)
        if not gapZ then
            submergedWallZ(name,cx,cz,len,h,depth,2)
            return
        end
        local low,high=cz-len*.5,cz+len*.5
        local a,b=gapZ-gapW*.5,gapZ+gapW*.5
        if a-low>.05 then submergedWallZ(name.."North",cx,low+(a-low)*.5,a-low,h,depth,2) end
        if high-b>.05 then submergedWallZ(name.."South",cx,b+(high-b)*.5,high-b,h,depth,2) end
        local openHeight=13
        if h>openHeight then
            tiledPart(parent,name.."Lintel",CFrame.new(cx,(h+openHeight)*.5,gapZ),
                Vector3.new(2,h-openHeight+.4,gapW),fineReferenceTile,nil,8)
        end
    end

    local function fineFlooded(name,cx,cz,w,d,depth)
        tiledPart(parent,name.."PoolBottom",CFrame.new(cx,-depth,cz),
            Vector3.new(w,.5,d),fineReferencePoolTile,{Enum.NormalId.Top},8)
        terrain:FillBlock(CFrame.new(cx,-depth*.5+.35,cz),
            Vector3.new(math.max(4,w+.6),depth+.7,math.max(4,d+.6)),Enum.Material.Water)
    end

    local function floodedShellRoom(name,cx,cz,w,d,h,depth,doors)
        fineFlooded(name,cx,cz,w-2,d-2,depth)
        ceilingRect(name.."Ceiling",cx,cz,w,d,h,true)
        fineGapWallX(name.."NorthWall",cx,cz-d*.5,w,h,depth,doors and doors.n,doors and doors.nw or 22)
        fineGapWallX(name.."SouthWall",cx,cz+d*.5,w,h,depth,doors and doors.s,doors and doors.sw or 22)
        fineGapWallZ(name.."WestWall",cx-w*.5,cz,d,h,depth,doors and doors.w,doors and doors.ww or 22)
        fineGapWallZ(name.."EastWall",cx+w*.5,cz,d,h,depth,doors and doors.e,doors and doors.ew or 22)
    end

    local function floodedLinkX(name,cx,cz,w,d,h,depth)
        ceilingRect(name.."Ceiling",cx,cz,w,d,h,true)
        submergedWallX(name.."NorthWall",cx,cz-d*.5,w,h,depth,2)
        submergedWallX(name.."SouthWall",cx,cz+d*.5,w,h,depth,2)
        fineFlooded(name,cx,cz,w,d,depth)
    end

    local function floodedLinkZ(name,cx,cz,w,d,h,depth)
        ceilingRect(name.."Ceiling",cx,cz,w,d,h,true)
        submergedWallZ(name.."WestWall",cx-w*.5,cz,d,h,depth,2)
        submergedWallZ(name.."EastWall",cx+w*.5,cz,d,h,depth,2)
        fineFlooded(name,cx,cz,w,d,depth)
    end

    local function floodedJunctionZ(name,cx,cz,w,d,h,depth,eastGapZ,eastGapW)
        ceilingRect(name.."Ceiling",cx,cz,w,d,h,true)
        submergedWallZ(name.."WestWall",cx-w*.5,cz,d,h,depth,2)
        fineGapWallZ(name.."EastWall",cx+w*.5,cz,d,h,depth,eastGapZ,eastGapW)
        fineFlooded(name,cx,cz,w,d,depth)
    end

    local function hiddenCeilingWash(name,position,brightness,range,angle)
        local source=part(lamps,name,CFrame.new(position),Vector3.new(8,.16,8),
            Color3.fromRGB(255,249,224),Enum.Material.Neon,1)
        source.CanCollide=false
        source.CanTouch=false
        source.CanQuery=false
        source.CastShadow=false
        source:SetAttribute("PoolLightScreen",true)
        local light=Instance.new("SurfaceLight")
        light.Face=Enum.NormalId.Bottom
        light.Color=Color3.fromRGB(255,246,218)
        light.Brightness=brightness or 2
        light.Range=range or 44
        light.Angle=angle or 135
        light.Shadows=false
        light.Parent=source
        return source
    end

    local valve3StarTextureId="rbxassetid://135968524354326"
    local valve3MosaicTextureId="rbxassetid://117153351675245"

    local function generatedPatternOnPart(target,assetId,studsPerTile,faces)
        if not target or not target:IsA("BasePart") then return end
        for _,child in ipairs(target:GetChildren()) do
            if child:IsA("Texture") then child:Destroy() end
        end
        target.Color=Color3.fromRGB(255,255,255)
        target.Material=Enum.Material.SmoothPlastic
        target.Reflectance=.045
        local patternFaces=faces
        if not patternFaces then
            patternFaces=target.Size.X>=target.Size.Z
                and {Enum.NormalId.Front,Enum.NormalId.Back}
                or {Enum.NormalId.Left,Enum.NormalId.Right}
        end
        for _,face in ipairs(patternFaces) do
            local layer=Instance.new("Texture")
            layer.Name="Valve3GeneratedSurface"
            layer.Texture=assetId
            layer.Face=face
            layer.StudsPerTileU=studsPerTile or 24
            layer.StudsPerTileV=studsPerTile or 24
            layer.Color3=Color3.new(1,1,1)
            layer.Transparency=0
            layer.Parent=target
        end
        target:SetAttribute("Valve3GeneratedTexture",assetId)
    end

    local function generatedPatternByPrefix(prefix,assetId,studsPerTile,wallsOnly,allSides)
        for _,target in ipairs(parent:GetChildren()) do
            if target:IsA("BasePart")
                and target.Name:sub(1,#prefix)==prefix
                and (not wallsOnly or target.Name:find("Wall")) then
                generatedPatternOnPart(target,assetId,studsPerTile,allSides and {
                    Enum.NormalId.Front,Enum.NormalId.Back,
                    Enum.NormalId.Left,Enum.NormalId.Right,
                    Enum.NormalId.Top,Enum.NormalId.Bottom,
                } or nil)
            end
        end
    end

    local function valve3RoundLight(name,position,diameter,brightness)
        local fixture=part(lamps,name,
            CFrame.new(position)*CFrame.Angles(0,0,math.rad(90)),
            Vector3.new(.2,diameter or 2.5,diameter or 2.5),
            Color3.fromRGB(255,250,229),Enum.Material.Neon,.025)
        fixture.Shape=Enum.PartType.Cylinder
        fixture.CanCollide=false
        fixture.CanTouch=false
        fixture.CanQuery=false
        fixture.CastShadow=false
        fixture:SetAttribute("PoolLightScreen",true)
        fixture:SetAttribute("Valve3RoundDownlight",true)
        local glow=Instance.new("PointLight")
        glow.Color=Color3.fromRGB(255,244,217)
        glow.Brightness=brightness or .55
        glow.Range=18
        glow.Shadows=false
        glow.Parent=fixture
        return fixture
    end

    local function valve3ChildrensPortalArch(name,center,width,height,tint)
        -- Repeated child-scale archways deliberately connect unlike rooms at
        -- slightly wrong offsets: cheerful architecture with backrooms logic.
        local model=Instance.new("Model")
        model.Name=name
        model.Parent=parent
        model:SetAttribute("Valve3ChildrensArea",true)
        model:SetAttribute("BackroomsConnector",true)
        local postWidth=1.35
        local thickness=1.6
        for _,side in ipairs({-1,1}) do
            local post=part(model,"Valve3KidsArchPost",
                CFrame.new(center+Vector3.new(side*(width-postWidth)*.5,height*.5,0)),
                Vector3.new(postWidth,height,thickness),tint,Enum.Material.SmoothPlastic)
            post.Reflectance=.12
            post:SetAttribute("Valve3ChildrensArea",true)
        end
        local crown=part(model,"Valve3KidsArchCrown",
            CFrame.new(center+Vector3.new(0,height-postWidth*.5,0)),
            Vector3.new(width,postWidth,thickness),tint:Lerp(Color3.new(1,1,1),.16),
            Enum.Material.SmoothPlastic)
        crown.Reflectance=.12
        crown:SetAttribute("Valve3ChildrensArea",true)
        return model
    end

    local function curvedFloodedCorridor(name,centerX,centerZ,radius,width,h,depth,startDegrees,endDegrees,segments)
        local model=Instance.new("Model")
        model.Name=name
        model.Parent=parent
        model:SetAttribute("ReferenceFloodedArchitecture",true)
        model:SetAttribute("CurvedWaterCorridor",true)

        local startAngle=math.rad(startDegrees)
        local endAngle=math.rad(endDegrees)
        local wallHeight=h+depth+1
        local wallY=(h-depth)*.5
        local function point(radialDistance,angle,y)
            return Vector3.new(centerX+math.cos(angle)*radialDistance,y or 0,centerZ+math.sin(angle)*radialDistance)
        end

        for i=0,segments-1 do
            local a0=startAngle+(endAngle-startAngle)*(i/segments)
            local a1=startAngle+(endAngle-startAngle)*((i+1)/segments)
            local c0,c1=point(radius,a0),point(radius,a1)
            local centerDelta=c1-c0
            local centerMid=(c0+c1)*.5
            local centerFrame=CFrame.lookAt(
                Vector3.new(centerMid.X,-depth,centerMid.Z),
                Vector3.new(centerMid.X+centerDelta.X,-depth,centerMid.Z+centerDelta.Z))
            tiledPart(model,name.."FloorSegment"..(i+1),centerFrame,
                Vector3.new(width+.8,.5,centerDelta.Magnitude+1.35),
                fineReferencePoolTile,{Enum.NormalId.Top},8)

            local ceilingFrame=CFrame.lookAt(
                Vector3.new(centerMid.X,h,centerMid.Z),
                Vector3.new(centerMid.X+centerDelta.X,h,centerMid.Z+centerDelta.Z))
            tiledPart(model,name.."CeilingSegment"..(i+1),ceilingFrame,
                Vector3.new(width+1.2,.8,centerDelta.Magnitude+1.35),softTile,{Enum.NormalId.Bottom},8)

            local waterFrame=CFrame.lookAt(
                Vector3.new(centerMid.X,-depth*.5+.35,centerMid.Z),
                Vector3.new(centerMid.X+centerDelta.X,-depth*.5+.35,centerMid.Z+centerDelta.Z))
            terrain:FillBlock(waterFrame,
                Vector3.new(width-1,depth+.7,centerDelta.Magnitude+1.4),Enum.Material.Water)

            for _,side in ipairs({
                {label="Inner",radialDistance=radius-width*.5},
                {label="Outer",radialDistance=radius+width*.5},
            }) do
                local p0,p1=point(side.radialDistance,a0),point(side.radialDistance,a1)
                local delta=p1-p0
                local mid=(p0+p1)*.5
                local wallFrame=CFrame.lookAt(
                    Vector3.new(mid.X,wallY,mid.Z),
                    Vector3.new(mid.X+delta.X,wallY,mid.Z+delta.Z))
                local wall=tiledPart(model,name..side.label.."CurveWall"..(i+1),wallFrame,
                    Vector3.new(1.5,wallHeight,delta.Magnitude+1.05),fineReferenceTile,nil,8)
                wall:SetAttribute("CurvedTiledWall",true)
            end
        end
        return model
    end

    local function floodedPortalBank(name,leftX,rightX,z,h,depth,openingCenters,openingWidth,openHeight,tunnelDepth,tunnelDirection)
        local model=Instance.new("Model")
        model.Name=name
        model.Parent=parent
        model:SetAttribute("ReferenceFloodedArchitecture",true)
        model:SetAttribute("FloodedDoorPortalBank",true)
        tunnelDirection=tunnelDirection or -1

        local cursor=leftX
        for index,centerX in ipairs(openingCenters) do
            local gapLeft=centerX-openingWidth*.5
            if gapLeft>cursor then
                local wall=submergedWallX(name.."Pier"..index,(cursor+gapLeft)*.5,z,gapLeft-cursor,h,depth,3)
                wall.Parent=model
            end
            cursor=centerX+openingWidth*.5

            local lintelHeight=h-openHeight+.45
            local lintel=tiledPart(model,name.."PortalLintel"..index,
                CFrame.new(centerX,openHeight+lintelHeight*.5,z),
                Vector3.new(openingWidth,lintelHeight,3),fineReferenceTile,nil,8)
            lintel:SetAttribute("DarkFloodedPortal",true)

            local tunnelCenterZ=z+tunnelDirection*tunnelDepth*.5
            for _,sideX in ipairs({centerX-openingWidth*.5,centerX+openingWidth*.5}) do
                local sideWall=submergedWallZ(name.."TunnelJamb"..index,sideX,tunnelCenterZ,
                    tunnelDepth,openHeight,depth,1.25)
                sideWall.Parent=model
                sideWall:SetAttribute("DarkFloodedPortal",true)
            end
            local tunnelCeiling=tiledPart(model,name.."TunnelCeiling"..index,
                CFrame.new(centerX,openHeight,tunnelCenterZ),
                Vector3.new(openingWidth+.6,.8,tunnelDepth),fineReferenceTile,{Enum.NormalId.Bottom},8)
            tunnelCeiling:SetAttribute("DarkFloodedPortal",true)
        end
        if rightX>cursor then
            local wall=submergedWallX(name.."PierEnd",(cursor+rightX)*.5,z,rightX-cursor,h,depth,3)
            wall.Parent=model
        end
        return model
    end

    local function submergedReferenceStair(name,cx,startZ,width,stepDepth,steps,rise,depth,direction)
        local model=Instance.new("Model")
        model.Name=name
        model.Parent=parent
        model:SetAttribute("ReferenceFloodedArchitecture",true)
        model:SetAttribute("SubmergedStaircase",true)
        direction=direction or 1
        local bottom=-depth-.2
        local firstTop=-depth+.75
        local finalTop=firstTop+(steps-1)*rise

        for i=0,steps-1 do
            local top=firstTop+i*rise
            local height=top-bottom
            local z=startZ+direction*i*stepDepth
            local step=tiledPart(model,name.."Step"..(i+1),
                CFrame.new(cx,bottom+height*.5,z),
                Vector3.new(width,height,stepDepth+.2),fineReferenceTile,nil,8)
            step:SetAttribute("SubmergedStepIndex",i+1)
        end

        local landingLength=12
        local landingCenterZ=startZ+direction*(steps*stepDepth+landingLength*.5-stepDepth*.5)
        tiledPart(model,name.."UpperLanding",
            CFrame.new(cx,bottom+(finalTop-bottom)*.5,landingCenterZ),
            Vector3.new(width,finalTop-bottom,landingLength),fineReferenceTile,nil,8)

        local wedge=Instance.new("WedgePart")
        wedge.Name=name.."LeftParapet"
        wedge.Anchored=true
        local wedgeTop=finalTop+1.5
        local runLength=steps*stepDepth
        local runCenterZ=startZ+direction*(steps-1)*stepDepth*.5
        wedge.Size=Vector3.new(1.4,wedgeTop-bottom,runLength)
        wedge.CFrame=CFrame.new(cx-width*.5-.8,(wedgeTop+bottom)*.5,runCenterZ)
            *CFrame.Angles(0,direction>0 and 0 or math.pi,0)
        wedge.Color=fineReferenceTile
        wedge.Material=Enum.Material.SmoothPlastic
        wedge.TopSurface=Enum.SurfaceType.Smooth
        wedge.BottomSurface=Enum.SurfaceType.Smooth
        wedge.Parent=model
        texture(wedge,Enum.NormalId:GetEnumItems(),8)
        wedge:SetAttribute("SubmergedStairParapet",true)
        return model
    end

    local function frostedPanel(name,cf,size,dim)
        local screen=part(lamps,name,cf,size or Vector3.new(5,12,.35),wallLightColor,Enum.Material.Neon,.04)
        screen.CanCollide=false; screen.CastShadow=false; screen:SetAttribute("PoolLightScreen",true)
        for _,face in ipairs({Enum.NormalId.Front,Enum.NormalId.Back}) do
            local light=Instance.new("SurfaceLight")
            light.Face=face; light.Color=wallLightColor; light.Brightness=dim and 1.15 or 2.2
            light.Range=dim and 30 or 48; light.Angle=150; light.Shadows=false; light.Parent=screen
        end
        local glow=Instance.new("PointLight")
        glow.Color=wallLightColor; glow.Brightness=dim and .35 or .65; glow.Range=dim and 16 or 25; glow.Shadows=false; glow.Parent=screen
        return screen
    end

    local overheadAqua=Color3.fromRGB(38,143,154)
    local overheadAquaLight=Color3.fromRGB(104,195,194)
    local overheadBlue=Color3.fromRGB(49,119,158)
    local overheadDark=Color3.fromRGB(17,76,88)
    local overheadCream=Color3.fromRGB(225,228,207)
    local overheadSteel=Color3.fromRGB(157,169,166)
    local referenceGreen=Color3.fromRGB(82,178,45)
    local referenceGreenLight=Color3.fromRGB(142,218,82)
    local referenceRed=Color3.fromRGB(197,47,38)
    local referenceRedLight=Color3.fromRGB(244,91,67)
    local referenceRedDark=Color3.fromRGB(92,18,20)
    local referenceYellow=Color3.fromRGB(199,177,22)
    local referenceYellowLight=Color3.fromRGB(244,223,69)
    local referenceBlue=Color3.fromRGB(31,143,193)
    local referenceBlueLight=Color3.fromRGB(88,201,232)

    local function markDecorative(object)
        object.CanTouch=false
        object.CanQuery=false
        object:SetAttribute("DecorativePoolSlide",true)
        object:SetAttribute("PlayableSlide",false)
        return object
    end

    local function ellipseRing(container,name,center,rx,rz,color,width,thickness)
        local segments=16
        for i=0,segments-1 do
            local a=i*math.pi*2/segments
            local b=(i+1)*math.pi*2/segments
            local p1=center+Vector3.new(math.cos(a)*rx,0,math.sin(a)*rz)
            local p2=center+Vector3.new(math.cos(b)*rx,0,math.sin(b)*rz)
            local delta=p2-p1
            local piece=part(container,name,CFrame.lookAt((p1+p2)*.5,p2),
                Vector3.new(width or .72,thickness or .28,delta.Magnitude+.16),
                color or wallLightColor,Enum.Material.Neon)
            piece.CanCollide=false
            piece.CastShadow=false
            piece:SetAttribute("PoolLightScreen",true)
            markDecorative(piece)
        end
    end

    local function replaceCeilingWithOpenings(roomName,cx,cz,w,d,h,muted,openings)
        local old=parent:FindFirstChild(roomName.."Ceiling")
        if old then old:Destroy() end

        local xCuts={cx-w*.5,cx+w*.5}
        local zCuts={cz-d*.5,cz+d*.5}
        for _,opening in ipairs(openings) do
            opening.x=math.clamp(opening.x,cx-w*.5+2,cx+w*.5-2)
            opening.z=math.clamp(opening.z,cz-d*.5+2,cz+d*.5-2)
            opening.w=math.min(opening.w,w-4)
            opening.d=math.min(opening.d,d-4)
            table.insert(xCuts,opening.x-opening.w*.5)
            table.insert(xCuts,opening.x+opening.w*.5)
            table.insert(zCuts,opening.z-opening.d*.5)
            table.insert(zCuts,opening.z+opening.d*.5)
        end
        table.sort(xCuts)
        table.sort(zCuts)
        local function unique(values)
            local result={}
            for _,value in ipairs(values) do
                if #result==0 or math.abs(value-result[#result])>.01 then
                    table.insert(result,value)
                end
            end
            return result
        end
        xCuts=unique(xCuts)
        zCuts=unique(zCuts)

        local section=0
        for xi=1,#xCuts-1 do
            for zi=1,#zCuts-1 do
                local x0,x1=xCuts[xi],xCuts[xi+1]
                local z0,z1=zCuts[zi],zCuts[zi+1]
                if x1-x0>.05 and z1-z0>.05 then
                    local mx,mz=(x0+x1)*.5,(z0+z1)*.5
                    local inside=false
                    for _,opening in ipairs(openings) do
                        if math.abs(mx-opening.x)<opening.w*.5-.01
                            and math.abs(mz-opening.z)<opening.d*.5-.01 then
                            inside=true
                            break
                        end
                    end
                    if not inside then
                        section+=1
                        ceilingRect(roomName.."CeilingSection"..section,mx,mz,x1-x0,z1-z0,h,muted)
                    end
                end
            end
        end

        for _,opening in ipairs(openings) do
            local well=Instance.new("Model")
            well.Name=opening.name
            well.Parent=parent
            well:SetAttribute("CeilingLightOpening",true)
            well:SetAttribute("ContainsDecorativeSlide",opening.slide==true)

            local revealY=h+.55
            local revealH=1.9
            tiledPart(well,"WhiteOpeningNorthReveal",
                CFrame.new(opening.x,revealY,opening.z-opening.d*.5),
                Vector3.new(opening.w+1.2,revealH,.65),C.tile,nil,8)
            tiledPart(well,"WhiteOpeningSouthReveal",
                CFrame.new(opening.x,revealY,opening.z+opening.d*.5),
                Vector3.new(opening.w+1.2,revealH,.65),C.tile,nil,8)
            tiledPart(well,"WhiteOpeningWestReveal",
                CFrame.new(opening.x-opening.w*.5,revealY,opening.z),
                Vector3.new(.65,revealH,opening.d),C.tile,nil,8)
            tiledPart(well,"WhiteOpeningEastReveal",
                CFrame.new(opening.x+opening.w*.5,revealY,opening.z),
                Vector3.new(.65,revealH,opening.d),C.tile,nil,8)

            local trimY=h-.43
            local trimColor=Color3.fromRGB(244,249,238)
            local function glowTrim(name,cf,size)
                local trim=part(well,name,cf,size,trimColor,Enum.Material.Neon,.03)
                trim.CanCollide=false
                trim.CastShadow=false
                trim:SetAttribute("PoolLightScreen",true)
                markDecorative(trim)
                return trim
            end
            if not opening.polygon then
                glowTrim("WhiteOpeningNorthTrim",CFrame.new(opening.x,trimY,opening.z-opening.d*.5),Vector3.new(opening.w+1.1,.22,.72))
                glowTrim("WhiteOpeningSouthTrim",CFrame.new(opening.x,trimY,opening.z+opening.d*.5),Vector3.new(opening.w+1.1,.22,.72))
                glowTrim("WhiteOpeningWestTrim",CFrame.new(opening.x-opening.w*.5,trimY,opening.z),Vector3.new(.72,.22,opening.d))
                glowTrim("WhiteOpeningEastTrim",CFrame.new(opening.x+opening.w*.5,trimY,opening.z),Vector3.new(.72,.22,opening.d))
            end

            local function safetySeal()
                local seal=part(well,"CeilingSafetySeal",CFrame.new(opening.x,h+.35,opening.z),
                    Vector3.new(opening.w-.8,.2,opening.d-.8),C.tile,Enum.Material.SmoothPlastic,1)
                seal.CanCollide=true
                seal.CanTouch=false
                seal.CanQuery=false
                seal.CastShadow=false
                seal:SetAttribute("InvisibleCeilingBarrier",true)
                return seal
            end

            if opening.slide then
                ellipseRing(well,"WhiteSlidePortalRing",
                    Vector3.new(opening.x,h-.48,opening.z),
                    math.min(opening.w,opening.d)*.38,
                    math.min(opening.w,opening.d)*.38,
                    trimColor,1.05,.32)
                local source=part(lamps,opening.name.."PortalGlow",CFrame.new(opening.x,h-.25,opening.z),
                    Vector3.new(.2,.2,.2),trimColor,Enum.Material.Neon,1)
                source.CanCollide=false
                source.CanTouch=false
                source.CanQuery=false
                local glow=Instance.new("PointLight")
                glow.Color=trimColor
                glow.Brightness=.7
                glow.Range=28
                glow.Shadows=false
                glow.Parent=source
                safetySeal()
            else
                local function configureDiffuser(diffuser)
                    diffuser.CanCollide=false
                    diffuser.CanTouch=false
                    diffuser.CanQuery=false
                    diffuser.CastShadow=false
                    diffuser:SetAttribute("PoolLightScreen",true)
                end

                if opening.polygon then
                    well:SetAttribute("OpeningShape","AsymmetricPolygon")
                    local backing=tiledPart(well,"SkylightCeilingBacking",
                        CFrame.new(opening.x,h+1.52,opening.z),
                        Vector3.new(opening.w-.1,.18,opening.d-.1),C.tile,nil,8)
                    backing.CanCollide=false
                    backing.CanTouch=false
                    backing.CanQuery=false
                    backing.CastShadow=false
                    backing:SetAttribute("SkylightCornerClosure",true)
                    local base=CFrame.new(opening.x,h+1.35,opening.z)
                        *CFrame.Angles(0,math.rad(opening.rotation or 0),0)
                    local pieces={
                        {0,0,.64,.72,0},
                        {-.31,-.01,.32,.55,-18},
                        {.31,.02,.34,.61,21},
                        {.03,-.29,.46,.27,-8},
                    }
                    for _,spec in ipairs(pieces) do
                        local diffuser=part(well,"AngularWhiteSkylight",
                            base*CFrame.new(spec[1]*opening.w,0,spec[2]*opening.d)
                                *CFrame.Angles(0,math.rad(spec[5]),0),
                            Vector3.new(spec[3]*opening.w,.24,spec[4]*opening.d),
                            trimColor,Enum.Material.Neon,.04)
                        configureDiffuser(diffuser)
                    end
                else
                    local diffuser=part(well,"RecessedWhiteDiffuser",
                        CFrame.new(opening.x,h+1.35,opening.z)*CFrame.Angles(0,0,math.rad(90)),
                        Vector3.new(.24,opening.w-1.4,opening.d-1.4),
                        trimColor,Enum.Material.Neon,.06)
                    diffuser.Shape=Enum.PartType.Cylinder
                    configureDiffuser(diffuser)
                end

                local source=part(lamps,opening.name.."Downlight",CFrame.new(opening.x,h+.7,opening.z),
                    Vector3.new(opening.w-1.2,.12,opening.d-1.2),trimColor,Enum.Material.Neon,1)
                source.CanCollide=false
                source.CanTouch=false
                source.CanQuery=false
                source.CastShadow=false
                source:SetAttribute("PoolLightScreen",true)
                local light=Instance.new("SurfaceLight")
                light.Face=Enum.NormalId.Bottom
                light.Color=Color3.fromRGB(232,250,242)
                light.Brightness=2.5
                light.Range=62
                light.Angle=150
                light.Shadows=false
                light.Parent=source
                safetySeal()
            end
        end
    end

    local function slideFrame(center,delta)
        local axis=delta.Unit
        local guide=math.abs(axis:Dot(Vector3.yAxis))>.92 and Vector3.new(0,0,1) or Vector3.yAxis
        local up=(guide-axis*axis:Dot(guide)).Unit
        local back=axis:Cross(up).Unit
        return CFrame.fromMatrix(center,axis,up,back)
    end

    local function helicalSlideCurves(center,radius,startY,endY,turns,startAngle)
        -- Quarter-turn cubic curves give decorative tubes a true, smooth helix
        -- instead of a nearly-flat overhead ribbon.
        local curves={}
        local segmentCount=math.max(4,math.ceil(turns*4))
        local totalAngle=turns*math.pi*2
        for segment=0,segmentCount-1 do
            local t0=segment/segmentCount
            local t1=(segment+1)/segmentCount
            local angle0=(startAngle or 0)+totalAngle*t0
            local angle1=(startAngle or 0)+totalAngle*t1
            local deltaAngle=angle1-angle0
            local y0=startY+(endY-startY)*t0
            local y1=startY+(endY-startY)*t1
            local deltaY=y1-y0
            local p0=Vector3.new(center.X+math.cos(angle0)*radius,y0,center.Z+math.sin(angle0)*radius)
            local p3=Vector3.new(center.X+math.cos(angle1)*radius,y1,center.Z+math.sin(angle1)*radius)
            local p1=p0+Vector3.new(-math.sin(angle0)*radius*deltaAngle/3,deltaY/3,math.cos(angle0)*radius*deltaAngle/3)
            local p2=p3-Vector3.new(-math.sin(angle1)*radius*deltaAngle/3,deltaY/3,math.cos(angle1)*radius*deltaAngle/3)
            table.insert(curves,{p0,p1,p2,p3})
        end
        return curves
    end

    local function slideBand(model,name,position,direction,radius,facets,color)
        local frame=slideFrame(position,direction)
        local segmentWidth=math.pi*2*(radius+.05)/facets+.1
        for i=0,facets-1 do
            local a=(i+.5)*math.pi*2/facets
            local band=part(model,name,
                frame*CFrame.Angles(a,0,0)*CFrame.new(0,radius+.04,0),
                Vector3.new(.72,.23,segmentWidth),color,Enum.Material.SmoothPlastic)
            band.Reflectance=.18
            band.CanCollide=false
            markDecorative(band)
        end
    end

    local function decorativePoolSlide(name,controls,radius,baseColor,highlight,ceilingY,suspended,capColor,rimColor)
        local model=Instance.new("Model")
        model.Name=name
        model.Parent=parent
        model:SetAttribute("DecorativePoolSlide",true)
        model:SetAttribute("PlayableSlide",false)
        model:SetAttribute("InaccessibleByDesign",true)
        capColor=capColor or overheadDark
        rimColor=rimColor or overheadCream

        local curves=typeof(controls[1])=="Vector3" and {controls} or controls
        local samples={}
        local steps=6
        for curveIndex,curve in ipairs(curves) do
            for i=0,steps do
                if curveIndex==1 or i>0 then
                    local t=i/steps
                    local u=1-t
                    local point=curve[1]*(u*u*u)
                        +curve[2]*(3*u*u*t)
                        +curve[3]*(3*u*t*t)
                        +curve[4]*(t*t*t)
                    table.insert(samples,point)
                end
            end
        end

        local facets=10
        local segmentWidth=math.pi*2*radius/facets+.14
        for i=1,#samples-1 do
            local a,b=samples[i],samples[i+1]
            local delta=b-a
            local frame=slideFrame((a+b)*.5,delta)
            for facet=0,facets-1 do
                local angle=(facet+.5)*math.pi*2/facets
                local shade=(facet%3==0) and highlight:Lerp(baseColor,.28) or baseColor
                local shell=part(model,"DecorativeSlideShell",
                    frame*CFrame.Angles(angle,0,0)*CFrame.new(0,radius,0),
                    Vector3.new(delta.Magnitude+.62,.46,segmentWidth),
                    shade,Enum.Material.SmoothPlastic)
                shell.Reflectance=.17
                shell.CanCollide=false
                markDecorative(shell)
            end
        end

        for index=math.floor(steps*.5)+1,#samples-1,steps do
            local direction=samples[index+1]-samples[index]
            slideBand(model,"DecorativeSlideMoulding",samples[index],direction,radius,facets,highlight)
        end

        local function closedEnd(label,point,direction)
            local cap=part(model,label,slideFrame(point,direction),
                Vector3.new(.78,radius*1.76,radius*1.76),
                capColor,Enum.Material.SmoothPlastic)
            cap.Shape=Enum.PartType.Cylinder
            cap.Reflectance=.1
            cap.CanCollide=true
            markDecorative(cap)
            slideBand(model,label.."Rim",point,direction,radius,facets,rimColor)
        end
        closedEnd("SealedDecorativeMouthA",samples[1],samples[2]-samples[1])
        closedEnd("SealedDecorativeMouthB",samples[#samples],samples[#samples]-samples[#samples-1])

        if suspended then
            for _,fraction in ipairs({.34,.68}) do
                local index=math.clamp(math.floor((#samples-1)*fraction)+1,2,#samples-1)
                local point=samples[index]
                local bottom=point+Vector3.new(0,radius+.45,0)
                local top=Vector3.new(point.X,ceilingY-.38,point.Z)
                if top.Y-bottom.Y>.3 then
                    local delta=top-bottom
                    local hanger=part(model,"CeilingSlideHanger",CFrame.lookAt((top+bottom)*.5,top),
                        Vector3.new(.46,.46,delta.Magnitude),overheadSteel,Enum.Material.Metal)
                    hanger.CanCollide=false
                    markDecorative(hanger)
                end
            end
        end
        return model
    end

    room("ArrivalChamber",-340,-300,100,90,22,{e=-300,ew=26},false)
    for z=-330,-270,30 do frostedPanel("ArrivalWallScreen",CFrame.new(-389,8,z)*CFrame.Angles(0,math.rad(90),0),Vector3.new(5,13,.35),false) end
    room("EntryWaterPassage",-270,-300,40,34,16,{w=-300,ww=24,e=-300,ew=24},false,true)
    flooded("EntryWater",-270,-300,38,32,.65)
    dryLedge("EntryNorthLedge",-270,-311.5,40,7,1.05)
    room("Stairwell",-225,-300,50,80,22,{w=-300,ww=24,s=-225,sw=24},false)
    for i=0,4 do floorRect("StairStep",-225,-276-i*2.7,28,5,-.2+i*.45,C.tile) end
    frostedPanel("StairwellScreen",CFrame.new(-249,8,-320)*CFrame.Angles(0,math.rad(90),0),Vector3.new(4,11,.35),false)
    room("FloodedNorthPassage",-225,-225,34,80,17,{s=-225,sw=24,n=-225,nw=24},false,true)
    flooded("NorthPassageWater",-225,-225,32,78,.7)
    -- Reach fully into the west wall and both doorway seals so no water
    -- can remain visible along the ledge's dry side.
    dryLedge("NorthPassageLedge",-237.5,-225,10,84,1.05)
    frostedPanel("NorthPassageScreen",CFrame.new(-208.6,8,-225)*CFrame.Angles(0,math.rad(-90),0),Vector3.new(5,11,.35),false)
    room("OvalLightChamber",-225,-160,80,50,25,{n=-225,nw=24,e=-160,ew=26},false)
    for x=-250,-200,25 do frostedPanel("MuffledWallWindow",CFrame.new(x,9,-135.6)*CFrame.Angles(0,math.rad(180),0),Vector3.new(6,15,.35),false) end
    room("FinalEntryTunnel",-165,-160,40,30,15,{w=-160,ww=26,e=-160,ew=26},false,true)
    flooded("FinalEntryWater",-165,-160,38,28,.6)
    dryLedge("FinalEntryLedge",-165,-170,40,7,1.05)
    -- A shallow tiled incline bridges the exact Valve 1 chamber/threshold
    -- height change so both players and path agents cross instead of snagging.
    local valve1ThresholdRamp=tiledPart(parent,"Valve1ThresholdNavigationRamp",
        CFrame.new(-192,.46,-151.5)*CFrame.Angles(0,0,math.rad(5.27)),
        Vector3.new(13,.32,5.5),C.tile,nil,9)
    valve1ThresholdRamp.CanTouch=false
    valve1ThresholdRamp:SetAttribute("Level2NavigationRamp",true)
    valve1ThresholdRamp:SetAttribute("ThresholdFor","PressureValve1")
    linkX("FinalToGrandLink",-137.5,-160,15,26,15,true)

    -- The showcase hall is intentionally double-height, giving every
    -- overhead slide enough vertical room to fall, bank and spiral independently.
    local grandHallHeight=68
    room("GrandPoolHall",0,-100,260,220,grandHallHeight,{w=-160,ww=30,s=20,sw=34,e=-55,ew=32},false,true)
    replaceCeilingWithOpenings("GrandPoolHall",0,-100,260,220,grandHallHeight,false,{
        {name="GrandSlidePortal",x=97,z=-168,w=18,d=24,slide=true},
        {name="GrandSkylightA",x=-70,z=-172,w=24,d=14,polygon=true,rotation=14},
        {name="GrandSkylightB",x=-15,z=-150,w=20,d=12,polygon=true,rotation=-11},
        {name="GrandSkylightC",x=45,z=-160,w=24,d=14,polygon=true,rotation=19},
        {name="GrandSkylightD",x=21,z=-55,w=28,d=15,polygon=true,rotation=-16},
        {name="GrandSkylightE",x=78,z=-85,w=22,d=13,polygon=true,rotation=25},
    })
    flooded("GrandPoolWater",0,-100,218,178,6)
    dryLedge("GrandNorthLedge",0,-199,260,20,1.08)
    dryLedge("GrandSouthLedge",0,-1,260,20,1.08)
    dryLedge("GrandWestLedge",-119,-100,22,178,1.08)
    dryLedge("GrandEastLedge",119,-100,22,178,1.08)
    dryLedge("GrandCentralIsland",0,-100,54,46,1.1)
    dryLedge("GrandBridgeWest",-72,-100,90,10,1.1)
    dryLedge("GrandBridgeNorth",0,-55,10,44,1.1)
    dryLedge("GrandBridgeEast",72,-100,90,10,1.1)
    for _,p in ipairs({Vector3.new(-72,0,-150),Vector3.new(72,0,-150),Vector3.new(-72,0,-50),Vector3.new(72,0,-50),Vector3.new(-20,0,-100),Vector3.new(20,0,-100)}) do tiledColumn(parent,p,5,grandHallHeight) end

    -- Blue: enters through the roof opening and makes the hall's steepest drop.
    decorativePoolSlide("GrandBlueCeilingDrop",{
        {
            Vector3.new(97,78,-168),
            Vector3.new(97,70,-168),
            Vector3.new(102,59,-162),
            Vector3.new(101,50,-151),
        },
        {
            Vector3.new(101,50,-151),
            Vector3.new(99,41,-141),
            Vector3.new(91,34,-133),
            Vector3.new(83,29,-126),
        },
    },4.5,referenceBlue,referenceBlueLight,grandHallHeight,false)

    -- Green: a full descending helix wrapped around the north-east tiled column.
    decorativePoolSlide("GrandGreenColumnHelix",
        helicalSlideCurves(Vector3.new(72,0,-150),15,60,27,1.75,math.rad(-35)),
        4.1,referenceGreen,referenceGreenLight,grandHallHeight,true)

    -- Red: a long banking S-curve with a clear end-to-end drop.
    decorativePoolSlide("GrandRedDescendingSCurve",{
        {
            Vector3.new(-108,54,-48),
            Vector3.new(-82,55,-31),
            Vector3.new(-47,48,-28),
            Vector3.new(-20,43,-48),
        },
        {
            Vector3.new(-20,43,-48),
            Vector3.new(12,37,-73),
            Vector3.new(45,38,-76),
            Vector3.new(68,33,-58),
        },
        {
            Vector3.new(68,33,-58),
            Vector3.new(86,30,-44),
            Vector3.new(99,29,-39),
            Vector3.new(108,27,-35),
        },
    },3.5,referenceRed,referenceRedLight,grandHallHeight,true)

    -- Yellow: a tighter descending coil around the opposite structural column.
    decorativePoolSlide("GrandYellowColumnSpiral",
        helicalSlideCurves(Vector3.new(-72,0,-150),11.5,49,26,1.15,math.rad(155)),
        3.2,referenceYellow,referenceYellowLight,grandHallHeight,true)
    for _,z in ipairs({-110,-55}) do frostedPanel("GrandHallWallScreen",CFrame.new(-129.3,11,z)*CFrame.Angles(0,math.rad(90),0),Vector3.new(5,15,.35),false) end

    room("ArchWaterWing",200,-55,140,150,22,{w=-55,ww=32,s=200,sw=26,e=-100,ew=24,n=180,nw=24},false,true)
    flooded("ArchWater",200,-55,116,126,5.4)
    dryLedge("ArchWestLedge",142,-55,12,150,1.05)
    dryLedge("ArchEastLedge",258,-55,12,150,1.05)
    dryLedge("ArchNorthLedge",200,-124,116,12,1.05)
    dryLedge("ArchSouthLedge",200,14,116,12,1.05)
    archGallery(parent,lamps,Vector3.new(200,0,-55),false)
    frostedPanel("ArchGuideLight",CFrame.new(200,8,-128.5),Vector3.new(8,12,.35),false)
    for _,x in ipairs({165,235}) do frostedPanel("ArchCeilingScreen",CFrame.new(x,21.3,-55)*CFrame.Angles(math.rad(90),0,0),Vector3.new(14,6,.35),false) end

    -- Reference-inspired optional loop: a concealed curved water corridor,
    -- a chamber of deep flooded portals, and a submerged column stair hall.
    -- Both ends reconnect to ArchWaterWing, so the main puzzle route and all
    -- valve requirements remain unchanged.
    curvedFloodedCorridor("ReferenceCurvedWaterCorridor",270,-145,45,24,17,2.7,90,0,18)
    hiddenCeilingWash("CurvedCorridorWarmWashA",Vector3.new(282,16.4,-103),2.15,40,125)
    hiddenCeilingWash("CurvedCorridorWarmWashB",Vector3.new(311,16.4,-134),1.35,32,120)
    -- Terrain water tops at +0.7 while a fine pool bottom tops at
    -- -depth + 0.25.  A .35 bottom-center depth therefore creates a visually
    -- shallow .8-stud wading layer without moving the room shells or doors.
    local valve3VisibleWaterDepth=.8
    local valve3FloorCenterDepth=valve3VisibleWaterDepth-.45
    floodedJunctionZ("CurveToFloodedDoorChamber",315,-160,24,30,17,valve3FloorCenterDepth,-160,16)
    floodedLinkX("Valve3DistrictJunction",331,-160,8,16,17,valve3FloorCenterDepth)

    -- Dedicated Valve 3 district: compact shallow-wading rooms with fine ivory
    -- tile, warm reflected light, and red-only sealed tubes suspended out of reach.
    floodedShellRoom("Valve3IvoryFoyer",355,-145,40,50,19,valve3FloorCenterDepth,{
        w=-160,ww=16,s=350,sw=16,
    })
    floodedLinkZ("Valve3FoyerToWarmRoom",350,-116,16,8,18,valve3FloorCenterDepth)
    floodedShellRoom("Valve3WarmRoomA",340,-90,46,44,18,valve3FloorCenterDepth,{
        n=350,nw=16,s=355,sw=16,
    })
    floodedLinkZ("Valve3WarmRoomToTubeRoom",355,-64,16,8,18,valve3FloorCenterDepth)
    floodedShellRoom("Valve3RedTubeRoom",365,-40,38,40,20,valve3FloorCenterDepth,{
        n=355,nw=16,s=350,sw=16,
    })
    floodedLinkZ("Valve3TubeToNarrowPool",350,-16,16,8,18,valve3FloorCenterDepth)
    floodedShellRoom("Valve3NarrowPoolRoom",335,8,50,40,18,valve3FloorCenterDepth,{
        n=350,nw=16,s=350,sw=16,
    })
    floodedLinkZ("Valve3NarrowToWarmBend",350,32,16,8,18,valve3FloorCenterDepth)
    floodedShellRoom("Valve3WarmBendRoom",360,55,42,38,19,valve3FloorCenterDepth,{
        n=350,nw=16,s=345,sw=16,
    })
    floodedLinkZ("Valve3WarmBendToControl",345,78,16,8,19,valve3FloorCenterDepth)
    floodedShellRoom("Valve3ControlRoom",330,105,54,46,21,valve3FloorCenterDepth,{
        n=345,nw=16,
    })

    for index,x in ipairs({318,328,338}) do
        local column=tiledPart(parent,"Valve3NarrowColumn"..index,
            CFrame.new(x,(18-valve3FloorCenterDepth)*.5,8),
            Vector3.new(3.4,19+valve3FloorCenterDepth,4),
            fineReferenceTile,nil,8)
        column:SetAttribute("ReferenceFloodedArchitecture",true)
    end

    submergedReferenceStair("Valve3ControlStair",330,94,16,2,8,.55,valve3FloorCenterDepth,1)
    local controlPlinth=tiledPart(parent,"Valve3ControlPlinth",
        CFrame.new(330,0,124.5),Vector3.new(16,4.8,7),
        fineReferenceTile,nil,8)
    controlPlinth:SetAttribute("ReferenceFloodedArchitecture",true)
    controlPlinth:SetAttribute("Valve3RaisedLanding",true)

    -- Repeated gateways make the route read as several incompatible
    -- children's poolrooms stitched together by backrooms logic.
    local kidsArchColors={
        Color3.fromRGB(246,126,173),
        Color3.fromRGB(247,151,78),
        Color3.fromRGB(244,207,73),
        Color3.fromRGB(85,185,139),
        Color3.fromRGB(74,162,215),
    }
    for index,arch in ipairs({
        {Vector3.new(350,0,-116),16,9},
        {Vector3.new(355,0,-64),16,8.6},
        {Vector3.new(350,0,-16),16,9.2},
        {Vector3.new(350,0,32),16,8.8},
        {Vector3.new(345,0,78),16,9.4},
    }) do
        valve3ChildrensPortalArch("Valve3KidsBackroomsArch"..index,
            arch[1],arch[2],arch[3],kidsArchColors[index])
    end

    -- The entire district now uses only the two ImageGen-authored children's
    -- patterns. Every legacy tile Texture is removed first, including floors,
    -- ceilings, stairs, columns, lintels and connecting passage shells.
    local allValve3Faces={
        Enum.NormalId.Front,Enum.NormalId.Back,
        Enum.NormalId.Left,Enum.NormalId.Right,
        Enum.NormalId.Top,Enum.NormalId.Bottom,
    }
    local function valve3DistrictRoot(target)
        local current=target
        while current and current.Parent~=parent do
            current=current.Parent
        end
        return current
    end
    for _,target in ipairs(parent:GetDescendants()) do
        if target:IsA("BasePart") then
            local rootObject=valve3DistrictRoot(target)
            local rootName=rootObject and rootObject.Name or target.Name
            local isValve3=rootName:sub(1,6)=="Valve3"
                or rootName:sub(1,#"CurveToFloodedDoorChamber")=="CurveToFloodedDoorChamber"
            if isValve3 then
                local playfulStars=rootName:find("Control",1,true)
                    or rootName:find("RedTube",1,true)
                    or rootName:find("KidsBackroomsArch",1,true)
                    or rootName:find("WarmBend",1,true)
                generatedPatternOnPart(target,
                    playfulStars and valve3StarTextureId or valve3MosaicTextureId,
                    playfulStars and 22 or 18,allValve3Faces)
                target:SetAttribute("Valve3ChildrensArea",true)
                target:SetAttribute("NoStandardPoolTiles",true)
            end
        end
    end

    hiddenCeilingWash("Valve3FoyerWarmWash",Vector3.new(352,18.4,-145),1.45,32,130)
    hiddenCeilingWash("Valve3WarmRoomWash",Vector3.new(341,17.4,-90),1.25,28,125)
    hiddenCeilingWash("Valve3RedTubeWash",Vector3.new(365,19.4,-40),1.65,32,130)
    hiddenCeilingWash("Valve3NarrowPoolWash",Vector3.new(335,17.4,8),1.45,32,130)
    hiddenCeilingWash("Valve3WarmBendWash",Vector3.new(360,18.4,55),1.35,30,125)
    hiddenCeilingWash("Valve3ControlWarmWash",Vector3.new(330,20.4,108),2.1,38,135)

    valve3RoundLight("Valve3FoyerRoundLight",Vector3.new(356,18.45,-145),2.55,.5)
    valve3RoundLight("Valve3WarmRoomRoundLight",Vector3.new(340,17.45,-90),2.45,.45)
    valve3RoundLight("Valve3RedTubeRoundLight",Vector3.new(365,19.45,-40),2.55,.55)
    valve3RoundLight("Valve3NarrowPoolRoundLight",Vector3.new(348,17.45,8),2.45,.45)
    valve3RoundLight("Valve3WarmBendRoundLight",Vector3.new(360,18.45,55),2.5,.5)
    valve3RoundLight("Valve3ControlRoundLight",Vector3.new(330,20.45,108),2.75,.65)

    decorativePoolSlide("Valve3FoyerRedElbow",{
        Vector3.new(341,15.5,-158),
        Vector3.new(348,16,-154),
        Vector3.new(360,15.8,-148),
        Vector3.new(368,15.5,-137),
    },1.4,referenceRed,referenceRedLight,19,true,referenceRedDark,referenceRedLight)
    decorativePoolSlide("Valve3CompactRedSTube",{
        Vector3.new(352,16.2,-53),
        Vector3.new(357,16.6,-47),
        Vector3.new(372,16.1,-45),
        Vector3.new(377,16.2,-30),
    },1.35,referenceRed,referenceRedLight,20,true,referenceRedDark,referenceRedLight)
    decorativePoolSlide("Valve3ControlRedHalfCoil",{
        Vector3.new(309,17,91),
        Vector3.new(316,17.4,92),
        Vector3.new(340,17.2,98),
        Vector3.new(347,17,113),
    },1.5,referenceRed,referenceRedLight,21,true,referenceRedDark,referenceRedLight)

    floodedShellRoom("ReferenceFloodedDoorChamber",315,-220,120,90,24,2.7,{
        s=315,sw=24,w=-250,ww=24,
    })
    floodedPortalBank("ReferenceFloodedDoorBank",256,374,-215,24,2.7,
        {295,335},11,14,10,-1)
    tiledPart(parent,"DoorChamberCeilingDropA",CFrame.new(282,22.85,-192),
        Vector3.new(38,1.5,24),fineReferenceTile,{Enum.NormalId.Bottom},8)
    tiledPart(parent,"DoorChamberCeilingDropB",CFrame.new(347,22.6,-243),
        Vector3.new(42,2,22),fineReferenceTile,{Enum.NormalId.Bottom},8)
    hiddenCeilingWash("DoorChamberWarmWashA",Vector3.new(282,22.4,-190),2.35,46,135)
    hiddenCeilingWash("DoorChamberWarmWashB",Vector3.new(350,22.4,-193),1.65,38,125)

    floodedLinkX("FloodedDoorToColumnStair",250,-250,10,24,18,2.9)
    floodedShellRoom("ReferenceColumnStairHall",180,-285,130,100,30,3.4,{
        e=-250,ew=24,s=180,sw=24,
    })
    for index,z in ipairs({-315,-294,-273,-252}) do
        local column=tiledPart(parent,"ReferenceTallSquareColumn"..index,
            CFrame.new(140,(30-3.4)*.5,z),Vector3.new(4.6,33.4,5.2),
            fineReferenceTile,nil,8)
        column:SetAttribute("ReferenceFloodedArchitecture",true)
    end
    submergedReferenceStair("ReferenceSubmergedStair",235,-282,18,3,13,.58,3.4,-1)
    hiddenCeilingWash("ColumnStairLandingWash",Vector3.new(235,28.5,-326),3,55,140)
    hiddenCeilingWash("ColumnStairDimFill",Vector3.new(151,28.5,-286),.95,32,125)
    floodedLinkZ("ColumnHallReturnToArch",180,-182.5,24,105,17,2.4)

    linkZ("GrandToPillarLink",20,15,32,10,22,true)
    room("PillarWaterHall",-40,95,180,150,28,{n=20,nw=34,e=135,ew=28,s=-35,sw=24,w=95,ww=26},false,true)
    replaceCeilingWithOpenings("PillarWaterHall",-40,95,180,150,28,false,{
        {name="PillarLightWellA",x=-72,z=74,w=18,d=8},
        {name="PillarLightWellB",x=10,z=146,w=18,d=8},
    })
    flooded("PillarHallWater",-40,95,150,120,5.2)
    dryLedge("PillarHallWest",-119,95,20,150,1.05)
    dryLedge("PillarHallEast",39,95,20,150,1.05)
    dryLedge("PillarHallNorth",-40,164,180,14,1.05)
    dryLedge("PillarHallSouth",-40,26,180,14,1.05)
    for x=-90,-40,50 do for z=55,135,40 do tiledColumn(parent,Vector3.new(x,0,z),5,28) end end
    for _,x in ipairs({-105,-72}) do frostedPanel("PillarHallScreen",CFrame.new(x,10,20.6),Vector3.new(5,14,.35),false) end
    decorativePoolSlide("PillarHallOverheadSlide",{
        Vector3.new(-9,22.5,104),
        Vector3.new(-2,21.4,111),
        Vector3.new(11,21.4,121),
        Vector3.new(19,22.5,129),
    },2.9,overheadAqua,overheadAquaLight,28,true)

    room("PillarChannelBend",-35,190,30,40,16,{n=-35,nw=24,e=200,ew=24},false,true)
    flooded("PillarChannelShallow",-35,190,28,38,.65)
    dryLedge("PillarChannelLedge",-45,190,8,40,1.05)
    room("PillarArchGallery",116.5,135,133,30,16,{w=135,ww=24,e=135,ew=24},false,true)
    flooded("PillarArchShallow",116.5,135,131,28,.65)
    dryLedge("PillarArchLedge",116.5,124.5,133,7,1.05)
    frostedPanel("PillarArchScreen",CFrame.new(116.5,8,149.4),Vector3.new(12,6,.35),false)

    room("LongWaterChannel",125,200,290,54,18,{w=200,ww=28,e=200,ew=28,n=200,nw=28,s=60,sw=28},false,true)
    flooded("ChannelWater",125,200,288,24,1.4) tiledPart(parent,"ChannelWestEntranceBridge",CFrame.new(-18,-.6,200),Vector3.new(24,1.4,28),C.tile,nil,14) tiledPart(parent,"ChannelEastEntranceBridge",CFrame.new(268,-.6,200),Vector3.new(24,1.4,28),C.tile,nil,14)
    dryLedge("ChannelNorthWalk",125,183,290,14,1.05)
    dryLedge("ChannelSouthWalk",125,217,290,14,1.05)
    for _,x in ipairs({10,105,150,195,240}) do frostedPanel("ChannelWallScreen",CFrame.new(x,8,226.5),Vector3.new(12,4,.3),false) end
    linkZ("ArchToChannelLink",200,171.5,28,8,16,true)
    room("ArchToChannel",200,95,34,150,16,{s=200,sw=26,n=200,nw=26,w=135,ww=24},false,true)
    flooded("ArchToChannelWater",200,95,32,148,.7)
    dryLedge("ArchToChannelLedge",189,95,8,150,1.05)

    room("ShallowArcade",-190,95,120,70,18,{e=95,ew=26,s=-190,sw=24},false,true)
    flooded("ShallowArcadeWater",-190,95,116,66,.7)
    dryLedge("ShallowArcadeNorth",-190,66,120,10,1.05)
    dryLedge("ShallowArcadeWest",-246,95,8,70,1.05)
    for _,z in ipairs({78,112}) do frostedPanel("ArcadeWallScreen",CFrame.new(-249.4,8,z)*CFrame.Angles(0,math.rad(90),0),Vector3.new(5,11,.35),false) end
    room("ColumnBath",-190,170,120,80,22,{n=-190,nw=24,s=-190,sw=24},false,true)
    flooded("ColumnBathWater",-190,170,96,58,5.1)
    dryLedge("ColumnBathNorth",-190,135,120,10,1.05)
    dryLedge("ColumnBathSouth",-190,205,120,10,1.05)
    dryLedge("ColumnBathWest",-246,170,8,60,1.05)
    dryLedge("ColumnBathEast",-134,170,8,60,1.05)
    for _,x in ipairs({-220,-160}) do tiledColumn(parent,Vector3.new(x,0,170),5,22) end
    for _,x in ipairs({-220,-160}) do lightPanel(lamps,Vector3.new(x,21.3,170),Vector3.new(13,.25,5)) end
    room("QuietPassage",-190,225,60,30,16,{n=-190,nw=24,s=-190,sw=24},false,true)
    flooded("QuietPassageWater",-190,225,58,28,.6)
    dryLedge("QuietPassageLedge",-210,225,8,30,1.05)
    room("ReflectionRoom",-190,270,110,60,24,{n=-190,nw=24,e=270,ew=24},false,true)
    flooded("ReflectionWater",-190,270,88,42,4.8)
    dryLedge("ReflectionNorth",-190,245,110,10,1.05)
    dryLedge("ReflectionSouth",-190,295,110,10,1.05)
    dryLedge("ReflectionWest",-240,270,10,42,1.05)
    dryLedge("ReflectionEast",-140,270,10,42,1.05)
    for _,z in ipairs({255,285}) do frostedPanel("ReflectionScreen",CFrame.new(-244.4,9,z)*CFrame.Angles(0,math.rad(90),0),Vector3.new(5,13,.35),false) end

    linkX("ReflectionToSunkenLink",-77.5,270,115,24,16,true)
    room("SunkenGallery",60,277,160,100,25,{n=60,nw=28,w=270,ww=24},false,true)
    replaceCeilingWithOpenings("SunkenGallery",60,277,160,100,25,false,{
        {name="SunkenLightWellA",x=18,z=305,w=17,d=7},
        {name="SunkenLightWellB",x=82,z=240,w=17,d=7},
    })
    flooded("SunkenGalleryWater",60,277,132,76,5.6)
    dryLedge("SunkenNorth",60,234,160,14,1.05)
    dryLedge("SunkenSouth",60,320,160,14,1.05)
    dryLedge("SunkenWest",-13,277,14,76,1.05)
    dryLedge("SunkenEast",133,277,14,76,1.05)
    dryLedge("SunkenIsland",60,277,34,28,1.1)
    dryLedge("SunkenBridge",23,277,40,8,1.1)
    for _,p in ipairs({Vector3.new(25,0,252),Vector3.new(95,0,302)}) do tiledColumn(parent,p,5,25) end
    decorativePoolSlide("SunkenGalleryOverheadSlide",{
        Vector3.new(96,20,245),
        Vector3.new(108,19,250),
        Vector3.new(113,19,258),
        Vector3.new(106,20,266),
    },2.6,overheadBlue,overheadAquaLight,25,true)

    room("ExitChamber",320,200,100,100,24,{w=200,ww=28},false)
    frostedPanel("ExitChamberScreen",CFrame.new(369.4,9,200)*CFrame.Angles(0,math.rad(-90),0),Vector3.new(6,15,.35),false)

    for _,p in ipairs({
        Vector3.new(-340,21.4,-300),Vector3.new(-225,21.4,-160),
        Vector3.new(-165,14.3,-160),Vector3.new(-40,27.4,95),
        Vector3.new(125,17.4,200),Vector3.new(-190,17.3,95),
        Vector3.new(-190,15.3,225),Vector3.new(320,23.4,200)
    }) do lightPanel(lamps,p,Vector3.new(16,.25,5)) end
end

local PARTY_WINDOW_IMAGE="rbxassetid://102207536891070"
local PARTY_DISCO_TILE_IMAGE="rbxassetid://133427598777423"
local PARTY_BLACK_MARBLE_IMAGE="rbxassetid://119157426585961"
local PARTY_MUSIC_ID="rbxassetid://129828529013630"

local function buildSecretPoolParty(world,geometry,lamps)
	local TweenService=game:GetService("TweenService")
	local model=Instance.new("Model")
	model.Name="SecretPoolParty"
	model.Parent=world
	model:SetAttribute("SecretEasterEgg",true)
	model:SetAttribute("GeneratedWithLevel2",true)

	local ox,oz=540,-300
	local tile=Color3.fromRGB(226,230,222)
	local dark=Color3.fromRGB(12,15,25)
	local cyan=Color3.fromRGB(43,242,224)
	local pink=Color3.fromRGB(255,80,205)
	local violet=Color3.fromRGB(139,91,255)
	local blue=Color3.fromRGB(52,137,255)
	local marble=Color3.fromRGB(220,226,234)

	-- Backrooms-tiled shell, kept far enough from the normal map that club audio is local.
	tiledPart(model,"PartyFloor",CFrame.new(ox,-.25,oz),Vector3.new(140,.5,100),Color3.fromRGB(185,215,218),{Enum.NormalId.Top},10)
	tiledPart(model,"PartyCeiling",CFrame.new(ox,25,oz),Vector3.new(140,.8,100),tile,{Enum.NormalId.Bottom},10)
	-- North wall is split around two real restroom entrances.
	tiledPart(model,"PartyNorthWallWest",CFrame.new(ox-52.25,12.5,oz-50),Vector3.new(35.5,25,1),tile,nil,10)
	tiledPart(model,"PartyNorthWallMiddle",CFrame.new(ox-18.5,12.5,oz-50),Vector3.new(14,25,1),tile,nil,10)
	tiledPart(model,"PartyNorthWallEast",CFrame.new(ox+33.75,12.5,oz-50),Vector3.new(72.5,25,1),tile,nil,10)
	tiledPart(model,"MensRestroomDoorHeader",CFrame.new(ox-30,18,oz-50),Vector3.new(9,14,1),tile,nil,8)
	tiledPart(model,"WomensRestroomDoorHeader",CFrame.new(ox-7,18,oz-50),Vector3.new(9,14,1),tile,nil,8)
	tiledPart(model,"PartySouthWall",CFrame.new(ox,12.5,oz+50),Vector3.new(140,25,1),tile,nil,10)
	tiledPart(model,"PartyWestWallNorth",CFrame.new(ox-70,12.5,oz-40),Vector3.new(1,25,20),tile,nil,10)
	tiledPart(model,"PartyWestWallSouth",CFrame.new(ox-70,12.5,oz+12),Vector3.new(1,25,76),tile,nil,10)
	tiledPart(model,"PartyWestDoorHeader",CFrame.new(ox-70,20.5,oz-29),Vector3.new(1,9,18),tile,nil,10)
	tiledPart(model,"PartyEastWallNorth",CFrame.new(ox+70,12.5,oz-44),Vector3.new(1,25,12),tile,nil,10)
	tiledPart(model,"PartyEastWallSouth",CFrame.new(ox+70,12.5,oz+44),Vector3.new(1,25,12),tile,nil,10)
	tiledPart(model,"PartyWindowHeader",CFrame.new(ox+70,22.5,oz),Vector3.new(1,5,76),tile,nil,10)
	tiledPart(model,"PartyWindowSill",CFrame.new(ox+70,1.75,oz),Vector3.new(1,3.5,76),tile,nil,10)

	-- One correctly rounded UI composition replaces the old four physical bars,
	-- which could separate and look diagonal when viewed close to the east wall.
	local windowBack=part(model,"UniverseWindowRecess",CFrame.new(ox+69.56,11.7,oz),
		Vector3.new(.72,20.5,74.5),Color3.fromRGB(5,8,18),Enum.Material.Metal)
	windowBack.CanCollide=false
	windowBack.Reflectance=.08
	local window=part(model,"UniversePanoramaWindow",CFrame.new(ox+69.1,11.7,oz),
		Vector3.new(.24,19.2,73.2),Color3.new(1,1,1),Enum.Material.SmoothPlastic,1)
	window.CanCollide=false
	window.CastShadow=false
	local gui=Instance.new("SurfaceGui")
	gui.Name="UniverseView"
	gui.Face=Enum.NormalId.Left
	gui.CanvasSize=Vector2.new(1800,600)
	gui.LightInfluence=0
	gui.Brightness=1.2
	gui.SizingMode=Enum.SurfaceGuiSizingMode.FixedSize
	gui.Parent=window
	local outer=Instance.new("Frame")
	outer.Name="RoundedUniverseFrame"
	outer.Size=UDim2.fromScale(1,1)
	outer.BackgroundColor3=Color3.fromRGB(5,8,20)
	outer.BorderSizePixel=0
	outer.Parent=gui
	local outerCorner=Instance.new("UICorner")
	outerCorner.CornerRadius=UDim.new(.105,0)
	outerCorner.Parent=outer
	local outerStroke=Instance.new("UIStroke")
	outerStroke.ApplyStrokeMode=Enum.ApplyStrokeMode.Border
	outerStroke.Thickness=18
	outerStroke.Color=cyan
	outerStroke.Transparency=.03
	outerStroke.Parent=outer
	local strokeGradient=Instance.new("UIGradient")
	strokeGradient.Color=ColorSequence.new({
		ColorSequenceKeypoint.new(0,pink),
		ColorSequenceKeypoint.new(.35,cyan),
		ColorSequenceKeypoint.new(.7,violet),
		ColorSequenceKeypoint.new(1,cyan),
	})
	strokeGradient.Parent=outerStroke
	local image=Instance.new("ImageLabel")
	image.Name="CosmicPanorama"
	image.Position=UDim2.fromScale(.018,.045)
	image.Size=UDim2.fromScale(.964,.91)
	image.BackgroundColor3=dark
	image.BorderSizePixel=0
	image.Image=PARTY_WINDOW_IMAGE
	image.ScaleType=Enum.ScaleType.Crop
	image.Parent=outer
	local imageCorner=Instance.new("UICorner")
	imageCorner.CornerRadius=UDim.new(.09,0)
	imageCorner.Parent=image
	local innerStroke=Instance.new("UIStroke")
	innerStroke.ApplyStrokeMode=Enum.ApplyStrokeMode.Border
	innerStroke.Thickness=6
	innerStroke.Color=Color3.fromRGB(187,111,255)
	innerStroke.Transparency=.1
	innerStroke.Parent=image

	-- Reflective shallow party pool and broad tiled coping.
	local poolBottom=tiledPart(model,"PartyPoolBottom",CFrame.new(ox+2,.1,oz+10),
		Vector3.new(76,.3,45),Color3.fromRGB(99,183,194),{Enum.NormalId.Top},7)
	poolBottom.Reflectance=.1
	local water=part(model,"PartyPoolWater",CFrame.new(ox+2,.7,oz+10),
		Vector3.new(73.5,1.15,42.5),Color3.fromRGB(40,175,194),Enum.Material.Glass,.28)
	water.CanCollide=false
	water.CastShadow=false
	water:SetAttribute("ShallowWalkWater",true)
	-- Shortened straight coping and glazed cylindrical corner caps make the
	-- pool read as one rounded basin instead of four intersecting square beams.
	for _,spec in ipairs({
		{Vector3.new(ox+2,1,oz-13),Vector3.new(76,2,2.4)},
		{Vector3.new(ox+2,1,oz+33),Vector3.new(76,2,2.4)},
		{Vector3.new(ox-39,1,oz+10),Vector3.new(2.4,2,44)},
		{Vector3.new(ox+43,1,oz+10),Vector3.new(2.4,2,44)},
	}) do
		local coping=tiledPart(model,"PartyPoolCoping",CFrame.new(spec[1]),spec[2],tile,nil,8)
		coping.Reflectance=.12
	end
	for _,cornerPosition in ipairs({
		Vector3.new(ox-39,1,oz-13),Vector3.new(ox+43,1,oz-13),
		Vector3.new(ox-39,1,oz+33),Vector3.new(ox+43,1,oz+33),
	}) do
		local cap=part(model,"PartyPoolRoundedCorner",
			CFrame.new(cornerPosition)*CFrame.Angles(0,0,math.rad(90)),
			Vector3.new(2,4.8,4.8),tile,Enum.Material.SmoothPlastic)
		cap.Shape=Enum.PartType.Cylinder
		cap.Reflectance=.14
	end

	-- Large circular ceiling feature and smaller summer-neon fixtures.
	local ceilingDisc=part(model,"PartyCeilingDisc",CFrame.new(ox,24.25,oz-3)*CFrame.Angles(0,0,math.rad(90)),
		Vector3.new(1.1,30,30),Color3.fromRGB(32,57,104),Enum.Material.SmoothPlastic)
	ceilingDisc.Shape=Enum.PartType.Cylinder
	ceilingDisc.CanCollide=false
	local colorParts={}
	local colorLights={}
	for i=0,19 do
		local a=i*math.pi*2/20
		local ring=part(model,"SummerNeonCeilingRing",
			CFrame.new(ox+math.cos(a)*15,23.55,oz-3+math.sin(a)*15),
			Vector3.new(4.9,.32,1.05),i%2==0 and cyan or pink,Enum.Material.Neon)
		ring.CFrame=CFrame.new(ring.Position)*CFrame.Angles(0,-a,0)
		ring.CanCollide=false
		table.insert(colorParts,ring)
	end
	for _,p in ipairs({
		Vector3.new(ox-52,23.8,oz-37),Vector3.new(ox+52,23.8,oz-37),
		Vector3.new(ox-52,23.8,oz+37),Vector3.new(ox+52,23.8,oz+37),
	}) do
		local lamp=part(model,"SummerNeonPanel",CFrame.new(p),Vector3.new(15,.35,5),cyan,Enum.Material.Neon)
		lamp.CanCollide=false
		local light=Instance.new("PointLight")
		light.Brightness=2.1
		light.Range=38
		light.Color=lamp.Color
		light.Shadows=false
		light.Parent=lamp
		table.insert(colorParts,lamp)
		table.insert(colorLights,light)
	end

	-- A persistent AI-generated museum-quality marble bust replaces the old
	-- primitive sphere construction. The invisible root is placed at the
	-- bottom of the asset, so it sits cleanly on the neon pedestal.
	local statue=Instance.new("Model")
	statue.Name="ClassicalPoolPartyStatue"
	statue.Parent=model
	statue:SetAttribute("HighDetailPartyStatue",true)
	local statueCenter=Vector3.new(ox+43,0,oz-30)
	local planter=part(statue,"StatuePlanter",CFrame.new(statueCenter+Vector3.new(0,2.2,0))*CFrame.Angles(0,0,math.rad(90)),
		Vector3.new(4.4,27,27),Color3.fromRGB(201,215,218),Enum.Material.SmoothPlastic)
	planter.Shape=Enum.PartType.Cylinder
	planter.Reflectance=.12
	local planterGlow=part(statue,"StatuePlanterGlow",CFrame.new(statueCenter+Vector3.new(0,4.5,0))*CFrame.Angles(0,0,math.rad(90)),
		Vector3.new(.35,28,28),cyan,Enum.Material.Neon)
	planterGlow.Shape=Enum.PartType.Cylinder
	planterGlow.CanCollide=false
	local pedestal=part(statue,"FlutedMarblePedestal",CFrame.new(statueCenter+Vector3.new(0,7,0))*CFrame.Angles(0,0,math.rad(90)),
		Vector3.new(5,10.5,10.5),marble,Enum.Material.Marble)
	pedestal.Shape=Enum.PartType.Cylinder
	pedestal.Reflectance=.05
	local templateFolder=game:GetService("ServerStorage"):FindFirstChild("Level2Assets")
	local template=templateFolder and templateFolder:FindFirstChild("SecretPartyStatueTemplate")
	if template then
		local bust=template:Clone()
		bust.Name="MuseumQualityMarbleBust"
		bust.Parent=statue
		local basePosition=statueCenter+Vector3.new(0,9.55,0)
		bust:PivotTo(CFrame.lookAt(basePosition,Vector3.new(ox,basePosition.Y,oz)))
		for _,item in ipairs(bust:GetDescendants()) do
			if item:IsA("BasePart") then
				item.Anchored=true
				item.CanCollide=false
				item.CastShadow=true
			end
		end
	else
		local fallback=part(statue,"MarbleBustFallback",CFrame.new(statueCenter+Vector3.new(0,14,0)),
			Vector3.new(8,10,6),marble,Enum.Material.Marble)
		fallback.Shape=Enum.PartType.Ball
	end
	for _,zOffset in ipairs({-9.4,9.4}) do
		for i=1,4 do
			local leaf=part(statue,"PlanterLeaf",
				CFrame.new(statueCenter+Vector3.new(math.sin(i)*2.3,6+i*.75,zOffset+math.cos(i)*2)),
				Vector3.new(.55,4.5,1.3),Color3.fromRGB(20,85+10*i,67),Enum.Material.SmoothPlastic)
			leaf.Shape=Enum.PartType.Ball
			leaf.CFrame=leaf.CFrame*CFrame.Angles(math.rad((i-2)*14),0,math.rad((i%2==0 and 1 or -1)*22))
			leaf.CanCollide=false
		end
	end

	-- Proper tangent-built C-shaped bar. Forty-two narrow sections create a
	-- smooth curve; the old version pointed each wide block toward the centre
	-- and therefore read as a broken star instead of a round bar.
	local barCenter=Vector3.new(ox-50,0,oz+31)
	local BAR_SEGMENTS=42
	local BAR_RADIUS=11.4
	local function blackMarbleSurface(surface,scale)
		surface.Material=Enum.Material.SmoothPlastic
		surface.Color=Color3.fromRGB(18,18,21)
		surface.Reflectance=.22
		surface:SetAttribute("BlackMarbleBar",true)
		for _,face in ipairs({
			Enum.NormalId.Top,Enum.NormalId.Front,Enum.NormalId.Back,
			Enum.NormalId.Left,Enum.NormalId.Right,
		}) do
			local texture=Instance.new("Texture")
			texture.Name="BlackMarbleWhiteVein"
			texture.Texture=PARTY_BLACK_MARBLE_IMAGE
			texture.Face=face
			texture.StudsPerTileU=scale
			texture.StudsPerTileV=scale
			texture.Parent=surface
		end
	end
	for i=0,BAR_SEGMENTS-1 do
		local a=i*math.pi*2/BAR_SEGMENTS
		-- A generous rear service opening keeps the C-shape readable.
		if not (i>=15 and i<=20) then
			local tangent=CFrame.new(barCenter+Vector3.new(math.cos(a)*BAR_RADIUS,4.85,math.sin(a)*BAR_RADIUS))
				*CFrame.Angles(0,-a+math.pi/2,0)
			local top=part(model,"BlackMarbleBarTop",tangent,
				Vector3.new(1.92,.72,5.3),Color3.fromRGB(14,14,17),Enum.Material.SmoothPlastic)
			blackMarbleSurface(top,7)
			local front=part(model,"BlackMarbleBarFront",tangent*CFrame.new(0,-2.15,.48),
				Vector3.new(1.9,3.6,4.15),Color3.fromRGB(12,13,17),Enum.Material.SmoothPlastic)
			blackMarbleSurface(front,8)
			local plinth=part(model,"BlackMarbleBarPlinth",tangent*CFrame.new(0,-4.35,.42),
				Vector3.new(1.94,.5,4.45),Color3.fromRGB(8,9,12),Enum.Material.SmoothPlastic)
			blackMarbleSurface(plinth,7)
			local glow=part(model,"RoundBarGlow",tangent*CFrame.new(0,-3.82,2.18),
				Vector3.new(1.82,.22,.24),i%3==0 and pink or (i%3==1 and cyan or violet),Enum.Material.Neon)
			glow.CanCollide=false
			table.insert(colorParts,glow)
		end
	end
	-- A lower inner service counter makes the centre feel functional rather
	-- than like an empty hole, without blocking the bartender entrance.
	for i=0,29 do
		local a=i*math.pi*2/30
		if not (i>=11 and i<=15) then
			local innerCF=CFrame.new(barCenter+Vector3.new(math.cos(a)*6.4,3.8,math.sin(a)*6.4))
				*CFrame.Angles(0,-a+math.pi/2,0)
			local inner=part(model,"InnerMarbleServiceCounter",innerCF,
				Vector3.new(1.55,.55,2.6),Color3.fromRGB(13,13,16),Enum.Material.SmoothPlastic)
			blackMarbleSurface(inner,6)
		end
	end
	-- Correctly proportioned stools: seat tops sit below the 5.2-stud counter,
	-- with slim chrome stems, weighted bases, foot rests and compact back pads.
	for _,degrees in ipairs({18,62,198,232,270,306}) do
		local a=math.rad(degrees)
		local stoolPos=barCenter+Vector3.new(math.cos(a)*17,0,math.sin(a)*17)
		local facing=CFrame.lookAt(stoolPos,barCenter)
		local base=part(model,"BarStoolWeightedBase",
			CFrame.new(stoolPos+Vector3.new(0,.22,0))*CFrame.Angles(0,0,math.rad(90)),
			Vector3.new(.42,2.6,2.6),Color3.fromRGB(124,130,142),Enum.Material.Metal)
		base.Shape=Enum.PartType.Cylinder
		base.Reflectance=.38
		local post=part(model,"BarStoolChromePost",
			CFrame.new(stoolPos+Vector3.new(0,1.95,0))*CFrame.Angles(0,0,math.rad(90)),
			Vector3.new(3.25,.38,.38),Color3.fromRGB(168,174,185),Enum.Material.Metal)
		post.Shape=Enum.PartType.Cylinder
		post.Reflectance=.45
		local footrest=part(model,"BarStoolFootRest",
			facing*CFrame.new(0,1.35,-.58),Vector3.new(2.35,.18,.18),
			Color3.fromRGB(158,164,175),Enum.Material.Metal)
		footrest.Reflectance=.4
		local seat=part(model,"BarStoolPaddedSeat",
			CFrame.new(stoolPos+Vector3.new(0,3.78,0))*CFrame.Angles(0,0,math.rad(90)),
			Vector3.new(.62,3.15,3.15),Color3.fromRGB(23,25,33),Enum.Material.Leather)
		seat.Shape=Enum.PartType.Cylinder
		seat.Reflectance=.08
		local back=part(model,"BarStoolBackPad",
			facing*CFrame.new(0,4.75,1.35)*CFrame.Angles(math.rad(-8),0,0),
			Vector3.new(3.05,1.65,.52),Color3.fromRGB(23,25,33),Enum.Material.Leather)
		back.Reflectance=.08
	end

	-- Fully modelled restrooms replace the former fake locked door panels.
	-- The annex sits behind the north wall and remains physically walkable.
	local restroomDark=Color3.fromRGB(25,28,38)
	local fixtureWhite=Color3.fromRGB(231,235,237)
	local chrome=Color3.fromRGB(155,164,176)
	local mensX,womensX=ox-30,ox-2
	local restroomZ=oz-66
	tiledPart(model,"RestroomAnnexFloor",CFrame.new(ox-13.5,-.25,restroomZ),
		Vector3.new(55,.5,32),tile,{Enum.NormalId.Top},8)
	tiledPart(model,"RestroomAnnexCeiling",CFrame.new(ox-13.5,15,restroomZ),
		Vector3.new(55,.6,32),tile,{Enum.NormalId.Bottom},8)
	tiledPart(model,"MensRestroomWestWall",CFrame.new(ox-41,7.5,restroomZ),
		Vector3.new(1,15,32),tile,nil,8)
	tiledPart(model,"RestroomDividerWall",CFrame.new(ox-19,7.5,restroomZ),
		Vector3.new(1,15,32),tile,nil,8)
	tiledPart(model,"WomensRestroomEastWall",CFrame.new(ox+14.5,7.5,restroomZ),
		Vector3.new(1,15,32),tile,nil,8)
	tiledPart(model,"RestroomNorthWall",CFrame.new(ox-13.5,7.5,oz-82),
		Vector3.new(55,15,1),tile,nil,8)
	local function restroomLight(name,position,color)
		local lamp=part(model,name,CFrame.new(position),Vector3.new(12,.3,4),color,Enum.Material.Neon)
		lamp.CanCollide=false
		local light=Instance.new("PointLight")
		light.Color=color
		light.Brightness=1.6
		light.Range=24
		light.Shadows=false
		light.Parent=lamp
		table.insert(colorParts,lamp)
		table.insert(colorLights,light)
	end
	restroomLight("MensRestroomCeilingLight",Vector3.new(mensX,14.4,restroomZ),blue)
	restroomLight("WomensRestroomCeilingLight",Vector3.new(womensX,14.4,restroomZ),pink)
	local function restroomEntrance(prefix,x,title,accent)
		local leftJamb=tiledPart(model,prefix.."LeftJamb",CFrame.new(x-4.5,6,oz-49.7),
			Vector3.new(.8,12,1.4),tile,nil,6)
		local rightJamb=tiledPart(model,prefix.."RightJamb",CFrame.new(x+4.5,6,oz-49.7),
			Vector3.new(.8,12,1.4),tile,nil,6)
		local hinge=CFrame.new(x-4.05,5.4,oz-50.25)
		local door=part(model,prefix.."OpenDoor",
			hinge*CFrame.Angles(0,math.rad(68),0)*CFrame.new(3.85,0,0),
			Vector3.new(7.7,10.8,.55),restroomDark,Enum.Material.Metal)
		door.Reflectance=.18
		door:SetAttribute("RestroomDoorOpen",true)
		for _,face in ipairs({Enum.NormalId.Front,Enum.NormalId.Back}) do
			local marbleTexture=Instance.new("Texture")
			marbleTexture.Name="RestroomDoorBlackMarble"
			marbleTexture.Texture=PARTY_BLACK_MARBLE_IMAGE
			marbleTexture.Face=face
			marbleTexture.StudsPerTileU=6
			marbleTexture.StudsPerTileV=6
			marbleTexture.Parent=door
		end
		local inset=part(model,prefix.."DoorAccentBand",door.CFrame*CFrame.new(0,-3.55,-.31),
			Vector3.new(5.8,.18,.08),accent,Enum.Material.Neon)
		inset.CanCollide=false
		inset.Transparency=.08
		local edgeGlow=part(model,prefix.."DoorEdgeGlow",door.CFrame*CFrame.new(-3.62,0,-.31),
			Vector3.new(.14,9.7,.08),accent,Enum.Material.Neon)
		edgeGlow.CanCollide=false
		local portholeCF=door.CFrame*CFrame.new(0,2.45,0)*CFrame.Angles(0,math.rad(90),0)
		local portholeRim=part(model,prefix.."DoorPortholeRim",portholeCF,
			Vector3.new(.72,2.65,2.65),accent,Enum.Material.Neon)
		portholeRim.Shape=Enum.PartType.Cylinder
		portholeRim.CanCollide=false
		local portholeGlass=part(model,prefix.."DoorPortholeGlass",portholeCF,
			Vector3.new(.76,1.85,1.85),Color3.fromRGB(34,49,65),Enum.Material.Glass,.22)
		portholeGlass.Shape=Enum.PartType.Cylinder
		portholeGlass.CanCollide=false
		local handle=part(model,prefix.."DoorHandle",door.CFrame*CFrame.new(2.65,0,-.55),
			Vector3.new(.38,.38,.38),chrome,Enum.Material.Metal)
		handle.Shape=Enum.PartType.Ball
		handle.CanCollide=false
		local sign=part(model,prefix.."RestroomSign",CFrame.new(x,12.5,oz-49.35),
			Vector3.new(8.2,2.8,.28),accent,Enum.Material.Neon)
		sign.CanCollide=false
		label(sign,Enum.NormalId.Back,title,"ÅBEN",Color3.new(1,1,1))
		return door
	end
	restroomEntrance("Mens",mensX,"HERRE",blue)
	restroomEntrance("Womens",ox-7,"DAME",pink)
	local function toiletFixture(prefix,center,accent,doorAngle)
		local halfWidth=3.25
		tiledPart(model,prefix.."LeftPartition",CFrame.new(center.X-halfWidth,4.5,center.Z),
			Vector3.new(.38,9,9),tile,nil,5)
		tiledPart(model,prefix.."RightPartition",CFrame.new(center.X+halfWidth,4.5,center.Z),
			Vector3.new(.38,9,9),tile,nil,5)
		local hinge=CFrame.new(center.X-halfWidth+.25,3.9,center.Z+4.45)
		local stallDoor=part(model,prefix.."StallDoor",
			hinge*CFrame.Angles(0,math.rad(doorAngle),0)*CFrame.new(2.65,0,0),
			Vector3.new(5.3,7.5,.35),restroomDark,Enum.Material.Metal)
		stallDoor:SetAttribute("StallDoorOpen",true)
		local doorAccent=part(model,prefix.."StallDoorAccent",stallDoor.CFrame*CFrame.new(0,0,-.2),
			Vector3.new(3.9,5.8,.05),accent,Enum.Material.SmoothPlastic)
		doorAccent.CanCollide=false
		doorAccent.Transparency=.6
		local tank=part(model,prefix.."ToiletTank",CFrame.new(center.X,2.45,center.Z-3.25),
			Vector3.new(3.2,3,1.45),fixtureWhite,Enum.Material.CeramicTiles)
		tank.Reflectance=.08
		local base=part(model,prefix.."ToiletBase",
			CFrame.new(center.X,1.05,center.Z-1.75)*CFrame.Angles(0,0,math.rad(90)),
			Vector3.new(1.7,2.7,2.7),fixtureWhite,Enum.Material.CeramicTiles)
		base.Shape=Enum.PartType.Cylinder
		local rim=part(model,prefix.."ToiletRim",
			CFrame.new(center.X,1.72,center.Z-1.25)*CFrame.Angles(0,0,math.rad(90)),
			Vector3.new(.28,3.25,3.8),fixtureWhite,Enum.Material.SmoothPlastic)
		rim.Shape=Enum.PartType.Cylinder
		local bowlWater=part(model,prefix.."ToiletBowlWater",
			CFrame.new(center.X,1.78,center.Z-1.2)*CFrame.Angles(0,0,math.rad(90)),
			Vector3.new(.12,2.05,2.45),Color3.fromRGB(75,190,213),Enum.Material.Glass,.18)
		bowlWater.Shape=Enum.PartType.Cylinder
		bowlWater.CanCollide=false
		local flush=part(model,prefix.."FlushButton",CFrame.new(center.X,3.15,center.Z-2.49),
			Vector3.new(.55,.3,.18),chrome,Enum.Material.Metal)
		flush.CanCollide=false
	end
	-- Two men's stalls.
	toiletFixture("MensStall1",Vector3.new(ox-36,0,oz-76.5),blue,62)
	toiletFixture("MensStall2",Vector3.new(ox-27.5,0,oz-76.5),blue,62)
	-- Four women's stalls.
	for index,x in ipairs({ox-15,ox-7.7,ox-.4,ox+6.9}) do
		toiletFixture("WomensStall"..index,Vector3.new(x,0,oz-76.5),pink,58)
	end
	local function urinal(prefix,z)
		local back=part(model,prefix.."UrinalBack",CFrame.new(ox-40.25,2.65,z),
			Vector3.new(.45,4.3,3.2),fixtureWhite,Enum.Material.CeramicTiles)
		back.Reflectance=.08
		local bowl=part(model,prefix.."UrinalBowl",CFrame.new(ox-39.55,1.65,z),
			Vector3.new(1.45,2.4,2.55),fixtureWhite,Enum.Material.CeramicTiles)
		bowl.Shape=Enum.PartType.Ball
		local water=part(model,prefix.."UrinalWater",CFrame.new(ox-38.78,1.38,z),
			Vector3.new(.12,1.15,1.35),Color3.fromRGB(71,181,208),Enum.Material.Glass,.2)
		water.CanCollide=false
		local pipe=part(model,prefix.."FlushPipe",
			CFrame.new(ox-40,4.85,z)*CFrame.Angles(0,0,math.rad(90)),
			Vector3.new(1.5,.22,.22),chrome,Enum.Material.Metal)
		pipe.Shape=Enum.PartType.Cylinder
	end
	urinal("MensUrinal1",oz-57.5)
	urinal("MensUrinal2",oz-64)
	local function sinkAndMirror(prefix,x,z,rotation,accent)
		local cf=CFrame.new(x,2.55,z)*CFrame.Angles(0,rotation,0)
		local cabinet=part(model,prefix.."SinkCabinet",cf,Vector3.new(5.2,4,2),restroomDark,Enum.Material.Metal)
		local basin=part(model,prefix.."SinkBasin",cf*CFrame.new(0,2.1,0),
			Vector3.new(5.5,.55,2.5),fixtureWhite,Enum.Material.CeramicTiles)
		basin.Reflectance=.1
		local faucet=part(model,prefix.."Faucet",cf*CFrame.new(0,2.75,-.45),
			Vector3.new(.3,1.3,.3),chrome,Enum.Material.Metal)
		local mirror=part(model,prefix.."Mirror",cf*CFrame.new(0,6.1,.95),
			Vector3.new(5.5,5,.18),Color3.fromRGB(151,177,190),Enum.Material.Glass,.12)
		mirror.Reflectance=.35
		local mirrorGlow=part(model,prefix.."MirrorGlow",mirror.CFrame*CFrame.new(0,0,.12),
			Vector3.new(5.9,5.4,.08),accent,Enum.Material.Neon,.25)
		mirrorGlow.CanCollide=false
	end
	sinkAndMirror("MensSink",ox-21.1,oz-58,math.rad(90),blue)
	sinkAndMirror("WomensSink1",ox+13.8,oz-58,math.rad(-90),pink)
	sinkAndMirror("WomensSink2",ox+13.8,oz-66,math.rad(-90),pink)

	-- Replace every ordinary generated tile layer in the secret room with the
	-- new seamless glossy disco tile, including floor, shell and pool coping.
	for _,surface in ipairs(model:GetDescendants()) do
		if surface:IsA("BasePart") and surface:FindFirstChild("PoolTileTexture") then
			for _,child in ipairs(surface:GetChildren()) do
				if child:IsA("Texture") then child:Destroy() end
			end
			surface.Material=Enum.Material.SmoothPlastic
			surface.Color=Color3.new(1,1,1)
			surface.Reflectance=math.max(surface.Reflectance,.09)
			for _,face in ipairs({
				Enum.NormalId.Front,Enum.NormalId.Back,
				Enum.NormalId.Left,Enum.NormalId.Right,
				Enum.NormalId.Top,Enum.NormalId.Bottom,
			}) do
				local discoTile=Instance.new("Texture")
				discoTile.Name="PartyDiscoTileSurface"
				discoTile.Texture=PARTY_DISCO_TILE_IMAGE
				discoTile.Face=face
				discoTile.StudsPerTileU=12
				discoTile.StudsPerTileV=12
				discoTile.Parent=surface
			end
			surface:SetAttribute("GlossyDiscoPoolTile",true)
		end
	end

	-- Every physical speaker is now a real spatial emitter. The four instances
	-- start together and are periodically phase-corrected to the first speaker.
	local partyMusicEmitters={}
	for index,p in ipairs({
		Vector3.new(ox-60,21.8,oz-41),Vector3.new(ox+60,21.8,oz-41),
		Vector3.new(ox-60,21.8,oz+41),Vector3.new(ox+60,21.8,oz+41),
	}) do
		local speaker=part(model,"CeilingSpeaker"..index,CFrame.lookAt(p,Vector3.new(ox,8,oz)),
			Vector3.new(4.6,3.2,2.6),Color3.fromRGB(13,15,20),Enum.Material.Metal)
		speaker:SetAttribute("PartyMusicEmitter",true)
		local cone=part(model,"SpeakerCone",speaker.CFrame*CFrame.new(0,0,-1.4),
			Vector3.new(2.2,2.2,.35),Color3.fromRGB(48,52,61),Enum.Material.SmoothPlastic)
		cone.Shape=Enum.PartType.Cylinder
		cone.CanCollide=false
		local music=Instance.new("Sound")
		music.Name="MidnightMotionPartyLoop"..index
		music.SoundId=PARTY_MUSIC_ID
		music.Looped=true
		music.Volume=.34
		music.RollOffMode=Enum.RollOffMode.InverseTapered
		music.RollOffMinDistance=10
		music.RollOffMaxDistance=78
		music.EmitterSize=18
		music:SetAttribute("SynchronizedPartySpeaker",true)
		music.Parent=speaker
		table.insert(partyMusicEmitters,music)
	end
	if PARTY_MUSIC_ID~="" then
		for _,music in ipairs(partyMusicEmitters) do
			music.TimePosition=0
			music:Play()
		end
		task.spawn(function()
			while model.Parent and partyMusicEmitters[1] and partyMusicEmitters[1].Parent do
				task.wait(3)
				local leader=partyMusicEmitters[1]
				if not leader.Playing then leader:Play() end
				local leaderTime=leader.TimePosition
				for index=2,#partyMusicEmitters do
					local music=partyMusicEmitters[index]
					if music.Parent then
						if not music.Playing then music:Play() end
						if math.abs(music.TimePosition-leaderTime)>.12 then
							music.TimePosition=leaderTime
						end
					end
				end
			end
		end)
	end

	-- Convert the middle start-room wall light into a two-way secret portal.
	local entrancePanel
	for _,candidate in ipairs(geometry:GetDescendants()) do
		if candidate:IsA("BasePart") and candidate.Name=="ArrivalWallScreen"
			and math.abs(candidate.Position.Z+300)<3 then
			entrancePanel=candidate
			break
		end
	end
	if entrancePanel then
		entrancePanel.Name="SecretPartyEntrancePanel"
		entrancePanel.CanCollide=false
		entrancePanel:SetAttribute("SecretPortal",true)
		local blinkLight=entrancePanel:FindFirstChildOfClass("PointLight") or Instance.new("PointLight")
		blinkLight.Color=cyan
		blinkLight.Brightness=1.2
		blinkLight.Range=18
		blinkLight.Parent=entrancePanel
		table.insert(colorParts,entrancePanel)
		table.insert(colorLights,blinkLight)
	end
	local entranceTrigger=part(model,"SecretEntranceTrigger",CFrame.new(-387.5,7.5,-300),
		Vector3.new(4,14,8),cyan,Enum.Material.Neon,1)
	entranceTrigger.CanCollide=false
	local returnPanel=part(model,"SecretReturnLightPanel",CFrame.new(ox-69.4,8,oz-29),
		Vector3.new(.35,14,14),cyan,Enum.Material.Neon,.08)
	returnPanel.CanCollide=false
	local returnTrigger=part(model,"SecretReturnTrigger",CFrame.new(ox-67.5,7.5,oz-29),
		Vector3.new(4,14,12),cyan,Enum.Material.Neon,1)
	returnTrigger.CanCollide=false
	local cooldown={}
	local function teleport(hit,target)
		local character=hit:FindFirstAncestorOfClass("Model")
		local player=character and Players:GetPlayerFromCharacter(character)
		local root=character and (character:FindFirstChild("HumanoidRootPart") or character.PrimaryPart)
		if not player or not root then return end
		local now=os.clock()
		if cooldown[player] and now-cooldown[player]<2 then return end
		cooldown[player]=now
		root.AssemblyLinearVelocity=Vector3.zero
		root.CFrame=CFrame.new(target)
	end
	entranceTrigger.Touched:Connect(function(hit) teleport(hit,Vector3.new(ox-62,3,oz-29)) end)
	returnTrigger.Touched:Connect(function(hit) teleport(hit,Vector3.new(-381,3,-300)) end)

	-- Slow continuous summer-neon ambience: one or more colors are always lit.
	task.spawn(function()
		local palette={cyan,pink,violet,blue,Color3.fromRGB(255,151,82)}
		local step=1
		while model.Parent do
			step=step%#palette+1
			for index,p in ipairs(colorParts) do
				local target=palette[((step+index-2)%#palette)+1]
				TweenService:Create(p,TweenInfo.new(4.8,Enum.EasingStyle.Sine,Enum.EasingDirection.InOut),{Color=target}):Play()
			end
			for index,l in ipairs(colorLights) do
				local target=palette[((step+index-2)%#palette)+1]
				TweenService:Create(l,TweenInfo.new(4.8,Enum.EasingStyle.Sine,Enum.EasingDirection.InOut),{Color=target,Brightness=2.1}):Play()
			end
			task.wait(5)
		end
	end)
	if entrancePanel then
		task.spawn(function()
			while entrancePanel.Parent do
				task.wait(10)
				local original=entrancePanel.Color
				local flash=TweenService:Create(entrancePanel,TweenInfo.new(.16,Enum.EasingStyle.Quad),{Color=Color3.new(1,1,1)})
				flash:Play(); flash.Completed:Wait()
				TweenService:Create(entrancePanel,TweenInfo.new(.45,Enum.EasingStyle.Sine),{Color=original}):Play()
			end
		end)
	end
	return model
end

function Generator.Build()
	-- Remove every legacy top-level hostile/marker copy before making a new
	-- generation.  Previous builds could accumulate duplicate Pool Foam models.
	for _,name in ipairs({
		"PoolroomsLevel2","Elevator","MazeStart","EntityStart","ElevatorSpawn",
		"PoolFoamEntity","PoolPipeEntity","PoolFoamStart","PoolPipeStart",
	}) do
		repeat
			local object=workspace:FindFirstChild(name)
			if not object then break end
			object:Destroy()
		until false
	end
	for _,o in ipairs(workspace:GetChildren()) do
		local n=o.Name:lower()
		if n:find("energytransfer") or n:find("exitdoor") or n=="exitgate" then o:Destroy() end
	end
	local lobby=workspace:FindFirstChild("ServerLobby")
	if lobby then lobby.Parent=ServerStorage; lobby.Name="StoredServerLobby" end
	for _,scriptName in ipairs({"EntityAI","EntityAnimation","EntityKill","PuzzleManager"}) do
		local s=game.ServerScriptService:FindFirstChild(scriptName)
		if s and s:IsA("Script") then s.Disabled=true end
	end
	for _, scriptName in ipairs(LEVEL2_ENTITY_SCRIPT_NAMES) do
		local scriptObject = game.ServerScriptService:FindFirstChild(scriptName)
		if scriptObject and scriptObject:IsA("Script") then scriptObject.Disabled = false end
	end
	local entity=workspace:FindFirstChild("Entity")
	if entity then entity.Parent=ServerStorage; entity.Name="StoredLevel1Entity" end

	workspace:SetAttribute("SelectedLevel",2)
	workspace:SetAttribute("Level2Valves",0)
	workspace:SetAttribute("Level2ValveGoal",3)
	workspace:SetAttribute("Level2ExitPowered",false)
	workspace:SetAttribute("PuzzleWon",false)
	workspace:SetAttribute("WorldGenerated",false)
	workspace:SetAttribute("SkipElevatorSequence",true)

	Lighting.Brightness=1.8
	Lighting.Ambient=Color3.fromRGB(88,92,88)
	Lighting.OutdoorAmbient=Color3.fromRGB(100,102,98)
	Lighting.FogStart=100000; Lighting.FogEnd=100000; Lighting.ClockTime=14
	local cc=Lighting:FindFirstChild("Level2PoolColor") or Instance.new("ColorCorrectionEffect")
	cc.Name,cc.Brightness,cc.Contrast,cc.Saturation,cc.Parent="Level2PoolColor",.01,.03,-.06,Lighting

	local buildGeneration=(workspace:GetAttribute("Level2BuildGeneration") or 0)+1
	workspace:SetAttribute("Level2BuildGeneration",buildGeneration)
	local world=Instance.new("Model"); world.Name="PoolroomsLevel2"; world.Parent=workspace
	world:SetAttribute("LevelNumber",2); world:SetAttribute("Theme","FloodedReferencePoolrooms")
	world:SetAttribute("BuildGeneration",buildGeneration)
	world:SetAttribute("Valve3WadingDepth",.8)
	local geometry=Instance.new("Folder"); geometry.Name="Geometry"; geometry.Parent=world
	local objectives=Instance.new("Folder"); objectives.Name="Objectives"; objectives.Parent=world
	local lamps=Instance.new("Folder"); lamps.Name="Lighting"; lamps.Parent=world
	local entities=Instance.new("Folder"); entities.Name="Entities"; entities.Parent=world
	entities:SetAttribute("BuildGeneration",buildGeneration)
	local alertEvent=ReplicatedStorage:FindFirstChild("Level2AlertEvent") or Instance.new("RemoteEvent")
	alertEvent.Name,alertEvent.Parent="Level2AlertEvent",ReplicatedStorage

	local edge=WORLD*.5
	local terrain=workspace.Terrain
	terrain:FillBlock(CFrame.new(0,0,0),Vector3.new(WORLD,100,WORLD),Enum.Material.Air)
	terrain.WaterColor=Color3.fromRGB(63,145,151)
	terrain.WaterTransparency=.38
	terrain.WaterReflectance=.08
	terrain.WaterWaveSize=.045
	terrain.WaterWaveSpeed=3.2
	lethalDepth(geometry)
	local bottomVoid=part(geometry,"AbyssUnderstructure",CFrame.new(0,-46,0),
		Vector3.new(WORLD,1,WORLD),Color3.fromRGB(10,28,35),Enum.Material.SmoothPlastic)
	bottomVoid.CanCollide=true
	buildReferencePoolrooms(geometry,lamps)
	buildSecretPoolParty(world,geometry,lamps)
	for _, object in ipairs(geometry:GetChildren()) do
		if object:IsA("BasePart") and object.Name:sub(-10)=="PoolBottom"
			and (object.Name:sub(1,6)=="Valve3" or object.Name=="CurveToFloodedDoorChamberPoolBottom") then
			object:SetAttribute("ShallowWadingWater",true)
			object:SetAttribute("WaterDepthStuds",.8)
		end
	end

	makeArrival(Vector3.new(-edge+34,0,-edge+ROOM*.5))
	local markers=createLevel2EntityMarkers(entities,buildGeneration)
	spawnLevel2Hostiles(entities,markers)
	local exit=exitTube(objectives,Vector3.new(292,0,200))
	local activated=0
	local function activatedValve()
		activated+=1; workspace:SetAttribute("Level2Valves",activated)
		local finalValve=activated>=3
		triggerValveBlackout(world,lamps,finalValve and function()
			beginFiltrationAlarm(world,lamps)
		end or nil)
		if finalValve then
			exit.portal.Color=C.green; exit.portal.Material=Enum.Material.ForceField
			exit.portal.Transparency=.28; exit.portal.CanCollide=false
			exit.light.Brightness=4; exit.trigger.CanTouch=true
			workspace:SetAttribute("Level2ExitPowered",true)
			for _,player in ipairs(Players:GetPlayers()) do
				if player:GetAttribute("InRound") then
					alertEvent:FireClient(player,
						"ALL THREE VALVES OPEN",
						"EXIT TUBE UNSEALED",
						"GET OUT!")
				end
			end
		end
	end
	wallValve(objectives,Vector3.new(-264,5,-160),Vector3.xAxis,C.red,1,activatedValve)
	wallValve(objectives,Vector3.new(-85,5,169),-Vector3.zAxis,C.yellow,2,activatedValve)
	wallValve(objectives,Vector3.new(330,5,127),-Vector3.zAxis,C.blue,3,activatedValve)

	exit.trigger.Touched:Connect(function(hit)
		if activated<3 then return end
		local character=hit:FindFirstAncestorOfClass("Model")
		local player=character and Players:GetPlayerFromCharacter(character)
		if not player or player:GetAttribute("Escaped") then return end
		player:SetAttribute("Escaped",true)
		local root=character:FindFirstChild("HumanoidRootPart")
		if root then root.CFrame=CFrame.new(0,80,0) end
		local all=true
		for _,p in ipairs(Players:GetPlayers()) do
			if p:GetAttribute("InRound") and p:GetAttribute("Escaped")~=true then all=false break end
		end
		if all then workspace:SetAttribute("PuzzleWon",true) end
	end)

	workspace:SetAttribute("LoadStage","READY")
	workspace:SetAttribute("WorldGenerated",true)
	return world
end

function Generator.Cleanup()
	-- Level2TerrainCleanup
	workspace.Terrain:FillBlock(CFrame.new(0,0,0),Vector3.new(WORLD,100,WORLD),Enum.Material.Air)
	for _, name in ipairs({
		"PoolroomsLevel2", "Elevator", "MazeStart", "EntityStart", "ElevatorSpawn",
		"PoolFoamEntity", "PoolPipeEntity", "PoolFoamStart", "PoolPipeStart"
	}) do
		repeat
			local object = workspace:FindFirstChild(name)
			if not object then break end
			object:Destroy()
		until false
	end

	local storedLobby = ServerStorage:FindFirstChild("StoredServerLobby")
	if storedLobby then
		local oldLobby = workspace:FindFirstChild("ServerLobby")
		if oldLobby then oldLobby:Destroy() end
		storedLobby.Name = "ServerLobby"
		storedLobby.Parent = workspace
	end

	local storedEntity = ServerStorage:FindFirstChild("StoredLevel1Entity")
	if storedEntity then
		local oldEntity = workspace:FindFirstChild("Entity")
		if oldEntity then oldEntity:Destroy() end
		storedEntity.Name = "Entity"
		storedEntity.Parent = workspace
	end

	for _, scriptName in ipairs({"EntityAI", "EntityAnimation", "EntityKill", "PuzzleManager"}) do
		local scriptObject = game.ServerScriptService:FindFirstChild(scriptName)
		if scriptObject and scriptObject:IsA("Script") then scriptObject.Disabled = false end
	end
	for _, scriptName in ipairs(LEVEL2_ENTITY_SCRIPT_NAMES) do
		local scriptObject = game.ServerScriptService:FindFirstChild(scriptName)
		if scriptObject and scriptObject:IsA("Script") then scriptObject.Disabled = true end
	end

	local poolColor = Lighting:FindFirstChild("Level2PoolColor")
	if poolColor then poolColor:Destroy() end
	Lighting.Brightness = 2
	Lighting.Ambient = Color3.fromRGB(92, 88, 70)
	Lighting.OutdoorAmbient = Color3.fromRGB(105, 101, 82)
	Lighting.FogStart = 100000
	Lighting.FogEnd = 100000
	Lighting.ClockTime = 14

	workspace:SetAttribute("SelectedLevel", 1)
	workspace:SetAttribute("WorldGenerated", false)
	workspace:SetAttribute("RoundActive", false)
	workspace:SetAttribute("SkipElevatorSequence", false)
	workspace:SetAttribute("Level2Valves", 0)
	workspace:SetAttribute("Level2ExitPowered", false)
	workspace:SetAttribute("PuzzleWon", false)
	print("[Level2] Poolrooms removed and lobby restored")
end

return Generator
