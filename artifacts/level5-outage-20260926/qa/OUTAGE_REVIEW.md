# Level 5 outage review — 2026-09-26

Read-only review of the task's final shared logic, server outage controller and revised client Lighting controller. This reviewer did not access Studio, change product sources during this review, or claim a native release result. Use the final native QA/publication receipts for delivery status.

## Confirmed local test coverage

`tests/test_level5_outage_logic.luau` passed **346,385 assertions** using the standalone Luau CLI. Its require paths support both the task layout and a committed `artifacts/<release>/tests` layout.

The pure checks cover all seven gate origins and eight section ranks, deterministic forward-before-backward wave ordering, normalized fixture output, one dim reflash on the standard path, monotonic reduced/unknown-preference shutdown, exact five-second cascade, sixty-second full-dark hold, 1.5-second recovery, malformed schedules and timing inputs, immutable overlap updates and recovery interruption. Overlap preserves the original start/gate/blackout time and extends the dark hold; a gate opened during recovery returns directly to black rather than restarting at full brightness. A new wave starts only after the old cycle has fully returned to NORMAL.

These assertions exercise pure timing/math. They do **not** execute Roblox Instances, actual server gate authorization, JSON replication, client rendering or multiplayer synchronization.

## Code-reviewed integration boundaries

- The server annotates only `FluorescentPanel`, `SuspendedSharedFluorescent`, `SharedLowDomesticPanel` and `LastFluorescent` beneath the actual `Level5_IndoorSuburbs` architecture. Every fixture belongs to one of the eight manifest models. Stable spatial/name ordering produces normalized per-section order. The server never changes fixture Material/Color or Light.Enabled/Brightness.
- A trigger requires the current live world, active Level 5 round, a gate index from 1–7 and the actual gate's `FullyOpen=true`. Successfully triggered gate indices are remembered per world. No client-accessible trigger remote was added. Duplicate-start, schedule ownership, cleanup and attribute-restoration paths were inspected; this is code review, not a separate server fault-injection test.
- The existing Level 5 client remains the single Lighting owner. It snapshots fixture Material/Color and child Light.Enabled/Brightness, keeps originally Off/FailedTube fixtures unchanged, registers streamed fixtures and later-arriving Light children, and restores originals on detach. The actual streamed timing and replication order still require native evidence.
- Client cleanup now disconnects tracked top-level listeners, world listeners, state listener and its heartbeat. A stopped flag prevents queued deferred sync from reattaching after script destruction. The accessibility clamp uses the wave's `startedAt`, so an overlap serial increment does not restart its reduced-power history.
- The native-discovered `Color3 * number` error is corrected in the reviewed source with an explicit RGB scaling helper. Numeric brightness/atmosphere values still use ordinary multiplication. Review found no remaining material correctness issue in these final files; native validation remains authoritative for runtime behavior.

## Evidence to retain from native QA

Retain a full production-duration run showing the actual gate trigger, different fixture shutdown times, all ceiling fixture types dark after the cascade, the uninterrupted sixty-second hold, and restoration of originally On/Dim/Off fixtures. Include the original-vs-restored property comparison, overlap extension and fresh-round/exit cleanup where exercised. Identify any developer-assisted staging clearly.

Do not infer two-account synchronization, physical mobile performance, every streaming-arrival race, or server fault-injection coverage from the pure assertion count or a single-player native run. The declared boundaries are local logic tests plus the source review above; final native results must be reported separately.
