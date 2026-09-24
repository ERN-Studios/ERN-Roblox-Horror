# Token Earner pass assets and IDs — 24 September 2026

The owner approved permanent multipliers for **future earned Tokens only**: gameplay, Daily Rewards and the wheel. Existing balances, bought Token packs, refunds and admin grants stay unchanged. The highest valid tier wins and does not stack. Direct tiers cost 149/299/399 Robux for 2x/3x/5x. Upgrade paths cost 150 Robux for 2→3, 100 for 3→5 and 250 for 2→5, so every legitimate path to 5x totals 399 Robux.

Six permanent Game Passes were created through the official Roblox Open Cloud Game Pass API for universe `10559217407`. Their IDs, prices, icon asset IDs and current sale status are in [game-pass-receipt.json](game-pass-receipt.json). **They remain off sale until the game code and purchase flow pass QA and are published.**

| Pass | ID | Requires |
| --- | ---: | --- |
| Token Earner 2x | 1995218405 | — |
| Token Earner 3x | 1995716395 | — |
| Token Earner 5x | 1994654411 | — |
| Upgrade 2x to 3x | 1994282418 | Direct 2x |
| Upgrade 3x to 5x | 1995812369 | Effective 3x: direct 3x or direct 2x + 2→3 |
| Upgrade 2x to 5x | 1994252411 | Direct 2x |

The upgrade passes can technically be bought outside the game's guarded shop. Each description states its prerequisite. The server must check the prerequisite chain and apply an upgrade only when it is satisfied. Early ownership remains a pending upgrade rather than granting a cheaper tier. The shop should present only eligible upgrades and never prompt a pass the player already owns.

The three icon designs were generated with the built-in image tool using `assets/monetization/icons-512/research-tokens-20.png` as a style reference. Prompts specified a centered embossed 2×, 3× or 5× gold medallion, dark industrial sci-fi background, cyan circuit glow and progressively richer token stacks. The three `source-*.png` files are the generated originals; `make_round_icons.py` creates 512×512 PNGs with transparent circular corners and a 128 px preview. The key numeral and coin remain inside Roblox's circular crop. No API key is in this folder; `provision_game_passes.py` reads the local secret file and is idempotent.

Integration is Claude-owned. Verify entitlement on the server with `UserOwnsGamePassAsync`, including rejoin and purchase completion. Exercise all six ownership paths, repeat purchases, pending upgrades, non-stacking, bought-token exclusion and UI prices before enabling sale.
