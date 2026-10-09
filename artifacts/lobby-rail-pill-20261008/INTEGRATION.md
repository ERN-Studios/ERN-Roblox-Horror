# Review fixes: token pill and Friend Boost over the rail windows

I applied five fixes, one of them test-only, and rejected one finding. All required suites pass apart from the known `test_lobby_shop_display.py` failure, which was already failing before this change. Every edited Lua file compiles. Studio was not touched and no git state was changed.

## Changes per file

- **`StarterPlayer/StarterPlayerScripts/Zyntra Shop L4.LocalScript.lua`** (the draft copy is byte-identical; no new top-level local):
  - The `PC_DOCK_BELOW` comment is reworded to the correct bound (R2-F4).
  - A `wasOver` local sits inside the pill do-block. When a window closes, `refreshPill` clears `GuiService.SelectedObject` only if it is inside `pillGui` (R1-F1).
  - The "+" handler now starts with `if not ui.build() then ui.refreshPill() return end`, so the other window is never closed for a shop that cannot open (R1-F4).
  - The docked branch now also needs `right - width - (6 + 104) >= band.Left`. That reserves room for Friend Boost's docked line (GAP 6 + LINE_WIDTH 104), so an expanded unibar hides the pill, and with it the chip, instead of putting them under CoreGui (R1-F2 and R2-F2).
- **`StarterPlayer/StarterPlayerScripts/Friend Boost Client.LocalScript.lua`**: adds a `GuiService` local and a `wasOver` local (43 top-level locals now). `refresh` clears selection inside `gui` only at the moment a window closes, so the 0.5 s poll does not clear it at rest (R1-F1).
- **`tools/tests/test_friend_boost.py`** (CRLF kept): adds a fake `GuiService` and `methods:IsDescendantOf` to the harness, plus 4 gamepad checks:
  - focus holds while the window is open;
  - closing the window clears it;
  - focus on the chip at rest is left alone;
  - focus on another UI is left alone.
- **`artifacts/shop-ui-figma-20261005/roblox-draft/tests/zyntra_shop_l4_harness.luau`**:
  - `band(height, left)` takes a left edge now.
  - Block 8c gains:
    - a 1180x820 touch tablet case, which docks because it is touch, not because of width (R2-F1);
    - a boundary pair for the band's left edge: exact fit keeps the pill, 1 px less hides it at DisplayOrder 55, and collapsing the unibar docks it again;
    - three gamepad checks.
  - Block 8d gains a case where Page_Shop is missing: the switch is never invoked, Daily stays open and the pill stands down.

Each of the four Shop fixes and the Friend Boost fix fails its new check when reverted. I restored every file afterwards and confirmed with `cmp`.

## Findings

| Finding | Decision |
|---|---|
| R1-F1 gamepad focus stuck on the pill or chip | **Applied** in the pill and the chip. The rail has the same hole; it shipped as accepted integration risk 7, so I left it alone. |
| R1-F2 / R2-F2 band left edge | **Applied** as one clause in the Shop. The chip only shows over a window when the pill is drawn, so it is covered too. This adds no Friend Boost geometry code, but the Shop now restates GAP and LINE_WIDTH in a comment and a test. |
| R1-F4 "+" closes a window before the build is known | **Applied** |
| R2-F1 the touch clause of the dock rule was untested | **Applied** (the tablet case) |
| R2-F4 wrong comment | **Applied** |
| R1-F3 / R2-F3 the docked PC chip has no "INVITE" label | **Rejected.** The click still works; this is the compact line the owner approved for touch, the plan lists it as owner check 8.5, and new copy such as "INVITE +x%" is the owner's call. It only happens on a PC under 1120 px wide with a window open. |
| R2-F5 the 44 px tap floor | No change: it already failed before this change and is not made worse. |
| R2-F6 the sync manifest and stray files | No change now. The manifest must be refreshed after the Studio push. The stray files at the repo root were already there; they now include `1.405` and `57`. |

## Final test lines (LUAU_BIN = luau 0.737)

- `test_zyntra_store_compact`: ok, 751 checks
- `test_friend_boost`: 845 checks passed (was 841)
- `test_lucky_wheel_client`: 657 passed
- `test_dev_free_respawn_offer`: 3 + 8; `test_equipment_hud`: 303; `test_rail_dots_intro`: 20; `test_reentry_dismissal`: 37 + 5; `test_ui_style`: 83; `test_controller_input`: 102; `test_round_exit_hold`: 299
- `roblox-draft tests/test_zyntra_shop_l4.py`: ALL CHECKS PASSED (11712, was 11703) + dump round-trip
- `daily/tests/test_zyntra_daily_l4.py`: 935 passed, 5 drafts equal their mirrors
- `dev-menu/tests/test_zyntra_dev_l4.py`: 6903 passed
- `test_lobby_shop_display.py`: FAIL ("expected 8 product textures, found 10"), the known earlier failure

`luau-compile --null` returns rc 0 for Shop L4 (mirror and draft), Friend Boost, ZyntraStore, Lucky Wheel, UIRegression and the Shop harness. The files edited this round have 0 CR bytes and no non-ASCII; the other edited Lua files also have 0 CR bytes, and their only non-ASCII is old box-drawing comments. `git diff --check` is clean. `cmp` reports identical draft and mirror for Shop, Daily and Dev.

## Geometry (Layout space, topbar band y -58..0, window open)

| Device | Docked pill (x, y) | Docked chip, 104x44 tap | Hides when band.Left > |
|---|---|---|---|
| 844x390 | 683..836, -55..-3 | 573..677, -51..-7 | 573 |
| iPhone 13 | 588..741 | 478..582 | 478 |
| 705x338 | 544..697 | 434..538 | 434 |
| 667x375 | 506..659 | 396..500 | 396 |
| 1180x820 tablet (touch) | 1019..1172 | 909..1013 | 909 |
| PC 1100 safe width | 939..1092 | 829..933 | 829 |
| PC 1280 / 1366 / 1920 | stays in the corner at 119 (not docked) | box under the pill | n/a |

- With the unibar collapsed the band starts at about 164 px (measured on an iPhone 16 Pro Max), so the guard only trips when the unibar expands.
- The windows start at y 0 or below and the docked row ends at y -3, so nothing overlaps.
- Window fits and tap sizes are as in plan §6 and unchanged: 44.4 on 844x390; 41.5, 37.5 and 40.9-42.4 on the other phones; Dev 35.3-42.3.

## Studio must still confirm

1. Rendering and taps in the topbar band under DeviceSafeInsets, and `GetGuiObjectsAtPosition` at negative y. Use the Device Emulator at iPhone 13 and 705x338 with ForceTouchUI, a 1100 px PC window and a touch tablet.
2. That `TopbarSafeInsets.Left` really moves when the unibar expands: expand it over an open window and watch the pill and chip hide, then come back on collapse.
3. Gamepad: D-pad from a window onto the "+" and INVITE, close with B, and check the pad drives the character again. The rail still has risk 7.
4. Whether `PromptGameInvite` sets `GuiService.MenuIsOpen`. If it does, Daily closes underneath, which is harmless.
5. Run the UIRegression rows `store-modal`, `daily-modal` and `wheel-modal` with the character inside the lobby box.
6. Ship as one batch: drift-audit the Studio copies, push all five scripts together, run the compile probe before UIRegression, then refresh the five manifest entries (bytes and sha256).
7. Owner checks:
   - the docked PC chip has no "INVITE" label;
   - the token pill now shows twice (the lobby pill plus the Shop and Daily headers);
   - the window tap targets are under 44 px on the small phones;
   - plan step 11 docs are still to do (CLAUDE.md note and `INTEGRATION-CONTRACT.md:624-625`).