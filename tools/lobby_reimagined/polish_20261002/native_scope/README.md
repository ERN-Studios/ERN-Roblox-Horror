This audit compares full native captures on disk. It never connects to Studio and never rewrites an input capture. The CLI accepts the owner's exact frozen source receipt schema: six rows containing `path`, `className`, `file`, `sha256`, and `new`. It also consumes the original `baseline-critical.json`, material candidate hash contract and image upload receipt.

Run from the repository root after the final capture is complete:

```sh
/private/tmp/level6-lune-20261001/lune run \
  tools/lobby_reimagined/polish_20261002/native_scope/verify_native_scope.luau \
  /private/tmp/lobby-polish-before-20261002 \
  /private/tmp/lobby-polish-after-20261002 \
  artifacts/lobby-polish-20261002/root/final-frozen-source-hashes.json \
  artifacts/lobby-polish-20261002/root/baseline-critical.json \
  artifacts/lobby-polish-20261002/materials/candidate-manifest.json \
  artifacts/lobby-polish-20261002/materials/uploaded-assets.json \
  artifacts/lobby-polish-20261002/root/native-scope-verification.json
```

The production CLI pins before native SHA256 `451e86549091122a992da3a8cabee5f38471dd20d5b77212dc6d77dad1433872`. Both captures must have correct raw bytes/hash, experience/owner, root inventory and full Source catalogs. Every native LuaSourceContainer is counted and checked against the live export. Every Source has exact native/export SHA and bytes, and editor/export parity. Native references are inspected before normalization so a saved reference to an omitted new module cannot disappear into serialized nil.

Only these changes leave the comparison in local deserialized memory:

- Builder, EndBlockades and LobbyReimaginedQueueController Source changes plus their `InstalledSourceSHA256` attributes, each pinned to the frozen candidate and critical before hash.
- Three exact new owned ModuleScripts: MaterialPolish, LobbyPolishBays and LobbyPolishScene. MaterialPolish must contain exactly one owned Ready folder with three owned SurfaceAppearances and one owned StringValue, with alpha/tint, dielectric/empty emissive mask, PNG hashes and all ten static published image URIs matching the upload receipt. The other modules have zero descendants.
- Absent versus explicitly empty attribute storage is canonicalized equally while all real attribute values are checked unchanged.

Full canonical root and forest hashes then bind all remaining saved geometry, opaque data, properties, sources and references. The original ServerLobby receives an explicit unchanged fingerprint check. Existing-root property and cross-reference diagnostics, Source changes/additions/removals, root additions/removals, typed service metadata, collision settings and material overrides remain reported as `unclassifiedConcurrent*` deltas. These deltas are never normalized away or restored. `verified` remains false, and the CLI exits unsuccessfully, until the actual task scope and remaining forest both match. `taskScopeVerified` is separate from whole-forest preservation to prevent an unrelated concurrent change from being presented as parity.

The new modules are authorized complete creations. Their classes, Sources, ownership, installed Source hashes and child contracts are checked; their complete saved properties/attributes are additionally recorded under `newTaskSourceRows` canonical hashes. This does not assert byte-pinned non-Source properties for the entire new creation beyond the explicit material child contract.

`selftest.luau` builds small independent fixtures under `/private/tmp/lobby-polish-native-scope-selftest-20261002`, with one passing exact-scope case and eight failing cases: original lobby geometry, extra Source, wrong material URI, extra helper child, editor conflict, reference to a new task module, unrelated attribute and new root. Its receipt is `artifacts/lobby-polish-20261002/materials/native-audit-selftest.json`. It never modifies a real capture. `preflight_before.luau` reads the actual before capture against itself and must report the nine expected uninstalled task pin errors; it cannot claim after verification.

The real capture contains roughly 392000 instances. Allow bounded processing time and avoid gathering client frame-time comparisons while this local audit is active. If Documents hydration stalls a frozen candidate read, a hash-identical candidate snapshot and corresponding pins file may be placed under `/private/tmp`; retain and hash the original frozen receipt for provenance. Native preservation, Source/editor parity, fixtures and typed property checks do not establish gameplay, multiplayer, texture loading or performance behavior.
