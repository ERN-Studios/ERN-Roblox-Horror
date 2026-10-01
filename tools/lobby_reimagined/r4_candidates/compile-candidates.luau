local fs = require("@lune/fs")
local luau = require("@lune/luau")
local serde = require("@lune/serde")
local root = "tools/lobby_reimagined/r4_candidates/"
local manifest = serde.decode("json", fs.readFile(root.."candidate-manifest.json"))
local result = {scope="Exact candidate syntax only; no Studio writes or gameplay claim", compiler="@lune/luau.compile",passed=true,sources={}}
for _,entry in ipairs(manifest) do
 local source=fs.readFile(root..entry.candidateFile)
 local ok,err=pcall(function()luau.compile(source)end)
 table.insert(result.sources,{path=entry.path,file=entry.candidateFile,bytes=#source,sha256=serde.hash("sha256",source),syntax=if ok then "PASS" else tostring(err)})
 result.passed=result.passed and ok
end
fs.writeFile(root.."syntax-receipt-v6.json",serde.encode("json",result,true).."\n")
print(serde.encode("json",result,true))
assert(result.passed,"Candidate syntax failed")
