# Level 2 Poolrooms - fix spec for the owner's second list (binding for every implementation agent)

Inputs: `FEEDBACK.md` (owner's words + images 1-14), `ANALYSIS.md` (9 analysts: root causes, exact designs, checks).
Every design referenced below is in ANALYSIS.md under its heading; implement it as written unless this spec says
otherwise. Where two analysts overlap, the decision here wins.

## Global rules (all work packages)
- G1 One tile look: every tiled surface (Part or MeshPart, kit or builder) = SmoothPlastic + `PR Tile` (above water)
  or `PR Tile Aqua` (submerged floors), Color (241,237,220), Reflectance 0.06. `TileShade` and `Worn` are deleted
  from the palette (a use must fail the kit build). Non-tile: `PR Iron`/Steel (pump), Neon (lights), Void (dark
  openings), new `Dial` (pump gauge face). [ANALYSIS F6, F3 (materials)]
- G2 Visible side and shading: every open shell authors its visible side (prkit `facing=` hint), finish() flips
  faces to it and marks edges > 45 deg sharp; UVs per vertex where the analyst says (arc shells, chamber corners,
  nook, ribs, collars). Meshes stay DoubleSided in Roblox. [F3+F6 (normals), F3+F6 (uv)]
- G3 No tiled mesh is stretched outside [0.875, 1.125] on any axis at runtime: compose runs from 64/32/16/8/4
  pieces; export the sizes that are needed instead of scaling (CornerCove H96, swerve pieces, no scaled spirals).
  [F6 (stretch), F4-E]
- G4 Floor-standing solids start at y = -4 (columns, piers, curve/swerve walls, spiral core and stair, decks, steps,
  platform supports), the same rule as walls. Nothing floats above a basin. [F4-B, F4-verticals, F4-walkways]
- G5 Collider yaw: Roblox CFrame.Angles(0,t,0) maps local X to (cos t, -sin t) in (x,z). prkit gets
  `yaw_x_along(dx,dz) = degrees(atan2(-dz,dx))` and `yaw_x_radial(angle) = -degrees(angle)` (docstring states the
  convention), and collider/marker accept a full 3x3 frame (written as a 12-number cf). Fix every oblique yaw site
  listed in ANALYSIS F12-A (arc_boxes, modules_arch spiral 404, modules_tunnel 469, objectives 262/272; leave the
  already-correct modules_tunnel 352). A kit test asserts every chained collider's long axis is parallel to its
  chord. [F12-A, F11]
- G6 Every visible solid a player can touch has collision behind it (coves, corner coves, decks, curbs, steps,
  columns, piers, partitions/swerve walls, collars, ribs, pump, platform, stairs, parapet, tube). No invisible
  collision without a visible surface within tolerance (ghost collision), except deliberate roof/sky caps, water
  floors under water, and slide bore pieces that coincide with the visual tube.
- G7 Nothing hangs below the ceiling plane except intended relief (vault bays on piers, LightRound flush trim);
  every ceiling opening is a flush plate whose outer edge equals the ceiling cut and whose inner edge is the circle,
  with an invisible colliding Sky Cap (CanQuery false) at the roof band. [F7+F14, F7, F14]
- G8 Instance budget: world descendants <= 12,349 per round (the builder asserts it; the 50-seed test measured
  10,566..12,281). The earlier 9,000 could not hold the composed coves, ring decks, swerve pieces and stair ramps;
  on 2026-10-04 the owner chose "cut down without losing anything" with quality before the number (target
  ~11-12k). Lights <= 96, shadow casters <= 6.
- G9 Offline harness must represent Roblox: the fake kit fixture applies import_kit's nativeCylinder (vertical
  cylinder colliders: Size X = height, rotated 90 deg about Z). [ceiling analysis other problems]
- G10 Nobody runs git, touches Roblox Studio or any MCP tool. The lead (main session) does Studio, commit, publish.

## Owner items -> decisions
- F1/F2 coves + corners: corrected concave cove profile (one shared definition), builder poses at the wall face, corner
  pieces at the fillet centre, per-corner radius with square fallback near doors, top cove one run tangent to tangent,
  base cove split only at foot-level holes with `CoveBaseStop` ends, butt joints (0.05) not 0.5 overlaps, Corner
  Blocks kept as collision. [F1, F1+F2, F2 (doors at corners), F2+F4 (cove runs)]
- F2/F4 decks: ring deck ("pool surround") on all four walls of every flooded hall with corner pieces
  (Walkway_Corner_R16/R24, box for R0/R8); dry halls get no deck and no pool steps; steps start at the deck's pool
  edge; PaddlingRoom curved steps fixed; Walkway_Bend16 strays removed; BigPool island = one ring piece.
  [F2+F4 (walkways), F4-C, F4-D, F4-J, F4-K, F4-steps, F4-walkway-band]
- Chambers: uniform ledge ring, cove tori at corners, socket cove segments/stops, nook fixed or dropped.
  [F1+F2+F4 (chambers)]
- F3/F6 tunnels: ribs Tile with planar side UV, worn patches deleted, pipe steps Tile, one colour rule G1, UV fixes.
- F5 water: aligned single voxel row FloorY-4..FloorY-0.1 over the whole hall footprint (edge behind the walls),
  wet tunnels the channel span, chambers the full footprint, narrow pipes DRY (no water region). Wading depth stays
  within the owner rule. [F5a, F5b, F5c]
- F7/F14 skylights: `ceiling_well` flush plate; LightWell_R6 (P24), LightWell_R12 (P32, spiral), LightWell_R14
  (P32, replaces ExitSkylight); builder pivots at the ceiling plane, cut = PanelSize attr, Sky Cap per opening.
  VaultArcade: no fallback well under the vaults (skip when no clear pocket). LightRound flush. [F7+F14, F7, F14,
  F7 (VaultArcade), F4-lightround]
- F8 spiral wells: top tread at CeilingClass-14 with a landing, column through the hole, opening is a separate
  LightWell_R12 + Sky Cap; at most 1 per map, only halls with min side >= 128, never scaled (footprint 40 only).
  [F8 (stairs), F8a, F8 (count), F8b]
- F9 swervy rooms: Option A from ANALYSIS F9 (lanes kept; inward serpentine outline: corner arcs R24-64 + S-bulges,
  straight at doors), 2-4 swerve halls per map, CurvedChannel partitions and bends deleted. Kit pieces live in a NEW
  file `tools/level2_poolrooms/modules_swerve.py` (registered in build.py) whose cove/deck cross-section equals the
  corrected straight pieces.
- F10 wall decor: WallVoid becomes a flush recess (a hole in the wall slab with a dark back plate, no frame); SunSlit
  the same (no frame, glow plane overlapping the hole), never on the Arrival door wall, never cutting the top cove;
  DrainHole = small dark disc on the basin surface. [F10, F10+F4, F4-drain, F4-L]
- F11/F13 exit: as ANALYSIS F11 + F13 (closed stair on a smooth ramp, parapet, landing/bridge, closed core and
  support, deck to the collar, 16-gon opaque tube visual + identical SlideCol_Bore16 collision from one path,
  ExitCollar + ExitMouthTrim, deckZ = MinZ+42, no tub supports/entry floor/portal/lead tiles). EXCEPTION: do NOT
  modify the Level 2 Objective Controller. Exit.Mouth = the ExitMouthTrim inlay; the controller's open colour and
  0.35 transparency on that thin inlay over the opaque collar is acceptable. ExitSkylight is retired (LightWell_R14).
- F12 collision: G5 + G6 and ANALYSIS F12-A..G: keep the kit's Corner Blocks (correct pose) and delete the Corner
  Seals; keep PoolSteps_Curved step colliders (fix its yaw); keep Chamber 'Room Curved Side' colliders and delete the
  chamber Corner Seals; coves get 'Cove Fill' colliders; tunnel collars get Lower Corner Fills; chamber coves seat on
  the real floor; pump elbow/drop/rod/gauge colliders; exit lip/stair/guard per F11. Permanent audit per F12-PERM
  (collision_audit.py promoted from G:/Roblox/_local/l2fix/collision/audit2.py + kit_check.py).
- F4 polish: dressing out of walkway bands and shuffled pocket choice, ColumnHall variety, PaddlingRoom columns at the
  hall height, VaultArcade bays only where all 4 corners carry piers (groin vault, not dome), Arrival door on the wall
  face + apron not z-fighting, z-fight fixes. [F4-F, F4-G, F4-H, F4-I, F4-vault, F4-L, F4-M]
- F4-A light: SpotLights under every ceiling opening (Face Bottom, Range 60, Angle 70, Brightness 3, warm) with
  Shadows only on the 6 largest; BigPool LightRound emitters as SpotLights; preview Lighting profile ambient lowered
  slightly so the pools are not flat. Light cap 96.

## Work packages and file ownership (strict: edit only your files)
- WP0 foundation: `tools/level2_poolrooms/prkit.py`, `tools/tests/test_level2_kit_world_builder.py` (fixture
  nativeCylinder only), `tools/level2_blender/import_kit.py` + `tools/tests/test_level2_kit_import.py` (variants,
  Poolrooms slide templates).
- WP1 arch kit: `tools/level2_poolrooms/modules_arch.py`.
- WP2 tunnel kit: `tools/level2_poolrooms/modules_tunnel.py`.
- WP3 objectives kit: `tools/level2_poolrooms/objectives.py` + new `tools/tests/test_level2_exit_stair.py`,
  `tools/tests/test_level2_exit_bore.py`.
- WP4 swerve kit: new `tools/level2_poolrooms/modules_swerve.py` + `tools/level2_poolrooms/build.py`.
- WP5 audit tools: new `tools/level2_poolrooms/collision_audit.py` (numpy/scipy, from the collision analyst's
  audit2.py/kit_check.py in G:/Roblox/_local/l2fix/collision/), new `tools/level2_poolrooms/world_audit.py` (Blender:
  visual leaks, intersections, hanging-below-ceiling, floating bases, water coverage, coplanar z-fight, colour/tile
  stretch, cove/corner orientation, ceiling-opening flushness, jump-out reach) and new
  `tools/tests/test_level2_kit_collision.py` + `tools/tests/test_level2_world_audit.py` runners. Read-only use of
  world_check.py/render_world.py helpers (import, do not edit).
- WP6 builder shell (after WP0-WP4): Kit World Builder + test_level2_kit_world_builder.py + Lighting Controller.
- WP7 builder dressing + generator, WP8 swerve runtime, WP9 exit runtime: same files, run one after another.
- Final: lead rebuilds the export, dumps worlds for many seeds, runs every test and audit, adversarial review.
