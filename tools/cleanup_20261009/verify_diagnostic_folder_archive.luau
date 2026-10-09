-- lune run tools/cleanup_20261009/verify_diagnostic_folder_archive.luau FACTS.json SNAPSHOT.rbxm NEW-RECEIPT.json
-- Never connects to Studio or writes the input facts/archive.
local fs = require("@lune/fs")
local process = require("@lune/process")
local serde = require("@lune/serde")
local verifier = require("./diagnostic_folder_archive")
assert(#process.args == 3, "Pass facts JSON, native RBXM, and a NEW receipt filename")
local factsPath, nativePath, receiptPath = table.unpack(process.args)
assert(not fs.isFile(receiptPath) and not fs.isDir(receiptPath), "Refusing existing receipt path")
local factsBytes, nativeBytes = fs.readFile(factsPath), fs.readFile(nativePath)
local report = verifier.Verify(serde.decode("json", factsBytes), nativeBytes)
report.factsSHA256 = serde.hash("sha256", factsBytes)
report.verifierSHA256 = serde.hash("sha256", fs.readFile("tools/cleanup_20261009/diagnostic_folder_archive.luau"))
report.runnerSHA256 = serde.hash("sha256", fs.readFile("tools/cleanup_20261009/verify_diagnostic_folder_archive.luau"))
report.runtime = "Lune @lune/roblox"
-- No attributes or test-token values are printed.
fs.writeFile(receiptPath, serde.encode("json", report, true) .. "\n")
print(serde.encode("json", {verified = true, rootCount = report.rootCount,
	nativeSHA256 = report.nativeSHA256, factsSHA256 = report.factsSHA256, receipt = receiptPath}))
