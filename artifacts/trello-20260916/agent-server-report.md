# A-SERVER report — 2026-09-16 batch

Owner of the profile schema, ZyntraConfig balance constants, the daily-rewards
server, the Speed Potion, and `ServerStorage.ZyntraInventory`.

Baseline `aa40f70`. Nothing committed, nothing pushed to Studio, manifest untouched.

## Files touched (exact paths)

| Path | What changed |
|---|---|
| `G:\Roblox\MongoTV\ReplicatedStorage\ZyntraConfig.ModuleScript.lua` | new `Items`, `DailyRewards`, `FieldNotes` blocks (contract values verbatim) |
| `G:\Roblox\MongoTV\ServerScriptService\ZyntraMonetization.Script.lua` | schema additions, `applyReward`/`rollDaily`/`dailyMutate`, playtime accrual, claims, wheel, BuyItem, UseSpeedPotion, `ZyntraInventory`, leaderboard row columns, title name tag |
| `G:\Roblox\MongoTV\tools\tests\test_daily_rewards.py` | NEW — 320 checks |
| `G:\Roblox\MongoTV\tools\tests\test_item_inventory.py` | NEW — 146 checks |

No other file was changed. No proposed diff for another agent's file is needed.

## Test results (LUAU_BIN = codex-luau-0.737)

Before and after are identical for every pre-existing suite.

| Suite | Before | After |
|---|---|---|
| test_support_product_receipts | 236 | 236 |
| test_token_grants | 243 | 243 |
| test_reentry_dismissal | 37 | 37 |
| test_dev_free_respawn_offer | 17 / 24 / 3 / 8 | 17 / 24 / 3 / 8 |
| test_feedback_gift | 26 | 26 |
| test_leaderboard_backfill | 100 | 100 |
| test_first_login_flag | 33 | 33 |
| test_purchase_alerts | 97 | 97 |
| **test_daily_rewards** (new) | — | **320** |
| **test_item_inventory** (new) | — | **146** |

`luau-compile --binary` exit 0 for both `.lua` files.

## What is verified offline, and how

Both new suites paste the REAL blocks out of `ZyntraMonetization.Script.lua`
(profile helpers, `publicProfile`, `applyAttributes`, `refreshPlayerTags`,
`mutate`, `publishSupportRows`, and the whole daily-rewards section) into a fake
DataModel and run them under the real Luau interpreter. The scheduler drives the
production one-second accrual loop; the fake DataStore reproduces
`failBefore` (never reached the callback), `failAfter` (committed, response
lost) and a pause that lets a second writer queue behind the mutation lock.

**test_daily_rewards (320)**
- Accrual gate matrix (10 states): lobby, in-round-alive-moving, `InRound`
  false, `RoundActive` false, loading cover up, `Escaped`, `Level2_ExitTransition`,
  dead body (spectating), no character, no root part. Each also asserts
  `ZyntraDailyAccruing`.
- AFK: counts through the 90 s grace, plateaus after it, resumes on movement,
  never subtracts. Sub-threshold drift (0.0001 studs/s) does not defeat the pause.
- `Level3_Hiding` counts for 200 s of perfect stillness.
- Flush ADDS: store advanced to 100 by another writer while the session held an
  older copy + 30 s delta → 130, not 30.
- Failed flush keeps the delta (`failBefore`); the retry banks it once.
- Committed-but-response-lost (`failAfter`): the store has the seconds, the
  session keeps them pending, and the retry recognises its own `Daily.FlushId`
  and adds **nothing** a second time — one durable write. The next flush mints a
  new id and banks normally.
- Seconds earned while a flush yields survive into the next flush.
- An empty flush opens no DataStore call at all.
- Day roll resets `PlaytimeSeconds` and `Claimed`, leaves `WheelDay` and
  `WheelLast` (key + serial) alone.
- Public payload: `Today`, `Day`, `SecondsToReset` (moved the clock 5 h 1 min),
  `Accruing`, and `PlaytimeSeconds` including unflushed seconds — proven by
  showing the profile genuinely does not hold them yet, and that the number does
  not jump backwards over the flush.
- Claims: below threshold → zero writes, zero transactions, exact refusal text;
  at threshold → one grant with the exact message; second claim → zero writes,
  refused in memory; a claim folds the pending seconds so 299 s durable + 1 s
  pending claims the 5 minute milestone and banks 300 in the same transaction;
  all three milestones pay exactly what config declares; unknown/malformed
  milestone payloads are ignored.
- EntityShield reward adds a charge and leaves `Protection.Revision` and
  `LastOperation` (SessionId/Status/Revision) byte-identical.
- A `Protection` table that does not validate blocks the shield reward and is
  not recorded as claimed (left for repair).
- Two claims interleaved through the mutation lock grant exactly one token.
- Wheel: weights sum to 100, five prizes; 20 000 picks with a real xorshift32
  land every prize within 1.5 pp of its weight; each of the five slices selects
  and pays its own prize with its own reply text; one spin per UTC day; same-day
  replay (including after a rejoin) grants nothing, writes nothing, opens no
  transaction and re-reports the recorded prize; the next UTC day spins again
  and advances the serial; a spin whose write never lands records nothing and
  can be spun again.
- BuyItem: both items, spend + add in one write, refusal text with the item's
  own price, zero writes on refusal, malformed payloads ignored.
- UseSpeedPotion: six-case refusal matrix (no round / loading / escaped / exit
  transition / dead / hiding) each with its contract message and zero writes and
  zero consumption; "No Speed Potion stored"; a successful use consumes one,
  sets `ZyntraSpeedBoostUntil`, `…Multiplier` 1.1, `…UsedThisRound`; the payload
  carries `SpeedBoostUntil`; a second use in the same round is refused with zero
  writes; the boost expires on its own; a new round clears the mark and allows
  one more. Six clear paths (death, InRound false, RoundActive false,
  SelectedLevel change, respawn, CharacterRemoving) each zero both attributes.
- The round boundary flushes the round's playtime; the accrual loop flushes on
  its own 60 s interval; the REAL line `finalizePlayerSessionBody` runs on leave
  is extracted from source and executed.
- Defensive normalisation: legacy saves, 9 bad value shapes per field, malformed
  container tables, unknown milestone claim keys, non-date day strings, a prize
  record with no key. `Version` stays 4 and unknown keys survive.
- Studio branch: every path (accrual, flush, claim, spin, buy, use) works with
  `w.calls == 0` — no DataStore access anywhere.

**test_item_inventory (146)**
- BuyItem spend/refuse for both items, attribute republish, a failed write
  spending nothing and the retry buying exactly one.
- `Count`: real value, empty, `EntityShield` (not an item), unknown key,
  non-string key, non-Player, nil, unloaded session.
- `Consume`: ok + attribute republish, more than owned, 7 invalid amounts,
  non-item key, non-Player, unloaded session, and a failed write answering
  `false` with nothing spent (so a caller cannot place an unpaid marker). Every
  refusal opens zero writes.
- `DiscoverNote`: first note by sorted Id (the fake module is deliberately out of
  order), the next call giving the next id, all-owned → `false, nil, "Every note
  on this level is already in your collection"`, six bad level values, non-Player,
  no module in the place → `false, nil, "Field notes unavailable"`, a failed write
  recording nothing and leaving the same note next, and a save that already holds
  a note skipping it while the serial continues.
- Completion: the title attribute and the `ZyntraTitleTag` name-tag row appear
  with the last note, exactly one row is drawn, it stacks under the Supporter tag
  rather than replacing it, and both are cleared in a round (they are lobby badges).
- `publishSupportRows` sets `Rank`/`Name`/`Robux` on the real StringValue rows,
  clears all three on an empty row, and leaves the existing string and status
  line byte-identical.

## NOT verified offline — needs Studio

1. **Every Roblox type semantic the fakes stand in for.** `Vector3` subtraction
   and `.Magnitude`, `BillboardGui`/`TextLabel` property assignment,
   `Instance:SetAttribute` on a `StringValue`, `BindableFunction.OnInvoke`
   returning three values, `workspace:GetServerTimeNow()`. Compile is proven;
   engine behaviour is not.
2. **`os.date("!%Y-%m-%d")` under the Roblox VM** — format string and the `!`
   (UTC) prefix. Verified under standalone Luau only.
3. **The real one-second loop over real sessions** — cost per tick with a full
   server, and `HumanoidRootPart.Position` sampling while streaming.
4. **`ServerStorage.ZyntraInventory` as a real instance.** The BindableFunction
   is created at module load by this script; A-ITEMS and A-NOTES must
   `WaitForChild` it, not `FindFirstChild` at their own module load.
5. **`ReplicatedStorage.ZyntraFieldNotes`** (A-NOTES). Its mirror file landed
   during this batch and I read it for compatibility only: it returns
   `{Notes = {...}, ByLevel, Total = 12, Levels}`, with `Id` `"L<level>-NN"`,
   numeric `Level` 1..3, already sorted by Id — which is exactly what
   `fieldNoteEntries()`/`nextFieldNote()` read (`loaded.Notes`, `#Notes`,
   `note.Level == level`, re-sorted by Id anyway). I read their `Notes`, never
   their `Total`, so a partial copy cannot make a collection look complete.
   Until the module exists in Studio, `FieldNotes.Total` is 0, `TitleUnlocked`
   is false, the title attribute is `""`, and `DiscoverNote` answers
   `false, nil, "Field notes unavailable"` — all by design, and all tested.
6. **Playtime across a real round boundary / a real teleport to a reserved
   server.** Playtime is per-profile, so a reserved-server hop re-loads the
   profile; the leaving server flushes in `finalizePlayerSessionBody` first.
   Untested against a live teleport.
7. **The dispatcher wiring** (`actionRemote.OnServerEvent`, `WRITE_BEARING_ACTIONS`,
   the per-action windows) is read-verified only; the new suites exercise the
   handlers directly, not the remote.

## Decisions I made (contract additions / deviations — please note)

1. **`Daily.FlushId` (string, ≤128) is a NEW profile field not in the contract.**
   It is the identity of one playtime flush and is what makes a write that
   committed and lost its response add nothing a second time. It is server-only:
   it is NOT in the public `Daily` block, so no other agent sees it.
2. **`Daily.Day` normalizes to `nil`, not to today**, when a save has none.
   Normalization must not read a clock, and "belongs to no day yet" is exactly
   right for a pre-daily-rewards save: the first daily transaction rolls it.
   (This also keeps `test_leaderboard_backfill` green, which shadows `os` with a
   table that has no `date`.)
3. **The public `Daily` block presents the PENDING day roll.** `Day` equals
   `Today`, and `PlaytimeSeconds`/`Claimed` are zeroed when the stored day is
   stale. Publishing yesterday's claims would show a claim button the transform
   is guaranteed to refuse.
4. **`publicProfile(data, player)` takes an optional second argument** carrying
   the three session-only facts (unflushed seconds, `Accruing`, `SpeedBoostUntil`).
   Called with one argument it reports "no session facts" — existing callers and
   existing tests are unaffected.
5. **A refusal writes nothing, UNLESS the same transform already rolled the day
   or banked playtime.** Cancelling then would adopt a copy the store never
   received (CLAUDE.md's "never mutate `current` and then return false").
6. **`applyReward` refuses (returns nil) when `Protection` does not validate.**
   A shield prize is then not paid and the spin/claim is NOT recorded, so it can
   be retried once the profile is repaired. It never invents charges over an
   unresolved buy/use operation, and never touches `Revision`/`LastOperation`.
7. **A potion consumed while the round ends mid-write is lost** (the write
   landed, the boost is not applied because `roundChanged` already cleared the
   attributes). One-`UpdateAsync` window; resurrecting the boost would hand a
   lobby player a speed boost. Documented in the code.
8. **`publishRowColumns` guards on `typeof(row) ~= "Instance"`.** The offline
   receipt and backfill harnesses run `publishSupportRows` against plain-table
   rows; without the guard those two suites (336 checks) break, and I may not
   edit them. Marked with a comment in the source.
9. **The completion title is a third name-tag row (`ZyntraTitleTag`)** stacked
   under Supporter/Developer, cleared in a round like the other two.
10. **`ClaimPlaytimeReward` and `BuyItem` get per-payload write windows**
    (`ClaimPlaytimeReward:5`, `BuyItem:SpeedPotion`), like `SetAccessibility:`
    does, so two legitimate consecutive clicks on different rows of the rewards
    page do not collapse into one. Both key sets are fixed by config.
11. **`ZyntraSpeedPotionUsedThisRound` is initialised to `false` at join** and
    `ZyntraDailyAccruing` is published on the first accrual tick, so no client
    has to handle a nil.

## Open questions for the lead

1. **`ZyntraInventory` is created by this script at module load.** A-ITEMS and
   A-NOTES must `ServerStorage:WaitForChild("ZyntraInventory")`; script start
   order is not guaranteed. Please make sure both know.
2. **`DiscoverNote`'s third return is the human message**, e.g.
   `"Field note logged: Intake Log (1 of 4)."` or
   `"Field note logged: Mall Manifest. Collection complete."` — not the note
   title. A-NOTES can read the title out of its own module by the returned id.
3. **`Consume` returns `true, ""`** on success (the contract types the second
   value as `message: string`, so it is an empty string rather than nil).
4. **Route markers are not removed by me.** `RouteMarkersActive` (0..3) and
   round-end cleanup are A-ITEMS'. `ZyntraInventory` only spends the stored
   count; it never gives one back. If a marker placement fails AFTER a
   successful `Consume`, A-ITEMS must not expect a refund path from me.
5. **`MaxActive` and `MaxUsesPerRound` live in `Config.Items`** but only
   `MaxUsesPerRound` is enforced by me (the round epoch). `MaxActive` is
   A-ITEMS' to enforce server-side.
6. `Config.FieldNotes.CompletionTitle` is `"FIELD ARCHIVIST"` per the contract.

## Texture / artwork needs for Codex

None from me. Everything I own is numbers, text and attributes.

---

# Trello card text drafts (server side)

## #83 — Daily rewards: progressive playtime

**Server (ZyntraMonetization / ZyntraConfig) — done, offline-verified**

Active round playtime now persists per UTC day and pays three milestones:
5 min → 1 Research Token, 15 min → 1 Speed Potion, 35 min → 1 Entity Shield
charge. One claim each per day.

A second counts only while `InRound`, `RoundActive`, `RoundLoadingState ==
"ready"`, not `Escaped`, not `Level2_ExitTransition`, with a living Humanoid and
a HumanoidRootPart, and the player is active — moved at least 1 stud within the
last 90 s, **or** is hiding under a Level 3 table. Lobby and spectating never
count (a dead body is not a living humanoid). Playtime is never subtracted.

Seconds accrue in memory and are flushed into the existing profile transaction at
most once a minute, at the round boundary, before any claim/spin/buy/use, on
leave and in BindToClose. The flush ADDS a delta and is idempotent through a
flush id, so a write that commits and loses its response is never counted twice
and never lost. Claims fold the pending seconds into the same transaction, so a
claim at exactly 5:00 cannot be refused for the last few seconds. The day roll
resets playtime and claims lazily inside the transform.

Balance constants are in `ReplicatedStorage.ZyntraConfig.DailyRewards`
(`AfkGraceSeconds`, `ActivityMinimumStuds`, `FlushIntervalSeconds`, `Milestones`).

`tools/tests/test_daily_rewards.py` — 320 checks against the real source under
the real Luau interpreter (accrual gates, AFK, hiding, flush add/keep/dedupe,
day roll, claim refusals with zero writes, concurrency through the mutation
lock, Studio). Not yet verified in Studio.

## #84 — Free daily wheel

**Server — done, offline-verified**

One free spin per UTC calendar day. No Robux, no token spins, no rerolls, no
tickets. Five prizes with published odds that sum to 100:

- 1 Research Token — 45%
- 3 Research Tokens — 20%
- 1 Speed Potion — 20%
- 2 Speed Potions — 5%
- 1 Entity Shield charge — 10%

The prize is picked and recorded **inside** the profile transaction, before any
reply leaves the server, so the UI animates to an outcome that is already
durable. A second call the same day — a double click, a retry after a lost
reply, a rejoin, another server — grants nothing, writes nothing, and re-reports
the recorded prize ("Today's spin is done: … Next spin at 00:00 UTC"). A spin
whose write never lands records nothing and can be spun again. The Entity Shield
prize adds one stored charge without touching the shield's operation identity
(`Revision`/`LastOperation` are untouched), so a buy or use still in flight is
unaffected.

Weights live in `ZyntraConfig.DailyRewards.Wheel` and are what the UI must show.
Verified in `test_daily_rewards.py`: the weighting is measured over 20 000 picks
with a real generator and lands within 1.5 percentage points of every weight.

## #89 — Rewards reachable at the physical shop terminal

**Server contract — done**

The terminal page needs no new remote. Everything is on the existing
`Remotes.ZyntraAction` / `ZyntraProfileChanged` pair:

- `ClaimPlaytimeReward {Minutes = 5|15|35}`
- `SpinDailyWheel`
- `BuyItem {Key = "SpeedPotion"|"RouteMarker"}`
- `UseSpeedPotion`

All four are write-bearing and share the existing 1 s per-action window; the
claim and buy windows are keyed per milestone / per item so two consecutive
clicks on different rows both land.

The push payload carries everything a page needs to render real saved state:
`Items`, `Daily` (`Day`, `Today`, `PlaytimeSeconds` **including** this session's
unflushed seconds, `Claimed`, `WheelDay`, `WheelLast`, `SecondsToReset` to the
next 00:00 UTC, `Accruing`), `FieldNotes` (`Discovered`, `Count`, `Total`,
`TitleUnlocked`) and `SpeedBoostUntil`. Player attributes `ZyntraSpeedPotions`,
`ZyntraRouteMarkers`, `ZyntraSpeedBoostUntil`, `ZyntraSpeedBoostMultiplier`,
`ZyntraSpeedPotionUsedThisRound`, `ZyntraFieldNotesTitle` and
`ZyntraDailyAccruing` are published for the HUD.

`SecondsToReset` is the server's own count to the next UTC midnight, so the page
runs a local countdown without inventing a timezone, and the UTC day boundary is
the only thing that grants.
