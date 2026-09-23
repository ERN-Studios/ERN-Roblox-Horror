# A-REWARDS-UI — DAILY REWARDS page (#83 / #84 / #89, UI side)

Baseline `aa40f70`. No git, no Studio, no manifest, no `_local/`. Two files written,
nothing else touched.

## Files

| Path | State |
|---|---|
| `G:\Roblox\MongoTV\ReplicatedStorage\ZyntraDailyRewardsPage.ModuleScript.lua` | new, compiles |
| `G:\Roblox\MongoTV\tools\tests\test_daily_rewards_page.py` | new, **403 checks pass** |

```
LUAU_BIN="C:/Users/mikke/AppData/Local/Temp/codex-luau-0.737/luau.exe" \
  python tools/tests/test_daily_rewards_page.py
Daily rewards page: 403 checks passed (offline Luau, config source: ZyntraConfig;
font metrics, TextBounds, real UIDevice and rendering not exercised)

"C:/Users/mikke/AppData/Local/Temp/codex-luau-0.737/luau-compile.exe" --binary \
  ReplicatedStorage/ZyntraDailyRewardsPage.ModuleScript.lua   # exit 0
```

**The test ran against the REAL `ZyntraConfig`** — A-SERVER's `DailyRewards` block
landed while this agent was running, and the page's rendered labels, weights and
percentages were asserted against it. `configSource` in the printed line says which
source was used; a contract fallback exists only for the case where the block is
absent, and it was not needed. This file is therefore a live contract test between
A-SERVER and the page: if the milestones stop being 5/15/35 or the weights stop being
45/20/20/5/10, it fails and names the row.

## What the page is

`return { mount = function(page, ctx) -> handle }`, exactly the contract's API. One
`ScrollingFrame` named `DailyRewards`, registered through `ctx.contract.scroll("Rewards", …)`,
holding three panels:

1. **Header** — eyebrow `ZYNTRA // DAILY SUPPLY`, title `DAILY REWARDS`, a live
   `RESETS IN HH:MM:SS` readout and the note `Resets 00:00 UTC`.
2. **Playtime** — `ACTIVE PLAY TODAY  12:40` (with `  //  COUNTING` appended while
   `Daily.Accruing`), a progress track, a caption naming the next milestone, three
   milestone cards (`Milestone5/15/35`) and one muted line explaining that only active
   round time counts.
3. **Supply wheel** — five segment rows with label, real odds and a proportional odds
   bar, a `FREE SPIN` / `SPUN TODAY` control, a `SKIP` control that only exists while a
   result replays, a result banner and a `Next spin in HH:MM:SS` note.

Card actions registered through `ctx.contract.card("Rewards", …)`: `Playtime5`,
`Playtime15`, `Playtime35`, `Wheel` — four, and only when the config supplies them.

## Decisions taken (not asked)

- **The wheel is a segment LIST, not a pie.** A circular wheel built from rotated
  frames is unreadable at a phone's column width and needs artwork nobody has approved.
  The brief's own wording ("five segments listed with their labels AND real odds") is
  what is drawn, plus a proportional bar per row so the odds are geometry as well as
  text. If the owner later wants a real pie face, that is the one artwork request.
- **No TweenService.** Both animation paths run on the page's own 1 Hz/frame ticker,
  which it already owns for the countdown. That removes a service, removes a tween to
  cancel on `destroy()`, and the test asserts `tweensCreated == 0` on both paths.
- **`workspace:GetServerTimeNow()` is the clock,** re-anchored from `SecondsToReset` on
  every push. It is a client-local estimate that keeps advancing while the page is
  hidden, so the countdown is correct again the moment the terminal reopens — which a
  dt accumulator gated on visibility would not be. (`os.clock()` is deliberately
  avoided: in Studio's server datamodel it is CPU time, per project memory.)
- **The UTC day is CHECKED, not assumed.** The server resets `PlaytimeSeconds` and
  `Claimed` lazily inside its transform, so between 00:00 UTC and the next write those
  fields still describe yesterday. The page treats them as zero/empty whenever
  `Daily.Day ~= Daily.Today`, and `WheelDay` is compared to `Today` separately.
  Without this, three CLAIMED cards would be drawn one second into the new day.
- **The progress track runs 0 → the LARGEST milestone** (35 min), not 0 → the next one.
  A bar that resets three times a day reads as a bug; "to the next milestone" is carried
  by the caption (`10:00 to the 15 minute reward`) and by each card's own `TO GO`.
  Flag it if the lead reads the brief more literally — it is a two-line change.
- **First profile read = seed, never a trigger.** A player who spun this morning and
  rejoins at lunch is shown the prize; only a Serial that CHANGES after the page has
  read a profile replays. An unchanged Serial on a same-day push (a replay push) shows
  the recorded prize with no animation at all.
- **Phone tier stays single column even in landscape** (816px content), because the
  brief states `fit.Compact and fit.Touch -> single column`. Landscape would read better
  two-up; open question below.
- **Surfaces and type from `ctx.UIStyle`; the two accents from `ctx.COLORS`.** The panel
  chrome, radii, strokes and faces are the shared Objectives/Mission Brief tokens; teal
  is the system accent and gold is money and only money (token prizes and token
  rewards). Shield prizes take `UIStyle.Color.Positive`. Controls are `ctx.button`, the
  terminal's own control, so the tab does not become the one page with different buttons.
- **The eyebrow is 11px, not the shared token's 10.** The brief's floor is 11 and this
  eyebrow sits in a scrolling panel held a foot from a phone, not on a HUD.
- **SKIP is deliberately NOT a contract card.** It exists only while a result replays,
  and the fit matrix requires every tagged action to be drawn; tagging it would report a
  hidden rectangle as a fault. It is still sized at the tap floor and measured by the test.
- **No config, no controls.** With `Config.DailyRewards` absent the page draws its header
  and one line, `Daily rewards are not configured on this server.`, and registers no card
  actions — a CLAIM button the server cannot honour is worse than no button.

## Disabled-button captions for `Fit.ZyntraDisabledCaptions`

These are the only captions a **tagged card action** carries while `Active == false`.
Note the entries are Lua patterns passed to `text:find`, so the ellipses must NOT be
written literally (`.` matches any character) and the locked caption is a pattern:

```lua
"CLAIMED", "CLAIMING", "%d+:%d+ TO GO", "SPUN TODAY", "SPINNING"
```

| Caption drawn | State |
|---|---|
| `CLAIMED` | that milestone is already claimed today |
| `CLAIMING...` | a claim is in flight (matched by `CLAIMING`) |
| `5:00 TO GO` / `0:01 TO GO` / `1:06:40 TO GO` | milestone not reached (matched by `%d+:%d+ TO GO`) |
| `SPUN TODAY` | today's free spin is spent |
| `SPINNING...` | a spin is in flight or its result is replaying (matched by `SPINNING`) |

`Fit.ZyntraExpectedActive` should have **no `Rewards` entry**, for the same reason Shop,
Dev and Settings have none: how many actions are reachable (0–3 claims plus 0–1 spin)
is a property of the tester's save, not of the build. The complete accounting —
reachable plus stood-down-with-a-reason equals four — is the statement that holds.

## Verified offline, and HOW

Everything below is the real module executed under real Luau, mounted through a fake
terminal that keeps the contract, with the real `UIStyle` module, the real `ZyntraStore`
`COLORS` table and its real `corner`/`outline`/`label`/`button` helpers extracted from
the LocalScript by string marker. The fake `Color3` **throws on arithmetic**, `UDim2`
and `Vector2` keep theirs.

| § | Proved by running it |
|---|---|
| 1 | Fresh day: one scroll and four cards registered under `Rewards`; header copy; all three milestones locked with their remaining time and out of the input stack; `FREE SPIN` reachable; no banner; nothing sent to the server by drawing. |
| 2 | Five prizes, weights summing to 100, each row's odds string equals `round(weight/total*100)`, labels are the owner's, and a likelier prize draws a longer bar. |
| 3 | 299s → `0:01 TO GO` disabled; 300s → `CLAIM` enabled; `Claimed["5"]` → `CLAIMED` disabled; 2100s → all three claimable, bar full, caption `Every milestone reached today.`; past an hour the readout grows an hours field; `Accruing` annotates it. |
| 4 | Day roll: `Day = yesterday` with 3000s and three claims and a spent wheel draws 0:00, three locked cards, `FREE SPIN` and no banner. |
| 5 | Countdown: 61s of real time takes exactly 61s off it; hidden it stops redrawing; shown it catches up from the CLOCK, not from what it drew last; a push re-anchors it; reaching zero re-reads the profile **once**, not once a second. |
| 6 | One press → one `ClaimPlaytimeReward {Minutes=5}`; second and third press send nothing; the push is the answer; the 6s timer does not fire for an answered request. |
| 7 | No answer: at 5s still waiting, at 6s `showStatus("No answer yet. Try again.", "error")` + `refreshProfile()` + the control comes back reachable, having sent nothing itself; a retry is a genuine second request. |
| 8 | Spin: one `SpinDailyWheel`, locked, second press ignored; the push replays — >3 highlight moves over ≥3 segments, landing on the recorded `Token3`, whole replay ≤2.5s, decelerating (last gap > first gap), zero tweens; banner `YOU RECEIVED: 3 Research Tokens`; `SPUN TODAY`; both clocks agree to the second. A same-Serial replay push animates nothing and sends nothing. |
| 9 | Resumed session: a profile that already carries a same-day `WheelLast` shows the prize and never replays it, then nothing animates for 3 further seconds. |
| 10 | `ReduceFlashing`: exactly ONE segment is ever lit (no stepping), the lit segment changes at most twice in two seconds, the fade is monotonic from invisible to fully lit over many frames, lands on the recorded prize, zero tweens. |
| 11 | A replay nobody is watching (`isVisible()` false) finishes instantly with the prize recorded. |
| 12 | `SKIP` ends the replay immediately ON the recorded prize, not wherever the highlight was. |
| 13 | `refresh()` re-renders and re-anchors from `ctx.profile()` without a push; `destroy()` disconnects the ticker (heartbeat listener count drops), disconnects the profile subscription, destroys its own tree and leaves the terminal's page frame empty; later frames do nothing and `refresh()` after destroy is a no-op. |
| 14 | Four fits — 390×844, 844×390, 1024×768, 1280×720 — rebuilt from `applyTerminalLayout`'s own figures. Per fit: every panel and every card inside `ContentWidth` and ≥ 0; every card action drawn, inside the content box, inside the canvas, and ≥ 44×44 on touch; two columns non-overlapping and top-aligned on tablet/pointer, stacked full-width on phone; canvas reaches the last row; the smallest face on the whole page ≥ 11px; every wheel row inside its column with the label clear of the odds readout. |
| 15 | Mounting with `ctx.contract`, `ctx.showStatus` and `ctx.isVisible` absent does not error and still draws. Config-absent draws the offline line, hides both sections and registers no card actions. |

## NOT verified — needs Studio

- Real font metrics and `TextBounds`. No `TextService` call is made and no layout branch
  is chosen on a measurement, so nothing can be silently mis-measured — but a long
  label could still wrap or ellipsize where the reserved box assumes it will not. The
  ones to look at: the milestone reward line, the wheel segment labels, the two-line
  playtime note and the result banner, on a 390-wide phone.
- Real `UIDevice`. The harness fakes `SetEnabled` as `element.Active = enabled`, which is
  the observable half; the real one also carries `Selectable`/`Modal` and early-returns
  for non-buttons. Gamepad selection on this page is untested.
- Real `UIStyle`/`UICorner`/`UIStroke` rendering, gradients, and how the whole thing
  actually looks. Desktop, tablet and phone captures are the proof.
- The mount itself: A-SHOP-UI writes it. Nothing here has been mounted by the real
  ZyntraStore, and the tab does not exist until the lead creates the ModuleScript in
  Studio.
- Live server behaviour: that a real `ClaimPlaytimeReward` / `SpinDailyWheel` answers
  with a push carrying the fields this page reads, and that a second same-day spin
  re-pushes the SAME `Serial` (the replay path depends on that).
- Scroll feel, and whether the two-column tablet layout needs the wheel column taller
  than the playtime column in practice.

## Open questions for the lead / owner

1. **Phone landscape** (844×390 → 816px of content) is drawn as one column per the
   brief. Two columns would fit comfortably. Want the tier rule changed to
   `twoColumn = usable >= 620` regardless of tier?
2. **Progress track scope** — 0 → 35 min (shipped) vs 0 → the next milestone (a literal
   reading of the brief). Two lines either way.
3. `Daily.Accruing` is rendered as `  //  COUNTING` appended to the readout. If A-HUD is
   also surfacing `ZyntraDailyAccruing` somewhere, one of the two should probably go.
4. The page calls `ctx.refreshProfile()` once when the countdown reaches zero. If the
   terminal already re-reads on a day roll, that is a duplicate read — harmless, but say
   so and it comes out.

## Artwork needed from Codex

**None.** The page uses no image assets: the wheel, swatches, bars and progress track are
UI frames, and the type is the shared faces. If the owner later wants a literal pie
wheel the ask would be one 512×512 PNG with transparency, five segments, flat colour, no
text baked in (labels stay live) — but that is a separate decision, not a blocker.

## Trello draft

**#89 — Daily rewards tab (UI)**
> One DAILY REWARDS tab in the Zyntra terminal, drawn in the shared UIStyle so it reads
> like the Objectives panel and the Mission Brief. Header carries a live countdown to the
> UTC reset and says `Resets 00:00 UTC` in plain words. Everything on the page is read
> back from the saved profile — the page never grants, never picks a prize and keeps no
> second copy of the state, so a lost answer, a rejoin, a retry, midnight and a double
> press cannot grant twice. A request nobody answers for 6 s puts the control back and
> RE-READS the profile instead of guessing. Phone, tablet and desktop tiers; every touch
> target at or above 44 px; nothing printed below 11 px.
> Offline proof: `tools/tests/test_daily_rewards_page.py`, 403 checks under real Luau
> against the real UIStyle, the real ZyntraStore helpers and the real ZyntraConfig.

**#84 — Free daily wheel (UI)**
> Five prizes with their REAL odds printed next to them (45/20/20/5/10, computed from the
> server's own weights, never typed in twice) and a proportional bar per row. One free
> spin a calendar day — no Robux spins, no token spins, no rerolls, no tickets, no
> near-miss. The server picks AND writes the prize before it answers; the animation is a
> replay of that record, it is skippable, it stops if the terminal closes, and a
> same-day replay push shows the prize without animating. `ReduceFlashing` replaces the
> stepping pass entirely with one slow fade to the winning segment — no stepping, no
> flicker, at most one colour change.

**#83 — Progressive playtime (UI)**
> `ACTIVE PLAY TODAY` with a progress track and three milestone cards: 5 min → 1 Research
> Token, 15 min → 1 Speed Potion, 35 min → 1 Entity Shield charge, one claim each per UTC
> day. Card states come only from the save: locked with the exact time remaining, CLAIM,
> CLAIMING while in flight, CLAIMED. The page states in one line that only active round
> time counts — not the lobby, not spectating. The UTC day boundary is checked on the
> client too, so the page cannot show yesterday's claims one second into the new day.
