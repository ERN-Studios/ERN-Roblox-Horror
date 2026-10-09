# Final in-round HUD · 2026-10-08

**APPROVED 2026-10-08, with changes.** The owner approved the combined HUD on this page ("Okay det ser rigtig godt ud.") and
asked for seven changes: P1-P4 on phone only, G1-G3 on all platforms. `OWNER-PICKS.md` (this folder) records them with his
words. The frames below already include all seven. Nothing is built in the game yet.

Later on 2026-10-08 the owner **replaced the level colours** and asked for a replacement for the "??? EXIT?" loading title
(C1 and T1 below). The recoloured frames were re-exported over their old PNGs.

Figma page **"Final HUD 2026-10-08"** (267:2):
https://www.figma.com/design/7FXycGKH6OT6Lme6FV3VBc/?node-id=267-2

These frames are built from the owner's element-by-element picks in `OWNER-PICKS.md`. The picks were made on the element
sheet, page 244:2 (`artifacts/hud-element-sheet-20261008/INDEX.md`). Every element is a clone from page 244:2. In the
mockups each clone is rescaled 0.5 to real game size. The reference sheets keep the sheet's 2x tiles.

Every PNG was exported with `get_screenshot` at native size. The exception is REF-1 and REF-2, which are 3000 x 9485 and
3000 x 13112 in Figma. They were capped at the 4200 px long edge, so they come out 1329 x 4200 and 961 x 4200. For full
detail, open them in Figma.

## What changed after approval

| # | Change | Where |
|---|---|---|
| P1 | On phone the battery is shown only inside the LIGHT touch cell. The separate battery and its LIGHT label are gone. | 4 phone frames |
| P2 | On phone the leave chip sits in the top-left of the safe area (x 59, y 64, 44x44), where REC used to be. | 4 phone frames |
| P3 | On phone the REC timecode, SIGNAL bars, watcher count and white corner brackets are removed. PC keeps them. | 4 phone frames |
| P4 | The phone objective pill is about 80 % (240 wide), with no text under 12 px. | 4 phone frames |
| G1 | The death card closes with a round X (44x44 target), Esc on PC or B on gamepad. Only the spectate band stays. | death frames, REF-2 row 18 |
| G2 | The spectate band has no backdrop. A dark text stroke keeps it legible. | death frames, REF-2 row 19 |
| G3 | Loading is pure black with six cards, LEVEL 1-6. LEVEL 2 reads only UNRECORDED and LEVEL 5 only ??? WHERE? (chosen later, replacing "??? EXIT?"). A level track runs along the bottom. | new loading frame, REF-2 row 17 |
| C1 | New level colours: LEVEL 1 yellow, 2 blue, 3 red, 4 neon pink (unchanged), 5 silver white, 6 violet (kept). Table below. | loading frame + annotations, REF-1, REF-2, PC LEVEL 1-3 + annotation strips, phone LEVEL 1-3, RESULTS · lose |
| T1 | Eight proposed replacements for "??? EXIT?". CHOSEN: LEVEL 2 = UNRECORDED, LEVEL 5 = ??? WHERE?; optional random draw from all 9 titles each load. | new frame 299:1319 |

## Level colours (owner, 2026-10-08)

"Farve for level 1: gul, 2: blaa, 3: roed, 4: neon pink, 5: graa/hvid, 6: violet". These replace #69E687, #69DEEE, #F6B088
and the Sage placeholder on LEVEL 5. `OWNER-PICKS.md` has the full record.

| Level | Accent | Dim |
|---|---|---|
| LEVEL 1 yellow | #FFE600 | #9E8F00 |
| LEVEL 2 blue | #4DA3FF | #30659E |
| LEVEL 3 red | #FF0000 | #B80000 |
| LEVEL 4 neon pink | #FF46C8 | #9E2B7C |
| LEVEL 5 silver white | #D4DCE8 | #838890 |
| LEVEL 6 violet | #9C86FF | #61539E |
