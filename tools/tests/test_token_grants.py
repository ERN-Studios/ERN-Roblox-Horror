"""Exercise the real developer token RemoteFunction and profile mutation in Luau.

Roblox services and profile normalization are stubbed. No Studio, network, live
balances or DataStores are touched. Engine UI/routing need a separate smoke test.
Set LUAU_BIN to the official Luau executable, or put luau on PATH.
"""

from pathlib import Path
import os
import shutil
import subprocess
import tempfile

ROOT = Path(__file__).resolve().parents[2]
SERVER = (ROOT / "ServerScriptService/ZyntraMonetization.Script.lua").read_text(encoding="utf-8")
ACCESS = (ROOT / "ReplicatedStorage/DevAccess.ModuleScript.lua").read_text(encoding="utf-8")


def section(source, start, stop):
    begin = source.index(start)
    return source[begin:source.index(stop, begin)]


COMMON = r'''
local checks = 0
local function check(value, message)
    checks += 1
    assert(value, message)
end
local function equal(actual, expected, message)
    check(actual == expected, message .. ": expected " .. tostring(expected) .. ", got " .. tostring(actual))
end
local function contains(actual, expected, message)
    check(type(actual) == "string" and string.find(actual, expected, 1, true) ~= nil, message)
end
local function clone(value)
    if type(value) ~= "table" then return value end
    local result = {}
    for key, child in pairs(value) do result[key] = clone(child) end
    return result
end
local function typeof(subject)
    return type(subject) == "table" and subject.ClassName and "Instance" or type(subject)
end
local actualDevAccess = (function()
'''

SERVER_PRELUDE = r'''
end)()
local function world(studio)
    local w = {now = 10, studio = studio == true, replies = {}, pushes = {}, logs = {},
        warnings = {}, committed = {}, storeCalls = 0, callbackCalls = 0, attributeCalls = 0}
    local os = {clock = function() return w.now end}
    local function print(...) table.insert(w.logs, {...}) end
    local function warn(...) table.insert(w.warnings, {...}) end
    local task = {wait = function() coroutine.yield("LOCK_WAIT") end}
    local Players = {roster = {}}
    function Players:GetPlayers() return self.roster end
    function Players:GetPlayerByUserId(userId)
        for _, player in ipairs(self.roster) do
            if player.UserId == userId and player.Parent == self then return player end
        end
    end
    local function player(name, userId)
        local p = {Name = name, UserId = userId, Parent = Players, ClassName = "Player"}
        function p:IsA(class) return class == "Player" end
        table.insert(Players.roster, p)
        return p
    end
    w.issuer = player("mikkelczar", 40920547)
    w.second = player("LaverSneglen", 9488575949)
    w.third = player("Detective_Costeau", 833029598)
    w.recipient = player("TargetPlayer", 222)
    w.other = player("OrdinaryPlayer", 111)
    w.other.DisplayName = "mikkelczar"
    local sessions, mutationLocks = {}, {}
    for _, p in ipairs(Players.roster) do
        local data = {Tokens = 8, BatteryLevel = 4, StaminaLevel = 2, CompletedLevels = 3,
            DonationRobux = 75, ReentryCredits = 2, Receipts = {existing = true},
            Grants = {Supporter = true}, Settings = {MuteDispatch = true}}
        sessions[p] = {data = clone(data), persistent = true}
        w.committed["u_" .. p.UserId] = clone(data)
    end
    local serverClosing = false
    local RunService = {IsStudio = function() return w.studio end}
    local ReplicatedStorage = {WaitForChild = function(_, name) return name end}
    local function require(module) assert(module == "DevAccess"); return actualDevAccess end
    local function ensureRemote(class, name)
        assert(class == "RemoteFunction", "token grants must use a RemoteFunction")
        assert(name == "ZyntraGrantTokens", "token grants remote name")
        w.remote = {}
        return w.remote
    end
    local function normalizeProfile(data) return data end
    local function reassertPendingAccessibility() end
    local function applyAttributes() w.attributeCalls += 1 end
    local function pushProfile(p, message, tone)
        table.insert(w.pushes, {player = p, message = message, tone = tone,
            data = clone(sessions[p].data)})
    end
    local store = {}
    function store:UpdateAsync(key, transform)
        w.storeCalls += 1
        if w.yieldStore then coroutine.yield("STORE_WAIT") end
        if w.failBeforeCommit then error("DataStore unavailable") end
        local result
        for attempt = 1, w.retryCallback and 2 or 1 do
            if attempt == 2 and w.concurrentTokens then w.committed[key].Tokens = w.concurrentTokens end
            w.callbackCalls += 1
            result = transform(clone(w.committed[key]))
            -- A rejected first callback result is never committed by Roblox.
        end
        if result then w.committed[key] = clone(result) end
        if w.failAfterCommit then error("Response lost after commit") end
        return clone(result)
    end
'''

SERVER_TAIL = r'''
    w.sessions, w.locks, w.players = sessions, mutationLocks, Players
    function w:closeServer() serverClosing = true end
    function w:invoke(targetUserId, amount, issuer)
        local response = self.remote.OnServerInvoke(issuer or self.issuer, targetUserId, amount)
        check(type(response) == "table" and type(response.Success) == "boolean"
            and type(response.Message) == "string", "remote returns a structured acknowledgement")
        table.insert(self.replies, response)
        return response
    end
    function w:balance(p) return sessions[p or self.recipient].data.Tokens end
    function w:saved(p) return self.committed["u_" .. (p or self.recipient).UserId].Tokens end
    function w:reply() return self.replies[#self.replies] end
    return w
end
'''

SERVER_TESTS = r'''
do
    local w = world()
    local result = w:invoke(222, 20)
    equal(w:balance(), 28, "valid grant changes session balance")
    equal(w:saved(), 28, "valid grant is saved")
    equal(w.storeCalls, 1, "one transaction per gift")
    equal(result.Success, true, "issuer receives confirmed success")
    contains(result.Message, "@TargetPlayer", "confirmation names exact recipient")
    equal(w.pushes[1].player, w.recipient, "recipient receives refreshed profile")
    equal(w.pushes[1].data.Tokens, 28, "recipient receives final balance")
    local data = w.committed.u_222
    check(data.BatteryLevel == 4 and data.StaminaLevel == 2 and data.CompletedLevels == 3,
        "upgrade/progression values preserved")
    check(data.DonationRobux == 75 and data.ReentryCredits == 2 and data.Receipts.existing
        and data.Grants.Supporter and data.Settings.MuteDispatch,
        "donations, receipts, passes and settings preserved")
    equal(w:balance(w.other), 8, "unrelated player remains unchanged")
end
for _, who in ipairs({"issuer", "second", "third"}) do
    local w = world()
    w:invoke(w[who].UserId, 1, w[who])
    equal(w:balance(w[who]), 9, "each allowlisted UserId can grant to self")
end
do
    local w = world()
    w:invoke(222, 10000)
    equal(w:balance(), 10008, "maximum amount accepted")
    local s = world(true)
    s.sessions[s.recipient].persistent = false
    s:invoke(222, 2)
    equal(s:balance(), 10, "Studio supports test profile")
    equal(s.storeCalls, 0, "Studio never writes DataStore")
    equal(s:saved(), 8, "Studio leaves saved balance alone")
    contains(s:reply().Message, "Studio test only; not saved.", "Studio acknowledgement is explicit")
end

-- Remote payloads are untrusted: numeric strings, instances, tables, nonfinite
-- numbers and fractional values must fail before profile or DataStore access.
local malformed = {false, true, "222", "TargetPlayer", "", {}, 0, -1, 1.5,
    0 / 0, math.huge, -math.huge, 9007199254740992}
for _, value in ipairs(malformed) do
    local w = world()
    equal(w:invoke(value, 2).Success, false, "malformed target rejected")
    equal(w.storeCalls, 0, "malformed target cannot access DataStore")
    equal(w:balance(), 8, "malformed target preserves balance")
end
for _, value in ipairs({false, true, "20", "1e3", "", {}, 0, -1, 1.5,
    0 / 0, math.huge, -math.huge, 10001}) do
    local w = world()
    equal(w:invoke(222, value).Success, false, "malformed amount rejected")
    equal(w.storeCalls, 0, "malformed amount cannot access DataStore")
    equal(w:balance(), 8, "malformed amount preserves balance")
end
do
    local w = world()
    equal(w:invoke(nil, 2).Success, false, "missing target rejected")
    equal(w:invoke(222, nil).Success, false, "missing amount rejected")
    equal(w:invoke(w.recipient, 2).Success, false, "instance target rejected")
    equal(w:invoke(222, w.recipient).Success, false, "instance amount rejected")
    equal(w.storeCalls, 0, "missing or instance payloads cannot write")
end
do
    local w = world()
    equal(w:invoke(222, 20, w.other).Success, false, "ordinary player cannot grant")
    w.other.Name = "mikkelczar"
    equal(w:invoke(222, 20, w.other).Success, false, "name impersonation cannot grant")
    equal(w.storeCalls, 0, "unauthorized callers cannot access DataStore")
    w:closeServer()
    equal(w:invoke(222, 20).Success, false, "shutdown rejects new grants")
    equal(w.storeCalls, 0, "shutdown cannot write grant")
end
do
    local w = world()
    equal(w:invoke(999, 20).Success, false, "offline target refused")
    w.recipient.Parent = nil
    equal(w:invoke(222, 20).Success, false, "departed target refused")
    equal(w.storeCalls, 0, "unavailable target cannot access DataStore")
end
for _, state in ipairs({"missing", "closing", "unavailable"}) do
    local w = world()
    if state == "missing" then w.sessions[w.recipient] = nil
    elseif state == "closing" then w.sessions[w.recipient].closing = true
    else w.sessions[w.recipient].persistent = false end
    equal(w:invoke(222, 20).Success, false, "profile readiness failure reported: " .. state)
    equal(w.storeCalls, 0, "unready profile refuses mutation")
    equal(w:saved(), 8, "unready profile keeps saved balance")
end
do
    local w = world()
    w:invoke(222, 2)
    equal(w:invoke(222, 2).Success, false, "immediate repeat throttled")
    equal(w.storeCalls, 1, "throttled repeat cannot write")
    contains(w:reply().Message, "3 seconds", "cooldown explains delay")
    w.now += 2.99
    w:invoke(222, 2)
    equal(w.storeCalls, 1, "full cooldown required")
    w.now += .01
    w:invoke(222, 2)
    equal(w:balance(), 12, "deliberate gift after cooldown accepted")
    w:invoke(222, 1, w.second)
    equal(w:balance(), 13, "developers have independent cooldowns")
end
do
    local w = world()
    w.yieldStore = true
    local thread = coroutine.create(function() w:invoke(222, 2) end)
    local ok, phase = coroutine.resume(thread)
    check(ok and phase == "STORE_WAIT", "grant waits for DataStore response")
    w.now += 100
    equal(w:invoke(222, 2).Success, false, "busy guard outlasts cooldown")
    equal(w.storeCalls, 1, "busy caller cannot start another write")
    check(coroutine.resume(thread), "pending gift finishes")
    equal(w:balance(), 10, "pending gift granted once")
    w:invoke(222, 2)
    equal(w.storeCalls, 1, "cooldown starts at save completion")
    equal(w.locks[w.recipient], nil, "completed gift releases lock")
end
for _, reason in ipairs({"recipient", "issuer", "server", "profile_closing", "profile_removed"}) do
    local w = world()
    w.locks[w.recipient] = true
    local thread = coroutine.create(function() w:invoke(222, 2) end)
    local ok, phase = coroutine.resume(thread)
    check(ok and phase == "LOCK_WAIT", "gift waits for existing mutation")
    if reason == "recipient" then w.recipient.Parent = nil
    elseif reason == "issuer" then w.issuer.Parent = nil
    elseif reason == "server" then w:closeServer()
    elseif reason == "profile_closing" then w.sessions[w.recipient].closing = true
    else w.sessions[w.recipient] = nil end
    w.locks[w.recipient] = nil
    check(coroutine.resume(thread), "post-wait cancellation finishes: " .. reason)
    equal(w:saved(), 8, "post-wait state recheck prevents gift: " .. reason)
    equal(w:reply().Success, false, "cancelled gift reports failure")
    equal(w.locks[w.recipient], nil, "cancelled gift releases lock")
end
for _, mode in ipairs({"before", "after"}) do
    local w = world()
    w.failBeforeCommit, w.failAfterCommit = mode == "before", mode == "after"
    local result = w:invoke(222, 2)
    equal(w.storeCalls, 1, "failed response never automatically retries currency delta")
    equal(w:saved(), mode == "after" and 10 or 8, "fake store models commit ambiguity")
    equal(w:balance(), 8, "unconfirmed response cannot fabricate session success")
    equal(result.Success, false, "unconfirmed response reports failure")
    contains(result.Message, "not confirmed", "uncertainty explained")
    contains(result.Message, "rejoin", "recipient instructed to refresh balance")
    contains(result.Message, "balance before repeating", "safe retry guidance given")
    equal(w.locks[w.recipient], nil, "failed save releases lock")
end
do
    local w = world()
    w.retryCallback, w.concurrentTokens = true, 15
    w:invoke(222, 2)
    equal(w.callbackCalls, 2, "UpdateAsync callback reruns after contention")
    equal(w.storeCalls, 1, "callback retry remains one transaction")
    equal(w:saved(), 17, "callback retry adds once to latest committed balance")
    equal(w:balance(), 17, "session adopts latest committed balance")
end
for _, balance in ipairs({9007199254740991, 0 / 0}) do
    local w = world()
    w.committed.u_222.Tokens = balance
    w.sessions[w.recipient].data.Tokens = balance
    equal(w:invoke(222, 2).Success, false, "overflow or NaN balance refuses gift")
    equal(#w.logs, 0, "invalid balance produces no successful audit log")
end
print(string.format("token grants: %d checks passed", checks))
'''


def main():
    luau = os.environ.get("LUAU_BIN") or shutil.which("luau")
    if not luau:
        raise SystemExit("Set LUAU_BIN or put luau on PATH")
    production_mutation = section(SERVER, "local function acquireMutation(player)", "-- Developer token gifts")
    production_grant = section(SERVER, "-- Developer token gifts", "local supportNameCache")
    source = "\n".join((COMMON, ACCESS, SERVER_PRELUDE, production_mutation,
        production_grant, SERVER_TAIL, SERVER_TESTS))
    with tempfile.TemporaryDirectory(prefix="token-grants-") as directory:
        path = Path(directory) / "token_grants.luau"
        path.write_text(source, encoding="utf-8")
        result = subprocess.run([luau, str(path)], capture_output=True, text=True, timeout=30)
    if result.stdout:
        print(result.stdout, end="")
    if result.stderr:
        print(result.stderr, end="")
    raise SystemExit(result.returncode)


if __name__ == "__main__":
    main()
