# Zyntra table-hiding hold — Blender MCP authoring

Trello #99, coordinated with A80's #80 placement fix. **Authoring complete; native Roblox validation and asset publication pending.**

- `zyntra-table-hide-v1.blend`: separate authoring project, preserving the original Blender scene. New scene `Zyntra_TableHide_20260915`, action `Zyntra_TableHide_Hold_4s_v1`.
- `hide-hold-keyframes.json`: 121 evaluated frames at30fps, four-second seamless Action-priority loop. Pose hierarchy uses R15 part names, with corresponding joint names in metadata.
- `authored-pose.json`: parameterized tucked pose fitted against actual measured Attachment0/1 transforms and MeshPart bounding sizes.
- `bake-validation.json`: full-loop geometry/round-trip measurements.
- `hide-hold-preview.png`: **bounding-box proxies only**, a cutaway authoring view; not proof of final mesh appearance.
- `blender-build-result.json`: actual successful MCP result.

## Method and constraints

Read-only capture of the live game's real R15 AnimationConstraints, scale1 and HipHeight2.60477 is in `artifacts/trello-20260915/codex-hiding-rig.json`. Reconstructed attachment rest hierarchy, created a matching Blender armature and rigid weighted geometry proxies, authored the crouched hold with subtle breathing, and baked evaluated Blender pose matrices back into Roblox joint-local space. Scripts: `tools/prepare_table_hide_pose.py` and `tools/build_table_hide_blender.py`.

Across121frames: body bounding boxes stay at root-space Y −2.17990…+0.47179. With root at floor+2.20, minimum floor clearance0.0201 and minimum table-collider clearance0.0882stud. X −1.45187…+1.50052 fits the two lanes with ample separation. Z −2.05313…+1.92713 exceeds the logical3stud hide-volume depth but remains within the physical table±2.30 and sight occluder±2.15. Final native visual checking must confirm concealment. Decorative seam liners are excluded from the proxy analysis and must also be visually checked.

Loop endpoints are identical. Maximum Blender/Roblox transform round-trip error2.53e-7. Root has no animation drift. The player is teleported into the lane by the server before this hold; no walking/crawling entry clip is included. Exit must stop the track immediately.

## Integration requirements for A80/Fable

1. Publish the KeyframeSequence as an Animation under creator group1039373905, matching the experience owner. Record the actual id and ownership response. Do not invent an id.
2. Add a replicated configuration seam for the local client; a client cannot directly require ServerScriptService's Configuration. Server can publish a validated animation id attribute or shared config value.
3. Use the player's server-created Animator and Action priority, Looped=true. Ensure the procedural writer **does not overwrite the playing hide track on observing clients**. The existing all-client hidden pose writer would otherwise defeat replication. Ordinary crouch must keep working. Failed/missing track uses the procedural pose fallback, with observable readiness rather than assuming LoadAnimation success means content ready.
4. Clean track/instance/state on exit, death, character replacement, level transitions and failed load. Do not alter camera, prompt/exit interaction, occupancy, lanes or server hiding security.
5. Verify actual avatar mesh under both table orientations/lanes and through a full loop. Test exit, re-entry, death/flush and fallback. Verify animation permission/content load and actual track weight. Cross-client visual evidence remains required if feasible; do not claim one local client proved replication.

Roblox's [AnimationConstraint reference](https://create.roblox.com/docs/reference/engine/classes/AnimationConstraint) documents the joint transform/Animator relationship.
