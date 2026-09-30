-- Exact Blender geometry, baked once per server into replicated static content.
-- Source payload persists in ServerStorage; Opaque Content lasts for this DataModel session.
local AS = game:GetService("AssetService")
local HS = game:GetService("HttpService")
local ENC = game:GetService("EncodingService")
local SS = game:GetService("ServerStorage")
local RunService = game:GetService("RunService")
local Module = {}
local cached, busy, lastError

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
function Module.Ensure()
	assert(not RunService:IsClient(), "Blender kit baking is server-only")
	if cached and cached.Parent == SS then return cached end
	local deadline = os.clock() + 180
	while busy and os.clock() < deadline do task.wait(.1) end
	if cached and cached.Parent == SS then return cached end
	assert(not busy, "Blender kit bake timeout")
	assert(not SS:FindFirstChild("Level6BlenderKit"), "Unexpected existing Level6BlenderKit; preserve it and reconcile explicitly")
	local source = assert(SS:FindFirstChild("Level6BlenderSource"), "Blender source payload is not installed")
	assert(source:GetAttribute("Ready") == true, "Incomplete Blender source payload")
	local manifest = HS:JSONDecode(source:WaitForChild("ManifestJSON").Value)
	assert(manifest.schema == "level6-blender-prefabs-v1", "Wrong Blender source manifest")
	busy = true
	local started = os.clock()
	local folder = Instance.new("Folder"); folder.Name = "Level6BlenderKit"
	folder:SetAttribute("Level6Owned", true)
	local ok, err = pcall(function()
		local atlasInfo = HS:JSONDecode(source:WaitForChild("AtlasJSON").Value)
		local pixels = decode(source:WaitForChild("AtlasPixels"))
		assert(buffer.len(pixels) == atlasInfo.width * atlasInfo.height * 4, "Incomplete atlas pixels")
		local image = assert(AS:CreateEditableImage({Size = Vector2.new(atlasInfo.width, atlasInfo.height)}), "Server image memory unavailable")
		local wrote, why = pcall(image.WritePixelsBuffer, image, Vector2.zero, image.Size, pixels)
		if not wrote then image:Destroy(); error(why) end
		local atlasContent = bakeContent(image)
		for index, chunk in ipairs(manifest.chunks) do
			local payload = decode(assert(source.Meshes:FindFirstChild(tostring(chunk.id)), "Missing mesh source " .. chunk.name))
			local content = bakeContent(meshFromBuffer(payload))
			local part = AS:CreateMeshPartAsync(content, {CollisionFidelity = Enum.CollisionFidelity.Box, RenderFidelity = Enum.RenderFidelity.Automatic})
			part.Name = chunk.name; part.Anchored = true; part.CanCollide = false; part.CanTouch = false; part.CanQuery = false
			part.Size = Vector3.new(table.unpack(chunk.size)); part.CFrame = CFrame.new(table.unpack(chunk.center))
			part.Color = Color3.new(1,1,1); part.Material = Enum.Material.SmoothPlastic
			part:SetAttribute("BlenderSourceSHA256", chunk.sha256)
			part:SetAttribute("BlenderTriangles", chunk.triangles)
			-- TextureContent is script-writable. SurfaceAppearance.ColorMapContent is
			-- PluginSecurity and cannot be assigned by this server ModuleScript.
			part.TextureContent = atlasContent
			part.Parent = folder
			folder:SetAttribute("BakedCount", index)
			task.wait()
		end
		folder:SetAttribute("Ready", true); folder:SetAttribute("BakeSeconds", os.clock()-started)
		folder:SetAttribute("BlenderSourceVersion", source:GetAttribute("Version"))
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
