# B3 design brief · body state: stamina C, marker C, grace, chase edge · 2026-10-08

The implementation brief for batch B3 (BUILD-PLAN §4 B3). It is split by owned file, so four agents can work in
parallel without two of them editing the same file.

Written read-only at about 23:40 on 2026-10-08 while B2 was still landing in the same tree. At that moment B2's
markers were already in NoiseReporter (`-- == B2 touch cells`), ProtectionHUD (`-- == B2 touch kit`) and
`test_controller_input.py` (`b2_program`), but B2 had not handed over. **Find code by function names and markers,
never by line number.**

Sources:
- `BUILD-PLAN.md`: §1.3, §1.4, §1.5, §1.6, §2 (02, 03, 10), §4 B3, §5, and the Framewisp adaptation.
- `FRAMEWISP-PIPELINE.md`: §1.6, §2.0, §2.7, §2.8, §5.
- `OWNER-PICKS.md`; `b2/B2-DESIGN.md` (D4, D11, C3, C6, C9).
- The approved frames `pc-level-3.png` and `phone-level-1.png` / `phone-level-3.png`, with their notes. Pixels sampled.
- The real dumps `tools/tests/fixtures/hud/framewisp-dump.HUD_PC.json` and `.HUD_Touch.json`.
- The four reader maps (stamina-noise, chase-grace, templates, roundui-limits).

---

## 0. Gate, agents, order

| Agent | Owns (the only files it edits) |
|---|---|
| **A · RoundHud** | `ReplicatedStorage/RoundHud.ModuleScript.lua`; `tools/tests/test_round_hud.py` |
| **B · NoiseReporter** | `StarterPlayer/StarterPlayerScripts/NoiseReporter.LocalScript.lua`; `tools/tests/test_controller_input.py`; `tools/tests/test_speed_potion.py`; `tools/playtest_ui_pit_regressions.py` |
| **C · ProtectionHUD** | `StarterPlayer/StarterPlayerScripts/ProtectionHUD.LocalScript.lua`; `tools/tests/test_equipment_hud.py` |
| **D · Round HUD (new)** | **new** `StarterPlayer/StarterPlayerScripts/Round HUD.LocalScript.lua`; **new** `tools/tests/test_round_hud_local.py` |

**Read-only for every B3 agent:** `tools/tests/hud_harness.luau`, the fixtures, `artifacts/.../install/*`, ShopBinder,
UIStyle, UIDevice, UIRegression, RoundUI, SpectateController, `Level 4 Round Client` (reels work in flight),
`Level 2 Pool Foam Client`. A test that needs more of the harness adds it in its own program after `context()`,
the way `test_equipment_hud`'s `hudContext` does; it never edits the harness.

**Gate.**
- **B and C wait for B2's handover.** B2's agent B owns NoiseReporter and `test_controller_input.py`, and B2's
  agent C owns ProtectionHUD and `test_equipment_hud.py`, until B2 hands over. B3 merges onto B2's tree.
- **A can land at once.** Its two Mount changes touch no node in any B1 or B2 template (no `*Fill` there; `opts.Touch`
  defaults to off). After landing it re-runs `test_round_hud`, `test_equipment_hud`, `test_flashlight_player_control`
  and `test_controller_input` (B2's program uses the real RoundHud).
- **D can start now.** It creates new files only.

**Order.** A lands first (B's stamina test needs its Fill fix). B, C and D in parallel. D's one cross-file check
(§6 test 12) goes green once B is in. Then one Studio pass (§7).

---

## 1. Decisions (these settle the contradictions)

| # | Question | Decision | Why |
|---|---|---|---|
| D1 | Chase-edge depth | **The approved frames**: side bands `0.146` of the width, top and bottom bands `0.185` of the height, as pure Scale sizes. Not BUILD-PLAN 02's "12 % of the shorter side". | `pc-level-3-annotations`: "side bands 280 wide, top and bottom bands 200 tall". `phone-level-3-notes`: "Sides 123, top and bottom 72 (PC 280/200 scaled to 844x390)". 280/1920 = 123/844 = 0.146; 200/1080 = 72/390 = 0.185. Pure Scale means no resize code. |
| D2 | Edge look | One Coral Frame per side with a UIGradient `Transparency` 0 → 1 (screen edge → inward). `BackgroundTransparency` 0.8 on, 1 off, tweened 0.18 s in and 0.4 s out. The corners overlap and come out darker (about 0.64); that is accepted. `ReduceFlashing` is never read. | A RF tile: "Static at 80 % transparency". Ramps, not flashes. |
| D3 | Edge gate | Base gate (§2.3) + `BeingChased == true` + `workspace.SelectedLevel ~= 2`. There is no Level 4 clause: nothing writes the flag there, so Q7's default holds by absence. Level 3 uses the plain flag. | OWNER-PICKS: no edge on Level 2. Test `== true`: Level 1 writes nil, Levels 2 and 3 write false. |
| D4 | Marker colours | Only the **Dot** changes: RailTeal, or Amber for LOUD. `Label` keeps the template's Sage. | Element tile 03 C and the frames. "(RailTeal) / (Amber)" in the plan means the dot. |
| D5 | LOUD while standing still | LOUD = `MoveNoise == "sprint"` **and** horizontal root speed > 2, the drain's own threshold. Round HUD applies the speed gate; `MoveNoise` stays the raw state. | Shift, L2 or the touch RUN toggle make `state` "sprint" with no movement, and nothing hears that. |
| D6 | Where `MoveNoise` is written | Once, compare-first, in `applySpeed`'s round branch, right after the `if crouching … else … end` chain. Not in the lobby branch. | That line also covers the hiding and slide early return. Round HUD is gated on InRound, and every InRound change re-runs `applySpeed`. |
| D7 | Grace | The marker's GRACE state, only for `PlayerProtectionSource == "Reentry"`. Attention key `"GRACE"` (never the seconds); the text is updated separately. It rests at 45 % after 6 s like the other states. A shield stays on the chip only. | The B3 QA expects "· 10 s". A key that carried the seconds would re-wake the pill every tick. |
| D8 | PC vertical stack | Stamina root bottom at `Safe.Bottom − 24`, the edge of B1's chip and flashlight row. The marker sits **4 px above the stamina root**, so its bottom is at `Safe.Bottom − 54`. | The plan says −24, and B1 built its row at −24. The frame's 4 px gap (marker 984..1008, bar root 1012..1038, sampled) keeps the marker clear of the WINDED band in the bar root's upper 18 px. The plan's "marker bottom at −40" would sit on WINDED. |
| D9 | Stamina on touch | **Shown**, as the approved phone frames draw it: `HUD_PC/StaminaBar` at Scale 0.5 (160 x 13, a 3 px track), centred in `Layout().Corridor`, root bottom at `Safe.Bottom − 4`. Hidden when the corridor is narrower than 168 px; then the RUN ring is all there is. This **supersedes** BUILD-PLAN 10 / §1.5 / the B3 QA line "the stamina bar is hidden". | Sampled: `phone-level-1` and `-3` draw the track at x 350..510, y 362..364. After B2's C6, the RUN ring is Amber whenever the toggle is on, so it can no longer show LOW. The bar also gives a touch spectator the watched stamina (B2's D11 hides the cluster). Owner TOUCH QA item. |
| D10 | WINDED at Scale 0.5 | Floored at 12 px through a new `Mount` option, `opts.Touch` (A). | Pipeline §2.0 rule 8. At 0.5 the template's 14 px would be 7 px. |
| D11 | GRACE on a phone | When the full-copy pill is wider than the corridor (844x390: 230 vs 191), the touch label reads `INVISIBLE \u{B7} N s` (144 px). Tablets and PC keep `INVISIBLE TO MONSTERS \u{B7} N s`. | Centred, the full pill reaches the LIGHT cell at x 553. A Scale below 1 would break the 12 px floor. Owner TOUCH QA small call. |
| D12 | Hugging the pill | `Soft` is anchored left at `(0, 0.5)`, width `W = 20 + n × CHAR_W + 8`, where n is `utf8.len(text)` and `CHAR_W = Label.FigmaTextW / utf8.len(Label.FW_Text0)` (195 / 27 = 7.22; Roboto Mono is monospaced). The root's left is `centre − W/2`. No `TextBounds`. | The pipeline lets the code resize `Soft`, never the root. TextBounds settles a deferred frame after `scaleText` refits, and the monospace width is exact. |
| D13 | The Framewisp Fill anchor | Fixed **once, in `RoundHud.Mount`**: every node whose base name ends in `Fill` is re-anchored to `(0, y)` with its left edge kept. | All 11 Fill nodes across the three bundles are centre-anchored (StaminaBar, ObjectiveCard, ObjectivePill, HoldFill, PromptPlateTouch, PartyDownFill x2, LoadingCard x2, TableCheck x2). B4, B6, B7 and B8 would each hit the same trap. |
| D14 | Stamina attention | Mount with `Attention = {Hold = 0, Rest = 0.55}`. DRAIN and WINDED: `Show("bar", true)`. RECOVER: `Show("bar")`. FULL, dead, escaped, lobby, no room: `Hide()`. Calls are made only when the mode changes. "Draining" means drained within the last 0.5 s. | BUILD-PLAN 1.3: 100 % while draining, 55 % recovering, hidden when full, WINDED never dims. The 0.5 s window stops a shimmer when the speed hovers at 2 studs/s. `test_round_hud` already proves "no longer urgent, hold over: rests at once". |
| D15 | Spectating | No marker and no edge. The bar shows the watched `SpectateStamina`, lifted 92 px (today's lift over SpectateGui's caption), on touch too. It is never WINDED, because only the fraction replicates. Its trend comes from value changes: a decrease drains, an increase recovers, and an unchanged value keeps the last trend. | The remote reports at 4 Hz. A per-frame "is it draining" test would flip DRAIN/RECOVER at 4 Hz. |
| D16 | Previews | The Level 6 playground (`Level6InRound`) and the new-map Level 2 preview (`Level2NewMapPreview`) draw nothing: the gate is `InRound`. | Developer-only. No plan text covers them. |
| D17 | RoundHud API | No `Paint`, `Stack` or `Ring` in B3. Round HUD keeps its own marker handle and is the first caller of `RoundHud.Clear()` (on InRound true → false). | Pipeline §5.2. Clear still only tears down the detector, which is right at round end. |
| D18 | UIRegression | No change in B3. | No gui is retired or renamed (`StaminaGui` stays). `ReentryGrace` was never listed. |

Owner TOUCH QA list (with B2's D7, D9-D12): D9, D11, D5 (no LOUD standing still), D16, and Level 4 drawing HIDDEN
twice until B4 (§9).

---

## 2. Shared contract (all agents)

### 2.1 Attributes

| Name | On | Written by | Values | Read by |
|---|---|---|---|---|
| `MoveNoise` | LocalPlayer, client-local | NoiseReporter `applySpeed`, round branch only, compare-first | `"walk"` / `"sprint"` / `"crouch"` | Round HUD |
| `BeingChased` | Player, server | EntityAI (true/nil), Pool Foam (true/false), Mall Manager (true/false) | `== true` only | Round HUD (edge), NoiseReporter (adrenaline, unchanged), EntityShakeController |
| `Level3_Hiding`, `Level4_Hidden` | Player, server | Level 3 Hiding Controller; Level 4 Objective Controller (true/nil) | `== true` only | Round HUD (HIDDEN) |
| `PlayerProtectionActive` / `ExpiresAt` / `Source` | Player, server | `PlayerProtection` (`"Reentry"` 10 s, `"Shield"` 5 s; `ExpiresAt` can jump on renewal) | as ProtectionHUD `secondsRemaining` reads them | Round HUD (GRACE), ProtectionHUD (chip) |
| `SpectateStamina` | the watched Player, server | GameManager `receiveSpectatorVital` | 0..1 | NoiseReporter (spectating bar) |

### 2.2 Geometry (one source per number, pinned by tests on both sides)

| Constant | Owner | Value |
|---|---|---|
| `BAR_BOTTOM`, `BAR_BOTTOM_TOUCH`, `BAR_TOUCH_SCALE`, `SPECTATE_LIFT` | NoiseReporter | 24, 4, 0.5, 92 (StaminaBar root bottom above `Safe.Bottom`; root height 26 × scale) |
| `MARKER_BOTTOM`, `MARKER_BOTTOM_TOUCH` | Round HUD | 54 (= 24 + 26 + 4) and 22 (= 4 + 13 + 5, the phone frame's marker at y 323..347) |
| Marker root | template | 240 x 24 at Scale 1 on PC and touch. `Dot` x 8..14, `Label` left edge at x 20 |
| Edge bands | Round HUD | Scale 0.146 (left, right) and 0.185 (top, bottom) |

The marker's top on PC is therefore `Safe.Bottom − 78`. B5 places captions above that.

### 2.3 The base gate (marker and edge)

`InRound == true`, the character's Humanoid `Health > 0`, `Spectating ~= true`, `Escaped ~= true`, and
`workspace.RoundActive == true`. The loading cover (RoundUI 100, opaque black since B0) hides orders 10 and 20
without a clause. PARTY DOWN needs no clause, because nobody is alive then.

### 2.4 States, tokens and Attention numbers (tokens are `ShopBinder.Palette` names)

| Element | State | Look | Attention |
|---|---|---|---|
| Marker (03 C) | GRACE | Dot RailTeal, Label `INVISIBLE TO MONSTERS \u{B7} 10 s` (touch, narrow: `INVISIBLE \u{B7} 10 s`), Sage | `Show("GRACE")`: 100 % for 6 s, rest 45 % |
| | HIDDEN | Dot RailTeal, `HIDDEN` | `Show("HIDDEN")`: 6 s, 45 % |
| | LOUD | Dot **Amber**, `LOUD` | `Show("LOUD", false, 0.6)`: 6 s, 60 % |
| | SNEAKING | Dot RailTeal, `SNEAKING` | `Show("SNEAKING")`: 6 s, 45 % |
| | walk / gate false | — | `Hide()` |
| Stamina (10 C) | DRAIN | Fill Cream (Amber at ≤ 25 %), `Winded` hidden | `Show("bar", true)`: 100 % |
| | WINDED (`exhausted`) | Fill **Coral**, `Winded` shown | `Show("bar", true)`: never dims until `STAMINA_RECOVER` |
| | RECOVER | Cream, or Amber at ≤ 25 % | `Show("bar")`: 55 % at once |
| | FULL (≥ 0.999) / off | — | `Hide()` |
| Edge (02 A RF) | on / off | Coral bands, 0.8 / 1 | not Attention; tween 0.18 s in / 0.4 s out |

Priority: GRACE > HIDDEN > LOUD > SNEAKING > nothing. Every level shows the marker, **Level 2 included**. The word
carries the state; there is no pulse anywhere. `ADRENALINE` is never drawn (adrenaline stays a stamina mechanic).

### 2.5 Rules for every B3 file

1. **ASCII-only source.** Write `·` as `\u{B7}`. Each file wraps its B3 code in the markers named below; its test
   asserts the marked section is ASCII.
2. **No waits on templates.** After `if not game:IsLoaded() then game.Loaded:Wait() end`, find `RoundHud`,
   `ZyntraShopUI.ShopBinder` and the bundles with `FindFirstChild` (B2 critic C3). NoiseReporter's last line,
   `RoundEntryControlsReady`, must never wait on B3.
3. **A missing template** is RoundHud's warning by path, and that element is not drawn. No `Instance.new`
   fallback. The edge is code-drawn and works without templates.
4. **Attention owns each CanvasGroup's `Visible`.** Gate with `Show` / `Hide`; never write `Visible` on a mounted
   root.
5. **Code writes only:** Dot `BackgroundColor3`, Label `Text`, Fill `Size.X` and `BackgroundColor3`, `Winded.Visible`,
   `Soft` hugging, and root placement. The single geometry exception is A's Fill re-anchor at mount.
6. Tag every B3 comment `HUD_B3`.

---

## 3. Agent A · RoundHud (`ReplicatedStorage/RoundHud.ModuleScript.lua`)

Two changes inside `RoundHud.Mount`, plus the header's API text. Nothing else in the module moves.

**3.1 Re-anchor every Fill (D13).** In Mount's descendant loop, after the `Soft` branch:
```lua
elseif string.sub(Binder.base(node.Name), -4) == "Fill" and node:IsA("GuiObject") then
	-- HUD_B3: Framewisp centre-anchors every node, so a width write would grow a Fill both ways.
	-- Anchor it on the left edge it already starts at; the code owns its width (pipeline 2.0 rule 12).
	local a, p, s = node.AnchorPoint, node.Position, node.Size
	node.AnchorPoint = Vector2.new(0, a.Y)
	node.Position = UDim2.new(p.X.Scale - a.X * s.X.Scale, p.X.Offset - a.X * s.X.Offset, p.Y.Scale, p.Y.Offset)
```
This covers `Fill`, `HoldFill` and `PartyDownFill`. HoldFill's 0.0074 left inset is kept exactly.

**3.2 `opts.Touch` (D10).**
`local touch = opts.Touch == true or bundle == "HUD_Touch" or string.sub(Binder.base(source.Name), -5) == "Touch"`.

**3.3 Header.** Mount's paragraph gains: "Every `*Fill` is anchored on its left edge (the caller owns its width);
`opts.Touch` floors text at 12 px for a PC template drawn on the touch layout." Leave the "B3-B5 add Paint, Stack,
Ring…" line as it is, minus B3.

**Test (`tools/tests/test_round_hud.py`, new `do` blocks):**
1. Mount `HUD_PC/StaminaBar`: `Track/Fill` AnchorPoint.X is 0 and Position.X.Scale is 0 (±1e-6). The **template's**
   Fill is untouched (still 0.5 / 0.3125). Writing `Size = fromScale(0.3, 1)` leaves Position unchanged.
2. Mount `HUD_PC/LeaveChipWide`: `HoldFill`'s left edge stays at 0.309259 − 0.5 × 0.603704 (±1e-6).
3. Mount `HUD_PC/StaminaBar` with `{Scale = 0.5, Touch = true}`: the root is 160 x 13 and `Winded` has a
   `UITextSizeConstraint` with MinTextSize 12. Without `Touch`, no constraint.
4. Mount `HUD_PC/NoiseMarker`: no node is re-anchored (no Fill).
5. Existing checks unchanged. ASCII, LF and `luau-compile --null` as today.

---

## 4. Agent B · NoiseReporter (`StarterPlayer/StarterPlayerScripts/NoiseReporter.LocalScript.lua`)

Wrap the bar code in `-- == B3 stamina bar (10 C; owner, 2026-10-08) ==` … `-- == end B3 stamina bar ==`.
Place it where `staBg` is built today: **above `local boostActive = false`**. `test_speed_potion` slices from there
to the main Heartbeat, and that span must hold no bar code.

**4.1 `MoveNoise` (D6).** In `applySpeed`, right after the round branch's `if crouching … else … end` chain and
before `desiredSpeed *= speedBoost()`:
```lua
if player:GetAttribute("MoveNoise") ~= state then player:SetAttribute("MoveNoise", state) end
```
That is the only write in the file.

**4.2 Remove**
- `BAR_W`, `BAR_H`, `STA_FULL`, `STA_EMPTY`, `BAR_BG_ALPHA`, `BAR_FADE`, and the white→red prose above them. The
  `StaminaGui` creation below them stays.
- `staBg`, `objectiveReserve()`, `applyStaminaLayout()` and its `UIDevice.Changed:Connect(applyStaminaLayout)`,
  `staFill`, `bgc`, `fc`, `barShown`.
- In the main Heartbeat:
  - the spectating branch's drawing (centre, bottom, size, fill, `Lerp`, fade);
  - the lobby branch's `barShown = 0` and its two transparency writes;
  - the in-round tail's `staFill` writes and the `wantShown` / `barShown` fade.
- In `updateRoundState`: `applyStaminaLayout()` (becomes `placeBar()`) and the `staBg.Visible = active …`
  statement with its comment. Death, escape and spectating are now gated in `paintBar`'s callers.

**4.3 The B3 section** (sketch; names are the contract the test slices against):
```lua
local BAR_BOTTOM, BAR_BOTTOM_TOUCH, BAR_TOUCH_SCALE, SPECTATE_LIFT = 24, 4, 0.5, 92
local barHud -- RoundHud, only when B2's lookup found it and ShopBinder (touchPalette ~= nil)
if touchPalette then barHud = require(RS:FindFirstChild("RoundHud")) end
local bar = {}          -- Root, Attention, Fill, Winded, Scale, Room, Frac, Tone, Mode, Watched, WatchedDrain
local lastDrainAt = -math.huge

-- (Re)mounts HUD_PC/StaminaBar when the scale changes (PC and pad 1, touch 0.5), then places it.
local function placeBar() ... end
-- frac nil = off. Writes Fill and Winded on change, and calls Attention only when the mode changes.
local function paintBar(frac, winded, draining) ... end
-- Spectating: the watched fraction, trend from value changes, never WINDED (D15).
local function paintWatched(frac) ... end
```
- **`placeBar()`:**
  - `scale = Layout().IsTouch and BAR_TOUCH_SCALE or 1`. When it differs from `bar.Scale`, destroy the old root,
    clear the cached fields, and mount. A device flip leaves exactly one `StaminaBar`:
    ```lua
    if barHud then
        bar.Root, bar.Attention = barHud.Mount("HUD_PC", "StaminaBar", gui, {Name = "StaminaBar",
            Scale = scale, Touch = touch, Attention = {Hold = 0, Rest = 0.55}})
    end
    ```
    Use a plain `if`: `barHud and barHud.Mount(...)` would drop the second return.
  - Then `bar.Fill = bar.Root:FindFirstChild("Fill", true)`, `bar.Winded = bar.Root:FindFirstChild("Winded", true)`,
    `bar.Winded.Visible = false` (the template ships it visible), and `bar.Root.AnchorPoint = Vector2.new(0.5, 1)`.
  - Every call: `bar.Room = not touch or Corridor.Width >= 320 * BAR_TOUCH_SCALE + 8`.
    - The centre is the Safe centre on PC, or the Corridor centre on touch.
    - The bottom is `Safe.Bottom − (touch and BAR_BOTTOM_TOUCH or BAR_BOTTOM) − (Spectating and SPECTATE_LIFT or 0)`.
    - `bar.Root.Position = UIDevice.LocalPosition(gui, centre, bottom)`.
- **`paintBar(frac, winded, draining)`:**
  - The mode is OFF when `frac` is nil or there is no room. Otherwise it is WINDED if `winded`, else DRAIN if
    `draining`, else RECOVER when `frac < 0.999`, else OFF.
  - The tone is Coral if `winded`, else Amber at `frac <= 0.25`, else Cream (`touchPalette[tone]`).
  - When `frac` moved more than 0.001, or the tone changed: write `Fill.Size = UDim2.fromScale(frac, 1)`, the Fill
    colour, and `Winded.Visible = winded`.
  - On a mode change: `Hide()` / `Show("bar")` / `Show("bar", true)` per §2.4.
- **`paintWatched(frac)`:** if `frac` differs from `bar.Watched`, set `bar.WatchedDrain = frac < bar.Watched`. Then
  `paintBar(frac, false, bar.WatchedDrain == true)`.

**4.4 Callers**
- **Main Heartbeat, spectating branch.** Keep `valid` as it is. Call
  `paintWatched(valid and not UIDevice.ScreenOwningModalOpen() and math.clamp(value, 0, 1) or nil)`. Keep
  `lastFrac = -1` and the `return`.
- **Lobby branch.** `paintBar(nil)`.
- **In-round tail.**
  - In the drain branch (`elseif state == "sprint" and moving …`), add `lastDrainAt = os.clock()`.
  - After the `Stamina` / `spectatevital` block, which is unchanged:
    ```lua
    local _, hum = currentChar()
    paintBar(hum and hum.Health > 0 and not isEscaped() and frac or nil, exhausted, os.clock() - lastDrainAt < 0.5)
    ```
- **`updateRoundState`.** `placeBar()` where `applyStaminaLayout()` was. It already runs on `Spectating`,
  `UIDevice.Changed`, `InRound` and death.
- Do **not** add another `RunService.Heartbeat:Connect(function(dt)` above the main one: two tests anchor on the
  first occurrence.

**4.5 Keep**
- Every stamina, speed and adrenaline constant (`test_speed_potion` asserts them), `staminaMax`, `stamina`,
  `exhausted` and `state`.
- The noise loop, the crouch pipeline, `sprintRequested`, and every input path.
- The `Stamina` attribute and the `spectatevital` report, with their `lastFrac` / `lastExhausted` dirty cache.
- `StaminaGui`: its name, `DisplayOrder = 60`, `ResetOnSpawn = false`, and `gui.Enabled = true` in
  `updateRoundState`. UIRegression `REQUIRED_GUIS` and `test_lucky_wheel_client` name it.
- B2's section, `paintRun` and `touchPalette`.
- `RoundEntryControlsReady` as the **last line**.

**4.6 Tests**
- **`test_controller_input.py`**
  1. `noise_setup`'s `player` gains `SetAttribute = function(_, k, v) attrs[k] = v; moveNoiseWrites += 1 end`, with
     `local moveNoiseWrites = 0`.
  2. New `noise_tests` lines:
     - walking in-round → `MoveNoise == "walk"`;
     - Shift → `"sprint"`;
     - `crouching = true; applySpeed()` → `"crouch"`;
     - `exhausted = true` with Shift held → `"walk"`;
     - an unchanged state makes no second write.
  3. A new `b3_program()`, shaped like `b2_program()`. It loads the B3 section over the real RoundHud (with A's
     change), ShopBinder and the HUD_PC dump. The prelude supplies `gui` (a ScreenGui in `ctx.PlayerGui`),
     `UIDevice` (`ctx.UIDevice` plus `Layout()` with `IsTouch`, `Safe`, `Corridor`), `player`, `RS`,
     `touchPalette = Binder.Palette` and `currentChar`. Checks:
     - **Mount.** A CanvasGroup `StaminaBar` in `StaminaGui`, 320 x 26, hidden. `Winded` is hidden and Fill
       AnchorPoint.X is 0 before any paint.
     - **Truth table.** Each row also asserts opacity after `ctx:Advance`:
       - `(1, false, false)`: hidden;
       - `(0.6, false, true)`: 100 %, Fill 0.6, Cream, and still 100 % after 60 s;
       - `(0.25, false, true)`: Amber;
       - `(0, true, false)`: Coral, `Winded` shown, 100 % after 60 s;
       - `(0.24, true, false)`: still 100 %;
       - `(0.26, false, false)`: 55 %, Cream, `Winded` hidden;
       - `(0.2, false, false)`: Amber at 55 %. This is the multiplier-2 band, where exhaustion clears at 12.5 %;
       - a repeated identical call creates no tween.
     - **Placement.** PC: AnchorPoint (0.5, 1), bottom at `Safe.Bottom − 24`, centred on Safe. Spectating: − 116.
       Touch 844 x 390 (Corridor 346..537): the remount gives 160 x 13, `Winded` MinTextSize 12, centre 441.5,
       bottom `Safe.Bottom − 4`. A Corridor of 140 gives no room and stays hidden. A flip back to PC leaves exactly
       one `StaminaBar`, at 320 x 26.
     - **`paintWatched`.**
       - 0.8 then 0.6: 100 %;
       - 0.6 again: still 100 %;
       - 0.7: 55 %;
       - 0: `Winded` stays hidden.
     - **Missing bundle** (skip HUD_PC): one `HUD_PC/StaminaBar` warning, and `paintBar` is a no-op without error.
  4. Static checks:
     - none of `staBg`, `staFill`, `barShown`, `BAR_FADE`, `STA_FULL`, `STA_EMPTY`, `applyStaminaLayout`,
       `objectiveReserve` or `:Lerp(` remain;
     - exactly one `SetAttribute("MoveNoise"`, and it is inside `applySpeed`;
     - the B3 section is ASCII, holds no `WaitForChild`, and sits above `local boostActive = false`;
     - the only `.Visible =` writes in the section are on `Winded`;
     - `gui.Name = "StaminaGui"` and `gui.DisplayOrder = 60` are present;
     - `RoundEntryControlsReady` is still the last line.

  B2's slices and checks stay as they are.
- **`test_speed_potion.py`** (red at HEAD, handed to B3 by B2). Add the stubs the real code needs, and bend no
  assertion:
  - `local previewAllowed = false` at the end of `HARNESS`;
  - `line("local function inPreview()")` before the `inRound` line in `FIXTURE`;
  - `block("local function isHiding()", "local vitalRemote")` after it.

  Verified on the 23:40 tree in a scratch copy: **498 checks pass**. The `MoveNoise` write needs nothing more,
  because that harness's `player` has `SetAttribute`.
- **`tools/playtest_ui_pit_regressions.py`.** `stamina:FindFirstChildWhichIsA("Frame")` finds nothing once the bar
  is a CanvasGroup. Read `stamina:FindFirstChild("StaminaBar")` instead (it now reports 320 x 26).

---

## 5. Agent C · ProtectionHUD (`StarterPlayer/StarterPlayerScripts/ProtectionHUD.LocalScript.lua`)

**Remove** (tag the edit `HUD_B3`):
- The `reentryNotice` TextLabel (`Name = "ReentryGrace"`, `UIStyle.caption` / `body`, Live colour), created right
  after `gui`.
- `reentryNotice.Visible = false` at the top of `refresh()`.
- The tail of `refresh()`: from `local remaining = secondsRemaining()` through the `"You are invisible to
  monsters\n%d seconds"` write and its `end`. This includes B2's C9 call `clearOfFan(layout, area.Bottom - 32)`.

**Keep**
- `clearOfFan`, because `placeKit` still uses it for the refusal tag.
- `secondsRemaining`, which the chip and the spectate mirror use.
- `PlayerProtectionSource` in the attribute listener list (`secondsRemaining` derives the 10 s / 5 s clamp from it).
- `underRoundUI`, `covered`, `contextAvailable`, the gui name and order 1001, and every B1 and B2 section.

**Test (`tools/tests/test_equipment_hud.py`):**
- With `PlayerProtectionActive = true`, `ExpiresAt = Now + 10` and `Source = "Reentry"` on a living in-round body:
  `ctx.gui` has no `ReentryGrace` child, and no TextLabel under it contains "invisible".
- The chip's ACTIVE look is unchanged (the existing `9.2 / SAFE` check stays).
- Static: the source holds neither `ReentryGrace` nor `invisible to monsters`. Every other check is unchanged.

---

## 6. Agent D · Round HUD (new `StarterPlayer/StarterPlayerScripts/Round HUD.LocalScript.lua`)

The cross-level body-state driver (BUILD-PLAN §1.1). B5 later adds the feed to this same script. Sections:
`-- == B3 chase edge (02 A, reduced flashing; owner, 2026-10-08) ==` and `-- == B3 marker (03 C; owner,
2026-10-08) ==`, each with its `-- == end … ==`.

**6.1 Boot**
```lua
local Players, RS = game:GetService("Players"), game:GetService("ReplicatedStorage")
local RunService, TweenService = game:GetService("RunService"), game:GetService("TweenService")
local UIDevice = require(RS:WaitForChild("UIDevice"))
local player = Players.LocalPlayer
if not game:IsLoaded() then game.Loaded:Wait() end
local hudModule, shopUI = RS:FindFirstChild("RoundHud"), RS:FindFirstChild("ZyntraShopUI")
local binderModule = shopUI and shopUI:FindFirstChild("ShopBinder")
if not (hudModule and binderModule) then warn("[Round HUD] RoundHud or ShopBinder is missing: nothing drawn") return end
local Hud, P = require(hudModule), require(binderModule).Palette
```

**6.2 Chase edge**
- **The gui.** A ScreenGui named `RoundHudThreat`: `DisplayOrder = 20`, `ResetOnSpawn = false`,
  `ScreenInsets = Enum.ScreenInsets.None` (full screen, under the notch too), `IgnoreGuiInset = true`, in PlayerGui
  at boot.
- **The bands.** Four Frames, `Left`, `Right`, `Top` and `Bottom`, each with `BackgroundColor3 = P.Coral`,
  `BackgroundTransparency = 1`, `BorderSizePixel = 0`, `Active = false`, and a UIGradient with
  `Transparency = NumberSequence.new(0, 1)`:

  | Band | AnchorPoint | Position | Size | Gradient Rotation |
  |---|---|---|---|---|
  | Left | (0, 0) | (0, 0) | `fromScale(0.146, 1)` | 0 |
  | Right | (1, 0) | `fromScale(1, 0)` | `fromScale(0.146, 1)` | 180 |
  | Top | (0, 0) | (0, 0) | `fromScale(1, 0.185)` | 90 |
  | Bottom | (0, 1) | `fromScale(0, 1)` | `fromScale(1, 0.185)` | 270 |
- **`setEdge(on)`.** Compare first. Then on every band, tween `BackgroundTransparency` to `EDGE_ALPHA` (0.8) over
  0.18 s, or to 1 over 0.4 s.
- **Forbidden in this section:** `os.clock`, `tick(`, `time(`, `sin(`, `ReduceFlashing`.
- **Order 20** draws under the touch cells (60/61/1001), Level 3's hide shade (92), RoundUI (100) and the kill cam.
  That is intended: the cells stay legible, and the Level 3 shade dims the edge.

**6.3 Marker**
- **Mount once at boot.**
  `marker.Root, marker.Attention = Hud.Mount("HUD_PC", "NoiseMarker", Hud.Gui(), {Name = "NoiseMarker",
  Attention = {Hold = 6, Rest = 0.45}})`. Use `"HUD_PC"` on every device: `Hud.Bundle()` returns HUD_Touch on
  touch, and that bundle has no marker. Scale 1. If the mount returns nil, there is no marker; the edge still works.
- **Then:**
  - find `Soft`, `Dot` and `Label`;
  - `Soft.AnchorPoint = (0, 0.5)`, `Soft.Position = fromScale(0, 0.5)`;
  - `marker.Root.AnchorPoint = (0, 1)`;
  - `CHAR_W = Label:GetAttribute("FigmaTextW") / utf8.len(Label:GetAttribute("FW_Text0"))`, falling back to 7.2.
- **`markerState(character)`:**
  1. GRACE when `PlayerProtectionSource == "Reentry"` and the remaining time is > 0. Copy ProtectionHUD
     `secondsRemaining`'s guards exactly: Active `== true`, ExpiresAt a finite number (not NaN, not ±huge), clamped
     to 0..10 against `workspace:GetServerTimeNow()`. Return the state and `math.ceil(remaining)`.
  2. HIDDEN when `Level3_Hiding == true` or `Level4_Hidden == true`.
  3. LOUD when `MoveNoise == "sprint"` and the root's horizontal `AssemblyLinearVelocity` magnitude is > 2.
  4. SNEAKING when `MoveNoise == "crouch"`.
  5. Otherwise nil.
- **`showMarker(state, seconds)`:**
  - **Text.** `state`, or `"INVISIBLE TO MONSTERS \u{B7} " .. seconds .. " s"` for GRACE. On touch, when
    `20 + utf8.len(full) * CHAR_W + 8 > Layout().Corridor.Width`, use `"INVISIBLE \u{B7} " .. seconds .. " s"` (D11).
  - **On a text change, or after `UIDevice.Changed`:**
    - write `Label.Text`;
    - `W = 20 + utf8.len(text) * CHAR_W + 8`;
    - `Soft.Size = UDim2.new(0, W, 1, 0)`;
    - `Dot.BackgroundColor3 = state == "LOUD" and P.Amber or P.RailTeal`;
    - place the root at `UIDevice.LocalPosition(Hud.Gui(), centre - W / 2, Safe.Bottom - bottom)`. On PC the centre
      is the Safe centre and `bottom` is `MARKER_BOTTOM`; on touch they are the Corridor centre and
      `MARKER_BOTTOM_TOUCH`.
  - **On a state change only:** the Attention call from §2.4. The GRACE countdown changes only the text.
- **Lifecycle:** one `RunService.Heartbeat` connection.
  ```lua
  local inRound = player:GetAttribute("InRound") == true
  if wasInRound and not inRound then Hud.Clear() end -- first caller (D17)
  wasInRound = inRound
  local base = <section 2.3>
  setEdge(base and player:GetAttribute("BeingChased") == true and workspace:GetAttribute("SelectedLevel") ~= 2)
  showMarker(if base then markerState(character) else nil)
  ```

**6.4 Install.** The push tool cannot create a script. Run
`python tools/install_new_scripts.py --dry-run "StarterPlayer/StarterPlayerScripts/Round HUD.LocalScript.lua"`,
then without `--dry-run`. It creates the script, reads it back byte for byte and writes the `synced` manifest item.
The source must be ASCII (`json.dumps` embedding).

**6.5 Test: new `tools/tests/test_round_hud_local.py`.**
- **Setup.** Import `HARNESS, SOURCES, long_string, lua, trees` from `test_round_hud`. Inject the script as
  `ROUND_HUD_SOURCE`. Build a `hudContext`-style context, copying `test_equipment_hud`'s, with:
  - `RunService = {Heartbeat = signal()}`;
  - `game.IsLoaded`;
  - a character with a Humanoid (Health) and a `HumanoidRootPart` carrying `AssemblyLinearVelocity`;
  - `ctx.UIDevice.Layout` returning `IsTouch`, `Safe` and `Corridor`;
  - `NumberSequence`, `TweenInfo`, `Vector3` and `utf8` in the script's environment;
  - a `ctx:Step()` that advances the clock and fires Heartbeat.

  Wrap the tests in `do` blocks.
- **Checks:**
  1. **Gui.** `RoundHudThreat`: order 20, ScreenInsets None, four bands with the §6.2 sizes and rotations,
     `Active = false`, Coral, gradient 0 → 1, transparency 1 at boot.
  2. **Edge truth table.** Over levels 1-4 × `BeingChased` true / false / nil × {alive, dead, `Spectating`,
     `Escaped`, InRound false, RoundActive false}, the edge is on (all four bands at 0.8, tween time 0.18) exactly
     when the flag is true, the level is not 2 and the base gate holds. Off means 1 and tween time 0.4.
  3. **ReduceFlashing.** The goal transparency and tween times are identical for true, false and nil.
  4. **Static.** The edge section holds none of `os.clock`, `tick(`, `time(`, `sin(`, `ReduceFlashing`.
  5. **Priority.** All 12 combinations of GRACE (on/off) × HIDDEN (on/off; Level3 and Level4 each) × `MoveNoise`
     walk / sprint / crouch. Text and Dot colour
     follow GRACE > HIDDEN > LOUD > SNEAKING; walking is hidden. `sprint` at speed 1 is hidden (D5).
  6. **Attention.**
     - SNEAKING is 100 % until 5.9 s and 45 % at 6 s;
     - LOUD rests at 60 %;
     - HIDDEN to SNEAKING is a change (100 % again);
     - walking then crouching after a Hide is 100 %.
  7. **Grace.**
     - `ExpiresAt = Now + 10`, Reentry: `INVISIBLE TO MONSTERS \u{B7} 10 s`, then `9 s` after 1 s, …, `1 s`, then the
       next state at 10 s;
     - opacity is 45 % from 6 s on, so the tick does not re-wake it;
     - a renewal (ExpiresAt jumps) shows 10 again;
     - `Source = "Shield"`, `Active = false`, NaN or `math.huge` give no GRACE.
  8. **Level 2.** With `SelectedLevel = 2`, crouch shows SNEAKING, and BeingChased true draws no edge.
  9. **Spectating, dead, escaped.** Marker hidden and edge off. InRound true → false calls `RoundHud.Clear()`: a
     detector card shown before is gone.
  10. **Placement.**
      - PC 1920 x 1080: the root bottom is at `Safe.Bottom − 54`, and `root.X + Soft.Width / 2` is the Safe centre
        (±1). `Soft` is anchored left, and SNEAKING has W = 20 + 8 × 7.22 + 8.
      - Touch 844 x 390 (Corridor 346..537): bottom at `Safe.Bottom − 22`, centred at 441.5 (±1). GRACE reads the
        short copy and W ≤ 191. With a 400-wide Corridor it reads the full copy.
  11. **Template facts against the dump.** Label left edge at 20, `CHAR_W` 195/27, Label `TextXAlignment` Left,
      Dot at x 8..14.
  12. **Cross-check.** NoiseReporter's `BAR_BOTTOM` etc. line is parsed, and `MARKER_BOTTOM == BAR_BOTTOM + 26 + 4`
      and `MARKER_BOTTOM_TOUCH == BAR_BOTTOM_TOUCH + 26 × BAR_TOUCH_SCALE + 5`. Green once B is in.
  13. **Missing bundle** (skip HUD_PC): one `HUD_PC/NoiseMarker` warning, no marker, and the edge still turns on.
  14. **Source.** ASCII-only, LF, `luau-compile --null` accepts it. No `ADRENALINE`. No `WaitForChild("RoundHud"`,
      `"ZyntraHUD"` or `"ZyntraShopUI"`.

---

## 7. Studio half (a local session on the owner's PC only)

**Push list**

| Script | Kind | How |
|---|---|---|
| `ReplicatedStorage/RoundHud.ModuleScript.lua` | changed (B1's; manifest `synced`) | `record_pending_push` + push |
| `StarterPlayer/StarterPlayerScripts/NoiseReporter.LocalScript.lua` | changed (on top of B2) | `record_pending_push` + push |
| `StarterPlayer/StarterPlayerScripts/ProtectionHUD.LocalScript.lua` | changed (on top of B2) | `record_pending_push` + push |
| `StarterPlayer/StarterPlayerScripts/Round HUD.LocalScript.lua` | **NEW** | `tools/install_new_scripts.py` (§6.4). It must be created in Studio first; the push tool cannot create it |

Tests and `tools/playtest_ui_pit_regressions.py` are repo-only.

**Steps**
1. B2's push has landed and its handover is in. Run `03_hud_check`: `HUD_PC/StaminaBar` and `HUD_PC/NoiseMarker`
   are present.
2. Run `git status` for foreign untracked files. Run `python tools/pull_source_from_studio.py --audit`. Take the
   Studio lock `_local/studio-lock.json`. Check `list_roblox_studios` for the place name: at 20:55 it was
   `[UPDATE] BACKROOMS: STAY QUIET`.
3. Run `python tools/record_pending_push.py`, then
   `python tools/push_repo_to_studio.py --audit --studio-name "[UPDATE] BACKROOMS: STAY QUIET"`, then the push.
   Merge any CONFLICT (MOBILE_QA and other sessions touch NoiseReporter and ProtectionHUD). Never use
   `--overwrite-conflicts`.
4. Install Round HUD (§6.4).
5. Run `tools/studio_compile_probe.luau`. Run the offline suites with
   `LUAU_BIN=C:/Users/mikke/AppData/Local/Temp/codex-luau-0.737/luau.exe`:
   `test_round_hud`, `test_round_hud_local`, `test_controller_input`, `test_speed_potion`, `test_equipment_hud`,
   `test_flashlight_player_control`, `test_lucky_wheel_client`, `test_spectator_vitals`, and
   `artifacts/.../tests/test_hud_templates.py`.

---

## 8. B3 QA → checks

PC is 1920 x 1080. TOUCH is `ForceTouchUI` + `UIRegressionViewport` 844 x 390. PAD is after a pad input. Start
rounds with the playtest recipe, and press B to hide developer ESP first.

| # | QA item (BUILD-PLAN §4 B3, plus what this brief adds) | Offline | Studio |
|---|---|---|---|
| 1 | PC: sprint and the hairline shows. ≤ 25 % turns Amber. Empty shows WINDED and does not dim until it recovers (25 stamina), then rests at 55 %. Full hides it. | B `b3_program` truth table | PC Level 1: sprint to empty, stop, wait |
| 2 | PC: crouch → SNEAKING, then 45 % after 6 s. Sprint → LOUD, resting at 60 %. Walk → nothing. Shift while standing still → nothing (D5). | D 5, 6; B `MoveNoise` | PC Level 1 |
| 3 | PC: hide under a Level 3 table → HIDDEN. Hide in Level 4 → HIDDEN (twice until B4: `hiddenChip`). | D 5 | Level 3 table; Level 4 crouched in an L4HideZone |
| 4 | Re-entry → `INVISIBLE TO MONSTERS \u{B7} 10 s` counts down. ProtectionHUD's old green sentence is gone. The shield chip shows ACTIVE beside it. | D 7; C | Die, then `ServerStorage.ZyntraReentry:Invoke(player, true)` (free developer path) |
| 5 | PC: a Level 1 entity chase → static coral edge, the same with ReduceFlashing on and off. A Level 3 Manager chase → the edge. | D 2, 3, 4 | Level 1 chase; toggle ReduceFlashing on the SETTINGS tab; Level 3 hunt |
| 6 | **Level 2:** no edge even while Pool Foam targets you; the marker still shows. | D 8 | Level 2 round; server-side `player:SetAttribute("BeingChased", true)` via `execute_luau` in the play session |
| 7 | TOUCH: the marker sits in the corridor. **Changed by D9:** the bar is shown 160 wide in the corridor (as `phone-level-1.png`), and hidden when the corridor is < 168 (667 x 375). GRACE reads the short copy at 844 x 390 (D11). | B placement; D 10 | TOUCH screenshot vs `phone-level-1.png`; `UIRegressionViewport` 667 x 375 |
| 8 | Spectating: no marker and no edge. The bar shows the watched stamina 92 px up, never WINDED. | D 9; B `paintWatched` | 2-player local server, PC and TOUCH |
| 9 | Template samples never show: no `WINDED` or 62.5 % fill at round start, and no `8 s` grace sample. | B mount; D 1, 10 | Round start, first frame (screenshot) |
| 10 | Death: the marker, edge and bar are gone at once over the death card. | D 9; B (alive gate) | Die to the Level 1 entity |
| 11 | Round end: the marker, edge and detector card are gone under the results. | D 9 (`Clear`) | Win a round |
| 12 | Missing bundle: warnings by path, the edge still works, `RoundEntryControlsReady` within 1 s of `game.Loaded`. | B, D 13 | — |
| 13 | PAD: the same as PC (L2 sprint → LOUD). | — | PAD pass of #1-#2 |
| 14 | A Fill grows rightward from the track's left edge. | A 1, 2 | #1, watched |
| 15 | Lucky Wheel still disables `StaminaGui` (lobby). | `test_lucky_wheel_client` | — |

---

## 9. Left for later, and flags

- **Owner TOUCH QA:** D9 (touch bar shown), D11 (short GRACE copy), D5, D16, and Level 4 showing HIDDEN twice until
  B4 retires `Level 4 Round Client`'s `hiddenChip`.
- **Level 3 edge semantics (owner or QA call).** `BeingChased` is the Manager's target: the hunt target, a player
  hidden under a table, and heard INVESTIGATE. The edge therefore shows for most of a hunt, under the hide shade.
  The stricter option is `workspace.Level3MallManagerState == "CHASE"` as well.
- **Level 2 Pool Foam caption (other owner).** `Level2PoolFoamGui.Caption` sits at scale 0.91, 50 tall, at order 72.
  On PC it clears the marker (933..983 against 1002..1026). On a phone it covers y 305..355, which is the marker,
  the bar and the lower cell row. It predates B3. Flag it for the Level 2 session; the entity is going anyway.
- **RoundUI `subtitleFrame`** (dormant, `BRIEFINGS_OFF_20261004`) drops onto the marker band while `Level3_Hiding`.
  A Studio-forced `UIRegressionForceDispatchActive` row may show the overlap.
- **SpectateController's comment** "Spectating hides the stamina bar" is now stale. B8 owns that file.
- **B5:** captions go above the marker's top (`Safe.Bottom − 78` on PC). Round HUD is the script B5 extends.
- **B4+:** every `*Fill` is already left-anchored by Mount (D13); B4's progress bar just writes its width.
- **Unowned:** `test_hud_copy_rules.py` does not exist. The new strings are `SNEAKING`, `LOUD`, `HIDDEN`,
  `INVISIBLE TO MONSTERS \u{B7} N s` and `INVISIBLE \u{B7} N s`.
- **Notes owner (orchestrator, after the push):** CLAUDE.md lines for the `MoveNoise` contract, `Round HUD`,
  `RoundHudThreat` at order 20, Mount's Fill re-anchor and `opts.Touch`, and the touch-bar deviation (D9).
- **Stray files** inside the Studio mirror and artifacts, not B3's to delete: `StarterPlayer/StarterPlayerScripts/6430`
  (0 bytes); `artifacts/hud-final-20261008/700'`, `3640`, `7030`.

---

## Critic findings (2026-10-08)

This is a read-only completeness review, done at about 00:15 while B2 was still landing. It checks the brief against:
- BUILD-PLAN 02, 03, 10 and §4 B3;
- OWNER-PICKS;
- the pipeline (§2.0, §2.7, §2.8, §5);
- B2-DESIGN;
- the HUD_PC and HUD_Touch dumps;
- the approved frames;
- the live scripts.

Offline suites on that tree:
- green: `test_round_hud` 164, `test_equipment_hud` 679, `test_controller_input` 123 + 86;
- red: `test_speed_potion`, as §4.6 says.

The corridor widths below come from the REAL UIDevice, run through `test_touch_control_plan`'s fixture matrix in a
scratch copy outside the repo.

### Blocking (the brief as written breaks code or a test)

**K1. `paintWatched` throws on its first call and on every invalid frame (§4.3, §4.4).**
- The rule "if `frac` differs from `bar.Watched`, set `bar.WatchedDrain = frac < bar.Watched`" has three faults:
  - The first sample compares against nil.
  - The caller passes `nil` on every frame where the watched player is invalid or a modal is open (`nil < number`).
    So the Heartbeat callback errors on every spectating frame and the bar never paints.
  - The sketch never stores `bar.Watched = frac`, and a target switch (Q / E) compares two different players' stamina.
- **Fix** (B):
  ```lua
  local function paintWatched(frac, id) -- id = SpectateTargetUserId
  	if frac == nil or id ~= bar.WatchedId then bar.Watched, bar.WatchedDrain, bar.WatchedId = nil, nil, id end
  	if frac == nil then paintBar(nil) return end
  	if bar.Watched ~= nil and frac ~= bar.Watched then bar.WatchedDrain = frac < bar.Watched end
  	bar.Watched = frac
  	paintBar(frac, false, bar.WatchedDrain == true)
  end
  ```
  The first sample of a target reads RECOVER (55 %). Add to the `paintWatched` test:
  - `nil` does not throw;
  - a switch from a target at 0.3 to one at 0.9 counts as a first sample, not a recovery.

**K2. `test_equipment_hud.py` already asserts the notice that C deletes (§5).**
- B2's C9 block (the refusal tag beside the open KIT fan) sets `PlayerProtectionSource = "Reentry"`. It then reads
  `local notice = ctx.gui:FindFirstChild("ReentryGrace")` and checks `notice.Visible` and `notice.Position`.
- After C's removal `notice` is nil and the suite errors. §5's "Every other check is unchanged" contradicts this.
- **Fix** (C, after B2's handover):
  - Delete the three `PlayerProtection*` writes and the two `notice` checks in that block.
  - Keep `ctx:TapKit(); ctx:Step(0)` and the caption check after them ("as does the tag").
  - The new absence check replaces the deleted lines.

### Should fix (layout and tooling collisions)

**K3. On smaller phones the marker leaves the corridor (D11, §6.3, test 10).**
- Real corridor widths:

  | Screen | Corridor |
  |---|---:|
  | 844x390 | **191** |
  | 812x375 | 175 |
  | 705x338 | 155 |
  | 667x375 (housing 44/44/21) | **88** |
  | 568x320 | **72** |
  | 375x812 portrait | **0** |

  The brief's "Corridor of 140 (667 x 375)" is a synthetic number.
- GRACE's short pill (`INVISIBLE \u{B7} 10 s`, W 143.5) does not fit in 88 or 72.
  - At 568x320 it runs into the thumbstick zone on the left. On the right it runs under the LIGHT cell (x 316..368,
    drawn above it at order 61), which hides the countdown.
  - In portrait, every state sits on the cluster.
- **Fix** (D): when `W > Corridor.Width + 16` (the two 8 px gutters), seat the pill where ProtectionHUD's retired
  `ReentryGrace` sat:
  - centre `(ModalArea.Left + ModalArea.Right) / 2`;
  - bottom `ModalArea.Bottom - 32`, lowered to `KitFan.Top - 8` while `Layout().KitFanOpen` (B2 C9's rule).

  ModalArea is movement-safe by construction. On 568x320 that band is shared with the objective pill, exactly as the old
  notice was: owner TOUCH QA.
- Test 10 gains a 667x375 row: SNEAKING (W 85.8) stays in the corridor, and GRACE moves to the ModalArea spot.

**K4. On PC windows narrower than about 1424 px, the bar and the marker sit on B1's kit row (D8).**
- B1's row ends at `Safe.Left + 544`: KIT_EDGE 24 + FlashlightWidget 232 + KIT_GAP 8 + EquipmentPanel 280, all taken
  from the dump and ProtectionHUD. It shares the bottom band (`Safe.Bottom - 108 .. -24`).
- The bar starts at `centre - 160`:
  - at 1366x768 it overlaps the chips by 21 px;
  - at 1280x720 it overlaps them by 64 px, and GRACE's 230 px pill overlaps them too.

  The QA list only measures 1920.
- **Fix** (B and D, the same formula, pinned like `BAR_BOTTOM`): on non-touch,
  `centre = math.max((Safe.Left + Safe.Right) / 2, Safe.Left + KIT_RIGHT + 8 + 160)` with `KIT_RIGHT = 544`.
  - Test 12 cross-checks `KIT_RIGHT` in both files.
  - Add a 1366x768 placement row to B's and D's tests.

**K5. On touch, the marker and the bar draw over the open Level 4 keypad (§2.3).**
- `Level4RoundGui` stays at order 6 until B7. At 844x390, `placeForDevice` seats the keypad at x 315..529, y 66..361
  (scale 0.894).
- The marker (order 10) lands on the keypad's bottom row at y 323..347. The bar (order 60) clips the keypad's bottom edge.
- **Fix:** add `player:GetAttribute("Level4CardOpen") ~= true` to the marker's base gate (D) and to `paintBar`'s
  in-round caller (B). The attribute is published on touch only, and ProtectionHUD's `covered()` already reads it.
  Remove both clauses in B7.

**K6. UIRegression will report both new elements, so D18 ("no change") does not hold.**
- **The marker.** Its root is a 240-wide CanvasGroup, and only `Soft` hugs the text. So on touch at 844x390 the
  transparent group runs from about x 398 to 638. `UIRegression.Scan` measures the group, which is Visible and not fully
  faded. Whenever a marker state is up it reports overlaps with the LIGHT and SNEAK cells, plus a Controls-zone hit.
- **The edge bands.** At 14.6 % and 18.5 % they are neither in `FULLSCREEN_OVERLAYS` nor 92 % of the screen. During a
  chase every rect near an edge "overlaps" `RoundHudThreat.Left` and the others.
- **Fix:**
  - (D) Pin the inner clone at `UDim2.fromOffset(240, 24)` right after Mount.
    - On every text change, set the CanvasGroup root to `UDim2.fromOffset(math.ceil(W), 24)`, so the group clips to the
      pill. `scaleText` reads its `k` from the clone, so the text size does not change.
    - Add this to §2.5 rule 5 as the second geometry exception, and to test 10 (`root.AbsoluteSize.X == ceil(W)`).
  - (D) Name the bands `ChaseEdgeLeft`, `ChaseEdgeRight`, `ChaseEdgeTop` and `ChaseEdgeBottom`, because generic names
    are a poor fit for path-based checks. Update test 1.
  - (Orchestrator, after B2 hands UIRegression over)
    - Add those four names to `FULLSCREEN_OVERLAYS`. It is a table entry, so no new local. The Level 3 shade's
      `TableEdgeTop` / `TableEdgeBottom` are the precedent.
    - Add UIRegression to the §7 push list.
    - Add to §8: a TOUCH `RunAll` with SNEAK engaged, and a Level 1 run with `BeingChased` forced.

**K7. LOUD flickers at the 2 studs/s threshold (D5).**
- D14 gives the bar a 0.5 s window for exactly this case, but the marker has none.
- A stop-start with sprint held, a corner or a wall drops LOUD to `Hide()` (0.4 s out). The next `Show("LOUD")` then
  counts as a change and shows 100 % for another 6 s. That reads as a pulse, which §2.4 forbids.
- **Fix** (D):
  - Keep `lastFastAt`, updated while the horizontal speed is above 2.
  - LOUD = `MoveNoise == "sprint" and os.clock() - lastFastAt < 0.5`. `os.clock` is allowed in the marker section;
    only the edge section bans it.
- Tests 5 and 6:
  - speed 3, then 1 for 0.3 s, then 3: one LOUD and no new tween;
  - speed 1 for 0.6 s: LOUD hides.

**K8. The harness's `Vector3` has no `.Magnitude` (§6.5 setup).**
- `hud_harness.luau`'s `Vector3.new` returns a plain `{X, Y, Z}`. So `Vector3.new(v.X, 0, v.Z).Magnitude` in Round HUD
  becomes `nil > 2` offline.
- **Fix** (D): `local v = root.AssemblyLinearVelocity; local speed = math.sqrt(v.X * v.X + v.Z * v.Z)`. It gives the same
  result in the engine and needs no harness change.

### Minor and wording

- **K9. D13 covers Mount only.**
  - `ObjectiveCard` and `ObjectivePill` hold `Progress/Track/Fill`, and both are *stack* templates that B4 mounts through
    `RoundHud.Stack`.
  - §9's "B4's progress bar just writes its width" holds only if Stack mounts each part through `Mount`. Say so in §9.
- **K10. D16 is not true for the bar.**
  - NoiseReporter's `inRound()` includes `inPreview()` (`Level6InRound`), so the bar keeps drawing in the Level 6
    playground, as it does today.
  - Reword D16: "Round HUD draws nothing; the bar keeps today's behaviour there". Do not gate it.
- **K11. D12's width is not exact.**
  - Roblox draws the label at TextSize 16: `12 x 1.3188`, rounded. The authored copy solves to 15.70, which also rounds
    to 16.
  - At that size a character is `FW_M100 / 27 / 100 x 16 = 7.36` px, not Figma's 7.22. The 28-character GRACE text
    therefore ends at x 226 of a 230 pill.
  - This is harmless today, but it matters once K6 clips the group. Use
    `CHAR_W = FW_M100 / (100 * utf8.len(FW_Text0)) * math.floor(FigmaFontSize * 1.3188 + 0.5)` (all three are clone
    attributes), so the clip never cuts a glyph. Test 11 pins 7.36.
- **K12. Test arithmetic.**
  - D test 5: GRACE x {off, Level3_Hiding, Level4_Hidden} x 3 noises is 18 combinations, not 12.
  - B's placement row expects "centre 441.5", but `UIDevice.LocalPosition` floors. Use 441 ±1, as D's test does.
- **K13. D's test 12 is red until B lands.**
  - List it as expected-red in D's handover.
  - The orchestrator re-runs `test_round_hud_local` after B (§7 step 5 already does this).
- **K14. The edge's static scan trips on its own comments.**
  - The "Forbidden in this section: ... `ReduceFlashing`" check also catches a comment that says ReduceFlashing is never
    read.
  - Strip `--` comments before the scan, or tell D that the word may not appear at all.
- **K15. The phone frames do not centre on the corridor.**
  - `phone-level-1` and `-3` draw the bar at x 350..510 and the marker at about x 408..452. Both are centred at x 430,
    which for the bar is `Corridor.Left + 4`.
  - The brief centres on the corridor (441.5), 11 px further right, and QA #7 compares against that frame.
  - Pick one and state it. The corridor centre is fine if the owner's TOUCH QA accepts it.
- **K16. Owner QA list.**
  - Level 3 also shows HIDDEN twice, permanently, because B7 keeps the `HIDDEN UNDER TABLE` banner. Add it beside
    Level 4's entry.
  - `RoundHudThreat` (order 20) washes over every RoundHud (order 10) element:
    - the marker sits under about 13 % Coral in the bottom band;
    - from B4 on, the card's top-right corner sits under about 28 %.

    pc-level-3 draws it that way. Add "the card is legible under a Level 3 chase" to B4 QA rather than change the ladder.
- **K17. `Clear()` and the marker mounted at boot.**
  - The marker lives in the same `RoundHud` gui. If B4 or B5 widens `Clear()` to "everything RoundHud draws", the marker
    is destroyed and never remounted.
  - Either `showMarker` remounts when `marker.Root.Parent == nil`, or §9 states that `Clear()` tears down only the
    module's own nodes.
