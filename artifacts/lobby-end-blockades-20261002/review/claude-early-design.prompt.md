READ-ONLY EARLY DESIGN REVIEW. Use only the material in this prompt. No tools, writes or external actions. Respond within 600 words. Do not give final PASS: exact final integration and client gate candidates will follow for another review.

The owner says Roblox Studio is sole authority. Git/remote/Trello can never overwrite Studio. Root inspected fresh source and editor source in Studio and reported seven existing task mirrors unchanged; GameManager fresh hash is pending (its supplied excerpts below are explicitly prior mirror context). Scope: only make both ends of R4 tunnel feel blocked by dense chaotic, visibly interlocked abandoned 1990s furniture from wall to arch, preserve DJ console/stage/vinyl discs and room approaches, visibly luminous ceiling fixtures, and present Coming Soon barriers at L5/L6 to unauthorized users. No redesign elsewhere.

Root clarified exact access policy: preserve existing authorization lists, including ZenMeister02 (11374988579), who was explicitly authorized for Level6 preview earlier. L5 = DevAccess.IsAllowed; L6 = DevAccess.IsLevel6PreviewAllowed. Never globally narrow DevAccess or remove Zen. Ordinary R4 preview remains unchanged. Existing server queue callbacks, door-entry and post-stream checks are authority. A planned new R4DevGateController is client visual/collision presentation only: unauthorized local users see opaque Coming Soon barrier and hidden owned kiosk/entry prompt; authorized users retain current flows.

No reference image bytes are supplied in this early review. The requested reference character is a dense chaotic full-arch barricade, not decorative upright columns. Distinguish design inference from verified visual appearance. Current root proposal reuses 173 existing mesh instances, adds 176424 rendered triangles, 0 unique meshes, 34 transparent arch-following blockers at local z +/-132. North/DJ pile is behind rear rail z128.4, forepieces skip abs(x)<17. PointLight tunnel fill .35->.55, cyan lenses centered localY30.23 at lamps localX +/-11, z -130..130. No global lighting edit. Source-only review cannot prove mobile performance, walkability, visual quality, or multiplayer. Give concrete corrections or tests, ranked by materiality. Review CFrame offset compensation, collision profile, DJ clearance, fixture placement, regularity of courses versus requested chaos, and client-gate security boundaries.

Baseline source hashes (eight task mirrors plus shared DevAccess):

[
  {
    "path": "artifacts/lobby-rebuild-r4-20261001/fresh-source-after/ServerScriptService.LobbyReimaginedPreview.Builder.ModuleScript.luau",
    "bytes": 11266,
    "sha256": "a4c4313b9291e412e860f1eb106d17851d25779108f1a900f9967f83e2fb9dcd",
    "rootFreshStudioMatchReported": true
  },
  {
    "path": "artifacts/lobby-rebuild-r4-20261001/fresh-source-after/ServerScriptService.LobbyReimaginedPreview.RuntimeBake.ModuleScript.luau",
    "bytes": 12341,
    "sha256": "1f564fdde835ad89b529d9069ddf87b0ed4991636f363eacbd098cc0b342ff28",
    "rootFreshStudioMatchReported": true
  },
  {
    "path": "artifacts/lobby-rebuild-r4-20261001/fresh-source-after/ServerScriptService.LobbyReimaginedPreview.QueueBridge.ModuleScript.luau",
    "bytes": 20289,
    "sha256": "ad7752eefc2561ccda5fb92828dc71d1a2ff805a0fadca6d740c0e1b3e82d674",
    "rootFreshStudioMatchReported": true
  },
  {
    "path": "artifacts/lobby-rebuild-r4-20261001/fresh-source-after/ServerScriptService.GameManager.Script.luau",
    "bytes": 169980,
    "sha256": "7e5939fabb1d98732a5bb2138eb5b0a7106e84aa5cb71ecee147ad949649ca9c",
    "rootFreshStudioMatchReported": false
  },
  {
    "path": "artifacts/lobby-rebuild-r4-20261001/fresh-source-after/ServerScriptService.Level4V4PreviewAccess.Script.luau",
    "bytes": 12317,
    "sha256": "b4f8fe4aeada5d9eb26e2d0e538889dd7dc10d52c53e5a42f63796831f20ea40",
    "rootFreshStudioMatchReported": true
  },
  {
    "path": "artifacts/lobby-rebuild-r4-20261001/fresh-source-after/ServerScriptService.Level5PreviewAccess.Script.luau",
    "bytes": 12232,
    "sha256": "07659b8077f3dc58869113e3371b906bbead0408edbb8d84ad21d746f7ee420f",
    "rootFreshStudioMatchReported": true
  },
  {
    "path": "artifacts/lobby-rebuild-r4-20261001/fresh-source-after/ServerScriptService.Level6PreviewAccess.Script.luau",
    "bytes": 14689,
    "sha256": "bc8e8f0722f023e22f5daedffa9929d4232eef62a170d592c473a7852f48d8f3",
    "rootFreshStudioMatchReported": true
  },
  {
    "path": "artifacts/lobby-rebuild-r4-20261001/fresh-source-after/StarterPlayer.StarterPlayerScripts.RoundUI.LocalScript.luau",
    "bytes": 265744,
    "sha256": "ea0e6f929f06cffa7b8e9ffc1b93a7ede1c6a6f8ed3cddd7ffb2acb82166db3c",
    "rootFreshStudioMatchReported": true
  },
  {
    "path": "artifacts/lobby-rebuild-r4-20261001/fresh-source-after/ReplicatedStorage.DevAccess.ModuleScript.luau",
    "bytes": 1353,
    "sha256": "49b292d585f47604b84486585af39edf9915e08f3eaf7e253485769260e4b29f",
    "rootFreshStudioMatchReported": true
  }
]

SOURCE ServerScriptService.LobbyReimaginedPreview.Builder.ModuleScript.luau
```luau
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
	model:SetAttribute("Ready",true); model:SetAttribute("InstantiatedTriangles",manifest.instantiatedTriangles)
	model.Parent = workspace
	return model
	end)
	if not ok then model:Destroy(); error(built) end
	return built
end
return Module

```


SOURCE ServerScriptService.LobbyReimaginedPreview.RuntimeBake.ModuleScript.luau
```luau
-- New isolated preview only. Persist raw source; regenerate opaque content per server.
local AS = game:GetService("AssetService")
local HS = game:GetService("HttpService")
local ENC = game:GetService("EncodingService")
local SS = game:GetService("ServerStorage")
local RunService = game:GetService("RunService")
local Module = {}
local SOURCE = "LobbyReimaginedBlenderSource20261001R4"
local KIT = "LobbyReimaginedBlenderKit20261001R4"
local OWNED = "LobbyReimaginedOwned"
local session = HS:GenerateGUID(false)
local cached, cachedManifest, busy, lastError

local function sha(raw)
	local digest = ENC:ComputeBufferHash(raw, Enum.HashAlgorithm.Sha256)
	local chars = table.create(buffer.len(digest))
	for index = 0, buffer.len(digest) - 1 do chars[index+1] = string.format("%02x", buffer.readu8(digest, index)) end
	return table.concat(chars)
end

local function decode(folder)
	assert(folder and folder:IsA("Folder"), "Missing compressed preview source")
	local pieces = folder:GetChildren()
	table.sort(pieces, function(a, b) return a.Name < b.Name end)
	local text = table.create(#pieces)
	assert(#pieces > 0, "Empty preview source")
	for index, piece in ipairs(pieces) do
		assert(piece:IsA("StringValue") and piece.Name == string.format("%05d", index - 1), "Wrong source-piece order")
		text[index] = piece.Value
	end
	local compressed = ENC:Base64Decode(buffer.fromstring(table.concat(text)))
	assert(buffer.len(compressed) == folder:GetAttribute("CompressedBytes"), "Compressed source length mismatch")
	local raw = ENC:DecompressBuffer(compressed, Enum.CompressionAlgorithm.Zstd)
	assert(buffer.len(raw) == folder:GetAttribute("RawBytes") and sha(raw) == folder:GetAttribute("RawSHA256"), "Preview source hash mismatch")
	return raw
end

function Module.GetManifest()
	assert(not RunService:IsClient(), "Preview bake is server-only")
	if cachedManifest then return cachedManifest end
	assert(game.PlaceId == 131311258779917 and game.GameId == 10559217407 and game.CreatorId == 1039373905, "Wrong preview place/owner")
	local source = assert(SS:FindFirstChild(SOURCE), "Preview raw source not installed")
	assert(source:GetAttribute(OWNED) == true and source:GetAttribute("Ready") == true, "Incomplete/unowned preview source")
	local raw = decode(source:FindFirstChild("ManifestJSON"))
	assert(sha(raw) == source:GetAttribute("ManifestSHA256"), "Wrong preview manifest")
	local manifest = HS:JSONDecode(buffer.tostring(raw))
	assert(manifest.schema == "lobby-reimagined-blender-v2", "Wrong preview schema")
	assert((manifest.placeId == nil or manifest.placeId == game.PlaceId)
		and (manifest.groupId == nil or manifest.groupId == game.CreatorId), "Wrong manifest owner")
	assert(manifest.atlas.width == 1024 and manifest.atlas.height == 1024 and #manifest.chunks > 0, "Incomplete preview manifest")
	cachedManifest = manifest
	return manifest
end

local function bakeContent(editable)
	local ok, result, content = pcall(AS.CreateDataModelContentAsync, AS, Content.fromObject(editable))
	editable:Destroy()
	assert(ok and result == Enum.CreateContentResult.Success, "Preview content bake failed: " .. tostring(result))
	return content
end

local function mesh(raw, chunk)
	assert(buffer.len(raw) == chunk.bytes and sha(raw) == chunk.sha256, "Wrong prefab hash: " .. chunk.name)
	assert(buffer.len(raw) >= 20 and buffer.readu32(raw, 0) == 0x364D564C, "Wrong mesh schema")
	local nv, nn, nu, nf = buffer.readu32(raw, 4), buffer.readu32(raw, 8), buffer.readu32(raw, 12), buffer.readu32(raw, 16)
	assert(nv > 0 and nv <= 60000 and nn > 0 and nn <= 60000 and nu > 0 and nu <= 60000 and nf > 0 and nf <= 20000, "Invalid mesh budget")
	assert(nf == chunk.triangles and buffer.len(raw) == 20+nv*12+nn*12+nu*8+nf*36, "Incomplete mesh")
	local editable = assert(AS:CreateEditableMesh(), "EditableMesh budget unavailable")
	local ok, why = pcall(function()
		local vertices, normals, uvs = {}, {}, {}
		local offset = 20
		for index = 1, nv do
			vertices[index] = editable:AddVertex(Vector3.new(buffer.readf32(raw, offset), buffer.readf32(raw, offset+4), buffer.readf32(raw, offset+8)))
			offset += 12
		end
		for index = 1, nn do
			normals[index] = editable:AddNormal(Vector3.new(buffer.readf32(raw, offset), buffer.readf32(raw, offset+4), buffer.readf32(raw, offset+8)))
			offset += 12
		end
		for index = 1, nu do
			uvs[index] = editable:AddUV(Vector2.new(buffer.readf32(raw, offset), 1-buffer.readf32(raw, offset+4)))
			offset += 8
		end
		for index = 1, nf do
			local v, n, u = {}, {}, {}
			for corner = 1, 3 do
				v[corner] = assert(vertices[buffer.readu32(raw, offset)+1], "Invalid vertex index")
				n[corner] = assert(normals[buffer.readu32(raw, offset+4)+1], "Invalid normal index")
				u[corner] = assert(uvs[buffer.readu32(raw, offset+8)+1], "Invalid UV index")
				offset += 12
			end
			local face = editable:AddTriangle(v[1], v[2], v[3])
			editable:SetFaceNormals(face, n); editable:SetFaceUVs(face, u)
			if index % 1000 == 0 then task.wait() end
		end
	end)
	if not ok then editable:Destroy(); error(why) end
	return bakeContent(editable)
end

function Module.Ensure()
	assert(not RunService:IsClient(), "Preview bake is server-only")
	if cached and cached.Parent == SS then return cached end
	local deadline = time()+240
	while busy and time() < deadline do task.wait(.1) end
	if cached and cached.Parent == SS then return cached end
	assert(not busy, "Preview kit busy timeout")
	assert(not SS:FindFirstChild(KIT), "Existing session kit must be inspected; opaque content must not be saved as deployment data")
	local manifest = Module.GetManifest()
	local source = assert(SS:FindFirstChild(SOURCE))
	busy = true
	local started = time()
	local folder = Instance.new("Folder"); folder.Name = KIT
	folder:SetAttribute(OWNED, true); folder:SetAttribute("Ready", false)
	local image
	local ok, why = pcall(function()
		local pixels = decode(source:FindFirstChild("AtlasPixels"))
		assert(buffer.len(pixels) == 1024*1024*4, "Incomplete RGBA atlas")
		image = assert(AS:CreateEditableImage({Size = Vector2.new(1024, 1024)}), "EditableImage atlas budget unavailable")
		-- Blender image pixels are bottom-up; EditableImage rows are top-down.
		-- UV V is already inverted by the importer; transpose rows exactly once.
		local topDown = buffer.create(buffer.len(pixels))
		for row = 0,1023 do buffer.copy(topDown,row*4096,pixels,(1023-row)*4096,4096) end
		image:WritePixelsBuffer(Vector2.zero, image.Size, topDown)
		local atlasContent = bakeContent(image); image = nil
        -- Static published PBR templates are authored in Edit before publication.
        -- Clone shared asset references; never allocate PBR EditableImages on server.
        local appearanceTemplates=Instance.new("Folder")
        appearanceTemplates.Name="PBRMaterials";appearanceTemplates.Parent=folder
        local storedTemplates=assert(source:FindFirstChild("StaticPBRMaterials"),"Missing published PBR templates")
        assert(storedTemplates:IsA("Folder") and storedTemplates:GetAttribute(OWNED)==true,"Unowned PBR templates")
        local expectedMaterials={tunnel_concrete=true,asphalt_road=true,sidewalk_concrete=true}
        local materialNames={}
        for key in pairs(manifest.materials) do
            assert(expectedMaterials[key],"Unexpected PBR material "..tostring(key))
            table.insert(materialNames,key)
        end
        assert(#materialNames==3 and #storedTemplates:GetChildren()==3,"Exactly three PBR templates required")
        table.sort(materialNames)
        local mapProperties={color="ColorMapContent",normal="NormalMapContent",roughness="RoughnessMapContent"}
        local appearances={}
        for _,key in ipairs(materialNames) do
            local spec=manifest.materials[key]
            local template=assert(storedTemplates:FindFirstChild(key),"Missing published PBR template "..key)
            assert(template:IsA("SurfaceAppearance") and template:GetAttribute(OWNED)==true,"Invalid PBR template "..key)
            assert(template.AlphaMode==Enum.AlphaMode.Overlay and template.Color==Color3.new(1,1,1),"Unexpected PBR tint/alpha "..key)
            assert(spec.maps.normal.normalConvention=="OpenGL","Unsupported PBR normal convention")
            for _,role in ipairs({"color","normal","roughness"}) do
                local info=assert(spec.maps[role],"Missing PBR manifest map "..role)
                local id=info.assetId
                assert(type(id)=="string" and string.match(id,"^[1-9]%d*$"),"Missing published PBR asset ID "..key.."/"..role)
                -- Content properties are readable at runtime; legacy string map
                -- properties require plugin security and are deliberately avoided.
                local content=template[mapProperties[role]]
                assert(typeof(content)=="Content" and content.SourceType==Enum.ContentSourceType.Uri
                    and content.Uri=="rbxassetid://"..id,"PBR template asset mismatch "..key.."/"..role)
            end
            assert(template.MetalnessMapContent.SourceType==Enum.ContentSourceType.None,"Concrete must be dielectric")
            local appearance=template:Clone();appearance.Parent=appearanceTemplates
            appearances[key]=appearance
        end
        local counts={};for _,chunk in ipairs(manifest.chunks) do counts[chunk.family]=(counts[chunk.family] or 0)+1 end
        local families,triangles={},0
        local meshes=assert(source:FindFirstChild("Meshes"))
        for index,chunk in ipairs(manifest.chunks) do
            assert(chunk.id==index-1,"Unordered prefab chunks")
            local family=chunk.family;assert(type(family)=="string","Invalid prefab family")
            local container=folder
            if counts[family]>1 then
                if not families[family] then
                    local model=Instance.new("Model");model.Name=family;model.WorldPivot=CFrame.identity;model:SetAttribute(OWNED,true);model.Parent=folder;families[family]=model
                end
                container=families[family]
            else assert(not families[family],"Duplicate single-mesh family") end
            local content=mesh(decode(meshes:FindFirstChild(tostring(chunk.id))),chunk)
            local part=AS:CreateMeshPartAsync(content,{CollisionFidelity=Enum.CollisionFidelity.Box,RenderFidelity=Enum.RenderFidelity.Precise})
            part.Parent=container
            part.Name=counts[family]>1 and chunk.name or family
            part.Size=Vector3.new(table.unpack(chunk.size));part.CFrame=CFrame.new(table.unpack(chunk.center));part.Anchored=true
            part.CanCollide=false;part.CanTouch=false;part.CanQuery=false
            part.Material=Enum.Material.SmoothPlastic;part.Color=Color3.new(1,1,1)
            if chunk.materialKey=="atlas" then part.TextureContent=atlasContent
            elseif chunk.colorAssetId then
                assert(string.match(chunk.colorAssetId,"^%d+$"),"Invalid original color map asset")
                part.TextureContent=Content.fromAssetId(tonumber(chunk.colorAssetId))
            else
                local appearance=assert(appearances[chunk.materialKey],"Unknown PBR map family")
                appearance:Clone().Parent=part
                part:SetAttribute("LobbyR4PBRMaterial",chunk.materialKey)
            end
            part:SetAttribute(OWNED,true);part:SetAttribute("BlenderSourceSHA256",chunk.sha256);part:SetAttribute("BlenderTriangles",chunk.triangles)
            if counts[family]==1 then families[family]=part end
            triangles+=chunk.triangles;folder:SetAttribute("BakedCount",index);task.wait()
        end

		assert(not SS:FindFirstChild(KIT), "Concurrent preview kit appeared")
		folder:SetAttribute("UniqueTriangles", triangles); folder:SetAttribute("BakeSeconds", time()-started)
		folder:SetAttribute("ManifestSHA256", source:GetAttribute("ManifestSHA256"))
		folder:SetAttribute("SessionScoped", true); folder:SetAttribute("BakeSession", session)
		folder:SetAttribute("Ready", true); folder.Parent = SS; cached = folder
	end)
	busy = false
	if not ok then
		if image then pcall(function() image:Destroy() end) end
		folder:Destroy(); lastError = tostring(why); error(lastError)
	end
	lastError = nil
	return cached
end

function Module.Status()
	return {Ready = cached ~= nil and cached.Parent == SS, Busy = busy == true, LastError = lastError}
end
return Module

```


SOURCE ServerScriptService.LobbyReimaginedPreview.QueueBridge.ModuleScript.luau
```luau
-- R3 adapter only. GameManager retains all admission, countdown and launch logic.
local Bridge = {}
local NAME = "LobbyReimaginedPreview"
local FIRST_ID, COUNT = 101, 24

function Bridge.IsLobby(model)
	return typeof(model) == "Instance" and model:IsA("Model") and model.Name == NAME
		and model.Parent == workspace and model:GetAttribute("LobbyReimaginedOwned") == true
		and model:GetAttribute("R3QueueRevision") == 3 and model:GetAttribute("Ready") == true
end

function Bridge.Build(model)
	assert(Bridge.IsLobby(model), "R3 queue model is not ready/owned")
	local found, result = {}, {}
	for _, zone in ipairs(model:GetDescendants()) do
		local id = zone:GetAttribute("R3QueueId")
		if id ~= nil then
			assert(zone:IsA("BasePart") and type(id) == "number" and id % 1 == 0
				and id >= FIRST_ID and id < FIRST_ID + COUNT, "Invalid R3 queue zone/id")
			assert(not found[id], "Duplicate R3 queue id")
			local ordinal = id - FIRST_ID
			local level, displayIndex = math.floor(ordinal / 4) + 1, ordinal % 4 + 1
			assert(zone:GetAttribute("LevelNumber") == level
				and zone:GetAttribute("QueueDisplayIndex") == displayIndex, "R3 queue metadata mismatch")
			assert(zone.Anchored and not zone.CanCollide and not zone.CanTouch and not zone.CanQuery,
				"Queue detector must be anchored/nonphysical")
			local radius = zone:GetAttribute("QueueRadius")
			-- Part.Size is float32; Number attributes retain the double radius.
			assert(zone:GetAttribute("QueueDetectorShape") == "Circle" and type(radius) == "number"
				and radius == radius and radius > 0 and radius < math.huge
				and radius <= math.min(zone.Size.X, zone.Size.Z) * .5 + 1e-4, "Invalid circular detector")
			local bay = zone.Parent
			local floor = bay and bay:FindFirstChild("ChamberFloor")
			local diameter = bay and bay:GetAttribute("CircularBayDiameter")
			assert(bay and bay:IsA("Model") and floor and floor:IsA("BasePart")
				and type(diameter) == "number" and diameter > radius * 2,
				"Queue zone requires direct bay parent, ChamberFloor and diameter")
			local ownerRef = zone:FindFirstChild("QueueRenderOwner")
			local owner = ownerRef and ownerRef:IsA("ObjectValue") and ownerRef.Value
			assert(owner and owner:IsA("Model") and owner:IsDescendantOf(model), "Missing queue render owner")
			local title, sub = owner:FindFirstChild("QueueTitle", true), owner:FindFirstChild("QueueSubtitle", true)
			assert(title and title:IsA("TextLabel") and sub and sub:IsA("TextLabel"), "Missing queue text labels")
			found[id] = {index = id, displayIndex = displayIndex, level = level,
				zone = zone, title = title, sub = sub, color = zone.Color, busy = false,
				revisionOwned = true, lobbyOwner = model, renderOwner = owner, previewOnly = level > 3, previewQueue = level > 3}
		end
	end
	for id = FIRST_ID, FIRST_ID + COUNT - 1 do
		assert(found[id], "Missing R3 queue id " .. id)
		table.insert(result, found[id])
	end
	return result
end

-- Called by existing DEV preview handlers before AND after their streaming yield.
-- This does not replace their allowlist, living-avatar, reach, cooldown or floor checks.
function Bridge.IsPreviewEntry(part, level)
	if typeof(part) ~= "Instance" or not part:IsA("BasePart") or level < 4 or level > 6 then return false end
	local model = workspace:FindFirstChild(NAME)
	return Bridge.IsLobby(model) and part:IsDescendantOf(model)
		and part:GetAttribute("R3DeveloperPreviewEntry") == level
end

function Bridge.GetPreviewEntries(model, level)
	local result = {}
	if not Bridge.IsLobby(model) then return result end
	for _, part in ipairs(model:GetDescendants()) do
		if Bridge.IsPreviewEntry(part, level) then table.insert(result, part) end
	end
	return result
end

-- R4 uses the existing queue engine for DEV cohorts without changing campaign
-- routing. Only these exact active server controllers can register launchers.
local Players = game:GetService("Players")
local RunService = game:GetService("RunService")
local EXPECTED_CONTROLLERS = {
    [4] = "Level4V4PreviewAccess", [5] = "Level5PreviewAccess", [6] = "Level6PreviewAccess",
}
local launchers = {}
local contexts = setmetatable({}, {__mode = "k"})
local preparations = setmetatable({}, {__mode = "k"})

function Bridge.RegisterPreviewLauncher(level, controller, callbacks)
    assert(not RunService:IsClient(), "Preview launcher registration is server-only")
    local expected = EXPECTED_CONTROLLERS[level]
    assert(expected and controller == game:GetService("ServerScriptService"):FindFirstChild(expected)
        and controller:IsA("Script"), "Wrong active preview controller")
    assert(type(callbacks) == "table" and type(callbacks.allowed) == "function"
        and type(callbacks.ready) == "function" and type(callbacks.launch) == "function",
        "Incomplete preview launcher")
    launchers[level] = {controller = controller, callbacks = callbacks}
end

local function ownedStation(station)
    if type(station) ~= "table" or station.revisionOwned ~= true or station.revisionRetired
        or not Bridge.IsLobby(station.lobbyOwner) then return false end
    local zone = station.zone
    return typeof(zone) == "Instance" and zone:IsA("BasePart")
        and zone:IsDescendantOf(station.lobbyOwner)
        and zone:GetAttribute("R3QueueId") == station.index
        and zone:GetAttribute("LevelNumber") == station.level
        and station.index >= FIRST_ID and station.index < FIRST_ID + COUNT
        and math.floor((station.index - FIRST_ID) / 4) + 1 == station.level
end

local function liveLauncher(station)
    if not ownedStation(station) or station.previewQueue ~= true then return nil end
    local record = launchers[station.level]
    return record and record.controller.Parent == game:GetService("ServerScriptService")
        and record.controller.Name == EXPECTED_CONTROLLERS[station.level] and record.callbacks or nil
end

local function livingRoot(player, character)
    if typeof(player) ~= "Instance" or not player:IsA("Player") or player.Parent ~= Players
        or player.Character ~= character or not character:IsDescendantOf(workspace)
        or player:GetAttribute("InRound") == true then return nil end
    local hum = character:FindFirstChildOfClass("Humanoid")
    local root = hum and hum.RootPart
    if not root or root.Anchored or hum.Health <= 0 or hum.SeatPart
        or hum:GetState() == Enum.HumanoidStateType.Dead then return nil end
    return root, hum
end

local function insideZone(station, root)
    local point = station.zone.CFrame:PointToObjectSpace(root.Position)
    local radius = station.zone:GetAttribute("QueueRadius")
    return type(radius) == "number" and radius > 0
        and point.X * point.X + point.Z * point.Z <= radius * radius
        and point.Y > -6 and point.Y < 12
end

function Bridge.IsPreviewPreparing(station)
    return ownedStation(station) and preparations[station] ~= nil
end

function Bridge.AllowsPreview(station, player, context)
    local callbacks = liveLauncher(station)
    if not callbacks or player:GetAttribute("Level6InRound") == true then return false end
    local previous = preparations[station]
    if previous and not previous.active then return false end
    local ok, allowed = pcall(callbacks.allowed, player, context, station)
    return ok and allowed == true
end

function Bridge.ContextOwns(context, player, station)
    local state = contexts[context]
    return state ~= nil and state.active and state.station == station
        and state.characters[player] ~= nil and state.characters[player] == player.Character
end

function Bridge.LockPreviewController(context, nextUse, locks, release)
    local state = contexts[context]
    if not state or not state.active then return false, "INVALID_PREVIEW_CONTEXT" end
    for _, player in ipairs(state.players) do
        if locks[player] or (nextUse[player] or 0) > os.clock()
            or not Bridge.ValidateQueueAdmission(context, player, state.characters[player]) then
            return false, "PREVIEW_PLAYER_BUSY"
        end
    end
    for _, player in ipairs(state.players) do locks[player]=context; nextUse[player]=math.huge end
    table.insert(state.finalizers, function()
        for _, player in ipairs(state.players) do
            if locks[player] == context then
                -- Never strand math.huge when one controller cleanup errors.
                nextUse[player] = if player.Parent == Players then os.clock()+2 else nil
                local ok, problem = pcall(release, player)
                locks[player] = nil
                if not ok then warn("[R4 Preview Queue] controller release: " .. tostring(problem)) end
            end
        end
    end)
    return true
end

local function closeContext(context, state)
    state.active = false
    -- A yielding first Runtime.Join may still need to roll back its cohort.
    -- Keep the shared E/cooldown lock until that commit task has unwound.
    if state.committing and not state.finished then contexts[context]=nil; return end
    for _, finalize in ipairs(state.finalizers) do
        local ok, problem = pcall(finalize)
        if not ok then warn("[R4 Preview Queue] finalizer: " .. tostring(problem)) end
    end
    table.clear(state.finalizers)
    contexts[context] = nil
end

function Bridge.ValidateQueueAdmission(context, player, character, requireZone)
    local state = contexts[context]
    if not state or not state.active or os.clock() > state.deadline then return nil end
    local station = state.station
    if not station.busy or station.cancelRequested or station.admissionEpoch ~= state.epoch
        or state.characters[player] ~= character or not ownedStation(station)
        or liveLauncher(station) ~= state.callbacks then return nil end
    local root, humanoid = livingRoot(player, character)
    if not root then return nil end
    -- Once committed, Runtime.Join sets Level6InRound. Admission was already
    -- checked for the whole frozen cohort; the living character is still checked.
    if requireZone ~= false then
        if not Bridge.AllowsPreview(station, player, context) or not insideZone(station, root) then return nil end
    else
        local ok, allowed = pcall(state.callbacks.allowed, player, context, station)
        if not ok or allowed ~= true then return nil end
    end
    return root, humanoid
end

local SLOT_OFFSETS = {
    Vector2.new(0,0), Vector2.new(-4.5,0), Vector2.new(4.5,0),
    Vector2.new(0,4.5), Vector2.new(-4.5,4.5), Vector2.new(4.5,4.5),
    Vector2.new(0,-4.5), Vector2.new(-4.5,-4.5), Vector2.new(4.5,-4.5),
    Vector2.new(0,9), Vector2.new(-4.5,9), Vector2.new(4.5,9),
    Vector2.new(0,-9), Vector2.new(-4.5,-9), Vector2.new(4.5,-9),
}

local function reserveLandings(context, model, exit)
    local state = contexts[context]
    if not state or not model or model.Parent ~= workspace or not exit
        or not exit:IsDescendantOf(model) then return nil, "PREVIEW_WORLD_CHANGED" end
    local look = Vector3.new(exit.CFrame.LookVector.X, 0, exit.CFrame.LookVector.Z)
    local facing = CFrame.lookAt(exit.Position, exit.Position + (if look.Magnitude > .01 then look else Vector3.zAxis))
    local ray = RaycastParams.new()
    ray.FilterType = Enum.RaycastFilterType.Include
    ray.FilterDescendantsInstances = {model}; ray.RespectCanCollide = true
    local overlap = OverlapParams.new()
    overlap.FilterType = Enum.RaycastFilterType.Include
    overlap.FilterDescendantsInstances = {model}; overlap.RespectCanCollide = true
    local chosen, entries = {}, {}
    for _, player in ipairs(state.players) do
        local character = state.characters[player]
        local root, hum = Bridge.ValidateQueueAdmission(context, player, character)
        if not root then return nil, "QUEUE_COHORT_CHANGED" end
        local selected
        for _, offset in ipairs(SLOT_OFFSETS) do
            local at = facing:PointToWorldSpace(Vector3.new(offset.X, 0, offset.Y))
            local hit = workspace:Raycast(at + Vector3.new(0,1.5,0), Vector3.new(0,-14,0), ray)
            if not hit or hit.Normal.Y < .7 or hit.Position.Y > exit.Position.Y - .75 then continue end
            local point = hit.Position + Vector3.new(0, math.max(3.5, hum.HipHeight + root.Size.Y * .5 + .2), 0)
            if (point - exit.Position).Magnitude > 16 then continue end
            local clear = true
            for _, used in ipairs(chosen) do
                if Vector3.new(point.X-used.X,0,point.Z-used.Z).Magnitude < 4.2 then clear = false; break end
            end
            if not clear then continue end
            for _, other in ipairs(Players:GetPlayers()) do
                local otherChar = other.Character
                local otherHum = otherChar and otherChar:FindFirstChildOfClass("Humanoid")
                local otherRoot = otherHum and otherHum.RootPart
                if other ~= player and otherRoot and otherHum.Health > 0
                    and (otherRoot.Position-point).Magnitude < 4.2 then clear = false; break end
            end
            if not clear then continue end
            for _, part in ipairs(workspace:GetPartBoundsInBox(CFrame.new(point), Vector3.new(3.4,5.4,3.4), overlap)) do
                if part.CanCollide then clear = false; break end
            end
            if clear then selected = point; break end
        end
        if not selected then return nil, "NO_SAFE_GROUP_ARRIVAL" end
        table.insert(chosen, selected)
        table.insert(entries, {player=player, character=character, root=root,
            previous=character:GetPivot(), frame=CFrame.lookAt(selected, selected+facing.LookVector)})
    end
    return entries
end

function Bridge.PreparePreviewGroup(context, model, exit, stream)
    local state = contexts[context]
    if not state or type(stream) ~= "function" then return nil, "INVALID_PREVIEW_CONTEXT" end
    local entries, problem = reserveLandings(context, model, exit)
    if not entries then return nil, problem end
    state.destinationModel = model; state.destinationExit = exit
    local completed, succeeded = 0, {}
    for index, entry in ipairs(entries) do
        task.spawn(function()
            local ok, streamed = pcall(stream, entry.player, entry.frame.Position)
            succeeded[index] = ok and streamed == true
            completed += 1
        end)
    end
    local deadline = os.clock() + 30
    while completed < #entries and os.clock() < deadline do
        if not Bridge.ValidateQueueAdmission(context, state.players[1], state.characters[state.players[1]]) then
            return nil, "QUEUE_COHORT_CHANGED"
        end
        task.wait(.1)
    end
    if completed < #entries then return nil, "GROUP_STREAM_TIMEOUT" end
    for index in ipairs(entries) do if not succeeded[index] then return nil, "GROUP_STREAM_FAILED" end end
    local nowModel, nowExit = state.callbacks.ready()
    if nowModel ~= model or nowExit ~= exit then return nil, "PREVIEW_WORLD_CHANGED" end
    -- Recheck floor, collision clearance, living characters and zone membership
    -- after every streaming yield, before any member is moved.
    return reserveLandings(context, model, exit)
end

function Bridge.CommitPreviewGroup(context, entries, commit, rollback)
    local state = contexts[context]
    if not state or type(entries) ~= "table" or #entries ~= #state.players then return false, "INVALID_COHORT" end
    for _, entry in ipairs(entries) do
        if not Bridge.ValidateQueueAdmission(context, entry.player, entry.character) then return false, "QUEUE_COHORT_CHANGED" end
    end
    local nowModel, nowExit = state.callbacks.ready()
    if nowModel ~= state.destinationModel or nowExit ~= state.destinationExit then return false, "PREVIEW_WORLD_CHANGED" end
    state.committing = true
    local moved = {}
    local ok, problem = xpcall(function()
        -- Freeze and validate everyone first, then release the whole cohort.
        for _, entry in ipairs(entries) do
            entry.root.AssemblyLinearVelocity = Vector3.zero
            entry.root.AssemblyAngularVelocity = Vector3.zero
            entry.character:PivotTo(entry.frame)
            table.insert(moved, entry)
        end
        for _, entry in ipairs(entries) do
            if not Bridge.ValidateQueueAdmission(context, entry.player, entry.character, false) then error("QUEUE_COHORT_CHANGED") end
            entry.commitAttempted = true
            local joined, reason = commit(entry)
            if joined ~= true then error(tostring(reason or "PREVIEW_JOIN_REJECTED")) end
            -- The final/solo Join can yield too. A revoked context must still
            -- roll back after that call, even when no next member follows it.
            if not Bridge.ValidateQueueAdmission(context, entry.player, entry.character, false) then error("QUEUE_COHORT_CHANGED") end
            local readyModel, readyExit = state.callbacks.ready()
            if readyModel ~= state.destinationModel or readyExit ~= state.destinationExit then error("PREVIEW_WORLD_CHANGED") end
        end
    end, debug.traceback)
    if not ok then
        for _, entry in ipairs(moved) do
            if rollback and entry.commitAttempted then
                local rollbackOK, rollbackProblem = pcall(rollback, entry)
                if not rollbackOK then warn("[R4 Preview Queue] rollback: " .. tostring(rollbackProblem)) end
            end
            -- Respect an explicit cancel/return that has already moved a living
            -- avatar away; never pull it back from a newer destination.
            if livingRoot(entry.player, entry.character)
                and (entry.root.Position-entry.frame.Position).Magnitude <= 24 then
                entry.root.AssemblyLinearVelocity = Vector3.zero
                entry.root.AssemblyAngularVelocity = Vector3.zero
                entry.character:PivotTo(entry.previous)
            end
        end
        return false, tostring(problem)
    end
    return true
end

function Bridge.LaunchPreviewGroup(station, players)
    local callbacks = liveLauncher(station)
    if not callbacks or not station.busy or type(players) ~= "table" or #players < 1 or #players > 6 then
        return false, "PREVIEW_LAUNCHER_UNAVAILABLE"
    end
    -- An abandoned EnsureWorld must finish its own bounded cleanup. Never
    -- task.cancel it or create another waiting job for this same station.
    if preparations[station] then return false, "PREVIEW_PREPARATION_BUSY" end
    local context = {}
    local state = {active=true, station=station, callbacks=callbacks, epoch=station.admissionEpoch,
        deadline=os.clock()+1400, players={}, characters={}, finalizers={}}
    contexts[context] = state
    for _, player in ipairs(players) do
        local character = player.Character
        if state.characters[player] or not character then closeContext(context,state); return false, "INVALID_COHORT" end
        state.characters[player] = character; table.insert(state.players, player)
        if not Bridge.ValidateQueueAdmission(context, player, character) then
            closeContext(context,state); return false, "QUEUE_COHORT_CHANGED"
        end
    end
    preparations[station] = state
    local done, ok, joined, problem = false, false, false, nil
    task.spawn(function()
        ok, joined, problem = pcall(callbacks.launch, context)
        state.finished = true
        if not state.active then closeContext(context, state) end
        done = true
        if preparations[station] == state then preparations[station] = nil end
    end)
    while not done do
        local valid = true
        for _, player in ipairs(state.players) do
            if not Bridge.ValidateQueueAdmission(context, player, state.characters[player], not state.committing) then
                valid = false; break
            end
        end
        if not valid then
            closeContext(context,state)
            if state.committing then
                -- A Join already in flight owns rollback. Keep this station
                -- busy until it finishes so no new queue can replace its epoch.
                while not done do task.wait(.1) end
            end
            return false, "QUEUE_COHORT_CHANGED"
        end
        task.wait(.1)
    end
    closeContext(context,state)
    return ok and joined == true, if ok then problem else tostring(joined)
end

return Bridge

```


SOURCE ServerScriptService.GameManager.Script.luau
```luau

PRIOR MIRROR CONTEXT EXCERPT lines 1100-1175
1100:  devControlRate[player] = nil
1101:  devRespawnRequests[player] = nil
1102:  player:SetAttribute("DevPushImmune", nil)
1103: end)
1104: 
1105: local function queueRadius(station)
1106:  local zone = station.zone
1107:  if zone:GetAttribute("QueueDetectorShape") == "Circle" then
1108:   local radius = tonumber(zone:GetAttribute("QueueRadius"))
1109:   if radius and radius > 0 and radius == radius then
1110:    return math.min(radius, zone.Size.X * .5, zone.Size.Z * .5)
1111:   end
1112:  end
1113:  return nil
1114: end
1115: 
1116: -- R4-owned preview queues share the existing station engine. Production
1117: -- routing and the original lobby remain untouched.
1118: local function revisedQueueBridge()
1119:  local folder = script.Parent:FindFirstChild("LobbyReimaginedPreview")
1120:  local module = folder and folder:FindFirstChild("QueueBridge")
1121:  return module and module:IsA("ModuleScript") and require(module) or nil
1122: end
1123: 
1124: local function revisedQueueIdleSubtitle(station)
1125:  if not station.previewQueue then return "ENTER TO HOST  •  CHOOSE 1-6 PLAYERS" end
1126:  local bridge = revisedQueueBridge()
1127:  if bridge and bridge.IsPreviewPreparing and bridge.IsPreviewPreparing(station) then
1128:   return "PREPARING PREVIEW WORLD  •  PLEASE WAIT"
1129:  end
1130:  return "DEV PARTY QUEUE  •  AUTHORIZED ACCESS"
1131: end
1132: 
1133: local function playerInsideZone(player, station, includeBusy)
1134:  if station.revisionOwned and not (RunService:IsStudio() or DevAccess.IsLevel6PreviewAllowed(player)) then return false end
1135:  if station.previewQueue then
1136:   local bridge = revisedQueueBridge()
1137:   if not bridge or not bridge.AllowsPreview(station, player) then return false end
1138:  elseif station.level > Routing.MaxLevel and not canAccessLevel(station.level, {player}) then return false end
1139:  if inRound[player] or (station.busy and not includeBusy) then return false end
1140:  local char = player.Character
1141:  local hum = char and char:FindFirstChildOfClass("Humanoid")
1142:  local root = char and char:FindFirstChild("HumanoidRootPart")
1143:  if player.Parent ~= Players or not (char and char.Parent and hum and hum.Health > 0
1144:   and root and root:IsA("BasePart")) then return false end
1145:  local zone = station.zone
1146:  if not zone or not zone.Parent then return false end
1147:  local p = zone.CFrame:PointToObjectSpace(root.Position)
1148:  local radius = queueRadius(station)
1149:  local inside = if radius then p.X * p.X + p.Z * p.Z <= radius * radius
1150:   else math.abs(p.X) <= zone.Size.X * .5 and math.abs(p.Z) <= zone.Size.Z * .5
1151:  return inside and p.Y > -6 and p.Y < 12
1152: end
1153: 
1154: local function rawQueuedPlayers(station, includeBusy)
1155:  local result = {}
1156:  local insideNow = {}
1157:  station.entrySeen = station.entrySeen or {}
1158:  station.entryCharacters = station.entryCharacters or {}
1159:  for _, player in ipairs(Players:GetPlayers()) do
1160:   if playerInsideZone(player, station, includeBusy) then
1161:    insideNow[player] = true
1162:    if station.entrySeen[player] == nil or station.entryCharacters[player] ~= player.Character then
1163:     station.entrySeen[player] = os.clock()
1164:     station.entryCharacters[player] = player.Character
1165:    end
1166:    result[#result + 1] = player
1167:   end
1168:  end
1169:  for player in pairs(station.entrySeen) do
1170:   if not insideNow[player] then
1171:    station.entrySeen[player] = nil
1172:    station.entryCharacters[player] = nil
1173:   end
1174:  end
1175:  table.sort(result, function(a, b)

PRIOR MIRROR CONTEXT EXCERPT lines 3055-3105
3055:  local settled, stranded = awaitTransferSettlement(Routing.Endpoints.Loss)
3056:  if not settled then holdCompletedWorld(stranded, Routing.Endpoints.Loss) end
3057:  task.wait(1.6)
3058: end
3059: 
3060: -- Launch one station. Published servers teleport the selected group into a fresh
3061: -- reserved server. Studio cannot test TeleportService, so it runs the same party
3062: -- locally as a practical editor-only fallback.
3063: local function launchStation(station, participants)
3064:  if station.previewQueue then
3065:   local bridge = revisedQueueBridge()
3066:   if not bridge or not bridge.LaunchPreviewGroup then return end
3067:   station.busy = true
3068:   setStationDisplay(station, "STARTING DEV PREVIEW", #participants .. "/" .. (station.maxPlayers or MAX_PLAYERS_PER_STATION) .. " PLAYERS", station.color)
3069:   -- Preview controllers own their stream/entry UI; never announce a campaign
3070:   -- loadinggame or create a reserved production server for levels4-6.
3071:   fireGroup(participants, "queueconfigclosed")
3072:   local ok, joined, problem = pcall(bridge.LaunchPreviewGroup, station, participants)
3073:   if not ok or joined ~= true then
3074:    warn("[R4 Preview Queue] " .. tostring(if ok then problem else joined))
3075:    setStationDisplay(station, "PREVIEW ENTRY FAILED", "STEP OUT AND TRY AGAIN", Color3.fromRGB(255,105,95))
3076:    fireGroup(participants, "lobbycancel")
3077:    task.wait(2.5)
3078:   end
3079:   station.busy = false
3080:   return
3081:  end
3082:  if not canAccessLevel(station.level or 1, participants) then return end
3083:  station.busy = true
3084:  setStationDisplay(station, "STARTING PRIVATE WORLD", #participants .. "/" .. (station.maxPlayers or MAX_PLAYERS_PER_STATION) .. " PLAYERS", station.color)
3085:  fireGroup(participants, "loadinggame", station.level or 1)
3086: 
3087:  if IS_STUDIO then
3088:   if roundBusy then
3089:    setStationDisplay(station, "STUDIO WORLD BUSY", "WAIT FOR THE ACTIVE TEST", Color3.fromRGB(255, 210, 90))
3090:    task.wait(2)
3091:    fireGroup(participants, "lobbycancel")
3092:    station.busy = false
3093:    return
3094:   end
3095: 
3096:   roundBusy = true
3097:   local attempt = beginGroupLoading(participants)
3098:   clearGlowsticks()
3099:   assignGlowstickSlots(participants)
3100:   -- A round started from the lobby is never a continuation, whatever the last
3101:   -- one was; leaving a stale route here would skip Level 3's elevator descent.
3102:   roundEntryMode = nil
3103:   if prepareGroupLoading(attempt, participants, station.level or 1, false) then
3104:    playRound(participants)
3105:   end

PRIOR MIRROR CONTEXT EXCERPT lines 3590-3670
3590:    station.feedback = {}
3591:    launchStation(station, participants)
3592:   end
3593:   if station.revisionRetired then return end
3594:   resetStation(station, false)
3595:  end
3596: end
3597: 
3598: -- R3 parallel lobby uses the same private queue engine, never a second countdown.
3599: -- Ready owned pads101-124 share one engine;4-6 use guarded local DEV launchers.
3600: if not IS_RESERVED_ROUND_SERVER then
3601:  local r3Models = setmetatable({}, {__mode = "k"})
3602:  local function bindR3(model)
3603:   if model.Name ~= "LobbyReimaginedPreview" or not model:IsA("Model") or model.Parent ~= workspace
3604:    or model:GetAttribute("LobbyReimaginedOwned") ~= true then return end
3605:   if r3Models[model] then return end
3606:   local ownerFolder = script.Parent:FindFirstChild("LobbyReimaginedPreview")
3607:   local module = ownerFolder and ownerFolder:FindFirstChild("QueueBridge")
3608:   if not module or not module:IsA("ModuleScript") then return end
3609:   local bridge = require(module)
3610:   if not bridge.IsLobby(model) then return end
3611:   local ok, specs = pcall(bridge.Build, model)
3612:   if not ok then warn("[R3 Queue Bridge] " .. tostring(specs)); return end
3613:   local registered = {}
3614:   for _, station in ipairs(specs) do
3615:    if station.previewQueue or not station.previewOnly then
3616:     if (not station.previewQueue and station.level > Routing.MaxLevel) or lobbyStations[station.index] then
3617:      warn("[R3 Queue Bridge] conflicting or unavailable queue id " .. station.index); return
3618:     end
3619:     table.insert(registered, station)
3620:    end
3621:   end
3622:   r3Models[model] = registered
3623:   local retired = false
3624:   local ancestryConnection
3625:   local function retire()
3626:    if retired then return end
3627:    retired = true
3628:    if ancestryConnection then ancestryConnection:Disconnect() end
3629:    for _, station in ipairs(registered) do
3630:     station.revisionRetired = true
3631:     local feedback = {}
3632:     for player in pairs(station.feedback or {}) do
3633:      if player.Parent == Players and not inRound[player] then table.insert(feedback, player) end
3634:     end
3635:     fireGroup(feedback, "lobbycancel")
3636:     resetStation(station, true)
3637:     setStationBarrier(station, false)
3638:     if station.barrier then station.barrier:Destroy(); station.barrier = nil end
3639:     if lobbyStations[station.index] == station then lobbyStations[station.index] = nil end
3640:    end
3641:    r3Models[model] = nil
3642:   end
3643:   model.Destroying:Once(retire)
3644:   ancestryConnection = model.AncestryChanged:Connect(function()
3645:    if model.Parent ~= workspace then retire() end
3646:   end)
3647:   for _, station in ipairs(registered) do
3648:    lobbyStations[station.index] = station
3649:    task.spawn(function() runStation(station) end)
3650:   end
3651:   model:SetAttribute("RegisteredQueueCount", #registered)
3652:  end
3653:  local watched = setmetatable({}, {__mode = "k"})
3654:  local function watchR3(model)
3655:   if model.Name ~= "LobbyReimaginedPreview" or not model:IsA("Model") or watched[model] then return end
3656:   watched[model] = true
3657:   local readyConnection = model:GetAttributeChangedSignal("Ready"):Connect(function() bindR3(model) end)
3658:   local ancestryConnection = model.AncestryChanged:Connect(function()
3659:    if model.Parent == workspace then task.defer(bindR3, model) end
3660:   end)
3661:   model.Destroying:Once(function() readyConnection:Disconnect(); ancestryConnection:Disconnect() end)
3662:   task.defer(bindR3, model)
3663:  end
3664:  workspace.ChildAdded:Connect(watchR3)
3665:  for _, model in ipairs(workspace:GetChildren()) do watchR3(model) end
3666: end
3667: 
3668: -- Every arrival's OWN packet. Admission is decided from the session each player
3669: -- travelled under, not from whichever packet happened to be read first: an
3670: -- immediate continuer and a timed-out continuer now carry the same session id,
```


SOURCE ServerScriptService.Level4V4PreviewAccess.Script.luau
```luau
-- Developer-only entry to the already-built V4 cinema preview.
-- The prompts are UI; every teleport is authorized again on the server.
local Players = game:GetService("Players")
local DevAccess = require(game:GetService("ReplicatedStorage"):WaitForChild("DevAccess"))

-- 2026-09-30: the Blender-built cinema; the original "Level 4 Cinema Preview" model is kept untouched.
local MODEL_NAME = "Level 4 Cinema Blender"
local EXIT_NAME = "Level4V4Exit"
local ENTER_PROMPT = "Level4DeveloperPreviewPrompt"
local RETURN_PROMPT = "Level4DeveloperPreviewReturnPrompt"
local COOLDOWN = 2
local nextUse = {}
local hooked = setmetatable({}, { __mode = "k" })

local function liveDoor()
	local lobby = workspace:FindFirstChild("ServerLobby")
	local doorways = lobby and lobby:FindFirstChild("LevelDoorways")
	local door = doorways and doorways:FindFirstChild("Level4SealedDoor")
	return door and door:IsA("BasePart") and door or nil
end

-- R3 additional hosts retain this controller's existing access/stream/launch path.
local function r3Bridge()
 local folder = script.Parent:FindFirstChild("LobbyReimaginedPreview")
 local module = folder and folder:FindFirstChild("QueueBridge")
 return module and module:IsA("ModuleScript") and require(module) or nil
end
local function isR3Entry(door)
 local bridge = r3Bridge()
 return bridge and bridge.IsPreviewEntry(door, 4) or false
end
local r3Inflight = setmetatable({}, {__mode = "k"})
local function beginR3Entry(door)
 if not isR3Entry(door) then return nil end
 local ref = door:FindFirstChild("QueueRenderOwner")
 local owner = ref and ref:IsA("ObjectValue") and ref.Value
 if not owner or not owner:IsA("Model") or not owner:IsDescendantOf(door:FindFirstAncestor("LobbyReimaginedPreview")) then return nil end
 r3Inflight[owner] = (r3Inflight[owner] or 0) + 1
 owner:SetAttribute("QueueActive", true)
 return owner
end
local function finishR3Entry(owner)
 if not owner then return end
 local count = math.max(0, (r3Inflight[owner] or 1) - 1)
 r3Inflight[owner] = count > 0 and count or nil
 if owner.Parent then owner:SetAttribute("QueueActive", count > 0) end
end

local function liveSpawn()
	local lobby = workspace:FindFirstChild("ServerLobby")
	local spawn = lobby and lobby:FindFirstChild("LobbySpawn")
	return spawn and spawn:IsA("BasePart") and spawn or nil
end

local function readyPreview()
	local model = workspace:FindFirstChild(MODEL_NAME)
	if not (model and model:IsA("Model") and model:GetAttribute("Level4Preview") == true
		and model:GetAttribute("PreviewOnly") == true
		and model:GetAttribute("Level4LayoutVersion") == 4
		and model:GetAttribute("Level4PreviewReady") == true) then return nil end
	local exit = model:FindFirstChild(EXIT_NAME, true)
	if not (exit and exit:IsA("BasePart") and exit:IsDescendantOf(model)) then return nil end
	return model, exit
end

local function readyPlayer(player)
	if player.Parent ~= Players or not DevAccess.IsAllowed(player)
		or player:GetAttribute("InRound") == true
		or workspace:GetAttribute("ReservedRoundServer") == true then return nil end
	local character = player.Character
	local humanoid = character and character:FindFirstChildOfClass("Humanoid")
	local root = humanoid and humanoid.RootPart
	if not root or not character:IsDescendantOf(workspace) or root.Anchored or humanoid.SeatPart
		or humanoid.Health <= 0 or humanoid:GetState() == Enum.HumanoidStateType.Dead then return nil end
	return character, root
end

local function upright(position, look)
	local flat = Vector3.new(look.X, 0, look.Z)
	return CFrame.lookAt(position, position + (if flat.Magnitude > 0.01 then flat else Vector3.zAxis))
end

local function stream(player, position)
	local ok, err = pcall(function() player:RequestStreamAroundAsync(position, 8) end)
	if not ok then warn("[Level4V4PreviewAccess] streaming failed:", err) end
	return ok
end

local function release(player)
	nextUse[player] = if player.Parent == Players then os.clock() + COOLDOWN else nil
end

local function hasFloor(model, exit)
	local params = RaycastParams.new()
	params.FilterType = Enum.RaycastFilterType.Include
	params.FilterDescendantsInstances = { model }
	params.RespectCanCollide = true
	local hit = workspace:Raycast(exit.Position, Vector3.new(0, -8, 0), params)
	return hit ~= nil and hit.Normal.Y > 0.7
end

local function onReturn(player, prompt)
	if (nextUse[player] or 0) > os.clock() then return end
	local character, root = readyPlayer(player)
	local model, exit = readyPreview()
	if not character or not model or not exit or prompt.Parent ~= exit
		or (root.Position - exit.Position).Magnitude > 12 then return end
	local spawn = liveSpawn()
	if not spawn then return end
	nextUse[player] = math.huge
	local ok, err = pcall(function()
		if not stream(player, spawn.Position) then return end
		local nowCharacter, nowRoot = readyPlayer(player)
		local nowModel, nowExit = readyPreview()
		spawn = liveSpawn()
		if nowCharacter ~= character or nowModel ~= model or nowExit ~= exit or not spawn
			or prompt.Parent ~= exit or (nowRoot.Position - exit.Position).Magnitude > 12 then return end
		character:PivotTo(upright(spawn.Position + Vector3.new(0, 4, 0), spawn.CFrame.LookVector))
	end)
	release(player)
	if not ok then warn("[Level4V4PreviewAccess] return failed:", err) end
end

local function onEnter(player, prompt)
	if (nextUse[player] or 0) > os.clock() then return end
	local character, root = readyPlayer(player)
	local door = prompt.Parent
	if not character or not door or not door:IsA("BasePart")
  or not (door == liveDoor() or isR3Entry(door)) or (root.Position - door.Position).Magnitude > 14 then return end
	local model, exit = readyPreview()
	local returnPrompt = exit and exit:FindFirstChild(RETURN_PROMPT)
	if not model or not returnPrompt or not returnPrompt:IsA("ProximityPrompt")
		or not returnPrompt.Enabled or not hasFloor(model, exit) then
		warn("[Level4V4PreviewAccess] ready V4 preview, return prompt or landing floor is missing")
		return
	end
	nextUse[player] = math.huge
 local r3Owner = beginR3Entry(door)
	local ok, err = pcall(function()
		if not stream(player, exit.Position) then return end
		local nowCharacter, nowRoot = readyPlayer(player)
		local nowModel, nowExit = readyPreview()
		if nowCharacter ~= character or nowModel ~= model or nowExit ~= exit
			or prompt.Parent ~= door or not (door == liveDoor() or isR3Entry(door))
			or (nowRoot.Position - door.Position).Magnitude > 14
			or returnPrompt.Parent ~= exit or not returnPrompt.Enabled
			or not hasFloor(model, exit) then return end
		character:PivotTo(upright(exit.Position, exit.CFrame.LookVector))
	end)
 finishR3Entry(r3Owner)
	release(player)
	if not ok then warn("[Level4V4PreviewAccess] entry failed:", err) end
end

local function ensurePrompt(parent, name, action, object, callback)
	local prompt = parent:FindFirstChild(name)
	if not prompt then
		prompt = Instance.new("ProximityPrompt")
		prompt.Name = name
		prompt.ActionText = action
		prompt.ObjectText = object
		prompt.HoldDuration = 0.5
		prompt.MaxActivationDistance = 10
		prompt.RequiresLineOfSight = false
		prompt.Parent = parent
	end
	if not prompt:IsA("ProximityPrompt") then return end
	if not hooked[prompt] then
		hooked[prompt] = true
		prompt.Triggered:Connect(function(player) callback(player, prompt) end)
	end
end

-- R4 queue cohorts use the same existing authorized preview/floor/stream
-- helpers as the original E entry. Original door prompts are unchanged.
do
 local bridge = r3Bridge()
 if bridge and bridge.RegisterPreviewLauncher then
  local queueLocks = {}
  local registered, registrationProblem = pcall(bridge.RegisterPreviewLauncher, 4, script, {
   allowed = function(player, _, station)
    local lock = queueLocks[player]
    return (if lock then bridge.ContextOwns(lock, player, station) else (nextUse[player] or 0) <= os.clock())
     and readyPlayer(player) ~= nil
   end,
   ready = function()
    local model, exit = readyPreview()
    local prompt = exit and exit:FindFirstChild(RETURN_PROMPT)
    if not model or not prompt or not prompt:IsA("ProximityPrompt") or not prompt.Enabled
     or not hasFloor(model, exit) then return nil end
    return model, exit
   end,
   launch = function(context)
    local locked, reason = bridge.LockPreviewController(context, nextUse, queueLocks, release)
    if not locked then return false, reason end
    local model, exit = readyPreview()
    local returnPrompt = exit and exit:FindFirstChild(RETURN_PROMPT)
    if not model or not returnPrompt or not returnPrompt:IsA("ProximityPrompt")
     or not returnPrompt.Enabled or not hasFloor(model, exit) then return false, "PREVIEW_NOT_READY" end
    local entries, problem = bridge.PreparePreviewGroup(context, model, exit, stream)
    if not entries then return false, problem end
    return bridge.CommitPreviewGroup(context, entries, function() return true end)
   end,
  })
  if not registered then warn("[R4 Preview Queue] registration: " .. tostring(registrationProblem)) end
 end
end

local function hookDoor()
	local door = liveDoor()
	if door then ensurePrompt(door, ENTER_PROMPT, "ENTER LEVEL 4 PREVIEW", "DEVELOPER PREVIEW", onEnter) end
 local bridge = r3Bridge()
 local model = workspace:FindFirstChild("LobbyReimaginedPreview")
 if bridge then
  for _, host in ipairs(bridge.GetPreviewEntries(model, 4)) do
   ensurePrompt(host, ENTER_PROMPT, "ENTER LEVEL 4 PREVIEW", "DEVELOPER PREVIEW", onEnter)
  end
 end
end

local function hookExit()
	local _, exit = readyPreview()
	if exit then ensurePrompt(exit, RETURN_PROMPT, "RETURN TO LOBBY", "LEVEL 4 DEVELOPER PREVIEW", onReturn) end
end

local watchedModel, readyConnection
local function watchPreview(model)
	if watchedModel ~= model then
		if readyConnection then readyConnection:Disconnect() end
		watchedModel = model
		readyConnection = model and model:GetAttributeChangedSignal("Level4PreviewReady"):Connect(hookExit) or nil
	end
	hookExit()
end

Players.PlayerRemoving:Connect(function(player) nextUse[player] = nil end)
workspace.DescendantAdded:Connect(function(instance)
	local name = instance.Name
	if name == "ServerLobby" or name == "LevelDoorways" or name == "Level4SealedDoor" then
		hookDoor()
	elseif name == MODEL_NAME and instance.Parent == workspace and instance:IsA("Model") then
		watchPreview(instance)
	elseif name == EXIT_NAME then
		hookExit()
	end
end)
hookDoor()
watchPreview(workspace:FindFirstChild(MODEL_NAME))

-- Preserve the existing preview's developer-only physical boundary during the V4 swap.
task.spawn(function()
	local boundedModel, bounds, half
	while task.wait(0.5) do
		local model = readyPreview()
		local spawn = liveSpawn()
		if model and spawn then
			if boundedModel ~= model then
				local size
				bounds, size = model:GetBoundingBox()
				half = size * 0.5 + Vector3.new(8, 20, 8)
				boundedModel = model
			end
			for _, player in ipairs(Players:GetPlayers()) do
				if not DevAccess.IsAllowed(player) then
					local character = player.Character
					local humanoid = character and character:FindFirstChildOfClass("Humanoid")
					local root = humanoid and humanoid.RootPart
					if root and humanoid.Health > 0 then
						local p = bounds:PointToObjectSpace(root.Position)
						if math.abs(p.X) <= half.X and math.abs(p.Y) <= half.Y and math.abs(p.Z) <= half.Z then
							character:PivotTo(upright(spawn.Position + Vector3.new(0, 4, 0), spawn.CFrame.LookVector))
						end
					end
				end
			end
		end
	end
end)

-- Observe ready publication/restoration; the original lobby watcher is unchanged.
local r3Watched = setmetatable({}, {__mode = "k"})
local function watchR3Lobby(model)
 if not model or not model:IsA("Model") or model.Name ~= "LobbyReimaginedPreview" or r3Watched[model] then return end
 r3Watched[model] = true
 local ready = model:GetAttributeChangedSignal("Ready"):Connect(hookDoor)
 local ancestry = model.AncestryChanged:Connect(function() if model.Parent == workspace then task.defer(hookDoor) end end)
 local descendants = model.DescendantAdded:Connect(function(part)
  if part:GetAttribute("R3DeveloperPreviewEntry") == 4 then task.defer(hookDoor) end
 end)
 model.Destroying:Once(function() ready:Disconnect(); ancestry:Disconnect(); descendants:Disconnect() end)
 task.defer(hookDoor)
end
workspace.ChildAdded:Connect(watchR3Lobby)
watchR3Lobby(workspace:FindFirstChild("LobbyReimaginedPreview"))

```


SOURCE ServerScriptService.Level5PreviewAccess.Script.luau
```luau
-- Developer-only entry to the imported Level 5 Quiet Suburbs preview; same
-- door/exit/return method as Level4V4PreviewAccess (the cinema).
-- The prompts are UI; every teleport is authorized again on the server.
local Players = game:GetService("Players")
local DevAccess = require(game:GetService("ReplicatedStorage"):WaitForChild("DevAccess"))

local MODEL_NAME = "Level 5 Quiet Suburbs"
local EXIT_NAME = "Level5Exit"
local ENTER_PROMPT = "Level5DeveloperPreviewPrompt"
local RETURN_PROMPT = "Level5DeveloperPreviewReturnPrompt"
local COOLDOWN = 2
local nextUse = {}
local hooked = setmetatable({}, { __mode = "k" })

local function liveDoor()
	local lobby = workspace:FindFirstChild("ServerLobby")
	local doorways = lobby and lobby:FindFirstChild("LevelDoorways")
	local door = doorways and doorways:FindFirstChild("Level5SealedDoor")
	return door and door:IsA("BasePart") and door or nil
end

-- R3 additional hosts retain this controller's existing access/stream/launch path.
local function r3Bridge()
 local folder = script.Parent:FindFirstChild("LobbyReimaginedPreview")
 local module = folder and folder:FindFirstChild("QueueBridge")
 return module and module:IsA("ModuleScript") and require(module) or nil
end
local function isR3Entry(door)
 local bridge = r3Bridge()
 return bridge and bridge.IsPreviewEntry(door, 5) or false
end
local r3Inflight = setmetatable({}, {__mode = "k"})
local function beginR3Entry(door)
 if not isR3Entry(door) then return nil end
 local ref = door:FindFirstChild("QueueRenderOwner")
 local owner = ref and ref:IsA("ObjectValue") and ref.Value
 if not owner or not owner:IsA("Model") or not owner:IsDescendantOf(door:FindFirstAncestor("LobbyReimaginedPreview")) then return nil end
 r3Inflight[owner] = (r3Inflight[owner] or 0) + 1
 owner:SetAttribute("QueueActive", true)
 return owner
end
local function finishR3Entry(owner)
 if not owner then return end
 local count = math.max(0, (r3Inflight[owner] or 1) - 1)
 r3Inflight[owner] = count > 0 and count or nil
 if owner.Parent then owner:SetAttribute("QueueActive", count > 0) end
end

local function liveSpawn()
	local lobby = workspace:FindFirstChild("ServerLobby")
	local spawn = lobby and lobby:FindFirstChild("LobbySpawn")
	return spawn and spawn:IsA("BasePart") and spawn or nil
end

local function readyPreview()
	local model = workspace:FindFirstChild(MODEL_NAME)
	if not (model and model:IsA("Model") and model:GetAttribute("Level5Preview") == true
		and model:GetAttribute("PreviewOnly") == true
		and model:GetAttribute("Level5PreviewReady") == true) then return nil end
	local exit = model:FindFirstChild(EXIT_NAME, true)
	if not (exit and exit:IsA("BasePart") and exit:IsDescendantOf(model)) then return nil end
	return model, exit
end

local function readyPlayer(player)
	if player.Parent ~= Players or not DevAccess.IsAllowed(player)
		or player:GetAttribute("InRound") == true
		or workspace:GetAttribute("ReservedRoundServer") == true then return nil end
	local character = player.Character
	local humanoid = character and character:FindFirstChildOfClass("Humanoid")
	local root = humanoid and humanoid.RootPart
	if not root or not character:IsDescendantOf(workspace) or root.Anchored or humanoid.SeatPart
		or humanoid.Health <= 0 or humanoid:GetState() == Enum.HumanoidStateType.Dead then return nil end
	return character, root
end

local function upright(position, look)
	local flat = Vector3.new(look.X, 0, look.Z)
	return CFrame.lookAt(position, position + (if flat.Magnitude > 0.01 then flat else Vector3.zAxis))
end

local function stream(player, position)
	local ok, err = pcall(function() player:RequestStreamAroundAsync(position, 8) end)
	if not ok then warn("[Level5PreviewAccess] streaming failed:", err) end
	return ok
end

local function release(player)
	nextUse[player] = if player.Parent == Players then os.clock() + COOLDOWN else nil
end

local function hasFloor(model, exit)
	local params = RaycastParams.new()
	params.FilterType = Enum.RaycastFilterType.Include
	params.FilterDescendantsInstances = { model }
	params.RespectCanCollide = true
	local hit = workspace:Raycast(exit.Position, Vector3.new(0, -8, 0), params)
	return hit ~= nil and hit.Normal.Y > 0.7
end

local function onReturn(player, prompt)
	if (nextUse[player] or 0) > os.clock() then return end
	local character, root = readyPlayer(player)
	local model, exit = readyPreview()
	if not character or not model or not exit or prompt.Parent ~= exit
		or (root.Position - exit.Position).Magnitude > 12 then return end
	local spawn = liveSpawn()
	if not spawn then return end
	nextUse[player] = math.huge
	local ok, err = pcall(function()
		if not stream(player, spawn.Position) then return end
		local nowCharacter, nowRoot = readyPlayer(player)
		local nowModel, nowExit = readyPreview()
		spawn = liveSpawn()
		if nowCharacter ~= character or nowModel ~= model or nowExit ~= exit or not spawn
			or prompt.Parent ~= exit or (nowRoot.Position - exit.Position).Magnitude > 12 then return end
		character:PivotTo(upright(spawn.Position + Vector3.new(0, 4, 0), spawn.CFrame.LookVector))
	end)
	release(player)
	if not ok then warn("[Level5PreviewAccess] return failed:", err) end
end

local function onEnter(player, prompt)
	if (nextUse[player] or 0) > os.clock() then return end
	local character, root = readyPlayer(player)
	local door = prompt.Parent
	if not character or not door or not door:IsA("BasePart")
  or not (door == liveDoor() or isR3Entry(door)) or (root.Position - door.Position).Magnitude > 14 then return end
	local model, exit = readyPreview()
	local returnPrompt = exit and exit:FindFirstChild(RETURN_PROMPT)
	if not model or not returnPrompt or not returnPrompt:IsA("ProximityPrompt")
		or not returnPrompt.Enabled or not hasFloor(model, exit) then
		warn("[Level5PreviewAccess] ready preview, return prompt or landing floor is missing")
		return
	end
	nextUse[player] = math.huge
 local r3Owner = beginR3Entry(door)
	local ok, err = pcall(function()
		if not stream(player, exit.Position) then return end
		local nowCharacter, nowRoot = readyPlayer(player)
		local nowModel, nowExit = readyPreview()
		if nowCharacter ~= character or nowModel ~= model or nowExit ~= exit
			or prompt.Parent ~= door or not (door == liveDoor() or isR3Entry(door))
			or (nowRoot.Position - door.Position).Magnitude > 14
			or returnPrompt.Parent ~= exit or not returnPrompt.Enabled
			or not hasFloor(model, exit) then return end
		character:PivotTo(upright(exit.Position, exit.CFrame.LookVector))
	end)
 finishR3Entry(r3Owner)
	release(player)
	if not ok then warn("[Level5PreviewAccess] entry failed:", err) end
end

local function ensurePrompt(parent, name, action, object, callback)
	local prompt = parent:FindFirstChild(name)
	if not prompt then
		prompt = Instance.new("ProximityPrompt")
		prompt.Name = name
		prompt.ActionText = action
		prompt.ObjectText = object
		prompt.HoldDuration = 0.5
		prompt.MaxActivationDistance = 10
		prompt.RequiresLineOfSight = false
		prompt.Parent = parent
	end
	if not prompt:IsA("ProximityPrompt") then return end
	if not hooked[prompt] then
		hooked[prompt] = true
		prompt.Triggered:Connect(function(player) callback(player, prompt) end)
	end
end

-- R4 queue cohorts use the same existing authorized preview/floor/stream
-- helpers as the original E entry. Original door prompts are unchanged.
do
 local bridge = r3Bridge()
 if bridge and bridge.RegisterPreviewLauncher then
  local queueLocks = {}
  local registered, registrationProblem = pcall(bridge.RegisterPreviewLauncher, 5, script, {
   allowed = function(player, _, station)
    local lock = queueLocks[player]
    return (if lock then bridge.ContextOwns(lock, player, station) else (nextUse[player] or 0) <= os.clock())
     and readyPlayer(player) ~= nil
   end,
   ready = function()
    local model, exit = readyPreview()
    local prompt = exit and exit:FindFirstChild(RETURN_PROMPT)
    if not model or not prompt or not prompt:IsA("ProximityPrompt") or not prompt.Enabled
     or not hasFloor(model, exit) then return nil end
    return model, exit
   end,
   launch = function(context)
    local locked, reason = bridge.LockPreviewController(context, nextUse, queueLocks, release)
    if not locked then return false, reason end
    local model, exit = readyPreview()
    local returnPrompt = exit and exit:FindFirstChild(RETURN_PROMPT)
    if not model or not returnPrompt or not returnPrompt:IsA("ProximityPrompt")
     or not returnPrompt.Enabled or not hasFloor(model, exit) then return false, "PREVIEW_NOT_READY" end
    local entries, problem = bridge.PreparePreviewGroup(context, model, exit, stream)
    if not entries then return false, problem end
    return bridge.CommitPreviewGroup(context, entries, function() return true end)
   end,
  })
  if not registered then warn("[R4 Preview Queue] registration: " .. tostring(registrationProblem)) end
 end
end

local function hookDoor()
	local door = liveDoor()
	if door then ensurePrompt(door, ENTER_PROMPT, "ENTER LEVEL 5 PREVIEW", "DEVELOPER PREVIEW", onEnter) end
 local bridge = r3Bridge()
 local model = workspace:FindFirstChild("LobbyReimaginedPreview")
 if bridge then
  for _, host in ipairs(bridge.GetPreviewEntries(model, 5)) do
   ensurePrompt(host, ENTER_PROMPT, "ENTER LEVEL 5 PREVIEW", "DEVELOPER PREVIEW", onEnter)
  end
 end
end

local function hookExit()
	local _, exit = readyPreview()
	if exit then ensurePrompt(exit, RETURN_PROMPT, "RETURN TO LOBBY", "LEVEL 5 DEVELOPER PREVIEW", onReturn) end
end

local watchedModel, readyConnection
local function watchPreview(model)
	if watchedModel ~= model then
		if readyConnection then readyConnection:Disconnect() end
		watchedModel = model
		readyConnection = model and model:GetAttributeChangedSignal("Level5PreviewReady"):Connect(hookExit) or nil
	end
	hookExit()
end

Players.PlayerRemoving:Connect(function(player) nextUse[player] = nil end)
workspace.DescendantAdded:Connect(function(instance)
	local name = instance.Name
	if name == "ServerLobby" or name == "LevelDoorways" or name == "Level5SealedDoor" then
		hookDoor()
	elseif name == MODEL_NAME and instance.Parent == workspace and instance:IsA("Model") then
		watchPreview(instance)
	elseif name == EXIT_NAME then
		hookExit()
	end
end)
hookDoor()
watchPreview(workspace:FindFirstChild(MODEL_NAME))

-- Keep the distant preview developer-only even if a client moves there without using the door.
task.spawn(function()
	local boundedModel, bounds, half
	while task.wait(0.5) do
		local model = readyPreview()
		local spawn = liveSpawn()
		if model and spawn then
			if boundedModel ~= model then
				local size
				bounds, size = model:GetBoundingBox()
				half = size * 0.5 + Vector3.new(8, 20, 8)
				boundedModel = model
			end
			for _, player in ipairs(Players:GetPlayers()) do
				if not DevAccess.IsAllowed(player) then
					local character = player.Character
					local humanoid = character and character:FindFirstChildOfClass("Humanoid")
					local root = humanoid and humanoid.RootPart
					if root and humanoid.Health > 0 then
						local p = bounds:PointToObjectSpace(root.Position)
						if math.abs(p.X) <= half.X and math.abs(p.Y) <= half.Y and math.abs(p.Z) <= half.Z then
							character:PivotTo(upright(spawn.Position + Vector3.new(0, 4, 0), spawn.CFrame.LookVector))
						end
					end
				end
			end
		end
	end
end)

-- Observe ready publication/restoration; the original lobby watcher is unchanged.
local r3Watched = setmetatable({}, {__mode = "k"})
local function watchR3Lobby(model)
 if not model or not model:IsA("Model") or model.Name ~= "LobbyReimaginedPreview" or r3Watched[model] then return end
 r3Watched[model] = true
 local ready = model:GetAttributeChangedSignal("Ready"):Connect(hookDoor)
 local ancestry = model.AncestryChanged:Connect(function() if model.Parent == workspace then task.defer(hookDoor) end end)
 local descendants = model.DescendantAdded:Connect(function(part)
  if part:GetAttribute("R3DeveloperPreviewEntry") == 5 then task.defer(hookDoor) end
 end)
 model.Destroying:Once(function() ready:Disconnect(); ancestry:Disconnect(); descendants:Disconnect() end)
 task.defer(hookDoor)
end
workspace.ChildAdded:Connect(watchR3Lobby)
watchR3Lobby(workspace:FindFirstChild("LobbyReimaginedPreview"))

```


SOURCE ServerScriptService.Level6PreviewAccess.Script.luau
```luau
-- Developer-only functional preview. Isolated from GameManager and public level progression.
local Players = game:GetService("Players")
local ReplicatedStorage = game:GetService("ReplicatedStorage")
local HttpService = game:GetService("HttpService")
local DevAccess = require(ReplicatedStorage:WaitForChild("DevAccess"))
local Runtime = require(script.Parent:WaitForChild("Level 6 Systems"):WaitForChild("Level 6 Preview Runtime"))
local MODEL_NAME, EXIT_NAME = "Level 6 Generated World", "Level6Exit"
local ENTER, RETURN = "Level6DeveloperPreviewPrompt", "Level6DeveloperPreviewReturnPrompt"
local RETURN_ANCHOR = "Level6DeveloperPreviewReturnAnchor"
local RETURN_OWNER = "Level6PreviewReturnOwned"
local RETURN_OFFSET = Vector3.new(1, 1.5, -4)
local transport = ReplicatedStorage:FindFirstChild("Level6PreviewTransport")
if not transport then
	transport = Instance.new("RemoteEvent")
	transport.Name = "Level6PreviewTransport"
	transport.Parent = ReplicatedStorage
end
assert(transport:IsA("RemoteEvent"), "Level6PreviewTransport has wrong class")
local pending, nextUse = {}, {}
local hooked = setmetatable({}, {__mode = "k"})

local function lobbyPart(name)
	local lobby = workspace:FindFirstChild("ServerLobby")
	if not lobby then return nil end
	if name == "LobbySpawn" then return lobby:FindFirstChild(name) end
	local doors = lobby:FindFirstChild("LevelDoorways")
	return doors and doors:FindFirstChild(name)
end
-- R3 additional hosts retain this controller's existing access/stream/launch path.
local function r3Bridge()
 local folder = script.Parent:FindFirstChild("LobbyReimaginedPreview")
 local module = folder and folder:FindFirstChild("QueueBridge")
 return module and module:IsA("ModuleScript") and require(module) or nil
end
local function isR3Entry(door)
 local bridge = r3Bridge()
 return bridge and bridge.IsPreviewEntry(door, 6) or false
end
local r3Inflight = setmetatable({}, {__mode = "k"})
local function beginR3Entry(door)
 if not isR3Entry(door) then return nil end
 local ref = door:FindFirstChild("QueueRenderOwner")
 local owner = ref and ref:IsA("ObjectValue") and ref.Value
 if not owner or not owner:IsA("Model") or not owner:IsDescendantOf(door:FindFirstAncestor("LobbyReimaginedPreview")) then return nil end
 r3Inflight[owner] = (r3Inflight[owner] or 0) + 1
 owner:SetAttribute("QueueActive", true)
 return owner
end
local function finishR3Entry(owner)
 if not owner then return end
 local count = math.max(0, (r3Inflight[owner] or 1) - 1)
 r3Inflight[owner] = count > 0 and count or nil
 if owner.Parent then owner:SetAttribute("QueueActive", count > 0) end
end

local function playerReady(player)
	if player.Parent ~= Players or not DevAccess.IsLevel6PreviewAllowed(player)
		or player:GetAttribute("InRound") == true
		or workspace:GetAttribute("ReservedRoundServer") == true then return nil end
	local character = player.Character
	local humanoid = character and character:FindFirstChildOfClass("Humanoid")
	local root = humanoid and humanoid.RootPart
	if not root or not character:IsDescendantOf(workspace) or root.Anchored
		or humanoid.SeatPart or humanoid.Health <= 0 then return nil end
	return character, root
end
local function previewReady()
	local model = workspace:FindFirstChild(MODEL_NAME)
	if not model or not model:IsA("Model") or model:GetAttribute("Level6Preview") ~= true
		or model:GetAttribute("PreviewOnly") ~= true or model:GetAttribute("Level6PreviewReady") ~= true then return nil end
	local exit = model:FindFirstChild(EXIT_NAME, true)
	if not exit or not exit:IsA("BasePart") then return nil end
	return model, exit
end
local function floorAt(model, point)
	local params = RaycastParams.new()
	params.FilterType = Enum.RaycastFilterType.Include
	params.FilterDescendantsInstances = {model}
	params.RespectCanCollide = true
	local hit = workspace:Raycast(point, Vector3.new(0, -10, 0), params)
	return hit ~= nil and hit.Normal.Y > 0.7
end
local function upright(cf)
	local flat = Vector3.new(cf.LookVector.X, 0, cf.LookVector.Z)
	return CFrame.lookAt(cf.Position, cf.Position + (if flat.Magnitude > .01 then flat else Vector3.zAxis))
end
transport.OnServerEvent:Connect(function(player, nonce, ready)
	local token = pending[player]
	if token and nonce == token.nonce and ready == true and os.clock() <= token.expires
		and DevAccess.IsLevel6PreviewAllowed(player) then token.ready = true end
end)
local function streamReady(player, target, modelName)
	local token = {nonce = HttpService:GenerateGUID(false), expires = os.clock() + 22, ready = false}
	pending[player] = token
	local ok = pcall(function() player:RequestStreamAroundAsync(target, 8) end)
	if ok and player.Parent == Players then
		transport:FireClient(player, token.nonce, target, modelName)
		while pending[player] == token and not token.ready and os.clock() < token.expires
			and player.Parent == Players do task.wait(.1) end
	end
	if pending[player] == token then pending[player] = nil end
	return ok and token.ready
end
local function release(player)
	nextUse[player] = if player.Parent == Players then os.clock() + 2 else nil
end

local onReturn
local function ensurePrompt(parent, name, action, callback)
	local prompt = parent:FindFirstChild(name)
	if not prompt then
		prompt = Instance.new("ProximityPrompt")
		prompt.Name = name; prompt.ActionText = action; prompt.ObjectText = "LEVEL 6 · DEV PREVIEW"
		prompt.HoldDuration = .5; prompt.MaxActivationDistance = 10; prompt.RequiresLineOfSight = false
		prompt.Parent = parent
	end
	if prompt:IsA("ProximityPrompt") and not hooked[prompt] then
		hooked[prompt] = prompt.Triggered:Connect(function(player) callback(player, prompt) end)
	end
	return prompt
end
-- The tube landing is underfoot. Mount only this RETURN prompt ahead of
-- the arrival view; the exit-relative distance/auth/stream guards stay intact.
local function validReturnAnchor(anchor, exit)
	return anchor ~= nil and anchor:IsA("Attachment") and anchor.Name == RETURN_ANCHOR
		and anchor.Parent == exit and anchor:GetAttribute(RETURN_OWNER) == true
		and anchor.Position == RETURN_OFFSET
end
local function validReturnPrompt(prompt, exit)
	if not prompt or not prompt:IsA("ProximityPrompt") or prompt.Name ~= RETURN then return false end
	-- Compatibility for an existing direct exit prompt before hookExit mounts it.
	return prompt.Parent == exit or validReturnAnchor(prompt.Parent, exit)
end
local function returnPrompt(exit)
	if not exit then return nil end
	local anchor = exit:FindFirstChild(RETURN_ANCHOR)
	local prompt = if anchor then (if validReturnAnchor(anchor, exit) then anchor:FindFirstChild(RETURN) else nil)
		else exit:FindFirstChild(RETURN)
	return if validReturnPrompt(prompt, exit) then prompt else nil
end
local function hookExit()
	local _, exit = previewReady()
	if not exit then return end
	local anchor = exit:FindFirstChild(RETURN_ANCHOR)
	local legacy = exit:FindFirstChild(RETURN)
	if (anchor and not validReturnAnchor(anchor, exit))
		or (legacy and not validReturnPrompt(legacy, exit)) then
		warn("[Level6PreviewAccess] RETURN mount conflicts with an existing instance")
		return
	end
	local mounted = anchor and anchor:FindFirstChild(RETURN)
	if mounted and (not validReturnPrompt(mounted, exit) or legacy) then
		warn("[Level6PreviewAccess] RETURN mount has a conflicting prompt")
		return
	end
	if not anchor then
		anchor = Instance.new("Attachment")
		anchor.Name = RETURN_ANCHOR
		anchor.Position = RETURN_OFFSET
		anchor:SetAttribute(RETURN_OWNER, true)
		anchor.Parent = exit
	end
	if legacy then legacy.Parent = anchor end
	local prompt = ensurePrompt(anchor, RETURN, "RETURN TO LOBBY", onReturn)
	if validReturnPrompt(prompt, exit) then prompt.MaxActivationDistance = 7.5 end
end

local function onEnter(player, prompt)
	if (nextUse[player] or 0) > os.clock() or player:GetAttribute("Level6InRound") == true then return end
	local character, root = playerReady(player)
	local door = prompt.Parent
	if not character or not door or not door:IsA("BasePart")
  or not (door == lobbyPart("Level6SealedDoor") or isR3Entry(door)) or (root.Position - door.Position).Magnitude > 14 then return end
	nextUse[player] = math.huge
 local r3Owner = beginR3Entry(door)
	local previous = character:GetPivot()
	local ok, err = pcall(function()
		local model, exit = Runtime.EnsureWorld()
		hookExit()
		if not model or not exit or not floorAt(model, exit.Position) then error("Preview landing floor unavailable") end
		if not streamReady(player, exit.Position, MODEL_NAME) then error("Preview streaming confirmation timed out") end
		local currentCharacter, currentRoot = playerReady(player)
		local currentModel, currentExit = previewReady()
		if currentCharacter ~= character or currentModel ~= model or currentExit ~= exit
			or not (door == lobbyPart("Level6SealedDoor") or isR3Entry(door)) or prompt.Parent ~= door
			or (currentRoot.Position - door.Position).Magnitude > 14
			or not floorAt(model, exit.Position) then return end
		root.AssemblyLinearVelocity = Vector3.zero; root.AssemblyAngularVelocity = Vector3.zero
		character:PivotTo(upright(exit.CFrame))
		local joined, reason = Runtime.Join(player)
		if not joined then
			character:PivotTo(previous)
			error("Preview join rejected: " .. tostring(reason))
		end
		-- Orient once only after an authorized, successful Level 6 arrival.
		transport:FireClient(player, "ArrivalFacing", upright(exit.CFrame), MODEL_NAME)
	end)
 finishR3Entry(r3Owner)
	release(player)
	if not ok then warn("[Level6PreviewAccess] " .. tostring(err)) end
end
onReturn = function(player, prompt)
	if (nextUse[player] or 0) > os.clock() then return end
	local character, root = playerReady(player)
	local model, exit = previewReady()
	local spawn = lobbyPart("LobbySpawn")
	if not character or not model or not exit or not spawn or player:GetAttribute("Level6InRound") ~= true
		or not validReturnPrompt(prompt, exit) or (root.Position - exit.Position).Magnitude > 12 then return end
	nextUse[player] = math.huge
	local ok, err = pcall(function()
		local landing = spawn.Position + Vector3.new(0, 4, 0)
		if not streamReady(player, landing, "ServerLobby") then error("Lobby streaming confirmation timed out") end
		local currentCharacter, currentRoot = playerReady(player)
		if currentCharacter ~= character or not exit.Parent or not validReturnPrompt(prompt, exit)
			or (currentRoot.Position - exit.Position).Magnitude > 12 or lobbyPart("LobbySpawn") ~= spawn then return end
		Runtime.Leave(player)
		root.AssemblyLinearVelocity = Vector3.zero; root.AssemblyAngularVelocity = Vector3.zero
		character:PivotTo(upright(spawn.CFrame + Vector3.new(0, 4, 0)))
	end)
	release(player)
	if not ok then warn("[Level6PreviewAccess] " .. tostring(err)) end
end
-- R4 queue cohorts keep the existing Level6 allowlist, floor/stream
-- confirmation and Runtime.Join path. No campaign routing is changed.
do
 local bridge = r3Bridge()
 if bridge and bridge.RegisterPreviewLauncher then
  local queueLocks = {}
  local registered, registrationProblem = pcall(bridge.RegisterPreviewLauncher, 6, script, {
   allowed = function(player, _, station)
    local lock = queueLocks[player]
    return (if lock then bridge.ContextOwns(lock, player, station) else (nextUse[player] or 0) <= os.clock())
     and playerReady(player) ~= nil
   end,
   ready = function()
    local model, exit = previewReady()
    local prompt = returnPrompt(exit)
    if not model or not prompt or not prompt:IsA("ProximityPrompt") or not prompt.Enabled
     or not floorAt(model, exit.Position) then return nil end
    return model, exit
   end,
   launch = function(context)
    local locked, reason = bridge.LockPreviewController(context, nextUse, queueLocks, release)
    if not locked then return false, reason end
    local model, exit = Runtime.EnsureWorld()
    hookExit()
    if not model or not exit or not floorAt(model, exit.Position) then return false, "PREVIEW_NOT_READY" end
    local entries, problem = bridge.PreparePreviewGroup(context, model, exit, function(player, position)
     return streamReady(player, position, MODEL_NAME)
    end)
    if not entries then return false, problem end
    return bridge.CommitPreviewGroup(context, entries, function(entry)
     local joined, reason = Runtime.Join(entry.player)
     if joined then transport:FireClient(entry.player, "ArrivalFacing", entry.frame, MODEL_NAME) end
     return joined, reason
    end, function(entry) Runtime.Leave(entry.player) end)
   end,
  })
  if not registered then warn("[R4 Preview Queue] registration: " .. tostring(registrationProblem)) end
 end
end

local function hookDoor()
	local door = lobbyPart("Level6SealedDoor")
	if door and door:IsA("BasePart") then ensurePrompt(door, ENTER, "ENTER PARTY BACKROOMS", onEnter) end
 local bridge = r3Bridge()
 local model = workspace:FindFirstChild("LobbyReimaginedPreview")
 if bridge then
  for _, host in ipairs(bridge.GetPreviewEntries(model, 6)) do
   ensurePrompt(host, ENTER, "ENTER PARTY BACKROOMS", onEnter)
  end
 end
end
local watchedModel, readyConnection
local function watchModel(model)
	if watchedModel ~= model then
		if readyConnection then readyConnection:Disconnect() end
		watchedModel = model
		readyConnection = model and model:GetAttributeChangedSignal("Level6PreviewReady"):Connect(hookExit) or nil
	end
	hookExit()
end
Players.PlayerRemoving:Connect(function(player) pending[player] = nil; nextUse[player] = nil end)
workspace.DescendantAdded:Connect(function(instance)
	if instance.Name == "ServerLobby" or instance.Name == "LevelDoorways" or instance.Name == "Level6SealedDoor" then hookDoor()
	elseif instance.Name == MODEL_NAME and instance.Parent == workspace and instance:IsA("Model") then watchModel(instance)
	elseif instance.Name == EXIT_NAME then hookExit() end
end)
hookDoor(); watchModel(workspace:FindFirstChild(MODEL_NAME))

-- Observe ready publication/restoration; the original lobby watcher is unchanged.
local r3Watched = setmetatable({}, {__mode = "k"})
local function watchR3Lobby(model)
 if not model or not model:IsA("Model") or model.Name ~= "LobbyReimaginedPreview" or r3Watched[model] then return end
 r3Watched[model] = true
 local ready = model:GetAttributeChangedSignal("Ready"):Connect(hookDoor)
 local ancestry = model.AncestryChanged:Connect(function() if model.Parent == workspace then task.defer(hookDoor) end end)
 local descendants = model.DescendantAdded:Connect(function(part)
  if part:GetAttribute("R3DeveloperPreviewEntry") == 6 then task.defer(hookDoor) end
 end)
 model.Destroying:Once(function() ready:Disconnect(); ancestry:Disconnect(); descendants:Disconnect() end)
 task.defer(hookDoor)
end
workspace.ChildAdded:Connect(watchR3Lobby)
watchR3Lobby(workspace:FindFirstChild("LobbyReimaginedPreview"))

```


SOURCE StarterPlayer.StarterPlayerScripts.RoundUI.LocalScript.luau
```luau
FOCUSED EXCERPTS ONLY; full file hash above.
345:  Ambient=Color3.fromRGB(30,32,30), OutdoorAmbient=Color3.fromRGB(0,0,0),
346:  Brightness=.6, ClockTime=0, FogColor=Color3.fromRGB(30,32,30), FogStart=0, FogEnd=100000,
347: }
348: function revisedLobbyLighting.contains(inMaze)
349:  if inMaze or player:GetAttribute("Level6InRound") == true then return false end
350:  local model = workspace:FindFirstChild("LobbyReimaginedPreview")
351:  if not model or not model:IsA("Model") or model.Parent ~= workspace
352:   or model:GetAttribute("LobbyReimaginedOwned") ~= true or model:GetAttribute("Ready") ~= true
353:   or model:GetAttribute("LobbyVisualRevision") ~= 4 then return false end
354:  local center = model:GetAttribute("PreviewCenter")
355:  local character = player.Character
356:  local root = character and character:FindFirstChild("HumanoidRootPart")
357:  if typeof(center) ~= "Vector3" or not root or not root:IsA("BasePart") then return false end
358:  local point = root.Position-center
359:  -- Authored R4 tube plus six circular bays. The original lobby is outside
360:  -- these bounds even at its nearest bay; distant level previews stay excluded.
361:  return math.abs(point.X) <= 100 and math.abs(point.Z) <= 144 and point.Y >= -5 and point.Y <= 45
362: end
363: function revisedLobbyLighting.restore()
364:  -- A nonparticipant can leave R4 while another party keeps the old global
365:  -- level markers set. Restore only our own pass before those guards return.
366:  local globalsOwned = player:GetAttribute("Level4LightingOwned") == true
367:   or player:GetAttribute("InRound") == true or player:GetAttribute("Level6InRound") == true
368:  if not globalsOwned and revisedLobbyLighting.lighting then
```


SOURCE ReplicatedStorage.DevAccess.ModuleScript.luau
```luau
-- One shared whitelist for every client and server developer command.
-- UserIds are permanent; usernames can change and should never be an authority boundary.
local DevAccess = {}

local ALLOWED_USER_IDS = {
	[40920547] = true,   -- mikkelczar
	[9488575949] = true, -- LaverSneglen
}

-- Timeline seeking is intentionally narrower than the shared developer tools.
local LEVEL3_TIMELINE_OWNER_USER_ID = 9488575949 -- LaverSneglen

function DevAccess.IsAllowed(subject)
	local userId
	if typeof(subject) == "Instance" and subject:IsA("Player") then
		userId = subject.UserId
	elseif type(subject) == "number" then
		userId = subject
	end
	return userId ~= nil and ALLOWED_USER_IDS[userId] == true
end

-- Preview access is narrower than the general developer commands.
function DevAccess.IsLevel6PreviewAllowed(subject)
	if DevAccess.IsAllowed(subject) then return true end
	if typeof(subject) == "Instance" and subject:IsA("Player") then
		return subject.UserId == 11374988579 -- ZenMeister02
	end
	return type(subject) == "number" and subject == 11374988579
end

function DevAccess.IsLevel3TimelineOwner(subject)
	local userId
	if typeof(subject) == "Instance" and subject:IsA("Player") then
		userId = subject.UserId
	elseif type(subject) == "number" then
		userId = subject
	end
	return userId == LEVEL3_TIMELINE_OWNER_USER_ID
end

return DevAccess

```


PROPOSED GEOMETRY build_plan.py
```
"""Additive layout only; reuses the installed R4 Blender mesh kit unchanged.

This script does not contact Studio, mutate the authoritative manifest, or edit
existing authoring files. Output positions and rotations use Roblox coordinates.
"""
from pathlib import Path
import json, math, random
ROOT=Path(__file__).resolve().parents[3]
OUT=Path(__file__).resolve().parent
m=json.loads((ROOT/'assets/models/lobby-reimagined-r4-20261001/manifest.json').read_text())
families=['Sofa','Desk','FilingCabinet','CRTMonitor','Photocopier','StackChair','VinylBench','WireTrolley','RolledCarpet']
chunks={f:next(c for c in m['chunks'] if c['family']==f) for f in families}

def rotation(rx,ry,rz):
    # Roblox CFrame.Angles Rx*Ry*Rz; same matrix order as the runtime emitter.
    sx,cx=math.sin(rx),math.cos(rx);sy,cy=math.sin(ry),math.cos(ry);sz,cz=math.sin(rz),math.cos(rz)
    return [[cy*cz,-cy*sz,sy], [cx*sz+sx*sy*cz,cx*cz-sx*sy*sz,-sx*cy], [sx*sz-cx*sy*cz,sx*cz+cx*sy*sz,cx*cy]]
def mul(a,p):return [sum(a[i][j]*p[j] for j in range(3)) for i in range(3)]
def bounds(fam,rot):
    mat=rotation(*rot); size=chunks[fam]['size']; corners=[mul(mat,[a*size[0]/2,b*size[1]/2,c*size[2]/2]) for a in (-1,1) for b in (-1,1) for c in (-1,1)]
    half=[max(abs(p[i]) for p in corners) for i in range(3)]
    return mat,corners,half
placements=[]; barriers=[];failures=[]
def emit(fam,center,rot,label):
    mat,corners,half=bounds(fam,rot)
    pose=[center[i]-mul(mat,chunks[fam]['center'])[i] for i in range(3)]
    for p in corners:
        x,y=center[0]+p[0],center[1]+p[1]
        if y<-.03 or x*x+max(0,y-1)**2>33.7**2:failures.append((label,x,y))
    placements.append({'name':label,'family':fam,'robloxPosition':[round(p,6) for p in pose], 'rotation':[round(p,8) for p in rot], 'bboxCenter':[round(p,6) for p in center], 'bboxHalf':[round(p,6) for p in half]})
    return half
for end,sign in [('South',-1),('NorthDJ',1)]:
    rng=random.Random(516029+(1 if sign>0 else 0))
    # A dense back layer follows the round arch; turned desks/cabinets are
    # interlocked like the reference rather than individual upright columns.
    for row, y in enumerate([2.05,5.6,9.2,12.8,16.4,20.0,23.6,27.2,30.7,33.2]):
        x=-31.5
        col=0
        while x<31.5:
            fam=rng.choice(['Desk','Desk','Sofa','VinylBench','FilingCabinet'])
            # Cabinet on its side becomes a broad, distinct drawer face.
            rolled=fam=='FilingCabinet'
            rot=(rng.uniform(-.10,.10), (math.pi if sign>0 else 0)+rng.uniform(-.20,.20), (math.pi/2 if rolled else 0)+rng.uniform(-.10,.10))
            mat,corners,half=bounds(fam,rot)
            cx=x+half[0]
            floor=.8 if abs(cx)+half[0]>=16.2 else 0
            center=[cx,max(y,floor+half[1]),sign*rng.uniform(134.2,134.6)]
            # Reject an entire bounding box if it pierces the curved shell.
            fits=all((center[0]+p[0])**2+max(0,center[1]+p[1]-1)**2<=33.55**2 for p in corners)
            if fits:emit(fam,center,rot,f'{end} Embedded {row:02d}-{col:02d}')
            x+=max(2.4,half[0]*2-.30)
            col+=1
    # A small irregular crown closes the last course towards the ceiling.
    # Narrow CRTs and one sideways cabinet fit where wide sofas cannot.
    for crown,fam,cx,cy,roll in [(0,'CRTMonitor',-3.9,32.55,-.025),(1,'FilingCabinet',.1,32.85,math.pi/2),(2,'CRTMonitor',3.8,32.58,.022)]:
        rot=(0,math.pi if sign>0 else 0,roll)
        _,corners,half=bounds(fam,rot)
        if all((cx+p[0])**2+max(0,cy+p[1]-1)**2<33.55**2 for p in corners):
            emit(fam,[cx,cy,sign*134.8],rot,f'{end} Ceiling crown {crown:02d}')
    # Foreground legged furniture and recognisable CRT/copier clutter disguise
    # the background's packed courses. DJ-front clearance is deliberate.
    for idx,x in enumerate([-29,-23,-17,-11,-5,1,7,13,19,25,30]):
        if sign>0 and abs(x)<17:continue
        fam=['Sofa','Photocopier','FilingCabinet','WireTrolley','VinylBench','Desk'][idx%6]
        rot=(0,(math.pi if sign>0 else 0)+rng.uniform(-.33,.33),0)
        _,corners,half=bounds(fam,rot)
        floor=.8 if abs(x)+half[0]>=16.2 else 0
        # Near-end foreground reaches z=-128, far-end pieces remain beyond+130.8.
        zz=sign*(132.6 if sign>0 else 129.6)
        center=[x,floor+half[1],zz]
        if all((x+p[0])**2+max(0,center[1]+p[1]-1)**2<33.55**2 for p in corners):
            emit(fam,center,rot,f'{end} Foreground {idx:02d}')
            # CRTs sit on genuine desk/copier/cabinet support tops only.
            if fam in ['Desk','Photocopier','FilingCabinet']:
                cfamily='CRTMonitor'; crot=(0,rot[1]+rng.uniform(-.25,.25),0)
                _,_,ch=bounds(cfamily,crot)
                emit(cfamily,[x,center[1]+half[1]+ch[1]-.04,zz],crot,f'{end} Supported CRT {idx:02d}')
    # A few chairs are visibly wedged into the packed background, not used as
    # supports. Their deep side parts overlap a background volume by design.
    for idx,x in enumerate([-26,-19,-12,-5,4,11,18,25]):
        y=rng.uniform(7,19)
        rot=(rng.uniform(-.5,.5), (math.pi if sign>0 else 0)+rng.uniform(-.5,.5), rng.choice([-1,1])*rng.uniform(.25,.8))
        _,corners,half=bounds('StackChair',rot)
        if all((x+p[0])**2+max(0,y+p[1]-1)**2<33.55**2 for p in corners):emit('StackChair',[x,y,sign*132.2],rot,f'{end} Wedged chair {idx:02d}')
    # Transparent full-width barrier is wholly behind DJ rail / foreground.
    # Top edges follow the arch; separate columns avoid square overhangs.
    for idx,x in enumerate(range(-32,33,4)):
        width=4.08; edge=min(33.78,abs(x)+width/2)
        height=1+math.sqrt(max(0,33.8**2-edge**2))
        barriers.append({'name':f'{end} Furniture Blocker {idx:02d}','position':[x,height/2,sign*132.0], 'size':[width,height,1.0]})
# Inspect exact measured load, not an estimate of unique geometry.
triangles=sum(chunks[p['family']]['triangles'] for p in placements)
plan={'schema':'lobby-r4-additive-end-clutter-v1','baseManifestSHA256':'17b68efc473a0f100cf6ce6b9389332a5f2a87d82faf7694a0536a82483bc995','previewCenter':m['previewCenter'],'axisMapping':'Roblox X,Y,Z; CFrame.Angles XYZ radians','reuseInstalledBlenderFamilies':True,'placements':placements,'colliders':barriers,'statistics':{'instances':len(placements),'extraInstancedTriangles':triangles,'uniqueNewMeshes':0,'archCornerFailures':len(failures)}, 'notes':['Dense lower-middle-class 1990s furniture blockade at both tunnel ends.','Central north pile stays behind DJ rear guard at local z=128.4.','Intentional embedding in clutter; no unrelated lobby edits.','Use center-relative placements; source mesh offset is already compensated.']}
assert not failures,failures[:6]
(OUT/'plan.json').write_text(json.dumps(plan,indent=2)+'\n')
print(plan['statistics'])

```


PROPOSED GEOMETRY EndBlockades.ModuleScript.luau
```
-- Candidate helper only; root must compare authoritative Studio before using.
-- Call after the existing R4 manifest placements. All geometry reuses the
-- exact Blender mesh kit; native parts supply collision and luminous lenses.
local Module = {}
local OWNED = "LobbyReimaginedOwned"
local function v(a) return Vector3.new(table.unpack(a)) end
function Module.Emit(plan, center, visuals, collisions, lighting, place)
	assert(plan.schema == "lobby-r4-additive-end-clutter-v1")
	assert(plan.statistics.uniqueNewMeshes == 0 and plan.statistics.archCornerFailures == 0)
	assert(not visuals:FindFirstChild("Reference End Furniture Piles"), "Owned pile already exists")
	local folder = Instance.new("Folder")
	folder.Name = "Reference End Furniture Piles"
	folder:SetAttribute(OWNED, true)
	folder:SetAttribute("ClutterRevision20261002", true)
	folder.Parent = visuals
	for _, item in ipairs(plan.placements) do
		local cf = CFrame.new(center + v(item.robloxPosition)) * CFrame.Angles(table.unpack(item.rotation))
		local object = place(item.family, cf, folder)
		object.Name = item.name
		object:SetAttribute(OWNED, true)
		object:SetAttribute("EndClutterFamily", item.family)
	end
	for _, item in ipairs(plan.colliders) do
		local p = Instance.new("Part")
		p.Name = item.name; p.Anchored = true
		p.Size = v(item.size); p.CFrame = CFrame.new(center + v(item.position))
		p.CanCollide = true; p.CanQuery = true; p.CanTouch = false
		p.Transparency = 1; p.CastShadow = false
		p:SetAttribute(OWNED, true); p:SetAttribute("FurnitureEndBlocker", true)
		p.Parent = collisions
	end
	-- Keep the established warm/cyan room fills and global Lighting untouched.
	-- A luminous underside makes the existing fixtures readable from eye level.
	local count = 0
	for _, host in ipairs(lighting:GetChildren()) do
		if host.Name == "Tunnel Lamp" and host:IsA("BasePart") then
			local fill = host:FindFirstChild("Preview Fill")
			if fill and fill:IsA("PointLight") then fill.Brightness = .55 end
			count += 1
			local lens = Instance.new("Part")
			lens.Name = string.format("Ceiling Tube Luminous Lens %02d", count)
			lens.Size = Vector3.new(3.0, .035, .74)
			lens.CFrame = host.CFrame * CFrame.new(0, .73, 0)
			lens.Anchored = true; lens.CanCollide = false
			lens.CanTouch = false; lens.CanQuery = false
			lens.Material = Enum.Material.Neon
			lens.Color = Color3.fromRGB(95, 220, 213)
			lens.Transparency = .12; lens.CastShadow = false
			lens:SetAttribute(OWNED, true); lens.Parent = lighting
		end
	end
	folder:SetAttribute("AddedFurnitureInstances", #plan.placements)
	folder:SetAttribute("AddedInstancedTriangles", plan.statistics.extraInstancedTriangles)
	return folder
end

function Module.Add(model, kit, manifest)
	assert(model:GetAttribute(OWNED)==true, "Unowned lobby")
	local center=v(manifest.previewCenter)
	local function place(family, cf, parent)
		local source=assert(kit:FindFirstChild(family), "Missing installed Blender family "..family)
		local object=source:Clone()
		if object:IsA("Model") then
			object:PivotTo(cf*source:GetPivot())
			for _, d in ipairs(object:GetDescendants()) do
				if d:IsA("BasePart") then d.CanCollide=false;d.CanTouch=false;d.CanQuery=false end
				if d:IsA("MeshPart") then d.DoubleSided=true end
			end
		else
			object.CFrame=cf*source.CFrame
			object.DoubleSided=true
			object.CanCollide=false;object.CanTouch=false;object.CanQuery=false
		end
		object.Parent=parent
		return object
	end
	return Module.Emit(PLAN, center, assert(model:FindFirstChild("BlenderVisuals")),
		assert(model:FindFirstChild("PreviewCollisions")), assert(model:FindFirstChild("PreviewLighting")), place)
end

return Module
[The PLAN table is generated by the supplied build_plan.py. All 173 placements are in plan.json; this early design review supplies generation code and statistics only.]
```


GEOMETRY PLAN SUMMARY
{
  "statistics": {
    "instances": 173,
    "extraInstancedTriangles": 176424,
    "uniqueNewMeshes": 0,
    "archCornerFailures": 0
  },
  "familyChunks": {
    "CRTMonitor": [
      {
        "center": [
          0.0,
          1.32,
          0.13124999999999998
        ],
        "size": [
          2.6,
          2.64,
          2.2975000000000003
        ],
        "triangles": 564
      }
    ],
    "Desk": [
      {
        "center": [
          0.0,
          1.6045,
          0.0
        ],
        "size": [
          6.8,
          3.209,
          3.0
        ],
        "triangles": 972
      }
    ],
    "FilingCabinet": [
      {
        "center": [
          0.0,
          2.49,
          0.10999999999999999
        ],
        "size": [
          2.48,
          4.98,
          2.83
        ],
        "triangles": 1080
      }
    ],
    "Photocopier": [
      {
        "center": [
          -0.2599999999999999,
          1.64225,
          -0.018000000000000016
        ],
        "size": [
          4.45,
          3.2845,
          3.094
        ],
        "triangles": 1520
      }
    ],
    "Sofa": [
      {
        "center": [
          0.0,
          1.835,
          -0.029999999999999916
        ],
        "size": [
          7.6,
          3.67,
          3.3
        ],
        "triangles": 1456
      }
    ],
    "StackChair": [
      {
        "center": [
          0.0,
          1.761935,
          -0.05876099999999995
        ],
        "size": [
          2.0724,
          3.52387,
          2.1863219999999997
        ],
        "triangles": 584
      }
    ],
    "VinylBench": [
      {
        "center": [
          0.0,
          1.845,
          0.025000000000000022
        ],
        "size": [
          5.6,
          3.69,
          2.17
        ],
        "triangles": 808
      }
    ],
    "WireTrolley": [
      {
        "center": [
          0.0,
          1.9325,
          -0.27564600000000006
        ],
        "size": [
          3.85,
          3.865,
          3.281292
        ],
        "triangles": 1660
      }
    ]
  },
  "endBounds": {
    "South": {
      "min": [
        -32.932626,
        0.0,
        -137.050139
      ],
      "max": [
        33.369172999999996,
        32.525099,
        -127.15884799999999
      ]
    },
    "NorthDJ": {
      "min": [
        -32.9995,
        0.0362969999999998,
        130.246571
      ],
      "max": [
        32.905772999999996,
        32.649677,
        136.80809200000002
      ]
    }
  }
}