# Product/pass icon inventory — read-only preparation

Card [RynrscFW](https://trello.com/c/RynrscFW), “Redo the logos for the developer items and passes.”, has no description or checklist. Its independently read state is To Do / incomplete; `trello-readback.json` preserves the result. No card was changed.

The current config contains **12 configured offers: 3 passes, 3 utility developer products and 6 donation developer products**. All 12 purchase IDs are distinct. See [catalogue-table.md](catalogue-table.md) for the complete names/IDs/icon IDs, and [inventory.json](inventory.json) for source hashes, line references and every local image's dimensions/hash. Prices were deliberately omitted. This is the configured catalogue, not a claim that the live Creator Dashboard contains no additional or retired items.

## What actually uses images

`StarterPlayer/StarterPlayerScripts/ZyntraStore.LocalScript.lua:1187–1290` creates the six Shop cards. Their `ProductIcon` reads only `Config.Passes/Products[key].IconId`, uses a 76×76 ImageLabel, `ScaleType.Crop` and a 38-pixel corner radius. The later GetProductInfo result does not set the image. Changing a platform product/pass thumbnail alone therefore does not update this custom shop.

Five Shop cards currently have positive image asset IDs. **Supporter intentionally has IconId=0 and IconText="Z//S"**: the old hazmat-themed art was retired because the pass grants a Supporter tag, not a hazmat appearance. The existing client already supports the replacement by setting a valid IconId later; its monogram fallback should remain for absent approved artwork.

`makeDonationCard` at lines 1393–1454 has a heading and action, **no ImageLabel and no IconId consumer**. Adding IconId fields to the six donations would currently render nothing. A full platform-logo refresh can include their six dashboard icons without adding images to this compact in-game page. Adding donation-card imagery would be a separate layout change and is unnecessary to replace the platform logos.

The four achievement badges are not passes or developer products. The prepared Entity Protection feature has no additional Roblox purchase ID; its token-based item does not increase this 12-offer catalogue. Those are not silently added to this art scope.

## Existing local artwork and redesign needs

`assets/monetization/icons-512/` contains six real 512×512 PNG files, paired with six larger originals in `assets/monetization/source/`. The preview sheet at `assets/monetization/zyntra-icon-preview-sheet.png` was visually inspected. File-name mapping is recorded by the existing `assets/monetization/README.md`; it is not proof that the current uploaded asset pixels match the local files. There is no local upload-ID manifest for this pack, and the live platform icon IDs were not queried.

The historical pack uses dark industrial circular frames, teal accents, gold tokens and red re-entry imagery. Its six subjects are a Supporter hazmat character, equipment helmet/color ring, three glowsticks, four tokens, a larger token cache and an airlock/return arrow. Keep these originals intact as references. **Do not restore the retired Supporter hazmat image.** The old README still describes it as final; the newer config retirement is authoritative for current runtime use.

No donation icon masters/exports were found in the monetization assets or relevant artifact image inventory. The complete requested catalogue therefore implies **six redesigned existing images plus six donation-tier images**, if “developer items” includes all nine configured developer products. A smaller six-image change would cover the custom Shop's visible icon slots but would leave the six donation products' platform presentation outside that delivery. Root can state that scope explicitly rather than claiming all 12 were refreshed.

For later art direction, keep each purchase recognisable at the actual small circular crop: Supporter should communicate support/status; Advanced Equipment its actual equipment customisation/upgrades; Glowstick Customizer glowstick colors; the two token packs should differ clearly; Emergency Re-entry should communicate return/re-entry. Donation variants can share one support motif with tier differentiation, without implying gameplay grants. This inventory creates no prompts or new artwork and makes no pricing recommendation.

## Existing upload workflow and its limits

The callable Studio MCP `upload_image` accepts `imagePaths` HTTP URLs plus the selected `studio_id`, and returns URL → `rbxassetid://...` mappings. The existing `tools/publish_lobby_concrete_textures.py` (and elevator equivalent) demonstrates a loopback-only HTTP server, selected Studio connection, returned-ID validation and a saved upload manifest. These are texture-specific publishing scripts, so **do not run them to publish the icon pack**. A later icon upload can reuse the small pattern with an explicit icon file list and its own manifest. No server was launched and no upload tool was called here.

Studio MCP `store_image` only loads a local image into an `IMAGEID_...` handle for other tools; it is not a product-icon publication step. Likewise, uploading a generic image asset does not assign it as a pass or developer product's platform icon.

For the platform icons, use the **existing** entries under Creator Dashboard → the same experience → Monetization → Passes or Developer Products. Preserve their purchase IDs; replacing artwork does not require creating replacement products. Roblox's current official guides specify images up to 512×512, JPG/PNG/BMP, with important content inside the circular crop: [passes](https://create.roblox.com/docs/production/monetization/passes), [developer products](https://create.roblox.com/docs/production/monetization/developer-products). These guides cover image requirements and catalogue location, not a verified click-by-click edit session in the current account.

The official API references also list authenticated localized-icon update endpoints, marked Experimental, for [game passes](https://create.roblox.com/docs/cloud/reference/features/game-passes) and [developer products](https://create.roblox.com/docs/cloud/reference/features/developer-products). No matching authenticated upload wrapper was found in this repo, no authorization was probed, and no API mutation was attempted. The existing dashboard workflow is the practical starting point; a generic Asset Server upload must not be mistaken for this separate platform assignment.

Once future approved images exist, record both the platform icon assignment and the image asset consumed by the six custom Shop cards, then inspect the circular crop in the actual Shop. Keep runtime changes to the six relevant IconId values unless a separate presentation change is authorized. This note does not initiate image generation, uploads, purchases, runtime/Studio changes, pricing work or any Testing card.
