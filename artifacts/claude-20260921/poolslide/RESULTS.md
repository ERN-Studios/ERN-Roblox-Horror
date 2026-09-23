# Pool Slide chase latency — measurements 2026-09-21

Studio play session (server + one client on the same PC), place v1958 + this branch,
seed pinned `Level2Seed = 1182081016` (resolved the same, attempt 1), one player, spawn
after pump 2 at 194.75 studs (anchor `Level 2 Entity Patrol Node 4.1`). The target is
moved by `harness-*.luau` (server-driven, 16 studs/s round four hall nodes), so every run
sees the same stimulus. `os.clock()` was checked against `GetServerTimeNow()` in this
session: ratio 0.99999 (wall clock, not CPU time).

**Goal age** = seconds since the request whose route is installed was made.
**Goal error** = studs between that request's goal and the target's position now.
Samples at 5 Hz while the state is CHASE/WAITING.

## Same round A/B (`harness-ab-server.luau`, 75 s per phase, mover holds ≥110 studs)

| Phase | PlanHorizon | n | goal age p50 / p90 / p95 / max (s) | goal error p50 / p90 / p95 / max (studs) | planner busy | Heartbeat mean p50 / p95 (ms) |
|---|---|---:|---|---|---:|---|
| 1 | 0 (old whole-route) | 310 | 3.2 / 11.9 / 13.9 / 16.1 | 39 / 164 / 183 / 191 | 95 % | 27.1 / 111.4 (*) |
| 2 | 96 (shipped) | 349 | 0.9 / 1.7 / 2.8 / 5.2 | 15 / 31 / 53 / 99 | 63 % | 16.6 / 19.7 |
| 3 | 0 (old whole-route) | 350 | 1.8 / 6.6 / 10.6 / 14.2 | 27 / 99 / 158 / 179 | 84 % | 16.6 / 27.8 |
| 4 | 96 (shipped) | 349 | 1.0 / 1.9 / 2.7 / 4.7 | 17 / 37 / 42 / 70 | 69 % | 16.6 / 28.2 |

(*) phase 1 overlapped other Studio MCP calls from this session (a full template
`GetDescendants` dump); treat its frame times as polluted. Phases 2–4 are comparable: the
horizon adds no frame cost (the planner's 2 ms/frame slice is unchanged; it is simply busy
less of the time).

Latency target used: the installed goal should be ≤ 1.5 s old typically and ≤ 3 s at p95
while the target moves (one 0.75 s repath interval + one short plan), at any range.
Result: p50 0.9–1.0 s, p95 2.7–2.8 s (was 10.6–13.9 s).

## Separate rounds (`harness-server.luau`)

| Build | n | goal age p50 / p90 / p95 / max | goal error p50 / p90 / p95 / max |
|---|---:|---|---|
| before (instrumented only) | 737 | 1.6 / 7.3 / 10.2 / 15.0 | 21 / 70 / 101 / 177 |
| after, long range @16 studs/s | 316 | 1.1 / 2.1 / 3.0 / 4.9 | 16 / 32 / 41 / 63 |
| after, close range (<100 studs) | 369 | 0.8 / 1.5 / 2.2 / 4.5 | 16 / 28 / 32 / 66 |

## What the request trace showed (before)

Long-range requests (span 110–220 studs) needed 0.5–1.5 s when the route was clear and ran
the whole 3 s `PATH_REQUEST_TIMEOUT` out whenever a detour search was needed somewhere
along the route (`Queries` 2 000–8 000 at the 2 ms/frame slice, `Aborted = true`,
outcome EXPIRED/SUPERSEDED). Three and four such requests in a row left the incumbent route
in place for 9–15 s: the giant walked (and once ran at 20 studs/s) to where the player had
been, and stood there. Close range was healthy before as well (150–640 ms per plan).

After: requests at range are truncated (`Truncated = true`), 350–1 000 ms each, and one
expiry cannot cascade because the next plan is cheap again.

## Spawn / escalation acceptance (solo, three rounds on the same seed)

- pump 2 (second distinct pump, dev pump pair) → one spawn, `SpawnCount = 1`,
  `SpawnDistance = 194.75` ≥ 100 from the only living participant, 1 probe.
- pump 3 (real ProximityPrompt hold on station 3) → `Phase = ENRAGED`, `Enraged = true`,
  speed 32, **same Model instance** (a tag set before pump 3 was still on the only
  `Level 2 Pool Slide` model), `SpawnCount` still 1.
- Three consecutive rounds in one server session each spawned once; `Controller.Stop`
  reset every published attribute between rounds.

Not verified: more than one living participant (spawn distance from *every* participant),
a published server, wall-contact sampling (see handoff), the enraged phase at range.
