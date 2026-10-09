# S08: local legacy Level 1 workflow retirement

Status: **gennemført for the seven scoped local files below**. Root applied the
reviewed candidates against exact fresh before hashes and completed the actual
installed current-package recheck. All 286 Level 1 asset/receipt files and six
other Level 1 Python dependencies remain byte-identical. The owner explicitly
retired the standalone old `Level1BlenderKit` workflow. Native old-kit removal
is a separate, still blocked S04 port.

The required narrow port is the current immutable package's actual local
selector/import/export/publication/QA contract, combined with exact preservation
of shared helper definitions and initializers. **Fresh V2 rebuild byte and
triangle equivalence remains afventer test**: the same unchanged BEFORE source
reproduces variability. No numerical tolerance, wire hash or receipt ID was
changed to make that broader gate pass.

## Exact applied scope

The table records the original proposal decisions and their test gates. Its
seven local scopes are now complete; the broader pending gates remain pending.

| ID / file / block | Change and dependency evidence | Risk / benefit | Port / status |
| --- | --- | --- | --- |
| S08-01 `tools/level1_blender/build.py`: standalone `main` and CLI guard | Archive/remove old standalone main; CLI exits with retirement message. Retain all 12 non-main definitions, imports, constants and initializers exactly. `build_v2.py` and `elevator_inset.py` import this file; neither calls `b.main`. | Low scoped risk; prevents accidental old standalone rebuild while preserving Mesh/material/UV/room/export/render APIs. | Actual V2/elevator headless helper calls completed before/after; shared bodies and initializers identical; retired entry rejects before any asset write. Gennemført for this local scope; fresh V2 triangulation gate separately pending. |
| S08-02 `tools/level1_blender/import_assets.py`: ASSETS, write_installer default/target guard, main CLI selection | Default assets/kit to V2; reject public old asset/kit targets before write/upload/install. `payload` and `upload` unchanged; old receipt fallback preserved. Only retained write_installer callers are importer itself and explicit-V2 importer test. Elevator uses its own installer on `base.INSTALL`. | Low; prevents recreating retired kit. Shared INSTALL token remains byte-identical, deliberately including its old placeholder. | Actual V2 payload/installer/source exact, old wire receipt fallback retains exact IDs, invalid texture hash refused, three legacy target negatives have zero writes/network. Gennemf?rt. |
| S08-03 `tools/level1_blender/check_assets.py`: default and legacy-path guard | V2 default, explicit legacy QA path refused. Remaining exported geometry/socket/PBR checks preserved. | Low; current QA selects active package. | Actual current V2 binary indices/hashes, all 15 socket masks, room/prop/PBR checks run before/after. Legacy target rejects without writes. Gennemf?rt. |
| S08-04 `tools/level1_blender/verify_native.py`: default and legacy-path guard/example | V2 default, explicit legacy QA path refused. Retain native .blend, relative texture, room metadata and fresh FBX import checks. | Low; selects active QA package. | Real Blender 5.2 background .blend/FBX QA in private copies before/after returns byte-identical verification record; legacy target refuses before receipt writes. Gennemf?rt. |
| S08-05 `tools/level1_blender/publish_textures.py`: default and legacy-path guard | V2 default; refuse old texture workflow. Preserve explicit elevator selection, hash checks, resumable IDs and existing publisher behavior. | Low; avoids old public workflow. Missing-map upload behavior is unchanged and was not invoked. | Actual cached V2 20-map and elevator 7-map publication branches before/after; forbidden network/Studio boundaries never used; legacy path refuses without writes. Gennemf?rt. |
| S08-06 `tools/export_level1_facelift_verified.py`: SCRIPTS/KIT default, former revision branch, kit filename | Fixed active V2 seven-script/kit export; keep `--revision-v2` compatibility alias, safely repeatable. Resulting COMMON/KIT is exact old explicit-V2 route. No native source-reader logic changed. | Low; prevents default old-kit export. | Actual no-run CLI/default/alias path, seven record selection and V2 exporter code are exact before/after; generated Luau compiles. Actual live export is not claimed. Gennemf?rt. |
| S08-07 `tools/level1_blender/README.md`: active workflow instructions | Document active V2/elevator routes, retained shared helpers/assets/receipts and old standalone/public-target retirement. Keep historical V2 gameplay evidence link and limits. | Documentation only; removes instructions to run retired entry. | Source/command review against candidate tools; no new gameplay or publication claim. Gennemf?rt. |

No runtime gameplay Source, manifest, collider, hiding/prompt/interaction part,
renderer fallback anchor, player data, entitlement, receipt ID or uploaded asset
is changed. `install_sources.py`, `prepare_v2_textures.py`, active V2/elevator
builders and `assets/level1/blender` are retained. V2 still reads old carpet/
ceiling pixels and matching old mesh-wire receipts. Installer construction calls,
collision roles, fixed elevator assemblies and template substitution remain.

## Evidence and results

`manifest.json` pins all seven before/candidate bytes and exact `.bin` paths.
Nested `.gitattributes` marks archived `.bin`, `.py`, `.luau` and `.json`
proofs as `-text -whitespace` so Git cannot change immutable proof bytes.
`manifest-before-status.bin` preserves the manifest used by the historical
receipts before status enrichment. The preparer and tests write private copies;
Root's application is recorded separately in `installed-result.json`. The
frozen proposal manifest retains historical proposal statuses deliberately.

`current-package-port-v2/paired-result.json` and
`installed-package-port-v1/paired-result.json` are **PASS** for the narrow local
package port, including the exact current installed candidate hashes. Six
complete outputs are byte-identical: V2/elevator payloads and
installers, active V2 exporter Luau, and real V2 native/FBX QA record. Generated
V2/elevator installers compile with actual Luau 0.737 O0/O1; exporter O0 passes.
Seven retirement negatives reject old targets/entry and preserve every private
asset/receipt byte. Cached publication exercises real tools and all current
verified receipts while actual MCP/network construction is forbidden.

The historical `current-package-port-v1` pass pinned the earlier manifest.
Root's first application preguard rejected its stale manifest hash before any
checkpoint or mutation. Root reran the port as `current-package-port-v2` against
the frozen current manifest, then applied only the seven reviewed candidates.
No guard was relaxed and no rollback was required after the successful apply.

The real headless helper probes in `paired-port-v1/v2/v3` completed V2 41
components/42 rooms and elevator component/four-depth assembly/UV/export
generation. All actual kernel summary records match. Independent source review
by `levels_core` verified exact retained initializer/definition ASTs, unchanged
INSTALL/payload/upload, complete callers and safe repeatable V2 alias behavior.
These observations are not a full rebuild byte/triangle pass.

Three failed broader trials are deliberately retained:

1. `paired-port-v1/paired-failure.json`: independent V2 generated raw wire hashes
   differ on chunks 15/38/41/81 and manifest; current-package outputs and elevator
   generated bytes match.
2. `paired-port-v2/paired-failure.json`: fixed embedded PYTHONHASHSEED=0 with a
   repeated same BEFORE source still produces raw V2 differences on the same
   chunks. The candidate differs on a subset of those existing variations.
3. `paired-port-v3/paired-failure.json`: exact f32 pool/corner representation
   permits only index/triangle order and cyclic oriented corner starts. It
   rejects reversed winding, coordinate deltas, UV binding and pool multiplicity
   changes in six negative/positive parser fixtures. Same-before control still
   differs for LeverHandle/Red chunk41; metadata and all other chunk geometry
   contracts match. This remaining triangulation variability is **unresolved**.

The diagnostic representations never modify raw wire hashes, asset IDs,
published receipts or canonical geometry. No render regeneration, full active
builder main invocation, gameplay, streaming, multiplayer, live Studio import/
export, asset availability, upload or performance gain is certified here.

## Application and installed recheck

Root completed the exact seven-file diff review, exclusive checkpoint and
fresh before-hash guards. Each scoped write used a verified temporary file and
atomic replacement, with guards for retained dependencies and all asset bytes.
Its failure path only restores a file still equal to its own candidate, thereby
preserving a concurrent edit. No native write or network call was made.

`installed-result.json` records 75,572 before bytes and 71,720 installed bytes
across the seven files, a reduction of 3,852 bytes. This is a file-size result,
not a measured runtime performance gain. Root's recoverable checkpoint is
`.git/mongotv-cleanup-20261009/s08-application-before`. The seven original full
sources are already portable in `before/`; portable checkpoint inventories and
the exact application source are indexed by `installed-proof-index.json`.

Root ran this installed port using the same archived before/candidate inputs,
requiring exact current canonical candidate hashes:

```powershell
python -B tools/cleanup_20261009/level1_retirement_contracts.py --proposal artifacts/cleanup-serverstorage-20261009/S08-level1-local --dest artifacts/cleanup-serverstorage-20261009/S08-level1-local/installed-package-port-v1 --package-only --verify-installed
```

This destination is already populated and immutable; any future recheck must
use a new destination. The runner creates private test copies only and never
installs the proposal, contacts Studio or uploads. Root owns the final staged
diff and commit. `commit-allowlist.json` explicitly enumerates only S08's seven
canonical files, three preparation/test tools and portable evidence. All native
old-kit recovery/removal and fresh V2 triangulation limits remain separately
pending.
