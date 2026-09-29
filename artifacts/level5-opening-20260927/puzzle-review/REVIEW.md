# Fresh v2150 puzzle and clue review

## Scope

Reviewed the root task's fresh Studio export at `../baseline/sources`, after reading the repository `AGENTS.md`. This reviewer made no Studio calls and changed no runtime or repository files. Seven reviewed scripts have matching Source/editor hashes and are byte-identical to the previous repository mirror; details are in `verification.json`.

The seven puzzle answers and submissions remain internally consistent. No fresh native gameplay, movement, rendering, or shared multiplayer completion is claimed. The root task owns those checks and all Studio writes.

## “Clue sign after the first section”

The likely candidate is B's Domestic Symbols board. Its answer is **LAMP → CUP → KEY**, indices `{2,4,1}`. Both printed board and UI use the same server definition and the same drawing implementation. Its labels are numbered 1/2/3, so ordering does not depend on recognizing the pictures. Sources: Puzzle Catalog line 11; Section Progression lines 305–349; client lines 33–67 and 122–143.

There is no evidenced orientation or wall-occlusion error in the fresh source:

- Architecture places `B_LowEavesArcade.ArcadeCrossLaneHome_1_0` at local `(0,0,272)`, facing the entering player (line 692). The selected median clue candidate is unchanged from the historical native map record.
- The home is 50×22 studs with a clear central hall. Its clue marker is local `(0,6,293.62)`; the board is `(0,6,293.52)` with `SurfaceGui.Face=Front`, facing negative Z toward the entrance (Architecture 499; Progression 130, 330). With origin `(17000,24,0)`, board world center is `(17000,30,293.52)`.
- The board's visible front is Z=293.455. The interior wall lining's visible face is Z=293.6425, so the board is 0.1875 studs in front of it. Its rear remains 0.0575 studs ahead of the lining. This is not coplanar or behind the wall.
- Side partitions sit at X=±5.5; the 6-stud-wide board occupies X=−3…3. Kitchen and breakfast furniture sit near X=−23.28/+23.1, leaving the central clue lane clear (Architecture 479–499; Furniture 234–254).
- The surface is 900×720 over a 6×4.8-stud board, with three columns, readable written labels and fitting square pictograms. It is affected by scene lighting (`LightInfluence=1`) and cannot be seen through walls (`AlwaysOnTop=false`). Whether the actual view is too dark or too small requires a native view.

Do not rotate, relocate, or replace the clue based only on the phrase “after the first section.” It might instead refer to gate 1's overhead section plaque. The supplied read-only inspector distinguishes the 12 actual clue panels from the seven gate labels. A native screenshot from inside B or the user's clarification should identify the exact requested defect.

## Actionable findings and limits

1. **Public-level completion remains absent in this baseline.** Round Adapter lines 2–5 explicitly describe preview gameplay without `Escaped`/`PuzzleWon` or rewards. `Build()` lines 262–265 rejects a non-developer roster. H geometry alone does not complete a level. Opening lobby access requires a verified ending implementation and review of all current entry restrictions; seven correct puzzle answers are insufficient release evidence.
2. **Through-wall prompts can look broken.** All puzzle prompts have `RequiresLineOfSight=false` and 12-stud range (Progression 280), but server `canUse` demands a clear root-to-lock ray and ≤14 studs (141–154). E can appear from the back of a nearby gate and do nothing. Keep server validation. If reproduced natively, consider prompt LOS or explicit unavailable feedback after verifying legitimate front approaches on all seven locks.
3. **Very short viewport is still a known edge.** The client imposes a 248px minimum panel height (163), exceeding 244px usable height on the existing 320×280 example. All nine normal modeled viewports still pass. No physical mobile/controller test was performed.
4. **Historical UI inspector is stale.** `artifacts/level5-dense-routes-20260926/qa/inspect_household_puzzle_ui.luau` looks for a child named `Frame`, while fresh client line 90 names it `ModalInputBlocker`. This would falsely report a missing panel on an open UI. A corrected copy is included here as `inspect_household_puzzle_ui_v2150.luau`; the runtime itself needs no change for this diagnostic bug.
5. **Clue search difficulty needs actual walking.** C uses three widely separated homes; G's clue is in a western ground-level house away from the raised route. Source equality preserves earlier coordinates, but fresh traversal has not been established.

## Tests executed against the fresh baseline

- `test_level5_puzzle_catalog.luau`: **6,910 assertions passed**, including all 2,185 possible combinations across seven gates, malformed inputs, ordered attempts, nonce/session expiry, and cooldown boundaries. Every puzzle has exactly one correct answer.
- `test_puzzle_layout_math.luau`: **2,737 assertions passed**, seven puzzles × nine modeled viewports; retains the known tiny-height limitation.
- Seven reviewed scripts compile with the local Luau compiler.

These are pure logic, arithmetic, and syntax results. Test copies only replace their `require` path to use the fresh baseline. They do not load production Studio modules or mutate source.

## Native check sequence for the root task

1. Run `inspect_clues_readonly.luau` in the current native world. It records the 12 clue faces, actual labels, sample eye/support/obstruction rays, and seven gate/prompt states without modifying any object. Rays are not proof that a player reached that point.
2. Walk into B's first centre home and inspect the board from its hall, then compare the gate 1 overhead plaque if the requested sign is still unclear.
3. Open each gate through its normal E/ButtonX prompt; inspect the actual open UI with `inspect_household_puzzle_ui_v2150.luau`; submit one wrong then the correct answer. Verify both leaves finish opening, the UI closes for other participants, and the next gate only activates afterward.
4. Answers: A `RED/YELLOW/BLUE/GREEN`; B `LAMP/CUP/KEY`; C printed digits `2/6/4` in RED/BLUE/YELLOW order; D `UP/DOWN/UP`; E `3:00/9:00/6:00`; F `CH04/CH07/CH02`; G `RIGHT/DOWN/UP`.
5. Complete actual F main route, pit recovery and clue detour, G clue detour/terraces, and H ending. Preserve any unverified movement, input, or completion item in the release report.
