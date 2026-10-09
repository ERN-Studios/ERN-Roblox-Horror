-- Local native decode only. Writes XML into the Python validator's owned tempdir.
local fs = require("@lune/fs")
local process = require("@lune/process")
local serde = require("@lune/serde")
local rbx = require("@lune/roblox")
local verifier = require("./diagnostic_folder_archive")
assert(#process.args == 3, "Pass facts JSON, reference RBXM, NEW owned XML tempfile")
local factsPath, nativePath, output = table.unpack(process.args)
assert(not fs.isFile(output) and not fs.isDir(output), "Refusing existing XML output")
local facts = serde.decode("json", fs.readFile(factsPath))
local bytes = fs.readFile(nativePath)
assert(#bytes == facts.referencesBytes and serde.hash("sha256", bytes) == facts.referencesSHA256,
	"Reference archive hash/length differs")
local roots = rbx.deserializeModel(bytes)
assert(#roots == 13, "Reference forest must contain 13 roots")
local folders, starterPlayer = {}, nil
for _, root in ipairs(roots) do
	assert(root.Parent == nil, "Reference root must be unparented")
	if root.ClassName == "StarterPlayer" then
		assert(not starterPlayer and root.Name == "StarterPlayer", "Unexpected StarterPlayer root")
		starterPlayer = root
	else
		assert(root.ClassName == "Folder", "Unexpected reference root class")
		table.insert(folders, root)
	end
end
assert(starterPlayer and #folders == 12, "Reference forest target set differs")
local subset = rbx.serializeModel(folders)
facts.nativeBytes, facts.nativeSHA256 = #subset, serde.hash("sha256", subset)
verifier.Verify(facts, subset) -- Exact target facts; hashes of the joint forest were checked above.
local xml = rbx.serializeModel(roots, true)
-- Reopening the complete joint forest must preserve all canonical native properties/referents.
local canonical = rbx.serializeModel(roots)
assert(rbx.serializeModel(rbx.deserializeModel(canonical)) == canonical, "Reference canonical reopen differs")
fs.writeFile(output, xml)
print(serde.encode("json", {verified = true, rootCount = 13, targetsVerified = 12,
	referencesSHA256 = serde.hash("sha256", bytes), xmlSHA256 = serde.hash("sha256", xml),
	canonicalSHA256 = serde.hash("sha256", canonical), xmlBytes = #xml}))
