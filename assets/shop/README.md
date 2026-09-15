# Lobby SHOP wall textures

Art for the wall-integrated Zyntra SHOP frontage in the transit lobby
(Trello #88). Specified in `artifacts/trello-20260915/texture-requests.md`;
**generated and owned by Codex**, which also uploads them and fills in the ids.
`generation-registry.json` records each file's generation prompt and master.

All twelve textures were generated, uploaded to the Roblox creator group, and
integrated in Studio on September 15. Upload receipts are in
`published-images.json` and `published-product-images.json`.

| File | Slot key | Where it lands |
|---|---|---|
| `shop-sign-face.png` | `SignFace` | Decal, Front face of `ShopSignFace` |
| `shop-sign-glow.png` | `SignGlow` | Decal, Front face of `ShopSignGlowPanel` (alpha) |
| `shop-backplate.png` | `Backdrop` | Texture (tiling, 6 studs), `ShopAlcoveBackdrop` |
| `shop-pedestal-top.png` | `PedestalTop` | Decal, Top face of each `ShopPedestalCap` |
| `shop-plate-top.png` | `PlateTop` | Decal, Top face of each `ShopInspectPlate` (alpha) |
| `box-supporter.png` | `Box.Supporter` | Decal, four vertical faces of that item's `ShopItemBox` |
| `box-advanced-equipment.png` | `Box.AdvancedEquipment` | as above |
| `box-cosmetic-equipment.png` | `Box.CosmeticEquipment` | as above |
| `box-tokens-4.png` | `Box.Tokens4` | as above |
| `box-tokens-20.png` | `Box.Tokens20` | as above |
| `box-emergency-reentry.png` | `Box.EmergencyReentry` | as above |
| `box-fallback.png` | `BoxFallback` | any catalogue item with no art of its own |

The asset ids go in ONE place: the `SHOP_TEXTURES` table at the top of
`ServerScriptService/LobbyShopDisplay.ModuleScript.lua`. Every generated part
also carries a `ShopTextureSlot` attribute naming its slot, so a Studio probe
can find any surface without reading the source.

## Published assets

| Slot | Roblox image asset |
|---|---|
| SignFace | 126032557889771 |
| SignGlow | 92494312014031 |
| PedestalTop | 101891958398163 |
| PlateTop | 131434121223604 |
| Backdrop | 124038960784765 |
| BoxFallback | 90558430724311 |
| Box.Supporter | 75534988741783 |
| Box.AdvancedEquipment | 133698774797678 |
| Box.CosmeticEquipment | 95744112613263 |
| Box.Tokens4 | 127956354478910 |
| Box.Tokens20 | 114348157561307 |
| Box.EmergencyReentry | 93091494402773 |

The native sign review found that the glow panel obscured the lettering. Its
depth now sits behind the sign face (X=31.78), preserving readable SHOP text.
Product plates only open a detail card; the explicit BUY action uses the existing
store purchase flow. No prices or discounts were changed.
