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
		return existing
	end
	local manifest, kit = Bake.GetManifest(), Bake.Ensure()
	local center = vec(manifest.previewCenter)
	local model = Instance.new("Model"); model.Name = NAME; model.WorldPivot = CFrame.new(center)
	local ok, built = pcall(function()
	model.ModelStreamingMode = Enum.ModelStreamingMode.Atomic
	model:SetAttribute(OWNED,true); model:SetAttribute("Ready",false)
	model:SetAttribute("IsolatedDesignPreview",true); model:SetAttribute("RealLevelLaunches",false)
	model:SetAttribute("PreviewCenter",center); model:SetAttribute("BlenderSourceSHA256",manifest.sourceBlendSha256)
	local visuals = Instance.new("Folder"); visuals.Name = "BlenderVisuals"; visuals.Parent = model
	local collisions = Instance.new("Folder"); collisions.Name = "PreviewCollisions"; collisions.Parent = model
	local signs = Instance.new("Folder"); signs.Name = "LevelGateSigns"; signs.Parent = model
	local lighting = Instance.new("Folder"); lighting.Name = "PreviewLighting"; lighting.Parent = model
	local pads = Instance.new("Folder"); pads.Name = "PreviewQueuePads"; pads.Parent = model
	local function place(family, cf, parent)
		local source = assert(kit:FindFirstChild(family), "Missing Blender prefab "..family)
		local p = source:Clone(); p.CFrame = cf*source.CFrame; p.DoubleSided = true; p.Parent = parent
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
	for _, item in ipairs(manifest.colliders) do
		local collider = part(collisions,item.name,vec(item.size),CFrame.new(center+vec(item.position))*CFrame.Angles(0,item.yaw or 0,0),true)
		if item.rotation then collider.CFrame = CFrame.new(center+vec(item.position))*CFrame.Angles(table.unpack(item.rotation)) end
		if item.shape == "Cylinder" then
			collider.Shape = Enum.PartType.Cylinder; collider.Size = Vector3.new(item.size[2],item.size[1],item.size[3])
			collider.CFrame *= CFrame.Angles(0,0,math.pi/2)
		end
	end
	for _, item in ipairs(manifest.signs) do
		local gate = CFrame.new(center+vec(item.gatePosition))*CFrame.Angles(0,item.yaw,0)
		local color = item.level <= 3 and Color3.fromRGB(184,255,245) or Color3.fromRGB(255,196,101)
		local label = "LEVEL "..item.level
		local lintel = part(signs,label.." Door Header",Vector3.new(23,3.5,.04),gate*CFrame.new(0,20,1.32),false)
		text(lintel,Enum.NormalId.Back,label,color,Vector2.new(450,110))
		local blade = part(signs,label.." Projecting Arrow",Vector3.new(.80,3.1,7.1),gate*CFrame.new(-11,18.4,9.1),false)
		text(blade,Enum.NormalId.Left,"←  "..label,color,Vector2.new(650,150))
		text(blade,Enum.NormalId.Right,label.."  →",color,Vector2.new(650,150))
	end
	for _, item in ipairs(manifest.lights) do
		local lens = part(lighting,item.name,Vector3.new(.2,.2,.2),CFrame.new(center+vec(item.position)),false)
		local light = Instance.new("PointLight"); light.Name = "Preview Fill"; light.Color = item.name == "Tunnel Lamp" and Color3.fromRGB(205,214,190) or Color3.new(table.unpack(item.color))
		light.Brightness = item.brightness*(item.name == "Tunnel Lamp" and .28 or .5); light.Range = item.name == "Tunnel Lamp" and 36 or item.range
		light.Shadows = false; light.Parent = lens
	end
	-- Retain the actual purchased-icon art visually, with all interactions inert.
	local liveLobby = workspace:FindFirstChild("ServerLobby")
	local shop = liveLobby and liveLobby:FindFirstChild("ZyntraShopDisplay",true)
	if shop and shop:IsA("Model") then
		local visualShop = shop:Clone(); visualShop.Name = "Shop Artwork Reference · Noninteractive"
		visualShop:PivotTo(CFrame.new(center-Vector3.new(0,30,-760))*visualShop:GetPivot())
		for _,d in ipairs(visualShop:GetDescendants()) do
			if d:IsA("BasePart") then d.CanCollide=false;d.CanTouch=false;d.CanQuery=false end
			if d:IsA("ProximityPrompt") then d.Enabled=false end
			if d:IsA("BaseScript") then d.Enabled=false end
			for _,tag in ipairs(d:GetTags()) do d:RemoveTag(tag) end
			for key in pairs(d:GetAttributes()) do if key:find("Shop") or key:find("Focus") then d:SetAttribute(key,nil) end end
		end
		visualShop:SetAttribute("PreviewNoninteractive",true);visualShop.Parent=model
	end
	for index, item in ipairs(manifest.pads) do
		local station = Instance.new("Model"); station.Name = string.format("Level%d Preview Queue %02d",item.level,index)
		station:SetAttribute(OWNED,true); station:SetAttribute("DemoQueueActive",false); station.Parent = pads
		local base = CFrame.new(center+vec(item.position))
		station:SetAttribute("HologramBase",base)
		local ring = place("HologramRing",base,station); ring.Name = "Active Queue Ring"
		ring.Material = Enum.Material.Neon; ring.Transparency = .8; ring.CastShadow = false
		local trigger = part(station,"Queue Preview Control",Vector3.new(1,1,1),base*CFrame.new(-8,3,0),false)
		local prompt = Instance.new("ProximityPrompt"); prompt.Name = "StartQueuePreview"
		prompt.ActionText = "START QUEUE PREVIEW"; prompt.ObjectText = "VISUAL DEMO · NO LEVEL LAUNCH"
		prompt.KeyboardKeyCode = Enum.KeyCode.E; prompt.MaxActivationDistance = 10; prompt.RequiresLineOfSight = false
		prompt.HoldDuration = .2; prompt.Parent = trigger
		local statusHost = part(station,"Queue Status",Vector3.new(4,1,.05),base*CFrame.new(-8,4,0),false)
		local status = text(statusHost,Enum.NormalId.Back,"QUEUE PREVIEW · IDLE",Color3.fromRGB(157,231,216))
		for band = 1,10 do
			local wall = place("HologramBand",base*CFrame.new(0,(band-1)*.6,0),station)
			wall.Name = string.format("HologramBand%02d",band); wall.Transparency = 1; wall.CastShadow = false
			wall.Material = Enum.Material.Neon; wall:SetAttribute("HologramBandIndex",band)
			wall:SetAttribute("HologramFullSize",wall.Size); wall:SetAttribute("HologramFullCFrame",wall.CFrame)
		end
		local generation = 0
		prompt.Triggered:Connect(function(player)
			if not allowed(player) or not model.Parent then return end
			generation += 1; local token = generation
			local active = not station:GetAttribute("DemoQueueActive")
			station:SetAttribute("DemoQueueActive",active)
			prompt.ActionText = active and "CANCEL QUEUE PREVIEW" or "START QUEUE PREVIEW"
			status.Text = active and "QUEUE ACTIVE · VISUAL DEMO" or "QUEUE PREVIEW · IDLE"
			if active then task.delay(20,function()
				if token ~= generation or not station.Parent then return end
				station:SetAttribute("DemoQueueActive",false); prompt.ActionText = "START QUEUE PREVIEW"; status.Text = "QUEUE PREVIEW · IDLE"
			end) end
		end)
	end
	local plaque = part(signs,"DEV Preview Notice",Vector3.new(16,3,.1),CFrame.new(center+Vector3.new(0,10,-115)),false)
	text(plaque,Enum.NormalId.Front,"BLENDER LOBBY · DEV PREVIEW",Color3.fromRGB(171,250,229))
	text(plaque,Enum.NormalId.Back,"BLENDER LOBBY · DEV PREVIEW",Color3.fromRGB(171,250,229))
	assert(not workspace:FindFirstChild(NAME), "Concurrent preview appeared; refusing overwrite")
	model:SetAttribute("Ready",true); model:SetAttribute("InstantiatedTriangles",manifest.instantiatedTriangles)
	model.Parent = workspace
	return model
	end)
	if not ok then model:Destroy(); error(built) end
	return built
end
return Module
