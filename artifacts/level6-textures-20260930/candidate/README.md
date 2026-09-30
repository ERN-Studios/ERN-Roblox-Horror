# Level 6 texture candidate — not installed in Studio

This folder contains an offline copy of the authored Blender project, a revised
atlas, and a raw runtime pixel payload. None of these files represents a fresh
Studio export. Creating them did not change Studio, import meshes, upload assets,
or publish the experience. The owner’s live-authority workflow still governs any
later installation.

The original Level 3 images were extracted and verified against the historical
source pack documented in `../reference-textures/reference-manifest.json`.
Current live slots, colors and rendering remain to be verified in Studio.

## Candidate changes

- Cell 0 uses the original pastel wallpaper over RGB 220,213,187 at 92% opacity.
- Cell 1 uses the original orange wall image over RGB 183,78,35 at 72% opacity.
- Cell 2 reuses only the original orange image’s normalized linear luminance as
  wear, tinted RGB 145,58,48. The 72% wear / 28% base mix preserves red party
  identity. This is an art approximation requiring a native A/B; it is not the
  historical orange-over-red composite.
- Carpet cells 5,6,7 reuse the original City Play, neon party and red party source
  pixels, resized to the unchanged atlas windows.
- Palette cell 15 uses the per-material Opus 5.5/max recommendation recorded in
  `claude-palette.json`. Existing pixel wear residuals remain in each changed
  swatch. No global grading, added material keys or UV remapping occurred.
- Cells 3,4,8,9,10,11,12,13,14 are pixel-identical at both 2048 and 1024 output
  resolutions. `textures/atlas-layout.json` is byte-identical to the original.

The three source carpets have native repeats of 52,22,30 studs. The old authored
Blender UVs still repeat per mesh face and remain unchanged. Runtime native floor
textures must provide the correct physical repeats; this atlas cannot fix that
stretching. Public arcade/supply carpeting and maintenance/kitchen hard flooring
are room-classification changes, separate from this asset preparation.

Within this candidate copy, Study 04 Budget Arcade’s main floor instance now
points to `L6K_FloorBeige` (City Play carpet), and Study 05 Party Supply Store’s
main floor points to `L6K_FloorOrange` (neon carpet). Study 06 Maintenance Workshop
retains `L6K_FloorService`. These two collection-instance references match the
current offline layout’s intended districts. All template mesh geometry, UVs,
material keys, transforms and object counts remain unchanged. They are recorded
separately as scoped authored study routing changes; they are not Studio edits.

## Files

- `Level6_WornParty_Level3Reference_candidate.blend`: original geometry/material
  slots with the new 2048 atlas packed. The source `.blend` is untouched.
- `textures/WornParty_Level3Reference_Atlas.png`: 2048 square RGB atlas.
- `textures/WornParty_Level3Reference_Atlas1024.png`: 1024 square RGBA runtime image.
- `atlas-rgba.b64`: uncompressed base64 RGBA8, exactly 4,194,304 decoded bytes.
  This is a transport candidate, not the compressed Studio StringValue payload.
- `atlas-pixels.json`: width, height, byte count and decoded pixel SHA-256.
- `atlas-candidate-manifest.json` and `blend-candidate-manifest.json`: source/output
  hashes, unchanged geometry/UV/count checks, palette changes and limitations.
- `saved-blend-parity.json` and `final-verification.json`: independent saved-file
  geometry/UV/material-key fingerprints, the two exact instance-routing changes,
  packed-atlas verification, decoded pixel hash and neutral-cell equality checks.
- `texture-comparison.jpg`: unlit old/candidate pixel comparison.
- `previews/*-before.png` and `previews/*-candidate.png`: matched Blender studies.
  Blender’s existing AgX, warm lighting and exposure remain the same across each
  pair. They do not prove Roblox rendering, gameplay or performance.

## Reproduce

Run the atlas script with Python supporting Pillow and NumPy:

```text
python3 build_candidate_atlas.py --palette claude-palette.json
Blender --background --python prepare_candidate_blend.py -- --render
```

Run these from the candidate folder, or use full script and palette paths. The
scripts resolve their source assets relative to this repository and write only
inside this candidate folder. `--render-after-only` reuses existing before images
and renders only the candidate. No Studio MCP calls exist in either script.
