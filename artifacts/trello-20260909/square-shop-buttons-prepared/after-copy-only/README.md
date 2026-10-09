# Square buttons after published copy only

This is the variant for the user's narrowed request: finish square buttons and lobby lights, then stop and commit/push. ESP and free DEV respawn remain deferred. Their existing artifacts are unchanged.

Input is the exact published v1872 Store, SHA `083c53b7639a578c64398f1da077745c07f1d99d03fd8421c660ef9619d87c71`. The existing reviewed square transform is imported without modification and given the verified uploaded IDs: shops `132462891522145`, upgrades `119432640057145`. The proposal is `proposed/StarterPlayer/StarterPlayerScripts/ZyntraStore.LocalScript.lua`, SHA `fa63e760427012ec3fdb08712b4edc5482629b242254503504a861869f4268d2`.

Exact inverse restores every input byte, including the published two-sentence copy removal. No ESP or free-respawn payload is added. Existing DEV controls already present in v1872 remain intact. The unchanged original square host and assertion set run against this exact composition in test_composition.py; exports stay in this folder. No old variant, test result, runtime source or Studio instance is overwritten by these scripts.

Root must verify that the actual Store baseline is exactly083c before installation. Root owns real UI/image-load/click/modal checks and the required independent native10/10 score; prior artifact10/10 is not the final native score. This folder's manifest records prepared status only.
