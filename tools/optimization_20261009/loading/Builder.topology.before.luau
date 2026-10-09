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
		-- LOBBY_COLLISION_20261004b (owner): everything outside the queue bays is solid: the DJ console, the speaker
		-- towers and subwoofers, the stage rail and the loose office furniture. All of them are Box-fidelity
		-- MeshParts, so each gets its own box. Gates, conduits, signs and floor visuals are left alone (a gate's box
		-- would close its doorway; the floors already have colliders).
		local SOLID = {DJConsole = true, SpeakerTower = true, Subwoofer = true, StageRearRail = true, CRTMonitor = true,
			FilingCabinet = true, Sofa = true, Desk = true, StackChair = true, Photocopier = true, VinylBench = true,
			WireTrolley = true, RolledCarpet = true, R4PartyChair = true, BeigeKeyboard = true}
		for _, d in ipairs(visuals:GetChildren()) do
			if SOLID[d.Name] then solid(d) end
		end
		-- END_PILES_REMOVED_20261004 (owner: "remove all the furniture from the ends of the tunnels", for load time
		-- and frame rate). The two piles EndBlockades builds (219 MeshParts), the 400-piece fill this block used to
		-- add behind them, and the loose office furniture standing at the foot of the south pile are all taken
		-- out; the stage, its speakers and the DJ console stay. The folder itself is kept (empty): the Ready line
		-- below still reads its triangle attribute.
		local piles = visuals:FindFirstChild("Reference End Furniture Piles")
		local removed = 0
		if piles then
			for _, piece in ipairs(piles:GetChildren()) do
				piece:Destroy()
				removed += 1
			end
			piles:SetAttribute("AddedInstancedTriangles", 0)
		end
		local STAGE = {DJConsole = true, SpeakerTower = true, Subwoofer = true, StageRearRail = true}
		for _, d in ipairs(visuals:GetChildren()) do
			if SOLID[d.Name] and not STAGE[d.Name] then
				local at = d:IsA("BasePart") and d.Position or (d:IsA("Model") and d:GetPivot().Position)
				if at and math.abs((at - center).Z) > 118 then
					d:Destroy()
					removed += 1
				end
			end
		end
		model:SetAttribute("EndFurnitureRemoved", removed)
	end
	-- BAY_DRESSING_20261004. A queue bay dressed to match the level behind it (owner request): Level 5 as a small
	--   void room, Level 4 as the foyer of the synthwave cinema. The bay's old decor is hidden where it clashes, never
	--   deleted. The wall gets a thin lining panel in front of each wall collider, the floor a disc, and the SET
	--   comes from tools/level5_void/build_bay.py, which builds both bays in Blender and writes the tables between
	--   the markers. Bay-local coordinates: y up from the floor's top, z toward the entrance.
	do
		local SETS = {
			[5] = {
				-- LEVEL5_BAY_SET_BEGIN (generated; edit build_bay.py, not this table)
				{n="Step", c="rose", s={9,0.8,1.7}, p={0,0.4,-18.45}},
				{n="Step", c="blue", s={9,1.6,1.7}, p={0,0.8,-20.15}},
				{n="Step", c="amber", s={9,2.4,1.7}, p={0,1.2,-21.85}},
				{n="Step", c="mint", s={9,3.2,1.7}, p={0,1.6,-23.55}},
				{n="Step", c="violet", s={9,4,1.9}, p={0,2,-25.35}},
				{n="Door", c="black", s={6,11,0.4}, p={0,9.5,-26.55}, m="SmoothPlastic"},
				{n="DoorPost", c="coral", s={1,15,1}, p={-3.5,7.5,-26.55}},
				{n="DoorPost", c="coral", s={1,15,1}, p={3.5,7.5,-26.55}},
				{n="DoorLintel", c="coral", s={8,1.1,1}, p={0,15.55,-26.55}},
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
			},
			[4] = {
				-- LEVEL4_BAY_SET_BEGIN (generated; edit build_bay.py, not this table)
				{n="Marquee", c="screen", s={14,3.4,0.6}, p={0,14.3,-26.3}, ghost=true, m="SmoothPlastic", text="NOW SHOWING", tc="warm"},
				{n="MarqueeTrim", c="magenta", s={14.6,0.24,0.7}, p={0,16.12,-26.3}, ghost=true, m="Neon"},
				{n="MarqueeTrim", c="cyan", s={14.6,0.24,0.7}, p={0,12.48,-26.3}, ghost=true, m="Neon"},
				{n="Bulb", c="warm", s={0.5,0.5,0.5}, p={-6.4,12,-25.9}, ball=true, ghost=true, m="Neon"},
				{n="Bulb", c="warm", s={0.5,0.5,0.5}, p={-4.8,12,-25.9}, ball=true, ghost=true, m="Neon", light={16,0.7}},
				{n="Bulb", c="warm", s={0.5,0.5,0.5}, p={-3.2,12,-25.9}, ball=true, ghost=true, m="Neon"},
				{n="Bulb", c="warm", s={0.5,0.5,0.5}, p={-1.6,12,-25.9}, ball=true, ghost=true, m="Neon"},
				{n="Bulb", c="warm", s={0.5,0.5,0.5}, p={0,12,-25.9}, ball=true, ghost=true, m="Neon", light={16,0.7}},
				{n="Bulb", c="warm", s={0.5,0.5,0.5}, p={1.6,12,-25.9}, ball=true, ghost=true, m="Neon"},
				{n="Bulb", c="warm", s={0.5,0.5,0.5}, p={3.2,12,-25.9}, ball=true, ghost=true, m="Neon"},
				{n="Bulb", c="warm", s={0.5,0.5,0.5}, p={4.8,12,-25.9}, ball=true, ghost=true, m="Neon", light={16,0.7}},
				{n="Bulb", c="warm", s={0.5,0.5,0.5}, p={6.4,12,-25.9}, ball=true, ghost=true, m="Neon"},
				{n="Poster", c="screen", s={5.4,8.1,0.3}, p={-19.693,7.45,17.732}, ghost=true, m="SmoothPlastic", yaw=132, img="rbxassetid://111560448892703"},
				{n="PosterFrame", c="cyan", s={6,0.22,0.4}, p={-19.693,11.61,17.732}, ghost=true, m="Neon", lc="cyan", yaw=132, light={14,0.6}},
				{n="PosterFrame", c="cyan", s={6,0.22,0.4}, p={-19.693,3.29,17.732}, ghost=true, m="Neon", yaw=132},
				{n="Poster", c="screen", s={5.4,8.1,0.3}, p={19.693,7.45,17.732}, ghost=true, m="SmoothPlastic", yaw=-132, img="rbxassetid://99844209195430"},
				{n="PosterFrame", c="magenta", s={6,0.22,0.4}, p={19.693,11.61,17.732}, ghost=true, m="Neon", lc="magenta", yaw=-132, light={14,0.6}},
				{n="PosterFrame", c="magenta", s={6,0.22,0.4}, p={19.693,3.29,17.732}, ghost=true, m="Neon", yaw=-132},
				{n="PosterCase", c="screen", s={5.7,8.25,0.86}, p={-8,7.3,-23.9}, ghost=true, m="SmoothPlastic"},
				{n="Poster", c="screen", s={5.2,7.8,0.06}, p={-8,7.3,-23.44}, ghost=true, m="SmoothPlastic", img="rbxassetid://107732660117869"},
				{n="PosterFrame", c="magenta", s={5.9,0.22,0.4}, p={-8,11.595,-23.47}, ghost=true, m="Neon", lc="magenta", light={14,0.6}},
				{n="PosterFrame", c="magenta", s={5.9,0.22,0.4}, p={-8,3.005,-23.47}, ghost=true, m="Neon"},
				{n="PosterCase", c="screen", s={5.7,8.25,0.86}, p={8,7.3,-23.9}, ghost=true, m="SmoothPlastic"},
				{n="Poster", c="screen", s={5.2,7.8,0.06}, p={8,7.3,-23.44}, ghost=true, m="SmoothPlastic", img="rbxassetid://70389718286652"},
				{n="PosterFrame", c="cyan", s={5.9,0.22,0.4}, p={8,11.595,-23.47}, ghost=true, m="Neon", lc="cyan", light={14,0.6}},
				{n="PosterFrame", c="cyan", s={5.9,0.22,0.4}, p={8,3.005,-23.47}, ghost=true, m="Neon"},
				{n="RopePost", c="gold", s={0.5,3.2,0.5}, p={-3.6,1.6,17}, m="Metal"},
				{n="RopeCap", c="gold", s={0.8,0.8,0.8}, p={-3.6,3.4,17}, ball=true, ghost=true, m="Metal"},
				{n="RopePost", c="gold", s={0.5,3.2,0.5}, p={-3.6,1.6,21.5}, m="Metal"},
				{n="RopeCap", c="gold", s={0.8,0.8,0.8}, p={-3.6,3.4,21.5}, ball=true, ghost=true, m="Metal"},
				{n="RopePost", c="gold", s={0.5,3.2,0.5}, p={-3.6,1.6,26}, m="Metal"},
				{n="RopeCap", c="gold", s={0.8,0.8,0.8}, p={-3.6,3.4,26}, ball=true, ghost=true, m="Metal"},
				{n="Rope", c="velvet", s={0.22,0.22,4.2}, p={-3.6,2.61,19.25}, ghost=true, m="Fabric"},
				{n="Rope", c="velvet", s={0.22,0.22,4.2}, p={-3.6,2.61,23.75}, ghost=true, m="Fabric"},
				{n="RopePost", c="gold", s={0.5,3.2,0.5}, p={3.6,1.6,17}, m="Metal"},
				{n="RopeCap", c="gold", s={0.8,0.8,0.8}, p={3.6,3.4,17}, ball=true, ghost=true, m="Metal"},
				{n="RopePost", c="gold", s={0.5,3.2,0.5}, p={3.6,1.6,21.5}, m="Metal"},
				{n="RopeCap", c="gold", s={0.8,0.8,0.8}, p={3.6,3.4,21.5}, ball=true, ghost=true, m="Metal"},
				{n="RopePost", c="gold", s={0.5,3.2,0.5}, p={3.6,1.6,26}, m="Metal"},
				{n="RopeCap", c="gold", s={0.8,0.8,0.8}, p={3.6,3.4,26}, ball=true, ghost=true, m="Metal"},
				{n="Rope", c="velvet", s={0.22,0.22,4.2}, p={3.6,2.61,19.25}, ghost=true, m="Fabric"},
				{n="Rope", c="velvet", s={0.22,0.22,4.2}, p={3.6,2.61,23.75}, ghost=true, m="Fabric"},
				-- LEVEL4_BAY_SET_END
			},
		}
		local COLOURS = {
			rose = Color3.fromRGB(224, 150, 200), blue = Color3.fromRGB(92, 150, 200), amber = Color3.fromRGB(228, 180, 88),
			mint = Color3.fromRGB(150, 216, 182), violet = Color3.fromRGB(164, 134, 214), coral = Color3.fromRGB(236, 118, 102),
			black = Color3.fromRGB(4, 4, 5), sphere = Color3.fromRGB(26, 38, 120), orb = Color3.fromRGB(255, 255, 250),
			navy = Color3.fromRGB(34, 20, 64), magenta = Color3.fromRGB(255, 64, 176), cyan = Color3.fromRGB(70, 230, 255),
			gold = Color3.fromRGB(212, 170, 80), velvet = Color3.fromRGB(150, 22, 44), carpet = Color3.fromRGB(46, 22, 60),
			screen = Color3.fromRGB(12, 10, 20), warm = Color3.fromRGB(255, 214, 150),
		}
		local ROOMS = {"rose", "blue", "amber", "mint", "violet", "coral"}
		local STYLE = {
			[5] = {folder = "Level5VoidBay", hide = "BayDecorLevel5", floor = "black", floorMaterial = Enum.Material.SmoothPlastic,
				lining = function(share) return COLOURS[ROOMS[math.clamp(math.floor(share * #ROOMS) + 1, 1, #ROOMS)]], Enum.Material.Plaster end},
			[4] = {folder = "Level4CinemaBay", floor = "carpet", floorMaterial = Enum.Material.Fabric, bands = {{6.2, "cyan"}, {15.4, "magenta"}},
				lining = function() return COLOURS.navy, Enum.Material.Fabric end},
		}
		local plaster = game:GetService("MaterialService"):FindFirstChild("L5 Void Plaster") ~= nil
		local pads = model:FindFirstChild("PreviewQueuePads")
		local signs = model:FindFirstChild("LevelGateSigns")
		for level, style in pairs(STYLE) do
			local bay = pads and pads:FindFirstChild("QueueBay_Level" .. level)
			local floor = bay and bay:FindFirstChild("ChamberFloor")
			local header = signs and signs:FindFirstChild("LEVEL " .. level .. " Door Header")
			if not floor or not header then continue end
			local top = floor.Position + Vector3.new(0, math.min(floor.Size.X, floor.Size.Y, floor.Size.Z) / 2, 0)
			local toward = ((header.Position - floor.Position) * Vector3.new(1, 0, 1)).Unit
			local frame = CFrame.lookAt(top, top - toward)                    -- +Z is the entrance
			local set = Instance.new("Folder")
			set.Name = style.folder
			set:SetAttribute("LobbyReimaginedOwned", true)
			set.Parent = model
			local function piece(name, size, cf, colour, material, collide)
				local part = Instance.new("Part")
				part.Name, part.Size, part.CFrame, part.Color = name, size, cf, colour
				part.Anchored, part.CanCollide, part.CanTouch, part.CanQuery = true, collide, false, collide
				part.Material = material == Enum.Material.Plaster and Enum.Material.SmoothPlastic or material   -- Level 5's smooth finish
				part.TopSurface, part.BottomSurface = Enum.SurfaceType.Smooth, Enum.SurfaceType.Smooth
				part:SetAttribute("LobbyReimaginedOwned", true)
				part.Parent = set
				return part
			end
			local old = style.hide and visuals:FindFirstChild(style.hide)
			for _, d in ipairs(old and old:GetDescendants() or {}) do
				if d:IsA("BasePart") then d.Transparency, d.CanCollide, d.CanQuery, d.CastShadow = 1, false, false, false end
			end
			for _, wall in ipairs(model:GetDescendants()) do
				if wall:IsA("BasePart") and wall.Name == "Bay Wall" and wall.Size.Y > 21 then
					local at = frame:PointToObjectSpace(wall.Position)
					local radius = math.sqrt(at.X * at.X + at.Z * at.Z)
					if radius > 26 and radius < 30 and math.abs(at.Y - 11) < 3 then
						local inward = ((top - wall.Position) * Vector3.new(1, 0, 1)).Unit
						local share = (math.atan2(at.X, -at.Z) + math.pi) / (2 * math.pi)        -- 0..1 round the bay, the entrance at both ends
						local colour, material = style.lining(share)
						piece("Lining", Vector3.new(wall.Size.X + 0.16, wall.Size.Y, 0.12), wall.CFrame + inward * 0.42, colour, material, false)
						for _, band in ipairs(style.bands or {}) do
							local strip = piece("NeonBand", Vector3.new(wall.Size.X + 0.16, 0.22, 0.1),
								wall.CFrame + inward * 0.52 + Vector3.new(0, band[1] - 11, 0), COLOURS[band[2]], Enum.Material.Neon, false)
							strip.CastShadow = false
						end
					end
				end
			end
			local disc = piece("BayFloor", Vector3.new(0.05, 55.8, 55.8), frame * CFrame.new(0, 0.045, 0) * CFrame.Angles(0, 0, math.pi / 2),
				COLOURS[style.floor], style.floorMaterial, false)
			disc.Shape = Enum.PartType.Cylinder
			if style.floor == "black" then disc.Reflectance = 0.06 end
			for _, row in ipairs(SETS[level]) do
				local part = piece(row.n, Vector3.new(row.s[1], row.s[2], row.s[3]),
					frame * CFrame.new(row.p[1], row.p[2], row.p[3]) * CFrame.Angles(0, math.rad(row.yaw or 0), 0),
					COLOURS[row.c], Enum.Material[row.m or (row.ball and "SmoothPlastic" or "Plaster")], not row.ghost)
				if row.ball then
					part.Shape = Enum.PartType.Ball
					if row.c == "sphere" then part.Reflectance = 0.25 end
				end
				if row.cyl then part.Shape = Enum.PartType.Cylinder end
				if row.m == "Neon" then part.CastShadow = false end
				if row.light then
					local glow = Instance.new("PointLight")
					glow.Range, glow.Brightness, glow.Shadows = row.light[1], row.light[2], false
					glow.Color = COLOURS[row.lc or "warm"]
					glow.Parent = part
					part.CastShadow = false
				end
				if row.img then
					local sheet = Instance.new("Decal")
					sheet.Face, sheet.Texture = Enum.NormalId.Back, row.img
					sheet.Parent = part
					local lamp = Instance.new("SurfaceLight")                -- a picture light, so the one-sheet reads in the dark bay
					lamp.Face, lamp.Range, lamp.Brightness, lamp.Angle, lamp.Shadows = Enum.NormalId.Back, 8, 1.3, 150, false
					lamp.Parent = part
				end
				if row.text then
					local gui = Instance.new("SurfaceGui")
					gui.Face, gui.CanvasSize, gui.LightInfluence, gui.Brightness = Enum.NormalId.Back, Vector2.new(900, 200), 0, 1.4
					local label = Instance.new("TextLabel")
					label.Size, label.BackgroundTransparency = UDim2.fromScale(1, 1), 1
					label.Font, label.TextScaled, label.Text = Enum.Font.Arcade, true, row.text
					label.TextColor3 = COLOURS[row.tc or "warm"]
					label.Parent = gui
					gui.Parent = part
				end
			end
		end
	end
	-- INFINITE_END_20261004 (owner: "make the end of the tunnel where the DJ set is look like the tunnel proceeds
	--   into infinity ... without making the lobby heavy ... then block it off with a metal fence that cannot be
	--   jumped over, and a warning sign"). The end wall carries ONE picture: this same tunnel, photographed in the
	--   game from 40 studs in front of the wall at eye height, with the stage and every sign hidden and the far end
	--   lost in the dark, cropped to the wall's own cross-section (assets/lobby-infinite-tunnel-20261004). It is a
	--   flat image, so it only lines up exactly from about that distance; the fence keeps everyone at least 7 studs
	--   off it. One part and one image for the tunnel, about 70 small parts for the fence.
	do
		local visuals = model:FindFirstChild("BlenderVisuals")
		local dj = visuals and visuals:FindFirstChild("DJConsole")
		local djAt = dj and (dj:IsA("Model") and dj:GetPivot().Position or dj.Position)
		local wall
		for _, item in ipairs(visuals and visuals:GetChildren() or {}) do
			if item.Name == "EndBackstop" and item:IsA("BasePart") and djAt
				and (not wall or (item.Position - djAt).Magnitude < (wall.Position - djAt).Magnitude) then wall = item end
		end
		if wall then
			local inward = (djAt - wall.Position) * Vector3.new(1, 0, 1)
			inward = math.abs(inward.X) > math.abs(inward.Z) and Vector3.new(math.sign(inward.X), 0, 0) or Vector3.new(0, 0, math.sign(inward.Z))
			local thick = math.min(wall.Size.X, wall.Size.Z)
			local width, height = math.max(wall.Size.X, wall.Size.Z), wall.Size.Y
			local floorY = wall.Position.Y - height / 2 + 1
			local set = Instance.new("Folder")
			set.Name = "InfiniteTunnelEnd"
			set:SetAttribute(OWNED, true)
			set.Parent = model
			local function piece(name, size, cf, colour, material, collide)
				local part = Instance.new("Part")
				part.Name, part.Size, part.CFrame, part.Color, part.Material = name, size, cf, colour, material
				part.Anchored, part.CanCollide, part.CanTouch, part.CanQuery, part.CastShadow = true, collide, false, collide, false
				part.TopSurface, part.BottomSurface = Enum.SurfaceType.Smooth, Enum.SurfaceType.Smooth
				part:SetAttribute(OWNED, true)
				part.Parent = set
				return part
			end
			-- TUNNEL_BEYOND_20261005. The flat picture did not work (owner: "the tunnel that goes on effect doesn't work
			-- with that picture ... make the tunnel longer after the fence and use perspective ... and make it just
			-- pitch black at some point"): seen from the stage, off its one right spot, a photo is a poster. So the
			-- tunnel really continues: the end wall is hidden and the lobby's own last 40-stud section (shell, rib,
			-- cable trays, conduit, lamps, road, pavement - the Blender meshes, cloned, so no new asset) is repeated
			-- five times beyond it. Real geometry has real perspective from every angle. Sheets of black across it,
			-- each a little denser, take it down to nothing, and a solid black cap closes the far end. About 75 parts,
			-- none colliding or casting shadows; the meshes are instances of ones the lobby already loads.
			wall.Transparency = 1
			for _, d in ipairs(wall:GetDescendants()) do
				if d:IsA("Decal") or d:IsA("Texture") then d.Transparency = 1 elseif d:IsA("SurfaceAppearance") then d:Destroy() end
			end
			local REPEAT = {PlainShell = true, ArchRib = true, CableTray = true, ConduitSection = true, Fluorescent = true,
				RoadSection = true, SidewalkSection = true}
			local SECTION, COPIES = 40, 5
			-- REACH_DARK_20261007 (owner, with a picture from a few steps behind the fence: "you can see the built
			-- monster and that it's not complete, make sure it is dark all the way down to the entity"). The copies
			-- were lit for 120 studs and only veiled after that, so the eyes and arms of the easter egg stood in a
			-- lit tunnel. Now the light is gone 70 studs in and the tunnel itself goes black with it: each copied
			-- section keeps this much of its colour (Lighting.Ambient lights an unlit shell too; black parts are the
			-- only thing it cannot light). The creature's own pieces are blacked out to match by its client script.
			-- (Seen in play: 0.5 on the second section was already black and drew a hard line across the road where
			-- the first section ends; a Color3 is not a linear amount of light.)
			local SHADE = {1, 0.78, 0.45, 0.12, 0}
			local outward = -inward
			local last = {}
			for _, item in ipairs(visuals:GetChildren()) do
				if REPEAT[item.Name] and item ~= wall then
					local at = item:IsA("Model") and item:GetPivot().Position or (item:IsA("BasePart") and item.Position or nil)
					local along = at and (at - wall.Position):Dot(inward)
					if along and along > 0.6 and along <= SECTION + 0.6 then table.insert(last, item) end
				end
			end
			for n = 1, COPIES do
				for _, item in ipairs(last) do
					local copy = item:Clone()
					copy.Name = "Beyond" .. item.Name
					if copy:IsA("Model") then copy:PivotTo(item:GetPivot() + outward * SECTION * n) else copy.CFrame = item.CFrame + outward * SECTION * n end
					local shade = SHADE[n]
					for _, d in ipairs(copy:IsA("BasePart") and {copy, table.unpack(copy:GetDescendants())} or copy:GetDescendants()) do
						if d:IsA("BasePart") then
							d.Anchored, d.CanCollide, d.CanTouch, d.CanQuery, d.CastShadow = true, false, false, false, false
							if shade < 1 then
								d.Color = Color3.new(d.Color.R * shade, d.Color.G * shade, d.Color.B * shade)
								d.Reflectance = 0
								if shade <= 0.2 and d:IsA("MeshPart") and d.TextureID ~= "" then d.TextureID = "" end   -- (a texture may not take the tint)
							end
						elseif d:IsA("SurfaceAppearance") then
							if shade < 1 then d.Color = Color3.new(d.Color.R * shade, d.Color.G * shade, d.Color.B * shade) end
						elseif d:IsA("Light") then
							d:Destroy()                                    -- lit by what spills in from the lobby, and less of it each section
						end
					end
					copy:SetAttribute(OWNED, true)
					copy.Parent = set
				end
			end
			-- Seen in play (2026-10-05): with no lamps of their own the copies were black from the first stud - a
			-- closed shell gets no light under Realistic lighting - so the tunnel just stopped at the fence. The
			-- lobby's own lamps over its last section are repeated with the shell, weaker the further in they hang.
			-- REACH_DARK_20261007: every lamp fades by its own distance behind the wall (not a whole section at a
			-- time, which drew a line across the road), and the last of the light is LAMPS_END studs in.
			local lamps = model:FindFirstChild("PreviewLighting")
			local LAMPS_END, LAMPS_FIRST = 70, 0.5
			for _, holder in ipairs(lamps and lamps:GetChildren() or {}) do
				local at = holder:IsA("BasePart") and holder.Position or (holder:IsA("Model") and holder:GetPivot().Position) or nil
				local along = at and (at - wall.Position):Dot(inward)
				if along and along > 0.6 and along <= SECTION + 0.6 and holder:FindFirstChildWhichIsA("Light", true) then
					for n = 1, COPIES do
						local depth = SECTION * n - along                         -- studs behind the wall
						local fade = LAMPS_FIRST * math.clamp(1 - depth / LAMPS_END, 0, 1) ^ 1.5
						if fade < 0.01 then break end
						local copy = holder:Clone()
						copy.Name = "BeyondLamp"
						if copy:IsA("Model") then copy:PivotTo(holder:GetPivot() + outward * SECTION * n) else copy.CFrame = holder.CFrame + outward * SECTION * n end
						for _, d in ipairs(copy:GetDescendants()) do
							if d:IsA("Light") then d.Brightness *= fade; d.Shadows = false end
							if d:IsA("BasePart") then d.CanCollide, d.CanTouch, d.CanQuery, d.CastShadow = false, false, false, false end
						end
						if copy:IsA("BasePart") then copy.CanCollide, copy.CanTouch, copy.CanQuery, copy.CastShadow = false, false, false, false end
						copy:SetAttribute(OWNED, true)
						copy.Parent = set
					end
				end
			end
			local centre = wall.Position
			-- (the sheets in front of 150 are gone: they were what dimmed the tunnel before it was black itself, and
			-- they dimmed the easter egg's eyes with it. These two stand behind the eyes, in front of its shoulders.)
			for i, row in ipairs({{156, 0.25}, {172, 0.05}}) do    -- the dark, in sheets
				local at = centre + outward * row[1]
				local sheet = piece("BeyondDark", Vector3.new(width, height, 0.2), CFrame.lookAt(at, at + inward),
					Color3.new(0, 0, 0), Enum.Material.SmoothPlastic, false)
				sheet.Transparency = row[2]
			end
			local far = centre + outward * 190
			piece("BeyondEnd", Vector3.new(width + 8, height + 8, 1), CFrame.lookAt(far, far + inward), Color3.new(0, 0, 0), Enum.Material.SmoothPlastic, false)
			-- the fence: 7.6 studs in front of the wall (behind the stage), wall to wall, 15 studs high
			local METAL, DARK = Color3.fromRGB(150, 156, 162), Color3.fromRGB(92, 97, 104)
			local base = CFrame.lookAt(Vector3.new(wall.Position.X, floorY, wall.Position.Z) + inward * 7.6,
				Vector3.new(wall.Position.X, floorY, wall.Position.Z) + inward * 8.6)        -- local X across, -Z toward the lobby
			local TOP = 15
			local function room(dx)                                              -- headroom under the arch at this offset
				local a = math.abs(dx)
				return a <= 28.5 and TOP or math.max(2, TOP - (a - 28.5) * 2.4)
			end
			for i = -6, 6 do                                                      -- posts
				local dx = i * 5.6
				local h = room(dx)
				piece("FencePost", Vector3.new(0.55, h + 0.4, 0.55), base * CFrame.new(dx, h / 2 - 0.2, 0), DARK, Enum.Material.Metal, true)
				piece("FencePostCap", Vector3.new(0.8, 0.25, 0.8), base * CFrame.new(dx, h + 0.1, 0), METAL, Enum.Material.Metal, false)
			end
			for _, rail in ipairs({{0.9, 67}, {7.6, 63}, {14.6, 57.5}}) do        -- rails
				piece("FenceRail", Vector3.new(rail[2], 0.32, 0.32), base * CFrame.new(0, rail[1], 0), DARK, Enum.Material.Metal, true)
			end
			for i = -23, 23 do                                                    -- bars
				local dx = i * 1.4
				if i % 4 ~= 0 then
					local h = room(dx) - 0.3
					piece("FenceBar", Vector3.new(0.16, h, 0.16), base * CFrame.new(dx, h / 2 + 0.15, 0), METAL, Enum.Material.Metal, false)
				end
			end
			-- TUNNEL_REACH_20261006 (owner: "an easter egg: you CAN get over the fence here, and as soon as you are
			--   over there, big glowing eyes come on in the dark and long arms creep toward you; if you do not jump
			--   back it takes you and pulls you into the dark"). The creature is `Lobby Tunnel Reach` (server) and
			--   `Lobby Tunnel Reach Client`; this block only makes the place for it:
			--   1. What stops a body is as tall as the fence you see, no taller. It was a 30-stud sheet, and behind
			--      it stood two more walls nobody could see: the retired furniture pile's blockers (in the fence's
			--      own plane, right up to the arch) and the end cap. Those are switched off at this end.
			--   2. A way over and a way back: two road cases on the back corner of the stage (deck 4.5 -> 7.4 ->
			--      10.0; a jump from the tall one clears the 14.9 by more than a stud), and three crates behind the
			--      fence, off to the other side (3.6 -> 7.2 -> 10.8, set back so a jump from them clears it too).
			--   3. Ground to stand on behind the wall: the road, both pavements and the lower walls carry on for
			--      REACH_GROUND studs, unseen (the tunnel you see there is the copies above), and an unseen wall
			--      closes it before the first sheet of dark.
			--   The scripts read where all this is from the folder's attributes.
			local FENCE_TOP, REACH_GROUND = 14.9, 64
			local stop = piece("FenceCollision", Vector3.new(68, FENCE_TOP, 0.6), base * CFrame.new(0, FENCE_TOP / 2, 0), METAL, Enum.Material.Metal, true)
			stop.Transparency = 1
			local opened = 0
			local colliders = model:FindFirstChild("PreviewCollisions")
			for _, c in ipairs(colliders and colliders:GetChildren() or {}) do
				local along = c:IsA("BasePart") and (c.Position - wall.Position):Dot(inward)
				if along and along > -3 and along < 9
					and (c.Name == "Opaque End Cap" or c.Name == "Furniture Base" or c:GetAttribute("FurnitureEndBlocker") == true) then
					c.CanCollide, c.CanQuery, c.CanTouch = false, false, false
					c:SetAttribute("OpenedForTunnelReach", true)
					opened += 1
				end
			end
			local function unseen(name, size, cf)
				local part = piece(name, size, cf, Color3.new(0, 0, 0), Enum.Material.SmoothPlastic, true)
				part.Transparency = 1
				return part
			end
			local GAP = 7.6                                                -- the fence stands this far in front of the wall
			local mid = GAP + 1 + (REACH_GROUND - 1) / 2                   -- the lobby's own ground ends a stud behind the wall
			unseen("BeyondGround", Vector3.new(33, 1, REACH_GROUND - 1), base * CFrame.new(0, -0.5, mid))
			for _, side in ipairs({-1, 1}) do
				unseen("BeyondGround", Vector3.new(17.6, 0.8, REACH_GROUND - 1), base * CFrame.new(side * 25, 0.4, mid))
				unseen("BeyondSide", Vector3.new(1.3, 36, REACH_GROUND + 8), base * CFrame.new(side * 34.2, 18, GAP + REACH_GROUND / 2 - 3))
			end
			unseen("BeyondStop", Vector3.new(73, 39, 1), base * CFrame.new(0, 19.5, GAP + REACH_GROUND + 0.5))
			-- road cases (the stage's own gear) and crates (whatever was left behind the fence)
			local CASE, TRIM, GRIP = Color3.fromRGB(23, 24, 27), Color3.fromRGB(104, 108, 114), Color3.fromRGB(10, 10, 11)
			local WOOD, BATTEN = Color3.fromRGB(104, 80, 55), Color3.fromRGB(72, 54, 37)
			local function box(at, size, wooden)                           -- `at`: the middle of its underside, fence frame
				local hx, hy, hz = size.X / 2, size.Y / 2, size.Z / 2
				local body = piece(wooden and "ReachCrate" or "ReachCase", size - Vector3.new(0.14, 0.14, 0.14), at * CFrame.new(0, hy, 0),
					wooden and WOOD or CASE, wooden and Enum.Material.WoodPlanks or Enum.Material.SmoothPlastic, true)
				body.CastShadow = true
				local edge, metal = wooden and BATTEN or TRIM, wooden and Enum.Material.Wood or Enum.Material.Metal
				local w = wooden and 0.34 or 0.15
				for _, sx in ipairs({-1, 1}) do
					for _, sz in ipairs({-1, 1}) do
						piece("ReachBoxEdge", Vector3.new(w, size.Y, w), at * CFrame.new(sx * (hx - w / 2), hy, sz * (hz - w / 2)), edge, metal, false)
					end
					for _, y in ipairs({w / 2, size.Y - w / 2}) do
						piece("ReachBoxEdge", Vector3.new(w, w, size.Z), at * CFrame.new(sx * (hx - w / 2), y, 0), edge, metal, false)
						piece("ReachBoxEdge", Vector3.new(size.X, w, w), at * CFrame.new(0, y, sx * (hz - w / 2)), edge, metal, false)
					end
					if not wooden then                                     -- a recessed handle on either end, two latches on the lid
						piece("ReachBoxGrip", Vector3.new(0.06, 0.55, 1.2), at * CFrame.new(sx * (hx + 0.01), size.Y * 0.42, 0), GRIP, Enum.Material.Metal, false)
						piece("ReachBoxLatch", Vector3.new(0.36, 0.46, 0.07), at * CFrame.new(sx * size.X * 0.27, size.Y * 0.7, -hz - 0.02), TRIM, Enum.Material.Metal, false)
					end
				end
				if wooden then                                             -- a plank across each long face
					for _, sz in ipairs({-1, 1}) do
						piece("ReachBoxEdge", Vector3.new(size.X * 1.05, w, 0.12), at * CFrame.new(0, hy, sz * hz) * CFrame.Angles(0, 0, math.atan2(size.Y, size.X) * 0.82),
							BATTEN, Enum.Material.Wood, false)
					end
				else
					piece("ReachBoxEdge", Vector3.new(size.X + 0.04, 0.07, size.Z + 0.04), at * CFrame.new(0, size.Y * 0.7, 0), TRIM, Enum.Material.Metal, false)
				end
			end
			local DECK = 4.5                                               -- the stage's top above the road
			box(base * CFrame.new(10.3, DECK, -5.0), Vector3.new(4.2, 2.9, 2.8), false)
			box(base * CFrame.new(13.7, DECK, -4.95) * CFrame.Angles(0, math.rad(-4), 0), Vector3.new(2.6, 2.75, 2.8), false)
			box(base * CFrame.new(13.72, DECK + 2.75, -4.9) * CFrame.Angles(0, math.rad(3), 0), Vector3.new(2.6, 2.75, 2.7), false)
			for i, x in ipairs({-15.6, -12.1, -8.6}) do                    -- one, two and three crates high
				for level = 1, i do
					box(base * CFrame.new(x, (level - 1) * 3.6, 3.9) * CFrame.Angles(0, math.rad(((i * 7 + level * 11) % 9) - 4), 0),
						Vector3.new(3.4, 3.6, 3.2), true)
				end
			end
			local at = Vector3.new(wall.Position.X, floorY, wall.Position.Z)
			set:SetAttribute("ReachFrame", CFrame.lookAt(at, at + inward))  -- on the road at the wall: x across, y up, +z into the dark
			set:SetAttribute("ReachFence", GAP)
			set:SetAttribute("ReachGround", REACH_GROUND)
			set:SetAttribute("ReachOpened", opened)
			-- the signs: a large one high in the middle (over the DJ console), one at eye height either side of the stage
			local function sign(dx, y, w, h)
				piece("WarningSignBack", Vector3.new(w + 0.5, h + 0.5, 0.12), base * CFrame.new(dx, y, -0.3), DARK, Enum.Material.Metal, false)
				local plate = piece("WarningSign", Vector3.new(w, h, 0.1), base * CFrame.new(dx, y, -0.4), Color3.fromRGB(240, 190, 20), Enum.Material.SmoothPlastic, false)
				local gui = Instance.new("SurfaceGui")
				gui.Face, gui.CanvasSize, gui.LightInfluence = Enum.NormalId.Front, Vector2.new(math.floor(900 * w / h / 1.6), 560), 1
				local edge = Instance.new("Frame")
				edge.Size, edge.Position = UDim2.new(1, -28, 1, -28), UDim2.fromOffset(14, 14)
				edge.BackgroundTransparency = 1
				local line = Instance.new("UIStroke")
				line.Color, line.Thickness = Color3.fromRGB(18, 18, 18), 10
				line.Parent = edge
				edge.Parent = gui
				for _, row in ipairs({{"WARNING", 0.06, 0.4, Enum.Font.GothamBlack}, {"UNSTABLE AFTER THIS POINT", 0.48, 0.2, Enum.Font.GothamBold},
					{"STAY BEHIND THIS FENCE", 0.7, 0.2, Enum.Font.GothamBold}}) do
					local label = Instance.new("TextLabel")
					label.BackgroundTransparency, label.Text, label.Font, label.TextScaled = 1, row[1], row[4], true
					label.TextColor3 = Color3.fromRGB(18, 18, 18)
					label.Position, label.Size = UDim2.fromScale(0.06, row[2]), UDim2.fromScale(0.88, row[3])
					label.Parent = gui
				end
				gui.Parent = plate
			end
			sign(0, 11.4, 17, 5.6)
			sign(-22.4, 5.4, 9.2, 3.2)
			sign(22.4, 5.4, 9.2, 3.2)
		end
	end
	-- ARRIVAL_GATE_20261004 (owner: "behind them the wall is like a gate they have arrived from ... a huge metal door
	--   in the wall, and the wall around it a shining subtle force field of Zyntra colour"). The end wall FARTHEST
	--   from the DJ stage, the one behind the spawn: a blast door, two leaves in a heavy frame, and over the rest of
	--   the wall one sheet of ForceField in the store's teal with a faint glow. About 45 parts, none colliding (the
	--   wall's own colliders are untouched).
	do
		local ZYNTRA = Color3.fromRGB(73, 245, 204)
		local visuals = model:FindFirstChild("BlenderVisuals")
		local dj = visuals and visuals:FindFirstChild("DJConsole")
		local djAt = dj and (dj:IsA("Model") and dj:GetPivot().Position or dj.Position)
		local wall
		for _, item in ipairs(visuals and visuals:GetChildren() or {}) do
			if item.Name == "EndBackstop" and item:IsA("BasePart") and djAt
				and (not wall or (item.Position - djAt).Magnitude > (wall.Position - djAt).Magnitude) then wall = item end
		end
		if wall then
			local inward = (djAt - wall.Position) * Vector3.new(1, 0, 1)
			inward = math.abs(inward.X) > math.abs(inward.Z) and Vector3.new(math.sign(inward.X), 0, 0) or Vector3.new(0, 0, math.sign(inward.Z))
			local thick = math.min(wall.Size.X, wall.Size.Z)
			local width, height = math.max(wall.Size.X, wall.Size.Z), wall.Size.Y
			local floorY = wall.Position.Y - height / 2 + 1
			local set = Instance.new("Folder")
			set.Name = "ArrivalGate"
			set:SetAttribute(OWNED, true)
			set.Parent = model
			local at = Vector3.new(wall.Position.X, floorY, wall.Position.Z) + inward * (thick / 2)
			local base = CFrame.lookAt(at, at + inward)                           -- local X across, Y up from the floor, -Z into the lobby
			local function piece(name, size, offset, colour, material, shape)
				local part = Instance.new("Part")
				part.Name, part.Size, part.Color, part.Material = name, size, colour, material
				if shape then part.Shape = shape end
				part.CFrame = base * offset
				part.Anchored, part.CanCollide, part.CanTouch, part.CanQuery, part.CastShadow = true, false, false, false, false
				part.TopSurface, part.BottomSurface = Enum.SurfaceType.Smooth, Enum.SurfaceType.Smooth
				part:SetAttribute(OWNED, true)
				part.Parent = set
				return part
			end
			local STEEL, DARK, LEAF = Color3.fromRGB(96, 102, 110), Color3.fromRGB(48, 52, 58), Color3.fromRGB(128, 134, 141)
			local M = Enum.Material
			-- the field: the whole wall, then a soft glow off it
			local field = piece("ForceField", Vector3.new(width, height, 0.2), CFrame.new(0, height / 2 - 1, -0.2), ZYNTRA, M.ForceField)
			field.Transparency = 0.62                 -- seen in play: 0.25 was a mint wall, 0.82 hardly there
			local glow = Instance.new("SurfaceLight")
			glow.Face, glow.Color, glow.Brightness, glow.Range, glow.Angle, glow.Shadows = Enum.NormalId.Front, ZYNTRA, 0.32, 16, 120, false
			glow.Parent = field
			-- the frame
			local W, H = 13, 22                                                   -- one leaf
			piece("GateJamb", Vector3.new(2.6, H + 2.6, 1.8), CFrame.new(-(W + 1.3), (H + 2.6) / 2, -0.9), DARK, M.Metal)
			piece("GateJamb", Vector3.new(2.6, H + 2.6, 1.8), CFrame.new(W + 1.3, (H + 2.6) / 2, -0.9), DARK, M.Metal)
			local lintel = piece("GateLintel", Vector3.new(W * 2 + 5.2, 2.6, 1.8), CFrame.new(0, H + 1.3, -0.9), DARK, M.Metal)
			piece("GateSill", Vector3.new(W * 2 + 5.2, 0.4, 2.4), CFrame.new(0, 0.2, -1.2), DARK, M.DiamondPlate)
			-- the leaves, their ribs, hinges and the seam
			for _, side in ipairs({-1, 1}) do
				piece("GateLeaf", Vector3.new(W, H, 0.9), CFrame.new(side * W / 2, H / 2, -0.75), LEAF, M.Metal)
				for _, y in ipairs({2.6, 7.6, 14.4, 19.4}) do
					piece("GateRib", Vector3.new(W - 1.4, 0.8, 0.35), CFrame.new(side * W / 2, y, -1.35), STEEL, M.Metal)
				end
				piece("GatePanel", Vector3.new(W - 3, 4.2, 0.2), CFrame.new(side * W / 2, 11, -1.28), STEEL, M.DiamondPlate)
				for _, y in ipairs({3.5, 11, 18.5}) do
					piece("GateHinge", Vector3.new(1.3, 2.2, 0.7), CFrame.new(side * (W - 0.2), y, -1.45), DARK, M.Metal)
				end
				piece("GateHazard", Vector3.new(W - 0.6, 1.1, 0.12), CFrame.new(side * W / 2, 0.95, -1.24), Color3.fromRGB(222, 172, 24), M.SmoothPlastic)
				piece("GateLamp", Vector3.new(3.2, 0.35, 0.15), CFrame.new(side * 11.6, H + 1.3, -1.85), ZYNTRA, M.Neon)
			end
			piece("GateSeam", Vector3.new(0.3, H, 1.0), CFrame.new(0, H / 2, -0.8), Color3.fromRGB(12, 13, 15), M.SmoothPlastic)
			-- the lock in the middle: a wheel and the one light on the door
			piece("GateLock", Vector3.new(0.6, 5, 5), CFrame.new(0, 11, -1.5) * CFrame.Angles(0, math.rad(90), 0), DARK, M.Metal, Enum.PartType.Cylinder)
			piece("GateLockLight", Vector3.new(0.7, 1.6, 1.6), CFrame.new(0, 11, -1.55) * CFrame.Angles(0, math.rad(90), 0), ZYNTRA, M.Neon, Enum.PartType.Cylinder)
			for _, angle in ipairs({0, 60, 120}) do
				piece("GateLockBar", Vector3.new(5.6, 0.5, 0.3), CFrame.new(0, 11, -1.7) * CFrame.Angles(0, 0, math.rad(angle)), STEEL, M.Metal)
			end
			-- the name over it
			-- The name over it. Owner, 2026-10-04: "the gate's text is not entirely visible" - it was an 11 x 1.5 plate
			-- with the lamps overlapping its ends. Now a plate nearly the width of the door, standing clear of the
			-- lintel, with the lamps moved out to the corners; the text is sized to the plate, not scaled into it.
			local plate = piece("GateNameplate", Vector3.new(19, 2.1, 0.12), CFrame.new(0, H + 1.3, -2.0), Color3.fromRGB(10, 22, 20), M.SmoothPlastic)
			local gui = Instance.new("SurfaceGui")
			gui.Face, gui.SizingMode, gui.PixelsPerStud = Enum.NormalId.Front, Enum.SurfaceGuiSizingMode.PixelsPerStud, 50
			gui.LightInfluence, gui.Brightness, gui.ClipsDescendants = 0, 1.2, false
			local label = Instance.new("TextLabel")
			label.Size, label.BackgroundTransparency = UDim2.fromScale(1, 1), 1
			label.Font, label.TextSize, label.Text, label.TextColor3 = Enum.Font.GothamBold, 62, "ZYNTRA  -  ARRIVAL GATE", ZYNTRA
			label.TextScaled = false
			label.Parent = gui
			gui.Parent = plate
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
