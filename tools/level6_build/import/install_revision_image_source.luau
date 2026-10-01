-- Additive Edit-mode staging of the 27 Blender RGBA maps for runtime content bake.
-- The existing mesh source, legacy source, variants and scripts remain untouched.
local SS = game:GetService("ServerStorage")
local HS = game:GetService("HttpService")
local ENC = game:GetService("EncodingService")
local RunService = game:GetService("RunService")
local BASE = "http://127.0.0.1:8881"
local SOURCE_NAME = "Level6BlenderSourceRevision20261001"
local SOURCE_SHA = "d2eddfce3820a27f01cdd53b93b719ec8bf8d048b9313bc6cdf29610344acc6b"
local IMAGES_SHA = "1e51bcdc2cf4cac0f49d79ea6600dfe6b59df92b2c7761a8c1bb8d70e7f7eb77"
local ROUTES_SHA = "c7819b4ca22e6366274ddb438c2985264499d7e44621e4638198fc3aff38ba37"

local function sha256(value)
	local digest = ENC:ComputeBufferHash(value, Enum.HashAlgorithm.Sha256)
	local chars = table.create(buffer.len(digest))
	for i = 0, buffer.len(digest) - 1 do chars[i + 1] = string.format("%02x", buffer.readu8(digest, i)) end
	return table.concat(chars)
end

assert(game.PlaceId == 131311258779917 and game.CreatorId == 1039373905, "Wrong Level 6 experience or owner")
assert(not RunService:IsRunning(), "Stage raw image source in Edit mode")
local source = assert(SS:FindFirstChild(SOURCE_NAME), "Revised mesh source is missing")
assert(source:IsA("Folder") and source:GetAttribute("Ready") == true, "Revised mesh source is incomplete")
assert(source:GetAttribute("Version") == "Level6Revised20261001" and source:GetAttribute("SourceBlendSHA256") == SOURCE_SHA
	and source:GetAttribute("InstalledCount") == 279, "Wrong revised mesh source")
assert(not source:FindFirstChild("Images"), "Raw image source already exists; inspect before retrying")
local manifestValue = assert(source:FindFirstChild("ManifestJSON"), "Missing mesh manifest")
local materialsValue = assert(source:FindFirstChild("MaterialsJSON"), "Missing material provenance")
local beforeManifest, beforeMaterials = manifestValue.Value, materialsValue.Value
local manifest = HS:JSONDecode(beforeManifest)
assert(manifest.sourceBlendSha256 == SOURCE_SHA and #manifest.chunks == 279, "Wrong mesh manifest")
local materials = HS:JSONDecode(beforeMaterials)
assert(materials.schema and materials.variants and materials.propsAtlasAssetId, "Wrong material provenance")
local previousHttp = HS.HttpEnabled
local images = Instance.new("Folder")
images.Name = "Images"
images:SetAttribute("Level6Owned", true)
images:SetAttribute("Ready", false)

local ok, err = pcall(function()
	HS.HttpEnabled = true
	local imagesJSON = HS:GetAsync(BASE .. "/import-package/images-runtime.json", true)
	assert(sha256(buffer.fromstring(imagesJSON)) == IMAGES_SHA, "Wrong locally served image manifest")
	local spec = HS:JSONDecode(imagesJSON)
	assert(spec.schema == "level6-blender-runtime-images-v1" and spec.placeId == game.PlaceId
		and spec.groupId == game.CreatorId and spec.sourceBlendSha256 == SOURCE_SHA
		and spec.sourceMaterialRoutesSha256 == ROUTES_SHA, "Wrong image source provenance")
	assert(spec.imageCount == 27 and #spec.images == 27 and spec.propsAtlasKey == "props__color", "Incomplete Blender image source")
	local names, totalCompressed = {}, 0
	for index, image in ipairs(spec.images) do
		assert(type(image.key) == "string" and image.key:match("^[%w_-]+$") and not names[image.key], "Duplicate or unsafe image key")
		names[image.key] = true
		assert(image.width == 1024 and image.height == 1024 and image.pixelFormat == "RGBA8"
			and image.rgbaBytes == 4194304 and #image.parts > 0, "Wrong image dimensions: " .. image.key)
		local imageFolder = Instance.new("Folder")
		imageFolder.Name = image.key
		local encoded = table.create(#image.parts)
		for partIndex, part in ipairs(image.parts) do
			assert(part.path:match("^taskgroup%-owned%-images/[%w_-]+%.zstd%.b64%.%d%d%d%.txt$")
				and part.path:find(image.key, 1, true), "Unexpected image part path")
			local value = HS:GetAsync(BASE .. "/" .. part.path, true)
			assert(#value == part.bytes and sha256(buffer.fromstring(value)) == part.sha256,
				"Corrupt RGBA source part: " .. part.path)
			encoded[partIndex] = value
			local child = Instance.new("StringValue")
			child.Name = string.format("%05d", partIndex - 1)
			child.Value = value
			child.Parent = imageFolder
		end
		local joined = table.concat(encoded)
		assert(#joined == image.base64Chars, "Wrong image base64 length: " .. image.key)
		local compressed = ENC:Base64Decode(buffer.fromstring(joined))
		assert(buffer.len(compressed) == image.compressedBytes and sha256(compressed) == image.compressedSha256,
			"Wrong compressed RGBA hash: " .. image.key)
		local raw = ENC:DecompressBuffer(compressed, Enum.CompressionAlgorithm.Zstd)
		assert(buffer.len(raw) == image.rgbaBytes and sha256(raw) == image.rgbaSha256,
			"Wrong authored RGBA hash: " .. image.key)
		imageFolder:SetAttribute("RGBABytes", image.rgbaBytes)
		imageFolder:SetAttribute("RGBASHA256", image.rgbaSha256)
		imageFolder:SetAttribute("CompressedBytes", image.compressedBytes)
		imageFolder:SetAttribute("CompressedSHA256", image.compressedSha256)
		imageFolder.Parent = images
		totalCompressed += image.compressedBytes
		images:SetAttribute("InstalledCount", index)
		task.wait()
	end
	assert(names["props__color"] and names["red-wall-color"], "Props or red wall is missing")
	local jsonValue = Instance.new("StringValue")
	jsonValue.Name = "ImagesJSON"
	jsonValue.Value = imagesJSON
	jsonValue.Parent = images
	images:SetAttribute("ImageManifestSHA256", IMAGES_SHA)
	images:SetAttribute("SourceBlendSHA256", SOURCE_SHA)
	images:SetAttribute("SourceMaterialRoutesSHA256", ROUTES_SHA)
	images:SetAttribute("CompressedBytes", totalCompressed)
	images:SetAttribute("Ready", true)
	assert(source.Parent == SS and SS:FindFirstChild(SOURCE_NAME) == source and source:GetAttribute("Ready") == true
		and source:GetAttribute("Version") == "Level6Revised20261001"
		and source:GetAttribute("SourceBlendSHA256") == SOURCE_SHA and source:GetAttribute("InstalledCount") == 279
		and not source:FindFirstChild("Images") and manifestValue.Parent == source and materialsValue.Parent == source
		and manifestValue.Value == beforeManifest and materialsValue.Value == beforeMaterials,
		"Revised source changed while images were staged; refusing to attach")
	images.Parent = source
end)
if HS.HttpEnabled == true then HS.HttpEnabled = previousHttp end
if not ok then images:Destroy(); error(err) end
return "Installed 27 SHA-verified compressed RGBA images as one additive source folder"
