# Images ready for Claude — Trello #103 / #104

Availability verified at 10:35 UTC: both official Roblox thumbnails now report **Completed**, and native ContentProvider preload of an unparented ImageLabel dependency returned **Success** for each asset. The earlier raw-ID-string preload remained Failure; the successful result comes specifically from preloading the actual image dependency. No scene objects or game source were changed. Unparented ImageLabel.IsLoaded stayed false, so this is asset-load evidence, not a screenshot/rendering claim. Claude must verify both visible buttons during implementation QA before publishing. See asset-validation.json. No reupload or further availability polling is needed.

Codex generated, visually inspected and uploaded two transparent PNGs through Roblox Studio's official upload_image tool. No game source or scene objects were modified. Claude owns all integration and runtime QA.

| Usage | Roblox asset | Workspace file |
|---|---|---|
| Lucky Wheel side-button symbol | rbxassetid://111918608092047 | assets/shop/hud-lucky-wheel-v1.png |
| Daily Rewards side-button symbol | rbxassetid://85423575361057 | assets/shop/hud-daily-rewards-v1.png |

Both are 1254 × 1254 RGBA, with genuine alpha range 0–255. Colors: charcoal, teal and amber matching the current shop. Preserve aspect ratio (Fit), keep background transparent, place inside the existing square HUD button treatment. The wheel symbol has five sectors and a fixed pointer. It is a BUTTON ICON, not a ready-to-rotate prize disc: rotating it would also rotate the pointer. Claude must construct the actual wheel and stationary pointer separately, and map the server-awarded result correctly.

Rewards symbol is an industrial gift crate with a clock badge. Neither image has baked words, reward counts, odds or prices. Claude supplies live text, accessible labels and proper desktop/mobile hit areas.

For #105, existing product artwork in assets/shop and the SHOP_TEXTURES mapping can be reused on the new floating hologram displays. No extra artwork is currently required. If the design needs a specific new texture, record size, alpha, exact role and slot in asset-requests.md; Codex may create/import that asset while Claude retains all code ownership.

Generation prompts and source paths: image-generation.json. Pixel metadata: image-validation.json. Upload receipt: uploaded-images.json. These files and icons are ready for Claude's focused commit with the completed work.
