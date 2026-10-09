# Independent native navigation review

Reviewed 10 September 2026 by the independent critic. Current Manager delivery score: **6/10 — not ready to publish**, because the exact SignalHall doorway retest remains blocked. Earlier **9/10** assessed the scoped code and offline checks only, before this native failure was discovered.

## Evidence that already passes

The critic independently read `level3-waypoint-native-first.json` and mapped its 191 production `Series` positions to the room rectangles and links in `level3-square-native-issue-layout.json` (seed 143259491, layout hash L3-2-0fbba959). All listed samples retain **Generation 1 / SpawnSerial 1**. The trace reports 350.7864 studs travelled in 12 seconds, 671 genuine progress events, 11 route advances, zero stuck recoveries, maximum genuine-progress plateau 0.350889 seconds, at most two path computations per second, and one concurrent computation.

| Trace time (seconds) | Actual world X / Z | Mapped passage |
|---|---|---|
| 2.717718 | 6304.470215 / 57.690880 | Enters L3_S1_R05 through its north doorway. |
| 4.467982 | 6336.501953 / 88.570946 | Leaves L3_S1_R05 through its east doorway: first 90-degree room turn. |
| 5.650269 | 6372.909668 / 89.961220 | Enters L3_S1_R06 through its west doorway. |
| 7.518030 | 6401.552734 / 122.831367 | Leaves L3_S1_R06 through its south doorway: second 90-degree room turn. |
| 8.783703 | 6402.411133 / 162.331848 | Enters L3_S2_R02 after traversing District gateway Level3_Link_29. |
| 10.616451 | 6402.629883 / 219.536697 | Leaves that room through its south doorway and continues along the route. |

These are continuous measured Manager positions crossing authored room boundaries, not inferences from yaw, a new path ID, or a single clear-volume query. This trace already supplies two turns and one direction across the first district connector. The earlier `level3-square-native-gateway-physics.json` separately records four actual client Humanoid traversals, both directions across both district connectors, with 100 HP and restoration; it is player traversal evidence, not Manager pursuit evidence.

## Remaining native blocker

`level3-waypoint-native-door-failed.json` and its compact companion record a separate exact-door fixture. The existing production-validated staging API accepted the clear 25-stud segment from ground (6604.5, 24, 642) toward (6604.5, 24, 617). The subsequent ordinary chase failed the new suite assertion: approximately **11.02 seconds motionless**, with 13 stuck recoveries.

The failure trace shows the following sequence:

- At 0.433039 seconds, the Manager is at X 6604.378906 / Z 633.877747 and follows the centered waypoint at Z 631.579956.
- At 0.648860 seconds, a replacement route has PathSwapSerial 3, 34 waypoints, and index 2; its published centered waypoint is (6604.5, 24, 630.848572).
- At 0.865347 seconds, the route has been cleared to zero waypoints; the Manager has moved southwest to X 6602.125977 / Z 632.306213.
- By 1.066139 seconds it reaches X 6597.161133 / Z 633.402954, then remains there throughout the stalled interval.

The published `WaypointTarget` remains after `clearPath`; consequently its later `VolumeFits=true` result is a **stale diagnostic**, not proof that the current fallback movement target is reachable. Source inspection identifies the short direct step toward the strategic destination as one possible source of drift after route rejection. Committed local avoidance is another possible contributor. Neither is yet proven as the root cause: inspect actual strategic destination, raw PFS points, projection rejection reasons and avoidance state at the first rejection before selecting a further correction.

The required remaining navigation acceptance is physical passage through this exact SignalHall north doorway and Manager passage across the second district connector, Level3_Link_30. Use unchanged generation/spawn through each trace, genuine sustained progress and normal movement/path-rate limits. The first trace can be reused for its already demonstrated gateway and two turns; repeat it only if a later change materially invalidates that evidence.

## Existing flow checks to retain

The final waypoint patch changes navigation and its tests; it does not change objective or escape handling. The following existing native artifacts therefore remain applicable unless a subsequent change affects those paths:

- `level3-square-native-exit-fixture.json`: five real CD records collected and inserted through existing server handlers, ExitUnlocked=true, and final-hall chase triggered; 100 HP. This is handler/position-fixture evidence, not proof of five physical keyboard/touch prompt activations. The Manager was paused for the final exit fixture.
- `level3-square-native-run-in-exit.json`: actual run-in escape, one observed escape event, Escaped=true and 100 HP. No exit button or synthetic escape event was used.
- `level3-square-native-win-cleanup.json`: normal win return with RoundActive=false, InRound=false, SelectedLevel=1, unanchored root and 100 HP; four original scripts restored.
- `level3-square-native-normal-cleanup.json`: world removed, normal round inactive, SelectedLevel=1 and four scripts restored.

No runtime source, Studio instance or published place was changed by this review. A new native failure overrides a prior conditional code score; the current complete delivery must be reassessed after its concrete blocker is fixed.

## Instrumented reproduction: confirmed route rejection

The later `level3-waypoint-native-door-instrumented.json` reproduces a sustained stop at X 6604.393555 / Z 627.801514. At 0.866 seconds the actual movement target is absent, status is `PHYSICAL_WAYPOINT_REJECTED`, and the last rejection shows raw waypoints 3–9 with `RawFits=false`, `CenterFits=false` and `ApproachClear=false`. For these candidates the unchecked center equals the raw point, so the first patch cannot repair them. The strategic destination lies west in L3_S3_R07 at approximately (6506.17, 24, 653.51). `AvoidanceSign=0` throughout this first rejection; committed local avoidance therefore does not explain this reproduction.

The native radius comparisons also rule out simply increasing the pathfinder radius as a sufficient correction. Radius 4 leaves points 3–26 without an accepted physical candidate; radii 5.25 and 6 leave points 3–27 without one. All three pathfinder queries still report Success. Any further correction must obtain a physically valid connected route, while preserving volume rejection for genuinely blocked passages. The current score remains **6/10** until an actual corrected chase traverses the failing doorway and the remaining second district connector.

## Confirmed GrandBanquet furniture barrier

Independent geometry analysis of `level3-signalhall-native-furniture-frames.json` confirms a layout obstruction in the 73-by-56-stud SignalHall. The exact native 2-degree, 90-degree and minus-3-degree rotations were retained. The Manager tests these already-inflated furniture boxes using local half-extents 11.6 by 11.4 after its 0.25-stud seam tolerance; adding another body radius to them would double-count clearance. For physical walls, the 1.5-stud wall thickness plus the 5.25-stud axis-aligned square sweep require the center to stay 6.0 studs inside the room edge, except through a door.

Separating-axis tests give the following positive overlap depths in studs:

| Connected obstacles | Minimum overlap over their separating axes |
|---|---:|
| Inflated west wall north of its doorway → first table envelope | 1.930730 |
| First table → middle table | 2.529691 |
| Middle table → last table | 3.140791 |
| Last table → inflated south wall | 0.631488 |
| Last table → inflated east wall | 2.120674 |

This connected chain crosses the usable room from the west wall above its west doorway to the south/east walls, separating the north doorway from the west doorway. Both door centers themselves are free. Independent 0.2- and 0.1-stud grid floods also find the west door unreachable from the north; these discretized checks support the continuous obstacle-chain evidence, rather than replacing it. Other physical decor was omitted, which can only enlarge the test's free space and cannot invalidate this obstruction.

The next correction should therefore reserve connected space around the GrandBanquet groups while keeping their table, chair, hiding and objective attachments together. It should not weaken the Manager's safety margins or add a general pathfinding system to solve an impossible furniture layout. Production traversal still needs native confirmation after the placement changes.


## Independent review: supplementary native ring/port sweep

Source: `level3-furniture-native-ring-port.json`, seed 143259491 / hash L3-2-0fbba959. The 155 queries comprise 96 perimeter edges in 24 ordinary rooms and 59 ordinary room-side doorway spokes. HiddenExit is excluded, consistently with the bounded helper's finale exclusion. 79/96 edges and 58/59 spokes pass.

Sixteen failed edges have blocked endpoints in the four structural-column rooms S1_R04, S2_R05, S2_R06 and S3_R04. This disproves a universal clear perimeter, but does not prove disconnected doors. Their tested doorway spokes are clear except S1_R04 south. S2_R05's district gateway30 is among the clear spokes; a real traversal still needs valid interior/PFS navigation because its ring corners are blocked. SignalHall's east edge is blocked by the AV cart, while its north/west edges and both normal doorway spokes remain clear. The helper must keep rejecting blocked candidates; no reduction of navigation padding is justified.

The single failed doorway spoke has a concrete structural-height explanation. S1_R04 is WhiteAtrium W64/D53/H11 and Module=false. `makeRoomStructure` emits a 1.5-high ceiling beam with underside at H-1.5=9.5 above the floor. Production AgentHeight10 yields a clearance box whose top is9.6, leaving a0.1 vertical overlap. The beam's half-width is .34*64=21.76; expanding by the unchanged5.25 sweep gives27.01. Side walls permit only32-.75-5.25=26 of center half-width. Therefore the beam spans the entire legal width for this Manager body, with1.01 extra on each side. The south beam is at world Z=-73.04 and its expanded Z interval[-78.84,-67.24] contains the native failed starting point [6604.5,24,-70].

This is a mathematical obstruction under the actual Builder/Manager constants, pending native blocker-name confirmation. It is stronger than the generic ring-corner failures: routing around the beam inside this room cannot solve the overlap. If the existing native diagnostic confirms the Ceiling Beam, a narrowly scoped structural-headroom correction is required. A new route algorithm or weakened body radius would not address its cause. No runtime or Studio change was made during this review.


## Native perimeter proposal: successful route prefix, failed S2_R05 continuation

`level3-perimeter-native-chase.json` records105 sampled snapshots across22.266s. The overall result is false: the Suite correctly rejects a3.85s motionless interval. The final WAITING snapshot at22.266s follows Suite cleanup; the last measured failing snapshot at22.049s is still CHASE. This is not an all-chase pass.

Position crossings below are linear interpolations between adjacent approximately .21s native trace samples, not separately observed event timestamps:

| Passage | Approx. time | Crossing X/Z |
|---|---:|---|
| SignalHall west exit |2.326s|6568.000 /652.940|
| S3_R07 east entry |3.464s|6532.500 /653.836|
| S3_R07 west exit |5.737s|6471.500 /652.559|
| S3_R06 east entry |6.796s|6438.500 /653.763|
| S3_R06 north exit (first subsequent right-angle room turn) |8.318s|6404.409 /626.000|
| S3_R02 south entry |12.261s|6403.099 /503.000|
| S3_R02 west exit (second turn) |14.089s|6367.500 /475.161|
| S3_R01 east entry |15.085s|6336.500 /474.201|
| S3_R01 north exit (third turn; gateway30) |16.567s|6305.819 /445.000|
| S2_R05 south entry (gateway30 fully crossed) |18.041s|6304.663 /399.000|

The sampled polyline totals554.084stud, with no individual sampled displacement over7.286stud. This trace itself does not expose Generation/SpawnSerial, so those values must come from the enclosing native session evidence if asserted. It does establish continuous physical positions through the originally failed SignalHall west passage, three subsequent right-angle transitions and the second district gateway.

The Manager then remains at [6304.526367,28.100058,393.556885], with genuine progress serial1074. Its progress counter does not credit repeated route replacements or the strategic rebuild: path serial rises while genuine progress stays fixed, and the watchdog rejects the plateau. The planar distance from this point to S2_R06's center [6403,369.5] is101.3695717; logged ProgressBest is101.3695679. This strongly identifies the next desired leg as S2_R05 south-entry to east-exit; exact private destination confirmation remains useful. The old visible waypoint [6304.5,24,392.5] is only1.057stud away and may persist after clearPath; its own validity cannot establish a usable onward route.

The S2_R05 south-east ring corner [6331.5,392.5] lies inside the southeast column expanded by5.25: column center [6327.28,388.38], half-width6.3. The ring helper therefore correctly refuses that corner. An interior route must be measured before changing navigation again. The next native acceptance can target this continuation and the separately confirmed S1_R04 low beam, while preserving the successful route-prefix evidence above. The code/artifact score remains9/10; whole-feature native acceptance remains below8 until the actual stalled continuation is fixed.
