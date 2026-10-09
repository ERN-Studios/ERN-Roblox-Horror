# Level 2 Pool Slide — server usage, 2026-09-09

**What was measured:** the *new* Pool Slide that another session installed into
Studio on 2026-09-09 (`Level 2 Pool Slide Controller` / `Navigator` / `Rig
Adapter` / `Configuration` under `ServerScriptService."Level 2 Systems"`, marked
"DRAFT ONLY: v1767 integration"). It exists **only in Studio**: the repo mirror
still carries the 2026-09-02 comment that the Pool Slide was removed, and the
manifest has no entries for the four scripts. Level 2 therefore has two hostiles
in the live place right now: Pool Foam (5 clones) and this Pool Slide (1 giant).

Two Opus 5 agents produced the two parts below. Part 1 is a live measurement in a
Studio play session (3 Level 2 rounds, 1261 samples at 0.5 s, nothing edited or
saved). Part 2 is a static cost model over byte-exact copies of the Studio
scripts (pulled through a loopback HTTP dump, not transcribed).

## Headline numbers (from Part 1, verified against the raw samples)

| Window | HeartbeatTimeMs mean | frames > 16.7 ms |
|---|--:|--:|
| Lobby | 0.16 ms | 0 % |
| Level 2 round, Pool Foam only, Pool Slide dormant | 1.10 ms | 0 % |
| Pool Foam motion alone (unpaused − paused, before spawn) | +0.79 ms | — |
| Pool Foam + Pool Slide motion (unpaused − paused, after spawn) | +2.07 ms | — |
| **Pool Slide's own share (difference of the two)** | **≈ +1.3 ms/frame ≈ 7.7 % of the 60 Hz budget** | — |
| Pool Slide active and moving (95 samples) | 5.23 ms, p95 22.6 ms, max 56.6 ms | 8.4 % |

- Spawned on **probe 1 in 3 of 3 rounds**, ~0.5 s after pump 2. `SpawnProbeCount`
  and `SpawnNavigatorBuilds` never exceeded 1; `LastError` was empty in every
  sample. The 2026-09-02 failure mode (never spawns, retries forever, 78 % of the
  frame budget) is gone.
- Navigation context built ~1 s after world handover; worst builder slice 4.1 ms.
- Mean server FPS while it hunted: 54.4, against 58.3 in the lobby.
- The cost that matters is the **tail**, not the mean: every one of the seven
  worst frames in the session was `State=CHASE, Active=true`.
- Control: round 2 had 19.6 % of frames over budget *before* any pump, with the
  Pool Slide dormant. Level 2 spikes are not automatically the Pool Slide's.
- **Not reached:** the enraged phase (pump 3). The map has exactly 3 pumps and
  `DevActivatePumpPair` needs two unstarted ones. Also unmeasured: chases longer
  than ~15 s (a solo player dies ~7 s after spawn), multi-player scaling, client
  frame time, per-function profiler attribution.

## What Part 2 adds

- Steady-state estimate ~0.5–2 % of one core, i.e. roughly two extra Pool Foam
  clones. Consistent with the measured +1.3 ms/frame.
- Worst single-frame risk: `candidates()` (Controller lines 206–231) is an
  unyielded raycast burst over every anchor × every player, estimated 6–13 ms,
  re-run on every spawn pass. Cheap fix: build the `RaycastParams` once per pass
  and yield every ~32 anchors.
- `StableRoutes = true` (Controller line 281) re-arms the shared Navigator's
  certification branches that the base's own comment declares dead since the old
  Pool Slide was deleted. The fork's 2 ms planning slice turns that from an FPS
  collapse into route latency, but the budgets are still sized in seconds.
- `Speed` is published as a per-frame float to both the state folder and the
  model: ~120 replicated attribute writes per second for nothing.
- **Publish blocker, not performance:** `StudioValidationMode` bypasses the
  `Level2_PoolSlideRigVerified` / `CorridorFitVerified` asserts only inside
  Studio. Both flags are false on the template, so on a real server `Start`
  returns nil and `Level 2 Round Adapter` throws — the whole Level 2 build fails.
  `Enabled = true` today. The console prints the warning once per round.

## Reading notes

- Line numbers in Part 2 match the byte-exact dump (LF line endings). Line
  numbers quoted in Part 1's prose are roughly doubled (that agent counted lines
  differently); trust Part 2's references.
- Raw samples: `live-samples.csv` in this session's scratchpad
  (`%LOCALAPPDATA%\Temp\claude\G--Roblox-MongoTV\93d4864d-0476-41ca-962a-eca04b3fc2fb\scratchpad\`),
  with the byte-exact script dump under `studio-dump\`.
- Studio was left in Edit mode with nothing modified or saved; `EntityPaused`
  cleared; the temporary `PoolSlideUsageLog` value destroyed; `HttpEnabled`
  restored to false after the dump.


---

# Part 1 — Live measurement (Opus 5 agent, Studio play session)

# Level 2 Pool Slide — live server frame-time measurement

Measured in Roblox Studio on 2026-09-09 against the live place
**BACKROOMS: STAY QUIET [CO-OP HORROR]** (placeId 131311258779917), studio
`6b585c88-8ef9-4fe1-b854-29dd70a03b57`. Single Studio player (`mikkelczar`,
userId 40920547), three consecutive Level 2 rounds in one play session.

Raw data: `live-samples.csv` — 1261 samples, one every 0.5 s, 35 columns,
covering 631 s of wall time. Every number below is computed from that file by
`analyze.py` / `extra.py` in the same directory. Nothing is estimated.

---

## 0. The entity exists and it works

The repository mirror does **not** contain the Pool Slide (`Level 2 Round
Adapter.ModuleScript.lua` line 389 still says *"The Pool Slide encounter was
removed on 2026-09-02"*). The **live place does**, and it is wired in and
enabled:

- `ServerScriptService."Level 2 Systems"` holds `Level 2 Pool Slide
  Configuration` / `Navigator` / `Rig Adapter` / `Controller` (controller
  35,774 B, navigator 126,975 B, 1517 lines in the controller).
- The live `Level 2 Round Adapter` requires the controller at line 33 and calls
  `PoolSlideController.Start(manifest, generation)` at line 784, guarded by
  `PoolSlideConfiguration.Enabled == true` at line 782.
- Live configuration: `Enabled=true`, `WalkSpeed=10`, `NormalRunSpeed=20`,
  `EnragedSpeed=32`, `AttackDamage=100`, `AttackCooldown=2.4`,
  `RunDistance=100`, **`StudioValidationMode=true`**.
- ServerStorage carries reinstall backups dated today
  (`PoolSlideInstallBackup_pipe-scale4-stage-20260909T0407Z`,
  `PoolSlideContextDiagnosticBackup_MP6..MP9_16xxZ`), i.e. another session
  reinstalled and iterated on it during 2026-09-09.

**The 2026-09-02 finding no longer holds.** On that date the entity never once
spawned and its retrying spawn cost 78 % of the frame budget. In all three
rounds measured today it spawned **on the first probe**, ~0.5 s after the second
pump, and the server never fell below a mean of 54 FPS in any phase.

---

## 1. Method

A `task.spawn` recorder was installed in the Server datamodel writing one CSV
line per 0.5 s into a temporary `ServerStorage.PoolSlideUsageLog` StringValue
(destroyed afterwards). Each line records `tick()` wall time, Heartbeat frames
counted over the interval (-> server FPS), `Stats.HeartbeatTimeMs`,
`Stats.PhysicsStepTimeMs`, `Stats.InstanceCount`, `Stats.MovingPrimitivesCount`,
`Stats.ContactsCount`, `Stats:GetTotalMemoryUsageMb()`, a free-text phase marker
and 23 live attributes (`Level2_PoolSlide*` from `ReplicatedStorage."Level 2
State"` and the runtime model, plus the workspace and pump attributes).

Rounds were driven with the documented playtest recipe: `DevFastQueue` +
`DevEspEnabled`, pivot onto the Level 2 launch pad, `Remotes.ConfigureQueue:
FireServer(5, 1, "public")`, then `Remotes.DevControl:FireServer("level2PumpPair",
true)` to start two pumps at once.

**Two measurement caveats to read the tables with:**

1. `Stats.HeartbeatTimeMs` is a *point sample* read once per 0.5 s, not a mean
   over the interval. The `fps` column (frames counted between samples) is the
   only true interval measure. A phase can therefore show a healthy mean FPS and
   still contain frames of 50 ms — see the `>16.7 ms` column.
2. In rounds 2 and 3 a keep-away watchdog repeatedly pivoted the player away from
   the entity (the only sanctioned way to keep a single-player round alive
   against a 100-damage attacker). That changes the entity's path lengths and is
   why the "moving" sample is 95 rows rather than a continuous minute.

---

## 2. Per-phase results

### 2.1 Clean windows (the numbers to quote)

| window | n | fps mean | fps min | hb mean ms | hb p95 ms | hb max ms | frames >16.7 ms |
|---|--:|--:|--:|--:|--:|--:|--:|
| Lobby (4 windows: INIT, LOBBY, LOBBY2, LOBBY_END) | 84 | 58.3 | 48.4 | 0.156 | 0.300 | 0.359 | 0 % |
| L2 round, pre-pumps, Pool Foam running, slide DORMANT (R1) | 50 | 58.0 | 45.7 | 1.102 | 1.512 | 2.006 | 0 % |
| `EntityPaused=true`, pre-spawn (R1) | 26 | 59.0 | 56.2 | 0.316 | 0.571 | 0.943 | 0 % |
| `EntityPaused=false`, pre-spawn, slide still inactive (R1) | 60 | 56.8 | 12.8 | 1.974 | 3.764 | 26.792 | 1.7 % |
| `EntityPaused=true`, post-spawn (R3) | 37 | 58.7 | 49.6 | 0.418 | 0.524 | 1.722 | 0 % |
| `EntityPaused=false`, post-spawn (R3) | 163 | 58.1 | 31.1 | 2.488 | 2.872 | 7.249 | 0 % |
| **Pool Slide active, unpaused, in round (all 3 rounds)** | **439** | **56.0** | **5.1** | **3.868** | **15.756** | **56.609** | **5.0 %** |
| ... of which `Moving=true` | 95 | 54.4 | 6.5 | 5.233 | 22.622 | 56.609 | 8.4 % |
| ... of which `State=CHASE` | 345 | 55.6 | 5.1 | 4.441 | 21.449 | 56.609 | 5.8 % |

### 2.2 Derived phases, all three rounds pooled

| phase | n | fps mean | fps min | fps max | hb mean | hb p95 | hb max | phys mean | phys max | instances | movPrims mean | movPrims max | contacts | mem MB |
|---|--:|--:|--:|--:|--:|--:|--:|--:|--:|--:|--:|--:|--:|--:|
| LOBBY | 397 | 56.6 | 3.6 | 61.8 | 1.127 | 1.611 | 25.345 | 0.073 | 2.223 | 367125 | 412.6 | 19113 | 17 | 3873 |
| WORLD_GENERATION | 9 | 39.5 | 9.1 | 61.8 | 7.915 | 18.944 | 18.944 | 0.899 | 1.536 | 433417 | 2383.9 | 8993 | 585 | 3905 |
| ROUND_IDLE (foam only) | 323 | 57.2 | 10.6 | 61.8 | 1.824 | 3.365 | 33.703 | 0.228 | 0.840 | 434344 | 37.9 | 141 | 395 | 3878 |
| ROUND_IDLE_PAUSED | 26 | 59.0 | 56.2 | 60.6 | 0.316 | 0.571 | 0.943 | 0.193 | 0.309 | 437344 | 24.6 | 39 | 342 | 3864 |
| SLIDE_ACTIVE_MOVING | 95 | 54.4 | 6.5 | 61.2 | 5.233 | 22.622 | 56.609 | 0.326 | 1.594 | 434712 | 70.1 | 304 | 563 | 3925 |
| SLIDE_ACTIVE_STATIONARY | 344 | 56.5 | 5.1 | 62.5 | 3.492 | 9.258 | 55.554 | 0.341 | 1.753 | 434271 | 37.1 | 284 | 497 | 3932 |
| SLIDE_ACTIVE_PAUSED | 37 | 58.7 | 49.6 | 60.9 | 0.418 | 0.524 | 1.722 | 0.183 | 0.367 | 435387 | 27.2 | 43 | 689 | 3942 |
| TEARDOWN/OTHER | 30 | 59.0 | 54.1 | 61.1 | 0.353 | 0.484 | 0.543 | 0.393 | 1.016 | 433514 | 12.0 | 47 | 709 | 3908 |

The pooled `LOBBY` row is contaminated by world teardown/rebuild bursts
(`movPrims` up to 19,113, `hb` up to 25.3 ms) because the world is destroyed
while `RoundActive` and `WorldGenerated` are already false. Section 2.1's
four-window lobby figure (0.156 ms, 0 % over budget) is the true idle baseline.

### 2.3 Marker windows, chronological (for the record)

| window | n | fps mean | hb mean | hb p95 | hb max | >16.7 ms |
|---|--:|--:|--:|--:|--:|--:|
| INIT | 13 | 58.9 | 0.131 | 0.184 | 0.336 | 0 % |
| LOBBY | 44 | 58.0 | 0.155 | 0.289 | 0.341 | 0 % |
| LAUNCHPAD (world build starts) | 23 | 50.6 | 3.425 | 19.672 | 20.581 | 8.7 % |
| GENERATING | 61 | 58.0 | 0.823 | 1.274 | 3.598 | 0 % |
| ROUND_PRE_PUMPS | 50 | 58.0 | 1.102 | 1.512 | 2.006 | 0 % |
| PAUSED_PRE_SPAWN | 26 | 59.0 | 0.316 | 0.571 | 0.943 | 0 % |
| UNPAUSED_PRE_SPAWN | 63 | 55.8 | 2.635 | 9.930 | 28.414 | 3.2 % |
| PUMPS2_PROBING (R1, slide live) | 83 | 57.5 | 1.472 | 3.161 | 25.345 | 2.4 % |
| ROUND1_ENDED | 123 | 58.1 | 0.211 | 0.375 | 0.454 | 0 % |
| LOBBY2 | 15 | 59.5 | 0.158 | 0.306 | 0.359 | 0 % |
| R2_LAUNCHPAD | 18 | 54.4 | 2.312 | 16.141 | 22.926 | 5.6 % |
| R2_GENERATING | 41 | 56.7 | 1.986 | 7.998 | 23.637 | 4.9 % |
| R2_ROUND_PRE_PUMPS | 56 | 52.0 | 6.583 | 28.580 | 33.703 | 19.6 % |
| R2_SLIDE_ACTIVE | 126 | 56.2 | 2.788 | 21.884 | 25.341 | 5.6 % |
| LOBBY3 | 23 | 53.5 | 2.864 | 21.824 | 23.871 | 8.7 % |
| R3_GENERATING | 27 | 56.0 | 2.170 | 17.638 | 21.689 | 7.4 % |
| R3_ROUND_PRE_PUMPS | 51 | 55.6 | 2.721 | 12.197 | 22.760 | 3.9 % |
| R3_SLIDE_ACTIVE | 62 | 54.8 | 5.276 | 22.622 | 56.609 | 6.5 % |
| PAUSED_POST_SPAWN | 37 | 58.7 | 0.418 | 0.524 | 1.722 | 0 % |
| UNPAUSED_POST_SPAWN | 163 | 58.1 | 2.488 | 2.872 | 7.249 | 0 % |
| SLIDE_CHASE_MOVING | 142 | 55.4 | 3.202 | 19.184 | 55.554 | 6.3 % |
| LOBBY_END | 12 | 57.3 | 0.182 | 0.264 | 0.266 | 0 % |

`R2_ROUND_PRE_PUMPS` is the important control: 19.6 % of frames over budget and
a 33.7 ms worst frame **with the Pool Slide dormant**. That window is world
settling / client streaming, not the entity. Spikes in a Level 2 round are not
automatically the Pool Slide's.

---

## 3. Derived deltas

All figures are differences of mean `Stats.HeartbeatTimeMs` between the windows
named, at 60 Hz where the whole frame budget is 16.67 ms.

| comparison | d hb mean | d hb p95 | d fps mean | reading |
|---|--:|--:|--:|---|
| L2 round idle (R1) - lobby | **+0.95 ms** | +1.21 | 0 | cost of a generated Level 2 world + Pool Foam, no slide |
| unpaused - paused, **pre**-spawn (R1) | **+0.79 ms** | +0.94 | -1.0 | **Pool Foam motion alone** (5 clones) |
| unpaused - paused, **post**-spawn (R3) | **+2.07 ms** | +2.35 | -0.6 | **Pool Foam + Pool Slide motion** |
| the difference of those two | **~ +1.28 ms** | ~ +1.4 | - | **the Pool Slide's own share ~ 1.3 ms/frame ~ 7.7 % of the 16.67 ms budget** |
| slide active & moving - round idle (pooled) | +3.41 ms | **+19.26 ms** | -2.8 | the same cost seen in the tail rather than the mean |
| slide active & stationary - round idle (pooled) | +1.67 ms | +5.89 | -0.7 | idling-but-spawned still costs ~1.7 ms |
| probing period - pre-pump idle | **0 ms - no probing period exists** | - | - | the spawn succeeded on probe 1 every time |

The two pause windows come from **different rounds** (pre-spawn from round 1,
post-spawn from round 3) because round 1 ended before a post-spawn pause could
be taken. Rounds differ in background load, so the 1.28 ms subtraction carries
that uncertainty. The within-round-3 figure that needs no cross-round
subtraction is **+2.07 ms for both entities together**, and it is the more
defensible number.

Instance and memory footprint of the model, measured at the sample where
`Level2_PoolSlideActive` flipped:

| round | instances before -> after | delta | memory delta |
|---|---|--:|--:|
| 1 | 437,371 -> 437,475 | **+104** | +0.4 MB |
| 2 | 427,776 -> 427,774 | -2 (model built inside a world-teardown sample) | +0.0 MB |
| 3 | 435,311 -> 435,417 | **+106** | +0.0 MB |

---

## 4. Spawn timeline

Attribute values are exactly as published; no error attribute was ever set.

| round | pump 1 | pump 2 | `Active=true` | latency | probes | navigator builds | spawn count |
|---|--:|--:|--:|--:|--:|--:|--:|
| 1 | t=138.045 | t=143.314 | t=143.314 (same 0.5 s sample) | < 0.5 s | 1 | 1 | 1 |
| 2 | t=310.076 | t=314.888 (`State=SPAWNING`) | t=315.453 | 0.565 s (direct in-Studio poll: **0.512 s**) | 1 | 1 | 1 |
| 3 | t=429.638 | t=434.871 | t=434.871 (same sample) | direct in-Studio poll: **0.516 s** | 1 | 1 | 1 |

- `Level2_PoolSlideSpawnProbeCount` never exceeded **1** in any of the 1261
  samples. `SPAWN_MAX_PROBES_PER_PASS` is 24 and `SPAWN_RETRY_SECONDS` is 5;
  neither the probe budget nor a single retry was ever needed.
- `Level2_PoolSlideSpawnNavigatorBuilds` never exceeded **1**.
- `Level2_PoolSlideNavigationContextReady` became `true` about **1 s after the
  world was handed over** (round 1: `WorldGenerated` at t~42.2, context ready at
  t=43.205) - i.e. long before the pumps, as designed.
- `Level2_PoolSlideNavigationContextMaxSlice` took three values across the three
  rounds: **0.0028472 s, 0.0038167 s, 0.004112 s**. Worst single builder slice
  measured: **4.1 ms** - under one frame.
- `Level2_PoolSlideLastError` was the empty string in **all 1261 samples**.
  `Level2_PoolSlideNavigationContextError` likewise.
- `Level2_PoolSlidePathStatus` only ever held `IDLE`, `MOVING`, `ARRIVED`.
- States observed: `DORMANT`, `SPAWNING`, `CHASE`, `ATTACK`, `IDLE`, `PAUSED`.
- Speeds observed while active (n=95 non-zero): min 9.99, mean 12.62, max 20.00
  - the walk (10) and run (20) tiers. `Level2_PoolSlideEnraged` was `false` in
  every sample.
- `Level2_PoolSlideAttackSerial` reached 1 in round 1: the entity closed and
  killed the single player **~7 s after spawning** (spawn t=143.3,
  `State=ATTACK` t=150.5, player health 0, round over at t=167.0).

### Console output (full, both reads)

The only Pool Slide line printed, once per round, three times in total:

> `[Level 2 Pool Slide] STUDIO VALIDATION ONLY: rig/fit acceptance flags are bypassed; do not publish`

No Pool Slide warning or error was printed. The other Level 2 lines seen were
`[Level 2] no recorded water regions; clearing the whole declared terrain block
as a recovery fallback` (twice per round) and, at boot,
`[EntityKill] Cinematic ground-pin knockout sequence active` and
`[TunnelLobbyBuilder] bays open: 1, 2, 3  |  launch stations: 12`.

That validation line comes from `Level 2 Pool Slide Controller` line 446:
`local validationOnly = Configuration.StudioValidationMode == true and
RunService:IsStudio()`. It bypasses exactly two asserts -
`Level2_PoolSlideRigVerified` and `Level2_PoolSlideCorridorFitVerified` (lines
448 and 452) - and sets a `ValidationOnly` session flag (line 1430). It does not
alter spawn probing, pathfinding or steering, so the frame-time numbers above
are not affected by it. It does mean **the rig/corridor acceptance flags have
never been set, and the entity would refuse to start outside Studio.**

---

## 5. Script Profiler

`game:GetService("ScriptProfilerService")` resolved.
`sps:ServerStart(1000)` returned **ok, no permission error**; `sps:ServerStop()`
likewise; both `SaveScriptProfilingData` and `OnNewData` are present on the
service. So the scripted profiler is usable in this Studio server datamodel.

**No per-function attribution was obtained**: the attempt was made after the
third round had already ended (the profiler was budgeted to two calls and the
round did not survive that long), so the captured window contains no Pool Slide
frames. Getting function-level attribution needs a fourth round with the
`OnNewData` connection made *before* `ServerStart`, inside the SLIDE_ACTIVE
window.

---

## 6. What could not be measured, and why

- **Enraged phase (pump 3, 32 studs/s).** Not reached; `Level2_PoolSlideEnraged`
  is `false` in all 1261 samples. The generated map had exactly **3 pumps**
  (`workspace.Level2PumpGoal = 3`, three `Level 2 Pump Prompt` instances).
  `ObjectiveController.DevActivatePumpPair` (line 1867) requires **two unstarted
  pumps** and returned `NEED_TWO_AVAILABLE_PUMPS` after the first pair, so the
  dev remote cannot reach pump 3 on a 3-pump map. The fallback - pivoting the
  player to the last pump and driving its ProximityPrompt from the client - was
  attempted once and failed because the round ended first. Reaching the enraged
  phase needs either a second player, or a map with >=4 pumps, or a client-side
  `InputHoldBegin` on the surviving prompt inside a surviving round.
- **A long, uninterrupted chase.** The longest continuous moving-chase window is
  the 15 s `SLIDE_CHASE_MOVING` block; only 95 samples in total have
  `Moving=true`. A single player is killed roughly 7 s after the spawn
  (round 1), so every longer window required teleporting the player away, which
  resets the path and biases path length downward. A two-player round, or a
  hostile-free harness, would give a cleaner sustained-load figure.
- **Per-function CPU attribution.** See section 5.
- **`ServerStorage.ZyntraReentry` as a round-extender.** 13 invocations from the
  watchdog in round 2 all returned from `pcall` without error, yet the round
  still ended. Whatever the bindable does, it did not keep a single-player round
  alive here. Not investigated further - it was a means, not the subject.
- **Client frame time.** Only the server datamodel was sampled.
- **Multi-player scaling.** One player. The controller refreshes targets every
  0.25 s and goals every 0.15 s per the constants at controller lines 53-57;
  with more players that work grows and none of it is measured here.
- **Production behaviour.** This is a Studio server with `StudioValidationMode`
  on and Studio's own overhead. Absolute milliseconds will differ on a real
  server; the *differences* between the paused and unpaused windows are the
  transferable part.
- **Round 2's `R2_ROUND_PRE_PUMPS` spikes** (19.6 % of frames over 16.7 ms with
  the slide dormant) were not traced to a cause. They are not the Pool Slide,
  and they are large enough to matter on their own.

---

## 7. Bottom line

The Pool Slide, as installed in the live place on 2026-09-09, **spawns reliably
on the first probe about half a second after the second pump**, never logs an
error, and costs roughly **1.3 ms of server frame time per frame on average
(~7.7 % of the 60 Hz budget)** on top of Pool Foam's 0.79 ms. Mean server FPS
with it hunting was **54.4**, against **58.3** in the lobby.

The cost that is worth attention is not the mean but the tail: with the entity
active and moving, **8.4 % of frames exceed the 16.67 ms budget**, p95 is
**22.6 ms** and the worst measured frame is **56.6 ms** - every one of the seven
worst frames in the session has `State=CHASE` and `Active=true`. Against that,
frames over budget are **0 %** in the lobby, **0 %** in a pre-pump Level 2 round,
and **0 %** while `EntityPaused=true`.

Studio was left as found: play stopped, Edit mode, `EntityPaused` cleared to
`nil`, `PoolSlideUsageLog` destroyed, dev attributes cleared, no script or world
object modified, nothing saved or published.


---

# Part 2 — Static cost analysis (Opus 5 agent, byte-exact Studio dump)

# Level 2 Pool Slide — static server cost analysis

Read-only analysis, 2026-09-09, by an Opus 5 agent over byte-exact copies of the Studio scripts. No measurements were taken; every number below is an **estimate** derived from the code, with the arithmetic shown. Nothing in Studio, the repo or the dump was modified.

## Headline summary

1. **This is not the 2026-09-02 disaster repeating.** Estimated steady-state cost: **~0.5–2 % of one core**, roughly 0.3–0.5× the five Pool Foam clones — not 78 % of the frame budget.
2. **The "bounded spawn probes" claim checks out**: ≤24 probes/pass, one `task.wait(.05)` each, **one** Navigator per pass (not per probe), ~1.3 ms per probe frame.
3. **The "context built once in task.defer" claim checks out** — `Controller:498` blocks any spawn before it exists, and it's reused by every retry.
4. **But `candidates()` is an unyielded ~6–13 ms raycast burst** (`Controller:206-231`) re-run on *every* retry pass — the worst single-frame risk left.
5. **The retry never gives up**: `FailedSpawnPasses` is never reset (`Controller:511/734`), so it's 30 s forever — ~42 passes and ~42 hitching frames in a failing 20-min round, but only ~0.1 % average CPU.
6. **Idle Heartbeat before pump 2 is genuinely free**: ~7 attribute reads/frame, no raycasts, no allocations (`Controller:657-672`).
7. **The rig adapter does NOT touch Bones or CFrames per frame** — `Play`/`Stop`/`AdjustSpeed` only, and `AdjustSpeed` is throttled to 10 Hz (`RigAdapter:123-127`).
8. **No yields inside Heartbeat, and `ComputeAsync` is never reached from one** — the fork's `task.spawn`→`task.defer` (`Nav(fork):1959`) fixed that; `planningCheckpoint` returns instantly on the walking thread.
9. **The fork's real win** is `PrepareContext`: it removes **three O(map) walks per `Navigator.new`** that Pool Foam still pays five times over.
10. **Its second win** is slicing planning to ~2 ms/frame vs the base's ~9 ms chunks — this converts a frame-rate catastrophe into a navigation-*latency* problem.
11. **But `StableRoutes = true` (`Controller:281`) re-arms the branches the base says are dead since the last Pool Slide was deleted** — budgets sized at 72 000 / 18 000 / 8192 units, i.e. **hundreds of ms to seconds of CPU per route**. Only the slicing and the 3 s deadline keep them honest.
12. **`ValidationOnly` changes nothing but two asserts and a flag** — the model still spawns into Workspace, chases, and deals 100 damage.
13. **Publish blocker (highest severity, not perf):** outside Studio the verification asserts fire → `Controller.Start` returns nil → `RoundAdapter:412` `error()` → **the whole Level 2 build fails**, and `Enabled = true` today.
14. **Cheapest fixes:** hoist `rayParams` out of `clearLine`; yield inside `candidates()`; stop publishing `Speed` at 60 Hz (120 replicated writes/s); cache `_refreshObstacleFilters` (~40 % off every placement, but it's shared with Pool Foam); don't `Navigator:Stop()` to start an attack (forces a full replan every 2.4 s in melee).
15. **Every number is an estimate** — no profiling was done, and `os.clock()` being CPU time in this datamodel may mean the 2 ms slice is really ~8 ms of wall time. That measurement should come before anything else.

## Files analysed

| Short name | Path |
|---|---|
| `Controller` | `scratchpad\studio-dump\Level 2 Pool Slide Controller.ModuleScript.lua` |
| `Nav(fork)` | `scratchpad\studio-dump\Level 2 Pool Slide Navigator.ModuleScript.lua` |
| `Nav(base)` | `G:\Roblox\MongoTV\ServerScriptService\Level 2 Systems\Level 2 Pool Foam Navigator.ModuleScript.lua` |
| `RigAdapter` | `scratchpad\studio-dump\Level 2 Pool Slide Rig Adapter.ModuleScript.lua` |
| `SlideConfig` | `scratchpad\studio-dump\Level 2 Pool Slide Configuration.ModuleScript.lua` |
| `RoundAdapter` | `scratchpad\studio-dump\Level 2 Round Adapter.ModuleScript.lua` |
| `FoamController` | `G:\Roblox\MongoTV\ServerScriptService\Level 2 Systems\Level 2 Pool Foam Controller.ModuleScript.lua` |
| `WorldBuilder` | `G:\Roblox\MongoTV\ServerScriptService\Level 2 Systems\Level 2 World Builder.ModuleScript.lua` |

`navigator.diff` reverse-applies cleanly onto `Nav(base)` (verified with `patch -R` + `diff -q`), so the fork is exactly `Nav(base)` + the 303-line diff. `Level 2 Configuration` in Studio is byte-identical to the repo copy.

---

## Cost unit and per-call assumptions (all ESTIMATE, unmeasured)

One **spatial op** = one `workspace:Raycast` / `:Blockcast` / `:GetPartBoundsInBox`. Order-of-magnitude figures used throughout:

| Operation | Assumed cost |
|---|---|
| Short filtered `Raycast` | ~3 µs |
| `Blockcast` / `GetPartBoundsInBox`, body box 9.8 × 8.7 × 9.8 | ~10 µs |
| `RaycastParams.new()` + one `FilterDescendantsInstances = {N items}` write | ~4 µs + 0.1 µs·N |
| `GetAttribute` | ~0.15 µs |
| replicated `SetAttribute` | ~1 µs + network |
| `Model:PivotTo` on a 3-part anchored model | ~5 µs |
| 60 Hz server frame budget | 16.7 ms |

Body volume comes from `Nav(base):568-573` with the Slide's `AgentRadius = 5`, `AgentHeight = 9` (`Controller:243`, template attributes): **9.8 × 8.7 × 9.8 studs** — roughly 4× the volume of the navigator's default 2.5/6 body.

### The one primitive that dominates everything: `_placeFoot`

`Nav(base):714-740` → `_surfaceAt` + `_clearAdvance` (`_bodyBoxClear` + `_bodySweepClear`).

| Component | Line | Engine work | Est. |
|---|---|---|---|
| `_surfaceAt` | `Nav(base):507-553` | 1–2 `Raycast` (Include-filtered to ground parts, so it seldom iterates its 16-cast loop) | ~6 µs |
| `_bodyBoxClear` | `Nav(base):581-593` | `_refreshObstacleFilters` + 1 `GetPartBoundsInBox` | ~30 µs |
| `_bodySweepClear` | `Nav(base):597-635` | `_refreshObstacleFilters` + 1–6 `Blockcast` | ~30–40 µs |
| `Model:PivotTo` (on success only) | `Nav(base):731` | 3 part CFrames | ~5 µs |
| **Total** | | **3–9 spatial ops** | **~70–80 µs** |

**About half of that is `_refreshObstacleFilters` (`Nav(base):498-505`), not raycasting.** It runs at the head of *both* `_bodyBoxClear` and `_bodySweepClear`, and each run does a `table.clone` of `BaseExclusions` plus **two** `FilterDescendantsInstances` writes. `BaseExclusions` contains every `Level2_BuoyantProp` in the map (`Nav(fork):430`, from `PrepareContext`); `WorldBuilder:4667-4676` marks them at four call sites inside per-hall loops, so tens to low hundreds per map. So this is O(#buoyant props) **per spatial predicate**. This is shared-base code — Pool Foam's five clones pay it too.

---

## 1. Per-phase cost model

### (a) Round start / navigation context build

`RoundAdapter:409-413` calls `PoolSlideController.Start(manifest, generation)` inside `Adapter.Build`'s `xpcall`. `SlideConfig:3` has `Enabled = true`, so this runs today.

| Work | Line | Frequency | Engine calls | Est. cost |
|---|---|---|---|---|
| `navigationTuning(template)` | `Controller:719` → `233-285` | once | `GetBoundingBox`, `GetPivot`, ~10 `GetAttribute`, 8-corner loop | < 0.1 ms |
| `collectAnchors` | `Controller:721` → `177-194` | once | `GetDescendants()` on `EntityNodes`, `EntityDen`, `Navigation` folders | 0.1–0.5 ms |
| runtime `Folder` creation | `Controller:723-726` | once | 1 `Instance.new`, 1 attribute | negligible |
| 2 signal connections | `Controller:756-759` | once | — | negligible |
| **`Navigator.PrepareContext`** | `Controller:740-751` → `Nav(fork):334-364` | once, deferred | **explicit-stack DFS over the whole generated world** | see below |

`PrepareContext` visits every instance under `manifest.World`. Per node (`Nav(fork):345-351`): `table.remove`, 1 `IsA`, `.CanCollide`, up to 2 `GetAttribute`, `.Name`, and **one `GetChildren()` array allocation**. Estimate 1–3 µs/node.

It slices at `sliceCount >= 1024 or elapsed >= .006` then `task.wait()` (`Nav(fork):355-358`). So the per-frame bound is real: **≤ 6 ms + one node**, which is **36 % of a 60 Hz frame**.

Arithmetic for an assumed world of N = 20 000–60 000 instances (unverified — see appendix):

```
Total CPU : 20 000 × 1 µs … 60 000 × 3 µs   = 20–180 ms
Slices    : ceil(N / 1024) ≈ 20–60, each ending in task.wait() = 1 frame
Wall time : 0.33–1.0 s at 60 fps, at ≤6 ms per affected frame
```

This lands *during* the Level 2 round-loading barrier, when world generation is already saturating the server. `MaxSlice` is published as `Level2_PoolSlideNavigationContextMaxSlice` (`Controller:749`), so the real number is observable at runtime without new instrumentation.

**Retained for the round:** `context.GroundParts` and `context.BuoyantProps` (`Nav(fork):338`) — O(map size) instance references, held until `activeSession` is dropped. Estimated tens of KB. Not a leak, but it means the floor filter is a **snapshot**: ground parts added or removed after the context is built are invisible to the navigator.

**Verdict on the "built once at Start in task.defer" claim: TRUE.** `Controller:498` (`if not session.NavigationContext then return end`) prevents any spawn attempt before it exists, and `Controller:391` asserts it at `Navigator.new`. It is built exactly once per session and reused by every retry pass.

### (b) Waiting for pump 2 — what the Heartbeat does per frame

`Controller:657-690`. Before `MaximumPumps >= SPAWN_PUMPS` the function reaches `Controller:672` (`if not session.Spawned then return end`) and stops.

| Work | Line | Per frame |
|---|---|---|
| `activeSession ~= session` | `658` | 1 comparison |
| `alive(session)` | `659` → `78-81` | 1 `.Parent` read + 1 `GetAttribute` |
| `roundReady(session)` | `660` → `83-87` | `alive()` **again** + 3 `workspace:GetAttribute` |
| `setPhase(session, pumpCount())` | `667` → `89-92`, `140-154` | 1 `GetAttribute`; early-returns when the phase is unchanged (`145`) |
| pump gate | `668` | comparison |

**Total: ~7 attribute reads + ~10 comparisons per frame. No raycasts, no allocations, no attribute writes, no scans.** Estimate 1–3 µs/frame → **0.06–0.18 ms/s ≈ 0.01 % of one core.** The idle claim holds.

One inefficiency: `alive()` is evaluated twice per frame (directly and inside `roundReady`). Irrelevant at this scale.

The *not-round-ready* branch (`Controller:661-663`) is slightly costlier: it calls `motion(..., "DORMANT", ...)` **every frame**, and `motion` (`127-138`) makes three `publish` calls, each of which does `stateFolder()` = `ReplicatedStorage:FindFirstChild` (`Controller:44-47`) plus a `GetAttribute` compare. So ~3 `FindFirstChild` + ~6 `GetAttribute` per frame, all write-guarded (`Controller:52`). ~5 µs/frame. Still trivial, but it is the pre-round and post-round steady state.

### (c) Spawn probing

Triggered from `Controller:668-671` once `workspace.Level2Pumps >= 2`, throttled by `requestSpawn` (`Controller:497-521`).

#### Per pass, in order

| Step | Line | Engine calls | Est. |
|---|---|---|---|
| `livingRecords` | `364` → `107-114` | O(P) × ~8 property/attribute reads | < 20 µs |
| **`candidates(session, records)`** | `364` → `206-231` | **A × P × (`rayParams` + 1 `Raycast`)**, plus A × `IsDescendantOf` | **see below** |
| `Template:Clone()` + descendant pass | `366-381` | ~105 descendants × 6 property writes | ~0.1 ms |
| `RigAdapter.PrepareModel` | `387` → `RigAdapter:28-65` | 2 × `model:GetDescendants()`, 2 Motor6D CFrame checks, ~105 property writes | ~0.1 ms |
| `navigationTuning(model)` | `388` → `233-285` | bounding box + 8 corners | < 0.1 ms |
| **`Navigator.new`** | `394` → `Nav(fork):366-535` | `model:GetDescendants()`, `buildHallIndex`, 3 × `RaycastParams`, 1 `OverlapParams`, **1 Include-filter write of the whole `GroundParts` array** | 0.1–0.6 ms |
| probe loop | `400-438` | ≤ 24 iterations, each after `task.wait(.05)` | see below |
| commit | `446-494` | reparent, 4 × `Animator:LoadAnimation`, 2 tags, ~18 attribute publishes | ~0.2 ms |

**`candidates()` is the single largest synchronous block in the whole feature.** `clearLine` (`Controller:171-175`) calls `rayParams(session)` (`Controller:156-169`) *on every call*, which allocates a fresh `RaycastParams` and a fresh exclusion table containing every player character. Anchor count A comes from `WorldBuilder:5857` (1 navigation node per hall) + `5867-5880` (4 patrol nodes per hall) + `5944-5952` (2 den spawns), with `MinimumHallCount = 16` and navigator comments citing 38 halls on seed 101:

```
A = 5 × halls + 2  →  82 (16 halls) … 192 (38 halls)
cost/call ≈ rayParams (4 µs + 0.1 µs × (4+P)) + Raycast (3 µs) ≈ 8 µs
A = 192, P = 4 : 192 × 4 × 8   µs ≈  6.1 ms
A = 192, P = 8 : 192 × 8 × 8.4 µs ≈ 12.9 ms
```

**Estimate 6–13 ms in one uninterrupted frame, with no `task.wait` anywhere inside `candidates()`.** That is 40–80 % of a 60 Hz frame, i.e. one visible hitch per spawn pass.

**Per probe iteration** (`Controller:409-437`), all synchronous between two `task.wait(.05)` calls:

| Sub-step | Line | Spatial ops | Est. |
|---|---|---|---|
| `resetPrivateSpawnProbe` | `409` → `324-334` | `Navigator:Stop()`, flag resets | ~2 µs |
| `WarpTo` | `417` → `Nav(base):742-746`, `714` | `_surfaceAt` + `_bodyBoxClear` (sweep skipped, `HasGrounded` false) | ~40 µs |
| `escapeClear` | `418` → `288-295` | 4 × `_clearAdvance` = 4 × (box + sweep) | ~240 µs |
| `localDepartureClear` | `420` → `342-358` | `_fallbackWaypoints` (graph BFS, pure Lua, or 1 `_clearDirectLine` raycast) + **one `_walkingEdgeClear` of ≤ 8 studs** | ~1.05 ms |
| re-validate participants | `428-435` | O(P) property reads | < 20 µs |

`_walkingEdgeClear` (`Nav(base):650-677`) splits the edge into `ceil(8 / MaxTravelStep) = ceil(8 / 0.6) = 14` pieces, each costing a full `_surfaceAt` + `_bodyBoxClear` + `_bodySweepClear` ≈ 75 µs → 14 × 75 µs ≈ 1.05 ms. **Worst case** (every `_surfaceAt` running its full 16-cast loop and every sweep exhausting its 6-exclusion budget) is 14 × 23 = 322 spatial ops ≈ 3 ms.

**Per probe ≈ 1.3 ms (worst ~3.5 ms), on ~24 frames spread over 24 × 0.05 = 1.2 s.** That is genuinely bounded: ~8 % of a 60 Hz frame on the probe frames, ~0 on the two frames between each.

**Per pass total (excluding the commit): ~7–17 ms of CPU, of which ~6–13 ms is the single `candidates()` spike, and ~24–35 ms is spread over 24 frames.**

#### What bounds it, and what happens if every probe fails all round

- Probes per pass: `math.min(SPAWN_MAX_PROBES_PER_PASS, #ranked)` = ≤ 24 (`Controller:400`). **Hard.**
- One `task.wait(SPAWN_PROBE_INTERVAL)` per candidate (`Controller:403`). **Hard.**
- One `Navigator` per pass, reused across all 24 probes (`Controller:394`, `409`). **Hard** — `SpawnNavigatorBuilds` (`Controller:396`) makes it observable.
- Retry backoff (`Controller:509-518`): `FailedSpawnPasses >= 3 → 30 s`, else 5 s.
- **`FailedSpawnPasses` is never reset** — initialised at `Controller:734`, only incremented at `511`. So the cadence is 5 s, 5 s, 5 s, then **30 s for the rest of the round, forever.**

Worst case, a 20-minute round in which no probe ever succeeds:

```
passes = 3 (at t+0, +5, +10) + floor((1200 - 10) / 30) ≈ 3 + 39 = 42
CPU    = 42 × ~30 ms ≈ 1.26 s over 1200 s  →  ~0.1 % average
spikes = 42 single frames of 6-13 ms (candidates) over 20 minutes
```

**Answer to the brief's question: yes, the retry is still unbounded in *time* — it never gives up and never backs off past 30 s — but it is no longer unbounded in *frame budget*. Estimated ~0.1 % average CPU plus ~42 hitching frames per 20-minute round, against the deleted Pool Slide's measured 78 %.** The structural fixes that buy this are (i) the `task.wait` per candidate, (ii) one Navigator per pass instead of per probe, (iii) `PreparedContext` removing three whole-world walks from `Navigator.new`, and (iv) `localDepartureClear`'s 8-stud local check replacing the whole-route certification whose 72 000-query budget is still sitting in `Nav(base):812`.

The cheap-fail path is genuinely cheap: if `candidates()` returns an empty list, the pass returns at `Controller:365` **before** the `Template:Clone()`, so a hopeless map costs only the `candidates()` spike every 30 s.

`session.SpawnCandidateCursor` (`Controller:399`, `405`) is an index into a list **rebuilt and re-sorted every pass** (`Controller:229`), so it does not reliably resume where the last pass stopped once players have moved. With A = 192 and 24 probes per pass, full coverage would need 8 passes ≈ 165 s even if the cursor worked perfectly.

### (d) Stalk / hunt / enraged movement

`Controller:584-630` (`updateModel`), called from the Heartbeat at `Controller:689`.

| Work | Line | Frequency | Engine calls | Est. cost/s at 60 fps |
|---|---|---|---|---|
| `updateAttack` early-out | `586` → `566-582` | per frame | — | < 0.1 ms/s |
| `chooseTarget` | `588` → `523-534` | **4 Hz** (`TARGET_REFRESH_SECONDS = .25`) | `livingRecords` = O(P) × ~8 reads + table allocs | < 0.1 ms/s |
| `livingRecord(target)` | `591` → `94-105` | per frame | `FindFirstChildOfClass` + `FindFirstChild` + ~6 attribute reads | ~0.3 ms/s |
| `beginAttack` × 2 | `599`, `619` → `551-564` | per frame | `attackReach` × 2; the `clearLine` raycast **short-circuits** and only fires inside 5.5 studs (`Controller:546-548`) | ~0.1 ms/s idle, +0.4 ms/s in melee |
| `SetGoal` | `610` → `Nav(fork):2247` | **6.67 Hz** (`GOAL_REFRESH_SECONDS = .15`) | `_positionAllowed` = O(#halls) `findHall`; then `_stableNeedsPath` gate | < 0.1 ms/s |
| **`Navigator:Step`** | `613` → `Nav(base):2212-2504` | per frame | 1–12 `_placeFoot` | **see below** |
| `GetDebugSnapshot` | `615` → `Nav(base):2765-2789` | per frame | pure Lua, one ~20-field table alloc | ~0.1 ms/s + GC |
| `motion` | `616` → `127-138` | per frame | 3 `publish`; **`Speed` changes every frame** | see below |
| `publish PathStatus` | `618` | per frame | write-guarded, changes rarely | negligible |
| watchdog | `620-629` | ≥ 3 s apart, cooldown 8 s | possibly one `SetGraphGoal(pos, true)` | negligible |

**`Step` substep count.** `Controller:605` clamps `dt` to ≤ 0.1. `Nav(base):2277`: `substeps = ceil(speed × dt / MaxTravelStep)` with `MaxTravelStep = 0.6` (`Controller:283`):

| speed | 60 fps (dt .0167) | 30 fps (dt .033) | 20 fps (dt .05) | dt clamp .1 |
|---|---|---|---|---|
| Walk 10 | 1 | 1 | 1 | 2 |
| Run 20 | 1 | 2 | 2 | 4 |
| **Enraged 32** | **1** | **2** | **3** | **6** |

So in the healthy case **one `_placeFoot` per frame ≈ 70–80 µs = 4.2–4.8 ms/s ≈ 0.3 % of a core.** `MAX_TRAVEL_SUBSTEPS = 12` (`Nav(base):54`) is a hard ceiling — the loop cannot spin.

**A blocked frame is the expensive one** (`Nav(base):2310-2500`): the steer ladder tries up to 3 angles × 2 signs = 6 `_placeFoot` (`2366-2388`), then a 0.45× short stride (`2396`), then `_clearanceSeekTarget` with up to 5 candidates each costing `_surfaceAt` + `_bodyBoxClear` + `_bodySweepClear` (`2194-2208`), then a waypoint-skip probe (`2439-2444`). **Up to ~12 full placements ≈ 0.9 ms in one frame ≈ 5 % of a 60 Hz frame.** Bounded by `MAX_CLEARANCE_SEEKS = 8`, `MAX_WAYPOINT_SKIPS = 6`, `ROUTE_ABANDON_FAILURES = 4`, `MAX_ROUTE_RETREATS = 5` (`Nav(base):59-70`), all of which refill only on real progress. Also ~7 × O(#corridors) pure-Lua `corridorCentreSeed` scans (`Nav(base):871-892`) per blocked frame — ~350 iterations, negligible.

**Path requests.** `_stableNeedsPath` (`Nav(base):1688-1707`) gates on `RepathInterval` = 0.75, or 0.45 when enraged (`Controller:151`), and `RepathDistance` = 6 / 4 (`Controller:152`). So **at most one request per 0.45–0.75 s**, and never two at once (`1698`), with a hung request cleared after `PathRequestTimeout = 3` (`1692-1697`, `Controller:281`).

`_requestPath` (`Nav(fork):1946-2220`) does, per request:

1. `PathfindingService:CreatePath` + `ComputeAsync` (`Nav(fork):1971-1979`) — engine cost, unmeasured.
2. `_centreRoute` (`Nav(base):1263-1556`) — thins to ≥ 9-stud spacing (`1289-1317`), then pass 1 moves every point to somewhere the body fits (`_centredWaypoint`, `Nav(base):951-1042` — analytic corridor centre, then up to 40 lateral tries, then up to 10 rings × 18 angles = 180 more), then pass 2 sweeps every segment. Each budget unit ≈ one `_standableAt` ≈ 36 µs.
   - normal chase route, 10–40 surviving points, 1–3 units each: **50–400 units ≈ 2–14 ms**
   - hard route needing `_clearanceDetour`: capped at `DETOUR_QUERY_CAP = 18 000` (`Nav(base):850`) → **~650 ms**
   - absolute route cap `CENTRING_QUERY_BUDGET = 72 000` (`Nav(base):812`) → **~2.6 s**
3. `_smoothStableRoute` (`Nav(base):1749-1772`) — stable-routes only, cap 8192 → **~295 ms**
4. `_reachablePrefix` (`Nav(base):1712-1742`) — stable-routes only, cap 4096 → **~147 ms**
5. `_joinStableRoute` → in the fork, `_certifiedJoin` (`Nav(fork):1958`, the base's old body) + `_shortAtomicJoin`. `_certifiedJoin` tries up to 16 candidates, each a `_walkingEdgeClear` over up to 128 studs = 213 pieces × 75 µs ≈ 16 ms → **worst case ~256 ms**; in practice it fails on the first piece for far candidates.

**The caps are sized in hundreds of milliseconds to seconds. What keeps them from being a frame-rate disaster is entirely the fork's slicing (§2) and the 3 s deadline.**

At 1.3–2.2 requests/s with a normal 2–14 ms certification: **3–30 ms/s ≈ 0.2–1.8 % of a core** for planning in steady chase.

**Attribute replication.** `motion` (`Controller:127-138`) publishes `State`, `Moving` and `Speed` every frame. `State` and `Moving` are write-guarded and rarely change, but `Speed` = `moved / dt` (`Controller:617`) is a float that changes on essentially every frame, and `publish` writes it to **both** the `Level 2 State` folder and the model (`Controller:52`, `59-61`). **~120 replicated attribute writes per second, to every client, for a value nothing needs at 60 Hz.**

**The animation driver does NOT move Bones or CFrames on the server per frame.** `RigAdapter.Attach` (`RigAdapter:67-165`) creates four `AnimationTrack`s via `Animator:LoadAnimation` on the server (`RigAdapter:87`); `driver:Motion` (`RigAdapter:107-128`) only calls `Play` / `Stop` / `AdjustSpeed`, and `AdjustSpeed` is throttled to 10 Hz with a 0.02 deadband (`RigAdapter:123-127`). The 20 Bones and 72 CFrameValues in the template are engine-side skinned-mesh data; the server Animator evaluates them each frame (estimated 10–50 µs/frame, engine cost, unverified). The only per-frame script-driven transform is `Model:PivotTo` inside `_placeFoot` (`Nav(base):731`), 1–12 times per frame.

### (e) Attack windup / hit / recovery

`Controller:551-582`. `AttackWindup = .5`, `AttackRecovery = .7`, `AttackCooldown = 2.4`, `AttackDamage = 100` (`SlideConfig:13-16`).

**This is the cheapest 1.2 s of the encounter.** `updateAttack` returns `true` while an attack is live, and `updateModel` returns immediately at `Controller:586` — **no `Step`, no target refresh, no goal refresh, no `motion` publishes.** Per frame during an attack: one `attackReach` (`536-549`), which costs a `livingRecord` plus, only inside 5.5 studs, one `rayParams` + one `Raycast`. Estimate ~15 µs/frame.

`beginAttack` itself (`Controller:551-564`) costs one `Navigator:Stop()`, one `Navigator:Face()` (a full `_placeFoot` ≈ 75 µs, `Nav(base):2554-2558`), a `driver:Attack` (4 track operations, `RigAdapter:129-139`), and 5 attribute publishes.

**But `Navigator:Stop()` (`Nav(base):2132-2152`) is heavy in consequence, not in cost:** it sets `Goal = nil`, empties `Waypoints`, **empties `Trail`** (destroying the retreat breadcrumbs), bumps `RequestId` (killing any in-flight plan) and clears the blocked binding. After the 1.2 s attack, `NextGoalRefresh` has long expired, so the next frame calls `SetGoal` with an empty route and a stale `LastPathAt` → **a full fresh path request plus a complete `_centreRoute` pass, on every single attack.** At the 2.4 s cooldown that is up to one extra full certification every 2.4 s while in melee — estimated **1–6 ms extra per attack**, and much worse on a route that needs a detour.

### (f) Stop / teardown

`Controller.Stop` (`Controller:692-704`), called by `RoundAdapter:256` and by the Heartbeat itself at `Controller:659` when the world dies.

| Work | Line | Cost |
|---|---|---|
| `activeSession = nil` (invalidates all deferred work first) | `694` | — |
| disconnect 2 connections | `696` | negligible |
| `setTarget(nil)` — clears the player's `Level2_PoolSlideChased` | `697` | 1 attribute write |
| `discardPending` | `698` → `297-307` | destroys pending driver/navigator/model |
| `Driver:Destroy` | `699` → `RigAdapter:148-158` | 4 × `Stop` + 4 × `Destroy` (both pcall'd, `RigAdapter:19-20`), 1 signal disconnect |
| `Navigator:Destroy` | `700` → `Nav(base):2791-2803` | `Stop()` → `_clearBlocked()` disconnects the `Path.Blocked` connection (`1585-1591`) |
| `RuntimeFolder:Destroy` | `701` | fires `model.Destroying` → `driver:Destroy` again, idempotent (`RigAdapter:149`) |
| `resetPublished` | `703` → `64-76` | 27 suffixes × (`FindFirstChild` + `GetAttribute` + `SetAttribute`) |

Estimated **< 1 ms total**, one-off.

**Everything I could find is cleaned:**

- Both signal connections are in `session.Connections` and disconnected (`696`).
- The navigator's `Path.Blocked` connection is disconnected via `Stop()` → `_clearBlocked`.
- The rig adapter's `model.Destroying` connection is disconnected in `Destroy` (`RigAdapter:151-155`).
- In-flight planning coroutines bail at their next `self.Destroyed` guard (`Nav(fork):1962`, `1982`, `2124`, and `planningCheckpoint` at `Nav(fork):324`).
- An in-flight `PrepareContext` checks `cancelled()` — i.e. `not alive(session)` — at the top of **every node** (`Nav(fork):343`), so it stops within one instance.
- An in-flight spawn pass returns "spawn cancelled" at `Controller:404` on its next iteration, before touching the model `discardPending` already destroyed.
- `planningThreads` is weak-keyed (`Nav(fork):320`) and explicitly cleared (`Nav(fork):2213`), including on error and timeout.

**Not cleaned, harmlessly:** `session.NavigationContext` keeps references to destroyed world instances until the session table itself is collected. `workspace:GetAttribute("Level2_PoolSlideActive")` is reset by `resetPublished` → `publish(nil, "Active", false)` (`Controller:55-57`), which the client sound controller reads (`Level 2 Sound Controller.LocalScript.lua:524`, `626`).

---

## 2. The Navigator fork

`navigator.diff` is 303 lines against a 2805-line base. It is **not** a rewrite of movement; it is four changes, three of which reduce cost.

### What changed

| Change | Diff | Effect on cost |
|---|---|---|
| **`Navigator.PrepareContext`** (new) | `Nav(fork):334-364` | **Removes O(map) work from `Navigator.new`.** The base does `manifest.World:FindFirstChild("Level 2 Navigation", true)` (recursive) at `Nav(base):357` plus **two** full `manifest.World:GetDescendants()` walks at `365-367` and `378-385`. The fork replaces all three with `queryContext.NavigationFolder` / `.BuoyantProps` / `.GroundParts` (`Nav(fork):412`, `420`, `430`). Estimated **3 × O(N) walks removed per `Navigator.new`**, i.e. per spawn pass. |
| **`planningCheckpoint`** at the head of `_surfaceAt`, `_bodyBoxClear`, `_bodySweepClear` | `Nav(fork):321-333`, `553`, `628`, `645` | **Bounds planning to ~2 ms of CPU per frame.** Base yields every `CENTRING_YIELD_EVERY = 600` predicates (`Nav(base):816`, `1319-1326`) — at ~36 µs per unit that is ~9 ms, over half a 60 Hz frame. |
| **`task.spawn` → `task.defer`** for the request thread | `Nav(fork):1959` | The planning body no longer executes *inside* the Heartbeat callback that called `SetGoal`/`Step`. In the base, `task.spawn` runs synchronously up to the first `ComputeAsync` yield. |
| **Ownership re-validation after every newly-yielding predicate** + `xpcall` wrapper | `Nav(fork):2124-2127`, `2161-2175`, `2180-2181`, `2212-2218` | Correctness, not cost. Necessary *because* the predicates can now yield. |
| `_joinStableRoute` split into `_certifiedJoin` (yielding) + `_shortAtomicJoin` (≤ 8 studs, `Atomic = true`, non-yielding) | `Nav(fork):1824-1921` | Neutral-to-positive. `Atomic` disables the checkpoint (`Nav(fork):323`), so the final commit cannot be torn — bounded to ~14 pieces ≈ 42 predicates ≈ 1 ms in one frame. |
| `stable and requestStart or self.FootPosition` at 6 call sites | `Nav(fork):1979`, `1988`, `1996`, `2000`, `2022`, `2059` | No cost change (Pool Slide is `StableRoutes = true`, so every one takes `requestStart`). |
| `if force ~= true` → `if self.Tuning.StableRoutes and force ~= true` in `SetGoal`/`SetGraphGoal` + new throttle blocks | `Nav(fork):2225`, `2232-2235`, `2238-2248`, `2255`, `2264-2267`, `2270-2276` | **Inert for the Pool Slide** — `StableRoutes` is true, so both take the original `_stableNeedsPath` branch. |
| The non-stable `else` branch of `_requestPath` deleted | diff `2060,2078d2196` | The fork is stable-routes-only; a `StableRoutes = false` fork navigator would never set `GoalApproach` / `InstalledGoal`. Not a drop-in replacement. |

**No change adds per-frame cost.** `planningCheckpoint` adds one weak-table lookup per spatial predicate on the walking thread (`Nav(fork):322`, returns `true` immediately because the Heartbeat thread is never registered) — sub-microsecond.

### One Pool Slide agent vs five Pool Foam clones on the shared base

| | Pool Slide (1 agent) | Pool Foam (5 clones) |
|---|---|---|
| `Navigator.new` world scans | **0** — `PreparedContext` (`Nav(fork):373-377`) | **3 × O(map) per clone × 5** (`Nav(base):357`, `365-367`, `378-385`), and again on every `refreshTemplate` replacement (`FoamController:1280`) |
| One-off O(map) walk | 1 cooperative DFS at Start (`Nav(fork):342-359`) | none (paid inline, 5×, non-cooperatively) |
| Retained O(map) memory | `GroundParts` + `BuoyantProps`, one copy shared | each clone builds its own `groundParts` array |
| `Step` per Heartbeat | 1 (`Controller:613`) | **5** (`FoamController:1357`) |
| `SetGoal` cadence | 6.67 Hz (`GOAL_REFRESH_SECONDS = .15`) | 10 Hz per clone (`FoamController:1167`) |
| Extra think tick | none | 10 Hz hearing + observation + proximity latch, per clone (`FoamController:1344-1356`) |
| Body box | 9.8 × 8.7 × 9.8 | default 4.8 × 5.7 × 4.8 (config not in repo) |
| `MaxTravelStep` | 0.6 (`Controller:283`) — 1.5× the placements per stud | default 0.9 (`Nav(base):26`) |
| `StableRoutes` | **true** (`Controller:281`) | **false** (`Nav(base):410-415`) |
| Planning slice | ~2 ms (`Nav(fork):326`) | ~600 predicates ≈ 9 ms (`Nav(base):816`) |

**The `StableRoutes = true` decision is the single biggest cost difference.** The base's own comment at `Nav(base):410-415` says the flag "is now always false and every StableRoutes branch below takes its else path — which is Pool Foam's own tested behaviour", and that its only user was the Pool Slide removed on 2026-09-02. Turning it back on re-activates, on every route install: `_reachablePrefix` (cap 4096), `_smoothStableRoute` (cap 8192), `_certifiedJoin` (up to 16 × a 128-stud `_walkingEdgeClear`), and the `fullyCertified` graph-route retry at `Nav(base):1938-1955` which can run `_centreRoute` a **second** time on the same request. **These branches have not executed in production since 2026-09-02 and are exactly the code the deleted Pool Slide was killed for.**

Everything O(map size) or O(player count) in the shared base:

- `_refreshObstacleFilters` (`Nav(base):498-505`) — O(#players + #buoyant props), **twice per spatial predicate**. Hottest inner loop in either entity.
- `findHall` (`Nav(base):182-208`) — O(#halls), called by `_positionAllowed` on every `SetGoal` and every centred candidate.
- `corridorCentreSeed` / `corridorContaining` (`Nav(base):871-915`) — O(#corridors), ~7× per blocked `Step` frame.
- `graphRoute` (`Nav(base):233-314`) — BFS over the hall graph, per fallback.
- `Trail` capped at `TRAIL_LIMIT = 48` (`Nav(base):711`). **No table grows unbounded for the round in either entity** — checked `Waypoints` (replaced per install), `sweepFilter` (≤ 6, discarded), `context.GroundParts`/`BuoyantProps` (fixed after build), `session.Connections` (fixed at 2), `planningThreads` (weak + explicitly cleared).

---

## 3. Worst-case paths, ranked by frame-time risk

**1. `candidates()` — an unyielded A × P raycast burst, once per spawn pass.** `Controller:206-231`, with `rayParams` rebuilt per call at `Controller:171-174`. Estimated **6–13 ms in one frame** (A = 192, P = 4–8), repeated on every retry pass — up to ~42 times in a failing 20-minute round. Highest single-frame risk in the feature.

**2. `StableRoutes = true` re-arms the certification budgets that killed the last Pool Slide.** `Controller:281` against `Nav(base):410-415`. Ceilings reachable once per 0.45–0.75 s: `CENTRING_QUERY_BUDGET` 72 000 ≈ 2.6 s of CPU (`Nav(base):812`), `DETOUR_QUERY_CAP` 18 000 ≈ 650 ms (`850`), `_smoothStableRoute` 8192 ≈ 295 ms (`1752`), `_certifiedJoin` 16 × 128-stud edges ≈ 256 ms (`Nav(fork):1832-1841`). **The fork converts this from a frame-rate catastrophe into a navigation-latency problem**: the 2 ms slice means a 650 ms certification takes ~325 frames ≈ 5.4 s of wall clock and the entity simply does not get a new route, rather than the server dropping to 13 FPS. That is a real fix, but it is *mitigation*, not removal — the budgets are still sized in seconds.

**3. `PrepareContext`'s 6 ms slices during round load.** `Nav(fork):355`. 36 % of a 60 Hz frame for an estimated 20–60 consecutive frames, landing inside the round-loading barrier while the world builder is also running.

**4. `_refreshObstacleFilters` twice per spatial predicate.** `Nav(base):498-505`, called from `582` and `598`. Estimated ~50 % of every `_placeFoot`, O(#buoyant props). Shared with Pool Foam's five clones, so fixing it helps both — and therefore needs the owner's sign-off because it touches production code.

**5. Two planner threads can overlap.** `_stableNeedsPath` bumps `RequestId` and clears `Computing` after `PathRequestTimeout` (`Nav(base):1692-1697`), letting a new request start while the orphan is still resident. The orphan only notices at its next `planningCheckpoint`, so for a short window **two threads each take a 2 ms slice → ~4 ms per frame**. Bounded and self-healing.

**6. Retry never gives up.** `FailedSpawnPasses` (`Controller:511`, `734`) is never reset, so after three failures the pass repeats every 30 s for the whole round even on a map with no qualifying anchor.

**7. Every attack forces a full replan.** `beginAttack` → `Navigator:Stop()` (`Controller:557`, `Nav(base):2132-2152`) wipes `Waypoints`, `Goal` and `Trail`. Up to one extra full `_centreRoute` per 2.4 s in melee.

**8. 120 replicated attribute writes/second.** `Controller:130-131` publishing a per-frame float `Speed` to both the state folder and the model.

**9. Heartbeat error resilience.** `Controller:756` connects `heartbeat` with no `pcall`. A Roblox signal connection whose handler errors is **not** disconnected, so any throw inside `updateModel` would repeat every frame with a full traceback. I found no reachable throw — `driver:Motion`'s asserts (`RigAdapter:109-111`) are satisfied by construction (`speed = moved/dt` with `dt` clamped to (0, .1] at `Controller:605`), the animation names are a closed set, `session.Navigator` is nil-guarded at `Controller:673`, and `attack.Record.Humanoid` is re-validated by `attackReach` before `TakeDamage` (`Controller:571-574`). But there is no backstop if a future edit introduces one.

**Checks that came back clean:**

- **No yields inside a Heartbeat callback.** `Step` never yields: `planningCheckpoint` returns `true` immediately on any thread not registered in `planningThreads` (`Nav(fork):322-323`), and the Heartbeat thread is never registered. `requestSpawn` defers (`Controller:500`) and `_requestPath` defers (`Nav(fork):1959`).
- **`ComputeAsync` is never called from a Heartbeat callback.** It sits inside the `task.defer`'d `runRequest` (`Nav(fork):1979`). It *is* still on the main thread in the same frame's deferred phase, but not inside the Heartbeat handler. In the base it would have been, via `task.spawn`.
- **No connection leaks in `Stop`** (see §1f).
- **No table grows for the whole round** (see §2).
- **The spawn thread has exactly one yield point**, `task.wait(SPAWN_PROBE_INTERVAL)` at `Controller:403`, and all pending-ownership fields are set before it (`Controller:395`, `397`), so `Stop` can never orphan a half-built model.

**Not a frame-time issue but the highest-severity finding: this cannot be published as-is.** `navigationTuning` (`Controller:234-238`) bypasses the `Level2_PoolSlideRigVerified` and `Level2_PoolSlideCorridorFitVerified` asserts only when `Configuration.StudioValidationMode == true` **and** `RunService:IsStudio()`. Both template attributes are `false` (`Level 2 Pool Slide Template.summary.txt:5`, `:8`). In a published server `IsStudio()` is false, so both asserts fire → `Controller.Start` returns nil at `Controller:720` → `RoundAdapter:412` calls `error(...)` → **the entire Level 2 build fails**, not just the entity. `SlideConfig:3` has `Enabled = true`, so this is armed today.

**What `ValidationOnly` actually changes at runtime: nothing except those two asserts and a published flag.** It is read at `Controller:234` (assert bypass), `735` (session flag), and `474`/`753`/`754` (publish + warn). **The model is still parented to `session.RuntimeFolder` inside `manifest.World` in Workspace (`Controller:447`, `726`), is tagged `Level2HostileEntity` (`459`), moves, chases, and deals 100 damage.** There is no "inspect-only" behaviour — clients see and can be killed by it exactly as in a normal run.

---

## 4. Comparison and recommended changes

### Pool Slide vs Pool Foam, steady state

| | Pool Slide × 1 | Pool Foam × 5 |
|---|---|---|
| `_placeFoot` per frame | 1 (2–6 when enraged at low fps) | 5 (each ~4× smaller body, 1.5× coarser step) |
| Est. movement CPU | ~4.5 ms/s | ~15–25 ms/s |
| Planning | 1.3–2.2 requests/s, stable-routes path | 5 agents × up to 1.4 requests/s, non-stable path |
| Est. planning CPU (normal) | 3–30 ms/s | 10–60 ms/s |
| **Est. steady-state total** | **~0.5–2 % of a core** | **~2–5 % of a core** |
| Worst-case single frame | ~13 ms (`candidates()`) | ~9 ms (a 600-predicate centring chunk, `Nav(base):816`) |
| Worst-case sustained | 2 ms/frame planning slice, up to 2× on thread overlap | 9 ms/frame chunks, no slicing |

**Estimate: one Pool Slide costs roughly 0.3–0.5× the five Pool Foam clones in steady state.** The 5× agent-count advantage is largely eaten by the Slide's ~4× body volume, its 1.5× finer `MaxTravelStep`, and `StableRoutes = true`. It is *not* a 78 %-of-frame-budget entity like its predecessor — on the code as written, its steady state is comparable to adding roughly two more Pool Foam clones.

### The 5 cheapest changes, best value first

**1. Build the `RaycastParams` once per `candidates()` pass instead of once per anchor.** `Controller:156-169` / `171-175` / `206-231`. Hoist it above the anchor loop and pass it in. Estimated **50–70 % off the 6–13 ms spike**, ~5 lines.

**2. Yield inside `candidates()`.** Same block. It already runs in a deferred thread (`Controller:503`), and `spawnAllowed` is re-checked immediately after (`Controller:404`), so a `task.wait()` every ~32 anchors is safe. Turns the remaining ~3 ms spike into ~6 frames of ~0.5 ms. ~2 lines.

**3. Stop publishing `Speed` at 60 Hz.** `Controller:130-131`, fed from `Controller:617`. Quantise (`math.round(speed * 4) / 4`) or gate on a 10 Hz timer. Removes ~120 replicated attribute writes/s with zero visible change. ~1 line.

**4. Cache the obstacle filter instead of rebuilding it twice per spatial predicate.** `Nav(base):498-505`, called from `582` and `598`. Rebuild only on `PlayerAdded` / `PlayerRemoving` / `CharacterAdded`. Estimated **~40 % off every `_placeFoot`, `_walkingEdgeClear` piece and centring predicate** — the largest steady-state win available. **Caveat: shared base code, so it changes production Pool Foam and needs an explicit decision plus a Level 2 traversal re-measurement.**

**5. Don't call `Navigator:Stop()` to start an attack.** `Controller:557`. Setting `session.CurrentSpeed = 0` and skipping `Step` for the attack window keeps the route, goal and trail, removing one full path request + centring pass per attack. `Navigator:Face()` alone already does the facing.

**Also worth doing, lower value:** lower `PrepareContext`'s slice from 6 ms to 2–3 ms (`Nav(fork):355`); and decide deliberately whether `StableRoutes` must be `true` (`Controller:281`) — turning it off would drop `_reachablePrefix`, `_smoothStableRoute` and `_certifiedJoin` from every install, but the fork's deleted non-stable `else` branch (diff `2060,2078d2196`) means that is **not** currently a one-flag change.

**Is any of this warranted before shipping?** Items 1–3 are small, local and free of behavioural risk. Item 5 is a behaviour change worth a playtest. Item 4 is the biggest win and the biggest blast radius. None of them is the blocker — the blocker is the `StudioValidationMode` / verification-flag issue in §3, plus the absence of a test suite, which is the same gap that let the previous Pool Slide fail silently for days.

---

## 5. Verification appendix — assumptions I could not confirm from code

**Cost constants.** Every microsecond figure is an order-of-magnitude assumption; no profiling was done. `Raycast` ≈ 3 µs, `Blockcast`/`GetPartBoundsInBox` on a 9.8³ box ≈ 10 µs, `RaycastParams` construction + filter write ≈ 4 µs + 0.1 µs/entry, `PivotTo` ≈ 5 µs, `GetAttribute` ≈ 0.15 µs. **If any is off by 5×, every derived number moves with it.** A `debug.profilebegin` pass around `_placeFoot` and `candidates()` would settle the whole report.

**World size.** `PrepareContext`'s cost is linear in the generated world's instance count, estimated at 20 000–60 000 with no evidence. The runtime already publishes `Level2_PoolSlideNavigationContextMaxSlice` (`Controller:749`) and the context carries `Visited` / `Slices` / `Elapsed` (`Nav(fork):339`, `361`) — read them instead of trusting my range.

**Anchor count.** A = 5 × halls + 2 comes from `WorldBuilder:5857`, `5867-5880`, `5944-5952` plus `MinimumHallCount = 16`; the 38-hall figure is from a comment in `Nav(base):1964`, not a measurement of a current seed.

**Buoyant prop count.** Four `makeBuoyant` call sites (`WorldBuilder:4772`, `4784`, `5357`, `5366`), all inside loops whose iteration counts I did not trace. This drives `_refreshObstacleFilters`, which I claim is ~half of every `_placeFoot`.

**Ground-part count.** Drives the `FilterDescendantsInstances` Include write in `Navigator.new`. 20 `Level2_EntityGround` assignment sites in `WorldBuilder`; total count unknown.

**`PathfindingService:ComputeAsync` main-thread cost** on a Level 2 nav mesh — not modelled at all. The one engine call whose cost I have no basis to estimate.

**Pool Foam's tuning is not in the repo.** `session.Configuration.Movement` (`FoamController:463`) comes from a Studio `Configuration` instance. §4 assumes `Nav(base):13-27` DEFAULTS for `MaxTravelStep` (0.9), `AgentRadius` (2.5) and `AgentHeight` (6), and `UpdateInterval` 0.1 / `PathRequestTimeout` 8 from the `numberOr` fallbacks at `FoamController:1167` and `1219`.

**`os.clock()` is CPU time, not wall time** in this project's server datamodel (project memory `roblox-studio-osclock-cpu-time`). Every deadline in both controller and navigator uses it: `PATH_REQUEST_TIMEOUT`, `WATCHDOG_SECONDS`, `WATCHDOG_COOLDOWN`, `SPAWN_RETRY_SECONDS`, `AttackWindup`/`Recovery`/`Cooldown` (`Controller:585`), the `planningCheckpoint` 2 ms slice (`Nav(fork):326`) and the `PrepareContext` 6 ms slice (`Nav(fork):355`). If `os.clock` runs ~4× slower than wall time as the memory note records, **the 2 ms slice is really ~8 ms of wall time (half a frame), the 3 s planning deadline is ~12 s, and the 0.5 s attack windup is ~2 s.** Inherited convention — Pool Foam does the same (`FoamController:1316`) — not a Pool Slide regression, but it undermines the slicing guarantee that is this fork's main safety property. **Worth one measurement before anything else here.**

**Whether any probe ever succeeds.** I verified the probe loop is bounded; I could not verify it ever produces a spawn. The previous Pool Slide's fatal flaw was a 0 % spawn rate, and the two paths that would reproduce it — `candidates()` returning empty (`Controller:365`) and `localDepartureClear` failing on all 24 (`Controller:439`) — are both still reachable. `SpawnProbeCount` and `FailedSpawnPasses` are published (`Controller:411`, `773`); a single playtest reading them answers this.

**Rig geometry asserts.** `navigationTuning` requires `radius >= max(staticRadius, animatedRadius) + .1` and `height >= max(staticHeight, animatedHeight) + .3` (`Controller:274-277`). From the template summary: `AgentRadius = 5` vs `AnimatedEnvelopeRadius = 4.82` → 4.92 ≤ 5 ✓; `AgentHeight = 9` vs `AnimatedEnvelopeHeight = 8.61` → 8.91 ≤ 9 ✓ (margin 0.09). The **static** radius and height depend on mesh offsets from the pivot, which the summary does not give, so I cannot confirm those pass. Nor can I confirm `GroundOffset = 4` matches the measured pivot-to-sole within 0.12 (`Controller:270`).

**Animation assets.** `RigAdapter:84` validates only the `rbxassetid://<digits>` *format*. Whether the four clips exist, are published under the right owner, and load without a stall is unverified. `Animator:LoadAnimation` on the server for a 20-bone skinned rig may have a first-load cost I have not modelled.

**Server-side skinned-mesh evaluation.** The 20 Bones are animated by the server Animator (`RigAdapter:68` asserts server). Estimated 10–50 µs/frame; engine cost I have no basis to quantify, and the one per-frame cost *not* visible in the Lua.

**Stale floor filter.** `PrepareContext` snapshots `GroundParts` once. If anything in Level 2 adds, removes or re-attributes a `Level2_EntityGround` part mid-round (doors, the pump sequence, the exit), the Include filter goes stale and destroyed parts stay referenced. I found no such site but did not audit the whole world builder or objective controller for it.

**Client scripts.** `Level 2 Pool Slide Dev ESP.LocalScript.lua` has **no** `FireServer`, `InvokeServer`, `RunService` loop or raycast — three signal connections plus a 4 Hz `task.wait(.25)` loop (`:207-219`) creating client-local `BillboardGui`/`Highlight` instances. `Level 2 Sound Controller.LocalScript.lua` only *reads* the published `Level2_PoolSlideActive` attribute (`:524`, `:626`) and sets attributes on its own client-created instances. **Neither causes any server work.** Verified by grep, not by reading them in full.
