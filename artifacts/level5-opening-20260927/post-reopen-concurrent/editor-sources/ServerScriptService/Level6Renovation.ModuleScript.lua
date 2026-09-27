-- Level 6 cinema renovation. Append-only geometry over a verified preview baseline.
local Renovation = {}
local ORIGIN = CFrame.new(23000, 24, 0)
local RED_CARPET = "rbxassetid://92732673815453"
local RING_CARPET = "rbxassetid://85044000846144"
local DARK = Color3.fromRGB(21, 17, 22)
local WALL = Color3.fromRGB(77, 35, 42)
local WARM = Color3.fromRGB(255, 181, 91)
local TEAL = Color3.fromRGB(72, 231, 221)
local EPS = 0.02

local function near(a, b)
	return math.abs(a - b) < EPS
end

local function localPoint(p)
	return ORIGIN:PointToObjectSpace(p.Position)
end

local function part(parent, name, x0, y0, z0, x1, y1, z1, color, material, collide)
	local p = Instance.new("Part")
	p.Name = name
	p.Anchored = true
	p.CanTouch = false
	p.CanCollide = collide ~= false
	if not p.CanCollide then p.CanQuery = false end
	p.Size = Vector3.new(math.abs(x1 - x0), math.abs(y1 - y0), math.abs(z1 - z0))
	p.CFrame = ORIGIN * CFrame.new((x0 + x1) / 2, (y0 + y1) / 2, (z0 + z1) / 2)
	p.Color = color
	p.Material = material or Enum.Material.SmoothPlastic
	if p.Material == Enum.Material.Neon then p.CastShadow = false end
	p.Parent = parent
	return p
end

local function carpet(parent, name, x0, z0, x1, z1, id, top)
	local p = part(parent, name, x0, -0.6, z0, x1, top or 0, z1,
		Color3.fromRGB(83, 24, 31), Enum.Material.Fabric)
	local texture = Instance.new("Texture")
	texture.Name = "CarpetPattern"
	texture.Face = Enum.NormalId.Top
	texture.Texture = id
	texture.StudsPerTileU = 12
	texture.StudsPerTileV = 12
	texture.Parent = p
	return p
end

local function neon(parent, name, x0, y0, z0, x1, y1, z1, color)
	return part(parent, name, x0, y0, z0, x1, y1, z1, color, Enum.Material.Neon, false)
end

local function lamp(parent, name, x0, y0, z0, x1, y1, z1, color, range)
	local p = neon(parent, name, x0, y0, z0, x1, y1, z1, color)
	local light = Instance.new("PointLight")
	light.Color = color
	light.Brightness = 1.1
	light.Range = range or 20
	light.Shadows = false
	light.Parent = p
	return p
end

local function marker(parent, name, eye, target)
	local p = part(parent, name, eye.X - 0.5, eye.Y - 0.5, eye.Z - 0.5,
		eye.X + 0.5, eye.Y + 0.5, eye.Z + 0.5, Color3.new(0, 0, 0),
		Enum.Material.SmoothPlastic, false)
	p.Transparency = 1
	p.CanQuery = false
	p.CFrame = ORIGIN * CFrame.lookAt(eye, target)
	p:SetAttribute("FieldOfView", 70)
	return p
end

local function counts(model)
	local n, lights = 0, 0
	for _, d in model:GetDescendants() do
		if d:IsA("BasePart") then n += 1
		elseif d:IsA("Light") then lights += 1 end
	end
	return n, lights
end

local function exactPart(parent, name, center, size)
	local found
	for _, p in parent:GetChildren() do
		if p.Name == name and p:IsA("BasePart") then
			local q = localPoint(p)
			if (q - center).Magnitude < EPS and (p.Size - size).Magnitude < EPS then
				if found then return nil end
				found = p
			end
		end
	end
	return found
end

local HALLS = {
	{ name = "AuditoriumA_Red", rearX = 920, rearZ = -35, fx = 0, fz = -1,
		wall = Color3.fromRGB(100, 18, 22), accent = Color3.fromRGB(255, 78, 37), carpet = RED_CARPET },
	{ name = "AuditoriumB_Teal", rearX = 920, rearZ = 35, fx = 0, fz = 1,
		wall = Color3.fromRGB(25, 56, 65), accent = TEAL, carpet = RING_CARPET },
	{ name = "AuditoriumC_Burgundy", rearX = 1045, rearZ = 0, fx = 1, fz = 0,
		wall = Color3.fromRGB(72, 22, 40), accent = WARM, carpet = RED_CARPET },
}

local function at(spec, u, v)
	return spec.rearX - spec.fz * u + spec.fx * v,
		spec.rearZ + spec.fx * u + spec.fz * v
end

local function hallBox(folder, spec, name, u0, v0, u1, v1, y0, y1, color, material, collide)
	local x0, z0 = at(spec, u0, v0)
	local x1, z1 = at(spec, u1, v1)
	return part(folder, name, x0, y0, z0, x1, y1, z1, color, material, collide)
end

-- Claude Opus 5.5 Ultracode supplied the two-span connector and red-corridor repair;
-- the final preflight and grouped Studio mutation are kept here.
local function preflight(model)
	if not (model and model:IsA("Model") and model.Name == "Level 6 Cinema Preview"
		and model:GetAttribute("Level6Preview") == true
		and model:GetAttribute("PreviewOnly") == true) then
		return nil, "wrong preview model"
	end
	local ext = model:FindFirstChild("ExtendedCinema")
	if not (ext and ext:IsA("Model") and ext:GetAttribute("Complete") == true
		and ext:GetAttribute("PolishedV2") == true) then
		return nil, "completed Level 6 expansion missing"
	end
	local connector = ext:FindFirstChild("Connector")
	local red = model:FindFirstChild("RedTheaterCorridor")
	local fork = ext:FindFirstChild("Fork")
	local foyer = ext:FindFirstChild("Foyer")
	local booth = ext:FindFirstChild("ProjectionBooth")
	if not (connector and red and fork and foyer and booth) then
		return nil, "expected Level 6 folders missing"
	end
	local refs = { ext = ext, connector = connector, red = red, fork = fork,
		foyer = foyer, booth = booth, halls = {}, redParts = {}, coveGroups = {} }
	for _, name in { "ConnectorWall_North", "ConnectorWall_South" } do
		local p = exactPart(connector, name, Vector3.new(624.5, 6,
			name == "ConnectorWall_North" and -10.5 or 10.5), Vector3.new(31, 12, 1))
		if not p or not p.Anchored then return nil, "connector wall changed: " .. name end
		table.insert(refs.redParts, { p = p, newSizeX = 32, deltaX = -0.5 })
	end
	local connectorCeiling = exactPart(connector, "ConnectorCeiling",
		Vector3.new(624.5, 12.4, 0), Vector3.new(31, 0.8, 22))
	if not connectorCeiling then return nil, "connector ceiling changed" end
	table.insert(refs.redParts, { p = connectorCeiling, newSizeX = 32, deltaX = -0.5 })
	for _, name in { "Soffit", "NeonTube", "BlueAccentLine" } do
		local count = 0
		for _, p in red:GetChildren() do
			if p.Name == name then
				local q = localPoint(p)
				if not (p:IsA("Part") and p.Anchored and near(q.X, 113) and near(p.Size.X, 34)) then
					return nil, "red corridor fixture changed: " .. name
				end
				count += 1
				table.insert(refs.redParts, { p = p, newSizeX = 160, deltaX = 63 })
			end
		end
		if count ~= (name == "NeonTube" and 3 or 1) then
			return nil, "red corridor fixture count changed: " .. name
		end
	end
	local forkChildren = fork:GetChildren()
	for _, cove in forkChildren do
		if cove:IsA("BasePart") and cove.Name:match("Cove%d+$")
			and cove:FindFirstChildOfClass("PointLight") then
			local direction
			local name = cove.Name
			if name:match("^WallN") then direction = Vector3.new(0, 0, -1)
			elseif name:match("^WallS") then direction = Vector3.new(0, 0, 1)
			elseif name:match("WallW") then direction = Vector3.new(-1, 0, 0)
			elseif name:match("WallE") then direction = Vector3.new(1, 0, 0)
			else return nil, "unknown cove wall: " .. name end
			local group = { cove }
			local names = {}
			for _, stripe in forkChildren do
				if stripe:IsA("BasePart") and stripe.Name:match("^CoveStripe[123]$")
					and near(stripe.Position.X, cove.Position.X)
					and near(stripe.Position.Z, cove.Position.Z) then
					if names[stripe.Name] then return nil, "duplicate stripe at " .. name end
					names[stripe.Name] = true
					table.insert(group, stripe)
				end
			end
			if #group ~= 4 then return nil, "floating cove stripe group changed: " .. name end
			table.insert(refs.coveGroups, { parts = group, delta = direction * 1.65 })
		end
	end
	if #refs.coveGroups == 0 then return nil, "fork coves missing" end
	for _, spec in HALLS do
		local hall = ext:FindFirstChild(spec.name)
		if not hall then return nil, "hall missing: " .. spec.name end
		local sides, ceil, front = {}, nil, nil
		for _, p in hall:GetChildren() do
			if p.Name == "SideWall" and p:IsA("BasePart") then table.insert(sides, p)
			elseif p.Name == "Ceiling" then ceil = p
			elseif p.Name == "FrontWall" then front = p end
		end
		if #sides ~= 2 or not ceil or not front then return nil, "hall shell changed: " .. spec.name end
		local cx, cz = at(spec, 0, 95)
		if not (near(localPoint(ceil).X, cx) and near(localPoint(ceil).Z, cz)
			and near(localPoint(ceil).Y, 30.5) and near(ceil.Size.Y, 1)) then
			return nil, "hall ceiling changed: " .. spec.name
		end
		for _, p in sides do
			if not (near(p.Size.Y, 38) and near(localPoint(p).Y, 11)
				and (near(p.Size.X, 190) or near(p.Size.Z, 190))) then
				return nil, "hall sidewall changed: " .. spec.name
			end
		end
		refs.halls[spec.name] = { hall = hall, sides = sides, ceiling = ceil, front = front }
	end
	local baseNorth = exactPart(foyer, "FoyerWall", Vector3.new(705, 9, -71), Vector3.new(134, 18, 2))
	local baseSouth = exactPart(foyer, "FoyerWall", Vector3.new(705, 9, 71), Vector3.new(134, 18, 2))
	if not (baseNorth and baseSouth) then return nil, "foyer side walls changed" end
	refs.foyerNorth, refs.foyerSouth = baseNorth, baseSouth
	local oldBoothFloor = exactPart(booth, "BoothCarpet", Vector3.new(1005, -0.225, 25),
		Vector3.new(60, 0.45, 20))
	if not oldBoothFloor then return nil, "old booth changed" end
	return refs
end

local function buildHall(folder, spec)
	local f = Instance.new("Folder")
	f.Name = spec.name .. "_Renovation"
	f.Parent = folder
	local top = spec.wall:Lerp(Color3.new(0, 0, 0), 0.37)
	for _, side in { -1, 1 } do
		local spans = if side == -1 then { { 0, 20 }, { 34, 190 } }
			else { { 0, 20 }, { 34, 150 }, { 164, 190 } }
		for _, span in spans do
			hallBox(f, spec, "SegmentedSideWall", side * 89, span[1], side * 90,
				span[2], -8, 48, spec.wall, Enum.Material.Fabric)
		end
		for _, door in (if side == -1 then { { 20, 34 } }
			else { { 20, 34 }, { 150, 164 } }) do
			hallBox(f, spec, "SideDoorHeader", side * 89, door[1], side * 90,
				door[2], 14, 48, spec.wall, Enum.Material.Fabric)
			hallBox(f, spec, "SideDoorUnderfloor", side * 89, door[1], side * 90,
				door[2], -8, -0.8, spec.wall, Enum.Material.Fabric)
			for _, v in door do
				hallBox(f, spec, "SideDoorJamb", side * 88.8, v - 0.55,
					side * 89, v + 0.55, 0, 14, top, Enum.Material.Metal, false)
				hallBox(f, spec, "SideDoorJambGlow", side * 88.7, v - 0.2,
					side * 88.8, v + 0.2, 1, 12, spec.accent, Enum.Material.Neon, false)
			end
			hallBox(f, spec, "SideDoorLintel", side * 88.7, door[1],
				side * 88.8, door[2], 13.6, 14, spec.accent, Enum.Material.Neon, false)
		end
		hallBox(f, spec, "UpperAcousticRail", side * 88.8, 1,
			side * 89, 189, 42.8, 43.1, top, Enum.Material.Metal, false)
		hallBox(f, spec, "UpperCoveBacking", side * 87.9, 1,
			side * 89, 189, 45.4, 47.4, top, Enum.Material.SmoothPlastic, false)
		hallBox(f, spec, "UpperCove", side * 87.8, 1,
			side * 88, 189, 46.2, 46.5, spec.accent, Enum.Material.Neon, false)
		for v = 54, 166, 28 do
			hallBox(f, spec, "UpperAcousticPanel", side * 88.7, v,
				side * 89, v + 18, 30.5, 42.5, top, Enum.Material.Fabric, false)
		end
	end
	hallBox(f, spec, "ScreenHeader", -70, 186, 70, 188,
		35, 42, top, Enum.Material.Fabric, false)
	hallBox(f, spec, "ScreenLeftPier", -76, 185, -70, 189,
		-5, 42, top, Enum.Material.Fabric, false)
	hallBox(f, spec, "ScreenRightPier", 70, 185, 76, 189,
		-5, 42, top, Enum.Material.Fabric, false)
	hallBox(f, spec, "ScreenTopTrim", -70, 185, 70, 186,
		34.7, 35, spec.accent, Enum.Material.Neon, false)
	for _, v in { 44, 100, 156 } do
		hallBox(f, spec, "CeilingRib", -87, v, 87, v + 1.3,
			46.9, 48, top, Enum.Material.SmoothPlastic, false)
	end
	local eyeX, eyeZ = at(spec, 0, 10)
	local targetX, targetZ = at(spec, 0, 180)
	marker(f, "CameraHigh_" .. spec.name, Vector3.new(eyeX, 16, eyeZ),
		Vector3.new(targetX, 19, targetZ))
end

local function buildRing(folder, spec)
	local ring = Instance.new("Folder")
	ring.Name = spec.name .. "_Circulation"
	ring.Parent = folder
	local c = spec.carpet
	local wall = Color3.fromRGB(48, 36, 43)
	local ceiling = Color3.fromRGB(22, 19, 22)
	local accent = spec.accent
	local function hc(name, u0, v0, u1, v1, y0, y1, color, material, collide)
		return hallBox(ring, spec, name, u0, v0, u1, v1, y0, y1, color, material, collide)
	end
	local function floor(name, u0, v0, u1, v1)
		local x0, z0 = at(spec, u0, v0)
		local x1, z1 = at(spec, u1, v1)
		carpet(ring, name, x0, z0, x1, z1, c)
	end
	floor("RearVestibuleCarpet", -104, -20, 104, 1)
	floor("LeftReturnCarpet", -104, -20, -89, 211)
	floor("RightReturnCarpet", 89, -20, 104, 211)
	floor("FrontReturnCarpet", -104, 189, 104, 211)
	hc("RearVestibuleCeiling", -104, -20, 104, 1, 22, 23, ceiling)
	if spec.name == "AuditoriumB_Teal" then
		-- The high stairwell and booth fill the center of this rear roof.
		local roof = ring:FindFirstChild("RearVestibuleCeiling")
		roof.Transparency = 1
		roof.CanCollide = false
		roof.CanQuery = false
		hc("VestibuleRoofWest", 30, -20, 104, 1, 22, 23, ceiling)
		hc("StairwellRoof", -104, -20, -30, 1, 43, 44, ceiling)
	end
	for _, u in { -104, 104 } do
		hc("ReturnOuterWall", u, -20, u + (u < 0 and 1 or -1), 211,
			0, 18, wall, Enum.Material.Fabric)
	end
	hc("ReturnFrontWall", -104, 210, 104, 211, 0, 18, wall, Enum.Material.Fabric)
	for _, side in { -1, 1 } do
		hc("ReturnSideCeiling", side * 90, 1, side * 104, 210,
			18, 19, ceiling)
		hc("ReturnCove", side * 102.8, 1, side * 103.1, 208,
			16.7, 17, accent, Enum.Material.Neon, false)
		for _, v in { 75, 145 } do
			hc("PosterFrame", side * 102.7, v, side * 102.8, v + 12,
				4, 12, Color3.fromRGB(16, 14, 17), Enum.Material.SmoothPlastic, false)
			hc("PosterBlank", side * 102.5, v + 0.6, side * 102.7, v + 11.4,
				4.6, 11.4, spec.wall, Enum.Material.Fabric, false)
		end
	end
	hc("ReturnFrontCeiling", -104, 189, 104, 211, 18, 19, ceiling)
	local rearOpenings = if spec.name == "AuditoriumB_Teal"
		then { { -104, -77 }, { -65, -15 }, { 15, 104 } }
		else { { -104, -15 }, { 15, 104 } }
	for _, span in rearOpenings do
		hc("VestibuleBackWall", span[1], -20, span[2], -19,
			0, 22, wall, Enum.Material.Fabric)
	end
	hc("VestibuleEntryHeader", -15, -20, 15, -19, 14, 22, wall)
	if spec.name == "AuditoriumB_Teal" then
		hc("StairEntryHeader", -77, -20, -65, -19, 14, 43, wall)
	end
	for _, side in { -1, 1 } do
		hc("EntryFascia", side * 90, 18.8, side * 104, 19.1,
			14, 18, wall, Enum.Material.Fabric, false)
		hc("EntryStrip", side * 90, 19.1, side * 104, 19.4,
			13.3, 13.6, accent, Enum.Material.Neon, false)
	end
	hc("ExitFascia", 90, 148.8, 104, 149.1,
		14, 18, wall, Enum.Material.Fabric, false)
	hc("ExitStrip", 90, 149.1, 104, 149.4,
		13.3, 13.6, Color3.fromRGB(107, 242, 139), Enum.Material.Neon, false)
	for _, v in { 55, 135, 185 } do
		local x, z = at(spec, 97, v)
		lamp(ring, "ReturnDownlight", x - 1, 17.4, z - 1, x + 1, 17.7, z + 1,
			Color3.fromRGB(235, 211, 178), 17)
	end
	local eyeX, eyeZ = at(spec, -97, 26)
	local aimX, aimZ = at(spec, -90, 75)
	marker(ring, "CameraSideEntry_" .. spec.name,
		Vector3.new(eyeX, 7, eyeZ), Vector3.new(aimX, 7, aimZ))
end

local function buildBooth(folder)
	local f = Instance.new("Folder")
	f.Name = "RaisedProjectionBooth"
	f.Parent = folder
	local metal = Color3.fromRGB(61, 57, 62)
	local glass = Color3.fromRGB(162, 197, 207)
	-- B rear is z35. This 24-stud landing sits directly above the rear vestibule.
	part(f, "BoothFloor", 890, 23, 17, 950, 24, 35, DARK, Enum.Material.Metal)
	part(f, "BoothRoof", 890, 42, 17, 950, 43, 35, DARK)
	part(f, "BoothWestWall", 890, 24, 17, 891, 42, 35, DARK)
	part(f, "BoothEastWallRear", 949, 24, 17, 950, 42, 24, DARK)
	part(f, "BoothEastWallFront", 949, 24, 33, 950, 42, 35, DARK)
	part(f, "BoothEntryHeader", 949, 36, 24, 950, 42, 33, DARK)
	part(f, "BoothBackWall", 890, 24, 17, 950, 42, 18, DARK)
	part(f, "BoothWindowSill", 908, 24, 34, 932, 30, 35, DARK)
	part(f, "BoothWindowHeader", 908, 38, 34, 932, 42, 35, DARK)
	part(f, "BoothFrontLeft", 890, 24, 34, 908, 42, 35, DARK)
	part(f, "BoothFrontRight", 932, 24, 34, 950, 42, 35, DARK)
	local window = part(f, "HighProjectionWindow", 908, 30, 34.7, 932, 38, 34.85,
		glass, Enum.Material.Glass, false)
	window.Transparency = 0.65
	for _, x in { 912, 926 } do
		part(f, "ProjectorStand", x - 1.5, 24, 29, x + 1.5, 27, 32, metal, Enum.Material.Metal)
		part(f, "ProjectorBody", x - 2.5, 27, 27, x + 2.5, 30, 31, metal, Enum.Material.Metal)
		part(f, "ProjectorLens", x - 0.8, 28, 31, x + 0.8, 29, 32,
			Color3.fromRGB(225, 207, 169), Enum.Material.Glass, false)
	end
	lamp(f, "BoothLamp", 916, 41.2, 23, 924, 41.5, 27, WARM, 18)
	-- 24 one-stud steps from the existing fork-side staff recess to the booth floor.
	for i = 1, 24 do
		local x0 = 1000 - i * 2
		part(f, "BoothStair", x0, 0, 25, x0 + 2, i, 33,
			Color3.fromRGB(56, 48, 49), Enum.Material.Metal)
		if i % 4 == 0 then
			neon(f, "StairNosing", x0, i, 25, x0 + 2, i + 0.08, 25.25, WARM)
		end
	end
	part(f, "BoothUpperLanding", 948, 23, 24, 954, 24, 33,
		DARK, Enum.Material.Metal)
	part(f, "StairHandrail", 951, 25, 24.6, 1000, 27, 24.9,
		metal, Enum.Material.Metal, false)
	marker(f, "CameraRaisedBooth", Vector3.new(925, 30, 24),
		Vector3.new(920, 28, 145))
end

local function buildSideRooms(folder)
	local arcade = Instance.new("Folder")
	arcade.Name = "ArcadeWaitingLounge"
	arcade.Parent = folder
	local red = Color3.fromRGB(112, 24, 27)
	local metal = Color3.fromRGB(70, 62, 64)
	carpet(arcade, "ArcadeCarpet", 650, -140, 760, -70, RED_CARPET)
	part(arcade, "ArcadeCeiling", 649, 19, -141, 761, 20, -70, DARK)
	part(arcade, "ArcadeWestWall", 649, 0, -141, 650, 19, -70, red)
	part(arcade, "ArcadeEastWall", 760, 0, -141, 761, 19, -70, red)
	part(arcade, "ArcadeFarWall", 649, 0, -141, 761, 19, -140, red)
	neon(arcade, "ArcadeCoveWest", 650, 17, -139, 651, 17.3, -71, WARM)
	neon(arcade, "ArcadeCoveEast", 759, 17, -139, 760, 17.3, -71, WARM)
	neon(arcade, "ArcadeCoveFar", 651, 17, -140, 759, 17.3, -139, WARM)
	lamp(arcade, "ArcadeCeilingLight", 689, 18.6, -109, 693, 18.9, -105, WARM, 22)
	for _, x in { 668, 686, 724, 742 } do
		part(arcade, "SilentArcadeCabinet", x - 3, 0, -132, x + 3, 9, -128,
			metal, Enum.Material.Metal)
		part(arcade, "ArcadeScreenFrame", x - 2.5, 4.5, -127.9,
			x + 2.5, 8, -127.6, DARK, Enum.Material.SmoothPlastic, false)
		neon(arcade, "ArcadeCabinetTrim", x - 2.5, 8, -127.7,
			x + 2.5, 8.2, -127.5, if x % 2 == 0 then TEAL else WARM)
		part(arcade, "ArcadeControlDeck", x - 3, 3.4, -127.7, x + 3, 4, -125,
			Color3.fromRGB(35, 31, 36), Enum.Material.Metal)
	end
	for _, x in { 680, 728 } do
		part(arcade, "WaitingBench", x - 11, 1.6, -92, x + 11, 2.6, -88,
			Color3.fromRGB(62, 28, 36), Enum.Material.Fabric)
		part(arcade, "WaitingBenchBack", x - 11, 2, -93, x + 11, 6, -92,
			Color3.fromRGB(62, 28, 36), Enum.Material.Fabric)
	end
	part(arcade, "OldTicketCounter", 652, 0, -116, 663, 5, -81,
		Color3.fromRGB(85, 43, 42))
	neon(arcade, "TicketCounterTrim", 663, 4.4, -115, 663.2, 4.7, -82, WARM)
	marker(arcade, "CameraArcadeWaitingLounge",
		Vector3.new(705, 7, -76), Vector3.new(704, 7, -128))

	local rest = Instance.new("Folder")
	rest.Name = "RestroomHall"
	rest.Parent = folder
	carpet(rest, "RestroomCarpet", 741, 72, 812, 135, RING_CARPET)
	part(rest, "RestroomCeiling", 740, 19, 71, 813, 20, 136, DARK)
	part(rest, "RestroomWestWall", 740, 0, 72, 741, 19, 136, WALL)
	part(rest, "RestroomEastWall", 812, 0, 72, 813, 19, 136, WALL)
	part(rest, "RestroomFarWall", 740, 0, 135, 813, 19, 136, WALL)
	for _, x in { 768, 786, 804 } do
		part(rest, "StallDivider", x, 0, 105, x + 1, 11, 134,
			Color3.fromRGB(48, 54, 58), Enum.Material.Metal)
	end
	for _, x in { 759, 777, 795 } do
		part(rest, "StallDoor", x, 0, 104, x + 9, 10.5, 105,
			Color3.fromRGB(60, 67, 70), Enum.Material.Metal)
		neon(rest, "StallNumber", x + 3, 9.3, 103.7, x + 6, 9.5, 103.9, TEAL)
	end
	part(rest, "SinkCounter", 745, 3, 76, 748, 4, 101,
		Color3.fromRGB(118, 121, 116), Enum.Material.Marble)
	for _, z in { 80, 90, 100 } do
		part(rest, "EmptySink", 746, 4, z - 2, 750, 4.3, z + 2,
			Color3.fromRGB(145, 151, 151), Enum.Material.Metal, false)
		part(rest, "Mirror", 745, 6, z - 3, 745.2, 12, z + 3,
			Color3.fromRGB(143, 169, 179), Enum.Material.Glass, false)
	end
	lamp(rest, "RestroomLight", 776, 18.7, 86, 780, 19, 90,
		Color3.fromRGB(229, 227, 197), 24)
	marker(rest, "CameraRestroomHall", Vector3.new(754, 7, 77),
		Vector3.new(782, 7, 115))
end

local function buildFoyerDoors(folder)
	local doors = Instance.new("Folder")
	doors.Name = "FoyerSideEntrances"
	doors.Parent = folder
	local red = Color3.fromRGB(126, 24, 17)
	for _, span in { { 638, 695 }, { 715, 772 } } do
		part(doors, "ArcadeDoorWall", span[1], 0, -72, span[2], 18, -70, red)
	end
	part(doors, "ArcadeDoorHeader", 695, 14, -72, 715, 18, -70, red)
	for _, span in { { 638, 747 }, { 761, 772 } } do
		part(doors, "RestroomDoorWall", span[1], 0, 70, span[2], 18, 72, red)
	end
	part(doors, "RestroomDoorHeader", 747, 14, 70, 761, 18, 72, red)
	neon(doors, "ArcadeEntryGlow", 695, 13.7, -69.8, 715, 14, -69.6, WARM)
	neon(doors, "RestroomEntryGlow", 747, 13.7, 69.6, 761, 14, 69.8, TEAL)
	-- Underfloor plates overlap old and new carpets across each open threshold.
	part(doors, "ArcadeDoorUnderfloor", 695, -1, -73, 715, -0.55, -69,
		Color3.fromRGB(64, 22, 28), Enum.Material.Fabric)
	part(doors, "RestroomDoorUnderfloor", 747, -1, 69, 761, -0.55, 73,
		Color3.fromRGB(64, 22, 28), Enum.Material.Fabric)
end

local function buildJointCovers(folder)
	local f = Instance.new("Folder")
	f.Name = "JoinCovers"
	f.Parent = folder
	part(f, "OldToNewUnderfloor", 607, -1.2, -11, 642, -0.55, 11,
		Color3.fromRGB(48, 25, 27), Enum.Material.Fabric)
	part(f, "FoyerForkUnderfloor", 768, -1.2, -15, 772, -0.55, 15,
		Color3.fromRGB(48, 25, 27), Enum.Material.Fabric)
	for _, z in { -35, 35 } do
		part(f, "BranchHallUnderfloor", 904, -1.2, z - 2, 936, -0.55, z + 2,
			Color3.fromRGB(48, 25, 27), Enum.Material.Fabric)
	end
	part(f, "ForkHallCUnderfloor", 1043, -1.2, -16, 1047, -0.55, 16,
		Color3.fromRGB(48, 25, 27), Enum.Material.Fabric)
end

function Renovation.Apply(model)
	local existing = model and model:FindFirstChild("ExtendedCinema")
		and model.ExtendedCinema:FindFirstChild("RenovationV3")
	if existing then
		if existing:IsA("Model") and existing:GetAttribute("Complete") == true
			and model.ExtendedCinema:GetAttribute("RenovatedV3") == true then
			local n, lights = counts(model)
			model:SetAttribute("PartCount", n)
			model:SetAttribute("LightCount", lights)
			return existing
		end
		return nil, "incomplete RenovationV3 already exists"
	end
	local refs, reason = preflight(model)
	if not refs then return nil, reason end
	local folder = Instance.new("Model")
	folder.Name = "RenovationV3"
	local ok, buildError = pcall(function()
		for _, spec in HALLS do
			buildHall(folder, spec)
			buildRing(folder, spec)
		end
		buildBooth(folder)
		buildSideRooms(folder)
		buildFoyerDoors(folder)
		buildJointCovers(folder)
		-- The old B booth window left a solid-floor gap after it is concealed.
		part(folder, "OldBoothWindowInfill", 979, -8, 34,
			1005, 48, 35, HALLS[2].wall, Enum.Material.Fabric)
		part(folder, "HighBoothRearHeader", 908, 38, 35,
			932, 48, 36, HALLS[2].wall, Enum.Material.Fabric)
	end)
	if not ok then folder:Destroy(); return nil, tostring(buildError) end
	local oldParts, oldLights = counts(model)
	local newParts, newLights = counts(folder)
	if oldParts + newParts > 5000 or oldLights + newLights > 220 then
		folder:Destroy()
		return nil, "renovation exceeds Level 6 geometry budget"
	end
	-- Recheck the live baseline immediately before the non-yielding write.
	local fresh, changed = preflight(model)
	if not fresh or model:FindFirstChild("ExtendedCinema") ~= refs.ext
		or refs.ext:FindFirstChild("RenovationV3") then
		folder:Destroy()
		return nil, "Level 6 baseline changed: " .. tostring(changed)
	end
	local previous, recorded = {}, {}
	local function remember(p)
		if recorded[p] then return end
		recorded[p] = true
		table.insert(previous, {
			part = p, size = p.Size, cf = p.CFrame, transparency = p.Transparency,
			collide = p.CanCollide, query = p.CanQuery, shadow = p.CastShadow,
		})
	end
	local function ghost(p)
		remember(p)
		p.Transparency = 1
		p.CanCollide = false
		p.CanQuery = false
		p.CastShadow = false
	end
	local writeOk, writeError = pcall(function()
		for _, op in fresh.redParts do
			local p = op.p
			remember(p)
			p.Size = Vector3.new(op.newSizeX, p.Size.Y, p.Size.Z)
			p.CFrame += Vector3.new(op.deltaX, 0, 0)
		end
		for _, group in fresh.coveGroups do
			for _, p in group.parts do
				remember(p)
				p.CFrame += group.delta
			end
		end
		ghost(fresh.foyerNorth)
		ghost(fresh.foyerSouth)
		for _, spec in HALLS do
			local record = fresh.halls[spec.name]
			local hall = record.hall
			for _, p in record.sides do ghost(p) end
			remember(record.ceiling)
			record.ceiling.CFrame += Vector3.new(0, 18, 0)
			for _, p in hall:GetChildren() do
				if p:IsA("BasePart") then
					if p.Name == "Downlight" then
						remember(p)
						p.CFrame += Vector3.new(0, 18, 0)
					elseif p.Name == "RearWall" or p.Name == "FrontWall"
						or p.Name == "Drape"
						or (p.Name == "DoorHeader" and spec.name ~= "AuditoriumB_Teal") then
						remember(p)
						p.Size += Vector3.new(0, 18, 0)
						p.CFrame += Vector3.new(0, 9, 0)
					elseif p.Name == "Screen" then
						remember(p)
						p.Size += Vector3.new(0, 8, 0)
						p.CFrame += Vector3.new(0, 4, 0)
					elseif spec.name == "AuditoriumB_Teal"
						and (p.Name == "WindowSill" or p.Name == "WindowHeader"
							or p.Name == "BoothViewGlass") then
						ghost(p)
					end
				end
			end
		end
		for _, d in fresh.booth:GetDescendants() do
			if d:IsA("BasePart") then ghost(d) end
		end
		folder:SetAttribute("Complete", true)
		folder.Parent = refs.ext
		refs.ext:SetAttribute("RenovatedV3", true)
		model:SetAttribute("PartCount", oldParts + newParts)
		model:SetAttribute("LightCount", oldLights + newLights)
	end)
	if not writeOk then
		folder:Destroy()
		refs.ext:SetAttribute("RenovatedV3", nil)
		for i = #previous, 1, -1 do
			local state = previous[i]
			local p = state.part
			p.Size, p.CFrame = state.size, state.cf
			p.Transparency, p.CanCollide = state.transparency, state.collide
			p.CanQuery, p.CastShadow = state.query, state.shadow
		end
		model:SetAttribute("PartCount", oldParts)
		model:SetAttribute("LightCount", oldLights)
		return nil, tostring(writeError)
	end
	return folder
end

function Renovation.SelfCheck(model)
	local issues = {}
	if not (model and model:IsA("Model")) then
		return false, { Issues = { "preview missing" } }
	end
	local ext = model:FindFirstChild("ExtendedCinema")
	local v3 = ext and ext:FindFirstChild("RenovationV3")
	if not (v3 and v3:IsA("Model") and v3:GetAttribute("Complete") == true
		and ext:GetAttribute("RenovatedV3") == true) then
		table.insert(issues, "completed RenovationV3 missing")
	end
	local parts, lights = counts(model)
	if parts > 5000 or lights > 220 then table.insert(issues, "part/light budget exceeded") end
	if model:GetAttribute("PartCount") ~= parts or model:GetAttribute("LightCount") ~= lights then
		table.insert(issues, "count attributes stale")
	end
	if v3 then
		local doors, strips = 0, 0
		for _, d in v3:GetDescendants() do
			if d:IsA("BasePart") then
				if not d.Anchored then table.insert(issues, "unanchored: " .. d:GetFullName()) end
				if d.Name == "SideDoorHeader" then doors += 1 end
				if d.Name == "ReturnCove" then strips += 1 end
			end
		end
		if doors ~= 9 then table.insert(issues, "six side entries and three exits missing") end
		if strips ~= 6 then table.insert(issues, "perimeter return corridors missing") end
		local booth = v3:FindFirstChild("RaisedProjectionBooth")
		local window = booth and booth:FindFirstChild("HighProjectionWindow")
		if not (window and near(localPoint(window).X, 920)
			and localPoint(window).Y > 30) then
			table.insert(issues, "elevated centered booth window missing")
		end
		for _, spec in HALLS do
			local hall = ext:FindFirstChild(spec.name)
			local roof = hall and hall:FindFirstChild("Ceiling")
			if not (roof and near(localPoint(roof).Y, 48.5)) then
				table.insert(issues, "raised ceiling missing: " .. spec.name)
			end
		end
		if v3:IsDescendantOf(workspace) then
			local params = RaycastParams.new()
			params.FilterType = Enum.RaycastFilterType.Include
			params.FilterDescendantsInstances = { model }
			for _, sample in {
				Vector3.new(608.5, 9, 0), Vector3.new(705, 9, 0),
				Vector3.new(705, 9, -71), Vector3.new(754, 9, 71),
				Vector3.new(920, 9, -25), Vector3.new(920, 9, 25),
				Vector3.new(1020, 9, -190), Vector3.new(820, 9, 190),
				Vector3.new(1035, 9, 80), Vector3.new(1250, 9, 97),
			} do
				local hit = workspace:Raycast(ORIGIN:PointToWorldSpace(sample),
					Vector3.new(0, -22, 0), params)
				if not hit or hit.Position.Y < ORIGIN.Position.Y - 9 then
					table.insert(issues, "walkable floor gap at " .. tostring(sample))
				end
			end
		end
	end
	return #issues == 0, { Issues = issues, PartCount = parts, LightCount = lights }
end

return Renovation
