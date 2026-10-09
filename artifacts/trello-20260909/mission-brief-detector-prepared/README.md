# Mission Brief / exit detector touch separation

Prepared PuzzleUI-only correction to the native compact overlap found during exit-compass acceptance. RoundUI and the existing 168×44 Mission Brief button, its help handler, objective column, compass geometry and direction calculations remain unchanged.

The detector subtracts the measured Mission Brief rectangle plus an 8 px gap from its existing movement-safe candidate rectangles. It prefers the space beside Brief; remaining candidates retain the existing ordering. The two ScreenGui origins are converted through UIDevice.LocalOffset, including synthetic viewport origins. Brief is reserved while hidden to prevent a jump when the help panel closes. Exact-button property/replacement signals handle script startup and resize ordering.

When no positive candidate exists, the active detector is temporarily hidden rather than redrawn over Brief; a valid touch layout or desktop layout restores it. This branch is for degenerate areas, not an assertion that every viewport can hold both cards. The focused supported-size fixtures retain a visible, readable detector.

Exact files and hashes: manifest.json. Proposal SHA256 `00e8da12537d57de12c347a89fd7838c1532015bc9cbe526f9fe982f9f322ba0`; baseline `cc1c8fdf497130c82be1f7174df1a035f9936790974316d76435357651ce3680`. Parent owns installation and publishing. No production writes were made by this task.

Run `python artifacts/trello-20260909/mission-brief-detector-prepared/test_layout.py`: 23 checks execute the actual complete applyPuzzleLayout, new geometry helpers, setReceiver and button watchers. Cases cover 844×390 and 568×270 fixture inputs, mixed GUI origins, late/replaced/removed buttons, resize and inactive/degenerate/desktop restoration. The unchanged previous layout fails the concrete overlap assertion. Both complete source files compile. UIDevice layout outputs and row/text measurement are controlled host inputs; this is not native font, physical device or pointer evidence. The exact transform reproduces the proposal from the preserved baseline.

Native acceptance is intentionally short: on the actual 844×390 phone layout, inspect NAV and the Mission Brief button together, tap Brief and close its help panel, verify the arrow/readout, objective counter and movement controls remain readable and unobscured, then restore the regular viewport. Existing desktop/direction/modal/cleanup evidence may be reused because those mechanics are unchanged. Do not claim 568×270 physical-device acceptance from the controlled host.
