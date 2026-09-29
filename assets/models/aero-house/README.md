# Aero House

An original large, furnished, two-storey Frutiger Aero house made in Blender for Roblox import. The supplied references guided the glossy white, cyan, aqua and lime palette, rounded furniture, broad windows and quiet uncluttered rooms. There are no water surfaces, aquariums, particle systems or running scripts.

## Contents

- `AeroHouse.blend`: editable native project, with a separate presentation collection, cameras and lighting.
- `AeroHouse.glb`: primary Roblox import, with embedded palette/PBR textures.
- `AeroHouse.fbx`: fallback export with embedded textures.
- `textures/`: three shared 256×256 color/roughness/metallic maps. No external downloaded assets.
- `SetupAeroHouse.luau`: optional one-time Command Bar setup for the selected imported model. Creates simple collision geometry and four local lights, anchors the visual meshes, and handles imported yaw/translation using three small decorative geometry markers.
- `manifest.json`: exact mesh statistics, collision shapes, local lighting and dimensions.
- `verification.json`: offline geometry, GLB roundtrip and collision-route checks.
- `previews/`: rendered views of the authored model. Presentation lights and backdrop are excluded from the Roblox export.

## Rooms and layout

The ground floor contains a double-height cyan lounge, kitchen and dining area, guest bedroom, study and dry bathroom fixtures. A broad U-shaped staircase with a curved turn leads to two upper bedrooms, a lime reading lounge, an atrium gallery and an accessible front terrace. The exterior uses rounded white bands, sparse cyan trim, panoramic glazing, a skylight and a simple lawn plinth.

The authored front is Blender negative Y. Ground-floor surface is Z=1; upper-floor surface is Z=18. Doorways are generally 7–10 studs wide. The entrance is intentionally open for walking. Doors, seats and appliances are static decorative geometry.

## Roblox import

1. In Studio, use **Import 3D** and choose `AeroHouse.glb`.
2. Set **Scale Unit: Studs**, **Anchored: on**, **Merge Meshes: off** and the scene-origin pivot option. Preserve mesh names and all three `Aero_Anchor_*` meshes. Import the complete model. The lawn/terrace bounds should be approximately **124 × 37.65 × 109 studs** (X/Y/Z).
3. Select only the complete imported Model. In Edit mode, paste/run `SetupAeroHouse.luau` in Studio's Command Bar. The script validates the untouched import and scale before it changes anything. It creates `AeroRuntime` under the house in one undoable operation. Undo that operation before rerunning it.
4. Move/rotate the **whole model**, including `AeroRuntime`, to place it. Put its lawn plinth above the experience's ground. The setup supports an upright house with translation/yaw and the documented stud scale.
5. Add or position your usual player spawn on a clear ground-floor or exterior walking surface. Keep normal workspace gravity (**196.2 studs/s²**) and run a Play test. The setup does not alter the experience's gravity, spawn, scripts, global lighting or other models.

The setup gives all static visuals `Anchored=true`, `CanCollide=false` and `RenderFidelity=Automatic`. It uses **183 invisible primitive collision Parts**, with ordinary floor/wall/furniture boxes and short oriented pieces for the stair turn. Glass casts no shadows; the four optional local lights have shadows disabled. Change `ENABLE_LOCAL_LIGHTS` to false before running setup if the experience already supplies sufficient lighting.

## Geometry budget and verification

| Measure | Final export |
| --- | ---: |
| Visual meshes | 87 |
| Total triangles | 50,448 |
| Largest mesh | 3,716 triangles |
| Shared imported materials | 3 |
| Shared source textures | 3 × 256×256 |
| Simple collision Parts after setup | 183 |
| Local lights after setup | 4 |

Offline validation passed: source topology/winding/normals, finite vertices, nonzero triangle area, one material and valid UVs per mesh; GLB reimport names/counts/bounds/surface areas; and **11 analytic collision routes with 1,760 samples**, including 423 stair samples and 5.5-stud head clearance. These route checks evaluate the authored collision data and are not a Roblox Humanoid simulation.

**Actual Studio import, Play-mode walking, frame time, memory, mobile performance and multiplayer performance remain unverified.** The budget is deliberately restrained, but total polygons alone cannot guarantee performance in an existing experience. No live Studio place was changed or published for this asset task.

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
