-- Syntax-only gate for local Level 6 candidates. No Studio mutations.
local fs = require("@lune/fs")
local luau = require("@lune/luau")

local roots = {
    "tools/level6_build/gameplay-candidates",
    "tools/level6_build/import",
    "tools/level6_build/import/shared-candidates",
}

local count = 0
for _, root in roots do
    for _, name in fs.readDir(root) do
        if name:sub(-5) == ".luau" then
            luau.compile(fs.readFile(root .. "/" .. name))
            count += 1
        end
    end
end
luau.compile(fs.readFile("tools/level6_build/room_dressing.luau"))
count += 1
print("Level 6 Luau syntax OK: " .. count .. " candidates")
