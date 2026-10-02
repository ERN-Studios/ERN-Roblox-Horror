-- Offline native-place Source/root verification; no Studio connection or edits.
local fs = require("@lune/fs")
local process = require("@lune/process")
local serde = require("@lune/serde")
local rbx = require("@lune/roblox")
local directory = assert(process.args[1], "Pass verified direct Source directory")
local placePath = assert(process.args[2], "Pass actual Studio saved native place")
local outputPath = assert(process.args[3], "Pass new receipt path")
local function sha(value) return serde.hash("sha256", value) end
local metadata = serde.decode("json", fs.readFile(directory .. "/catalog-first.json"))
local second = serde.decode("json", fs.readFile(directory .. "/catalog-second.json"))
local sourceBytes = fs.readFile(directory .. "/scripts.json")
assert(sha(sourceBytes) == "21e656f8b0049fc5bdb02e1e7a9787c3038bcb3becec5a2f466a9d5dd77634b7", "Wrong verified Source catalog")
local sources = serde.decode("json", sourceBytes)
assert(metadata.task == "level3-promotion-20261002" and metadata.phase == "after")
assert(metadata.placeId == 131311258779917 and metadata.universeId == 10559217407 and metadata.groupId == 1039373905)
assert(metadata.scriptCount == 231 and #sources == 231 and metadata.rootCount == 195 and #metadata.roots == 195)
assert(#metadata.skipped == 0 and #second.skipped == 0)
assert(#metadata.sources == #second.sources and #metadata.roots == #second.roots)
for i, row in metadata.sources do
    local other = second.sources[i]
    assert(row.path == other.path and row.class == other.class and row.sourceBytes == other.sourceBytes
        and row.sourceSha256 == other.sourceSha256 and row.editorSourceSha256 == other.editorSourceSha256
        and row.editorMatch and other.editorMatch, "Source catalogs changed")
end
for i, row in metadata.roots do
    local other = second.roots[i]
    assert(row.path == other.path and row.name == other.name and row.class == other.class
        and row.service == other.service and row.descendants == other.descendants, "Root catalogs changed")
end
local nativeBytes = fs.readFile(placePath)
local native = rbx.deserializePlace(nativeBytes)
local services = {}
for _, service in native:GetChildren() do
    assert(not services[service.ClassName], "Duplicate native service " .. service.ClassName)
    services[service.ClassName] = service
end
local rootRows, sourceRows, rootErrors, sourceErrors = {}, {}, {}, {}
local expectedPaths = {}
local nativeContentInstances = 0
for _, row in metadata.roots do
    expectedPaths[row.path] = true
    local service = services[row.service]
    local found = service and service:FindFirstChild(row.name)
    local omitted = if row.path == "Workspace.StarterCharacter" or row.path == "Workspace.Dummy" then 1 else 0
    local descendants = if found then #found:GetDescendants() else -1
    local verified = found ~= nil and found.Name == row.name and found.ClassName == row.class
        and descendants == row.descendants - omitted
    if not verified then table.insert(rootErrors, row.path) end
    if found then nativeContentInstances += descendants + 1 end
    table.insert(rootRows, {path = row.path, class = row.class, capturedDescendants = row.descendants,
        savedDescendants = descendants, intentionallyOmittedStatus = omitted, verified = verified})
end
local savedRootCount = 0
for _, class in {"Chat", "CollectionService", "HttpService", "JointsService", "Lighting", "LocalizationService",
    "MaterialService", "PathfindingService", "PhysicsService", "ProximityPromptService", "ReplicatedFirst",
    "ReplicatedStorage", "ServerScriptService", "ServerStorage", "SoundService", "StarterGui", "StarterPack",
    "StarterPlayer", "Teams", "TestService", "TextChatService", "VoiceChatService", "Workspace"} do
    local service = services[class]
    if service then
        for _, root in service:GetChildren() do
            local path = service.Name .. "." .. root.Name
            savedRootCount += 1
            if not expectedPaths[path] then table.insert(rootErrors, "Unexpected saved root: " .. path) end
        end
    end
end
if savedRootCount ~= metadata.rootCount then table.insert(rootErrors, "Saved root count " .. savedRootCount) end
local function resolve(path)
    local best
    for _, row in metadata.roots do
        if path == row.path or path:sub(1, #row.path + 1) == row.path .. "." then
            if not best or #row.path > #best.path then best = row end
        end
    end
    if not best then return nil end
    local service = services[best.service]
    local cursor = service and service:FindFirstChild(best.name)
    for token in path:sub(#best.path + 2):gmatch("[^%.]+") do cursor = cursor and cursor:FindFirstChild(token) end
    return cursor
end
for _, row in sources do
    local found = resolve(row.path)
    local digest = sha(row.source)
    assert(row.editorMatch and digest == row.sourceSha256 and digest == row.editorSourceSha256 and #row.source == row.sourceBytes)
    local verified = found ~= nil and found.ClassName == row.class and found.Source == row.source
    if not verified then table.insert(sourceErrors, row.path) end
    table.insert(sourceRows, {path = row.path, class = row.class, sourceBytes = row.sourceBytes,
        capturedSourceSHA256 = digest, savedSourceSHA256 = if found then sha(found.Source) else nil, verified = verified})
end
local savedSourceCount = 0
for _, instance in native:GetDescendants() do
    if instance:IsA("LuaSourceContainer") then savedSourceCount += 1 end
end
if savedSourceCount ~= 231 then table.insert(sourceErrors, "Saved Source count " .. savedSourceCount) end
assert(fs.readFile(placePath) == nativeBytes, "Native file changed during verification")
local report = {schema = "level3-promotion-actual-native-direct-source-parity-v1", task = metadata.task, phase = "after",
    captureId = metadata.captureId, capturedPlaceId = metadata.placeId, capturedUniverseId = metadata.universeId,
    capturedGroupId = metadata.groupId, nativePlacePath = placePath, nativePlaceSHA256 = sha(nativeBytes), nativePlaceBytes = #nativeBytes,
    method = "Actual Studio native save supplied by authorized UI operator; offline Lune deserializePlace",
    sourceCatalogSHA256 = sha(sourceBytes), sourceCount = savedSourceCount, expectedSourceCount = 231,
    rootCount = savedRootCount, expectedRootCount = 195, nativeContentInstances = nativeContentInstances,
    sourceErrors = sourceErrors, rootErrors = rootErrors, sourceEditorConflicts = 0, sourceRows = sourceRows, rootRows = rootRows,
    sourceAndRootStructureVerified = #sourceErrors == 0 and #rootErrors == 0,
    fullNativeForestComparisonPerformed = false, serviceReconstructionPerformed = false, studioWritesPerformed = false,
    publicationClaim = false, historicalBeforeNativeRecovered = false,
    limits = "Every saved Source matches the previously captured Source/editor baseline; saved root classes/names/descendant counts match that inventory, with two known non-archivable engine Status omissions. No fresh Studio reread, exhaustive property equality, original-before native recovery, gameplay, or publication claim. Experience IDs come from the authoritative capture, not inferred from the native file."}
assert(not fs.isFile(outputPath), "Do not overwrite an existing native verification receipt")
fs.writeFile(outputPath, serde.encode("json", report, true) .. "\n")
print(serde.encode("json", {nativePlaceSHA256 = report.nativePlaceSHA256, nativePlaceBytes = #nativeBytes,
    sourceCount = savedSourceCount, rootCount = savedRootCount, sourceErrors = #sourceErrors, rootErrors = #rootErrors,
    sourceAndRootStructureVerified = report.sourceAndRootStructureVerified, output = outputPath}, true))
assert(report.sourceAndRootStructureVerified, "Saved native place Source/root parity failed; see receipt")
