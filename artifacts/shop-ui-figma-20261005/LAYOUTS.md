# The four layouts

## L1 - Field Catalogue (rail + featured banner + 4-column grid)

Pitch: The classic big-simulator shop. A labelled category rail on the left (thumb-reachable), a wide featured bundle banner, then sectioned 4-up card grids. It is the densest layout and the most familiar: every product is a full card with art, name, benefit and a big amber price button. The Token Earner row's spare cell shows the player's current multiplier, which the game never shows today. The tokens row's spare cell is a shortcut into UPGRADES.

Inspired by: Pet Simulator 99 / PSX Exclusive Shop (pack banner above a card grid); DOORS lobby store (dense 4-up grid, owned strip, hero row); Anime Vanguards store and Blade Ball's store (category column on the left beside the grid).

Structure: Coordinates are window-relative; the window is 1760x1016 at artboard (80,32).

HEADER (0-136):
- TitleBlock at (48,20): eyebrow 30, Title 64 at y52, TitleBar 96x8 at (48,126).
- TokenPill (1136,12) 456x112.
- CloseSlot (1616,8) 120x120, which is artboard x1696-1816, y40-160.
- HeaderRule (40,136) 1680x4.

CATEGORIES_TABGROUP: a vertical rail at (40,164), 272 wide.
- 5 tabs, 272x120 each, gap 12 (ends y808).
- CategoryIcon 80 at (16,20); Label 34 at x112.
- Active SHOP: TILE fill, 4 RAIL TEAL stroke, 8x56 RAIL TEAL bar on the inner left edge.

PRODUCTS_SCROLL (336,164), 1384x792, vertical. Content_list gap 24.
1. Featured_panel = Card_ExpeditionPack, 1384x208, TILE, 4 ICON TEAL stroke.
   - Art 176 at (16,16) with the FEATURED BUNDLE ribbon.
   - Name 'Expedition Pack' (Montserrat Black 56) at (216,24).
   - Contents_txt '1 Emergency Re-entry · 1 Entity Shield · 3 Route Markers' (32 SAGE, 2 lines, max width 740) at (216,96).
   - BuySlot 360x128 at (1000,40): 'R$ 69' at 72.
2. Section_Passes.
   - SectionHeader 56: 'PERMANENT PASSES' 44 + SectionBar; helper 'BOUGHT ONCE · YOURS FOREVER' right-aligned, 30 SAGE.
   - Passes_grid: 4 columns, cells 328x488, gap 24 (4x328 + 3x24 = 1384).
   - Card layout: Art 160 centred at y16; Name_txt at y188 (2 lines, 80); Benefit_txt at y272 (2 lines, 76); BuySlot (16,360) 296x112.
   - Cards: Supporter R$ 99; AdvancedEquipment (OWNED badge + owned button); EntityDetector R$ 149; CosmeticEquipment R$ 99.
3. Section_Earner.
   - Header 'TOKEN EARNER' / 'HIGHEST TIER WINS'.
   - Earner_grid, 4 columns:
     - 2x: ACTIVE badge, OWNED button.
     - 3x: SAVE R$ 149 ribbon, UPGRADE R$ 150.
     - 5x: SAVE R$ 149 ribbon, UPGRADE R$ 250.
     - 4th cell EarnerStatus (non-interactive; INK fill, 3 LINE stroke): 'YOUR EARNER' (mono 30 SAGE), '2x' (Roboto Condensed Black 160 CREAM), ACTIVE badge, 'TIERS NEVER STACK' (32 SAGE).
4. Section_Tokens.
   - Header 'TOKENS & SUPPLIES' / 'SPEND TOKENS IN UPGRADES'.
   - Tokens_grid:
     - Tokens4 R$ 49.
     - Tokens20: BEST VALUE ribbon, R$ 149.
     - EmergencyReentry: '1 STORED' badge, R$ 29.
     - 4th cell GoUpgrades_button: TILE_HI fill, 4 ICON TEAL stroke, rail-upgrades art 120, 'OPEN UPGRADES' (ExtraBold 34). It switches to the Upgrades tab.

FOOTER: Status at (336,964): 'Prices are read live from Roblox.', 32 SAGE.

ABOVE THE FOLD: header, the full rail, the featured banner and the complete PERMANENT PASSES row (208+24+56+16+488 = 792). TOKEN EARNER starts just below.

Phone: At 0.36x on an 844x390 phone, the window is about 635x367 pt.
- Rail tabs: 120 px is 43 pt, a good left-thumb column.
- Cards are 328 px, about 118 pt wide. That is the narrowest of the four layouts and slightly under the research brief's 137 pt ideal.
- Card text: names 34 px is 12.3 pt; benefits 32 px is 11.6 pt; prices 52 px is 18.8 pt.
- Buttons: card buy 112 px is 40 pt; featured buy 128 px is 46 pt; close 120 px is 43 pt.
- On phones it reads like a dense catalogue: art and amber buttons carry it, benefit text is secondary.
- If phone tests show crowding, drop Benefit_txt below the tablet tier (use Hook) rather than shrinking the font.

Reference image: refs/L1-reference.png

## L2 - Storefront Shelves (top tabs + giant hero + horizontal shelves)

Pitch: A modern storefront. Big icon tabs run across the top, a full-width hero bundle with the largest buy button in any of the four layouts, then one horizontal shelf per section (Passes / Token Earner / Tokens & Supplies) that the player swipes sideways. A peeking fourth card signals the swipe. The Token Earner shelf becomes a visible ladder: 2x -> 3x -> 5x joined by a teal track that is lit up to the tier the player owns.

Inspired by: Steal a Brainrot Robux shop and Roblox's own 2026 Shop (Top Picks / Passes / Robux top tabs); Fortnite-style item-shop shelves; 99 Nights in the Forest (tallest featured row with a giant buy button); PS99 starter-pack banner with an item strip.

Structure: Window 1760x1016 at artboard (80,32). The header (0-136) is identical to L1: TitleBlock, TokenPill (1136,12), CloseSlot (1616,8), HeaderRule.

CATEGORIES_TABGROUP: a horizontal strip at (40,152), 1680x112.
- 5 equal tabs, 320x112, gap 20.
- CategoryIcon 80 at the left + Label 34.
- Active SHOP: TILE fill, 4 RAIL TEAL stroke, 120x8 RAIL TEAL underbar centred on the inner bottom.

PRODUCTS_SCROLL (40,280), 1680x672, vertical. Content_list gap 24.
1. Hero_panel = Card_ExpeditionPack, 1680x320, TILE, 4 ICON TEAL stroke.
   - Art 288 at (16,16) with the FEATURED BUNDLE ribbon.
   - Text column x336-1160:
     - Name 'Expedition Pack' (Montserrat Black 72) at y32.
     - Benefit 'Stored until used.' (32 SAGE) at y116.
     - Contents_list (horizontal, gap 16) at y176: three chips, 72 tall, TILE_HI, r12:
       - product-emergency-reentry icon 56 + '1' (44 ICON TEAL) + 'RE-ENTRY' (32 CREAM)
       - '1' + 'ENTITY SHIELD'
       - '3' + 'ROUTE MARKERS'
     - Kind 'REPEATABLE BUNDLE' (mono 30 ICON TEAL) at y264.
   - BuySlot 440x144 at (1216,88): 'R$ 69' at 80, the biggest button in any layout, under the right thumb.
2. Shelf_Passes (Section_Passes).
   - SectionHeader 64: 'PERMANENT PASSES' + 'BOUGHT ONCE · YOURS FOREVER'.
   - Passes_scroll: horizontal _scroll, 1680x240 > Passes_list (horizontal, gap 24).
   - 4 shelf cards, 520x240. Three fit (1608); the 4th (Glowstick Customizer) peeks 48 px.
   - Shelf card: Art 208 at (16,16); text column x240-504 with Name_txt 34/40 (2 lines) at y16, Hook (mono 30 SAGE) at y100, BuySlot (240,128) 264x96.
3. Shelf_Earner.
   - Header 'TOKEN EARNER' + 'HIGHEST TIER WINS · TIERS NEVER STACK'.
   - Earner_list (gap 0): card 544x240, LadderLink 24x8, card, LadderLink, card (3x544 + 2x24 = 1680).
   - Link colours: 2x->3x RAIL TEAL (reached); 3x->5x LINE colour (not reached).
   - Cards:
     - 2x: ACTIVE badge, OWNED button.
     - 3x: SAVE R$ 149, Hook 'UPGRADE 2x TO 3x', button 'UPGRADE / R$ 150'.
     - 5x: SAVE R$ 149, Hook 'UPGRADE 2x TO 5x', button 'UPGRADE / R$ 250'.
4. Shelf_Tokens.
   - Header 'TOKENS & SUPPLIES' + 'SPEND TOKENS IN UPGRADES'.
   - 3 cards, 544x240:
     - Tokens4: '+4 TOKENS', R$ 49.
     - Tokens20: BEST VALUE, '+20 TOKENS', R$ 149.
     - EmergencyReentry: '1 STORED' badge, 'ONCE PER ROUND', R$ 29.

FOOTER: Status at (40,964).

ABOVE THE FOLD: header, the tab strip, the whole hero, and the PERMANENT PASSES shelf (3 cards + the peek of the 4th; 320+24+64+240 = 648 of 672).

Phone: At 0.36x on a phone:
- Hero: the buy button is 440x144 px, about 159x52 pt, at the right-thumb position. The hero name is 26 pt.
- Shelf cards: 520 px, about 188 pt wide, so names (12.3 pt) get more room than in L1.
- Shelf buttons are 96 px (35 pt), the floor of what is allowed. Raise them to 104 if the card height can grow.
- Top tabs: 112 px (40 pt) tall, 115 pt wide, easy to hit.
- Risk: horizontal shelves inside a vertical scroll need a clear swipe direction on touch. Keep the 48 px peek, and keep the Earner and Tokens shelves non-scrolling (they fit).
- It uses the least text per card (Hook instead of Benefit), so it is the most glanceable on phones.

Reference image: refs/L2-reference.png

## L3 - Terminal Split (product list + large detail pane)

Pitch: The current Zyntra terminal grown up and made touch-first. On the left, a compact list where every row is one big tap target with icon, name, hook and a price chip. On the right, a large detail pane for the selected product: huge art, a WHAT YOU GET breakdown and one full-width BUY button. It explains products best (Expedition Pack's contents, the upgrade path), and today it is pointer-only; this version brings it to phones.

Inspired by: DOORS pre-run shop (rows with icon, name, one-line description, price, and a full-width confirm button); Forsaken's item store with a preview pane; Jailbreak's revamped gamepass store; the live Zyntra terminal's pointer list+detail (ShopDetail), rebuilt with large type and touch targets.

Structure: Window 1760x1016 at artboard (80,32). The header (0-136) is identical to L1.

CATEGORIES_TABGROUP: underline tabs at (40,148), 96 tall.
- Tabs hug their content, gap 8, left-aligned. Total about 1205 wide.
- CategoryIcon 56 + Label 32.
- Active SHOP: TILE fill, r20, an 8 px RAIL TEAL underbar across its inner bottom, CREAM label.
- Inactive: no fill, SAGE label.
- HeaderRule at (40,252).

LIST PANE = Products_scroll (40,264), 760x688. Content_list gap 12.
- SectionHeader rows: 56 tall, Montserrat Black 40 + a 48x8 bar.
- Product rows Card_<Key>_button: 760x120, TILE, r24, 3 LINE.
  - ProductIcon 104 at (8,8), r20.
  - Name: ExtraBold 32, single line, max 420, at (128,18).
  - Hook: mono 30 SAGE at (128,66).
  - PriceChip (564,20), 180x80, r20, one of:
    - AMBER face, 'R$ 149' at 44 in TILE colour;
    - owned: OWNED_FILL + 3 RAIL TEAL stroke + 'OWNED' at 32 RAIL TEAL;
    - upgrade: 'R$ 150' with Hook 'UPGRADE 2x TO 3x'.
- Row order:
  - FEATURED: ExpeditionPack. Selected: TILE_HI fill, 6 RAIL TEAL stroke.
  - PERMANENT PASSES: Supporter, AdvancedEquipment (OWNED), EntityDetector, CosmeticEquipment.
  - TOKEN EARNER: 2x (OWNED, hook 'ACTIVE · 2x TOKENS' in RAIL TEAL), 3x (R$ 150), 5x (R$ 250).
  - TOKENS & SUPPLIES: Tokens4, Tokens20 (hook 'BEST VALUE · +20 TOKENS', BEST VALUE in LIME), EmergencyReentry (hook '1 STORED · ONCE PER ROUND').

DETAIL_PANEL (824,264), 896x688, TILE, r32, 3 LINE.
- DetailArt 288 at (32,32), with the FEATURED BUNDLE ribbon.
- Right column x352-864:
  - Kind 'REPEATABLE BUNDLE' (mono 30 ICON TEAL) at y40.
  - Name_txt 'Expedition Pack' (Montserrat Black 64/68, 2 lines) at y84.
  - Benefit_txt 'Stored until used.' (32 SAGE) at y236.
- 'WHAT YOU GET' (mono 30 ICON TEAL) at (32,344).
- Contents_list at (32,388), 832 wide: three ContentRows, 44 tall. Each is a Count (Roboto Condensed Black 44, ICON TEAL) + a Label (ExtraBold 34, CREAM):
  - '1  Emergency Re-entry credit'
  - '1  Entity Shield charge'
  - '3  Route Markers'
- BuySlot (32,536), 832x128: Buy_button 'BUY  ·  R$ 69' at Roboto Condensed Black 64. It ends at 664 + 24 padding.

FOOTER: Status at (40,964).

ABOVE THE FOLD: the header and tabs; in the list, FEATURED + Expedition Pack, PERMANENT PASSES and three pass rows plus part of the fourth; the complete detail pane with BUY. Token Earner and Tokens rows are one scroll below.

Phone: At 0.36x on a phone:
- Every list row is a full-width 120 px target (274x43 pt). This is the easiest of the four layouts to tap accurately.
- The detail BUY is 832x128 px (300x46 pt) at the bottom-right, under the right thumb.
- Detail name 64 px is 23 pt; WHAT YOU GET lines 34 px are 12.3 pt.
- Row names are 32 px (11.6 pt), single line. 'Zyntra Entity Detector' just fits in 420 px, so keep the price chip at 180 wide.
- Inline tabs are 96 px (35 pt), at the floor.
- Trade-off: the list pane shows only about 5 rows at a time, so browsing all 11 items takes a scroll. This layout optimises deciding over browsing.

Reference image: refs/L3-reference.png

## L4 - Bento Home (mosaic of big, medium and small tiles + bottom dock)

Pitch: A store home screen rather than a catalogue. Tile size tells the story:
- The bundle is the biggest tile.
- The Token Earner ladder (with both upgrade prices) is one wide tile.
- The best-value token pack and the cheap Re-entry impulse buy are small tiles beside it.
- The passes form the row below, with Supporter as the wide flagship.
Categories move to a centred bottom dock, which frees the whole top of the window for products and keeps clear of the thumbstick and jump corners.

Inspired by: Adopt Me and Grow a Garden store home screens (featured tiles of mixed sizes); Dress to Impress shop (a big featured VIP card beside a grid of smaller tiles); Blox Fruits bundle banner; mobile storefront docks (bottom-centre category bar).

Structure: Window 1760x1016 at artboard (80,32). The header (0-136) is identical to L1.

PRODUCTS_SCROLL (40,152), 1680x680 (ends 832). Content is a fixed 1680x960 bento frame on a 12-column grid (column 118, gutter 24).

BAND 1 (y 0-560):
- Card_ExpeditionPack, the hero tile: (0,0) 828x560, TILE, 4 ICON TEAL.
  - Art 336 at (24,24) with the FEATURED BUNDLE ribbon.
  - Text column x384-804:
    - Name_txt 'Expedition Pack' (Black 64/68, 2 lines) at y32.
    - Benefit 'Stored until used.' at y184.
    - Contents at y240-384: 3 rows of 48. Each is a Count (44 ICON TEAL) + a Label (32 CREAM): '1 Re-entry credit', '1 Entity Shield', '3 Route Markers'.
  - BuySlot (24,400) 780x136: 'R$ 69' at 72.
- Earner_panel: (852,0) 828x316, no fill, 3 LINE, r32.
  - Title 'TOKEN EARNER' (Black 40) at (24,16); helper 'HIGHEST TIER WINS' (mono 30 SAGE) right-aligned.
  - Earner_list at (24,72), horizontal, gap 18: three sub-cards, 248x228, TILE, r24.
  - Sub-card layout: ProductIcon 96 at (12,12); state column x116-236; BuySlot (12,120) 224x96.
  - States:
    - 2x: ACTIVE chip, OWNED button.
    - 3x: LIME 'SAVE' / 'R$ 149', amber 'UPGRADE / R$ 150'.
    - 5x: LIME 'SAVE' / 'R$ 149', amber 'UPGRADE / R$ 250'.
- Small tiles, 402x220 each, at (852,340) and (1278,340):
  - Card_Tokens20: BEST VALUE ribbon at (16,12); Art 140 at (16,68); Name_txt 32/36 (2 lines) at (172,16); BuySlot (172,108) 214x96, 'R$ 149'.
  - Card_EmergencyReentry: the same layout, '1 STORED' badge, 'R$ 29'.

BAND 2 (y 584-960):
- Card_Supporter, wide medium: (0,584) 544x376.
  - Art 224 at (16,16).
  - Text column x256-528: Name_txt 36/40 at y24; Benefit_txt 32/38 at y112.
  - BuySlot (16,264) 512x96, 'R$ 99'.
- Four vertical medium tiles, 260x376, at x 568, 852, 1136, 1420: Card_AdvancedEquipment (OWNED), Card_EntityDetector (R$ 149), Card_CosmeticEquipment (R$ 99), Card_Tokens4 (R$ 49).
  - Layout: Art 152 centred at y16; Name_txt 32/36 at y184; BuySlot (16,264) 228x96.

STATUS: (40,840) 1680x40, centred: 'Prices are read live from Roblox.'

CATEGORIES_TABGROUP: a bottom dock at (356,888), 1048x112 (artboard x436-1484, y920-1032).
- INK fill, r56, 3 LINE, padding 8.
- 5 items, 200x96, gap 8: icon 48 over Label 30.
- Active SHOP: TILE fill + 4 RAIL TEAL stroke.

ABOVE THE FOLD: header; all of band 1, which is the hero, the full Token Earner ladder with ACTIVE / UPGRADE R$ 150 / UPGRADE R$ 250, 20 Research Tokens (BEST VALUE) and Emergency Re-entry; the top 96 px of band 2 (art tops of Supporter, Advanced Equipment, Detector, Glowstick and 4 Tokens); the status line; the dock.

Phone: At 0.36x on a phone:
- Hero buy: 780x136 px, about 282x49 pt.
- Dock: items 96 px (35 pt) tall and 72 pt wide. The dock is centred between artboard x436 and x1484, about 157-536 pt on an 844 pt screen, so it stays out of the bottom-left thumbstick and bottom-right jump zones.
- Small tiles and Earner sub-cards use 96 px buttons (35 pt), at the floor. Earner sub-card buttons are only 224 px (81 pt) wide.
- Small-tile names at 32 px (11.6 pt) wrap to 2 lines; '20 Research' just fits in 214 px.
- Strongest first impression of the four: the biggest money items are huge.
- Weakest for a complete scan: the passes sit below the fold, and the fixed-position bento needs a re-layout for the tablet/phone tiers rather than simple reflow.

Reference image: refs/L4-reference.png

