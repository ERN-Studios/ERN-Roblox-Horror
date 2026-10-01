-- Read only a serialized native backup. No Studio connection or mutation.
local fs = require("@lune/fs")
local process = require("@lune/process")
local serde = require("@lune/serde")
local rbx = require("@lune/roblox")

local root = assert(process.args[1], "Pass native backup directory")
local output = assert(process.args[2], "Pass pre-created temporary output directory")
local phase = assert(process.args[3], "Pass phase label")
local metadata = serde.decode("json", fs.readFile(root .. "/metadata.json"))
local scriptRecords = serde.decode("json", fs.readFile(root .. "/scripts.json"))
local roots = rbx.deserializeModel(fs.readFile(root .. "/all-service-children.rbxm"))
assert(#roots == #metadata.roots, "Native root count differs from capture metadata")

local report = {phase = phase, placeId = metadata.placeId, universeId = metadata.universeId,
    placeVersion = metadata.placeVersion, nativeRoots = #roots, sources = {}, variants = {},
    rootRecords = {}, level3Roots = {},
    serializedScriptCount = 0}

local function attributes(instance)
    local result = {}
    for name, value in instance:GetAttributes() do
        local kind = typeof(value)
        if kind == "number" or kind == "string" or kind == "boolean" then
            result[name] = value
        else
            result[name] = tostring(value)
        end
    end
    return result
end

local expectedScripts = {}
for _, item in scriptRecords do
    assert(not expectedScripts[item.path], "Duplicate captured script path: " .. item.path)
    expectedScripts[item.path] = item
end

local function scanScripts(instance, path)
    local queue = {{instance = instance, path = path}}
    local position = 1
    while position <= #queue do
        local entry = queue[position]
        position += 1
        if entry.instance:IsA("LuaSourceContainer") then
            local expected = assert(expectedScripts[entry.path], "Native script absent from script capture: " .. entry.path)
            assert(entry.instance.ClassName == expected.class and entry.instance.Source == expected.source,
                "Native serialized script differs from captured Source: " .. entry.path)
            expectedScripts[entry.path] = nil
            report.serializedScriptCount += 1
        end
        for _, child in entry.instance:GetChildren() do
            table.insert(queue, {instance = child, path = entry.path .. "." .. child.Name})
        end
    end
end

for index, instance in roots do
    local path = metadata.roots[index].path
    local hasScript = false
    for sourcePath in expectedScripts do
        if sourcePath == path or sourcePath:sub(1, #path + 1) == path .. "." then
            hasScript = true
            break
        end
    end
    if hasScript then scanScripts(instance, path) end
end
for missing in expectedScripts do error("Captured script not present in native serialization: " .. missing) end
assert(report.serializedScriptCount == #scriptRecords, "Serialized script count differs")

local function scalar(instance, property)
    local ok, value = pcall(function() return instance[property] end)
    if ok then return tostring(value) end
    return {error = tostring(value)}
end

local function contentMap(instance, property)
    -- Current native serialization stores MaterialVariant maps in the new
    -- Content properties; Lune's legacy ContentId getter has no default and
    -- errors even when the URI is present. Read the actual serialized value.
    local ok, value = pcall(function() return instance[property .. "Content"] end)
    assert(ok and typeof(value) == "Content", "Native MaterialVariant " .. property .. "Content is unreadable: " .. tostring(value))
    local sourceType = tostring(value.SourceType)
    assert(sourceType == "Enum.ContentSourceType.Uri" or sourceType == "Enum.ContentSourceType.None",
        "Native MaterialVariant " .. property .. "Content has unexpected source: " .. sourceType)
    return {sourceType = sourceType, uri = value.Uri}
end

local function extractSource(instance)
    local record = {name = instance.Name, class = instance.ClassName,
        attributes = attributes(instance), strings = {}, payloads = {}}
    for _, child in instance:GetChildren() do
        if child:IsA("StringValue") then
            record.strings[child.Name] = child.Value
        elseif child:IsA("Folder") then
            local function payload(folder, label, destination)
                local pieces = folder:GetChildren()
                table.sort(pieces, function(a, b) return a.Name < b.Name end)
                local encoded = {}
                for index, piece in pieces do
                    assert(piece:IsA("StringValue") and piece.Name == string.format("%05d", index - 1),
                        "Unexpected compressed payload piece in " .. label)
                    encoded[index] = piece.Value
                end
                local contents = table.concat(encoded)
                local file = (phase .. "-" .. instance.Name .. "-" .. label):gsub("[^%w_-]", "_") .. ".b64"
                fs.writeFile(output .. "/" .. file, contents)
                destination[label] = {file = file, attributes = attributes(folder), pieces = #pieces,
                    encodedBytes = #contents}
            end
            if child.Name == "Meshes" then
                local items = child:GetChildren()
                table.sort(items, function(a, b) return tonumber(a.Name) < tonumber(b.Name) end)
                for _, mesh in items do
                    assert(mesh:IsA("Folder") and tonumber(mesh.Name), "Unexpected mesh source payload")
                    payload(mesh, "mesh-" .. mesh.Name, record.payloads)
                end
            elseif child.Name == "Images" then
                local imageSource = {attributes = attributes(child), strings = {}, payloads = {}}
                for _, item in child:GetChildren() do
                    if item:IsA("StringValue") then
                        imageSource.strings[item.Name] = item.Value
                    else
                        assert(item:IsA("Folder"), "Unexpected revised image source item")
                        payload(item, "image-" .. item.Name, imageSource.payloads)
                    end
                end
                record.imageSource = imageSource
            else
                payload(child, child.Name, record.payloads)
            end
        end
    end
    return record
end

for index, instance in roots do
    local map = metadata.roots[index]
    assert(instance.Name == map.name and instance.ClassName == map.class, "Native root order changed")
    local file = (phase .. "-root-" .. index .. ".rbxm")
    local serialized = rbx.serializeModel({instance})
    fs.writeFile(output .. "/" .. file, serialized)
    local rootRecord = {file = file, bytes = #serialized, class = instance.ClassName}
    report.rootRecords[map.path] = rootRecord
    if map.path:lower():match("level[ _]?3") then
        report.level3Roots[map.path] = rootRecord
    end
    if map.service == "ServerStorage" and instance.Name:match("^Level6BlenderSource") then
        report.sources[instance.Name] = extractSource(instance)
    elseif map.service == "MaterialService" and instance.Name:match("^L6R_") then
        assert(instance:IsA("MaterialVariant"), "Expected MaterialVariant " .. instance.Name)
        report.variants[instance.Name] = {class = instance.ClassName,
            baseMaterial = scalar(instance, "BaseMaterial"),
            studsPerTile = scalar(instance, "StudsPerTile"),
            colorMap = contentMap(instance, "ColorMap"),
            normalMap = contentMap(instance, "NormalMap"),
            roughnessMap = contentMap(instance, "RoughnessMap"),
            metalnessMap = contentMap(instance, "MetalnessMap"),
            attributes = attributes(instance)}
    end
end

fs.writeFile(output .. "/" .. phase .. "-native-snapshot.json", serde.encode("json", report, true))
print(serde.encode("json", {phase = phase, roots = #roots,
    serializedScripts = report.serializedScriptCount,
    sourceNames = (function()
        local names = {} for name in report.sources do table.insert(names, name) end table.sort(names) return names
    end)(), variantCount = (function()
        local count = 0 for _ in report.variants do count += 1 end return count
    end)()}, true))
