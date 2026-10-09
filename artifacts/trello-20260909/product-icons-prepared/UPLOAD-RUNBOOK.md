# Icon upload and assignment runbook

Prepared read-only on 2026-09-10. No image resizing, UI/browser operation, upload, assignment, runtime edit or pricing change was performed. All twelve masters remain the independently reviewed originals (both artwork groups 9/10).

## Resolution decision

**The original 1254×1254 PNGs are eligible by size/format for ordinary image-asset upload, but exceed the documented maximum for pass and developer-product icons.** The current official [pass guide](https://create.roblox.com/docs/production/monetization/passes) and [developer-product guide](https://create.roblox.com/docs/production/monetization/developer-products) each specify no more than 512×512 and JPG/PNG/BMP with the subject inside the circle. Neither guide establishes that their current picker will automatically resize a 1254px input. Do not claim direct master-to-platform upload is verified.

The [Open Cloud asset guide](https://create.roblox.com/docs/cloud/guides/usage-assets) permits PNG Image/Decal inputs below 8000×8000 and up to 20 MB; every master is 1254px and at most 2,534,645 bytes. That is a separate generic asset limit. The installed Studio `upload_image` tool reports no pixel limit in its schema, so its specific acceptance still needs an actual upload/readback. Its success would not establish compliance with the platform-icon picker.

For a reliable full-platform refresh, use separate delivery copies at or below 512px while preserving masters. None have been created here. If root observes a supported platform picker that accepts and resamples the original itself, that observed result can replace a local export; do not assume such a control exists or bypass a rejection. This runbook uses no PIL editing or other transformation.

## Identity and exact assignments

The local `assets/live-asset-manifest.json` identifies **BACKROOMS: STAY QUIET [CO-OP HORROR]**, universe **10559217407**, place **131311258779917**, group **ERN Roblox Studios / 1039373905**. This is a historical identity snapshot; match the live experience and existing purchase IDs before changing an icon.

Every filename below is under `G:\Roblox\MongoTV\artifacts\trello-20260909\product-icons-prepared\generated-masters\`. Full paths and hashes are in `upload-assignment-plan.pending.json`. The final column is a field in `ReplicatedStorage/ZyntraConfig.ModuleScript.lua`, not a platform purchase ID.

| Existing platform entry | Type / purchase ID | Reviewed master | Custom Shop destination |
| --- | --- | --- | --- |
| Zyntra Supporter | Pass 1941938256 | `supporter-v2.png` | `Passes.Supporter.IconId` |
| Advanced Equipment | Pass 1945402536 | `advanced-equipment-v2.png` | `Passes.AdvancedEquipment.IconId` |
| Glowstick Customizer | Pass 1946086261 | `glowstick-customizer-v2.png` | `Passes.CosmeticEquipment.IconId` |
| 4 Research Tokens | Product 3707755089 | `research-tokens-4-v2.png` | `Products.Tokens4.IconId` |
| 20 Research Tokens | Product 3707755233 | `research-tokens-20-v2.png` | `Products.Tokens20.IconId` |
| Emergency Re-entry | Product 3707755318 | `emergency-reentry-v2.png` | `Products.EmergencyReentry.IconId` |
| ZYNTRA Donate — Signal | Product 3710116814 | `donation-signal-v2.png` | None |
| ZYNTRA Donate — Supply | Product 3710116945 | `donation-supply-v2.png` | None |
| ZYNTRA Donate — Field | Product 3710117017 | `donation-field-v2.png` | None |
| ZYNTRA Donate — Research | Product 3710117070 | `donation-research-v2.png` | None |
| ZYNTRA Donate — Command | Product 3710117099 | `donation-command-v2.png` | None |
| ZYNTRA Donate — Director | Product 3710117136 | `donation-director-v2.png` | None |

The current six custom Shop values are respectively **0, 82752249741977, 96817218792472, 122080898819162, 85350713730800, 105488216694656**. Preserve the Supporter `IconText="Z//S"` fallback. The actual Shop builds a 76×76 `ProductIcon` with `ScaleType.Crop` and circular corner radius 38. It reads `item.IconId` directly; later Marketplace metadata does not update it. The six Donate cards have no image consumer, so do not add unused donation IconId fields or new card layouts.

## Shortest reliable sequence

1. Prepare compliant platform delivery files from the approved masters, preserving composition and the originals. Inspect the six Shop images in a 76px circle and all twelve at 64px before committing assignments. Review scores apply to the masters, not automatically to the delivery encoding.
2. In the correctly owned existing experience, navigate through **Creator Dashboard → Creations → the game → Monetization → Passes / Developer Products**. Select each existing entry from the table and use its current image-edit control. The guides document this catalogue location; exact edit controls have not been inspected in this preparation. Replace only its icon. Preserve purchase IDs, names, descriptions, sale state, categories and all pricing fields. Creating replacement products is unnecessary.
3. Save and verify each new platform preview before moving to the next entry. Record the local delivery-file hash, existing purchase ID, old icon identity if available, new icon identity and the resulting preview. Wait for actual image availability/moderation before declaring it displayed; do not repeatedly upload duplicates merely because a thumbnail is delayed.
4. Run the prepared **read-only** `read-platform-icons.luau` once before changes and once after saved changes propagate, in the matching Studio experience. It queries exactly these twelve entries with the correct `Enum.InfoType` and returns only identity/icon fields, never pricing. It neither buys anything nor changes the world. Save both JSON results separately.
5. **First try reusing the six verified platform icon image IDs for the custom Shop.** Roblox's official [MarketplaceService reference source](https://github.com/Roblox/creator-docs/blob/main/content/en-us/reference/engine/classes/MarketplaceService.yaml) documents `IconImageAssetId` as the product icon image ID, or zero if absent, and cautions that returned fields vary by queried product type. Reuse only an actually returned positive integer that loads and visually matches the intended new artwork. This can avoid six extra generic uploads. A query succeeding, a stale icon ID, or a purchase ID alone is not sufficient.
6. If a particular platform entry does not expose a usable image ID after verification, upload only the necessary Shop image(s) through the generic-image fallback below. Capture the returned IDs in the plan. Do not generically upload all six donation masters merely to fill nonexistent Shop fields.
7. Apply the six actual image asset IDs to the current `ZyntraConfig` fields above, using root's normal source-sync/CAS workflow. Rebase these tiny assignments onto the current config if Protection has since changed it; do not overwrite it with the earlier catalogue snapshot or an obsolete proposal. Keep any Supporter comment consistent with its approved replacement while retaining the fallback. Diff review should show only these image assignments and any directly necessary stale-comment correction, with no purchase-ID, grant or price change.
8. In normal lobby UI, open SHOP and inspect all six actual `ProductIcon` images, including Supporter replacing the monogram, readable token-pack differences and full circular framing. Verify the two catalogue pages show all twelve intended platform icons. Close SHOP normally, perform the scoped compile/sync audit, obtain independent review of the completed change, then **mouse-publish via File → Publish to Roblox** and record the confirmed version. No Alt+P shortcut.

## Generic Shop-image fallback

The currently installed `mcp__Roblox_Studio__upload_image` accepts this contract:

```text
{ imagePaths: ["http://127.0.0.1:<actual-port>/<approved-file>.png", ...],
  studio_id: "<current matching Studio id>" }
→ URL-to-"rbxassetid://<numeric-image-id>" mapping
```

Use the current explicit Studio id obtained from `list_roblox_studios`, matched to the existing experience. The tool has no creator/group argument; verify the resulting asset's ownership and experience accessibility rather than inferring them from the call. An authorized Asset Manager import into the open game's owning inventory is the supported UI alternative. [Asset Manager documentation](https://create.roblox.com/docs/projects/assets/manager) describes PNG import, owning user/group inventories and asset preview.

`tools/publish_lobby_concrete_textures.py` and `tools/publish_elevator_textures.py` already demonstrate the required small transport pattern: `ThreadingHTTPServer(("127.0.0.1", 0), ...)`, explicit file URLs, call, validate mapping, persist IDs, then shut down in `finally`. Reuse that pattern with only the approved icon directory and file list. **Do not execute those texture-specific publishers**: they hardcode other assets and output manifests. Do not expose the repository root or any credential directory. No HTTP server or upload was started for this runbook.

Each successful returned value must match `^rbxassetid://[1-9][0-9]*$`. Store the numeric image ID, source hash and ownership/readback beside the matching key; don't use a pass/product purchase ID as an ImageLabel image ID. Verify the actual image pixels and loading in the target experience before assigning it.

`store_image` returns a temporary `IMAGEID_...` tool handle and is not a Roblox publication or platform assignment. A generic upload never automatically replaces a product/pass icon. The official [game-pass](https://create.roblox.com/docs/cloud/reference/features/game-passes) and [developer-product](https://create.roblox.com/docs/cloud/reference/features/developer-products) API indexes expose experimental localized-icon update endpoints, but there is no matching installed assignment tool or existing authenticated repo wrapper. API credentials/scopes were not inspected. Dashboard editing is the practical supported route for this runbook; do not repurpose undocumented cookie requests or localization endpoints.

## Prepared files and honest boundaries

- `upload-assignment-plan.pending.json`: twelve IDs/absolute master paths/hashes, six exact config destinations, empty future upload/readback fields; not an upload manifest.
- `read-platform-icons.luau`: compiled successfully (2 KB), not executed. Missing/query-failed icon fields remain explicit and never become invented IDs.
- `prepare_upload_plan.py`: checks twelve unique purchase IDs against current source, twelve master hashes and six destinations, then writes the inert plan. No image editing/network/Studio calls.
- The source baseline at preparation is Config `e7b9d2902d18674386c04c4a32d55cc6a4c829c1baa66c1636120f840a852779`; Store `a8a53afaaccb7718e551b46ffb11f4e85f72e121f4589eae1c8446dbd4a1decc`. Future legitimate Protection edits require a new current baseline, not a blind reset.

Direct 1254px platform-picker acceptance, delivery exports, platform ownership/assignments, moderation, image IDs and native small-size rendering remain unobserved. This task completed the runbook only; it made no pricing recommendation and did not execute any Testing card.
