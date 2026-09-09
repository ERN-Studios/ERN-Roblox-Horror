# Offline review and diagnostic sources — 2026-09-09

**NON-RUNTIME ARCHIVE. No overall gameplay or performance pass is claimed.**
The diagnostic source files were copied byte-for-byte from the task's
`work/level2-entity-2026-09-09/current-review/` directory. Their sizes and SHA-256
hashes are recorded in `manifest.json`. No fixture or diagnostic was executed
while archiving them; the archival step itself made no Studio changes. Later
native runs performed by the main agent are recorded separately below.

## Contents and limits

- `pump3-native-test.server.lua` and `pump3-native-test.client.lua`: paired,
  temporary **single-player** normal-Play diagnostics. They require the exact
  Studio experience, temporary script names, and a shared TestToken; the server
  also requires an explicit MinimumSpawnDistance. They drive the existing queue
  and proximity/line-of-sight validated pump method, record actual spawn distance,
  same-model third-pump enrage, movement, exit-power timing, and memory samples.
  Diagnostic player placements are used. This is **not** an ordinary-input escape
  or multiplayer replication test. The ordinary game entry/loading handshake,
  character health, enemy damage, and other enemy tuning are not bypassed.
- `pump3-active-server-profile.luau`: a **plugin-security MCP Server Play snippet**,
  not a normal Script. It requires exclusive ownership of the server profiler,
  waits for a living player's actual ENRAGED entity, and bounds capture at 20
  seconds / 1 kHz. It records partial captures and cleanup failures rather than
  claiming a completed active window. It must never be installed in a runtime
  service or published. A profile needs separate collection and analysis before
  any CPU claim; endpoint state samples are not CPU attribution.
- `obstacle-filter-cache.fixture.luau`: a table-mock comparison of original and
  proposed query-filter behavior. No Instances or gameplay mutation. It checks
  ordered exclusions as player/character membership changes and counts filter
  assignments. Even a passing fixture would not prove production performance,
  full navigator cleanup, corridor traversal, or multiplayer safety.
- `refresh-obstacle-filters.candidate.luau`: **offline proposed code, unapplied**
  when archived. It is not a full navigator and is not an authorized repository
  push into Studio. Any requested optimization requires a fresh authoritative
  Studio baseline, scoped conflict-safe editing, and live verification.

## Safety and evidence status

The first baseline attempt encountered Studio disconnect `RCC-288`. The corrected
harness uses the current `Level2_EntityGround` attribute and excludes
`Level2_NoEntityGround`. A later actual baseline capture is now preserved below;
it contains a completed observation with **failed movement checks**, not a release
pass. Do not change failed, blocked, partial, or unobserved tests into PASS
because the source exists, was reviewed, or compiles.

Keep these files outside mirrored runtime service folders. After a separately
authorized test, remove only its exact temporary Studio instances, harvest the
result before cleanup, and attach result hashes and limitations separately.
Do not publish test scripts or leave a profiler running. Stop on an ownership
or baseline conflict rather than overwriting another developer's state.

The native model preserved alongside this archive lives under
`assets/level2/poolslide/native-studio-2026-09-09/`. It is a single entity-template
backup only, not a complete game snapshot.

## Baseline 2 — actual native observation, before the safety/cache changes

Files `baseline2-gameplay.json`, `baseline2-server-profile.json`, and
`baseline2-server-trace.json` preserve the exact collected data. The gameplay and
profile files retain their original `{Attributes, Data}` envelopes (Data is a
JSON string); the trace is already decoded JSON. The original 60-stud spawn
threshold was tested here, **not** the subsequent proposed 100-stud threshold.
Seed: `405609315`, generation 1, one real Studio test player.

| Check | Actual baseline result |
|---|---|
| No entity at pumps 0 and 1; one at pump 2 | PASS |
| Closest living-player spawn distance | 89.993225 horizontal studs; PASS against the old 60-stud limit only |
| Pump 3 uses the same entity and sets ENRAGED | PASS |
| Original exit-power transition | PASS; observed 11.913007 s after pump 3, sampled at approximately 0.25 s |
| Active movement observation | **FAIL: 0 studs in 20.018337 s** |
| Actual speed reaches 32 | **FAIL: maximum published speed 0** |
| Exactly one spawned model | PASS |

All 69 movement samples reference the same entity. The final snapshot has zero
route installations and zero waypoints; request ID advanced from 4 to 11. The
last reported path failure is `target changed direction during planning`.
That is observed telemetry, not proof that this message explains every stalled
request. A state change to ENRAGED alone therefore did **not** validate the chase.

The profile captured **18:32:53.497–18:33:13.567 UTC** on 2026-09-09 at 1 kHz.
Its recorded capture window completed without cleanup or no-data failures; the
trace reports 20.072489 seconds and 19.557026 endpoint-sampled active seconds.
The live actor remained healthy and the entity was active, but did not move.
These results must not be relabeled as a successful moving chase.

### Non-overlapping sampled script CPU attribution

`analyze-script-profile.mjs` reads profiler schema v2 without modifying anything.
The category roots are disjoint; their durations are added once. Within each
callgraph branch, only the **first** Pool Slide Controller/Navigator/Rig Adapter
function owns its inclusive subtree; descendant Pool Slide functions are not
added again. The parser rejects shared/cyclic nodes, mismatched child arrays,
unreachable nodes, and invalid duration partitions. Roblox documents node and
function durations as microseconds and session timestamps as milliseconds.
[Roblox Script Profiler documentation](https://create.roblox.com/docs/studio/optimization/scriptprofiler)

- All sampled script CPU: **4.767991 s** during the 20.070-second profiler window.
- Unique inclusive Pool Slide attribution: **1.843447 s**, or **38.663% of sampled
  script CPU**, averaging **91.851 sampled milliseconds per wall-clock second**.
- This includes **5.121 ms** in `GetDebugSnapshot` called by the diagnostic.
  Excluding that diagnostic caller gives **1.838326 s**.
- Private Pool Slide `_refreshObstacleFilters` inclusive attribution:
  **631.674 ms**, **34.266%** of the Pool Slide total and **13.248%** of all sampled
  script CPU. Its callgraph-node sum independently equals its function total.

These are aggregate sampled script-stack costs, including attributed native API
calls. They are **not** total machine/server CPU utilization, per-frame budgets,
median/p95 frame times, rendering/physics totals, or memory-leak evidence.
Frame median and p95 are unavailable from this aggregate export and are recorded
as null. No values from an unshared memory query were inferred.

Reproduce the derived `baseline2-analysis.json` without Studio:

```sh
node tests/level2/poolslide/studio-review-2026-09-09/analyze-script-profile.mjs \
  tests/level2/poolslide/studio-review-2026-09-09/baseline2-server-profile.json
```

The baseline predates the main agent's subsequent spawn-distance/cache edits.
It does not establish that those edits work or are published. Results for a
modified source baseline must be recorded separately, with its own source hashes.

## Cache 3 and budget 4 — separate native runs, different seeds

The later raw gameplay/profile/trace files are direct JSON objects, unlike the
baseline-2 gameplay/profile envelopes. `cache3-analysis.json` and
`budget4-analysis.json` were generated with the same read-only parser.
These trials use **different generated layouts and different movement**, so the
figures are observations, not a controlled benchmark or causal percentage
improvement attributable to one patch.

| Observation | Baseline 2 | Cache 3 | Budget 4 |
|---|---:|---:|---:|
| Seed | 405609315 | 1162830069 | 1254293067 |
| Tested spawn minimum, studs | 60 | 100 | 100 |
| Actual nearest spawn distance, horizontal studs | 89.993 | 142.209 | 146.165 |
| Observation duration, s | 20.018 | 20.102 | 20.160 |
| Actual horizontal travel, studs | 0 | 0 | 513.307 |
| Maximum published speed, studs/s | 0 | 0 | 32.001 |
| Same model at pump 3, ENRAGED | PASS | PASS | PASS |
| Original exit-power delay, s | 11.913 | 11.796 | 11.658 |
| All 9 diagnostic checks | 7 PASS / 2 FAIL | 7 PASS / 2 FAIL | **9 PASS** |
| Profiler window, s | 20.070 | 20.146 | 20.445 |
| All sampled script CPU, s | 4.767991 | 6.123890 | 3.280444 |
| Unique inclusive Pool Slide, s | 1.843447 | 1.533832 | 0.698742 |
| Pool Slide share of sampled script CPU | 38.663% | 25.047% | 21.300% |
| Pool Slide sampled ms per wall-clock second | 91.851 | 76.136 | 34.177 |
| Private filter-refresh inclusive CPU, ms | 631.674 | 21.883 | 7.456 |

Budget 4 captured **18:41:28.275–18:41:48.720 UTC**. Its profile trace recorded a
completed, non-partial capture with no cleanup failure and 19.929287
endpoint-sampled active seconds. The gameplay observation recorded **zero coarse
direction reversals**, one actual entity, and all 9 diagnostic checks passed.
The actor remained healthy in the captured final state. This is an actual moving
entity observation, not merely an ENRAGED attribute or animation-only test.

Budget 4's inclusive entity total contains 2.144 ms from a diagnostic
`GetDebugSnapshot` caller; non-diagnostic callers total **696.598 ms**. The private
filter-refresh subtree accounts for **7.456 ms / 1.067%** of inclusive entity
time in this run. As above, these are sampled script costs, not a server-wide
hardware CPU percentage or a frame-time distribution. No median or p95 is
available from the aggregate profile.

Cache 3 still had no movement despite its farther spawn and lower sampled
filter-refresh cost. Budget 4 demonstrates one successful generated layout after
the main agent's additional scoped planning-budget adjustment. It does not alone
prove every corridor, multi-player proximity safety, ordinary escape, long-run
stability, or public asset availability. No publication is established here.

### Budget 4 memory evidence and its limits

`budget4-memory.json` is an actual Scene Analysis snapshot at
**2026-09-09 18:41:48 UTC**, while the entity existed and pump count was 3.
Its unparented-instance ownership report lists **one Path** owned by the private
Pool Slide Navigator and **four AnimationTracks** owned by the Pool Slide Rig
Adapter. These are consistent with the active encounter's retained resources;
an unparented object in an ownership report is not automatically leaked.
This one snapshot does not prove cleanup or absence of long-session growth.

The animation-memory report attributes **6,273 bytes** for the currently reported
run clip `71870594656450` to this entity's Animator. That is **one reported loaded
animation asset**, not the total of all four clips, meshes, textures, Luau state,
navigation data, or the entity's full RAM footprint.

Per-script Luau-heap measurement was reported unavailable due to feature flag
`STUDIOPLAT37936`; no per-entity byte figure is inferred. `Stats` memory samples
in gameplay JSON describe the broader Studio/server process and generated world,
not memory attributable to this one entity. In particular, multi-gigabyte whole
Studio totals must **never** be presented as this entity using that much RAM.
No controlled before/after entity-allocation delta or repeated cleanup trend is
claimed by this archive.

## Budget 5 — second successful random layout

`budget5-gameplay.json`, `budget5-server-profile.json`, and
`budget5-server-trace.json` preserve the second native run of the scoped
planning-budget change, seed **1094051225**. All **9 diagnostic checks passed**:
one actual entity at pump 2, none at 0/1, the same instance ENRAGED at pump 3,
and the original exit-power transition. Measured nearest spawn distance was
**153.289978 horizontal studs** against the 100-stud limit. It travelled
**383.095326 studs in 20.267080 s**, reached **32.002918 studs/s**, recorded
zero coarse direction reversals, and the exit powered after **11.618119 s**.

Its profile window was **18:43:16.470–18:43:36.827 UTC / 20.357 s**:

- All sampled script CPU: **4.535372 s**.
- Unique inclusive Pool Slide CPU: **791.810 ms**; **17.459%** of sampled script
  CPU, averaging **38.896 sampled ms per wall-clock second**.
- Non-diagnostic callers: **788.786 ms**, after excluding 3.024 ms in the
  diagnostic's `GetDebugSnapshot` call path.
- Private filter refresh: **8.897 ms / 1.124%** of the inclusive entity total.

Thus two different generated layouts have successful 20-second native moving
entity observations after the final scoped route-budget edit. Their observed
script cost is recorded separately, not averaged into a causal performance
improvement claim. Neither run establishes frame median/p95, whole-entity RAM,
an ordinary-input escape, multiplayer behavior, or publication.

### Native control-flow fixture

`route-install-budget.fixture.luau` and
`route-install-budget-fixture-result.json` preserve the main agent's **26/26
passing native fixture checks**. The original MCP result envelope is retained.
These checks cover deadline/ownership restoration, exact-origin joins, rejected
uncertified joins, preservation of mandatory certified route vertices, and
cleanup after predicate errors. They use mocked geometry dependencies and do
not replace real corridor, moving-door, performance, or multiplayer validation.

`filter-cache-fixture-result.json` separately preserves the **38/38 passing
native table-mock checks** for filter-cache membership and assignment behavior.
It is not a server performance or memory pass.

`current-studio-source-comparison.json` records the final read-only source
comparison: 122 scripts, with only the requested Pool Slide Controller and
Navigator differing from the starting Studio export; no other script changed or
was removed. `test-script-cleanup.json` records removal of the two exact temporary
diagnostic scripts. These records are provenance/cleanup evidence, not a public
release. The final release remains held on the live configuration/verification
flags; see `docs/studio-sync/20260909-pump3-results.md`.
