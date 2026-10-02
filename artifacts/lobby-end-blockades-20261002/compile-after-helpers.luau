-- Syntax only: neither native capture nor preservation audit is executed here.
local fs,luau,serde=require("@lune/fs"),require("@lune/luau"),require("@lune/serde")
local root="artifacts/lobby-end-blockades-20261002/"
local rows={}
for _,name in ipairs({"capture-after-readonly.luau","verify-endfix-scoped-native.luau"})do
	local source=fs.readFile(root..name)
	local ok,why=pcall(luau.compile,source)
	table.insert(rows,{file=name,bytes=#source,sha256=serde.hash("sha256",source),passed=ok,error=if ok then nil else tostring(why)})
	assert(ok,tostring(why))
end
local receipt={scope="After helper Luau syntax only; no Studio/UI/server/capture or native-comparison execution",passed=true,files=rows}
fs.writeFile(root.."after-helper-syntax-receipt.json",serde.encode("json",receipt,true).."\n")
print(serde.encode("json",receipt,true))
