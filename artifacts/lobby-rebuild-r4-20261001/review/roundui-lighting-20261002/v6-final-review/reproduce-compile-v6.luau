local fs=require("@lune/fs")
local luau=require("@lune/luau")
local serde=require("@lune/serde")
local path="/Users/zeanjuul4/Documents/Roblox Horror REPO/artifacts/lobby-rebuild-r4-20261001/review/roundui-lighting-20261002/v6-final-review/RoundUI.v6.candidate.luau"
local text=fs.readFile(path)
local ok,why=pcall(luau.compile,text)
local result={path="StarterPlayer.StarterPlayerScripts.RoundUI",candidateFile=path,bytes=#text,sha256=serde.hash("sha256",text),passed=ok,error=if ok then nil else tostring(why),scope="Exact local Luau syntax only; no Studio or Play"}
fs.writeFile("/Users/zeanjuul4/Documents/Roblox Horror REPO/artifacts/lobby-rebuild-r4-20261001/review/roundui-lighting-20261002/v6-final-review/reproduced-syntax-receipt-v6.json",serde.encode("json",result,true).."\n")
print(serde.encode("json",result,true));assert(ok)
