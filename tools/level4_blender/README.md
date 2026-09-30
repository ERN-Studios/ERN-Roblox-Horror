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
