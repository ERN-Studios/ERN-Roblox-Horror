# Job: BUILD the mall lobby in Blender (script, data for the Roblox importer, textures, QA renders)

You are the single helper on the Roblox co-op horror game "BACKROOMS: STAY QUIET". The owner approved the concept
pictures of a new lobby ("Amazing. Use blender to make a lobby exactly like those pictures with the layout following
the blue print ... make Codex 6.1 sol ultra do the heavy lifting with rendering and all that stuff, and make sure
Claude QAs its work before importing anything"). Claude (the main agent) did the groundwork below, will QA your
renders and data, and will then import the data into Roblox Studio and wire the game's functions to it. You build.

Work only in /Users/zeanjuul4/Projects/stayquiet-poolrooms-audio-20261009.
Two earlier runs of this job were stopped within minutes over the number of queue pads; it is THREE a shop, final;
anything it left under `tools/lobby_mall/` or `artifacts/lobby-mall-20261011/build/` is yours to keep, change or discard.
HARD RULES. No Roblox Studio, no MCP server, no computer use, no browser, no network, no other agents. No git commit,
push, stash or reset. Never print credentials. ONE Blender process at a time, `--threads 2` (this Mac has 8 GB and a
nearly full swap); renders at most 960 x 540, Eevee, low samples. Scratch under /tmp, removed at the end.
Files you may create or change, and nothing else: `tools/lobby_mall/*` (new folder) and
`artifacts/lobby-mall-20261011/build/*` (data, textures, blend, renders, your report). Blender is
/Applications/Blender.app/Contents/MacOS/Blender; numpy and Pillow are in /usr/local/bin/python3 and numpy in
Blender's Python.

## What to read first
- `artifacts/lobby-mall-20261011/raw_v3/W01..W13.png`: THE pictures to match (round three; `W02` and `W13` are the
  shop stand after the owner's reference). `brief_v3.md` section "THE LOOK" describes them in words, and
  `brief_v3_stand.md` the stand. `plan_v3.png` (script `tools/lobby_reach/mall_plan.py`) is the blueprint.
- `artifacts/lobby-mall-20261011/refs/owner_sign_reference.png`: THE SIGN STYLE, the owner's own crop: "Make sure
  the layout of the signs follow layout, color and font as the level 2 example attached". So EVERY sign box in the
  build is this, not round three's dark-red lettering: a long shallow backlit box, face pale cream-yellow (about
  RGB 236,226,160, a little uneven, brighter in the middle), a thin dark bronze-grey frame (about 62,58,46), and the
  text centred in ONE line in a bold CONDENSED sans-serif (DIN Condensed Bold:
  /System/Library/Fonts/Supplemental/DIN Condensed Bold.ttf) in dark warm grey (about 72,66,54): the number, a space,
  the name, capitals, cap height about 55% of the face's height.
- How an earlier map went from Blender to Roblox: `tools/level5_void/build_level5.py` and `import_level5.py` (native
  Parts made from a JSON file). Same idea here; the data contract is below.

## Coordinates and the fixed measurements (Roblox studs; x east, y up, z north; a player is 5 studs tall)
The new lobby is built on the PRESENT lobby's plan coordinates, so everything that works today keeps its place; the
importer adds an offset to stand it beside the old one. Floor top is y = 30.0 everywhere unless said.
- CONCOURSE: x 180..260, lit part z -900 (entrance wall) to -621 (the tape). Suspended ceiling underside y = 46.0.
- DARK WING: the same concourse and the same shop modules going on from z -621 to z -421 with no light at all
  (the lobby's monster lives there; keep its floor completely clear, x 184..256).
- SIX SHOPS, each a unit 53 deep and 58 long, floor level with the concourse, interior height 14, open to the
  concourse along its whole front except a 3-stud pier at each end: an opening 52 long and 12 high, with an
  oak-laminate fascia band above it carrying the sign box (40 x 3.2), centred.
  West side, x 127..180: Level 1 z -869..-811, Level 3 z -789..-731, Level 5 z -709..-651.
  East side, x 260..313: Level 2 z -869..-811, Level 4 z -789..-731, Level 6 z -709..-651.
  Signs: `1 OFFICE`, `2 POOLROOMS`, `3 MALL PARTY`, `4 CINEMA`, `5 THE VOID`, `6 PLAY ZONE`.
  Front zone of each shop (27 deep, nearest the concourse): the QUEUE BAY: THREE round pads in a row parallel to
  the front, exactly as the pictures show (the owner: "lav 3 plader, det passer bedre til dette map"), radius 7.4,
  0.6 high, dark green with a paler ring inlay, centres at x = 166 (west) or 274 (east) and z = shop centre -19, 0,
  +19; a sign post beside each on the concourse side (post 4 high, plate 3.2 x 1.3): `STATION 1`, `STATION 2`,
  `STATION 3` (station 1 nearest the entrance, lowest z). A clear cylinder of radius 7.4 and 9 high over every pad:
  nothing may stand in it.
  Back zone (26 deep): the level's SHOWCASE, as in W03..W08, built of plain geometry:
   1 OFFICE: mustard damask wallpaper, beige carpet, its own low tile ceiling with one fluorescent panel, a square
     pillar, a grey wall cabinet.
   2 POOLROOMS: pale small-tile walls, a basin of dark teal water 1.2 deep across the zone, five tiled round columns
     with flared capitals standing in it, cool light.
   3 MALL PARTY: orange walls with a black lower band, road-map play carpet, one folding table with paper cups, two
     bunches of balloons, a black tile ceiling.
   4 CINEMA: navy walls with one magenta and one cyan neon band, a pale glowing screen, two short rows of red seats,
     a triangle-patterned carpet.
   5 THE VOID: everything one flat rose colour; the floor falls away to black at the back with a narrow ledge and
     two blocks standing in the drop; one lamp globe on a thin rod.
   6 PLAY ZONE: padded posts in yellow, red, blue and green on a grid, black netting between them, blue-and-green
     puzzle mats, the round mouth of a tube slide.
- THE STAND `SHOP & SUPPLIES`, centre x 220, z -770 (W02, W13, `brief_v3_stand.md`): hexagonal island counter
  (circumradius 9, 3.6 high) with five round stools; hexagonal display tower from its middle (circumradius 3.5, top
  at y 39.5) with pegboard faces, small boxed goods, potion bottles, one CRT, a rail of five simple hooded suits
  (yellow, pale blue, cream, black-and-gold, purple); six opal globe lamps on brass arms; a hexagonal sign fascia
  with the sign on all six faces; a hexagonal carpet (circumradius 15) with a brass edge; a side counter with a till.
  The gap in the counter faces south (toward the entrance).
- ARRIVAL: entrance wall at z -900 with dead dark glass doors; a brown mat; a hanging sign `WELCOME` at z -886; two
  rows of nested trolleys by the side walls. The players' spawn point is x 220, z -860: keep 12 studs clear round it.
- FURNITURE: a planter with benches at (220, -835) and at (220, -700); a few brown plastic tubs with fake plants by
  the piers. A freestanding `DIRECTORY` board by the west wall at z -795 (board face 18 wide x 12 high, facing
  east), and a small notice board (8 wide x 10 high) by each shop: at (195,-825) (245,-855) (195,-745) (245,-745)
  (195,-665) (245,-695), facing the concourse's middle. These seven faces are where the game's leaderboards go:
  leave them blank and flat.
- EVENT STAGE: deck x 205..235, z -655..-632, 2 high, carpeted, steps on the south side; a folding table with a DJ
  console centred at (220, -639); two speakers on stands; a cloth banner `GRAND OPENING` on two posts behind it; rows
  of folding chairs south of it, three fallen.
- THE TAPE at z -621: seven black-and-yellow striped poles (x 184..256, every 12; 3.6 high, round bases) carrying
  one yellow tape at y 33.2, printed along its whole length `DANGER: DO NOT GO PAST THIS POINT`, repeated, with a
  gap of two words' width between repeats. No fence, nothing else across the concourse.
- CEILING LIGHT: recessed panels 8 x 4 in two rows at x 200 and x 240, every 20 studs from z -890 to z -630; dead
  (dark, not glowing) at (240,-830) (200,-750) (240,-690) (200,-650) (240,-650); one dim and flagged to flicker at
  (200,-810). None at all in the dark wing.
- WALLS between and beside the shops, columns 4 x 4 at the piers and every 20 studs: yellowed cream plaster, a brown
  tile skirting 1.2 high, the teal stripe (y 33.4..34.2) and the mauve stripe (y 34.4..35.2) all the way round,
  across walls and columns. Oak-laminate fascia band over the shop fronts.
- THE LOOK is `brief_v3.md` "THE LOOK": yellow cast, MATTE worn floor (beige terrazzo with a brown border), stained
  2x2 ceiling tiles, laminate, dull brass. Nothing glossy, nothing modern.

## What you deliver
1. `tools/lobby_mall/build_mall.py`, run as
   `/Applications/Blender.app/Contents/MacOS/Blender -b --factory-startup --threads 2 --python tools/lobby_mall/build_mall.py`.
   ONE script that holds the whole design as code and from it (a) builds the Blender scene, with materials that look
   right in Eevee, and saves `artifacts/lobby-mall-20261011/build/mall.blend`; (b) writes
   `artifacts/lobby-mall-20261011/build/mall.json` for the importer; (c) writes its tiling textures (512 or 1024 px
   PNG, generated in code with numpy/Pillow: terrazzo, ceiling tile, damask wallpaper, plaster, oak laminate, the
   carpets, small tile, pegboard, puzzle mat ...) into `artifacts/lobby-mall-20261011/build/textures/`. Running it
   twice gives the same files.
2. THE DATA CONTRACT, `mall.json` (Roblox will be built from this and nothing else; Blender and the JSON must come
   from the same numbers):
   `{"version": 1, "units": "studs", "bounds": {"min": [x,y,z], "max": [x,y,z]},`
   `"materials": {"<key>": {"base": "<Roblox material name, e.g. Concrete, Plaster, Carpet, WoodPlanks, Metal, Glass,
     Fabric, SmoothPlastic, Neon>", "colour_map": "textures/<file>.png" or null, "normal_map": ... or null,
     "roughness_map": ... or null, "studs_per_tile": n}},`
   `"parts": [{"name": "...", "group": "Concourse|Shop1..Shop6|Stand|Arrival|Stage|Tape|DarkWing|Furniture|Ceiling",
     "shape": "Block|Cylinder|Ball|Wedge", "pos": [x,y,z], "size": [sx,sy,sz], "rot": [rx,ry,rz],
     "color": [r,g,b], "material": "<key>", "transparency": 0..1, "collide": true|false, "glow": true|false}],`
   `"signs": [{"name", "text", "style": "box|station|banner|tape|plain", "pos": [x,y,z], "size": [w,h],
     "normal": [x,y,z], "part": "<name of the part it sits on>"}],`
   `"lights": [{"name", "kind": "panel|globe|showcase|neon", "pos": [x,y,z], "color": [r,g,b], "brightness": n,
     "range": n, "state": "on|dim_flicker"}],`
   `"anchors": {"spawn": [x,y,z], "pads": [{"level": n, "station": k, "pos": [x,y,z], "radius": 7.4}],
     "shop_stand": {"centre": [x,y,z], "radius": 9}, "boards": [{"key": "directory|level1..level6", "pos", "size":
     [w,h], "normal"}], "dj_console": [x,y,z], "stage_deck": {"min": [...], "max": [...]}, "tape_z": -621,
     "dark_wing": {"min": [...], "max": [...]}}}`
   Rules: `pos` is the part's centre; `rot` is degrees for Roblox `CFrame.fromOrientation(rx, ry, rz)` (Roblox
   applies Y, then X, then Z); a Cylinder's axis is its local X and a Wedge slopes as Roblox's WedgePart does; sizes
   are the part's local x, y, z; no dimension under 0.05 or over 2048. Say in your report exactly how you converted
   from Blender's axes, and prove it with a test of three rotated parts whose corners you compute both ways. The
   whole build must stay under 5,000 parts: use long merged boxes and tiling textures, not a part per tile. Every
   part the players can touch has `collide` true; decoration smaller than a fist, netting and lamp globes false.
   Signs are DATA (the importer draws the text in Roblox); in Blender show them with real text in that style.
3. `tools/lobby_mall/check_mall.py` (plain Python, `/usr/local/bin/python3`): reads `mall.json` and asserts the
   contract and the measurements above: every anchor present; 18 pads at the stated centres with their clear
   cylinders empty; the spawn's clear circle; the dark wing's floor clear; each shop opening at least 52 x 12; the
   concourse free for a 5-stud-tall player along a 20-stud-wide path from the spawn to the tape that passes the
   stand; every sign's text exactly as written here; part count; nothing outside `bounds`; no two large solid parts
   occupying the same volume (overlapping coplanar faces flicker in Roblox: flag any pair of parts whose coplanar
   faces overlap by more than a square stud).
4. `tools/lobby_mall/render_mall.py`: from `mall.blend`, renders at 960 x 540 the same thirteen views as W01..W13
   (same standpoints and directions as near as the plan allows; name them `R01_arrival.png` ... `R13_stand_from_above.png`)
   plus `R00_plan.png` (straight down, ceiling hidden, the whole lobby) and `R14_dark_wing_lit_for_review.png` (the
   dark wing with a work light, so its geometry can be judged), into `artifacts/lobby-mall-20261011/build/renders/`,
   lit only by the panels, globes, showcases and neon in the data.
5. LOOK at every render beside its W picture and fix the build until they agree in layout, proportions, colours and
   mood; then write `artifacts/lobby-mall-20261011/build/REPORT.md`: what is built, the part count by group, the
   axis conversion and its proof, the checks' output, one line per view on how it differs from its W picture, and
   everything you are NOT satisfied with or could not do. Final message: a fifteen-line summary of the report.
If something here contradicts a picture, the measurements here win and you say so in the report.
