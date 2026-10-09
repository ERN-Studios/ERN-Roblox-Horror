"""Run the whole RouteMarkerService in offline Luau under a fake DataModel.

Mocks only the engine boundary this Script touches: instances and attributes,
the downward floor raycast, ServerStorage.ZyntraInventory, the RemoteEvent and
the server clock. The placement rules, the geometry and the lifecycle are the
real source. Vector3/CFrame are real maths (Roblox's are too); Color3 is a plain
value with no arithmetic, exactly like the engine's.

Rendering, replication and ProximityPrompt-free visibility still need Studio.
Set LUAU_BIN to an official Luau interpreter.
"""

import os
from pathlib import Path
import shutil
import subprocess
import tempfile

ROOT = Path(__file__).resolve().parents[2]
SOURCE = ROOT / "ServerScriptService/RouteMarkerService.Script.lua"

HARNESS = r'''
local checks = 0
local function check(value, message) assert(value, message); checks += 1 end
local function same(value, wanted, message)
    checks += 1
    assert(value == wanted, message .. ": expected " .. tostring(wanted) .. ", got " .. tostring(value))
end
local function near(value, wanted, message)
    checks += 1
    assert(type(value) == "number" and math.abs(value - wanted) < 1e-4,
        message .. ": expected " .. tostring(wanted) .. ", got " .. tostring(value))
end
local function signal()
    local listeners = {}
    return {
        Connect = function(_, fn) table.insert(listeners, fn); return {Disconnect = function() end} end,
        Fire = function(_, ...) for _, fn in ipairs(listeners) do fn(...) end end,
    }
end

-- Vector3 / CFrame carry real arithmetic; Color3 deliberately carries none.
local Vector3, vectorMeta = {}, {}
function Vector3.new(x, y, z)
    return setmetatable({Kind = "Vector3", X = x, Y = y, Z = z}, vectorMeta)
end
vectorMeta.__add = function(a, b) return Vector3.new(a.X + b.X, a.Y + b.Y, a.Z + b.Z) end
vectorMeta.__sub = function(a, b) return Vector3.new(a.X - b.X, a.Y - b.Y, a.Z - b.Z) end
vectorMeta.__mul = function(a, b) return Vector3.new(a.X * b, a.Y * b, a.Z * b) end
vectorMeta.__index = function(a, key)
    local magnitude = math.sqrt(a.X * a.X + a.Y * a.Y + a.Z * a.Z)
    if key == "Magnitude" then return magnitude end
    if key == "Unit" then return Vector3.new(a.X / magnitude, a.Y / magnitude, a.Z / magnitude) end
    return nil
end
local function dot(a, b) return a.X * b.X + a.Y * b.Y + a.Z * b.Z end
local CFrame = {}
function CFrame.new(position, lookAt)
    return {Kind = "CFrame", Position = position, LookVector = (lookAt - position).Unit}
end
local Color3 = {fromRGB = function(r, g, b) return {Kind = "Color3", R = r, G = g, B = b} end}
local UDim2 = {
    fromOffset = function(x, y) return {Kind = "UDim2", X = x, Y = y, Scale = false} end,
    fromScale = function(x, y) return {Kind = "UDim2", X = x, Y = y, Scale = true} end,
}
local Enum = {
    Material = {SmoothPlastic = "SmoothPlastic", Neon = "Neon"},
    SurfaceType = {Smooth = "Smooth"},
    Font = {Code = "Code"},
    RaycastFilterType = {Exclude = "Exclude", Include = "Include"},
}
local RaycastParams = {new = function() return {} end}

-- One flat registry of every instance ever created; children are whatever
-- currently points at you through Parent, which is what Destroy really changes.
local registry = {}
local nodeMethods, nodeMeta = {}, {}
nodeMeta.__index = function(self, key)
    local method = nodeMethods[key]
    if method ~= nil then return method end
    return nodeMethods.FindFirstChild(self, key)
end
local function node(class, name, parent)
    local value = setmetatable({ClassName = class, Name = name or class, Parent = parent,
        Attributes = {}, AttributeSignals = {}}, nodeMeta)
    table.insert(registry, value)
    return value
end
function nodeMethods:IsA(class) return self.ClassName == class
    or (class == "BasePart" and (self.ClassName == "Part" or self.ClassName == "MeshPart")) end
-- rawget throughout: an unset property reads as nil through __index, and __index
-- itself looks children up, so a plain `candidate.Parent` here would recurse.
function nodeMethods:GetChildren()
    local result = {}
    for _, candidate in ipairs(registry) do
        if rawget(candidate, "Parent") == self then table.insert(result, candidate) end
    end
    return result
end
function nodeMethods:FindFirstChild(name)
    for _, candidate in ipairs(registry) do
        if rawget(candidate, "Parent") == self and rawget(candidate, "Name") == name then
            return candidate
        end
    end
    return nil
end
function nodeMethods:WaitForChild(name) return self:FindFirstChild(name) end
function nodeMethods:FindFirstChildOfClass(class)
    for _, candidate in ipairs(registry) do
        if rawget(candidate, "Parent") == self and rawget(candidate, "ClassName") == class then
            return candidate
        end
    end
    return nil
end
function nodeMethods:Destroy()
    for _, child in ipairs(self:GetChildren()) do child:Destroy() end
    self.Parent = nil
    self.Destroyed = true
end
function nodeMethods:ClearAllChildren()
    for _, child in ipairs(self:GetChildren()) do child:Destroy() end
end
function nodeMethods:GetAttribute(key) return self.Attributes[key] end
function nodeMethods:SetAttribute(key, value)
    if self.Attributes[key] == value then return end
    self.Attributes[key] = value
    local changed = self.AttributeSignals[key]
    if changed then changed:Fire() end
end
function nodeMethods:GetAttributeChangedSignal(key)
    self.AttributeSignals[key] = self.AttributeSignals[key] or signal()
    return self.AttributeSignals[key]
end

local function context()
    local ctx = {Now = 500, Replies = {}, Consumes = {}, ConsumeResult = true,
        FloorY = 0, Rays = {}}
    ctx.Workspace = node("Workspace", "Workspace")
    function ctx.Workspace:GetServerTimeNow() return ctx.Now + 10000 end
    function ctx.Workspace:Raycast(origin, direction, params)
        table.insert(ctx.Rays, {Origin = origin, Direction = direction, Params = params})
        if ctx.FloorY == nil then return nil end
        return {Position = Vector3.new(origin.X, ctx.FloorY, origin.Z)}
    end
    ctx.Workspace:SetAttribute("RoundActive", true)
    ctx.Workspace:SetAttribute("RoundLoadingState", "ready")

    ctx.Players = node("Players", "Players")
    ctx.Players.PlayerAdded = signal()
    ctx.Players.PlayerRemoving = signal()
    ctx.Roster = {}
    function ctx.Players:GetPlayers()
        local copy = {}
        for _, player in ipairs(ctx.Roster) do table.insert(copy, player) end
        return copy
    end
    function ctx:AddPlayer(name, userId, position, facing)
        local player = node("Player", name, ctx.Players)
        player.UserId = userId
        player:SetAttribute("InRound", true)
        local character = node("Model", name, ctx.Workspace)
        local root = node("Part", "HumanoidRootPart", character)
        root.Position = position or Vector3.new(0, 5, 0)
        root.CFrame = {Kind = "CFrame", Position = root.Position,
            LookVector = facing or Vector3.new(0, 0, -1)}
        local humanoid = node("Humanoid", "Humanoid", character)
        humanoid.Health = 100
        player.Character = character
        table.insert(ctx.Roster, player)
        ctx.Players.PlayerAdded:Fire(player)
        return player, character, root, humanoid
    end

    ctx.ReplicatedStorage = node("ReplicatedStorage", "ReplicatedStorage")
    ctx.Remotes = node("Folder", "Remotes", ctx.ReplicatedStorage)
    ctx.Config = node("ModuleScript", "ZyntraConfig", ctx.ReplicatedStorage)
    ctx.Config.Value = {Items = {RouteMarker = {MaxActive = 3, PackSize = 3}}}

    ctx.ServerStorage = node("ServerStorage", "ServerStorage")
    ctx.Inventory = node("BindableFunction", "ZyntraInventory", ctx.ServerStorage)
    function ctx.Inventory:Invoke(action, player, key, amount)
        table.insert(ctx.Consumes, {Action = action, Player = player, Key = key, Amount = amount})
        if ctx.ConsumeError then error("inventory exploded") end
        if ctx.ConsumeResult == true then return true, "ok" end
        return false, "You have no route markers"
    end

    local services = {Players = ctx.Players, ReplicatedStorage = ctx.ReplicatedStorage,
        ServerStorage = ctx.ServerStorage}
    ctx.Game = {GetService = function(_, name) return assert(services[name], name) end}
    function ctx:Advance(seconds) self.Now += seconds end
    function ctx:Folder() return self.Workspace:FindFirstChild("RouteMarkers") end
    function ctx:Markers()
        local folder = self:Folder()
        return folder and folder:GetChildren() or {}
    end
    function ctx:Place(player, ...)
        ctx.Remote.OnServerEvent:Fire(player, ...)
        return ctx.Replies[#ctx.Replies]
    end
    return ctx
end

local function boot(ctx)
    local game, workspace = ctx.Game, ctx.Workspace
    local os = {clock = function() return ctx.Now end}
    local require = function(module) return module and module.Value or nil end
    local Instance = {new = function(class)
        local created = node(class, class, nil)
        if class == "RemoteEvent" then
            created.OnServerEvent = signal()
            function created:FireClient(player, kind, payload)
                table.insert(ctx.Replies, {Player = player, Kind = kind, Payload = payload})
            end
        end
        return created
    end}
'''

TESTS = r'''
    ctx.Remote = ctx.Remotes:FindFirstChild("RouteMarker")
end
local function fresh()
    local ctx = context()
    boot(ctx)
    return ctx
end

-- --------------------------------------------------------------- remote setup
do
    local ctx = fresh()
    check(ctx.Remote ~= nil, "the service creates ReplicatedStorage.Remotes.RouteMarker")
    same(ctx.Remote.ClassName, "RemoteEvent", "RouteMarker is a RemoteEvent")
end
do
    local ctx = context()
    local impostor = node("Folder", "RouteMarker", ctx.Remotes)
    boot(ctx)
    same(ctx.Remote.ClassName, "RemoteEvent", "a wrongly classed RouteMarker is replaced")
    same(impostor.Parent, nil, "the replaced instance is destroyed")
end

-- ------------------------------------------------------------- every refusal
local refusals = {
    {Reason = "NotInRound", Apply = function(ctx, p) p:SetAttribute("InRound", false) end},
    {Reason = "NotInRound", Apply = function(ctx, p) p:SetAttribute("Escaped", true) end},
    {Reason = "NotInRound", Apply = function(ctx, p) p:SetAttribute("Level2_ExitTransition", true) end},
    {Reason = "NotInRound", Apply = function(ctx) ctx.Workspace:SetAttribute("RoundActive", false) end},
    {Reason = "NotInRound", Apply = function(ctx) ctx.Workspace:SetAttribute("RoundLoadingState", "loading") end},
    {Reason = "NotInRound", Apply = function(ctx) ctx.Workspace:SetAttribute("RoundLoadingState", "failed") end},
    {Reason = "NoCharacter", Apply = function(ctx, p) p.Character = nil end},
    {Reason = "NoCharacter", Apply = function(ctx, p) p.Character:FindFirstChildOfClass("Humanoid"):Destroy() end},
    {Reason = "NoCharacter", Apply = function(ctx, p) p.Character:FindFirstChildOfClass("Humanoid").Health = 0 end},
    {Reason = "NoCharacter", Apply = function(ctx, p) p.Character:FindFirstChild("HumanoidRootPart"):Destroy() end},
    {Reason = "Hiding", Apply = function(ctx, p) p:SetAttribute("Level3_Hiding", true) end},
    {Reason = "Hiding", Apply = function(ctx, p) p.Character:SetAttribute("Level2_ForcedSliding", true) end},
    {Reason = "Hiding", Apply = function(ctx, p) p.Character:SetAttribute("Level2_RagdollServerActive", true) end},
}
for index, case in ipairs(refusals) do
    local ctx = fresh()
    local player = ctx:AddPlayer("Placer", 101)
    case.Apply(ctx, player)
    local reply = ctx:Place(player, "place")
    same(reply.Kind, "refused", "case " .. index .. " is refused")
    same(reply.Payload, case.Reason, "case " .. index .. " refusal reason")
    same(#ctx:Markers(), 0, "case " .. index .. " places nothing")
    same(#ctx.Consumes, 0, "case " .. index .. " never reaches the durable spend")
end

-- ------------------------------------------------------------ the happy path
do
    local ctx = fresh()
    local player, character, root = ctx:AddPlayer("Placer", 101,
        Vector3.new(10, 5, -20), Vector3.new(0, 0, -1))
    ctx.FloorY = 1.5
    local reply = ctx:Place(player, "place")
    same(reply.Kind, "placed", "a valid request places a marker")
    same(reply.Payload, 1, "the reply carries the active count")
    same(reply.Player, player, "the reply goes to the requesting player")
    same(player:GetAttribute("RouteMarkersActive"), 1, "RouteMarkersActive published")

    same(#ctx.Consumes, 1, "exactly one durable consume per placement")
    local spend = ctx.Consumes[1]
    same(spend.Action, "Consume", "the inventory action is Consume")
    same(spend.Player, player, "the spend is charged to the placer")
    same(spend.Key, "RouteMarker", "the spend names the RouteMarker item")
    same(spend.Amount, 1, "one marker per placement")

    local markers = ctx:Markers()
    same(#markers, 1, "one marker under workspace.RouteMarkers")
    local marker = markers[1]
    same(marker.ClassName, "Model", "the marker is a Model")
    same(marker.Name, "RouteMarker", "the marker is named RouteMarker")
    same(marker:GetAttribute("Owner"), 101, "Owner holds the placer UserId")
    same(marker:GetAttribute("PlacedAt"), ctx.Workspace:GetServerTimeNow(), "PlacedAt is server time")
    same(marker:GetAttribute("Serial"), 1, "the first marker is serial 1")

    local plate = marker:FindFirstChild("Base")
    check(plate ~= nil, "the marker has a base plate")
    same(marker.PrimaryPart, plate, "the plate is the model's PrimaryPart")
    near(plate.CFrame.Position.X, 10, "marker X is the placer's own X")
    near(plate.CFrame.Position.Z, -22.5, "marker sits 2.5 studs along the look vector")
    near(plate.CFrame.Position.Y, 1.65, "marker snaps 0.15 studs above the hit floor")
    near(plate.CFrame.LookVector.Z, -1, "marker yaw follows the root look vector")
    near(plate.CFrame.LookVector.Y, 0, "marker yaw is flat")

    local parts = 0
    for _, child in ipairs(marker:GetChildren()) do
        if child.ClassName == "Part" then
            parts += 1
            same(child.Anchored, true, child.Name .. " is anchored")
            same(child.CanCollide, false, child.Name .. " cannot collide")
            same(child.CanQuery, false, child.Name .. " is invisible to other raycasts")
            same(child.CanTouch, false, child.Name .. " raises no touch events")
            check(child.CFrame.Position.Y >= 1.65, child.Name .. " sits at or above the plate")
        end
    end
    same(parts, 3, "the arrow is three parts")

    local left = marker:FindFirstChild("HeadLeft")
    local right = marker:FindFirstChild("HeadRight")
    check(left ~= nil and right ~= nil, "the head is a two-armed chevron")
    same(left.Material, Enum.Material.Neon, "the chevron is neon")
    same(right.Material, Enum.Material.Neon, "both arms are neon")
    same(plate.Material, Enum.Material.SmoothPlastic, "the plate is not neon")
    same(left.Color.R, 68, "the chevron uses the store accent red")
    same(left.Color.G, 221, "the chevron uses the store accent green")
    same(left.Color.B, 196, "the chevron uses the store accent blue")
    local forward = Vector3.new(0, 0, -1)
    check(dot(left.CFrame.LookVector, forward) > 0.5, "the left arm leans forward")
    check(dot(right.CFrame.LookVector, forward) > 0.5, "the right arm leans forward")
    near(left.CFrame.LookVector.X, -right.CFrame.LookVector.X, "the arms mirror each other")
    check(left.CFrame.Position.Z < plate.CFrame.Position.Z, "the chevron sits ahead of the plate centre")

    local tag = plate:FindFirstChild("Placer")
    check(tag ~= nil, "the marker carries a name tag")
    same(tag.ClassName, "BillboardGui", "the name tag is a BillboardGui")
    same(tag.MaxDistance, 60, "the name tag fades beyond 60 studs")
    same(tag.Adornee, plate, "the name tag is adorned to the plate")
    local label = tag:FindFirstChild("Name")
    same(label.Text, "Placer", "the name tag names who placed it")
    same(label.Font, Enum.Font.Code, "the name tag uses the project's Code font")

    local ray = ctx.Rays[#ctx.Rays]
    same(ray.Params.FilterType, Enum.RaycastFilterType.Exclude, "the floor probe excludes, never includes")
    same(ray.Params.IgnoreWater, true, "flooded Level 2 water is not floor")
    same(ray.Params.RespectCanCollide, true, "decoration nothing can stand on is not floor")
    same(ray.Direction.Y, -12, "the floor probe reaches 12 studs down")
    near(ray.Origin.Y, 5, "the floor probe starts at root height")
    local excluded = ray.Params.FilterDescendantsInstances
    local sawCharacter, sawFolder = false, false
    for _, entry in ipairs(excluded) do
        if entry == character then sawCharacter = true end
        if entry == ctx:Folder() then sawFolder = true end
    end
    check(sawCharacter, "the placer's own body is excluded from the floor probe")
    check(sawFolder, "existing markers are excluded from the floor probe")
end

-- ------------------------------------------------------- floor probe fallback
do
    local ctx = fresh()
    local player = ctx:AddPlayer("Placer", 101, Vector3.new(0, 30, 0))
    ctx.FloorY = nil
    ctx:Place(player, "place")
    local plate = ctx:Markers()[1]:FindFirstChild("Base")
    near(plate.CFrame.Position.Y, 30 - 2.6 + 0.15, "no floor hit falls back to root height")
end
do
    local ctx = fresh()
    local player = ctx:AddPlayer("Placer", 101, Vector3.new(0, 5, 0), Vector3.new(1, 0, 0))
    ctx.FloorY = 0
    ctx:Place(player, "place")
    local plate = ctx:Markers()[1]:FindFirstChild("Base")
    near(plate.CFrame.Position.X, 2.5, "facing +X places the marker along +X")
    near(plate.CFrame.Position.Z, 0, "facing +X leaves Z alone")
    near(plate.CFrame.LookVector.X, 1, "the marker yaw follows +X")
end
do
    -- A root looking straight down has no flat direction to copy.
    local ctx = fresh()
    local player = ctx:AddPlayer("Placer", 101, Vector3.new(0, 5, 0), Vector3.new(0, -1, 0))
    ctx.FloorY = 0
    local reply = ctx:Place(player, "place")
    same(reply.Kind, "placed", "a vertical look vector still places a marker")
    local plate = ctx:Markers()[1]:FindFirstChild("Base")
    check(plate.CFrame.Position.Position == nil, "the plate CFrame is a CFrame")
    near(plate.CFrame.Position.Y, 0.15, "the fallback marker still snaps to the floor")
end

-- --------------------------------------------------------------- rate limiting
do
    local ctx = fresh()
    local player = ctx:AddPlayer("Placer", 101)
    ctx:Place(player, "place")
    local reply = ctx:Place(player, "place")
    same(reply.Payload, "RateLimited", "a second immediate request is throttled")
    same(#ctx:Markers(), 1, "the throttled request places nothing")
    same(#ctx.Consumes, 1, "the throttled request never spends")
    ctx:Advance(1.49)
    same(ctx:Place(player, "place").Payload, "RateLimited", "1.49s is still inside the window")
    ctx:Advance(0.02)
    same(ctx:Place(player, "place").Kind, "placed", "1.51s reopens placement")
    same(#ctx.Consumes, 2, "one spend per accepted placement")
end

-- ------------------------------------------------------------ inventory says no
do
    local ctx = fresh()
    local player = ctx:AddPlayer("Placer", 101)
    ctx.ConsumeResult = false
    local reply = ctx:Place(player, "place")
    same(reply.Payload, "NoMarkers", "a refused consume refuses the placement")
    same(#ctx:Markers(), 0, "a refused consume places nothing")
    same(player:GetAttribute("RouteMarkersActive"), 0, "a refused consume leaves the count alone")
    same(#ctx.Consumes, 1, "the refusal came from the inventory, not a guess")
    same(ctx:Place(player, "place").Payload, "RateLimited", "an empty pack cannot hammer the profile write")
    same(#ctx.Consumes, 1, "the throttle held the second attempt off the datastore")
end
do
    local ctx = fresh()
    local player = ctx:AddPlayer("Placer", 101)
    ctx.Inventory:Destroy()
    local reply = ctx:Place(player, "place")
    same(reply.Payload, "Unavailable", "a missing inventory refuses rather than granting")
    same(#ctx:Markers(), 0, "a missing inventory places nothing")
end
do
    local ctx = fresh()
    local player = ctx:AddPlayer("Placer", 101)
    ctx.ConsumeError = true
    local reply = ctx:Place(player, "place")
    same(reply.Payload, "Unavailable", "an erroring inventory refuses rather than granting")
    same(#ctx:Markers(), 0, "an erroring inventory places nothing")
end

-- ------------------------------------------------------------------- the cap
do
    local ctx = fresh()
    local player = ctx:AddPlayer("Placer", 101)
    local counts = {}
    for index = 1, 4 do
        table.insert(counts, ctx:Place(player, "place").Payload)
        ctx:Advance(2)
    end
    same(counts[1], 1, "first placement reports one")
    same(counts[2], 2, "second placement reports two")
    same(counts[3], 3, "third placement reports three")
    same(counts[4], 3, "a fourth placement still reports three")
    same(#ctx.Consumes, 4, "the fourth marker is still paid for")
    same(#ctx:Markers(), 3, "never more than three markers stand")
    same(player:GetAttribute("RouteMarkersActive"), 3, "the published count matches")
    local serials = {}
    for _, marker in ipairs(ctx:Markers()) do serials[marker:GetAttribute("Serial")] = true end
    same(serials[1], nil, "the OLDEST marker is the one retired")
    check(serials[2] and serials[3] and serials[4], "the three newest markers remain")
end
do
    local ctx = context()
    ctx.Config.Value = {Items = {RouteMarker = {MaxActive = 2}}}
    boot(ctx)
    ctx.Remote = ctx.Remotes:FindFirstChild("RouteMarker")
    local player = ctx:AddPlayer("Placer", 101)
    for _ = 1, 3 do ctx:Place(player, "place"); ctx:Advance(2) end
    same(#ctx:Markers(), 2, "MaxActive is read from ZyntraConfig")
end
do
    local ctx = context()
    ctx.Config.Value = {}
    boot(ctx)
    ctx.Remote = ctx.Remotes:FindFirstChild("RouteMarker")
    local player = ctx:AddPlayer("Placer", 101)
    for _ = 1, 4 do ctx:Place(player, "place"); ctx:Advance(2) end
    same(#ctx:Markers(), 3, "a config without Items falls back to three")
end
do
    local ctx = context()
    ctx.Config:Destroy()
    boot(ctx)
    ctx.Remote = ctx.Remotes:FindFirstChild("RouteMarker")
    local player = ctx:AddPlayer("Placer", 101)
    same(ctx:Place(player, "place").Kind, "placed", "a missing ZyntraConfig does not break placement")
end

-- ------------------------------------------------------- two players, one round
do
    local ctx = fresh()
    local one = ctx:AddPlayer("One", 101, Vector3.new(0, 5, 0))
    local two = ctx:AddPlayer("Two", 202, Vector3.new(50, 5, 0))
    ctx:Place(one, "place")
    same(ctx:Place(two, "place").Kind, "placed", "one player's cooldown does not throttle another")
    same(one:GetAttribute("RouteMarkersActive"), 1, "counts are per player")
    same(two:GetAttribute("RouteMarkersActive"), 1, "counts are per player")
    same(#ctx:Markers(), 2, "both markers share the team folder")
    local owners = {}
    for _, marker in ipairs(ctx:Markers()) do owners[marker:GetAttribute("Owner")] = true end
    check(owners[101] and owners[202], "each marker records its own owner")
    local ray = ctx.Rays[#ctx.Rays]
    local sawOther = false
    for _, entry in ipairs(ray.Params.FilterDescendantsInstances) do
        if entry == one.Character then sawOther = true end
    end
    check(sawOther, "a teammate's body is not floor either")
end

-- ------------------------------------------------- death, leaving and round end
do
    local ctx = fresh()
    local player = ctx:AddPlayer("Placer", 101)
    ctx:Place(player, "place")
    player.Character:FindFirstChildOfClass("Humanoid").Health = 0
    same(#ctx:Markers(), 1, "the placer's death does NOT remove their markers")
    ctx:Advance(2)
    same(ctx:Place(player, "place").Payload, "NoCharacter", "but a dead player cannot place another")
end
do
    local ctx = fresh()
    local player = ctx:AddPlayer("Placer", 101)
    ctx:Place(player, "place")
    ctx.Players.PlayerRemoving:Fire(player)
    same(#ctx:Markers(), 1, "a leaver's markers stay up for the rest of the team")
end
do
    local ctx = fresh()
    local one = ctx:AddPlayer("One", 101)
    local two = ctx:AddPlayer("Two", 202, Vector3.new(50, 5, 0))
    ctx:Place(one, "place")
    ctx:Place(two, "place")
    ctx.Workspace:SetAttribute("RoundActive", false)
    same(#ctx:Markers(), 0, "round end destroys every marker")
    same(one:GetAttribute("RouteMarkersActive"), 0, "round end zeroes the counts")
    same(two:GetAttribute("RouteMarkersActive"), 0, "round end zeroes every player's count")
    same(ctx:Place(one, "place").Payload, "NotInRound", "no placing between rounds")
    ctx.Workspace:SetAttribute("RoundActive", true)
    ctx:Advance(2)
    same(ctx:Place(one, "place").Kind, "placed", "the next round starts from an empty pack of three")
    same(one:GetAttribute("RouteMarkersActive"), 1, "the new round counts from one")
end
do
    -- A world teardown that takes the folder with it must not strand the count.
    local ctx = fresh()
    local player = ctx:AddPlayer("Placer", 101)
    ctx:Place(player, "place")
    ctx:Folder():Destroy()
    ctx:Advance(2)
    same(ctx:Place(player, "place").Payload, 1, "a destroyed folder is rebuilt and the count re-derived")
    same(#ctx:Markers(), 1, "the rebuilt folder holds the new marker")
end

-- ------------------------------------------------------------- hostile clients
do
    local ctx = fresh()
    local player = ctx:AddPlayer("Placer", 101, Vector3.new(0, 5, 0), Vector3.new(0, 0, -1))
    ctx.FloorY = 0
    for _, message in ipairs({"remove", "Place", "", "PLACE", 42, true}) do
        ctx.Remote.OnServerEvent:Fire(player, message)
        same(#ctx.Replies, 0, "unknown message '" .. tostring(message) .. "' is ignored silently")
        same(#ctx.Consumes, 0, "unknown message '" .. tostring(message) .. "' spends nothing")
    end
    ctx.Remote.OnServerEvent:Fire(player)
    same(#ctx.Replies, 0, "an empty request is ignored")
    ctx.Remote.OnServerEvent:Fire(player, {"place"})
    same(#ctx.Replies, 0, "a table shaped like a request is ignored")
    same(#ctx:Markers(), 0, "no hostile message ever placed a marker")

    -- The exploit the contract exists to prevent: a supplied position.
    local forged = CFrame.new(Vector3.new(9999, 9999, 9999), Vector3.new(9999, 9999, 9998))
    ctx.Remote.OnServerEvent:Fire(player, "place", forged, Vector3.new(9999, 9999, 9999), ctx.Workspace)
    local plate = ctx:Markers()[1]:FindFirstChild("Base")
    near(plate.CFrame.Position.X, 0, "a client CFrame cannot move the marker in X")
    near(plate.CFrame.Position.Y, 0.15, "a client CFrame cannot move the marker in Y")
    near(plate.CFrame.Position.Z, -2.5, "a client CFrame cannot move the marker in Z")
    same(ctx:Markers()[1].Parent, ctx:Folder(), "a client instance cannot re-parent the marker")
end

print("Route markers: " .. checks .. " checks passed (whole actual Script, offline Luau; rendering and replication not exercised)")
'''


def main():
    binary = os.environ.get("LUAU_BIN") or shutil.which("luau")
    if not binary:
        raise SystemExit("Set LUAU_BIN; no tests executed.")
    with tempfile.TemporaryDirectory(prefix="route-markers-") as directory:
        path = Path(directory) / "route_markers_test.luau"
        path.write_text(HARNESS + SOURCE.read_text(encoding="utf-8") + TESTS, encoding="utf-8")
        subprocess.run([binary, str(path)], check=True, timeout=30)


if __name__ == "__main__":
    main()
