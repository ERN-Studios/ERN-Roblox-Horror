# Roblox shop UI research brief, for the Zyntra lobby shop (2026-10-05)

**How this was gathered.** Fandom pages return HTTP 402 to WebFetch. I pulled their wikitext through the MediaWiki API instead and downloaded the shop screenshots the wikis host. I looked at 26 real shop screens from DOORS, Dress to Impress, Grow a Garden, Pet Simulator 99/X, Anime Vanguards, Murder Mystery 2, Forsaken, Piggy, Dead Rails, Steal a Brainrot, Blox Fruits, Jailbreak, Arsenal, 99 Nights in the Forest and Adopt Me. Colours and proportions marked "≈" are my estimates from those screenshots, not exact values.

**Coverage gaps.**
- Bee Swarm and Brookhaven: text only.
- Apeirophobia and The Mimic: I found no documentation of their shop UI.
- Pet Simulator 99's current shop window: only its pack banners are on the wiki; the full-window shot is from PSX.

---

## 0. Two corrections to the run's constraints (read first)

**1. The "24 px minimum text" rule is too small.** Under Framewisp "Fit & centre", a 1920×1080 design on an 844×390 phone is height-bound, so it scales by 390/1080 = 0.361. If the ScreenGui respects the Roblox top bar (36 px classic, or 58 px according to a reply in the Roblox staff thread), the scale drops to about 0.307.

| Artboard px | Phone pt @0.361 | Phone pt @0.307 |
|---|---|---|
| 24 | 8.7 | 7.4 |
| 32 | 11.6 | 9.8 |
| 40 | 14.4 | 12.3 |
| 48 | 17.3 | 14.7 |
| 96 | 34.7 | 29.5 |
| 120 | 43.3 | 36.8 |
| 132 | 47.7 | 40.5 |

Published guidance is 14–18 TextSize for body text and a 44×44 pt minimum touch target, rising to 56 for important actions (kitsblox, spawnblox). Recommended floors on the artboard:

| Element | Recommended size |
|---|---|
| Any text | 32 px absolute floor |
| Meta / body text | 36–40 px |
| Item names | 44–52 px |
| Prices | 48–60 px |
| Section headers | 64 px |
| Window title | 88–110 px |
| Buy buttons, tabs, close | ≥ 120 px tall |
| Secondary chips | ≥ 96 px |

**2. Use the whole artboard.** Every pixel outside the window is letterbox on a phone, so the window should fill at least 90% of the artboard height (about 1760×980). Put the dimmed backdrop in a separate `_ignore` layer.

**Also new this year: Roblox's own Shop.** It was announced 2026-06-24 and adds a global Shop button **top-left next to the top bar**, plus `MarketplaceService:OpenShop()` from 2026-09-16. Its tabs are "Top Picks / Passes / Robux", so players now know those labels. Keep our opener and any tappable elements out of the top-left corner.

---

## 1. Shared conventions that make a shop feel like a big game

### Window and header

| Convention | Observed |
|---|---|
| One modal panel, centred, rounded, with its own frame colour and a visible 4–8 px border | All of them. PS99: thick dark-navy border. 99 Nights: light-blue 8 px border. Anime Vanguards: violet gradient outline. DOORS: thin 2 px cream border. |
| Title top-left or top-centre, about 6% of panel height, display font, often breaking out of the frame | PS99 "Exclusive Shop!" is a tilted tab breaking the top edge. 99 Nights "BUY DIAMONDS" has gem art spilling over the border. DOORS "Store" is a condensed title top-left. GaG title sits on a grass header bar. |
| A coloured header strip that carries the title, timer and utility buttons | GaG: "New seeds in 3m 9s", a yellow RESTOCK button, then the X. Adopt Me: an orange header with "You have: 0 Candy". |

### Close button

- It sits top-right on every verified shop except old MM2, which puts it top-left.
- Its size is about 5–7% of panel width: DOORS 6.4%, GaG 5.9%, 99 Nights 6.3%, Blox Fruits 6.4%, Adopt Me 5.8%.
- Style: a red rounded square with a darker red 3–4 px stroke and a white bold X (GaG, 99 Nights, Blox Fruits, Adopt Me). DTI uses a pink circle; DOORS uses a large bare cream X glyph with no plate (the horror version).
- On our window that works out to **120×120**, inset about 24 px or overlapping the corner by half its size.

### Currency display

- A pill showing your balance sits in the header next to the close button or under the title.
- MM2: a gold coin bar plus a gem bar with a green "+" to buy more.
- DOORS pre-run shop: the knob count in a rounded box top-right.
- Blox Fruits and Adopt Me: "You currently have 7017 Candy Eggs" in a footer or header.
- Convention: icon left, number right-aligned, and a **"+" button** that jumps to the currency tab.

### Category navigation

- **Top tabs dominate** in what I could verify:
  - DTI: 5 icon-over-label tabs, each about 13% of panel width, plus a search field.
  - MM2: tabs in a different colour each, with item art (Effects, Powers, Emotes, Radios, Pets).
  - PS99: small icon chips top-right (star, pet, $, flame, gem).
- **Stacked sections in one scroll** is the other pattern: DOORS runs FEATURED | TODAY'S DEALS | KNOBS | REVIVES as big section headers with no tabs, and PS99 puts Redeem Codes at the bottom. Section headers are about 4–5% of panel height in heavy caps.
- **Left rail:** I did not verify one as a nav rail in these games. DTI's left column is a featured VIP card, not navigation. PS99 moves its shop opener to the left side on mobile (wiki).

### Featured / bundle banner

- A full-width hero row, 25–35% of panel height, above the grid.
- PS99 starter pack: a banner with a mascot left and an item strip with "x3" quantity labels. The green Robux button is huge, about 14% of banner width.
- DTI: a "$40500" best-value hero under the 4-up currency row.
- 99 Nights: the biggest pack is the tallest row, about 30% height, and gets a giant buy button.
- DOORS: two big bundle tiles left, a deals grid right.
- Blox Fruits: a bundle banner with a timer blob and a strikethrough old price.
- **Rule:** the most expensive or best-value item is the biggest thing on screen, with ascending tiers next to or under it.

### Card anatomy (top to bottom)

1. Image area, 55–65% of the card. Art is large, overflows the slot slightly, and sits on a tinted background (DOORS tints each card in the item's colour; PS99 uses a sunburst behind it).
2. Rarity or star marks top-left: PS99 and 99 Nights use 1–3 small stars; GaG uses a coloured rarity chip top-right.
3. Ribbon or discount top-right.
4. Name, in a bold display font with a dark outline.
5. Price at the bottom, in one of two forms:
   - **Full-width price strip**, 20–25% of card height (DOORS, Blox Fruits, Adopt Me).
   - **Pill button**, about 60–70% of card width (PS99, Anime Vanguards, 99 Nights, DTI).
- **Rarity colours (near-universal):** Common grey · Uncommon green · Rare blue · Epic purple · Legendary gold/orange · Mythic red/pink. GaG adds Divine orange and Prismatic.

### Ribbons and value labels (pick one or two, not all)

| Type | Examples |
|---|---|
| Corner sash "BEST VALUE!" | DTI: a gold diagonal sash. 99 Nights: a red hanging price tag. |
| Flag "Best Deal!" | GaG: red, top-left. |
| Escalating value words inside the price strip | Adopt Me: GOOD VALUE, GREAT VALUE, BEST DEAL! |
| Percentage bonus under the amount | DOORS: "20% EXTRA / 30% / 40% EXTRA" in gold. |
| Discount chip | 99 Nights "-10%" (red rounded chip, top-right). Dead Rails "-70%" (pink, tilted, on the button corner). |
| Strikethrough original price | Blox Fruits: 9999 next to struck-out 13998. |
| Slanted callout text breaking the grid | Anime Vanguards: "BEST DEAL!" in green with a black stroke, overlapping card borders. |
| Small status lines | PS99: "Recently Increased!" in lime. |

### Price buttons by currency (≈ hex)

| Currency | Treatment |
|---|---|
| **Robux, majority style: saturated green**, light top to dark bottom, dark green stroke, white Robux glyph and number with a dark outline | PS99 ≈ #6BD62B→#3FA51C with stroke #1F5E0F. Anime Vanguards ≈ #2BE36A→#16B24A. 99 Nights ≈ #18B312 / #0B6E08. Dead Rails ≈ #22E85A. Steal a Brainrot: muted flat green. |
| Robux, alternatives | DTI gold-yellow ≈ #FFD21F→#F5A70A. DOORS cream-peach gradient, with red ≈ #F0505E for Revives. Jailbreak: dark pill with gold outline "450 R$". Forsaken: dark rectangle with a thin grey border. PSX: blue. |
| Soft currency | Blox Fruits: a yellow strip with an egg icon. GaG: a green button with "¢". MM2: inline "100 💎 / 1,000 🪙" on the art with no button. 99 Nights: inline diamonds with no button, the whole card is the tap target. |
| **Takeaway** | Robux and soft currency must never share a style. A common split is green/gold for Robux and in-theme outline or inline for tokens, or the other way round. |

### Owned, equipped and out-of-stock states

- **OWNED:**
  - DOORS: the price strip becomes a dark strip with muted grey "OWNED"; the card art stays in full colour.
  - 99 Nights: a big green check over the portrait plus green "OWNED" text.
- **EQUIPPED:** 99 Nights fills the card green with a yellow 4 px highlight outline and the text "EQUIPPED".
- **Show-owned toggle:** 99 Nights has one in the header.
- **Sold out:** GaG shows a grey "NO STOCK" button and red "X0 Stock".
- **Gated:** PS99 hides the next permanent pack until the previous one is bought.

### Gamepasses vs consumables

| | Gamepass (permanent) | Consumable / currency |
|---|---|---|
| Card | Larger, often 2 per row (DTI) | Smaller, 3–5 per row |
| Art | Circular portrait or badge (DTI, Jailbreak) | Pile of the item, growing per tier: 1 bill, a stack, a crate, a truck |
| Text | Name and a 1–2 line benefit description | Just the amount |
| Actions | Price, then a **gift button** to its right | Price only |
| Value cue | — | A value label ("+40% EXTRA", BEST VALUE) |

- **Gift buttons are now standard:** DTI, Forsaken, 99 Nights "GIFT GEMS", Blox Fruits, and Steal a Brainrot's "Gift Player". Forsaken adds a **preview (eye)** button.
- **Codes** sit inside the shop: DOORS has a code field at the top; 99 Nights has a CODES button bottom-right; PS99 puts codes at the bottom.

### Limited-time timers

- A red blob or pill at the top-left of the banner: Blox Fruits "07d 01h 14m".
- A clock icon plus "New deals in 23h 18m" in the header: GaG.
- "00:00:00" under the buy button: Dead Rails.
- Text dates: Bee Swarm uses "Offer ends Feb 9th".
- Rotating stock: DOORS Today's Deals rotate daily at 3 PM EST; GaG every 5 minutes, with a 79 Robux restock; DTI's Weekly Boutique every 7 days; 99 Nights runs a daily class shop with sales.

### Outlines, gradients, fonts, bevels

**Outlines**
- On text: a 1–2 px dark stroke at native size, about 6–8% of cap height. Big numbers and titles get thicker strokes.
- Panel and button strokes: the simulator tutorial uses 6–15 px, always Outside, and always a darker shade of the fill. DOORS and Forsaken drop to 2 px light strokes.

**Gradients**
- Vertical, 2 stops, lighter top. Used on every buy button and many card backgrounds.
- 99 Nights runs blue to white inside its cards; DOORS uses a peach price gradient.

**Bevel (native recipe)**
- Button = a dark "base" frame, then the face frame lifted 6–10 px with the same radius. Gradient on the face, darker-shade stroke on both.
- DTI adds diagonal gloss stripes. Those are rotated frames or an image; Framewisp rotation support is unverified, so use an image or skip them.

**Fonts, as identified by eye**
- PS99 and DTI: Fredoka One. DTI: rounded white with a pink drop.
- Anime Vanguards: a rounded heavy font with a black stroke.
- Steal a Brainrot, Jailbreak, Dead Rails labels: a Gotham/Montserrat Black look.
- DOORS: a condensed Oswald-style font for titles and body, Montserrat-style ExtraBold for big numbers.
- Piggy: typewriter, matches Special Elite.
- Forsaken: a worn serif. There is no allowed equivalent; use Special Elite or Jura.
- GaG: a comic font with a heavy black stroke.

**Feedback worth faking statically**
- GaG: an item expands and shakes on hover.
- Hover grow (keep it small; the devforum says oversized hover looks bad).
- A press "sink": the face drops onto the base.
- Click and cash sounds.
- In Figma, show one card in its hovered state (scale 1.05 with a brighter stroke), the sparkle and shine stars as part of the art image, and a static sunburst behind featured art. A sunburst is a radial shape, so it bakes; reuse one image.

---

## 2. How the horror games darken it and stay readable

**DOORS** (closest reference, verified screenshots)
- Near-black warm panel ≈ #1D1414 with card fills ≈ #3A2A28 and a 2 px cream border ≈ #F5D9C4.
- A cream/peach palette in place of white.
- Condensed caps titles; big numbers with a soft drop shadow instead of a cartoon stroke.
- Card backgrounds tinted at about 30% saturation in each item's colour (red skin → maroon card).
- It still keeps every big-game convention: a hero row ("3 BOOSTS" with a buy button), "20% EXTRA" value labels, an OWNED strip, a code field, a big X.
- The pre-run shop uses 2-column rows (icon, name, one-line description in small condensed text, price on the right) and a full-width muted-green CONFIRM button with the cost under it.

**Forsaken**
- Desaturated grainy grey-black, a serif cream title, square corners, 1–2 px light-grey outlines.
- Price, gift and eye buttons as separate boxed chips; pagination dots for multi-page packs.
- It reads as "film noir", not "cartoon".

**Piggy**
- A typewriter font (Special Elite), a dark maroon panel with a red rounded border, a pink icon accent.
- Uniform icon tiles with outline colour coding the source: white = purchasable, grey = badge reward, yellow/green = special.

**Dead Rails**
- A pure black panel with a distressed edge (image) and a western serif title with a white glow.
- White Montserrat-style labels, and **a vivid green Robux button with a pink "-70%" chip**: the buy button is the only saturated thing in the frame.
- Its Close button is a separate dark plate under the panel.

**The common recipe**
- Darken and desaturate the chrome.
- Swap white for a warm cream or the brand accent.
- Thin the panel strokes and drop the cartoon text outlines, using shadows instead.
- Keep **one** loud colour for the purchase action and one for the ribbon or discount.
- Keep big numbers and the hero/tier/value structure exactly as the simulators do.
- Readability comes from size and value contrast (aim for at least 4.5:1, per spawnblox), not from saturation.

---

## 3. Mobile-first sizing rules

| Rule | Source | On our 1920×1080 artboard |
|---|---|---|
| Touch target ≥ 44×44 pt; ≥ 56 for important or destructive actions | kitsblox, spawnblox | ≥ 120 px; Buy and Close 132–150 px |
| Keep interactive elements ≥ 48 px from screen edges | kitsblox | Window inset ≥ 130 px from the artboard's left and right edges, since phone width is the bound after letterboxing |
| Bottom-left = thumbstick, bottom-right = jump; avoid them | Roblox staff thread, devforum mobile-buttons post | Keep tappables out of the bottom 25% corners |
| Top bar reserved (36, or about 58 new); the native Shop button is top-left | Staff thread, Roblox Shop announcement | Keep the top-left clear; Close goes top-right |
| Body TextSize 14–18 on phone | kitsblox | Text 40–48 px; floor 32 px |
| Mobile is 60–70%+ of players; design phone-first | Staff thread, spawnblox | Test at 844×390 in the Device Emulator |
| Use Scale, not Offset; anchor 0.5,0.5; UIAspectRatioConstraint | Staff thread, ultimate guide | Framewisp does this; tag key tiles `_aspect` |
| TextScaled with no constraint renders inconsistently | kitsblox | Use fixed sizes; reserve `_fit` for single numbers |

**Cards per row (observed):**

| Layout | Games |
|---|---|
| 3 per row | Anime Vanguards, Blox Fruits, Adopt Me, PS99 |
| 4 per row | DOORS, MM2, 99 Nights, DTI currency |
| 2 per row | Descriptive gamepass cards (DTI) |
| 1 per row | List shops (GaG, 99 Nights diamonds) |

- For us: **3–4 per row**, with cards about 380–480 px wide (137–173 pt on a phone), plus one hero row.
- Five or more per row pushes names below 10 pt.
- In landscape, the right thumb covers the right half: put the hero's buy button on the right; tabs at the top or on a left rail work for the left thumb.

---

## 4. Six candidate directions for the Zyntra lobby shop

Each direction lists its borrowed sources and its Framewisp image budget. Every direction shares the product art from `figma-assets.json`, which counts once.

**A. "Requisition Terminal"** (DOORS store, plus the DTI left featured column)
- Palette: #070B0D background, #141D21 cards, 2 px teal #44DDC4 borders.
- Fonts: Oswald caps for titles and labels, Montserrat Black for numbers.
- Layout:
  - Left column: a tall featured card, "ZYNTRA SUPPORTER" (gamepass, benefit text, buy plus gift).
  - Right: stacked sections FEATURED, DAILY ISSUE (4-up), TOKENS (4-up tiers with "+20% EXTRA" in gold #FFCB4F).
- Buttons: Robux buy is a token-gold gradient pill; token prices are a teal-outline pill.
- Owned = a dark strip with muted "ISSUED".
- Feel: the most "horror-native" option and the safest for Framewisp. Images: art only.

**B. "Hazmat Supply Drop"** (PS99 banner, Anime Vanguards dark cards, 99 Nights buy buttons)
- The big-simulator look in dark mode: deep blue-black #0E1418 cards with a 4 px teal gradient outline, and the window frame is a thick 8 px #FFCB4F hazmat-yellow stroke.
- Fredoka One / Luckiest Guy with a 3 px dark text stroke.
- Hero starter-pack banner with an item strip and "x3" labels.
- Green bevelled Robux buttons, a "BEST DEAL!" slanted callout, icon tabs top-right.
- Feel: the strongest "big game" read. Images: art plus 1 sunburst.

**C. "Case File"** (Forsaken, Piggy, MM2 grid)
- Grainy grey-black (one shared paper/grain image), Special Elite typewriter titles, cream text, square corners, 2 px light outlines.
- Cards look like evidence tags with a red stamp chip "CLASSIFIED -30%".
- A price chip, gift chip and eye chip under each card; pagination dots.
- Only the buy chip is saturated: emergency red #F45F52 for Robux, teal for tokens.
- Images: art plus 1 grain.

**D. "Emergency Protocol"** (Dead Rails starter pack, Blox Fruits bundle, GaG daily deals)
- Black panel with an emergency-red hazard-stripe header (a linear gradient with hard stops is native, up to 20 stops).
- Michroma or Sarpanch titles, Montserrat Black numbers.
- Countdown timers everywhere: "SUPPLY WINDOW CLOSES 23h 18m" in the header, a red timer pill on the hero bundle.
- A tilted-looking "-70%" chip (keep it unrotated), a vivid green buy button as the only green, strikethrough prices.
- Images: art only.

**E. "Level 0 Vending Wall"** (Grow a Garden seed shop, 99 Nights daily shop)
- A diegetic frame: Backrooms mono-yellow wallpaper border (one image) around dark list rows.
- A row = icon tile, name, "X3 IN STOCK" in teal, price button right.
- A header strip: "NEW STOCK IN 3m 09s", a RESTOCK button, a red close square.
- States: NO STOCK greyed; a "Best Deal" red flag on a daily hero row; a "show owned" toggle; EQUIPPED = a teal-filled card with a gold outline.
- Feel: playful, very readable, phone-friendly (1-column rows mean huge targets). Images: art plus 1 wallpaper.

**F. "Field Unit HUD"** (Jailbreak gold pills, Roblox native Shop tab vocabulary, DOORS layout)
- A teal-phosphor sci-fi terminal: Jura/Michroma plus Roboto Mono numbers.
- A left rail of 120 px tall tabs (TOP PICKS / PASSES / SUPPLIES / TOKENS / CODES), thumb-reachable.
- Corner-bracket frames, built from 4 small native frames per corner (no vectors).
- Gamepasses as circular badges with a gold-outlined price pill; scanlines as one shared image.
- Images: art plus 1 scanline.

---

## 5. Anti-patterns that make a Roblox shop look amateur

From devforum feedback threads and the wikis:
- Inconsistent icon style, size or detail level, or icons that are white while the buttons are colourful. Even GaG's wiki notes its Robux seed icons are "laid sideways, some do not include outlines, some outlines are way thicker".
- Content overflowing a ScrollingFrame without clipping; uneven gaps; no layout objects (use `_list` / `_grid`).
- Strokes too thin; cramped padding inside buttons; hover growth so big it overlaps neighbours.
- A close button that doesn't match the rest of the UI; garish pure-red text; a currency display that takes too much space.
- Controls with no affordance (a search bar with no icon or placeholder).
- Theme mismatch (a skull "death effects" tab in a cute pet shop); everything dark with no hierarchy, or everything loud with no hierarchy.
- Default Roblox look: grey frames, SourceSans, no corners, no gradient, no art. The "first GUI" redesign thread's fix was rounded shapes, colour, tweens and a TextSizeConstraint.
- No purchase confirmation dialog. DTI shows a full "Checkout" confirm/cancel modal even for soft currency.
- Robux and soft-currency buttons styled the same; no owned state; buttons that stay active on owned items.
- Text below about 11 pt on phone, or TextScaled with no constraint; tappables in the thumbstick or jump zones or the top-left top-bar zone.
- Framewisp-specific: decorative vectors, radial glows, per-corner radii, inner shadows and gradient-filled text each bake to a PNG. More than 15 distinct images means a failed free-plan conversion.

---

## Sources used

Devforum and guides:
- https://devforum.roblox.com/t/designing-ui-tips-and-best-practices/3074034
- https://devforum.roblox.com/t/the-ultimate-ui-design-guide/1236916
- https://devforum.roblox.com/t/how-to-make-ui-styled-for-simulator-detailed-tutorial/2895762
- https://devforum.roblox.com/t/feedback-on-ui-shop/3603272
- https://devforum.roblox.com/t/how-can-i-make-my-shop-ui-better/3293954
- https://devforum.roblox.com/t/how-should-i-redesign-my-shop-gui/1553556
- https://devforum.roblox.com/t/feedback-on-my-pet-simulator-99-inspired-ui/3814728
- https://devforum.roblox.com/t/feedback-on-my-shop-ui/2862690
- https://devforum.roblox.com/t/the-correct-way-to-design-mobile-buttons/2494558
- https://devforum.roblox.com/t/introducing-shop-a-personalized-in-game-storefront/4701505
- https://devforum.roblox.com/t/tutorial-how-to-make-roblox-shop-gui-scripting-design-free-plugin/4159627
- https://spawnblox.com/articles/ui-ux-design.html
- https://kitsblox.com/blog/fix-roblox-ui-scaling-mobile
- https://doorsgame.wiki/wiki/Shops

Fandom pages (wikitext via `/api.php` plus their hosted screenshots):
- https://doors-game.fandom.com/wiki/Shops (screenshots: Lobby Shop, NewLobbyShop, TodaysDealsSection, Pre-run shop The Hotel)
- https://doors-game.fandom.com/wiki/Lobby_Menu
- https://pet-simulator.fandom.com/wiki/Exclusive_Shop_(Pet_Simulator_99) (screenshots: Super Starter Pack, Super Diamond Pack, Exclusive Shop PSX)
- https://growagarden.fandom.com/wiki/Seed_Shop (screenshots: SeedshopUI, DailyDealsSeedShop)
- https://dress-to-impress.fandom.com/wiki/Shop (screenshots: Gamepasses, Currency, Checkout)
- https://animevanguards.fandom.com/wiki/Store (screenshot: GemShop)
- https://murder-mystery-2.fandom.com/wiki/Shop (screenshot: WInterface)
- https://forsaken2024.fandom.com/wiki/Gamepasses_%26_Products (screenshots: SpecOpsPackFeatured, Kawaii in shop)
- https://piggy.fandom.com/wiki/Shop (screenshot: Itemsmenunew)
- https://dead-rails.fandom.com/wiki/Bundles (screenshots: Starter Pack UI, Christmas Bundle)
- https://dead-rails.fandom.com/wiki/Lobby
- https://stealabrainrot.fandom.com/wiki/Robux_Shop
- https://stealabrainrot.fandom.com/wiki/Gamepasses_and_Dev_Products/Gallery
- https://blox-fruits.fandom.com/wiki/Shop (screenshots: Ultimate Bundle 2025, Easter-shop-ui)
- https://jailbreak.fandom.com/wiki/Gamepasses (screenshot: GamepassStoreRevamp)
- https://roblox-arsenal.fandom.com/wiki/Shop
- https://99-nights-in-the-forest.fandom.com/wiki/Diamonds (screenshots: CurrencyShop, Classes Shop)
- https://adoptme.fandom.com/wiki/Gamepasses (screenshot: 2020 Candy exchange)
- https://bee-swarm-simulator.fandom.com/wiki/Robux_Shop
- https://brookhaven.fandom.com/wiki/Gamepasses

The downloaded screenshots are in `C:\Users\mikke\AppData\Local\Temp\wk\img\` if a designer wants to look at them.