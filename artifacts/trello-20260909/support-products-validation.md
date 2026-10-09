# Recorded support from new Developer Product receipts

Trello: [gTgtoztS](https://trello.com/c/gTgtoztS/36-donation-leaderboard-include-all-in-game-purchases). This is an independently publishable partial delivery. The complete card remains **In Progress** because passes and historical utility purchases are not yet reconciled.

## Behavior and accounting

A newly acknowledged Tokens4, Tokens20 or Emergency Re-entry receipt now adds the actual `CurrencySpent` to `UtilityRobux`. Donations continue to add to their separate `DonationRobux` stream. The receipt ID, the purchased benefit and exactly one paid stream are saved in the same existing profile `UpdateAsync`. `RecordedSupportRobux` is derived from the two streams; it is not a second persisted balance that can fall out of step.

Permanent `ReceiptIds` remain intact. A duplicate is checked before paid-amount validation and produces no additional grant or paid amount. This also means an old utility receipt cannot be silently turned into a historical backfill. A lost response after a successful commit is repaired by the ordinary receipt replay. Fresh Emergency Re-entry retains its existing automatic-use path; a duplicate does not repeat it.

New paid amounts must be finite, nonnegative integers at or below 9,007,199,254,740,991. Sum and grant-balance overflow are checked before any receipt ID or balance changes. Zero remains zero. Studio grants add zero paid support and never substitute a catalog price. There are no real purchases, receipt injections into Studio, or live DataStore writes in this implementation work.

The existing `ZyntraDonationLeaderboard_v2` store, monotonic max writes and per-user worker/coalescer are retained. Receipt acknowledgement remains independent of ranking availability. Receipt/replay, join and leave all request the combined recorded total. Failed cache writes remain dirty after five immediate attempts, and the existing periodic loop retries them. No global migration, cache clearing, legacy summation or CSV import is performed; absent donors remain in the existing store.

## Display

The personal Donate view shows recorded support, separate donation/product amounts, and the explicit exclusion of passes and earlier token/re-entry purchases. Its header height is measured at the actual available width, leaving the donation cards in their existing scrolling area. The board reads TOP SUPPORTERS and carries the same limitation in a footer and RankingScope metadata. Existing instance names and v2 store identifiers remain stable.

No pending-pass marker was added. A boolean user/pass flag without a stable transaction identity or buyer-paid amount would not establish a deterministic link to a sales-export row; it would add a second incomplete accounting mechanism. Existing pass ownership, one-time grants and purchase-event behavior are unchanged. The authenticated export and historical reconciliation remain separate work.

## Scope and backups

Exact byte backups are under `support-products-before/`, retaining the service folder paths. `support-products.diff` is the complete feature delta against those backups.

- `ServerScriptService/ZyntraMonetization.Script.lua`: normalization, derived fields/attributes, receipt accounting and combined cache targets.
- `StarterPlayer/StarterPlayerScripts/ZyntraStore.LocalScript.lua`: personal total, breakdown and measured explanatory header.
- `ServerScriptService/TunnelLobbyBuilder.ModuleScript.lua`: board title, scope text and footer.
- `ReplicatedStorage/ZyntraConfig.ModuleScript.lua`: only the obsolete donation-only comment; product IDs, prices, grants and store name are unchanged.
- `tools/tests/test_support_product_receipts.py`: offline fake-DataStore regression running actual production code sections.

## Verification

All four complete production files compile with Luau 0.737 (8 KLOC, 245 KB bytecode). Whitespace checks report no errors; Git emits the existing line-ending conversion notices. Independent core review found no blocking issues and repeated all 236 receipt checks plus all four complete compiles. The visible scope wording was then narrowed to earlier token/re-entry purchases so existing donations are unambiguously retained. The final independent score is **9/10**, after direct review of the native JSON and all four images; no required corrections remain.

The new receipt suite passes **236 checks**. It executes the real normalizer, mutation callback, receipt handler, public-profile/attribute projection, ranking cache and worker. Cases cover every utility grant and donation, actual paid amounts differing from catalog prices, zero/malformed/unsafe amounts, safe-sum and grant overflow, legacy receipt replay, two servers sharing a durable fake profile with callback conflict/retry, lost commit response, ranking outage, new totals arriving during an older write, old-server lower writes, repair targets from the actual join/leave/periodic statements, unavailable sessions and free Studio grants. DataStore callbacks receive separate cloned snapshots so rejected attempts cannot accidentally mutate committed fake data. The join/leave repair statements are executed against loaded test profiles; this does not claim to retest the entire unrelated dispatch-session lifecycle.

The existing developer token-grant suite also passes **242 checks**, confirming those free grants retain their separate behavior. No broad unrelated test suite was run.

## Root native pass and rollout boundary

Root owns scoped Studio synchronization, native rendering, auditing and mouse-menu publication. Before release, inspect the Donate header and scrolling cards on a narrow phone and desktop; verify the board title/status/footer fit. Native test profile amounts, if needed for layout, must remain explicitly temporary display fixtures rather than simulated paid purchase evidence. No real purchase is necessary for this pass.

Publication updates new servers. Servers still running the previous version can continue acknowledging utility receipts without recording UtilityRobux. Their subsequent lower donation-only ranking writes cannot decrease an already higher v2 value, and their profile normalizer retains unknown fields. However, their utility receipts create a real accounting coverage gap until those servers are replaced. Do not describe coverage as beginning globally at the publish timestamp, claim all historical purchases, or close the full Trello card. An owner-directed server rollout and the verified transaction export are required to close those remaining gaps; no restart or live migration is performed here.

The receipt contract was checked against [Roblox MarketplaceService documentation](https://create.roblox.com/docs/reference/engine/classes/MarketplaceService#ProcessReceipt). The export authentication and disabled Studio API reads remain documented in `sales-export-access.md`; no inference is made that live stores are empty.


## Completed native verification and publication

Root verified desktop, iPhone 13 portrait/landscape and the world board; the critic personally reviewed all four images. The measured personal header fits and the donation cards retain a working scroll with 44-pixel purchase targets. The board scope footer is clear of rank 10. These were Studio Device Simulator checks, with no paid purchase simulated or live DataStore access.

Root mouse-published **v1824** on **10 September 2026 at 00:22:23.542 Danish time**. Final native compile:122/122, zero failures and no staged scripts. Audit:122 matched, zero drift, one explicitly allowed trailing-newline difference. Backup:20260909-221829. The Trello card was read back as **In Progress, complete=false**, retaining its original request and appending the partial release and remaining constraints. Priority row15 and support-products-native.json release metadata are updated.
