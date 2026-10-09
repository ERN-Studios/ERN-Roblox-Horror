# In-round HUD · build plan · 2026-10-08

> **APPROVED 2026-10-08.** The owner approved the combined mockup (Figma page "Final HUD 2026-10-08", 267:2) with seven changes: P1-P4 on phone and G1-G3 on all platforms. `OWNER-PICKS.md` records them under "Approved with changes". This plan already includes them in §1.2, §1.3, §1.5, §2 (01, 04-06, 07, 13, 17, 18, 19), §3.3, §4, §5, §6 and §7. Later the same day he replaced the level colours (LEVEL 1 yellow, 2 blue, 3 red, 4 neon pink, 5 silver white, 6 violet; §1.2, §3.3) and replaced the "??? EXIT?" title. LEVEL 2 is now UNRECORDED and LEVEL 5 is ??? WHERE?, with an optional random draw from the 9-title pool (§17, §7 Q12 answered).

This plan covers building the HUD the owner picked, element by element. Nothing here has been built. No source file, Studio or Figma was touched to write it.

**Read first.**
- `artifacts/hud-final-20261008/OWNER-PICKS.md`: the authoritative picks.
- `_local/rail-and-hud/hud-brief.md`: inventory, problems, positions and per-level content. "Brief §n" below points into it.
- `artifacts/hud-element-sheet-20261008/INDEX.md` and its PNGs. Each tile is drawn at **2x** game size, so in-game px = tile px ÷ 2.

**Two corrections to the task framing.** OWNER-PICKS.md records two answers the owner gave later on 2026-10-08. They supersede "still open":
1. **"BACK WHERE YOU FELL" is removed.** The line exists only in the Figma tile (no source file contains it), so the job is simply never to build it. Check that the combined mockup drops it.
2. **The sneaking marker stays, Level 2 included.** The "open question" label on the Level 2 marker in the mockups should go.

**Studio is reachable only from a session on the owner's PC** (`uname -s` ≠ Linux). Every batch below has a repo half (any session) and a Studio half (local only).

---

## 1. Architecture

### 1.1 What goes where

Each level script and system script stays the owner of its own data and logic. Only the drawing moves. Two new scripts render the components that are shared:

| New script | Kind | Owns |
|---|---|---|
| `ReplicatedStorage.RoundHud` | ModuleScript | The `RoundHud` ScreenGui (DisplayOrder 10) and the shared C components: `Attention` (the C visibility rule), `Keycap` (glyph chip via `UIDevice.Binding` and `GetStringForKeyCode`/`GetImageForKeyCode`), `ObjectiveCard` (PC card, phone pill and compass), `Feed` (event rows and captions), `DetectorCard`. Its API: `SetObjective(state)`, `Feed(row)`, `Caption(speaker, text)`, `Detector(reading, expiresAt)`, `Clear()`, `LastObjective()`. |
| `StarterPlayerScripts."Round HUD"` | LocalScript | The cross-level drivers that have no other owner: the team, death and escape feed from `RoundStatus` (it **replaces Team Objective Feed**), the sneak/loud marker, the re-entry grace pill, the chase edge (ScreenGui `RoundHudThreat`, DisplayOrder 20), and `RoundHud.Clear()` when `InRound` goes false. |

**Why a module and not one LocalScript that does everything.** The level scripts hold the hard parts. The Level 3 reader alone is 1,233 lines of signal logic, and Level 4 reads a state folder. Moving that logic would be a rewrite. Each level script replaces its panel code with calls such as `RoundHud.SetObjective{...}`. On one client, `require` returns the same module table to every LocalScript, so there is one card and one feed.

`execute_luau` gets its own module instance (CLAUDE.md, 2026-09-03). Studio QA therefore reads the GUI text and attributes, never module state.

**Restyled in place** (the owner script keeps both its data and its drawing):
- FlashlightController (07)
- NoiseReporter (10, 14)
- ProtectionHUD (08, 14)
- ZyntraDetectorClient (09, via `RoundHud.Detector`)
- Round Exit Client (13)
- SpectateController (19)
- Level 3 Table Hiding Client (15)
- Level 4 Round Client: note and keypad (16)
- Found Footage HUD (01, 12)
- RoundUI do-blocks (17, 18, 20, 21)

**Retired:**
- `Team Objective Feed` (merged into Round HUD)
- the PuzzleUI objective card, toggle and compass
- `Level2ObjectiveGui`
- the Level 3 reader panel and toast drawing
- the Level 4 objective panel, HIDDEN/CARRYING chips and `say()` drawing
- the Level 2 alert toast drawing
- the MISSION BRIEF button and the ESCAPE PROCEDURE panel inside `LevelOneGuideGui` (owner OK needed, §7 Q4)
- the `FlashlightPopup` dead-battery strip

### 1.2 Tokens: `UIStyle.Hud` (extend the existing shared-look module)

| Token | Value | Source |
|---|---|---|
| Ink / Tile / Line | 5,9,11 / 22,29,32 / 38,49,52 | ShopBinder `P` (SB:31-46) |
| Cream / Sage | 242,235,219 / 167,184,174 | same |
| IconTeal / RailTeal | 75,180,176 / 68,221,196 | same |
| Amber (warning; owner OK'd in rounds) | 232,160,36 | same |
| Coral (danger) | 242,112,95 | same. PARTY DOWN's 255,116,96 (RUI:4977, 4994) is retired |
| Level accent | L1 255,230,0 (#FFE600 yellow), dim 158,143,0 (#9E8F00) · L2 77,163,255 (#4DA3FF blue), dim 48,101,158 (#30659E) · L3 255,0,0 (#FF0000 red), dim 184,0,0 (#B80000) · L4 255,70,200 (#FF46C8 neon pink), dim 158,43,124 (#9E2B7C) · L5 212,220,232 (#D4DCE8 silver white), dim 131,136,144 (#838890) · L6 156,134,255 (#9C86FF violet), dim 97,83,158 (#61539E) | owner 2026-10-08, second pass: "Farve for level 1: gul, 2: blaa, 3: roed, 4: neon pink, 5: graa/hvid, 6: violet". Replaces #69E687 / #69DEEE / #F6B088 and the Sage placeholder on L5 (`OWNER-PICKS.md`). Dims are 0.62 x the accent, L3 0.72. L5 and L6 appear only on the loading cards (17) |
| Loading background | 0,0,0 (#000000), opaque | owner G3: "Det skal bare vaere sort" |
| Fonts | `Font.new("rbxasset://fonts/families/RobotoMono.json", Bold)` for tags and the REC line; Montserrat SemiBold/ExtraBold/Black; RobotoCondensed Black for numerals | built-in families, no upload |
| Soft Ink | a UIGradient from Ink at 0.35 → 1, used instead of a plate | C "on soft Ink" |

`test_ui_style.py` asserts that these equal the ShopBinder palette, and that the level accents equal `RoundUI.LOADING_PALETTES[n].Title`. These are copies with a test, not a new dependency of RoundUI.

### 1.3 C visibility rule (`RoundHud.Attention`), numbers read off the tiles

| Element | On change | Rest | Never dims |
|---|---|---|---|
| Objective card / pill / compass (04-06) | 100 % for 6 s | 45 % | DANGER row. WARNING rests at 45 % like the card |
| Sneak marker (03) | 100 % for 6 s | 45 % (LOUD 60 %) | — |
| Equipment chips (08) | 100 % for 6 s (on use / change) | 40 %; all empty → hidden | ACTIVE, REFUSED |
| Detector (09) | 100 % for 4 s after a scan | hidden | HIGH |
| Stamina (10) | 100 % while draining | recovering 55 %; full → hidden | WINDED until it recovers |
| Leave chip (13) | 100 % on hover / hold | 50 % | — |
| Hiding banner / button (15) | 100 % for 6 s | 45 % / 55 % | TABLE CHECK |
| Spectate band (19) | 100 % for 6 s | 45 % (text only, no plate) | — |
| REC (01, B), flashlight (07, B) | always on, **PC and gamepad only** | — | — |
| Death card (18) | shown on death | — | never dims; it closes only when the player closes it |

Fades are 0.18 s in and 0.4 s out (Brief §4). The sheet's "hidden (12 % ghost)" is a drawing convention; in game these elements are `Visible = false` (§7 small call).

The implementation is a `CanvasGroup` per element, with tweened `GroupTransparency`. If CanvasGroup text is soft on low-end phones, `Attention` falls back to walking the descendants and setting Text/Background transparency. That fallback is one function and no caller changes.

### 1.4 DisplayOrder ladder (minimal change)

| Order | Gui | Change |
|---:|---|---|
| 10 | `RoundHud` (card, pill, compass, feed, captions, marker, detector) | new. The detector moves down from **1100** |
| 12 | Found Footage HUD (REC frame, prompt plates) | set on restyle. The value today is unknown until the pull |
| 20 | `RoundHudThreat` (chase edge) | new |
| 58 | SpectateGui | unchanged |
| 60 | StaminaGui | unchanged |
| 61 | flashlight widget gui (was `FlashlightPopup` at 60) | today two guis tie at 60 and their order is undefined |
| 60 | Level4RoundGui (note, keypad, title cards) | **6 → 60**. Today the note sits under the whole HUD |
| 70 | RoundExitGui | unchanged |
| 92 | Level3TableHideUI | unchanged |
| 100 | RoundUI (loading ZIndex 100, death card 96/118, PARTY DOWN 112, results 120) | unchanged |
| 120 | ZyntraStore re-entry modal | unchanged |
| 1000 | JumpscareGui | **unchanged** |
| 1001 | ProtectionHUD | unchanged. It must stay above the kill cam, because the shield cancels a Level 1 capture (PHUD:74-76). It now **hides while `PartyDownCardOpen` is true or `RoundActive` is false**, which fixes the HUD showing through results and PARTY DOWN (brief problem 9) without moving the kill cam |

The brief's full re-ladder (kill cam at 90) is rejected. With the kill cam below RoundUI, PARTY DOWN's full-screen NO SIGNAL (B) would cover a solo player's jumpscare.

### 1.5 Screen map

The PC column is 1920x1080 with the topbar at 0-58, so content starts at y 74. The phone column is 844x390: safe area x 47..797, y 58..369, and the thumbstick zone x 0..338 by y 130..390 stays empty. Every position comes from `UIDevice.Layout()` / `TopRightPanel` / `LocalPosition`, never from fixed pixels. Level 4 ignores UIDevice today (brief problem 4).

| Zone | PC | Phone |
|---|---|---|
| Top-left | Leave chip (13) at Safe.Left+24, then REC (01) at +72 on the same row. Corner brackets in all four corners | **Leave chip only**, x 59, y 64, 44x44 (owner P2). No REC, no SIGNAL, no watcher count and no corner brackets on phone (owner P3). Nothing else may enter x 59..103 by y 64..108 |
| Top-centre | Feed (11), ≤560 wide, 2 rows. While hiding in Level 3, the hiding banner (15) takes y 74 and the feed drops below it | Feed x 115..473, 1 row. The detector card (09) sits under the feed |
| Top-right | Objective card (04/06) `TopRightPanel(360, h)` → x 1536..1896 | Pill (05) `TopRightPanel(240, h)`, about 80 % of the drawn 300 (owner P4). Its height is already clamped above the cluster |
| Bottom-left | Flashlight B (07) at Safe.Left+24, bottom −24. Chips (08) to its right with a 16 px gap. Detector card (09) above the SCAN chip | Thumbstick zone: nothing. There is no flashlight widget on phone; the battery lives only in the LIGHT button (owner P1) |
| Bottom-centre | Stamina (10) 320x6 at bottom −24, marker (03) centred above it, captions (11) above that. Death card (18) and spectate band (19) appear only when dead, when the first two are gone | Marker centred in `Layout().Corridor`. Stamina becomes the RUN ring (14) |
| Bottom-right | free | Touch cluster 14 A + KIT fan |
| Centre | Note and keypad (16), leave confirm (13), PARTY DOWN (20), results (21), loading (17) | same, scaled |

**What "phone" means for P1-P4.**
- **P1-P3** key on the touch layout (`UIDevice` touch tier, i.e. the touch cluster is drawn), so a tablet follows the phone.
- **P4** (the 240 pill) keys on the compact touch tier only (`fit.Compact and fit.Touch`, as ZyntraStore uses it).
- **Gamepad** on a TV keeps the PC look.

This is a small call (§7).

### 1.6 Rules that bind every batch

- **RoundUI is at Luau's 200-register limit.** Make no new top-level `local`. New state goes in `do ... end` blocks or in fields of existing tables; restyle by mutating existing instances. B0 and B4 free registers by deleting dead code. Run `luau-compile` (test_death_advice.py already does it) and `tools/studio_compile_probe.luau` after every RoundUI edit.
- **New scripts are installed through `tools/install_new_scripts.py`**, which also writes the manifest item. It embeds source with `json.dumps`, so source must be **ASCII only**. Write `·` as `\u{B7}`, `●` as `\u{25CF}`, `‹ ›` as `\u{2039}` `\u{203A}`, `»` as `\u{BB}`, `↑ ↓` as `\u{2191}` `\u{2193}`, `◀ ▶` as `\u{25C0}` `\u{25B6}`. Use the same escapes in edited HUD strings so the copy lint (§5) can check one form.
- **Copy rules, for visible text only:**
  - no `//`, no `>` prompts, no `[X]` keycaps (keycaps are chips), no `L1`-`L4` (write `LEVEL 1`);
  - separator ` · `; CAPS for tags, titles and buttons; sentence case for guidance, captions and the death cause and tip;
  - players are named by `DisplayName`, never by `@Username`.
- **No uploads.** Build everything from Frames, UIStroke, UIGradient and text glyphs. The account was banned for 7 days on 2026-10-07; icons are an owner question (§7).
- **Before each Studio push:**
  - run `git status` for foreign untracked files, then `pull_source_from_studio.py --audit`;
  - Studio lock `_local/studio-lock.json`;
  - `push_repo_to_studio.py --studio-name "(UPDATE) BACKROOMS: STAY QUIET"`;
  - merge any CONFLICT, never `--overwrite-conflicts`.

  The manifest marks every HUD script `synced` while the 2026-10-07 parity dump says seven have drifted. **The manifest is not evidence.**

---

## 2. Per element

Format per element: **owner today → change → data → states → layout (PC / touch / gamepad) → accessibility → tests.** Cites come from the brief and are PLAUSIBLE for the drifted scripts until those are re-read (B0).

### 01 · Timer · REC: **B**; its WARNING state is **C**. **PC only** (owner P3)
- **Today.** Found Footage HUD (Studio only, 13,623 B, not in the manifest) draws `● REC 00:00:09` and the corner brackets. SpectateController draws "N SPECTATORS WATCHING" top-centre (SPC:305-333).
- **Change.**
  - Restyle in place in Found Footage HUD after the B0 pull. The line becomes `● REC 02:37   SIGNAL ▮▮▮▯`, plus ` · 1 WATCHING` when the player's own `SpectatorCount` > 0. On PC the brackets stay (the owner keeps the REC frame).
  - **On the touch layout, Found Footage HUD draws neither the REC line nor the four corner brackets** (owner P3). There is no replacement. A watched phone player gets no watcher count, because SPC's counter is deleted below. The prompt plates (12) in the same script are unaffected.
  - Delete SPC's counter label; the count now lives on the REC line.
  - WARNING is the C amber status row inside the objective card ("Main breaker: fuse 42 s"), so it is built under 04. Nothing about it goes on the REC line.
- **Data.**
  - Round clock: if Found Footage HUD's timecode is not round-relative, GameManager publishes `workspace.RoundStartedAt = GetServerTimeNow()` beside both `RoundActive = true` writes (GameManager:3050, 3086). REC shows `GetServerTimeNow() - RoundStartedAt`, the same number on every client.
  - `SpectatorCount` is already replicated (GameManager:1438-1460).
  - SIGNAL bars: static (§7 Q2).
- **States.** NORMAL, WATCHED. Hidden outside `InRound`, under the loading cover and on the touch layout. Never dims.
- **Layout.** PC: Mono Bold 14 at Safe.Left+72, y Safe.Top+16. Phone and tablet: not drawn. Gamepad: as PC.
- **Accessibility.** No jitter and no blinking dot. B's jitter belonged to B's chase edge, which was not picked.
- **Tests.**
  - `test_round_hud.py`: mm:ss, h:mm:ss past 60 min, WATCHING only when > 0.
  - Update `test_spectator_count.py`: the count is drawn by the REC line, and SPC no longer draws it.
  - `test_prompt_plate.py` (pulled source): the touch layout hides the REC line and all four brackets, and the plates still draw.

### 02 · Chase edge: **A · REDUCED FLASHING** (static coral, no pulse)
- **Today.** Nothing on screen. Level 1 has camera shake (EntityShakeController); Level 2 has the Pool Foam grade.
- **Change.** New, in Round HUD. ScreenGui `RoundHudThreat` (order 20, `IgnoreGuiInset`), four edge Frames with a coral→transparent UIGradient, `Active = false`. Static at **0.8** transparency for every player. Only the edge drawn at 50 % in the A RF tile is built; there is no pulsing variant at all.
- **Data.** Player `BeingChased == true`. Writers:
  - Level 1 EntityAI `setChaseMarker` (1153-1158);
  - Level 3 Mall Manager (259-263);
  - Level 2 Pool Foam (691/694).

  Shown only while `InRound`, alive, not `Spectating`, not `Escaped`, **and `SelectedLevel ~= 2`**: the owner wants no chase edge in Level 2, even while the live Pool Foam still sets the flag. Level 4 has no `BeingChased` writer, so there is no edge there (§7 Q7).
- **States.** off / on. The 0.18 s in and 0.4 s out fades are opacity ramps, not flashes.
- **Layout.** Full screen on every device. The edge depth is 12 % of the shorter viewport side.
- **Accessibility.** Identical with and without ReduceFlashing, because the picked variant already is the reduced one.
- **Tests.** `test_round_hud.py`:
  - truth table (levels 1-4, spectating, escaped, dead);
  - the transparency is the same constant for `ReduceFlashing` true, false and nil;
  - no `os.clock` or `sin` term on the edge path.

### 03 · Sneak / loud marker: **C, without ADRENALINE**
- **Today.**
  - The marker is not drawn. Only the touch SNEAK ring shows crouch (NR:589-598).
  - Re-entry grace is PHUD's green sentence "You are invisible to monsters\nN seconds" (PHUD:123-130, 313-320, 536-543).
- **Change.**
  - New, in Round HUD. One pill on soft Ink: `● SNEAKING` (RailTeal), `● LOUD` (Amber), `● HIDDEN` (RailTeal), `● INVISIBLE TO MONSTERS · 8 s` (RailTeal). ADRENALINE is never drawn.
  - PHUD's grace notice is deleted.
- **Data.**
  - NoiseReporter publishes the client-local player attribute `MoveNoise` (`"crouch" | "walk" | "sprint"`) from `applySpeed` whenever `state` changes (NR:166-200). That is one `SetAttribute` and no new top-level local.
  - `Level3_Hiding` (Level 3 Hiding Controller).
  - `Level4_Hidden` (Level 4 Objective Controller:949).
  - `PlayerProtectionActive` / `ExpiresAt` / `Source`, read exactly as PHUD reads them today.
  - Priority: GRACE > HIDDEN > LOUD (sprint) > SNEAKING (crouch). Walking shows nothing.
- **States.** As listed. On change 100 % for 6 s, then 45 % (LOUD 60 %).
  - Shown on **every level, Level 2 included** (owner).
  - Not shown while spectating: there is no spectator vital for noise, and none is worth adding.
- **Layout.** PC: centred above the stamina bar (pill bottom at Safe.Bottom−40, 24 tall). Phone: centred at the bottom of `UIDevice.Layout().Corridor`. Gamepad: as PC.
- **Accessibility.** The state is carried by words, not colour alone. No pulse.
- **Tests.** `test_round_hud.py`:
  - priority table;
  - Level 2 shows it;
  - LOUD rests at 60 % and the others at 45 %;
  - the grace text counts down;
  - ADRENALINE never appears.

  Also extend `test_controller_input.py` (it already lifts NoiseReporter blocks) to check that `MoveNoise` follows crouch, walk and sprint.

### 04a / 04b · Objective card · PC: **C** · 05 · Objective pill · phone: **C** · 06 · Exit compass: **C**
- **Today.**

  | Level | Gui (DisplayOrder) | Contents | Cites |
  |---|---|---|---|
  | Level 1 | `PuzzleGui` (18) | card, toggle, private message, compass | PUI:181-307, 581-724, 993-1378 |
  | Level 1 | `LevelOneGuideGui` (110) | MISSION BRIEF / ESCAPE PROCEDURE | RUI:2301-2562 |
  | Level 2 | `Level2ObjectiveGui` (40) | objective panel | L2O:24-267 |
  | Level 3 | `Level3ReaderGui` (42) | reader panel | L3R:49-212, 924-1060 |
  | Level 4 | `Level4RoundGui` (6) | panel, HIDDEN/CARRYING chips | L4C:82-121, 159-167, 259-306 |

  That is four layouts and four distance units.
- **Change.** The drawing moves into `RoundHud.ObjectiveCard`. Each level script deletes its panel and calls `RoundHud.SetObjective(state)` from the code that fills its labels today.
  - The MISSION BRIEF button and the ESCAPE PROCEDURE panel retire (§7 Q4): `objectivesButton` / `objectivesPanel` / `Title` / `Close` / `Divider` / `Body` / `Layout`, `objectiveCopy`, `refreshObjectivesButton`, `setObjectivesAvailable`, `toggleObjectives` and `OBJECTIVES_ACTION`. That is about 13 top-level RoundUI locals, plus the H / D-pad-up binding.
  - The `LevelOneGuideGui` ScreenGui itself stays for as long as the dead Level 1 and Level 3 briefings still parent their subtitle frame and Sounds to it (RUI:2137-2230, 2564-2635).
  - `LevelOneGuideObjectivesOpen` stops being written. PuzzleUI and Round Exit Client drop their reads of it.
  - The Level 3 reader's R / ButtonY hide toggle and its touch ▾ restore chip retire as well, because the card is always present.
- **State contract** (plain Lua table, diffed by the module to fire "on change"):
  ```lua
  {Level = 3, Eyebrow = nil --[[nil → "LEVEL 3"; Level 4 → "LEVEL 4 · THE LAST SHOW"]],
   Title = "FIND THE CDS", Count = 2, Goal = 5, Tag = "CDS IN THE PLAYER",
   Lines = {"Follow the reader to the next CD."},              -- ≤ 2, sentence case
   Status = {Text = "Main breaker: fuse 42 s", Kind = "warning"}, -- or "danger", or nil
   Compass = {State = "locked", Target = Vector3}, Done = false}
  ```
- **Content.** Brief §4 table, reworded per the copy rules. Specifics:
  - **Level 2:** START THE PUMPS · PUMP STATIONS n/3 · "2 stations left." / "Find the other pump stations." The coral status "The water is no longer safe." appears only when `Level2FoamLethal` flips, so it disappears by itself once Level 2 ships without Pool Foam.
  - **Level 4 LOAD THE PROJECTORS:** "You carry 2 reels." (replaces the CARRYING chip). "Reels: Cafe, Arcade" from `Level4_ReelRooms` (L4C:286-293, in flight in another session; §6 R1). Main-breaker status row: "held by Anna" (Sage), "fuse 42 s" (**Amber: this is 01's WARNING**), "off, in the service room" (Coral).
  - **Level 4 RESTORE THE POWER:** "Order: B1 › B3 › A2 › B2" when known; that line also reopens the note (16).
- **Look** (C tiles). No plate, soft Ink behind.
  - Eyebrow: Roboto Mono caps in the level accent.
  - Title: Montserrat Black, Cream, with a 4 px underbar in the level accent.
  - Counter: Roboto Condensed numeral, then a Mono Sage tag.
  - Progress: 4 px in the level accent on Line.
  - Guidance: Montserrat SemiBold, Sage.
  - Status row: 4 px left bar in Amber (warning) or Coral (danger).
- **States.** COLLAPSED, EXPANDED, DONE (counter and progress turn RailTeal inside the 6 s window), WARNING, DANGER, SPECTATING (eyebrow `WATCHING ANNA · LEVEL 3` in RailTeal), IDLE 45 %.
- **Layout.**
  - PC: always expanded, 360 wide at `TopRightPanel`.
  - Phone pill, **about 80 % of the drawn size (owner P4)**. It still sits top-right in the safe area.
    - Collapsed it is 240x40 (eyebrow, title, count right). The tap hit area stays 44 tall.
    - It auto-expands for 6 s on change and on tap, up to 240x140, clamped above the cluster by `TopRightPanel(240, h)`.
    - Every text size is the drawn size × 0.8, floored at 12 px. So the Mono eyebrow and tag stay at 12, and the title and counter shrink.
  - Gamepad: as PC, no binding needed.
- **Compass (06) inside the card.** 328x32 on PC, 220x20 on the pill (was 276x24).
  - Ticks every 15° across ±60°. The chevron is in the level accent at the bearing (camera look against the target, Y ignored), clamped to the edge as `◀` / `▶` beyond ±60° (BEHIND).
  - Distance in metres: studs ÷ 3.571, as Level 3 already does (L3R:1035), measured **from the watched player's root while spectating**. This fixes L4C:300, which measures from your own body.
  - CALIBRATING: three chevrons and the text CALIBRATING (Level 3 exit).
  - IN THIS ROOM: coral chevron at centre and coral text (Level 3 CD in the current room).
  - ARRIVED: under 8 m, RailTeal "AT THE EXIT".
  - Targets:

    | Level | Target | Condition |
    |---|---|---|
    | Level 1 | `workspace.ExitPos` (PUI:923) | — |
    | Level 2 | `workspace.Level2_ExitPosition` | once `Level2ExitPowered` |
    | Level 3 | the reader's nearest CD or exit position | — |
    | Level 4 | the Cinema 2 screen (L4C:295-300) | — |
- **Accessibility.** IN THIS ROOM is steady for everyone; L3R's pulse (1025-1030) goes. The done state is a colour change, not a blink.
- **Tests.**
  - New `test_round_hud.py`:
    - compass maths (clamp, behind, arrived, metre conversion, spectator origin);
    - the state diff drives on-change;
    - danger never dims, warning does;
    - accent per level;
    - pill collapse and expand timing;
    - pill width 240 on the compact touch tier, and no pill text under 12 px.
  - Port `test_round_exit_hold.py` (references `PuzzleGui`, `Level1Objectives`, `LevelOneGuideGui`), `test_ui_style.py` (`Level1Objectives`, `Level 2 Objective UI`), `test_level1_team_prompts.py` (PuzzleUI) and `test_level3_first_cd.py` (reader).
  - UIRegression rows naming `Level1Objectives` (24), `PuzzleGui` (15), `LevelOneGuideGui` (18), `Level2ObjectiveGui` (12) and `Level3Reader` (28) must move to `RoundHud.ObjectiveCard` in the same batch.

### 07 · Flashlight: **B**, bottom-left corner on PC; **phone: the LIGHT button only** (owner P1)
- **Today.** FlashlightController draws the black, white and yellow torch silhouette with 5 bars in a 72x136 box at bottom-left (FLC:264-350, 456-600). It also draws the "[RB]" caption (370-391), the focus caption (620-644) and the dead-battery strip `FlashlightPopup` (221-262). Below 5 % a press is silently refused (608-618).
- **Change.** Restyle in place. The torch silhouette, the bracket caption and the popup strip go. The new widget is the B tile: keycap `F` chip, a 5-segment battery outline, and a Mono line under it. Lines by state:

  | State | Line |
  |---|---|
  | on | `LIGHT` |
  | off, charging | `LIGHT OFF · CHARGING` |
  | ≤ 2 segments | `LIGHT · LOW` (Amber) |
  | 0 | `LIGHT · EMPTY` (Coral outline) |
  | refused press | `LIGHT · TOO LOW` for 2 s (new; ends the silent refusal) |
  | Advanced Equipment | `LIGHT · WIDE` / `LIGHT · FOCUSED` |
  | spectating | `THEIR LIGHT` |
- **Data.** FLC's own `battery`, `MIN_TO_TURN_ON`, `FlashlightFocused`, `ZyntraOwnsAdvancedEquipment`; while spectating, `SpectateBattery` on the watched player (FLC:897). No new data.
- **States.** As above. Always visible in a round on PC (B has no idle state; §7 Q1).
- **Layout.**
  - PC: bottom-left, Safe.Left+24, bottom −24, about 110x56. Gui order 61.
  - Touch (owner P1, "kun i knappen light"): **no B widget and no separate "LIGHT" label anywhere on screen.** The phone mockups' battery at x 346 is dropped, which closes INDEX.md's open question on its placement. The battery lives only in the 14 A `LIGHT` cell, as its 5 segments; that cell keeps `FlashlightPower` and `RegisterControlRect` (FLC:312-318). The state table maps onto the cell:

    | State | LIGHT cell |
    |---|---|
    | on / off | segments lit / outline |
    | ≤ 2 segments | Amber segments |
    | 0 | Coral outline |
    | refused press | label reads `LOW` for 2 s, then `LIGHT` (no flash) |
    | spectating | not drawn (the cluster is hidden while spectating) |
    | WIDE / FOCUSED | not drawn: the cell has no room, and the beam itself shows it |
  - Gamepad: the keycap shows the R1 glyph through `RoundHud.Keycap`. The "Y: WIDE" focus hint is dropped, because B draws only one key (§7 small calls).
- **Accessibility.** No beam-blink change (that is world light, not HUD). EMPTY does not pulse.
- **Tests.** `test_flashlight_player_control.py`:
  - a refused press sets the TOO LOW line;
  - state → line table;
  - `THEIR LIGHT` while spectating;
  - on touch the B widget is never visible, and the LIGHT cell carries segment count and colour.

### 08 · Equipment chips: **C**
- **Today.** ProtectionHUD panel `EquipmentPanel` (order 1001): an EQUIPMENT eyebrow and four rows with `[Q]`-style text keys and raw server refusal text (PHUD:70-130, 177-249, 351-467, 714-727). Touch squares read "SHIELD\nx3" (546-600).
- **Change.** Restyle in place into a row of 64x64 chips: SHIELD, POTION, MARKERS, SCAN, each drawn only if owned. Each chip has an icon (§7 Q8), a count badge and a keycap below. States per chip:

  | State | Look |
  |---|---|
  | READY | Cream |
  | COOLDOWN | seconds numeral in place of the icon, dimmed face |
  | ACTIVE | RailTeal 3 px stroke with `4.2` over `SAFE` |
  | EMPTY | Tile face at 50 % |
  | REFUSED | Coral stroke and a tag above the row |

  The refusal tag is one of `TOO SOON` / `NOT WHILE HIDING` / `NO MARKERS LEFT` / `NOT NOW`, one at a time. Raw server strings map onto these four and are never printed. **No shake.**
- **Data.** Unchanged: `PlayerProtection*`, `ZyntraSpeedBoostUntil`, `ZyntraSpeedPotionUsedThisRound`, `ZyntraDetector*`, the route-marker counts and the ZyntraProfileChanged remote.
- **Visibility.** On use or change 100 % for 6 s, then rest at 40 %. With all four empty, the row hides. ACTIVE and REFUSED never dim. The gui hides while `PartyDownCardOpen` is true or `RoundActive` is false (§1.4).
- **Layout.**
  - PC: bottom-left, right of the flashlight, gap 8.
  - Touch: the row is hidden. SHIELD is the 14 A upper-row button, and POTION, MARKER and SCAN live in the KIT fan (14).
  - Gamepad: the keycaps show the D-pad and RT glyphs that PHUD already binds (PHUD:244-249: Q/D-pad down, T/D-pad right, X/RT, Z/D-pad left).
- **Accessibility.** Text tags plus colour. The 2 s tag window is unchanged (`CAPTION_SECONDS`).
- **Tests.** `test_equipment_hud.py`: chip per state, the refusal-tag mapping, the owned-only rule, the all-empty hide, glyphs per input. `test_lucky_wheel_client.py` already lists `ProtectionHUD`; it is unaffected unless the gui name changes, so keep the name.

### 09 · Detector reading: **C**
- **Today.** ZyntraDetectorClient (55 lines) builds `ZyntraDetectorReadout` at order **1100**, holding the ZyntraDetectorVisual 3D handheld (up to 277x420) and a caption.
- **Change.** Rewrite the client's draw part as a call to `RoundHud.Detector(reading, expires)`. The flat card shows bars (LOW Sage / MEDIUM Amber / HIGH Coral), `SCAN · MEDIUM`, `ENTITY NEARBY` (Montserrat ExtraBold) and `4 s`. The 3D handheld leaves the round HUD; `ZyntraDetectorVisual` stays for the Shop Display Client.
- **Data.** The `ZyntraDetector` remote `"reading"` event (reading, expires), and `Visual.Labels`. The gating stays as it is (InRound, alive, not escaped or spectating, no screen-owning modal).
- **States.** LOW, MEDIUM, HIGH. 100 % for 4 s, then hidden. HIGH never dims.
- **Layout.** PC: 240x72 above the SCAN chip. Phone: under the feed, top-centre. Gamepad: as PC.
- **Tests.** In `test_round_hud.py`: a reading becomes the card text and colour, and it expires at `expires`. Drop the 1100 order.

### 10 · Stamina: **C**, bottom centre
- **Today.** NoiseReporter `StaminaGui` (60): a 300x14 bar, white to red, no label, fading at full (NR:417-440, 859-881).
- **Change.** Restyle in place: a 320x6 hairline with radius 3.
  - Cream fill; Amber at ≤ 25 %.
  - Exhausted: Coral fill and the tag `WINDED` at the right end until it recovers to `STAMINA_RECOVER` (NR:853).
- **Data.** NR's `stamina`, `exhausted`; `SpectateStamina` while spectating (NR:767).
- **States.** DRAINING 100 %, LOW (Amber), WINDED (never dims), RECOVERING (rests at 55 %), FULL (hidden).
- **Layout.** PC: bottom-centre, bottom −24. Touch: the bar is hidden and stamina is the 14 A RUN button's ring. Gamepad: as PC.
- **Accessibility.** The word WINDED carries the state.
- **Tests.** `test_controller_input.py` / `test_speed_potion.py` lift NR blocks; add a stamina → (fill, colour, tag, opacity) table.

### 11 · Event feed + captions: **C**
- **Today.** There are four separate surfaces:
  - **Team Objective Feed** (60): `@Username  —  DETAIL`, 3 lines (TOF:1-80).
  - **Level 2 alert toasts** (80; L2A:17-405).
  - **Level 3 reader toasts** (L3R:216-251, 727-843).
  - **Level 4 `say()`** (L4C:133, 960-1031).

  On top of those, RoundUI status lines in rounds (RUI:4806-4813) say "found a way out" and give access lines. The same fact is often shown 2-3 times (brief problem 6).
- **Change.** One `RoundHud.Feed` with rows of: a coloured left bar, an initial in a circle, a **DisplayName** in Montserrat ExtraBold, and the detail in Sage.

  | Kind | Bar | Example |
  |---|---|---|
  | TEAM | RailTeal | "Jonas put a CD in the player · 2/5" |
  | LEVEL | Amber dot | "Wrong order. The breakers reset." |
  | DANGER | Coral | "Freja is down · 3 left" |
  | SYSTEM | Cream | "Oskar got out. Follow the green lights." |

  - PC shows 2 rows and phone 1; each row lives 4 s.
  - A row carries an optional `Key`, and a second row with the same key within 2 s merges into the first. This collapses the Level 2 pump toast + team row and the Level 3 CD toast + team row.
  - Hidden Level 3 players see the feed (today they miss toasts; L3R:738, 772).
  - **Captions:** a soft card with the speaker in IconTeal and the line in Cream ("USHER / Shhh..."), 3.5 s, shown only when `CaptionsEnabled` and not `DisableCaptions` (as L4C reads them today). The bracketed `[ "shhh..." ]` copy goes.
- **Data.**
  - Round HUD listens to `RoundStatus`:
    - `"objective"`: actor → `Players:FindFirstChild(actor).DisplayName`, a client-side fix;
    - `"death"`: name, position and cause. GameManager **appends** `aliveCount` as a 5th argument, the existing append-only convention (GameManager:2723);
    - `"escape"`: the name.
  - Level 2 alert, Level 3 toast and Level 4 `say()` call `RoundHud.Feed` / `Caption` instead of drawing.
  - **Server copy:** `TeamObjectives.Announce` detail strings drop "//" and caps-shouting:
    - Level 1 PuzzleManager:62;
    - Level 2 Objective Controller:570, e.g. "started pump 1 · 1/3";
    - Level 3 Objective Controller:655 and 1004, e.g. "put a CD in the player · 2/5".

    The Level 6 controller is a preview: leave it.
- **States.** Four kinds plus a caption. No idle state; rows are transient.
- **Layout.** PC: top-centre, y 74, 320-560 wide. Phone: x 115..473, one row, Mono floor 12 px. Captions on PC sit bottom-centre above the marker; on phone they sit in the feed lane.
- **Tests.**
  - `test_round_hud.py`: merge by key, DisplayName resolution, row cap and expiry, the caption gate (CaptionsEnabled / DisableCaptions), Level 3 hidden players still get rows.
  - Copy lint (§5) over the server Announce strings.
  - Delete Team Objective Feed's mirror file and its manifest item once Studio has removed it.

### 12a / 12b · Prompt plate (keyboard + gamepad / touch): **C** (C keeps A's plate)
- **Today.** Found Footage HUD redraws every ProximityPrompt as `Custom`: key circle, object line and action line. On touch the plate is the button, and it reads ActionText only on show (CLAUDE.md, 2026-10-03; Luna relies on that, LunaTribute:486-493). Its source is Studio only.
- **Change.** Restyle in place after the B0 pull.
  - Ink plate, radius 12.
  - 40 px keycap circle. On gamepad it shows the platform glyph via `GetImageForKeyCode`; on touch there is no key.
  - Object line in Mono caps, Sage. Action line in Montserrat ExtraBold, Cream.
  - **Both lines are uppercased at render**, so Level 3 "HIDE UNDER TABLE" and Level 4 "Flip" stop clashing with no server change.
  - HOLD: a 3 px RailTeal ring around the keycap; on touch, a teal bar along the plate's bottom.
  - DISABLED: an Amber reason line in place of the object line, and the action and key greyed.
- **Data.**
  - ProximityPrompt `ObjectText` / `ActionText` / `KeyboardKeyCode` / `GamepadKeyCode` / `HoldDuration`, and the PromptButtonHoldBegan / Ended events.
  - DISABLED reads a new optional prompt attribute `HudDisabledReason` (string). The renderer supports it in B6. Wiring it into individual server prompts is follow-up work, done per prompt as a server change; the sheet's three are INSERT CD, THREAD REEL and ENTER CODE.
- **Accessibility.** A hold shows a ring that fills, with no blinking.
- **Tests.** Offline: a tiny `test_prompt_plate.py` over the pulled source (uppercase at render, reason line, touch has no keycap). Studio: Luna's "Rub belly" swap still works.

### 13 · Leave to lobby: **C**
- **Today.** Round Exit Client `RoundExitGui` (70): `HOLD L • LOBBY` 156x30, "RETURNING...", "NO ANSWER — HOLD AGAIN", the hint, and the confirm card. There is **no gamepad binding** (REX:48-110, 112-172, 174-297).
- **Change.** Restyle in place.
  - Resting: an icon-only door chip at 50 %.
  - Hover or hold: it expands to `HOLD [L] · BACK TO LOBBY` with a RailTeal fill over 1.5 s and the hint "Leaving ends your run. The others keep playing." without a plate.
  - **Phone (owner P2, "rykkes vaek"):** the chip moves out of the way and stays small and quiet.
    - It is an icon-only door chip in the top-left corner of the safe area, where REC was. It is alone there, because REC and the brackets are gone on phone (01).
    - It **never expands**: the hold fills a RailTeal ring round the 44x44 chip over 1.5 s, and the confirm card carries the words.
    - Nothing may overlap x 59..103 by y 64..108. The feed lane and the Level 3 hiding banner start at x 115. The docked death card (18) is centred. The results sheet (21) only shows once the chip is hidden.
  - Confirm card C: "RETURN TO THE LOBBY?" / "Your run ends here. The others keep playing.", **BACK TO LOBBY** (Coral) and **STAY**.
  - The status copy becomes "RETURNING..." and "NO ANSWER · HOLD AGAIN".
- **Data.** Unchanged: `RoundStatus "leaveround"` / `leaveack` / `leavefailed`, `RoundExitPromptOpen`, and `PlayerScripts.RoundExitPrompt`.
- **Layout.** PC x 24, y 74, 40x40 (expanded 240x40). Phone **x 59, y 64, 44x44, resting at 50 %, never expanded** (owner P2).
- **Gamepad.** New: **hold View/Select (`ButtonSelect`) for 1.5 s**, a button nothing in the game binds today. The confirm card is navigable (`GuiService.SelectedObject` on STAY, B = STAY).
- **Accessibility.** Hold-to-leave with a visible fill; the confirm defaults to STAY.
- **Tests.**
  - `test_round_exit_hold.py`: the gamepad hold path, the copy (no "•", no "—"), and the confirm default focus. On touch the chip sits at 59,64, is 44x44 and never expands.
  - `test_controller_input.py`: `ButtonSelect` is unbound elsewhere.

### 14 · Touch buttons · phone: **A**, KIT OPEN FAN from **C**
- **Today.**
  - NoiseReporter builds JUMP ↑, RUN » (a toggle with a different style after respawn), SNEAK and DROP\nGLOW (NR:454-659).
  - PHUD builds the SHIELD / POTION / MARKER / SCAN squares; FLC builds `FlashlightPower`.
  - The positions come from `UIDevice.ControlPlan`, nine keys in `CONTROL_KEYS_RIGHT_FIRST` (UID:550-570).
- **Change.**
  - Restyle every cell to the A face: Ink, radius 10, glyph above a 12 px caps label. The labels are JUMP, RUN, SNEAK, LIGHT (battery segments inside), GLOW, KIT (`+` closed, `×` open, RailTeal face when open) and SHIELD (◆). One style fixes the RUN-after-respawn mismatch.
  - RUN's border is the stamina ring (A): Amber when ≤ 25 %, Coral when winded.
  - SNEAK and RUN faces carry the noise state.
  - **KIT fan (C):** tapping KIT fans POTION, MARKER and SCAN leftwards in a row above the KIT row, without a plate, owned items only. Tapping KIT again or using an item closes it.
  - **UIDevice change:**
    - `CONTROL_KEYS_RIGHT_FIRST` becomes JUMP, RUN, SNEAK, LIGHT (lower row) and GLOW, KIT, SHIELD (upper row), plus the developer-only `TouchPOV`.
    - The three fan items leave the reserved zone; the fan is transient and drawn above the cluster, never in the thumbstick zone.
    - This shrinks the cluster, so the objective pill gains headroom.
- **Data.** As today, plus a KIT open flag (client-local attribute `KitFanOpen`) so UIRegression can see it.
- **States.** The cell states from 08 (cooldown numeral, ACTIVE ring, empty 50 %) are mapped onto the A faces, because the A tiles only show READY (§7 small calls).
- **Layout.** Phone (Brief §4 #21): 52x52 cells, gap 8, edge 12. Lower row y 305..357, x 553..785; upper row y 245..297. Tablet: 64 px cells. The row fallback in `rowControlPlan` stays.
- **Tests.**
  - `test_controller_input.py`: the new key order.
  - `test_equipment_hud.py`: the KIT fan opens and closes, owned-only.
  - UIRegression: `ControlZoneMatrix` and `QueueModalMatrix` rows re-baselined, and a new KIT-open row asserting the fan clears `Zones.Thumbstick`.

### 15 · Level 3 hiding: **C**
- **Today.** Level 3 Table Hiding Client `Level3TableHideUI` (92):
  - shade and 34 px letterbox, the banner "HIDDEN UNDER TABLE", the button "LEAVE HIDING  //  E";
  - the warned banner "SOMETHING IS LOOKING UNDER THE TABLE" with **no countdown** (L3H:276-354, 391, 402-426, 446-474).
- **Change.** Restyle in place. Keep the shade and the letterbox.
  - Banner: `HIDDEN UNDER TABLE` in RailTeal Mono, without a plate.
  - Button: keycap `E` (B on gamepad, nothing on touch) and **LEAVE HIDING**.
  - Table check: `IT'S LOOKING · LEAVE NOW` in Coral Montserrat Black, the seconds right-aligned (`1.2 s`), and a Coral bar draining from `Level3_MallManagerTableCheckEndsAt`.
- **Data.** `Level3_Hiding`, `Level3_HideTableIndex`, `Level3_MallManagerTableCheckIndex` / `EndsAt` (server time; L3H already reads them).
- **States.** HIDDEN: 100 % for 6 s, then the banner rests at 45 % and the button at 55 %. TABLE CHECK never dims.
- **Layout.** Banner at top-centre y 74 (the feed moves below it while hidden), button under it. Phone: banner x 115..473 at y 64, button 200x44. Gamepad: B and X leave, as today (L3H:483-484).
- **Accessibility.** The countdown is a draining bar plus numerals, with no flashing. The letterbox is unchanged.
- **Tests.** New `test_level3_hiding_hud.py`, lifting the L3H banner block against fakes: the countdown from EndsAt, copy without "//", warned never dims.

### 16 · Level 4 note + keypad: **C**
- **Today.** L4C `Level4RoundGui` (order **6**).
  - Note card: PatrickHand, "click to close", an X, and no way to reopen it (L4C:548-601).
  - Keypad: no gamepad support (L4C:466-544).
- **Change.** Restyle in place; the gui order becomes **60**.
  - **Note:** keep the paper, drop the X. "E CLOSE" keycap on PC and gamepad (B); "TAP TO CLOSE" on touch, where a tap anywhere closes it. It becomes **rereadable**: tap the card's "Order:" line, or press N / D-pad up. The objective card's Order line is the anchor.
  - **Keypad:** heading `PRIZE CASE · ENTER CODE`; flat keys (Tile face, Cream numerals); OK in RailTeal; C in Sage; a Coral close. Gamepad focus ring in RailTeal via `GuiService.SelectedObject` and `NextSelection*`, with the hint `[A] PRESS · [B] CLOSE` as keycap chips. "DENY" becomes `WRONG CODE`.
- **Data.** Unchanged: `Level4_NoteOrder`, `Level4CardOpen`, the keypad remote.
- **Layout.** Centre. Note 380x270 (PC) / 340x240 (phone). Keypad 240x330, scaled to 300 px tall on phone.
- **Accessibility.** Fully playable on a pad. Close is reachable by key, by B and by tap.
- **Tests.** New `test_level4_note_keypad.py`: reopen path, B closes, focus wraps, phone close copy. **Coordinate with the in-flight Level 4 reels session** (§6 R1).

### 17 · Loading card: **C**, six black cards LEVEL 1-6 (owner G3)
- **Today.**
  - RoundUI `LevelLoading` (gui 100, ZIndex 100) is an opaque full-screen Frame. Its colour is `LOADING_PALETTES[n].Background`: near-black 3,5,4 for Level 1 and 3,6,8 for Level 2 (RUI:1186-1199). It has no image.
  - On it sit the Code font, "> ENTERING ANOMALOUS SPACE" (RUI:4687) and the staged status (RUI:1988-2015). At the end of that sequence, `"> SYNCHRONIZING PARTY"` overwrites the title (RUI:2007-2008).
  - Palettes exist only for Levels 1 and 2. `loadingPaletteFor` falls back to [1], so any other level is painted Level 1 green.
  - The pictures the owner saw were the mockup's gameplay frames behind soft Ink (frame 273:303). They are not RoundUI code.
  - A second, **Studio-only** loading script also exists: `ReplicatedFirst."Lobby Loading Screen"` (LocalScript, 33,509 B in the 2026-10-07 parity dump, not in the mirror). It reads the player attribute `LoadingLevel` that RoundUI sets at RUI:4686. Whether it draws per-level images is unknown until B0 pulls it (PLAUSIBLE).
- **Change.** Restyle in place by mutating `loadingFrame`, `loadingTitle` and `loadingStatus`, and add the rest in a `do` block.
  - **Pure black, no pictures (owner G3):**
    - `loadingFrame` is 0,0,0 at transparency 0 for every level, and the world never shows through.
    - No ImageLabel goes under `LevelLoading`.
    - If the pulled `Lobby Loading Screen` draws level art, remove that art in B0.
    - This answers the old §7 Q6.
  - **Six cards, one per level.** The per-level copy lives in a table inside the `do` block (no new top-level local):

    | Level | Eyebrow | Title | Steps | Tip |
    |---|---|---|---|---|
    | 1 | `LEVEL 1` | RESTORE THE POWER | 3, as in the 17 tile | DeathAdvice `L1Entity` |
    | 2 | none | **UNRECORDED** | none | none |
    | 3 | `LEVEL 3` | FIND THE CDS | 3, as in the 17 tile | DeathAdvice `L3Manager` |
    | 4 | `LEVEL 4 · THE LAST SHOW` | RESTORE THE POWER | 3, as in the 17 tile | DeathAdvice `L4Usher` |
    | 5 | none | **??? WHERE?** | none | none |
    | 6 | `LEVEL 6` | THE PLAYGROUND | none | none |

    - **Mystery titles (owner, 2026-10-08):** LEVEL 2 = UNRECORDED, LEVEL 5 = ??? WHERE?. Data: `MysteryTitles = {[2] = "UNRECORDED", [5] = "??? WHERE?"}`, plus `MysteryTitlePool = {"UNRECORDED", "NO FOOTAGE", "TAPE ENDS HERE", "??? WHERE?", "WHERE IS THIS?", "UNMAPPED", "BLANK TAPE", "ANYONE THERE?", "??? EXIT?"}` and `MysteryTitleMode = "fixed"`.
      - With `"random"` (the owner's optional idea), each loading cover draws one title from the pool for both levels.
      - The draw is client-local, so party members may see different titles. That is fine for flavour; seed it from the round id if the party should match.
      - Below, "the Level 2 / 5 title" means this value.
    - **Levels 2 and 5 reveal nothing else.** The card carries no objective preview, no tip and no level name. Level 2's old "START THE PUMPS" steps and its "Watch your step" tip leave the loading card; the tip stays on the death card. Only the title, the staged status with its progress bar, and the track remain.
    - **Level 6 title.** The mirrored `Level 6 Systems` is an abandoned-mall CD clone of Level 3. Its first objective is the alert "PARTY MUSIC OVERRIDE REQUIRED" (Level 6 Objective Controller:1365), which does not fit "the playground" (ZyntraConfig badge "Get out of Level 6, the playground."). The playground's own scripts, `Level 6 Playground Game` (98,357 B) and `Level 6 Playground Client` (63,163 B), exist only in Studio.
      - So the title is THE PLAYGROUND until B0 pulls those scripts. If they hold a first objective, that objective becomes the title.
      - No tip: DeathAdvice has no Level 6 key, and no honest tip exists in code.
  - Title: Montserrat Black, with an underbar in the accent. It is written once, on `loadinggame`.
    - The `"> ENTERING ANOMALOUS SPACE"` write (RUI:4687) becomes the per-level title.
    - The `"> SYNCHRONIZING PARTY"` title write (RUI:2007-2008) moves into the status line, so it can no longer replace "??? EXIT?" or the objective. `TitleDone` retires with it.
  - The staged status: Mono Sage without ">", for example `WAITING FOR EVERYONE TO LOAD · 3/4`, over a thin accent progress bar.
  - **Level track (new)** at the bottom of the card: `1 · ? · 3 · 4 · ? · 6` in Mono 12+.
    - 2 and 5 are always "?", on every card.
    - The current level is drawn in its accent at full opacity; the others are Sage at 45 %.
    - On the Level 2 and 5 cards the "?" itself is the highlight.
  - Accents (owner 2026-10-08, second pass): 1 #FFE600 yellow, 2 #4DA3FF blue, 3 #FF0000 red, 4 #FF46C8 neon pink, 5 #D4DCE8 silver white, 6 #9C86FF violet. Dims in §1.2. The non-current track slots and the Status line stay Sage on every card, LEVEL 5 included.
- **Levels 5 and 6 are not rounds yet.**
  - `Routing.MaxLevel = 4` (Round Completion Routing:47), so GameManager never fires `loadinggame` with 5 or 6.
  - Level 5 Quiet Suburbs is a developer preview behind `Level5PreviewAccess`.
  - The Level 6 playground is a developer preview that runs on the lobby server (`Level6PlaygroundPreview`).
  - Their cards are therefore data only: they show if and when those levels become rounds. Until then, nothing exercises them in play; the offline test does.
  - The stale `Level5VoidRound` / `Level6PlaygroundPreview` level branches at RUI:4835 are not this element's business.
- **Data.**
  - The `RoundLoadingState` / `Token` / `Deadline` staging is unchanged.
  - `LOADING_PALETTES` gains [3] to [6], and every Background is 0,0,0 (§3.3).
  - The level comes from the `loadinggame` argument, as today (RUI:4682-4685).
- **Layout.** A centre column 960 wide (title 64) on PC; title 34 with 2 steps on phone. The track sits 24 px above the bottom of the column on PC, and above the safe-area bottom on phone.
- **Tests.** `test_round_loading_notice.py` and `test_round_loading_host.py`:
  - copy without ">";
  - accent per level, 1-6;
  - the background is 0,0,0 at transparency 0, with no ImageLabel under `LevelLoading`;
  - tip == `DeathAdvice.Causes[key].Tip` for 1, 3 and 4;
  - levels 2 and 5 draw exactly their mystery title (UNRECORDED / ??? WHERE?, or a pool draw in random mode), with no eyebrow, steps or tip;
  - the track text is `1 · ? · 3 · 4 · ? · 6` and the highlight sits on the right slot;
  - the synchronizing stage never writes the title;
  - the RoundUI compile check.

### 18 · Death card: **C**, closable (owner G1)
- **Today.** RoundUI death-card do-block (RUI:5318-5526; `dc` table from 5355): coral title, cause, "NEXT TIME", tip. It fades by itself after `dc.dwell = 12` s. It docks at the top while PARTY DOWN is open. There is no close control.
- **Change.** Restyle inside the existing do-block, so it needs no registers.
  - Soft-Ink plate card: `WHAT HAPPENED` (Coral Mono), title in Montserrat Black Cream, cause in Sage, divider, `NEXT TIME` (IconTeal Mono), tip in Cream. With no tip it shrinks.
  - DOCKED: a Coral 4 px left bar and the title only.
  - Level 2 hole copy comes from B0's `L2Hole`.
  - **Close (owner G1, "skal man kunne lukke ned").**
    - A small round X button sits at the card's top-right: a 28 px Tile circle with a Cream ×, inside a 44x44 hit area (`dc.close`, a field of `dc`, not a local).
    - Keycap hints sit beside it: `Esc` on PC, the B glyph on gamepad, none on touch.
    - **Ways to close:** click or tap the X, Esc (see below), or gamepad B.
    - B is bound with `BindActionAtPriority` High and **passes** when the card is hidden, when PARTY DOWN is open (there B = NO THANKS, §2.20), or while `GuiService.MenuIsOpen`. That keeps it off the dispatch-stop binding on N/ButtonB (RUI:2285-2298).
    - The docked card keeps its X, which is click and tap only while PARTY DOWN is open.
    - **Esc is reserved by Roblox for its own menu.** A game cannot sink it, and `InputBegan` may never see it (PLAUSIBLE: verify in B8). If so, the card closes on `GuiService.MenuOpened` instead, so the Esc press still closes it behind the menu, and the `Esc` hint stays truthful.
    - **After closing:** the card is gone for the rest of that life and does not re-dock when PARTY DOWN opens. Only the spectate band (19) remains, with its BACK TO LOBBY button, plus REC and the brackets on PC. The next death shows the card again (`dc.serial` already separates deaths). The 12 s self-fade stays as the automatic close.
- **States.** OPEN (per cause key; Unknown shows no tip), DOCKED, CLOSED. It never dims while open.
- **Layout.** PC: bottom-centre 480x176, bottom edge y 952; docked at top-centre y 74. Phone: 420x140 above the spectate band; docked 420x44 at y 64, centred, clear of the leave chip. The X and its 44x44 hit area sit inside the card's top-right corner on every layout.
- **Tests.**
  - `test_death_advice.py` already drives this block. Update the label expectations, and add:
    - the docked case;
    - X, B and the Esc path each close the card;
    - B passes while PARTY DOWN is open;
    - a closed card does not re-dock;
    - the next death reopens it;
    - the hit area is ≥ 44x44.
  - `test_zyntra_analytics.py` greps `DeathCause`: keep the names `DeathCauseTitle` / `Body` / `Tip`.

### 19 · Spectate band: **C**, transparent (owner G2)
- **Today.** SpectateController `SpectateGui` (58): "POV: <name>  (Q / E to switch)", the escaped and empty lines, touch ‹ › 44x44, and the spectator counter (SPC:32-133, 165-333).
- **Change.** Restyle in place.
  - `‹ [Q]` · an initial in a circle · `WATCHING` (RailTeal Mono) over the DisplayName (Montserrat Black) · `[E] ›`.
  - **No backdrop (owner G2, "skal vaere transparent"):**
    - The band Frame is at `BackgroundTransparency = 1`, with no plate, no soft-Ink gradient and no shadow box.
    - Legibility comes from the text alone: a `UIStroke` on every TextLabel (Ink 5,9,11, 1.5 px, transparency 0.35; Contextual).
    - The Q / E keycaps and the touch ‹ › are outline chips (stroke only, no fill), so nothing reads as a backdrop. The initial's circle is an outline too.
    - The BACK TO LOBBY button above the band is a button, not a backdrop, so it keeps the 13 C look.
  - Escaped: `YOU GOT OUT · WATCHING`.
  - Empty: `SPECTATING` / `NO ONE LEFT TO WATCH`.
  - The counter moves to REC (01). The "BACK TO LOBBY" button above the band takes the 13 C look.
- **Data.** Unchanged: `SpectateTargetUserId`, `Spectating`, `Escaped`.
- **States.** As above; 100 % for 6 s on switch, then 45 %. At 45 % the stroke fades with the text, because the band has no plate to keep.
- **Layout.** PC: bottom-centre 520x80. Phone: 420x56 at y 297 (the cluster is hidden while spectating). Gamepad: D-pad left / right glyphs in the keycaps.
- **Accessibility.** The band must stay legible over a bright Level 2 pool and the Level 4 neon. Check those two in B8 QA; if either fails, thicken the stroke to 2 px rather than adding a plate.
- **Tests.** `test_spectate_parity.py`:
  - the copy per state;
  - initials from DisplayName;
  - no counter;
  - every band Frame is at background transparency 1, and every band TextLabel has a UIStroke.

### 20 · PARTY DOWN: **B**, without "BACK WHERE YOU FELL"
- **Today.** RoundUI do-block (RUI:4890-5316): a 0.45 dim, and a card with "PARTY DOWN", "<NAME> WAS THE LAST TO FALL", a 15 s bar, "USE RE-ENTRY CREDIT  //  N OWNED" / "<price> R$  //  BUY CREDIT", NO THANKS, and the developer row FREE RESPAWN. The ZyntraStore re-entry modal (120) stands down while `PartyDownWindowOpen`.
- **Change.** Restyle inside the do-block into the B "NO SIGNAL" screen:
  - full screen, navy-black (≈ 4,7,16) at 0.1 transparency (§7 Q3), with corner brackets;
  - `NO SIGNAL` in large Mono;
  - `PARTY DOWN · 00:15` in Coral with a Coral drain bar;
  - `ANNA FELL` (DisplayName). When the name is nil (the party emptied by a leave), the line is not drawn;
  - `EMERGENCY RE-ENTRY`, then the buttons:

  | State | Buttons |
  |---|---|
  | credit owned | `USE CREDIT · 1 OWNED` (outlined) + NO THANKS |
  | buy | `BUY · R$ 29` (Amber outline) with `0 OWNED` + NO THANKS |
  | waiting | `WAITING FOR ROBLOX...` + NO THANKS |
  | not eligible | NO THANKS only, **no empty slot** (fixes RUI:5090-5096) |
  | developer | FREE RESPAWN with a Coral `DEV` chip |

  - The docked death card (18) draws above the screen, at the top, unless the player has already closed it (G1).
  - On the touch layout the screen drops its corner brackets, matching P3 (small call).
  - After NO THANKS the screen closes and the status reads `PARTY DOWN · 12 s`. The status label moves out of the topbar strip to top-centre under the feed.
- **Data.** Unchanged: `"partydown"` / `"partydownclear"` / `"lose"`, the client-local `ZyntraReentryCredits` / `Price` / `ProductId`, `PartyDownCardOpen`, `PartyDownWindowOpen`.
- **Layout.** Phone: the same screen, UIScale ≥ 0.85, buttons 44 tall. Gamepad: focus starts on the primary button; B = NO THANKS.
- **Accessibility.** The drain bar has no flicker. The kill cam (1000) still plays over it (§1.4).
- **Tests.**
  - `test_reentry_dismissal.py`, `test_dev_free_respawn_offer.py`, `test_controller_input.py`: new labels, no empty slot when ineligible, focus and B.
  - Assert the string "BACK WHERE" is absent.

### 21 · Results: **C**
- **Today.** RoundUI `RoundEnding` (ZIndex 120) and the CONTINUE / party list (RUI:1250-1519, 1663-1947, 4788-4887).
  - Copy: "RETURNING TO BASE"; an own escape shows "SIGNAL LOST"; `CompletionPressedText` is never read.
  - The SignalFlash ignores ReduceFlashing.
- **Change.** Restyle in place: mutate the existing frames, and put new children in a do-block table.
  - A Zyntra window without a plate on soft Ink. Title, then a RailTeal underbar.
  - Stat tiles: TIME, SURVIVORS, and on a loss the level's counter (for example PUMP STATIONS 2/3, from `RoundHud.LastObjective()`).
  - A PARTY header and one row per player: initial, DisplayName and a sub-status (GOT OUT / FELL / WATCHING NEXT), plus a chip (CONTINUE / DECIDING / LOBBY / DOWN / INSIDE / GOT OUT).
  - Countdown: `LEVEL 4 BEGINS IN 14` / `RETURNING TO LOBBY IN 5` / `WATCHING JONAS IN 3`.
  - Buttons: CONTINUE (pressed: `CONTINUING...`) and BACK TO LOBBY (pressed: `RETURNING...`).
  - Copy: "LEVEL 3 CLEARED" / "NO ONE FOUND A WAY OUT" (Coral) / "YOU GOT OUT" + "WAITING FOR THE OTHERS".
  - SignalFlash is gated on `ReduceFlashing`.
- **Data.** The existing win / lose / escape payloads and the party choice events. Per-player outcome comes from `Escaped` and the humanoid state on each roster Player; check in Studio (PLAUSIBLE).
- **Layout.** PC: window 1040x600 centred. Phone: a sheet x 59..785, y 64..357, buttons 52 tall side by side. Gamepad: focus on CONTINUE.
- **Tests.**
  - `test_round_loading_notice.py` references `RoundEnding`: update.
  - New block test: escape copy is never "SIGNAL LOST", pressed text shows, the flash respects ReduceFlashing.
  - The Achievements Client toast (Studio only) must not cover the buttons: Studio QA.

---

## 3. Non-UI prerequisites (batch B0)

1. **Audit and pull.**
   - Run `git status`, then `pull_source_from_studio.py --audit`. The 2026-10-07 parity dump lists these as drifted: RoundUI (−173 B), Level 3 Reader Client (+12,402 B), Level 3 Table Hiding Client, ProtectionHUD (+1,601 B), NoiseReporter, SpectateController, Round Exit Client and DeathAdvice.
   - Pull them, or merge them if the working copy is also edited.
   - Then re-read the cites in §2 for those scripts.
2. **Pull the Studio-only scripts into the mirror.**
   - `Found Footage HUD` (13,623 B) and `Achievements Client`: read `.Source` with `execute_luau` (13.6 KB fits one call).
   - `ReplicatedFirst."Lobby Loading Screen"` (33,509 B): it reads `LoadingLevel` and may draw loading art (17, G3).
   - Read only, no mirror needed: `Level 6 Playground Game` (98,357 B) and `Level 6 Playground Client` (63,163 B), for the Level 6 card's title (17).
   - Write them byte-exact, then add the manifest items with `sha256_of` / `canonical_bytes` from `tools/studio_source_contract.py`. HttpService is gone from the MCP sandbox, so the HTTP dump recipe no longer works.
   - Record Found Footage HUD's DisplayOrder, its timecode source and its prompt mechanics. They decide whether GameManager needs `RoundStartedAt` (01).
3. **`LOADING_PALETTES[1]` to `[6]`, all on black** in RoundUI (RUI:1186-1199). [1] and [2] change colour, [3] to [6] are new. These are table entries, not new locals. Owner G3 makes every cover pure black. So `Background` leaves the palette: `loadingFrame` is set to 0,0,0 once, and `applyLoadingPalette` stops writing it.
   ```lua
   [1] = {Title = Color3.fromRGB(255, 230, 0),   Status = Color3.fromRGB(158, 143, 0)},   -- yellow
   [2] = {Title = Color3.fromRGB(77, 163, 255),  Status = Color3.fromRGB(48, 101, 158)},  -- blue
   [3] = {Title = Color3.fromRGB(255, 0, 0),     Status = Color3.fromRGB(184, 0, 0)},     -- red
   [4] = {Title = Color3.fromRGB(255, 70, 200),  Status = Color3.fromRGB(158, 43, 124)},  -- neon pink
   [5] = {Title = Color3.fromRGB(212, 220, 232), Status = Color3.fromRGB(131, 136, 144)}, -- silver white
   [6] = {Title = Color3.fromRGB(156, 134, 255), Status = Color3.fromRGB(97, 83, 158)},   -- violet
   ```
   - [1] and [2] drop `Background` too, and their old colours go: Title 105,230,135 / 105,222,238, Status 65,165,90 / 48,150,159. Level 2's loading palette is blue now, no longer cyan.
   - Title and Status are the owner's accent and dim for every level (owner 2026-10-08, second pass; §1.2).
   - `TitleDone` retires in B8 with the `"> SYNCHRONIZING PARTY"` title write (17). Until then, every entry carries `TitleDone` equal to its `Title` (the old brighter 125,255,155 and 155,244,255 go), so B0 does not touch that code path.
   - Levels 5 and 6 are not rounds yet (17), so their entries are dormant data. They exist so that `loadingPaletteFor`'s fallback to [1] can never paint them LEVEL 1 yellow.
   - Remove any per-level picture that the pulled `Lobby Loading Screen` draws (step 2).
4. **DeathAdvice `L2Hole`:** `{Title = "YOU FELL", Cause = "You fell through a hole in the floor.", Tip = "Watch your step: some of the floor gives way."}`. It is within the 22 / 72 / 72 limits.
   - The **kill site does not exist in the repo yet**: no Level 2 hole kill is found under `Level 2 Systems`.
   - Whichever session builds the no-entity Level 2 adds `DeathAdvice.Mark(player, "L2Hole")` on the line before the kill. Until then a hole fall reads SIGNAL LOST with no tip; that is honest, not wrong.
   - Add the test key to `KILL_SITES` together with that file.
5. **Remove the Pool Slide tip (`L2Slide`)** together with the Pool Slide's `DeathAdvice.Mark(..., "L2Slide")` (Level 2 Pool Slide Controller:648), **in the build where the Pool Slide no longer spawns.**
   - The Pool Slide is still live in Level 2 today: it spawned and chased in the 2026-10-03 receipt. Dropping only the tip would turn its kills into SIGNAL LOST.
   - Remove `L2Slide` from `KILL_SITES` in `test_death_advice.py`.
   - New check in the same test: every `DeathAdvice.Mark(_, "X")` call site in `ServerScriptService` uses a key in `Causes`. That fails if one half is removed without the other.
6. **Remove the "pumps alert an entity" briefing.**
   - It sits in RoundUI `levelTwoBriefingCues` (RUI:2656-2671; cue 18.65-25.00, plus the 12.20 Pool Foam and 33.45 "the entity knows" lines) and is dead behind `BRIEFINGS_OFF_20261004`.
   - Delete the whole Level 2 briefing: its cues, the `levelTwoBriefingSound` / `levelTwoRadioCue` Sounds, the `levelTwoBriefing*` state locals and `preloadLevelTwoBriefing` / `playLevelTwoBriefing` / `cancelLevelTwoBriefing` / `isLevelTwoParticipant`.
   - Deleting only the caption lines would leave the recording saying it if briefings ever came back. The whole deletion frees about 10 top-level registers.
   - Remove the UIRegression row that carries the line (UIRegression:3935).
   - The Level 1 and Level 3 briefings are §7 Q5.

---

## 4. Batches

Every batch can be pushed and checked in Studio on its own. Each one leaves every level playable, even when some levels still wear the old look. Order: B0 → B1 → B2 → B3 → B4 → B5 → B6 → B7 → B8. Dependencies: B1 creates `RoundHud`, B3 creates `Round HUD`, and B4 and B5 extend both.

The QA modes:

| Mode | How |
|---|---|
| **PC** | Studio play, 1920x1080 (or `workspace.UIRegressionViewport = Vector2.new(1920,1080)`) |
| **TOUCH** | `workspace:SetAttribute("ForceTouchUI", true)` + `UIRegressionViewport` 844x390, and once per batch the Device Simulator on an iPhone in landscape for real insets |
| **PAD** | Studio's controller emulator or a real pad, after a pad input so `LastInput()` is Gamepad |

Start rounds with the playtest recipe (LaunchZone teleport + ConfigureQueue + DevFastQueue). Press B to hide developer ESP before judging the HUD. Run the UIRegression rows the batch touches. Run the compile probe after every push.

### B0 · Prerequisites (§3)
- **Scripts:** RoundUI, DeathAdvice, UIRegression, the two pulled scripts (Studio → repo only); the Pool Slide controller only if retired.
- **QA:**
  - [ ] PC: start Levels 3 and 4. The loading cover is pure black, with red and neon pink accents, not yellow.
  - [ ] PC: start Levels 1 and 2. The cover is pure black with yellow and blue accents (no longer green and cyan), and no picture shows (including from `Lobby Loading Screen`).
  - [ ] RoundUI compiles. No briefing, voice or caption on Level 2.
  - [ ] `pull --audit` shows 0 drift, and Found Footage HUD, Achievements Client and Lobby Loading Screen are in the manifest.
  - [ ] The Level 6 playground scripts were read for a first-objective title (17). Record the result.
  - [ ] The DeathAdvice card for a Level 1 pit still reads YOU FELL with its own tip.
  - [ ] TOUCH and PAD: the loading cover is legible at 844x390.

### B1 · Foundation and the PC kit: flashlight B, chips C, detector C
- **Scripts:** UIStyle (`Hud` tokens), **new** `RoundHud` (`Attention`, `Keycap`, `DetectorCard`), FlashlightController, ProtectionHUD (PC row, the hide-under-RoundUI gate), ZyntraDetectorClient.
- **QA:**
  - [ ] PC: flashlight B bottom-left. ON, CHARGING, LOW (≤ 2 segments, Amber), EMPTY (Coral). Press F at < 5 % and TOO LOW shows for 2 s. With Advanced Equipment: WIDE and FOCUSED.
  - [ ] PC: the chips show READY, then 40 % idle after 6 s. Shield → ACTIVE `4.2 SAFE`. Cooldown numerals. Use a marker with none left and NO MARKERS LEFT shows. All empty hides the row.
  - [ ] PC: scan shows the detector card above SCAN for 4 s; LOW, MEDIUM and HIGH colours. It no longer draws over the results or PARTY DOWN.
  - [ ] PC: die to the Level 1 entity with a shield ready. The shield still cancels the capture (PHUD at 1001 over the kill cam).
  - [ ] PC: win a round. No chips or detector over the result window.
  - [ ] PAD: the keycaps show the R1, D-pad and RT glyphs, and every chip fires from the pad.
  - [ ] TOUCH: the PC widget and chip row are hidden. No battery or "LIGHT" label shows anywhere outside the LIGHT button (P1). The old touch buttons still work (they are restyled in B2).
  - [ ] Spectating (2-player local server): THEIR LIGHT mirrors the watched battery.

### B2 · Touch cluster 14 A + KIT fan C
- **Scripts:** UIDevice (`CONTROL_KEYS_RIGHT_FIRST`, `ControlPlan`), NoiseReporter (cells, RUN ring), ProtectionHUD (SHIELD, KIT fan), FlashlightController (LIGHT cell), UIRegression (re-baseline the control matrices).
- **QA:**
  - [ ] TOUCH 844x390: the lower row reads JUMP, RUN, SNEAK, LIGHT and the upper row GLOW, KIT, SHIELD. Every cell is ≥ 44 px, and none is in the thumbstick zone.
  - [ ] TOUCH: the LIGHT cell is the only battery on screen (P1). Its segments go Amber at ≤ 2 and show a Coral outline at 0, and a refused press reads LOW for 2 s.
  - [ ] TOUCH: KIT fans out POTION, MARKER and SCAN (owned only) and closes on a second tap or on use. The fan never enters the thumbstick zone.
  - [ ] TOUCH: the RUN ring turns Amber at ≤ 25 % and Coral when winded. SNEAK shows as engaged.
  - [ ] TOUCH: the RUN style survives a respawn.
  - [ ] TOUCH, short screen (568x320): the row fallback still seats the cells.
  - [ ] Device Simulator iPhone landscape: the insets are respected.
  - [ ] PC and PAD: nothing changed.
  - [ ] UIRegression ControlZoneMatrix, QueueModalMatrix and the KIT-open row are green.

### B3 · Body state: stamina C, marker C, grace, chase edge
- **Scripts:** **new** `Round HUD` (marker, grace, chase edge), NoiseReporter (`MoveNoise` attribute, stamina restyle), ProtectionHUD (grace notice removed).
- **QA:**
  - [ ] PC: sprint and the hairline shows. ≤ 25 % turns Amber. Empty shows WINDED and does not dim until it recovers. Full stamina hides it.
  - [ ] PC: crouch → SNEAKING, then 45 % after 6 s. Sprint → LOUD, resting at 60 %. Walk → nothing.
  - [ ] PC: hide under a Level 3 table → HIDDEN. Hide in Level 4 → HIDDEN.
  - [ ] Trigger `ServerStorage.ZyntraReentry:Invoke(player)` → `INVISIBLE TO MONSTERS · 10 s` counts down.
  - [ ] PC: Level 1 entity chase → a static coral edge, the same with ReduceFlashing on and off. The Level 3 Manager chase → the edge.
  - [ ] **Level 2:** no edge even when Pool Foam targets you, and the marker still shows.
  - [ ] TOUCH: the marker sits in the corridor. The stamina bar is hidden (RUN ring only).
  - [ ] Spectating: no marker and no edge.

### B4 · Objective card, pill and compass for all four levels (+ 01's WARNING row)
- **Scripts:**
  - `RoundHud` (`ObjectiveCard`)
  - PuzzleUI, Level 2 Objective UI, Level 3 Reader Client, Level 4 Round Client (panel, chips, `ReelRooms` line)
  - RoundUI: retire the MISSION BRIEF button and panel after the owner's OK
  - Round Exit Client (it reads `LevelOneGuideObjectivesOpen`)
  - UIRegression rows
- **QA**, per level, on PC and TOUCH:
  - [ ] Level 1: RESTORE THE POWER · FUSE BOXES a/b. The guidance follows the fuses carried. PULL THE LEVERS. GET OUT with the compass on the exit.
  - [ ] Level 2: START THE PUMPS · PUMP STATIONS n/3. After the lethal pump, the Coral status row (never dims). GET OUT with the compass, once powered.
  - [ ] Level 3: FIND THE CDS · CDS IN THE PLAYER n/5. IN THIS ROOM is steady. Exit CALIBRATING, then locked.
  - [ ] Level 4: RESTORE THE POWER with the Order line. LOAD THE PROJECTORS with "You carry 2 reels." and "Reels: Cafe, Arcade". The breaker fuse shows as the **Amber WARNING row**. GET OUT with the compass in metres.
  - [ ] On change 100 % for 6 s, then 45 %. DONE turns RailTeal. BEHIND clamps to the edge. ARRIVED shows under 8 m.
  - [ ] Spectating: WATCHING ANNA · LEVEL n, with the distance from the watched player.
  - [ ] TOUCH: the pill is 240 wide (P4), top-right in the safe area. It is collapsed, expands on tap and on change, and sits above the cluster (`TopRightPanel`). No pill text is under 12 px.
  - [ ] PAD: nothing to bind. Level 3's R / Y no longer hides anything.
  - [ ] No MISSION BRIEF button anywhere. H and D-pad up do nothing.

### B5 · Event feed + captions
- **Scripts:**
  - `RoundHud` (`Feed`, `Caption`), `Round HUD` (`RoundStatus` listeners; delete Team Objective Feed)
  - Level2AlertClient, Level 3 Reader Client (toasts), Level 4 Round Client (`say`)
  - RoundUI (escape and access lines → feed)
  - **server:** TeamObjectives callers' copy (PuzzleManager, Level 2 and Level 3 Objective Controllers), GameManager `"death"` appends `aliveCount`
- **QA:**
  - [ ] PC: a teammate powers a box → one TEAM row named by DisplayName. A Level 2 pump → **one** row, not a toast plus a row. A Level 3 CD insert → one row.
  - [ ] A teammate dies → DANGER `Freja is down · 2 left`. A teammate escapes → SYSTEM row.
  - [ ] Level 4: a wrong breaker order → LEVEL row. The Usher "shhh" → caption with CaptionsEnabled, and nothing with captions off.
  - [ ] Hidden under a Level 3 table: rows still arrive.
  - [ ] TOUCH: one row at a time, ≥ 12 px, inside x 115..473.
  - [ ] No "//", no "@", no "—" in any row (the copy lint is also green offline).

### B6 · Frame, prompts, leave: REC B, prompt plate C, leave C
- **Scripts:** Found Footage HUD (REC line, WATCHING, brackets, plates), SpectateController (counter removed), Round Exit Client, GameManager `RoundStartedAt` (only if B0 showed it is needed).
- **QA:**
  - [ ] PC: `● REC 02:37  SIGNAL` top-left, right of the door chip. It reads the same time on two clients.
  - [ ] Spectated by a dead teammate → ` · 1 WATCHING`.
  - [ ] Prompts: Level 3 table → `TABLE` / `HIDE UNDER TABLE`. Level 4 breaker → `BREAKER B3` / `FLIP` (uppercased). A hold fills the teal ring.
  - [ ] PAD: the prompt glyph is the X button.
  - [ ] TOUCH: no keycap; the plate is the button and the hold bar fills. Luna's "Rub belly" still swaps.
  - [ ] Leave: the door chip rests at 50 % and expands on hover or hold. Confirm card: BACK TO LOBBY (Coral) / STAY.
  - [ ] **PAD: hold View for 1.5 s leaves**, and the confirm defaults to STAY.
  - [ ] TOUCH: no REC line, no SIGNAL, no watcher count and no corner brackets (P3). The door chip sits alone at x 59, y 64, 44x44, resting at 50 % (P2). A hold fills its ring without expanding it, and nothing overlaps it.
  - [ ] PC: REC and all four brackets still draw.

### B7 · Level specials: Level 3 hiding C, Level 4 note + keypad C
- **Scripts:** Level 3 Table Hiding Client, Level 4 Round Client (note and keypad, order 60).
- **QA:**
  - [ ] Level 3: hide → `HIDDEN UNDER TABLE` + `[E] LEAVE HIDING`, resting at 45 / 55 %. The Manager checks the table → `IT'S LOOKING · LEAVE NOW 1.9 s`, draining, never dimmed. B and X leave on the pad. On touch, the button is the only control.
  - [ ] Level 4: read the note → E or B closes it, and on touch a tap anywhere closes it ("TAP TO CLOSE"). Reopen it from the card's Order line and with N / D-pad up.
  - [ ] Keypad: the pad focus ring moves; A presses, B closes; a wrong code shows WRONG CODE. The note and keypad draw above the HUD (order 60).

### B8 · Death and after: death card C, spectate band C, PARTY DOWN B, results C, loading card C
- **Scripts:** RoundUI (do-blocks for death, PARTY DOWN, results and loading), SpectateController, ZyntraStore (check only: the re-entry modal still stands down).
- **QA**, with a 2-player local server:
  - [ ] Die → WHAT HAPPENED card with the right cause and tip. Unknown has no tip. The Level 2 hole death reads YOU FELL once its mark exists.
  - [ ] Close the card (G1) with the X (click, and tap on TOUCH), with gamepad B and with Esc. Record whether Esc reaches the game or only `MenuOpened` fires. After closing, only the spectate band is left. It does not come back for that death, and the next death shows it again.
  - [ ] The spectate band shows `WATCHING` + DisplayName, and Q / E or the D-pad switch.
  - [ ] The band has no plate or backdrop (G2). It is legible over the Level 2 pool and the Level 4 neon on PC and TOUCH.
  - [ ] The last player dies → the kill cam plays, then **NO SIGNAL** · `PARTY DOWN · 00:15` · `ANNA FELL` · EMERGENCY RE-ENTRY.
    - [ ] With a credit: USE CREDIT · 1 OWNED.
    - [ ] Without: BUY · R$ 29, then WAITING FOR ROBLOX....
    - [ ] Ineligible: NO THANKS only, with no gap.
    - [ ] Developer: FREE RESPAWN DEV.
    - [ ] The docked death card sits on top.
    - [ ] There is no "BACK WHERE YOU FELL".
  - [ ] NO THANKS → `PARTY DOWN · 12 s` status line below the topbar.
  - [ ] Win → the C results window: stat tiles, party rows with chips, the countdown, CONTINUE → CONTINUING....
  - [ ] Lose → NO ONE FOUND A WAY OUT in Coral, plus the level counter tile.
  - [ ] Own escape → YOU GOT OUT / WAITING FOR THE OTHERS, never SIGNAL LOST.
  - [ ] ReduceFlashing on → no SignalFlash.
  - [ ] Loading (G3): every cover is pure black with no picture, and the track reads `1 · ? · 3 · 4 · ? · 6`.
    - Levels 1, 3 and 4 show their eyebrow, title, steps and the DeathAdvice tip, with the accent progress bar.
    - Level 2 shows only UNRECORDED (Level 5: ??? WHERE?), the status line and the track. In random mode the title is one of the 9 pool titles.
    - The synchronizing stage never replaces the title.
    - Levels 5 and 6 cannot be launched; their cards are covered offline only.
  - [ ] TOUCH: the results sheet and the NO SIGNAL screen fit 844x390 (UIScale ≥ 0.85) with ≥ 44 px buttons. PAD: the results focus is on CONTINUE; PARTY DOWN's focus is on the primary button.
  - [ ] The Achievements Client toast does not cover the result buttons.

---

## 5. Offline tests

Run them with `LUAU_BIN` pointing at luau 0.737 (`…/CodexTools/luau/0.737/luau.exe`; see the memory note "Offline luau tests"). When a suite fails, check HEAD first: stale fake-engine harnesses are common. Add the stub the real code needs, and never bend an assertion.

| Test | New / update | Covers |
|---|---|---|
| `test_round_hud.py` | new (B1, grows B3-B5) | `Attention` timings (6 s, 45 / 40 / 55 / 60 %, danger and active never dim, all-empty hide); compass maths and spectator origin; objective state diff; phone pill 240 wide with no text under 12 px (P4); feed merge, DisplayName, caps and expiry; caption gate; chase-edge truth table and the static transparency across ReduceFlashing; marker priority and Level 2 presence; REC time format; REC and brackets hidden on the touch layout (P3) |
| `test_hud_copy_rules.py` | new (B1, extended per batch) | A lint over `Text =` / `.Text` / `RoundHud.Feed` / `Caption` / `SetObjective` string literals and the `TeamObjectives.Announce` details in every touched file. Bans `//`, a leading `> `, `\[[A-Z0-9]{1,3}\]`, `\bL[1-4]\b`, `@` before a name, ` — `, `•`; requires ` · ` (`\u{B7}`) as the separator. Asserts the ASCII-only source of new scripts |
| `test_ui_style.py` | update (B1) | `UIStyle.Hud` equals the ShopBinder palette; level accents equal `LOADING_PALETTES[n].Title`. Drops `Level1Objectives` / `Level 2 Objective UI` / `Round Exit Client` needles where those move |
| `test_death_advice.py` | update (B0, B8) | `L2Hole` copy limits; `L2Slide` gone; **every Mark call-site key exists**; card labels; docked state; close by X / B / Esc path, B passes under PARTY DOWN, no re-dock after close, reopen on the next death (G1); RoundUI `luau-compile` (the register check) |
| `test_round_loading_host.py`, `test_round_loading_notice.py` | update (B0, B8) | palettes [1] to [6] with the new level colours (§3.3); a black opaque cover with no image; the C loading copy for six cards; the Level 2 / 5 titles (UNRECORDED / ??? WHERE?; random mode draws from the pool) alone on 2 and 5; the track `1 · ? · 3 · 4 · ? · 6`; the tip comes from DeathAdvice (1, 3, 4); result escape copy (G3) |
| `test_flashlight_player_control.py` | update (B1, B2) | B states; the TOO LOW refusal; THEIR LIGHT; no B widget on touch, with the LIGHT cell carrying the battery (P1) |
| `test_equipment_hud.py` | update (B1, B2) | chip states, the refusal-tag map, owned-only, the all-empty hide, the KIT fan |
| `test_controller_input.py` | update (B2, B3, B6, B8) | touch key order; `MoveNoise`; `ButtonSelect` hold for leave; the PARTY DOWN focus and B |
| `test_speed_potion.py` | update if needed (B3) | NR block extraction still matches |
| `test_round_exit_hold.py` | update (B4, B6) | no `PuzzleGui` / `Level1Objectives` / `LevelOneGuideObjectivesOpen` reads; gamepad hold; copy; phone chip at 59,64, 44x44, never expanded (P2) |
| `test_level1_team_prompts.py`, `test_level3_first_cd.py` | update (B4) | the PuzzleUI and reader blocks after their panel code moves out |
| `test_spectator_count.py`, `test_spectate_parity.py` | update (B6, B8) | the count on REC; the band copy; band background transparency 1 and a UIStroke on its text (G2) |
| `test_reentry_dismissal.py`, `test_dev_free_respawn_offer.py` | update (B8) | PARTY DOWN B buttons; no empty slot; no "BACK WHERE" |
| `test_level3_hiding_hud.py` | new (B7) | the countdown from `EndsAt`; copy; warned never dims |
| `test_level4_note_keypad.py` | new (B7) | reopen, B closes, focus, touch close copy |
| `test_prompt_plate.py` | new (B6, after the pull) | uppercase at render; reason line; no keycap on touch |
| `test_lucky_wheel_client.py` | unchanged | it lists `ProtectionHUD` and `StaminaGui` by name, so keep both names |
| UIRegression (Studio) | update per batch | rows naming retired guis; control matrices (B2); the KIT-open row; `Fit.ZyntraDisabledCaptions` if any caption copy matches it |

Known failures to leave alone: `test_level3_run_in_exit`, `test_level3_hidden_chase` and `test_level3_slide_aperture` already failed at HEAD on 2026-09-14.

---

## 6. Risks

1. **Parallel sessions.**
   - The working copy holds uncommitted changes to `Level 4 Round Client`, `Level 4 Objective Controller` and `Level 4 Configuration`, and `artifacts/level4-reels-20261008/` is untracked. That is the reels work (REEL_ROOMS, TORCH_GLINT).
   - B4 and B7 edit the same client. Wait for that handover or merge it first, and expect CONFLICTs from the push tool.
   - The no-entity Level 2 is being designed in another session: L2O copy, the hole kill site and the Pool Slide removal depend on it.
2. **Drift.** The parity dump contradicts the manifest for seven HUD scripts (§3.1). Editing an unpulled copy and pushing it would overwrite someone's Studio change.
3. **RoundUI registers.** B0 and B4 free roughly 20-25 top-level registers (the Level 2 briefing, plus the MISSION BRIEF button and panel), but every RoundUI edit still has to go through do-blocks and the compile check. If the owner keeps the MISSION BRIEF (§7 Q4), B8 has only the Level 2 briefing's ~10 registers of slack. Q5 (delete the dead Level 1 / Level 3 briefings and the solver) would free far more.
4. **UIRegression churn.** About 130 references to `Level1Objectives`, `PuzzleGui`, `LevelOneGuideGui`, `Level2ObjectiveGui`, `Level3Reader`, `RoundEnding` and `PartyDown`. A batch that ships without its row updates turns the matrix red, and the next session will not know why.
5. **New scripts.** They are created in Studio first (`install_new_scripts.py`), ASCII only, and the push tool cannot create them. A `·` written literally breaks the Luau parse at install.
6. **Found Footage HUD is unknown code.** Restyling the prompt plates touches every ProximityPrompt in the game, the lobby included (Luna, shop, queue, the Level 2 preview pedestal). B6 QA must walk the lobby prompts too.
7. **CanvasGroup.** Text can render soft on some devices, and each group costs texture memory. A fallback path is specified in §1.3; check on the Device Simulator before shipping B1.
8. **Escape is Roblox's menu key.** The death card's `Esc` close (G1) may never reach game code. The fallback is `GuiService.MenuOpened`, specified in 18. Verify in B8 before the hint ships. (The old risk 8, the world showing through a soft-Ink loading cover, is gone: the owner made the cover opaque black, G3.)
9. **PARTY DOWN B is nearly opaque.** The old card dimmed on purpose ("they can still see what is happening", RUI:4951-4953). At PARTY DOWN nobody is alive, so little is lost, but the owner should see it (§7 Q3).
10. **Fonts.** The first use of Montserrat and Roboto Mono can render in a fallback for a frame. Preload them with `ContentProvider:PreloadAsync` on the module's text instances at module start.
11. **Phone layout.** Changing `ControlPlan` moves every touch control and the objective headroom at once. B2 is deliberately its own batch.
12. **Level 4 has no `BeingChased` writer.** The chase edge never shows there unless the Usher publishes one (§7 Q7).
13. **Per-player result rows** derive "DOWN / INSIDE / GOT OUT" on the client from `Escaped` and the humanoid state. They are PLAUSIBLE until checked against a real 3-player round end.
14. **The graph under-covers RoundUI-adjacent files** (CLAUDE.md, GameManager 4 symbols). Grep GameManager directly for the `"death"` and `RoundActive` sites in B5 and B6.
15. **LEVEL 3 red sits close to Coral.** #FF0000 against Coral #F2705F is CIEDE2000 13.5, below the 15 target, and both appear on the LEVEL 3 chase frame (274:1046): the Coral chase edge next to the red eyebrow, underbar, progress bar and compass chevron. Position and role carry the meaning there; the owner should look at that frame. LEVEL 1 yellow next to Amber warnings (21.5) is fine on the numbers but worth a look in B4.

---

## 7. Owner answers needed (each with the default used if no answer comes)

**Answered by the approval on 2026-10-08** (`OWNER-PICKS.md`, "Approved with changes"). These are no longer questions:
- **Old Q6, loading card C over soft Ink:** answered by G3. The cover is pure black #000000, opaque, with no pictures, so the world never shows through (17, §3.3).
- **INDEX.md "phone · bottom-left bracket in the thumbstick zone":** answered by P3. Phone has no corner brackets at all (01).
- **INDEX.md "phone · flashlight placement at x 346":** answered by P1. Phone has no battery widget; the battery lives only in the LIGHT button (07).
- **Q1 and Q2, phone half:** moot. Phone has neither the B flashlight widget nor the REC line, so both questions below are now PC-only.

The questions keep their old numbers, because the sections above cite them by number. Q6 is the one that was answered.

- **Q1. Flashlight B visibility (PC).** B has no idle state, so it is always on. Keep it so, or apply C's rule (rest at 45 %, hidden above 50 %)? *Default: always on, as drawn.*
- **Q2. The REC line's `SIGNAL ▮▮▮▯` bars (PC).** Decoration, or drop a step while chased (static, no jitter)? *Default: static decoration.*
- **Q3. PARTY DOWN "NO SIGNAL":**
  - opacity? *Default: 0.1 transparency.*
  - the docked death card drawn on top? *Default: yes, unless the player already closed it (G1).*
  - `ANNA FELL` on Level 2, where "fell" also means the floor hole? *Default: as drawn.*
- **Q4. Retire the MISSION BRIEF button and the ESCAPE PROCEDURE panel** (inside `LevelOneGuideGui`), which the expanded objective card replaces? *Default: retire.*
- **Q5. Delete the dead Level 1 and Level 3 Command Center briefings and the subtitle solver** (about 690 lines, off since 2026-10-04)? *Default: B0 deletes only the Level 2 briefing (it names the entity); the rest stays until he says.*
- **Q7. Chase edge in Level 4.** The Usher sets no `BeingChased`. *Default: no edge in Level 4.*
- **Q8. Icons** for the chips, the KIT fan and the door chip: approve uploading about 6 small monochrome icons from the Figma sheet (account ban risk), or keep Frame-drawn and glyph approximations? *Default: no uploads; Frame / glyph icons.*
- **Q9. The Level 2 hole kill site:** which session adds `DeathAdvice.Mark(player, "L2Hole")`, and when is the Pool Slide (and its `L2Slide` tip) retired? *Default: the Level 2 session, in the build that removes the entities.*
- **Q10. Sneak / loud marker on Level 3,** where no hunter listens to noise? *Default: shown on every level, as answered for Level 2.*
- **Q11. The Level 6 card title (new, from G3).** The Level 5 and Level 6 accents that were asked here are answered: the owner named a colour for every level on 2026-10-08 (§1.2, `OWNER-PICKS.md` "Level colours changed").
  - Level 6 title: THE PLAYGROUND, until the Studio-only playground scripts show a first objective (17). *Default: THE PLAYGROUND, no tip.*
- **Q12 (ANSWERED 2026-10-08).** LEVEL 2 = UNRECORDED, LEVEL 5 = ??? WHERE?. Optional random draw from the 9-title pool; `MysteryTitleMode` defaults to "fixed" until he asks for random.

**Small calls made without asking.** Each is reversible within its batch:
- The sheet's "12 % ghost" means hidden in game.
- Level 3's reader hide toggle (R / Y, touch ▾) retires.
- B's flashlight drops the Y / R3 focus hint.
- Touch cells reuse the 08 C chip states on the A faces.
- Leave on a pad is hold View 1.5 s.
- The PC card is always expanded; the phone pill is collapsed with tap and on-change expansion.
- Refusals never shake.
- "Phone" in P1-P3 means the touch layout, so a tablet follows the phone. P4's smaller pill applies to the compact touch tier only, and gamepad keeps the PC look (§1.5).
- On phone the leave chip never expands; the hold fills its ring (13).
- A closed death card stays closed for that death; the 12 s self-fade stays (18).
- PARTY DOWN's NO SIGNAL screen drops its corner brackets on touch, to match P3 (20).
- On touch the LIGHT cell shows LOW for 2 s on a refused press, and draws no WIDE / FOCUSED state (07).
- The 3D detector handheld leaves the round HUD (it stays in the shop display).
- Captions are only sound captions; gameplay lines go to the feed.

---

## Framewisp adaptation (2026-10-08, owner: "Brug framewisp og figma til det hele")

The visuals now travel from Figma through Framewisp Live Sync, the way the lobby shop did. `FRAMEWISP-PIPELINE.md` (this folder) is the contract. What changes here:

- **§1.1.**
  - Each owner script keeps its logic and its ScreenGui. It **mounts a template clone** instead of drawing with `Instance.new` or mutating instances in place.
  - The templates are three Framewisp bundles, `HUD_PC`, `HUD_Touch` and `HUD_Screens`, staged at `ReplicatedStorage.ZyntraHUD.Templates`.
  - `RoundHud` gains `Template`, `Mount`, `Stack`, `Paint`, `Keycap`, `Ring` and `Soften`, and requires `ZyntraShopUI.ShopBinder` (`at`, `designSize`, `scaleText`, `strip`, `button`, `flowRow`) rather than copying it.
  - The batch-to-template map is pipeline §5.2.
- **§1.2.**
  - The fixed colours are drawn in Figma and come from `Binder.Palette`.
  - `UIStyle.Hud` shrinks to the level accent and dim table plus the Soft-Ink ramp, still tested against `LOADING_PALETTES`.
  - Accent nodes are drawn in LEVEL 1 yellow and repainted by `RoundHud.Paint` (pipeline §2.20).
- **§1.6 "No uploads" still holds, with a new gate.**
  - Every bundle must convert with **0 images**: Framewisp uploads images on the owner's account before Studio sees them.
  - No letter spacing, vectors, blur, non-linear gradients or unmapped fonts (pipeline §1.2).
  - Codex stops before Send unless the Framewisp panel reads "0 image(s)".
- **§2.** Wherever an element says "restyle in place", read "mount its template" (pipeline §2.1-§2.19 give the names per element and state).
  - Pinned names such as `DeathCauseTitle`, `PartyDownCard`, `KeyChip`, `FlashlightPower` and `RoundExitCard` are kept in the templates.
  - Some elements stay code-drawn: the chase edge, full-screen backdrops, fill amounts, ring sweeps, the bracket placement and the compass chevron position (pipeline §1.6).
- **§4. New steps before B1.**
  - **T0:** Figma export page, lint, then three Live Sync conversions via Codex computer use (3 of the 5 a day), then `00_stage_hud`, `01_hud_templates` and `02_dump_hud`.
  - B1-B6 need `HUD_PC` and `HUD_Touch`; B7 and B8 need `HUD_Screens`.
  - Every batch's QA starts with `03_hud_check`. A leftover `Framewisp_*` ScreenGui in StarterGui (Auto-sync re-delivers edited bundles) would draw over the game.
- **§5.**
  - New `tools/tests/test_hud_templates.py` over the committed dumps `tools/tests/fixtures/hud/framewisp-dump.HUD_*.json`: names, 0 images, fonts, 12 px touch floor, copy lint, palette and accent map.
  - The batch harnesses build their fake trees from those dumps.
- **§6 new risks.**
  - The templates are place data and are not mirrored; the dumps are the repo's record.
  - A re-import costs a conversion, a Codex run, a re-stage and a fixture refresh, so fix in code what code can own.
  - Phone re-layouts that are not in the approved frames (pipeline §1.7) need the owner's eye in the TOUCH QA.
- **§7.**
  - Q8 (icons) now also decides whether up to 4 images may enter `HUD_PC`. The default is still none.
  - The DECIDING chip loses its dashed stroke, which Framewisp cannot carry.
