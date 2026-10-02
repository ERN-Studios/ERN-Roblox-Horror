local fs,luau,serde=require("@lune/fs"),require("@lune/luau"),require("@lune/serde")
local root="tools/level3_promotion_20261002/admission/"
local m=serde.decode("json",fs.readFile(root.."candidate-manifest.json"))
local receipt={Scope="Exact syntax only, no Studio or gameplay claim",Sources={}}
for _,x in ipairs(m.changes)do
 local source=fs.readFile(x.candidateFile)
 assert(serde.hash("sha256",source)==x.candidateSHA256,"manifest SHA mismatch")
 luau.compile(source)
 table.insert(receipt.Sources,{Path=x.path,SHA256=x.candidateSHA256,Bytes=#source,Syntax="PASS"})
end
receipt.Passed=true
fs.writeFile(root.."compile-receipt.json",serde.encode("json",receipt,true).."\n")
print(serde.encode("json",receipt,true))
