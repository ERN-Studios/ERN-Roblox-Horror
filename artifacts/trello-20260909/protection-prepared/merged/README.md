# Developer tag + protection purchase merge

Prepared full-source integration only. Runtime, Studio, DataStores and publication are unchanged.

`proposed/ServerScriptService/ZyntraMonetization.Script.lua` is **114500 bytes**, SHA `1f44dfa34ef69fec7cf04be80007498a1945afde0422e2e099ec9a8675d53ef4`. `proposed/ReplicatedStorage/ZyntraConfig.ModuleScript.lua` is the exact reviewed transaction Config, SHA `e135906911e606de53411cacc9f9b2376f8e9734ec556ea34403716dc504484a`.

`prepare_merge.py` checks the two reviewed proposals share the identical original source, snapshots all inputs under their SHA, normalizes line endings for Git's three-way text merge and refuses any conflict. The merge was conflict-free. `developer-to-merged.diff` shows only the protection additions; `transactions-to-merged.diff` shows only Developer-tag changes. No new feature behavior or manual conflict resolution was introduced.

Inputs:

| Input | SHA256 |
| --- | --- |
| Common original | `a381ce02e48dd5c4f7333d8e09e67b9ffd52f137389701b1c234138647ebb789` |
| Developer proposal | `a707c6ed610ef47ae08757993653e2d2d9a74a8d9eccb02328f067ca8fca3a03` |
| Transactions proposal | `d684924da96df79e879833c421729df66de845ec37a5603d22dfd732605224f8` |

`test_merged.py` imports the original behavioral suites and runs them against the combined source: **83 Developer + 215 transaction + 236 receipt checks pass**, and both full merged files compile. The only extraction adaptation changes the former `addSupporterTag` DTO boundary to Developer's `local tagCharacters = {}`. Developer's original baseline/style fixture is preserved. Tests write to their own `checks/` folders, leave original runners and snapshots unchanged, and validate a separate exact runtime checkpoint. That checkpoint accepts only the original Monetization or the exact reviewed Developer release; unrelated runtime drift is refused. Its hash is recorded before and checked after testing. The original historical baseline files are not rewritten to claim that a later legitimate release never happened.

The existing `../native-fixture/prepare_native.py --source <this merged Monetization>` has regenerated the Play-only full-script fixture. Current fixture SHA is `92f78aae8fa45dbf96348d7fe651f8747eff7fb4271b70a49765fd6593bcbb82`. Its memory backend remains byte-identical at `2e3c6fdfc7cac6df485d9071e283c4f3aa114ecb0c729a61aee8803ee87c35b0`. **73 fixture checks and both complete fixture compiles pass**. Its manifest and hash-named source snapshot now point to this combined source, so Developer-tag code survives native test isolation.

This does not install or execute the fixture in Studio. Root must follow the existing native-fixture owner/run-ID isolation instructions, validate the combined UI and complete PlayerProtection/AI integration, stop Play and verify production source parity before publication. If native Developer QA changes its source, regenerate this merge from that exact reviewed input and rerun the affected checks before installation.

Independent integration critic: **9/10**, with all83+215+236+73 checks and complete compiles rerun independently. A separate three-way reconstruction matched the merged source byte for byte, and the fixture transform/snapshot matched its manifest. See `independent-review.md`. No remaining code blocker was found; native combined integration remains pending.
