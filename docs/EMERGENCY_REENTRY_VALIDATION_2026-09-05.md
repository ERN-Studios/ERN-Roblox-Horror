# Emergency Re-entry validation — 2026-09-05

The three checks requested by [the Trello card](https://trello.com/c/R5tjB30m)
passed in the owner's local Roblox Studio place. The Creator Dashboard also
confirmed the product was **already on sale at 29 R$**; the card's off-sale note
was stale. No product-setting change was necessary. The existing **15-second**
PARTY DOWN window was retained, following the owner's earlier stated preference.
The playtest itself changed no gameplay source, product settings, player
DataStores, or published place versions. Studio was returned to Edit mode.
The subsequent badge configuration and approved publication are recorded
separately below.

## Environment and scope

- Experience: BACKROOMS: STAY QUIET [CO-OP HORROR].
- Universe ID: `10559217407`; place ID: `131311258779917`.
- Product: Emergency Re-entry, `3707755318`, displayed price **29 R$**.
- Single-player Level 2 rounds launched through the existing lobby station 5.
- Purchases used the real Roblox Studio purchase prompt, which explicitly said
  **"This is a test purchase. Your account will not be charged."** The prompt
  reported purchase completion and the game's actual receipt handler processed
  the simulated purchase. No real Robux were spent.
- The live monetization script creates an in-memory Studio profile and its
  `mutate` Studio branch bypasses DataStore writes. Each restarted play session
  started with zero re-entry credits.
- Test-only player positioning, deaths, fast-queue attribute, and event recorder
  existed only inside Play mode and disappeared when the session stopped.

## Results

| Check | Observed result |
| --- | --- |
| Purchase while alive in lobby | Credit count **0 → 1**, `InRound=false`, health **100**; no automatic respawn. |
| `ZyntraAction:FireServer("UseReentry")` while alive in lobby | Credit remained **1**, character instance unchanged, health **100**, `InRound=false`. The rejected use/refund path preserved the credit. |
| NO THANKS during a real party wipe | Clicking the real `PartyDownDecline` button immediately hid the overlay. `PartyDownCardOpen` cleared while `PartyDownWindowOpen` remained true. The status line showed **14 SECONDS LEFT**, then **1 SECOND LEFT**. |
| Declined wipe reaches its normal endpoint | Recorded `partydown` with duration **15** at client `os.clock()` **958.262208**, followed by `lose` at **973.595697**: about **15.33 seconds**, including polling/replication timing. `RoundActive=false` afterward. |
| Fresh purchase while dead in active round | Recorded `partydown(15)` at **1148.089613**, automatic `reentry` at **1162.146496** (about **14.06 seconds** into the window), then `partydownclear` at **1162.404844**. Credit count ended **0**, health **100**, `InRound=true`, `RoundActive=true`, and `ZyntraReentryUsed=true`. No second UseReentry action was sent. |
| Purchase confirmation lands after the wipe expires | In an earlier timing attempt, `lose` arrived about **15.27 seconds** after `partydown`; the subsequently granted credit remained **1** with `RoundActive=false`. The purchase was preserved for a later round instead of being consumed. |

For the successful in-window test, the purchase prompt was opened while the
round was active and the player was then killed before pressing **Buy**. This
kept desktop automation latency inside the unchanged 15-second deadline. The
actual purchase/receipt occurred while dead; automatic re-entry succeeded.
The preceding timing attempt separately exercised opening the purchase prompt
through the real PARTY DOWN purchase button after death.

## Limits and release notes

- These are real Studio simulation results, not a real-money transaction in a
  published server. Live Roblox receipt-delivery timing and DataStore outage
  behavior were not exercised.
- The 15-second choice is still a short purchasing window. A receipt arriving
  after expiry keeps a stored credit; it does not rescue the already lost round.
- The current repository contains other sessions' unpushed changes. The live
  Studio scripts, not a broad repository push, were tested. The re-entry and
  receipt blocks are present in both copies; unrelated monetization persistence
  changes differ. This report is not approval to publish those unrelated edits.
- The parent agent inspected the authoritative Creator Dashboard UI during this
  task: **Item for sale** was enabled, price was **29**, Managed Pricing was
  enabled, and **Save Changes** was disabled. It made no product mutations.
- Any later place publication must be verified separately.

## Badge-config deployment boundary inspected alongside this test

At initial inspection, live `ReplicatedStorage.ZyntraConfig` had four zero badge
IDs. The repository had those same four IDs plus an unpushed
`AccessibilitySettings` block. A whole
file push would therefore deploy unrelated settings work.

Patch only `FirstClearLevel1`, `FirstClearLevel2`, `FirstClearLevel3`, and
`CampaignComplete` in each copy, using `ScriptEditorService:UpdateSourceAsync`
against the live source with exact-match guards. Preserve each copy's other
content. Since the two complete files remain different, the manifest must not
claim `synced`: record the edited repository hash and use the patched live hash
as `studioSha256Before` for the remaining pending changes. Do not run the broad
pending-record/push commands across the dirty worktree for this four-ID task.

## Badge configuration and subsequent approved publication

All four created badges were checked read-only with
`BadgeService:GetBadgeInfoAsync`: each returned the expected name and
`IsEnabled=true`. No actual badge award was issued as a test.

| Configuration key | Verified badge name | Badge ID |
| --- | --- | --- |
| `FirstClearLevel1` | Level 1 Cleared | `2788462628933614` |
| `FirstClearLevel2` | Level 2 Cleared | `349186155479685` |
| `FirstClearLevel3` | Level 3 Cleared | `457908347698355` |
| `CampaignComplete` | Stay Quiet | `2318404539475574` |

Only these four numeric values were changed in the repository Config and live
Studio Config. The Studio edit used a compare-and-swap
`ScriptEditorService:UpdateSourceAsync` callback that refused if the current
editor source differed from the source read beforehand. Requiring a temporary
Config clone verified the IDs, the unchanged re-entry product ID/29 R$ price,
and the absence of the repository-only accessibility block from Studio. The
clone was destroyed after verification. The existing live monetization source
compiled in a non-executed function wrapper, and its badge hook was inspected:
per-level awards follow level completion; campaign completion checks all three
stored level-clear flags; unsuccessful badge awards are not recorded as earned.

The only manifest entry changed was `ReplicatedStorage/ZyntraConfig`:

- Status: `pending-studio-push`, because the existing 42-line accessibility
  addition remains repository-only.
- Repository canonical bytes: `6668`.
- Repository SHA-256:
  `891cb0bb88fb6aa88ba712181ca9a46e220df890bd8300f920a3093b6f48ffc3`.
- Patched live Studio baseline SHA-256:
  `58b80b35b7a39618d7f3e381d6286906fe9b257a8c49730a4bd71750d882edfd`.

The user explicitly approved publishing the full open Studio version after being
informed that this also publishes its other changes, that Studio was loaded
from version 1751, and that the dashboard showed version 1754 already published.
The approved **File → Publish to Roblox** action was executed for universe
`10559217407`, place `131311258779917`; no broad repository synchronization ran.

Studio output on 2026-09-05 (local time) confirmed:

- **11:30:21.517**: publication request sent to the server.
- **11:30:28.561**: **Place published**, with an **Add publish notes to v1755**
  link.
- **11:30:28.625**: new changes in **BACKROOMS: STAY QUIET [CO-OP HORROR]**
  published to Roblox.

The current datamodel's `game.PlaceVersion` remained 1751 after publication;
the success output and explicit v1755 link are the Studio-side publication
evidence. The parent agent independently verified **v1755** in Creator Dashboard
with **Show published only** enabled (September 5, 2026 at 11:29 AM as displayed
by the dashboard). All four badges were Active and all four uploaded icons,
including the corrected actual-map Level 3 icon, rendered in the final dashboard
screenshot; the earlier processing placeholders had cleared.
Publication is separate from the no-charge re-entry simulations above and is
not evidence of a real-money purchase or live badge award.
