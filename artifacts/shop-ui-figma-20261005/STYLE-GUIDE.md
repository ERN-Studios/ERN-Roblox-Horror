# Zyntra Flat - style guide (art director, 2026-10-05)

STYLE NAME: "Zyntra Flat". The UI should look like the same artist drew it as the 2026-10-01 product icons. That means flat fills, no gradients inside any element, thick rounded geometry, cream ink on charcoal, teal as the system colour, and exactly one warm, loud colour per card: the Robux price.

COLOUR ROLES (hex, sampled from the PNGs where marked):
- TILE #161D20: surface for cards, list rows, the detail pane and the hero. It is the baked ground of every product icon (measured #131A1D-#161D20), so ProductIcon sits on a card with no visible edge.
- WINDOW #0F1618 -> #090D0F: fill of ShopWindow_panel, a 2-stop vertical LINEAR UIGradient. This is the only gradient in the design.
- INK #05090B (measured ground of rail-shop / rail-upgrades): window stroke, currency pill fill, dock fill, nav icon tiles (the rail images sit seamlessly on it), and the Dim scrim at 50%.
- TILE_HI #1D262A: hover and selected fill, contents chips, unavailable buttons.
- LINE #263134: 3px card and row strokes. DIVIDER #1F2A2D: 4px rules.
- CREAM #F2EBDB (measured #F0E8D8-#F6F2E1): titles, product names, numerals, the close X, identity ribbons.
- SAGE #A7B8AE: benefit text, meta, inactive tab labels, status line. Contrast is about 8:1 on TILE.
- ICON TEAL #4BB4B0 (measured on the icons' token chip; #3FA9A6 is its dark edge): the brand voice and Research Tokens. Used for the token glyph, token price buttons, eyebrows and kind tags, section underbars, contents counts and the hero stroke.
- RAIL TEAL #44DDC4 (measured #40D8C8 on the rail icons): interaction STATE only. Used for the active tab stroke and underbar, the selected row stroke, OWNED and ACTIVE badges, the owned button and hover/focus strokes. Never decorative.
- AMBER #E8A024 (the Supporter star): ROBUX ONLY. Face of every Robux price button; stroke #9C6410, hard shadow #6B430B, hover #F5B53C.
- LIME #C4F06C (the glowstick): VALUE CLAIMS ONLY: BEST VALUE and SAVE R$ 149.
- CORAL #F2705F (the detector's top bar): the close button (stroke #B4473A, shadow #7E2F27) and notification dots only.
- OWNED_FILL #10292A: face of the owned button.
- Token button: face ICON TEAL, stroke #2D7774, shadow #1D4F4D, hover #5CC6C1.
- Detector orange #F0A83C stays inside the art and is not a chrome colour.

Why amber for Robux:
- Today's terminal already prints Robux prices in gold #FFCB4F.
- Amber is the icon family's "premium" mark.
- On a cool charcoal and teal screen it is the warmest colour, so it is the loudest.
- Robux (warm amber + "R$") and tokens (cool teal + chip glyph) can never be confused.

Bright teal vs muted teal: muted ICON TEAL means "Zyntra / tokens / information" and matches the icons' token chip exactly. Bright RAIL TEAL means "this is selected, owned or active" and matches the lobby rail buttons that players already tap.

TYPE (Figma font = Roblox font; px on the 1920x1080 artboard. Floor: 30px for mono caps tags, 32px for body, per the research brief; nothing below 30):
- Window title: Montserrat Black 64, CREAM, caps "ZYNTRA SHOP".
- Eyebrow, kind tag, section subtitle, ribbon, hook, button sub-label: Roboto Mono Bold 30, caps, letter-spacing +4%. Colour: ICON TEAL for eyebrows, SAGE for subtitles and hooks, or the ribbon's text colour.
- Section title: Montserrat Black 44 (40 in the L3 list), CREAM, caps.
- Hero and detail name: Montserrat Black 64-72, line-height 1.06, CREAM.
- Card name: Montserrat ExtraBold 34/40, CREAM, title case, max 2 lines (layer Name_txt). List rows: ExtraBold 32, single line (layer Name).
- Benefit: Montserrat SemiBold 32/38, SAGE, max 2 lines (Benefit_txt).
- Price on card buttons: Roboto Condensed Black 52 in TILE #161D20. It reads as cut-out ink, like the hole in the icon's token chip, and its heavy condensed numerals match the icons' "2x" and "+20".
- Hero and detail price: Roboto Condensed Black 72-80. Price chips in list rows: 44.
- OWNED / ACTIVE on buttons: Montserrat Black 40, RAIL TEAL.
- Tab label: Montserrat ExtraBold, caps. 34 on the rail and top tabs, 32 inline, 30 in the dock.
- Currency number: Roboto Condensed Black 56, CREAM.
- Contents counts: Roboto Condensed Black 44-48, ICON TEAL. Contents labels: Montserrat ExtraBold 32-34, CREAM.
- Status line: Montserrat SemiBold 32, SAGE.
- Close glyph: Montserrat Black 64 "X", CREAM.
- Text rules: no text strokes and no text gradients. A text layer is multi-line only if its name ends in _txt.

RADII (one uniform radius per node):
- Window 40.
- Hero, detail pane, Token Earner panel 32.
- Cards 28; list rows 24.
- ProductIcon 24 in cards (invisible, because ground = TILE) and 20 in rows.
- Nav icon tiles 20; buttons 20.
- Ribbons, chips, badges 12.
- Pills (token pill, dock): height/2.
- Close 28.

STROKES (solid, uniform, inside):
- Window: 6 INK.
- Cards and rows: 3 LINE.
- Hero / featured: 4 ICON TEAL.
- Active tab: 4 RAIL TEAL. Selected row or card: 6 RAIL TEAL.
- Price buttons: 4 in their deep shade. Owned button: 4 RAIL TEAL.
- Currency pill: 3 LINE.
- Dividers are 4px DIVIDER frames, not strokes.

SPACING: 8px grid. Window inner padding 40, gutters 24, card padding 16, section gap 32, section title to content 16. The header is 136 tall and ends in a 4px divider.

SIGNATURE MOTIF, the underbar. The token mark is a chip with a short bar under it, and the UI repeats that bar:
- 96x8 ICON TEAL under "ZYNTRA SHOP".
- 48x8 ICON TEAL under each section title.
- 8px RAIL TEAL along the inner bottom of the active tab (8x56 on the inner left edge in a vertical rail).
Nothing else is decorated.

CARD ANATOMY:
- Vertical tile (grids): Card_<Key> has TILE fill, radius 28, 3px LINE stroke, padding 16, vertical auto-layout with gap 12, centred. Children in order:
  1. Art (square). It holds ProductIcon as an IMAGE fill, FIT, radius 24, plus a Ribbon at top-left inset 10 and an OwnedBadge at top-right inset 10.
  2. Name_txt.
  3. Benefit_txt.
  4. BuySlot, full width, holding BuyShadow_shadow and Buy_button.
- Horizontal variant (shelves, small tiles, list rows): Art left, text column right, button at bottom-right.
- Owned cards keep full-colour art and their normal stroke. The state lives in the badge and the button.
- Selected: 6px RAIL TEAL stroke + TILE_HI fill. Hover (optional, one card per layout at most): 4px RAIL TEAL stroke.

PRICE BUTTONS (always at least 96px tall: 112 on cards, 128-144 on the hero and detail pane):
- ROBUX:
  - BuySlot = BuyShadow_shadow (same size, #6B430B, radius 20, offset y+8) + Buy_button (AMBER face, radius 20, 4px #9C6410 stroke) > Price "R$ 149" in Roboto Condensed Black 52, TILE colour.
  - "R$" is always text, never a Robux logo.
- ROBUX UPGRADE:
  - The same amber button with two stacked labels: "UPGRADE" (Roboto Mono Bold 30) over "R$ 150" (Roboto Condensed Black 48).
  - A LIME ribbon "SAVE R$ 149" sits on the art.
  - A SAGE meta line "WAS R$ 299" / "WAS R$ 399" sits above the button where the layout has room.
- TOKENS (Upgrades tab and the pill's +):
  - ICON TEAL face, 4px #2D7774 stroke, #1D4F4D shadow.
  - Contents: a TokenGlyph in TILE colour + the amount in Roboto Condensed Black 52, TILE colour.
  - Never amber, never "R$".
- OWNED:
  - No shadow. OWNED_FILL face, 4px RAIL TEAL stroke, "OWNED" in Montserrat Black 40, RAIL TEAL.
  - The layer keeps the name Buy_button so the game can bind and disable it.
- UNAVAILABLE / CHECKING PRICE: TILE_HI face, 3px LINE stroke, SAGE label in Montserrat ExtraBold 32.
- Pressed: hide the shadow and move the face down 8px.

TOKEN CHIP (native; never a coin):
- TokenGlyph, S wide:
  - TokenChip: an SxS frame with no fill, an inside stroke of round(0.16S) in ICON TEAL, radius round(0.22S).
  - TokenBar: an S x round(0.14S) ICON TEAL frame with square ends, placed 0.2S below the chip.
- Sizes: S=44 in the pill (stroke 7, radius 10, bar 44x6); S=32 in buttons (stroke 5, radius 7, bar 32x5).
- CURRENCY PILL (TokenPill): 456x112, INK fill, radius 56, 3px LINE stroke. Horizontal auto-layout, padding 16/12, gap 16. Children:
  1. TokenGlyph, S=44.
  2. TokenCount "37", Roboto Condensed Black 56, CREAM.
  3. TokenLabel "TOKENS", Roboto Mono Bold 30, SAGE.
  4. AddTokens_button: 96x96, ICON TEAL face, radius 20, with "+" in Montserrat Black 56, TILE colour.

CLOSE:
- CloseSlot 120x120 = CloseShadow_shadow (#7E2F27, radius 28, offset y+8) + Close_button_close (CORAL face, radius 28, 4px #B4473A stroke) > "X" in Montserrat Black 64, CREAM.
- Placed top-right of the window, 24px inset. The top-left stays free of tappables, because the Roblox Shop button sits there.

NAV ITEM (Tab_<Name>_tab:<Name>):
- A CategoryIcon tile (INK, radius 20; 80px on the rail and top tabs, 56 inline, 48 in the dock) + a Label.
- UPGRADES and SHOP tiles carry the rail-upgrades and rail-shop images.
- SKINS, DONATE and COLORS get native glyphs in the same tile:
  - SKINS: a gas-mask face. CREAM circle at 60% of the tile, two INK eye circles at 18% of the tile, a SAGE mouth bar.
  - DONATE: a coin over a box. AMBER circle at 25% of the tile above a CREAM box at 60x40% (radius 8) with an INK slot bar.
  - COLORS: three glowsticks. Rounded bars at 15x60% of the tile in RAIL TEAL, CORAL and LIME.
- Inactive: no fill, SAGE label. Active: TILE fill, 4px RAIL TEAL stroke, CREAM label, RAIL TEAL underbar.
- Every tab is at least 96 tall.

RIBBONS AND BADGES:
- Geometry: 48 tall, radius 12, horizontal padding 16, Roboto Mono Bold 30 caps, placed on the Art.
- Kinds:
  - Identity: "FEATURED BUNDLE", CREAM fill, TILE text, top-left.
  - Value: "BEST VALUE" and "SAVE R$ 149", LIME fill, TILE text, top-left.
  - State: "OWNED" and "ACTIVE", RAIL TEAL fill, TILE text, top-right.
  - Count: "1 STORED", TILE_HI fill, CREAM text.
- Nothing else. No POPULAR, no timers and no % OFF: none of them is true to the data.

BACKGROUND, in stacking order:
1. Backdrop_ignore: the yellow Backrooms lobby, heavily blurred. Mockup only; Framewisp skips it.
2. Dim: INK at 50%, a native frame. It is the in-game scrim.
3. WindowShadow_shadow: INK at 60%, radius 40, offset y+16.
4. ShopWindow_panel: the WINDOW gradient + a 6px INK stroke.
- No grain, glow, radial or image in the chrome. Each of those would cost a baked image.

IMAGE BUDGET: 13 of the free plan's 15 images.
- Used: the 11 product icons + rail-shop + rail-upgrades. Reusing one (for example product-emergency-reentry in the hero's contents) costs nothing.
- 2 slots stay spare for unforeseen bakes.
- Not used in this view: daily-*, wheel-disc, rail-rewards, rail-wheel, rail-music, supply-*, skin-*.