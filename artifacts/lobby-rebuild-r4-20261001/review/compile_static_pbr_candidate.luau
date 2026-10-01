local fs = require("@lune/fs")
local luau = require("@lune/luau")
local serde = require("@lune/serde")
local file = "artifacts/lobby-rebuild-r4-20261001/review/RuntimeBake.static-pbr.candidate.ModuleScript.luau"
local source = fs.readFile(file)
local ok, why = pcall(function() luau.compile(source) end)
local receipt = {scope="Local syntax check only; no Studio execution or gameplay claim",file=file,
    sha256=serde.hash("sha256",source),bytes=#source,passed=ok,error=if ok then nil else tostring(why)}
fs.writeFile("artifacts/lobby-rebuild-r4-20261001/review/static-pbr-syntax-receipt.json",serde.encode("json",receipt,true).."\n")
print(serde.encode("json",receipt,true))
assert(ok,"Static PBR candidate syntax failure")
