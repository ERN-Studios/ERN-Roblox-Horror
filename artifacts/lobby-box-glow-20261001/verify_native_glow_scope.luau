-- Read-only local comparison of an authoritative native capture.
-- The captured .rbxm and .rbxl backups are never modified. Only deserialized
-- after-capture objects in this verification process have their one approved
-- Source properties normalized, to prove every other native property is equal.
local fs = require("@lune/fs")
local process = require("@lune/process")
local serde = require("@lune/serde")
local rbx = require("@lune/roblox")

local directory = assert(process.args[1], "Pass native capture directory")
local baseline = assert(process.args[2], "Pass baseline native capture directory")
local output = assert(process.args[3], "Pass JSON report path")
local phase = assert(process.args[4], "Pass before or after phase")
assert(phase == "before" or phase == "after")
local scoped = {
	["ServerScriptService.LobbyShopDisplay"] = true,
}
local metadata = serde.decode("json", fs.readFile(directory .. "/metadata.json"))
local scripts = serde.decode("json", fs.readFile(directory .. "/scripts.json"))
local oldScripts = serde.decode("json", fs.readFile(baseline .. "/scripts.json"))
assert(metadata.placeId == 131311258779917 and metadata.universeId == 10559217407)
assert(#metadata.editorConflicts == 0 and #metadata.skipped == 0)
local expected, oldSources = {}, {}
for _, source in scripts do
	assert(not expected[source.path], "Duplicate captured Source path " .. source.path)
	assert(source.editorMatch == true, "Source/editor conflict " .. source.path)
	expected[source.path] = source
end
for _, source in oldScripts do
	assert(not oldSources[source.path], "Duplicate baseline Source path " .. source.path)
	oldSources[source.path] = source.source
end
local roots = rbx.deserializeModel(fs.readFile(directory .. "/all-service-children.rbxm"))
assert(#roots == #metadata.roots, "Native root count differs from metadata")
local report = {
	phase = phase,
	placeId = metadata.placeId,
	universeId = metadata.universeId,
	capturedAt = metadata.capturedAt,
	rootCount = #roots,
	scriptCount = 0,
	canonicalWholeForestSHA256 = serde.hash("sha256", rbx.serializeModel(roots)),
	rootRecords = {},
	sourceNormalization = {},
	comparisonOnly = true,
}
local scopedInstances = {}
for index, instance in roots do
	local rootMap = metadata.roots[index]
	assert(instance.Name == rootMap.name and instance.ClassName == rootMap.class,
		"Native root order mismatch " .. rootMap.path)
	assert(not report.rootRecords[rootMap.path], "Duplicate native root path " .. rootMap.path)
	local payload = rbx.serializeModel({instance})
	local record = {
		class = instance.ClassName,
		actualSHA256 = serde.hash("sha256", payload),
		actualBytes = #payload,
		capturedDescendants = rootMap.descendants,
	}
	report.rootRecords[rootMap.path] = record
	local queue = {{instance = instance, path = rootMap.path}}
	local position = 1
	while position <= #queue do
		local entry = queue[position]
		position += 1
		if entry.instance:IsA("LuaSourceContainer") then
			local source = assert(expected[entry.path], "Native Source absent from capture " .. entry.path)
			assert(entry.instance.ClassName == source.class and entry.instance.Source == source.source,
				"Native Source differs from Source/editor capture " .. entry.path)
			expected[entry.path] = nil
			report.scriptCount += 1
			if scoped[entry.path] then
				table.insert(scopedInstances, {instance = entry.instance, path = entry.path,
					root = rootMap.path, actualSource = source.source})
			end
		end
		for _, child in entry.instance:GetChildren() do
			table.insert(queue, {instance = child, path = entry.path .. "." .. child.Name})
		end
	end
end
for path in expected do error("Captured Source absent from native backup " .. path) end
assert(report.scriptCount == #scripts and #scopedInstances == 1)
if phase == "after" then
	for _, entry in scopedInstances do
		local old = assert(oldSources[entry.path], "Scoped Source absent from baseline " .. entry.path)
		assert(old ~= entry.actualSource, "Scoped Source did not change " .. entry.path)
		entry.instance.Source = old
		table.insert(report.sourceNormalization, {path = entry.path, root = entry.root,
			beforeSourceSHA256 = serde.hash("sha256", old),
			afterSourceSHA256 = serde.hash("sha256", entry.actualSource)})
	end
end
for index, instance in roots do
	local record = report.rootRecords[metadata.roots[index].path]
	local payload = rbx.serializeModel({instance})
	record.sourceNormalizedSHA256 = serde.hash("sha256", payload)
	record.sourceNormalizedBytes = #payload
end
report.sourceNormalizedWholeForestSHA256 = serde.hash("sha256", rbx.serializeModel(roots))
fs.writeFile(output, serde.encode("json", report, true))
print(serde.encode("json", {phase = phase, roots = #roots, sources = report.scriptCount,
	canonicalWholeForestSHA256 = report.canonicalWholeForestSHA256,
	sourceNormalizedWholeForestSHA256 = report.sourceNormalizedWholeForestSHA256,
	report = output}, true))
