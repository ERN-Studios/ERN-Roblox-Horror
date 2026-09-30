# Level6 Texture Review (offline architecture only)

These offline exports show how things are built, not what is live. Level3 looks up textures through the `ReplicatedStorage["Level 3 Assets"]` StringValue slots before falling back to Configuration. Every ID, StudsPerTile value and color below therefore needs confirmation in Studio. The export stops before Level3's corridor code, so Level3's corridor floor rule is unknown.

### 1. Probable causes of the pale, different look
Causes 1–5 are visible in the code. Their live impact depends on whether the Level6 runtime builds rooms the same way the Blender map does.

1. **Category mapping.** `theme()` sends every room except OrangeBlackParty, RedParty and Exit to Beige (khaki carpet and beige walls).
   - Level3's default is PartyCarpet with orange Plaster walls.
   - Level3's City/CityPlay rooms get CityCarpet with pastel wallpaper.
   - Level6 doesn't recognise the OrangeParty or RedCelebration aliases.
   - So most Level6 rooms get the palest combination, and corridors copy room A's theme.
2. **Different pixels.** Level6 carpets are procedural stand-ins: olive diamonds on (78,72,44), confetti at roughly 160 per channel or less on near-black, and a muted red. Level3 walls layer the OrangeWall texture at 0.28 transparency over saturated Plaster colors (183,78,35) and (145,58,48). The atlas reproduces neither.
3. **Broken texel scale.** Level3 textures repeat at fixed StudsPerTile values (28/22/30/52 for carpets, 22/18 for walls) no matter the part size. Level6 does this instead:
   - It maps one whole cell to each 16-stud quad, then scales the 80×64 prefab by (W/80, D/64). That stretches each room differently in X and Y.
   - In corridors, quads end up about 2.8–3.5 studs across but 3.5–16 along. Carpet motifs render 4–6× smaller and smeared.
   - Each wall segment (4–8 studs wide, full height) gets one whole cell.
   - The ceiling T-grid squashes to 0.7–0.9-stud spacing in corridors.
4. **A visible 16-stud grid.** The cells don't tile seamlessly:
   - the noise is upscaled without wrapping;
   - the 56-, 25- and 27-px pattern grids don't divide 512;
   - each tile is resized 512→504 with LANCZOS;
   - the UV window covers 500 px;
   - the guard bands copy edge pixels instead of wrapping.
5. **Mip bleed.** The 4-px guards (about 2 px if Roblox downsizes the 2048 upload; verify) stop working within a few mip levels. Floor cells sit next to the pale ceiling and laminate cells, so grey seam lines appear at distance.
6. **Studio-only candidates:**
   - Level6 light tint, brightness or ColorCorrection may differ from Level3's warm party (255,222,181) and utility (204,222,202) tones.
   - If `setup_render` keeps Blender 4.x's default AgX view, previews look paler than Roblox.

### 2. Room categories
Use one resolver for both the preview and the runtime, checking Exit first, then room function, then theme.

- **Exit:** Level3 uses untextured DiamondPlate (70,71,66), not linoleum.
- **Hard floors by function** (confirm the live Kind/Role names):
  - VCT/linoleum for Maintenance, non-party Utility, BreakRoom and storage/janitor rooms.
  - Tile for Kitchen.
  - This deliberately differs from Level3's legacy fallbacks, which put UtilityWest on neon carpet and Maintenance/BreakRoom on City carpet.
- **Theme carpets:**
  - Red/RedCelebration → PartyCarpetRed with red plaster.
  - OrangeBlack/OrangeParty → PartyCarpetNeon with orange plaster.
  - City/CityPlay → CityCarpet with pastel wallpaper.
  - Everything else → PartyCarpet with **orange** plaster.
  - Honour `WallStyle` if the layout sets it.
- **Corridors:** follow Level3's corridor carpet rule and never inherit a hard floor. Whether service-to-service links get VCT is your decision.

### 3. Recommended changes
- **Floors: use Level3's method.**
  - For each room or corridor, use one Part (or the existing collider).
  - Material: Carpet, or SmoothPlastic for VCT/tile. This also sets FloorMaterial.
  - Color: Level3's Part color, which also shows through any texture alpha.
  - Add a Top `Texture` with the live Level3 ID and StudsPerTile.
  - Replace or hide the atlas floor finish so nothing overlaps and z-fights.
  - Keep the collider and navigation geometry, and any names or tags scripts rely on.
  - Seed Level6-owned slots from the live Level3 values so Level3 itself is never edited.
  - Result: identical carpets, constant texel scale at any generated size, no seams or bleed, and no Blender reimport.
- **Hard-floor images** (standalone and seamless):
  - VCT: 4×4 tiles at StudsPerTile 8, giving 2-stud squares. Use a mid-value warm base, colored chips and about 10% accent tiles instead of the current dull (135,130,111) grey.
  - Kitchen: cream/brick checker or terracotta quarry tile, 1.5–2-stud squares, dark grout.
  - Optionally set OffsetStudsU/V from world position so grids line up where parts meet.
- **Atlas for walls, ceiling and props (pixel changes only):**
  - Cells 1 and 2: re-synthesise OrangeWall at its 22-stud feature scale and blend it about 72% over the live wall colors. Do the blend numerically, not from tone-mapped screenshots.
  - Default rooms switch to WallOrange; this is a resolver change only.
  - Cell 0 then serves service walls only (check props first); repaint it as warmer painted block.
  - Compare ceiling cell 4 with Level3's ceiling, since it fills much of the frame.
  - City wallpaper has no dedicated cell. Either overlay a Texture or add one new wall prefab.
- **Keeping floors in the atlas instead** would need fixed-size, unscaled floor modules plus carpets re-authored to a 16-stud repeat. Scattered designs could keep Level3's motif size. Any design that depends on its 22/28/30/52-stud repeat could not, so the floors would not be the same carpets.

### 4. Changing pixels without reimporting geometry
- **Keep the layout fixed.**
  - Leave `atlas-layout.json` byte-identical: 2048 px, 512-px cells, same cell order, window [6,6,506,506].
  - Keep the PNG square, RGB, with no alpha and no flips. Alpha would expose MeshPart.Color or transparency.
  - Then new pixels only need an upload and an ID swap. MeshIds, UVs, collisions and instancing stay intact.
  - Blender loads the PNG by path, so previews update without re-exporting.
- **Give each cell its own random generator**, e.g. `default_rng([603091, cell])`. With the current shared stream, editing one cell changes every cell generated after it.
- **Paint to the stud span.**
  - A floor window covers 16 studs: about 31 px/stud, or about 15.6 px/stud if downsized to 1024.
  - Make each window exactly one repeat, and fill the margins and guards with wrapped content.
  - Keep wall cells free of recognisable features, because segments stretch.
- **Check side effects before repainting.**
  - Cells are shared: `beige_wall` feeds both WallBeige and WallService, and prop usage is unknown.
  - SurfaceAppearance maps may not be writable at runtime, so swap them on the stored templates.
  - Update the atlas provenance note if Level3 pixels are embedded.

### 5. Verification
- **Visual A/B:** capture Level3 and Level6 from matched cameras for each category, including corridors. Use the same Lighting, ClockTime and ColorCorrection, at high and low graphics quality. The mean HSV of each floor crop should match within about 5%.
- **Texel scale:** put a 1-stud debug checker on the smallest room, the largest room, and corridors in both directions. The squares should stay the same size everywhere.
- **Seams and bleed:** look down a corridor at a grazing angle and from a zoomed-out top view. There should be no 16-stud lines or tint bleed.
- **Leftovers and load-in:**
  - No stale references to the old atlas or cells.
  - Base color close to each texture's mean, so textures streaming in never flash pale.
  - FloorMaterial reads correctly on each floor type.
- **Performance:** compare GraphicsTexture memory in the Dev Console, plus MicroProfiler draw calls and frame time in the busiest view against Level3. About 70 floor Textures is fewer than Level3 already uses.

**Uncertain:**
- Live Level3 IDs, image sizes and alpha, and whether the Level6 place can use those assets.
- Level3's corridor rule.
- How the Level6 runtime scales prefabs, and whether it uses SurfaceAppearance or TextureID.
- Roblox's upload resolution cap.
- Level6's room Kind/Role names.
- Lighting.
- Which props use which cells.
- Whether Textures pick up the Carpet material's shading.
