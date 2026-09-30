# Level 3 texture reference for Level 6

Reference only, pending a fresh live Studio read. Inspected the verified `artifacts/level6-light-esp-20260930/native-after/scripts.json` snapshot and source mirrors from the Level 3/Level 6 repair. Source/editor parity was recorded in that snapshot; it does not establish current Studio parity.

## Level 3 image slots

`Level 3 World Builder` resolves each slot from a nonempty StringValue under `ReplicatedStorage.Level 3 Assets`, falling back to `Level 3 Configuration.Textures`. The following are configuration fallback IDs, also recorded in `assets/live-asset-manifest.json`. Read the live StringValues before treating them as effective IDs.

| Slot | ID | Repeat size / use |
|---|---:|---|
| PartyCarpetTexture | 92795890253148 | 28 x 28 studs; default party carpet |
| PartyCarpetNeonTexture | 110230144446272 | 22 x 22 studs; OrangeBlackParty / OrangeParty |
| PartyCarpetRedTexture | 108064770913201 | 30 x 30 studs; RedParty / RedCelebration |
| CityPlayCarpetTexture | 75635502248205 | 52 x 52 studs; City / CityPlay |
| PastelWallpaperTexture | 96252806287644 | 18 x 18 studs; wallpaper, Transparency .08 |
| OrangeWallTexture | 128270554927663 | 22 x 22 studs; orange/red plaster, Transparency .28 |
| ConfettiTableclothTexture | 103412925025303 | 10 x 10 studs; fabric tabletop, Transparency .34 |
| FinalExitDoorTexture | 120063024460642 | exit door artwork |
| KidsDrawingsAtlasTexture | 136455642832077 | child art atlas |
| KidsDrawingsWholesome25Texture | 128767366284181 | 5 x 5 atlas images |
| KidsDrawingsDisturbing25Texture | 132144680342985 | 5 x 5 atlas images |
| KidsNotesAtlasTexture | 81550568434150 | notes atlas |
| CDCoversAtlasTexture | 88160214591687 | CD sleeve artwork |
| DiscPlayerPanelTexture | 92830391726737 | AV cart / VCR / CRT casing; repeats 2.4–3 studs, Transparency .34–.40 |
| CRTScreenTexture | 106602270400755 | CRT screen image |

Other model texture IDs in the historical live asset manifest: FoldingTable texture `112282995723556`; Mall Manager ColorMap `139917107442839`. Effective furniture template MeshPart TextureID/SurfaceAppearance maps need a live read.

## Level 3 floor and wall appearance

| Theme | Floor base RGB | Material | Wall RGB / finish |
|---|---|---|---|
| City / CityPlay | 190,188,166 | Carpet with city carpet | 220,213,187; SmoothPlastic + pastel wallpaper; Reflectance .08 |
| OrangeBlackParty / OrangeParty | 13,17,24 | Carpet with neon party carpet | 183,78,35; Plaster + OrangeWall |
| RedParty / RedCelebration | 111,31,27 | Carpet with red party carpet | 145,58,48; Plaster + OrangeWall |
| Default / ArrivalTransition | 18,18,22 | Carpet with party carpet | 183,78,35; Plaster + OrangeWall |
| Exit kind | 70,71,66 | DiamondPlate, no carpet | theme-dependent |

Configuration accent RGB: AgedWhite 218,211,184; DustyPeach 176,99,74; MutedBlue 66,83,124; FadedGreen 91,126,83; Burgundy 92,43,49; DarkCarpet 18,18,22; Energon 66,244,218. Ceiling is AgedWhite Plaster. Chair colors include teal 38,153,165; green 55,130,87; red 151,49,59; orange 192,112,35; violet 71,72,137. Balloon colors include red 187,42,52; blue 40,104,169; green 55,139,91; yellow 210,159,37; purple 119,61,151; orange 215,94,38.

The normal Level 3 client grade is mildly desaturated: Saturation -.065 before unlock / -.045 after, Contrast .045 / .040. Base texture/palette differences are more significant than that grade. Blackout phases intentionally apply additional desaturation.

## Why Level 6 currently differs

`Level 6 Visual Adapter` makes every old BasePart and Texture invisible, then clones the Blender kit. Consequently changing the cloned World Builder's texture IDs alone cannot alter the rendered floor/wall appearance.

`tools/level6_build/textures.py` authors a procedural 2048 atlas. Its four architecture floor cells are beige geometric carpet, dark confetti carpet, red swirl/star carpet, and linoleum. These are different artwork from original Level 3. In `build.py`, floor tops consist of 16-stud quads, each UV mapped to the same atlas cell; scaling room floors stretches that repeat. Current Level 3 repeats are fixed physical 52/22/30/28-stud Texture repeats.

Level 6 themes choose FloorBeige/FloorOrange/FloorRed solely from theme; Exit chooses FloorService. WallBeige is matte beige paint, rather than Level 3's wallpaper. All kit clones retain template texture and properties unless the adapter specifically overrides them.

## Service rooms and requested floor exceptions

There are three seeded service alcove variants: BudgetArcade, PartySupplyStore and MaintenanceWorkshop, each 18 x 24 studs. All three currently add FloorService linoleum over the main carpet at +.025 studs. The desired distinction is carpet for arcade/supply and tiles for MaintenanceWorkshop. No separate Kitchen variant occurs in the inspected Level 6 Layout Generator or Room Dressing snapshot. Cafeteria/CityCafe are decor types, so any kitchen exception must be scoped to an actual kitchen area rather than replacing the entire City district floor.

## Implementation options for root review

Use the original live Level 3 carpet assets directly where possible. The existing cloned Level 6 floor proxies already have the Level 3 image/scale choice before the visual adapter hides them. Revealing the native floor finish and omitting the Blender carpet plane is a possible scoped solution retaining current collision/navigation geometry. Alternatively rebake the original carpet images into the Blender atlas with correct physical repeat sizes and preserve the template mesh/UV map under a fresh native backup. A global atlas color multiplier cannot reproduce different carpet artwork or recover saturated colors from dull cells; it also recolors props unnecessarily.

Do not alter Level 3 to accomplish the Level 6 restyle.
