# Phone and tablet QA, 2026-10-08

Reports (`<state>__<WxH>.txt`) and pictures (`.jpg`) from `tools/mobile_qa/qa.py`, taken in Studio play sessions
with the touch fixture (`ForceTouchUI` + `UIRegressionViewport`). A picture of a device larger than Studio's
viewport is scaled down after measuring; scaled pictures exaggerate text clipping, the `CUT` lines do not.

Sizes: 568x320, 667x375, 705x338, 844x390, 956x440 (phones, landscape), 390x844 (portrait), 1024x768, 1180x820,
820x1180 (tablets).

## What was covered

| Where | States |
|---|---|
| Lobby | idle HUD (all nine sizes), shop (Settings, Shop, Upgrades, Skins), daily rewards, lucky wheel, badges panel, help, first-login tutorial, queue host panels |
| Shared round screens | party down, level cleared, loss, spectate, hiding (the suite's own stagings) |
| Level 1 | HUD, mission brief, entity detector |
| Level 2 | HUD, entity detector, death -> PARTY DOWN with the re-entry offer |
| Level 3 | HUD, CD hint card, hiding under a table |
| Level 4 | HUD, keypad, note card |
| Level 5, Level 6 | HUD |
| `UIRegression.RunAllCompact` | before: 22 of 24 scenarios failing; after: 3 (all three older than this pass, see below) |

## Fixed (all in Studio; markers `MOBILE_QA_20261008`)

1. HELP and BADGES buttons lay on MUTE or under the bottom edge on phones.
2. BADGES and HELP windows opened under the token pill and the rail (close button covered on phones) and shrank to
   unreadable text. They are screen-owning windows now, full-size text, scrolling.
3. Achievement toast was "visible" while parked off screen (20 false scenario failures in the suite).
4. Lucky Wheel title lay under the rail and on the disc on phones.
5. Level 1 MISSION BRIEF showed a header and no objectives on every landscape phone.
6. Level 4 objective card lay under the touch buttons; its keypad ran off small screens and the LOBBY chip lay on
   the code display.
7. Entity detector device and status line covered SCAN/HIDE, DROP GLOW, SNEAK and RUN on small phones.
8. LOBBY chip stood in the thumbstick's zone on every phone in Level 1 (now beside the mission brief from 667x375 up).
9. LOBBY chip lay under LEAVE HIDING on 568x320.
10. Level 3 CD hint card fell on the touch buttons on 667x375 and smaller.
11. DROP GLOW showed in Levels 5 and 6, where it does nothing.
12. HOLD WIDE was 10 px.

## Found and not changed

- **Portrait.** The game allows it (`ScreenOrientation = Sensor`). The shop and daily rewards windows keep their
  landscape shape there and come out about 330 px wide with 5 px text (`sc-daily-modal__390x844.jpg`). Owner's call:
  lock to landscape, or give those windows a portrait layout.
- 568x320 (the smallest phone): the LOBBY chip is still 15 px inside the thumbstick's zone (44 px in Level 1), the
  shop's and wheel's small labels are 8 to 10 px, SIGNAL LOST touches the PARTY DOWN card.
- Equipment slots keep fixed places, so with two of four owned there is a gap between SCAN and SHIELD.
- The torch's art reaches about 18 px into JUMP.
- Suite, still failing: `wheel-modal` (the close button and title inside the disc's bounding square: by design) and
  the two `level3-reader` rows (the lobby's token pill is on screen in that staging; it is not in a real round).

## Not tested

A real phone or tablet, real touch input (Studio has no thumbstick), the notch (the fixture has no housing), the
Level 6 kill cam at phone size, more than one player, Donate and Colors tabs of the shop.
