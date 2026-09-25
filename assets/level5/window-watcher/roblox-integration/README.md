# Window Watcher — pending Roblox integration

This package is **prepared and preview-tested, not installed or published**. Do not copy the draft Adapter over Studio. Studio remains authoritative; reconcile its fresh Source/editor bytes before a scoped install.

The exact Meshy GLB is converted to 8,996 UV-split vertices, 11,862 triangles and 25 bones. The transient native mesh, material and all three clips have been inspected in Studio Edit. Native Animator checks cover 400 bone/time samples with maximum matrix-component error 0.0002191. These temporary clip IDs are not production asset IDs.

## White eyes

Use `tools/install_watcher_eyes.luau` and mask `rbxassetid://91743869995723` (v5; SHA 99315f05889bbc4c9f1122f502913bef7bf3fd5d7742b2a5a30ded79fee45738). The measured .067-stud iris cores use SurfaceAppearance emission on the real skin, so they follow every head pose without a frame loop or extra lights. Suggested strength 200 was visually checked; original albedo is dark in the iris and strengths 15–30 remained gray. Billboard eyes were rejected because tinted Glass occluded them. Emission is visible through a test pane with the same Glass/RGB/transparency as Level 5.

V5 guards neighboring brow UV islands. The very close native preview still needs a final filtering check after Roblox finishes processing the new material pack; do not claim an exact no-fleck result. No body geometry, albedo, bone bases or original Blender source was changed.

## Current blocker

`CreateAssetAsync` fails with `CreateAssetAsync and CreateAssetVersionAsync are not available yet`. The normal Studio Beta Features dialog was inspected and **CreateAssetAsync Lua API is unchecked**. Coordinate UI actions report noWindowsAvailable and native dialog interactions intermittently time out. The owner has been asked to enable that feature through File → Beta Features and save/restart if requested. Do not edit internal flags, use cookies or create API credentials to bypass the normal workflow.

The built mesh is transient. EditableMesh content and temporary animation IDs are not a durable delivery. The source/chunks and clip data are all preserved here for rebuilding after restart.

## Rebuild and finish

1. From repository root, regenerate if needed: `python3 assets/level5/window-watcher/roblox-integration/mesh-import/convert_exact_glb.py --source assets/level5/window-watcher`. Inputs are hash-pinned. The existing generated chunks are identical and ready.
2. Run `python3 assets/level5/window-watcher/roblox-integration/tools/local_bridge.py` (localhost:8769, task files only). Temporarily enable Studio HttpService for each bounded import call and restore the original value afterward.
3. Execute the reviewed `mesh-import/import_exact_mesh.luau` as a module in Studio Edit. Call begin with `http://127.0.0.1:8769/mesh-import/`, six nextVertices calls and four nextFaces calls.
4. `publishMesh()` uploads to ERN Roblox Studios group 1039373905. `verifyPublished()` must pass before `buildRuntime()`. `buildPreview()` is explicitly temporary and must be discarded before saving/publishing the place.
5. `buildRuntime(91091934459636)`, then apply white eyes with the final mask/strength. Inspect original UVs, skin, scale and eye filtering. Name the model WindowWatcherRig under a new ServerStorage.Level5WindowWatcher folder.
6. `tools/publish_watcher_clips.luau` creates real group-owned Animation assets and sibling Animations instances. All three complete gestures intentionally loop; their endpoints match. Record actual IDs.
7. Reconcile/install `patches/Level 5 Window Watcher Encounters.ModuleScript.lua` and the small Adapter hook against fresh Studio bytes. `patches/Level 5 Round Adapter.ModuleScript.lua` is a **proposal**, not the live source mirror. The earlier repository `tools/staging/level5_window_watcher_preview.luau` is superseded for installation by the intermittent draft here.
8. Enter through Level5DevStart/normal developer queue, inspect all three real windows, animation curves and eye visibility; verify one actor, 8–14s appearances, 18–35s gaps, leaving/cleanup/re-entry and no chase/damage. Test client rendering and asset permissions, not just a server attribute.
9. Export fresh native state/source, preserve a full native after-backup and publish only after verification. Confirm Roblox publication, then sync Git/Trello. Last verified publication before this task remains v2104.

## Checks

The draft scheduling test passes 1,031 assertions; lifecycle test passes29. Run with a Luau CLI:

```sh
/path/to/luau assets/level5/window-watcher/roblox-integration/qa/test_window_watcher_schedule.luau
python3 assets/level5/window-watcher/roblox-integration/qa/test_window_watcher_lifecycle.py /path/to/luau
```

Native evidence is under `artifacts/level5-window-watcher-20260925/`. All 182 live scripts still match the fresh pre-integration source snapshot; no runtime installation has been silently applied. Level 4 and the other developer's changes are preserved. The furnishing rerun passed 20 homes/891 parts/7,128 corners, 202 panes and 72 mold rays with zero failures.
