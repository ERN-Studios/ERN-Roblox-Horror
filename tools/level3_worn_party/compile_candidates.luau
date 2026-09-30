-- Syntax only. No Studio access or place mutation.
local fs = require("@lune/fs")
local luau = require("@lune/luau")

local root = "tools/level3_worn_party"
local count = 0
for _, name in fs.readDir(root) do
    if name:sub(-5) == ".luau" and name ~= "compile_candidates.luau" then
        luau.compile(fs.readFile(root .. "/" .. name))
        count += 1
    end
end
print("Level 3 Worn Party syntax OK: " .. count .. " candidates")
