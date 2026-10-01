-- Read-only local syntax compilation, no candidate execution or Studio.
local fs = require("@lune/fs")
local luau = require("@lune/luau")
local serde = require("@lune/serde")
local process = require("@lune/process")
local records = {}
for _, path in ipairs(process.args) do
 local source = fs.readFile(path)
 luau.compile(source)
 table.insert(records, {file=path, bytes=#source, syntax="passed", executed=false})
end
fs.writeFile("artifacts/lobby-reimagined-r3-20261001/claude-review/active-v4-syntax.json", serde.encode("json", {passed=true, candidates=records, limitations="Syntax only; no Roblox API/runtime/gameplay check."}, true))
print(serde.encode("json", {passed=true, count=#records, executed=false}))
