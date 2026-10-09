# Texture requests — 2026-09-16

Format and art direction inherit `artifacts/trello-20260915/texture-requests.md`
and `assets/monetization/README.md`. **Every existing id stays exactly where it
is** (`assets/shop/README.md` lists all twelve); nothing below replaces a
published asset, and every new slot already renders a procedural placeholder, so
**nothing here blocks the code**. Fill an id in and that surface upgrades on the
next lobby rebuild.

---

## Section: A-SHOP-WALL, Trello #102 (physical wall shop, enlarged)

The wall shop at the right service ledge (z −68.2 … −45.8, wall face x = +32.9)
was rebuilt larger for #102. Three new surfaces appeared, one existing surface
changed proportion, and two existing images could use a higher-resolution
re-render. **None of the twelve published ids change.**

### Where the ids go

One table, one file, unchanged from 2026-09-15:
`ServerScriptService/LobbyShopDisplay.ModuleScript.lua`, top of file.

```lua
local SHOP_TEXTURES = {
	SignFace = "rbxassetid://126032557889771",   -- unchanged
	SignGlow = "rbxassetid://92494312014031",    -- unchanged
	PedestalTop = "rbxassetid://101891958398163",-- unchanged
	PlateTop = "rbxassetid://131434121223604",   -- unchanged
	Backdrop = "rbxassetid://124038960784765",   -- unchanged
	BoxFallback = "rbxassetid://90558430724311", -- unchanged
	Box = { ... six unchanged ids ... },

	-- NEW SLOTS (2026-09-16). "" draws the procedural placeholder.
	CanopyFascia = "",
	NamePlate = "",
	RewardsPlaque = "",
}
```

Value format unchanged: bare numeric id as a string, or a full `rbxassetid://`.
Every generated part still carries `ShopTextureSlot` naming its slot, so a Studio
probe can re-point any surface without reading the source.

**Repo path for every file below: `assets/shop/<filename>`.** Masters under
`assets/shop/source/`, mapping table appended to `assets/shop/README.md`.

### Shared constraints (unchanged from 2026-09-15)

No Robux symbol, no price numbers, no real-world logos, no watermark, no player
likeness. Prices and item names are live text the game draws; baking either into
a texture makes it lie. PNG, sRGB, no embedded colour profile. Alpha only where
stated. Readable at 1/4 scale — these are read from 12–35 studs across the road.

Palette (same hexes as the 2026-09-15 table):
`#49F5CC` Zyntra teal · `#44DDC4` terminal teal · `#56FFAD` signal green ·
`#FFCB4F` token gold · `#FFB748` sign amber · `#F45F52` emergency red ·
`#070B0D` panel black · `#141D21` card charcoal · `#202322` housing metal ·
`#3E423E` edge metal · `#746952` tunnel concrete.

---

## NEW — 3 files

### N1 `shop-canopy-fascia.png` — 512 × 256 (2:1), **seamless in U**, no alpha

* **Slot key** `CanopyFascia`.
* **Applied as** `Texture` (tiling) on the **Front** face of `ShopCanopyFascia`,
  a part 21.80 studs wide (along the wall) × 1.30 tall × 0.44 deep, facing −X
  across the road. `StudsPerTileU = 2.60`, `StudsPerTileV = 1.30` — one tile is
  a 2.60 × 1.30 stud patch, which is exactly the image's 2:1, so **the image
  must tile cleanly left-to-right**. Vertical tiling never repeats (one tile
  fills the height), so the top and bottom edges do not have to match.
* **Subject** a Zyntra canopy fascia band seen straight on: `#202322` brushed
  housing metal with a horizontal `#3E423E` seam 18 % down from the top, two
  flush hex bolts per tile near the seam, a thin `#49F5CC` conduit line running
  the full width 22 % up from the bottom, and light grime pooling under the
  seam. **Low contrast, no lettering, no glyphs** — the game draws
  `ZYNTRA // SUPPLY` over this with a live SurfaceGui, so any baked text would
  double up and any bright pattern would fight the type.
* **Purpose** the lit band directly above the crates. It is the first
  brand surface a player reads at walking height.
* **Placeholder shipping now** flat `#202322` Metal with a `SurfaceGui` drawing
  `ZYNTRA // SUPPLY` in amber Code over it, plus a neon under-rail. Complete and
  lit; this texture only adds material grain behind the letters.

### N2 `shop-nameplate.png` — 512 × 256 (2:1), **alpha required**

* **Slot key** `NamePlate`.
* **Applied as** `Decal` on the **Front** face of each `ShopNamePlate`, a part
  2.86 studs wide × 1.43 tall × 0.12 deep on the road-facing front of every
  pedestal column, tucked under the pedestal cap. One per catalogue item, no
  tiling, image fills the face edge to edge. 2:1 exactly.
* **Subject** an empty engraved Zyntra name plaque: `#141D21` recessed field,
  `#3E423E` chamfered bevel all the way round, two small fixing screws in the
  left and right margins, a 4-px `#49F5CC` rule across the top 16 % of the
  height, and worn edges. **The middle 78 % of the height and 88 % of the width
  must stay flat, dark and empty** — the game draws the item's live name and its
  `PASS` / `PRODUCT` eyebrow there. Alpha outside the plaque's rounded corners
  so the pedestal metal shows through.
* **Must not** carry any item name, price, currency mark or icon. Six pedestals
  share one image; a baked name would be wrong on five of them.
* **Purpose** the nameplate is the thing that tells a player what the crate is
  before they step on the plate. It grew from a 2.20-stud pedestal face to its
  own 2.86-stud plaque for this card; the art makes it read as hardware rather
  than as floating text.
* **Placeholder shipping now** a dark `#141D21` SmoothPlastic plate with a neon
  top rule part and the live `SurfaceGui` text. Functional, plain.

### N3 `shop-rewards-plaque.png` — 512 × 640 (4:5), no alpha

* **Slot key** `RewardsPlaque`.
* **Applied as** `Decal` on the **Front** face of `DailyRewardsPlaque`, a part
  2.80 studs wide × 3.50 tall × 0.30 deep standing on its own plinth at the
  kiosk end of the row (the seventh stand). 4:5 exactly, no tiling, fills the
  face.
* **Subject** a Zyntra notice plaque, portrait: `#070B0D` field inside a
  `#3E423E` machined frame with rounded inner corners, a `#FFCB4F` token-gold
  chevron band across the **top 14 %**, a faint etched calendar/rosette motif
  ghosted at 12 % opacity behind the centre, and a `#49F5CC` hairline rule
  across the **bottom 12 %**. **The centre 62 % of the height must stay flat and
  dark and empty** — the game draws `DAILY REWARDS`, the sub-line and the prompt
  hint there as live text.
* **Must not** say a number, a countdown, a prize, a percentage or an odds
  figure. Rewards, odds and the daily reset are server truth and are drawn live;
  a baked number would be a lie the first time the config changes.
* **Purpose** the physical reach-in to the DAILY REWARDS tab. It is the only new
  interactive surface on the wall and has to read as an official notice, not as
  an advertisement.
* **Placeholder shipping now** a dark plate with a gold neon frame part and the
  live `SurfaceGui` text. Complete and interactive; the prompt works today.

---

## OPTIONAL re-renders — 2 files, same slots, same subjects

Both are **quality-only**. The existing ids stay in place until Codex uploads a
replacement, and the geometry is already correct for them.

### O1 `shop-sign-face.png` at 2048 × 768 (still 8:3)

The sign face went from 14.40 × 3.60 studs to **16.00 × 6.00** — 1.85× the area.
The aspect is now **exactly 8:3**, which the current 1024 × 384 master already
is, so today's id renders correctly proportioned for the first time (it was
stretched 1.5× horizontally on the old 4:1 part). Pixel density drops from
71 px/stud to 64 px/stud. A 2048 × 768 re-render of the **same artwork** puts it
back to 128 px/stud on a sign that is now the loudest object on the walk.
Nothing changes in code.

### O2 `shop-sign-glow.png` at 2048 × 768 (still 8:3), alpha

Same reason. The glow panel is **16.80 × 6.30 studs — 8:3 exactly** and
concentric with the face (both centred at y = 12.49, z = −57), so the halo
glyphs sit on the face glyphs. Keep the letterforms in the same place in the
frame as O1 or the halo will drift off the letters.

---

## Not requested, deliberately

* **No new crate art.** The six `Box.*` ids and `BoxFallback` still land on a
  square cube (2.20 studs instead of 2.00) — the aspect did not change.
* **No new `PedestalTop`.** The cap is 2.86 × 2.80 studs, 1.02:1; a 512 × 512
  square image stretches 2 %, which is invisible on a concentric ring motif.
* **No new `PlateTop`.** The inspect plate is 3.00 (toward the road) × 2.86
  (along the wall), 1.05:1, a 5 % stretch on a deliberately scuffed floor
  stencil. Re-cutting it would cost more than it buys.
* **No new `Backdrop`.** It is a tiling texture at 6 studs per tile; the panel
  got shorter (top y 10.45 → 9.34) and tiling absorbs that.

## Priority if the night is short

`shop-rewards-plaque` → `shop-nameplate` → `shop-canopy-fascia` → the two
optional re-renders. The plaque is the one new interaction; the nameplate is
what a player reads before deciding to step on a plate; the fascia is material
grain behind live type.
