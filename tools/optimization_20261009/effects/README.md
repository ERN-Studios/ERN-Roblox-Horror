# Prepared scene-effect budget — 2026-10-09

These files are reviewable proposals. No Studio instance, source, property or Play state was changed by this subtask. The owner explicitly asked to preserve the concurrent Play session, so deployment, native contract execution, gameplay checks and publication remain pending.

## Implementation

Install `SceneEffectBudget.ModuleScript.lua` as a **new ModuleScript** at `game.ReplicatedStorage.SceneEffectBudget` and `SceneEffectBudgetClient.LocalScript.lua` as a **new LocalScript** at `game.StarterPlayer.StarterPlayerScripts.SceneEffectBudgetClient`, only after the root agent has backed up the native place, verified the exact live baselines, and obtained Edit mode.

The client budgets **explicitly marked** decorative Lights and ParticleEmitters. It changes only Enabled. Brightness, Color, Angle, Range, material, collision and server game state remain owned by their existing controllers. XZ sectors restrict candidate searches; exact distance includes height. Camera and local body each retain nearby sectors, so a detached camera does not darken the player's immediate surroundings. A 0.25-second update, hysteresis, deduplicated pending queue, moved-mount reindexing and streaming addition/removal signals avoid whole-map per-frame scans. Bootstrap scans only the relevant Lights/Props or Water FX containers.

`SceneBudgetWantedEnabled` is an independent authoritative boolean, never a client culling output. This prevents restoring an old “on” state after a server blackout has written Enabled=false while the client was already suppressing the light. Enabled-property signals also repair a repeated replicated Enabled=true when the wanted attribute did not change. Equality checks prevent a self-write loop.

The 11-line additive Level 4 Director change initializes the desired attribute from the server's actual original state, publishes it **before** each Enabled write, and restores it **before** original properties during Stop. Apply the three exact replacements from `Level4LightDirector.replacements.json` against a freshly read, conflict-free Source/editor baseline. The full baseline/proposed files are evidence and review aids, not deployment authority.

## Conservative initial selection

| Map | Proposed candidates | Active distance | Hysteresis | Additional safety |
| --- | --- | --- | --- | --- |
| L4 Cinema | Existing static lights with numeric L4Zone (expected 254) | 320 studs | 48 studs | Director supplies current desired state |
| L5 Void | Lights whose holder is named Light (620) | 384 studs | 64 studs | The 9 CrusherLights and 32 Geometry/orb lights remain outside this budget |
| L2 Poolrooms | 8 Water FX emitters | 320 studs | 48 studs | Explicit 32-stud particle influence envelope |
| L6 Arena | No distance suppression | — | — | Open atrium/galleries must remain visible across the arena |

Light activation adds the authored Range to these distances. Particle activation adds its explicitly authored influence radius. A 32-stud envelope covers the measured foam bound (19.99 studs) and spray bound (13.92 studs). The selector combines actual maximum lifetime, speed, acceleration magnitude, holder half-diagonal and maximum particle half-diagonal including Size envelopes; unaccounted wind or a combined bound over 32 fails closed at selection. A2 skylight/reflection beams, hazards, emergency lights, objectives, flashlights and characters are not opted in. L2's 512 authored lights contain 239 disabled lights; they are deliberately left alone.

`effect_selector.ModuleScript.lua` is a **read-only** candidate collector for Edit mode. It supplies actual Instance identities plus Enabled/attribute baselines, including duplicate-name objects. The root must compare the same exact instances and baselines again inside each metadata write. Record full native rollback data for every added attribute. Do not treat the expected counts as authorization to overwrite a fresh different map.

## LOD and asset reuse findings

Fresh Studio inventory (initial Edit read, then bounded Server reads after concurrent Play started) confirms:

- L4: all 4,051 MeshParts already Automatic; 516 distinct MeshIds. The leading meshes repeat 1,132 and 1,024 times, and PBR sets repeat 1,309 and 1,190 times.
- L6: all 73 MeshParts already Automatic, with 7 MeshIds. 5,688 Texture instances use only 3 texture IDs, of which one appears 5,306 times. The Level 6 union LOD proposal is owned by the geometry subtask.
- L2: 2,931 MeshParts Automatic and 5 Precise. Those five are authored slide entry/outlet edge/cap/cradle surfaces; changing their visual fidelity without a slide-quality comparison is not justified.
- L5 uses primitive geometry rather than mesh/texture assets in the current template.

The actual common mesh/PBR/texture assets are already shared; cloning SurfaceAppearance instances with identical asset IDs does not demonstrate duplicate downloads. No asset ID was replaced, no upload was invented, and no blanket SLIM policy is proposed for runtime-modified maps. Evidence is in `live_asset_summary.json`, `live_particles_and_precise_meshes.json`, `live_water_particle_bounds.json`, and `live_controller_contracts.json`.

Roblox's existing occlusion/frustum culling means fewer locally Enabled lights does not directly imply an FPS gain. The distance values above are conservative initial candidates, not measured optimal settings.

## Validation and remaining checks

Luau 0.741 compiled the budget ModuleScript, client adapter, selector, native probe and proposed Director. The **36 offline policy/lifecycle assertions passed** in `test_budget.luau`. They cover authored false, unmarked state, hysteresis, the same-value blackout, repeated server Enabled=true, untouched flicker/finale properties, moved mounts, stream-in/out, marker removal, particle-bound failure, combined future particle bounds/wind, deduplicated queues, far-sector idle checks, no-view restoration and complete connection/index release.

Command:

```powershell
& 'G:/Roblox/MongoTV/_local/optimization-20261009/luau-0.741/luau.exe' 'tools/optimization_20261009/effects/test_budget.luau'
```

These tests use an event-capable Instance stand-in. They do not prove Roblox replication ordering, rendering, gameplay or device performance.

`native_contract_probe.luau` is prepared for the root to stage in a fresh empty ModuleScript. It tests actual synthetic PointLights with task.wait around signals and always destroys test-owned objects after either success or failure. It is not yet executed. Verify authoritative originals before staging and after success/failure, as required by AGENTS.md.

Before publication: run the native probe and actual L4 power-off/power-up/finale/reset checks, L5 sight lines and crusher-room arrival, L2 cascade approach/re-entry, map park/unpark, streaming removal/re-entry, and camera/teleport movement. Compare identical routes/cameras with the runtime rollback switch on/off; capture light/particle rendering time, p95 frame time and connection/memory retention. Confirm distant light suppression does not change visible room illumination or distant gallery silhouettes. If it does, enlarge the budget or narrow the opt-in set.

## Rollback

Set `workspace.SceneEffectBudgetDisabled = true` to release all local suppression within the next 0.25-second update; restoration uses **current authoritative desired state**, including an active blackout. Remove the flag or set false to rebuild sessions. The rollback switch does not touch collision or server game state.

For permanent rollback in Edit: restore the exact recorded pre-task metadata attributes, apply the inverse of the three scoped Director replacements after a fresh baseline check, and remove/archive only the new task-owned client/module instances through the root's guarded workflow. Preserve the native place backup and every unrelated developer change.

## Primary documentation

- [Roblox performance guidance](https://create.roblox.com/docs/performance-optimization/improve)
- [Light API](https://create.roblox.com/docs/reference/engine/classes/Light)
- [MeshPart API](https://create.roblox.com/docs/reference/engine/classes/MeshPart)
