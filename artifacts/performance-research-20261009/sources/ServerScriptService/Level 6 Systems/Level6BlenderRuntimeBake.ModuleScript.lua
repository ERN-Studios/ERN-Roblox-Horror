-- Exact Blender geometry, baked once per server into replicated static content.
-- Source payload persists in ServerStorage; Opaque Content lasts for this DataModel session.
local AS = game:GetService("AssetService")
local HS = game:GetService("HttpService")
local ENC = game:GetService("EncodingService")
local SS = game:GetService("ServerStorage")
local MS = game:GetService("MaterialService")
local RunService = game:GetService("RunService")
local Module = {}
local cached, busy, lastError
local REVISION_SOURCE = "Level6BlenderSourceRevision20261001"
local REVISION_SHA = "d2eddfce3820a27f01cdd53b93b719ec8bf8d048b9313bc6cdf29610344acc6b"

local function decode(folder)
	local pieces = folder:GetChildren()
	table.sort(pieces, function(a, b) return a.Name < b.Name end)
	local strings = table.create(#pieces)
	for i, piece in ipairs(pieces) do
		assert(piece:IsA("StringValue"), "Unexpected source payload class")
		strings[i] = piece.Value
	end
	local compressed = ENC:Base64Decode(buffer.fromstring(table.concat(strings)))
	return ENC:DecompressBuffer(compressed, Enum.CompressionAlgorithm.Zstd)
end
local function meshFromBuffer(b)
	assert(buffer.len(b) >= 20, "Blender payload is too short")
	assert(buffer.readu32(b, 0) == 0x364D564C, "Wrong Blender binary schema")
	local nv, nn, nu, nf = buffer.readu32(b, 4), buffer.readu32(b, 8), buffer.readu32(b, 12), buffer.readu32(b, 16)
	assert(nv > 0 and nv <= 60000 and nf > 0 and nf <= 20000, "Invalid Blender geometry budget")
	assert(buffer.len(b) == 20 + nv*12 + nn*12 + nu*8 + nf*36, "Truncated Blender payload")
	local em = assert(AS:CreateEditableMesh(), "Server mesh memory unavailable")
	local ok, err = pcall(function()
		local v, n, u = {}, {}, {}
		local at = 20
		for i = 1, nv do
			v[i] = em:AddVertex(Vector3.new(buffer.readf32(b, at), buffer.readf32(b, at+4), buffer.readf32(b, at+8))); at += 12
		end
		for i = 1, nn do
			n[i] = em:AddNormal(Vector3.new(buffer.readf32(b, at), buffer.readf32(b, at+4), buffer.readf32(b, at+8))); at += 12
		end
		for i = 1, nu do u[i] = em:AddUV(Vector2.new(buffer.readf32(b, at), 1 - buffer.readf32(b, at+4))); at += 8 end
		for face = 1, nf do
			local vv, nn, uu = {}, {}, {}
			for corner = 1, 3 do
				vv[corner] = assert(v[buffer.readu32(b, at)+1]); nn[corner] = assert(n[buffer.readu32(b, at+4)+1])
				uu[corner] = assert(u[buffer.readu32(b, at+8)+1]); at += 12
			end
			local id = em:AddTriangle(vv[1], vv[2], vv[3]); em:SetFaceNormals(id, nn); em:SetFaceUVs(id, uu)
			if face % 1000 == 0 then task.wait() end
		end
	end)
	if not ok then em:Destroy(); error(err) end
	return em
end
local function bakeContent(editable)
	local ok, status, content = pcall(AS.CreateDataModelContentAsync, AS, Content.fromObject(editable))
	editable:Destroy()
	assert(ok and status == Enum.CreateContentResult.Success, "Static Blender content bake failed: " .. tostring(status))
	return content
end

local function makeMeshPart(payload, chunk)
	assert(buffer.len(payload) == chunk.bytes, "Blender payload length differs from manifest: " .. chunk.name)
	local nv, nf = buffer.readu32(payload, 4), buffer.readu32(payload, 16)
	assert(chunk.vertices == nil or nv == chunk.vertices, "Vertex count differs: " .. chunk.name)
	assert(nf == chunk.triangles, "Triangle count differs: " .. chunk.name)
	local content = bakeContent(meshFromBuffer(payload))
	local part = AS:CreateMeshPartAsync(content, {
		CollisionFidelity = Enum.CollisionFidelity.Box,
		RenderFidelity = Enum.RenderFidelity.Automatic,
	})
	part.Name = chunk.name
	part.Anchored = true
	part.CanCollide = false
	part.CanTouch = false
	part.CanQuery = false
	part.Size = Vector3.new(table.unpack(chunk.size))
	part.CFrame = CFrame.new(table.unpack(chunk.center))
	part.Color = Color3.new(1, 1, 1)
	part.Material = Enum.Material.SmoothPlastic
	part:SetAttribute("BlenderSourceSHA256", chunk.sha256)
	part:SetAttribute("BlenderTriangles", chunk.triangles)
	part:SetAttribute("BlenderChunkId", chunk.id)
	return part
end

local function bakeV2(source, manifest, folder)
	assert(source.Name == REVISION_SOURCE and manifest.schema == "level6-blender-prefabs-v2", "Wrong Level 6 revision source")
	assert(manifest.placeId == game.PlaceId and manifest.groupId == game.CreatorId, "Wrong place or owner for Level 6 revision")
	assert(manifest.sourceBlendSha256 == REVISION_SHA, "Unexpected revised Blender source")
	assert(#manifest.families == 61 and #manifest.chunks == 279 and manifest.uniqueTriangles == 74092, "Incomplete revised Blender manifest")
	local materials = HS:JSONDecode(assert(source:FindFirstChild("MaterialsJSON"), "Missing Level 6 material routes").Value)
	local propsAtlasId = tonumber(materials.propsAtlasAssetId)
	assert(propsAtlasId and propsAtlasId > 0, "Revised props atlas asset is missing")
	local models = {}
	for _, family in ipairs(manifest.families) do
		assert(not models[family], "Duplicate Blender family " .. family)
		local model = Instance.new("Model")
		model.Name = family
		model.WorldPivot = CFrame.identity
		model:SetAttribute("Level6Owned", true)
		model.Parent = folder
		models[family] = model
	end
	local triangles = 0
	for index, chunk in ipairs(manifest.chunks) do
		assert(chunk.id == index - 1 and chunk.triangles > 0, "Out-of-order Blender chunk")
		local model = assert(models[chunk.family], "Missing family " .. tostring(chunk.family))
		local payload = decode(assert(source.Meshes:FindFirstChild(tostring(chunk.id)), "Missing source " .. chunk.name))
		local part = makeMeshPart(payload, chunk)
		if chunk.materialVariant then
			local route = assert(materials.variants[chunk.runtimeSurface], "Missing material route " .. tostring(chunk.runtimeSurface))
			assert(route.name == chunk.materialVariant and route.baseMaterial == "SmoothPlastic", "Material route differs for " .. chunk.name)
			local variant = assert(MS:FindFirstChild(chunk.materialVariant), "Missing PBR MaterialVariant " .. chunk.materialVariant)
			assert(variant:IsA("MaterialVariant") and variant.BaseMaterial == Enum.Material.SmoothPlastic,
				"Wrong PBR MaterialVariant " .. chunk.materialVariant)
			assert(math.abs(variant.StudsPerTile - route.studsPerTile) < .001, "Physical tile repeat differs for " .. chunk.name)
			part.TextureID = ""
			part.MaterialVariant = chunk.materialVariant
		else
			part.TextureID = "rbxassetid://" .. tostring(propsAtlasId)
		end
		part.Parent = model
		triangles += chunk.triangles
		folder:SetAttribute("BakedCount", index)
		task.wait()
	end
	assert(triangles == manifest.uniqueTriangles, "Revised Blender triangle total differs")
	for _, family in ipairs(manifest.families) do
		assert(#models[family]:GetChildren() > 0, "Empty Blender family " .. family)
	end
	folder:SetAttribute("BlenderSourceSHA256", manifest.sourceBlendSha256)
	folder:SetAttribute("BlenderImportKitSHA256", manifest.importKitBlendSha256)
	folder:SetAttribute("MaterialRoute", "MaterialVariant SmoothPlastic + uploaded props atlas")
end

local function bakeV1(source, manifest, folder)
	local atlasInfo = HS:JSONDecode(source:WaitForChild("AtlasJSON").Value)
	local pixels = decode(source:WaitForChild("AtlasPixels"))
	assert(buffer.len(pixels) == atlasInfo.width * atlasInfo.height * 4, "Incomplete atlas pixels")
	local image = assert(AS:CreateEditableImage({Size = Vector2.new(atlasInfo.width, atlasInfo.height)}), "Server image memory unavailable")
	local wrote, why = pcall(image.WritePixelsBuffer, image, Vector2.zero, image.Size, pixels)
	if not wrote then image:Destroy(); error(why) end
	local atlasContent = bakeContent(image)
	for index, chunk in ipairs(manifest.chunks) do
		local payload = decode(assert(source.Meshes:FindFirstChild(tostring(chunk.id)), "Missing mesh source " .. chunk.name))
		local part = makeMeshPart(payload, chunk)
		-- Legacy 49-kit source stores one atlas and one mesh per family.
		part.TextureContent = atlasContent
		part.Parent = folder
		folder:SetAttribute("BakedCount", index)
		task.wait()
	end
end

function Module.Ensure()
	assert(not RunService:IsClient(), "Blender kit baking is server-only")
	if cached and cached.Parent == SS and cached:GetAttribute("Ready") == true then
		assert(not SS:FindFirstChild(REVISION_SOURCE) or cached:GetAttribute("BlenderSourceSHA256") == REVISION_SHA,
			"A legacy baked kit is active alongside the revision source")
		return cached
	end
	local installed = SS:FindFirstChild("Level6BlenderKit")
	if installed then
		assert(installed:IsA("Folder") and installed:GetAttribute("Ready") == true, "Incomplete existing Level6BlenderKit; reconcile explicitly")
		assert(not SS:FindFirstChild(REVISION_SOURCE) or installed:GetAttribute("BlenderSourceSHA256") == REVISION_SHA,
			"Existing baked kit is not the revised 61-family source")
		cached = installed
		return installed
	end
	local deadline = os.clock() + 1200
	while busy and os.clock() < deadline do task.wait(.1) end
	if cached and cached.Parent == SS and cached:GetAttribute("Ready") == true then return cached end
	assert(not busy, "Blender kit bake timeout")
	assert(not SS:FindFirstChild("Level6BlenderKit"), "Unexpected existing Level6BlenderKit; preserve it and reconcile explicitly")
	local source = SS:FindFirstChild(REVISION_SOURCE) or SS:FindFirstChild("Level6BlenderSource")
	assert(source, "Blender source payload is not installed")
	assert(source:GetAttribute("Ready") == true, "Incomplete Blender source payload")
	local manifest = HS:JSONDecode(source:WaitForChild("ManifestJSON").Value)
	assert(manifest.schema == "level6-blender-prefabs-v1" or manifest.schema == "level6-blender-prefabs-v2", "Wrong Blender source manifest")
	busy = true
	local started = os.clock()
	local folder = Instance.new("Folder"); folder.Name = "Level6BlenderKit"
	folder:SetAttribute("Level6Owned", true)
	local ok, err = pcall(function()
		if manifest.schema == "level6-blender-prefabs-v2" then bakeV2(source, manifest, folder)
		else bakeV1(source, manifest, folder) end
		folder:SetAttribute("Ready", true); folder:SetAttribute("BakeSeconds", os.clock()-started)
		folder:SetAttribute("BlenderSourceVersion", source:GetAttribute("Version"))
		assert(not SS:FindFirstChild("Level6BlenderKit"), "Concurrent Blender kit appeared during bake")
		folder.Parent = SS
		cached = folder
	end)
	busy = false
	if not ok then folder:Destroy(); lastError = tostring(err); error(lastError) end
	lastError = nil
	return cached
end
function Module.Status()
	return {Ready = cached ~= nil and cached.Parent == SS, Busy = busy == true, LastError = lastError}
end
return Module
