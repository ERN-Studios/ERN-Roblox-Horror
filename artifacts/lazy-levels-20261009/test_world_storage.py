"""Execute the actual storage module with small containers; no Studio mutation."""
from pathlib import Path
import argparse
import hashlib
import json
import subprocess
import tempfile
import os
import shutil

ROOT = Path(__file__).resolve().parents[2]
HERE = Path(__file__).resolve().parent
parser = argparse.ArgumentParser()
parser.add_argument("--candidate", action="store_true")
parser.add_argument("--luau", type=Path)
args = parser.parse_args()
source_path = HERE / "LevelWorldStorage.candidate.luau" if args.candidate else ROOT / "ServerScriptService/LevelWorldStorage.ModuleScript.lua"
source = source_path.read_text(encoding="utf-8")
luau = args.luau or os.environ.get("LUAU_BIN") or shutil.which("luau")
if not luau:
    local_tool = ROOT / "artifacts/hazmat-20260924/luau-0.737/luau.exe"
    if local_tool.is_file():
        luau = local_tool
if not luau or not Path(luau).is_file():
    parser.error("Supply --luau or LUAU_BIN; no tests executed")
prelude = r'''
local count, objects = 0, {}
local function check(value, message) count += 1 assert(value, message) end
local function container(name)
    local result = {Name=name}
    function result:GetChildren()
        local children = {}
        for _, object in objects do if object.Parent == self then table.insert(children, object) end end
        return children
    end
    return result
end
local workspace, parked = container("Workspace"), container("ServerStorage")
local game = {GetService=function(_, name) assert(name=="ServerStorage") return parked end}
local function model(name, parent, class)
    local result = {Name=name, Parent=parent, ClassName=class or "Model", Art={Texture="asset:123", Pivot={1,2,3}}}
    function result:IsA(name) return self.ClassName==name end
    table.insert(objects,result)
    return result
end
local Storage = (function()
SOURCE
end)()
check(#workspace:GetChildren()==0, "module import loaded a map")
local a = model("Level 4 Cinema Blender", parked)
local b = model("Level 5 Void", parked)
local c = model("Level 6 Indoor Playground", parked)
local art = a.Art
for _, level in {4,5,6} do
    local expected = level==4 and a or level==5 and b or c
    check(Storage.Get(level)==expected, "readiness changed model identity")
    check(expected.Parent==parked, "readiness loaded an inactive map")
    check(Storage.Activate(level)==expected, "entry replaced the authored model")
    check(expected.Parent==workspace, "entry did not mount its map")
    check(Storage.Activate(level)==expected, "repeated entry duplicated the map")
    check(Storage.Deactivate(level)==expected, "cleanup replaced the authored model")
    check(expected.Parent==parked, "cleanup kept inactive map live")
    check(Storage.Deactivate(level)==expected, "repeated cleanup lost the map")
    check(Storage.Activate(level)==expected, "second entry changed identity")
    check(Storage.Deactivate(level)==expected, "second cleanup changed identity")
end
check(a.Art==art and a.Art.Texture=="asset:123" and a.Art.Pivot[2]==2, "parking changed non-script data")
Storage.Activate(5); Storage.Activate(6)
check(b.Parent==workspace and c.Parent==workspace and a.Parent==parked, "overlapping 5-to-6 transfer loaded Level 4")
Storage.Deactivate(5)
check(b.Parent==parked and c.Parent==workspace, "Level 5 cleanup removed active Level 6")
Storage.Deactivate(6)
local duplicate = model(a.Name, parked)
check(not pcall(Storage.Activate,4), "duplicate parked map was accepted")
check(a.Parent==parked and duplicate.Parent==parked, "duplicate refusal changed either map")
duplicate.Parent=nil
local conflicting = model(a.Name,workspace)
check(not pcall(Storage.Deactivate,4), "live/stored collision was accepted")
check(a.Parent==parked and conflicting.Parent==workspace, "collision handling destroyed or moved developer work")
conflicting.Parent=nil
local wrongClass = model(c.Name,workspace,"Folder")
c.Parent=nil
check(not pcall(Storage.Activate,6), "non-Model map was accepted")
wrongClass.Parent=nil
check(Storage.Get(6)==nil and Storage.Activate(6)==nil, "missing map falsely reported loaded")
check(Storage.Deactivate(6)==nil, "missing map cleanup invented data")
check(not pcall(Storage.Get,1), "unsupported level touched generated maps")
print("world storage checks="..count)
'''
with tempfile.TemporaryDirectory(prefix="lazy-level-storage-") as directory:
    test = Path(directory) / "test.luau"
    test.write_text(prelude.replace("SOURCE", source), encoding="utf-8")
    result = subprocess.run([str(luau), str(test)], capture_output=True, text=True, timeout=20)
    assert result.returncode == 0, result.stdout + result.stderr
    print(result.stdout.strip())
    print(json.dumps({"sourceSHA256": hashlib.sha256(source.encode()).hexdigest(), "scope": "Offline container/identity contract; native streaming and gameplay are separate"}))
