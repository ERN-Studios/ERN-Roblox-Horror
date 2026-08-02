-- Level2Generator
-- Bright, dry Poolrooms: spacious tiled chambers, shallow basins,
-- wall-mounted filtration valves, open-sky ceiling voids and a powered exit tube.

local Players = game:GetService("Players")
local ServerStorage = game:GetService("ServerStorage")
local Lighting = game:GetService("Lighting")
local ReplicatedStorage = game:GetService("ReplicatedStorage")

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
	loreBoard(model, position + Vector3.new(-3, 7, -10.9))
	-- Invisible compatibility doors keep the shared round manager happy without
	-- visually or physically turning this Poolrooms arrival bay into an elevator.
	local doorL = part(model,"DoorL",CFrame.new(position+Vector3.new(14.5,5,-5)),Vector3.new(.2,10,10),C.tile,Enum.Material.SmoothPlastic,1)
	local doorR = part(model,"DoorR",CFrame.new(position+Vector3.new(14.5,5,5)),Vector3.new(.2,10,10),C.tile,Enum.Material.SmoothPlastic,1)
	doorL.CanCollide, doorR.CanCollide = false, false
	local ramp = tiledPart(model,"ArrivalRamp",CFrame.new(position+Vector3.new(18,.2,0)),Vector3.new(8,.4,20),C.tile,nil,16)
	local start = part(workspace,"MazeStart",CFrame.new(position+Vector3.new(27,2.5,0)),Vector3.new(4,1,4),C.green,Enum.Material.Neon,1)
	start.CanCollide=false
	-- Start the entity on a distant perimeter ledge instead of in the arrival
	-- room.  This gives the players time to orient themselves before contact.
	local entityStart = part(workspace,"EntityStart",CFrame.new(Vector3.new(45,2.5,-100)),Vector3.new(4,1,4),C.red,Enum.Material.Neon,1)
	entityStart.CanCollide=false
	local spawn = part(workspace,"ElevatorSpawn",CFrame.new(position+Vector3.new(0,1.25,0)),Vector3.new(18,1,14),C.green,Enum.Material.Neon,1)
	spawn.CanCollide=true
end

local function spawnPoolFoamEntity()
	local assets = ServerStorage:FindFirstChild("Level2Assets")
	local template = assets and assets:FindFirstChild("PoolFoamEntityTemplate")
	local start = workspace:FindFirstChild("EntityStart")
	if not template or not start then
		warn("[Level2] Pool Foam Entity template or EntityStart is missing")
		return nil
	end

	local entity = template:Clone()
	entity.Name = "PoolFoamEntity"
	entity.Parent = workspace
	local root = entity.PrimaryPart or entity:FindFirstChild("char1", true) or entity:FindFirstChildWhichIsA("BasePart", true)
	if not root then
		entity:Destroy()
		warn("[Level2] Pool Foam Entity has no root part")
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
	local bottomOffset = root.Size.Y * .5
	-- EntityStart is a marker above the deck, not the floor itself.
	entity:PivotTo(CFrame.new(start.Position.X, bottomOffset + .1, start.Position.Z))
	entity:SetAttribute("MotionState", "Idle")
	entity:SetAttribute("MoveSpeed", 0)
	return entity
end

local function wallValve(parent, position, normal, color, number, onActivated)
	local model=Instance.new("Model"); model.Name="PressureValve"..number; model.Parent=parent
	model:SetAttribute("VisionColor",color)
	local base=part(model,"WallMount",CFrame.lookAt(position,position+normal),Vector3.new(5.5,5.5,.7),C.metal,Enum.Material.DiamondPlate)
	local center=position+normal*.65
	local right=normal:Cross(Vector3.yAxis).Unit
	local up=Vector3.yAxis
	local pieces={}
	for i=0,15 do
		local a=i*math.pi/8
		local radial=right*math.cos(a)+up*math.sin(a)
		local tangent=-right*math.sin(a)+up*math.cos(a)
		local p=part(model,"ValveRim",CFrame.lookAt(center+radial*2.25,center+radial*2.25+tangent),
			Vector3.new(.42,.42,.95),color,Enum.Material.Metal)
		table.insert(pieces,p)
	end
	for _,a in ipairs({math.pi/4,3*math.pi/4,5*math.pi/4,7*math.pi/4}) do
		local dir=right*math.cos(a)+up*math.sin(a)
		local p=part(model,"ValveSpoke",CFrame.lookAt(center+dir*1.05,center+dir*2.1),
			Vector3.new(.36,.36,2.1),color,Enum.Material.Metal)
		table.insert(pieces,p)
	end
	local hub=part(model,"ValveHub",CFrame.new(center),Vector3.new(.9,.9,.9),color,Enum.Material.Metal)
	hub.Shape=Enum.PartType.Ball
	local glow=Instance.new("PointLight")
	glow.Color,glow.Brightness,glow.Range,glow.Parent=color,.65,10,hub
	local prompt=Instance.new("ProximityPrompt")
	prompt.ActionText,prompt.ObjectText,prompt.HoldDuration,prompt.MaxActivationDistance,prompt.RequiresLineOfSight,prompt.Parent =
		"TURN VALVE","FILTRATION LINE "..number,1.1,10,false,hub
	local sign=part(model,"ValveStatus",CFrame.lookAt(position+Vector3.new(0,3.8,0)+normal*.1,position+Vector3.new(0,3.8,0)+normal),
		Vector3.new(4.8,1.25,.25),C.dark,Enum.Material.Metal)
	local title,sub=label(sign,Enum.NormalId.Front,"VALVE "..number,"OFFLINE",color)
	prompt.Triggered:Connect(function(player)
		if model:GetAttribute("Activated") then return end
		model:SetAttribute("Activated",true); prompt.Enabled=false
		for _,p in ipairs(pieces) do p.Material=Enum.Material.Neon end
		hub.Material,glow.Brightness=Enum.Material.Neon,2
		title.Text,sub.Text="VALVE "..number.." ACTIVE","PRESSURE RESTORED"
		onActivated(player,number)
	end)
	return model
end

local function exitTube(parent, position)
	local model=Instance.new("Model"); model.Name="ExitTube"; model.Parent=parent
	local steps,rise,run=13,.62,2.45
	for i=0,steps-1 do
		local y=.25+i*rise
		part(model,"GroundedStep",CFrame.new(position+Vector3.new(i*run,y,0)),Vector3.new(run+.1,.5,10),C.metal,Enum.Material.DiamondPlate)
		if i%3==0 then
			part(model,"StepSupport",CFrame.new(position+Vector3.new(i*run,y*.5,0)),Vector3.new(1.2,math.max(.5,y),8),C.metal,Enum.Material.Metal)
		end
	end
	local topY=.25+(steps-1)*rise
	local platformCenter=position+Vector3.new((steps-1)*run+11,topY,0)
	part(model,"ExitPlatform",CFrame.new(platformCenter),Vector3.new(24,.65,14),C.metal,Enum.Material.DiamondPlate)
	for _,z in ipairs({-6,6}) do
		part(model,"PlatformSupport",CFrame.new(platformCenter+Vector3.new(0,-topY*.5,z)),Vector3.new(1.2,topY,1.2),C.metal,Enum.Material.Metal)
	end
	-- The tube now physically continues into the outer wall instead of ending
	-- over empty space. Its far end remains sealed until all valves are open.
	local tubeCenter=platformCenter+Vector3.new(27,6,0)
	local radius,length=6.2,40
	for i=0,15 do
		local a=i*math.pi/8
		local cf=CFrame.new(tubeCenter)*CFrame.Angles(a,0,0)*CFrame.new(0,radius,0)
		part(model,"ExitTubeShell",cf,Vector3.new(length,.75,2.65),
			Color3.fromRGB(31,43,45),Enum.Material.Metal)
	end
	local entrance=tubeCenter+Vector3.new(-length*.5,0,0)
	local rimLight
	for i=0,15 do
		local a=i*math.pi/8
		local cf=CFrame.new(entrance)*CFrame.Angles(a,0,0)*CFrame.new(0,radius,0)
		local rim=part(model,"SubtleGreenEntranceRim",cf,Vector3.new(.75,.72,2.65),
			Color3.fromRGB(38,183,101),Enum.Material.Neon)
		if not rimLight then
			rimLight=Instance.new("PointLight")
			rimLight.Color, rimLight.Brightness, rimLight.Range, rimLight.Parent =
				Color3.fromRGB(54,218,126), .28, 12, rim
		end
	end
	local tunnel=part(model,"DarkTubeInterior",CFrame.new(tubeCenter),Vector3.new(length-1,10.8,10.8),Color3.fromRGB(3,15,11),Enum.Material.SmoothPlastic,.08)
	tunnel.CanCollide=false
	local portal=part(model,"ExitPlasma",CFrame.new(tubeCenter+Vector3.new(19,0,0)),Vector3.new(1,10.4,10.4),Color3.fromRGB(2,10,8),Enum.Material.SmoothPlastic,0)
	portal.CanCollide=true
	local light=Instance.new("PointLight")
	light.Color,light.Brightness,light.Range,light.Parent=C.green,0,36,portal
	local trigger=part(model,"ExitTrigger",CFrame.new(tubeCenter+Vector3.new(20.5,0,0)),Vector3.new(2,10,10),C.green,Enum.Material.Neon,1)
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
    local function room(name,cx,cz,w,d,h,doors,muted,noFloor)
        if not noFloor then floorRect(name.."Floor",cx,cz,w,d,0,C.tile) end
        ceilingRect(name.."Ceiling",cx,cz,w,d,h,muted)
        gapWallX(name.."NorthWall",cx,cz-d*.5,w,h,doors and doors.n,doors and doors.nw or 22,C.tile)
        gapWallX(name.."SouthWall",cx,cz+d*.5,w,h,doors and doors.s,doors and doors.sw or 22,C.tile)
        gapWallZ(name.."WestWall",cx-w*.5,cz,d,h,doors and doors.w,doors and doors.ww or 22,C.tile)
        gapWallZ(name.."EastWall",cx+w*.5,cz,d,h,doors and doors.e,doors and doors.ew or 22,C.tile)
    end
    local function flooded(name,cx,cz,w,d,depth)
        depth=depth or 3 if depth<1 then depth=1.4 end
        tiledPart(parent,name.."PoolBottom",CFrame.new(cx,-depth,cz),Vector3.new(w,.45,d),Color3.fromRGB(157,194,194),{Enum.NormalId.Top},14)
        terrain:FillBlock(CFrame.new(cx,-depth*.5+.35,cz),Vector3.new(math.max(4,w+.6),depth+.7,math.max(4,d+.6)),Enum.Material.Water)
    end
    local function dryLedge(name,cx,cz,w,d,y)
        tiledPart(parent,name,CFrame.new(cx,(y or .9)-1.05,cz),Vector3.new(w,2.2,d),C.tile,nil,14)
    end
    local function linkX(name,cx,cz,w,d,h,shallow)
        ceilingRect(name.."Ceiling",cx,cz,w,d,h,false)
        wallX(name.."NorthWall",cx,cz-d*.5,w,h,C.tile)
        wallX(name.."SouthWall",cx,cz+d*.5,w,h,C.tile)
        if shallow then flooded(name.."Basin",cx,cz,w,d,1.4) tiledPart(parent,name.."OverlapThreshold",CFrame.new(cx,-1.05,cz),Vector3.new(w+4,.8,d+4),C.tile,nil,14) else floorRect(name.."Floor",cx,cz,w,d,0,C.tile) end
    end
    local function linkZ(name,cx,cz,w,d,h,shallow)
        ceilingRect(name.."Ceiling",cx,cz,w,d,h,false)
        wallZ(name.."WestWall",cx-w*.5,cz,d,h,C.tile)
        wallZ(name.."EastWall",cx+w*.5,cz,d,h,C.tile)
        if shallow then flooded(name.."Basin",cx,cz,w,d,1.4) tiledPart(parent,name.."OverlapThreshold",CFrame.new(cx,-1.05,cz),Vector3.new(w+4,.8,d+4),C.tile,nil,14) else floorRect(name.."Floor",cx,cz,w,d,0,C.tile) end
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
    dryLedge("NorthPassageLedge",-236.5,-225,7,80,1.05)
    frostedPanel("NorthPassageScreen",CFrame.new(-208.6,8,-225)*CFrame.Angles(0,math.rad(-90),0),Vector3.new(5,11,.35),false)
    room("OvalLightChamber",-225,-160,80,50,25,{n=-225,nw=24,e=-160,ew=26},false)
    for x=-250,-200,25 do frostedPanel("MuffledWallWindow",CFrame.new(x,9,-135.6)*CFrame.Angles(0,math.rad(180),0),Vector3.new(6,15,.35),false) end
    room("FinalEntryTunnel",-165,-160,40,30,15,{w=-160,ww=26,e=-160,ew=26},false,true)
    flooded("FinalEntryWater",-165,-160,38,28,.6)
    dryLedge("FinalEntryLedge",-165,-170,40,7,1.05)
    linkX("FinalToGrandLink",-137.5,-160,15,26,15,true)

    room("GrandPoolHall",0,-100,260,220,34,{w=-160,ww=30,s=20,sw=34,e=-55,ew=32},false,true)
    flooded("GrandPoolWater",0,-100,218,178,6)
    dryLedge("GrandNorthLedge",0,-199,260,20,1.08)
    dryLedge("GrandSouthLedge",0,-1,260,20,1.08)
    dryLedge("GrandWestLedge",-119,-100,22,178,1.08)
    dryLedge("GrandEastLedge",119,-100,22,178,1.08)
    dryLedge("GrandCentralIsland",0,-100,54,46,1.1)
    dryLedge("GrandBridgeWest",-72,-100,90,10,1.1)
    dryLedge("GrandBridgeNorth",0,-55,10,44,1.1)
    dryLedge("GrandBridgeEast",72,-100,90,10,1.1)
    for _,p in ipairs({Vector3.new(-72,0,-150),Vector3.new(72,0,-150),Vector3.new(-72,0,-50),Vector3.new(72,0,-50),Vector3.new(-20,0,-100),Vector3.new(20,0,-100)}) do tiledColumn(parent,p,5,34) end
    for x=-85,85,85 do frostedPanel("GrandHallCeilingScreen",CFrame.new(x,33.3,-100)*CFrame.Angles(math.rad(90),0,0),Vector3.new(18,8,.35),false) end
    for _,z in ipairs({-110,-55}) do frostedPanel("GrandHallWallScreen",CFrame.new(-129.3,11,z)*CFrame.Angles(0,math.rad(90),0),Vector3.new(5,15,.35),false) end

    room("ArchWaterWing",200,-55,140,150,22,{w=-55,ww=32,s=200,sw=26},false,true)
    flooded("ArchWater",200,-55,116,126,5.4)
    dryLedge("ArchWestLedge",142,-55,12,150,1.05)
    dryLedge("ArchEastLedge",258,-55,12,150,1.05)
    dryLedge("ArchNorthLedge",200,-124,116,12,1.05)
    dryLedge("ArchSouthLedge",200,14,116,12,1.05)
    archGallery(parent,lamps,Vector3.new(200,0,-55),false)
    frostedPanel("ArchGuideLight",CFrame.new(200,8,-128.5),Vector3.new(8,12,.35),false)
    for _,x in ipairs({165,235}) do frostedPanel("ArchCeilingScreen",CFrame.new(x,21.3,-55)*CFrame.Angles(math.rad(90),0,0),Vector3.new(14,6,.35),false) end

    linkZ("GrandToPillarLink",20,15,32,10,22,true)
    room("PillarWaterHall",-40,95,180,150,28,{n=20,nw=34,e=135,ew=28,s=-35,sw=24,w=95,ww=26},false,true)
    flooded("PillarHallWater",-40,95,150,120,5.2)
    dryLedge("PillarHallWest",-119,95,20,150,1.05)
    dryLedge("PillarHallEast",39,95,20,150,1.05)
    dryLedge("PillarHallNorth",-40,164,180,14,1.05)
    dryLedge("PillarHallSouth",-40,26,180,14,1.05)
    for x=-90,-40,50 do for z=55,135,40 do tiledColumn(parent,Vector3.new(x,0,z),5,28) end end
    for _,x in ipairs({-105,-72}) do frostedPanel("PillarHallScreen",CFrame.new(x,10,20.6),Vector3.new(5,14,.35),false) end
    for _,p in ipairs({Vector3.new(-80,27.3,90),Vector3.new(0,27.3,90)}) do lightPanel(lamps,p,Vector3.new(16,.25,6)) end

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
    flooded("SunkenGalleryWater",60,277,132,76,5.6)
    dryLedge("SunkenNorth",60,234,160,14,1.05)
    dryLedge("SunkenSouth",60,320,160,14,1.05)
    dryLedge("SunkenWest",-13,277,14,76,1.05)
    dryLedge("SunkenEast",133,277,14,76,1.05)
    dryLedge("SunkenIsland",60,277,34,28,1.1)
    dryLedge("SunkenBridge",23,277,40,8,1.1)
    for _,p in ipairs({Vector3.new(25,0,252),Vector3.new(95,0,302)}) do tiledColumn(parent,p,5,25) end
    for _,p in ipairs({Vector3.new(25,24.3,277),Vector3.new(95,24.3,277)}) do lightPanel(lamps,p,Vector3.new(15,.25,6)) end

    room("ExitChamber",320,200,100,100,24,{w=200,ww=28},false)
    frostedPanel("ExitChamberScreen",CFrame.new(369.4,9,200)*CFrame.Angles(0,math.rad(-90),0),Vector3.new(6,15,.35),false)

    for _,p in ipairs({
        Vector3.new(-340,21.4,-300),Vector3.new(-225,21.4,-160),
        Vector3.new(-165,14.3,-160),Vector3.new(-40,27.4,95),
        Vector3.new(125,17.4,200),Vector3.new(-190,17.3,95),
        Vector3.new(-190,15.3,225),Vector3.new(320,23.4,200)
    }) do lightPanel(lamps,p,Vector3.new(16,.25,5)) end
end

function Generator.Build()
	for _,name in ipairs({"PoolroomsLevel2","Elevator","MazeStart","EntityStart","ElevatorSpawn"}) do
		local o=workspace:FindFirstChild(name); if o then o:Destroy() end
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

	local world=Instance.new("Model"); world.Name="PoolroomsLevel2"; world.Parent=workspace
	world:SetAttribute("LevelNumber",2); world:SetAttribute("Theme","FloodedReferencePoolrooms")
	local geometry=Instance.new("Folder"); geometry.Name="Geometry"; geometry.Parent=world
	local objectives=Instance.new("Folder"); objectives.Name="Objectives"; objectives.Parent=world
	local lamps=Instance.new("Folder"); lamps.Name="Lighting"; lamps.Parent=world
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

	makeArrival(Vector3.new(-edge+34,0,-edge+ROOM*.5))
	spawnPoolFoamEntity()
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
	wallValve(objectives,Vector3.new(269,5,-55),-Vector3.xAxis,C.blue,3,activatedValve)

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
		"PoolroomsLevel2", "Elevator", "MazeStart", "EntityStart", "ElevatorSpawn", "PoolFoamEntity"
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
