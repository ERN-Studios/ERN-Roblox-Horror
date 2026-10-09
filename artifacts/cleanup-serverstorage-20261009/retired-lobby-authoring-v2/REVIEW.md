# S07 / T16,T17 — completed local lobby workflow retirement

The owner explicitly retired the old R1/R2/R3/R3B import/export/QA workflows.
Only the17 exact files listed in `removal-receipt.json` were removed from active
`tools/lobby_reimagined`. Their133,791 original bytes remain in `sources/**`;
archive reload and every file hash passed. This batch made no Studio writes.
Native five-pack retirement remains S04, with separate ports.

Closure: old serve→install→revision generators/manifests/runtime candidates→QA;
R3B also reads the R2 generator AST. Active R4 imports are independent. Current
native R4 Builder/RuntimeBake/MaterialPolish use only R4 source/kit. Preserve
shared `props`, R4 bay/PBR/export helpers and all162 other tracked authoring
files plus the shared Level6 prefab exporter; exact bytes remained unchanged.
No remote, attribute, receipt ID, mesh-upload cache or player-data change.

The actual active before/after port loaded and checked the existing91-endpoint
R4 mesh/PBR package, compiled real generated installer and quotation payloads,
ran Blender5.2.0 headless prop QA (nine checks;37,096 original triangles), then
built a fresh standalone R4 package in isolated output and validated all91
endpoints again. All90 non-manifest fresh endpoint hashes match. Every manifest
field, including geometry, placements, colliders and asset references, matches
except its verified generated `.blend` file hash. All other port records match.
Python AST8; old Luau O0/O1 14; archive Luau O0/O1 14; generated/quoting compiles
10 before and10 after:48 actual compiles passed across the final gate.

The preserved default R4 catalog has8 entries while the historical loader expects
7. Its verify-only catalog gate failed before and after identically; no installer
was run, catalog regenerated or historical deployment baseline adopted. The
package loader, builder and shared QA passed independently. Fresh current Studio
Source/editor guards remain mandatory for future game work.

The first trial used raw equality for generated output. It rejected the changed
`sourceBlendSha256` and exclusively restored all17 originals; no foreign file
conflict. A second unchanged baseline with all17 originals present reproduced
only that difference. The final comparator verifies each actual private `.blend`
hash and raw manifest receipt, then permits solely that generated metadata field.
No production/source/asset receipt is normalized. The failed trial, byte archive,
rollback and unchanged-baseline evidence remain in `../retired-lobby-authoring`.

No gameplay, multiplayer, streaming or performance pass is inferred. Gain:
17 retired local entrypoints/candidates removed from active tools, with exact
recoverable history and the active authoring flows retained.
