# Aero House

An original large, furnished, two-storey Frutiger Aero house made in Blender for Roblox import. The supplied references guided the glossy white, cyan, aqua and lime palette, rounded furniture, broad windows and quiet uncluttered rooms. There are no water surfaces, aquariums, particle systems or running scripts.

## Contents

- `AeroHouse.blend`: editable native project, with a separate presentation collection, cameras and lighting.
- `AeroHouse.glb`: primary Roblox import, with embedded palette/PBR textures.
- `AeroHouse.fbx`: fallback export with embedded textures.
- `textures/`: three shared 256×256 color/roughness/metallic maps. No external downloaded assets.
- `SetupAeroHouse.luau`: optional one-time Command Bar setup for the selected imported model. Creates simple collision geometry and four local lights, anchors the visual meshes, and handles imported yaw/translation using three small decorative geometry markers.
- `manifest.json`: exact mesh statistics, collision shapes, local lighting and dimensions.
- `verification.json`: offline geometry, GLB roundtrip and collision-route checks. Its runtime fields describe the pre-import checkpoint; see the live verification below for later Studio results.
- `previews/studio-exterior.jpg` and `previews/studio-lounge.jpg`: current screenshots of the furnished house in Roblox Studio, included in the import bundle. The repository also retains the initial Blender renders as PNGs; those precede the added wardrobes, TV, shelf and terrace furniture. Presentation lights and backdrop are excluded from the Roblox export.

## Rooms and layout

The ground floor contains a double-height cyan lounge, kitchen and dining area, guest bedroom, study and dry bathroom fixtures. A broad U-shaped staircase with a curved turn leads to two upper bedrooms, a lime reading lounge, an atrium gallery and an accessible front terrace. The exterior uses rounded white bands, sparse cyan trim, panoramic glazing, a skylight and a simple lawn plinth.

Simple matching furniture includes lounge seating and a coffee table, kitchen cabinets and a four-seat dining table, beds and bedside tables, a study desk and computer, and a reading sofa. The furnished revision adds a low media console with a rounded TV facing the main sofa, sliding-panel wardrobes at the edges of all three bedrooms, a study shelf with books, and two pedestal chairs with a round table on the terrace. Their white, cyan, aqua and lime finishes share the existing texture palette. Doorways and the main walking routes remain clear; furniture and appliances are decorative and do not run scripts.

The authored front is Blender negative Y. Ground-floor surface is Z=1; upper-floor surface is Z=18. Doorways are generally 7–10 studs wide. The entrance is intentionally open for walking. Doors, seats and appliances are static decorative geometry.

## Roblox import

1. In Studio, use **Import 3D** and choose `AeroHouse.glb`.
2. Set **Scale Unit: Studs**, **Anchored: on**, **Merge Meshes: off** and the scene-origin pivot option. Preserve mesh names and all three `Aero_Anchor_*` meshes. Import the complete model. The lawn/terrace bounds should be approximately **124 × 37.65 × 109 studs** (X/Y/Z).
3. Select only the complete imported Model. In Edit mode, paste/run `SetupAeroHouse.luau` in Studio's Command Bar. The script validates the untouched import and scale before it changes anything. It creates `AeroRuntime` under the house in one undoable operation. Undo that operation before rerunning it.
4. Move/rotate the **whole model**, including `AeroRuntime`, to place it. Put its lawn plinth above the experience's ground. The setup supports an upright house with translation/yaw and the documented stud scale.
5. Add or position your usual player spawn on a clear ground-floor or exterior walking surface. Keep normal workspace gravity (**196.2 studs/s²**) and run a Play test. The setup does not alter the experience's gravity, spawn, scripts, global lighting or other models.

The setup gives all static visuals `Anchored=true`, `CanCollide=false` and `RenderFidelity=Automatic`. It uses **192 invisible primitive collision Parts**, with ordinary floor/wall/furniture boxes and short oriented pieces for the stair turn. Glass casts no shadows; the four optional local lights have shadows disabled. Change `ENABLE_LOCAL_LIGHTS` to false before running setup if the experience already supplies sufficient lighting.

## Geometry budget and verification

| Measure | Final export |
| --- | ---: |
| Visual meshes | 88 |
| Total triangles | 53,128 |
| Largest mesh | 4,284 triangles |
| Shared imported materials | 3 |
| Shared source textures | 3 × 256×256 |
| Simple collision Parts after setup | 192 |
| Local lights after setup | 4 |

Offline validation passed: source topology/winding/normals, finite vertices, nonzero triangle area, one material and valid UVs per mesh; GLB reimport names/counts/bounds/surface areas; and **11 analytic collision routes with 1,760 samples**, including 423 stair samples and 5.5-stud head clearance. These route checks evaluate the authored collision data and are not a Roblox Humanoid simulation.

The additional furniture adds 2,680 triangles, one visual mesh batch and nine collision Parts. The budget is deliberately restrained, but total polygons alone cannot guarantee performance in an existing experience.

## Live Studio verification — 2026-09-29

The furnished house was successfully imported into place **121672571539226**, universe **10768500985**, with 88 visual meshes, 192 collision Parts and four local lights. Normal gravity remains **196.2 studs/s²**. The previous cathedral was preserved under `ServerStorage.AeroReplacementArchive.Vesper Cathedral`, with a full native place backup at `artifacts/aero-import-20260929/BeforeAeroReplacement.rbxl`.

An R15 avatar completed all **73 forward walking points in 38.8 seconds**, then all **72 reverse legs**, with no requested jumps, teleports or health loss. See the [forward walkthrough](../../../artifacts/aero-import-20260929/walk-result.json) and [return walkthrough](../../../artifacts/aero-import-20260929/return-walk-result.json). These checks exercise the stairs, rooms and terrace in Play mode.

A [30-second local client sample](../../../artifacts/aero-import-20260929/client-performance.json) during movement observed approximately **41.03 render events/second**, with a **33.93 ms p95 render interval**, at maximum quality and a 2173×1023 viewport. Reported memory was approximately **3,401–3,406 MB for the whole Studio process**, not the house's allocation. These are measurements from this desktop session, not a performance guarantee or a house-only before/after comparison. **Mobile and multiplayer performance remain unverified.** No publication is claimed by this asset package.

Roblox's current [mesh specifications](https://create.roblox.com/docs/art/modeling/specifications) allow up to 20,000 triangles per mesh. This package stays well below that per mesh. See the official [3D importer settings](https://create.roblox.com/docs/studio/importer), [texture specifications](https://create.roblox.com/docs/art/modeling/texture-specifications), and [performance guidance](https://create.roblox.com/docs/performance-optimization/improve) for the project-side checks.

## Rebuild and verify

From the repository root, run the installed Blender binary with:

```sh
Blender -b --factory-startup --python tools/build_aero_house.py
Blender -b assets/models/aero-house/AeroHouse.blend --python tools/verify_aero_house.py
Blender -b assets/models/aero-house/AeroHouse.blend --python tools/render_aero_house.py
```

`tools/aero_house_furniture.py` supplies the furnishings. `tools/aero_house_setup_template.luau` is filled with the final manifest to create the packaged setup. The build runs in a separate background Blender process; it does not replace any existing live scene. All source geometry is authored specifically for this house.

The packaged setup was successfully compiled with Studio's Luau compiler without executing it. `tools/package_aero_house.py` checks the final source/export hashes and packages only the listed deliverables, excluding Blender backup files and caches.
