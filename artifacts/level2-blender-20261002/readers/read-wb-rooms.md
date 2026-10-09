# Level 2 World Builder: how it builds the rooms (for a Blender modular-kit rewrite)

**Files:**
- WB = `G:\Roblox\MongoTV\ServerScriptService\Level 2 Systems\Level 2 World Builder.ModuleScript.lua` (6400 lines, read in full)
- CFG = `G:\Roblox\MongoTV\ServerScriptService\Level 2 Systems\Level 2 Configuration.ModuleScript.lua`
- RA = `...\Level 2 Round Adapter.ModuleScript.lua`
- LG = `...\Level 2 Layout Generator.ModuleScript.lua`
- LLC = `G:\Roblox\MongoTV\StarterPlayer\StarterPlayerScripts\Level 2 Lighting Controller.LocalScript.lua`

## 1. Entry points and call order

**Public API**
- `WorldBuilder.Build(layout, generation)`, WB:5890-6356.
- `ArchRibMeshMissingKeys()`, WB:6360-6365.
- `EnsureArchRibMeshTemplates(keys)`, WB:6371-6388. This is a command-bar tool. It sets `workspace.Level2ArchMeshRibsAllowEditable = true`.
- `ArchRibMeshKeyFor(corridorWidth, floorDepth)`, WB:6393-6398.

**Caller:** RA:356 runs `LayoutGenerator.Generate(seed, {AllowRandomRecovery})`, then RA:370 runs `WorldBuilder.Build`. It then records `Level2_BuildSeconds` and `Level2_WorldDescendants` (RA:371-375). Cleanup is `clearOwnedTerrain` (RA:196-225). It fills every `manifest.WaterRegions` entry with Air plus an 8-stud margin, falls back to `TerrainCenter`/`TerrainSize`, then restores `PreviousWaterAppearance`.

**`Build` order:**
1. **Terrain water appearance** (WB:5900-5911). It saves the five global Terrain water properties first, then sets: `WaterColor = C.Water` (48,150,159), `WaterTransparency .24`, `WaterReflectance .08`, `WaterWaveSize .035`, `WaterWaveSpeed 1.65`.
2. **World container** (WB:5918-5935).
   - `workspace."Level 2 Generated World"` (Model), with attributes `Level2_Seed`, `Level2_Generation`, `Level2_GenerationAttempt`, `Level2_Theme` ("Sunken Leisure Complex").
   - Folders:
     - `Level 2 Geometry`, containing `Level 2 Halls`, `Level 2 Corridors`, `Level 2 Kids Wing` and `Level 2 Slide Halls`
     - `Level 2 Objectives`, containing `Level 2 Pressure Doors`
     - `Level 2 Lighting`
     - `Level 2 Navigation`
     - `Level 2 Entity Nodes`
3. **Doors per hall** (WB:5940-5957). `doorsByHall[i] = {East, West, North, South}` holds the corridor `Cross` coordinates.
4. **Spiral placement** (WB:5963-5988). `spiralStairPlacement` runs for each "Spiral Stair Well". A hall that fails is changed to "Porthole Hall". Attributes written: `Level2_SpiralRolls`, `Level2_SpiralsBuilt`, `Level2_SpiralsRerouted`.
5. **Hall loop** (WB:5996-6202). It yields every 4 halls.
   - Creates a Model named `"<hall.Id> <Archetype>"` with attributes `Level2_Role`, `PoolType`, `Archetype`, `GraphDepth`, `Height`, `FloorY`, `PumpIndex` and `KidsColor`.
   - Runs `makeHallFloor`, then `makeHallCeiling`, then a branch by role:
     - **Kids Area:** `makeKidsHall`, plus the `Level 2 Pool Foam Spawn <i>` part (attribute `Level2_PoolFoamSpawn`) at the reserved spot +2 Y (WB:6015-6028).
     - **Slide Hall:** `makeSlideHall` into `Level 2 Slide Halls`, then `dressHall(... .6)`. If `IsGrand`, it also runs `makeExitFlume` into `Level 2 Geometry` (WB:6029-6035).
     - **Other halls:** dressing by archetype (WB:6037-6125), then `makeHallEdgeWalkway` (not Pump Station), then `decorateLargeHall` (not Ring Corridor or Pump Station), then `dressHall(...,1)`, then the deep-water doorway stairs (WB:6139-6168).
   - Then `lightHall` into `Level 2 Lighting` (skipped for Kids and Slide halls).
   - Then `Level 2 Navigation Node <i>` at hall centre, `floorY+1`.
   - Then 4 × `Level 2 Entity Patrol Node i.c` at ±.32 of Width/Depth, `floorY+2` (WB:6175-6198).
6. **Hall walls** (WB:6205-6218). Each hall gets 4 × `makeWallWithGaps` with `bottomY = -(depth or 0) - 4`. The Grand hall's east wall also gets the `exit.HallWallGap` flume opening.
7. **Corridors** (WB:6224-6232). `makeCorridor` runs for each corridor and yields every 2. It collects `corridorRecords`, `drains[DrainGroup]` and `pressureDoors`.
8. **Arch-mesh readbacks** (WB:6236-6247). Attributes `Level2_ArchRibMeshEnabled`, `Level2_ArchRibMeshRibs`, `Level2_ArchRibMeshMissingKeys`.
9. **Pumps** (WB:6250-6255). `makePumpStation` runs for each of `layout.PumpHalls`, into `Level 2 Objectives`. Handle colours come from `shuffledLeverHandleColors(seed, generation)`.
10. **Arrival** (WB:6257-6274). The room direction comes from the first corridor touching Arrival. Then `makeArrivalConcourse` and `makeCompatibilityArrival` run.
11. **Entity dens** (WB:6277-6293). `Level 2 Entity Den A Spawn` (and B), 10×.4×10 parts, plus `Level2_DenAPosition`/`DenBPosition`.
12. **Terrain attributes** (WB:6295-6302). `TerrainCenter = (worldCenterX, -16, worldCenterZ)`, `TerrainSize = (extent+700, 200, extent+700)`, plus count attributes.
13. **Roof pass** (WB:6317-6332). Every BasePart whose name contains "Ceiling", "Skylight" or "Roof" gets `Level2_NoEntityGround = true` and a `PathfindingModifier` with `Label "Level2Roof"`, `PassThrough false`. The pass is time-sliced at 8 ms. The comment says the world is "around 71,000 instances".
14. **Manifest returned** (WB:6334-6355): `World`, `Layout`, `Pumps`, `PressureDoors`, `Drains`, `Corridors`, `Exit`, `Arrival`, `EntityDen`, `EntityNodes`, `Navigation`, `WaterRegions`, `PreviousWaterAppearance`, `TerrainCenter`, `TerrainSize`, `Generation`. A rewrite must keep this contract.

**Parts left outside the world model:** `makeCompatibilityArrival` (WB:5824-5886) parents these straight to `workspace`, each tagged `Level2_CompatibilityMarker`:
- an `Elevator` Model (`Level 2 Arrival Elevator Shell`, `DoorL`, `DoorR`, all invisible)
- `MazeStart`
- `ElevatorSpawn`
- `EntityStart` (moved to den centre +4, WB:6293)

## 2. Units, grid and dimensions

**There is no grid.** The layout is a binary space partition (BSP), and every value is a continuous number of studs.
- Plan: `ComplexExtent 1400`, centred on (`WorldCenterX 0`, `WorldCenterZ 240`) (CFG:19-25).
- Leaves: `MinimumLeafSize 150`, `MaximumLeafSize 310` (halls about 85-270).
- `HallMargin 30` (the corridor gap), `HallInsetJitter 14`, `MinimumHallSize 85`, `MinimumHallCount 16`.
- `CorridorWidth 34`, `MaximumCorridorLength 130`.
- Slide halls: minimum 175×165. Exit (grand) hall: minimum 210×200, `ExitHallMaximumShellGap 80` (CFG:27-84).
- `hall.Center` always has Y = 0 (LG:28-30).

**Vertical values (CFG:90-121):**

| Key | Value |
|---|---|
| WallHeight | 34 |
| GrandSlideHallHeight | 96 |
| SlideHallHeight | 76 |
| KidsWallHeight | 33 |
| CorridorHeight | 32 |
| CorridorVaultVerticalScale | 1.9 |
| WallThickness | 3.5 |
| DoorWidth | 30 |
| DoorHeight | 30 |
| ShallowPoolDepth | 1.6 |
| DeepPoolDepth | 2 |
| SlidePoolDepth | 1.8 |
| CorridorChannelDepth | 1.5 |
| DrainableCorridorDepth | 1.8 |
| KidsWadingDepth | .8 |
| HallEdgeWalkwayChance | .5 |
| HallEdgeWalkwayWidth | 4.5 |
| CorridorWalkwayWidth | 2.2 |

**Hall heights:** `hallHeight` (WB:110-116) returns 96 for Grand, 76 for Slide Hall, 33 for Kids, 34 otherwise.

**Water depth by role:** `hallWaterDepth` (WB:205-215).
- Kids, Arrival and Exit: nil (dry).
- Pump Station: 1.2.
- Slide Hall: 1.8.
- `PoolType == "Deep"`: 2.
- Otherwise: 1.6.

**Floor Y:** `hallFloorY` (WB:219-224) is -.8 for Kids and 0 for every other hall.

**Fixed Y datums:**
- Nominal walk level Y = 0.
- Water surface Y = .1.
- `WALKWAY_TOP = .45` for every raised deck (WB:45).
- Water-floor slab top = `-depth` (WB:385-387).
- Wall bottom = `-depth-4`. Wall top = `height+1.85` (buried in the ceiling, WB:236).
- Ceiling slab spans `height .. height+2`.

## 3. Primitives, materials, textures, colours

**Helpers**
- `part()` (WB:49-62): anchored Part, default `C.Tile`, SmoothPlastic, Smooth surfaces.
- `addTexture()` (WB:64-76): one `Texture` named "Level 2 Tile Texture" per face.
  - `TILE_TEXTURE = rbxassetid://113211706146395` (WB:29).
  - `Color3 TILE_TINT (248,242,218)` (WB:30).
  - StudsPerTile defaults to 7.
- `visibleFaces()` (WB:84-90) is gated by `Performance.CullHiddenTileFaces = true` (CFG:164).
- `tiledPart()` (WB:92-96) textures all 6 faces when no face list is passed.
- `surfaceFor()` (WB:194-201) applies the kids texture inside kids halls and the tile texture otherwise.

**Tile studs per surface**

| Surface | Studs per tile |
|---|---|
| Walls | 7 |
| Water-hall floor | 10 |
| Dry floor | 7 |
| Hall ceiling | 9 |
| Columns | 9 |
| Corridor floor | 8 |
| Corridor ceiling | 9 |
| Vault strips | 8 |
| Slide decks and catwalks | 8 |
| Recovery chamber | 9 |

**Colours** (`Configuration.Colors`, CFG:184-197)

| Name | RGB |
|---|---|
| Tile | 228,224,205 |
| TileCool | 206,221,212 (walls, ceilings, corridor shell) |
| TileWarm | 236,227,196 (floors, decks, columns, stairs) |
| Metal | 83,96,99 |
| Rail | 196,202,205 |
| Water | 48,150,159 |
| Light | 255,247,210 |
| Emergency | 194,224,205 |
| Locked | 214,96,78 |
| Void | 7,15,18 |

- `KidsColors` (CFG:200-204): Sun, Coral and Lagoon, each with Color and Accent.
- `SlideColors` (CFG:206-211): green, red, yellow, blue.
- `BOARD_COLORS` (WB:5119-5124).
- `KIDS_BALL_COLORS` (WB:3653-3659).

**Kids surfaces**
- Tile textures come from `ReplicatedStorage."Level 2 Assets"` StringValues: `Level 2 Kids Sun/Coral/Lagoon Tile Texture` (WB:127-131, 154-161). Studs 24, white, Transparency .08 (WB:175-192).
- MaterialVariants (they must exist in MaterialService):
  - `Level2 Kids Foam Vinyl`
  - `Level2 Kids Rubber Floor`
  - `Level2 Kids Slide Fiberglass` (WB:133-135)

**Decal:** pump artwork comes from `ReplicatedStorage."Level 2 Assets"."Level 2 Pump Machinery Texture"` (WB:4270-4294). It is a Decal on the Back face of `Level 2 Pump Machinery Artwork Panel`.

**SurfaceAppearance:** only on column flares. It clones the authored `ServerStorage."Level 2 Column Tile Surface Template"` (WB:36, 1242-1257). If that is missing, it falls back to `TextureID = TILE_TEXTURE`.

**Materials used**
- SmoothPlastic: almost everything.
- Metal: rails, pump, gate.
- CeramicTiles: slide-hall frames, arrival piers and lintels, column fallback, seam backings.
- Neon: light diffusers, portholes, gauges, lamp, gate, invisible marker parts.
- Glass: round skylight panes (.82), kids pool surface (.34).
- WoodPlanks: crates, story door.
- DiamondPlate: pressure doors, gauge panel.
- Rubber: kids pool base and step.
- WedgePart: only the kids foam wedge (WB:3671-3686).

## 4. Room shell builders

### Walls: `makeWallWithGaps`, WB:228-343
- Slabs run along the X or Z axis, 3.5 thick.
- Both ends extend `thickness*.5 + .85` past the room bounds so corners overlap outside the room (WB:296-297).
- **Openings:**
  - Doors are 30 wide, with a lintel from 30 up to `wallTop`.
  - Door sills are added only when `bottomY < -4`, i.e. in water halls.
  - The flume gap has a sill and a header.
- **Visible faces:** the room-side face, plus the jamb end faces at openings only.
- **Colour:** `C.TileCool`, or `palette.Color` in kids halls.

### Floor and water: `makeHallFloor`, WB:358-396
- **Dry halls:** `Level 2 Hall Floor`, W×.7×D, top at 0, TileWarm, Top face only, studs 7.
- **Water halls:** `Level 2 Hall Water Floor`, W×1.2×D, top at `-depth`, TileCool, studs 10. Then `addWater` fills a terrain Water block of `(W+1.5) × (depth+.1) × (D+1.5)` with its top at Y = .1.
- **Kids halls:** slab top at -.8, `palette.Accent`, kids studs 24. Then a terrain "Kids Film" of `.9` height.
- All floors carry `Level2_EntityGround = true`.

### Ceilings

**Main builder:** `makeHallCeiling`, WB:927-1073. It always runs `makeExteriorCeilingEdgeSeal` and `makeInteriorCeilingCove` first.
- **Edge seal** (WB:864-890): 4 × `Level 2 Exterior Light Seal n`, 3 thick, 6 overhang, non-collide, `CastShadow` on, attribute `Level2_CeilingLightSeal`.
- **Cove** (WB:896-923): 4 × `Level 2 Perimeter Shadow Cove n`, 1.25 deep × 3 drop (1.5 in kids halls), `C.Metal`, attribute `Level2_CeilingShadowCove`.

**Skylight plan:** `skylightSlotsFor` (WB:403-487). The same plan is shared with `overlapsSkylight` (WB:587-621), `dodgeSkylight` (WB:1467-1490) and `lightHall`, so lights and columns never land in an opening.
- **Kids halls:** no slots.
- **Arrival:** "Centre" pattern, slot width 14, `clamp(floor(along/58), 2, 4)` slots.
- **Always enclosed:** Pump Station, Entity Den, Entity Den B, Spiral Stair Well.
- **Enclosed by lottery:** `LocalSeed % 6 == 0` makes 1 in 6 ordinary halls enclosed. Skylight Hall archetypes and Slide Halls are exempt.
- **Pattern roll** (`Random(hallKey+4177)`):
  - Lines: under .3, and always for authored skylight halls.
  - Dashed: under .48.
  - Punched: under .66.
  - Centre: under .8.
  - Round: otherwise (falls back to Punched if no templates).
- **Axis:** Z only for Ring Corridor, Porthole Hall and Spiral Stair Well when `hallKey % 3 == 1`.
- **Slots:** `clamp(floor(along/48), 1, 5)` slots, each 12 wide. Slide halls reserve the two column bands (WB:467-485).
- **Open spans:** `skylightOpenIntervals` (WB:492-527).

**Strip skylights** (WB:1013-1072):
- Solid slabs are `Level 2 Hall Ceiling`, 2 thick, studs 9.
- Openings are covered by `Level 2 Frosted Skylight Diffuser`, a .6-thick, **Transparency 1**, CanCollide, `CastShadow false` pane. The "translucent glass roof" in the header comment (WB:12-13) is really an invisible collider; the sun comes straight through an open hole.

**Round skylights** (WB:940-1011):
- Clones UnionOperation templates from `ServerStorage."Level 2 Kids Round Skylight Templates"`:
  - "...Module Small": 22 module, radius 7
  - "...Module Medium": 28 module, radius 10
  - "...Module Large": 36 module, radius 14
- These are defined at WB:535-540 and filtered by `availableKidsRoundSkylightVariants` (WB:542-556). They are authored Studio assets, not built by code.
- Each opening also gets a Glass cylinder at Transparency .82.
- Placement comes from `roundSkylightOpeningsFor` (WB:560-581).

**Kids ceilings:** `makeKidsRoundSkylightCeiling` (WB:747-851) uses `kidsRoundSkylightPlan` (WB:623-700) to place 4-7 modules. The fallback is a solid ceiling plus a Neon disc with a SurfaceLight (WB:702-745).

### Lighting

**The World Builder never touches `Lighting` or Atmosphere.** Halls with skylights get **no artificial lights**; the sun does the work (WB:2144-2147).

**Lights the builder creates (all `Shadows = true`)**

| Source | Location | Light | Settings |
|---|---|---|---|
| `lightHall` (WB:2143-2171) | Enclosed halls only: 1-4 panels, `clamp(floor(W/130),1,2) × clamp(floor(D/130),1,2)`, skipped near column capitals | `makeCeilingPanel` (WB:2119-2141): Metal frame + Neon diffuser + 1 SurfaceLight on Bottom face | Brightness 1.085, Range 44 (CFG:126-127), Angle 115 |
| Recovery chamber | 1 panel, 44×13 | SurfaceLight | Same as above |
| Corridors | 2 per corridor at ±.25 of length, y = `vaultRadius*1.9 - 2.2` ≈ 24.6 (WB:4932-4946) | PointLight | Brightness .7, Range 26 |
| Porthole Hall | Up to 3 portholes, 10×15 Neon (WB:6100-6124) | SurfaceLight | Brightness .49, Range 26, Angle 110 |
| Kids slide tower | 1 per tower (WB:3905-3918) | PointLight | Brightness .85, Range 34 |
| Pump status lamp | 1 per pump (WB:4407-4417) | PointLight | Brightness .294, Range 12 |
| Arrival gate | 6 red nodes (WB:5778-5789) | PointLight | Brightness .315, Range 4 |
| Kids fallback skylight | Only when templates are missing | SurfaceLight | Brightness .56, Range 42, Angle 120 |

**Measured count:** CFG:152-162 records 138 PointLights on seed 1182081016.

**Global lighting (client-side):** LLC:75-128, active only while `workspace.Level2LightingOwnedByController` is set.

| Setting | NORMAL | EXIT_OPEN |
|---|---|---|
| Atmosphere.Density | .16 | .16 |
| ClockTime | 12 | 12 |
| FogStart / FogEnd | 100000 | 100000 |
| EnvironmentDiffuseScale | .62 | .62 |
| EnvironmentSpecularScale | .58 | .58 |
| GlobalShadows | true | true |
| ColorShift_Top | 18,14,8 | 18,14,8 |
| ColorShift_Bottom | 0,5,6 | 0,5,6 |
| Brightness | 1.42 | 1.56 |
| ExposureCompensation | -.22 | -.16 |
| ColorCorrection / Bloom | Bloom Size 24, Threshold 1.35, Intensity .085 | Intensity .11 |

The place runs LightingStyle Realistic (CLAUDE.md).

## 5. Water: terrain, plus a few visual parts

- `addWater` (WB:349-354) runs `Terrain:FillBlock(..., Water)` and appends the region to `waterRegionsRef`, which is returned as `manifest.WaterRegions`.
- **Regions:**
  - Each water hall: top at .1, 1.5 overlap into the walls.
  - Each corridor: `(length-1) × (depth+.1) × (width+1.5)` (WB:4949-4953).
  - Kids film (WB:371-373).
  - Kids raised pool core, inset 12 because of 4-stud voxels (WB:1100-1109).
- The only water *parts* are `Level 2 Kids Pool Water Surface` (Glass .34, attribute `Level2_WaterVisual`, WB:1110-1120).
- Water is always a flat sheet at Y = .1. That assumption is built into every hall and corridor.

## 6. Columns, arches, vaults, stairs, rails

### Columns: `makeColumn`, WB:1340-1460
- The `radius` argument is really the **diameter**: the cylinder size is `(H, radius, radius)`.
- **Shaft:** `Level 2 Tiled Column` cylinder, TileWarm, studs 9. Non-essential columns get barrel faces only.
- **Flares:** 2 `Level 2 Column Flare` MeshPart clones per column, size `diam*2.22 × flareLength`, with `flareLength = clamp(diam*1.35, 7.2, 10.2)`. The seam yaw points at the nearest wall (`hiddenColumnSeamYaw`, WB:1267-1285).
- **Base collision:** 5 nested invisible cylinders `Level 2 Column Base Flare Collision 01-05`, tagged `Level2_EntityGround` (WB:1303-1338, profile bands at WB:1161-1167).
- **Fallback when the asset fails:** 5 CeramicTiles rings per end.
- **Registry:** `columnRegistry` (WB:1127-1149) prevents overlap within 9 studs. An `essential` column (the spiral mast, diameter 8) destroys any decorative column it overlaps.

### Colonnades: `makeColonnade`, WB:1552-1590
- Per row: `clamp(floor(long/38), 2, 8)` columns of diameter 5.5, standing at `-depth` with height `H+depth`.
- Skipped near doors (20) and the navigation hub/spokes (17, `nearHallNavigationRoute`, WB:1520-1549; `nearDoorApproach`, WB:1494-1512).

**Rows per archetype (WB:6039-6098)**

| Archetype | Row offsets |
|---|---|
| Pillar Basin / Diving Well | ±.6 |
| Column Forest | -.62, 0, .62 |
| Curved Gallery | -.56 |
| Flooded Gallery | ±.64 |
| Arch Tunnel | ±.58 |
| Skylight Hall | ±.5 |

### Arches: `makeArchSpan`, WB:1778-1867
- Elliptical arc, from `-dip` to `π+dip`, with the feet dipping below the floor.
- `steps = max(MinimumSteps 14, ceil(r*Density 1.9))`.
- Each segment is a 3.2×2.2 band Part. Kids styling and the `CanCollide` flag are handled here.
- **Mesh-rib path** (WB:1794-1835) is used when `MeshRib`, not kids, and `archMeshEnabled()` (`Performance.ArchMeshRibs = true`, CFG:179; overridable by `workspace.Level2ArchMeshRibs`). It builds:
  - 1 non-colliding MeshPart `Level 2 Arch Rib <i>`
  - 2×4 invisible colliding `Level 2 Arch Rib Foot` Parts
- **Ring Corridor archetype** (WB:6053-6083) uses free-standing rings: 3-7 of them, radius = `min(shortSide*.5-6, H-5, min(DoorWidth*.5-2, DoorHeight-2))`.

### Barrel vault: `makeBarrelVault`, WB:1873-1911
`max(12, floor(r*1.5))` long `Level 2 Vault Strip` Parts, 1.6 thick, Bottom face textured, studs 8.

### Stairs and rails
- **`makeStairFlight`** (WB:1932-1955): step *i* is a solid block from the base up to `i*rise`. Default run 2.3, rise .78. Tagged `Level2_EntityGround`.
- **`makeStairSideRails`** (WB:1959-1969).
- **`makeRail`** (WB:1913-1930): a .42 bar at 4.2 height, with posts every 9 studs (Metal, `C.Rail`).
- **`makeSpiralStair`** (WB:1971-2018):
  - Whole turns only: `max(2, floor(Δy/34+.5))`.
  - `steps = max(floor(Δy/1.05), ceil(turns·2π·r/3.2))`.
  - Treads `r*1.45 × .7 × 6.4`, plus guard posts and rails.
  - Mast is an essential column of diameter 8.
- **`spiralStairPlacement`** (WB:2028-2117): radius 13, structure radius 22.75. It docks the stair in a quadrant clear of the doors and the centre lines.

## 7. Room types and set pieces

### Plain water halls
Archetype dressing, then the following:
- **`makeHallEdgeWalkway`** (WB:5355-5408):
  - 50% chance, `Random(LocalSeed+37)`.
  - 4.5-wide deck, top .45, 1.9 in from the wall.
  - 1.2-wide submerged curb, top -.8.
  - Sets the attribute `Level2_EdgeWalkway` on the hall model.
- **`decorateLargeHall`** (WB:5447-5701), only when `Area ≥ 12000`. Spots are claimed and every far end of each structure is checked against doors, the navigation route, walls and other structures (`fittingYaw`, 8 yaws × 45°). It builds:
  - Diving tower if `Area ≥ 15000` (`makeDivingTower`, WB:5180-5237): boards at 4.5/7.5/10.5, plus 13.5 if `Area ≥ 34000` (50% chance).
  - 1-4 slide kits (`makeSlideKit`, WB:5130-5174): 8×8 pad at height 4.5-8 on legs, stair, open chute of radius 2.6.
  - Play towers if `Area ≥ 26000`, 2 if `≥ 52000` (`makePlayTowerKit`, WB:5412-5440): 13×13 deck at 10-14, tube radius 4.2.
  - Railed overlook if `Area ≥ 28000`: landing at 7, stair 10 wide.
  - 4-12 floats: rafts 4×.7×7.2 and rings 6.4.
  - Centre island if `Area ≥ 48000`: 19-diameter cylinder plus two columns of diameter 4.5.
  - Attribute `Level2_DivingOutcome`.
- **`dressHall`** (WB:5015-5116):
  - Loungers when depth ≤ 2.2.
  - Beach balls (2-10) and noodles (3-12). These are **unanchored and buoyant** (`makeBuoyant`, WB:4974-4983, attribute `Level2_BuoyantProp`) and placed through `freeWaterSpot`'s overlap query (WB:4987-5008).
  - A stopped clock.
- **Porthole Hall:** 3 Neon panes on the north wall.

### Pump Station halls
- **`decoratePumpHall`** (WB:5242-5345):
  - 6.5-wide walkway ring around the walls, a cross, and a 26×18 island, all at top .45.
  - 3-5 crates and a gauge panel.
  - A diving tower when the hall is at least 80×80.
  - Painted safety stripes.
- **`makePumpStation`** (WB:4312-4647): about 60 Parts plus a SurfaceGui gauge, a welded lever assembly and a ProximityPrompt (`START PUMP`, hold 1.6, distance 10). The whole model is scaled with `Model:ScaleTo(.34)` and re-grounded. Its returned table is the objective controller's contract.

### Slide Hall: `makeSlideHall`, WB:3002-3214
- **Corner columns:** 4 of diameter 9 at ±30% offsets.
- **Scale frames** (`makeSlideHallScaleFrames`, WB:2924-2997): 3-9 frames. Each has a CeramicTiles beam (4×3) at `H-1.5` and 5×6 collidable piers.
- **Deck:** `Level 2 Slide Hall Deck` at `deckY = H-22` (54, or 74 in the Grand hall), depth `min(46, D*.3)`, 2 thick.
- **Flumes:** 3 open-top lanes (`SlidesPerHall 3`, `SlideTubeRadius 7.5`), `laneStep = max(25, min(34, W*.18))`, Bézier curves via `makeSlideTube`, entry tubs via `makeEntryTub` (WB:2708-2919).
- **Helix slide** (`makeHelixSlide`, WB:2671-2700): tube radius 4.6, helix radius 12-16, 2.1 turns, around its own column of diameter 9, with a 14-wide catwalk bridge.
- **Spiral stair:** radius 12 in the south-east corner, from `-depth+1` to `deckY+.65`.
- **East catwalk, rails and seam backings.**
- **Returns** `{Folder, DeckY, DeckZ, DeckDepth}`.

### Grand Slide Hall / exit: `makeExitFlume`, WB:3228-3649
The Grand hall is the Slide Hall with `IsGrand` set; it is also the exit hall.
- **Closed tube**, radius 8:
  - Start: (`MaxX-14`, `deckY+9.3`).
  - A 72-segment Bézier plunge down to `plungeEnd = (shellX+41, 4)`, with `shellX = Bounds.MaxX + 60`.
  - A transfer of 250 studs at grade .21.
  - A helix of radius 96, 3 turns, 6° steps, ending at Y ≈ -428.
- **Built by** `makeTubeFromPoints(..., closed, forceOneWay = true)`, which tags `Level2_OneWayExit`.
- **Model attributes** used for the endless "recycle": `Level2_RecycleActive`, `Level2_RecycleTriggerY`, `Level2_RecycleDeltaY`, `Level2_HelixCenterX/Z`, `Level2_HelixRadius`, `Level2_HelixTopY/BottomY`, `Level2_FlumeBoreRadius`.
- **End stop:** `Level 2 Exit Transition End Stop`.
- **Wall collar:** 32 segments at `hall.MaxX`.
- **Recovery chamber:** sealed, 78×78×30, placed at `DeckZ+300`. It holds a WoodPlanks story door (12×14), a ceiling panel, and `Level 2 Exit Safe Spawn` (attribute `Level2_ExitRecoverySpawn`).
- **Completion sensors:** `Level 2 Exit Completion Beam` and `... Backstop`, invisible, 9 thick, attribute `Level2_ExitCompletionBeam`.
- **Returns** `HallWallGap`, `PathPoints`, `Recycle` and related fields (WB:3609-3648).

### Kids area: `makeKidsHall`, WB:3943-4241
- **Reservation solver:** door clearances of 32×38, a navigation hub of 24, spokes, a 60×52 pump zone when the hall has a pump, and a Pool Foam spawn of 8×8 that must succeed (`assert`).
- **Archetypes:**
  - Pump Playroom.
  - Splash Room: `makeRaisedPool` (WB:1076-1121), 5 size tiers.
  - Slide Tower: `makeKidsSlideStructure` (WB:3829-3941), with Full/Compact/Micro/Nano tiers.
  - Ball Pit Room: `makeKidsBallPit` (WB:3723-3795). It builds a hex-packed bed of individual ball Parts; the full 34×30 pit is about 600 Parts (attribute `Level2_BallCount`). Crawl frames come from `makeKidsCrawlFrames`.
  - Sparse Abandoned Room.
- Every kids room also gets foam clusters (`makeKidsFoamCluster`).

### Arrival: `makeArrivalConcourse`, WB:5705-5822
- Dry floor.
- 3 pier frames at 26, 58 and 90 studs along the room direction: 4×(H-4)×4 piers at ±22, with a 48×3×4 lintel.
- A story-only "Energy Transfer Gate" on the rear wall with SurfaceGui text "ANOMALOUS SPACE HAS BEEN LOST" and "ENTRY LOCKED".
- Spawn is 5.5 studs in front of the gate.

### Entity Den (A and B)
LG:621-625 sets roles "Sunken Basin" (Deep) and "Column Forest". The den is enclosed, so it gets ceiling panels plus the generic dressing.

## 8. Tunnels: `makeCorridor`, WB:4653-4970 (the instance hotspot)

**SharedWall corridors** (WB:4654-4682) are only two 4.7-wide threshold slabs.

**Standard corridor, piece by piece:**
- **Floor:** `Level 2 Corridor Water Floor`, `(len+4) × 1.2 × width`, top at `-depth`.
- **Side ledge:** top .45; the slab runs from 9.1 to 15.4 studs off the centreline. Plus a curb with top -.8 (WB:4754-4789).
- **Shell:** 2 × `Level 2 Corridor Wall`, from `-depth-3` up to 34. 1 × `Level 2 Corridor Ceiling` at 32-34.
- **Arch ribs:** `clamp(floor(len/22), 3, 7)` ribs. Arch radius = `min(w*.5-3, 13.2)`, so 13.2 at width 34; steps 26.
  - With the mesh pilot, each rib is 1 MeshPart plus 8 invisible feet. Otherwise each rib is 26 textured Parts.
- **Barrel vault:** radius 14.1, 21 strips.
- **Portals, per end:**
  - 1 header.
  - Up to **32 spandrel slats**, each with 2 Textures.
  - A **30-segment face ring** (`MinimumSteps 28`, Density 2.1), each segment with 2 Textures.
  - That is about **126 Parts and about 250 Textures per corridor in the portals alone** (WB:4850-4928).
- **Lights:** 2 PointLights.
- **Water:** terrain water region.
- **PressureDoor kind:** `Level 2 Pressure Door <i>` (DiamondPlate, `C.Locked`, `2.2 × (H+4) × width`, attribute `Level2_CorridorIndex`) plus a Neon stripe, in `Level 2 Pressure Doors`.
- **Returns** `{Corridor, Water, Door, Stripe, Center}`.

**Measured counts (CFG:152-180, seed 1182081016):**
- 74,654 descendants, of which 44,923 were Textures.
- With mesh ribs on: 56,001 vs 71,771 descendants, and 29,103 vs 42,051 Textures.
- Texture owners: Corridor Wall 696, Tiled Column 630, each hall wall 416-424, Arch Rib 228.

## 9. MeshPart templates (`AssetService:CreateMeshPartAsync`)

**Adoption rule:** each loader first adopts a MeshPart already sitting in **ServerStorage root** under the exact template name with a matching MeshId (for arch ribs: matching key attribute). It re-stamps the attributes and caches it in a module-local table. Only if none exists does it create one and parent it to ServerStorage. These copies are saved with the place, which is why the adoption step exists (WB:1190-1207, 2226-2236, 1736-1742).

| Template (ServerStorage name) | Asset | Loader | Fidelity |
|---|---|---|---|
| `Level 2 Column Flare Template <diam:flareLen>`, e.g. `5.500:7.425`, `9.000:10.200`, `4.500:7.200` | 4.5 → 90304501186271; 5.5 → 118916035196716; 9 → 111134467625970; fallback 90196117593704 (WB:31, 1153-1157) | `getColumnFlareTemplate` WB:1180-1263 | Collision Box, Render Automatic |
| `Level 2 Sealed Open Slide Segment Template` | 134677774662968 | `slideTemplate` WB:2276-2301 via `loadSlideMeshTemplate` WB:2222-2259 | Box / Precise |
| `Level 2 Open Slide End Cap Template` | 107012498668441 | WB:2303-2310 | Box / Precise |
| `Level 2 Fitted Slide Cradle Template` | 132916619634128 | WB:2312-2325 | Box / Precise |
| `Level 2 Closed Slide End Cap Template` | 107409495820821 | WB:2266-2274 | Box / Precise |
| `Level 2 Arch Rib Mesh r13.20_vs1.90_fd1.50_a3.20_d2.20_s26` and `..._fd1.80_...` | 121489049526127 / 105818906248010, group-uploaded and already in ServerStorage (artifacts/codex-polish-20260923/README.md:65-66) | `archRibMeshTemplate` WB:1722-1776 (EditableMesh path is Studio-only) | PreciseConvexDecomposition / Precise |

**Not built by code (authored assets that must exist):**
- `ServerStorage."Level 2 Slide Assets"."Level 2 Slide Templates"."Level 2 Slide Closed Segment" / "...Open Segment"` (the closed exit tube uses this one, WB:2291-2299).
- The kids round skylight UnionOperations.
- The column SurfaceAppearance template.

**Possible leak:** if a flare variant asset fails and the fallback mesh loads, the saved template's MeshId no longer equals the variant id (WB:1214-1222 vs 1200). The next session will not adopt it and will build another copy.

## 10. Y and height: what exists today

- **The whole map is flat.** Every hall centre is at Y = 0. Halls are only recessed by the water depth (1.2-2.0) and kids floors sit at -.8. Corridors connect at the same Y.
- **There are no slopes:** no ramps, terrain hills or WedgeParts, except the kids foam wedge.
- **Vertical content:**
  - Slide decks at `H-22`.
  - Spiral stairs.
  - Stepped solid stair blocks in kits, towers and the overlook.
  - Diving boards up to 13.5.
  - The exit flume descending to about -428.
- **Unreachable code:** the deep-water doorway stairs (WB:6139-6168) and the corridor end steps (WB:4733-4743) only run when `depth > 2.5`. The deepest current config value is `DeepPoolDepth 2`, so neither ever builds.

**What height variation would break:**
1. The flat terrain water sheet at Y = .1, used for every region.
2. The `WALKWAY_TOP .45` and curb -.8 constants.
3. `hallFloorY`, the navigation node and patrol node Y values.
4. The column registry's `|ΔY| < 30` test.
5. `freeWaterSpot` probing at Y = 1.4.
6. The navigation tags: `Level2_EntityGround` on walkable slabs and steps; `Level2_NoEntityGround` on slide floors and roofs; `PathfindingModifier "Level2Roof"`. The Pool Foam navigator's step test (`_isSteppable`, quoted in WB:1328-1334) depends on all of these.

## 11. Replace map for the rewrite

| Area | Functions (line ranges) | Rewrite intent |
|---|---|---|
| Room shell | `makeWallWithGaps` 228-343, `makeHallFloor` 358-396, the ceiling family 403-1073 (incl. kids round skylights 535-851, seals and coves 858-923), `lightHall`/`makeCeilingPanel` 2119-2171 | Replace with kit room modules |
| Tunnels | `makeCorridor` 4653-4970, `makeArchSpan` 1778-1867, `makeBarrelVault` 1873-1911, arch-mesh pilot 1624-1776 | Replace with kit corridor modules |
| Columns | 1127-1590 | Kit props |
| Dressing | `dressHall` 5015-5116, `decorateLargeHall` 5447-5701, kits and towers 5130-5237 and 5412-5440, `makeHallEdgeWalkway` 5355-5408, `decoratePumpHall` 5242-5345 | Meshy/Blender props |
| Gameplay contracts (keep or port carefully) | `makePumpStation` 4312-4647; `makeSlideHall` 3002-3214 plus the slide/tube system 2177-2700 and `makeEntryTub` 2708-2919; `makeExitFlume` 3228-3649 (recycle attributes, sensors, recovery chamber); `makeKidsHall` 3943-4241 (Pool Foam spawn reservation); `makeArrivalConcourse`/`makeCompatibilityArrival` 5705-5886; the `Build` manifest 6334-6355 | Keep the contracts; the slide system's collision is physics-tuned |
| Roof pass and water | 6317-6332 and `addWater` | Must survive in some form |