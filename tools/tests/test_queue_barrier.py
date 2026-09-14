"""Full-party circle barrier (Trello #76): the real GameManager queue functions
under a fake lobby.

Extracts the actual queue/capacity functions from GameManager by name and runs
them against controlled stations, characters and a fake Instance/PhysicsService
surface. Covers: barrier appears only for a configured full party, is parented
to the station's room, uses the QueueBarrier collision group with CanQuery off;
members move to QueueMember and back; the wall disappears when capacity frees,
on cancel and on an unconfigured station; developer noclip parts are never
touched; the existing push-out of extras still runs. No Studio, no network.
Set LUAU_BIN to the official Luau interpreter.
"""

from pathlib import Path
import os
import re
import shutil
import subprocess
import tempfile

ROOT = Path(__file__).resolve().parents[2]
SOURCE = (ROOT / "ServerScriptService/GameManager.Script.lua").read_text(encoding="utf-8")

NAMES = [
    "arrivalPointFree", "queueRadius", "playerInsideZone", "rawQueuedPlayers",
    "stationAllowsPlayer", "selectQueuedPlayers", "queuedPlayers", "privacyLabel",
    "resetStation", "queueOutsidePosition", "setQueueMemberCollision",
    "buildStationBarrier", "setStationBarrier", "enforceStationCapacity",
]


def func(name):
    start = SOURCE.index("local function " + name + "(")
    end = re.search(r"\n(?:local function |queueConfig\.OnServerEvent:Connect|-- One non-yielding server pass)",
                    SOURCE[start + 1:])
    assert end, name
    return SOURCE[start:start + 1 + end.start()]


PRELUDE = r'''
local checks = 0
local function check(ok, why) checks += 1; assert(ok, why) end
local V = {}
local Vector3 = {new = function(x, y, z) return setmetatable({X = x, Y = y, Z = z}, V) end}
Vector3.zero = Vector3.new(0, 0, 0)
local Vector2 = {new = function(x, z) return Vector3.new(x, 0, z) end}
V.__add = function(a, b) return Vector3.new(a.X + b.X, a.Y + b.Y, a.Z + b.Z) end
V.__sub = function(a, b) return Vector3.new(a.X - b.X, a.Y - b.Y, a.Z - b.Z) end
V.__mul = function(a, b) return Vector3.new(a.X * b, a.Y * b, a.Z * b) end
V.__index = function(a, k)
    if k == "Magnitude" then return math.sqrt(a.X * a.X + a.Y * a.Y + a.Z * a.Z) end
    if k == "Unit" then return a * (1 / a.Magnitude) end
    if k == "Dot" then return function(x, y) return x.X * y.X + x.Y * y.Y + x.Z * y.Z end end
end
local CF = {}
local CFrame = {}
function CFrame.new(x, y, z)
    return setmetatable({Position = type(x) == "table" and x or Vector3.new(x or 0, y or 0, z or 0), Yaw = 0}, CF)
end
function CFrame.lookAt(a, b) return CFrame.new(a) end
CF.__index = {
    VectorToWorldSpace = function(a, p)
        local c, s = math.cos(a.Yaw), math.sin(a.Yaw)
        return Vector3.new(c * p.X + s * p.Z, p.Y, -s * p.X + c * p.Z)
    end,
    PointToWorldSpace = function(a, p) return a.Position + a:VectorToWorldSpace(p) end,
    PointToObjectSpace = function(a, p)
        local d = p - a.Position
        local c, s = math.cos(a.Yaw), math.sin(a.Yaw)
        return Vector3.new(c * d.X - s * d.Z, d.Y, s * d.X + c * d.Z)
    end,
}
CF.__mul = function(a, b)
    local r = CFrame.new(a:PointToWorldSpace(b.Position)); r.Yaw = a.Yaw + b.Yaw; return r
end
local Color3 = {fromRGB = function(r, g, b) return {r, g, b} end}
local OverlapParams = {new = function() return {} end}
local Enum = {RaycastFilterType = {Include = "Include"}, Material = {ForceField = "ForceField"}}
-- Fake instances: enough surface for the barrier builder and the collision sweep.
local created = {}
local Instance = {}
function Instance.new(class)
    local inst = {ClassName = class, Name = class, Parent = nil, Children = {}}
    function inst:IsA(kind)
        return kind == class or (kind == "BasePart" and class == "Part")
    end
    function inst:GetDescendants()
        local out = {}
        local function walk(node) for _, c in ipairs(node.Children) do table.insert(out, c); walk(c) end end
        walk(self); return out
    end
    local meta = {}
    meta.__index = function(_, k) return rawget(inst, "_" .. k) end
    meta.__newindex = function(t, k, v)
        if k == "Parent" then
            local old = rawget(inst, "_Parent")
            if old and old.Children then
                for i, c in ipairs(old.Children) do if c == t then table.remove(old.Children, i) break end end
            end
            if v and v.Children then table.insert(v.Children, t) end
        end
        rawset(inst, "_" .. k, v)
    end
    setmetatable(inst, meta)
    inst.CollisionGroup = "Default"
    table.insert(created, inst)
    return inst
end
local Players = {List = {}}
function Players:GetPlayers() return self.List end
local workspace = {}
function workspace:GetPartBoundsInBox(cf, size, params)
    check(params.FilterType == "Include", "target checks only authored bay geometry")
    if self.BlockEverything then return {{CanCollide = true}} end
    return {}
end
local os = {Now = 0}
os.clock = function() return os.Now end
local inRound = {}
local IS_RESERVED_ROUND_SERVER = false
local IS_STUDIO = false
local roundBusy = false
local MAX_PLAYERS_PER_STATION = 6
local lobbyStations = {}
local events = {}
local status = {FireClient = function(_, player, event, ...) table.insert(events, {Player = player, Event = event}) end}
local function setStationDisplay(station, main, sub, color) station.Display = {main, sub, color} end
local QUEUE_BARRIER_GROUP = "QueueBarrier"
local QUEUE_MEMBER_GROUP = "QueueMember"

-- ACTUAL_SOURCE

local function zone(yaw)
    local floor = {Position = Vector3.new(100, 29.58, -760), IsA = function(_, kind) return kind == "BasePart" end}
    local room = {Parent = workspace, Children = {}, Name = "Level1QueueRoom",
        FindFirstChild = function(_, name) return name == "ChamberFloor" and floor end,
        GetAttribute = function(_, name) return name == "CircularBayDiameter" and 56 end}
    local z = {Parent = room, Size = Vector3.new(14.82, .3, 14.82), Attrs = {QueueDetectorShape = "Circle", QueueRadius = 7.41}, RoomFloor = floor}
    z.CFrame = CFrame.new(100, 30, -760); z.CFrame.Yaw = yaw or 0; z.Position = z.CFrame.Position
    function z:GetAttribute(k) return self.Attrs[k] end
    function z:IsDescendantOf(p) return self.Parent and self.Parent.Parent == p end
    return z
end
local function station(capacity, yaw)
    local s = {zone = zone(yaw), index = 1, color = {}, feedback = {}, entrySeen = {}, friendCache = {}, configured = true, privacy = "public",
        maxPlayers = capacity, busy = false, admissionEpoch = 1, admittedCharacters = {}}
    lobbyStations[1] = s; return s
end
local function character(p, position, group)
    local c = {Parent = workspace, Pivots = 0, Offset = Vector3.new(-.0054, -3.4862, -.0965), Yaw = .37}
    local root = {Position = position, AssemblyLinearVelocity = Vector3.zero, AssemblyAngularVelocity = Vector3.new(0, 1, 0), Anchored = false,
        CollisionGroup = group or "Default", Name = "HumanoidRootPart"}
    function root:IsA(k) return k == "BasePart" end
    local hat = {CollisionGroup = group or "Default", Name = "Hat", IsA = function(_, k) return k == "BasePart" end}
    c.Root = root; c.Hat = hat; c.Humanoid = {Health = 100, WalkSpeed = 16, AutoRotate = true, IsA = function() return false end}
    function c:FindFirstChild(k) return k == "HumanoidRootPart" and self.Root or nil end
    function c:FindFirstChildOfClass(k) return k == "Humanoid" and self.Humanoid or nil end
    function c:GetDescendants() return {self.Root, self.Hat, self.Humanoid} end
    function c:GetPivot() local cf = CFrame.new(root.Position); cf.Yaw = self.Yaw; return cf * CFrame.new(self.Offset) end
    function c:PivotTo(cf)
        self.Pivots += 1; self.Yaw = cf.Yaw
        root.Position = cf.Position - cf:VectorToWorldSpace(self.Offset)
    end
    p.Character = c; return c
end
local function player(id, s, x, z, group)
    local p = {UserId = id, Name = "P" .. id, DisplayName = "P" .. id, Parent = Players}
    function p:IsFriendsWith() return self.Friend == true end
    character(p, s.zone.CFrame:PointToWorldSpace(Vector3.new(x or 0, 3, z or 0)), group)
    table.insert(Players.List, p); return p
end
local function fresh(capacity, yaw)
    Players.List = {}; events = {}; inRound = {}; os.Now = 0; roundBusy = false; workspace.BlockEverything = false; lobbyStations = {}
    local s = station(capacity, yaw); local host = player(100, s); s.host = host; return s, host
end
local function place(p, s, x, z, y)
    p.Character.Root.Position = s.zone.CFrame:PointToWorldSpace(Vector3.new(x, y or 3, z))
end
local function segments(s)
    return s.barrier and s.barrier.Children or {}
end

-- 1. Not full: no barrier, members keep Default collision.
local s, h = fresh(2)
queuedPlayers(s); enforceStationCapacity(s)
check(s.barrier == nil, "a party under capacity grows no wall")
check(h.Character.Root.CollisionGroup == "Default", "member collision untouched under capacity")

-- 2. Full: the wall appears in the station's room, members pass through it.
os.Now += .01
local mate = player(101, s, 1, 0)
queuedPlayers(s); enforceStationCapacity(s)
check(s.barrier ~= nil and s.barrier.Parent == s.zone.Parent, "full party parents the barrier to the room")
check(#segments(s) == 24, "barrier is a 24-segment ring")
for _, seg in ipairs(segments(s)) do
    check(seg.CanCollide == true and seg.CanQuery == false and seg.Anchored == true, "segments collide but hide from spatial queries")
    check(seg.CollisionGroup == "QueueBarrier" and seg.Material == "ForceField", "segments use the barrier group and force-field look")
end
check(h.Character.Root.CollisionGroup == "QueueMember" and mate.Character.Root.CollisionGroup == "QueueMember", "members move to the QueueMember group")
check(h.Character.Hat.CollisionGroup == "QueueMember", "every member part moves, not only the root")
local builtBarrier = s.barrier
enforceStationCapacity(s)
check(s.barrier == builtBarrier and #created == #created, "a second full pass reuses the same wall")

-- 3. An extra walking in is still pushed out by the server and never becomes a member.
local extra = player(2, s, 5, 1)
enforceStationCapacity(s)
check(not playerInsideZone(extra, s), "full circle still physically rejects an extra character")
check(extra.Character.Root.CollisionGroup == "Default", "the rejected extra keeps Default collision")
check(s.barrier.Parent == s.zone.Parent, "wall stays while the party remains full")

-- 4. A member leaves: capacity frees, wall drops, collision restored.
place(mate, s, 12, 0); enforceStationCapacity(s)
check(s.barrier.Parent == nil, "leaving frees capacity and removes the wall")
check(mate.Character.Root.CollisionGroup == "Default" and mate.Character.Hat.CollisionGroup == "Default", "departed member collision restored")
check(h.Character.Root.CollisionGroup == "Default", "remaining member collision restored when the wall drops")
place(mate, s, 1, 0); enforceStationCapacity(s)
check(s.barrier.Parent == s.zone.Parent and s.barrier == builtBarrier, "re-entry refills and re-raises the same wall")

-- 5. Developer noclip parts are never rewritten in either direction.
s, h = fresh(1)
h.Character.Root.CollisionGroup = "DevNoclip"; h.Character.Hat.CollisionGroup = "DevNoclip"
queuedPlayers(s); enforceStationCapacity(s)
check(s.barrier ~= nil and s.barrier.Parent == s.zone.Parent, "a solo capacity-1 host is a full party")
check(h.Character.Root.CollisionGroup == "DevNoclip" and h.Character.Hat.CollisionGroup == "DevNoclip", "noclip parts are left to setServerNoclip")
place(h, s, 12, 0); enforceStationCapacity(s)
check(h.Character.Root.CollisionGroup == "DevNoclip", "noclip parts are still untouched on release")

-- 6. Cancel and unconfigured stations drop the wall; reset clears membership.
s, h = fresh(1); queuedPlayers(s); enforceStationCapacity(s)
check(s.barrier.Parent ~= nil, "full again")
s.cancelRequested = true; enforceStationCapacity(s)
check(s.barrier.Parent == nil and h.Character.Root.CollisionGroup == "Default", "cancel drops the wall and restores members")
s.cancelRequested = false; s.configured = false; enforceStationCapacity(s)
check(s.barrier.Parent == nil, "an unconfigured station never shows a wall")
resetStation(s, true)
check(next(s.admittedCharacters) == nil, "reset clears membership as before")

-- 7. A busy (launching) full station keeps its wall for the frozen cohort.
s, h = fresh(1); queuedPlayers(s); enforceStationCapacity(s); s.busy = true; enforceStationCapacity(s)
check(s.barrier.Parent ~= nil and h.Character.Root.CollisionGroup == "QueueMember", "frozen launch cohort keeps the wall and its passage")

-- 8. Studio test round in progress: no wall, members restored.
s, h = fresh(1); queuedPlayers(s); enforceStationCapacity(s)
IS_STUDIO = true; roundBusy = true; enforceStationCapacity(s)
check(s.barrier.Parent == nil and h.Character.Root.CollisionGroup == "Default", "Studio round in progress stands the wall down")

print(string.format("queue barrier: %d checks passed (actual GameManager queue functions; fake lobby)", checks))
'''


def main():
    luau = os.environ.get("LUAU_BIN") or shutil.which("luau")
    if not luau:
        raise SystemExit("Set LUAU_BIN or put luau on PATH")
    snippets = "\n".join(func(n) for n in NAMES)
    source = PRELUDE.replace("-- ACTUAL_SOURCE", snippets)
    with tempfile.TemporaryDirectory(prefix="queue-barrier-") as directory:
        path = Path(directory) / "queue_barrier.luau"
        path.write_text(source, encoding="utf-8")
        result = subprocess.run([luau, str(path)], capture_output=True, text=True, timeout=60)
    if result.stdout:
        print(result.stdout, end="")
    if result.stderr:
        print(result.stderr, end="")
    raise SystemExit(result.returncode)


if __name__ == "__main__":
    main()
