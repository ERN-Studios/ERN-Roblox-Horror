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
		-- R4 chunks preserve authored atlas UVs exactly, without a V inversion.
		-- The raw tile rows already match those UV cells; do not reverse them.
		image:WritePixelsBuffer(Vector2.zero, image.Size, pixels)
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
