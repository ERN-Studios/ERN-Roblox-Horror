# Shared spec - SHOP tab (art director, 2026-10-05)

VIEW: the lobby SHOP window with the SHOP category active, on a 1920x1080 artboard (Framewisp Fit & centre). Every layout shows identical content; only the arrangement changes.

Assumed player state: owns Advanced Equipment and Token Earner 2x, holds 37 Research Tokens and 1 Emergency Re-entry credit.

INFORMATION ARCHITECTURE (this order is the Figma child order, which becomes Roblox LayoutOrder; that also fixes today's alphabetical-by-Name card order):
1. HEADER
   - Eyebrow "ZYNTRA // RESEARCH TERMINAL".
   - Title "ZYNTRA SHOP".
   - TokenPill: "37" + "TOKENS" + AddTokens_button "+". The + scrolls to TOKENS & SUPPLIES (or selects 20 Research Tokens in L3).
   - Close_button_close.
2. CATEGORIES, in this order: UPGRADES, SHOP (active), SKINS, DONATE, COLORS.
   - Icons: UPGRADES = rail-upgrades image, SHOP = rail-shop image, the other three = native glyphs (see the style guide).
   - RECORDS and SETTINGS are not shop categories and are left out of this view.
3. PRODUCTS, in four sections:
   - FEATURED (hero): Expedition Pack.
   - PERMANENT PASSES, helper "BOUGHT ONCE · YOURS FOREVER": Zyntra Supporter, Advanced Equipment, Zyntra Entity Detector, Glowstick Customizer.
   - TOKEN EARNER, helper "HIGHEST TIER WINS · TIERS NEVER STACK" (short form "HIGHEST TIER WINS"): Token Earner 2x, 3x, 5x.
   - TOKENS & SUPPLIES, helper "SPEND TOKENS IN UPGRADES": 4 Research Tokens, 20 Research Tokens, Emergency Re-entry.
4. FOOTER status line: "Prices are read live from Roblox." In game this line also shows purchase results such as "+20 Zyntra Research Tokens".

PRODUCTS. Key = layer suffix and binding key. Hook = at most 16 characters, one line, for compact cards. Benefit_txt = at most 38 characters.

- ExpeditionPack: "Expedition Pack". R$ 69.
  - Kind: REPEATABLE BUNDLE. Ribbon: FEATURED BUNDLE (CREAM). Hook: "STORED UNTIL USED". Benefit: "Stored until used."
  - Contents, long form: "1 Emergency Re-entry credit", "1 Entity Shield charge", "3 Route Markers". Chip form: "1 RE-ENTRY", "1 ENTITY SHIELD", "3 ROUTE MARKERS".
  - Art: product-expedition-pack, hash 84f765f20d2e535b0ae1813103f8662cfbe2c4bf.
- Supporter: "Zyntra Supporter". R$ 99. PERMANENT PASS.
  - Hook: "+10 TOKENS + TAG". Benefit: "+10 tokens and a SUPPORTER name tag".
  - Art: hash f2a7f6187f2e8b153ec5a9e256625b6aaaa06dbb.
- AdvancedEquipment: "Advanced Equipment". OWNED. PERMANENT PASS.
  - Hook: "FOCUS BEAM +45%". Benefit: "Focus beam +45% range, +50% stamina".
  - Badge: OWNED (RAIL TEAL). Button: OWNED state.
  - Art: hash 6400a07cf6bdb0828baffc2deacb9790d0b8912c.
- EntityDetector: "Zyntra Entity Detector". R$ 149. PERMANENT PASS.
  - Hook: "THREAT SCANNER". Benefit: "Reads nearby threat: LOW, MEDIUM, HIGH".
  - Art: hash a519a968280dc9569f983d549b81e65f5c8f490b.
- CosmeticEquipment: "Glowstick Customizer". R$ 99. PERMANENT PASS.
  - Hook: "ANY GLOW COLOR". Benefit: "Pick the color of every glowstick".
  - Art: hash ab622334b363b5ed75ff857494d86c93b90f1cd2.
- TokenEarner2x: "Token Earner 2x". OWNED. PERMANENT PASS.
  - Hook: "2x TOKENS". Benefit: "2x tokens from clears, daily, wheel".
  - Badge: ACTIVE (RAIL TEAL). Button: OWNED state.
  - Art: hash a98d00c4508a0b27902c942ae183fe80cf1f195f.
- TokenEarner3x: "Token Earner 3x". UPGRADE R$ 150. PERMANENT PASS.
  - Hook: "UPGRADE 2x TO 3x". Benefit: "3x tokens from clears, daily, wheel".
  - Ribbon: SAVE R$ 149 (LIME). Meta where room allows: "WAS R$ 299".
  - Button: amber upgrade button ("UPGRADE" / "R$ 150").
  - Art: hash 17defa447ae80cc85c32127c4382fb28e6630c92.
- TokenEarner5x: "Token Earner 5x". UPGRADE R$ 250. PERMANENT PASS.
  - Hook: "UPGRADE 2x TO 5x". Benefit: "5x tokens from clears, daily, wheel".
  - Ribbon: SAVE R$ 149 (LIME). Meta: "WAS R$ 399".
  - Button: amber upgrade button ("UPGRADE" / "R$ 250"). This is the 2x->5x upgrade pass, the cheapest pass that reaches 5x.
  - Art: hash 464cf2dfa585fe12549a602ed51287d7732e9260.
- Tokens4: "4 Research Tokens". R$ 49. REPEATABLE.
  - Hook: "+4 TOKENS". Benefit: "Spend on upgrades, shields, supplies".
  - Art: hash bda4dd60d42a2cb357cdecf9c90bd1afdfe3dbb1.
- Tokens20: "20 Research Tokens". R$ 149. REPEATABLE.
  - Hook: "+20 TOKENS". Benefit: "Best price per token in the shop".
  - Ribbon: BEST VALUE (LIME). This is true: R$ 7.45 per token vs R$ 12.25 for the 4-pack.
  - Art: hash b8624ac8e89d6af011f912445f5f0988df21f135.
- EmergencyReentry: "Emergency Re-entry". R$ 29. REPEATABLE.
  - Hook: "ONCE PER ROUND". Benefit: "Respawn where you fell, 10 s unseen".
  - Badge: "1 STORED" (TILE_HI).
  - Art: hash 0665d3d1289cc0492966f7690fd3a3bfb592ea82.

Nav images: rail-shop 7fabdb1dc268ccec0480b3bdb57022219d5e4149, rail-upgrades c66a32a7204c0bd7fd9b140a1e95c386119671a0. The hashes come from figma-images-v2.json; the uploaded images are on page 2:2.
Fill product icons as {type:'IMAGE', imageHash, scaleMode:'FIT'}. Use 'FILL' only on square tiles.

Not in the data, so do not show: discounts, timers, POPULAR, gift buttons, a Robux logo. Token Earner passes are currently off sale until QA; this design shows their intended on-sale state.

LAYER TREE (identical naming in every layout; # = 1..4):
Shop_L# (FRAME 1920x1080, no fill, clips)
├ Backdrop_ignore (1920x1080, blurred yellow lobby, mockup only)
├ Dim (1920x1080, INK #05090B at 50%)
├ WindowShadow_shadow (1760x1016 at 80,48, INK 60%, r40)
└ ShopWindow_panel (1760x1016 at 80,32, r40, WINDOW gradient, 6 INK stroke)
  ├ Header (1760x136)
  │ ├ TitleBlock > Eyebrow, Title, TitleBar (96x8)
  │ ├ TokenPill > TokenGlyph (TokenChip, TokenBar), TokenCount, TokenLabel, AddTokens_button > Plus
  │ ├ CloseSlot > CloseShadow_shadow, Close_button_close > Glyph
  │ └ HeaderRule (1680x4)
  ├ Categories_tabgroup (auto-layout; direction per layout)
  │ ├ Tab_Upgrades_tab:Upgrades > CategoryIcon (rail-upgrades), Label
  │ ├ Tab_Shop_tab:Shop > CategoryIcon (rail-shop), Label, ActiveBar
  │ ├ Tab_Skins_tab:Skins > CategoryIcon (native: Face, EyeL, EyeR, Mouth), Label
  │ ├ Tab_Donate_tab:Donate > CategoryIcon (native: Coin, Box, Slot), Label
  │ └ Tab_Colors_tab:Colors > CategoryIcon (native: StickTeal, StickCoral, StickLime), Label
  ├ Products_scroll (the visible scrolling window, clips) > Content_list (vertical auto-layout)
  │ ├ Featured_panel > Card_ExpeditionPack
  │ ├ Section_Passes > SectionHeader (SectionTitle, SectionBar, SectionHelper) + Passes_grid | Passes_scroll > Passes_list
  │ ├ Section_Earner > SectionHeader + Earner_grid | Earner_list
  │ └ Section_Tokens > SectionHeader + Tokens_grid | Tokens_list
  ├ Detail_panel (L3 only) > DetailArt > ProductIcon, Ribbon; Kind; Name_txt; Benefit_txt; WhatYouGet; Contents_list > ContentRow x3 (Count, Label); BuySlot > BuyShadow_shadow, Buy_button > Price
  └ Footer > Status

Every card:
Card_<Key> (in L3 rows: Card_<Key>_button, since the whole row selects)
├ Art > ProductIcon (IMAGE), Ribbon > RibbonText, OwnedBadge > BadgeText
├ Name_txt (or Name)
├ Benefit_txt and/or Hook, Meta (optional)
└ BuySlot > BuyShadow_shadow, Buy_button > Price (+ PriceLabel "UPGRADE" on upgrade buttons)

Owned cards keep the name Buy_button.

Fonts: Montserrat Black/ExtraBold/SemiBold, Roboto Condensed Black, Roboto Mono Bold. That is all.

Binding notes for the game:
- Prices bind per Key to the live MarketplaceService price.
- Ownership comes from the ZyntraOwns* attributes.
- "1 STORED" comes from ZyntraReentryCredits.
- TokenCount needs a NEW published attribute (e.g. ZyntraTokens). None exists today.