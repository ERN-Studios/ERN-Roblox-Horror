# PoolSlide phase-grid: reuse of saved mesh and skin evidence

Read-only inspection, 10 September 2026. No Studio, Mesh/Image API, animation, flags or runtime files were changed.

## Conclusion

The saved artifacts do **not** contain enough raw geometry to calculate the proposed new Idle-to-Walk phase-grid skin bounds without obtaining the mesh data again. Existing validated cases can be reused as references. Bone poses and previous skin envelopes cannot reconstruct a new blended skin envelope or certify its minimum floor clearance.

## Evidence inspected

All 19 `pool-slide*.json` files in this directory were parsed: 6,917,318 bytes in total. None contains the probe's `geometry`, `influences`, `offset`, `vertexId`, `vertexBones`, `vertexWeights`, `binds`, `bind` or `raw` fields. A recursive artifact-file inventory found no mesh/model export with `.fbx`, `.obj`, `.glb`, `.gltf`, `.blend`, `.mesh`, `.rbxm`, `.rbxmx`, `.bin`, `.zip` or `.gz` extension. These inventory checks are supported by reading the actual probes and report shapes, rather than relying on field names alone.

The complete native reports measured two meshes: `Mesh_0` (`rbxassetid://108970159979893`, 13,105 vertices) and `Mesh_02` (`rbxassetid://91916953208682`, 1,986 vertices). The 15,091 per-vertex influence records were never serialized. `result.bones` stores 20 names and rest positions; the fresh realtime report also stores bone world matrices and local transforms. Neither supplies the inverse-bind vertex offsets and skin weights needed to reconstruct every vertex.

`pool-slide-original-authored-clips.json` preserves authored keyframes, pose CFrames, easing and Pose weights. These are animation data; Pose weights are not mesh skin weights. `pool-slide-contact-candidate-data.json` preserves root/contact corrections and anchor measurements, also not skin geometry.

In the unchanged `pool-slide-idle-walk-phase-grid.luau`, `geometry` is local at line 91. The probe creates EditableMeshes at line 99, reads vertices at line 132, reads vertex bones/weights at line 140, and builds influence offsets at line 150. Only mesh counts/mapping diagnostics are added to the result around line 163. Measurements serialize the resulting envelope and foot minima around line 374. EditableMeshes are destroyed at line 404. The original scale-six and fresh-realtime probes follow the same pattern.

## Evidence that can be reused

`pool-slide-transitions-fixed-full.json` already contains 72 valid transition cases, 1,224 validated samples and zero maximum weight error. Its four Idle-to-Walk cases all start incoming Walk at phase zero, with outgoing Idle phases 0, .25, .5 and .9999. Their minimum floor gaps are approximately +.03076, -.13170, +.03295 and +.03076 studs. These four cases are useful baseline references and need not be represented as new measurements.

The proposed grid crosses those four outgoing phases with incoming Walk phases 0, .25, .5 and .75. The other 12 combinations have no saved full-skin measurements. Seven valid fresh realtime cases also already establish the default fade and rejected shorter-fade comparisons. The earlier dense report's invalid blend checks must not be used as accepted transition evidence.

## Bounded options

With the setting kept off, existing clip data still support clip reconstruction, bone/weight/phase/endpoint checks and visual review on a disposable Play clone. Those would be bone/visual checks, not full-skin floor-clearance acceptance.

A future authorized raw-cache export could reuse the current validated reconstruction without a new framework: store each mesh identity and count, scale/rest fingerprint, and every vertex's bone-name, inverse-bind offset and skin weight (plus its existing foot classification). Validate complete coverage, weight sums and rest mapping when loading, then rebind bone names to the current clone. No such cache has been produced here. A separate authorized mesh-data source would be required before claiming a new full-skin phase-grid result.
