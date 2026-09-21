# A-HUD — Trello #101 Shield HUD -> EQUIPMENT panel (+ Speed Potion / Route Marker controls)

Baseline `aa40f70`. Nothing committed, nothing pushed to Studio, manifest untouched.

## Files touched (exact paths)

| Path | What |
|---|---|
| `G:\Roblox\MongoTV\StarterPlayer\StarterPlayerScripts\ProtectionHUD.LocalScript.lua` | rewritten: one shield chip -> a three-row EQUIPMENT panel in UIStyle, plus T/X actions, a transient caption, and three touch control slots. 289 -> 561 lines. |
| `G:\Roblox\MongoTV\ReplicatedStorage\UIDevice.ModuleScript.lua` | slot table only: two keys appended to `CONTROL_KEYS_RIGHT_FIRST`, two column slots derived from ProtectionUse's own bottom, one stale comment corrected. 36 lines, all inside `columnControlPlan` / that list. |
| `G:\Roblox\MongoTV\ReplicatedStorage\UIRegression.ModuleScript.lua` | the two control-key allow-lists only (`MOVEMENT_CONTROLS` ~line 414, `expectedControlKeys` ~line 3498). Another agent's edits to the terminal rows of the same file are present and untouched. |
| `G:\Roblox\MongoTV\tools\tests\test_equipment_hud.py` | new. `python tools/tests/test_equipment_hud.py` -> **303 checks passed**. |

## Decisions I made (not asked, stated here)

1. **The two touch slots are seated by `CONTROL_KEYS_RIGHT_FIRST`, not pinned above ProtectionUse.**
   The brief suggested `Bottom = ProtectionUse.Bottom + (Height + gap) * k`. That is what the
   *column* plan now does, but it cannot be the whole answer, and I measured why:
   - on a 812x375 and a 844x390 landscape phone the second column would need 432px of a
     375/390px screen — the third slot lands off the top of the display;
   - on a 568x320 phone the row arrangement puts the second stacked slot at y 50 inside a
     top band that runs to y 97 — straight through the objective readout.

   Listing them instead makes the module's own guarantees cover them: `planZone` reserves
   them, `rowControlPlan` shrinks the cell until **all nine** clear `MINIMUM_TOUCH_TARGET`,
   and the readout's headroom is measured against the result.
   **Consequence, and the one thing that needs a look in Studio:** the touch cluster reflows
   on some devices even for a player who owns nothing. Measured, from the real module:

   | Viewport | Before (7 keys) | After (9 keys) |
   |---|---|---|
   | 705x338 (Galaxy A06 landscape) | row, 1 rank of 7, cell 49 | row, 2 ranks of 5, **cell 56** |
   | 568x320 | row, 2 ranks of 4, cell 56 | row, 2 ranks of 5, cell 55 |
   | 812x375 | **column**, 64/58 | row, 2 ranks of 5, cell 56 |
   | 844x390 | **column**, 64/58 | row, 1 rank of 9, **cell 45** |
   | 1024x768 tablet | column | column (unchanged, stack fits) |
   | 375x812 portrait | column | column (unchanged, stack fits) |

   Every cell still clears the 44px floor, and four of the six get *bigger* targets. The one
   to eyeball is **844x390**: JUMP goes 64 -> 45px because `rowControlPlan` prefers fewer
   ranks over bigger cells (`for _, perRank in ipairs({count, math.ceil(count / 2)})`). If the
   owner dislikes it, the one-line knob is that candidate list — pick the largest cell that
   fits instead of the first. I did not change it: it is shipped behaviour unrelated to #101.

2. **Touch captions stay two lines.** The brief asked for `"SHIELD x2"`. A 45-58px slot at
   TextSize 10 with `TextWrapped = false` does not hold that on one line, and two lines is
   exactly what the shield ships today. So: `"SHIELD\nx2"`, `"POTION\nx1"`, `"MARKER\n1/3"`.

3. **The marker row stays pressable at 3/3.** Per the lead's note, RouteMarkerService retires
   the oldest marker rather than refusing, so a greyed-out row at the cap would be a lie.
   Only the readout changes.

4. **The marker row also shows while `stored == 0` but `placed > 0`** (brief said stored > 0
   only). That is the moment a player most wants to read "0 STORED · 3/3 PLACED"; it mirrors
   the potion's own "active / used" clause.

5. **`MaxActive` and `DurationSeconds` are read from `ZyntraConfig.Items`** with 3 / 6 as
   fallbacks, so the readout cannot print a cap the server does not use. ProtectionHUD now
   requires ZyntraConfig (ProtectionClient already did, so no new yield).

6. **Registration follows the form factor, visibility follows the inventory.** All three rows
   register a control rect on any touch device, exactly as the shield does today — which is
   what lets `UIRegression.expectedControlKeys` list them without a "missing key" the moment
   a player owns nothing. An undrawn control is excluded from `measuredControlUnion`, so the
   live `Zones.Controls` still describes what is on screen.

7. **Caption placement**: under the panel on pointer; inside `UIDevice.Layout().ModalArea` on
   touch (the module's own "an overlay that takes no input lives here" rectangle).

8. **No tween, no pulse anywhere.** Reduced-motion by construction.

## Exact strings

**Panel** eyebrow: `EQUIPMENT`.

**Row names (pointer, UIStyle.title 13):** `Entity Shield`, `Speed Potion`, `Route Markers`.
While a shield is live the shield row's name becomes `SAFE`, or `RETRY` when it is pressable
(that is the shipped logic, unchanged; `SAFE` prints in `UIStyle.Color.Live`).

**Readouts (pointer, UIStyle.readout / Code 12):**
- shield — `2 CHARGES` / `99+ CHARGES` / `WAIT` / `RETRY` / `4.2s`
- potion — `2 STORED` / `ACTIVE 4.2s` / `USED THIS ROUND`
- markers — `3 STORED · 1/3 PLACED` (U+00B7 middot, already used elsewhere in the repo)

**Keycap chips (UIStyle.Radius.Key, Code 11):** `[Q]`, `[T]`, `[X]`; the shield's becomes
`[D-PAD DOWN]` on a live gamepad, and every chip disappears when `UIDevice.Binding` returns ""
(any touchscreen, or a gamepad-only device).

**Touch captions (two lines, TextSize 10):** `SHIELD\nx2`, `SHIELD\nWAIT`, `SHIELD\nRETRY`,
`SAFE\n4.2s`, `RETRY\n4.2s`, `POTION\nx1`, `POTION\n4.2s`, `POTION\nUSED`, `MARKER\n1/3`.

**Spectate mirror (unchanged):** `SAFE\n4.2s`.

**Transient caption (2 s):** `NO MARKERS LEFT` (NoMarkers), `TOO SOON` (RateLimited),
`NOT WHILE HIDING` (Hiding), `NOT NOW` (NotInRound / NoCharacter / Unavailable), any other
reason uppercased and cut to 28 characters, and a `ZyntraProfileChanged` message verbatim when
its tone is `"error"` and the HUD is live.

## Verified offline, and how

`python tools/tests/test_equipment_hud.py` — 303 checks, real Luau 0.737, no Studio, no network.
It is two halves in one process:

**Half 1 — the control plan, from the REAL `UIDevice.ModuleScript.lua`** loaded against a fake
DataModel (five services, a camera, `Instance.new`, memoised `Enum`, `Vector2`/`Rect`/`UDim2`/
`Color3` with **no Color3 arithmetic**). For each of 705x338, 568x320, 812x375, 844x390,
1024x768 and 375x812 portrait it asks `UIDevice.Layout()` and asserts, against the module's own
`Safe`/`TopBand`/`Zones`, never against copied numbers:
- all nine slots exist and clear 44px in both axes;
- no two of the nine overlap (36 pairs per viewport);
- each equipment slot is behind the shield (above it or left of it), inside the safe area, and
  clear of `Zones.Thumbstick`, `Zones.Jump` and `TopBand`;
- on the portrait column, `SpeedPotionUse.Bottom == ProtectionUse.Bottom + cell + gap` and
  `RouteMarkerPlace` one step further, in the same column, at the same size;
- the slots are published on a pointer layout too.

**Half 2 — the WHOLE `ProtectionHUD.LocalScript.lua`** executed under that fake DataModel with
the **real UIStyle**, a fake ProtectionClient/ZyntraConfig, and remotes whose `FireServer` calls
are captured. `UIDevice` is a thin fake there, but its `Layout()` returns the layouts half 1
computed from the real module — so the slots the HUD positions buttons in are shipping
arithmetic. Asserted: chrome comes from UIStyle (panel radius/stroke, eyebrow colour, row name
colour and size, keycap radius and face); the 7-case visibility matrix over
`ZyntraSpeedPotions` / `ZyntraRouteMarkers` / `RouteMarkersActive` /
`ZyntraSpeedPotionUsedThisRound` / `ZyntraSpeedBoostUntil`, including panel height per visible
row count; every readout string; disabled states; the potion countdown falling 4.2 -> 3.2 ->
lapsed across `RenderStepped`; NaN/over-cap attributes clamped; T and X gating (processed input
ignored, held-key latch, 1.2 s and 1.5 s rate windows measured, nothing fired at 0 stock / used
/ active / no remote); seven shared gates (textbox, SelectedObject, modal, dead, escaped,
loading cover, briefing) each blocking all three actions; the shield's own RETRY/WAIT/99+/SAFE
path and that neither new key ever touches ProtectionClient; tap vs non-touch `Activated`;
every RouteMarkerService refusal string and the unknown-reason fallback; error-tone profile
pushes shown and success-tone ones not; three distinct non-overlapping touch rects at the plan's
own insets; panel inside the safe area at 1280x720, 1920x1080 and 956x382 with rows stacking
upward by row+gap; the spectate mirror (text, not pressable, no rows, no panel, no rects, no key
does anything, and a spectating touch client releases its rects); keycap suppression; keycap
width vs readout column; and the destroy path (rects released, RenderStepped disconnected, gui
destroyed, keys inert).

The test was mutation-checked in both halves: changing the column step to a value that overlaps
fails "tablet 1024x768: no two control slots overlap", and changing `USED THIS ROUND` fails
"a used potion says so".

All three `.lua` files pass `luau-compile.exe --binary`.

Existing suites that touch these files, run after the change: `test_controller_input` (120),
`test_ui_style` (83), `test_lobby_shop_display` (307), `test_dev_free_respawn_offer` (35),
`test_spectator_vitals` (14), `test_spectate_parity` (18) — all pass. Full sweep of
`tools/tests/`: the only failures are pre-existing or other agents' (`test_level3_run_in_exit`,
`test_level3_hidden_chase`, `test_level3_slide_aperture`, `test_pool_slide_navigation`,
`test_push_repo_to_studio` (its `luau --version` probe), `test_zyntra_store_compact`
(ZyntraStore, not mine), and `test_full_sync_contract` (the manifest has no entries for this
batch's edits yet, by design — the lead updates it)).

## NOT verified — needs Studio

- **Anything rendered.** Font metrics are the big one: the panel is 300px wide with a fixed
  96px name column and a `#text * 7 + 10` keycap; `3 STORED · 1/3 PLACED` at Code 12 is the
  longest readout and is expected to fit the ~134px left over, but only a real render says so.
  `TextTruncate.AtEnd` is set on both labels so an overflow degrades rather than overlaps.
- **The U+00B7 middot** rendering in Gotham/Code at 12px.
- **Real thumbstick geometry and the reflow above.** The zone arithmetic is the module's own,
  but 844x390 dropping JUMP to 45px, and 812x375 moving from column to row, should be looked at
  on a device or in the Device Emulator.
- **`UIRegression.Fit` matrices** — the queue-modal matrix now expects nine registered keys.
  Only a live run proves ProtectionHUD registers all three there.
- **Touch activation feel** (`.Activated` with `AutoButtonColor` on a 45-56px cell).
- **The `ModalArea` caption placement** on a short landscape phone.
- **Server side**: `UseSpeedPotion` and `("place")` are fired as contracted but nothing here
  proves the server answers.

## Open questions for the lead / owner

1. **The 844x390 reflow** above — accept, or flip `rowControlPlan`'s candidate list to prefer
   the biggest cell? (One line in UIDevice, but it changes the shipped cluster on other
   devices too, so I did not do it.)
2. **`ZyntraConfig.Items` does not exist yet** (A-SERVER owns it). The HUD falls back to
   MaxActive 3 / DurationSeconds 6. If A-SERVER names those fields differently, tell me.
3. **`RouteMarkersActive`** — I assume it is `nil`/absent until the server first publishes it,
   and read that as 0. Confirmed by the lead's note that it is published after each placement.
4. **Speed potion "active" is read from `ZyntraSpeedBoostUntil` only.** If A-SERVER also wants
   `ZyntraSpeedBoostMultiplier` reflected in the HUD, say so — I do not read it.
5. Should the EQUIPMENT panel stay visible in the **lobby** (it does not today: everything is
   gated on `contextAvailable()`, i.e. a live round)? The inventory is visible in the terminal,
   so I left the HUD round-only.

## Texture / artwork needs for Codex

**None.** The panel is type, rule and colour only, all from UIStyle. If the owner later wants
per-item glyphs, the row reserves nothing for them yet and I would need a 24x24 (48x48 @2x)
transparent PNG per item.

## Trello card text draft — #101

> **Shield HUD -> EQUIPMENT panel (done, pending Studio render check)**
>
> The lone shield chip is now an EQUIPMENT panel in the Objectives panel's own language —
> same shared `UIStyle` tokens the Level 1 objectives card uses, so nothing is restated:
> panel bg/stroke/corner, a SignalAccent bar, an "EQUIPMENT" eyebrow in Code 10, rows with
> the item name at GothamBold 13, a Code readout, and a keycap chip on the right.
>
> Each row states its name, what is left, and its key:
> * **Entity Shield — 2 CHARGES — [Q]** (D-PAD DOWN on a gamepad)
> * **Speed Potion — 2 STORED / ACTIVE 4.2s / USED THIS ROUND — [T]**
> * **Route Markers — 3 STORED · 1/3 PLACED — [X]**
>
> No clutter: the potion and marker rows only exist once you own one, so a player with
> nothing sees the single shield chip exactly as before, and the panel never grows past
> three rows. Nothing animates, so reduced-motion needs no special case.
>
> Mobile: no panel chrome — each row becomes its own >=44px control in the same reserved
> touch cluster as JUMP/RUN/SNEAK/FLASHLIGHT, seated by the same arithmetic, so the layout
> engine keeps all nine clear of the thumbstick, the jump button and the objective readout
> by construction rather than by hand-placed numbers. Captions are short (SHIELD x2,
> POTION x1, MARKER 1/3) and keyboard glyphs are dropped on touch.
>
> A refusal from the server ("NO MARKERS LEFT", "TOO SOON", "NOT WHILE HIDING") shows as a
> two-second line under the panel instead of failing silently.
>
> Every existing shield behaviour is untouched: the same owner module, the same
> retry/wait/pending states, the same Q binding, and the same read-only "SAFE 4.2s" mirror
> while spectating.
>
> Offline proof: `tools/tests/test_equipment_hud.py`, 303 checks — the whole LocalScript and
> the real layout module run under real Luau. Still to check in Studio: the rendered text
> fit, and the touch cluster reflow on 812x375 / 844x390 (details in
> `artifacts/trello-20260916/agent-hud-report.md`).
