# Analysis of the owner's second fix list (9 analysts, 2026-10-04)

## F7+F14 - Every ceiling opening hangs below or frames the ceiling: LightWell_R6 is an 8.5-stud block under the ceiling, ExitSkylight is a square 32x28 hole with a thin ring and a 60-wide frame 1 stud below the ceiling, and the spiral collar has a 0.25 lip

**rootCause:** Three different openings, none of them flush with the ceiling. The runtime builder and the kit do not agree on where the ceiling plane is. The ceiling is a 2.5-thick 'Level 2 Overhead Tile' slab from C to C+2.5 (C = FloorY+CeilingClass). The roof collider sits at C+1.5..C+2.5. ceilingShell cuts an exact square of side `panel` and leaves it completely empty.
(1) LightWell_R6: the builder pivots it at C-8 (Kit World Builder lines 748 and 756). tiled_opening (modules_arch.py 343-383) is a closed solid collar from base-0.25 to base+8.25, with an outer square of panel/2+0.5 = 12.5 against a 12 cut. So in the hall it is a 25x8.5x25 block hanging 8.25 below the ceiling with a 12-wide round hole in it (image 6).
(2) ExitSkylight (objectives.py 334-348) has 4 Parts at local y 95..96. The ExitHall ceiling is at 96, so they hang 1 stud below it. They reach +-30/+-32 against the 32x32 cut, which gives the stepped frame. The space between them is a 32x28 rectangle. The 'ring' is a single-surface lathe at radius 14 (95..101.4) with no annular plate, so you see a square hole to the sky with a thin circle inside (image 14). The builder places it at floor level (line 752).
(3) The SpiralStairWell collar uses the same tiled_opening at base=Height. Its bottom ring sits at C-0.25 with half 16.5*s against a 16*s cut, which leaves a 0.25 lip. The whole collar box rises to C+8.25, sticking 5.75 above the roof (image 9).
The Blender review assembly (assemble_level.py 117-136) put LightWells AT the ceiling plane, so the approved renders never showed the runtime fault. The offline oracle (test_level2_kit_world_builder.py 1398-1430) checks only that the open-sky markers are not covered. It never checks heights, so all of this passed.

**occurrences:** Measured over the real builder output for 40 seeds (837834, 1, 101 + 37 test-sequence seeds; 1065 openings; scratch G:/Roblox/_local/l2fix/F7F8F14/openings_audit.py -> openings.json, audit40.txt):
- LightWell_R6: 939/939 have pivot C-8, bottom C-8.25, outer half 12.5 vs cut 12. Hall Types: ColumnHall 323, PaddlingRoom 200 (Kids Area; the PumpIndex ones at the centre), CurvedChannel 195, VaultArcade 139, PumpHall 80, CorridorHall 2. Entity Den / Den B halls are typed ColumnHall/VaultArcade and are included. That is every non-small hall except BigPool, Arrival, SpiralWell and ExitHall: 19-29 per map, mean 24.1 (400 seeds).
- ExitSkylight: 40/40 (one per map, ExitHall) have bottom C-1.0, frame half 32 vs cut 16, open rectangle 32x28.
- SpiralStairWell_H42/H52: 86/86 have the 0.25 lip and the collar to C+8.25.
- LightWell_R10: exported but never placed by the builder; the kit fix still applies.
- LightRound (BigPool) and VaultBay are not openings. Chambers (Small, ceiling 15) have no ceiling openings.

**fixDesign:** Same idea as the KIT_SPEC section 6 tunnel collar: a flush tiled plate whose OUTER edge is exactly the ceiling cut square and whose INNER edge is the circle, with a tiled shaft going up and nothing below the ceiling plane.

KIT (modules_arch.tiled_opening, used by LightWell_R*, SpiralStairWell_H* and the new ExitSkylight):
- Every ring that is now at base-0.25 moves to base. The bottom face is the flat square annulus at y=base: ('square', base, panel/2) -> ('round', base, r+.55). The round-over goes UP into the hole: ('round', base+.41, r+.18), ('round', base+.71, r). The shaft wall r runs to base+depth-.46. The top lip stays as is but ends at base+depth: ('round', base+depth, r+.55), ('square', base+depth, panel/2).
- Outer square = panel/2 EXACTLY (drop the +.5), so the plate's outer side faces sit on the slab's cut faces. That leaves no overlap band (no z-fight, no lip) and no gap.
- Collar colliders: vertical=(base+depth/2, depth), i.e. base..base+depth, never below base. outside=(panel/2)*sqrt(2).
- Keep depth 8: the shaft is C..C+8, 5.5 above the 2.5 roof, visible only through the hole.
- Export attrs PanelSize (24 for R6, 32 for R10/R14/spiral) and ShaftDepth. Add PanelSize=32 to the spiral's attrs.
- light_well: loop `for r in (6,10,14)` with panel 24 if r==6 else 32. 32 > 2*(14+1.15) = 30.3, so the existing validate() rule holds.
- Rewrite objectives.skylight() as `tiled_opening(m,14,32,0,8)`, keeping the name ExitSkylight and the marker LightOpening at (0,8,0). Delete the four 'Level 2 Exit Overhead Tile' Parts and the thin lathe.

BUILDER (Kit World Builder):
- Line 748 and line 756: `CFrame.new(p+Vector3.yAxis*hall.CeilingClass)` (was CeilingClass-8).
- Line 752: `CFrame.new(p+Vector3.yAxis*hall.CeilingClass)` (was the floor pivot).
- The cuts stay 24 / 32 / 32*scale. They now equal the plate outer square exactly. Read them from template:GetAttribute('PanelSize') (the installer copies component attrs to the Model, import_kit.py line 511) so kit and builder cannot drift again.
- ceilingShell: per opening add one 'Level 2 Sky Cap <hall>' Part, size (2*Half, 1, 2*Half) at y C+2 (the roof-collider band). Settings: Transparency 1, CastShadow false, CanCollide true, CanQuery false (so light, camera and the open-sky oracle ignore it), CanTouch false, plus roof() for the Level2Roof modifier. Collision is then closed at every opening while the hole stays visually open.
- Minor: LightRound at C-.55 instead of C-.6 so its bezel touches the ceiling (today there is a 0.05 gap).

BLENDER REVIEW: assemble_level.py must use the same cut (panel, not r+5) and the same pivot, so renders match the runtime.

**check:** KIT (in modules_arch.validate and the objectives build, over the export): for every component with a PanelSize attr (LightWell_*, SpiralStairWell_*, ExitSkylight), with base = 0 or Height:
(a) No mesh vertex has y in [base-3, base) inside the panel square |x|,|z| <= panel/2+.01. Spiral treads now end at Height-14 and the core has vertices only at 0 and Height+8, so this holds and catches any hanging block or lip.
(b) The vertices at y==base reach max(|x|,|z|) == panel/2 +-1e-4 (the plate's outer edge equals the cut).
(c) No collider has a bottom below base-0.01, except the spiral Stair Ground and Core Block colliders.

WORLD (new block in check_snapshot, test_level2_kit_world_builder.py, default 10 seeds; run 40+ locally). For each opening model, with C = FloorY+CeilingClass:
(d) Pivot y == C for LightWell/ExitSkylight. For the spiral, pivot y == FloorY and Height == CeilingClass.
(e) The Overhead Tile strips of the hall exactly frame each opening: the nearest strip edges are at X+-Half and Z+-Half within .01, and Half == PanelSize*scale/2. Also sum(strip areas) + sum(cut areas) == Width*Depth within 0.1, with no strip overlapping another.
(f) A 'Level 2 Sky Cap' that is CanCollide, not CanQuery, covers the full cut square at y in [C+1.5, C+2.5].
(g) No visible Part or MeshPart other than the opening's own component has its OBB inside the prism cut square x [C-12, C+2.5]. Corner coves are tested exactly instead of by AABB: for a corner of radius R with arc centre O, every point of the cut square inside the RxR corner box satisfies |P-O| <= R-3.5, which keeps it clear of the top-cove band. This catches the VaultBay groin.
Mutation: shift one LightWell pivot by -1 in memory and assert (d) and (a) fire; drop one Sky Cap and assert (f) fires.
The prototype at G:/Roblox/_local/l2fix/F7F8F14/openings_audit.py already measures pivotRel, bottomRel, outerHalf vs cutHalf, caps and intrusions on dumps. Today it reports 1065/1065 failing at least one of these.

**risks:** - The tile grid may not line up across the plate/slab seam. The plate's underside UV is planar (co.x, co.y); the ceiling Part's MaterialVariant tiling origin is per Part face. I am not sure it aligns: settle it with one Studio screenshot looking up at a well. If it does not align, snap opening centres so the cut edges fall on the tile pitch.
- The kit must be re-exported and re-installed (new mesh asset ids). The ExitSkylight name is kept, so test line 909 still matches, but line 1409's model matching needs the new pivot.
- The Sky Cap must stay CanQuery=false or the open-sky oracle (it matches 'Roof Collider' and 'Overhead Tile' names) and sunlight/camera raycasts would see it.
- The shaft above the roof is unchanged in height (8). Sun-patch behaviour should not change, but verify in Studio.

**files:** tools/level2_poolrooms/modules_arch.py, tools/level2_poolrooms/objectives.py, ServerScriptService/Level 2 Systems/Level 2 Kit World Builder.ModuleScript.lua, tools/level2_poolrooms/assemble_level.py, tools/tests/test_level2_kit_world_builder.py, artifacts/level2-poolrooms-20261003/KIT_SPEC.md (section 6: add the ceiling-opening contract next to the tunnel collar)

**refs:** ServerScriptService/Level 2 Systems/Level 2 Kit World Builder.ModuleScript.lua:381-388 (openSky: Half=panel/2); ServerScriptService/Level 2 Systems/Level 2 Kit World Builder.ModuleScript.lua:390-425 (ceilingShell: slab C..C+2.5 non-colliding, roof collider C+1.5..C+2.5, cut cells left empty); ServerScriptService/Level 2 Systems/Level 2 Kit World Builder.ModuleScript.lua:746-749 (PumpHall/PumpIndex LightWell_R6 at CeilingClass-8, cut 24); ServerScriptService/Level 2 Systems/Level 2 Kit World Builder.ModuleScript.lua:750-753 (ExitSkylight at floor pivot, cut 32); ServerScriptService/Level 2 Systems/Level 2 Kit World Builder.ModuleScript.lua:754-758 (generic LightWell_R6 at CeilingClass-8, cut 24); ServerScriptService/Level 2 Systems/Level 2 Kit World Builder.ModuleScript.lua:729 (spiral cut 32*scale); tools/level2_poolrooms/modules_arch.py:343-383 tiled_opening (rings at base-.25, outer square panel/2+.5, collar colliders vertical=(base+depth/2, depth+.5)); tools/level2_poolrooms/modules_arch.py:465-470 light_well (panel 24 for R6, 32 for R10); tools/level2_poolrooms/modules_arch.py:406 spiral: tiled_opening(m,12,32,height,8); tools/level2_poolrooms/objectives.py:334-348 skylight() (4 overhead Parts at y95.5 size 60x1x18/14x1x28 + thin lathe r14); tools/level2_poolrooms/assemble_level.py:117-136 (review assembly places wells at the ceiling, cut r+5: diverges from runtime); tools/tests/test_level2_kit_world_builder.py:1398-1430 (sky oracle has no vertical/flush check)

## F8 (stairs) - Spiral stair top tread is exactly at the ceiling plane under an uncapped hole: a player stands at C and jumps to C+7.2, 1.05 short of the collar rim (C+8.25)

**rootCause:** modules_arch.spiral(height) (lines 386-409) runs the treads to `top=(i+1)*rise` up to height. validate() line 557 even asserts `max(tread top)==height`. The builder uses suffix h=min(CeilingClass,52) and SpiralWell halls are 42 or 52, so Height == CeilingClass and the last 4x0.8x4 'Stair Ground' collider has its top at C. Its 0.28 curb is visual only. ceilingShell leaves the cut square without any collider, and nothing caps the shaft. GameManager.Script.lua:1153 sets JumpPower 50 (Roblox quotes JumpHeight 7.2 for this; physics gives 6.37 at gravity 196.2, and the game never changes gravity). Feet reach C+7.2 and the head (R15 ~5.2) reaches C+12.4, well into the shaft and past the roof top (C+2.5), so the player can see over the roof. The rim is C+8.25: 'almost jump out' is literal, and any higher JumpPower, a speed glitch or a flinging teammate gets out.

**occurrences:** Every SpiralStairWell_H42 and H52 in every SpiralWell hall: 86/86 in 40 maps have stairTopRel 0.0, capped false. No other standable surface comes near an opening: the next highest is the ExitHall spiral/platform at 74 against a 96 ceiling (C-22). LightWell halls have nothing climbable above C-29 (pump body), and decks and water floors are lower. The exit flume floor at C-5 showed up only through a crude AABB and lies outside the hall wall, 39.5 studs from the skylight. ExitSpiral (objectives.py 229-276) ends at 74 = C-22, which is fine.

**fixDesign:** Numbers: with jump 7.2 and character 5.2, head apex = T + 12.4. Rule: T <= C - 14 for every standable surface within (cut half + 10) studs horizontally of an opening. That leaves 1.6 studs of clearance between the jumping head and the ceiling underside, and the eye (T+11.8) stays at C-2.2, so nobody sees into the shaft or over the roof.

Kit spiral(height):
- `stair_top = height - 14` (H42 -> 28, H52 -> 38). count = ceil(stair_top/.78) gives 36 treads at rise .778 (H42) and 49 at .776 (H52).
- Treads end on a quarter-turn landing at stair_top: one arc_solid spanning 90 deg at radius 5..11.3 plus 3 Stair Ground 4x.8x4 colliders along it.
- Core lathe and Core Block stay 0..height+8 (the column rises into the light well).
- Export attrs StairTop=stair_top and PanelSize=32. StairEnd marker at (8, stair_top, 0).
- validate(): `max(tread top) == attrs.StairTop <= attrs.Height - 14`.

Collision: the Sky Cap from the F7+F14 design (invisible, CanCollide true, CanQuery false, 2*Half x 1 x 2*Half at C+2) closes every opening at the roof band. Escape is then impossible even with abnormal jump or fling, and the hole still renders open.

**check:** Kit: validate() asserts the StairTop rule above.
World (check_snapshot, every seed): for each opening, take every CanCollide part that is ground-tagged (Level2_EntityGround, or a name containing 'Ground', or 'Walkway Deck') and whose OBB lies within cut half + 10 of the opening centre. Assert top <= C-14 (C = FloorY+CeilingClass). For each SpiralStairWell, assert max('Stair Ground*' top) == FloorY + CeilingClass - 14 +-.01. The Sky Cap assertion is shared with F7+F14.
Prototype: openings_audit.py 'reachRel'/'stairTopRel'. Today 86/86 spirals report 0.0.
Mutation: raise one tread to C-13 in memory and the check must fail.

**risks:** The 14-stud rule is conservative for R15 at JumpPower 50. If the owner wants the stairs visibly closer to the hole, C-12.4 is the absolute floor before the head touches the ceiling plane, and the cap still prevents escape. A landing that ends in mid-air at 28-38 studs is a design call (stairs to nowhere). Fall damage is not modelled in Level 2 as far as I can see, so a fall from the landing is harmless.

**files:** tools/level2_poolrooms/modules_arch.py, ServerScriptService/Level 2 Systems/Level 2 Kit World Builder.ModuleScript.lua, tools/tests/test_level2_kit_world_builder.py

**refs:** tools/level2_poolrooms/modules_arch.py:386-409 spiral() (count=ceil(height/.78), treads to height, core lathe 0..height+8, collar tiled_opening at height); tools/level2_poolrooms/modules_arch.py:553-558 validate() asserts the top tread == height; ServerScriptService/Level 2 Systems/Level 2 Kit World Builder.ModuleScript.lua:706-731 SpiralWell dressing (suffix _H min(CeilingClass,52), scale (footprint-2)/32); ServerScriptService/Level 2 Systems/Level 2 Kit World Builder.ModuleScript.lua:390-425 ceilingShell (no collider over the cut); ServerScriptService/GameManager.Script.lua:1152-1153 (JumpPower 50)

## F8 (count) - Spiral wells are overused: mean 2.57 per map, up to 7, about 94% of maps have at least one, and the owner's seed 837834 has 4

**rootCause:** Kit Layout Generator HALL_TYPES (lines 26-30) gives SpiralWell weight 10 of 100. drawHallType (lines 442-455) rerolls whenever the rolled type is not allowed for the hall. BigPool needs Area >= 24000, VaultArcade needs ceiling 34/42 and >= 96, CorridorHall needs aspect >= 2.2, so most lattice halls reject much of the weight. Every always-allowed type, SpiralWell included, therefore gains share: measured 13.9% of ordinary halls over 400 seeds. Nothing limits the count per layout.

**occurrences:** 400 seeds (G:/Roblox/_local/l2fix/F7F8F14/count_types.py). Spiral wells per map: {0:23, 1:67, 2:113, 3:100, 4:65, 5:19, 6:11, 7:2}, mean 2.57. Seeds 1 and 101 have 2 each, 837834 has 4. Spiral ceilings: 52 x562, 42 x466. Only ordinary 'Hall' role halls can be SpiralWell; Entity Den halls are typed ColumnHall/VaultArcade.

**fixDesign:** Cap at 1 per map without disturbing the rest of the layout stream:
- Add `local MAX_SPIRAL_WELLS = 1`.
- Give drawHallType an `exclude` argument: `if entry.Name ~= exclude and allowedHallType(hall, entry.Name) then return entry.Name end`.
- After the per-hall typing loop in decorate() (after line 504), add:
```
local capRng, spirals = Random.new(layout.Seed + 0x5917), 0
for _, hall in ipairs(layout.Halls) do
  if hall.Type == "SpiralWell" then
    spirals += 1
    if spirals > MAX_SPIRAL_WELLS or math.min(hall.Width, hall.Depth) < 128 then
      hall.Type = drawHallType(capRng, hall, "SpiralWell")
    end
  end
end
```
The separate RNG leaves typeRng and rng untouched, so every other hall of every seed is unchanged. The 128 minimum makes the unscaled 40-stud pocket geometrically possible (pocket centre |d| >= 37 and <= half-26 needs half >= 63) and avoids the shrunken spirals (see otherProblemsSeen). The raised CeilingClass 42/52 stays valid for every redrawn type.
- Validate: count SpiralWell <= MAX_SPIRAL_WELLS, else bad('spiral count'). Validate also already rejects SpiralWell with ceiling 34.
- Expected result: at most 1 per map. The share drops to about 3-5% of ordinary halls. The exact value depends on how many SpiralWell draws land in halls with min side >= 128; I did not measure it, the 400-seed report will.

**check:** test_level2_kit_layout.py (400 seeds): assert each layout has <= 1 Type=='SpiralWell', and that the spiral hall has min(Width,Depth) >= 128. Replace the SpiralWell share band (.09,.19) with the newly measured band, and assert at least 50% of layouts still have one so the feature is not lost. Mutation: set MAX_SPIRAL_WELLS=2 in memory and assert the per-layout assertion fails for some seed. In the world builder test, assert at most one SpiralStairWell_ model per build and that its HorizontalScale attribute == 1.

**risks:** Changing the Types of the dropped halls changes their dressing, light-well count and collider set, so world-test expectations tied to specific seeds (837834) will move. If a SpiralWell hall with min side >= 128 still finds no 40 pocket because door spokes block every corner, the builder falls back to 32 (scale .9375). I am not sure this cannot happen; a 400-seed world run settles it.

**files:** ServerScriptService/Level 2 Systems/Level 2 Kit Layout Generator.ModuleScript.lua, tools/tests/test_level2_kit_layout.py

**refs:** ServerScriptService/Level 2 Systems/Level 2 Kit Layout Generator.ModuleScript.lua:26-30 HALL_TYPES; ServerScriptService/Level 2 Systems/Level 2 Kit Layout Generator.ModuleScript.lua:430-455 allowedHallType / drawHallType (rejection redraw); ServerScriptService/Level 2 Systems/Level 2 Kit Layout Generator.ModuleScript.lua:486-504 decorate typing loop (SpiralWell forces CeilingClass 42/52 at 491-493); ServerScriptService/Level 2 Systems/Level 2 Kit Layout Generator.ModuleScript.lua:928-933 Validate hall type; tools/tests/test_level2_kit_layout.py:526-531 share band SpiralWell (.09,.19)

## F7 (VaultArcade) - In VaultArcade halls the light well falls back to the hall centre, where the four groin-vault bays meet and hang 12 studs below the ceiling across the hole

**rootCause:** Generic light well (Kit World Builder lines 754-758): `reservePocket(hall,doors,36,36,reservations) or center(hall)`. A 36 pocket must keep its centre >= 35 from both centre axes and stay inside the walls. In VaultArcade halls up to about 144 wide that fails, and the well goes to the exact centre. The VaultArcade branch (573-607) places four VaultBay32 domes at (+-16, +-16) covering +-32 and never reserves them. A bay dome's rim (spring) is 12 below the ceiling at its edges, so the centre cut square sits on the groin, and even pocketed wells reach the bay corner region. The current LightWell block also clips straight through the domes.

**occurrences:** 40 maps: 54 of 139 VaultArcade light wells intersect a VaultBay32_H34/H42, all of them at the centre fallback (56 at the centre). Seed 837834: halls 4 (144x120) and 42 (120x152). The centre fallback is also used by 179/323 ColumnHall, 81/195 CurvedChannel and 2 CorridorHall wells. No ceiling-reaching geometry sits at the centre in those Types (columns, curve walls and piers keep >= 17+w/2 off the centre axes), so they are clean. PumpHall and pump PaddlingRooms are centred on purpose.

**fixDesign:** In the VaultArcade branch, append each placed bay to reservations as {Position=bay, Width=32, Depth=32}; the fallback bay goes in too. For kind=='VaultArcade', drop the `or center(hall)` fallback and skip the light well when no pocket clears the bays. A cut square needs |c| >= 32+12 on one axis and a wall margin (c <= half-18), so halls narrower than about 124 on both axes get no skylight. In the Type contract that becomes 0 openings allowed for VaultArcade. The vaults are their own ceiling feature, and a skylight is not needed for lighting.

**check:** Check (g) from F7+F14 over every seed: no non-own visible geometry in the prism cut square x [C-12, C+2.5]. Today it flags exactly these 54 VaultBay cases plus the corner-cove false positives, which the exact arc test removes. Also assert that no VaultArcade light well's cut square intersects any VaultBay footprint square (bay pivot +-16).

**risks:** Fewer skylights in small vault halls (roughly 40% of VaultArcade halls lose theirs). If the owner wants a skylight in every hall, the alternative is an oculus cut into a bay crown, which needs a new vault mesh with a hole.

**files:** ServerScriptService/Level 2 Systems/Level 2 Kit World Builder.ModuleScript.lua, tools/tests/test_level2_kit_world_builder.py (line 1403: allow 0 sky for VaultArcade; line 940 LightWell requirement)

**refs:** ServerScriptService/Level 2 Systems/Level 2 Kit World Builder.ModuleScript.lua:754-758 (center(hall) fallback); ServerScriptService/Level 2 Systems/Level 2 Kit World Builder.ModuleScript.lua:573-607 VaultArcade (bays placed at lines 589 and 598, not reserved); ServerScriptService/Level 2 Systems/Level 2 Kit World Builder.ModuleScript.lua:492-503 placeVaultBay; tools/level2_poolrooms/modules_arch.py:412-438 vault() (y = height-12 + 12*sqrt(1-(max|x|,|z|/16)^2))

### Other problems seen
- Scaled spiral wells (footprint 32/26/20/16 -> HorizontalScale .9375/.75/.5625/.4375; 31 of 86 spirals in 40 maps) have a real-Roblox collision bug. The installer's nativeCylinder (tools/level2_blender/import_kit.py 467-472) gives Core Block Size=(H+8,10,10) rotated 90 deg about Z, so its local X is VERTICAL. Kit World Builder lines 715-721 scale p.Size.X, so the core collider's HEIGHT shrinks to (H+8)*s, still centred at (H+8)/2. Example H52, s=.5625: the collider covers 13.1..46.9, so you walk through the lowest 13 studs of the visible column. The offline fake engine stores the cylinder as (10,H+8,10) with identity rotation and cannot see this. Treads become 1.75-2.25 wide at the small scales. Recommend footprints {40} only (or {40,32}) and scaling only world-horizontal axes (transform the size through the part rotation).
- Scaled spirals placed in an R24-corner hall (max side >200 or PaddlingRoom) put their cut corner at (7,7) from the hall corner. That is 24.04 from the corner arc centre (24,24), i.e. inside the CoveTopCorner_R24 band (21..24) and a 0.04 sliver of the CornerCove solid, so the corner cove passes under or into the opening. Unscaled 40 pockets give (10,10), 19.8, which is clear.
- LightRound (BigPool, Kit World Builder line 553) is placed at C-0.6 while the bezel is 0.55 tall, leaving a 0.05 gap to the ceiling. Use C-0.55.
- tools/level2_poolrooms/assemble_level.py 117-136 (owner review renders) places LightWells AT the ceiling plane and cuts r+5. It diverges from the runtime builder (C-8, cut panel), so the approved renders never showed F7. The assembly should call the same placement rules or be generated from the builder dump.
- drawHallType's rejection redraw silently inflates every always-allowed Type: SpiralWell 10% -> 13.9%, ColumnHall 25% -> 35.5%, CurvedChannel 20% -> 27.3%. The weights in HALL_TYPES are not the shares the owner sees.
- WallVoid side Parts ('Void Side -1') are collidable ledges about 6-13 studs below the ceiling near some light wells. They are unreachable from the floor today; once a cap and reach check exist they are the next things to watch if anything climbable is added.
- test_level2_kit_world_builder.py 1398-1430 verifies only that sky markers exist and are not covered, so a well hanging 8 studs low, an uncapped hole or a stair reaching the ceiling all pass. That is the root of 'tested but wrong'.

### Notes
I ran the real builder over 40 seeds and the real layout generator over 400, all read-only, with scratch output only in G:/Roblox/_local/l2fix/F7F8F14/:
- count_types.py: spiral counts and Type shares from the layout generator, 400 seeds.
- openings_audit.py: runs the offline world-builder harness with dump_world.instrument and measures every opening's pivot/bottom/top relative to the ceiling, plate outer half vs ceiling cut half, spiral stair top, cap presence, intrusions into the cut prism, and the highest standable surface within cut+10. It is the prototype for the proposed check.
- openings.json and audit40.txt: the results.

Images match the numbers:
- 6 is LightWell_R6: a 25x8.5x25 collar, top at C+0.25, bottom at C-8.25, 12-wide hole.
- 14 is ExitSkylight: a 32x28 rectangle between plates hanging at 95..96 under a 96 ceiling, with a single-surface r14 lathe ring.
- 9 is the SpiralStairWell collar box sticking 5.75 above the roof, with the core to C+8 and the top tread at C.

How the builder cuts: ceilingShell builds non-colliding 2.5-thick Overhead Tile strips (C..C+2.5) around exact squares of side panel (24 / 32*scale / 32). It adds roof colliders (C+1.5..C+2.5) only on the strips, so every opening is open for collision today. openSky markers are read by nothing at runtime, only by the offline test.

Uncertain and needs Studio:
- Whether the MaterialVariant tile grid lines up across the plate/slab seam.
- The real convex hulls of the new plates.
Neither is reachable offline. Blender was not needed: the dumps plus the kit manifest carry the exact numbers.

## F6 - Two different tile whites: every kit piece (collars, coves, walkways, light wells, chamber walls) is Color 255,255,255, every builder Part (hall walls, floors, ceilings, lintels, sills) is 241,237,220

**rootCause:** Two separate constants, both on the same 'PR Tile' and 'PR Tile Aqua' variants. tools/level2_poolrooms/prkit.py:28-31 PALETTE gives Tile and Aqua a tint of (255,255,255). import_kit.py copies that to Part.Color on every kit MeshPart and kit Part record (import_kit.py:483 for meshes, :528 for parts). The Kit World Builder paints its own Parts WHITE = Color3.fromRGB(241,237,220) (WB:9, used by part() at WB:19-24). So a kit collar standing flush in a builder wall is about 6% lighter and 14% less yellow in blue. Image 5 measured: wall (116,102,67) against collar (126,115,87). The tile scale is NOT the cause: the grout period measured in image 5 is 8.5 px on both the wall Part and the collar MeshPart, so mesh UVs at 1 repeat per 4.8 studs match StudsPerTile 4.8. That also answers KIT_SPEC section 9 question 1 empirically. A second, smaller F6 effect: in PaddlingRoom halls the builder's 'Level 2 Paddling Threshold Ground' (WB:465-466, top at y=0) is exactly coplanar with the kit's 'Corridor/Passage MouthTo|MouthFrom Threshold' (modules_tunnel.py collar(), top at y=0). That z-fights two whites with different tile phase right at the tunnel mouth (4-11 overlaps per seed).

**occurrences:** Measured over world_837834/1/101: a visible PR Tile/Aqua look of (255,255,255) on 2770-2973 BaseParts per seed (1368 MeshParts plus 1402 Parts on 837834), against 596 builder Parts at (241,237,220). adjacency.py finds 6095 touching pairs of different colour in 440 kinds on seed 837834. The top kinds are CoveTop64/CoveBase64 against hall Wall/Lintel/Sill/Overhead Tile, Hall Water Floor against Step Ground/CoveBase/DrainHole/Corridor Ledge/Channel Side, Overhead Tile against LightRound/LightWell, hall walls against Walkway Deck/Walkway_Straight32, Corridor MouthFrom/MouthTo Threshold against hall walls, and CornerCove against Overhead Tile. Every tunnel and pipe mouth is affected: 74/82/75 corridors per seed, x2 collars each, in every hall Type that has a door (all except dens). Every hall cove, walkway, light well, pool step, drain and column is affected too. Chambers are kit-only, so their walls and pieces are 255 all through, but they meet builder halls at every pipe mouth. The paddling threshold z-fight shows up in PaddlingRoom halls with a Wet tunnel or a pipe at the door (seed 837834 Hall 22, seed 101 Halls 30/31).

**fixDesign:** ONE RULE for every tiled surface, Part or MeshPart, kit or builder: Material SmoothPlastic, MaterialVariant 'PR Tile' (everything above water) or 'PR Tile Aqua' (submerged floors only), Color = TILE_RGB = (241,237,220) (the builder's WHITE, i.e. the hall look the owner already saw), Reflectance 0.06. No other tile variant or tint anywhere. Changes: (1) prkit.py:28-31: add TILE_RGB = (241, 237, 220) with the comment '== Kit World Builder WHITE'. Set the 'Tile' and 'Aqua' tints to TILE_RGB. Delete 'TileShade' and 'Worn' from PALETTE, so that any future use raises KeyError at kit build (the uses are replaced in issue F3-materials). Add 'Dial': (None, None, (226,220,204), 1.0) for the pump gauge face, which is not a tile surface. (2) Kit World Builder cloneComponent WB:121: change to `if p.MaterialVariant=='PR Tile' or p.MaterialVariant=='PR Tile Aqua' then p.Reflectance=.06; p.Color=WHITE end`. Every kit clone passes through this one function, so the colour fix lands with a builder push even before the kit is reinstalled, and an older installed kit cannot bring 255 back. (3) WB:466: lower the Paddling Threshold Ground 0.02 stud (`cf*CFrame.new(0,-.37,-4)`) so the kit threshold owns the surface at the mouth. This is invisible and still walkable. (4) After the kit rebuild (needed anyway for F3), tools/level2_blender/import_kit.py:352 expected variants become {'PR Tile','PR Tile Aqua','PR Iron'}. Update the same set in tools/tests/test_level2_kit_import.py:582 and test_level2_kit_world_builder.py:269 and :1599-1600. An already installed 'PR Tile Worn' MaterialVariant in MaterialService can stay; it is simply unused.

**check:** (a) World-dump invariant, already written: G:/Roblox/_local/l2fix/f3f6/tile_rule_check.py and rule A of G:/Roblox/_local/l2fix/f3f6/f3f6_check.py. Every BasePart with transparency < 0.98 and a variant starting 'PR Tile' must be PR Tile|PR Tile Aqua, Color == (241,237,220) and Reflectance == 0.06. Exit 1 otherwise. Baseline today: 2883/2991/3076 violating parts on seeds 837834/1/101. This global invariant is stronger than adjacency: if it holds, no two touching tile surfaces can differ. adjacency.py (touching-AABB pairs with different variant family or colour) stays as the diagnostic listing. (b) Put the same predicate into tools/tests/test_level2_kit_world_builder.py check_snapshot, in the per-object loop next to the variant assertion at :1599. That makes it run over the 10 fake-engine seeds on every test run. The fake engine already records Color/MaterialVariant/Reflectance (:368, :391-392, :455). (c) Kit-level rule C in f3f6_check.py: manifest materials contain no TileShade/Worn, and Tile/Aqua colour == TILE_RGB. (d) Coplanar rule: G:/Roblox/_local/l2fix/f3f6/coplanar_dir.py reports visible same-facing coplanar overlapping Part faces (gap < 0.05) with a different look or a different Part. Gate it on zero 'y+' overlaps between builder ground and kit thresholds.

**risks:** Kit meshes and kit parts get about 5% darker and warmer, matching the halls. The Blender review renders change the same way, because render_world.py honours the dump colours. If the owner prefers the lighter kit white, set TILE_RGB = (255,255,255) and WHITE to match instead; the rule and the check stay the same. Colour alone does NOT fix the bore and coves next to the collar: they are also lit from the wrong side (issue F3-normals). Both must land together for image 5 to read as one material.

**files:** tools/level2_poolrooms/prkit.py, ServerScriptService/Level 2 Systems/Level 2 Kit World Builder.ModuleScript.lua, tools/level2_poolrooms/objectives.py, tools/level2_blender/import_kit.py, tools/tests/test_level2_kit_import.py, tools/tests/test_level2_kit_world_builder.py

**refs:** tools/level2_poolrooms/prkit.py:28-31 (PALETTE Tile/Aqua tint 255,255,255; TileShade 226,220,204); ServerScriptService/Level 2 Systems/Level 2 Kit World Builder.ModuleScript.lua:9 (WHITE = 241,237,220); ServerScriptService/Level 2 Systems/Level 2 Kit World Builder.ModuleScript.lua:19-24 part() default colour WHITE; ServerScriptService/Level 2 Systems/Level 2 Kit World Builder.ModuleScript.lua:116-122 cloneComponent loop (sets Reflectance only, leaves kit Color); tools/level2_blender/import_kit.py:483 (mesh Color from manifest), :527-529 (part record Color); ServerScriptService/Level 2 Systems/Level 2 Kit World Builder.ModuleScript.lua:465-466 Paddling Threshold Ground coplanar with kit collar threshold; tools/level2_poolrooms/modules_tunnel.py:163-168 collar threshold Part (top y=0)

## F3+F6 (normals) - Tunnel/pipe barrels, chamber corners/coves/sockets and other open shells have normals pointing AWAY from the visible side; DoubleSided hides the culling but Roblox still shades them with the wrong normal (sunlit white patches inside tunnels, bluish ambient-only coves, a differently lit ring at every mouth and at every rib)

**rootCause:** prkit.Mesh.finish() (prkit.py:179) runs bmesh.ops.recalc_face_normals on every component. On an OPEN shell (the tunnel barrel is authored as 'only the visible inside', modules_tunnel.py:52-73) that picks the outward side. Measured on the export: barrel faces of every RoundTunnel_*/Pipe_* point 0% toward the axis. Collar panel faces (closed solid) are correct (100% into the hall), and rib inner faces (closed strip) are correct (100% toward the axis). Chamber_* vertical corners face the room for 44% of their area; the chamber straight floor coves, ceiling coves and socket faces for 0%. tools/level2_poolrooms/backface_check.py run on world_837834 reports 491,989 back-face hits in 37 chunks: every tunnel and pipe Tile chunk, Chamber_A-D, CornerCove_R24, Column_D16, ExitSpiral, CurveWall, SpiralStairWell, ExitPlatform (G:/Roblox/_local/l2fix/f3f6/backface_837834.txt). The v2610 fix set MeshPart.DoubleSided=true (import_kit.py:517-520), which stops the culling (studio-qa/01 vs 02). The screenshots indicate that the back face is still lit with the STORED normal. Image 3 (a chamber: walls are kit Parts with the SAME Color 255 and variant as the mesh) shows walls with B/R 0.81, the 44%-correct corner 0.95, and the 0%-correct floor cove 1.09 (bluish = only the cyan pool ambient (70,170,150), no warm lamp light). In images 2 and 5 the barrel reads bright neutral white: its outward normal faces the sky and sun outside the tunnel, which is not roofed. Against it, the inward-facing ribs and the inward-facing mouth reveal ring read as 'a ring in another colour'. A second shading fault adds to the ribs: raw(..., smooth=True) averages vertex normals across 90 degree edges. Rib inner-face normals tilt about 45 degrees along the axis (rib(): 100% of TileShade triangles deviate > 35 degrees from their face), and chamber corners tilt 0.24 in y because their top and bottom caps share vertices. The same averaging hits Column_*, CornerCove_*, CoveBaseCorner/CoveTopCorner, PoolSteps_Curved, Porthole_* and SpiralStairWell: 61 of 135 tile chunks have more than 5% smeared area (G:/Roblox/_local/l2fix/f3f6/shading.py).

**occurrences:** Every corridor in every seed: 74/82/75 RoundTunnel_*/Pipe_* placements (Dry/Wet/Stair4/Stair8 x 64/72/80 and Pipe Flat/Stair4 x 16-80). Every chamber (Hall Type 'Chamber', 21/22/20 per seed, prefabs A-D): 4 vertical corners, 8 straight coves and the socket faces each. Outside this cluster, the same mechanism (open or capped shells with smoothed or wrong normals) hits CornerCove_R24 in ColumnHall/SpiralWell/VaultArcade/BigPool, Column_D16, CurveWall_* (CurvedChannel), SpiralStairWell_* (SpiralWell), ExitSpiral/ExitPlatform (ExitHall) and PumpStation Iron. The F1 analyst owns those, but the fix below is the shared prkit mechanism.

**fixDesign:** In prkit (one place, all modules route through it): (1) absorb()/raw()/box()/cylinder() take an optional `facing=` callable (roblox_point_studs) -> roblox_direction of the visible side, stored next to each face in self.uvf. (2) finish(), after recalc_face_normals: for every face with a facing hint, take c = f.calc_center_median()/S (Blender studs), convert to Roblox p = (c.x, c.z, -c.y) and want = facing(p) converted back to Blender (w.x, -w.z, w.y). If f.normal.dot(want) < 0, call f.normal_flip(). Then hard edges: `for e in bm.edges: if len(e.link_faces)==2 and e.calc_face_angle(0) > math.radians(45): e.smooth = False`. Then bm.normal_update(). The exporter reads mesh.corner_normals, which honours sharp edges, so ribs, caps and corners stop averaging; curved surfaces (48/32/24/16 segments, coves at 15 degrees per step) stay smooth. (3) Hints in modules_tunnel.py: arc_shell: facing = lambda p: (-p[0], cy + floor_height(p[2], length, rise) - p[1], 0) (toward the bore axis). chamber_corner: author only the inner surface (radius 8-WALL; drop the outer r=8 and the cap faces, which are hidden in walls, ceiling and floor; colliders already exist), with facing = lambda p: (cx-p[0], 0, cz-p[2]). straight_cove: facing = (0, -1 if upper else 1, -sign) for N/S and (-sign, -1 if upper else 1, 0) for E/W. socket_face: (0,0,-sign) for N/S and (-sign,0,0) for E/W. Chamber_D nook: (cx-p[0], 0, cz-p[2]) (the colliders sit on the convex side, so the room sees the concave side). Rib and collar need no hint (closed strips, already correct), but get the hard-edge rule. (4) Keep DoubleSided=true; it does no harm once normals are right. (5) Rebuild the kit (build.py), re-upload the changed chunk wires, reinstall (import_kit --plan/--upload-meshes/--install/--audit).

**check:** (a) tools/level2_poolrooms/backface_check.py must print BACKFACE_TOTAL 0 (exit 0) on every dumped seed. Run it over world_837834/1/101 plus the 10 test seeds dumped with dump_world.py (1, 101, 1182081016, 738163940, 484836893 and the five derived ones from test_level2_kit_world_builder.py:1675-1676). It is a ray cast from interior sample points of every hall and corridor (128 directions): any first hit on a mesh face with dot(ray, normal) > 0 is a back face seen by a player. Baseline: 491,989 hits in 37 chunks. (b) Kit-level, no Blender: rule E of G:/Roblox/_local/l2fix/f3f6/f3f6_check.py. No Tile/Aqua triangle with area > 0.02 may have a corner normal deviating more than 35 degrees from its geometric normal. Baseline: 26,810 triangles (rib TileShade 576 per tunnel, chamber corners 384 per chamber, ...). (c) Kit-level, cheaper than (a), for the corridor/chamber family: G:/Roblox/_local/l2fix/f3f6/tunnel_normals.py and chamber_normals.py assert 100% of barrel area faces the axis and 100% of chamber corner/cove/socket area faces the room. (d) Studio settle step (the only part offline checks cannot prove): one screenshot each of a chamber corner, a tunnel mouth (image 5 framing) and a pipe interior (image 2 framing) after reinstall. The wall Part, the collar, the reveal ring, the barrel and the ribs must read as one brightness under the same light.

**risks:** UNSURE about one thing: that Roblox shades DoubleSided back faces with the unflipped normal. It is inferred from the screenshots (same Color/variant chamber walls against corners and coves, bright barrels, darker inward ribs), not from Roblox documentation. To settle it: in Studio, put one Chamber_A clone in a dark baseplate with one PointLight and compare the corner and floor cove against the wall Part before and after the reinstall. Either way, correct normals are required for the backface check and cost nothing. After the flip, tunnels no longer receive leaked sky light. Pipes that get no lamp (WB:1035, narrowLightBudget = 80 - tunnels - 3 - lights, often 0) will become noticeably darker, so check pipe readability. The hard-edge threshold of 45 degrees must stay above the per-segment angle of every intended smooth surface (coves 15 degrees, 16-segment columns 22.5 degrees); a 6- or 8-segment surface would get faceted.

**files:** tools/level2_poolrooms/prkit.py, tools/level2_poolrooms/modules_tunnel.py, tools/level2_poolrooms/modules_arch.py (hints for its open shells; F1 cluster), tools/level2_poolrooms/objectives.py (ExitSpiral/ExitPlatform hints; F11/F13 clusters)

**refs:** tools/level2_poolrooms/prkit.py:106-116 absorb() (no facing hint stored); tools/level2_poolrooms/prkit.py:149-154 raw() smooth flag applies to every face; tools/level2_poolrooms/prkit.py:178-180 finish(): recalc_face_normals + normal_update; tools/level2_poolrooms/modules_tunnel.py:52-73 arc_shell (open barrel); tools/level2_poolrooms/modules_tunnel.py:76-94 rib (smooth=True across 90 degree side edges); tools/level2_poolrooms/modules_tunnel.py:327-352 chamber_corner (inner/outer/cap faces, smooth=True); tools/level2_poolrooms/modules_tunnel.py:355-368 socket_face, :371-394 straight_cove; tools/level2_poolrooms/modules_tunnel.py:455-469 Chamber_D nook; tools/level2_blender/import_kit.py:515-520 DoubleSided=true (masks culling only); tools/level2_poolrooms/backface_check.py (existing ray check, exit 1 today)

## F3 (materials) - Deliberate off-tile materials inside tunnels, pipes and chambers: TileShade ribs (darker ring), PR Tile Worn patches on the aqua pipe floor (white squares), Worn pipe stairs, TileShade chamber porthole ring

**rootCause:** modules_tunnel.py authors the internal bands of every tunnel and pipe as 'TileShade' (prkit tint 226,220,204 = 0.89/0.86/0.80 of Tile) at :94. Pipe_Flat_* gets two 1.8 x 2.4 'Worn' overlay boxes 0.012 above the aqua floor (:316-318). The PR Tile Worn albedo is cream (mean 206,195,172), so on PR Tile Aqua (mean 143,178,161) it reads as a white square: image 2. Its 0.0045-stud bottom gap and 0.0195-stud top lift also invite z-fighting at distance. Pipe_Stair4_* steps are 'Worn' (:312). The chamber daylight porthole ring is 'TileShade' (:485). KIT_SPEC section 2 allowed Worn as 'sparse variety', and the owner now reads it as defects. The rib also has degenerate side-face UVs (issue F3-uv), so its sides show streaks.

**occurrences:** Ribs: every RoundTunnel_* (2-3 rings each) and every Pipe_* of length >= 32. That is 76-86 TileShade rib MeshParts per seed (837834: 78, 1: 86, 101: 76), in components RoundTunnel_{Dry,Wet,Stair4,Stair8}_{64,72,80} and Pipe_{Flat,Stair4}_{32,48,64,80}. Worn: 31-33 Pipe_Flat placements per seed (all lengths 16-80, 2 patches each) plus 1-3 Pipe_Stair4 per seed (Worn steps). 34/42/38 Worn BaseParts per seed. Porthole ring: Chamber_A/B/D (w < 64), one per chamber, 20-22 chambers per seed minus Chamber_C. Gauge: 3 PumpHalls per seed (not a tile surface).

**fixDesign:** modules_tunnel.py:94: rib material 'Tile'. Split the rib into the inner band (smooth, cylindrical UV as today) and the two side faces as a separate raw() with planar UV (u,v) = (Roblox x, Roblox y) in metres and smooth=False. modules_tunnel.py:316-318: delete the Worn patch loop (2 lines). modules_tunnel.py:312: steps(..., 'Tile', base=1). modules_tunnel.py:485: 'Tile'. objectives.py:114 and :116: 'Dial' (the new plain SmoothPlastic, no-variant palette entry from F6), so the dial stays a dial and is not a tiled surface. Then delete TileShade and Worn from PALETTE (F6), which makes any reintroduction fail at kit build. KIT_SPEC.md section 2: replace the Worn row with 'none: one tile look everywhere (owner 2026-10-03, F3)'. Optional, only if the owner wants the bands to stay visible: keep them 'Tile' and let their 0.34-stud relief carry them. A colour band is what the owner rejected.

**check:** Rule C of G:/Roblox/_local/l2fix/f3f6/f3f6_check.py: manifest.materials has no TileShade or Worn key. Today it has both. Rule A (world dumps) and the same predicate in test_level2_kit_world_builder.py check_snapshot: no visible BasePart has variant 'PR Tile Worn' or a Color other than TILE_RGB. Baseline: 78-89 TileShade and 32-36 Worn per seed. Add to test_level2_kit_world_builder.py: no Pipe_* component contains a chunk or Part whose top is within 0.05 stud above its floor Part top (overlay patches), which catches any reintroduced decal-like overlay.

**risks:** The tunnels lose their only colour variation; that is what the owner asked for. The ribs keep their relief. Removing Worn from the manifest changes the importer's expected variant set (F6 step 4), and the import tests must be updated in the same change.

**files:** tools/level2_poolrooms/modules_tunnel.py, tools/level2_poolrooms/objectives.py, tools/level2_poolrooms/prkit.py, artifacts/level2-poolrooms-20261003/KIT_SPEC.md

**refs:** tools/level2_poolrooms/modules_tunnel.py:94 rib material 'TileShade'; tools/level2_poolrooms/modules_tunnel.py:312 Pipe Stair4 steps 'Worn'; tools/level2_poolrooms/modules_tunnel.py:316-318 Pipe_Flat Worn overlay patches; tools/level2_poolrooms/modules_tunnel.py:485 chamber porthole ring 'TileShade'; tools/level2_poolrooms/objectives.py:114-116 PumpStation gauge face 'TileShade' (mesh disc + Part); tools/level2_poolrooms/prkit.py:29-30 PALETTE TileShade/Worn; artifacts/level2-poolrooms-20261003/KIT_SPEC.md:23-28 (Worn 'sparse variety' rule to retire)

## F3+F6 (uv) - Kit UV bugs that change the tile size/direction on tunnel and chamber surfaces: rib side faces have a degenerate (1-D) UV, chamber corners and the Chamber_D nook use the wrong axis sign and stretch tiles 7-50x along the arc, the pipe bottom seam squeezes 31x

**rootCause:** The modules re-derive cylinder angles from Blender-axis coordinates inside the uv callback. In chamber_corner (modules_tunnel.py:342-345), t = atan2((co.y/kit.S - cz)*sz, ...) uses Blender y, which is -Roblox z, so (co.y/S - cz) = -(z + cz). That is a large near-constant term, so t barely changes over the quarter arc. Measured: u spans only -1.73..-1.89 repeats over about 10 studs of arc (density 0.02-0.15 of nominal, so tiles 7-50x wide). The Chamber_D nook lambda (:464) has the same sign bug. rib() (:89-93) applies the cylindrical uv to its side faces as well; on a face of constant z, u = -co.y is constant, so those faces get a smeared 1-D texture (singular value 0, 384 of 576 rib triangles). arc_shell for pipes (full circle, low = -pi/2) wraps atan2 at the seam: the last strip maps u from 2*pi*r back to 0 (31x squeeze). It is hidden under the pipe floor, but it fails a strict check. The collar's outer edge faces (x = +-17, y = 32/12) use the arc formula with a 0.57-0.72 density; they are hidden in the wall.

**occurrences:** Chamber_A/B/C/D: 384-408 triangles each (all 4 vertical corners), in every Chamber hall (20-22 per seed). Chamber_D nook: every Chamber_D placement. Ribs: every RoundTunnel_* and every Pipe_* of length >= 32 (76-86 per seed). Pipe seam: every Pipe_* (hidden). Collar edges: every tunnel and pipe (hidden).

**fixDesign:** Root fix in prkit: raw() accepts `vertex_uv=` (a list of (u,v) in metres per vertex index), used by finish() instead of the callback for those faces. The modules already know (angle, axial, radius) for every vertex when they build it, so nothing has to be re-derived from Blender coordinates. Use it in arc_shell (u = z, v = (angle-low)*radius: no wrap, the end vertex at `high` gets the full arc length), in chamber_corner (u = angle*radius_of_that_vertex, v = y) and in the nook (u = angle*r, v = y). Minimal alternative if prkit should not change: in chamber_corner and the nook use t = atan2((-co.y/kit.S - cz)*sz, (co.x/kit.S - cx)*sx) and u = t * math.hypot(...) * kit.S. For the rib, the side faces become their own raw() with box_uv (issue F3-materials). For the collar, use kit.box_uv for faces whose normal is axis-aligned in x or y.

**check:** Rule D of G:/Roblox/_local/l2fix/f3f6/f3f6_check.py, kit-level and offline: for every Tile/Aqua triangle with area > 0.02 stud^2, both singular values of d(uv)/d(surface studs) must lie within [0.87, 1.15] of 1 repeat per 4.8 studs. Baseline: 26,996 failing triangles kit-wide. For this cluster: Chamber_A-D 384-408 each, rib 384 per tunnel and 130 per pipe, pipe seam 86-96, collar 136 per tunnel. Hidden faces either get correct UVs or are deleted, so the check needs no visibility exemption. Add it to tools/tests/test_level2_kit_import.py so that every kit export is gated.

**risks:** Changing UVs changes the chunk wire hashes, so those meshes must be re-uploaded. The vertex_uv path must keep the existing division by tile_m in finish().

**files:** tools/level2_poolrooms/prkit.py, tools/level2_poolrooms/modules_tunnel.py

**refs:** tools/level2_poolrooms/modules_tunnel.py:342-345 chamber_corner uv (co.y sign bug); tools/level2_poolrooms/modules_tunnel.py:464 Chamber_D nook uv (same bug); tools/level2_poolrooms/modules_tunnel.py:89-94 rib uv applied to side faces; tools/level2_poolrooms/modules_tunnel.py:64-71 arc_shell uv atan2 wrap at the seam; tools/level2_poolrooms/modules_tunnel.py:151-158 collar uv for non-panel faces; tools/level2_poolrooms/prkit.py:183-188 finish() UV pass (callback per loop, no per-vertex option)

## F6 (stretch) - Runtime MeshPart resizing stretches mesh UVs: hall coves 0.04x-3.5x, walkway bullnose 3.2x-7.4x, ExitHall corner coves 1.85x tall, curve walls/spiral wells 0.56x-0.94x, so their tiles no longer match the 0.6-stud wall tiles next to them

**rootCause:** Mesh UVs are fixed in mesh space; a MaterialVariant on a MeshPart repeats per UV (measured equal to Parts at nominal scale), so changing MeshPart.Size stretches the tiles. Parts re-tile by stud. The builder resizes kit meshes in place. coveRun scales CoveBase64/CoveTop64 by factor = (b-a+1)/64 along X (WB:276-282). The kit's CoveBase16/32 and CoveTop16/32 exist but are unused. placeWalkways scales Walkway_Straight32 by (high-low-3)/32 (WB:439-445); only the bullnose strips are mesh, the deck is a Part. Corner coves scale Y by CeilingClass/52 (WB:357-363) for the ExitHall's ceiling of 96. CurveWall/SpiralStairWell placements scale XZ (WB:635, 691, 720).

**occurrences:** meshscale.py over the three dumps. CoveTop64 and CoveBase64: 212/219/201 placements per seed outside +-12% (every hall wall run in every hall Type except Chamber; the factor ranges 0.04-3.5). Walkway_Straight32: 56/58/58 per seed (every hall with walkways, factor 3.2-7.4; image 5's curbs). CornerCove_R24_H52 x1.85 in Y: 4 per seed (ExitHall). CurveWall_Q16/Q32/S48 x0.63-0.87 and SpiralStairWell_H52/H42 x0.56-0.94: 1-3 per seed (CurvedChannel, SpiralWell; F9 may replace these). VaultBay32 x0.95 in Y (VaultArcade, within tolerance).

**fixDesign:** Never stretch a tiled mesh by more than +-12.5%; compose instead. coveRun: L = b-a+1, unit u = 16 if L >= 64, 8 if L >= 32, else 4. n = max(1, round(L/u)). Lay pieces greedily from {64,32,16,8,4} to total n*u, all scaled by f = L/(n*u), so |f-1| <= 0.125 whenever L >= 4u. Add CoveBase/CoveTop 4 and 8 to the kit: two calls each in the modules_arch.py cove loop, beside the existing 16/32/64. placeWalkways: the same composition with Walkway_Straight32/16 (export 8/4). Alternatively make the two bullnose strips cylinder Parts, which tile by stud, and drop the mesh. Corner coves: add 96 to modules_arch.py:517 (`for h in (34,42,52,96)`) and at WB:351-353 select an exact sourceHeight from {34,42,52,96} with no Y scaling. CurveWall/SpiralStairWell: belongs to F9's redesign; the same +-12.5% rule applies (export the needed radii instead of scaling). Instance cost: about 1-3 extra cove pieces per run (roughly +400-700 per seed), within the 8,500 budget only if F9/F4 do not add more. Measure with the existing world-descendant total in test_level2_kit_world_builder.py.

**check:** Rule B of G:/Roblox/_local/l2fix/f3f6/f3f6_check.py over the world dumps: every visible tiled MeshPart's Size divided by its exported chunk size must be in [0.88, 1.14] on every axis. Baseline: 1,249 violations over 3 seeds. Put the same rule into test_level2_kit_world_builder.py check_snapshot for the 10 fake-engine seeds: the harness has the chunk sizes from read_exports() and the MeshPart Size in the snapshot.

**risks:** More instances (budget). Seams between consecutive cove pieces are coplanar end faces. Pieces must abut exactly; overlap would z-fight, the existing 0.5 overlap into corners must stay on the outer pieces only. Shared with F2 (cove runs into corners): coordinate so that only one change rewrites coveRun.

**files:** ServerScriptService/Level 2 Systems/Level 2 Kit World Builder.ModuleScript.lua, tools/level2_poolrooms/modules_arch.py

**refs:** ServerScriptService/Level 2 Systems/Level 2 Kit World Builder.ModuleScript.lua:268-285 coveRun; ServerScriptService/Level 2 Systems/Level 2 Kit World Builder.ModuleScript.lua:432-447 placeWalkways stretch; ServerScriptService/Level 2 Systems/Level 2 Kit World Builder.ModuleScript.lua:349-363 corner cove Y stretch (sourceHeight capped at 52); ServerScriptService/Level 2 Systems/Level 2 Kit World Builder.ModuleScript.lua:635, 691, 720 CurveWall/Spiral XZ scale; tools/level2_poolrooms/modules_arch.py:517 corner_cove heights (34,42,52); tools/level2_poolrooms/modules_arch.py:121-141 cove(length, top) exports 16/32/64

### Other problems seen
- Z-fighting cream against aqua under water: PoolSteps_Straight12 'Step Ground N' tops sit 0.019-0.028 stud above the Hall Water Floor top (28/31/15 visible overlaps per seed; VaultArcade, ColumnHall, BigPool). This is F4/F5 territory: drop the lowest step's top at least 0.05 or stop it at the basin floor.
- The Exit Room Wooden Door is built as 'PR Iron' with the cream WHITE colour (WB:896-897), so it renders as a cream iron plate (F13 area).
- Pipes get no lamp once narrowLightBudget runs out (WB:1035, 1247: 80 - tunnels - 3 - lights, often 0). Today they are lit mainly by sky leaking through the inverted barrel normals. After the normals fix they will be dark; decide whether that is wanted.
- Pipe_Flat water region is 0.7 thick with surfaceY 1.1 (0.1 above the floor). On the 4-stud terrain voxel grid this is about 17% of one voxel and will render patchily or not at all (F5).
- Coplanar same-look duplicates inside Wet tunnels (Corridor Channel Side against Corridor Ledge, Channel Side against Water Floor, gap 0.000) and hall Wall/Overhead Tile/Lintel overlaps: mostly buried faces, but any visible one z-fights grout phase. Diagnostic: G:/Roblox/_local/l2fix/f3f6/coplanar_dir.py.
- Kit-wide UV density failures outside this cluster (rule D): VaultBay32 (up to 4x), CornerCove_R8/R16/R24 (0.73-0.84, caps 0), CurveWall_* (bottom caps 0), LightWell_R6/R10 and SpiralStairWell (0.74), ExitTubeVisual (1.3), Porthole_* (0.5-0.75), CoveBase/CoveTop end caps (5.7-15.7x, hidden behind corners), ExitMouth (0.79). Full list: G:/Roblox/_local/l2fix/f3f6/out/f3f6_check_baseline.txt.
- Smoothing across hard edges (rule E) also hits Column_* (side normals tilted 44 degrees toward the caps), CornerCove_*, CoveBaseCorner/CoveTopCorner, PoolSteps_Curved, Porthole_*, SpiralStairWell and VaultBay. Columns will show a top-light/bottom-dark gradient unlike flat Parts. The prkit hard-edge rule fixes them all at once.
- The test harness tools/tests/test_level2_kit_world_builder.py reads G:/Blender/Level2_Poolrooms/jobs/{A,B,C}/export manifests, not assets/level2/poolrooms-kit/export. A kit rebuild must refresh both, or the tests verify a stale kit.
- Grout phase: Parts tile from their own face origin, so the collar's grid does not line up with the hall wall's grid at the seam (visible in image 5). This cannot be fully solved with per-Part tiling; it is low priority once colour and lighting match.

### Notes
I did not edit anything in the repo. Scratch scripts and output are in G:/Roblox/_local/l2fix/f3f6/:

- f3f6_check.py: the combined acceptance check (rules A-E). Baseline is in out/f3f6_check_baseline.txt; it exits 1 today with A 8950, B 1249, C 5, D 26996, E 26810.
- tile_rule_check.py: the colour invariant over the world dumps.
- adjacency.py: touching pairs with different looks.
- shading.py: smoothed-normal deviation.
- uvscale.py and uvscale_detail.py: texel density.
- meshscale.py: MeshPart stretch.
- tunnel_normals.py and chamber_normals.py: facing per surface.
- coplanar_dir.py: visible coplanar z-fights.
- backface_837834.txt: an earlier run of tools/level2_poolrooms/backface_check.py, 491,989 back hits.

Key facts established:

1. The tile SCALE on MeshParts equals Parts at nominal size. I measured an 8.5 px grout period on both the wall and the collar in image 5, so StudsPerTile 4.8 and UV repeats of 4.8 studs agree. That settles KIT_SPEC section 9 question 1 empirically. Mismatches come only from runtime stretching and the module UV bugs.
2. F6 in image 5 is the Color difference (kit 255,255,255 against builder 241,237,220) plus the bore being lit from the wrong side.
3. F3 in image 2 has four parts:
   - the white square is the Pipe_Flat 'Worn' overlay patch;
   - the darker ring is a 'TileShade' rib with smoothed normals and degenerate side UVs;
   - the bright white areas are the barrel whose normals face outward to the sky (DoubleSided renders it but, judging by the screenshots, lights it with the outward normal);
   - the mouth reveal ring faces correctly, so it reads differently from the barrel.

One unsure point: Roblox back-face lighting for DoubleSided. The evidence is image 3 (a chamber, where walls and corners share the same Color and variant but read differently) and images 2 and 5. A Studio comparison after the reinstall settles it. The normals fix is required regardless, by the existing backface_check.

The single rule to adopt: every tiled surface is SmoothPlastic + 'PR Tile' (or 'PR Tile Aqua' for submerged floors), Color (241,237,220), Reflectance 0.06, normals facing the playable side, no smoothing across edges over 45 degrees, and texel density 1 repeat per 4.8 studs within +-12.5%, including after any runtime resize.

Order of landing:
- The builder cloneComponent colour line and the paddling threshold change can be pushed alone.
- Everything else needs a kit rebuild (build.py, refresh jobs/A,B,C exports), mesh re-upload and a reinstall, then backface_check, f3f6_check and the 10-seed test.

## F9 - CurvedChannel halls are rectangles with a free-standing curved partition in the pool; the owner wants the room's own walls to swerve

**rootCause:** The only curvature in a CurvedChannel hall is dressing. In dressHall (Kit World Builder 609-705) the CurvedChannel branch reserves pockets outside the AI lanes and drops free-standing kit walls into them: one CurveWall_S48_H{h} (only when longHalf >= 88), one or two CurveWall_Q16_H{h}, plus a Walkway_Bend16. The room shell is always the lattice rectangle. wallShell (288-342) builds straight slabs, coveRun (268-286) builds straight scaled coves, cornerCoves (344-379) builds R8/16/24 corners, placeWalkways (427-473) builds straight decks on the two long walls only, and ceilingShell/floorShell/water (390-425, 238-257) are all rectangles. Nothing in the kit or builder can turn a room wall. The kit's CurveWall pieces (modules_arch.py wall_from_path 233-265, curve_wall 268-272) are free-standing 3-stud blades. They run from y=0 to y=h, so in pool halls they float 1.6-2.0 studs above the basin floor, and they have no coves or deck. RECIPES.md:28 and KIT_SPEC.md:39,51 specify exactly this partition recipe, and test_level2_kit_world_builder.py 1376-1397 requires 2-4 partition models.

**occurrences:** Hall Type CurvedChannel only. It is drawn only for Role=='Hall', never for Arrival, Pump, Exit, Kids or Den halls. Over 400 seeds of the real generator (offline stub RNG) there are 2021 CurvedChannel halls, 0-11 per map (mean 5.05), sizes 96..240 per side, ceilings 34/42/52, PoolType Shallow 1455 / Deep 566. All 12 CurvedChannel halls in the three dumped worlds have the partition: 837834 (resolves to seed 1570937) halls 21, 23, 37, 44; seed 1 halls 5, 21, 30, 32; seed 101 halls 23, 28, 29, 43. Each is 1x S48 + 1x Q16, or 2x Q16, plus a Walkway_Bend16, which is 39-68 parts per hall in the dump. Kit pieces: CurveWall_Q16/Q32/S48/S64 x H34/42/52 (12 components; only Q16 and S48 are used). The same rectangle-only shell code paths (wallShell, coveRun, cornerCoves, placeWalkways, ceilingShell, floorShell) build every big hall, so the new swerve path must be gated to swerve halls only.

**fixDesign:** A. WHAT 'SWERVY' MEANS (geometry rules)
- The lattice rectangle stays the AI and contract boundary: findHall, lanes, rectangle wall slabs, rectangle floor, ceiling and water are all unchanged.
- Inside it, the room outline becomes a closed G1-continuous loop that only ever moves INWARD from the wall face line (boundary + 1.75). The rectangle slabs remain as a hidden backstop, so a skin gap can never open a hole out of the map. The dead pocket behind the skin is sealed by the rectangle walls, floor and ceiling.
- Loop order: North W->E, East N->S, South E->W, West S->N. Every corner is the same left turn toward the room.
- Cross-section, identical on every straight and arc so junctions have no step:
  - wall body n in [-1.75, 0] (n = inward from the face), y in [-8, h+2];
  - top and base coves r=3 on the room side, using the CORRECTED concave profile from F1 (one shared profile function);
  - deck n in [-0.5, 9.5], top y=+0.45, bottom -0.35, bullnose front edge (same as Walkway_Straight32 at 6.25 from the boundary).
- Straight (offset d=0) is forced on:
  - every door: [cross-20, cross+20], all kinds including Narrow pipes, so collars stay flush and the 30x38 approach and the 34x8 mouth stay clear;
  - wherever the allowance <= 0.
- Allowance(s) = normal distance from the face line to the nearest keep-clear rectangle overlapping [s-3, s+3], minus 3 margin, minus 10.5 deck reach. Keep-clear is exactly today's contract: centre axes +-17 over the full extent, and every door spoke +-17 from the wall to the centre. Wall AND deck stay outside the lanes, so lanes keep exactly today's floor.
- Corners: the largest Rc in {64, 48, 32, 24} (quarter concave arc, tangent on both face lines) whose quadrant clears every door straight and whose arc+deck satisfies the allowance pointwise. Otherwise the standard corner applies, with its radius clipped to <= gap-3 to the nearest door hole (also fixes the corner/door overlap listed below).
- Bulges: in each free zone (maximal interval of positive allowance between fixed intervals) place one S-in, a plateau straight at offset D, then one S-out. The S is two equal arcs of radius R and angle theta, with along-length Ls=2R sin(theta) and depth Ds=2R(1-cos(theta)). Try deepest first:
  - (24,60): 41.57/24.00
  - (32,45): 45.25/18.75
  - (16,60): 27.71/16.00
  - (16,45): 22.63/9.37
  The plateau is the zone length minus 2Ls and must be >= 0. The profile is checked against the allowance every 0.5 stud.
- Patrol nodes in swerve halls move onto the centre axes: (cx+-0.32W, cz) and (cx, cz+-0.32D). These lie inside the lanes, so they are always clear (Pool Slide AgentRadius <= 12 < 17) and always inside the outline.

B. HOW MANY
- Post-pass in decorate after the type loop (keeps typeRng and every other hall's type unchanged):
  - an ineligible CurvedChannel becomes ColumnHall;
  - eligible = curved fraction >= 0.30 and >= 2 corners with Rc >= 32;
  - keep at most 4, highest curved fraction first;
  - if fewer than 2, promote eligible Role=='Hall' halls (ColumnHall first).
- Prototype over 400 seeds: 2 swerve halls in 270 maps, 3 in 71, 4 in 59. Chosen halls are curved over p10/p50/p90 = 37% / 49% / 60% of the perimeter.
- Without filtering, 11% of current CurvedChannel halls cannot curve at all under the lane contract.

C. KIT (modules_arch.py, registered in build())
- swerve_profile(h): the shared cross-section above.
- swerve_s(R, deg, In|Out, h) -> SwerveS_In/Out_R{R}_A{deg}_H{h}:
  - one fused mesh per S-bend (no z-fight at the inflection);
  - In and Out are mirror images (Roblox cannot mirror MeshParts);
  - families (16,45), (16,60), (24,60), (32,45).
- swerve_corner(R, h) -> SwerveCorner_R{24,32,48,64}_H{h}: one quarter concave arc, used at all four corners by rotation.
- Heights 34/42/52. Total 4x2x3 + 4x3 = 36 components, each <= 4000 tris.
- Markers Start (origin, yaw 0) and End (analytic end point and yaw), so the builder chains pieces without trig.
- Colliders:
  - 'Swerve Wall Block i': 1.75 thick at n [-1.75, 0], y [-8, h+2]; chords sized on the OUTER radius with sagitta <= 0.25, i.e. chord <= 2*sqrt(0.5R): 5.7 at R16 up to 11.3 at R64.
  - 'Swerve Deck Ground i' (ground=True): 9.4 wide, 0.8 thick, top +0.45, chords sized on the outer deck edge so the union covers the whole annulus.
- 0.5-stud tangent extensions at both ends, recessed 0.02 so the coplanar straight Part wins the overlap.
- validate():
  - face points 0.1 behind the face are inside the union of wall colliders (0.5 grid, y 0.5..h-0.5);
  - deck top points are inside ground colliders;
  - collider protrusion past the face is <= 0.3;
  - end cross-sections equal CoveTop64/CoveBase64/Walkway_Straight32/slab within 0.01.

D. GENERATOR (Kit Layout Generator)
- planSwerve(hall, doors) is a pure function on rectangles and door crosses. Door sides are derived exactly like the builder's hallDoors.
- It emits hall.Swerve = {Loop = ordered segments, CurvedFraction, Keepout}:
  - segments: {Wall, Kind='Straight', From, To, Offset}, {Kind='S', Piece='In'|'Out', R, Deg, At}, {Kind='Corner', Corner, R};
  - Keepout: AABBs <= 8 long covering wall + deck + dead pocket + 2.
- validateKit re-plans and compares, and checks the 2..4 count.

E. BUILDER (Kit World Builder)
- Gate on hall.Swerve. Delete the CurvedChannel branch at 609-705 (partitions and bend).
- New buildSwerve(ctx, parent, hall) runs after wallShell:
  - S and corner pieces are cloned at wallPose(hall, wall, At, inset=offset)-style frames;
  - each plateau gets a slab Part (1.75 thick, y -8..h+2) at offset D, plus coveRun and a Walkway_Straight32 deck at inset D;
  - d=0 straights reuse the rectangle slab.
- wallShell and coveRun clip coves to the plan's d=0 straights. The slabs stay whole.
- cornerCoves skips corners that have an arc.
- placeWalkways lays decks on every straight of all four walls (the loop's deck is continuous). PoolSteps at doors are unchanged.
- Push hall.Swerve.Keepout into `reservations` before any reservePocket. This keeps the light well, drains and other pockets inside the outline (the light well falls back to the centre).
- WallVoid only on a straight with >= 10 of clearance, else skip.
- nodes() uses the axis positions for swerve halls.
- Instance estimate: about +20..+45 net per swerve hall after removing partitions (39-68 parts) and replaced corners. With at most 4 halls that is under +180 against measured 7586-8164 and the 8500 budget. The budget assert enforces it.

F. Docs: RECIPES.md:28 and KIT_SPEC.md:39,51 describe the whole-room serpentine outline instead of partitions.

Option B (needs owner/AI sign-off; not recommended by default): use only the routed lanes (hub segment centre->(axis,cross) plus spokes, which is what graphRoute actually walks) instead of the full axes. The prototype measured a median curved fraction of 0.55 instead of 0.37 for unfiltered halls, and more wave bulges at mid-wall. It relaxes the full-axis rule that dressing obeys today.

**check:** 1) KIT (Blender, modules_arch.validate(), every Swerve* component):
- All 36 components are present.
- Collider-union coverage of the face (points 0.1 behind the face, 0.5 grid) and of the deck top annulus is 100%.
- No collider protrudes more than 0.3 past the face.
- The End marker matches the analytic end within 0.01 / 0.05 degrees.
- End cross-sections equal the straight pieces' cross-sections within 0.01.
- Cove profile is concave (F1): the profile centre lies on the room side.
- Tris <= 4000.
- test_level2_kit_import.py asserts the 36 components install as DoubleSided non-colliding MeshParts with invisible colliding collider Parts, and that ground colliders carry Level2_EntityGround.

2) LAYOUT (pure data, 400 seeds, test_level2_kit_layout.py, with an INDEPENDENT Python oracle, not a port of planSwerve):
- Per map: 2 <= swerve halls <= 4, all Role=='Hall'.
- Each loop closes within 0.01 with heading continuity <= 0.1 degrees at every joint.
- Sampling the face polyline and the deck front (+9.5) every 0.5 stud:
  - 0 <= d <= the rectangle;
  - no point within 3 of: either full centre axis (+-17), any door spoke (+-17 from wall to centre), any 30x38 approach, or any 34x8 mouth;
  - d == 0 exactly on [cross-20, cross+20] for every door on that wall.
- Minimum radius >= 16.
- Every corner without an arc uses radius <= gap-3 to the nearest door hole.
- Patrol-node positions lie inside the outline with >= 14 clearance from the face.
- Print curved-fraction p10/p50/p90 (expected about 0.37/0.49/0.60).

3) BUILDER (fake engine, test_level2_kit_world_builder.py; raise its seed list to about 40 and add the layout test's worst seeds), per swerve hall:
- No CurveWall_* or Walkway_Bend16 in the hall.
- Wall coverage: for every planned segment, sample the face every 1 stud at y in {0.5, 2.9, 5.8, h-1}. The point 0.2 behind the face must be inside some CanCollide CanQuery Part.
- Deck coverage: deck-top samples every 0.5 stud lie within 0.05 under the top of a CanCollide part with Level2_EntityGround.
- Swerve wall and deck colliders go through the EXISTING obstacle asserts at 1316-1375 (centre lanes, approach, mouth, 34-wide spoke path). Extend the obstacle set beyond Level2_Dressing models.
- No CoveTop64/CoveBase64/CornerCove/WallVoid centre lies behind the outline.
- Every reservation-placed object (LightWell, DrainHole, open-sky marker) lies inside the outline shrunk by half-size+2.
- Patrol nodes are inside the outline with >= 14 clearance from any swerve collider.
- Existing check_hall_shell (rectangle slab, collars, sills/lintels) still passes unchanged.
- World descendants <= 8500 for every seed.

4) WORLD (Blender, world_check.py on dump_world.py dumps of 837834/1/101 plus the 3 seeds with the most swerve halls):
- Add per-hall dead-region polygons (rectangle minus outline).
- collision_check: no flood-filled capsule voxel lands in a dead region.
- visual_check: sample points only inside the outline. For every ray, the first hit must not lie in a dead region, so the backstop is never visible. No new leak rays.
- backface_check passes for the Swerve* chunks.

**risks:** - Under the binding full-axis lane contract a swerve hall reads as a big rounded blob, not a fully wavy room. Large corner arcs (24-64) plus 0-3 S-bulges; straight sections remain at every door (+-20) and wherever a centre axis or a spoke meets the wall. That is measured median 49% curved for the chosen halls. If the owner wants more waves, Option B (routed lanes only) needs an explicit decision. Settle with an owner review render of 2-3 planned halls before modelling all 36 pieces.
- The statistics come from the offline stub RNG (Park-Miller), so live per-seed maps differ, but the distributions should hold.
- The eligibility post-pass changes the Type of some halls (demotion and promotion), so pinned or debug seeds and the dumped worlds change.
- Coplanar 0.5-stud overlaps can z-fight on grout; mitigated by the 0.02 recess but must be eyeballed in Studio.
- The cove profile must come from F1's corrected shared function, or the swerve will reproduce the bullnose.
- The instance budget is tight (8164 measured worst against 8500).
- Terrain water is deliberately left as the rectangle (hidden behind the skin). If the F5 fix reshapes water per wall, swerve halls must keep rectangle water or water will stop short of the curved face.
- Offline green is not Studio green. Needs a play test that walks the deck loop, hugs the arcs (no snag on the deck wedges) and checks the Pool Slide's chase through a swerve hall.

**files:** G:/Roblox/MongoTV/tools/level2_poolrooms/modules_arch.py, G:/Roblox/MongoTV/ServerScriptService/Level 2 Systems/Level 2 Kit Layout Generator.ModuleScript.lua, G:/Roblox/MongoTV/ServerScriptService/Level 2 Systems/Level 2 Kit World Builder.ModuleScript.lua, G:/Roblox/MongoTV/tools/tests/test_level2_kit_layout.py, G:/Roblox/MongoTV/tools/tests/test_level2_kit_world_builder.py, G:/Roblox/MongoTV/tools/tests/test_level2_kit_import.py, G:/Roblox/MongoTV/tools/level2_poolrooms/world_check.py, G:/Roblox/MongoTV/artifacts/level2-poolrooms-20261003/RECIPES.md, G:/Roblox/MongoTV/artifacts/level2-poolrooms-20261003/KIT_SPEC.md

**refs:** ServerScriptService/Level 2 Systems/Level 2 Kit World Builder.ModuleScript.lua:609-705 (CurvedChannel branch: CurveWall_S48 619-645, CurveWall_Q16 647-698, Walkway_Bend16 699-705); ServerScriptService/Level 2 Systems/Level 2 Kit World Builder.ModuleScript.lua:288-342 wallShell (coveRun calls 329-330, 340-341); ServerScriptService/Level 2 Systems/Level 2 Kit World Builder.ModuleScript.lua:268-286 coveRun; ServerScriptService/Level 2 Systems/Level 2 Kit World Builder.ModuleScript.lua:344-379 cornerCoves; ServerScriptService/Level 2 Systems/Level 2 Kit World Builder.ModuleScript.lua:427-473 placeWalkways; ServerScriptService/Level 2 Systems/Level 2 Kit World Builder.ModuleScript.lua:187-230 clearPocket/reserveAt/reservePocket (lane contract: centre axes +-17 over the full extent, door spokes +-17 wall-to-centre); ServerScriptService/Level 2 Systems/Level 2 Kit World Builder.ModuleScript.lua:759-766 WallVoid at 25% along the South/East wall; ServerScriptService/Level 2 Systems/Level 2 Kit World Builder.ModuleScript.lua:1195-1203 nodes() patrol nodes at +-0.32 W/D (Pool Slide spawn anchors: Pool Slide Controller 209-225); ServerScriptService/Level 2 Systems/Level 2 Kit World Builder.ModuleScript.lua:1233-1243 per-hall build order; ServerScriptService/Level 2 Systems/Level 2 Kit Layout Generator.ModuleScript.lua:26-30 HALL_TYPES (CurvedChannel weight 20), 430-454 allowedHallType/drawHallType, 489-501 type assignment in decorate, 929-933 validateKit hall-type check; ServerScriptService/Level 2 Systems/Level 2 Pool Foam Navigator.ModuleScript.lua:182-208 findHall (rectangle containment), 233-322 graphRoute (centre -> (axis,cross) -> door spoke); ServerScriptService/Level 2 Systems/Level 2 Pool Slide Navigator.ModuleScript.lua:293-328 same hub/spoke route; tools/level2_poolrooms/modules_arch.py:224-231 curve_path, 233-265 wall_from_path (cap from y=0), 268-272 curve_wall, 92-103 arc_boxes, 276-293 path_deck, 514-536 build() registration (526-528); tools/tests/test_level2_kit_world_builder.py:1376-1397 (asserts 2-4 CurveWall models), 1316-1375 lane/approach/mouth obstacle asserts (Level2_Dressing only), 606-726 check_hall_shell, 1658 8500 budget; artifacts/level2-poolrooms-20261003/RECIPES.md:28, KIT_SPEC.md:39 and :51

### Other problems seen
- CORNER COVES OVERLAP DOOR OPENINGS (all hall types). cornerCoves (Kit World Builder 344-379) picks R8/16/24 from hall size alone and ignores doors. Over 400 seeds, 3193 of 11813 big halls (27%) have a door hole edge closer to a corner than the cove radius. Breakdown: Open R24 1689, Narrow R24 1179, Narrow R16 426, Open R16 399, Open R8 122, plus PressureDoor cases. Example: seed 314188 hall 5, South door cross 236, gap 10 < R24, where the corner cove stands about 4.5 studs proud of the tunnel collar. Fix: radius = largest of {24,16,8} that is <= gap-3, else a square corner.
- F1 ROOT CAUSE CONFIRMED in modules_arch.py cove() 122-141. The base profile y=3 sin a, z=3-3 cos a and the top profile y=3-3 sin a are quarter circles centred ON the wall/floor (and wall/ceiling) corner, so CoveBase64/CoveTop64 are convex bullnoses, not coves. Image 1 shows this. cove_corner (144+) and the profile should be checked the same way.
- CurveWall_* meshes and colliders start at y=0 (wall_from_path cap, modules_arch 233-265; collider cf y=17, size 34 for H34). In pool halls the partition floats 1.6-2.0 studs above the basin floor with water under it, and it does not overlap the ceiling by +2. This is moot once the partitions are removed.
- coveRun (268-286) and placeWalkways (439-446) stretch CoveTop64/CoveBase64/Walkway_Straight32 up to about 4x along their length (walls up to 272), which breaks KIT_SPEC's one-tile-scale rule along coves and decks.
- CorridorHall occurs only 23 times in 400 seeds despite weight 15: its >= 2.2 aspect ratio is rarely met, so drawHallType re-rolls.

### Notes
I didn't edit anything in the repo. Scratch work is in G:/Roblox/_local/l2fix/F9/:
- layouts400.json: 400 real Kit Layout Generator layouts from the test harness's run_layouts, including seed 837834, which resolves to 1570937 and matches the world dump.
- swerve_proto3.py: the planner prototype; it measures curved fraction, corner radii and bulge use.
- elig.py: eligibility per hall and swerve-hall count per map.
- plot_outlines.py with outlines_1570937.png and outlines_82309184.png: planned walls and decks drawn over the lane keep-clear areas, full-axis versus routed-lane variants.

What settles the open look question: show the owner Blender renders of 2-3 planned halls, built from the prototype outline, before the 36 kit pieces are modelled. Also confirm with the AI owner whether Option B (routed lanes only) is acceptable.

Assumptions:
- Pool Slide anchors are the patrol, den and navigation nodes (Pool Slide Controller 209-225), with AgentRadius <= 12.
- Pool Foam only patrols Kids halls, which are never swerve halls.
- DeepEndMax defaults to 2.0 (not set in Configuration), so basin floors are at most 2 below FloorY.

## F4-A - Lighting dead zones: no local light reaches any hall floor, so the preview is lit only by flat ambient

**rootCause:** The builder creates hall lights in exactly one place: BigPool LightRound emitters, every third one, as PointLight Range 25 hung at CeilingClass-0.75. Ceilings are 34/42/52, so the floor is 30-50 studs away and these lights never reach it. No other hall Type, chamber, Arrival or ExitHall gets any light. Every kit light marker except LightRound.Light and the corridor LampLight is dropped by cloneComponent (markers are read, then the folder is destroyed): SunSlit.Light (SurfaceLight 2/32), Chamber_A-D DaylightPorthole/DaylightSlit (Range 20), ArrivalDoor.ArrivalLampGlow, ExitSkylight.LightOpening, LightWell/SpiralStairWell OpenSky. The approved Blender assembly instead puts lamp() area lights in every hall, a daylight spot under every well and extra BigPool lamps (assemble_level.py:315-323, 417-428). The preview lighting profile compensates with high flat ambient (Ambient 126,124,112; Brightness 2.2; Exposure +0.2), which is why the owner's shots look evenly lit and shadowless, i.e. half finished, next to the renders.

**occurrences:** Measured over 12 seeds of the real builder output (837834, 1, 101, 1182081016, 738163940, 484836893, 20261003, 35746866, 51232729, 66718592, 82204455, 97690318). Floor sample points (8-stud grid, FloorY+3) outside every light's range: Arrival 100%, ExitHall 100%, BigPool 100% (its lights stop 5-25 studs above the floor), ColumnHall/CurvedChannel/VaultArcade/SpiralWell 99.9%, PaddlingRoom 99.5%, PumpHall 98.1%, chambers 51% (the lit half is corridor-lamp spill at pipe mouths). Overall 96.5% unlit. Seeds without a BigPool (1, 35746866) have no hall light at all. 355 of about 370 big halls fail a 60%-coverage bar.

**fixDesign:** 1) Builder: add hallLights(ctx,hallModel,hall,openings) after dressHall. For every opening openSky returns (LightWell/SpiralWell/PumpHall/ExitHall), add an invisible emitter at (X, FloorY+CeilingClass-0.5, Z) carrying a SpotLight: Face=Bottom, Angle=70, Range=60 (the Roblox maximum), Brightness=3, Color=(255,224,181). Only the 6 largest openings by hall area get Shadows=true (spec: at most 6 shadow casters). 2) BigPool: the every-third LightRound emitter becomes a SpotLight Face=Bottom, Range=60, Angle=110, Brightness=1.4, so it reaches 52-stud floors. Raise the LightRound pivot from CeilingClass-0.6 to CeilingClass-0.55 so the 0.55-tall bezel is flush; today it hangs 0.05 below the tile. 3) Instantiate the kit markers that exist: SunSlit.Light as a SurfaceLight Face=Front, Brightness 2, Range 32; Chamber Daylight* as a SurfaceLight, Range 20, Brightness 1.5; ArrivalLampGlow as a PointLight, Range 16, Brightness 1. 4) Budget: roughly 25 well spots, 24 BigPool rounds (capped), 20 chambers, about 40 tunnels, 3 pumps and 2 arrival lights is about 114, which is over the 80 cap at :152/:1303. Either the owner raises the cap to 128 (the shadow cap of 6 is the real perf limit), or tunnel lamps go on every second tunnel (about -20) and chamber lights only on chambers whose pipe leads to a pump/drain. 5) Lighting Controller preview profile: Ambient (126,124,112)->(78,80,72), OutdoorAmbient (118,120,110)->(90,92,84), ExposureCompensation .2->0. These are tuning knobs: confirm against renders/_sheet.jpg in a Studio play session.

**check:** Offline, in test_level2_kit_world_builder.py, over 10+ seeds. Collect every PointLight/SpotLight/SurfaceLight from the harness Objects; dump_world.py currently exports only BaseParts, so add the light classes with Range/Angle/Face/Shadows and the parent CFrame. For each non-Small hall, sample the floor on an 8-stud grid at FloorY+3. A point is lit if it is within Range of a PointLight, or within Range and inside Angle/2 of a SpotLight's face normal. Assert: lit fraction >= 0.6 per hall; total lights <= the budget; Shadows=true count <= 6; every opening has a light within 2 studs of its centre. The coverage part is prototyped in G:/Roblox/_local/l2fix/F4general/check_misc.py section 1 (prints 355 failures today).

**risks:** Many more lights cost GPU on low-end and mobile devices; keep Shadows off except on 6. Adding lights also needs the darker ambient, otherwise the halls just get brighter. Final numbers need a Studio look, because offline coverage is not appearance. The owner set the 80-light budget (KIT_SPEC section 5), so raising it is their decision.

**files:** ServerScriptService/Level 2 Systems/Level 2 Kit World Builder.ModuleScript.lua, StarterPlayer/StarterPlayerScripts/Level 2 Lighting Controller.LocalScript.lua, tools/tests/test_level2_kit_world_builder.py

**refs:** ServerScriptService/Level 2 Systems/Level 2 Kit World Builder.ModuleScript.lua:550-561 (BigPool LightRound, PointLight 1.2/25 every 3rd); ServerScriptService/Level 2 Systems/Level 2 Kit World Builder.ModuleScript.lua:100-113 (cloneComponent keeps markers only as return value, destroys Markers); ServerScriptService/Level 2 Systems/Level 2 Kit World Builder.ModuleScript.lua:151-159 (addLight, hard 80 cap); ServerScriptService/Level 2 Systems/Level 2 Kit World Builder.ModuleScript.lua:1031-1039 (only corridor LampLight used); ServerScriptService/Level 2 Systems/Level 2 Kit World Builder.ModuleScript.lua:1301-1308 (hallLightLimit=80-tunnels-3); ServerScriptService/Level 2 Systems/Level 2 Kit World Builder.ModuleScript.lua:334-335,748,752,756,1175 (SunSlit/LightWell/ExitSkylight/ArrivalDoor cloned, markers ignored); StarterPlayer/StarterPlayerScripts/Level 2 Lighting Controller.LocalScript.lua:125-136 (preview flat ambient); tools/level2_poolrooms/modules_arch.py:448-462 (LightRound marker range 25), 473-483 (SunSlit Light marker); tools/level2_poolrooms/modules_tunnel.py:488-490 (Daylight markers); tools/level2_poolrooms/assemble_level.py:315-323 (approved look: lamp per hall + daylight per well)

## F4-B - Everything placed at FloorY floats above the sunk/sloped pool basin (columns, piers, partitions, spiral wells, walkways, islands, drains, steps)

**rootCause:** floorShell sinks every flooded hall's floor to FloorY-0.8 at the shallow end and FloorY-DeepEnd at the deep end (tilted along PoolAxis). DeepEnd is clamped to 1.6..2.0 by Configuration.DeepEndMax. Every dressing placement still uses Y=FloorY: patterned(), reservePocket (pos.Y=hall.FloorY), fitVaultPier, CurveWall/Spiral cf, Walkway_*, PoolSteps, DrainHole at FloorY-0.7, ExitPlatform/ExitSpiral. The kit meshes all start at local y=0 (Column lathe 0..H, CurveWall 0..H, VaultPier 0..42, SpiralStairWell -0.1..), and the walkway deck bottom is at -0.35. Nothing reaches down to the basin, so in Roblox's 0.35-transparency water every base hovers with a visible slot under it. DrainHole is also an 8x8 'Tile' (white) plate, so on the aqua floor it reads as a white square. In PaddlingRoom (floor -0.8) its black void disc (-0.19..-0.13 below the pivot) sits under the floor, so only a plain white square shows.

**occurrences:** 12 seeds, every flooded hall Type. Gap between the visible base and the basin floor: Column_D10/D16 (ColumnHall, BigPool, SpiralWell) 0.8-1.9 studs, over 700 instances. VaultPier 0.8-1.9 (156). CurveWall_Q16/S48 0.8-1.8 (130). SpiralStairWell 0.7-1.7 (24). Column_D6 (PaddlingRoom) 0.8 (120). Walkway_Straight32 decks 0.45-1.05 (about 1,280 deck parts, every hall with a walkway incl. PaddlingRoom and ExitHall). Walkway_End 0.6-1.55 (50). Walkway_Bend16 0.5-1.45 (104). PoolSteps_Straight12 0.2-0.73 at deep ends (about 330). DrainHole: all 1,181 drains are not resting on their floor, floating up to 1.04 in pools and buried in PaddlingRooms (239), where only the white plate shows. ExitPlatform/ExitSpiral 1.3-1.6 above the ExitHall basin in all 12 seeds; ExitHall is a pool because PoolType 'Slide' is not 'Dry'.

**fixDesign:** Kit, so every caller is fixed at once. Author every floor-standing piece down to y=-4, the same rule KIT_SPEC section 6 already applies to walls. The deepest basin is 2.0 (3.5 cap), so -4 always reaches the floor; in dry halls the extra length hides inside or under the 1-stud floor slab. Nothing is rescaled, so tile pitch is unchanged. Changes: column(): lathe [(-4,r),(h,r)], collider centre (0,(h-4)/2,0), size h+4. wall_from_path()/curve_wall(): bottom -4. pier(): part and collider centre (0,19,0), size (5,46,5); builder fitVaultPier then sets Size.Y=height+4 and centre pos.Y+(height-4)/2. spiral(): core lathe from -4. path_deck(): bottom -4. walkway('Straight'): deck Part centre (0,-1.78,0), size Y 4.445 (top .445 unchanged); bullnose prisms bottom -4. Walkway_End arc_solid ys (-4,.45). steps(): each Step Ground box from its top down to -4 (centre (top-4)/2, size 4+top), with prisms to match. ExitPlatform/ExitSpiral: plinth/skirt to -4 (or flag to the F11 owner). Builder, drains: skip drains when basinDepth==0. Otherwise compute the floor surface at (x,z) from the floor Part (top CFrame * (0,.4,0) plane, like floor_planes in geo.py) and pivot = surfacePoint + up*0.03 with the floor's tilt rotation. In pools set the plate's MaterialVariant to 'PR Tile Aqua' so it is not a white square.

**check:** G:/Roblox/_local/l2fix/F4general/check_float.py, run over worlds dumped by dump_many.py (12 seeds today; use 30+). For every visible BasePart under a big hall whose AABB bottom is within FloorY-4.5..FloorY+0.6, excluding hall walls/sills/lintels, floors and coves, evaluate the basin floor plane under the 4 bottom corners plus the centre. Assert bottom <= floorTop+0.05 everywhere: 0 floating, currently thousands. Drains: |plate top - floor top| <= 0.06 and plate MaterialVariant == 'PR Tile Aqua' in pools (check_misc.py section 4). Port both into test_level2_kit_world_builder.py using the harness Objects plus the manifest chunk bounds for MeshParts.

**risks:** Collider changes alter Pool Foam/Pool Slide navigation slightly: columns now block under-column swimming, which is correct. Reinstalling the kit changes ManifestSha256/KitBuild. Walls' existing 'base -4' rule stays consistent. Hidden geometry adds a few triangles per piece.

**files:** tools/level2_poolrooms/modules_arch.py, tools/level2_poolrooms/objectives.py, ServerScriptService/Level 2 Systems/Level 2 Kit World Builder.ModuleScript.lua, assets/level2/poolrooms-kit/export (rebuild + reinstall with tools/level2_blender/import_kit.py --profile poolrooms), tools/tests/test_level2_kit_world_builder.py

**refs:** ServerScriptService/Level 2 Systems/Level 2 Kit World Builder.ModuleScript.lua:233-257 (basinDepth/floorShell: sunk tilted floor); ServerScriptService/Level 2 Systems/Level 2 Kit World Builder.ModuleScript.lua:220 (reservePocket returns Y=FloorY); ServerScriptService/Level 2 Systems/Level 2 Kit World Builder.ModuleScript.lua:511-517 (patterned at FloorY); ServerScriptService/Level 2 Systems/Level 2 Kit World Builder.ModuleScript.lua:483-490 (fitVaultPier bottom = FloorY); ServerScriptService/Level 2 Systems/Level 2 Kit World Builder.ModuleScript.lua:624-629,682-684,712 (curve walls, spiral at FloorY); ServerScriptService/Level 2 Systems/Level 2 Kit World Builder.ModuleScript.lua:435-438,452-460 (walkways/steps at c.Y); ServerScriptService/Level 2 Systems/Level 2 Kit World Builder.ModuleScript.lua:546-548,607-608,705 (Walkway_End/Bend at FloorY); ServerScriptService/Level 2 Systems/Level 2 Kit World Builder.ModuleScript.lua:767-779 (DrainHole at FloorY-0.7, flat, Tile); ServerScriptService/Level 2 Systems/Level 2 Kit World Builder.ModuleScript.lua:924-926 (ExitPlatform/ExitSpiral at FloorY); tools/level2_poolrooms/modules_arch.py:174-183 (column 0..H), 233-273 (curve walls 0..H), 276-318 (path_deck/walkway bottom -.35), 321-340 (steps), 386-409 (spiral core 0..H+8), 441-445 (pier 0..42), 495-511 (drain plate, Tile)

## F4-C - Door approaches into pools: 1-stud trench, a hidden first step under the walkway, fixed 3-step stairs, dry-hall steps and walkways, +1.0 pipe lips

**rootCause:** placeWalkways puts PoolSteps_Straight12 at boundary+5, but every tunnel or pipe mouth threshold ends at boundary+4. That leaves a 1-stud-wide, 12-stud-long trench down to the pool floor (0.8-2.0 deep) in front of every step. On the two long walls a Walkway_Straight32 (deck 1.55..10.95 from the wall, top +0.445) runs straight over the steps: step 1 (top -0.6) is buried inside the deck, and the walker drops 1.65 from the deck edge to step 2. The kit stairs are always 3 x 0.6 regardless of the local basin depth, so at the shallow end steps 2-3 are buried and only a 0.2 lip remains. Walkways and steps are also built in dry halls (PumpHall, all door sides; ExitHall too): steps fully buried, walkway a pointless 0.45 curb. Narrow-pipe thresholds are authored with sill=1 (top FloorY+1.0), giving a 1-stud lip at every pipe mouth in halls and chambers next to 0.0 thresholds and 0.445 walkways. These are three different levels at adjacent floors. In PaddlingRooms the steps' collision is replaced by a visible 12x12 slab at top FloorY that ends with a 0.8 drop.

**occurrences:** G:/Roblox/_local/l2fix/F4general/check_approach.py samples walkable ground every 0.5 stud along each door's centre line, 12 seeds. About 500 of about 1,100 hall-side door approaches drop more than 0.7 studs in one step. Profiles: (a) walls without a walkway: 0.0 to 4.0, then pool floor (-0.8..-2.0) at 4.5, step at -0.6 from 5.0; seen in ColumnHall, CurvedChannel, VaultArcade, SpiralWell, BigPool, ExitHall, CorridorHall. (b) walls with a walkway: 0.0, then 0.445 deck to 11.0, then -1.2 (a 1.65 drop), then -1.8. (c) PaddlingRoom: 0.0 slab to 15.5, then a 0.8 drop. (d) pipe mouths: +1.0 to 4.0, then -0.82. Pipe thresholds sit at +1.0 in every room: 557 chamber pipe mouths and about 195 hall pipe mouths. PumpHall: 236 buried step Parts; walkway curbs on dry floors in every PumpHall.

**fixDesign:** 1) placeWalkways returns early when basinDepth(hall)==0 (PumpHall, Arrival and dry halls): no walkways, no steps. 2) Steps start where the threshold ends: pivot at boundary+4, not +5. Tunnel doors are 34 wide, so place three PoolSteps_Straight12 at cross-12, cross, cross+12 (or add a PoolSteps_Straight34 kit piece). Pipe doors keep one. 3) On a wall that carries a walkway, the walkway is the landing: pivot the steps at the deck's outer edge (boundary+11) and at Y=FloorY+0.445, so tops run -0.155/-0.755/-1.355, with steps skirted to -4 (F4-B). Every rise is then <=0.6, with no hidden step and no trench. 4) Pipe lip: builder adds 'Level 2 Passage Mouth Step' Parts, 12 wide x 2 deep, top FloorY+0.5, at boundary+4..+6 for each Narrow corridor door, in chambers too (on the Dry Threshold), giving two 0.5 risers. The cleaner option is the kit change sill 1->0 with the pipe placed 1 stud lower, but that moves the -2..12 wall hole and chamber Below/Above Socket parts, so it is a larger change. 5) PaddlingRoom handled in F4-D.

**check:** Port check_approach.py into the offline tests. For every door side of every non-Small hall, sample from boundary to boundary+24 at 0.5 steps. Ground = max top of collidable Parts/colliders containing (x,z) below FloorY+1.2, else the basin floor plane. Assert: no step down > 0.65, no step up > 1.0 (0.6 preferred), and no sample hits the basin floor before the last step (no trench). Assert no PoolSteps/Walkway exists in halls with basinDepth==0. Today about 500 failures in 12 seeds.

**risks:** Steps at +4 may meet the walkway reservation and corner coves on short walls; doors are kept 17+ from corners by the layout, so this should fit. Three step pieces per tunnel add about 120 Parts per map, which is within the 8,500 budget. Pool Foam ground attributes must stay on the new step Parts.

**files:** ServerScriptService/Level 2 Systems/Level 2 Kit World Builder.ModuleScript.lua, tools/level2_poolrooms/modules_arch.py (optional PoolSteps_Straight34), tools/tests/test_level2_kit_navigation.py or test_level2_kit_world_builder.py

**refs:** ServerScriptService/Level 2 Systems/Level 2 Kit World Builder.ModuleScript.lua:427-473 (placeWalkways: walkway full wall length; steps at +5; curved replaced by 12x12 slab; runs in dry halls); tools/level2_poolrooms/modules_tunnel.py:170-176 (threshold 4 deep into the hall; pipe sill=1); tools/level2_poolrooms/modules_arch.py:296-318 (walkway top .445), 321-340 (fixed 3 steps, rise .6); artifacts/level2-poolrooms-20261003/RECIPES.md 'every door/pipe mouth is reached by a walkway or by pool steps'

## F4-D - PaddlingRoom curved steps are misplaced: half-annulus off to one side and 17 studs out through the wall; collision swapped for a flat slab

**rootCause:** PoolSteps_Curved is a half-annulus with radii 10..22, local x in [0,22], z in [-22,22] (chunk bounds). The builder places it like the straight piece: pivot at boundary+5 with the door yaw. The ring therefore lies to one side of the door, and its local +z half (17 studs) passes through the hall wall into the corridor or void. The builder then destroys the 48 'Step N Ground' colliders and drops a visible 12x12 'Paddling Threshold Ground' slab (top FloorY) on top. The visible steps no longer match the collision, and the slab is coplanar with the corridor threshold (z-fight, see F4-M). In wet tunnels the ring's step tops (-0.6) sit above the channel floor (-1.5) inside the tunnel.

**occurrences:** All 207 PoolSteps_Curved placements in 12 seeds extend outside their room, by 17.0 studs max. Every door of every PaddlingRoom (5 per map, the kids area). Visual check in Studio: any kids room door.

**fixDesign:** Pivot on the wall face at the door centre (boundary+1.75, Y=FloorY) with yaw = doorYaw + 90 deg, so local +x points into the room. The half ring then lies wholly inside the room, centred on the door and 44 wide along the wall (doors are 12/34 wide, at least 17 from corners). Keep the kit's 48 Step Ground colliders; delete lines 462-468 (Ground destroy + 12x12 slab). Fill the ring's empty r<10 centre with a landing: a Cylinder Part, diameter 20, 0.7 thick, axis Y, top FloorY, centred on the wall face so half of it is hidden in the wall. That gives a semicircular landing flush with the threshold. Better, add an authored 'PoolSteps_Curved_Landing' disc to the kit.

**check:** check_misc.py section 5: every PoolSteps_Curved MeshPart AABB lies inside its room interior (MinX+1.75..MaxX-1.75 etc.). Today 207 of 207 fail. The F4-C ground profile must pass through the curved steps, and each curved-step model must keep >=48 collidable 'Ground' Parts.

**risks:** The half ring's 22-stud radius may overlap the walkway band on walkway walls; reserve the band (F4-F) or skip the walkway on PaddlingRoom door walls. Keep the Pool Foam spawn pocket (makeKids reservation) clear.

**files:** ServerScriptService/Level 2 Systems/Level 2 Kit World Builder.ModuleScript.lua, tools/level2_poolrooms/modules_arch.py (optional landing piece)

**refs:** ServerScriptService/Level 2 Systems/Level 2 Kit World Builder.ModuleScript.lua:450-472; tools/level2_poolrooms/modules_arch.py:321-340 (curved: angles -pi/2..pi/2 around local +x)

## F4-E - Non-uniform MeshPart rescaling stretches/squeezes the tile texture (coves, walkway bullnoses, ExitHall corner coves, curve walls, spiral wells)

**rootCause:** Tile UVs are baked into the mesh at a fixed pitch (prkit UVs in metres*S). The builder resizes MeshParts non-uniformly, which scales geometry but not UVs, so the tiles stretch. coveRun scales CoveBase64/CoveTop64 along X by (b-a+1)/64 for every wall run between openings. placeWalkways scales Walkway_Straight32, including its two bullnose mesh strips, by (wall length-3)/32. cornerCoves stretches CornerCove meshes vertically by CeilingClass/52 in ExitHall (96). Curve walls and spiral wells are shrunk horizontally (0.3-0.9) when a hall is crowded, which also thins the 3-stud wall. Owner image 3 shows the effect: the cove tiles are visibly wider than the wall tiles next to them.

**occurrences:** 12 seeds, per-axis scale relative to each chunk's native size. CoveBase64 and CoveTop64: 2,272 pieces each, X scale 0.04 (tiles 25x too dense on short runs) to 3.75. Walkway_Straight32 bullnoses: 686, 3.16-7.41x. CornerCove_R24_H52 in every ExitHall: 48, 1.85x vertical. CurveWall_S48/Q16: 65, 0.63-0.9. SpiralStairWell: 6, scaled below 1. Every hall wall run and every walkway.

**fixDesign:** No non-uniform mesh scaling outside [0.9,1.1]. Coves and walkways: add 4- and 8-stud pieces to the kit (CoveBase4/8, CoveTop4/8, Walkway_Straight4/8; 16/32/64 exist). Fill each run of length L greedily with 64/32/16/8/4 so the pieces sum to S = 4*round(L/4), and scale every piece uniformly along X by L/S. The deviation is then <=2/L: at most 3% for L>=64 and at most 12.5% at L=16 (accept, or use the 4-piece remainder). Export the run pieces without the ±0.5 end overlap, or offset chained pieces by their nominal length, so identical surfaces do not overlap and z-fight. Keep the ±0.5 only where a run meets a corner cove or collar. ExitHall: export CornerCove_R*_H96 and CoveTop/Corner placement at 93, or stack an H52 and an H42 corner piece. Curve walls/spiral: choose a smaller authored size (Q16/Q32/S48/S64 exist) instead of scaling; coordinate with the F9 redesign.

**check:** check_misc.py section 2 (offline): for every MeshPart in the build, find its chunk by (Level2_KitComponent, name suffix) in manifest.json and compute size/nativeSize on each axis longer than 0.2. Assert max/min <= 1.1. Today 5,355 violations over 12 seeds. Port to the harness, where the MeshPart Size and component attribute are available.

**risks:** How MeshPart MaterialVariant textures follow UVs under resize is inferred from the UV-baked kit and owner image 3, not measured. To settle it, put one stretched CoveBase64 next to an unscaled one in Studio. More pieces per run add instances (about +2 per wall run), and the descendant budget needs re-measuring.

**files:** tools/level2_poolrooms/modules_arch.py, tools/level2_poolrooms/build.py, ServerScriptService/Level 2 Systems/Level 2 Kit World Builder.ModuleScript.lua, tools/tests/test_level2_kit_world_builder.py

**refs:** ServerScriptService/Level 2 Systems/Level 2 Kit World Builder.ModuleScript.lua:268-286 (coveRun factor); ServerScriptService/Level 2 Systems/Level 2 Kit World Builder.ModuleScript.lua:438-448 (walkway factor); ServerScriptService/Level 2 Systems/Level 2 Kit World Builder.ModuleScript.lua:356-365 (corner cove vertical factor); ServerScriptService/Level 2 Systems/Level 2 Kit World Builder.ModuleScript.lua:619-639,687-695 (curve wall scale); ServerScriptService/Level 2 Systems/Level 2 Kit World Builder.ModuleScript.lua:711-724 (spiral scale); tools/level2_poolrooms/modules_arch.py:122-141 (cove UV), 296-318 (walkway bullnose prisms)

## F4-F - Dressing is packed into the walkway band and into the +X+Z corner (edge-first deterministic reservePocket)

**rootCause:** reservePocket scans quadrants in a fixed order (+X+Z first), from the walls inward, with a 6-stud margin. The walkway strips (deck 1.55..10.95 from both long walls) are never reserved. So the first legal pocket for drains, columns, curve-wall quarters, spiral wells, Walkway_Bend and light wells is almost always pressed against a wall in the +X+Z corner, overlapping or under the walkway. All four drains of a hall sit in a row 14 studs apart along one wall.

**occurrences:** 12 seeds: 533 of 1,181 drains partly under a walkway deck. 569 dressing/deck intersections: Column_D16 and D10 pierce the deck by up to 2.95 studs in ColumnHall, BigPool, SpiralWell and PaddlingRoom (Column_D6); CurveWall_Q16 4.23; SpiralStairWell 4.42; Walkway_Bend16 crosses the straight deck by 8.8-9.4 in CurvedChannel and VaultArcade. Drain quadrants: +X+Z 787, +X-Z 298, -X+Z 70, -X-Z 26. 769 of 1,181 drains sit exactly 11 studs from a wall.

**fixDesign:** 1) placeWalkways appends a reservation per strip: {Position=strip centre, Width=strip length, Depth=9.4+2*3} (3-stud clearance). It already runs before dressHall; makeKids runs before it, so the spawn pocket keeps priority. 2) reservePocket(hall,doors,w,d,res,rng): build the candidate list (same 4-stud lattice), shuffle it with the hall rng (Random.new(hall.LocalSeed+…)) and take the first clear one. Keep determinism per seed. 3) Drains get a minimum spacing of 24 (pass spacing to clearPocket) and are never placed within 12 of a wall that has a walkway. 4) reserveCurve uses the same shuffled order.

**check:** check_misc.py sections 4 and 8: zero AABB overlaps between any 'Walkway Deck' and Column_/CurveWall/SpiralStair/Walkway_Bend/Walkway_End/DrainHole parts (today 569 + 533). Distribution test over 50 seeds: each hall quadrant holds 15-35% of drains/obstacles, and at most 30% of drains sit at the minimum wall offset.

**risks:** Shuffled placement can fail to find a pocket in tight halls where the edge-first scan found one. Keep the asserts (spiral, curve pair, kids pocket) and fall back to the old order on failure. Must keep the AI lanes and door spokes (clearPocket) untouched; test_level2_kit_navigation must still pass.

**files:** ServerScriptService/Level 2 Systems/Level 2 Kit World Builder.ModuleScript.lua, tools/tests/test_level2_kit_world_builder.py

**refs:** ServerScriptService/Level 2 Systems/Level 2 Kit World Builder.ModuleScript.lua:187-230 (clearPocket margin 6; reservePocket fixed scan); ServerScriptService/Level 2 Systems/Level 2 Kit World Builder.ModuleScript.lua:427-449 (walkways not reserved); ServerScriptService/Level 2 Systems/Level 2 Kit World Builder.ModuleScript.lua:475-481,601,699,709,730,744,755,775 (callers); ServerScriptService/Level 2 Systems/Level 2 Kit World Builder.ModuleScript.lua:647-663 (reserveCurve also edge-first)

## F4-G - Repeated identical layouts: every ColumnHall has the same core, the same WallVoid and well in every hall, 4 chamber prefabs ~20x per map

**rootCause:** ColumnHall dressing is fixed: four Column_D10 at (±min(32,W/2-14), ±min(32,D/2-14)) with ±2 jitter, plus two Column_D16 on one diagonal at ±min(64,·). RECIPES asks for a 'loose jittered grid of Column_D10 (spacing 28-36), 1-2 Column_D16'. BigPool uses five fixed slots. Every non-Arrival/Exit hall gets one WallVoid at the same relative spot (South/East wall, 25% along, 0.6·CeilingClass). Every hall except BigPool/Arrival/SpiralWell gets exactly one LightWell_R6 (RECIPES: 1-3, R6/R10). The small rooms are four prefabs (Chamber_A-D) with no variation, about 19.5 per map.

**occurrences:** 12 seeds: all 93 ColumnHalls share the identical D10 square at ±32; 26 are fully identical including the D16 pair (mirror-folded, 8-stud bins). 35 of 60 PaddlingRooms are identical. ColumnHall is the most common type (5-14 per map). Chamber prefab counts over 12 maps: D 84, B 62, C 53, A 35. One identical WallVoid per hall, roughly 23-28 per map.

**fixDesign:** ColumnHall: spacing s = rng:NextInteger(28,36); grid origin offset rng:NextNumber(0,s) on each axis; candidate cells over the whole interior minus lanes, door spokes and walkway bands. Count = clamp(floor(Area/2500),4,12), chosen by rng from the shuffled cells. D16 landmarks: rng 1-2 of the chosen cells. BigPool: rows every 32 along the long axis as RECIPES says, with the row offset and count from the hall. WallVoid: rng picks a wall without doors and an along position in [0.2,0.8], with 0-2 per hall. LightWell: 1-3 by area (Area/18000 as in the assembler), R6 or R10 by rng. Chambers (lower priority): allow 180-degree rotation/mirror where the sockets allow it, and vary the daylight marker side per instance.

**check:** Over 50 seeds, compute each hall's dressing signature: sorted (component family, |dx|/8, |dz|/8) relative to the hall centre, mirror-folded. Assert that per Type at most 5% of halls share a signature with another hall, and that the ColumnHall column count has variance > 0. The repetition part of the prototype is in this report's analysis (signature code inline; same logic as check_misc.py).

**risks:** More columns may block the 34-wide Pool Slide paths: keep clearPocket lanes. Changing the dressing RNG stream changes every seed's look, so previously reviewed seeds (837834) will differ from the review renders.

**files:** ServerScriptService/Level 2 Systems/Level 2 Kit World Builder.ModuleScript.lua, ServerScriptService/Level 2 Systems/Level 2 Kit Layout Generator.ModuleScript.lua (chamber variety, optional), tools/tests/test_level2_kit_world_builder.py

**refs:** ServerScriptService/Level 2 Systems/Level 2 Kit World Builder.ModuleScript.lua:518-533 (ColumnHall fixed pattern); ServerScriptService/Level 2 Systems/Level 2 Kit World Builder.ModuleScript.lua:534-545 (BigPool fixed slots); ServerScriptService/Level 2 Systems/Level 2 Kit World Builder.ModuleScript.lua:746-766 (one LightWell, one WallVoid, same spot); ServerScriptService/Level 2 Systems/Level 2 Kit Layout Generator.ModuleScript.lua:21-24,240-275 (4 chamber prefabs); artifacts/level2-poolrooms-20261003/RECIPES.md (Types table, Light/Darkness lines)

## F4-H - PaddlingRoom columns hard-coded to the 34-stud height end 8 or 18 studs below 42/52 ceilings

**rootCause:** dressHall uses the literal component name 'Column_D6_H34' for every PaddlingRoom instead of 'Column_D6'..suffix. Kids rooms take ceiling 34/42/52, and Column_D6_H42 and Column_D6_H52 exist in the kit but are unused.

**occurrences:** 70 of 120 PaddlingRoom columns in 12 seeds stop 8 or 18 studs under the ceiling with a flat cap, in mid-air.

**fixDesign:** Line 744: placeObstacle(ctx,parent,hall,doors,reservations,"Column_D6"..suffix,10,10), where suffix is already "_H"..min(CeilingClass,52).

**check:** check_misc.py section 3: every visible Column_/CurveWall_/VaultPier part has its top within 0.3 of FloorY+CeilingClass (70 failures today, all PaddlingRoom).

**risks:** None beyond the kit's H42/H52 D6 pieces being installed. They are in manifest.json.

**files:** ServerScriptService/Level 2 Systems/Level 2 Kit World Builder.ModuleScript.lua

**refs:** ServerScriptService/Level 2 Systems/Level 2 Kit World Builder.ModuleScript.lua:743-745

## F4-I - VaultArcade vault bays hang with 3 of 4 corners on nothing; the fallback bay is centred on a pier

**rootCause:** Four bays are placed at (±16, ±16), a 2x2 group with corners at 0 and ±32. Piers are placed only at the four outer corners (±min(32,W/2-15)), because clearPocket forbids anything within 17+w/2 of the centre axes. The five inner and edge corners (0,0), (0,±32) and (±32,0) never get a pier. When W/2-15 < 32 the piers are not at the bay corners at all. If no pier lands on grid, fallbackBay centres a whole bay on the pier position.

**occurrences:** 12 seeds: 121 VaultBay placements; 120 have 3 unsupported corners and 1 (the fallback) has 4. 364 unsupported corners total, every VaultArcade hall including Entity Den VaultArcades.

**fixDesign:** Put bays only where all 4 corners can carry a pier outside the lanes. A pier is 9 wide when reserved, so its centre must be at least 21.5 from an axis. Bay centres at ±37.5 give corners at ±21.5 and ±53.5, which needs a hall half-size of at least 53.5+4.5+6 = 64 (W,D >= 128). Place a VaultPier on each of the 16 corners of the 4 bays, deduplicated. For 96-127 halls, use one bay per quadrant only on the axis that fits; otherwise place piers without vaults. Never place an unsupported bay: remove fallbackBay (:597-600). RECIPES also says bays replace the flat ceiling there; optional, coordinate with the F7/F14 ceiling owner.

**check:** check_misc.py section 7: each VaultBay's 4 corners (pivot ±16) have a 'Pier Tile' (or column) centre within 3.5 studs in XZ. 364 failures today.

**risks:** More piers in VaultArcade reduce open water and may crowd the Walkway_Bend pocket. Re-run test_level2_kit_navigation and the Pool Slide clearance tests.

**files:** ServerScriptService/Level 2 Systems/Level 2 Kit World Builder.ModuleScript.lua

**refs:** ServerScriptService/Level 2 Systems/Level 2 Kit World Builder.ModuleScript.lua:573-608; ServerScriptService/Level 2 Systems/Level 2 Kit World Builder.ModuleScript.lua:483-503 (fitVaultPier, placeVaultBay); ServerScriptService/Level 2 Systems/Level 2 Kit World Builder.ModuleScript.lua:191 (±17 lane rule)

## F4-J - BigPool 'round island' is two half-discs swallowed by the column, leaving floating slivers

**rootCause:** RECIPES asks for a round island (Walkway_End pair) around one column. The builder places Walkway_End at island-5 (yaw 0) and island+5 (yaw pi). Each is a radius-5 half-disc whose flat side is at its pivot, so both lie inside x in [island-5, island+5] and are almost fully inside the D10 column (radius 5). Only the corners of the flat edges poke out, floating 0.6-1.55 over the basin. A Walkway_End pair can never form an island around a 10-wide column; the radius is too small.

**occurrences:** Every BigPool with a placed column: 50 Walkway_End parts floating in 10 of 12 seeds, plus 10 overlapping the wall walkway.

**fixDesign:** New kit piece Island_R10: an annular deck with radii 5.2..10, top .45, bottom -4, bullnose rim, ring of ground colliders. Place it with its pivot at the island column's pivot. No new piece: drop the two Walkway_End calls rather than scaling them (scaling stretches tiles, see F4-E).

**check:** For each BigPool: exactly one island whose centre is within 0.1 of a column centre, outer radius minus column radius >= 4, and bottom on the basin floor (check_float.py). Zero Walkway_End within 6 studs of a column centre.

**risks:** The island (diameter 20) must fit its column's reservation: grow patterned()'s 14x14 to 22x22 for the island column.

**files:** tools/level2_poolrooms/modules_arch.py, ServerScriptService/Level 2 Systems/Level 2 Kit World Builder.ModuleScript.lua

**refs:** ServerScriptService/Level 2 Systems/Level 2 Kit World Builder.ModuleScript.lua:539-549; tools/level2_poolrooms/modules_arch.py:311-317 (Walkway_End radius 5)

## F4-K - Walkway_Bend16 is a lone open-ended curved deck fragment in the pool (VaultArcade, CurvedChannel), z-fighting the straight walkway where they cross

**rootCause:** The bend is dropped at a reservePocket(24x24) spot, or 20 studs from a pier/curve wall, with nothing joined to either end and no end caps. path_deck's ends are flat cuts. The bend top (.45) and the straight deck Part top (.445) are 0.005 apart, so where edge-first packing puts the bend across the wall walkway the two surfaces z-fight.

**occurrences:** 12 seeds: 104 Walkway_Bend16 placements floating 0.5-1.45 above the basin. 95 cross a straight walkway deck by 8.8-9.4 studs (CurvedChannel 64, VaultArcade 31).

**fixDesign:** Make the bend part of the walkway, as RECIPES says ('curved pool edge across the hall'): run the wall walkway into the corner and replace its last 16 with Walkway_Bend16 turning off the wall, ending in a Walkway_End cap. If kept freestanding, cap both ends with Walkway_End (yaw from the path tangent), skirt it to -4 (F4-B), and reserve it so it never overlaps a straight deck. Raise the overlap offset from 0.005 to 0.05 wherever two decks are meant to overlap.

**check:** Walkway continuity: every end of every walkway piece (straight ends at ±L/2, bend ends at path endpoints) is within 0.7 of another piece's end, a Walkway_End, or a wall face. No two deck top surfaces closer than 0.04 while overlapping more than 1 stud² (extend check_coplanar.py to mesh deck tops via the manifest).

**risks:** Joining bends to walls needs the corner cove interplay settled by the F2 owner. Coordinate so the walkway also continues into corners.

**files:** ServerScriptService/Level 2 Systems/Level 2 Kit World Builder.ModuleScript.lua, tools/level2_poolrooms/modules_arch.py

**refs:** ServerScriptService/Level 2 Systems/Level 2 Kit World Builder.ModuleScript.lua:601-608,699-705; tools/level2_poolrooms/modules_arch.py:276-293 (path_deck), 304-306 (straight deck .445, '5-millistud lower top')

## F4-L - Arrival: the story-gate ArrivalDoor is buried inside the wall in every seed; the SunSlit is cut through the same wall above it in 5/12 seeds

**rootCause:** makeArrival sets back = centre - direction*(W/2-0.8), i.e. 0.8 studs inside the layout boundary. The hall walls built by wallShell are 1.75 thick (boundary..boundary+1.75). The door's chunks span local z -0.85..+0.15, which puts the whole door (iron leaf, tile frame, lamp, 'Arrival Wall Left/Right/Upper' Parts) 0.1-1.0 studs behind the wall's inner face, invisible. This is a port error: the Blender assembler used 2-stud walls centred on the boundary and put the door at boundary+2. wallShell picks the sun wall by hall proportions only (North if W>=D, else West) and puts the slit at the wall centre. When the arrival's connection points the other way, that is the door wall at the door's along-position: the slit hole is cut above the door and the slit frame (protruding 1.95) overlaps the door zone, directly over the spawn.

**occurrences:** All 12 seeds: 48 of 48 ArrivalDoor MeshParts are behind the wall face (seed 837834: wall face x=-658.25, door max x=-658.34). SunSlit over the door in seeds 101, 20261003, 82204455, 837834, 97690318. This is the first room every player sees.

**fixDesign:** makeArrival: back = centre - direction*(W/2 - 1.75 - 0.85 - 0.02), i.e. W/2-2.62, so the door's back face sits on the wall face and the frame (z +0.15) tucks 0.15 into the wall. Move the spawn and apron with it; they derive from back, so verify the 32x30 apron still fits. wallShell: for Arrival, choose a sun wall that is not the ArrivalDoor wall (pass the arrival direction in), or skip slit positions within 24 studs of the door's along-coordinate.

**check:** check_misc.py sections 6 and 9: every ArrivalDoor MeshPart AABB lies between the wall inner face and face+1.0 (48 failures today), and no SunSlit pivot is within 14 studs of the ArrivalDoor pivot (5 today). Generalise to every wall-mounted component (ArrivalDoor, SunSlit, WallVoid): visible chunk depth in front of the wall face within [0,1.0].

**risks:** The elevator compatibility markers and ArrivalSpawn derive from 'back'; the Round Adapter/GameManager spawn tests must still pass. The spawn moves 1.82 studs into the room.

**files:** ServerScriptService/Level 2 Systems/Level 2 Kit World Builder.ModuleScript.lua

**refs:** ServerScriptService/Level 2 Systems/Level 2 Kit World Builder.ModuleScript.lua:1169-1175 (back offset .8); ServerScriptService/Level 2 Systems/Level 2 Kit World Builder.ModuleScript.lua:288-316 (wall 1.75 thick; sunWall/slit at wall centre); ServerScriptService/Level 2 Systems/Level 2 Kit World Builder.ModuleScript.lua:259-266 (wallPose inset+1, used for SunSlit/WallVoid); tools/level2_poolrooms/assemble_level.py:303 (approved: ArrivalDoor at z0+2 with 2-wide walls)

## F4-M - Coplanar overlapping visible faces (z-fighting) at doors, the arrival apron, walkway bends and step noses

**rootCause:** Several visible surfaces are generated at the same height. The corridor mouth threshold (top FloorY) extends 4 studs into the hall, over the PaddlingRoom 12x12 threshold slab (top FloorY) and over dry hall floors (PumpHall/Arrival floor top FloorY). The Arrival Clear Apron is a visible 32x30 tile Part at FloorY+0.02 over the floor at FloorY. Walkway_Bend16's top (.45) is 0.005 above the straight deck (.445). PoolSteps nosing prisms have their top face exactly on the Step Ground Part tops.

**occurrences:** G:/Roblox/_local/l2fix/F4general/check_coplanar.py (visible axis-aligned Parts, faces inside hall interiors, offsets <=0.06, overlap >=1 stud²), 12 seeds: PaddlingRoom threshold/slab 178; PumpHall floor/threshold 50 (up to 136 stud² each); Arrival floor/threshold 21; Arrival apron 12 (960 stud²). Mesh/Part pairs (bend/deck 95, step noses about 3 per straight steps) are not scanned by the script.

**fixDesign:** Arrival apron: set Transparency=1 (it is navigation ground only; the floor Part is already Level2_EntityGround) or remove it. PaddlingRoom slab: removed by F4-D. Dry halls: in the hall interior set the corridor threshold's visible surface Transparency=1 and keep it collidable, or trim the hall floor Part to stop 4 studs short of each mouth. Bend vs deck: never overlap (F4-F/K), or offset at least 0.05. Step nose: lower the prism top by 0.03 or drop the prism's top face.

**check:** check_coplanar.py restricted to hall interiors (as run in this analysis), extended to MeshPart planar tops using manifest chunk bounds. Assert 0 pairs of visible faces with the same normal, |Δ| <= 0.05 and overlap >= 1 stud².

**risks:** Low. Visibility of these z-fights depends on whether the two tile textures line up and on distance, so severity in Studio is PLAUSIBLE, not confirmed; it is cheap to remove anyway.

**files:** ServerScriptService/Level 2 Systems/Level 2 Kit World Builder.ModuleScript.lua, tools/level2_poolrooms/modules_arch.py

**refs:** ServerScriptService/Level 2 Systems/Level 2 Kit World Builder.ModuleScript.lua:465-467 (paddling slab); ServerScriptService/Level 2 Systems/Level 2 Kit World Builder.ModuleScript.lua:242-243 (dry floor); ServerScriptService/Level 2 Systems/Level 2 Kit World Builder.ModuleScript.lua:1173 (apron +0.02); tools/level2_poolrooms/modules_tunnel.py:170-176 (threshold); tools/level2_poolrooms/modules_arch.py:304-306,326-330 (deck .445; step nosing)

### Other problems seen
- F10 owner: wallPose adds +1 to every inset (World Builder :259-266), so WallVoid and SunSlit (inset 1.2 -> 2.2 from the boundary) have 3-deep frames spanning 0.7..3.7. They protrude 1.95 from the 1.75 wall face, and WallVoid's dark 'Void' plane (local z 1.6..1.7) lands 0.55 from the boundary, inside the wall slab. That is exactly image 8: a frame with wall tile showing inside it. The BigPool 'outflow' WallVoids (:562-572) are placed at FloorY: half-submerged, their bottoms float 1.6-2.0 above the basin.
- F5 owner: makeSmall fills chamber water at local (0,-0.75,+2) with size (w-16, 1.7, d-12) (kit attr waterRegion, modules_tunnel.py:491). The +2 offset leaves 2.25 studs of dry aqua floor at the far wall of every chamber (about 20 per map), before the 4-stud terrain snapping is even applied.
- F11/F13 owner: ExitHall is a pool (PoolType 'Slide' is not 'Dry' in basinDepth), so ExitPlatform and ExitSpiral, placed at FloorY (:924-926), float 1.3-1.6 above the exit hall basin in all 12 seeds.
- F12 owner: cornerCoves (:366-372) destroys the kit's 'Corner Block' colliders and puts back only a 5x5 invisible seal in the corner. The R8/R16/R24 curved fill is non-colliding mesh, so players walk into the curved corner until they hit the 5x5 seal.
- F2 owner: the wall walkway runs from 1.5 to 1.5 short of the end walls (:439), straight through the corner-cove solid. For R24 the deck is inside the curved fill over 3.9-15.5 studs of its length, so the walkway sinks into the corner instead of continuing round it.
- F7/F8 owner: LightWell_R6 also comes from the edge-first reservePocket(36x36) (:755); 109 of 282 wells sit exactly 24 studs from a wall, so they cluster near the walls too.
- Pipes: every narrow-pipe mouth threshold is at FloorY+1.0 by design (modules_tunnel.py:172 sill=1): a 1-stud lip at about 750 mouths per 12 seeds (557 in chambers). Handled in F4-C, but the KIT_SPEC/RECIPES text does not mention it.
- LightRound fixtures hang 0.05 below the ceiling tile (pivot CeilingClass-0.6, mesh height 0.55; :551). Fold into F4-A.
- dump_world.py exports only BaseParts (BASEPART_CLASSES), so lights cannot be audited from the existing world dumps. Extend it with Light classes before writing the lighting test.
- Unused exported kit pieces that the RECIPES/approved look call for: Porthole_R6/R10/R15 ('porthole arch wall panels'), CurveWall_Q32/S64, LightWell_R10, Walkway_Straight16/Bend32, CoveTop/Base16/32, Column_D6_H42/H52, SpiralStairWell_H34. The builder never places them; portholes especially are part of the approved look and absent in Roblox.

### Notes
Method: read-only. I looked at all 14 owner shots, the approved renders (_sheet, 02, 03) and the Studio QA shots, then read the builder's dressing code end to end and the kit modules (modules_arch.py, modules_tunnel.py chamber/threshold, manifest.json chunk bounds, markers and parts). To measure the real builder output beyond the 3 existing dumps, I dumped 12 seeds (837834, 1, 101, 1182081016, 738163940, 484836893, 20261003, 35746866, 51232729, 66718592, 82204455, 97690318) with the unmodified harness. The scratch copy G:/Roblox/_local/l2fix/F4general/dump_many.py reuses tools/level2_poolrooms/dump_world.py with the output redirected, python -B, so nothing was written in the repo. Outputs are in G:/Roblox/_local/l2fix/F4general/worlds/. Check scripts, all runnable with `python -B <script>` from that folder: geo.py (shared OBB and floor-plane helpers), check_float.py (F4-B), check_approach.py (F4-C ground profile at each door), check_coplanar.py (F4-M), check_misc.py (F4-A coverage, F4-E stretch, F4-H tops, F4-B/F drains, F4-D curved steps, F4-L arrival door and slit, F4-I vault supports, F4-F deck intersections). Each prints the current violation counts quoted above; a fixed builder should print 0. No Blender run was needed; every finding is a numeric property of the dumped geometry. Uncertainties: (1) F4-E assumes MeshPart MaterialVariant tiling follows the baked UVs when a MeshPart is resized. Owner image 3 (cove tiles wider than wall tiles) supports this; a 1-minute Studio side-by-side settles it. (2) The F4-A lighting numbers in the fix need Studio tuning; offline coverage only proves light reaches the floor. The 80-light cap is an owner budget. (3) How visible the F4-M z-fights are depends on texture alignment (PLAUSIBLE). (4) The approach-profile count is about 500 of about 1,100 door sides; PumpHall rows in the raw output are inflated by a filter artefact, and PumpHall's real issue is buried steps and a curb on a dry floor. Ordering by visible impact: F4-A lighting, F4-B floating bases, F4-C door approaches, F4-E tile stretch, F4-L invisible arrival door, F4-F packing into walkways, F4-G repetition, then F4-D/H/I/J/K/M.

## F1 (image 1, image 5 'curbs') - Every straight hall cove (CoveBase*/CoveTop*) is a convex bullnose, and the builder also turns it 180° so its back faces the room

**rootCause:** There are two bugs and both have to be fixed. (1) KIT: cove() authors a quarter-ROUND, not a cove. The base arc is (z,y)=(3-3cos a, 3 sin a). Its centre is (z=3,y=0) and the solid is the quarter disc INSIDE that circle. A concave cove needs the arc centre at (z=0,y=3) with the solid outside the circle. CoveTop is the same shape point-reflected. Because the solid is the inside of the circle, no rigid placement can make it concave. (2) BUILDER: coveRun multiplies wallPose by CFrame.Angles(0,math.pi,0). wallPose already points local +Z at the wall (the same convention WallVoid and SunSlit use), so the extra turn puts the kit's wall side (back plane z=3.3, 3-7 studs tall) 3.3 studs into the room. Measured in the world dump (hall 1, west wall): the arc runs from the wall foot (-658.25,-4) to (-655.25,-1), its centre is 3 studs into the room at floor level, and a vertical back face stands at -654.95 facing the room. That is exactly image 1: a vertical face toward the walkway with the round side falling to the wall. Seen from the front on a walkway, the same piece is the 'curb' left and right of the collar in image 5. CoveTop64 is the mirror case: a 5-stud fascia hanging 3.3 studs off the wall below the ceiling.

**occurrences:** Every straight hall cove in every non-Small hall Type (Arrival, PumpHall, ColumnHall, BigPool, VaultArcade, CurvedChannel, SpiralWell, CorridorHall, PaddlingRoom, ExitHall), one base and one top run per wall run between openings. cove_check.py on the dumps: seed 837834 has 218/219 CoveBase64 and 218/219 CoveTop64 classified 'CONVEX bullnose, wall side facing room' (the 1 'other' is a run too short for the filter). Seed 1: 231/231 each. Seed 101: 220/221 each. That is 1,340 visibly wrong pieces over 3 seeds. CoveBase16/32 and CoveTop16/32 carry the same convex profile but the builder does not place them (the assembler does). Chamber coves use a different function (straight_cove), are concave and are covered in the chamber issue.

**fixDesign:** KIT (modules_arch.cove): re-author with the wall plane at local z=0, the wall on +Z (WallSide '+Z' as declared) and the room on -Z. Base: arc (z,y)=(-3+3sin a, 3-3cos a) for a=0..pi/2, from the floor tangent (-3,0) to the wall tangent (0,3), centre (-3,3). Back polygon (y=3,z=.3),(y=-4,z=.3),(y=-4,z=-3). Top (pivot 3 below the ceiling): arc (z,y)=(-3+3cos a, 3 sin a), from the wall tangent (0,0) to the ceiling tangent (-3,3), centre (-3,0). Back (y=3,z=.3),(y=5,z=.3),(y=5,z=-3). Keep the length+1 extrusion and update cove_uv for the new z range. BUILDER coveRun: drop `*CFrame.Angles(0,math.pi,0)` and pose at the wall face: `wallPose(hall,side,(a+b)/2,.75)*CFrame.new(0, top and hall.CeilingClass-3 or baseY, 0)`, where baseY = .445 (deck top) in halls that have a deck and 0 in dry halls (see the walkway issue). Apply the same correction to assemble_level.py so the review renders match. Re-export with build.py and re-run import_kit.py --profile poolrooms.

**check:** (a) Kit test, numpy only, no Blender (new tools/tests/test_level2_poolrooms_coves.py): decode the CoveBase*/CoveTop* chunks from assets/level2/poolrooms-kit/export. For every triangle that is not an end cap (|n.x|<.3) and lies in 0<-z<3, 0<y<3, assert |hypot(z+3, y-3)-3|<.01 for base (hypot(z+3,y) for top), and that the normal points toward that centre. Today's kit fails. (b) World test, added to test_level2_kit_world_builder.py, which already runs the real builder in the fake engine and loads the A/B/C manifests: transform each cove MeshPart's chunk triangles by its snapshot CFrame and Size. For arc faces compute dw (distance from the inner wall plane into the room) and dh (height above the base plane, or below the ceiling bottom for top coves). Assert hypot(3-dw,3-dh)=3±.05 and normal·(centre-P)>0. Run with --seeds 200. G:/Roblox/_local/l2fix/f1f2/cove_check.py is a working prototype of (b) over the three world dumps; it flags all 1,340 pieces today, and positive_control.py shows the corrected profile classifies as concave.

**risks:** New chunk hashes mean manifest/ManifestSha256 change and the kit must be reinstalled before the builder change goes to Studio (old builder + new kit, or the reverse, puts coves inside the wall). test_level2_kit_world_builder.py:639-645 asserts coves never project outside the wall shell. That still holds, because the back is only 0.3 into the 1.75 wall. Coincident overlaps with the corner tori can z-fight (see the corner issue).

**files:** tools/level2_poolrooms/modules_arch.py, ServerScriptService/Level 2 Systems/Level 2 Kit World Builder.ModuleScript.lua, tools/level2_poolrooms/assemble_level.py, assets/level2/poolrooms-kit/export (re-export), tools/tests/test_level2_kit_world_builder.py

**refs:** tools/level2_poolrooms/modules_arch.py:122-141 cove(); profile at 127-133: z=3-3cos(a), y=3sin(a) (base) / y=3-3sin(a) (top); back (3,3.3),(-4,3.3),(-4,0); ServerScriptService/Level 2 Systems/Level 2 Kit World Builder.ModuleScript.lua:268-286 coveRun; 273-274 `*CFrame.Angles(0,math.pi,0)`; ServerScriptService/Level 2 Systems/Level 2 Kit World Builder.ModuleScript.lua:259-266 wallPose (+Z already faces the wall); tools/level2_poolrooms/assemble_level.py:165-175 (the Blender review assembler places the same convex cove with its wall side to the room: yaw N=0 puts kit +Z = Blender -Y = room); tools/tests/test_level2_kit_world_builder.py:639-669 (checks bounding boxes only, so it cannot see orientation); scratch proof: G:/Roblox/_local/l2fix/f1f2/cove_check.py

## F1+F2 (vertical corners, images 1/3 background, 4) - All hall corner pieces (CornerCove, CoveBaseCorner, CoveTopCorner) are point-reflected through the hall corner, giving convex, collision-less rings

**rootCause:** The kit authors CornerCove_R*_H* with the pivot at the FILLET CENTRE: the inner surface is at r=R in the (-X,-Z) quadrant, the walls are at x=-R and z=-R (markers TangentX/TangentZ), and the comment says 'Interior positive X and positive Z'. cornerCoves places the pivot at the BOUNDARY CORNER (MinX/MaxX, MinZ/MaxZ) with yaw {pi, pi/2, -pi/2, 0}, which is the correct yaw + pi. The result is a quarter ring of radii R..R+3 around the corner point that bulges into the room (convex, room face at r=11/19/27 from the corner point). It meets the wall faces almost at right angles, which is the hard vertical crease you can see. The Blender assembler places these pieces correctly (pos = corner - s*cr, assemble_level.py:194-199), so this is a porting error in the Luau builder. The tori have a second kit bug: cove_corner() uses the same convex profile as cove() and puts the wall at r=R+3 instead of R (floor tangent r=R, top at R+3), so they would sit 3 studs inside the vertical cove even when posed correctly. Collision: the builder deletes the kit's 'Corner Block' arc colliders (which sit 1.1 behind the correct fillet surface) and adds one invisible 5x5 'Level 2 Corner Seal' from the boundary. Players walk through the visible ring into the pocket, and the seal sits in door apertures near corners.

**occurrences:** Four corners in every non-Small hall, all Types. CornerCove: seed 837834 116/116 convex (R8:8, R16:48, R24:60). Seed 1: 120/120. Seed 101: 120/120. CoveBaseCorner and CoveTopCorner: 116+116, 120+120 and 120+120 pieces, all 'NOT a concave fillet'. Corner Seal: 116/120/120. Example of the seal in a door: seed 837834 hall 12 (ColumnHall), narrow corridor 51 on the West wall at cross z=-84 (aperture -90..-78). The seal at (-489.5,·,-78.5), 5x5, covers z -81..-76, i.e. 3 of the pipe mouth's 12 studs, invisibly.

**fixDesign:** BUILDER cornerCoves: with R_c the per-corner radius (next issue), pose at the fillet centre: corners {MinX,MinZ,sx=1,sz=1,yaw 0}, {MaxX,MinZ,-1,1,-pi/2}, {MinX,MaxZ,1,-1,pi/2}, {MaxX,MaxZ,-1,-1,pi}; cf = CFrame.new(cx+sx*(1.75+R_c), FloorY, cz+sz*(1.75+R_c))*CFrame.Angles(0,yaw,0). positive_control.py shows this pose makes the current CornerCove_R8_H42 mesh concave and tangent to both wall faces (within 0.004) in all four corners. Stop deleting 'Corner Block' (lines 366-368); those blocks span R+.25..R+1.95 behind the surface. Delete the 5x5 Corner Seal (lines 369-373) and update the test that counts seals. Keep the vertical rescale for CeilingClass>52. Tori: CoveTopCorner_R at cf*CFrame.new(0,C-3,0); CoveBaseCorner_R at cf*CFrame.new(0,baseY,0) with baseY=.445 in deck halls, 0 otherwise. KIT cove_corner: wall at r=R to match CornerCove. Base arc (r,y)=(R-3+3sin a, 3-3cos a), centre (R-3,3), back at r=R+.3 from y=-4..3 and bottom y=-4. Top arc (r,y)=(R-3+3cos a, 3sin a), centre (R-3,0), back r=R+.3 up to y=5. Use over=asin(.05/R) on the cove tori instead of asin(.6/R), so the run/torus joint is a butt joint; identical surfaces overlapping by 0.5-1.1 studs would z-fight.

**check:** World test (in test_level2_kit_world_builder.py, real builder, --seeds 200), for each hall corner with R_c>0: C = boundary corner + (1.75+R_c)(sx,sz). The vertical CornerCove faces with |P-C|=R_c±.05 whose normal points toward C must cover ≥85° about C, and min distance to each wall-face plane must be ≤.05 (tangent). Torus arc faces must satisfy hypot(3-(R_c-|P-C|), 3-dh)=3±.05. Collision: a capsule/ray probe at mid-height from C toward the corner along the diagonal must hit a CanCollide part within R_c+0.3 of C. No invisible CanCollide part may intersect any door aperture box (cross±half, floor..top, 0..4 studs in from the boundary). cove_check.py already implements the orientation part on the dumps: it fails 356/356 corners today and passes for the corrected pose (positive_control.py, 4/4).

**risks:** Once the pose is right, a full-height fillet COVERS any door whose edge is closer than 1.75+R to the corner. This fix must ship together with the per-corner radius rule (next issue), or pipes and tunnels near corners disappear behind tiles. Reservation pockets (reservePocket margin 6) can reach behind an R24 fillet: the pocket corner at (6,6) from the boundary is 27.9 from C. clearPocket should treat each corner circle as a boundary. Navigation and capsule tests may change slightly because the walkable corner area shrinks to the fillet.

**files:** ServerScriptService/Level 2 Systems/Level 2 Kit World Builder.ModuleScript.lua, tools/level2_poolrooms/modules_arch.py, tools/level2_poolrooms/assemble_level.py, tools/tests/test_level2_kit_world_builder.py

**refs:** ServerScriptService/Level 2 Systems/Level 2 Kit World Builder.ModuleScript.lua:344-379 cornerCoves; 350-354 corner list and cf; 366-368 destroys 'Corner Block'; 369-373 5x5 Corner Seal at cf*(-2.5,·,-2.5); 376-377 CoveTopCorner/CoveBaseCorner at the same wrong cf; tools/level2_poolrooms/modules_arch.py:107-119 corner_cove (correct convention, keep); tools/level2_poolrooms/modules_arch.py:144-171 cove_corner; profile 151-156 r=radius+3-3cos(a), y=3sin(a); tools/level2_poolrooms/assemble_level.py:184-202 (reference: correct pivot, plus a near-door radius rule); tools/tests/test_level2_kit_world_builder.py:706-728, 870-891 (bounding-box overlap and seal count only); scratch: G:/Roblox/_local/l2fix/f1f2/cove_check.py (torus_report), positive_control.py

## F2 (doors at corners) - Door apertures can sit inside the corner fillet zone; the builder needs a per-corner radius with a square-corner fallback

**rootCause:** The layout generator only keeps door centres 8 (narrow) or 21 (tunnel) studs from the wall-span ends, so door edges can be 2 or 4 studs from the boundary. The corner fillet's tangent points are 1.75+R from the boundary (9.75/17.75/25.75). cornerCoves always uses one hall-wide radius (8/16/24 by size/Type). The Blender assembler had a near-door rule (cr=8 if a door is within radius+width/2+2); the Luau port dropped it.

**occurrences:** doorcorner.py: 39 of 309 hall door-sides across seeds 837834/1/101 have an edge inside the fillet zone (edges 2, 6, 7, 10, 11, 14, 15, 18, 19, 23 studs from the boundary). Types: ColumnHall, BigPool, CurvedChannel, SpiralWell, VaultArcade, PaddlingRoom, ExitHall (pressure door). Kinds: Open, Narrow and PressureDoor. corner_radius.py, a door-safe radius per corner over 356 corners: R24 kept 137-142, R24->16 5-9, R24->8 8-9, R24->0 5. R16 kept 127-129, R16->8 9, R16->0 10-12. R8 kept 47, R8->0 1.

**fixDesign:** BUILDER: add `cornerRadius(hall, corner, doors)`. Start from the hall rule R (lines 345-347). Let e = the smallest door-edge distance from that corner on its two walls (|Cross-cornerCoord|-Width/2). Pick the largest r in {24,16,8} with r<=R and e >= 1.75+r+0.5+3 (the 3 is the base-cove stop length from the coves issue). If none fits, use r=0: no CornerCove and no tori; straight coves and decks run to the boundary (as today) and overlap. Two concave cove solids crossing at 90° form a correct mitred inside corner, and the wall slabs already overlap there. Use the same R_c in coveRun, the decks and the corner deck pieces. OPTIONAL (keeps more round corners, needs a layout-test rerun): raise the generator margin to keep e>=13.25 (narrow 6+13.25 -> 20, tunnel 17+13.25 -> 32 on the 4-grid). Then R8 always fits. Ship the builder fallback first; it is required for correctness either way.

**check:** World test, --seeds 200: for every hall corner and every door on its two walls, assert door-edge distance >= 1.75+R_c+0.5(+3 with stops) when R_c>0. Also assert that no visible or collidable part other than the collar, threshold, deck and steps intersects the aperture prism (cross±half along the wall, floor-2..top, boundary..boundary+4 inward). The current test (870-891) hard-codes the hall radius and must read the per-corner value from an attribute the builder writes, e.g. Level2_CornerRadius on each corner piece.

**risks:** R=0 corners look different (sharp vertical corner with mitred coves). That is acceptable and finished, but it is a visible variation, so tell the owner. The optional generator change reshuffles layouts for pinned seeds (837834 etc.), so test_level2_kit_layout / navigation must be rerun on ≥200 seeds to confirm generation success does not drop.

**files:** ServerScriptService/Level 2 Systems/Level 2 Kit World Builder.ModuleScript.lua, (optional) ServerScriptService/Level 2 Systems/Level 2 Kit Layout Generator.ModuleScript.lua, tools/level2_poolrooms/assemble_level.py, tools/tests/test_level2_kit_world_builder.py (radius expectation at 870-873)

**refs:** ServerScriptService/Level 2 Systems/Level 2 Kit Layout Generator.ModuleScript.lua:156 `local margin = narrow and 8 or 21`; 108-114 socket(); ServerScriptService/Level 2 Systems/Level 2 Kit World Builder.ModuleScript.lua:345-347 single radius per hall; tools/level2_poolrooms/assemble_level.py:192-196 near_door rule; scratch: G:/Roblox/_local/l2fix/f1f2/doorcorner.py, corner_radius.py

## F2+F4 (cove runs, doors, collars) - Cove runs ignore corner tangents, the top cove is cut at every opening, base coves end in raw cut ends at collars, and cove UVs are stretched up to 3.5x

**rootCause:** wallShell calls coveRun(top) AND coveRun(base) for every hole: tunnel and pipe doors, the exit gap and sun slits. But only door holes reach the base band (hole bottom -2), and no hole reaches the top band (tunnel collar top 32 < C-2; the cove at y=C-2 is only 0.17 off the wall, in front of the solid collar panel; sun slit top = C-3; exit gap top FloorY+92.55 < 93). coveRun clamps runs to boundary ±0.5. The comment says 'half a stud into the adjoining corner cove', but the real corner tangent is 1.75+R from the boundary. At openings the run just stops 0.5 inside the hole and shows its prism end cap. Each run is one 64-long mesh scaled by (b-a+1)/64, so the tile texture stretches along the run (it is not world-space like Parts).

**occurrences:** Every hall wall run. Top coves are split at every corridor door: 219/231/221 top runs in the three seeds, the same count as base runs. Arrival and CorridorHall sun walls are split per slit (seed 837834 hall 1 West wall: two runs meeting at z=-364 with a 0.14 gap). UV stretch of CoveBase64: median about 1.0, max 3.5x, >1.5x on 44/219, 38/231 and 47/221 runs, and as low as 0.04x (squashed). The BigPool foot-level WallVoid (4 per BigPool, frame y 0..8) is crossed by the base cove band 0..3.

**fixDesign:** BUILDER: (1) Top cove: one run per wall from tangent to tangent, [Min+1.75+R_c0, Max-1.75-R_c1], or to the boundary when R_c=0. Never split it at holes. (2) Base cove: split only at holes whose vertical span intersects [baseY, baseY+3] (corridor doors) and at foot-level wall features (the BigPool WallVoid, or raise that WallVoid's y to baseY+3.5). Split them into runs [prevEnd, holeLow-3] and [holeHigh+3, next], and place a new kit piece CoveBaseStop (3 long; the cove profile revolved 90° about the vertical line at the wall face, so it blends into the wall) mirrored so it ends exactly at the hole edge. A run shorter than 6.1 between two features gets no cove. Joints between runs, stops and tori are butt joints (0.05 overlap), never 0.5 overlaps of identical surfaces. (3) UV: instead of stretching one 64 mesh, place n=max(1,round(L/16)) 16-stud units, grouped greedily into 64/32/16 pieces, each scaled by L/(16n). Stretch stays within [0.75,1.33]. KIT: add CoveBaseStop (modules_arch: revolve the corrected base profile around x=0, z=0 over 0..90°, 8 segments, the same chunk material). Apply the same splitting rules in assemble_level.py.

**check:** World test, --seeds 200, continuity probe. Per hall, build the foot path 1.0 stud in front of the wall surface: straight along the walls, then a quarter arc of radius R_c-1 around each C, sampled every 1 stud. At each sample cast a ray down from baseY+2.5 (vectorised Möller-Trumbore over the transformed cove chunks). It must hit a cove-family triangle at baseY+0.764±0.1, i.e. the concave cove height at dw=1. The only allowed misses are samples inside a door aperture span. Samples within 3 studs of an aperture edge must hit a CoveBaseStop. Repeat for the top cove (ray up from C-2.5, expected C-0.764, no misses at all). End-cap check: every cove run's along-axis end must lie within 0.06 of a torus tangent, a stop or another run. UV check: size.X/chunk.size.X ∈ [0.74,1.34] for every straight cove.

**risks:** Instance count rises (+2 stops per door side, more 16/32/64 segments) against the ≤8,500 world-descendant budget (measured 7,586-8,164). Not splitting top coves and deleting the Walkway_End/Bend pieces (walkway issue) win some back; check the budget assertion at test_level2_kit_world_builder.py about line 1657. CoveBaseStop is a new component, so manifest consumers (import_kit audit, test_level2_kit_import) need it registered.

**files:** ServerScriptService/Level 2 Systems/Level 2 Kit World Builder.ModuleScript.lua, tools/level2_poolrooms/modules_arch.py, tools/level2_poolrooms/assemble_level.py, tools/tests/test_level2_kit_world_builder.py

**refs:** ServerScriptService/Level 2 Systems/Level 2 Kit World Builder.ModuleScript.lua:268-276 coveRun clamp/scale; 288-342 wallShell; 304-316 sun-slit holes; 326-341 split of both coves at every hole; ServerScriptService/Level 2 Systems/Level 2 Kit World Builder.ModuleScript.lua:571, 764-765 WallVoid at the wall foot (BigPool) and at 0.6C; tools/level2_poolrooms/modules_tunnel.py:97-188 collar (panel ±17 x -2..32 tunnel, ±6 x -2..12 pipe)

## F2+F4 (walkways / decks / curbs in big halls) - Decks run along only two walls, float over the basin, never turn corners, and stray deck fragments (Bend16, inverted Walkway_End pair) sit in the pool

**rootCause:** placeWalkways puts one stretched Walkway_Straight32 on each LONG wall only. The deck is an 0.8 slab (top .445, bottom -.355) over a basin floor at -0.8..-3.5, so there is an open gap under the walkway. The end walls have no deck, so the wall foot there is at basin level while the long walls' foot is at deck level. A single base cove and corner torus cannot serve both heights, which is why corners cannot read finished. Dry PumpHalls also get raised decks, plus PoolSteps sunk below their flat floor. Walkway_Bend16 (VaultArcade, CurvedChannel) is dropped into a free 24x24 pocket with both closed ends 7-37 studs from any wall: an isolated deck fragment that 'ends short'. BigPool's 'round island' places two Walkway_End half-discs at island∓5. Their round sides point INTO the D10 column (radius 5) and their flat cut faces point outward, so all that shows is two flat-ended plinth stubs. Pipe-mouth thresholds (sill 1) protrude 2.25 studs into the hall at top +1.0, which is a 0.555 'curb' above the deck.

**occurrences:** Every basin hall (all Types except Arrival and the dry PumpHall), 2 long-wall decks each: 56 deck parts in seed 837834. PumpHall decks: 2 per pump hall (6 per seed). Walkway_Bend16: 8 / 5 / 8 per seed (837834 / 1 / 101), with ends 7.2-37.3 studs from the nearest wall. Walkway_End pairs: seed 837834 halls 15 and 24, seed 101 halls 16, 18 and 33, seed 1 none (BigPool only). Pipe thresholds: 64 passage mouth thresholds in seed 837834, in halls and chambers.

**fixDesign:** Ring deck ('pool surround') in every hall with basinDepth>0. Dry halls (Arrival, PumpHall) get no deck and no PoolSteps (`if basinDepth(hall)==0 then return end`), so their coves sit at 0. Deck: 10 wide, from 0.5 inside the wall face to 9.5 from the wall face (centre 6.25 from the boundary, as today), top FloorY+.445. Extend the 'Walkway Deck' Part down to FloorY-4.5 so the pool-side face is a solid basin wall. Four straights per hall: each spans between corner zones [Min+1.75+max(R_c,9.5), Max-1.75-max(R_c,9.5)]. Scale only the pool-side nosing to that span and delete the wall-side nosing (it is hidden). Corners: R_c>=16 gets a new kit piece Walkway_Corner_R16/R24, a quarter annulus in the CornerCove frame (same pose as the fixed CornerCove), radii R-9.5..R+0.5 (6.5..16.5 / 14.5..24.5), top .445, bottom -4.5, the straight's nosing along the inner arc, and arc_boxes ground colliders at mid-radius. R_c∈{0,8} gets a box Part [boundary+1.25, boundary+11.25]² (top .445, bottom -4.5, ground). With this rule, base coves and base tori sit at FloorY+.445 on all four walls, top coves at C-3, and every corner reads continuous. Steps: PoolSteps_Straight12 pivot at the deck's pool edge (boundary+11.25, y=FloorY+.445), giving step tops -0.155/-0.755/-1.355 rel FloorY. Add a second piece offset -12 z / -1.8 y where the local basin depth exceeds 1.9. PaddlingRoom PoolSteps_Curved pivot at boundary+1.25, so its rings start at the deck edge, and delete the Paddling Threshold Ground. Delete the floating Walkway_Bend16 placements (601-608, 699-705); curved decks belong to the F9 swervy-room redesign. Replace the BigPool island with a correct one: both Walkway_End pieces pivoted at the island centre (yaw 0 and pi) and scaled 2x horizontally (r=10 around the r=5 column), or delete it. Pipe threshold: make it flush (depth 1.75 within the wall, no protrusion), or 0.25 proud with a nosing, so the 1-stud rise reads as a door sill, not a block.

**check:** World test, --seeds 200, per basin hall. (1) Deck ring probe: a path 5 studs from the wall surface (radius R_c-5 around C at R_c>=16, square otherwise), sampled every 1 stud. A ray down from FloorY+2 must hit a CanCollide Level2_EntityGround Part or collider at FloorY+.445±.05 everywhere, including corners and in front of doors. (2) Skirt: at 9.6 from the wall face, a ray down from FloorY+.3 must hit nothing above the basin floor top, and a horizontal ray toward the wall at FloorY-.5 must hit the deck face, i.e. no gap under the deck. (3) No exposed ends: for every deck or Walkway-family piece, each short-side end-face centre must have another deck piece, a wall or a fillet within 0.6 along its axis. That fails today for every Bend16 end and every Walkway_End flat face. (4) Dry halls have no Walkway_* and no PoolSteps. (5) Every PoolSteps top surface lies between the deck top and the local basin floor top, and step 1 touches the deck edge (±.05). (6) No threshold top more than 0.6 above the adjacent deck or floor unless it is within the wall thickness.

**risks:** This is the biggest change in the cluster. It changes walkable area (navigation and Foam targeting tests), reservations (props at margin 6 now stand on the deck; columns already float at FloorY, see otherProblems) and the instance budget. The ExitHall's east-wall deck must be clipped against the ExitPlatform/ExitSpiral footprint and the exit lead-in; coordinate with the exit analyst. Water regions (F5 owner) must reach under the deck by at least one 4-stud voxel so the water meets the skirt. The test lines that require 'Walkway_Bend'/'Walkway_End' (892-905) and exactly one deck on each long wall (651-658) must be rewritten to the ring contract.

**files:** ServerScriptService/Level 2 Systems/Level 2 Kit World Builder.ModuleScript.lua, tools/level2_poolrooms/modules_arch.py (Walkway_Corner_R16/R24; deck part height), tools/level2_poolrooms/modules_tunnel.py (threshold depth), tools/level2_poolrooms/assemble_level.py, tools/tests/test_level2_kit_world_builder.py, tools/tests/test_level2_kit_navigation.py (deck/steps ground expectations)

**refs:** ServerScriptService/Level 2 Systems/Level 2 Kit World Builder.ModuleScript.lua:427-473 placeWalkways (deck 434-449 on two walls only; steps 450-472 at boundary-5 with tops -0.6/-1.2/-1.8 rel FloorY; paddling threshold 465-467); ServerScriptService/Level 2 Systems/Level 2 Kit World Builder.ModuleScript.lua:546-549 BigPool Walkway_End pair at island∓5; ServerScriptService/Level 2 Systems/Level 2 Kit World Builder.ModuleScript.lua:601-608 and 699-705 Walkway_Bend16 in a pocket; ServerScriptService/Level 2 Systems/Level 2 Kit World Builder.ModuleScript.lua:233-257 basinDepth/floorShell (basin floor top -0.8..-deep); tools/level2_poolrooms/modules_arch.py:296-318 walkway (Straight deck Part .8 thick at 302; End half-disc +X with the flat side at the pivot 313-317); tools/level2_poolrooms/modules_tunnel.py:170-176 collar threshold (2*halfwidth x (2+sill) x 4 at z±2; sill=1 for pipes); tools/tests/test_level2_kit_world_builder.py:651-658 (expects exactly one deck on each long wall), 892-905 required Walkway_End/Walkway_Bend

## F1+F2+F4 (chambers, images 3 and 4) - Escape chambers: the south-wall cove floats 1.2 above the floor, coves and ledges stop at every corner, and the cove runs across pipe sockets

**rootCause:** Chamber_A..D are one kit mesh each. straight_cove (concave, radius 1.2) is correct in shape and sits at y 0..1.2 on all four walls. But the only floors at y=0 are the N 'Dry Threshold' (w-16 x 8) and the E/W 'Side Step' ledges (5 wide, from w/2-7.5 to w/2-2.5, z±(d/2-8)). The S wall and all four corners have only the aqua floor at -1.2. So on S the cove is a lip hanging 1.2 above the floor with wall tile showing under it (image 3, right), and the side-step ledges end with box faces at the corner tangent (image 4 'deck ends short'; image 3 left). chamber_corner (concave, inner r 6.25, centre (±(w/2-8),±(d/2-8))) has no matching lower or upper torus, so both coves end in open sheet edges at the corner. straight_cove spans the whole wall (length L-15) regardless of sockets, so an opened pipe socket has the cove sheet across the bottom of its mouth, plus the pipe threshold block (top +1.0, 2.25 proud), which is the 'small rounded curb' in image 4.

**occurrences:** All four prefabs (Chamber_A 48x48, B 48x64, C 64x64, D 40x56). Floor top under the lower-cove floor tangent: N 0, E 0, W 0, S -1.2 (floating); every corner -1.2. Per seed, every Small hall: 21 chambers in seed 837834 (21 'Room Side Step' pairs). Each chamber has 1 floating S cove, 8 unfinished corner cove ends, 8 ledge ends at corners, and the cove across each opened socket.

**fixDesign:** KIT chamber(): a uniform perimeter ledge 6.25 wide from the wall face (equal to the corner inner radius), top 0, bottom -1.4. N: keep the threshold (z -d/2..-d/2+8, x±(w/2-8)). S: mirror it. E/W: widen to x∈[w/2-8, w/2], z±(d/2-8). Corners: 8x8 boxes at (±(w/2-4), ±(d/2-4)). The ledge's inner edges then pass through the fillet centres, the corner ledge is the quarter disc inside the fillet, and the lower cove rests on y=0 everywhere. Add chamber cove tori around each fillet centre (sx cos t, sz sin t, t=0..pi/2). Lower arc (r,y)=(5.05+1.2 sin a, 1.2-1.2cos a). Upper arc (r,y)=(5.05+1.2cos a, 13.8+1.2 sin a). Straight runs keep length L-15 but end at the tangent with a 0.05 overlap. Sockets: cut the lower straight_cove out of each socket span [offset-6, offset+6] and export two small components, ChamberSocketCove (the 12-long cove segment) and ChamberSocketStops (two radius-1.2 stop ends). makeSmall places the segment where the plug stays and the stops where it removes the plug (same matching as 813-824). The water region becomes the inner rectangle (w-16)x(d-16) centred on 0, not z+2 (coordinate with F5). Chamber_D nook: extend its ends to the N wall face and its foot to -1.2, or drop it.

**check:** Kit test (numpy over job B chunks and parts): for each Chamber_*, at 1.2 from each wall face along the whole straight run and around each corner arc at r=5.05, the highest ground-part top below must be 0±.05 (fails today on S and in all corners). The lower and upper coves must be continuous: rays down from y=1.0 at 0.3 from the wall surface along a path that wraps the fillets hit cove triangles everywhere except open socket spans. World test: for each placed chamber, every socket whose plug was removed has ChamberSocketStops and no cove triangles inside the aperture (|along-offset|<6, y<12), and every kept socket has ChamberSocketCove.

**risks:** New chamber components and socket logic in makeSmall; the corner seals (808-812) must not intrude into the new ledge corners in a way the navigation test would object to (they are invisible 8x15x8 boxes at the corners, behind the fillet, so they are fine). Water-region change belongs to F5; coordinate so the pool rectangle and the ledge faces meet.

**files:** tools/level2_poolrooms/modules_tunnel.py, ServerScriptService/Level 2 Systems/Level 2 Kit World Builder.ModuleScript.lua (makeSmall socket cove placement, water region), tools/tests/test_level2_kit_world_builder.py (chamber section near 1250), tools/tests/test_level2_kit_import.py

**refs:** tools/level2_poolrooms/modules_tunnel.py:394-494 chamber(); floors 403-404; side steps 452-454; coves 448-450; tools/level2_poolrooms/modules_tunnel.py:371-391 straight_cove (length = side-15, y 0..1.2 / h-1.2..h); tools/level2_poolrooms/modules_tunnel.py:327-352 chamber_corner (inner 6.25, outer 8); tools/level2_poolrooms/modules_tunnel.py:455-469 Chamber_D nook; ServerScriptService/Level 2 Systems/Level 2 Kit World Builder.ModuleScript.lua:798-826 makeSmall (corner seals 808-812, socket plug removal 813-824, water 801-803)

### Other problems seen
- Columns (Column_D6/D10/D16), VaultPier, CurveWall_Q/S partitions, SpiralStairWell and DrainHole are placed at FloorY, but basin floors are 0.8-3.5 below FloorY. Their bases float above the pool floor, with the gap visible through the water (World Builder 478, 483-490, 514, 629, 684, 713, 777). Owner: F4/F12 analysts.
- ArrivalDoor is placed 0.8 studs from the boundary (World Builder 1169-1175), inside the 1.75 wall slab with no wall hole. Its chunks (z -0.35..-0.84) sit behind the wall face, so it is likely invisible. Unverified visually; settle with a render of the Arrival hall.
- WallVoid frames ('Void Side'/'Void End' 3 deep at inset 1.2) are the plain white rectangles of F10. The BigPool 'outflow' WallVoids sit at the wall foot (World Builder 571) and collide with the base-cove band.
- PoolSteps_Straight12 nosing prism (modules_arch.py 330-331) is fully coincident with the Step Ground Part's front and top faces, so the two will z-fight and the nosing adds nothing.
- Walkway_Straight32 nosing meshes are stretched 5.4-7.4x along their length (one 33.2 mesh scaled to the wall length), and CornerCove is stretched vertically 1.85x in the ExitHall (H52 scaled to 96), giving visibly stretched tiles.
- The corner radius rule differs between the Blender assembler (24 if min(w,d)>200) and the Luau builder (24 if max(W,D)>200), so the review renders do not match the game.
- Blender assembler (assemble_level.py) places straight coves with the wall side to the room too, so the owner-approved renders already contained the convex/flipped coves.

### Notes
I found the wrong-way smooth edge, the corner faults and the walkway-end/curb faults in both the Blender kit and the Luau builder, confirmed them against the three world dumps, and designed the fixes below. Nothing is edited yet: this phase was read-only.

**Which piece is in image 1:** it is CoveBase64. The kit draws it as a convex quarter-round, and coveRun in the builder turns it 180°, so its 3.3-stud flat back faces the room. The same piece, seen from the front sitting on a walkway, is the "curb" on either side of the collar in image 5. CoveTop64 has the same fault at the ceiling.

**The corner fault is wider than images 3 and 4 suggest.** The vertical corner pieces (CornerCove) are placed point-reflected through the hall corner in every hall: 356 of 356 corners across the 3 dumped seeds are convex rings, and players can walk through them. The cove corner pieces under and above them are inside-out the same way. The Blender assembler places these corners correctly, so the error came in when the placement was ported to Luau. The builder also deletes the kit's corner colliders and puts in one invisible 5x5 box instead, which blocks 3 of 12 studs of a pipe mouth in seed 837834 hall 12.

**Images 3 and 4 are escape chambers, not halls.** The chamber coves have the right shape. What is wrong there:
- On the south wall the base cove floats 1.2 studs above the floor, because no ledge is there.
- The coves and ledges stop at every corner, with no corner pieces.
- The "curb" in image 4 is the pipe-mouth threshold block, 1 stud high and sticking 2.25 studs into the room.

**One coupling decides the order of work.** Once the corner pieces are placed correctly, any door closer to a corner than 1.75 + R studs gets hidden behind the curved corner. That is 39 of 309 door-sides in the three seeds. So the builder needs a radius chosen per corner, with a square-corner fallback, in the same change. That fallback hits about 5% of corners. Moving doors away from corners in the layout generator would keep more round corners, but it reshuffles the pinned seeds, so I listed it as optional.

**Why the decks need to go round the whole room.** Decks sit on only two walls, so the wall foot is at deck height on two walls and at pool-floor height on the other two. No single cove height can then go round a corner cleanly. My recommended fix puts a deck on all four walls with new corner deck pieces. It is the biggest change here: it moves walkable area, navigation, steps and the instance budget, and the exit hall's deck must be clipped against the exit platform. The floating curved deck pieces and the island end pieces in the pool would be removed or rebuilt.

**Uncertain and unverified:**
- I inferred the image-to-component matches from geometry and image details, not from renders.
- I measured the instance-budget growth only roughly.
- The arrival door looks buried inside the wall, but I have not seen it.

Before/after renders of seeds 837834, 1 and 101 with render_world.py, plus the proposed checks run over 200 seeds, would settle these.

**Checks:** I wrote prototypes over the existing dumps; the new tests would go into `tools/tests/test_level2_kit_world_builder.py`, which already runs the real builder over many seeds. `cove_check.py` flags all 1,340 straight coves, 356 corners and 712 cove corner pieces today, and `positive_control.py` shows the corrected corner placement passes 4 of 4 corners. The current test missed all of this because it only compares bounding boxes, which cannot see which way a piece faces.

Scratch scripts are in `G:/Roblox/_local/l2fix/f1f2/`:
- `cove_check.py`
- `positive_control.py`
- `doorcorner.py`
- `corner_radius.py`
- `chunks.py`

## F5 (F5a: every pool) - Every terrain water body is one partly filled 4-stud voxel row with nothing under it, so its edges render shrunken back from walls, ledges and steps

**rootCause:** Water is written with Terrain:FillBlock boxes that run from the basin floor to FloorY+0.1. Every FloorY and every hall or corridor bound sits on the 4-stud lattice (Layout Generator L485 heights = n*4, L893 room/leaf lattice, L905 floor class {-8,-4,0,4,8}, L973 Cross%4). So each box puts all of its water into the single voxel row [F-4,F] at a fraction o = depth/4, and adds a 0.025 sliver in row [F,F+4]. There is no full voxel under that row. Measured o values: halls 0.40-0.50, PaddlingRoom 0.20, chambers 0.40, wet tunnels 0.375, pipes 0.175. Terrain draws such thin rows shrunken at their free edges. The box edges also cut partway into the edge voxel, which lowers its fill further: hall edges sit at bound+1.25 (edge-voxel coverage 0.6875), tunnel channels at Cross+-6.8 (0.70), pipes at +-3.275 (0.82). The geometric gaps are small: hall boxes reach 0.5 into the 1.75 wall (inner face at bound+1.75), and tunnel boxes reach 0.1 past the channel-side inner face at 6.7. The visible dry bands therefore come from how terrain renders thin rows, not from short boxes. Two screenshots support this. Image 4 is a RoundTunnel_Wet channel (cream ledge, 1.5-stud channel-side face on Aqua floor, curb, bore behind) with a dry band of about 1.3 studs at o=0.375. Image 2 is a Pipe_Flat, whose 0.7-tall water (o=0.175, nominally 0.1 above the floor) does not render at all. UNCERTAIN: Roblox does not document how its terrain renders partly filled water. This conclusion is inferred from images 2 and 4; the Studio test listed under check settles it. The fix does not depend on the exact rule, because it removes partly filled rows entirely.

**occurrences:** Every hall with basin>0, all three seeds: 80 halls (ColumnHall 28, CurvedChannel 12, PaddlingRoom 15, VaultArcade 9, SpiralWell 8, BigPool 5, ExitHall 3). Also 75 RoundTunnel_Wet (incl. PressureDoor Wet) and 96 Pipe_Flat. In check_f5.py current mode, 100% of the visible submerged floor in every one of these spaces lacks a solid water column at the surface: 2,009,234 sq studs in halls, 70,538 in tunnels, 29,120 in pipes, plus 268,632 / 10,864 / 2,080 thin voxels respectively. PaddlingRoom (o=0.20) is as thin as the pipes that render no water at all, so kids rooms are probably mostly dry-looking (unverified). Dry by design and unaffected: Arrival, PumpHall, Dry/Stair4/Stair8 tunnels, Pipe_Stair4.

**fixDesign:** Put every water body exactly in ONE voxel row, flush with the 4-grid, filled to 0.975: box bottom = FloorY-4, box top = FloorY-0.1 (height 3.9), horizontal faces on voxel boundaries that lie inside solids. Add one helper in the Kit World Builder next to water() (L161): poolWater(ctx,x0,x1,z0,z1,floorY,label). It asserts x0,x1,z0,z1,floorY %4==0 and x1>x0, z1>z0, then calls water(ctx, Vector3.new((x0+x1)/2, floorY-2.05, (z0+z1)/2), Vector3.new(x1-x0, 3.9, z1-z0), label). (1) floorShell L255 -> poolWater(ctx, hall.MinX, hall.MaxX, hall.MinZ, hall.MaxZ, hall.FloorY, "Hall "..hall.Index): the whole footprint, so the edge lies at the wall's OUTER face, 1.75 behind the inner face. (2) makeCorridor L1041-1044 -> only when c.Kind~="Narrow" and c.Variant=="Wet": the axis span [c.From, c.To] x [c.Cross-8, c.Cross+8] at c.FromY. That puts the edge 1.0-1.3 behind the channel side (6.7-7.0), under/inside the ledge (top F); the cavity under the ledge is closed by side, ledge and bore, and the ends meet the hall water at the bound under the 4-deep mouth threshold. Drains keep working: the Air fill over an aligned box clears exactly the tunnel and leaves both halls full. Wading rules: the surface moves from F+0.1 to F-0.1, so depth is 0.7 at the shallow end and PaddlingRoom, up to 1.9 at the deepest basin (DeepEnd<=2.0), 1.4 in tunnels and 1.1 in chambers. All are inside 'deep end <=3.5, never swimming': a 3-stud root height stays above the surface everywhere. Every walkable top at F (tunnel/pipe mouth thresholds, Room Dry Threshold, Side Steps, Corridor Ledges, Paddling Threshold Ground, top pool step) stays dry, and the water meets its face 0.1 below the top. That removes today's 0.1 film over those tops (582 / 307 / 189 / 192 part-tops under water now in halls / tunnels / chambers / pipes). Leak safety: footprints are disjoint by layout validation ('corridor touches third room', lattice), and the box never leaves its own footprint or corridor strip. Walls go down to F-4.8..F-6, chamber walls to F-5.25, and door holes start at F-2 with the threshold filling F-2..F, so the extra water under floors, inside walls and outside the tunnel bore is enclosed and invisible. The vertical extent is one row, so FillBlock writes FEWER voxels than now (two rows today). Kit/spec sync: modules_tunnel.py L282-283 wet tunnel waterRegion -> center [0,-2.05,0], size [16,3.9,body], surfaceY -0.1. RECIPES.md L8-9 'surface at FloorY + 0.1' -> FloorY - 0.1, one voxel row over the whole footprint. Rebuild the manifest; the table-valued attr is not installed into Roblox, so this is the documentation and test contract. Optional, only if the Studio check shows rounding at the outer edges: add a full row below (bottom F-8); the offline check stays the same.

**check:** Offline, real builder output: port G:/Roblox/_local/l2fix/f5/check_f5.py into test_level2_kit_world_builder.py, which already records every FillBlock in `fills` (L276) and every object, over its 10 seeds. Run it against the world dumps too: `python check_f5.py current|proposed`. Per seed it asserts: (a) every Water fill's 4 side faces and its bottom are multiples of 4, its bottom equals its owner's FloorY-4 and its top FloorY-0.1 (+-1e-4); (b) the horizontal extent equals the owner hall or chamber footprint, or [From,To]x[Cross+-8] for Open/PressureDoor Wet, and there is no fill for Narrow, Dry, Stair, Arrival or PumpHall; (c) voxelise every fill (occupancy = product of 1-D overlaps): no voxel with 0<o<0.9 unless the voxel under it is >=0.9 (THIN=0); no voxel cell overlaps another space's footprint (LEAK=0); (d) sample every visible submerged floor point (top of Hall Water Floor / Room Aqua Floor / Corridor Water Floor < surface-0.05, not inside a visible Part, chamber points behind the r~5.7 curved corners excluded) on a 0.5 grid: its voxel column must be solid at the surface, and so must the probes 1 stud away in +-X/+-Z unless the probe lies inside a wall/step/threshold/seal Part (NOT_SOLID=0); (e) no Threshold/Side Step/Ledge/Walkway Deck/Hall Floor top lies within 0.5 below the surface (FILM=0); (f) surface minus lowest floor <=3.5. Measured on the 3 dumps: current fails everything (above numbers); proposed gives THIN 0, LEAK 0, NOT_SOLID 0, FILM 0, max depth 1.89 for all 80 halls, 63 chambers and 75 tunnels. Studio (local session only, settles the uncertainty): in a play session on pinned seeds 837834/1/101, call Terrain:ReadVoxels(region:ExpandToGrid(4),4) over every manifest WaterRegion. Assert occupancy >=0.97 in row [F-4,F] across the footprint and 0 in the neighbouring columns. Screenshot a hall wall foot, a chamber corner and side step, a wet tunnel channel side and a PaddlingRoom. Stand a default R15 at the deepest basin point and confirm the Humanoid never enters Swimming.

**risks:** Water surface is 0.2 lower than today (F-0.1 instead of F+0.1), so every wading depth is 0.2 shallower; flag to the owner and update RECIPES. If someone later raises Configuration.DeepEndMax toward 3.5, depth 3.4 puts a 3-stud root 0.4 under water, so the swim check must be repeated. Coves at the wall foot sit at F (F1/F2 cluster): with the surface at F-0.1 their lower lip stands 0.1 proud, so any re-seated cove must keep its lip >= surface. Offline tests L1182-1194 and L849-853 currently assert the old exported sizes and must change together with the kit attrs. Unproven assumption: a 0.975-full row reads as a flat surface ending at the voxel boundary. That is standard terrain behaviour but must be confirmed by the Studio screenshots.

**files:** ServerScriptService/Level 2 Systems/Level 2 Kit World Builder.ModuleScript.lua, tools/level2_poolrooms/modules_tunnel.py, assets/level2/poolrooms-kit/export/manifest.json (rebuild via build.py), artifacts/level2-poolrooms-20261003/RECIPES.md, tools/tests/test_level2_kit_world_builder.py

**refs:** ServerScriptService/Level 2 Systems/Level 2 Kit World Builder.ModuleScript.lua:161-166 water(); ServerScriptService/Level 2 Systems/Level 2 Kit World Builder.ModuleScript.lua:233-236 basinDepth (PaddlingRoom .8, else clamp(DeepEnd,1.6,3.5)); ServerScriptService/Level 2 Systems/Level 2 Kit World Builder.ModuleScript.lua:255 hall water Vector3(Width-2.5, deep+.1, Depth-2.5) top F+.1; ServerScriptService/Level 2 Systems/Level 2 Kit World Builder.ModuleScript.lua:294 and 369 wall/corner-seal base = -basinDepth-4 (walls enclose down to F-4.8 or lower); ServerScriptService/Level 2 Systems/Level 2 Kit World Builder.ModuleScript.lua:1041-1044 corridor water 13.6x1.6 at -0.7 (wet tunnel) / 6.55x0.7 at +0.75 (pipe); ServerScriptService/Level 2 Systems/Level 2 Kit Layout Generator.ModuleScript.lua:482-502 DeepEnd in [1.6, clamp(DeepEndMax or 2.0)] -> 2.0 in practice; ServerScriptService/Level 2 Systems/Level 2 Kit Layout Generator.ModuleScript.lua:893,905,973 4-stud lattice guaranteed for bounds, FloorY, Cross; tools/level2_poolrooms/modules_tunnel.py:272-283 wet tunnel (channel_half 6.8, side faces 6.7-7.0, ledges to 11.23 top F, Water Floor top F-1.5); ServerScriptService/Level 2 Systems/Level 2 Objective Controller.ModuleScript.lua:345-348 drain = FillBlock(Air) on record.Water; ServerScriptService/Level 2 Systems/Level 2 Round Adapter.ModuleScript.lua:187-213 cleanup FillBlock(Air) region+8

## F5 (F5b: escape chambers) - Chamber water is a hard-coded undersized box: 21.7% of every chamber's visible pool floor has no water above it (image 3)

**rootCause:** makeSmall writes water from the table chamberWater={Chamber_A={32,36},Chamber_B={32,52},Chamber_C={48,52},Chamber_D={24,44}} at cf*(0,-.75,2). That mirrors the kit's waterRegion = (w-16, 1.7, d-12) shifted +2 in local Z (modules_tunnel.py L492-493). The chamber's Aqua floor, though, covers the full w x d (L403), with walls' inner faces at +-(w/2-1.75). Side Steps (top F) cover only x in [w/2-7.5, w/2-2.5] for z in +-(d/2-8) (L451-454), and the Dry Threshold covers only x +-(w/2-8) at the entry wall (L404). Resulting dry, visible Aqua floor per chamber: a 2.25 strip along the whole far wall, a 0.75 strip between each side step and its wall, a 0.5 strip between the water edge and the step, 6.25 x 6.25 patches beside the threshold, and the corners outside the step ends. On top of that, the water is the same thin 0.4 row as F5a, so even the covered part recedes from its edges.

**occurrences:** All 63 chambers in the 3 seeds (21+22+20), all four prefabs A/B/C/D and every rotation (0/90/180/270): 27,319 of 126,135 sq studs of visible submerged floor sit outside the water box, up to 6.37 studs from the nearest water. Per-side gap between the water edge and the face it should meet: far wall 2.25, both side walls 6.25 (0.5 to the step, 0.75 behind it), entry wall 0 at the threshold face but 6.25 beside it.

**fixDesign:** Delete the chamberWater table (L801-802) and call poolWater(ctx, hall.MinX, hall.MaxX, hall.MinZ, hall.MaxZ, hall.FloorY, "Chamber "..hall.Index). The chamber footprint already equals the rotated prefab Width x Depth and is on the lattice, so the box is [footprint] x [F-4, F-0.1]. Depth over the Aqua floor becomes 1.1. The Dry Threshold and Side Steps (tops at F) stay dry and the water meets their faces. The strip behind the steps, the far wall and the corners fill. The water's edge sits at the wall's outer face, 1.75 behind the inner face. Wall Runs go down to F-5.25; at open sockets the pipe's mouth threshold (12 wide, F-2..F+1, bound-4..bound) closes the opening; unused sockets keep their Plug and Below-Socket parts. Kit: modules_tunnel.py L492-493 -> waterRegion center [0,-2.05,0], size [w,3.9,d], surfaceY -0.1. Test L849-853 -> expect that box.

**check:** Same check as F5a, item (d): it fails today in 63/63 chambers (dryOutsideBox 27,319 sq studs, NOT_SOLID 126,135) and passes with the fix (0/0, no leaks, max depth 1.1). Add a chamber-specific assertion in the builder test: for each Small hall, the Water fill's XZ extent == (MinX,MaxX,MinZ,MaxZ) and its top == FloorY-0.1 < every Room Dry Threshold / Side Step top.

**risks:** The curved corners and the Chamber_D nook are meshes. The check hides chamber floor outside an r~5.7 arc about (7.5,7.5) from each corner; the D nook (r=7 at w/2-9, -d/2+10) is not modelled and should be added if the test reports nook points. Water now also lies under the Dry Threshold's 0.3 underside gap (visible only edge-on), as it already does under the side steps.

**files:** ServerScriptService/Level 2 Systems/Level 2 Kit World Builder.ModuleScript.lua, tools/level2_poolrooms/modules_tunnel.py, assets/level2/poolrooms-kit/export/manifest.json (rebuild), tools/tests/test_level2_kit_world_builder.py

**refs:** ServerScriptService/Level 2 Systems/Level 2 Kit World Builder.ModuleScript.lua:798-803 makeSmall chamberWater table + water(cf*CFrame.new(0,-.75,2), (w,1.7,d)); tools/level2_poolrooms/modules_tunnel.py:403-404 Room Aqua Floor (w x d, top F-1.2), Dry Threshold (w-16 x 8, top F); tools/level2_poolrooms/modules_tunnel.py:451-454 Side Steps (5 x 1.4 x d-16, top F); tools/level2_poolrooms/modules_tunnel.py:492-493 waterRegion center [0,-.75,2] size [w-16,1.7,d-12]; tools/tests/test_level2_kit_world_builder.py:849-853 asserts the builder copies that exported region

## F5 (F5c: narrow pipes) - Pipe_Flat 'water' is a 0.1-stud film that never renders (image 2); either drop it or rebuild the pipe floor

**rootCause:** Pipe_Flat's Aqua floor top is F+1.0 (modules_tunnel.py L314, centre .6, size .8). Its waterRegion runs from F+0.4 to F+1.1 (L319-320), i.e. 0.1 above the floor, and fills row [F,F+4] to only 0.175. The owner's pipe screenshot (image 2) shows bare Aqua tiles and no water anywhere. The pipe floor is 1 stud above the hall deck by design (mouth thresholds top F+1.0), so no voxel-solid water surface (F-0.1) can lie above it.

**occurrences:** Every Pipe_Flat in every seed: 31/33/32 in seeds 837834/1/101, 96 total. In all of them check_f5 reports 100% non-solid surface and 2,080 thin voxels. Pipe_Stair4 has no water.

**fixDesign:** Default: pipes are dry passages. Remove the `or (narrow and c.Variant=="Flat")` branch at L1041, delete the pipe waterRegion attr in modules_tunnel.py L319-320, and have the test assert no Water fill for Narrow. This is safe: drains are only ever on Open Wet tunnels (Layout L984/L1002), and visually nothing changes because the film never rendered. If the owner wants wet pipes instead, the kit must lower the Pipe_Flat floor to F-0.8 (top) while keeping the 1-stud mouth thresholds at F+1.0 as steps down. Then use the F5a rule with box [From,To] x [Cross-4,Cross+4] x [F-4,F-0.1]: the bore half-width at F-0.1 is about 3.5, so the edge sits behind the shell. That is a kit geometry change and needs an owner decision.

**check:** check (b) in the F5a check: no Water fill whose owner corridor has Kind=='Narrow' (or, with wet pipes, the aligned box and the solid-surface test over the 'Passage Aqua Floor' samples).

**risks:** Image 2's aqua pipe floor still reads as a channel without water; if the owner expects water there, take the alternative (kit floor change, collar/threshold step heights, chamber socket bottoms at F-2 must still be filled).

**files:** ServerScriptService/Level 2 Systems/Level 2 Kit World Builder.ModuleScript.lua, tools/level2_poolrooms/modules_tunnel.py, tools/tests/test_level2_kit_world_builder.py

**refs:** ServerScriptService/Level 2 Systems/Level 2 Kit World Builder.ModuleScript.lua:1041-1044 (narrow and c.Variant=="Flat") water 6.55x0.7 at +0.75; tools/level2_poolrooms/modules_tunnel.py:309-320 Pipe_Flat floor + waterRegion surfaceY 1.1; ServerScriptService/Level 2 Systems/Level 2 Kit Layout Generator.ModuleScript.lua:984 narrow corridors can never carry a DrainGroup; tools/tests/test_level2_kit_world_builder.py:1182-1194 corridor water must equal exported waterRegion

### Other problems seen
- The water (nominal F+0.1) currently covers every walkable top at FloorY: tunnel and pipe mouth thresholds inside halls, chamber Dry Thresholds and Side Steps, tunnel Ledges, and Paddling Threshold Ground. That is 582 hall, 307 tunnel, 189 chamber and 192 pipe part-tops within 0.5 under the surface. The F5 fix (surface F-0.1) ends this, but the RECIPES contract 'surface FloorY+0.1' must change with it.
- Pool hall CoveBase runs sit at FloorY (wallPose y=hall.FloorY, coveRun L276-294), i.e. at the water line above a basin floor 0.8-2.0 lower, so the cove floats over the pool (images 1/3: gap under the cove, dry strip seen beneath it). This belongs to the F1/F2 cluster, but any re-seated cove must keep its lower lip at or above the new F-0.1 surface.
- Pipe_Flat 'Worn' overlay patches are 0.015-thick boxes at y 1.012 (modules_tunnel.py L315-317), i.e. 0.012 above the Aqua floor top. These are the white squares in image 2 (F3 cluster).
- The Objective Controller drain (L345-348) Air-fills record.Water as-is. With today's non-aligned 13.6-wide tunnel box it only partly clears the edge voxels, which straddle the channel sides. The aligned box fixes this as a side effect.
- Configuration has no DeepEndMax, so the Layout Generator's deepMax is clamp(2.0) and every DeepEnd is <=2.0 (measured max 2.0). The KIT_SPEC phrase 'deep end <= 3.5' is a ceiling that is never reached; raising it later would need a swim test.

### Notes
I edited nothing in the repo, ran no git, and did not touch Studio. Scratch work is in G:/Roblox/_local/l2fix/f5/:
- check_f5.py is the proposed check. Run `python check_f5.py current|proposed [seeds]`; it writes check_current.json and check_proposed.json.
- measure.py is an earlier measurement pass.
- check_dbg.py is a debug copy.
- crop3.png and crop4.png are crops of the screenshots.

Images:
- Image 3 is an escape chamber (Side Step ending before the curved corner, dry Aqua floor along the wall foot), so F5b applies.
- Image 4 is almost certainly the inside of a RoundTunnel_Wet: cream ledge with a 1.5-stud channel-side face, a curb, the bore curving up behind it, and the hall seen through the mouth. That is F5a.
- Image 2 (pipe) shows that the 0.175-full pipe water never renders.

Key enabler: the layout validator already guarantees that every hall bound, corridor Cross/From/To and every FloorY sits on the 4-stud lattice. Water boxes can therefore be made exactly voxel-aligned with no layout change. The design rests on one assumption about how terrain draws a nearly full (0.975) row. It is standard behaviour, but the Studio ReadVoxels pass plus screenshots in the check must confirm it before landing.

What I did not model: hall coves and corner coves are MeshParts, so the offline check treats the floor under them as visible. That is conservative and only makes the check stricter. In the proposed design the water already runs under the walls.

## F10 - WallVoid reads as a plain white square frame: it sits 1.95 studs proud of the wall, the dark face is buried inside the wall slab, and the frame colour does not match

**rootCause:** Kit WallVoid (modules_arch.py:486-492) is four standalone Tile Parts that form a 14x8x3 frame, plus a 10x4x0.1 'Void' plane at local z=+1.65. The builder places it with wallPose(hall,side,along,1.2), and wallPose adds +1 for the collar, so the pivot ends up 2.2 studs inside the boundary. It never cuts the wall slab. The slab spans boundary..boundary+1.75, so the frame spans boundary+0.7..+3.7: 1.95 studs in front of the wall face and 1.05 studs inside the slab. The dark plane lands at boundary+0.5..0.6, fully inside the opaque slab (SAT containment in every case). Inside the frame you therefore see the cream wall face, not a void. On top of that, the frame Parts come in at the kit palette colour (255,255,255, prkit.py:29), while every builder shell Part is WHITE (241,237,220, builder line 9), so the frame is whiter and bluer than the wall. That is exactly image 8.

**occurrences:** Every WallVoid placement: 27 / 23 / 28 in seeds 837834 / 1 / 101, 100% with the buried dark face (prototype check C1b). Placements: (a) one high void on the South wall (Width>=Depth) or East wall at Center+0.25*long side, y=FloorY+0.6h..+0.6h+8, in ColumnHall, BigPool, VaultArcade, CurvedChannel, SpiralWell, CorridorHall, PaddlingRoom and PumpHall. (b) 3-4 foot 'outflow' voids per BigPool hall (~1.9 BigPools per layout) at y FloorY..FloorY+8. Each of these also intersects CoveBase64 by 1.95 studs (6 in 837834, 18 in 101). (c) In every CorridorHall (8% of layouts, 16 in 200 seeds) the void sits on the same wall as the SunSlit row. Since |0.75W-16-24k|<12 always holds and 0.6h+8 > h-20 for every class, the void frame always interpenetrates a slit frame there. Chambers and corridors have no voids.

**fixDesign:** Recommended: make it a real flush recess, which is how references df377... and PoolroomsThemeBg show it (a dark opening in the tile, no frame).
(1) Kit wall_void(): delete the four 'Void Side/End' part records. The component becomes one 'Void Back' record: m.part('Void Back',(0,2,-0.1),(10,4,0.2),'Void',collide=True). The pivot is the outer boundary plane, local +Z points out of the room, y=0 is the opening bottom.
(2) Builder: add a pure function wallVoidSlots(hall,doorsBySide). For each slot it returns {side, along, bottom, top}. The high slot is bottom=round(0.6*h), top=bottom+4. The BigPool outflow slots are bottom=3.5, top=7.5, which keeps them above the 3-stud base cove. Keep the existing along rules. In wallShell, insert each slot as a hole {low=along-5, high=along+5, bottom, top, Void=true}, but only if it is clear of every existing hole by 2 studs, using the same test as the sun slit at lines 310-313. Never let it reach the overlap assert at 327, which would abort generation. The sill and lintel slabs then line the 10x4 opening with the wall's own WHITE tiled faces.
(3) Dressing: cloneComponent('WallVoid', parent, wallPose(hall,side,along,-1)*CFrame.new(0,bottom,0), true). wallPose(-1) puts the pivot exactly on the boundary, so the back plate fills boundary..boundary+0.2 and the recess reads 1.55 deep, entirely inside the hall's own slab. Nothing protrudes into the room, so nothing in the room can intersect it.
(4) Fix the cove cut rule in wallShell (lines 326-341). The base cove may be split only by holes with bottom<3.3, and the top cove only by holes with top>h-3.3. Today every hole splits both coves.
Fallback, if the owner would rather not have voids: delete lines 562-572 and 759-766, and remove 'WallVoid' from the BigPool 'required' table in tools/tests/test_level2_kit_world_builder.py:901.

**check:** New tools/tests/test_level2_kit_decor.py. It reuses harness.build_program/run_luau from test_level2_kit_world_builder.py to build at least 40 seeds: the 5 fixed ones, plus generated seeds until at least 3 CorridorHalls and at least 5 BigPools have been exercised. The test asserts those Type counts. Runnable prototype on the existing dumps: G:/Roblox/_local/l2fix/decor/decor_check.py (common.py next to it). Assertions for this issue:
C1: no visible Part/MeshPart whose Level2_KitComponent is WallVoid or SunSlit extends more than 0.05 beyond the room face of the hall wall slab it touches (wall slabs = 'Level 2 Hall Wall/Sill/Lintel').
C1b: for every WallVoid back plate, the point 0.1 studs off its room-side face lies inside no opaque part.
C1c: every WallVoid has a matching Sill/Lintel hole of exactly 10x4 at its along/bottom.
C2: every PR Tile/Aqua/Worn part has Color == (241,237,220).
C8: no WallVoid OBB intersects any other component, cove or door by more than 0.05.
Today this fails C1b 27/23/28 times, C1 31/27/32 (with SunSlit), C8 CoveBase x WallVoid 6/0/18.
Kit-level assert in modules_arch.validate(): the WallVoid and SunSlit records and chunks span local z in [-0.25,0] only.

**risks:** Cutting holes adds one Sill and one Lintel Part per void, but four frame Parts go away, so the count drops. A void slot that collides with a door, slit or exit gap must be skipped, never asserted. The current along rules already avoid corners for every legal hall size (the void edge is at least 19 studs from a corner), but keep the corner-radius guard. The installed kit needs a Blender re-export plus import_kit.py --profile poolrooms, and the KitBuild/ManifestSha256 change. Open owner decision: KIT_SPEC calls these 'glowing' voids while RECIPES calls them 'darkness accents'. The design above is dark; to make it glow, change the back plate's material only.

**files:** tools/level2_poolrooms/modules_arch.py, ServerScriptService/Level 2 Systems/Level 2 Kit World Builder.ModuleScript.lua, tools/level2_poolrooms/assemble_level.py, tools/tests/test_level2_kit_world_builder.py, new: tools/tests/test_level2_kit_decor.py

**refs:** ServerScriptService/Level 2 Systems/Level 2 Kit World Builder.ModuleScript.lua:259-266 (wallPose inset+1); ServerScriptService/Level 2 Systems/Level 2 Kit World Builder.ModuleScript.lua:562-572 (BigPool foot 'outflow' voids, i=2..5 of 7 along East/South, local y 0..8 = on the waterline); ServerScriptService/Level 2 Systems/Level 2 Kit World Builder.ModuleScript.lua:759-766 (one high void per hall at CeilingClass*0.6, every Type except Arrival/ExitHall); ServerScriptService/Level 2 Systems/Level 2 Kit World Builder.ModuleScript.lua:288-342 (wallShell: no hole cut for voids; coveRun cut by every hole); tools/level2_poolrooms/modules_arch.py:486-492 (wall_void); tools/level2_poolrooms/prkit.py:29 (Tile tint 255,255,255); tools/level2_poolrooms/assemble_level.py:304-306 (render assembler mirrors the placement)

## F10+F4 - SunSlit is the same protruding white frame, sits on top of the Arrival door in 2 of 3 seeds, intersects the top cove, and its glow plane leaves slivers

**rootCause:** Kit sun_slit (modules_arch.py:473-483) builds a 10x20x3 frame (Slit Side/End Parts plus colliders), and the builder places it at wallPose(...,1.2) (line 334). That stands it 1.95 studs proud of the wall, at kit colour 255 against wall 241/237/220, and it runs through CoveTop64 by 1.95. The wall hole (bottom h-17, top h-3, wallShell 304-316) reaches the top cove band, so both coves get cut there; the base cove keeps a 0.14-stud hairline seam under the slit. The 1.8x13.8 Neon plane sits inside a 2x14 hole, which leaves 0.1-stud slivers to the outside. For the Arrival, sunWall is North (W>=D) or West, at the wall midpoint. makeArrival centres the ArrivalDoor on its back wall, and when that is the same wall the frame lands on 'Level 2 Arrival Wall Upper' (FloorY+20..26) and the hole bottom (h-17=FloorY+25) overlaps it.

**occurrences:** Arrival: one per layout. Seeds 837834 and 101 have it intersecting the ArrivalDoor (8 OBB hits each); seed 1 does not. CorridorHall: every 24 studs from low+16 to high-16 on the South/East wall, in the 8% of layouts that contain one, and always colliding with that hall's WallVoid (see F10). CoveTop64 is intersected in every seed (4 hits each).

**fixDesign:** Kit: delete the four Slit Side/End parts and colliders. The sill, lintel and wall slab already line the 2x14 hole. Make the warm plane 2.4x14.4x0.2 at local z=-0.1 with the pivot on the boundary (wallPose(...,-1)), so it overlaps the hole edges by 0.2 and leaves no slivers. Keep it Neon LightWarm.
Builder: set hole top to h-3.5 so the top cove is not cut, and apply the cove cut rule from F10. Place it at wallPose(hall,side,at,-1)*CFrame.new(0,h-17.5,0) so the plane's 14.4 height covers h-17.5..h-3.1 overlapping the hole by 0.2.
Arrival: compute the door direction exactly as makeArrival does (shared helper arrivalDirection(layout,hall)) and put the slit on a side wall parallel to it: direction along X gives 'North', along Z gives 'West'. Never use the door wall.
CorridorHall: insert the slit holes first and the void slot only if clear (F10 step 2).

**check:** Same test file. C1 flush test applied to SunSlit. C8: no SunSlit part intersects ArrivalDoor or any Cove part. C10: each slit's Neon plane covers its wall hole rectangle with at least 0.1 overlap on all four sides (compare the plane OBB with the hole rectangle derived from the Sill/Lintel/Wall gap). C11 cove continuity: along every wall, the union of CoveBase64 intervals (and of CoveTop64 intervals) covers [low+R, high-R] except at holes that reach that band, with no gap over 0.01. Seeds must include at least 3 CorridorHalls.

**risks:** An open slit to the sky is listed in KIT_SPEC as an intended opening; keeping the glow plane closes it visually, so tell the owner. Moving the Arrival slit to a side wall changes the arrival lighting slightly.

**files:** tools/level2_poolrooms/modules_arch.py, ServerScriptService/Level 2 Systems/Level 2 Kit World Builder.ModuleScript.lua, tools/level2_poolrooms/assemble_level.py

**refs:** ServerScriptService/Level 2 Systems/Level 2 Kit World Builder.ModuleScript.lua:304-316,333-336; ServerScriptService/Level 2 Systems/Level 2 Kit World Builder.ModuleScript.lua:1158-1175 (makeArrival back wall); tools/level2_poolrooms/modules_arch.py:473-483

## F4-verticals - Every column, pier, curved wall and spiral core in a flooded hall stops 0.8-1.9 studs above the basin floor; PaddlingRoom columns stop 8 or 18 studs below the ceiling

**rootCause:** Floor-standing kit pieces are modelled from y=0 = FloorY (water level): column lathe at modules_arch.py:177 [(0,r),(h,r)], wall_from_path cap at 243 starting at y=0, pier part at 443, spiral core at 389. Builder fitVaultPier (483-490) also seats piers at FloorY. The basin floor top, however, is FloorY-0.8 (shallow end) down to FloorY-DeepEnd (up to 2.0 with DeepEndMax), so through the 0.35-transparency water every vertical visibly hovers. Separately, PaddlingRoom hardcodes 'Column_D6_H34' (line 744), but PaddlingRoom CeilingClass is rolled from 34/42/52; Column_D6_H42/H52 exist in the kit and are never used.

**occurrences:** Floating bottoms: 92 / 112 / 102 visible pieces in seeds 837834 / 1 / 101. That is every Column_D10/D16/D6, VaultPier, CurveWall_Q16/S48 and SpiralStairWell in ColumnHall, BigPool, VaultArcade, CurvedChannel, SpiralWell, PaddlingRoom and CorridorHall. Short PaddlingRoom columns: 8 / 4 / 8 per seed. Over 200 layouts, 67.5% of PaddlingRooms are CeilingClass 42/52, about 3.4 rooms x 2 columns per layout.

**fixDesign:** Use one constant, matching the wall rule in KIT_SPEC section 6 ('start 4 below the floor'):
(1) Kit: model every floor-standing vertical from y=-4. Column: lathe [(-4,r),(h,r)], collider centre (h-4)/2, size h+4. Spiral core: lathe [(-4,5),(h+8,5)], collider likewise. wall_from_path: cap profile y=0 becomes y=-4, and arc_boxes vertical becomes ((height-4)/2, height+4). The worst deep end is FloorY-3.5 (builder clamp at line 235), so -4 is always at least 0.5 below the basin floor and hidden under it.
(2) Builder fitVaultPier(model,pos,height): Size.Y=height+4, CFrame=CFrame.new(pos+Vector3.yAxis*(height/2-2)).
(3) Line 744: 'Column_D6'..suffix, where suffix='_H'..min(CeilingClass,52) is already in scope.

**check:** C3 in test_level2_kit_decor.py. For every visible part whose component starts with Column_/VaultPier/CurveWall_/SpiralStairWell and is taller than 10: AABB min y <= basinTop(hall,x,z)+0.05 and AABB max y >= FloorY+CeilingClass-0.05. basinTop = FloorY-0.8-(deep-0.8)*(s-Min)/run, with s=x or z along PoolAxis (shallow at Min, deep at Max; verified against the dump floor Parts). Today it fails 92/112/102 (bottom) and 8/4/8 (top). Also update the pier assert at test_level2_kit_world_builder.py:933 to low[1] <= basinTop+0.05.

**risks:** Kit re-export and reinstall. The column collider grows downward by 4, which is invisible and below the floor, so no gameplay effect. The Pool Foam pathfinding modifiers are unaffected because the colliders keep the same XZ.

**files:** tools/level2_poolrooms/modules_arch.py, ServerScriptService/Level 2 Systems/Level 2 Kit World Builder.ModuleScript.lua, tools/tests/test_level2_kit_world_builder.py

**refs:** tools/level2_poolrooms/modules_arch.py:174-182 (column); tools/level2_poolrooms/modules_arch.py:233-273 (wall_from_path/curve_wall); tools/level2_poolrooms/modules_arch.py:386-389 (spiral core); tools/level2_poolrooms/modules_arch.py:441-445 (pier); ServerScriptService/Level 2 Systems/Level 2 Kit World Builder.ModuleScript.lua:483-490 (fitVaultPier); ServerScriptService/Level 2 Systems/Level 2 Kit World Builder.ModuleScript.lua:744 (Column_D6_H34); tools/tests/test_level2_kit_world_builder.py:926-936 (asserts piers span exactly FloorY..ceiling, i.e. it encodes the defect)

## F4-walkways - Walkway decks, bends and island ends float 0.4-1.6 studs above the basin floor; Walkway_Bend16 is an isolated quarter ring that dead-ends in the water; the Walkway_End 'island' is two slivers stuck inside a column

**rootCause:** Walkway_Straight32 is a 0.8-thick deck Part (top +0.445, bottom -0.355) plus thin bullnose strips. Bend (path_deck) and End (arc_solid) are 0.8 thick too. Pools are 0.8-2.0 deep, so there is a visible gap under every deck. Walkway_Bend16 is dropped into an arbitrary 24x24 floor pocket (VaultArcade 601-608, CurvedChannel 699-705) at walk-(10.7,0,10.7), so it connects to nothing and both of its closed square ends sit in water. Walkway_End is placed twice at island-5x and island+5x (546-549). Each is a radius-5 half disc centred 5 studs from the column centre, so most of it lies inside the radius-5 Column_D10 and only two crescent slivers poke out at the waterline.

**occurrences:** Floating decks: 64/59/68 straight strips and every Bend/End (all flooded halls). Bends: 24 placements across the 3 seeds, of which 21 dead-end at both ends and 3 at one end (G:/Roblox/_local/l2fix/decor/bends.py). Walkway_End: every BigPool hall, 2 pieces each, overlapping the column (8 and 12 hits). Bends also overlap straight decks (14/8/14) and corner coves.

**fixDesign:** (1) Kit: deck solids go down to y=-4. Straight: m.part('Walkway Deck',(0,-1.7775,0),(size+1.2,4.445,9.4)), and the bullnose prism strips from -4. path_deck bottom=-4. End arc ys=(-4,.45). Ground colliders unchanged (top at +0.445).
(2) Remove the free Walkway_Bend16 placements (lines 601-608 and 699-705), and drop 'Walkway_Bend' from the VaultArcade/CurvedChannel required list in the world builder test. A bend belongs only where it joins two walkway runs, which is the F2 corner-continuation work.
(3) Replace the Walkway_End pair with one ring island: new kit piece Walkway_Ring_R9 = arc_solid over 0..2pi, radii (5.0, 9.0), ys (-4, 0.45), with ground colliders via arc_boxes on radius 7, width 4. Place it once at CFrame.new(island) and reserve that column as 20x20 instead of 14x14. If the owner prefers less, delete lines 546-549 and drop 'Walkway_End' from the test.

**check:** C3b: every 'Walkway Deck' and every Walkway_* MeshPart has AABB min y <= basinTop at 7 sample points along its length +0.05 (fails 64/59/68 today). C7: for every walkway piece, each free end, sampled 1.5 studs beyond the end along its tangent at FloorY+0.2, must lie inside another walkway deck, a dry floor Part or a wall slab, so no dead end in water. Every Walkway_Ring is concentric with a column (within 0.1), and its inner radius equals the column radius ±0.05.

**risks:** A taller deck changes nothing for walking, since the top is unchanged. Terrain water filled inside the deck volume is hidden. Removing the bends removes walkable islands in the AI pockets, which is neutral for the Pool Foam lanes.

**files:** tools/level2_poolrooms/modules_arch.py, ServerScriptService/Level 2 Systems/Level 2 Kit World Builder.ModuleScript.lua, tools/level2_poolrooms/assemble_level.py, tools/tests/test_level2_kit_world_builder.py

**refs:** tools/level2_poolrooms/modules_arch.py:276-318 (path_deck, walkway); ServerScriptService/Level 2 Systems/Level 2 Kit World Builder.ModuleScript.lua:427-449 (straight strips); ServerScriptService/Level 2 Systems/Level 2 Kit World Builder.ModuleScript.lua:546-549 (Walkway_End pair); ServerScriptService/Level 2 Systems/Level 2 Kit World Builder.ModuleScript.lua:601-608, 699-705 (free Bend16)

## F4-vault - VaultBay32 hangs as an unsupported dome block: wrong vault type, and 3 of 4 corners have no pier

**rootCause:** modules_arch.py:422 computes the surface as y = h-12 + 12*sqrt(1-(max(|x|,|z|)/16)^2). That is a cloister (domical) vault, whose whole perimeter sits at spring height h-12 with a 0.65 lip, and it needs walls on all sides. KIT_SPEC asks for groin vaults on piers. The builder (573-600) puts 2x2 bays at Center±16 but piers only at Center±32, so the centre point and the four mid-edge points, which are on the ±17 AI lanes, are left with nothing under them. From outside the 64x64 area you see the lip 12 studs under the flat ceiling with the dome's back rising behind it, as in renders/03_vault_arcade.jpg. On top of that, the hall LightWell (reservePocket 36x36, lines 754-757) is placed with no knowledge of the bays and lands inside them.

**occurrences:** Every VaultArcade hall (about 2.8 per layout; 552 in 200 layouts) and Entity Dens drawn as VaultArcade. Unsupported corners: 42/9/25 in seeds 837834/1/101. LightWell x VaultBay intersections: 16/6/8.

**fixDesign:** (1) Kit line 422: replace max(abs(x),abs(z)) with min(abs(x),abs(z)), giving a groin vault. The perimeter arches then rise to h at the mid-edges, flush with the flat ceiling, and spring only at the corners.
(2) Builder VaultArcade: one bay per quadrant, never straddling a lane. Bay side S = clamp(min(W,D)/2-32, 16, 32). Bay centre = Center + (sx,sz)*(21.5+S/2). Pier corners = bay centre ± S/2 (inner corners 21.5 from the axes, so the 9x9 pier reservation clears the 17 lane). reserveAt each of the 4 corner piers. If any corner fails (door spoke, wall margin), place no bay in that quadrant. Scale the bay mesh horizontally by S/32 (same pattern as CurveWall at 632-638) and keep the 12-stud rise.
(3) Keep a ceilingTaken list of bay squares, and place the LightWell only where its 24+2 panel does not overlap any of them. If none fits, put it in a bay-free quadrant or skip it for VaultArcade.
Fallback (lazy): delete the VaultBay placements and keep the piers as square columns.

**check:** C6: for every VaultBay MeshPart, each of its 4 corners at spring height lies inside a VaultPier OBB padded by 0.5 (fails 42/9/25 today). C8: no LightWell or other ceiling decor OBB intersects a VaultBay. Kit-level: sample the exported VaultBay mesh and assert y(±16,0) == h and y(±16,±16) == h-12 (groin) within 0.05.

**risks:** 16 piers per hall instead of 4 (+12 Parts plus colliders per VaultArcade) is well inside the 8,500 budget. More pier reservations can starve the Pool Foam spawn or walkway pockets in 96-wide halls, so run a 200-seed builder sweep for new asserts. Kit reinstall needed.

**files:** tools/level2_poolrooms/modules_arch.py, ServerScriptService/Level 2 Systems/Level 2 Kit World Builder.ModuleScript.lua, tools/level2_poolrooms/assemble_level.py, tools/tests/test_level2_kit_world_builder.py (vault assertions 914-926)

**refs:** tools/level2_poolrooms/modules_arch.py:412-438; ServerScriptService/Level 2 Systems/Level 2 Kit World Builder.ModuleScript.lua:492-503 (placeVaultBay); ServerScriptService/Level 2 Systems/Level 2 Kit World Builder.ModuleScript.lua:573-600; ServerScriptService/Level 2 Systems/Level 2 Kit World Builder.ModuleScript.lua:754-757 (LightWell)

## F4-drain - DrainHole is an 8x8 white tile patch floating 0.1-1.1 studs above the aqua basin floor, under the water

**rootCause:** Kit drain() (modules_arch.py:495-511) is an 8x8 square 'Tile' patch, 0.25 thick, with a 3-diameter hole and a Void disc. The builder places it at FloorY-0.7 (line 777). The basin floor top is FloorY-0.8..-DeepEnd and tilted along PoolAxis, so every drain floats, and it is white Tile on an Aqua floor: a white square in the pool, the same look as the white patch in image 2. Pockets also ignore pool steps, so drains land on PoolSteps_Curved and touch corner coves.

**occurrences:** Every drain: 100/104/99 placements (up to 4 per hall, by area) in all flooded Types except Arrival/PumpHall/ExitHall. Not one is flush (G:/Roblox/_local/l2fix/decor/drains.py). On PoolSteps_Curved in PaddlingRooms: 12/0/4.

**fixDesign:** Kit: drop the square patch ring and keep a Void disc of radius 1.5, height 0.06. A plain dark round drain matches the dark floor pits in reference df377.
Builder: add basinTop(hall,x,z) = FloorY-0.8-(deep-0.8)*(s-Min)/run, with s=x or z by PoolAxis and run = Width/Depth, matching floorShell. Place the disc at CFrame.new(x, basinTop+0.03, z)*rotation, where rotation is floorShell's tilt (a 0.5° slope keeps the edge within 0.013).
In placeWalkways, add reservations for every PoolSteps footprint: straight 12 wide x 17 deep from the wall; curved 44 x 22. Do the same for the walkway bands (see the next issue), so drains and other floor decor avoid them.

**check:** C4: every DrainHole part's AABB top is within basinTop+0.03±0.05 at its centre (fails 196/199/192 today). No DrainHole part uses a PR Tile variant over an Aqua floor. C8: no DrainHole intersects PoolSteps, Walkway, Cove or CornerCove parts.

**risks:** Minimal. Fewer instances. A drain sitting on the AI lane has no collider, so it is harmless.

**files:** tools/level2_poolrooms/modules_arch.py, ServerScriptService/Level 2 Systems/Level 2 Kit World Builder.ModuleScript.lua, tools/level2_poolrooms/assemble_level.py

**refs:** tools/level2_poolrooms/modules_arch.py:495-511; ServerScriptService/Level 2 Systems/Level 2 Kit World Builder.ModuleScript.lua:767-779; ServerScriptService/Level 2 Systems/Level 2 Kit World Builder.ModuleScript.lua:238-257 (floorShell tilt: shallow at Min, deep at Max)

## F4-walkway-band - Columns, piers and curved partitions are placed inside the walkway strip and pierce the walkway deck

**rootCause:** clearPocket/reservePocket (187-230) keep only a 6-stud margin from the walls, but the walkway strips on two walls occupy 1.25..11.25 from the wall. So a Column_D10 at 13 from the wall (8..18), a Column_D16 at 16 (8..24), CurveWall_Q16 and the CorridorHall VaultPier row at 12 (9.5..14.5, line 735) all cut into the deck and its bullnose.

**occurrences:** OBB hits (seed 837834 / 1 / 101): Column_D10 x Walkway 22/22/18, Column_D16 16/36/26, Column_D6 16/20/12, CurveWall_Q16 12/14/12, VaultPier 4/2/12. Affects ColumnHall, BigPool, SpiralWell, PaddlingRoom, CurvedChannel, VaultArcade and CorridorHall (every pier).

**fixDesign:** Have placeWalkways return its two strip rectangles, and seed each hall's reservations with them before makeKids and dressHall: Position = strip centre, Width = full wall length, Depth = 10+2 (band 0..12.25 from the wall). reserveAt/reservePocket then keep all floor decor off the walkways. For CorridorHall, change line 735 offset -hall.Depth/2+12 to +16, and the same for Width.

**check:** C8: no Column_/VaultPier/CurveWall_/SpiralStairWell/DrainHole/LightWell part intersects a 'Walkway Deck' or Walkway_* part by more than 0.05. Run the world builder harness over 200 seeds and assert no new '[Level 2 Kit] no clear spiral well' or 'no safe curved partition pair' errors.

**risks:** Fewer free pockets: the SpiralWell (footprints 40 down to 16) and CurvedChannel asserts could fire in small halls. The 200-seed sweep settles this; if they do fire, let curve walls use the band side only in halls under 112 wide.

**files:** ServerScriptService/Level 2 Systems/Level 2 Kit World Builder.ModuleScript.lua, tools/level2_poolrooms/assemble_level.py

**refs:** ServerScriptService/Level 2 Systems/Level 2 Kit World Builder.ModuleScript.lua:187-230; ServerScriptService/Level 2 Systems/Level 2 Kit World Builder.ModuleScript.lua:427-449; ServerScriptService/Level 2 Systems/Level 2 Kit World Builder.ModuleScript.lua:731-742

## F4-lightround - LightRound is a surface ring hanging just below the ceiling (not recessed) and cuts into column tops

**rootCause:** The kit bezel is 0.55 tall (modules_arch.py:448-462). The builder places it at FloorY+h-0.6 (line 551), leaving a 0.05 gap under the ceiling. The 16-stud grid takes no account of the columns placed just before it.

**occurrences:** Every BigPool LightRound: 98/0/147, all with a 0.05 gap. Column-top intersections: 24/0/36.

**fixDesign:** Kit: bezel rings (0,1.7),(0.15,1.5),(0.15,1.7) make a flat 0.15 flush trim, and the LightWarm disc becomes a 0.04-thick Neon at y=0.02. Builder: pivot y = FloorY+h-0.15, so the top is exactly the ceiling underside. Keep the BigPool column positions in a list and skip any grid point within column radius + 1.7 + 1 of a column centre.

**check:** C5: every LightRound tile part's AABB max y equals FloorY+CeilingClass within 0.01. C8: no LightRound intersects any Column_.

**risks:** None significant; it only changes the light marker height, by 0.45.

**files:** tools/level2_poolrooms/modules_arch.py, ServerScriptService/Level 2 Systems/Level 2 Kit World Builder.ModuleScript.lua

**refs:** tools/level2_poolrooms/modules_arch.py:448-462; ServerScriptService/Level 2 Systems/Level 2 Kit World Builder.ModuleScript.lua:550-561

## F4-steps - Pool steps at walkway walls start under the deck, and pool steps in dry halls are fully buried

**rootCause:** placeWalkways (450-472) puts every door's PoolSteps pivot 5 studs from the wall at y=FloorY. On a walkway wall the deck covers 1.25..11.25, so step 1 is hidden under the deck and the deck edge drops 1.65 to step 2 (-1.2). In dry halls (PumpHall) all three steps sit below the floor.

**occurrences:** Step 1 under a deck: 43 / 48 / 44 steps in seeds 837834/1/101 (all flooded Types with a door on a walkway wall). PumpHall: every step buried (12/9/15 step Parts).

**fixDesign:** On walls with a walkway, place the step pivot at the deck edge (11.25 from the wall) and at y=FloorY+0.45. Kit tops -0.6/-1.2/-1.8 then become FloorY-0.15/-0.75/-1.35: equal 0.6 risers down from the deck. Skip PoolSteps entirely when basinDepth(hall)==0.

**check:** C12: for every PoolSteps_Straight12 'Step Ground 1', the top is at deck top -0.6±0.05 and it lies outside every Walkway Deck footprint. There are no PoolSteps parts in halls with basinDepth 0.

**risks:** This overlaps the F2 walkway/corner cluster; coordinate so only one change edits placeWalkways.

**files:** ServerScriptService/Level 2 Systems/Level 2 Kit World Builder.ModuleScript.lua

**refs:** ServerScriptService/Level 2 Systems/Level 2 Kit World Builder.ModuleScript.lua:450-472; tools/level2_poolrooms/modules_arch.py:321-340

### Other problems seen
- Shared root cause with F6/F3: every kit Part and MeshPart is installed at palette colour (255,255,255) (prkit.py:29, import_kit.py:483/528), while every builder shell Part uses WHITE (241,237,220) (builder line 9). That is 1698/1676/1781 kit tile parts per seed that are whiter and bluer than the walls (coves, collars, frames, piers, decks). Smallest fix in one place: in cloneComponent (builder 118-137), set p.Color=WHITE when the MaterialVariant is PR Tile/Aqua/Worn and Color==Color3.new(1,1,1). TileShade (226,220,204) is the separate tunnel ring colour from F3.
- F1 root cause (other cluster): CoveBase/CoveTop profiles in modules_arch.py:122-141 and cove_corner 144-171 put the quarter-circle centre at the wall/floor (or wall/ceiling) corner (y=3 sin a, z=3-3cos a gives centre (y0, z3)). That is a convex quarter-round. A concave cove needs its centre 3 off both surfaces.
- F2 (other cluster): the straight walkway deck length is (size+1.2)*(L-3)/32, about L+4.4 for L=200, so it runs through both end walls and the corner coves instead of turning the corner. Walkways only ever run along two opposite walls.
- Porthole_R6/R10/R15 and 19 other kit components are exported but never placed by the builder (Column_D6_H42/H52, CoveBase/Top16/32, CurveWall_Q32/S64, LightWell_R10, Walkway_Bend32/Straight16, SpiralStairWell_H34, RoundTunnel_Dry_64, Pipe_Stair4_48/80).
- CorridorHall appears in only 16 of 200 layouts (aspect ratio >= 2.2 is rare), and none of the three dumped seeds has one, so its dressing (slit row, pier row, drain row on the centre lane) is barely exercised by the dumps or the 10-seed harness.
- tools/tests/test_level2_kit_world_builder.py:926-936 asserts that VaultPier spans exactly FloorY..ceiling, which encodes the floating-pier defect. The decor test should replace it, not be bent to fit it.
- SpiralStairWell core and LightWell_R6 hang/float in the same way (F7/F8 clusters). LightWell_R6 is a 24x24x8 square collar block under the ceiling (tiled_opening, modules_arch.py:343-383).

### Notes
The white frame in image 8 is the WallVoid. It is not a missing texture: the frame Parts stand 1.95 studs off the wall, the dark face is buried inside the wall slab (100% of placements), and the kit is coloured 255 white against a 241/237/220 wall. Everything above was measured on the exact builder dumps (seeds 837834, 1, 101) with scratch scripts in G:/Roblox/_local/l2fix/decor/: common.py (OBB helpers), overlaps.py, supports.py, drains.py, bends.py, steps.py, and decor_check.py, which prototypes checks C1-C8 for the proposed tools/tests/test_level2_kit_decor.py and currently reports 2577/~2400/~2700 failures per seed. hall_types.py runs the real layout generator over 200 seeds (Type and ceiling frequencies). decor_check.py's C8 is OBB-level: hits involving curved meshes (corner coves, curved steps) can be AABB false positives. The true intersections were confirmed separately (column/deck geometry, void inside slab, slit vs door). The real test should use exact chunk vertices from the export for curved pieces. Unverified: how the 1.55-deep dark recess actually reads in Roblox lighting (needs a Studio play check), and whether the extra walkway-band reservations starve SpiralWell/CurvedChannel pockets; a 200-seed builder sweep settles that. Owner decisions needed: dark versus glowing voids; keep the voids, vaults, island ring and bends redesigned, or simply remove them (fallbacks are given per issue). No files in the repo were edited, no git, no Studio.

## F11 - Exit spiral stair: the step colliders are rotated the wrong way (stairs hitch, gaps near the core), the railing is a zero-thickness sawtooth standing 0.2 off the steps, and the centre column is an open tube

**rootCause:** Everything comes from objectives.py spiral() (ExitSpiral component, placed by makeExit at platformCF). (1) Collision is rotated wrong. Each of the 99 'Level 2 Exit Spiral Ground NNN' boxes (10 x 0.68 x 4.1) and each 'Outer Guard NNN' box (2.1 x 3.6 x 2.9) is exported with yaw=+math.degrees(amid). Roblox applies CFrame.Angles(0,yaw), which sends local X to (cos yaw, -sin yaw) in (x,z), while the step centre sits at (cos amid, +sin amid). Every box therefore ends up 2*amid away from radial: mirrored, and fully tangential at 45 degrees. The dump confirms it: Ground 001 is 11 degrees off and Ground 010 is 27 degrees off. A walk over the dumped colliders of seed 837834 (stair_profile.py) measured this: at r=10, treads are 0.19 to 4.62 studs long with risers of 0.747 and 1.495 (double steps); at r<=7, 83-88% of the circle has no reachable collider top; at r=12-13.5 there are holes; from r=13.5 outward, the guard boxes (top 0.9 above the tread) stick into the walking surface. (2) Even with correct boxes, the design is 99 discrete 0.747-stud risers. A Humanoid pops up every step, about 8 times a second at walk speed, so the walk is jerky. There is no ramp. (3) The first collider top is 0.747 while the pool floor is at -0.8 to -3.5 (dump: -1.31), so the first step is 2.06 high. (4) The visual steps are separate 0.64-thick slabs (bot=top-.64, L243) with no side or under faces. Each step's 0.747 rise leaves a 0.107 slit under the slab; that is the jagged edge in image 10. The top tread (y=74) is coplanar with the deck top over local x -30..-29, which z-fights. (5) The 'railing' is one zero-thickness quad per step (L264-269) at r=15.2, while the steps end at r=15.0. That is the 0.2 gap ('floats off'). The quads are straight chords between top-3 and top+1.1, and each is offset by 0.747 from the next, which makes the sawtooth. It is 0 thick. (6) The core is lathe(m,[(0,5),(74,5)]) with closed=False (L233): a tube open at both ends. Its top at y=74 sits at local x -34..-24 while the deck starts at x=-30, so its west part is uncovered and you see down it (image 11). The bottom is open and floats 0.8-3.5 above the sloped pool floor. The platform support lathe (L184) has the same open, floating bottom. (7) The circle centre (-29,7) lies on the deck footprint, so the final quarter-turn runs into the deck's west face (0.27-0.83 lips at the deck edge) instead of arriving on a landing.

**occurrences:** ExitSpiral exists once per round, in the ExitHall (layout.GrandSlideHall; the Type is always 'ExitHall', 224x208, ceiling 96, hall.MaxX = Bounds.MaxX-32 or -40, so 668 or 660), at platformCF=(MaxX-36,FloorY,deckZ+10). It is the same in every seed, so every round is affected. The ExitPlatform support column (open bottom, floating) has the same flaw. The yaw-sign error is not exit-only: arc_boxes() in modules_arch.py:94-105 and the Room Nook Wall colliders in modules_tunnel.py:466-469 have it too (see otherProblemsSeen).

**fixDesign:** Redo the stair as a closed solid on a smooth hidden ramp. Local frame = platformCF. Move the spiral entirely west of the deck: centre C=(-45.6, 7), world (MaxX-81.6, deckZ+17). Helix: theta1=-90 deg (arrival heading +X), theta0=theta1-1080 deg (3 turns). Nosing line y_n(theta) = -4 + 78*(theta-theta0)/1080 deg, which is 26 studs per turn (4.138 studs/rad). The stair starts 4 studs below FloorY so it comes out of any pool floor between -0.8 and -3.5. VISUAL (objectives.py spiral, one closed mesh): 156 steps, rise 0.5, 6.923 deg each. Tread i has its top at -4+0.5*(i+1) (the last is exactly 74.0) and spans r 4.8..15.0 with 3 angular subdivisions. Add a riser face per step, a continuous helicoid soffit at y_n-1.3, and side faces at r=4.8 and r=15.0, so the stair is a closed solid. CORE: lathe r=5 with closed=True, from y=-4 to 77.5 (a newel post 3.5 above the deck), 32 sides, top cap with a 0.3 chamfer. Collider: Cylinder 10 x 81.5 x 10 at y=36.75. RAMP COLLISION (the only walk surface): 240 segments of 4.5 deg, each with two boxes. Band A: r 4.8..8.6, centre 6.7, Z width 0.705. Band B: r 8.5..15.0, centre 11.75, Z width 1.161. Thickness 1.0. Top plane passes through y_n-0.2 at (r_c, theta_mid). Pitch about the radial axis is atan(4.138/r_c): 31.7 deg (A) and 19.4 deg (B). Right(X) is radial (cos t, 0, sin t), and each box is written as a 12-number cf. ground=True, attribute Level2_StairRamp=true. Computed deviation from the true helicoid is at most 0.09 studs. Relative to the visible treads, feet float at most 0.3 and sink at most 0.2. Rises go up continuously, with no pops. PARAPET: closed visual band from r 15.0 to 15.6, from theta0+60 deg to theta1. The open first 60 degrees is the entry from the pool, where the ramp is still at or below floor level. Bottom y_n-2.0, top y_n+3.5, with a 0.3 half-round cap. It continues straight along the bridge. Collision: 114 boxes (8.947 deg each), 0.6 radial x 5.5 high x 2.44 tangential, centred r=15.3 and y_n(mid)+0.75, pitched 15.1 deg, X radial. TOP LANDING (visible PR Tile Parts): Bridge x -45.6..-30, z -8.6..2.6, y 72.7..74.0, ground. South guard x -45.6..-30, z -8.6..-8.0, y 72..77.5. North guard x -45.6..-30, z 2.0..2.6, y 74..77.5; its west end sits inside the core. DECK: extend 'Level 2 Exit Platform Deck' to local x -30..34.0 (centre x 2.0, size 64 x 1.3 x 41), which puts its east face at MaxX-2.0, flush with the new exit collar (F13). Re-parameterise the nose over x in [-30,34], and clamp each nose ground box so it stays inside the visible nose arc. Close the support lathe (closed=True) and start it at y=-4. ROOT-CAUSE GUARD: prkit.collider/marker take an optional 3x3 matrix (written as a 12-number cf), plus a helper yaw_toward(dx,dz) = -degrees(atan2(dz,dx)); raw yaw is only allowed for multiples of 90. Raise done() budget for ExitSpiral to 8000 tris. Instance delta for the stair is +158 (355 ramp/parapet boxes + 3 landing parts versus the old 198 boxes); with F13 net -6, the total is about +152, inside KIT_SPEC section 5 (8,500 max against 8,164 measured).

**check:** New tools/tests/test_level2_exit_stair.py, plain Python and numpy, reading the Poolrooms manifest plus chunks through render_world.load_kit_chunks. (a) Rebuild every ExitSpiral collider OBB from its 12-number cf. Walk the union of collider tops along circles r in {5.0, 5.5, 7, 9, 11, 13, 14.5} from theta0 to theta1 in 0.05-stud arc steps, accepting a step-up of at most 0.3. Assert: no sample without a collider underneath; every dy is in [-0.02, +0.12]; the end height is 74.0 +-0.02 and continues onto the bridge and deck at 74.0. Today: holes at 83-88% of the circle for r<=7, and 0.747/1.495 jumps. (b) For each sample, the ramp top minus the visual tread top (raycast down on the ExitSpiral chunk) is in [-0.25, +0.45]. (c) Every Ramp and parapet collider's local X axis is radial (|dot| >= 0.999). (d) Every parapet collider's 8 corners lie inside the visual band (r 14.98..15.62, y within band bottom/top +-0.05); consecutive parapet boxes leave no gap > 0.02; the band top is >= ramp+3.4 everywhere. (e) Closure: for ExitSpiral, ExitPlatform and every other Exit* chunk, weld vertices at 1e-4 and assert every undirected edge is used by exactly 2 triangles. This catches a hollow pole, open slabs and a zero-thickness railing; the current export fails it. Per seed, in test_level2_kit_world_builder.py over at least 50 seeds that cover both MaxX=660 and 668 (assert both occur): the hall floor plane height at C lies between ramp(theta0) and ramp(theta0+60 deg); the spiral's OBB set (r<=15.6) intersects no collidable Part except the floor, deck and bridge. In Blender, world_check.py collision flood over the dumps of 837834/1/101: deck-top voxels must be reachable from the hall floor. Today the report shows exitTransitionVoxels=0, so the climb was never validated.

**risks:** Moving the spiral and deck changes the exit hall's look; the owner should see renders. Spiral bbox is x MaxX-97..-66, z MinZ+43..75 with deckZ=MinZ+42 (F13); it is clear of walkways and door pool steps, which sit within 11 of the walls, but the per-seed OBB check is what proves it. Ramp boxes float at most 0.3 above treads, which is visible at the back of each tread. Humanoid on the 22.5 deg mean (39.6 deg at the core) slope is fine at the default MaxSlopeAngle of 89. Pool Foam may climb the ramp because it is EntityGround, as before. Players can still jump the 3.5 parapet (jump height 7.2) into water; collision may not exceed the visual height. A Studio play-test walk-up is still needed to confirm 'no hitch' (record root Y at 60 Hz: its second difference stays small).

**files:** tools/level2_poolrooms/objectives.py (spiral() rewrite, platform() deck/nose/support/portal removal), tools/level2_poolrooms/prkit.py (collider/marker full-frame cf, yaw_toward helper), assets/level2/poolrooms-kit/export (rebuild via build.py), then reinstall with tools/level2_blender/import_kit.py --profile poolrooms, tools/tests/test_level2_exit_stair.py (new), tools/tests/test_level2_kit_world_builder.py (ExitHall component expectations), tools/level2_poolrooms/world_check.py (flood must reach the deck)

**refs:** tools/level2_poolrooms/objectives.py:229-275 spiral() (L233 open core lathe, L243 slab thickness .64, L259-262 Ground collider yaw=math.degrees(amid), L264-269 zero-thickness cheek quad at r=15.2, L270-272 Outer Guard yaw); tools/level2_poolrooms/objectives.py:179-227 platform() (L182 deck 60x1.3x41 ends at local x=30, L184 open support lathe, L189-193 portal walls, L211-215 nose ground boxes extend up to 0.95 past the visible nose); tools/level2_poolrooms/prkit.py:169-172 collider() stores [x,y,z,yaw] with Roblox CFrame.Angles(0,yaw) semantics (no full-frame option); tools/level2_blender/import_kit.py:450-454 cf(): 4-number cf = CFrame.Angles(0,rad(yaw)); a 12-number cf is already supported; ServerScriptService/Level 2 Systems/Level 2 Kit World Builder.ModuleScript.lua:924-926 platformCF and ExitPlatform/ExitSpiral placement; G:/Roblox/_local/l2fix/f11f13/stair_profile.py (measurement), ghost_collision.py (all 45 Outer Guards and 46 Spiral Ground boxes in the sampled height band have no visual within 0.15)

## F13 - Exit tube: the green semi-transparent C is the ExitMouth ring, buried in a convex corner pillar and recoloured to 35% transparency; the square wall and portal openings show sky; invisible style-C tub collision sits on the deck

**rootCause:** The green half-ring in images 12-13 is ExitMouth_Tile, the only MeshPart of the ExitMouth component (objectives.py mouth(): an annulus r 7.2-9.05, 1.5 deep, at local x=22, plus a 5.8-stud sleeve r=7.2). makeExit returns it as Exit.Mouth. When pressure equalizes, ObjectiveController (L465-468) sets Mouth.Color=OPEN_COLOR (180,218,196, pale green) and Mouth.Transparency=.35. That produces the 'green, semi-transparent' look. 'Half inside the wall': the mouth sits at (MaxX-14, FloorY+83.3, deckZ) with deckZ=Center.Z-79.25=MinZ+24.75, which is 28.4 from the NE hall corner. The NE CornerCove_R24_H52 placed by cornerCoves() is a CONVEX quarter pillar: all of its vertices are 24..27 studs from the corner (cove_probe.py; this is the F1 wrong-way cove). The ring's north half (nearest point about 19.4 from the corner) is buried in it. A Workbench render of the dump (renders/837834_visual_deck_e.png) reproduces images 12-13 exactly, for both MaxX=660 (837834) and 668 (seed 1). 'Big opening': the east wall gets an 18.5 x 18.5 rectangular HallWallGap. In front of it, free-standing 'Exit Portal' Parts (L189-193) frame a 20 x 18 rectangle at MaxX-7. The deck stops at MaxX-6, so there is a 4.25-stud drop gap to the wall. The round tube (outer r 7.52) passes through these rectangles, so every corner shows sky. For MaxX=660, 'Level 2 Exit Lead Tile' Parts (builder L941-956) add a square 15.1 duct between the sleeve and the tube. For MaxX=668, the fixed-lead ExitTubeVisual starts at x=656, 10 studs inside the hall, and its inner surface coincides with the sleeve's from 656 to 660.5 (z-fight). 'Invisible collision with nothing': makeExit calls buildTube(..., skipVisual=true), which skips the old style-C tub visual but still creates the tub's three SlideCol_Cradle 'Level 2 Exit Flume Entry Support 1-3' MeshParts. They form an invisible U trough on the deck at x MaxX-24..-14, y 74.5..87. The prefab 'Level 2 Exit Flume Entry Collision Floor' (12.4 x 0.6 x 10.75, top 76.1, 2.1 above the deck top of 74) is also invisible. The SlideCol_Ring_r8 lead duct also has square corners outside the round visuals. The bore floor (76.1) sits 2.1 above the deck, so entering needs a jump. More generally, collision and visual come from two different cross-sections: collision is the old style-C octagonal duct (walls and roof at +-7.2, flat floor, upper corners open), while the visual is a 32-gon circle of r 7.2. In the corners the collision lies up to 2.98 outside the visual shell, so a rider in the helix can push their body or camera through the tube wall.

**occurrences:** Every seed: the exit is always in the ExitHall with deckZ=MinZ+24.75 and the convex NE corner pillar, so the mouth is always half buried. Inset 40 (MaxX=660, e.g. 837834): lead tiles form a square duct; the round tube starts at the wall. Inset 32 (MaxX=668, e.g. seeds 1, 101): no lead tiles; the round tube starts 10 studs inside the hall and z-fights with the sleeve. In all seeds: ghost tub collision and entry floor on the deck; a 2.1 step up into the bore; transparency 0.35 after the pumps finish; collision differs from the visual along all 271 segments of the ride (lead, plunge, 3-turn helix). The prototype ghost_collision.py run on 837834 flags Entry Support x3, Entry Collision Floor, 15 Nose Ground boxes (they protrude up to 0.95 past the visible nose), plus the F11 stair boxes.

**fixDesign:** ONE generator (objectives.py), ONE path (the reviewed slides.json pathPoints, unchanged), ONE cross-section. GEOMETRY (hall-relative; E=hall.MaxX, F=FloorY): deckZ = hall.MinZ+42 (= Center.Z-62). The collar then spans MinZ+32.8..51.2, clear of the convex pillar (27) and of a corrected concave R24 cove (tangent at MinZ+24). anchor = (E+23, F+81.2, deckZ). start = anchor-(25,0,0) = (E-2.0, F+81.2, deckZ), which is exactly the old pathPoints[1], so PathPoints are untouched and the lead is 25 for both insets. Tube axis F+81.2 puts the bore floor top at F+74.0, flush with the deck (and the step-up is gone). BORE CROSS-SECTION: a 16-gon with a flat stave at the bottom (stave centres at -90+22.5k), inner apothem 7.2 (circumradius 7.34 <= BoreRadius 8, so the contract attribute stays 8), wall 0.6 (outer apothem 7.8). VISUAL: tube_visual() builds the 16-gon tube with rings at each path point on the miter (bisector) frame, scaled 1/cos(phi/2) in the bend plane. Inner and outer surfaces plus a closed end ring at the mouth; opaque PR Tile. Per-segment frames: look=normalize(p[j+1]-p[j]), right=normalize(look x Y), up=right x look. The same frames go into both the visual and the collision. COLLISION: 271 'BoreSegment' markers with 12-number cf (segment midpoint plus the segment frame; attrs Index, Length, OneWay from slides segments[i].oneWay), spread across the ExitTubeVisual* components. A new template component 'SlideCol_Bore16' (Template=true; 16 trapezoid-prism islands exactly matching the visual staves; unit Z; size 15.6 x 15.6 x 1) is installed into SlideTemplates; extend import_kit.py:128-139 to take Poolrooms templates. In makeExit, for each marker: clone the template, Size=(15.6,15.6,Length+1.5), CFrame=marker, Name='Level 2 Exit Flume Collision Floor %03d', Transparency 1, attributes Level2_SlideCollision/SlideFloor/OneWayExit/NoEntityGround, SlideDirection=LookVector, CustomPhysicalProperties=SLIDE_PHYSICS. This gives the same 271 instances and names, so the Exit Transition Test Suite's orderedExitFloors, the Size.Z reach check and the slope check are unchanged. Delete the buildTube call, the slidePiece/buildTube functions (only the exit used them), the tub supports, the Entry Collision Floor (skip it in the prefabParts loop, delete the L961-964 shift), and the Lead Tile panels. Keep prefabParts for the sensors, End Stop, recovery chamber and door: they are anchor-relative and move with the anchor (Y shifts -2.1; recycle BottomY becomes F-430.6, still above FallenPartsDestroyHeight+40). WALL OPENING: HallWallGap = {center=deckZ, width=15.92, bottom=F+73.24, top=F+89.16}, a square that hugs the tube's outer circumradius. New 'ExitCollar' component at CFrame (E,F,deckZ): a solid tile panel x in [E-2.0, E+0.25] (through the 1.75 wall, 0.25 proud each side), square +-7.96 about the axis, inner edge = the tube's outer 16-gon. A three-sided frame trim (left, right, top) 1.25 wide and 0.25 proud on the hall face, top at F+90.4, which stays below the CoveTop at F+93. Four 'Exit Collar Corner Fill' colliders at [5.6,7.96]^2 (z,y) x the panel depth, entirely inside the panel and outside the tube polygon. MOUTH: 'ExitMouthTrim', an arch-only annular inlay (y >= F+74) from the bore polygon to r 9.0, 0.06 proud of the collar face. This is the recolor target. Exit.Mouth = it, and Exit.MouthOpenTransparency = 0. Objective Controller L467 becomes exit.Mouth.Transparency = exit.MouthOpenTransparency or .35, so the live Level 2 tub behaviour is unchanged. Remove the portal walls (objectives.py L189-193). The deck east face moves to E-2.0 (F11). Stash ctx.exitPlatformCF in makeExit and place ExitSkylight from it in dressHall L751 (coordinate with the F14 owner). Instance delta for F13 is about -6.

**check:** (1) tools/tests/test_level2_exit_bore.py, numpy only, against the kit export. Transform the SlideCol_Bore16 islands by each BoreSegment marker (Z scale Length+1.5). For 3000 random points on the visual tube's inner triangles, the distance to the nearest collision inner face is <= 0.02 and never more than 0.1 inside the bore (joint overlap). For random points on each island's inner face (excluding the 0.75 overlap ends), the nearest visual triangle is within 0.02. Marker count is 271; marker[1] starts at local (-25,0,0); Lengths equal |p[j+1]-p[j]|. The closure check (every edge has exactly 2 triangles) holds for ExitTubeVisual*, ExitCollar and ExitMouthTrim. (2) Fake engine over at least 50 seeds in test_level2_kit_world_builder.py, asserting both MaxX insets occur: the Exit Transition Test Suite structural checks pass (already wired); there are exactly 271 'Collision Floor NNN' MeshParts and none of 'Entry Support', 'Entry Collision Floor', 'Exit Portal', 'Lead Tile'; |deck top - (anchor.Y-7.2)| <= 0.02; the deck east face equals the collar face (E-2.0) within 0.02; HallWallGap width 15.92 and center MinZ+42; every visible exit Part/MeshPart has Transparency 0. A fake-engine call of the ObjectiveController open path leaves Exit.Mouth.Transparency at 0. (3) Ghost-collision check (generalise G:/Roblox/_local/l2fix/f11f13/ghost_collision.py into tools/level2_poolrooms; Blender BVH on dumps 837834/1/101 plus fresh dumps). Every CanCollide part with Transparency >= .98 in the exit hall and the Exit Flume model must have at least 80% of its 5x5 face samples within 0.15 of a visible triangle or inside a closed visual solid (parity ray). Slide-collision MeshParts are judged by their template geometry; Level2_StairRamp boxes use tolerance 0.45. Today it flags the tub supports, the entry floor and 15 nose boxes. (4) Intersection check: min distance between ExitCollar/ExitMouthTrim/deck/tube triangles and every cove/corner-cove triangle in the exit hall is >= 0.3. Today the mouth is buried in CornerCove_R24_H52 in every seed. (5) world_check.py visual leak test with intended_exit deleted: 0 leak rays in the exit hall (the bore is closed). Collision flood with exit_transition replaced by 'inside the 16-gon around PathPoints': no leak voxels. (6) Studio one-off probe (needs a local session): 64 rays outward from the axis of 5 installed bore pieces must hit at 7.2/cos(delta) +-0.05. This settles whether PreciseConvexDecomposition reproduces all 16 islands. If it does not, split each segment into two 8-island MeshParts (+271 instances, still under budget).

**risks:** KIT_SPEC section 4 (binding) says exit collision is 'unchanged from the reviewed slide design'; this replaces the cross-section and needs the owner's OK. The hull fidelity of a 16-island PreciseConvexDecomposition template is unverified until the Studio raycast probe runs; there is a fallback (above). A per-stave Box-Part tube would be exact but adds about 4,300 instances and breaks the 8,500 budget, so it is rejected. A deckZ shift of +17.25 moves the deck, skylight, spiral and ride (the whole ride translates; the recycle/transition contract is relative and preserved). The Y shift of -2.1 lowers recycle BottomY by 2.1 (29.4 margin left against FallenPartsDestroyHeight -500+40; confirm the place's setting). Depends on F1: deckZ=MinZ+42 clears even the current convex pillar, but the intersection check must run after F1 changes the coves. Old SlideTemplates and SlidesJSON stay installed for prefabParts and recycle data. Ride feel at joints (overlap 1.5, inner-bend protrusion <= 0.09) is the same as today but should be ridden once in Studio with ProbeTransitionRideDuration.

**files:** ServerScriptService/Level 2 Systems/Level 2 Kit World Builder.ModuleScript.lua (makeExit, delete buildTube/slidePiece, cloneComponent SLIDE_PHYSICS for slide collision, dressHall ExitHall skylight position), ServerScriptService/Level 2 Systems/Level 2 Objective Controller.ModuleScript.lua (L467 Mouth transparency from manifest), tools/level2_poolrooms/objectives.py (tube_visual 16-gon + BoreSegment markers, SlideCol_Bore16 template, ExitCollar, ExitMouthTrim, remove mouth()/portal), tools/level2_poolrooms/prkit.py (12-number cf for colliders/markers), tools/level2_blender/import_kit.py (accept Poolrooms SlideCol templates), tools/tests/test_level2_kit_world_builder.py (HallWallGap center MinZ+42 / Y F+81.2 / width 15.92; check_tube rewrite; forbid Entry Support / Entry Collision Floor / Exit Portal / Lead Tile), tools/tests/test_level2_exit_bore.py (new), tools/level2_poolrooms/world_check.py (remove hard-coded 83.3/724.75 exit excusals), artifacts/level2-poolrooms-20261003/KIT_SPEC.md section 4 ('collision unchanged from the reviewed slide design' becomes 'regenerated from the reviewed path')

**refs:** ServerScriptService/Level 2 Systems/Level 2 Kit World Builder.ModuleScript.lua:914-993 makeExit (L918 deckZ=Center.Z-79.25, L919 anchor=(Bounds.MaxX-19,FloorY+83.3,deckZ), L921 start=(MaxX-14,...), L931 prefabParts loop incl. Entry Collision Floor, L932-937 Mouth=first MeshPart of ExitMouth, L938-940 fixed-lead ExitTubeVisual clones, L941-956 Lead Tile panels, L958-964 buildTube(skipVisual=true)+entry floor shift, L992 HallWallGap width 18.5); ServerScriptService/Level 2 Systems/Level 2 Kit World Builder.ModuleScript.lua:830-892 slidePiece/buildTube (L887-889 tub collisionPlacements -> Entry Support 1-3); ServerScriptService/Level 2 Systems/Level 2 Kit World Builder.ModuleScript.lua:344-379 cornerCoves (NE CornerCove_R24_H52 pivot on the corner; convex pillar r 24-27); ServerScriptService/Level 2 Systems/Level 2 Kit World Builder.ModuleScript.lua:288-342 wallShell exitGap rectangle; L1238 passes exit.HallWallGap; ServerScriptService/Level 2 Systems/Level 2 Kit World Builder.ModuleScript.lua:750-753 ExitSkylight at Center+(76,0,-69.25) (coupled to deckZ); ServerScriptService/Level 2 Systems/Level 2 Objective Controller.ModuleScript.lua:465-468 Mouth.Color=OPEN_COLOR, Mouth.Transparency=.35; tools/level2_poolrooms/objectives.py:324-331 mouth() annulus+sleeve; 351-430 tube_visual() 32-gon r=7.2 t=.32 from old path incl. fixed (-25,0,0) lead; 189-193 portal walls; assets/level2/blender-kit/export/slides.json ExitFlume_Tube (segments use SlideCol_Ring_r8, tub.collisionPlacements, prefabParts.ExitFlume Entry Collision Floor), same sha256 as G:/Blender/Level2_Pool/jobs/F/export/slides.json; tools/level2_blender/import_kit.py:128-139 (Poolrooms profile copies SlideCol templates only from the old export); tools/tests/test_level2_kit_world_builder.py:1510-1514 (HallWallGap expectations), 1528-1571 check_tube incl. L1566-1567 requiring tub collision; tools/level2_poolrooms/world_check.py:166-174 intended_exit and 409-414 exit_transition hard-code y=83.3, z=724.75 (seed 837834 only)

### Other problems seen
- Yaw-sign error across the whole kit, a likely big part of F12 ('walk through things'). prkit colliders use Roblox CFrame.Angles(0,yaw), so local X goes to (cos, -sin) in (x,z). But arc_boxes() (tools/level2_poolrooms/modules_arch.py:94-105) passes yaw=degrees(atan2(dz,dx)), which mirrors every arc collider about the X axis. Measured from the export manifest: CurveWall_S48 33/40 and S64 45/54 boxes are >15 deg off their chord (worst 50 deg); CurveWall_Q16/Q32 10/11 and 12/13 (worst 86-87 deg); Walkway_Bend16/32 9/11 and 10/12 (worst 80 deg); LightWell_R6/R10 collar blocks 16/20 and 24/28 (90 deg); Chamber_D 'Room Nook Wall' (modules_tunnel.py:466-469, yaw=degrees(t)). CornerCove 'Corner Block' and PoolSteps_Curved ground boxes are mis-rotated too, but the builder deletes them (cornerCoves L366-368, placeWalkways L459-461). The fix is a yaw_toward(dx,dz) = -degrees(atan2(dz,dx)) helper, plus an export test asserting every chain box's long axis is parallel to its chord.
- F1 confirmed with numbers: CornerCove_R24_H52 (and presumably every CornerCove_R*) installs as a CONVEX quarter pillar centred on the hall corner (all vertices 24..27 from the corner; G:/Roblox/_local/l2fix/f11f13/cove_probe.py). cornerCoves() places the pivot on the corner (Kit World Builder L350-355) with an export that assumes the opposite interior. In the exit hall it also swallows the north half of the HallWallGap.
- world_check.py hard-codes the exit for seed 837834 only: intended_exit (L166-174) and exit_transition (L409-414) test y=83.3 and z=724.75. For seeds 1 and 101 (exit at z 444.75 and -403.25) the exit is not excused, and for 837834 the collision report shows exitTransitionVoxels=0. The voxel flood never reached the deck, so the stair route was never validated by the audit.
- Exit platform 'Nose Ground' boxes (objectives.py:211-215) are 4 deep even where the visible nose is 1.8 deep; near x=+-28 they stick up to 0.95 beyond the visible edge. This is invisible collision.
- The platform support column lathe (objectives.py:184) is open at the bottom and starts at y=0 above a sloped pool floor at -0.8..-3.5. It floats with a visible open end, the same class of defect as the spiral core.
- ExitSkylight position is computed independently (dressHall L751: Center+(76,0,-69.25)) rather than from the exit platform frame. Any deckZ change must move it too. It is also an F14 candidate: 4 'Exit Overhead Tile' Parts frame a square bay around a 14-radius lathe ring.
- test_level2_kit_world_builder.py:1566-1567 asserts the ghost tub collision must exist ('lacks tub collision'), so the current test enforces the F13 bug.
- Image 9 / F8: the generic SpiralStairWell components (modules_arch.py ~L395-405) use 4x4 'Stair Ground' boxes with yaw=degrees(mid)+90 and 'arc_solid' wedges. Not analysed here, but the same ramp-vs-steps hitch and yaw convention apply.
- render_world.py:184 has an exit review shot with hard-coded offsets (x+25, y+83.3, z-10) that will be wrong after the exit moves.

### Notes
The analysis was read-only. Nothing in G:/Roblox/MongoTV was edited, no git commands were run, and Studio was not touched. Scratch files are under G:/Roblox/_local/l2fix/f11f13/: exit_views.py (Workbench renders of a dumped world's exit corner; renders/837834_visual_deck_e.png and 1_visual_deck_e.png reproduce owner images 12-13: green half-ring buried in the big curved NE corner pillar, portal frame and sky to the right), stair_profile.py (walks the union of dumped spiral colliders: holes and irregular 0.747/1.495 risers), cove_probe.py (shows the corner cove is convex, r 24-27 about the corner), ghost_collision.py (Blender BVH prototype of the 'invisible collision with nothing' check; seed 837834 gives 127 offenders: Spiral Ground 46, Outer Guard 45, Collision Floor 16 (dump gives those MeshParts only as boxes, so ignore), Nose Ground 15, Entry Support 3, Entry Collision Floor 1, Corner Seal 1 (enclosed, harmless)). Facts: OPEN_COLOR is (180,218,196). The old slides.json in assets and the one under G:/Blender/Level2_Pool/jobs/F are byte-identical (sha 6ddadcfc...), with pathPoints equal to collisionPoints. The ExitHall MaxX is always Bounds.MaxX-32 or -40 (validated), so 668 or 660. The slide controller starts a slide only on a floor with downhill >= ENTER_SLOPE, so the flat lead and the deleted tub are not needed for entry. The Exit Transition Test Suite depends only on the 'Collision Floor NNN' names, Size.Z, Position, SlideDirection and OneWayExit, all of which the MeshPart-per-segment design preserves. Uncertain: (a) the owner's exact camera, though the render matches closely; (b) whether a 16-island PreciseConvexDecomposition is faithful, which only the Studio raycast probe settles; (c) how strongly Humanoid floor-spring smoothing hides <=0.09-stud ramp facet bumps, which needs one Studio walk with root-Y logging. F11/F13 depend on F1 (corner cove direction) and touch F14 (exit skylight). Whoever implements must coordinate the deckZ move and the yaw helper with those owners.

## F12-A - Every oblique-yaw kit collider is mirrored (kit writes yaw with the wrong sign for Roblox)

**rootCause:** The kit's arc_boxes computes yaw = degrees(atan2(dz, dx)) from a chord (dx, dz) in Roblox x/z. Both the installer and the offline harness build the CFrame as CFrame.new(x,y,z)*CFrame.Angles(0,rad(yaw),0), and that maps local X to (cos θ, 0, -sin θ). So the box's long axis comes out reflected across X: it lies along (dx, -dz), and an arc box at chord angle α is rotated 2α away from the curve.

I checked this in the dump: Walkway_Bend16 'Deck Ground 1' has its X axis at (-0.065, 0, -0.998) while its chord runs (-0.065, 0, 0.998). The kit-only check agrees: for each affected component, the unbacked surface share drops to about 0 once the yaw is negated.

The other hand-written yaw sites have the same sign error. The only correct oblique site is the Chamber 'Room Curved Side' record, which already negates its yaw. The Blender preview hides the bug because colliders are never drawn there. The installed kit (assets/level2/poolrooms-kit/export/manifest.json) has byte-identical collider records to jobs A/B/C, so Studio has the same mirrored boxes.

**occurrences:** - Walkway_Bend16 (and the unused Bend32): placed by Kit World Builder lines 607 and 705 in CurvedChannel and VaultArcade halls. About 17% of reachable deck surface is unbacked, gaps up to 3.1 studs at the 45-degree part of the bend. Players sink into the outer and inner deck edges.
- CurveWall_Q16/S48 (and the unused Q32/S64): builder lines 629 and 684, CurvedChannel. 9-11% unbacked, gaps up to 1.05.
- ExitSpiral treads: ExitHall. The mirrored treads stick out as invisible colliders: about 600 stud² per seed, 25-28% of the treads' exposed surface. That falls to about 44 stud² once the yaw is fixed. This is the likely mechanical cause of F11's 'hakker' (stairs hitch).
- Exit Spiral Outer Guard: ExitHall.
- SpiralStairWell_H34/42/52 'Stair Ground': SpiralWell, builder line 713.
- Chamber_D 'Room Nook Wall': Chamber halls, 35-51% of exposed surface is invisible collision.
- LightWell_R6/R10 'Collar Block': at the ceiling, builder lines 748 and 756. Not reachable today; becomes reachable if the F8 stairs reach the ceiling.
- CornerCove 'Corner Block' and PoolSteps_Curved 'Step Ground': affected too, but the builder currently destroys them (see F12-B).
- Kit-only scan, unbacked share as installed vs with yaw negated:
  - CurveWall Q16 0.175→0.000, Q32 0.236→0, S48 0.27→0.005, S64 0.267→0.005
  - LightWell R10 0.265→0, R6 0.252→0.002
  - Walkway_Bend16 0.157→0, Bend32 0.177→0
  - ExitSpiral 0.020→0
  - SpiralStairWell 0.17→0.08-0.09 (the rest is the undersized tread, see F12-G)

**fixDesign:** Fix the sign once in the kit, then rebuild and reinstall it.

1. Add two helpers to prkit.py with a docstring stating the Roblox convention (CFrame.Angles(0,θ,0) maps local X to (cos θ, -sin θ)):
   - yaw_x_along(dx, dz) = math.degrees(math.atan2(-dz, dx))
   - yaw_x_radial(angle) = -math.degrees(angle)
2. arc_boxes line 100: yaw = kit.yaw_x_along(dx, dz).
3. modules_arch.py:404: yaw = -math.degrees(mid). The box is square, so the +90 offset does not matter.
4. modules_tunnel.py:469: yaw = -math.degrees(t).
5. objectives.py:262 and 272: yaw = -math.degrees(amid). Size X is already the radial axis for both.
6. Leave modules_tunnel.py:352 alone; it is already correct.

No change is needed in import_kit.py or the harness: they agree with each other and with Roblox.

Simulated on the three dumps, mirroring 1110-1285 colliders per seed removes Walkway_Bend16 and CurveWall from the unbacked ranking and removes the Exit Spiral Ground invisible collision.

**check:** Make G:/Roblox/_local/l2fix/collision/kit_check.py a test (tools/tests/test_level2_kit_collision.py, kit part).

For every exported component that has collider or collide-part records with a 4-element cf and an oblique yaw:
- Place the records with the importer formula.
- Measure the share of chunk-surface samples (2/stud², passable materials excluded) farther than 0.6 stud from the component's own colliders.
- Do it twice: as authored and with every oblique yaw negated.
- FAIL if as-authored is worse than negated by more than 0.02.

Also add a direct unit assertion: for each consecutive pair of arc_boxes records, the Roblox X axis must be parallel to the chord between their centres, |dot| ≥ 0.999.

Today 23 exported components fail the first rule (12 CurveWall variants, 3 SpiralStairWell, 2 LightWell, 2 Walkway_Bend; ExitSpiral, PoolSteps_Curved and the CornerCoves also fail on the mirrored-axis assertion), so the test catches this bug.

**risks:** Corrected boxes now occupy space the AI lanes never saw. CurveWall blocks and Walkway_Bend decks are where the art is, so the Pool Foam navigation tests (test_level2_kit_navigation.py, and the placement-oracle mutation in test_level2_kit_world_builder.py:1710) must be re-run.

The exit stair treads will change how climbing feels; F11 is redoing those stairs anyway and must pick up the sign fix.

Kit manifest hashes change, so the Studio kit needs reinstalling, the world dumps need regenerating, and every export receipt hash in the tests must be updated.

**files:** tools/level2_poolrooms/prkit.py, tools/level2_poolrooms/modules_arch.py, tools/level2_poolrooms/modules_tunnel.py, tools/level2_poolrooms/objectives.py, assets/level2/poolrooms-kit/export (rebuild) + reinstall via tools/level2_blender/import_kit.py --profile poolrooms

**refs:** tools/level2_poolrooms/modules_arch.py:94-104 arc_boxes (line 100: yaw = math.degrees(math.atan2(dz, dx))); tools/level2_poolrooms/modules_arch.py:116 CornerCove 'Corner Block'; tools/level2_poolrooms/modules_arch.py:265 CurveWall 'Wall Block'; tools/level2_poolrooms/modules_arch.py:293 path_deck 'Deck Ground' (Walkway_Bend16/32); tools/level2_poolrooms/modules_arch.py:338 PoolSteps_Curved 'Step N Ground'; tools/level2_poolrooms/modules_arch.py:382 LightWell 'Collar Block'; tools/level2_poolrooms/modules_arch.py:403-404 SpiralStairWell 'Stair Ground' yaw=degrees(mid)+90; tools/level2_poolrooms/modules_tunnel.py:467-469 Chamber_D 'Room Nook Wall' yaw=degrees(t); tools/level2_poolrooms/objectives.py:260-262 'Exit Spiral Ground' yaw=degrees(amid); tools/level2_poolrooms/objectives.py:270-272 'Exit Spiral Outer Guard' yaw=degrees(amid); tools/level2_poolrooms/modules_tunnel.py:350-352 'Room Curved Side' yaw=-sx*sz*degrees(t) (already correct); tools/level2_blender/import_kit.py:450-453 cf(); tools/tests/test_level2_kit_world_builder.py:291-297 recordCF

## F12-B - World Builder destroys correct kit colliders and replaces them with seals that leave holes or stick out invisibly

**rootCause:** Three builder paths delete the kit's collider records after cloning and add a crude stand-in.

(a) cornerCoves deletes every BasePart named 'Corner Block', which is every collider in CornerCove_*, and adds one 5×5 'Level 2 Corner Seal' at the room corner. The curved corner shell (radius R to R+3, 58 tall) therefore has no collision at all. With today's wrong-way placement (F1) the shell stands inside the room around the hall corner, so players walk straight through it into a pocket up to 24 studs deep. The CoveBaseCorner and CoveTopCorner pieces inside that pocket are reachable too.

(b) placeWalkways (PaddlingRoom) deletes every part with 'Ground' in its name from PoolSteps_Curved, which is all 48 'Step N Ground' colliders, and adds a single 12×0.7×12 threshold. Separately, PoolSteps_Curved is placed rotated 90 degrees wrong: its half-disc of steps (kit local +X) runs along the wall. In all 52 instances across the three seeds the steps stick 17 studs through the doorway into the corridor.

(c) makeSmall (Chamber) deletes the correctly authored 'Level 2 Room Curved Side' colliders and adds four 8×15×8 'Level 2 Room Corner Seal' boxes. Each fills the whole rounded corner quadrant inside the room, so it is an invisible wall.

**occurrences:** (a) All four corners of every built hall: Arrival, PumpHall, ColumnHall, VaultArcade, BigPool, CurvedChannel, SpiralWell, PaddlingRoom, ExitHall. That is 112-136 CornerCove placements per seed.
- Unbacked reachable area summed over the three seeds:
  - CornerCove_R24: 69.9k stud², 79% (55.5k of it with gaps over 1.5)
  - CornerCove_R16: 38.4k, 72%
  - CornerCove_R8: 5.9k, 64%
  - CoveBaseCorner_R24 45.7k, R16 24.3k, R8 3.2k
- R24 by hall type: PaddlingRoom 25.3k, ColumnHall 19.0k, SpiralWell 8.0k, ExitHall 5.5k, CurvedChannel 5.3k, BigPool 3.5k.
- Example: seed 837834, Hall 14 ColumnHall, point (15.1, 9.0, -209.0), more than 3 studs from any collider.

(b) Every PaddlingRoom doorway: 15-20 per seed. Visual steps are unbacked by up to 1.24, and 1305 of the 1356 stud² unbacked sits inside 'Corridor Open Wet', because the steps stick out of the room. Example: seed 837834 Hall 22 has its pivot at (96, 4, 167) and the step bbox reaches z = 189 while the hall's MaxZ is 172.

(c) Every Chamber, 21-22 per seed, × 4 corners. Room Corner Seal shows 4.1-4.9k stud² of exposed, reachable collider surface per seed with no visual within 1 stud (73-89% of their exposed surface). Example: seed 837834 Hall 5 at (368.7, 9.8, -316.0). The Arrival/ColumnHall 'Level 2 Corner Seal' is also exposed: 1.4-1.7k stud² per seed, because the cove pocket is open.

**fixDesign:** (a) Delete line 367. The existing Y-stretch loop (357-365) already scales every BasePart, colliders included, by CeilingClass/sourceHeight. Keep the Corner Blocks with the F12-A yaw fix.

The Corner Blocks only back the shell's inner face (r to r+0.25 to r+1.95). That is correct for the placement the kit was designed for: pivot at the fillet centre, room on the concave r<R side. F1 must move the pivot there (corner + R along both inward axes, yaw so the arc faces the corner). Once it does, delete the 'Level 2 Corner Seal' too (370-373); it would be fully buried.

If F1 instead keeps the shell convex toward the room, the blocks must move to radius R+1.5 with thickness 2.9 so the room face at R+3 is backed. That variant is what I simulated, because it matches today's placement.

(b) Delete lines 461-467. Place curved steps with cf*CFrame.Angles(0, math.pi/2, 0) so the half-disc (local +X) points into the room, matching PoolSteps_Straight12, which descends along local -Z. Keep the 48 'Step N Ground' colliders: they are 4×4 squares, so they work even before the yaw fix. Keep a 12×12 landing only if a check shows r<10 needs it, as an addition, not a replacement.

(c) Delete lines 804-811. The kit's 16 'Room Curved Side' boxes (1.45 radial × 3.0 tangential, already correctly yawed) close the rounded corners exactly.

Simulated on the three dumps, (a)+(b)+(c)+F12-A+F12-D cut the per-seed totals as follows:
- Solid unbacked: 155.9k→67.1k, 153.0k→68.1k, 147.7k→69.5k stud².
- Walk-through area with gaps over 1.5: 100.7k→38.1k, 99.5k→39.9k, 93.7k→40.2k.
- Invisible collision: 7.8k→1.8k, 8.0k→1.6k, 7.6k→1.6k.

Almost all of what remains is CoveBase64 (F12-C).

**check:** Add a collider-preservation test to tools/tests/test_level2_kit_world_builder.py. It is cheap and needs no geometry.
- Instrument placements the way dump_world.py's instrument() does.
- For every placement P of component C, every name in manifest[C].colliders, plus every parts record with collide:true, must appear among the BaseParts created under P, with CanCollide=true.
- Allowlist only the door-socket 'SocketPlug' parts that makeSmall removes on purpose (816-823), checked by attribute.
- This test would fail today on the CornerCove (0 of 16-24), PoolSteps_Curved (0 of 48) and Chamber (0 of 16 curved sides) placements.

Also add a placement-bounds assertion: every kit placement's chunk AABB must lie inside its hall rectangle, plus up to 2 studs of wall thickness, except components that are meant to bridge into a corridor (RoundTunnel/Pipe/collars). That catches the PoolSteps_Curved overhang of 17.0 studs.

Finally run the world audit (F12-PERM).

**risks:** Restored CornerCove blocks and step grounds add colliders that the AI placement oracle and Pool Foam spawn pockets have never seen. Run test_level2_kit_navigation.py and the spawn-pocket assertion (test_level2_kit_world_builder.py:968-978).

The curved-step rotation changes where the steps meet the 6.25-inset walkway strips in PaddlingRooms.

F1 has to land in the same change as (a), or the corner blocks must use the R+1.5 / 2.9 variant. Restoring the corner blocks without fixing the placement would leave a 1.05-stud standoff behind the room face.

**files:** ServerScriptService/Level 2 Systems/Level 2 Kit World Builder.ModuleScript.lua, tools/level2_poolrooms/modules_arch.py (only if F1 keeps the convex corner shell: Corner Block radius/thickness)

**refs:** ServerScriptService/Level 2 Systems/Level 2 Kit World Builder.ModuleScript.lua:344-378 cornerCoves (367 destroys 'Corner Block'; 370-373 adds 'Level 2 Corner Seal'); ServerScriptService/Level 2 Systems/Level 2 Kit World Builder.ModuleScript.lua:456-470 placeWalkways (460 cf has no extra yaw for curved; 461-464 destroys 'Ground'; 465-467 adds 'Paddling Threshold Ground'); ServerScriptService/Level 2 Systems/Level 2 Kit World Builder.ModuleScript.lua:798-812 makeSmall (804-806 destroys 'Room Curved Side'; 807-811 adds 'Room Corner Seal' 8x15x8); tools/level2_poolrooms/modules_arch.py:107-119 corner_cove (Corner Blocks at radius+1.1, thickness 1.7; intended pivot = fillet centre, per TangentX/TangentZ markers); tools/level2_poolrooms/modules_arch.py:320-341 steps(curved) (half-disc at angles -pi/2..pi/2 = local +X); tools/level2_poolrooms/modules_tunnel.py:327-352 chamber_corner

## F12-C - Wall-foot and ceiling coves (CoveBase*/CoveBaseCorner*/CoveTop*) ship no collider at all

**rootCause:** The kit's cove() and cove_corner() emit only a mesh, with no collider records. The comment assumes the back is 'hidden inside the two flat Parts', but the cove solid stands in front of the wall slab and above the floor. coveRun and cornerCoves clone them as non-colliding MeshParts.

Today's cove is a solid convex quarter-round: 3.3 studs deep and 3 high above FloorY, with a 4-stud skirt (kit profile y -4..3, z 0..3.3, arc centred at y=0, z=3). coveRun also adds Angles(0, π, 0), which turns the flat back toward the room; this is owner image 1, and it belongs to F1.

The result is a 3.3-stud lump along every wall foot that players walk through. Over basin floors the lump hangs at deck level with nothing under it.

**occurrences:** - CoveBase64: 219-231 runs per seed in every hall type, on every wall run between openings. This is the largest single item. 60% of its reachable surface is unbacked: 84-85k stud² per seed, with 51-52k of it at gaps over 1.5 (gap up to 3.3 at the room-side face).
- CoveBase64 unbacked area by hall type, summed over the three seeds: ColumnHall 86.4k, PaddlingRoom 38.1k, CurvedChannel 31.2k, VaultArcade 24.2k, SpiralWell 22.6k, BigPool 16.3k, PumpHall 15.4k, ExitHall 13.1k (Arrival also).
- Examples: seed 837834 Hall 3 VaultArcade (-207.0, -1.4, -405.6); seed 1 Hall 5 CurvedChannel (33.0, 2.5, -401.5); seed 101 Hall 9 SpiralWell (169.0, 2.6, -339.8).
- CoveBaseCorner_R8/16/24: see F12-B. Today they sit inside the corner-shell pocket.
- CoveTopCorner_R24: 56 stud² reachable from SpiralWell stairs near the ceiling (F8).

**fixDesign:** This depends on F1, which must first turn the profile into a concave fillet of R=3 against the wall and the floor. Then add colliders in the kit:

1. cove(): one Block collider 'Cove Fill' of 0.85 × 0.85 cross-section in the wall/floor corner, length length+1. For CoveBase: centre (0, 0.425, 3.3-0.425) with WallSide +Z. coveRun's existing X-scale loop stretches it with the run.
   - Measured for R=3: the largest gap from the arc to the union of wall, floor and box is 0.485 (under 0.6), with no protrusion.
   - Three boxes (0.85², 0.5×1.5, 1.5×0.5) bring it down to 0.27.
   - A 45-degree wedge with 1.75 legs gives 0.23, but import_kit.py has no WedgePart support, so prefer boxes.
2. If F1 keeps the 4-stud skirt and the cove can hang over a basin floor (FloorY above the slab), also add a skirt box: 3.0 deep × 4.0 tall, from the wall face to the fillet's floor tangent, y from -4 to 0. Better still, have F1/F5 seat the cove on the real floor.
3. cove_corner(): the same 0.85² fill as a ring, using the fixed arc_boxes on the room side of the corner surface (radius R-0.425 in the corrected placement, thickness 0.85, vertical (0.425, 0.85)).
4. CoveTop*: the same mirrored fill. It is cheap even though the ceiling is mostly unreachable.

If F1 decided to keep the convex bullnose, the colliders would instead be staircase boxes inscribed under the arc (y 0..1 z 0.17..3.3; y 1..2 z 0.76..3.3; y 2..2.8 z 1.5..3.3) plus the skirt box. Either way, the rule is that the kit ships colliders for the visible solid.

**check:** World audit (F12-PERM): the per-label thresholds apply to CoveBase*/CoveBaseCorner*/CoveTop* like every other solid.

The kit-level coverage test applies to cove pieces only on the room-facing side: tag the kit attrs with 'ExposedSide' and sample only faces whose normal points to that side. Required: unbacked share ≤ 0.02 and max gap ≤ 0.6.

**risks:** A collider that ends up on the room side of a wrongly oriented cove becomes an invisible kerb, so it must land in the same change as F1's orientation fix. The world audit's invisible-collision pass will flag a mismatch.

Cove colliders make wall feet 0.85 studs 'thicker'. The Pool Foam lanes keep a 6+ stud margin from walls (clearPocket margin 6), so I don't expect lane impact, but the navigation test will confirm.

**files:** tools/level2_poolrooms/modules_arch.py (cove, cove_corner), ServerScriptService/Level 2 Systems/Level 2 Kit World Builder.ModuleScript.lua (coveRun line 274 orientation per F1; its X-scale loop already handles colliders)

**refs:** tools/level2_poolrooms/modules_arch.py:122-141 cove() (no collider; WallSide='+Z'); tools/level2_poolrooms/modules_arch.py:144-160+ cove_corner() (no collider); ServerScriptService/Level 2 Systems/Level 2 Kit World Builder.ModuleScript.lua:268-283 coveRun (274 extra CFrame.Angles(0,math.pi,0); 277-283 stretches every BasePart along X); ServerScriptService/Level 2 Systems/Level 2 Kit World Builder.ModuleScript.lua:286-342 wallShell calls coveRun per wall run; ServerScriptService/Level 2 Systems/Level 2 Kit World Builder.ModuleScript.lua:376-377 cornerCoves clones CoveTopCorner/CoveBaseCorner

## F12-D - Walkway_End collider is a 4×6 box under a radius-5 half-disc deck, and the end pair is placed facing the wrong way

**rootCause:** The kit authors 'End Ground' as a box of size (4, 0.8, 6) at (2, 0.05, 0). The visible deck is a half-disc of radius 5: x 0..5, z ±5. The builder places the two ends at island ∓ 5 with yaw 0/π, so both round tips point into the D10 column at the island centre and the flat cut edges face the water.

**occurrences:** BigPool halls with an island, 4-6 ends per seed. 27% of the reachable end surface is unbacked, gaps up to 2.0. Example: seed 837834 Hall 15 at (323.1, 4.5, -197.6) and (332.2, 3.6, -197.8).

**fixDesign:** 1. Swap the yaws at 547-548 so the round tips point away from the column: the first end at island-5 gets Angles(0, π, 0), the second at island+5 gets yaw 0. Or drop the pair if the owner did not want a 'pier'; that is a design question.
2. Replace the 'End Ground' box with five ground boxes inscribed in the half-disc. Each box spans x from x0 to x1 and has half-width √(25 - x1²):
   - x 0..1.6: 3.2 × 0.8 × 9.47
   - x 1.6..2.6: 1.0 × 0.8 × 8.54
   - x 2.6..3.4: 0.8 × 0.8 × 7.33
   - x 3.4..4.1: 0.7 × 0.8 × 5.72
   - x 4.1..4.6: 0.5 × 0.8 × 3.92
   All sit at y 0.05 with ground=true, and the largest residual gap is about 0.5.

Do not use a full D10 cylinder: simulated, its back half is 53% invisible collision.

**check:** Kit coverage test: Walkway_End unbacked share ≤ 0.02 (today 0.284). World audit per-label thresholds. Invisible-collision share ≤ 5% for 'End Ground'.

**risks:** The island ends are walkable; changing their orientation moves where a player can stand around the island column, so re-run the Pool Foam navigation test.

**files:** tools/level2_poolrooms/modules_arch.py, ServerScriptService/Level 2 Systems/Level 2 Kit World Builder.ModuleScript.lua

**refs:** tools/level2_poolrooms/modules_arch.py:311-317 walkway('End'); ServerScriptService/Level 2 Systems/Level 2 Kit World Builder.ModuleScript.lua:546-548 Walkway_End pair

## F12-E - Round-tunnel collars: the lower spandrels (between the bore circle and the square wall opening, at floor level) have no collider

**rootCause:** collar() closes only the upper spandrels with invisible 'Corner Fill' boxes (12.7..17 × 24..top). The comment at line 178 says 'the sill above closes the lower pair', but the threshold sill's top is the floor chord at floor_y. The bore circle (cy=13, r=17) only reaches the 34-wide opening's sides at y=13.

So at each mouth the tiled collar face over |x| ≈ 11..17, y 0..~9 has nothing behind it, and players walk about 1.5 studs into the tunnel mouth's lower corners.

**occurrences:** Every RoundTunnel variant (Dry/Wet/Stair4/Stair8 × 64/72/80), at both mouths, in every hall type that has a large-corridor door, and in the corridor ends.
- Summed over the three seeds:
  - RoundTunnel_Wet: 2.2k stud² (ColumnHall 620, PaddlingRoom 602, CurvedChannel 291, VaultArcade 212, SpiralWell 134, PumpHall 109, BigPool 105, Corridor Open Wet 112)
  - Stair4: 0.9k
  - Stair8: 0.6k
  - Dry: 0.13k
- Gaps reach 1.5 in the world and 2.2 kit-only.
- Example: seed 837834 RoundTunnel_Wet_72 mouths at (-407.9, -2.9, -226.2), Hall 12 ColumnHall, and (-439.4, -1.2, -301.8), Hall 2 PumpHall.
- Pipe_* (r≈6) mouths: gaps of 0.7 or less. Not a blocker.

**fixDesign:** In collar(), add a 'Lower Corner Fill ±1' set for radius > 10, built like the upper fills: Transparency 1, collide, depth 1.75, centred at z ± 0.875.

Use stepped boxes inscribed below the bore circle, each spanning x0..halfwidth (=17) and floor_y..y1, where y1 = cy - √(r² - x0²):
- x0 = 12.0 → y1 = 0.96
- x0 = 14.0 → y1 = 3.36
- x0 = 15.5 → y1 = 6.02
- x0 = 16.5 → y1 = 8.90

No box crosses the circle, so the bore stays clear, and the residual gap is about 0.5 or less.

Also correct the comment at line 178. For Stair variants the 'To' mouth sits at floor_y = rise, and collar() already receives that, so compute from floor_y.

**check:** Kit coverage test per RoundTunnel component: unbacked ≤ 0.005 (today 0.016-0.029) and max gap ≤ 0.6 (today 2.2). The existing in-kit validator at modules_tunnel.py:518 ('fills') should assert the lower fills too. World audit per-label thresholds.

**risks:** The fills must stay outside the corridor's AI clear width (clearWidth = 2·halfwidth at floor). They sit at |x| ≥ 12, which the round bore already blocks at those heights. Run the tunnel navigation test. Wet tunnels' terrain water is unaffected.

**files:** tools/level2_poolrooms/modules_tunnel.py

**refs:** tools/level2_poolrooms/modules_tunnel.py:170-189 collar (173-178 threshold; 180-187 Corner Fill upper only; comment 178); tools/level2_poolrooms/modules_tunnel.py:195-223 side_collision (facets only follow the circle)

## F12-F - Chamber wall-foot coves float 1.2 studs above the submerged floor, leaving an open slot under them

**rootCause:** straight_cove() builds the lower fillet from y=1.2 at the wall down to y=0 (R=1.2, concave and correct in shape). But the chamber's 'Room Aqua Floor' top is at -1.2. Only the north wall gets the 'Room Dry Threshold', whose top is at 0. On the E/S/W walls the cove's bottom edge hangs 1.2 above the floor, so players clip under and into it.

**occurrences:** - Every Chamber (Chamber_A/B/C/D, 21-22 per seed), along the walls without a threshold.
- Kit-only: unbacked share 0.7-1.1%, max gap 1.2.
- In the world, summed over 3 seeds: Chamber_C 342, Chamber_B 255, Chamber_D 208, Chamber_A 102 stud².
- Example: seed 837834 Hall 5 Chamber at (342.6, 4.1, -361.6).
- Probably the chamber_corner lower cove too (same y).

**fixDesign:** Seat the lower fillet on the actual floor of each wall: base y = -1.2 where there is no dry threshold, 0 where there is. That is a visual fix too (F4/F5). A seated R=1.2 concave fillet has a largest gap of 0.35 against wall plus floor, so it needs no collider.

If seating is rejected, add a collider 'Room Cove Fill' of (run length, 2.4, 0.5) against the wall, y from -1.2 to 1.2.

**check:** Kit coverage test for Chamber_*: unbacked ≤ 0.005 and max gap ≤ 0.6. World audit.

**risks:** Low. It is purely kit geometry, and the chambers' terrain water is unaffected.

**files:** tools/level2_poolrooms/modules_tunnel.py

**refs:** tools/level2_poolrooms/modules_tunnel.py:371-393 straight_cove; tools/level2_poolrooms/modules_tunnel.py:403-404 Aqua Floor (top -1.2) and Dry Threshold (north only); tools/level2_poolrooms/modules_tunnel.py:449-450 cove calls

## F12-G - Objective and exit props: pump elbows and pipes, exit platform lip, exit stair treads and guard, exit lead panels are non-colliding or under-covered

**rootCause:** - PumpStation has a single 4.4×4.4×3.4 body collider. The Iron mesh spans x ±3.98, y 0.15..6.76, z -2.33..1.65: two pipe elbows down to the floor, a right-hand rod and a gauge stem. The code comments 'All their visible pieces are static noncolliding mesh', and the Intake Pipe parts are collide=False.
- The ExitPlatform bullnose lip (y 74..74.85) has no collider.
- The SpiralStairWell 'Stair Ground' boxes are 4×4 at r=8.5, so they cover r 6.5..10.5 while the treads are drawn from r 5 to 11.3.
- The Exit Spiral Outer Guard (2.1 thick at r=15) stands up to 1 stud inside the visible 0-thickness cheek at r=15.2, which reads as an invisible railing.
- The builder's 'Exit Lead Tile' panels are explicitly CanCollide=false.

**occurrences:** - PumpStation: 3 per seed (PumpHall, PaddlingRoom). 16% of its reachable surface is unbacked, gaps up to 1.77. Example: seed 1 Hall 50 at (80.0, 3.9, 799.5). Plus 'Pump Intake Pipe' at 32% and 'Pressure Gauge Face' at 57-76%.
- SpiralStairWell_H42/H52: every SpiralWell hall. Unbacked share is 11-13% after the yaw fix (13% before), gaps up to 1.3-1.5. Example: seed 837834 Hall 32 at (640.6, 7.4, 279.1).
- ExitPlatform lip: 49 stud² summed over 3 seeds, gap 0.86.
- Exit Spiral Outer Guard: 15-18% invisible after the yaw fix.
- Exit Lead Tile Left/Right: 59-60% unbacked, gap 2.2. Example: seed 837834 at (654.8, 76.1, 732.5).

**fixDesign:** Pump, extra kit colliders, all inside the 9.2×7.2 plinth footprint:
- per side: 'Pump Elbow Collider' (2.7, 0.9, 0.9) @ (±2.35, 2.5, -0.35)
- per side: 'Pump Drop Collider' (1.5, 2.3, 1.5) @ (±3.25, 1.15, -0.35)
- 'Pump Rod Collider H' (2.7, 1.0, 1.0) @ (2.65, 4.2, -0.5)
- 'Pump Rod Collider V' (1.0, 4.2, 1.0) @ (3.5, 2.6, -0.5)
- 'Pump Gauge Collider' (1.5, 1.6, 0.6) @ (-1.4, 5.9, 0.0)
Keep the intake pipe Parts as non-colliding audio anchors. Leave the animated PumpLever and Needle passable (gap ≤ 1.0); allowlist them.

ExitPlatform: 24 tangent boxes along the lip curve, z = 18 + 5√(1 - (x/30)²), each 0.6 thick × 0.85 tall, y 74..74.85, using the fixed arc_boxes.

SpiralStairWell 'Stair Ground': size (6.5 radial, 0.8, 4.1 tangential) centred at r=8.15, yaw = -degrees(mid). F8 is redesigning these stairs and must keep that coverage.

Exit Spiral Outer Guard: centre r = 15.5, radial thickness 0.6, so the room face sits at 15.2 = the cheek. Better, as F11 asks, give the cheek a real thickness and back it 1:1.

Exit Lead Tiles: F13's tube rework. Either give the panels collision or make them unreachable.

**check:** World audit per-label thresholds (F12-PERM). Kit coverage test thresholds:
- PumpStation ≤ 0.02 (today 0.13)
- ExitPlatform ≤ 0.005
- SpiralStairWell ≤ 0.02 (today 0.16-0.17)
- ExitSpiral ≤ 0.005
The invisible-collision check covers the Outer Guard.

**risks:** Pump colliders near the lever must not block the ProximityPrompt. The prompt is on the lever; RequiresLineOfSight should be verified in a play test, and the colliders stay behind the lever plane (z < 1.6).

F8/F11/F13 are redesigning the stairs and exit tube, so their new geometry has to pass the same audit.

**files:** tools/level2_poolrooms/objectives.py, tools/level2_poolrooms/modules_arch.py, ServerScriptService/Level 2 Systems/Level 2 Kit World Builder.ModuleScript.lua (Exit Lead Tile, coordinated with F13)

**refs:** tools/level2_poolrooms/objectives.py:81-110 pump (83 Body Collider; 99-110 elbows/rods; 106-108 Intake Pipe collide=False; 112-118 gauge); tools/level2_poolrooms/objectives.py:216-224 ExitPlatform lip (mesh only); tools/level2_poolrooms/objectives.py:228-275 ExitSpiral (Ground 258-262; Outer Guard 264-272; cheek r=15.2 at 266-269); tools/level2_poolrooms/modules_arch.py:394-404 SpiralStairWell treads; ServerScriptService/Level 2 Systems/Level 2 Kit World Builder.ModuleScript.lua:944-957 Exit Lead Tile panels (955 CanCollide=false)

## F12-PERM - Permanent pass/fail collision-coverage audit over the builder's real output (all seeds) and over the kit export

**rootCause:** Nothing in the pipeline ever compares visible geometry against collision. The world builder test checks lanes, spawn pockets and ground flags, but it never asks whether a visible solid has anything solid behind it. That is how the mirrored yaws, the destroyed colliders and the collider-less coves all shipped.

**occurrences:** Applies to every hall Type (Arrival, PumpHall, ColumnHall, VaultArcade, BigPool, CurvedChannel, SpiralWell, PaddlingRoom, Chamber, ExitHall), every corridor Kind/Variant, and every kit component.

**fixDesign:** Promote audit2.py to tools/level2_poolrooms/collision_audit.py (pure numpy + scipy, no Blender needed) and add tools/tests/test_level2_kit_collision.py with three parts.

(A) Kit test, about 10 s, no builder: kit_check.py logic.
- Yaw-sign rule from F12-A.
- For components flagged self-contained (Column*, CurveWall*, Walkway*, PoolSteps*, VaultPier, LightWell*, SpiralStairWell*, ExitSpiral, ExitPlatform, PumpStation, Chamber_*, RoundTunnel*, Pipe*, CornerCove* and Cove* on their ExposedSide faces): unbacked share at TOL 0.6 must be ≤ 0.02 (≤ 0.005 for tunnels/pipes/chambers) and max gap ≤ 1.0.
- Components with no colliders must be explicitly listed as passable or unreachable (LightRound, DrainHole, ExitTubeVisual*, VaultBay32_* above head height, ExitSkylight, ExitMouth, WallVoid's Void material, Porthole only if unplaced), so a new solid component cannot ship without colliders by accident.

(B) Builder preservation test, cheap: the per-placement collider-preservation and placement-bounds assertions from F12-B, run on the existing 10-seed harness build.

(C) World audit: per seed, on the harness output for the same 10 seeds; the three dumps G:/Blender/Level2_Poolrooms/worlds/world_{837834,1,101}.json are the fixed regression set.
- Sample every visible (Transparency < 0.98) non-colliding chunk MeshPart and visible CanCollide=false Part at 2 samples/stud².
- 'Backed' means the distance to the union of CanCollide parts is ≤ 0.6 (grid padded to 3 studs so gaps up to 3 are exact).
- 'Reachable' means touched by the body of a player flooded from ElevatorSpawn with pressure doors open: 5-tall column, 3×3 footprint above the 2-stud step-up, steps ±3 voxels, drops, ±2-voxel body dilation.
- Classes: PASSABLE = materials LightWarm/Void/Neon/Glass/Water plus components LightRound, DrainHole, SunSlit, ExitTubeVisual*, plus parts Overhead Tile, Pump Status Lamp, Pressure Door Stripe, Pump Pressure Gauge Needle, Pump Lever Status Ring, Pump Lever grip. Everything else is MUST-COLLIDE.
- PASS criteria per seed:
  1. For every MUST-COLLIDE label (component or builder part name): unbacked reachable share ≤ 0.02.
  2. Reachable area with gap > 1.0 ≤ 1 stud² per label.
  3. Σ unbacked / Σ reachable over all MUST-COLLIDE ≤ 0.005.
  4. Invisible collision: exposed (offset 0.35 off the face, outside all colliders), reachable with the tight 2×2×5 body, and no visual surface within 1.0. Per collider label share ≤ 0.05 and area ≤ 50 stud²; seed total ≤ 300 stud². The only allowlisted labels are slide-template hulls (F13 checks them with its own ride test) and the roof colliders.
  5. Flush-decal rule for passables: DrainHole plates within 0.3 of the floor collider, and LightRound within 0.3 of the ceiling.

Today's baseline fails every criterion. Per seed:
- Solid unbacked: 155.9k of 461.5k (33.8%), 153.0k of 471.0k, 147.7k of 454.7k stud².
- Gaps over 1.5: 100.7k / 99.5k / 93.7k.
- Invisible collision: 7.8k / 8.0k / 7.6k.
The simulated F12-A/B/D fixes bring the non-cove residual to 2.4-3.7k and invisible collision to 1.6-1.8k. The rest needs F12-C/E/F/G.

Runtime: about 25-30 s and about 2 GB per seed (the voxel grid is 121×1416×1416), so 10 seeds take about 5 min. Offer --quick (the 3 dump seeds) for the default test run and --all for pre-publish. Print a ranked table (label, unbacked/reachable, by hall Type, three worst world positions) on failure, as audit2.py already does.

**check:** This item is the check. To prove it works, it must:
1. Fail on today's HEAD build (confirmed: all five criteria fail on all three dumps).
2. Pass after the F12-A..G changes on the 10 harness seeds and the 3 dumps.
3. Fail again on two mutations: (i) revert arc_boxes to +atan2; (ii) re-add the 'Corner Block' Destroy at builder line 367.

**risks:** - The voxel flood with ±2 dilation slightly over-reports what is reachable behind thin visual skins. The visual pass errs toward flagging, which is the safe side. The invisible pass uses a tighter body; without it, tunnel facet outer faces showed a false 5%.
- The dump's slide-template hulls are bounding boxes, so the exit flume cannot be judged here; F13 needs its own ride test.
- Cylinder colliders in the fake engine are logical-Y, so the audit inherits world_check's convention. Verify one Column and the SpiralStairWell core in Studio once.
- Memory: run at most one seed at a time.

**files:** tools/level2_poolrooms/collision_audit.py (new, from G:/Roblox/_local/l2fix/collision/audit2.py + collision_audit.py + kit_check.py, minus the --fix simulation), tools/tests/test_level2_kit_collision.py (new), tools/tests/test_level2_kit_world_builder.py (collider-preservation + placement-bounds assertions; expose the instrumented build dump_world.py uses), tools/level2_poolrooms/build.py (call the kit part after export so a bad kit never gets uploaded)

**refs:** G:/Roblox/_local/l2fix/collision/audit2.py (prototype: sampling, classification, reach flood, invisible-collision pass, --fix simulation); G:/Roblox/_local/l2fix/collision/collision_audit.py (Colliders grid distance; reach_mask flood from ElevatorSpawn with doors open); G:/Roblox/_local/l2fix/collision/kit_check.py (kit-only coverage + yaw-negation detector); tools/level2_poolrooms/dump_world.py (instrumented harness build) and world_check.py / render_world.py helpers; tools/tests/test_level2_kit_world_builder.py (10-seed fake-engine harness)

### Other problems seen
- DrainHole plates are placed flat at FloorY-0.7 (World Builder line 777) while basin floors slope from 0.8 to 3.5 deep. About 80% of the 99-104 drains per seed float 0.5-1.05 studs above the actual floor: on seed 837834, 20 of 100 sit flush and the rest are 0.55-1.05 up. They should sit on the slope, with the floor's height and tilt sampled at the drain's x/z. This is F4 ('half-finished').
- PoolSteps_Curved is oriented 90 degrees wrong in every PaddlingRoom doorway (builder line 460 has no extra yaw for the curved variant). Its half-disc of steps runs along the wall and sticks 17.0 studs through the doorway into the corridor. Rings 2 and 3 (tops at -1.2 and -1.8) also sit below the 0.8-deep paddling floor and are buried.
- The Walkway_End pair (builder lines 547-548) points both round tips into the D10 island column, with the flat cut edges facing the water. The yaws look swapped.
- Exit Lead Tile Left/Right/Floor/Top (builder lines 944-957) are visible, CanCollide=false panels on the exit platform, reachable at gaps up to 2.2. They belong to F13's 'tube half in the wall / big opening' cluster.
- The exit spiral's visible outer cheek is a 0-thickness quad at r=15.2 (objectives.py:266-269), while the guard collider is 2.1 thick at r=15. This is the 'paper-thin railing that floats' in F11. The mirrored tread yaw (F12-A) is a mechanical cause of the reported hitching on the same stairs.
- Chamber_D's 'Room Nook Wall' is a single 0-thickness curved skin (modules_tunnel.py:460-466) with 1.2-thick colliders. Even with the yaw fixed, 33-51% of the collider's exposed surface is about 1 stud from the visual. Give the nook an arc_solid of (7, 8.2) and centre the boxes at r=7.6 with thickness 1.2.
- CornerCove, CoveBaseCorner and CoveTopCorner geometry is authored for a pivot at the fillet centre: the TangentX/TangentZ markers sit at distance R from the pivot. cornerCoves (builder 354-356) puts the pivot at the hall corner with yaw π, which makes the corner shell convex toward the room. CoveBaseCorner (r R..R+3.3) is authored on the far side of the shell even in the intended placement. All of this is root cause for F1.
- The kit cove profile (modules_arch.py:126-132, WallSide '+Z') is a convex quarter-round (arc centre at y=0, z=3). coveRun adds CFrame.Angles(0, π, 0) at line 274, which turns its flat back toward the room; this is owner image 1. Both are F1.
- LightWell_R6/R10 'Collar Block' colliders carry the same mirrored yaw. They are at ceiling height and unreachable today, but will matter if the F8 stair wells reach the ceiling again.
- Porthole_R6/R10/R15 have kit-only gaps of 1.6 to over 3 (unbacked share 6.5-17.5%). They are not placed by the current builder; if they ever are, they fail the kit test as designed.
- The remaining 'Level 2 Corner Seal' exposure (about 100 stud² per seed after the simulated fix, e.g. seed 837834 Hall 12 ColumnHall at (-487.0, 0.4, -79.5)) means some corner pockets stay reachable, probably where a door opening sits within R of a corner. The world audit will show it again after F1.

### Notes
I made no edits inside G:/Roblox/MongoTV, ran no git and touched no Studio/MCP. Scratch work is in G:/Roblox/_local/l2fix/collision/:
- audit2.py: the final audit. `python -B audit2.py [--fix] 837834 1 101`.
- kit_check.py: kit-only coverage plus the yaw-negation detector.
- detail2.py: per-placement clusters in the pivot frame.
- Results: audit2_<seed>.json and audit2_<seed>_fix.json, which hold the ranked rows, a by-hall-Type breakdown, world examples and the invisible-collision list. Run logs are run5_base.txt and run5_fix.txt.
- collision_audit.py, detail.py and the other small diag scripts came from an earlier attempt of this cluster and are reused as a library.

Method:
- The audit is pure numpy/scipy over the exact dumps. It uses render_world.load_kit_chunks / mesh_triangles_world and world_check.part_triangles / voxel_grid / volume_masks.
- Each world's kit export hashes are verified against its dump receipts. The installed kit manifest (assets/level2/poolrooms-kit/export) has identical collider and part records to jobs A/B/C.
- The installer and the harness use the same yaw formula (import_kit.py:450-453 matches test_level2_kit_world_builder.py:291-297), so the dumps represent Studio's collision.
- Blender was not needed: no BVH or rendering was required.

Uncertainties and how to settle them:
1. Why the builder author destroyed the Corner Blocks, Curved Sides and Step Grounds is not recorded. Most likely the mirrored yaw made them visibly wrong or broke lanes. Settle it by re-running test_level2_kit_navigation.py with the colliders restored and the yaw fixed.
2. I have not proven the fix for the coves, collars, chamber cove, pump, spiral treads and exit lip in a simulation; those are numeric designs. The audit must be re-run after implementation.
3. Exit flume collision (slide-template) is dumped as bounding boxes and was excluded. That needs F13's ride test.
4. Reachability uses a voxel flood with a generous body dilation. The visual pass may slightly over-count reachable area; the invisible-collision pass uses a tight body and exposed-face offset to avoid that bias.
5. Cylinder axis in the fake engine is logical-Y; one Studio spot check of a Column and the SpiralStairWell core would confirm it.

Headline: three root causes explain more than 95% of 'walking through things'. In order: coves ship no collider (F12-C, about 85k stud² per seed of walk-into surface); the builder destroys kit colliders, so the corner shells are fully passable (F12-B); and the kit writes every oblique collider yaw mirrored (F12-A), which also hits the exit stairs and probably causes F11's hitching.
