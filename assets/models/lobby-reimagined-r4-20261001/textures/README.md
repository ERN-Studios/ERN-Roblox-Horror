# Lobby R4 PBR material pack

These are real, separate texture maps for the requested concrete tunnel, asphalt
road, and concrete sidewalk. They have not been uploaded or verified in Studio
by this preparation step. They do not replace the old lobby assets.

| Material family | Median color (RGB) | Tile scale | Recommended use |
|---|---:|---:|---|
| `tunnel_concrete` | 163, 160, 152 | 12 studs | Rounded tunnel lining and wall panels |
| `asphalt_road` | 62, 64, 63 | 14 studs | Main central road |
| `sidewalk_concrete` | 158, 156, 149 | 8 studs | Sidewalk slabs and concrete steps |
| `curb_concrete` | 171, 168, 162 | 8 studs | Curbs and concrete trim |

Each family has 1024 × 1024 color, OpenGL tangent normal, 16-bit height/bump,
and roughness PNGs. `manifest.json` records source/download hashes, exact
dimensions, PNG modes, tiling scale, color space, and intended Roblox mappings.
`verification.json` records dimension/hash checks, nonconstant texture checks,
normal length checks, and exact preservation of the genuine 16-bit height scans.

Use the color PNG in sRGB. Normal, roughness, and height must use **Non-Color**
data in Blender. The supplied normal strength is already baked into the PNG;
use strength 1 on the Blender Normal Map node. Height is retained for optional
Blender Bump adjustment. Avoid doubling the full normal relief with an
additional strong height effect.

For Roblox, upload and assign **color, normal, and roughness**. Roblox's PBR
pipeline uses the normal map for bumps; it has no separate height-map property.
Do not map the grayscale height image into `NormalMap`.

For `MaterialVariant`, use the stated `StudsPerTile`, base material, and a unique
name from the manifest, scoped to R4 parts. Do not override all concrete or
asphalt in the game. For `SurfaceAppearance`, the mesh's UVs determine tiling:
split architecture into chunks by material, leave the furniture atlas separate,
and export tangent information. A single whole-lobby atlas does not preserve
these normal maps.

Rounded tunnel UVs should use circumferential arclength and longitudinal
distance divided by 12 studs. Keep radial shading normals and UV values
continuous across shell sections. Road and sidewalk UVs should likewise follow
world distance; do not reset each chunk to one stretched tile.

The source scans are public domain under **CC0 1.0**, downloaded directly from
Poly Haven. Their source PNGs and API download receipts are retained under
`source/`, and the original MD5 hashes were checked before use:

- [Concrete Wall 008](https://polyhaven.com/a/concrete_wall_008): Charlotte
  Baglioni (photography), Dario Barresi (processing). Used for tunnel and curb.
- [Clean Asphalt](https://polyhaven.com/a/clean_asphalt): Dimitrios Savva.
- [Concrete Pavement](https://polyhaven.com/a/concrete_pavement): Charlotte
  Baglioni.
- [Poly Haven license](https://polyhaven.com/license).

Color maps have a restrained gray palette, preserving scanned pores, chips, and
aggregate. Roughness retains scan variation while staying dry and matte.
Normals keep Poly Haven's OpenGL convention and are attenuated/renormalized;
height is the unmodified real scan, rather than an estimate from color.

Preparation and verification:

```sh
python tools/lobby_reimagined/r4_materials.py
python tools/lobby_reimagined/r4_materials.py --verify-only
python tools/lobby_reimagined/r4_materials.py --runtime-pixels
```

The helper requires NumPy and Pillow. It writes only this R4 texture pack,
does not mutate a Blender scene or Studio, and does not upload assets.

`runtime-pixels.json` describes nine raw image buffers for tunnel, road, and
sidewalk color/normal/roughness. The associated `.rgba.b64` files decode to
4,194,304 bytes each: 1024 × 1024 opaque RGBA8 with **top-down** rows. All RGB
bytes match the decoded source PNG; there is no gamma conversion or green
normal channel flip. Grayscale roughness is repeated in R, G, and B. The
manifest records hashes of the PNG, raw RGBA bytes, and encoded base64. A
runtime importer should respect the declared row order, rather than flip these
rows again as it would Blender's bottom-up `image.pixels` data.

Technical references:
[MaterialVariant](https://create.roblox.com/docs/reference/engine/classes/MaterialVariant),
[Roblox PBR textures](https://create.roblox.com/docs/art/modeling/surface-appearance).
