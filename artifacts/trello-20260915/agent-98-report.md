# Agent A98 — Trello #98 "Unify in-game UI using Objectives and Mission Brief as the style reference"

Phase 1 (offline). No Studio tools were used; nothing was pushed, committed or published.
All claims below are either a file diff or a test run recorded in this document.

---

## 1. The reference, read off the two surfaces the owner named

| Role | Value | Where it is authored |
|---|---|---|
| HUD panel surface | `Color3.fromRGB(9, 13, 11)` @ `0.08` | `PuzzleUI` `objectivePanel` "Level1Objectives" |
| Full card surface | `Color3.fromRGB(8, 12, 10)` @ `0.035` | `RoundUI` `objectivesPanel` "ObjectivesPanel" |
| Caption band surface | `Color3.fromRGB(4, 8, 6)` @ `0.18` | `RoundUI` `subtitleFrame` "CommandSubtitles" |
| Control surface / hover | `Color3.fromRGB(14, 20, 17)` @ `0.04` / `(25, 34, 29)` | `objectivesToggle`, `objectivesButton` |
| Stroke | `Color3.fromRGB(75, 94, 83)`, `1px`, `0.28` (card `0.25`, soft `0.46`) | both panels + both controls |
| Corner radius | card `12`, panel `10`, control `9`, chip `8`, inner `7`, key `6` | as above |
| Eyebrow | `Code` `10` `Color3.fromRGB(101, 177, 139)` | `Eyebrow` in both panels |
| Readout / speaker | `Code` `13` `Color3.fromRGB(105, 238, 168)` | `subtitleSpeaker`, `DispatchMuteButton` |
| Title | `GothamBold` `16` (card `20`) `Color3.fromRGB(231, 238, 233)` | `objectiveTitle`, `objectivesTitle` |
| Body | `GothamMedium` `13` `Color3.fromRGB(201, 213, 205)` (muted `142,159,149`) | `makeLabel`, row `Description` |
| Caption copy | `GothamMedium` `20` `Color3.fromRGB(240, 242, 235)` | `subtitleText` |
| Accent | `Color3.fromRGB(83, 204, 145)` | `SignalAccent`, `ProgressTrack.Fill` |
| Warning family | bg `42,34,20` / line `139,111,58` / text `224,202,151` / badge `224,188,111` | the `!` threat row |
| Spacing | margin 18, padX 16, padTop 27, padBottom 9, row 21, gap 3 | `PuzzleUI.LAYOUT` |

The reference carries **no red at all**. Danger is Level 2's existing pair
(`255,116,96` line / `255,138,120` text), now stated once so the three levels stop
each inventing their own.

## 2. Audit — every in-game UI surface

Verdicts: **C** consistent, **I** inconsistent (fixed this pass unless noted),
**D** deliberately different (kept, with the reason).

| Script | Surface | Before | Verdict |
|---|---|---|---|
| `PuzzleUI` | `Level1Objectives`, toggle, detector | *the reference* | C (frozen, A82) |
| `RoundUI` | `ObjectivesPanel`, `ObjectivesButton`, `CommandSubtitles` | *the reference* | C (frozen, lead) |
| `RoundUI` | `PartyDownCard` | radius 10, stroke `255,82,72` 1.5 @.2, GothamBlack | **D** — red is the danger accent; card chrome already matches. Patch 4.1 for thickness only |
| `RoundUI` | `LevelLoading`, round-ending banner | own greens `115,255,170` / `105,255,165` | **I** — patch 4.1 |
| `Level 2 Objective UI` | `Level2ObjectivePanel` + 3 rows | radius **6**, stroke cyan **2px** @.35, bg `6,13,15` @.16 | **I** → fixed |
| `Level 3 Reader Client` | `ReaderPanel`, `Chip`, `AlertToast`, `DirectionTrack` | radius 6/7/7, strokes **2px**/1.5, bg `6,13,15` @.12 | **I** → fixed. Stroke *colour* is the calibration gauge: **D**, kept |
| `Level2AlertClient` | `Level2AlertGui` toast | **no UICorner at all**, stroke cyan **3px**, no transparency | **I** → fixed (the single worst offender) |
| `SpectateController` | caption band, `‹ ›` arrows, `SpectateBackToLobby`, `SpectatorCounter` | pure black @.4/.45, **no stroke**, `Gotham`, radius 6, teal `73,245,204`, blue `190,225,255` | **I** → fixed |
| `Round Exit Client` | `LeaveChip`, `RoundExitCard`, buttons | own teal accent, radius 6/10, strokes 1.2/1.5 | **I** → fixed (visual only; card 74 behaviour untouched) |
| `ProtectionHUD` | `ProtectionUse` | radius 8 ✓, stroke `70,115,91` **with no transparency** | **I** (mild) → fixed |
| `Level 2 Pool Foam Client` | `Caption` | bg `5,13,16` @.3, radius 7, **no stroke** | **I** → fixed |
| `First Entry Guide` | `FirstEntryMarker` billboard | **bare floating text**, no panel | **I** → fixed. Zyntra cyan kept: **D**, it labels a cyan beam in the lobby |
| `JumpscareUI` | `JumpscareGui` → one full-screen `Black` frame | no text, no panel, no chrome | **D** — deliberately raw; nothing to style. **Not touched** |
| `Level 3 Lighting Controller`, `Level 1/2/3 Sound Controller` | — | **draw no UI at all** | n/a — verified, not touched |
| `NoiseReporter` | `StaminaGui` bar + touch buttons | pill radius, stroke `220,228,218` 1.5 @.48, bg `8,10,9` @.52 | **I** — not mine, patch 4.2 |
| `Level 3 Table Hiding Client` | `HiddenStatus`, `LeaveHiding` | radius 8/10, strokes `79,183,157` 1.5 @.2 and `101,224,187` **2px @.05** | **I** — frozen (A80), patch 4.3 |
| `ZyntraStore` | terminal, HUD open button | own coherent palette: line `65,92,98`, text `232,240,238`, radius 7/8/12 | **D/C** — a self-consistent terminal family already ~95% aligned. Patch 4.4 |
| `Shop Display Client` (new, A88) | `ShopDetailCard` | reuses ZyntraStore's `COLORS` | C with the terminal family |
| `DevCheats` | `DevPlayerESP`, `MasterTuningPanel` | developer-only | **D** — out of scope, deliberately utilitarian |

**A rendering fault found while doing this, worth its own line.** `UIStroke.ApplyStrokeMode`
defaults to `Contextual`, and on a `TextLabel`/`TextButton` that means *outline the text*,
not draw a border. Consequences in the shipped build:

- `Level3ReaderGui.ReaderPanel` is a `TextButton` with `Text = ""` (deliberately — the whole
  rectangle is the tap target). Its "2px energon border", **including the signal-strength
  colour ramp `updateReader` writes every tick, has never been drawn by the engine.**
- `ProtectionUse` and Round Exit's buttons were getting *outlined glyphs* where a border was
  intended.
- The same is true of `RoundUI`'s `ObjectivesButton` (`Text = ""` + `roundAndStroke`) — see
  patch 4.1.

`UIStyle.panel` now states `ApplyStrokeMode = Border` explicitly. This is the one change in
this pass that makes something newly *visible*, so it is called out for phase 2 rather than
buried. One-line revert if the owner dislikes it: delete that line from `UIStyle.panel`.

## 3. What was implemented

### New: `ReplicatedStorage/UIStyle.ModuleScript.lua` (10,555 canonical bytes)

Tokens `Color` / `Radius` / `Stroke` / `Transparency` / `Font` / `TextSize` / `Pad`, each with a
comment naming the reference element it was read from, plus six helpers:
`panel`, `button`, `hover`, `title`, `body`, `readout`, `caption`.

They **only set properties** and adopt (never duplicate) an existing `UICorner`/`UIStroke` —
they never write `Position`, `Size`, `Name`, `Visible`, `Text` or `Parent` on the target, which
is exactly what `UIRegression`'s fit matrix measures. A `pick()` helper is used instead of `or`
so a legitimate `0` (`Transparency = 0`, `Radius = 0`) is not silently replaced by the default.
`TextSize` is skipped when the label is `TextScaled`, so every measured scale contract survives.

### Changed (chrome, faces and the state palette only — no layout, copy or behaviour)

| File | What |
|---|---|
| `Level 2 Objective UI` | `UIStyle.panel(panel)`; title/meter/hint via `UIStyle.readout`; state colours → `Positive`/`Accent`/`Warning`/`Danger`/`Line`. Cyan `126,224,235` identity kept |
| `Level 3 Reader Client` | `PANEL`/`TEXT`/`MUTED`/`AMBER` now come from the tokens; panel, restore chip and toast take `UIStyle.panel`; toast title/body → `title`/`body`; direction track is a pill. `ENERGON` and the stroke ramp kept |
| `Level2AlertClient` | `ALERT_PANEL` table applied at build **and** in `presentAlert` (one set of numbers, not two); first/run → `readout`; line 2 and the run line → `Warning` |
| `SpectateController` | caption band and counter get the subtitle surface + a real border; `‹ ›` and `SpectateBackToLobby` → `UIStyle.button`. `AutoButtonColor` kept and **no hover added** on the touch affordance so the two cannot fight for the background |
| `Round Exit Client` | `makeButton` is now three lines + `UIStyle.button`; card → `UIStyle.panel` at card tokens; title/body/notice → `title`/`body`/`readout`; `STAY` one step quieter than `BACK TO LOBBY`. Local `corner()` helper deleted (dead) |
| `ProtectionHUD` | one `UIStyle.button` call; gains the reference stroke transparency |
| `Level 2 Pool Foam Client` | `UIStyle.caption` with the neutral line (not the live green — this is a hostile cue, not Command) |
| `First Entry Guide` | the `Title` label gains the card surface, a cyan border and padding; beam, placement and every ending condition untouched |
| `tools/tests/test_first_entry_guide.py` | harness gains `UDim`, `Enum.ApplyStrokeMode`, `FindFirstChildOfClass` and loads the **real** `UIStyle` rather than a stub |

Not touched, as required: `RoundUI`, `ZyntraStore`, `PuzzleUI`, `TunnelLobbyBuilder`,
`Level 3 Table Hiding Client`, `DevCheats`, every server script, `studio-sync-manifest.json`.
`UIRegression` needed no edit — every instance `Name` is unchanged and no caption was added or
removed, so `Fit.ZyntraDisabledCaptions` and the fit matrix are untouched.

## 4. Patch lists for the frozen files

### 4.1 `RoundUI.LocalScript.lua` (lead)

RoundUI **cannot take a new top-level local** (200-register limit), so every patch below either
edits an existing literal or puts the `require` inside the existing `do ... end` block.

| Anchor | Old → New | Reason |
|---|---|---|
| `roundAndStroke(objectivesButton, 9, …)` and `roundAndStroke(objectivesPanel, 12, …)` | add `stroke.ApplyStrokeMode = Enum.ApplyStrokeMode.Border` inside `roundAndStroke` (line ~1878) | `objectivesButton.Text == ""`, so its authored border is currently **not drawn at all** |
| `pd.cardStroke.Thickness = 1.5` (~4501) | `1.5` → `1` | only weight differs from the reference; the red stays |
| `queueCloseStroke.Color = Color3.fromRGB(255, 125, 125)` (~511) | → `Color3.fromRGB(255, 138, 120)` | the one danger-text value |
| `endFlash`/`endLine` `Color3.fromRGB(105, 255, 165)` (~1036, ~1047) | → `Color3.fromRGB(83, 204, 145)` | the accent token |
| `Color3.fromRGB(115, 255, 170)` win colour (~852, 1060, 1593, 1661-1669) | → `Color3.fromRGB(127, 218, 166)` | the positive token |
| `Color3.fromRGB(255, 82, 72)` lose colour (~1675) | → `Color3.fromRGB(255, 116, 96)` | the danger token |
| `corner(…, 6)` on `queueCorner`'s siblings (~404, ~2092, ~2268) | 6 → 7 (inner) | the reference's inner radius |
| optional | inside the existing `do … end`, `local UIStyle = require(RS:WaitForChild("UIStyle"))` and route `roundAndStroke` through `UIStyle.panel` | one definition instead of six call sites |

### 4.2 `NoiseReporter.LocalScript.lua` (`StaminaGui`, unowned tonight)

`makeTouchButton` (~407): `BackgroundColor3 (8,10,9) @0.52` → `UIStyle.Color.Control @ 0.04`;
`stroke.Color (220,228,218) @0.48 ×1.5` → `UIStyle.Color.Line @ 0.28 ×1`, plus
`ApplyStrokeMode = Border` (these buttons carry text, so the stroke is currently outlining it).
Keep the pill `UDim.new(1, 0)` and every size. `staBg` (~679) `Color3.new(0,0,0)` →
`UIStyle.Color.Caption`; `bgc` radius 5 → `UDim.new(1, 0)` to match the reference's
`ProgressTrack`. Do **not** touch `STA_FULL`/drain colours — they are the stamina signal.

### 4.3 `Level 3 Table Hiding Client.LocalScript.lua` (A80)

`message` (~262): bg `(8,10,11) @.24` → `UIStyle.Color.Caption @ 0.18`; `messageStroke`
`(79,183,157) @.2 ×1.5` → `UIStyle.Color.Line @ 0.28 ×1` + `ApplyStrokeMode = Border` (it is a
`TextLabel`, so the stroke currently outlines "HIDDEN UNDER TABLE").
`leave` (~284): bg `(17,22,23) @.08` → `UIStyle.Color.Control @ 0.04`; radius 10 → 9;
`leaveStroke` `(101,224,187) @.05 ×2` → `UIStyle.Color.Line @ 0.28 ×1` + `Border`;
`TextColor3 (236,248,243)` → `UIStyle.Color.Title`. Sizes and the re-captioning stay.

### 4.4 `ZyntraStore.LocalScript.lua` (A88 + lead)

Smallest list of the four — this palette is already close.
`COLORS.line (65,92,98)` → `(75, 94, 83)`; `COLORS.text (232,240,238)` → `(231, 238, 233)`;
`outline()` default `transparency or 0` → `transparency or 0.28`, and add
`object.ApplyStrokeMode = Enum.ApplyStrokeMode.Border`;
`label()` default `font or Enum.Font.Gotham` → `Enum.Font.GothamMedium`;
`corner()` default `radius or 8` → `9` for controls (the button helper already passes 7 for
inner chips, which is the reference's inner radius). Leave `accent`, `accent2` and `error` —
they are the Zyntra brand and the store's own state colours. `Shop Display Client` inherits all
of this for free.

## 5. Tests and results

New: `tools/tests/test_ui_style.py` — loads the **real** `UIStyle` under Luau, asserts the
tokens against the values read off the reference, asserts each helper writes *exactly* its
documented property set (a helper that started writing `Position`/`Size` fails), asserts
`pick()` survives a `0`, asserts a second call adopts rather than adding a second
`UICorner`/`UIStroke`, asserts `ApplyStrokeMode = Border` including on a `Text = ""`
`TextButton`, then runs two **marker-extracted production blocks** — Level 2 Objective UI's
panel + three rows, and Round Exit Client's `makeButton` + confirm card — and checks both build
with the new tokens *and* keep their authored geometry (`title.Position.OX == 10`,
`card.Size.OX == 340`, `TextScaled` intact, `Name`/`Text` intact).

```
LUAU_BIN=C:\Users\mikke\AppData\Local\Temp\codex-luau-0.737\luau.exe

tools/tests/test_ui_style.py          83 checks passed          (new)
tools/tests/test_first_entry_guide.py 39 checks passed          (updated harness)
tools/tests/test_controller_input.py  120 checks passed
tools/tests/test_pool_foam_audio.py   24 checks passed
tools/tests/test_spectate_parity.py   18 checks passed
```

Mutation-checked: setting `UIStyle.Radius.Panel` to 6 fails `test_ui_style.py` with
`panel radius: expected 10, got 6`; reverted and re-run green. A test that cannot fail proves
nothing, so this was verified rather than assumed.

`luau-compile --binary` is clean on every changed file and on `UIStyle` itself. Native Studio
compile has **not** been run (phase 1 has no Studio).

## 6. Deployment order — this matters

`UIStyle` is a **new** ModuleScript, and per CLAUDE.md the sync tools cannot push new scripts.
Eight client LocalScripts now open with `require(ReplicatedStorage:WaitForChild("UIStyle"))`.

> **Create `ReplicatedStorage.UIStyle` in Studio BEFORE pushing any of the eight.** If the eight
> land first, every one of them yields forever at `WaitForChild` and the entire in-round HUD —
> objectives, reader, alerts, spectate band, exit chip, shield — simply does not appear.

Manifest item, once it exists in Studio:

```json
{
  "studioPath": "ReplicatedStorage.UIStyle",
  "className": "ModuleScript",
  "file": "ReplicatedStorage/UIStyle.ModuleScript.lua",
  "bytes": 10555,
  "sha256": "0b165e8a3819b6f14bc7c785b1f8af2ba4d5bd3a433bba48c0d952ed65ecf08a",
  "status": "synced"
}
```

(`bytes`/`sha256` from `tools/studio_source_contract.py` `canonical_bytes`/`sha256_of` — recompute
if the file changes.)

## 7. Phase-2 capture plan

Desktop (pointer) and a phone layout for each. Phone via `UIRegression`'s device emulation /
`UIDevice` forced viewport — the `Fit` matrix already drives 375×667 and 705×338, and both
tiers matter because the touch branches are separate code paths.

| # | Scene | How to reach it | Look for |
|---|---|---|---|
| 1 | Level 1 HUD with objectives open | playtest recipe → Level 1 round, `H` / objectives toggle | the reference itself — the baseline every other capture is compared against |
| 2 | Mission Brief card | `ObjectivesButton` in the lobby/round | baseline; confirm patch 4.1's `ApplyStrokeMode` if applied |
| 3 | Level 2 objective panel, 3 states | pumps 0/3, then `Level2FoamLethal`, then `Level2ExitPowered` | radius 10 + 1px neutral line idle; red on lethal; green on powered |
| 4 | Level 2 completion toast | `Level 2 Alert Event` | **rounded** now, 1px — this was square with a 3px border |
| 5 | Level 3 reader + alert toast | Level 3 round; `Level3DevSkipToPreBlackout` for the toast | **the border that was never drawn.** Confirm the signal ramp is now visible and not garish |
| 6 | Spectate band | die in a round with a living teammate | caption + arrows + BACK TO LOBBY now one family; check the band still fits at 705×338 |
| 7 | Exit chip + confirm card | alive in a round, top-left chip → confirm | neutral chrome; STAY reads quieter than BACK TO LOBBY |
| 8 | Shield HUD | Level 1 capture with a charge | border instead of outlined text |
| 9 | Pool Foam caption | Level 2 sighting | bordered caption band |
| 10 | First-entry billboard | fresh profile in the lobby | card behind the text, cyan border, beam unchanged |
| 11 | Jumpscare frame | Level 1 kill | **unchanged** — confirm it is still raw |
| 12 | Lobby terminal | Zyntra terminal, SHOP + SETTINGS tabs | unchanged this pass; baseline for patch 4.4 |

Run the `UIRegression` fit matrix after the push, before the captures — it is the only thing
that measures whether a stroke or radius change moved a rectangle.

## 8. Limitations — stated, not papered over

- **Nothing has been seen.** Offline Luau has no font metrics, no `TextBounds`, no rendering.
  Every claim here about how something *looks* is an inference from property values.
- **`ApplyStrokeMode = Border` makes borders appear that the engine was not drawing.** Biggest
  single visual delta in this pass and the one most likely to need an owner opinion.
  Revert is one line.
- **Level 3's reader stroke ramp becomes visible for the first time.** Its three colours
  (`66,244,218` / `75,122,116` / `89,170,159`) were chosen by someone who could not see them.
  They may want retuning once they render.
- **Deliberate neutralisations to confirm with the owner:** the teal `73,245,204` on Round
  Exit / spectate BACK TO LOBBY, and the cyan on Level 2's and Level 3's panel strokes, are now
  the neutral line. That is the point of the card, but it is a taste call — it is listed here
  so it can be vetoed cheaply rather than discovered in a capture.
- **Four files are frozen** (§4). Their patch lists are written from a read of the current
  source; the owning agent should re-read before applying, since they are being edited tonight.
- **No native Studio compile, no runtime, no desktop/touch capture.** Phase 2.
- Copy, layout, sizes, instance names, accessibility rules (`ReduceFlashing` and friends) and
  card 74's behaviour were not touched anywhere.
