-- TunnelLobbyBuilder
-- Modular Zyntra transit lobby used by GameManager.
-- Geometry is intentionally built from simple anchored parts so the lobby remains
-- easy to resize, texture, and extend when more levels are enabled.

local Builder = {}
local TweenService = game:GetService("TweenService")
local ReplicatedStorage = game:GetService("ReplicatedStorage")

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

-- The Level 1 loading bay borrows the actual Level 1 material language.
-- These are cosmetic-only and never alter the bay's queue geometry or triggers.
local LEVEL_ONE_BAY_STYLE = {
	wallTexture = "rbxassetid://87947439437597",
	floorTexture = "rbxassetid://100093931957721",
	ceilingTexture = "rbxassetid://91804597609254",
	litFixtureTexture = "rbxassetid://135786374638992",
	wallColor = Color3.fromRGB(197, 180, 116),
	floorColor = Color3.fromRGB(158, 144, 96),
	ceilingColor = Color3.fromRGB(222, 214, 170),
	lightColor = Color3.fromRGB(255, 244, 200),
	tile = 6,
}

-- Lobby-only interpretations of the live Level 2 and Level 3 art direction.
-- They deliberately reuse the games' real texture IDs and palettes, but none of
-- their runtime names, tags, prompts, physics, or objective attributes.
local LEVEL_TWO_BAY_STYLE = {
	tileTexture = "rbxassetid://113211706146395",
	tileTint = Color3.fromRGB(248, 242, 218),
	wallColor = Color3.fromRGB(206, 221, 212),
	floorColor = Color3.fromRGB(236, 227, 196),
	ceilingColor = Color3.fromRGB(228, 224, 205),
	metalColor = Color3.fromRGB(83, 96, 99),
	railColor = Color3.fromRGB(196, 202, 205),
	waterColor = Color3.fromRGB(48, 150, 159),
	lightColor = Color3.fromRGB(255, 247, 210),
	tile = 7,
}

local LEVEL_THREE_BAY_STYLE = {
	partyCarpetTexture = "rbxassetid://110230144446272",
	wallpaperTexture = "rbxassetid://96252806287644",
	orangeWallTexture = "rbxassetid://128270554927663",
	confettiTexture = "rbxassetid://103412925025303",
	partyCarpetColor = Color3.fromRGB(13, 17, 24),
	wallpaperColor = Color3.fromRGB(220, 213, 187),
	orangeWallColor = Color3.fromRGB(183, 78, 35),
	ceilingColor = Color3.fromRGB(218, 211, 184),
	lightColor = Color3.fromRGB(255, 222, 181),
	carpetTile = 22,
	wallpaperTile = 18,
	orangeWallTile = 22,
	tableclothTile = 10,
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
	local circularOffsetU = part:GetAttribute("CircularTextureOffsetU")
	if type(circularOffsetU) == "number" then
		texture.OffsetStudsU = circularOffsetU
	end
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
			-- Chamber floors are horizontal Cylinder parts whose upward circular cap
			-- is local Right after the 90-degree rotation. Ordinary floors remain Top.
			faces = { part.Shape == Enum.PartType.Cylinder and Enum.NormalId.Right or Enum.NormalId.Top }
		elseif role == "Curb" then
			faces = { Enum.NormalId.Top, Enum.NormalId.Left, Enum.NormalId.Right }
		elseif part.Name == "CurvedChamberWall" then
			-- The exterior faces void. One interior texture per leaf keeps the finer
			-- circular shell inexpensive and avoids mirrored seams on its hidden back.
			faces = { Enum.NormalId.Front }
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
	background.ClipsDescendants = true
	background.Parent = gui

	-- Every lobby display shares the same softened Zyntra enclosure treatment.
	-- UICorner shapes the visible sign face while the rounded stroke preserves a
	-- crisp silhouette at long tunnel distances.
	local backgroundCorner = Instance.new("UICorner")
	backgroundCorner.Name = "RoundedSignCorners"
	backgroundCorner.CornerRadius = UDim.new(0.08, 0)
	backgroundCorner.Parent = background

	local backgroundBorder = Instance.new("UIStroke")
	backgroundBorder.Name = "RoundedSignBorder"
	backgroundBorder.ApplyStrokeMode = Enum.ApplyStrokeMode.Border
	backgroundBorder.Color = titleColor:Lerp(Color3.fromRGB(102, 112, 108), 0.38)
	backgroundBorder.Thickness = 6
	backgroundBorder.Transparency = 0.22
	backgroundBorder.LineJoinMode = Enum.LineJoinMode.Round
	backgroundBorder.Parent = background

	local line = Instance.new("Frame")
	line.Position = UDim2.new(0.04, 0, 0.74, 0)
	line.Size = UDim2.new(0.92, 0, 0, 4)
	line.BackgroundColor3 = titleColor
	line.BackgroundTransparency = 0.22
	line.BorderSizePixel = 0
	line.Parent = background
	local lineCorner = Instance.new("UICorner")
	lineCorner.CornerRadius = UDim.new(1, 0)
	lineCorner.Parent = line

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

local function addDonationLeaderboard(parent, center)
	local model = Instance.new("Model")
	model.Name = "ZyntraDonationLeaderboardBoard"
	model:SetAttribute("LeaderboardVersion", 2)
	model:SetAttribute("RankingScope", "Donation Developer Products recorded since August 2026")
	model.Parent = parent

	local panel = makePart(
		model,
		"LeaderboardPanel",
		CFrame.new(center + Vector3.new(-30, 7.15, -35)),
		Vector3.new(0.62, 12.6, 18),
		Color3.fromRGB(25, 31, 30),
		Enum.Material.Metal
	)
	panel.CanCollide = false
	panel.CanTouch = false
	panel.CanQuery = false

	-- Moving the display clear of the curved ceiling leaves a narrow space behind
	-- it. Fill from the tunnel wall through the panel's front face with one solid,
	-- invisible convex block: players cannot walk through the display or enter a
	-- pocket behind it, and the main walkway still retains almost 13 studs.
	local collision = makePart(
		model,
		"LeaderboardCollision",
		CFrame.new(center + Vector3.new(-31.37, 7.05, -35)),
		Vector3.new(3.36, 12.8, 18),
		Color3.new(0, 0, 0),
		Enum.Material.SmoothPlastic
	)
	collision.Transparency = 1
	collision.CanCollide = true
	collision.CanTouch = false
	collision.CanQuery = true
	collision.CastShadow = false

	local gui = Instance.new("SurfaceGui")
	gui.Name = "DonationLeaderboardDisplay"
	gui.Face = Enum.NormalId.Right
	gui.CanvasSize = Vector2.new(900, 660)
	gui.LightInfluence = 0
	gui.AlwaysOnTop = false
	gui.Parent = panel

	local background = Instance.new("Frame")
	background.Size = UDim2.fromScale(1, 1)
	background.BackgroundColor3 = Color3.fromRGB(6, 11, 10)
	background.BackgroundTransparency = 0.03
	background.BorderSizePixel = 0
	background.Parent = gui
	local backgroundCorner = Instance.new("UICorner")
	backgroundCorner.CornerRadius = UDim.new(0, 26)
	backgroundCorner.Parent = background
	local border = Instance.new("UIStroke")
	border.ApplyStrokeMode = Enum.ApplyStrokeMode.Border
	border.Color = COLORS.green
	border.Thickness = 5
	border.Transparency = 0.24
	border.Parent = background

	local title = Instance.new("TextLabel")
	title.Name = "Title"
	title.Position = UDim2.fromOffset(38, 22)
	title.Size = UDim2.new(1, -76, 0, 58)
	title.BackgroundTransparency = 1
	title.Font = Enum.Font.GothamBlack
	title.Text = "TOP DONORS"
	title.TextColor3 = COLORS.green
	title.TextSize = 43
	title.TextXAlignment = Enum.TextXAlignment.Left
	title.Parent = background

	local status = Instance.new("TextLabel")
	status.Name = "Status"
	status.Position = UDim2.fromOffset(40, 78)
	status.Size = UDim2.new(1, -80, 0, 30)
	status.BackgroundTransparency = 1
	status.Font = Enum.Font.Code
	status.Text = "CONNECTING TO DONATION RANKINGS"
	status.TextColor3 = Color3.fromRGB(215, 205, 165)
	status.TextSize = 19
	status.TextXAlignment = Enum.TextXAlignment.Left
	status.Parent = background

	local divider = Instance.new("Frame")
	divider.Position = UDim2.fromOffset(38, 116)
	divider.Size = UDim2.new(1, -76, 0, 3)
	divider.BackgroundColor3 = COLORS.green
	divider.BackgroundTransparency = 0.25
	divider.BorderSizePixel = 0
	divider.Parent = background

	local rowLabels = {}
	for rank = 1, 10 do
		local row = Instance.new("TextLabel")
		row.Name = string.format("Rank%02d", rank)
		row.Position = UDim2.fromOffset(38, 128 + (rank - 1) * 50)
		row.Size = UDim2.new(1, -76, 0, 42)
		row.BackgroundColor3 = rank % 2 == 1 and Color3.fromRGB(15, 25, 22) or Color3.fromRGB(10, 17, 15)
		row.BackgroundTransparency = 0.12
		row.BorderSizePixel = 0
		row.Font = Enum.Font.Code
		row.Text = rank == 1 and "NO DONATIONS RECORDED YET" or ""
		row.TextColor3 = rank <= 3 and Color3.fromRGB(236, 224, 165) or Color3.fromRGB(201, 225, 214)
		row.TextSize = 24
		row.TextXAlignment = Enum.TextXAlignment.Left
		row.Parent = background
		local padding = Instance.new("UIPadding")
		padding.PaddingLeft = UDim.new(0, 16)
		padding.PaddingRight = UDim.new(0, 16)
		padding.Parent = row
		local corner = Instance.new("UICorner")
		corner.CornerRadius = UDim.new(0, 8)
		corner.Parent = row
		rowLabels[rank] = row
	end

	task.spawn(function()
		local values = ReplicatedStorage:WaitForChild("ZyntraDonationLeaderboard", 15)
		if not values or not model.Parent then return end
		local connections = {}
		local function bind(value, render)
			if not value or not value:IsA("StringValue") then return end
			render(value.Value)
			connections[#connections + 1] = value:GetPropertyChangedSignal("Value"):Connect(function()
				if model.Parent then render(value.Value) end
			end)
		end
		bind(values:FindFirstChild("Status"), function(value) status.Text = value end)
		for rank, label in ipairs(rowLabels) do
			bind(values:FindFirstChild(string.format("Row%02d", rank)), function(value) label.Text = value end)
		end
		connections[#connections + 1] = model.AncestryChanged:Connect(function(_, newParent)
			if newParent then return end
			for _, connection in ipairs(connections) do connection:Disconnect() end
			table.clear(connections)
		end)
	end)

	return model
end

local function makeStationMonitorPart(parent, name, cf, size, color, material, shape)
	local part = makePart(parent, name, cf, size, color, material)
	part.CanCollide = false
	part.CanTouch = false
	part.CanQuery = false
	part.CastShadow = false
	if shape then
		part.Shape = shape
	end
	part:SetAttribute("StationMonitorDecor", true)
	return part
end

local function makeStationMonitorArm(parent, name, pointA, pointB, thickness)
	local delta = pointB - pointA
	local arm = makeStationMonitorPart(
		parent,
		name,
		CFrame.lookAt((pointA + pointB) * 0.5, pointB),
		Vector3.new(thickness, thickness, delta.Magnitude),
		Color3.fromRGB(49, 55, 54),
		Enum.Material.Metal
	)
	arm:SetAttribute("MonitorArm", true)
	return arm
end

local function makeWayfindingFixturePart(parent, name, cf, size, color, material, shape)
	local part = makePart(parent, name, cf, size, color, material)
	part.CanCollide = false
	part.CanTouch = false
	part.CanQuery = false
	part.CastShadow = false
	if shape then
		part.Shape = shape
	end
	part:SetAttribute("WayfindingSignFixture", true)
	return part
end

local function makeWayfindingArm(parent, name, pointA, pointB, thickness)
	local delta = pointB - pointA
	return makeWayfindingFixturePart(
		parent,
		name,
		CFrame.lookAt((pointA + pointB) * 0.5, pointB),
		Vector3.new(thickness, thickness, delta.Magnitude),
		Color3.fromRGB(47, 53, 52),
		Enum.Material.Metal
	)
end

local function addMountedLevelSign(parent, center, panel, level, side, accentColor)
	local width, height = panel.Size.Z, panel.Size.Y
	local depth = 0.72
	local centerWidth = math.max(width - height, 0.5)
	local backingCF = panel.CFrame * CFrame.new(side * 0.32, 0, 0)
	local backingColor = Color3.fromRGB(17, 22, 21)

	local body = makeWayfindingFixturePart(
		parent,
		"Level" .. level .. "RoundedSignBody",
		backingCF,
		Vector3.new(depth, height, centerWidth),
		backingColor,
		Enum.Material.Metal
	)
	body:SetAttribute("RoundedLevelSignBacking", true)

	for _, direction in ipairs({-1, 1}) do
		local cap = makeWayfindingFixturePart(
			parent,
			"Level" .. level .. (direction < 0 and "RoundedSignCapA" or "RoundedSignCapB"),
			backingCF * CFrame.new(0, 0, direction * centerWidth * 0.5),
			Vector3.new(depth, height, height),
			backingColor,
			Enum.Material.Metal,
			Enum.PartType.Cylinder
		)
		cap:SetAttribute("RoundedLevelSignBacking", true)
	end

	local signTopY = panel.Position.Y + height * 0.5
	local armY = signTopY + 1.45
	local wallX = center.X + side * 33.05
	local signBackX = panel.Position.X + side * 0.42
	for index, zDirection in ipairs({-1, 1}) do
		local mountZ = panel.Position.Z + zDirection * width * 0.32
		local wallPoint = Vector3.new(wallX, armY, mountZ)
		local signPoint = Vector3.new(signBackX, armY, mountZ)
		local hangerPoint = Vector3.new(signBackX, signTopY + 0.08, mountZ)
		makeWayfindingArm(parent, "Level" .. level .. "SignCantilever" .. index, wallPoint, signPoint, 0.34)
		makeWayfindingArm(parent, "Level" .. level .. "SignHanger" .. index, signPoint, hangerPoint, 0.28)
		makeWayfindingFixturePart(
			parent,
			"Level" .. level .. "SignWallPlate" .. index,
			CFrame.new(wallPoint),
			Vector3.new(0.42, 2.15, 1.2),
			Color3.fromRGB(58, 64, 62),
			Enum.Material.Metal
		)
		makeWayfindingFixturePart(
			parent,
			"Level" .. level .. "SignJoint" .. index,
			CFrame.new(signPoint),
			Vector3.new(0.68, 0.68, 0.68),
			Color3.fromRGB(68, 75, 72),
			Enum.Material.Metal,
			Enum.PartType.Ball
		)
	end

	local accentRail = makeWayfindingFixturePart(
		parent,
		"Level" .. level .. "RoundedSignAccent",
		backingCF * CFrame.new(-side * (depth * 0.5 + 0.04), -height * 0.5 + 0.16, 0),
		Vector3.new(0.1, 0.14, width - height * 0.3),
		accentColor,
		Enum.Material.Neon
	)
	accentRail:SetAttribute("LevelSignAccentRail", true)

	panel.Transparency = 1
	panel:SetAttribute("RoundedLevelSign", true)
	panel:SetAttribute("LintelMountedLevelSign", true)
end

local function addMountedStationMonitor(parent, roomCenter, signPanel, index, accentColor)
	local width, height = signPanel.Size.X, signPanel.Size.Y
	local depth = 0.52
	local capDiameter = height
	local centerWidth = math.max(width - capDiameter, 0.5)
	local backingOffset = 0.36
	local backingColor = Color3.fromRGB(20, 25, 24)

	local body = makeStationMonitorPart(
		parent,
		"Station" .. index .. "MonitorBacking",
		signPanel.CFrame * CFrame.new(0, 0, backingOffset),
		Vector3.new(centerWidth, height, depth),
		backingColor,
		Enum.Material.Metal
	)
	body:SetAttribute("RoundedMonitorBacking", true)

	for _, direction in ipairs({ -1, 1 }) do
		local cap = makeStationMonitorPart(
			parent,
			"Station" .. index .. (direction < 0 and "MonitorCapLeft" or "MonitorCapRight"),
			signPanel.CFrame
				* CFrame.new(direction * centerWidth * 0.5, 0, backingOffset)
				* CFrame.Angles(0, math.rad(90), 0),
			Vector3.new(depth, capDiameter, capDiameter),
			backingColor,
			Enum.Material.Metal,
			Enum.PartType.Cylinder
		)
		cap:SetAttribute("RoundedMonitorBacking", true)
	end

	local radialOffset = signPanel.Position - roomCenter
	local outward = Vector3.new(radialOffset.X, 0, radialOffset.Z).Unit
	local wallPoint = roomCenter
		+ outward * 26.72
		+ Vector3.new(0, radialOffset.Y + 0.72, 0)
	local wallPlate = makeStationMonitorPart(
		parent,
		"Station" .. index .. "MonitorWallPlate",
		CFrame.lookAt(wallPoint, wallPoint - outward),
		Vector3.new(2.25, 2.7, 0.34),
		Color3.fromRGB(59, 64, 62),
		Enum.Material.Metal
	)
	wallPlate:SetAttribute("MonitorWallMount", true)

	local monitorHub = signPanel.CFrame:PointToWorldSpace(Vector3.new(0, 0, 0.48))
	local elbow = signPanel.Position + outward * 2.35 + Vector3.new(0, 0.92, 0)
	local wallHub = wallPoint - outward * 0.24
	makeStationMonitorArm(parent, "Station" .. index .. "MonitorArmInner", monitorHub, elbow, 0.42)
	makeStationMonitorArm(parent, "Station" .. index .. "MonitorArmWall", elbow, wallHub, 0.42)

	for jointIndex, point in ipairs({ monitorHub, elbow, wallHub }) do
		local joint = makeStationMonitorPart(
			parent,
			"Station" .. index .. "MonitorJoint" .. jointIndex,
			CFrame.new(point),
			Vector3.new(0.76, 0.76, 0.76),
			jointIndex == 2 and accentColor:Lerp(Color3.fromRGB(70, 74, 71), 0.68)
				or Color3.fromRGB(66, 71, 69),
			Enum.Material.Metal,
			Enum.PartType.Ball
		)
		joint:SetAttribute("MonitorArmJoint", true)
	end

	signPanel:SetAttribute("RoundedStationMonitor", true)
	signPanel:SetAttribute("WallMountedMonitor", true)
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
	lens.Color = Color3.fromRGB(255, 234, 191)
	lens:SetAttribute("PartyCeilingLight", true)

	local point = Instance.new("PointLight")
	point.Color = Color3.fromRGB(255, 230, 178)
	point.Brightness = 1.25
	point.Range = 24
	point.Shadows = false
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
	local inwardZ = offset.Z < 0 and 1 or -1
	local zoneCF = CFrame.lookAt(origin, origin + Vector3.new(0, 0, inwardZ))
	local visualDiameter = 11.4 * 1.3
	local queueRadius = visualDiameter * 0.5

	-- The invisible detector matches the enlarged circular artwork. NOTE:
	-- GameManager's playerInsideZone currently does rectangular X/Z containment
	-- on this square part — the QueueRadius/shape attributes below describe the
	-- artwork, they are not read by any script yet.
	local zone = makePart(
		parent,
		(active and "LaunchZone" or "FutureLaunchZone") .. index,
		zoneCF,
		Vector3.new(visualDiameter, 0.3, visualDiameter),
		color,
		Enum.Material.SmoothPlastic,
		1
	)
	zone.CanCollide = false
	zone.CanTouch = false
	zone.CanQuery = false
	zone.CastShadow = false
	zone:SetAttribute("QueueDetectorShape", "Circle")
	zone:SetAttribute("QueueRadius", queueRadius)
	zone:SetAttribute("CircularPadDiameter", visualDiameter)

	-- A SurfaceGui gives the launch station a mathematically circular edge with
	-- no polygon facets and far fewer parts than an arc made from tiny blocks.
	local padVisual = makePart(
		parent,
		"Station" .. index .. "CircularPad",
		zoneCF * CFrame.new(0, 0.27, 0),
		Vector3.new(visualDiameter, 0.05, visualDiameter),
		color,
		Enum.Material.SmoothPlastic,
		1
	)
	padVisual.CanCollide = false
	padVisual.CanTouch = false
	padVisual.CanQuery = false
	padVisual.CastShadow = false
	padVisual:SetAttribute("CircularLaunchVisual", true)
	padVisual:SetAttribute("StationIndex", index)
	padVisual:SetAttribute("Diameter", visualDiameter)
	padVisual:SetAttribute("NearestCircleGap", 18 - visualDiameter)

	local padGui = Instance.new("SurfaceGui")
	padGui.Name = "CircularPadSurface"
	padGui.Face = Enum.NormalId.Top
	padGui.SizingMode = Enum.SurfaceGuiSizingMode.PixelsPerStud
	padGui.PixelsPerStud = 32
	padGui.LightInfluence = 0
	padGui.Brightness = active and 2 or 0.7
	padGui.AlwaysOnTop = false
	padGui.Parent = padVisual

	local circle = Instance.new("Frame")
	circle.Name = "Circle"
	circle.Size = UDim2.fromScale(1, 1)
	circle.BackgroundColor3 = color
	circle.BackgroundTransparency = active and 0.78 or 0.91
	circle.BorderSizePixel = 0
	circle.Parent = padGui

	local corner = Instance.new("UICorner")
	corner.CornerRadius = UDim.new(1, 0)
	corner.Parent = circle

	local outline = Instance.new("UIStroke")
	outline.Name = "CircularOutline"
	outline.ApplyStrokeMode = Enum.ApplyStrokeMode.Border
	outline.Color = color
	outline.Thickness = active and 11 or 8
	outline.Transparency = active and 0.08 or 0.58
	outline.LineJoinMode = Enum.LineJoinMode.Round
	outline.Parent = circle

	local signPosition = origin + Vector3.new(0, 5.2 * stationScale, (offset.Z < 0 and -5.1 or 5.1) * stationScale)
	local signPanel = makePart(
		parent,
		"Station" .. index .. "Sign",
		CFrame.lookAt(signPosition, origin + Vector3.new(0, 4.4, 0)),
		Vector3.new(8.7 * stationScale, 3.1 * stationScale, 0.08),
		COLORS.metal,
		Enum.Material.SmoothPlastic,
		1
	)
	signPanel.CanCollide = false
	signPanel.CanTouch = false
	signPanel.CanQuery = false
	signPanel.CastShadow = false

	local title, subtitle = addBoard(
		signPanel,
		Enum.NormalId.Front,
		active and ("STATION " .. (displayIndex or index) .. "  •  0/6") or ("STATION " .. (displayIndex or index) .. "  •  OFFLINE"),
		active and "ENTER TO HOST  •  MAX 6 PLAYERS" or "AWAITING LEVEL AUTHORIZATION",
		color
	)

	local displayGui = signPanel:FindFirstChild("Display")
	if displayGui and displayGui:IsA("SurfaceGui") then
		-- AlwaysOnTop must stay FALSE: it made every station monitor render
		-- through the chamber walls. LightInfluence=0 already keeps the screen
		-- readable and glowing without skipping the depth test.
		displayGui.AlwaysOnTop = false
		displayGui.MaxDistance = 90
	end

	local screen = title.Parent
	screen.ClipsDescendants = true

	addMountedStationMonitor(parent, roomCenter, signPanel, index, color)

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

local function addLevelOneTexture(part, textureId, faces, tileU, tileV)
	if textureId == "" then return end
	for _, child in ipairs(part:GetChildren()) do
		if child:IsA("Texture") and child.Name == "LobbyConcreteTexture" then
			child:Destroy()
		end
	end
	for _, face in ipairs(faces) do
		local texture = Instance.new("Texture")
		texture.Name = "Level1BayTexture"
		texture.Texture = textureId
		texture.Face = face
		texture.StudsPerTileU = tileU
		texture.StudsPerTileV = tileV or tileU
		local circularOffsetU = part:GetAttribute("CircularTextureOffsetU")
		if type(circularOffsetU) == "number" then
			texture.OffsetStudsU = circularOffsetU
		end
		texture.Parent = part
	end
end

local function makeLevelOneDecorPart(parent, name, cf, size, color, material, solid)
	local part = makePart(parent, name, cf, size, color, material)
	-- floor-standing furniture is SOLID so players cannot walk through it;
	-- wall-glitched geometry stays intangible so it can never wedge anyone
	-- into the chamber shell
	part.CanCollide = solid == true
	part.CanTouch = false
	part.CanQuery = false
	part:SetAttribute("Level1BayDecor", true)
	return part
end

local function addLevelOneChair(parent, name, seatCF, glitched)
	local model = Instance.new("Model")
	model.Name = name
	model:SetAttribute("Level1BayDecor", true)
	model:SetAttribute("GlitchedIntoWall", glitched == true)
	model.Parent = parent

	local solid = not glitched
	local upholstery = glitched and Color3.fromRGB(84, 70, 45) or Color3.fromRGB(104, 87, 48)
	local metal = Color3.fromRGB(54, 53, 46)
	makeLevelOneDecorPart(model, "Seat", seatCF, Vector3.new(3.5, 0.55, 3.4), upholstery, Enum.Material.Fabric, solid)
	makeLevelOneDecorPart(model, "Back", seatCF * CFrame.new(0, 2.1, 1.42), Vector3.new(3.5, 3.8, 0.48), upholstery, Enum.Material.Fabric, solid)
	for _, x in ipairs({-1.3, 1.3}) do
		for _, z in ipairs({-1.2, 1.2}) do
			makeLevelOneDecorPart(model, "Leg", seatCF * CFrame.new(x, -1.55, z), Vector3.new(0.28, 2.85, 0.28), metal, Enum.Material.Metal, solid)
		end
	end
	return model
end

local function styleLevelOneBay(roomModel, roomCenter, side, roomRadius, roomHeight)
	-- Keep the authored cylinder and vestibule geometry exactly as-is. Only the
	-- room-facing surface receives the Level 1 material, avoiding stacked or
	-- hidden textures on the shell backs.
	local surfaceByName = {
		ChamberFloor = {"floor", Enum.NormalId.Right},
		DoorThreshold = {"floor", Enum.NormalId.Top},
		DoorVestibuleFloor = {"floor", Enum.NormalId.Top},
		ChamberCeiling = {"ceiling", Enum.NormalId.Left},
		DoorVestibuleCeiling = {"ceiling", Enum.NormalId.Bottom},
		CurvedChamberWall = {"wall", Enum.NormalId.Front},
	}

	for _, object in ipairs(roomModel:GetChildren()) do
		if object:IsA("BasePart") then
			local spec = surfaceByName[object.Name]
			if object.Name == "DoorVestibuleWall" then
				spec = {
					"wall",
					object.Position.Z > roomCenter.Z and Enum.NormalId.Front or Enum.NormalId.Back,
				}
			end
			if spec then
				local role, face = spec[1], spec[2]
				object.Material = Enum.Material.SmoothPlastic
				if role == "wall" then
					object.Color = LEVEL_ONE_BAY_STYLE.wallColor
					object:SetAttribute("TunnelTextureRole", "Level1Wall")
					addLevelOneTexture(object, LEVEL_ONE_BAY_STYLE.wallTexture, {face}, LEVEL_ONE_BAY_STYLE.tile)
				elseif role == "floor" then
					object.Color = LEVEL_ONE_BAY_STYLE.floorColor
					object:SetAttribute("TunnelTextureRole", "Level1Floor")
					addLevelOneTexture(object, LEVEL_ONE_BAY_STYLE.floorTexture, {face}, LEVEL_ONE_BAY_STYLE.tile)
				else
					object.Color = LEVEL_ONE_BAY_STYLE.ceilingColor
					object:SetAttribute("TunnelTextureRole", "Level1Ceiling")
					addLevelOneTexture(object, LEVEL_ONE_BAY_STYLE.ceilingTexture, {face}, 8)
				end
			end
		end
	end

	-- Replace the generic transit bars with Level 1's broad fluorescent office
	-- panels and shadowless downward SurfaceLights.
	for _, child in ipairs(roomModel:GetChildren()) do
		if child.Name == "ChamberLight" then
			child:Destroy()
		end
	end
	local fixtureOffsets = {
		Vector2.new(-9, -8),
		Vector2.new(9, -8),
		Vector2.new(-9, 8),
		Vector2.new(9, 8),
	}
	for fixtureIndex, offset in ipairs(fixtureOffsets) do
		local panel = makePart(
			roomModel,
			string.format("Level1BayFluorescentFixture_%02d", fixtureIndex),
			CFrame.new(roomCenter + Vector3.new(offset.X, roomHeight - 0.5, offset.Y)),
			Vector3.new(7.5, 0.2, 3.8),
			LEVEL_ONE_BAY_STYLE.lightColor,
			Enum.Material.SmoothPlastic
		)
		panel.CanCollide = false
		panel.CanTouch = false
		panel.CanQuery = false
		panel.CastShadow = false
		panel:SetAttribute("Level1BayDecor", true)
		addLevelOneTexture(
			panel,
			LEVEL_ONE_BAY_STYLE.litFixtureTexture,
			{Enum.NormalId.Bottom},
			7.5,
			3.8
		)
		local light = Instance.new("SurfaceLight")
		light.Name = "Level1FluorescentLight"
		light.Face = Enum.NormalId.Bottom
		light.Brightness = 0.7
		light.Range = 28
		light.Angle = 140
		light.Color = LEVEL_ONE_BAY_STYLE.lightColor
		light.Shadows = false
		light.Parent = panel
	end

	local decor = Instance.new("Model")
	decor.Name = "Level1BackroomsDecor"
	decor:SetAttribute("Level1BayDecor", true)
	decor.Parent = roomModel
	local outward = Vector3.new(side, 0, 0)

	-- Two abandoned office chairs sit outside every queue pad's footprint.
	for index, z in ipairs({-4.5, 4.5}) do
		local seatPosition = roomCenter + outward * 20.5 + Vector3.new(0, 2.05, z)
		local seatCF = CFrame.lookAt(seatPosition, roomCenter + Vector3.new(0, 2.05, z))
			* CFrame.Angles(0, math.rad(index == 1 and -9 or 12), 0)
		addLevelOneChair(decor, "AbandonedOfficeChair" .. index, seatCF, false)
	end

	-- One chair and one filing cabinet deliberately intersect the curved shell:
	-- visual "Backrooms geometry error" props, but fully non-colliding/querying.
	local glitchZ = 10
	local wallX = math.sqrt(math.max(0, roomRadius * roomRadius - glitchZ * glitchZ))
	local glitchPosition = roomCenter + Vector3.new(side * (wallX + 0.55), 4.2, glitchZ)
	local glitchCF = CFrame.lookAt(glitchPosition, roomCenter + Vector3.new(0, 4.2, glitchZ))
		* CFrame.Angles(math.rad(18), 0, math.rad(68))
	addLevelOneChair(decor, "WallGlitchedOfficeChair", glitchCF, true)

	local cabinetPosition = roomCenter + Vector3.new(side * (wallX + 0.3), 4.8, -glitchZ)
	local cabinetCF = CFrame.lookAt(cabinetPosition, roomCenter + Vector3.new(0, 4.8, -glitchZ))
		* CFrame.Angles(math.rad(-8), math.rad(12), math.rad(-61))
	makeLevelOneDecorPart(
		decor,
		"WallGlitchedFileCabinet",
		cabinetCF,
		Vector3.new(4.6, 7.2, 2.9),
		Color3.fromRGB(78, 82, 73),
		Enum.Material.Metal
	)
	for drawer = -1, 1 do
		makeLevelOneDecorPart(
			decor,
			"GlitchedCabinetDrawer",
			cabinetCF * CFrame.new(0, drawer * 2.05, -1.48),
			Vector3.new(3.7, 1.55, 0.12),
			Color3.fromRGB(42, 45, 41),
			Enum.Material.Metal
		)
	end

	roomModel:SetAttribute("Level1InspiredBay", true)
	roomModel:SetAttribute("Level1BayStyleVersion", 1)
end

local function clearLobbyConcreteTextures(part)
	for _, child in ipairs(part:GetChildren()) do
		if child:IsA("Texture") and child.Name == "LobbyConcreteTexture" then
			child:Destroy()
		end
	end
end

local function addLobbyThemeTexture(part, name, textureId, faces, tileU, tileV, tint, transparency)
	clearLobbyConcreteTextures(part)
	if textureId == "" then return end
	for _, face in ipairs(faces) do
		local image = Instance.new("Texture")
		image.Name = name
		image.Texture = textureId
		image.Face = face
		image.StudsPerTileU = tileU
		image.StudsPerTileV = tileV or tileU
		image.Color3 = tint or Color3.new(1, 1, 1)
		image.Transparency = transparency or 0
		local circularOffsetU = part:GetAttribute("CircularTextureOffsetU")
		if type(circularOffsetU) == "number" then
			image.OffsetStudsU = circularOffsetU
		end
		image.Parent = part
	end
end

local function makeLobbyThemePart(parent, level, name, cframe, size, color, material, transparency, solid)
	local object = makePart(parent, name, cframe, size, color, material, transparency)
	-- floor-standing furniture is SOLID so players cannot walk through it;
	-- ceiling fittings, basins and wall-glitched props stay intangible
	object.CanCollide = solid == true
	object.CanTouch = false
	object.CanQuery = false
	object:SetAttribute("LobbyBayDecorLevel", level)
	return object
end

local function styleLevelTwoBay(roomModel, roomCenter, side, roomRadius, roomHeight)
	local surfaces = {
		ChamberFloor = {"floor", Enum.NormalId.Right},
		DoorThreshold = {"floor", Enum.NormalId.Top},
		DoorVestibuleFloor = {"floor", Enum.NormalId.Top},
		ChamberCeiling = {"ceiling", Enum.NormalId.Left},
		DoorVestibuleCeiling = {"ceiling", Enum.NormalId.Bottom},
		CurvedChamberWall = {"wall", Enum.NormalId.Front},
	}
	for _, object in ipairs(roomModel:GetChildren()) do
		if object:IsA("BasePart") then
			local spec = surfaces[object.Name]
			if object.Name == "DoorVestibuleWall" then
				spec = {"wall", object.Position.Z > roomCenter.Z and Enum.NormalId.Front or Enum.NormalId.Back}
			end
			if spec then
				local role, face = spec[1], spec[2]
				object.Material = Enum.Material.SmoothPlastic
				object.Color = role == "wall" and LEVEL_TWO_BAY_STYLE.wallColor
					or role == "floor" and LEVEL_TWO_BAY_STYLE.floorColor
					or LEVEL_TWO_BAY_STYLE.ceilingColor
				object:SetAttribute("TunnelTextureRole", "LobbyPoolrooms" .. role)
				addLobbyThemeTexture(object, "LobbyLevel2TileTexture",
					LEVEL_TWO_BAY_STYLE.tileTexture, {face}, LEVEL_TWO_BAY_STYLE.tile,
					LEVEL_TWO_BAY_STYLE.tile, LEVEL_TWO_BAY_STYLE.tileTint)
			end
		end
	end

	for _, child in ipairs(roomModel:GetChildren()) do
		if child.Name == "ChamberLight" then child:Destroy() end
	end
	for fixtureIndex, z in ipairs({-8, 8}) do
		local fixtureCF = CFrame.new(roomCenter + Vector3.new(0, roomHeight - 0.48, z))
		local frame = makeLobbyThemePart(roomModel, 2, "Lobby L2 Pool Ceiling Frame " .. fixtureIndex,
			fixtureCF, Vector3.new(20, .5, 6.5), LEVEL_TWO_BAY_STYLE.metalColor, Enum.Material.Metal)
		frame.CastShadow = false
		local diffuser = makeLobbyThemePart(roomModel, 2, "Lobby L2 Pool Ceiling Diffuser " .. fixtureIndex,
			fixtureCF * CFrame.new(0, -.34, 0), Vector3.new(17, .18, 4.8),
			LEVEL_TWO_BAY_STYLE.lightColor, Enum.Material.Neon, .08)
		diffuser.CastShadow = false
		local light = Instance.new("SurfaceLight")
		light.Name = "Lobby L2 Pool Light"
		light.Face = Enum.NormalId.Bottom
		light.Color = LEVEL_TWO_BAY_STYLE.lightColor
		light.Brightness = 1.085
		light.Range = 44
		light.Angle = 115
		light.Shadows = false
		light.Parent = diffuser
	end

	local decor = Instance.new("Model")
	decor.Name = "LobbyLevel2PoolroomsDecor"
	decor:SetAttribute("LobbyBayDecorLevel", 2)
	decor.Parent = roomModel
	local outward = Vector3.new(side, 0, 0)

	-- Dry tile now dominates the bay. A very shallow, non-physical basin at
	-- the far wall keeps a small Poolrooms reflection without changing movement.
	local basinCenter = roomCenter + outward * 19.2
	local basinApron = makeLobbyThemePart(decor, 2, "Lobby L2 Basin Tile Apron",
		CFrame.new(basinCenter + Vector3.new(0, .305, 0)) * CFrame.Angles(0, 0, math.rad(90)),
		Vector3.new(.05, 12.8, 12.8), LEVEL_TWO_BAY_STYLE.floorColor, Enum.Material.SmoothPlastic)
	basinApron.Shape = Enum.PartType.Cylinder
	basinApron.CastShadow = false
	basinApron:SetAttribute("AestheticWaterBasin", true)
	addLobbyThemeTexture(basinApron, "LobbyLevel2TileTexture", LEVEL_TWO_BAY_STYLE.tileTexture,
		{Enum.NormalId.Right}, LEVEL_TWO_BAY_STYLE.tile, LEVEL_TWO_BAY_STYLE.tile,
		LEVEL_TWO_BAY_STYLE.tileTint)

	local basinBed = makeLobbyThemePart(decor, 2, "Lobby L2 Basin Bed",
		CFrame.new(basinCenter + Vector3.new(0, .325, 0)) * CFrame.Angles(0, 0, math.rad(90)),
		Vector3.new(.035, 10.8, 10.8), Color3.fromRGB(145, 194, 184), Enum.Material.SmoothPlastic)
	basinBed.Shape = Enum.PartType.Cylinder
	basinBed.CastShadow = false
	basinBed:SetAttribute("AestheticWaterBasin", true)
	addLobbyThemeTexture(basinBed, "LobbyLevel2BasinTileTexture", LEVEL_TWO_BAY_STYLE.tileTexture,
		{Enum.NormalId.Right}, LEVEL_TWO_BAY_STYLE.tile, LEVEL_TWO_BAY_STYLE.tile,
		Color3.fromRGB(205, 235, 226), .12)

	local basinWater = makeLobbyThemePart(decor, 2, "Lobby L2 Basin Water",
		CFrame.new(basinCenter + Vector3.new(0, .355, 0)) * CFrame.Angles(0, 0, math.rad(90)),
		Vector3.new(.02, 10.2, 10.2), LEVEL_TWO_BAY_STYLE.waterColor, Enum.Material.Glass, .42)
	basinWater.Shape = Enum.PartType.Cylinder
	basinWater.Reflectance = .10
	basinWater.CastShadow = false
	basinWater:SetAttribute("AestheticWaterBasin", true)

	-- One tiled pool column at the far wall, solid like real architecture (it
	-- sits well clear of every queue pad).
	local columnBase = roomCenter + outward * 20.5
	local shaft = makeLobbyThemePart(decor, 2, "Lobby L2 Tiled Column",
		CFrame.new(columnBase + Vector3.new(0, 4.6, 0)), Vector3.new(3.6, 9.2, 3.6),
		LEVEL_TWO_BAY_STYLE.floorColor, Enum.Material.SmoothPlastic, nil, true)
	addLobbyThemeTexture(shaft, "LobbyLevel2TileTexture", LEVEL_TWO_BAY_STYLE.tileTexture,
		Enum.NormalId:GetEnumItems(), LEVEL_TWO_BAY_STYLE.tile, LEVEL_TWO_BAY_STYLE.tile,
		LEVEL_TWO_BAY_STYLE.tileTint)
	for _, y in ipairs({.25, 8.95}) do
		local flare = makeLobbyThemePart(decor, 2, "Lobby L2 Column Flare",
			CFrame.new(columnBase + Vector3.new(0, y, 0)), Vector3.new(5.2, .5, 5.2),
			LEVEL_TWO_BAY_STYLE.floorColor, Enum.Material.SmoothPlastic, nil, true)
		addLobbyThemeTexture(flare, "LobbyLevel2TileTexture", LEVEL_TWO_BAY_STYLE.tileTexture,
			{Enum.NormalId.Top, Enum.NormalId.Front, Enum.NormalId.Back, Enum.NormalId.Left, Enum.NormalId.Right},
			LEVEL_TWO_BAY_STYLE.tile, LEVEL_TWO_BAY_STYLE.tile, LEVEL_TWO_BAY_STYLE.tileTint)
	end

	-- Stainless pool ladder motif at the rear edge.
	local ladderBase = basinCenter - outward * 4.45
	for _, z in ipairs({-1.35, 1.35}) do
		makeLobbyThemePart(decor, 2, "Lobby L2 Pool Ladder Rail",
			CFrame.new(ladderBase + Vector3.new(0, 2.6, z)), Vector3.new(.38, 5.2, .38),
			LEVEL_TWO_BAY_STYLE.railColor, Enum.Material.Metal, nil, true)
	end
	for rung = 0, 3 do
		makeLobbyThemePart(decor, 2, "Lobby L2 Pool Ladder Rung",
			CFrame.new(ladderBase + Vector3.new(0, .9 + rung * 1.05, 0)), Vector3.new(.4, .32, 2.7),
			LEVEL_TWO_BAY_STYLE.railColor, Enum.Material.Metal, nil, true)
	end

	-- A dry faded lounger sits beyond the basin; the ball floats over its water.
	local loungerPosition = roomCenter + outward * 19 + Vector3.new(0, .55, 9)
	local loungerCF = CFrame.lookAt(loungerPosition, roomCenter + Vector3.new(0, .55, 9))
	makeLobbyThemePart(decor, 2, "Lobby L2 Sunken Lounger Seat", loungerCF,
		Vector3.new(2.6, .5, 6.4), Color3.fromRGB(108, 164, 181), Enum.Material.SmoothPlastic, nil, true)
	makeLobbyThemePart(decor, 2, "Lobby L2 Sunken Lounger Back",
		loungerCF * CFrame.new(0, 1.4, -2.9) * CFrame.Angles(math.rad(-35), 0, 0),
		Vector3.new(2.6, .4, 3.4), Color3.fromRGB(108, 164, 181), Enum.Material.SmoothPlastic, nil, true)
	local ball = makeLobbyThemePart(decor, 2, "Lobby L2 Pool Ball",
		CFrame.new(basinCenter + Vector3.new(0, 1.25, 3.05)),
		Vector3.new(2.3, 2.3, 2.3), Color3.fromRGB(238, 202, 84), Enum.Material.SmoothPlastic, nil, true)
	ball.Shape = Enum.PartType.Ball
	local noodle = makeLobbyThemePart(decor, 2, "Lobby L2 Wall Glitched Pool Noodle",
		CFrame.new(roomCenter + outward * (roomRadius + .2) + Vector3.new(0, 4.1, 12))
			* CFrame.Angles(0, math.rad(18), math.rad(37)),
		Vector3.new(6.2, .62, .62), Color3.fromRGB(96, 196, 132), Enum.Material.SmoothPlastic)
	noodle.Shape = Enum.PartType.Cylinder

	roomModel:SetAttribute("LobbyBayTheme", "Poolrooms")
	roomModel:SetAttribute("LobbyBayStyleVersion", 2)
end

local function cloneLobbyLevelThreeFurniture(templateName, parent, name, cframe, size, color, solid)
	local assets = game:GetService("ServerStorage"):FindFirstChild("Level3Assets")
	local templates = assets and assets:FindFirstChild("FurnitureTemplates")
	local template = templates and templates:FindFirstChild(templateName)
	if not template or not template:IsA("BasePart") then return nil end
	local object = template:Clone()
	object.Name = name
	object.Anchored = true
	-- floor furniture is SOLID; the wall-glitched chair stays intangible
	object.CanCollide = solid == true
	object.CanTouch = false
	object.CanQuery = false
	object.CFrame = cframe
	object.Size = size
	if color then object.Color = color end
	object:SetAttribute("LobbyBayDecorLevel", 3)
	object.Parent = parent
	return object
end

local function styleLevelThreeBay(roomModel, roomCenter, side, roomRadius, roomHeight)
	local surfaces = {
		ChamberFloor = {"floor", Enum.NormalId.Right},
		DoorThreshold = {"floor", Enum.NormalId.Top},
		DoorVestibuleFloor = {"floor", Enum.NormalId.Top},
		ChamberCeiling = {"ceiling", Enum.NormalId.Left},
		DoorVestibuleCeiling = {"ceiling", Enum.NormalId.Bottom},
		CurvedChamberWall = {"wall", Enum.NormalId.Front},
	}
	local outward = Vector3.new(side, 0, 0)
	for _, object in ipairs(roomModel:GetChildren()) do
		if object:IsA("BasePart") then
			local spec = surfaces[object.Name]
			if object.Name == "DoorVestibuleWall" then
				spec = {"wall", object.Position.Z > roomCenter.Z and Enum.NormalId.Front or Enum.NormalId.Back}
			end
			if spec then
				local role, face = spec[1], spec[2]
				clearLobbyConcreteTextures(object)
				if role == "floor" then
					object.Color = LEVEL_THREE_BAY_STYLE.partyCarpetColor
					object.Material = Enum.Material.Carpet
					object:SetAttribute("TunnelTextureRole", "LobbyMallPartyFloor")
					addLobbyThemeTexture(object, "LobbyLevel3PartyCarpet",
						LEVEL_THREE_BAY_STYLE.partyCarpetTexture, {face},
						LEVEL_THREE_BAY_STYLE.carpetTile, LEVEL_THREE_BAY_STYLE.carpetTile)
				elseif role == "ceiling" then
					object.Color = LEVEL_THREE_BAY_STYLE.ceilingColor
					object.Material = Enum.Material.Plaster
					object:SetAttribute("TunnelTextureRole", "LobbyMallDropCeiling")
				else
					local rearAccent = object.Name == "CurvedChamberWall"
						and (object.Position - roomCenter):Dot(outward) > roomRadius * .55
					if rearAccent then
						object.Color = LEVEL_THREE_BAY_STYLE.wallpaperColor
						object.Material = Enum.Material.SmoothPlastic
						object.Reflectance = .08
						object:SetAttribute("TunnelTextureRole", "LobbyMallWallpaper")
						addLobbyThemeTexture(object, "LobbyLevel3Wallpaper",
							LEVEL_THREE_BAY_STYLE.wallpaperTexture, {face},
							LEVEL_THREE_BAY_STYLE.wallpaperTile, LEVEL_THREE_BAY_STYLE.wallpaperTile,
							Color3.new(1, 1, 1), .08)
					else
						object.Color = LEVEL_THREE_BAY_STYLE.orangeWallColor
						object.Material = Enum.Material.Plaster
						object:SetAttribute("TunnelTextureRole", "LobbyMallOrangeWall")
						addLobbyThemeTexture(object, "LobbyLevel3OrangeWall",
							LEVEL_THREE_BAY_STYLE.orangeWallTexture, {face},
							LEVEL_THREE_BAY_STYLE.orangeWallTile, LEVEL_THREE_BAY_STYLE.orangeWallTile,
							Color3.new(1, 1, 1), .28)
					end
				end
			end
		end
	end

	for _, child in ipairs(roomModel:GetChildren()) do
		if child.Name == "ChamberLight" then child:Destroy() end
	end

	-- A real drop-ceiling read: restrained eight-stud metal seams on the authored
	-- ceiling, followed by mismatched old fluorescent fittings.
	for _, offset in ipairs({-16, -8, 0, 8, 16}) do
		makeLobbyThemePart(roomModel, 3, "Lobby L3 Ceiling Grid",
			CFrame.new(roomCenter + Vector3.new(offset, roomHeight - .75, 0)),
			Vector3.new(.08, .04, 44), Color3.fromRGB(83, 79, 67), Enum.Material.Metal, .38)
		makeLobbyThemePart(roomModel, 3, "Lobby L3 Ceiling Grid",
			CFrame.new(roomCenter + Vector3.new(0, roomHeight - .75, offset)),
			Vector3.new(44, .04, .08), Color3.fromRGB(83, 79, 67), Enum.Material.Metal, .38)
	end
	local fixtureOffsets = {
		Vector2.new(-9, -8), Vector2.new(9, -8),
		Vector2.new(-9, 8), Vector2.new(9, 8),
	}
	for index, offset in ipairs(fixtureOffsets) do
		local dead = index == 4
		local fixtureCF = CFrame.new(roomCenter + Vector3.new(offset.X, roomHeight - .92, offset.Y))
		makeLobbyThemePart(roomModel, 3, "Lobby L3 Fluorescent Frame " .. index,
			fixtureCF, Vector3.new(7.5, .32, 2.4), Color3.fromRGB(85, 84, 75), Enum.Material.Metal)
		local diffuser = makeLobbyThemePart(roomModel, 3, "Lobby L3 Fluorescent Diffuser " .. index,
			fixtureCF * CFrame.new(0, -.20, 0), Vector3.new(7.05, .14, 2.05),
			dead and Color3.fromRGB(92, 88, 72) or LEVEL_THREE_BAY_STYLE.lightColor,
			dead and Enum.Material.SmoothPlastic or Enum.Material.Neon, dead and .18 or .03)
		if not dead then
			local light = Instance.new("SurfaceLight")
			light.Name = "Lobby L3 Party Fluorescent"
			light.Face = Enum.NormalId.Bottom
			light.Color = LEVEL_THREE_BAY_STYLE.lightColor
			light.Brightness = 1.62
			light.Range = 34
			light.Angle = 128
			light.Shadows = false
			light.Parent = diffuser
		end
	end

	local decor = Instance.new("Model")
	decor.Name = "LobbyLevel3MallPartyDecor"
	decor:SetAttribute("LobbyBayDecorLevel", 3)
	decor.Parent = roomModel
	local tablePosition = roomCenter + outward * 19
	local tableCF = CFrame.lookAt(tablePosition, roomCenter)
	local tableMesh = cloneLobbyLevelThreeFurniture("FoldingTableTemplate", decor,
		"Lobby L3 Vetted Folding Table", tableCF * CFrame.new(0, 1.72, 0),
		Vector3.new(11.2, 3.44, 4.35), nil, true)
	if not tableMesh then
		tableMesh = makeLobbyThemePart(decor, 3, "Lobby L3 Folding Table",
			tableCF * CFrame.new(0, 3, 0), Vector3.new(11.2, .5, 4.35),
			Color3.fromRGB(201, 198, 185), Enum.Material.SmoothPlastic, nil, true)
	end
	local tablecloth = makeLobbyThemePart(decor, 3, "Lobby L3 Confetti Tablecloth",
		tableCF * CFrame.new(0, 3.48, 0), Vector3.new(11.45, .12, 4.62),
		Color3.fromRGB(38, 153, 165), Enum.Material.Fabric, nil, true)
	addLobbyThemeTexture(tablecloth, "LobbyLevel3ConfettiTablecloth",
		LEVEL_THREE_BAY_STYLE.confettiTexture, {Enum.NormalId.Top},
		LEVEL_THREE_BAY_STYLE.tableclothTile, LEVEL_THREE_BAY_STYLE.tableclothTile,
		Color3.new(1, 1, 1), .34)

	local chairColors = {Color3.fromRGB(194, 157, 49), Color3.fromRGB(137, 45, 52)}
	for index, localPosition in ipairs({Vector3.new(-2.7, 2.28, -4.1), Vector3.new(2.7, 2.28, 4.1)}) do
		local chairPosition = (tableCF * CFrame.new(localPosition)).Position
		local tableTarget = (tableCF * CFrame.new(localPosition.X, 2.28, 0)).Position
		local chairCF = CFrame.lookAt(chairPosition, tableTarget)
		local chair = cloneLobbyLevelThreeFurniture("PlasticPartyChairTemplate", decor,
			"Lobby L3 Mismatched Party Chair " .. index, chairCF,
			Vector3.new(2.55, 4.3, 2.58), chairColors[index], true)
		if not chair then
			makeLobbyThemePart(decor, 3, "Lobby L3 Mismatched Party Chair " .. index,
				chairCF, Vector3.new(2.55, 4.3, 2.58), chairColors[index], Enum.Material.SmoothPlastic, nil, true)
		end
	end

	-- A crooked chair is deliberately swallowed by the shell: harmless visual
	-- geometry corruption matching the party level's shifted furniture.
	local glitchZ = 11
	local wallX = math.sqrt(math.max(0, roomRadius * roomRadius - glitchZ * glitchZ))
	local glitchPosition = roomCenter + Vector3.new(side * (wallX + .55), 4.2, glitchZ)
	local glitchCF = CFrame.lookAt(glitchPosition, roomCenter + Vector3.new(0, 4.2, glitchZ))
		* CFrame.Angles(math.rad(16), math.rad(-12), math.rad(68))
	local glitchChair = cloneLobbyLevelThreeFurniture("PlasticPartyChairTemplate", decor,
		"Lobby L3 Wall Glitched Party Chair", glitchCF,
		Vector3.new(2.55, 4.3, 2.58), Color3.fromRGB(73, 129, 86))
	if not glitchChair then
		makeLobbyThemePart(decor, 3, "Lobby L3 Wall Glitched Party Chair",
			glitchCF, Vector3.new(2.55, 4.3, 2.58), Color3.fromRGB(73, 129, 86), Enum.Material.SmoothPlastic)
	end

	local bouquetBase = roomCenter + outward * 18 + Vector3.new(0, 0, -10)
	local balloonColors = {
		Color3.fromRGB(187, 42, 52),
		Color3.fromRGB(40, 104, 169),
		Color3.fromRGB(210, 159, 37),
	}
	for index, offset in ipairs({
		Vector3.new(-1.2, 7.1, 0), Vector3.new(.2, 8.2, .5), Vector3.new(1.35, 7.35, -.25),
	}) do
		local balloonPosition = bouquetBase + offset
		local balloon = makeLobbyThemePart(decor, 3, "Lobby L3 Party Balloon " .. index,
			CFrame.new(balloonPosition), Vector3.new(1.72, 2.36, 1.72),
			balloonColors[index], Enum.Material.SmoothPlastic, .025)
		balloon.Shape = Enum.PartType.Ball
		balloon.Reflectance = .06
		local stringLength = balloonPosition.Y - (roomCenter.Y + .3)
		makeLobbyThemePart(decor, 3, "Lobby L3 Balloon String " .. index,
			CFrame.new(balloonPosition.X, roomCenter.Y + .3 + stringLength * .5, balloonPosition.Z),
			Vector3.new(.05, stringLength, .05), Color3.fromRGB(90, 87, 79), Enum.Material.Metal)
	end

	roomModel:SetAttribute("LobbyBayTheme", "MallBackroomsParty")
	roomModel:SetAttribute("LobbyBayStyleVersion", 1)
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

	-- A 64-leaf tangent ring reads as a circle at player distance while keeping
	-- the exact 56-stud wall-center diameter. The old 28-leaf ring made long,
	-- visibly flat wall bands. The .955 portal cut omits seven leaves and still
	-- aligns with the existing 18.8-stud vestibule opening on either side.
	local wallSegments = 64
	local wallArcStep = (math.pi * 2 * roomRadius) / wallSegments
	local chord = 2 * roomRadius * math.tan(math.pi / wallSegments) + 0.08
	local doorwayDotCutoff = 0.955
	local towardTunnel = Vector3.new(-side, 0, 0)
	local visibleWallCount = 0
	for i = 0, wallSegments - 1 do
		local theta = (i / wallSegments) * math.pi * 2
		local radial = Vector3.new(math.cos(theta), 0, math.sin(theta))
		-- Preserve one engineered doorway bite; every other leaf follows the same
		-- radius, so all six bays share one circular footprint.
		if radial:Dot(towardTunnel) < doorwayDotCutoff then
			local position = roomCenter + radial * roomRadius + Vector3.new(0, roomHeight * 0.5, 0)
			local wall = makePart(
				roomModel,
				"CurvedChamberWall",
				CFrame.lookAt(position, Vector3.new(roomCenter.X, wallY, roomCenter.Z)),
				Vector3.new(chord, roomHeight, 1.25),
				COLORS.concrete,
				Enum.Material.Concrete
			)
			visibleWallCount += 1
			wall:SetAttribute("CircularWallSegmentIndex", i + 1)
			wall:SetAttribute("CircularWallSegmentCount", wallSegments)
			wall:SetAttribute("CircularWallCenterRadius", roomRadius)
			-- CFrame.lookAt makes local +X run opposite increasing polar angle.
			-- Carry the artwork around the arc instead of restarting it per leaf.
			wall:SetAttribute("CircularTextureOffsetU", -i * wallArcStep)
			tagSurface(wall, "Concrete")
		end
	end
	roomModel:SetAttribute("BayPlanShape", "Circle")
	roomModel:SetAttribute("CircularBayDiameter", roomRadius * 2)
	roomModel:SetAttribute("CircularWallSegments", wallSegments)
	roomModel:SetAttribute("CircularVisibleWallCount", visibleWallCount)
	roomModel:SetAttribute("CircularDoorwayDotCutoff", doorwayDotCutoff)

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

	if level == 1 then
		styleLevelOneBay(roomModel, roomCenter, side, roomRadius, roomHeight)
	elseif level == 2 then
		styleLevelTwoBay(roomModel, roomCenter, side, roomRadius, roomHeight)
	elseif level == 3 then
		styleLevelThreeBay(roomModel, roomCenter, side, roomRadius, roomHeight)
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
	local accentColor = active and COLORS.green or COLORS.amber
	addMountedLevelSign(parent, center, header, level, side, accentColor)
	addBoard(
		header,
		face,
		"LEVEL " .. level,
		active and "ACCESS READY  •  4 QUEUES  •  MAX 6 EACH" or "ANOMALOUS ACCESS POINT  •  NOT YET STABLE",
		accentColor
	)

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

local function addConcourseBench(parent, center, side, zOffset)
	local benchCenter = center + Vector3.new(side * 27.2, 0, zOffset)
	local benchCF = CFrame.lookAt(benchCenter + Vector3.new(0, 2.25, 0), center + Vector3.new(0, 2.25, zOffset))
	local wood = Color3.fromRGB(118, 88, 55)
	local frame = Color3.fromRGB(42, 48, 47)

	local seat = makePart(parent, "ConcourseBenchSeat", benchCF, Vector3.new(7.2, 0.55, 2.15), wood, Enum.Material.WoodPlanks)
	seat:SetAttribute("LobbySocialProp", true)
	local back = makePart(parent, "ConcourseBenchBack", benchCF * CFrame.new(0, 1.7, 0.82), Vector3.new(7.2, 3.15, 0.42), wood, Enum.Material.WoodPlanks)
	back:SetAttribute("LobbySocialProp", true)
	for _, x in ipairs({-2.65, 2.65}) do
		for _, z in ipairs({-0.68, 0.68}) do
			local leg = makePart(parent, "ConcourseBenchLeg", benchCF * CFrame.new(x, -1.22, z), Vector3.new(0.38, 2.2, 0.38), frame, Enum.Material.Metal)
			leg:SetAttribute("LobbySocialProp", true)
		end
	end
end


local function addGameplayShopkeeper(parent, center, zOffset)
	-- The same authored yellow hazmat rig players use in every level. It is
	-- cloned as a deliberately inert display character so no gameplay scripts,
	-- collisions, prompts, or movement controllers leak into the lobby.
	local source = game:GetService("StarterPlayer"):FindFirstChild("StarterCharacter")
		or game:GetService("ServerStorage"):FindFirstChild("StarterCharacter")
	if not source or not source:IsA("Model") then
		warn("[TunnelLobbyBuilder] Shared gameplay StarterCharacter was unavailable for the shopkeeper")
		return nil
	end

	local character = source:Clone()
	character.Name = "ZyntraShopkeeper"
	character:SetAttribute("GameplayRigClone", true)
	character:SetAttribute("StandardYellowAppearance", true)
	character:SetAttribute("VisualOnly", true)

	for _, descendant in ipairs(character:GetDescendants()) do
		if descendant:IsA("BaseScript") or descendant:IsA("ModuleScript") or descendant:IsA("Tool") or descendant:IsA("ProximityPrompt") then
			descendant:Destroy()
		elseif descendant:IsA("BasePart") then
			descendant.Anchored = true
			descendant.CanCollide = false
			descendant.CanTouch = false
			descendant.CanQuery = false
			descendant.Massless = true
			descendant.CastShadow = true
		end
	end

	local humanoid = character:FindFirstChildOfClass("Humanoid")
	if humanoid then
		humanoid.DisplayDistanceType = Enum.HumanoidDisplayDistanceType.None
		humanoid.BreakJointsOnDeath = false
		humanoid.AutoRotate = false
	end

	character.Parent = parent
	-- A low staff platform and forward placement keep the authentic rig visible
	-- above the counter without scaling or recoloring it.
	local feetY = center.Y + 1.16
	character:PivotTo(CFrame.lookAt(
		Vector3.new(center.X + 29.15, feetY, center.Z + zOffset),
		Vector3.new(center.X, feetY, center.Z + zOffset)
	))
	return character
end

local function addSupplyKiosk(parent, center)
	local kiosk = Instance.new("Model")
	kiosk.Name = "ZyntraSupplyKiosk"
	kiosk:SetAttribute("VisualOnly", false)
	kiosk:SetAttribute("ShopFunctional", true)
	kiosk:SetAttribute("SupplyKioskVersion", 4)
	kiosk:SetAttribute("Placement", "Right service ledge between Level 2 and Level 4")
	kiosk.Parent = parent

	local zOffset = -35
	local metal = Color3.fromRGB(28, 34, 33)
	local metalLight = Color3.fromRGB(50, 59, 57)
	local cyan = Color3.fromRGB(73, 245, 204)
	local warm = Color3.fromRGB(228, 214, 167)

	local floorPad = makePart(
		kiosk,
		"ShopFloorPad",
		CFrame.new(center + Vector3.new(29.6, 0.72, zOffset)),
		Vector3.new(7.2, 0.16, 18),
		Color3.fromRGB(45, 51, 48),
		Enum.Material.DiamondPlate
	)
	floorPad:SetAttribute("ShopDecor", true)

	local backWall = makePart(
		kiosk,
		"ShopBackWall",
		CFrame.new(center + Vector3.new(32.55, 5.95, zOffset)),
		Vector3.new(0.8, 10.6, 18),
		metal,
		Enum.Material.Metal
	)
	backWall:SetAttribute("ShopDecor", true)

	for _, zSide in ipairs({-1, 1}) do
		local sidePost = makePart(
			kiosk,
			"ShopSidePost",
			CFrame.new(center + Vector3.new(29.75, 5.95, zOffset + zSide * 8.7)),
			Vector3.new(6.4, 10.6, 0.65),
			metalLight,
			Enum.Material.Metal
		)
		sidePost:SetAttribute("ShopDecor", true)

		local edgeGlow = makePart(
			kiosk,
			"ShopEdgeGlow",
			CFrame.new(center + Vector3.new(26.5, 6.1, zOffset + zSide * 8.72)),
			Vector3.new(0.18, 10.2, 0.18),
			cyan,
			Enum.Material.Neon,
			0.08
		)
		edgeGlow.CanCollide = false
		edgeGlow.CanTouch = false
		edgeGlow.CanQuery = false
		edgeGlow:SetAttribute("ShopDecor", true)
	end

	local canopy = makePart(
		kiosk,
		"ShopCanopy",
		CFrame.new(center + Vector3.new(29.65, 11.35, zOffset)),
		Vector3.new(7.2, 0.72, 18),
		metal,
		Enum.Material.Metal
	)
	canopy:SetAttribute("ShopDecor", true)

	local counterFront = makePart(
		kiosk,
		"ShopCounterFront",
		CFrame.new(center + Vector3.new(27.45, 2.15, zOffset)),
		Vector3.new(1.05, 3.05, 15.3),
		metal,
		Enum.Material.Metal
	)
	counterFront:SetAttribute("ShopDecor", true)
	local counterTop = makePart(
		kiosk,
		"ShopCounterTop",
		CFrame.new(center + Vector3.new(27.7, 3.82, zOffset)),
		Vector3.new(2.35, 0.42, 16.1),
		metalLight,
		Enum.Material.Metal
	)
	counterTop:SetAttribute("ShopDecor", true)

	local counterGlow = makePart(
		kiosk,
		"ShopCounterGlow",
		CFrame.new(center + Vector3.new(26.91, 2.9, zOffset)),
		Vector3.new(0.12, 0.22, 14.2),
		cyan,
		Enum.Material.Neon
	)
	counterGlow.CanCollide = false
	counterGlow.CanTouch = false
	counterGlow.CanQuery = false
	counterGlow:SetAttribute("ShopDecor", true)

	local sign = makePart(
		kiosk,
		"ShopOverheadSign",
		CFrame.new(center + Vector3.new(26.95, 9.3, zOffset)),
		Vector3.new(0.36, 2.45, 12.2),
		metal,
		Enum.Material.Metal
	)
	sign.CanCollide = false
	sign.CanTouch = false
	sign.CanQuery = false
	sign:SetAttribute("ShopDecor", true)
	addBoard(
		sign,
		Enum.NormalId.Left,
		"ZYNTRA SUPPLY",
		"EQUIPMENT  •  UPGRADES  •  SUPPLIES",
		cyan
	)

	local shelf = makePart(
		kiosk,
		"ShopDisplayShelf",
		CFrame.new(center + Vector3.new(31.75, 5.9, zOffset)),
		Vector3.new(1.15, 0.3, 14.5),
		metalLight,
		Enum.Material.Metal
	)
	shelf.CanCollide = false
	shelf.CanTouch = false
	shelf.CanQuery = false
	shelf:SetAttribute("ShopDecor", true)

	local productColors = {
		Color3.fromRGB(255, 106, 86),
		Color3.fromRGB(255, 213, 79),
		Color3.fromRGB(75, 229, 141),
		Color3.fromRGB(77, 190, 255),
		Color3.fromRGB(182, 92, 255),
	}
	for index, productColor in ipairs(productColors) do
		local product = makePart(
			kiosk,
			"DisplayProduct" .. index,
			CFrame.new(center + Vector3.new(31.05, 6.65, zOffset - 6 + (index - 1) * 3)),
			Vector3.new(1.15, 1.35 + (index % 2) * 0.35, 1.75),
			productColor,
			Enum.Material.SmoothPlastic
		)
		product.CanCollide = false
		product.CanTouch = false
		product.CanQuery = false
		product:SetAttribute("ShopDecor", true)
	end

	local downlight = makePart(
		kiosk,
		"ShopDownlight",
		CFrame.new(center + Vector3.new(29.2, 10.92, zOffset)),
		Vector3.new(2.8, 0.12, 8.2),
		warm,
		Enum.Material.Neon
	)
	downlight.CanCollide = false
	downlight.CanTouch = false
	downlight.CanQuery = false
	downlight:SetAttribute("ShopDecor", true)
	local light = Instance.new("SurfaceLight")
	light.Name = "ShopWarmLight"
	light.Face = Enum.NormalId.Bottom
	light.Color = warm
	light.Brightness = 0.7
	light.Range = 12
	light.Angle = 100
	light.Shadows = true
	light.Parent = downlight

	local accessTerminal = makePart(
		kiosk,
		"ShopAccessTerminal",
		CFrame.new(center + Vector3.new(26.84, 4.65, zOffset + 5.45)),
		Vector3.new(0.22, 1.45, 3.2),
		metal,
		Enum.Material.Metal
	)
	accessTerminal.CanCollide = false
	accessTerminal.CanTouch = false
	accessTerminal.CanQuery = false
	accessTerminal:SetAttribute("ShopInteraction", true)
	addBoard(accessTerminal, Enum.NormalId.Left, "SHOP", "PRESS  E", cyan)


	local prompt = Instance.new("ProximityPrompt")
	prompt.Name = "ZyntraShopPrompt"
	prompt.ActionText = "OPEN SHOP"
	prompt.ObjectText = "ZYNTRA SUPPLY"
	prompt.KeyboardKeyCode = Enum.KeyCode.E
	prompt.GamepadKeyCode = Enum.KeyCode.ButtonX
	prompt.HoldDuration = 0
	prompt.MaxActivationDistance = 10
	prompt.RequiresLineOfSight = false
	prompt.Style = Enum.ProximityPromptStyle.Default
	prompt.Parent = accessTerminal

	local staffPlatform = makePart(
		kiosk,
		"ShopkeeperPlatform",
		CFrame.new(center + Vector3.new(29.15, 0.91, zOffset)),
		Vector3.new(3.2, 0.5, 3.4),
		metalLight,
		Enum.Material.DiamondPlate
	)
	staffPlatform.CanCollide = false
	staffPlatform.CanTouch = false
	staffPlatform.CanQuery = false
	staffPlatform:SetAttribute("ShopDecor", true)

	-- The tunnel is intentionally dim, so a narrow warm key light illuminates
	-- the suit and visor without bleaching the rest of the kiosk.
	local keyLightMount = makePart(
		kiosk,
		"ShopkeeperKeyLightMount",
		CFrame.new(center + Vector3.new(27.05, 6.1, zOffset)),
		Vector3.new(0.1, 0.1, 0.1),
		warm,
		Enum.Material.SmoothPlastic,
		1
	)
	keyLightMount.CanCollide = false
	keyLightMount.CanTouch = false
	keyLightMount.CanQuery = false
	local keyLight = Instance.new("SpotLight")
	keyLight.Name = "ShopkeeperKeyLight"
	keyLight.Face = Enum.NormalId.Right
	keyLight.Color = warm
	keyLight.Brightness = 2.1
	keyLight.Range = 9
	keyLight.Angle = 82
	keyLight.Shadows = false
	keyLight.Parent = keyLightMount

	addGameplayShopkeeper(kiosk, center, zOffset)
	return kiosk
end

local function addPartyButton(parent, center)
	local model = Instance.new("Model")
	model.Name = "ZyntraPartyButton"
	model:SetAttribute("PartyButtonVersion", 1)
	model:SetAttribute("Placement", "Right wall between Level 2 and the supply kiosk")
	model:SetAttribute("PartyModeDuration", 10)
	model.Parent = parent

	local zOffset = -51.5
	local plate = makePart(
		model,
		"PartyButtonWallPlate",
		CFrame.new(center + Vector3.new(33.35, 4.45, zOffset)),
		Vector3.new(0.58, 4.5, 4.2),
		Color3.fromRGB(27, 33, 32),
		Enum.Material.Metal
	)
	plate.CanCollide = false
	plate.CanTouch = false
	plate.CanQuery = false
	plate:SetAttribute("LobbyPartyControl", true)

	local label = makePart(
		model,
		"PartyButtonLabel",
		CFrame.new(center + Vector3.new(33.02, 6.35, zOffset)),
		Vector3.new(0.16, 1.15, 3.55),
		Color3.fromRGB(18, 24, 23),
		Enum.Material.Metal
	)
	label.CanCollide = false
	label.CanTouch = false
	label.CanQuery = false
	addBoard(
		label,
		Enum.NormalId.Left,
		"???",
		"UNMARKED CONTROL",
		Color3.fromRGB(177, 89, 255)
	)

	local button = makePart(
		model,
		"PartyButton",
		CFrame.new(center + Vector3.new(32.93, 4.05, zOffset)),
		Vector3.new(0.72, 1.62, 1.62),
		Color3.fromRGB(255, 125, 36),
		Enum.Material.Neon
	)
	button.Shape = Enum.PartType.Cylinder
	button.CanCollide = false
	button.CanTouch = false
	button.CanQuery = false
	button:SetAttribute("LobbyPartyControl", true)
	button:SetAttribute("PartyModeDuration", 10)

	local glow = Instance.new("SurfaceLight")
	glow.Name = "ButtonGlow"
	glow.Face = Enum.NormalId.Left
	glow.Color = button.Color
	glow.Brightness = 1.25
	glow.Range = 7
	glow.Angle = 95
	glow.Shadows = false
	glow.Parent = button

	local prompt = Instance.new("ProximityPrompt")
	prompt.Name = "ZyntraPartyPrompt"
	prompt.ActionText = "PRESS"
	prompt.ObjectText = "UNMARKED WALL BUTTON"
	prompt.KeyboardKeyCode = Enum.KeyCode.E
	prompt.GamepadKeyCode = Enum.KeyCode.ButtonX
	prompt.HoldDuration = 0
	prompt.MaxActivationDistance = 9
	prompt.RequiresLineOfSight = false
	prompt.Style = Enum.ProximityPromptStyle.Default
	prompt.Parent = button

	return model
end

local function addLobbyConcourse(parent, center, lobbyModel)
	local concourse = Instance.new("Model")
	concourse.Name = "ZyntraDispatchConcourse"
	concourse:SetAttribute("LobbyConcourseVersion", 6)
	concourse.Parent = parent

	-- A real arrival threshold makes the spawn read as a station instead of the
	-- middle of an empty road. Posts stay on the curb, outside player traffic.
	local gantryZ = -92.2
	for _, side in ipairs({-1, 1}) do
		makePart(
			concourse,
			"ArrivalGantryPost",
			CFrame.new(center + Vector3.new(side * 18.2, 8.2, gantryZ)),
			Vector3.new(0.8, 16.4, 0.8),
			COLORS.metalLight,
			Enum.Material.Metal
		)
		local foot = makePart(
			concourse,
			"ArrivalGantryFoot",
			CFrame.new(center + Vector3.new(side * 18.2, 0.5, gantryZ)),
			Vector3.new(2.2, 1, 2.2),
			COLORS.metal,
			Enum.Material.DiamondPlate
		)
		foot:SetAttribute("LobbyWayfinding", true)
	end
	makePart(
		concourse,
		"ArrivalGantryBeam",
		CFrame.new(center + Vector3.new(0, 13.8, gantryZ)),
		Vector3.new(37.2, 0.85, 0.85),
		COLORS.metal,
		Enum.Material.Metal
	)

	-- A small pedestrian crossing and two benches turn the dead middle stretch
	-- into a readable waiting area without touching any bay or queue footprint.
	for stripe = -4, 4 do
		local crossing = makePart(
			concourse,
			"ConcourseCrossingStripe",
			CFrame.new(center + Vector3.new(0, 0.045, 42 + stripe * 1.55)),
			Vector3.new(30.4, 0.08, 0.72),
			stripe % 2 == 0 and Color3.fromRGB(192, 178, 120) or Color3.fromRGB(132, 124, 91),
			Enum.Material.SmoothPlastic,
			0.12
		)
		crossing.CanCollide = false
		crossing.CanTouch = false
		crossing.CanQuery = false
		crossing:SetAttribute("LobbyWayfinding", true)
	end
	addConcourseBench(concourse, center, -1, 54)
	addConcourseBench(concourse, center, 1, 54)
	addSupplyKiosk(concourse, center)
	addDonationLeaderboard(concourse, center)
	addPartyButton(concourse, center)

	-- The signal console is a harmless lobby toy. It runs a synchronized light
	-- wave down the road, giving waiting groups something to trigger together.
	local consolePosition = center + Vector3.new(-27.2, 3.25, 35)
	local consoleCF = CFrame.lookAt(consolePosition, center + Vector3.new(0, 3.25, 35))
	local console = makePart(
		concourse,
		"ZyntraSignalConsole",
		consoleCF,
		Vector3.new(4.8, 6.2, 2.35),
		Color3.fromRGB(35, 42, 41),
		Enum.Material.Metal
	)
	console:SetAttribute("LobbySocialProp", true)
	local screen = makePart(
		concourse,
		"ZyntraSignalConsoleScreen",
		consoleCF * CFrame.new(0, 0.55, -1.21),
		Vector3.new(4.05, 2.85, 0.12),
		Color3.fromRGB(8, 14, 13),
		Enum.Material.SmoothPlastic
	)
	screen.CanCollide = false
	local signalTitle, signalSubtitle = addBoard(
		screen,
		Enum.NormalId.Front,
		"SIGNAL SWEEP",
		"PRESS TO PULSE THE TRANSIT LINE",
		COLORS.green
	)
	local button = makePart(
		concourse,
		"SignalSweepButton",
		consoleCF * CFrame.new(0, -1.8, -1.35),
		Vector3.new(2.4, 0.72, 0.38),
		Color3.fromRGB(45, 157, 112),
		Enum.Material.Neon
	)
	button.CanCollide = false
	button:SetAttribute("LobbySocialProp", true)
	local prompt = Instance.new("ProximityPrompt")
	prompt.Name = "SignalSweepPrompt"
	prompt.ActionText = "RUN LIGHT SWEEP"
	prompt.ObjectText = "ZYNTRA SIGNAL CONSOLE"
	prompt.KeyboardKeyCode = Enum.KeyCode.E
	prompt.GamepadKeyCode = Enum.KeyCode.ButtonX
	prompt.HoldDuration = 0.2
	prompt.MaxActivationDistance = 10
	prompt.RequiresLineOfSight = false
	prompt.Parent = button

	local baseSignalColor = Color3.fromRGB(39, 126, 121)
	local pulseSignalColor = Color3.fromRGB(86, 255, 173)
	local signalGroups = {}
	for z = -112, 112, 12 do
		local group = {}
		for _, side in ipairs({-1, 1}) do
			local node = makePart(
				concourse,
				"TransitSignalNode",
				CFrame.new(center + Vector3.new(side * 14.75, 0.13, z)),
				Vector3.new(0.42, 0.12, 2.25),
				baseSignalColor,
				Enum.Material.Neon,
				0.28
			)
			node.CanCollide = false
			node.CanTouch = false
			node.CanQuery = false
			node:SetAttribute("LobbyWayfinding", true)
			local glow = Instance.new("PointLight")
			glow.Name = "SignalNodeGlow"
			glow.Color = baseSignalColor
			glow.Brightness = 0.04
			glow.Range = 4
			glow.Shadows = false
			glow.Parent = node
			table.insert(group, {Part = node, Light = glow})
		end
		table.insert(signalGroups, group)
	end

	local sweepBusy = false
	prompt.Triggered:Connect(function()
		if sweepBusy or not lobbyModel.Parent then return end
		sweepBusy = true
		prompt.Enabled = false
		lobbyModel:SetAttribute("SignalSweepSerial", (lobbyModel:GetAttribute("SignalSweepSerial") or 0) + 1)
		signalTitle.Text = "SIGNAL SWEEP ACTIVE"
		signalSubtitle.Text = "FOLLOW THE LIGHT WAVE"
		button.Color = pulseSignalColor

		for groupIndex, group in ipairs(signalGroups) do
			task.delay((groupIndex - 1) * 0.075, function()
				for _, record in ipairs(group) do
					if record.Part.Parent and record.Light.Parent then
						TweenService:Create(record.Part, TweenInfo.new(0.12), {
							Color = pulseSignalColor,
							Transparency = 0,
						}):Play()
						TweenService:Create(record.Light, TweenInfo.new(0.12), {
							Color = pulseSignalColor,
							Brightness = 1.15,
							Range = 11,
						}):Play()
						task.delay(0.48, function()
							if record.Part.Parent and record.Light.Parent then
								TweenService:Create(record.Part, TweenInfo.new(0.38), {
									Color = baseSignalColor,
									Transparency = 0.28,
								}):Play()
								TweenService:Create(record.Light, TweenInfo.new(0.38), {
									Color = baseSignalColor,
									Brightness = 0.04,
									Range = 4,
								}):Play()
							end
						end)
					end
				end
			end)
		end

		task.delay(#signalGroups * 0.075 + 1.05, function()
			if button.Parent then button.Color = Color3.fromRGB(45, 157, 112) end
			if signalTitle.Parent then signalTitle.Text = "SIGNAL SWEEP" end
			if signalSubtitle.Parent then signalSubtitle.Text = "PRESS TO PULSE THE TRANSIT LINE" end
			if prompt.Parent then prompt.Enabled = true end
			sweepBusy = false
		end)
	end)

	return concourse
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
	model:SetAttribute("TextureVersion", 9)
	model:SetAttribute("LobbyAestheticRevision", 3)
	model:SetAttribute("DispatchConcourseVersion", 7)
	model:SetAttribute("SupplyKioskVersion", 4)
	model:SetAttribute("DonationLeaderboardVersion", 2)
	model:SetAttribute("PartyButtonVersion", 1)
	model:SetAttribute("TunnelCurveRevision", 2)
	model:SetAttribute("SignageRevision", 2)
	model:SetAttribute("RoundedSignFacesVersion", 1)
	model:SetAttribute("LevelSignMountVersion", 1)
	model:SetAttribute("CircularBayGeometryVersion", 1)
	model:SetAttribute("CircularLaunchPadVersion", 2)
	model:SetAttribute("Level2DecorativeBasinVersion", 1)
	model:SetAttribute("RoundedStationMonitorVersion", 3) -- v3: depth-tested monitors (no more through-wall screens)
	model:SetAttribute("BayFurnitureCollisionVersion", 1) -- v1: floor furniture in the bays is solid

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
	-- A 48-sided half-circle keeps both the concrete skin and black ribs visually
	-- smooth at player scale while remaining lightweight static geometry.
	local shellSegments = 48
	local doorwayShellSegments = math.ceil(shellSegments / 8)
	local shellChord = 2 * radius * math.sin(math.pi / shellSegments) + 0.6
	model:SetAttribute("TunnelShellSegments", shellSegments)

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

	-- Curved concrete shell. The lowest 22.5-degree band on each side is
	-- segmented around the level bays; full-length low panels would physically
	-- wall off every doorway even though the decorative frames remained visible.
	for i = 1, shellSegments - 1 do
		local theta = math.pi * (i / shellSegments)
		local position = center + Vector3.new(
			math.cos(theta) * radius,
			1 + math.sin(theta) * radius,
			0
		)
		local segmentedAtDoors = i <= doorwayShellSegments or i >= shellSegments - doorwayShellSegments
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

	-- Keep the road lighting purely Zyntra cyan; the old alternating red/amber
	-- emergency curb markers competed with the level-room wayfinding.

	addLobbyConcourse(detail, center, model)

	local stations = {}
	local levelDefs = {
		{level = 1, side = -1, z = -80, active = true},
		{level = 2, side = 1, z = -80, active = true},
		{level = 3, side = -1, z = 0, active = true},
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
		CFrame.new(center + Vector3.new(0, 18.1, -92.2)),
		Vector3.new(32, 7.2, 0.55),
		COLORS.metal,
		Enum.Material.Metal
	)
	welcome.CanCollide = false
	addBoard(
		welcome,
		Enum.NormalId.Front,
		"ZYNTRA\nTRANSIT GATES",
		"LEVEL ACCESS IS THROUGH THE SIDE GATES",
		COLORS.green
	)
	addBoard(
		welcome,
		Enum.NormalId.Back,
		"ZYNTRA\nTRANSIT GATES",
		"LEVEL ACCESS IS THROUGH THE SIDE GATES",
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
