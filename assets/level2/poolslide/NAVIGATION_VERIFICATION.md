# Pool Slide pathfinding verification — 2026-08-31

## Scope and cause

Published successfully as **version1699** at2026-08-31T19:55:03Z. Studio logged
PublishSuccessful, Place published and Published new changes for the target game.

Target: BACKROOMS: STAY QUIET [CO-OP HORROR], place131311258779917, universe10559217407.
Only the Pool Slide controller opts into the new stable-route policy. Its size,
speed, animations, third-pump trigger, attack reach and collision requirements
are unchanged. Other navigator users retain their timer-driven policy.

Three distinct issues reproduced:

1. The existing0.65-second timer replaced healthy routes for stationary targets.
   Async routes were generated from an earlier foot position and could send the
   moving giant back toward an old origin or graph hub.
2. Incomplete full-body routes could be installed. Some real solid corridor ribs
   have less clearance than the giant physically needs, producing repeated
   attempts and recovery movement.
3. Individually safe centring detours could combine into unnecessary internal
   walk-back loops, even without another path request.

## Corrections

- Retain healthy routes; replan for meaningful target movement, actual blockage,
  exhaustion, explicit recovery or an8-second expired request.
- Capture one request origin, discard incompatible stale results, and join the
  returned route to the live foot only through full floor/step/body checks.
- Reject aborted, unresolved, over-budget and otherwise uncertified replacements
  without throwing away useful incumbent movement.
- Remove redundant bends through bounded, full-body-certified shortcuts.
  Necessary wall detours are retained; no line-of-sight-only clipping shortcuts.
- Walk only a newly certified reachable prefix at an impassable passage, then
  report WAITING_FOR_CLEARANCE, **not goal arrival**.
- Probe the recorded obstructed edge every3seconds without movement or a full
  replan. Resume when it becomes passable or the target materially moves.
- The controller watchdog allows bounded async planning and legitimate waits.
- Fixed the Path.Blocked handler's lost second return value when checking the
  installed segment.

## Native regression results

The exact final source passed **76/76** cases in Studio's native Luau runtime:
43navigator checks and33controller checks. The fixtures use controlled service/
geometry seams but execute the production constructor, async lifecycle, route
installation and Step; they do not mutate the DataModel or enable runtime
LoadStringEnabled.

Coverage includes30/60FPS, delayed path calculation and centring,180-point stale
prefixes, wall-safe joins, internal loop removal, genuine U-turns, vertical goals,
invalid replacement retention, graph fallback, cleared-obstacle recovery, timeout/
Stop races, legacy policy, third-pump latching, pause/resume and attack gates.

Fixtures: tests/level2/poolslide/navigation-fixture.luau and controller-fixture.luau.

## Real generated geometry: reproduction

All measurements use the unchanged imported16-stud template and actual
PathfindingService, generated collision geometry, Heartbeat and production
Navigator. Each trial holds a fixed goal; path samples and intermediate failed
iterations are retained in navigation-trial-results.json.

Requested seed202 resolved to2199511. Original24-second trials:

| Route | Reversals | Backward travel | Outcome |
|---|---:|---:|---|
| node1 →2 | 10 | 100.86studs | no arrival |
| node30 →31 | 19 | 134.06studs | no arrival |
| node38 →41, added250ms delay | 3 | 22.14studs | no arrival |

The first strict-certification revision did not move because of genuine
insufficient passage clearance. It is recorded as an intermediate failure, not
a successful chase. Reachable-prefix handling then produced six trials with
zero reversals: three safe approaches to blocked passages and three reached
same-room goals. Only one full path request was made in each.

## Second-layout findings and final results

Requested and resolved seed101. Before internal route smoothing, the otherwise
reachable node30 →31 route arrived but travelled443.60studs with3reversals and
22.24backwardstuds. The final source travelled352.15studs, arrived1.86studs from
the target, and recorded **zero reversals and zero backward travel**. One request,
including an injected250ms centring delay.

The other final seed101 trials also used one request and had zero reversals:
node1 →2 safely waited at the low passage after51.08studs; same-hall40/50-stud
targets arrived within1.60/1.69studs. Maximum measured frame travel stayed below
2.401studs at speed24 with dt capped at0.1. See navigation-seed101-results.json.

The exact final source was then repeated on resolved2199511: all six trials had
zero reversals and zero backward travel. Three reached same-room goals (one at
the certified approach beside an unoccupiable goal); three safely waited at
undersized passages after32.80/44.46/62.49studs of forward travel. Under the six
concurrent trials, the delayed node38route hit the8-second calculation timeout
once, invalidated its stale result and recovered; it did not repeatedly replan
while waiting. The probe's requests field is a RequestId delta, so its value3
includes that invalidation as well as the two actual attempts. All other cases
used one attempt. Full traces: navigation-seed2199511-final.json.

Across both layouts the final10trials recorded zero reversals. This distinguishes
actual arrival on reachable routes from safe waiting at physical obstructions.

## Actual production third-pump encounter

Run separately through normal shared controller/adapter state and valid pump
guards, not just cloned navigators. Counts1and2 had no spawn; the third distinct
pump asynchronously produced exactly one giant. Tests intentionally paused the
entity at spawn, anchored/increased health of the tester and disabled damage
temporarily in the disposable Play session; none of that is production code.

Latest seed101 spawn separation:100.12studs. Three reachable target changes
completed within1.63/1.81/1.76studs, with zero repeated reversals. Pause drift was
zero over1second and the spawn count stayed1. Earlier seed2199511 integration
also passed at82.53stud spawn separation. RequestId differences in these pause
tests include Stop invalidations; they are not path-computation counts.

## Physical clearance and limits

Measured actual template: approximately15.0004wide ×16.0000high ×3.6428deep,
navigation radius7.60017. Some solid corridor ribs leave only14.897studs of
headroom at centre,13.809at±5studs and12.255at±7.5studs. These are actual collidable
Block Parts, not just broad-phase mesh bounding boxes. The fix does not shrink
the entity/collider or change the level. Such passages remain impassable; the
giant approaches and waits instead of pacing or clipping. Supporting pursuit
through them requires a separate size/crouch/opening design decision.

This is single-client Studio testing, not multiplayer/device/public-server load
testing. The Studio capture/viewport showed a rendering issue (magenta/empty sky),
so this task does not claim a successful visual animation QA pass. Movement,
spawn and pause results above are instrumented real DataModel measurements.

## Source and recovery

Original live scripts are preserved in
ServerStorage.PoolSlideNavigationBackup_20260831. Repository source mirrors were
compared exactly against Edit Studio Source. Only these production sources changed:

- ServerScriptService/Level 2 Systems/Level 2 Pool Foam Navigator.ModuleScript.lua
- ServerScriptService/Level 2 Systems/Level 2 Pool Slide Controller.ModuleScript.lua

The large Navigator Git diff includes a preexisting newer Studio snapshot. This
task's baseline is the saved live script, not Git HEAD. Unrelated repository edits
were preserved. No Git commit/push or active-server restart was performed.

Publication status and version are recorded in studio-sync-manifest.json under
lastPoolSlideNavigationMirror and lastPublished after verified Studio publication.
