-- Same actual-installer CAS harness, now writes only three and guards all five.
local fs,luau=require("@lune/fs"),require("@lune/luau")
local source=fs.readFile("tools/level3_finale_player_20261002/test-delta-install.luau")
source=source:gsub("source%-manifest%.v2%.json","incremental-source-manifest.json")
source=source:gsub("install%-five%-scoped%.v2%.luau","install-three-incremental.luau")
source=source:gsub("installer%-mock%-receipt%.json","incremental-installer-mock-receipt.json")
source=source:gsub("local first=manifest%.changes%[1%]%.path","local first=manifest.changes[2].path")
source=source:gsub("f%.writes==5 and f%.compiles==5","f.writes==3 and f.compiles==5")
source=source:gsub("f%.nodes%[manifest%.changes%[1%]%.path%]%.Source:find","f.nodes[manifest.changes[2].path].Source:find")
source=source:gsub("serde%.hash%(\"sha256\",f%.nodes%[manifest%.changes%[2%]%.path%]%.Source%)==manifest%.changes%[2%]%.baselineSHA256",
    'serde.hash("sha256",f.nodes[manifest.changes[4].path].Source)==manifest.changes[4].baselineSHA256')
source=source:gsub("valid five%-source CAS prepares exact candidate hashes and writes all five",
    "valid incremental CAS prepares all five exact hashes and writes only three")
luau.load(source,{environment={require=require}})()
