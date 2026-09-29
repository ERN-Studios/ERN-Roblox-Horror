-- Authorized new Level6 data only. No scripts or existing instances are overwritten.
-- After installation, install Level6BlenderRuntimeBake and call Ensure before Runtime.Build.
local SS = game:GetService("ServerStorage")
local HS = game:GetService("HttpService")
local ENC = game:GetService("EncodingService")
local BASE = "http://127.0.0.1:8879"
assert(game.PlaceId == 131311258779917 and not game:GetService("RunService"):IsRunning(), "Wrong place or mode")
assert(not SS:FindFirstChild("Level6BlenderSource"), "Level6 source exists; refusing overwrite")
local source = Instance.new("Folder"); source.Name = "Level6BlenderSource"
source:SetAttribute("Level6Owned", true); source:SetAttribute("Ready", false)
local previousHttp = HS.HttpEnabled
local function text(name, value, parent)
	local part = Instance.new("StringValue"); part.Name = name; part.Value = value; part.Parent = parent
end
local function compressedFolder(name, raw, parent)
	local folder = Instance.new("Folder"); folder.Name = name
	local compressed = ENC:CompressBuffer(raw, Enum.CompressionAlgorithm.Zstd, 3)
	local encoded = buffer.tostring(ENC:Base64Encode(compressed))
	for offset = 1, #encoded, 60000 do text(string.format("%05d", math.floor((offset-1)/60000)), encoded:sub(offset, offset+59999), folder) end
	folder:SetAttribute("RawBytes", buffer.len(raw)); folder:SetAttribute("CompressedBytes", buffer.len(compressed))
	folder.Parent = parent
end
local ok, err = pcall(function()
	HS.HttpEnabled = true
	local manifestJSON = HS:GetAsync(BASE .. "/exports-v2/manifest.json", true)
	local manifest = HS:JSONDecode(manifestJSON)
	assert(manifest.schema == "level6-blender-prefabs-v1" and #manifest.chunks == 49, "Wrong Blender manifest")
	text("ManifestJSON", manifestJSON, source)
	local meshes = Instance.new("Folder"); meshes.Name = "Meshes"; meshes.Parent = source
	for _, chunk in ipairs(manifest.chunks) do
		local raw = ENC:Base64Decode(buffer.fromstring(HS:GetAsync(BASE .. "/exports-v2/" .. chunk.file, true)))
		assert(buffer.len(raw) == chunk.bytes and buffer.readu32(raw, 0) == 0x364D564C, "Corrupt mesh payload")
		compressedFolder(tostring(chunk.id), raw, meshes)
		task.wait()
	end
	local atlasJSON = HS:GetAsync(BASE .. "/runtime-source/atlas-pixels.json", true)
	local atlas = HS:JSONDecode(atlasJSON)
	assert(atlas.width == 1024 and atlas.height == 1024, "Unexpected atlas dimensions")
	text("AtlasJSON", atlasJSON, source)
	local raw = ENC:Base64Decode(buffer.fromstring(HS:GetAsync(BASE .. "/runtime-source/atlas-rgba.b64", true)))
	assert(buffer.len(raw) == atlas.bytes, "Corrupt atlas payload")
	compressedFolder("AtlasPixels", raw, source)
	source:SetAttribute("Version", "WornParty20260930-v2")
	source:SetAttribute("Ready", true)
	assert(not SS:FindFirstChild("Level6BlenderSource"), "Concurrent Level6 source appeared; refusing overwrite")
	source.Parent = SS
end)
HS.HttpEnabled = previousHttp
if not ok then source:Destroy(); error(err) end
return "Level6BlenderSource installed: 49 exact Blender meshes + shared RGBA atlas; no runtime world built"
