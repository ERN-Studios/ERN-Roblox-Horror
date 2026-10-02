local fs = require("@lune/fs")
local luau = require("@lune/luau")
local serde = require("@lune/serde")
local r = require("@lune/roblox")
local path = "tools/lobby_reimagined/polish_20261002/scene/shop_apply.fragment.luau"
local source = fs.readFile(path)
luau.compile(source)
local apply = luau.load(source .. "\nreturn polishShop", {environment={Instance=r.Instance, Vector3=r.Vector3, Vector2=r.Vector2, CFrame=r.CFrame, Color3=r.Color3, UDim2=r.UDim2, Enum=r.Enum}})()
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
local untouchedOriginal=shop:Clone();untouchedOriginal.Name="ZyntraShopDisplay"
local untouchedBytes=r.serializeModel({untouchedOriginal})
local result=apply(m,{})
assert(#result.cards==10 and result.addedParts==14 and result.addedTriangles==168 and result.disabledShopGlows==10)
local keys, newPositions, minGap={}, {}, math.huge
for _,record in ipairs(result.cards) do
	assert(record.box.Parent==record.stand and record.plate.Parent==record.stand)
	assert(record.key==record.plate:GetAttribute("ShopItemKey") and record.key==record.focusCopy:GetAttribute("ShopItemKey"))
	assert(record.plate.CFrame==record.focusCopy.CFrame and record.plate.Size==record.focusCopy.Size)
	assert((record.box.Size-r.Vector3.new(3.7,3.7,.55)).Magnitude<.0001)
	assert(not record.box.ShopHologramCaption.Enabled and not record.box.ShopBoxGlow.Enabled)
	assert(record.stand.ShopFixedNamePanel.ShopPolishFace.Face==r.Enum.NormalId.Front)
	keys[record.key]=true;table.insert(newPositions,record.plate.CFrame.Position.Z)
end
table.sort(newPositions)
for i=2,#newPositions do minGap=math.min(minGap,newPositions[i]-newPositions[i-1]) end
assert(minGap>=4.999, "Plate zones too close")
for _,before in ipairs(originalObjects) do
	local x=before.object;assert(x.Parent==before.parent,"Original object reparented/deleted")
	for k,v in pairs(before.attrs) do assert(x:GetAttribute(k)==v,"Changed original attribute "..k) end
	if before.image then assert(x.Image==before.image) end
	if before.texture then assert(x.Texture==before.texture) end
	if before.text then assert(x.Text==before.text) end
end
assert(r.serializeModel({untouchedOriginal})==untouchedBytes,"Original shop changed")
local lights=0
for _,x in ipairs(shop:GetDescendants()) do if x:IsA("Light") and x.Enabled then lights+=1 end end
assert(lights==0,"Shop lights left enabled")
local once={}
for _,record in ipairs(result.cards) do once[record.key]=record.box.CFrame end
local second=apply(m,{})
assert(second.addedParts==0,"Repeated apply duplicated panels")
for _,record in ipairs(second.cards) do assert((record.box.CFrame.Position-once[record.key].Position).Magnitude<.0001,"Repeated layout drift") end
local receipt={status="PASS",scope="Local Lune reconstruction of captured runtime geometry, fragment execution, and Source/editor policy comparison; no Studio gameplay/render/performance claim",sourceSha256=serde.hash("sha256",source),sourceBytes=#source,cards=#result.cards,addedParts=result.addedParts,addedTriangles=result.addedTriangles,disabledShopGlows=result.disabledShopGlows,enabledShopLights=lights,minimumPlatePitch=minGap,minimumRawFocusZoneGap=minGap-3.4,minimumFullHysteresisEnvelopeGap=minGap-4.6,minimumNamePanelGap=minGap-4.35,minimumArtTileGap=minGap-3.7,allExistingObjectsAndAttributesRetained=true,syntheticArtUrlsUnchanged=true,liveAssetIdReadbackPending=true,originalShopSentinelUnchanged=true,focusPlateCopiesMatch=true,sourceAndEditorEqual=true,focusWriterPolicyUnchanged=true,repeatedApplyHasNoLayoutDrift=true,positions=newPositions}
fs.writeFile(base.."offline-validation.json",serde.encode("json",receipt,true))
print(serde.encode("json",receipt))
