# Level 2 v2: rebuilding the pool level as a Blender modular kit

**What this is.** One analysis of the live Level 2 code, written for the owner and for the sessions that will build v2.
- **Basis.** The working tree at HEAD `e8e4e7c` on 2026-10-03, including the uncommitted GameManager and RoundUI edits. It merges nine reader reports (`readers/read-*.md` in this folder) and a verification sweep.
- **Spot checks.** I re-checked these lines myself: `Level 2 Pool Slide Configuration:4`, RA:196-225, 340-450, CFG:86-121, 145-182, PFC:234-252, PFN:125-145, 530-600, PSC:20-50, 262-282, GM:120-3954 (the grep hits), TLB:2111-2118, 2936-2941, `Level6BlenderRuntimeBake` and `LobbyReimaginedPreview/RuntimeBake`.
- **Read-only.** Studio was not touched. No other repo file was changed.

**Owner decisions already given on 2026-10-02.** These come from session memory `level2-blender-rework-2026-10-02`, and this document builds on them rather than re-asking them:
- **Studio access.** Work offline until `artifacts/level1-quality-20261002/coordination.md` shows an EDIT handback, then reserve Studio there.
- **Preview first.** A developer-only preview comes first. It launches a **real round** (Pool Foam, pumps, exit) with no progression.
- **Budgets.** Meshy spend is capped at about 1,000 of 1,695 credits. Mobile must run well: low polycount, mostly 1K textures, few lights.
- **Approval stops.** First, three Codex imagegen style directions; second, Blender renders before any import.
- **Height variation.** Yes to sloped pool floors (shallow to deep), steps and ramps between rooms, and varied ceilings. **No small hills.**
- **Tunnels.** Tunnels stay, but each segment becomes one mesh.
- **Git and publishing.** Local commits only. Never publish.

**Abbreviations**

Under `ServerScriptService/Level 2 Systems/`:

| Short | Module |
|---|---|
| WB | World Builder |
| LG | Layout Generator |
| CFG | Configuration |
| RA | Round Adapter |
| OC | Objective Controller |
| PFC / PFN / PFO / PFCFG | Pool Foam Controller / Navigator / Observer / Configuration |
| PSC / PSN / PSCFG | Pool Slide Controller / Navigator / Configuration |
| SRS | Slide Ragdoll Service |
| TS | Exit Transition Test Suite |

Under `ServerScriptService/`:

| Short | Script |
|---|---|
| GM | GameManager |
| RP | ReentryPlacement |
| RMS | RouteMarkerService |
| TLB | TunnelLobbyBuilder |
| L1PA | Level1BlenderPreviewAccess |
| BRR | Level 1 Systems/BlenderRoomRenderer |
| L3WB | Level 3 World Builder |

Under `StarterPlayer/StarterPlayerScripts/`:

| Short | Script |
|---|---|
| REC | Round Entry Client |
| RUI | RoundUI |
| SC | SoundController |
| L2SC | Level 2 Sound Controller |
| L2SL | Level 2 Slide Controller |
| L2LC | Level 2 Lighting Controller |
| L2AC | Level2AlertClient |
| L2OUI | Level 2 Objective UI |
| L2PF | Level 2 Pool Foam Client |
| L2EA | Level 2 Entity Audio |

Other: MC = `ReplicatedStorage/MasterConfiguration`.

---

## 1. Level 2 today in one page

### Call chain
1. GM `LEVEL_GENERATORS[2] = "Level2Generator"` (GM:139-143).
2. `Level2Generator.ModuleScript.lua:4-14` is a 14-line shim.
3. `RA.Build` (RA:314-461) runs in this order:
   - `Cleanup()` and `Master.ApplyInto(CFG,"L2")` (RA:322).
   - Terrain wipe `clearOwnedTerrain(nil)` (RA:348).
   - `LG.Generate` (RA:356).
   - `WB.Build` (RA:370).
   - Readback `Level2_WorldDescendants` (RA:374-375).
   - Moves **every** server player onto the arrival grid (RA:381-402), then parks `workspace.ServerLobby` (RA:403, 61-68).
   - Starts `OC.Start` (RA:410), then `PoolFoamController.Start`, which is fatal on failure (RA:413-420), then `PoolSlideController.Start`, whose failure only warns and sets UNAVAILABLE (RA:425-445).
   - Sets `SelectedLevel=2`, `LoadStage=READY` and `WorldGenerated=true` (RA:447-449).

### Round loop
1. **Load.** `loadinggame` → token barrier `entryprepare` → client `entryready` → `entryreleased`, with a 60 s limit (RLR:5, GM:2166-2256, REC:66-138).
   - REC's ground check: a ray from root+2 down 14 studs must hit a CanCollide part inside `"Level 2 Generated World"` or `ElevatorSpawn`, with `Normal.Y > .15` (REC:31-64).
2. **Start.** `poolaccess` then `start`, and `RoundActive=true` (GM:2964-3026).
3. **Pool Foam.** It is Dormant for 15 s. Before the first pump it only targets players inside the Kids Area (PFC:666-670, 843-848).
4. **Pumps (3).** Hold the prompt for 1.6 s; the server rechecks with `canUsePump` (OC:225-243).
   - Each pump drains its corridor's terrain water 10 s later (OC:615-621, 345-349).
   - Phases by pump count: 1 = Foreshadow, 2 = Pressure (kills on, `Level2FoamLethal`), 3 = Finale (PFCFG:286-312).
   - The Pool Slide spawns at 2 pumps and enrages at 3 (PSC:24-25).
5. **Doors.** After the final pump, `openPressureDoors` runs (OC:404-495). Doors on every Grand-Slide-Hall corridor lose collision and rise 42 studs, and the exit sensors arm.
6. **Exit.** Players climb to the grand hall deck (`deckY = H-22`) and ride the closed exit flume (bore radius 8).
   - The flume plunges, runs a 250-stud transfer at grade .21, then a 3-turn helix of radius 96 down to about Y -428 (WB:3228-3335).
   - The completion beam sets `Escaped` and `Level2_ExitTransition` (OC:667-687).
   - The client "recycles" the rider up one helix turn until teleport (L2SL:582-614). The server backstops with OC:823-916.
7. **Win.** The round is won when every living participant has escaped (GM:3052-3056). It then continues to Level 3 with the tube continuation (GM:3103-3142, 948-1059).

### Generator (LG)
- **BSP split.**
  - ComplexExtent is 1400, centred on (0, 240) (CFG:19-25).
  - Leaves are 150–310 (CFG:27-30).
  - Halls are inset by 30 plus 0–14 of jitter per side (LG:270-315).
- **Corridors.** One corridor is made for **every facing pair** with an overlap of at least 42 and a gap of at most 130 (LG:126-179, 319-327).
  - There is no spanning tree and no loop pass; LG:13-14 and 318 say otherwise and are stale.
  - Connectivity is enforced only by BFS rejection (LG:330-333).
- **Roles.**
  - Arrival: the hall nearest the (MinX, MinZ) corner.
  - Three slide halls, at least 175×165 and at least 320 apart.
  - The exit ("Grand") hall: at least 210×200 and within 80 of the east boundary.
  - A connected kids block of 5 halls.
  - Three pumps: pump 1 is in the kids block; pumps 2 and 3 are at least 300 away.
  - Two dens.
  - Every grand-hall corridor is a PressureDoor.
  - Each pump gets one Deep drain corridor.
  - Sources: LG:352-599, 619-664.
- **Retries.** Up to 300 attempts, then a 300-attempt random recovery stride, then fallback seed 101 × 40 (LG:921-983).
- **Offline 400-seed probe** (layout reader):

  | Metric | Median | Range |
  |---|---:|---:|
  | Halls | 39 | 32–48 |
  | Corridors (including SharedWall) | 66 | 52–80 |
  | Hall width | 149 | 85–277 |
  | Tunnel length (the gap) | 73.5 | 60.1–88.0 |

  - A wall has 1 door 79% of the time and 2 doors 2.5% of the time. The door offset from the wall midpoint goes up to 110 studs.
  - **`MaximumCorridorLength` 130 and `MinimumDrainableLength` 40 never bind.**

### World builder (WB, 6,400 lines)
- **Geometry approach.** Everything is SmoothPlastic Parts plus `Texture` children; one tile texture is shared (asset 113211706146395, WB:29-30, 64-96). On top of that, column-flare/slide/rib MeshParts are cloned from ServerStorage templates (WB:1153-1263, 2222-2325, 1722-1776).
- **Water.** All water is Terrain `FillBlock` with a flat surface at Y .1 (WB:349-354). Depths: kids 0.8, pump 1.2, shallow 1.6, slide 1.8, deep 2.0; tunnels 1.5, or 1.8 when drainable (CFG:108-121, WB:205-215).
- **Heights.** The map is flat: every hall centre is at Y = 0 (LG:28-30). Hall heights are 34 / 33 kids / 76 slide / 96 grand; tunnels are 32 (CFG:90-95).
- **Entity ground.** A final pass tags every part named "Ceiling", "Skylight" or "Roof" with `Level2_NoEntityGround` and a `PathfindingModifier "Level2Roof"` (WB:6317-6332).

### Hostiles: there are **two** in code
- **Pool Foam.** 5 clones, one per kids room. It is a layout-graph and PathfindingService hybrid, with a server body box of 4.2×5.7×4.2 and a look-latch.
- **Pool Slide.** `PSCFG:4 Enabled = true`; started at RA:425-445; it has a 14.8-stud navigation body (PSC:38-41).
- **CLAUDE.md is wrong** where it says "Level 2 has exactly one hostile" (CLAUDE.md:126); the code above settles it.

---

## 2. Instance budget

### 2.1 Which number is true
| Figure | Source | Status |
|---|---|---|
| ~52,000 | the brief | Not in source. Plausibly a lower-instance seed, or a client count under streaming (53,989 client vs 71,596 server on seed 738163940, `docs/REVIEW_FOR_CLAUDE_2026-09-21.md:83`) |
| **56,001** | CFG:173-178; `artifacts/codex-polish-20260923/README.md:83-87` | **Latest Studio measurement**, seed 1182081016, arch mesh ribs on. Texture 29,103 · Part 22,176 · MeshPart 2,521 · PathfindingModifier ~1,052 · PointLight 138 |
| ~71,000 | WB:6311, SRS:547, PFC:776 | Stale comments from before the mesh ribs (−15,770, CFG:173-178) and face culling (−2,872) |

**Resolution:** use `ReplicatedStorage."Level 2 State".Level2_WorldDescendants` (RA:374-375) on pinned seeds. Per-seed spread is ±several thousand. Each tunnel costs about 472. Each Ring Corridor ring costs 125. A helix is about 420. A ball pit is 211–594 balls. A spiral well is 264.

### 2.2 Ranked contributors
The live config is `CullHiddenTileFaces=true` (CFG:164) and `ArchMeshRibs=true` (CFG:179). The table is from the census reader, reconciled to 56,001 within 0.1%. Labels: d = derived from measured counts, e = estimate, m = measured.

| # | Contributor | Instances | % | Code |
|---|---|---:|---:|---|
| 1 | **Tunnel mouths** ("portal surrounds"): 64 tunnels × 2 mouths × (1 header + 32 spandrel slats + 30-piece face ring), each Part + 2 Textures. **None of it collides, is touchable or is queryable** | **24,192 (d)** | **43.2** | WB:4850-4928 (non-collide at 4882-4884, 4926) |
| 2 | Tunnel vault body: 21 strips × (Part+Tex), mesh ribs (1 MeshPart + 8 invisible feet), kids Part-ribs 26×3 per ring | 6,477 (d) | 11.6 | WB:1778-1911, 4820-4843 |
| 3 | Hall shells: ceilings ~2,840 (light seals, shadow coves, slabs, panes, modifiers) + walls ~2,460 + floors + panels | ~5,480 (e) | 9.8 | WB:228-396, 858-1073, 2119-2171 |
| 4 | Tube collision strips (5 per open segment, 6 per closed segment; tub bands) | ~4,870 (e) | 8.7 | WB:2513-2582, 2858-2891 |
| 5 | Hall play structures (stairs at Part + 3 Tex per step, spiral wells 264, diving towers 97–118, kits ~190, play towers ~225, overlooks 71, edge walkways 48) | ~4,700 (e) | 8.4 | WB:1932-2018, 5130-5440 |
| 6 | Ring Corridor rings: 20 × 25 × (Part + 4 Tex) | 2,500 (d) | 4.5 | WB:6053-6083 |
| 7 | Tube visuals (MeshPart per segment: 106 per flume, 120 per helix, 271 exit) | ~2,200 (e) | 3.9 | WB:2327-2331 |
| 8 | Tunnel shell remainder (floor, ledge, curb, 2 walls, ceiling, 2 lamps) | 1,617 (d) | 2.9 | WB:4725-4946 |
| 9 | Columns, ~100 × 14 (shaft + 4 Tex, 2 flare MeshParts + 2 SurfaceAppearances, 5 collision rings) | ~1,435 (e) | 2.6 | WB:1340-1460 |
| 10 | PathfindingModifiers, one per "Ceiling/Skylight/Roof" part (inside #1–3) | 1,052 (m) | 1.9 | WB:6317-6332 |
| 11 | Kids set pieces (ball pit ≈594 balls, slide tower, splash) | ~690 (e) | 1.2 | WB:3661-3941 |
| 12 | Pool Foam rigs (5) | ~650 (e) | 1.2 | out of scope |
| 13 | Buoyant props (floats, balls, noodles, loungers) | ~470 (e) | 0.8 | WB:4974-5093, 5654-5676 |
| 14 | Pumps, 3 × 77 (51 Parts) | 231 (d) | 0.4 | WB:4312-4647 |
| 15 | Navigation, patrol and spawn nodes | ~210 (d) | 0.4 | WB:6175-6198 |
| 16 | Models, folders, arrival gate, exit chamber | ~230 (e) | 0.4 | WB:5705-5886, 3527-3551 |

**Readers disagree on the pump**, and the census settles it:
- The rooms reader says "about 60 Parts".
- The tunnels and census readers say 77 instances, of which 51 are Parts.
- The census class check (27 WeldConstraints = 3 × 9, WB:4304, 4502) settles it at **77**.

### 2.3 The tunnels specifically
- **Per tunnel (standard, mesh ribs):** floor 2 + ledge 6 + curb 6 + walls 4 + ceiling 3 + vault 42 + mouths 378 + lamps 4 + ribs 9R = **445 + 9R**.
  - R = clamp(⌊(G+4)/22⌋, 3, 7) (WB:4820).
  - Because real gaps are 60–88, **R is only ever 3 or 4**, so a tunnel is **472 or 481** instances. The tunnels reader's 472–499 assumed G up to 130, which never happens.
  - A kids-skinned tunnel is about 700 (Part ribs, WB:1794 `not styleHall`).
  - A SharedWall connector is 4 (WB:4654-4682).
- **Readers agree on the per-tunnel figure:**
  - census: 472;
  - tunnels reader: 445 + 9R;
  - layout reader: about 190 Parts + 280 Textures, which is about 470.
- **Tunnels per layout:** the census back-derives 64 on seed 1182081016 (3,840 face parts / 60). The layout probe median is 66 corridors minus about 5 SharedWall, so about 61. Both are right for their own seeds.
- **Tunnels are about 58% of the world**, and **78% of each tunnel is its two mouths**.

### 2.4 Invisible or redundant geometry
| Geometry | Why players never see it | Load-bearing? |
|---|---|---|
| `Level 2 Corridor Wall` ×2 and `Level 2 Corridor Ceiling` per tunnel (WB:4794-4817) | They sit fully behind the vault: outer surface ±14.9, crown at about 28.6, against wall inner faces at ±15.25 and a ceiling bottom at 32 | Collision backstop and sealed void. The "Ceiling" name drives the Level2Roof cost (PFN:1936) |
| Tunnel-side faces of mouth slats, header and face ring (126 Textures per tunnel) | Buried in the vault strip thickness | Slats occlude the void from the hall side. Not collision |
| `… Sill` at every wet doorway (Part + 6 Tex, WB:318-321) | It sits at y −depth−4..−4, under the floor slabs | **No** |
| Lintels (6 textured faces, WB:312-314) | 5 of 6 faces are buried | Yes: the shell above the door, which the pressure door slides through |
| `Level 2 Exterior Light Seal 1-4` + `Perimeter Shadow Cove 1-4` per hall (WB:858-923) | Above the ceiling, outside the walls | A shadow-bias hack for Part seams; not needed with a watertight module |
| Parked pressure doors (y 38..74, Transparency 1 after opening, OC:440-457) | Invisible | Dead weight |
| The exit flume shell is `DoubleSided` (WB:2613-2615) | It is seen only from inside the bore | Its collision is gameplay; its visual can be single-sided |
| Stair risers, overlapping pump walkway slabs (z-fighting, WB:5272-5276) | Buried, or coplanar | The EntityGround is load-bearing; the duplicates are not |

**Dead code in WB:**
- Corridor steps (WB:4733-4743) and deep-doorway stairs (WB:6139-6168) need depth > 2.5, but the maximum depth is 2.0 (CFG:111).
- The pool island and its twin columns sit on the hall hub with a 3.5-stud gap. The Pool Foam body is 4.2, and the island never calls `nearHallNavigationRoute` (WB:5688-5698).
- The play-tower deck and overlook float with no legs (WB:5417-5421, 5639-5643).

---

## 3. The world contract a Blender build must keep

Side: S = server, C = client. "Fatal" means the build errors → `WORLD_ERROR` → failed entry.

### 3.1 Identity, folders and markers
| Item | Reader (script:line) | Side | What breaks if missing or wrong |
|---|---|---|---|
| Model named exactly `"Level 2 Generated World"` | REC:50; RUI:379, 425-428, 464; L2SC:326, 330, 801; L2SL:571; SRS:202, 224; L2PF:364, 398-404; L2EA:422; L2AC:420, 454-455; RA:250, 272-276; GM:656-662 | S+C | Cleanup misses it; REC ground check fails (`LOADING_TIMEOUT`); slide floors are rejected server-side; Level 2 lighting doesn't engage |
| World attribute `Level2_Generation` equal to the session | OC:198; PSC:90, 813; L2SC:588, 672; PFC:166-167 | S+C | Pumps and exit go dead; Pool Slide refuses; no groans |
| Folder `Level 2 Objectives` with pump Models **directly** under it, named `^Level 2 Pump Station` | L2AC:421-424 | C | Dev valve vision |
| Folder named exactly `Level 2 Navigation` (hall-centre nodes) | PFN:357; PFO:196; PSN:362; PFC:780-781 | S | Nodes block AI rays |
| Folder `Level 2 Entity Nodes`: **BaseParts as direct children** with `Level2_HallId` and `Level2_PoolFoamSpawn`, sorted by Name; ≥1 per kids hall | PFC:234-252 (`GetChildren`, `IsA("BasePart")`) | S | Spawn falls back to hall centre +2; fatal if that fails the floor check (PFC:538-542, 2104-2109) |
| Part-name prefixes `Level 2 Entity Den `, `Level 2 Entity Patrol Node `, `Level 2 Navigation Node ` (any depth) | PSC:209-225, 823-824 | S | Pool Slide "no entity navigation anchors" → **silently** UNAVAILABLE (RA:428-440) |
| `workspace.Elevator` Model with `DoorL`, `DoorR` | GM:1598-1619 (180 s, then **no timeout** on doors) | S | Entry times out |
| `workspace.MazeStart` | GM:1661 | S | `WORLD_LOAD_FAILED` |
| `workspace.ElevatorSpawn` (CFrame looks into the room; Y = floor + .1) | GM:825-839, 2839-2840; RA:382-402; REC:54 | S+C | `ENTRY_PLACEMENT_FAILED`, nil index at RA:383 |
| `Level2_CompatibilityMarker` on those four markers plus `EntityStart` | RA:121-129; GM:803 | S | Not cleaned up |

### 3.2 Manifest (server Lua table returned by `WB.Build`, WB:6334-6355)
| Field | Reader | What breaks |
|---|---|---|
| `World`, `Layout`, `EntityNodes`, `Navigation`, `EntityDen` | OC:265; PFC:2000-2012; PSC:811; RA:416-418 | Fatal (Pool Foam) |
| `Pumps[i]` = `{Index, Model, Prompt, Lamp, GaugeNeedlePivot, GaugeNeedleZeroCFrame, GaugeNeedleFullCFrame, GaugePressureValue (NumberValue), GaugePressureText (TextLabel)}`; optional `LampGlow`, `LeverStatusRing`, `Lever`, `LeverRestCFrame`. `#Pumps` = goal | OC:270-286, 516, 550-568 | Fatal (assert) |
| `PressureDoors[]` = `{Door (BasePart), Stripe?}`; may be empty | OC:288, 433-457 | Fatal if not a table |
| `Drains[pumpIndex].Water = {CFrame, Size}` | OC:345-349, 610 | Pump doesn't drain |
| `Exit.Trigger`, `Exit.Backstop`: two BaseParts with `Level2_ExitCompletionBeam`, `Level2_ExitCompletionSensorThickness ≥ 8`, Transparency 1, no Neon/lights/decals | OC:295-319; TS:101-150 | Fatal |
| `Exit.SafeSpawn` (with `Level2_ExitRecoverySpawn`), `TransitionEnd`, `TransitionLength ≥ 2000` (and within 35% of measured), `FlumeBoundsCenter/Size`, `PathPoints` (>32), `BoreRadius`, `Recycle{TriggerY, DeltaY, LandingY, Radius, CenterX, CenterZ, Turns ≥ 3, TopY, BottomY}`, `Mouth` (optional), `FlumeModel` with one `Level2_ExitTransitionEndStop` | OC:104, 320-342, 465-482, 782-799; TS:209-383 | Fatal, or a failed test suite |
| `Arrival.ElevatorSpawn` | RA:382 | Fatal |
| `WaterRegions`, `PreviousWaterAppearance`, `TerrainCenter`, `TerrainSize` | RA:196-235 | Water leaks into the lobby, or the fallback full wipe |
| `BuoyantProps`: **read but never built** (existing bug) | PSC:191 | Props are not excluded from Pool Slide spawn sight rays |

### 3.3 Layout (also the AI route graph)
| Item | Reader | What breaks |
|---|---|---|
| `Halls[i] = {Index, Id, MinX, MaxX, MinZ, MaxZ, Center (Y=0), Connections, Role, KidsIndex, …}`. **Rooms must be axis-aligned rectangles** | PFN:163-208; PFC:192-232 | Hall lookup, and the kids-only targeting before pump 1 |
| `Corridors[i] = {Index, A, B, Axis "X"/"Z", Cross, From, To, Width (default 34), Kind Open/SharedWall/PressureDoor, DrainGroup}`, `CorridorByPair["min:max"]` | PFN:210-314; LG:139-179 | Graph route fails; only pathfinding is left |
| Corridors are straight and axis-aligned. Points inside [From,To] ±11 and Cross ±(W/2+2) are **always snapped to Cross** | PFN:909-932, 1013-1023, 1400-1415, 2446-2470 | Off-axis or off-centre openings snap routes into walls |
| `KidsArea` (≥1; makes 5), `PumpHalls`, `Seed` (PFC RNG), `Arrival`, `SlideHalls`, `GrandSlideHall`, `Bounds` | PFC:2008-2012, 2054 | Pool Foam start fails (fatal) |
| Invariants: every grand-hall corridor is a PressureDoor and the rest stays reachable; one drain per pump (Open, not kids) | LG:549-599; PFN:227-231 | Pool Foam routes through closed doors |
| Graph waypoints carry the foam's current foot Y; floor resolution searches +12/−68 | PFN:296-312, 516, 528, 980 | A connected hall more than about 12 studs higher is unresolvable on the graph route |

### 3.4 Per-part attributes and names
| Item | Reader | Side | What breaks |
|---|---|---|---|
| `Level2_EntityGround=true` on **every** walkable collider (CanCollide, normal Y ≥ .57). Read on the hit part, so Model attributes don't count. **Snapshotted at `Controller.Start`** | PFN:139-142, 377-393, 515-559; PSN:360, 627 | S | NO_FLOOR → spawn fatal; the AI can't walk |
| `Level2_NoEntityGround` on roofs and all slide/flume collision | PFN:141, 538; PSN:146, 628 | S | AI plans over roofs or slides |
| Name contains `Ceiling`/`Skylight`/`Roof` → NoEntityGround + `PathfindingModifier Label "Level2Roof"` (cost `math.huge`). **Trap:** a floor named "Skylight Hall Floor" becomes unwalkable | WB:6317-6332; PFN:1936; PSN:2127 | S | Wrong routes, or dead floors |
| `Level2_BuoyantProp` (excluded from nav queries, not from sight) | PFN:365-367; PSN:361 | S | Props block AI |
| `Level2_SlideFloor` + `Level2_SlideDirection` (Vector3) [+ `Level2_OneWayExit` on the exit]. Any flagged floor with grade ≥ .20 ragdolls | L2SL:524-541, 669-671; SRS:198-252; TS:165-197, 580 | S+C | No slide or ride |
| Slide detection takes the **first collidable part** under the player, and it must be inside the world model | L2SL:38-41; SRS:209-224 | S+C | A kit collider above a slide hides it |
| Flume Model `Level2_RecycleActive`, `Level2_RecycleTriggerY`, `Level2_RecycleDeltaY`, `Level2_HelixCenterX/Z`, `Level2_HelixRadius`, `Level2_FlumeBoreRadius` | L2SL:568-614 | C | No client recycle (server backstop only) |
| Pump Model `Level2_PumpRunning`, `Level2_LeverHandleColorValue`; Part `Level 2 Pump Intake Pipe` inside it | L2SC:299, 362-371, 407-412; L2AC:427 | C | No drain gurgle; generic valve colour |
| `Level 2 Corridor Vault Light <corridor.Index>`, **unique per corridor** | L2SC:292, 815-822 | C | Corridor echoes collapse into one source |
| `Level 2 Navigation Node ` (with `Level2_Role`), `Level 2 Entity Patrol Node `, `Level 2 Entity Den ` | L2SC:295-296, 570-580; PSC:213-215 | S+C | **Monster groans never play** (55–180 stud anchors, no fallback) |
| `^Level 2 Pressure Door %d+$` | L2SC:805 | C | Door cue without positions |
| `Level 2 Exit Flume` model with `…Collision Floor NNN`; "Recovery Chamber" in ≥6 part names, ≥40 studs from flume floors | TS:57-80, 367-381 | S | Test suite fails |
| Prefixes `Level 2 Lounger Seat `, `Beach Ball `, `Pool Noodle `, `Pool Raft `, `Pool Float Ring ` → **SRS adds 6 runtime Textures each** | SRS:496-562 | S | Instance bloat on PBR props |
| `"Water Floor"` in a name = ignored by the prop-spawn overlap check | WB:4987-5004 | S | Floating props can't spawn |
| Avoid root names `PitZones`, `PuzzleItems`, `Decor`, `Maze`, `Elevator`, `ElevatorSpawn`, `MazeStart`, `EntityStart` | RP:30-41; GM:1685-1695 | S | Level 1 cleanup deletes them |
| Avoid prompt names `ZyntraShopPrompt`, `ZyntraPartyPrompt`, `Level{4,5,6}DeveloperPreview*Prompt`, `Level1BlenderPreviewEntry` | sweep M21 | C | Foreign prompt handlers |

### 3.5 Physical, spatial and query rules
| Rule | Reader | Side | What breaks |
|---|---|---|---|
| **Arrival:** dry, flat, collidable floor about **32 wide × 30 deep** in front of `ElevatorSpawn`. RA places **all server players**, up to 8 per row at 4-stud spacing, rows 4 forward, +4 up (RA:387-401); GM's own grid is 7 rows × 4 at ±2/±6 (GM:802-821) | RA, GM, REC:31-64 | S | Players land in water or walls |
| Pump: at hall centre + floor Y, about 6.78 tall after `ScaleTo(.34)`. Reach 10 (+2). Head→grip ray ignores CanCollide, so **any queryable mesh or another player in between blocks it** | OC:215-243; WB:4312-4313, 4601-4626 | S | Pump silently refuses |
| No other E-prompt near a pump (OnePerButton exclusivity) | CLAUDE.md Level 4 note | C | Prompt hidden |
| Pressure door `2.2 × 36 × 34`, Y-centre 14, at the corridor's **`To`** end; rises Size.Y+6 = 42 | WB:4955-4967; OC:440-441 | S | Stuck door |
| Doorways 30×30, corridors 34 wide. The **Pool Slide template certifies corridor fit** (`Level2_PoolSlideCorridorFitVerified`) | PSC:265-281; CFG:57, 98-99 | S | Changing the tunnel or doorway envelope invalidates the certification |
| Exit flume: bore 8; grade .21 > release .12; helix radius 96 × 3 turns; bottom about −428, which must stay ≥40 above FallenPartsDestroyHeight; overlapping floors; ride >15 s at 105 studs/s; sensors 9 thick | WB:3229-3335, 3570-3607; TS:189-230, 313-343 | S | Test suite or ride fails |
| Level 3 continuation tube hard-codes radius 8, colour (218,226,211), resume speed 62 | L3WB:1620, 1665-1700, 1738-1739; TS:396-450 | S | Visible seam if the flume is restyled alone |
| Pool Foam body: `GetPartBoundsInBox` 4.2×5.7×4.2 from foot +0.18 (**bounding boxes, not mesh shape**). Steppable = EntityGround **and** bbox top ≤ foot +3.55. ≤6 steppable hits per 0.9-stud sweep | PFN:32, 130-137, 567-643; PFCFG:170-176 | S | A colliding room or hill mesh is a solid wall |
| Sight and kill rays respect **CanQuery, not CanCollide**. Kill = 5.5 studs **3D**, foot→root | PFO:173-179, 199-203; PFC:764-786, 849, 884; PFCFG:167 | S | Collider vs visual mismatch → foam freezes or kills through walls |
| Re-entry: anchored floor with Normal.Y ≥ .85 (≤31.8°) under 4 corners, clear 2.8×4.8×2.8 bounding box. **Water counts as floor** | RP:19-22, 43-69 | S | Every revive falls back to ElevatorSpawn |
| Route markers sit on the first collidable hit within 12 studs below | RMS:103-123, 149-161 | C/S | Markers float or clip on slopes |
| Wading audio: the first queryable hit from foot +1.5 down 6.5 must be terrain Water | SC:1379-1386, 1481-1506 | C | Dry-tile footsteps in water |
| **Terrain water only**: surface Y .1, depth ≤ 2 ("below the swim threshold"); buoyant props float only on terrain water | CFG:108-121; WB:4974-4983 | S/C | Swimming; props sink |
| Terrain can never be AI ground (it can't carry the attribute) or REC ground (REC:41-53) | PFN:537 | S/C | — |
| Every build wipes terrain over X −1050..1050, Y −116..84, Z −810..1290 | RA:205-214, 348 | S | Any terrain feature inside it is erased |
| Collision groups: none used. DevNoclip is paired with groups **registered at boot** | GM:193-198 | S | A late-registered kit group collides with noclip devs |
| Streaming: pump Models, the flume Model and audio anchors are scanned client-side at any distance; only the Pool Slide is Persistent (PSC:498) | L2AC:420-424; L2SC:312-315, 362-371; L2SL:568-580 | C | Missing ambience and recycle on distant clients |
| `workspace.LobbyReimaginedPreview` (centre (220,30,−760), X 120..320, Z −904..−616) **stays in the world** during Level 2 | GM:618-619; RUI:358-361; RA:61-68 | S | The kit footprint must stay north of about Z −600 (today's MinZ is −460) |

### 3.6 Corrections and dropped items
These are claims from the reader reports that the sweep or the code proved wrong. They are corrected above.

| # | Reader claim | What the code shows |
|---|---|---|
| W1 | "Every gameplay ray ignores water" | RP:19-22 doesn't, the SC wade ray hits water on purpose (SC:1381), and FC rays use the default (FC:119-120, 715-716) |
| W2 | Arrival needs "about 24×12 studs" | About 32 wide (RA:387-401) |
| W3 | `BeingChased`/`Level2_PoolFoamTargeted` read by EntityShakeController | ESC reads `BeingChased` only in its Level 1 branch (ESC:85-99); `Level2_PoolFoamTargeted` has no reader outside PFC. **Dropped from the contract** |
| W4 | Pool Slide "spawns at pump 2" | It spawns once `Level2Pumps ≥ 2`, at the best-scoring anchor: ≥100 **flat** studs from every player, +30 if hidden, near 140 from the pump-2 activator (PSC:228-263) |
| W5 | Layout reader: "Use Attachments for PoolFoamSpawn" | **Wrong.** Must be Parts directly in `Level 2 Entity Nodes` (PFC:236-237). Attachments may only be authoring markers converted to Parts at build time |
| W6 | Foam reader: "plain invisible Part colliders everywhere" | Breaks camera pull-in (Poppercam only stops at CanCollide parts with Transparency < .25) and risks streaming. Section 6.4 replaces it |
| W7 | List of `Level2_ExitTransition` readers | Add RMS:201; Level 3 Table Hiding Client:101-102 reads `Level2_ForcedSliding` |
| W8 | "≈52k" / "≈71k" | 56,001 measured (2.1) |
| — | CLAUDE.md:126 "exactly one hostile" | Two (PSCFG:4, RA:425-445) |
| — | README.md:327-329 "a pinned seed skips the fallback" | It skips only the random stride; fallback seed 101 still runs (LG:916-920, 966) |
| — | README:345-362 Level 2 cover timeouts (15/35/16 s) | Superseded by the shared 60 s token barrier (RLR:5); `poolaccess` only shows text (RUI:4692-4695) |

### 3.7 Master tuning keys that already break the current generator
These belong in the kit decision (Q32):
- `L2_SlideHallCount = 0` (MC:131-133) → every attempt fails, because `chooseSpread` always returns the exit hall (LG:206-219, 715-717).
- `L2_KidsAreaRoomCount` 0 or 1 (MC:137-139) → no dry kids room for pump 1 (LG:438-448).
- `L2_DeepPoolDepth` up to 6 (MC:142-144) → swimming.
- `L2_MinimumLeafSize < 145` → leaves that LG:291-293 always rejects.

---

## 4. The Level 1 Blender facelift, and what transfers

### 4.1 How Level 1 was done
1. **Kit, authored headless.**
   - Command: `D:/Blender/blender.exe -b --factory-startup --python-exit-code 1 -P tools/level1_blender/build.py` (`tools/level1_blender/README.md:12`). V2 is `build_v2.py`.
   - Geometry is procedural bmesh. Scale is 0.28 m per stud. Axis map: Blender (x,y,z) → Roblox (x,z,−y) (build.py:15-16). UVs are box-projected in studs per material `tileStuds` (build.py:116-135).
   - Cell 24, wall 14, half-walls at ±11.5. Socket bits N(+Z)=1, E=2, S(−Z)=4, W=8 (build.py:157-161, 344-367, 437).
   - V2 has 41 components, 42 rooms, 93 chunks and 22,768 triangles. `SelectionWeight` is Quiet 16 / ColumnBay 1 / special 4 / LowWall 3 (build_v2.py:246-286).
2. **Export.**
   - Chunk = component × material.
   - Binary little-endian: u32 nv, nn, nu, nf; f32 positions, normals, UVs; u32[9] per triangle. Encoded as base64. Limits: ≤20k triangles and ≤60k vertices (build.py:401-446).
   - Plus `export/manifest.json` and an FBX for review only.
   - Checks: `check_assets.py` and `verify_native.py`.
3. **Upload.**
   - `import_assets.py --upload --studio-id <exact>` slices `build()` out of `tools/level4_blender/upload.luau` (import_assets.py:142-143).
   - It inlines base64 into `execute_luau`, at most 650k characters per batch, and calls `AssetService:CreateAssetAsync` (group 1039373905).
   - Receipts are keyed by `wireSha256`, which allows reuse: 47 of 93 were reused from V1.
   - Textures: `publish_textures.py` runs a loopback server and calls MCP `upload_image`, with sha256 receipts.
4. **Install.**
   - One `execute_luau` builds `ServerStorage.Level1BlenderKitV2` off-tree and sets `Ready` last (import_assets.py:47-130).
   - Contents: `Components/<Name>` MeshParts (Box fidelity, all Can* false, `SurfaceAppearance "BlenderPBR"`), `Colliders` (group `Decor`), and `Rooms/<Name>` with `OpenMask`/`SelectionWeight`.
5. **Renderer.** BRR is a **skin over the live maze**.
   - MazeGenerator still builds every native Part. BRR sets them to Transparency 1 and keeps their collision (BRR:168-173).
   - It clones a weighted room per cell (BRR:179-245), using unseeded `math.random()` (BRR:189).
   - Result: 19,625–20,357 meshes per preview round, an instance count that goes **up**.
6. **Preview button.**
   - Server script `Level1BlenderPreviewAccess`:
     - creates an invisible host `Level1BlenderPreviewEntry` at ChamberFloor + (−20, 4.42, 0);
     - places it in `Level1QueueRoom` or `QueueBay_Level1`;
     - gates on DevAccess and a 12-stud range;
     - invokes `ServerStorage.Level1BlenderPreviewLaunch` (L1PA:24-113).
   - Client `Level1BlenderPreviewButton` builds the prompt only for DevAccess players (:5-34).
   - GM handles the launch:
     - checks: GM:3297-3313;
     - Studio local round: GM:3319-3344;
     - published: teleport to a reserved server with `packet.Level1BlenderPreview` (GM:3345-3357);
     - the arrival arm re-checks DevAccess for every participant (GM:3939-3955);
     - no Continue (GM:2449) and no `zyntraLevelCompleted` (GM:3086);
     - the flag is reset in Level 1 cleanup (GM:1683).

### 4.2 What transfers
| Piece | Transfers unchanged | Needs new work for Level 2 |
|---|---|---|
| bmesh `Mesh` class, chunk binary, manifest, `check_assets` structure | ✔ (generalise the Level-1-only asserts: import_assets.py:192-193, publish_textures.py:24, check_assets.py:14 grid 24/14/2) | Level 2 dimensions and component set |
| Uploader (`upload.luau` `build()`, wireSha256 reuse), `publish_textures.py`, off-tree `Ready` install | ✔ | Kit name `Level2BlenderKit` and the whitelist |
| Socket masks on a 24-stud cell | ✘ | Level 2 has no grid: doors sit at continuous `Cross` offsets up to 110 off-centre (§6.2) |
| "Skin over native parts" renderer | ✘ **Must not copy**: it adds instances | The builder must **not** build the native visuals at all |
| Unseeded room picks (BRR:189) | ✘ | Use the layout seed so `Level2Seed` pins the art too |
| `SurfaceAppearance` per MeshPart | Optional | Costs +1 instance per MeshPart; MaterialVariant costs 0 (§5.4) |
| Preview access + button + GM launch, reserved-server arm, progression guards | ✔ pattern | New names; per-level host offset; Level 2 cleanup reset; Level 2 ready check (§6.8) |
| `test_level1_blender_preview(_access).py` | ✔ pattern | Point at the mirror, not `drafts/` |

---

## 5. Asset pipeline available

### 5.1 Tools (checked 2026-10-03 by the pipeline reader)
| Tool | Version / path | Use |
|---|---|---|
| Blender | **5.2.0 LTS**, `D:\Blender\blender.exe` | Headless `-b … --python-exit-code 1 -P script -- args`. At most 4 concurrent (`G:\Roblox\_local\l4facelift\v3\blrun.py`, about 2 GB each). **Never** the GUI MCP on `localhost:9876` (owner's open Blender), and never save over a master blend |
| Codex CLI | 0.160.0; `codex exec -m gpt-6.1-sol` (fallback `gpt-6-sol`) `--skip-git-repo-check --dangerously-bypass-approvals-and-sandbox -C …` | Built-in `image_gen`. **The prompt must say "do NOT run git"** (a batch auto-committed on 2026-09-30: 3d7f70e, 5eae851). Output is 1254² PNG; Roblox stores 1024² |
| Meshy | Claude MCP `mcp__meshy__*` | `meshy_image_to_3d` `{ai_model meshy-6/7, should_texture, enable_pbr, remove_lighting, should_remesh, target_polycount 2.5–8k, target_formats ["glb"]}` costs 30 credits each. Balance 1,695 (2026-10-02 19:25); **cap about 1,000** |
| PBR from albedo | `tools/level4_blender/make_pbr.py` (numpy+PIL, wrap-safe, OpenGL normals) via `make_pbr_all.py` + `pbr_spec.json` | Already imported by Level 1 (`prepare_v2_textures.py:10-13`) |
| Meshy import | `tools/level4_blender/import_meshy.py` + `meshy_specs.json` | Canonical frame, decimation, **exactly one textured atlas**, rough/metal split, slab collision (`:75-364`). Hard-coded TEX dir and `L4A_` prefix |
| Mesh upload | `tools/level4_blender/studio_upload.py` (900k characters per call, `results.jsonl` ledger, `--reuse`) or `tools/level1_blender/import_assets.py --upload` (650k, wireSha256 receipts) | `CreateAssetAsync` can return `UploadFailed` (`results_v2.jsonl` id 321) → retry |
| Texture upload | `tools/level1_blender/publish_textures.py` (loopback + MCP `upload_image`, sha256 receipts) | Not affected by the sandbox's missing HTTP |
| Existing Level 2 meshes | `assets/level2/*.luau` (column flares 90304501186271 / 118916035196716 / 111134467625970; closed end cap 107409495820821; cradle 132916619634128), `tools/level2_arch_rib_obj.py` (ribs 121489049526127 / 105818906248010) | Reusable or replaceable |

### 5.2 Studio MCP sandbox limits (CLAUDE.md 2026-10-02)
`execute_luau` has:
- no HttpService;
- no `shared`/`_G` between calls;
- `task.spawn` work that dies with the call;
- **no creating or reparenting scripts** under Workspace/ServerStorage. New scripts go through MCP `multi_edit` with `className`, then a manifest item (`install_sources.py:118-120`).

What still works: `UpdateSourceAsync`, `CreateAssetAsync` and a 1.2 MB payload. Large MCP results spill to files with a cap of about 100k characters.

Workarounds already in use:
- inline base64 in the payload;
- StringValue staging folders between phases (`place_driver.py:60-87`);
- re-running `--phase` after an MCP timeout.

### 5.3 Pitfalls already paid for
- **Camera.** Poppercam stops only at CanCollide parts with Transparency < .25. Invisible colliders under non-colliding meshes let the camera clip. The Level 4 fix is opaque black occluders inset 0.1 (`make_place.py:47, 106-118`).
- **Streaming.** A streamed 755×480 floor collider dropped on the client, so Level 4's `Collision` must be Persistent.
- **Lighting.** The place runs LightingStyle **Realistic**. Blender light values come out far too dim; Level 4 keeps gains in `make_place.py:35-45`.
- **Level 1 readability lesson.** The client re-applies the dark baseline.
- **Template leaks.** Runtime `CreateMeshPartAsync` templates leaked 21 duplicates into the ServerStorage root. Adopt an existing copy by name + MeshId first (CLAUDE.md:450). The rib leak path is WB:1214-1222 vs 1200.
- **Parallel Claude agents.** Heavy fan-out burned about 2.3M tokens for nothing. Heavy batch work goes to `codex exec` jobs.
- **`cull_hidden.py`** is Level-4-coordinate-bound and saves 2–6%. **Skip it.** Delete hidden faces at authoring time.

### 5.4 A route the pipeline reader missed: runtime bake plus MaterialVariant PBR
`LobbyReimaginedPreview/RuntimeBake.ModuleScript.lua:1-60` (the **live** lobby every player spawns in) and `Level 6 Systems/Level6BlenderRuntimeBake.ModuleScript.lua:1-135` do the following:
- **Storage.** Blender chunks are stored as zstd + base64 StringValues in ServerStorage.
- **Bake.** Each server rebuilds them: EditableMesh → `AssetService:CreateDataModelContentAsync` → `CreateMeshPartAsync(content, {CollisionFidelity=Box})`. **No asset upload, no moderation, no ID ledger** (Level6BlenderRuntimeBake:31-79).
- **PBR without extra instances.** It applies PBR with `part.MaterialVariant = <variant>` on SmoothPlastic and `TextureID = ""`. It asserts the variant's `StudsPerTile` equals the authored UV scale (:111-120). So **a tiled-PBR MeshPart costs 1 instance**, against 2 with a SurfaceAppearance.
- **Level 2 already uses MaterialVariants** on Parts for the kids rooms (WB:133-143, 3679).
- **Costs:** per-server bake time (`BakeSeconds` attribute, RuntimeBake:197) and server EditableMesh memory (`"Server mesh memory unavailable"` assert, :31).
- **What it enables:** per-round procedural meshes. For example, one MeshPart per slide flume built from its path, instead of 106 clones.

---

## 6. Proposed architecture for Level 2 v2

### 6.1 Approaches
| | A. Fixed-footprint prefab rooms on a lattice | **B. Hybrid kit on the unchanged generator (recommended)** | C. Level 1-style skin |
|---|---|---|---|
| Generator | Rewrite `split`, inset, `connect` for sockets; re-measure `GenerationAttempts` (CFG:41-49) | **LG byte-identical.** Kit-only fields (FloorY, ceiling class, pool slope) come from a separate RNG on `layout.Seed` inside the kit builder | Unchanged |
| Rooms | Whole-room meshes per footprint × socket variant (combinatorial: up to 2 doors per side at continuous offsets today) | Large flat surfaces of **any size** are opaque Parts with PBR **MaterialVariants**: 1 instance each, tiled physically, and visual = collider = camera occluder = sight blocker. Every fixed-size feature is a Blender mesh | Native parts hidden + meshes on top |
| Contract risk | High (new graph, re-certify everything) | Low: same Halls/Corridors, same seeds → **A/B by `Level2Seed`** | Low |
| Instances | Lowest | About 11.6k (6.7) | **Higher than today** |
| Matches "Blender-authored rooms" | Fully | Features, trims, tunnels, columns, props and set pieces in Blender; flat expanses as PBR Parts | Yes, but defeats the goal |

**Recommendation: B** (Q1).
- It is the shortest path that keeps every row of §3 true by construction.
- It lets the owner compare preview and live on the same pinned seed.
- It still delivers the two things asked for: one mesh per tunnel, and Blender/Meshy look and props.
- A can follow later if the owner wants authored room layouts. The hybrid's mesh library carries over.

### 6.2 Kit components fitted to Level 2's real dimensions
All values are in studs. Every "mesh" is `CanCollide/CanQuery/CanTouch = false`, Box fidelity and Anchored, and uses MaterialVariant PBR (Meshy props use a SurfaceAppearance atlas).

| Component | Dimensions | Variants | Triangle budget | Collision (Parts) |
|---|---|---|---:|---|
| **Door surround** (replaces header + 32 slats + 30-piece ring + lintel faces + jamb faces) | 36 wide × 36 tall × 3.5 deep, +0.6 proud each face; opening 30×30 (doors may sit as close as 21 from a hall corner, LG:126-137 overlap ≥42) | Standard; Kids (Part.Color tint for Sun/Coral/Lagoon); PressureDoor (slot for the 2.2-thick door at the `To` side); FlumeGap (grand hall only, 18.5² at y 83.3, WB:3642-3647) | ≤1,500 | Jambs and lintel come from the wall-run Parts (below), so the module needs none |
| **Wall run** | Any length, 3.5 thick, from −depth−1 (no buried 4-stud skirt) to height+1.85 | MaterialVariant `L2 Wall Tile` (7-stud tile, WB:64-76) | Part | It *is* the collider. Above each door a lintel Part from 30 to the top |
| **Hall floor** | Any size. Dry: top 0, 0.7 thick. Wet: top −depth, 1.2 thick | MaterialVariant `L2 Pool Tile` (10-stud) / `L2 Deck Tile` (7-stud). Wet name **must contain "Water Floor"** | Part | It *is* the collider, `Level2_EntityGround` |
| **Pool step / terrace** (§6.6) | Strip across the hall, rise ≤0.6, run ≥4 | — | Part | EntityGround |
| **Ceiling** | Slabs as Parts (MaterialVariant 9-stud) named `Level 2 Overhead Tile n` (**must not** contain Ceiling/Skylight/Roof). Skylight frame meshes per slot (12-wide slots, WB:403-487 plan unchanged). **One** invisible `Level 2 Hall Roof Collider` (Transparency 1, CastShadow false) + 1 PathfindingModifier per hall | Height classes 34 / 42 / 52 (+76 slide, 96 grand) | Frames ≤800 | Roof collider |
| **Cove trim** (replaces 4 light seals + 4 shadow coves) | Profile 1.25 × 3, scaled along length (plain painted metal, so stretch is invisible) | Kids drop 1.5 | ≤200 | none |
| **Tunnel body: one mesh per tunnel** | Interior 34 wide (CFG:57), today's vault silhouette (rib radius 13.2, vault radius 14.1 × 1.9, WB:4823, 4839) with ribs and a lamp fixture baked in | **8 length buckets, 60–88 in steps of 4** (scale ≤ ±3.3% along the axis) × {Standard, Kids} = 16 meshes | ≤3,000 | See §6.5 |
| **Column** (replaces 14 instances) | Shaft + 2 flares baked; diameters 4.5 / 5.5 / 9 (WB:1153-1157) | 3 | ≤800 | 1 shaft cylinder + 1 EntityGround flare band (WB:1303-1338 profile, simplified) |
| **Ring Corridor ring** | radius = min(shortSide·.5−6, H−5, 13) (WB:6053-6083) → 3 radius buckets | 3 | ≤1,000 | 2–4 foot boxes (as WB:1815-1832) |
| **Stairs, diving tower, overlook, play tower, slide-kit frame** | Today's footprints (WB:1932-1955, 5130-5440) | Prefab meshes | ≤2,500 each | Per-step EntityGround boxes, rise ≤0.78 (keep `makeStairFlight` geometry invisible) |
| **Pump shell** | Today's 6.78-tall station, scaled 0.34 | 1 | ≤3,000 | Keep Lever/LeverGrip/Prompt/Lamp/LampGlow/StatusRing/Needle/Gauge GUI/NumberValue/`Level 2 Pump Intake Pipe` as today (OC:270-286, L2SC:299) |
| **Arrival gate** | 16-part story gate (WB:5755-5820) → 1 mesh + 2 SurfaceGuis | 1 | ≤2,000 | none (story only) |
| **Kids sets** | Ball bed as 1–2 meshes (balls are non-colliding today, WB:3766-3770); slide tower and splash pool as meshes | — | ≤4,000 | Keep today's collision boxes |
| **Exit helix + transfer** | **Constant shape**: `plungeEnd = (Bounds.MaxX+60+41, 4, deckZ)`, Bounds.MaxX is 700 for every seed (CFG:19-25) and grand hall height 96 is fixed. Only deckZ translates it | 1 mesh set (≤4 chunks, single-sided inward) | ≤20k per chunk | Unchanged: 6 strips per segment with `Level2_SlideFloor` / `SlideDirection` / `OneWayExit` (WB:2513-2582) |
| **Exit plunge** | Varies with `hall.MaxX` (shell gap 30–44) | Procedural: keep today's MeshPart segments, or a runtime-baked mesh (§5.4) | — | Unchanged |
| **Meshy props** (loungers, lifeguard chair, signage, lockers, drains, crates, pool toys) | ≤2.5k triangles each (Level 4 rule, `BRIEF.md:33`), 1024² atlas (512² small) | ~25 | ≤2,500 | 0–1 box each; buoyant props keep `Level2_BuoyantProp` and **avoid the SRS prefixes** (§3.4) |

### 6.3 Generator changes
- **Approach B: none in LG.** The kit builder derives its extras from `Random.new(layout.Seed + 0x2B1E)`, so LG's load-bearing draw order (LG:275-276) is untouched:
  - `FloorY`: 0 for Arrival, the kids block, both ends of every drain, PressureDoor and SharedWall corridor, and the exit hall's corridors.
  - `CeilingClass` (34/42/52; slide and grand fixed).
  - `PoolSlope`.
- **Validation added in the kit builder:**
  1. |ΔFloorY| ≤ 8 across any corridor.
  2. Drain and PressureDoor corridors are flat.
  3. Every corridor `Cross` lies inside both halls' wall spans with ≥21 to each corner.
  4. Every kids hall has a standable `Level2_PoolFoamSpawn` Part.
  5. The arrival 32×30 clear box is satisfied.
- **The archetype roll** (LG:603-617) still picks a family. The kit maps each archetype to a dressing recipe:
  - Pillar Basin / Column Forest → columns;
  - Ring Corridor → rings;
  - Skylight Hall → strip skylights;
  - Porthole → 3 porthole meshes.
- **The Master `L2_*` geometry keys** are clamped for the kit (Q32).

### 6.4 Collision strategy (rules for every kit piece)
1. **Big flat surfaces:** the visual *is* the collider (opaque Part + MaterialVariant). Camera (Poppercam), sight rays (CanQuery), route markers (RMS:103-123), re-entry (RP:43-69) and slide/ground rays all agree automatically. This replaces W6.
2. **Mesh features** never collide or query. The silhouette that should block sight gets a box Part that matches what players see through (PFO:173-179). Openings stay open: arches, railings, grates and glass get no box.
3. **No colliding mesh anywhere.** `GetPartBoundsInBox` sees bounding boxes (PFN:593), and RP:65 does the same.
4. **Every walkable collider:** `Level2_EntityGround`, inside `World`, present before `Controller.Start` (snapshot, PFN:377-393). Rises ≤3 studs per piece and is ≥4 studs across (PFN:32, 567-643).
5. **Roofs:** one per hall and one per tunnel, named with "Roof"/"Ceiling". **No other kit part name** contains Ceiling/Skylight/Roof.
6. **Default collision group only** (GM:193-198).
7. **Water:** terrain only. One region per hall and per tunnel, recorded in `WaterRegions`. Each drain corridor is its own region (OC:345-349). Any water-surface visual mesh is `CanQuery=false` (SC:1379-1386, WB:1112-1121).
8. **Streaming:** keep today's part sizes (halls ≤277×269 have streamed fine). Set the exit flume Model and the pump Models `ModelStreamingMode = Persistent` (L2SL:568-580, L2AC:420-424). Verify on a client in Studio.

### 6.5 Tunnels redesigned
**Per tunnel: 15 instances, against 472–481 today.**

| Instance | Notes |
|---|---|
| Model `Level 2 Corridor <i>` | 1 |
| Tunnel MeshPart (length bucket, skin) | 1 |
| `Level 2 Corridor Water Floor <i>` Part, `(G+4) × 1.2 × 34`, top −depth, EntityGround | 1, as WB:4725-4729 |
| Side ledge + curb, EntityGround, top .45 / −.8 | 2, as WB:4754-4788 |
| Side colliders, stepped, **inner face at ±12.1 at floor level** (today's rib-foot line, the envelope the Pool Slide fit was certified against) then following the vault inside it by ≤0.5 | 6 (3 per side) |
| `Level 2 Corridor Roof Collider <i>` + PathfindingModifier | 2 |
| `Level 2 Corridor Vault Light <corridor.Index>` Part + **one** PointLight (Brightness .7, Range 26, **Shadows false**) | 2 |
| **Total** | **15** |

- **Mouths cost nothing in the tunnel.** They are the hall's door-surround modules.
- **Kinds:**
  - **PressureDoor** adds today's `Level 2 Pressure Door <i>` + Stripe at the `To` end (WB:4955-4967).
  - **Drainable** uses depth 1.8 and its own water region.
  - **SharedWall** keeps the 2 thresholds (WB:4663-4681).
- **Kids skin:** used if either end is a kids hall, as today (WB:4709-4722).

### 6.6 Height variation options and their impact on Pool Foam
| Option | Geometry rule | Pool Foam / Pool Slide | Other systems | Verdict |
|---|---|---|---|---|
| **Sloped pool floor, shallow → deep** (owner: yes) | One tilted wet-floor Part per hall, from −0.8 to −2.0 (CFG:108-111 "below the swim threshold"). Optional 1–2 terrace steps ≤0.6. The water region box runs from the deepest point to .1 | No impact: 1.2 rise ≪ the 3.55 steppable rule (PFN:567-570); slope ≈0.5° | Re-entry, route markers and wading are fine; terrain water still reads as floor for re-entry (RP:19-22) | **Do it.** Visually subtle; terraces and tile banding sell it (Q16) |
| Deeper end (>2.5) | Same, deeper | Foam walks the bottom (rays ignore water); a swimming player's root is far above the foam foot → 5.5 3D kill radius (PFCFG:167) rarely reached | Swimming changes movement, noise (NR speed ≥2) and wading audio (SC:1481-1506); dormant code at WB:4733, 6139 starts building | Only with an owner decision (Q16) |
| **Steps/ramps between rooms** (owner: yes) | Per-hall FloorY with \|ΔY\| ≤ 8 per corridor. Level changes live in **dry** stair or ramp tunnels (water must stay a flat box per region, WB:349-354). Ramp collider pieces rise ≤3, ≥4 long, slope ≤15° (re-entry limit 31.8°, RP:43-69). Stairs 0.78 rise × 2.3 run as `makeStairFlight` | Pathfinding is fine. The graph route puts waypoints at the foam's current Y and resolves +12/−68 (PFN:296-312, 516, 528), so ΔY ≤ 8 stays resolvable. **Recommended code change:** carry hall FloorY into `graphRoute` in PFN and PSN. Pool Slide can't hit players >7 above or below it (PSC:43) | Drain, PressureDoor, SharedWall and kids corridors stay flat (§6.3). Objective UI says "CLIMB" above 15 (L2OUI:181-207). Exit hall FloorY must stay ≥ −70 (helix floor vs −500, TS:223-230) | **Do it**, ΔY ≤ 8, plus the small nav change (Q17, Q18) |
| **Varied ceiling heights** (owner: yes) | Classes 34 / 42 / 52 for ordinary halls; slide 76 and grand 96 fixed (deck at H−22, WB:3030-3043). **Not lower than 34:** doors are 30 and the lintel top is 31.85+; lower doors void the Pool Slide corridor-fit certification (PSC:267-270) | None (bodies 6 and 14.8 tall) | Enclosed halls get dimmer with height: ceiling-panel Range is 44 (CFG:126-127) | **Do it**, taller only (Q19) |
| Small hills (owner: **no**) | Would need split Part colliders (terrain can't be ground, PFN:537, and RA:205-214 wipes it) | Each piece ≤3 rise / ≥4 across; hilltops >2.5 above the foam's foot make players unkillable at 5.5 3D (PFC:849, 884); more repaths (PFN:1778) | Buoyant props and wading break on mounds in water | **Skip.** Raised dry islands and decks give the same silhouette at zero nav risk |

### 6.7 Instance budget target, with the arithmetic
Seed basis: 39 halls / 61 tunnels / 5 SharedWall. The "today" column comes from §2.2 and is not additive.

| Bucket | Today | Kit target | Arithmetic |
|---|---:|---:|---|
| Tunnel mouths | 24,192 | 0 | Folded into door modules (counted under hall shells) |
| Tunnel bodies and shells | 8,094 | 915 | 61 × 15 |
| SharedWall thresholds | 20 | 10 | 5 × 2 |
| Hall shells (model, floor, walls, ceiling, lights, 5 nodes) | ~5,690 | 1,450 | 39 × 37: model 1 + floor 2 + walls 17 (doors avg 3.37 per hall × [2 runs + lintel + module] + solid runs) + ceiling 10 + lights 2 + nodes 5 |
| Hall dressing (new Meshy/Blender props) | (in #5, #13) | 1,400 | 39 × 12 props × (MeshPart + SA + 1 box) |
| Columns | 1,435 | 400 | ~100 × 4 |
| Ring Corridor rings | 2,500 | 80 | 20 × (mesh + 3 foot boxes) |
| Play structures, stairs, towers, kits | 4,700 | 1,200 | ~45 × ~25 (mesh + step boxes) |
| **Tube collision** | 4,870 | **4,870** | Unchanged in phase 1 (gameplay-critical) |
| Tube visuals | 2,200 | 60 | 1 mesh per flume, helix, kit tube; exit as ≤4 chunks; plunge as today or baked |
| Kids set pieces | 690 | 100 | Ball bed as a mesh |
| Pumps | 231 | 90 | 3 × 30 |
| Floating props | 470 | 250 | ~100 × (MeshPart + SA) + loungers; no SRS textures |
| Arrival, exit chamber (32-piece collar → 1 mesh), dens, folders | 230 | 150 | |
| Pool Foam rigs | 650 | 650 | Out of scope |
| **Total** | **56,001** | **≈ 11,600 (−79%)** | |
| Phase-2 option: slide collision from the path (Q23) | | **≈ 7,800 (−86%)** | 4,870 → ~1,000 |

Other budgets, for mobile (CFG:155-156: two thirds of players are on phones and tablets):

| Budget | Target | Today |
|---|---|---|
| Lights | ≤ 80 | 154 lights, **all** `Shadows=true` (`artifacts/claude-20260921/level2-perf/MEASUREMENTS.md:15-22`) |
| Shadow-casting lights | ≤ 6 | — |
| MaterialVariants | ≤ 12 × 4 maps at 1024² | — |
| Triangles per mesh | as in §6.2 | — |

- The gate is measured, not estimated: `Level2_WorldDescendants` plus a client frame-time sample on 3 pinned seeds.
- **No Level 2 draw-call or phone measurement exists today** (census reader).

### 6.8 Wiring: builder swap and preview button
1. **Builder.**
   - Add a new ModuleScript `ServerScriptService."Level 2 Systems"."Level 2 Kit Builder"`. It holds the kit cloners, generated from the kit manifest.
   - In WB, read `workspace:GetAttribute("Level2BlenderPreviewActive") == true` **once** at the top of `Build`. The precedent is `Level2ArchMeshRibs` (WB:1628-1633).
   - Branch only the visual call sites: `makeHallFloor`, `makeHallCeiling`, `makeWallWithGaps`, `makeCorridor` visuals, dressing and columns.
   - The gameplay builders (`makePumpStation`, `makeExitFlume`, `makeSlideHall` collision, `makeKidsHall` reservations, `makeCompatibilityArrival`, nodes, water, roof pass) and the manifest stay **exactly** as they are.
   - Because the switch lives in WB, RA:370 doesn't change. The alternative is the lobby-l2 reader's RA:370 swap to a separate module, which would have to re-implement the WB-local gameplay builders (Q4).
   - **Never** swap `LEVEL_GENERATORS[2]` (GM:139-143). Cleanup and sanitize use it too.
2. **GameManager.**
   - Generalise `launchBlenderPreview` / `canLaunchBlenderPreview` (GM:3296-3358) by level.
   - Level 2 readiness = `ServerStorage.Level2BlenderKit:GetAttribute("Ready")`.
   - Set and clear `Level2BlenderPreviewActive` around `prepareGroupLoading(attempt,{player},2,false)`.
   - **Add the flag to GM:2449** (no Continue to Level 3) **and GM:3086** (no `zyntraLevelCompleted`, records, `FirstClearLevel2` badge, ZyntraConfig:292).
   - Add a `packet.Level2BlenderPreview` arm with `selectedLevel == 2` next to GM:3939-3955.
   - Reset the flag at boot (beside GM:120) and in `cleanupActiveWorld` (GM:1735-1753).
   - Check the Level 2 win path that keeps the lifecycle open for riders (GM:3073-3076) when `nextLevel` is nil.
3. **Lobby.** Two new scripts, created in Studio first (CLAUDE.md:179-182):
   - `ServerScriptService.Level2BlenderPreviewAccess`
   - `StarterPlayerScripts.Level2BlenderPreviewButton`

   Names:
   - Remote `ReplicatedStorage.Level2BlenderPreviewRequest`
   - Bindable `ServerStorage.Level2BlenderPreviewLaunch`
   - Host `Level2BlenderPreviewEntry` with attribute `Level2BlenderPreviewHost`
   - Prompt `Level2DeveloperPreviewPrompt`, ActionText "ENTER LEVEL 2 FACELIFT PREVIEW"

   Rooms:
   - `LobbyReimaginedPreview.PreviewQueuePads.QueueBay_Level2` (R3QueueRevision 3, Ready, LobbyReimaginedOwned).
   - `ServerLobby.LevelQueueRooms.Level2QueueRoom` (`LevelNumber == 2`, TLB:2111, 2284).

   **Host offset is per level.** Level 1's ChamberFloor + (−20, 4.42, 0) points at Level 2's **doorway**, because Level 2 is `side = +1` (TLB:2936-2937, 2118).
   - R4 bay: `floor.Position + Vector3.new(20*sign(floor.X − PreviewCenter.X), 4.42, 0)`. This is inferred; the bay manifest lives only in `ServerStorage.LobbyReimaginedBlenderSource20261001R4` (RuntimeBake:8-9). **Measure it in a Play Server datamodel**, because the lobby is rebuilt at play start.
   - Old room: `(83, 34, −848)`, which is ≥8 from the column (outward 20.5), basin (19.2) and ladder (14.75) (TLB:1588-1655), and 12.2 from pad 6.
   - It must stay within the prompt's 10 studs and the server's 12.

### 6.9 Phased plan (every Studio step gated on `artifacts/level1-quality-20261002/coordination.md`)
State at 2026-10-03:
- The last entry (19:30 UTC) has **Level 4 holding Studio**, and the Level 1 readability follow-up queued behind it.
- `git status` shows uncommitted foreign edits to GameManager, RoundUI, FlashlightController and the lobby scripts. Level 2 must **merge, not overwrite**.

| Phase | Where | Work | Exit gate |
|---|---|---|---|
| P0 | offline | This analysis; owner answers §8 | Answers recorded here |
| P1 | offline | Codex imagegen: 3 style directions (pool tile, grout, wall, ceiling, metal, kids), each with a hero render prompt | **Owner picks one** (stop 1) |
| P2 | offline | `tools/level2_blender/` (forked from level1_blender; generalised asserts): door modules, 16 tunnel meshes, columns, rings, coves, skylight frames, stairs/towers, pump shell, gate, ball bed, exit helix. `make_pbr` maps → MaterialVariant specs. Meshy props ≤ ~750 credits + 250 reserve. `check_assets` (triangles, chunk limits, collider rules §6.4) | **Owner approves Blender renders** at real Level 2 dimensions (stop 2) |
| P3 | offline | `Level 2 Kit Builder` + WB flag branch + GM/lobby scripts. Fake-engine Luau tests with luau 0.737 (CodexTools): (a) LG output byte-identical with the flag on and off; (b) every §3.1–3.4 row asserted on built manifests for 20 seeds; (c) PFN body-box and steppable rules on every ramp/terrace piece; (d) projected instance count per seed; (e) `test_level1_blender_preview_access`-style access test. Update `test_level2_tunnel_height.py` / `test_level2_tile_face_culling.py` to skip the kit path | All green; compile probe offline |
| P4 | **Studio, gated** | Wait for an EDIT/no-Play handback in coordination.md → write a reservation there → `git status` + `pull_source_from_studio.py --audit` → upload meshes + textures (receipts) → install `ServerStorage.Level2BlenderKit` off-tree with `Ready` last → create MaterialVariants → create 2 new scripts (`multi_edit` + className) → `UpdateSourceAsync` WB/GM (merge foreign hunks) → `studio_compile_probe.luau` → manifest items → hand back in coordination.md | 0 drift, compile clean |
| P5 | **Studio, gated** | Play QA on pinned seeds (3), live vs preview: `Level2_WorldDescendants`, `Level2_BuildSeconds`, client frame p50/p95. Pool Foam spawn/patrol/chase/kill, pumps/drains/doors, exit ride + `Level 2 Exit Transition Test Suite`, re-entry, Pool Slide spawn/attack (**re-verify `Level2_PoolSlideCorridorFitVerified`** if any envelope changed), Device Simulator + `ForceTouchUI`, and one real phone if the owner agrees (Q31) | Target met (Q30); no contract regressions |
| P6 | offline → gated Studio | Height variation: terraces/slopes first, then ramp tunnels + PFN/PSN `graphRoute` FloorY (offline nav tests first) | Same QA |
| P7 | owner | Decide on replacing live (Q2). We never publish | — |

---

## 7. Risks and unknowns, ranked

1. **Silent contract failures.**
   - Pool Slide → UNAVAILABLE with only a warning (RA:428-440).
   - Groans vanish without the name anchors (L2SC:570-580).
   - A pump refuses because of a queryable mesh in the line of sight (OC:233-241).
   - A floor named "…Skylight…" becomes unwalkable (WB:6322-6331).
   - *Mitigation:* the P3 contract test, plus asserting readbacks (`Level2_PoolSlideState`) in P5.
2. **Concurrent Studio and GameManager edits.**
   - Three sessions are active (coordination.md). GameManager and RoundUI carry uncommitted foreign hunks; RoundUI sits at the 200-register limit (CLAUDE.md).
   - *Mitigation:* CAS merge, never `--overwrite-conflicts`. No RoundUI change is planned.
3. **Slide and flume physics.**
   - Slide collision is physics-tuned (overlap 1.5, friction .05, CFG:144-149). A new visual must not add a collider above a slide (L2SL:38-41).
   - *Mitigation:* phase 1 keeps the collision byte-identical.
4. **Pool Foam navigation on new colliders.**
   - Bounding-box blocking, the ground snapshot at start, ≤6 steppable sweeps, the hub/spoke lanes ±16–17 (WB:1514-1549) and the kids 24-wide hub (WB:4023-4067).
   - *Mitigation:* the dressing recipes keep the lanes clear; offline nav tests.
5. **Pool Slide re-certification** whenever doorway or tunnel envelopes change (PSC:265-281).
6. **Mobile performance is unmeasured.** No draw-call or phone figure exists. 154 shadowed lights today. A new PBR look can cost more texture memory than it saves in instances.
7. **Mesh route.**
   - Uploads: `UploadFailed` (results_v2 id 321) and possible moderation.
   - Runtime bake: per-server time and EditableMesh memory (§5.4).
   - Templates adopted at runtime can leak (CLAUDE.md:450).
8. **Streaming.** Pump and flume containers on distant clients (L2AC/L2SL scans); large floors.
9. **Lobby interactions in Studio.**
   - RA pulls **every** server player into Level 2 and parks only the old lobby (RA:381-403).
   - The new lobby stays loaded (RUI:358-361).
   - A missing progression guard leaks a preview win into a Level 3 Continue and a `FirstClearLevel2` badge.
10. **Lighting.** Realistic style + fewer lights + PBR roughness may read darker. L2LC owns the grade only while `Level2LightingOwnedByController` is set (L2LC:37-47, 75-128).
11. **Unknowns needing Studio:**
    - the R4 Level 2 bay coordinates;
    - MaterialVariant tint (Part.Color) and UV scale on MeshParts in this place;
    - server EditableMesh headroom during a Level 2 round;
    - the exact swim threshold for depths > 2;
    - whether a typical seed really sits near 52k or 56k.
12. **Budget and approval loop.** Meshy credits (30 each), Codex image-model availability (`gpt-6.1-sol` was rejected once).

---

## 8. OPEN QUESTIONS FOR THE OWNER

(Identical to the section 8 at the top of this reply.)