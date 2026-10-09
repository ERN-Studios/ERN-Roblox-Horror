# Level 2 Poolrooms kit spec (restart of 2026-10-03)

The owner rejected the style C kit and restarted Level 2 from `G:\Roblox\Level 2 rework` (7 Poolrooms references).
Binding: only the OBJECTIVES (3 pumps + drains, pressure doors, the exit flume, arrival) and the ENTITIES
(Pool Foam, Pool Slide) carry over; every space, module, material and layout rule below is new. Still randomly
generated. The world contract other scripts read (`artifacts/level2-blender-20261002/ANALYSIS.md` section 3) still
applies in full, and the infrastructure of the first attempt is reused: `tools/level2_blender/kit.py` (Mesh builder,
export), `import_kit.py`, the Kit Layout Generator / Kit World Builder frameworks, the FloorY / narrow-passage aware
navigators, the developer preview wiring and the review fixes (commits 6e89a02..1436ed4).

## 1. Look (from the references)
- Monochrome warm cream / white small square glazed tiles with thin dark grout on EVERY surface: walls, floors,
  ceilings, columns, stairs, tunnels. No colour bands, no props, no signage, no furniture.
- Shallow green-turquoise water over most floors (terrain water, wading only, deep end <= 3.5 never swimming).
- Soft geometry: rounded room corners, coves where walls meet ceilings and floors, organic curved walls and
  walkways, fat cylindrical columns, circular porthole arches, round tiled tunnels, spiral stairs into round
  ceiling holes, groin-vaulted arcades.
- Light: few, hard sources - sun falling through round light wells and slits (real sky through holes so Roblox's
  sun casts the patches), glowing rectangular voids, recessed round ceiling lights in the big pool halls; a soft
  green ambient (Lighting/Atmosphere tint while the round runs). Darkness at the edges.

## 2. Materials (MaterialService, SmoothPlastic base) - the whole level uses three
| Variant | Use |
|---|---|
| `PR Tile` | everything by default (walls, ceilings, columns, decks, stairs, tunnels) |
| `PR Tile Aqua` | submerged pool and channel floors (reads green under the terrain water) |
| `PR Tile Worn` | sparse variety: cracked/grimy panels, pipe interiors, low chambers |
Plus Neon for light voids/lamp discs and terrain water. One tile scale everywhere: ten tiles per 6 studs.

## 3. Space classes and scale
| Class | Who can enter | Ceiling | Notes |
|---|---|---|---|
| Big halls | everyone incl. Pool Slide | 34 / 42 / 52 | lattice-snapped rectangles (AI contract) whose INSIDE is shaped by modules: rounded corners, coves, curved partitions, islands |
| Round tunnels (main network) | everyone | circle radius 21.5, centre at 15 over the floor | contain the certified 30 x 30 doorway envelope and the Pool Slide body; water channel + walkway variants, stair variants for FloorY changes |
| Narrow round pipes (escape) | players + Pool Foam only | diameter 12 | Width 12 corridor records, Pool Slide excluded (already supported) |
| Low chambers (escape pockets) | players + Pool Foam only | 14-16 | rounded small rooms 40-64, reached only through pipes |
Hall types (seeded per hall, all tiled): Column Hall (loose grid of fat round columns), Big Pool (regular rows of
columns, recessed round ceiling lights, round island around one column, dark arched outflows), Vault Arcade
(groin-vault bays on square piers + curved pool edge), Curved Channel (S-curved partition walls forming a winding
channel with a curving raised walkway), Spiral Well (spiral stair around a fat column into a ceiling hole with a
light well), Corridor Hall (long hall: channel + raised walkway + square columns + sun slits).
Role halls: Arrival (dry, quiet), 3 Pump Halls (Poolrooms pump chamber: heavy old pump, iron lever, round gauge on a
tiled plinth, pipes into the wall), Exit Hall (tall; spiral stair to a high tiled platform with the round tiled
mouth of the exit tube, round skylight above), 5 Paddling Rooms (the kids-area role: shallow, smaller, softest
curves; Pool Foam spawn pockets), 2 dens. NO decorative slide halls (no code outside the generator/builders reads
SlideHalls; the exit hall keeps the grand-hall role).

## 4. Modules (Blender, kit.py conventions, one material per chunk)
Rounded corner coves (radii 8/16/24 x ceiling class), wall-ceiling and wall-floor coves (lengths 16/32/64), fat
columns (diameters 6/10/16 x ceiling class) with cylinder colliders, porthole arch wall panels (circle openings in
internal walls), curved partition walls (quarter arcs R 16/32, S-curves) with box colliders along the arc, curved
walkways (stadium ends, quarter bends, straights) with ground colliders, pool steps (straight and curved), spiral
stair well (stair + column + ceiling collar + light well), groin vault bay 32 x 32 + pier, recessed round ceiling
light, round light well (ceiling hole to sky), glowing wall void, floor drain hole, round tunnels (Wet/Dry/Stair4/
Stair8 x lengths 64/72/80), narrow pipes (Flat/Stair4 x lengths 16-80), low chambers (4 prefabs), Poolrooms pump
station, exit platform + tube mouth + tiled exit tube visuals (collision unchanged from the reviewed slide design).

## 5. Instance budget
Fewer pieces than style C by design (no props): target <= 7,000, budget <= 8,500 after the watertight pass (measured 7,586-8,164) world descendants per round incl. the exit
flume; lights <= 80, shadow casters <= 6.

## 6. Watertightness contract (owner, 2026-10-03: "no holes out of the map, no gaps that make no sense, e.g. the
## corners at the round tunnels")
Seen in the review renders: hall walls had RECTANGULAR openings behind which the round tunnel's outer shell and
corner gaps showed, the 43-wide tunnel rose above 34-ceiling halls, and a light-blue line (the background) showed
along the wall feet at the water line. New rules, binding for the kit, the Luau builder and the Blender renders:
- Round tunnels: inner radius **17**, centre **13** above the tunnel floor at the mouth (floor chord half-width
  10.95; top at 30, collar to 32 < every hall ceiling). Pipes: radius 6, centre 6.
- Every tunnel/pipe mouth is a flush tiled COLLAR panel, 1.75 deep, whose outer edge is the rectangle x +-17,
  y -2 .. 32 (pipes x +-6, y -2 .. 12) and whose inner edge is the circle - so the hall wall's opening is EXACTLY
  that rectangle and the hall sees only a round portal. No tunnel outer shell, backface or void may be visible
  from inside any space.
- Walls start 4 below the lowest floor/basin floor of their hall and end 2 inside the ceiling slab; floors and
  basin floors run under the walls; ceilings overlap walls; corner coves and coves overlap the straight runs by
  >= 0.5; every seam is covered.
- Intended openings only: light wells and sun slits (to sky), the exit hall's flume gap, the tunnel/pipe portals,
  chamber sockets in use. Everything else must be closed visually AND for collision (no walking or falling out).
