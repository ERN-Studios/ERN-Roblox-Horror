-- TunnelLobbyBuilder
-- Modular Zyntra transit lobby used by GameManager.
-- Geometry is intentionally built from simple anchored parts so the lobby remains
-- easy to resize, texture, and extend when more levels are enabled.

local Builder = {}

local LOBBY_CONCRETE_MATERIALS = {
	Concrete = {
		texture = "rbxassetid://137549469660951",
		studsPerTile = 14,
	},
	ConcreteAlt = {
		texture = "rbxassetid://111820708793535",
		studsPerTile = 14,
	},
	ConcreteAll = {
		texture = "rbxassetid://137549469660951",
		studsPerTile = 14,
	},
	FloorConcrete = {
		texture = "rbxassetid://134299652574760",
		studsPerTile = 12,
	},
	FloorConcreteAll = {
		texture = "rbxassetid://134299652574760",
		studsPerTile = 12,
	},
	Curb = {
		texture = "rbxassetid://135670497420182",
		studsPerTile = 5,
	},
}

local COLORS = {
	concrete = Color3.fromRGB(116, 105, 82),
	concreteDark = Color3.fromRGB(73, 68, 58),
	concreteLight = Color3.fromRGB(157, 144, 111),
	asphalt = Color3.fromRGB(27, 28, 27),
	curb = Color3.fromRGB(116, 112, 95),
	metal = Color3.fromRGB(32, 35, 34),
	metalLight = Color3.fromRGB(62, 66, 62),
	paint = Color3.fromRGB(222, 207, 140),
	green = Color3.fromRGB(86, 255, 173),
	amber = Color3.fromRGB(255, 183, 72),
	red = Color3.fromRGB(255, 76, 60),
	wallpaper = Color3.fromRGB(198, 185, 112),
}

local function makePart(parent, name, cf, size, color, material, transparency)
	local p = Instance.new("Part")
	p.Name = name
	p.Anchored = true
	p.Size = size
	p.CFrame = typeof(cf) == "CFrame" and cf or CFrame.new(cf)
	p.Color = color
	p.Material = material or Enum.Material.SmoothPlastic
	p.Transparency = transparency or 0
	p.TopSurface = Enum.SurfaceType.Smooth
	p.BottomSurface = Enum.SurfaceType.Smooth
	p.Parent = parent
	return p
end

local function addSurfaceTexture(part, spec, face)
	local texture = Instance.new("Texture")
	texture.Name = "LobbyConcreteTexture"
	texture.Texture = spec.texture
	texture.Face = face
	texture.StudsPerTileU = spec.studsPerTile
	texture.StudsPerTileV = spec.studsPerTile
	texture.Color3 = Color3.new(1, 1, 1)
	texture.Parent = part
end

local function tagSurface(part, role)
	part:SetAttribute("TunnelTextureRole", role)
	local spec = LOBBY_CONCRETE_MATERIALS[role]
	if spec then
		part.Material = Enum.Material.Concrete
		local faces
		if role == "ConcreteAll" or role == "FloorConcreteAll" then
			faces = {
				Enum.NormalId.Top,
				Enum.NormalId.Bottom,
				Enum.NormalId.Left,
				Enum.NormalId.Right,
				Enum.NormalId.Front,
				Enum.NormalId.Back,
			}
		elseif role == "FloorConcrete" then
			faces = { Enum.NormalId.Top }
		elseif role == "Curb" then
			faces = { Enum.NormalId.Top, Enum.NormalId.Left, Enum.NormalId.Right }
		elseif part.Size.X <= part.Size.Y and part.Size.X <= part.Size.Z then
			faces = { Enum.NormalId.Left, Enum.NormalId.Right }
		elseif part.Size.Y <= part.Size.Z then
			faces = { Enum.NormalId.Top, Enum.NormalId.Bottom }
		else
			faces = { Enum.NormalId.Front, Enum.NormalId.Back }
		end
		for _, face in ipairs(faces) do
			addSurfaceTexture(part, spec, face)
		end
	end
	return part
end

local function addBoard(panel, face, titleText, subtitleText, titleColor)
	local gui = Instance.new("SurfaceGui")
	gui.Name = "Display"
	gui.Face = face or Enum.NormalId.Front
	gui.CanvasSize = Vector2.new(900, 300)
	gui.LightInfluence = 0
	gui.AlwaysOnTop = false
	gui.Parent = panel

	local background = Instance.new("Frame")
	background.Size = UDim2.fromScale(1, 1)
	background.BackgroundColor3 = Color3.fromRGB(9, 12, 11)
	background.BackgroundTransparency = 0.06
	background.BorderSizePixel = 0
	background.Parent = gui

	local line = Instance.new("Frame")
	line.Position = UDim2.new(0.04, 0, 0.74, 0)
	line.Size = UDim2.new(0.92, 0, 0, 4)
	line.BackgroundColor3 = titleColor
	line.BackgroundTransparency = 0.22
	line.BorderSizePixel = 0
	line.Parent = background

	local title = Instance.new("TextLabel")
	title.Name = "Title"
	title.Position = UDim2.new(0.035, 0, 0.06, 0)
	title.Size = UDim2.new(0.93, 0, 0.58, 0)
	title.BackgroundTransparency = 1
	title.Font = Enum.Font.GothamBold
	title.Text = titleText
	title.TextColor3 = titleColor
	title.TextScaled = true
	title.TextWrapped = true
	title.Parent = background

	local subtitle = Instance.new("TextLabel")
	subtitle.Name = "Subtitle"
	subtitle.Position = UDim2.new(0.045, 0, 0.76, 0)
	subtitle.Size = UDim2.new(0.91, 0, 0.17, 0)
	subtitle.BackgroundTransparency = 1
	subtitle.Font = Enum.Font.Code
	subtitle.Text = subtitleText or ""
	subtitle.TextColor3 = Color3.fromRGB(227, 218, 177)
	subtitle.TextScaled = true
	subtitle.TextWrapped = true
	subtitle.Parent = background

	return title, subtitle
end

local function addLamp(parent, center, x, z)
	local mount = makePart(
		parent,
		"LightMount",
		CFrame.new(center + Vector3.new(x, 29.8, z)),
		Vector3.new(7.5, 0.55, 1.5),
		COLORS.metal,
		Enum.Material.Metal
	)
	mount.CanCollide = false

	local lens = makePart(
		parent,
		"WarmTunnelLight",
		CFrame.new(center + Vector3.new(x, 29.45, z)),
		Vector3.new(6.8, 0.22, 1.1),
		Color3.fromRGB(255, 220, 145),
		Enum.Material.Neon
	)
	lens.CanCollide = false

	local point = Instance.new("PointLight")
	point.Color = Color3.fromRGB(255, 216, 144)
	point.Brightness = 2.35
	point.Range = 30
	point.Shadows = true
	point.Parent = lens
end

local function addTunnelEndBarricade(parent, center, zOffset, inward, seed)
	local model = Instance.new("Model")
	model.Name = zOffset < 0 and "NearPropBarricade" or "FarPropBarricade"
	model.Parent = parent
	local random = Random.new(seed)
	local base = center + Vector3.new(0, 0, zOffset)

	-- The dark backstop is fully hidden by the pile in normal play. It prevents
	-- pinholes between silhouettes from revealing the finite end of the lobby.
	local backstop = makePart(
		model,
		"OcclusionBackstop",
		CFrame.new(base + Vector3.new(0, 29, -inward * 2.8)),
		Vector3.new(70, 58, 2.4),
		Color3.fromRGB(38, 37, 34),
		Enum.Material.Concrete
	)
	tagSurface(backstop, "ConcreteAlt")

	-- A single continuous collider guarantees that players cannot squeeze
	-- through small natural gaps in the furniture wall.
	local blocker = makePart(
		model,
		"PropBarricadeCollision",
		CFrame.new(base + Vector3.new(0, 18, inward * 1.5)),
		Vector3.new(69, 36, 7),
		Color3.new(0, 0, 0),
		Enum.Material.SmoothPlastic,
		1
	)
	blocker.CanQuery = false
	blocker.CanTouch = false

	local cardboard = {
		Color3.fromRGB(139, 105, 66),
		Color3.fromRGB(118, 89, 57),
		Color3.fromRGB(156, 122, 77),
		Color3.fromRGB(102, 78, 54),
	}

	-- Six overlapping courses make a dense, irregular mass across the complete
	-- road and both walkways instead of a repeated row of identical crates.
	for layer = 0, 5 do
		for column = -5, 5 do
			local width = random:NextNumber(5.7, 7.2)
			local height = random:NextNumber(4.3, 5.8)
			local depth = random:NextNumber(4.5, 7.5)
			local x = column * 6.25 + random:NextNumber(-0.8, 0.8)
			local y = 2.25 + layer * 4.55 + random:NextNumber(-0.35, 0.35)
			local z = inward * (1.2 + random:NextNumber(-1.4, 2.5) - layer * 0.24)
			-- Leave irregular pockets above the solid bottom course. Furniture is
			-- wedged into these spaces below instead of merely standing in front.
			if layer == 0 or random:NextNumber() > 0.24 then
				local box = makePart(
					model,
					"AbandonedArchiveBox",
					CFrame.new(base + Vector3.new(x, y, z)) * CFrame.Angles(
						math.rad(random:NextNumber(-4, 4)),
						math.rad(random:NextNumber(-10, 10)),
						math.rad(random:NextNumber(-5, 5))
					),
					Vector3.new(width, height, depth),
					cardboard[random:NextInteger(1, #cardboard)],
					Enum.Material.Wood
				)
				box:SetAttribute("LobbyProp", "ArchiveBox")
			end
		end
	end

	local function addEmbeddedChair(chairCF, scale)
		makePart(model, "WedgedChairSeat", chairCF, Vector3.new(3.8, 0.65, 3.8) * scale, Color3.fromRGB(63, 65, 60), Enum.Material.Metal)
		makePart(model, "WedgedChairBack", chairCF * CFrame.new(0, 2.25 * scale, 1.65 * scale), Vector3.new(3.8, 4.2, 0.55) * scale, Color3.fromRGB(72, 73, 66), Enum.Material.Metal)
		for _, legX in ipairs({ -1.45, 1.45 }) do
			for _, legZ in ipairs({ -1.45, 1.45 }) do
				makePart(
					model,
					"WedgedChairLeg",
					chairCF * CFrame.new(legX * scale, -1.65 * scale, legZ * scale),
					Vector3.new(0.35, 3.1, 0.35) * scale,
					Color3.fromRGB(42, 44, 42),
					Enum.Material.Metal
				)
			end
		end
	end

	local function addEmbeddedTable(tableCF, scale)
		makePart(model, "WedgedDeskTop", tableCF, Vector3.new(9.2, 0.75, 5.1) * scale, Color3.fromRGB(76, 55, 38), Enum.Material.WoodPlanks)
		for _, legX in ipairs({ -3.8, 3.8 }) do
			for _, legZ in ipairs({ -1.8, 1.8 }) do
				makePart(
					model,
					"WedgedDeskLeg",
					tableCF * CFrame.new(legX * scale, -2.4 * scale, legZ * scale),
					Vector3.new(0.5, 4.5, 0.5) * scale,
					Color3.fromRGB(48, 50, 47),
					Enum.Material.Metal
				)
			end
		end
	end

	local function addGrandfatherClock(clockCF, scale)
		local wood = Color3.fromRGB(79, 48, 29)
		makePart(model, "WedgedGrandfatherClockBody", clockCF, Vector3.new(4.2, 10.5, 2.4) * scale, wood, Enum.Material.WoodPlanks)
		makePart(model, "WedgedGrandfatherClockHood", clockCF * CFrame.new(0, 5.2 * scale, 0), Vector3.new(5.1, 4.1, 3) * scale, Color3.fromRGB(64, 38, 24), Enum.Material.WoodPlanks)
		local face = makePart(
			model,
			"GrandfatherClockFace",
			clockCF * CFrame.new(0, 5.25 * scale, -1.53 * scale) * CFrame.Angles(0, math.rad(90), 0),
			Vector3.new(0.3, 2.8, 2.8) * scale,
			Color3.fromRGB(204, 189, 143),
			Enum.Material.SmoothPlastic
		)
		face.Shape = Enum.PartType.Cylinder
		face.CanCollide = false
		local window = makePart(model, "GrandfatherClockWindow", clockCF * CFrame.new(0, 0.4 * scale, -1.23 * scale), Vector3.new(2.2, 4.1, 0.18) * scale, Color3.fromRGB(25, 23, 20), Enum.Material.Glass, 0.18)
		window.CanCollide = false
		local pendulum = makePart(model, "GrandfatherClockPendulum", clockCF * CFrame.new(0, 0.15 * scale, -1.36 * scale), Vector3.new(0.38, 2.7, 0.18) * scale, Color3.fromRGB(177, 139, 56), Enum.Material.Metal)
		pendulum.CanCollide = false
	end

	local function addPrinter(printerCF, scale)
		local shell = Color3.fromRGB(165, 166, 157)
		makePart(model, "WedgedOfficePrinter", printerCF, Vector3.new(4.8, 2.5, 4) * scale, shell, Enum.Material.SmoothPlastic)
		makePart(model, "PrinterScannerLid", printerCF * CFrame.new(0, 1.45 * scale, 0.15 * scale), Vector3.new(4.35, 0.45, 3.45) * scale, Color3.fromRGB(194, 195, 184), Enum.Material.SmoothPlastic)
		local slot = makePart(model, "PrinterOutputSlot", printerCF * CFrame.new(0, -0.15 * scale, -2.03 * scale), Vector3.new(3.25, 0.38, 0.18) * scale, Color3.fromRGB(28, 30, 28), Enum.Material.SmoothPlastic)
		slot.CanCollide = false
		local paper = makePart(model, "PrinterPaper", printerCF * CFrame.new(0, -0.65 * scale, -2.7 * scale) * CFrame.Angles(math.rad(18), 0, 0), Vector3.new(3, 0.08, 2.4) * scale, Color3.fromRGB(220, 216, 195), Enum.Material.SmoothPlastic)
		paper.CanCollide = false
	end

	-- Furniture and office equipment are distributed through the entire height
	-- of the pile. Strong rotations make pieces look crushed and load-bearing.
	for index = 1, 15 do
		local row = math.floor((index - 1) / 5)
		local column = (index - 1) % 5
		local chairCF = CFrame.new(base + Vector3.new(
			-25 + column * 12.5 + random:NextNumber(-2, 2),
			8 + row * 8.2 + random:NextNumber(-1.2, 1.2),
			inward * random:NextNumber(4.3, 7.2)
		)) * CFrame.Angles(
			math.rad(random:NextNumber(-55, 55)),
			math.rad(random:NextNumber(-75, 75)),
			math.rad(random:NextNumber(-70, 70))
		)
		addEmbeddedChair(chairCF, random:NextNumber(0.82, 1.08))
	end

	for index = 1, 7 do
		local row = math.floor((index - 1) / 4)
		local column = (index - 1) % 4
		local tableCF = CFrame.new(base + Vector3.new(
			-24 + column * 16 + random:NextNumber(-2.2, 2.2),
			11 + row * 11 + random:NextNumber(-1, 1),
			inward * random:NextNumber(3.5, 6.2)
		)) * CFrame.Angles(
			math.rad(random:NextNumber(-25, 25)),
			math.rad(random:NextNumber(-50, 50)),
			math.rad(random:NextNumber(-38, 38))
		)
		addEmbeddedTable(tableCF, random:NextNumber(0.82, 1.05))
	end

	for index = 1, 5 do
		local clockCF = CFrame.new(base + Vector3.new(
			-26 + (index - 1) * 13 + random:NextNumber(-1.5, 1.5),
			10.5 + (index % 2) * 8,
			inward * random:NextNumber(5.2, 7.8)
		)) * CFrame.Angles(
			math.rad(random:NextNumber(-16, 16)),
			math.rad(random:NextNumber(-35, 35)),
			math.rad(random:NextNumber(-32, 32))
		)
		addGrandfatherClock(clockCF, random:NextNumber(0.78, 0.96))
	end

	for index = 1, 12 do
		local row = math.floor((index - 1) / 6)
		local column = (index - 1) % 6
		local printerCF = CFrame.new(base + Vector3.new(
			-28 + column * 11 + random:NextNumber(-1.5, 1.5),
			7.5 + row * 13 + random:NextNumber(-1.4, 1.4),
			inward * random:NextNumber(6, 9)
		)) * CFrame.Angles(
			math.rad(random:NextNumber(-35, 35)),
			math.rad(random:NextNumber(-65, 65)),
			math.rad(random:NextNumber(-38, 38))
		)
		addPrinter(printerCF, random:NextNumber(0.78, 1.08))
	end

	-- Metal filing cabinets break up the cardboard silhouette and sell the
	-- abandoned-office origin of the barricade.
	for index = -3, 3 do
		local x = index * 9 + random:NextNumber(-1.5, 1.5)
		local cabinetCF = CFrame.new(base + Vector3.new(x, 5.2, inward * 5.3))
			* CFrame.Angles(0, math.rad(random:NextNumber(-16, 16)), math.rad(random:NextNumber(-3, 3)))
		local cabinet = makePart(
			model,
			"AbandonedFileCabinet",
			cabinetCF,
			Vector3.new(5.4, 10.2, 4.2),
			Color3.fromRGB(72, 76, 72),
			Enum.Material.Metal
		)
		cabinet:SetAttribute("LobbyProp", "FileCabinet")
		for drawer = -1, 1 do
			local front = makePart(
				model,
				"CabinetDrawer",
				cabinetCF * CFrame.new(0, drawer * 2.7, inward * 2.13),
				Vector3.new(4.5, 0.18, 0.18),
				Color3.fromRGB(29, 31, 29),
				Enum.Material.Metal
			)
			front.CanCollide = false
		end
	end

	-- Half-buried office tables and chairs form the readable foreground layer.
	for index = 1, 5 do
		local x = -27 + (index - 1) * 13.5 + random:NextNumber(-1.5, 1.5)
		local yaw = math.rad(random:NextNumber(-28, 28))
		local tableCF = CFrame.new(base + Vector3.new(x, 5.2, inward * 9.2)) * CFrame.Angles(0, yaw, 0)
		makePart(model, "DiscardedDeskTop", tableCF, Vector3.new(10.5, 0.8, 5.5), Color3.fromRGB(76, 55, 38), Enum.Material.WoodPlanks)
		for _, legX in ipairs({ -4.4, 4.4 }) do
			for _, legZ in ipairs({ -2.1, 2.1 }) do
				makePart(
					model,
					"DiscardedDeskLeg",
					tableCF * CFrame.new(legX, -2.5, legZ),
					Vector3.new(0.55, 4.8, 0.55),
					Color3.fromRGB(48, 50, 47),
					Enum.Material.Metal
				)
			end
		end
	end

	for index = 1, 7 do
		local x = -30 + (index - 1) * 10 + random:NextNumber(-1, 1)
		local chairCF = CFrame.new(base + Vector3.new(x, 2.9, inward * 13.2))
			* CFrame.Angles(math.rad(random:NextNumber(-7, 7)), math.rad(random:NextNumber(-35, 35)), math.rad(random:NextNumber(-8, 8)))
		makePart(model, "DiscardedChairSeat", chairCF, Vector3.new(3.8, 0.65, 3.8), Color3.fromRGB(63, 65, 60), Enum.Material.Metal)
		makePart(model, "DiscardedChairBack", chairCF * CFrame.new(0, 2.25, 1.65), Vector3.new(3.8, 4.2, 0.55), Color3.fromRGB(72, 73, 66), Enum.Material.Metal)
		for _, legX in ipairs({ -1.45, 1.45 }) do
			for _, legZ in ipairs({ -1.45, 1.45 }) do
				makePart(model, "DiscardedChairLeg", chairCF * CFrame.new(legX, -1.65, legZ), Vector3.new(0.35, 3.1, 0.35), Color3.fromRGB(42, 44, 42), Enum.Material.Metal)
			end
		end
	end

	-- Long fallen shelving panels close the irregular upper outline beneath the
	-- tunnel crown and make the blockade feel deliberately impossible to cross.
	for index = -1, 1 do
		makePart(
			model,
			"CollapsedShelvingPanel",
			CFrame.new(base + Vector3.new(index * 21, 29 + math.abs(index) * 1.6, inward * 2.2))
				* CFrame.Angles(math.rad(4 * index), math.rad(random:NextNumber(-9, 9)), math.rad(index * 13)),
			Vector3.new(25, 1.25, 5.5),
			Color3.fromRGB(54, 57, 54),
			Enum.Material.Metal
		)
	end

	model:SetAttribute("DenseEndBarricade", true)
	return model
end

local function addQueueStation(parent, roomCenter, index, offset, color, active, displayIndex, level)
	local origin = roomCenter + offset
	local stationScale = 1.4
	local halfX, halfZ = 5.2 * stationScale, 4.3 * stationScale
	local inwardZ = offset.Z < 0 and 1 or -1
	local zoneCF = CFrame.lookAt(origin, origin + Vector3.new(0, 0, inwardZ))

	local zone = makePart(
		parent,
		(active and "LaunchZone" or "FutureLaunchZone") .. index,
		zoneCF,
		Vector3.new(halfX * 2, 0.3, halfZ * 2),
		color,
		Enum.Material.Neon,
		active and 0.78 or 0.9
	)
	zone.CanCollide = false
	zone.CanTouch = false
	zone.CanQuery = false

	for _, data in ipairs({
		{Vector3.new(0, 0.35, -halfZ), Vector3.new(halfX * 2 + 0.6, 0.34, 0.34)},
		{Vector3.new(0, 0.35, halfZ), Vector3.new(halfX * 2 + 0.6, 0.34, 0.34)},
		{Vector3.new(-halfX, 0.35, 0), Vector3.new(0.34, 0.34, halfZ * 2 + 0.6)},
		{Vector3.new(halfX, 0.35, 0), Vector3.new(0.34, 0.34, halfZ * 2 + 0.6)},
	}) do
		local rail = makePart(
			parent,
			"Station" .. index .. "Rail",
			zoneCF * CFrame.new(data[1]),
			data[2],
			color,
			Enum.Material.Neon,
			active and 0.14 or 0.55
		)
		rail.CanCollide = false
		rail.CanTouch = false
		rail.CanQuery = false
	end

	local signPosition = origin + Vector3.new(0, 5.2 * stationScale, (offset.Z < 0 and -5.1 or 5.1) * stationScale)
	local signPanel = makePart(
		parent,
		"Station" .. index .. "Sign",
		CFrame.lookAt(signPosition, origin + Vector3.new(0, 4.4, 0)),
		Vector3.new(8.7 * stationScale, 3.1 * stationScale, 0.38),
		COLORS.metal,
		Enum.Material.Metal
	)
	signPanel.CanCollide = false

	local title, subtitle = addBoard(
		signPanel,
		Enum.NormalId.Front,
		active and ("STATION " .. (displayIndex or index) .. "  •  0/6") or ("STATION " .. (displayIndex or index) .. "  •  OFFLINE"),
		active and "ENTER TO HOST  •  MAX 6 PLAYERS" or "AWAITING LEVEL AUTHORIZATION",
		color
	)

	if not active then
		return nil
	end

	return {
		index = index,
		displayIndex = displayIndex or index,
		level = level or 1,
		zone = zone,
		title = title,
		sub = subtitle,
		color = color,
		busy = false,
	}
end

local function addRoom(parent, center, level, side, zOffset, active, stations)
	local roomModel = Instance.new("Model")
	roomModel.Name = "Level" .. level .. "QueueRoom"
	roomModel.Parent = parent

	local roomScale = 1.4
	local roomRadius = 20 * roomScale
	local roomHeight = 16 * roomScale
	-- Keep the larger chamber's inner edge aligned with the tunnel entrance.
	local roomCenter = center + Vector3.new(side * (35 + roomRadius), 0, zOffset)
	local wallY = center.Y + roomHeight * 0.5

	local floor = makePart(
		roomModel,
		"ChamberFloor",
		CFrame.new(roomCenter + Vector3.new(0, -0.42, 0)) * CFrame.Angles(0, 0, math.rad(90)),
		Vector3.new(1.4, roomRadius * 2 + 3, roomRadius * 2 + 3),
		COLORS.concreteDark,
		Enum.Material.Concrete
	)
	floor.Shape = Enum.PartType.Cylinder
	tagSurface(floor, "FloorConcrete")

	local ceiling = makePart(
		roomModel,
		"ChamberCeiling",
		CFrame.new(roomCenter + Vector3.new(0, roomHeight + 0.2, 0)) * CFrame.Angles(0, 0, math.rad(90)),
		Vector3.new(1.8, roomRadius * 2 + 3, roomRadius * 2 + 3),
		COLORS.concrete,
		Enum.Material.Concrete
	)
	ceiling.Shape = Enum.PartType.Cylinder
	tagSurface(ceiling, "Concrete")

	local wallSegments = 28
	local chord = 2 * roomRadius * math.sin(math.pi / wallSegments) + 0.35
	local towardTunnel = Vector3.new(-side, 0, 0)
	for i = 0, wallSegments - 1 do
		local theta = (i / wallSegments) * math.pi * 2
		local radial = Vector3.new(math.cos(theta), 0, math.sin(theta))
		-- Continue the cylinder all the way around, omitting only the narrow
		-- three-panel arc that lines up with the actual tunnel doorway.
		if radial:Dot(towardTunnel) < 0.955 then
			local position = roomCenter + radial * roomRadius + Vector3.new(0, roomHeight * 0.5, 0)
			local wall = makePart(
				roomModel,
				"CurvedChamberWall",
				CFrame.lookAt(position, Vector3.new(roomCenter.X, wallY, roomCenter.Z)),
				Vector3.new(chord, roomHeight, 1.25),
				COLORS.concrete,
				Enum.Material.Concrete
			)
			tagSurface(wall, "Concrete")
		end
	end

	local tunnelEdgeX = side * 34
	local roomEdgeX = side * 35
	local passageCenterX = (tunnelEdgeX + roomEdgeX) * 0.5
	tagSurface(makePart(
		roomModel,
		"DoorThreshold",
		CFrame.new(center.X + passageCenterX, center.Y - 0.25, center.Z + zOffset),
		-- Overlap both the service ledge and chamber floor slightly. The old
		-- three-stud bridge left a visible crack on either side of the doorway.
		Vector3.new(math.abs(roomEdgeX - tunnelEdgeX) + 4, 0.5, 19.6),
		COLORS.metalLight,
		Enum.Material.DiamondPlate
	), "Metal")

	-- Join the cylindrical chamber to the tunnel with a short rectangular
	-- vestibule. Large square seam fillers looked correct from the tunnel but
	-- exposed their backs (and a sliver of sky) when viewed from inside a bay.
	-- These edge-on walls, floor, and ceiling overlap both structures instead.
	for _, zSide in ipairs({ -1, 1 }) do
		tagSurface(makePart(
			roomModel,
			"DoorVestibuleWall",
			CFrame.new(center + Vector3.new(
				side * 38,
				11.25,
				zOffset + zSide * 10.15
			)),
			Vector3.new(11, 23.5, 1.5),
			COLORS.concrete,
			Enum.Material.Concrete
		), "ConcreteAll")
	end

	tagSurface(makePart(
		roomModel,
		"DoorVestibuleFloor",
		CFrame.new(center + Vector3.new(side * 38, -0.25, zOffset)),
		Vector3.new(11, 0.8, 21.8),
		COLORS.concreteDark,
		Enum.Material.Concrete
	), "FloorConcreteAll")
	tagSurface(makePart(
		roomModel,
		"DoorVestibuleCeiling",
		-- A solid overhead backfill reaches the chamber ceiling. A thin roof
		-- still allowed high third-person cameras to see into the void above it.
		CFrame.new(center + Vector3.new(side * 38, 19.4, zOffset)),
		Vector3.new(11, 7.8, 21.8),
		COLORS.concrete,
		Enum.Material.Concrete
	), "ConcreteAll")

	local stationColors = {
		Color3.fromRGB(82, 255, 180),
		Color3.fromRGB(88, 218, 255),
		Color3.fromRGB(168, 255, 112),
		Color3.fromRGB(126, 196, 255),
	}
	local offsets = {
		Vector3.new(-9, 0.18, -13.2),
		Vector3.new(9, 0.18, -13.2),
		Vector3.new(-9, 0.18, 13.2),
		Vector3.new(9, 0.18, 13.2),
	}
	for index, offset in ipairs(offsets) do
		local queueId = (level - 1) * 4 + index
		local station = addQueueStation(roomModel, roomCenter, queueId, offset, active and stationColors[index] or COLORS.red, active, index, level)
		if station then
			stations[queueId] = station
		end
	end

	for _, x in ipairs({-11.2, 11.2}) do
		local lamp = makePart(
			roomModel,
			"ChamberLight",
			CFrame.new(roomCenter + Vector3.new(x, roomHeight - 0.55, 0)),
			Vector3.new(11.2, 0.22, 1.8),
			active and Color3.fromRGB(229, 239, 221) or Color3.fromRGB(255, 87, 67),
			Enum.Material.Neon,
			active and 0 or 0.35
		)
		lamp.CanCollide = false
		local light = Instance.new("PointLight")
		light.Color = active and Color3.fromRGB(226, 236, 214) or Color3.fromRGB(255, 82, 66)
		light.Brightness = active and 1.25 or 0.65
		light.Range = 31
		light.Parent = lamp
	end

	roomModel:SetAttribute("LevelNumber", level)
	roomModel:SetAttribute("LevelEnabled", active)
	return roomModel
end

local function addDoorway(parent, center, level, side, zOffset, active)
	local x = center.X + side * 34
	local z = center.Z + zOffset
	local face = side < 0 and Enum.NormalId.Right or Enum.NormalId.Left

	for _, zSide in ipairs({-1, 1}) do
		tagSurface(makePart(
			parent,
			"Level" .. level .. "DoorPost",
			CFrame.new(x, center.Y + 7.3, z + zSide * 9.8),
			Vector3.new(3.1, 15, 1.55),
			COLORS.metal,
			Enum.Material.Metal
		), "Metal")
	end
	tagSurface(makePart(
		parent,
		"Level" .. level .. "DoorHeader",
		CFrame.new(x, center.Y + 15, z),
		Vector3.new(3.1, 2.1, 21),
		COLORS.metal,
		Enum.Material.Metal
	), "Metal")

	local header = makePart(
		parent,
		"Level" .. level .. "Information",
		-- Pull the sign toward the roadway so the curved shell cannot hide it.
		CFrame.new(x - side * 7.5, center.Y + 15.8, z),
		Vector3.new(0.48, 4.4, 19),
		COLORS.metal,
		Enum.Material.Metal
	)
	header.CanCollide = false
	addBoard(
		header,
		face,
		"EXIT  •  LEVEL " .. level,
		active and "4 QUEUES  •  MAX 6 EACH  •  10 SECOND LAUNCH" or "ANOMALOUS ACCESS POINT  •  NOT YET STABLE",
		active and COLORS.green or COLORS.amber
	)

	local exitPanel = makePart(
		parent,
		"Level" .. level .. "ExitMarker",
		CFrame.new(x - side * 7.58, center.Y + 19.15, z),
		Vector3.new(0.36, 1.5, 8.5),
		active and Color3.fromRGB(24, 96, 57) or Color3.fromRGB(100, 63, 24),
		Enum.Material.Metal
	)
	exitPanel.CanCollide = false
	addBoard(exitPanel, face, "EXIT", active and "ACCESS READY" or "ACCESS PENDING", active and COLORS.green or COLORS.amber)

	if not active then
		local blocker = makePart(
			parent,
			"Level" .. level .. "SealedDoor",
			CFrame.new(x, center.Y + 7, z),
			Vector3.new(2.25, 13.8, 18),
			COLORS.metalLight,
			Enum.Material.DiamondPlate
		)
		tagSurface(blocker, "Metal")
		local blockedTitle, blockedSubtitle = addBoard(
			blocker,
			face,
			"ACCESS UNSTABLE",
			"STILL TRYING TO BREACH THIS ANOMALOUS SPACE",
			COLORS.red
		)
		blockedTitle.TextScaled = false
		blockedTitle.TextSize = 58
		blockedTitle.TextWrapped = false
		blockedSubtitle.TextScaled = false
		blockedSubtitle.TextSize = 26
		blockedSubtitle.TextWrapped = false
	end
end

function Builder.Build(center)
	local old = workspace:FindFirstChild("ServerLobby")
	if old then
		old:Destroy()
	end

	local model = Instance.new("Model")
	model.Name = "ServerLobby"
	model.Parent = workspace
	model:SetAttribute("LobbyStyle", "ZyntraTunnel")
	model:SetAttribute("TextureVersion", 1)

	local geometry = Instance.new("Folder")
	geometry.Name = "TunnelGeometry"
	geometry.Parent = model
	local rooms = Instance.new("Folder")
	rooms.Name = "LevelQueueRooms"
	rooms.Parent = model
	local doors = Instance.new("Folder")
	doors.Name = "LevelDoorways"
	doors.Parent = model
	local lights = Instance.new("Folder")
	lights.Name = "TunnelLighting"
	lights.Parent = model
	local detail = Instance.new("Folder")
	detail.Name = "TunnelDetails"
	detail.Parent = model

	local tunnelLength = 280
	local halfLength = tunnelLength * 0.5
	local radius = 35
	local shellBaseY = center.Y + 1
	local shellSegments = 16
	local shellChord = 2 * radius * math.sin(math.pi / shellSegments) + 0.6

	-- Road, ledges, curbs, and lane paint.
	local road = makePart(
		geometry,
		"MainAsphaltRoad",
		CFrame.new(center + Vector3.new(0, -0.55, 0)),
		Vector3.new(33, 1.1, tunnelLength),
		COLORS.asphalt,
		Enum.Material.Asphalt
	)
	tagSurface(road, "Asphalt")

	for _, side in ipairs({-1, 1}) do
		local walkway = makePart(
			geometry,
			"RaisedServiceLedge",
			CFrame.new(center + Vector3.new(side * 25, 0.05, 0)),
			-- Reach 0.3 studs underneath the lower tunnel wall. The old 14.5
			-- width stopped 0.65 studs short and exposed a long void trench.
			Vector3.new(16.4, 1.2, tunnelLength),
			COLORS.curb,
			Enum.Material.Concrete
		)
		tagSurface(walkway, "FloorConcrete")

		local curb = makePart(
			geometry,
			"RoadCurb",
			CFrame.new(center + Vector3.new(side * 17.1, 0.12, 0)),
			Vector3.new(1.4, 1.45, tunnelLength),
			COLORS.concreteLight,
			Enum.Material.Concrete
		)
		tagSurface(curb, "Curb")

		local edgeLine = makePart(
			geometry,
			"RoadEdgePaint",
			CFrame.new(center + Vector3.new(side * 15.65, 0.03, 0)),
			Vector3.new(0.42, 0.08, tunnelLength - 4),
			COLORS.paint,
			Enum.Material.SmoothPlastic
		)
		edgeLine.CanCollide = false
		tagSurface(edgeLine, "RoadPaint")

		local conduit = makePart(
			detail,
			"WallConduit",
			CFrame.new(center + Vector3.new(side * 33.2, 10.5, 0)),
			Vector3.new(0.65, 0.65, tunnelLength - 6),
			COLORS.metal,
			Enum.Material.Metal
		)
		conduit.CanCollide = false
	end

	for z = -halfLength + 10, halfLength - 10, 16 do
		local dash = makePart(
			geometry,
			"CenterLaneDash",
			CFrame.new(center + Vector3.new(0, 0.035, z)),
			Vector3.new(0.58, 0.09, 7.5),
			COLORS.paint,
			Enum.Material.SmoothPlastic
		)
		dash.CanCollide = false
		tagSurface(dash, "RoadPaint")
	end

	local doorwayZ = {-80, 0, 80}
	local wallRanges = {
		{-halfLength, -90},
		{-70, -10},
		{10, 70},
		{90, halfLength},
	}

	-- Curved concrete shell. The two lowest panels on each side are segmented
	-- around the level bays; full-length low panels would physically wall off
	-- every doorway even though the decorative frames remained visible.
	for i = 1, shellSegments - 1 do
		local theta = math.pi * (i / shellSegments)
		local position = center + Vector3.new(
			math.cos(theta) * radius,
			1 + math.sin(theta) * radius,
			0
		)
		local segmentedAtDoors = i <= 2 or i >= shellSegments - 2
		local ranges = segmentedAtDoors and wallRanges or {{-halfLength, halfLength}}
		for _, range in ipairs(ranges) do
			local zMid = (range[1] + range[2]) * 0.5
			local zSize = range[2] - range[1]
			local panel = makePart(
				geometry,
				segmentedAtDoors and "DoorClearanceShell" or "CurvedConcreteShell",
				CFrame.new(position + Vector3.new(0, 0, zMid)) * CFrame.Angles(0, 0, theta - math.pi * 0.5),
				Vector3.new(shellChord, 2.2, zSize),
				COLORS.concrete,
				Enum.Material.Concrete
			)
			tagSurface(panel, "Concrete")
		end
	end

	for _, side in ipairs({-1, 1}) do
		for _, range in ipairs(wallRanges) do
			local zMid = (range[1] + range[2]) * 0.5
			local zSize = range[2] - range[1]
			local wall = makePart(
				geometry,
				"LowerTunnelWall",
				CFrame.new(center + Vector3.new(side * 34, 7, zMid)),
				Vector3.new(2.2, 14, zSize),
				COLORS.concrete,
				Enum.Material.Concrete
			)
			tagSurface(wall, "Concrete")
		end
		for _, z in ipairs(doorwayZ) do
			local lintel = makePart(
				geometry,
				"EntranceLintelWall",
				CFrame.new(center + Vector3.new(side * 34, 18.4, z)),
				Vector3.new(2.2, 8.8, 20),
				COLORS.concrete,
				Enum.Material.Concrete
			)
			tagSurface(lintel, "Concrete")
		end
	end

	-- Reinforcing ribs and ceiling service tracks.
	for z = -halfLength + 8, halfLength - 8, 20 do
		for i = 1, shellSegments - 1 do
			local theta = math.pi * (i / shellSegments)
			local position = center + Vector3.new(
				math.cos(theta) * (radius - 1.2),
				1 + math.sin(theta) * (radius - 1.2),
				z
			)
			local rib = makePart(
				detail,
				"TunnelReinforcementRib",
				CFrame.new(position) * CFrame.Angles(0, 0, theta - math.pi * 0.5),
				Vector3.new(shellChord, 1.1, 0.72),
				COLORS.metal,
				Enum.Material.Metal
			)
			rib.CanCollide = false
			tagSurface(rib, "Metal")
		end
	end

	for _, x in ipairs({-9, 9}) do
		local track = makePart(
			detail,
			"CeilingServiceTrack",
			CFrame.new(center + Vector3.new(x, 30.3, 0)),
			Vector3.new(0.6, 0.55, tunnelLength - 8),
			COLORS.metal,
			Enum.Material.Metal
		)
		track.CanCollide = false
	end

	for z = -halfLength + 12, halfLength - 12, 19 do
		addLamp(lights, center, -9, z)
		addLamp(lights, center, 9, z)
	end

	for z = -halfLength + 8, halfLength - 8, 12 do
		for _, side in ipairs({-1, 1}) do
			local marker = makePart(
				lights,
				"EmergencyCurbMarker",
				CFrame.new(center + Vector3.new(side * 16.45, 0.7, z)),
				Vector3.new(0.28, 0.45, 0.75),
				z % 24 == 0 and COLORS.red or COLORS.amber,
				Enum.Material.Neon
			)
			marker.CanCollide = false
			local glow = Instance.new("PointLight")
			glow.Color = marker.Color
			glow.Brightness = 0.35
			glow.Range = 6
			glow.Parent = marker
		end
	end

	local stations = {}
	local levelDefs = {
		{level = 1, side = -1, z = -80, active = true},
		{level = 2, side = 1, z = -80, active = true},
		{level = 3, side = -1, z = 0, active = false},
		{level = 4, side = 1, z = 0, active = false},
		{level = 5, side = -1, z = 80, active = false},
		{level = 6, side = 1, z = 80, active = false},
	}
	for _, def in ipairs(levelDefs) do
		addDoorway(doors, center, def.level, def.side, def.z, def.active)
		addRoom(rooms, center, def.level, def.side, def.z, def.active, stations)
	end

	-- Startup fingerprint. This is the fastest way to tell a stale server apart
	-- from a code problem: if the log does not list the bay, the running build
	-- is older than the change that opened it.
	local activeBays, stationCount = {}, 0
	for _, def in ipairs(levelDefs) do
		if def.active then table.insert(activeBays, def.level) end
	end
	for _ in pairs(stations) do stationCount += 1 end
	print(string.format("[TunnelLobbyBuilder] bays open: %s  |  launch stations: %d",
		table.concat(activeBays, ", "), stationCount))

	-- Dense abandoned-office barricades replace the old flat wallpaper caps.
	-- `inward` points from each finite end back into the playable tunnel.
	addTunnelEndBarricade(detail, center, -halfLength + 1.2, 1, 1993)
	addTunnelEndBarricade(detail, center, halfLength - 1.2, -1, 1997)

	local spawn = Instance.new("SpawnLocation")
	spawn.Name = "LobbySpawn"
	spawn.Anchored = true
	local spawnPosition = center + Vector3.new(0, 0.4, -100)
	-- Keep enough clearance behind a third-person camera for the new dense end
	-- barricade, and face arrivals toward the level stations.
	spawn.CFrame = CFrame.lookAt(spawnPosition, center + Vector3.new(0, 0.4, 0))
	spawn.Size = Vector3.new(8, 0.5, 8)
	spawn.Transparency = 1
	spawn.Neutral = true
	spawn.Enabled = true
	spawn.Duration = 0 -- remove Roblox's default join/spawn ForceField glow
	spawn.Parent = model
	spawn.CanCollide = false
	spawn.CanTouch = false
	spawn.CanQuery = false

	local welcome = makePart(
		detail,
		"ZyntraWelcomeBoard",
		CFrame.new(center + Vector3.new(0, 13.5, -138.1)) * CFrame.Angles(0, math.pi, 0),
		Vector3.new(26, 7.5, 0.55),
		COLORS.metal,
		Enum.Material.Metal
	)
	welcome.CanCollide = false
	addBoard(
		welcome,
		Enum.NormalId.Front,
		"ZYNTRA TRANSIT ACCESS",
		"POWERING THE FUTURE.  •  PROCEED TO AN AUTHORIZED LEVEL BAY",
		COLORS.green
	)

	local farWarning = makePart(
		detail,
		"FarEndWarning",
		CFrame.new(center + Vector3.new(0, 12, 138.05)),
		Vector3.new(21, 5.5, 0.5),
		COLORS.metal,
		Enum.Material.Metal
	)
	farWarning.CanCollide = false
	addBoard(
		farWarning,
		Enum.NormalId.Front,
		"NO SURFACE ROUTE",
		"RETURN TO YOUR ASSIGNED ACCESS BAY",
		COLORS.red
	)

	return model, spawn, stations
end

return Builder
