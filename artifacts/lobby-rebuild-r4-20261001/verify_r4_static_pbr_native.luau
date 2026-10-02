-- Read-only local native asset-reference verification; no Studio connection.
local fs = require("@lune/fs")
local process = require("@lune/process")
local serde = require("@lune/serde")
local rbx = require("@lune/roblox")
local directory = assert(process.args[1], "Pass final checkpoint directory")
local catalogPath = assert(process.args[2], "Pass final cumulative task catalog")
local outputPath = assert(process.args[3], "Pass verification receipt path")
local function read(path) return serde.decode("json", fs.readFile(path)) end
local function sha(bytes) return serde.hash("sha256", bytes) end
local metadata = read(directory.."/metadata.json")
local gate = read(directory.."/checkpoint-install-gate.json")
local catalog = read(catalogPath)
assert(gate.verified == true and gate.captureId == metadata.captureId
    and gate.nativeSHA256 == metadata.nativeSHA256, "Native recovery verification missing")
assert(metadata.placeId == 131311258779917 and metadata.universeId == 10559217407
    and metadata.groupId == 1039373905, "Wrong recovery place/universe/owner")
local raw = fs.readFile(directory.."/all-service-children.rbxm")
assert(sha(raw) == metadata.nativeSHA256 and #raw == metadata.nativeBytes, "Native bytes changed")
local roots = rbx.deserializeModel(raw)
assert(#roots == metadata.rootCount and #roots == #metadata.roots, "Native root mapping differs")
local source
for index, instance in roots do
    local row = metadata.roots[index]
    assert(instance.Name == row.name and instance.ClassName == row.class, "Native root identity differs")
    if row.service == "ServerStorage" and instance.Name == catalog.payload.sourceName then
        assert(source == nil, "Ambiguous R4 source folder")
        source = instance
    end
end
assert(source and source.ClassName == "Folder", "R4 source folder missing")
assert(source:GetAttribute("LobbyReimaginedOwned") == true and source:GetAttribute("Ready") == true)
assert(source:GetAttribute("ManifestSHA256") == catalog.payload.manifestSHA256)
local materials = assert(source:FindFirstChild("StaticPBRMaterials"), "Static PBR folder missing")
assert(materials.ClassName == "Folder" and materials:GetAttribute("LobbyReimaginedOwned") == true)
assert(#materials:GetChildren() == 3 and #catalog.payload.StaticPBRMaterials.templates == 3)
local rows = {}
for _, spec in catalog.payload.StaticPBRMaterials.templates do
    local appearance = assert(materials:FindFirstChild(spec.name), "Missing static template "..spec.name)
    assert(appearance.ClassName == "SurfaceAppearance" and #appearance:GetChildren() == 0)
    assert(appearance:GetAttribute("LobbyReimaginedOwned") == true)
    local maps = {}
    for _, role in {"color", "normal", "roughness"} do
        local property = role:sub(1, 1):upper()..role:sub(2).."MapContent"
        -- rbx-dom migrates legacy map strings to the current Content properties
        -- during deserialization. Read the actual typed URI, not a formatted
        -- tostring or a security-restricted runtime Roblox legacy property.
        local value = appearance[property]
        local expected = "rbxassetid://"..spec.assetIds[role]
        assert(typeof(value) == "Content" and value.SourceType.Name == "Uri", "Native map URI type differs")
        assert(value.Uri == expected and value == rbx.Content.fromUri(expected),
            "Static native map ID differs: "..spec.name.."/"..role)
        maps[role] = {property = property, assetId = spec.assetIds[role], uri = value.Uri}
    end
    assert(appearance.AlphaMode.Name == "Overlay", "Template alpha mode differs")
    assert(appearance.Color == rbx.Color3.new(1, 1, 1), "Template color multiplier differs")
    assert(appearance.MetalnessMapContent == rbx.Content.none, "Unexpected metalness map")
    table.insert(rows, {name = spec.name, class = appearance.ClassName, maps = maps,
        color = {1, 1, 1}, alphaMode = "Overlay", metalnessMapContent = "None", owned = true})
end
local receipt = {schema = "lobby-r4-static-pbr-native-reference-verification-v1", verified = true,
    captureId = metadata.captureId, nativeSHA256 = metadata.nativeSHA256,
    catalogSHA256 = sha(fs.readFile(catalogPath)), manifestSHA256 = catalog.payload.manifestSHA256,
    sourcePath = "ServerStorage."..source.Name, templateCount = #rows, imageReferenceCount = 9,
    templates = rows, studioActions = false,
    scope = "Exact nine published URI references and three template properties in the actual final native checkpoint. This does not prove client permission, fetch status, rendering, gameplay or publication."}
fs.writeFile(outputPath, serde.encode("json", receipt, true).."\n")
print(serde.encode("json", {verified = true, templates = #rows, imageReferences = 9, output = outputPath}, true))
