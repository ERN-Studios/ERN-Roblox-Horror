# Level 6 Studio material audit

Inspected the authoritative Edit place `131311258779917` in universe
`10559217407` (group `1039373905`). The existing `MaterialService` has Level 2
and Level 5 variants and no Level 6 variant. No Studio place instances were
changed during this audit. Capability probes used only unparented temporary
instances and confirmed plugin-context writes to all four PBR map fields on
`MaterialVariant`, `SurfaceAppearance`, and `Texture`.

The Blender import manifest contains 279 material-split mesh segments across
61 reusable assets. Twenty segments need nine material treatments: four
carpets, beige wallpaper, orange wall, red wall, diamondplate, and kitchen
tile. Red wall uses its own baked color image and shares the orange wall
normal and roughness images. The remaining 259 segments use one props atlas.
The deduplicated upload list has 27 PNGs. Grayscale height files and archived
source colors are Blender authoring inputs, not Studio PBR maps. Exact source
paths and SHA-256 values are in `material-routes.json`.

`MaterialVariant` with `StudsPerTile` is the chosen route for architecture:
the live Visual Adapter changes room floor, wall, and corridor mesh sizes, so
fixed 0–1 UV `SurfaceAppearance` would stretch the tile as those meshes grow.
All nine variants use `SmoothPlastic` as their base; the visible meshes are
noncollidable and the PBR maps supply the intended surface. Runtime mesh
segments must set `Material=SmoothPlastic`, then set their matching variant
name; the props segments instead use the atlas in `MeshPart.TextureID`.
The runtime script can assign a variant by name, while map fields require the
Edit plugin context and must be installed in `MaterialService` beforehand.

An Edit/plugin capability probe does not establish rendered appearance.
`MaterialVariant` tiles from each MeshPart's center, so neighboring panels
may have a phase seam even when their stud repeat size matches. Imported
mesh tangent generation, raised normal direction, map access permissions,
and texture memory also require a target-place visual/runtime check before
publication. The documented alternatives are a plugin-authored tiled `Texture`
on suitable flat faces, or mesh UV splitting with `SurfaceAppearance`.

Primary Roblox references: [custom materials](https://create.roblox.com/docs/parts/materials),
[MaterialVariant API](https://create.roblox.com/docs/reference/engine/classes/MaterialVariant),
[mesh materials](https://create.roblox.com/docs/parts/meshes),
[PBR texture requirements](https://create.roblox.com/docs/art/modeling/texture-specifications),
and [SurfaceAppearance](https://create.roblox.com/docs/art/modeling/surface-appearance).
