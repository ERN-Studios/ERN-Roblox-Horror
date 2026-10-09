# Level 2 v2 kit spec (style C "Leisure Centre 1989")

Source of truth for the Blender kit, the new layout generator and the kit builder. Built on `ANALYSIS.md`
(the world contract in section 3 is binding) and the owner's answers of 2026-10-02/03.

## 0. Owner decisions this spec implements
- Developer preview first, next to live Level 2. Real round (Pool Foam + Pool Slide, pumps, exit), no progression.
- NEW random layouts assembled from Blender rooms. Mixed scale: big halls, small rooms, narrow passages.
- Style C: white and pale-teal glazed tile, coral / sun-yellow / lagoon-blue bands, terrazzo decks, glass block,
  chrome. References: `G:/Roblox/_local/l2blender/style/l2_C_*.png`.
- Height: sloped pool floors (shallow to deep), steps/ramps between rooms, varied ceiling heights. No hills.
- Water: wading only, deep end at most ~3.5 studs and never deep enough to swim (measured in Studio, section 9).
- Tunnels stay tunnels, one Blender mesh set per tunnel instead of ~470 parts.
- Narrow passages 10-12 studs wide as an escape route: players and Pool Foam fit, the Pool Slide does not.
- Small rooms: changing rooms with lockers, and plant/pump rooms.
- Slides: visuals AND collision rebuilt in Blender with far fewer instances; players must still slide, exit included.
- Mobile first: low polycount, 1K maps, few lights. Instances as low as possible.
- Approval stops: Blender renders before any Roblox import. Local commits only, never publish.

## 1. Units and conventions
- Blender metres, **0.28 m per stud** (same as the Level 1 and Level 4 kits). Blender (x, y, z) -> Roblox (x, z, -y).
- All gameplay numbers below are in **studs**.
- Kit master: `G:/Blender/Level2_Pool/Level2_PoolKit.blend`, written only by `tools/level2_blender/build.py`
  run headless (`blender -b --factory-startup -P ...`). Never open the owner's GUI Blender; never save over a
  finished file; at most 4 Blender processes at once.
- Export: `assets/level2/blender-kit/export/` (manifest.json + chunk wire files, Level 1 wire format).
- Every mesh chunk is ONE material, so it becomes ONE MeshPart with a MaterialVariant (no SurfaceAppearance).
  Meshy props are the exception: one atlas -> one MeshPart + one SurfaceAppearance.
- Mesh UVs are written in **texture repeats** (u = surface metres / tile_m), so a MaterialVariant repeats at the
  same physical size on Parts and on MeshParts. Studio check in section 9 confirms how StudsPerTile treats meshes.

## 2. Materials (MaterialService, BaseMaterial SmoothPlastic)
| Variant | PBR set | Repeat | Use | Tint via Part.Color |
|---|---|---|---|---|
| `L2K Tile` | tile_white | 1.0 m | walls, ceilings, columns, arches, bands | white; bands coral (238,120,98), yellow (244,196,72), blue (52,150,196); dado pale teal (150,205,200) |
| `L2K Mosaic` | mosaic_aqua | 1.1 m | pool basins (floor + walls), tunnel channel | white |
| `L2K Cobalt` | mosaic_cobalt | 1.1 m | lane lines, basin edge band | white |
| `L2K Terrazzo` | terrazzo | 1.2 m | decks, walkways, ledges, stairs, coping | white |
| `L2K Glass Block` | glassblock | 0.8 m | window panels | white |
| `L2K Service` | concrete_paint | 2.4 m | narrow passages, plant rooms | white / grey |
| `L2K Rubber` | rubber_kids | 1.2 m | kids rooms floors | white |
| `L2K Steel` | steel (metal 1) | 0.5 m | ladders, rails, pipes, grates | white |
| `L2K Bands` | bands (derived, `make_bands.py`) | 1.0 m block | the coral/yellow/blue stripe block on MESHES (columns, arches, tunnels, wells): v 0..1 spans one block (1 m = 3.57 studs tall, rows W C C W Y Y W B B W), u repeats along the length | white |

Meshes that show bands use one `Bands` chunk with explicit UVs (v from the band's bottom to its top), so a banded
column or arch is 2 MeshParts (Tile + Bands), not 4. Parts (walls) still use three tinted `L2K Tile` strips.
Maps: `G:/Blender/Level2_Pool/textures/pbr/<set>_{albedo,normal,rough[,metal]}.png`, 1024 px.
Spec: `tools/level2_blender/pbr_spec.json`. Eight variants x 3-4 maps is the whole architectural texture budget.

## 3. Geometry rules (from the contract; every kit piece obeys them)
1. Big flat surfaces (walls, floors, decks, ceilings, basin sides) are **Parts** with a MaterialVariant: one
   instance each, any size, and the visual IS the collider, camera occluder and sight blocker.
2. Shaped features (arches, coping, columns, skylight wells, vaults, pipes, lamps, props) are **MeshParts** with
   `CanCollide = CanQuery = CanTouch = false`, `CastShadow` only on large features. Where a feature must block
   movement or sight, it gets a simple box/cylinder Part that matches what players see through.
3. No colliding mesh anywhere except slide collision (section 7), which is its own contract.
4. Every walkable collider: `Level2_EntityGround = true`, under the world model, present before Pool Foam starts.
   Each collider piece rises at most 3 studs across its own footprint and is at least 4 studs across.
5. Roof colliders: one per hall/tunnel/passage, name contains `Roof`. NO other kit part name contains
   `Ceiling`, `Skylight` or `Roof` (the roof pass would make it unwalkable). Visible ceiling Parts are named
   `Level 2 Overhead Tile ...`.
6. Default collision group only. Terrain water only (one region per wet hall and wet tunnel, flat surface).
7. Pool Foam lanes stay clear: halls +-17 studs along both centre axes and every door spoke; kids rooms a 24-wide
   hub. Props never stand in a lane.
8. Prop name prefixes `Level 2 Lounger Seat`, `Beach Ball`, `Pool Noodle`, `Pool Raft`, `Pool Float Ring` are
   reserved (the slide ragdoll service adds 6 textures to each). Kit props use `L2K <Prop>`.

## 4. Spaces
### 4.1 Big halls (procedural shell + kit modules)
- Footprint: rectangle on a 4-stud lattice, 96..272 per side. Ceiling class 34 / 42 / 52 (slide halls 76,
  grand hall 96). Floor Y per hall from {-8, -4, 0, +4, +8} (section 6).
- Floor: terrazzo deck Parts around a recessed pool basin. Deck top = hall FloorY. Basin floor is one tilted
  Part (`L2K Mosaic`) from shallow -0.8 to deep `DeepEnd` (default 2.0, studio-measured max <= 3.5), named
  `Level 2 Hall Water Floor <i>`. Pool steps (2 x 0.6 rise) at the shallow end; a ladder module at the deep end.
  Lane lines: 4-6 thin cobalt Parts following the slope. Deck width 10-18 around the pool; the pool covers
  60-80 % of the hall.
- Walls: tile Parts per run between openings + one dado Part (pale teal, 0..3 above deck) per run +
  three band Parts (coral/yellow/blue, 0.6 tall, 0.1 proud) running unbroken above the door tops (y 31..33 for
  ceiling 34; at 1/3 height and under the cove for taller halls).
- Openings: big door 30 x 30 (tunnels), service door 12 x 16 (narrow passages). Each opening gets a door
  module (section 5).
- Ceiling: tile Parts on a slot grid leaving square holes where skylight modules sit. Classes 42/52 add
  a cove module along the wall top.
- Lights: skylights carry the day; enclosed halls get 1-2 ceiling panels (SurfaceLight, no shadows).
- Glass-block window panels set into some walls (Part, `L2K Glass Block`), never in front of a door spoke.

### 4.2 Small rooms (authored Blender prefabs)
| Prefab | Footprint | Ceiling | Floor | Contents |
|---|---|---|---|---|
| `ChangingRoom_A` | 64 x 48 | 22 | terrazzo | 2 locker banks, 2 benches, 4 cubicles (Blender), mop bucket |
| `ChangingRoom_B` | 64 x 80 | 22 | terrazzo | 4 locker banks, 3 benches, 6 cubicles, kickboard rack |
| `PlantRoom_A` | 64 x 64 | 24 | service concrete | 2 sand filters, pump unit, drums, pipe manifold (Blender), hose reel |
| `PlantRoom_B` | 80 x 64 | 24 | service concrete | 3 filters, 2 pump units, drums, manifold, catwalk-free |
- Dry, flat. Openings are ONLY service doors (12 wide x 16 tall) at fixed sockets: the centre of each wall
  (and at +-16 off centre on the 64/80 walls). Unused sockets are closed with a wall Part.
- Small rooms connect only through narrow passages, so the Pool Slide never enters them.
- Layout role: `Role = "Small"`, Archetype `Changing Room` / `Plant Room`, PoolType `Dry`.

### 4.3 Tunnels (34 wide, existing envelope)
- Lengths quantised by the generator to {56, 64, 72, 80}. Interior and doorway envelope identical to today
  (width 34, rib line +-12.1 at floor level, vault 32 high), so the Pool Slide corridor-fit certification holds.
- Variants: `Wet` (channel 1.5 deep, terrazzo side ledges, lane lines), `Drain` (1.8 deep), `Dry` (no water),
  `Stair` (dry, rises 4 or 8 over its length with 0.78 x 2.3 steps), `Kids` (rubber floor, kids band colours).
- Mesh set per (variant, length): vault tile chunk + band chunks (3) + terrazzo chunk + mosaic chunk + cobalt
  chunk -> at most 7 MeshParts. Bulkhead lamps are geometry; one PointLight per tunnel, Shadows false.
- Colliders per tunnel: floor, 2 ledges, 6 side colliders (inner face +-12.1), roof collider. Total per tunnel
  about 18 instances (today ~472).

### 4.4 Narrow passages (escape routes)
- Width **12** (clear 11), height 16, service style: painted concrete, pipe runs and a cable tray overhead,
  caged bulkhead lamps, floor drain grates. Lengths {16, 24, 32, 48, 64, 80}; a `Stair` variant rises 4.
- Layout: a corridor record with `Width = 12`, `Kind = "Narrow"`, straight and axis-aligned like every corridor.
- Pool Slide (body ~15 wide) cannot path through (its pathfinding agent cannot fit; its graph route must skip
  `Width < 16`, a small Pool Slide navigator change). Pool Foam (body 4.2) uses them normally.

### 4.5 Special halls (fixed prefabs, gameplay-critical)
- `SlideHall` 208 x 176, ceiling 76: deck at H-22, 3 flumes + 1 helix authored in Blender (section 7).
- `GrandSlideHall` 224 x 208, ceiling 96 (exit hall, east edge): deck, flume mouth, pressure-door tunnels.
- `PumpHall` (big hall recipe + pump station prefab at centre): pump shell from Meshy around the existing
  gameplay parts (lever, gauge, lamp, prompt, intake pipe) honouring the manifest `Pumps[i]` fields.
- `Arrival` (big hall recipe, dry deck, story gate mesh, 32 x 30 clear spawn apron).
- Kids rooms (5): big-hall recipe with rubber floors, kids palette bands, splash pool, ball pit as one mesh.

## 5. Kit modules (Blender components)
| Module | Size (studs) | Materials (chunks) | Tri budget |
|---|---|---|---|
| `DoorArch30` | opening 30 x 30, frame 36 wide, 3.5 deep + 0.6 proud | Tile, 3 bands, Cobalt edge | 1500 |
| `DoorService12` | opening 12 x 16, steel frame + tiled reveal | Tile, Steel | 600 |
| `Coping{8,16,32,64}` | bullnose pool edge, 1.2 wide | Terrazzo | 120-600 |
| `Gutter{16,32,64}` | grated overflow gutter | Steel, Mosaic | 200-800 |
| `Column{4.5,5.5,9}` x height class | tiled shaft, flared base, 3 bands | Tile, bands | 800 |
| `SkylightWell{S,M,L}` | ceiling panel 36/44/52 square with round hole r 10/14/18, banded well 6 deep | Tile, bands | 900 |
| `Cove{16,32,64}` | ceiling cove trim | Tile | 150 |
| `Ladder` | chrome pool ladder | Steel | 600 |
| `PoolSteps` | shallow-end steps 12 wide | Terrazzo, Mosaic | 300 |
| `StairFlight{4,8}` | 10-wide steps, rise 0.78, run 2.3 | Terrazzo | 400 |
| `DivingTower` | 3 platforms 4.5/7.5/10.5, stairs, rails | Tile, Terrazzo, Steel | 2500 |
| `LampPanel` | enclosed-hall ceiling light | Steel + Neon | 200 |
| `PipeRun{16,32,64}`, `CableTray{16,32,64}`, `Grate` | narrow passages, plant rooms | Steel, Service | 300 |
| `Cubicle`, `Manifold` | changing-room cubicle, plant-room pipe manifold | Tile/Steel | 800 |
| `Tunnel_<variant>_<len>` | section 4.3 | up to 7 | 3000 |
| `Passage_<variant>_<len>` | section 4.4 | Service, Steel | 1500 |
| `GateStory` | arrival gate | Tile, Steel, Neon | 2000 |
| `BallBed{S,M,L}` | kids ball pit fill | (vertex-coloured -> one tinted chunk per colour) | 3000 |

Meshy props (one atlas each, <= 2.5k tris after decimation, 1024 or 512 maps): bench, bulkhead lamp, drums, sand
filter, float ring, hose reel, kickboard rack, lane-rope reel, lifebuoy, lifeguard chair, lockers, lounger,
mop bucket, pump shell, starting block, pool vacuum. Task ids: `G:/Roblox/_local/l2blender/meshy/tasks.json`.

## 6. Layout generator v2 (new module, live generator untouched)
- New ModuleScript `Level 2 Kit Layout Generator` (copy of the live generator's seed, retry, graph and role logic;
  only the geometry step changes). Output keeps the live layout contract (ANALYSIS 3.3) plus new fields.
- BSP leaves become either one big hall (lattice-snapped) or a **small-room cluster**: 2-4 small prefabs packed in
  the leaf, joined to each other and to neighbouring halls by narrow passages. Target mix per round: ~26 big halls,
  ~10 small rooms, ~12 narrow passages, ~55 tunnels.
- Tunnels join big halls only; lengths snapped to {56,64,72,80}; door centres at least 21 from a corner.
- Roles (arrival, 3 slide halls incl. grand, 3 pumps, 5 kids, 2 dens) are chosen among big halls only. The big
  halls must be fully connected by tunnels alone; small rooms are extras.
- Height: per-hall `FloorY` from a separate RNG (`layout.Seed + 0x2B1E`); |dY| <= 8 across any connection;
  level changes only through `Stair` tunnels/passages; arrival, kids block, pump halls and every Drain,
  PressureDoor and Wet tunnel are flat at both ends. Corridor records gain `FromY`/`ToY`.
- `Hall.CeilingClass`, `Hall.DeepEnd`, `Hall.PoolAxis`, `Hall.Prefab` (small and special rooms).
- Pool Foam and Pool Slide navigators: carry hall FloorY into the graph route (~10 lines each); Pool Slide skips
  corridors with `Width < 16`. Both offline-tested before Studio.

## 7. Slides (owner: rebuild visuals + collision, keep the slide)
Detailed contract and design come from the slide-system reader (pending). Fixed constraints already known:
- Collision parts carry `Level2_SlideFloor`, `Level2_SlideDirection` (Vector3), `Level2_NoEntityGround`, and
  `Level2_OneWayExit` on the exit; the first collidable part under the rider must be the slide floor; grade >= .20
  starts a slide; exit bore 8; helix radius 96 x 3 turns; recycle attributes on the flume model; test-suite
  thresholds (TransitionLength >= 2000, PathPoints > 32, sensors 9 thick).
- Slides live inside the fixed SlideHall / GrandSlideHall prefabs, so their shape is authored once in Blender.

## 8. Instance budget (typical round)
| Bucket | Target |
|---|---:|
| 26 big halls x ~45 (deck/basin/walls/bands/doors/ceiling/lights/nodes) | 1,170 |
| Big-hall modules and props (~14 per hall) | 1,100 |
| 10 small rooms x ~40 | 400 |
| 55 tunnels x 18 | 990 |
| 12 narrow passages x 12 | 144 |
| Slide halls + exit (visual + collision) | <= 1,500 (section 7) |
| Pumps, arrival, kids sets, dens, markers, nodes | 600 |
| Pool Foam rigs + Pool Slide | 700 |
| **Total** | **~6,600** (live: ~56,000) |
Lights <= 80, shadow-casting <= 6. Verified in Studio as `Level2_WorldDescendants` on 3 pinned seeds.

## 9. Studio checks before trusting the kit (in the gated Studio phase)
1. MaterialVariant on a MeshPart: does StudsPerTile scale mesh UVs? (one MeshPart, two StudsPerTile values).
2. Swim threshold: deepest wading depth before the Humanoid swims (2.0, 2.5, 3.0, 3.5).
3. Upload route vs runtime bake (Level 6 precedent `Level6BlenderRuntimeBake`) for kit meshes.
4. Pool Slide cannot enter a 12-wide passage (pathfinding + graph route).
5. Phone frame time (Device Simulator + one real phone if the owner agrees).

## 10. Install and runtime contract (the importer writes it, the kit builder reads it)
Kit export: `assets/level2/blender-kit/export/manifest.json` (+ `chunks/cNNNNN.b64`, Level 1 wire format) and
`slides.json` (slide records, `readers/read-slides.md` design (i)). The Studio install (gated, later) creates:
```
ServerStorage.Level2BlenderKit (Folder)            attrs: Ready (set LAST), KitBuild, ManifestSha256
  Components (Folder)
    <Component> (Model, WorldPivot = component origin; attrs = component attrs)
      <Component>_<Material> MeshPart per chunk    MaterialVariant + Color (or SurfaceAppearance "Atlas" for
                                                   Meshy atlases), Anchored, CanCollide/CanQuery/CanTouch false,
                                                   CastShadow when its largest side > 8, CollisionFidelity Box
      <part record> Part                           SmoothPlastic + MaterialVariant + Color, CanCollide = CanQuery
                                                   = record.collide, attrs (+ Level2_EntityGround if ground)
      <collider record> Part                       Transparency 1, CanCollide + CanQuery true, CanTouch false,
                                                   Shape Block/Cylinder, Level2_EntityGround if ground
      Markers (Folder)                             CFrameValue per marker (Name = marker name, Value = local
                                                   CFrame), marker attrs copied onto the CFrameValue
  SlideTemplates (Folder)                          unit-length collision MeshParts, PreciseConvexDecomposition,
                                                   CustomPhysicalProperties(.7, .05, .05, 1, 1), Transparency 1
  Data (Folder)                                    StringValues SlidesJSON-001.. (split <= 190k chars)
MaterialService: MaterialVariants `L2K Tile`, `L2K Mosaic`, ... (section 2), StudsPerTile = tile_m / 0.28
```
Runtime rules for `Level 2 Kit World Builder`:
- Clone a component, read and destroy its `Markers` folder, `PivotTo` the target CFrame (yaw in 90-degree steps
  only), then FLATTEN: small modules (coping, gutters, columns, lamps, props) move their children into the room's
  Model and the clone shell is destroyed; rooms, tunnels, passages and slide prefabs keep their own Model.
- Never copy `Level2BlenderKit` folders into the world; never leave templates in ServerStorage root.
- Slide pieces: clone the unit template, `Size.Z = segment.len`, CFrame from the record times the prefab CFrame,
  then set `Level2_SlideDirection = piece.CFrame.LookVector` (attributes do not rotate with PivotTo).
