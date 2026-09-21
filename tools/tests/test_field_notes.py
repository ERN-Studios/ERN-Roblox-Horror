"""Run the whole Field Notes feature under the real Luau interpreter.

Four programs, each executing the ACTUAL .lua source against a fake DataModel:

  content  ReplicatedStorage/ZyntraFieldNotes           -- the twelve rows
  service  ServerScriptService/FieldNotesService        -- placement + reading
  client   StarterPlayerScripts/Field Notes Client      -- the reading card
  page     ReplicatedStorage/ZyntraFieldNotesPage       -- the NOTES tab

Nothing is copied or paraphrased: every program concatenates the real file and
drives it. The engine boundary is faked and kept honest -- Color3 has no
arithmetic, Vector3/CFrame do, ProximityPrompt.Triggered proves nothing about
distance, and PathfindingService answers Success only where a test says so.

UIStyle and ZyntraFieldNotes are loaded from their REAL sources too, so the
chrome the prop and the card wear is the chrome the game ships. UIDevice is
faked at its published API (Layout/LocalPosition/SetEnabled/Changed): it is a
separate module with its own suite, and this one is not re-testing it.

No network, no Studio. Set LUAU_BIN to an official Luau interpreter.
"""

import os
import re
from pathlib import Path
import shutil
import subprocess
import tempfile

ROOT = Path(__file__).resolve().parents[2]
CONTENT = ROOT / "ReplicatedStorage/ZyntraFieldNotes.ModuleScript.lua"
PAGE = ROOT / "ReplicatedStorage/ZyntraFieldNotesPage.ModuleScript.lua"
UISTYLE = ROOT / "ReplicatedStorage/UIStyle.ModuleScript.lua"
SERVICE = ROOT / "ServerScriptService/FieldNotesService.Script.lua"
CLIENT = ROOT / "StarterPlayer/StarterPlayerScripts/Field Notes Client.LocalScript.lua"


def read(path: Path) -> str:
    return path.read_text(encoding="utf-8")


def loader(name: str, path: Path) -> str:
    """Wrap a real module's source as a zero-argument loader function."""
    return "local function load_%s()\n%s\nend\n" % (name, read(path))


# ---------------------------------------------------------------------------
# The shared engine fake. Globals, so a module loaded inside a function body
# sees the same Instance/Enum/Vector3 the driver does.
# ---------------------------------------------------------------------------
LIB = r'''
local checks = 0
local function check(value, message)
    if not value then error("FAILED: " .. tostring(message), 2) end
    checks += 1
end

local function signal()
    local listeners = {}
    return {
        Connect = function(_, fn)
            table.insert(listeners, fn)
            return {Disconnect = function()
                for index, entry in ipairs(listeners) do
                    if entry == fn then table.remove(listeners, index); break end
                end
            end}
        end,
        Fire = function(_, ...)
            for _, fn in ipairs(table.clone(listeners)) do fn(...) end
        end,
        Count = function() return #listeners end,
    }
end

-- Vector3: real arithmetic, because the source does real arithmetic with it.
Vector3 = {}
local v3meta = {}
function Vector3.new(x, y, z)
    return setmetatable({Kind = "Vector3", X = x or 0, Y = y or 0, Z = z or 0}, v3meta)
end
v3meta.__add = function(a, b) return Vector3.new(a.X + b.X, a.Y + b.Y, a.Z + b.Z) end
v3meta.__sub = function(a, b) return Vector3.new(a.X - b.X, a.Y - b.Y, a.Z - b.Z) end
v3meta.__mul = function(a, b) return Vector3.new(a.X * b, a.Y * b, a.Z * b) end
v3meta.__eq = function(a, b) return a.X == b.X and a.Y == b.Y and a.Z == b.Z end
v3meta.__index = function(v, key)
    if key == "Magnitude" then return math.sqrt(v.X * v.X + v.Y * v.Y + v.Z * v.Z) end
    return nil
end

Vector2 = {}
function Vector2.new(x, y) return {Kind = "Vector2", X = x or 0, Y = y or 0} end

-- Color3 carries NO arithmetic metamethods, exactly like the engine's: a test
-- that multiplied one here would pass where the game throws.
Color3 = {}
function Color3.new(r, g, b) return {Kind = "Color3", R = r or 0, G = g or 0, B = b or 0} end
function Color3.fromRGB(r, g, b)
    return Color3.new((r or 0) / 255, (g or 0) / 255, (b or 0) / 255)
end

local cfmeta = {}
local function makeCF(position, up)
    return setmetatable({Kind = "CFrame", Position = position,
        UpVector = up or Vector3.new(0, 1, 0)}, cfmeta)
end
CFrame = {}
function CFrame.new(a, b, c)
    if type(a) == "table" then return makeCF(a) end
    return makeCF(Vector3.new(a or 0, b or 0, c or 0))
end
function CFrame.Angles() return makeCF(Vector3.new(0, 0, 0)) end
cfmeta.__mul = function(a, _) return makeCF(a.Position, a.UpVector) end
-- A slide tub or a ramp: same place, top face no longer level.
function tiltedCF(position) return makeCF(position, Vector3.new(0, 0.4, 0.9)) end

UDim = {}
function UDim.new(scale, offset) return {Kind = "UDim", Scale = scale or 0, Offset = offset or 0} end
UDim2 = {}
function UDim2.new(sx, ox, sy, oy)
    return {Kind = "UDim2", X = UDim.new(sx, ox), Y = UDim.new(sy, oy)}
end
function UDim2.fromOffset(x, y) return UDim2.new(0, x or 0, 0, y or 0) end
function UDim2.fromScale(x, y) return UDim2.new(x or 0, 0, y or 0, 0) end

-- Enum items are memoised, so identity comparison behaves like the engine's.
Enum = setmetatable({}, {__index = function(self, category)
    local group = setmetatable({}, {__index = function(inner, item)
        local value = {EnumType = category, Name = item}
        rawset(inner, item, value)
        return value
    end})
    rawset(self, category, group)
    return group
end})

-- Lehmer RNG. Deterministic and, unlike a textbook 32-bit LCG, every product
-- stays under 2^53 so no shuffle silently loses precision.
local randomMeta = {}
randomMeta.__index = randomMeta
Random = {}
function Random.new(seed)
    return setmetatable({state = (math.floor(math.abs(seed or 0)) % 2147483646) + 1}, randomMeta)
end
function randomMeta:step()
    self.state = (self.state * 48271) % 2147483647
    return self.state / 2147483647
end
function randomMeta:NextNumber(a, b)
    local value = self:step()
    if a and b then return a + value * (b - a) end
    return value
end
function randomMeta:NextInteger(a, b) return a + math.floor(self:step() * (b - a + 1)) end

local BASE_PARTS = {Part = true, MeshPart = true, WedgePart = true,
    CornerWedgePart = true, TrussPart = true, SpawnLocation = true}
local GUI_OBJECTS = {Frame = true, TextLabel = true, TextButton = true,
    ImageButton = true, ImageLabel = true, ScrollingFrame = true}

local nodeMethods = {}
local nodeMeta = {
    __index = function(self, key)
        if key == "Parent" then return rawget(self, "_parent") end
        return nodeMethods[key]
    end,
    __newindex = function(self, key, value)
        if key == "Parent" then
            local old = rawget(self, "_parent")
            if old then
                for index, child in ipairs(old.Children) do
                    if child == self then table.remove(old.Children, index); break end
                end
            end
            rawset(self, "_parent", value)
            if value then table.insert(value.Children, self) end
            return
        end
        -- CFrame and Position are ONE fact on a real BasePart. Letting them
        -- drift here would let a test pass where the engine reads the other one
        -- and finds nil -- which is exactly how this harness first failed.
        if key == "CFrame" and type(value) == "table" then
            rawset(self, "Position", value.Position)
        elseif key == "Position" and type(value) == "table" then
            rawset(self, "CFrame", CFrame.new(value))
        end
        rawset(self, key, value)
    end,
}

function node(class, name, parent)
    local value = setmetatable({Kind = "Instance", ClassName = class, Name = name or class,
        Children = {}, Attributes = {}}, nodeMeta)
    if parent then value.Parent = parent end
    return value
end

function nodeMethods:IsA(class)
    if class == self.ClassName then return true end
    if class == "BasePart" then return BASE_PARTS[self.ClassName] == true end
    if class == "GuiObject" then return GUI_OBJECTS[self.ClassName] == true end
    return false
end
function nodeMethods:FindFirstChild(name)
    for _, child in ipairs(self.Children) do if child.Name == name then return child end end
    return nil
end
function nodeMethods:WaitForChild(name) return self:FindFirstChild(name) end
function nodeMethods:FindFirstChildOfClass(class)
    for _, child in ipairs(self.Children) do if child.ClassName == class then return child end end
    return nil
end
function nodeMethods:GetChildren() return table.clone(self.Children) end
function nodeMethods:GetDescendants()
    local found = {}
    local function walk(parent)
        for _, child in ipairs(parent.Children) do
            table.insert(found, child)
            walk(child)
        end
    end
    walk(self)
    return found
end
function nodeMethods:IsDescendantOf(ancestor)
    local current = rawget(self, "_parent")
    while current do
        if current == ancestor then return true end
        current = rawget(current, "_parent")
    end
    return false
end
function nodeMethods:ClearAllChildren()
    for _, child in ipairs(table.clone(self.Children)) do child.Parent = nil end
end
function nodeMethods:Destroy()
    self:ClearAllChildren()
    self.Parent = nil
end
function nodeMethods:GetAttribute(key) return self.Attributes[key] end
function nodeMethods:SetAttribute(key, value)
    self.Attributes[key] = value
    local store = rawget(self, "AttributeSignals")
    local hook = store and store[key]
    if hook then hook:Fire() end
end
function nodeMethods:GetAttributeChangedSignal(key)
    local store = rawget(self, "AttributeSignals")
    if not store then store = {}; rawset(self, "AttributeSignals", store) end
    if not store[key] then store[key] = signal() end
    return store[key]
end

FIRED = {}
function nodeMethods:FireClient(player, ...)
    table.insert(FIRED, {Player = player, Args = table.pack(...)})
end
function nodeMethods:Invoke(...) return self.Handler(...) end

Instance = {}
function Instance.new(class)
    local made = node(class)
    if class == "ProximityPrompt" then made.Triggered = signal() end
    if class == "TextButton" or class == "ImageButton" then made.Activated = signal() end
    if class == "RemoteEvent" then
        made.OnClientEvent = signal()
        made.OnServerEvent = signal()
    end
    return made
end

-- A floor the service should like: big, anchored, collidable, level, opaque.
function floorPart(parent, name, x, z, size)
    local part = node("Part", name, parent)
    part.Anchored = true
    part.CanCollide = true
    part.Transparency = 0
    part.Shape = Enum.PartType.Block
    part.Material = Enum.Material.Concrete
    part.Size = Vector3.new(size or 24, 1, size or 24)
    part.Position = Vector3.new(x, -0.5, z)
    part.CFrame = CFrame.new(part.Position)
    return part
end

-- Text measurement: a deterministic stand-in for the engine's wrapper. One
-- character per 6.5px of width, one line per 17px of height.
function textService()
    return {GetTextSize = function(_, text, size, _, bounds)
        local perLine = math.max(1, math.floor(bounds.X / 6.5))
        local lines = math.max(1, math.ceil(#tostring(text) / perLine))
        return Vector2.new(bounds.X, lines * math.max(12, (size or 13) + 4))
    end}
end
'''


# ---------------------------------------------------------------------------
# 1. content
# ---------------------------------------------------------------------------
CONTENT_TESTS = r'''
local content = load_content()

check(type(content.Notes) == "table", "Notes is a table")
check(content.Total == 12, "Total states twelve")
check(#content.Notes == 12, "twelve notes are actually present")
check(#content.Notes == content.Total, "Total agrees with the array it describes")
check(#content.Levels == 3, "three levels are covered")

local seen = {}
local previous = ""
for index, note in ipairs(content.Notes) do
    local where = " (" .. tostring(note.Id) .. ")"
    check(type(note.Id) == "string" and string.match(note.Id, "^L[123]%-%d%d$") ~= nil,
        "id is L<level>-NN" .. where)
    check(seen[note.Id] == nil, "id is unique" .. where)
    seen[note.Id] = true
    check(note.Id > previous, "notes are sorted by id" .. where)
    previous = note.Id
    check(note.Level == tonumber(string.sub(note.Id, 2, 2)), "Level matches its id" .. where)
    check(type(note.Title) == "string" and #note.Title >= 6, "Title is present" .. where)
    check(type(note.Stamp) == "string" and #note.Stamp >= 6, "Stamp is present" .. where)

    local words = 0
    for _ in string.gmatch(note.Body, "%S+") do words += 1 end
    check(words >= 35 and words <= 60,
        "body is 35-60 words, got " .. tostring(words) .. where)

    -- A four-digit run reads as a year, and a year reads as a claim about the
    -- real world. The collection makes none.
    local joined = note.Title .. " " .. note.Stamp .. " " .. note.Body
    check(string.match(joined, "%d%d%d%d") == nil, "no year-like digits" .. where)
    check(string.match(note.Body, "^%s") == nil and string.match(note.Body, "%s$") == nil,
        "body has no stray edge whitespace" .. where)
end

for _, level in ipairs(content.Levels) do
    local block = content.ByLevel[level]
    check(type(block) == "table" and #block == 4, "level " .. level .. " has four notes")
    for _, note in ipairs(block) do
        check(note.Level == level, "ByLevel[" .. level .. "] holds only that level")
        local found = false
        for _, other in ipairs(content.Notes) do if other == note then found = true end end
        check(found, "ByLevel shares the identical row with Notes")
    end
end

print("Field Notes content: " .. checks .. " checks passed")
'''


# ---------------------------------------------------------------------------
# 2. service
# ---------------------------------------------------------------------------
SERVICE_HARNESS = r'''
local loaded = {}
local function makeContext()
    table.clear(FIRED)
    local ctx = {Now = 100, Warnings = {}, ComputeCalls = 0, Routes = {}, OnCompute = nil,
        Inventory = {true, "L2-01", ""}, InventoryError = false, HasInventory = true}
    table.clear(loaded)

    ctx.Workspace = node("Workspace", "Workspace")
    ctx.Storage = node("ReplicatedStorage", "ReplicatedStorage")
    ctx.ServerStorage = node("ServerStorage", "ServerStorage")
    node("ModuleScript", "ZyntraFieldNotes", ctx.Storage)
    node("ModuleScript", "UIStyle", ctx.Storage)

    ctx.Inv = node("BindableFunction", "ZyntraInventory", ctx.ServerStorage)
    ctx.Inv.Handler = function(action, player, level)
        ctx.LastInvoke = {Action = action, Player = player, Level = level}
        if ctx.InventoryError then error("datastore down") end
        return table.unpack(ctx.Inventory)
    end

    ctx.PlayerRemoving = signal()
    ctx.Pathfinding = {CreatePath = function()
        local path = {Status = Enum.PathStatus.NoPath, Waypoints = {}}
        function path:ComputeAsync(origin, target)
            ctx.ComputeCalls += 1
            if ctx.OnCompute then ctx.OnCompute(ctx.ComputeCalls) end
            if ctx.ComputeError then error("pathfinding refused") end
            local length = ctx.Routes[math.floor(target.X + 0.5)]
            if not length then
                self.Status = Enum.PathStatus.NoPath
                return
            end
            self.Status = Enum.PathStatus.Success
            self.Waypoints = {{Position = Vector3.new(0, 0, 0)},
                {Position = Vector3.new(length, 0, 0)}}
        end
        function path:GetWaypoints() return self.Waypoints end
        return path
    end}

    local services = {Players = {PlayerRemoving = ctx.PlayerRemoving},
        ReplicatedStorage = ctx.Storage, ServerStorage = ctx.ServerStorage,
        PathfindingService = ctx.Pathfinding}
    ctx.Game = {GetService = function(_, name)
        if name == "Workspace" then return ctx.Workspace end
        return assert(services[name], name)
    end}

    ctx.Task = {spawn = function(fn, ...)
        local thread = coroutine.create(fn)
        local ok, err = coroutine.resume(thread, ...)
        if not ok then error(err) end
    end}

    ctx.Player = node("Player", "Tester")
    ctx.Player.UserId = 4242
    ctx.Player.Character = node("Model", "Character", ctx.Workspace)
    ctx.Humanoid = node("Humanoid", "Humanoid", ctx.Player.Character)
    ctx.Humanoid.Health = 100
    ctx.Root = node("Part", "HumanoidRootPart", ctx.Player.Character)
    ctx.Root.Position = Vector3.new(300, 0, 0)
    ctx.Player:SetAttribute("InRound", true)

    -- The spawn pad and a level-2 world with four floors, each far enough from
    -- the pad to clear START_CLEARANCE. Route length is keyed off X.
    ctx.Start = node("Part", "ElevatorSpawn", ctx.Workspace)
    ctx.Start.Position = Vector3.new(0, 0, 0)
    ctx.World = node("Model", "Level 2 Generated World", ctx.Workspace)
    ctx.Floors = {}
    for index = 1, 4 do
        ctx.Floors[index] = floorPart(ctx.World, "Floor" .. index, index * 100, 0)
    end
    ctx.Workspace:SetAttribute("SelectedLevel", 2)

    function ctx:Start2()
        self.Workspace:SetAttribute("RoundLoadingState", "ready")
        self.Workspace:SetAttribute("RoundActive", true)
    end
    function ctx:Prop() return self.Folder and self.Folder.Children[1] or nil end
    function ctx:Prompt()
        local prop = self:Prop()
        if not prop then return nil end
        return prop:FindFirstChild("Board"):FindFirstChild("Read")
    end
    return ctx
end

local function boot(ctx)
    local game = ctx.Game
    local workspace = ctx.Workspace
    local task = ctx.Task
    local os = {clock = function() return ctx.Now end}
    local warn = function(...)
        local parts = {}
        for _, value in ipairs({...}) do table.insert(parts, tostring(value)) end
        table.insert(ctx.Warnings, table.concat(parts, " "))
    end
    local require = function(target)
        local name = target.Name
        if not loaded[name] then
            if name == "ZyntraFieldNotes" then loaded[name] = load_content()
            elseif name == "UIStyle" then loaded[name] = load_uistyle()
            else error("unexpected require " .. name) end
        end
        return loaded[name]
    end
'''

SERVICE_TESTS = r'''
end

local function fresh(prepare)
    local ctx = makeContext()
    if prepare then prepare(ctx) end
    boot(ctx)
    ctx.Folder = ctx.Workspace:FindFirstChild("FieldNotes")
    ctx.Remote = ctx.Storage:FindFirstChild("Remotes"):FindFirstChild("FieldNote")
    return ctx
end

-- ── instances the contract names ────────────────────────────────────────────
do
    local ctx = fresh()
    check(ctx.Folder ~= nil and ctx.Folder.ClassName == "Folder", "workspace.FieldNotes exists")
    check(ctx.Remote ~= nil and ctx.Remote.ClassName == "RemoteEvent", "Remotes.FieldNote exists")
    check(#ctx.Folder.Children == 0, "nothing is placed before a round starts")
    check(ctx.ComputeCalls == 0, "no pathfinding work outside a round")
end

-- ── one prop, at the median reachable candidate ─────────────────────────────
do
    local ctx = fresh()
    ctx.Routes = {[100] = 50, [200] = 900, [300] = 400, [400] = 120}
    ctx:Start2()
    check(#ctx.Folder.Children == 1, "exactly one prop is placed on a ready round")
    check(ctx.ComputeCalls == 4, "every candidate was actually routed")
    local prop = ctx:Prop()
    check(prop.Name == "Field Note", "the prop is the Field Note model")
    -- lengths sorted 50,120,400,900 -> ceil(4/2)=2 -> 120 -> the X=400 floor
    check(prop.PrimaryPart.CFrame.Position.X == 400, "median route wins, not shortest or longest")
    check(prop.PrimaryPart.CFrame.Position.Y == 0.1 + 3 / 2,
        "the board rests on the floor top plus the lift")
    check(#prop.Children == 2, "the prop is two parts")
end

do
    local ctx = fresh()
    ctx.Routes = {[100] = 10, [200] = 20, [300] = 30}
    ctx:Start2()
    -- three successes -> ceil(3/2) = 2 -> the middle one
    check(ctx:Prop().PrimaryPart.CFrame.Position.X == 200, "odd success count takes the middle")
end

do
    local ctx = fresh()
    ctx.Routes = {[100] = 7}
    ctx:Start2()
    check(ctx:Prop().PrimaryPart.CFrame.Position.X == 100, "a single success picks itself")
end

-- ── the prop itself ─────────────────────────────────────────────────────────
do
    local ctx = fresh()
    ctx.Routes = {[100] = 5}
    ctx:Start2()
    local prop = ctx:Prop()
    local board = prop:FindFirstChild("Board")
    local base = prop:FindFirstChild("Base")
    check(board and base, "board and base are both built")
    check(board.Anchored and base.Anchored, "neither part can fall")
    check(board.CanCollide == false and base.CanCollide == false,
        "the prop never blocks a corridor")
    check(board.CanQuery == true, "the board answers queries, so the prompt can hit it")
    check(board:FindFirstChildOfClass("PointLight") ~= nil, "it carries its own light")
    -- A generated level has no "front", so a single-sided sign is blank from
    -- wherever half the party arrives.
    for _, side in ipairs({"Front", "Back"}) do
        local face = board:FindFirstChild("Face" .. side)
        check(face ~= nil and face.Face == Enum.NormalId[side],
            "the sign is legible from the " .. side)
        local panel = face:FindFirstChildOfClass("Frame")
        check(panel ~= nil, side .. " has a styled panel")
        check(panel:FindFirstChildOfClass("UICorner") ~= nil,
            "UIStyle chrome was really applied to " .. side)
        check(panel:FindFirstChild("Title").Text == "FIELD\nNOTE",
            "the " .. side .. " says what it is")
    end
    local prompt = ctx:Prompt()
    check(prompt.ActionText == "READ NOTE", "the prompt reads READ NOTE")
    check(prompt.HoldDuration == 0.4, "it is a hold, not a tap")
    check(prompt.MaxActivationDistance == 8, "prompt range is eight studs")
    check(prompt.RequiresLineOfSight == false, "line of sight is not required")
end

-- ── candidates that are not floors ──────────────────────────────────────────
for _, case in ipairs({
    {Name = "small", Apply = function(p) p.Size = Vector3.new(3, 1, 30) end},
    {Name = "unanchored", Apply = function(p) p.Anchored = false end},
    {Name = "non-collidable", Apply = function(p) p.CanCollide = false end},
    {Name = "water", Apply = function(p) p.Material = Enum.Material.Water end},
    {Name = "tilted", Apply = function(p) p.CFrame = tiltedCF(p.Position) end},
    {Name = "invisible", Apply = function(p) p.Transparency = 1 end},
    {Name = "wedge", Apply = function(p) p.ClassName = "WedgePart" end},
    {Name = "cylinder", Apply = function(p) p.Shape = Enum.PartType.Cylinder end},
    {Name = "a folder", Apply = function(p) p.ClassName = "Folder" end},
}) do
    local ctx = fresh(function(inner)
        for index = 2, 4 do inner.Floors[index].Parent = nil end
        case.Apply(inner.Floors[1])
    end)
    ctx.Routes = {[100] = 5}
    ctx:Start2()
    check(#ctx.Folder.Children == 0, case.Name .. " is not a floor candidate")
    check(ctx.ComputeCalls == 0, "no route is even computed for " .. case.Name)
end

do
    local ctx = fresh(function(inner)
        -- Inside START_CLEARANCE of the pad: a note at spawn is not a discovery.
        for index = 1, 4 do inner.Floors[index].Position = Vector3.new(index * 5, -0.5, 0) end
    end)
    ctx.Routes = {[5] = 1, [10] = 2, [15] = 3, [20] = 4}
    ctx:Start2()
    check(#ctx.Folder.Children == 0, "candidates at the spawn pad are excluded")
    check(#ctx.Warnings == 1, "and the exclusion is reported once")
end

-- ── failure never becomes a retry ───────────────────────────────────────────
do
    local ctx = fresh()
    ctx.Routes = {}
    ctx:Start2()
    check(#ctx.Folder.Children == 0, "nothing pathable places nothing")
    check(#ctx.Warnings == 1, "and warns exactly once")
    local calls = ctx.ComputeCalls
    ctx.Workspace:SetAttribute("RoundLoadingState", "loading")
    ctx.Workspace:SetAttribute("RoundLoadingState", "ready")
    ctx.Workspace:SetAttribute("SelectedLevel", 2)
    check(ctx.ComputeCalls == calls, "a failed round never re-scans -- no retry loop")
    check(#ctx.Warnings == 1, "and never warns twice about the same round")
end

do
    local ctx = fresh()
    ctx.ComputeError = true
    ctx.Routes = {[100] = 5}
    ctx:Start2()
    check(#ctx.Folder.Children == 0, "a throwing ComputeAsync is survived, not propagated")
end

do
    local ctx = fresh(function(inner) inner.Start.Parent = nil end)
    ctx.Routes = {[100] = 5}
    ctx:Start2()
    check(#ctx.Folder.Children == 0, "no spawn marker means no placement")
end

do
    local ctx = fresh(function(inner) inner.World.Name = "Something Else" end)
    ctx.Routes = {[100] = 5}
    ctx:Start2()
    check(#ctx.Folder.Children == 0, "no level world means no placement")
end

do
    local ctx = fresh(function(inner) inner.Workspace:SetAttribute("SelectedLevel", 7) end)
    ctx.Routes = {[100] = 5}
    ctx:Start2()
    check(#ctx.Folder.Children == 0, "an unsupported level places nothing")
    ctx.Workspace:SetAttribute("SelectedLevel", 2)
    check(#ctx.Folder.Children == 1, "and the level becoming supported still works")
end

-- ── ceilings on the work done ───────────────────────────────────────────────
do
    local ctx = fresh(function(inner)
        for index = 5, 30 do
            inner.Floors[index] = floorPart(inner.World, "Floor" .. index, index * 100, 0)
        end
    end)
    ctx:Start2()
    check(ctx.ComputeCalls == 14, "at most fourteen routes are ever computed")
end

-- ── determinism ─────────────────────────────────────────────────────────────
do
    local positions = {}
    for attempt = 1, 2 do
        local ctx = fresh(function(inner)
            inner.World:SetAttribute("Level2_Seed", 4321)
            for index = 5, 20 do
                inner.Floors[index] = floorPart(inner.World, "Floor" .. index, index * 100, 0)
            end
        end)
        for index = 1, 20 do ctx.Routes[index * 100] = index * 13 end
        ctx:Start2()
        positions[attempt] = ctx:Prop().PrimaryPart.CFrame.Position.X
    end
    check(positions[1] == positions[2], "a pinned layout seed reproduces the same spot")
end

-- ── lifecycle ───────────────────────────────────────────────────────────────
do
    local ctx = fresh()
    ctx.Routes = {[100] = 5}
    ctx:Start2()
    check(#ctx.Folder.Children == 1, "placed")
    ctx.Workspace:SetAttribute("RoundActive", false)
    check(#ctx.Folder.Children == 0, "RoundActive false destroys the prop")
    ctx.Workspace:SetAttribute("RoundActive", true)
    check(#ctx.Folder.Children == 1, "the next round gets its own prop")
end

do
    local ctx = fresh()
    ctx.Routes = {[100] = 5}
    ctx:Start2()
    local first = ctx:Prop()
    ctx.Workspace:SetAttribute("RoundLoadingState", "loading")
    check(ctx:Prop() == first, "a loading state mid-round does NOT tear the prop down")
end

do
    local ctx = fresh()
    ctx.Routes = {[100] = 5}
    ctx:Start2()
    check(#ctx.Folder.Children == 1, "level 2 prop placed")
    -- the Level 2 -> Level 3 continuation: same round, new world
    ctx.World.Name = "Level 3 Generated World"
    ctx.Workspace:SetAttribute("SelectedLevel", 3)
    check(#ctx.Folder.Children == 1, "the continuation replaces rather than stacks")
    check(ctx.ComputeCalls > 4, "and the new leg really re-scanned")
end

do
    local ctx = fresh()
    ctx.Routes = {[100] = 5, [200] = 6, [300] = 7, [400] = 8}
    ctx.OnCompute = function(index)
        -- The round ends while the placement thread is between two routes.
        if index == 2 then ctx.Workspace:SetAttribute("RoundActive", false) end
    end
    ctx:Start2()
    check(#ctx.Folder.Children == 0, "a round that ends mid-scan places nothing")
    check(ctx.ComputeCalls == 2,
        "and ABANDONS the remaining routes rather than finishing a dead scan")
end

-- ── reading it ──────────────────────────────────────────────────────────────
local function readyToRead()
    local ctx = fresh()
    ctx.Routes = {[100] = 5}
    ctx:Start2()
    ctx.Root.Position = ctx:Prop().PrimaryPart.CFrame.Position
    table.clear(FIRED)
    return ctx
end

do
    local ctx = readyToRead()
    ctx:Prompt().Triggered:Fire(ctx.Player)
    check(#FIRED == 1, "a valid trigger answers the player")
    check(FIRED[1].Player == ctx.Player, "and only that player")
    check(FIRED[1].Args[1] == "discovered" and FIRED[1].Args[2] == "L2-01",
        "the reply carries the granted id")
    check(ctx.LastInvoke.Action == "DiscoverNote", "DiscoverNote is the op invoked")
    check(ctx.LastInvoke.Player == ctx.Player and ctx.LastInvoke.Level == 2,
        "invoked with the player and the LEVEL NUMBER")
end

do
    local ctx = readyToRead()
    ctx:Prompt().Triggered:Fire(ctx.Player)
    ctx.Now += 5
    ctx:Prompt().Triggered:Fire(ctx.Player)
    check(#FIRED == 2, "a repeat read is answered")
    check(FIRED[2].Args[1] == "alreadyLogged", "with alreadyLogged")
    check(FIRED[2].Args[2] == "L2-01", "naming what they already have")
    check(ctx:Prop() ~= nil, "and the prop stays for everyone else")
end

do
    local ctx = readyToRead()
    ctx:Prompt().Triggered:Fire(ctx.Player)
    ctx:Prompt().Triggered:Fire(ctx.Player)
    check(#FIRED == 1, "a second trigger inside the cooldown is dropped entirely")
    ctx.Now += 2.01
    ctx:Prompt().Triggered:Fire(ctx.Player)
    check(#FIRED == 2, "and allowed again once the cooldown passes")
end

do
    local ctx = readyToRead()
    ctx.Inventory = {false, nil, "Every note on this level is already in your collection", "complete"}
    ctx:Prompt().Triggered:Fire(ctx.Player)
    check(FIRED[1].Args[1] == "alreadyLogged", "a false grant is already-in-collection")
    check(FIRED[1].Args[2] == nil, "with no id to name")
end

do
    local ctx = readyToRead()
    ctx.Inventory = {false, nil, "That could not be saved. Try again."}
    ctx:Prompt().Triggered:Fire(ctx.Player)
    check(FIRED[1].Args[1] == "unavailable", "a failed save is not an already-owned note")
    ctx.Now += 3
    ctx.Inventory = {true, "L2-01", "saved"}
    ctx:Prompt().Triggered:Fire(ctx.Player)
    check(FIRED[2].Args[1] == "discovered", "a failed save can retry the same prop")
end

do
    local ctx = readyToRead()
    ctx.Inv.Parent = nil
    ctx:Prompt().Triggered:Fire(ctx.Player)
    check(FIRED[1].Args[1] == "unavailable", "no ZyntraInventory is reported as unavailable")
end

do
    local ctx = readyToRead()
    ctx.InventoryError = true
    ctx:Prompt().Triggered:Fire(ctx.Player)
    check(FIRED[1].Args[1] == "unavailable", "a throwing Invoke is reported, never propagated")
    check(#ctx.Warnings >= 1, "and logged")
end

for _, case in ipairs({
    {Name = "out of reach",
        Apply = function(ctx) ctx.Root.Position = Vector3.new(9999, 0, 0) end},
    {Name = "dead", Apply = function(ctx) ctx.Humanoid.Health = 0 end},
    {Name = "no humanoid", Apply = function(ctx) ctx.Humanoid.Parent = nil end},
    {Name = "no root", Apply = function(ctx) ctx.Root.Parent = nil end},
    {Name = "bodyless", Apply = function(ctx) ctx.Player.Character = nil end},
    {Name = "not in the round",
        Apply = function(ctx) ctx.Player:SetAttribute("InRound", false) end},
    {Name = "round over",
        Apply = function(ctx) ctx.Workspace.Attributes.RoundActive = false end},
}) do
    local ctx = readyToRead()
    case.Apply(ctx)
    ctx:Prompt().Triggered:Fire(ctx.Player)
    check(#FIRED == 0, "a trigger from a player who is " .. case.Name .. " grants nothing")
    check(ctx.LastInvoke == nil, "and never reaches the inventory: " .. case.Name)
end

do
    local ctx = readyToRead()
    local prompt = ctx:Prompt()
    ctx.Workspace:SetAttribute("RoundActive", false)
    ctx.Workspace.Attributes.RoundActive = true
    prompt.Triggered:Fire(ctx.Player)
    check(#FIRED == 0, "a prompt from a torn-down round cannot be revived")
end

do
    local ctx = readyToRead()
    ctx:Prompt().Triggered:Fire(ctx.Player)
    ctx.PlayerRemoving:Fire(ctx.Player)
    ctx.Now += 5
    table.clear(FIRED)
    ctx:Prompt().Triggered:Fire(ctx.Player)
    check(FIRED[1].Args[1] == "discovered", "a rejoin within the round reads again")
end

print("Field Notes service: " .. checks .. " checks passed")
'''


# ---------------------------------------------------------------------------
# 3. client
# ---------------------------------------------------------------------------
CLIENT_HARNESS = r'''
local loaded = {}
local function makeContext()
    table.clear(FIRED)
    table.clear(loaded)
    local ctx = {Now = 0, Timers = {}, Touch = false, Suppressed = 0}
    ctx.Storage = node("ReplicatedStorage", "ReplicatedStorage")
    node("ModuleScript", "UIStyle", ctx.Storage)
    node("ModuleScript", "ZyntraFieldNotes", ctx.Storage)
    node("ModuleScript", "UIDevice", ctx.Storage)
    local remotes = node("Folder", "Remotes", ctx.Storage)
    ctx.Remote = Instance.new("RemoteEvent")
    ctx.Remote.Name = "FieldNote"
    ctx.Remote.Parent = remotes

    ctx.Player = node("Player", "Tester")
    ctx.Gui = node("PlayerGui", "PlayerGui", ctx.Player)
    ctx.Player:SetAttribute("InRound", true)
    ctx.Changed = signal()

    ctx.Device = {
        Changed = ctx.Changed,
        Layout = function()
            if ctx.Touch then
                return {IsTouch = true,
                    Safe = {Left = 0, Top = 0, Right = 400, Bottom = 800},
                    ModalArea = {Left = 20, Top = 60, Right = 380, Bottom = 520, Fits = true},
                    Zones = {Controls = {Top = 560}}}
            end
            return {IsTouch = false,
                Safe = {Left = 0, Top = 0, Right = 1280, Bottom = 720},
                ModalArea = {Left = 0, Top = 0, Right = 1280, Bottom = 720, Fits = true},
                Zones = nil}
        end,
        LocalPosition = function(_, x, y) return UDim2.fromOffset(x, y) end,
        LocalOffset = function(_, x, y) return x, y end,
        SuppressTouchMovement = function() ctx.Suppressed += 1 end,
        SetEnabled = function(element, on) element.Active = on end,
    }

    local services = {Players = {LocalPlayer = ctx.Player}, ReplicatedStorage = ctx.Storage,
        TextService = textService()}
    ctx.Game = {GetService = function(_, name) return assert(services[name], name) end}

    ctx.Task = {delay = function(seconds, fn)
        table.insert(ctx.Timers, {At = ctx.Now + seconds, Fn = fn})
    end}
    function ctx:Advance(seconds)
        self.Now += seconds
        local due = {}
        for index = #self.Timers, 1, -1 do
            if self.Timers[index].At <= self.Now then
                table.insert(due, table.remove(self.Timers, index))
            end
        end
        for _, timer in ipairs(due) do timer.Fn() end
    end
    function ctx:Gui2() return self.Gui.Children[1] end
    function ctx:Card() return self:Gui2():FindFirstChild("FieldNoteCard") end
    function ctx:Caption() return self:Gui2():FindFirstChild("FieldNoteCaption") end
    return ctx
end

local function boot(ctx)
    local game = ctx.Game
    local task = ctx.Task
    local require = function(target)
        local name = target.Name
        if not loaded[name] then
            if name == "ZyntraFieldNotes" then loaded[name] = load_content()
            elseif name == "UIStyle" then loaded[name] = load_uistyle()
            elseif name == "UIDevice" then loaded[name] = ctx.Device
            else error("unexpected require " .. name) end
        end
        return loaded[name]
    end
'''

CLIENT_TESTS = r'''
end

local content = load_content()
local function fresh()
    local ctx = makeContext()
    boot(ctx)
    return ctx
end

do
    local ctx = fresh()
    local gui = ctx:Gui2()
    check(gui ~= nil and gui.ClassName == "ScreenGui", "a ScreenGui is created")
    check(gui.DisplayOrder == 60, "DisplayOrder 60: over the HUD, under exit and PARTY DOWN")
    check(gui.ResetOnSpawn == false, "it survives a respawn")
    check(ctx:Card().Visible == false, "the card starts closed")
    check(ctx:Caption().Visible == false, "the caption starts closed")
    check(ctx:Card().Active ~= true, "the card frame does not take input away from the world")
    check(ctx.Suppressed == 0, "movement is never suppressed")
    check(ctx.Player:GetAttribute("ScreenOwningModal") == nil, "no screen-owning modal flag")
    check(ctx.Player:GetAttribute("FieldNoteCardOpen") == nil, "no modal attribute at all")
end

do
    local ctx = fresh()
    local note = content.ByLevel[2][1]
    ctx.Remote.OnClientEvent:Fire("discovered", note.Id)
    local card = ctx:Card()
    check(card.Visible == true, "a discovery opens the card")
    check(card:FindFirstChild("Title").Text == note.Title, "with the note's real title")
    check(card:FindFirstChild("Stamp").Text == note.Stamp, "and its stamp")
    check(card:FindFirstChild("Body").Text == note.Body, "and its whole body")
    check(card:FindFirstChild("Body").TextWrapped == true, "the body wraps")
    check(card:FindFirstChild("Eyebrow").Text == "FIELD NOTE RECOVERED", "the card says why")
    check(ctx:Caption().Visible == false, "no caption alongside the card")
end

do
    local ctx = fresh()
    ctx.Remote.OnClientEvent:Fire("discovered", "L1-03")
    ctx:Card():FindFirstChild("Close").Activated:Fire()
    check(ctx:Card().Visible == false, "CLOSE closes it")
    ctx:Advance(20)
    check(ctx:Card().Visible == false, "and it stays closed")
end

do
    local ctx = fresh()
    ctx.Remote.OnClientEvent:Fire("discovered", "L1-03")
    ctx:Advance(13.9)
    check(ctx:Card().Visible == true, "the card is still up just before the auto-close")
    ctx:Advance(0.2)
    check(ctx:Card().Visible == false, "and closes itself at fourteen seconds")
end

do
    local ctx = fresh()
    ctx.Remote.OnClientEvent:Fire("discovered", "L1-01")
    ctx:Advance(13)
    ctx.Remote.OnClientEvent:Fire("discovered", "L1-02")
    ctx:Advance(1.5)
    check(ctx:Card().Visible == true, "the first card's timer cannot close the second")
    check(ctx:Card():FindFirstChild("Title").Text == content.ByLevel[1][2].Title,
        "the second note replaced the first")
    ctx:Advance(13)
    check(ctx:Card().Visible == false, "the second card closes on its own schedule")
end

for _, case in ipairs({
    {Event = "alreadyLogged", Text = "ALREADY IN YOUR COLLECTION"},
    {Event = "unavailable", Text = "FIELD NOTES UNAVAILABLE"},
}) do
    local ctx = fresh()
    ctx.Remote.OnClientEvent:Fire(case.Event)
    check(ctx:Caption().Visible == true, case.Event .. " shows a caption")
    check(ctx:Caption():FindFirstChild("Text").Text == case.Text,
        case.Event .. " says " .. case.Text)
    check(ctx:Card().Visible == false, case.Event .. " never opens the card")
    ctx:Advance(2.9)
    check(ctx:Caption().Visible == true, case.Event .. " caption holds for three seconds")
    ctx:Advance(0.2)
    check(ctx:Caption().Visible == false, case.Event .. " caption clears itself")
end

do
    local ctx = fresh()
    ctx.Remote.OnClientEvent:Fire("discovered", "L9-99")
    check(ctx:Card().Visible == false, "an unknown id never opens an empty card")
    check(ctx:Caption():FindFirstChild("Text").Text == "FIELD NOTE LOGGED",
        "and says something true instead")
end

do
    local ctx = fresh()
    ctx.Remote.OnClientEvent:Fire("discovered", "L3-01")
    ctx.Player:SetAttribute("InRound", false)
    check(ctx:Card().Visible == false, "leaving the round closes the card")
    ctx.Remote.OnClientEvent:Fire("alreadyLogged")
    ctx.Player:SetAttribute("InRound", false)
    check(ctx:Caption().Visible == false, "and the caption")
end

do
    local ctx = fresh()
    ctx.Touch = true
    ctx.Changed:Fire()
    ctx.Remote.OnClientEvent:Fire("discovered", "L2-02")
    local card = ctx:Card()
    local close = card:FindFirstChild("Close")
    check(close.Size.Y.Offset >= 44, "CLOSE meets the touch floor")
    check(card.Size.X.Offset <= 360, "the card fits inside the free lane on a phone")
    check(card.Position.X.Offset >= 20, "and sits inside the modal area, clear of the stick")
    check(card.Position.Y.Offset >= 60, "including its top edge")
    check(card.Position.Y.Offset + card.Size.Y.Offset <= 521,
        "and its bottom edge stays above the movement cluster")
end

do
    local ctx = fresh()
    ctx.Remote.OnClientEvent:Fire("discovered", "L2-04")
    local before = ctx:Card().Size.X.Offset
    ctx.Touch = true
    ctx.Changed:Fire()
    check(ctx:Card().Size.X.Offset ~= before, "a device change re-lays the open card out")
end

print("Field Notes client: " .. checks .. " checks passed")
'''


# ---------------------------------------------------------------------------
# 4. page
# ---------------------------------------------------------------------------
PAGE_HARNESS = r'''
local loaded = {}
local UIStyle = load_uistyle()
local content = load_content()

local COLORS = {bg = Color3.fromRGB(7, 11, 13), panel = Color3.fromRGB(14, 21, 24),
    card = Color3.fromRGB(20, 29, 33), card2 = Color3.fromRGB(25, 36, 40),
    line = Color3.fromRGB(75, 94, 83), text = Color3.fromRGB(231, 238, 233),
    muted = Color3.fromRGB(144, 164, 165), accent = Color3.fromRGB(68, 221, 196),
    accent2 = Color3.fromRGB(255, 203, 79), error = Color3.fromRGB(244, 95, 82)}

local function makeContext(discovered, unlocked)
    table.clear(loaded)
    local ctx = {Hooks = {}, Listeners = {}, Cards = {}, Scrolls = {}, Disconnects = 0}
    ctx.Storage = node("ReplicatedStorage", "ReplicatedStorage")
    node("ModuleScript", "ZyntraFieldNotes", ctx.Storage)
    local services = {ReplicatedStorage = ctx.Storage, TextService = textService()}
    ctx.Game = {GetService = function(_, name) return assert(services[name], name) end}
    ctx.Page = node("Frame", "NotesPage")
    ctx.Profile = {FieldNotes = {Discovered = discovered or {}, Count = 0,
        Total = 12, TitleUnlocked = unlocked == true}}

    ctx.Ctx = {
        UIStyle = UIStyle, COLORS = COLORS, pageName = "Notes",
        Config = {FieldNotes = {CompletionTitle = "FIELD ARCHIVIST"}},
        UIDevice = {SetEnabled = function(element, on) element.Active = on end},
        label = function(parent, text, size, position, textSize, color, font)
            local made = node("TextLabel", "Label", parent)
            made.Text = text or ""
            made.Size = size
            made.Position = position or UDim2.new()
            made.TextSize = textSize or 16
            made.TextColor3 = color or COLORS.text
            made.Font = font
            made.BackgroundTransparency = 1
            return made
        end,
        button = function(parent, text, size, position)
            local made = Instance.new("TextButton")
            made.Name = "Button"
            made.Text = text
            made.Size = size
            made.Position = position or UDim2.new()
            made.TextSize = 14
            made.Active = true
            made.Parent = parent
            return made
        end,
        corner = function(parent, radius)
            local made = node("UICorner", "UICorner", parent)
            made.CornerRadius = UDim.new(0, radius or 9)
            return made
        end,
        outline = function(parent, color, transparency, thickness)
            local made = node("UIStroke", "UIStroke", parent)
            made.Color = color
            made.Transparency = transparency or 0.28
            made.Thickness = thickness or 1
            return made
        end,
        action = function() end,
        profile = function() return ctx.Profile end,
        onProfile = function(fn)
            table.insert(ctx.Listeners, fn)
            return function() ctx.Disconnects += 1 end
        end,
        refreshProfile = function() end,
        showStatus = function() end,
        registerLayoutHook = function(fn) table.insert(ctx.Hooks, fn) end,
        isVisible = function() return true end,
        contract = {
            scroll = function(page, scroll) table.insert(ctx.Scrolls, page .. "|" .. scroll.Name) end,
            card = function(page, key, card, action)
                table.insert(ctx.Cards, {Page = page, Key = key, Card = card, Action = action})
            end,
        },
    }
    function ctx:Fit(width, height, compact, touch)
        local fit = {Width = width, Height = height, ContentWidth = width,
            ContentHeight = height, Compact = compact == true, Touch = touch == true,
            Tap = touch and 44 or 30, TabHeight = 34}
        for _, hook in ipairs(self.Hooks) do hook(fit) end
        return fit
    end
    function ctx:Row(id) return self.Page:FindFirstChild("NotesScroll")
        :FindFirstChild("NotesGrid"):FindFirstChild("Note" .. id) end
    function ctx:Header() return self.Page:FindFirstChild("NotesHeader") end
    function ctx:Detail() return self.Page:FindFirstChild("NotesScroll"):FindFirstChild("NoteDetail") end
    function ctx:Grid() return self.Page:FindFirstChild("NotesScroll"):FindFirstChild("NotesGrid") end
    return ctx
end

local function boot(ctx)
    local game = ctx.Game
    local require = function(target)
        local name = target.Name
        if not loaded[name] then
            if name == "ZyntraFieldNotes" then loaded[name] = content
            else error("unexpected require " .. name) end
        end
        return loaded[name]
    end
'''

PAGE_TESTS = r'''
end

local function fresh(discovered, unlocked)
    local ctx = makeContext(discovered, unlocked)
    local Page = boot(ctx)
    ctx.Handle = Page.mount(ctx.Page, ctx.Ctx)
    return ctx
end

local function labelText(parent, text)
    for _, child in ipairs(parent.Children) do
        if child.ClassName == "TextLabel" and child.Text == text then return child end
    end
    return nil
end
local function findProgress(ctx)
    for _, child in ipairs(ctx:Header().Children) do
        if child.ClassName == "TextLabel" and string.find(tostring(child.Text), "RECOVERED") then
            return child
        end
    end
    return nil
end
local function findTitleLine(ctx)
    for _, child in ipairs(ctx:Header().Children) do
        if child.ClassName == "TextLabel" and
            (string.find(tostring(child.Text), "TITLE:") or string.find(tostring(child.Text), "Recover")) then
            return child
        end
    end
    return nil
end

do
    local ctx = fresh()
    check(type(ctx.Handle.refresh) == "function", "mount returns a refresh")
    check(type(ctx.Handle.destroy) == "function", "mount returns a destroy")
    check(ctx:Header() ~= nil, "the header is drawn")
    check(labelText(ctx:Header(), "ZYNTRA // ARCHIVE") ~= nil, "eyebrow reads ZYNTRA // ARCHIVE")
    check(labelText(ctx:Header(), "FIELD NOTES") ~= nil, "title reads FIELD NOTES")
    check(findProgress(ctx).Text == "0 / 12 RECOVERED", "progress starts at zero of twelve")
    check(ctx:Header():FindFirstChild("ProgressTrack") ~= nil, "there is a track")
    check(ctx:Header():FindFirstChild("ProgressTrack"):FindFirstChild("ProgressFill") ~= nil,
        "and a fill inside it")
    check(#ctx.Scrolls == 1 and ctx.Scrolls[1] == "Notes|NotesScroll",
        "the page registers exactly one scroll with the terminal contract")
    check(#ctx.Cards == 12, "all twelve rows are registered as contract cards")
    check(#ctx.Listeners == 1, "the page subscribes to profile pushes once")
end

do
    local ctx = fresh()
    for _, note in ipairs(content.Notes) do
        local row = ctx:Row(note.Id)
        check(row ~= nil, "a card exists for " .. note.Id)
    end
    for _, level in ipairs({1, 2, 3}) do
        check(ctx:Grid():FindFirstChild("Level" .. level .. "Header") ~= nil,
            "there is a LEVEL " .. level .. " group header")
    end
    local keys = {}
    for _, entry in ipairs(ctx.Cards) do
        check(entry.Page == "Notes", "contract card is filed under Notes")
        check(keys[entry.Key] == nil, "contract key " .. entry.Key .. " is registered once")
        keys[entry.Key] = true
    end
end

do
    local ctx = fresh()
    local row = ctx:Row("L1-01")
    local open = row:FindFirstChild("Open")
    check(open.Text == "NOT YET FOUND", "an undiscovered row carries the NOT YET FOUND caption")
    check(open.Active == false, "and is taken out of the input stack")
    check(labelText(row, "LEVEL 1") ~= nil, "it shows the level it lives on instead of a title")
    check(labelText(row, content.ByLevel[1][1].Title) == nil, "it never leaks the real title")
    check(labelText(row, content.ByLevel[1][1].Stamp) == nil, "nor the stamp")
end

do
    local ctx = fresh({["L1-01"] = true, ["L2-03"] = true, ["L3-04"] = true})
    check(findProgress(ctx).Text == "3 / 12 RECOVERED", "progress counts what is owned")
    local fill = ctx:Header():FindFirstChild("ProgressTrack"):FindFirstChild("ProgressFill")
    check(math.abs(fill.Size.X.Scale - 3 / 12) < 0.0001, "the fill matches the fraction")
    local row = ctx:Row("L2-03")
    local note = content.ByLevel[2][3]
    check(labelText(row, note.Title) ~= nil, "a discovered row shows its title")
    check(labelText(row, note.Stamp) ~= nil, "and its stamp")
    check(row:FindFirstChild("Open").Text == "READ", "and offers READ")
    check(row:FindFirstChild("Open").Active == true, "which is reachable")
    local preview = nil
    for _, child in ipairs(row.Children) do
        if child.ClassName == "TextLabel" and child.Text ~= note.Title and child.Text ~= note.Stamp then
            preview = child
        end
    end
    check(preview ~= nil and #preview.Text > 0, "and a first line of the body")
    check(#preview.Text < #note.Body, "which is shorter than the whole body")
end

do
    local ctx = fresh({["L3-02"] = true})
    ctx:Fit(900, 500, false, false)
    local note = content.ByLevel[3][2]
    check(ctx:Detail().Visible == false, "the detail view starts closed")
    ctx:Row("L3-02"):FindFirstChild("Open").Activated:Fire()
    check(ctx:Detail().Visible == true, "READ opens the detail view")
    check(ctx:Grid().Visible == false, "and the grid stands down")
    local panel = ctx:Detail():FindFirstChild("DetailPanel")
    check(labelText(panel, note.Body) ~= nil, "the detail shows the whole body")
    check(labelText(panel, note.Title) ~= nil, "with its title")
    check(labelText(panel, note.Stamp) ~= nil, "and its stamp")
    local back = ctx:Detail():FindFirstChild("Back")
    check(back ~= nil and back.Text == "BACK", "there is a BACK control")
    back.Activated:Fire()
    check(ctx:Detail().Visible == false, "BACK closes the detail")
    check(ctx:Grid().Visible == true, "and brings the grid back")
end

do
    local ctx = fresh()
    ctx:Fit(900, 500, false, false)
    ctx:Row("L1-02"):FindFirstChild("Open").Activated:Fire()
    check(ctx:Detail().Visible == false, "an undiscovered row cannot open the detail")
end

do
    local ctx = fresh()
    check(string.find(findTitleLine(ctx).Text, "FIELD ARCHIVIST") ~= nil,
        "the locked line names the title on offer")
    check(string.find(findTitleLine(ctx).Text, "TITLE:") == nil, "and does not claim it")
    local owned = fresh(nil, true)
    check(findTitleLine(owned).Text == "TITLE: FIELD ARCHIVIST", "the unlocked line awards it")
end

do
    local ctx = fresh()
    ctx.Ctx.Config = {FieldNotes = {CompletionTitle = "ARCHIVIST OF RECORD"}}
    local other = makeContext()
    other.Ctx.Config = {FieldNotes = {CompletionTitle = "ARCHIVIST OF RECORD"}}
    local Page = boot(other)
    other.Handle = Page.mount(other.Page, other.Ctx)
    check(string.find(findTitleLine(other).Text, "ARCHIVIST OF RECORD") ~= nil,
        "the completion title comes from ZyntraConfig when it is there")
end

-- ── fit tiers ───────────────────────────────────────────────────────────────
for _, height in ipairs({90, 110, 145}) do
    local ctx = fresh()
    ctx:Fit(520, height, true, true)
    local scroll = ctx.Page:FindFirstChild("NotesScroll")
    check(scroll.Position.Y.Offset + scroll.Size.Y.Offset <= height,
        "short landscape notes remain within the page")
    check(scroll.Size.Y.Offset >= 44, "short notes viewport holds a touch target")
end

for _, case in ipairs({
    {Name = "phone", Width = 300, Compact = true, Touch = true, Columns = 1},
    {Name = "tablet", Width = 700, Compact = false, Touch = true, Columns = 2},
    {Name = "pointer", Width = 900, Compact = false, Touch = false, Columns = 3},
}) do
    local ctx = fresh()
    ctx:Fit(case.Width, 520, case.Compact, case.Touch)
    local first = ctx:Row("L1-01")
    local columns = 0
    for _, note in ipairs(content.ByLevel[1]) do
        local row = ctx:Row(note.Id)
        if row.Position.Y.Offset == first.Position.Y.Offset then columns += 1 end
    end
    check(columns == case.Columns,
        case.Name .. " lays the grid out in " .. case.Columns .. " column(s)")
    for _, note in ipairs(content.Notes) do
        local row = ctx:Row(note.Id)
        local open = row:FindFirstChild("Open")
        check(open.Size.Y.Offset >= (case.Touch and 44 or 30),
            case.Name .. " keeps the action at the tap floor")
        check(row.Size.X.Offset >= 140, case.Name .. " keeps a card readable")
        check(row.Position.X.Offset + row.Size.X.Offset <= case.Width,
            case.Name .. " keeps every card inside the content width")
    end
    local scroll = ctx.Page:FindFirstChild("NotesScroll")
    check(scroll.CanvasSize.Y.Offset > 0, case.Name .. " gives the scroll a real canvas")
end

do
    -- A narrow pointer terminal must still narrow, tier or no tier.
    local ctx = fresh()
    ctx:Fit(300, 520, false, false)
    local first = ctx:Row("L1-01")
    local columns = 0
    for _, note in ipairs(content.ByLevel[1]) do
        if ctx:Row(note.Id).Position.Y.Offset == first.Position.Y.Offset then columns += 1 end
    end
    check(columns < 3, "a narrow pointer viewport drops columns rather than shrink the card")
end

do
    local ctx = fresh()
    ctx:Fit(900, 500, false, false)
    for _, child in ipairs(ctx:Grid():GetDescendants()) do
        if child.ClassName == "TextLabel" or child.ClassName == "TextButton" then
            check((child.TextSize or 12) >= 11, "no type below 11px in the grid")
            check(string.find(tostring(child.Text), "%[") == nil, "no key glyphs on the page")
        end
    end
end

-- ── refresh and teardown ────────────────────────────────────────────────────
do
    local ctx = fresh()
    check(ctx:Row("L1-01"):FindFirstChild("Open").Text == "NOT YET FOUND", "starts unowned")
    ctx.Profile.FieldNotes.Discovered["L1-01"] = true
    ctx.Listeners[1](ctx.Profile)
    check(ctx:Row("L1-01"):FindFirstChild("Open").Text == "READ", "a profile push updates the row")
    check(findProgress(ctx).Text == "1 / 12 RECOVERED", "and the progress line")
    ctx.Profile.FieldNotes.Discovered["L2-01"] = true
    ctx.Handle.refresh()
    check(findProgress(ctx).Text == "2 / 12 RECOVERED", "refresh() re-reads the profile")
end

do
    local ctx = fresh()
    ctx.Handle.destroy()
    check(ctx.Disconnects == 1, "destroy drops the profile subscription")
    check(ctx.Page:FindFirstChild("NotesHeader") == nil, "and takes the header down")
    check(ctx.Page:FindFirstChild("NotesScroll") == nil, "and the scroll")
    ctx.Handle.refresh()
    check(true, "refresh after destroy is a no-op rather than an error")
end

do
    local ctx = makeContext()
    ctx.Storage:FindFirstChild("ZyntraFieldNotes").Parent = nil
    local Page = boot(ctx)
    local handle = Page.mount(ctx.Page, ctx.Ctx)
    check(type(handle.destroy) == "function", "a missing content module still returns a handle")
    check(labelText(ctx.Page, "FIELD NOTES UNAVAILABLE") ~= nil, "and says so on the page")
end

do
    -- ZyntraStore pcalls its own UIStyle require and hands over nil on failure.
    local ctx = makeContext()
    ctx.Ctx.UIStyle = nil
    local Page = boot(ctx)
    local handle = Page.mount(ctx.Page, ctx.Ctx)
    check(handle ~= nil, "a nil UIStyle still mounts the page")
    check(ctx:Row("L2-02") ~= nil, "and still draws every row")
end

do
    local ctx = makeContext()
    ctx.Ctx.contract = nil
    ctx.Ctx.registerLayoutHook = nil
    local Page = boot(ctx)
    local handle = Page.mount(ctx.Page, ctx.Ctx)
    check(handle ~= nil, "an older terminal without contract/layout hooks still mounts")
    check(ctx.Page:FindFirstChild("NotesScroll").ScrollingEnabled == true,
        "and the scroll is still scrollable")
end

print("Field Notes page: " .. checks .. " checks passed")
'''


def build_programs() -> dict:
    content_loader = loader("content", CONTENT)
    uistyle_loader = loader("uistyle", UISTYLE)
    return {
        "content": LIB + content_loader + CONTENT_TESTS,
        "service": (LIB + content_loader + uistyle_loader + SERVICE_HARNESS
                    + read(SERVICE) + SERVICE_TESTS),
        "client": (LIB + content_loader + uistyle_loader + CLIENT_HARNESS
                   + read(CLIENT) + CLIENT_TESTS),
        "page": (LIB + content_loader + uistyle_loader + PAGE_HARNESS
                 + read(PAGE) + PAGE_TESTS),
    }


def main() -> None:
    binary = os.environ.get("LUAU_BIN") or shutil.which("luau")
    if not binary:
        raise SystemExit("Set LUAU_BIN; no tests executed.")
    total = 0
    with tempfile.TemporaryDirectory(prefix="field-notes-") as directory:
        for name, program in build_programs().items():
            path = Path(directory) / ("field_notes_%s.luau" % name)
            path.write_text(program, encoding="utf-8")
            done = subprocess.run([binary, str(path)], capture_output=True, text=True,
                                  timeout=60)
            if done.stdout:
                print(done.stdout.rstrip())
            if done.returncode != 0:
                print(done.stderr.rstrip())
                raise SystemExit("Field Notes %s suite FAILED" % name)
            found = re.search(r"(\d+) checks passed", done.stdout)
            total += int(found.group(1)) if found else 0
    print("Field Notes: %d checks passed (real Lua sources, offline Luau)" % total)


if __name__ == "__main__":
    main()
