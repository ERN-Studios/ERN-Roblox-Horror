# Level 2 water slides: collision contract and a Blender replacement design

Everything below comes from the working tree, read-only. Studio was not touched and no files were written.

**Abbreviations**
- WB = `ServerScriptService/Level 2 Systems/Level 2 World Builder.ModuleScript.lua`
- L2SL = `StarterPlayer/StarterPlayerScripts/Level 2 Slide Controller.LocalScript.lua`
- SRS = `…/Level 2 Slide Ragdoll Service.Script.lua`
- TS = `…/Level 2 Exit Transition Test Suite.ModuleScript.lua`
- OC = `…/Level 2 Objective Controller.ModuleScript.lua`
- CFG = `…/Level 2 Configuration.ModuleScript.lua`
- LG = `…/Level 2 Layout Generator.ModuleScript.lua`
- PFN / PSN / PSC = the Pool Foam Navigator, Pool Slide Navigator and Pool Slide Controller modules in the same folder
- KS = `artifacts/level2-blender-20261002/KIT_SPEC.md`
- kit.py = `tools/level2_blender/kit.py`

## 0. New findings and corrections to the prior notes

1. **The exit flume carries 271 PathfindingModifiers nobody counted.** The roof pass adds a `PathfindingModifier` and `NoEntityGround` to every part whose name contains "Ceiling" (WB:6318-6329). Every `… Collision Ceiling NNN` matches, so that is 271 extra instances. A replacement whose piece names avoid "Ceiling" drops them for free. KS rule 5 already forbids that word.
2. **The plunge does not depend on `hall.MaxX`.**
   - `plungeEnd = (Bounds.MaxX+60+41, 4, deckZ)` and `plungeStart = plungeEnd − (120, 0, 0)` (WB:3274-3275).
   - Only segment 1 depends on `hall.MaxX`. It is the level lead-in from `(hall.MaxX−14, 83.3, deckZ)` to x = 681, so its length is `695 − hall.MaxX`, between 25 and 75. LG keeps `hall.MaxX` between 620 and 670 (LG:257-260, 369-377; Bounds.MaxX = 700).
   - The exit's Y values are absolute: `plungeEnd.Y = 4`, and `startPoint.Y = deckY + 9.3 = 83.3`.
3. **The exit's collision depends on a visual asset.**
   - `slideTemplate(false)` needs `ServerStorage."Level 2 Slide Assets"."Level 2 Slide Templates"."Level 2 Slide Closed Segment"` (WB:2291-2300).
   - If that asset is missing, the exit falls back to legacy panels (WB:2497-2503). Those have no "Collision Floor" names and a different cross-section, so TS fails.
   - The same coupling exists for the hall helix: its collision count is `smoothedSlideSegmentCount(30)`, which is 48 with the open template and 30 without (WB:2327-2331, 2674).
4. **The closed exit tube has two open 1-stud slots at its upper corners.**
   - The ceiling covers |x| ≤ 0.775r (WB:2578-2580). The side walls start at |x| = 0.9r and stop at y = +0.9r (WB:2566-2567, 2569-2575).
   - That leaves a 0.125r slot (1.0 stud at r = 8) running the whole length, from the bore up past the ceiling.
   - A replacement that is "exactly as today" reproduces the slot. Closing it is an owner decision.
5. **Navigation reads slide collision through bounding boxes.**
   - Pool Foam and Pool Slide body tests use `workspace:GetPartBoundsInBox` (PFN:589-600, PSN:684). Any CanCollide hit that is not EntityGround blocks them (PFN:139-142, 567-570).
   - That query uses each part's bounding box, not its collision geometry. So the size of each collision instance's box matters, and this rules out "one big MeshPart per tube" inside halls.

## 1. Inventory of tubes today

| Tube | Call | r | Visual chords | Collision chords | Guard wall full / outlet | Tub |
|---|---|---|---|---|---|---|
| Hall flume ×3 per slide hall | WB:3068-3072 | 7.5 (CFG:131) | 106 (=⌊66×1.6+.5⌋) | **40** Bezier, uniform t=k/40 | 14 / 8.625 | yes |
| Hall helix (if R ≥ 12) | WB:3121-3125, 2671-2700 | 4.6 | 120 | **48**, 2.1 turns, 15.75° each | 14 / 5.29 | yes |
| Exit flume | WB:3334-3335 | 8, closed, one-way | 271 | **271** (same polyline as the visual) | closed, 14.4 | yes (WB:3428) |
| Slide kit chute | WB:5170-5173 | 2.6 | 38 | 10 | 4.94 / 2.99 | yes |
| Play tower | WB:5432-5439 | 4.2 | 51 | 12 | 8 / 4.83 | yes |
| Kids slide | WB:3924-3931 | 1.8 / 2.7 / 3.5 / 4.1 | 26–45 | 10 | 1.9r / 1.15r | no |

## A. The contract a replacement must satisfy

### A1. Geometry of one collision segment (WB:2513-2582)

Each segment spans consecutive collision points a → b. Its points come from `collisionPoints`, or from the visual points when that list is nil.

- **Frame:** `base = CFrame.lookAt((a+b)/2, b, Vector3.yAxis)`. There is no bank or roll; local up is world Y projected (WB:2518).
- **Length:** `L = |b−a| + 1.5`. `SlideCollisionOverlap` is 1.5 (CFG:148), so every piece extends 0.75 past both ends of its chord.
- **Thickness:** `t = 0.6`, or ×1.5 = **0.9 on the exit** (WB:2508, CFG:141).
- **Pieces:**

| Piece | Name suffix | Local offset | Size |
|---|---|---|---|
| Floor | `Collision Floor NNN` | (0, −0.9r − t/2, 0) | (1.55r, t, L) |
| Chamfer ×2 | `Collision Chamfer LNNN` / `RNNN` (no space) | base·Angles(0,0,∓π/4) then (0, −0.9r − t/2, 0) | (0.8r, t, L) |
| Walls ×2 | `Collision Left NNN` / `Right NNN` | x = ±(0.9r + t/2). Open: y = −0.9r + h/2. Closed: y = 0 | (t, h, L) |
| Ceiling (closed only) | `Collision Ceiling NNN` | (0, +0.9r + t/2, 0) | (1.55r, t, L) |

- **Open-tube wall height:** `h = 1.15r + (full − 1.15r)·clamp((n−i)/2, 0, 1)`, where `full = max(safetyWallHeight or 14, 1.15r)` (WB:2557-2564). The last segment gets the outlet height, the one before it the midpoint.
- **Closed-tube walls:** h = 1.8r (WB:2566).

**The resulting inner surface**
- The lower half of a regular octagon with apothem 0.9r:
  - a flat floor for |x| ≤ 0.3728r at y = −0.9r;
  - 45° faces up to (±0.9r, −0.3728r);
  - vertical walls at |x| = 0.9r.
- Closed tube: a flat ceiling at +0.9r, with square upper corners and the slot from §0.4.
- The bottom of the chamfer slab lies inside the floor box, and its top lies inside the wall box. So the union has no gaps at the bottom.

| Tube | Floor top below axis | Flat-bottom half-width | Wall inner (outer) | Wall top above axis |
|---|---|---|---|---|
| Flume 7.5 | 6.75 | 2.80 | ±6.75 (7.35) | 7.25 (mid 4.56, outlet 1.88) |
| Hall helix 4.6 | 4.14 | 1.71 | ±4.14 | 9.86 |
| Exit 8 | 7.2 | 2.98 | ±7.2 (8.1) | ceiling 7.2–8.1, 12.4 wide |
| Kit 2.6 / Tower 4.2 / Kids r | 0.9r | 0.3728r | ±0.9r | 2.6 / 4.22 / r |

### A2. Physical properties (identical on every collision part)

- `Part`, Anchored, Transparency 1, CanCollide true, CanTouch false, CanQuery true, CastShadow false, SmoothPlastic, white (WB:2472-2482, part() WB:49-62).
- `CustomPhysicalProperties(density .7, friction .05, elasticity .05, frictionWeight 1, elasticityWeight 1)` (WB:2178-2182, CFG:144-145).
- CollisionGroup is Default (never set; KS rule 6).
- During a ride only the rider's **Head** collides. Every other part is set CanCollide false (L2SL:283-295, mirrored at SRS:428-431).
- The combined friction is therefore head material blended with .05 at weight 1 each. Keep these exact values or the slide speed changes.

### A3. Attributes

| Part | Attributes |
|---|---|
| Floor and both chamfers | `Level2_SlideCollision`, `Level2_SlideFloor = true`, `Level2_SlideDirection = (b−a).Unit`, `Level2_NoEntityGround = true` (WB:2524-2549) |
| Same, on one-way tubes only | `Level2_OneWayExit = true` when `dir.Y < −.01` (WB:2177, 2528, 2547) |
| Walls and ceiling | `Level2_SlideCollision` only (WB:2480) |
| Tube Model | `Level2_SmoothSlide`, `Level2_OpenTop`, `Level2_OneWayExit`, `Level2_CollisionWallThickness` (WB:2492-2509) |

- **Direction semantics.** The direction is the **chord** unit vector of that collision segment, constant across the piece. It is the same on the floor and both chamfers, not a tangent sampled at a point. For pieces built as `lookAt(mid, b, Y)` it equals `CFrame.LookVector`, which is exactly what both readers fall back to when the attribute is missing (L2SL:536-539, SRS:239-242).
- **Unused attributes.** No code outside WB reads `Level2_SlideCollision`, `SmoothSlide`, `OpenTop`, `ClosedTube`, `SlideVisual`, `SlideEndCap` or `SlideEntrySupport` (grep over ServerScriptService, StarterPlayer and ReplicatedStorage).

### A4. Detection: what the ray must hit

**Client** (`slideFloorUnder`, L2SL:524-541)
- One world-down ray from `root.Position + (0, .5, 0)`, length `HipHeight + root.Size.Y/2 + 4`.
- Raycast params: Exclude every player character (L2SL:505-522), IgnoreWater, RespectCanCollide (L2SL:37-40).
- **The first CanCollide + CanQuery hit must carry `Level2_SlideFloor`**, otherwise the result is nil, which counts as no contact.
- Any collidable decoration within reach above a slide surface hides the slide.

**Server** (`floorUnderPlayer`, SRS:198-252)
- Same ray but length +6, run on the server's (lagged) copy of the character.
- Additionally requires `floor:IsDescendantOf(Workspace."Level 2 Generated World")` (SRS:200-202, 224).

**Grade**
- `grade = −dir.Unit.Y`, the sine of the chord's descent angle.
- Start needs grade **≥ .20** on both client (L2SL:665-671) and server (SRS:250).
- Release is **< .12** (L2SL:694).

### A5. Ride behaviour the geometry must reproduce

- **Start** (L2SL:423-500):
  - impulse up to 30 studs/s (open) or 36 (exit) along the direction;
  - tumble angular velocity;
  - joints released;
  - PlatformStand plus the Physics state;
  - a world-space `VectorForce` = Direction × mass × 46 (open) or 58 (exit) (L2SL:339-356);
  - `Begin` sent to the server.
- **Active** (L2SL:690-739):
  - the direction blends toward each hit's direction with α = 1 − e^(−13·dt);
  - above the soft cap of 88 (open) or 105 (exit), acceleration becomes `max(−g, drive − 5·(v − cap))`;
  - OneWay is sticky: it stays true once any hit carries the flag (L2SL:693).
- **Ending:**
  - no contact for more than .30 s → COASTING (L2SL:715-722);
  - grade under .12: open tubes coast after .24 s; one-way tubes enter RUNOUT_BRAKING (215 studs/s²);
  - the exit transition ignores both (L2SL:694-722).
  - COASTING or RUNOUT finishes once grounded for .15 s, using `supportedUnder` (normal.Y ≥ .6, length +5, L2SL:543-549), with speed ≤ 32 or 40. The cap is 2.5 s (L2SL:741-799).
- **Teleport guard:** a jump of more than 20 studs in one frame ends the ride, except during the exit transition (L2SL:648-662).
- **Server watchdog:** 30 s maximum, except during the exit transition (SRS:452-476).

### A6. Exit-specific contract (WB:3228-3649, OC, TS)

- **Path:**
  - points 1–2: level lead-in;
  - points 3–74: plunge, 72 Bezier samples with c1 = plungeStart + (24, −2, 0) and c2 = plungeEnd + (−34, 7.3028, 0);
  - points 75–92: transfer, 18 steps of 13.889 horizontal and −2.917 vertical;
  - points 93–272: helix, R 96, 3 turns, 6° steps, centre `(plungeEnd.X+250, −48.5, deckZ−96)`, entered at angle π/2 with the angle **decreasing** (travel +X at entry).
  - Total 272 points and 271 segments (WB:3283-3328).
- **`TransitionLength`** is summed from **hard-coded index 74** (WB:3390). It is about 255.5 + 1848.2 = **2103.7**, against the OC minimum of 2000 (OC:104, 323-327). That is only **about 104 studs of margin**.
- **End stop:** one Part, 2 × 18 × 18, at `TransitionEnd + axis·0.5`. CanCollide true, CanQuery false, attribute `Level2_ExitTransitionEndStop`, inside FlumeModel (WB:3363-3388).
- **Completion sensors:** 9 × 18 × 18 at `pathAtX(plungeEnd.X−26)` and `(−6)`. Transparency 1, no collide, query or touch, attributes `Level2_ExitCompletionBeam` and `…SensorThickness = 9` (WB:3570-3607). OC arms CanTouch (OC:486-488) and sweeps root segments as a backup (OC:708-763). `pathAtX` assumes x rises monotonically through the plunge.
- **Recycle attributes on the flume Model** (WB:3348-3356): RecycleActive, TriggerY **−301.84**, DeltaY **126.669**, HelixCenterX/Z, HelixRadius 96, TopY **−48.5**, BottomY **−428.51**, FlumeBoreRadius 8.
  - **Client recycle:** when Y ≤ TriggerY and |horizontal distance from centre − 96| ≤ 12, lift by DeltaY and keep velocity (L2SL:582-614). The client finds the Model by scanning world descendants (L2SL:567-580).
  - **Server backstop:** at Y ≤ −365.17 within 14 (OC:823-840).
  - **Recovery:** triggers when more than 22 from PathPoints for 1.5 s, or under 2 studs per .25 s for 3 s. It places the rider at the **hard-coded landing angle π/2** with the tangent (R, −DeltaY/2π, 0)·unit at 70 studs/s (OC:780-847, 899-912).
  - So **the exit helix may be translated but not rotated** unless OC:805-813 changes.
  - **Periodicity:** segment k and segment k+60 must be the same shape shifted by DeltaY (60 per turn, starting exactly at the entry).
- **`Exit.Mouth`** is the visual apron. OC recolours it to `OPEN_COLOR` at Transparency .35 and publishes its position (OC:464-482). It must stay its own small MeshPart; otherwise the whole tube turns translucent green.
- **OC `validateManifest`** (OC:263-343) checks: the sensors; SafeSpawn under World; TransitionEnd; TransitionLength ≥ 2000; FlumeBoundsCenter and Size (padding r + 24); PathPoints ≥ 2; BoreRadius; a Recycle block with Turns ≥ 3.
- **TS structural checks:**
  - **Floors.** The Model is named exactly `Level 2 Exit Flume`. Its parts' names contain `Collision Floor` and are sorted by trailing digits (TS:57-80). The sensor floor is the floor centre nearest the Trigger (TS:82-92).
  - **Every floor from the sensor onward:** has a `SlideDirection`; is flagged OneWay; has grade **> .12**; and satisfies `centre distance − (SizeZ_i + SizeZ_{i+1})/2 ≤ 0`. In addition: the summed length / 105 is over 15 s; the declared length is within 35% of the measured length; the lowest floor `Position.Y` is above FPDH + 40 (−460); exactly one collidable end stop contains TransitionEnd (TS:155-276).
  - **Recycle.** PathPoints > 32; lifting each point by DeltaY lands within **.5** of another path point; BottomY > −460; backstop minus BottomY > 40 (TS:290-358).
  - **Recovery chamber.** At least 6 parts named "Recovery Chamber", and every floor centre more than 40 from SafeSpawn (TS:361-383).
  - **Probes.** The launch point is floor[start−16].Position + 3.2, which must ray-hit a SlideFloor within 24 and drift less than 12 (TS:561-590, 651-659).

### A7. Entry tubs (WB:2708-2919)

`makeEntryTub` is called with `collidableSupport = true` everywhere. No caller passes `forceEntryRide`, so **no tub is one-way**.

Collision per tub:
- **Entry floor** (WB:2734-2756): Part, width 1.55r, thickness 0.6 (**not** ×1.5 on the exit), length `entryLength + .75` with `entryLength = clamp(1.35r, 5.5, 10)`, top at `mouth.Y − 0.9r`. It carries SlideFloor, a **horizontal** SlideDirection and NoEntityGround.
- **Ground base** (WB:2774-2786): 2.15r × clamp(.065r, .28, .55) × (entryLength + .35). It is visible and collidable.
- **16 cradle bands** (WB:2857-2892): angles 157°→383°, radius r → 1.085r, length entryLength + .19. Each carries SlideCollision, SlideEntrySupport and NoEntityGround.

That is 18 collidable parts per tub. The rest of the tub (apron, edge cap, saddle and 6 handles) is visual.

### A8. Other readers

- Pool Foam and Pool Slide only treat `Level2_EntityGround` without `NoEntityGround` as ground (PFN:139-142, 538; PSN:144-147, 628). Slide collision is never steppable, so it blocks their body boxes, which are checked against bounding boxes (§0.5).
- PSC ignores riders in the exit transition (PSC:106-110).
- The Pool Slide hostile has no other relation to the water slides.
- `ForcedSliding` and `RagdollServerActive` are read by Crouch, NoiseReporter, RouteMarker and others. Those are character attributes and do not depend on geometry.
- No offline test covers water-slide collision. The `tools/tests` slide tests are about the Pool Slide hostile.

## B. Replacement designs

| | (i) **Per-segment convex-island MeshParts (recommended)** | (ii) Fewer, longer box strips | (iii) A few big MeshParts per tube, direction from the path | (iv-a) Merge collinear runs | (iv-b) (iii) for the exit only |
|---|---|---|---|---|---|
| Collision instances, typical live round* | **1,456** (open tubes 2 per segment, exit 1) or 886 with 1 per segment | ~3,950 | ~180 | −17 on any design | ~1,200 |
| Same for the KIT prefab set** | **1,306** (802 with 1 per segment) | ~3,500 | ~120 | −17 | ~1,050 |
| Code changes | **None.** Only the builder's `addCollisionSegment` changes (WB:2513-2582), or it is replaced by the prefab placer | None | L2SL:524-541, SRS:236-250, TS:57-92 / 155-276 / 375-381 / 633-659 / 769-791 | None | Same as (iii), exit branch only |
| Matches today exactly? | Yes: same chords, same convex pieces, same attributes | No: chords change, so floor heights against the visual and direction sampling change. WB:3330-3333 records that coarser exit-helix collision opened holes | Direction sampling changes; one-way must be tracked per chord | Yes (collinear transfer boxes) | Exit only |
| Main risks | Fidelity of the convex decomposition; CollisionFidelity must be set when the template is created; templates leaking into ServerStorage (CLAUDE.md rule) | Visible sinking or floating, seams, recycle periodicity | Decomposition of curved chunks (hull budget undocumented, bumps at hull joins); **bounding-box navigation false blocks** (PFN:593, PSN:684); huge colliders streaming out (memory note) | — | Decomposition and streaming (no navigation exposure: the exit is outside the map) |

\* 9 flumes, 2 hall helices, the exit, 22 tubs, about 8 kits, 2 towers and 1 kids slide. Today that is 4,873 collision parts plus the 271 PathfindingModifiers.
\*\* 3 × (3 flumes + 1 helix) + exit + 13 tubs. Today that is 4,381 + 271.

**Recommendation: (i).**

**Per collision segment, keep today's chord, CFrame (`lookAt(mid, b, Y)` × a template axis offset), length L and attributes, and replace the 5–6 Parts with:**
- **Open tubes: 2 MeshParts.**
  - *Floor* piece: floor plus both chamfers. Carries SlideFloor, SlideDirection and NoEntityGround.
  - *Guard* piece: both walls, with no slide attributes.
  - Why two and not one: with a single piece, a player standing on a reachable guard-wall top would get a SlideFloor hit and be ragdolled. Reachable tops: kit chute outlets about 3.7 above the pool floor; the hall-helix outlet about 6.4; kids slides. Today the walls carry no SlideFloor, so this does not happen.
  - The 1-per-segment variant (886 / 802) is an owner trade-off: it saves about 500 more instances and accepts that edge case.
- **Closed exit: 1 MeshPart** per segment (floor, chamfers, walls and ceiling), named `Level 2 Exit Flume Collision Floor NNN`. The exterior cannot be reached, so carrying the attributes on all of it is exact. It must not contain "Ceiling".
- **Tubs: 2 instances.** The entry floor stays a Part with its attributes; one cradle MeshPart holds the 16 bands plus the base as islands.

**How to author the pieces:**
- **Each convex box as its own closed shell (islands), never as one concave U.**
  - Clip each chamfer slab to y ≥ −0.9r and |x| ≤ 0.9r so the islands do not overlap. The rider-facing surface is unchanged. Arithmetic confirms that, for every r and t listed above, the clipped-away bits lie inside the floor and wall boxes.
  - The decomposition then has nothing to approximate: one hull per island.
- **Set `CollisionFidelity = PreciseConvexDecomposition` when the template is created.**
  - Use the `CreateMeshPartAsync` options, the same pattern WB:2238-2241 already uses with Box, or set it on a saved template.
  - Clone the template and set only Size.Z = L. Scaling a prism along its length keeps the hulls exact.
  - The guard piece may also scale in Y to the wall height, because its walls always start at −0.9r.
- **About 17 tiny template meshes** are needed: 2 per open radius, the exit ring, and the cradles. Each is 72 triangles or fewer.
- **Bounding boxes:** each piece's box is about the same as the union of today's strip boxes, so the navigation queries behave as today.

**Verification**
- *Offline:*
  - port WB:2513-2582 to Python;
  - assert that the island vertices equal today's box corners (to 1e-3) for every radius and wall height;
  - assert directions, names and counts;
  - re-run the TS structural asserts on the exported exit data (grades, overlap, length, periodicity < .5, FPDH margins).
- *Studio (gated):*
  - Studio Settings › Physics › "Show Decomposition Geometry": one hull per island;
  - A/B rides on a pinned seed (speed trace and time-to-outlet within ±5%);
  - a ray grid inside each bore: the first hit is SlideFloor with the right direction;
  - TS `ValidateExitGeometry`, `ProbeHighSpeedCompletion`, and `ProbeTransitionRideDuration(…, true)` with `Level2_ExitRecoveryCount = 0`;
  - Pool Foam pathing beside the flume outlets;
  - `Level2_WorldDescendants`.
- *Arithmetic already checked for TS with exit ring pieces:*
  - piece centres sit on the axis, so the lowest is −428.5, above −460;
  - the overlap check still holds because Size.Z = L;
  - `settleAt` places the rider 3.2 above the axis, inside a bore that reaches +7.2.

**Optional later saving:** (iv-b), chunking the exit only, cuts about 250 more instances but needs the client, server and TS edits listed above. Not needed for KS §8: (i) lands at about 1,345 including visuals and Models, under the ≤ 1,500 budget.

## C. What Blender must export per slide

Use kit.py conventions: studs, Roblox axes x right, y up, z back, Blender = Roblox (x, −z, y) (kit.py:1-7). Limits per mesh: ≤ 20k triangles, ≤ 60k vertices, ≤ 1800-stud extent (kit.py:259).

Extend the manifest with two sections.

**`slideProfiles[key]`**
- `islands`: a list of convex 2D polygons in the cross-section plane, extruded as unit-length closed shells.
- `axisOffsetY`: the bounding-box centre relative to the tube axis.
- `kind`: Floor, Guard, Ring or Cradle.
- `r`, `t`, and for Guard a `unitHeight` (bottom at −0.9r).
- The chunk id.

**`slides[name]`**, one per tube, in prefab-local coordinates:
- `model`: today's names, e.g. `Level 2 Slide Hall {i} Flume {s}` and, required, `Level 2 Exit Flume`.
- `kind` (open or closed), `r`, `t`, `overlap` (1.5), `oneWay`, `guard: {full, outlet}`.
- `collisionPoints`: n+1 points, today's exact formulas (§D).
- `segments[]` for the checker only: `{i, len, dir, oneWay, guardHeight}`.
- `visualPoints`, and the visual chunk ids. The visual inner radius should be 0.9r, the octagon's inscribed circle, so collision never pokes into view.
- `tub: {mouth, toward, deckTop, r, entryLength, profile}`, with `mouthComponent` kept separate on the exit.
- For the exit:
  - `anchor = plungeStart`;
  - `leadIn` as a stretchable segment (`from` is hall-local `(MaxX−14, 83.3, deckZ)`);
  - `pathPoints` (all 272);
  - `plungeEndIndex = 74`;
  - the sensor offsets (−26 and −6 from plungeEnd.X);
  - the end-stop frame;
  - `recycle {TopY, DeltaY, Turns, Radius, startAngle = π/2, cw = true}`.

**At runtime the placer should:**
- clone the template per segment with `CFrame = prefabCF · lookAt(mid, b, Y) · (0, axisOffsetY, 0)` and `Size.Z = len`;
- **then set `SlideDirection = piece.CFrame.LookVector`**, which stays correct after a yaw rotation (saved attributes do not rotate with PivotTo);
- set OneWay from the record;
- compute the recycle values in world space after placement.

Generate the points with one Python port of the WB formulas that both Blender and the checker use, so visual and collision cannot drift apart.

## D. Procedural dependencies a fixed prefab must freeze

The fixed prefab must freeze these inputs:
- **Hall size.** `hall.Width`, `Depth`, `Center`, `MinZ`, `MaxX` and `MaxZ` set the lanes, deck, flume control points and helix.
- **Skylights.** `dodgeSkylight` (WB:1467) can move or remove the columns and the helix.
- **Doors.** `nearDoorApproach` (WB:1494) and `nearHallNavigationRoute` (WB:1520) depend on per-round door positions.
- **Hall index.** It sets the slide colours (WB:3054, 3117).
- **Kits, towers and kids slides.** Per-hall RNG for `padTop` 4.5–8, `chuteRun` 12–18, tower top 10–14, yaw and origin (WB:5577-5614); kids slide mode by zone (WB:4148-4170).
- **Exit.** Lead-in length `695 − hall.MaxX`, the wall-collar x, and `deckZ`.

**Fixed values today:**
- deckY = H − 22: 54 for a slide hall, 74 for the grand hall (CFG:91-92, WB:3031).
- deckDepth = 46 (since D ≥ 165).
- Pool depth 1.8, so p3.Y = 6.1.
- laneStep = 34 whenever W ≥ 189.
- Helix: top = deckY + 5.75, bottom 3.4, 2.1 turns, start angle π/2 with the angle increasing.
- Exit block: §A6. It translates only by deckZ (Bounds.MaxX = 700).

**KS prefabs, hall-local (origin at the hall centre, floor at y = 0), assuming no skylight dodge:**

| | SlideHall 208×176 (H 76) | GrandSlideHall 224×208 (H 96) |
|---|---|---|
| deckZ / deckFront | −63.25 / −40.25 | −79.25 / −56.25 |
| Flume lanes x | −34, 0, 34 | −34, 0, 34 |
| p0 / p1 | (x, 62.65, −39.25) / (x, 62.65, −26.25) | (x, 82.65, −55.25) / (x, 82.65, −42.25) |
| p2 / p3 | (x, 15, 10.56) / (x, 6.1, 45.76) | (x, 15, 12.48) / (x, 6.1, 54.08) |
| Helix | column (62.4, 0), R 15.4, top 59.75, grade ≈ .27 | column (67.2, 0), R 16, top 79.75, grade ≈ .34 |
| Exit | — | mouth (98, 83.3, −79.25); wall gap 18.5² at y 83.3; lead-in 25 if MaxX is 670 |

## Open owner decisions

1. 2 pieces per open segment (exact, 1,306) or 1 per segment (802, accepts the wall-top ragdoll edge case)?
2. Reproduce the exit's 1-stud upper-corner slots, or close them with upper chamfers?
3. Keep the decorative slide kits, play towers and kids slides? They are outside KS §5.
4. May prefabs rotate? If yes, OC:805-813 assumes the exit helix's entry angle and must change; hall slides are fine via the LookVector rule.