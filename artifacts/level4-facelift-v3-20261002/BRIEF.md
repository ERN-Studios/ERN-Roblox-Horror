# Level 4 cinema — facelift v3 brief (2026-10-01)

You are one of several agents changing the Blender-built Roblox Level 4 cinema at the owner's request. Read this whole
file first, then `tools/level4_blender/README.md` ("Facelift v2" section) and the header of `tools/level4_blender/slots.py`
(export conventions). The owner's 15 screenshots are in `G:\Roblox\_local\l4facelift\v3\user\1.png ... 15.png` — LOOK at
the ones for your items. Overview renders I made: `G:\Roblox\_local\l4facelift\v3\plan_top.png` (top-down, ceilings
hidden; top of image = north = negative Z = auditoria; left = west = low X), `arcade_top.png`, `concession_top.png`,
`restroom_top.png`. The owner's moodboard (picked direction "F Synthwave Grid"):
`G:\Roblox\MongoTV\artifacts\level4-facelift-20260930\synth\mb_f_hero.jpg`.

The owner is a they/them. Theme: a mega retro 1980s-90s multiplex, abandoned, lost in the Backrooms, Synthwave look
(near-black plum walls, magenta + cyan neon, dark ceilings), film-still realism.

## Hard rules for every agent

- Do NOT run git. Do NOT touch Roblox Studio or the Blender GUI MCP (localhost:9876 is the owner's open Blender).
- NEVER save over `G:\Blender\Level4_Cinema\Level4_Cinema.blend` (the master). Work on copies / save outputs under
  your own folder `G:\Roblox\_local\l4facelift\v3\<PKG>\`.
- Run Blender ONLY through the slot runner (max 4 Blender processes machine-wide, ~2 GB RAM each):
  `python G:/Roblox/_local/l4facelift/v3/blrun.py <file.blend> <script.py> [args]`
  (it runs `D:/Blender/blender.exe -b <blend> --python-exit-code 1 -P <script> -- args`). Keep each run focused: to test
  your module, open a COPY of the master blend (or your own saved blend) and exec `slots.py` + your module only (every
  module's build function is idempotent: it deletes and rebuilds its own collection). The full chain is
  `tools/level4_blender/build_all.py -- <out.blend>` (env `L4_BUILD_KEEP_GOING=1`); only run it when you must.
- Edit ONLY the files your package owns (table below). If you need a change in someone else's file, write the exact
  request into your PROGRESS.md under "REQUESTS FOR OTHER PACKAGES" and work around it.
- Keep `G:\Roblox\_local\l4facelift\v3\<PKG>\PROGRESS.md` current (done / todo / decisions / render paths) so a
  restarted agent can resume. If `PROGRESS.md` already exists when you start, RESUME from it — never restart from zero.
- Look at your own renders (EEVEE or Workbench, from player eye height ~5 studs above the floor and from the owner's
  camera angles) and iterate until it genuinely looks like a film still and every owner point you own is visibly fixed.
- Collision: anything solid a player can bump into gets a collider (`obj["l4_collide"]="bounds"` or mesh `l4_col` boxes).
  Floor litter gets NO collider. New walls that close off spaces are solid and also block the camera (see "Camera").
- Budgets: keep the whole level under ~1.0M unique triangles; new instanced props <= 2.5k tris each; lights total <= 260.

## Coordinates

Layout/studs coordinates are the ORIGINAL Studio coordinates (X 22624..23376, Y up, Z -239..239). Blender metres =
((X-23000)*0.28, -Z*0.28, Y*0.28). The final Studio model sits at +6000 X. The ground floor top is Y=24.
Zones (studs): auditoria A1 (Cinema 1, west) X 22678-22854, A2 X 22912-23088, A3 X 23146-23322, all Z -239..-21;
side corridors C1 (west of A1) X 22624-22676, C2, C3, C4; concourse/lobby Z -20..100 full width; a maintenance core
(stair room, "SecretPoster" door at X 22675 Z 86) at X 22647-22676 Z 0-98; the projection gallery ("maintenance
corridor", HiddenService/Gallery*) upstairs at Y 85-98, Z -20..0, full width; south rooms (Z 101-239): Service
X 22624-22879, Concession X 22880-23120 (the street main entrance is in its south wall at X 22976-23024 Z 239),
Arcade X 23122-23260, Restrooms X 23262-23377.

## What the owner asked (verbatim, Danish) and what we will do

Owner's answers to my questions: main entrance = "Som om det er dækket til af træ, fordi det er efterladt og der har
været indbrud" (boarded up with wood after a break-in); star ceiling = "Alle steder undtagen service rummet"
(everywhere except the service room — includes restrooms, corridors, concourse, concession, arcade, gallery and the
auditoria); wallpaper = dark synthwave pattern; Meshy = lockers x2 + floor litter x4 approved.

1. "de her ting der ligger på gulvet, det må gerne være 3d, altså små props ... De skal ikke have nogen collision."
   -> The flat popcorn/cup DECALS on the floor (props_decay, material L4S_DECAL_popcorn_cups, ~254 uses) become small
   3D litter props (4 Meshy variants: popcorn bucket spill, crushed cups, popcorn pile, paper/candy/tickets), NO
   colliders. Fewer, better placed (~100-150 clusters), never floating, never through walls/props. [P6]
2. "indgangen til cinema den skal ikke have noget synligt ude fra" + answer "dækket til af træ ... indbrud"
   -> The street glass storefront + main entry doors (Concession south wall, Z 239, arch_detail facade glass,
   layout MainEntry_*, doors MainEntryWest/East which stay welded shut) get boarded up with weathered plywood boards
   and planks screwed over them, from the INSIDE and the OUTSIDE, so nothing is visible through them; break-in story:
   one board pried loose/cracked, broken glass shards on the floor inside, crowbar marks. No see-through gaps. [P4]
3. Ceiling light: "mærkelige overlaps" (two layers of ceiling fixtures overlap: the cloned ORIGINAL Fixtures + the new
   troffers) and "utrolig mørkt under der hvor der faktisk er lys" (lights never reach the floor). Owner wants the
   primary light from NEON, plus a Rolls-Royce STARLIGHT ceiling ("stjerner som på en rolls royce i loftet"); neon
   blinks here and there so some places go dark; "Man skal være i stand til at se alt, men når de blinker kan man ikke
   se noget der, og det skal allerede være mørkt" (you can see everything, but where a light blinks off it goes dark,
   and the mood is already dark); "Nogen lys har bare mindre lys end andre" (some lights weaker than others).
   -> LIGHTING SPEC below. [P2 Blender, P8 Roblox side]
4. Concession walls: same texture as the rest of the cinema, not red -> new wallpaper. [P1 + whoever builds the surface]
5. Concession counter too deep ("Disken ... skal ikke være så bred"): the owner drew a line; keep the counter from its
   BACK edge (the staff side, toward the back wall Z~102) to at most ~5 studs deep (currently 17 studs: layout
   Concession/Counter X 22890-23050 Z 107.5-124.5). Thinner is fine if everything on it still fits (registers, soda
   fountain, popcorn machine, candy case). The customer side in front of it becomes carpet. [P3]
6. "de ternede hvor man kan købe ting, skal fjernes, det samme med de sorte blocks, skal bare være tæppet" -> remove the
   checker floor strip in front of the counter (layout Concession/Checker_White, Checker_Red, Checker_Black = the black
   6x6 blocks at Z 128). Only carpet there. [P1]
7. "De ternede røde og hvide bag disken skal også bare være tæppet" -> the red/white checker floor BEHIND the counter
   (props_rooms, slot CHECKER_VCT) becomes carpet. [P3]
8. Arcade: "1 større dør der passer bedre til arcade tema, ... døren er ud fra midten af lokalet" -> ONE bigger
   arcade-themed door (single leaf, ~10 studs wide x 13 tall, neon-edged, porthole/marquee feel) centred on the room:
   opening X 23187-23197, Y 24-37 in the concourse south wall (Z 101). The old opening (X 23150-23178, sidelights,
   ArcadeLeft/ArcadeRight doors) becomes solid wall. "der er 2 tomme sider til hver sin side hvor arcade spil er, kan du
   lukke dem af, og så få arcade spil til at være fra væg til væg" -> the glass alcove boxes ("ArcadeAlcoveWalls",
   props_rooms, at X~23172 and X~23212) leave two empty side spaces; close them with SOLID walls (wallpaper + synthwave
   neon trim, colliders, camera-blocking) and line both side walls with arcade machines from the front wall to the
   back (prize counter) wall, no gaps. [P1 opening, P3 room, P5 door]
9. Restrooms: remove the teal tile cap line so the white tiles go straight up to the wallpaper ("bare kun er hvidt op
   til væggen"); wallpaper "noget HELT andet end det røde"; urinals face the WRONG way -> turn them to face away from
   the wall, mounted on the wall; the chrome flush-valve pipes on top are crooked / go into the wall -> straight,
   meeting the wall cleanly. "kan se op igennem taget" and "Ret mange vægge ved toiletterne ... kan man bare se igennem
   væggene" -> the camera clips through walls and roofs EVERYWHERE (see "Camera"); also make sure every restroom room
   has a real closed ceiling + collider at its ceiling height. [P3 props, P1 walls, P2 ceiling, P8 camera]
10. "hver projektor ting der holder den oppe, går ned igennem 4 sædder, fjern den væg der holder den oppe" -> delete
   A1/A2/A3_BoothFrontSupport (the 32x13 wall under the projection booth front, Z -33.5, Y 72-85, which cuts through the
   last seat row). The booth stays (hung from the rear wall with its lintel). Check no seat is intersected after. [P1]
11. Service doors: "skal også ændres til noget bedre, ... passe til temaet, ... bare 1 er nok" -> one single themed
   door: opening narrowed to X 22860-22868, Y 24-36 (wall infill either side). Service wallpaper also changed to the
   theme wallpaper (the service room keeps its Backrooms fluorescent lights, NO star ceiling there). [P1 opening/walls,
   P5 door, P3 service decor]
12/13. Cinema 1: "der er en væg som er tynd og dækker ingen ting" -> it is a bug: an `L4D_Casings` island (arch_detail)
   0.2 studs thick spanning X 22602-22738, Y 24-96 at Z 2.0-2.2 standing in the open lobby. Fix the casing generator and
   audit ALL casings/trims for any piece larger than its opening or floating in the open. [P4]
   "Hele indgangen til cinema 1 i venstre side skal fjernes, samt der hvor du kan gå rundt om selve biografen ... det
   skal blokeres af lige der hvor jeg står, det er lige ved trapperne op til cinema 1. Så bare fjern det, så det ikke
   skal renders og have alt muligt bagved, og så også fjern inde i biografen at man kan gå ud/ind fra venstre side."
   -> The owner stood in the passage west of the lobby, under the gallery, at the queue stanchions (X 22646-22652,
   Z -16..-6) in front of the C1 mouth. Block it with a solid wall from the A1 rear facade (Z -21) to the core's
   north-east corner (Z 0) at X ~22676 (flush with the core's east face and A1's west wall line), full height up to the
   gallery floor (Y 24-85), finished like the surrounding lobby wall (facade/wallpaper, skirting, neon trim continuing).
   Everything behind it becomes unreachable and is REMOVED: all of C1 (stair, return corridor, cladding, lights, roof),
   the north passage (X 22624-22676, Z -20..0, ground level, stanchions) and the west passage beside the core (X
   22624-22647, Z 0-98) — floors, props, decals, lights, ceilings, colliders. The gallery upstairs above them stays.
   Inside A1, close the west side entry (A1_WallWest opening Z -124..-136, Y 42-52) with wall matching the
   auditorium wall, and remove the west-entry trims/signs/landing bits. [P1 layout, P4 detail, others clean their
   own objects in that zone: P2 ceilings/lights, P3, P5, P6 decay/props]
   Mirror-check: do NOT touch C4 (east of A3); the owner only asked for Cinema 1.
   "Maintenance trappen og det rum er perfekt" -> keep the core stair room; only change the stair carpet and its
   wallpaper to the theme. [P1]
14. Projection gallery ("maintenance gangen", image 14): new theme floor (use the lobby carpet slot CARPET_LOBBY or the
   auditorium carpet — consistent with the lobby) and theme wallpaper; "den der neon lys er meget godt" -> KEEP the
   orange neon cove strips. "Kan du ... få det til at være buet som den er i højre side i billedet, men også på venstre
   side, stadig have de døre hvor de er" -> the south wall (right side when looking east) is curved (layout
   GalleryCurvePanel/Cove/Valence/Skirting x24); give the NORTH wall (with the A1/A2/A3 projection booth doors, layout
   GalleryNorth + A*_GalleryBoothFrame) the same curved panel treatment while every booth door stays exactly where it
   is (doors and their frames remain usable, panels return into the door reveals). Ceiling: ONLY the starlight, no
   other lamps, and the stars light the whole corridor. "Nede i bunden af maintenance gangen" add cabinets: the two
   Meshy lockers (LockerBank, SupplyCabinet) at the far (east) end of the gallery, against a wall, not blocking the
   path, with colliders. [P4 north curve, P1 floor/wallpaper, P2 stars, P3 lockers]
15. "Cinema 2 skiltet er dækket til af den trekants væg" -> the CINEMA 2 marquee/sign above A2's entrance is hidden
   behind the V-shaped "CentralFork" wall (layout CentralFork/*, X 22936-23064, Z 0-41). Move/rebuild the Cinema 2 sign
   onto the V-wall (its tip/front, facing the lobby) so it reads like the other cinemas' signs. Find which module builds
   that sign (props_lobby marquees, arch_detail, or an original SurfaceGui sign cloned onto a Signage carrier by
   place.luau) and fix it there. [P4; if it is a Signage carrier, P8 adds a carrier move override]
General: "væk fra de røde wallpapers, og have ensartet wallpapers, som passer ind i det samme tema all around" -> ONE
   theme wallpaper everywhere a wall shows plaster/wallpaper (lobby/concourse plain walls, corridors C2-C4,
   CentralFork, concession, arcade, restrooms above the tiles, service, core stair room, gallery). Auditoria keep their
   acoustic/velvet panels; their remaining plain wall areas get the same wallpaper. No red/orange walls anywhere.
General: "optimere hele levelet, så vi ikke har så mange ligegyldige ting ... hvis du fjerner noget så skal du være helt
   sikker på at det ikke laver et hul" -> a later dedicated pass (P7). In YOUR package: do not add hidden junk, delete
   what you supersede, and do not leave objects in the removed C1 zone.

## New textures (Codex is generating them now)

`G:\Roblox\_local\l4facelift\v3\gen\`: `tex_wallpaper_synth.png` [1.2 m], `tex_board_weathered.png` [1.2 m],
`tex_headliner_suede.png` [1.0 m] (plus Meshy reference images). P1 turns them into PBR sets with
`tools/level4_blender/make_pbr.py` (see pbr_spec.json for parameters; output dir `G:\Blender\Level4_Cinema\textures\pbr`)
and points slots at them: `WALLPAPER_MAIN` -> wallpaper_synth (tile 1.2, base rgb ~ (30,18,34), Roblox "Fabric" or
"Plaster" material, sem "plaster"), new `BOARD_WEATHERED` (Wood), new `HEADLINER` (Fabric, very dark), new `EMIT_STAR`
(Neon, warm white ~ (255,244,225)), `EMIT_STAR_COOL` (~ (220,232,255)). If a texture file is not there yet when you
need it, the slot falls back to flat values (slots.py does that) — build anyway and re-run later.

## Meshy assets (I generate them; GLBs land in G:\Roblox\_local\l4meshy\<Asset>\<Asset>.glb)

`LockerBank` (3 tall staff lockers, ~0.9 x 0.45 x 1.8 m), `SupplyCabinet` (2-door steel cabinet ~0.9 x 0.45 x 1.8 m),
`LitterPopcornSpill` (~0.45 m), `LitterCups` (~0.4 m), `LitterPopcornPile` (~0.35 m), `LitterPaper` (~0.4 m).
Add their specs to `tools/level4_blender/meshy_specs.json` (P3 adds the two lockers, P6 the four litter assets; tris:
lockers 3000, litter 1200; litter col_slices 0 / no collider) — coordinate by editing only your own entries. Until a
GLB exists, code against `L4A_<Asset>` and test with a proxy box.

## LIGHTING SPEC (P2 builds it in Blender, P8 makes Roblox honour it; I tune final gains live in Studio)

- Everywhere except the Service room: the ceiling becomes a dark STARLIGHT headliner: a flat or gently coffered
  near-black deck (slot HEADLINER) at the REAL ceiling height (the layout roof underside, so the camera-blocking roof and
  the visible ceiling coincide — no plenum above a lower visible ceiling), with thousands of tiny star points: emissive
  quads/discs 0.08-0.25 studs, irregular (Poisson-disc, NOT a grid), 3-4 brightness tiers + a few clusters, mostly
  warm/cool white with a rare faint magenta/cyan one, exported as Neon (pool stars per zone into a few meshes, split into
  3 "twinkle groups" via obj["l4_tags"]="L4StarTwinkleA|B|C" so the client can gently twinkle them). Density ~1 star per
  4-6 sq studs. Drop the ACT/troffer/can/drum fixtures and their lights everywhere except Service; the Service room keeps
  (and may get a few more) flickering fluorescent tubes — that is the Backrooms room.
- The stars LIGHT the space: soft, low, cool-neutral fill from the ceiling (Roblox has no emissive lighting, so add real
  lights: a sparse grid of downward SurfaceLights (AREA lights facing -Z, l4_angle ~80-90) or PointLights a few studs
  below the deck, range reaching the floor + 10, low brightness, no shadows). Vary them ±40% so some zones are darker.
- NEON is the primary light: real lights along the magenta/cyan/orange/red neon strips (facades, coves, signs, columns,
  the gallery's orange cove), colour-matched, short-medium range (12-24 studs), brighter than the star fill. About 12-18%
  of neon groups blink: they get OccasionalFlicker (FlickerLens prop + light parented, see existing ceilings.py /
  props_rooms.py flicker code) and when they blink OFF their area goes properly dark. Some neon is dead/dim already.
- Auditoria: starlight ceiling too, plus their wall coves/sconces; keep a readable but dark room.
- Remove the cloned ORIGINAL ceiling fixtures and their legacy lights (the "overlaps"): P8 (place.luau/export legacy
  lights) + P2 (lights_and_camera.py "L4 Lights" legacy set) — keep only Level4V4Exit and anything gameplay needs.
- Keep shadows off except at most 6 hero lights. Total lights <= 260. Write the light plan + counts per zone into
  PROGRESS.md.

## Camera (root cause of "see through walls/roof")

Roblox's Poppercam only treats a part as a camera occluder if `CanCollide == true` AND its transparency < 0.25. Our
visual MeshParts are CanCollide=false and our colliders are Transparency 1, so the camera passes through EVERYTHING.
Fix (P8, in export/make_place/place.luau): architectural colliders (walls, floors, roofs/ceilings, tiers, stairs —
the layout parts that are visible, plus new solid walls/ceilings flagged `obj["l4_occluder"]=True` by the Blender
packages) are placed Transparency 0, inset 0.1 stud inside the visual surface on every axis (skip if any dimension
would drop below 0.3), Color black (8,8,8), SmoothPlastic, CastShadow false, CanQuery true, CanTouch false. Glass,
props, seats, litter, door leaves stay as they are. P2/P3/P4 set `obj["l4_occluder"]=True` on every NEW solid wall or
ceiling deck they add (C1 block wall, arcade side walls, star ceiling decks, restroom ceilings).

## File ownership

| Package | Owns (edit only these) |
|---|---|
| P1 LAYOUT+MATERIALS | `layout_edits.py` (-> regenerate `l4_layout.json`), `build_base.py`, `slots.py`, `pbr_spec.json`, `make_pbr_all.py`, new PBR files in the textures\pbr dir |
| P2 CEILINGS+LIGHTS | `ceilings.py`, `lights_and_camera.py` (may add a final lighting pass function in ceilings.py that rebalances lights other packages created) |
| P3 ROOMS | `props_rooms.py`, its entries in `meshy_specs.json` (LockerBank, SupplyCabinet) |
| P4 DETAIL+LOBBY | `arch_detail.py`, `props_lobby.py` |
| P5 DOORS | `doors_v2.py`, `PushDoors.server.lua` |
| P6 DECAY+LITTER | `props_decay.py`, its entries in `meshy_specs.json` (Litter*) |
| P8 PIPELINE | `export_l4.py`, `make_place.py`, `place.luau`, `Level4LightingController.client.lua`, `serve.py`, `upload.luau`, `build_all.py`, `import_meshy.py` |

All paths are in `G:\Roblox\MongoTV\tools\level4_blender\`. `meshy_specs.json` is shared: edit only your entries and
re-read the file right before writing it.

## Final answer of a package agent

A short report: what you changed per owner point, files touched, counts (objects/tris/colliders/lights), render paths
that prove each point, open issues, and any REQUESTS FOR OTHER PACKAGES.
