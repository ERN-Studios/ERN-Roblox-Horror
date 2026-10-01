-- New isolated preview only. Persist raw source; regenerate opaque content per server.
local AS = game:GetService("AssetService")
local HS = game:GetService("HttpService")
local ENC = game:GetService("EncodingService")
local SS = game:GetService("ServerStorage")
local RunService = game:GetService("RunService")
local Module = {}
local SOURCE = "LobbyReimaginedBlenderSource20261001R3B"
local KIT = "LobbyReimaginedBlenderKit20261001R3B"
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
	assert(manifest.schema == "lobby-reimagined-blender-v1", "Wrong preview schema")
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
	local deadline = time()+180
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
		local names, triangles = {}, 0
		local meshes = assert(source:FindFirstChild("Meshes"))
		for index, chunk in ipairs(manifest.chunks) do
			assert(chunk.id == index-1, "Unordered prefab chunks")
			local family = chunk.family or chunk.name
			assert(type(family) == "string" and not names[family], "Duplicate prefab family")
			names[family] = true
			local content = mesh(decode(meshes:FindFirstChild(tostring(chunk.id))), chunk)
			local part = AS:CreateMeshPartAsync(content, {CollisionFidelity = Enum.CollisionFidelity.Box, RenderFidelity = Enum.RenderFidelity.Automatic})
			part.Parent = folder -- Track immediately so property errors also clean up the new part.
			part.Name = family; part.Size = Vector3.new(table.unpack(chunk.size))
			part.CFrame = CFrame.new(table.unpack(chunk.center)); part.Anchored = true
			part.CanCollide = false; part.CanTouch = false; part.CanQuery = false
			part.Material = Enum.Material.SmoothPlastic; part.Color = Color3.new(1, 1, 1)
			part.TextureContent = atlasContent
			part:SetAttribute(OWNED, true); part:SetAttribute("BlenderSourceSHA256", chunk.sha256)
			part:SetAttribute("BlenderTriangles", chunk.triangles)
			triangles += chunk.triangles; folder:SetAttribute("BakedCount", index); task.wait()
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
