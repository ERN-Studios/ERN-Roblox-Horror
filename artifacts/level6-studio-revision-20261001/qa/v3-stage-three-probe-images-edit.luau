-- Temporary, additive Edit-mode staging for the isolated PBR viewport probe.
-- Parent may run via Studio plugin command after a native backup, then remove
-- ServerStorage.L6PBRProbeImages after Play. Does not modify revision source.
local SS = game:GetService("ServerStorage")
local HS = game:GetService("HttpService")
local ENC = game:GetService("EncodingService")
local RunService = game:GetService("RunService")
local BASE = "http://127.0.0.1:8881/"
local NAME = "L6PBRProbeImages"
local wanted = {
	["diamondplate__color"] = true,
	["diamondplate__normal-opengl"] = true,
	["diamondplate__roughness"] = true,
}

local function sha256(value)
	local digest = ENC:ComputeBufferHash(value, Enum.HashAlgorithm.Sha256)
	local chars = table.create(buffer.len(digest))
	for i = 0, buffer.len(digest) - 1 do chars[i + 1] = string.format("%02x", buffer.readu8(digest, i)) end
	return table.concat(chars)
end

assert(game.PlaceId == 131311258779917 and game.CreatorId == 1039373905, "Wrong Level 6 place or creator")
assert(not RunService:IsRunning(), "Stage the three probe images only in Edit mode")
assert(not SS:FindFirstChild(NAME), "Probe images already staged; inspect before retry")
local previousHttp = HS.HttpEnabled
local staged = Instance.new("Folder")
staged.Name = NAME
staged:SetAttribute("Ready", false)
local ok, err = pcall(function()
	HS.HttpEnabled = true
	local manifest = HS:JSONDecode(HS:GetAsync(BASE .. "taskgroup-owned-images/manifest.json", true))
	assert(manifest.schema == "level6-group-owned-rgba-upload/1" and manifest.imageCount == 27
		and manifest.placeId == game.PlaceId and manifest.targetCreatorId == game.CreatorId,
		"Wrong authored image package")
	local selected = {}
	for _, image in ipairs(manifest.images) do
		if wanted[image.key] then table.insert(selected, image) end
	end
	assert(#selected == 3, "Missing one of the three diamondplate probe maps")
	for _, image in ipairs(selected) do
		local folder = Instance.new("Folder")
		folder.Name = image.key
		local encoded = table.create(#image.parts)
		for index, part in ipairs(image.parts) do
			assert(part.path:match("^taskgroup%-owned%-images/diamondplate__[%w_-]+%.zstd%.b64%.%d%d%d%.txt$"),
				"Unexpected probe part path")
			local value = HS:GetAsync(BASE .. part.path, true)
			assert(#value == part.bytes and sha256(buffer.fromstring(value)) == part.sha256,
				"Corrupt probe part " .. part.path)
			encoded[index] = value
			local child = Instance.new("StringValue")
			child.Name = string.format("%05d", index - 1)
			child.Value = value
			child.Parent = folder
		end
		local zipped = ENC:Base64Decode(buffer.fromstring(table.concat(encoded)))
		assert(buffer.len(zipped) == image.compressedBytes and sha256(zipped) == image.compressedSha256,
			"Corrupt compressed probe map " .. image.key)
		local raw = ENC:DecompressBuffer(zipped, Enum.CompressionAlgorithm.Zstd)
		assert(buffer.len(raw) == image.rgbaBytes and sha256(raw) == image.rgbaSha256,
			"Corrupt authored probe RGBA " .. image.key)
		folder.Parent = staged
	end
	local manifestValue = Instance.new("StringValue")
	manifestValue.Name = "ImagesJSON"
	manifestValue.Value = HS:JSONEncode({schema = "level6-pbr-probe-images/1", imageCount = 3, images = selected})
	manifestValue.Parent = staged
	staged:SetAttribute("Ready", true)
	assert(not SS:FindFirstChild(NAME), "Probe folder appeared during staging")
	staged.Parent = SS
end)
HS.HttpEnabled = previousHttp
if not ok then staged:Destroy(); error(err) end
return "Staged three SHA-verified diamondplate images for a bounded Play probe; remove L6PBRProbeImages afterward"
