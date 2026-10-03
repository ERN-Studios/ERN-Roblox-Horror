-- Isolated Blender preview. The authoritative ServerLobby is never changed.
local HS = game:GetService("HttpService")
local RunService = game:GetService("RunService")
local DevAccess = require(game:GetService("ReplicatedStorage"):WaitForChild("DevAccess"))
local Bake = require(script.Parent:WaitForChild("RuntimeBake"))
local Module = {}
local NAME = "LobbyReimaginedPreview"
local OWNED = "LobbyReimaginedOwned"
local function vec(a) return Vector3.new(table.unpack(a)) end
local function allowed(player)
	return RunService:IsStudio() or DevAccess.IsLevel6PreviewAllowed(player)
end
local function part(parent, name, size, cf, colliding)
	local p = Instance.new("Part"); p.Name = name; p.Size = size; p.CFrame = cf
	p.Anchored = true; p.CanCollide = colliding == true; p.CanTouch = false; p.CanQuery = colliding == true
	p.Transparency = 1; p.CastShadow = false; p:SetAttribute(OWNED, true); p.Parent = parent
	return p
end
local function text(host, face, message, color, canvas)
	local gui = Instance.new("SurfaceGui"); gui.Name = "Preview Sign"; gui.Face = face
	gui.CanvasSize = canvas or Vector2.new(1100,200); gui.LightInfluence = 0; gui.Brightness = 1.2
	gui.AlwaysOnTop = false; gui.MaxDistance = 400; gui.Parent = host
	local label = Instance.new("TextLabel"); label.Name = "Label"; label.Size = UDim2.fromScale(1,1)
	label.BackgroundTransparency = 1; label.Text = message; label.TextColor3 = color
	label.Font = Enum.Font.GothamBold; label.TextScaled = true; label.Parent = gui
	return label
end
-- Move the original live renderer; its existing Value/attribute connections
-- are closure-held and would not survive cloning just the display model.
local function supportBoardTransfer(destination, center)
    local installed = destination:FindFirstChild("ZyntraDonationLeaderboardBoard", true)
    if installed then
        assert(installed:IsA("Model"), "Inspect conflicting R4 support board")
        return nil
    end
    local lobby = assert(workspace:FindFirstChild("ServerLobby"), "Original server lobby must precede R4")
    local board
    for _, descendant in ipairs(lobby:GetDescendants()) do
        if descendant.Name == "ZyntraDonationLeaderboardBoard" then
            assert(descendant:IsA("Model") and board == nil, "Inspect conflicting original support boards")
            board = descendant
        end
    end
    assert(board, "Original support board is not ready")
    local panel = board:FindFirstChild("LeaderboardPanel")
    assert(panel and panel:IsA("BasePart") and panel:FindFirstChild("DonationLeaderboardDisplay"),
        "Inspect original support-board renderer before relocation")
    return {
        Board = board,
        Parent = board.Parent,
        Pivot = board:GetPivot(),
        TargetPivot = CFrame.new(center + Vector3.new(-30, 7.15, -35) - panel.Position) * board:GetPivot(),
    }
end
local function applySupportBoardTransfer(transfer, destination)
    if not transfer then return end
    transfer.Board:PivotTo(transfer.TargetPivot)
    -- Never assign a nil direct Parent: the original renderer tears down on nil.
    transfer.Board.Parent = destination
end
local function restoreSupportBoardTransfer(transfer)
    if not transfer then return end
    transfer.Board.Parent = transfer.Parent
    transfer.Board:PivotTo(transfer.Pivot)
end
function Module.Build()
	assert(not RunService:IsClient(), "Server preview only")
	local existing = workspace:FindFirstChild(NAME)
	if existing then
		assert(existing:GetAttribute(OWNED) == true and existing:GetAttribute("Ready") == true, "Inspect conflicting preview first")
		-- Existing Level 5/6 access protection must survive board-relocation failure.
		require(script.Parent:WaitForChild("DevBayAccessGuard")).Start(existing)
		local transfer
		local ok, failure = pcall(function()
			local center = existing:GetAttribute("PreviewCenter")
			assert(typeof(center) == "Vector3", "Inspect R4 lobby center before relocating support board")
			transfer = supportBoardTransfer(existing, center)
			applySupportBoardTransfer(transfer, existing)
		end)
		if not ok then
			restoreSupportBoardTransfer(transfer)
			warn("[LobbyReimaginedPreview] Existing support-board relocation failed: " .. tostring(failure))
		end
		return existing
	end
	local manifest, kit = Bake.GetManifest(), Bake.Ensure()
	local center = vec(manifest.previewCenter)
	local model = Instance.new("Model"); model.Name = NAME; model.WorldPivot = CFrame.new(center)
	local transfer
	local ok, built = pcall(function()
	model.ModelStreamingMode = Enum.ModelStreamingMode.Atomic
	model:SetAttribute(OWNED,true); model:SetAttribute("Ready",false)
	model:SetAttribute("IsolatedDesignPreview",true); model:SetAttribute("RealLevelLaunches",true)
	model:SetAttribute("R3QueueRevision",3)
	model:SetAttribute("LobbyVisualRevision",4)
	model:SetAttribute("PreviewCenter",center); model:SetAttribute("BlenderSourceSHA256",manifest.sourceBlendSha256)
	local visuals = Instance.new("Folder"); visuals.Name = "BlenderVisuals"; visuals.Parent = model
	local collisions = Instance.new("Folder"); collisions.Name = "PreviewCollisions"; collisions.Parent = model
	local signs = Instance.new("Folder"); signs.Name = "LevelGateSigns"; signs.Parent = model
	local lighting = Instance.new("Folder"); lighting.Name = "PreviewLighting"; lighting.Parent = model
	local pads = Instance.new("Folder"); pads.Name = "PreviewQueuePads"; pads.Parent = model
	local function place(family, cf, parent)
		local source = assert(kit:FindFirstChild(family), "Missing Blender prefab "..family)
		local p = source:Clone()
        if p:IsA("Model") then
            p:PivotTo(cf*source:GetPivot())
            for _,d in ipairs(p:GetDescendants()) do if d:IsA("MeshPart") then d.DoubleSided=true end end
        else p.CFrame=cf*source.CFrame;p.DoubleSided=true end
        p.Parent=parent
		return p
	end
	for _, item in ipairs(manifest.placements) do
		local cf = CFrame.new(center+vec(item.robloxPosition))*CFrame.Angles(0,item.yaw or 0,0)
		local p = place(item.family,cf,visuals)
		if item.runtimeKind == "VinylDisc" then
			p:SetAttribute("PreviewVinylDisc",true); p:SetAttribute("RecordPivot",cf)
			p:SetAttribute("RecordMeshOffset",kit[item.family].CFrame)
			p:SetAttribute("DegreesPerSecond",12)
		end
	end
	local collisionItems = {}
	for _, item in ipairs(manifest.colliders) do
		local collider = part(collisions,item.name,vec(item.size),CFrame.new(center+vec(item.position))*CFrame.Angles(0,item.yaw or 0,0),true)
		table.insert(collisionItems,collider)
		if item.rotation then collider.CFrame = CFrame.new(center+vec(item.position))*CFrame.Angles(table.unpack(item.rotation)) end
		if item.shape == "Cylinder" then
			collider.Shape = Enum.PartType.Cylinder; collider.Size = Vector3.new(item.size[2],item.size[1],item.size[3])
			collider.CFrame *= CFrame.Angles(0,0,math.pi/2)
		end
	end
	for _, item in ipairs(manifest.signs) do
		local gate = CFrame.new(center+vec(item.gatePosition))*CFrame.Angles(0,item.yaw,0)
		local color = Color3.fromRGB(208,255,247)
		local label = "LEVEL "..item.level
		local lintel = part(signs,label.." Door Header",vec(item.headerLocalSize),gate*CFrame.new(vec(item.headerLocalPosition)),false)
		text(lintel,Enum.NormalId.Back,label,color,Vector2.new(450,110))
		local blade = part(signs,label.." Projecting Arrow",vec(item.bladeLocalSize),gate*CFrame.new(vec(item.bladeLocalPosition)),false)
		text(blade,Enum.NormalId.Left,"←  "..label,color,Vector2.new(650,150))
		text(blade,Enum.NormalId.Right,label.."  →",color,Vector2.new(650,150))
		lintel:SetAttribute("Level",item.level); blade:SetAttribute("Level",item.level)
		blade:SetAttribute("ArrowTowardDoor",true)
	end
	for _, item in ipairs(manifest.lights) do
		local lens = part(lighting,item.name,Vector3.new(.2,.2,.2),CFrame.new(center+vec(item.position)),false)
		local light = Instance.new("PointLight"); light.Name = "Preview Fill"; light.Color = item.name == "Tunnel Lamp" and Color3.fromRGB(205,214,190) or Color3.new(table.unpack(item.color))
		light.Brightness = item.brightness*(item.name == "Tunnel Lamp" and .28 or .5); light.Range = item.name == "Tunnel Lamp" and 36 or item.range
		light.Shadows = false; light.Parent = lens
	end
	-- Reuse verified product art; the original server focus poll owns both walls.
	local liveLobby = workspace:FindFirstChild("ServerLobby")
	local shop = liveLobby and liveLobby:FindFirstChild("ZyntraShopDisplay",true)
	if shop and shop:IsA("Model") then
		local visualShop = shop:Clone(); visualShop.Name = "R3ShopDisplay"
		visualShop:PivotTo(CFrame.new(center-Vector3.new(0,30,-760))*visualShop:GetPivot())
		visualShop:ScaleTo(visualShop:GetScale()*.9)
		for _,d in ipairs(visualShop:GetDescendants()) do
			if d:IsA("BasePart") then d.Anchored=true;d.CanCollide=false;d.CanTouch=false;d.CanQuery=false end
			if d:IsA("ProximityPrompt") then d.Enabled=false end
			if d:IsA("BaseScript") then d.Enabled=false end
			d:SetAttribute("ShopBobOrigin",nil);d:SetAttribute("ShopBobPhase",nil)
		end
		visualShop:SetAttribute("LobbyReimaginedOwned",true);visualShop.Parent=model
		local focusPlates=Instance.new("Folder");focusPlates.Name="PreviewShopPressurePlates";focusPlates.Parent=model
		for _,d in ipairs(visualShop:GetDescendants()) do
			if d:IsA("BasePart") and d.Name=="ShopPressurePlate" then
				local copy=d:Clone();copy.Name=tostring(copy:GetAttribute("ShopItemKey"));copy.Parent=focusPlates
			end
		end
	end
	local bays = {}
	for _, item in ipairs(manifest.bays) do
		local bay = Instance.new("Model");bay.Name="QueueBay_Level"..item.level
		bay:SetAttribute("CircularBayDiameter",item.diameter);bay.Parent=pads;bays[item.level]=bay
		bay:SetAttribute("BayCenter",center+vec(item.floorPosition))
	end
	local bayNames={ ["Bay Doorway Return"]=true,["Bay Floor"]=true,["Bay Wall"]=true,["Bay Roof"]=true,["Bay Entry Upper Frieze"]=true,
		["Queue Pad"]=true,["Queue Kiosk"]=true,["Connector Floor"]=true,["Connector Roof"]=true,["Connector Cheek"]=true,["Door Threshold"]=true }
	for _, collider in ipairs(collisionItems) do
		if bayNames[collider.Name] then
			local nearest,best=nil,math.huge
			for _,bay in pairs(bays) do
				local delta=collider.Position-bay:GetAttribute("BayCenter");local distance=delta.X*delta.X+delta.Z*delta.Z
				if distance<best then nearest,best=bay,distance end
			end
			if collider.Name=="Bay Floor" then collider.Name="ChamberFloor" end
			collider.Parent=assert(nearest)
		end
	end
	for _,bay in pairs(bays) do assert(bay:FindFirstChild("ChamberFloor"),"Missing real bay collider floor") end
	local perLevel = {}
	for _, item in ipairs(manifest.pads) do
		perLevel[item.level]=(perLevel[item.level] or 0)+1
		local displayIndex=perLevel[item.level]
		local station = Instance.new("Model"); station.Name = string.format("Level%d Queue %02d",item.level,displayIndex)
		station:SetAttribute(OWNED,true); station:SetAttribute("QueueActive",false); station.Parent = bays[item.level]
		local base = CFrame.new(center+vec(item.position))
		station:SetAttribute("HologramBase",base)
		local ring = place("HologramRing",base,station); ring.Name = "Active Queue Ring"
		ring.Material = Enum.Material.Neon; ring.Transparency = .8; ring.CastShadow = false
		local kiosk = CFrame.new(center+vec(item.kioskPosition))*CFrame.Angles(0,item.kioskYaw,0)
		local control = part(station,"Queue Kiosk Control",Vector3.new(1,1,1),kiosk*CFrame.new(vec(item.controlLocalPosition)),false)
		local statusHost = part(station,"Queue Status",vec(item.statusLocalSize),kiosk*CFrame.new(vec(item.statusLocalPosition)),false)
		local title = text(statusHost,Enum.NormalId[item.statusFace or "Back"],"STEP ON PAD",Color3.fromRGB(192,255,242),Vector2.new(1000,330))
		title.Name="QueueTitle";title.Position=UDim2.fromScale(0,.05);title.Size=UDim2.fromScale(1,.42)
		local sub=title:Clone();sub.Name="QueueSubtitle";sub.Position=UDim2.fromScale(0,.5);sub.Size=UDim2.fromScale(1,.4)
		sub.Text="CHOOSE 1–6 PLAYERS";sub.Parent=title.Parent
		local bayFloor=bays[item.level].ChamberFloor
		local toward=Vector3.new(bayFloor.Position.X,base.Position.Y,bayFloor.Position.Z)
		local zone=part(bays[item.level],"QueueZone"..displayIndex,Vector3.new(14.82,1,14.82),CFrame.lookAt(base.Position,toward),false)
		zone.Color=Color3.fromRGB(140,255,231);zone:SetAttribute("R3QueueId",100+(item.level-1)*4+displayIndex)
		zone:SetAttribute("LevelNumber",item.level);zone:SetAttribute("QueueDisplayIndex",displayIndex)
		zone:SetAttribute("QueueDetectorShape","Circle");zone:SetAttribute("QueueRadius",7.41)
		local ref=Instance.new("ObjectValue");ref.Name="QueueRenderOwner";ref.Value=station;ref.Parent=zone

		for band = 1,10 do
			local wall = place("HologramBand",base*CFrame.new(0,(band-1)*.6,0),station)
			wall.Name = string.format("HologramBand%02d",band); wall.Transparency = 1; wall.CastShadow = false
			wall.Material = Enum.Material.Neon; wall:SetAttribute("HologramBandIndex",band)
			wall:SetAttribute("HologramFullSize",wall.Size); wall:SetAttribute("HologramFullCFrame",wall.CFrame)
		end
	end
	assert(not workspace:FindFirstChild(NAME), "Concurrent preview appeared; refusing overwrite")
	-- Reuse the installed Blender furniture for dense reference end blockades.
	local endPiles = require(script.Parent:WaitForChild("EndBlockades")).Add(model, kit, manifest)
	local bayPolish = require(script.Parent:WaitForChild("LobbyPolishBays")).Add(model, kit, manifest)
	require(script.Parent:WaitForChild("MaterialPolish")).Apply(model)
	require(script.Parent:WaitForChild("LobbyPolishScene")).Apply(model)
	transfer = supportBoardTransfer(model, center)
	applySupportBoardTransfer(transfer, model)
	-- LOBBY_COLLISION_20261004 (reported by the other developer: "a lot of things in the lobby have no collision"
	-- and "the Level 4 cinema bay objects do not fit").
	--   The manifest's colliders cover the architecture; the bay furniture, the cinema seat row and the furniture
	--   piles at the tunnel ends were visuals only, so players walked through them. Their MeshParts carry Box
	--   collision fidelity, so turning CanCollide on gives each piece its own box and nothing wider.
	--   The cinema seat row is a straight 26.3-stud piece against a round wall of inner radius 27.84: at
	--   23.5 studs out its corners sat at 28.89 and showed through the wall. 1.5 studs toward the bay's
	--   centre puts them at 27.58.
	do
		local function solid(root)
			if not root then return end
			for _, d in ipairs(root:IsA("BasePart") and {root} or root:GetDescendants()) do
				if d:IsA("BasePart") and d.Transparency < 0.9 then d.CanCollide = true end
			end
		end
		local cinemaRow = visuals:FindFirstChild("BayDecorLevel4")
		local rowPart = cinemaRow and (cinemaRow:IsA("BasePart") and cinemaRow or cinemaRow:FindFirstChildWhichIsA("BasePart", true))
		if rowPart then
			local bayCentre = center + Vector3.new(63, 0.4, 0)
			local inward = (bayCentre - rowPart.Position) * Vector3.new(1, 0, 1)
			if inward.Magnitude > 22.5 then rowPart.CFrame += inward.Unit * 1.5 end
		end
		solid(cinemaRow)
		solid(visuals:FindFirstChild("Reference End Furniture Piles"))
		solid(bayPolish:FindFirstChild("Theme Furniture") or model:FindFirstChild("Theme Furniture", true))
	end
	-- LEVEL5_BAY_20261004. The Level 5 bay as a small void room, to match the level behind it (owner request).
	--   The suburb house fronts (BayDecorLevel5) are hidden, not deleted. The wall gets a plaster lining in the
	--   five room colours, one thin panel in front of each wall collider; the floor a black disc; and the set
	--   below (the stair to the lit doorway, the monoliths, the balls) comes from tools/level5_void/build_bay.py,
	--   which builds it in Blender and writes the table between the markers. Bay-local: z toward the entrance.
	do
		local SET = {
			-- LEVEL5_BAY_SET_BEGIN (generated; edit build_bay.py, not this table)
			{n="Step", c="rose", s={9,0.8,1.7}, p={0,0.4,-18.45}},
			{n="Step", c="blue", s={9,1.6,1.7}, p={0,0.8,-20.15}},
			{n="Step", c="amber", s={9,2.4,1.7}, p={0,1.2,-21.85}},
			{n="Step", c="mint", s={9,3.2,1.7}, p={0,1.6,-23.55}},
			{n="Step", c="violet", s={9,4,1.9}, p={0,2,-25.35}},
			{n="Door", c="black", s={6,11,0.4}, p={0,9.5,-26.55}, m="SmoothPlastic"},
			{n="DoorPost", c="violet", s={1,15,1}, p={-3.5,7.5,-26.55}},
			{n="DoorPost", c="violet", s={1,15,1}, p={3.5,7.5,-26.55}},
			{n="DoorLintel", c="violet", s={8,1.1,1}, p={0,15.55,-26.55}},
			{n="Orb", c="orb", s={2.2,2.2,2.2}, p={0,17.4,-22}, ball=true, ghost=true, m="Neon", light={30,1.3}},
			{n="OrbRod", c="black", s={0.2,3.5,0.2}, p={0,20.25,-22}, ghost=true, m="Metal"},
			{n="Monolith", c="rose", s={3.2,13,3.2}, p={-8.2,6.5,-23.4}},
			{n="Monolith", c="mint", s={2.6,8.5,2.6}, p={-11.6,4.25,-20.6}},
			{n="Monolith", c="amber", s={3,10.5,3}, p={8,5.25,-23.6}},
			{n="Monolith", c="blue", s={2.4,6,2.4}, p={11.4,3,-20.8}},
			{n="Bench", c="rose", s={2.6,1.7,8}, p={-22.6,0.85,0}},
			{n="Bench", c="blue", s={2.6,1.7,8}, p={22.6,0.85,0}},
			{n="Monolith", c="amber", s={1.8,9,1.8}, p={-23.2,4.5,-5.6}},
			{n="Monolith", c="mint", s={1.8,9,1.8}, p={23.2,4.5,5.6}},
			{n="Ball", c="sphere", s={1.6,1.6,1.6}, p={2.8,2.4,-20.15}, ball=true},
			{n="Ball", c="sphere", s={3,3,3}, p={-5.6,1.5,-18.9}, ball=true},
			{n="Ball", c="sphere", s={2,2,2}, p={11.4,7,-20.8}, ball=true},
			{n="Ball", c="sphere", s={1.4,1.4,1.4}, p={-22.6,2.4,2.4}, ball=true},
			-- LEVEL5_BAY_SET_END
		}
		local COLOURS = {
			rose = Color3.fromRGB(224, 150, 200), blue = Color3.fromRGB(92, 150, 200), amber = Color3.fromRGB(228, 180, 88),
			mint = Color3.fromRGB(150, 216, 182), violet = Color3.fromRGB(164, 134, 214), black = Color3.fromRGB(4, 4, 5),
			sphere = Color3.fromRGB(26, 38, 120), orb = Color3.fromRGB(255, 255, 250),
		}
		local ORDER = {"rose", "blue", "amber", "mint", "violet"}
		local pads = model:FindFirstChild("PreviewQueuePads")
		local bay = pads and pads:FindFirstChild("QueueBay_Level5")
		local floor = bay and bay:FindFirstChild("ChamberFloor")
		local signs = model:FindFirstChild("LevelGateSigns")
		local header = signs and signs:FindFirstChild("LEVEL 5 Door Header")
		if floor and header then
			local top = floor.Position + Vector3.new(0, math.min(floor.Size.X, floor.Size.Y, floor.Size.Z) / 2, 0)
			local toward = ((header.Position - floor.Position) * Vector3.new(1, 0, 1)).Unit
			local frame = CFrame.lookAt(top, top - toward)                    -- +Z is the entrance
			local plaster = game:GetService("MaterialService"):FindFirstChild("L5 Void Plaster") ~= nil
			local set = Instance.new("Folder")
			set.Name = "Level5VoidBay"
			set:SetAttribute("LobbyReimaginedOwned", true)
			set.Parent = model
			local function piece(name, size, cf, colour, material, collide)
				local part = Instance.new("Part")
				part.Name, part.Size, part.CFrame, part.Color = name, size, cf, colour
				part.Anchored, part.CanCollide, part.CanTouch, part.CanQuery = true, collide, false, collide
				part.Material = material
				if material == Enum.Material.Plaster and plaster then part.MaterialVariant = "L5 Void Plaster" end
				part.TopSurface, part.BottomSurface = Enum.SurfaceType.Smooth, Enum.SurfaceType.Smooth
				part:SetAttribute("LobbyReimaginedOwned", true)
				part.Parent = set
				return part
			end
			local old = visuals:FindFirstChild("BayDecorLevel5")
			for _, d in ipairs(old and old:GetDescendants() or {}) do
				if d:IsA("BasePart") then d.Transparency, d.CanCollide, d.CanQuery, d.CastShadow = 1, false, false, false end
			end
			for _, wall in ipairs(model:GetDescendants()) do
				if wall:IsA("BasePart") and wall.Name == "Bay Wall" and wall.Size.Y > 21 then
					local at = frame:PointToObjectSpace(wall.Position)
					local radius = math.sqrt(at.X * at.X + at.Z * at.Z)
					if radius > 26 and radius < 30 and math.abs(at.Y - 11) < 3 then
						local inward = (top - wall.Position) * Vector3.new(1, 0, 1)
						local share = (math.atan2(at.X, -at.Z) + math.pi) / (2 * math.pi)        -- 0..1 round the bay, the entrance at both ends
						local colour = COLOURS[ORDER[math.clamp(math.floor(share * 5) + 1, 1, 5)]]
						piece("Lining", Vector3.new(wall.Size.X + 0.16, wall.Size.Y, 0.12),
							wall.CFrame + inward.Unit * 0.42, colour, Enum.Material.Plaster, false)
					end
				end
			end
			local disc = piece("VoidFloor", Vector3.new(0.05, 55.8, 55.8), frame * CFrame.new(0, 0.045, 0) * CFrame.Angles(0, 0, math.pi / 2),
				COLOURS.black, Enum.Material.SmoothPlastic, false)
			disc.Shape = Enum.PartType.Cylinder
			disc.Reflectance = 0.06
			for _, row in ipairs(SET) do
				local part = piece(row.n, Vector3.new(row.s[1], row.s[2], row.s[3]), frame * CFrame.new(row.p[1], row.p[2], row.p[3]),
					COLOURS[row.c], Enum.Material[row.m or (row.ball and "SmoothPlastic" or "Plaster")], not row.ghost)
				if row.ball then
					part.Shape = Enum.PartType.Ball
					if row.c == "sphere" then part.Reflectance = 0.25 end
				end
				if row.light then
					local glow = Instance.new("PointLight")
					glow.Range, glow.Brightness, glow.Shadows = row.light[1], row.light[2], false
					glow.Color = Color3.fromRGB(255, 250, 240)
					glow.Parent = part
					part.CastShadow = false
				end
			end
		end
	end
	model:SetAttribute("Ready",true); model:SetAttribute("InstantiatedTriangles",manifest.instantiatedTriangles + endPiles:GetAttribute("AddedInstancedTriangles") + bayPolish:GetAttribute("AddedInstancedTriangles"))
	model.Parent = workspace
	require(script.Parent:WaitForChild("DevBayAccessGuard")).Start(model)
	return model
	end)
	if not ok then restoreSupportBoardTransfer(transfer); model:Destroy(); error(built) end
	return built
end
return Module
