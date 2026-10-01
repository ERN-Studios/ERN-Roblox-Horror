-- Additive, Edit-mode installation of the SHA-pinned revised Level 6 raw source.
-- The existing 49-mesh source is preserved. No scripts or world parts are edited.
-- Run tools/level6_build/import/serve.py against the import-package directory first.
local SS = game:GetService("ServerStorage")
local HS = game:GetService("HttpService")
local ENC = game:GetService("EncodingService")
local RunService = game:GetService("RunService")
local BASE = "http://127.0.0.1:8890"
local NAME = "Level6BlenderSourceRevision20261001"
local SOURCE_SHA = "d2eddfce3820a27f01cdd53b93b719ec8bf8d048b9313bc6cdf29610344acc6b"

assert(game.PlaceId == 131311258779917 and game.CreatorId == 1039373905, "Wrong Level 6 experience or owner")
assert(not RunService:IsRunning(), "Install source in Edit mode")
assert(not SS:FindFirstChild(NAME), "Revised Level 6 raw source already exists; inspect before reconciling")

local source = Instance.new("Folder")
source.Name = NAME
source:SetAttribute("Level6Owned", true)
source:SetAttribute("Ready", false)
local previousHttp = HS.HttpEnabled

local function stringValue(name, value, parent)
	local item = Instance.new("StringValue")
	item.Name = name
	item.Value = value
	item.Parent = parent
end

local function compressedFolder(name, raw, parent)
	local folder = Instance.new("Folder")
	folder.Name = name
	local compressed = ENC:CompressBuffer(raw, Enum.CompressionAlgorithm.Zstd, 3)
	local encoded = buffer.tostring(ENC:Base64Encode(compressed))
	for offset = 1, #encoded, 60000 do
		stringValue(string.format("%05d", math.floor((offset - 1)/60000)), encoded:sub(offset, offset + 59999), folder)
	end
	folder:SetAttribute("RawBytes", buffer.len(raw))
	folder:SetAttribute("CompressedBytes", buffer.len(compressed))
	folder.Parent = parent
end

local ok, err = pcall(function()
	HS.HttpEnabled = true
	local manifestJSON = HS:GetAsync(BASE .. "/runtime-manifest", true)
	local manifest = HS:JSONDecode(manifestJSON)
	assert(manifest.schema == "level6-blender-prefabs-v2" and manifest.sourceBlendSha256 == SOURCE_SHA, "Wrong revised Blender source")
	assert(manifest.placeId == game.PlaceId and manifest.groupId == game.CreatorId, "Wrong manifest owner")
	assert(#manifest.families == 61 and #manifest.chunks == 279 and manifest.uniqueTriangles == 74092, "Incomplete revised kit")
	local materialsJSON = HS:GetAsync(BASE .. "/materials-runtime", true)
	local materials = HS:JSONDecode(materialsJSON)
	assert(type(materials.propsAtlasAssetId) == "number" and materials.propsAtlasAssetId > 0, "Props atlas is not uploaded")
	stringValue("ManifestJSON", manifestJSON, source)
	stringValue("MaterialsJSON", materialsJSON, source)
	local meshes = Instance.new("Folder")
	meshes.Name = "Meshes"
	meshes.Parent = source
	for index, chunk in ipairs(manifest.chunks) do
		assert(chunk.id == index - 1 and chunk.bytes > 20, "Invalid mesh index")
		local encoded = HS:GetAsync(BASE .. "/chunk/" .. chunk.id, true)
		local raw = ENC:Base64Decode(buffer.fromstring(encoded))
		assert(buffer.len(raw) == chunk.bytes and buffer.readu32(raw, 0) == 0x364D564C, "Corrupt Blender mesh " .. chunk.name)
		assert(buffer.readu32(raw, 16) == chunk.triangles, "Wrong triangle count " .. chunk.name)
		compressedFolder(tostring(chunk.id), raw, meshes)
		source:SetAttribute("InstalledCount", index)
		task.wait()
	end
	source:SetAttribute("Version", "Level6Revised20261001")
	source:SetAttribute("SourceBlendSHA256", SOURCE_SHA)
	source:SetAttribute("Ready", true)
	assert(not SS:FindFirstChild(NAME), "Concurrent revised source appeared; refusing overwrite")
	source.Parent = SS
end)
HS.HttpEnabled = previousHttp
if not ok then
	source:Destroy()
	error(err)
end
return "Installed 279 compressed revised Level 6 mesh chunks in ServerStorage; no world was built"
