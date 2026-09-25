# Level 5 — Window Watcher asset and reference courts

## Delivery state

The F-court replacement is installed and tested in Studio. The model has now also been rebuilt exactly in a **temporary Studio preview**, with white emissive eyes and all three clips validated through native Animator stepping. **The durable mesh/animation assets are not uploaded, the intermittent encounter drafts are not installed, and current F changes are not published.**

The upload API fails because the normal Studio **CreateAssetAsync Lua API** beta is visibly unchecked. Native UI automation cannot toggle its row reliably; the owner has been asked to enable it and save/restart if requested. Last independently verified game publication remains **v2104**.

The prepared package is `assets/level5/window-watcher/roblox-integration/`, including exact mesh/skin transfer, white-eye UV masks, runtime drafts, upload tools, tests and completion steps. `artifacts/level5-window-watcher-20260925/integration-assets.json` lists the uploaded image IDs and explicitly leaves mesh/animation IDs empty. This is a recoverable checkpoint, not a claim the entity is playable.

## Meshy and Blender

The installed Blender 5.2 LTS background `bpy` connection was executed successfully. No additional MCP addon was needed. Meshy CLI 0.4.0 was authorized through the owner's device flow; no credentials or expiring download URLs are included in this repository.

| Stage | Resource / task | Actual cost |
| --- | --- | --- |
| Textured A-pose model | `image-to-3d` / `01a0d8e3-3fdd-752a-b810-ea9cace0266e` | 15 credits |
| Skeleton and automatic weights | `rigging` / `01a0d8ec-0c4f-71fc-b513-af1e1d1e59b4` | 5 credits |

Three window clips were authored in Blender, without paid Meshy animation tasks: WatchingIdle (6s), SlowWindowLean (5s), GlassTap (4s). The final custom NPC is 2.4m tall with one 11,862-triangle mesh, 8,968 vertices and 25 bones. Original Meshy bone names are retained; an unweighted Root was added and an unrelated Icosphere helper removed. All vertices have normalized weights with at most four influences. The rig has no finger bones; tapping uses hand/wrist motion.

Files are in `assets/level5/window-watcher/`: editable `.blend`, model GLB/FBX, one FBX per animation, exact base-color texture, source references, Meshy source models, compact 30fps pose JSON, preview renders and reproducible Blender scripts. Expanded matrix evidence is stored as `animation-transforms-30fps.json.gz`.

Blender QA passes: fresh reimport of GLB/FBX and each clip preserves the hierarchy and movement; feet/root remain planted; loop endpoints and shared starting pose agree. Full-frame glass-clearance inspection caught and corrected a fingertip overshoot during the arm's raising arc. Final renders were visually inspected. These checks establish the local files, not native Roblox playback.

## Coordinate and import contract

Frozen GLB SHA256: `cbf260ff36b8c7226f27271456eae6bf4db7fd266bdce82dda8b0eae7cbc051e`.

The compact `*-roblox-30fps.json` files derive pose deltas against the actual serialized GLB joint-node matrices and inverse binds. Use them instead of guessing a world-axis conjugation for bone-local rotations. Each pose is `[boneName, tx, ty, tz, qx, qy, qz, qw]`, with translation in metres. Compare native imported Bone rest CFrames before uploading KeyframeSequences; scale translations and the rig consistently.

Target prepared actor height is 8 studs, bottom pivot at the floor, facing local −Z. The model's GLB world-facing direction is +Z, so inspect the importer and normalize the full model orientation. Do not resize only MeshPart.Size. At 8-stud height, whole-mesh forward extrema are −0.763673 studs idle, −0.779343 lean and −1.745002 tap. The F panes are 0.14 studs thick. The uninstalled draft uses inward depths 0.95/0.95/1.90; tap therefore keeps its nearest evaluated fingertip 0.154998 studs behind the pane centre, beyond its rear surface at 0.07. These are provisional placements until the actual imported actor and clip are inspected in Studio.

All three anchors reference the real tinted pane through an ObjectValue. The planned actor X offset is 1.1 studs to avoid the central mullion. Preserve dark tinted Glass, existing crossbars and unlit houses. Check the face/palm from both the balcony and the ground, including the entire raising/lowering arc.

## Area F

The former tall canyon is replaced with 33 nested domestic houses around three connected carpet courts. Floors at 0/15/30 studs, continuous white balconies, two switchback stair circuits, short bridges, sage/rose/oatmeal façades and dark gabled roofs match the concept's architectural language. One office-style shared ceiling sits at 60 studs. House Lights/Neon remain absent. Three F mold carriers were resized for the lower enclosure.

Current map, before actor staging: 11,372 BaseParts, 12,240 descendants, 44 actual lights and 202 standard tinted panes. Map footprint is unchanged. Canonical native geometry comparison confirms A–E, G and H exactly match the baseline; outside F only the three named Canyon mold carriers changed.

Actual Humanoid traversal passed 44 movement segments: 11 ground route, 18 stairs/upper bridge, 15 middle bridge/house interiors. No required jumps or noclip; only the start of each separate route was positioned. Hold-L returned to the lobby, removed the generated world and left phase IDLE. Entry inspection covered 77 open homes and 462 rays with no foreign obstruction or embedded sample. The existing chute still passed 98 enclosure rays.

Furnishing inspection retained 20 furnished homes, 891 furniture parts, 7,128 corner checks and 72 mold-backing rays. The first report exposed four obsolete test assertions: three pane-reference ObjectValues were treated as panes, and the old total was 356. The test now checks actual BaseParts and expects 202 panes; the adjusted test was rerun through the real Level 5 developer round and passed with zero failures. Source compilation passed 182/182 scripts; the existing access/transport test passed 74 assertions.

## Preserving Studio and completing integration

Fresh baseline and current export matched Source/editor for all 182 scripts. Exactly Architecture and Landmark Districts changed; the other 180, including all 12 Level 4 scripts, are unchanged. Native pre-task backup is 9,635,146 bytes and exactly matches `artifacts/level5-qa-20260925/after.rbxl` (SHA256 `a2ffc35f2e9e443e2946f2582158808028c3a4d7ac67dca384f59b45e9c351d0`). Current map changes are completely represented by the two exact source exports. A new full native backup is required after the imported mesh/animations are in place.

Remaining integration: enable the normal upload beta and publish the exact mesh under game group 1039373905; verify the published mesh round trip and final material filtering; publish and play all three durable clips in a round; prepare `ServerStorage.Level5WindowWatcher.WindowWatcherRig` plus sibling `Animations`; install/review the staging module and call it from the developer-only Adapter; verify cleanup, rendering, visibility, collision and re-entry; rerun relevant checks; save a native after-backup and publish to existing place 131311258779917 with a verified receipt.

Physical mobile/tablet performance, two-account human multiplayer and published-server asset permissions have not been tested. Git delivery is a reviewable work checkpoint, not evidence that the pending import or publication is complete.

## Intermittent encounters and white eyes — follow-up checkpoint

The uninstalled encounter module shows one actor at a time at the three F panes: first appearance after 2–4 seconds, visibility 8–14 seconds, then 18–35 seconds hidden. It requires a living Level 5 participant in F with line of sight to a real pane. Cleanup owns all tracks/connections. No chase, damage, sounds or rewards were added. The draft passes 1,031 scheduling and 29 lifecycle assertions.

The exact native EditableMesh has 8,996 serialized UV-split vertices (the Blender topology count is 8,968), 11,862 triangles and 25 bones. Temporary Animator tests verified Idle/Lean/Tap at four times each, plus the alternative parent-pose hierarchy for Idle: 400 bone comparisons, worst component error 0.0002191. Root directly under Keyframe binds correctly. These are Studio Edit temporary IDs; published-client playback/permissions remain pending.

White eyes use SurfaceAppearance emission on the actual iris UVs, with no physical Lights or GUI. The original Billboard approach was rejected because Glass hid it. The selected v5 mask is 91743869995723; basecolor 91091934459636 is unchanged. Strength 200 produces white cores and has been previewed. Targeted UV guarding preserves 98.34% mask energy. Check the small brow-filtering artifact again after the new material pack finishes processing before final visual sign-off.

A fresh 182-script export has no Source/editor conflicts and no changes since the previous committed F checkpoint. The latest origin/claude/trello-20260921 remains a8259d3; unrelated developer work is preserved. Temporary preview actors/test fixtures are removed at handoff; no provisional actor or HTTP setting should be saved in the game.
