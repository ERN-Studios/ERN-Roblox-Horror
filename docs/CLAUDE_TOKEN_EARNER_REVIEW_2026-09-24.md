# Token Earner integration review — purchase blockers

Independent read-only review of Claude commit `91106da`, 24 September 2026. The existing 350 Token Earner, 58 completion-save and 329 friend-boost offline checks pass. They do not model two ownership refreshes interleaving around a purchase. The six Game Passes remain **off sale**; keep them off sale until both issues below, publication and purchase/rejoin QA are resolved.

## 1. Confirmed purchase can be temporarily downgraded

`ServerScriptService/ZyntraMonetization.Script.lua` around lines 2103–2115 checks the local purchase latch, then yields inside `UserOwnsGamePassAsync`. A refresh already in progress can therefore use a pre-purchase cached `false` after the purchase-finished callback latches 2× and starts a new refresh. The earlier refresh can publish `ZyntraOwnsTokenEarner2x=false` after the newer refresh published `true`. It can also carry a stale `earnerOwns` table through later pass reads and publish tier 1 at lines 2177–2182 after the purchase callback's tier 2. A latch recheck only inside `passOwnership` does not fix the second interleaving. A Luau 0.737 harness using the exact extracted repository functions reproduced **tier 2 after the purchase refresh, then tier 1 after the stale refresh resumed**.

Required behavior: a refresh started before a confirmed purchase must never overwrite a newer ownership snapshot. Serialize refreshes or use a monotonic generation so only the latest can publish, with purchase latches winning after each yielding ownership read. Compute the tier from the final monotonic snapshot. Add a deterministic test that pauses refresh A on a 2× ownership read (and again on a later pass), completes the purchase callback and refresh B, resumes A with cached false, then asserts the pass attribute and multiplier never drop. Cover 2×, the upgrade chain, and a failed ownership read. A live purchase/rejoin test is still required.

## 2. Off-sale offers appear purchasable

`StarterPlayer/StarterPlayerScripts/ZyntraStore.LocalScript.lua` around lines 1887–1893 creates three Token Earner cards, and lines 3266–3272 enable BUY when an ownership offer exists. The UI does not check sale state. If published while the six passes are intentionally off sale, players can see active 149/299/399 R$ offers that cannot complete. Hide or disable the three paid cards until the pass sale state is enabled, or explicitly label them unavailable. Preserve dynamic price/ownership checks when sale begins.

Both findings are tracked as unchecked items on [the Token Earner card](https://trello.com/c/EtdsUM4e). This review did not edit game code or Studio. No other definite material issue was found in the reviewed commit.
