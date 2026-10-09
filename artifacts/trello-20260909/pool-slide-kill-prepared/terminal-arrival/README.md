# Pool Slide: finish the certified final approach

Prepared only. The runtime mirror was not changed by this agent. The parent owns installation, native testing and publication.

The normal corner run on seed **188232071** exposed a distinct failure after the 10.5-stud melee correction. The final recorded waypoint at index 4 of 4 was `(656.8135376, -1.1199995, 899.9632568)`, **9.999994 XZ studs** from the stationary living player. The follower consumed it while the foot was still **1.350188 studs** away, because every waypoint shared a 1.4 arrival tolerance. The resulting player distance was **11.165027**, followed by 17.96469 seconds of `ARRIVED`, HP 100, attack serial 0 and clear LOS. The planned dodge never triggered. See `../native-seed188232071-corner{,-compact}.json` and the independent corner review.

This two-file delta adds an optional `GoalArrivalDistance`, inherited exactly from each caller's existing `WaypointArrivalDistance` when unspecified. The constructor bounds it to .05 through the existing intermediate tolerance. Pool Slide opts into **.2**. The final waypoint pop, `_reachedGoal` and the nonstable no-waypoint arrival branch use this value consistently. Intermediate waypoints, the 1.4 comparison between the current and installed goal, vertical gates and waiting-for-clearance retain their existing behavior.

The entire movement body is unchanged: `travel=min(distance,speed*dt)`, .6-stud maximum substeps, `_placeFoot`, floor resolution, body-box clearance, swept clearance, recovery and route ownership. The recorded final point plus .2 bounds this particular end position to **10.199994**, inside the unchanged 10.5 attack range. This is a correction to the actual early stop, not a claim that every blocked goal is reachable or attackable.

The unchanged 10.5 range retains the prior calibration margin; its earlier comment about 1.4 describes how that range was selected. The new final-arrival override is explicitly documented next to the tuning. No damage, windup, cooldown, arc, LOS, Shield, Pool Foam or rig values change.

## Exact handoff

| Script | Required runtime raw SHA256 | Proposal SHA256 |
|---|---|---|
| Level 2 Pool Slide Navigator | `4b23468e356ef93d7d7ddb094c6f2ead305a199e832a51b095c59e1aec5617cc` | `24507756188f5bd0bf80a94570222b3b77542d1ed44831223d4a88c819e26bd8` |
| Level 2 Pool Slide Controller | `9f8b259843309d3935644737a462152c1fca54707ac035dff8a4f93b86b01d60` | `a9c53bf7c95e7d81b08998c0fcfdfe41c9722801712ca30d5c92ea47c91debd0` |

Both files retain their normal `ServerScriptService/Level 2 Systems/...ModuleScript.lua` paths beneath `proposed/`. `manifest.json` records the exact input and output hashes. Inverting only the listed source deltas restores both baselines byte-for-byte after line-ending normalization.

## Validation

`test_terminal.py` passes **61** focused actual-source checks, **219** existing combat/Shield regression checks, **five** precise negative controls and **four** whole-source compiles. The focused host runs the complete actual `Step`, `_placeFoot`, `_clearAdvance`, `_reachedGoal`, numeric sanitizer and new constructor assignment. Engine floor/box/sweep operations and the model are controlled fixtures; the test does not claim engine physics or fresh pathfinding.

The recorded stopped foot must advance through the unchanged placement gates, reach melee range and finish at the tighter terminal tolerance. Four frame cadences (.016/.05/.1/.25) remain within the .6 step bound. Separate failed floor, failed full-body box and failed sweep cases cannot move or falsely arrive. Additional cases preserve intermediate consumption, absent-tuning legacy behavior, valid small goal drift, rejected stale/vertical targets, direct standable goals, waiting-for-clearance and retired models. The negatives separately restore early terminal popping, early `_reachedGoal`, tighten all intermediate points, tighten goal identity, and remove the body sweep; each fails its intended assertion.

The prior combat host is reused without changing its original artifacts or validation. It runs the proposed Controller with the new `_reachedGoal` and retains all 219 range/LOS/arc/damage, one-hit, stale-character, pause/cleanup and Shield checks. Runtime SHA guards passed before and after this run.

## Native acceptance still required

Use the existing normal queue and a disclosed pinned seed **188232071** for a repeatable corner comparison. Stage only the actual player before spawn at the same corner. Do not move the entity or remove collision, ForceField or Entity Shield protection. Save the same observers and capture actual terminal movement beyond the failed foot, first attack and the HP transition. A positive damage result also needs the existing maximum-range visual-contact assessment; the sidewall approach screenshot alone is insufficient. The ordinary open-floor, dodge/LOS, protection and normal round cleanup checks remain as scoped in `../native-acceptance-plan.md`.

This artifact does not alter the sidecar's reported `ExpectedControllerSHA256`; before a new observer installation the parent should keep that provenance value aligned with the installed Controller. It is a declared expected hash, not an independent runtime-source measurement.
