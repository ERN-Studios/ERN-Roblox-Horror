-- Local syntax only. Never execute a candidate or connect to Studio.
local fs = require("@lune/fs")
local luau = require("@lune/luau")
local serde = require("@lune/serde")
local process = require("@lune/process")
local paths = {
	"tools/lobby_reimagined/runtime_bake.ModuleScript.luau",
	"tools/lobby_reimagined/preview_builder.ModuleScript.luau",
	"tools/lobby_reimagined/preview_bootstrap.Script.luau",
	"tools/lobby_reimagined/queue_controller.LocalScript.luau",
}
for _, path in ipairs(process.args) do table.insert(paths, path) end
local records = {}
for _, path in ipairs(paths) do
	local text = fs.readFile(path)
	luau.compile(text)
	table.insert(records, {file = path, bytes = #text, syntax = "passed", executed = false})
end
local report = {passed = true, candidates = records, limitations = "Syntax only; no Roblox API/runtime/render/replication check."}
fs.writeFile("artifacts/lobby-reimagined-20261001/candidate-syntax-verification.json", serde.encode("json", report, true))
print(serde.encode("json", {passed = true, count = #records, executed = false}))
