# B2 design brief · touch cluster 14 A + KIT fan C · 2026-10-08

This is the implementation brief for batch B2 (BUILD-PLAN §4 B2). It is split by script so that five agents can work in parallel and no two of them edit the same file.

It was written read-only on 2026-10-08 at about 19:30, while B1 was still editing the working tree. Every line number below comes from that tree and will move. **Find code by the function names and markers given here, not by line number.**

Sources:
- `BUILD-PLAN.md`: §1.5, §2 (07, 08, 10, 14), §4 B2, §5.
- `FRAMEWISP-PIPELINE.md`: §1.4, §1.6, §2.0, §2.12, §5.
- `OWNER-PICKS.md`.
- The approved phone frames `phone-level-1.png` and `phone-level-3.png`, with their `-notes`.
- Element sheet tile `artifacts/hud-element-sheet-20261008/14-touch-buttons-phone.png`.
- The real import `tools/tests/fixtures/hud/framewisp-dump.HUD_Touch.json`.

---

## 0. Gate, agents, order

**Gate.** B1 is still editing `FlashlightController`, `ProtectionHUD`, `RoundHud`, `test_equipment_hud.py`, `test_flashlight_player_control.py` and `hud_harness.luau`. No B2 agent opens any of those until B1's handover has landed.

| Agent | Owns (the only files it edits) |
|---|---|
| **A · UIDevice** | `ReplicatedStorage/UIDevice.ModuleScript.lua`; **new** `tools/tests/test_touch_control_plan.py` |
| **B · NoiseReporter** | `StarterPlayer/StarterPlayerScripts/NoiseReporter.LocalScript.lua`; `tools/tests/test_controller_input.py` |
| **C · ProtectionHUD** | `StarterPlayer/StarterPlayerScripts/ProtectionHUD.LocalScript.lua`; `tools/tests/test_equipment_hud.py` |
| **D · FlashlightController** | `StarterPlayer/StarterPlayerScripts/FlashlightController.LocalScript.lua`; `tools/tests/test_flashlight_player_control.py` |
| **E · UIRegression** | `ReplicatedStorage/UIRegression.ModuleScript.lua` |

**Read-only for every B2 agent:**
- `RoundHud`, `ShopBinder`, `UIStyle`, RoundUI
- `tools/tests/hud_harness.luau` and `tools/tests/test_round_hud.py`
- the fixtures and `artifacts/.../install/*`

`hud_harness` exposes `ctx.UIDevice`. A test that needs more of UIDevice (`RegisterControlRect`, `SetInteractive`, `ScreenOwningModalOpen`, `Layout().ControlPlan`) adds those fields to `ctx.UIDevice` in its own program after `fresh()`. It never edits the harness. List any stub you added in your handover so it can be folded in later.

**Order.**
1. **A lands first**, because it is the contract (§2).
2. **B, C and D** code against §2 in parallel. Their offline tests go green only once A is in.
3. **E goes last**, against the merged tree.
4. **One Studio push for all five scripts** (§8).

---

## 1. Decisions (these settle the contradictions)

| # | Question | Decision | Why |
|---|---|---|---|
| D1 | Upper-row order | Template order. Right-first, the whole cluster is **JUMP, RUN, SNEAK, LIGHT, SHIELD, KIT, GLOW**, then the developer-only POV. Read left to right, the upper row is GLOW, KIT, SHIELD. | The dump and the approved frames ("GLOW KIT SHIELD y245"). BUILD-PLAN §14 wrote the upper row left to right and the lower row right-first. |
| D2 | Where the fan opens | One row directly above the KIT row, with a gap of 8. Its right edge sits on KIT's right edge, and owned items pack toward KIT. At 844x390 that is x 553..725, y 185..237. | The approved frame `phone-level-3` puts the fan tray at x 545-733, y 177-245. The dump's 377,245 is only where KitFan sat on the export board. Placed there, the fan would enter the engine's thumbstick region at 568, 667 and 705 px wide. |
| D3 | Instance names | Every mounted cell is named after its ControlPlan key (`TouchJump` and so on). The one new key is **`KitToggle`**. Fan items keep `Fan_Potion` / `Fan_Marker` / `Fan_Scan` and are never registered. | Pipeline §2.0 rule 13 allows the live name. Keeping it means `MOVEMENT_CONTROLS`, `TouchTargets`, QueueModalMatrix and the test lookups keep working. |
| D4 | The RUN "stamina ring" | The cell's own UIStroke colour: Line normally, Amber at ≤ 25 %, Coral while winded. There is no sweep. `RoundHud.Ring` is not needed in B2, and `RingSlot` stays empty. | Element sheet tile 14 A draws the ring as the cell's outline. This also removes B2's dependency on a RoundHud function that does not exist yet (risk 2 in the readers' map). |
| D5 | Geometry | One 4 + 4 grid on every touch layout, portrait included.<br>• Phone: cell 52, gap 8, edge 12.<br>• Tablet: 64, 10, 15.<br>`columnControlPlan` is deleted. `rowControlPlan` stays as the short-screen fallback. | BUILD-PLAN 14. Neither existing plan yields 52/8/12. |
| D6 | Resizing a mounted cell | Allowed, for the cluster and the fan only. The layout pass writes Size from the slot, and `Binder.scaleText` re-fits on AbsoluteSize (ShopBinder `scaleText` → `apply`). **Never re-mount.** | QueueModalMatrix fails on a changed root and on any descendant that appears or disappears. |
| D7 | KIT when nothing is owned | KIT is drawn only while at least one fan item is drawn. It stays registered either way. | The 08 owned-only rule. |
| D8 | KIT's state | The client-local player attribute **`KitFanOpen`** is the only state. ProtectionHUD reads it, writes it, and forces it to false. | One copy, settable from UIRegression and from offline tests. |
| D9 | Shield charge count on touch | Not drawn. | The A SHIELD tile has no count, and `Cell_Shield` has no Badge. |
| D10 | LIGHT on/off | Not drawn on the cell. Segments show the charge, on or off. | The template has no outline node, and the A LIGHT tile shows segments only. The beam itself shows on/off. |
| D11 | Spectating | The whole touch cluster is hidden, the SHIELD mirror included. PC keeps B1's mirror chip. | BUILD-PLAN 07: "the cluster is hidden while spectating". |
| D12 | WIDE / FOCUSED | Hold-to-focus (0.45 s) stays. `FocusModeHint` is deleted, and the MOBILE_QA 26 px / 11 px tweak goes with it. | BUILD-PLAN 07 small call: "the cell has no room, and the beam itself shows it". |
| D13 | Modal predicate | NoiseReporter and FlashlightController gate their cells on `UIDevice.ScreenOwningModalOpen()` (eight modals) instead of their private four-attribute lists. | One predicate for one cluster. UIDevice's zones already use the eight, and `UIDevice.Changed` fires (forced) on every one of them. |
| D14 | Missing template | Warn by path, draw nothing, no `Instance.new` fallback. If `Cell_Jump` is missing, Roblox's default jump is **not** suppressed. | Pipeline §5.3. A phone must always have a jump. |
| D15 | Corner radius | 12 px (the template's 0.2308), not the plan text's 10. | The template is the look. |

D7, D9, D10, D11 and D12 are small calls. List them in the handover for the owner's TOUCH QA.

---

## 2. Shared contract (all agents)

### 2.1 Keys, templates, owners, slots

| Key = mounted `Name` | `HUD_Touch` path | Owner | Gui (DisplayOrder) | Order index | Phone slot `Right, Bottom` (52x52) | Rect at 844x390 (safe 47..797 × 58..369) |
|---|---|---|---|---:|---|---|
| `TouchJump` | `TouchCluster/Cell_Jump` | B | `StaminaGui` (60) | 1 | 12, 12 | x 733..785, y 305..357 |
| `TouchRunHold` | `TouchCluster/Cell_Run` | B | `StaminaGui` | 2 | 72, 12 | 673..725, 305..357 |
| `TouchSneakHold` | `TouchCluster/Cell_Sneak` | B | `StaminaGui` | 3 | 132, 12 | 613..665, 305..357 |
| `FlashlightPower` | `TouchCluster/FlashlightPower` | D | `FlashlightPopup` (61) | 4 | 192, 12 | 553..605, 305..357 |
| `ProtectionUse` | `TouchCluster/Cell_Shield` | C | `ProtectionHUD` (1001) | 5 | 12, 72 | 733..785, 245..297 |
| `KitToggle` | `TouchCluster/Cell_Kit` | C | `ProtectionHUD` | 6 | 72, 72 | 673..725, 245..297 |
| `TouchDropGlowstick` | `TouchCluster/Cell_Glow` | B | `StaminaGui` | 7 | 132, 72 | 613..665, 245..297 |
| `TouchPOV` (developers only) | `TouchCluster/Cell_Jump`, relabelled | B | `StaminaGui` | 8 | 192, 72 | 553..605, 245..297 (the slot the template leaves empty) |
| *(not a key)* `KitFan` | `KitFan` | C | `ProtectionHUD` | — | `ControlPlan.Fan` = 72, 132, 172x52 | 553..725, 185..237 |

All three guis are inset to the safe area: default insets for `StaminaGui` and `FlashlightPopup`, `CoreUISafeInsets` for ProtectionHUD. A slot is therefore an inset from the gui's bottom-right corner, placed with:
- `AnchorPoint = (1, 1)`
- `Position = UDim2.new(1, -Right, 1, -Bottom)`
- `Size = UDim2.fromOffset(Width, Height)`

A tablet has 64-px cells, and its fan is 212x64.

### 2.2 Rules for every mounted cell (agents B, C and D)

1. **Mount once, at script load,** after a bounded wait for the bundle:
   ```lua
   local t = RS:WaitForChild("ZyntraHUD", 10); t = t and t:WaitForChild("Templates", 10)
   if t then t:WaitForChild("HUD_Touch", 10) end
   ```
   Then call `RoundHud.Mount("HUD_Touch", path, gui, {Name = key})`. Mount on every client, PC included, so the registered identity never changes.
2. **Right after mounting:**
   - set `AutoButtonColor = false`, `Selectable = false`, `Visible = false`, `Active = false`. `Selectable` must be set **before the first `UIDevice.SetInteractive`**, because `rememberedFlag` latches the first value it sees, and the template ships `true`.
   - Cache the template's own values for the state writes: face colour and alpha, stroke colour and Thickness, text colours. B1's `paintChip` uses the same pattern.
3. **Register** with `UIDevice.RegisterControlRect(key, cell)` on the root, never on a child. Never destroy or re-mount a registered root.
4. **Every layout pass** writes AnchorPoint, Position and Size from the slot. Never write TextSize: `scaleText` owns it.
5. **Visible and Active.** A cell is drawn only when its owner's availability predicate holds. `Active` is false whenever that predicate is false, whatever `Visible` says. QueueModalMatrix counts `Active` independently of visibility.
6. **What code may write.** Only these:
   - `Glyph`, `Label`, `Cooldown` and `Count` text;
   - `TextColor3`, `TextTransparency` and `BackgroundTransparency`;
   - face `BackgroundColor3`;
   - `UIStroke` Color and Thickness;
   - `Visible` on named children.

   Never move or resize a node inside a mounted root. The one exception: at mount, `KitFan`'s `Items` UIListLayout gets `HorizontalAlignment = Right` (D2).
7. **ASCII-only source.** Write glyphs as escapes: ↑ `\u{2191}`, ↓ `\u{2193}`, × `\u{D7}`. Each file wraps its B2 code in the markers named in §3-§6, and its test asserts the marked section is ASCII.
8. **Missing template.** If Mount returns nil, that key is neither drawn nor registered. Every `.Activated` or `.InputBegan` connect on a cell is nil-guarded.
9. **No tween, no pulse, no Attention fade on cells.** The A face has no idle state; cells are 100 % or hidden.

### 2.3 Face states (tokens are `Binder.Palette` names)

| State | Face | Stroke | Glyph / Icon | `Cooldown` | `Label` | `Badge` (fan items) |
|---|---|---|---|---|---|---|
| default / READY | template (Ink at 0.3) | template (Line, 2 px) | shown | hidden | template copy, Cream | shown when Count > 0; `9+` above 9 |
| EMPTY / WAIT | Tile at 0.5 | template | shown at 0.5 | hidden | text at 0.5 | hidden |
| COOLDOWN | template | template | hidden | `ceil(s)`, Cream | template | hidden |
| ACTIVE | template | RailTeal, 3 px (`Thickness * 3 / FigmaStrokeW`) | hidden | `%.1f`, RailTeal | SHIELD reads `SAFE` in RailTeal; POTION keeps `POTION` | hidden |
| REFUSED (`CAPTION_SECONDS` = 2 s) | — | Coral | — | — | — | — |
| SNEAK engaged | template | RailTeal | RailTeal | — | RailTeal | — |
| RUN, sprint toggled on | template | (stamina, next row) | Amber | — | Amber | — |
| RUN stamina | — | Coral while `exhausted`; else Amber at `stamina / staminaMax() <= 0.25`; else template | — | — | — | — |
| KIT closed | template | template | `+` | — | `KIT` | — |
| KIT open | RailTeal at 0 | template | `\u{D7}`, Ink | — | Ink | — |
| LIGHT | see §6 | | | | | |

The two RUN rows combine: Coral wins, and a sprinting player at low stamina gets Amber text inside an Amber stroke.

### 2.4 Attributes and Layout fields

| Name | Where | Written by | Read by | Meaning |
|---|---|---|---|---|
| `KitFanOpen` | LocalPlayer attribute, client-local, boolean | ProtectionHUD only | UIDevice (layout input), UIRegression KitFanMatrix, B4's pill (forced collapsed, per the approved frame) | The fan is drawn. ProtectionHUD writes `false` the moment the fan cannot be open. Writes only on change. |
| `SneakEngaged` | attribute on the `TouchSneakHold` cell | NoiseReporter | anyone | as today |
| `UIDeviceControlKey` | each registered root | UIDevice | QueueModalMatrix | the key |
| `Layout().ControlPlan.Fan` | `{Right, Bottom, Width, Height}` | UIDevice | ProtectionHUD | the fan slot |
| `Layout().KitFan` | `{Left, Top, Right, Bottom}`, absolute | UIDevice | TopRightPanel, UIRegression | the fan rect, always computed |
| `Layout().KitFanOpen` | boolean | UIDevice | TopRightPanel | a copy of the attribute at compute time |

### 2.5 MOBILE_QA_20261008 changes inside B2 files

These belong to another session and must be preserved:

| File | Change (find it by…) | B2 action |
|---|---|---|
| UIDevice | `SCREEN_OWNING_MODALS` gained `AchievementsOpen`, `HelpPanelOpen` | **keep**; D13 now routes NoiseReporter and FlashlightController through it |
| NoiseReporter | the `TOUCH_JUMP_GROUNDED_20261008` `do` block | **keep the body verbatim**. The `do` may become `if touchJumpButton then` (nil guard) |
| NoiseReporter | the GLOW gate in `updateRoundState`: `usable and not inPreview() and ... Level6PlaygroundPreview ~= true` | **keep verbatim** on the GLOW cell |
| NoiseReporter | `Level6PlaygroundPreview` in `crouchAllowed` and in the noise loop | untouched |
| ProtectionHUD | `covered()`: `LevelOneGuideObjectivesOpen` on touch with `TopBand.Height < 150`, and `Level4CardOpen`; both are in the refresh listener list | **keep**; they now hide SHIELD, KIT and the fan |
| ProtectionHUD | touch `TextSize = slot.Width >= 56 and 12 or 10` | **deleted** with the squares it sized |
| ProtectionHUD | the `DETECTOR_BIG_SCREEN_20261008` block in `computeStates` | **keep**; its `Short` (`SCAN` / `HIDE` / `SHOW`) becomes `Fan_Scan/Label` |
| FlashlightController | `FocusModeHint` at 26 px / 11 px | **deleted** (D12). Say so in the handover. |

---

## 3. Agent A · UIDevice (`ReplicatedStorage/UIDevice.ModuleScript.lua`)

Tag new comments `GRID_CONTROL_PLAN_20261008`.

**Remove**
- `columnControlPlan` (the whole hand-written slot table) and its call in `computeLayout`.
- The "nine keys" / `EQUIPMENT_SLOTS_20260916` prose around `CONTROL_KEYS_RIGHT_FIRST` and `rowControlPlan`. Rewrite it to say eight.

**Replace**
- **The key list.**
  ```lua
  CONTROL_KEYS_RIGHT_FIRST = {"TouchJump", "TouchRunHold", "TouchSneakHold", "FlashlightPower",
      "ProtectionUse", "KitToggle", "TouchDropGlowstick", "TouchPOV"}
  ```
  `SpeedPotionUse`, `RouteMarkerPlace` and `EntityDetectorScan` leave it: they are fan items, transient and never reserved.
- **The slot loop.** Lift `rowControlPlan`'s slot loop into one helper, `rankedSlots(perRank, cell, gap, edge, textSize)`. It uses the same arithmetic: column `(i-1) % perRank`, rank `floor((i-1) / perRank)`, `Right = edge + column*(cell+gap)`, `Bottom = edge + rank*(cell+gap)`. `rowControlPlan` calls it, and is otherwise unchanged.
- **The grid.** New `gridControlPlan(tablet)` returns `{Mode = "grid", Edge, Gap, Cell, Order = CONTROL_KEYS_RIGHT_FIRST, Slots = rankedSlots(4, cell, gap, edge, 12)}`:
  - phone: cell 52, gap 8, edge 12;
  - tablet: cell 64, gap 10, edge 15.

  On phone this reproduces §2.1 to the pixel.
- **In `computeLayout`.** `local plan = gridControlPlan(tabletControls)`. The short-screen fallback is unchanged: landscape touch, headroom < `MINIMUM_USABLE_HEIGHT`, a row that fits, and a row that buys the headroom. After the plan is chosen, add the fan slot:
  ```lua
  local kit = plan.Slots.KitToggle
  plan.Fan = {Right = kit.Right, Bottom = kit.Bottom + kit.Height + plan.Gap,
      Width = math.round(172 * kit.Width / 52), Height = kit.Height}
  ```
- **Layout return.** Add:
  - `KitFan`: `plan.Fan` converted through the safe rect exactly as `planZone` converts a slot (`Right = safe.Right - Fan.Right`, `Bottom = safe.Bottom - Fan.Bottom`, and so on);
  - `KitFanOpen = Players.LocalPlayer and Players.LocalPlayer:GetAttribute("KitFanOpen") == true`.

  `KitFan` does **not** go into `Zones`: Zones are movement zones, and `OverlapsMovementZone` stays Thumbstick / Controls / Jump.
- **`TopRightPanel`, touch branch only.** Inside `build`:
  ```lua
  if info.KitFanOpen and left < info.KitFan.Right and right > info.KitFan.Left then
      limit = math.min(limit, info.KitFan.Top - gutterBelow)
  end
  ```
  Every objective readout already routes through this function. On 844x390, a Level 1 panel that is allowed to reach y 229 would otherwise sit under the fan's 185..237.
- **The signal `do` block.** Add:
  ```lua
  if Players.LocalPlayer then
      Players.LocalPlayer:GetAttributeChangedSignal("KitFanOpen"):Connect(function() refresh(true) end)
  end
  ```
  This uses the same forced refresh as the modal flags.

**Keep**
- The `ControlPlan` shape (`Mode`, `Edge`, `Gap`, `Cell`, `Order`, `Slots{Right, Bottom, Width, Height}`), which the stale-union guard reads.
- `MINIMUM_TOUCH_TARGET` 44, `planZone` (still the union of `Order`), the measured branch, the zero-area-under-modal rules, the zones, `SuppressDefaultJump`, `SetInteractive`, and the registry.
- The slicing anchors other tests depend on, **byte for byte**:
  - `function UIDevice.IsGamepadOnly()`
  - the `-- 3. Layout` section header
  - `local SCREEN_OWNING_MODALS = {`, followed later by a `\n-- ------` line
  - `` -- Run `callback` whenever ``

**Placement guarantees** (assert these in the test):
- every slot is ≥ 44 in both axes;
- in landscape, `Controls.Left ≥ display.Left + 0.4·W + THUMBSTICK_CLEARANCE`. Assert the raw 40 % line, because `Zones.Thumbstick.Right` is clipped to `Controls.Left` by construction, which makes "clear of Zones.Thumbstick" a tautology;
- all slots, the fan included, lie inside Safe;
- the fan's bottom is the KIT row's top minus `Gap`.

**Test: new `tools/tests/test_touch_control_plan.py`.**

Reuse, by import, `ENGINE`, `CONTEXT`, `BOOTS`, `wrap` and `UIDEVICE` from `test_equipment_hud.py`, plus `HARNESS` from `test_round_hud`. Agent C must not rename them. Checks:
1. `Order` is exactly the eight keys, in D1 order. This is the "new key order" check BUILD-PLAN §5 put in `test_controller_input.py`; it lives here because the order is UIDevice's.
2. **Phone inset values.**
   - The slots are exactly the §2.1 inset values, and Fan is `72, 132, 172x52`.
   - Rects relative to Safe: JUMP is `Safe.Right-64 .. Safe.Right-12` by `Safe.Bottom-64 .. Safe.Bottom-12`.
   - Run this at 844x390 and 812x375.
3. **Tablet 1024x768:** cell 64, gap 10, edge 15, Fan 212x64.
4. **Every fixture** (705x338, 568x320, 667x375, 812x375, 844x390, 956x440, 1024x768, 375x812): all eight slots are ≥ 44, there are no overlaps, everything is inside Safe, and the 40 % line holds in landscape.
5. **`Layout().KitFan`:**
   - it is inside Safe;
   - `OverlapsMovementZone(KitFan)` is nil (its bottom equals `Controls.Top`, which counts as touching, not overlapping);
   - it is clear of `Zones.Jump`;
   - it is left of nothing in the thumbstick region.
6. **568x320 keeps the grid** with objective headroom ≥ 56. The readers measured 136; re-measure.
   - Then find one landscape fixture whose grid headroom is < 56 and assert that `Mode == "row"` seats all eight at ≥ 44, right of the 40 % line.
   - If no realistic size triggers the row, say so in the test and assert that the grid stands on the shortest fixture.
7. **`TopRightPanel(240, 300)` on 844x390:**
   - `KitFanOpen = true`: the panel bottom is ≤ `KitFan.Top - 8`, and the attribute change fired `Changed`;
   - false: the bottom is back to `Controls.Top - 8`.
8. A pointer layout still publishes `ControlPlan` (grid), so PC stays untouched.
9. The four anchor strings above exist.

---

## 4. Agent B · NoiseReporter (`StarterPlayer/StarterPlayerScripts/NoiseReporter.LocalScript.lua`)

Wrap the cell code in `-- == B2 touch cells (14 A; owner, 2026-10-08) ==` … `-- == end B2 touch cells ==`. Tag comments `HUD_B2_TOUCH`.

**Remove**
- `makeTouchButton` and the five `makeTouchButton(...)` creations, with them the `runStroke`, `sneakStroke` and `povStroke` locals and the literal `»` / `↑` strings.
- `showRunEnabled` and its three call sites:
  - RUN `Activated`;
  - `CharacterAdded` #2;
  - the round→lobby latch in `updateRoundState`.

  The toggle writes (`touchSprintToggled`, `touchSprintHeld`) stay where they are.
- In `applyTouchControlLayout`, `if plan.Mode == "column" then sneakBottom += lift end` (there is no column now).
- `placeTouchControl`'s `TextSize` write.

**Mount** (§2.1, §2.2)
- Require `RoundHud` and `ZyntraShopUI.ShopBinder` (for `Palette`, `find` and `text`) at the top of the section.
- Assign the mounted cells to the **existing variable names**: `touchRunButton`, `touchJumpButton`, `touchSneakButton`, `touchGlowButton`, `touchPOVButton`. The `Activated` handlers and the grounded-jump block then keep working unchanged.
- Glyph writes at mount:
  - `Cell_Jump/Glyph = "\u{2191}"`;
  - `Cell_Sneak/Glyph = "\u{2193}"`.

  `»` (RUN) and `*` (GLOW) are template copy and are never written.
- POV mounts `TouchCluster/Cell_Jump` as `TouchPOV`. `refreshPOVButton` writes `Label = "POV"` and `Glyph = firstPerson and "3RD" or "1ST"`, with no colour state.
- The existing `RegisterControlRect` loop stays as it is, after all five exist. It skips nil cells.

**Placement.** `placeTouchControl(button, slot, bottomOverride)` writes AnchorPoint `(1, 1)`, Position and Size. The lobby RUN lift (`BottomOffsetFor(gui, Zones.Jump.Top) + plan.Gap`) is kept as it is: only RUN is drawn in the lobby, so lifting it is harmless.

**States** (§2.3)
- **`showSneakEngaged(engaged)`** keeps its name, its forward declaration and every caller. Its body sets `touchSneakToggled`, paints SNEAK (stroke, Glyph and Label in RailTeal, or the cached template values), and writes the `SneakEngaged` attribute on the cell. Because the off look is the template, the creation look and the reset look are now the same.
- **`paintRun()`** is new, inside the markers, and is the only writer of RUN's look:
  - it reads `touchSprintToggled`, `exhausted`, `stamina` and `staminaMax()`;
  - it builds a key from them and writes only when the key changes;
  - it is connected by its **own** `RunService.Heartbeat:Connect(paintRun)`.

  Do **not** call it inside the main Heartbeat: `test_controller_input` slices that function from `RunService.Heartbeat:Connect(function(dt)` to `\tif not inRound() then`, and the lobby and spectating branches return early anyway.

  Because the look is recomputed from state every frame, "the RUN style survives a respawn" holds by construction.

**Gating** (`updateRoundState` and its helpers)
- `modalOwnsScreen()` returns `UIDevice.ScreenOwningModalOpen()` (D13).
- `controlsAvailable()` becomes `touchControls() and movementAvailable() and not UIDevice.ScreenOwningModalOpen()`. `movementAvailable()` itself, which drives gameplay, is unchanged.
- `UIDevice.SuppressDefaultJump(touchControls() and active and touchJumpButton ~= nil)` (D14).
- The `SetInteractive` lines stay, one per cell, each nil-guarded. The GLOW line is the MOBILE_QA gate, kept verbatim.

**Keep**
- `StaminaGui`: its name, `DisplayOrder` 60, `ResetOnSpawn = false`, and `gui.Enabled = true`.
- The stamina bar, `staBg` / `staFill` and `applyStaminaLayout`. These are B3's: during B2 the touch corridor bar still draws.
- `sprintRequested()` and every keyboard and gamepad input path.
- The attribute listener list.
- `RoundEntryControlsReady = true` stays the **last line** of the script.

**Test: `tools/tests/test_controller_input.py`**
1. The four existing NoiseReporter slices and the two UIDevice slices pass unchanged.
2. A new slice of the B2 section's paint functions, with the cells stubbed as tables holding `Glyph`, `Label`, `UIStroke` and their cached base values. Check:
   - **`paintRun` truth table:**
     - `(off, 0.5, false)` gives a Line stroke and Cream text;
     - toggle on gives Amber text;
     - a fraction of 0.25 gives an Amber stroke;
     - `exhausted` gives a Coral stroke;
     - a repeat call writes nothing;
     - with a stamina multiplier of 2, Amber holds between 12.5 % (where exhaustion clears) and 25 %.
   - `showSneakEngaged(true/false)` sets the colours and the attribute.
3. The marked section is ASCII-only.
4. Static checks on the source:
   - there is no `makeTouchButton`, no `showRunEnabled(` and no `"column"`;
   - `ScreenOwningModalOpen` appears in `modalOwnsScreen` and `controlsAvailable`;
   - `SuppressDefaultJump(` carries the `touchJumpButton ~= nil` guard.

`test_speed_potion.py` already fails at HEAD (its harness has no `inPreview` stub). It is B3's to fix; leave it.

---

## 5. Agent C · ProtectionHUD, touch path (`StarterPlayer/StarterPlayerScripts/ProtectionHUD.LocalScript.lua`)

Wrap the mount and the paint helpers in `-- == B2 touch kit (14 A + KIT fan C; owner, 2026-10-08) ==` … `-- == end B2 touch kit ==`. Tag edits elsewhere (`refresh`, `applyLayout`, wiring) `HUD_B2_TOUCH`.

**Remove**
- `makeRow`'s `Instance.new("TextButton")` and its `UIStyle.button` styling. `ROWS` entries become `{Key, Chip, Keyboard, Gamepad, Fan}`, where `Fan` is `nil`, `"Fan_Potion"`, `"Fan_Marker"` or `"Fan_Scan"`.
- `TOUCH_CHIP`, `DIMMED` if nothing else uses it, `row.Button`, `row.Slotted`, and the line `state.Visible = state.Visible and row.Slotted`.
- The square text writes (`Short .. "\n" .. ShortDetail`), the touch TextSize 12/10, and the PC-branch styling of the squares in `applyLayout`.
- Registration of `SpeedPotionUse`, `RouteMarkerPlace` and `EntityDetectorScan`.
- The touch half of the spectate mirror (D11). On touch the mirror draws nothing, but the PC chip mirror stays exactly as B1 left it.
- The `row.Button.Activated` loop. Cell and fan connects replace it.

**Mount** (§2.1, §2.2), into `gui`, once at load. Keep the handles in **one table** to spare locals.
- `Cell_Shield` as `ProtectionUse`.
- `Cell_Kit` as `KitToggle`.
- `KitFan` as `KitFan`. Then:
  - its items are `Binder.find(fan, "Fan_Potion" / "Fan_Marker" / "Fan_Scan")` for rows 2, 3 and 4;
  - set `Items` UIListLayout `HorizontalAlignment = Right`;
  - items get `AutoButtonColor = false` and `Selectable = false`;
  - the whole fan starts `Visible = false`.

  The template's visible samples (`Cooldown "12"`, `Badge "2"`) must never show before the first paint.

**Placement** (`applyLayout`, when `control = touch and not mirroring`)
- The shield comes from `Slots.ProtectionUse`, and **the ≥ 44 assert stays**.
- The kit comes from `Slots.KitToggle`.
- The fan comes from `ControlPlan.Fan`.
- All three use the §2.1 idiom and are resized every pass (D6).
- On the `control` flip, register `ProtectionUse` → shield and `KitToggle` → kit, and nothing else. Unregister both on the flip back and on `script.Destroying`.

**States** (`refresh`, touch, not mirroring). `computeStates()` is untouched; only its consumers change.
- **Shield:**
  - `Visible = states[1].Visible`, `Active = states[1].Enabled`;
  - paint from `states[1].Look`, plus REFUSED while `refusedChip == 1` and the caption is live;
  - no count (D9).
- **Kit:**
  - `fanAny` is true when any of `states[2..4].Visible` is;
  - `kit.Visible = states.Available and fanAny`, and `Active` the same;
  - closed or open face (§2.3).
- **Open:**
  - `open = KitFanOpen and states.Available and fanAny`;
  - if the attribute is true and `open` is not, write `false`. This covers the modal, `covered()`, death, spectate, PARTY DOWN, round end, the last item going, and a flip to PC.
- **Fan:**
  - `fan.Visible = open`;
  - item `i`: `Visible = open and states[i].Visible`, `Active = open and states[i].Enabled`;
  - paint from `states[i].Look`;
  - Badge/Count = `Look.Count` (stored, so `MARKER` reads its stored count like the PC chip);
  - `Fan_Scan/Label = states[4].Short` (`SCAN`, `HIDE` or `SHOW`).
- **PC** (`touch` false) **or mirroring:** every touch node has `Visible = false` and `Active = false`, and `KitFanOpen` is false.

**Input.** Each connect accepts Touch or MouseButton1, as the rows did, so ForceTouchUI mouse testing works.
- `kit.Activated`: if `kit.Active`, write `KitFanOpen = not open`, then `refresh()`.
- Fan item `i`, `Activated`: `press(i)`, then `KitFanOpen = false`. A use closes the fan, even a refused one.
- `shield.Activated`: `press(1)`.
- Add `"KitFanOpen"` to the attribute refresh list.
- On `script.Destroying`, write `KitFanOpen = false`.

**Keep**
- Every `computeStates` predicate; `canPress`; `RATE_WINDOW`; the remotes; `REFUSALS` and the 2 s tag; the detector stow toggle.
- `KEY_ROWS` and the keyboard and pad paths.
- B1's `mountKit`, `paintChip`, `drawKit` and `placeKit`, untouched. On touch the refusal tag is still `HUD_PC/EquipmentCaption`, bottom-centre in `ModalArea`.
- The gui name and order 1001; `underRoundUI`; `covered`; `contextAvailable`; the reentry notice (B3 removes it).

**Test: `tools/tests/test_equipment_hud.py`**
- **`PLAN_TESTS`, re-baselined:**
  - `ALL_KEYS` = the eight grid keys;
  - drop the `EQUIPMENT` "behind the shield" loop, "a portrait phone still uses the column", and "equipment slots on a pointer layout";
  - keep the 44 floor, the no-overlap check and Safe containment;
  - add: `Slots.KitToggle` ≥ 44, and `ControlPlan.Fan` is present.
  - Keep the `ENGINE`, `CONTEXT`, `BOOTS`, `wrap`, `UIDEVICE` and `PLAN_EXPORT` names (agent A imports them).
- **`HUD_TESTS` touch blocks, re-baselined on the HUD_Touch dump** (`trees()` already loads it). The square captions `SHIELD\nx2`, `POTION\nx1`, `MARKER\n1/3` and `SAFE\n4.2s` become:
  - **shield cell:** READY template; EMPTY at x0 (Tile 0.5, not Active); WAIT; ACTIVE (`Cooldown "4.2"`, `Label "SAFE"`, RailTeal 3 px stroke); refused Coral stroke;
  - **fan items:** Badge counts, `9+`, potion ACTIVE / USED (EMPTY), marker stored count, SCAN COOLDOWN and `HIDE` / `SHOW`.
- **New checks:**
  - exactly `{ProtectionUse, KitToggle}` are registered on touch, and nothing on PC or while mirroring;
  - KIT is hidden with nothing owned and drawn with one item;
  - a tap opens the fan (`KitFanOpen` true, KIT face RailTeal, Glyph `\u{D7}`);
  - a second tap closes it;
  - pressing a fan item fires its action and closes the fan;
  - only owned items show;
  - `KitFanOpen` is forced false by each of: an open modal, `Level4CardOpen`, death, Spectating, `PartyDownCardOpen`, the last item going, and a flip to PC;
  - a touch spectate draws nothing;
  - the template samples (`12`, `2`) are never visible after mount;
  - the B2 section is ASCII-only.
- PC chip assertions are **unchanged**.

---

## 6. Agent D · FlashlightController, the LIGHT cell (`StarterPlayer/StarterPlayerScripts/FlashlightController.LocalScript.lua`)

Wrap the cell code in `-- == B2 LIGHT cell (14 A, owner P1; 2026-10-08) ==` … `-- == end B2 LIGHT cell ==`, after B1's `-- == end B flashlight widget ==`. **B1's widget section is not edited.** Call `widgetState`, do not change it.

**Remove**
- The `batBody` Frame, `torchScale`, and the whole torch drawing: `Silhouette`, `batBars`, `lens`, `lightRays` and the rays, and `BAT_FULL` / `BAT_EMPTY`.
- The `TouchFlashlightToggle` child button.
- `focusCaption`, `refreshFocusCaption`, and every connect to or call of them: the `ZyntraOwnsAdvancedEquipment` signal, `UIDevice.Changed`, the `FlashlightFocused` connect in `bindCharacter`, the call in the Died handler, and the Heartbeat call. This includes the MOBILE_QA 26 px tweak (D12).
- The `lens` / `lightRays` writes in `setLights` and in the Heartbeat spectating branch.
- `batBody.Visible = ...` and the bar loop at the end of the Heartbeat.

**Mount.**
- `TouchCluster/FlashlightPower` into `popupGui`, named `FlashlightPower`.
- Cache `Seg1`-`Seg5`, `Label` and the cell's `UIStroke`.
- Cache the template's lit alpha (Seg1, 0.1), its unlit alpha (Seg5, 0.85), and the stroke and label colours.
- Paint once before the first `SetInteractive`.

**Placement.** `applyFlashlightLayout` keeps its `flashlightRegistered` latch, now on the cell (key `FlashlightPower`), and places the cell from `Slots.FlashlightPower` (§2.1).

**Gate.**
- `flashlightTargetAvailable()`: replace its `ZyntraStoreOpen`, `DevPhoneOpen`, `ZyntraReentryOpen` and `QueueModalOpen` reads with `UIDevice.ScreenOwningModalOpen()` (D13). Keep `queueShadeVisible`, because the shade can lead the attribute by two frames.
- `applyFlashlightTouchTarget` calls `UIDevice.SetInteractive(cell, flashlightTargetAvailable())`. That is the **only** writer of the cell's `Visible`. It already runs on `UIDevice.Changed`, which fires on every screen-owning modal.

**Input.** Move the `touchFlashButton.InputBegan` handler to `cell.InputBegan` verbatim: Touch, or the Studio ForceTouchUI mouse; the 0.2 s debounce; the 0.45 s hold to focus with Advanced Equipment. `UIS.InputEnded` → `toggle()` is unchanged.

**Paint.** `paintLight(s)` runs in the Heartbeat, after `paintWidget`, only when the cell exists and the player is not spectating (the cell is hidden then). `local _, tone, lit, coral = widgetState(s)`:

| Case | Seg 1..lit | Seg lit+1..5 | Stroke | Label |
|---|---|---|---|---|
| lit ≥ 3 | Cream at the lit alpha | Cream at the unlit alpha | template Line | `LIGHT`, Cream |
| lit 1-2 | Amber | unlit | Line | `LOW`, Amber (the approved frame: "label turns amber LOW") |
| Empty, lit 0 | — | all unlit | **Coral** (`coral`) | `LIGHT`, Cream |
| Refused (2 s, `time() < refusedUntil`) | one Coral segment (`widgetState` returns lit 1, tone Coral) | unlit | Line | `LOW`, Coral; then back to its own case |

On and off are not drawn (D10), and WIDE / FOCUSED are not drawn (D12).

**Keep**
- `popupGui`: name `FlashlightPopup`, order 61, `Enabled = roundBody()`.
- B1's widget section, byte for byte.
- `toggle`, `REFUSED_SECONDS` / `refusedUntil`, `widgetState`.
- The F, R1, Y and R3 keys.
- `spectatevital`, the mate beams, and `updateRoundVisibility`.

**Test: `tools/tests/test_flashlight_player_control.py`**
- The HOST stubs `batBody`, `touchFlashButton`, `lens`, `lightRays`, `batBars` and `BAT_FULL` / `BAT_EMPTY` go.
- Slices keep their anchors:
  - `local BATTERY_BASE` → `-- The flashlight gui.`;
  - the widget markers;
  - `local function setLights(` → `` -- ── teammates' flashlights ``;
  - `-- drive every mate beam`;
  - `-- DevCheats owns`.
- The "until B2" block becomes:
  - **touch:** the widget is hidden, and the LIGHT cell is drawn and registered as `FlashlightPower`;
  - **flip to PC:** the cell is hidden and unregistered, and the widget is drawn.
- **New program over the HUD_Touch dump** (via `test_round_hud` helpers, extending `ctx.UIDevice` per §0):
  - segments at fractions 1, 0.6, 0.4, 0.2 and Empty (count and colour);
  - a Coral stroke only at Empty;
  - `LOW` Amber at lit 1-2;
  - a refused press: `LOW` Coral with one Coral segment for 2 s, then back;
  - the cell is hidden while spectating and under each of the eight modals, and `Active` is false then;
  - a tap toggles; a 0.45 s hold focuses (Advanced only); a second tap inside 0.2 s is ignored;
  - the B2 section is ASCII-only.
- Touch pins `touch turns it on`, `touch hold focuses` and `a short tap still toggles` stay, re-pointed at the cell.

---

## 7. Agent E · UIRegression (`ReplicatedStorage/UIRegression.ModuleScript.lua`)

The module is near Luau's local ceiling: add **no new top-level `local`**. New code goes in `Fit.*` functions.

1. **`MOVEMENT_CONTROLS`** = the eight keys: `TouchRunHold`, `TouchSneakHold`, `TouchJump`, `TouchPOV`, `TouchDropGlowstick`, `FlashlightPower`, `ProtectionUse`, `KitToggle`.
   - Drop `SpeedPotionUse` and `RouteMarkerPlace`.
   - Fan items are not listed. They must clear the movement zones like any other control, and they do by construction.
2. **QueueModalMatrix `expectedControlKeys`** = `TouchRunHold`, `TouchJump`, `TouchPOV`, `TouchDropGlowstick`, `TouchSneakHold`, `FlashlightPower`, `ProtectionUse`, `KitToggle`, `FriendBoost`.
   - Drop `SpeedPotionUse`, `RouteMarkerPlace` and `EntityDetectorScan`.
   - Rewrite the comment.
   - Root identity and descendant snapshots need no change. Cells are mounted once and never re-mounted, and cells and their children carry `Active = false` while the shade is up.
3. **ControlZoneMatrix, the modal block.** The flashlight target is `findGui("FlashlightPopup"):FindFirstChild("FlashlightPower")`: a direct child, which must be a `GuiButton`.
   - Before the queue opens: Visible and Active.
   - While the shade is open: neither.
   - After it closes: restored.

   Reword the messages ("the LIGHT cell is live"). `#tagged >= 5` and `Count == #drawn` still hold.
4. **New lane `KitFanMatrix`.** `Fit.bodyKitFanMatrix` plus `UIRegression.KitFanMatrix(token)`, run from `Fit.bodyRunAll` right after ControlZoneMatrix. It has two parts.
   - **(a) Analytic, per touch fixture** (the `Fit.Devices` touch rows plus 844x390 and 568x320, applied with `Fit.apply`):
     - `Layout().KitFan` is inside Safe;
     - `UIDevice.OverlapsMovementZone(KitFan...)` is nil;
     - it is right of the raw 40 % line in landscape;
     - each item cell (`KitFan.Height` square) is ≥ 44;
     - its bottom equals the `KitToggle` slot's top minus `Gap`.
   - **(b) Live, at the real viewport** with `ForceTouchUI` and `InRound`:
     - Borrow `ZyntraSpeedPotions = 1`, `ZyntraRouteMarkers = 1` and `ZyntraOwnsEntityDetector = true`. Save and restore workspace `RoundActive = true` and `RoundLoadingState = "ready"` **inside the lane**, never through `BORROWED_WORKSPACE_ATTRIBUTES`: QueueModalMatrix nils that whole list.
     - `KitToggle` is drawn.
     - Set `KitFanOpen = true`, which is the attribute KIT's own tap writes. Then:
       - KitFan and the three items are visible, each ≥ 44, and match `Layout().KitFan` within 1 px;
       - each `OverlapsMovementZone` is nil;
       - the KIT face is RailTeal with Glyph `×`;
       - `TopRightPanel(240, 300).Bottom ≤ KitFan.Top - 8`.
     - Set `ZyntraSpeedPotions = 0`: `Fan_Potion` hides and the other two pack toward KIT.
     - Open `QueueHostShade` through production's choke point: `KitFanOpen` goes false, and the fan and KIT are not drawn and not Active.
     - Close the shade: the fan stays closed.
     - Restore everything; the residue must be empty.
5. **Borrow lists.**
   - Add `ZyntraSpeedPotions`, `ZyntraRouteMarkers` and `ZyntraOwnsEntityDetector` to `BORROWED_PLAYER_ATTRIBUTES`.
   - Add `KitFanOpen` to `DERIVED_PLAYER_ATTRIBUTES`: ProtectionHUD derives it and forces it false.
6. **Unchanged:**
   - the `touch-movement-cluster` scenario (the names are kept);
   - `REQUIRED_GUIS` (`StaminaGui`, `FlashlightPopup`);
   - `BORROWED_GUIS`. Its stale `"NoiseGui"` is harmless; leave it;
   - the objective-corner check against `Zones.Controls.Top`.

UIRegression has no offline test. It is verified in Studio (§9).

---

## 8. Studio half (a local session on the owner's PC only)

1. Run `03_hud_check` first. `ZyntraHUD.Templates.HUD_Touch` must contain `TouchCluster/Cell_Glow`, not `Cell`: re-run `01_hud_templates` after any re-import.
2. Before pushing:
   - run `git status` for foreign untracked files;
   - run `python tools/pull_source_from_studio.py --audit`;
   - take the Studio lock `_local/studio-lock.json`.
3. Push the five scripts with `python tools/push_repo_to_studio.py --studio-name "(UPDATE) BACKROOMS: STAY QUIET"`.
   - There are no new scripts.
   - Merge any CONFLICT; never use `--overwrite-conflicts`. MOBILE_QA and other sessions touch these files.
4. Run the compile probe. Then run the offline suites:
   - `test_touch_control_plan`, `test_controller_input`, `test_equipment_hud`, `test_flashlight_player_control`;
   - plus `test_round_hud`, `test_lucky_wheel_client` and `test_zyntra_store_compact`, which slice or name these files.

   Set `LUAU_BIN` to luau 0.737.

---

## 9. B2 QA checklist → checks

TOUCH means `ForceTouchUI = true` plus `UIRegressionViewport` 844x390. Start rounds with the playtest recipe, and press B to hide developer ESP first.

| # | QA item (BUILD-PLAN §4 B2, plus what this brief adds) | Offline | Studio |
|---|---|---|---|
| 0 | Templates staged; the cell outline is visible. The dump does not record `StrokeSizingMode`; a 0.038 Thickness that is not ScaledSize draws nothing. | — | `03_hud_check`; look at one cell at 52 and at 64 px |
| 1 | Lower row JUMP, RUN, SNEAK, LIGHT and upper row GLOW, KIT, SHIELD (read left to right). Every cell ≥ 44, none in the thumbstick region. | `test_touch_control_plan` 1-4 | TOUCH screenshot against `phone-level-1.png`; ControlZoneMatrix; TouchTargetMatrix |
| 2 | LIGHT is the only battery on screen (P1). Amber at ≤ 2 segments, a Coral outline at 0, a refused press reads LOW for 2 s. | `test_flashlight_player_control` | TOUCH in a round: drain to empty, press at < 5 % |
| 3 | KIT fans POTION, MARKER and SCAN (owned only) above the KIT row, and closes on a second tap or on use. Never in the thumbstick region. | `test_equipment_hud` (fan), `test_touch_control_plan` 5 | KitFanMatrix; TOUCH screenshot against `phone-level-3.png` |
| 4 | The RUN ring turns Amber at ≤ 25 % and Coral when winded; SNEAK shows as engaged. | `test_controller_input` (paint truth table) | TOUCH in a round: sprint to empty, toggle SNEAK |
| 5 | The RUN style survives a respawn. | structural (single writer `paintRun`); `test_controller_input` | TOUCH: die, then re-entry via `ServerStorage.ZyntraReentry:Invoke(player)`, then compare RUN |
| 6 | Short screen (568x320): the cells are seated (grid; the row fallback where the grid leaves < 56). | `test_touch_control_plan` 6 | `UIRegressionViewport` 568x320, 667x375, 705x338 |
| 7 | Device Simulator, iPhone landscape: insets respected. | — | Device Simulator once, real insets |
| 8 | PC and PAD unchanged. | PC widget and chip assertions untouched in both suites | PC 1920x1080 and PAD pass of B1's checklist |
| 9 | ControlZoneMatrix, QueueModalMatrix and KitFanMatrix are green. | — | UIRegression `RunAll` |
| 10 | The cluster stands down under all eight screen-owning modals, including AchievementsOpen and HelpPanelOpen. | `test_flashlight_player_control`, `test_equipment_hud` | QueueModalMatrix; open the store and the dev phone in a round |
| 11 | Objective readouts on Levels 1-4 use the new headroom and never sit under the open fan. | `test_touch_control_plan` 7 | TOUCH, each level: open KIT and look at the objective panel. Level 4's `Zones.Controls.Left` clamp moves (545 at 844) |
| 12 | Lobby: only RUN is drawn, lifted clear of Roblox's jump; Roblox's jump still works. | — | TOUCH in the lobby |
| 13 | Missing `HUD_Touch`: warnings by path, Roblox's jump is not suppressed, and the script still reaches `RoundEntryControlsReady`. | each agent's own test, with the bundle skipped | — |

---

## 10. Left for later, and flags

- **B3.** The approved phone frames draw a 160-wide stamina bar at x 350-510, y 352, beside the RUN stroke. BUILD-PLAN 10 hides the bar on touch. B3 decides. B2 leaves the corridor bar as it is, and leaves `MoveNoise` to B3.
- **B4.** The approved frame shows the pill "forced collapsed while the fan is open". The pill reads `KitFanOpen`. `TopRightPanel` already shortens it.
- **`RoundHud.Ring`.** RoundHud's header says Ring arrives in B3-B5, and the pipeline says B1. B2 does not need it (D4). B6's leave-hold ring does.
- **ProtectionHUD order 1001** draws KIT and the fan above `JumpscareGui` (1000) during a Level 1 capture. That order is the shield's requirement; the fan riding along is accepted.
- **`covered()`** (`Level4CardOpen`, the Level 1 brief on short screens) hides only ProtectionHUD's cells. NoiseReporter's and FlashlightController's cells (60 and 61) still draw over the Level 4 card until B7 moves `Level4RoundGui` to 60. Decide in B7.
- **Test location.** `test_hud_templates.py` still lives in `artifacts/hud-final-20261008/tests/`, not in `tools/tests/` as plan §3.6 says.
- **Stray file.** An empty file named `700'` sits in `artifacts/hud-final-20261008/` (created 19:17, not by B2).

---

## Critic findings (2026-10-08)

This is a read-only review done at about 19:55, while B1 was still editing the tree. It checks the brief against:
- BUILD-PLAN 07, 08, 10, 14 and §4 B2;
- the pipeline's §2.12 and §5;
- OWNER-PICKS and element sheet tile 14;
- the HUD_Touch dump;
- the approved phone frames, with pixels sampled;
- the live scripts.

Offline suites on that tree:
- green: `test_controller_input` (102), `test_equipment_hud` (414), `test_flashlight_player_control` (557 + 226), `test_round_hud` (164), `test_lucky_wheel_client` (657);
- red: `test_zyntra_store_compact` (C11).

The line numbers below come from that tree and are moving.

### Blocking

**C1. Agent A can land neither while B1 is open nor with the imports §3 gives it.**
- `test_equipment_hud.py`'s PLAN_TESTS run the real UIDevice. A's key list breaks them at once:
  - `ALL_KEYS` holds `SpeedPotionUse` and `RouteMarkerPlace`;
  - "a portrait phone still uses the column" fails;
  - "the equipment slots are present on every layout" fails.

  B1 is still verifying with that suite (§0 gate), so A landing early turns B1's handover red for a reason outside B1.
- `slotRect`, `overlaps`, `layoutAt`, `MATRIX` and `touchLayouts` are defined inside `PLAN_TESTS`, the block C rewrites, not in `ENGINE` or `CONTEXT`. §3's import list cannot reach them.
- **Fix:**
  - Put A behind the B1 gate too.
  - A copies those five helpers into `test_touch_control_plan.py`. Alternatively, C first hoists them into a named `PLAN_HELPERS` constant and A imports that.
  - Add to §0: after A lands, `test_equipment_hud` is red until C lands, and A does not edit it.

**C2. A single marked block per file breaks Lua scoping in NoiseReporter and FlashlightController.**
- **NoiseReporter.** The cells must mount at the old `makeTouchButton` site, before the `RegisterControlRect` loop and the `Activated` connects. But `local touchSprintToggled` is declared later (old line 577).
  - A `paintRun` defined in the mount block therefore reads a global `touchSprintToggled`, which is always nil, so RUN never shows the toggle.
  - An offline slice that stubs the local will not catch this.
  - **Fix:** move `local touchSprintToggled = false` up beside `touchSprintHeld` (line 38, outside every `test_controller_input` slice). One block then works.
- **FlashlightController.** §6 places the block right after B1's widget section (about line 306).
  - The moved `InputBegan` handler calls `toggle` and `toggleFocus`, which are locals declared at about lines 619 and 634. From inside that block they are nil globals, and every tap throws.
  - The cell itself must exist before `applyFlashlightLayout()` runs at load (about line 461).
  - **Fix:** allow two marked blocks:
    - `-- == B2 LIGHT cell (mount) ==` after B1's widget;
    - `-- == B2 LIGHT cell (input/paint) ==` where `touchFlashButton.InputBegan` is today.

    The ASCII test covers both.

**C3. The template wait and the RoundHud require can stall round entry.**
- NoiseReporter's last line sets `RoundEntryControlsReady`, and Round Entry Client sends `entryready` only after it.
  - §2.2 rule 1 can yield 10 to 20 s when part of the bundle is missing.
  - "Require RoundHud", if written as `WaitForChild` (ProtectionHUD's B1 pattern), yields forever without RoundHud. RoundHud has no manifest item yet: it is not in Studio.
- In FLC the same wait delays the F, R1 and Heartbeat wiring.
- **Fix, in both scripts:**
  ```lua
  if not game:IsLoaded() then game.Loaded:Wait() end
  ```
  then `FindFirstChild` chains for:
  - `ZyntraHUD.Templates.HUD_Touch`;
  - `RoundHud`;
  - `ZyntraShopUI.ShopBinder`.

  The templates are place data, so they exist after initial replication. A nil anywhere takes the D14 path. This is the pattern FLC's B1 widget already uses ("RoundHud is looked up, never waited for").
- QA 13 adds: with the bundle removed, `RoundEntryControlsReady` is true within 1 s of `game.Loaded`.

**C4. §8 cannot push as written.**
- `push_repo_to_studio.py` acts only on `pending-studio-push` entries, and all five scripts are `synced`. Step 3 has to be:
  1. `python tools/record_pending_push.py`
  2. `push_repo_to_studio.py --audit --studio-name ...`
  3. the push itself.
- **Missing precondition.** B1's new `ReplicatedStorage.RoundHud` must be installed through `install_new_scripts.py` (manifest item present), and B1's FlashlightController and ProtectionHUD push must have landed. Otherwise:
  - ProtectionHUD hangs on `WaitForChild("RoundHud")`;
  - NoiseReporter, under C3, mounts nothing.

### Wrong against the dump or the approved frames

**C5. `Cell_Shield/Glyph` is a Frame, and the touch cells have no `Face`.**
- In the dump, `Cell_Shield/Glyph` is a Frame rotated -45 (REQUIRED lists it without `:T`).
  - §2.3's "Glyph shown at 0.5" and any write to `TextTransparency`, `TextColor3` or `Text = "\u{25C6}"` would throw on it.
  - ProtectionHUD's `refresh` runs every RenderStepped, so one throw kills SHIELD and KIT.
- The cells are flat: the root TextButton carries the UICorner and the UIStroke, and there is no `Face` child. The HUD_PC chips that B1's `paintChip` paints do have one, so copying `paintChip` paints nil.
- Fan items carry an `Icon` Frame whose child Frames do the drawing (Body/Neck/Cap, Pole/Flag, Items/Step1-3), and no Glyph. Frame transparency does not cascade.
- `Cell_Shield/Cooldown` ships a visible sample, `12`, drawn over the diamond.
- **Fix (§5):**
  - paint the root as the face;
  - dim the shield glyph through `BackgroundTransparency`;
  - dim a fan icon by caching every descendant Frame's `BackgroundTransparency`, as B1's `IconParts` does;
  - hide `Cell_Shield/Cooldown` at mount, and add it to the "samples never visible" check;
  - §2.2 rule 6 reads "Glyph (a TextLabel; a Frame on SHIELD)".

**C6. RUN's look contradicts both approved phone frames.**
- Sampled pixels:
  - `phone-level-1` (stamina DRAINING, bar still Cream at about 60 %): RUN stroke 148,105,30, text 215,210,194;
  - `phone-level-3` (stamina LOW): stroke 143,99,26, text 213,207,193;
  - every other cell's edge is Line 38,49,52.
- So the frames draw an Amber ring while the player runs, with Cream text. Neither shows the brief's Amber text on toggle, or an Amber stroke only at ≤ 25 %.
- **Fix (§2.3 and B's truth table).** Glyph and Label never change colour. The stroke is:
  - Coral while `exhausted`;
  - else Amber while `touchSprintToggled` or `stamina / staminaMax() <= 0.25`;
  - else the template.

  This matches both frames and BUILD-PLAN 14's ≤ 25 % rule, still shows the toggle while the player stands still, and leaves `paintRun` writing one property.

**C7. The KIT-open stroke is RailTeal.** In `phone-level-3` the KIT cell's edge samples 68,221,196, not Line. **Fix (§2.3):** in the KIT-open state the stroke is RailTeal.

**C8. Stroke thickness fights D6.**
- `Binder.scaleText` runs `apply` on every AbsoluteSize change. It rewrites any UIStroke that is not ScaledSize to `FigmaStrokeW * k`.
- With D6 resizing every pass:
  - the next resize clobbers the ACTIVE 3 px stroke and a REFUSED write;
  - a Thickness cached at mount goes stale at 64 px. B1's `paintChip` gets away with caching because PC chips never resize.
- QA 0 has it backwards: scaleText rescues a FixedSize stroke, and this fight is the real hazard.
- The dump does not record `StrokeSizingMode`. The values 0.038462 (2/52) and 0.055556 (1/18) say ScaledSize.
- **Fix:**
  - `02_dump_hud` records `StrokeSizingMode`, and `03_hud_check` asserts ScaledSize on every HUD_Touch cell stroke.
  - The paint helpers use `base * (active and 1.5 or 1)` from a cached base only when the stroke is ScaledSize, and `FigmaStrokeW * cell.AbsoluteSize.X / 52` otherwise.
  - The change keys in `paintRun` and in ProtectionHUD include `cell.AbsoluteSize.X`.

**C9. The open fan sits inside ModalArea.**
- With the grid at 844x390, `ModalArea` resolves to the row-lane candidate, x 346..785 × y 66..229. That contains the open fan's 553..725 × 185..229.
- ProtectionHUD's own touch messages land on the fan:
  - the refusal tag (`EquipmentCaption` at ModalArea's bottom centre, about x 565, bottom 229);
  - the reentry notice (bottom 197, up to 360 wide).
- **Fix (C).** While `KitFanOpen`, place the tag and the notice with their bottom at `min(area.Bottom, Layout().KitFan.Top - 8)`.
- **Fix (E).** KitFanMatrix asserts that the drawn tag and the fan do not intersect.
- Level 2's announcement also uses ModalArea. Put it on the owner's TOUCH QA list: the fan is transient and closes on use.

**C10. The row fallback is effectively unreachable, and §3's 40 % assertion is wrong for it.**
- The grid leaves ≥ 56 px of objective headroom whenever the safe area is at least about 204 px tall.
  - Measured: 568x320 gives 136, 667x375 gives 191, 705x338 gives 154, and 640x240 with a 36 px topbar gives 56.
  - So the row appears only on screens no fixture or device has, and test 6 never runs `rankedSlots` or `plan.Fan` in row mode.
- In row mode the slots are sized to the 40 % line, and `planZone` then subtracts CONTROL_CUSHION. So `Controls.Left ≥ 0.4·W + 8` fails by construction: at 812x220 with a 36 px topbar, the slots' left edge is 334 against a line at 332.8, but `Controls.Left` is 326.
- **Fix (A's test 6).** Add a synthetic 812x220 row with a stated 36 px topbar:
  - grid headroom 36, so the one-rank row is chosen: cell 50, headroom 78;
  - `Fan = {Right 312, Bottom 80, 165x50}`, which is absolute x 335..500, y 54..104.

  Assert that:
  - every slot rect and the fan's left edge are ≥ 0.4·W + 8;
  - the fan is inside Safe;
  - `Controls.Left ≥ 0.4·W + 8 - CONTROL_CUSHION` holds wherever `Controls.Left` is asserted.

  Either test it this way or delete `rowControlPlan` (an owner call). Do not ship it untested.

### Collisions and unowned work

**C11. `test_zyntra_store_compact.py` is already red.**
- It fails with `the set is exactly those six: expected 6, got 8`: MOBILE_QA added `AchievementsOpen` and `HelpPanelOpen`.
- §8.4 runs it, and no B2 agent owns it.
- **Fix:** record it as pre-existing in the handover. The orchestrator, not agents A-E, raises the expectation to 8 and adds the two names to its loop.

**C12. Unowned items.**
- **Copy lint.** `test_hud_copy_rules.py` (BUILD-PLAN §5: new in B1, extended per batch) is not in the tree. B2's new strings (POV, 1ST/3RD, LOW, SAFE, 9+, HIDE/SHOW) have no lint owner. If B1 lands the lint, the orchestrator extends it after E.
- **Notes.** The new contract has no CLAUDE.md or README note owner: `KitFanOpen`, `KitToggle`, the 4 + 4 grid, eight keys. The orchestrator writes one after the push.
- **Stray file.** A second empty stray file, `3640` (19:35), sits beside `700'`.

**C13. KitFanMatrix (b) borrows round state while in the lobby.**
- Writing workspace `RoundActive` and `RoundLoadingState` locally wakes every client listener on them: RoundUI, the level clients, sound. Restoring the values does not undo what those listeners did.
- **Fix:** run (b) only inside a live round started with the playtest recipe.
  - There those values are already true, and the lane borrows only the three inventory attributes and `KitFanOpen`.
  - Outside a live round, record SKIP.

### Smaller

**C14. The lobby RUN lift is unconditional.**
- At 844x390 (47 px housing), RUN at x 673..725 is clear of Roblox's jump zone (x 749..819). `applyTouchControlLayout` still lifts it to about y 240.
- At 667x375 with no housing the two do overlap: 543..595 against 572..642.
- **Fix (B):** lift only when RUN's rect overlaps `Zones.Jump` horizontally. QA 12 checks 844x390 (no lift) and 667x375 (lift).

**C15. `KitFan/Items`.**
- `Items` is a wrapper Framewisp inserts; it is not in REQUIRED. `Fan_Scan/Icon/Items` carries a UIListLayout of its own.
- **Fix:** `Binder.find(fan, "Items")` (its preorder reaches KitFan's direct child first), then `:FindFirstChildOfClass("UIListLayout")`. Never use a recursive class search. If `Items` is missing, warn and keep left-packing.

**C16. Harness stubs.** §0's stub list is incomplete:
- ProtectionHUD also needs `UnregisterControlRect`, `Layout().ModalArea`, `Layout().TopBand` and `ControlPlan.Fan`;
- FlashlightController needs `UnregisterControlRect`.

**C17. §9 QA gaps.** Add:
- **Level 1 capture (TOUCH).** Get captured with a shield ready. The SHIELD cell (order 1001) is tappable over the kill cam and cancels the capture. This is the reason the gui sits at 1001.
- **Developer POV.** The POV cell sits at 553..605 × 245..297 and reads POV over 1ST or 3RD. A non-developer does not see it.
- **Tablet.** One pass at 1024x768: 64 px cells, the 212x64 fan, text and stroke at s ≈ 1.23.
- **D11 in Studio.** On a 2-player local server, die: no touch cell is drawn and there is no SHIELD mirror.
- **`KitFanOpen` forced false.** Check death and `Level4CardOpen`. KitFanMatrix only drives the shade.

**C18. Small calls for the owner's TOUCH QA list,** next to D7 and D9-D12:
- The potion's ACTIVE countdown, SCAN's cooldown and the marker count are invisible while the fan is closed, and using an item closes the fan. KIT's closed face carries no state.
- As the battery runs out, the LIGHT label reads LIGHT, then LOW (≤ 2 segments), then LIGHT again (empty, Coral outline), then LOW (refused, Coral).
- After D12, a touch player with Advanced Equipment has no hint that holding LIGHT focuses the beam.
- A world-anchored prompt plate under the open fan cannot be tapped until the fan closes. The `phone-level-3` notes say the prompt's "reference spot runs under the open fan tray".
- Spectating touch players lose the watched battery that the old torch body mirrored.

### Verified, no change needed

- **Template paths.**
  - Every `HUD_Touch` path in §2.1, §5 and §6 exists in the dump.
  - `TouchCluster/Cell_Glow` exists only after `01_hud_templates` renames it.
  - These are absent by design: `Cell_Shield/Badge` (D9), `Cell_Kit/Cooldown`, and the fan items' `Glyph`, `ActiveTime`, `ActiveTag` and `KeyChip`.
  - `HUD_PC/EquipmentCaption/Label` exists, at 14 px.
- **Geometry.**
  - Cells are 52x52, with radius 0.2308.
  - The fan is 172x52. Its items are at LayoutOrder 1/2/3 (POTION, MARKER, SCAN), with a padding of 8.
  - At 844x390 the dump's cluster spans x 553..785 × y 245..357, and `phone-level-3` puts the fan items at x 553..725 × y 185..237. D1 and D2 reproduce both to the pixel. 568x320 keeps the grid with headroom 136.
- **Rule 2.** `rememberedFlag` latches the first `Selectable` it sees. The template ships `Selectable`, `AutoButtonColor` and `Active` all true, so rule 2 is right.
- **MOBILE_QA_20261008 sits where §2.5 says:**
  - UIDevice, lines 1644-1651;
  - NoiseReporter:
    - `TOUCH_JUMP_GROUNDED`, lines 620-647;
    - the GLOW gate, lines 946-948;
    - `Level6PlaygroundPreview` at lines 138 and 402;
  - ProtectionHUD:
    - `covered()`, lines 217-224;
    - the listener list, about line 745;
    - `DETECTOR_BIG_SCREEN`, line 374;
    - touch `TextSize`, about line 628;
  - FlashlightController: `FocusModeHint`, lines 645-646;
  - UIRegression carries none.
