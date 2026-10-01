-- Read-only local syntax gate for the two exact live-baseline candidates.
local fs = require("@lune/fs")
local luau = require("@lune/luau")
local root = "artifacts/level6-ceiling-lighting-20261001/candidate-source/"
for _, name in ipairs({
    "ServerScriptService.Level 6 Systems.Level 6 World Builder.ModuleScript.luau",
    "StarterPlayer.StarterPlayerScripts.Level 6 Lighting Controller.LocalScript.luau",
}) do
    local source = fs.readFile(root .. name)
    luau.compile(source)
    print("PASS syntax: " .. name .. " (" .. tostring(#source) .. " bytes)")
end
