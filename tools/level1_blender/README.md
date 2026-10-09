# Level 1 Blender room kit

`build.py` authors an independent project from
`assets/level1/blender/concepts/room-direction.png`. It never connects to the
running Blender session or Studio. All 30 architectural components and props
are modelled in Blender, with shared physically scaled UVs. The native project
contains 34 named room collections, the shared component gallery and cinematic
review scenes. The FBX exports each shared component once; the manifest records
how rooms assemble them.

```powershell
& D:/Blender/blender.exe -b --factory-startup --python-exit-code 1 -P tools/level1_blender/build.py
python tools/level1_blender/check_assets.py
& D:/Blender/blender.exe -b assets/level1/blender/Level1_ModularKit.blend --python-exit-code 1 -P tools/level1_blender/verify_native.py
python tools/level1_blender/import_assets.py
```

Assets: `assets/level1/blender/Level1_ModularKit.blend`, `.fbx`, `textures/`,
`renders/` and `export/manifest.json`. Native file hashes are in
`native-files.json`; actual Blender/FBX verification is in
`native-verification.json`. No native backups are made, as requested by the
owner. `check_assets.py` verifies binary indices, finite attributes, hashes,
socket masks, central column clearance, required prop names and PBR maps.

Room origins sit at the cell's floor centre. Cell size is 24 studs, wall height
14, full wall thickness 2. Room walls are half-walls, 1 stud deep, positioned
11.5 studs from the centre so neighbours join at the cell boundary. Open sockets
use bits N(+Z)=1, E(+X)=2, S(-Z)=4, W(-X)=8. The 15 possible connected masks each
have a quiet and a column variant; maintenance, office, records and elevator
pockets add four recognisable variants. Decorative columns remain outside the
central 16×16 square and cardinal navigation lanes.

`import_assets.py` defaults to writing a reviewable installer; it does not
connect to Studio without `--upload` or `--install`. Both require an exact
`--studio-id` and bind the destination place ID. The upload uses the existing
Level 4 binary mesh builder without modifying any Level 4 file. Receipts are
specific to this kit and content hash. Its installer refuses to overwrite an
existing `ServerStorage.Level1BlenderKit`; components are staged off-tree and
marked Ready only after every mesh, texture and room has loaded. PBR image
receipts may come from `textures/published.json` (file hashes checked) or a
filename-to-content-ID map in `textures/roblox-assets.json`.

All room meshes receive a `RoomRole` attribute (`SurfaceFloor`,
`SurfaceCeiling`, `ShellWalls`, `Fixture`, `Detail`), so pits can suppress only
the new floor visual. Extra props and pillars receive simple invisible Decor
colliders; the original maze keeps floor, wall and ceiling collision. Dynamic
objective skins preserve the live game's interaction proxies and need no second
collider. The renderer and preview access scripts live outside this asset tool.

These asset checks do not certify live gameplay, navigation, multiplayer,
performance or developer access. Those require the actual current Studio game.

## Quality revision V2

`build_v2.py` reuses the component builder and authors `assets/level1/blender-v2`.
Its Imagegen references are in `concept/prompts.json`. The exact original
wallpaper asset `87947439437597` supplies unchanged albedo pixels; material tint
and derived normal/roughness maps provide the stronger yellow finish. The new
kit contains 42 weighted room variants, 41 shared components, five-channel
grille fixtures, rare columns, short internal dividers and mechanical props.

```powershell
python tools/level1_blender/check_assets.py --assets assets/level1/blender-v2
& D:/Blender/blender.exe -b assets/level1/blender-v2/Level1_ModularKit.blend --python-exit-code 1 -P tools/level1_blender/verify_native.py -- --assets assets/level1/blender-v2
python tools/level1_blender/publish_textures.py --assets assets/level1/blender-v2
python tools/level1_blender/import_assets.py --assets assets/level1/blender-v2 --kit-name Level1BlenderKitV2
```

Upload/install still require the explicit action flag and exact Studio ID.
Existing mesh assets are reused only when their binary wire hash matches.
The independent V2 kit leaves the existing V1 kit intact and creates no backup.
Source changes use fresh scoped Source/editor CAS, and shared Play/publication
ownership is recorded in `artifacts/level1-quality-20261002/coordination.md`.


The final V2 Studio seed 5 audit passes 122 checks in both locked and open exit
states, including 1,600 connected rooms, matching PBR/mesh identities, original
five-channel lamp geometry, physical low dividers, cable clearance and the
cropped exit aperture. The original trigger escape and reset were exercised;
two post-fix resets retain zero Animation children/playing tracks and one owned
release callback. Records and the current bounded QA summary are in
`artifacts/level1-quality-20261002/current-qa-summary.md`. Objective setup used
assisted actor positioning and existing developer pause; multiplayer, mobile,
server CPU and full-height overhead cable coverage remain unverified. These
checks do not themselves establish publication.
