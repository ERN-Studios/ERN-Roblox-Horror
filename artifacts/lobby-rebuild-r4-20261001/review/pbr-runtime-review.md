# Independent R4 PBR pipeline review

Reviewed 2026-10-02. This is a local source/export review; no Studio writes, imports, source/editor parity claim, publication, or Play validation occurred in this review. Exact input hashes and the numeric checks are in `pbr-package-audit.json`.

## Runtime blocker

The initial RuntimeBake `bbdb3ea1375e3ad8ebe923ae7351d2fbd91575661d5e005c37535b6fb0a90c6e` converted each PBR map into opaque DataModel content and destroyed its EditableImage before calling CreateSurfaceAppearanceAsync. That constructor currently accepts Content wrapping EditableImage only; ColorMap, NormalMap and RoughnessMap are supported keys. Opaque maps and direct asset IDs are not supported constructor inputs. The revised `f3f39ad9212ac24de041fe06b777a747ea8f2377ecad4c7856b20a03e4eae1a5` fixes constructor input and keeps all nine images alive. [Official AssetService source documentation](https://raw.githubusercontent.com/Roblox/creator-docs/main/content/en-us/reference/engine/classes/AssetService.yaml).

The retained EditableImage route still does not establish multiplayer rendering: Content.Object values do not replicate their pixel contents, and clients receive unusable placeholders. The constructor returning a SurfaceAppearance is insufficient proof. The staff announcement demonstrates this API in a LocalScript. Use uploaded static PNG maps assigned to editor-authored SurfaceAppearance templates, then clone those templates onto the runtime architecture chunks. If testing the dynamic route, inspect client-rendered textures and map Content.SourceType in actual server/client Play first. [Official Content documentation](https://raw.githubusercontent.com/Roblox/creator-docs/main/content/en-us/reference/engine/datatypes/Content.yaml), [Roblox staff announcement](https://devforum.roblox.com/t/in-experience-build-a-texture-editableimage-support-for-surfaceappearance/3866947).

## Lifetime and memory

Destroying an EditableImage immediately destroys its contents. Content.fromObject provides strong shared ownership, but cannot rescue explicitly destroyed contents. The revised retained-image list with cleanup on kit destruction and failure respects this requirement. Kit destruction must occur only after its cloned preview consumers are removed. Server, Studio and plugin editable-memory budgets are unlimited; client budgets remain device-dependent. [Official EditableImage documentation](https://raw.githubusercontent.com/Roblox/creator-docs/main/content/en-us/reference/engine/classes/EditableImage.yaml).

Nine 1024×1024 RGBA images require 36 MiB raw pixels. The atlas requires another 4 MiB during editing and retains baked static content afterward. At least another 8 MiB of temporary decoded/copy buffers exists during writes; the atlas buffers currently remain in the surrounding function scope during the bake. These numbers exclude source StringValues, decompression/hash allocations, renderer copies and engine overhead. The dynamic SurfaceAppearance API does not provide compressed maps or mipmaps and can use considerably more GPU memory than published appearances. Three shared static template materials fit this authored-lobby use better.

Opaque mesh and atlas content creation remains appropriate: meshes reference content through MeshContent and the atlas uses TextureContent, preserving reference ownership. These session-scoped values must be regenerated per server, not saved as a deployment baseline. [Roblox staff DataModel content announcement](https://devforum.roblox.com/t/full-release-introducing-createdatamodelcontent-convert-editable-mesh-and-image-data-into-static-content/4541898/1).

## Color, UVs, normals and export

All nine current runtime buffers exactly equal the corresponding PNG bytes after Pillow RGBA decoding. Rows are top-down, alpha is 255, roughness is replicated to RGB, and no gamma conversion or normal-channel flip occurred. RuntimeBake preserves top-down PBR rows and retains the separate legacy atlas bottom-up conversion.

The importer converts Blender V to `1-v`; the exporter applies a proper X/Z/−Y rotation with determinant +1. OpenGL normal maps retain their green channel. A UV coordinate-system conversion is not by itself a reason to invert that channel. The tunnel and road use ten-stud repeats, matching analytic tunnel UVs; forty-stud prefab steps divide the repeat. Sidewalk repeats at eight studs and the same forty-stud steps also preserve phase.

Every actual PBR chunk passed independent numerical checks for nondegenerate triangles, noncollapsed UV triangles, unit corner normals and normal direction consistent with winding. Smooth shell normals remain radial across material export copies. These checks do not prove that Roblox generates a correct tangent frame from EditableMesh normals and UVs. The API exposes no tangent setter in its documented interface; verify visible relief with grazing light and confirm seams in actual Play. The manual FBX export currently omits `use_tspace=True`, so explicit tangent export should be enabled if that fallback is used. [Official SurfaceAppearance normal documentation](https://raw.githubusercontent.com/Roblox/creator-docs/main/content/en-us/reference/engine/classes/SurfaceAppearance.yaml).

## Concrete package and Builder assumptions

The pack contains scanned concrete color, genuine 16-bit height, OpenGL tangent normal and roughness maps; asphalt and sidewalk use separate scanned sets. Heights remain genuine editing/bump assets in Blender while normal maps provide relief in Roblox. The architecture has three PBR materials and 48 placed PBR mesh parts. Other props retain their atlas and the themed bays retain original published color texture assets.

The complete package is 71 chunks in 54 families, 66,872 unique triangles, 217,804 placed triangles and 351 placed visual mesh parts. Largest chunk is 9,844 triangles. Material splitting adds parts and possible draw calls; measure actual client rendering and server construction times instead of inferring performance from triangle count alone.

VinylDiscAmber, VinylDiscCyan, HologramRing and HologramBand each remain single atlas mesh parts. Builder's direct CFrame, Material and Size accesses for those families therefore match this manifest. Composite families use identity-pivot Models and per-part centered offsets, preserving their assembled local positions.

## Required live checks

1. Fresh source/editor parity and full native recovery checkpoint before installing any candidates.
2. Actual client Play showing correct concrete color, pore relief, matte roughness and aligned shell-section seams under grazing light.
3. Server/client visibility and late-joining/streamed-in visibility of every PBR map; no checkerboards.
4. Construction latency, image budget/engine errors and frame/memory measurements with the original lobby still present.
5. Normal player viewpoints on both sign approaches and all queue/DJ interactions; this review does not substitute for those checks.
