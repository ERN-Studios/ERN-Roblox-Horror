-- Offline diagnostic only. Reads pinned historical binary archives.
-- Lune XML is a comparison view, never a native restoration certificate.
local fs = require("@lune/fs")
local roblox = require("@lune/roblox")
local serde = require("@lune/serde")
local process = require("@lune/process")
assert(#process.args == 1, "Provide new output directory")
local out = process.args[1]
local original = "artifacts/cleanup-serverstorage-20261009/external-storage-archive-v1/native.rbxm"
local roundtrip = "artifacts/cleanup-serverstorage-20261009/external-storage-reopen-v1/roundtrip.rbxm"
local inputs = {
 {name="original", path=original, bytes=2739764, sha="139a76d70022770ac30b0a4e9cfaeaea967668955ab0930666de0d3ab1f23dca"},
 {name="roundtrip", path=roundtrip, bytes=2739764, sha="dbfb34d6dc742c50c4b743fd7a5fc0e374599f3b8c81ea1e8f5d6baa455eb121"},
}
local result = {schema="s06-offline-lune-binary-diagnostic-v1", nativeCalls=0, nativeWrites=0,
 restorationCertified=false, limits="Lune decode of historical binaries only; unsupported engine/private/runtime fields may be omitted. No original live instance comparison or normalization."}
result.files = {}
for _, row in inputs do
 local raw = fs.readFile(row.path)
 assert(#raw == row.bytes and serde.hash("sha256", raw) == row.sha, "Pinned binary changed")
 local roots = roblox.deserializeModel(raw)
 assert(#roots == 23, "Expected 23 historical roots")
 local path = out .. "/" .. row.name .. ".rbxmx"
 assert(not fs.isFile(path) and not fs.isDir(path), "Refusing existing comparison output")
 local xml = roblox.serializeModel(roots, true)
 fs.writeFile(path, xml)
 table.insert(result.files, {name=row.name, inputPath=row.path, inputSHA256=row.sha, inputBytes=#raw,
  roots=#roots, xmlPath=path, xmlBytes=#xml, xmlSHA256=serde.hash("sha256",xml)})
end
print(serde.encode("json", result, true))
