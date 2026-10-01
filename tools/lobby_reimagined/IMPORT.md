# Isolated lobby preview import

These helpers target only this task's separate `LobbyReimagined` preview. Initial installation adds unique namespaces; the active R2 correction compares and updates exactly four already installed preview Sources against their fresh Studio/editor baseline. It preserves the original lobby, round systems and previous raw payload. Helpers do not connect to Studio, upload assets or publish; parent owns the reviewed application and publication.

## Package contract

`manifest.json` has schema `lobby-reimagined-blender-v1`, `chunks`, optional `prefabs`, `placements` and `atlas`. Each family has exactly one chunk from `export_prefab()` in `tools/level6_build/import/export_prefabs.py`: LVM6 binary magic, X/Z/−Y proper axis mapping, centered position/normal/UV buffers and triangle index triples. Each chunk includes `id`, `name`, optional `family`, `file`, `sha256`, `bytes`, `triangles`, `center`, `size`. Families default to chunk.name. Prefabs may be name strings or `{name,chunkId}`. Placements use `{family,robloxPosition:[x,y,z],yaw,runtimeKind?}` relative to parent-selected preview center `(220,30,-760)`.

Atlas is `{width:1024,height:1024,file:"atlas.rgba.b64",sha256?}`. The current Blender build exports **bottom-up RGBA** directly from its authored image-pixel layout, not PNG file bytes. Runtime reverses the 1024 rows into EditableImage's top-down layout, then writes the pixel buffer. Independently, mesh import converts Blender UV V to `1−V` exactly once. Both conversions are required for this package; do not remove one as a duplicate flip. Parent verified this orientation correction in an actual render. The final local Play screenshots and interaction receipts are recorded under `artifacts/lobby-reimagined-20261001/play-verification`; the performance limits below remain separate. Package/source bytes are validated and frozen before serving.

Optional source-module manifest:

```json
{
  "sources": [
    {"key":"preview-builder","path":"ServerScriptService.LobbyReimaginedPreview.Builder","class":"ModuleScript","file":"../../tools/lobby_reimagined/preview_builder.ModuleScript.luau"},
    {"key":"preview-bootstrap","path":"ServerScriptService.LobbyReimaginedPreview.Bootstrap","class":"Script","file":"../../tools/lobby_reimagined/preview_bootstrap.Script.luau"},
    {"key":"queue-controller","path":"StarterPlayer.StarterPlayerScripts.LobbyReimaginedQueueController","class":"LocalScript","file":"../../tools/lobby_reimagined/queue_controller.LocalScript.luau"}
  ]
}
```

Relative file paths resolve from this JSON file's directory. The default `ServerScriptService.LobbyReimaginedPreview.RuntimeBake` is included automatically; do not duplicate it. Direct new ModuleScript children under `ReplicatedStorage.LobbyReimaginedPreview` are also supported. Existing namespaces and arbitrary targets are forbidden.

## Active R2 correction and transport

```sh
python3 tools/lobby_reimagined/serve.py PACKAGE --verify-only --sources-manifest SOURCES.json
python3 tools/lobby_reimagined/revision_install.py
python3 tools/lobby_reimagined/serve.py PACKAGE --port 8892 --sources-manifest SOURCES.json
```

The first two commands do local verification/generation only. The R2 generator uses the fixed task package, current source-module manifest and `artifacts/lobby-reimagined-20261001/installed-source-manifest.json`, which records the actual installed four-Source baseline. It produces a SHA-pinned `install_revision_r2.luau` and receipt and refuses to replace a different already generated candidate. The third command starts the loopback-only transport when root is ready. Endpoints are strictly `/manifest`, `/chunk/{id}`, `/atlas-pixels`, `/source-module-manifest` and `/script/{key}`.

The active `SOURCE_NAME` and RuntimeBake source target are **`ServerStorage.LobbyReimaginedBlenderSource20261001R2`**. R2 adds that compressed payload while retaining `LobbyReimaginedBlenderSource20261001`. It checks each preview instance's exact class, ownership, Source SHA and editor parity, repeats those checks after downloads and immediately before each write, and checks again inside `ScriptEditorService:UpdateSourceAsync`. Candidate bytes are pinned too. HttpEnabled returns to its previous value. A partial correction is reported for fresh reconciliation; it is never blindly rolled back over concurrent work.

`install.py` and archived `install_preview.luau` / `install_preview_v2.luau` describe the completed initial additive installation. **Do not rerun them against this installed preview.** Likewise, `install_revision_r2_pre_pile_fix.luau` and its receipt are historical attempts. The R2 correction was installed successfully with 34 chunks and four Sources; its generated candidate and receipts now describe that completed application. Parent subsequently tuned only Builder's sign canvases and warm main lamps against a fresh Source/editor baseline. Final Builder is 9,162 bytes, SHA `8d808c569101432309f954d5a0f33f48ba4e1b115831b4877e064ca56c0be921`. Historical files and receipts remain unchanged. Any future correction requires a fresh authoritative Studio baseline and a newly pinned candidate; none of these completed installers is a recipe for overwriting current Studio.

## Runtime and persistence

`RuntimeBake.GetManifest()` returns the decoded manifest. `RuntimeBake.Ensure()` returns `ServerStorage.LobbyReimaginedBlenderKit20261001` with direct, family-named MeshPart children retaining their local `chunk.center` CFrame and size. Place clones with `placementCFrame * template.CFrame`; using PivotTo on a lone MeshPart would lose the author's local offset. All mesh geometry is cosmetic, anchored, and non-colliding/touching/querying; parent Builder separately supplies clear collision proxies and lights.

The legacy atlas route uses `CreateEditableImage` → baked `TextureContent`, without SurfaceAppearance. Do not use `Level6BlenderRuntimeBake.V3.ModuleScript.luau`: that file explicitly marks its checkerboard SurfaceAppearance experiment unsupported. Current group-owned upload is optional: official [AssetService documentation](https://create.roblox.com/docs/reference/engine/classes/AssetService) restricts `CreateAssetAsync` to locally loaded plugins, while `CreateDataModelContentAsync` creates ephemeral DataModel-scoped content and may return a storage-budget failure. Runtime source payloads avoid an external API key and gameplay HTTP dependency.

**Persist raw source and Bootstrap, not session-baked opaque content.** Recreate the kit in each fresh server. An existing kit not created by the current module instance is refused for inspection; helpers never delete/replace an old Level 6 kit or original lobby. Final native-after export records exact Source/editor parity for all four preview scripts. A fresh local Play build reached PreviewReady in 4.28 seconds on its first attempt. Actual Humanoid movement climbed the stage steps in Running state with health 100, and gravity remained approximately 196.2. These are local Studio observations; public-server DEV eligibility and streaming across multiple clients were not certified.

The latest vinyl behavior uses two separate client-animated record MeshParts at **12 degrees/second**. Actual Play measured approximately 11.80 degrees/second over 2.02 seconds, and a later sample measured 12.01 degrees/second. Record positions, consoles and pickup arms stayed fixed. Reduced-motion preferences stopped rotation and the original preference was restored afterward.

Actual E input activated a queue cylinder with ten horizontal bands fading from transparency 0.62 at its base to 1 at its top. Cancellation returned the prompt to `START QUEUE PREVIEW` and hid every band. The authored automatic reset is 20 seconds; the saved later observation at 212.68 seconds confirms inactivity and hidden bands, but does not measure the exact reset time. These are cosmetic preview queues: **they do not launch real levels**. Final header and projecting blade canvases are 450×110 and 650×150; main lamps use warm `(205,214,190)` at brightness 0.35.

The background Studio sample observed 14.93 FPS, about 66.71 ms mean frame time, and 5,527 MB reported memory for the whole running client/place. A settled sample remained 14.26 FPS. A temporary owned-client-preview detach produced a transient difference and does not establish the preview's performance cost. **Performance is not certified**, and no mobile or multiplayer test was performed. These whole-place Studio readings must not be presented as isolated preview memory or a performance pass.

Run `python3 tools/lobby_reimagined/verify_import_helpers.py` for the synthetic binary/hash/path/refusal and Luau compilation checks. This does not start a server or execute candidate scripts. The exact real Blender package requires its own verify-only check and receipts. Stage only reviewed helper files, generated candidates and verified task artifacts; omit Python caches.

## Native capture route

Use a new task-specific receiver directory. Copy only the compatible current reflection-derived service schema (the previous schema is `/private/tmp/lobby-box-glow-native-after-20261001/service-property-schema.json`); do not reuse an old native snapshot as current state. Root owns the fresh live capture:

```sh
python3 tools/level6_build/import/backup_receiver.py NEWDIR
```

After root runs the read-only Edit-state `capture_native_backup.luau` through Studio and observes completion, stop the receiver and locally assemble/reopen:

```sh
python3 tools/level6_build/import/assemble_native_backup.py NEWDIR
/private/tmp/level6-lune-20261001/lune run tools/level6_build/import/pack_native_backup.luau NEWDIR
```

The assembly rejects Source/editor conflicts, skipped roots and incomplete transport parts. Preserve raw native bytes, service metadata and the reconstructed `.rbxl`, including reconstruction limitations. Capture after-state separately and verify all pre-existing Sources, native roots/properties and service settings remain unchanged; only explicit new preview namespaces may be added. Neither a local reconstruction nor the loaded PlaceVersion proves current cloud publication.
