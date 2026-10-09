# Level 1 Blender facelift independent source review

Review date: 2026-10-02. Reviewed the new access/button sources, renderer, and final GameManager/MazeGenerator drafts against the authoritative pre-change Studio export. This record is source review and executable source-backed testing; it does not claim engine gameplay, multiplayer, client input or publication passed.

## Reviewed integration

- `ServerScriptService.Level1BlenderPreviewAccess` owns transparent, nonphysical anchors inside the exact Level 1 lobby rooms. The complete visible native ProximityPrompt is created locally only after `DevAccess.IsAllowed` succeeds. It copies the authoritative Level 4-6 developer entry settings (hold 0.5 seconds, range 10, no line-of-sight requirement, `DEVELOPER PREVIEW`) with `ENTER LEVEL 1 FACELIFT PREVIEW`. The central two-developer allowlist is used; the separate Level 6 guest exception does not grant Level 1 access.
- The remote validates its server-owned host, exact room/floor, current living avatar, distance, participation flags, reserved-server restriction, cooldown and invocation lock before calling the server-only GameManager BindableFunction. Client-supplied party, seed or authorization data is not accepted.
- Published entry reserves a fresh server. Destination cohort admission independently authorizes every actual participant before setting `Level1BlenderPreviewActive`. A preview TeleportData marker does not authorize an ordinary player.
- The preview uses the existing Level 1 loading, original maze topology, objectives, entity, elevator, death/win and lobby-return loop. Renderer selection is conditional on the preview flag. Public queue selection remains unchanged. The preview suppresses progression/rewards and has no next-level transition.
- Room visuals preserve the original physical maze while authored pillar/detail colliders remain physical. Original puzzle interaction parts and mechanical movements remain authoritative; Blender meshes provide their visible surfaces.

## Concrete issues found and resolved before installation

| Finding | Resolution reviewed |
| --- | --- |
| Readiness gate required `MetalPanel`, absent from the initial manifest. | Importer alias added for the authored elevator-door skin; component now exists. |
| Importer marked `Complete` but renderer checked `Ready`. | Final importer sets both after installing the kit. |
| Nested floor ancestry could hide the pit opening under Blender carpet. | Placement meshes receive explicit `RoomRole`; renderer also resolves ancestor roles. Pit floor/details are hidden and detail colliders disabled in pit/elevator cells. |
| Renderer disabled authored pillar/detail collisions. | `Collider` role remains collidable with the existing Decor collision group outside pit/elevator cells. |
| Generic skins lost original circuit cable colors; static fuse-cap skins failed to follow extraction. | Initial original color is copied, including SurfaceAppearance tint; fuse cap uses dynamic weld movement. |
| Prefab fixtures repeated visible lamps in every room and bypassed original sparse-light behavior. | Template fixtures are hidden; original generated fixtures provide the skinned light positions and phases. |
| Teleport options/packet construction could throw outside protected launch cleanup and leave a lock. | Entire published teleport setup and call are protected; launch lock is released on failure. |
| Studio launch exception could return players while leaving gameplay flags/reentry active. | Failure path clears `RoundActive`, `PostWinIntermissionActive` and reentry callback before protected lobby recovery. Preview and launch flags are then released. |
| First actual Play reported conflicting hosts although exactly one script created the public and reimagined hosts. Weak Instance-key ownership could disappear during garbage collection while the engine Parts stayed parented. | Server/client/watched registries now retain strong keys and explicitly release on host destruction/removal. Unregistered existing hosts remain rejected; the script does not adopt or replace them. |

No remaining source-level blocker was found in the final reviewed drafts. Asset readiness, pathfinding and performance must still be checked in the running engine before treating the implementation as verified.

## Executed offline checks

- `python tools/tests/test_level1_blender_preview_access.py`: 26 actual-function gate assertions, six actual `ensureHost` lifecycle assertions and 12 full authorized client lifecycle assertions passed. Tests cover repeated hooks, destroyed-host release, replacement registration, rejecting a foreign host, native trigger/rate limiting, round hide/restore and callback cleanup. The complete unauthorized client execution creates no UI. Access and client sources compile.
- `python tools/tests/test_level1_blender_preview.py`: 51 actual-function assertions passed; the original topology-generation block is unchanged. Draft GameManager/MazeGenerator and renderer compile.
- `assets/level1/blender/qa-runtime.luau` compiles with official Luau 0.737. It is a read-only Server Play probe that performs no launch, teleport, interaction or round writes. It verifies runtime source/asset provenance, PBR maps, masks and reciprocal connected room graph, pit visibility/detail collisions, original participants and objective populations, and bounded navigation samples for a relay, fuse box and lever. Three path computations are capped at four seconds each and their temporary paths/tasks are disposed. A separate reset/public mode verifies preview room cleanup.
- Test runners fail if an executable Luau runtime is unavailable; no successful skipped test result is reported. The access runner falls back to the known checked artifact executable.

## Engine verification boundaries

The runtime probe reports server memory and a short Heartbeat sample. Heartbeat duration is not a server CPU profiler measurement. A scene with thousands of room meshes requires an actual bounded active-round performance assessment. Visual/input behavior for both developers and ordinary clients, relay extraction and installation, lever activation, entity navigation/escape, death/return, reset/reentry, and multiplayer remain engine checks. A successful publication response is a separate required result.

The owner explicitly instructed no backups for this task. This review creates no native place backup and does not introduce a backup prerequisite. Root owns fresh Studio baseline comparison, scoped installation, export, staged-diff inspection, commit and publication.

The host-registry diagnosis follows Roblox's [metatables documentation](https://create.roblox.com/docs/luau/metatables): weak Instance references can be collected while the Instance remains alive in the data model. The initial engine observation was read-only: exactly one enabled Access script and two correctly tagged hosts at the expected room paths. No yielding operation exists between ownership registration and parenting in `ensureHost`, so deferred room hooks cannot race that creation sequence. Offline lifecycle checks do not simulate Roblox userdata collection; a fresh Play is required to verify warning-free engine retention after the fix.
