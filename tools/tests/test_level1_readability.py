"""Exercise the actual client lighting branch across extraction counts/modes/owners."""
from pathlib import Path
import ast
import json
import subprocess
import sys
import tempfile

ROOT = Path(__file__).resolve().parents[2]
SOURCE = Path(sys.argv[1]) if len(sys.argv) > 1 else ROOT / "StarterPlayer/StarterPlayerScripts/RoundUI.LocalScript.lua"
source = SOURCE.read_text(encoding="utf-8")
block = source[source.index("local function applyPlayerLighting()"):source.index('player:GetAttributeChangedSignal("InRound"):Connect(applyPlayerLighting)')]
program = r'''
local Color3={new=function(r,g,b)return {R=r,G=g,B=b} end}
Color3.fromRGB=function(r,g,b)return Color3.new(r/255,g/255,b/255) end
local attrs,playerAttrs,worlds={},{},{}
local workspace={GetAttribute=function(_,name)return attrs[name]end,FindFirstChild=function(_,name)return worlds[name]end}
local player={GetAttribute=function(_,name)return playerAttrs[name]end}
local Lighting={FindFirstChild=function()return nil end}
local lobbyGrade={}
local revisedLobbyLighting={contains=function()return false end,restore=function()end,apply=function()error("Unexpected lobby override")end}
''' + block + r'''
local checks=0
local function check(value)assert(value);checks+=1 end
playerAttrs.InRound=true;attrs.SelectedLevel=1;attrs.Level1BlenderActive=true
for _,total in ipairs({1,2,3,4,6}) do
 attrs.Level1RelaysPlaced=total
 for count=0,total do
  attrs.Level1RelaysExtracted=count
  attrs.LightMode="NORMAL"
  applyPlayerLighting()
  local stage=count*3>=total*2 and 3 or count*3>=total and 2 or 1
  check(Lighting.Ambient.R==({100,65,36})[stage]/255)
  check(Lighting.FogStart==({200,140,85})[stage] and Lighting.FogEnd==({900,650,450})[stage])
  check(Lighting.OutdoorAmbient.R==({35,20,10})[stage]/255)
  -- ALERT keeps a dim red fill (owner 2026-10-04); the dark phases stay dark.
  attrs.LightMode="ALERT";applyPlayerLighting()
  check(Lighting.Ambient.R==48/255 and Lighting.Ambient.G==14/255 and Lighting.FogEnd==450 and Lighting.Brightness==.3)
  for _,mode in ipairs({"POWERDOWN","BLACKOUT","ESCAPE"}) do
   attrs.LightMode=mode;applyPlayerLighting()
   check(Lighting.Ambient.R==4/255 and Lighting.FogEnd==220 and Lighting.Brightness==.3)
  end
 end
end
-- An unloaded relay cannot change this authoritative permanent counter.
attrs.Level1RelaysPlaced=3;attrs.Level1RelaysExtracted=2;attrs.LightMode="NORMAL";applyPlayerLighting()
check(Lighting.Ambient.R==36/255)
attrs.Level1BlenderActive=false;applyPlayerLighting();check(Lighting.Ambient.R==4/255)
attrs.Level1BlenderActive=true;attrs.SelectedLevel=4;applyPlayerLighting();check(Lighting.Ambient.R==4/255)
for _,owner in ipairs({"Level4LightingOwned","Level5LightingOwned","Level6PlaygroundLightingOwned"}) do
 playerAttrs[owner]=true;Lighting.Ambient="foreign-owned";applyPlayerLighting();check(Lighting.Ambient=="foreign-owned")
 playerAttrs[owner]=false
end
for _,n in ipairs({2,3}) do
 attrs.SelectedLevel=n;worlds["Level "..n.." Generated World"]={};attrs["Level"..n.."LightingOwnedByController"]=true
 Lighting.Ambient="owned";applyPlayerLighting();check(Lighting.Ambient=="owned")
 worlds["Level "..n.." Generated World"]=nil
end
worlds["Level 6 Generated World"]={};attrs.Level6SelectedLevel=6;attrs.Level6LightingOwnedByController=true;playerAttrs.Level6InRound=true
Lighting.Ambient="mall-owned";applyPlayerLighting();check(Lighting.Ambient=="mall-owned")
worlds["Level 6 Generated World"]=nil;playerAttrs.Level6InRound=false;playerAttrs.InRound=false;applyPlayerLighting()
check(Lighting.Ambient.R==76/255 and Lighting.FogEnd==100000 and lobbyGrade.Enabled==true)
-- Reset clears counts upstream; next preview enters C again.
playerAttrs.InRound=true;attrs.SelectedLevel=1;attrs.Level1RelaysExtracted=nil;applyPlayerLighting();check(Lighting.Ambient.R==100/255)
print("Level 1 lighting: "..checks.." actual client assertions passed (C/B/A, red/dark priority, owner guards, reset)")
'''
binary=ROOT / "artifacts/hazmat-20260924/luau-0.737/luau.exe"
with tempfile.TemporaryDirectory(prefix="level1-readability-") as d:
    target=Path(d)/"lighting.luau";target.write_text(program,encoding="utf-8")
    subprocess.run([str(binary),str(target)],check=True)
subprocess.run([str(binary.with_name("luau-compile.exe")),"--null",str(SOURCE)],check=True)

# Compile the actual installer template without importing it or touching Studio.
artifact = ROOT / "artifacts/level1-readability-20261002"
tree = ast.parse((artifact / "install_scoped.py").read_text(encoding="utf-8"))
templates = [node.value for node in ast.walk(tree) if isinstance(node, ast.Constant)
             and isinstance(node.value, str) and "Scoped Source/editor CAS applied:" in node.value]
assert len(templates) == 1, "Expected one scoped CAS Luau template"
patches = json.loads((artifact / "progression-patch.json").read_text(encoding="utf-8"))
with tempfile.TemporaryDirectory(prefix="level1-install-syntax-") as directory:
    for index, patch in enumerate(patches):
        segments = patch["repoFile"].split("/")
        segments[-1] = segments[-1].rsplit(".", 2)[0]
        payload = json.dumps({"segments": segments, "class": "Script", "rawBytes": 0,
                              "rawHash": 5381, "changes": patch["changes"]}, ensure_ascii=False)
        generated = templates[0].replace("PAYLOAD", json.dumps(payload, ensure_ascii=False))
        target = Path(directory) / (str(index) + ".luau")
        target.write_text(generated, encoding="utf-8")
        subprocess.run([str(binary.with_name("luau-compile.exe")), "--null", str(target)], check=True)
print("Level 1 installer: all four actual JSON payloads compile in the scoped CAS template")
