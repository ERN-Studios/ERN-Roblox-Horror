# Level 3 square layout — implementation validation

Prepared 10 September 2026 for [k6e4BnS1](https://trello.com/c/k6e4BnS1). **Final status: published v1831, Done, independent whole-feature score 9/10.** Earlier sections preserve the chronological preparation and failed native attempts; the final delivery entry below supersedes their then-current pending/blocker status.

## Result and exact scope

The three existing 2x4 districts now occupy four shared columns and six rows. Rooms retain seeded widths/depths and their local IDs/themes/decor contracts. The two district gateways run South from row 2 to North on row 1 in a shared column. Arrival stays west of district 1; SignalHall remains the rightmost column of district 3, and its hidden final route remains exactly 560 studs along +X to Exit. No authored arrival/exit set, AI, objective, flashlight, music or hiding script was changed.

Three runtime files changed, with byte-exact source baselines under `level3-square-before/`:

- Configuration: `Layout.GeneratorVersion` 1 to 2.
- Layout Generator: two-phase placement, incoming-room DFS roots, initial CD separation, GatewayColumns metadata, measured full/core/district bounds, versioned hash with fractional coordinate precision, and cardinal/metadata/corridor-shell validation.
- Test Suite: existing generated-layout/navigation functions accept optional seed lists; standard aspect enforcement is explicit. Reports include maximum full/core aspect, attempts and fallback count. Normal generation does not impose the standard aspect target on arbitrary Master size overrides.

The exact patch is `level3-square-layout.diff`. The first frozen delta was Configuration +1/-1, Generator +153/-53, Test Suite +34/-8; the later targeted existing-arrival-sign test correction is recorded below and included in the current diff. Shared envelope maxima preserve minimum horizontal spacing; narrower district rooms can have physical gaps greater than the original maximum sampled 34-stud gap. Counts remain 26 rooms, 31 links/six cycles at standard tuning, three districts, 24 hiding tables and five CDs with at least one per district. Part counts are expected to remain stable because topology and builder calls are unchanged; native build cost is still to be measured.

The first-per-district CD choice now excludes candidates less than 105 studs from already chosen CDs. This closes a real weakness exposed by stacking: the old first three selections ignored separation, while only the last two enforced it.

The validator checks the actual corridor kit's conservative 17-stud outer shell width (14 clear + two 1.5 walls), its 0.04 floor seal and foreign room shells expanded by half a wall thickness. Endpoint rooms are exempted from their own joins; corridor-pair overlap outside rooms is rejected. Layout/district bounds and gateway diagnostics must match the emitted plan. The hidden link's edge length must equal the currently resolved tuning.

## Offline evidence

Run:

```powershell
$env:LUAU_BIN='C:\Users\mikke\AppData\Local\Temp\codex-luau-0.737\luau.exe'
python tools/tests/test_level3_square_layout.py
```

**9,976 checks passed**, using the real Configuration, full Generator/Validate and actual generated-layout/navigation Test Suite functions. The host substitutes constructors, a read-only Master overlay and a deterministic **Park-Miller test PRNG**. It is explicitly **not Roblox Random** and does not certify the native seed results.

- All 104 unchanged baseline layouts fail both new aspect targets in the same host.
- 232 revised seeds preserve unique deterministic hashes, all standard counts, cardinal bridges, the east-facing 560-stud finale, shared column centres and all ten CD pair distances. Hashes include the seed, so hash uniqueness alone is not proof of 232 different coordinate/link plans.
- All 232 generate on attempt 1 with no fallback. The existing structural/navigation suite also passes the named 104 acceptance seeds.
- Seven override sets across four seeds each validate (28 cases): standard size extremes, zero/three extra links, final lengths 120/720 and larger room/row/CD spacing. Geometry validation remains active under overrides.
- Removing only the new initial-CD filter in memory causes **22 of the 104 seeds** to retry. The completed implementation requires no such retries in this host.
- Negative fixtures reject stale/NaN bounds, wrong gateway column/theme/reference, altered final length, duplicate side ports, CD separation below 105, a foreign room intersecting only the outer shell, and crossing unrelated corridors. Positive endpoint joins and separated shells remain accepted.

| Revised offline metric | Minimum | Median | Maximum |
|---|---:|---:|---:|
| Full width | 1,081 | 1,114 | 1,139 |
| Depth | 786.5 | 805 | 824 |
| Full aspect | 1.334550 | 1.381988 | 1.424031 |
| Core width | 469 | 498 | 521 |
| Core aspect | 1.546512 | 1.618902 | 1.716075 |

The raw records are `level3-square-offline.json`. Aspect always means longer dimension / shorter dimension. Core excludes Exit but includes Arrival. These room-plan figures exclude the long arrival slide and decorative extents.

All three complete runtime files compile with Luau 0.737 (5 KLOC/209 KB bytecode); adding the standalone native probe produces 211 KB. Whitespace checks are clean apart from Git's existing LF-to-CRLF notices. Repository search found no remaining runtime GatewayRows or version-1 assumptions outside the preserved historical artifacts.

## Native acceptance handoff

`level3-square-native-probe.luau` runs the same 104 named seeds through the actual Roblox generator, existing structural suite with explicit aspect acceptance, and navigation suite. It returns per-seed full/core bounds, hash, attempts/fallback, gateway columns and minimum CD distance. Root must use the synced three-file version and report the resolved Master tuning. The probe generates plans only; it does not build or traverse a world.

Then root must build and inspect 101/7331 and the native aspect extrema, measure the complete rendered footprint including the arrival slide, and exercise both gateways in both directions, all CD/hiding access and actual Manager pursuit across districts/turns. Preserve the slide aperture/NO EXIT sign, locked exit, five-CD reveal, 40% spawn/50% halfway final chase, automatic one-shot run-in escape, safe-room flow, teardown and fresh lobby start. Compare native build duration/count and pursuit behavior. No geometry/fixture-only check is evidence of successful physical traversal.

The optional seed list in `ValidateGeneratedLayouts` is for a suite of at least four distinct layouts; its existing diversity assertion deliberately rejects one-to-three-seed calls. Use `Generate`/`Validate` directly for an individual seed.

## Native plan evidence and independent review

Root ran the exact new Configuration and Generator in a **Play-only shadow folder**, with only the Test Suite's HidingController import redirected to the unchanged original. Actual Roblox Random passed all 104 seeds and all 104 navigation checks: 26 rooms, 31 links/six cycles, five CDs, maximum full aspect **1.421152628**, maximum core aspect **1.711134454**, minimum CD separation **105**, every attempt 1 and no fallback. The 104 distinct reported hashes include seed identity. The raw evidence and exact staging method are in `level3-square-native-shadow.json`.

This native evidence evaluates plans only: no revised production world was built by that probe, and no physical traversal or complete rendered-footprint acceptance is implied. Root still owns the production push and world/flow checks listed above.

Root subsequently built seed 101 using a Play-only shadow of the current World Builder with the new Configuration/Generator/Test Suite: 0.4069 seconds, 3,638 instances. Its complete rendered bounding box including the arrival slide measured 1,328.1797 by 806, aspect **1.647866**. This is separately reported from the <=1.5 room-plan target. It was a shadow-world build, not normal lobby-flow acceptance.

That build exposed a stale Test Suite restriction: ValidateWorld rejected the already published v1820 arrival sign. The authorized correction allows only the exact `Arrival Only Notice` instance under the verified slide's direct `Arrival Only Sign`, and its exact `NoExit="NO EXIT"` / `ArrivalOnly="ONE-WAY ARRIVAL"` TextLabels. It also checks Front orientation and depth-tested rendering. Other signs, duplicated names, extra labels and text inputs remain forbidden. No sign geometry or text was changed. `test_level3_arrival_allowlist.py` executes the actual old/new allowlist and exact sign checks: **19 checks pass**, including baseline rejection of the authored sign and preservation of existing CD/drawing/CRT exceptions. The complete Test Suite compiles after this adjustment.

The critic independently read the frozen delta, reran all **9,976 checks** and compiled **3/3** whole files. No code blocker; preliminary code/layout score **8.5/10**, with final score awaiting native world/flow evidence. No Studio push, UI action, paid action, live data change or publication was performed by this agent.

Root's further shadow-world checks built seeds101/7331/4817535 (last is the104-seed plan-aspect maximum). All three pass the exact revised ValidateWorld after the harness correctly performs compatibility-marker cleanup between direct Builder calls. Complete rendered aspects including arrival slide:1.647866/1.679678/1.714513; instances3638/3717/3668; build durations0.405/0.413/0.410s. The first direct-builder loop omitted RoundAdapter's marker cleanup and therefore correctly failed duplicate-marker validation; that harness error is preserved in the first report and is not a source defect.

All180 actual collidable blockcasts through the30 open corridors, both directions across all three worlds, pass (3.5×5×3.5 player body, centre3.5stud over floor). The hidden exit was intentionally excluded while locked. Separately, the actual client Humanoid physically traversed both district gateways in both directions for seed101:4/4,100HP,52stud paths,3.16s each,remaining distance1.42–1.49stud at the chosen1.5stud arrival threshold. Default PlayerModule inputs were temporarily disabled to allow Humanoid MoveTo, then restored with original character position. This is physical traversal, not human input or full gameplay.

Actual old production generator seed101 gives a full rendered aspect8.600327 (2094.1797×243.5) versus new1.647866 (1328.1797×806), with identical3638instances and comparable0.403→0.405s build duration. One timing sample is not a performance benchmark. Evidence: level3-square-native-before.json, level3-square-native-three-worlds.json, level3-square-native-three-worlds-corrected.json, level3-square-native-gateway-physics.json.

## Normal round evidence and remaining navigation blocker

Normal lobby launches now cover an unpinned seed143259491 (hash L3-2-0fbba959), its reproducible pinned repeat, and seed101. The actual GameManager/Adapter path reaches ready, InRound, 100HP and released movement. World validation and Runtime(0) pass. Four inserted CDs keep the exit locked; all five unlock it through the ordinary Objective handlers. One Runtime(4) check ran before the final disc's .32-second hide tween settled and failed correctly; the settled repeat passes. The collection fixtures reposition the tester at actual prompts and call the supported handlers, which still validate distance and line of sight; they are not keyboard/touch prompt evidence.

At 49% of the 560-stud final hall there is no final chase; at51% exactly one Manager appears at the authored40% spawn, with unchanged model/SpawnSerial on repeated evaluation. A separate isolated detector test pauses the Manager through its existing Studio hook and physically moves the client Humanoid about18studs into the unlocked detector: Escaped=true,100HP and exactly one RoundStatus escape event after1.412seconds, followed by normal win-to-lobby cleanup. All four original scripts restore, world and Manager disappear, InRound/RoundActive=false, SelectedLevel=1 and the fresh character is unanchored with100HP. These results do not certify a multiplayer quorum or a player outrunning the Manager. See native-normal-initial, four-cds, finalhall, exit-fixture, run-in-exit and win-cleanup JSON files with the level3-square prefix.

The first chase exposed a physically invalid coarse-PFS waypoint near SignalHall. The old probe incorrectly accepted8.62seconds of circling because it counted total movement and an earlier progress event. The revised Suite now rejects every long progress plateau, including a trailing one. The Manager repair accepts an authored corridor centre only after a full actual-position approach succeeds and rejects unrepairable raw points; PFS Success alone no longer resets real stuck escalation. Seventy actual-source checks and222existing steering checks pass; both complete modules compile. The two sources were pushed separately to Edit with backup .studio-push-backups/20260910-000259, but are **not published**.

The revised normal hunt's first12-second native chase passes191samples/350.786studs/671progress events/0stuck, longest progress plateau.350889seconds and at most2path computations per second/1concurrent. The independent critic mapped its actual positions to both90-degree junctions in L3_S1_R05/R06 and the first district gateway into L3_S2_R02. See level3-waypoint-native-first.json and the independent level3-waypoint-native-review.md.

However, a validated starting fixture in SignalHall at[6604.5,24,642] still stalls during pursuit. The latest **delivery score is6/10**, below acceptance; earlier9/10 concerned code/offline preparation only. A temporary, Play-only diagnostic copy of Manager shows its actual next strategic room is the western L3_S3_R07, not the north doorway. Coarse PFS hugs SignalHall's north and west walls and emits physically invalid points outside the corridor's centre-projection region. Both radius4 and5.25 return similar Success paths with invalid points, so increasing to5.25 does not solve this case. The authoritative5.25 physical sweep remains unchanged. Last published WaypointTarget is stale after clearPath and must not be treated as the active destination. Full instrumented report: level3-waypoint-native-door-instrumented.json; exact planner comparison: level3-waypoint-native-pfs-radius-comparison.json. The instrumentation exists only in Play and must disappear on Stop; it is not a release-source change.

Remaining acceptance: repair and demonstrate actual sustained passage from this failing room route plus the second district gateway, obtain final independent score≥8, stop Play, compile/audit the final Edit sources, and publish with the mouse. Existing completed geometry, CD, exit and cleanup evidence is reusable unless the final correction changes those contracts. Mesh/Image APIs remain OFF and no new place version has been published since v1825.

## Compact-room furniture correction and current native result

The smaller SignalHall had an actual continuous furniture barrier, independently confirmed by rotated exclusion overlap and native clearance queries. Additional narrow-room archetypes also blocked ports. The shared Builder fit keeps every complete table/chair group, yaw, size, hide/CD anchor and navigation padding, reserving a one-stud perimeter against the full inflated navigation boxes. The independent preparation review scored 9/10 after 118,782 emitted-geometry checks over 4,538 layouts and full compilation. See room-furniture-prepared/README.md.

Studio lost its live editing connection (RCC-288); root reconnected with the visible Reconnect button. The reviewed Builder (104,414 bytes) was pushed after baseline verification; backup .studio-push-backups/20260910-004933. The complete source audit found 122 matched and zero drift, confirming that the other upublished edits survived the reconnect.

A fresh normal lobby launch of seed143259491 reached ready/InRound/RoundActive with 100HP and passed ValidateWorld. All three exact full-volume segments now pass with both endpoints fitting: (6604.5,24,632.1)→(6574.1,24,632.1)→(6574.1,24,654)→(6560,24,654). The formerly blocked north-to-west perimeter is therefore physically clear.

The actual 18-second chase still fails: it stops near (6604.207,28.100,630.481), with 17.10 seconds motionless, 20 stuck recoveries and path serial78. This is a remaining coarse-route/steering failure despite corrected furniture, not successful native acceptance. Full evidence is level3-furniture-native-door-failed.json and its compact companion. The delivery remains below the required score. Play was stopped and temporary segment diagnostics were removed automatically; no publish occurred. A bounded authored room-perimeter repair is being prepared while retaining all full-volume collision checks.

A subsequent fresh normal round ran the actual shared Manager volume queries on 96 perimeter segments and 59 open-door spokes: 137/155 pass. All previously furniture-blocked named ports pass, but the room-wide perimeter is not universally free: the four existing structural-column rooms (S1R04, S2R05, S2R06, S3R04) block their four corner segments; S1R04 also blocks the tested south spoke; the SignalHall east side is blocked by the existing CD player's AV Cart Television Shelf. Direct diagnostic probes report physical blockers, zero furniture exclusions, at the sampled failed corners. The confirmed north-to-west SignalHall route remains clear. See level3-furniture-native-ring-port.json.

These findings limit the geometry claim to the moved table/chair groups. They do not by themselves show a disconnected open doorway or failure of the ordinary interior PFS route. The bounded room-perimeter fallback must refuse obstructed candidates, preserve valid PFS routes, and be judged by actual traversal. No column or CD player was removed or made non-collidable. Play was stopped after this diagnostic pass.


## Final delivery — published v1831, 10 September 2026

The later independent review isolated the H11 ceiling-beam overlap and the S2_R05 column-room continuation. The final Builder retains beam ceiling attachment while giving full Manager height clearance. The final Manager preserves the original checked outer route and tries one inner rectangle only when needed, with unchanged body/furniture checks and asynchronous replacement fences. Both concrete failures have passed native retesting; the historical failed traces above remain part of this journal.

Final native chases passed26.240s/805.257stud and13.516s/417.725stud, with623 asserted CHASE samples, no stuck/frozen interval, both district gateways and the previously failed S2_R05→S2_R06 turn. Maximum PFS rate2/second and1 concurrent; all24 hide anchors and5 actual CD pickups pass at the final moved locations. The existing locked/unlocked exit, final-hall trigger, single physical run-in escape and normal cleanup evidence remains applicable. See `level3-final-native-acceptance.md` and `level3-final-independent-review.md` for full provenance and controlled-fixture limitations.

After Stop Play, all122 Edit scripts compiled and the source audit matched122/122 with zero drift. The independent critic gave the complete feature **9/10**, with no remaining blocker within this scope.

Root published with the mouse through File→Publish to Roblox. The observed Studio Output on10 September2026 records **03:42:04.490: Add publish notes to v1831** and **03:42:04.562: Published new changes** (Europe/Copenhagen). The actual released version is **v1831**, not the earlier expected v1826. Screenshot: `level3-published-v1831.jpg`.

Root updated the original Trello description, moved the card to Done and marked it complete. Independent Trello readback confirmed the card's list **Done**, `complete=true`, and its v1831/9/10 delivery description; last activity2026-09-10T01:42:46.207Z. No Trello write was performed by the critic during this bookkeeping step. The feature is complete; other Trello tasks retain their own acceptance requirements.
