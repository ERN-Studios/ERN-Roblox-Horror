"""Run the real ServerScriptService.ZyntraAnalytics module under a fake Roblox host.

The module source is used verbatim, and so is ReplicatedStorage.ZyntraConfig --
the product allow-list has to come from the real catalogue or the shop intake is
not being tested at all. game/Enum/Instance/typeof/require are shadowed by the
prelude; AnalyticsService, the clock, the place/job ids, the reserved-server flag
and the debug folder are injected through the module's own _configure seam.

No Studio, no network, no DataStore. Set LUAU_BIN to the Luau executable, or put
luau on PATH.
"""

from pathlib import Path
import os
import shutil
import subprocess
import tempfile

ROOT = Path(__file__).resolve().parents[2]
MODULE = (ROOT / "ServerScriptService/ZyntraAnalytics.ModuleScript.lua").read_text(encoding="utf-8")
CONFIG = (ROOT / "ReplicatedStorage/ZyntraConfig.ModuleScript.lua").read_text(encoding="utf-8")

PRELUDE = r'''
local checks = 0
local function check(value, message)
    checks += 1
    assert(value, message)
end
local function equal(actual, expected, message)
    checks += 1
    assert(actual == expected,
        message .. ": expected " .. tostring(expected) .. ", got " .. tostring(actual))
end

local Color3 = {fromRGB = function(r, g, b) return {R = r, G = g, B = b} end}

-- Roblox globals the module touches at load time.
local CF = {CustomField01 = "CF01", CustomField02 = "CF02", CustomField03 = "CF03"}
local Enum = {AnalyticsCustomFieldKeys = CF}

local function isInstance(value)
    return type(value) == "table" and rawget(value, "__instance") == true
end
local function typeof(value)
    if isInstance(value) then return "Instance" end
    return type(value)
end

local function newObject(className, name)
    local object = {__instance = true, ClassName = className, Name = name, attrs = {}}
    function object:SetAttribute(key, value) self.attrs[key] = value end
    function object:GetAttribute(key) return self.attrs[key] end
    function object:FindFirstChild() return nil end
    return object
end
local Instance = {new = function(className) return newObject(className, className) end}

local PlayersService = newObject("Players", "Players")
local ServerStorageService = newObject("ServerStorage", "ServerStorage")
local RunServiceStub = {IsStudio = function() return false end}
local ConfigModule = {__instance = true, Module = nil}
local ReplicatedStorageService = newObject("ReplicatedStorage", "ReplicatedStorage")
function ReplicatedStorageService:WaitForChild(name)
    equal(name, "ZyntraConfig", "the module asks ReplicatedStorage only for ZyntraConfig")
    return ConfigModule
end
local SERVICES = {
    Players = PlayersService,
    ReplicatedStorage = ReplicatedStorageService,
    RunService = RunServiceStub,
    ServerStorage = ServerStorageService,
    AnalyticsService = {},
}
local game = {
    PlaceId = 7001, JobId = "job-lobby", PrivateServerId = "", PrivateServerOwnerId = 0,
    GetService = function(_, name) return SERVICES[name] end,
}
local require = function(module) return module.Module end

local nextUserId = 100
local function newPlayer(options)
    options = options or {}
    nextUserId += 1
    local player = newObject("Player", "p" .. nextUserId)
    player.UserId = options.userId or nextUserId
    player.Parent = PlayersService
    player.join = options.join or {SourcePlaceId = 0}
    function player:IsA(className) return className == "Player" end
    function player:GetJoinData() return self.join end
    return player
end

ConfigModule.Module = (function()
'''

BRIDGE = r'''
end)()
local Config = ConfigModule.Module

local Analytics = (function()
'''

HOST = r'''
end)()

-- A fake AnalyticsService that records every accepted call, and can be made to
-- throw or to be missing its methods entirely.
local function newService(options)
    options = options or {}
    local service = {calls = {}}
    local function recorder(kind)
        return function(_, ...)
            if options.throws then error("analytics exploded", 0) end
            table.insert(service.calls, {Kind = kind, Args = {...}})
        end
    end
    if not options.missing then
        service.LogOnboardingFunnelStepEvent = recorder("onboard")
        service.LogFunnelStepEvent = recorder("funnel")
        service.LogCustomEvent = recorder("custom")
    end
    return service
end

local clock = {t = 1000}
local function fakeFolder()
    return newObject("Folder", "ZyntraAnalyticsDebug")
end

-- One configured module per scenario. reserved/live default to a published
-- public lobby, which is where most of the interesting behaviour lives.
local function host(options)
    options = options or {}
    clock.t = options.start or 1000
    local service = newService(options)
    local folder = fakeFolder()
    Analytics._configure({
        AnalyticsService = service,
        Keys = {CF.CustomField01, CF.CustomField02, CF.CustomField03},
        now = function() return clock.t end,
        placeId = 7001,
        jobId = options.jobId or "job-lobby",
        reserved = options.reserved == true,
        live = options.live ~= false,
        folder = folder,
    })
    return {Service = service, Folder = folder}
end

local function kinds(service)
    local names = {}
    for _, call in ipairs(service.calls) do
        if call.Kind == "onboard" then
            table.insert(names, "onboard:" .. tostring(call.Args[2]) .. ":" .. tostring(call.Args[3]))
        elseif call.Kind == "funnel" then
            table.insert(names, "funnel:" .. tostring(call.Args[4]) .. ":" .. tostring(call.Args[5]))
        else
            table.insert(names, "custom:" .. tostring(call.Args[2]))
        end
    end
    return table.concat(names, " ")
end

local function lastCustom(service, name)
    for index = #service.calls, 1, -1 do
        local call = service.calls[index]
        if call.Kind == "custom" and call.Args[2] == name then
            return {Value = call.Args[3], Fields = call.Args[4]}
        end
    end
    return nil
end

local function lastFunnel(service, step)
    for index = #service.calls, 1, -1 do
        local call = service.calls[index]
        if call.Kind == "funnel" and call.Args[4] == step then
            return {Funnel = call.Args[2], Session = call.Args[3], Name = call.Args[5], Fields = call.Args[6]}
        end
    end
    return nil
end

local function countCalls(service, kind)
    local total = 0
    for _, call in ipairs(service.calls) do
        if call.Kind == kind then total += 1 end
    end
    return total
end
'''

TESTS = r'''
-- 1. The onboarding funnel only ever moves forward, and only once per step.
do
    local h = host()
    local player = newPlayer()
    Analytics.Join(player)
    Analytics.ProfileLoaded(player, true)
    Analytics.Ready(player, 1)
    Analytics.RoundStart(player, 1)
    Analytics.Objective(player, 1)
    player:SetAttribute("Escaped", true)
    Analytics.Outcome(player, 1, nil)
    local steps = {}
    for _, call in ipairs(h.Service.calls) do
        if call.Kind == "onboard" then table.insert(steps, call.Args[2] .. call.Args[3]) end
    end
    equal(table.concat(steps, ","),
        "1Joined,2ProfileLoaded,3RoundLoaded,4RoundStarted,5FirstObjective,6FirstEscape",
        "six onboarding steps land once each, in order")

    -- Replaying every hook adds nothing: Roblox would take only the first
    -- instance anyway, and the per-server latch is what keeps it off the wire.
    local before = countCalls(h.Service, "onboard")
    Analytics.Join(player)
    Analytics.ProfileLoaded(player, true)
    Analytics.Ready(player, 1)
    Analytics.RoundStart(player, 1)
    Analytics.Objective(player, 1)
    Analytics.Outcome(player, 1, nil)
    equal(countCalls(h.Service, "onboard"), before, "no onboarding step is ever logged twice")
end

-- 2. A death is a branch, not a step: it must not advance the linear funnel.
do
    local h = host()
    local player = newPlayer()
    Analytics.Join(player)
    Analytics.ProfileLoaded(player, false)
    Analytics.Ready(player, 2)
    Analytics.RoundStart(player, 2)
    clock.t += 42
    player:SetAttribute("LastDeathCause", "PoolFoam")
    Analytics.Death(player, 2)
    equal(countCalls(h.Service, "onboard"), 4, "a death leaves the funnel at RoundStarted")
    local death = lastCustom(h.Service, "zq_first_death")
    check(death ~= nil, "the death is its own custom event")
    equal(death.Value, 42, "the death carries seconds since the round started")
    equal(death.Fields.CF01, "L2", "the death names the level")
    equal(death.Fields.CF02, "poolfoam", "the death cause is admitted in lower case")
    equal(death.Fields.CF03, "returning", "the death carries the new/returning segment")

    clock.t += 10
    Analytics.Death(player, 2)
    equal(countCalls(h.Service, "custom"), 2, "only the FIRST death of a session is logged")

    -- The outcome is a separate fact and is not an onboarding step either.
    Analytics.Outcome(player, 2, nil)
    local outcome = lastCustom(h.Service, "zq_round_outcome")
    equal(outcome.Fields.CF02, "died", "a player who never escaped settles as died")
    equal(countCalls(h.Service, "onboard"), 4, "a lost round never logs FirstEscape")
end

-- 3. An unset or unusable death cause degrades rather than inventing one, and a
--    server admits only a bounded number of distinct causes.
do
    local h = host()
    local player = newPlayer()
    Analytics.RoundStart(player, 1)
    Analytics.Death(player, 1)
    equal(lastCustom(h.Service, "zq_first_death").Fields.CF02, "unknown",
        "no LastDeathCause attribute reads unknown")

    for index = 1, 20 do
        local other = newPlayer()
        other:SetAttribute("LastDeathCause", "cause_" .. index)
        Analytics.RoundStart(other, 1)
        Analytics.Death(other, 1)
    end
    local seen = {}
    for _, call in ipairs(h.Service.calls) do
        if call.Kind == "custom" and call.Args[2] == "zq_first_death" then
            seen[call.Args[4].CF02] = true
        end
    end
    local distinct = 0
    for _ in pairs(seen) do distinct += 1 end
    check(distinct <= 14, "distinct death causes stay bounded, got " .. distinct)
    check(seen.other == true, "causes past the ceiling collapse to other")
end

-- 4. The retry loop. It opens where the NEXT launch can also be observed, and a
--    re-entry inside the same round is never an attempt.
do
    -- Studio / local-lobby shape: one server runs the round and the lobby.
    local h = host()
    local player = newPlayer()
    Analytics.Join(player)
    Analytics.ProfileLoaded(player, false)
    Analytics.RoundStart(player, 1)
    clock.t += 30
    Analytics.Death(player, 1)
    Analytics.ItemUse(player, "Reentry", 1)
    equal(countCalls(h.Service, "funnel"), 0, "an Emergency Re-entry is not a retry")
    Analytics.Outcome(player, 1, nil)
    equal(lastFunnel(h.Service, 1).Name, "BackInLobby", "the round ending opens the retry loop")
    clock.t += 25
    Analytics.Launch(player, 1)
    local step = lastFunnel(h.Service, 2)
    equal(step.Name, "StartedAgain", "launching another round closes the retry loop")
    equal(step.Fields.CF02, "afterdeath", "a retry after a death is marked as one")
    equal(lastCustom(h.Service, "zq_round_relaunch").Value, 25,
        "the relaunch carries the seconds between the two")

    -- A reserved round server must never open a loop it cannot close.
    local r = host({reserved = true, jobId = "job-round"})
    local rider = newPlayer({join = {SourcePlaceId = 7001}})
    Analytics.Join(rider)
    Analytics.RoundStart(rider, 2)
    Analytics.Outcome(rider, 2, "escaped")
    equal(countCalls(r.Service, "funnel"), 0,
        "a reserved round server logs no retry funnel session")
end

-- 5. A teleport back from a round is the SAME session continuing, not a join.
do
    local h = host()
    local fresh = newPlayer({join = {SourcePlaceId = 0}})
    Analytics.Join(fresh)
    equal(countCalls(h.Service, "funnel"), 0, "a first join opens no retry loop")
    clock.t += 30
    Analytics.Leave(fresh)
    local ended = lastCustom(h.Service, "zq_session_end")
    equal(ended.Fields.CF03, "unknown", "a fresh arrival is not tagged as continued")
    equal(ended.Fields.CF01, "lt60s", "a 30 second visit buckets under a minute")

    local back = newPlayer({join = {SourcePlaceId = 7001}})
    Analytics.Join(back)
    equal(countCalls(h.Service, "funnel"), 1, "a return from our own place opens the retry loop")
    clock.t += 120
    Analytics.Leave(back)
    equal(lastCustom(h.Service, "zq_session_end").Fields.CF03, "continued",
        "a continuation is tagged, so a session count can exclude it")
    equal(lastCustom(h.Service, "zq_session_end").Fields.CF01, "1to3m", "120 seconds buckets 1-3m")
end

-- 6. A disconnect mid-round settles that round before the session ends.
do
    local h = host()
    local player = newPlayer()
    Analytics.RoundStart(player, 3)
    player:SetAttribute("InRound", true)
    clock.t += 90
    Analytics.Leave(player)
    local outcome = lastCustom(h.Service, "zq_round_outcome")
    equal(outcome.Fields.CF02, "disconnected", "a mid-round disconnect is its own outcome")
    equal(outcome.Value, 90, "the abandoned round carries its length")
    equal(lastCustom(h.Service, "zq_session_end").Fields.CF02, "round",
        "the session records that a round was reached")
end

-- 7. The shop intake trusts the catalogue and nothing else.
do
    local h = host()
    local player = newPlayer()
    Analytics.ShopView(player, "EntityDetector", false)
    Analytics.ShopView(player, "EntityDetector", true)
    equal(countCalls(h.Service, "custom"), 2, "a real product key is measured")
    equal(lastCustom(h.Service, "zq_shop_view").Fields.CF02, "demo", "a demo is distinguishable")

    Analytics.ShopView(player, "NotAProduct", false)
    Analytics.ShopView(player, {Key = "EntityDetector"}, false)
    Analytics.ShopView(player, nil, false)
    Analytics.ShopView(player, "__index", false)
    equal(countCalls(h.Service, "custom"), 2, "an unknown or malformed product key is dropped")

    Analytics.Purchase(player, "Tokens4", "Utility", 49)
    local bought = lastCustom(h.Service, "zq_shop_purchase")
    equal(bought.Value, 49, "a purchase carries the Robux actually paid")
    equal(bought.Fields.CF01, "Tokens4", "a purchase names the catalogue key")
end

-- 8. Every custom field value stays inside the allow-list.
do
    local h = host()
    local player = newPlayer()
    Analytics.RoundStart(player, 99)
    equal(lastCustom(h.Service, "zq_round_start").Fields.CF01, "L0",
        "a level outside 1-3 degrades to the lobby tag")
    Analytics.ItemUse(player, "SomethingInvented", 2)
    equal(lastCustom(h.Service, "zq_item_use").Fields.CF01, "other",
        "an item name we do not publish reads other")
    player:SetAttribute("ZyntraDeviceClass", "Supercomputer")
    Analytics.Objective(player, 2)
    equal(lastCustom(h.Service, "zq_objective_first").Fields.CF03, "Unknown",
        "a client that invents a device class is capped to the enum")
    -- Real catalogue keys travel as themselves; the sweep below proves it.
    Analytics.ShopView(player, "ExpeditionPack", false)
    Analytics.Purchase(player, "DonationSignal", "Donation", 10)
    Analytics.ItemUse(player, "RouteMarker", 2)
    equal(lastCustom(h.Service, "zq_shop_purchase").Fields.CF01, "DonationSignal",
        "a donation product key survives the sanitiser intact")

    local allowed = {
        L0 = true, L1 = true, L2 = true, L3 = true, new = true, returning = true,
        unknown = true, continued = true, none = true, round = true, objective = true,
        lt60s = true, ["1to3m"] = true, ["3to10m"] = true, ["10m+"] = true,
        escaped = true, died = true, left = true, disconnected = true,
        afterdeath = true, afterclear = true, card = true, demo = true,
        Utility = true, Donation = true, Pass = true, other = true,
        PC = true, Phone = true, Tablet = true, Console = true, Unknown = true,
    }
    for _, call in ipairs(h.Service.calls) do
        local custom = call.Kind == "custom" and call.Args[4] or call.Args[#call.Args]
        for _, key in ipairs({"CF01", "CF02", "CF03"}) do
            local field = custom[key]
            check(type(field) == "string", "every custom field is a string")
            check(allowed[field] or Config.Products[field] or Config.Passes[field]
                or Config.Donations[field] or Config.Items[field]
                or field == "SpeedPotion" or field == "RouteMarker"
                or field == "EntityShield" or field == "Reentry" or field == "DetectorScan",
                "unexpected custom field value: " .. field)
        end
    end
end

-- 9. The rate limiter drops rather than floods, and counts what it dropped.
do
    local h = host()
    local player = newPlayer()
    for _ = 1, 300 do Analytics.ItemUse(player, "SpeedPotion", 1) end
    equal(countCalls(h.Service, "custom"), 120, "the server window caps what is sent")
    equal(h.Folder:GetAttribute("Logged"), 120, "the readback counts what was logged")
    equal(h.Folder:GetAttribute("Dropped"), 180, "the readback counts what was dropped")

    -- The window slides: a minute later the budget is back.
    clock.t += 61
    Analytics.ItemUse(player, "SpeedPotion", 1)
    equal(countCalls(h.Service, "custom"), 121, "the window is a sliding minute, not a session cap")
end

-- 10. A service that throws, or has no methods at all, never reaches the caller.
do
    local h = host({throws = true})
    local player = newPlayer()
    Analytics.Join(player)
    Analytics.ProfileLoaded(player, true)
    Analytics.RoundStart(player, 1)
    Analytics.Death(player, 1)
    Analytics.Outcome(player, 1, "died")
    Analytics.Leave(player)
    check(true, "a throwing AnalyticsService does not propagate")
    check(h.Folder:GetAttribute("Failed") > 0, "the failures are counted")
    equal(h.Folder:GetAttribute("Faults"), 0, "nothing threw inside the module itself")

    local m = host({missing = true})
    local other = newPlayer()
    Analytics.Join(other)
    Analytics.RoundStart(other, 1)
    Analytics.Leave(other)
    check(true, "a service with no Log methods does not propagate")

    -- Junk arguments are refused at the boundary, not passed through.
    local s = host()
    Analytics.Join(nil)
    Analytics.RoundStart("not a player", 1)
    Analytics.Leave({})
    Analytics.Objective(nil, 1)
    equal(#s.Service.calls, 0, "a call with no real player logs nothing")
    equal(s.Folder:GetAttribute("Faults"), 0, "and raises no module fault")
end

-- 11. Studio records without ever calling the service, so a probe can read the
--     ring on a play session while the dashboard stays untouched.
do
    local h = host({live = false})
    local player = newPlayer()
    Analytics.Join(player)
    Analytics.ProfileLoaded(player, true)
    Analytics.RoundStart(player, 2)
    equal(#h.Service.calls, 0, "Studio never calls AnalyticsService")
    equal(h.Folder:GetAttribute("Mode"), "studio", "the readback says which mode it is in")
    check(h.Folder:GetAttribute("Logged") > 0, "Studio still counts what it would have sent")
    check(string.find(h.Folder:GetAttribute("Recent"), "zq_round_start", 1, true) ~= nil,
        "the ring holds the event names a published server would send")
    local snapshot = Analytics.Snapshot()
    equal(snapshot.Mode, "studio", "Snapshot agrees with the folder")
    check(#snapshot.Recent > 0, "Snapshot returns the ring")
end

print(string.format("zyntra analytics: %d checks passed", checks))
'''


def main():
    luau = os.environ.get("LUAU_BIN") or shutil.which("luau")
    if not luau:
        raise SystemExit("Set LUAU_BIN or put luau on PATH")
    source = "\n".join((PRELUDE, CONFIG, BRIDGE, MODULE, HOST, TESTS))
    with tempfile.TemporaryDirectory(prefix="zyntra-analytics-") as directory:
        path = Path(directory) / "zyntra_analytics.luau"
        path.write_text(source, encoding="utf-8")
        result = subprocess.run([luau, str(path)], capture_output=True, text=True, timeout=60)
    if result.stdout:
        print(result.stdout, end="")
    if result.stderr:
        print(result.stderr, end="")
    raise SystemExit(result.returncode)


if __name__ == "__main__":
    main()
