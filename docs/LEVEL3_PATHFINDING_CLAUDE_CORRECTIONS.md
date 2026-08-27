# Level 3 pathfinding — required correction pass

Codex independently reviewed the final first-pass sources (`AI` SHA-256
`CC4CEE3B...`, test-suite SHA-256 `A57CDB99...`). The single-flight/coalesced
path pipeline is sound, but the pass is rejected until the issues below are
fixed and exercised in Studio.

Do not publish Roblox, push Git, create a PR, or touch unrelated systems. Keep
repo and Studio byte-identical, update the sync manifest, and leave the final
working tree for Codex to audit.

## Blocking fixes

1. **Cumulative forward-progress credit**

   In `trackNavigationProgress`, a sub-`PROGRESS_DISTANCE_EPSILON` decrease
   currently advances `ProgressBestDistance` without crediting progress. At
   normal movement speeds this discards every small frame-to-frame gain, so a
   genuinely moving Manager can false-trigger `STUCK_REPATH` roughly every
   `StuckSeconds`.

   Keep the credited distance checkpoint unchanged until cumulative progress
   reaches the epsilon, or use separate raw-best and credited-checkpoint
   fields. Target/segment changes may rebase deliberately. Recovery actions
   must not masquerade as genuine movement progress in test telemetry.

2. **Reachable overlap escalation**

   `resetBlockedRoute` currently zeros `OverlapEscapeAttempts` after the same
   number of failed steering frames used by `ObstructionRecoveryAttempts`.
   Therefore the `OverlapEscapeAttempts > ObstructionRecoveryAttempts` branch
   can be unreachable when no escape direction is available, causing an
   endless reset/repath loop.

   Preserve overlap escalation across ordinary obstruction repaths. Reset it
   only after the Manager is actually outside the overlap or has made genuine
   forward/escape progress. Give each attempt a fixed deadline and require
   measurable blocker-count or goal-distance improvement.

3. **Full waypoint-projection validation**

   Every movement-facing call to `centerCorridorWaypoint`, including the
   waypoint-consumption loop, must revalidate. Endpoint occupancy alone is not
   enough: retain the original PFS waypoint unless the shared furniture-aware
   full-segment clearance contract validates the lateral segment from the
   original waypoint to its centreline projection (and the movement segment
   used by that caller). A blocked projection must never replace or prematurely
   consume a valid PFS point.

4. **Wall-hugging target must remain catchable**

   The first pass documents that `resolveNavigationGoal` can park the Manager
   about seven studs from an exposed player against a wall, outside the 4.4
   attack range, after which arrival-hold makes the standoff permanent. Resolve
   this rather than leaving it as an owner decision. Pick/validate the closest
   reachable goal that permits the existing attack without wall penetration,
   or make an equivalently safe minimal correction. Preserve the rule that a
   wall blocks attacks.

## Test and telemetry corrections

- Replace the single-snapshot `LastProgressAgeSeconds` test with time-series
  evidence of genuine forward progress: position/segment distance and
  waypoint/strategic index over time. A recovery timestamp alone must not let
  a motionless Manager pass.
- Add deterministic probes for:
  - normal-speed movement where every frame advances less than 0.25 studs;
  - total overlap with no initially usable escape direction, proving bounded
    escalation and eventual recovery rather than an endless loop;
  - a centreline projection blocked between the original PFS point and the
    projection;
  - an exposed player hugging a wall, proving the Manager gets into attack
    range while a wall still prevents attacks through it.
- Furniture restoration must fail if *any* baseline part is missing/destroyed,
  and must also capture/compare relevant Decal/Texture visibility state rather
  than silently skipping it.
- Make the new navigation regression entry point actually invoke the relevant
  tests, then run it in the fresh Studio server VM. Do not call a function
  behavioral if it only mirrors implementation math or validates one
  self-reported snapshot.
- Make the one-second request-rate metric half-open (`age < 1`, with a small
  clock tolerance if needed), so exact starts at 0, .2, .4, .6, .8, 1.0 do not
  falsely report six in the same one-second window.

## Required evidence before stopping

- Fresh Luau compilation of all changed sources.
- The 20-seed layout suite, including 101, 7331, 65537 and 1900813.
- Time-series outputs for each of the four edge probes above.
- Peak concurrent `ComputeAsync` remains 1 and the half-open request cap is at
  most 5/sec.
- Furniture REMOVED / VISIBLE_GHOST / RESTORED behavior and exact restoration.
- Final-hall chase, normal hunt, cleanup, and zero new console errors.
- Stop Studio in Edit mode and report any genuinely untestable residual risk.

