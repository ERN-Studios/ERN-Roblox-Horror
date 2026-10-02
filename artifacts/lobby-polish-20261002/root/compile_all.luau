local fs=require("@lune/fs")
local serde=require("@lune/serde")
local luau=require("@lune/luau")
local c=serde.decode("json",fs.readFile("artifacts/lobby-polish-20261002/root/install-catalog.json"))
for _,row in ipairs(c.sources) do luau.compile(row.source); print(row.path,"compiled") end
luau.compile(fs.readFile("artifacts/lobby-polish-20261002/root/install-scoped.luau"))
print("Installer compiled")
