-- Read captured native forests only. All normalization occurs in local,
-- deserialized comparison copies; no Studio, backup, or source file is edited.
local fs = require("@lune/fs")
local process = require("@lune/process")
local serde = require("@lune/serde")
local rbx = require("@lune/roblox")

local beforeDir = assert(process.args[1], "Pass before directory")
local afterDir = assert(process.args[2], "Pass after directory")
local contractPath = assert(process.args[3], "Pass approved scope contract")
local output = assert(process.args[4], "Pass report path")
local contract = serde.decode("json", fs.readFile(contractPath))
local function sha(bytes) return serde.hash("sha256", bytes) end
local report = {
	schema = "level6-ceiling-independent-native-forest-scope-v1",
	placeId = contract.placeId, universeId = contract.universeId,
	contractPath = contractPath, contractSHA256 = sha(fs.readFile(contractPath)),
	comparisonOnly = true, backupFilesUnchanged = true,
	checks = {}, failures = {}, sourceRecords = {}, rootRecords = {},
	memoryOnlyNormalizations = {}, additions = {},
}
local function check(condition, description)
	table.insert(report.checks, {passed = condition, description = description})
	if not condition then table.insert(report.failures, description) end
	return condition
end
local function load(directory, phase)
	local metadata = serde.decode("json", fs.readFile(directory .. "/metadata.json"))
	local scripts = serde.decode("json", fs.readFile(directory .. "/scripts.json"))
	assert(metadata.placeId == contract.placeId and metadata.universeId == contract.universeId)
	assert(#metadata.editorConflicts == 0 and #metadata.skipped == 0)
	local native = fs.readFile(directory .. "/all-service-children.rbxm")
	local roots = rbx.deserializeModel(native)
	assert(#roots == #metadata.roots and #scripts == metadata.scriptCount)
	local capture = {metadata = metadata, roots = roots, byPath = {}, scripts = {}, phase = phase}
	for index, instance in roots do
		local row = metadata.roots[index]
		assert(instance.Name == row.name and instance.ClassName == row.class)
		assert(not capture.byPath[row.path], "Duplicate native root " .. row.path)
		capture.byPath[row.path] = instance
	end
	function capture.resolve(path)
		local rootPath
		for candidate in capture.byPath do
			if path == candidate or path:sub(1, #candidate + 1) == candidate .. "." then
				if not rootPath or #candidate > #rootPath then rootPath = candidate end
			end
		end
		assert(rootPath, "Native source root missing " .. path)
		local cursor = capture.byPath[rootPath]
		for token in path:sub(#rootPath + 2):gmatch("[^%.]+") do
			cursor = cursor and cursor:FindFirstChild(token)
		end
		return assert(cursor, "Native source instance missing " .. path)
	end
	for _, row in scripts do
		assert(not capture.scripts[row.path] and row.editorMatch == true)
		local instance = capture.resolve(row.path)
		assert(instance:IsA("LuaSourceContainer") and instance.ClassName == row.class
			and instance.Source == row.source, "Captured Source/editor/native mismatch " .. row.path)
		capture.scripts[row.path] = row
	end
	report[phase] = {directory = directory, roots = #roots, sources = #scripts,
		capturedAt = metadata.capturedAt, observedPlaceVersion = metadata.placeVersion,
		serializedInputBytes = #native, serializedInputSHA256 = sha(native),
		canonicalForestSHA256 = sha(rbx.serializeModel(roots)),
		editorConflicts = #metadata.editorConflicts, skippedRoots = #metadata.skipped}
	return capture
end

local before = load(beforeDir, "before")
local after = load(afterDir, "after")
check(before.metadata.scriptCount == contract.beforeSources, "Before has exactly approved Source count")
check(after.metadata.scriptCount == contract.afterSources, "After has exactly approved Source count")
local approved = {}
for _, row in contract.sourceRows do
	assert(not approved[row.path], "Duplicate scope path")
	approved[row.path] = row
end
local addedRoots = {}
for _, row in contract.addedRoots do
	assert(not addedRoots[row.path], "Duplicate added root")
	addedRoots[row.path] = row
end
local unchanged, changed, new = 0, 0, 0
for path, previous in before.scripts do
	local current = after.scripts[path]
	if not check(current ~= nil, "Existing Source retained " .. path) then continue end
	local beforeSHA, afterSHA = sha(previous.source), sha(current.source)
	local isChanged = previous.source ~= current.source
	local row = approved[path]
	check(previous.class == current.class, "Existing Source class retained " .. path)
	if isChanged then
		changed += 1
		check(row ~= nil and not row.new, "Changed Source is approved " .. path)
	else unchanged += 1 end
	if row then
		check(not row.new and row.class == current.class, "Existing scope class matches " .. path)
		check(afterSHA == row.expectedAfterSHA256 and #current.source == row.expectedAfterBytes,
			"Source matches exact approved final candidate " .. path)
		if row.expectedBeforeSHA256 ~= nil and row.expectedBeforeSHA256 ~= serde.null then
			check(beforeSHA == row.expectedBeforeSHA256, "Source matches fresh approved baseline " .. path)
		end
		local oldInstance, newInstance = before.resolve(path), after.resolve(path)
		newInstance.Source = previous.source
		table.insert(report.memoryOnlyNormalizations, {path = path, property = "Source"})
		if row.allowInstalledSourceSHA256Change then
			check(oldInstance:GetAttribute("LobbyReimaginedOwned") == true
				and newInstance:GetAttribute("LobbyReimaginedOwned") == true, "Existing script ownership retained " .. path)
			check(newInstance:GetAttribute("InstalledSourceSHA256") == afterSHA,
				"Owned installed-source attribute matches exact final Source " .. path)
			local oldValue = oldInstance:GetAttribute("InstalledSourceSHA256")
			newInstance:SetAttribute("InstalledSourceSHA256", oldValue)
			table.insert(report.memoryOnlyNormalizations, {path = path, attribute = "InstalledSourceSHA256",
				before = oldValue, after = afterSHA})
		end
	end
	report.sourceRecords[path] = {class = current.class, beforeBytes = #previous.source,
		afterBytes = #current.source, beforeSHA256 = beforeSHA, afterSHA256 = afterSHA,
		changed = isChanged, approved = row ~= nil, editorMatch = true}
end
for path, current in after.scripts do
	if before.scripts[path] then continue end
	new += 1
	local row = approved[path]
	check(row ~= nil and row.new and row.class == current.class, "New Source is approved " .. path)
	local afterSHA = sha(current.source)
	if row then check(afterSHA == row.expectedAfterSHA256 and #current.source == row.expectedAfterBytes,
		"New Source matches exact approved candidate " .. path) end
	local instance = after.resolve(path)
	check(instance:GetAttribute("LobbyReimaginedOwned") == true
		and instance:GetAttribute("InstalledSourceSHA256") == afterSHA
		and #instance:GetChildren() == 0, "New bridge has exact owned leaf structure " .. path)
	report.sourceRecords[path] = {class = current.class, afterBytes = #current.source,
		afterSHA256 = afterSHA, new = true, approved = row ~= nil, editorMatch = true}
	if row and row.new then
		instance:Destroy() -- Local comparison copy only.
		table.insert(report.memoryOnlyNormalizations, {path = path, newInstance = true})
	end
end
check(unchanged == contract.unchangedExistingSources, "Exactly the expected unrelated existing Sources are unchanged")
check(changed == contract.changedExistingSources, "Exactly the approved existing Sources changed")
check(new == contract.addedSources, "Exactly the approved count of new Sources")
report.sourceCounts = {unchangedExisting = unchanged, changedExisting = changed, added = new}

local normalized = {}
for index, instance in before.roots do
	local path = before.metadata.roots[index].path
	local current = after.byPath[path]
	if not check(current ~= nil, "Existing native root retained " .. path) then continue end
	check(current.ClassName == instance.ClassName, "Existing native root class retained " .. path)
	local beforeBytes, afterBytes = rbx.serializeModel({instance}), rbx.serializeModel({current})
	local beforeSHA, afterSHA = sha(beforeBytes), sha(afterBytes)
	report.rootRecords[path] = {class = instance.ClassName, beforeSHA256 = beforeSHA,
		normalizedAfterSHA256 = afterSHA, beforeBytes = #beforeBytes,
		normalizedAfterBytes = #afterBytes, beforeDescendants = #instance:GetDescendants(),
		normalizedAfterDescendants = #current:GetDescendants()}
	check(beforeSHA == afterSHA, "Existing native root unchanged after scoped normalization " .. path)
	table.insert(normalized, current)
end
for path, current in after.byPath do
	if before.byPath[path] then continue end
	local row = addedRoots[path]
	check(row ~= nil, "New native root is approved " .. path)
	if row then
		check(current.ClassName == row.class and current:GetAttribute("LobbyReimaginedOwned") == true
			and current:GetAttribute("Ready") == true
			and current:GetAttribute("ManifestSHA256") == row.manifestSHA256,
			"New raw root is owned, ready, and matches approved Blender revision " .. path)
	end
	table.insert(report.additions, {path = path, class = current.ClassName,
		descendants = #current:GetDescendants(), attributes = current:GetAttributes(),
		canonicalSHA256 = sha(rbx.serializeModel({current}))})
end
check(#report.additions == #contract.addedRoots, "Only the approved additive native roots exist")
check(#normalized == #before.roots, "All original roots preserved in normalized forest")
report.normalizedAfterCanonicalForestSHA256 = sha(rbx.serializeModel(normalized))
check(report.before.canonicalForestSHA256 == report.normalizedAfterCanonicalForestSHA256,
	"Whole original native forest including cross-references is identical after scoped normalization")
report.passed = #report.failures == 0
report.limits = "Equality of captured native forests and Source/editor parity; inaccessible service properties, engine omissions, and reconstruction limits are recorded separately in native-place-verification and independent service metadata review. No live gameplay or publication inferred."
fs.writeFile(output, serde.encode("json", report, true))
print(serde.encode("json", {passed = report.passed, before = report.before,
	after = report.after, sourceCounts = report.sourceCounts, checks = #report.checks,
	failures = report.failures, normalizedAfterCanonicalForestSHA256 = report.normalizedAfterCanonicalForestSHA256,
	output = output}, true))
assert(report.passed, "Scoped native comparison failed; inspect JSON receipt")
