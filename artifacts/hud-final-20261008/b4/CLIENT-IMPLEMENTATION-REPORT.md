# B4/B5 receivers and B7 Level 4 cards

Implemented offline on 2026-10-09 by conversation_audit. Root owns installation/live QA. No Studio, lock, git, upload or external message was performed by this agent.

## Changed product sources

- PuzzleUI: replaces the old Level1Objectives/toggle/ExitEnergyDetector surfaces with RoundHud.SetObjective; keeps real PuzzleStatus receiver and private refusal delivery. Legacy team events use shared Feed keys, actor strings remain available for DisplayName resolution. Fuse/lever/exit counts are ordinary data. UIRegressionPuzzleProbe is now under RoundHud.Gui and returns a plain state table.
- Level 2 Objective UI: attr-driven receiver publishes pump states, lethal danger and powered-exit guidance; legacy top-deck climb guidance survives. Explore-only Level2NewMapPreview cannot inherit the old-kit pump HUD. No map or server mechanics changed here.
- Level 3 Reader Client: replaces ReaderPanel/ReaderRestore/R/Y hiding/toast drawing with objective/Feed calls; preserves current authoritative CD state, nearest-disc selection, PLAYER mode, streamed player locator, precise world-pinned CDPlayerGuide, generation guard, 10 Hz polling, signal teardown and ReaderHint. Hint measures the shared card's real absolute rectangle and keeps MOBILE_QA placement; it yields while a shared feed row is visible. Missing watched subjects never create a parked-body compass. Studio force cannot activate Level 3 guides under another selected level.
- Level 4 Round Client: shared objective/carry/room/status/compass and Feed/Caption calls replace only the old panel/chips/say surface. The note/keypad use imported HUD_Screens/Level4Note and HUD_Screens/Keypad at order 60. Four PatrickHand lines, tap/E/B close, N/D-pad-up/Order reread, exact four-digit submit, real WRONG CODE event/timer, pad focus links and device remount state are implemented. A dead player cannot reopen the private note. Touch CloseHit is 44 px and Level4CardOpen remains published.

## Verification completed

Luau 0.737 compiled all four touched clients successfully.

| Suite | Result |
|---|---|
| test_objective_receivers.py | 66 production-code runtime checks passed, including legacy/new-map Level 2 separation and Level 3 exact CD-player projection/movement bounds |
| test_level4_note_keypad.py | 91 production-code runtime checks passed, using actual imported HUD_Screens fixture trees |
| test_level1_team_prompts.py | rebased to actual shared server delivery and new client state/Feed: 21 server + 15 client checks passed |
| test_level3_first_cd.py | 7,937 checks passed across 240 seeds; server/native Random sweep remains outside offline coverage |

Direct source comparisons against the scoped before snapshots proved these blocks remained exactly unchanged: Level 4 TORCH_GLINT, Level 4 Usher implementation, Level 3 streamed CD-player locator, and Level 3 pure PLAYER-mode/projection helpers. Level 4 REEL_ROOMS parsing keeps first-occurrence order and duplicate x2 formatting; its data now feeds the shared card.

## Remaining integration validation

Root must install the coupled shared module, retire RoundUI/Round Exit references and port UIRegression in the same batch. Native template pixels, platform glyph loading, pad selection-ring display, hint/scene-guide placement and modal/dispatch timing need live PC/touch/pad QA. No offline fake engine result is claimed as live QA.

Read-only UIRegression audit recommendations were sent to root: stage through a real player-client shared QA probe; replace obsolete corner/reader bodies while preserving lane guard, pcall, cleanup and residue checks; compare exact current TopRightPanel output; restore shared semantic/current/last-objective state because device remount destroys old descendant identities; add full borrow/restore to TouchTargetMatrix. Do not keep old hidden/restore assertions or missing-panel skips that can pass without measuring the new card.
