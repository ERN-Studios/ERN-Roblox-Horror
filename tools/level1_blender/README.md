# Level 1 Blender authoring

The active room kit is `Level1BlenderKitV2`, authored by `build_v2.py` in an
independent headless Blender. The separate elevator workflow uses
`elevator_inset.py` and `import_elevator_inset.py` to produce
`Level1ElevatorInsetKit`. `build.py` retains their shared mesh, material, room,
UV, export and render helpers; its standalone legacy build entry is retired.

```powershell
python tools/level1_blender/prepare_v2_textures.py
& D:/Blender/blender.exe -b --factory-startup --python-exit-code 1 -P tools/level1_blender/build_v2.py
python tools/level1_blender/check_assets.py
& D:/Blender/blender.exe -b assets/level1/blender-v2/Level1_ModularKit.blend --python-exit-code 1 -P tools/level1_blender/verify_native.py
python tools/level1_blender/import_assets.py
```

Check, native QA, texture publication and room import default to
`assets/level1/blender-v2`. Explicit old `assets/level1/blender` public workflow
targets and `Level1BlenderKit` installation are retired. Keep that historical
asset tree: V2 still reuses carpet/ceiling pixels and matching old mesh/texture
receipts. No receipt IDs or uploaded assets are retired by this tool change.

The V2 kit contains 42 weighted room variants and 41 shared components. It
preserves the exact original wallpaper asset `87947439437597`, five-channel
grille fixtures, rare columns, short dividers and mechanical props. Room cells
remain 24 studs, wall height 14, full wall thickness 2; cardinal socket masks
and collision authority stay with the original gameplay Parts. Decorative
columns remain outside the central clear square and navigation lanes.

`import_assets.py` prepares a reviewable V2 installer without connecting to
Studio. Upload/install require an explicit action flag and exact `--studio-id`.
Installers refuse an existing target kit and stage their components off-tree.
Existing meshes are reused only when their binary wire hash matches; PBR
receipts in `textures/published.json` are checked against actual file hashes.
The shared INSTALL template's old kit token remains an elevator substitution
placeholder, not a public legacy install target.

```powershell
& D:/Blender/blender.exe -b --factory-startup --python-exit-code 1 -P tools/level1_blender/elevator_inset.py
python tools/level1_blender/import_elevator_inset.py
python tools/level1_blender/publish_textures.py --assets assets/level1/elevator-inset-20261004
```

Elevator fixed-size prefabs, UVs, assembly pivots and existing physical door/
collision proxies remain independent of the room kit. Both publication
workflows retain resumable texture receipts. Running a texture publisher can
upload missing maps; run it only when that external action is authorized.

`tools/export_level1_facelift_verified.py` exports the V2 kit and its seven
script/editor records. `--revision-v2` remains a compatibility alias. Use a new
`--output` directory for evidence and `--run` only for an authorized fresh
Studio Edit read. `install_sources.py` is an active gameplay source tool and
is outside this retirement.

These authoring checks do not establish gameplay, navigation, multiplayer,
streaming, performance or publication. Historical V2 Studio checks and their
limits remain in `artifacts/level1-quality-20261002/current-qa-summary.md`.
