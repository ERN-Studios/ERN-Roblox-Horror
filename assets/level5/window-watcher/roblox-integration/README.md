# Window Watcher — Roblox integration

**Status 2026-09-26:** the permanent rig, published animation assets, intermittent encounter module, Adapter hook and scoped client visibility guard are installed in Studio Edit. The CreateAssetAsync beta blocker is resolved. Final runtime QA, experience publication and delivery receipts are recorded in the [main handoff](../../../../docs/LEVEL5_WINDOW_WATCHER_2026-09-25.md); asset publication alone does not establish that the updated experience is live.

The exact Meshy GLB is converted to 8,996 UV-split vertices, 11,862 triangles and 25 bones. The three published clips passed 300 native bone/time comparisons with maximum matrix-component error below 0.000194 (tolerance 0.001). Earlier temporary-ID checks remain historical evidence.

| Durable asset | Roblox ID |
| --- | --- |
| Skinned mesh | `138178192370575` |
| WatchingIdle | `123386867650430` |
| SlowWindowLean | `85635358459792` |
| GlassTap | `85948818863545` |

The mesh and animations belong to group 1039373905. The existing base-color image `91091934459636` and eye-mask image `91743869995723` are reused. The client guard waits for the matching official track to load, advance and evaluate a non-bind pose before allowing local visibility; server encounter timing remains authoritative. No chase or damage is added.

## White eyes

The installed material uses `tools/install_watcher_eyes.luau` and mask `rbxassetid://91743869995723` (v5; SHA 99315f05889bbc4c9f1122f502913bef7bf3fd5d7742b2a5a30ded79fee45738). The measured .067-stud iris cores use SurfaceAppearance emission on the real skin, so they follow every head pose without a frame loop or extra lights. Strength 200 was visually checked; original albedo is dark in the iris and strengths 15–30 remained gray. Billboard eyes were rejected because tinted Glass occluded them. Native Play inspection showed the dark body and white eyes through the real window during the tap gesture.

V5 guards neighboring brow UV islands. This is not a guarantee against all texture-filtering artifacts; use the main handoff's final visual QA result. No body geometry, albedo, bone bases or original Blender source was changed.

## Recovery and source ownership

Studio remains authoritative. Reconcile its fresh Source/editor bytes before any further installation. The files under `patches/` preserve the 25 September proposals and are not the authoritative installed source. Use fresh Studio source mirrors for the encounter module, Adapter and new visual client; do not overwrite them with these older drafts. The earlier `tools/staging/level5_window_watcher_preview.luau` is also superseded.

The following steps document recovery, not a request to upload duplicate assets or reinstall a working rig. Reuse the durable IDs above. The temporary `buildPreview()` path still creates transient content and must never substitute for the permanent mesh.

## Rebuild procedure

1. From repository root, regenerate if needed: `python3 assets/level5/window-watcher/roblox-integration/mesh-import/convert_exact_glb.py --source assets/level5/window-watcher`. Inputs are hash-pinned. The existing generated chunks are identical and ready.
2. Run `python3 assets/level5/window-watcher/roblox-integration/tools/local_bridge.py` (localhost:8769, task files only). Temporarily enable Studio HttpService for each bounded import call and restore the original value afterward.
3. Execute the reviewed `mesh-import/import_exact_mesh.luau` as a module in Studio Edit. Call begin with `http://127.0.0.1:8769/mesh-import/`, six nextVertices calls and four nextFaces calls.
4. `publishMesh()` uploads to ERN Roblox Studios group 1039373905. `verifyPublished()` must pass before `buildRuntime()`. `buildPreview()` is explicitly temporary and must be discarded before saving/publishing the place.
5. `buildRuntime(91091934459636)`, then apply white eyes with the final mask/strength. Inspect original UVs, skin, scale and eye filtering. Name the model WindowWatcherRig under a new ServerStorage.Level5WindowWatcher folder.
6. `tools/publish_watcher_clips.luau` creates real group-owned Animation assets and sibling Animations instances. All three complete gestures intentionally loop; their endpoints match. Record actual IDs.
7. Restore the reviewed current encounter module, Adapter hook and client visibility guard from their authoritative source mirrors. Reconcile against fresh Studio bytes; do not use the older `patches/` proposals as replacements.
8. Enter through Level5DevStart/normal developer queue, inspect all three real windows, animation curves and eye visibility; verify one actor, 8–14s appearances, 18–35s gaps, leaving/cleanup/re-entry and no chase/damage. Test client rendering and asset permissions, not just a server attribute.
9. Export fresh native state/source, preserve a full native after-backup and publish only after verification. Confirm Roblox publication, then sync Git/Trello. The main handoff records the current verified receipt.

## Checks

The 25 September draft passed 1,031 scheduling assertions and 29 lifecycle assertions. These tests cover their draft source version; current guard/runtime QA is separate. Run the historical tests with a Luau CLI:

```sh
/path/to/luau assets/level5/window-watcher/roblox-integration/qa/test_window_watcher_schedule.luau
python3 assets/level5/window-watcher/roblox-integration/qa/test_window_watcher_lifecycle.py /path/to/luau
```

Historical native evidence is under `artifacts/level5-window-watcher-20260925/`. The fresh pre-integration baseline matched all 182 scripts; integration adds the encounter module and visual client and updates the Adapter. Use the main handoff for final 184-script parity and native server/client results. Level 4 and the other developer's work are preserved. The earlier furnishing rerun passed 20 homes/891 parts/7,128 corners, 202 panes and 72 mold rays with zero failures.
