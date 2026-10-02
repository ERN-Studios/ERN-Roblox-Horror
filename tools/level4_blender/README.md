# Level 4 cinema: Blender rebuild -> Studio

Built 2026-09-30. `Workspace."Level 4 Cinema Blender"` is the Level 4 developer preview now
(`Level4V4PreviewAccess.MODEL_NAME`). The original `Workspace."Level 4 Cinema Preview"` is untouched,
and so is its QA copy.

Blend file: `G:\Blender\Level4_Cinema\Level4_Cinema.blend` (textures in `textures\` next to it).
Scale: 1 stud = 0.28 m. Studio (23000, 0, 0) is the Blender origin. The new Studio model sits 6000 studs
east of the original, at (29000, 0, 0).

## Pipeline (run in order)

1. `l4_dump.json` holds every part, light and non-part instance of the original preview. It was dumped
   from Studio through execute_luau + an HTTP POST to a loopback receiver.
2. `python layout_edits.py` writes `l4_layout.json`, which is the dump plus two owner edits:
   * a flush plaster skin over every opening's header, so the walls above openings have no notches;
   * the Concessions opening is 8 studs taller (top at Y 44).
3. `python make_textures.py` turns the Codex (GPT-6 Sol) texture renders in
   `artifacts/level4-blender-20260930/refs` into tiling colour maps plus neutral `_n` detail maps
   (the `_n` maps are tinted with the Studio colour).
4. In Blender (MCP `execute`, or `blender -P`), run `build_base.py`, `props.py`, `doors.py`,
   `lights_and_camera.py` (`build_lights(); world()`), then save.
   * **Architecture**: every visible layout part at its exact CFrame, with semantic PBR materials.
   * **Props**: one modelled asset each (seat, arcade cabinet, table, cafe chair, marble column,
     popcorn case, toilet, sink, stock box, extinguisher, bench/sofa, stool, janitor cart), placed as
     linked duplicates.
   * **Doors**: one collection per door. The Empty `DoorHinge_<Name>` sits on the hinge axis and parents
     the leaf. Rotating it about Z opens the door.
5. In Blender, run `export_l4.py`. It writes chunks (UV box-projected) plus `manifest.json` to
   `G:\Roblox\_local\l4blender\export`.
6. Upload and place:
   1. Upload the textures with the MCP `upload_image` tool. The ids go in `textures.json`.
   2. Start `python serve.py 8765`.
   3. Upload the meshes with `upload.luau` (group-owned). The ids go in `results.jsonl`.
   4. Run `python make_place.py`.
   5. Run `place.luau`, with `__PUSH_DOOR_SOURCE__` replaced by `PushDoors.server.lua` as a long string.

## What the Studio model contains

- `World`: pooled visual meshes. `Props`: one Model per prop. All visual meshes are CanCollide false.
- `Collision`: invisible parts, which are exactly the collidable parts of the layout, so walking and
  raycasts behave like the original. They keep its Materials and `Level4V4Floor` tags.
- `Signage`: the original poster Decals and sign SurfaceGuis, cloned onto invisible carriers 0.02 studs
  proud of the new surfaces.
- `Lights` and `Fixtures` are cloned from the original. `OccasionalFixtureFlicker` still works.
  `Level4V4Exit` is cloned from the original.
- `Doors`: each door is a Model with an anchored `Hinge`, an unanchored invisible `Leaf` collider, the
  welded visual meshes, and a Servo HingeConstraint.
  * `PushDoors` opens a door away from whoever walks into it, and closes it once its swing arc is empty.
  * Doors without floor on both sides (the two street doors) are welded shut. `PushDoor` shows which is
    which.

## Facelift v2 (2026-10-01): "Synthwave Grid" 80s-90s cinema lost in the Backrooms

The owner asked for a film-still facelift: same floor plan, new architecture, PBR, much better doors, toilets
and arcade machines, and collision on everything solid. The owner picked moodboard F "Synthwave Grid"
(`artifacts/level4-facelift-20260930/moodboard/`), wants lights blinking here and there and half-dark places,
and approved LightingStyle Realistic for the place.

Build (headless; every step is idempotent and is skipped if its file is missing):
```
blender -b G:/Blender/Level4_Cinema/Level4_Cinema.blend -P build_all.py -- <out.blend>   # L4_BUILD_KEEP_GOING=1 to carry on past a failing step
blender -b <out.blend> -P export_l4.py                                                     # -> G:\Roblox\_local\l4blender\export
python make_place.py --tex-requests      # upload the listed maps with Studio MCP upload_image, then:
python make_place.py --tex-merge <answers.json> ...
python serve.py 8765  +  upload.luau (Studio)  ->  results.jsonl ;  python make_place.py ;  place.luau (Studio)
```
Pieces (each owns one collection; see the header of each file):
- `slots.py`: every PBR material slot + the export conventions (colliders, seats, tags, fixture lights).
- `make_pbr.py` / `make_pbr_all.py` / `pbr_spec.json`: albedo/normal/rough/metal sets from the Codex texture art.
- `import_meshy.py` + `meshy_specs.json`: the 9 Meshy props (arcade x4, toilet, urinal, popcorn, soda, projector).
- `arch_detail.py` (A): acoustic-panel facades with real magenta/cyan neon, coves, columns, mouldings, casings,
  nosings, handrails, bevels. `ceilings.py` (B): coffers, ACT + troffers, decks, bulkheads, fixtures + lights.
- `doors_v2.py` (C): every opening >= 9 studs is a mirrored pair of hinged leaves; leaf colliders ride on the leaves.
- `props_lobby.py` (D1): seats (Level4V4Seat), tables, cafe Seats, banquettes, stanchions, lightboxes, marquees,
  sconces, screens, projectors. `props_rooms.py` (D2): restrooms, concession, arcade, service.
- `props_decay.py` (F, written by Codex): decals, puddles, peeling sheets, cobwebs, rubbish, wear lanes.
- `Level4LightingController.client.lua` (installed in StarterPlayerScripts as "Level 4 Lighting Controller"):
  the interior grade while inside the model's BoundsCenter/BoundsSize; RoundUI stands down on the client
  attribute `Level4LightingOwned`.
Design plan and research: G:\Roblox\_local\l4facelift\r7.md (Roblox PBR/lighting/collision) and r8.md (element plan).

## Facelift v3 (2026-10-02): the owner's 15-point list

What changed (brief + per-point decisions: `artifacts/level4-facelift-v3-20261002/BRIEF.md`):
- Lighting: a Rolls-Royce starlight headliner everywhere except the Service room (stars = pooled Neon quads tagged
  `L4StarTwinkleA/B/C`, twinkled by the Level 4 Lighting Controller), neon as the main light, ~15 % of neon groups
  blinking hard off (`OccasionalFlicker`), the original preview's ceiling fixtures/lights no longer cloned (the
  "overlaps"). Gains in `make_place.py` (`LIGHT_GAIN` 2.7, star fill x5/3 brightness, longer reach, auditorium star
  fills hung at Y 80); controller grade `AMBIENT` (46,36,60), `EXPOSURE` 0.9, Atmosphere density 0.1 — all tuned in
  a Studio play test.
- One theme wallpaper (`WALLPAPER_MAIN` -> `wallpaper_synth`, dark plum with faded magenta/cyan triangles) on every
  plaster/wall surface; theme carpet on the gallery floor and core stair; concession checker floors/backsplash gone.
- Cinema 1's west side (C1, the passages beside the core) removed and sealed (`Shell/C1BlockWall*`), A1's west entry
  closed; projection booth front supports removed; counter 5 studs deep; arcade side walls solid with machines wall to
  wall and ONE centred door; ONE service door; restroom teal cap gone, urinals turned; gallery north wall curved like
  the south; CINEMA 2 marquee on the V-wall; the street entrance boarded up after a break-in; Meshy lockers at the
  gallery's east end; 264 Meshy litter props (no colliders) instead of the flat popcorn decals.
- Camera: Poppercam only stops at CanCollide parts with transparency < 0.25, so occluder colliders (visible layout
  walls/floors/roofs + Blender objects flagged `l4_occluder`) are now black, opaque, inset 0.1 stud inside the visual
  surface (`make_place.py` / `place.luau`). Verified in play: the camera stays under the restroom ceiling and in front
  of walls.
- `cull_hidden.py` (default visibility mode) removes geometry no camera position can see, proven per run by >= 150
  before/after Workbench renders with a magenta world (no new magenta, <= 0.1 % changed pixels per view). Pipeline:
  `build_all.py -> cull_hidden.py -> export_l4.py -> make_place.py`; see `G:\Roblox\_local\l4facelift\v3\final2\run.sh`.

Studio import changed (2026-10-02): the MCP `execute_luau` thread now has no Network capability, no `shared`
between calls and may not create Scripts under Workspace, so `serve.py` + `upload.luau` + `place.luau` no longer
run as-is. Use instead (the model must already exist; its `OccasionalFixtureFlicker` and `Doors.PushDoors` scripts
are kept and updated through ScriptEditorService):
```
python studio_upload.py [export_dir] --reuse results_v3a.jsonl   # chunks in the code payload; identical chunks reused by hash
python make_place.py                                             # after --tex-requests / upload_image / --tex-merge
python place_driver.py [export_dir]                              # stages the packet, then place_phases.luau: templates, placements, rest
```
Blender master: `G:\Blender\Level4_Cinema\Level4_Cinema.blend` = the v3 build (un-culled); v2 kept as
`Level4_Cinema_v2.blend`. `results_v2.jsonl` / `results_v3a.jsonl` hold the earlier mesh uploads.
