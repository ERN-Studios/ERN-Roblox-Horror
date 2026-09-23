# Texture requests — Trello #88 lobby SHOP area (agent A88 → Codex)

Written 2026-09-15. Everything here is for the **new wall-integrated shop area**
in the Zyntra transit lobby (right service ledge, world z −70 … −47, wall face
x = +32.9). Geometry, pedestals, plates and the UI all ship **before** these
ids exist and render with procedural placeholders, so nothing here is blocking.
Fill an id in and that slot upgrades on the next lobby rebuild.

## Where the ids go

One table, one file:
`ServerScriptService/LobbyShopDisplay.ModuleScript.lua`, top of file:

```lua
-- Codex fills these in. "" = draw the procedural placeholder instead.
local SHOP_TEXTURES = {
	SignFace   = "",
	SignGlow   = "",
	PedestalTop = "",
	PlateTop   = "",
	Backdrop   = "",
	BoxFallback = "",
	Box = {
		Supporter = "", AdvancedEquipment = "", CosmeticEquipment = "",
		Tokens4 = "", Tokens20 = "", EmergencyReentry = "",
	},
}
```

Value format: the bare numeric id as a string (`"123456789"`) or a full
`rbxassetid://…`; both are accepted. Every generated part also carries the
attribute `ShopTextureSlot = "<slot key>"` (boxes: `"Box:<itemKey>"`), so a
Studio probe can find and re-point any surface without reading this file.

**Repo path for every file below: `assets/shop/<filename>`.** Keep the
full-resolution master under `assets/shop/source/` the way
`assets/monetization/source/` does, and add the upload mapping table to
`assets/shop/README.md`.

## Shared art direction (inherit `assets/monetization/README.md`)

Same world, same palette, one step dirtier — these are physical objects in a
concrete service tunnel, not UI icons.

| Role | Hex | Color3 | Where it comes from |
|---|---|---|---|
| Zyntra teal (primary neon) | `#49F5CC` | `Color3.fromRGB(73,245,204)` | `TunnelLobbyBuilder.COLORS.zyntraCyan` |
| Terminal teal (UI accent) | `#44DDC4` | `Color3.fromRGB(68,221,196)` | `ZyntraStore.COLORS.accent` |
| Signal green | `#56FFAD` | `Color3.fromRGB(86,255,173)` | `COLORS.green` |
| Token gold | `#FFCB4F` | `Color3.fromRGB(255,203,79)` | `ZyntraStore.COLORS.accent2` |
| Sign amber trim | `#FFB748` | `Color3.fromRGB(255,183,72)` | `COLORS.amber` |
| Emergency red | `#F45F52` | `Color3.fromRGB(244,95,82)` | `ZyntraStore.COLORS.error` |
| Panel black | `#070B0D` | `Color3.fromRGB(7,11,13)` | `ZyntraStore.COLORS.bg` |
| Card charcoal | `#141D21` | `Color3.fromRGB(20,29,33)` | `ZyntraStore.COLORS.card` |
| Housing metal | `#202322` | `Color3.fromRGB(32,35,34)` | `COLORS.metal` |
| Edge metal | `#3E423E` | `Color3.fromRGB(62,66,62)` | `COLORS.metalLight` |
| Tunnel concrete | `#746952` | `Color3.fromRGB(116,105,82)` | `COLORS.concrete` |

Constraints for all eleven: **no Robux symbol, no price numbers, no real-world
logos, no watermark, no player likeness.** Prices and names are live text drawn
by the game (they change when the catalogue changes); baking either into a
texture makes it lie. PNG, sRGB, no embedded colour profile. Alpha only where
stated. Readable at 1/4 scale — a player reads these from 12–25 studs away
across the road.

---

## A. Environment — 5 files

### A1 `shop-sign-face.png` — 1024 × 384 (8:3)

* **Applied as** `Decal` on the **Front** face of `ShopSignFace`
  (Part 15.6 studs wide × 5.85 tall × 0.4 deep, facing −X across the road).
  8:3 exactly, **no tiling**, image fills the face edge to edge.
* **Subject** the word **`SHOP`** in heavy condensed industrial capitals,
  centred, filling ~72% of the width and ~62% of the height; beneath it a thin
  `ZYNTRA // SUPPLY` stencil line at ~10% height. Tube-neon read: teal `#49F5CC`
  core with a white-hot `#E8F0EE` inner stroke, amber `#FFB748` hairline outline
  around the glyphs only.
* **Background** dark `#070B0D` housing with a faint brushed-metal grain and two
  amber `#FFB748` trim rules 24 px in from the top and bottom edges. Background
  is **opaque** (no alpha) — it is the sign's own enclosure.
* **Purpose** the thing a player notices from the spawn walk. It has to out-read
  the arrival gantry 40 studs behind it.
* **Placeholder until it lands** a `SurfaceGui` drawing "SHOP" in GothamBlack
  over a neon panel. Functional, generic.

### A2 `shop-sign-glow.png` — 1024 × 384 (8:3), **alpha required**

* **Applied as** `Decal` on the **Front** face of `ShopSignGlowPanel`, a Neon
  part 0.06 studs in front of A1 and 12% larger (17.5 × 6.55). Same 8:3 UV, so
  the glyph centres of A1 and A2 land on top of each other.
* **Subject** the bloom/halo of the same `SHOP` letterforms and nothing else:
  soft teal `#49F5CC` falloff, transparent everywhere the glow is not.
  No housing, no trim, no text edges.
* **Purpose** the sign's light spill, faded in and out by the pulse. Under
  `ReduceFlashing` the client holds it at a constant mid brightness, so the image
  must look right static as well as animated.
* **Placeholder** the Neon panel alone at a fixed transparency.

### A3 `shop-backplate.png` — 1024 × 1024, **seamless tiling**

* **Applied as** `Texture` (tiling) on the **Front** face of `ShopAlcoveBackdrop`
  (0.12 × 11 × 23 studs). `StudsPerTileU = StudsPerTileV = 6`, so one tile is a
  6 × 6 stud patch and the image must tile cleanly in both axes.
* **Subject** dark Zyntra service panelling: `#141D21` sheet metal, recessed
  square panels with `#3E423E` seams, occasional flush rivets, one faint teal
  `#49F5CC` conduit stripe per tile, light grime pooling at panel joints. Flat,
  low contrast — it sits **behind** the products and must never compete with
  them.
* **Purpose** makes the alcove read as built into the wall rather than bolted
  onto concrete.
* **Placeholder** flat `#141D21` SmoothPlastic at 0.18 reflectance.

### A4 `shop-pedestal-top.png` — 512 × 512

* **Applied as** `Decal` on the **Top** face of each `ShopPedestalCap`
  (2.6 × 0.3 × 2.6 studs). Square, one per pedestal, no tiling.
* **Subject** a circular Zyntra deck plate seen from directly above: concentric
  teal `#49F5CC` ring, four registration notches at 12/3/6/9 o'clock, a fine
  grid inside the ring, dark `#070B0D` outside it, thin amber `#FFB748` arc at
  the bottom edge. Rotationally sensible — it is seen from every angle.
* **Purpose** the emitter the product appears to hover above.
* **Placeholder** a teal Neon ring part.

### A5 `shop-plate-top.png` — 512 × 512, **alpha required**

* **Applied as** `Decal` on the **Top** face of each `ShopInspectPlate`
  (3.4 × 0.12 × 3.4 studs) sitting on the ledge floor in front of a pedestal.
* **Subject** a floor marking, drawn as if stencilled onto steel: a dashed
  circular border, a centred **footstep-into-bracket** glyph, and the word
  `INSPECT` in a small stencil arc along the bottom. Teal `#49F5CC` at ~70%
  opacity with worn/scuffed edges; transparent background so the plate's own
  metal shows through.
* **Must not** say BUY, PAY, PURCHASE or show a currency mark. Standing on this
  plate never charges anything and the floor must not imply it does.
* **Purpose** the invitation. It is the only instruction the interaction gets.
* **Placeholder** a teal `SurfaceGui` reading "STEP TO INSPECT".

---

## B. Product boxes — 6 + 1 files, 512 × 512 each

One per existing catalogue entry. **No new products.**

* **Applied as** `Decal` on the four vertical faces (Front/Back/Left/Right) of
  the hovering `ShopItemBox` — a 2.0 stud cube that bobs ~0.35 studs above its
  pedestal and turns slowly. Square, no tiling, opaque.
* **Composition for every box** a sealed Zyntra supply crate face seen straight
  on: `#141D21` shell, `#3E423E` corner brackets and a horizontal banding strap,
  a small `Z//` stamp in the bottom-left corner, and a **large central subject
  panel** carrying the item's own motif in that item's accent colour. Leave the
  outer 8% as quiet margin — the cube's neon edge trim sits there. The subject
  panel should read as a printed/etched label, not a glowing screen.
* **No names or prices in the image.** A live `SurfaceGui` nameplate under the
  box draws `item.Name`, and the price only ever appears in the detail card.
* **Front-face fallback until these land:** the box draws the item's **existing
  live monetization icon** (`ZyntraConfig.<Products|Passes>.<key>.IconId`, the
  six ids already uploaded from `assets/monetization/icons-512/`) on the front
  face and flat accent colour on the other three. So the shop is never blank —
  these textures replace a working surface, they do not enable it.

| File | Item key | Accent | Central subject |
|---|---|---|---|
| `box-supporter.png` | `Supporter` (pass, 99 R$) | teal `#44DDC4` | Etched supporter badge/chevron over three small gold chips; a small `//S` mark. Reads as a credential, not a person. |
| `box-advanced-equipment.png` | `AdvancedEquipment` (pass, 149 R$) | teal `#44DDC4` + gold `#FFCB4F` | Hazmat respirator module in profile with a colour-calibration arc; one teal chevron (stamina) and one gold chevron (battery). |
| `box-cosmetic-equipment.png` | `CosmeticEquipment` (pass, 99 R$) | cyan/magenta/amber | Three rugged glowsticks in a triangular fan over a luminous colour-selection ring. No flashlight, no helmet. |
| `box-tokens-4.png` | `Tokens4` (product, 49 R$) | gold `#FFCB4F` | Exactly **four** countable square research chips with teal cores, diamond cluster. |
| `box-tokens-20.png` | `Tokens20` (product, 149 R$) | gold `#FFCB4F` | A dense cache of the same chips in three stacked layers with one brighter master chip. Must read as clearly more than the four-pack at a glance. |
| `box-emergency-reentry.png` | `EmergencyReentry` (product, 29 R$) | red `#F45F52` | Sealed airlock door with one thick luminous circular return arrow pointing inward, small teal status lights. Urgent, no gore. |
| `box-fallback.png` | *(any key with no art)* | teal `#49F5CC` | A blank Zyntra crate: shell, brackets, strap, `Z//` stamp, and an empty recessed label panel with a faint holographic shimmer. Used for anything added to the catalogue later, so it must look deliberate and never like a missing texture. |

These deliberately echo the six icon prompts in `assets/monetization/README.md`
so a player recognises the crate in the world as the card in the terminal — but
they are **crate faces, not circular icons**: square framing, edge-to-edge
crate shell, no circular vignette, no dark radial falloff.

---

## Import checklist for Codex

1. Generate at the stated pixel size; keep masters under `assets/shop/source/`.
2. Upload as **Image** assets in the experience's own creator inventory (the
   game reads them as `Decal.Texture` / `Texture.Texture`; an Image id works for
   both). A2 and A5 must keep their alpha through upload.
3. Write the ids into `SHOP_TEXTURES` in
   `ServerScriptService/LobbyShopDisplay.ModuleScript.lua` — **that one table
   only**; nothing else in the shop needs editing.
4. Record the mapping in `assets/shop/README.md` (same table shape as
   `assets/monetization/README.md`), including the generation prompts.
5. The lobby rebuilds on every play start, so a pushed id shows up on the next
   play session with no further step.

## Priority if the night is short

`shop-sign-face` → `shop-plate-top` → `shop-pedestal-top` → the six boxes →
`shop-sign-glow` → `shop-backplate`. The sign and the plate marking carry the
whole "notice → curious → interact" funnel; everything after them is polish on
a shop that already works.
