# Owner's per-element picks · 2026-10-08

These picks were made from the HUD element sheet (Figma page 244:2, `artifacts/hud-element-sheet-20261008/`). The owner's original wording is in parentheses.

| # | Element | Pick | Owner's notes |
|---|---|---|---|
| 01 | Timer · REC | **B** | The WARNING state (amber timer row) comes from **C** ("der vælger jeg B men for warning så er det c") |
| 02 | Chase edge | **A, REDUCED FLASHING** | A's static, non-pulsing coral edge ("A reduced flashing") |
| 03 | Sneak / loud marker | **C** | ADRENALINE is not shown ("adrenaline skal ikke vises") |
| 04a / 04b | Objective card · PC | **C** | 04b was not listed separately; it is the second half of the same element, so C is assumed |
| 05 | Objective pill · phone | **C** | |
| 06 | Exit compass | **C** | |
| 07 | Flashlight | **B** | Placed in the bottom-left corner ("nede i venstre hjørne") |
| 08 | Equipment chips | **C** | |
| 09 | Detector reading | **C** | |
| 10 | Stamina | **C** | Placed at the bottom centre ("nede i bunden i midten") |
| 11 | Event feed + captions | **C** | |
| 12a / 12b | Prompt plate | **C** | |
| 13 | Leave to lobby | **C** | |
| 14 | Touch buttons · phone | **A** | KIT OPEN FAN comes from **C** |
| 15 | Level 3 hiding | **C** | |
| 16 | Level 4 note + keypad | **C** | |
| 17 | Loading card | **C** | |
| 18 | Death card | **C** | |
| 19 | Spectate band | **C** | |
| 20 | PARTY DOWN | **B** | |
| 21 | Results | **C** | |

Rejected earlier: the team row and the rail-button highlight.

Answered by the owner on 2026-10-08, later the same day:
- **"BACK WHERE YOU FELL"** (the re-entry line on PARTY DOWN): **REMOVE it** ("Re-entry linjen skal fjernes").
- **The sneaking marker stays** ("Sneaking markør bliver"). C's sneak/loud marker shows in Level 2 too.

## Approved with changes · 2026-10-08

The owner approved the combined HUD on Figma page "Final HUD 2026-10-08" (267:2): "Okay det ser rigtig godt ud." He asked for the changes below. Every other pick in the table above is unchanged. The team row and the lobby rail highlight stay rejected. Nothing is built in the game yet.

**Phone only.** PC is unchanged for all four.

| # | Change | Owner's words |
|---|---|---|
| P1 | On phone the flashlight battery is shown **only inside the LIGHT touch button** (the 14 A cell with its segments). The separate B battery and its "LIGHT" label are removed from every phone screen. PC keeps the B battery in the bottom-left corner. | "Selve batteriet paa tlf, skal kun vaere i knappen light" |
| P2 | On phone the leave-to-lobby (door) chip moves out of the way, to the **top-left corner of the safe area (x 59, y 64, 44x44)**, where REC used to be. It is small and quiet, and nothing else may overlap it. | "Samt saa skal den exit knap ogsaa rykkes vaek" |
| P3 | On phone, **remove the REC timecode** ("REC 02:37", the SIGNAL bars, the watcher count) **and the white corner brackets**. Both stay on PC only. | "Du maa gerne fjerne det her recording, og de hvide kanter paa tlf ogsaa, det skal kun vaere paa pc." |
| P4 | On phone the **objective pill is a bit smaller**: about 80 %, so 240 wide instead of 300, with text scaled to match but never under 12 px. It stays top-right in the safe area. | "Objective ui maa ogsaa gerne vaere lidt mindre paa tlf." |

