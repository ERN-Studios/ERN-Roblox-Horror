# Level 2 wall lamps — BACKROOMS: STAY QUIET

Rebuild from the project folder (one Blender process at a time):

```sh
/Applications/Blender.app/Contents/MacOS/Blender --factory-startup -b --python work/build_props.py
```

Use `-- --skip-renders` for the deterministic JSON / blend rebuild only. All asset vertices are generated in the script; no downloaded assets, textures or fonts. The saved blend has an `Assets` scene displaying both assemblies apart through collection instances, and a separate `Preview` scene with the five named source mesh objects, tiled wall, camera and lights. The opening scene is `Assets`; the five source objects remain at zero with shared wall origins. Preview geometry is excluded from JSON.

## Units, placement and dimensions

One Blender unit = one Roblox stud. The level scale is **2.86 studs/metre**. Blender wall plane is **X–Z at Y=0**, X right, Z up, room/front **−Y**. All object origins are **(0,0,0)** on this wall plane. No asset vertex lies behind it; there are **no deliberate wall recesses**.

Export axes: **Roblox X=Blender X, Roblox Y=Blender Z, Roblox Z=Blender Y**. Thus wall Z=0, front −Z. This permutation reflects orientation, so every triangle has B/C swapped. Do not apply the old sign script's minus on Blender Y. When using the reference template, position each MeshPart at its `middle` relative to the assembly's wall origin, preserving the exported `size`.

Pool outside diameter **1.40**, lens rim radius **0.52**, total projection **0.14**. Inner lip depth **0.05**, lens crown **0.14**: rise **0.09**. The bezel is 24-sided, the lens 20-sided, and the eight six-sided countersunk heads are on the face at radius 0.603. A 0.012-stud backplate closes the recess; the lip has two angular rolled slopes. Five prismatic teeth surround a smooth central boss.

Exit housing is **about 1.10 wide × 0.62 high**, with the **0.35** upward conduit seated **0.04** into the housing, making complete height **0.93**. Complete depth is **about 0.50**. Origin is the centre of the complete projected footprint, including conduit; housing/lens centre is Blender Z=−0.155 (Roblox Y=−0.155). Conduit radius **0.12** throughout; its complete length is 0.35. Two perpendicular six-sided wire hoops and an oval wire rim have radius **0.022**. The nearest crown wire surface is at least **0.05** beyond the lens, while shoulder spacing is larger. Fixing ears, screws, conduit and crossing wires are overlapping **individually closed shells**, not boolean unions.

## Export numbers

`props.json` has `meshes[name]` with the exact four arrays the supplied `install_sign.py` **UPLOAD** block consumes:

- `verts`: flat **integer XYZ triples in millistuds**, divide by 1000.
- `normals`: flat **integer XYZ triples scaled by 1000**, divide by 1000; one angle-weighted normal per shared vertex.
- `colours`: flat **RGB byte triples**, 0–255, one per shared vertex.
- `tris`: flat **zero-based vertex-index triples**, add 1 only to index Lua tables.

Unlike the reference's private corners, these are shared indexed vertices, accepted unchanged by that UPLOAD code and retaining manifold topology. `middle`/`size` are retained for the template. `bbox` min/max, vertex/triangle counts, closed-shell count, positive component volumes and 12-character SHA1 are added. SHA1 covers compact JSON of the four arrays in order `verts,normals,colours,tris`.

`uvs` are flat floating-point UV pairs with separate zero-based `uv_tris` matching triangle corners; the angular seam is unwrapped per triangle. Pool lens UV is planar 0..1 across its diameter; bezel UV is cylindrical angle/depth. **The reference UPLOAD block ignores UVs**; an installer must add `AddUV`/`SetFaceUVs` handling to retain them. No texture is required. UVMap is already present in the blend.

## Mesh table

Bounding boxes below are **Roblox axes, studs**, measured after 0.001-stud quantization. Every mesh is closed.

| Mesh | Triangles | Shared vertices | Bbox min | Bbox max | Closed shells | Numbers SHA1 |
|---|---:|---:|---|---|---:|---|
| `PoolLamp_Bezel` | 448 | 242 | [-0.7, -0.7, -0.054] | [0.7, 0.7, 0.0] | 9 | `189d152af752` |
| `PoolLamp_Lens` | 440 | 222 | [-0.52, -0.52, -0.14] | [0.52, 0.52, -0.047] | 1 | `bed52e14492d` |
| `ExitLamp_Base` | 588 | 306 | [-0.547, -0.465, -0.25] | [0.547, 0.465, 0.0] | 6 | `1cc96271f0bb` |
| `ExitLamp_Lens` | 384 | 194 | [-0.385, -0.39, -0.406] | [0.385, 0.08, -0.22] | 1 | `e148094bf8fd` |
| `ExitLamp_Cage` | 688 | 348 | [-0.426, -0.431, -0.497] | [0.426, 0.121, -0.272] | 3 | `c722a1bdf2ed` |

Pool total: **888/900 triangles**. Exit total: **1660/1800 triangles**.

## Roblox appearance

| Mesh | Material | RGB colour | Purpose |
|---|---|---|---|
| PoolLamp_Bezel | Metal | 143,156,166; head vertices 87,97,102 | Stainless trim, rolled lip, eight heads, hidden backplate |
| PoolLamp_Lens | **Neon** | 168,237,255; valleys 122,191,214 | Glowing aqua-white prismatic lens with subtle vertex-colour relief |
| ExitLamp_Base | Metal | 71,79,77; heads 107,112,107 | Cast grey box, fixing ears, conduit |
| ExitLamp_Lens | **Neon** | 31,255,71 | Green exit indicator lens |
| ExitLamp_Cage | Metal | 19,24,22 | Dark wire guard |

Viewport materials are set in the blend; render emission is modest to preserve the ridge relief. The lead supplies Roblox lighting, depth fading, placement and gameplay. No light instances are exported.

## Validation and render review

The builder asserts both group budgets and each individual allocation, bounds, wall clearance, no degenerate triangles, valid directed edge pairs (exactly one each direction), cyclic vertex links, and **positive signed volume for every connected shell**. It repeats topology, winding and normals checks on the **final quantized Roblox coordinates**. The final table prints on rebuild. Determinism is checked with two builds and byte comparison of JSON. Preview PNGs are 800×600, EEVEE, two CPU threads, sequential renders.

Render review: Inspected all seven PNGs. The first pool front/three-quarter views flattened the Fresnel relief, so valley setback increased from 0.014 to 0.026 studs and subtle darker aqua vertex colours were added at the five valleys. Re-rendering shows five concentric rings and the central boss; the exact side view exposes the shallow dome and teeth. The chamfer, rolled lip and eight darker heads distinguish the fitting from a plain ring. Exit front and three-quarter views leave most green lens area visible; its exact side view shows the wire gap. The conduit initially touched the curved housing at a tangent, so it was seated 0.04 studs into the box while retaining its 0.35-stud total length. The 3×4 view remains legible at a steep angle from above. Side cameras were changed to true orthographic profiles. These are shape reviews, not tests at Roblox viewing distances.

## Not verified

Nothing ran inside Roblox or Roblox Studio. EditableMesh creation/upload, MeshPart recentering, imported UVs, actual Neon appearance, culling in-engine, lighting, depth fade, collision, draw-call cost, 360-copy performance, and readability at the stated in-game distances are not runtime-tested. Renders inspect shape and placement only. Disconnected overlapping shells are intentional; this is not a watertight boolean-union manufacturing model.
