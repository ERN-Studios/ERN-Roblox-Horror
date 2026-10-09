# UIRegression shared HUD migration — offline handoff, 2026-10-09

Product source is released to the root agent for its existing Studio lock/install.
No Studio state, lock files, Git state, publish action or uploads were changed by this agent.

## Changes completed

- CompletionContract reads the actual nested button Label and expects production pressed labels `CONTINUING...` / `RETURNING...`. Final-level countdown permits `RETURNING TO LOBBY IN` and rejects a promise of another level.
- TouchTargetMatrix borrows the full workspace/player/GUI/shared-HUD state before either sweep and restores it even when both sweeps throw. Its residue assertion includes SelectedLevel, lobby shop GUI flags, nested interactivity and scrolling.
- Shared roots are deliberately excluded from stale Instance snapshots: the production probe destroys and remounts them during restore. Residue instead invokes the **actual player's** RoundHud probe, compares LastObjective to `capture.LastObjective` semantically (including a nil baseline), and remeasures the current named roots' visibility and absolute geometry.
- Feed/caption state keeps original absolute deadlines. Expired transient rows and the elapsed touch expansion are allowed to finish; restoring QA never restarts them to reproduce an obsolete visible screenshot. New fixture state/counter and geometry/visibility drift still fail residue.
- Imported panels nested inside same-name CanvasGroup wrappers are measured once; fully faded CanvasGroup ancestors are excluded.
- Hiding-with-objective setup publishes the actual Level3_Hiding gate and forbids the shared ObjectiveCard. The retired ReaderHidden residue seam and passive reader/caption movement-zone exemption are removed.
- RoundHudMatrix uses the player's real QA probe. Legacy BriefingFit, BriefingExclusion, DispatchCompact and ObjectiveCorner public entry points forward to that actual shared lane; RunAll invokes it once. Actual caption root name is `Caption`.
- Quiet-dispatch admission, live-dispatch refusal proof, lease token and harness serialization were preserved.

## Validation

- Official Luau 0.737 whole-module `luau-compile -O0 --null`: PASS.
- `python -B tools/tests/test_ui_regression_shared.py`: **25 PASS**. Executes unchanged production borrow/restore/residue helpers and TouchTargetMatrix body against the actual RoundHud and actual Framewisp PC/touch fixtures. Covers nil/copy counter restore, destroyed/remounted root identity, geometry/visibility corruption, elapsed deadlines/touch collapse, errors in both real touch sweeps followed by full cleanup, and same-name wrapper/faded ancestor panel collection.
- `python -B tools/tests/test_hud_b8.py`: **703 PASS** against actual controller blocks/imported fixtures; confirms the result labels/countdown that CompletionContract now reads.

Native Studio geometry, real fonts, real input and full RunAll remain the root agent's live QA step. This report is offline evidence, not a publish or native Play result.

## Follow-up to the first native PC RunAll

The root agent's first native PC L1 RunAll reported 429 checks / 100 failures. Analysis found a harness state defect: resetScenario still disabled RoundHud and hid its caller-owned children. That made otherwise healthy production objective/caption/marker surfaces unmeasurable and failed shared objective visibility assertions. Reset now clears only module-owned fixture state through the actual reversible probe; RoundHud stays enabled and caller-owned roots are preserved.

The revised startup requirements name the actual shared HUD/threat/recording/exit owners and omit retired per-level objective/alert GUI surfaces. Synthetic safe-slot policy remains checked against each stated fixture; readback parity separately resolves the actual native ScreenGui origin and size, including Scale=1 ancestors. Internal transparent non-interactive text labels use measured TextBounds and alignment, so empty authored padding does not create false text collisions. Buttons, backgrounds and strokes retain their complete surface/hit bounds; real ink collisions still fail.

Shop/daily/wheel chip and topmost contracts are preserved as LiveLobby scenarios. Friend Boost refuses any actual round/loading state and requires the body physically inside the server-selected lobby, so these rows explicitly skip in a live L1 round and still need a native lobby pass. The recording-line/HiddenStatus overlap is **not** exempted; it remains a product candidate for the root agent's B6 hiding probe.

Expanded offline helper: **47 PASS** (the original 25 plus 22 focused checks), including real reset → stage → Scan measuring objective/caption/noise marker; retired-versus-current startup requirements; independent fixture/native frame resolution; genuine versus padding-only text collisions; and active/loading/physical/server-selected lobby admission. Whole-module official `-O0` compile passes. Revised source is released for install; focused native scenarios/shared/exclusion reruns remain to verify these changes in the engine.

## Follow-up to the second native lobby RunAll

Root saved the full, non-truncated native report as `codex-studio/native/phone-lobby-runall-full.txt`: 1023 checks / 40 failures. Its current input layout reports desktop/pointer at 666×374 even though native touch hardware is present. The shared module's 33 Chevron font-fit failures and one modal fade-timing failure are owned by the shared-module agent.

The remaining scenario audit identified these harness corrections:

- The hiding fixture now publishes both actual InRound and Level3_Hiding. Previously it drew forced hiding UI while leaving the lobby token pill eligible.
- The Level 1 receiver row now explicitly requires the shared ObjectiveCard; an empty row cannot pass.
- Compass ticks, centre line and pointing glyph are the joined marks of one bearing graphic. Their measured ink union remains separate from the metre Readout and all objective rows; real collisions between that union and the readout still fail.
- Lucky Wheel's authored image is circular. At the reported safe 666×316 shape, the 271px disc occupies the square approximately `(197.5,22.5)–(468.5,293.5)` and the 44px X approximately `(431.7,15.3)–(475.7,59.3)`. The X overlaps the empty square corner but its nearest corner is about 4px beyond the circular rim. Scan now models the actual circle, plus protruding rotated pointer and text regions. Close retains its complete interactive bounds. Genuine rim/pointer collisions still fail; opaque or misaligned holders receive the ordinary rectangle treatment.

Two product candidates were sent to root without exemptions: the hybrid in-round dev chip admits raw TouchEnabled but chooses desktop positioning from UIDevice.IsTouch=false, intersecting the shared card/hiding UI; and the first objective row briefly reports FlashlightWidget versus an unmirrored Achievements.Open. The ZyntraStore candidate is assigned separately to the conversation agent.

Expanded offline helper: **68 PASS**, including the original restore/error cleanup tests and focused bearing/readout collision, circle/rim/pointer collision, complete Close44 bounds, opaque/misaligned circle fallbacks, and the real hiding Setup. Whole-module official `-O0` compile passes. This UIRegression source is frozen/released for the root agent's next install and native rerun.

## Changed paths in this final assignment

- `ReplicatedStorage/UIRegression.ModuleScript.lua`
- `tools/tests/test_ui_regression_shared.py`
- `artifacts/hud-final-20261008/UIREGRESSION-MIGRATION-QA.md`
