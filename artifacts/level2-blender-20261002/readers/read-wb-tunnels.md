# Level 2 World Builder: tunnels, doorways, doors and decor (read-only analysis)

**What the numbers say:**
- **The two tunnel mouths are most of every tunnel.** A standard tunnel (mesh ribs on, culling on) is 472–499 instances. 378 of those come from the two mouths: 32 spandrel slats, 1 header and a 30-segment face ring per end, plus their Textures.
- **Measured check of my per-rib arithmetic.** The arch-mesh pilot measurement saved 15,770 instances and 12,948 Textures (C:173-178). Dividing gives exactly 166 rib rings at 95 instances and 78 Textures saved per ring.
- **The rectangular tunnel shell can never be seen.** The two corridor walls and the corridor ceiling sit entirely behind the barrel vault and the mouth caps. They only serve as a collision backstop and a sealed void.
- **A colliding tunnel mesh will block Pool Foam.** The navigator's body test uses `GetPartBoundsInBox` with `RespectCanCollide`, which tests bounding boxes. Any colliding mesh whose box covers the tunnel interior reads as a wall. Kit visual meshes must be `CanCollide=false`, with collision built from box parts.

Abbreviations: **WB** = `ServerScriptService/Level 2 Systems/Level 2 World Builder.ModuleScript.lua`; **C** = `…/Level 2 Configuration.ModuleScript.lua`; **LG** = `…/Level 2 Layout Generator.ModuleScript.lua`; **OC** = `…/Level 2 Objective Controller.ModuleScript.lua`; **NAV** = `…/Level 2 Pool Foam Navigator.ModuleScript.lua`.

Primitive defaults: `part()` (WB:49-62) never sets CanCollide/CanTouch/CanQuery/CastShadow, so every part it makes collides, can be touched and is queryable unless the caller changes it. `tiledPart` (WB:92-96) adds one Texture "Level 2 Tile Texture" (asset 113211706146395, tint 248,242,218) per face. When the face list is nil that means all 6 faces (WB:64-76). `visibleFaces()` passes a face list through only while `Performance.CullHiddenTileFaces=true`, which it currently is (WB:84-90, C:164).

---

## 1. How rooms are joined

**The graph (LG):**
- A corridor is created for every pair of halls that face each other along one axis with a span overlap of at least `CorridorWidth+8` = 42 (LG:126-137) and a gap of at most `MaximumCorridorLength` 130 (LG:319-327, C:63). There is no pruning pass after this.
- Each corridor record carries `Axis` (X or Z), `Cross` (centre of the overlap, which is also the doorway centre), `From`/`To` (the two facing hall rect lines), `Width`=34, `Kind`="Open", `Length` and `Index` (LG:147-172).
- The gap is at least 60 (2 × `HallMargin` 30 plus up to 14 of jitter per side, LG:271-290, C:37-38) and at most 130.

**Four kinds of connection:**

| Kind | Built as | Where decided |
|---|---|---|
| `Open` | Full arch tunnel (`makeCorridor`, WB:4653-4970) | LG:155 |
| `PressureDoor` | Arch tunnel plus a pressure door. Applies to every corridor touching `GrandSlideHall` | LG:549-558 |
| `DrainGroup` = pump index | An `Open` tunnel at depth 1.8 instead of 1.5, with `PoolType` "Deep". The nearest drainable corridor (Length ≥ 40, not kids) per pump | LG:578-599, C:115-118, WB:4694-4695 |
| `SharedWall` | Kids hall pairs extended wall-to-wall (gap 3.5). Just a doorway through a 7-stud double wall plus 2 threshold slabs | LG:495-518, WB:4654-4682 |

- **Doorways are punched for every corridor, including SharedWall**, into both halls' walls (`doorsByHall`, WB:5940-5957). Hall walls are built at WB:6204-6218 with `makeWallWithGaps` (WB:228-343).
- **Every doorway opening is 30 wide × 30 tall** (`DoorWidth`/`DoorHeight`, C:98-99) in a 3.5-thick wall (C:97), whatever the corridor's width of 34.

## 2. Anatomy of a standard tunnel segment

The figures below use `alongX` as the example. `G` = gap length, `d` = 1.5 (or 1.8 for DrainGroup) (WB:4684-4695).

Fixed dimensions:
- Width 34, `CorridorHeight` 32, vault vertical scale 1.9 (C:57, 94, 96).
- Rib radius 13.2 = min(34·.5−3, 30·.5−1.8) (WB:4823).
- Vault radius 14.1 = min(13.2+1.4, 15−.9) (WB:4839).

| Element (Name) | Count / size / position | Textures (cull on) | Collide/Touch/Query | Role | Visible? |
|---|---|---|---|---|---|
| `Level 2 Corridor Water Floor` | 1 slab (G+4)×1.2×34, top at y=−d (WB:4725-4729) | 1 (Top) | C/T/Q; `Level2_EntityGround` | collision + nav ground | Top visible through water; outer ~3 studs each side (outside the vault feet at ±13.96) hidden |
| Corridor steps | Only if d>2.5 (WB:4733-4743) | n/a | n/a | n/a | **Never built**: the max depth is 1.8 |
| `Level 2 Corridor Side Ledge <i>` | 1 slab; cross band 9.1..15.4 on side +1 if Index is even, else −1; top `WALKWAY_TOP` .45, bottom −d−.3; length G+3.5, running to both halls' inner wall faces (WB:4754-4776) | 5 | C/T/Q; EntityGround | walk surface | Outer 13.3..15.4 band sits inside or behind the vault; the outer long face is 0.15 inside the corridor wall |
| `Level 2 Corridor Side Ledge Curb <i>` | 1; cross 7.9..9.1, top −.8, height d−.5 (WB:4777-4788) | 5 | C/T/Q; EntityGround | step-up | Submerged, visible |
| `Level 2 Corridor Wall` | 2; centred at cross ±17, 3.5 thick, y −d−3..34, length G+3.26, ends 0.12 inside the hall walls (WB:4794-4813) | 1 (inside face) | C/T/Q | backstop | **Never visible** (see §7) |
| `Level 2 Corridor Ceiling` | 1; y 32..34, 34 wide, length G+3.26 (WB:4814-4817). The final pass adds a `PathfindingModifier` labelled "Level2Roof" and sets `Level2_NoEntityGround` (WB:6323-6331) | 1 (Bottom) | C/T/Q | backstop | **Never visible** |
| `Level 2 Arch Rib <i.r>`, mesh path | R rings, R = clamp(floor((G+4)/22),3,7), so 3..6 because G≤130. Evenly spaced at t=i/(R+1) (WB:4820-4837). One MeshPart cloned from ServerStorage `Level 2 Arch Rib Mesh <key>`, CanCollide=false (WB:1794-1814). Key `r13.20_vs1.90_fd1.50|1.80_a3.20_d2.20_s26` (WB:1635-1638, 6393-6398); assets 121489049526127 and 105818906248010 (C:173-174) | baked UV | no collide | visual only | Soffit and axial faces visible; extrados buried 1 stud in the vault |
| `Level 2 Arch Rib Foot <i.r>` | 8 per rib (4 per side), invisible Transparency 1, CastShadow false, attribute `Level2_ArchRibFoot`, floor up to about 10.3 studs (WB:1646-1650, 1815-1832) | 0 | **C/T/Q** (Touch left at the default true) | collision at the rib feet | invisible |
| `Level 2 Arch Rib <i.r>`, Part path (kids corridors, or a missing template) | 26 Parts per ring (steps=max(14,ceil(13.2·1.9))), each 3.2×2.2×(chord+.9), feet dipping to y=−2.7 (WB:1778-1866) | 3 (Left, Right, Bottom); kids: 2 | C/T/Q | visual + collision | Same faces as the mesh path |
| `Level 2 Vault Strip <i>` | 21 strips (max(12,floor(14.1·1.5))), each (chord+.9)×1.6×(G+2.8), forming a closed elliptical half-cylinder whose feet reach y=−2.7 at cross ±13.96 (WB:1873-1911, 4839-4843) | 1 (Bottom/inner); kids: 2 | **C/T/Q** (default) | visible tunnel surface + collision + occluder | Inner face visible, outer face never |
| `Level 2 Corridor Arch Header <i>` | 2 (one per mouth); y 27.31..30.15, 30.3 wide, depth 3.38 inside the 3.5 hall wall (WB:4850-4890) | 2 | none | mouth infill | Hall-side face visible (0.06 recessed); tunnel-side face hidden |
| `Level 2 Corridor Arch Spandrel <i>` | **32 per mouth = 64**; slats .947(+.07) wide filling between the 30×30 doorway rectangle and the arch curve (r 13.847·1.9), bottom at −d−2.2; the outer 2 run full height (WB:4866-4913) | 2 each | none | mouth infill (occluder) | Hall side visible, tunnel side hidden |
| Portal face ring (`Arch Rib <i>.face±1`) | 2 rings × 30 segments; radius 14.1, radial 1.4, axial .6, 0.04 proud into the hall (WB:4915-4927) | 2 each (Left, Right) | none | trim hiding the slat stair-steps | Hall-facing face only; the tunnel face is buried in the vault end |
| `Level 2 Corridor Vault Light <i>` | 2 at ±.25(G+4), y 24.59; invisible Neon 1.2×.4×1.2 plus a `PointLight` (Brightness .7, Range 26, Shadows) (WB:4932-4946) | 0 | none | light; also a **sound anchor** (§9) | Emitter invisible (no lamp fixture exists) |
| Water | Terrain `FillBlock` (G+3)×(d+.1)×35.5, top at .1 (WB:4949-4953) | n/a | n/a | gameplay (drained by OC:345-349) | n/a |
| `Level 2 Pressure Door <i>` + `… Stripe <i>` | PressureDoor kind only (§4) | 0 | door C/T/Q; stripe no collide | gameplay | visible |

**Per-corridor instance count, standard corridor, mesh ribs:**

floor 2 + ledge 6 + curb 6 + walls 4 + ceiling 3 (including the modifier) + vault 42 + mouths 2×(3+32×3)=198 + face rings 2×30×3=180 + lights 4 + ribs 9R = **445 + 9R → 472–499**, plus 2 for a pressure door.
- With Part ribs: 445 + 104R = 757–1069.
- Kids corridors always use Part ribs (WB:1794 requires `not styleHall`).
- The world records `Level2_CorridorCount` (WB:6300) and the rib readbacks `Level2_ArchRibMeshEnabled/Ribs/MissingKeys` (WB:6236-6246).

**SharedWall connector:** 2 × `Level 2 Shared Doorway Threshold` (4.7×.7×29.6, Top kids texture, EntityGround, the two halves overlapping by 0.2 at the wall line) (WB:4663-4681), plus each hall's doorway pieces.

## 3. Doorway pieces in the hall walls (`makeWallWithGaps`, WB:228-343)

- **Wall slab heights:** from `bottomY` = −depth−4 (WB:6212) to `height+1.85`, so the top is buried 1.85 in the 2-stud ceiling slab (WB:236).
- **Wall slab ends:** they run 2.6 past the room corners (WB:296-297).
- **Wall slab faces:** the room face, plus a jamb end where a slab ends at an opening (WB:280-290).
- **`… Lintel`:** opening span × (wallTop−30), all 6 faces textured (faces nil, WB:312-314). That is 5.85 tall for 34-high halls, 47.85 for slide halls (76) and 67.85 for the grand hall (96).
- **`… Sill`:** span × (|bottomY|−4) at y bottomY..−4, all 6 faces textured (WB:318-321). It is built at every door in a hall with water (all water halls, pump halls at depth 1.2, kids halls at 0.8).
- **Exit-flume opening** in the grand hall east wall: `HallWallGap`, 18.5×18.5 centred at y 83.3 (WB:3642-3647). Its `… Sill` and `… Header` are textured on 6 faces (WB:323-333).
- **`Level 2 Exit Flume Wall Collar 1.0..31`:** 32 untextured, non-colliding blocks, an annulus from r 8.1 to 15.25 around the tube where it crosses that wall, tagged `Level2_ExitWallCollar` (WB:3489-3525).

## 4. Doors

**Pressure door** (WB:4955-4967):
- `Level 2 Pressure Door <i>`: 2.2×36×34, y −4..32, DiamondPlate, `C.Locked`, CanCollide, `Level2_CorridorIndex`. It sits at the corridor's **`To` end**, the higher-coordinate hall's rect line, whichever side the grand hall is on (WB:4957, LG:164-171).
- It is wider (34) and taller than the 30×30 opening, so its edges are buried in the jambs and lintel.
- `… Stripe <i>`: 2.4×1.2×30 Neon at y 18, no collision.
- **Opening** (OC:404-462):
  - Fires once the final pump's clip completes (OC:626-631).
  - Sets `Level2ExitPowered` and `Level2FoamLethal`.
  - Door CanCollide goes false, then it tweens up by Size.Y+6 = 42 over 3.4 s, then Transparency=1. It stays parked at y 38..74 forever, an invisible dead part.
  - The stripe recolours and rides up with it.
  - The `DoorPositions` are sent to the sound cue.

**Exit "door":**
- The exit flume entry apron (`Mouth`, WB:3428-3429) is recoloured to `OPEN_COLOR` at Transparency .35 (OC:464-468).
- The flume itself is closed tube built from 272 path points: 271 visual MeshParts plus 6 hidden collision parts per segment (≈1,626) (WB:3274-3335, 2513-2581).
- End stop and two invisible completion sensors: WB:3363-3388 and 3570-3607.

**Story-only doors:**
- `Level 2 Exit Room Wooden Door`: 12×14×1.2 WoodPlanks, collidable, `Level2_StoryDoor`, plus 3 `… Door Frame` pieces, inside the sealed recovery chamber (WB:3527-3551).
- `Level 2 Energy Transfer Gate` at Arrival: 16 parts, all non-colliding with `Level2_StoryOnly`, plus 6 PointLights and 2 SurfaceGuis ("ANOMALOUS SPACE HAS BEEN LOST" / "ENTRY LOCKED") (WB:5755-5820).
- Compatibility `Elevator` model (shell/DoorL/DoorR invisible) plus the markers `MazeStart`/`ElevatorSpawn`/`EntityStart` (WB:5840-5885). These are gameplay contracts.

**There are no door frames on corridor doorways.** The only "frame" is the portal face ring.

## 5. How tunnel length and shape are decided

- **Always straight.** Axis-aligned X or Z; no bends, no slopes, no height change (WB:4691-4705).
- **Length.** The gap G = distance between the two facing hall rect lines, between 60 and 130. The floor runs G+4, the vault G+2.8, the shell G+3.26, the ledge G+3.5, and the water G+3 (WB:4689, 4765, 4797, 4841, 4951).
- **Cross-section.** Fixed for every corridor; only the floor depth (1.5 or 1.8) and the kids skin vary (WB:4709, 4717-4722).
- **Kids skin.** Used if either hall is kids; the tiles come from the `ReplicatedStorage."Level 2 Assets"` slots (WB:154-161). The mouths take the style of their own end hall (WB:4875-4877).
- **Rib count.** Varies only through R (WB:4820).
- **Light positions.** Fixed at ±25% of the length.
- **Everything walkable is at nominal Y≈0.** Water surface .1, walkways .45, door height 30. The water is axis-aligned `FillBlock` boxes (WB:349-354).
  - Sloped tunnels would need water that isn't a flat box.
  - Pool Foam's step limit is `MaxStepHeight` 3.5 (NAV:23). Steppability requires `Level2_EntityGround` (NAV:567-570).

## 6. Decor and props: per-instance counts

The Slide Ragdoll Service also adds **6 runtime Textures** to every part whose name starts with Lounger Seat/Back, Beach Ball, Pool Noodle, Pool Raft or Pool Float Ring (`Level 2 Slide Ragdoll Service.Script.lua:496-561`).

| Prop | Where (WB) | Instances each | Collision / gameplay |
|---|---|---|---|
| Lounger (Seat + Back) | dressHall 5032-5065; 1–3 per water hall (depth ≤2.2, not slide hall) | 2 Parts + 12 runtime Tex | seat collides; back doesn't |
| Beach ball | 5069-5081; clamp(Area/9000·density, 2, 10) | 1 + 6 | **unanchored, buoyant** density .16, `Level2_BuoyantProp` (excluded by NAV:366) |
| Pool noodle | 5082-5093; clamp(Area/8000, 3, 12) | 1 + 6 | buoyant .14 |
| Stopped clock | 5097-5112; 50% chance, south wall, 0.75 off the wall face | 3 | none |
| Float ring / raft | decorateLargeHall 5654-5676; clamp(Area/6500, 4, 12) | 1 + 6 | buoyant .28 / .24 |
| `makeRail` | 1913-1930 | bar + (max(2,floor(L/9))+1) posts, at least 4 | **all collide** (posts by default) |
| `makeStairFlight` | 1932-1955 | 4 per step (Part + 3 Tex) | collide, EntityGround |
| Slide kit | 5130-5174; clamp(Area/13000, 1, 4) | ≈182–202: pad 7, 4 legs, 9–14 steps, 4 rails, open tube = 38 MeshParts + 50 collision + cap + 3 containers, entry tub 27 | collision parts carry `Level2_SlideFloor`/`SlideDirection` |
| Diving tower | 5180-5237; first claim in halls with Area ≥15000 | ≈97 (3 boards), ≈118 (4 boards) | platform/ledges/boards collide but are **not** EntityGround |
| Play tower | 5412-5440; Area ≥26000 (2 if ≥52000) | ≈217–239 (tube 51 visual + 60 collision) | deck EntityGround; **no legs (floating deck)** |
| Overlook | 5617-5650; Area ≥28000 | ≈71 | landing EntityGround; no legs |
| Pool island + twin 4.5 columns | 5679-5700; Area ≥48000 | 7 + 2×14 | island collides, not EntityGround; **sits on the hall hub** (see §10) |
| Column (non-essential) | 1340-1460 | 14: shaft + 4 Tex, 2 flare MeshParts each carrying a SurfaceAppearance, 5 invisible collision cylinders (EntityGround) | Colonnades: clamp(long/38, 2, 8) per row × 1–3 rows (1552-1590, 6039-6052, 6096-6098) |
| Ring Corridor ring | 6053-6083 | 25 Parts × (1 + 4 Tex) = 125; 3–7 rings per hall | collide |
| Porthole panes | 6099-6125 | 3 × (Part + SurfaceLight) | none |
| Spiral stair well | 1971-2018, 6086-6095 | ≈264 (53 treads × 4, 23 posts, 22 guards, 7-instance newel) | treads EntityGround |
| Hall edge walkway | 5355-5408; 50% of non-pump water halls | 8 slabs × 6 = 48 | EntityGround |
| Pump room decor | 5242-5345 | ≈138: 7 overlapping walkway slabs × 6, 3–5 crates, gauge board + 3 gauges, 4 stripes, diving tower ≈85 | slabs EntityGround |
| Pump station (objective) | 4312-4647 | ≈77 (51 Parts, 6 Tex, PointLight, SurfaceGui + 4 labels, 9 welds, NumberValue, Prompt, 2 Models); scaled 0.34 | Prompt, lever, gauge, lamp all referenced by OC |
| Ceiling panel | 2119-2141; only in skylight-less halls (2143-2171) | 3 + 2 PathfindingModifiers (names contain "Ceiling") | frame collides |
| Slide-hall scale frame | 2924-2997; 3–9 per slide hall | beam + up to 2 piers | piers collide |
| Arrival scale frames | 5716-5743 | 3 × (2 piers + lintel) | piers collide |
| Kids ball pit, Full 34×30 | 3723-3795 | 7 structural + **≈594 Ball Parts** (371 base + ~50% + ~10% layers) | balls no collide |
| Other kids pieces | 3661-3941 | foam cluster 3; crawl frames 9; splash toys 6; raised pool 7; kids slide ≈100–125 | foam collides |

## 7. Geometry players can never see

| Geometry | Why it is hidden | Load-bearing? |
|---|---|---|
| `Corridor Wall` ×2, `Corridor Ceiling` per corridor (WB:4798-4817) | The vault outer surface reaches cross 14.9 and crown y≈28.6. The walls' inner face is at ±15.25 and the ceiling bottom at 32. The shell ends 0.12 inside the hall walls. Through the doorway, the mouth slats and header cover everything outside the arch. Its 3 Textures are wasted. | **Collision backstop and sealed void** behind 1.6-stud strips. The "Ceiling" name drives the `Level2Roof` cost (NAV:1936). Removable only if the replacement tunnel mesh is sealed and some invisible backstop remains. |
| Mouth slats + header, tunnel-side face (66 Tex per corridor) | The slat inner edge (r 13.847) sits inside the vault strip thickness (13.3..14.9). | The slats are **occlusion-load-bearing** from the hall side. Removing them shows the void between vault and wall. Not collision. |
| Face ring, tunnel-side face (60 Tex per corridor) | The ring spans 1.19..1.79 from the rect line; the vault reaches 1.4 → buried. | trim only |
| Hall-wall jamb end faces at corridor doorways (2 Tex per mouth) | Covered by the full-height outer slats, which reach 0.19 into the jamb (WB:4897-4898). | the jamb slab itself is collision and the shell |
| Lintel at corridor doorways: 5 of 6 Tex | Top buried in the ceiling; underside covered by the mouth header (0.15 overlap); tunnel side behind the vault/shell; ends in the jambs. | **yes**: shell above the door, and the pressure door slides through it |
| **`… Sill`** at every wet doorway (1 Part + 6 Tex; 2 per corridor) | y −depth−4..−4, at least 1.2 below the floor slabs | **no**: the floors above collide, and Terrain water ignores Parts |
| Wall bottoms −depth−4 (2.8 below the floor slab); wall tops +1.85 inside the ceiling; corner overhangs 2.6 outside the room | under the floor / inside another part / outside the shell | tops and overhangs are deliberate shadow-bias seals (WB:232-236, 292-297) |
| `Level 2 Exterior Light Seal 1-4` per hall (WB:858-890) | Above the ceiling plane and outside the walls; no collide/touch/query; CastShadow on | shadow-bias hack, unnecessary with a watertight room mesh |
| Corridor floor outer 3.04 per side; ledge outer 2.1 band; ledge outer long face | outside the vault or inside the wall | floor and ledge are collision + EntityGround: shrink, don't drop |
| Rib extrados; rib/vault feet below y=−1.5 | buried in the vault, floor or ledge | rib foot parts are the nav-tested collision |
| Parked pressure doors after opening (y 38..74, Transparency 1) | n/a | dead weight once open |
| Exit flume beyond the grand hall east wall (shellX = Bounds.MaxX+60, helix radius 96) | Seen only from inside a closed bore, yet every shell is `DoubleSided` (WB:2613-2615) | the collision is gameplay |
| Exit collar beyond the 18.5² gap | inside the wall slabs | visual |
| Pump `Lower Cap` (y 3.07..3.83) inside the plinth (0..5); housing/pipe bottoms inside the plinth (WB:4327-4365) | buried | no |
| Diving tower core top face (under the platform) and floor face | buried | the core collides |
| Stair step uphill (Front) faces, except the top step | covered by the next, taller step | the steps are EntityGround |
| Hall-edge-walkway E/W slab ends and curb ends | butt flush against the N/S strips | EntityGround |
| Pump walkway cross slabs overlapping the island and ring (WB:5272-5276) | coplanar duplicate tops (z-fighting) | EntityGround |

## 8. Merge and replace candidates for a Blender kit, by savings

1. **Tunnel mouth → one mesh per end.** Currently header + 32 slats + 30-segment ring = 63 Parts + 126 Textures = 189 instances. These pieces are non-colliding (WB:4882-4884, 4926), so a single `CanCollide=false` MeshPart is a drop-in. Best done by baking an arched opening into the "wall with door" module, which also absorbs the lintel, sill and jambs.
2. **Tunnel body → mesh bays plus box collision.** Vault 21 strips and R ribs become fixed-length bay meshes (one rib per bay), N=round(G/Lb), each scaled along the axis by ≤±10%. This keeps a near-uniform tile density, since scaled MeshPart UVs stretch where Textures don't.
   - Collision: floor, ledge and curb (EntityGround), 2 side boxes at the rib inner line (±12.1 at the floor), 1 roof box named "…Ceiling".
   - Do not make the vault mesh collidable (NAV:589-598 `GetPartBoundsInBox`, as the comment at WB:1802-1810 warns).
   - Result: about 12–15 instances per corridor instead of 472–499.
   - Precedent pipeline: `tools/level2_arch_rib_obj.py` exports the rib as OBJ with UV = studs/7.
3. **Kids ball pit (~594 Balls) → 1–3 meshes.**
4. **Ring Corridor rings (125 each) → the existing arch-rib mesh family.** Radius 13 needs its own key, with foot collision kept as in WB:1815-1832.
5. **Floating props.** Each is 1 Part + 6 runtime Tex (7 instances). A Meshy MeshPart + SurfaceAppearance is 2. Keep `Level2_BuoyantProp` and the name prefixes, or anchor them if physics bobbing is not wanted.
6. **Stairs, rails, towers, kits** become prefab meshes plus invisible collision. Stairs as one mesh plus per-step invisible boxes (EntityGround and the 3.5 step rule) or a wedge. Slide collision must keep the per-segment `Level2_SlideFloor`/`SlideDirection`/`OneWayExit` parts.
7. **Columns (14 → about 3):** one shaft+flare mesh, and keep the 5 EntityGround flare bands or an equivalent.
8. **Pump-room walkways (7 overlapping slabs) and hall edge walkways (8)** → one deck mesh plus collision boxes.
9. **Exit collar (32) → 1 mesh.** Exit flume visuals beyond the shell can be single-sided, inward-facing.

## 9. Contracts a rebuilt kit must keep

- **Layout corridor records** `{Axis, Cross, From, To, Width, Kind, DrainGroup, Index}`. These drive the navigator graph and centring: NAV:210-231, 909-955 (`CORRIDOR_APPROACH_REACH` 11 assumes the vault overhangs the corridor by about 1.4).
- **Manifest fields:**
  - `Corridors[i] = {Corridor, Water(CFrame, Size), Door, Stripe, Center}` (WB:4969)
  - `Drains[pump]` and `PressureDoors` (WB:6221-6232, 6338-6340)
  - OC drains with `FillBlock Air` over `record.Water` (OC:345-349)
  - The door must keep `.Position`, `.Size.Y`, CFrame-tweening and `CanCollide`.
- **Name and attribute hooks:**
  - The roof pass keys on "Ceiling", "Skylight" or "Roof" in the name, giving `Level2_NoEntityGround` plus `PathfindingModifier "Level2Roof"` (WB:6318-6331; NAV:1936 cost `math.huge`).
  - `Level2_EntityGround` on every walk surface.
  - Sound anchors: names starting `Level 2 Corridor Vault Light`, `Level 2 Navigation Node `, and the name `Level 2 Pump Intake Pipe` (`StarterPlayer/StarterPlayerScripts/Level 2 Sound Controller.LocalScript.lua:289-302`).
  - `freeWaterSpot` ignores names containing "Water Floor" (WB:4998).
- **Body clearance:** Pool Foam's body box is 4.2×5.7×4.2 (`Level 2 Pool Foam Configuration.ModuleScript.lua:170-171`; NAV:576-581).

## 10. Dead code and oddities

- **Corridor and doorway stairs are never built.** Both branches need depth >2.5 (WB:4733, 6140), but the maximum depth is 2.0 (C:111).
- **Pool island and its twin columns sit on the hall hub** at Center ±4 (WB:5688-5698). They never call `nearHallNavigationRoute`, which every other structure respects. The shafts leave a 3.5 gap, smaller than the 4.2 body.
- **Mesh rib feet keep CanTouch=true** (WB:1826-1830).
- **Play tower deck and overlook landing float without supports** (WB:5417-5421, 5639-5643).
- **The pressure door sits at the `To` end, not necessarily on the grand hall side** (WB:4957).