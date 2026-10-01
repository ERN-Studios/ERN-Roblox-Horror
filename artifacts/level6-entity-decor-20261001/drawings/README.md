# Level 6 crayon wall drawings

48 new drawings made with the built-in `image_gen.imagegen` tool, in three transparent 4 × 4 atlases. The full generation prompts are in `prompts.json`.

- Tier 1: 16 ordinary children's party, home, family, animal and toy drawings.
- Tier 2: 16 unsettling variations with empty faces, strange doorways, watching windows and looming silhouettes.
- Tier 3: 16 intense, non-graphic surreal horror drawings with giant silhouettes, impossible corridors, eyes, spirals and faceless crowds.

The crayon grain and irregular edges are part of the art. There is no paper, wall background, frame, logo or watermark; transparent areas allow the actual wall material to show through. Content was visually reviewed: no blood, physical injuries, sexual content or abuse.

Source PNGs are 1254 × 1254, RGBA8. Roblox resamples each uploaded image to **1024 × 1024**, verified by `AssetService:CreateEditableImageAsync` in the target Studio Edit context. Runtime `ImageRectOffset` should therefore use a **256 × 256** cell grid, not the source PNG dimensions. All 16 cells are in left-to-right row order.

`atlas-manifest.json` records source SHA-256, dimensions and measured alpha transparency; `roblox-assets.json` records group-owned image IDs, decal wrappers and decoded Roblox dimensions. Creator Dashboard upload used ERN Roblox Studios (group 1039373905); only the existing experience 10559217407 is granted access. Asset privacy stays Restricted.

The source images are copied into this project and remain available independently of the image generation cache. No raster postprocessing or substitute artwork was used.
