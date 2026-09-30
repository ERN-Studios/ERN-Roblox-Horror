# Level 6 Blender revision

The editable map is `Level6_Revised_Full_Seed101.blend`. Its main scene is
`Level 6 | Revised FULL seed 101 | 35 rooms`; nine `Revision study` scenes show
individual room styles. The nine PNGs in `previews/` are actual Blender renders.

This revision keeps all 32 original rooms, 37 original links and 189,656 square
studs of original room floor area. Three furnished, connected 18 × 24 × 12-stud
modules add a kitchen, utility workshop and staff break room, bringing room
floor area to 190,952 square studs. Original CD/CD-case/player instances remain.
The original 49 kit collections and original mesh vertex positions are retained.
The two new exterior openings retain wall stubs and lintels; unused module
ports are capped in the assembled map. Source `.blend` files are unchanged.

## Materials

`materials/` contains the four historical Level 3 carpet images, wallpaper and
orange wall color image copied byte-for-byte from the verified reference archive.
Current live Studio overrides have not been verified. The red wall uses a red
variant of the orange wall wear; the export includes its baked color image.
Kitchen tile and DiamondPlate are newly authored in the same worn 1990s palette.
The new utility room and Exit use DiamondPlate; kitchen surfaces use ivory/sage
ceramic tile. Arrival uses the default carpet, with city/neon/red carpets in
their respective districts. The original maintenance pocket remains part of
its red-carpet party room; standalone study 06 demonstrates the metal workshop
finish used in the new utility room. Arcade and supply-room carpets match
their district finishes in the full map and the corresponding studies.

Each surface has 1024-pixel color, grayscale height, OpenGL +Y normal and
roughness maps; DiamondPlate also has metalness. Blender uses the unchanged
source-resolution color artwork for the historical surfaces. Color images are
sRGB; data maps are Non-Color. Printed carpet motifs do not become raised shapes:
the height/normal maps describe microfiber pile independently of the artwork.
Height maps remain available for editing, while the baked normal is the active
shader route, avoiding duplicate relief. No fiber or tread displacement geometry
is added. Physical image repeats are recorded in `materials/material-manifest.json`.

Architecture is realized and scaled before UV mapping. Planar tile-boundary cuts
keep face UVs inside 0–1 while preserving physical repeat size. Night-world
lighting and fluorescent fixtures are present in the Blender map.

## Import assets and verification

`exports/Level6_Revised_ReusableKit.fbx` is the reusable kit in a separated
showroom layout, not the full assembled map. `Level6_Revised_ImportKit.blend` is
its compact, packed Blender counterpart. The export contains 61 kit names,
279 material-group meshes and 74,132 unique triangles; its largest mesh has
3,456 triangles. One Blender unit is one stud; export axis mapping is `(x,z,-y)`.
Keep `exports/` and `materials/` together so all FBX sidecar paths resolve.
`exports/import-manifest.json` records per-mesh maps, repeats, bounds and hashes.

Independent saved-file checks in `verification/` pass for source preservation,
packed maps, physical UV repeats, actual geometry at the new joins/interior
walkways, furnishing transforms and end caps. A fresh Blender FBX reimport
matches mesh/material counts, UVs, bounds and connected PBR map files; the raw
FBX contains finite normals, tangents and binormals on every geometry.

Codex authored and independently checked the package; Claude Opus 5.5 at max
effort provided a read-only design review. Its response and the documented
Roblox compatibility contract are in `review/`.

Studio MCP returned `Place is not open`. This is an offline Blender revision,
not a verified mirror of current Studio geometry. No Studio objects/scripts,
Level 3 routes, runtime generator, collisions or gameplay were edited, imported
or published. Seed 101 is preserved; the new modules have reusable connection
anchors for later generator integration. Roblox material import, collision,
gameplay and performance require a fresh open-place reconciliation and playtest.
Future integration must read current Studio instances and Source/editor baselines
and apply only the scoped Level 6 delta. Git is not a deployment baseline.

## Rebuild

Run `tools/level6_build/revision_materials.py` with Python, NumPy and Pillow,
then load `assets/level6-worn-party/Level6_FULL_Seed101.blend` in background
Blender and run `revision_build.py`. Load the resulting revised file in background
Blender to run `revision_render.py` or `revision_export.py`. All paths are
resolved relative to the repository; the original assets/reference archive
are required. No rebuild script writes to Studio.
