"""Historical sales import (Trello #36): the REAL import block, normalizeProfile,
mutateIdempotent, syncSupportTotal and ProcessReceipt from ZyntraMonetization,
run under a fake DataStore with SYNTHETIC buyers -- no real user id or amount
appears in this file.

Covers: audited corrections preserve later purchases without double counting; a second
run commits nothing; a game pass is counted once and stays once under a second
export; donations are preserved; an offline buyer gets a profile and an ordered
store entry without logging in; two servers race for one claim; a failed
per-user write leaves the claim un-Done so the next server retries and lands
once; a live purchase after the import still counts normally; a buyer online
during the import keeps both their session copy and their new spend; no
entitlement (token, credit or grant) is ever created; an absent module and a
Studio session are silent no-ops. No Studio, no network. Set LUAU_BIN.
"""

from pathlib import Path
import os
import shutil
import subprocess
import tempfile

ROOT = Path(__file__).resolve().parents[2]
SERVER = (ROOT / "ServerScriptService/ZyntraMonetization.Script.lua").read_text(encoding="utf-8")
CONFIG = (ROOT / "ReplicatedStorage/ZyntraConfig.ModuleScript.lua").read_text(encoding="utf-8")


def section(start, stop):
    begin = SERVER.index(start)
    return SERVER[begin:SERVER.index(stop, begin)]


COMMON = r'''
local checks = 0
local function check(v, m) checks += 1; assert(v, m) end
local function eq(v, e, m) check(v == e, m .. ": expected " .. tostring(e) .. ", got " .. tostring(v)) end
local function clone(v)
    if type(v) ~= "table" then return v end
    local r = {}; for k, c in pairs(v) do r[k] = clone(c) end; return r
end
local Color3 = {fromRGB = function(r, g, b) return {R = r / 255, G = g / 255, B = b / 255} end}
local Config = (function()
'''

WORLD = r'''
end)()
-- Synthetic buyers. 101 has one counted and one uncounted product row, 102's
-- single row is already in both the recorded total AND ReceiptIds, 103 never
-- played and only ever bought on the storefront, 104 donated more than this
-- export can see, 105 is online while the import runs.
local function rows(sourceKey)
    return {
        {UserId = 101, AssetId = 77345358, AssetType = "Developer Product", Price = 29,
            Time = "2026-09-05T10:00:00Z", CsvId = "syn-101-a", Stream = "utility", Marker = "row:syn-101-a"},
        {UserId = 101, AssetId = 77345358, AssetType = "Developer Product", Price = 29,
            Time = "2026-09-12T10:00:00Z", CsvId = "syn-101-b", Stream = "utility", Marker = "row:syn-101-b"},
        {UserId = 102, AssetId = 77345358, AssetType = "Developer Product", Price = 29,
            Time = "2026-09-12T11:00:00Z", CsvId = "syn-102-a", Stream = "utility", Marker = "row:syn-102-a"},
        {UserId = 103, AssetId = 1941938256, AssetType = "Game Pass", Price = 99,
            Time = "2026-09-09T11:00:00Z", CsvId = "syn-103-a", Stream = "pass", Marker = "pass:1941938256"},
        {UserId = 103, AssetId = 10559217407, AssetType = "Private Server Product", Price = 10,
            Time = "2026-09-13T11:00:00Z", CsvId = "syn-103-b", Stream = "pass", Marker = "row:syn-103-b"},
        {UserId = 104, AssetId = 77665692, AssetType = "Developer Product", Price = 10,
            Time = "2026-09-10T08:00:00Z", CsvId = "syn-104-a", Stream = "donation", Marker = "row:syn-104-a"},
        {UserId = 105, AssetId = 77345358, AssetType = "Developer Product", Price = 29,
            Time = "2026-09-14T08:00:00Z", CsvId = "syn-105-a", Stream = "utility", Marker = "row:syn-105-a"},

    }
end

local function world(opts)
    opts = opts or {}
    local w = {db = opts.db or {}, ranks = opts.ranks or {}, attrs = opts.attrs or {}, now = 1000,
        studio = opts.studio == true, jobId = opts.jobId or "job-a", warnings = {}, prints = {},
        calls = 0, writes = 0, cacheCalls = 0}
    local function warn(...) table.insert(w.warnings, table.concat({...}, " ")) end
    local function print(...) table.insert(w.prints, table.concat({...}, " ")) end
    local os = {time = function() return w.now end, clock = function() return w.now end}
    local game = {JobId = w.jobId}
    local task = {}
    -- Every wait in the import and in mutateIdempotent is a throttle, not a
    -- synchronisation point, so the whole run is driven straight through.
    function task.wait() return 0 end
    function task.spawn(fn, ...) fn(...) end
    task.defer = task.spawn
    local serverClosing = false
    local Players = {roster = {}}
    function Players:GetPlayerByUserId(id) return self.roster[id] end
    function Players:GetNameFromUserIdAsync(id) return "Buyer" .. id end
    local function newPlayer(userId)
        local p = {Name = "Buyer" .. userId, UserId = userId, Parent = Players, attributes = {}}
        function p:SetAttribute(k, v) self.attributes[k] = v end
        function p:GetAttribute(k) return self.attributes[k] end
        Players.roster[userId] = p
        return p
    end
    local RunService = {IsStudio = function() return w.studio end}
    local Enum = {ProductPurchaseDecision = {PurchaseGranted = "Granted", NotProcessedYet = "Retry"}}
    local MarketplaceService = {}
    local sessions, mutationLocks = {}, {}
    local ACCESSIBILITY_SETTINGS = Config.AccessibilitySettings
    local PERCENT_PER_LEVEL = math.floor(Config.TokenPercentPerLevel * 100 + .5)
    local SUPPORT_LEADERBOARD_SIZE = Config.SupportLeaderboardSize
    local supportStatus, supportRows = {}, {}
    for n = 1, SUPPORT_LEADERBOARD_SIZE do supportRows[n] = {} end
    local ServerStorage = {attrs = w.attrs}
    function ServerStorage:SetAttribute(k, v) self.attrs[k] = v end
    function ServerStorage:FindFirstChild(name)
        if name ~= "ZyntraSalesBackfill" then return nil end
        return w.module
    end
    -- The import requires a ModuleScript instance; standalone Luau has no such
    -- require, so it reads the table the fake instance carries.
    local function require(module) return module.Source end
    local store = {}
    function store:UpdateAsync(key, transform)
        w.calls += 1
        if w.failKey == key then error("DataStore unavailable for " .. key) end
        local result = transform(clone(w.db[key]))
        if result then w.db[key] = clone(result); w.writes += 1 end
        return clone(result)
    end
    local supportStore = {}
    function supportStore:UpdateAsync(key, transform)
        w.cacheCalls += 1
        local result = transform(w.ranks[key]); w.ranks[key] = result; return result
    end
    function supportStore:GetSortedAsync(_, count)
        local list = {}
        for k, v in pairs(w.ranks) do table.insert(list, {key = k, value = v}) end
        table.sort(list, function(a, b) return a.value > b.value end)
        while #list > count do table.remove(list) end
        return {GetCurrentPage = function() return list end}
    end
    local function applyHazmatColor() end
    local function reassertPendingAccessibility() end
    local function reentryEligible() return false end
    local function useReentry() end
    local PurchaseAlerts = nil
    local function pushProfile(p, message, tone)
        w.lastPush = {userId = p.UserId, message = message, tone = tone}
    end
'''

TAIL = r'''
    -- Stubbed on purpose: the receipt path's own coalescing worker is proven by
    -- test_support_product_receipts; here it only has to reach the ordered store.
    local function queueSupportTotalSync(userId, total) syncSupportTotal(userId, total) end
'''

BOOT = r'''
    w.source = {SourceKey = opts.sourceKey or "src_a", Sha256 = "sha_a", Rows = opts.rows or rows(), Baselines = {
        ["101"]={DonationRobux=0,UtilityRobux=29,ReceiptIds={"live-a","live-old"}},
        ["102"]={DonationRobux=0,UtilityRobux=29,ReceiptIds={"syn-102-a"}},
        ["103"]={DonationRobux=0,UtilityRobux=0,ReceiptIds={}},
        ["104"]={DonationRobux=10,UtilityRobux=0,ReceiptIds={"live-b"}},
        ["105"]={DonationRobux=0,UtilityRobux=0,ReceiptIds={"old105"}},
    }}
    if not opts.noModule then
        local carried = opts.badModule and {} or w.source
        w.module = {Source = carried, IsA = function(_, class) return class == "ModuleScript" end}
    end
    w.run = runSalesImport
    w.sessions, w.players, w.market, w.newPlayer = sessions, Players, MarketplaceService, newPlayer
    w.normalize, w.total = normalizeProfile, recordedSupportRobux
    function w:profile(userId) return self.db["u_" .. userId] end
    function w:online(userId, data)
        local p = newPlayer(userId)
        self.db["u_" .. userId] = normalizeProfile(data or self.db["u_" .. userId])
        sessions[p] = {data = normalizeProfile(clone(self.db["u_" .. userId])), persistent = true}
        return p
    end
    function w:receipt(productKey, paid, id, userId)
        local product = Config.Products[productKey] or Config.Donations[productKey]
        return MarketplaceService.ProcessReceipt({PlayerId = userId or 105, ProductId = product.Id,
            PurchaseId = id, CurrencySpent = paid})
    end
    return w
end

-- The starting state every scenario shares: 101 has one of its two rows already
-- recorded, 102 has its only row recorded AND acknowledged, 104 donated 40 R$
-- before this export's window, 103 has no profile at all.
local function seed(w)
    w.db.u_101 = w.normalize({UtilityRobux = 29, Tokens = 3, ReceiptIds = {"live-a", "live-old"}})
    w.db.u_102 = w.normalize({UtilityRobux = 29, Tokens = 1, ReceiptIds = {"syn-102-a"}})
    w.db.u_105 = w.normalize({ReceiptIds={"old105"}})
    w.db.u_104 = w.normalize({DonationRobux = 40, ReceiptIds = {"live-b", "live-c"}})
    return w
end

-- Ceiling, per-row markers, readback, and the streams that must not move.
do
    local w = seed(world())
    local online = w:online(105, {UtilityRobux = 0, Tokens = 5, ReceiptIds={"old105"}})
    w.run()
    eq(w:profile(101).UtilityRobux, 58, "the uncounted row is added, the counted one is not")
    eq(w:profile(102).UtilityRobux, 29, "a stream the live total already covers never grows")
    eq(w:profile(103).PassRobux, 109, "pass and private server spend added in full")
    eq(w:profile(103).UtilityRobux, 0, "storefront spend never lands in the product stream")
    eq(w:profile(104).DonationRobux, 40, "a donation total larger than the export is never lowered")
    eq(w:profile(105).UtilityRobux, 29, "an online buyer's profile is written too")
    eq(w.attrs.ZyntraSalesImportRowsInvalid, 0, "the bad user id and the unknown stream are refused")
    eq(w.attrs.ZyntraSalesImportBuyers, 5, "only the five valid buyers are touched")
    eq(w.attrs.ZyntraSalesImportRowsApplied, 7, "five rows moved a total")
    eq(w.attrs.ZyntraSalesImportRowsAlreadyCounted, 0, "two rows were already covered")
    eq(w.attrs.ZyntraSalesImportProfilesChanged, 5, "every buyer commits at least its markers")
    eq(w.attrs.ZyntraSalesImportProfilesFailed, 0, "nothing failed")
    eq(w.attrs.ZyntraSalesImportStatus, "done", "the run reports done")
    eq(w.attrs.ZyntraSalesImportSource, "src_a", "the source key is reported")
    -- The export Id is measured against ReceiptIds, never trusted as one.
    eq(w.attrs.ZyntraSalesImportIdMatches, 0, "the one export id that is a receipt id is counted")
    eq(w.attrs.ZyntraSalesImportAmbiguous, 0, "104 holds two receipts the export cannot see")
    check(#w.prints == 1, "exactly one summary line")

    -- No entitlement is ever created by recording spend.
    eq(w:profile(101).Tokens, 3, "no tokens granted")
    eq(w:profile(103).Tokens, 0, "a profile created by the import starts empty")
    eq(w:profile(103).ReentryCredits, 0, "no re-entry credit granted")
    eq(w:profile(103).Grants.Supporter, false, "owning the pass in the export grants nothing")
    eq(#w:profile(101).ReceiptIds, 2, "no receipt id is invented")
    eq(w:profile(103).Settings.LobbyBriefingPlayed, false, "a created profile still gets its first-entry guide")

    -- Offline buyers reach the board without ever logging in.
    eq(w.ranks.u_103, 109, "an offline buyer is ranked from the import alone")
    eq(w.ranks.u_101, 58, "the ordered store carries the raised total")
    eq(w.ranks.u_104, 40, "a preserved donation still syncs")

    -- The online buyer's session copy adopted the write rather than lagging.
    eq(w.sessions[online].data.UtilityRobux, 29, "session copy adopts the imported total")
    eq(online.attributes.ZyntraRecordedSupportRobux, 29, "published attribute follows")
    eq(online.attributes.ZyntraPassRobux, 0, "the new stream is published")

    -- Idempotence: a second run commits nothing at all.
    local writesBefore = w.writes
    w.now += 7200
    w.run()
    eq(w.attrs.ZyntraSalesImportStatus, "claim-held", "a finished source is never claimed again")
    eq(w.writes, writesBefore, "the finished claim stops the second run before any write")
    -- Even with the claim gone, the row markers alone stop every amount.
    w.db["salesimport_src_a"] = nil
    w.run()
    eq(w:profile(101).UtilityRobux, 58, "re-running adds nothing")
    eq(w:profile(103).PassRobux, 109, "re-running never pays the pass twice")
    eq(w.attrs.ZyntraSalesImportRowsApplied, 0, "a re-run applies no rows")
    eq(w.attrs.ZyntraSalesImportProfilesChanged, 0, "a re-run changes no profile")
end

-- A second export that overlaps the first: the pass marker is keyed by pass id,
-- so neither a repeated export row nor a future live pass detector pays twice.
do
    local w = seed(world())
    w.run()
    local second = world({db = w.db, ranks = w.ranks, sourceKey = "src_b"})
    second.run()
    eq(second:profile(103).PassRobux, 109, "an overlapping export never re-pays the pass")
    eq(second:profile(101).UtilityRobux, 58, "an overlapping export never re-adds a product row")
    eq(second:profile(103).SalesImport.Sources.src_a, true, "the first source marker survives")
    eq(second:profile(103).SalesImport.Sources.src_b, true, "a source that changes nothing writes no marker")
    eq(second:profile(103).SalesImport.Rows["pass:1941938256"], true, "the pass is keyed by pass id")
    eq(second.attrs.ZyntraSalesImportProfilesChanged, 1, "a fully overlapping export commits nothing")
end

-- Spend recorded after the export still counts, on top of the import.
do
    local w = seed(world())
    local player = w:online(105, {UtilityRobux = 0, Tokens = 0, ReceiptIds={"old105"}})
    w.run()
    eq(w:profile(105).UtilityRobux, 29, "the imported row landed")
    eq(w:receipt("EmergencyReentry", 29, "fresh-receipt"), "Granted", "a new purchase is granted")
    eq(w:profile(105).UtilityRobux, 58, "a new live purchase adds on top of the import")
    eq(w:profile(105).ReentryCredits, 1, "the new purchase still grants its benefit")
    eq(w.ranks.u_105, 58, "the board follows the new purchase")
    eq(w:receipt("EmergencyReentry", 29, "fresh-receipt"), "Granted", "the retry is acknowledged")
    eq(w:profile(105).UtilityRobux, 58, "a receipt retry never doubles")
end

-- An import that runs while the buyer is mid-session keeps both sides.
do
    local w = seed(world())
    local player = w:online(105, {UtilityRobux = 0, Tokens = 0, ReceiptIds={"old105"}})
    eq(w:receipt("EmergencyReentry", 29, "during-a"), "Granted", "the buyer spends before the import")
    w.run()
    eq(w:profile(105).UtilityRobux, 58, "old missing sale plus later receipt both survive")
    eq(w.sessions[player].data.UtilityRobux, 58, "the session copy includes old and later spend")
    eq(w:profile(105).ReentryCredits, 1, "the import leaves the session's benefit alone")
    eq(w:profile(105).SalesImport.Rows["row:syn-105-a"], true, "the row is still marked, never revisited")
end

-- A buyer who leaves mid-import still lands, through the offline path.
do
    local w = seed(world())
    local player = w:online(105, {UtilityRobux = 0, Tokens = 0, ReceiptIds={"old105"}})
    player.Parent = nil
    w.run()
    eq(w:profile(105).UtilityRobux, 29, "a departing buyer is written anyway")
    eq(w.attrs.ZyntraSalesImportProfilesFailed, 0, "one buyer leaving does not fail the source")
    eq(w.db["salesimport_src_a"].Done, true, "and does not leave the source open")
    eq(w.ranks.u_105, 29, "the departing buyer still reaches the board")
end

-- Two servers, one claim.
do
    local shared = {}
    local ranks = {}
    local a = seed(world({db = shared, ranks = ranks, jobId = "job-a"}))
    local b = world({db = shared, ranks = ranks, jobId = "job-b"})
    a.run()
    b.run()
    eq(b.attrs.ZyntraSalesImportStatus, "claim-held", "the second server stands down")
    eq(a:profile(101).UtilityRobux, 58, "the first server did the work")
    eq(b.calls, 1, "the loser spends one claim read, nothing more")
    eq(b.writes, 0, "and commits nothing at all")
end

-- A per-user failure leaves the claim un-Done, and the retry lands once.
do
    local w = seed(world())
    w.failKey = "u_103"
    w.run()
    eq(w.attrs.ZyntraSalesImportProfilesFailed, 1, "the failed buyer is reported")
    eq(w.attrs.ZyntraSalesImportStatus, "incomplete", "the run reports itself incomplete")
    eq(w:profile(103), nil, "the failed buyer committed nothing")
    eq(w.db["salesimport_src_a"].Done, false, "an incomplete run never marks the source done")
    local retry = world({db = w.db, ranks = w.ranks, jobId = "job-b"})
    retry.now = w.now + 7200
    retry.run()
    eq(retry:profile(103).PassRobux, 109, "the retry delivers the missing buyer")
    eq(retry:profile(101).UtilityRobux, 58, "and adds nothing to the buyers that already landed")
    eq(retry.attrs.ZyntraSalesImportRowsApplied, 2, "only the missing rows apply on the retry")
    eq(retry.db["salesimport_src_a"].Done, true, "a clean retry closes the source")
end

-- Reject drift before changing any field or marking the source.
for _, mode in {"missing-receipt", "reduced-total", "missing-baseline", "bad-count"} do
    local w = seed(world())
    if mode == "missing-receipt" then w.db.u_101.ReceiptIds = {"live-a"}
    elseif mode == "reduced-total" then w.db.u_101.UtilityRobux = 10
    elseif mode == "missing-baseline" then w.source.Baselines["101"] = nil
    else w.source.Baselines["101"].ReceiptIds = {"live-a"} end
    local before = w.db.u_101.UtilityRobux
    w.run()
    eq(w.db.u_101.UtilityRobux, before, mode .. " cannot mutate money")
    eq(w.db.u_101.SalesImport.Sources.src_a, nil, mode .. " cannot mark source")
    eq(w.db.salesimport_src_a.Done, false, mode .. " leaves job incomplete")
end

-- Later receipts before migration are additive, not a reason to use max().
do
    local w=seed(world())
    w.db.u_101.UtilityRobux += 30
    table.insert(w.db.u_101.ReceiptIds,"after-export")
    w.run()
    eq(w.db.u_101.UtilityRobux,88,"58 export + 30 later; ceiling would wrongly give 59")
end

-- Invalid rows abort the entire source before a claim is acquired.
do
    local w=seed(world())
    table.insert(w.source.Rows,{UserId=0,Price=5,Stream="utility",Marker="bad"})
    w.run()
    eq(w.writes,0,"invalid rows never produce a partial import")
    eq(w.attrs.ZyntraSalesImportStatus,"invalid-rows","invalid source reports refusal")
end

-- Absent module, unusable module, and Studio are all no-ops.
do
    local w = seed(world({noModule = true}))
    w.run()
    eq(w.attrs.ZyntraSalesImportStatus, "no-module", "an absent module is reported, not warned")
    eq(w.writes, 0, "an absent module writes nothing")
    eq(#w.warnings, 0, "an absent module is the normal state and stays quiet")

    local bad = seed(world({badModule = true}))
    bad.run()
    eq(bad.attrs.ZyntraSalesImportStatus, "bad-module", "a malformed module is refused")
    eq(bad.writes, 0, "a malformed module writes nothing")
    eq(#bad.warnings, 1, "and is warned about exactly once")

    local studio = seed(world({studio = true}))
    studio.run()
    eq(studio.attrs.ZyntraSalesImportStatus, "skipped-studio", "Studio never imports")
    eq(studio.writes, 0, "Studio writes no profile")
    eq(studio.calls, 0, "Studio never even reads the claim")
end

-- normalizeProfile is what makes the markers permanent.
do
    local w = world()
    local kept = w.normalize({SalesImport = {Sources = {src_a = true}, Rows = {["pass:1"] = true,
        [string.rep("x", 65)] = true, bad = "yes", [7] = true}}})
    eq(kept.SalesImport.Sources.src_a, true, "a source marker survives a reload")
    eq(kept.SalesImport.Rows["pass:1"], true, "a row marker survives a reload")
    eq(kept.SalesImport.Rows[string.rep("x", 65)], nil, "an over-long key is dropped")
    eq(kept.SalesImport.Rows.bad, nil, "a non-true value is dropped")
    eq(kept.SalesImport.Rows[7], nil, "a non-string key is dropped")
    local fresh = w.normalize(nil)
    eq(fresh.PassRobux, 0, "a fresh profile starts with an empty pass stream")
    eq(w.total({DonationRobux = 5, UtilityRobux = 7, PassRobux = 11}), 23, "all three streams are recorded support")
end

print(string.format("leaderboard backfill: %d checks passed (actual import block + normalizeProfile + mutateIdempotent + ProcessReceipt; fake DataStore)", checks))
'''


def check_generator():
    """The generator's classification, on a synthetic export. Unmapped asset ids
    must abort rather than be guessed into a stream."""
    import importlib.util

    spec = importlib.util.spec_from_file_location(
        "generate_backfill", ROOT / "tools/leaderboard_backfill/generate_backfill.py"
    )
    gen = importlib.util.module_from_spec(spec)
    spec.loader.exec_module(gen)

    header = "Id,Buyer User Id,Date and Time,Location,Location Id,Universe Id,Universe,Asset Id,Asset Name,Asset Type,Status,Revenue,Price\n"

    def line(csv_id, user, asset, name, kind, status="Paid", price="29.0", universe="10559217407"):
        return f"{csv_id},{user},2026-09-10T00:00:00.000Z,Game,1,{universe},Game,{asset},{name},{kind},{status},20.0,{price}\n"

    body = (
        line("id-a", 101, 77345358, "Re-entry", "Developer Product")
        + line("id-b", 102, 77665692, "Signal", "Donate", price="10.0")  # unknown type -> asset map
        + line("id-c", 103, 1941938256, "Supporter", "Game Pass", price="99.0")
        + line("id-d", 103, 10559217407, "Server", "Private Server Product", price="10.0")
        + line("id-a", 104, 77345358, "Re-entry", "Developer Product")  # duplicate export id
        + line("id-e", 0, 77345358, "Re-entry", "Developer Product")  # no buyer
        + line("id-f", 105, 77345358, "Re-entry", "Developer Product", status="Refunded")
        + line("id-g", 106, 77345358, "Re-entry", "Developer Product", universe="7")
        + line("id-h", 107, 77345358, "Re-entry", "Developer Product", price="29.5")
    )
    with tempfile.TemporaryDirectory(prefix="backfill-gen-") as directory:
        path = Path(directory) / "synthetic.csv"
        path.write_text(header + body, encoding="utf-8")
        sha, rows, skipped = gen.build(path, "src_test")
        assert len(rows) == 4, rows
        assert len(skipped) == 5, skipped
        streams = {row["CsvId"]: (row["Stream"], row["Marker"], row["Price"]) for row in rows}
        assert streams["id-a"] == ("utility", "row:id-a", 29), streams
        assert streams["id-b"] == ("donation", "row:id-b", 10), streams
        assert streams["id-c"] == ("pass", "pass:1941938256", 99), streams
        assert streams["id-d"] == ("pass", "row:id-d", 10), streams

        path.write_text(header + line("id-x", 108, 999999, "Mystery", "Developer Product"), encoding="utf-8")
        try:
            gen.build(path, "src_test")
        except SystemExit as error:
            assert "Unmapped" in str(error), error
        else:
            raise AssertionError("an unmapped asset id must abort the generator")

        try:
            gen.main([str(path), str(Path(directory) / "out.lua"), "--source-key", "src_test", "--profile-audit", str(path)])
        except SystemExit as error:
            assert "Unmapped" in str(error) or "_local" in str(error), error
        else:
            raise AssertionError("the generator must refuse to write buyer data outside _local/")
    return len(rows), len(skipped)


def main():
    luau = os.environ.get("LUAU_BIN") or shutil.which("luau")
    if not luau:
        raise SystemExit("Set LUAU_BIN or put luau on PATH")
    kept, skipped = check_generator()
    source = "\n".join(
        (
            COMMON,
            CONFIG,
            WORLD,
            section("local function colorData", "local function isDispatchPredecessorClosed"),
            section("local function accessibilityValue", "-- The switch a player"),
            section("local function publicProfile", "local tagCharacters"),
            section("local function applyAttributes", "local function enrichedPublicProfile"),
            section("local function acquireMutation", "-- Developer token gifts"),
            section("local supportNameCache", "-- Outer retries are safe"),
            section("-- Outer retries are safe", "\nlocal function protectionOwnsLease"),
            TAIL,
            section("local productById", "\nPlayers.PlayerAdded:Connect(setupPlayer)"),
            section("-- SALES_IMPORT_20260915", "-- SALES_IMPORT_BOOT"),
            BOOT,
        )
    )
    with tempfile.TemporaryDirectory(prefix="leaderboard-backfill-") as directory:
        path = Path(directory) / "leaderboard_backfill.luau"
        path.write_text(source, encoding="utf-8")
        result = subprocess.run([luau, str(path)], capture_output=True, text=True, timeout=120)
    if result.stdout:
        print(result.stdout, end="")
    if result.stderr:
        print(result.stderr, end="")
    if result.returncode == 0:
        print(f"generator: {kept} rows classified, {skipped} refused, unmapped asset ids abort")
    raise SystemExit(result.returncode)


if __name__ == "__main__":
    main()
