local fs, luau = require("@lune/fs"), require("@lune/luau")
local paths = {
    "tools/level3_finale_player_20261002/device/Level 3 Worn Party Visual Adapter.candidate.luau",
    "tools/level3_finale_player_20261002/device/Level 3 World Builder.candidate.luau",
}
for _, path in paths do
    luau.compile(fs.readFile(path))
    print("SYNTAX PASS " .. path)
end
