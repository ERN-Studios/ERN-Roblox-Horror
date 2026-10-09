# Square lobby Shop / Upgrades — prepared only

[Nn65pxPk/#63](https://trello.com/c/Nn65pxPk) requests square buttons, two-color imagegen artwork centered above the exact labels `shops` and `upgrades`, and independent **10/10 before release**. This package changes only the two lobby opener presentations in ZyntraStore. Root has uploaded the accepted pair; no source has been installed or published for this feature. The independent critic gave the prepared artwork/layout and code **10/10** after reviewing the composition and independently repeating all 317 checks, the negative control, three compiles and three forward/inverse/hash proofs. See `independent-review.md`. The actual two-ID revision independently retains **10/10**: `image-id-independent-review.md` verifies all three exact inverses, returned IDs and full compiles. Native final 10/10 remains a separate checkpoint.

`composition-preview.png` shows the actual proposed ImageLabel/label rectangles at 112, 104, 84 and 64 pixels using the untouched imagegen masters. It is an offline UI render with Arial Bold, not Roblox Gotham or a native screenshot. Upgrades uses a 0.9 image scale to balance its heavier filled chevrons against the cart.

## Exact scope and preservation

- Desktop squares are 112×112, tablet 104×104, phone 84×84, with an 8px gap. The layout uses the actual UIDevice safe rectangle and measured Controls/Thumbstick/Jump rectangles, trying a horizontal pair, a vertical pair, then smaller squares down to 64px. It retains the safe-right clamp when an empty measured controls zone lies outside the viewport. A physically impossible safe area hides both inputs instead of placing them offscreen or over controls; all nine supported fixtures retain both buttons.
- Each button retains its original instance name, Activated handler and terminal behavior. Decorative image and label children are inactive. The original Shop router, selected-page behavior, J binding, queue/briefing/terminal suppression, and ordinary in-round hiding are unchanged.
- The separate touch in-level **136×44 DEV chip** retains its original placement, text, hover and input behavior. The new square border is disabled in that state. Direct Contextual strokes remain disabled for the square captions, preventing the previously observed duplicate text; Border strokes remain visible.
- The two lobby button backgrounds stay dark on hover. Their mint border brightens on hover; unrelated buttons retain their existing shared hover colors. No product artwork, Config, prices, purchases, Entity Shield, inventories or currencies change.

`prepare.py` applies unique narrow replacements and reverses every replacement to prove exact input preservation. `before/` is the immutable current runtime baseline; `inputs/` also freezes the two future compositions. The three whole-source outputs and their hashes are in `manifest.json`:

| Variant | Preserved input | Purpose |
| --- | --- | --- |
| `proposed/…/ZyntraStore.LocalScript.lua` | current `749afb83…8151` | Current published Store |
| `after-esp-copy.lua` | `88f25ffe…cbb6` | Retains pending ESP and upgraded stamina copy |
| `after-dev-respawn.lua` | `596ff4f4…4093` | Also retains audio's pending DEV free-respawn block |

Do not install a future composition before its other features are intentionally included in that checkpoint. If root's Store checkpoint changes, reapply the unique transform to the actual reviewed source and verify the inverse against that input. Do not copy an obsolete whole file over newer work. The preparation script fails if any frozen input has changed.

## Artwork and actual IDs

`generated/shops-v2.png` and `generated/upgrades-v2.png` are the accepted-for-review 1254px RGB candidates. `art-prompts.json` contains the exact generation/edit instructions. `art-manifest.json` records original generator paths, SHA256, dimensions and byte-exact copies. The v1 transparent images are retained as superseded history because of edge fringes. No master was manually edited, recolored, cropped or resized; `render_preview.py` only renders an independent UI composition.

The palette has two design colors, **#070B0D** and **#44DDC4**. Generated raster pixels contain small shade and antialiasing variations; this is not a claim that only two literal RGB values exist. No third decorative color is introduced.

Root uploaded only the two accepted masters through the existing Studio tool and saved the exact response in `upload-result.json` (response file saved **2026-09-10T12:34:44.4261175Z**). It returned **shops `rbxassetid://132462891522145`** and **upgrades `rbxassetid://119432640057145`**. `record_upload.py` validates that exact two-file mapping and master hashes, then records it in the art manifest. The local transport server was closed by root. This proves the returned asset IDs. Root subsequently observed `ContentProvider:PreloadAsync` return `AssetFetchStatus.Success` for both in the experience; the immediate temporary labels still reported `IsLoaded=false`. Actual button loading and native pixels remain pending.

`prepare.py --shops-id 132462891522145 --upgrades-id 119432640057145` produces the final two Image strings while preserving source guards. The earlier empty-ID source must not be released. `installable` only records that actual IDs are supplied; it is not native acceptance or permission to skip the final 10/10 checkpoint. No product/pass ID or image-tool handle stands in for an image asset ID.

## Bounded verification

```
python artifacts/trello-20260909/square-shop-buttons-prepared/prepare.py --shops-id 132462891522145 --upgrades-id 119432640057145
python artifacts/trello-20260909/square-shop-buttons-prepared/test_proposal.py
python artifacts/trello-20260909/square-shop-buttons-prepared/render_preview.py
```

**319 actual-source checks / nine layout fixtures / three whole-file compiles pass** after inserting the returned image IDs (317 original checks plus two actual ImageLabel-to-upload-response checks). The test extracts the real button/content builders and `updateVisibility`, checks square dimensions and safe geometry, exact captions, noninteractive decoration, hover, modal recovery and the unchanged DEV exception. Restoring the original rectangle visibility logic fails the square-dimension assertion. Frozen runtime SHA is unchanged. `validation.json` and `layout-geometry.json` retain the result. `image-id-proof.json` proves the three sources changed only their two Image strings since the prior review. See `UPLOAD-CHECKPOINT.md` for full hashes and the precise fetch-versus-render distinction. These mocks establish authored geometry and state behavior, not native font fitting, texture loading or physical-device input.

## Root's final native checkpoint

1. After uploading the accepted pair and rebasing onto the correct Store checkpoint, verify both actual `Image` IDs and `IsLoaded`. Inspect the two complete squares in the normal lobby at desktop, tablet, phone portrait/landscape, and the narrow constrained case. Labels must be exactly lowercase, centered, readable and `TextFits`; there must be no ghost caption, colored tile seam, clipping or overlap with controls.
2. Click/tap the icon and caption regions of each parent. Shop must select Shop; Upgrades retains its existing terminal reopen behavior. Close, hover/leave and reopen. Verify queue/briefing/terminal suppression and recovery; in-round ordinary players see neither lobby square and touch DEV retains its original 136×44 exception.
3. Have the independent critic inspect the final native composition and behavior. The card's **10/10** is required before root's separate mouse publication. An offline art/code score does not waive it. Record actual installed source/image IDs, native evidence and the resulting version; no release has happened here.
