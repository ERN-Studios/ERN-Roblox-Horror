# Independent baseline spawn-path audit

Read-only source audit. AI SHA256 `af5885402a9d42760e7ba059057d186a97395fab20819a8bd6e7aab481f7598d` and Objective SHA256 `5474b27128d9d48deaa5503f4e340b138a06596534d87bff0a21d695ad2f39e8` matched the requested mirrors exactly. Repository HEAD observed `9b89211`; remote-tracking HEAD observed `de2e4de`. Existing unrelated dirty/untracked work was preserved. No Studio, API, UI, source, or Git writes were performed by this audit.

Line numbers below refer to those exact baseline hashes. No gameplay, multiplayer, or performance result is claimed.

## Concrete findings

1. Objective `updateFinalHallChase` lines 131–189 uses first-survivor semantics. Its final guard at 176 requires only `crossedCount > 0`, despite maintaining both counts. Require `eligibleCount > 0` and `crossedCount == eligibleCount`. Strict `along > entryProgress` already rejects exact halfway; the crossing is character-scoped and latched. A revived/new character cannot inherit another character's crossing.

2. Objective increments eligible count only after `livingCharacter` returns both a living character and HRP (146–147). A living participant with a temporarily missing root is omitted. Separate living membership from valid crossing position: known living participants without an observable position must block crossing, not disappear from the denominator. Dead, escaped, disconnected, and `InRound ~= true` players should remain excluded. Protected living participants are included by Objective, unlike AI target/spawn eligibility.

3. AI `chooseFinalHallSpawn` lines 3386–3447 tries preferred progress (usually .97), .95, .93, and .90. This permits four distinct spawn positions. Consume the one validated authored far-end marker, at hall FloorY, without a candidate list. Config currently authors a 560-stud hall and marker .97. WorldBuilder lines 2213–2232 publish both `SpawnMarker` and `SpawnProgress`.

4. Finale spawn currently requires ordinary `SpawnMinimumDistance = 90` from every AI-eligible player (3404–3408). A player near the exit can suppress all far-end candidates indefinitely, even after the final slower player crosses halfway. Adapter retries nil starts every .35 seconds (295–301). Remove the ordinary distance gate from the fixed finale reveal; preserve physical clearance and make any genuinely blocked fixed marker an explicit blocker. Spawn visibility (3442) is telemetry only, not a LOS gate. There is no fallback from a failed finale choose into normal choose: `chooseBlackoutSpawn` directly returns the finale result at 3450–3451.

5. AI `eligibleSpawnPlayers` (3306–3323) and `livingPlayer` (139–154) exclude protected living players. This disagrees with the barrier roster and can prevent spawn/initial CHASE when everyone is temporarily protected. Finale chase eligibility should be distinct from attack eligibility; preserve protection at attack initiation and confirmation. `forgetProtectedPlayer` also participates in target cleanup every Heartbeat. Any policy allowing protected finale targets must reconcile that cleanup.

6. `trackNearestBlackoutPlayer` (2048–2082) selects random room/table PATROL when it finds no target; protection or temporary missing roots can cause that branch even while humans remain alive. A finale should hold at its current position with cleared goal rather than ordinary roaming. `choosePatrolGoal` itself has no finale guard (1973–2019). Attacks briefly enter SEARCH/RECOVER (2553–2554), but blackout tracking restores CHASE on the next think; attack recovery is separate from ordinary random patrol.

7. `EntityPaused` causes `validRound` to fail (108–114), dormant PAUSED (2159–2161), and no initial target acquisition (3922). Decide finale pause behavior explicitly; preserving the pause control is reasonable, but report runtime pause/resume as a separate check. Config normal `SpawnGraceSeconds` is currently zero; finale activation should be explicitly immediate if ordinary grace changes. `roundChanged` always writes AWAKENING (3837–3843), then startup tracking writes CHASE before first Heartbeat when valid.

## Other paths inspected

- All production placement is the initial clone/PivotTo (3543–3590) and clearance-checked kinematic movement (3186–3187). `facePosition` changes orientation only (2311). `resetBlockedRoute` (2669–2692) only changes navigation bookkeeping and cannot relocate. Debug placement at 4142 is Studio-only. No production teleport recovery was found.
- Same-hall strategic routing follows the target directly (1340–1352); room perimeter/aisle repairs decline when a finale Manager is in the hall (1007, 1110). Stuck/obstruction recovery repaths; physical sweeps continue to gate motion. This is source evidence, not proof the current authored geometry navigates correctly.
- Adapter retains an existing Manager at line 289, but Music `setPhase(DONE)` (119–165) normally clears Hunt/Blackout, so the previous ordinary rig is removed before the finale hunt edge. Runtime should verify this transition and ensure only one active rig/one finale serial. Finale sessions capture `FinalHallChase` at Start; merely changing the flag on an existing normal rig cannot reposition it.
- Stop invalidates path/attack tokens, disconnects connections, stops audio, destroys the owned rig, and clears state (3244–3285). Deferred path/attack callbacks fence live session/token state. No cleanup/runtime performance claim is made.

## Runtime edge-case matrix

Two players .60/.49: no finale. Exact .50: no finale. Last survivor .5001: one fixed marker spawn and CHASE before normal think delay. Fastest player .95 while last crosses: fixed reveal still occurs without ordinary-distance retry. Alive/no HRP: barrier waits. Dead/escaped/disconnected/non-round spectator: excluded. New revived character: old crossing invalid. All protected: barrier counts humans and chase preserves attack immunity. Paused/resumed: same rig/serial, no relocation. Existing normal hunt reaches DONE: ordinary rig clears before one finale rig. Fixed-marker blocker: no alternate position; expose actual failure. No-target finale after escape/death: no random roam. Repeated stuck/PFS failure: no teleport or spawn serial change. Round reset: no surviving owned tasks/connections/audio/state.
