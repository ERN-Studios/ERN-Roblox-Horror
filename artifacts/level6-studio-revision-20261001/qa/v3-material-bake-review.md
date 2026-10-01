# Level 6 raw image bake gates

**2026-10-01 Play result: blocked.** A real server Script could not assign
`MaterialVariant.*MapContent` (`PluginSecurity`), while the server
`CreateSurfaceAppearanceAsync` factory returned a SurfaceAppearance. The real
client then showed Roblox's pink/cyan missing-texture checkerboard on all six
three-map test panels, including factory originals and clones, **before** their
EditableImages were destroyed. Therefore neither server-created opaque
MaterialVariant maps nor server-created SurfaceAppearance maps are currently a
verified replacement for authorized uploaded image assets. Do not install or
publish V3 on the basis of the factory's success return. The live V2 geometry
path remains the last actually rendered kit. The 27 Zen-owned map IDs have now
been replaced in local manifests by 27 group-owned Image IDs, uploaded from the
same SHA-verified PNGs. Creator Dashboard verified a Use grant to universe
`10559217407` for every group Decal wrapper; the tested underlying raw Image
also showed the universe as already added. The final V2 group images subsequently passed all 27 client preload checks and actual Studio Play rendering; see verified-play-summary.md. See
`../materials-studio/group-upload-receipts.json` for wrapper IDs, resolved raw
Image IDs, and source hashes. The root applied the guarded map-ID update, native verification passed, and the final V2 place was published as v2440. The V3 experiment remains uninstalled.

The package `../taskgroup-owned-images/manifest.json` pins 27 authored
1024×1024 RGBA8 images. They total 113,246,208 raw pixel bytes, 25,753,201
Zstd bytes, and 34,337,640 Base64 characters in 281 ordered parts. Each image
has source PNG, compressed, part, and decoded RGBA SHA-256 checks. Conversion
uses the decoded PNG RGBA channel bytes with no resize, resampling, channel
swap, or green-channel inversion; Blender OpenGL +Y normals remain +Y.

The current successful Edit probe only demonstrates that a **plugin** may put
DataModel-scoped image content into a MaterialVariant. The official
[MaterialVariant API](https://create.roblox.com/docs/reference/engine/classes/MaterialVariant)
labels `ColorMapContent`, `NormalMapContent`, `RoughnessMapContent`, and
`MetalnessMapContent` **Plugin Security**. A real server Script must run
`v3-runtime-material-api-probe.luau` before a RuntimeBake implementation relies
on those setters. `execute_luau` alone has plugin privilege and cannot establish
that gate. The generated
[Roblox API metadata](https://github.com/Roblox/creator-docs/blob/main/content/en-us/reference/engine/classes/MaterialVariant.yaml)
also says MaterialVariant map Content fields only support **asset URIs** as
textures, so successful Edit assignment of OpaqueContent still does not prove
it can render. The probe also checks
[`AssetService:CreateSurfaceAppearanceAsync`](https://create.roblox.com/docs/reference/engine/classes/AssetService/CreateSurfaceAppearanceAsync),
the documented Basic-capability server PBR factory, as a possible alternative.
It creates unparented one-pixel objects and destroys them afterward; a separate
visible Play test is still required to prove client rendering and replication.

`CreateSurfaceAppearanceAsync` accepts EditableImage objects for color, normal,
roughness, and metalness. It creates PBR on a MeshPart but has no
`StudsPerTile`; the Visual Adapter resizes floor and wall chunks, so their
authored UV patterns would stretch unless scaled geometry/UVs are rebaked for
each distinct room or wall size. The current fixed-repeat `MaterialVariant`
route depends on usable map assets or runtime-settable map content.

For a raw-source bake, decode one image at a time and release temporary strings,
buffers, and EditableImage objects promptly. A 1024×1024 RGBA buffer is
4,194,304 bytes, before concurrent compressed/string/editable/baked copies.
`CreateDataModelContentAsync` can return `StorageLimitExceeded` and its
result is ephemeral to the current DataModel, according to the
[AssetService API](https://create.roblox.com/docs/reference/engine/classes/AssetService/CreateDataModelContentAsync).
The source text is stored in ServerStorage and does not replicate to clients;
the rendered result and its map content still need actual client Play proof.
Roblox's [place-file limit](https://create.roblox.com/docs/projects/place-files)
is 100 MiB, so verify native backup size after adding source strings. The
[EditableImage API](https://create.roblox.com/docs/reference/engine/classes/EditableImage)
also requires creator verification and the experience Mesh/Image API switch for
published servers; Studio Play cannot establish that setting.

Do not mark the PBR gate green from Source inspection, map property values in
Edit, or the earlier failed render with Zen-owned image IDs. In Play, capture
the 27-map bake result, actual client visual evidence for color and normal-map
relief under angled light, Output errors, client memory/FPS bounded samples,
and a second seed after cleanup. A published-server smoke test is necessary
before claiming production dynamic asset creation works.
