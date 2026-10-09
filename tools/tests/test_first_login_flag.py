"""Run the real ZyntraMonetization loadProfile against a fake DataStore.

Proves the one thing the first-entry guide depends on: ZyntraFirstLogin is true
only when this load created the record, it is published BEFORE
ZyntraProfileLoaded, and a load that never commits does not spend it.

Only loadProfile is real. Profile normalization, dispatch handoff and the
attribute/push plumbing are stubbed; no Studio, no network, no DataStore.
Set LUAU_BIN to the official Luau executable, or put luau on PATH.
"""

from pathlib import Path
import os
import shutil
import subprocess
import tempfile

ROOT = Path(__file__).resolve().parents[2]
SERVER = (ROOT / "ServerScriptService/ZyntraMonetization.Script.lua").read_text(encoding="utf-8")

START = "local function loadProfile(player, loadState)"
STOP = '-- A throw and a "no" used to collapse into the same false'

PRELUDE = r'''
local checks = 0
local function check(value, message)
    checks += 1
    assert(value, message)
end
local function equal(actual, expected, message)
    check(actual == expected, message .. ": expected " .. tostring(expected)
        .. ", got " .. tostring(actual))
end
local function clone(value)
    if type(value) ~= "table" then return value end
    local result = {}
    for key, child in pairs(value) do result[key] = clone(child) end
    return result
end

-- Each world pastes loadProfile inside itself, so every scenario gets its own
-- upvalues: sessions, store and the attribute log.
local function world(options)
    options = options or {}
    local w = {attributeWrites = {}, warnings = {}, waits = {},
        storeCalls = 0, callbackCalls = 0, applyCalls = 0, pushCalls = 0,
        throwsLeft = options.throws or 0, guids = 0}
    if options.record then w.committed = {Tokens = 12, Settings = {}} end

    local sessions, pendingDispatchSnapshots = {}, {}
    local DISPATCH_HANDOFF_GRACE_SECONDS, DISPATCH_RECOVERY_RETRY_SECONDS = 30, 10
    local function warn(...) table.insert(w.warnings, {...}) end
    local task = {
        wait = function(seconds) table.insert(w.waits, seconds) end,
        spawn = function() end,   -- the dispatch-handoff tasks never run here
    }
    local os = {clock = function() return 0 end}
    local RunService = {IsStudio = function() return options.studio == true end}
    local HttpService = {}
    function HttpService:GenerateGUID()
        w.guids += 1
        return "guid" .. w.guids
    end
    local game = {JobId = "job"}
    local workspace = {Attributes = options.workspaceAttributes or {}}
    function workspace:GetAttribute(key) return self.Attributes[key] end

    local player = {Name = "Tester", UserId = 4242, Parent = true, Attributes = {}}
    function player:SetAttribute(key, value)
        self.Attributes[key] = value
        table.insert(w.attributeWrites, {Key = key, Value = value})
    end
    function player:GetAttribute(key) return self.Attributes[key] end
    w.player = player

    local store = {}
    function store:UpdateAsync(key, transform)
        w.storeCalls += 1
        w.lastKey = key
        if w.throwsLeft > 0 then
            w.throwsLeft -= 1
            error("DataStore unavailable")
        end
        if options.cancelDuring then w.loadState.cancelled = true end
        local runs = (w.storeCalls == 1 and options.reruns) or 1
        local result
        for _ = 1, runs do
            w.callbackCalls += 1
            result = transform(clone(w.committed))
            -- Roblox commits the callback's return value, and a conflict re-runs the
            -- callback against whatever won the race. Committing between runs models
            -- both: the second run sees the record the first one wrote.
            w.committed = clone(result)
        end
        return clone(result)
    end

    local function normalizeProfile(data)
        if type(data) ~= "table" then data = {} end
        data.Settings = data.Settings or {}
        local settings = data.Settings
        settings.MuteDispatchSessionClaims = settings.MuteDispatchSessionClaims or {}
        settings.MuteDispatchSessionEpoch = settings.MuteDispatchSessionEpoch or 0
        settings.MuteDispatchInputEpoch = settings.MuteDispatchInputEpoch or 0
        settings.MuteDispatchClosedEpoch = settings.MuteDispatchClosedEpoch or 0
        return data
    end
    local function newProfile() return normalizeProfile({}) end
    local function recoverProtectionReservation() end
    local function isDispatchPredecessorClosed() return true end
    local function dispatchSnapshotFromData() return nil end
    local function applyDispatchSnapshot() end
    local function recoverStaleDispatchPredecessor() return true end
    local function recordedSupportRobux() return 0 end
    local function queueSupportTotalSync() end
    local function applyAttributes() w.applyCalls += 1 end
    local function pushProfile() w.pushCalls += 1 end
'''

TAIL = r'''
    function w:run()
        self.loadState = {cancelled = false}
        loadProfile(self.player, self.loadState)
        return self.loadState
    end
    function w:session() return sessions[self.player] end
    -- Index of the first write of this exact key/value, for ordering assertions.
    function w:order(key, value)
        for index, entry in ipairs(self.attributeWrites) do
            if entry.Key == key and entry.Value == value then return index end
        end
    end
    return w
end
'''

TESTS = r'''
do  -- (a) no record: this load creates it, so this join is the first one
    local w = world()
    w:run()
    equal(w.storeCalls, 1, "one UpdateAsync")
    equal(w.lastKey, "u_4242", "keyed on the UserId")
    equal(w.player:GetAttribute("ZyntraFirstLogin"), true, "a brand-new account is a first login")
    equal(w.player:GetAttribute("ZyntraProfileLoaded"), true, "the profile loaded")
    equal(w:session().firstLogin, true, "the session carries the first login")
    equal(w:session().persistent, true, "a committed load is persistent")
    check(type(w.committed) == "table", "the callback's return value committed the record")
    check(w:order("ZyntraFirstLogin", true) < w:order("ZyntraProfileLoaded", true),
        "ZyntraFirstLogin is published before ProfileLoaded, never after")
end
do  -- (b) the record exists: a returning player, on this and every later join
    local w = world({record = true})
    w:run()
    equal(w.player:GetAttribute("ZyntraFirstLogin"), false,
        "an existing record is never a first login")
    equal(w:session().firstLogin, false, "the session carries the returning player")
    equal(w:session().persistent, true, "a returning player still loads persistently")
    equal(w.committed.Tokens, 12, "the existing record survives the claim")
    check(w:order("ZyntraFirstLogin", false) < w:order("ZyntraProfileLoaded", true),
        "the false is published before ProfileLoaded too")
end
do  -- (c) three throws: nothing committed, so no first login is spent
    local w = world({throws = 3})
    w:run()
    equal(w.storeCalls, 3, "three attempts before giving up")
    equal(w.player:GetAttribute("ZyntraFirstLogin"), false,
        "a load that never commits is not a first login -- the next one is")
    equal(w.player:GetAttribute("ZyntraProfileLoaded"), true, "the fallback profile still loads")
    equal(w:session().firstLogin, false, "the session agrees")
    equal(w:session().persistent, false, "a fallback profile is not persistent")
    equal(#w.warnings, 1, "the failure is warned once")
end
do  -- (d) conflict: Roblox re-runs the callback. The first run saw nil, the second
    -- saw the record that run wrote -- and only the LAST run's return value commits,
    -- so this join did not create the record and must not count as a first login.
    local w = world({reruns = 2})
    w:run()
    equal(w.callbackCalls, 2, "the callback ran twice")
    equal(w.storeCalls, 1, "a conflict re-run is still one transaction")
    equal(w.player:GetAttribute("ZyntraFirstLogin"), false,
        "the last callback run decides, and it saw an existing record")
    equal(w:session().firstLogin, false, "the session agrees")
end
do  -- a load cancelled while UpdateAsync is in flight publishes nothing at all
    local w = world({cancelDuring = true})
    w:run()
    equal(w:session(), nil, "a cancelled load installs no session")
    equal(w.player:GetAttribute("ZyntraFirstLogin"), nil, "no first login is published")
    equal(w.player:GetAttribute("ZyntraProfileLoaded"), false, "ProfileLoaded stays false")
    equal(w.applyCalls, 0, "a cancelled load applies no attributes")
end
do  -- Studio has no DataStore, so nothing can have existed: never a first login...
    local w = world({studio = true})
    w:run()
    equal(w.storeCalls, 0, "Studio never touches the DataStore")
    equal(w.player:GetAttribute("ZyntraFirstLogin"), false, "Studio is not a first login")
    equal(w:session().firstLogin, false, "the session agrees")
    equal(w:session().persistent, false, "Studio profiles are never persistent")
    -- ...unless the dev asks for one, to preview the guide in a play session.
    local dev = world({studio = true, workspaceAttributes = {DevSimulateFirstLogin = true}})
    dev:run()
    equal(dev.player:GetAttribute("ZyntraFirstLogin"), true,
        "DevSimulateFirstLogin previews the first-entry guide")
    check(dev:order("ZyntraFirstLogin", true) < dev:order("ZyntraProfileLoaded", true),
        "the Studio branch keeps the publish order")
end
print(string.format("first-login flag: %d checks passed", checks))
'''


def section(source, start, stop):
    begin = source.index(start)
    return source[begin:source.index(stop, begin)]


def main():
    luau = os.environ.get("LUAU_BIN") or shutil.which("luau")
    if not luau:
        raise SystemExit("Set LUAU_BIN or put luau on PATH")
    source = "\n".join((PRELUDE, section(SERVER, START, STOP), TAIL, TESTS))
    with tempfile.TemporaryDirectory(prefix="first-login-flag-") as directory:
        path = Path(directory) / "first_login_flag.luau"
        path.write_text(source, encoding="utf-8")
        result = subprocess.run([luau, str(path)], capture_output=True, text=True, timeout=30)
    if result.stdout:
        print(result.stdout, end="")
    if result.stderr:
        print(result.stderr, end="")
    raise SystemExit(result.returncode)


if __name__ == "__main__":
    main()
