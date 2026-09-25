# Window Watcher white-eye placement

**Current rendering approach:** use the physical UV emission mask and installer described in [EMISSION_README.md](EMISSION_README.md). Native testing found the historical BillboardGui approach below invisible behind the tinted Glass. The coordinates and old renders remain anatomical references only.

## Historical anatomical measurements — superseded rendering approach

The following coordinates document the original marker study only. Its GUI rendering instructions are not the installation procedure; use EMISSION_README.md above. Historical local renders are not all included in this checkpoint.

Two temporary white emissive markers have been placed on the actual frozen mesh eye sockets, rendered and inspected at rest and during SlowWindowLean (frame 76). The original GLB and blend hashes are unchanged. This anatomical study did not alter the source GLB or blend. Later native preview work is documented separately.

At an 8-stud actor height, use these **Head-bone-local** Attachment positions when the native rig preserves serialized GLB bone-local bases:

| Eye | Head-local Attachment XYZ (studs) | Canonical actor rest XYZ (studs) |
| --- | --- | --- |
| RightEye | -0.135794744, 0.491177469, 0.181248844 | 0.130499989, 7.496333122, -0.367343307 |
| LeftEye | 0.117678143, 0.494406253, 0.183640093 | -0.122999996, 7.496333122, -0.368888646 |

Use `Attachment.CFrame = CFrame.new(x, y, z)`. Rotation is unnecessary for a camera-facing BillboardGui. Recommended white core diameter: **0.067 studs**, up to **0.075 studs** after distance QA. Set `AlwaysOnTop=false`, `LightInfluence=0`, and RGB255/255/255; retain normal wall occlusion. Add a subtle translucent halo if matching the Level1 style, without adding a scene PointLight.

The iris centers were identified in an orthographic render, raycast onto real mesh geometry, then offset 0.002 meters toward the face front to avoid embedding. All three nearby vertices sampled for each eye are 100% weighted to Head. `inverse(HeadRest) * eye` yields local offsets; evaluating the serialized GLB Head matrix independently agrees within 0.000000164 meters. **Do not rotate these local offsets by the actor/world conversion.** World/actor conversion X=-BlenderX, Y=BlenderZ, Z=BlenderY is already incorporated in the supplied canonical-actor coordinates.

If the importer rebases bone axes instead of preserving GLB locals, derive the offset from its native rest Head transform and supplied canonical actor coordinates: `nativeHeadRestWorld:PointToObjectSpace(actorFrame:PointToWorldSpace(canonicalActorStuds))`. Both parent and actor must be in the same rest pose; do not compute this from an arbitrary animated pose.

- `eye-placement.json`: source hashes, real raycast samples, rest matrices, per-eye Blender/GLB/actor coordinates, skin-weight evidence and QA status.
- `place_eyes.py`: reproducible read-only Blender authoring/render script.
- `rest-face-front.png`: unmodified face reference.
- `eyes-white-rest-front.png`, `eyes-white-rest-three-quarter.png`, `eyes-white-lean-three-quarter.png`: white-marker reference renders (3D ellipsoids, not a simulation of Roblox BillboardGui).

These outputs establish anatomical coordinates. Native temporary Animator binding has since passed 400 comparisons, while durable asset/client playback remains pending; the final design uses no eye attachments.
