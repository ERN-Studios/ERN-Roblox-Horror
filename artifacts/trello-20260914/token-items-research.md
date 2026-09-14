# Token items — card 44

Recommendation: start with a route-marker pack and a flashlight casing collection. These give Research Tokens repeat uses without replacing the survival loop or the existing paid colour pickers. These are proposed product decisions, not implemented catalogue entries.

Current local catalogue: 2 tokens per level completion; permanent +5% Stamina/Battery upgrades; Entity Shield costs 5 tokens for a stored 5-second charge. Advanced Equipment already sells the hazmat colour picker and one upgrade to each capacity; Glowstick Customizer already sells glowstick colours. Do not resell those same entitlements as new token items.

| Candidate | Proposed token price | Purpose and limits | Effort |
|---|---:|---|---|
| Route-marker pack | 2 for 3 placements | Team-visible floor arrows for maze navigation; limit active markers per player, remove at round end; never auto-reveal the solution | Medium |
| Flashlight casing skin | 10–20 permanent | Equipment appearance with identical light, battery and collision; avoid large glowing silhouettes that undermine darkness | Medium |
| Field-researcher titles | 6–15 permanent | Lobby/result-screen title unlocked after an earned milestone; distinguish from Supporter/dev badges | Small |
| Emergency battery cell | 3 single use | Restore 25% battery, one use per round, cannot exceed capacity; hold until telemetry shows battery scarcity is enjoyable rather than frustrating | Medium |
| Noise lure | 4 single use | A short 3D sound at a valid thrown location; entity reacts through existing hearing; requires careful Level 1/2/3 balance and anti-grief checks | Large |
| Death-card / results-frame themes | 8–12 permanent | Cosmetic collection with no combat effect; maintain phone readability and accessible contrast | Small–medium |

First release proposal: route-marker pack at 2 tokens, three flashlight casings at 10/15/20, and two milestone-gated titles at 6/10. Keep purchases deterministic and visible before spending. These prices are hypotheses calibrated against 2 tokens per level and the current 5-token shield, not measured willingness-to-pay.

Measure token sources/sinks, wallet distribution, time to first token purchase, repeat use, completion rate by item, and phone/tablet use. Do not balance around token-pack Robux prices alone. Roblox recommends tracking acquisition, spending and use and testing prices against actual behaviour: [Balance virtual economies](https://create.roblox.com/docs/production/game-design/balance-virtual-economies).

Avoid selling required CD hints, mandatory exit access, stronger permanent entity immunity, or a second copy of existing pass cosmetics. Because tokens can also be bought for Robux, random token rewards add paid-random-item requirements; fixed rewards keep this proposal straightforward. [Roblox paid random item guidance](https://github.com/Roblox/creator-docs/blob/main/content/en-us/production/monetization/virtual-items.md).

Source inspection: ReplicatedStorage/ZyntraConfig.ModuleScript.lua and the active ZyntraMonetization implementation, 2026-09-14. Card 44 asks for research and suitable proposals; this deliverable completes that research, with implementation awaiting an item selection.
