**Verdict:** the baseline breaks the finale policy in four places (any-one barrier, spawn ladder, 90-stud gate, protection exclusion) and has no CD-player scanner mode. Nothing was run, so there are no runtime facts: **[Read]** is visible in the supplied lines, **[Inferred]** depends on code not supplied. Fixes stay inside the three mirrored scripts except finding 5 (Adapter), which needs a fresh fingerprint first.

## Finale (Objective + AI)

1. **Barrier is ANY, not ALL [Read].** Objective L176 fires once `crossedCount ≥ 1`. Fix: `if eligibleCount == 0 or crossedCount < eligibleCount then return end`. Already compliant: strict `>` (L159), character-scoped latch (L148/161), removal clear (L1471), and no protection check in L113–129, so protected participants count.

2. **Spawn is not the authored point [Read].** AI L3400–3401 clamps progress to .90–.98 and walks `{preferred, .95, .93, .90}`: alternate points, and a silent override of any re-authored marker. Fix: one candidate from `hall.SpawnMarker.Position` at `FloorY`; no clamp, no ladder.

3. **The 90-stud gate defeats an ALL barrier [Read + arithmetic].** L3408 needs every participant ≥90 studs away. Anyone past about 453 studs (81%) blocks all four candidates, so `Start` returns nil and the adapter polls every .35 s (L298). Fix: drop the gate for the finale. **Decision for you:** if someone is already at the marker, spawn anyway (my reading of "exactly") or hold; baseline holds silently and indefinitely.

4. **Protection blocks spawn and chase [Read].** L3318 drops protected players from spawn records, L151 from targeting. All protected means nil and delayed retries; with nobody targetable, L2064–2081 starts random mall-room patrol. A protected body on the marker also fails `spawnVolumeFits` (not in the L3356 exclude list). Fix: a finale-only participant predicate without the protection clause for spawn records, facing and navigation; leave `attackLineClear` (L2491) and the windup confirm (L2530) untouched. In finale no-target, hold in the hall; never `choosePatrolGoal`. **[Inferred]** `forgetProtectedPlayer` (body not supplied, runs every Heartbeat, L3890) probably clears such a target each frame.

5. **Retry gaps [Read].** Adapter L289 keeps any existing session (a non-finale Manager would not be replaced). L291–294 never retries a thrown `Start`, and the latch (L132) never re-fires. **[Inferred]** Normal flow is safe: DONE drops Hunt once (Music L120), then Objective raises it for a fresh start.

6. **Recovery relocation.** **[Read]** `resetBlockedRoute` (L2685–2692) is bookkeeping only; the only supplied hard snap is the spawn publish (L3939). **[Inferred]** Overlap-escape, `rebuildStrategicRoute` and `installRoomPerimeterPath` were not supplied, so this stays unverified.

7. **Pause [Read].** The trigger ignores `EntityPaused`; the Manager spawns, goes PAUSED, then resumes CHASE on the next think tick. Paused kills are refused (L2491 via L140).

8. **Latch and stale position [Read].** The latch means "has been beyond midpoint", monotonic per character, so walking back keeps it, as required. It matters only here:
   - The trigger can fire with a latched player back in the mall; targeting prefers in-hall players (L2033), otherwise the Manager follows them out.
   - A revived character already beyond midpoint re-latches from its own position within 0.1 s: no inheritance, but no physical re-crossing either. Confirm.
   - A living participant briefly without a character drops from `eligibleCount` and can fire the irreversible trigger early.
   - **[Inferred]** A stale `InRound = true` on a living lobby character now deadlocks the finale; that fix belongs in GameManager.

9. **Cleanup [Read].** Reset clears the finale attributes (L1622–1655), but ChaseActive (L1654) drops before Hunt (L1655), so a live Manager can publish one normal-profile state. Reverse them.

## Scanner (Reader + Objective)

1. **No CD-player mode [Read].** `cd == nil` drops into the exit branch (L1003–1010) with its deliberate bearing noise (155° scale at zero inserts). Add the priority disc, then CD player, then exit, on the no-noise path.

2. **"No beacons" is not "secured" [Read].** L901 drops WORLD/DROPPED discs lacking a Vector3, and goal falls back to 5 (L953). Fix: a pure function over `Level3_CD<n>State` for 1..goal. Any WORLD/DROPPED gives disc mode, even without a position; all CARRIED/INSERTED with at least one CARRIED gives CD player; any empty or unknown state gives neither. Ignore cumulative counts. Keep it outside the block ending at L913, which `test_level3_first_cd.py` runs. **[Inferred]** Exact state strings; the publisher was not supplied.

3. **Position is not published [Read].** `Level3_CDPlayerPosition` is absent from the supplied start (L1491–1510) and reset (L1611–1655) lists; the rest of Objective was not supplied. Publish after the visual pass; set both attributes nil at start and reset, because the L684 helper falls back to the workspace mirror.

4. **Bearing is not 360° [Read].** L1001 clamps to ±90°, L1014 smooths a scalar across the ±180° seam (sweeping through "ahead"), and L918 returns 0 when the camera is vertical. Fix: heading from `Vector3.yAxis:Cross(camera.CFrame.RightVector)`, shortest-arc smoothing, reset on mode change.

5. **No pointer exists in the supplied Reader [Read].** Use `camera.CFrame:PointToObjectSpace`; when the target is behind (Z > 0), never draw at projected coordinates; clamp to the safe-area edge along (X, -Y). **[Inferred]** The 10 Hz tick (L24) will stutter; project per frame.

6. **Gates and teardown [Read].** Early returns at L947–951, L962–967 and L977–983 do not reset other widgets (stroke and needle colour already go stale). Drive the pointer from the panel's own expression (L937) plus root and target, hide it on every return, keep it non-interactive, and destroy it in `teardownReader` if it lives outside `gui`.

7. **Wording.** Product terms only, e.g. `> CD PLAYER READER`; no state names or attribute vocabulary.

## Runtime test matrix (none run)

| Finale case | Expected |
|---|---|
| 3 alive, 2 crossed | No trigger |
| Last crosser passes 280 studs | Trigger within 0.1 s; Manager at exact marker, CHASE same frame, no retry warning |
| Uncrossed player dies, escapes or leaves | Trigger on the remaining players |
| Lobby spectator or non-round joiner | Never blocks |
| Protected uncrossed player | Blocks barrier |
| All crossed and protected | Spawns at once, approaches, no kill until protection ends |
| Crossed, then walks back to mall | Still counted; Manager pursues |
| Revived before / beyond midpoint | Must cross / re-latches by position |
| Participant at the marker | Per your decision; never an alternate point |
| Paused at trigger or mid-windup | No movement or kill; CHASE on resume |
| Discs completed before song timeline arms | Phase reaches DONE; finale can trigger (Music L214–217) |
| Final disc inserted mid-hunt | Old Manager removed; finale spawns fresh at marker |
| Forced stuck and recovery | No hard snap after spawn; step ≤ speed × dt |
| Round end or reset | Manager gone, attributes cleared |

| Scanner case | Expected |
|---|---|
| Last world disc picked up, none inserted | CD player mode, exact bearing and distance |
| Carrier drops, dies or disconnects | Disc mode on next tick, though collected count equals goal |
| WORLD disc without position; empty state; missing goal | Not CD player mode |
| All inserted | Exit mode |
| Target at 0°, ±90°, 180°; camera vertical | Correct bearing; no flip or centre sweep at 180° |
| Target behind camera | Edge pointer on correct side, no mirrored marker |
| Spectating; subject dies or escapes | Uses subject's position; no stale pointer |
| Panel hidden, toast, modal, dispatch, hiding | Panel and pointer both hidden |
| Touch, rotation, notch | Pointer inside safe area, clear of controls, taps pass through |
| Reset; script or gui destroyed | Position nil in both places; nothing left on screen |
