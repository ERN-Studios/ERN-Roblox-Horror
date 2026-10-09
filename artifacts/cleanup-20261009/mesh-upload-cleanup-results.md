# B05 — X02 EditableMesh ownership in authoring upload tools

Status: resource-cleanup change completed; offline contract gates passed.
No live upload, HTTP request, Studio edit, game-runtime edit or publication.

## Exact scope and rollback

- `tools/level4_blender/upload.luau:build(b)` and `run()`.
- `tools/level5_import/upload.luau:build(b)` and `run()`.
- Generated upload payload in `tools/level1_blender/import_assets.py:upload`.
- Generated upload payload in `tools/level4_blender/studio_upload.py`.
- New offline gate `tools/tests/test_mesh_upload_cleanup.py`.

Before editing, all four existing files were copied byte-for-byte into
`.git/mongotv-cleanup-20261009/tooling-before/` at their original relative paths.
SHA-256 receipts and exact rollback paths are in
`mesh-upload-cleanup-checks.json`. No batch rollback was required. Deliberate
negative mutants ran only in OS temporary directories.

## Dependency closure and reason for change

The L4 builder is extracted by L1 `upload`, L2 `upload_code`, L2
`large_upload_codes`, and L4 `studio_upload`. All use the exact boundary from
`local function build(b)` up to `local function run()`. The signature and both
markers are preserved, and each actual generated consumer contains the complete
identical revised builder exactly once. L5 uses its own non-UV format.

Originally, buffer-body reads and AddVertex/AddNormal/AddUV/AddTriangle or
SetFace* exceptions after allocation escaped before the caller received the
mesh. The allocated mesh was therefore never destroyed. L1, L4 manual, L5
manual and L4 studio wrappers also skipped Destroy if CreateAssetAsync raised.
The existing L2 inline and sliced callers already protected their upload phase;
they were preserved unchanged.

The builder now owns failed construction: a protected construction block
destroys its allocated mesh before rethrowing the original error. On success,
ownership still transfers to the caller. Each changed caller keeps the mesh
outside its protected upload block and destroys it once after that block settles,
before returning or recording the result. A failed build never assigns a mesh
to that caller, preventing double cleanup. Allocation exceptions or nil returns
do not cause a Destroy call on a nonexistent mesh.

No remotes, gameplay attributes, receipts, entitlement IDs, kit metadata,
colliders or native instances changed. Creator/group IDs, asset names,
descriptions, asset-result values, four-attempt retry policy and waits, POST
URLs/bodies, HttpEnabled restoration, helper markers and public signatures are
preserved. Risk is limited to authoring upload object ownership; gain is removing
the reproduced resource leaks on exceptional authoring paths.

## Before and after test port

The real Luau interpreter ran the real helpers and actual Python-generated
payloads. Only AssetService, vector constructors, EncodingService, HTTP and
Instance boundaries were fake. Binary buffers and parsing loops were native
Luau. Python tests evaluated exact reviewed AST definitions/assignments rather
than importing the live top-level MCP uploader. Exports, receipts, staged
StringValues and all mutated fixture programs existed only in temporary test
storage or the fake DataModel.

| Gate | Result |
| --- | --- |
| Before sources: same 93 scenarios | 1,653 assertions; successful flow/geometry/identity preserved; original partial-build and L1/L4/L5 thrown-upload leaks reproduced. This observation is not a passing cleanup gate. |
| Revised sources: same 93 scenarios | 1,775 assertions passed; every allocated mesh destroyed exactly once on success/error, and no upload of a destroyed mesh. |
| Python generation, extraction and receipt boundaries | 12 checks passed, including exact helper identity in all four consumers and L1 wire hash/receipt round trip. |
| Independent negative fixture: remove failed-build Destroy | Rejected by the exactly-once resource oracle. |
| Independent negative fixtures: remove caller Destroy in L1, L4 studio, L4 manual and L5 manual | All four thrown-upload cases rejected by the same oracle. |
| Compile all six final upload payloads plus two actual L2 staging payloads | 8/8 native Luau compilation passes. |
| Python AST for two changed wrappers and new gate | 3/3 pass. |
| Existing `test_level1_blender_import.py` | PASS: V2 installer scoped/no-overwrite; wallpaper tint/glass preserved; compiles. |
| Existing broader `test_level2_kit_import.py` | BLOCKED before uploader execution: `check_geometry` requires the absent historical `ServerScriptService/Level 2 Systems/Level 2 Kit World Builder.ModuleScript.lua`. Existing oracle preserved. |
| Exact scoped diff/whitespace check | PASS. |

Scenarios cover allocation exceptions/nil, decode error, truncated header/body,
AddVertex/AddNormal/AddUV/AddTriangle/SetFaceNormals/SetFaceUVs errors,
CreateAssetAsync exception, four failed status attempts, failed status followed
by success, normal geometry/normal/UV identity and returned AssetId, manual
second-chunk reentry after a partial failure, and restoration from initially
enabled/disabled HttpEnabled. For sliced L2, successful scratch cleanup and
failed-upload scratch retention are both checked. For manual result POST failure
after successful upload, the mesh has already been freed, the returned AssetId
remains 7001 at the registration boundary, the error is surfaced, and no second
upload occurs.

Reproduce:

```powershell
$env:LUAU_BIN = Join-Path $env:TEMP 'codex-luau-0.737\luau.exe'
python tools/tests/test_mesh_upload_cleanup.py --baseline --source-root .git/mongotv-cleanup-20261009/tooling-before
python tools/tests/test_mesh_upload_cleanup.py
```

The committed gate does not require the private before checkpoints for its
normal after test. Raw before/after logs are `mesh-upload-cleanup.baseline.txt`
and `mesh-upload-cleanup.after.txt`.

## Boundaries and retained work

This validates resource lifetime and generated authoring contracts offline;
actual Roblox asset permissions, native EditableMesh limits and real network
uploads were not exercised. No FPS, CPU or memory saving is claimed or estimated.
The broader historical L2 installer harness remains awaiting reconciliation
with current Studio state (T07); focused current upload consumers passed here.
X03 result-registration/recovery redesign remains pending and was not changed.
No successful asset receipt or ID is cleared to retry registration.
