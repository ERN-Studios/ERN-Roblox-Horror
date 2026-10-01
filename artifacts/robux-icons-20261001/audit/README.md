# Fresh Robux purchase artwork audit

Studio is authoritative. This audit read the open **131311258779917 / 10559217407** experience through Studio MCP `08b776ed-0330-44f6-8378-c6eea82b3f38` in Edit mode on 2026-10-01. No game source, hierarchy, purchase setting, price, or ownership rule was changed by the audit.

## Inventory and sources

`robux-purchase-inventory.json` records all **25 Robux purchase IDs**: four ordinary passes, four utility developer products, six Token Earner passes, nine voluntary support tiers, and two premium cosmetic suits. Fresh MarketplaceService metadata succeeded for all 25; every purchase was on sale and its price matched the configured value. Comments describing Token Earner as off sale are outdated and were not used as an authority.

`live-source-manifest.json` records the seven relevant exact Studio Sources, SHA-256 hashes, classes, paths, and successful whole Source/editor parity. Long Sources were read in chunks, verifying their total byte length and whole editor parity each time. Any writer must independently reread and guard its exact changes against the fresh live Source; these audit files must not bulk overwrite Studio.

`live-catalog.json` contains the current utility and donation configuration. `recent-native-locator/` is explicitly historical, used only to locate script names while Studio was closed; it is not a write baseline.

## What the player actually sees

- The Shop page has **11 Robux cards**: eight ordinary items and three Token Earner target tiers. The six earner passes represent direct purchases plus prerequisite-dependent upgrades; the unchanged `TokenEarner.Offer` logic selects the appropriate purchase ID while card artwork remains the destination tier's direct icon.
- The card list, enlarged Shop detail pane, and lobby item detail card use `ZyntraConfig` item `IconId`. MarketplaceService calls read prices and sale state; they do not replace card images with Marketplace thumbnails.
- Lobby floating boxes have a separate `LobbyShopDisplay.SHOP_TEXTURES.Box` table. Six entries are independent of their corresponding card `IconId`: Supporter `75534988741783`, AdvancedEquipment `133698774797678`, CosmeticEquipment `95744112613263`, Tokens4 `127956354478910`, Tokens20 `114348157561307`, EmergencyReentry `93091494402773`. ExpeditionPack and EntityDetector share their current configuration images. Builder resolution is explicit box image, item icon, shared fallback. The fresh Edit scan found no existing `ZyntraShopDisplay` or current decals using the six independent IDs; the builder creates them during Play.
- All nine donation cards are text-only in the game, but Roblox's purchase prompt has official artwork for each tier.
- Paid skin cards use `PreviewImageId`, a standing suit portrait. Skin `ImageId` is a separate UV texture applied to the actual suit and must **not** be changed by an icon refresh. Marketplace pass icons are separate bust portraits.

## Visual findings

All six Token Earner images and all 17 remaining Marketplace purchase icons were visually inspected. The two in-game paid skin portrait references could not be inspected from the public thumbnail endpoint: despite a `Completed` API state, they returned the same unavailable-image placeholder. This is documented rather than treated as actual art.

The multipliers are the clearest problem. Large beveled gold numerals sit on elaborate cyan/gold medallions amid glowing crates, electrical arcs, sparks, and a metal platform. At the game's 52–76 pixel card sizes, the composition becomes noisy and suggests a sci-fi loot game rather than a worn backrooms research shop. Direct 3x and the 2x-to-3x upgrade use the same composition. Direct 5x, 2x-to-5x, and 3x-to-5x also use the same composition. Upgrade artwork does not identify the prerequisite tier.

Recommended multiplier refresh: one plain research token, a large exact destination multiplier for the three in-game cards, and explicit source-to-destination labels for the three official upgrade purchase icons. Avoid a pile of coins implying a purchased balance increase: these passes multiply earned rewards only, not bought packs, existing balances, refunds, or grants. Do not change that distinction or the purchase logic.

The ordinary utility pictures share the same glossy cyan/gold rendering. Supporter is a teal star badge and is semantically reasonable. Advanced Equipment centers a futuristic gas mask instead of its main benefit, the focused flashlight and added stamina. Glowstick Customizer shows three colored glowsticks, which is accurate but excessively ornate. Token packs show four separate square cyan chips versus five stacks of four chips, a helpful quantity distinction worth preserving with clearer restrained artwork. Emergency Re-entry depicts a sci-fi portal; a worn backrooms doorway and return arrow would fit the setting. The Expedition Pack includes shield and return cues, but its three cylindrical objects look like glowsticks rather than the three route markers actually granted. The Entity Detector purchase icon faithfully shows a rugged handheld instrument with low/medium/high colored bars; replacements must avoid promising exact enemy positions or guaranteed safety.

All nine support icons form a recognizable teal-heart/gold-medallion family: signal lines, supporting hands, a hexagonal badge, orbiting dots, laurels, a golden heart, a faceted heart, a crowned faceted heart, and a ticket with a heart. They honestly communicate voluntary support and are less cluttered than multipliers, but their glossy jewelry aesthetic does not match the game's worn environment. A restrained heart/stamped supporter family would unify a complete purchase artwork refresh without implying a gameplay reward.

Static Wraith's official purchase portrait shows the existing purple/gray hazmat suit; False Sun shows the existing cream/gold suit. Those portraits are honest product representations. Keep them or replace them with direct renders of the same owned cosmetic. Generating a different outfit would misrepresent what a buyer receives.

## Image reference limitations

`current-icon-download-receipt.json` identifies **35 distinct current asset references** across in-game icons, lobby artwork, skin portraits, and official purchase icons. Public Roblox 420x420 PNG thumbnails were downloaded unchanged for 27 `Completed` assets; two of those are unavailable skin placeholders. Eight references remained `Pending`, including six old lobby box decals and the in-game Entity Detector/Expedition Pack decals. A public full-resolution asset delivery probe returned HTTP 401. No credentials were read and no permissions changed.

Thumbnail files are review references, not full-resolution production artwork or asset ownership evidence. Each download records its actual returned URL, state, dimensions, byte length, and SHA-256. New uploaded images must be verified in the real in-game UI before publication.
