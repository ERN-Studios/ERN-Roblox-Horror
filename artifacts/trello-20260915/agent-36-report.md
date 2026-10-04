# Agent A36 — Trello #36 "Donation leaderboard: Include all in-game purchases"

> Historical Claude working report. The ceiling reconciliation described below
> was rejected and replaced by an audited per-stream delta before publication.
> Current result: publication-and-import.md and leaderboard-reconciliation-proof.md.

Opus 5 (1M). Working copy `G:\Roblox\MongoTV`. No git, no Studio, no Trello touched.
Buyer-level data stayed under `_local/`; nothing below is per-buyer.

---

## 1. Design

### 1.1 What the profile actually stores per live receipt

`ProcessReceipt` stores, in one `store:UpdateAsync` transaction:

- `table.insert(data.ReceiptIds, purchaseId)` — **an opaque string, nothing else**.
- `data.DonationRobux += spent` or `data.UtilityRobux += spent` — **a running total**.

That is the whole record. There is **no per-receipt product id, no amount, no
timestamp** anywhere in the profile. `ReceiptIds` is an unordered-in-practice
array of ids; `DonationRobux`/`UtilityRobux` are sums with no provenance.

Consequences that drove every decision below:

- A CSV row **cannot** be matched to "the receipt that already counted it".
  Not by product (not stored), not by amount (not stored), not by time (not
  stored). The only candidate key is the id itself.
- Even a perfect id match would **not** prove the amount was counted: before
  commit `715e4d9` (2026-09-10 19:15 CEST, v1824) `ProcessReceipt` appended the
  PurchaseId to `ReceiptIds` but had **no `UtilityRobux` field at all**. Those
  receipts are acknowledged and uncounted. `DonationRobux` has existed since
  `a686ef3` (2026-08-27), i.e. for the whole export window.

### 1.2 The CSV `Id` ↔ `PurchaseId` relationship — what I found

**Undetermined, and deliberately not depended on.**

- All 44 export ids are 22 characters over the standard base64 alphabet
  (`A–Za–z0–9+/`, verified — `+` and `/` both occur), i.e. 16 raw bytes. That is
  the shape of a base64-encoded GUID.
- The repo contains **no recorded sample of a real `receiptInfo.PurchaseId`** —
  I grepped every `.lua`, `.py` and `.md` including `.studio-push-backups/`.
  Every occurrence is the variable, never a value.
- So the equality can only be settled against live profile data, which needs a
  live server. Codex reports the same (no match established).

The import therefore **measures** the relationship instead of assuming it: for
every row it checks whether its `CsvId` is present in that buyer's `ReceiptIds`
and reports the count as `ServerStorage.ZyntraSalesImportIdMatches`. Nothing in
the arithmetic reads that number. After the first live run the lead will know
the answer as a fact.

### 1.3 The overlap rule — per-stream ceiling

Three streams, classified per row by the generator:

| stream | rows in this export | written live by | reconciliation |
|---|---|---|---|
| `utility` | 38 (Emergency Re-entry) | `ProcessReceipt`, since 2026-09-10 | ceiling |
| `donation` | 2 (Donate Signal) | `ProcessReceipt`, since 2026-08-27 | ceiling |
| `pass` | 4 (2 game passes, 2 private servers) | **nothing, ever** | added in full |

For a ceiling stream, per buyer:

```
newTotal = max(storedTotal, sum of that buyer's export rows in that stream)
```

**Proof it can never double count.** Let `T` be what the buyer truly spent in
that stream. `storedTotal ≤ T` (it is a sum of real receipts). `exportTotal ≤ T`
(every row is a real completed sale by that buyer in that stream). Therefore
`max(storedTotal, exportTotal) ≤ T`. It is also monotone — it never lowers an
existing total — so pre-window donations and post-export purchases already in
the profile survive untouched. This holds **whatever** the CSV `Id` turns out to
be, which is exactly why it was chosen over id matching.

**Why this beats per-row id matching even if the ids do match.** A per-row
"skip if `CsvId ∈ ReceiptIds`" rule would skip the 6 pre-2026-09-10 Developer
Product rows (157 R$ gross) whose ids are in `ReceiptIds` but whose amounts were
never recorded — the precise gap card #36 exists to close. The ceiling recovers
them without needing to know which rows those are, and self-corrects for the
fuzzy rolling-deploy boundary (old servers kept running the amount-less build
for hours after the publish).

For the `pass` stream there is no live writer, so rows are added in full, guarded
by permanent per-row markers.

### 1.4 Game passes — counted exactly once

A game pass row's marker key is **`pass:<assetId>`**, not the export row id. A
Roblox account owns a pass at most once, so this key is the pass itself. Any
future live pass-purchase recording must write the **same** key (e.g. in
`refreshPasses`/`PromptGamePassPurchaseFinished`) and skip when it is already
set; then neither path can pay the same pass twice, and a re-export of the same
pass row is a no-op. Tested (`"the pass is keyed by pass id"`, and a second
overlapping export commits nothing).

Note: asset `1978617781` ("ZYNTRA Support — 20K", 20 000 R$ — 94% of the export's
gross) is **not in `ZyntraConfig.Passes`**. It grants nothing in game and the
import grants nothing either; it only records spend. Asset `1941938256` is
`Config.Passes.Supporter`, whose token grant is handled by `refreshPasses` from
real ownership and is untouched here.

### 1.5 Private server products

Included as gross spend, in the `pass` stream. Reasons: they are real Robux the
player spent on this universe, they never reach `ProcessReceipt` (so there is no
overlap risk at all), and the card title is "include all in-game purchases".
They **repeat** (one row per server bought), so their marker is `row:<csvId>`,
not an asset key. Their CSV `Asset Id` equals the universe id, so they are
classified by `Asset Type`, never by asset id.

### 1.6 Donations preserved

`DonationRobux` is a ceiling stream, so it is never lowered and never re-added.
Both Donate Signal rows are dated 2026-09-10, well inside the period during which
`ProcessReceipt` already recorded donation amounts, so the expected contribution
is 0 — the ceiling reaches that conclusion without needing to know it. A buyer
whose stored donation total is *larger* than the export (pre-window donations)
keeps the larger number. Tested.

### 1.7 Per-source import markers and permanent idempotence

Two levels, both permanent:

- **Per profile:** `data.SalesImport = { Sources = {[sourceKey]=true}, Rows = {[marker]=true} }`.
  `normalizeProfile` rebuilds both from validated string keys (≤64 bytes,
  value must be `true`) and **never truncates** — same discipline as
  `ReceiptIds`, and for the same reason. When every marker for a buyer is
  already set, the transform returns `false`, which **cancels** the
  `UpdateAsync` (the documented 2026-09-05 write discipline); a re-run costs one
  read per buyer and commits nothing.
- **Global, per source:** DataStore key `salesimport_<sourceKey>` in
  `ZyntraPlayerData_v1` (no collision with the `u_<id>` namespace), holding
  `{JobId, At, Sha, Done, Applied, Failed}`. `Done = true` blocks the source
  forever. An incomplete run leaves `Done = false`; the claim then expires after
  `SALES_IMPORT_CLAIM_SECONDS` (3600) and the next server redoes the whole
  source — safe, because every per-user write is a max or marker-guarded.

`sourceKey` for this export is **`sales_20260915`**, sha256
`97fb4a8d30be0e2e2da18e6bed3a626446bb35336a61a25d99847ce8f6b95edc` (regenerated
and verified from the file, not copied).

A profile the source contributes nothing to gets **no** `Sources` entry — the
write is cancelled rather than committed for provenance alone. The global claim
record is the per-source marker that matters.

### 1.8 Offline buyers, concurrency, and buyers who are online

The job is one `task.spawn` at the bottom of `ZyntraMonetization`, 20 s after
server start:

1. `RunService:IsStudio()` → return immediately. Studio never claims and never
   writes, matching the existing Studio-never-writes discipline.
2. Module absent → return silently. That is the normal state both before the
   lead places it and after it is removed, so it produces **no warn**. A module
   that is present but malformed produces exactly **one** warn.
3. Claim `salesimport_<sourceKey>` via `UpdateAsync`. Losing servers stand down
   after one cancelled read.
4. Group rows by buyer — **one atomic `UpdateAsync` per profile, never per row**.
5. Per buyer:
   - **Online with a persistent session** → `mutateIdempotent(player, …, true)`.
     That is the existing retrying writer: it reads `current` fresh inside the
     callback, adopts the committed result into `session.data`, re-asserts
     pending accessibility targets and republishes attributes. So a buyer who is
     mid-session does not lose the write and does not display a stale total; a
     silent `pushProfile` follows. The failure toast is suppressed.
   - **Offline, or the session closed underneath that write** → raw
     `store:UpdateAsync("u_<id>", …)`. Following a write that committed and lost
     its response is safe: its markers cancel this one. A buyer leaving
     mid-import therefore does not leave the source unfinished.
   - Then `syncSupportTotal(userId, recorded)` — the OrderedDataStore write is
     `math.max(current, total)`, so **an offline buyer reaches the board without
     ever logging in**, and a replay repairs a lost entry even when the profile
     write itself was a no-op.
   - `task.wait(0.2)` between buyers.
6. Write the readback attributes, close the claim (`Done = failed == 0`), print
   one summary line, `refreshSupportLeaderboard()`.

**Stale session copies cannot clobber the import.** Every writer in this script
(`mutate`, `mutateIdempotent`, the dispatch/accessibility/protection paths)
mutates a `current` read fresh inside its own `UpdateAsync` callback; none of
them writes `session.data` wholesale. Verified by reading each write site.

### 1.9 No entitlements, ever

The import writes only `DonationRobux`, `UtilityRobux`, `PassRobux`,
`SalesImport`. It never touches `Tokens`, `ReentryCredits`, `StaminaLevel`,
`BatteryLevel`, `Grants`, `AwardedBadges` or `ReceiptIds`, and it never calls
`awardBadge`, `useReentry` or `PurchaseAlerts`. A buyer with no profile at all
(website-only purchasers) gets one created from `newProfile()` — 0 tokens, 0
credits, no grants, `LobbyBriefingPlayed = false` so their first-entry guide
still plays. All asserted in the tests.

### 1.10 Row classes that cannot be disambiguated

| class | count in this export | treatment |
|---|---|---|
| Developer Product, both statuses | 40 | ceiling stream; ambiguity between "already counted" and "not" is absorbed by the max, never resolved per row |
| Game Pass | 2 | added in full, keyed by pass id |
| Private Server Product | 2 | added in full, keyed by row id |
| foreign universe | 0 | generator skips and reports |
| status other than Pending/Paid | 0 | generator skips and reports (Pending = creator payout pending, a completed sale) |
| duplicate export Id | 0 | generator skips and reports |
| non-integer Price | 0 | generator skips and reports |
| unmapped asset id | 0 | generator **aborts the whole run** rather than guess a stream |

No historical amount is invented anywhere: every number comes from the export's
`Price` column. Catalogue prices are never consulted. `Revenue` (the creator's
net) is never read.

---

## 2. Files and functions changed

### `ServerScriptService/ZyntraMonetization.Script.lua` (+285 lines)

| where | change | why |
|---|---|---|
| `recordedSupportRobux` | adds `PassRobux` | storefront spend has to reach the board and the personal view |
| `newProfile` | `PassRobux = 0` | third stream, with a comment saying it has no live writer |
| `normalizeProfile` | normalises `PassRobux`; rebuilds `SalesImport.Sources`/`.Rows` from validated string keys, never truncating | markers must be permanent and un-forgeable, like `ReceiptIds` |
| `publicProfile` | carries `PassRobux` | the store footer needs the third number |
| `applyAttributes` | publishes `ZyntraPassRobux` | parity with the other two streams |
| `ProcessReceipt` overflow guard | three-term instead of two-term | the old guard could not see the new stream |
| new block `-- SALES_IMPORT_20260915 … -- SALES_IMPORT_BOOT` | `runSalesImport` + boot spawn | the import itself |

### `StarterPlayer/StarterPlayerScripts/ZyntraStore.LocalScript.lua` (2 lines, mine)

The footer said *"Passes & earlier token/re-entry purchases excluded."* — the
import makes that untrue. Both the placeholder (L1636) and the live format
(L2541) now read:

```
RECORDED SUPPORT  %d R$
Donations %d R$ / Products %d R$ / Passes %d R$
Purchases made before 2 Sep 2026 are not recorded.
```

The label already auto-sizes through `textHeightFor` (L1721), so the longer
middle line reflows at every fit tier. **`ReplicatedStorage/UIRegression.ModuleScript.lua`
was NOT edited**: I grepped it for `RECORDED SUPPORT`, `Passes &`, `earlier token`
and `DonationTotal` — it references none of them, so no caption fixture changed.
(The file had 39 changed lines from another agent's concurrent work when I
started; only the two lines above are mine.)

### New files

- `tools/leaderboard_backfill/generate_backfill.py` — CSV → ModuleScript source.
  Holds the **explicit, closed** asset-id → stream mapping; an unmapped asset id
  aborts. Refuses to write outside `_local/`.
- `tools/tests/test_leaderboard_backfill.py` — see §3.
- `_local/trello-20260915/ZyntraSalesBackfill_20260915.ModuleScript.lua` —
  generated, gitignored (`.gitignore:16 _local/`), 44 rows.

### The CSV asset-id mapping (per Codex: export ids ≠ catalogue ids)

| CSV `Asset Id` | CSV `Asset Type` | catalogue | catalogue `Id` | stream |
|---|---|---|---|---|
| 77345358 | Developer Product | `Config.Products.Reentry` | 3707755318 | utility |
| 77665692 | Developer Product | `Config.Donations.Signal` | 3710116814 | donation |
| 1941938256 | Game Pass | `Config.Passes.Supporter` | 1941938256 | pass |
| 1978617781 | Game Pass | *(not in catalogue)* | — | pass |
| *(any)* | Private Server Product | — | — | pass |

Roblox reports a developer product in the export by its **product id**, while
`ZyntraConfig` holds the id passed to `PromptProductPurchase`; they are different
numbers for the same product. Game passes use the same id in both places. Nothing
at runtime re-derives this — the generator stamps `Stream` onto each row and the
import validates it against three known values.

---

## 3. Tests — commands and verbatim results

```
set LUAU_BIN=C:\Users\mikke\AppData\Local\Temp\codex-luau-0.737\luau.exe
python tools/tests/test_support_product_receipts.py
python tools/tests/test_token_grants.py
python tools/tests/test_feedback_gift.py
python tools/tests/test_leaderboard_backfill.py
```

```
test_support_product_receipts    support product receipts: 236 checks passed
test_token_grants                token grants: 243 checks passed
test_feedback_gift               feedback gift: 26 checks passed (actual mutate + gift block; fake DataStore)
                                 normalizeProfile keeps unknown Grants keys (3 Grants lines inspected)
test_leaderboard_backfill        leaderboard backfill: 85 checks passed (actual import block + normalizeProfile + mutateIdempotent + ProcessReceipt; fake DataStore)
                                 generator: 4 rows classified, 5 refused, unmapped asset ids abort
```

All four exit 0. The three pre-existing suites are at their pre-change counts
(236 / 243 / 26 — baseline captured before any edit).

The new suite runs the **real** extracted blocks — `normalizeProfile`,
`mutate`/`mutateIdempotent`, `syncSupportTotal`/`refreshSupportLeaderboard`,
`ProcessReceipt` and the import block itself — against a fake DataStore with
**synthetic** buyers (ids 101–106, invented 22-char export ids). What it asserts:

- ceiling: an uncounted row is added, a counted one is not, a stream the stored
  total already covers never grows, a donation total larger than the export is
  never lowered;
- storefront spend lands in `PassRobux` and not in the product stream;
- **idempotence** — a finished source is never claimed again, and even with the
  claim deleted a second run applies 0 rows and changes 0 profiles;
- **gamepass once** — a second overlapping export re-pays nothing and the marker
  is `pass:<assetId>`;
- **offline buyer** — a buyer with no profile gets one plus an ordered-store
  entry, with 0 tokens, 0 credits and no grants;
- **online buyer** — session copy adopts the write, `ZyntraRecordedSupportRobux`
  and `ZyntraPassRobux` republish, and spend recorded during that session is
  neither lost nor lowered;
- **departing buyer** — a player whose `Parent` goes nil mid-import still lands
  through the offline path and does not fail the source;
- **concurrent claim** — two servers, one runs, the loser spends one read and
  zero writes;
- **retry** — a per-user failure reports `incomplete`, leaves `Done = false`,
  and a later server delivers exactly the missing buyer and nothing else;
- **new live purchase after the import** — `ProcessReceipt` adds on top, grants
  its benefit, updates the board, and a receipt retry still does not double;
- **absent module** = `no-module`, 0 writes, 0 warns; **malformed module** =
  `bad-module`, 0 writes, exactly 1 warn; **Studio** = `skipped-studio`, 0
  DataStore calls at all;
- `normalizeProfile` keeps both marker tables across a reload and drops
  over-long keys, non-`true` values and non-string keys;
- generator: correct stream/marker/price for all four classes, 5 malformed rows
  refused, an unmapped asset id aborts, and writing outside `_local/` is refused.

### Dry run of the real generated module (aggregates only)

Real module driven through the real import block against **cold/empty** profiles,
i.e. the upper bound:

```
rows=44 invalid=0 buyers=39 applied=44 already=0 changed=39 failed=0
idmatches=0 ambiguous=0 status=done
donation=20 utility=1068 pass=20119 total=21207 rankedBuyers=39
```

21 207 R$ matches Codex's independent gross exactly, and the per-stream split
matches `sales-audit.json` by asset. On real profiles the ceiling will absorb
whatever is already recorded, so the live `applied`/`changed` numbers will be
lower — and `idmatches`/`ambiguous` will be non-zero if real receipts overlap.

### Not verified

No Studio, no live server, no published build, no real DataStore was touched by
me. The compile check is `luau 0.737` parsing the whole file (it reaches
line 4 and fails on the absent `game` global, which proves it compiled). The
lead's native Studio compile probe and the live run below are still required.

---

## 4. Live-server verification steps for the lead

1. Create `ServerStorage.ZyntraSalesBackfill` as a **ModuleScript** and paste
   `_local/trello-20260915/ZyntraSalesBackfill_20260915.ModuleScript.lua` into it
   (new scripts cannot be pushed by the sync tools — `execute_luau` +
   `UpdateSourceAsync`, per CLAUDE.md). It carries buyer user ids: **ServerStorage
   only, never `ReplicatedStorage`, never committed.** No manifest item — it is
   deliberately not mirrored.
2. Push the two mirror edits (`ZyntraMonetization.Script.lua`,
   `ZyntraStore.LocalScript.lua`) and run the compile probe. `ZyntraStore` is
   being edited by another agent — expect to merge, not overwrite.
3. Publish. **In Studio nothing happens** — `ZyntraSalesImportStatus` reads
   `skipped-studio` and no DataStore call is made. That is the expected Studio
   result and is not a failure.
4. Join a live server. ~20–35 s after it starts, read the readback:

   ```lua
   local S = game:GetService("ServerStorage")
   for _, k in ipairs({"Status","Source","Sha256","RowsTotal","RowsInvalid","Buyers",
       "RowsApplied","RowsAlreadyCounted","ProfilesChanged","ProfilesFailed",
       "IdMatches","Ambiguous"}) do
       print(k, S:GetAttribute("ZyntraSalesImport" .. k))
   end
   ```

   Expect on the first live run: `Status = done`, `Source = sales_20260915`,
   `Sha256 = 97fb4a8d…5edc`, `RowsTotal = 44`, `RowsInvalid = 0`, `Buyers = 39`,
   `ProfilesFailed = 0`. `RowsApplied + RowsAlreadyCounted = 44`.
   `ProfilesChanged ≤ 39`. The server output carries the same numbers on one
   `[Zyntra] Sales import complete:` line.
5. **Record `IdMatches` and `Ambiguous`.** `IdMatches > 0` settles that the
   export `Id` *is* the `PurchaseId` (worth putting on the card either way).
   `Ambiguous` is the number of profiles that hold more acknowledged receipts
   than this export has product rows for them — the upper bound on the
   under-count described in §5.
6. A second server started later must read `claim-held` and write nothing.
   Restarting the first server must also read `claim-held`.
7. Check the board: `ReplicatedStorage.ZyntraDonationLeaderboard.Row01…` should
   be topped by the 20 000 R$ pass buyer. In the store's DONATE tab the footer
   should show three numbers and the new disclaimer.
8. If `Status = incomplete`, nothing is lost: leave it, and any server started
   more than an hour later retries only the buyers that failed. Re-check the
   attributes then.
9. Once `Status = done`, **delete `ServerStorage.ZyntraSalesBackfill`** and
   republish. The block then reads `no-module` and is inert; the global `Done`
   marker means re-adding the module later would also do nothing.

---

## 5. True coverage limits

1. **Nothing before 2026-09-02T04:54Z is recovered.** The export's earliest row
   is that timestamp. If the game sold anything earlier, it is recorded only to
   the extent the live path already recorded it (donations from 2026-08-27;
   utility amounts not at all before 2026-09-10). The import invents nothing.
2. **Nothing after 2026-09-15T13:24Z is in this export.** Purchases after it are
   recorded by the live path as normal and add on top.
3. **The ceiling under-counts exactly one class**: a buyer who has *both*
   uncounted rows inside the export *and* product spend recorded between the
   export being taken and the import running. For such a buyer the stored total
   already exceeds the part of the export that was uncounted, and the max
   absorbs the difference. In this export only 3 of 39 buyers have more than one
   row, and the gap is hours, so the exposure is at most a few times 29 R$.
   `ZyntraSalesImportAmbiguous` measures the population that *could* be
   affected (it is an over-estimate; see 4).
4. **`Ambiguous` has false positives.** It compares `#ReceiptIds` against the
   export's product-row count for that buyer, and `ReceiptIds` also contains
   donation receipts, Studio test grants and any pre-window purchase. A non-zero
   count is a prompt to look, not proof of a loss.
5. **Pre-v1824 utility receipts are recovered only through the export.** A
   receipt acknowledged without an amount that is *not* in the export (i.e.
   before 2026-09-02) stays uncounted forever — the profile holds no evidence of
   what it cost.
6. **The CSV `Id` ↔ `PurchaseId` relation is still formally unknown** until step
   5 of §4 is run. Nothing depends on it; it is reported, not used.
7. **Statuses.** Pending (29 rows) and Paid (15) are both treated as completed
   sales — Pending is the creator payout, not the buyer's payment. A future
   export containing a refund/chargeback status would be *skipped by the
   generator*, not subtracted; the import has no decrement path at all.
8. **Passes grant nothing.** The import records pass spend but never sets
   `Grants.Supporter`. `refreshPasses` continues to be the only thing that grants
   from real ownership — correct, and it means asset 1978617781 (the 20 K pass,
   absent from `ZyntraConfig.Passes`) confers no in-game benefit today.
9. **One export = one source key.** A future export must be generated with a new
   `--source-key`. It is then safe to import over this one (ceiling + markers),
   but a source key is never reused.

---

## 6. Open questions for the owner / lead

1. **Should the 20 000 R$ pass (1978617781) grant anything?** It is not in
   `ZyntraConfig.Passes`, so it currently buys a leaderboard position and nothing
   else. Out of scope for #36 — flagging it because it is 94% of the recorded
   gross.
2. **Should live game-pass purchases be recorded going forward?**
   `PromptGamePassPurchaseFinished` already fires with the pass id; recording
   `Config.Passes[key].Price` into `PassRobux` under the same `pass:<assetId>`
   marker would close the stream permanently. Deliberately **not** done here:
   the catalogue price is not the paid amount (sales, regional pricing), and the
   brief forbids fabricating amounts from catalogue prices. It needs an owner
   decision on whether catalogue price is acceptable for that path.
3. **Private servers in "support"?** Included as gross spend, on the reading of
   the card title. Easy to exclude (one line in the generator's `TYPE_STREAMS`)
   if the owner considers a private server a service rather than support.
4. **Footer wording.** "Purchases made before 2 Sep 2026 are not recorded." is
   accurate but exposes a date. An alternative is to drop the third line
   entirely now that the two exclusions it named are gone.
5. **Manifest.** I did not touch `studio-sync-manifest.json` (the lead owns
   Studio and source/manifest writes); the two edited mirror files need
   `record_pending_push.py` before the push.
