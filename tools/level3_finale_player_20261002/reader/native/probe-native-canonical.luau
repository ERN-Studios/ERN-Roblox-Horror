local fs,serde,rbx=require("@lune/fs"),require("@lune/serde"),require("@lune/roblox")
local path="/Users/zeanjuul4/Projects/RobloxStudioBackups/20261002-level3-finale-player/before/before.rbxl"
local bytes=fs.readFile(path)
local game=rbx.deserializePlace(bytes)
local sources=0
for _,i in game:GetDescendants() do if i:IsA("LuaSourceContainer") then sources+=1;i.Source="" end end
local a=serde.hash("sha256",rbx.serializePlace(game))
local b=serde.hash("sha256",rbx.serializePlace(game))
print(serde.encode("json",{bytes=#bytes,sha256=serde.hash("sha256",bytes),sources=sources,roots=#game:GetChildren(),descendants=#game:GetDescendants(),canonicalRepeatEqual=a==b,canonicalSHA256=a},true))
