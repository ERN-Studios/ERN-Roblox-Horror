# R4 Blender and live bay audit

Read-only audit on 2026-10-01. Studio instance `08b776ed-0330-44f6-8378-c6eea82b3f38`, authoritative place `131311258779917`. Current Builder and original TunnelLobbyBuilder had Source/editor parity. No Studio/Blender/UI edits, Play movement, publication, or performance certification were performed by this audit.

## Latest starting assets

- `assets/models/lobby-reimagined-r3-20261001/LobbyReimaginedPreview.blend`, SHA `768045ae70b97407d57fb44a9827298905c17641a845a5ae2d2561b8f166ea36`.
- `tools/lobby_reimagined/build.py` builds the geometry and assembled scene; `props.py` authors furniture/DJ/truss kit.
- `tools/lobby_reimagined/runtime_bake.ModuleScript.luau` currently imports a single MeshPart per family, one baked color atlas; `preview_builder.ModuleScript.luau` assembles the live preview.
- The revised preview remains offset at `(220,30,-760)` beside the original. Current Edit does not contain its generated runtime model. Archived actual R3 Play screenshots were reviewed, including `r3b-axis-final.jpg` and `r3-bay1-entrance.jpg`; these are evidence of the R3 appearance, not a fresh R4 Play test.
- Live Blender MCP returned “Could not connect to Blender.” The current scene was not opened or changed.

## Why R3 looks poor

1. **All six bays reuse the same orange room.** `QueueRoom` has orange walls, generic dark carpet with oversized orange marks, generic concrete ceiling, and teal fixtures. The current Builder has no distinct bay theme. This loses the original game’s most recognizable lobby feature.
2. **Incorrect material export design.** The 1024 atlas provides only 128×128 pixels per material. Every polygon is normalized independently into its material tile. A tiny face and a 40-stud panel therefore repeat the same pattern once, with inconsistent scale and stretched noise. The real material repeat and aggregate size are absent. There are no normal or roughness maps. Blender bump nodes alone would not solve the Roblox result.
3. **Hard curved shading.** `Geometry.arc` emits independently duplicated faces for every segment, including internal end faces. The 36-segment shell uses flat polygon normals, which the binary exporter correctly preserves. The shell contour is approximately circular, but its shading reads as faceted strips; increasing segment count without shared vertices and smooth normals leaves the fundamental problem.
4. **Queue stations were simplified too far.** Original pads have rounded wall monitors, mounting arms, and a different arrangement. R3 replaces them with small freestanding kiosks, losing the original silhouette, readable status surfaces, and room composition.
5. **Flat surfaces dominate the whole view.** Archived R3 Play shows washed yellow walls, smooth blue-grey asphalt, a uniformly patterned sidewalk, and evenly repeated tiny props. Details exist, but the construction and material hierarchy are weak.

## Exact original bay references

Fresh live properties are in `live-original-bay-geometry.json` and `live-original-bay-models.json`. Current Source excerpts are in `live-original-style-functions.json`; geometry takes precedence when the two differ.

| Level | Actual original style to recreate in Blender |
|---|---|
| 1 | Yellow Backrooms wallpaper (`87947439437597`, repeat 6), brown carpet (`100093931957721`, repeat 6), office drop ceiling (`91804597609254`, repeat 8), broad fluorescent panels, abandoned office chairs, wall-glitched chair and filing cabinet. |
| 2 | Cream/pale-green Poolrooms tiles (`113211706146395`, repeat 7), tiled column with flares, stainless ladder, shallow water surface, lounger, pool ball and wall-glitched noodle. Existing live geometry is style version 1 while current Source describes version 2; use live arrangement, not an unrequested rebuild of the original. |
| 3 | Black confetti carpet (`110230144446272`, repeat 22), orange plaster (`128270554927663`, repeat 22), ceiling grid, mismatched fluorescent panels with one dead, folding table with confetti cloth (`103412925025303`), mismatched chairs, and three balloons. |
| 4 | The original current bay is generic concrete with no distinct level decor. Read the active Level 4 map before proposing its new style; do not label a guessed style an exact reproduction. |
| 5 | Indoor Suburbs: cream/sage/pale domestic fronts, closed doors and brass handles, house numbers, pitched porch canopies, warm sconces, white framed dark recessed windows, balcony and white pickets. Actual `Level5AgedPlaster`, `Level5FloralWallpaper`, `Level5PaintedSiding`, `Level5VeneerWood`, and `Level5LoopCarpet` variants already have PBR routes. |
| 6 | The original current bay is generic concrete with no distinct level decor. A new preview should use current Level 6 saturated 1990s mall-party materials and furniture, deliberately distinct from Level 3. |

Original circular bay walls advertise diameter 56; floor and ceiling cylinders actually measure 59. Original Level 3 queue pad offsets from room center are **X ±9 / Z ±13.2**, diameter **14.82**, circular detector radius **7.41**. Wall monitor sign size is **12.18 × 4.34 × .08**, mounted approximately **7.88 studs above the chamber floor center** on visible articulated arms. R3 instead uses ±11/±9 pad offsets and approximately 1.45×1.28 status surfaces. The additional all-level pad inventory request stalled, so those exact measurements are established from the fresh Level 3 read, not certified across every other bay.

## Recommended implementation

### Rebuild the shell as a continuous surface

Author a connected semicircular tunnel grid with **96–128 segments per half circle**, radial smooth normals on the inner and outer curved surfaces, hard sharp normals only on cut/trim/end surfaces, and no internal coplanar faces. Use matching shared segment positions at every 40-stud module boundary. Preserve the genuine portal cutouts, connector clearance, separate shell thickness and closed end caps. At radius 35, 128 segments gives under .003-stud chord error; smooth shading and consistent cylindrical UVs matter more than extra triangles. Apply the same curvature discipline to ribs and bay walls. Bevel visible steel lips modestly (.03–.08 studs) instead of random boxes.

Keep collider proxies separate from the cosmetic meshes. Do not increase collision detail merely to match visual segment count; verify the portal aperture and floor edges by normal Humanoid walking and Include-world raycasts. No silhouette should depend on a double-sided fallback hiding inverted winding.

### Real bump/PBR maps, with stable physical scale

Split architecture into **one surface/material per chunk**: concrete shell, asphalt, sidewalk/curb, steel ribs, painted lane markings, and each bay floor/wall/ceiling. Use multi-part family Models rather than collapsing every material into one textured MeshPart. Reuse the already implemented Level 6 `MaterialVariant` + uploaded maps route from `tools/level6_build/import/Level6BlenderRuntimeBake.ModuleScript.luau`; adapt its guarded route and manifest, not its fixed Level 6 counts/hashes. Clear TextureID on PBR architectural pieces so the old atlas does not mask or compound the material. Keep the props atlas separate.

Proposed starting values, to tune in actual Play:

- Concrete: aged warm beige aggregate, 8–14-stud tile, roughness .72–.88, metalness 0. Fine pores and shallow pits in the normal map; a separate broad stain layer at 20–40-stud scale avoids coarse pepper-like dots. A restrained .02–.05-stud equivalent bump impression is enough.
- Asphalt: dark neutral aggregate, 4–8-stud tile, roughness .85–.96, metalness 0. Fine aggregate normal; broad tire wear and patched areas should be color/roughness variation. Keep lane paint a separate chunk with consistent paint roughness and occasional edge wear.
- Sidewalk: 5–8-stud slab repeat, roughness .76–.9, metalness 0. Fine aggregate normal plus real shallow joints, curb edge chips and drain details. Avoid widening the dark joints into a grid that competes with the gates.
- Normal maps should be OpenGL tangent-space, correctly marked Non-Color in Blender; roughness/height also Non-Color. Preserve Color maps as sRGB. Bake/export the actual maps; a procedural shader graph is not an importable Roblox bump result.

For uniquely UV-authored trim/props, an installed SurfaceAppearance is appropriate if the verified Studio import route supplies it; do not assume game Scripts can write its protected map properties. Reusable tileable MaterialVariant is the lower-risk established route here. Official docs: [materials](https://create.roblox.com/docs/parts/materials), [PBR maps](https://create.roblox.com/docs/art/modeling/surface-appearance).

### Restore the authored bay compositions

Create distinct Blender families for each level’s shell surfaces and rear furniture/decor, plus a shared rounded monitor/arm kit. Preserve the four-pad spacing and clear center aisle. Recreate original L1/L2/L3/L5 silhouettes with more measured edges, better material depth and restrained wear. Do not clutter the foreground or detector footprints. Use per-level fixture shapes and warm/cool lighting that match each map, rather than tinting a single generic bay.

Keep the existing QueueBridge/GameManager contract: IDs 101–124, `QueueBay_LevelN`, `R3QueueId`, `R3QueueRevision=3`, direct `ChamberFloor` parent, valid circular detector radius, `QueueRenderOwner`, `QueueTitle`, `QueueSubtitle`, and developer entry attributes. New larger wall monitor labels can live beneath the same station/render owner. Rebuilding visuals does not require changing admission/countdown/launch policy. Preserve DEV authorization and streaming/floor checks for Levels 4–6.

Keep the existing ten hologram fade bands, active ring and reduced-motion behavior. Their triangles/transparent overdraw already exist; avoid doubling them with an extra cosmetic cylinder. Preserve the separate vinyl discs rotating at 12°/second and the static tonearms/needles in the console. The console and speaker kit already contain the required DJ/festival shapes; refine grounding, cable runs and stage lighting instead of rebuilding working behavior.

### Budget and verification

Current kit: **37 chunks, 45,812 unique triangles, 260 placed meshes, 153,484 placed triangles, 703 colliders**. This is a record, not a performance pass. A smoother shell and six distinct bays can stay around 200–250k placed triangles by reusing modules and avoiding displacement geometry. Current DJ console is 9,844 triangles; each vinyl is 2,824 and each speaker tower is 5,820. Consider baking vinyl groove detail and simplifying unobservable underside details before adding large mesh counts elsewhere.

After applying from a fresh Studio/editor baseline, test every bay from both tunnel approaches, mounted sign readability, pad enter/leave/host/join/cancel/countdown/launch, DEV previews, shop focus, hologram fade/reset, stage ascent, disc rotation/static needles, seams, ceiling leaks and collision. Inspect actual normal-player close and distant views. Capture matching before/after views, native before/after backups, scoped source/property receipts, and commit/publish only the verified change. Multiplayer, mobile and isolated performance cannot be claimed from this read-only audit.

## Claude review attempt

The installed Claude CLI advertises model `claude-opus-5-5` and effort `max` (no `ultra` flag). A no-tool, strict-MCP, bounded read-only design review was attempted with the evidence above, but timed out after 180.24 seconds without a review result. `claude-design-prompt.txt` records the submitted brief. This is an attempted collaboration, not a completed Claude analysis; root should retry the requested collaboration when beginning implementation.
