"""Exercise the complete music controller and production configuration in Luau.

The host supplies only Roblox services, instances, signals, and a controllable
server clock. Boundary expectations intentionally pin the existing song/hunt
timing while checking that the former flashlight-lock windows stay usable.
"""

import argparse
import os
from pathlib import Path
import shutil
import subprocess
import tempfile

ROOT = Path(__file__).resolve().parents[2]
SYSTEMS = ROOT / "ServerScriptService/Level 3 Systems"
CONTROLLER = SYSTEMS / "Level 3 Music Sequence Controller.ModuleScript.lua"
CONFIGURATION = SYSTEMS / "Level 3 Configuration.ModuleScript.lua"

HOST = r'''
local checks = 0
local function check(value, message)
    checks += 1
    assert(value, message)
end
local function equal(actual, expected, message)
    check(actual == expected, message .. ": expected " .. tostring(expected) .. ", got " .. tostring(actual))
end
local function near(actual, expected, message)
    check(type(actual) == "number" and math.abs(actual - expected) < 1e-6,
        message .. ": expected " .. tostring(expected) .. ", got " .. tostring(actual))
end
local Vector3 = {new = function(x, y, z) return {X=x, Y=y, Z=z} end}
local Color3 = {fromRGB = function(r, g, b) return {R=r, G=g, B=b} end}
local Configuration = (function()
__CONFIGURATION__
end)()

local function signal()
    local connections = {}
    local event = {}
    function event:Connect(callback)
        local connection = {Connected=true, Callback=callback}
        function connection:Disconnect() self.Connected=false end
        table.insert(connections, connection)
        return connection
    end
    function event:Fire(...)
        for _, connection in ipairs(table.clone(connections)) do
            if connection.Connected then connection.Callback(...) end
        end
    end
    function event:Count()
        local count = 0
        for _, connection in ipairs(connections) do
            if connection.Connected then count += 1 end
        end
        return count
    end
    return event
end

local function fresh()
    local ctx = {Now=1000, Writes={}, Sounds={}, Nodes={}, Studio=true}
    local Instance = {}
    function Instance.new(class)
        local node = {ClassName=class, Attributes={}, Signals={}}
        function node:IsA(wanted)
            return self.ClassName == wanted or (wanted == "BasePart" and self.ClassName == "Part")
        end
        function node:GetAttribute(name) return self.Attributes[name] end
        function node:GetAttributeChangedSignal(name)
            if not self.Signals[name] then self.Signals[name]=signal() end
            return self.Signals[name]
        end
        function node:SetAttribute(name, value)
            table.insert(ctx.Writes, {Node=self, Name=name, Value=value, At=ctx.Now})
            local changed = self.Attributes[name] ~= value
            self.Attributes[name] = value
            if changed and self.Signals[name] then self.Signals[name]:Fire() end
        end
        function node:FindFirstChild(name)
            for _, child in ipairs(ctx.Nodes) do
                if child.Parent == self and child.Name == name then return child end
            end
            return nil
        end
        function node:GetDescendants()
            local result = {}
            for _, child in ipairs(ctx.Nodes) do
                local ancestor = child.Parent
                while ancestor do
                    if ancestor == self then table.insert(result, child);break end
                    ancestor = ancestor.Parent
                end
            end
            return result
        end
        function node:Destroy() self.Parent=nil;self.Destroyed=true end
        function node:FireAllClients(payload) table.insert(ctx.Sounds, payload) end
        table.insert(ctx.Nodes, node)
        return node
    end
    local workspace = Instance.new("Workspace")
    function workspace:GetServerTimeNow() return ctx.Now end
    workspace:SetAttribute("SelectedLevel", 3)
    workspace:SetAttribute("RoundActive", false)
    local replicated = Instance.new("ReplicatedStorage")
    local storage = Instance.new("ServerStorage")
    local runService = {Heartbeat=signal(), IsStudio=function() return ctx.Studio end}
    local services = {ReplicatedStorage=replicated, ServerStorage=storage, RunService=runService}
    local game = {GetService=function(_, name) return assert(services[name], name) end}
    local moduleToken = {}
    local script = {Parent={WaitForChild=function(_, name)
        assert(name == "Level 3 Configuration");return moduleToken
    end}}
    local function require(module)
        assert(module == moduleToken);return Configuration
    end
    local state = Instance.new("Folder")
    state.Name = Configuration.StateFolderName;state.Parent = replicated
    state:SetAttribute("Level3_CDCollectedProgress", 0)
    state:SetAttribute("Level3_ModuleProgress", 0)
    state:SetAttribute("Level3_ModuleGoal", Configuration.ModuleGoal)
    local remotes = Instance.new("Folder")
    remotes.Name = Configuration.RemotesFolderName;remotes.Parent = replicated
    local event = Instance.new("RemoteEvent")
    event.Name = Configuration.ClientEventName;event.Parent = remotes
    local world = Instance.new("Model")
    world.Name=Configuration.WorldName;world.Parent=workspace
    world:SetAttribute("Level3_Generation", 17)
    local Controller = (function()
__CONTROLLER__
    end)()
    ctx.Controller=Controller;ctx.State=state;ctx.Workspace=workspace
    ctx.World=world;ctx.RunService=runService;ctx.Storage=storage
    function ctx:Pulse(now)
        if now then self.Now=now end
        runService.Heartbeat:Fire(.05)
    end
    function ctx:Start()
        return Controller.Start({World=world}, 17)
    end
    function ctx:Ready()
        workspace:SetAttribute("RoundActive", true)
        state:SetAttribute("Level3_CDCollectedProgress", 1)
        self:Start()
        return Controller.GetSnapshot().StartServerTime
    end
    function ctx:FreeLights(message)
        equal(state:GetAttribute("Level3_FlashlightsSuppressed"), false, message .. " replicated flag")
        equal(workspace:GetAttribute("Level3FlashlightsSuppressed"), false, message .. " workspace flag")
    end
    function ctx:NoForcedWrites()
        for _, write in ipairs(self.Writes) do
            if write.Name == "Level3_FlashlightsSuppressed" or write.Name == "Level3FlashlightsSuppressed" then
                check(write.Value ~= true, "timeline wrote forced flashlight suppression at " .. write.At)
            end
        end
    end
    return ctx
end

-- These are user-visible timeline contracts, independent of implementation.
near(Configuration.MusicSequence.DurationSeconds, 180.035917, "song duration")
near(Configuration.MusicSequence.BlackoutStartSeconds, 150, "blackout starts at 2:30")
near(Configuration.MusicSequence.PreBlackoutFlickerSeconds, 5, "five-second warning")
near(Configuration.MusicSequence.BlackoutScreamLeadSeconds, 3, "three-second scream lead")
near(Configuration.MusicSequence.PostSongBlackoutSeconds, 30, "thirty-second hunt")
near(Configuration.MusicSequence.CycleEndSeconds, 210.035917, "hunt end")
near(Configuration.MusicSequence.RecoveryFlickerSeconds, 3.2, "recovery duration")
near(Configuration.MusicSequence.PreloadLeadSeconds, 1.5, "preload lead")

for _,operation in ipairs({"Stop", "Start"}) do
    local ctx=fresh()
    ctx.State:SetAttribute("Level3_FlashlightsSuppressed", true)
    ctx.Workspace:SetAttribute("Level3FlashlightsSuppressed", true)
    ctx.Writes={}
    if operation == "Stop" then ctx.Controller.Stop() else ctx:Start() end
    ctx:FreeLights("cold " .. operation .. " clears saved legacy suppression")
    ctx:NoForcedWrites()
end

do
    local ctx=fresh()
    ctx.Workspace:SetAttribute("SelectedLevel", 2)
    ctx.Workspace:SetAttribute("RoundActive", true)
    ctx:Start()
    equal(ctx.Controller.GetSnapshot().Phase, "WAITING_FOR_ROUND", "other levels cannot start the song")
    ctx.Workspace:SetAttribute("SelectedLevel", 3);ctx:Pulse()
    equal(ctx.Controller.GetSnapshot().Phase, "WAITING_FOR_FIRST_CD", "spawn stays silent")
    ctx.State:SetAttribute("Level3_ModuleProgress", 1);ctx:Pulse(ctx.Now+10)
    equal(ctx.Controller.GetSnapshot().StartServerTime, nil, "installed progress is not the first-CD signal")
    equal(ctx.State:GetAttribute("Level3_RoomSongCycle"), 0, "waiting does not increment cycle")
    local ok, reason=ctx.Controller.DevSkipToPreBlackout()
    equal(ok, false, "dev shortcut cannot bypass first-CD gate")
    equal(reason, "NOT_ARMED", "unarmed shortcut explanation")
    ctx.State:SetAttribute("Level3_CDCollectedProgress", 1);ctx:Pulse()
    local start=ctx.Now+1.5
    near(ctx.Controller.GetSnapshot().StartServerTime, start, "first CD establishes absolute start")
    equal(ctx.Controller.GetSnapshot().Phase, "ARMED", "preload period remains armed")
    equal(ctx.State:GetAttribute("Level3_RoomSongCycle"), 1, "first CD starts one cycle")
    ctx.State:SetAttribute("Level3_CDCollectedProgress", 2);ctx:Pulse(start-.01)
    near(ctx.Controller.GetSnapshot().StartServerTime, start, "later CDs never restart the clock")
    equal(ctx.State:GetAttribute("Level3_RoomSongCycle"), 1, "later CDs never add a cycle")
    ctx:FreeLights("waiting and arming")
    ctx:NoForcedWrites()
end

do
    local ctx=fresh()
    local start=ctx:Ready()
    local edges={
        {-0.01, "ARMED", false, false, false, false, 0},
        {0.00001, "PLAYING", false, false, false, false, 0},
        {144.99999, "PLAYING", false, false, false, false, 0},
        {145.00001, "PRE_BLACKOUT", true, false, false, false, 0},
        {149.99999, "PRE_BLACKOUT", true, false, false, false, 0},
        {150.00001, "BLACKOUT_SONG", false, true, false, false, 0},
        {176.035907, "BLACKOUT_SONG", false, true, false, false, 0},
        {176.035927, "BLACKOUT_SONG", false, true, false, false, 0},
        {176.535917, "BLACKOUT_SONG", false, true, false, false, 0},
        {177.035907, "BLACKOUT_SONG", false, true, false, false, 0},
        {177.035927, "BLACKOUT_SONG", false, true, false, false, 1},
        {180.035907, "BLACKOUT_SONG", false, true, false, false, 1},
        {180.035927, "BLACKOUT_HUNT", false, true, true, false, 1},
        {208.035907, "BLACKOUT_HUNT", false, true, true, false, 1},
        {208.035927, "BLACKOUT_HUNT", false, true, true, false, 1},
        {209.035917, "BLACKOUT_HUNT", false, true, true, false, 1},
        {210.035907, "BLACKOUT_HUNT", false, true, true, false, 1},
        {210.035927, "RECOVERY_FLICKER", false, false, false, true, 1},
        {213.235907, "RECOVERY_FLICKER", false, false, false, true, 1},
    }
    for _,edge in ipairs(edges) do
        ctx:Pulse(start+edge[1])
        local snapshot=ctx.Controller.GetSnapshot()
        equal(snapshot.Phase, edge[2], "phase at " .. edge[1])
        equal(snapshot.PreBlackoutActive, edge[3], "warning flag at " .. edge[1])
        equal(snapshot.BlackoutActive, edge[4], "blackout flag at " .. edge[1])
        equal(snapshot.HuntActive, edge[5], "hunt flag at " .. edge[1])
        equal(snapshot.RecoveryFlickerActive, edge[6], "recovery flag at " .. edge[1])
        equal(ctx.State:GetAttribute("Level3_BlackoutSerial"), edge[7], "scream edge at " .. edge[1])
        equal(ctx.Workspace:GetAttribute("Level3BlackoutActive"), edge[4], "world blackout agrees")
        equal(ctx.Workspace:GetAttribute("Level3MallManagerHuntActive"), edge[5], "world hunt agrees")
        ctx:FreeLights("elapsed " .. edge[1])
        if edge[3] then
            near(ctx.State:GetAttribute("Level3_PreBlackoutStartedAtServerTime"), start+145, "warning timestamp")
            near(ctx.State:GetAttribute("Level3_PreBlackoutUntilServerTime"), start+150, "warning deadline")
        end
        if edge[4] then
            near(ctx.State:GetAttribute("Level3_BlackoutUntilServerTime"), start+210.035917, "blackout deadline")
        end
        if edge[7] == 1 then
            near(ctx.State:GetAttribute("Level3_BlackoutScreamStartedAtServerTime"), start+177.035917, "scream absolute timestamp")
            equal(#ctx.Sounds, 1, "scream sound emitted once")
        end
        if edge[6] then
            near(ctx.State:GetAttribute("Level3_RecoveryFlickerStartedAtServerTime"), start+210.035917, "recovery timestamp")
            near(ctx.State:GetAttribute("Level3_RecoveryFlickerUntilServerTime"), start+213.235917, "recovery deadline")
        end
    end
    equal(ctx.Sounds[1].Cue, "PowerDown", "blackout sound cue is retained")
    equal(ctx.Sounds[1].Generation, 17, "blackout sound generation is retained")
    ctx:Pulse(start+213.235927)
    equal(ctx.Controller.GetSnapshot().Phase, "ARMED", "recovery rearms the next song")
    equal(ctx.State:GetAttribute("Level3_RoomSongCycle"), 2, "next cycle increments exactly once")
    local nextStart=ctx.Now+1.5
    near(ctx.Controller.GetSnapshot().StartServerTime, nextStart, "next cycle receives preload lead")
    ctx:Pulse(nextStart+177.035927)
    equal(ctx.State:GetAttribute("Level3_BlackoutSerial"), 2, "next cycle can scream once again")
    equal(#ctx.Sounds, 2, "one sound edge per cycle")
    ctx:FreeLights("second cycle former lock window")
    ctx:NoForcedWrites()
end

do
    local ctx=fresh();local start=ctx:Ready()
    ctx:Pulse(start+200)
    equal(ctx.Controller.GetSnapshot().Phase, "BLACKOUT_HUNT", "missed frame can enter hunt directly")
    near(ctx.State:GetAttribute("Level3_BlackoutScreamStartedAtServerTime"), start+177.035917,
        "late hunt frame preserves original scream timestamp")
    equal(#ctx.Sounds, 1, "missed scream frame still sends one edge")
    ctx.Controller.DebugSetElapsed(20)
    local snapshot=ctx.Controller.GetSnapshot()
    equal(snapshot.Phase, "PLAYING", "backward Studio seek restores playing")
    equal(snapshot.BlackoutActive, false, "backward seek clears blackout")
    equal(snapshot.HuntActive, false, "backward seek clears hunt")
    equal(snapshot.RecoveryFlickerActive, false, "backward seek clears recovery")
    ctx:FreeLights("backward seek")
    local ok, reason=ctx.Controller.DevSkipToPreBlackout()
    equal(ok, true, "dev shortcut still reaches warning")
    equal(reason, "SKIPPED_TO_2_25", "dev shortcut result")
    equal(ctx.Controller.GetSnapshot().Phase, "PRE_BLACKOUT", "dev shortcut warning phase")
    ok, reason=ctx.Controller.DevSkipToPreBlackout()
    equal(ok, false, "dev shortcut is idempotent")
    equal(reason, "ALREADY_AT_OR_PAST_WARNING", "duplicate shortcut explanation")
    ctx.Studio=false
    equal(pcall(ctx.Controller.DebugSetElapsed, 20), false, "production rejects raw debug seeks")
    ctx:NoForcedWrites()
end

do
    local ctx=fresh();local start=ctx:Ready()
    ctx:Pulse(start+209)
    ctx.State:SetAttribute("Level3_ModuleProgress", Configuration.ModuleGoal);ctx:Pulse()
    local snapshot=ctx.Controller.GetSnapshot()
    equal(snapshot.Phase, "DONE", "completed objective ends timeline")
    equal(snapshot.BlackoutActive, false, "completion restores lighting")
    equal(snapshot.HuntActive, false, "completion ends hunt")
    equal(snapshot.RecoveryFlickerActive, false, "completion stops recovery")
    local ok, reason=ctx.Controller.DevSkipToPreBlackout()
    equal(ok, false, "completed objective rejects dev shortcut")
    equal(reason, "OBJECTIVE_COMPLETE", "completed objective explanation")
    ctx:Pulse(start+500)
    equal(ctx.State:GetAttribute("Level3_RoomSongCycle"), 1, "completion never starts another cycle")
    ctx:FreeLights("objective complete")
    ctx:NoForcedWrites()
end

do
    local ctx=fresh();local start=ctx:Ready()
    ctx:Pulse(start+209)
    local active=ctx:Start()
    equal(ctx.RunService.Heartbeat:Count(), 1, "restarting replaces heartbeat connection")
    equal(ctx.Workspace:GetAttributeChangedSignal("RoundActive"):Count(), 1, "restarting replaces round connection")
    ctx.Controller.Stop()
    equal(active.Connection.Connected, false, "Stop disconnects heartbeat")
    equal(active.RoundConnection.Connected, false, "Stop disconnects round signal")
    equal(ctx.RunService.Heartbeat:Count(), 0, "Stop leaves no heartbeat listener")
    equal(ctx.Workspace:GetAttributeChangedSignal("RoundActive"):Count(), 0, "Stop leaves no round listener")
    equal(ctx.Controller.GetSnapshot(), nil, "Stop releases session")
    equal(ctx.State:GetAttribute("Level3_RoomSongPhase"), "STOPPED", "Stop publishes stopped phase")
    equal(ctx.Workspace:GetAttribute("Level3BlackoutActive"), false, "Stop clears blackout")
    equal(ctx.Workspace:GetAttribute("Level3MallManagerHuntActive"), false, "Stop clears hunt")
    local writes=#ctx.Writes
    ctx:Pulse(ctx.Now+500)
    active.Connection.Callback(.1) -- a queued callback cannot revive the retired session
    equal(#ctx.Writes, writes, "retired heartbeat cannot publish state")
    ctx.Workspace:SetAttribute("RoundActive", false)
    equal(ctx.State:GetAttribute("Level3_RoomSongPhase"), "STOPPED", "disconnected round event stays inert")
    ctx:FreeLights("stopped timeline")
    ctx:NoForcedWrites()
end

do
    local ctx=fresh();local start=ctx:Ready()
    ctx.World:SetAttribute("Level3_Generation", 18)
    local writes=#ctx.Writes
    ctx:Pulse(start+209)
    equal(#ctx.Writes, writes, "stale generation heartbeat cannot publish")
    local ok, reason=ctx.Controller.DevSkipToPreBlackout()
    equal(ok, false, "stale generation rejects dev shortcut")
    equal(reason, "NOT_RUNNING", "stale generation explanation")
    ctx.World:SetAttribute("Level3_Generation", 17);ctx.World.Parent=nil
    writes=#ctx.Writes;ctx:Pulse(start+210)
    equal(#ctx.Writes, writes, "unparented world heartbeat cannot publish")
end

print(string.format("Level 3 flashlight timeline: %d checks passed (complete controller + production config, clock boundaries, legacy cleanup, first CD, cycles and lifecycle)", checks))
'''


def main():
    parser = argparse.ArgumentParser()
    parser.add_argument("--controller", type=Path, default=CONTROLLER)
    parser.add_argument("--configuration", type=Path, default=CONFIGURATION)
    args = parser.parse_args()
    binary = os.environ.get("LUAU_BIN") or shutil.which("luau")
    if not binary:
        raise SystemExit("Set LUAU_BIN or put luau on PATH; no tests executed.")
    host = HOST.replace("__CONFIGURATION__", args.configuration.read_text(encoding="utf-8"))
    host = host.replace("__CONTROLLER__", args.controller.read_text(encoding="utf-8"))
    with tempfile.TemporaryDirectory(prefix="level3-flashlight-timeline-") as directory:
        path = Path(directory) / "timeline.luau"
        path.write_text(host, encoding="utf-8")
        subprocess.run([binary, str(path)], check=True, timeout=20)


if __name__ == "__main__":
    main()
