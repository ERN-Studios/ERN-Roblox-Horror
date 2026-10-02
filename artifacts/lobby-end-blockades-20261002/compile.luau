local fs=require("@lune/fs");local luau=require("@lune/luau");local serde=require("@lune/serde")
local result={scope="Syntax only",passed=true,sources={}}
for _,path in ipairs({"artifacts/lobby-end-blockades-20261002/Builder.candidate.luau","tools/lobby_reimagined/end_clutter_20261002/EndBlockades.ModuleScript.luau","tools/lobby_reimagined/dev_gate_20261002/R4DevGateController.LocalScript.candidate.luau","artifacts/lobby-end-blockades-20261002/install-scoped.luau"})do
 local s=fs.readFile(path);luau.compile(s);table.insert(result.sources,{path=path,sha256=serde.hash("sha256",s),bytes=#s,syntax="PASS"})
end
fs.writeFile("artifacts/lobby-end-blockades-20261002/syntax-receipt.json",serde.encode("json",result,true))
print(serde.encode("json",result))
