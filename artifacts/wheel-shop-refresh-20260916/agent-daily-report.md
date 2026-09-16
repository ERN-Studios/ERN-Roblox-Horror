# A-DAILY — Daily Rewards, the inviting version (contract section 3)

Baseline `86c675d`. Four files, no Studio, no git, no manifest.

## Files

| File | What changed |
|---|---|
| `ReplicatedStorage/ZyntraDailyRewardsPage.ModuleScript.lua` | 599 -> 799 lines. Content rebuilt: countdown strip, play strip, three big colourful cards. |
| `StarterPlayer/StarterPlayerScripts/Daily Rewards Client.LocalScript.lua` | 583 -> 636 lines. Shell header replaced with the warm gradient bar (gift + title + big red X). |
| `tools/tests/test_daily_rewards_page.py` | 280 -> **480** checks. |
| `tools/tests/test_daily_rewards_client.py` | 439 -> **488** checks. |

## What it draws now

**Shell (the client owns it).** `RewardsHeader`, a white Frame with a `UIGradient`
`(255,170,60) -> (255,120,40)` at Rotation 90 (white underneath because a UIGradient
MULTIPLIES `BackgroundColor3` — over the old dark panel colour the ramp would have
rendered as a slightly-less-dark bar). Inside it: `HeaderGift` (ImageLabel
`rbxassetid://117126194981100`, ScaleType Fit, square `barHeight - 10`), `HeaderTitle`
"DAILY REWARDS" GothamBlack white with a dark UIStroke at 26 px (22 compact), and
`CloseButton` "X" GothamBlack on `Color3.fromRGB(190,60,50)`, **48x48 at every tier**
(`max(48, tap)`), with the shared `UIStyle.hover`. Bar height 64 (56 compact) plus an
8 px margin. The eyebrow "ZYNTRA // DAILY SUPPLY" is gone; both suites now fail on any
"SUPPLY" / "ZYNTRA //" string anywhere in the modal.

**Page (the page owns it).** `CountdownStrip` (dark, 28–32 tall) with one line,
`RESETS IN HH:MM:SS  ·  00:00 UTC`, from the existing `SecondsToReset` clock code;
`PlayStrip` with `PlaytimeReadout`, the existing `ProgressTrack`/`Fill` and
`ProgressCaption`; then the three cards; then the two muted footer notes (the
active-play rule and where the wheel went), unchanged.

**A card** is `Milestone<minutes>` (names unchanged), white under a per-reward
`UIGradient`, UICorner 12, a 2 px white UIStroke at 0.6 transparency, holding
`Threshold` ("5 MIN"), `RewardIcon` (ImageLabel, ScaleType Fit), `RewardName` (the
existing `rewardLabel`), `ClaimButton`, `ClaimedLabel` and `ClaimedCheck`.
Art and colours are keyed on the reward's `Kind`/`Key` — the two fields the **server**
grants from — never on the minutes, so re-ordering the config table cannot make the
page draw a token over a potion:

| reward | icon | gradient |
|---|---|---|
| Tokens | `93116899475472` | `(255,205,60) -> (255,150,30)` |
| SpeedPotion | `120211340805188` | `(80,220,255) -> (40,120,220)` |
| EntityShield | `126728249949579` | `(150,90,230) -> (60,200,140)` |

**States.** locked = dark, disabled, "M:SS TO GO"; ready = `Color3.fromRGB(70,200,90)`
"CLAIM", 44 px tall at every tier; claimed = `ClaimedCheck` (green circle, white tick,
white rim) shown over the art plus `ClaimedLabel` "CLAIMED" in the state row, with the
button **hidden** via `UIDevice.SetInteractive` (falling back to Visible/Active when a
host ships no `SetInteractive`).

**Tiers**, measured (card / icon / CLAIM, at the modal viewport each device gives):

| tier | content box | card | icon | CLAIM | canvas |
|---|---|---|---|---|---|
| phone portrait (390x844) | 334x538 | 326x150 column, icon left | 126 (84%) | 164x44 | 675 (scrolls) |
| phone landscape (844x390) | 696x236 | 222x178 row | 56 (31%) | 198x44 | 383 (scrolls) |
| tablet (1024x768) | 680x514 | 216x239 row | 108 (45.2%) | 188x44 | 465 (fits) |
| pointer (1280x720) | 680x514 | 214x251 row | 113 (45.0%) | 182x44 | 495 (fits) |

## Verified offline

```
LUAU_BIN=C:/Users/mikke/AppData/Local/Temp/codex-luau-0.737/luau.exe
python tools/tests/test_daily_rewards_page.py     -> 480 checks passed
python tools/tests/test_daily_rewards_client.py   -> 488 checks passed
luau-compile.exe --binary <both .lua files>       -> OK
python tools/tests/test_zyntra_store_compact.py   -> 540 checks (unchanged, only suite
                                                     that names the page module)
```

Both suites run the SHIPPED files (not copies) against the fake DataModel, with the real
UIStyle, the real ZyntraConfig and — in the client suite — the real page module mounted
through the real `mount(page, ctx)`. New coverage: the header gift id / Fit / parentage,
the gradient keypoints on both the header and each card, the white-underneath rule,
X >= 48 at every tier, the icon id per card, icon square + >= 56 px + >= 45% of the card
(or floored at 56 with the body scrolling), CLAIM >= 44 at every tier, the claimed state
showing the tick and hiding the button, the locked state disabled but still drawn, the
day roll taking yesterday's tick down, one-row-of-three vs one-column geometry asserted
by relative card positions, every label inside its own parent, nothing under 11 px, and
no "SUPPLY"/"ZYNTRA //" copy. Unchanged and still asserted: one mount across three
open/close cycles, `ClaimPlaytimeReward {Minutes}` with one in flight, the 6 s recovery
being a RE-READ, the profile subscription, the countdown re-anchor, `DailyRewardsOpen`,
`SuppressTouchMovement` derived from the whole modal set, all five refusals, all seven
close paths and the `UIRegressionDailyRewardsProbe` (its `cards` string is byte-identical).

## Needs Studio

1. **The four asset ids actually rendering** in a real ImageLabel at these sizes — an
   upload id is not proof of runtime display (project memory
   `mongotv-codex-proposals-need-studio-run`).
2. **The tick glyph.** `ClaimedCheck` draws `"\u{2713}"` in GothamBlack. If Roblox's font
   fallback does not cover it the circle renders empty — the state is still unambiguous
   because "CLAIMED" is spelled out beside it, but the character should be eyeballed and
   swapped if it is blank.
3. Real touch, the thumbstick suppression, font metrics/TextBounds, and whether the warm
   header reads well against the dark panel. Captures wanted: phone portrait, phone
   landscape, tablet, desktop.
4. The two `.lua` files still need `record_pending_push` + `push_repo_to_studio --file`
   by the orchestrator. Nothing here is a new script, so no manifest item is needed.

## Decisions

- **The strips stayed in the PAGE, not the shell.** The contract lists `CountdownStrip`
  and `PlayStrip` under "Shell", but the clock code, the profile subscription and the
  progress track all live in the page. Moving them would have meant a second profile
  subscription in the client for no visible difference. The client owns identity (gift,
  title, X); the page owns state. Both strips are still directly under the header.
- **"CLAIMED under the tick" reads as "tick over the art, word under it."** A 44 px state
  row cannot stack a circle and a caption without making every card taller for one state,
  so the badge sits over the icon (which is also how the owner's reference draws it) and
  the word occupies the state row the button vacates.
- **CLAIM is built by hand, not through `ctx.button`.** The host helper wires a
  `MouseLeave` that repaints its own dark card colour — it would have wiped the green off
  a ready CLAIM the moment the pointer left it. Same reason for the X in the client.
- **`PlaytimeSection` survives as the name of a transparent container** holding the play
  strip, the cards and the notes, so the "this server has no daily rewards configured"
  branch stays one `Visible` flip.
- **No seven-day streak, no new rewards, no economy change.** `Config.DailyRewards.Milestones`
  is still the only source of the three thresholds; the reference image supplied energy only.
- **48 px X on a pointer too**, not just on touch: it is the one control a screen-owning
  modal must never shrink, and it is now the floor the header bar is measured around.

## Open questions

1. **Landscape phone scrolls ~150 px.** At 844x390 the two strips take 126 px of a 236 px
   content box, so the CLAIM row sits just below the fold and needs one flick. Dropping the
   two footer notes and the progress caption on that tier alone would recover ~80 px; I did
   not add the branch because the contract explicitly allows the body to scroll there. Say
   the word if the flick is unacceptable.
2. **The icon floors at 56 px in landscape (31% of the card, not 45%).** That is the cap
   doing its job — the alternative is a taller card and more scrolling. Both suites assert
   the 45% rule with the floor as the stated exception.
3. **`ProgressCaption` and the two footer notes were kept.** The contract does not mention
   them; they are the only place the page states that lobby time and spectating do not
   count, and where the wheel went. Easy to delete if the owner wants the page barer.
