# A2 lion reflector, 2026-10-09

Status: **installed and Play-verified on 2026-10-09** after Shop UI released Studio and the owner authorized takeover. The normal shared lock was acquired without changing queue order. Three mesh assets passed moderation. Only the five old A2 prop meshes and their unique collider were replaced. The incoming skylight now reaches the measured disc hub; reflected warm illumination and a visible shaft reach the lion. Studio is returned to Edit. No place publishing was performed.

QA receipt: `qa/studio-qa.json`. Final scene: `qa/a2_reflection_front.jpg`; grounded frame: `qa/reflector_grounded.jpg`. Same-camera lion views `qa/lion_reflection_on.jpg` and `qa/lion_reflection_off.jpg` disable the Beam ribbons in both shots, isolating actual SpotLight illumination. The lion ROI mean luminance rises from 0.046 to 15.048 (8-bit scale) with that SpotLight enabled. Four walking waypoints around the frame retained 100 health, with maximum horizontal arrival residual 2.23 studs. Existing sound-access/library warnings remain; no reflector or skylight runtime errors appeared.

Original image-to-3D task: `01a110ef-da7c-76c0-af4d-c6cff685ea24`.
Replacement image-to-3D task: `01a11fcc-a1b3-740f-82ef-21602da84d1e`.
Meshy project: `meshy_output/20261009_103512_a2-lion-reflector_01a11fcc`.
Quoted planner estimate: 30 credits. Actual replacement task charge: **15 credits**.

Reference was edited with the built-in image generation tool. The reference preserves two vertical posts and flat feet and tilts the circular plate around its horizontal axle. Meshy smart topology produced the frame and rim; local Blender processing isolates the plate and rim from the supports, repairs folded triangles on the inner face, and fits the exact reflection angle. No second paid generation was submitted.

Final deliverables:

- `reflector-reference.png`: new Meshy input.
- `reflector.glb`: untouched Meshy result.
- `reflector-fitted.glb`: repaired, precisely aimed model for reuse.
- `prepared/reflector_staged.blend`: corrected Blender mesh.
- `prepared/preview.png`, `reflector-fitted-side.png`: rendered model previews.
- `prepared/manifest.json` and three wire meshes: Roblox import packet.
- `reflection_validation.json`: independent geometry, floor, hashes, winding and collision-path audit.

Final floor origin: `(69742.6, 282.554, 0)` studs. Plate center: `(69742.6432647, 288.7305275, -0.2208649)`. Lion face target: `(69699.40618026388, 318.2325, 43.19381973613)`, measured on its normalized Blender geometry. Plate normal: `(-0.375452, 0.846706, 0.3769942)`. Plate rotates **57.855186 degrees from vertical**; posts do not pitch. The vertical incoming ray reflects toward the lion at 68.005 studs. Numerical center-ray miss is about 0.0000052 stud; this is an offline geometric check, not a Roblox lighting test.

Lighting uses a warm SpotLight (120-stud range, 28-degree cone, brightness 12, shadows enabled) plus five Beam ribbons with 24 segments so their interior transparency keys render correctly. Actual illumination and beam continuity passed Play under the map's normal grade (brightness 0.9, A2 clock 12, vertical sun). Live disc normal error is 0 degrees at float precision and the collision query reaches the lion before any other obstacle. The incoming skylight received three source edits confined to `buildSkylight`, reading the new center while retaining legacy fallbacks; live Source/editor and repository mirror parity were checked.

## Import procedure and recovery

Use the existing shared lock normally. Do not jump the queue, publish the place, or run the whole-map builder. Exact measured Studio ID is `1b603e69-7ae1-4572-b210-d5bf05c684ff`, place `131311258779917`; re-check the connected ID if Studio has restarted.

These were run sequentially from `G:/Roblox/MongoTV` with this session holding the lock. `apply` intentionally refuses a second swap; use `verify` on the installed map:

```powershell
python artifacts/level2-lion-reflection-20261009/import_reflector.py check
python artifacts/level2-lion-reflection-20261009/import_reflector.py uploads
python artifacts/level2-lion-reflection-20261009/import_reflector.py prepare
python artifacts/level2-lion-reflection-20261009/import_reflector.py apply
python artifacts/level2-lion-reflection-20261009/import_reflector.py lights
python artifacts/level2-lion-reflection-20261009/apply_skylight_patch.py
python artifacts/level2-lion-reflection-20261009/import_reflector.py verify
```

Import replaces only `Visual.A2.254` through `258` and the precisely identified original prop collider. Originals are preserved in `ServerStorage.CodexBackup_20261009_A2Reflector`. Swap validation occurs inside a rollback guard with an optional Studio undo recording (the MCP host can own the active recording). Mesh uploads are resumable by content hash; moderation is checked after each mesh. No image textures were uploaded. New mesh asset IDs: `81149896917489`, `86514264330055`, `86300620651777`.

Play QA: enter the new map through its normal developer entry; stream A2; confirm upright grounded feet, continuous skylight-to-disc-to-lion beam, a warm illuminated lion, and no player obstruction regression. Capture comparable reflected-light on/off views under the actual map grade, confirm all light settings and geometry on Server, check console output, and return Studio to Edit before releasing the lock.

## Blender source

See `SOURCE-INTEGRATION.md` and `source-integration-receipt.json`. After passing Studio QA, `integrate_reflector_source.py` installed the reviewed master, new reusable asset, one manifest entry and the single A2 build_props asset-name change. Local and world instance matrices are preserved, and the replacement mesh compensates for A2's parent rotation, avoiding double yaw. Originals were backed up under `G:/Blender/Level2_Poolrooms_New_20261006/backups/before_A2LionReflection_20261009T124435577027Z`. All written source files passed fresh SHA checks.

The current Studio map retains its static reflection folder and measured attributes. A future whole-map rebuild must also restore the measured `A2ReflectorCentre` and `A2ReflectorNormal` Vector3 attributes from `prepared/manifest.json` and run `install_reflection.luau` before Play. The map exporter does not yet transfer those custom Blender attributes automatically.

Relevant Roblox behavior: [Beam documentation](https://create.roblox.com/docs/reference/engine/classes/Beam), [SpotLight documentation](https://create.roblox.com/docs/reference/engine/classes/SpotLight), [Lighting range clamp](https://create.roblox.com/docs/reference/engine/classes/Lighting).
