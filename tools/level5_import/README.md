# Level 5 import (Blender Quiet Suburbs -> Studio)

Built `Workspace."Level 5 Quiet Suburbs"` on 2026-09-29 from
`G:\Blender\Level4_Quiet_Suburbs\Level4_Quiet_Suburbs.blend` (1 m = 1/0.28 studs, origin 40000,0,0).

1. `blender -b <blend> -P export_l5.py` writes `chunks/cNNNNN.b64` + `manifest.json` next to the script:
   instanced kits (2+ copies) become one asset per material; everything else is baked to world space
   and pooled per material. Every chunk is <= 20,000 triangles, <= 60,000 vertices, <= 1800 studs.
2. `python serve.py 8765` (loopback). In Studio Edit, run `upload.luau` (replace `__LIMIT__`,
   `__BACKGROUND__`, `__ONLY__`) through execute_luau: it builds an EditableMesh per chunk and uploads it
   to the group as a Mesh asset; ids land in `results.jsonl` (the ids of the 2026-09-29 build are kept here).
3. `python make_place.py` (material/colour/collision mapping), then run `place.luau` in Studio Edit.
   Afterwards the live build flipped `L4_CeilingTile` 180 degrees about X (single-sided plane facing up)
   and made `L4_CeilingGlow` SmoothPlastic at Transparency 0.75.

Both scripts toggle `HttpService.HttpEnabled` for the loopback fetches and restore it.
Entry: `ServerScriptService.Level5PreviewAccess` (same method as the cinema's `Level4V4PreviewAccess`).
