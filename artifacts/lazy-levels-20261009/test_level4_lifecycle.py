"""Execute production Level 4 lifecycle code; --candidate checks local candidate files.

No Studio/gameplay/performance claim. The default uses the promoted canonical mirrors,
including the embedded client script under the inactive cinema in ServerStorage.
"""
from pathlib import Path
import argparse
import os
import shutil
import subprocess
import tempfile

ROOT = Path(__file__).resolve().parents[2]
HERE = Path(__file__).parent
H = (HERE / 'level4_lifecycle_harness.luau').read_text(encoding='utf-8')
DEFAULT_LUAU = ROOT / 'artifacts/hazmat-20260924/luau-0.737/luau.exe'


def between(source, start, end):
    return source[source.index(start):source.index(end, source.index(start))]


GENERATOR_TEST = r'''
local world = object("Model", "Level 4 Cinema Blender", ServerStorage)
local collision = object("Model", "Collision", world)
collision.ModelStreamingMode = Enum.ModelStreamingMode.Persistent
local doorsFolder = object("Folder", "Doors", world)
local door = object("Model", "Entry Door", doorsFolder)
local hingePart = object("Part", "Hinge", door)
local hinge = object("HingeConstraint", "Servo", hingePart)
hinge.Enabled, hinge.TargetAngle = true, 0
local leaf = object("Part", "Leaf", door)
local neutral = {Identity = "authored CFrame"}
leaf.CFrame, leaf.Anchored, leaf.CanCollide = neutral, false, true
local originalWorld, originalDoor = world, door
local participant, lobby = newPlayer("participant"), newPlayer("lobby")
local preview6, preview2 = newPlayer("preview6"), newPlayer("preview2")
participant:SetAttribute("InRound", true)
preview6:SetAttribute("InRound", true); preview6:SetAttribute("Level6PlaygroundPreview", true)
preview2:SetAttribute("InRound", true); preview2:SetAttribute("Level2NewMapPreview", true)
local WorldStorage = {}
local stops, parkedChecks, starts, failure, stopFailure = {}, 0, 0, false, false
function WorldStorage.Get(level) check(level == 4, "wrong level Get"); return world end
function WorldStorage.Deactivate(level)
    check(level == 4, "wrong level Deactivate")
    if world.Parent == workspace then
        check(stops.Usher and stops.Objectives and stops.LightDirector, "parked before systems stopped")
        check(workspace:GetAttribute("Level4RoundActive") == false, "parked while clients stayed active")
        check(not next(collision.PersistentPlayers or {}), "parked with persistent members")
        parkedChecks += 1
    end
    world.Parent = ServerStorage
    return world
end
function WorldStorage.Activate(level)
    check(level == 4, "wrong level Activate")
    check(world.Parent == ServerStorage, "activation did not use parked original")
    check(leaf.CFrame == neutral and leaf.Anchored == false and leaf.CanCollide == true,
        "door was not neutral before embedded script restart")
    check(hinge.Enabled and hinge.TargetAngle == 0, "hinge was not restored before restart")
    check(collision.ModelStreamingMode == Enum.ModelStreamingMode.PersistentPerPlayer,
        "lobby clients receive persistent cinema floor")
    check(collision.PersistentPlayers[participant] == true and not collision.PersistentPlayers[lobby],
        "persistent membership was not set before map replication")
    check(not collision.PersistentPlayers[preview6] and not collision.PersistentPlayers[preview2],
        "another live level got the cinema floor")
    world.Parent = workspace
    return world
end
local function system(name)
    return {Stop = function()
        stops[name] = true
        if world.Parent == workspace then check(world:IsDescendantOf(workspace), "Stop lost authored world") end
        if name == "Usher" and stopFailure then error("injected Stop failure") end
    end}
end
local Usher, Objectives, LightDirector = system("Usher"), system("Objectives"), system("LightDirector")
function LightDirector.Start(manifest)
    check(manifest.World.Parent == workspace, "system started before activation")
    stops = {}; starts += 1
    if failure then error("injected system startup failure") end
    return 2
end
Objectives.Start = function() end
Usher.Start = function() return 42 end
local Configuration = {ModelName = world.Name, RuntimeName = "Runtime", StateName = "State", Level = 4}
local Generator, generation, activeManifest, levelOneScriptStates = {}, 0, nil, nil
local function ownedFolder(parent, name)
    return parent:FindFirstChild(name) or object("Folder", name, parent)
end
local function resetState(folder) folder:SetAttribute("Level4_Phase", "Idle") end
local function ensureRemotes() return {}, {}, {} end
local function isolateLevelOneRuntime() levelOneScriptStates = {enabled = true} end
local function restoreLevelOneRuntime() levelOneScriptStates = nil end
local function destroyCompatibilityObjects()
    for _, item in ipairs(workspace:GetChildren()) do if item.Name == "Compat" then item:Destroy() end end
end
local USHER_VISUAL_NAME = "Level 4 Usher Visual"
local function collectManifest(model)
    check(model == originalWorld and model.Parent == workspace, "manifest does not use mounted original")
    return {World = model}
end
local function buildCompatibility() object("Part", "Compat", workspace) end
local function publishUsherVisual() object("Model", USHER_VISUAL_NAME, ReplicatedStorage) end
SOURCE
local baseConnections = connectionCount()
check(Generator.Build() == originalWorld and originalDoor.Parent == doorsFolder, "Build cloned authored objects")
local mountedConnections = connectionCount()
check(mountedConnections > baseConnections, "no live membership watchers")
local addCalls = collision.AddCalls
participant:SetAttribute("Escaped", true)
participant:SetAttribute("Spectating", true)
check(collision.PersistentPlayers[participant] and collision.AddCalls == addCalls, "escaped spectator lost floor")
lobby:SetAttribute("InRound", true)
check(collision.PersistentPlayers[lobby], "later entrant did not receive persistent floor")
lobby:SetAttribute("Level6PlaygroundPreview", true)
check(not collision.PersistentPlayers[lobby], "preview transition retained cinema floor")
lobby:SetAttribute("Level6PlaygroundPreview", nil)
check(collision.PersistentPlayers[lobby], "return from excluded preview did not restore membership")
lobby:SetAttribute("InRound", false)
check(not collision.PersistentPlayers[lobby], "local return retained persistent floor")
local late = newPlayer("late")
late:SetAttribute("InRound", true)
check(collision.PersistentPlayers[late], "PlayerAdded/late InRound was not observed")
leavePlayer(late)
check(not collision.PersistentPlayers[late], "departed member retained floor")
leaf.CFrame, leaf.Anchored, leaf.CanCollide = {Identity = "open"}, true, false
leaf.AssemblyLinearVelocity, leaf.AssemblyAngularVelocity = {Moving = true}, {Moving = true}
hinge.Enabled, hinge.TargetAngle = false, 95
Generator.Cleanup()
check(world.Parent == ServerStorage and not world:FindFirstChild("Runtime"), "cleanup did not park/clear runtime")
check(leaf.CFrame == neutral and not leaf.Anchored and leaf.CanCollide, "cleanup did not reset door properties")
check(leaf.AssemblyLinearVelocity == Vector3.zero and leaf.AssemblyAngularVelocity == Vector3.zero,
    "cleanup left door physics velocity")
check(hinge.Enabled and hinge.TargetAngle == 0, "cleanup left stale hinge target")
check(not ReplicatedStorage:FindFirstChild(USHER_VISUAL_NAME) and not workspace:FindFirstChild("Compat"),
    "cleanup leaked round objects")
check(connectionCount() == baseConnections, "cleanup leaked membership connections")
leaf.CFrame = {Identity = "parked late drift"}
hinge.TargetAngle = 95
check(Generator.Build() == originalWorld and starts == 2, "second entry lost authored identity")
Generator.Cleanup()
failure = true
local ok = pcall(Generator.Build)
check(not ok and world.Parent == ServerStorage, "failed Build left map mounted")
check(connectionCount() == baseConnections and not next(collision.PersistentPlayers), "failed Build leaked members")
check(workspace:GetAttribute("LoadStage") == "WORLD_ERROR", "failed Build lost error readiness")
check(parkedChecks == 3, "not all mounted lifetimes parked")
failure = false
Generator.Build()
stopFailure = true
local cleaned, problem = pcall(Generator.Cleanup)
check(not cleaned and string.find(tostring(problem), "Usher"), "Stop failure was not reported")
check(stops.Objectives and stops.LightDirector, "one Stop failure prevented other systems restoring")
check(world.Parent == workspace and collision.PersistentPlayers[participant], "Stop failure parked map or removed floor")
check(workspace:GetAttribute("LoadStage") == "WORLD_ERROR", "Stop failure did not fail readiness")
stopFailure = false
Generator.Cleanup()
check(world.Parent == ServerStorage and connectionCount() == baseConnections, "cleanup retry leaked ownership")
print("PASS Level4 generator: " .. checks .. " ownership/door/persistence/lifecycle checks")
'''

FLICKER_TEST = r'''
local player = newPlayer("local")
Players.LocalPlayer = player
local model = object("Model", "Cinema", workspace)
local unit = object("Part", "Lens", model)
unit.Material, unit.Transparency, unit.Color = Enum.Material.Neon, 0, colour()
unit:SetAttribute("OccasionalFlicker", true)
local light = object("PointLight", "Light", unit); light.Brightness = 5
local script = object("Script", "Flicker", model)
local initialConnections = connectionCount()
SOURCE
check(jobCount() == 1, "initial unit did not start exactly once")
advance(0)
check(light.Brightness == 0 and tweenCount() > 0, "test did not reach an active fade")
model.Parent = ServerStorage
check(jobCount() == 0 and tweenCount() == 0 and light.Brightness == 5, "unmount did not cancel/restore blink")
local late = object("Part", "Late Lens", model)
late.Material, late.Transparency, late.Color = Enum.Material.Neon, 0, colour()
late:SetAttribute("OccasionalFlicker", true)
check(jobCount() == 0, "parked descendant spawned a flicker worker")
model.Parent = workspace
check(jobCount() == 2, "same-instance reentry did not rescan units")
model.AncestryChanged:Fire(model, workspace)
check(jobCount() == 2, "duplicate ancestry notification duplicated unit workers")
advance(0)
workspace:SetAttribute("Level4RoundActive", true)
check(light.Brightness == 5 and tweenCount() == 0, "round takeover did not restore/cancel blink")
model.Parent = nil
check(jobCount() == 0 and tweenCount() == 0, "replica removal retained unit jobs/tweens")
script:Destroy()
check(connectionCount() == initialConnections, "destroyed flicker retained signal connections")
print("PASS Level4 flicker: " .. checks .. " unload/reentry/takeover checks")
'''

CLIENT_TEST = r'''
local MODEL_NAME = "Level 4 Cinema Blender"
local function cinema() return workspace:FindFirstChild(MODEL_NAME) end
local function reduceFlashing() return false end
local zoneLights, zoneNeon, tracked, stutterUntil = {}, {}, {}, {}
MODEL_SOURCE
SCREEN_SOURCE
local active, roundConnections = true, {}
ARRIVAL_SOURCE
check(watchedModel == nil and not next(tracked), "absent map retained model state")
local model = object("Model", MODEL_NAME)
local lens = object("Part", "Lens", model)
lens:SetAttribute("L4Zone", 1); lens:SetAttribute("L4OnColor", colour())
local light = object("PointLight", "Light", lens)
light.Brightness = 4; light:SetAttribute("L4Brightness", 4)
model.Parent = workspace
check(watchedModel == model and tracked[light] == 1 and tracked[lens] == 1, "late map was not bound")
local boundConnections = connectionCount()
model.AncestryChanged:Fire(model, workspace)
watchModel()
check(connectionCount() == boundConnections, "same map bound duplicate connections")
local screen = object("Part", "Late Screen")
screen:AddTag("L4Screen"); screen:SetAttribute("L4FilmRunning", true)
screen.Parent = model
check(filmRunning[screen] and #screenGuis == 2 and jobCount() == 1, "late streamed running screen was not bound")
local oldToken = filmRunning[screen]
screen.Parent = nil
check(not filmRunning[screen] and not screenConnections[screen] and #screenGuis == 0,
    "streamed-out screen retained GUI/connection/cache")
screen.Parent = model
check(filmRunning[screen] ~= oldToken and #screenGuis == 2, "screen reentry did not create a fresh film generation")
advance(0.08)
check(jobCount() == 1, "stale film generation survived same-instance screen reentry")
light.Brightness = 0
model.Parent = nil
check(watchedModel == nil and not next(tracked) and not next(zoneLights) and not next(zoneNeon),
    "root unmount retained model/light caches")
check(not next(screenConnections) and not next(filmRunning) and #screenGuis == 0 and light.Brightness == 4,
    "root unmount retained screen caches or unrestored light")
advance(0.08)
check(jobCount() == 0, "root unmount retained film worker")
model.Parent = workspace
check(watchedModel == model and #screenGuis == 2 and filmRunning[screen], "map reentry did not bind existing screen")
for _, connection in ipairs(roundConnections) do connection:Disconnect() end
active = false
releaseModel()
advance(0.08)
check(connectionCount() == 0 and jobCount() == 0, "round stop retained model/screen/arrival ownership")
print("PASS Level4 client: " .. checks .. " delayed streaming/unload/generation checks")
'''


def programs(generator, flicker, client):
    helpers = between(generator, 'local doorStateWorld, doorStates', '\nlocal function ownedFolder')
    cleanup_build = between(generator, 'function Generator.Cleanup()', '\nreturn Generator')
    model = between(client, 'local function track(d)', '\nlocal function zoneOn(id)')
    screens = between(client, 'local screenGuis = {}', '\n-- owner 2026-10-04:')
    arrival = between(client, '\ttable.insert(roundConnections, workspace.ChildAdded', '\tbuildUsher()')
    return (
        H + GENERATOR_TEST.replace('SOURCE', helpers + '\n' + cleanup_build),
        H + FLICKER_TEST.replace('SOURCE', flicker),
        H + CLIENT_TEST.replace('MODEL_SOURCE', model).replace('SCREEN_SOURCE', screens).replace('ARRIVAL_SOURCE', arrival),
    )


def run(luau, program, label, expect_ok=True):
    with tempfile.TemporaryDirectory(prefix='level4-lifecycle-') as temp:
        path = Path(temp) / 'test.luau'
        path.write_text(program, encoding='utf-8')
        result = subprocess.run([str(luau), str(path)], text=True, capture_output=True, timeout=15)
    if expect_ok:
        assert result.returncode == 0, label + '\n' + result.stdout + result.stderr
        print(result.stdout.strip())
    else:
        assert result.returncode != 0, f'{label}: mutation was not detected'
        print('PASS mutation:', label)


def main():
    parser = argparse.ArgumentParser()
    parser.add_argument('--luau', type=Path)
    parser.add_argument('--candidate', action='store_true')
    args = parser.parse_args()
    discovered = os.environ.get('LUAU_BIN') or shutil.which('luau')
    luau = args.luau or (Path(discovered) if discovered else DEFAULT_LUAU)
    if not luau.is_file():
        parser.error('Supply --luau or LUAU_BIN with an available Luau CLI executable')
    if args.candidate:
        paths = tuple(HERE / 'candidates' / path for path in (
            'ServerScriptService__Level4RoundGenerator.luau',
            'Workspace__Level 4 Cinema Blender__OccasionalFixtureFlicker.luau',
            'StarterPlayer__StarterPlayerScripts__Level 4 Round Client.luau'))
    else:
        paths = tuple(ROOT / path for path in (
            'ServerScriptService/Level4RoundGenerator.ModuleScript.lua',
            'ServerStorage/Level 4 Cinema Blender/OccasionalFixtureFlicker.Script.lua',
            'StarterPlayer/StarterPlayerScripts/Level 4 Round Client.LocalScript.lua'))
    sources = tuple(path.read_text(encoding='utf-8') for path in paths)
    labels = ('generator', 'flicker', 'client')
    for label, program in zip(labels, programs(*sources)):
        run(luau, program, label)
    mutations = (
        (0, '\tWorldStorage.Deactivate(4)\n\tresetDoors(world)', '\tresetDoors(world)', 'missing park'),
        (0, '\tresetDoors(world)', '', 'missing door reset across reentry'),
        (0, '\t\t\tstate.Leaf.CanCollide = state.CanCollide', '', 'nonblocking door collider leak'),
        (0, 'and player:GetAttribute("Level6PlaygroundPreview") ~= true', 'and true', 'other level persistent floor'),
        (0, '\tstopPersistence()\n\tWorldStorage.Deactivate(4)', '\tWorldStorage.Deactivate(4)', 'membership/connection leak'),
        (0, '\tif #stopErrors > 0 then', '\tif false then', 'parking after failed system Stop'),
        (1, '\t\tstopAll()\n\tend\nend\nlocal added', '\t\t-- leak\n\tend\nend\nlocal added', 'unmounted blink workers'),
        (2, 'if active and child.Name == MODEL_NAME then watchModel() end', '', 'late map arrival race'),
        (2, '\t\tforgetScreen(d)', '', 'streamed screen strong cache leak'),
        (2, 'filmRunning[part] == token and part:IsDescendantOf(workspace)', 'filmRunning[part] and part:IsDescendantOf(workspace)', 'stale film ABA generation'),
    )
    for index, old, new, label in mutations:
        assert old in sources[index], f'missing mutation anchor {label}'
        mutated = list(sources)
        mutated[index] = mutated[index].replace(old, new)
        run(luau, programs(*mutated)[index], label, expect_ok=False)
    print(f'PASS {len(mutations)}/{len(mutations)} lifecycle mutations detected')


if __name__ == '__main__':
    main()
