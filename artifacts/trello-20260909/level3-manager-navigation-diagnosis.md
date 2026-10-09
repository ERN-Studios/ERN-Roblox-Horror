# Level 3 square: physical waypoint regression

10 September 2026. Manager/Suite patch prepared locally; native retest and final critic acceptance remain with root. No Studio actions by this agent.

## Observed failure

Normal round seed **143259491**, hash **L3-2-0fbba959**, 100 HP/ready controls, normal Music→Adapter hunt. `level3-square-native-chase-full.json` contains 190 actual samples over 12 seconds: 198.62 studs travelled,191 early progress events, then a trailing 8.62 second genuine-progress plateau,10 stuck recoveries,0 full recovery repaths. The former chase probe incorrectly passed because it required only one event somewhere in the interval and no physical standstill.

The enriched final trace puts Manager at `[6602.83251953125,28.1000576019,626.80413818]` (volume fits) and its waypoint at `[6598.8447265625,24,627.37670898]` (does not fit: 2 physical blockers, 0 furniture). This is SignalHall's **north doorway**, not a district gateway. Captured layout places SignalHall centre at world X6604.5 / local Z654, depth 56, so its north face is Z626. The 14 stud doorway and unchanged 5.25 physical half-sweep allow roughly 1.75 stud centre offset; raw PFS offset is 5.66 studs.

## Minimal correction

The existing centreline projection recognized the corridor but refused its clear centre because its raw→centre sweep starts inside a wall. `movementProjectedWaypoint` now distinguishes an invalid raw endpoint from a valid raw point:

- Invalid raw: only its existing authored-corridor centre can replace it, and only after the actual Manager→centre full-volume sweep succeeds. Otherwise return nil.
- Valid raw: preserve existing lateral-hop and actual-approach checks, including retaining a valid original detour point when centering is obstructed.
- Adoption, consumption, lookahead and route certification share this helper. No unsafe `initialIndex or nearestIndex` fallback remains. A rejected active point can only be skipped to a later candidate with a clear actual approach; otherwise the path is cleared and a bounded replan is requested.
- PFS installation no longer clears PathFailures. Actual credited progress and existing recovery/arrival resets remain; repeated coarse Success cannot erase a genuine stuck sequence before escalation.
- `ValidateChaseProgressSeries` measures all serial plateaus including the final one. Live fixed-target chase permits at most max(2, 2×StuckSeconds+.25) seconds. Direct target distance need not decrease during a legitimate detour.

No collision radius, movement speed, geometry, target-selection, attack, teleport or publishing change was made here.

## Local checks

- `test_level3_physical_waypoint.py`: 70 actual-source checks pass using the captured layout/coordinates and conservative 5.25 inflated physical slab fixtures. Includes 20 repeated route adoptions, corrected-point consumption, a solid doorway with no legal repair, preserved valid-original centering fallback, a 14 stud 90° turn, and a long detour with a 4 stud initial PFS point.
- Same regression using byte-exact before-Manager fails at the blocked raw-point repair assertion.
- Replays the actual native 190-sample serial trace unchanged and rejects its 8.62 second plateau. Positive steady-progress and short-recovery samples pass; a late event cannot erase an earlier long plateau.
- Existing `tools/tests/test_level3_steering.py`: 222/222 pass.
- Actual installation/progress source checks preserve stuck failures on coarse route installation and reset them only on credited progress.
- Both edited runtime modules compile with official Luau 0.737.

The slab fixtures do not replace native Roblox navigation. Before snapshots and scoped diffs: `level3-waypoint-manager-before.lua`, `level3-waypoint-suite-before.lua`, `level3-waypoint-manager.diff`, `level3-waypoint-suite.diff`. Local output: `level3-waypoint-local-tests.txt`.

## Native acceptance owned by root

1. In the same generated world with Manager alive, run the read-only production helper below. Expected: original invalid, accepted centre X6604.5, accepted endpoint and actual approach clear. The production helper cannot bypass a solid door.

```lua
local systems=game.ServerScriptService["Level 3 Systems"]
local Manager=require(systems["Level 3 Mall Manager AI Controller"])
local p=Manager.DebugMovementProjection(
    Vector3.new(6602.83251953125,24,626.80413818),
    Vector3.new(6598.8447265625,24,627.37670898))
assert(p.OriginalEndpointFits==false)
assert(p.Accepted and math.abs(p.Accepted.X-6604.5)<.01)
assert(p.AcceptedEndpointFits and p.ApproachSegmentClear)
```

2. Run existing `Suite.ProbeBlockedProjection(Manager)` to retain the valid-original projection/approach negative contracts.
3. Resume the actual normal-round chase and capture XYZ/room positions across SignalHall's north doorway into the next routed room. Require sustained route progress over multiple intervals and actual doorway passage, not only a new path ID. Re-run `Suite.ProbeChaseForwardProgress(Manager,player,12)` with the new trailing-plateau assertion and inspect its full telemetry.
4. Complete square-layout native acceptance across both district gateways/right-angle turns, five CDs, final-hall run-in/once-only completion and cleanup using the existing `level3-square-runtime-acceptance.md` commands. Local path tests alone do not certify the entire layout.

Final feature approval and publication remain pending these native results and the independent critic score ≥8.

Independent critic reviewed the complete patch and independently ran all 70 focused checks, 222 steering checks and both full-module compiles: **9/10 for code and offline validation**, no blocker before native retest. Full feature acceptance still requires actual passage and sustained pursuit in Studio.

## Native retest: unresolved second coarse-route failure

The exact original invalid-raw repair passed natively. A separate normal hunt travelled about 350 studs with a 0.35-second maximum progress plateau and no stuck recoveries (`level3-waypoint-native-first.json`). Full feature acceptance nevertheless FAILED a staged SignalHall pursuit: the new test correctly rejected about 11 seconds of standstill. Current critic acceptance is 6/10 pending a real passage fix.

The root-owned Play-only instrumented trace (`level3-waypoint-native-door-instrumented.json`, 231,535 characters) proves that the strategic first target is the WEST room L3_S3_R07 at `[6506.06885,24,652.95892]`, not the north corridor. Manager eventually stays at `[6604.39355,24,627.80151]` in the north doorway, with a free current volume, no active avoidance commitment, 51 coarse path installations and 13 stuck recoveries. Every rejected candidate from raw waypoint 3 `[6596.416,24,628.406]` through waypoint 9 `[6572.4834,24,630.221]` lies outside the corridor's projection range and inside the north wall's full-body clearance. None has a valid authored-centre repair. The actual west strategic endpoint fits, but its approach is blocked.

Returning to the stale displayed waypoint is clear, but that attribute is not the actual fallback destination after clearPath. Subsequent native PFS comparisons at radii 4, 5.25 and 6 all returned almost the same invalid route; radius changes do not solve this reproduction.

## Furniture barrier and bounded placement correction

The actual SignalHall navigation exclusions form a continuous barrier, despite the north start and west goal both fitting individually. Root's production-volume lattice found 763 reachable positions but could not reach the valid west goal. Independent rotated-rectangle SAT analysis proves a connected exclusion chain from the west north jamb, through all three table groups, to the south/east wall. This is an authored placement obstruction, not grounds for weakening the Manager's physical volume or adding a general pathfinding fallback. SparseWelcome has a separately proven west-jamb barrier; KidsCluster and BanquetRows also failed source-derived screening on the same seed.

`room-furniture-prepared/` contains the bounded World Builder correction and its exact baseline. The shared table-placement loop minimally clamps complete groups to reserve one stud of continuous centre perimeter around the FULL existing nav exclusions. If the clamped physical table/chair groups overlap, a fixed pair/triangle arrangement separates them. All authored rotations, table/chair counts, dimensions and hide/CD offsets remain intact. Spacious legacy layouts are unchanged.

The actual-source emission harness passes 118,782 checks across 4,538 layouts, with minimum physical group separation 0.828475978 stud and minimum full-exclusion perimeter lane 1.0 stud. All four perimeter edges and all four door spokes pass continuous segment/exclusion checks. This is offline geometry evidence only. Independent review, a fresh native world build, actual blocked-room passage, the other flagged ports and sustained Manager chase remain required before feature acceptance or publication.
