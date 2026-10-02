local fs, luau, serde=require("@lune/fs"),require("@lune/luau"),require("@lune/serde")
local root="tools/lobby_reimagined/dev_gate_20261002/"
local records={}
for _,name in ipairs({"play-probe-client-readonly.luau","play-probe-server-readonly.luau"})do
	local source=fs.readFile(root..name)
	local ok,why=pcall(luau.compile,source)
	table.insert(records,{file=name,sha256=serde.hash("sha256",source),bytes=#source,passed=ok,error=if ok then nil else tostring(why)})
	assert(ok,tostring(why))
end
local receipt={scope="Exact read-only probe syntax only; not Studio Play",passed=true,records=records}
fs.writeFile(root.."play-probe-syntax-receipt.json",serde.encode("json",receipt,true).."\n")
print(serde.encode("json",receipt,true))
