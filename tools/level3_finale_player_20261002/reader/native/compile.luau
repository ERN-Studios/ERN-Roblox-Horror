local fs,luau=require("@lune/fs"),require("@lune/luau")
luau.compile(fs.readFile("tools/level3_finale_player_20261002/reader/native/verify-native-five.luau"))
print("Native comparison helper compiled; no native-after or live-parity claim.")
