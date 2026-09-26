# Exact Window Watcher GLB → Roblox EditableMesh transfer

This is an import of the real, frozen Meshy model with its authored Blender rig. It does not replace the model with primitives, regenerate the shape, decimate it, merge seams, or re-rig it.

**Status 2026-09-26:** durable mesh **138178192370575** and the three published clips are installed in Studio with the intermittent encounter and visual client. The normal CreateAssetAsync beta blocker is resolved. The [main handoff](../../../../../docs/LEVEL5_WINDOW_WATCHER_2026-09-25.md) records final QA and experience publication. The procedure below is for recovery; reuse existing assets and reconcile fresh Studio state before rebuilding.

## Frozen input and evidence

- Input: `../../model.glb`
- SHA-256: `cbf260ff36b8c7226f27271456eae6bf4db7fd266bdce82dda8b0eae7cbc051e`
- Serialized GLB: **8,996 vertices, 11,862 triangles, 25 joints**. Blender's 8,968 vertices become 8,996 on export because normal/UV seams split vertices. These serialized vertices are intentionally preserved.
- Each vertex has at most four nonzero weights. The maximum original weight-sum error is `1.150183379650116e-7`; no weights are intentionally altered.
- Texture: `texture-0.png`, **5,952,974 bytes**, SHA-256 `3229b3bc4eec4498379348bcfabb74dfac136dc1ab51d8a18cb073c34bb01133`. This is byte-identical to the uploaded `../../WindowWatcher-basecolor.png`, Roblox image **91091934459636**.
- Rig bind matrices require an epsilon orthonormalization for Roblox CFrame: maximum rotation-element change **3.381202993701926e-6**. Thus this is exact geometry/UV/normal/weight transfer with a documented tiny rigid-bind correction, not a claim of mathematically lossless material or non-rigid matrix parity.

`convert_exact_glb.py` reads the actual binary accessors and embedded image bytes. Its six vertex chunks, four triangle chunks, material metadata, and clip files have byte lengths and SHA-256 values in `manifest.json`.

## Coordinate contract

The source model is 2.4 meters tall, faces GLB +Z, and has its feet at Y=0. Conversion applies an eight-stud target height and a Y half-turn:

`actorPosition = (-sourceX, sourceY, -sourceZ) * (8 / 2.4)`

The converted actor faces **−Z** and has Y bounds approximately **0…8**. To remove engine mesh-centering ambiguity, the importer explicitly subtracts the measured AABB center from **both vertices and mesh-world bind frames** before creating the EditableMesh. The center is approximately `(0,4,0)`.

- EditableMesh vertex and bind coordinates: centered around zero.
- MeshPart.Size: exact native MeshSize, asserted against manifest bounds.
- MeshPart.CFrame: `actorFloorCFrame * CFrame.new(center)`.
- MeshPart.PivotOffset: `CFrame.new(-center)`.
- Top-level runtime Root Bone: centered root bind frame.
- Child runtime Bones: manifest parent-local rest frames, unchanged by centering.
- Model PrimaryPart: that MeshPart, giving a floor-origin pivot.
- To position the finished model: `model:PivotTo(actorFloorCFrame)`.
- To play a pose: `Bone.Transform = localDelta`, using the provided stud-scaled clips.

Uniform world rotation does **not** conjugate bone-local animation rotations. The delta rotations retain the actual serialized GLB local bases. Only their translations are scaled to studs. Previous expanded/compact Blender coordinate audit remains in `../../`.

## Bounded Studio execution

The parent controller owns all Studio changes. This helper returns a module; loading the source alone imports or publishes nothing. Each call processes one bounded chunk.

```lua
local H = game:GetService("HttpService")
_G.WWImport = loadstring(H:GetAsync("http://127.0.0.1:8769/mesh-import/import_exact_mesh.luau"))()
print(H:JSONEncode(_G.WWImport.begin("http://127.0.0.1:8769/mesh-import/")))
```

Then call `nextVertices()` **six times**, and `nextFaces()` **four times**, in separate tool invocations or a bounded call. Use `report()` for counts and progress.

```lua
-- Explicit owner-authorized upload to group 1039373905:
print(H:JSONEncode(_G.WWImport.publishMesh()))
-- Explicit published-asset readback; can be retried while asset processing runs:
print(H:JSONEncode(_G.WWImport.verifyPublished()))
-- Requires that readback to pass. Returns an UNPARENTED model for review.
local model, info = _G.WWImport.buildRuntime(91091934459636)
print(H:JSONEncode(info))
```

`getModel()` returns that model. `applyPose("WatchingIdle",1)` applies the lowered-arm initial pose for Edit preview. This direct Bone.Transform preview may be overridden by an Animator in Play. Publish the animation KeyframeSequences using the parent's separate helper and verify actual Animator playback in Play.

`verifyPublished()` checks the reloaded mesh's vertex, triangle and bone counts; bounds center and dimensions; all 25 bone names, bind frames and parent relationships. A failure leaves the asset available for diagnosis but prevents `buildRuntime()`. Native renderer/published animation visual QA is still necessary; source compilation is not proof of runtime success.

### Explicit temporary preview when upload is unavailable

After all ten chunks are loaded, `buildPreview(91091934459636, actorFloorCFrame)` constructs the same rig directly from `Content.fromObject(S.mesh)`. This call is Studio-only and creates an unparented model named `WindowWatcher_TemporaryStudioPreview`. Both the model and MeshPart have `TemporaryStudioPreview=true`, and the model's `PersistenceStatus` explicitly says it is not a published asset. `getModel()` and `applyPose()` work on this preview for local visual QA.

The preview has no durable mesh ID. It is not a workaround for asset publication and must not be treated as preserved by saving/publishing the containing place. See the parent integration README for the existing durable asset IDs and recovery prerequisites.

`discardPreview()` explicitly destroys this helper-created preview and clears its pose target, retaining the editable mesh so a later verified runtime model can be built. `destroy()` refuses while a preview is still attached to the session; discard it first. Otherwise `destroy()` only destroys the helper's temporary EditableMesh and clears its session reference. It does not delete a returned published model or uploaded asset.

## Material and eyes

GLB normal and UV coordinates are copied without a UV flip. The single embedded PNG is shared by its base-color and emissive slots. Roblox applies it as the body's albedo; the source GLB's broad emissive/specular/IOR extensions are archived in the manifest, not claimed to be reproduced by TextureID. This keeps the body dark under room lighting while the requested eye glow is added separately.

Eye glow uses the separate UV emission mask described in `../eye-placement/EMISSION_README.md`. Estimated attachment coordinates were removed from the manifest. The importer creates no eye attachments; emission follows the actual skinned iris surface.

## Official API evidence and restrictions

- [EditableMesh](https://create.roblox.com/docs/reference/engine/classes/EditableMesh): AddBone supports Name, ParentId, CFrame in mesh-local bind space, and Virtual; assign vertex bone IDs before weights.
- [AssetService](https://create.roblox.com/docs/reference/engine/classes/AssetService): CreateAssetAsync supports EditableMesh as Mesh and creator metadata; the docs limit this creation route to locally loaded plugin context. This route produced durable mesh 138178192370575 after the normal beta feature was enabled. Any future upload still requires its own verified receipt and readback.
- [Roblox skinning API announcement](https://devforum.roblox.com/t/studio-beta-introducing-skinning-and-facs-data-support-for-editablemesh-objects/3731147): embedded mesh bones and runtime Bone instances are distinct; they bind by unique names.
- [StudioService](https://create.roblox.com/docs/reference/engine/classes/StudioService) and [File](https://create.roblox.com/docs/reference/engine/classes/File): PromptImportFileAsync is a PluginSecurity native picker returning a File, not an arbitrary filesystem-path GLB decoder. It does not bypass the blocked native picker.
- [Open Cloud Assets](https://create.roblox.com/docs/cloud/guides/usage-assets): authenticated Model creation supports GLB/GLTF/FBX, but requires an authorized API key or OAuth. No credentials or browser cookies were accessed. The in-Studio EditableMesh route uses the already authorized Studio context.

The links above identify the official API evidence. No undocumented internal file-import API is used.
