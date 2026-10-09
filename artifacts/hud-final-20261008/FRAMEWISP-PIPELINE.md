# In-round HUD · Framewisp pipeline and template contract · 2026-10-08

**Owner order, 2026-10-08:** "Yes, faa alt det ui du nu har lavet ind i spillet. Brug framewisp og figma til det hele, computer use er tilladt. Eventuelt faa codex til at faa alt ind, og faa det til at virke."

This file is the contract that three groups of workers follow:
- the **Figma builders**, who build the export page;
- the **Codex import run** (computer use, Framewisp Live Sync);
- the **code batches B1-B8** in `BUILD-PLAN.md`.

The look is the approved one: Figma page "Final HUD 2026-10-08" (267:2), `OWNER-PICKS.md` and `INDEX.md`. This file decides only how that look travels from Figma into Roblox and how the code binds to it. Nothing was sent to Figma or Studio to write it.

**Precedent.** The lobby shop went the same way (`artifacts/shop-ui-figma-20261005/`):
- `INTEGRATION-CONTRACT.md` §6 is the layer-name contract.
- `roblox-draft/install/00_stage_reimport.luau` and `01_templates.luau` do the staging.
- `ReplicatedStorage.ZyntraShopUI.ShopBinder` is the binder.
- `"Zyntra Shop L4"` is the controller.
- `roblox-draft/tests/` holds the dump fixtures and the harness.
- The Codex runs are in `_local/shop-ui-figma/codex-import/` (`prompt-6.txt` / `report-6.txt` is the successful Live Sync bundle send of 2026-10-07).

Every "measured" fact below comes from those files.

---

## 0. The pipeline at a glance

| Step | Who | What | Cost |
|---|---|---|---|
| F1 | Figma builders | Build page **"HUD · Roblox export"** in file `7FXycGKH6OT6Lme6FV3VBc`: three wrapper frames `HUD_PC`, `HUD_Touch` and `HUD_Screens`, per §1 and §2. Record their node ids in §4.1. | Figma MCP calls. Full seat: 200 a day, 10 a minute, so batch a whole wrapper per `use_figma` call. |
| F2 | Figma builder | Run the pre-send lint (§1.2) as one `use_figma` call. It must report nothing. | 1 call |
| I1 | Codex (computer use) | Send `HUD_PC` with Live Sync (§4). | Conversion 1 of 5 |
| S1-S3 | Session (`execute_luau`, Edit) | Run `00_stage_hud`, `01_hud_templates` and `02_dump_hud` (§3). | none |
| T1 | Session | Run `test_hud_templates.py` on the dump (§3.6). If it fails, fix the Figma page before spending another conversion. | none |
| I2 | Codex | Send `HUD_Touch`, then `HUD_Screens`, in one run. | Conversions 2 and 3 of 5 |
| S1-S3, T1 | Session | Repeat them for both bundles. | none |
| B1-B8 | Code batches | Mount the templates (§5) instead of drawing with `Instance.new`. | none |
| S4 | Session | Run `03_hud_check` before **every** Play QA and every publish (§3.5). | none |

The conversions touch no script, so they can run at any time after B0's `pull --audit`. B1 needs `HUD_PC` and `HUD_Touch` installed (the detector has a touch line); B7 and B8 need `HUD_Screens`.

---

## 1. Bundles

### 1.1 What a bundle is

- **One wrapper frame is one conversion.** That is how `ZyntraBundle_L4` carried three shop screens on 2026-10-07 (`report-6.txt`). Framewisp then creates the ScreenGui `Framewisp_Live_<wrapper>` in StarterGui, and the wrapper sits as its child.
- **Wrapper names.** In Figma the layers are named `HUD_PC_nolist`, `HUD_Touch_nolist` and `HUD_Screens_nolist`. The tag is stripped on import, so in Studio they arrive as `HUD_PC`, `HUD_Touch` and `HUD_Screens`.
- **Wrapper size is a screen.**
  - `HUD_PC` and `HUD_Screens` are 1920x1080. `HUD_Touch` is 844x390.
  - A frame exported on its own is centred ("Exact layout needs an artboard"). A screen-size wrapper therefore lands exactly, and its size becomes the `BB_DesignW` / `BB_DesignH` attributes that the binder measures against.
- **Templates are the wrapper's direct children, drawn at 1:1 game pixels.**
  - The frames on page 267:2 are already at game size.
  - The element-sheet tiles (page 244:2, REF-1 and REF-2) are **2x**. Never copy one without halving it.
- **Positions inside the wrapper are free.** The code places every element through `UIDevice` (BUILD-PLAN §1.5). Templates may overlap; the shop bundle stacked three full screens. Put each template where its mockup has it when it fits, because that keeps the page readable.
- **State samples, annotations and notes stay outside the wrappers.** Only a selected wrapper is converted. A note that has to sit inside a wrapper ends in `_ignore`.

### 1.2 Bake rules: what becomes an image

Framewisp uploads every image to Roblox during "Prepare images", in Figma, before Studio sees anything. It uploads with the owner's saved key into group 1039373905 (`report-6.txt`). The owner's account was banned for an upload on 2026-10-07. Therefore:
- The target is **0 images in all three bundles.**
- The hard cap is 4 per bundle, and only after the owner explicitly approves that upload (BUILD-PLAN §7 Q8).
- An image Framewisp already uploaded counts as "reused", and nothing is uploaded again.

| In Figma | After Framewisp | Rule |
|---|---|---|
| Frame or rectangle with a solid fill, corner radius or stroke | Frame + UICorner + UIStroke | Use freely. Rules and dividers are 1-4 px rectangles, never LINE nodes. |
| Ellipse | Frame with a full UICorner | Use for dots, rings and initial circles. |
| Text in Montserrat, Roboto Mono, Roboto Condensed or Builder Sans, with **letter spacing 0** | TextLabel stamped with `FigmaFontSize` / `FigmaTextW` / `FW_M100` | The only allowed text. These are the families in ShopBinder's `EM` table. |
| Text with letter spacing other than 0, any other font, or a glyph the font lacks | **ImageLabel**: "Unsupported text is being sent as images", and that toggle stays ON | Forbidden. In the `DailyRewards_L4` dump, `Eyebrow`, `TokenLabel`, two `Label`s, `RewardName` and `SectionHelper` all arrived as images. The approved PC frames track their Mono eyebrows and tags ("LEVEL 4", "REELS LOADED"); set that tracking to 0 in the export copy. |
| Text stroke | UIStroke on the TextLabel (32 in the shop dump) | Allowed. The spectate band needs it (G2). |
| Linear gradient | UIGradient (7 in the shop dump) | Allowed. Its alpha is not proven, so see `Soft` in §2.0. |
| Drop shadow | UIShadow (28 in the shop dump) | Allowed, but the C designs use none. |
| Vector path, boolean, star, polygon, icon, radial or angular gradient, layer or background blur, image fill | **ImageLabel** | Forbidden. Build icons from frames and ellipses, or use a text glyph. |
| A frame's layer opacity under 100 % | CanvasGroup (7 in the shop dump) | Forbidden. Use fill alpha instead. Element opacity belongs to the code's `Attention`. |
| Dashed stroke | Not native | Forbidden. The DECIDING chip on Results gets a solid Sage stroke. |
| Hidden layer | **Not imported at all** | Every node the code needs must be visible (§2.0 rule 6). |
| Component instance | Unreliable names | Detach every instance in the export copy. |
| Characters | | In Figma text, only ASCII plus `·`, `×`, `«` and `»`. Other glyphs (`●`, `◆`, `▮`, `◀`, `▶`, `▼`, `↑`, `↓`, `‹`, `›`) are either drawn as frames, or carry an ASCII placeholder that the code overwrites at runtime with the `\u{...}` escapes of BUILD-PLAN §1.6. |

**The pre-send lint (F2)** is one `use_figma` script over the three wrappers. It lists every one of the following:
- VECTOR, BOOLEAN_OPERATION, STAR, POLYGON and LINE nodes;
- IMAGE fills;
- non-linear gradients;
- effects other than DROP_SHADOW;
- dashed strokes;
- text whose `letterSpacing` is not 0, whose family is outside the four allowed, or whose characters are outside the allowed set;
- frames with opacity under 1;
- hidden nodes inside a template;
- instances;
- names that break §2.0.

The list must be empty. Codex then checks the second gate, the Framewisp panel line **"This selection: N image(s)"**, which must read **0** (§4.3).

### 1.3 `HUD_PC` (1920x1080)

PC and gamepad. Gamepad keeps the PC look (BUILD-PLAN §1.5).

| Template | Element | Design size | Owner script |
|---|---|---|---|
| `RecLine` | 01 B REC line | about 330x24 | Found Footage HUD |
| `Bracket` | 01 one corner bracket, top-left orientation | about 56x56 | Found Footage HUD; also PARTY DOWN |
| `ObjectiveCard` | 04 C card + 06 C compass + 01 C WARNING row (`StatusRow`) | 360 wide, stack | RoundHud |
| `FlashlightWidget` | 07 B | about 110x56 | FlashlightController |
| `EquipmentPanel` | 08 C chips | 4 x 64, gap 8 | ProtectionHUD |
| `EquipmentCaption` | 08 refusal tag | about 200x24 | ProtectionHUD |
| `DetectorCard` | 09 C | 240x72 | RoundHud |
| `StaminaBar` | 10 C | 320 wide, hairline 6 | NoiseReporter |
| `NoiseMarker` | 03 C (also used on touch, at s = 1) | about 240x24 | Round HUD |
| `FeedRow` | 11 C row | ≤ 560 wide | RoundHud |
| `Caption` | 11 C caption | about 480x56 | RoundHud |
| `PromptPlate` | 12a C | about 300x64 | Found Footage HUD |
| `LeaveChip` | 13 C, resting | 40x40 | Round Exit Client |
| `LeaveChipWide` | 13 C, hover and hold | 240x40, plus the hint line | Round Exit Client |
| `RoundExitNotice` | 13 status line | about 240x20 | Round Exit Client |
| `RoundExitCard` | 13 C confirm (also on phone, scaled) | about 480x220 | Round Exit Client |

The objective card's states, the compass row's states and the WARNING row are not separate templates. They are property and visibility writes on `ObjectiveCard` (§2.3).

### 1.4 `HUD_Touch` (844x390)

The touch layout, so a tablet follows the phone (BUILD-PLAN §1.5).

| Template | Element | Design size | Owner script |
|---|---|---|---|
| `ObjectivePill` | 05 C, P4 | 240 wide; bar 40 tall, expanded ≤ 140 | RoundHud |
| `TouchCluster` | 14 A: seven cells | 52x52 cells | NoiseReporter, FlashlightController, ProtectionHUD |
| `KitFan` | 14 C KIT OPEN FAN | 3 x 52, gap 8 | ProtectionHUD |
| `FeedRowTouch` | 11 C, phone | 358 wide | RoundHud |
| `CaptionTouch` | 11 caption in the feed lane | 358 wide | RoundHud |
| `LeaveChipTouch` | 13 C, P2 | 44x44 | Round Exit Client |
| `DetectorLine` | 09, one line | 358x24 | RoundHud |
| `PromptPlateTouch` | 12b C | about 260x56 | Found Footage HUD |

### 1.5 `HUD_Screens` (1920x1080)

The full-screen and modal pieces, with their phone versions. Phone versions are drawn at phone pixels; the 1920 wrapper does not matter for them, because the size is measured per node.

| Template | Element | Design size | Owner script |
|---|---|---|---|
| `DeathCause` | 18 C card, open (G1 close X) | 480 wide, stack | RoundUI death do-block |
| `DeathCauseDocked` | 18 C docked | 480x44 | RoundUI |
| `DeathCauseTouch`, `DeathCauseDockedTouch` | 18 C on phone (frame 287:1466) | 420 wide / 420x44 | RoundUI |
| `SpectateBand`, `SpectateBandTouch` | 19 C, transparent (G2) | 520x80 / 420x56 | SpectateController |
| `SpectateBackToLobby` | the 13 C button above the band | about 180x40 | SpectateController |
| `PartyDownCard` | 20 B NO SIGNAL content block | about 960x740 | RoundUI party-down do-block |
| `PartyDownCardTouch` | 20 B on phone | ≤ 750x311 | RoundUI |
| `Results`, `ResultsTouch` | 21 C win, lose and escaped, with party rows | 1040 wide stack / 726x293 sheet | RoundUI results |
| `LoadingCard`, `LoadingCardTouch` | 17 C template for all six cards (G3) | 960x780 column / ≤ 750x311 | RoundUI loading |
| `HidingBanner`, `LeaveHiding`, `TableCheck` | 15 C | about 560x24 / 240x44 / 560x56 | Level 3 Table Hiding Client |
| `HidingBannerTouch`, `LeaveHidingTouch`, `TableCheckTouch` | 15 C on phone | 358x24 / 200x44 / 358x48 | Level 3 Table Hiding Client |
| `Level4Note` | 16 C note (on phone at s ≈ 0.89) | 380x270 | Level 4 Round Client |
| `Keypad` | 16 C keypad (on phone scaled to 300 tall) | 240x330 | Level 4 Round Client |

The **closed** death card is not a template: after X, Esc or B nothing is drawn (G1).

### 1.6 Not templates, because the code draws them better

| Thing | Drawn by | Why |
|---|---|---|
| Chase edge (02 A, reduced flashing) | Round HUD: four edge Frames with a Coral to transparent UIGradient, depth 12 % of the shorter side, one static transparency | Its size depends on the screen, and a gradient vignette would bake as an image |
| Full-screen backdrops: loading black `LevelLoading` (0,0,0, opaque), `PartyDownOverlay` (navy 4,7,16 at 0.1), the results scrim, the Level 3 shade and letterbox | The existing RoundUI / L3H code: one Frame each | They are one colour and fill the screen |
| Fill amounts and drains (objective progress, loading status bar, PARTY DOWN 15 s drain, table-check drain, stamina, the touch hold bar, `HoldFill`) | The code writes `Fill.Size.X.Scale` or tweens it | Live values. The template supplies only `Track` and `Fill` at a sample width |
| Ring sweeps (RUN stamina ring, phone leave-hold ring, prompt HOLD ring) | `RoundHud.Ring` in each `RingSlot` | Roblox has no native arc, and a drawn arc is a vector, which would bake |
| Compass chevron position and glyph | RoundHud: `Chevron.Position.X.Scale` and its text | The bearing is live. Ticks, centre and readout are template |
| Corner brackets in four corners | Code clones `HUD_PC/Bracket` four times, at Rotation 0, 90, 180 and 270 | The corners depend on the screen |
| Soft-Ink transparency ramp | `RoundHud.Soften` on every `Soft` node and stack root | Framewisp's gradient alpha is unproven, and this makes the look deterministic |
| Gamepad and keyboard glyph images | `RoundHud.Keycap`: `GetImageForKeyCode` into `KeyChip/GlyphSlot` | Engine content, so nothing is uploaded |
| Gamepad focus ring | `GuiService.SelectedObject` / `SelectionImageObject` | Engine feature |
| Element fades (6 s on, rest 45 / 40 / 55 / 60 %) | `RoundHud.Attention`, a CanvasGroup around each mount | Behaviour, not look |
| SignalFlash on results | The existing RoundUI code, gated on ReduceFlashing | Effect |
| Level 4 note handwriting face | Code sets `Body.FontFace` to PatrickHand | Patrick Hand is not a mapped family, so drawn in Figma it would bake |

### 1.7 Phone re-layouts that are not in the approved frames

The approved frames have no phone version of these. The builders lay out the **same named parts** at the BUILD-PLAN §2 phone sizes, with text of at least 12 px and tap targets of at least 44x44:
- `DetectorLine`: INDEX "Unfinished", e.g. `SCAN · HIGH · ENTITY VERY CLOSE`.
- `CaptionTouch`.
- `PartyDownCardTouch`: B's 740 px block cannot reach UIScale 0.85 on 390 px.
- `ResultsTouch`.
- `LoadingCardTouch`: title 34, two steps.
- `HidingBannerTouch`, `LeaveHidingTouch` and `TableCheckTouch`.

They are no new design decisions, but list them in the handover so the owner sees them in the B7 and B8 TOUCH QA.

---

## 2. The layer-name contract

### 2.0 Rules (all templates)

1. **Base names.** Framewisp strips tags on import: every real dump reports `namesKeepingTags: 0`. `ShopBinder.base` also strips any tag that survives. The code finds nodes with `Binder.at(root, "A/B")`, which runs one descendant search per segment. So the `Items` frames that Framewisp inserts when it turns equal gaps into a UIListLayout cost nothing.
2. **Uniqueness.**
   - Template names are unique across all three bundles.
   - A child name is unique inside its template, except names that repeat under **different named parents** (`Prev/KeyChip`, `Next/KeyChip`). The code always addresses those through the parent.
3. **Never use a GuiObject property as a name:** `Name`, `Text`, `Image`, `Size`, `Position`, `Visible`, `Parent`, `Active`, `Rotation`, `Font`, `Selected`, `ZIndex`. A DisplayName goes in `Who`, and a line of text in `Line`, `Label` or `Said`.
4. **Underscores** appear only in the family prefixes `Chip_`, `Cell_`, `Fan_`, `Stat_` and `Key<n>_`, and never followed by a tag word (`list`, `grid`, `image`, `panel`, `fit`, `aspect`, `shadow`, `txt`, `close`, `button`, `ignore`, `scroll`, `tabgroup`).
5. **Framewisp tags:**
   - `_button` goes on every node the code binds input to. It becomes a TextButton.
   - `_close` is added to close Xs: `Close_button_close`.
   - `_list` goes on a row whose children the code hides one by one, so the gap closes ("no empty slot", owned-only chips).
   - `_nolist` goes on the wrappers, on stack roots, on `Compass`, and on any container holding a node whose `Position` the code writes.
   - `_ignore` marks a note inside a wrapper.
   - **Never use** `_tab`, `_tabgroup`, `_active`, `_hover` (Framewisp ignored `_active` neighbours in run 6), `_scroll`, `_grid` or `_txt`. Framewisp drops `_txt`'s wrapping and the binder cannot see the stripped tag; rule 7 decides wrapping instead.
6. **One template per element, drawn as the union of its states.**
   - Every child the code may ever show is in the template and **visible**.
   - States are property writes (**P**) or Visible toggles (**U**) on that one template.
   - A separate template (**S**) is used only where the layout itself changes: docked and open death card, resting and wide leave chip, PC and touch.
   - Draw the default state: READY, NORMAL, LOCKED, LEVEL 1.
7. **Text boxes.**
   - **Dynamic single-line text:** Fixed width, at the widest the design allows. One line tall. The sample is the longest realistic copy (e.g. `WATCHING ALEXANDRA · LEVEL 3`). Fixed, not Hug, because `fitLine` can only widen into free space.
   - **Multi-line text:** draw the box *N* lines tall. `RoundHud.Mount` sets `TextWrapped` on every text whose design height ÷ (`FigmaFontSize` × em) ≥ 1.8.
   - Keep `Title` and `Detail` one line tall, because ShopBinder wraps those names on its own when their box is two lines tall.
8. **Touch floor.** Every text in `HUD_Touch` and in every `*Touch` template has `FigmaFontSize` ≥ 12, and every tap target is ≥ 44x44. A smaller visual sits inside a transparent 44x44 `_button` frame. At mount the code also adds `UITextSizeConstraint.MinTextSize = 12` to touch texts.
9. **Colours** come only from the fixed tokens in `Binder.Palette`:
   - Ink, Tile, TileHi, Line, Cream, Sage, IconTeal, RailTeal, Amber and Coral;
   - plus black 0,0,0 and the PARTY DOWN navy 4,7,16;
   - plus **LEVEL 1 yellow #FFE600 on every accent node**, and only on accent nodes (§2.10).

   The level dims are drawn nowhere (INDEX: "No node on the page used a level dim colour"). The `Level4Note/Paper` colours are the one exception to the lint.
10. **`Soft`** is the soft-Ink backing.
    - Draw it as a Frame filled Ink with a linear gradient from 65 % to 0 % alpha. `RoundHud.Soften` rewrites its UIGradient Transparency to 0.35 → 1.
    - Where a pill or row hugs dynamic text, the code resizes `Soft` (or `Plate`), which holds no text. It **never resizes a mounted root**: `Binder.scaleText` takes its scale `k` from the root's size.
11. **Stack templates** (marked *stack* below) change height with their content.
    - The root carries the card look: fill, UICorner, UIStroke and UIGradient.
    - Its direct children are full-width **parts** that tile it from top to bottom with no gap and no overlap.
    - The code mounts each part into a code-made, auto-height vertical list and hides parts to collapse the card.
    - The root is tagged `_nolist`.
12. **Shared parts** (same names everywhere):
    - **`KeyChip`**: an outline chip > `Key` (text, sample `E`) + `GlyphSlot` (an empty, visible, transparent square). `RoundHud.Keycap` writes the key letter, or puts the engine glyph into `GlyphSlot`, or hides the chip on touch. The name is pinned by `test_equipment_hud.py` and UIRegression.
    - **`RingSlot`**: an empty, visible, transparent square where the code draws a ring sweep.
    - **`Track` > `Fill`**: drawn at a sample fraction. The code owns `Fill`'s width.
    - **`Initial`** > `Ring` (circle outline) + `Letter` (dyn).
13. **Pinned names.** Tests and UIRegression rows read these, so the templates use them as they are:
    - `KeyChip`, `FlashlightPower`, `EquipmentPanel`, `EquipmentCaption`;
    - `RoundExitCard`, `Title`, `Body`, `HoldFill`, `HoldHint`, `Notice`;
    - `SpectateBackToLobby`;
    - `DeathCause`, `DeathCauseTitle`, `DeathCauseBody`, `DeathCauseEyebrow`, `DeathCauseTip`;
    - `PartyDownCard`, `PartyDownTitle`, `PartyDownTimer`, `PartyDownFallen`, `PartyDownTrack`, `PartyDownFill`, `PartyDownReentry`, `PartyDownFreeRespawn`, `PartyDownDecline`;
    - `EndingTitle`, `EndingStats`, `EndingHint`, `ContinueRun`, `ReturnToLobby`, `PartyChoice1`-`PartyChoice6`.

    A mounted root may be renamed to its live name. That name is given under **Mounted as**.

**Table legend.**
- Kind: **F** frame, **T** text, **B** `_button`, **part** = a stack part.
- **dyn**: the code rewrites the text or colour. **static**: design copy that the code never writes. Anything sitting in a dyn text slot is placeholder copy.
- State: **P** property write, **U** shown or hidden, **S** separate template.
- Every path is required unless marked *(opt)*. `01_hud_templates.luau`'s `REQUIRED` table is exactly this list (§3.3).

### 2.1 `RecLine` · 01 B · PC only

Root tagged `_nolist`. Mounted as `RecLine` inside the Found Footage HUD gui (order 12).

| Path | Kind | Content | State |
|---|---|---|---|
| `Dot` | F ellipse, Coral | | static |
| `Rec` | T Mono, Cream | `REC` | static |
| `Time` | T Mono, Cream | dyn `02:37` (sample `1:02:37`); mm:ss, then h:mm:ss past 60 min | P |
| `SignalLabel` | T Mono, Sage | `SIGNAL` | static |
| `Bars/Bar1`-`Bar4` | F, rising heights | lit Cream, `Bar4` Line | static (Q2 default) |
| `Watching` | T Mono, Sage | dyn `· 1 WATCHING` | U, only while own `SpectatorCount` > 0 |

`Bracket`: `ArmH` and `ArmV`, both F in Cream at the design alpha. One top-left corner, rotated by the code.

### 2.2 `FlashlightWidget` · 07 B · PC and gamepad

Root tagged `_nolist`. FlashlightController mounts it in its widget gui (order 61). It is never mounted on the touch layout (P1).

| Path | Kind | Content | State |
|---|---|---|---|
| `KeyChip` | shared | `F`, or the R1 glyph | P |
| `Battery/Shell` | F with a Cream UIStroke | | P: Coral stroke at EMPTY |
| `Battery/Seg1`-`Seg5` | F | | P: lit Cream, unlit Line; Amber when ≤ 2 are lit |
| `Battery/Nub` | F, Cream | | static |
| `Line` | T Mono, Cream | dyn: `LIGHT`, `LIGHT OFF · CHARGING` (the sample), `LIGHT · LOW` (Amber), `LIGHT · EMPTY` (Coral), `LIGHT · TOO LOW`, `LIGHT · WIDE`, `LIGHT · FOCUSED`, `THEIR LIGHT` | P |

### 2.3 `ObjectiveCard` · 04 C + 06 C + 01 C WARNING · PC, *stack*, 360 wide

`RoundHud.ObjectiveCard` mounts it into `RoundHud` (order 10). The root's fill is the soft-Ink look (rule 10).

| Part / path | Kind | Content | State |
|---|---|---|---|
| **`Head`** | part | | |
| `Head/Eyebrow` | T Mono, **accent** | dyn `LEVEL 4`. Level 4 is `LEVEL 4 · THE LAST SHOW`; spectating is `WATCHING ANNA · LEVEL 3` in RailTeal (the sample, being the longest) | P |
| `Head/Title` | T Montserrat Black, Cream | dyn `LOAD THE PROJECTORS` | P |
| `Head/Underbar` | F, **accent**, 4 px | | P |
| **`Counter`** | part | | |
| `Counter/Count` | T Roboto Condensed, Cream | dyn `1/3` | P: RailTeal while DONE |
| `Counter/CountTag` | T Mono, Sage | dyn `REELS LOADED` | P |
| **`Progress`** | part | | |
| `Progress/Track/Fill` | F Line track, F **accent** fill | the code owns the width | P: RailTeal while DONE |
| **`Guide1`**, **`Guide2`** | parts | | U: zero to two lines |
| `Guide1/Line`, `Guide2/Line` | T Montserrat SemiBold, Sage, one line | dyn `You carry 2 reels.` | P |
| **`StatusRow`** | part: **the 01 C WARNING row** | | U |
| `StatusRow/Bar` | F, Amber, 4 px | | P: Amber for warning, Coral for danger |
| `StatusRow/Label` | T Montserrat SemiBold, Amber | dyn `Main breaker: fuse 42 s` | P: Amber, Coral, or Sage for `held by Anna` |
| **`Compass`** | part, `_nolist`, 328x32 inside the 360 part | | U: only when a target exists |
| `Compass/Ticks` | nine F ticks, ±60° every 15° | | static |
| `Compass/Centre` | F | | static |
| `Compass/Chevron` | T, **accent**, ASCII placeholder `v` | the code writes `▼`, `◀` or `▶`, or `▼▼▼` for CALIBRATING, and sets `Position.X.Scale` | P |
| `Compass/Readout` | T Mono | dyn: `42 m` (Sage), `AT THE EXIT` (RailTeal), `CALIBRATING` (Sage), `IN THIS ROOM` (Coral) | P |

Every state on this card is P or U: COLLAPSED and EXPANDED do not apply on PC, DONE, WARNING, DANGER, SPECTATING, and the compass states LOCKED, BEHIND, CALIBRATING, IN THIS ROOM and ARRIVED. IDLE 45 % comes from `Attention`. DANGER never dims.

### 2.4 `ObjectivePill` · 05 C · touch, *stack*, 240 wide (P4)

It uses **the same child names as the card**, so one writer drives both.

| Part | Contents | State |
|---|---|---|
| `Bar` (240x40) | `Eyebrow` (accent), `Title`, `Count` (right-aligned), `Underbar` (accent) | always shown: this is COLLAPSED |
| `Progress` | `CountTag`, `Track/Fill` (accent) | U: EXPANDED only |
| `Guide1`, `Guide2` | `Line` | U: EXPANDED only |
| `StatusRow` | `Bar`, `Label` | U: EXPANDED only, and only while a status exists |
| `Compass` (220x20, `_nolist`) | `Ticks`, `Centre`, `Chevron`, `Readout` | U: EXPANDED only |

The code lays a transparent `Hit` button, at least 44 tall, over `Bar` (`Binder.button`).

### 2.5 `EquipmentPanel` + `EquipmentCaption` · 08 C · PC and gamepad

`EquipmentPanel` is tagged `_list`: horizontal, gap 8. ProtectionHUD mounts both in the `ProtectionHUD` gui (order 1001), as `EquipmentPanel` and `EquipmentCaption`.

Each of `Chip_Shield`, `Chip_Potion`, `Chip_Markers` and `Chip_Scan` is a **B**, a 64x64 face with a keycap below it:

| Path (per chip) | Kind | Content | State |
|---|---|---|---|
| `Face` | F Tile, UICorner, UIStroke Line | | P: stroke RailTeal 3 px for ACTIVE, Coral for REFUSED; face alpha 50 % when EMPTY |
| `Icon` | frames and ellipses (vectors are forbidden, Q8) | | U: hidden during COOLDOWN |
| `Badge/Count` | F circle, T | dyn `2` | U |
| `Cooldown` | T Roboto Condensed, Cream | dyn `12` | U: COOLDOWN |
| `ActiveTime` | T Roboto Condensed, RailTeal | dyn `4.2` | U: ACTIVE |
| `ActiveTag` | T Mono, RailTeal | `SAFE` | U: ACTIVE, static |
| `KeyChip` | shared | `Q`, `T`, `X` or `Z`, or the pad glyphs | P |

A chip that is not owned is hidden (U), and the `_list` closes the gap. With every chip hidden, the panel is hidden.

`EquipmentCaption` holds `Soft` and `Label`: T Mono, Coral, dyn, sample `NO MARKERS LEFT`, one of the four refusal tags. It is U.

**Icons.** If the owner approves Q8, the four chip icons may be at most 4 images in `HUD_PC`. `KitFan` and `Cell_Shield` reuse the same images, which counts as 0 new uploads.

### 2.6 `DetectorCard` (PC) and `DetectorLine` (touch) · 09 C

`RoundHud.Detector` mounts them into `RoundHud` (order 10, down from 1100).

| Path | Kind | Content | State |
|---|---|---|---|
| `Soft` | backing | | static |
| `Bars/Bar1`-`Bar3` | F | | P: lit by level, LOW Sage, MEDIUM Amber, HIGH Coral |
| `Reading` | T Mono | dyn `SCAN · MEDIUM` | P (PC) |
| `Headline` | T Montserrat ExtraBold, Cream | dyn `ENTITY NEARBY` | P (PC) |
| `Seconds` | T Mono, Sage | dyn `4 s` | P (PC) |
| `Line` | T Mono, at least 12 px | dyn `SCAN · HIGH · ENTITY VERY CLOSE` | P (touch only; replaces the three PC texts) |

### 2.7 `StaminaBar` · 10 C · PC and gamepad

NoiseReporter mounts it in `StaminaGui` (order 60, the name kept).

| Path | Kind | Content | State |
|---|---|---|---|
| `Track/Fill` | F Line track (radius 3), F Cream fill | the code owns the width | P: Amber at ≤ 25 %, Coral while winded |
| `Winded` | T Mono, Coral | `WINDED` | U, static |

### 2.8 `NoiseMarker` · 03 C · every level, PC and touch

Round HUD mounts it into `RoundHud`.

| Path | Kind | Content | State |
|---|---|---|---|
| `Soft` | backing, resized by the code to the text | | P |
| `Dot` | F ellipse | | P: RailTeal; Amber for LOUD |
| `Label` | T Mono | dyn `SNEAKING`, `LOUD`, `HIDDEN`, or `INVISIBLE TO MONSTERS · 8 s` (the sample) | P |

`ADRENALINE` never appears; the lint forbids it.

### 2.9 `FeedRow`, `FeedRowTouch`, `Caption`, `CaptionTouch` · 11 C

`RoundHud.Feed` mounts each row **once**: two on PC, one on phone. It rewrites them and never clones per event.

| Path | Kind | Content | State |
|---|---|---|---|
| `Soft` | backing, resized | | P |
| `Bar` | F, RailTeal | | P: RailTeal TEAM, Coral DANGER, Cream SYSTEM. U: hidden for LEVEL |
| `Dot` | F ellipse, Amber | | U: LEVEL kind only |
| `Initial/Ring`, `Initial/Letter` | F, T | dyn `O` | P |
| `Words` | F, `_nolist` | | |
| `Words/Who` | T Montserrat ExtraBold, Cream | dyn DisplayName, `Oskar` | P |
| `Words/Detail` | T Montserrat SemiBold, Sage, one line | dyn `loaded a reel · 1/3` | P |

`Detail` follows `Who` through `Binder.flowRow(Words)`, which lays it out from the drawn width of `Who`.

The caption templates hold `Soft`, `Speaker` (T Mono, IconTeal, dyn `USHER`) and `Said` (T Montserrat SemiBold, Cream, dyn `Shhh...`).

### 2.10 `PromptPlate` (12a) and `PromptPlateTouch` (12b) · C

The Found Footage HUD mounts one per visible ProximityPrompt and pools them.

| Path | Kind | Content | State |
|---|---|---|---|
| `Plate` | F Ink, radius 12 (on touch `Plate_button`) | | static |
| `KeyChip` | shared, 40 px circle variant (PC and gamepad only) | `E`, or the pad glyph | P |
| `RingSlot` | around `KeyChip` (PC only) | HOLD sweep | code |
| `ObjectLine` | T Mono, Sage | dyn `PROJECTOR`, uppercased at render | P |
| `ActionLine` | T Montserrat ExtraBold, Cream | dyn `THREAD REEL`, uppercased at render | P: greyed while DISABLED |
| `Reason` | T Mono, Amber | dyn `NEEDS A FUSE` | U: DISABLED, replaces `ObjectLine` |
| `HoldBar/Track/Fill` | F (touch only) | | code |

### 2.11 Leave: `LeaveChip`, `LeaveChipWide`, `RoundExitNotice`, `RoundExitCard`, `LeaveChipTouch` · 13 C

Round Exit Client mounts all of them in `RoundExitGui` (order 70).

| Template / path | Kind | Content | State |
|---|---|---|---|
| `LeaveChip` (root `_button`) > `Door` | frames (a door frame and a knob dot) | | S, resting 50 % |
| `LeaveChipWide` (root `_button`) | | | S: hover and hold |
| `LeaveChipWide/Door` | frames | | static |
| `LeaveChipWide/Hold` | T Mono, Cream | `HOLD` | static |
| `LeaveChipWide/KeyChip` | shared | `L`, or the View glyph | P |
| `LeaveChipWide/Label` | T Mono, Cream | `· BACK TO LOBBY` | static |
| `LeaveChipWide/HoldFill` | F, RailTeal | the code fills it over 1.5 s | P |
| `LeaveChipWide/HoldHint` | T Montserrat SemiBold, Sage, no plate | `Leaving ends your run. The others keep playing.` | static |
| `RoundExitNotice/Notice` | T Mono | dyn `NO ANSWER · HOLD AGAIN` or `RETURNING...` | P |
| `RoundExitCard/Title` | T Montserrat Black, Cream | `RETURN TO THE LOBBY?` | static |
| `RoundExitCard/Body` | T Sage, 2 lines | `Your run ends here. The others keep playing.` | static |
| `RoundExitCard/BackToLobby_button` > `Label` | B Coral | `BACK TO LOBBY` | static |
| `RoundExitCard/Stay_button` > `Label` | B | `STAY` | static; default focus |
| `LeaveChipTouch` (root `_button`, 44x44) > `Door`, `RingSlot` | | the hold fills the ring; the chip never expands (P2) | P |

### 2.12 `TouchCluster` + `KitFan` · 14 A + C · touch

The cells are mounted **one by one** into the `UIDevice.ControlPlan` rects at s = rect / 52, which is about 1.23 on a tablet. The `TouchCluster` frame itself is only the drawing board. Each cell is a 52x52 **B** with an Ink face, radius 10, a glyph above, and a 12 px caps `Label`.

| Cell | Mounted by, as | Children | State |
|---|---|---|---|
| `Cell_Jump` | NoiseReporter | `Glyph` (placeholder `^`; the code writes `↑`), `Label` `JUMP` | static |
| `Cell_Run` | NoiseReporter | `Glyph` `»`, `Label` `RUN`, `RingSlot` | P: ring Amber at ≤ 25 %, Coral while winded; the face carries the noise state |
| `Cell_Sneak` | NoiseReporter | `Glyph` (placeholder `v`; the code writes `↓`), `Label` `SNEAK` | P: engaged face |
| `FlashlightPower` | FlashlightController (pinned) | `Seg1`-`Seg5`, `Label` `LIGHT` | P: segments lit or outlined, Amber at ≤ 2, Coral outline at 0; `Label` reads `LOW` for 2 s after a refused press |
| `Cell_Glow` | NoiseReporter | `Glyph` `*`, `Label` `GLOW`. Framewisp strips `_Glow` as a tag, so it imports as `Cell`; `01_hud_templates` renames it by its `GLOW` label | static |
| `Cell_Kit` | ProtectionHUD | `Glyph` `+` (open: `×`), `Label` `KIT` | P: RailTeal face while open; publishes `KitFanOpen` |
| `Cell_Shield` | ProtectionHUD | `Glyph` (a rotated square frame, or the code writes `◆`), `Label` `SHIELD`, `Cooldown` | P/U: 08 C states on the A face |

`KitFan` is tagged `_list` (horizontal) and holds `Fan_Potion`, `Fan_Marker` and `Fan_Scan`, each a **B** with `Icon`, `Label`, `Badge/Count` and `Cooldown`. A fan item that is not owned is U-hidden, and the list closes the gap.

### 2.13 Death card · 18 C · G1

RoundUI's death do-block mounts the card, as `DeathCause`.

**`DeathCause`** (PC, *stack*, 480 wide) and **`DeathCauseTouch`** (420 wide, no `CloseHint`). The root has the plate look: Ink, radius and stroke.

| Part / path | Kind | Content | State |
|---|---|---|---|
| **`Head`** | part | | |
| `Head/WhatHappened` | T Mono, Coral | `WHAT HAPPENED` | static |
| `Head/DeathCauseTitle` | T Montserrat Black, Cream | dyn `YOU FELL` | P |
| `Head/CloseHint/KeyChip` | shared | `Esc`, or the B glyph | P. U: hidden on touch |
| `Head/Close_button_close` | B, a transparent 44x44 hit area | | |
| `Head/Close_button_close/Disc` | F, Tile circle, 28 px | | static |
| `Head/Close_button_close/Cross` | T, Cream | `×` | static |
| **`Cause`** > `DeathCauseBody` | T Montserrat SemiBold, Sage, 2 lines | dyn `You fell through a hole in the floor.` | P |
| **`Advice`** | part | | U: hidden when the cause has no tip; the card shrinks |
| `Advice/Divider` | F, Line | | static |
| `Advice/DeathCauseEyebrow` | T Mono, IconTeal | `NEXT TIME` | static |
| `Advice/DeathCauseTip` | T Montserrat SemiBold, Cream, 2 lines | dyn `Watch your step: some of the floor gives way.` | P |

**`DeathCauseDocked`** (480x44) and **`DeathCauseDockedTouch`** (420x44) are **S**. They hold `DockBar` (F, Coral, 4 px), `DeathCauseTitle` and `Close_button_close`. While PARTY DOWN is open the docked X takes click and tap only.

CLOSED is not drawn.

### 2.14 Spectate · 19 C · G2

SpectateController mounts these in `SpectateGui` (order 58).

**`SpectateBand`** (PC, 520x80) and **`SpectateBandTouch`** (420x56). The root has **no fill**, at BackgroundTransparency 1.

| Path | Kind | Content | State |
|---|---|---|---|
| `Prev_button` | B; on touch a 44x44 hit | | |
| `Prev_button/KeyChip` | shared, outline only (PC and gamepad) | `Q`, or the D-pad left glyph | P |
| `Prev_button/Arrow` | T | placeholder `«`; the code writes `‹` | static |
| `Initial/Ring`, `Initial/Letter` | F outline, T | dyn `A` | P |
| `Watching` | T Mono, RailTeal | dyn `WATCHING`, `YOU GOT OUT · WATCHING` (the sample), or `SPECTATING` | P |
| `Who` | T Montserrat Black, Cream | dyn `ANNA`, or `NO ONE LEFT TO WATCH` | P |
| `Next_button` | B | | |
| `Next_button/KeyChip`, `Next_button/Arrow` | as for `Prev_button` | `E` / `›` | P |

**Every T carries a text stroke**: Ink, 1.5 px, transparency 0.35. The code asserts it and adds it if it is missing. The keycap chips are outlines with no fill, so nothing reads as a backdrop.

**`SpectateBackToLobby`** is a **B** in the 13 C button look, holding `Label` `BACK TO LOBBY`. Mounted as `SpectateBackToLobby`.

### 2.15 `PartyDownCard` and `PartyDownCardTouch` · 20 B

RoundUI's party-down do-block mounts the card into the code-made `PartyDownOverlay`, together with four `Bracket`s on PC.

| Path | Kind | Content | State |
|---|---|---|---|
| `NoSignal` | T Mono, Cream, large | `NO SIGNAL` | static |
| `TitleRow` | F, `_nolist` | | |
| `TitleRow/PartyDownTitle` | T Mono, Coral | `PARTY DOWN` | static |
| `TitleRow/PartyDownTimer` | T Mono, Coral | dyn `· 00:15` | P (laid out with `flowRow`) |
| `PartyDownTrack/PartyDownFill` | F dark-coral track, F Coral fill | the code drains it | P |
| `PartyDownFallen` | T Mono, Sage | dyn `ANNA FELL` | U: hidden when the name is nil |
| `Reentry` | T Mono, Cream | `EMERGENCY RE-ENTRY` | U: hidden when not eligible |
| `Offer` | F, `_list`, horizontal, centred | | |
| `Offer/PartyDownReentry_button` > `Label` | B, Cream outline | dyn `USE CREDIT · 1 OWNED`, `BUY · R$ 29 · 0 OWNED` (Amber outline, the sample), or `WAITING FOR ROBLOX...` | P/U |
| `Offer/PartyDownFreeRespawn_button` | B | | U: developers only |
| `Offer/PartyDownFreeRespawn_button/Label` | T | `FREE RESPAWN` | static |
| `Offer/PartyDownFreeRespawn_button/DevChip/Label` | T, Coral | `DEV` | static |
| `Offer/PartyDownDecline_button` > `Label` | B | `NO THANKS` | static |

When the player is not eligible, only `PartyDownDecline` stays, and the list closes the gap (no empty slot). The **docked death card** is a separate template, `DeathCauseDocked`, placed above the card unless the player has closed it.

`BACK WHERE YOU FELL` must not exist. `01_hud_templates.luau`'s forbidden-text check fails on it.

### 2.16 `Results` (PC, *stack*, 1040 wide) and `ResultsTouch` (726x293) · 21 C

RoundUI's results block mounts it into `RoundEnding`. The rows go into a code-made `PartyChoices` list. The root's fill is the soft-Ink look; there is no plate.

| Part / path | Kind | Content | State |
|---|---|---|---|
| **`Head`** | part | | |
| `Head/Eyebrow` | T Mono, **accent** | dyn `LEVEL 2` | U: on a loss |
| `Head/EndingTitle` | T Montserrat Black | dyn `NO ONE FOUND A WAY OUT` (the sample) or `LEVEL 3 CLEARED` (Cream); Coral on a loss | P |
| `Head/Underbar` | F, RailTeal | | static |
| `Head/EndingHint` | T Mono, Sage | dyn `WAITING FOR THE OTHERS` | U: own escape |
| `Head/EndingStats` | F, `_list` | | |
| `Head/EndingStats/Stat_Time`, `Stat_Survivors`, `Stat_Counter` | tiles | `Stat_Counter` is shown only on a loss | U |
| each tile's `Label` | T Mono, Sage | `TIME`, `SURVIVORS`; for the counter tile dyn `PUMP STATIONS` | P |
| each tile's `Num` | T Roboto Condensed, Cream | dyn `02:37` | P |
| `Head/Rule` | F, Line | | static |
| **`Party`** > `PartyHeader` | T Mono, Sage | `PARTY` | static |
| **`PartyChoice1`**-**`PartyChoice6`** | parts, one per member (max party 6, GameManager `MAX_PLAYERS_PER_STATION`) | | U |
| each row: `Plate`, `Initial/Ring`, `Initial/Letter` | | | |
| each row: `Who` | T | dyn `Anna` | P |
| each row: `Sub` | T Mono | dyn `GOT OUT` (RailTeal), `FELL`, `DOWN`, `WATCHING NEXT` | P |
| each row: `Chip/Label` | | dyn `CONTINUE` (RailTeal outline), `DECIDING` (solid Sage stroke, never dashed), `LOBBY`, `DOWN` (Coral), `INSIDE`, `GOT OUT` | P |
| **`Footer`** | part | | |
| `Footer/Countdown` | T Mono, Sage | dyn `RETURNING TO LOBBY IN` | P |
| `Footer/CountNum` | T Roboto Condensed | dyn `14` | P (laid out with `flowRow`) |
| `Footer/ContinueRun_button` > `Label` | B, RailTeal face | dyn `CONTINUE` / `CONTINUING...` | U: hidden on a loss |
| `Footer/ReturnToLobby_button` > `Label` | B | dyn `BACK TO LOBBY` / `RETURNING...` | P |

`SignalFlash` and `SignalLine` stay as code. `EndingStats` stops being a TextLabel; B8 updates the UIRegression rows that read its `.Text`.

### 2.17 `LoadingCard` (PC, 960x780) and `LoadingCardTouch` · 17 C · G3

This is **not a stack.** The status line and the level track sit at the bottom on every card, LEVEL 2 included. RoundUI's loading block mounts it into `LevelLoading` (code: black and opaque) with the bottom anchored 24 px above the safe bottom.

| Path | Kind | Content | State |
|---|---|---|---|
| `Eyebrow` | T Mono, **accent** | dyn `LEVEL 4 · THE LAST SHOW` | U: hidden on 2 and 5 |
| `Title` | T Montserrat Black, Cream, one line | dyn `RESTORE THE POWER`, `UNRECORDED`, `??? WHERE?`, `THE PLAYGROUND` | P |
| `Underbar` | F, **accent** | | P |
| `Steps` | F | | U: hidden on 2, 5 and 6 |
| `Steps/Step1`-`Step3` | each: `Num` (T, IconTeal, `1`, static) and `Line` (T, Cream, dyn) | | `Step3` is *(opt)*: it is absent in `LoadingCardTouch` |
| `Divider` | F, Line | | U, with `Steps` |
| `Tip` | F | | U: 1, 3 and 4 only |
| `Tip/TipLabel` | T Mono, IconTeal | `TIP` | static |
| `Tip/TipText` | T Sage, 2 lines | dyn: the DeathAdvice tip | P |
| `Status/StatusLine` | T Mono, Sage | dyn `WAITING FOR EVERYONE TO LOAD · 3/4` | P |
| `Status/Track/Fill` | F, **accent** | | P |
| `LevelTrack` | F, `_nolist` | | |
| `LevelTrack/Slot1`-`Slot6` | T Mono | `1`, `?`, `3`, `4`, `?`, `6` | P: the current slot in the accent at full opacity, the others Sage at 45 % |
| `LevelTrack/Sep1`-`Sep5` | T, Sage | `·` | static |

### 2.18 Level 3 hiding · 15 C

The Level 3 Table Hiding Client mounts these in `Level3TableHideUI` (order 92). The shade and the letterbox stay as code.

| Template / path | Kind | Content | State |
|---|---|---|---|
| `HidingBanner/Banner` (and `…Touch`) | T Mono, RailTeal, no plate | `HIDDEN UNDER TABLE` | static; rests at 45 % |
| `LeaveHiding` (root `_button`) | | | rests at 55 % |
| `LeaveHiding/KeyChip` | shared | `E`, or the B glyph | P. Absent in `LeaveHidingTouch` |
| `LeaveHiding/Label` | T | `LEAVE HIDING` | static |
| `TableCheck/Warn` (and `…Touch`) | T Montserrat Black, Coral | `IT'S LOOKING · LEAVE NOW` | static |
| `TableCheck/Seconds` | T, Coral, right-aligned | dyn `1.2 s` | P |
| `TableCheck/Track/Fill` | F, Coral | the code drains it from `EndsAt` | P |

TABLE CHECK never dims.

### 2.19 Level 4 · 16 C

The Level 4 Round Client mounts these in `Level4RoundGui`, order **60**.

**`Level4Note`** is a root `_button`: on touch a tap anywhere closes it.

| Path | Kind | Content | State |
|---|---|---|---|
| `Paper` | F, paper colour (the lint exception) | | static |
| `Body` | F, the imported auto-layout `Items` list | | static |
| `Body/Items/BodyLine1`-`4` | T, one line each (as imported 2026-10-08) | dyn: the order text, one line per label (line 3 is the blank spacer). Drawn in Montserrat; the code sets PatrickHand on each line. The sample route's `>` is rewritten to `·` by `01_hud_templates` | P |
| `CloseHint` | F | | U: PC and pad |
| `CloseHint/KeyChip` | shared | `E`, or the B glyph | P |
| `CloseHint/Label` | T | `CLOSE` | static |
| `TapToClose` | T | `TAP TO CLOSE` | U: touch |

**`Keypad`**:

| Path | Kind | Content | State |
|---|---|---|---|
| `Heading` | T Mono | `PRIZE CASE · ENTER CODE` | static |
| `Display` | T Roboto Condensed | dyn `----` | P |
| `Key0_button`-`Key9_button` > `Label` | B, Tile face, Cream numerals | `0`-`9` | static |
| `KeyC_button` > `Label` | B | `C`, Sage | static |
| `KeyOK_button` > `Label` | B, RailTeal | `OK` | static |
| `Close_button_close` > `Cross` | B, Coral | `×` | static |
| `Status` | T, Coral | dyn `WRONG CODE` | U |
| `PressHint/KeyChip` + `PressHint/Label` `PRESS` | | | U: pad only |
| `CloseHint/KeyChip` + `CloseHint/Label` `CLOSE` | | | U: pad only |

### 2.20 Accent map: the only nodes drawn in #FFE600

`RoundHud.Paint(root, templateName, level)` writes `UIStyle.Hud` accent[level] into exactly these nodes:

| Template | Path → property |
|---|---|
| `ObjectiveCard`, `ObjectivePill` | `Eyebrow`.TextColor3, `Underbar`.BackgroundColor3, `Progress/Track/Fill`.BackgroundColor3, `Compass/Chevron`.TextColor3 |
| `LoadingCard`, `LoadingCardTouch` | `Eyebrow`.TextColor3, `Underbar`.BackgroundColor3, `Status/Track/Fill`.BackgroundColor3, `LevelTrack/Slot<current>`.TextColor3 |
| `Results`, `ResultsTouch` | `Head/Eyebrow`.TextColor3 |

Any other #FFE600 node, or any listed node drawn in another colour, fails `test_hud_templates.py`. State colours (RailTeal for DONE and SPECTATING, Amber and Coral) are written over the accent by the same writer after `Paint`.

---

## 3. Staging in Studio

### 3.1 Layout

```
ReplicatedStorage.ZyntraHUD                 Folder
  Imports                                   Framewisp_Live_HUD_* ScreenGuis: Enabled = false, scripts destroyed (the backup)
    Superseded                              older imports of the same bundle; nothing is ever destroyed
  Templates
    HUD_PC, HUD_Touch, HUD_Screens          clones of the wrappers, carrying BB_DesignW / BB_DesignH / BB_TextFactor + HudTemplateSource
```

The templates are **place data, not scripts.** The sync tools never mirror them. The repo's record is the dumps (§3.4) plus `01`'s report.

The scripts below go in `artifacts/hud-final-20261008/install/` and run through `execute_luau` on the **Edit** data model. They are copies of the shop's, with the differences listed.

### 3.2 `00_stage_hud.luau`: a copy of `00_stage_reimport.luau`

- It creates `ReplicatedStorage.ZyntraHUD`, `Imports` and `Templates` if they are missing. (The shop's version errors instead.)
- `FRAMES = {"HUD_PC", "HUD_Touch", "HUD_Screens"}`.
- It moves **only** a `Framewisp_*` ScreenGui that holds one of `FRAMES`, at depth 1 or depth 2. Any other ScreenGui (a shop import) stays in StarterGui and is reported as `leftInStarterGui`.
- It disables the gui and destroys its scripts. Expect `scriptsRemoved: 3`: FramewispActions, FramewispButtonFX and FramewispTextScaler.
- An older import that holds the same frame moves to `Imports.Superseded`.
- **Expected:** `"ok": true`, and `starterGuiNow` holds no `Framewisp_Live_HUD_*`.
- **Fix the shop's `00_stage_reimport.luau` the same way before its next run.** Today it moves *every* `Framewisp_*` gui into `ZyntraShopUI.Imports`, where `01_hud_templates` would never find a HUD import. The fix is to skip a gui whose `framesOf()` is empty.

### 3.3 `01_hud_templates.luau`: a copy of `01_templates.luau`

**What it does:**
- It finds each wrapper as the depth-1 child of a ScreenGui under `Imports`. If two imports hold the same wrapper, it refuses and writes nothing (`duplicates`).
- It clones the wrapper to `Templates.<name>`, replacing an older clone, so it is idempotent. It destroys any script, carries the ScreenGui's `BB_*` attributes onto the clone, and sets `HudTemplateSource`.

**Checks per bundle.** Any failure sets `ok` to false.

| Check | Pass condition |
|---|---|
| `bb` | `BB_DesignW`/`H` equal 1920x1080, 844x390 and 1920x1080, and `BB_TextFactor` is present |
| `namesKeepingTags` | 0, because lookups assume stripped names |
| `text` | every non-empty text carries `FigmaFontSize`. The number with `FigmaTextW` + `FW_M100` (width-exact) is reported |
| `fonts` | every `FontFace.Family` is Montserrat, RobotoMono, RobotoCondensed or BuilderSans |
| `touchFloor` | every text in `HUD_Touch` and in `*Touch` templates has `FigmaFontSize` ≥ 12 |
| `forbiddenText` | none of: `//`, a leading `> `, `\[[A-Z0-9]{1,3}\]`, `%f[%w]L%d%f[%W]`, ` — `, `•`, `@`, `BACK WHERE`, `ADRENALINE` |
| `images` | the distinct non-empty `Image` ids across ImageLabels and ImageButtons are ≤ `IMAGE_BUDGET`, which is **0** until the owner approves Q8 |
| `canvasGroups` | 0 |
| `missing` | every `REQUIRED` path exists. `REQUIRED` is §2 as a Lua table, `{["HUD_PC"] = {["ObjectiveCard"] = {"Head/Eyebrow", ...}}}`, checked with a base-name descendant walk |
| `listsWhereForbidden` | no UIListLayout is a direct child of `Compass`, `LevelTrack`, `TitleRow`, `Words` or a stack root |
| `hidden` | lists every `Visible = false` node inside a template. It should be empty, since Framewisp imports only visible layers and the HUD uses no tab groups |

**Expected:** `"ok": true`, `images` 0 and `missing` [] for each bundle.

**Rollback:** destroy `Templates.<bundle>`. `Imports` keeps the original.

### 3.4 `02_dump_hud.luau` and the fixtures

This is a copy of `artifacts/shop-ui-figma-20261005/roblox-draft/tools/dump_framewisp_tree.luau` with two changes:
1. The root is `ReplicatedStorage.ZyntraHUD.Templates.<FRAME>` only, so the dump never picks up the `Imports` copy.
2. Every node gets an `Attributes` field: its attributes matching `^Figma`, `^FW_`, `^BB_` and `HudTemplateSource`. The shop harness's `build(spec)` already reads `Attributes`, so the HUD tests need no reconstruction of `FigmaFontSize` from `TextSize`, which the shop test had to do.

Run it with `CHUNK = 1`, read the `chunk 1/n` header, run it again for `2..n`, and concatenate the chunks into:
- `tools/tests/fixtures/hud/framewisp-dump.HUD_PC.json`
- `tools/tests/fixtures/hud/framewisp-dump.HUD_Touch.json`
- `tools/tests/fixtures/hud/framewisp-dump.HUD_Screens.json`

**Commit the three dumps.** Keep each Codex report beside them as `framewisp-import.<bundle>.txt`.

Optional rollback copy: export `Templates` as `.rbxm` through SerializationService (the "Studio native export" memory) to `_local/hud-final/templates/`, with a sha256 per file.

### 3.5 `03_hud_check.luau`: before every Play QA and every publish

It reports `ok` only when all of these hold:
- `Templates` holds the three bundles, each with `BB_*`;
- there is no LuaSourceContainer anywhere under `ZyntraHUD`;
- every ScreenGui in `Imports` has `Enabled = false`;
- **StarterGui holds no ScreenGui whose name starts with `Framewisp_`.**

The last point matters: Auto-sync re-delivers a changed bundle into StarterGui with Framewisp's own runtime scripts. In Play, every PlayerGui would then draw the raw templates over the game; in a publish, so would every player's. The fix is `00_stage_hud`, then this check again.

### 3.6 Offline: `tools/tests/test_hud_templates.py`

It runs on the three dumps and needs no luau. It asserts:
- every `REQUIRED` path exists. The list is parsed out of `01_hud_templates.luau`, so there is one source;
- images 0, CanvasGroups 0 and `namesKeepingTags` 0;
- fonts, the touch floor and the forbidden copy;
- **palette:** every visible fill, text and stroke colour (BackgroundTransparency < 1) is within ±2 of a token. The exception is `Level4Note/Paper`. Framewisp's default 163,162,165 on transparent frames is ignored;
- **accent:** the set of nodes coloured #FFE600 equals the §2.20 map;
- no node is named after a property, and `Who` is used for every DisplayName slot;
- **stack templates:** the parts are full width and tile the root, with heights summing to the root's height ±1 px.

The batch harnesses in BUILD-PLAN §5 (`test_round_hud.py` and the rest) build their fake trees from these dumps with the shop harness's `build(spec)`. Copy it to `tools/tests/hud_harness.luau` rather than importing it across artifact folders.

If a batch's code is written before the import exists, hand-write `hud-tree.contract.json` from §2, in the same format. Otherwise skip it.

---

## 4. Codex computer-use import (Live Sync)

### 4.1 Preconditions

- [ ] F2 lint is empty, and the three wrappers are recorded here:

  | Bundle | Node id | URL |
  |---|---|---|
  | `HUD_PC` | `313:2` | https://www.figma.com/design/7FXycGKH6OT6Lme6FV3VBc?node-id=313-2 |
  | `HUD_Touch` | `314:2` | https://www.figma.com/design/7FXycGKH6OT6Lme6FV3VBc?node-id=314-2 |
  | `HUD_Screens` | `315:2` | https://www.figma.com/design/7FXycGKH6OT6Lme6FV3VBc?node-id=315-2 |

  The page is "HUD Framewisp export 2026-10-08" (`311:2`). The wrappers are named `HUD_PC_nolist`, `HUD_Touch_nolist` and `HUD_Screens_nolist`. Phase A found 0 image-baking nodes in all three.

- [ ] Today's conversion count is known, and the planned sends fit in 5 (§4.6).
- [ ] The HUD session holds `_local/studio-lock.json`. At 2026-10-08 15:00 it was queued as "Design new lobby shop UI" behind the Level 2 session.
- [ ] Studio is open on the game place, in Edit, with no Play running. `03_hud_check` reports no leftover `Framewisp_*` in StarterGui, so the new item is unambiguous.
- [ ] The allowlists are edited (§4.2).

### 4.2 Allow Figma for computer use, temporarily

Run 2 on 2026-10-06 was refused with "Computer Use was not approved to use Figma". Add Figma before the run and **remove it afterwards**. Edit only these entries; never restore a whole file from a backup.

`~/.codex/config.toml` (today it holds only Studio):
```toml
[computer_use.windows.always_allowed_app_ids]
"robloxstudiobeta.exe" = true
"figma.exe" = true          # added for the HUD import; delete this line afterwards
```

`~/.codex/computer-use/config.toml`:
```toml
[apps]
allowed = ["robloxstudiobeta.exe", "figma.exe"]   # afterwards: ["robloxstudiobeta.exe"]
```

Codex 0.159.2 logged `computer_use.windows.always_allowed_app_ids is ignored` in run 6. The `computer-use/config.toml` list is the one that took effect, but the owner's recipe edits both, so edit both and revert both.

### 4.3 Prompt template

Save one prompt per run in `_local/hud-final/codex-import/` (not committed). Run 1 sends `HUD_PC`. Run 2 sends `HUD_Touch`, then `HUD_Screens`.

```
You are doing ONE bounded desktop task with computer use on the owner's Windows PC. Do NOT run git. Do NOT edit any
files except your report and screenshots in this folder.

GOAL: send <ONE FRAME | TWO FRAMES, one after the other> from Figma to the already open Roblox Studio place (window
title contains "BACKROOMS: STAY QUIET") with the Framewisp plugin's LIVE SYNC ("Live from Figma" / "Send to Studio").
Each send is one conversion of the owner's daily Framewisp limit.
<For each bundle:> Frame <HUD_PC> on the page "HUD · Roblox export" of the Figma file "Backrooms Stay Quiet — Shop UI":
https://www.figma.com/design/7FXycGKH6OT6Lme6FV3VBc?node-id=<id>
It is a temporary wrapper (<1920 x 1080 | 844 x 390>) holding many small HUD templates, some overlapping. That is intended.

IMPORTANT, owner's order: Live Sync and Auto-sync are ON in both Figma and Studio and must STAY ON. NEVER switch Live
Sync, Auto-sync or any other Framewisp toggle off, and never press "Pause automatic sync". Use Live Sync, not Code mode.
If Studio's Framewisp panel is closed you MAY open it (Plugins tab > Framewisp) and choose "Live from Figma"; if a
toggle shows OFF there you MAY switch it ON.

STUDIO LOCK: you are acting FOR the session titled "<holder>", the current holder of
G:\Roblox\MongoTV\_local\studio-lock.json. It delegates exactly this Live Sync send/import to you. Do not edit the lock
file. The owner explicitly approved computer use for the Figma desktop app and Roblox Studio for this import.

STEPS (per frame):
1. Figma desktop: open the URL so that exactly that frame is selected: the frame itself, not a Section, not a child.
   The right panel must show ONE frame of the size above with that exact name.
2. Open the Framewisp plugin (right-click > Plugins > Framewisp) and pick Live / "Send to Studio".
3. IMAGE GATE, before pressing Send: read the line "This selection: N image(s)". If N is not 0, STOP. Do not send.
   Screenshot it as blocked-hud-<n>.png and report N. (Images are uploaded to Roblox on the owner's account.)
4. Press Send to Studio ONCE. Wait for "Delivered to Studio" / "Studio confirmed". Copy every message and warning the
   plugin shows into report-hud-<n>.txt, including the "Interactive buttons detected", tag-conflict and UIListLayout
   lists.
5. In Studio, check that the Framewisp panel reports the import as done. Expand ONLY the new item in StarterGui
   (Framewisp_Live_<frame>) and screenshot it as import-hud-<n>-<frame>.png. Copy the [Framewisp] lines from Output,
   including "text N width-exact, M fallback", into the report.
6. Two-frame run only: do the second frame only if the first one fully succeeded.

HARD LIMITS:
- In Studio use ONLY the Framewisp panel and the Explorer's expand arrows. Do not press Play, Save, Publish or Undo.
  Do not edit, move, rename or delete anything. Do not close Studio.
- In Figma, do not edit the design; only select and use the plugin.
- STOP at once, with a screenshot (blocked-hud-<n>.png) and the exact text, if Framewisp asks for a login, API key,
  payment or upgrade, or reports an error, the daily conversion limit, or a node or size limit.
- Record an "images did not load" message, but do not stop for it; press "Retry unresolved images" at most once.
- Any other dialog you are unsure about: stop and report it. Do not guess.
- Send each frame only once. Never retry a failed send.
- Only an error that appears AFTER you press Send counts. Earlier Output lines belong to other work.

When finished, write report-hud-<n>.txt with: whether each send and import succeeded; the exact new StarterGui item
names and their children; every warning; and the state of Live Sync and Auto-sync at the end (they must be ON).
```

### 4.4 Command

The session runs it from Bash on the PC:
```
CX=$(ls /c/Users/mikke/AppData/Local/OpenAI/Codex/bin/*/codex.exe | head -1)
W=G:/Roblox/MongoTV/_local/hud-final/codex-import
"$CX" exec --enable computer_use -m gpt-6.1-sol -C "$W" - < "$W/prompt-hud-1.txt" > "$W/codex-run-hud-1.log" 2>&1
```
- If the model is refused or at capacity (EXIT 1), use `-m gpt-6-sol`.
- On EXIT 1 after a send, read the report and inspect StarterGui. **Never** re-launch a prompt that would send again.

### 4.5 After each run

1. Read the report and the screenshots. Confirm that Live Sync and Auto-sync are ON.
2. Revert both allowlists (§4.2). Keep them only if the second run follows within the hour, and revert after that one.
3. Run `00_stage_hud`, then `01_hud_templates`, then `02_dump_hud` (§3). Then run `test_hud_templates.py`.
4. After run 1 only: if `01` or the test fails on something systematic (text baked to images, tracking, a wrong name pattern), fix the Figma page **before** run 2. The other two bundles would repeat the mistake.
5. Run `03_hud_check`. Release the Studio lock if nothing else follows.

### 4.6 Conversion budget

Framewisp's free plan allows **5 conversions a day**, reset at 00:00 UTC (02:00 in Copenhagen).

| # | Bundle | Note |
|---|---|---|
| 1 | `HUD_PC` | Alone, so a systematic fault costs one conversion, not three |
| 2 | `HUD_Touch` | Codex run 2 |
| 3 | `HUD_Screens` | Codex run 2, only if #2 succeeded |
| 4-5 | Reserve | At most one batched re-send per bundle that failed `01` |

- **A re-import costs far more than one conversion.** It also costs:
  - a Codex run (about 1 % of weekly Codex usage);
  - `00`, `01` and `02` again, plus a fixture refresh and every harness re-run;
  - and a moved or renamed node breaks code.

  So fix in **code** anything code can own (a colour, a text, a visibility). Re-import only for structure, names or a baked node, and batch every fix into one re-send per bundle.
- **Auto-sync.** While Framewisp's Figma window is open, editing a sent wrapper re-sends it into StarterGui. Assume that counts as a conversion.
  - Do not touch a sent wrapper except for a planned re-import.
  - After any Figma edit session, run `00_stage_hud` and `03_hud_check` before Play or publish.
  - Do not pause or switch off Auto-sync to avoid this (owner's order).
- **The plan may have changed.** Run 6's panel read "Monthly · 37 days · Nov 11, 2026" and "8 image(s) · 1000 allowed", so the plan may now be paid. This contract keeps 5 a day and 0 images regardless; the image rule is about moderation, not quota. Ask the owner only if a sixth conversion is ever needed in one day.

---

## 5. How the code binds (B1-B8)

### 5.1 The template API in `ReplicatedStorage.RoundHud` (added in B1)

`RoundHud` requires **`ReplicatedStorage.ZyntraShopUI.ShopBinder`** for `at`, `find`, `designSize`, `scaleText`, `strip`, `button`, `image`, `flowRow` and `Palette`. It does not copy them. ShopBinder is pure and already in the place.

| Function | Does |
|---|---|
| `RoundHud.Template(bundle, path)` | Returns `Binder.at(Templates[bundle], path)`. If it is missing, warns once per path (`[RoundHud] missing template: HUD_PC/ObjectiveCard/Head`) and returns nil. |
| `RoundHud.Mount(bundle, path, parent, opts)` → `clone` | Clones the node, then: `design = Binder.designSize(templateNode)` (measured in the template, where the Scale chain to `BB_DesignW` is intact; Binder.skin's graft trick); `Binder.strip`; `Size = fromOffset(design × s)` with `s = opts.Scale or 1`; AnchorPoint and Position reset for the caller; `TextWrapped` on multi-line boxes (§2.0 rule 7); `Soften` on each `Soft`; `MinTextSize` 12 on the touch layout; `Name = opts.Name` (the "Mounted as" name); parent; then `Binder.scaleText(clone, design, BB_TextFactor)`. With `opts.Attention`, it wraps the clone in a CanvasGroup for `Attention`. It never resizes the root afterwards. |
| `RoundHud.Stack(bundle, path, parent, opts)` → `container, parts` | Makes an auto-height vertical list Frame that copies the root's look (fill, UICorner, UIStroke, UIGradient), mounts every direct child part in design-Y order, and returns `parts[name]`. Callers hide parts. |
| `RoundHud.Paint(root, templateName, level)` | Writes the §2.20 accent paths from `UIStyle.Hud` accent[level]. |
| `RoundHud.Keycap(chip, keyboard, gamepad)` | Writes `Key`, or the `GetImageForKeyCode` glyph into `GlyphSlot` (`Binder.image`), or hides the chip on touch. |
| `RoundHud.Ring(slot)` → `set(fraction, colour)` | The code-drawn ring sweep: two half-masks with UIGradient. |
| `RoundHud.Soften(node)` | The soft-Ink UIGradient transparency, 0.35 → 1. |

The device pick is the same everywhere:
- the touch layout (`UIDevice` touch tier) uses the `HUD_Touch` and `*Touch` templates;
- everything else, gamepad included, uses the PC templates;
- P4's 240 pill is the only compact-tier rule, and it is baked into `ObjectivePill`.

### 5.2 Per batch

| Batch | Script (owner of logic and gui) | Mounts | Into (gui, order) | Mounted as |
|---|---|---|---|---|
| B1 | **new** `RoundHud` | API §5.1; `Detector` → `HUD_PC/DetectorCard` or `HUD_Touch/DetectorLine` | `RoundHud` (10) | `DetectorCard` |
| B1 | FlashlightController | `HUD_PC/FlashlightWidget` (PC and pad only) | widget gui (61) | `FlashlightWidget` |
| B1 | ProtectionHUD | `HUD_PC/EquipmentPanel` and `HUD_PC/EquipmentCaption` (PC and pad) | `ProtectionHUD` (1001) | same names |
| B1 | ZyntraDetectorClient | calls `RoundHud.Detector`. `ZyntraDetectorReadout` (1100) is deleted | — | — |
| B2 | NoiseReporter | `HUD_Touch/TouchCluster/Cell_Jump`, `Cell_Run`, `Cell_Sneak` and `Cell_Glow`, at `ControlPlan` rects | its touch gui | the cell names |
| B2 | FlashlightController | `HUD_Touch/TouchCluster/FlashlightPower` | its touch gui | `FlashlightPower` |
| B2 | ProtectionHUD | `TouchCluster/Cell_Kit`, `Cell_Shield` and `HUD_Touch/KitFan` | `ProtectionHUD` | the cell names, `KitFan` |
| B3 | **new** `Round HUD` | `HUD_PC/NoiseMarker` (PC and touch); the chase edge is code | `RoundHud` (10), `RoundHudThreat` (20) | `NoiseMarker` |
| B3 | NoiseReporter | `HUD_PC/StaminaBar` (PC and pad) | `StaminaGui` (60) | `StaminaBar` |
| B4 | `RoundHud.ObjectiveCard`, fed by PuzzleUI, Level 2 Objective UI, Level 3 Reader Client and Level 4 Round Client through `SetObjective` | `Stack HUD_PC/ObjectiveCard`, or `Stack HUD_Touch/ObjectivePill` on touch; `Paint` by level | `RoundHud` (10) | `ObjectiveCard` |
| B5 | `RoundHud.Feed` / `Caption`, with `Round HUD` driving `RoundStatus` | `HUD_PC/FeedRow` ×2 and `HUD_PC/Caption`, or `HUD_Touch/FeedRowTouch` ×1 and `CaptionTouch` | `RoundHud` (10) | `FeedRow1`, `FeedRow2`, `Caption` |
| B6 | Found Footage HUD (pulled in B0) | `HUD_PC/RecLine`, `HUD_PC/Bracket` ×4 (PC and pad), `HUD_PC/PromptPlate` (keyboard and pad), `HUD_Touch/PromptPlateTouch` (touch) | its gui (12) | `RecLine`, `Bracket1`-`Bracket4`, `PromptPlate` |
| B6 | Round Exit Client | `HUD_PC/LeaveChip`, `LeaveChipWide` and `RoundExitNotice` (PC and pad), or `HUD_Touch/LeaveChipTouch`; `HUD_PC/RoundExitCard` (both, scaled to fit the safe area on touch) | `RoundExitGui` (70) | `RoundExitCard`, `HoldFill`, `HoldHint`, `Notice` as pinned |
| B6 | SpectateController | deletes `SpectatorCounter`; the count moves to `RecLine/Watching` | — | — |
| B7 | Level 3 Table Hiding Client | `HUD_Screens/HidingBanner`, `LeaveHiding` and `TableCheck`, or their `*Touch` versions | `Level3TableHideUI` (92) | same names |
| B7 | Level 4 Round Client | `HUD_Screens/Level4Note` (touch s ≈ 0.89) and `HUD_Screens/Keypad` (touch: scaled to 300 tall) | `Level4RoundGui` (6 → **60**) | same names |
| B8 | RoundUI death do-block | `Stack HUD_Screens/DeathCause` or `DeathCauseTouch`; `DeathCauseDocked` or `DeathCauseDockedTouch` | RoundUI gui (100) | `DeathCause` |
| B8 | RoundUI party-down do-block | `HUD_Screens/PartyDownCard` or `PartyDownCardTouch`, plus `HUD_PC/Bracket` ×4 on PC, into the code-made `PartyDownOverlay` | RoundUI gui | `PartyDownCard` |
| B8 | RoundUI results block | `Stack HUD_Screens/Results` or `ResultsTouch` into `RoundEnding`; rows into a code Frame `PartyChoices` | RoundUI gui | the pinned names |
| B8 | RoundUI loading block | `HUD_Screens/LoadingCard` or `LoadingCardTouch` into `LevelLoading` (code black); `Paint` by level | RoundUI gui | `LoadingCard` |
| B8 | SpectateController | `HUD_Screens/SpectateBand` or `SpectateBandTouch`, and `SpectateBackToLobby` | `SpectateGui` (58) | `SpectateBand`, `SpectateBackToLobby` |

### 5.3 Rules for every batch

- **RoundUI is at the 200-register limit.** Each RoundUI do-block does its own `local Hud = require(ReplicatedStorage:WaitForChild("RoundHud"))` **inside the block**, and keeps its mounts in fields of its existing table (`dc.card`, `pd.card`, ...). There is no new top-level local. Run `luau-compile` and the compile probe after every RoundUI edit (BUILD-PLAN §1.6).
- **ScreenGui names and DisplayOrders stay as in BUILD-PLAN §1.4.** Only what is drawn inside them changes.
- **A missing template means a warning by path and no drawing of that element.** There is no `Instance.new` fallback, the same contract as the shop go-live. `03_hud_check` is what keeps a place without templates from being published.
- **Each batch's QA starts with `03_hud_check`**, and its offline tests load the committed dumps.
- **The code writes only the dyn slots, state colours and Visible flags of §2.** It never moves or resizes a node inside a mounted template. The exceptions are `Compass/Chevron`, the `Fill` widths, and `Soft` or `Plate` hugging.

---

## 6. Open items

- **Q8, icons** for the chips, the KIT fan and the door chip. The default is frame-built icons with 0 images. With the owner's OK, at most 4 images in `HUD_PC`, reused in `HUD_Touch` with no new uploads.
- **The phone re-layouts in §1.7** go into the handover for the owner's TOUCH QA in B7 and B8.
- **DECIDING chip:** a solid Sage stroke replaces the dashed one, because a dashed stroke is not native.
- **Level 4 note:** the code sets the PatrickHand face. Its exact look depends on B0 re-reading L4C.
- **Esc on the death card** (BUILD-PLAN risk 8) is unchanged by this pipeline. The `Esc` keycap is only a drawn chip.
