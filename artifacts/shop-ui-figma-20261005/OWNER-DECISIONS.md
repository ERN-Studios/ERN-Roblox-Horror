# Owner decisions — shop UI (2026-10-05)

These override the earlier shared spec wherever they differ.

## Style
- Every proposal follows the current in-game shop icons ("Zyntra Flat", see STYLE-GUIDE.md).
- Four layouts are kept: L1 Field Catalogue, L2 Storefront Shelves, L3 Terminal Split, L4 Bento Home.

## Tools
- Image generation uses the owner's **Figma** AI credits, NOT Codex. Codex image jobs are stopped.
- Figma Weave first needs the owner to link the Figma account at app.weavy.ai.
- Until then, new art is drawn natively in Figma.

## SHOP tab (fewer items, bigger icons, scrolling)
The SHOP tab shows **6 products**:
- **Expedition Pack** R$ 69 (featured);
- **Zyntra Supporter** R$ 99;
- **Advanced Equipment** R$ 149;
- **Zyntra Entity Detector** R$ 149;
- **Token Earner 2x** R$ 149;
- **20 Research Tokens** R$ 149.

Removed from the SHOP tab. The products still exist; they are only hidden or moved:
- **Glowstick Customizer** is sold only in the **COLORS** tab, which is where it is used.
- **Emergency Re-entry** is sold in context only: the death modal, the PARTY DOWN card and inside Expedition Pack.
- **4 Research Tokens** is hidden. It is dominated by Supporter (see the pricing report).

**Token Earner:** only **2x** can be bought; **3x and 5x go away**, together with their upgrade products.
- Players who already own 3x or 5x MUST keep their multiplier, because the game code keeps honouring the passes.
- To stop web-store sales, the owner sets the 3x/5x passes and the upgrade products off-sale in the Creator Dashboard.

**Product art** gets 2-3x bigger.

**Scrolling:**
- L1 and L3 scroll vertically.
- L2 and L4 scroll horizontally (shelves).

## DONATE tab
Five tiers: **R$ 10 / 50 / 250 / 1,000 / 10,000**. The 100, 500 and 5,000 tiers and the 20K pass are hidden. Existing 20K owners keep their recognition.

## Lucky Wheel
- A brand-new wheel in the Zyntra Flat style.
- It keeps the six equal fields in config order, so it stays compatible with the Lucky Wheel Client: Token1 at 12 o'clock, then clockwise Token3, Potion1, Potion2, Shield1, Skin5.
- The server weights stay the odds: 40/20/20/5/10/5.

## Lobby menu buttons
- Brand-new buttons for every lobby button that opens a menu (SHOP, UPGRADES, REWARDS, WHEEL, MUSIC).
- Same style, with hover, pressed and badge states.
