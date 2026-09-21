# Level 3 table-hiding hold

## Current asset — 16 September 2026

Roblox animation **119040885264927**, owned by **ERN Roblox Studios**, group **1039373905**. Publication succeeded and MarketplaceService confirmed asset type 24 and the group creator. `published-animation-v2.json` records the receipt.

- `zyntra-table-hide-v2.blend`: actual StarterCharacter meshes, measured AnimationConstraint rig and actual Level 3 folding table; textures packed, existing scenes preserved.
- `hide-hold-v2-keyframes.json`: 121 evaluated frames at 30 fps, four-second Action hold with subtle breathing. No entry/exit sequence or root drift.
- `authored-actual-pose.json`: fitted transforms using actual mesh convex hulls, including three seam liners.
- `actual-bake-validation.json`: every mesh vertex checked throughout the loop. Floor clearance 0.0415 stud, collider clearance 0.0538, maximum lane |X| 1.4908 and depth |Z| 2.0298. Physical table and sight occluder contain this depth. Roundtrip error 5.07e-7.
- `actual-character-table-final.png`: actual mesh/table authoring preview. Final gameplay evidence goes in `artifacts/trello-20260916/animation-native-qa.md`.

Native exports: `_local/trello-20260916/character-export`. All 18 meshes match measured positions and dimensions within 0.00004 stud. Studio OBJ export omits SurfaceAppearance tint; the Blender preview restores measured colors. These are existing game textures.

## Authoring and runtime

Use `tools/build_actual_table_hide.py`, `fit_actual_hide_pose.py`, `preview_actual_hide_pose.py` and `bake_actual_hide_pose.py` through the active Blender MCP bridge. The fitter uses task-local SciPy under `_local/trello-20260916/python-deps`.

Publish with `tools/publish_table_hide_animation.py --coordinated-edit-window --version v2`. The uploader refuses repeat publication when a receipt exists and checks the experience owner.

The server places the root at floor +2.20 and starts the Action track. Clients defer to the loaded, fully weighted track; the procedural fallback now copies v2's fitted pose. Ordinary crouch retains its previous gait. Existing controller cleanup owns exit, death and character replacement.

## History

v1 files and animation **113160394754713** remain as history. That preview used bounding-box proxies. v2 uses actual geometry, a forward gaze and arms drawn forward. v1 is no longer the configured hold.
