-- Read-only Level 3/6 appearance inventory. Does not build a world or edit sources.
-- Run only against the authoritative Edit place after a successful Studio login.
local HS = game:GetService("HttpService")
local SES = game:GetService("ScriptEditorService")
local RS = game:GetService("ReplicatedStorage")
local SS = game:GetService("ServerStorage")
assert(game.PlaceId == 131311258779917 and game.GameId == 10559217407, "Wrong place")
assert(not game:GetService("RunService"):IsRunning(), "Capture requires Edit mode")

local result = {
	placeId = game.PlaceId, universeId = game.GameId, placeVersion = game.PlaceVersion,
	capturedAt = DateTime.now():ToIsoDate(), assets = {}, surfaces = {}, scripts = {},
}
local function rgb(color) return {color.R, color.G, color.B} end
local function describe(instance)
	local entry = {path = instance:GetFullName(), class = instance.ClassName}
	if instance:IsA("StringValue") then
		entry.value = instance.Value
	elseif instance:IsA("Texture") then
		entry.texture = instance.Texture; entry.face = instance.Face.Name
		entry.studsPerTileU = instance.StudsPerTileU; entry.studsPerTileV = instance.StudsPerTileV
		entry.offsetU = instance.OffsetStudsU; entry.offsetV = instance.OffsetStudsV
		entry.transparency = instance.Transparency; entry.color = rgb(instance.Color3)
	elseif instance:IsA("Decal") then
		entry.texture = instance.Texture; entry.face = instance.Face.Name
		entry.transparency = instance.Transparency; entry.color = rgb(instance.Color3)
	elseif instance:IsA("SurfaceAppearance") then
		entry.colorMap = instance.ColorMap; entry.normalMap = instance.NormalMap
		entry.roughnessMap = instance.RoughnessMap; entry.metalnessMap = instance.MetalnessMap
		entry.color = rgb(instance.Color); entry.alphaMode = instance.AlphaMode.Name
	elseif instance:IsA("MeshPart") then
		entry.meshId = instance.MeshId; entry.textureId = instance.TextureID
		entry.meshContent = tostring(instance.MeshContent); entry.textureContent = tostring(instance.TextureContent)
		entry.color = rgb(instance.Color); entry.material = instance.Material.Name
		entry.materialVariant = instance.MaterialVariant; entry.transparency = instance.Transparency
	else return nil end
	return entry
end

for _, name in ipairs({"Level 3 Assets", "Level 6 Assets"}) do
	local root = RS:FindFirstChild(name)
	if root then
		local scan = root:GetDescendants(); table.insert(scan, root)
		for _, instance in ipairs(scan) do
			local entry = describe(instance)
			if entry then table.insert(result.assets, entry) end
		end
	else table.insert(result.assets, {path = "ReplicatedStorage." .. name, missing = true}) end
end

for _, root in ipairs({SS, game:GetService("ServerScriptService"), game:GetService("StarterPlayer")}) do
	for _, instance in ipairs(root:GetDescendants()) do
		if instance:IsA("LuaSourceContainer") and (instance.Name:match("^Level 3 ") or instance.Name:match("^Level 6 ")
			or instance.Name == "Level6BlenderRuntimeBake") then
			local source = instance.Source
			local editor = SES:GetEditorSource(instance)
			table.insert(result.scripts, {path = instance:GetFullName(), class = instance.ClassName,
				source = source, editorSource = editor, editorMatch = source == editor})
		end
	end
end

for _, name in ipairs({"Level6BlenderKit", "Level6BlenderSource"}) do
	local root = SS:FindFirstChild(name)
	if root then
		local record = {path = root:GetFullName(), class = root.ClassName, attributes = root:GetAttributes(), children = {}}
		for _, instance in ipairs(root:GetDescendants()) do
			local entry = describe(instance)
			if entry then
				entry.attributes = instance:GetAttributes()
				table.insert(record.children, entry)
			end
		end
		table.insert(result.surfaces, record)
	else table.insert(result.surfaces, {path = "ServerStorage." .. name, missing = true}) end
end

local previousHttp = HS.HttpEnabled
local ok, err = pcall(function()
	HS.HttpEnabled = true
	local base = "http://127.0.0.1:8882"
	local json = HS:JSONEncode(result)
	local chunkSize = 750000
	local parts = math.ceil(#json / chunkSize)
	for index = 0, parts - 1 do
		HS:PostAsync(base .. "/reference-part?index=" .. index,
			json:sub(index * chunkSize + 1, (index + 1) * chunkSize), Enum.HttpContentType.TextPlain)
	end
	HS:PostAsync(base .. "/reference", HS:JSONEncode({schema = "appearance-reference-parts/1",
		partCount = parts, bytes = #json}), Enum.HttpContentType.ApplicationJson)
end)
HS.HttpEnabled = previousHttp
assert(ok, tostring(err))
return HS:JSONEncode({ok = true, placeId = result.placeId, placeVersion = result.placeVersion,
	assets = #result.assets, scriptCount = #result.scripts, destination = "localhost texture reference receiver"})
