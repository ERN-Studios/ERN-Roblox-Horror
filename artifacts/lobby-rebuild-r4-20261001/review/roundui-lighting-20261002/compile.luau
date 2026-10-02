local fs=require("@lune/fs")
local luau=require("@lune/luau")
local serde=require("@lune/serde")
local path="/private/tmp/lobby-r4-roundui-lighting-review/RoundUI.candidate.luau"
local text=fs.readFile(path)
local ok,why=pcall(luau.compile,text)
local result={path="StarterPlayer.StarterPlayerScripts.RoundUI",candidateFile=path,bytes=#text,sha256=serde.hash("sha256",text),passed=ok,error=if ok then nil else tostring(why),scope="Exact local Luau syntax only; no Studio or Play"}
fs.writeFile("/private/tmp/lobby-r4-roundui-lighting-review/syntax-receipt-final.json",serde.encode("json",result,true).."\n")
print(serde.encode("json",result,true));assert(ok)
