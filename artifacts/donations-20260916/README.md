# Donation buttons — 16 September 2026

Published to the existing experience, version 1919. Studio log confirms PublishSuccessful and “Place published” at 07:53:03 UTC.

| Button | ID | Type |
|---|---|---|
| 5,000 Robux | 3713115025 | Repeatable developer product |
| 10,000 Robux | 3713115125 | Repeatable developer product |
| 20,000 Robux | 1978617781 | Existing one-time gamepass |

New products are on sale with managed pricing disabled. Roblox may independently apply buyer-specific discounts in its purchase prompt. The 20K pass shows OWNED after ownership is established; gamepass IDs are excluded from ProcessReceipt. No artificial nominal-price support credit is added for pass ownership; the existing verified sales-import mechanism handles pass totals.

Studio was the source of truth. The full source mirrors contain pre-existing work newer than origin/main, including daily rewards; task-only.patch isolates this task from that existing work. Each write compared live Source and editor source against the exported baseline, then verified readback. No old repository sources were deployed to Studio.

Before the user requested immediate publication: all four changed scripts compiled using official Luau 0.738; the production receipt harness passed 252 checks, including repeated 5K/10K donations, duplicate receipt protection, and gamepass exclusion. Studio built all nine cards, displayed correct prices and OWNED for the pass under the existing Studio grant-all-passes setting. The 5K button opened the correct Roblox test-purchase prompt. No purchase was completed. Further UI and purchase testing was stopped at the user’s instruction; 10K/20K purchase dialogs and mobile layout were not separately exercised.

Full native pre-change backup and hashes are recorded in manifest.json. No active servers were restarted.
