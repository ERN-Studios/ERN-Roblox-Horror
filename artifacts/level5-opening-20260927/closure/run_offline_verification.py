"""Exercise exact closure access/room construction source without Roblox writes."""
from pathlib import Path
import json
import subprocess

folder = Path(__file__).resolve().parent
root = folder.parents[2]
runtime = root / "output/level5-build/tools/luau/luau"
compiler = runtime.with_name("luau-compile")
source_dir = folder / "sources/ServerScriptService"
game = (source_dir / "GameManager.Script.lua").read_text()
builder = (source_dir / "TunnelLobbyBuilder.ModuleScript.lua").read_text()

start = game.index('if workspace:GetAttribute("Level5PublicPreviewEnabled") == nil then')
end = game.index("\n-- Always-on server authority", start)
access = game[start:end]
start = builder.index("\tlocal levelDefs = {")
end = builder.index("\n\t-- Startup fingerprint", start)
construction = builder[start:end]

prefix = '''local Routing=require("../baseline/sources/ServerScriptService/Round Completion Routing.ModuleScript")
local attrs={}
local workspace={GetAttribute=function(_,key) return attrs[key] end,SetAttribute=function(_,key,value) attrs[key]=value end}
local DevAccess={IsAllowed=function(player) return player.developer==true end}
local normal={developer=false};local developer={developer=true}
local assertions=0
local function check(ok,message) assertions+=1;assert(ok,message) end
local function setup(initial)
 attrs=table.clone(initial or {})
'''
suffix = '''
 return canAccessLevel,devCeiling
end
for _,initial in ipairs({{}, {Level5PublicPreviewEnabled=false,Level5DevEnabled=false},
 {Level5PublicPreviewEnabled=false,Level5DevEnabled=false,Level4DevEnabled=true}}) do
 local access,ceiling=setup(initial)
 check(attrs.Level5PublicPreviewEnabled==false,"Public Level 5 default reopened")
 check(attrs[Routing.Level5DevAttribute]==false,"Developer Level 5 default reopened")
 for _,group in ipairs({{normal},{developer},{normal,developer},{developer,developer},{}}) do
  check(not access(5,group),"Closed Level 5 accepted a roster")
  check(ceiling(group)<5,"Closed Level 5 transport ceiling enabled")
  check(not access(6,group),"Level 6 unexpectedly enabled")
  for level=1,3 do check(access(level,group),"Existing public campaign level changed") end
 end
 check(not access(5,nil),"Closed Level 5 accepted nil roster")
 check(not access(5.5,{developer}),"Fractional level accepted")
 check(not access(0,{developer}),"Invalid level accepted")
 check(not access(nil,{developer}),"Nil level accepted")
end
local access=setup({Level4DevEnabled=true})
check(access(4,{developer}),"Existing Level 4 developer policy changed")
check(not access(4,{normal}),"Level 4 opened to normal players")
check(not access(4,{normal,developer}),"Level 4 mixed roster allowed")
-- Closure is the saved configuration, not deletion of future authoring controls.
access=setup({Level5DevEnabled=true,Level5PublicPreviewEnabled=false})
check(access(5,{developer}) and not access(5,{normal}),"Explicit future developer override changed")
access=setup({Level5DevEnabled=false,Level5PublicPreviewEnabled=true})
check(access(5,{normal}) and not access(5,{}),"Explicit future preview override changed")
local roomActive,doorActive={},{}
local rooms,center,doors={},{},{}
local stations={}
local function addDoorway(_,_,level,_,_,active) doorActive[level]=active end
local function addRoom(_,_,level,_,_,active) roomActive[level]=active end
'''
ending = '''
check(doorActive[5]==false,"Level 5 doorway built open")
check(roomActive[5]==false,"Level 5 stations built active behind closed door")
for level=1,3 do check(doorActive[level]==true and roomActive[level]==true,"Existing public lobby bay changed") end
check(doorActive[4]==false and roomActive[4]==true,"Existing Level 4 developer station behavior changed")
check(doorActive[6]==false and roomActive[6]==false,"Level 6 offline behavior changed")
print("PASS: "..assertions.." assertions; exact extracted access defaults deny Level 5 to normal/developer/mixed rosters; actual builder room/door expressions keep Level 5 closed.")
print("Offline source execution only; does not claim native queue or teleport behavior.")
'''
test = folder / "test_closed_access.generated.luau"
test.write_text(prefix + access + suffix + construction + ending)
results = []
for name, args in [
    ("compile mirrored closure scripts", [str(compiler), "--null", str(source_dir / "GameManager.Script.lua"), str(source_dir / "TunnelLobbyBuilder.ModuleScript.lua")]),
    ("exact access/default/builder tests", [str(runtime), str(test)]),
]:
    result = subprocess.run(args, text=True, capture_output=True)
    results.append({"name": name, "exitCode": result.returncode, "stdout": result.stdout, "stderr": result.stderr})
    print(result.stdout + result.stderr, end="")
(folder / "offline-verification.json").write_text(json.dumps(results, indent=2) + "\n")
raise SystemExit(0 if all(r["exitCode"] == 0 for r in results) else 1)
