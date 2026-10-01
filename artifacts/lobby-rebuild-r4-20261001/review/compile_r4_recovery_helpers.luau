local fs=require("@lune/fs")
local luau=require("@lune/luau")
local serde=require("@lune/serde")
local files={"artifacts/lobby-rebuild-r4-20261001/capture-r4-fresh-readonly.luau","artifacts/lobby-rebuild-r4-20261001/verify_r4_native_recovery.luau"}
local rows={}
for _,file in files do
 local source=fs.readFile(file)
 local ok,why=pcall(function()luau.compile(source)end)
 table.insert(rows,{file=file,sha256=serde.hash("sha256",source),bytes=#source,passed=ok,error=if ok then nil else tostring(why)})
 assert(ok,"Recovery helper syntax failure")
end
fs.writeFile("artifacts/lobby-rebuild-r4-20261001/review/recovery-helper-syntax-receipt-v2.json",serde.encode("json",{scope="Local syntax only; no Studio run or fresh recovery claim",sources=rows},true).."\n")
print(serde.encode("json",rows,true))
