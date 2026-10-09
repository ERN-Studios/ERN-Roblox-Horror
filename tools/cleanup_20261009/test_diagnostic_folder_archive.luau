-- Actual Lune serializer tests. All mutations use local deserialized copies.
-- Arguments: immutable facts JSON, immutable RBXM, NEW test receipt filename.
local fs = require("@lune/fs")
local process = require("@lune/process")
local serde = require("@lune/serde")
local rbx = require("@lune/roblox")
local verifier = require("./diagnostic_folder_archive")
assert(#process.args == 3, "Pass facts JSON, native RBXM, and a NEW test receipt filename")
local factsPath, nativePath, output = table.unpack(process.args)
assert(not fs.isFile(output) and not fs.isDir(output), "Refusing existing test receipt")
local factsRaw, nativeRaw = fs.readFile(factsPath), fs.readFile(nativePath)
local facts = serde.decode("json", factsRaw)
local checks, positive, negative, cases = 0, 0, 0, {}
local function check(value, label)
	checks += 1
	assert(value, label)
end
local function copy(value) return serde.decode("json", serde.encode("json", value)) end
local function repin(value, bytes)
	value.nativeBytes = #bytes
	value.nativeSHA256 = serde.hash("sha256", bytes)
	return value
end
local function accept(label, value, bytes)
	print("CASE accept: " .. label)
	local report = verifier.Verify(value, bytes)
	check(report.verified and report.rootCount == 12 and report.nativeReloadEqual, label)
	positive += 1
	table.insert(cases, {name = label, expected = "accept", passed = true})
end
local function reject(label, value, bytes, expectedError)
	print("CASE reject: " .. label)
	local ok, problem = pcall(function() return verifier.Verify(value, bytes) end)
	check(not ok, "Accepted invalid case: " .. label)
	check(tostring(problem):find(expectedError, 1, true) ~= nil, "Wrong rejection reason: " .. label)
	negative += 1
	table.insert(cases, {name = label, expected = "reject", passed = true})
end
local function factsMutation(label, mutate, expectedError)
	local value = copy(facts)
	mutate(value)
	reject(label, value, nativeRaw, expectedError)
end
local function nativeMutation(label, mutate, expectedError)
	print("PREPARE native: " .. label)
	local roots = rbx.deserializeModel(nativeRaw)
	mutate(roots)
	local bytes = rbx.serializeModel(roots)
	reject(label, repin(copy(facts), bytes), bytes, expectedError)
end
local function xmlMutation(label, transform, expectedError)
	local xml = rbx.serializeModel(rbx.deserializeModel(nativeRaw), true)
	local altered, applied = transform(xml)
	check(applied == 1, "DOM mutation not applied: " .. label)
	local bytes = rbx.serializeModel(rbx.deserializeModel(altered))
	reject(label, repin(copy(facts), bytes), bytes, expectedError)
end

accept("actual captured archive", facts, nativeRaw)
local reversed = copy(facts)
local rows = {}
for i = #reversed.roots, 1, -1 do table.insert(rows, reversed.roots[i]) end
reversed.roots = rows
accept("fact order independent", reversed, nativeRaw)
local rootsReversed = rbx.deserializeModel(nativeRaw)
rows = {}
for i = #rootsReversed, 1, -1 do table.insert(rows, rootsReversed[i]) end
local reversedBytes = rbx.serializeModel(rows)
accept("native order independent", repin(copy(facts), reversedBytes), reversedBytes)

-- Independent authoring-style attributes/tags use known, manually specified facts.
local extraRoots = rbx.deserializeModel(nativeRaw)
local firstName = extraRoots[1].Name
extraRoots[1]:SetAttribute("FixtureVector", rbx.Vector3.new(1, 2, 3))
extraRoots[1]:SetAttribute("FixtureColor", rbx.Color3.new(0.25, 0.5, 0.75))
extraRoots[1]:SetAttribute("FixtureUDim", rbx.UDim.new(0.25, 12))
extraRoots[1]:SetAttribute("FixtureRange", rbx.NumberRange.new(1, 3))
extraRoots[1]:SetAttribute("FixtureString", "nul\0line\n\u{1F4BE}")
extraRoots[1]:AddTag("z_fixture"); extraRoots[1]:AddTag("a_fixture")
local extraFacts = copy(facts)
for _, row in ipairs(extraFacts.roots) do
	if row.name == firstName then
		row.attributes.FixtureVector = {type = "Vector3", value = {1, 2, 3}}
		row.attributes.FixtureColor = {type = "Color3", value = {0.25, 0.5, 0.75}}
		row.attributes.FixtureUDim = {type = "UDim", value = {0.25, 12}}
		row.attributes.FixtureRange = {type = "NumberRange", value = {1, 3}}
		row.attributes.FixtureString = {type = "string", value = "nul\0line\n\u{1F4BE}"}
		row.tags = {"z_fixture", "a_fixture"}
	end
end
local extraBytes = rbx.serializeModel(extraRoots)
accept("typed attributes, exact strings and unordered tags", repin(extraFacts, extraBytes), extraBytes)

factsMutation("wrong schema", function(v) v.schema = "old" end, "Wrong archive schema")
factsMutation("wrong place", function(v) v.placeId = 1 end, "Wrong archive place")
factsMutation("wrong universe", function(v) v.universeId = 1 end, "Wrong archive place")
factsMutation("wrong digest", function(v) v.nativeSHA256 = string.rep("0", 64) end, "Native SHA256 differs")
factsMutation("wrong length", function(v) v.nativeBytes += 1 end, "Native byte length differs")
factsMutation("missing fact root", function(v) table.remove(v.roots) end, "exactly 12 roots")
factsMutation("duplicate fact root", function(v) v.roots[2] = copy(v.roots[1]) end, "Duplicate fact root")
factsMutation("unknown fact root", function(v) v.roots[1].name = "Other" end, "Unexpected fact root")
factsMutation("non-array root facts", function(v) v.roots.extra = copy(v.roots[1]) end, "Non-array root facts")
factsMutation("wrong fact class", function(v) v.roots[1].class = "Model" end, "Root class differs")
factsMutation("wrong fact children", function(v) v.roots[1].children = 1 end, "children are not zero")
factsMutation("wrong fact archivable", function(v) v.roots[1].archivable = false end, "Archivable differs")
factsMutation("wrong fact attribute type", function(v) v.roots[1].attributes.Complete.type = "string" end, "Attributes differ")
factsMutation("missing fact attribute", function(v) v.roots[1].attributes.Complete = nil end, "Attributes differ")
factsMutation("extra fact attribute", function(v) v.roots[1].attributes.Unexpected = {type = "boolean", value = true} end, "Attributes differ")
factsMutation("wrong fact tags", function(v) v.roots[1].tags = {"missing_tag"} end, "Tags differ")
factsMutation("duplicate fact tags", function(v) v.roots[1].tags = {"tag", "tag"} end, "Invalid/duplicate tag fact")
factsMutation("non-array fact tags", function(v) v.roots[1].tags = {extra = "tag"} end, "Non-array tag facts")
factsMutation("wrong fact sandboxed", function(v) v.roots[1].properties.Sandboxed = true end, "Property differs: Sandboxed")
factsMutation("wrong fact icon tint", function(v) v.roots[1].properties.IconTint = {1, 0, 0} end, "Property differs: IconTint")
factsMutation("wrong fact capabilities", function(v) v.roots[1].properties.Capabilities = "RunServerScript" end, "Property differs: Capabilities")
factsMutation("unsupported fact property", function(v) v.roots[1].properties.Unknown = true end, "Unsupported fact property")
reject("same-length native byte corruption", facts, "X" .. nativeRaw:sub(2), "Native SHA256 differs")
reject("native byte truncation", facts, nativeRaw:sub(1, #nativeRaw - 1), "Native byte length differs")
nativeMutation("unexpected native root name", function(v) v[1].Name = "Other" end, "Unexpected native root")
nativeMutation("duplicate native root name", function(v) v[2].Name = v[1].Name end, "Duplicate native root")
xmlMutation("native class mutation", function(xml)
	return xml:gsub('<Item class="Folder"', '<Item class="Model"', 1)
end, "Root class differs")
nativeMutation("native missing root", function(v) table.remove(v) end, "exactly 12 roots")
xmlMutation("native extra root", function(xml)
	return xml:gsub('</roblox>%s*$', '<Item class="Folder" referent="RBXMUTANTROOT"><Properties>'
		.. '<string name="Name">Other</string></Properties></Item></roblox>', 1)
end, "exactly 12 roots")
xmlMutation("native extra child", function(xml)
	return xml:gsub('</Properties>', '</Properties><Item class="Folder" referent="RBXMUTANTCHILD"><Properties>'
		.. '<string name="Name">Child</string></Properties></Item>', 1)
end, "children are not zero")
nativeMutation("native attribute removal", function(v) v[1]:SetAttribute("Complete", nil) end, "Attributes differ")
nativeMutation("native attribute addition", function(v) v[1]:SetAttribute("Unexpected", true) end, "Attributes differ")
nativeMutation("native attribute type change", function(v) v[1]:SetAttribute("Complete", "true") end, "Attributes differ")
nativeMutation("native result string change", function(v) v[1]:SetAttribute("Result001", "changed fixture result") end, "Attributes differ")
nativeMutation("native numeric metadata change", function(v) v[1]:SetAttribute("Bytes", v[1]:GetAttribute("Bytes") + 1) end, "Attributes differ")
nativeMutation("native tag addition", function(v) v[1]:AddTag("unexpected") end, "Tags differ")
nativeMutation("native sandbox change", function(v) v[1].Sandboxed = true end, "Property differs: Sandboxed")

local xml = rbx.serializeModel(rbx.deserializeModel(nativeRaw), true)
local wrongCaps, capsCount = xml:gsub('<SecurityCapabilities name="Capabilities">0</SecurityCapabilities>',
	'<SecurityCapabilities name="Capabilities">1</SecurityCapabilities>', 1)
check(capsCount == 1, "Capability DOM mutation not applied")
local wrongCapsBytes = rbx.serializeModel(rbx.deserializeModel(wrongCaps))
reject("native nonzero capability bitset", repin(copy(facts), wrongCapsBytes), wrongCapsBytes,
	"Unsupported/missing nonzero native capability bitset")
local wrongTint, tintCount = xml:gsub('<Color3 name="IconTint">%s*<R>0</R>', '<Color3 name="IconTint"><R>1</R>', 1)
check(tintCount == 1, "IconTint DOM mutation not applied")
local wrongTintBytes = rbx.serializeModel(rbx.deserializeModel(wrongTint))
reject("native icon tint change", repin(copy(facts), wrongTintBytes), wrongTintBytes, "Property differs: IconTint")

check(fs.readFile(factsPath) == factsRaw, "Immutable facts changed")
check(fs.readFile(nativePath) == nativeRaw, "Immutable native archive changed")
local report = {schema = "diagnostic-folder-archive-offline-tests-v1", passed = true,
	checks = checks, positiveCases = positive, negativeCases = negative, cases = cases,
	factsSHA256 = serde.hash("sha256", factsRaw), nativeSHA256 = serde.hash("sha256", nativeRaw),
	verifierSHA256 = serde.hash("sha256", fs.readFile("tools/cleanup_20261009/diagnostic_folder_archive.luau")),
	testSHA256 = serde.hash("sha256", fs.readFile("tools/cleanup_20261009/test_diagnostic_folder_archive.luau")),
	limits = "All mutations are local deserialized copies; no Studio connection, gameplay or place-restore claim."}
fs.writeFile(output, serde.encode("json", report, true) .. "\n")
print(serde.encode("json", {passed = true, checks = checks, positiveCases = positive,
	negativeCases = negative, receipt = output}))
