-- Local-only, read-only comparison of captured native files. Only an extra
-- preview client in the deserialized after forest is removed IN MEMORY.
-- No captured file, current Studio instance or service is changed.
local fs = require("@lune/fs")
local process = require("@lune/process")
local serde = require("@lune/serde")
local rbx = require("@lune/roblox")

local directory = assert(process.args[1], "Pass native capture directory")
local output = assert(process.args[2], "Pass JSON output path")
local phase = assert(process.args[3], "Pass before or after")
assert(phase == "before" or phase == "after")
local metadata = serde.decode("json", fs.readFile(directory .. "/metadata.json"))
local scripts = serde.decode("json", fs.readFile(directory .. "/scripts.json"))
assert(metadata.placeId == 131311258779917 and metadata.universeId == 10559217407)
assert(#metadata.editorConflicts == 0 and #metadata.skipped == 0)
local roots = rbx.deserializeModel(fs.readFile(directory .. "/all-service-children.rbxm"))
assert(#roots == #metadata.roots and #scripts == metadata.scriptCount)
local additions = {
	["ServerScriptService.LobbyReimaginedPreview"] = true,
	["ServerStorage.LobbyReimaginedBlenderSource20261001"] = true,
	["ServerStorage.LobbyReimaginedBlenderSource20261001R2"] = true,
}
local clientPath = "StarterPlayer.StarterPlayerScripts.LobbyReimaginedQueueController"
local approvedSources = {
	["ServerScriptService.LobbyReimaginedPreview.RuntimeBake"] = "ModuleScript",
	["ServerScriptService.LobbyReimaginedPreview.Builder"] = "ModuleScript",
	["ServerScriptService.LobbyReimaginedPreview.Bootstrap"] = "Script",
	[clientPath] = "LocalScript",
}
local byPath, expected = {}, {}
for index, instance in roots do
	local map = metadata.roots[index]
	assert(instance.Name == map.name and instance.ClassName == map.class, "Root order differs " .. map.path)
	assert(not byPath[map.path], "Duplicate native root path " .. map.path)
	byPath[map.path] = instance
end
local function resolve(path)
	local rootPath
	for candidate in byPath do
		if path == candidate or path:sub(1, #candidate + 1) == candidate .. "." then
			if not rootPath or #candidate > #rootPath then rootPath = candidate end
		end
	end
	assert(rootPath, "Source root absent " .. path)
	local cursor = byPath[rootPath]
	for token in path:sub(#rootPath + 2):gmatch("[^%.]+") do cursor = cursor and cursor:FindFirstChild(token) end
	return assert(cursor, "Source instance absent " .. path)
end
local report = {
	schema = "lobby-preview-native-forest-scope-v1", phase = phase,
	placeId = metadata.placeId, universeId = metadata.universeId,
	capturedAt = metadata.capturedAt, observedPlaceVersion = metadata.placeVersion,
	actualRootCount = #roots, scriptCount = #scripts,
	actualWholeForestSHA256 = serde.hash("sha256", rbx.serializeModel(roots)),
	rootRecords = {}, sourceRecords = {}, memoryOnlyExclusions = {},
	comparisonOnly = true,
}
for _, source in scripts do
	assert(not expected[source.path] and source.editorMatch == true, "Duplicate/conflicting Source " .. source.path)
	expected[source.path] = true
	local instance = resolve(source.path)
	assert(instance:IsA("LuaSourceContainer") and instance.ClassName == source.class and instance.Source == source.source,
		"Native Source differs from Source/editor capture " .. source.path)
	if approvedSources[source.path] then assert(source.class == approvedSources[source.path]) end
	report.sourceRecords[source.path] = {class = source.class, bytes = #source.source,
		sha256 = serde.hash("sha256", source.source), editorMatch = true}
end
for index, instance in roots do
	local map = metadata.roots[index]
	local payload = rbx.serializeModel({instance})
	report.rootRecords[map.path] = {class = instance.ClassName, actualBytes = #payload,
		actualSHA256 = serde.hash("sha256", payload), capturedDescendants = map.descendants,
		nativeDescendants = #instance:GetDescendants()}
end
if phase == "after" then
	for path in additions do assert(byPath[path], "Approved added root absent " .. path) end
	local client = resolve(clientPath)
	assert(client:GetAttribute("LobbyReimaginedOwned") == true, "Unowned preview client")
	client:Destroy() -- Local deserialized comparison copy only.
	table.insert(report.memoryOnlyExclusions, clientPath)
end
local normalized = {}
for index, instance in roots do
	local path = metadata.roots[index].path
	if not additions[path] then
		table.insert(normalized, instance)
		local payload = rbx.serializeModel({instance})
		report.rootRecords[path].normalizedBytes = #payload
		report.rootRecords[path].normalizedSHA256 = serde.hash("sha256", payload)
	elseif phase == "after" then
		table.insert(report.memoryOnlyExclusions, path)
	else error("Preview root unexpectedly exists in before capture " .. path) end
end
report.normalizedRootCount = #normalized
report.normalizedWholeForestSHA256 = serde.hash("sha256", rbx.serializeModel(normalized))
assert(#normalized == 181, "Original forest root count differs")
assert(#scripts == (if phase == "before" then 205 else 209))
fs.writeFile(output, serde.encode("json", report, true))
print(serde.encode("json", {phase = phase, actualRoots = #roots, originalRoots = #normalized,
	sources = #scripts, normalizedWholeForestSHA256 = report.normalizedWholeForestSHA256,
	output = output}, true))
