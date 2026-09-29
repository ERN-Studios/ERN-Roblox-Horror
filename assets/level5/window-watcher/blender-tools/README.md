# Window Watcher: Blender preparation

Completed against the actual Meshy rigged source on 25 September 2026. No replacement geometry or invented humanoid was generated. Three animations were authored locally in Blender; no paid Meshy animation tasks were requested.

## Final files and verification

Delivered files are in the parent `window-watcher/` directory: `model.blend`, `model.glb`, `model.fbx`, `WatchingIdle.fbx`, `SlowWindowLean.fbx`, `GlassTap.fbx`, and exact embedded `WindowWatcher-basecolor.png`. The blend stores all three actions. The model GLB/FBX retain the original bind stance; play WatchingIdle immediately for the lowered-arm gameplay stance.

The real model is 2.4 metres tall, 11,862 triangles / 8,968 vertices in one mesh, 25 bones (24 Meshy bones plus an unweighted Root at origin). Every vertex has 1–4 normalized influences. No root-weighted or unweighted vertices, no new leaf bones, and no finger bones. Meshy's unrelated Icosphere helper was excluded; its 0.01 object scales were applied without changing world shape. Oversized bone display lengths were shortened along their existing axes.

`roundtrip-audit.json` passes for the model GLB/FBX and all three animation FBXs: exact bone hierarchy, expected zero/one clips, valid weights and sampled exported movement. `animation-quality-audit.json` passes: identical start/end pose, shared initial pose within 0.0000003m, stationary feet and root, and no abrupt transition (largest rotation step 10.9° during the quick hand movement). Final full-body, palm, raising-arc and three-pose contact-sheet renders in `../renders/` were inspected. The hand faces the glass and the face is unobstructed; this is an asset QA result, not a claim of Studio runtime import.

## Roblox animation data and coordinate contract

Use `WatchingIdle-roblox-30fps.json`, `SlowWindowLean-roblox-30fps.json`, and `GlassTap-roblox-30fps.json` (each under 280KB). Each contains `frames[].time` and `poses` rows `[boneName,tx,ty,tz,qx,qy,qz,qw]`. Translation units are metres. Root integration must scale translations to its actual imported model size.

**Use these final compact files, not an assumed world-axis conversion of local rotations.** `export_serialized_gltf_clips.py` reads the actual frozen GLB joint-node matrices and inverse binds. Bone-local bases are preserved by this exporter; only the world basis changes. `serialized-glb-coordinate-audit.json` verifies the mapping to approximately 0.000002 and pins the GLB SHA-256 `cbf260ff36b8c7226f27271456eae6bf4db7fd266bdce82dda8b0eae7cbc051e`. The expanded `animation-transforms-30fps.json.gz` is corrected to the same serialized-node contract. Runtime import may further transform node bases, so compare Studio Bone rest CFrames before publication.

## Window placement

`placement-reference.json` uses an actor frame facing −Z: actor X=−BlenderX, actor Y=BlenderZ, actor Z=BlenderY. At 8-stud height, scale is 3.333333 studs/metre. Maximum forward mesh extent is −0.763673 studs for WatchingIdle, −0.779343 for SlowWindowLean, and **−1.745002 for GlassTap**, including the complete raising/lowering arc. Actor origin approximately **1.80 studs inward from the glass plane** leaves at least 0.055 stud clearance at the closest fingertip; account separately for actual glass thickness and importer scaling.

Idle eye reference is approximately `(0.016,7.400,-0.461)` studs; maximum lean eye reference approximately `(-0.014,7.337,-0.702)`. Tap palm reference near contact is approximately `(0.900,6.249,-1.501)` studs. These eye/palm points are anatomical estimates from the real skeleton; whole-mesh extrema come from evaluated skinned vertices at every frame. Add the actor's placement offset to obtain window-local coordinates.

## Available tools

- `inspect_asset.py`: isolated import of GLB/FBX/blend; real geometry count, bone tree/rest matrices, influence counts and sums, root weights, image payload, and layered-action inventory.
- `watcher_common.py`: Blender 5.2-compatible action helpers and explicit export defaults. `export_model_and_clips()` requires all three genuine authored actions and an imported bound mesh before it produces anything.
- `prepare_rig.py`, `author_watcher.py`: inspected bone mapping and local animation authoring. Source assets remain unchanged. The authoring script now leaves the already handed-off static GLB/FBX untouched.

Executable: `/Applications/Blender.app/Contents/MacOS/Blender`.
Use `--background --factory-startup --disable-autoexec --python-exit-code 23 --python SCRIPT -- ARGUMENTS`. No addon installation or user-preference changes are necessary.

## Authored animation design

At 30 FPS, all three clips keep the root stationary and start/end in the same unsettling watching stance. Feet remain planted. The A-pose is the bind pose, not the gameplay pose.

1. **WatchingIdle** — frames 1–181, 6 seconds, loop. Arms relaxed beside the body; subtle uneven breathing, a small slow head inclination, gaze returning towards the observer. Restrained movement preserves the window silhouette.
2. **SlowWindowLean** — frames 1–151, 5 seconds. Long still hold, gradual spine/neck lean toward the glass, slight head tilt, quiet hold, slow return. Feet and hips stay near the starting position; no forward root travel.
3. **GlassTap** — frames 1–121, 4 seconds. Right forearm rises, hand approaches an imaginary glass plane at chest/face level, two short wrist/finger pulses separated by a disturbing pause, hand lowers to the watching pose. Use actual finger bones only if present. Never add fake fingers or bone names. Avoid penetration of the torso/hair and abrupt shoulder collapse.

## Export and evidence contract

- `model.blend`: real source mesh/materials/rig, packed textures, all three authored actions.
- `model.glb`, `model.fbx`: bind/rest pose, materials and skin, no animation.
- `WatchingIdle.fbx`, `SlowWindowLean.fbx`, `GlassTap.fbx`: selected mesh and same armature, one baked animation each. No leaf bones, no all-actions/NLA aggregation, no frame simplification, textures embedded.
- Preserve bone names/hierarchy/rest pose. FBX Z-forward/Y-up per Roblox export guidance; verify front direction, scale, and skeleton after fresh reimport.
- Before delivery: each mesh ≤20,000 triangles, ≤4 influences per vertex, no unweighted skinned vertices; inspect normalization/root weights; verify all images are available.
- Fresh-process FBX reimport: exactly one clip per animation export, equivalent hierarchy and transformed geometry bounds, nonzero sampled pose movement; model exports contain no clips. Compare sampled world bone heads / deformation to the authored original, allowing coordinate conversion and FBX representation tolerances.
- Render full-body front/three-quarter, face/hand close-up and contact sheets of each clip. Inspect shoulder/elbow/neck/wrist extremes and first/last-frame loop closure. A GLB/FBX export is not proof of Roblox runtime import; Studio validation remains a distinct parent task.

## Existing project pipeline reviewed

The repository's `tools/export_entity_animations.py` is explicitly deprecated and contains a Windows-specific output path. Its useful action-slot selection and per-action FBX bake flags are retained as patterns, not executed. The existing pool-slide GLB reconstruction is specific to a lost-source Roblox rig and must not be used for this new Meshy model. `tools/inspect_blender_actions.py` establishes compatibility with layered actions in current Blender.

## Repository layout

Authoring utilities resolve their outputs to this directory’s parent, next to the delivered model. Run them in a writable copy of the asset directory. `prepare_rig.py` regenerates the intermediate `prepared-rig.blend` from `../meshy-source/window-watcher-rigged.glb`; then `author_watcher.py` builds the three actions. These scripts write generated files. The expanded JSON evidence is gzip-compressed in Git. The original verified task outputs and hashes are retained separately.
