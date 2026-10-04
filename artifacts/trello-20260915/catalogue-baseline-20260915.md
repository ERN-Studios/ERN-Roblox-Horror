# Catalogue baseline — 2026-09-15 (#87 preparation only; NOTHING changed)

Owner answer 2 (19:44 UTC): the 50 % / 14-day sale must NOT be started, scheduled or
claimed yet. This file only records the authored baseline so a later, owner-approved
sale can be reversed exactly. Source: `ReplicatedStorage/ZyntraConfig.ModuleScript.lua`
at git `d17fa28` (unchanged tonight). Live platform prices are fetched at runtime by
`ZyntraStore` (`displayedProductPrices` via `MarketplaceService`) and were not read tonight
(requires a running server); Codex/owner should confirm them on the Creator Dashboard
before any sale.

| Item | Kind | Id | Config price (R$) | Grant |
|---|---|---:|---:|---|
| Zyntra Supporter | Game pass | 1941938256 | 99 | +10 tokens once, tag |
| Advanced Equipment | Game pass | 1945402536 | 149 | hazmat picker + 1 upgrade each |
| Glowstick Customizer | Game pass | 1946086261 | 99 | glowstick picker |
| 4 Research Tokens | Dev product | 3707755089 | 49 | +4 tokens |
| 20 Research Tokens | Dev product | 3707755233 | 149 | +20 tokens |
| Emergency Re-entry | Dev product | 3707755318 | 29 | +1 re-entry credit |
| Donate — Signal / Supply / Field / Research / Command / Director | Dev products | 3710116814 / 3710116945 / 3710117017 / 3710117070 / 3710117099 / 3710117136 | 10 / 50 / 100 / 250 / 500 / 1000 | none (donation) |

Token prices (unchanged): upgrade 1 token per +5 % level, Entity Shield 5 tokens.

Notes for a future sale design (not authorised now):
- Platform prices for passes/products are edited on the Creator Dashboard; the game
  shows the live price (`displayedProductPrices`) with the config value as fallback, so
  a dashboard change and a config change must land together or the terminal shows the
  wrong number until the next fetch.
- Automatic end/restoration "even when the PC is off" cannot be done from the game
  client; it needs either Roblox's own scheduled price tools (if available for the
  product type) or a hosted job with Open Cloud credentials — an owner/Codex decision.
- Private-server price is set on the dashboard only; it is not in `ZyntraConfig`.
