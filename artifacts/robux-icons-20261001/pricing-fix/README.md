# Managed Pricing compatibility proposals

These are **review-only source proposals**, built from the fresh live Studio audit. The parent is the sole Studio writer and must reread Source/editor parity and apply the exact replacements against that fresh baseline. No purchase IDs, configured base prices, ownership grants, data stores, outfit textures, or tier prerequisites change.

Two current UI paths were incompatible with player-specific prices. Token Earner required `PriceInRobux == Config.Price`, selected offers using base prices, and displayed base prices. The paid skin page required `PriceInRobux == RobuxPrice` and displayed the configured price. A valid regional or test price could therefore make a real on-sale purchase appear unavailable.

The Token Earner proposal keeps a client-only table of verified on-sale pass metadata. Every price is a finite positive integer and every returned `TargetId` must match the requested known pass ID. It passes a cloned catalogue containing actual client prices into the existing `TokenEarner.Offer` function, preserving the existing prerequisite and highest-tier rules while comparing available offers at their actual prices. Reached tiers remain `OWNED` independently of network or sale state. Pending/error states have no purchase ID and cannot prompt. An unavailable offer is not falsely treated as an owned tier.

The skin proposal returns both sale validation and actual price from the same metadata request, stores that price locally, and displays it in the card and existing 3D preview status. Already-owned suits continue to equip without requiring a price response. Pending/unavailable states do not invent an actual price.

`exact-replacements.json` supplies the exact old/new spans and before/after hashes. `proposed-after/` contains the full resulting source for review and local compilation, and the two `.diff` files show the scoped change. The base source hashes are:

- `StarterPlayer.StarterPlayerScripts.ZyntraStore`: `0a9f2669a16d18124acd22a4606ea5a0f8a0e086e63e0960fb4878b3e1ff8356`.
- `ReplicatedStorage.ZyntraSkinsPage`: `2dd92ce9389f57917a26ff6b608f6314d492c0ad99c5b7d312c5c4d5620d3bc1`.

## All 25 price paths

The full native-before capture records **13 game passes and 12 developer products**. The eight ordinary Shop items, nine donation tiers, lobby item detail cards, Shop enlarged detail pane, and Emergency Re-entry death interface already consume client `GetProductInfo(...).PriceInRobux`. Ordinary cards use the configured base price while their request is pending, then replace it with the current response; owned ordinary pass buttons retain `OWNED`. The re-entry price is passed to RoundUI through `ZyntraReentryPrice`. These existing paths are preserved. The six Token Earner purchase variants share three destination-tier cards and are covered by the proposed earner table. The two paid skins are covered by the skin proposal. `price-source-usage-before.json` records the exact source paths and lines for the current display references.

Roblox documents that Managed Pricing can adjust an item's price for a user's economic location and that a custom UI should read the user's current price through a client MarketplaceService request. The runtime price need not equal the configured base value. [Regional pricing documentation](https://create.roblox.com/docs/production/monetization/regional-pricing), [MarketplaceService API](https://create.roblox.com/docs/reference/engine/classes/MarketplaceService).

The Edit `GetProductInfo` snapshot in `audit/marketplace-managed-pricing-before.json` includes all returned fields, including `UserBasePriceInRobux` and `PriceDiscountDetails` where present. It **does not expose a reliable Creator Dashboard Managed Pricing toggle**. Dashboard settings require their separate UI receipts; successful metadata reads are not proof that Managed Pricing has been enabled.

## Local validation and remaining live checks

`verify_pricing_contracts.luau` compiles both complete proposed scripts and executes their actual pricing validators and render functions, plus the unchanged production tier/offer and skin catalogues. It does not reimplement the changed UI functions as its test subject.

- **1,344 earner UI rows**: all 64 ownership combinations, three target tiers, and seven base/regional/pinned/reordered/off-sale/unavailable/pending scenarios. Every purchasable offer is the cheapest known on-sale valid offer at the actual price, honors prerequisites, and uses an unowned configured purchase ID. Owned states and unavailable states remain distinct.
- **23 validator checks**: normal regional price, off sale, wrong/missing returned ID, zero, negative, fractional, infinite, NaN, string, missing price, and a skin network failure.
- **10 paid skin UI rows**: base and regional prices, pending/error metadata, and owned suits with no available price. The existing 3D preview status mirrors the same price/action.
- Base catalogue unchanged, upgrades require prerequisites, and tiers do not stack.

All checks passed in `pricing-contract-test-results.json`. These are meaningful local function tests, **not** a claim that gameplay, a real purchase, or a region-pinned live account check has passed.

The actual installed Sources have since been exported to `../verified-studio-mirror/` and tested again successfully in `actual-source-contract-test-results.json`. The harness defaults to that committed mirror rather than the transient `proposed-after/` directory. Run `lune run artifacts/robux-icons-20261001/pricing-fix/verify_pricing_contracts.luau` from the repository root; optional argument 1 overrides the mirror, and argument 2 overrides the report. The unchanged `ZyntraSkins` audit catalogue is also retained. `verify_committed_pricing_scope.py` verifies the two actual Sources against the six exact approved spans using the committed before/after Sources, without requiring a full native backup.

After the guarded Studio write, check the actual Shop card and detail pane price on an account without each tested entitlement. Exercise the real Dynamic Price Check or location-pinned account for 2x/3x/5x and both paid skins; an owned 2x account should see the cheapest eligible upgrade with its actual returned price. Check an owned 5x account stays owned even if prices fail. Verify the nine donation tiers and ordinary products still match their Roblox prompt price, and disable any temporary price check afterward. No real Robux purchase is required for display/offer verification.
