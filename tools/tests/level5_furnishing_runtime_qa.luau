-- Read-only inspection of the generated Level 5 map. Prints one compact JSON record.
-- No services are mutated, no modules are required, and no yields are performed.
local HttpService = game:GetService("HttpService")
local report = {
	qa="Level5MoldRuntime",version="2026-09-25.window-watcher.1",pass=false,
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
local homes,houseSet,groups,windows,murals,molds={},{},{},{},{},{}
local oldAssetReferences=0
local oldDrawingAssets={"114474831346440","108980796139348"}
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
	if object:IsA("BasePart") and object.Name=="WindowGlass" then
		check(object:GetAttribute("Level5TintedWindow")==true,"UNTAGGED_WINDOW",object)
	end
	if object:GetAttribute("Level5WallDrawing")~=nil then table.insert(murals,object) end
	if object:GetAttribute("Level5WallMold")==true then table.insert(molds,object) end
	if object:IsA("Decal") or object:IsA("Texture") then
		for _,asset in ipairs(oldDrawingAssets) do
			if string.find(object.Texture,asset,1,true) then
				oldAssetReferences+=1
				check(false,"OLD_DRAWING_ASSET_REMAINS",object,asset)
			end
		end
	end
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
-- F's 2026-09-25 Window Watcher court rebuild changes the total to 202 panes.
check(#windows==202,"TINTED_WINDOW_COUNT",root,tostring(#windows))
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

local moldAssets={
	rising="rbxassetid://111130507669211",
	corner="rbxassetid://84997095468417",
	seam="rbxassetid://119550867817499",
}
local expectedMolds={
	VillageFloorSpread={variant="corner",origin="Floor corner",wall="DistrictSideWall"},
	CanyonRearRising={variant="rising",origin="Floor seam",wall="ThresholdSideWall"},
	CanyonWestRising={variant="rising",origin="Floor seam",wall="DistrictSideWall"},
	SubdivisionTerraceSpread={variant="corner",origin="Raised terrace floor",wall="DistrictSideWall"},
	CanyonUpperSeam={variant="seam",origin="Upper wall seam",wall="DistrictSideWall"},
	SubdivisionUpperSeam={variant="seam",origin="Upper wall seam",wall="DistrictSideWall"},
	ArcadeDampCorner={variant="corner",origin="Low wall corner",wall="ThresholdSideWall"},
	DomesticCeilingSeam={variant="seam",origin="Ceiling seam",wall="ThresholdSideWall"},
}
report.counts.oldDrawingAttributes=#murals
report.counts.oldDrawingAssetReferences=oldAssetReferences
check(#murals==0,"OLD_DRAWING_ATTRIBUTES_REMAIN",root,tostring(#murals))
check(root:GetAttribute("TallWallDrawingCount")==0,"OLD_DRAWING_COUNT_ATTRIBUTE",root)
check(#molds==8 and root:GetAttribute("WallMoldCount")==8,"MOLD_COUNT",root,tostring(#molds))
check(root:GetAttribute("WallMoldVariantCount")==3,"MOLD_VARIANT_COUNT_ATTRIBUTE",root)
local rayParams=RaycastParams.new()
rayParams.FilterType=Enum.RaycastFilterType.Include
rayParams.FilterDescendantsInstances={root}
rayParams.IgnoreWater=true
-- Baseboards and decals are noncollidable decoration. Inspect solid wall backing.
rayParams.RespectCanCollide=true
local moldNames,usedVariants,usedAssets={},{},{}
local moldDecals,backedCarriers,backingRays=0,0,0
report.molds={}
table.sort(molds,function(a,b)return a.Name<b.Name end)
for _,mold in ipairs(molds) do
	local before=report.failureCount
	local expected=expectedMolds[mold.Name]
	local variant=mold:GetAttribute("MoldVariant")
	local row={name=mold.Name,variant=variant,backingRays=0,pass=false}
	check(not moldNames[mold.Name],"DUPLICATE_MOLD_NAME",mold);moldNames[mold.Name]=true
	check(expected~=nil,"UNEXPECTED_MOLD_NAME",mold)
	check(mold:IsA("BasePart"),"MOLD_CARRIER_CLASS",mold)
	if expected then
		check(variant==expected.variant,"MOLD_VARIANT",mold,tostring(variant))
		check(mold:GetAttribute("GrowthOrigin")==expected.origin,"MOLD_GROWTH_ORIGIN",mold)
	end
	if type(variant)=="string" then usedVariants[variant]=true end
	if mold:IsA("BasePart") then
		check(mold.Anchored and mold.Transparency==1 and not mold.CanCollide and not mold.CanQuery and not mold.CanTouch and not mold.CastShadow,"MOLD_CARRIER_FLAGS",mold)
		check(mold:GetAttribute("AlphaBackground")==true,"MOLD_ALPHA_ATTRIBUTE",mold)
		check(mold.Size.X>0 and mold.Size.Y>0 and mold.Size.Z>0 and mold.Size.Z<=.02,"MOLD_FLAT_CARRIER_SIZE",mold)
		check(mold.Parent and mold.Parent.Name=="MyceliumWallGrowth","MOLD_CONTAINER",mold)
		check(mold.Material~=Enum.Material.Neon,"MOLD_EMISSION",mold)
		local decals={}
		for _,child in ipairs(mold:GetChildren()) do
			if child:IsA("Decal") then table.insert(decals,child) end
			check(not child:IsA("Light"),"MOLD_LIGHT",child)
		end
		check(#decals==1,"MOLD_DECAL_COUNT",mold,tostring(#decals))
		for _,decal in ipairs(decals) do
			moldDecals+=1;usedAssets[decal.Texture]=true
			check(decal.Name=="DarkMyceliumOnPlaster" and decal.Texture==moldAssets[variant],"MOLD_DECAL_ASSET",decal)
			local tint=Color3.fromRGB(168,164,150)
			check(decal.Face==Enum.NormalId.Front and math.abs(decal.Transparency-.04)<.00001,"MOLD_DECAL_DISPLAY",decal)
			check(math.abs(decal.Color3.R-tint.R)<.00001 and math.abs(decal.Color3.G-tint.G)<.00001 and math.abs(decal.Color3.B-tint.B)<.00001,"MOLD_DECAL_TINT",decal)
		end
		-- Nine short rays cover the center, four near-corners and edge midpoints.
		-- Their direction is opposite the decal's Front normal. A room-facing,
		-- nearly flush carrier must hit an inward-facing solid named wall, never
		-- a door, window, floor, external face, or a distant object across a gap.
		local normal=mold.CFrame.LookVector
		local rayPass=true
		local backing=nil
		local maxGap=0
		local offsets={-1,0,1}
		for _,sx in ipairs(offsets) do for _,sy in ipairs(offsets) do
			local p=mold.CFrame:PointToWorldSpace(Vector3.new(sx*math.max(0,mold.Size.X/2-.03),sy*math.max(0,mold.Size.Y/2-.03),0))
			local hit=workspace:Raycast(p+normal*.2,-normal*.6,rayParams)
			backingRays+=1;row.backingRays+=1
			local valid=hit~=nil
			check(valid,"MOLD_BACKING_MISSING",mold,tostring(sx)..","..tostring(sy))
			if hit then
				local wall=hit.Instance
				local gap=hit.Distance-.2
				maxGap=math.max(maxGap,gap)
				local named=expected~=nil and wall.Name==expected.wall and wall.Parent and wall.Parent.Name=="Enclosure"
				local solid=wall:IsA("BasePart") and wall.Anchored and wall.CanCollide and wall.Transparency<1
				local inward=hit.Normal:Dot(normal)>.995
				local flush=gap>=-.015 and gap<=.18
				check(named,"MOLD_WRONG_BACKING_WALL",mold,wall:GetFullName())
				check(solid,"MOLD_NONSOLID_BACKING",mold,wall:GetFullName())
				check(inward,"MOLD_OUTSIDE_OR_ANGLED",mold,tostring(hit.Normal:Dot(normal)))
				check(flush,"MOLD_NOT_FLUSH",mold,tostring(gap))
				if backing then check(backing==wall,"MOLD_STRADDLES_WALL_OR_OPENING",mold,wall:GetFullName()) else backing=wall end
				valid=named and solid and inward and flush and wall==backing
			end
			rayPass=rayPass and valid
		end end
		if rayPass then backedCarriers+=1 end
		row.backing=backing and backing:GetFullName() or ""
		row.maxWallGap=math.floor(maxGap*10000+.5)/10000
	end
	row.pass=report.failureCount==before
	table.insert(report.molds,row)
end
local variantCount,assetCount=0,0
for _ in pairs(usedVariants) do variantCount+=1 end
for _ in pairs(usedAssets) do assetCount+=1 end
check(variantCount==3 and assetCount==3,"MOLD_DISTINCT_VARIANTS_ASSETS",root,tostring(variantCount).."/"..tostring(assetCount))
check(moldDecals==8 and backedCarriers==8 and backingRays==72,"MOLD_BACKING_TOTAL",root,tostring(moldDecals).."/"..tostring(backedCarriers).."/"..tostring(backingRays))
for name in pairs(expectedMolds) do check(moldNames[name]==true,"EXPECTED_MOLD_MISSING",root,name) end
report.counts.molds=#molds
report.counts.moldDecals=moldDecals
report.counts.moldVariants=variantCount
report.counts.moldAssets=assetCount
report.counts.moldBackedCarriers=backedCarriers
report.counts.moldBackingRays=backingRays
report.moldAlphaCheck="Transparent carrier flags, alpha attribute and exact uploaded asset references; image alpha is verified separately."
finish()
