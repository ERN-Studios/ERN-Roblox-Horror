# Independent prepared-code review — 9/10

Reviewed 2026-09-10 by the independent critic. This score covers the proposed code and offline evidence, not a completed native multiplayer release. No source or Studio changes were made by this review.

Reviewed frozen hashes: GameManager `35a462287d32d8db38920d3849f1bea06a3c6272054acc390d750ec1ebbc0a15`; RoundUI `068aaaf68b2db0202847ec7444293468bd4e97198d3fa546e7ce230ae7e1a7fe`; UIRegression `dc25736196dc893fb97f9624a8de98599cd6103d977f3f43c8e8d3ec5a3fe140`.

I read all three exact diffs, the actual surrounding intermission/transfer/lifecycle code, the unchanged Routing roster and admission contract, and the test extraction/host. I independently ran `test_party.py`: **189 checks, two specific negative controls and three whole-file compiles passed**.

No blocking code issue found. Continue records an authoritative choice without an early teleport; one settlement produces the continuing cohort. The no-timeout policy is explicit in root's agreed scope. Ready may change to Lobby while the decision window is open. Reserved-server opt-outs hold the barrier until actual departure, and the existing failure path restores their choice. A waiting continuer who disconnects becomes Gone, avoiding a phantom expected arrival. The transport clock begins at settlement and is still extended by the existing Routing arrival horizon, without a new routing implementation.

Client serial/revision checks and the corrected own-choice acknowledgement guard are appropriate. A newer peer snapshot updates the rows while preserving our pending click; it cannot re-arm our actions before the matching choice arrives. Closed snapshots lock the local controls. The six rows are noninteractive, and the actual layout checks preserve existing action targets across the seven tested sizes. Native font metrics are not simulated.

Root release acceptance should observe more than one real client choosing at different times: no dispatch while one is waiting, visible peer choices, Ready-to-Lobby/actual departure, and the remaining ready cohort advancing together. A focused rejected opt-out test can reuse the existing transfer failure machinery. Desktop and one shallow/touch layout should confirm all six long-name rows and the action area remain readable. Offline fixtures do not prove live Roblox transport, native font fit or a full multiplayer campaign.

The existing comments referring to a 15-second countdown/immediate continuers are historical and now stale in several unchanged adjacent blocks; this does not alter execution. More importantly, root's spawn work has legitimately advanced GameManager beyond this proposal's original baseline. Apply the narrow transform onto that checkpoint and review the resulting merged diff; do not install this full old-baseline Manager over it. The raw-baseline mismatch in the test report is correctly disclosed.

## Installed merge readback

Root subsequently installed the focused merge. I independently reconstructed all three transforms from `installation/before`, checked their SHA values against `installation/installed-rebase.json`, and compared the outputs byte-for-byte with both `installation/merged` and current production files. All three matched. GameManager's spawn baseline `4d0ee8f3f4af1945d558b3711565f4434f183b766c46e91ee74f16b4d68f7d29` produces exactly installed `83ae02f5e5748e78af9f50b1be0c2abffdf01f070fdd355cba8fbfc9005407e8`; RoundUI and UIRegression retain the reviewed proposal hashes above. No additional source change or merge loss was found. The code score remains 9/10; native acceptance is separate.
