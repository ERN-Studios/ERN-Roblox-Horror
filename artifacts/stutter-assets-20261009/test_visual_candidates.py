"""Run production visual fragments with the existing shop fake DataModel.

Defaults to promoted repository mirrors. --candidate uses local candidates;
--baseline additionally verifies the captured originals reproduce regressions.
This checks scheduling, late replication, restoration and cache invalidation.
It does not measure Roblox streaming, frame time, device rendering or gameplay.
"""
from pathlib import Path
import argparse
import ast
import json
import os
import shutil
import subprocess
import tempfile

ROOT = Path(__file__).resolve().parents[2]
HERE = Path(__file__).resolve().parent
LOCAL_LUAU = ROOT / "artifacts/hazmat-20260924/luau-0.737/luau.exe"
MIRRORS = (
    ROOT / "StarterPlayer/StarterPlayerScripts/Shop Display Client.LocalScript.lua",
    ROOT / "StarterPlayer/StarterPlayerScripts/Lobby DJ Client.LocalScript.lua",
    ROOT / "ServerScriptService/Level 1 Systems/BlenderRoomRenderer.ModuleScript.lua",
)
tree = ast.parse((ROOT / "tools/tests/test_lobby_shop_display.py").read_text(encoding="utf-8"))
PRELUDE = next(ast.literal_eval(node.value) for node in tree.body if isinstance(node, ast.Assign)
               and any(isinstance(name, ast.Name) and name.id == "PRELUDE" for name in node.targets))
PRELUDE = PRELUDE[:PRELUDE.index("local moduleResults = {}")]
PRELUDE = PRELUDE.replace("function methods:GetDescendants()\n", "function methods:GetDescendants()\n\t\tif inst == watchedShop then shopScans += 1 end\n")
PRELUDE = "local watchedShop, shopScans = nil, 0\n" + PRELUDE

SHOP_TEST = r'''
local RunService = runService
local lobby = Instance.new("Model"); lobby.Name = "ServerLobby"; lobby.Parent = workspace
local model = Instance.new("Model"); model.Name = "ZyntraShopDisplay"; model.Parent = lobby
model:SetAttribute("ShopItemCount", 2); watchedShop = model
local function box(name, phase)
    local part = Instance.new("Part"); part.Name = name
    part.CFrame = CFrame.new(0, 7, 0)
    part:SetAttribute("ShopBobOrigin", part.CFrame); part:SetAttribute("ShopBobPhase", phase)
    part.Parent = model; return part
end
local first = box("first", 0)
local stopDemo, evaluate = function() end, function() end
SOURCE
local clock = 0
local function beat(count)
    for _ = 1, count do clock += 1/60; heartbeat:Fire(1/60) end
end
beat(120)
check(shopScans <= 5, "incomplete streamed shop scanned every frame: " .. shopScans)
check(shopScans >= 3, "incomplete streamed shop never retried")
check(near(first.Position.Y, 7 + .35 * math.sin(clock * 2*math.pi/3.4)), "throttle changed the bob")
local before = shopScans
player:SetAttribute("InRound", true); beat(120)
check(shopScans == before, "in-round client scanned the lobby shop")
check(near(first.Position.Y, 7), "entering a round left the box bobbing")
player:SetAttribute("InRound", nil); workspace:SetAttribute("RoundActive", true); beat(60)
check(shopScans == before, "active round bystanders scanned the shop")
workspace:SetAttribute("RoundActive", nil)
local late = box("late", 1); beat(40)
check(near(late.Position.Y, 7 + .35 * math.sin(clock * 2*math.pi/3.4 + 1)), "late box not discovered within .67s")
before = shopScans; beat(120)
check(shopScans == before, "complete shop kept rescanning")
for _, flag in ipairs({"ReduceFlashing", "ReduceCameraShake"}) do
    player:SetAttribute(flag, true); beat(1)
    check(near(first.Position.Y, 7) and near(late.Position.Y, 7), flag .. " no longer restores the boxes")
    player:SetAttribute(flag, nil); beat(1)
end
model.Parent = nil; beat(1)
check(near(first.Position.Y, 7) and near(late.Position.Y, 7), "shop teardown did not restore boxes")
model.Parent = lobby; beat(1)
check(near(late.Position.Y, 7 + .35 * math.sin(clock * 2*math.pi/3.4 + 1)), "shop reappearance lost motion")
print("PASS shop: " .. checks .. " scheduling/replication/restoration checks; incomplete scans <= 2 Hz")
'''

DJ_TEST = r'''
local calls, reads = 0, 0
local HttpService = {}
function HttpService:JSONDecode(raw)
    calls += 1
    if raw == "one" then return {{Genre = "SYNTHWAVE", Bpm = 110}} end
    if raw == "two" then return {{Genre = "EURODANCE", Bpm = 120}} end
    error("invalid track JSON")
end
CACHE
workspace:SetAttribute("LobbyDJTracks", "one")
local first = tracks()
for _ = 1, 100 do check(tracks() == first, "stable JSON was not cached") end
check(calls == 1, "stable JSON decoded repeatedly")
workspace:SetAttribute("LobbyDJTracks", "two")
check(tracks()[1].Genre == "EURODANCE" and calls == 2, "changed catalogue did not invalidate")
workspace:SetAttribute("LobbyDJTracks", "broken")
for _ = 1, 20 do check(#tracks() == 0, "invalid JSON was not contained") end
check(calls == 3, "invalid JSON retried on every tick")
workspace:SetAttribute("LobbyDJTracks", nil)
check(#tracks() == 0, "removed catalogue kept stale tracks")
local before = calls; tracks(); check(calls == before, "absent catalogue retried")
local originalTracks = tracks
tracks = function() reads += 1; return originalTracks() end
local colours = {}; colours.__index = colours
function colours:Lerp(to, alpha) return to end
local oldRGB = Color3.fromRGB
Color3.fromRGB = function(...) return setmetatable(oldRGB(...), colours) end
function workspace:GetServerTimeNow() return 10 end
local lobby = Instance.new("Model"); lobby.Name = "LobbyReimaginedPreview"; lobby.Parent = workspace
lobby:SetAttribute("Ready", true)
local host = Instance.new("Part"); host.CFrame = CFrame.new(); host.Parent = lobby
local lamp = Instance.new("Light"); lamp.Enabled = true; lamp.Color = Color3.fromRGB(1,2,3); lamp.Brightness = 2; lamp.Parent = host
local baseColour = lamp.Color
LIGHTING
player:SetAttribute("InRound", true); workspace:SetAttribute("LobbyDJTracks", "one")
before = calls; for _ = 1, 30 do heartbeat:Fire(.05) end
check(reads == 0 and calls == before, "inactive lighting still reads/decodes the catalogue")
player:SetAttribute("InRound", nil); workspace:SetAttribute("ReservedRoundServer", true)
for _ = 1, 30 do heartbeat:Fire(.05) end
check(reads == 0, "reserved round lighting still reads the catalogue")
workspace:SetAttribute("ReservedRoundServer", nil); workspace:SetAttribute("LobbyDJTrack", 1)
heartbeat:Fire(.05)
check(reads == 1 and lamp.Color ~= baseColour, "lobby lighting did not start")
player:SetAttribute("InRound", true); heartbeat:Fire(.05)
check(reads == 1 and lamp.Color == baseColour and lamp.Brightness == 2, "leaving lobby failed to restore lamps")
print("PASS DJ: " .. checks .. " cache/invalid-input/inactive-gate/restoration checks")
'''

RENDERER_TEST = r'''
local Renderer = {}
HELPERS
local template = Instance.new("Model"); template.ModelStreamingMode = Enum.ModelStreamingMode.Default
function template:Clone()
    local clone = Instance.new("Model"); clone.ModelStreamingMode = self.ModelStreamingMode
    local roof = Instance.new("Part"); roof.Name = "Roof"; roof.CFrame = CFrame.new(0,14,0)
    roof.Size = Vector3.new(24,1,24); roof:SetAttribute("RoomRole", "SurfaceCeiling"); roof.Parent = clone
    local floor = Instance.new("Part"); floor.Name = "Floor"; floor.CFrame = CFrame.new()
    floor.Size = Vector3.new(24,1,24); floor:SetAttribute("RoomRole", "SurfaceFloor"); floor.Parent = clone
    return clone
end
function Renderer.PickRoom(choices) return choices[1] end
CF.__index = function(frame, key)
    if key == "Rotation" then return CFrame.new() end
    return rawget(CF, key)
end
function CF:ToObjectSpace(other) return CFrame.new(other.Position - self.Position) end
task.wait = function() end
local roomsByMask = {[15] = {template}}
local maze = Instance.new("Model"); maze.Name = "ProbeMaze"; maze.ModelStreamingMode = Enum.ModelStreamingMode.Default
local state = {recessCells = {}}
local matte = function() error("unexpected matte path") end
SOURCE
state:Rooms({{},{}}, {{},{}}, 2, 24, -24, {}, 0, 0)
local folder = maze:FindFirstChild("BlenderRooms")
check(folder and #folder:GetChildren() == 4, "room generation changed")
for _, room in ipairs(folder:GetChildren()) do
    check(room.ModelStreamingMode == Enum.ModelStreamingMode.Atomic, "generated room is still non-atomic")
    check(room:FindFirstChild("Roof") and room:FindFirstChild("Floor"), "atomic room lost surfaces")
end
check(template.ModelStreamingMode == Enum.ModelStreamingMode.Default, "source kit was changed")
check(maze.ModelStreamingMode == Enum.ModelStreamingMode.Default, "whole maze made atomic")
check(workspace:GetAttribute("Level1BlenderRoomCount") == 4, "count marker changed")
print("PASS renderer: " .. checks .. " per-room scope/generation/original-preservation checks")
'''


def program(kind, source):
    if kind == "shop":
        fragment = source[source.index("local BOB_HEIGHT ="):source.index("script.Destroying:Connect(function() stopDemo(); restoreMotion() end)")]
        return PRELUDE + SHOP_TEST.replace("SOURCE", fragment)
    if kind == "dj":
        start = source.index("local trackJson") if "local trackJson" in source else source.index("local function tracks()")
        cache = source[start:source.index("-- the sound")]
        lighting = source[source.index("do\n\tlocal RunService = game:GetService(\"RunService\")"):source.index("-- the DJ's hands")]
        return PRELUDE + DJ_TEST.replace("CACHE", cache).replace("LIGHTING", lighting)
    fragment = source[source.index("\tfunction state:Rooms("):source.index("\t-- Replace a complete fixed casing")]
    helper = source[source.index("function Renderer.OpenMask("):source.index("function Renderer.Begin(maze)")]
    return PRELUDE + RENDERER_TEST.replace("HELPERS", helper).replace("SOURCE", fragment)


def main():
    parser = argparse.ArgumentParser()
    parser.add_argument("--candidate", action="store_true")
    parser.add_argument("--baseline", action="store_true")
    parser.add_argument("--luau", default=os.environ.get("LUAU_BIN") or shutil.which("luau")
                        or (str(LOCAL_LUAU) if LOCAL_LUAU.exists() else None))
    parser.add_argument("--compiler", default=os.environ.get("LUAU_COMPILE_BIN") or shutil.which("luau-compile"))
    args = parser.parse_args()
    if not args.luau:
        raise SystemExit("Set LUAU_BIN or supply --luau; no tests executed.")
    if not args.compiler:
        compiler = Path(args.luau).with_name("luau-compile.exe" if Path(args.luau).suffix == ".exe" else "luau-compile")
        args.compiler = str(compiler) if compiler.exists() else None
    if not args.compiler:
        raise SystemExit("Set LUAU_COMPILE_BIN or supply --compiler; no tests executed.")
    rows = None
    if args.candidate or args.baseline:
        manifest = HERE / "visual-candidates/manifest.json"
        if not manifest.exists():
            raise SystemExit("Local candidate manifest is required only for --candidate or --baseline.")
        rows = json.loads(manifest.read_text(encoding="utf-8"))
    paths = tuple(ROOT / row["candidateFile"] for row in rows) if args.candidate else MIRRORS
    results = []
    with tempfile.TemporaryDirectory() as temp:
        for index, (kind, path) in enumerate(zip(("shop", "dj", "renderer"), paths)):
            source = path.read_text(encoding="utf-8")
            compiled = subprocess.run([args.compiler, str(path)], capture_output=True, text=True, timeout=30)
            assert compiled.returncode == 0, compiled.stderr
            test = Path(temp) / f"{kind}.luau"
            test.write_text(program(kind, source), encoding="utf-8")
            result = subprocess.run([args.luau, str(test)], capture_output=True, text=True, timeout=30)
            assert result.returncode == 0, result.stdout + result.stderr
            print(result.stdout.strip())
            row = {"name": kind, "sourceFile": path.relative_to(ROOT).as_posix(),
                   "compiled": True, "checks": result.stdout.strip()}
            if args.baseline:
                baseline_path = ROOT / rows[index]["baselineFile"]
                if not baseline_path.exists():
                    raise SystemExit(f"Local --baseline capture is unavailable: {baseline_path}")
                test.write_text(program(kind, baseline_path.read_text(encoding="utf-8")), encoding="utf-8")
                negative = subprocess.run([args.luau, str(test)], capture_output=True, text=True, timeout=30)
                assert negative.returncode != 0, f"{kind} baseline did not reproduce its regression"
                row.update(baselineRejected=True, baselineFailure=negative.stderr.splitlines()[0])
            results.append(row)
    (HERE / "visual-offline-receipt.json").write_text(json.dumps({"scope": "synthetic contracts only", "results": results}, indent=2) + "\n", encoding="utf-8")


if __name__ == "__main__":
    main()
