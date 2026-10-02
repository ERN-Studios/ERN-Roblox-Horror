-- Apply once to the newly constructed owned R4 model, after end furniture exists.
-- Static templates live under this module. No runtime image allocation or global effects.
local HS = game:GetService("HttpService")
local SS = game:GetService("ServerStorage")
local RunService = game:GetService("RunService")
local Module = {}
local OWNED = "LobbyReimaginedOwned"
local REVISION = "R4-MaterialPolish-20261002"
local BASELINE = "17b68efc473a0f100cf6ce6b9389332a5f2a87d82faf7694a0536a82483bc995"
local SPEC = HS:JSONDecode(__ASSET_SPEC__)
local KNOWN = HS:JSONDecode(__CHUNK_SPEC__)
local SINGLE_SIDED = HS:JSONDecode(__SINGLE_SIDED_SPEC__)
local AUTOMATIC = HS:JSONDecode(__AUTOMATIC_SPEC__)
local CONTENT_PROPERTY = {color="ColorMapContent", normal="NormalMapContent", roughness="RoughnessMapContent"}

local function uri(content)
	assert(typeof(content)=="Content" and content.SourceType==Enum.ContentSourceType.Uri,"Unpublished static material content")
	assert(content.Uri:match("^rbxassetid://[1-9]%d*$"),"Static material must use a published URI")
	return content.Uri
end

local function appearances(part)
	local result={}
	for _,child in ipairs(part:GetChildren()) do
		if child:IsA("SurfaceAppearance") then table.insert(result,child) end
	end
	return result
end

local function furnitureOwner(part,root)
	local cursor=part
	while cursor and cursor~=root do
		if (cursor.Name:match("^South Embedded 0[678]%-") or cursor.Name:match("^NorthDJ Embedded 0[678]%-"))
			and (cursor:GetAttribute("EndClutterFamily")=="FilingCabinet" or cursor:GetAttribute("EndClutterFamily")=="Desk"
				or cursor:GetAttribute("EndClutterFamily")=="Sofa" or cursor:GetAttribute("EndClutterFamily")=="VinylBench") then
			return cursor
		end
		cursor=cursor.Parent
	end
	return nil
end

local function tintFor(part,root,key)
	if key=="asphalt_road" then return Color3.new(1,1,1) end
	local p=root:GetPivot():PointToObjectSpace(part.Position)
	local minimum=key=="tunnel_concrete" and .947 or .97
	local value=minimum+(1-minimum)*(.5+.5*math.sin(p.X*.173+p.Z*.087+part.Size.Y*.37))
	return Color3.new(value,value,value)
end

function Module.AssetSpec()
	-- Read-only contract for the guarded Edit installer; IDs must be uploaded,
	-- pinned and represented by matching static templates before Apply can run.
	return HS:JSONDecode(HS:JSONEncode(SPEC))
end

function Module.Apply(root,options)
	options=options or {}
	assert(not RunService:IsClient(),"R4 material polish is server-only")
	assert(game.PlaceId==131311258779917 and game.GameId==10559217407 and game.CreatorId==1039373905,"Wrong material polish place/owner")
	assert(script:GetAttribute(OWNED)==true,"Unowned material helper")
	assert(root and root:IsA("Model") and root.Name=="LobbyReimaginedPreview" and root:GetAttribute(OWNED)==true,"Unowned R4 model")
	assert(root:GetAttribute("LobbyVisualRevision")==4 and root:GetAttribute("IsolatedDesignPreview")==true
		and root:GetAttribute("PreviewCenter")==Vector3.new(220,30,-760),"Wrong R4 visual baseline")
	assert(root.Parent==nil or root.Parent==workspace,"Wrong R4 model parent")
	local previous=root:GetAttribute("MaterialPolishRevision")
	if previous then
		assert(previous==REVISION,"Conflicting R4 material revision")
		return {AlreadyApplied=true,Revision=previous}
	end
	assert(options.OptimizeBackfaces==nil or type(options.OptimizeBackfaces)=="boolean","Invalid backface option")
	assert(options.AutomaticFidelity==nil or type(options.AutomaticFidelity)=="boolean","Invalid fidelity option")
	local source=assert(SS:FindFirstChild("LobbyReimaginedBlenderSource20261001R4"),"R4 raw source missing")
	assert(source:GetAttribute(OWNED)==true and source:GetAttribute("Ready")==true
		and source:GetAttribute("ManifestSHA256")==BASELINE,"Material baseline manifest changed")
	local folder=assert(script:FindFirstChild("StaticPBRMaterials"),"Publish and install static polish material templates first")
	assert(folder:IsA("Folder") and folder:GetAttribute(OWNED)==true and folder:GetAttribute("Ready")==true,"Incomplete polish materials")
	assert(#folder:GetChildren()==3,"Expected exactly three polish PBR templates")
	local templates={}
	for key,mapSpec in pairs(SPEC.materials) do
		local template=assert(folder:FindFirstChild(key),"Missing material template "..key)
		assert(template:IsA("SurfaceAppearance") and template:GetAttribute(OWNED)==true
			and template.AlphaMode==Enum.AlphaMode.Overlay and template.Color==Color3.new(1,1,1),"Invalid polish template "..key)
		assert(template.MetalnessMapContent.SourceType==Enum.ContentSourceType.None,"Concrete/asphalt must be dielectric")
		for role,property in pairs(CONTENT_PROPERTY) do
			assert(template:GetAttribute(role.."PNG_SHA256")==mapSpec[role].pngSHA256,"Candidate PNG hash changed "..key.."/"..role)
			uri(template[property])
		end
		templates[key]=template
	end
	local atlas=assert(script:FindFirstChild("SidewalkAtlas"),"Published sidewalk-specific atlas missing")
	assert(atlas:IsA("StringValue") and atlas:GetAttribute(OWNED)==true and atlas.Value:match("^[1-9]%d*$")
		and atlas:GetAttribute("PNG_SHA256")==SPEC.sidewalkAtlas.pngSHA256,"Invalid sidewalk-specific atlas")
	local visuals=assert(root:FindFirstChild("BlenderVisuals"),"Missing owned R4 visuals")
	local pbr,sidewalk,furniture,backfaces,fidelity={},{},{},{},{}
	for _,part in ipairs(visuals:GetDescendants()) do
		if part:IsA("MeshPart") and part:GetAttribute(OWNED)==true then
			local hash=part:GetAttribute("BlenderSourceSHA256")
			local chunk=KNOWN[hash]
			if chunk then
				assert(part:GetAttribute("BlenderTriangles")==chunk.triangles,"Material mesh metadata changed")
				local key=part:GetAttribute("LobbyR4PBRMaterial")
				if key then
					assert(key==chunk.materialKey and templates[key],"Material key differs from verified chunk")
					local existing=appearances(part)
					assert(#existing==1 and existing[1]:GetAttribute(OWNED)==true,"Unexpected PBR child set")
					local old=existing[1]
					for role,property in pairs(CONTENT_PROPERTY) do
						assert(uri(old[property])==SPEC.materials[key][role].originalURI,"Original PBR references changed; inspect fresh baseline")
					end
					table.insert(pbr,{part=part,old=old,key=key})
				elseif hash==SPEC.sidewalkAtlas.chunkSHA256 then
					assert(#appearances(part)==0,"Unexpected sidewalk atlas PBR")
					table.insert(sidewalk,part)
				end
				local owner=furnitureOwner(part,root)
				if owner then table.insert(furniture,{part=part,owner=owner}) end
				-- Mesh hashes were checked against manifold/winding/normal proofs.
				-- Open holograms and inconsistent furniture are deliberately absent.
				if options.OptimizeBackfaces and SINGLE_SIDED[hash] and not part:GetAttribute("PreviewVinylDisc") then table.insert(backfaces,part) end
				if options.AutomaticFidelity and AUTOMATIC[hash] and not part:GetAttribute("PreviewVinylDisc") then table.insert(fidelity,part) end
			end
		end
	end
	assert(#pbr>=7 and #sidewalk==14,"Expected R4 roadway/sidewalk mesh set changed")
	-- Validate the complete scope first. Only runtime clones of owned appearances
	-- are replaced; original raw templates and shared atlas remain untouched.
	for _,row in ipairs(pbr) do
		local replacement=templates[row.key]:Clone()
		replacement.Color=tintFor(row.part,root,row.key)
		replacement:SetAttribute("MaterialPolishRevision",REVISION)
		replacement.Parent=row.part
		row.old:Destroy()
		row.part:SetAttribute("MaterialPolishRevision",REVISION)
	end
	local atlasContent=Content.fromAssetId(tonumber(atlas.Value))
	for _,part in ipairs(sidewalk) do part.TextureContent=atlasContent;part:SetAttribute("MaterialPolishRevision",REVISION) end
	for _,row in ipairs(furniture) do
		local p=root:GetPivot():PointToObjectSpace(row.owner:GetPivot().Position)
		local value=.94+.06*(.5+.5*math.sin(p.X*.39+p.Y*.53+p.Z*.17))
		row.part.Color=Color3.new(value,value,value)
		row.part:SetAttribute("MaterialPolishFurnitureTint",value)
	end
	for _,part in ipairs(backfaces) do part.DoubleSided=false;part:SetAttribute("MaterialPolishClosedMesh",true) end
	for _,part in ipairs(fidelity) do part.RenderFidelity=Enum.RenderFidelity.Automatic end
	root:SetAttribute("MaterialPolishRevision",REVISION)
	root:SetAttribute("MaterialPolishPBRCount",#pbr)
	root:SetAttribute("MaterialPolishJointAtlasCount",#sidewalk)
	root:SetAttribute("MaterialPolishFurnitureCount",#furniture)
	root:SetAttribute("MaterialPolishSingleSidedCount",#backfaces)
	root:SetAttribute("MaterialPolishAutomaticCount",#fidelity)
	return {Revision=REVISION,PBR=#pbr,SidewalkAtlas=#sidewalk,FurnitureTints=#furniture,
		SingleSided=#backfaces,Automatic=#fidelity,RequiresPlayVerification=true}
end

return Module
