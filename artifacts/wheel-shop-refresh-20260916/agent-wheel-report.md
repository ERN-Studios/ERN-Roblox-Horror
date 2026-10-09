# A-WHEEL report — Lucky Wheel, full-screen takeover (2026-09-16)

Contract: `claude-contracts.md` section 1. Baseline `86c675d`.

## Files

| File | Change |
|---|---|
| `G:/Roblox/MongoTV/StarterPlayer/StarterPlayerScripts/Lucky Wheel Client.LocalScript.lua` | rewritten, 979 -> 785 lines |
| `G:/Roblox/MongoTV/tools/tests/test_lucky_wheel_client.py` | rewritten, 475 checks |

Nothing else touched. No Studio, no git, no `studio-sync-manifest.json`.

## What it is now

`LuckyWheelGui` (118, ResetOnSpawn false, CoreUISafeInsets) -> `WheelShade`
(full-screen, black @0.35, Active) -> `WheelHolder` (square, centred on the whole
`Display`) -> `WheelDisc` (ImageLabel `rbxassetid://86770264881525`, ScaleType
Fit, the one animated `Rotation`), `WheelPointer` (Frame, Rotation 45, fixed at
12 o'clock), `HubButton` (circular TextButton, SPIN lives here). `CloseButton`
"X" is the shade's other child, pinned to `Safe` top-right with an 8 px margin.
The disc carries exactly ten TextLabels: `FieldLabel1..5` and `FieldOdds1..5`,
each rotated `72*(i-1)` so it turns with its field.

Gone: the panel, eyebrow, title, legend, banner, note line, status line,
scrolling body, the SPIN/SKIP footer, the 180-arm disc, the rim, the old hub
frame. The only frames left in the whole gui are the shade, the holder and the
pointer.

Kept verbatim: `SpinDailyWheel` with one request in flight, the 6 s no-answer
re-read, the `WheelLast {Day, Key, Serial}` seed-vs-trigger rule (the first
profile of a session parks, it never animates), the deterministic
jitter-from-Serial, ReduceFlashing = one 1.4 s Sine turn, close on
Escape / ButtonB / InRound / RoundActive / QueueModalOpen,
`SuppressTouchMovement(ScreenOwningModalOpen())` on open and after close,
`blockedFromOpening`, the attribute `LuckyWheelOpen`, the Studio-only
`UIRegressionLuckyWheelProbe`, and the gamepad focus/ButtonB binding.

## Verified offline

`python tools/tests/test_lucky_wheel_client.py` with
`LUAU_BIN=C:/Users/mikke/AppData/Local/Temp/codex-luau-0.737/luau.exe`:

```
Lucky Wheel client: 475 checks passed
```

`luau-compile.exe --binary` on the LocalScript: clean.

The harness is unchanged in kind — the entire real LocalScript runs against a
fake DataModel with the real `UIStyle` and `ZyntraConfig` — with these additions:
`ScreenGui.Enabled` defaults true, `ImageLabel` carries
`Image/ScaleType/ImageColor3/IsLoaded`, `ChildAdded` fires on reparent (after
`.Parent` is already the new one), `Destroy()`, `CharacterAdded`, and each
viewport row now states a `Display`/`Safe` pair instead of a `ModalViewport`.
`Color3` still has no operators and `Rotation` is still a plain number.

What the 475 cover:

- **Structure** — the disc is an ImageLabel with that asset id, Fit, filling the
  holder by scale and centred in it; pointer and hub are siblings of the disc,
  not children; nothing named Panel/Body/Legend/Banner/Spin/Skip/Eyebrow/Note/
  Status/Rim/Arm exists; no ScrollingFrame; the shade has exactly two children.
- **Fields** — five names and five odds, the right texts (`1 TOKEN` ... `1 ENTITY
  SHIELD`, `45% 20% 20% 5% 10%` off the server's own weights), rotations
  `72*(i-1)`, polar positions at 0.80 R and 0.36 R, glyph-outlining strokes, the
  short copy below side 300, and field 1 at 12 o'clock so the texture's
  orientation and the maths agree.
- **Viewports** — 1280x720 -> 619, 390x844 -> 335, 844x390 -> 335, 1024x768 ->
  640 (the clamp), 705x338 -> 290, 749x310 -> 266; side <= min(w, h) on every
  one; centred on the display within a pixel; hub >= 56 and equal to
  `max(56, floor(side*0.26))`; X >= 48, inside `Safe`, at exactly 8 px; pointer
  >= 18 and at (0.5, 0); both above the disc in ZIndex; rotation re-lays out.
- **Landing** — 100 replays (5 keys x 20 serials) each produce one forward tween
  on the disc landing the pointer inside the awarded field; 200 more confirm
  every landing sits in [6, 66] of its 72-degree field and spreads across it;
  the same Serial lands identically on two clients and on a rejoin park.
- **Forward travel in both modes** — 100 landings at 5 turns and 100 at 1 turn,
  all strictly forward and >= one whole turn. See the deviation below.
- **The hub** — SPIN -> SPINNING (request in flight, no second send on a double
  press) -> RETRY after 6 s with exactly one re-read and no client-side grant,
  and RETRY re-asks; a tap while the disc turns skips, cancels the tween and
  finishes exactly once; a second tap afterwards sends nothing and starts
  nothing; the prize (`1\nSHIELD`, `2\nPOTIONS`) holds 3.5 s then becomes
  `SPUN\nHH:MM:SS`; two landings in one session do not let the older 3.5 s timer
  cut the newer window short; text sizes are `0.30`/`0.19` of the diameter and
  never below 11.
- **Countdown** — `SPUN\n01:01:01`, two lines, ticking at 1 Hz, silent while
  closed, caught up on reopen, and one single re-read at the UTC roll.
- **Takeover** — every other ScreenGui in PlayerGui goes off on open and comes
  back on close; one already off stays off; one that re-enabled itself while
  hidden is left alone; one parented in while open is disabled and restored; one
  destroyed while hidden is not resurrected; `CharacterAdded` closes, restores
  and clears the flag; open/close twice is idempotent; a refused open takes
  nobody's screen.
- **Modal hygiene** — refuses to open under InRound / ZyntraStoreOpen /
  ZyntraReentryOpen / DailyRewardsOpen / QueueModalOpen; all six close paths
  clear the attribute, hand the UI back and leave `SuppressTouchMovement`
  derived from the whole published modal set; Escape does nothing while shut.
- **Copy** — on three viewports, no drawn string contains "SUPPLY" or "ZYNTRA"
  and every drawn string is >= 11 px.
- **Gamepad / probe** — the pad lands on the hub (on the X when the day is
  spent), selection is handed back on close, a keyboard gets no forced
  selection, and the probe exists only in Studio.

## Needs Studio (cannot be seen offline)

1. **The asset.** That `rbxassetid://86770264881525` loads, and that its rim
   meets the pointer where the pointer is drawn. The pointer is centred on the
   holder's top edge, which assumes the art's circle reaches the edge of its
   square. If the PNG carries air around the motif, the pointer will float off
   the rim — the fix is one multiplier on `pointer.Position`.
2. **Field-name fit.** `1 SPEED POTION` is 14 characters at TextSize 13 in a
   0.34-wide box on a 390x844 phone (side 335, box ~113 px). It is the tightest
   case in the matrix and only real TextBounds can settle it. One constant,
   `SHORT_LABEL_SIDE` (currently 300), switches that row to `1 POTION`; raising
   it to ~380 covers the phone.
3. **Landscape topbar.** The contract centres and sizes the disc on the whole
   `Display`, so on 844x390 the disc (335) is taller than the safe area (332)
   and its top edge reaches into the topbar band. That is inherent to
   `0.86 * min(display)` and is what the contract asks for; if the owner wants
   clearance, `applyLayout` reads `display` in exactly one place.
4. **Feel** — the 4.2 s Quint, whether the rotating field copy is readable while
   turning, and whether the gold hub reads as pressable over the gold rim.
5. **Regression matrix.** `UIRegression` does not drive
   `UIRegressionLuckyWheelProbe` today (grepped), so nothing there needed
   changing. Its `Fit.ZyntraDisabledCaptions` list still carries "SPUN TODAY",
   which this file no longer prints — that entry belongs to the terminal's own
   cards, so it was left alone.

## Decisions where the contract left room

- **The hub stays Active while the disc is turning.** The contract says both
  "SPINNING (button disabled via `UIDevice.SetEnabled`)" and "a tap on the hub
  while spinning SKIPS". `GuiButton.Activated` does not fire on an inactive
  button, so those cannot both hold. Split: disabled while the REQUEST is in
  flight (nothing to skip, and a second tap must not re-ask), active while the
  disc turns (that tap is the skip). Text is "SPINNING" in both.
- **`SPINNING` takes the small text face.** The contract gives the big face
  (0.30 of the diameter) to "the one-word state". Eight characters at 0.30 of
  the circle are wider than the circle, so only SPIN and RETRY take it;
  SPINNING, the prize and the countdown take 0.19.
- **The prize is two lines** — `"1 SHIELD"` is drawn `"1\nSHIELD"`, because a
  circle is not a row. The contract allows two lines.
- **The remembered `Enabled` value is honoured on restore.** The contract says
  restore remembered guis that are still `false`; this also refuses to switch on
  a gui the game had deliberately disabled before the wheel opened. Turning
  someone else's hidden HUD on would be a worse bug than leaving it off.
- **The pointer is the blessed Frame-at-45-degrees diamond**, not the `▼`
  TextLabel: Gotham's coverage of the geometric-shapes block is not something
  this session could verify, and the rotated frame is what shipped before.
- **`FIELD` is derived as `360 / #sectors`**, not the literal 72, so the label
  rotations, the jitter window and the landing maths can never disagree with the
  config. The artwork still has five fields baked in — a comment says so.

## Deviation from the contract (one, deliberate)

**The tween goal.** The contract states
`spinGoal = current - (current % 360) + target + 360 * turns`. That reaches the
right angle, but its travel is `target - (current % 360) + 360 * turns`, and
with `turns == 1` — the ReduceFlashing path — `target` can be as low as -318
while `current % 360` is as high as 360, so travel goes negative and the disc
jerks backwards into its result. Shipped as

```lua
spinGoal = current + (target - current) % 360 + 360 * turns
```

which is congruent to `target` (identical landing degree, identical jitter,
identical determinism) and always at least one whole turn forward. Two suites of
100 landings each assert forward travel >= 360 in both modes; the contract's
expression fails the reduced-flashing one.

## Open questions for the owner

- Does the disc want clearance from the landscape topbar (item 3 above), or is
  "centred on the whole screen" worth the overlap?
- Should the short copy threshold move from 300 to ~380 so a phone reads
  `1 POTION` rather than a clipped `1 SPEED POTION`?
- The odds are printed inside every field at 0.36 R in gold. On the emulator row
  (side 266) they render at the 11 px floor. Acceptable, or should the odds drop
  out below some size rather than shrink to the floor?

---

## Follow-up (coordinator's two adjustments, same session)

**475 -> 520 checks**, LocalScript still compiles clean. 785 -> 804 lines.

### 1. The disc is sized and centred on `Safe`, not `Display`

`applyLayout` now takes `minAxis = min(safe width, safe height)` and centres the
holder on the `Safe` rect's centre. Same formula otherwise
(`min(clamp(floor(minAxis * 0.86), 220, 640), floor(minAxis))`). This closes
open question 3 and Studio item 3 of the original report: the pointer sits on
the disc's top edge, so with `Display` a landscape phone put it under the 58 px
topbar band.

Worked examples in the code comment and asserted by the suite:

| Display | Safe | Side |
|---|---|---|
| 1280x720 | 1280x662 | 569 |
| 390x844 | 390x786 | 335 |
| 844x390 | 720x332 | 285 |
| 1024x768 | 1024x710 | 610 |
| 705x338 | 705x280 | 240 |
| 749x368 | 749x310 (625 wide after the housing) | 266 |

Every test row now carries the 58 px topbar the contract's examples assume; a
desktop Studio window reports 36, which only makes the disc bigger, so 58 is the
conservative row. Two new per-row checks assert the disc's top and bottom edges
are inside `Safe`, which is the thing that was actually wrong before.

### 2. Field names can no longer overflow their field

`FieldLabel1..5` are `TextScaled = true` with a `UITextSizeConstraint` child:
`MinTextSize = 11` fixed, `MaxTextSize` written by `applyLayout` to the size it
already derived (`max(11, floor(side * 0.040))`). The fixed `TextSize` write is
gone — the engine ignores it on a scaled label, so leaving it would have been a
lie. `FieldOdds1..5` are unchanged: fixed size, still >= 11.

`SHORT_LABEL_SIDE` raised 300 -> 400, so every phone-sized disc (335, 285, 266,
240) prints `1 POTION` / `1 SHIELD` outright and only desktop (569) and tablet
(610) print `1 SPEED POTION` / `1 ENTITY SHIELD`. The constraint stops an
overflow; the threshold stops a name being *shrunk* to the 11 px floor to fit,
which is legible but not readable.

New checks: every field label is TextScaled with a constraint whose
`MinTextSize` is exactly 11 and whose `MaxTextSize` is >= 11 and >= the floor;
the ceiling tracks the diameter on a device rotation; the four phone rows print
the short names with the right ceiling and the desktop row prints the long ones;
the odds labels are not scaled and stay >= 11. The "no drawn string below 11 px"
sweep now reads a scaled label's floor from its constraint instead of from its
ignored `TextSize`.

Unchanged: the forward-travel tween goal, the hub staying Active while the disc
turns, the takeover, and everything else in the sections above.

### Open questions now

- The desktop/tablet long names (`2 SPEED POTIONS` at ceiling 22 on a 569 disc)
  are the only remaining TextBounds unknown, and the constraint makes the worst
  case "smaller than authored", not "clipped". Still worth one look in Studio.
- The pointer's alignment with the art's rim (Studio item 1) is untouched by
  this change and is still the one thing that can only be checked by eye.
