# Tooling cleanup results, 2026-10-09

Root authorized the tooling batches after a fresh native baseline: 230 scripts, 15 remotes, exact source/hash/class/properties/attributes parity and no editor-source conflict. This agent made no Studio, manifest, runtime economy, bot, vault or upload changes and no commits. Before-file bytes and SHA-256 manifest are retained in `.git/mongotv-cleanup-20261009/tooling-before/`.

## B01a — native mirror safety (T03/T04/T05)

- `tools/sync_from_studio.py` now uses the existing direct native Source chunk reader with length/djb2 verification; it no longer substitutes `script_read` editor text for native Source.
- Pull enumeration and full-sync orphan discovery now share one service tuple that includes ReplicatedFirst.
- Full sync refuses pending/conflict work before creating its client or writing files. An unreadable existing manifest also fails closed, preserving unknown queue state.
- `test_full_sync_contract.py` covers stale editor vs current Source, a multibyte source larger than 200KB across chunks, corrupt chunk verification, loading-script change/new/orphan discovery and untouched pending/conflict/invalid-manifest bytes. Existing CRLF/+LF canonical contracts remain green.

**Gate:** source contract PASS; full-sync integration PASS. No real sync was run. Full sync is still a sequential exporter, not a transaction over every file in a changing place; fresh parity and concurrent-change handling remain required.

## B01b — literal and fixture safety (T06/T07/T08)

- Generic installer lookup/update payloads use the existing safe Luau literal encoder for path segments and source. A new offline Luau fixture passes **20 checks**, including Danish/accent/emoji paths and source, quotes, backslashes and control bytes.
- That test revealed fake Studio decoded Unicode object paths using Windows' default subprocess text codec. `tools/tests/fakestudio.py` now decodes actual Luau stdout as UTF-8; no production engine is involved.
- Layout mutation_check constructs its mutant in memory and writes only its OS-temp runner. It no longer overwrites/restores MODULE. Guarded source-write and interrupted real Luau-child checks passed. An independent corridor wall-gap oracle accepted the historical baseline and rejected the length68 mutant.
- Receipt and inventory fixtures now load actual ZyntraSkins and DevAccess modules through their fake engine boundary. Current receipt assertions pass **299 checks**; inventory assertions pass **87 checks**. Receipt scenarios include duplicate/rejoin, concurrent callbacks/servers, failure-before-commit, commit-then-error, bounded supporter-cache recovery and unavailable/closing sessions.
- Meaningful negative controls failed on the intended balances: disabling receipt dedupe produced expected6/got10; removing item debit produced expected2/got3. The verification harness checks these failures and protects actual runtime source hashes.

**Limitations:** retired Level2 Kit/Layout source inputs are absent from the current runtime mirror. The historical planner in git predates today's full vault/swerve oracle; the full legacy authoring suite remains **pending**. The temporary historical fixture is never restored to repo runtime or Studio. Inventory87 covers failure-before-commit, not full operation-ID/refund/disconnect safety. Receipt fixture stubs the actual reentry invocation and cannot certify reentry debit/refund behavior or live Roblox economy.

**Reproduced unresolved CORE-004:** with the current actual inventory handler, a fake DataStore commits a debit and loses the response. Consume returns false while durable markers fall3→2; a fresh retry succeeds and falls2→1. This is recorded failure evidence, not an economy pass or an observed production incident. Durable item-operation remediation and its full lifecycle fixtures remain pending. No economic implementation was changed.

## Additional baseline foundations

- `tools/tests/test_push_repo_to_studio.py` formerly refused installed official Luau0.737 because its probe used unsupported `--version`. The authorized correction executes an OS-temp Luau program and requires the exact success marker and exit0 before the suite can run. The full fake-push suite **PASS: 18/18 cases executed, 82 assertions, 0 failed**, including conflicts, compare-and-swap races, staged transfer, rollback copies, cleanup and actual compile rejection/recovery. Result: `test_push_repo_to_studio.after.txt`/`tooling-after-checks.json`.
- `tools/level6_build/import/build_material_installer.py` had nested f-string quoting that required Python3.12; available interpreters are Python3.11/3.10. Extracting the metalness URI preserves the generated row. Python3.11 fixtures verified exact golden rows with/without metalness, normalized asset IDs and MaterialsJSON roles; generated Luau compiles. No existing material output or Studio import was run.
- Fresh Python AST scan passes **450/450** tooling/plugin files after the compatibility correction. No FPS/MB claim follows from these checks.

## B03 — doc and one-file cleanup (X05/T18)

- Corrected the actual U+0008 in `tools/level4_blender/README.md` to the verified rollback path `G:/Roblox/_local/l4public/backup/Workspace__Level_4_Cinema_Preview.rbxm`.
- The asset exists, size280679 bytes, SHA-256 `9de33df7bc34cbcb8940013e15bf436a468fa2cc57dc07124cce437fdaaaed78`.
- Removed only tracked, zero-byte `tools/level2_poolrooms/smoke_tmp.py`, after exact filename references and manifest checks found no consumer. Its empty before-file is preserved. Other empty QA/parity/vendor package files remain.

**Gate:** resolved target checked before edit/deletion; docs control scan and post tooling AST verified. No initializer side effects existed in the empty helper. No runtime/native object removal occurred.

## Review and rollback

`git diff --check` passed. Exact post-test logs and JSON results are under this folder; root owns final diff/staging, commits and Studio/repo parity. No batch was rolled back. Development-only negative mutants intentionally fail inside OS-temp fixtures; they are not installed anywhere. No performance scenario was modified or measured.

Changed tracked paths: installer, pull/full sync, Level4 README, zero helper, Level6 material codegen, fake Studio, full-sync/receipt/inventory/layout/push tests. New test: `tools/tests/test_install_new_scripts.py`. The root must explicitly stage selected ignored artifacts; no broad add is authorized.
