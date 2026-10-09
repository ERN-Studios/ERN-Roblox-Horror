# B1 in Studio: install and QA record (2026-10-08, evening)

## Install
- `ReplicatedStorage.RoundHud` (new) was created with `tools/install_new_scripts.py`, then VERIFIED and added to the manifest.
- Pushed by compare-and-swap with `_local/shop-ui-figma/studio-turn/install_hud_b1.py`; each was drift-checked against the manifest first and read back after:
  - UIStyle
  - FlashlightController
  - ProtectionHUD
  - ZyntraDetectorClient
  - PuzzleUI
- Compile probe: 231/231. Drift audit afterwards: none of the B0 or B1 files drift. The other 37 drifts belong to other sessions and were left alone.
- Two fixes from the offline verify went in before the push:
  - The detector card now sits above the refusal-tag band, so a refusal during a reading no longer draws under it.
  - The flashlight keycap is hidden while spectating.
- One stopgap: on PC, PuzzleUI's Level 1 exit receiver stands 228 px up, clear of the bottom-left kit. B4 retires it.

## Studio Play, Level 1 round
| Check | Result |
|---|---|
| PC flashlight B bottom-left, F keycap, 5 segments, LIGHT OFF at full | pass (`b1-l1-pc-start.jpg`) |
| F turns the light on, and it reads `LIGHT · WIDE` (Advanced Equipment owned) | pass |
| Battery drains from the right (4 lit + 1 dark) | pass (`b1-l1-pc-shield-active.jpg`) |
| Owned chips only (SHIELD Q, SCAN Z), resting at 40 % | pass |
| Z scan: detector card above SCAN, clear of the tag band, `SCAN · LOW` / `SAFE DISTANCE` / `28 s`; SCAN shows the `38` cooldown | pass (`b1-l1-pc-on-shield-scan.jpg`) |
| SHIELD ACTIVE `4.2 SAFE` | not reached: the shield stays WAIT in the elevator and maze start under the shipped availability rule (old touch square agrees: SHIELD WAIT) |
| TOUCH (ForceTouchUI + 844x390): PC widget, chips and card hidden; old touch buttons still there for B2 | pass (`b1-l1-touch.jpg`) |
| PAD glyphs | not run: MCP cannot emulate a gamepad; covered offline (test_round_hud Keycap rows) |
| Spectating THEIR LIGHT | not run (needs 2 players); covered offline |
| Level 1 receiver over the kit after power is restored | not run; covered by layout arithmetic |

## Observations for the owner
- The detector card's soft fade (the B/C template's Soft ramp) makes `28 s` faint over Level 1's bright cream walls. It reads well on dark backgrounds. This is a design call, not a bug.
- The flashlight line reads `LIGHT OFF` at full battery; the approved tiles have no wording for that state.
- On the first start, the character stayed on the lobby pad with `InRound` true after three CREATE PARTY clicks. A fresh start placed it in the elevator normally. Not reproduced.
