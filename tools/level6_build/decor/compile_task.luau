local fs=require("@lune/fs")
local luau=require("@lune/luau")
local serde=require("@lune/serde")
local dir="artifacts/level6-entity-decor-20261001/candidates/combined"
local results={}
for _,name in fs.readDir(dir) do
    luau.compile(fs.readFile(dir.."/"..name))
    table.insert(results,{name=name,syntax="passed",executed=false})
end
fs.writeFile("artifacts/level6-entity-decor-20261001/syntax-verification.json",serde.encode("json",results,true))
print("Scoped Level 6 Luau syntax passed: "..#results)
