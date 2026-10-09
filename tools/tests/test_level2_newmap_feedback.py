"""Execute the real code of the Level 2 new-map feedback patch (owner, 2026-10-07) in Luau with fake services.

Each program below is assembled from sections of the actual scripts (never copies):
- Level2BlenderPreviewButton: the client grade (take/apply/release, model-attribute knobs, the Changed guard, the
  inherited-effect suppression, the Terrain water look), the lamp flicker (only inside the map, ReduceFlashing fades,
  streaming stop) and the third-person camera clamp.
- Level2BlenderPreviewAccess: the exit slide build from marker EXIT_SLIDE (the World Builder's own tub and tube, with
  the live exit flume's arguments) and hookNewMap's KillZone hazard collection and zone loop.
- RoundUI restore(): Level2NewMapLightingOwned keeps the pre-R4 lobby values pending.
- GameManager onCharacter, DevCheats applyPerspective, HazmatSkinVisuals refresh/addPlayer, HazmatSkinDriver
  reconcile: the Level2NewMapPreview flag gives the round camera, skips the lobby scatter, and shows the skin only on
  the server-marked gameplay body, including its loading brief.
- Level 2 World Builder: the additive MakeEntryTub/MakeTubeFromPoints export.
Engine rendering, physics, streaming and Studio are NOT covered: those need the Play QA.
"""
from pathlib import Path
import os
import shutil
import subprocess
import tempfile

ROOT = Path(__file__).resolve().parents[2]


def read(path):
    return (ROOT / path).read_text(encoding="utf-8").replace("\r\n", "\n")


def section(source, start, stop):
    begin = source.index(start)
    return source[begin:source.index(stop, begin)]


BUTTON = read("StarterPlayer/StarterPlayerScripts/Level2BlenderPreviewButton.LocalScript.lua")
ACCESS = read("ServerScriptService/Level2BlenderPreviewAccess.Script.lua")
ROUNDUI = read("StarterPlayer/StarterPlayerScripts/RoundUI.LocalScript.lua")
MANAGER = read("ServerScriptService/GameManager.Script.lua")
DEVCHEATS = read("StarterPlayer/StarterPlayerScripts/DevCheats.LocalScript.lua")
VISUALS = read("ServerScriptService/HazmatSkinVisuals.Script.lua")
DRIVER = read("StarterPlayer/StarterPlayerScripts/HazmatSkinDriver.LocalScript.lua")
BUILDER = read("ServerScriptService/Level 2 Systems/Level 2 World Builder.ModuleScript.lua")

# ── shared fakes: signals, property objects that fire Changed, Color3/Vector3/CFrame, a coroutine scheduler ──
FAKES = r'''
local checks = 0
local function check(value, message) checks += 1; assert(value, message) end
local function signal()
    local s = {list = {}}
    function s:Connect(fn)
        local c = {on = true}
        function c:Disconnect() c.on = false end
        table.insert(s.list, {c = c, fn = fn})
        return c
    end
    function s:Once(fn) local c; c = s:Connect(function(...) c:Disconnect(); fn(...) end); return c end
    function s:Fire(...) for _, e in ipairs(table.clone(s.list)) do if e.c.on then e.fn(...) end end end
    function s:Wait() return nil end
    return s
end
local colors = {}
local Color3 = {}
function Color3.fromRGB(r, g, b)
    local key = r .. "," .. g .. "," .. b
    colors[key] = colors[key] or {kind = "Color3", key = key, R = r / 255, G = g / 255, B = b / 255}
    return colors[key]
end
function Color3.new(r, g, b) return Color3.fromRGB(math.floor(r * 255 + .5), math.floor(g * 255 + .5), math.floor(b * 255 + .5)) end
local vmeta = {}
local function V(x, y, z) return setmetatable({kind = "Vector3", X = x, Y = y, Z = z}, vmeta) end
vmeta.__index = function(v, k)
    if k == "Magnitude" then return math.sqrt(v.X * v.X + v.Y * v.Y + v.Z * v.Z) end
    if k == "Unit" then local m = math.sqrt(v.X * v.X + v.Y * v.Y + v.Z * v.Z); return V(v.X / m, v.Y / m, v.Z / m) end
end
vmeta.__add = function(a, b) return V(a.X + b.X, a.Y + b.Y, a.Z + b.Z) end
vmeta.__sub = function(a, b) return V(a.X - b.X, a.Y - b.Y, a.Z - b.Z) end
vmeta.__mul = function(a, b)
    if type(a) == "number" then a, b = b, a end
    if type(b) == "number" then return V(a.X * b, a.Y * b, a.Z * b) end
    return V(a.X * b.X, a.Y * b.Y, a.Z * b.Z)
end
vmeta.__div = function(a, b) return V(a.X / b, a.Y / b, a.Z / b) end
vmeta.__eq = function(a, b) return a.X == b.X and a.Y == b.Y and a.Z == b.Z end
local function near(a, b, eps) return (a - b).Magnitude <= (eps or 1e-6) end
local Vector3 = {new = V, zero = V(0, 0, 0), xAxis = V(1, 0, 0), yAxis = V(0, 1, 0), zAxis = V(0, 0, 1)}
local cmeta = {}
local function CF(p) return setmetatable({kind = "CFrame", Position = p}, cmeta) end
cmeta.__index = {PointToObjectSpace = function(cf, p) return p - cf.Position end}
cmeta.__add = function(cf, v) return CF(cf.Position + v) end
cmeta.__sub = function(cf, v) return CF(cf.Position - v) end
local CFrame = {new = function(a, b, c) return CF(if type(a) == "number" then V(a, b, c) else a) end}
local function typeof(v) return type(v) == "table" and (v.kind or (v.ClassName and "Instance")) or type(v) end

local ISA = {Part = {BasePart = true}, PointLight = {Light = true}, SpotLight = {Light = true}}
local methods = {}
function methods:IsA(c) return self.ClassName == c or (ISA[self.ClassName] or {})[c] == true end
function methods:GetChildren() return table.clone(self.kids) end
function methods:GetDescendants()
    local list = {}
    local function walk(o) for _, c in ipairs(o.kids) do table.insert(list, c); walk(c) end end
    walk(self)
    return list
end
function methods:FindFirstChild(name) for _, c in ipairs(self.kids) do if c.Name == name then return c end end return nil end
function methods:FindFirstChildOfClass(class) for _, c in ipairs(self.kids) do if c.ClassName == class then return c end end return nil end
function methods:GetAttribute(key) return self.attrs[key] end
function methods:SetAttribute(key, value) self.attrs[key] = value end
function methods:IsDescendantOf(target)
    local o = self.Parent
    while o do if o == target then return true end; o = o.Parent end
    return false
end
function methods:Destroy() self.Parent = nil; self.destroyed = true end
local function object(class, props)
    local p = {}
    local o = setmetatable({}, {
        __index = function(_, k) local v = p[k]; if v ~= nil then return v end; return methods[k] end,
        __newindex = function(t, k, v)
            if p[k] == v then return end
            if k == "Parent" then
                local old = p.Parent
                if old then for i, c in ipairs(old.kids) do if c == t then table.remove(old.kids, i); break end end end
                if v then table.insert(v.kids, t) end
            end
            p[k] = v
            p.Changed:Fire(k)
        end})
    p.ClassName, p.kids, p.attrs, p.Changed = class, {}, {}, signal()
    for k, v in pairs(props or {}) do o[k] = v end
    return o
end
local DEFAULTS = {
    ColorCorrectionEffect = {Enabled = true, TintColor = Color3.fromRGB(255, 255, 255), Saturation = 0, Contrast = 0, Brightness = 0},
    BloomEffect = {Enabled = true, Intensity = 1, Size = 24, Threshold = 2},
    Atmosphere = {Density = .395, Offset = 0, Haze = 0, Glare = 0, Color = Color3.fromRGB(199, 199, 199), Decay = Color3.fromRGB(106, 112, 125)},
}
local Instance = {new = function(class)
    local o = object(class, {Name = class})
    for k, v in pairs(DEFAULTS[class] or {}) do o[k] = v end
    if class == "ProximityPrompt" then o.Triggered = signal() end
    return o
end}
local game = object("DataModel", {Name = "Game"})

-- coroutine scheduler: task.wait yields the calling thread until the fake clock reaches its wake time
local clock = 0
local queue, cancelled = {}, {}
local task = {}
function task.spawn(fn, ...)
    local co = coroutine.create(fn)
    local ok, err = coroutine.resume(co, ...)
    assert(ok, err)
    return co
end
function task.wait(t)
    t = t or 1 / 60
    table.insert(queue, {t = clock + t, co = coroutine.running()})
    coroutine.yield()
    return t
end
function task.cancel(co) cancelled[co] = true end
function task.defer(fn, ...) fn(...) end
function task.delay(t, fn, ...) table.insert(queue, {t = clock + t, fn = fn, args = {...}}) end
local function runUntil(limit)
    while true do
        table.sort(queue, function(a, b) return a.t < b.t end)
        local e = queue[1]
        if not e or e.t > limit then clock = limit; return end
        table.remove(queue, 1)
        clock = e.t
        if e.fn then e.fn(table.unpack(e.args))
        elseif not cancelled[e.co] and coroutine.status(e.co) == "suspended" then
            local ok, err = coroutine.resume(e.co)
            assert(ok, err)
        end
    end
end
local os = {clock = function() return clock end}
'''

# ── Level2BlenderPreviewButton: grade, water look, flicker, camera clamp ──
CLIENT_PRELUDE = r'''
local NEW_MAP = "Level 2 Poolrooms New (preview)"
local player = object("Player", {Name = "Developer"})
local others = {}
local Players = {GetPlayers = function() local list = {player}; for _, o in ipairs(others) do table.insert(list, o) end; return list end}
local workspace = object("Workspace", {Name = "Workspace", Parent = game})
local Terrain = object("Terrain", {Name = "Terrain", WaterColor = Color3.fromRGB(12, 84, 92), WaterTransparency = .3,
    WaterReflectance = 1, WaterWaveSize = .15, WaterWaveSpeed = 10})
Terrain.Parent = workspace
workspace.Terrain = Terrain
local model = object("Model", {Name = NEW_MAP}); model.Parent = workspace
local Lighting = object("Lighting", {Name = "Lighting", ClockTime = 14, Brightness = 1.35, GeographicLatitude = 41.7,
    Ambient = Color3.fromRGB(76, 69, 45), OutdoorAmbient = Color3.fromRGB(48, 43, 28),
    ColorShift_Top = Color3.fromRGB(0, 0, 0), ColorShift_Bottom = Color3.fromRGB(0, 0, 0),
    EnvironmentDiffuseScale = 1, EnvironmentSpecularScale = 1, ExposureCompensation = 0,
    GlobalShadows = true, ShadowSoftness = .5, Parent = game})
local placeAtmosphere = object("Atmosphere", {Name = "Atmosphere", Density = .25, Offset = .25, Haze = 0, Glare = 0,
    Color = Color3.fromRGB(199, 199, 199), Decay = Color3.fromRGB(106, 112, 125)})
placeAtmosphere.Parent = Lighting
local lobbyGrade = object("ColorCorrectionEffect", {Name = "LobbyLocalGrade", Enabled = true}); lobbyGrade.Parent = Lighting
local sunRays = object("SunRaysEffect", {Name = "SunRays", Enabled = true}); sunRays.Parent = Lighting
local oldBloom = object("BloomEffect", {Name = "Bloom", Enabled = false}); oldBloom.Parent = Lighting
local Enum = {EasingStyle = {Sine = "Sine"}, EasingDirection = {InOut = "InOut"}, RaycastFilterType = {Exclude = "Exclude"},
    RenderPriority = {Camera = {Value = 200}}, CameraType = {Custom = "Custom", Scriptable = "Scriptable"}}
local tweenWrite, tweensMade = false, 0
local TweenInfo = {new = function() return {} end}
local TweenService = {Create = function(_, target, _, goals)
    tweensMade += 1
    local t = {}
    function t:Play() tweenWrite = true; for k, v in pairs(goals) do target[k] = v end; tweenWrite = false end
    function t:Cancel() end
    return t
end}
local Random = {new = function()
    local s = 12345
    local r = {}
    local function nxt() s = (s * 1103515245 + 12345) % 2147483648; return s / 2147483648 end
    function r:NextNumber(a, b) a = a or 0; b = b or 1; return a + (b - a) * nxt() end
    function r:NextInteger(a, b) return a + math.floor((b - a + 1) * nxt()) end
    return r
end}
local RunService = {steps = {}}
function RunService:BindToRenderStep(name, priority, fn) self.steps[name] = {priority = priority, fn = fn} end
local RaycastParams = {new = function()
    local params = {FilterDescendantsInstances = {}}
    function params:AddToFilter(i) table.insert(self.FilterDescendantsInstances, i) end
    return params
end}
'''

CLIENT_CHECKS = r'''
-- ── grade: take, apply, knobs, guard, release ──
local before = {ClockTime = Lighting.ClockTime, Brightness = Lighting.Brightness, Ambient = Lighting.Ambient,
    Density = placeAtmosphere.Density, WaterColor = Terrain.WaterColor, WaterReflectance = Terrain.WaterReflectance,
    WaterWaveSize = Terrain.WaterWaveSize}
check(grade == nil, "nothing owned before the character is in the map")
takeGrade(); applyGrade()
local ours = Lighting:FindFirstChild("Level 2 New Map Grade")
local ourBloom = Lighting:FindFirstChild("Level 2 New Map Bloom")
check(Lighting.ClockTime == 13 and Lighting.Brightness == .9 and Lighting.Ambient == Color3.fromRGB(20, 24, 25)
    and Lighting.OutdoorAmbient == Color3.fromRGB(13, 16, 17)
    and Lighting.EnvironmentDiffuseScale == .08 and Lighting.ExposureCompensation == -.05 and Lighting.GlobalShadows == true,
    "dark grade with a daytime sun (weak shafts), owner F21; a touch lighter, owner 2026-10-08")
check(placeAtmosphere.Density == .3 and placeAtmosphere.Color == Color3.fromRGB(28, 34, 36) and placeAtmosphere.Glare == 0,
    "the place's own Atmosphere is darkened for depth")
check(Terrain.WaterColor == Color3.fromRGB(24, 62, 60) and Terrain.WaterReflectance == .06 and Terrain.WaterWaveSize == .03
    and Terrain.WaterTransparency == .4 and Terrain.WaterWaveSpeed == 1.2, "client-local dark teal water: low reflectance, small waves")
check(ours and ours.ClassName == "ColorCorrectionEffect" and ours.Enabled and ours.Saturation == -.3
    and ourBloom and ourBloom.Enabled and ourBloom.Intensity == .5, "own cold grade and bloom on")
check(lobbyGrade.Enabled == false and sunRays.Enabled == false and oldBloom.Enabled == false,
    "inherited grades, sun rays and bloom are held off")
local rotunda = object("Model", {Name = "Developer"})
local rotundaRoot = object("Part", {Name = "HumanoidRootPart", Position = V(69790, 285.8, 30)}); rotundaRoot.Parent = rotunda
player.Character = rotunda; applyGrade()
check(Lighting.ClockTime == 12 and Lighting.GeographicLatitude == 23.5,
    "in the lion rotunda the sun stands over the oculus (12:00 at the measured latitude)")
Lighting.ClockTime = 9 -- a foreign write while in the rotunda
check(Lighting.ClockTime == 12, "a foreign write in the rotunda is put straight back to the A2 sun")
model:SetAttribute("A2GradeLatitude", 20.25); applyGrade()
check(Lighting.GeographicLatitude == 20.25, "A2GradeLatitude retunes the rotunda's sun live")
model:SetAttribute("A2GradeLatitude", nil)
rotundaRoot.Position = V(69790, 380, 30); applyGrade()
check(Lighting.ClockTime == 12, "flying up under the oculus is still the rotunda")
rotundaRoot.Position = V(69860, 285.8, 0); applyGrade()
check(Lighting.ClockTime == 13 and Lighting.GeographicLatitude == 0.0, "out of the drum: back to 13:00, the place's latitude")
rotundaRoot.Position = V(69790, 400, 30); applyGrade()
check(Lighting.ClockTime == 13, "above the dome is not the rotunda")
player.Character = nil; applyGrade()
model:SetAttribute("GradeAmbient", Color3.fromRGB(40, 41, 42))
model:SetAttribute("GradeBrightness", "bright") -- wrong type: the default stays
model:SetAttribute("GradeWaterReflectance", .02)
applyGrade()
check(Lighting.Ambient == Color3.fromRGB(40, 41, 42) and Lighting.Brightness == .9 and Terrain.WaterReflectance == .02,
    "model attributes retune the grade live; a wrong-typed attribute is ignored")
Lighting.ClockTime = 9 -- a server write while owned
check(Lighting.ClockTime == 13, "a foreign Lighting write is put straight back")
Terrain.WaterColor = Color3.fromRGB(70, 170, 150)
check(Terrain.WaterColor == Color3.fromRGB(24, 62, 60), "a foreign water write is put straight back")
lobbyGrade.Enabled = true; applyGrade()
check(lobbyGrade.Enabled == false, "the re-apply holds an inherited grade off again")
releaseGrade()
check(grade == nil and Lighting.ClockTime == 9 and Lighting.Brightness == before.Brightness and Lighting.Ambient == before.Ambient
    and placeAtmosphere.Density == before.Density and Terrain.WaterColor == Color3.fromRGB(70, 170, 150)
    and Terrain.WaterReflectance == before.WaterReflectance and Terrain.WaterWaveSize == before.WaterWaveSize,
    "release restores the place (a write made while owned is what comes back)")
check(Lighting.GeographicLatitude == 41.7, "release gives the place its own latitude back")
check(lobbyGrade.Enabled == true and sunRays.Enabled == true and oldBloom.Enabled == false
    and ours.Enabled == false and ourBloom.Enabled == false, "release gives inherited effects their own state back")
Lighting.ClockTime = 5
check(Lighting.ClockTime == 5, "after release nothing is enforced")
placeAtmosphere.Parent = nil
takeGrade(); applyGrade()
local made = Lighting:FindFirstChildOfClass("Atmosphere")
check(made and made.Name == "Level 2 New Map Atmosphere" and made.Density == .3, "no place Atmosphere: one is made")
releaseGrade()
check(Lighting:FindFirstChildOfClass("Atmosphere") == nil and made.destroyed, "and removed again on release")
placeAtmosphere.Parent = Lighting
print("Level 2 new map client grade: " .. checks .. " checks passed")

-- ── flicker ──
local before2 = checks
local holder = object("Part", {Name = "A3_Sodium_07"}); holder:SetAttribute("L2NFlicker", true); holder:SetAttribute("BaseBrightness", 2)
local light = object("PointLight", {Name = "PointLight", Brightness = 2}); light.Parent = holder
local steady = object("Part", {Name = "A3_Sodium_08"}); steady:SetAttribute("BaseBrightness", 2)
local steadyLight = object("PointLight", {Name = "PointLight", Brightness = 2}); steadyLight.Parent = steady
local writes = {}
light.Changed:Connect(function(property)
    if property == "Brightness" then table.insert(writes, {value = light.Brightness, tween = tweenWrite}) end
end)
local steadyWrites = 0
steadyLight.Changed:Connect(function() steadyWrites += 1 end)
watchFlicker(holder); watchFlicker(steady); watchFlicker(holder)
runUntil(clock + 200)
check(#writes == 0 and steadyWrites == 0, "outside the map (no grade) no lamp flickers")
player:SetAttribute("ReduceFlashing", false)
takeGrade(); applyGrade()
runUntil(clock + 200)
local zero, other = false, false
for _, w in ipairs(writes) do
    if w.value == 0 and not w.tween then zero = true end
    if w.value ~= 0 and w.value ~= 2 then other = true end
end
check(zero and not other and steadyWrites == 0, "inside the map an L2NFlicker lamp cuts out (0) and comes back at BaseBrightness")
table.clear(writes)
player:SetAttribute("ReduceFlashing", nil) -- not loaded yet = reduced
local made0 = tweensMade
runUntil(clock + 200)
local snapped = false
for _, w in ipairs(writes) do if not w.tween then snapped = true end end
check(#writes > 0 and not snapped and tweensMade > made0, "ReduceFlashing (anything but false) only fades")
light.Brightness = 0
stopFlicker(holder)
check(light.Brightness == 2, "a lamp that stops (streams out) is left on at BaseBrightness")
table.clear(writes)
runUntil(clock + 200)
check(#writes == 0, "and its thread is gone")
releaseGrade()
print("Level 2 new map lamp flicker: " .. (checks - before2) .. " checks passed")

-- ── third-person camera clamp ──
local before3 = checks
local clamp = RunService.steps.Level2NewMapCameraClamp
check(clamp and clamp.priority == 201, "bound one step after the camera module")
check(cameraParams.IgnoreWater == true and cameraParams.RespectCanCollide == true
    and cameraParams.FilterType == "Exclude", "water and non-colliding parts are never walls")
local collision = object("Model", {Name = "Collision"}); collision.Parent = model
local guards = object("Model", {Name = "Guards"}); guards.Parent = collision
local wall = object("Part", {Name = "Part"}); wall.Parent = collision
local barrier = object("Part", {Name = "Barrier"}); barrier.Parent = collision
local guard = object("Part", {Name = "Guard"}); guard.Parent = guards
local character = object("Model", {Name = "Developer"}); player.Character = character
local hits = {} -- {instance, distance} along the cast
function workspace:Spherecast(origin, radius, direction, params)
    check(radius == .5, "camera sphere radius")
    local best
    for _, h in ipairs(hits) do
        local filtered = false
        for _, f in ipairs(params.FilterDescendantsInstances) do
            if h[1] == f or h[1]:IsDescendantOf(f) then filtered = true end
        end
        if not filtered and h[2] <= direction.Magnitude and (not best or h[2] < best.Distance) then
            best = {Instance = h[1], Distance = h[2], Position = origin + direction.Unit * h[2]}
        end
    end
    return best
end
local camera = {CameraType = "Custom", Focus = CF(V(0, 10, 0)), CFrame = CF(V(0, 10, 12))}
workspace.CurrentCamera = camera
local function frame(at) camera.CFrame = CF(at); clamp.fn() end
hits = {{wall, 5}}
frame(V(0, 10, 12)); check(near(camera.CFrame.Position, V(0, 10, 12)), "outside the map the camera is left alone")
takeGrade(); applyGrade()
frame(V(0, 10, 12)); check(near(camera.CFrame.Position, V(0, 10, 5)), "a wall between focus and camera pulls the camera to it")
hits = {{barrier, 2}, {guard, 3}, {character, 1}, {wall, 7}}
frame(V(0, 10, 12)); check(near(camera.CFrame.Position, V(0, 10, 7)), "guards, Barriers and the character are not walls")
hits = {{wall, 30}}
frame(V(0, 10, 12)); check(near(camera.CFrame.Position, V(0, 10, 12)), "nothing in reach: unchanged")
hits = {{wall, .2}}
frame(V(0, 10, .5)); check(near(camera.CFrame.Position, V(0, 10, .5)), "first person (focus 0.5 away) is never touched")
camera.CameraType = "Scriptable"; frame(V(0, 10, 12))
check(near(camera.CFrame.Position, V(0, 10, 12)), "kill/spectate cameras are left alone")
releaseGrade()
print("Level 2 new map camera clamp: " .. (checks - before3) .. " checks passed")
'''

# ── Level2BlenderPreviewAccess: exit slide build, hazard collection, zone loop ──
SERVER_PRELUDE = r'''
local NEW_MAP, RETURN_PROMPT, RANGE, COOLDOWN = "Level 2 Poolrooms New (preview)", "Level2NewMapReturnPrompt", 12, 2
local nextUse = {}
local warnings = {}
local function warn(...) table.insert(warnings, table.concat({...}, " ")) end
local workspace = object("Workspace", {Name = "Workspace"})
local Players = object("Players", {Name = "Players"})
function Players:GetPlayers() return self.kids end
local ServerStorage = object("ServerStorage", {Name = "ServerStorage"})
local ServerScriptService = object("ServerScriptService", {Name = "ServerScriptService"})
local systems = object("Folder", {Name = "Level 2 Systems"}); systems.Parent = ServerScriptService
local builderModule = object("ModuleScript", {Name = "Level 2 World Builder"}); builderModule.Parent = systems
local configModule = object("ModuleScript", {Name = "Level 2 Configuration"}); configModule.Parent = systems
local calls = {}
local WorldBuilder = {
    MakeEntryTub = function(...) table.insert(calls, {"tub", ...}) end,
    MakeTubeFromPoints = function(...) table.insert(calls, {"tube", ...}) end,
}
local TILE_COOL = Color3.fromRGB(206, 221, 212)
local function require(module)
    if module == builderModule then return WorldBuilder end
    if module == configModule then return {Colors = {TileCool = TILE_COOL}} end
    error("unexpected require")
end
local Enum = {RaycastFilterType = {Include = "Include"}, Material = {SmoothPlastic = "SmoothPlastic"},
    PartType = {Block = "Block", Cylinder = "Cylinder"}, CameraMode = {Classic = "Classic"},
    NormalId = {Front = "Front", Top = "Top"}, RollOffMode = {InverseTapered = "InverseTapered"},
    ParticleEmitterShape = {Box = "Box"}, ParticleEmitterShapeStyle = {Volume = "Volume"},
    ModelStreamingMode = {Atomic = "Atomic"}}
local RaycastParams = {new = function() return {} end}
-- what the F8 water FX (hookNewMap -> buildWaterFx) builds with: Lerp, lookAt, the particle value types and the
-- Level 2 Sound Library's water bed
local vIndex = vmeta.__index
vmeta.__index = function(v, k)
    if k == "Lerp" then return function(a, b, t) return a + (b - a) * t end end
    return vIndex(v, k)
end
CFrame.lookAt = function(at, target) local cf = CF(at); cf.Look = (target - at).Unit; return cf end
local ColorSequence = {new = function(c) return {kind = "ColorSequence", c} end}
local NumberSequence = {new = function(points) return {kind = "NumberSequence", points} end}
local NumberSequenceKeypoint = {new = function(t, v) return {t, v} end}
local NumberRange = {new = function(a, b) return {Min = a, Max = b or a} end}
local Vector2 = {new = function(x, y) return {X = x, Y = y} end}
local ReplicatedStorage = object("ReplicatedStorage", {Name = "ReplicatedStorage"})
local soundLibrary = object("Folder", {Name = "Level 2 Sound Library"}); soundLibrary.Parent = ReplicatedStorage
object("StringValue", {Name = "Level 2 Distant Water", Value = " 1234567 "}).Parent = soundLibrary
local plainFind = methods.FindFirstChild
function methods:FindFirstChild(name, recursive) -- Studio's recursive flag (the skylight finds A2_BeamCone)
    local hit = plainFind(self, name)
    if hit or not recursive then return hit end
    for _, c in ipairs(self.kids) do
        local found = c:FindFirstChild(name, true)
        if found then return found end
    end
    return nil
end
local lightsFolder = object("Folder", {Name = "Lights"})
local a2Lights = object("Folder", {Name = "A2"}); a2Lights.Parent = lightsFolder
local beamHolder = object("Part", {Name = "A2_BeamCone", CFrame = CF(V(69742.6, 340.28, 0))}); beamHolder.Parent = a2Lights
local beamSpot = object("SpotLight", {Name = "SpotLight", Face = "Bottom", Angle = 11, Brightness = .4, Range = 60,
    Shadows = true}); beamSpot.Parent = beamHolder
local model = object("Model", {Name = NEW_MAP}); model.Parent = workspace
model:SetAttribute("BoundsCenter", V(70000, 300, 0)); model:SetAttribute("BoundsSize", V(500, 200, 500))
lightsFolder.Parent = model
local markers = object("Folder", {Name = "Markers"}); markers.Parent = model
local collision = object("Model", {Name = "Collision"}); collision.Parent = model
local function marker(name, at)
    local p = object("Part", {Name = name, Position = at, CFrame = CF(at), Size = V(1, 1, 1)}); p.Parent = markers
    return p
end
marker("SPAWN", V(69256.4, 303, 710.42)); marker("P0_00", V(70000, 303, 0)); marker("EXIT", V(70082.94, 339.61, -462.18))
local exitSlide = marker("EXIT_SLIDE", V(70097.1, 339.61, -462.18)) -- build.luau lifts markers 3 studs
-- the exporter's fall barriers in the slide room's far-wall hole (packet 2026-10-08, mouth-relative), one over it,
-- and a rail guard: only the three in the hole may stop colliding
local guardsFolder = object("Model", {Name = "Guards"}); guardsFolder.Parent = collision
local MOUTH0 = V(70097.1, 336.6 + 8.3, -462.18)
local holeBarriers = {}
for _, d in ipairs({V(4.58, -3.3, 3.8), V(4.58, -3.3, -3.8), V(5.29, -3.3, 0)}) do
    local b = object("Part", {Name = "Barrier", Position = MOUTH0 + d, CanCollide = true}); b.Parent = guardsFolder
    table.insert(holeBarriers, b)
end
local roofBarrier = object("Part", {Name = "Barrier", Position = MOUTH0 + V(4.58, 15.7, 0), CanCollide = true})
roofBarrier.Parent = guardsFolder
local railGuard = object("Part", {Name = "Guard", Position = MOUTH0 + V(5, -3.3, 0), CanCollide = true})
railGuard.Parent = guardsFolder
-- real fall barriers just outside the filter's window (in front of the wall, past it, beside the hole)
local nearBarriers = {}
for _, d in ipairs({V(2.5, -3.3, 0), V(7.5, -3.3, 0), V(4.58, -3.3, 8.5), V(4.58, -8.5, 0)}) do
    local b = object("Part", {Name = "Barrier", Position = MOUTH0 + d, CanCollide = true}); b.Parent = guardsFolder
    table.insert(nearBarriers, b)
end
local rays = {}
function workspace:Raycast(origin, direction, params)
    table.insert(rays, {origin = origin, direction = direction, params = params})
    if params.FilterType == "Include" and params.FilterDescendantsInstances[1] == collision then
        return {Position = V(origin.X, 336.6, origin.Z)} -- the room's floor collider
    end
    return nil
end
local function body(name)
    local b = object("Model", {Name = name})
    local root = object("Part", {Name = "HumanoidRootPart", Position = V(0, 30, 0)}); root.Parent = b
    local humanoid = object("Humanoid", {Name = "Humanoid", Health = 100, RootPart = root}); humanoid.Parent = b
    return b, humanoid, root
end
local developer = object("Player", {Name = "Developer"}); developer.Parent = Players
local diver, diverHumanoid, diverRoot = body("Developer"); developer.Character = diver
'''

SERVER_CHECKS = r'''
-- the slide: the World Builder's own tub and tube, with the live exit flume's arguments
buildExitSlide(model, exitSlide)
local slide = model:FindFirstChild("Exit Slide")
check(slide and slide.ClassName == "Model", "the Exit Slide model is built inside the preview model")
check(rays[1].params.FilterType == "Include" and rays[1].params.FilterDescendantsInstances[1] == collision,
    "the deck height is read from the map's own floor collider")
local tub, tube = calls[1], calls[2]
local mouth = V(70097.1, 336.6 + 8.3, -462.18)
check(tub[1] == "tub" and tub[2] == slide and near(tub[3], mouth, 1e-4) and near(tub[4], mouth + V(8, 0, 0), 1e-4)
    and tub[5] == 8 and tub[6] == 336.6 and tub[7] == TILE_COOL and tub[8] == "Level 2 Exit Flume"
    and tub[9] == true and tub[10] == false,
    "MakeEntryTub(slide, mouth = deck + 8.3, +X, r 8, deckTop, TileCool, the flume's name, collidable, not forced)")
local pts = tube[3]
local tail = mouth + V(8 + 120 + 60, -32, 0)
check(tube[1] == "tube" and tube[2] == slide and #pts == 76 and near(pts[1], mouth, 1e-4)
    and near(pts[2], mouth + V(8, 0, 0), 1e-4) and near(pts[74], mouth + V(128, -32, 0), 1e-4) and near(pts[76], tail, 1e-4)
    and tube[4] == 8 and tube[5] == TILE_COOL and tube[6] == "Level 2 Exit Flume" and tube[7] == false and tube[8] == .18
    and tube[9] == nil and tube[10] == nil and tube[11] == true,
    "MakeTubeFromPoints: a lead, the live flume's 72-point plunge (120 on, 32 down) and a 60-stud runout, one-way")
local monotone, lowest, steepest = true, math.huge, 0
for i = 2, #pts do
    local d = pts[i] - pts[i - 1]
    monotone = monotone and d.X > 0 and d.Y <= 1e-9 and math.abs(pts[i].Z - mouth.Z) < 1e-6
    lowest = math.min(lowest, pts[i].Y)
    steepest = math.max(steepest, -d.Y / d.X)
end
check(monotone and lowest - 8 > 304 and steepest < math.tan(math.rad(20)) and steepest > 1.2 * 32 / 120,
    "the ride only runs on and down, its bore stays over the site's ground sheet (Y 300), a curved plunge "
        .. "(steeper mid-way than a straight ramp) never steeper than 20 deg")
check(slide.ModelStreamingMode == "Atomic", "the slide streams whole: no missing segment under a rider")
local stop = slide:FindFirstChild("Exit Slide End Stop")
check(stop and near(stop.CFrame.Position, tail + V(1, 0, 0), 1e-4) and stop.Size == V(4, 18, 18)
    and stop.CanCollide ~= false and stop.Color == Color3.new(0, 0, 0), "a solid black seal overlaps the runout's end")
local finish = slide:FindFirstChild("Exit Slide Finish")
local bottom = mouth + V(128, -32, 0)
check(finish and finish.Transparency == 1 and finish.CanCollide == false and finish.CanTouch == false
    and inside(finish, bottom - V(25, -2, 0)) and inside(finish, tail - V(1, 0, 0)) and not inside(finish, bottom - V(27, -4, 0))
    and not inside(finish, tail + V(4, 0, 0)) and not inside(finish, bottom + V(0, 0, 9)),
    "the finish runs from 26 studs before the plunge's end to the stop, inside the bore (polled, not Touched)")
check(inside(finish, bottom + V(10, -6.5, 0)) and inside(finish, bottom + V(10, 7, 0)) and inside(finish, bottom + V(-20, -6, 0))
    and inside(finish, bottom + V(10, -4.2, 6.5)),
    "a rider's root anywhere in the bore is inside: on the floor, at the ceiling, in the plunge's tail, at the side")
check(holeBarriers[1].CanCollide == false and holeBarriers[2].CanCollide == false and holeBarriers[3].CanCollide == false
    and roofBarrier.CanCollide == true and railGuard.CanCollide == true and nearBarriers[1].CanCollide == true
    and nearBarriers[2].CanCollide == true and nearBarriers[3].CanCollide == true and nearBarriers[4].CanCollide == true,
    "only the exporter's three barriers across the far wall's hole stop colliding (the bore fills it)")

-- hookNewMap: prompts, the slide build, KillZone hazards anywhere under Collision, the zone loop
model:FindFirstChild("Exit Slide").Parent = nil
local spawned = {}
task.spawn = function(fn) table.insert(spawned, fn) end
local pitBox = object("Part", {Name = "Hazard", CFrame = CF(V(70050, 250, 0)), Size = V(10, 40, 10)})
pitBox:SetAttribute("KillZone", true); pitBox.Parent = collision
local nested = object("Model", {Name = "Pits"}); nested.Parent = collision
local drain = object("Part", {Name = "Hazard", Shape = "Cylinder", CFrame = CF(V(70200, 250, 0)), Size = V(40, 10, 10)})
drain:SetAttribute("KillZone", true); drain.Parent = nested
local unflagged = object("Part", {Name = "Hazard", CFrame = CF(V(70300, 250, 0)), Size = V(10, 10, 10)}); unflagged.Parent = collision
hookNewMap()
-- the A2 skylight: the shaft from the oculus throat to the island, the dust, the oculus spot moved onto the disc
local sky = model:FindFirstChild("A2 Skylight")
local shaft = sky and sky:FindFirstChild("Shaft")
check(shaft and near(shaft.CFrame.Position, V(69742.6, 343.25, 0), 1e-4) and shaft.Size == V(14, 101.5, 14)
    and shaft.CanCollide == false and shaft.CanQuery == false and shaft.Transparency == 1,
    "the skylight's shaft spans the oculus throat (Y 394) down to just over the gold disc (Y 292.5), on the axis")
local beams, dust, widest = 0, nil, 0
for _, c in ipairs(shaft:GetChildren()) do
    if c.ClassName == "Beam" and c.FaceCamera == true and c.LightEmission == 1 and c.LightInfluence == 0
        and c.Attachment0 and c.Attachment1 and c.Attachment0.Position.Y == 50.75 and c.Attachment1.Position.Y == -50.75
        and c.Transparency[1][1][2] == .9 and c.Width0 < c.Width1 then
        beams += 1
        widest = math.max(widest, c.Width0)
    end
    if c.ClassName == "ParticleEmitter" then dust = c end
end
check(beams == 7 and widest <= 17.16 and dust and dust.Texture == "rbxasset://textures/particles/sparkles_main.dds",
    "seven thin additive camera-facing layers, widening downwards, none wider than the 17.16-stud throat; sparkles")
local spotAt = V(69742.6, 287.9 + 26, 0) + V(.7071, 0, .7071) * 9
check(near(beamHolder.CFrame.Position, spotAt, 1e-4) and near(beamHolder.CFrame.Look, (V(69742.6, 287.9, 0) - spotAt).Unit, 1e-4)
    and beamSpot.Face == "Front" and beamSpot.Angle == 24 and beamSpot.Brightness == 8 and beamSpot.Range == 60
    and beamSpot.Shadows == true and beamHolder:GetAttribute("BaseBrightness") == 8,
    "the oculus spot hangs 26 studs over the gold disc, leaning to its entry-side face (BaseBrightness follows)")
check(markers:FindFirstChild("SPAWN"):FindFirstChild(RETURN_PROMPT) and markers:FindFirstChild("P0_00"):FindFirstChild(RETURN_PROMPT)
    and markers:FindFirstChild("EXIT"):FindFirstChild(RETURN_PROMPT),
    "RETURN TO LOBBY prompts at Level 1's door (SPAWN, the arrival), P0_00 and EXIT")
check(#spawned == 2, "the slide build and the zone loop each run in their own thread")
-- F8 on the raised water stair (owner 2026-10-08). passages_a.build_p2, re-derived here: the sheet is
-- UP_BED + (s - S_C0) * 0.59 / 1.25 + D_CASC (m, s = -Z / 2.86), D_CASC 0.45; the upper pool runs on to
-- nosing 0 (Z 148), so the foam starts there; the toe is S_TOE + 0.002 (Z 180.17).
local function sheetY(z) return (-40.85 + (-z / 2.86 + 50.5) * .59 / 1.25 + .45) * 2.86 + 300 end
local fx = model:FindFirstChild("Water FX")
check(fx and #fx:GetChildren() == 9 and #warnings == 0, "the water FX: six foam strips, crest spray, toe mist, water bed")
local crest, toe = CASCADE_CREST, CASCADE_TOE
check(crest.Z == 148 and math.abs(crest.Y - sheetY(148)) < .01 and math.abs(toe.Z - 180.17) < 1e-9
    and math.abs(toe.Y - sheetY(180.17)) < .01, "crest at nosing 0 and toe on the raised sheet (passages_a numbers)")
for i = 0, 5 do
    local p = fx:FindFirstChild("Cascade Foam " .. i).CFrame.Position
    check(p.Z > 148 and p.Z < 180.17 and math.abs(p.Y - (sheetY(p.Z) + .25)) < .02,
        "foam strip " .. i .. " rides 0.25 stud over the raised sheet, on the visible run")
end
local water = fx:FindFirstChild("Cascade Sound") and fx:FindFirstChild("Cascade Sound"):FindFirstChild("Cascade Water")
check(water and water.SoundId == "rbxassetid://1234567" and water.Looped and water.Playing, "the water bed plays the library id")
spawned[1]()
check(model:FindFirstChild("Exit Slide") ~= nil and #warnings == 0, "the boot thread builds the slide")
local waits = 0
task.wait = function() waits += 1; if waits > 1 then error("stop") end; return .1 end
local function pass(position)
    waits = 0; diverHumanoid.Health = 100; diverRoot.Position = position
    pcall(spawned[2])
    return diverHumanoid.Health
end
check(pass(V(70050, 271, 0)) == 100, "above a pit's kill box: alive")
check(pass(V(70054, 232, -4)) == 0, "inside a KillZone Hazard: dead")
check(pass(V(70200, 254, 0)) == 0, "inside the drain's round kill zone (a Hazard under a sub-model): dead")
check(pass(V(70200, 254, 4)) == 100, "outside the drain's circle (its bounding box corner): alive")
check(pass(V(70300, 250, 0)) == 100, "a Hazard without KillZone=true never kills")
model.Parent = nil
waits = 0; diverHumanoid.Health = 100; diverRoot.Position = V(70054, 232, -4); spawned[2]()
check(diverHumanoid.Health == 100 and waits == 0, "the loop ends with the model")
print("Level 2 new map exit slide and kill zones: " .. checks .. " checks passed")
'''

# ── RoundUI restore(): ownership keeps the pre-R4 lobby values pending ──
ROUNDUI_PROGRAM = r'''
local attrs, worldAttrs = {}, {}
local player = {GetAttribute = function(_, key) return attrs[key] end}
local workspace = {GetAttribute = function(_, key) return worldAttrs[key] end, FindFirstChild = function() return nil end}
local Lighting = {ClockTime = 0, Ambient = "r4-ambient"}
local lobbyGrade = {}
local revisedLobbyLighting = {active = true, atmospheres = {}}
''' + "__RESTORE__" + r'''
local atmosphere = {Parent = Lighting, Density = 0}
local function arm()
    revisedLobbyLighting.lighting = {ClockTime = 14, Ambient = "lobby-ambient"}
    revisedLobbyLighting.applied = {ClockTime = 0, Ambient = "r4-ambient"}
    revisedLobbyLighting.atmospheres[atmosphere] = .3
    Lighting.ClockTime, Lighting.Ambient, atmosphere.Density = 0, "r4-ambient", 0
end
arm(); attrs.Level2NewMapLightingOwned = true
revisedLobbyLighting.restore()
check(revisedLobbyLighting.lighting ~= nil and Lighting.ClockTime == 0 and revisedLobbyLighting.atmospheres[atmosphere] == .3
    and atmosphere.Density == 0, "while the new map owns the look, the pre-R4 lobby values stay pending")
attrs.Level2NewMapLightingOwned = false
revisedLobbyLighting.restore()
check(revisedLobbyLighting.lighting == nil and Lighting.ClockTime == 14 and Lighting.Ambient == "lobby-ambient"
    and atmosphere.Density == .3 and next(revisedLobbyLighting.atmospheres) == nil,
    "once it lets go, restore() puts the lobby back (no R4 night leaks)")
arm(); attrs.Level4LightingOwned = true
revisedLobbyLighting.restore()
check(Lighting.ClockTime == 0 and atmosphere.Density == 0, "Level 4 ownership still holds them too")
print("RoundUI restore with Level2NewMapLightingOwned: " .. checks .. " checks passed")
'''

# ── GameManager onCharacter + DevCheats applyPerspective ──
CAMERA_PROGRAM = r'''
local Enum = {CameraMode = {Classic = "Classic", LockFirstPerson = "LockFirstPerson"}}
local inRound, characterLoadOwner, loadingFailures = {}, {}, {}
local failedReservedEntry, worldReady, activeLevel = false, true, 1
local pendingExplicitPlacement, pendingReentryPlacement = {}, {}
local lobbySpawn = {Name = "LobbySpawn"}
local scattered, lobbyLoads = 0, 0
local function scatterAt() scattered += 1 end
local function placeSafelyInElevator() return true end
local function loadLobbyCharacter() lobbyLoads += 1 end
local attrs = {}
local player = {Parent = true, GetAttribute = function(_, key) return attrs[key] end}
local function newBody()
    local humanoid = {Died = signal()}
    local char = {}
    function char:WaitForChild() return humanoid end
    function char:FindFirstChild() return nil end
    function char:FindFirstChildOfClass() return humanoid end
    return char, humanoid
end
''' + "__ONCHARACTER__" + r'''
local char = newBody(); player.Character = char
attrs.Level2NewMapPreview = true
onCharacter(player, char)
check(player.CameraMode == "LockFirstPerson" and player.CameraMinZoomDistance == .5 and player.CameraMaxZoomDistance == .5,
    "a preview body gets the round's first-person camera")
check(scattered == 0, "and is not scattered onto the lobby spawn (the preview places it)")
attrs.Level2NewMapPreview = nil
char = newBody(); player.Character = char
onCharacter(player, char)
check(player.CameraMode == "Classic" and player.CameraMinZoomDistance == 8 and player.CameraMaxZoomDistance == 18 and scattered == 1,
    "a lobby body keeps the Classic camera and the lobby scatter")
attrs.Level6PlaygroundPreview = true
char = newBody(); player.Character = char
onCharacter(player, char)
check(player.CameraMode == "LockFirstPerson" and scattered == 1, "Level 6 is unchanged")
attrs.Level6PlaygroundPreview = nil
local char2, humanoid2 = newBody(); player.Character = char2
attrs.Level2NewMapPreview = true; onCharacter(player, char2)
attrs.Level2NewMapPreview = nil -- the access script's Died hook clears it
humanoid2.Died:Fire(); runUntil(clock + 3.1)
check(player.CameraMode == "Classic" and lobbyLoads == 1, "a preview death: lobby camera, own avatar back after 3 s")
print("GameManager onCharacter with Level2NewMapPreview: " .. checks .. " checks passed")

local before = checks
local thirdPersonOn = false
local dev = {Character = nil}
local devAttrs = {}
function dev:GetAttribute(key) return devAttrs[key] end
do
    local player = dev
''' + "__PERSPECTIVE__" + r'''
    devAttrs.Level2NewMapPreview = true; applyPerspective()
    check(dev.CameraMode == "LockFirstPerson" and dev.CameraMaxZoomDistance == .5, "DevCheats keeps first person in the preview")
    thirdPersonOn = true; applyPerspective()
    check(dev.CameraMode == "Classic" and dev.CameraMinZoomDistance == 6 and dev.CameraMaxZoomDistance == 14,
        "the dev C toggle gives the round's third person there")
    devAttrs.Level2NewMapPreview = nil; thirdPersonOn = false; applyPerspective()
    check(dev.CameraMode == "Classic" and dev.CameraMinZoomDistance == 8 and dev.CameraMaxZoomDistance == 18,
        "back in the lobby: the lobby camera")
end
print("DevCheats perspective with Level2NewMapPreview: " .. (checks - before) .. " checks passed")
'''

# ── HazmatSkinVisuals refresh/addPlayer + HazmatSkinDriver reconcile ──
SKIN_PROGRAM = r'''
local Players = {}
local worldAttrs = {}
local workspace = {GetAttribute = function(_, key) return worldAttrs[key] end,
    GetAttributeChangedSignal = function() return signal() end}
local Skins = {DefaultId = "BaselineYellow", Get = function(id) return id == "BaselineYellow" end}
local Config = {Colors = {HazmatDefault = Color3.fromRGB(255,255,0)}}
''' + "__COLOR_HELPER__" + r'''
''' + "__VISUAL_DECLS__" + r'''
local built = 0
local function destroyVisual(p)
    local state = active[p]
    if state then state.Visual.Parent = nil end
    active[p] = nil
end
local function buildVisual(_, character)
    built += 1
    local visual = {Parent = character}
    function visual:Destroy() self.Parent = nil end
    return visual
end
local attrs = {ZyntraSkinId = "BaselineYellow"}
local attrSignals = {}
local player = {Parent = Players, CharacterAdded = signal(), CharacterRemoving = signal()}
function player:GetAttribute(key) return attrs[key] end
function player:GetAttributeChangedSignal(key) attrSignals[key] = attrSignals[key] or signal(); return attrSignals[key] end
function player:SetAttribute(key, value) attrs[key] = value; self:GetAttributeChangedSignal(key):Fire() end
local function newBody(name)
    local body = {Name = name, Parent = true, ChildAdded = signal(), attrs = {}, signals = {}}
    function body:GetAttribute(key) return self.attrs[key] end
    function body:GetAttributeChangedSignal(key)
        self.signals[key] = self.signals[key] or signal(); return self.signals[key]
    end
    function body:SetAttribute(key, value)
        self.attrs[key] = value; self:GetAttributeChangedSignal(key):Fire()
    end
    return body
end
local function spawnBody(b)
    if player.Character then player.CharacterRemoving:Fire(player.Character) end
    player.Character = b; player.CharacterAdded:Fire(b)
end
''' + "__REFRESH__" + r'''
local lobby = newBody("lobby"); player.Character = lobby
addPlayer(player)
check(active[player] == nil and built == 0, "a lobby avatar has no suit visual")
player:SetAttribute("Level2NewMapPreview", true) -- the flag goes up before the round body loads
check(active[player] == nil and built == 0, "the lobby avatar never gets the suit while the round body loads")
local roundBody = newBody("round"); spawnBody(roundBody)
check(active[player] == nil, "a body waits for the authoritative successful gameplay load marker")
roundBody:SetAttribute("ZyntraGameplayCharacter", true)
check(active[player] and active[player].Character == roundBody and built == 1,
    "the marked gameplay body wears the equipped skin before RoundActive")
player:SetAttribute("Level2NewMapPreview", nil)
check(active[player] and active[player].Character == roundBody, "clearing the flag retains the new suit until body removal")
local lobby2 = newBody("lobby2"); spawnBody(lobby2)
player:SetAttribute("Level2NewMapPreview", true)
check(active[player] == nil and built == 1, "a lobby body that spawned without the flag never gets it")
player:SetAttribute("Level2NewMapPreview", nil)
worldAttrs.RoundActive = true; player:SetAttribute("InRound", true)
check(active[player] == nil and built == 1, "round state never skins the outgoing lobby avatar")
local gameplay = newBody("gameplay"); spawnBody(gameplay); gameplay:SetAttribute("ZyntraGameplayCharacter", true)
check(active[player] and active[player].Character == gameplay and built == 2, "normal round loads use the same marker")
player:SetAttribute("ZyntraOwnsAdvancedEquipment", true)
local customColor = Color3.fromRGB(0,0,255)
player:SetAttribute("ZyntraHazmatColor", customColor)
if __TINT_ENABLED__ then
    check(active[player] and active[player].Character == gameplay and active[player].TintColor == customColor,
        "advanced custom colour keeps the new marked visual")
else
    check(active[player] == nil, "base candidate preserves deliberate native advanced colour fallback")
end
player:SetAttribute("ZyntraOwnsAdvancedEquipment", false)
check(active[player] and active[player].Character == gameplay and active[player].TintColor == nil,
    "without advanced ownership the authored new default skin is restored")
print("HazmatSkinVisuals with Level2NewMapPreview: " .. checks .. " checks passed")

local before = checks
local VISUAL_NAME = "ZyntraHazmatSkinVisual"
local ORIGINAL_ATTRIBUTE = "ZyntraHazmatOriginalTransparency"
local states, blockedVisuals, pendingStates = {}, {}, {}
local stateBuilt = 0
local function warnOnce() end
local function captureBody() end
local function clearState(p) states[p] = nil end
local function buildState(character, visual)
    stateBuilt += 1
    return {Character = character, Visual = visual, Mesh = {Parent = true}, Originals = {}, Visible = false}
end
''' + "__PENDING_HELPERS__" + r'''
local driverAttrs = {}
local driverBodyAttrs = {}
local suit = {Name = VISUAL_NAME}
local rider = {GetAttribute = function(_, key) return driverAttrs[key] end,
    Character = {FindFirstChild = function(_, name) return if name == VISUAL_NAME then suit else nil end,
        GetAttribute = function(_, name) return driverBodyAttrs[name] end, DescendantAdded = signal()}}
local Players = {GetPlayers = function() return {rider} end}
''' + "__RECONCILE__" + r'''
worldAttrs.RoundActive = nil
reconcile()
check(stateBuilt == 0 and states[rider] == nil, "outside a round and the preview the client never drives a suit")
driverAttrs.Level2NewMapPreview = true; reconcile()
check(stateBuilt == 0 and states[rider] == nil, "preview flag alone cannot drive a lobby body")
driverBodyAttrs.ZyntraGameplayCharacter = true; reconcile()
check(stateBuilt == 1 and states[rider] and states[rider].Visual == suit, "the preview body's suit is driven like a round's")
driverAttrs.Level2NewMapPreview = nil; reconcile()
check(states[rider] and states[rider].Visual == suit, "clearing preview ownership does not expose the old model before replacement")
driverBodyAttrs.ZyntraGameplayCharacter = nil; reconcile()
check(states[rider] == nil, "an unmarked replacement releases the old gameplay bind")
print("HazmatSkinDriver with Level2NewMapPreview: " .. (checks - before) .. " checks passed")
'''


def run(binary, directory, name, source):
    path = Path(directory) / name
    path.write_text(source, encoding="utf-8")
    subprocess.run([binary, str(path)], check=True)


def main():
    artifact_binary = ROOT / "artifacts/hazmat-20260924/luau-0.737/luau.exe"
    binary = os.environ.get("LUAU_BIN") or shutil.which("luau") or (
        str(artifact_binary) if artifact_binary.exists() else None)
    if not binary:
        raise SystemExit("Set LUAU_BIN or put luau on PATH; no checks executed.")

    client = (FAKES + CLIENT_PRELUDE
              + section(BUTTON, "local REAPPLY = 0.75", "local function refresh()")
              + section(BUTTON, "local FLICKER_FADE", "request.OnClientEvent:Connect") + CLIENT_CHECKS)
    server = (FAKES + SERVER_PRELUDE
              + section(ACCESS, "local PREVIEW_FLAG", "request.OnServerEvent:Connect(function(player, host)")
              + SERVER_CHECKS)
    roundui = FAKES + ROUNDUI_PROGRAM.replace("__RESTORE__", section(
        ROUNDUI, "function revisedLobbyLighting.restore()", "function revisedLobbyLighting.apply(mazeGrade)"))
    cameras = FAKES + CAMERA_PROGRAM.replace(
        "__ONCHARACTER__", section(MANAGER, "local function onCharacter(player, char)", "local function setupPlayer(player)")
    ).replace("__PERSPECTIVE__", section(DEVCHEATS, "local function applyPerspective()", "local function reapplyPerspectiveSoon()"))
    skins = FAKES + SKIN_PROGRAM.replace(
        "__VISUAL_DECLS__", section(VISUALS, "local active = {}", "local warned = {}")
    ).replace("__COLOR_HELPER__", section(VISUALS,
        "local function advancedHazmatColor" if "local function advancedHazmatColor" in VISUALS else "local function keepsAdvancedColor",
        "local function destroyVisual")
    ).replace("__TINT_ENABLED__", "true" if "local function advancedHazmatColor" in VISUALS else "false"
    ).replace("__PENDING_HELPERS__", (section(DRIVER, "local PENDING_TIMEOUT =", "\n\n") + "\n" +
        section(DRIVER, "local function hidePending(", "local function clearState(")) if "local function hidePending(" in DRIVER else ""
    ).replace("__REFRESH__", section(VISUALS, "local function refresh(player)", 'Players.PlayerAdded:Connect(addPlayer)')
    ).replace("__RECONCILE__", section(DRIVER, "local function reconcile()", "local elapsed = RESCAN_INTERVAL"))

    slidectl = FAKES + '''
local attrs, wattrs = {}, {}
local player = {GetAttribute = function(_, k) return attrs[k] end}
local Workspace = {GetAttribute = function(_, k) return wattrs[k] end}
''' + section(read("StarterPlayer/StarterPlayerScripts/Level 2 Slide Controller.LocalScript.lua"),
              "local function levelIsActive()", "local function setWalkSpeed(") + '''
wattrs.SelectedLevel = 1
check(levelIsActive() == false, "a lobby body does not slide")
attrs.Level2NewMapPreview = true
check(levelIsActive() == true, "a Level 2 new-map preview body rides its exit slide outside any round")
attrs = {InRound = true}; wattrs.SelectedLevel = 2
check(levelIsActive() == true, "a Level 2 round body rides")
attrs.Escaped = true
check(levelIsActive() == false, "an escaped Level 2 body stops (no exit transition)")
print("Level 2 Slide Controller gate: " .. checks .. " checks passed")
'''
    ru = read("StarterPlayer/StarterPlayerScripts/RoundUI.LocalScript.lua")
    head = 'dead and "THE OTHERS FOUND A WAY OUT" or ("LEVEL " .. tostring('
    i = ru.index(head) + len(head)
    title = FAKES + '''
local attrs, wattrs = {}, {}
local player = {GetAttribute = function(_, k) return attrs[k] end}
local workspace = {GetAttribute = function(_, k) return wattrs[k] end}
local function title() return "LEVEL " .. tostring(''' + ru[i:ru.index(') .. " CLEARED"', i)] + ''') .. " CLEARED" end
wattrs.SelectedLevel = 1
check(title() == "LEVEL 1 CLEARED", "the lobby server's own level")
attrs.Level2NewMapPreview = true
check(title() == "LEVEL 2 CLEARED", "the new-map preview's exit slide says LEVEL 2 on the lobby server")
attrs.Level5VoidRound = true
check(title() == "LEVEL 5 CLEARED", "Level 5 keeps its own number")
attrs = {}; wattrs.SelectedLevel = 3
check(title() == "LEVEL 3 CLEARED", "a real round says SelectedLevel")
print("RoundUI win title: " .. checks .. " checks passed")
'''
    with tempfile.TemporaryDirectory(prefix="level2-newmap-feedback-") as directory:
        for name, source in (("client.luau", client), ("server.luau", server), ("roundui.luau", roundui),
                             ("cameras.luau", cameras), ("skins.luau", skins), ("slidectl.luau", slidectl),
                             ("roundui_title.luau", title)):
            run(binary, directory, name, source)

    # The World Builder exports its two top-level builders, additively, right before the module returns.
    tail = BUILDER[BUILDER.rindex("WorldBuilder.MakeEntryTub = makeEntryTub"):]
    assert tail.split("\n")[:3] == ["WorldBuilder.MakeEntryTub = makeEntryTub",
                                    "WorldBuilder.MakeTubeFromPoints = makeTubeFromPoints", ""], tail[:200]
    assert tail.rstrip().endswith("return WorldBuilder") and tail.count("\n") <= 4, "export sits right before the return"
    assert BUILDER.index("\nlocal function makeEntryTub(") < BUILDER.rindex("WorldBuilder.MakeEntryTub")
    assert BUILDER.index("\nlocal function makeTubeFromPoints(") < BUILDER.rindex("WorldBuilder.MakeTubeFromPoints")
    print("Level 2 World Builder: MakeEntryTub/MakeTubeFromPoints exported (additive)")


if __name__ == "__main__":
    main()
