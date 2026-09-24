# Pool Slide v2 — ScaleTo(6.6) A/B candidate (offline)

This is a **second Walk/Run XML pair**, derived from the [dropout-repaired v2 candidate](../README.md) for comparison on Claude's current 20-bone Studio rig (`Model:ScaleTo(6.6)`, visually 1.10× the former scale-6 template). It is not uploaded or installed. Current Animation IDs remain `103719823156557` / `128800704640816`.

The original v2 GLB baked a 1.20× multiplier into all animation translations. [Roblox documents](https://create.roblox.com/docs/reference/engine/classes/Model) that the Model scale factor also applies to animation joint offsets under an `AnimationController`. This variant divides **Pose.CFrame X/Y/Z by 1.20** to test whether the baked scale causes the observed foot dip on the scaled Studio model. This is a test hypothesis, not a claim about the resulting in-game foot position.

| Clip | Offline file | SHA-256 | Frames / poses |
|---|---|---|---|
| Walk | [`pool_slide_walk_v2-scale-neutral.rbxmx`](animations/pool_slide_walk_v2-scale-neutral.rbxmx) | `d6e2c8fa19ac7cbd7ea1c5a9abbdcbd6103325df825c66c19230735865b6dccc` | 64 / 20 each |
| Run | [`pool_slide_run_v2-scale-neutral.rbxmx`](animations/pool_slide_run_v2-scale-neutral.rbxmx) | `2f1e1d85d819bbe099be986a8be5d41fbb69f85b9a3daa8ddff6b919e5ac2f0a` | 39 / 20 each |

Frame times, bone hierarchy/names, all rotation matrices, easing, priority, loop flag and exact loop seam match the first v2 candidate. The XML validator checked orthonormal CFrames and 20 unique poses per frame; independent post-serialization comparison checked every rotation and timestamp unchanged and every translation equals v2/1.20 to <1e-8. See [`validation.json`](validation.json). Idle and Attack are untouched.

When Claude has finished using Studio, test the first v2 and this scale-neutral variant on the **same** current Studio rig and exact seeded movement at walk 10, chase 20 and enraged 32 studs/s. Measure `Bone.Transform.Position`, skinned sole clearance and contact-window horizontal displacement; choose only after native playback. The GLB/Blender v2 render is not a preview of this XML-only variant's effective Roblox pose.

Rebuild locally:

```powershell
python tools/pool_slide_retarget_pose_translation.py assets/models/pool_slide/candidates/animations assets/models/pool_slide/candidates/scale-neutral/animations
```
