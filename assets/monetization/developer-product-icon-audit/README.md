# Developer Product circular-icon audit — 24 September 2026

The live Roblox experience (`universe 10559217407`) has 12 Developer Products.
The official Open Cloud creator list supplied their current names, icon asset
IDs, sale status, and prices. The [Roblox product-art guidance](https://create.roblox.com/docs/production/monetization/developer-products)
says important details must stay inside the circular icon boundary. All 12 were
reviewed at 128 px in `before-all-developer-products-128-preview.png`.

Nine existing icons read clearly after circular clipping. Three products shared
the same gray placeholder cube (`88963008124478`) despite being on sale:

| Product | Product ID | New live icon asset ID | Proposed art |
|---|---:|---:|---|
| Zyntra Expedition Pack | `3713829859` | `109100897990462` | `proposed/expedition-pack-round-512.png` |
| Donate — 5,000 Robux | `3713115025` | `109172844880978` | `proposed/donation-5k-round-512.png` |
| Donate — 10,000 Robux | `3713115125` | `75225035218519` | `proposed/donation-10k-round-512.png` |

The three new images were generated with the built-in `image_gen` tool using
existing game art only as style/product-content references. The full final
prompts are in `PROMPTS.md`. Source PNGs are kept under `proposed/source-*`; the
512 px PNGs are the normalized upload files. `three-proposed-before-after-128.png`
is the 128 px review sheet that was inspected before applying the icons.

`apply_three_icons.py` sent only `imageFile` in each official Developer Product
PATCH. Creator GET before and after shows that **only** `iconImageAssetId` and
`updatedTimestamp` changed; name, description, price, sale status, managed
pricing and other configuration fields match exactly. See
`before-three-state.json`, `apply-three-receipt.json`, and
`after-three-state.json`. All three new image assets were separately read back
as `Active` and `Approved` in `uploaded-assets-readback.json`. The in-game Shop's separate Expedition Pack artwork
(`ZyntraConfig.Products.ExpeditionPack.IconId`) was not changed.

The documented Developer Product thumbnail endpoint returned `data: []` for
these 12 current Open Cloud product IDs, so the contact sheets use the official
thumbnail API for each linked **icon asset ID** and apply a local circle mask.
The live product metadata and icon asset IDs come from the creator API. CDN
thumbnail generation briefly lagged behind the icon PATCH. The final
`inventory.json` has `Completed` for all 12 icons, and
`all-developer-products-128-preview.png` is the verified post-update sheet.

To refresh the read-only inventory and sheet:

```powershell
python assets/monetization/developer-product-icon-audit/audit_icons.py
```

The API key is read from the local secret file only. The audit scripts never
write credentials or signed CDN URLs into the repository.
