# Card #86 — "Pool mouth entity stops up in Level 2" — phase 1 (offline)

## Codex correction, 21:03 UTC

The CPU-only clock claim in the original report below is false in this Roblox runtime. Native Edit measurement around task.wait(1): os.clock delta 1.0146677, tick delta 1.01466775. The mocked 28-second CPU/wall divergence is not evidence of a Roblox stall. Source comments are corrected; the independent server-time guard is defensive. The clearance latch and its bounded recovery still require native validation. Preserve the original agent report below as review history, not as an accepted root-cause conclusion.

Agent A86 (Opus 5). No Studio access in this phase; nothing below is a runtime
verification unless it says so.

## 0. Which entity

**The Pool Slide.** No script in the project uses "mouth" for a Level 2 entity;
the only `mouth` identifiers in the codebase are `Level3_SlideMouthPosition`, the
open end of a flume bore. The Pool Slide is the giant pipe/slide creature whose
open end reads as a mouth; the Pool Foam is five blobs with no such feature. Both
are enabled in Level 2 today (`Level 2 Round Adapter` starts Foam then Slide), so
CLAUDE.md's "Level 2 has exactly one hostile" is stale, as the brief says.

**The Pool Foam is not implicated in any stall class below.** The Slide's
`navigationTuning` is the only caller that passes `StableRoutes = true`; the Foam
controller never sets it, so in `Level 2 Pool Foam Navigator` every certification
branch, `_waitingForClearance` and the whole planning-deadline pipeline take their
dead else-path. The two navigators are separate forked files, so nothing here
touches the Foam. It was left out of scope and out of the diff.

## 1. Root-cause analysis

Everything that can leave the rig standing while a target exists, ranked. All
line numbers are the pre-fix files at HEAD.

### Rank 1 — a planning pass owns the navigator for unbounded REAL time
`Level 2 Pool Slide Navigator.ModuleScript.lua`, `planningCheckpoint` (321) and
`_requestPath` (1985).

`_requestPath` sets `Computing = true` and a deadline of
`os.clock() + PathRequestTimeout` (3, from the controller). Every guard in the
pipeline — `shouldAbort`, `planningCheckpoint`, `_rejectStableRoute`,
`_joinStableRoute`, `_smoothStableRoute`, `_reachablePrefix` — compares against
`os.clock()`. **On a Roblox server `os.clock()` is CPU time**, and
`planningCheckpoint` is the one place the pass yields: it spends .002 s of budget
and then `task.wait()`s a whole frame, during which the CPU clock does not move.
The 3-second budget is therefore three seconds of *compute* spread over as much
wall time as the pass needs. The project has already measured this ratio once
(MEMORY `roblox-studio-osclock-cpu-time`: a 900 s CPU deadline ran ~4× longer in
wall time).

While `Computing` is true, every escape is closed at once:

| Escape | Where | Why it is closed |
|---|---|---|
| Step re-plans when the route runs out | `Step`, 2429 | branch requires `not self.Computing` |
| `SetGoal` re-plans on target motion | `_stableNeedsPath`, 1767 | `if self.Computing then return false end` |
| the in-flight-request timeout | `_stableNeedsPath`, 1762 | `age >= PathRequestTimeout` is the same CPU clock |
| controller watchdog forces a graph route | Controller `updateModel`, 659 | `planning = nav.Computing and now - RequestStartedAt < PATH_REQUEST_TIMEOUT`, again CPU |

A rig with no incumbent route stands still for the whole window, and if the pass
is then rejected (Rank 3) it immediately starts another. **This is the mechanism
that best fits the report and the existing measurements**: the 2026-09-09
measurement recorded `SLIDE_ACTIVE_STATIONARY` in 344 of 439 active samples
against `SLIDE_ACTIVE_MOVING` in 95 — 78 % of the encounter standing still. That
session read those rows as a performance measurement; they are a direct record of
the stall.

Runtime tell: `Level2_PoolSlideComputing` true across many seconds with
`Moving=false` and `Waypoints=0` (all four are published by the new diagnostics
block). Measured offline at **28.0 s of wall time for a single pass** — see §2.

### Rank 2 — `WAITING_FOR_CLEARANCE` never ends against a player who stands still
`_probeBlockedClearance` (1743), `_waitingForClearance` (1735), `Step` (2419),
`_stableNeedsPath` (1781), Controller `updateModel` (661).

When `_reachablePrefix` can only certify part of a route it installs the prefix
and latches `BlockedGoalApproach` at its end. The rig walks there and waits. The
latch is cleared **only** by a probe that succeeds — and the probe is
`_walkingEdgeClear(from, target)`, a static geometry test against an authored
vault rib or column, which never starts passing. Meanwhile `Step` returns before
its repath branch, `_stableNeedsPath`'s last clause excludes the case, and the
controller watchdog explicitly exempts `nav.WaitingForClearance` from recovery.
The only remaining escape is the target moving `RepathDistance` (6 studs, 4
enraged) away from `InstalledGoal`.

So the wait ends when the player runs and never when they stand still — which is
the exact behaviour this game asks of the player. Worse, the invalid-endpoint
early-out (`if not finiteVector3(from) ... then return false end`) returned
without testing or counting anything, so a latch whose prefix walk recorded no
endpoints waited forever having never probed once.

Runtime tell: `Level2_PoolSlideState = "WAITING"`, `PathStatus =
"WAITING_FOR_CLEARANCE"`.

### Rank 3 — certification is all-or-nothing, so a failed pass installs nothing
`fullyCertified` (1729), `_requestPath` (2160–2210), `_rejectStableRoute` (1960).

`fullyCertified` demands `Aborted == false and Unwalkable == 0 and Unresolved == 0
and Queries < 72000`. Anything else falls to `_rejectStableRoute`, which preserves
an incumbent route if there is one and otherwise leaves `Waypoints` empty with
`Status = "NO_PATH"`. The designed escape is the `PARTIAL` prefix at 2168, but it
is gated on `stats.Aborted == false` — i.e. only when the pass *finished* and
found unwalkable segments, never when it ran out of budget. Two compounding
reasons a long route cannot certify: the body box is `AgentRadius*2 - .2` ≈ 16.2
studs across against a clear corridor channel the module's own comments measure at
±2 studs, and past the deadline `planningCheckpoint` makes `_surfaceAt` return nil
and `_bodyBoxClear`/`_bodySweepClear` return false, so every remaining query
answers "blocked" and inflates `Unwalkable`/`Unresolved`.

Runtime tell: `PathFailure = "replacement route incomplete, blocked, or timed
out"` with `Waypoints = 0`. **Not fixed here** — loosening certification is how
the giant would start clipping geometry, which the brief forbids. See §5.

### Rank 4 — "target changed direction during planning" deletes the incumbent
`_requestPath` (2148 and again at 2196). Both direction guards do
`self.Waypoints = {}` *before* rejecting, unlike every other reject path. A player
circling the giant can trip this on consecutive requests and leave it with no
route each time. Proposal only.

### Rank 5 — authored standing time
`updateAttack`/`beginAttack` return early from `updateModel` for
`AttackWindup .5 + AttackRecovery .7 = 1.2 s` per swing with a 2.4 s cooldown, and
`chooseTarget` → `livingRecord` returns nil (→ `navigator:Stop()`, IDLE) for any
player who is escaped, in the exit transition, or under `PlayerProtection`. Both
are intended; they matter because they are the two ways a probe can mistake
correct behaviour for the bug.

### Checked and cleared

- **Jump waypoints**: `AgentCanJump = false`, and `Step` reads only
  `waypoint.Position` — no `Action` is consulted anywhere. Not a stall source.
- **`Path.Blocked`**: `_bindBlocked` (1675) revalidates the segment actually being
  walked and sets `LastPathAt = -math.huge` when it clears the route, so it forces
  an immediate re-plan rather than stalling.
- **Yields inside Heartbeat**: `Step` → `_placeFoot` → `_bodyBoxClear` does reach
  `planningCheckpoint`, but that returns `true` immediately when
  `planningThreads[coroutine.running()]` is nil, which it always is on the
  Heartbeat thread. No yield on the movement path.
- **Step's recovery ladder** (steer / short stride / clearance seek / waypoint
  skip / retreat) and its budgets (`ClearanceSeeks`, `WaypointSkips`,
  `RouteFailures`, `RouteRetreats`): all reset on progress or on route install.
  No leak found.
- **`Computing` leaks**: every early `return` inside the request thread is guarded
  by `requestId ~= self.RequestId`, i.e. a newer request already owns the flag.

### History

`git log` plus a diff of all five `ServerStorage/PoolSlideContextDiagnosticBackup_*`
generations: the Controller is byte-identical from `_0710` through `_MP9`, and the
Navigator's only pre-live change in that chain is the MP8 "budget fix", which
raised the slice budget in `PrepareContext` (256→1024 nodes, 2 ms→6 ms) — the
one-off world scan, not the per-request planning loop. MP9→live added
`GoalArrivalDistance`, the `_refreshObstacleFilters` cache, `_smoothStableRoute`'s
inner deadline and `_joinStableRoute`'s early-out. **Nobody has previously touched
the CPU-vs-wall-clock premise.**

## 2. Offline evidence

New: `tools/tests/test_pool_slide_navigation.py` (7 checks). It loads the real
navigator source and supplies two clocks — `os.clock` advances only while the pass
computes, `workspace:GetServerTimeNow` also advances one frame per `task.wait` —
plus a cooperative scheduler, and drives the real `_requestPath`, the real
`shouldAbort` and the real `planningCheckpoint` (reached through the real
`_bodyBoxClear`). Geometry is stubbed; these stalls are about time, not geometry.

It then runs the identical fixtures against `git show HEAD:` of the same module,
which **must fail**, so the file is its own before/after record:

```
Pool Slide navigation: 7 checks passed (offline clocks and scheduler; geometry stubbed)
FAIL: one planning pass held the navigator for 28.0 s of real time (allowed 5.0);
      Step cannot repath and the watchdog is suppressed for all of it
FAIL: the rig waited on static geometry forever while the target stood still
FAIL: a latch with no recorded probe endpoints also has to end
Pool Slide navigation: pre-fix source failed 3 of 7 checks, as expected
```

The pre-fix source *passes* the other four, including "an aborted pass keeps the
route the rig is already walking" and "a cleared obstruction still releases the
wait immediately" — so the fix does not buy the stall bound by giving up
incumbent preservation or by disabling the wait.

Also run, all green, unchanged: `test_level2_pool_slide_release` (372),
`test_pool_foam_navigation` (25), `test_pool_foam_audio` (24),
`test_level2_tunnel_height` (33822).

`_local/pool-foam-navigation-repro.luau` is the 2026-09-09 Pool Foam repro and
exercises the `StableRoutes = false` paths only; it is not a Slide harness.

## 3. Studio probe pack

`artifacts/trello-20260915/probes/`. All four compile under luau 0.737. They read
**attributes only** — `require` inside `execute_luau` is a separate module
instance, so `Controller.GetDebugSnapshot()` is unreachable from a probe. That is
why the controller now publishes four extra fields behind
`workspace.Level2_PoolSlideDiagnostics` (see §4).

- **`86-recorder-install.luau`** — (a)+(b). Installs one `workspace.Probe86` folder
  with `Samples`/`Stalls` StringValues and a `task.spawn` sampler at 0.25 s.
  Returns immediately. 21 columns: wall, **cpu**, seed, pinned, pumps, paused,
  state, phase, path, computing, waypoints, clearanceProbes, moving, speed, x/y/z,
  targetId, targetDist, stillFor, failure. Recording `cpu` next to `wall` is
  deliberate: their ratio is the Rank-1 premise measured on the real server, and
  it is the number that calibrates `PLANNING_WALL_TIMEOUT`. The stall detector
  writes one line per *episode* when displacement stays under 0.5 studs/s for more
  than 4 s while `TargetUserId ~= 0`.
- **`86-recorder-read.luau`** — summarises in Luau (wall-per-cpu ratio, % standing
  while targeted, % Computing, longest unbroken Computing run, WAITING count,
  no-route count, failure histogram, the stall lines). Set `TAIL` for raw rows.
- **`86-round-control.luau`** — (c)+(d). `ACTION` = `pinSeed` / `pumps` /
  `invincible` / `still` / `chase` / `quietFoam` / `restore` / `status`.
  - **Seed plan**: unpinned first (the owner's actual case), then 101 (the seed
    every stall comment in the module was measured on), 303 (the detour-search
    seed), 651224003 and 341095071 (`pool-slide-acceptance` generations 2 and 3).
    Pin with `workspace:SetAttribute("Level2Seed", n)` before the launch pad;
    `Level2_SeedPinned` reads back.
  - **Two modes.** `chase` (unanchored) exercises long routes and Rank 1;
    `still` (anchored root) is the only way to reproduce Rank 2, because a moving
    goal masks it. Both raise `Humanoid.MaxHealth` so the 100-damage attack does
    not end the round — deliberately *not* `PlayerProtection`, which would make
    `livingRecord` return nil and stop the chase outright, i.e. hide the bug.
  - **(d) Pool Foam**: `quietFoam` re-parents the Foam runtime instances into
    `ServerStorage.Probe86FoamHold`. Its controller keeps running and no
    configuration module is touched; `restore` puts them back.
    `workspace:SetAttribute("EntityPaused", true)` remains the blunt option but
    pauses the Slide too.
- **`86-recorder-stop.luau`** — removes the folder and the diagnostics attribute.

## 4. Prepared fix

Two surgical changes, both about time, neither about geometry. No teleports, no
new movement code, no loosened clearance test.

**`Level 2 Pool Slide Navigator.ModuleScript.lua`**

1. New `planningExpired(context)` next to `planningCheckpoint`: a pass is over when
   **either** the CPU deadline **or** a new wall deadline passes. `planningCheckpoint`
   uses it on both its gates; `shouldAbort` in `_requestPath` gains the same wall
   term; the four `os.clock() >= context.Deadline` sites in `_rejectStableRoute`
   and `_joinStableRoute` become `planningExpired(context)` so that a wall abort
   still **preserves the incumbent route** instead of clearing it. New tuning key
   `PlanningWallTimeout` (default 8, range 1–30).
2. `_probeBlockedClearance` gains a bounded probe count (`MAX_CLEARANCE_PROBES = 3`)
   and a `_releaseBlockedApproach` helper; the invalid-endpoint early-out is folded
   into the counted path. Releasing the latch moves nothing and bypasses no
   geometry — it only re-opens planning and un-suppresses the controller watchdog.
   `ClearanceProbes` is initialised in the constructor, reset in `Stop` and where
   the latch is installed, and exposed in `GetDebugSnapshot`.

**`Level 2 Pool Slide Controller.ModuleScript.lua`**

3. `PLANNING_WALL_TIMEOUT = 4` passed through `navigationTuning`.
4. The four diagnostics publishes behind `workspace.Level2_PoolSlideDiagnostics`
   (`Computing`, `Waypoints`, `ClearanceProbes`, `PathFailure`), plus their entries
   in `resetPublished`. Absent in production; `publish` writes only on change.

No production value in any configuration module was changed. Line endings stay LF.
`git diff --stat`: navigator +100/−16, controller +18/−0.

**The calibration knob.** 4 wall-seconds is deliberately *looser* than the
3 CPU-second `PathRequestTimeout`, which gives the fix a property worth stating:
where `os.clock` tracks wall time the CPU deadline still fires first and behaviour
is bit-identical to today; the new bound binds only once real time has run away
from compute time. That makes it safe to land before measuring, and it is the
conservative first value — the recorder's wall-per-cpu ratio and the distribution
of pass durations are exactly what should tighten it (1.5 s is the target if the
ratio confirms; going lower risks no route ever certifying, which is worse than
the bug).

## 5. Not fixed — proposals needing Studio data first

- **Rank 3**: let the `PARTIAL`/`_reachablePrefix` fallback run when the centring
  pass aborted on a deadline, not only when it completed. `_reachablePrefix` would
  need its own small budget past the deadline. This changes *what the giant walks
  on*, so it must not land before the recorder shows how often Rank 3 actually
  fires and what `PathFailure` says.
- **Rank 4**: the two direction guards should reject without `self.Waypoints = {}`,
  like every other reject path. Small, but it changes chase feel.
- **Controller watchdog**: `WATCHDOG_SECONDS`/`WATCHDOG_COOLDOWN` (3 / 8) are CPU
  seconds too. With the wall bound in place `Computing` now clears promptly so the
  watchdog fires again; whether the cooldown also needs a wall bound is a
  measurement, not a guess.
- **Pool Foam has no test suite** (CLAUDE.md). `test_pool_slide_navigation.py` is
  the Slide's first navigation suite; it does not cover geometry.

## 6. Handover hazards

- **Studio holds an older copy of both files.** `studio-sync-manifest.json` lists
  both as `pending-studio-push` with a `studioSha256Before`, from before this
  agent started. Its `sha256` for both currently **matches** the edited working
  copy, so the record is fresh — but `TunnelLobbyBuilder` and `ZyntraMonetization`
  are pending with **stale** hashes, so another agent is mid-edit. Run
  `push_repo_to_studio.py --audit` and expect to reconcile the Studio-side drift
  before pushing.
- Everything in §1 is read from the **repo** copy. The live Studio source may
  differ; diff it before trusting the line numbers.
- Nothing was committed, pushed, published, or run against Studio.
