# PoolSlide raw mesh cache and unchanged animation probes

These are local task artifacts. The preparation scripts do not connect to Studio or change production source, settings, flags, assets or animation IDs. Root executes the bounded native steps separately.

Roblox's announcement explicitly permits the Editable APIs in Studio plugins in Edit without enabling the experience toggle. Its discussion also identifies Command Bar/Edit use and a historical Team Create limitation. The current Creator Hub reference distinguishes published-game opt-in from asset ownership/edit permissions. Sources: [Roblox announcement](https://devforum.roblox.com/t/client-beta-in-experience-mesh-image-apis-now-available-in-published-experiences/3267293), [Edit discussion](https://devforum.roblox.com/t/client-beta-in-experience-mesh-image-apis-now-available-in-published-experiences/3267293?page=2), [EditableMesh API](https://create.roblox.com/docs/reference/engine/classes/EditableMesh). These sources motivated an Edit-only test; they were not treated as proof of the current session's permissions.

Root subsequently verified both exact owned meshes through `CreateEditableMeshAsync` in Edit with Mesh/Image APIs still OFF, and destroyed both objects. Root then executed this extractor and retrieved its chunks. The resulting `native-mesh-cache.json` is **7,931,138 bytes**, SHA256 **c783fd090b22802aee5ec3e13cd6a4319ef355f6f5854cca1e44e56464061e61**: Mesh_0 `108970159979893` has 13,105 vertices; Mesh_02 `91916953208682` has 1,986; each has 20 bind bones. All 199 transfer checksums and the assembled DJB2 checksum 727056419 passed. These are raw mesh data, not new phase-grid results.

## Export

Run `extract-edit.luau` only through the existing Edit Command Bar/plugin. It requires unposed source bones and the exact two meshes/counts. It exports each stable vertex ID, mesh-local position, ordered bone influences and weights, bind CFrames, and the unscaled inverse-bind offset of each influence. A source scale/rest/parent/mesh fingerprint is recorded before and checked after the yielding reads. Temporary EditableMeshes are destroyed on success and failure. Only a completely successful export becomes one `_G.TrelloPoolSlideRawMeshExport_20260910` entry; no instance is parented into Edit.

The small returned manifest includes a token, total bytes, chunk count, and full/per-chunk DJB2 checksums. `read-chunk.luau` returns one matching-token chunk; fill its token/index literals. Chunks are at most 40,000 bytes and do not split a UTF-8 character. Root's existing `fetch-edit-cache.py` retrieves them through the local MCP client and saves the manifest, `.jsonpart` chunks and complete JSON. The extractor never silently replaces a previous scratch export. After its local file is verified, root may clear that exact scratch entry; this does not touch the source rig.

The earlier reports did not retain raw vertex positions/weights, and bone transforms or old envelopes could not recover them. No undocumented binary-cache parser, unknown software download or security-setting change was used.

## Validate and stage

```powershell
python artifacts/trello-20260909/pool-slide-cache-prepared/prepare_cached_grid.py --cache artifacts/trello-20260909/pool-slide-cache-prepared/native-mesh-cache.json
```

This checks complete identities/counts, finite matrices and vectors, proper orthonormal bind/rest frames, vertex/bone uniqueness, matching rig and mesh bone names, valid weight sums, and each inverse-bind offset. The actual export passed; maximum unscaled offset discrepancy is **2.0859052438704221e-7** studs. It emits:

- `mesh-cache.json`: identical validated raw bytes.
- `mesh-cache.rbxmx`: one data-only Folder named `TEMP_PoolSlideMeshCache_20260910`, containing `CacheManifest` and 199 StringValues `000001` through `000199`.
- `cache-validation.json`: raw SHA, chunk metadata and validation metrics.
- `phase-grid-cached.luau` and `realtime-fresh-cached.luau`: separate derived probes; both originals remain unchanged.

Root stages and loads the data Folder **only in a disposable Play session**, as a child of ServerStorage, using the existing local-content workflow. The preparation tool itself writes only this artifact directory. The cache loader checks every chunk, the full checksum/size, current source rest/parent/size/asset fingerprints, and all supplied inverse-bind offsets. A uniform model scale change is supported; other rest changes fail closed. The raw offsets are deliberately unscaled: the original reconstruction still derives the actual import/model scale from current clone bind distances (scale 6 in these probes).

## Probe behavior and limits

The cache reader implements only the original EditableMesh read methods and Destroy. It returns copied ID/weight arrays, rejects use after Destroy, and never calls AssetService. The complete original vertex mapping, skin-weight sums, rest box/mapping errors, clone lifecycle, animated bone measurements, phase/weight validation and single-track endpoint comparisons remain in the derived probes. Only the loader, one mesh-read expression and two provenance fields differ. Tests reverse these declared seams and recover each complete original source exactly.

`test_cache.py` passes **15,136 actual extractor/reader/original-mapping checks**, using deterministic synthetic rotated/translated bind geometry at source scale 4 and probe scale 6, plus **13 Python transfer, malformed-input, XML roundtrip and source-preservation checks**. All five complete Luau sources compile. The actual raw-cache schema validator also passes separately. The host is a math/API simulation; it does not certify Roblox rendering or native animation timing.

Run the cached grid only after loading the existing reviewed V2 local clip copies. Its original 16 cases, 272 samples and 32 endpoint references are preserved. The fresh realtime variant retains the original seven fresh-Animator cases, lifecycle/weight gates and cleanup. Neither artifact has a new native result merely because compilation or cache validation passes. The existing outgoing Idle .25 / incoming Walk zero transition penetration remains an unresolved measured baseline until an actual new candidate is validated. Cache metadata is recorded in each resulting report.

On completion, root saves the native reports and stops Play, removing the staged data Folder and test helpers. No cache Folder, edited animation IDs, security-toggle change or test source should be published.
