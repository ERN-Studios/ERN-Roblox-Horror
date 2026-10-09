"""Execute exact proposed lifecycle code against streamed removal/re-entry fixtures."""
from pathlib import Path
import hashlib
import json
import os
import re
import subprocess

HERE = Path(__file__).resolve().parent


def section(source, start, end):
    assert source.count(start) == source.count(end) == 1
    return source.split(start, 1)[1].split(end, 1)[0]


def main():
    l2 = (HERE / "Level2Sound.proposed.luau").read_bytes().decode("utf-8")
    l6 = (HERE / "Level6Client.proposed.luau").read_bytes().decode("utf-8")
    l2_old = (HERE / "Level2Sound.before.luau").read_bytes().decode("utf-8")
    l6_old = (HERE / "Level6Client.before.luau").read_bytes().decode("utf-8")
    # New Poolrooms pack ownership and every authored cue/scheduler remain exact.
    assert l2.split("local function randomActive()",1)[1] == l2_old.split("local function randomActive()",1)[1]
    assert l2.split("local function classifyAmbientAnchor(instance)",1)[0] == l2_old.split("local function classifyAmbientAnchor(instance)",1)[0]
    assert section(l6, "task.spawn(function()\n\tlocal last = os.clock()", "local rigs =") == section(l6_old, "task.spawn(function()\n\tlocal last = os.clock()", "local rigs =")
    assert l6.split("-- Kill cam (KILL_CHOKE_20261004",1)[1] == l6_old.split("-- Kill cam (KILL_CHOKE_20261004",1)[1]
    assert "local litBefore = {}" in l6 and 'setmetatable(litBefore' not in l6
    anchor = "local function classifyAmbientAnchor(instance)" + section(l2, "local function classifyAmbientAnchor(instance)", "local function randomActive()")
    stop = "local function stopRandomSession()" + section(l2, "local function stopRandomSession()", "local function classifyAmbientAnchor(instance)")
    release = "local function forgetFinaleInstance(item)" + section(l6, "local function forgetFinaleInstance(item)", "task.spawn(function()\n\tlocal last = os.clock()")
    rig = "local function rigOf(child)" + section(l6, "local function rigOf(child)", "-- Kill cam (KILL_CHOKE_20261004")
    preamble = '''local checks = 0
local function check(condition, label)
    assert(condition, label)
    checks += 1
end
local function signal()
    local records = {}
    return {
        Connect = function(_, callback)
            local connection = {Connected = true, Callback = callback}
            function connection:Disconnect() self.Connected = false end
            table.insert(records, connection)
            return connection
        end,
        Fire = function(_, ...)
            for _, connection in ipairs(table.clone(records)) do
                if connection.Connected then connection.Callback(...) end
            end
        end,
        Count = function()
            local count = 0
            for _, connection in ipairs(records) do if connection.Connected then count += 1 end end
            return count
        end,
    }
end
local function instance(class, name, attributes)
    local item = {Name = name or class, Attributes = attributes or {}}
    function item:IsA(wanted)
        return wanted == class or (wanted == "BasePart" and (class == "Part" or class == "MeshPart"))
            or (wanted == "Light" and (class == "PointLight" or class == "SpotLight"))
    end
    function item:GetAttribute(key) return self.Attributes[key] end
    return item
end
local function world(items)
    local item = instance("Model", "world")
    item.Parent = {}
    item.DescendantAdded, item.DescendantRemoving, item.AncestryChanged = signal(), signal(), signal()
    item.Items = items or {}
    function item:GetDescendants() return self.Items end
    return item
end
'''
    anchor_state = '''local ambientAnchors = {Corridor = {}, WetHall = {}, PumpPipe = {}}
local ambientAnchorSeen = {}
local ambientConnections = {}
local randomSessionActive, ambientWorld, nextCommonAt, lastCommonKey, authoredBusyUntil
local COMMON_FIRST_DELAY_MIN, COMMON_FIRST_DELAY_MAX = 1, 2
local rng = {NextNumber = function() return 1.5 end}
local resets, emitterClears, cueClears = 0, 0, 0
local function resetGroanSession() resets += 1 end
local function clearAmbientEmitters() emitterClears += 1 end
local function clearSpatialCueEmitters() cueClears += 1 end
local function disconnectAmbientConnections()
    for _, connection in ipairs(ambientConnections) do connection:Disconnect() end
    ambientConnections = {}
end
'''
    anchor_tests = '''
local a = instance("Part", "Level 2 Corridor Vault Light 1")
local b = instance("Part", "Level 2 Navigation Node 2")
local c = instance("Part", "Level 2 Pump Intake Pipe")
local kids = instance("Part", "Level 2 Navigation Node 3", {Level2_Role="Kids Area"})
local unrelated = instance("Folder", "Level 2 Pump Intake Pipe")
local oldWorld = world({a,b,c,kids,unrelated})
startRandomSession(oldWorld)
check(randomSessionActive and ambientWorld == oldWorld, "session attached")
check(#ambientAnchors.Corridor == 1 and #ambientAnchors.WetHall == 1 and #ambientAnchors.PumpPipe == 1, "classified streamed initial anchors")
check(ambientAnchorSeen[a] == "Corridor" and ambientAnchorSeen[b] == "WetHall" and ambientAnchorSeen[c] == "PumpPipe", "category ownership")
check(ambientAnchorSeen[kids] == nil and ambientAnchorSeen[unrelated] == nil, "classification exclusions retained")
check(#ambientConnections == 3 and oldWorld.DescendantRemoving.Count() == 1, "one bounded removal connection")
oldWorld.DescendantAdded:Fire(a)
check(#ambientAnchors.Corridor == 1, "duplicate add idempotent")
oldWorld.DescendantRemoving:Fire(a)
check(#ambientAnchors.Corridor == 0 and ambientAnchorSeen[a] == nil, "individual removal releases anchor and seen ownership")
check(#ambientAnchors.WetHall == 1 and #ambientAnchors.PumpPipe == 1 and randomSessionActive, "removal preserves other anchors and session")
oldWorld.DescendantRemoving:Fire(a)
oldWorld.DescendantRemoving:Fire(unrelated)
check(#ambientAnchors.Corridor == 0, "duplicate/unowned removal harmless")
oldWorld.DescendantAdded:Fire(a)
check(#ambientAnchors.Corridor == 1, "same replica re-entry recognized")
oldWorld.DescendantRemoving:Fire(b)
local b2 = instance("Part", "Level 2 Navigation Node 2")
oldWorld.DescendantAdded:Fire(b2)
check(#ambientAnchors.WetHall == 1 and ambientAnchors.WetHall[1] == b2 and not ambientAnchorSeen[b], "replacement replica has no retained old reference")
for _ = 1, 400 do
    oldWorld.DescendantRemoving:Fire(a)
    oldWorld.DescendantAdded:Fire(a)
end
check(#ambientAnchors.Corridor == 1 and #ambientConnections == 3, "400 cycles stay bounded")
local secondWorld = world({})
startRandomSession(secondWorld)
check(oldWorld.DescendantAdded.Count() == 0 and oldWorld.DescendantRemoving.Count() == 0 and oldWorld.AncestryChanged.Count() == 0, "world replacement disconnects all old session signals")
check(#ambientAnchors.Corridor == 0 and #ambientAnchors.WetHall == 0 and #ambientAnchors.PumpPipe == 0 and next(ambientAnchorSeen) == nil, "replacement clears all old references")
oldWorld.DescendantAdded:Fire(a)
check(next(ambientAnchorSeen) == nil, "retired world cannot append")
secondWorld.DescendantAdded:Fire(c)
check(ambientAnchors.PumpPipe[1] == c, "new world can append")
secondWorld.Parent = nil
secondWorld.AncestryChanged:Fire(secondWorld, nil)
check(not randomSessionActive and ambientWorld == nil and next(ambientAnchorSeen) == nil, "Improved root stream-out stops session")
check(#ambientConnections == 0 and secondWorld.DescendantRemoving.Count() == 0, "stream-out root disconnects removal watcher")
check(resets == 3 and emitterClears == 3 and cueClears == 3, "all three session cleanup paths retained")
startRandomSession(world({a}))
stopRandomSession()
check(#ambientAnchors.Corridor == 0 and next(ambientAnchorSeen) == nil and #ambientConnections == 0, "explicit round end clears every cache and connection")
'''
    light_state = '''local litBefore = {}
local exitLamp = {bulb = nil, base = 0, dipUntil = 0, nextDip = 0}
local workspace = {DescendantRemoving = signal()}
'''
    light_tests = '''
local lamp = instance("SpotLight")
lamp.Color, lamp.Brightness, lamp.Angle = "red", 100, 14
litBefore[lamp] = {"white", 2, 70}
workspace.DescendantRemoving:Fire(lamp)
check(lamp.Color == "white" and lamp.Brightness == 2 and lamp.Angle == 70, "spot lamp restores pre-finale values")
check(litBefore[lamp] == nil, "removed lamp released")
workspace.DescendantRemoving:Fire(lamp)
check(lamp.Brightness == 2, "repeat removal does not rescale")
local point = instance("PointLight")
point.Color, point.Brightness = "red", 0.1
litBefore[point] = {"yellow", 0.55, 0}
point.Parent = nil
workspace.DescendantRemoving:Fire(point)
check(point.Color == "yellow" and point.Brightness == 0.55, "deferred callback restores nil-parent light")
local neon = instance("Part")
neon.Color = "dark"
litBefore[neon] = {"blue", 0, 0}
workspace.DescendantRemoving:Fire(neon)
check(neon.Color == "blue" and neon.Brightness == nil, "neon restoration only owns color")
local exit = instance("PointLight")
exit.Brightness = 0.35
exitLamp.bulb, exitLamp.base = exit, 1
workspace.DescendantRemoving:Fire(exit)
check(exit.Brightness == 1 and exitLamp.bulb == nil and exitLamp.base == 0, "exit flicker replica restores and releases cache")
check(exitLamp.dipUntil == 0 and exitLamp.nextDip == 0, "removal leaves timing contract unchanged")
local other = instance("SpotLight")
other.Color, other.Brightness, other.Angle = "green", 6, 48
workspace.DescendantRemoving:Fire(other)
check(other.Color == "green" and other.Brightness == 6 and other.Angle == 48, "unowned lights unchanged")
for _ = 1, 400 do
    litBefore[lamp] = {lamp.Color, lamp.Brightness, lamp.Angle}
    lamp.Color, lamp.Brightness, lamp.Angle = "red", lamp.Brightness * 5, 12
    workspace.DescendantRemoving:Fire(lamp)
end
check(lamp.Color == "white" and lamp.Brightness == 2 and lamp.Angle == 70 and next(litBefore) == nil, "400 stream cycles never save already-scaled finale brightness")
local live = instance("SpotLight")
litBefore[live] = {"white", 3, 45}
check(getmetatable(litBefore) == nil and litBefore[live][2] == 3, "live baseline remains strong")
workspace.DescendantRemoving:Fire(live)
local readOnly = setmetatable({IsA = lamp.IsA}, {__newindex = function() error("disposed fixture") end})
litBefore[readOnly] = {"white", 2, 70}
exitLamp.bulb, exitLamp.base = readOnly, 4
workspace.DescendantRemoving:Fire(readOnly)
check(litBefore[readOnly] == nil and exitLamp.bulb == nil and exitLamp.base == 0, "restore error still releases removed references")
check(workspace.DescendantRemoving.Count() == 1, "single lifetime light removal connection")
'''
    rig_state = '''local rigs = setmetatable({}, {__mode = "k"})
local function bodyOf(child, includeHead)
    local body = instance("MeshPart", "Body")
    body.Parent = child
    body.Bones = {instance("Bone", "Hips")}
    if includeHead then table.insert(body.Bones, instance("Bone", "Head")) end
    function body:GetDescendants() return self.Bones end
    child.Body = body
    return body
end
local doll = {}
function doll:FindFirstChild(name) return name == "Body" and self.Body or nil end
'''
    rig_tests = '''
check(rigOf(doll) == nil and rigs[doll] == nil, "no streamed Body stands down")
local body1 = bodyOf(doll, true)
local first = rigOf(doll)
check(first and first.body == body1 and first.bones.Head == body1.Bones[2], "fresh rig owns current mesh bones")
first.t = 4
check(rigOf(doll) == first and first.t == 4, "live rig keeps animation continuity")
doll.Body = nil
body1.Parent = nil
check(rigOf(doll) == nil and rigs[doll] == nil, "partial Body removal releases cached bones")
doll.Body, body1.Parent = body1, doll
local returned = rigOf(doll)
check(returned ~= first and returned.body == body1, "same Body returning after observed stream-out rebuilds")
local body2 = bodyOf(doll, true)
body1.Parent = nil
local replaced = rigOf(doll)
check(replaced ~= returned and replaced.body == body2 and replaced.bones.Head == body2.Bones[2], "Body replacement refreshes visible bone targets")
local partial = bodyOf(doll, false)
check(rigOf(doll) == nil and rigs[doll] == nil, "incomplete returning bone tree waits instead of stale cache")
table.insert(partial.Bones, instance("Bone", "Head"))
local complete = rigOf(doll)
check(complete and complete.body == partial and complete.bones.Head == partial.Bones[2], "late head completes rig retry")
for _ = 1, 400 do
    doll.Body = nil
    check(rigOf(doll) == nil, "cycle stream-out stands down")
    bodyOf(doll, true)
    local current = rigOf(doll)
    check(current and current.body == doll.Body and current.bones.Head == doll.Body.Bones[2], "cycle animates only current visible bones")
end
check(getmetatable(rigs).__mode == "k", "existing rig cache weak ownership retained")
print("STREAMING_LIFECYCLE_CHECKS=" .. checks)
'''
    code = preamble + "\ndo\n" + anchor_state + stop + anchor + anchor_tests + "\nend\ndo\n" + light_state + release + light_tests + "\nend\ndo\n" + rig_state + rig + rig_tests + "\nend\n"
    target = HERE / "lifecycle-contract.luau"
    target.write_bytes(code.encode("utf-8"))
    (HERE / "native-contract-probe.luau").write_bytes(("return function()\n"+code+"\nreturn true\nend\n").encode("utf-8"))
    native = '''return function()
local checks = 0
local function check(condition, label) assert(condition, label); checks += 1 end
local fixtureRoot = Instance.new("Model")
fixtureRoot.Name = "OptimizationStreamingLifecycleFixture"
local owned = {fixtureRoot}
local function make(class, name, parent)
    local item = Instance.new(class)
    item.Name = name or class
    table.insert(owned, item)
    item.Parent = parent or fixtureRoot
    return item
end
local ambientAnchors = {Corridor = {}, WetHall = {}, PumpPipe = {}}
local ambientAnchorSeen, ambientConnections = {}, {}
local randomSessionActive, ambientWorld, nextCommonAt, lastCommonKey, authoredBusyUntil
local COMMON_FIRST_DELAY_MIN, COMMON_FIRST_DELAY_MAX = 1, 2
local rng = Random.new(1234)
local function resetGroanSession() end
local function clearAmbientEmitters() end
local function clearSpatialCueEmitters() end
local function disconnectAmbientConnections()
    for _, connection in ipairs(ambientConnections) do connection:Disconnect() end
    ambientConnections = {}
end
''' + stop + anchor + '''
local litBefore = {}
local exitLamp = {bulb=nil, base=0, dipUntil=0, nextDip=0}
local workspace = {DescendantRemoving = fixtureRoot.DescendantRemoving}
local removalConnection
''' + release.replace("workspace.DescendantRemoving:Connect(forgetFinaleInstance)", "removalConnection = workspace.DescendantRemoving:Connect(forgetFinaleInstance)") + '''
local rigs = setmetatable({}, {__mode="k"})
''' + rig + '''
local ok, result = xpcall(function()
    local w = make("Model", "FixtureWorld")
    local a = make("Part", "Level 2 Corridor Vault Light Fixture", w)
    local b = make("Part", "Level 2 Navigation Node Fixture", w)
    local c = make("Part", "Level 2 Pump Intake Pipe", w)
    startRandomSession(w)
    check(#ambientAnchors.Corridor == 1 and #ambientAnchors.WetHall == 1 and #ambientAnchors.PumpPipe == 1, "native initial classification")
    a.Parent = nil; task.wait()
    check(ambientAnchorSeen[a] == nil and #ambientAnchors.Corridor == 0, "native individual stream-out signal prunes")
    a.Parent = w; task.wait()
    check(ambientAnchors.Corridor[1] == a and #ambientAnchors.Corridor == 1, "native same replica re-entry")
    for _ = 1, 10 do
        a.Parent = nil; task.wait()
        a.Parent = w; task.wait()
    end
    check(#ambientAnchors.Corridor == 1 and #ambientConnections == 3, "native repeated signals bounded")
    local p = make("Part", "FixtureLamp")
    local lamp = make("SpotLight", "FixtureSpot", p)
    lamp.Color, lamp.Brightness, lamp.Angle = Color3.fromRGB(255, 0, 0), 100, 14
    local originalColor = Color3.fromRGB(180, 220, 255)
    litBefore[lamp] = {originalColor, 2, 70}
    p.Parent = nil; task.wait()
    check(lamp.Color == originalColor and lamp.Brightness == 2 and lamp.Angle == 70 and litBefore[lamp] == nil, "native removed subtree restores cached light")
    p.Parent = fixtureRoot; task.wait()
    local exit = make("PointLight", "FixtureExit", p)
    exit.Brightness = 0.35; exitLamp.bulb, exitLamp.base = exit, 1
    exit.Parent = nil; task.wait()
    check(exit.Brightness == 1 and exitLamp.bulb == nil and exitLamp.base == 0, "native exit lamp stream-out restores")
    local doll = make("Model", "FixtureDoll")
    local function makeBody()
        local body = make("MeshPart", "Body", doll)
        local hips = make("Bone", "Hips", body)
        make("Bone", "Head", hips)
        return body
    end
    local firstBody = makeBody()
    local firstRig = rigOf(doll)
    check(firstRig and firstRig.body == firstBody and firstRig.bones.Head:IsA("Bone"), "native rig captures actual bones")
    firstBody.Parent = nil
    check(rigOf(doll) == nil and rigs[doll] == nil, "native body disappearance releases rig")
    local secondBody = makeBody()
    local secondRig = rigOf(doll)
    check(secondRig and secondRig ~= firstRig and secondRig.body == secondBody and secondRig.bones.Head:IsDescendantOf(secondBody), "native new Body refreshes bone owner")
    w.Parent = nil; task.wait()
    check(ambientWorld == nil and #ambientConnections == 0 and next(ambientAnchorSeen) == nil, "native Improved root removal cleanup")
    return {nativeFixtureChecks=checks, realStreamingGameplayPerformancePass=false}
end, debug.traceback)
stopRandomSession()
if removalConnection then removalConnection:Disconnect() end
table.clear(litBefore); table.clear(rigs); exitLamp.bulb, exitLamp.base = nil, 0
for i = #owned, 1, -1 do pcall(function() owned[i]:Destroy() end) end
assert(ok, result)
return result
end
'''
    (HERE / "native-instance-probe.luau").write_bytes(native.encode("utf-8"))
    luau = os.environ["LUAU_BIN"]
    compiler = str(Path(luau).with_name("luau-compile.exe"))
    compiled = []
    for name in ("Level2Sound.proposed.luau", "Level6Client.proposed.luau", "lifecycle-contract.luau", "native-contract-probe.luau", "native-instance-probe.luau"):
        result = subprocess.run([compiler, str(HERE/name)], capture_output=True, text=True)
        assert result.returncode == 0, result.stderr + result.stdout
        compiled.append(name)
    result = subprocess.run([luau, str(target)], capture_output=True, text=True)
    assert result.returncode == 0, result.stderr + result.stdout
    match = re.search(r"STREAMING_LIFECYCLE_CHECKS=(\d+)", result.stdout)
    assert match, result.stdout
    receipt = {"runner": luau, "compiler": compiler, "productionExtractedChecks":int(match[1]),
        "focusedTransitionChecks":int(match[1])-800, "cycleIterationChecks":800,
        "staticPreservationChecks": 5, "compiled": compiled, "nativeProbeExecuted": False,
        "gameplayStreamingPerformancePass": False,
        "proposals": {name:hashlib.sha256((HERE/name).read_bytes()).hexdigest() for name in compiled[:2]}}
    (HERE/"offline-result.json").write_text(json.dumps(receipt, indent=2)+"\n", encoding="utf-8")
    print(result.stdout.strip())
    print(json.dumps(receipt, indent=2))


if __name__ == "__main__":
    main()
