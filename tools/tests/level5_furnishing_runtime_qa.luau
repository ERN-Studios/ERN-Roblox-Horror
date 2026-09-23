-- Read-only inspection of the generated Level 5 map. Prints one compact JSON record.
-- No services are mutated, no modules are required, and no yields are performed.
local HttpService = game:GetService("HttpService")
local report = {
	qa="Level5FurnitureRuntime",version="2026-09-24.2",pass=false,
	failureCount=0,failures={},counts={},rooms={},
}
local MAX_DESCENDANTS, MAX_FAILURES, EPS = 60000, 50, .015
local function check(ok, code, object, detail)
	if ok then return end
	report.failureCount+=1
	if #report.failures<MAX_FAILURES then
		table.insert(report.failures,{code=code,path=object and object:GetFullName() or "",detail=detail or ""})
	end
end
local function finish()
	report.pass=report.failureCount==0
	report.failuresOmitted=math.max(0,report.failureCount-#report.failures)
	print(HttpService:JSONEncode(report))
end
local world=workspace:FindFirstChild("Level 5 Generated World")
check(world~=nil,"WORLD_MISSING")
if not world then finish();return end
local descendants=world:GetDescendants()
report.counts.worldDescendants=#descendants
check(#descendants<=MAX_DESCENDANTS,"DESCENDANT_BOUND",world,tostring(#descendants))
if #descendants>MAX_DESCENDANTS then finish();return end
local architectureRoots={}
local worldParts=0
for _,object in ipairs(descendants) do
	if object.Name=="Level5_IndoorSuburbs" and object:IsA("Model") then table.insert(architectureRoots,object) end
	if object:IsA("BasePart") then worldParts+=1 end
end
report.counts.worldParts=worldParts
check(#architectureRoots==1,"ARCHITECTURE_ROOT_COUNT",world,tostring(#architectureRoots))
if #architectureRoots~=1 then finish();return end
local root=architectureRoots[1]
local objects=root:GetDescendants()
report.counts.architectureDescendants=#objects
local homes,houseSet,groups,windows,murals={},{},{},{},{}
local parts,lights,neon,houseCount=0,0,0,0
local variantNames={"SofaTVLounge","ReadingCorner","DiningRoom","JoinedChairs","SparseSittingRoom"}
for _,object in ipairs(objects) do
	if object:IsA("BasePart") then
		parts+=1
		if object.Material==Enum.Material.Neon then neon+=1 end
	end
	if object:IsA("Light") then lights+=1 end
	if object:IsA("Model") then
		if object:GetAttribute("HouseLighting")~=nil then
			houseSet[object]=true;houseCount+=1
			check(object:GetAttribute("HouseLighting")=="None","HOUSE_LIGHTING_ATTRIBUTE",object)
		end
		if object:GetAttribute("Level5FurnitureVersion")~=nil then
			table.insert(homes,object);houseSet[object]=true
		end
		if object.Name=="DomesticFurniture" then table.insert(groups,object) end
	end
	if object:GetAttribute("Level5TintedWindow")==true then table.insert(windows,object) end
	if object.Name=="WindowGlass" then
		check(object:GetAttribute("Level5TintedWindow")==true,"UNTAGGED_WINDOW",object)
	end
	if object:GetAttribute("Level5WallDrawing")==true then table.insert(murals,object) end
end
report.counts.architectureParts=parts
report.counts.architectureLights=lights
report.counts.architectureNeon=neon
report.counts.houseModels=houseCount
report.counts.furnishedHomes=#homes
report.counts.furnitureGroups=#groups
check(root:GetAttribute("PartCount")==parts,"PART_COUNT_ATTRIBUTE",root,tostring(root:GetAttribute("PartCount")))
check(root:GetAttribute("LightCount")==lights,"LIGHT_COUNT_ATTRIBUTE",root,tostring(root:GetAttribute("LightCount")))
check(#homes==20,"FURNISHED_HOME_COUNT",root,tostring(#homes))
check(root:GetAttribute("Level5FurnishedHomeCount")==#homes,"FURNISHED_COUNT_ATTRIBUTE",root)
check(#groups==#homes,"FURNITURE_GROUP_TOTAL",root,tostring(#groups))

-- Every furniture corner is transformed back through the actual stored world
-- room frame. This checks placement after house rotations and world offsets.
table.sort(homes,function(a,b)return a:GetFullName()<b:GetFullName()end)
local furnitureParts,checkedCorners,tvFronts,tvDecals,glitchedTables=0,0,0,0,0
for _,home in ipairs(homes) do
	local row={name=home.Name,variant=home:GetAttribute("Level5FurnitureVariant"),parts=0,pieces=0,pass=true}
	local before=report.failureCount
	local frame,size=home:GetAttribute("FurnitureRoomFrame"),home:GetAttribute("FurnitureRoomSize")
	local validFrame=typeof(frame)=="CFrame"
	local validSize=typeof(size)=="Vector3" and size.X>=18 and size.Y>=9 and size.Z>=10.5
	check(validFrame,"ROOM_FRAME_ATTRIBUTE",home)
	check(validSize,"ROOM_SIZE_ATTRIBUTE",home)
	check(home:GetAttribute("Level5FurnitureVersion")=="2026-09-24.2","FURNITURE_VERSION",home)
	local ownGroups={}
	for _,child in ipairs(home:GetChildren()) do
		if child.Name=="DomesticFurniture" then table.insert(ownGroups,child) end
	end
	check(#ownGroups==1,"DUPLICATE_OR_MISSING_GROUP",home,tostring(#ownGroups))
	if #ownGroups==1 then
		local group=ownGroups[1]
		check(group:IsA("Model"),"FURNITURE_GROUP_CLASS",group)
		check(group:GetAttribute("FurnitureVersion")=="2026-09-24.2","GROUP_VERSION",group)
		check(group:GetAttribute("Variant")==row.variant,"GROUP_VARIANT",group)
		check(group:GetAttribute("VariantName")==variantNames[row.variant],"GROUP_VARIANT_NAME",group)
		check(group:GetAttribute("ReservedCenterRouteWidth")==7,"ROUTE_WIDTH_ATTRIBUTE",group)
		for _,piece in ipairs(group:GetChildren()) do
			if piece:IsA("Model") then row.pieces+=1 end
		end
		for _,object in ipairs(group:GetDescendants()) do
			if object:GetAttribute("GlitchedTable")==true then glitchedTables+=1 end
			if object:IsA("BasePart") then
				row.parts+=1;furnitureParts+=1
				check(object.Anchored,"UNANCHORED_FURNITURE",object)
				check(object.Size.X>0 and object.Size.Y>0 and object.Size.Z>0,"NONPOSITIVE_FURNITURE_SIZE",object)
				if not object.CanCollide then check(not object.CanQuery and not object.CanTouch,"TRIM_QUERY_OR_TOUCH",object) end
				if validFrame and validSize then
					local lo,hi=Vector3.new(math.huge,math.huge,math.huge),Vector3.new(-math.huge,-math.huge,-math.huge)
					for _,sx in ipairs({-1,1}) do for _,sy in ipairs({-1,1}) do for _,sz in ipairs({-1,1}) do
						local corner=object.CFrame:PointToWorldSpace(Vector3.new(sx*object.Size.X/2,sy*object.Size.Y/2,sz*object.Size.Z/2))
						local p=frame:PointToObjectSpace(corner)
						lo=Vector3.new(math.min(lo.X,p.X),math.min(lo.Y,p.Y),math.min(lo.Z,p.Z))
						hi=Vector3.new(math.max(hi.X,p.X),math.max(hi.Y,p.Y),math.max(hi.Z,p.Z))
						checkedCorners+=1
					end end end
					check(lo.X>=-size.X/2+.3-EPS and hi.X<=size.X/2-.3+EPS,"FURNITURE_SIDE_WALL",object)
					check(lo.Z>=.6-EPS and hi.Z<=size.Z-.6+EPS,"FURNITURE_DOOR_PLANE",object)
					check(lo.Y>=-.025-EPS and hi.Y<=size.Y-.5+EPS,"FURNITURE_VERTICAL_BOUNDS",object)
					check(hi.X<=-3.5+EPS or lo.X>=3.5-EPS,"FURNITURE_CENTER_ROUTE",object)
				end
				if object.Name=="FullCRTFrontPanel" then
					tvFronts+=1
					check(math.abs(object.Size.X/object.Size.Y-4/3)<.001,"TV_FRONT_ASPECT",object)
					check(object:GetAttribute("ScreenState")=="Off","TV_SCREEN_STATE",object)
				end
				check(object.Name~="OffCRTGlass" and object.Name~="CRTControlDial" and object.Name~="CRTFrontVent","OLD_DUPLICATED_TV_FRONT",object)
			elseif object:IsA("Decal") and object.Name=="CompleteCRTFrontPanel" then
				tvDecals+=1
				check(object.Parent and object.Parent.Name=="FullCRTFrontPanel","TV_DECAL_PARENT",object)
				check(object.Texture=="rbxassetid://129933596500815","TV_DECAL_ASSET",object)
				check(object.Face==Enum.NormalId.Front and object.Transparency==0 and object.Color3==Color3.new(1,1,1),"TV_DECAL_DISPLAY",object)
			end
		end
		check(row.parts<=100,"ROOM_PART_BUDGET",group,tostring(row.parts))
		check(row.pieces>=2 and row.pieces<=4,"ROOM_PIECE_COUNT",group,tostring(row.pieces))
		check(group:GetAttribute("PartCount")==row.parts,"ROOM_PART_COUNT_ATTRIBUTE",group)
		check(group:GetAttribute("FurniturePieceCount")==row.pieces,"ROOM_PIECE_COUNT_ATTRIBUTE",group)
	end
	row.pass=report.failureCount==before
	table.insert(report.rooms,row)
end
for _,group in ipairs(groups) do
	check(group.Parent and group.Parent:GetAttribute("Level5FurnitureVersion")~=nil,"ORPHAN_FURNITURE_GROUP",group)
end
report.counts.furnitureParts=furnitureParts;report.counts.checkedFurnitureCorners=checkedCorners
report.counts.tvFronts=tvFronts;report.counts.tvDecals=tvDecals;report.counts.glitchedTables=glitchedTables
check(tvFronts>0 and tvFronts==tvDecals,"TV_FRONT_DECAL_TOTAL",root)
check(glitchedTables==1,"GLITCHED_TABLE_COUNT",root,tostring(glitchedTables))

local houseNeon,houseLights=0,0
for _,object in ipairs(objects) do
	local luminous=object:IsA("Light") or (object:IsA("BasePart") and object.Material==Enum.Material.Neon)
	if luminous then
		local ancestor=object.Parent
		for _=1,32 do
			if not ancestor or ancestor==root then break end
			if houseSet[ancestor] then
				if object:IsA("Light") then houseLights+=1 else houseNeon+=1 end
				check(false,"LUMINOUS_HOUSE_CONTENT",object)
				break
			end
			ancestor=ancestor.Parent
		end
	end
end
report.counts.houseNeon=houseNeon;report.counts.houseLights=houseLights
report.counts.tintedWindows=#windows
check(#windows==356,"TINTED_WINDOW_COUNT",root,tostring(#windows))
check(root:GetAttribute("TintedWindowCount")==#windows,"WINDOW_COUNT_ATTRIBUTE",root)
local tint=Color3.fromRGB(87,102,102)
for _,window in ipairs(windows) do
	check(window:IsA("BasePart"),"WINDOW_CLASS",window)
	if window:IsA("BasePart") then
		check(window.Material==Enum.Material.Glass,"WINDOW_MATERIAL",window)
		check(math.abs(window.Color.R-tint.R)<.00001 and math.abs(window.Color.G-tint.G)<.00001 and math.abs(window.Color.B-tint.B)<.00001,"WINDOW_TINT",window)
		check(math.abs(window.Transparency-.2)<.00001 and math.abs(window.Reflectance)<.00001,"WINDOW_OPTICS",window)
		for _,child in ipairs(window:GetDescendants()) do check(not child:IsA("Light"),"WINDOW_LIGHT",child) end
	end
end

local muralAssets={
	VillageHouseDrawing="rbxassetid://114474831346440",CanyonHouseDrawing="rbxassetid://114474831346440",
	CanyonStairDrawing="rbxassetid://108980796139348",SubdivisionStairDrawing="rbxassetid://108980796139348",
}
local muralNames,muralDecals={},0
report.counts.murals=#murals
check(#murals==4 and root:GetAttribute("TallWallDrawingCount")==4,"MURAL_COUNT",root,tostring(#murals))
for _,mural in ipairs(murals) do
	check(not muralNames[mural.Name],"DUPLICATE_MURAL_NAME",mural);muralNames[mural.Name]=true
	check(muralAssets[mural.Name]~=nil,"UNEXPECTED_MURAL_NAME",mural)
	check(mural:IsA("BasePart"),"MURAL_CARRIER_CLASS",mural)
	if mural:IsA("BasePart") then
		check(mural.Transparency==1 and not mural.CanCollide and not mural.CanQuery and not mural.CanTouch and not mural.CastShadow,"MURAL_CARRIER_FLAGS",mural)
		check(mural:GetAttribute("AlphaBackground")==true,"MURAL_ALPHA_ATTRIBUTE",mural)
		local decals={}
		for _,child in ipairs(mural:GetChildren()) do if child:IsA("Decal") then table.insert(decals,child) end end
		check(#decals==1,"MURAL_DECAL_COUNT",mural,tostring(#decals))
		for _,decal in ipairs(decals) do
			muralDecals+=1
			check(decal.Name=="CharcoalOnPlaster" and decal.Texture==muralAssets[mural.Name],"MURAL_DECAL_ASSET",decal)
			check(decal.Face==Enum.NormalId.Front and math.abs(decal.Transparency-.08)<.00001,"MURAL_DECAL_DISPLAY",decal)
		end
	end
end
report.counts.muralDecals=muralDecals
report.muralAlphaCheck="Carrier flags, alpha attribute and exact uploaded asset references; image pixels require visual inspection."
finish()
