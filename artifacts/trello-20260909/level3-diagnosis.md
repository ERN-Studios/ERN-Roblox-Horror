# Level 3: escape and slide entry — read-only diagnosis

**User clarification supersedes the escape interpretation below:** Level 3 must
allow players to run into the unlocked exit without a button. The report was a
requested behavior change, not a complaint about automatic escape. The run-in
implementation is recorded in `level3-run-in-exit.diff` and covered by
`tools/tests/test_level3_run_in_exit.py`. The slide issue was clarified separately
as orange wall slivers protruding into the white circular tube mouth.

9 September 2026. Current synchronized production source; no Studio/UI actions or production edits in this investigation.

## Escape without a button — 8hIQpNOw

Card report: “You dont need to press a button to escape in level 3.” No reproduction detail, comments or checklist.

**No automatic Level 3 escape path was found in current source.** Do not add another gate or change multiplayer completion policy until the behavior is reproduced.

- `Level 3 Objective Controller.ModuleScript.lua:1012` is the only Level 3 production writer of `player.Escaped=true`.
- Its containing `escapePlayer` function (`:1002`) is called only by `EscapePrompt.Triggered` (`:1289`). It requires `session.ExitUnlocked`, prevents repeated escape, calls `canUsePrompt`, and verifies a living character before awarding escape or moving anyone to the waiting room.
- `canUsePrompt` (`:193`) checks the live Level 3 round, player membership, not already escaped, prompt enabled and inside the current world, living character, server distance, and a raycast when line of sight is required.
- `insertHeldCDs` (`:769`) calls `unlockExit` only when the number of actually inserted owned CD records reaches the goal (`:812`). Merely collecting CDs does not unlock the exit.
- `unlockExit` (`:934`) disables collision on the hidden Signal Hall wall and enables the final escape prompt. It does **not** mark any player escaped.
- `Level 3 World Builder.ModuleScript.lua:1919` creates the final prompt with a 1-second hold, 10-stud range and line of sight; it starts disabled. The freight door itself remains collidable. The prompt sits on `Final Exit Lock Core`.
- `GameManager.Script.lua:2438` awards a party win when at least one living player has escaped and no living player remains inside. Dead teammates also receive the party result without pressing the exit themselves; they retain `Escaped=false`, and `:2470` only fires the completion award for actual escapees. Distinguish this intentional party result from an individual escape bypass.
- Level 1's touch escape belongs to `PuzzleManager`, isolated during Level 3 by the adapter. There is no Level 3 `Touched` completion trigger. `PuzzleWon` is read globally by GameManager but no current production writer sets it true in the searched server source.

**Separate potential finale issue, not the reported button bypass:** `escapePlayer` requires only the CD unlock. The final chase begins in `updateFinalHallChase` (`:130`) only after the music reaches `DONE` and all living, not-yet-escaped players cross the hall's halfway point. A fast player can reach the escape prompt before the whole group activates the chase. Do not change this policy under this card without confirming that this is the observed problem.

### Minimal actual-play checks

1. Direct Level 3 launch through station 9. Record server `Escaped`, `RoundActive`, `Level3ExitUnlocked`, and client/server `EscapePrompt.Triggered` timestamps.
2. Before inserting CDs, approach/touch the hidden wall and the actual final freight door without pressing E. Assert no escape. Positioning into a locked area is useful to test authority, but is not evidence of a physically reachable bypass.
3. Unlock via the real CD insertion path. Approach the freight door, stand within range, touch it and wait without E. Assert `Escaped` remains false.
4. Tap E for less than the 1-second hold, then release. Confirm whether the engine produces `Triggered`; no escape is expected for an incomplete ordinary hold.
5. Hold E for the full duration from a valid visible position. Assert one `Triggered`, one escape, waiting-room placement and correct party outcome. Repeated hold, dead character, excess distance and obstructed side must fail.
6. With two players, let one escape and leave the other alive inside: no party victory yet. Kill the remaining player: the party result can then show victory while that player's `Escaped` stays false. This isolates a likely wording/UI misunderstanding from a true bypass.

## Slide entry — psRtwdjR

Card report: “Level 3 slide entry is bugged.” No symptom or route provided. **No new definite source defect established.** The direct lobby route and Level 2 continuation intentionally differ today.

- Direct lobby Level 3: `launchStation` calls `prepareGroupLoading(..., false)` (`GameManager:2604`), so it uses the solid `ElevatorSpawn` about 26 studs inside the mall (`World Builder:1817`). GameManager then shows a seven-second service elevator sequence (`:2390`) although the compatibility elevator is invisible. It does not start the player in the tube.
- Level 2 continuation: the completion route latches `level2-exit-tube`, and `placeAtLevelThreeSlideResume` (`GameManager:744`) anchors the new character at the tube's advertised rear resume position. Client readiness must succeed before release; fallback goes to the solid pad.
- `World Builder:1541` builds the actual continuation: length 230, rise 66, radius 8, 32 longitudinal sections, 20 shell sides. Resume alpha is .93, with a downhill tangent and initial velocity 62 (`:1644`). The rear end has a collidable safety cap; attempting to climb back into it is deliberately prevented by the one-way slip behavior.
- The common `Round Entry Client` ground probe uses 20 studs for Level 3; this already fixes the previously measured ~14.9-stud ground distance that exceeded the old 14-stud ray. The 5 September validation report records a passing actual local L2→L3 continuation after that fix.
- The shared `Level 2 Slide Controller` recognizes `Level3_ProgressionSlide` and drives travel as the inverse local X axis of each panel (`:533`). `Level 2 Slide Ragdoll Service` revalidates this same direction and slope server-side (`:225`).
- World Builder's slip loop (`:1738`) applies a server fallback and returns `PlatformStand` control outside the bore. Actual client physics and recovery must be observed to distinguish a stuck ragdoll, blocked outlet, backwards ride, loading timeout or unintended pad fallback.

### Existing useful probes and minimal actual-play checks

- `Level 2 Exit Transition Test Suite.ValidateLevelThreeResume(world)` (`:396`): read-only geometry/metadata check for a rear position, correct downhill tangent, real tube floor and a solid fallback pad.
- `ProbeLevelThreeSlideOut(world, player)` (`:900`): Studio-only temporary behavioral probe; positions the actual client-owned character at the resume, observes travel for up to 14 seconds, checks actual exit speed and restoration from `PlatformStand`, then restores the player. This measures tube behavior, not actual transfer/admission.
- Actual route test: complete Level 2 via its real exit sensor, select Continue with the real result-window serial, and observe L3 entry token, release, position and velocity. Verify no unwanted arrival-pad fallback; at least 80% of bore traversed; correct forward view; `PlatformStand=false`, slide flags cleared and walking/jump control restored after the mouth.
- Direct Level 3 station start must separately yield the documented pad placement, clear loading and usable controls. Do not count that as a tube continuation test.
- Public server-to-server transport and multiple slow-streaming clients remain separate from these local checks.
