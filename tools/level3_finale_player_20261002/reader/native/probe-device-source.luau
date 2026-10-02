local fs,serde,rbx=require("@lune/fs"),require("@lune/serde"),require("@lune/roblox")
local g=rbx.deserializePlace(fs.readFile("/Users/zeanjuul4/Projects/RobloxStudioBackups/20261002-level3-finale-player/before/before.rbxl"))
local s=g:FindFirstChild("ReplicatedStorage"):FindFirstChild("UIDevice").Source
local mirror=fs.readFile("ReplicatedStorage/UIDevice.ModuleScript.lua")
print(serde.encode("json",{nativeSHA256=serde.hash("sha256",s),mirrorEqualsNative=s==mirror,bytes=#s,hasMovementZones=s:find("Controls = controls",1,true)~=nil},true))
