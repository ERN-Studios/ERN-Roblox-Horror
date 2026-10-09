# Native phone DEV chip correction

Only product changed: StarterPlayer/StarterPlayerScripts/ZyntraStore.LocalScript.lua. No Zyntra Shop changes.

The DEV chip used raw TouchEnabled for admission and UIDevice.Layout().IsTouch for sizing/placement, so a native emulator or hybrid with mouse+keyboard could display a 280x64 desktop button over objectives and hiding. Admission and layout now use the same UIDevice result; pointer layouts keep the existing J access, and true touch keeps the visible 44px minimum chip.

The existing ordered placements now reserve the current imported ObjectiveCard dimensions and visible HiddenStatus, LeaveHiding and TableCheck roots. A further candidate below the hiding band preserves the touch chip when its old spots collide. Known HUD-root size/position/visibility changes and device remounts coalesce a deferred placement refresh. HUD coordinate conversions use UIDevice.LocalOffset, including synthetic fixture origins. Lobby rail, skins, modal order, purchases and window bridges remain intact.

Validation: product compile PASS; test_zyntra_store_compact.py 777 PASS; test_zyntra_dev_chip.py 27 PASS. New regression runs the production UIDevice classifier and production updateVisibility plus geometry subscriptions. The original source fails the exact raw-touch/desktop-admission assertion. Existing store test modal set was stale at six; updated to the already-shipped eight (Achievements/Help), with no UIDevice edit.

Native/Studio re-test and installation remain with root. No Studio calls, install, publication or git mutation occurred here. Hashes and scoped diff: proof.json, ZyntraStore.diff.
