"""Exercise the real Level 2 adapter and Pool Slide release-acceptance guards.

World generation, characters and entity creation are engine boundaries here.
The complete Adapter.Build and Adapter.Cleanup functions, shipping configuration,
and the controller's two preverification guards are read from production on every run. This does not
certify the rig's geometry, animation envelope or a published Roblox session.
Set LUAU_BIN or put luau on PATH.
"""

import os
from pathlib import Path
import shutil
import subprocess
import tempfile


ROOT = Path(__file__).resolve().parents[2]
SYSTEMS = ROOT / "ServerScriptService/Level 2 Systems"


def section(source, start, stop):
    begin = source.index(start)
    return source[begin:source.index(stop, begin)]


HARNESS = r'''
local checks = 0
local function expect(actual, wanted, message)
    checks += 1
    assert(actual == wanted, message .. ": expected " .. tostring(wanted)
        .. ", got " .. tostring(actual))
end
local function contains(value, fragment, message)
    checks += 1
    assert(tostring(value):find(fragment, 1, true), message .. ": " .. tostring(value))
end
local function node()
    return {Attributes = {}, SetAttribute = function(self, key, value)
        self.Attributes[key] = value
    end}
end
local Vector3 = {}
function Vector3.new(x, y, z)
    local vector = {X = x, Y = y, Z = z}
    vector.Unit = vector
    return vector
end
local attributes, isStudio = {}, false
local model = {GetAttribute = function(_, name) return attributes[name] end}
local RunService = {IsStudio = function() return isStudio end}
local slideConfiguration
local function verifyAcceptance()
    local Configuration = slideConfiguration
    __ACCEPTANCE_GUARDS__
    return true
end
local shippingConfiguration = (function()
    __SHIPPING_CONFIGURATION__
end)()
local function makeWorld(config, options)
    options = options or {}
    local trace = {Cleanup = 0, FoamStarts = 0, SlideStarts = 0, SlideStops = 0, Warnings = {}}
    local state, workspace = node(), node()
    state.Attributes.Level2_PoolSlideLastError = "stale previous generation"
    local Adapter = {Cleanup = function()
        trace.Cleanup += 1
        trace.PartialSession = false
    end}
    local function warn(message) table.insert(trace.Warnings, tostring(message)) end
    local generation = 0
    local Configuration = {}
    local PoolSlideConfiguration = config
    local PoolFoamConfiguration = {Enabled = true}
    local Master = {ApplyInto = function() end}
    local activeManifest
    local function getState() return state end
    local function pinnedSeedOverride() return nil end
    local function randomRoundSeed() return 123 end
    local function isolateLevelOneRuntime() trace.Isolated = true end
    local function clearOwnedTerrain() end
    local function storeLobby() trace.LobbyStored = true end
    local LayoutGenerator = {Generate = function()
        return {Seed = 123, Attempt = 1, Halls = {{}}}
    end}
    local generatedWorld = {}
    local WorldBuilder = {Build = function()
        if options.WorldError then error("world construction failed") end
        return {World = generatedWorld, Arrival = {ElevatorSpawn = {
            Position = Vector3.new(0, 0, 0), CFrame = {LookVector = Vector3.new(0, 0, 1)},
        }}}
    end}
    local game = {GetService = function()
        return {GetPlayers = function() return {} end}
    end}
    local ObjectiveController = {Start = function()
        if options.ObjectiveError then error("objectives failed") end
        trace.ObjectivesStarted = true
    end}
    local PoolFoamController = {Start = function()
        trace.FoamStarts += 1
        if options.FoamError then return nil, "required Pool Foam failed" end
        return {}
    end}
    local PoolSlideController = {Start = function()
        trace.SlideStarts += 1
        if options.Partial then trace.PartialSession = true end
        if options.StartMode == "throw" then error("slide startup threw") end
        if options.StartMode == "nil" then return nil, "slide template unavailable" end
        slideConfiguration = config
        local ok, reason = pcall(verifyAcceptance)
        if not ok then return nil, reason end
        local phase = options.Working and "ACTIVE" or "DORMANT"
        state:SetAttribute("Level2_PoolSlideState", phase)
        state:SetAttribute("Level2_PoolSlidePhase", phase)
        return {Spawned = options.Working == true}
    end, Stop = function()
        trace.SlideStops += 1
        if options.StopError then error("slide cleanup threw") end
        trace.PartialSession = false
    end}
    __ADAPTER_BUILD__
    return Adapter, trace, state, workspace, generatedWorld
end

-- Enabled is a rollout choice. The same suite must remain meaningful when
-- native rig/fit acceptance later authorizes switching the encounter on.
expect(type(shippingConfiguration.Enabled), "boolean", "shipping enablement is explicit")
expect(shippingConfiguration.StudioValidationMode, false, "shipping config cannot bypass acceptance in Studio")

local function expectReady(adapter, trace, state, workspace, world, message)
    local ok, result = pcall(adapter.Build)
    expect(ok, true, message .. " builds")
    expect(result, world, message .. " returns generated Level 2")
    expect(trace.Cleanup, 1, message .. " only performs initial world cleanup")
    expect(trace.FoamStarts, 1, message .. " preserves Pool Foam")
    expect(trace.ObjectivesStarted, true, message .. " preserves objectives")
    expect(workspace.Attributes.SelectedLevel, 2, message .. " selects Level 2")
    expect(workspace.Attributes.LoadStage, "READY", message .. " reaches entry readiness")
    expect(workspace.Attributes.WorldGenerated, true, message .. " hands world to GameManager")
    expect(state.Attributes.Level2_Error, nil, message .. " is not a world failure")
end

local function expectUnavailable(trace, state, message)
    expect(trace.SlideStops, 1, message .. " cleans encounter once")
    expect(trace.PartialSession, false, message .. " leaves no partial session")
    expect(state.Attributes.Level2_PoolSlideEnabled, false, message .. " reports effective disabled")
    expect(state.Attributes.Level2_PoolSlideState, "UNAVAILABLE", message .. " reports unavailable state")
    expect(state.Attributes.Level2_PoolSlidePhase, "UNAVAILABLE", message .. " reports unavailable phase")
    contains(state.Attributes.Level2_PoolSlideLastError, "Pool Slide encounter unavailable", message .. " keeps reason")
    expect(#trace.Warnings, 1, message .. " emits one warning")
    expect(trace.Warnings[1], state.Attributes.Level2_PoolSlideLastError, message .. " warning matches diagnostics")
end

-- Disabled remains an explicitly covered rollout branch even after shipping
-- enablement changes. Broken assets must never be touched in this branch.
for _, studio in ipairs({false, true}) do
    isStudio = studio
    attributes = {Level2_PoolSlideRigVerified = false, Level2_PoolSlideCorridorFitVerified = false}
    local adapter, trace, state, workspace, world = makeWorld({Enabled = false, StudioValidationMode = false},
        {StartMode = "throw", StopError = true})
    expectReady(adapter, trace, state, workspace, world, "disabled encounter")
    expect(trace.SlideStarts, 0, "disabled draft never reaches acceptance or startup")
    expect(trace.SlideStops, 0, "disabled branch needs no encounter fallback cleanup")
    expect(state.Attributes.Level2_PoolSlideEnabled, false, "disabled rollout is observable")
    expect(state.Attributes.Level2_PoolSlideState, "DISABLED", "disabled draft state is explicit")
    expect(state.Attributes.Level2_PoolSlidePhase, "DISABLED", "disabled draft phase is explicit")
    expect(state.Attributes.Level2_PoolSlideLastError, nil, "disabled build clears stale error")
    expect(#trace.Warnings, 0, "intentional disable is not an error")

    -- The actual shipping configuration is exercised separately, without
    -- hardcoding that the verified encounter must remain disabled forever.
    local shipping, st, ss, sw, generated = makeWorld(shippingConfiguration)
    expectReady(shipping, st, ss, sw, generated, "shipping with unverified template")
    if shippingConfiguration.Enabled then
        expectUnavailable(st, ss, "shipping rejection")
    else
        expect(st.SlideStarts, 0, "shipping disable avoids unverified template")
        expect(ss.Attributes.Level2_PoolSlideLastError, nil, "shipping disable clears stale reason")
    end
end

-- Missing certification still fails the encounter, including the original
-- accidental published configuration, but cannot tear down the valid world.
for _, studio in ipairs({false, true}) do
    for _, validationMode in ipairs({false, true}) do
        for _, missing in ipairs({"Level2_PoolSlideRigVerified", "Level2_PoolSlideCorridorFitVerified"}) do
            isStudio = studio
            attributes = {Level2_PoolSlideRigVerified = true, Level2_PoolSlideCorridorFitVerified = true}
            attributes[missing] = false
            local config = {Enabled = true, StudioValidationMode = validationMode}
            local adapter, trace, state, workspace, world = makeWorld(config)
            local permitsDraft = studio and validationMode
            expectReady(adapter, trace, state, workspace, world, "certificate guard")
            expect(trace.SlideStarts, 1, "enabled draft reaches actual acceptance guards")
            if not permitsDraft then
                expectUnavailable(trace, state, "certificate rejection")
                contains(state.Attributes.Level2_PoolSlideLastError,
                    missing == "Level2_PoolSlideRigVerified" and "full-cycle validation" or "corridor envelope",
                    "actual missing certificate is reported")
            else
                expect(trace.SlideStops, 0, "explicit Studio draft session is retained")
                expect(state.Attributes.Level2_PoolSlideEnabled, true, "explicit Studio bypass stays enabled")
                expect(state.Attributes.Level2_PoolSlideLastError, nil, "accepted Studio draft clears old error")
            end
        end
    end
end

isStudio = false
attributes = {Level2_PoolSlideRigVerified = true, Level2_PoolSlideCorridorFitVerified = true}
local enabled = {Enabled = true, StudioValidationMode = false}
for _, working in ipairs({false, true}) do
    local adapter, trace, state, workspace, world = makeWorld(enabled, {Working = working})
    expectReady(adapter, trace, state, workspace, world, "accepted encounter")
    expect(trace.SlideStarts, 1, "accepted encounter starts once")
    expect(trace.SlideStops, 0, "successful session is not stopped")
    expect(state.Attributes.Level2_PoolSlideEnabled, true, "accepted encounter stays enabled")
    expect(state.Attributes.Level2_PoolSlideState, working and "ACTIVE" or "DORMANT", "adapter preserves controller state")
    expect(state.Attributes.Level2_PoolSlideLastError, nil, "successful start clears stale error")
    expect(#trace.Warnings, 0, "successful start emits no fallback warning")
end

for _, mode in ipairs({"nil", "throw"}) do
    for _, partial in ipairs({false, true}) do
        local adapter, trace, state, workspace, world = makeWorld(enabled, {StartMode = mode, Partial = partial})
        expectReady(adapter, trace, state, workspace, world, "failed startup")
        expectUnavailable(trace, state, "failed startup")
        contains(state.Attributes.Level2_PoolSlideLastError,
            mode == "nil" and "template unavailable" or "startup threw", "original startup cause survives")
    end
    local adapter, trace, state, workspace = makeWorld(enabled, {StartMode = mode, Partial = true, StopError = true})
    local ok, result = pcall(adapter.Build)
    expect(ok, false, "failed encounter cleanup is fatal")
    expect(trace.SlideStops, 1, "cleanup was attempted")
    expect(trace.Cleanup, 2, "cleanup failure invokes outer world rollback")
    expect(workspace.Attributes.WorldGenerated, false, "unclean encounter cannot publish world readiness")
    expect(workspace.Attributes.LoadStage, "WORLD_ERROR", "cleanup failure exposes world error")
    expect(state.Attributes.Level2_Phase, "ERROR", "cleanup failure exposes failed phase")
    contains(result, "cleanup failed", "cleanup failure is not hidden")
    contains(state.Attributes.Level2_Error, "slide cleanup threw", "cleanup cause is retained")
end

for _, failure in ipairs({"WorldError", "ObjectiveError", "FoamError"}) do
    local adapter, trace, state, workspace = makeWorld(enabled, {[failure] = true})
    local ok = pcall(adapter.Build)
    expect(ok, false, "required system failure is still fatal")
    expect(trace.SlideStarts, 0, "fallback does not catch unrelated system failures")
    expect(trace.Cleanup, 2, "required system failure rolls back world")
    expect(workspace.Attributes.LoadStage, "WORLD_ERROR", "required failure remains observable")
    expect(workspace.Attributes.WorldGenerated, false, "required failure cannot return ready")
end

-- Exercise the real cleanup separately: the Build harness above isolates its
-- call boundary, so alone it cannot prove a broken Stop still releases the
-- generated world and restores the lobby. No engine object is created here.
local function cleanupWorld(stopFails)
    local trace = {Warnings = {}, SlideStops = 0, FoamStops = 0, ObjectiveStops = 0}
    local function warn(message) table.insert(trace.Warnings, tostring(message)) end
    local state, workspace = node(), node()
    workspace.GetAttribute = function(self, key) return self.Attributes[key] end
    workspace.Attributes.SelectedLevel = 2
    workspace.Attributes.WorldGenerated = true
    workspace.Attributes.EntityPaused = true
    local generated = {Parent = workspace}
    function generated:Destroy() self.Parent = nil; trace.WorldDestroyed = true end
    function workspace:FindFirstChild(name)
        return name == "Level 2 Generated World" and generated.Parent and generated or nil
    end
    local ServerStorage = {FindFirstChild = function() return nil end}
    local levelOneScriptStates = {}
    local STORED_LOBBY_NAME = "Stored Lobby"
    local activeManifest = {World = generated}
    local Adapter = {}
    local function getState() return state end
    local function clearOwnedTerrain(manifest)
        expect(manifest.World, generated, "cleanup releases terrain belonging to actual manifest")
        trace.TerrainCleared = true
    end
    local function destroyCompatibilityObjects() trace.CompatibilityCleared = true end
    local function restoreLobby() trace.LobbyRestored = true end
    local function restoreLevelOneRuntime() trace.LevelOneRestored = true end
    local PoolSlideController = {Stop = function()
        trace.SlideStops += 1
        if stopFails then error("persistent Pool Slide stop failure") end
    end}
    local PoolFoamController = {Stop = function() trace.FoamStops += 1 end}
    local ObjectiveController = {Stop = function() trace.ObjectiveStops += 1 end}
    __ADAPTER_CLEANUP__
    local ok, problem = pcall(Adapter.Cleanup)
    expect(trace.SlideStops, 1, "cleanup attempts slide teardown")
    expect(trace.FoamStops, 1, "slide teardown cannot skip Pool Foam cleanup")
    expect(trace.ObjectiveStops, 1, "slide teardown cannot skip objective cleanup")
    expect(trace.TerrainCleared, true, "slide teardown cannot strand terrain")
    expect(trace.WorldDestroyed, true, "slide teardown cannot strand generated world")
    expect(activeManifest, nil, "cleanup releases manifest ownership")
    expect(trace.CompatibilityCleared, true, "cleanup clears compatibility objects")
    expect(trace.LobbyRestored, true, "slide teardown cannot skip lobby restoration")
    expect(trace.LevelOneRestored, true, "cleanup restores Level 1 runtime")
    expect(workspace.Attributes.WorldGenerated, false, "cleanup clears world-ready flag")
    expect(workspace.Attributes.EntityPaused, false, "cleanup clears pause")
    expect(workspace.Attributes.SelectedLevel, 1, "cleanup returns level ownership")
    expect(state.Attributes.Level2_PoolSlideEnabled, nil, "cleanup clears encounter enable flag")
    if stopFails then
        contains(table.concat(trace.Warnings, "\n") .. (ok and "" or tostring(problem)),
            "persistent Pool Slide stop failure", "persistent stop failure remains observable")
    else
        expect(ok, true, "ordinary cleanup completes")
        expect(#trace.Warnings, 0, "ordinary cleanup has no warning")
    end
end
cleanupWorld(false)
cleanupWorld(true)
print(string.format("Level 2 Pool Slide release: %d checks passed (actual adapter and acceptance guards)", checks))
'''


def main():
    binary = os.environ.get("LUAU_BIN") or shutil.which("luau")
    if not binary:
        raise SystemExit("Set LUAU_BIN or put luau on PATH; no tests executed.")
    adapter = (SYSTEMS / "Level 2 Round Adapter.ModuleScript.lua").read_text(encoding="utf-8")
    controller = (SYSTEMS / "Level 2 Pool Slide Controller.ModuleScript.lua").read_text(encoding="utf-8")
    configuration = (SYSTEMS / "Level 2 Pool Slide Configuration.ModuleScript.lua").read_text(encoding="utf-8")
    guards = section(controller, "local function navigationTuning(model)", "\tlocal bounds, size")
    guards = guards.split("\n", 1)[1]
    source = HARNESS.replace("__ACCEPTANCE_GUARDS__", guards)
    source = source.replace("__SHIPPING_CONFIGURATION__", configuration)
    source = source.replace("__ADAPTER_BUILD__", section(adapter, "function Adapter.Build()", "\nreturn Adapter"))
    source = source.replace("__ADAPTER_CLEANUP__", section(adapter, "function Adapter.Cleanup()", "\nfunction Adapter.Build()"))
    with tempfile.TemporaryDirectory(prefix="level2-pool-slide-release-") as directory:
        path = Path(directory) / "release_test.luau"
        path.write_text(source, encoding="utf-8")
        subprocess.run([binary, str(path)], check=True, timeout=20)


if __name__ == "__main__":
    main()
