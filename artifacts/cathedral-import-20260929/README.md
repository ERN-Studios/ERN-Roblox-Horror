# Vesper Cathedral — playable Studio import

Imported into `Untitled Experience`, place `121672571539226`, universe `10768500985`, on 2026-09-29. The authoritative Studio scene contains one cathedral Model, the existing baseplate, and the existing spawn moved to the forecourt. The Backrooms experience was not changed.

Open `VesperCathedral_Playable.rbxl` in Roblox Studio and press Play. The cathedral is anchored, uses 114 simple collision parts and 12 local lights, and keeps standard gravity (196.2). The avatar remains unanchored and uses ordinary Roblox movement. The complete native place is also in `/Users/zeanjuul4/Downloads/VesperCathedral_20260929/`, alongside the Blender and GLB files.

All 104 visual meshes and their SurfaceAppearance assets uploaded successfully. Eleven live raycasts verified floor and stair heights. A fresh-spawn R15 Play test walked all 24 waypoints through the entrance, nave, altar steps and both side aisles, with 100 health, no teleporting and no requested jumps. See `walk-test-result.json`; `walk-test.luau` is the bounded test used in the temporary Play server, not a gameplay script. No scripts were installed. Multiplayer, mobile performance and published servers were not tested.

`BeforeCathedralImport.rbxl` is the full original Studio backup. `verified-studio-manifest.json` records exact instance paths, classes, transforms, properties and asset IDs after the import. Script/editor-source lists are empty. The native place, manifest, screenshots and test results were captured from Studio; source-only data is not used as a substitute for the native backup.

The importer baked a 180-degree yaw with World Forward = Front. The imported geometry was normalized to the authored +Z entrance and its pivot reset before the original collision metadata was applied. `applied-setup.luau` records that scoped adaptation and uses Studio MCP's existing undo recording. Do not blindly run it on another Model: its assertions intentionally require this untouched import baseline. The ready-to-play native place already has the correct orientation and setup.

Save to Roblox was invoked; Studio displayed a save timestamp of 29 Sep 2026 19:59. No Publish action was performed. This new experience is outside the standing Backrooms publication instruction. The latest local native backup is independently present and hashed in `import-record.json`.

The current Blender source had a pre-existing binary modification. Its mesh topology, UVs, materials and geometry matched the original export; it was reopened, copied to Downloads and preserved, without committing that unrelated source-file change. The repository has no configured remote; task commits are local and are not GitHub pushes.
