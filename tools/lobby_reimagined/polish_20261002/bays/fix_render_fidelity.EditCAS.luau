-- Root-run native Edit-only CAS: remove one runtime-forbidden property write.
local R=game:GetService("RunService")
local E=game:GetService("EncodingService")
local SES=game:GetService("ScriptEditorService")
assert(not R:IsRunning(),"Stop Play before scoped Bays fix")
assert(game.PlaceId==131311258779917 and game.GameId==10559217407 and game.CreatorId==1039373905,"Wrong authoritative place")
local OLD="2f6c8007a8472aefad700dac5511a0ad24e8ba1341e745c7ef5306142fb92058"
local NEW="1ab19711a303b058d033de6652da3d94c15e73f7e40b4e983036fa99c805bc2c"
local SOURCE=[====[-- R4 bay presentation only. GameManager/QueueBridge retain all queue authority.
-- Add once during the owned Builder transaction, before Ready/Workspace parenting.
local Module = {}
local OWNER = "LobbyPolishBays20261002Owned"
local FOLDER = "R4BayPresentation"
local THEME = {
	[1] = "OFFICE BACKROOMS · START HERE",
	[2] = "POOLROOMS",
	[3] = "MALL BACKROOMS",
	[4] = "90s CINEMA · DEV ONLY",
	[5] = "QUIET SUBURBS",
	[6] = "MALL PARTY",
}
-- Local coordinates use the bay's existing yaw: +Z is the entrance.
-- Rear/side furniture stays outside every 7.41-stud queue circle and entry path.
local PROPS = {
	{level=1, family="Desk", name="Office Workstation", position={13,.8,-21}, yaw=math.pi},
	{level=1, family="CRTMonitor", name="Office Terminal", position={13,4.009,-21.35}, yaw=math.pi},
	{level=1, family="BeigeKeyboard", name="Office Keyboard", position={13,4.009,-20.12}, yaw=math.pi},
	{level=2, family="VinylBench", name="Pool Waiting Bench A", position={-21,.8,0}, yaw=-math.pi/2},
	{level=2, family="VinylBench", name="Pool Waiting Bench B", position={21,.8,0}, yaw=math.pi/2},
	{level=2, family="WireTrolley", name="Pool Service Trolley", position={-14,.8,-20.5}, yaw=math.pi},
	{level=3, family="R4PartyChair", name="Party Chair A", position={-15,.76,-20}, yaw=0},
	{level=3, family="R4PartyChair", name="Party Chair B", position={15,.76,-20}, yaw=0},
	{level=3, family="WireTrolley", name="Party Supply Trolley", position={0,.8,-17.5}, yaw=math.pi},
	{level=4, family="VinylBench", name="Cinema Waiting Bench A", position={-21,.8,0}, yaw=-math.pi/2},
	{level=4, family="VinylBench", name="Cinema Waiting Bench B", position={21,.8,0}, yaw=math.pi/2},
	{level=4, family="Desk", name="Cinema Check Desk", position={0,.8,-18}, yaw=math.pi},
	{level=4, family="CRTMonitor", name="Cinema Check Monitor", position={0,4.009,-18.35}, yaw=math.pi},
	{level=5, family="Sofa", name="Suburb Waiting Sofa", position={-21,.8,0}, yaw=-math.pi/2},
	{level=5, family="VinylBench", name="Suburb Waiting Bench", position={21,.8,0}, yaw=math.pi/2},
	{level=5, family="RolledCarpet", name="Suburb Moving Carpet", position={17,.8,-18}, yaw=0},
	{level=6, family="VinylBench", name="Mall Waiting Bench A", position={-21,.8,0}, yaw=-math.pi/2},
	{level=6, family="VinylBench", name="Mall Waiting Bench B", position={21,.8,0}, yaw=math.pi/2},
	{level=6, family="R4PartyChair", name="Mall Spare Party Chair", position={-15,.76,-19.5}, yaw=0},
}
local function vec(values) return Vector3.new(table.unpack(values)) end
local function own(instance)
	instance:SetAttribute(OWNER, true)
	instance:SetAttribute("LobbyReimaginedOwned", true)
end
local function part(parent, name, size, frame, color, material)
	local object = Instance.new("Part")
	object.Name, object.Size, object.CFrame = name, size, frame
	object.Anchored = true
	object.CanCollide, object.CanTouch, object.CanQuery = false, false, false
	object.CastShadow = false
	object.Color, object.Material = color, material or Enum.Material.SmoothPlastic
	own(object); object.Parent = parent
	return object
end
local function text(host, face, message, color, canvas, distance, brightness)
	local gui = Instance.new("SurfaceGui")
	gui.Name, gui.Face = "R4 Bay Legend", face
	gui.CanvasSize = canvas
	gui.LightInfluence, gui.Brightness = 0, brightness or 1
	gui.AlwaysOnTop, gui.MaxDistance = false, distance or 160
	own(gui)
	local label = Instance.new("TextLabel")
	label.Name, label.Size = "Legend", UDim2.fromScale(1, 1)
	label.BackgroundTransparency, label.Text = 1, message
	label.TextColor3, label.Font, label.TextScaled = color, Enum.Font.GothamBold, true
	label.TextStrokeTransparency = .85
	own(label); label.Parent = gui; gui.Parent = host
	return label
end
local function addProp(parent, kit, record, frame)
	local source = assert(kit:FindFirstChild(record.family), "Missing bay prop " .. record.family)
	local copy = source:Clone()
	copy.Name = record.name
	if copy:IsA("Model") then copy:PivotTo(frame * source:GetPivot())
	else assert(copy:IsA("MeshPart"), "Invalid bay prop class"); copy.CFrame = frame * source.CFrame end
	local triangles = 0
	local function configure(object)
		own(object)
		if object:IsA("BasePart") then
			object.Anchored = true
			object.CanCollide, object.CanTouch, object.CanQuery = false, false, false
			object.CastShadow = true
		end
		if object:IsA("MeshPart") then
			-- Preserve the existing furniture defaults. The separately validated
			-- material helper owns any exact-hash culling/fidelity allowance.
			object.DoubleSided = true
			triangles += object:GetAttribute("BlenderTriangles") or 0
		end
	end
	configure(copy)
	for _, object in ipairs(copy:GetDescendants()) do configure(object) end
	copy:SetAttribute("BayLevel", record.level)
	copy:SetAttribute("SourceFamily", record.family)
	copy.Parent = parent
	return triangles
end
function Module.Add(model, kit, manifest)
	assert(model:IsA("Model") and model:GetAttribute("LobbyReimaginedOwned") == true
		and model:GetAttribute("LobbyVisualRevision") == 4 and model:GetAttribute("Ready") == false,
		"Bay polish requires the uncommitted owned R4 build")
	assert(not model:FindFirstChild(FOLDER), "Conflicting bay presentation owner")
	assert(#manifest.bays == 6 and #manifest.pads == 24, "Unexpected R4 bay/pad layout")
	local root = Instance.new("Folder")
	root.Name = FOLDER; own(root); root.Parent = model
	local props = Instance.new("Folder"); props.Name = "Theme Furniture"; own(props); props.Parent = root
	local signs = assert(model:FindFirstChild("LevelGateSigns"), "Missing R4 level signs")
	local pads = assert(model:FindFirstChild("PreviewQueuePads"), "Missing R4 queue bays")
	local center = vec(manifest.previewCenter)
	local frames, bayRecords = {}, {}
	local cream = Color3.fromRGB(228, 220, 184)
	for _, record in ipairs(manifest.bays) do
		local level = record.level
		assert(THEME[level] and not frames[level], "Duplicate/invalid bay level")
		local floor = vec(record.floorPosition) - Vector3.new(0, record.floorPosition[2], 0)
		local frame = CFrame.new(center + floor) * CFrame.Angles(0, record.yaw, 0)
		frames[level], bayRecords[level] = frame, record
		local header = assert(signs:FindFirstChild("LEVEL " .. level .. " Door Header"), "Missing exact door header")
		assert(header:IsA("BasePart") and header:GetAttribute("Level") == level, "Wrong door header owner")
		-- Header/arrow hosts and messages remain intact. Existing client L5/L6 status
		-- is at gate Y=19.6; these ribbons are BELOW the main header at Y=15.25.
		local ribbon = part(root, "Level" .. level .. " Theme Ribbon", Vector3.new(21.8,.86,.055),
			header.CFrame * CFrame.new(0,-1.95,.08), Color3.fromRGB(30,34,29))
		text(ribbon, Enum.NormalId.Back, THEME[level], cream, Vector2.new(1100,90), 230, 1.05)
		local instruction = if level <= 3 then "STEP ON A PAD · CHOOSE 1–6 PLAYERS"
			elseif level == 4 then "DEV ONLY · TRIAL OR MAP PREVIEW"
			else "DEV ACCESS REQUIRED · PARTY QUEUE"
		local board = part(root, "Level" .. level .. " Queue Instruction", Vector3.new(19.1,.92,.055),
			header.CFrame * CFrame.new(0,-3.4,.08), Color3.fromRGB(30,34,29))
		text(board, Enum.NormalId.Back, instruction, Color3.fromRGB(204,229,214), Vector2.new(1150,88), 160, 1)
		-- Thin visual runner joins the existing connector to the center aisle. It has
		-- no collision/query and stays outside the four circle detectors.
		part(root, "Level" .. level .. " Entry Runner", Vector3.new(4.3,.014,33.2),
			frame * CFrame.new(0,record.floorTopY+.014,16.6), Color3.fromRGB(107,101,77), Enum.Material.Fabric)
		for _, z in ipairs({22,28}) do
			for _, side in ipairs({-1,1}) do
				local tip, rear = Vector3.new(0,record.floorTopY+.036,z-1), Vector3.new(side*1.1,record.floorTopY+.036,z+.5)
				part(root, "Level" .. level .. " Entry Chevron", Vector3.new(.14,.014,(tip-rear).Magnitude),
					frame * CFrame.lookAt((tip+rear)/2,tip), Color3.fromRGB(211,198,145))
			end
		end
	end
	local perLevel = {}
	for _, record in ipairs(manifest.pads) do
		local level = record.level
		perLevel[level] = (perLevel[level] or 0) + 1
		local index = perLevel[level]
		local bay = assert(pads:FindFirstChild("QueueBay_Level" .. level), "Missing exact queue bay")
		local station = assert(bay:FindFirstChild(string.format("Level%d Queue %02d",level,index)), "Missing exact queue station")
		local base = station:GetAttribute("HologramBase")
		assert(typeof(base) == "CFrame" and (base.Position-(center+vec(record.position))).Magnitude < .001,
			"Queue station moved from fresh manifest")
		-- Presentation attributes are consumed only by the local renderer. No queue
		-- activation, launch, authorization or detector metadata is changed here.
		station:SetAttribute("QueueIdleRingAlpha", .52)
		station:SetAttribute("QueueActiveRingAlpha", .18)
		station:SetAttribute("QueueIdleRingColor", Color3.fromRGB(224,209,154))
		station:SetAttribute("QueueActiveRingColor", Color3.fromRGB(123,231,197))
		station:SetAttribute("QueueHologramLowerAlpha", .74)
		station:SetAttribute("QueueHologramColor", Color3.fromRGB(147,225,202))
		local ring = assert(station:FindFirstChild("Active Queue Ring"), "Missing exact queue ring")
		ring.Transparency, ring.Color = .52, Color3.fromRGB(224,209,154)
		local disc = part(root, string.format("Level%d Pad %d Matte Inlay",level,index), Vector3.new(.018,13.1,13.1),
			base * CFrame.new(0,.017,0) * CFrame.Angles(0,0,math.pi/2), Color3.fromRGB(67,81,74))
		disc.Shape = Enum.PartType.Cylinder
		local floorLabel = part(root, string.format("Level%d Pad %d Number",level,index), Vector3.new(4.2,.01,4.2),
			CFrame.new(base.Position+Vector3.new(0,.044,0)) * CFrame.Angles(0,bayRecords[level].yaw,0), Color3.new())
		floorLabel.Transparency = 1
		local label = text(floorLabel, Enum.NormalId.Top, tostring(index), Color3.fromRGB(222,225,201), Vector2.new(256,256), 110, .85)
		label.TextTransparency = .12
		for _, name in ipairs({"QueueTitle","QueueSubtitle"}) do
			local current = assert(station:FindFirstChild(name,true), "Missing exact live queue label")
			assert(current:IsA("TextLabel"), "Wrong queue label class")
			current.TextWrapped = true
			current.TextStrokeTransparency = .8
		end
	end
	local triangles = 0
	for _, record in ipairs(PROPS) do
		local frame = frames[record.level] * CFrame.new(vec(record.position)) * CFrame.Angles(0,record.yaw,0)
		triangles += addProp(props,kit,record,frame)
	end
	root:SetAttribute("AddedInstancedTriangles", triangles)
	root:SetAttribute("NewPropClones", #PROPS)
	root:SetAttribute("NewUniqueMeshes", 0)
	root:SetAttribute("NewPointLights", 0)
	root:SetAttribute("NewColliders", 0)
	root:SetAttribute("QueuePads", 24)
	root:SetAttribute("PreservedMainSignHosts", 12)
	return root
end
return Module
]====]
local function hash(s)return(E:ComputeStringHash(s,Enum.HashAlgorithm.Sha256):gsub(".",function(c)return string.format("%02x",string.byte(c))end))end
local function exact(parent,name,class)
 local found
 for _,i in ipairs(parent:GetChildren())do if i.Name==name then assert(not found,"Ambiguous owned path "..name);found=i end end
 assert(found and found.ClassName==class,"Missing/wrong exact path "..name);return found
end
local service=game:GetService("ServerScriptService")
local owner=exact(service,"LobbyReimaginedPreview","Folder")
local target=exact(owner,"LobbyPolishBays","ModuleScript")
local before=target.Source
assert(hash(SOURCE)==NEW and SOURCE==before:gsub("\t\t\tobject.RenderFidelity = Enum.RenderFidelity.Precise\n","",1),"Fix exceeds the one reviewed deletion")
local function verify()
 assert(not R:IsRunning() and exact(service,"LobbyReimaginedPreview","Folder")==owner
  and exact(owner,"LobbyPolishBays","ModuleScript")==target,"Exact owned identity changed")
 assert(owner:GetAttribute("LobbyReimaginedOwned")==true and target:GetAttribute("LobbyReimaginedOwned")==true
  and target:GetAttribute("InstalledSourceSHA256")==OLD,"Owned installed helper pin changed")
 assert(hash(target.Source)==OLD and hash(SES:GetEditorSource(target))==OLD,"Fresh Source/editor differs from installed Bays baseline")
end
verify()
SES:UpdateSourceAsync(target,function(current)
 verify();assert(hash(current)==OLD and current==before,"Editor CAS changed")
 return SOURCE
end)
assert(hash(target.Source)==NEW and SES:GetEditorSource(target)==SOURCE,"Scoped fix source/editor readback differs")
target:SetAttribute("InstalledSourceSHA256",NEW)
return {schema="lobby-bays-render-fidelity-edit-cas-v1",path=target:GetFullName(),class=target.ClassName,
 beforeSHA256=OLD,afterSHA256=NEW,sourceBytes=#SOURCE,editorMatch=true,onlyRemovedRuntimeRenderFidelityWrite=true,
 sourceKitRenderFidelityPreserved=true,requiresActualClonePropertyRead=true,DoubleSidedPreserved=true,requiresFreshPlay=true}
