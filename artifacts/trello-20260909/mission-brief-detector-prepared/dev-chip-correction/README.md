# DEV chip extension

Exact PuzzleUI-only extension of the reviewed 00e8 Mission Brief correction. Native iPhone 13 layout exposed a second collision: ZyntraStore.ZyntraOpenButton at (295,8), 136×44 covered the detector at (260,8), 164×116. This uses the same measured common-space rectangle and candidate subtraction for that exact button. A hidden ordinary opener does not reserve space; the DEV caption retains its reservation while a modal hides it. Position, size, visibility, caption, late creation and replacement trigger the same layout. Store, whitelist, input and game rules are untouched.

The recorded candidate fits below the chip at (260,60), 164×116 in the controlled geometry fixture. Native text rendering and controls must still be inspected by root. This folder preserves the previous proposal and its native failure rather than replacing their evidence.

`python artifacts/trello-20260909/mission-brief-detector-prepared/dev-chip-correction/test_layout.py` runs the complete current applyPuzzleLayout and its actual helpers/watchers: the previous 23 checks plus 9 DEV checks. The exact before source fails the newly reproduced DEV overlap. Both complete sources compile. Proposal hash and exact baseline are in manifest.json; no production writes by this task.

Root's short acceptance: verify the actual phone NAV card below/clear of DEV, both header/readout and the existing compass visible, Mission Brief still opens/closes, counter column and movement controls clear. Ordinary-player visibility is a code check unless a real ordinary account is actually used. Restore the standard viewport afterward.
