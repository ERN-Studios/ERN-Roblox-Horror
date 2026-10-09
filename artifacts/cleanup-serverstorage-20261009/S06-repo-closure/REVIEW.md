# S06 — externally absent native source mirrors

This is a downstream reconciliation proposal for T16/T17. It does not remove a
runtime feature or claim credit for the other session's native changes. The
12 mirrors remain present: all three actual native preflights rejected before
any removal or manifest write. Status is **afventer test**, pending a stable
concurrent native/repository Source baseline. The reviewed source-only batch
gate is required before removal. Full-object native reopen and
opaque restoration certification are separate ports.

## Exact scope and evidence

`preflight-v2.json` lists every exact file, native path, class, raw/canonical
digest, byte count, properties and attributes. The allowlist comprises:

| Native root | Exact ModuleScript names | Planned action | Status |
|---|---|---|---|
| `ServerStorage.PoolSlideContextDiagnosticBackup_0710` | `Level 2 Pool Slide Controller`, `Level 2 Pool Slide Navigator` | Archive exact mirror bytes, then remove only these two mirrors/rows | afventer test |
| `ServerStorage.PoolSlideContextDiagnosticBackup_MP6_1609Z` | `Controller`, `Navigator` | Same, two mirrors/rows | afventer test |
| `ServerStorage.PoolSlideContextDiagnosticBackup_MP7_1624Z` | `Controller`, `Navigator` | Same, two mirrors/rows | afventer test |
| `ServerStorage.PoolSlideContextDiagnosticBackup_MP8_1633Z` | `Controller`, `Navigator`, `NavigatorBeforeBudgetFix` | Same, three mirrors/rows | afventer test |
| `ServerStorage.PoolSlideContextDiagnosticBackup_MP9_1640Z` | `Controller`, `Navigator` | Same, two mirrors/rows | afventer test |
| `ServerStorage.TEMP_PipeEntityAnimations_20260909` | `PreviewControls` | Same, one mirror/row; owner explicitly retired this manual preview workflow | afventer test |

The parent's `external-storage-observation.json` records all23 held original
roots with `Parent=nil`, no live same-name roots, and exact Source/editor
equality for these12 modules. Current mirrors also match their clean HEAD9cc
versions and these held Sources. No enabled/run-context fields apply to
ModuleScripts; Archivable=true, LinkedSource empty and attributes empty are
verified for all12 manifest entries. There are four distinct Source digests.
Identical Source does not prove identical folders, properties or assets.

A separate bounded native Edit names-only read verifies exactly these12 known
paths absent. At that later read native source count was213, with three new
concurrent modules/scripts absent from the working manifest:
`ReplicatedStorage.SceneEffectBudget`,
`ServerStorage._OptimizationGeometryInstall_20261009`, and
`StarterPlayer.StarterPlayerScripts.SceneEffectBudgetClient`.
`native-names-only.json` records that scope. It contains no Source read or write
and does not establish final parity.

## Callers, dependency closure and authoring contracts

- Exact root/module-name searches across current runtime mirrors, tools,
  asset records and docs found no active caller of these six roots. The
  historical `docs/POOL-SLIDE-SERVER-USAGE-2026-09-09.md:109–110` records
  installation/context backups. Current cleanup capture/verification helpers
  intentionally reference the allowlist as archive inputs. Historical audit,
  observation and archive records are evidence consumers, not gameplay callers.
- Controller copies require sibling `Level 2 Pool Slide Navigator`,
  `Level 2 Pool Slide Configuration` and `Level 2 Pool Slide Rig Adapter` at
  module initialization (lines11–13). Those calls can wait/initialize modules;
  this review never executes them. `Start`, `Stop`, `IsRunning` and
  `GetDebugSnapshot` own the subsequent gameplay tasks, runtime objects,
  player attributes and dependencies. Preserve every source byte in archive.
  The renamed MP backup siblings are not repaired or loaded as live modules.
- Navigator copies obtain PathfindingService/Players at initialization, define
  their API/defaults and return the module. They have no module-scope requires.
  Their task/connection/pathfinding lifecycle belongs to invoked methods;
  these methods are not invoked during the source-contract gate.
- `PreviewControls` returns `Sample`, `PlayFor`, `Stop`. Its invoked workflow
  requires Edit, the exact `PipeEntity_Final_20260909` workspace model,
  the exact authoring folder, `AuthoringOwner=level2-entity-2026-09-09`,
  non-superseded state, matching `NormalizedModelScale` and named
  KeyframeSequences. It registers/plays tracks, owns preview objects and
  restores bone transforms. Names/status alone are not retirement evidence;
  the owner's explicit workflow retirement supplies the product decision.
- `tools/publish_entity_animations.py:94–146` uses the separate
  `MongoTVEntityAnimations` cache and published-ID reuse. It is preserved.
  `tools/level2_blender/import_kit.py` stages `__<kit>_Installing_...` and
  `__L2KMeshWire_...`, not these retired roots. Active Level2 helpers, rigs,
  collision/nav parts and authored animation source packs remain outside S06.
- Generic mirror/sync tools consume the manifest. None was invoked to push,
  recreate or delete native objects. Removing only absent entries in a future
  batch makes the downstream record match verified native absence; it does
  not authorize a repository-to-Studio push.

## Risk, benefit and test port

Risk is low for downstream-only file/row retirement once the native archive
gate passes. Risk would be high if source equality were used to delete whole
backup trees or to retire animation publication/recovery workflows. That is
outside this allowlist. The concrete benefit is moving944770 source bytes and
12 stale entries out of the canonical native mirror; no FPS/memory saving has
been measured or claimed.

Before removal, the port has passed:

1. Exact twelve-source HEAD/manifest/held-native Source and editor contracts;
   selected paths/classes/properties/attributes and external root absence.
2. Byte-exact private checkpoints and public source archive reload; real
   Luau0.737 O0/O1 compiles for every private source copy (24) and every public
   archive copy (24). No module was required.
3. Actual validator/proposal tests: three positive cases,17 meaningful negative
   controls,28 checks. Concurrent source/HEAD changes, editor conflict,
   unreadability, digest/length/class/attribute/property/path drift, duplicate
   identities, target reintroduction and unexpected formatting reject.
   A concurrent extra manifest row/top metadata survive, including correction
   of stale actual counters. No source/manifest writes occur in this fixture.

Still required: reviewed retirement wrapper performs a fresh read-only native
absence/held-original Source/editor/class/property/attribute guard before and
after retirement. It verifies every remaining current working mirror against
native Source/editor and relevant properties, and compares current live Source,
root, remote and scene-structure signatures. Then remove exactly the archived
twelve files/rows with CAS and exclusive restoration on failure; preserve all
other actor rows/top metadata and unrelated RoundUI bytes. Compile and verify
all remaining current source mirrors. Scene-structure signatures do not certify
every geometry/asset property.
Native full-object reopen is not a gameplay/streaming/multiplayer pass.
No gameplay removal is performed by S06: the originals were already moved out
of the DataModel by another actor.

## Rollback and manifest proposals

`../retired-external-repo-mirrors/` contains exact raw source copies,
`manifest-before.json`, byte/digest mapping in `archive-preparation.json`, and
scoped `-text` attributes. It is an off-mirror source archive, not a full place
backup. The separate `../external-storage-archive-v1/native.rbxm` retains the
23 native trees; its2739764-byte raw native backup passed with digest
`139a76d70022770ac30b0a4e9cfaeaea967668955ab0930666de0d3ab1f23dca`.
The engine deserialize trial verified21 readable root trees,12 Sources and ten
internal references; two old model root digests differed. All23 test copies
were cleaned up, original Source/editor/property and native binary hash guards
passed. It remains a failed full-forest readable/opaque restoration gate. The
parent expressly separated that result from this source-only downstream batch:
the candidates are twelve local mirror files/entries for sources already
removed externally, with exact source archive/reload and fresh native guards;
this batch does not remove native trees or any live runtime feature.

Private immutable checkpoint/proposals are in
`.git/mongotv-cleanup-20261009/s06-retirement-before-v2/`. The working proposal
preserves the dirty unrelated RoundUI row. The initial staged-manifest proposal
derived from HEAD9cc plus the then-frozen S03 Ambience/S05 Level2Sound changes
and these12 row removals. It kept the HEAD RoundUI row and every other actor row.
Both initial proposals are210 scripts/225 rows/15 remotes; this is the scoped
baseline arithmetic, not current native parity. The execution wrapper takes a
fresh working manifest and preserves concurrent owner exports, including any
new rows; its working counts follow actual surviving rows. The private commit
blob now retains only S03/S09/S06 over the current HEAD when its manifest is byte
identical to the reviewed9cc baseline (HEAD later advanced to9c6d713f without
manifest changes). The other actor subsequently changed Level2Sound to7a0fe436;
that working file/row is preserved and excluded from our commit. Its HEAD77afb
row remains in the scoped blob. The original S05 export receipt/proposal is
historical and superseded for staging. S09 freshly verified and exported only
`StarterPlayer.StarterPlayerScripts.SoundController` (General Sound) from native
Source/editor:68062 bytes/SHA022342ec4e78d46d28319198f05174ffae84261e9e075cc42820b5219fc0bf02.
The new combined S03/S09 input is4ee2083b1f71fc3d30448e4f2e37433c638b31937f10fc39e205e827eb09f2c0.
A changed HEAD manifest requires a fresh scoped review.
No working manifest replacement or source retirement has been performed yet.

The final wrapper v3 offline gate in `retirement-offline-tests-v6.json` passed
13 cases/5440 checks. One actual success compiled210 copied current source
files at O0/O1 (420) and the exact generated read-only Luau guard at O0/O1 (2).
Eleven failure ports cover initialization, native class/path drift, partial
unlink, actor manifest edits, atomic replacement/compile failures, native
after-signature drift, actor row/source reintroduction, Play and client cleanup
failure. These tests run the actual wrapper in owned temporary repositories
with fake MCP/native boundaries. Actual native v3 subsequently rejected the
concurrent GameManager Source mismatch described below. Transport cleanup
failure rolls back within the reversible transaction;
it cannot leave a successful retirement receipt.
The additional successful scenario has one extra native Source and proves
`nativeMirrorCoverage.allLiveSourcesCovered=false` is reported. The receipt
records before/after live Source counts and verified working-mirror counts
separately. A subset pass does not establish all-source parity, and the scoped
commit's historical210-source manifest is distinct from a working manifest
that includes the other owner's two new Source rows.

Reproduce the read-only fixture using portable archived inputs:

```powershell
python -B tools/cleanup_20261009/test_external_mirror_retirement_preflight.py --source-root artifacts/cleanup-serverstorage-20261009/retired-external-repo-mirrors/sources --manifest artifacts/cleanup-serverstorage-20261009/retired-external-repo-mirrors/manifest-before.json
python -B tools/cleanup_20261009/test_retire_external_mirror_sources.py
```

The second command uses two exact, hash-pinned public historical manifest
inputs in `offline-inputs-v3/`, the public12-source archive, and losslessly
compressed full capture facts. It requires no private `.git` checkpoint or
current historical HEAD. Altered historical manifest bytes are rejected.
The actual retirement wrapper retains its separate fresh working/current-HEAD
CAS and private-checkpoint requirements; the fixture inputs are not a current
Studio deployment baseline.

`preflight-v2.json`, `offline-archived-input-tests.json`,
`retirement-offline-tests-v6.json`, `scene-digest-offline-v1.json`,
`native-names-only.json`, this review,
the exact public inputs/archive and the reviewed helpers are task files.
The initial preflight/fixture receipts are superseded historical attempts;
private checkpoints are not for committing. No secrets or caches are included.
Full native reopen failure details and strict local facts inflation instructions
are preserved in `../external-storage-reopen-v1/REVIEW.md`.

## Failed native preflights and bounded scene port

Actual native v1 rejected the100000-node scene limit before any file removal or
manifest write; fresh Edit had416276 descendants. `guard-failed-census-v1.luau`
is the exact generated read-only input (120599 bytes/SHA691cb5eb5c4e92abc862ae4111cf81e08dd28d552fed79b381edcceab15c03cb).
`../retired-external-repo-mirrors/rollback.json` preserves the failure and empty
removal/restore lists. The original private checkpoint is unchanged.

Actual native v2 passed that broader census but rejected a concurrent native
General Sound Source mismatch before any file removal or manifest write.
`guard-failed-source-v2.luau` is the exact input (122846 bytes/SHA1c61712c08cffe0507a1f81b8f9b98c83e96861cd516e119eac30cc9802a8c97).
`rollback-v2.json` is immutable. S09 reconciled that one Source downstream; no
native Source was edited. Neither rejection is a gameplay regression caused by
cleanup. V3 uses new checkpoint and success/rollback-v3 names; it never clears
the older checkpoints, results, held-original ledger or S04 state.

Actual native v3 rejected `ServerScriptService.GameManager` Source drift before
any file removal or manifest write. The other owner has unrelated dirty
GameManager work. Root preserved it and left these12 candidates pending rather
than chasing that changing baseline. `guard-failed-source-v3.luau` is the exact
generated input (122871 bytes/SHA6e1366f7407681aa274a8c25dde5dd514e2d26f0f0607923c4eb9590f1a54859).
The unchanged `rollback-v3.json` has485 bytes/SHA258eaad7912cda759e658d155969f0fff7750fea6b3aba45bc71c62044eece08,
empty restore/removal lists and `manifestCommittedBeforeRollback=false`.
All12 canonical files and manifest entries remain. The private v3 checkpoint,
failed guard and failed receipt remain immutable. No fourth retirement attempt
or unrelated runtime reconciliation is authorized by these historical receipts.

The current scene digest keeps exact canonical name/class/parent rows and
duplicate multiplicity, capped at500000 objects. SHA256-derived256 buckets each
hold at most10000 unique rows; sort each bounded bucket and seal it in fixed
order. Census/digest construction checkpoint every1000 rows and after each
bucket. There is no full416k sort or recursive full-scene serialization.
`scene-digest-offline-v1.json` executes the identical extracted helper with real
offline SHA256:12 cases/14 checks,416276 rows,100001 unique rows, reorder equality,
changed-row/multiplicity distinction, exact500000 boundary, over-cap/oversized
bucket/invalid hash/count/interrupted-checkpoint rejections. The actual helper
compiled with Luau0.737 at O0/O1. This does not certify native getter behavior,
continuous snapshot consistency, full asset geometry, gameplay or performance.
