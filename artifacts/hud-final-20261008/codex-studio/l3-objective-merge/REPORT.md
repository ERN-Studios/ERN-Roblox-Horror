# Level 3 Objective Controller: fresh-live merge

Only `ServerScriptService/Level 3 Systems/Level 3 Objective Controller.ModuleScript.lua` was changed in product source. The candidate starts from the fresh Studio audit copy, then applies exactly two existing HUD copy/key call changes:

1. CD pickup: sentence-case recovered/found and key `level3:cd`.
2. CD insertion: sentence-case "put n CD(s) in the player", middle-dot progress separator and key `level3:insert`.

The diff has exactly two call hunks. Reversing those two replacements reproduces the original live bytes exactly. Every newer live change therefore survives unchanged, including the all-living-survivors beyond-50% finale gate, MallManagerController.Stop, replicated CDPlayerPosition and the newer exit/world visual work. The live file's 1,770 CRLF line endings were preserved.

| File | SHA256 |
|---|---|
| Repo before CAS merge | `c380e6801b787bd375713321694300bc48ed27c60163f97b759ff38cbb49072a` |
| Reviewed fresh-live baseline | `b0e7741edf0d9258a432293c8102f547c5c168a12300a75d53fde0109d36e06e` |
| Final candidate/product, 77,241 bytes | `9ecdb90bec658187a1fa930086ff86d7031efb7c7f189c4a1df48c0b735d16eb` |

CAS verified the current product hash before each authorized write. `repo-before-merge.lua`, `Level 3 Objective Controller.candidate.lua`, `live-to-candidate.diff` and `proof.json` preserve the review evidence.

Validation: candidate compiled with official Luau 0.737; `test_level3_first_cd.py` passed 7,937 checks across 240 seeds. Native Roblox Random and live engine behavior are outside this offline check. No Studio calls, lock operation, git operation or other product edit was performed.
