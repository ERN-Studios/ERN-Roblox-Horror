# A-WHEEL report — Trello #103, real Lucky Wheel + dedicated side button

Baseline read: `CLAUDE.md`, `claude-contracts.md`, `OWNER-BRIEF.md`,
`assets-handoff.md`. Nothing outside my two files was touched.

## Files

| File | State |
|---|---|
| `StarterPlayer/StarterPlayerScripts/Lucky Wheel Client.LocalScript.lua` | NEW (mirror only — the lead creates it in Studio, then adds the manifest item) |
| `tools/tests/test_lucky_wheel_client.py` | NEW |

Confirmed against A-RAIL's landed work while writing: `SCREEN_OWNING_MODALS`
already carries `"LuckyWheelOpen", "DailyRewardsOpen"`, and
`ZyntraStore.lobbyModalOpener("OpenLuckyWheel")` creates the same BindableEvent
with the same refusal set. Both sides create-if-absent, both refuse
independently.

## Verified offline, and how

`"C:/Users/mikke/AppData/Local/Temp/codex-luau-0.737/luau-compile.exe" --binary
"StarterPlayer/StarterPlayerScripts/Lucky Wheel Client.LocalScript.lua"` — compiles.

`LUAU_BIN=... python tools/tests/test_lucky_wheel_client.py` —
**530 checks passed** (417 as first written; 433 after Fix 1, 530 after Fix 2 — both below). The test is not string matching: the entire LocalScript
runs under a fake DataModel with the **real** `UIStyle` and **real**
`ZyntraConfig` modules, and every assertion is made by driving it (firing the
open bindable, pressing SPIN, pushing a profile, stepping Heartbeat, rotating
the device) and reading what the script did to its own instances, to
`ZyntraAction` and to the tween it asked for.

What the 417 cover:

- **Construction.** ScreenGui name / DisplayOrder 118 / `ResetOnSpawn = false` /
  `ScreenInsets = CoreUISafeInsets`; Active shade; ScrollingFrame body; disc,
  rim, hub, pointer present; rim and hub are `UICorner(1,0)` circles drawn by a
  `UIStroke`, not images; the pointer and rim are **siblings** of the disc, so
  neither turns with it.
- **180 arms**, `Rotation = (i-1) * 2`, each centred on the hub
  (`AnchorPoint (0.5, 0.5)`, `Position` scale 0.5/0.5) and the FULL diameter
  tall, transparent, carrying one coloured top-half spoke at its origin; arm 1
  points at 12 o'clock where the pointer is. See Fix 1.
- **Wedge size IS the odds.** Counted per colour off the built disc: 81 / 36 /
  36 / 9 / 18 spokes = exactly `weight * 1.8` for 45/20/20/5/10, five
  contiguous runs accounting for all 180 with nothing left over, five distinct
  colours, and **no wedge sharing a colour with the wedge next to it**.
- **Legend** = one row per config prize, printing the config `Label` and the
  odds derived from the server's own weights (`45% 20% 20% 5% 10%`), with a
  swatch in the wedge's colour.
- **Open/close.** Opening publishes `LuckyWheelOpen` and calls
  `SuppressTouchMovement(ScreenOwningModalOpen())`; refused while `InRound`,
  `ZyntraStoreOpen`, `ZyntraReentryOpen`, `DailyRewardsOpen`, `QueueModalOpen`;
  closed by CLOSE, Escape, gamepad ButtonB, `InRound → true`,
  `RoundActive → true`, `QueueModalOpen → true`; every close clears the
  attribute, and suppression after close is derived from the whole published
  modal set (the queue case correctly leaves the cluster down for the queue).
- **Spin flow.** SPIN fires `SpinDailyWheel` **once** with no payload and locks;
  a double press cannot become a second request; nothing spins before the server
  answers.
- **The server's result decides where it lands — 100 checks.** Every one of the
  five prizes at Serial 1..20, replayed on one disc that keeps turning: exactly
  one tween per push, played, on the disc, always forward, and the pointer angle
  `(-goal) % 360` falls inside that prize's own wedge. Plus: every landing is
  ≥ 4° clear of a wedge boundary, and the same Serial lands on the identical
  degree on a second client.
- **Animation.** 4.2 s Quint/Out, ≥ 3 whole turns; SKIP jumps to the goal and
  cancels the tween; a completed tween lands the same; `ReduceFlashing` gives
  1.4 s Sine, ≤ 720° and never backwards; closing mid-spin finishes the replay.
- **Replay ≠ spin.** The first profile read SEEDS (a rejoin parks the disc in
  the recorded wedge and announces it without animating); a same-Serial push
  animates nothing however often it repeats; yesterday's `WheelLast` is not
  today's result.
- **Countdown.** `Next spin in HH:MM:SS` re-anchored on every push, ticking at
  1 Hz only while visible (a closed panel redraws nothing), one — and only one —
  profile re-read at the UTC roll.
- **Timeout.** 6 s of silence → status line `No answer yet. Try again.`, SPIN
  re-enabled, one `ZyntraGetProfile:InvokeServer()` re-read, still zero tweens.
  An answered request never reports a stale timeout later.
- **Layout at five stated ModalViewports** (1280×720, 390×844, 844×390,
  1024×768, and an inset 1280×720 at origin 24,40): panel inside the viewport,
  every panel child inside the panel, every body child inside the content width,
  `CanvasSize` covering everything the content reaches, CLOSE/SPIN/SKIP ≥ 44 px
  on touch, every text ≥ 11 px, no keyboard glyph on any device. Plus a
  portrait→landscape→portrait rotation.
- **Gamepad and probe.** `GuiService.SelectedObject` is set only when
  `LastInput() == "Gamepad"` and handed back on close; the
  `UIRegressionLuckyWheelProbe` BindableFunction exists only under
  `RunService:IsStudio()` and answers `open` / `close` / `state` with the
  resulting panel visibility.

Resolved geometry after Fix 2, for the lead's Studio comparison (read out of a
real boot at each stated ModalViewport):

| Viewport | Panel | Tier | Body | Disc (holder) | Canvas | SPIN |
|---|---|---|---|---|---|---|
| 1280×720 pointer | 820×620 | 3, two columns | 472 | 341 (364) | 364 | body y184, h40 |
| 390×844 phone portrait | 390×620 | 1, stacked | 452 | 260 (278) | 596 | **footer** y536, h44 |
| 844×390 phone landscape | 820×390 | 1, stacked | 222 | 202 (216) | 534 | **footer** y306, h44 |
| 705×338 short landscape | 705×338 | 1, stacked | 170 | 150 (162) | 480 | **footer** y254, h44 |
| 1024×768 tablet | 820×620 | 2, stacked | 424 | 260 (278) | 610 | **footer** y532, h44 |

On every touch row the holder is shorter than the body, so the whole wheel is on
screen with nothing to scroll for; only the legend, banner and note are below the
fold, and SPIN is never in the scroll at all.

## NOT verified — needs Studio

- That 180 rotated arms actually **render** as a clean disc: seams between
  spokes, antialiasing at the rim, and whether `spokeWidth = ceil(r·2π/180)+1`
  leaves visible gaps or visible overlap at 341 px and at 260 px. **This is the
  first thing to look at after Fix 1** — the offline test can prove the arms
  pivot about the hub, not that the result looks like a disc.
- Whether the **diamond pointer** reads as a pointer. It is a 45°-rotated square
  straddling the rim; the half above the rim is what the player sees. A real
  triangle needs an ImageLabel, and this card ships no disc artwork on purpose.
- **Font metrics / TextBounds**: whether the short sector labels ("1 TOKEN",
  "3 TOKENS", "1 POTION", "1 SHIELD") fit inside their wedges at the phone disc
  (260 px) without clipping, and whether the legend label column ellipsizes at
  the narrowest tier.
- **Real tween feel**: 4.2 s Quint/Out on a real frame budget, and whether the
  1.4 s `ReduceFlashing` turn is actually calmer rather than merely shorter.
- Whether the five wedge colours are distinguishable **to a human eye** on a
  real screen (the test only proves they are distinct values).
- Whether the modal reads correctly stacked against the rail's own DisplayOrder,
  and that the rail button's icon (A-RAIL) opens exactly this modal.
- Live `SpinDailyWheel` round trip against the real server (the offline run
  fakes the remote).

## Decisions taken

1. **Five wedge colours = three prize families × a brightness step.** Colouring
   purely by reward kind puts a 162° gold wedge next to a 72° gold wedge and a
   72° teal next to an 18° teal — they read as ONE wedge, which is the owner's
   "equal sectors must not imply equal odds" failure inverted. Every second
   sector is therefore drawn at 62% brightness. The family still says what kind
   of prize it is, and every neighbour pair is distinguishable. Resolved values:
   `Token1 (255,203,79)`, `Token3 (158,126,49)`, `Potion1 (68,221,196)`,
   `Potion2 (42,137,122)`, `Shield1 (127,218,166)`. Built with scaled *numbers* —
   Color3 itself is never used in arithmetic.
2. **Jitter is an integer hash of `WheelLast.Serial`, not `Random.new`.** The
   same recorded result must land on the same degree on every client and on
   every redraw, including the park after a rejoin. `(serial * 2654435761) %
   1000003` stays inside double exact-integer range.
3. **One deviation from the contract's rotation formula, one line:**
   `if spinGoal <= current then spinGoal += 360 end`. The literal formula
   `current - (current % 360) + target + 360 * turns` can resolve BEHIND the
   current rotation when `turns == 1`, because the whole-turn boundary is up to
   360° back — a backwards jerk, on the `ReduceFlashing` path of all places. The
   5-turn path can never reach it (`goal - current > 1080`), so the shipped
   spin is byte-identical to the contract.
4. **Spoke → sector is integer cross-multiplication against cumulative
   WEIGHTS**, never against float degrees, so a 45% wedge gets exactly 81 spokes
   rather than 80 or 82 depending on how `162.00000000000003` rounds.
5. **Rim, hub and pointer are siblings of the disc, not children.** Rotating a
   circle is invisible work on every frame of a 4.2 s tween.
6. **Sector labels only on wedges ≥ 36°**, so the 18° (5%) wedge carries none —
   which is exactly why the legend prints the odds for all five.
7. **SKIP and the result banner are sized on every layout pass whether or not
   they are drawn.** A control whose rectangle only exists after it has been
   shown once is a rectangle the fit matrix cannot measure.
8. **Opening is also a profile re-read.** A wheel opened minutes after the last
   push would otherwise draw a countdown anchored to a stale `SecondsToReset`.
9. **Two columns above 560 px of content width**, otherwise stacked — so a
   narrow desktop window gets the phone composition rather than a squeezed one.
10. **No sound, and the disc rotation is the only tween in the file**, per brief.

## Open — for the lead

- **Asymmetry the contract states and I followed:** `RoundActive → true`
  *closes* the wheel, but `RoundActive` is **not** in the refuse-to-open list
  (which is `InRound` / `ScreenOwningModalOpen` / `QueueModalOpen`). In Studio's
  local lobby a player not in the round can therefore still open the wheel while
  someone else's round runs, and it will not close until `RoundActive` next
  changes. Adding the guard would make the wheel unopenable during any Studio
  round, which may break the playtest recipe — so I left the contract as
  written. Say the word and it is one line.
- The mirror file exists but **no Studio script and no manifest item**: new
  scripts cannot be pushed by the tools (CLAUDE.md), so the lead must create
  `StarterPlayerScripts."Lucky Wheel Client"` via `execute_luau` +
  `UpdateSourceAsync`, then add the manifest item with `sha256_of` /
  `canonical_bytes`.
- For A-RAIL's `UIRegression` work: the captions this modal can print are listed
  below; none of them is device-conditional, and none contains a key glyph.

## Exact strings

**Instance names** (all under `PlayerGui.LuckyWheelGui`):

```
LuckyWheelGui                    ScreenGui, DisplayOrder 118, ResetOnSpawn false,
                                 ScreenInsets CoreUISafeInsets
  LuckyWheelShade                Frame, Active, full safe area
    LuckyWheelPanel              Frame (UIStyle.panel, Card tokens)
      Eyebrow / Title / CloseButton / StatusLine
      WheelBody                  ScrollingFrame
        DiscHolder
          WheelDisc              the rotating Frame
            Spoke1 .. Spoke180
            SectorLabel1, SectorLabel2, SectorLabel3, SectorLabel5
          WheelRim / WheelHub / WheelPointer     (siblings of the disc)
        WheelLegend
          LegendRow1 .. LegendRow5  ->  Swatch, LegendLabel, LegendOdds
        SpinButton / SkipButton
        ResultBanner -> ResultText
        NoteLine
  UIRegressionLuckyWheelProbe    BindableFunction, Studio only
```

Player attribute: `LuckyWheelOpen` = `true` while drawn, `nil` otherwise.
Open bindable: `PlayerScripts.OpenLuckyWheel` (created if absent).

**Captions, verbatim:**

| Where | Text |
|---|---|
| Eyebrow | `ZYNTRA // DAILY SUPPLY` |
| Title | `LUCKY WHEEL` |
| CloseButton | `CLOSE` |
| SpinButton | `FREE SPIN` / `SPINNING...` / `SPUN TODAY` |
| SkipButton | `SKIP` |
| ResultText | `YOU RECEIVED: 1 Research Token` (and the other four config Labels) |
| NoteLine, unspent | `One free spin a day. Resets 00:00 UTC.` |
| NoteLine, spent | `One free spin a day. Resets 00:00 UTC.  Next spin in 01:00:00` (two spaces before "Next") |
| NoteLine, no config | `Daily rewards are not configured on this server.` |
| StatusLine, timeout | `No answer yet. Try again.` |
| LegendOdds | `45%` `20%` `20%` `5%` `10%` |
| SectorLabel1/2/3/5 | `1 TOKEN` `3 TOKENS` `1 POTION` `1 SHIELD` |

## Trello draft — card #103

> **Real Lucky Wheel with its own side button — done (pending Studio QA).**
>
> The wheel is now an actual spinning wheel in its own modal
> (`StarterPlayerScripts."Lucky Wheel Client"`, ScreenGui `LuckyWheelGui`),
> opened by its own square rail button next to the shop and terminal buttons.
> The Rewards list the terminal used to draw is gone from this card's scope
> (#104 owns the milestones).
>
> **The odds are the picture.** The disc is built from 180 rotated frames
> coloured straight from the server's own weights, so the five wedges are
> genuinely proportional — 162° / 72° / 72° / 18° / 36° for 45% / 20% / 20% /
> 5% / 10%. Nothing is a PNG, so the day a weight changes the wedge changes with
> it. A legend beside the disc (under it on phones) prints the real percentage
> for every prize, including the 18° one that is too narrow to carry a label, and
> no wedge shares a colour with the wedge beside it.
>
> **The server still decides.** `SpinDailyWheel` goes out once, the server picks,
> grants and records the prize, and the client only animates to the
> `Daily.WheelLast` it is handed: 4.2 s, five turns, Quint decelerating into the
> recorded sector, with a stationary pointer at 12 o'clock. A replay of the same
> Serial does not animate, a rejoin parks the disc on the prize already won, and
> there is no client-side roll anywhere in the file. One free spin a day, no paid
> spins, no rerolls; the countdown to 00:00 UTC comes from the server's own
> `SecondsToReset`.
>
> Accessibility: `ReduceFlashing` replaces the five-turn spin with one slow
> 1.4 s turn, SKIP jumps straight to the result, every touch target is ≥ 44 px
> and no text is under 11 px. The panel is measured against UIDevice's
> ModalViewport and lays out at phone portrait, phone landscape, tablet and
> desktop.
>
> Offline proof: `tools/tests/test_lucky_wheel_client.py` — 530 checks, the
> whole real LocalScript under real Luau with the real UIStyle and ZyntraConfig
> modules, including every prize at twenty different Serials landing inside its
> own wedge. Rendering, fonts and real tween feel are Studio QA.


## Fix 1 — the spokes pivoted in the wrong place (lead review, blocking)

**What was wrong.** Roblox rotates a GuiObject about the **centre of its own
rectangle**; `AnchorPoint` only places the rectangle, it is not the pivot. The
first version made each slice a single `Size (spokeWidth, radius)` frame
anchored `(0.5, 1)` on the hub — so every one of them span about a point
`radius/2` **above** the hub, and the 180 together would have drawn a flower
ring, not a disc. Caught by the lead in review; the offline harness could not
see it, because a fake DataModel has no rendering.

**What it is now.** The standard pivot pair, per the lead's instruction:

- `Arm<i>` — transparent `Frame`, `AnchorPoint (0.5, 0.5)`,
  `Position UDim2.fromScale(0.5, 0.5)`, `Size UDim2.fromOffset(spokeWidth,
  discSize)` (the **full diameter**, so the rectangle's own centre IS the disc
  centre under either pivot rule), `Rotation = (i-1) * 2`.
- `Spoke<i>` — the coloured child inside it, `Size UDim2.new(1, 0, 0.5, 0)` at
  `Position UDim2.new()`: the **top half only**, so `Arm` rotation 0 still paints
  the 12 o'clock ray exactly as before.

`applyLayout` now resizes **only the arms** (`Size (spokeWidth, discSize)`); the
coloured half follows by scale and is never written again after build. Sector
labels are unchanged — they are children of `WheelDisc`, which is its own centre
(`AnchorPoint (0.5, 0.5)`, `Size (discSize, discSize)` centred on the hub).

**Nothing else moved.** The spoke → sector mapping, the colours, the rotation
maths, the rim/hub/pointer and the whole open/close/spin contract are untouched.

**One harness bug found while fixing it.** The fake's `UDim2.new()` returned four
`nil`s instead of `(0, 0, 0, 0)`, so a position comparison against zero would
have passed against nil. Fixed in the fake, not worked around in the test — the
engine's constructors zero-fill and the fake must too.

**New coverage** (16 checks, 417 → **433**): every arm's rotation, that it is
centred on the hub AND the full diameter AND transparent, that its spoke is the
top half by scale sitting at the arm's origin, that the arm is about one 180th of
the circumference wide, and — at all five stated viewports — that the layout pass
resizes the arm to the full diameter while leaving the coloured half unwritten.
The 81/36/36/9/18 per-sector counts, contiguity, five distinct colours and the
no-neighbour-shares-a-colour rule are all still asserted, now read off the arms'
children.

Recompiled (`luau-compile --binary`, clean) and rerun: **433 checks passed.**


## Fix 2 — SPIN was under the fold on landscape phones (lead review, native measurement)

**What was wrong.** Measured by the lead in Studio Play with the viewport
override: at 844×390 the panel resolved to 820×316, the body to 202 px, the disc
alone was 260, and `SpinButton` landed at y 600 inside a 604 px canvas. At
705×338 the body was 150. A player had to scroll past the entire wheel and its
five legend rows to reach the one control the panel exists for. The offline fit
checks all passed, because "inside the content width with a canvas that covers
it" is true of a control at the very bottom of a long scroll — reachability is a
different property from containment, and the first version only asserted the
second.

**What it is now.** Two changes, touch tiers only (1 and 2):

1. **SPIN and SKIP are a fixed footer.** On touch they are reparented to `panel`
   and laid out as one row directly above the status line
   (`footerTop = height - pad - statusHeight - gap - spinHeight`,
   `spinHeight = max(tap, 40)` = 44). While SKIP is visible it takes
   `max(tap, 92)` px on the right and SPIN the rest of `bodyWidth`; otherwise
   SPIN takes the whole row. `body` is shortened by `spinHeight + gap`, so the
   footer never sits over the scroll. The disc, legend, banner and note keep
   scrolling in the body.
2. **The disc fits the body on short screens.**
   `discSize = min(260, contentWidth, bodyRoom - 20)` clamped to ≥ 140, so the
   whole wheel is visible without scrolling at 844×390 (202 px disc in a 222 px
   body) and at 705×338 (150 px in 170 px).

**The pointer tier is untouched** — 341 px disc, two columns, SPIN in the body
under the legend, exactly as reviewed. Reparenting is guarded on
`spinButton.Parent ~= wanted`, so a layout pass that does not change tier moves
nothing.

Every existing rule still holds and is still asserted: ≥ 44 px touch targets,
≥ 11 px text, no keyboard glyphs, everything inside the ModalViewport, and the
banner/SKIP still carry a measurable rectangle whether or not they are drawn.

**One harness bug found while fixing it.** The fake's `Parent` setter added the
child to the new parent without removing it from the old one, so a control that
moves between `body` and `panel` would have been findable in both and a
parent assertion could have passed against a stale copy. Fixed in the fake.

**New coverage** (57 checks, 433 → **530**), including a fifth stated viewport
(705×338, the short landscape the lead measured):

- SPIN and SKIP are `panel` children on all four touch fits and `body` children
  on the pointer fits.
- The footer is inside the panel, sits **above** the status line and **below**
  the body, never over either.
- The holder's full height fits inside the body at every touch viewport — the
  whole disc is visible with no scrolling — while still ≥ 140 px.
- The footer split while a replay runs, at all four touch viewports: SKIP keeps
  its 92 px strip on the right, SPIN gives up exactly that width and stays ≥ 100
  px wide, both stay 44 px tall, the row does not move when SKIP appears, the two
  never overlap, SKIP stays inside the panel, and SPIN takes the row back when
  the replay ends.

Recompiled (`luau-compile --binary`, clean) and rerun: **530 checks passed.**
