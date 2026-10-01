# Robux purchase artwork refresh — 2026-10-01

Replaced cluttered cyan/gold purchase artwork with readable matte charcoal, ivory and teal research-shop pictograms. Token earners use large `2×`, `3×`, `5×`; upgrade images identify both prerequisite and destination. Immediate token packs use `+4` and `+20`. Utility pictures depict the actual benefit: focused torch, three-bar threat detector, glowstick colors, supporter tag, re-entry doorway, and the exact re-entry/shield/three-marker expedition bundle.

**Publication is blocked by the current Studio control connection.** All 23 official replacement images are saved, approved and rendering; the four guarded Studio changes and local/Play checks are complete. Studio remains at place version **2450**. Managed Pricing is still **12/25 enabled**, with the other 13 deliberately held until the pricing-compatible place is successfully published. Native menu actions produced no publish receipt; native coordinate input reported `noWindowsAvailable`; the direct current-Edit SavePlaceAsync attempt returned a server-only rejection. No Play-server save or reconstructed-place upload was attempted. The owner has been asked to unlock/bring Studio forward; no response had arrived at this checkpoint. Exact publisher evidence is recorded under `publication/`.

## Authoritative inventory and design review

The fresh Edit audit of place **131311258779917**, universe **10559217407**, records **25 purchase IDs: 13 game passes and 12 developer products**. The inventory consists of four ordinary passes, four utility products, six Token Earner passes, nine donation amounts, and two paid skins. All 25 returned on-sale metadata at the audit's current account price. [Audit](audit/README.md), [purchase inventory](audit/robux-purchase-inventory.json).

The genuine multimodal Claude Code review completed using canonical **`claude-opus-5-5`**, effort **`max`**, in **388.782 seconds**, exit 0. It received 27 downloaded reference files and the actual purchase benefits, with no tools or MCP access. Codex independently reviewed the images and generated candidates. [Claude response](claude-review/design-review.response.md), [execution receipt](claude-review/design-review.receipt.json), [Codex notes](claude-review/codex-visual-notes.md).

The built-in `image_gen.imagegen` tool produced **15 project PNGs**: 14 utility images plus one shared donation heart. Exact prompts, revisions, files and hashes are in [utility prompts](generated-utility-prompts.json), [utility PNG verification](generated-utility-png-verification.json), [token generation](../../assets/shop/icons-v2-20261001/token-generation-manifest.json), and [donation generation](claude-review/donation-generation-receipt.json). Utility PNGs are opaque RGB, 1254×1254. [Preview gallery](preview.html) compares exact PNGs at 52/76/240 px with square and circular CSS masks; it never edits the raster assets.

## Uploaded and official images

All 15 uploaded assets belong to **ERN Roblox Studios, group 1039373905**. Studio InsertService decoded each uploaded Decal's exact raw `Texture` image ID. Creator Dashboard confirmed the exact universe already had permission to use all 15 Decals and all 15 raw images, retaining restricted access. [Upload mapping](../../assets/shop/icons-v2-20261001/published-images.json), [permissions receipt](marketplace/image-permissions-receipt.json).

| Asset key | Raw image ID | Decal ID |
| --- | ---: | ---: |
| EntityDetector | 87202894425080 | 86950067720768 |
| Supporter | 106022873152277 | 111581165935734 |
| AdvancedEquipment | 80999828522184 | 93955741424368 |
| CosmeticEquipment | 83090272487976 | 78744444495038 |
| ExpeditionPack | 134334664606741 | 126054956646209 |
| Tokens4 | 118242405264841 | 105816258132894 |
| Tokens20 | 124733504759279 | 124135806714223 |
| EmergencyReentry | 92866750717809 | 134269180449779 |
| TokenEarner2x | 118036691232665 | 98310598099056 |
| TokenEarner3x | 87690773145206 | 108075745777769 |
| TokenEarner5x | 135373819751914 | 80982991097390 |
| TokenEarnerUp2to3 | 109389693183150 | 89404136100782 |
| TokenEarnerUp3to5 | 80236147559406 | 136071686760140 |
| TokenEarnerUp2to5 | 125900723066493 | 115290090448283 |
| DonationSupport | 123958330018036 | 96765651181007 |

Creator Dashboard saved and retained **23 official purchase-image changes after reload**: all 14 utility purchases and nine donation amounts. Purchase names and descriptions were preserved; developer-product receipts also record unchanged prices, sale state and Managed Pricing state during these image-only saves. Final rendered DOM receipts and screenshots confirm all replacement thumbnails are approved and rendering, including the final +4 and +20 images. [Official image receipt](marketplace/official-icon-update-receipt.json), [approved product thumbnails](marketplace/product-images-rendered-dom.json).

**Static Wraith and False Sun keep their authentic marketplace portraits, in-game suit portraits and UV textures.** Their two public in-game portrait thumbnails returned unavailable placeholders; the actual marketplace suit portraits were available and inspected. No different outfit or reward was invented. Donation cards remain text-only in the game; the shared heart represents voluntary support in the official purchase artwork.

## Four scoped Studio source changes

The guarded write changed only these four instances, against freshly reread Source/editor baselines, with the baseline rechecked inside each editor update and Source/editor parity asserted afterward. [Write receipt](scoped-studio-write-receipt.json).

- `ReplicatedStorage.ZyntraConfig`: 14 utility `IconId` numeric literals only.
- `ServerScriptService.LobbyShopDisplay`: eight `SHOP_TEXTURES.Box` image references only; token-only Speed Potion/Route Marker artwork is preserved.
- `StarterPlayer.StarterPlayerScripts.ZyntraStore`: accept verified client-specific earner prices and choose the cheapest eligible on-sale offer at that price, keeping reached tiers owned even when metadata is unavailable.
- `ReplicatedStorage.ZyntraSkinsPage`: accept/display the verified client-specific paid-skin price; retain owned-skin equip actions when pricing fails.

The pricing compatibility change removes strict equality to configured base prices. IDs, configured base prices, grants, prerequisites, highest-tier/non-stacking rules and suit textures remain outside the write scope. Metadata must refer to the requested known ID and return a finite positive integer on-sale price; pending or invalid offers cannot prompt. This compatibility change is distinct from enabling a Creator Dashboard pricing setting. [Exact replacement spans](pricing-fix/exact-replacements.json), [pricing rationale](pricing-fix/README.md).

## Verification and recovery

Local pricing tests execute the actual production validators/render functions and unchanged tier/offer functions: **1,344 earner ownership/price rows**, **23 validator checks**, and **10 paid-skin UI rows**, all passed both on the reviewed proposals and again on the **actual verified native-after Sources**. Coverage includes regional/reordered prices, prerequisites, owned states, pending/error/off-sale responses and malformed prices/IDs. These are local function checks, not real Robux transactions or region-pinned live-account verification. [Actual-source test results](pricing-fix/actual-source-contract-test-results.json).

`verify_shop_icon_scope.py` allows exactly 14 Config and eight lobby image-ID spans, then requires every surrounding Source byte to match. Its nine negative controls reject price, grant, purchase-ID, function, unrelated-art and comment changes. Actual execution against the native-after exported Sources **passed**. The optional evaluated after-catalog comparison was not performed; the exact Source check independently proves all catalogue fields and functions outside those 14 image IDs are unchanged. [Self-test](icon-scope-verifier-self-test.json), [actual icon scope](icon-source-scope-verification.json).

The full native-before/native-after scope comparison **passed**: exactly four Sources changed, all **201 unrelated Sources** are byte-identical, both pricing Sources match the exact approved spans, and all **181 roots**, the complete native forest and service properties/attributes/tags/global settings are identical after comparison-only normalization of the four approved Source strings. No geometry, texture assignment, unrelated level, purchase grant or game setting changed. The four Sources exported under `verified-studio-mirror/` carry exact paths, classes, SHA-256 hashes and whole Source/editor parity. [Native scope verification](native-scope-verification.json), [mirror manifest](verified-studio-mirror/manifest.json).

Actual Studio Play on **ZenMeister02** confirmed all **11 visible Shop icons** loaded, displayed the new token multipliers/packs and re-entry art, and retained owned-skin actions, portraits and suit textures. Observed pack/re-entry prices were 49/149/29 Robux. Temporary ownership attributes were restored and Play stopped. Initial cached earner preload failures were superseded by successful visible `ImageLabel.IsLoaded` checks and screenshots; this is not a claim that every account or region was tested. No Robux transaction was performed. [Play receipt and screenshots](play-verification/receipt.json).

The full local native backups are `native-before/BeforeRobuxIcons-AuthoritativeStudio.rbxl` (66,120,667 bytes) and `native-after/AfterRobuxIcons-AuthoritativeStudio.rbxl` (66,121,185 bytes), with retained raw `all-service-children.rbxm` bytes and service metadata. Each captures **205 Sources**, **181 roots**, **24 services**, and **387,471 native content instances**, with zero Source/editor conflicts, skipped roots, source errors or root errors. Both local places reopened with 387,493 descendants. **29 service-property assignments are unsupported by the local packer; 129 live property reads were unavailable; Roblox omitted two engine-generated `Archivable=false` Status objects.** Raw native data and metadata remain local for recovery; source mirrors alone are not the game. [Before completeness](native-before/native-completeness-receipt.json), [after completeness](native-after/native-completeness-receipt.json), [before hashes](native-before/backup-file-hashes.json), [after hashes](native-after/backup-file-hashes.json).

Live multi-region/fully unowned-account pricing and real transactions were not performed. The remaining required work is a confirmed publication of the current authoritative Studio place followed by enrolling the remaining 13 eligible items and verifying 25/25 Managed Pricing. No active servers were restarted. This repository has no configured remote; the task commit is local and is not a GitHub push.

## Reproduce the recorded checks

Run these commands from the repository root with Python 3 and Lune 0.10.5 available. The pricing harness now defaults to the committed `verified-studio-mirror/` and writes `actual-source-contract-test-results.json`; optional arguments still override the mirror and report paths. Five exact audit Sources are retained for reproduction: Config, LobbyShopDisplay, ZyntraStore, ZyntraSkinsPage and the unchanged ZyntraSkins catalogue. Full native backups and transient proposed Sources are unnecessary for these three checks.

```sh
lune run artifacts/robux-icons-20261001/pricing-fix/verify_pricing_contracts.luau
python3 artifacts/robux-icons-20261001/pricing-fix/verify_committed_pricing_scope.py
python3 artifacts/robux-icons-20261001/verify_shop_icon_scope.py \
  --after-config artifacts/robux-icons-20261001/verified-studio-mirror/ReplicatedStorage/ZyntraConfig.ModuleScript.luau \
  --after-display artifacts/robux-icons-20261001/verified-studio-mirror/ServerScriptService/LobbyShopDisplay.ModuleScript.luau \
  --published-mapping assets/shop/icons-v2-20261001/published-images.json \
  --report artifacts/robux-icons-20261001/icon-source-scope-verification.json
```

All three commands were rerun successfully after the default-path change: the actual pricing matrix retained **1,344/23/10** passing rows/checks, the two pricing Sources match exactly **six approved replacement spans**, and the icon scope remains exactly **14+8** literals. A fresh evaluated after-catalog can additionally be supplied with `--after-catalog`; it is distinct from the exact Source proof. [Portable pricing scope result](pricing-fix/committed-pricing-scope-verification.json).
