# Square Shop / Upgrades — source and asset constraints

Read-only preparation for [Nn65pxPk/#63](https://trello.com/c/Nn65pxPk), from `trello-recheck-native-active-20260910.json`, card revision **2026-09-10T11:07:14.495Z**. That complete saved card has no comments/checklists and neither collection reports more items.

The exact requested result is: **both buttons square; polished icons generated with imagegen; only two colors matching the current buttons; each logo centered with its label directly below; labels exactly `shops` and `upgrades`; independent critic rating 10/10 before release.** This replaces the current rectangular lobby presentation. The earlier PkEUQQ74 approval is historical, not automatic approval of this new design. No artwork, design code, upload or UI operation was performed for this specification.

## Current source measurements

Current `StarterPlayer/StarterPlayerScripts/ZyntraStore.LocalScript.lua` SHA256: **`749afb8362e159940ab1f719fe74f8f1bc9ce84a495d41bd08f6306b79768151`**, the published Shield + section-logo source. These are authored values, not new native measurements.

| Property | Upgrades opener | Shop opener |
| --- | --- | --- |
| Actual instance name | `ZyntraOpenButton` | `ZyntraShopButton` |
| Desktop | 280×64 | 280×48 |
| Tablet touch | up to 280×64 | same width ×48 |
| Phone touch | up to 220×56 | same width ×48 |
| Current placement | Desktop right 18px, top 20px; touch safe top+8px, before measured controls | same X, 8px below Upgrades |
| Current text | `UPGRADES & GEAR` | `SHOP` |
| Current icon | 32×32 double ascending chevrons | 32×32 cart |
| Current caption | GothamBold, 18px, left after icon, wrapped | same |

Both initial backgrounds are **RGB(7,11,13), `#070B0D`**. Both logos and captions use **RGB(68,221,196), `#44DDC4`**. These are the two base colors for the new artwork. Transparent pixels may expose the same authored background; avoid introducing another decorative hue, gradient or shadow palette. Keep the requested labels as native text beneath the artwork rather than asking imagegen to rasterize the words.

Important existing style detail: the shared `button()` helper changes background on hover to RGB(32,50,53), `#203235`, and on leave to `COLORS.card2` RGB(25,36,40), `#192428`; it does not restore these two openers' initial dark color. A strict two-color redesign must account for this specifically on the two lobby buttons. Do not globally restyle every Shop action. Generic line color is RGB(65,92,98); direct Contextual strokes are currently disabled while replacement captions are visible to prevent the previously reproduced ghost text. Do not reintroduce those ghosts around the new image/caption.

## Preservation and layout acceptance

- Use the same two buttons, activation paths and modal/input exclusion. Shop calls `openKioskShop()` and selects Shop. The existing Upgrades opener calls `toggleMain()`; it starts with Upgrades but retains the currently selected terminal page on later reopen. This task does not authorize silently changing that behavior.
- Preserve `UIDevice.SetInteractive` hiding/deactivation behind the terminal, queue modal and dispatch briefing, normal in-round hiding, close/death/escape behavior, existing J binding and developer authorization. Decorative image/caption children must not consume the original click/tap.
- The touch in-level developer exception is a separate **136×44** `ZYNTRA // DEV` chip with 11px type, existing collision-free placement and no Shop button. Keep that exception; the requested square presentation applies to the two lobby openers.
- Touch width is currently clamped against `min(layout.Safe.Right, layout.Zones.Controls.Left)`, with at least 44px hit size. This safe-right correction handles measured controls temporarily lying outside the safe area. Retain its protection and respect the actual top inset/control rectangles when choosing new square dimensions and arrangement.
- Current icon fallback hides icons below 188px width because the old horizontal caption needed that space. That threshold is tied to the old layout; it cannot be copied blindly into a new square design. The new native result must still show the requested centered logo and exact lowercase label where the buttons are available, with two actual square hit rectangles, readable labels and no overlap/clipping. New sizes are the design author's decision, not specified by this source audit.
- Preserve all product IDs, six v1856 product IconIds, prices, purchase handlers, Entity Shield and pending ESP/upgrade-copy changes. Use narrow transforms against a fresh full-file checkpoint; do not install an obsolete Store copy. The two section images are not product icons and require no monetization catalogue edits.

Inspect the prepared design at its intended desktop and compact render sizes before upload. Final independent 10/10 must cover the actual native rasterization, complete square shapes, centered logos, lowercase labels, hover/restoration, clicks, modal guards and narrow layout; an offline preview alone is not final release evidence. Record synthetic viewport/touch fixtures accurately instead of claiming physical-phone testing.

## Existing image upload and assignment route

The completed product-icon workflow is documented in `product-icons-prepared/PLATFORM-DELIVERY.md`: twelve original 1254×1254 masters were accepted by the actual Creator Dashboard, returned verified image asset IDs and became visible catalogue art. Six IDs were then assigned to numeric Config fields and verified in native 76px circular ProductIcons before v1856. That monetization-icon route is historical and unnecessary for these two new UI-only section images.

The installed `mcp__Roblox_Studio__upload_image` tool accepts **`{imagePaths:[http URLs], studio_id:<current explicit Studio ID>}`** and returns a URL-to-`rbxassetid://…` mapping. `list_roblox_studios` supplies current IDs. The existing local transport pattern is in `tools/publish_lobby_concrete_textures.py` and `tools/publish_elevator_textures.py`: serve only the approved image directory on `127.0.0.1` with an ephemeral port, send explicit file URLs, retain the returned mapping, and shut the server down in `finally`. Reuse that transport pattern; do not execute those texture-specific scripts, which publish unrelated files. No local server was started here.

For the accepted pair, preserve generated masters and source hashes, upload only the two approved images, persist each returned positive image ID immediately, and confirm that the assets are accessible to the actual experience (place **131311258779917**, universe **10559217407**, ERN group **1039373905**). The tool has no group-owner argument, so ownership/access cannot be inferred from its schema. Avoid duplicate uploads after an uncertain result. Asset Manager import into the correct owning inventory is the existing UI alternative if required.

Use the returned image asset strings on the new section ImageLabels. A temporary `IMAGEID_…` image-tool handle and a pass/product purchase ID are not usable substitutes. Keep the existing product catalogue and Config IconIds untouched. Verify actual `Image`, `IsLoaded` and pixels in both lobby buttons at native size, then root performs the ordinary source/compile audit and separate mouse publication. No new generic upload infrastructure or product creation is necessary.
