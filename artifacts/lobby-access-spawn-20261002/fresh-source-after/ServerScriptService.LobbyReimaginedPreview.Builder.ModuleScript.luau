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
function Module.Build()
	assert(not RunService:IsClient(), "Server preview only")
	local existing = workspace:FindFirstChild(NAME)
	if existing then
		assert(existing:GetAttribute(OWNED) == true and existing:GetAttribute("Ready") == true, "Inspect conflicting preview first")
		require(script.Parent:WaitForChild("DevBayAccessGuard")).Start(existing)
		return existing
	end
	local manifest, kit = Bake.GetManifest(), Bake.Ensure()
	local center = vec(manifest.previewCenter)
	local model = Instance.new("Model"); model.Name = NAME; model.WorldPivot = CFrame.new(center)
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
		local title = text(statusHost,Enum.NormalId[item.statusFace or "Back"],item.level<=3 and "STEP ON PAD" or "DEV PARTY QUEUE",Color3.fromRGB(192,255,242),Vector2.new(1000,330))
		title.Name="QueueTitle";title.Position=UDim2.fromScale(0,.05);title.Size=UDim2.fromScale(1,.42)
		local sub=title:Clone();sub.Name="QueueSubtitle";sub.Position=UDim2.fromScale(0,.5);sub.Size=UDim2.fromScale(1,.4)
		sub.Text=item.level<=3 and "CHOOSE 1–6 PLAYERS" or "CHOOSE 1–6 · DEV ACCESS";sub.Parent=title.Parent
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
	local notice=manifest.notice
	if notice then
		local host=part(signs,"Mounted Revision Notice",vec(notice.size),CFrame.new(center+vec(notice.position))*CFrame.Angles(0,notice.yaw,0),false)
		text(host,Enum.NormalId.Back,"LOBBY REVISION · DEV",Color3.fromRGB(192,244,223),Vector2.new(440,100))
	end
	assert(not workspace:FindFirstChild(NAME), "Concurrent preview appeared; refusing overwrite")
	-- Reuse the installed Blender furniture for dense reference end blockades.
	local endPiles = require(script.Parent:WaitForChild("EndBlockades")).Add(model, kit, manifest)
	local bayPolish = require(script.Parent:WaitForChild("LobbyPolishBays")).Add(model, kit, manifest)
	require(script.Parent:WaitForChild("MaterialPolish")).Apply(model)
	require(script.Parent:WaitForChild("LobbyPolishScene")).Apply(model)
	model:SetAttribute("Ready",true); model:SetAttribute("InstantiatedTriangles",manifest.instantiatedTriangles + endPiles:GetAttribute("AddedInstancedTriangles") + bayPolish:GetAttribute("AddedInstancedTriangles"))
	model.Parent = workspace
	require(script.Parent:WaitForChild("DevBayAccessGuard")).Start(model)
	return model
	end)
	if not ok then model:Destroy(); error(built) end
	return built
end
return Module
