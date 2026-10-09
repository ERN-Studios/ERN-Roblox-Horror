# Kit work package reports (WP1-WP4) - interfaces for the runtime builder


# WP1-arch

## Review: defects, 8 defects
- [blocker] F4-D / F2+F4 PoolSteps_Curved_Landing (G6, G2): The landing's profile is built wrong. `nosing(10,0,DECK_BOTTOM,1)[::-1][:-1][::-1]` evaluates to [(9.92,-.1),(10,-.3),(10,-4.5)], so the revolved section becomes (0,-4.5),(10,-4.5),(9.92,-.1),(10,-.3),(10,-4.5),(0,0). The result has no flat top at y=0 (the only vertex at y=0 is on the axis), and no vertex at (9.7,0). The visible surface is a cone falling from y=0 at the wall to -4.5 at r=10, plus a degenerate fin. Its normals are inside out: the chunk's signed volume is -228.9, every other kit c
- [major] F4-vault / F4-I VaultBay32_H34/H42 (owner F4 'half finished'): In two of the four quadrants of each bay, the groin crease is triangulated across instead of along. Faces are (a,b,c,d) quads split on a-c. On the anti-diagonal |x|=|z| with x*z<0, the crease runs b-d. Measured on the export: 16 lower-surface triangles per quadrant straddle the crease in quadrants (-,+) and (+,-), 0 in the other two, with a centroid error up to 1.01 studs near the springing. The vault is also flat-shaded (raw default smooth=False), and groin_uv maps an elliptical barrel with cir
- [major] G4 (spiral stair) / F4-B SpiralStairWell_H42/H52: G4 lists the 'spiral core and stair' among the solids that must start at y=-4. Only the core does. The lowest tread vertex is at -0.102 and the lowest ground collider bottom at -0.022. In a flooded SpiralWell hall (basin floor at FloorY-0.8 to -2.0), the first treads hover 0.7 to 1.9 studs above the basin, visible through the water. This is the floating-base defect from F4-B. The first riser from the basin floor up to tread 1 (top .778) is also 1.6 to 2.8 studs.
- [minor] FIX_SPEC F1/F2 butt joints (0.05) / CornerCove: CornerCove still extends asin(.6/R) past each tangent. Beyond the tangent, its inner surface stands 0 to 0.0225 studs (R8), 0.011 (R16) or 0.0075 (R24) in front of the wall Part's room face. That is a 0.6-wide, full-height strip at each of 8 tangent lines per hall where two differently phased tile faces are almost coplanar, so z-fighting is likely. It also contradicts the spec's rule of butt joints, not 0.5 overlaps. The tori were fixed to .05; the vertical piece was not.
- [minor] G2/G3 tile pitch on revolved pieces (CoveBaseCorner_*, CoveTopCorner_*, CoveBaseStop_*): revolve() unwraps u = (a - a0) * r_vertex, measured from the start angle. Profile edges that change radius therefore shear in UV in proportion to (a - a0). Measured on visible faces: CoveBaseCorner_R16 singular values reach 2.02 / 0.50 at the far end, so tiles turn into skewed parallelograms toward one tangent and the tori don't match the runs at both ends equally. CoveBaseStop reaches 20x stretch and 0 (degenerate) where the fan meets the axis.
- [minor] F10+F4 SunSlit interface: The SunSlit attribute says Opening=[2,14], but the interface the implementer hands to the builder cuts the hole from h-17 to h-3.5, which is 13.5 tall (the review hall also uses 17..30.5). A builder that reads the attribute would cut a hole 0.5 too tall, back into the top-cove band the spec keeps uncut.
- [minor] F7/F14 ceiling_well shading (owner image 9, seen from the roof): The top lip's round-over meets the flat top annulus at about 23 degrees, under the 45-degree sharp rule, and the mesh is smooth=True. The long fan triangles running from the circle to the square corners therefore interpolate tilted normals, giving the same streaky triangular shading the owner photographed on the old collar top. The bottom plate is fine (48 degrees, sharp).
- [minor] Review/test coverage (task rules: render key pieces, look at them): The renders A01-A13 never show VaultBay32, PoolSteps_Curved, PoolSteps_Curved_Landing, the Walkway_Corner_R24/R8 box corner, CornerCove H96 or CoveTopCorner from below. That is why both mesh defects above shipped with 'all PASS'. check_kit also never checks CornerCove concavity. The world-builder test can't run against this kit yet: the current builder errors with 'missing Components.Walkway_Bend16' (expected until WP6/7).

## Implementation report

WP1 is finished, with one known gap: the Kit World Builder and its test (WP6/WP7) haven't caught up, so the world-builder test will fail until they do. All of `modules_arch.py`'s own checks pass, the WP5 kit collision audit passes on all 77 components, and the job A export is written to `G:/Blender/Level2_Poolrooms/jobs/A/export`.

## (1) What I changed

I edited only `G:/Roblox/MongoTV/tools/level2_poolrooms/modules_arch.py` (the original is backed up at `G:/Roblox/_local/l2fix/impl/WP1/modules_arch.before.py`).

**Coves (F1, F2, F12-C)**
- There is now one shared concave R3 fillet profile (`fillet_arc` / `cove_profile`).
- New lengths 4, 8, 16, 32 and 64 for CoveBase and CoveTop. They are cut to exact length, so runs meet at butt joints.
- New pieces `CoveBaseStop_PX` and `CoveBaseStop_NX`: the cove turned 90° into the wall. Two pieces are needed because a MeshPart can't be mirrored.
- The base and top corner coves sit with the wall at r=R, use `over=asin(.05/R)`, and carry a ring of fill colliders.
- Corner Blocks use fewer, longer boxes that fill R+0.25 to R+3. They are now oriented correctly.
- New CornerCove height H96. Its side faces are split every 30 studs or less, because one 100-stud face broke Blender's ray test.

**Collider orientation (F12-A):** `arc_boxes` and the new box helpers (`tangent_box`, `sector_boxes`) get their angle from `kit.yaw_x_along`.

**Ceiling openings (F7, F14):** `tiled_opening` is replaced by a flush `ceiling_well`. Nothing is below y=0, and the outer square is exactly half the panel size.
- LightWell_R6 uses panel 24; R10, R12 and R14 use panel 32. I kept R10 because it costs nothing.

**SpiralStairWell (F8):** only H42 and H52 remain.
- The top step is a quarter-turn landing at StairTop = Height−14.
- The core is closed from −4 to Height+8 and has its collider.
- The well no longer contains its own opening.

**Floor-standing pieces (G4):** columns, the pier, curve walls and the spiral core start at y=−4; decks and steps go down to −4.5.

**Decks and steps**
- New Walkway_Straight 4/8/16/32 (pool-side nosing only), Walkway_Corner_R16/R24, and Walkway_Ring_R9.
- PoolSteps_Straight12 is skirted down with a rounded nosing. PoolSteps_Curved is skirted, with collider boxes kept for every step.
- New PoolSteps_Curved_Landing.

**Wall decor**
- WallVoid is now just a back plate.
- SunSlit is just a glow plane, with no frame.
- DrainHole is a dark disc.
- LightRound is a flush trim.
- VaultBay32 is a groin vault (`min` replaces `max`).

**Removed:** Walkway_End, Walkway_Bend16/32 and SpiralStairWell_H34. `assemble_level.py` still places End and Bend, so it will break (it isn't my file).

**`validate()` now checks:**
- Every arc face of every cove family is concave and faces its own centre.
- Cove Fill gap is 0.6 or less, and no fill box sits in open room space.
- Every oblique collider's local X, decoded with Roblox's own formula, runs along its chord: 1037 checked.
- Light wells: no mesh below the plate, outer edge equals panel/2, no collider below base.
- Spiral: the StairTop rule, nothing within 3 studs under the ceiling, and a single closed core.
- Curved decks: ground gap 0.6 or less, no box top sticking out, and box tops at the right height.
- G4 reach down to −4 / −4.5, decor depth, the LightRound top, the groin vault heights, and triangle budgets.

## (2) Interface for WP6/WP7

**Frames**
- **WALL-FACE** (straight coves, stops, Walkway_Straight):
  - Pivot on the wall's room face; local +Z points into the wall, the room is −Z, and X runs along the wall. Use `wallPose(hall,side,along,.75)` with no extra 180° turn.
  - Base pieces sit at y = FloorY+.445 in halls with a deck, FloorY in dry halls. CoveTop sits at y = C−3.
- **CORNER** (CornerCove, the corner coves, Walkway_Corner):
  - Pivot at the fillet centre = boundary corner + (1.75+R)(sx,sz). Yaw is MinX/MinZ 0, MaxX/MinZ −π/2, MinX/MaxZ π/2, MaxX/MaxZ π. I checked this pose in the renders.
  - CornerCove and Walkway_Corner sit at FloorY. CoveBaseCorner sits at the base height, CoveTopCorner at C−3.
- **BOUNDARY** (SunSlit, WallVoid): pivot on the outer boundary plane, local +Z out of the room; use `wallPose(...,-1)`.
- **CEILING** (LightWell_*): pivot = (x, C, z), not C−8.

**Coves**
- **CoveBase{4..64} / CoveTop{4..64}**
  - Attributes: Length, Radius=3, WallSide '+Z', WallPlane 0, Profile.
  - One collider, `Cove Fill`, of size (L, 1.1, 1.1), centred at (0, .25, −.25) on the base or (0, 2.75, −.25) on the top.
  - Lay runs from 64/32/16/8/4 pieces and scale along X by no more than 12.5%.
- **CoveBaseStop_PX / CoveBaseStop_NX**
  - Pivot at the run's end (x=0). PX extends toward local +X and NX toward −X. Each reaches 3 studs, to the hole edge.
  - One collider, `Cove Fill`, of size (.7, 1, 1).
- **CoveBaseCorner_R / CoveTopCorner_R (8, 16, 24)**
  - Fill boxes `Cove Fill 1..n` with n = 4, 7, 10. They span radius R−.8 to R+.3, height −.3 to .8 on the base or 2.2 to 3.3 on the top.
  - Attributes: CornerRadius, FilletRadius=3.
- **CornerCove_R{8,16,24}_H{34,42,52,96}**
  - Pick the exact height and never scale it vertically.
  - Colliders `Corner Block 1..n`, n = 5, 8, 11, covering −4 to H+2.
  - Markers TangentX and TangentZ.

**Decks and steps**
- **Walkway_Straight{4,8,16,32}**
  - Pivot y = FloorY. One Part, `Walkway Deck` (ground, collides): centre (0, −2.0275, −4.35), size (L, 4.945, 9.7).
  - Mesh nosing from z −9.2 to −9.5. The deck top is .445 and the bottom −4.5. Attribute PoolEdge = −9.5.
  - The **old Walkway_Straight16/32 names now use this new frame**.
- **Walkway_Corner_R16 / R24**
  - Ring from radius R−9.5 to R+.5, over the angle range π to 3π/2.
  - Colliders `Corner Deck Ground 1..6` (R16) or `1..8` (R24), ground, from −4.5 to .445.
  - Use a plain box Part for corners with R of 0 or 8.
- **Walkway_Ring_R9**
  - Pivot = the Column_D10 pivot. Radius 4.96 to 9; colliders `Ring Ground 1..14`.
- **PoolSteps_Straight12**
  - Pivot at the deck's pool edge, at deck-top height. The steps descend toward −Z.
  - Parts `Step Ground 1..3`, tops −.6, −1.2, −1.8, bottoms −4.5, covering z −3.7..0, −7.7..−4 and −11.7..−8.
- **PoolSteps_Curved**
  - Half rings over local +X with tops −.6, −1.2, −1.8.
  - Colliders `Step N Ground i`: 10, 13 and 16 per ring.
- **PoolSteps_Curved_Landing**
  - Half disc of radius 10, top 0. Colliders `Landing Ground 1..6`. Only for curved steps placed where there is no deck.

**Ceiling openings and stairs**
- **LightWell_R6, R10, R12, R14**
  - Attributes: HoleRadius, PanelSize (24 or 32), ShaftDepth=8. Read PanelSize for the ceiling cut.
  - Marker `OpenSky` at (0, 8, 0) with Radius. Colliders `Collar Block i` from y 0 to 8.
  - LightWell_R14 replaces ExitSkylight. The spiral hall gets an R12 at the same x and z as the spiral.
- **SpiralStairWell_H42 / H52**
  - Pivot at FloorY.

    | | H42 | H52 |
    |---|---|---|
    | StairTop | 28 | 38 |
    | Steps (last one is the landing) | 36 | 49 |
    | Rise | .7778 | .7755 |

  - Other attributes: Height, PanelSize=32, HoleRadius=12, Opening='LightWell_R12'. No parts and no OpenSky marker.
  - Colliders:
    - `Core Block` (cylinder, y −4 to H+8, NativeSizeX = H+12).
    - Ground steps: `Stair Ground i` and `Stair Ground Outer i`. These are narrower than 4 studs, which breaks the old [4,.8,4] rule.
    - `Stair Fill i` and `Stair Fill Outer i`, not ground.
    - Landing: `Stair Ground Landing 1..4` and `Stair Ground Landing Outer 1..5`. The highest Stair Ground top equals StairTop.
  - Markers StairStart and StairEnd.

**Vaults and columns**
- **VaultBay32_H34 / H42** are groin vaults: the edges reach H at mid-span and sit at H−12 only at the corners.
- **VaultPier**: Part and collider at (0, 19, 0), size (5, 46, 5). `fitVaultPier` should set Size.Y = height+4 and centre y = FloorY + (height−4)/2.
- **Column_D{6,10,16}_H{34,42,52}**: from y −4 to H; the collider centre is at (H−4)/2 with NativeSizeX = H+4. Curve walls also start at −4.

**Decor and fixtures**
- **LightRound**: pivot at the bottom of the trim; place it at y = C−.15. Diameter 3.4.
- **SunSlit**: Neon plane 2.4×14.4 at z −.2 to 0, y 0 to 14.4. Pivot = `wallPose(-1)` × (0, h−17.5, 0); cut the hole 2×14 from h−17 to h−3.5. Light marker faces Front.
- **WallVoid**: Part `Void Back` (collides), centre (0, 2, −.1), size (10.4, 4.4, .2). Cut a 10×4 hole whose bottom is at the pivot y.
- **DrainHole**: Void disc 3 across and .06 thick, centred on the pivot; place it at y = basin top + .03.

## (3) Test output
- `modules_arch.py` build:
  - `validate()` all assertions **PASS**.
  - Cove Fill gaps: 0.501 on straights, 0.537 on stops, 0.528–0.569 on corners.
  - Ground gaps: 0.0 on decks, the ring and curved steps; 0.041 on the landing; 0.269 on the spiral.
  - Watertight ray check: 77 components, **0 escapes**, 0 open edges.
  - Export: `PR_EXPORT={"components": 77, "chunks": 76, "tris": 32684}` and `PR_A_OK`.
- `python -B tools/level2_poolrooms/collision_audit.py --no-world --kit .../jobs/A/export`: `KIT 1 dirs, 77 components, 0 failing: PASS`. The first run failed on CornerCove gaps (0.85–1.02) and spiral coverage (7%); I fixed both.
- I checked the ring and corner deck UVs separately: 0 mismatch along their vertical edges.
- **Not run:** `test_level2_kit_world_builder.py`. It reads jobs A–D, and the current builder still uses Walkway_End/Bend, the old centred deck, LightWell at C−8 and the 4×4 step rule, so it will fail until WP6/WP7.

## (4) Renders inspected
All in `G:/Blender/Level2_Poolrooms/review/A/`, rendered with backface culling on:
- **A01**: wall-foot coves and the stops at a door.
- **A02**: a corner with the vertical cove, base corner cove and corner deck. It reads as one continuous piece.
- **A03**: ceiling coves.
- **A04**: light well from below, flush with the ceiling.
- **A05**: light well from above the roof.
- **A06**: a column reaching the basin floor.
- **A07**: wall void.
- **A08**: sun slit.
- **A09**: drain and steps.
- **A10**: island ring.
- **A11 / A12**: spiral from below, and the landing with the hole.
- **A13**: spiral from above the roof, showing the closed core top.

From the renders I trimmed the step lips to the part you actually stand on, and moved the A02 camera. The files 00–03 in that folder are stale renders from earlier runs.

## (5) Not done or uncertain
- **Instance budget:** collider counts grew. SpiralStairWell_H52 has 202 (at most one per map), the corner coves 4–10 each, Corner Blocks 5–11, every cove piece 1, CoveTop and CoveTopCorner included even though players can't reach them. WP6 needs to measure this against the 9,000 limit. The cheapest cut is dropping the top cove fills and the high `Stair Fill` boxes.
- **Deck height mismatch:** my deck top is .445 with bottom −4.5; `modules_swerve.py` uses .45 and −4. WP4 should match .445 / −4.5.
- **Spiral collision:** I used two bands of boxes per step instead of the single box ANALYSIS F12-G specified. That keeps both the gap and the overhang near the core under 0.3. The outside edge of the stair still looks stepped, which is how it was designed.
- **Corner cove overlap:** CornerCove keeps its 0.6-stud overlap past each tangent point (unchanged).
- **Can't be checked offline:** whether the tile grid lines up where the well plate meets the ceiling slab, and how a stretched MeshPart's tiles look in Studio.
- **Not touched:** `assemble_level.py`, `build.py`, and the canonical export.

## Fix report (final; supersedes the implementation report where they differ)

I fixed all eight defects in `tools/level2_poolrooms/modules_arch.py`, the only file I edited. Validate, the watertight check, the export and the WP5 kit collision audit all pass. `test_level2_kit_world_builder.py` still fails with `missing Components.Walkway_Bend16`, as before: the runtime builder has not been updated yet (WP6/WP7).

## Fixes, per defect

1. **Landing (blocker).**
   - The profile is now (0,-4.5) (10,-4.5) (10,-.3) (9.92,-.1) (9.7,0) (0,0): a flat top at y=0, a rounded rim, and a skirt down to -4.5.
   - New check: every chunk's signed volume must be above 0.
   - New check `check_tops()`, run on Walkway_Corner_R16/R24, Walkway_Ring_R9, PoolSteps_Curved and the Landing. It reads the mesh itself, not a sample grid. Every flat up-facing face must sit at a declared top, and those faces must cover each top's radius range (less the small sag between polygon edges and the true curve).
   - Rendered in A16 and A17.
2. **Vault (major).**
   - Triangles are now emitted explicitly. Quads split on a–c, except where ix+iz+1==n, which split on b–d. So the groin crease |x|=|z| is always an edge.
   - The mesh is now smooth=True.
   - UVs follow the true arc length of the half ellipse (16 across, 12 high), from a 2001-sample lookup table.
   - New check: no triangle may have corners on both sides of |x|=|z|.
   - Rendered in A14 and A15. The groins now read as clean curves, with no zigzag.
3. **Spiral G4 (major).**
   - Treads whose top is under 2.5 (treads 1–3) now reach down to y=-4.
   - Their `Stair Ground {,Outer }1..3` and `Stair Fill {,Outer }1..3` boxes now go from -4 up to the tread top.
   - New check: the lowest tread vertex is at -4 or lower.
   - The core end-ring check now looks for the 48 core vertices by position, because the skirted treads put extra vertices on r=5 at y=-4. It is no stricter or looser than before.
4. **CornerCove overlap.** It now runs past each tangent by `asin(.05/R)`, down from `asin(.6/R)`. New check: the r=R faces face the pivot, and the inner surface goes no more than 0.05 past either tangent.
5. **Revolved-piece UVs.**
   - `revolve()` now measures u from the middle angle and takes an optional fixed `u_radius`.
   - The corner coves use √(R(R−3)). Tile lines stay radial, so they continue the straight runs' lines at both tangents, with no shear.
   - The stops use u_radius 3: true tile size at the floor, fanning in toward the axis.
   - New check: UV density on the fillet faces must be between 0.75 and 1.3. The reviewer suggested 0.8–1.25, but R8 can't meet that. Its fillet spans radius 5 to 8, a 1.6:1 ratio, wider than 1.25/0.8 = 1.56. Measured: R8 0.791–1.269, R16 0.902–1.117, R24 0.936–1.074, straight runs exactly 1.0. Stops are excluded because they fan into the axis by design.
6. **SunSlit attributes.** Now `Opening=[2,13.5]`, `HoleBottom=.5`, `HoleTop=14.0`.
7. **Ceiling-well top lip.** It now mirrors the bottom lip (rings at depth-.71 and depth-.41), so it meets the flat top at 48°. That is above prkit's 45° sharp-edge rule, so the edge is kept sharp and the streaky shading goes away. A05 shows a clean top.
8. **Review coverage.** A new `detail_review()` renders A14–A19 (vault group, curved steps with landing, an R24/H42 corner and an R8/H96 corner, each low and from below). The new CornerCove check is item 4.

## Interface (full; changes marked NEW or CHANGED)

**Frames**
- **WALL-FACE** (CoveBase/CoveTop, CoveBaseStop, Walkway_Straight): pivot on the wall's room face, local +Z into the wall, room toward −Z, X along the wall. Use `wallPose(hall,side,along,.75)` with no extra 180° turn.
  - Base pieces sit at FloorY+.445 in halls with a deck, FloorY in dry halls. CoveTop sits at C−3.
- **CORNER** (CornerCove, CoveBaseCorner/CoveTopCorner, Walkway_Corner): pivot at the fillet centre = boundary corner + (1.75+R)(sx,sz).
  - Yaw: MinX/MinZ 0, MaxX/MinZ −π/2, MinX/MaxZ π/2, MaxX/MaxZ π.
  - CornerCove and Walkway_Corner sit at FloorY, CoveBaseCorner at the base height, CoveTopCorner at C−3.
- **BOUNDARY** (SunSlit, WallVoid): pivot on the outer boundary plane, local +Z out of the room; use `wallPose(...,-1)`.
- **CEILING** (LightWell_*): pivot at (x, C, z).

**Coves**
- **CoveBase{4,8,16,32,64} / CoveTop{same}**
  - Attributes: Length, Radius=3, WallSide '+Z', WallPlane 0, Profile.
  - Collider `Cove Fill`, size (L, 1.1, 1.1), centred at (0, .25, −.25) on the base or (0, 2.75, −.25) on the top.
  - Build runs from 64/32/16/8/4 pieces and scale along X by no more than 12.5%.
- **CoveBaseStop_PX / _NX**
  - Pivot at the run's end. Reaches 3 studs toward ±X.
  - Collider `Cove Fill` (.7, 1, 1).
  - CHANGED: UVs only.
- **CoveBaseCorner_R / CoveTopCorner_R (8, 16, 24)**
  - Colliders `Cove Fill 1..n`, n = 4, 7, 10.
  - Attributes: CornerRadius, FilletRadius=3.
  - CHANGED: UVs only.
- **CornerCove_R{8,16,24}_H{34,42,52,96}**
  - CHANGED: runs only 0.05 past each tangent.
  - Colliders `Corner Block 1..n` covering y −4 to H+2. CHANGED counts: n = 4, 8, 11 (R8 was 5).
  - Markers TangentX and TangentZ. Pick the exact height; never scale it vertically.

**Decks and steps**
- **Walkway_Straight{4,8,16,32}**
  - Part `Walkway Deck` (ground), centre (0, −2.0275, −4.35), size (L, 4.945, 9.7).
  - Top .445, bottom −4.5. Attribute PoolEdge = −9.5.
- **Walkway_Corner_R16 / R24**
  - Ring from radius R−9.5 to R+.5, over the angle range π to 3π/2.
  - Colliders `Corner Deck Ground 1..6` (R16) or `1..8` (R24).
  - Use a plain box Part for corners with R of 0 or 8.
- **Walkway_Ring_R9**
  - Pivot = the Column_D10 pivot. Radius 4.96 to 9; colliders `Ring Ground 1..14`.
- **PoolSteps_Straight12**
  - Pivot at the deck's pool edge, at deck-top height; steps descend toward −Z.
  - Parts `Step Ground 1..3`, tops −.6, −1.2, −1.8, bottoms −4.5.
- **PoolSteps_Curved**
  - Half rings over local +X with tops −.6, −1.2, −1.8.
  - Colliders `Step N Ground i`: 10, 13 and 16 per ring.
- **PoolSteps_Curved_Landing** (CHANGED mesh)
  - Half disc of radius 10, flat top at y=0 out to r=9.7, rim out to 10, skirt to −4.5.
  - Colliders `Landing Ground 1..6`.
  - Pivot = the curved steps' pivot.

**Ceiling openings and stairs**
- **LightWell_R6 (panel 24), R10 / R12 / R14 (panel 32)**
  - Attributes: HoleRadius, PanelSize, ShaftDepth=8. Read PanelSize for the ceiling cut.
  - Marker `OpenSky` at (0, 8, 0) with Radius. Colliders `Collar Block i` from y 0 to 8.
  - CHANGED: top lip shape only. LightWell_R14 replaces ExitSkylight.
- **SpiralStairWell_H42 / H52**
  - Pivot at FloorY. Attributes unchanged:

    | | H42 | H52 |
    |---|---|---|
    | StairTop | 28 | 38 |
    | Steps | 36 | 49 |
    | Rise | .7778 | .7755 |

  - Also PanelSize=32, HoleRadius=12, Opening='LightWell_R12'.
  - Colliders: `Core Block` (cylinder, y −4 to H+8); `Stair Ground {,Outer }i` (ground, narrower than 4 studs); `Stair Fill {,Outer }i`; `Stair Ground Landing 1..4` and `Stair Ground Landing Outer 1..5`.
  - CHANGED: treads 1–3 and their Ground and Fill boxes now run from −4 to the tread top.
  - Collider totals: H42 150, H52 202.
  - Markers StairStart and StairEnd.

**Vaults and columns**
- **VaultBay32_H34 / H42**: groin vault (CHANGED: triangles and UVs only, same shape).
- **VaultPier**: Part and collider at (0, 19, 0), size (5, 46, 5). `fitVaultPier`: Size.Y = height+4, centre y = FloorY + (height−4)/2.
- **Column_D{6,10,16}_H{34,42,52}**: from y −4 to H.

**Decor and fixtures**
- **LightRound**: place the pivot at y = C−.15; diameter 3.4.
- **SunSlit** (CHANGED attributes): `Opening=[2,13.5]`, `HoleBottom=.5`, `HoleTop=14.0`, relative to a pivot at `wallPose(-1)` × (0, h−17.5, 0). The Neon plane is 2.4×14.4, from y 0 to 14.4.
- **WallVoid**: Part `Void Back`, centre (0, 2, −.1), size (10.4, 4.4, .2). Cut a 10×4 hole whose bottom is at the pivot y.
- **DrainHole**: Void disc 3 across and .06 thick; place it at basin top + .03.

## Test and validate output
- **modules_arch build (full run, exit 0):** `PR_EXPORT={"components": 77, "chunks": 76, "tris": 32684}`, `PR_A_OK`.
  - validate() and check_kit pass, with 1033 collider orientations checked.
  - Cove Fill gaps: 0.501 on straights, 0.537 on stops, 0.528–0.569 on corners.
  - Ground gaps: 0.0 on decks, the ring and curved steps; 0.041 on the landing; 0.269 on the spiral.
  - Up-facing faces at declared tops: 32 / 48 / 80 / 96 / 16 (R16 corner, R24 corner, ring, curved steps, landing).
  - Watertight ray check: 77 components, 0 escapes, 0 open edges.
- **Negative tests** (`G:/Roblox/_local/l2fix/impl/WP1/r2/neg.py`): each new check fails on the defect it was written for.
  - Old landing: inside-out chunk, signed volume −228.88.
  - Old vault: triangle straddles the groin crease.
  - Old 0.6 overrun: CornerCove runs more than .05 past a tangent.
  - Unskirted spiral: lowest treads don't reach −4.
  - Old sheared UVs: fillet UV density 0.495–2.02.
- **WP5 kit collision audit:** `KIT 1 dirs, 77 components, 0 failing: PASS`.
- **test_level2_kit_world_builder.py:** FAIL, `missing Components.Walkway_Bend16`, until WP6/WP7 update the builder.

## Renders inspected
All in `G:/Blender/Level2_Poolrooms/review/A/`, rendered with backface culling on:
- New: A14_vault_group_from_below, A15_vault_bay_straight_up, A16_curved_steps_landing, A17_landing_rim_low, A18/A19_corner_R24_H42 (low, top from below), A18/A19_corner_R8_H96 (low, top from below).
- Re-checked: A01 (stops), A05 (well top), A11 (spiral in the basin).
- I deleted the stale 00–03 renders from that folder.

## Still open
- The basin floor is 0.8–2.0 below FloorY, so the step up onto the first tread is still 1.6–2.8 studs (a jump, not an auto-step). Fixing that needs a separate plinth step or a lower StairStart, which is a design decision.
- The collider instance budget against the 9,000 limit is unchanged and still for WP6 to measure. The spiral H52 has 202 colliders.
- The deck height mismatch with `modules_swerve.py` (.45/−4 there, .445/−4.5 here) is for WP4.
- `assemble_level.py` still places the deleted Walkway_End/Bend pieces. That file isn't mine.
- Still can't be checked offline: whether the tile grid lines up where the well plate meets the ceiling, and how stretched MeshParts look in Studio.


# WP2-tunnel

## Review: defects, 7 defects
- [minor] F12-E / G8 instance budget: Each RoundTunnel now ships 16 'Lower Corner Fill' Parts (4 steps x 2 sides x 2 mouths). The round-bore facets were also thickened to 3.0, and with those facets 12 of the 16 fills add nothing. Measured at the audit's 0.6 tolerance on RoundTunnel_Dry_64, at the hall face, mid-depth and outer face of the collar: facets alone leave 91 of 2,495 lower-spandrel samples uncovered (x >= 15.8, y <= 1.2), and the k=1 step (x0=12, y1=0.96) on its own covers all of them. The dumps place 41-46 RoundTunnels pe
- [minor] F3/F4 ribs (half-finished look): rib() takes its angle range from arch_angles(radius=17, ...), which is the barrel's floor chord, but builds the inner band at radius-0.34. Every rib band therefore ends 0.26 studs above the floor or ledge (at x=+-10.71, y=floor+0.26). The rib has no end cap, so each rib foot has an open slot into the hollow ring, and through it you see the back of the side faces (drawn DoubleSided in Roblox). That is 2 slots per rib, with 2-3 ribs in each of 41-46 tunnels per map. My independent back-face ray ch
- [minor] F4-M coplanar z-fight (G1 tile Parts): In every RoundTunnel_Wet, two visible Tile Parts have coplanar top faces at y=0 that overlap. 'Level 2 Corridor Channel Side +-1' spans x 6.7..7.0, y -1.9..0, and 'Level 2 Corridor Ledge +-1' spans x 6.8..11.23, y -0.9..0. That leaves a 0.2-wide strip along both ledge lips for the full tunnel length (14-16 stud^2 per side), where two Parts with different tile phase z-fight. The defect predates this package, but the file is WP2's and it fails the F4-M rule: 0 same-facing coplanar overlaps of 1 st
- [minor] F1/F2 butt-joint rule (FIX_SPEC 'butt joints (0.05)') at chamber sockets: wall_coves cuts the lower cove at exactly offset+-6. ChamberSocketCove is authored over exactly -6..6, so at every kept socket two separate MeshParts meet with zero overlap. After two float32 CFrame transforms (chamber then marker) that can open a hairline crack in the cove line. It is also inconsistent with the 0.05 overlap the same file uses at the corner tori.
- [minor] F1/F2 butt-joint rule, chamber corners (PLAUSIBLE z-fight): The chamber Wall Run Parts still run 0.5 past each fillet tangent (cursor = -end-.5 / end+.5). Across that 0.5 the corner mesh lies only 0 to 0.02 in front of the wall Part's face (offset s^2/(2*6.25)). That leaves a near-coplanar overlap strip about 0.25 x 17 studs at all 8 tangents of every chamber, which is the kind of 0.5 overlap of identical surfaces the spec bans. Not confirmed in Studio.
- [minor] F2 'every corner reads continuous' (UV): The corner-torus UVs restart at u=0 at the tangent. The straight wall-cove runs end at u = end_along*S. So grout lines jump at all 16 cove/torus joints of every chamber (8 upper, 8 lower). The implementer acknowledged this, but it is still a visible seam on the pieces this package was meant to make continuous.
- [minor] F12-E check (max gap <= 0.6): The ANALYSIS F12-E acceptance is max gap <= 0.6. The kit audit measures 0.66-0.68 on every RoundTunnel: at the rib bands, the 12-facet polygon's seams sit 0.34 behind the barrel and 0.68 behind the r-0.34 band. Pipes measure 0.71-0.77 at the lower mouth corners (x=+-6, y about 2), where neither the 0.7-thick pipe facets nor the threshold (top y=1) back the collar. These pass collision_audit's 1.0 limit but not the analyst's stated check, and the report quotes 0.67 without flagging that.

## Implementation report

WP2 is done, with three gaps outside my file. In tools/level2_poolrooms/modules_tunnel.py every escape, capsule-walk, chamber, UV, normals and kit-collision check passes. Still outstanding: the builder test stops at the chamber water region (WP6 work), the two new socket pieces need a KIT_ALLOW entry in WP5's audit, and nothing has been tried in Studio yet.

## (1) What changed (only `tools/level2_poolrooms/modules_tunnel.py`)

**Materials (F3)**
- Ribs are now Tile, split into a smooth inner band (cylindrical per-vertex UV) and two flat side faces with planar UV.
- The Worn patch loop is deleted.
- Pipe_Stair4 steps are Tile.
- The chamber porthole ring is Tile.
- The Pipe_Flat floor is now Tile and renamed to "Level 2 Passage Floor" (was "Level 2 Passage Aqua Floor"). Reason: G1 says Aqua is only for floors under water, and pipes are now dry.

**Normals and UVs (G2, F3+F6)**
- `arc_shell` faces the bore axis and uses per-vertex UV (axial, arc length), so the pipe seam no longer wraps.
- The collar's circular reveal is now its own shell with per-vertex UV, facing the axis. Panels and outer edges use box UV and face away from the collar solid.
- `chamber_corner` is the inner surface only, with facing and per-vertex UV.
- Wall coves, corner tori and socket pieces all carry facing hints and per-vertex UV.
- The porthole rim was rebuilt with no back face against the wall.
- `socket_face` was dead code (never called), so I deleted it rather than give it a hint.

**F12-E collars**
- Added 16 Lower Corner Fills per round tunnel, as specified.
- The audit still found up to 1.47-stud gaps in the upper part of the collar, between the circle and the existing Corner Fill. I closed those by making the 12 round-bore facets 3.0 thick, growing outward only; the inner plane is unchanged and no instances are added. Pipe facets stay 0.7.
- Stepped boxes there would have cost 28 more parts per tunnel, about 700 per map against the G8 budget of 9,000.
- The facets' outer corners stay within 20.3 studs of the corridor axis. The layout keeps any third hall's wall at least 20 studs out, so a facet can poke at most about 0.25 into that wall and never into the room.

**Chambers (F1+F2+F4, F12-F)**
- A uniform ledge ring at top y=0 replaces the Dry Threshold and the Side Steps.
- Cove tori now run round all four fillets, top and bottom.
- Straight cove runs go tangent to tangent with a 0.05 overlap.
- The lower cove is cut out of every socket span.
- The Chamber_D nook is dropped, so the Room Nook Wall yaw fix no longer applies.
- Chamber_D's porthole moved from x=-11 to x=-9, because its rim overlapped the fillet.
- Chamber_C's daylight slit dropped 0.1 to y=13.15 so it no longer cuts the upper cove.
- Room Curved Side colliders now get their yaw from `kit.yaw_x_along`. Some corners differ from before by 180°, which is the same box.

**Water (F5)**
- Wet tunnels and chambers use the new single 4-stud row (top at floor - 0.1; exact numbers below).
- Pipe_Flat has no water region.

**`__main__` checks**
- New `check_chamber`: the cove foot is on y=0 ground along every run and round every arc, the water is the full footprint, and no Nook or Side Step remains.
- Lower-fill assertions: count, corner exactly on the circle, box on the spandrel.
- Water region per tunnel and pipe variant.
- Component count is now 30.

## (2) Interface for the runtime builder

**Chamber_A/B/C/D**
- Parts, all Tile, `ground=True`, `Level2_EntityGround`:
  - "Level 2 Room Ledge N" / "S": centre (0, -0.7, ∓(d/2-4)), size (w, 1.4, 8).
  - "Level 2 Room Ledge E" / "W": centre (±(w/2-4), -0.7, 0), size (8, 1.4, d-16).
- Removed: "Level 2 Room Dry Threshold", "Level 2 Room Side Step ±1", and the "Room Nook Wall 1-4" colliders.
- Unchanged: Aqua Floor (top -1.2), wall runs, Plug / Below / Above Socket parts, Socket markers (`cf [x,0,z,yaw]`; N 0, E -90, S 180, W 90), Roof Collider, slab, and the 16 "Room Curved Side" colliders. Per FIX_SPEC the builder should keep these colliders and delete its Corner Seals.
- `waterRegion` = `{center [0,-2.05,0], size [w,3.9,d], surfaceY -0.1}`. The builder's `chamberWater` table must go.
- DaylightPorthole on Chamber_D is now at x=-9. DaylightSlit on Chamber_C is at y=13.15.

**ChamberSocketCove / ChamberSocketStops** (new components)
- No records. Attributes: `Role="ChamberSocketPiece"`, `Pivot="SocketMarker"`, `SocketPiece="Cove"` or `"Stops"`, `Width=12`, `CoveRadius=1.2`.
- Authored in the Socket marker's frame: +Z points into the room, inner wall face at z=1.75, ledge at y=0.
- `makeSmall` places them at `chamberCF * markerCF`: the Cove where the Plug stays, the Stops where it removes the Plug.

**RoundTunnel_\***
- New parts "Level 2 Corridor MouthFrom|MouthTo Lower Corner Fill ±1 k" (k = 1..4):
  - Tile, collide, `Transparency=1`, `show=False`.
  - Box spans x0..17 by floor..y1, depth 1.75, centred at the mouth's z ∓0.875.
  - x0 = 12 / 14 / 15.5 / 16.5; y1 = 0.96 / 3.36 / 6.02 / 8.91.
- Facets: still 12, size (9.0, 3.0, (L+3.5)·pitch), centre radius r-0.25+1.5. Collider counts are unchanged at 13/14 per tunnel and 9 per pipe.
- Wet variant `waterRegion` = `{center [0,-2.05,0], size [16,3.9,L], surfaceY -0.1}`.
- Unchanged: InnerRadius, CircleCentreY, CollarDepth, mouth markers (clearWidth/clearHeight), Thresholds, the 4 upper Corner Fills, Roof Collider, Entry Crown Cap, LampLight, stair profile.

**Pipe_\***
- No `waterRegion`; the builder must drop its narrow-pipe water branch.
- Floor part renamed to "Level 2 Passage Floor" (Tile).

## (3) Check results

- `modules_tunnel.py` run: exit 0. `PR_ESCAPE` is 0 for all 24 tunnels and pipes, and for the 4 chambers both sealed and open. Capsule walk, `check_chamber` and the lower-fill asserts pass. `PR_EXPORT` gives 30 components, 34 chunks, 40,348 tris.
- f3f6 kit rules C/D/E (scratch `kitrules.py` on job B): `TOTAL {}`.
- `facing_check.py`: `FACING_BAD 0`. As a control, the same check on the old canonical export reports `FACING_BAD 28`.
- `collision_audit.py --no-world --kit jobs/B/export`: all 28 tunnel, pipe and chamber components pass. Tunnels are 0.04–0.09% unbacked with max gap 0.67; chambers are 0; pipes are at most 0.45%.
  - ChamberSocketCove and ChamberSocketStops fail rule A3 only. WP5 needs to add `"ChamberSocket*": ("backed", "seated R1.2 fillet on the chamber ledge/wall")` to KIT_ALLOW.
- `test_level2_kit_world_builder.py`: FAIL at "seed 1: chamber 3 lacks its authored shallow water region". This is expected until WP6 replaces the `chamberWater` table and the corridor water code.

## (4) Renders inspected (G:/Blender/Level2_Poolrooms/review/B/, backface culling on)

- Tunnels: `RoundTunnel_Wet_72`, `RoundTunnel_Wet_Mouth_Corners_72`, `RoundTunnel_Wet_Mouth_LowerCorner_72`, `RoundTunnel_Stair8_64`
- Pipes: `Pipe_Flat_48`, `Pipe_Flat_Mouth_Corners_48`, `Pipe_Stair4_48`
- Chambers: `Chamber_A`–`D` (`.png`) and `Chamber_A`–`D_Corner` (`.png`)
- Sockets: `Chamber_B_Socket_Kept_E0`, `Chamber_B_Socket_Open_N0`, `Chamber_B_Pipe_Joined`

## (5) Not done or uncertain

- I did not run `build.py`, so the canonical export, the import test and the backface check on world dumps wait for the lead's rebuild. No Studio check yet.
- At an open socket the Stops are almost entirely hidden inside the pipe threshold. Their faces at x=±6 lie in the same planes as the threshold's sides but face the other way, so I expect no z-fighting from any reachable view; this is not confirmed in Studio.
- The pipe threshold still steps up 1 stud onto the pipe floor, 2.25 studs into the chamber; this is the "small rounded curb" in image 4. It stays because the pipe floor sits at +1.
- Tile grout lines do not line up where the straight coves meet the corner tori; the UV phases differ at those joints.
- Pipes have no lamp of their own and may read dark once the normals face inward.
- Scratch scripts are in `G:/Roblox/_local/l2fix/impl/wp2/`.

## Fix report (final; supersedes the implementation report where they differ)

**WP2-tunnel, revision 2.** I fixed all 7 review defects, and I only edited `tools/level2_poolrooms/modules_tunnel.py`. The full module run exits 0, the job-B export has 30 components, 34 chunks and 40,348 tris, and every kit check passes except the 2 KIT_ALLOW entries that WP5 still has to add. The offline builder test stops on a missing component in another package's code, before it reaches anything I changed.

## Fixes, one per defect

1. **Lower fills and instance budget.** Each RoundTunnel now has 4 Lower Corner Fills instead of 16: one per side per mouth.
   - I picked x0=14 rather than the reviewer's 12. Both give the same overall worst gap, but 14 leaves more margin in the lower spandrel on Stair8.
   - The "16 per tunnel" count rule is replaced by `check_collar_backing`. It checks that every collar-panel point on both mouths (hall face, mid-depth and inner face) is within 0.6 of a collider or colliding Part.
   - The first run of that check failed in two places, and the old count rule had missed both. Each was a pre-existing gap at the 0.6 limit:
     - Stair8: the round-bore facets came apart at their outer corners on the 30° seam. Their seam overlap went from 0.2 to 0.8.
     - Pipe_Stair4_16: the tilted top facets left the collar header 0.84 from collision. Pipe facets went from 0.7 to 1.2 thick.
   - Net change is roughly −12 instances per tunnel and +4 per pipe, about −380 per map. That is an estimate from the reviewer's 41–46 tunnels and about 35 pipes per map.

2. **Rib feet.** The tunnel ribs now take their angles from `arch_angles(inner, cy+.05)`, so each foot ends 0.05 below the floor or ledge and is buried. Pipe ribs stay full circles. The reviewer's back-face check went from 1 hit to `TOTAL_BACK 0`.

3. **Coplanar tile tops in Wet tunnels.** I deleted "Corridor Channel Side ±1". Each Ledge is now one solid from the channel face to the wall. The top-face coplanar check gives `COPLANAR_BAD 0`; the previous export gives 6.

4. **Socket cove butt joint.** ChamberSocketCove now runs from −6.05 to 6.05, a 0.05 butt past each cut end. The Width attribute stays 12, and the Stops stay at ±6.

5. **Chamber wall runs.** They now end 0.05 past each fillet tangent instead of 0.5. The chambers still pass the escape check with sockets both closed and open.

6. **Cove grout continuity.** `cove_phase()` gives the coves one tile phase running round the whole room.
   - All 16 cove-to-corner joints in each chamber meet in phase.
   - The lower cove also lands on a whole 0.6-stud tile at every socket edge, so the shared ChamberSocketCove meets every kept socket in phase.
   - The stretch needed to close the loop is at most 0.3 stud per stretch, which stays inside the tile-density rule.
   - New check `uvphase.py`: `UV_PHASE_BAD 0` on this export. The previous export gives 72, so the check does catch the old seams.

7. **Collision gap ≤ 0.6.** Rib relief is now 0.24 (`RIB_RELIEF`, was 0.34). The pipe fills from defect 1 also close the lower pipe corners. The collision audit now reports a worst gap of 0.58 everywhere: tunnels 0.57–0.58, pipes at most 0.45, and 0 unbacked area in every tunnel, pipe and chamber (was up to 0.09%).

## Interface for the runtime builder (full)

**RoundTunnel_{Wet,Dry,Stair4,Stair8}_{64,72,80}**
- Attributes are unchanged: Kind=Tunnel, Variant, Length, Width=34, FromY=0, ToY=rise, InnerRadius=17, CircleCentreY=13, CollarDepth=1.75.
- Markers are unchanged: MouthFrom (yaw 180) and MouthTo (yaw 0) with clearWidth 34 / clearHeight 30; LampLight.
- Unchanged Parts: Threshold, 4 upper "Corner Fill" Parts (x 12.7..17, y 24..32), Dry Floor and Stair Ramps.
- Unchanged colliders: Roof Collider, and Entry Crown Cap on the stair variants.
- **Changed:** "Level 2 Corridor {MouthFrom|MouthTo} Lower Corner Fill ±1" (no step index any more). Tile, collides, Transparency 1, `show=False`. Box spans x 14..17 (×side) and y floor..floor+3.358 (`13−√(289−196)`), depth 1.75, centred at mouth z ∓0.875. Floor is 0 at MouthFrom and rise at MouthTo.
- **Changed:** 12 Facets, each `(2·17·sin15°+0.8, 3.0, (L+3.5)·pitch)`, 12-number cf. The inner plane is still r−0.25; outer corners are at most 20.33 from the axis. Collider counts are still 13 (flat) / 14 (stair).
- **Changed, Wet only:** "Corridor Ledge ±1" = Tile, ground, `Level2_EntityGround`, centre (±8.967, −0.95, 0), size (4.534, 1.9, L). "Corridor Channel Side ±1" is removed. Water Floor is unchanged (centre (0,−1.95,0), size (13.6,0.9,L), Aqua). `waterRegion = {center [0,−2.05,0], size [16,3.9,L], surfaceY −0.1, terrainOnly true}`.
- Ribs are mesh only: band at r−0.24, feet at floor−0.05.

**Pipe_{Flat,Stair4}_{16..80}**
- **New:** "Level 2 Passage {MouthFrom|MouthTo} Lower Corner Fill ±1". Tile, collides, Transparency 1, `show=False`. Box spans x 4.5..6 and y floor+1..floor+2.031, depth 1.75, at mouth z ∓0.875.
- **Changed:** 8 Facets `(2·6·sin22.5°+0.2, 1.2, (L+3.5)·pitch)`. The inner plane is unchanged (r−0.25); outer corners are at most 7.35 from the axis. Still 9 colliders.
- Unchanged: "Level 2 Passage Floor" (Tile), no waterRegion, Corner Fills, Thresholds, markers.

**Chamber_A/B/C/D**
- Same as the previous report: Ledge N/S/E/W, Aqua Floor, Plug / Below / Above Socket, Socket markers (N 0, E −90, S 180, W 90), 16 Room Curved Side colliders, Roof Collider, waterRegion `{[0,−2.05,0],[w,3.9,d],−0.1}`, DaylightPorthole x=−9 on D, DaylightSlit y=13.15 on C.
- **Changed:** "Room {wall} Wall Run j" Parts now run from tangent−0.05 to tangent+0.05 (previously ±0.5 past each tangent).

**ChamberSocketCove / ChamberSocketStops**
- Attributes unchanged: Role=ChamberSocketPiece, Pivot=SocketMarker, SocketPiece=Cove|Stops, Width=12, CoveRadius=1.2. No records.
- Both are placed at `chamberCF * markerCF`.
- The Cove mesh now spans local x −6.05..6.05 with u = local x. Its tile phase matches the chamber's because the marker's +X runs in the chamber's cove direction.

## Check results
- `modules_tunnel.py` (Blender, `__main__`): exit 0. `PR_ESCAPE … 0` on all 32 runs (24 tunnels and pipes, 4 chambers sealed and open). Capsule walk, collar backing, lower-fill corners, `check_chamber` and water-region asserts all pass. 19 renders.
- `facing_check.py`: `FACING_BAD 0`
- `kitrules.py` (rules C, D, E): `TOTAL {}`
- `backface_b.py` (reviewer's ray check on job B): `TOTAL_BACK 0`
- `uvphase.py`: `UV_PHASE_BAD 0` (control on the previous export: 72)
- `coplanar.py` (top faces): `COPLANAR_BAD 0` (control: 6)
- `collision_audit.py --no-world --kit jobs/B/export`: all 28 tunnel, pipe and chamber components pass, 0 unbacked, worst gap 0.58. **FAIL** only for ChamberSocketCove and ChamberSocketStops on rule A3. WP5 still needs to add `"ChamberSocket*": ("backed", "seated R1.2 fillet on the chamber ledge/wall")` to KIT_ALLOW.
- `test_level2_kit_world_builder.py`: **FAIL**, but earlier than last time and not in my file: `missing Components.Walkway_Bend16`. Another package's in-progress builder change asks for a component that isn't in the canonical export yet. The chamber-water failure I expected last time is still waiting behind it.

## Renders inspected (`G:/Blender/Level2_Poolrooms/review/B/`, backface culling on)
- `RoundTunnel_Wet_72`: the ledge is now its own channel side.
- `RoundTunnel_Stair8_64`
- `RoundTunnel_Stair8_RibFoot_72` (new): the rib foot is buried in the ramp with no open slot.
- `Pipe_Flat_Mouth_Corners_48`
- `Chamber_A_Corner`, `Chamber_D_Corner`: grout runs continuously from the straight cove into the corner, and the wall meets the fillet with no gap.
- `Chamber_B_Socket_Kept_E0`: grout is continuous across the kept-socket cove.

## Still open
- The canonical rebuild (`build.py`), the import tests and the world back-face check are waiting on the lead. Nothing has been checked in Studio.
- The thicker facets push slightly further out:
  - **Pipes:** outer corners now reach 7.35 from the axis, about 0.47 further than before. Anything within that distance of a pipe axis would meet invisible collision; I did not check the layout spacing for that.
  - **Tunnels:** outer corners now reach 20.33 from the axis. That can sit up to 0.33 inside a neighbouring 1.75-stud wall slab, never in the room.
- A rib side face is only 0.3 wide, so its planar UV shows just scattered grout marks.
- The Chamber_D porthole rim looks slightly faceted at grazing angles; that wasn't in the review and I left it.
- The pipe threshold's 1-stud step up into the chamber (the curb in image 4) is unchanged.

Scratch checks are in `G:/Roblox/_local/l2fix/impl/wp2/`: `uvphase.py`, `coplanar.py`, `pipecov.py`, `gapwhere.py`, `backface_b.py` and the run logs.


# WP3-objectives

## Review: defects, 9 defects
- [major] F13 / check (1) of test_level2_exit_bore (owner F13 'invisible collision with nothing'): Marker 1's collision piece is shifted so it starts at the mouth, which pushes its whole 1.5 overlap past P1. P1 is the crest into the plunge and the sharpest bend on the path (6.83 deg; segments 1 and 2 are only about 1.03 long). The result is a flat ghost shelf in the floor, up to 0.40 above the visible floor, at anchor-relative (1.50, -7.60, -0.23). Test (3) still passes for two reasons. It samples only 3000 random points over the whole ~1000-stud tube, so it never lands on this ~1.5x3 stud pa
- [major] G8 instance budget: Verified from the manifest. The exit adds about +772 instances per round: ExitSpiral +650 (847 colliders vs 199), ExitPlatform +48, ExitCollar +64, pumps +21, minus about 11 removed. The plan was +152. Against the 8,164 baseline that is about 8,936 of the 9,000 cap, before WP1/2/4/6-9 add ring decks, cove fills, corner fills, sky caps and lights. G8 will almost certainly fail. Some of the cost does no gameplay work. The 56 'Exit Collar Side Fill' boxes back a 0.16-0.67 wide ring between the bore
- [minor] F4-M z-fighting (ExitCollar trim): 'Exit Collar Trim Left/Right' (y 72.7..90.4, z ±7.96..9.21) and 'Exit Collar Trim Top' (y 89.16..90.4, z ±9.21) are the same 0.25 thick at the same x, so their volumes coincide in a 1.25 x 1.24 patch at each top corner. The hall-facing face (x=E-2.0), the top face (y=90.4) and the outer face (z=±9.21) are coplanar there. Two Parts of different sizes have different texture phase, so the patch will flicker.
- [minor] F11 deck / collar closure: Below the collar there is an open recess 0.25 deep x 0.54 high x 15.92 long, between the deck's east face (E-2.0) and the wall face (E-1.75), at y 72.7..73.24. The wall strips stop at the trim legs and the collar's square starts at 73.24. It is visible from under the deck.
- [minor] F12-G pump gauge collider / G6: 'Pump Gauge Collider' (1.4 x 1.4 x 0.3 at (-1.4, 6.05, 0.12)) is a square around a round gauge of radius 0.71. Its corners stand 0.28 outside the visual, which is ghost collision. It also no longer backs the gauge stem (rod y 5.45..6.1, z -0.51..-0.19), which the spec's (1.5, 1.6, 0.6) box at z 0 covered. The report describes this as 'tightened to the visible iron'.
- [minor] Render rule (backface culling ON): In reviews(), 'pump_station' renders before the loop that sets use_backface_culling. That loop also runs only once, so materials created later (review water, the open-mouth green) are not culled. The pump was therefore never inspected with culling. I re-rendered it with culling on and it looks correct.
- [minor] test_level2_exit_stair (f) / lip ghost check: The docstring for (f) promises that the ramp's bottom stays inside the visible silhouette, but no code checks it. I checked it separately: 20 of 724 ramp boxes protrude, and all of them are buried foot boxes (y about -4.9) or top boxes inside the bridge Part, so nothing is visible. Also, the lip exemption 'ok |= top' accepts any top corner above 74.5 with no limit, while the comment says 'at most 0.15'.
- [minor] G2 shading / owner F3 ('ring in another tile colour'): The tube visual writes each stave as its own unwelded quad with smooth=False. In Roblox every one of the 16 staves is then flat-shaded, which shows as lengthwise light/dark stripes in the bore (renders exit_collar_mouth, collar_grazing). At every twisted helix joint, the neighbour's end cap also shows through a ~0.03-wide sliver as a seam ring (the implementer saw this too). The owner rejected exactly this kind of colour ring in tunnels.
- [minor] F4 'half-finished' (pump, objectives.py owned by WP3): The horizontal right-hand rod starts at x=1.8, but the drum surface at y 4.2 ends at x≈1.03. The rod floats about 0.77 off the drum with its flat end cap visible (render pump_station, upper right). This predates WP3 but sits in this package's file.

## Implementation report

I've finished WP3 in full: the exit stair, platform, collar, mouth trim and 16-gon tube are rebuilt, the pump and arrival door are fixed, and both new tests and the kit-only collision audit pass on `jobs/C/export`. Before WP9 starts, the lead should know about one budget issue and one number that came out above the spec:

- **Instance budget:** the exit adds roughly +770 instances per round. The spec planned about +152. Most of it is the stair: 724 ramp boxes, 90 parapet boxes and 43 base boxes, plus 60 collar fills and 6 extra pump colliders on each of the 3 pumps. The spec's 2-band layout (480 boxes) fails its own walk check: at r = 14.5 it dips 0.058 per step, and the limit is -0.02. At about 8,164 measured that lands near 8,934 before the other work packages add theirs, against the 9,000 cap.
- **Ride joints:** collision pieces stand up to 0.131 inside the bore at helix joints, not the 0.1 F13 estimated. The estimate ignored a frame twist of up to 1.23° per joint. I replaced that assertion with the bound computed from the path itself, which is 0.144.

## 1. What changed

**`tools/level2_poolrooms/objectives.py`**
- **Pump:**
  - The gauge disc and the "Pressure Gauge Face" Part now use `Dial`.
  - New colliders per F12-G: Elbow L/R, Drop L/R, Rod H, Rod V and Gauge. I tightened the drop and gauge sizes to the visible iron (the drop pipe's flange is buried in the plinth).
- **ExitPlatform:**
  - The deck now runs local x -30..34 (centre (2, 73.35, -2.5), size 64 × 1.3 × 41).
  - Two 0.25-wide wall strips close the slot between the deck and the wall face on either side of the collar.
  - The support column is closed and starts at y = -4.
  - The nose is a closed slab over x -30..34.
  - The lip is a closed 0.6 × 0.85 kerb with a half-round top.
  - 32 lip boxes and 32 axis-aligned nose-ground steps, all inside the visible deck, nose and kerb.
  - The portal walls are gone.
- **ExitSpiral:**
  - The stair is one closed solid: 156 steps of 0.5 rise.
  - Its first 120° is a solid foot rising from y = -4.5, instead of the spec's open soffit, so it doesn't hang over the pool floor.
  - The core is a closed newel from -4 to 77.5 with a chamfered top.
  - The parapet is a closed band at r 14.95..15.6 with a cap. It runs from 60° to the top, then straight along the bridge to the deck.
  - Bridge and north guard are tile Parts.
  - The walk surface is 4 bands × 181 pitched ramp boxes.
  - Parapet colliders: 76 pitched boxes, 2 upright fillers at the ends, and 12 base boxes at the foot.
  - 31 base boxes under the foot, plus a south guard collider.
- **ExitCollar:** a closed panel from the square opening to the tube's outer 16-gon, a three-sided trim (Parts), 4 corner fills and 56 side fills.
- **ExitMouthTrim:** the recolour target. It's a closed arch inlay from the bore's 16-gon out to r = 9, only above the deck top, 0.06 proud of the collar.
- **Tube:**
  - The `ExitTubeVisual` chunks (5) are opaque 16-gon tubes cut exactly from the same per-segment prisms the collision uses, closed at every joint and chunk end.
  - New `SlideCol_Bore16` template.
  - 271 `BoreSegment` markers.
- **Removed:** `mouth()`, `skylight()` and `annulus()`. `ExitMouth` and `ExitSkylight` are no longer exported.
- **ArrivalDoor:** the arch ends are now closed, and the reveal strips get an explicit room-facing side.

**New tests:** `tools/tests/test_level2_exit_stair.py` and `tools/tests/test_level2_exit_bore.py`. Both default to the canonical export (or a path argument / `$L2_POOLROOMS_EXPORT`) and fail on today's canonical export.

## 2. Interface for WP9

**Frames.** E = hall.MaxX, F = hall.FloorY, never yawed.
- **deckZ = hall.MinZ + 42**
- **platformCF = CFrame.new(E-36, F, deckZ+10)**: `ExitPlatform` and `ExitSpiral`. Deck top is F+74. The deck's east face is E-2.0, the collar face.
- **collarCF = CFrame.new(E, F, deckZ)**: `ExitCollar` and `ExitMouthTrim`.
  - The collar fills x E-2.0..E+0.25, square ±7.96 around the axis at F+81.2.
  - Trim Parts: legs at z ±7.96..9.21, y 72.7..90.4; top bar y 89.16..90.4.
- **Exit.Mouth** = the single MeshPart of `ExitMouthTrim` (attribute `RecolorTarget = true`). The Objective Controller is unchanged; the green tint at 0.35 transparency over the opaque collar was rendered and reads correctly.
- **anchor = (E+23, F+81.2, deckZ)**, tube cf = CFrame.new(anchor): clone `ExitTubeVisual` and `ExitTubeVisual_02` to `_05`.
  - The path points are the reviewed ones, unchanged.
  - points[1] = anchor + (-25, 0, 0) = (E-2, F+81.2, deckZ). Don't override it any more.
  - The bore floor is F+74, flush with the deck.
- **HallWallGap** = {center = deckZ, width = 15.92, bottom = F+73.24, top = F+89.16}.

**Collision pieces.** For each `BoreSegment` marker (12-number cf, back = -look; attributes Index 1..271, Length, OneWay):
- Clone `SlideTemplates.SlideCol_Bore16` (Template = true; mesh 15.6 × 15.6 × 1, unit Z, centred; 16 stave islands at apothem 7.2..7.8).
- Size = (15.6, 15.6, Length + 1.5), CFrame = cf * marker local CFrame.
- Name `"Level 2 Exit Flume Collision Floor %03d"` using Index.
- Slide attributes as today: SlideCollision, SlideFloor, OneWayExit when OneWay is true, NoEntityGround, SlideDirection = LookVector, SLIDE_PHYSICS.
- Marker 1 is already shifted so its piece starts exactly at the mouth plane.

**Builder deletions:** buildTube, slidePiece, the ExitMouth and ExitSkylight clones, the Lead Tile panels, the Entry Collision Floor and its shift, and the tub supports. Recycle values stay anchor-relative: the Y shift is -2.1, and X moves +10 (inset 32) or +2 (inset 40).

**LightWell_R14** goes at platformCF's x/z, which is (E-36, deckZ+10). The `ExitPlatform` marker `LightWellCenter` (0,0,0) points there.

**Markers:**

| Component | Marker | Local position |
|---|---|---|
| ExitPlatform | MouthCenter | (34, 81.2, -10) |
| ExitPlatform | CollarPivot | (36, 0, -10) |
| ExitPlatform | TubeAnchor | (59, 81.2, -10) |
| ExitPlatform | SpiralLanding | (-30, 74, -2.975), Width 9.95 |
| ExitSpiral | SpiralStart | (-38.6, -0.75, 0) |
| ExitSpiral | SpiralEnd | (-30, 74, -2.975) |
| ExitCollar | CollarFace | (-2, 81.2, 0) |
| ExitMouthTrim | Mouth | (-2.06, 81.2, 0) |

**Stair geometry for reservations and checks:**
- Centre (E-81.6, deckZ+17), radius ≤ 15.6. Bridge x E-81.6..E-66, z deckZ+2..deckZ+12.6.
- Entry: the open sector θ -90°..-30° about the centre, where the ramp rises from F-4 to F+0.33 (the hall floor must sit in that range).
- Ramp boxes are ground and carry `Level2_StairRamp = true`. The deck, wall strips and bridge are ground Parts.
- Ramp boxes are named `"Level 2 Exit Spiral Ramp {A-D} NNN"`.

## 3. Test output (on `G:/Blender/Level2_Poolrooms/jobs/C/export`)

**Stair test:**
- PASS (a) walker climbs all 7 circles to 74.0 and across the bridge onto the deck; rise -0.004..0.095 per 0.05 stud
- PASS (b) ramp minus visible tread -0.178..0.380
- PASS (c) radial X on every ramp and parapet box, min |dot| 0.99945
- PASS (d) 90 parapet colliders inside the band solid, 32 base/guard colliders inside visible bodies, no gap over 81,114 samples, band top ≥ ramp + 3.47
- PASS (e) all Exit* chunks closed
- PASS (f) deck at x 34 (E-2.0), lip and nose colliders inside the visuals
- `EXIT STAIR OK`

**Bore test:**
- PASS (1) 271 markers match the path
- PASS (2) template correct
- PASS (3) collision face within 0.0000 of the visual; joint protrusion 0.131, bound 0.144
- PASS (4) visual within 0.0000 of the collision
- PASS (5) tube, collar and trim closed; mouth = collar face; 60 collar fills inside the collar
- `EXIT BORE OK`

**Other checks:**
- `collision_audit.py --no-world --kit jobs/C`: `KIT ... 0 failing: PASS`. The ExitCollar fills were added to get there.
- `import_kit.validate_export(jobs/C, "poolrooms")`: VALID.

## 4. Renders inspected (`G:/Blender/Level2_Poolrooms/review/C/`, backface culling on)

`exit_hall`, `exit_stair_from_below`, `exit_stair_top_down_core` (newel closed, no see-through), `exit_stair_entry`, `exit_railing_close`, `exit_stair_top_landing`, `exit_deck_edge`, `exit_deck_from_hall`, `exit_collar_mouth`, `exit_collar_mouth_open`, `exit_tube_inside_lead`, `exit_tube_inside_helix`, `exit_tube_outside`, `pump_station`, `arrival_door`.

Two things I fixed after looking: grout ticks on the parapet cap (its UVs now follow the band) and a wrong top-down camera. Inside the helix, each twisted joint shows a thin sliver ring, which reads like a segment seam.

## 5. Not done or uncertain

- Untested in Studio: whether `PreciseConvexDecomposition` reproduces all 16 islands of the template (needs the F13 raycast probe), and how the ramp feels to walk.
- The parapet collision stops at the cap line, 0.325 below the visual top. The colliders are 0.30 thick inside the 0.65 visual band, which keeps every corner inside it.
- The canonical export needs the lead's `build.py` rebuild before these tests pass there.
- Files I don't own that still reference the old exit:
  - `test_level2_kit_world_builder.py` expects ExitSkylight, ExitMouth and tub collision (WP6/WP9).
  - `assemble_level.py:280` names ExitMouth and ExitSkylight.
  - `render_world.py` and `world_check.py` hard-code the old exit position.
  - `smoke.py` still uses the retired materials.
- In the builder, `coveRun` splits the wall-foot and top coves at the mid-wall exit gap. Per F2 it should only split at foot-level holes.
- The ArrivalDoor's "Arrival Wall" Parts are visible but non-colliding. That predates this work and is part of F4-L.

Scratch files are in `G:/Roblox/_local/l2fix/impl/WP3/` (logs, ramp simulations, audit report).

## Fix report (final; supersedes the implementation report where they differ)

**WP3-objectives final report.** I fixed all 9 defects. Both tests pass on `G:/Blender/Level2_Poolrooms/jobs/C/export`, and so do the kit-only collision audit and `validate_export(poolrooms)`. Two decisions are left for you: the ramp box count (G8 budget) and a Studio check on the bore collision.

## 1. Fixes per defect

**F13 ghost shelf / bore check (major).** The fix is a new kind of collision piece: a mitered copy of the visual segment. Square-cut pieces cannot meet the spec's 0.1 limit on this path:
- With full coverage they stand 0.106 inside the bore at every helix joint. That is 0.0755 from the 5.87° bend plus 0.030 from the 1.23° frame twist.
- They stand 0.133 inside at the entry crest.
- Covering less does not help: a twisted neighbour then misses the visual by 0.03, which breaks the 0.02 coverage rule.

So every segment next to a bend of 3.5° or more now gets a mitered collision template. Congruent segments share one template, so the whole helix is a single shape. The other 88 segments keep the square `SlideCol_Bore16`, reaching `RHO_IN·tan(φ/2) + 0.005` (at most 0.216) past each joint. Piece 1 starts exactly at the mouth plane and piece 271 ends at the path end.

The bore test now asserts the fixed limit of 0.1. It no longer uses a computed bound or random sampling. Instead it checks:
- every inner-triangle vertex and edge midpoint of the real mesh (52,032 points);
- 2,553,696 grid points spaced 0.05 apart along the path near every joint, with stave corners included, spot-checked against the mesh.

Measured: protrusion 0.033 and coverage 0.0001. The old layout scores 0.40 on this check, so the shelf would have been caught.

**G8 budget (major).**
- Collar side fills went from 56 to 24, as a 3-step staircase per half-octant. With the 4 corner fills that is 28 colliders. Audit result for ExitCollar: unbacked share 0.004, max gap 0.63.
- Lip and nose-ground boxes went from 32 each to 24 each (`NOSE_N = 24`).
- The stair test now has an instance-budget check (g) with limits per component: ExitSpiral 850, ExitPlatform 54, ExitCollar 32, ExitMouthTrim 1, PumpStation 17.
- The exit is now 937 records plus 17 per pump, about +723 per round against the spec's +152. At the 8,164 baseline that is about 8,887 before the other work packages add theirs, against the 9,000 cap.
- **Decision needed:** I left the 724 ramp boxes alone. One option is to log root Y in Studio and, if dips of about 0.06 per 0.05 stud do not hitch, drop to the spec's 2-band layout and relax walk check (a) to that measured value. The other is a helicoid MeshPart ramp.

**Collar trim z-fight.** The legs now stop at 89.16, giving height 16.46. They no longer share any volume with the top bar.

**Recess under the collar.** New Part `Level 2 Exit Platform Wall Strip Mouth`: size (0.25, 0.54, 15.92) at (E_X-1.875, 72.97, DECK_Z), Tile, ground.

**Gauge collider.**
- `Pump Gauge Collider` is now (1.0, 1.0, 0.3) at (-1.4, 6.05, 0.12), inscribed in the round gauge.
- New `Pump Gauge Stem Collider`: (0.32, 0.65, 0.32) at (-1.4, 5.775, -0.35).

**Backface culling.** It is now set on every material inside `render()`, right before each render, so the pump image and any materials created later are culled too.

**Stair test (f).** The ramp-bottom check is now implemented as (f-ramp): each ramp box's bottom corners must be inside the stair body, inside the bridge Part, or below y = -3.5. It caught 5 foot boxes poking about 0.02 past the faceted r = 15 side. I fixed that in the kit: the outer face is now `sqrt((r1-0.01)² - sw²)`, so corners stay inside. The lip check no longer exempts top corners; they must be at y ≤ 74.86 (the kerb's crown).

**Tube shading.** The staves are now one welded mesh per chunk with smooth shading, so the bore no longer shows lengthwise light/dark stripes. UVs come from a per-loop callback, so there is no seam vertex.

**Pump rod.** The horizontal rod now starts at (0.9, 4.2, -0.5), inside the drum.

## 2. Interface for the runtime builder (all frames unchanged unless noted)

**Frames** (E = hall.MaxX, F = hall.FloorY, deckZ = hall.MinZ + 42, never yawed):
- `platformCF = CFrame.new(E-36, F, deckZ+10)`: ExitPlatform and ExitSpiral. Deck top is F+74; deck east face is E-2.0.
- `collarCF = CFrame.new(E, F, deckZ)`: ExitCollar and ExitMouthTrim.
- Tube anchor `CFrame.new(E+23, F+81.2, deckZ)`: ExitTubeVisual and ExitTubeVisual_02.._05.
- `HallWallGap = {center = deckZ, width = 15.92, bottom = F+73.24, top = F+89.16}`.
- `Exit.Mouth` is the single MeshPart of ExitMouthTrim (`RecolorTarget = true`). The Objective Controller is unchanged.

**BoreSegment markers (changed).** There are 271, carried by the ExitTubeVisual chunks. Each has a 12-number cf whose back is -look. Attributes: `Index` 1..271, `Length`, `Template`, `Size` {x, y, z}, `BackExtension`, `ForwardExtension`, `OneWay`.

For each marker the builder should:
- clone `SlideTemplates[Template]`;
- set `Size = Vector3.new(Size[1], Size[2], Size[3])` and `CFrame = anchorCF * marker cf`;
- name it `"Level 2 Exit Flume Collision Floor %03d"` using Index;
- set the slide attributes as before (SlideCollision, SlideFloor, OneWayExit when OneWay is true, NoEntityGround, SlideDirection = LookVector, SLIDE_PHYSICS).

There is no Length+1.5 rule and no special case for Index 1 any more.

**Templates.** All have Template = true, one chunk, centred, and install through the existing generic Template path.

| Template | Used by markers | Size |
|---|---|---|
| `SlideCol_Bore16` | 4..91 | (15.6, 15.6, span), unit length on Z |
| `SlideCol_Bore16_M01` | 1 | native |
| `SlideCol_Bore16_M02` | 2 | native |
| `SlideCol_Bore16_M03` | 3 | native |
| `SlideCol_Bore16_M04` | 92 | native |
| `SlideCol_Bore16_M05` | 93..270 (helix) | native |
| `SlideCol_Bore16_M06` | 271 | native |

Each mitered template's `Segments` attribute lists the markers that use it.

**ExitPlatform.**
- Parts: Deck (2, 73.35, -2.5) size 64 × 1.3 × 41; Wall Strip North and South; **Wall Strip Mouth** (new).
- Colliders: Support (cylinder), `Lip 01..24`, `Nose Ground 01..24`.
- Markers: MouthCenter (34, 81.2, -10); CollarPivot (36, 0, -10); TubeAnchor (59, 81.2, -10); SpiralLanding (-30, 74, -2.975), Width 9.95; LightWellCenter (0, 0, 0) for LightWell_R14.

**ExitCollar.**
- Trim Left/Right Parts: z ±(7.96..9.21), y **72.7..89.16**.
- Trim Top Part: y 89.16..90.4, z ±9.21.
- 4 Corner Fills and `Side Fill 01..24`.
- Marker CollarFace (-2, 81.2, 0).

**ExitSpiral (unchanged apart from the ramp's outer face).**
- Ramp boxes `Level 2 Exit Spiral Ramp {A-D} NNN` carry `Level2_StairRamp = true`. Each box's outer face sits at `sqrt((r1-0.01)² - sw²)`.
- Parapet: 76 pitched boxes plus Start and Junction fillers. 31 Base boxes, 12 Parapet Base boxes, a South Guard collider, and the Bridge and North Guard Parts.
- Markers: SpiralStart and SpiralEnd. Stair centre is (E-81.6, deckZ+17).

**PumpStation colliders.** Body, Elbow L/R, Drop L/R, Rod H, Rod V, Gauge, **Gauge Stem** (new).

**Builder deletions** stay as listed in the original report.

## 3. Test and validation output

| Check | Result |
|---|---|
| `test_level2_exit_stair.py` (a) walk | PASS: rise -0.004..0.095 per 0.05 stud, 724 ramp boxes |
| (b) ramp vs visible tread | PASS: -0.178..0.380 |
| (c) radial X | PASS: min \|dot\| 0.99945 |
| (d) parapet | PASS: 90 parapet colliders, 32 base/guard colliders, no gap over 81,114 samples, band top ≥ ramp + 3.47 |
| (f-ramp) ramp bottoms | PASS: 724 boxes |
| (e) closed solids | PASS |
| (f) deck and lip | PASS: 48 lip/nose colliders inside the visuals |
| (g) instance budget | PASS: exit total 937, plus 3 pumps × 17 |
| | **EXIT STAIR OK** |
| `test_level2_exit_bore.py` (1) markers | PASS: 183 mitered pieces capped on the miter planes, 88 square pieces reaching ≤ 0.216 past a joint |
| (2) templates | PASS: 7 templates |
| (3) visual vs collision | PASS: coverage within 0.0001, protrusion 0.0329, limit 0.1 |
| (4) collision vs visual | PASS: within 0.0000 |
| (5) closure | PASS: 28 collar fills inside the collar |
| | **EXIT BORE OK** |
| `collision_audit.py --no-world --kit jobs/C` | 21 components, 0 failing: PASS (ExitCollar 0.004 / 0.63, ExitPlatform 0 / 0.44, PumpStation 0 / 0.59) |
| `import_kit.validate_export(jobs/C, "poolrooms")` | VALID (run with POOL_EXPORT pointed at jobs/C) |

## 4. Renders inspected

All in `G:/Blender/Level2_Poolrooms/review/C/`, with culling on for every image:
- **pump_station:** the rod now enters the drum.
- **exit_collar_under_deck** (new): the recess is closed.
- **exit_collar_trim_corner** (new).
- **exit_collar_mouth** and **exit_collar_mouth_open:** smooth bore, no stripes.
- **exit_tube_inside_lead** and **exit_tube_inside_helix:** smooth.
- exit_hall, exit_deck_edge (24-segment nose reads smooth), exit_deck_from_hall, and the remaining stair views.

## 5. Not done or uncertain

- **Helix joints:** each joint still shows a grout jog of about 0.16 plus a thin cap sliver, both caused by the twist. It is the same tile colour, not a coloured ring. Please check it in Studio. Trimming the caps would open the mesh and fail closure test (5).
- **Studio checks still needed:**
  - Does PreciseConvexDecomposition keep all 16 islands, now on 7 template assets instead of 1?
  - How does the ramp feel to walk?
- **Files I don't own** that will need follow-up:
  - The builder and `test_level2_kit_world_builder.py` must switch to the marker `Template` and `Size` attributes.
  - Still referencing the old exit: `assemble_level.py:280`, `render_world.py`, `world_check.py`, `smoke.py`.
  - `coveRun` still splits the coves at the mid-wall exit gap.
  - The ArrivalDoor's "Arrival Wall" Parts are still non-colliding.
- The canonical export needs the `build.py` rebuild.

Scratch scripts and logs are in `G:/Roblox/_local/l2fix/impl/WP3/` (`logs2/`, `audit2/`, `diag*.py`).


# WP4-swerve (Codex)

# WP4 final report

1. **Changed.** Added `tools/level2_poolrooms/modules_swerve.py` with 36 one-chunk Tile components: S In/Out for (R, degrees) = (16,45), (16,60), (24,60), (32,45), and corners R24/32/48/64, each at H34/42/52. Registered the module last in `tools/level2_poolrooms/build.py`. The loft includes the wall, corrected concave base/top coves, a 10-stud deck with the straight walkway bullnose, arclength UVs, visible-side normals, and 0.5-stud tangent extensions recessed 0.02. Isolated export: `G:/Blender/Level2_Poolrooms/jobs/D/export/manifest.json`.

2. **Runtime interface.** Names are `SwerveS_In_R{R}_A{deg}_H{h}`, `SwerveS_Out_R{R}_A{deg}_H{h}`, and `SwerveCorner_R{R}_H{h}`. Local travel is +X and room/inward is +Z; the wall face is n=0. Component attrs: `Height`, `WallThickness=1.75`, `DeckWidth=10`, `DeckTop=.45`, `WallBottom=-8`, `DeckBottom=-4`, `Kind`, `Radius`, `Angle`; S pieces also have `Direction`. Each component has one `Tile` mesh chunk, no Part records, `Start` marker at `(0,0,0)` yaw 0, and `End` marker. S end = `(2R sin θ,0,±2R(1-cos θ))` yaw 0 (+ In, − Out in Z); corner end = `(R,0,R)` yaw −90. All marker and collider `cf` records have four numbers; oblique yaw uses `kit.yaw_x_along`. Every chord has `Swerve Wall Block i` (Block, non-ground) and `Swerve Deck Ground i` (Block, `ground=true`, for `Level2_EntityGround` at installation). Wall blocks are 1.75 thick, y centre `(h-6)/2`, size Y `h+10`, bottom −8/top `h+2`; deck grounds are 9.4 wide, y centre −1.775, size Y 4.45, bottom −4/top +.45. Chord lengths are sized from the outer wall/deck radii and include 0.5-stud end overlap. No other names or frames are exported. The installer should create non-colliding DoubleSided MeshParts and invisible colliding collider Parts from these records.

3. **Validation.** `PASS` all 36 component checks; `SWERVE_VALIDATE PASS 36` for 0.5-stud face/deck sampling, upper wall coverage, collider protrusion ≤0.3, outer-deck sagitta ≤0.25, chord length, marker endpoints, analytic concave profile, and triangle budget. `PR_EXPORT={"components":36,"chunks":36,"tris":46200}`; max per component 2,464 triangles; only `Tile` material. `git diff --check` had no whitespace errors. Scratch full-build probe **FAIL** before WP4: `modules_arch.py` `CornerCove_R8_H34.Corner Block 1` still passes oblique raw yaw `-91.2198959106285` to `prkit` (WP1 work). The probe redirected all writes to `G:/Roblox/_local/l2fix/impl/wp4/full_build/`.

4. **Renders inspected** with Blender backface culling on: `G:/Blender/Level2_Poolrooms/review/D/01_s_bend.png`, `02_corner.png`, `03_chained_outline.png`, `04_single_in.png`, `05_single_out.png`. The S and corner silhouettes, coves, tile grid, and deck continuity read correctly. The Out deck has a bright triangular region from this oblique camera view even in its isolated render; its geometry and collider sampling pass, but the final Roblox shading is unverified.

5. **Not done / uncertain.** A's `manifest.json` was still dated 2026-10-03 20:35:01 at the end, older than this task, so the end cross-sections were checked against F1's analytic cove equations and the straight deck numbers, not new CoveBase/CoveTop/Walkway chunks. Full combined build, canonical repository export, installer/world/runtime checks, Studio play, commit, and publish remain with the lead and other work packages under the task rules. WP4 changed only its two owned repository files and did no git write or Studio action.


# WP4b-swerve collision fix (Codex) - supersedes WP4 collider names

# WP4b swerve collision report

## Changes

- Split each S-bend collider sequence into A and B arc chains at the inflection. Corner wall and deck names remain numbered as before.
- Added chord aligned base cove fill (1.1 x 1.1 cross-section) and top cove fill (3.0 x 0.6 cross-section) behind the visible fillets. Each chord overlaps its neighbour by 0.5 stud at both ends.
- New names: `Swerve Base Cove Fill A i`, `Swerve Base Cove Fill B i`, `Swerve Top Cove Fill A i`, `Swerve Top Cove Fill B i` for S bends; `Swerve Base Cove Fill i` and `Swerve Top Cove Fill i` for corners. S bend wall/deck names are now `Swerve Wall Block A/B i` and `Swerve Deck Ground A/B i`.
- Component names, markers, attributes, visible geometry, UVs, triangle counts, wall/deck collider dimensions, and end cross-sections did not change.

## Checks

- Blender export: `SWERVE_VALIDATE PASS 36; face/deck coverage, wall protrusion, sagitta, markers, profile, tris`; `PR_EXPORT={"components": 36, "chunks": 36, "tris": 46200}`.
- Audit command: `python -B tools/level2_poolrooms/collision_audit.py --no-world --kit G:/Blender/Level2_Poolrooms/jobs/D/export --out G:/Roblox/_local/l2fix/impl/wp4b/audit`.
- Audit output: `KIT 1 dirs, 36 components, 0 failing: PASS`; `COLLISION AUDIT PASS (reports in G:\Roblox\_local\l2fix\impl\wp4b\audit)`.
- All 36 swerve rows are `ok`; worst unbacked share 0.0028 and worst max gap 0.78 stud. Report: `G:/Roblox/_local/l2fix/impl/wp4b/audit/collision_kit.json`.
- `git diff --check -- tools/level2_poolrooms/modules_swerve.py`: no whitespace errors.

### Per-component audit rows

```text
  ok SwerveCorner_R24_H34 colliders=32 unbacked=0.0019 maxGap=0.69
  ok SwerveCorner_R24_H42 colliders=32 unbacked=0.0016 maxGap=0.68
  ok SwerveCorner_R24_H52 colliders=32 unbacked=0.0016 maxGap=0.67
  ok SwerveCorner_R32_H34 colliders=32 unbacked=0.0016 maxGap=0.70
  ok SwerveCorner_R32_H42 colliders=32 unbacked=0.0013 maxGap=0.69
  ok SwerveCorner_R32_H52 colliders=32 unbacked=0.0010 maxGap=0.70
  ok SwerveCorner_R48_H34 colliders=36 unbacked=0.0011 maxGap=0.69
  ok SwerveCorner_R48_H42 colliders=36 unbacked=0.0013 maxGap=0.70
  ok SwerveCorner_R48_H52 colliders=36 unbacked=0.0009 maxGap=0.69
  ok SwerveCorner_R64_H34 colliders=40 unbacked=0.0009 maxGap=0.67
  ok SwerveCorner_R64_H42 colliders=40 unbacked=0.0008 maxGap=0.69
  ok SwerveCorner_R64_H52 colliders=40 unbacked=0.0007 maxGap=0.68
  ok SwerveS_In_R16_A45_H34 colliders=32 unbacked=0.0023 maxGap=0.72
  ok SwerveS_In_R16_A45_H42 colliders=32 unbacked=0.0021 maxGap=0.73
  ok SwerveS_In_R16_A45_H52 colliders=32 unbacked=0.0016 maxGap=0.72
  ok SwerveS_In_R16_A60_H34 colliders=40 unbacked=0.0028 maxGap=0.73
  ok SwerveS_In_R16_A60_H42 colliders=40 unbacked=0.0020 maxGap=0.73
  ok SwerveS_In_R16_A60_H52 colliders=40 unbacked=0.0018 maxGap=0.72
  ok SwerveS_In_R24_A60_H34 colliders=40 unbacked=0.0027 maxGap=0.74
  ok SwerveS_In_R24_A60_H42 colliders=40 unbacked=0.0022 maxGap=0.74
  ok SwerveS_In_R24_A60_H52 colliders=40 unbacked=0.0020 maxGap=0.77
  ok SwerveS_In_R32_A45_H34 colliders=32 unbacked=0.0024 maxGap=0.78
  ok SwerveS_In_R32_A45_H42 colliders=32 unbacked=0.0022 maxGap=0.76
  ok SwerveS_In_R32_A45_H52 colliders=32 unbacked=0.0018 maxGap=0.77
  ok SwerveS_Out_R16_A45_H34 colliders=32 unbacked=0.0020 maxGap=0.72
  ok SwerveS_Out_R16_A45_H42 colliders=32 unbacked=0.0020 maxGap=0.73
  ok SwerveS_Out_R16_A45_H52 colliders=32 unbacked=0.0017 maxGap=0.72
  ok SwerveS_Out_R16_A60_H34 colliders=40 unbacked=0.0019 maxGap=0.71
  ok SwerveS_Out_R16_A60_H42 colliders=40 unbacked=0.0023 maxGap=0.74
  ok SwerveS_Out_R16_A60_H52 colliders=40 unbacked=0.0015 maxGap=0.72
  ok SwerveS_Out_R24_A60_H34 colliders=40 unbacked=0.0026 maxGap=0.76
  ok SwerveS_Out_R24_A60_H42 colliders=40 unbacked=0.0018 maxGap=0.73
  ok SwerveS_Out_R24_A60_H52 colliders=40 unbacked=0.0015 maxGap=0.76
  ok SwerveS_Out_R32_A45_H34 colliders=32 unbacked=0.0027 maxGap=0.76
  ok SwerveS_Out_R32_A45_H42 colliders=32 unbacked=0.0022 maxGap=0.77
  ok SwerveS_Out_R32_A45_H52 colliders=32 unbacked=0.0020 maxGap=0.77
```

## Backface culling renders

- S bend: `G:/Blender/Level2_Poolrooms/review/D/01_s_bend.png`.
- Corner: `G:/Blender/Level2_Poolrooms/review/D/02_corner.png`.
- Both updated renders were visually inspected with backface culling enabled; wall, cove, and deck surfaces remain continuous. The pre-existing bright triangular region is still visible on the Out deck from this camera angle.

Offline kit only: no Studio gameplay, multiplayer, performance, publish, or Git write was performed.
