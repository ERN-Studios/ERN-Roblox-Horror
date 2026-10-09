# B2 (touch cluster) and the dev GIVE TOKENS dropdown: Studio record, 2026-10-09 01:20-02:05

## How it reached Studio
Both were already in Studio when I took the lock. Another session's bulk push (record_pending_push) carried them in between 00:46 and 01:13.

- B2's five scripts (UIDevice, UIRegression, NoiseReporter, FlashlightController, ProtectionHUD) and Zyntra Dev L4 are equal in Studio, the repo and the manifest.
- Zyntra Dev L4 includes the other session's refinement, a drawn chevron: Montserrat has no glyph for the `\u{25BE}` arrow.
- RoundHud correctly differs: the repo holds B3 phase 1, which is not pushed.
- Compile probe: 231/231.

## Incidents during the slot
- At 01:24 Studio was in a stale Play session that nobody held: t = 577 s, one idle player at the Level 1 elevator spawn. I stopped it.
- At about 01:27 Play stopped by itself, and at about 01:30 the place was closed: both Studio instances went back to the start page.
  - I reopened it with `-task EditPlace`.
  - All eleven HUD-related scripts and the three HUD templates survived the close.

## Checks
| Check | Result |
|---|---|
| Dev dropdown, closed: "CHOOSE A PLAYER" with a down chevron, inside the Economy tab | pass (`devgrant-closed.jpg`) |
| Dev dropdown, open: teal ring and up chevron, the list just under the selector and above TOKENS, "@mikkelczar (you)" | pass (`devgrant-open.jpg`) |
| Dev menu offline test | 6965 checks pass (with the other session's chevron checks) |
| TOUCH lobby: only RUN drawn (52 px); no old controls | pass (`b2-touch-lobby.jpg`) |
| TOUCH Level 1: lower row LIGHT (5 segments), SNEAK, RUN, JUMP; upper row POV (dev), GLOW, KIT, SHIELD (WAIT, dimmed); 52x52 cells; no second battery, torch or PC widget | pass (`b2-touch-l1.jpg`) |
| KIT open (via `KitFanOpen`): RailTeal KIT with an x; the fan shows only owned items (SCAN x2) right above KIT; `KitFanOpen=false` hides it | pass (`b2-touch-kit-open-crop.png`) |
| PC after `ForceTouchUI=false`: touch cluster hidden, B1 widget and chips back | pass (`b2-pc-after.jpg`) |
| A real TAP on KIT | **not verified**: MCP's synthetic mouse clicks (by path and by coordinates) did not toggle the fan under ForceTouchUI. Check on a phone or in the Device Simulator. |
| 667x375 / 568x320 rows, tablet, spectating, Level 1 capture with SHIELD, UIRegression RunAll | not run (time box); covered offline by test_touch_control_plan (545), test_equipment_hud (679), test_controller_input, test_flashlight_player_control |

## Anomaly for the coordinator (not HUD)
Twice, after the QA driver's repeated CREATE PARTY clicks, a Level 1 round was active and the player had `InRound` set, but the character stood on the LaunchZone1 pad:
- once at 20:30;
- once now, about one minute into the round, after the entry cover had lifted at 5.6 s with `RoundEntryControlsReady` true and no console error.

A fresh start at 20:37 placed the character in the elevator normally. Not investigated.
