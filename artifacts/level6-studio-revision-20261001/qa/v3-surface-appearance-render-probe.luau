-- Temporary real server Script for a bounded Play-only PBR visual probe.
-- Requires the SHA-verified source.Images folder. Parent/install in
-- ServerScriptService before Play, inspect on a client, then remove in Edit.
-- Creates six non-colliding procedural floor MeshParts near the first player.
-- The script never touches the live Level 6 world or material variants.
local AS = game:GetService("AssetService")
local ENC = game:GetService("EncodingService")
local HS = game:GetService("HttpService")
local Players = game:GetService("Players")
local SS = game:GetService("ServerStorage")

local source = assert(SS:FindFirstChild("Level6BlenderSourceRevision20261001"), "Revision source missing")
local imagesRoot = assert(source:FindFirstChild("Images"), "Revision image source missing")
assert(imagesRoot:GetAttribute("Ready") == true, "Revision image source incomplete")
local spec = HS:JSONDecode(assert(imagesRoot:FindFirstChild("ImagesJSON")).Value)
assert(spec.imageCount == 27 and spec.propsAtlasKey == "props__color", "Wrong revision image manifest")

local byKey = {}
for _, entry in ipairs(spec.images) do byKey[entry.key] = entry end
local function sha256(value)
	local digest = ENC:ComputeBufferHash(value, Enum.HashAlgorithm.Sha256)
	local chars = table.create(buffer.len(digest))
	for i = 0, buffer.len(digest) - 1 do chars[i + 1] = string.format("%02x", buffer.readu8(digest, i)) end
	return table.concat(chars)
end
local function decode(key)
	local entry = assert(byKey[key], "Missing authored image " .. key)
	assert(entry.width == 1024 and entry.height == 1024 and entry.rgbaBytes == 4194304, "Wrong image dimensions")
	local folder = assert(imagesRoot:FindFirstChild(key), "Missing image payload " .. key)
	local chunks = folder:GetChildren()
	table.sort(chunks, function(a, b) return a.Name < b.Name end)
	assert(#chunks == #entry.parts, "Incomplete image payload " .. key)
	local encoded = table.create(#chunks)
	for i, chunk in ipairs(chunks) do
		assert(chunk:IsA("StringValue") and chunk.Name == string.format("%05d", i - 1), "Out-of-order image payload")
		encoded[i] = chunk.Value
	end
	local zipped = ENC:Base64Decode(buffer.fromstring(table.concat(encoded)))
	assert(buffer.len(zipped) == entry.compressedBytes and sha256(zipped) == entry.compressedSha256,
		"Compressed image differs: " .. key)
	local rgba = ENC:DecompressBuffer(zipped, Enum.CompressionAlgorithm.Zstd)
	assert(buffer.len(rgba) == entry.rgbaBytes and sha256(rgba) == entry.rgbaSha256,
		"Decoded image differs: " .. key)
	local image = assert(AS:CreateEditableImage({Size = Vector2.new(1024, 1024)}), "EditableImage memory unavailable")
	local ok, err = pcall(image.WritePixelsBuffer, image, Vector2.zero, image.Size, rgba)
	if not ok then image:Destroy(); error(err) end
	return image
end

local editable = {
	color = decode("diamondplate__color"),
	normal = decode("diamondplate__normal-opengl"),
	roughness = decode("diamondplate__roughness"),
}
local full = AS:CreateSurfaceAppearanceAsync({
	ColorMap = Content.fromObject(editable.color),
	NormalMap = Content.fromObject(editable.normal),
	RoughnessMap = Content.fromObject(editable.roughness),
})
local colorOnly = AS:CreateSurfaceAppearanceAsync({ColorMap = Content.fromObject(editable.color)})

local function plane(width, depth)
	local mesh = assert(AS:CreateEditableMesh(), "EditableMesh memory unavailable")
	local vertices = {
		mesh:AddVertex(Vector3.new(-width / 2, 0, -depth / 2)),
		mesh:AddVertex(Vector3.new(-width / 2, 0, depth / 2)),
		mesh:AddVertex(Vector3.new(width / 2, 0, depth / 2)),
		mesh:AddVertex(Vector3.new(width / 2, 0, -depth / 2)),
	}
	local tile = 8 -- Authored diamondplate StudsPerTile.
	local uvs = {
		mesh:AddUV(Vector2.new(0, 0)),
		mesh:AddUV(Vector2.new(0, depth / tile)),
		mesh:AddUV(Vector2.new(width / tile, depth / tile)),
		mesh:AddUV(Vector2.new(width / tile, 0)),
	}
	local normal = mesh:AddNormal(Vector3.yAxis)
	for _, corners in ipairs({{1, 2, 3}, {1, 3, 4}}) do
		local face = mesh:AddTriangle(vertices[corners[1]], vertices[corners[2]], vertices[corners[3]])
		mesh:SetFaceNormals(face, {normal, normal, normal})
		mesh:SetFaceUVs(face, {uvs[corners[1]], uvs[corners[2]], uvs[corners[3]]})
	end
	local status, content = AS:CreateDataModelContentAsync(Content.fromObject(mesh))
	mesh:Destroy()
	assert(status == Enum.CreateContentResult.Success, "Probe mesh bake failed: " .. tostring(status))
	local part = AS:CreateMeshPartAsync(content, {CollisionFidelity = Enum.CollisionFidelity.Box})
	part.Anchored = true
	part.CanCollide = false
	part.CanTouch = false
	part.CanQuery = false
	part.Color = Color3.new(1, 1, 1)
	return part
end

local player = Players:GetPlayers()[1] or Players.PlayerAdded:Wait()
local character = player.Character or player.CharacterAdded:Wait()
local root = assert(character:WaitForChild("HumanoidRootPart", 20), "Probe player root missing")
local origin = root.Position + root.CFrame.LookVector * 27 + Vector3.new(0, 3, 0)
local model = Instance.new("Model")
model.Name = "L6_PBR_Visual_Probe_PlayOnly"
model:SetAttribute("Level6Owned", true)
for row = 1, 2 do
	for col, width in ipairs({8, 16, 24}) do
		local part = plane(width, 8)
		part.Name = string.format("%s_%dx8_tile8", row == 1 and "FullPBR" or "ColorOnly", width)
		part.CFrame = CFrame.new(origin + root.CFrame.RightVector * ((col - 2) * 25)
			+ root.CFrame.LookVector * ((row - 1) * 11))
		-- Keep one factory original in each row. If only the later panels
		-- fail, cloning is the issue rather than the factory or image content.
		local template = row == 1 and full or colorOnly
		local appearance = col == 1 and template or template:Clone()
		appearance.Parent = part
		part.Parent = model
	end
end
local lightHolder = Instance.new("Part")
lightHolder.Name = "AngledWhiteLight"
lightHolder.Size = Vector3.one
lightHolder.Anchored = true
lightHolder.CanCollide = false
lightHolder.Transparency = 1
lightHolder.CFrame = CFrame.new(origin + Vector3.new(-12, 13, -10))
local light = Instance.new("PointLight")
light.Brightness = 4
light.Range = 75
light.Parent = lightHolder
lightHolder.Parent = model
model.Parent = workspace
print("L6_PBR_VISUAL_PROBE_READY", model:GetFullName(), "3 authored maps, 6 panels, UV 1 tile/8 studs")

task.delay(30, function()
	for _, image in pairs(editable) do image:Destroy() end
	print("L6_PBR_VISUAL_PROBE_EDITABLES_DESTROYED", "Compare client rendering now; blank maps mean images must stay live")
end)
task.delay(90, function()
	model:Destroy()
	print("L6_PBR_VISUAL_PROBE_CLEANED")
end)
