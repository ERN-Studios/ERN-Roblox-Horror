# L2 generated world root correction

The root's actual two-client Level 2 test observed a Workspace model named `Level 2 Generated World`. The installed effect budget client looked for `Level2PoolroomsMap`, so it never bound the generated runtime world. The exact one-line patch changes that CONFIG key. Radius 320, hysteresis 48, `Water FX` scan root, other level configurations, and controller lifecycle remain byte-identical.

Fresh authoritative Edit Source/editor parity was captured at `2026-10-09T22:11:58Z`, LocalScript `StarterPlayer.StarterPlayerScripts.SceneEffectBudgetClient`, instance `0_79286921`, parent `1_410029`. Before SHA256: `f39408bcef93a6e6513d48a0806ddc736c28a69962eb23c992c0722f3487a5be` (3532 bytes). Corrected SHA256: `d87559348d39821adfb35191a3b8b030967537cc0d8da955222217d7686bcaa0` (3537 bytes).

Root applied the correction with its scoped CAS installer; `source-install-receipt.json` records successful exact Source/editor verification at `2026-10-09T22:14:29Z`. This subagent made no Studio edits and no backups.

`prepare_and_test.py` compiles the complete corrected controller and a mocked full-controller native fixture. Twenty discovery/lifecycle checks pass, including actual generated root binding, Water FX options, duplicate discovery, root stream-out/re-entry, disabled/re-enabled sessions, other level configurations, views and cleanup. The identical test fails against the before source specifically at generated runtime world binding. The prepared `native-controller-contract-probe.luau` returns a function with `{checks=20, realGameplayStreamingPerformancePass=false}`. It uses only mock services/models/signals and borrows no gameplay state; root has not executed it through this subagent.

`refresh_verified_source.py --apply-mirrors` freshly reread all seven native Source/editor and instance/parent pins before and after the correction export. It wrote an exact raw correction export under this folder's `verified-export/`, refreshed the current task raw controller export and runtime controller mirror after each exact old-local f394 SHA guard, and changed only that controller row in the seven-source task export manifest. `verified-source-refresh-receipt.json` retains the previous row metadata and native verification timestamps. Initial install, promotion and native receipts remain intact. The global sync manifest was not written by this subagent.

`refresh_global_manifest.py` prepares a seven-source-row/two-new-entry update using the current dirty global manifest, with exact current-file SHA and HEAD provenance. The prepared `global-manifest-plan.json` and `studio-sync-manifest.proposed.json` preserve all non-target items, existing target non-source fields, unrelated top-level metadata, remote events and historic operation totals. Only verified source fields, two missing budget source entries, script/total membership counts and trailing-newline count are refreshed. Eighteen in-memory preservation checks pass (`global-manifest-plan-test-result.json`).

Root reviews and applies the prepared metadata update:

```powershell
python tools/optimization_20261009/loading/install/compatibility/l2-root-fix/refresh_global_manifest.py --apply
```

Apply requires unchanged HEAD and exact current global manifest bytes, fresh read-only native seven-source CAS, exact runtime mirror hashes, and the reviewed proposed JSON. It refuses a concurrent manifest/HEAD change; root can prepare another fresh task-owned `--plan`, `--proposed` and `--receipt` path while preserving these records. This tool does not write Studio, stage/commit git, or take backups.

At initial correction capture, the existing two-client test copy still contained the old controller. Root subsequently started a fresh two-client session: actual generated-world binding and all eight near/far Water FX checks passed, with the temporary retention focus removed. See [fresh runtime result](../../../../runtime/observations/level2-fresh-budget-binding.json). Full traversal and matched performance gains remain unverified.
