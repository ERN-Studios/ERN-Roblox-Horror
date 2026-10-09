# In-round HUD proposal · v2 · 2026-10-08

This round applies the owner's answers from the morning of 2026-10-08 to all three directions in Figma. They are on the same page as v1: file `7FXycGKH6OT6Lme6FV3VBc`, page "In-round HUD proposal 2026-10-07" (`182:11282`).

**No direction has been chosen yet, and nothing is built in the game.**

The v1 direction boards were not changed:
- D-A `193:443`
- D-B `198:864`
- D-C `199:1159`
- their annotations

The v2 frames sit beside them. The only v1 frames that changed are the Pool Foam cleanup frames (answer 8), listed below.

The PNGs in this folder were exported with Figma `get_screenshot` at 1:1:
- 1920-wide boards at 1920.
- Phone frames at their native 844 px (the export does not upscale).
- TEAM-01 at its native 2800 px.

## What changed, by owner answer

### 3 · Rail button highlight (lobby only, not rounds)
- There is a new frame, **LOBBY-01**, a BEFORE/AFTER mockup built on two real Studio captures:
  - **PC:** the Lucky Wheel is open.
  - **Touch:** the shop is open on UPGRADES.
- **BEFORE:** every rail button looks the same.
- **AFTER:** only the button of the open window lights up.
- **The AFTER style** is drawn on the real WHEEL and UPGRADES buttons:
  - a 3 px inside stroke in Rail teal `#44DDC4`
  - a faint teal tint on the face (24 %)
  - a 4 px bar on the button's right edge, 60 % of its height, pointing at the window
- Each card also has a crop of the rail at about game size.
- The board text is in Danish. The owner only needs to answer yes or no. Nothing is built.

### 4 · The REC frame stays, in every direction
All three directions keep `● REC 02:37` and four corner brackets on PC and on phone.

- **D-A:**
  - PC shows `REC 02:37 · 1 WATCHING`. The brackets sit 8 px in from the screen edges.
  - D-B's object-focus brackets were not carried over.
  - On phone the pill eyebrow reads `REC 02:37 · LEVEL 3`, with 28 px brackets.
- **D-B:**
  - REC keeps its jitter ghost and SIGNAL bars, plus all four brackets.
  - On phone the brackets sit on the safe-area corners.
- **D-C:**
  - The principle now reads "No permanent HUD except the REC frame".
  - REC has no plate. The 64 px brackets sit 12 px from the edges.
  - On phone the pill eyebrow drops its timecode, because REC is already on screen.

### 5 · Amber marks warnings in rounds
Amber covers low battery, timers, the fuse countdown, and running or loud. All three directions show:
- the flashlight cell at LOW, with 2 amber segments
- the stamina bar amber when low
- the LOUD marker in amber

Direction details:
- **D-B** also has amber breath segments.
- **The AMBER token row** on each board now lists these warnings.
- **The D-A annotation** says the Level 4 fuse countdown and the round timers use the same amber status row.

On phone:
- **LIGHT** shows 2 amber segments in every direction.
- **RUN** differs per direction:
  - D-A: an amber ring at 60 %.
  - D-B: a 6 px amber dot at the cell corner.
  - D-C: an amber stamina ring.

### 6 · Each level gets its own colour
| Level | Accent | Dim | Background | Source |
|---|---|---|---|---|
| LEVEL 1 · green | `#69E687` (105,230,135) | `#41A55A` (65,165,90) | `#030504` (3,5,4) | Loading screen, `RoundUI.LocalScript.lua` `LOADING_PALETTES[1]` (line 1186) |
| LEVEL 2 · cyan | `#69DEEE` (105,222,238) | `#30969F` (48,150,159) | `#030608` (3,6,8) | Loading screen, `LOADING_PALETTES[2]` |
| LEVEL 3 · dusty peach | `#F6B088` (proposed) | `#B0634A` (176,99,74) | `#060505` (derived) | **PROPOSED.** A lighter version of `DustyPeach` from Level 3 Configuration (a world colour). The Level 3 Reader Client accents do not work: ENERGON (66,244,218) is too close to cyan, and the table-hiding red clashes with the coral chase colour. |
| LEVEL 4 · THE LAST SHOW | `#FF46C8` (255,70,200) | `#9E2B7C` (derived) | `#0A0612` (derived) | **PROPOSED.** `MAGENTA` from `Level 4 Round Client.LocalScript.lua` line 30 |

- Every board carries the label **"Level 3/4 have no loading colour yet (they show Level 1's green) · proposed accent"**. In code, `loadingPaletteFor` falls back to `LOADING_PALETTES[1]` for Levels 3 and 4.
- **Where the level colour goes:**
  - D-A and D-C: the eyebrow, title underbar, progress fill and compass marker of the objective card and pill.
  - D-B: the eyebrow, underbar, 2/5 progress and heading strip of the Tape notes.
  - The mockups are all Level 3, so they show `#F6B088`.
- TEAM-01's Level 3 eyebrow and underbar were recoloured to match.
- Icon teal now means only section tags. Rail teal means done, hidden and sneaking.

### 7 · A quiet sneaking/loud marker, and a loud red chase edge
- The v1 noise pill is gone from all three mockups.
- **The marker** is a 6 px dot and one 12 px mono word:
  - no plate, and it never pulses
  - 45-75 % opacity
  - `● SNEAKING` in rail teal or sage
  - `● LOUD` / `RUNNING · LOUD` in amber
- **The chase edge** is coral on all four screen edges. It is the loud signal.
- Each board has a panel comparing the two: 1:1 crops of the marker next to a thumbnail of the chase edge.
- **Per direction:**
  - **D-A:** sneaking at 55 %, loud at 60 %, placed above the stamina bar. On phone the RUN ring was turned down to 60 % so it stays quiet.
  - **D-B:** the marker sits outside the breath plate at 55-75 %. The chase edge is at alpha 0.55, with depth 110 px at the sides and 150 px at the top and bottom.
  - **D-C:** sneaking at 45 %, loud at 60 %. The chase edge is 300 px at the sides and 200 px at the top and bottom.

### 8 · No Pool Foam
- **Cover:** the decision-card item "Add a Level 2 cue when the Pool Foam has seen you?" is deleted. The cover now lists 6 decisions, renumbered.
- **Other text:** every Pool Foam mention and the Level 2 "lethal water" cue that came with it are removed from the cover, tokens, library, C-01, C-07, the Level 2 screens and notes, the loading covers, PARTY DOWN and the results screen.
- **Replacement copy** comes from code:
  - The Level 2 death lines use the Pool Slide (DeathAdvice `L2Slide`): `THE SLIDE STRUCK` on the death card, `STRUCK BY THE SLIDE` in party rows.
  - The loading cover preview reads "Once a pump is running, move quickly." (the RoundUI briefing line).
  - The tip reads "Step behind it during the windup; its swing is locked forward."
- **L2-PC-B** is now "pumps running": the objective card is expanded at 2/3 pump stations, and an amber level-event feed row reads "Jonas started pump 2 · 2/3". It replaces the old danger state.
- **C-01:** the Level 2 danger example is hidden. The Danger state is still shown in the Level 4 column (MAIN BREAKER OFF).
- A final scan of every text node on the page finds no visible text containing "foam".

### 9 · Team row: where it sits and what it shows
This answer has its own frame, **TEAM-01**. All three direction boards place the row at the same spot.

**PC:**
- The row is right-aligned under the objective card: right edge x 1896, top = card bottom + 12.
- With the card collapsed (bottom y 178) the row sits at **y 190..222**. When the card expands, the row moves down with it, at most to y 346.
- The D-A and D-C mockups show the expanded card, so their row sits at y 270..302.
- Avatars are 32 px with a 2 px ring and a gap of 8:
  - 4 teammates: x 1744..1896
  - 5 teammates: x 1704..1896
- On mouse hover a name plate appears, e.g. `Jonas · CHASED`: 28 px tall, 8 px under the row.

**Phone:**
- The dots are 22 px with a 2 px ring and a gap of 4. They sit **inside the objective pill's top line**, at the right end:
  - 4 teammates: x 673..773
  - 5 teammates: x 647..773
  - y 68..90 in both cases
- The pill grows from 48 to 52 px. Expanded, it reaches at most 176 px, so its bottom is at y 240. The prompt plate starts at y 244 and the touch row at y 245.
- The phone shows no names.

**Rejected option:** a row under the pill. It is clear only while the pill is closed (y 120..142). The pill expands for 6 s on every change, and then the row would land on the prompt plate and on SHIELD, KIT and GLOW.

**What it shows:**
- Each teammate's Roblox headshot. Until it loads, the avatar shows the first letter of the DisplayName.
- A state ring:
  - ALIVE: cream
  - HIDING: rail teal
  - CHASED: coral
  - DOWN: sage with ×
  - ESCAPED: rail teal with a tick
- **Rules:**
  - You are not in your own row.
  - The row holds up to 5 teammates (a round takes 6 players, from `GameManager` `MAX_PLAYERS_PER_STATION = 6`), in party order.
  - A solo round has no row.
  - The ring never pulses.

**Clearance** (all checked):

| Screen | Clear of |
|---|---|
| PC | objective card, feed (ends at x 1240), REC and leave chip (left side), corner brackets, prompt plate, kit bar, noise marker, stamina bar |
| Phone | feed, leave chip, REC, prompt plate, touch cluster, thumbstick zone (x 0..338, y 130..390) |

## New frames

The names are from the page; all are top-level frames on page `182:11282`.

| Frame | Size | Figma | PNG |
|---|---|---|---|
| D-A Direction A · Quiet Flat v2 · 2026-10-08 | 1920×1080 | [218:2771](https://www.figma.com/design/7FXycGKH6OT6Lme6FV3VBc/?node-id=218-2771) | `d-a-v2-board.png` |
| D-A v2 annotation · 2026-10-08 | 1920×234 | [218:3098](https://www.figma.com/design/7FXycGKH6OT6Lme6FV3VBc/?node-id=218-3098) | `d-a-v2-annotation.png` |
| D-A v2 · phone 844x390 · Level 3 chased while running | 844×390 | [218:3851](https://www.figma.com/design/7FXycGKH6OT6Lme6FV3VBc/?node-id=218-3851) | `d-a-v2-phone.png` |
| D-A v2 · phone notes | 844×260 | [218:3954](https://www.figma.com/design/7FXycGKH6OT6Lme6FV3VBc/?node-id=218-3954) | `d-a-v2-phone-notes.png` |
| D-B Direction B · Tape v2 · 2026-10-08 | 1920×1080 | [218:3510](https://www.figma.com/design/7FXycGKH6OT6Lme6FV3VBc/?node-id=218-3510) | `d-b-v2-board.png` |
| D-B v2 annotation | 1920×148 | [218:3847](https://www.figma.com/design/7FXycGKH6OT6Lme6FV3VBc/?node-id=218-3847) | `d-b-v2-annotation.png` |
| D-B v2 · phone · Level 3 chased | 844×390 | [218:15756](https://www.figma.com/design/7FXycGKH6OT6Lme6FV3VBc/?node-id=218-15756) | `d-b-v2-phone.png` |
| D-B v2 · phone note | 844×189 | [218:15876](https://www.figma.com/design/7FXycGKH6OT6Lme6FV3VBc/?node-id=218-15876) | `d-b-v2-phone-note.png` |
| D-C Direction C · Only When It Matters v2 · 2026-10-08 | 1920×1080 | [218:3107](https://www.figma.com/design/7FXycGKH6OT6Lme6FV3VBc/?node-id=218-3107) | `d-c-v2-board.png` |
| D-C v2 annotation | 1920×161 | [218:3507](https://www.figma.com/design/7FXycGKH6OT6Lme6FV3VBc/?node-id=218-3507) | `d-c-v2-annotation.png` |
| D-C v2 phone · Level 3 · chased · 844x390 | 844×390 | [218:15884](https://www.figma.com/design/7FXycGKH6OT6Lme6FV3VBc/?node-id=218-15884) | `d-c-v2-phone.png` |
| D-C v2 phone notes | 844×176 | [218:15980](https://www.figma.com/design/7FXycGKH6OT6Lme6FV3VBc/?node-id=218-15980) | `d-c-v2-phone-notes.png` |
| TEAM-01 Team row · where it sits | 2800×1320 | [218:3957](https://www.figma.com/design/7FXycGKH6OT6Lme6FV3VBc/?node-id=218-3957) | `team-01-team-row.png` |
| LOBBY-01 Rail highlight · before / after | 1920×1300 | [214:2794](https://www.figma.com/design/7FXycGKH6OT6Lme6FV3VBc/?node-id=214-2794) | `lobby-01-rail-highlight.png` |

## Changed v1 frames (Pool Foam cleanup, answer 8)
| Frame | Figma | What changed | PNG |
|---|---|---|---|
| 00 Cover · problems | [192:233](https://www.figma.com/design/7FXycGKH6OT6Lme6FV3VBc/?node-id=192-233) | Pool Foam decision deleted, header "OWNER DECISIONS · 6", decisions renumbered, mention dropped from 192:394 | `changed-00-cover-problems.png` |
| 00 Cover · annotation | [192:400](https://www.figma.com/design/7FXycGKH6OT6Lme6FV3VBc/?node-id=192-400) | Sentence rewritten without the entity name, removal note added | `changed-00-cover-annotation.png` |
| T-01 HUD tokens | [183:7](https://www.figma.com/design/7FXycGKH6OT6Lme6FV3VBc/?node-id=183-7) | CORAL usage no longer says "lethal water" | `changed-t-01-hud-tokens.png` |
| HUD/Objective Card (library set, inside 184:7) | [185:92](https://www.figma.com/design/7FXycGKH6OT6Lme6FV3VBc/?node-id=185-92) | Danger default text is now "Something is looking under the table." | `changed-library-objective-card-set.png` |
| C-01 Objective card · all states | [195:418](https://www.figma.com/design/7FXycGKH6OT6Lme6FV3VBc/?node-id=195-418) | Level 2 danger example hidden, the pill example's water status row hidden | `changed-c-01-objective-card.png` |
| C-01 notes | [195:1178](https://www.figma.com/design/7FXycGKH6OT6Lme6FV3VBc/?node-id=195-1178) | Removal note | `changed-c-01-notes.png` |
| C-07 Threat cues | [203:2384](https://www.figma.com/design/7FXycGKH6OT6Lme6FV3VBc/?node-id=203-2384) | "Level 2 · lethal water" cell deleted, removal note in the empty cell | `changed-c-07-threat-cues.png` |
| C-07 notes | [203:2506](https://www.figma.com/design/7FXycGKH6OT6Lme6FV3VBc/?node-id=203-2506) | Lethal-water and latch clauses removed | `changed-c-07-notes.png` |
| L2-PC-B Level 2 · pumps running (was · water lethal) | [203:2622](https://www.figma.com/design/7FXycGKH6OT6Lme6FV3VBc/?node-id=203-2622) | Danger card is now expanded at 2/3 pumps, feed row is now an amber level event | `changed-l2-pc-b.png` |
| Notes · L2-PC-B | [203:2896](https://www.figma.com/design/7FXycGKH6OT6Lme6FV3VBc/?node-id=203-2896) | Rewritten for the pumps-running state | `changed-l2-pc-b-notes.png` |
| Notes · L2-PC-A | [203:2892](https://www.figma.com/design/7FXycGKH6OT6Lme6FV3VBc/?node-id=203-2892) | Decision number 6 changed to 5, removal note | `changed-l2-pc-a-notes.png` |
| Notes · L2-PC-C | [203:2900](https://www.figma.com/design/7FXycGKH6OT6Lme6FV3VBc/?node-id=203-2900) | Lethal-water sentence removed | `changed-l2-pc-c-notes.png` |
| Notes · L1-PC-A | [194:367](https://www.figma.com/design/7FXycGKH6OT6Lme6FV3VBc/?node-id=194-367) | Decision number 6 changed to 5, inline removal note | `changed-l1-pc-a-notes.png` |
| L2-PH-A | [205:2755](https://www.figma.com/design/7FXycGKH6OT6Lme6FV3VBc/?node-id=205-2755) | Water status row hidden, feed row is now a level event | `changed-l2-ph-a.png` |
| Notes · L2-PH-A | [205:2966](https://www.figma.com/design/7FXycGKH6OT6Lme6FV3VBc/?node-id=205-2966) | Water and Pool Foam clauses removed | `changed-l2-ph-a-notes.png` |
| S-01 Loading cover · PC | [194:11948](https://www.figma.com/design/7FXycGKH6OT6Lme6FV3VBc/?node-id=194-11948) | New preview line and Pool Slide tip | `changed-s-01-loading-cover-pc.png` |
| S-01 notes | [194:12025](https://www.figma.com/design/7FXycGKH6OT6Lme6FV3VBc/?node-id=194-12025) | Removal note | `changed-s-01-notes.png` |
| S-02 Loading cover · phone | [194:12027](https://www.figma.com/design/7FXycGKH6OT6Lme6FV3VBc/?node-id=194-12027) | Pool Slide tip | `changed-s-02-loading-cover-phone.png` |
| S-02 notes | [194:12044](https://www.figma.com/design/7FXycGKH6OT6Lme6FV3VBc/?node-id=194-12044) | Removal note | `changed-s-02-notes.png` |
| S-05 PARTY DOWN · PC | [200:1485](https://www.figma.com/design/7FXycGKH6OT6Lme6FV3VBc/?node-id=200-1485) | Death title is now "THE SLIDE STRUCK" | `changed-s-05-party-down-pc.png` |
| S-05 notes | [200:1690](https://www.figma.com/design/7FXycGKH6OT6Lme6FV3VBc/?node-id=200-1690) | Inline removal note | `changed-s-05-notes.png` |
| S-06 PARTY DOWN · phone | [200:1692](https://www.figma.com/design/7FXycGKH6OT6Lme6FV3VBc/?node-id=200-1692) | Death title is now "THE SLIDE STRUCK" | `changed-s-06-party-down-phone.png` |
| S-06 notes | [200:1724](https://www.figma.com/design/7FXycGKH6OT6Lme6FV3VBc/?node-id=200-1724) | Removal note | `changed-s-06-notes.png` |
| S-09 Results lose + escaped waiting · PC | [202:2197](https://www.figma.com/design/7FXycGKH6OT6Lme6FV3VBc/?node-id=202-2197) | Party rows now read "STRUCK BY THE SLIDE" | `changed-s-09-results-lose-pc.png` |
| S-09 notes | [202:2317](https://www.figma.com/design/7FXycGKH6OT6Lme6FV3VBc/?node-id=202-2317) | New death strings cited, removal note | `changed-s-09-notes.png` |

## Open points
1. **Pick a direction (A, B or C)** and answer yes or no on the rail highlight (LOBBY-01). Nothing gets built before that.
2. **Level 3 and Level 4 colours:**
   - Both accents are proposals. Level 3 `#F6B088` sits between coral (chase) and amber (warnings), and on the red Level 3 plates it reads close to amber. The alternative is a lighter MutedBlue, about `#8C9EEB`.
   - The Level 4 dim colour and the Level 3/4 backgrounds are derived, not taken from code.
   - If the colours are approved, `LOADING_PALETTES[3]` and `[4]` still have to be added to RoundUI. Today both levels show Level 1's green.
3. **The Level 2 replacement copy assumes the Pool Slide is in the next update.** If it is not:
   - change the Level 2 death lines to SIGNAL LOST
   - change the tip to the pump briefing line
4. **The game code still has Pool Foam.** No repo edits were allowed, so these were not touched:
   - DeathAdvice `L2Foam` (lines 66-75)
   - the RoundUI briefing cue "poolfoam-like entities" (around line 2660)
   - the lethal-pump logic
5. **Eleven note layers are still named "Note · Pool Foam removed"** (217:2794, 2796, 2797, 2799, 2819, 2820, 2826, 2827, 2828, 2830, 2831). Their visible text is clean. The name shows only in the layers panel, and a one-call rename fixes it.
6. **The PC REC corner brackets are placed differently on each board:**
   - D-A: 8 px inset, y from 59
   - D-C: 12 px from the edges
   - TEAM-01: x 1864..1904, y 16..56

   Align them once a direction is chosen. On TEAM-01's phone mockup, the bottom-left bracket sits inside the area marked "thumbstick zone · no UI". It is decoration only and takes no input.
7. **Touch glyphs are placeholders:**
   - D-B's touch cells use typed glyphs: ↓ » ↑ 2 + *.
   - The `»` on RUN, also in D-C and TEAM-01, can read like a `>` prompt.
   - The D-C SHIELD cell has no glyph.

   All of these need real icons.
8. **D-A's phone loud ring is a stroke override**, not a library variant. If D-A is chosen, add a "Loud ring" variant to HUD/Touch Cell `188:189`.
9. **D-C's phone RUN stamina ring is full-opacity amber.** D-A's ring was turned down to 60 % to keep the marker quiet. Check that it still reads as a warning and not as a second loud cue.
10. **Gaps in the mockups:**
    - The direction mockups draw only some ring states. ESCAPED (and CHASED in D-A and D-C) appear only in the legends. TEAM-01 and the D-A key panel draw all five.
    - D-C has no idle phone view, and its collapsed phone pill shows the level colour only on the eyebrow.
    - D-B's phone Tape notes leave out the PC guidance line, and its phone note does not say so.
11. **TEAM-01 suggests the phone dots could replace "· 2 WATCHING"** in the pill eyebrow. This is a proposal: with 5 dots the eyebrow has only about 142 px left.
12. **The cover's decision card still reads as open questions.** It does not record the 2026-10-08 answers. Its numbering (1-6) also differs from the owner's numbering (3-9).
13. **Language:** LOBBY-01 is in Danish, written for the owner; every other board is in English. Say if the page should use one language.
14. **Leftovers on the page:**
    - The emptied C-07 cell still shows a bare plate with the removal note. Delete it or re-flow the grid if a tidy board is wanted.
    - The v1 designer notes still use frame codes such as `L3-PC-A`, and a few contain ` > `. These notes are internal, not player-facing.
15. **Stray files in this folder** were not made by this export:
    - `shot.png` is a byte-identical copy of `lobby-01-rail-highlight.png`.
    - `-p/` is empty.
    - `.claude-flow/` holds tool state.
    - `lobby-plates/` holds the two Studio captures that LOBBY-01 was built from.

## Update 2026-10-08 (later): rail highlight rejected
The owner dropped the rail button highlight (answer 3): "he does not want it, he does not think it looks good". Frame 214:2794 is renamed "AFVIST · LOBBY-01 Rail highlight · before / after". It carries a coral banner "AFVIST AF EJEREN · 2026-10-08", and its content is dimmed to 35 %. `lobby-01-rail-highlight.png` shows the frame as it was before the rejection. Nothing is built.

Still waiting on the owner for:
- the Level 3 and Level 4 colours
- whether the Pool Slide copy holds
- the direction (A/B/C)
- the team row

## Update 2026-10-08 (later): team row dropped
The owner does not want a team row (answer 9).

**In Figma:**
- **Hidden in all v2 frames** (not deleted, so it can be undone): the drawn team row and its "TEAM ROW" callouts in D-A, D-B and D-C (boards and phones), and D-A's "Team row · where and what" panel. A coral note "TEAM ROW · dropped by the owner 2026-10-08" stands where that panel was.
- **Notes:** their team-row sentences now read "No team row: dropped by the owner 2026-10-08".
- **TEAM-01 (218:3957):** renamed "AFVIST · TEAM-01 …" and given the same coral AFVIST banner as LOBBY-01.

**PNGs:**
- Re-exported after the change: `d-a-v2-board.png`, `d-b-v2-board.png`, `d-c-v2-board.png`, `d-a-v2-phone.png`, `d-b-v2-phone.png`, `d-c-v2-phone.png`.
- Now `team-01-team-row-REJECTED.png` and `lobby-01-rail-highlight-REJECTED.png`.
- **Stale:** the annotation/notes PNGs (`*-annotation.png`, `*-notes.png`, `d-b-v2-phone-note.png`) still show the old team-row text. Figma is current.

**Still waiting on the owner for:**
- the Level 3 and Level 4 colours
- the Pool Slide copy
- the direction (A/B/C)

## Update 2026-10-08 (later): Level 3/4 colours approved, Level 2 = falling

**Direction A/B/C is still undecided, and nothing is built in the game.** The team row stays hidden (answer 9), and the rail highlight stays AFVIST (answer 3). TEAM-01 `218:3957` and LOBBY-01 `214:2794` were not touched.

### Answer 1 · The Level 3 and Level 4 colours are approved
The owner called the Level 3 dusty peach `#F6B088` (dim `#B0634A`) and the Level 4 magenta `#FF46C8` (dim `#9E2B7C`) "perfect". Level 1 green `#69E687` and Level 2 cyan `#69DEEE` stay.

**Every "proposed" marking about the level colours is gone:**
- **D-A:**
  - The two PROPOSED chips are deleted.
  - The caveat no longer says "Level 3/4 have no loading colour yet ... proposed accent". It now reads "The level colour paints only the eyebrow, underbar, progress and compass."
  - The mockup header no longer ends in "· LEVEL 3 ACCENT IS PROPOSED".
  - The annotation and the phone notes say "the Level 3 dusty peach", without "proposed".
- **D-B:**
  - The PROPOSED tag chips are deleted, and so is the caveat label.
  - The note frame is now "Note · Level 3/4 source". The sections below it moved up 24 px to close the gap.
  - The annotation no longer says "(proposed)".
- **D-C:**
  - The header no longer says "(PROPOSED)", and the PROPOSED texts and the caveat line are deleted.
  - The frame is now "Source · Level 3/4", and "apricot" is now "dusty peach".
  - The annotation says the colours "come from the level's own palette".

No "approved" badge was added. The headings stay neutral, for example "LEVEL COLOURS · FROM THE LOADING SCREENS".

**Loading covers S-01 and S-02:** each cover's level tag, underbar and progress bar now take its level colour, following the board rule "eyebrow, underbar, progress":
- Level 1: `#69E687`
- Level 2: `#69DEEE`
- Level 3: `#F6B088`
- Level 4: `#FF46C8`

The list numbers and the TIP tag stay Icon teal, and the track stays Line `#263134`. The S-01 and S-02 notes now give these four colours.

A page-wide `/propos/i` scan finds only two texts, and neither is about level colours:
- `192:234` "IN-ROUND HUD PROPOSAL · 2026-10-07", the document title
- `203:2160` "PROPOSED · ONE MERGED ROW", the C-05 feed idea

### Answer 2 · Level 2 has no entity: players die by falling into a hole
The Pool Slide copy is gone from every Level 2 frame. There is no Pool Slide, no "THE SLIDE STRUCK", no "STRUCK BY THE SLIDE", no windup or swing tip, and no entity or chase edge in Level 2.

**Danger state:** the danger is the hole itself. The HUD stays calm: no coral chase edge, no danger row and no noise marker. The fall shows as the death fade, then the YOU FELL card.

**Copy used** (modelled on DeathAdvice `L1Pit`):

| Where | Copy |
|---|---|
| Death title | `YOU FELL` |
| Cause | `You fell through a hole in the floor.` |
| Tip (death card, NEXT TIME) | `Watch your step: some of the floor gives way.` |
| PARTY DOWN line | `ANNA FELL` |
| Results party rows | `FELL` |
| Level 2 loading tip | `Watch your step: some of the floor gives way.` |

**v1 frames rewritten:**
- **S-01:** the Level 2 tip is new. The briefing line from the entity era, "Once a pump is running, move quickly.", is hidden (not deleted), and the cover is renumbered 1-2.
- **S-02:** the Level 2 tip is new.
- **S-05 and S-06:** the docked death title is `YOU FELL` and the PARTY DOWN line is `ANNA FELL`. The main component `45:7783` is untouched.
- **S-09:** all four party rows read `FELL`. The notes explain why party rows use the third person.
- **C-07** and its notes now say: "No entity in Level 2 (owner 2026-10-08): the danger is falling into a hole, so nothing chases there."
- **The S-01, S-02, S-05, S-06 and S-09 notes** each gained a dated log line.

**A new Level 2 frame per direction**, at y -1400, above each v2 board. Each one has:
- (a) a 67 % PC mockup on the L2-pc plate, calm, beside a stand-in hole
- (b) the death card
- (c) a PARTY DOWN thumbnail and a results thumbnail
- (d) the note "Level 2 in the next update has no entity: nothing hunts you, so there is no chase edge. The danger is the holes; the HUD stays calm until you fall."

### New frames

| Frame | Size | Figma | PNG |
|---|---|---|---|
| D-A v2 · Level 2 · fall, no entity | 1920×1080 | [235:3266](https://www.figma.com/design/7FXycGKH6OT6Lme6FV3VBc/?node-id=235-3266) | `d-a-v2-level2-fall.png` |
| D-B v2 · Level 2 · fall, no entity | 1920×1080 | [235:3508](https://www.figma.com/design/7FXycGKH6OT6Lme6FV3VBc/?node-id=235-3508) | `d-b-v2-level2-fall.png` |
| D-C v2 · Level 2 · fall, no entity | 1920×1080 | [235:14979](https://www.figma.com/design/7FXycGKH6OT6Lme6FV3VBc/?node-id=235-14979) | `d-c-v2-level2-fall.png` |

### Changed frames (PNG re-exported, same name)

| Frame | Figma | What changed | PNG |
|---|---|---|---|
| D-A Quiet Flat v2 board | [218:2771](https://www.figma.com/design/7FXycGKH6OT6Lme6FV3VBc/?node-id=218-2771) | PROPOSED chips deleted, caveat and mockup header cleaned | `d-a-v2-board.png` |
| D-A v2 annotation | [218:3098](https://www.figma.com/design/7FXycGKH6OT6Lme6FV3VBc/?node-id=218-3098) | "proposed" dropped; leftover team-row legend badge 22 (`218:3101`) hidden | `d-a-v2-annotation.png` |
| D-A v2 phone notes | [218:3954](https://www.figma.com/design/7FXycGKH6OT6Lme6FV3VBc/?node-id=218-3954) | "proposed" dropped | `d-a-v2-phone-notes.png` |
| D-B Tape v2 board | [218:3510](https://www.figma.com/design/7FXycGKH6OT6Lme6FV3VBc/?node-id=218-3510) | PROPOSED chips and caveat label deleted, note renamed, sections moved up 24 px | `d-b-v2-board.png` |
| D-B v2 annotation | [218:3847](https://www.figma.com/design/7FXycGKH6OT6Lme6FV3VBc/?node-id=218-3847) | "(proposed)" dropped | `d-b-v2-annotation.png` |
| D-C Only When It Matters v2 board | [218:3107](https://www.figma.com/design/7FXycGKH6OT6Lme6FV3VBc/?node-id=218-3107) | "(PROPOSED)" and PROPOSED texts deleted, caveat line deleted, "apricot" → "dusty peach" | `d-c-v2-board.png` |
| D-C v2 annotation | [218:3507](https://www.figma.com/design/7FXycGKH6OT6Lme6FV3VBc/?node-id=218-3507) | "proposals" sentence rewritten | `d-c-v2-annotation.png` |
| S-01 Loading cover · PC | [194:11948](https://www.figma.com/design/7FXycGKH6OT6Lme6FV3VBc/?node-id=194-11948) | Level colours on tag, underbar and progress; Level 2 tip; Level 2 line 2 hidden | `changed-s-01-loading-cover-pc.png` |
| S-01 notes | [194:12025](https://www.figma.com/design/7FXycGKH6OT6Lme6FV3VBc/?node-id=194-12025) | Colour sentence, "up to 3 preview lines", log line | `changed-s-01-notes.png` |
| S-02 Loading cover · phone | [194:12027](https://www.figma.com/design/7FXycGKH6OT6Lme6FV3VBc/?node-id=194-12027) | Cyan tag, underbar and progress; Level 2 tip | `changed-s-02-loading-cover-phone.png` |
| S-02 notes | [194:12044](https://www.figma.com/design/7FXycGKH6OT6Lme6FV3VBc/?node-id=194-12044) | Cyan note, log line | `changed-s-02-notes.png` |
| S-05 PARTY DOWN · PC | [200:1485](https://www.figma.com/design/7FXycGKH6OT6Lme6FV3VBc/?node-id=200-1485) | `YOU FELL`, `ANNA FELL` | `changed-s-05-party-down-pc.png` |
| S-05 notes | [200:1690](https://www.figma.com/design/7FXycGKH6OT6Lme6FV3VBc/?node-id=200-1690) | Log line, shortened to fit the 108 px frame | `changed-s-05-notes.png` |
| S-06 PARTY DOWN · phone | [200:1692](https://www.figma.com/design/7FXycGKH6OT6Lme6FV3VBc/?node-id=200-1692) | `YOU FELL`, `ANNA FELL` | `changed-s-06-party-down-phone.png` |
| S-06 notes | [200:1724](https://www.figma.com/design/7FXycGKH6OT6Lme6FV3VBc/?node-id=200-1724) | `ANNA FELL`, log line | `changed-s-06-notes.png` |
| S-09 Results lose + escaped waiting · PC | [202:2197](https://www.figma.com/design/7FXycGKH6OT6Lme6FV3VBc/?node-id=202-2197) | Party rows read `FELL` | `changed-s-09-results-lose-pc.png` |
| S-09 notes | [202:2317](https://www.figma.com/design/7FXycGKH6OT6Lme6FV3VBc/?node-id=202-2317) | Third-person `FELL` note, log line | `changed-s-09-notes.png` |
| C-07 Threat cues | [203:2384](https://www.figma.com/design/7FXycGKH6OT6Lme6FV3VBc/?node-id=203-2384) | Note `217:2798`: no entity in Level 2, the HUD stays calm | `changed-c-07-threat-cues.png` |
| C-07 notes | [203:2506](https://www.figma.com/design/7FXycGKH6OT6Lme6FV3VBc/?node-id=203-2506) | BeingChased now confirmed for Level 3 only; no entity in Level 2 | `changed-c-07-notes.png` |

These were also re-exported so they are current. They were stale after the team-row change:
- `d-b-v2-phone-note.png` (`218:15876`)
- `d-c-v2-phone-notes.png` (`218:15980`). The frame is now 844×104, so this PNG is 844×104.

The PNGs were exported with `get_screenshot` at 1:1: 1920-wide frames at 1920, phone frames at their native 844. The three new PNGs and S-01, S-05 and the D-C phone notes were read back and checked.

### What building it would need (not done; nothing is built)
- **DeathAdvice** (`ReplicatedStorage/DeathAdvice.ModuleScript.lua`):
  - It needs a Level 2 hole entry, for example `L2Hole = { Title = "YOU FELL", Cause = "You fell through a hole in the floor.", Tip = "Watch your step: some of the floor gives way." }`.
  - The server has to `Mark` that key at the hole kill site.
  - `L2Foam` (lines 66-75) and `L2Slide` (lines 76-84) would then be unused.
- **RoundUI `LOADING_PALETTES[3]` and `[4]`** (`RoundUI.LocalScript.lua`, line 1186). Today `loadingPaletteFor` falls back to Level 1's green for Levels 3 and 4. The values:
  - Level 3: Title `#F6B088` (246,176,136), Status `#B0634A` (176,99,74), Background `#060505` (derived)
  - Level 4: Title `#FF46C8` (255,70,200), Status `#9E2B7C` (158,43,124), Background `#0A0612` (derived)
  - `TitleDone` is not designed for either level.
- **The Level 2 briefing** (`levelTwoBriefingCues`, RoundUI lines 2657-2672) still mentions "poolfoam-like entities" and an "unusually large entity" that the pumps alert. With no entity, the voice-over and captions need an owner call.

### Supersedes earlier open points
- **Open point 2** (Level 3/4 colours) is answered: approved.
- **Open point 3** (Pool Slide copy) is answered: Level 2 has no entity and the copy is the fall copy above.
- **The "Stale" note** in "team row dropped" no longer applies: the annotation and notes PNGs are current.

### Still open
1. **Pick a direction (A, B or C).**
2. **Emergency Re-entry "BACK WHERE YOU FELL"** is still visible on S-05 and S-06. With a hole death it can read as respawning over the hole. The D-A Level 2 thumbnail hides it, as its source does. Owner call.
3. **D-B Level 2 strings the builder made up**, for the owner to check:
   - `Follow the pipes to the next pump room.`
   - `PUMP ROOM · 24 m`
   - `Freja started a pump · 1/3`
   - `STOP 02:37`
4. **D-C's Level 2 mockup leaves out the SNEAKING/LOUD marker**, because nothing listens in Level 2. C's rule otherwise shows it while running.
5. **The hole is a hand-drawn stand-in** on the old 2026-10-03 kit Poolrooms plate, and it is labelled STAND-IN HOLE. A real plate needs the new map and an upload. No uploads were made, because of the 2026-10-07 ban and because an upload needs the owner's OK.
6. **Scope: S-01 and S-02 also recoloured Levels 1 and 2.** The old underbars were `#8FBF6A` and `#4FA8D8`. To keep only Levels 3 and 4, revert:
   - S-01: `194:11950`, `194:11952`, `194:11967`, `194:11969`, `194:11971`, `194:11986`
   - S-02: `194:12029`, `194:12031`, `194:12043`
   - and reword the notes `194:12026` and `194:12045`
7. **D-A's Level 2 objective card** keeps the source's progress fill of about 40 % against the count 1/3. The fill is an instance sublayer.
8. **Leftovers:**
   - The cover question `192:310` "Per-level accent colours for the loading cover and results?" is answered but still worded as a question.
   - Layer names: `218:3246` still says "dim team row" and `235:3580` "Avatar · A · chased"; both sit in or above hidden rows.
   - Several notes open with "Cut Level 2 entity removed (owner answer 8, 2026-10-08)", which says the same thing twice.
   - The D-B v2 Tape thumbnail `218:3825` "Anna was the last to fall" is a Level 3 strip, so it stays.

Figma calls for this export: 25 (1 read-only `use_figma` to map the changed nodes to their top-level frames, plus 24 `get_screenshot`).

## Correction 2026-10-08: the team row stays removed
A relayed message called the team row "undecided". That was wrong: the owner wrote directly "Vi skal heller ikke have en team row". The team row stays out of every direction.

A final check over all v2 boards, phones, notes and the three Level 2 fall frames found two leftovers, both fixed:
- **D-C thumbnail layer name:** "dim team row" removed from the name.
- **D-B Level 2 note:** the sentence "The team row stays hidden." removed. `d-b-v2-level2-fall.png` is re-exported.

No visible team-row element or text is left. Only direction A/B/C is still open.
