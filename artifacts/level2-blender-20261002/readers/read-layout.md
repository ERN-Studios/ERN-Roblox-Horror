# Level 2 random generator: how it works, and what a Blender prefab kit would change

Path abbreviations used below (all under `G:\Roblox\MongoTV\ServerScriptService\`):
- **LG** = `Level 2 Systems\Level 2 Layout Generator.ModuleScript.lua`
- **CFG** = `Level 2 Systems\Level 2 Configuration.ModuleScript.lua`
- **RA** = `Level 2 Systems\Level 2 Round Adapter.ModuleScript.lua`
- **WB** = `Level 2 Systems\Level 2 World Builder.ModuleScript.lua` (6400 lines; I read the sections the generator feeds)
- **PFC** = Pool Foam Controller, **NAV** = Pool Foam Navigator, **PSC** = Pool Slide Controller, **OC** = Objective Controller (all in `Level 2 Systems\`)
- **BRR** = `Level 1 Systems\BlenderRoomRenderer.ModuleScript.lua`

## 0. Call chain
- GameManager calls `Level2Generator.Build()`, which is a 14-line wrapper that calls `Adapter.Build()` (`Level2Generator.ModuleScript.lua:4-14`).
- `RA.Build()` (RA:314-461) runs `Cleanup`, then `Master.ApplyInto(Configuration, "L2")` (RA:322), resolves the seed, calls `LayoutGenerator.Generate(seed, {AllowRandomRecovery = pinnedSeed == nil})` (RA:356-358) and `WorldBuilder.Build(layout, generation)` (RA:370).
- It then moves players to `manifest.Arrival.ElevatorSpawn`: 8 columns, 4-stud pitch, +4 Y (RA:381-402). After that come `storeLobby` (RA:403), `ObjectiveController.Start` (RA:410), `PoolFoamController.Start` (RA:413) and `PoolSlideController.Start` if enabled (RA:425-441).
- The Master overrides that can rewrite CFG at build time are `L2_ComplexExtent` (600-2400), `L2_MinimumLeafSize` (90-400), `L2_MaximumLeafSize`, `L2_MinimumHallCount`, `L2_CorridorWidth`, `L2_WallHeight`, `L2_SlideHallCount` (0-8), `L2_SlidesPerHall`, `L2_KidsAreaRoomCount` (0-12), the two pool depths and `L2_CeilingPanelBrightness` (`ReplicatedStorage/MasterConfiguration.ModuleScript.lua:113-146`).
- **Latent hazard:** `L2_MinimumLeafSize` below 145 lets leaves exist that LG:291-293 always rejects ("BSP leaf cannot contain the minimum hall size"), because 145 = 2×30 margin + 85 minimum hall.

## 1. Seed handling
- **`pinnedSeedOverride()`** (RA:35-45) reads `workspace.Level2Seed`.
  - Non-number, NaN, `< 1` or `>= 2147483647` returns nil, which means random.
  - Otherwise it returns `math.floor(value)`. Out-of-range values are rejected, not wrapped (RA:39-43).
- **`randomRoundSeed(generation)`** = `(UnixTimestampMillis + Random.new():NextInteger(0, MAX_SEED-1) + generation*7919) % (MAX_SEED-1) + 1` (RA:51-55). The result is never written back to the attribute (RA:325-327). `generation` increments on every Build (RA:316).
- **State folder** `ReplicatedStorage["Level 2 State"]`:
  - Before generating: `Level2_Phase` = `GENERATING_LAYOUT`, `Level2_Generation`, `Level2_Seed` = `Level2_RequestedSeed` = requested seed, `Level2_SeedPinned` (boolean), and `Level2_RandomRecoverySeed` / `Level2_ResolvedSeed` / `Level2_GenerationAttempt` / `Level2_FallbackBaseSeed` cleared, `Level2_UsedFallback` = false (RA:331-342).
  - After generating: `Level2_LayoutSeconds`, `Level2_RandomRecoverySeed`, `Level2_ResolvedSeed` = `layout.Seed`, `Level2_GenerationAttempt` = `layout.Attempt`, `Level2_UsedFallback`, `Level2_FallbackBaseSeed` (RA:360-365).
  - Later: `Level2_BuildSeconds`, `Level2_WorldDescendants`, `Level2_HallCount` (RA:372-408).
  - Workspace attribute `LoadStage` goes `LEVEL_2_GENERATING_LAYOUT` → `LEVEL_2_BUILDING_WORLD` → `READY`, or `WORLD_ERROR` on failure (RA:344, 368, 448, 455).
- **Inside `Generate`:** `normalizeSeed(v, true)` = `floor(v) % 2147483647`, falling back to the clock if the value is not finite (LG:901-908).
- **What is deterministic:** `generateAttempt(seed)` is deterministic in its seed, so pinning `Level2_ResolvedSeed` reproduces the layout. Lever handle colours are the exception: `shuffledLeverHandleColors(layout.Seed, generation)` mixes in the round counter (WB:4254-4268).

## 2. `generateAttempt(seed)` step by step (LG:247-669)
One `Random.new(seed)` stream drives everything. Draw order is load-bearing: LG:275-276 says to keep it identical so that layouts which already succeed stay the same.

1. **Bounds.** Centred on `WorldCenterX/Z` = 0 / 240 (CFG:24-25) with `ComplexExtent` 1400 (CFG:19), giving X −700..700 and Z −460..940 (LG:252-260).
2. **Recursive BSP `split()`** (LG:66-111):
   - An axis can split only if it is at least `2×MinimumLeafSize + HallMargin` = 2×150 + 30 = 330 (LG:68-70; CFG:27, 37).
   - A leaf is forced to keep splitting while either side exceeds `MaximumLeafSize` 310 (LG:72-73; CFG:30).
   - Otherwise it stops when it cannot split, or when depth ≥ `MaximumSplitDepth` 6 and it is not oversize (LG:74-75). From depth ≥ `MinimumSplitDepth` 2 it also stops early with probability `EarlyStopChance` 0.18 (LG:79-82; CFG:31-35).
   - Axis choice: cut the long axis if one side is more than 1.25× the other, else 50/50 (LG:88-96). The cut position is uniform in `[Min+150, Max−150]` (LG:98-110).
   - `#leaves < MinimumHallCount` (16) rejects the attempt (LG:268).
3. **Leaf → hall** (LG:270-315):
   - Each side is inset by `HallMargin` 30 plus jitter `U(0, HallInsetJitter=14)`, with four draws in fixed order (LG:277-280).
   - `fitInsetPair` scales the insets down only when they would push the hall below `MinimumHallSize` 85 (LG:54-62, 281-290). The hall is rejected if still below 85 (LG:305-308).
   - Hall record fields: `Index`, `Id` = `"Level 2 Hall %02d"`, `MinX/MaxX/MinZ/MaxZ`, `Connections = {}`, `Role = "Hall"`, `PoolType = "Shallow"`, then `Center` (Y = 0), `Width`, `Depth`, `Area`, and `LocalSeed = rng:NextInteger(1, 2^30)` (LG:294-314).
4. **Graph: there is no spanning tree and no loop pass.**
   - Every pair `i<j` is tested with `gapBetween`: the halls must face each other with axis overlap ≥ `CorridorWidth + 8` = 42 (LG:126-137). If the gap is ≤ `MaximumCorridorLength` 130, `connect(...,"Open")` runs (LG:319-327).
   - `connect` creates one corridor per pair (`CorridorByPair["min:max"]`). It is straight along `Axis` "X" or "Z", centred on the overlap: `Cross = (low+high)/2`, `From` = near wall, `To` = far wall, `Length` = gap, `Width = 34`, `Kind`, `PoolType = "Shallow"`. Both halls' `Connections` get the other's index (LG:139-179).
   - Overlap safety is not checked explicitly. Corridors cannot cross halls or each other only as a by-construction consequence: only BSP-adjacent leaves are ever within 130 studs, since a gap is 60-88 between neighbours and ≥ 210 across an intervening leaf.
5. **Connectivity.** A BFS from hall 1 must reach every hall, else the attempt is rejected with "hall graph disconnected" (LG:330-333).
6. **Arrival.** The hall whose centre is closest to `(Bounds.MinX, Bounds.MinZ)` (LG:335-343). BFS depths from it are stored as `GraphDepth` and `ConnectionCount`, plus `layout.Distances` (LG:345-350).
7. **Slide halls and the exit ("Grand") hall** (LG:352-400):
   - Halls are sorted by `Area` descending.
   - A slide candidate is not the arrival, has `GraphDepth ≥ 1`, and is at least `SlideHallMinimumWidth/Depth` 175×165 (CFG:70-71).
   - An exit candidate also clears `ExitHallMinimumWidth/Depth` 210×200 (CFG:78-79) and satisfies `Bounds.MaxX − hall.MaxX ≤ ExitHallMaximumShellGap` 80 (CFG:84).
   - The exit hall is the exit candidate with the largest `MaxX`, ties broken by lowest Index (LG:385-391). It is put first, then `chooseSpread` greedily picks `SlideHallCount` 3 halls at least `SlideHallSeparation` 320 apart, centre to centre (LG:206-219, 392-399).
   - Because 80 < 30 margin + 150 minimum leaf, the shell-gap rule really means "the exit hall's leaf touches the east boundary".
8. **Kids block** (LG:405-433):
   - Seeds are unprotected halls with `GraphDepth ≥ 2` and `max(W, D) ≤ 200`, sorted deepest first.
   - `growBlock` grows a connected run of `KidsAreaRoomCount` 5 halls by BFS (LG:223-243). Failure rejects the attempt.
9. **Pumps** (LG:435-473):
   - Pump 1 is the largest-area hall among kids block entries 2..5. Entry 1 is never chosen; it holds the splash pool.
   - Pumps 2 and 3 come from unprotected halls with `GraphDepth ≥ 1` that are at least `PumpSeparation` 300 from pump 1. They are sorted farthest first, then picked with `chooseSpread(…, 2, 300)`.
   - The result is `layout.PumpHalls = {kidsPump, out1, out2}`.
10. **Kids wall-to-wall merge** (LG:475-524). For each Open corridor joining two kids halls where it is the only corridor on that side of both halls, both halls are stretched to `mid ± 1.75` and the corridor becomes `Kind = "SharedWall"`. This mutates hall bounds after the graph exists; `Center`, `Width`, `Depth` and `Area` are recomputed.
11. **Dens** (LG:526-547).
    - `EntityDen` is the deepest unprotected hall, falling back to `pumps[3]`.
    - `EntityDenB` is the first other candidate at least 300 from it, falling back to `denCandidates[2]`.
12. **Pressure doors** (LG:549-565). Every corridor touching the grand hall becomes `Kind = "PressureDoor"`. A BFS with those corridors blocked must still reach every other hall.
13. **Drains** (LG:567-599).
    - Eligible corridors are Open, with `Length ≥ MinimumDrainableLength` 40, and touch no kids hall.
    - For each pump in order, the nearest unassigned eligible corridor (by its end-hall centres) gets `DrainGroup = pumpIndex` and `PoolType = "Deep"`.
14. **Archetype rolls** for unprotected halls, one roll each (LG:603-617):

    | Roll | PoolType | Archetype (uniform pick) |
    |---|---|---|
    | < 0.28 | Deep | Diving Well, Pillar Basin, Column Forest |
    | 0.28 to < 0.62 | Shallow | Flooded Gallery, Curved Gallery, Skylight Hall, Column Forest |
    | ≥ 0.62 | Shallow | Arch Tunnel, Ring Corridor, Spiral Stair Well, Porthole Hall |

15. **Named roles, applied last so they win** (LG:619-664), in this order:
    - Arrival: Dry, "Arrival Concourse".
    - Den A: "Entity Den", Deep, "Sunken Basin".
    - Den B: "Entity Den B", Shallow, "Column Forest".
    - Slides: Role "Slide Hall", PoolType "Slide", `IsGrand`, Archetype "Grand Slide Hall" / "Slide Hall", `SlideHallIndex`.
    - Pumps: Role "Pump Station", `PumpIndex`, Dry, "Pump Station".
    - Kids (these overwrite pump 1's role): Role "Kids Area", PoolType `KidsShallow` for index 1 and `KidsDry` otherwise, Archetype "Kids Play Room", `KidsIndex`, `KidsColorIndex`. Colours are 3 (Sun, Coral, Lagoon; CFG:200-204), assigned greedily so connected kids halls differ.
    - Finally `HallCount` and `CorridorCount`.

## 3. Validation, retries, recovery
- **`validateLayout`** (LG:678-895).
  - Roles: arrival, slides, pumps and kids may not share a hall (the "overlap" check is about roles, LG:703-711). Exactly 3 slide halls, the grand hall among them, and the grand hall at least 210×200 and within the shell gap (LG:728-741). 3 pumps with matching `PumpIndex`. 5 kids halls with exactly one pump, and that pump must be `PumpHalls[1]`, not `KidsIndex` 1, and `KidsDry` (LG:743-784). Pairwise pump separation ≥ 300 (LG:785-796).
  - Halls: contiguous indices, finite bounds, at least 85 a side.
  - Corridors: contiguous, unique pairs, `CorridorByPair` consistent, pressure doors only on the grand hall, `DrainGroup` unique and in 1..3, connections reciprocal.
  - Graph: fully connected, and still connected minus the grand hall when pressure doors are blocked. Cached counts current (LG:798-893).
- **`Generate`** (LG:921-983) runs `trySequence(base, n)`, where the attempt seed is `(base + attempt×104729) % 2147483647` (LG:928-948).
  1. Primary: `GenerationAttempts` 300 (CFG:49; default 40 if unset, LG:950).
  2. If unpinned (`AllowRandomRecovery`): one more 300-attempt stride from a fresh clock+entropy seed, which sets `RandomRecoverySeed` (LG:954-964).
  3. Then `GenerationFallbackSeeds = {101}` × `GenerationFallbackAttemptsPerSeed` 40 (CFG:54-55; LG:966-976), sets `FallbackUsed` / `FallbackBaseSeed`.
  4. Then `error(...)` (LG:978-982). Worst case is 640 attempts unpinned and 340 pinned.
- **README wording is wrong:** README.md:327-329 says "A pinned seed skips the fallback". The code shows a pinned seed skips only the random stride and still runs fallback seed 101 (LG:916-920, 966; RA:353-354).
- Success fields: `RequestedSeed`, `Attempt` (cumulative), `AttemptWithinSequence`, `FallbackUsed`, `FallbackBaseSeed`, `RandomRecoverySeed` (LG:936-941, 961).
- Budget rationale: 11.1% acceptance, about 9 attempts, p99 42, 0.23 ms per attempt (CFG:41-48). This must be re-measured if any size tunable changes.

## 4. Measured distributions (offline probe, 400 seeds)
I ran the real LG and CFG under Luau 0.737 with stub `Vector3` and a Park-Miller RNG in place of Roblox's `Random`. The harness is `%TEMP%\l2gen_probe\run.luau`, outside the repo. Individual layouts differ from live seeds, but the distributions reproduce README's own 400-seed figures: exit-hall median 233×226 and shell gap ≤ 44.

| Metric | Min | Median | p90 | Max |
|---|---|---|---|---|
| Halls | 32 | 39 | 42 | 48 |
| Corridors (all kinds) | 52 | 66 | 72 | 80 |
| SharedWall corridors | 3 | 5 | 5 | 5 |
| Independent loops (E−V+1) | 20 | 28 | 31 | 34 |
| Attempts per accepted plan | 1 | 6 (mean 8.7) | 19 | 69 |
| Hall width (studs) | 85 | 149 | 233 | 277 |
| Hall depth (studs) | 85 | 144 | 229 | 269 |
| Connections per hall | 2 | 3 (mean 3.37) | 4 | 7 |
| Tube length (studs) | 60.1 | 73.5 | 81.1 | 88.0 |
| Exit hall (W×D) | 210×200 | 233×226 | — | 268×266 |
| Exit hall shell gap | 30 | 35 | — | 44 |

- Corridor length is always 60-88 because it equals 2×30 margin plus 0-28 of insets. `MaximumCorridorLength` 130 and `MinimumDrainableLength` 40 therefore never bind.
- Doors per wall: 0 on 18%, 1 on 79%, 2 on 2.5%, never 3.
- Door offset from the wall midpoint: median 3.3 studs, p90 46.5, max 110.5 (up to 0.8 of the half-wall). Door positions are continuous, not socketed.
- Named-role halls total 13 (1 arrival, 3 slide, 2 outside pump, 5 kids, 2 den); the other ~26 are generic.

## 5. What the World Builder (and others) read from the layout
- **Layout:** `Bounds{MinX,MaxX,MinZ,MaxZ}`, `Seed`, `Version`, `Attempt`, `Halls[]`, `Corridors[]`, `CorridorByPair`, `Arrival`, `Distances`, `SlideHalls`, `GrandSlideHall`, `KidsArea`, `PumpHalls`, `EntityDen`, `EntityDenB`, `HallCount`, `CorridorCount`, plus the §3 success fields.
- **Hall:** `Index`, `Id`, `MinX`, `MaxX`, `MinZ`, `MaxZ`, `Center`, `Width`, `Depth`, `Area`, `LocalSeed`, `Connections`, `Role`, `PoolType`, `Archetype`, `GraphDepth`, `ConnectionCount`, `IsGrand`, `SlideHallIndex`, `PumpIndex`, `KidsIndex`, `KidsColorIndex`.
  - WB writes back `SpiralCenter`, `SpiralRadius`, `SpiralStructureRadius` and `SpiralRerouted` (WB:5976-5982).
  - `LocalSeed` seeds every per-hall `Random` in WB (WB:428, 624, 2046, 4096, 5018, 5244, 5356, 5449).
- **Corridor:** `Index`, `Id`, `A`, `B`, `Axis`, `Length`, `Width`, `Kind` (Open / SharedWall / PressureDoor), `PoolType`, `Cross`, `From`, `To`, `DrainGroup`.
- **WB derives doors only from corridors:** `doorsByHall[i].{East,West,North,South}` = lists of `Cross` values (WB:5940-5957).
  - **Naming trap:** "North" is the MinZ (−Z) wall and "South" is MaxZ (+Z) (WB:5952-5955, 6216-6217). The Level 1 Blender kit uses the opposite convention, N = +Z (BRR:125).
- **Other consumers:**
  - PFC: `layout.KidsArea`, `Halls`, `Seed` (PFC:201-216, 2008, 2054).
  - NAV and the Pool Slide navigator: `Halls` (bounds, `Center`, `Index`, `Connections`), `Corridors` (`Cross`, `From`, `To`, `Width`, `Axis`, `Kind`, `A`, `B`), `CorridorByPair` (NAV:165-312, 912-950).
  - OC: only the manifest (`Pumps`, `Drains[pumpIndex]`, `PressureDoors`, `Exit.*`; OC:267-335, 610).
  - RA: `WaterRegions`, which are terrain regions that `Cleanup` clears (RA:196-214). OC drains via `Terrain:FillBlock(record.Water…, Air)` (OC:348).

## 6. Where gameplay anchors are chosen
| Anchor | Generator decides | World Builder or controller decides |
|---|---|---|
| Player spawn | Arrival hall: nearest the (MinX, MinZ) corner (LG:335-343) | `roomDirection` points toward the first connected neighbour (WB:6257-6272). Spawn is 5.5 studs in front of the rear wall, Y = 0 (WB:5748-5754). Markers: `Level 2 Arrival Spawn`, plus `ElevatorSpawn`, `MazeStart`, `EntityStart` with `Level2_CompatibilityMarker` (WB:5824-5885) |
| Pumps | `PumpHalls` (LG:435-473) | `makePumpStation` at `hall.Center + hallFloorY` (WB:4312-4313). Kids pump room reserves a 60×52 zone (WB:4069-4076) |
| Exit | `GrandSlideHall` (LG:385-400) | Deck at `deckY = height−22` on the north edge (WB:3030-3043). Flume starts at `(hall.MaxX−14, deckY+9.3, deckZ)`, shell at `Bounds.MaxX+60`, plunge to Y = 4, 250-stud transfer at grade 0.21, 3-turn helix of radius 96, bottom near Y = −428 (WB:3228-3335). Wall gap through `HallWallGap` (WB:3642-3647, 6213-6215). `Level2_ExitPosition` = mouth (OC:478-481) |
| Pressure doors | `Kind = "PressureDoor"` on every grand-hall corridor (LG:549-558) | Door part `Level 2 Pressure Door N` at the corridor's `To` end, i.e. the higher-coordinate wall, which may be the neighbour's (WB:4956-4967) |
| Drains | `DrainGroup` (LG:585-599) | `manifest.Drains[group]` = corridor record (WB:6228) |
| Pool Foam spawns | `KidsArea` (5 halls) | One 8×8 pocket per kids room (WB:4081-4084). Marker `Level 2 Pool Foam Spawn <i>` with `Level2_PoolFoamSpawn` (WB:6016-6028). PFC prefers those nodes, `SpawnGap` 9 (PFC:234-300) |
| Pool Slide spawn | `EntityDen` / `EntityDenB` | Anchors are `Level 2 Entity Den A/B Spawn`, all `Patrol Node`s and all `Navigation Node`s (WB:6175-6198, 6277-6292; PSC:209-225). It spawns at pump 2 (`SPAWN_PUMPS=2`), at least 100 from every participant (PSC:24-26) |

The Pool Slide config has `Enabled = true` and RA starts it (RA:425-441). CLAUDE.md's "Level 2 has exactly one hostile" is out of date relative to this mirror.

## 7. Heights / Y
- The layout has no Y at all. Every hall `Center` has Y = 0 (LG:28-30).
- `hallFloorY` is 0, or −0.8 for kids rooms (WB:219-224). Terrain water surfaces sit at Y = 0.1 (WB:390-394).
- Water depths:
  - Pump room: 1.2.
  - Shallow halls: 1.6. Deep halls: 2.0. Slide halls: 1.8 (CFG:108-114; WB:205-215).
  - Corridor channel: 1.5, or 1.8 when drainable (CFG:115-118).
- Ceiling heights: `WallHeight` 34, slide halls 76, grand hall 96, kids rooms 33, corridors 32 (CFG:90-95).
- The stair branches for depth > 2.5 never build at current depths (WB:4733, 6140).
- NAV's `graphRoute` puts every waypoint at `fromPosition.Y` (NAV:296-312).
- Terrain water is flat per `FillBlock` region (WB:349-354).

## 8. Stale or dead items in the generator
- LG:11 says "L-shaped CORRIDORS"; corridors are straight on a single axis.
- LG:13-14 says "BSP merge order guarantees connectivity … second pass adds loops", and LG:318 refers to "the loop pass below". There is no such pass: connectivity is the all-facing-pairs graph plus BFS rejection.
- LG:17-18 says the "largest" slide hall holds the exit; it is actually the easternmost eligible hall.
- `MaximumCorridorLength` and `MinimumDrainableLength` never bind (see §4).

## 9. Judgement: what changes for prefab rooms with fixed footprints and sockets
**Keep the layout table (§5) as the contract.** If a prefab generator emits the same `Halls` / `Corridors` / `CorridorByPair` shape, with straight `Axis` / `Cross` tunnels, then the navigators, PFC, PSC, OC (via the manifest) and RA keep working unchanged. Only the World Builder is replaced by a prefab cloner.

**Survives verbatim:**
- Seed path: RA:35-55 and 328-366, LG:901-983, retry stride, recovery and fallback seeds.
- Graph and role logic: `bfs`, `chooseSpread`, `growBlock`, arrival choice, slide/pump/den selection, pressure-door lock and reachability, drain choice, kids colours (LG:181-243, 330-599, 643-664).
- The role and graph half of `validateLayout`.
- **Caveat:** `GenerationAttempts` 300 must be re-measured, because acceptance changes.

**Survives with new inputs:**
- Archetype rolls (LG:603-617) become weighted prefab families. The 0.28 / 0.34 / 0.38 weights carry over, in the style of the Level 1 kit's `SelectionWeight` (BRR:39-55).
- Size gates become prefab tags:
  - 175×165 slide minimum → `CanSlide` (LG:38-47, 368-381).
  - 210×200 exit minimum plus shell gap → an exit prefab that is placed only in the east column.
  - `kidsSized ≤ 200` → kids prefabs (LG:412-414).
  - `MinimumHallSize` → kit minimum.
- `validateLayout` size checks (LG:728-741, 804-807) become tag checks. A new check is needed: every corridor end lands on a declared socket.

**Replaced:**
1. **`split()` and the inset/jitter step** (LG:66-111, 270-315). Fixed footprints come from a kit of S/M/L rooms (say 3-6 footprints covering 85-270), placed into leaves on a module grid.
2. **`gapBetween` / `connect`** (LG:126-179). Today a door sits at the overlap centre at any offset (§4: up to 110 studs off-centre, up to 2 per wall). Prefabs need fixed sockets. The lowest-risk rule:
   - Sockets at a fixed pitch P along each wall, and room corners snapped to the P grid.
   - A link exists only where two facing walls share a socket coordinate, which needs an overlap of at least P + 30 (the door width).
   - This keeps tunnels straight, so NAV's `graphRoute`, `corridorCentreSeed` and WB's `doorsByHall` stay valid.
   - Dog-leg tunnels would break the single-`Axis` corridor record and both navigators. Avoid them.
3. **Kids wall-to-wall merge** (LG:475-524), which mutates hall bounds. Replace it with kids prefabs abutted socket to socket with a 3.5-stud gap, kept as `Kind = "SharedWall"`. WB already builds only a threshold for that kind (WB:4654-4682), and NAV skips the midpoint for it (NAV:298-307).
4. **Unused sockets** need a blank-wall cap per socket. Prefer per-socket cap pieces over Level 1's one-variant-per-mask scheme (`OpenMask` 1..15 all required; BRR:26-35, 183-188), because two or more sockets per side would explode the variant count.
5. **Tunnels.** If insets are dropped or quantized, tunnel length becomes a small discrete set. Then a tunnel is one prefab per kind: Open, Drainable (1.8 water, carries `DrainGroup`), PressureDoor (door at the `To` end) and a kids-skinned variant.
   - Today one tube corridor is roughly 190 Parts and 280 Textures. That is my arithmetic from the code, not a measurement: 2 mouths × (1 header + up to 32 spandrel slats + 30-step face ring), each piece with 2 textures (WB:4851-4928); 21 vault strips (WB:1880); 3-4 mesh ribs plus 8 invisible feet each (WB:1815, 4820).
   - At about 61 tube corridors per layout, that is about 28k instances, roughly half of the measured 56k (CFG:173-178). The tunnels are the biggest win.
6. **Authored anchors replace WB solvers.** Use Attachments in the prefab for SpawnAnchor, PumpAnchor, PoolFoamSpawn (replacing the kids reservation solver, WB:3952-4084), exit deck and flume socket (DeckY/DeckZ, WB:3031-3034), and the spiral stair (WB:2028).
   - `makeExitFlume` can stay procedural, fed from the socket. OC asserts its `Exit.*` fields (OC:290-335), and the Exit Transition Test Suite checks them.
7. **Water.** Keep invisible "WaterVolume" parts in the prefabs that the builder turns into `addWater` regions. RA:196-214 clears from `manifest.WaterRegions`, and OC:348 drains a corridor by filling its terrain region with air.

**New work for height variation:**
- Add a per-hall `FloorY`, and `FromY`/`ToY` on corridors.
- Water surfaces must stay flat. Put level changes in dry stair or ramp tunnels or in-room terraces, never in flooded tubes.
- Both navigators need per-hall Y in `graphRoute` (NAV:296-312), and `hallFloorY` (WB:219-224) must read the field. Pool Foam's 3.5-stud step limit (README.md:287-295) suits stairs.
- An exit hall raised by Y keeps the helix bottom (about −428) clear of the −500 kill height; lowering it by more than ~70 studs would not (WB:3266-3267).

**Preview-button precedent:** `Level1BlenderPreviewAccess.Script.lua` (DevAccess-gated host part in `Level1QueueRoom` / `QueueBay_Level1`, `Level1BlenderPreviewActive`, GameManager:3304-3337). Level 1's renderer is a skin over the live grid (BRR:1, 179-183). Level 2 cannot be skinned, so its preview has to run the new generator and builder behind its own flag while emitting the same layout contract.