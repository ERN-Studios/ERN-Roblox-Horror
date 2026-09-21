# Historical leaderboard reconciliation — 15 September 2026

Read-only Creator Dashboard Data Stores Manager audit: 39 CSV buyers, 38 existing profiles and one absent game-pass buyer. All 40 acknowledged developer-product receipts are covered by the 40 CSV developer-product sales, with exact counts per buyer. No CSV Id was assumed to equal a PurchaseId. CSV coverage is the owner's complete purchase export (actual transactions September 2–15); all corresponding stored receipt sets predate the export cutoff.

One product buyer had a later profile save. Its September 15 13:24 Copenhagen version (`08DF123B6860050C.000000000F.08DF131BE5FCF61C.01`) already contains the same sole receipt and UtilityRobux=29 as its 18:52 version. Thus that later save contains no additional product purchase. Other product profile saves predate the cutoff of 15:24:12 Copenhagen. Buyer identifiers and exact receipt sets are kept only in ignored `_local/trello-20260915/live-profile-audit.json`.

Stored paid streams total 877 Robux. The export totals 21,207 Robux: donation20, utility1068, game passes20099, private servers20. Required correction totals20,330 Robux. This includes pre-recording purchases and differences between the CSV's actual sale price and the stored aggregate. The [Roblox sales data reference](https://create.roblox.com/docs/production/analytics/analytics-dashboard) defines Price as the amount paid, and Revenue as the creator's proceeds. The CSV is the requested reconciliation authority; entitlement balances are not re-granted.

Implementation must add the audited per-stream difference once under a source marker, preserving any later receipt deltas. It must validate that the current profile still contains every audited receipt, that its aggregates have not fallen below the audited baseline, and that the baseline's receipt count equals this export's per-buyer product count. A mismatch must fail that buyer and leave the job incomplete. The previous ceiling algorithm is insufficient when old missing purchases and later purchases coexist.

This pre-import proof was subsequently applied successfully in published1906.
All39 profiles read back:44 rows,21207 Robux,40/40 original receipts preserved,
no entitlement/balance changes. See publication-and-import.md. The private
module was removed in cleanup1907; CSV and audit baselines remain ignored locally.
