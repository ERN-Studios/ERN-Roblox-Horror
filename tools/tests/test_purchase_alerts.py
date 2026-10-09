"""Run the real ServerScriptService.PurchaseAlerts module under a fake Roblox host.

The module source is used verbatim; game/task/warn/DateTime are shadowed by the
prelude and HttpService, ServerStorage, the clock and task.wait are injected
through the module's own _configure seam. No Studio, no network, no secrets.
Set LUAU_BIN to the Luau executable, or put luau on PATH.
"""

from pathlib import Path
import os
import shutil
import subprocess
import tempfile

ROOT = Path(__file__).resolve().parents[2]
MODULE = (ROOT / "ServerScriptService/PurchaseAlerts.ModuleScript.lua").read_text(encoding="utf-8")
MONETIZATION = (ROOT / "ServerScriptService/ZyntraMonetization.Script.lua").read_text(encoding="utf-8")


def receipt_hook() -> str:
    """ProcessReceipt's alert block, verbatim out of the production file."""
    start = MONETIZATION.index("\t\t-- First-time grant only:")
    return MONETIZATION[start:MONETIZATION.index("\t\tlocal session = sessions[player]", start)]

PRELUDE = r'''
local checks = 0
local function check(value, message)
    checks += 1
    assert(value, message)
end
local function equal(actual, expected, message)
    check(actual == expected, message .. ": expected " .. tostring(expected) .. ", got " .. tostring(actual))
end
local function contains(actual, expected, message)
    check(type(actual) == "string" and string.find(actual, expected, 1, true) ~= nil,
        message .. ": " .. tostring(expected) .. " not in " .. tostring(actual))
end
local function missing(actual, expected, message)
    check(type(actual) ~= "string" or string.find(actual, expected, 1, true) == nil, message)
end

-- Deterministic JSON for the fake HttpService: keys sorted, test data only.
local function encode(value)
    local kind = type(value)
    if kind == "number" or kind == "boolean" then return tostring(value) end
    if kind == "string" then return '"' .. value .. '"' end
    local keys = {}
    for key in pairs(value) do table.insert(keys, key) end
    table.sort(keys)
    local parts = {}
    for _, key in ipairs(keys) do
        table.insert(parts, '"' .. key .. '":' .. encode(value[key]))
    end
    return "{" .. table.concat(parts, ",") .. "}"
end

-- Shadow the Roblox globals the module reads at load time.
local warn = function() end
local task = {wait = function() end, spawn = function(fn) fn() end}
local DateTime = {now = function() return {ToIsoDate = function() return "LOAD" end} end}
local game = {
    PlaceId = 0, JobId = "",
    GetService = function(_, name) return {Name = name, FindFirstChild = function() return nil end} end,
}

local Alerts = (function()
'''

HOST = r'''
end)()

local ENDPOINT = "http://127.0.0.1:8787/"
local TOKEN = "relay-token-n0t-a-real-secret"

local function host(opts)
    opts = opts or {}
    local h = {requests = {}, warns = {}, waits = {}, threads = {}, now = 1000}
    h.responses = opts.responses or {}
    local Http = {}
    function Http:GetSecret(name)
        if not opts.secrets then error("Secret " .. name .. " is not configured", 0) end
        return {AddPrefix = function(_, prefix) return "SECRET<" .. prefix .. name .. ">" end,
            Name = name}
    end
    function Http:JSONEncode(value) return encode(value) end
    function Http:RequestAsync(request)
        table.insert(h.requests, request)
        local outcome = h.responses[#h.requests] or opts.status or 200
        if type(outcome) == "string" then error(outcome, 0) end
        return {StatusCode = outcome, Success = outcome < 300, Body = "{}"}
    end
    local Storage = {}
    function Storage:FindFirstChild(name)
        if name ~= "PurchaseAlertConfig" or not opts.endpoint then return nil end
        return {GetAttribute = function(_, key)
            if key == "Endpoint" then return opts.endpoint end
            if key == "Token" then return opts.token end
            return nil
        end}
    end
    h.deps = {
        HttpService = Http,
        ServerStorage = Storage,
        wait = function(seconds) table.insert(h.waits, seconds) h.now += seconds end,
        clock = function() return h.now end,
        spawn = function(fn)
            local co = coroutine.create(fn)
            table.insert(h.threads, co)
            if not opts.defer then local ok, err = coroutine.resume(co) assert(ok, err) end
        end,
        warn = function(...)
            local parts = {}
            for index = 1, select("#", ...) do
                table.insert(parts, tostring((select(index, ...))))
            end
            table.insert(h.warns, table.concat(parts, " "))
        end,
        now = function() return "2026-09-14T10:11:12Z" end,
        placeId = 111,
        jobId = "job-a",
    }
    function h:flush()
        for _, co in ipairs(self.threads) do
            if coroutine.status(co) == "suspended" then
                local ok, err = coroutine.resume(co)
                assert(ok, err)
            end
        end
    end
    function h:start()
        Alerts._configure(self.deps)
        return self
    end
    return h
end

-- The exact field set ZyntraMonetization.ProcessReceipt passes.
local function alert(purchaseId, extra)
    local payload = {PurchaseId = purchaseId, ProductId = 3707755089, ProductKey = "Tokens4",
        ProductName = "4 Research Tokens", Kind = "Utility", RobuxSpent = 49,
        PlayerName = "SomePlayer", UserId = 40920547, IsStudio = false}
    for key, value in pairs(extra or {}) do payload[key] = value end
    return payload
end

local function notify(purchaseId, extra)
    Alerts.Notify(alert(purchaseId, extra))
end

-- Notify on its own thread: proves it neither throws nor yields its caller.
local function notifyIsolated(purchaseId, extra)
    local co = coroutine.create(function() notify(purchaseId, extra) end)
    local ok, err = coroutine.resume(co)
    check(ok, "Notify must never throw: " .. tostring(err))
    equal(coroutine.status(co), "dead", "Notify returns without yielding its caller")
end
'''

RECEIPT = r'''
-- The alert block of MarketplaceService.ProcessReceipt, sliced verbatim out of
-- ZyntraMonetization and given the locals it reads there.
local function receipt(opts)
    local PurchaseAlerts = opts.module
    local changed, alreadyGranted = opts.changed, opts.alreadyGranted
    local purchaseId = opts.purchaseId
    local receiptInfo = {PlayerId = 40920547, ProductId = 3707755089,
        PurchaseId = purchaseId, CurrencySpent = 49}
    local entry = {Key = "Tokens4", Kind = "Utility",
        Product = {Id = 3707755089, Name = "4 Research Tokens", Price = 49, TokenGrant = 4}}
    local spent = opts.spent or 49
    local player = {Name = "SomePlayer", UserId = 40920547}
    local RunService = {IsStudio = function() return opts.studio == true end}
    if changed or alreadyGranted then
RECEIPT_HOOK
    end
end
'''

TESTS = r'''
-- Not configured: one warn, no traffic, and Notify still safe to call.
do
    local h = host():start()
    notifyIsolated("p1")
    equal(#h.requests, 0, "unconfigured module sends nothing")
    equal(#h.warns, 1, "unconfigured module warns once")
    contains(h.warns[1], "[PurchaseAlerts] not configured; alerts disabled", "warn names the cause")
    notifyIsolated("p2")
    notifyIsolated("p3")
    equal(#h.warns, 1, "unconfigured module warns only once")
    equal(#h.requests, 0, "disabled module stays disabled")
end

-- Configured through the ServerStorage fallback: one POST, right shape.
do
    local h = host({endpoint = ENDPOINT, token = TOKEN}):start()
    notifyIsolated("p1")
    equal(#h.requests, 1, "configured module posts once")
    local request = h.requests[1]
    equal(request.Url, ENDPOINT, "posts to the configured endpoint")
    equal(request.Method, "POST", "alert is a POST")
    equal(request.Headers["Content-Type"], "application/json", "json content type")
    equal(request.Headers.Authorization, "Bearer " .. TOKEN, "bearer token header")
    contains(request.Body, '"purchaseId":"p1"', "body carries the PurchaseId")
    contains(request.Body, '"productId":3707755089', "body carries the product id")
    contains(request.Body, '"productKey":"Tokens4"', "body carries the product key")
    contains(request.Body, '"productName":"4 Research Tokens"', "body carries the product name")
    contains(request.Body, '"kind":"Utility"', "body carries the kind")
    contains(request.Body, '"robux":49', "body carries the Robux actually paid")
    contains(request.Body, '"playerName":"SomePlayer"', "body carries the player name")
    contains(request.Body, '"userId":40920547', "body carries the userId")
    contains(request.Body, '"placeId":111', "body carries the place id")
    contains(request.Body, '"jobId":"job-a"', "body carries the job id")
    contains(request.Body, '"timestamp":"2026-09-14T10:11:12Z"', "body carries an ISO timestamp")
    contains(request.Body, '"test":false', "a live purchase is not flagged as a test")
    equal(#h.warns, 0, "a delivered alert warns about nothing")
    equal(#h.waits, 0, "a first-try success never backs off")
end

-- Studio purchases are marked, not hidden.
do
    local h = host({endpoint = ENDPOINT, token = TOKEN}):start()
    notify("studio-1", {IsStudio = true, RobuxSpent = 0})
    contains(h.requests[1].Body, '"test":true', "a Studio purchase is flagged")
    contains(h.requests[1].Body, '"robux":0', "a Studio purchase reports zero paid")
end

-- Production path: Roblox Secrets win over the ServerStorage fallback, and the
-- URL is used as the opaque Secret object rather than as a readable string.
do
    local h = host({secrets = true, endpoint = ENDPOINT, token = TOKEN}):start()
    notify("p1")
    equal(#h.requests, 1, "secret-configured module posts once")
    equal(type(h.requests[1].Url), "table", "the Url stays an opaque Secret")
    equal(h.requests[1].Headers.Authorization, "SECRET<Bearer ZYNTRA_PURCHASE_ALERT_TOKEN>",
        "authorization is the prefixed Secret, never a plain token")
end

-- The profile's ReceiptIds is the durable dedupe; this is the server-lifetime one.
do
    local h = host({endpoint = ENDPOINT, token = TOKEN}):start()
    notify("p1")
    notify("p1")
    notify("p1", {RobuxSpent = 999})
    equal(#h.requests, 1, "a repeated PurchaseId is sent once")
    notify("p2")
    equal(#h.requests, 2, "a new PurchaseId still sends")
end

-- Retryable answers: server error, rate limit, timeout.
do
    local h = host({endpoint = ENDPOINT, token = TOKEN, responses = {500, 200}}):start()
    notify("p1")
    equal(#h.requests, 2, "a 500 is retried once and then succeeds")
    equal(#h.waits, 1, "one backoff between the two attempts")
    equal(h.waits[1], 2, "first backoff is 2 s")
    equal(#h.warns, 0, "a recovered send warns about nothing")
end
for _, status in ipairs({429, 408, 503}) do
    local h = host({endpoint = ENDPOINT, token = TOKEN, responses = {status, 200}}):start()
    notify("p1")
    equal(#h.requests, 2, "HTTP " .. status .. " is retried")
end

-- Everything else 4xx is a permanent refusal: drop it, say only the status.
do
    local h = host({endpoint = ENDPOINT, token = TOKEN, status = 403}):start()
    notify("p1")
    equal(#h.requests, 1, "a 403 is not retried")
    equal(#h.warns, 1, "a 403 warns once")
    contains(h.warns[1], "403", "the warn names the status code")
    equal(#h.waits, 0, "a permanent refusal never backs off")
    notify("p2")
    equal(#h.requests, 2, "a 403 does not disable the module")
end

-- Network failure: three attempts, 2 s then 5 s, then dropped.
do
    local h = host({endpoint = ENDPOINT, token = TOKEN, status = "HttpError: Timedout"}):start()
    notify("p1")
    equal(#h.requests, 3, "a throwing request is attempted three times")
    equal(#h.waits, 2, "two backoffs between three attempts")
    equal(h.waits[1], 2, "first backoff is 2 s")
    equal(h.waits[2], 5, "second backoff is 5 s")
    equal(#h.warns, 1, "an undelivered alert warns once")
    contains(h.warns[1], "not delivered after 3 attempts", "the warn says it gave up")
end

-- HttpEnabled off: stop after the first attempt for the life of the server.
do
    local h = host({endpoint = ENDPOINT, token = TOKEN,
        status = "Http requests are not enabled. Enable via game settings"}):start()
    notify("p1")
    equal(#h.requests, 1, "a disabled HttpService is not retried")
    equal(#h.warns, 1, "a disabled HttpService warns once")
    contains(h.warns[1], "alerts disabled", "the warn says alerts are off")
    notify("p2")
    notify("p3")
    equal(#h.requests, 1, "later alerts are not attempted")
    equal(#h.warns, 1, "later alerts do not warn again")
end

-- Rate limit: twenty per minute, the rest wait out the window.
do
    local h = host({endpoint = ENDPOINT, token = TOKEN}):start()
    for n = 1, 20 do notify("rate-" .. n) end
    equal(#h.requests, 20, "twenty alerts send inside one window")
    equal(#h.waits, 0, "twenty alerts need no rate wait")
    notify("rate-21")
    equal(#h.waits, 1, "the twenty-first alert waits")
    equal(h.waits[1], 60, "it waits out the remainder of the 60 s window")
    equal(#h.requests, 21, "and sends once the window has passed")
end

-- The HTTP work happens on the spawned worker, never on the receipt's thread.
do
    local h = host({endpoint = ENDPOINT, token = TOKEN, defer = true}):start()
    notifyIsolated("p1")
    equal(#h.requests, 0, "Notify does no network work on the calling thread")
    h:flush()
    equal(#h.requests, 1, "the worker sends the queued alert")
end

-- No warn may ever carry the endpoint or the token.
do
    local secrets = {"HTTP 403", "HttpError: Timedout",
        "Http requests are not enabled. Enable via game settings"}
    local warns = {}
    for _, status in ipairs(secrets) do
        local h = host({endpoint = ENDPOINT, token = TOKEN, status = status}):start()
        notify("p1")
        for _, text in ipairs(h.warns) do table.insert(warns, text) end
    end
    local h = host():start()
    notify("p1")
    for _, text in ipairs(h.warns) do table.insert(warns, text) end
    check(#warns >= 4, "every failure path warned")
    for _, text in ipairs(warns) do
        missing(text, TOKEN, "a warn leaked the token")
        missing(text, ENDPOINT, "a warn leaked the endpoint")
        missing(text, "127.0.0.1", "a warn leaked the relay host")
    end
end

-- The ProcessReceipt hook: only a first-time grant alerts, and a broken or
-- missing module cannot reach the receipt.
do
    local h = host({endpoint = ENDPOINT, token = TOKEN}):start()
    receipt({module = Alerts, changed = true, alreadyGranted = false, purchaseId = "r1"})
    equal(#h.requests, 1, "a first-time grant alerts once")
    contains(h.requests[1].Body, '"purchaseId":"r1"', "the alert carries the receipt's PurchaseId")
    contains(h.requests[1].Body, '"productKey":"Tokens4"', "the alert carries the product key")
    contains(h.requests[1].Body, '"productName":"4 Research Tokens"', "and the product name")
    contains(h.requests[1].Body, '"kind":"Utility"', "and the kind")
    contains(h.requests[1].Body, '"robux":49', "and the Robux ProcessReceipt measured")
    contains(h.requests[1].Body, '"test":false', "a live receipt is not flagged as a test")

    -- A Roblox retry of an already-granted receipt: granted again, alerted never.
    receipt({module = Alerts, changed = false, alreadyGranted = true, purchaseId = "r2"})
    equal(#h.requests, 1, "a receipt retry does not alert")

    receipt({module = Alerts, changed = true, alreadyGranted = true, purchaseId = "r3"})
    equal(#h.requests, 2, "a fresh grant alerts even when the retry flag is set")

    receipt({module = Alerts, changed = true, studio = true, purchaseId = "r4", spent = 0})
    contains(h.requests[3].Body, '"test":true', "a Studio receipt is flagged as a test")
    contains(h.requests[3].Body, '"robux":0', "a Studio receipt reports zero paid")
end
do
    local h = host({endpoint = ENDPOINT, token = TOKEN}):start()
    receipt({module = nil, changed = true, purchaseId = "r1"})
    receipt({module = {}, changed = true, purchaseId = "r2"})
    receipt({module = {Notify = function() error("module exploded", 0) end},
        changed = true, purchaseId = "r3"})
    equal(#h.requests, 0, "a missing or broken alert module sends nothing")
    check(true, "a missing or broken alert module cannot break a receipt")
end

print(string.format("purchase alerts: %d checks passed", checks))
'''


def main():
    luau = os.environ.get("LUAU_BIN") or shutil.which("luau")
    if not luau:
        raise SystemExit("Set LUAU_BIN or put luau on PATH")
    source = "\n".join((PRELUDE, MODULE, HOST,
                        RECEIPT.replace("RECEIPT_HOOK", receipt_hook()), TESTS))
    with tempfile.TemporaryDirectory(prefix="purchase-alerts-") as directory:
        path = Path(directory) / "purchase_alerts.luau"
        path.write_text(source, encoding="utf-8")
        result = subprocess.run([luau, str(path)], capture_output=True, text=True, timeout=30)
    if result.stdout:
        print(result.stdout, end="")
    if result.stderr:
        print(result.stderr, end="")
    raise SystemExit(result.returncode)


if __name__ == "__main__":
    main()
