# What the Pool Foam hostile needs from the Level 2 world, and what a Blender modular-kit rebuild would break

Pool Foam finds its way using Roblox pathfinding first, with a fallback route built from the layout's hall and corridor data. Every route is then re-checked against a box shaped like the creature's body, using raycasts and overlap queries. The world has to provide four things:
- **Floor parts** that collide and carry the attribute `Level2_EntityGround`.
- **Wall parts** that collide and are queryable.
- **A rectangle-and-corridor layout table.**
- **The `Level 2 Entity Nodes` folder** of spawn and patrol nodes.

Two findings shape the whole rebuild:
- **Any colliding mesh is treated as its whole bounding box.** One large colliding MeshPart therefore reads as a solid wall across that whole box.
- **Line-of-sight checks ignore `CanCollide` and use only `CanQuery`.** What the players see, what the server sees and what the creature can walk through can drift apart.

The Pool Slide is **not** retired: the Round Adapter still loads and starts it, and its config has `Enabled = true`. Section 9 covers it.

File key, all under `G:\Roblox\MongoTV\ServerScriptService\Level 2 Systems\` unless noted:
- **Nav** = Level 2 Pool Foam Navigator.ModuleScript.lua
- **Ctl** = Level 2 Pool Foam Controller.ModuleScript.lua
- **Obs** = Level 2 Pool Foam Observer.ModuleScript.lua
- **PF** = Level 2 Pool Foam Proxy Factory.ModuleScript.lua
- **AA** = Level 2 Pool Foam Animation Adapter.ModuleScript.lua
- **FCfg** = Level 2 Pool Foam Configuration.ModuleScript.lua
- **RM** = README - LEVEL 2 POOL FOAM.ModuleScript.lua
- **WB** = Level 2 World Builder.ModuleScript.lua
- **LG** = Level 2 Layout Generator.ModuleScript.lua
- **RA** = Level 2 Round Adapter.ModuleScript.lua
- **L2Cfg** = Level 2 Configuration.ModuleScript.lua
- **OC** = Level 2 Objective Controller.ModuleScript.lua
- **PSC** = Level 2 Pool Slide Controller.ModuleScript.lua
- **PSN** = Level 2 Pool Slide Navigator.ModuleScript.lua
- **NR** = `ServerScriptService\NoiseRegistry.ModuleScript.lua`

---

## 1. How navigation works

It is a hybrid of three layers. None of them use CollisionGroups or PathfindingLinks.

1. **Roblox pathfinding** (`PathfindingService`) comes first (Nav 1929-1939):
   - `CreatePath{AgentRadius = PathAgentRadius (2.2), AgentHeight = 6, AgentCanJump = false, AgentCanClimb = false, WaypointSpacing = 5, Costs = {Water = 1, Level2Roof = math.huge}}`, then `ComputeAsync(foot, goal)`.
   - If the result fails, it falls back to the graph route (Nav 1958-1960).
   - Path.Blocked does not throw the route away. It only re-checks the segment currently being walked (Nav 1642-1672).
2. **A graph route built from the layout tables**, in `graphRoute` (Nav 233-314):
   - A breadth-first search over `hall.Connections`, refusing any `PressureDoor` corridor until `workspace.Level2ExitPowered` is true (Nav 227-231).
   - Each hall is crossed hub-and-spoke: hall centre → (centre, `Cross`) → corridor midpoint → (next centre, `Cross`) → next centre. `SharedWall` corridors skip the midpoint (Nav 295-310).
   - Every point uses the foam's current foot height (`fromPosition.Y`).
   - It is also used when the pathfinding route has unwalkable segments and the graph route is better (Nav 2014-2034).
   - If neither route works, it walks straight at the goal, but only if a raycast toward it is clear (Nav 1601-1609, 788-796).
3. **A body check that runs on every route.** `_centreRoute` (Nav 1303-1592) does the following:
   - Thins the points to at least 9 studs apart (Nav 864, 1329-1357).
   - Moves each point to somewhere the body can stand. Inside a corridor or its approach, the point is snapped unconditionally onto the corridor's `Cross` centre line (Nav 991-1023).
   - Adds a corridor-mouth entry point when the route enters a corridor (Nav 1400-1415).
   - Re-walks every segment exactly as the live walker would (`_walkingEdgeClear`, Nav 658-685).
   - Runs a bounded A* detour on an 8-stud grid, then a 4-stud grid, with a 64-stud margin, at most 1,800 expanded nodes and an 18,000-query cap (Nav 880-894, 1087-1296).
   - The total budget is 72,000 queries, yielding every 600 (Nav 852, 856).
   - Only the first `PlanHorizon` 96 studs are checked, and the next piece is requested when 48 studs remain (FCfg 182-183, Nav 1730-1743, 1772-1775).

**Walking** (Nav 2294-2586) moves in pieces of at most `MaxTravelStep` 0.9 studs (the default at Nav 26; FCfg does not set it), with at most 12 pieces per call (Nav 54). Each piece is a full `_placeFoot`, which:
- **Finds the floor** with `_surfaceAt` (Nav 515-561). It casts down from foot + `FloorProbeAbove` 12, `FloorProbeDepth` 80 deep, and passes through up to 16 hits. A hit only counts if all of these hold:
  - the part has `CanCollide`;
  - the surface normal's Y is at least 0.57;
  - the part has `Level2_EntityGround == true`;
  - the part does not have `Level2_NoEntityGround == true`;
  - the height change is at most `MaxStepHeight` 3.5.
  
  While walking it takes the **highest** valid surface (Nav 547-554). When warping it takes the surface nearest the requested height.
- **Checks the body volume** with `_bodyBoxClear` (Nav 589-601). It calls `GetPartBoundsInBox` on an axis-aligned box of 4.2 × 5.7 × 4.2 (from AgentRadius 2.2 and AgentHeight 6.0 in FCfg 170-171, sized at Nav 576-581). The box spans foot +0.18 to foot +5.88 (Nav 592).
  - Any hit with `CanCollide` blocks movement unless `_isSteppable` passes.
  - `_isSteppable` requires `Level2_EntityGround` and the part's **world bounding-box top** (`partTopY`) at or below foot + 3.55 (Nav 130-137, 567-570).
- **Sweeps the box** with `Blockcast` from the previous foot (Nav 605-643). The box bottom is at max(fromY, toY) + 0.18. Steppable hits are excluded and the cast repeated, at most 6 times (`SWEEP_EXCLUSION_BUDGET`, Nav 32). Running out of that budget counts as **blocked**.

**Recovery** when a piece fails (all in Nav):
- the steer ladder at 20°, 35° and 50°, which in corridors must not drift away from the centre line (2431-2477);
- a 45% shorter step (2478);
- up to 8 clearance sidesteps (59, 2497-2504);
- up to 6 waypoint skips (63, 2519-2532);
- after 4 failed frames, retreat along the trail, up to 16 studs and 5 times (66-70, 2537-2581).

The controller's own stuck watchdog acts after 1.1 s without progress: first a forced repath, then a 3 s "unreachable" cooldown on that target, then a switch to patrol (FCfg 177-178, Ctl 1369-1416).

## 2. What it reads from the world (exact names)

**Manifest** (from `WB.Build`, WB 6334-6355):
- `World` must stay parented. Its attribute `Level2_Generation` must be nil or equal to the round's generation (Ctl 164-168).
- `Layout`.
- `EntityNodes`, the folder "Level 2 Entity Nodes" (WB 5935).
- `Navigation`, the folder "Level 2 Navigation" (WB 5934). The navigator also finds it by name, recursively (Nav 357).

**Layout tables** (LG 139-179, 294-315):

| Table | Fields used |
|---|---|
| `Halls[i]` | `Index`, `Id` (string, e.g. "Level 2 Hall 07"), `MinX`, `MaxX`, `MinZ`, `MaxZ` (axis-aligned rectangle), `Center` (Vector3; rebuilt from the rectangle if missing, Nav 173-180), `Connections` (hall indices) |
| `Corridors[i]` | `A`, `B`, `Axis` ("X", anything else is treated as Z), `Cross` (centre line), `From`, `To` (span along the axis), `Width` (defaults to 34, Nav 916), `Kind` ("Open", "SharedWall" or "PressureDoor") |
| `CorridorByPair["min:max"]` | lookup from a hall pair to its corridor; falls back to a linear search (Nav 210-225) |
| `KidsArea` | hall tables or indices (Ctl 201-216) |
| `Seed` | random number seed (Ctl 2054) |

**Attributes on parts** (read on the hit part itself, so a Model-level attribute does not count):

| Attribute or name | Effect |
|---|---|
| `Level2_EntityGround = true` | Floor or step. Required for every walkable surface (Nav 139-142, 381, 537). WB sets it on hall, corridor and kids floors, ledges, curbs, stairs, spiral treads, decks, thresholds and the column-flare collision rings (WB 367, 382, 389, 1335, 1952, 1996, 4675, 4729, 4776, 4787, …). |
| `Level2_NoEntityGround = true` | Overrides EntityGround: never a floor and never steppable. Set on slide and flume collision (WB 2209, 2527, 2546, 2750, 2785, 2848, 2889) and on roofs. |
| `Level2_BuoyantProp = true` | Left out of every navigator query (Nav 365-367), but **not** out of sight lines. |
| Name containing "Ceiling", "Skylight" or "Roof" | WB adds `Level2_NoEntityGround` and a `PathfindingModifier` with Label "Level2Roof" and `PassThrough = false` (WB 6318-6331). This is a **name-based** contract. |
| Entity nodes | `Level2_HallId` (hall `Id` string or number), `Level2_PoolFoamSpawn = true` (Ctl 234-254) |

**Workspace attributes:**
- `SelectedLevel == 2` and `RoundActive == true` (Ctl 170-174)
- `Level2Pumps` and `Level2PumpGoal`, which drive the phase (Ctl 641-646)
- `Level2ExitPowered`
- `EntityPaused`
- `TestLevel2PoolFoamEnabled` (Studio only, Ctl 1997-1998)

**What the navigator leaves out of its queries** (Nav 349-375, 506-513): its own model, EntityNodes, the Navigation folder, the runtime folder (so the foams cannot see each other), every buoyant prop, and every player character.

The ground list is a snapshot taken when the navigator is created. The navigator is built in `createEntity` at `Controller.Start` and on a template swap (Ctl 535-537, 1449). Floors added or streamed in later are invisible to it. Each navigator does two full `World:GetDescendants()` passes (Nav 365, 378), so five entities mean ten whole-world walks at start.

## 3. Query filters

| Query | API | Filter | Ignores `CanCollide = false`? | Ignores water? |
|---|---|---|---|---|
| Floor probe | Raycast with an **Include** list of ground parts (Exclude list if there are none) | Nav 386-393, 532 | yes | yes |
| Body box | `GetPartBoundsInBox`, MaxParts 64; bounding boxes only, not mesh geometry | Nav 369-375, 593 | yes | n/a |
| Body sweep | `Blockcast` (real collision geometry) | Nav 343-348, 616-636 | yes | yes |
| Direct-line fallback | Raycast | Nav 788-796 | yes | yes |
| Player sight (Observer) | Raycast excluding the observer's character, EntityNodes and Navigation | Obs 193-203, 334-342 | **no** (only `CanQuery`) | yes |
| Kill and proximity-latch sight | Raycast from foam pivot +1.8, excluding its own model, EntityNodes and Navigation | Ctl 764-785 | **no** | yes |

None of these set `CollisionGroup`, so all of them use the default group ("Default").

## 4. Sight rules that depend on walls and ceilings (Obs)

- **Client reports.** The client sends at most 8 per second (RM 38-48). The server accepts one per 0.10 s, valid for 0.85 s (FCfg 58-60).
  - The camera must be within 8 studs of the head (FCfg 67; Obs 315, 364).
  - It must point within 60° of the root's facing (FCfg 68; Obs 157-165).
  - Field of view must be 35-100°, and each viewport axis 64-16,384 (Obs 299-314).
  - Otherwise the server uses the **head's** view, with a 72° field of view at 16:9 (FCfg 70 → Obs 224-225, 380-387).
- **Sample points.** Five points on the model's bounding box (Obs 123-133): the centre; centre + min(0.42·Y, 5) up; 0.55 of that down; and ± min(0.35·X, 3.5) along its right axis.
- **Visibility test.** A sample is seen when it is inside the view frustum, within 180 studs (FCfg 61), and a raycast reaches it with nothing in between, or the ray hits the foam model itself (Obs 136-146, 173-179). Water is ignored (Obs 203). **Any part with `CanQuery = true` blocks**, collidable or not.
- **Hold and effect.** A short loss of sight is held for 0.24 s (FCfg 72; Ctl 1069-1073). While seen:
  - the foam freezes and its animation pauses, and its speed ramp resets (Ctl 1084-1092, 1284-1290);
  - the first real sighting latches the chase (`TriggerChaseOnObserve`, Ctl 1093-1099).
- **Kills** require the latched chase, a phase that allows attacks (Pressure or Finale), distance ≤ 5.5 from the foam's foot to the player's HumanoidRootPart, measured in 3D (FCfg 167; Ctl 863-886), and a clear kill sight line (Ctl 886).
- **Unused config keys.** These are never read: `RequireServerLineOfSight`, `ServerLineOfSightInterval`, `AcquireSeconds`, `NearThreatDistance`, `RevealOverrunCooldown`, `WaypointTolerance`, `SearchSeconds`, `RetreatSeconds`. Sight checks are always on.

## 5. Proximity latch (Ctl 992-1058, FCfg 111-115)

This is a server-side backstop for the chase latch. It only fires when all of these hold:
- the entity is active, not Dormant and not already chasing;
- a player who is eligible (some pump started, or the player is inside a Kids hall rectangle) stays within **8 studs, measured in 3D**;
- that player's flat speed is at most **3 studs/s**;
- the kill sight line from Section 3 is clear;
- all of the above for **7 s**, with the current candidate keeping the timer.

It only ever adds a latch. Its only dependency on the world is that sight line.

## 6. Spawn rules

- **One clone per KidsArea hall.** `KidsAreaRoomCount` is 5 (L2Cfg 86). IDs run `Primary_01`…`Primary_05` in hall-index order (Ctl 2095-2112).
- **Spawn node choice** (Ctl 279-312):
  - Only nodes in EntityNodes whose `Level2_HallId` is a Kids hall are used. Nodes with `Level2_PoolFoamSpawn` are preferred.
  - The list is sorted by name. The first node at least `SpawnGap` 9 studs from earlier spawns wins (FCfg 276); otherwise the roomiest; otherwise hall centre + 2.
- **What WB provides:**
  - "Level 2 Pool Foam Spawn <i>" at the centre of an 8×8 pocket with 4-stud spacing, +2 up. It has `CanQuery`, `CanCollide` and `CanTouch` all false (WB 4081-4084, 6018-6028).
  - Patrol nodes "Level 2 Entity Patrol Node <i>.<k>" at hall centre ± 0.32 of width/depth, floor +2 (WB 6185-6198).
  - Patrol and noise-investigation targets are **Kids-hall nodes only** (Ctl 1131-1178).
- **Placement check:** `WarpTo(spawn, nil, allowLargeStep = true)` needs a ground surface between +12 and −68 studs and a clear body box (Ctl 538).
- **Failure kills the whole round build.** The chain is: `CreateError` (Ctl 538-542, 2104-2108) → `RA` raises because `Enabled = true` (RA 413-418) → `Adapter.Build` cleans up → `WORLD_ERROR` (RA 453-458).
- **Phases** (FCfg 286-312; Ctl 639-671):
  - Dormant until 15 s or the first pump.
  - Foreshadow: stalks and latches, cannot kill.
  - Pressure at 2 pumps: kills allowed.
  - Finale once all pumps are done or `Level2ExitPowered` is true: speed ×1.12.
  - Before the first pump, only players inside the Kids hall **rectangles** are valid targets (Ctl 218-232, 843-848).

## 7. Hearing (NoiseRegistry)

- **Loading and lifetime.** Ctl loads NR from the ServerScriptService root (Ctl 17-37). Sounds decay after 5 s. The list is pruned every tick (Ctl 1914) and cleared on Stop (Ctl 2156).
- **Range.** `GetBest(foot, 120)` scales the range by loudness (FCfg 138; NR 6-23, 59-72): sprint 1.0 gives 120 studs, walk 0.45 gives 54, pump 2.0 gives 240. It is **straight-line distance with no occlusion**, so walls and room geometry are irrelevant.
- **Sources.**
  - Players: `Remotes.ReportNoise` with "walk" or "sprint". Speed must be ≥ 2, or ≥ 12 for sprint. The server rate-limits each player to one report per 0.15 s and uses the player's root position (Ctl 1958-1987).
  - Pumps: OC adds "pump" at `pump.Model:GetPivot()` every 2 s while the motor clip plays (OC 55, 598-608).
- **Effect.** Hearing only steers:
  - Target choice: a player within 35 studs of the noise has their distance weighted ×0.55 (FCfg 145-150; Ctl 834-857).
  - Patrol: the foam walks to the Kids node nearest the noise (Ctl 1147-1158).

## 8. What would break

### (a) The world built from large MeshParts with invisible box colliders

1. **A colliding MeshPart becomes a wall across its whole bounding box.** `GetPartBoundsInBox` tests the box, not the mesh (Nav 593).
   - Unless the part is `EntityGround` with its box top at or below foot + 3.55, it blocks.
   - A room shell or floor mesh that includes walls or a hill blocks every placement inside it. The spawn then fails, which errors the round (Section 6).
   - WB already documents this for the arch-rib mesh pilot (WB 1802-1810). Its fix is the pattern the kit should copy: a visual mesh with `CanCollide = false`, plus invisible Part "Arch Rib Foot" colliders (WB 1811-1832, `ARCH_MESH_FOOT_SEGMENTS = 4` at WB 1650).
2. **Floor colliders must be ready before the encounter starts.** They need `Level2_EntityGround = true` and `CanCollide = true`, and must sit under `manifest.World` before `Controller.Start`, because of the snapshot (Nav 377-393).
   - Terrain cannot be ground, because the attribute check fails on it (Nav 537).
   - Missing ground means NO_FLOOR at spawn, which errors the round.
3. **Visual meshes left with `CanQuery = true` still block sight**, even when `CanCollide = false`, and they block using their collision fidelity (Section 4).
   - With `CollisionFidelity = Box`, a doorway or arch mesh would block sight and the kill raycast across its whole box.
   - The foam then moves while players are looking at it, and spots in its line become kill-proof.
4. **Roof colliders need a matching name.** Name them with "Ceiling", "Skylight" or "Roof", or add the `Level2Roof` modifier and `Level2_NoEntityGround` yourself. WB applies both purely by name (WB 6323-6331).
5. **Collision groups.** Colliders placed in a group that does not collide with "Default" become invisible to every query in Section 3.
6. **Gains.** Fewer instances make the ten start-of-round world walks and the pathfinding navmesh cheaper. Box colliders slightly larger than the visuals are harmless for walking (they are just conservative), but they do block sight.

### (b) Slopes and height changes

1. **The tightest limit is the body box.** Its bottom sits only 0.18 above the foot (Nav 592).
   - On any slope steeper than about 4.9° (atan(0.18 / 2.1)), the uphill floor enters the 4.2-wide box. It then has to pass `_isSteppable`: `EntityGround` and **bounding-box top** at most foot + 3.55.
   - The sweep hits the same rule (Nav 624).
   - A single long ramp, hill or floor mesh therefore reads as a wall from its lower part.
   - **Fix:** split slope colliders so each piece rises no more than about 3 studs across its own footprint.
2. **Pieces cannot be too small either.** One 0.9-stud sweep may pass at most 6 steppable pieces (Nav 32, 618-642). A finely split hill fails closed. Keep pieces roughly 4 studs or more across.
3. **Steepness limits.** A floor normal Y below 0.57 (steeper than about 55°) is not floor (Nav 536). Each 0.9-stud piece may rise or drop at most 3.5 (Nav 539).
4. **Overhangs get climbed.** Walking takes the highest floor within 3.5 (Nav 547-554), so a low overhang or bridge within 3.5 studs above the floor gets climbed onto.
5. **Graph routes are flat.** Every graph point carries the foam's current foot height (Nav 296-310). Floor resolution searches from point +12 down to −68 (Nav 516, 528, 980).
   - A room more than **12 studs higher** than where the foam stands cannot be resolved on the graph route: points are "Unresolved" and the route is unwalkable.
   - Pathfinding routes carry the real height and are unaffected.
6. **Kill and stop distances are 3D,** from the foam's **foot** to the player's root, which sits about 3 studs above the ground on a default rig (Ctl 849, 884, 1307).
   - A player standing more than about 2.5 studs above the foam's foot cannot be killed even when directly on top of it.
   - The 8-stud proximity-latch radius is 3D too.
7. **More repaths.** A goal height change of 3.5 or more forces a new path request (Nav 1778), so hilly chases cost more pathfinding calls.
8. **Spawn and patrol nodes** must stay about 2 studs above a ground collider, within that +12 / −68 window.

### (c) Shorter tunnels, or plain doorways instead

1. **Every room-to-room link still needs a corridor record** in the layout table: `Axis`, `Cross`, `From`, `To`, `Width`, `Kind`, plus `CorridorByPair` and two-way `Connections`.
   - Without it the graph search fails and only pathfinding remains.
   - A plain doorway should use `Kind = "SharedWall"` (no midpoint), with `Cross` at the door's centre (Nav 299, 305; LG 495-517 is the existing kids-wing merge).
2. **The centring code assumes straight, axis-aligned strips.**
   - Points within [From, To] ± 11 and Cross ± (Width/2 + 2) are **always** snapped onto `Cross` (Nav 909-932, 1013-1023, 1231-1234, 1400-1415, 2255-2262).
   - The steer ladder may not drift away from that centre line (Nav 2446-2470).
   - Angled, curved or off-centre openings, or a wrong `Width` (default 34), snap points into walls and make routes unwalkable.
3. **Thresholds need floor.** A doorway through a 3.5-stud wall (L2Cfg 97) needs a ground collider across the wall's thickness. Today that is the "Level 2 Shared Doorway Threshold" (WB 4664-4676) or the corridor floor running 2 studs into each hall (WB 4689). Otherwise the foam hits NO_FLOOR in the doorway.
4. **Clearance.** Pool Foam needs openings of at least about 4.2 wide and 5.9 tall, and a 2.2 pathfinding radius. The Pool Slide's roughly 14.8-stud body is what actually limits openings (PSC 38). Current doors are 30 × 30 (L2Cfg 98-99).
5. **Keep the hub-and-spoke lanes clear of props:**
   - halls: ±16-17 studs along both centre axes and each door spoke (WB 1514-1549, 1569-1571);
   - kids rooms: a 24-wide hub and spokes, plus 32 × 38 door approaches (WB 4023-4067).
   
   Otherwise every route falls back on the A* detours and their query budgets.
6. **Pressure doors.** Corridors into the Grand Slide Hall must stay `Kind = "PressureDoor"` (LG 552-557). The door Part must collide until OC 440 opens it.
7. **Rooms must be rectangles.** Hall location and the kids-area check use the hall rectangles (Nav 182-208; Ctl 218-232). Rooms that are not rectangles need a rectangle covering their walkable floor.
8. **Tunnel length does not matter** to Pool Foam. Removing ribs and vaults only removes obstacles.

### (d) Visual meshes with `CanQuery` and `CanCollide` set to false

1. **Walking is unaffected.** Every navigator query ignores non-colliding parts, and the floor list requires `CanCollide`.
2. **Sight and kill raycasts then stop only at colliders** (plus any decoration left queryable):
   - **A visible wall with no collider:** the server sees through it. Foams freeze and latch their chase through walls (Ctl 1093-1099), and kills can pass through it.
   - **A collider that covers a visible opening** (a box over an arch, glass, railings or grates): the server treats the view as blocked. The foam walks while being watched, and kills there are blocked.
   
   Collider outlines around openings must match what the player sees.
3. **Water.** `IgnoreWater` only covers Terrain water. A water-plane part must have `CanQuery = false`, or it hides the foam's lower sample point.
4. **The foam model itself** follows the README contract: visuals not queryable, root queryable (PF 99-106, 108-131; RM 94-96).
   - The final rig is about 5.2 × 3.8 (WB 4079), but the navigator's body box stays 4.2 because it is not measured from the rig.
   - Doorways tuned to 4.2 will show the art clipping into walls.

## 9. The Pool Slide is still live

- **It is wired in and enabled.**
  - The Round Adapter loads it (RA 17-18) and stops it (RA 258).
  - It starts it when `Enabled` is true (RA 425-445). Its config has `Enabled = true` (Level 2 Pool Slide Configuration line 4).
  - The sync manifest lists it as synced.
  - Clients and other scripts still read it: NoiseReporter (83, 96), Level 2 Entity Audio, ZyntraDetectorSensing (6) and DeathAdvice (76).
- **CLAUDE.md is out of date** where it says "exactly one hostile".
- **It uses the same world contract** through a copy of the navigator (PSN 145-146, 221-235, 346-376, 2124-2127):
  - `EntityGround` and `NoEntityGround`, buoyant props;
  - a folder named exactly "Level 2 Navigation";
  - the Level2Roof cost;
  - the Corridors and Halls tables.
- **It also needs:**
  - Spawn anchors found by part name: "Level 2 Entity Den *", "Level 2 Entity Patrol Node *" and "Level 2 Navigation Node *" (PSC 209-226).
  - At least 100 studs from every player, preferring anchors hidden from them (PSC 26, 238-263).
  - `manifest.World` must be a Model (PSC 811).
  - The template attributes `Level2_PoolSlideRigVerified` and **`Level2_PoolSlideCorridorFitVerified`** (PSC 267-270). The second one certifies the rig against the **current** corridors, so a new kit means measuring the fit again.
- **Its larger body (PSC 38-41) sets the minimum doorway and tunnel size,** not Pool Foam's 4.2.

## 10. Minimum rules for a kit to keep Pool Foam working

1. All walls and floors as plain, invisible Part colliders with `CanCollide = true`, in the default collision group. Visual meshes set to `CanCollide`, `CanQuery` and `CanTouch` false.
2. Every walkable collider tagged `Level2_EntityGround`, under `World`, before `Controller.Start`.
3. Slopes split into pieces of about 4 or more studs that each rise no more than about 3.
4. Room floors within 12 studs of their neighbours, or graph points given real heights (a code change).
5. Roof colliders named "Ceiling", "Skylight" or "Roof", or given the `Level2Roof` modifier.
6. Slide and flume colliders tagged `Level2_NoEntityGround`.
7. Layout `Halls` as rectangles, and `Corridors` / `CorridorByPair` with an accurate `Cross` and `Width` at each opening, using `SharedWall` for doorways.
8. A threshold ground collider in every doorway.
9. Hub and spoke lanes kept clear of props.
10. The `Level 2 Entity Nodes` folder with a `Level2_PoolFoamSpawn` node and patrol nodes in every Kids room, each standable for a 4.2 × 5.7 box.
11. Collider outlines that match what players can see through, for the sight rules.

**For the lobby preview:** `Controller.Start` is only called from `RA.Build`, and the foam stays frozen unless `RoundActive` is true and `SelectedLevel == 2`. A map preview will therefore have no foam.