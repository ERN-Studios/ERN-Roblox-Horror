local fs = require("@lune/fs")
local luau = require("@lune/luau")
local root = "tools/level3_promotion_20261002/gameplay_boards/candidates"
local count = 0
for _, name in ipairs(fs.readDir(root)) do
    if name:sub(-5) == ".luau" then
        luau.compile(fs.readFile(root .. "/" .. name))
        count += 1
    end
end
assert(count == 4, "Expected exactly four scoped gameplay/board candidates")
print("Syntax-only compile passed for " .. count .. " candidates; no gameplay pass implied")
