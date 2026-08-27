# Claude prompt — Level 3 Mall Manager pathfinding

Copy everything below this line into Claude:

---

You are working on the Roblox experience **Backrooms: No Way Out**, place ID
`131311258779917`. Fix Level 3 Mall Manager pathfinding in the live Studio
place and mirror the verified source back to the repository. Do not redesign
the monster or change unrelated gameplay.

## Source of truth and workflow

- Treat the connected live Studio place as the source of truth. Read each live
  script's `.Source` before editing it and compare it with the repository.
- Read `CLAUDE.md` and the latest handoff first.
- The active files are:
  - `ServerScriptService/Level 3 Systems/Level 3 Mall Manager AI Controller.ModuleScript.lua`
  - `ServerScriptService/Level 3 Systems/Level 3 Configuration.ModuleScript.lua`
  - `ServerScriptService/Level 3 Systems/Level 3 World Builder.ModuleScript.lua`
  - `ServerScriptService/Level 3 Systems/Level 3 Layout Generator.ModuleScript.lua`
  - `ServerScriptService/Level 3 Systems/Level 3 Music Sequence Controller.ModuleScript.lua`
  - `ServerScriptService/Level 3 Systems/Level 3 Test Suite.ModuleScript.lua`
  - `ServerScriptService/Level 3 Systems/Level 3 Round Adapter.ModuleScript.lua`
  - `StarterPlayer/StarterPlayerScripts/Level 3 Mall Manager Visual Smoother.LocalScript.lua`
- Ignore `ServerStorage/*Backup*`; those are archives, not active code.
- Preserve unrelated work. Compile every touched Luau script, run Studio
  playtests, verify the final Studio/repository bytes, and update the sync
  manifest. Do not claim success from static inspection alone.

## Architecture that must remain intact

- The Mall Manager is a server-authoritative, anchored, collisionless custom
  rig. The client only smooths the rendered mesh through the unreliable
  `MallManagerMotion` remote. Do not convert it to Humanoid locomotion.
- `Level3MallManagerHuntActive` remains the spawn/despawn authority.
- During blackout, reevaluate the nearest eligible, living, non-hidden,
  non-escaped player every `0.10` seconds. Target changes after hiding, death,
  escape, distance crossover, or leaving must remain immediate.
- Straight unobstructed chase speed must remain exactly `26 * 1.20 = 31.2`
  studs/second.
- Preserve attacks, line-of-sight rules, hiding, furniture disappearance and
  restoration, the final-hall chase, audio, ESP tags, and client smoothing.
- Current navigation dimensions are agent radius `5`, sweep radius `5.25`, and
  height `10` inside corridors roughly `14` studs wide and `10.5` studs high.
  Inspect Studio's navigation mesh/modifier visualization before changing any
  of those values.
- Do not solve this with noclip, large CFrame teleports, moving world geometry,
  blindly shrinking the entity, extending furniture removal, or replacing the
  custom controller with a Humanoid.

## Defects to fix

1. **Moving-goal path starvation.** `requestPath` discards a successful route
   whenever the latest moving goal differs by only about `0.05` studs. A target
   moves several studs per think tick, so usable paths can be discarded forever.
   `pendingForce or true` is also always true and bypasses the intended rate
   limit. Coalesce goal updates, install the last successful usable route first,
   then schedule a fresher replacement. Allow at most one computation in flight
   and no more than five blackout path requests per second.

2. **Strategic backtracking/oscillation.** `rebuildStrategicRoute` includes the
   current room centre as its first waypoint and resets the index whenever the
   target moves by roughly three studs. Cache the room sequence while the goal
   room is unchanged, skip the current-room centre, and route directly from the
   current position for same-room targets. Progress must not reset just because
   the player moved within the same room.

3. **Ghost furniture blockers.** Furniture navigation exclusions are collected
   even after the music sequence makes their parts invisible, non-collidable,
   and `CanQuery = false`. Manual volume checks therefore avoid furniture that
   no longer exists while PathfindingService sees different geometry. An
   exclusion must be authoritative only in the intended furniture state, and
   every movement stage must use one consistent clearance contract.

4. **Incomplete stuck detection.** The current check runs only after successful
   movement. Early returns for a pending path, missing waypoint, or obstruction
   evade recovery, and lateral circling counts as progress. Run no-progress
   tracking across every branch. Measure progress using waypoint-index advance
   and decreasing distance to the active segment/goal, not raw displacement.

5. **Permanent overlap escape.** An escape direction remains accepted when its
   blocker count is merely equal, and its timer is renewed forever. Give escape
   attempts a bounded lifetime and require them to reduce blocker count or
   improve goal progress; otherwise choose a new clearance-checked direction
   and escalate recovery. Do not reset escalation counters until genuine
   forward progress occurs.

6. **Unsafe room/waypoint classification.** `nearestRoomId` uses room-centre
   distance near doorways instead of containment/distance to room bounds.
   `centerCorridorWaypoint` can move a valid PathfindingService waypoint onto a
   blocked centreline without revalidation. Use room bounds and revalidate every
   projected waypoint; retain the original waypoint when projection is invalid.

7. **False validation telemetry.** `PathValidated = true` is assigned at spawn
   without a real path computation. Either perform genuine reachability
   validation or remove/rename the claim and update the tests accordingly.

## Required verification

Extend the active Level 3 test suite with behavioral navigation coverage and
prove all of the following in Studio:

- A continuously moving target behind a wall gets a usable installed route in
  bounded time; successful routes are not continually discarded.
- Same-room and cross-room strategic progress is monotonic unless the target
  genuinely moves behind the Manager.
- Furniture states `RESTORED`, `REMOVED`, and `VISIBLE_GHOST` apply exclusions
  only when intended, and all original properties restore correctly.
- From a crowded table start, each escape attempt reduces overlap or is replaced;
  there is no permanent equal-blocker loop.
- With two to six players, the nearest target changes within one think tick after
  distance crossover, hiding, death, escape, or leaving, and stale
  `BeingChased` flags clear.
- Run at least 20 generated layouts, including seeds `101`, `7331`, `65537`, and
  `1900813`.
- The authored final-hall spawn/chase remains correct and never routes back into
  Signal Hall.
- No valid chase remains motionless longer than the stuck interval plus one
  recovery/repath window.
- There is never more than one path computation in flight and never more than
  five blackout requests per second.
- Unobstructed chase remains 31.2 studs/second; attack LOS and visual smoothing
  are unchanged.
- Inspect and report the live navigation mesh and modifier geometry for the
  radius-5/height-10 agent.

Return a concise cause-and-fix summary, the exact scripts changed, compile/test
results, sampled navigation telemetry, and any remaining risk. Do not publish
the Roblox experience and do not push Git; leave the verified changes locally
for Codex to audit and finish.

---
