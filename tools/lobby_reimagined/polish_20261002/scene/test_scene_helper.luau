local fs=require("@lune/fs")
local luau=require("@lune/luau")
local serde=require("@lune/serde")
local r=require("@lune/roblox")
local path="tools/lobby_reimagined/polish_20261002/scene/LobbyPolishScene.ModuleScript.candidate.luau"
local source=fs.readFile(path)
luau.compile(source)
local module=luau.load(source,{environment={Instance=r.Instance,Vector3=r.Vector3,Vector2=r.Vector2,CFrame=r.CFrame,Color3=r.Color3,UDim2=r.UDim2,Enum=r.Enum}})()
assert(type(module.Apply)=="function")
local base = "artifacts/lobby-polish-20261002/scene/shop/"
local baseline = serde.decode("json", fs.readFile(base .. "runtime-baseline.json"))
local summary = serde.decode("json", fs.readFile(base .. "runtime-summary.json"))
local edit = serde.decode("json", fs.readFile(base .. "LobbyShopDisplay.edit-baseline.json"))
assert(edit.editorReadOK and edit.source == edit.editorSource, "Shop Source/editor conflict")
local server = serde.decode("json", fs.readFile(base .. "LobbyShopDisplay.server-baseline.json"))
assert(edit.source == server.source, "Shop policy changed between Play/Edit captures")
assert(edit.source:find('return plateUnder(root.Position, current) or r3PlateUnder(root.Position, current)',1,true))
assert(edit.source:find('local FOCUS_POLL = 0.2',1,true))
assert(edit.source:find('local PLATE_HALF_X, PLATE_HALF_Z = 1.60, 1.70',1,true))
local m = r.Instance.new("Model"); m.Name = "LobbyReimaginedPreview"; m:SetAttribute("LobbyReimaginedOwned",true)
local shop = r.Instance.new("Model"); shop.Name = "R3ShopDisplay"; shop.Parent=m
for k,v in pairs(baseline.attrs) do shop:SetAttribute(k,v) end
local lookup = {[baseline.root]=shop}
local originalObjects = {}
for _, row in ipairs(baseline.rows) do
	local parent = assert(lookup[row.path:match("^(.*)%.[^.]+$")],row.path)
	local x = r.Instance.new(row.class); x.Name=row.name; x.Parent=parent; lookup[row.path]=x
	for k,v in pairs(row.attrs) do x:SetAttribute(k,v) end
	if x:IsA("BasePart") then x.CFrame=r.CFrame.new(table.unpack(row.cf)); x.Size=r.Vector3.new(table.unpack(row.size)) end
	if x:IsA("TextLabel") then x.Text=row.text end
	if x:IsA("Light") then x.Enabled=true end
	if x:IsA("SurfaceGui") then x.Face=r.Enum.NormalId[row.face] end
	-- Synthetic distinct URLs verify object/value retention; they are not live asset-ID evidence.
	if x:IsA("ImageLabel") then x.Image="rbxassetid://"..tostring(100000+#originalObjects) end
	if x:IsA("Decal") then x.Texture="rbxassetid://"..tostring(200000+#originalObjects) end
	table.insert(originalObjects,{object=x,attrs=x:GetAttributes(),parent=parent,image=x:IsA("ImageLabel") and x.Image or nil,texture=x:IsA("Decal") and x.Texture or nil,text=x:IsA("TextLabel") and x.Text or nil})
end
local focus=r.Instance.new("Folder");focus.Name="PreviewShopPressurePlates";focus.Parent=m
for _,row in ipairs(summary.focus) do
	local p=r.Instance.new("Part");p.Name=row.name;p.Size=r.Vector3.new(table.unpack(row.size));p.CFrame=r.CFrame.new(table.unpack(row.pos));p:SetAttribute("ShopItemKey",row.key);p.Parent=focus
end
m:SetAttribute("PreviewCenter",r.Vector3.new(220,30,-760));m:SetAttribute("LobbyVisualRevision",4);m:SetAttribute("Ready",false)
local center=m:GetAttribute("PreviewCenter")
local captured=serde.decode("json",fs.readFile("tools/lobby_reimagined/polish_20261002/scene/baseline/runtime-lighting-stage.json"))
local lighting=r.Instance.new("Folder");lighting.Name="PreviewLighting";lighting.Parent=m
for _,row in ipairs(captured.lights)do
 if row.path:find(".PreviewLighting.",1,true)then
  local p=r.Instance.new("Part");p.Name=row.parent;p.Size=r.Vector3.new(.2,.2,.2);p.CFrame=r.CFrame.new(center+r.Vector3.new(table.unpack(row.position)));p.Parent=lighting
  local light=r.Instance.new("PointLight");light.Name=row.name;light.Brightness=row.brightness;light.Range=row.range;light.Enabled=row.enabled;light.Shadows=row.shadows;light.Color=r.Color3.new(table.unpack(row.color));light.Parent=p
 end
end
local collisions=r.Instance.new("Folder");collisions.Name="PreviewCollisions";collisions.Parent=m
for _,row in ipairs(captured.stage)do
 if row.path:find(".PreviewCollisions.",1,true)and(row.name=="Stage Step"or row.name=="Stage Deck"or row.name=="Stage Rear Guard")then
  local p=r.Instance.new("Part");p.Name=row.name;p.Size=r.Vector3.new(table.unpack(row.size));p.CFrame=r.CFrame.new(center+r.Vector3.new(table.unpack(row.position)));p.CanCollide=true;p.Parent=collisions
 end
end
local queues=r.Instance.new("Folder");queues.Name="PreviewQueuePads";queues:SetAttribute("QueueActive",false);queues.Parent=m
local q=r.Instance.new("Part");q.Name="QueueZone1";q.Size=r.Vector3.new(14.82,1,14.82);q.CFrame=r.CFrame.new(157,31.62,-760);q:SetAttribute("R3QueueId",109);q:SetAttribute("QueueRadius",7.41);q.Parent=queues
local gates=r.Instance.new("Folder");gates.Name="LevelGateSigns";gates:SetAttribute("DevStatus","per-viewer-owner");gates.Parent=m
local original=shop:Clone();original.Name="ZyntraShopDisplay"
local sentinelBytes=r.serializeModel({original,collisions,queues,gates})
local lightsBefore=0
for _,x in ipairs(m:GetDescendants())do if x:IsA("Light")then lightsBefore+=1 end end
local changed=module.Apply(m)
assert(changed.Name=="R4ScenePresentation"and changed:GetAttribute("StageGuidanceParts")==20)
assert(changed:GetAttribute("ChangedExistingEmitters")==36 and changed:GetAttribute("DisabledShopGlows")==10)
assert(changed:GetAttribute("ShopCards")==10 and changed:GetAttribute("AddedInstancedTriangles")==408)
assert(changed:GetAttribute("AddedPointLights")==0 and changed:GetAttribute("AddedColliders")==0)
assert(r.serializeModel({original,collisions,queues,gates})==sentinelBytes,"Colliders/queues/gates/original shop changed")
local lightsAfter,enabled=0,0
for _,x in ipairs(m:GetDescendants())do
 if x:IsA("Light")then lightsAfter+=1;if x.Enabled then enabled+=1 end end
 if x:IsA("BasePart")and x:GetAttribute("LobbyPolishScene20261002Owned")==true and x:IsDescendantOf(changed)then
  assert(not x.CanCollide and not x.CanTouch and not x.CanQuery,"New guidance became collision")
 end
end
assert(lightsBefore==87 and lightsAfter==87 and enabled==77,"Emitter count changed")
for _,before in ipairs(originalObjects)do
 local x=before.object;assert(x.Parent==before.parent,"Original clone objects deleted/reparented")
 for k,v in pairs(before.attrs)do assert(x:GetAttribute(k)==v,"Changed product attribute "..k)end
 if before.image then assert(x.Image==before.image)end
 if before.texture then assert(x.Texture==before.texture)end
 if before.text then assert(x.Text==before.text)end
end
for _,stand in ipairs(shop:GetChildren())do
 if stand:IsA("Model")and stand:GetAttribute("ShopItemKey")then
  local key=stand:GetAttribute("ShopItemKey")
  local match=focus:FindFirstChild(key)
  assert(match and match:GetAttribute("ShopItemKey")==key and match.CFrame==stand.ShopPressurePlate.CFrame and match.Size==stand.ShopPressurePlate.Size,"Focus copy drift")
 end
end
local function coverage(x,y,z,name)
 local best=math.huge
 for _,p in ipairs(lighting:GetChildren())do if p.Name==name then
  local light=p:FindFirstChild("Preview Fill")
  best=math.min(best,(p.CFrame.Position-center-r.Vector3.new(x,y,z)).Magnitude/light.Range)
 end end
 return best
end
local maxRoad=0
for z=-120,120,10 do maxRoad=math.max(maxRoad,coverage(0,3.5,z,"Tunnel Lamp"))end
assert(maxRoad<.73,"Road avatar center outside targeted sphere envelope")
local maxTread=0
for i=1,6 do maxTread=math.max(maxTread,coverage(0,i*.75,104.5+i,"Stage Fill"))end
assert(maxTread<.65,"Stair centers outside stage fill envelope")
assert(coverage(0,28,134,"Stage Fill")>1,"Upper furniture crown still receives stage fill")
local repeatOK=pcall(module.Apply,m)
assert(not repeatOK,"Existing scene owner should refuse a second construction apply")
local receipt={status="PASS",scope="Exact helper syntax and execution against a Lune reconstruction of captured scene/shop; geometry/reference/emitter ownership only, no Studio rendering/gameplay/performance pass",sha256=serde.hash("sha256",source),bytes=#source,stageGuidanceParts=20,shopCards=10,newPrimitiveParts=34,addedPrimitiveTriangles=408,newUniqueMeshes=0,newColliders=0,newEmitters=0,changedExistingEmitters=36,disabledShopGlows=10,totalEmittersBefore=lightsBefore,totalEmittersAfter=lightsAfter,enabledEmittersAfter=enabled,originalShopCollidersQueuesGatesSerializedIdentical=true,existingArtObjectsSyntheticIdsAndCommerceAttributesRetained=true,focusCopiesMatch=true,maxRoadAvatarDistanceOverRange=maxRoad,maxStageTreadDistanceOverRange=maxTread,upperCrownOutsideStageLightRanges=true,refusesSecondBuildApply=true,liveAssetIdsPendingReadback=true}
fs.writeFile("artifacts/lobby-polish-20261002/scene/helper-validation.json",serde.encode("json",receipt,true))
print(serde.encode("json",receipt))
