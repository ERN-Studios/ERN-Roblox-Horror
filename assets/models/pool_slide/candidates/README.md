# Pool Slide gait v2 — isolated Studio A/B candidate

**Do not swap the current Walk/Run asset IDs yet.** Both v2 pairs have been uploaded as approved, active group-owned Animation assets and tested on copies of the current rig in an isolated Studio Play session. Neither has been installed on the active template or tested in an active Level 2 round. The [Studio A/B report](../../../../docs/POOL_SLIDE_AB_2026-09-24.md) has IDs, measurements and screenshots.

The v1 conversion from the recovered live clips treated missing pose tracks as a rest pose. The resulting Walk clip has **31 of 64** frames where all 20 bone rotations jump exactly to rest; Run has **19 of 39**. These frames alternate with actual gait frames, so a few selected stills can look fine while playback jerks and feet skate. [`v1_v2_pose_comparison.png`](v1_v2_pose_comparison.png) shows four such instants rendered headlessly in Blender; [`gait_v1_v2_comparison.png`](gait_v1_v2_comparison.png) shows the trajectory spikes.

[`pool_slide_scaled_walk_run_v2_dropout_repaired.glb`](pool_slide_scaled_walk_run_v2_dropout_repaired.glb) interpolates those absent bone poses between their two surrounding authored frames. The separate [`Walk`](animations/pool_slide_walk_1p20_v2-candidate.rbxmx) and [`Run`](animations/pool_slide_run_1p20_v2-candidate.rbxmx) KeyframeSequences carry the same fix. [`pool_slide_scaled_walk_run_v2_candidate.blend`](pool_slide_scaled_walk_run_v2_candidate.blend) is the editable Blender 5.2 file. The 20-bone names/hierarchy, both skinned meshes, geometry, bind matrices, in-place Root, keyframe times, and exact loop endpoints are preserved. **Idle and Attack animation payloads are byte-identical to v1**, including Attack's existing separate in-game `Contact` marker arrangement.

| Offline measure | v1 | v2 candidate |
|---|---:|---:|
| Walk all-20-bone rest flashes | 31 / 64 frames | 0 / 64 |
| Run all-20-bone rest flashes | 19 / 39 frames | 0 / 39 |
| Walk lowest skinned sole relative to −7.20-stud rest floor | −0.329 stud | −0.164 stud |
| Run lowest skinned sole relative to rest floor | −0.255 stud | −0.119 stud |
| Walk duration | 1.033333 s | 1.033333 s |
| Run duration | 0.633333 s | 0.633333 s |

The residual sole dips and slip still need native review. Using the current provisional `WalkAnimationReferenceSpeed = 14.85` and `RunAnimationReferenceSpeed = 36.8` studs/s, the fixed Walk stance bone advances about 15.1–15.4 studs/s, close to its reference. The sampled Run stances differ: left about 38.4, right about 50.3 studs/s; the right foot can still slide roughly 1.2 studs over a 0.10-second contact window. These numbers come from offline mesh/bone reconstruction, not Roblox Animator playback, collision, or a physical device. In Studio, check Walk at 10 and Run at 20/32 studs/s, transitions/turns, floor placement and chase clearance before choosing whether to author a further foot-contact pass. Do not solve the visual artifact only by changing playback speed; the all-bone rest flashes are embedded in the current animation asset data.

Validation: the glTF validator reports zero errors and zero warnings (two informational unused UV notices); generated Roblox XML has 20 unique poses per frame, orthonormal CFrames, exact reconstruction to the GLB, and zero horizontal Root motion. Blender 5.2 headlessly reopened the candidate `.blend` with two weighted meshes, 20 bones, and four actions. [`repair_report.json`](repair_report.json), [`animation_validation.json`](animation_validation.json), and the full [v1](gait_analysis_v1.json)/[v2](gait_analysis_v2.json) measurements are retained. The v2 GLB SHA-256 is `f620805f7558340731890ae60ffc70a7089a6aeaf1057b1e9335d510be619bdb`.

Rebuild from the unchanged v1 GLB:

```powershell
python tools/pool_slide_repair_sparse_pose_dropout.py assets/models/pool_slide/pool_slide_scaled_walk_run_v1.glb assets/models/pool_slide/candidates/pool_slide_scaled_walk_run_v2_dropout_repaired.glb
python tools/pool_slide_glb_to_rbxmx.py assets/models/pool_slide/candidates/pool_slide_scaled_walk_run_v2_dropout_repaired.glb assets/models/pool_slide/candidates/animations --label v2-candidate
```

The isolated Studio test has finished and the current rig/IDs were preserved. If this fix is accepted, only the Walk/Run animation IDs need replacement, followed by fresh conflict checks, native active-round tests, physical-device checks and a separate publication receipt. Keep the current group model ID `95190427565492` out of the live template because its imported bones were incomplete.
