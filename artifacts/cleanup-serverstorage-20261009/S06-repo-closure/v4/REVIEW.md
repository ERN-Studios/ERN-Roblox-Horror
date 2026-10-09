# S06 v4 preparation and offline gates

This is the reviewed source-only continuation after three zero-removal native guard rejections. Parent owns actual execution. Preparing and testing v4 did not call Studio, change canonical Sources or the manifest, stage, commit, publish, require archived modules, or initialize gameplay code.

The scope remains exactly the 12 ModuleScript mirror files and rows listed by the retained `retired-external-repo-mirrors/archive-preparation.json` and existing S06 closure. Those originals were detached by another session; this batch claims downstream mirror retirement only. The full 23-root native archive and exact 12 Source archive remain unchanged. Full object reopening failed readable equality for 2/23 roots; that separate restoration port remains uncertified. V4 does not certify or remove those native objects.

## Current reviewed inputs

Owner commit `37f09c9c0cdfa936717b659ac26e26a06677263b` includes the concurrent streaming/loading/scene optimization implementation. Its HEAD manifest has 224 script rows and 15 RemoteEvent rows (239 total), raw SHA256 `13ae3b1cd77fdf447a646b4798961af5ba4175d8ee42cc8e232aa7349e9f6c5b`. Current working manifest has the same counts and raw SHA256 `0532d938dde5cb53b9273ffbb6fbff4c053e1d87ec226c3266a8e045ece77faf`. The sole HEAD/working row difference is the pre-existing owner RoundUI row; canonical RoundUI is not changed or staged by this preparation.

Current exact expected HEAD is now `9635a38c3b434d1d573e33786eee2f11167bac60`. Its nine changed paths contain optimization documentation/publication records only; no Source or manifest file changed. HEAD manifest remains byte-exact `13ae3b...`. The first parent invocation of v4 (wrapper SHA `7e10cbec...`, expected37f) rejected this HEAD change before checkpoint/client/native/removal/manifest writes. Executed source is retained byte-exact at `early-head-rejection-v1/source.py`; reconciliation metadata and the parent-owned rejection receipt are separate. The latest wrapper differs only in the exact HEAD literal (`9635`); every native/CAS/rollback assertion is unchanged.

Both actual proposals derive directly from their fresh before-manifest and remove only the 12 allowlisted rows. HEAD scoped and working after-counts are 212 scripts, 15 remotes, 227 total. All surviving rows and top metadata are preserved; RoundUI remains separate in the working proposal. No old S03/S09 merge is needed because those exports already exist in HEAD.

`offline-inputs-v2/` retains exact current HEAD/working metadata inputs and raw/LF hashes. `source-deltas-v2/` contains only one byte-pinned existing owner Source, RoundUI (244,971 raw bytes, raw SHA256 `bd0d1dd235aace6d8be5b7ffedca8d16db2d4423c4d98895c8af274ca960ae73`), as an offline fixture input. It records explicit provenance and is never imported/required/initialized or copied into a canonical mirror. Unchanged HEAD Source bodies are not duplicated.

The first v4 input pair, wrapper/test snapshots and `offline-tests.json` remain historical: their 2231 HEAD configuration was superseded by the owner commit before any actual v4 execution. V1-v3 native failed guards/rollbacks, original archived sources, native binary/gzip facts and all previously committed evidence are retained byte-exact.

## Gates completed offline

`offline-clean-head-tests-v3.json`: actual v4 wrapper runs in owned temporary repos, with fake read-only MCP boundaries. Thirteen scenarios pass 5,503 checks. The success port compiles all 212 preserved real Sources at Luau 0.737 O0/O1 (424 compiles), plus the actual generated native guard at O0/O1 (2 compiles). Base Source files were copied read-only from exact clean owner HEAD37f; the one pinned RoundUI input supplies its observed working delta. Thus the port does not depend on uncommitted canonical owner Sources. Canonical Source/manifest writes and native calls are zero.

Failure scenarios cover initialization, native held class/path drift, second-unlink failure, actor manifest change before commit, atomic replace failure, a remaining compile error, native signature drift, actor Source+row reintroduction after commit, Studio changing to Play, and transport-close failure. Restoration preserves actor files/rows/top metadata; historical failed receipts are unchanged. The coverage scenario explicitly reports `allLiveSourcesCovered=false` for an extra native Source instead of claiming full parity. Both phases compute coverage strictly as live count equal to verified mirror count.

Modified manifest and modified Source fixture input are rejected before compilation/initialization. `head-cas-negative-v2.json` additionally invokes actual v4 main in empty owned fixtures and verifies that a different HEAD with an identical manifest, or a modified pinned HEAD input, fails before MCP creation, checkpoint creation or writes.

The native guard is unchanged SHA256 `d47a69e0f416c150ed7708e66e1f7a8f9d7118aa31971a117f87f44a6a8c23ef`. Its existing bounded scene digest port covers the observed 416,276 descendants and rejects exceeding 500,000. V4 has the same full remaining mirror/native Source-editor/class/recorded property checks, held original identity/path/source/metadata checks, Edit/Place/Universe/lease checks, before/after structural snapshot comparison, exact raw CAS and independent scoped rollback. No assertion was relaxed to force this continuation.

## Parent-owned actual execution

Only after parent peer review and an available authoritative Edit window:

```powershell
python -B tools/cleanup_20261009/retire_external_mirror_sources_v4.py
```

The wrapper pins the exact current HEAD revision as well as its manifest bytes. It refuses any existing `.git/mongotv-cleanup-20261009/s06-retirement-execution-before-v4` or `retired-external-repo-mirrors/execution-v4` output. It performs fresh read-only native guards before and after the local transaction and never switches mode. New output is `execution-v4/removal-receipt.json` or `execution-v4/rollback.json`; the private scoped HEAD blob is `manifest-head-scoped-S06-for-commit.json`. The first invocation failed at the exact HEAD assertion before entering its transaction. The reconciled current9635 transaction remains parent-owned; this preparation record contains no successful actual-removal claim. A new actor change must fail closed and be reconciled, never bypassed.

A clean clone can reproduce the offline port after the fixture/tool changes are committed:

```powershell
python -B tools/cleanup_20261009/test_retire_external_mirror_sources_v4.py
python -B artifacts/cleanup-serverstorage-20261009/S06-repo-closure/v4/head-cas-negative.py
```

The offline fixture reads gzip facts directly and verifies their exact lossless receipt. The actual wrapper expects the retained local raw `external-storage-archive-v1/facts.json`; if absent in a clean clone, inflate the gzip to that raw path and verify all compression receipt hashes before invoking actual retirement. This is not a full native asset, gameplay, multiplayer, streaming, performance, publication or continuous scene-epoch certificate.

The two v4 tools and guard hashes are fixed by the receipts and `freeze-invariants-v2.json`. No private Source-base copies, private checkpoints, mutable caches, raw 41MB facts or transport chunks belong in the v4 commit allowlist. Parent reviews/stages/commits the exact task paths and any successful actual receipt separately.

The immutable `offline-clean-head-tests-v2.json`, old test source snapshot, original HEAD-negative source/receipt and first `freeze-invariants.json` retain the prior freeze. The final fixture pins its historical Source index revision to37f explicitly, rather than comparing it to the wrapper's current docs-only HEAD9635; raw index/payload and Source/class/hash contracts remain exact. The negative runner now prints by default and accepts an optional new `--receipt` path, so clean-clone reruns do not attempt to overwrite committed evidence.
