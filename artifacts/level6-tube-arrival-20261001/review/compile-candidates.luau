local fs = require("@lune/fs")
local luau = require("@lune/luau")
local serde = require("@lune/serde")
local root = "artifacts/level6-tube-arrival-20261001/candidate-source/"
local names = {
"ServerScriptService.Level 6 Systems.Level 6 Layout Generator.ModuleScript.luau",
"ServerScriptService.Level 6 Systems.Level 6 Visual Adapter.ModuleScript.luau",
"ServerScriptService.Level 6 Systems.Level 6 World Builder.ModuleScript.luau",
"ServerScriptService.Level6PreviewAccess.Script.luau",
"StarterPlayer.StarterPlayerScripts.Level6PreviewTransport.LocalScript.luau",
}
local result = {scope="Exact candidate Luau syntax compilation only; no Studio or UI mutation",compiler="@lune/luau.compile",sources={},passed=true}
for _,name in names do
 local source = fs.readFile(root..name)
 local ok, err = pcall(function() luau.compile(source) end)
 table.insert(result.sources,{file=root..name,bytes=#source,sha256=serde.hash("sha256",source),syntax=if ok then "PASS" else tostring(err)})
 result.passed = result.passed and ok
end
fs.writeFile("artifacts/level6-tube-arrival-20261001/review/compiled-candidate-review.json",serde.encode("json",result,true).."\n")
print(serde.encode("json",result,true))
assert(result.passed,"Syntax review failed")
