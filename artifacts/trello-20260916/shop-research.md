# Shop research — Trello #102, terminal half (A-SHOP-UI)

Fetched 2026-09-16 with WebFetch/WebSearch. Primary sources only: Roblox Creator
Documentation, Nielsen Norman Group, W3C WCAG 2.2, Android developer docs. Apple's
HIG pages render client-side and returned title-only through WebFetch, so the 44 pt
figure is NOT cited from Apple here — WCAG 2.5.5 and Android 48 dp carry that claim
instead, and the terminal's existing 44 px floor already sits between them.

Each finding says what it changed in `ZyntraStore.LocalScript.lua`. Findings that
changed nothing are not listed; there is no filler here.

---

## Findings

**1. A shop is a destination, not a dialog.**
<https://create.roblox.com/docs/production/game-design/monetization-foundations>
Roblox asks for a shop players can "linger and browse", "effectively integrated
within the experience" and consistent with the rest of the UI.
→ The pointer design size goes 840x610 → 1180x760. The panel is still clamped inside
`UIDevice.Layout().ModalViewport`, so a small laptop gets a proportionally smaller
panel with the same composition rather than a cropped big one.

**2. Item detail needs surrounding context so a player can compare value.**
(same page) "accurate and truthful in your descriptions" so customers "know exactly
what they're buying and the value it provides."
→ The Shop tab on the pointer tier becomes a list + DETAIL browser. The detail pane
states the kind, the live price, and a WHAT YOU GET bullet list split out of the
existing `Description` — no new copy was invented, the authored description is
re-rendered as scannable lines.

**3. E-commerce product pages must carry name, recognisable image, enlarged view,
price.** <https://www.nngroup.com/articles/ecommerce-product-pages/>
NN/g's must-have list is exactly those four, plus availability state and a concise
description.
→ The detail pane draws the same `IconId` image at 128 px (against 76 px in the
card list), the product name at 30 px, an OWNED/price line, and the description.
Availability is the existing OWNED state, which also takes BUY out of the input stack.

**4. Vital detail goes first, because users skim.** (same NN/g article)
"users typically skim text when reading online", so vital details belong at the
beginning.
→ The WHAT YOU GET list splits `Description` on ". " and draws each sentence as its
own bulleted row, longest-first order untouched (authored order is kept — reordering
would change meaning).

**5. Split view beats full-page navigation for browsing a small set.**
<https://create.roblox.com/docs/production/game-design/ui-ux-design> ("reveal
additional menu items only after selection, preventing screen clutter") plus
Material's list-detail canonical layout, which pairs a list pane with a detail pane
once the window is wide enough.
→ Two panes only at the pointer tier and only while `ContentWidth >= 760`; below
that the Shop tab keeps exactly the scrolling card list it has today. A phone never
sees a 300 px detail pane squeezed beside a 300 px list.

**6. Minimum touch target: 48 dp × 48 dp, "larger is even better".**
<https://developer.android.com/guide/topics/ui/accessibility/apps>
**WCAG 2.2 SC 2.5.8 (AA)** puts the floor at 24 × 24 CSS px and points at SC 2.5.5
(AAA) for important controls.
<https://www.w3.org/WAI/WCAG22/Understanding/target-size-minimum.html>
→ The terminal's existing published floor (`TerminalTapFloor`, 44 on touch) is kept
as the floor for every new action: the two FIELD SUPPLIES buttons and the detail
pane's BUY. Nothing new draws under it, and no new type is under 11 px.

**7. Mobile reserves the bottom corners and rewards thumb-reachable controls.**
<https://create.roblox.com/docs/ui/cross-platform-design> — the bottom-left and
bottom-right are the engine's own control zones; buttons 40% from the top of a phone
are nearly unreachable on a tablet.
→ No new touch tier gets a second pane, and the touch tiers' BUY row stays where it
is (bottom of the card, inside a scroll). The detail pane is pointer-only, where
there is a cursor and no reserved corner.

**8. Positioning by Scale is the common approach — but not here.** (same page)
Scale is a percentage of the container.
→ Deliberately NOT adopted: the terminal is offset-positioned on purpose, because
the Studio viewport override renders at the real window size and a scale-positioned
panel would measure against a screen that is not the one under test (the note above
`applyTerminalLayout` says so). The new geometry keeps offsets.

**9. Hierarchy: headers larger and bolder than body; group by proximity; use
conventions for unavailable items.**
<https://create.roblox.com/docs/production/game-design/ui-ux-design>
→ FIELD SUPPLIES is a named group heading above its two cards on the Upgrades tab,
not two more anonymous cards in the same grid. Unavailable/pending states keep the
project's existing convention: the button keeps its rectangle, states the reason
("SAVING...") and leaves the input stack via `UIDevice.SetEnabled`.

**10. Feedback for every action.** (same page) — "purchase sounds", button colour
changes; missing feedback leaves players unsure whether anything happened.
→ The supplies buttons latch to "SAVING..." on press and stay latched until the next
profile push re-renders the readout, so a slow DataStore write cannot look like a
dead button. A latch that never clears is the failure mode, so it also clears on any
push and on a 6 s timeout.

**11. Thumbnails must be big enough to be recognisable, and not so big the text is
squeezed.** <https://www.nngroup.com/articles/mobile-list-thumbnail/>
"if the thumbnail is too small, it will no longer be recognizable and useful", but an
oversized one truncates the copy.
→ Icon ladder is unchanged where the copy shares the row (52/64/76 px, pinned by
`test_zyntra_store_compact.py`). The 128 px icon only exists in the detail pane,
where it has a column to itself.

**12. Prices must be read live, not hardcoded.**
<https://create.roblox.com/docs/production/monetization/game-passes> — "Use
GetProductInfo() to retrieve information about a pass, like name and price, and then
to display that pass to users."
→ The detail pane reuses `displayedProductPrices`, which the existing per-card
`GetProductInfo` task already fills. No second fetch was added — one price read per
product per session, and the detail pane carries the line "Prices are read live from
Roblox" so a player who sees a different number in the Robux prompt knows why.

**13. Transparency: no pressure, no manufactured urgency.**
<https://create.roblox.com/docs/production/monetization> — discounts "must be genuine
and fair", users "must never be misled, confused, or pressured".
→ Nothing here adds a countdown, a fake sale, a "limited" badge or a rotating offer.
The owner's brief forbids new products and price changes and this redesign adds
neither; the only new BUY paths are the two token items the owner approved.

---

## Design decisions taken from the above

| Decision | Source | Note |
|---|---|---|
| Pointer design 1180x760 (was 840x610) | 1 | clamped to ModalViewport; laptops shrink, composition holds |
| Shop = list + detail at pointer, cards on touch | 2, 5, 7 | one breakpoint, `ContentWidth >= 760` |
| Detail icon 128 px, list icons unchanged | 3, 11 | the big image has its own column |
| WHAT YOU GET from the authored Description | 2, 4 | split on ". ", no new copy |
| One BUY path (`productPurchase[key]`) | — | existing rule from card 88; the detail pane calls the same function |
| Live price via `displayedProductPrices` | 12 | no second GetProductInfo |
| Every new action at `TerminalTapFloor` | 6 | 44 on touch, 32 pointer |
| FIELD SUPPLIES as a named group | 9 | proximity grouping, not more anonymous cards |
| "SAVING..." latch on a pending buy | 10 | clears on push or after 6 s |
| No urgency, no sale, no new products | 13 | owner brief agrees |

## What research did NOT support, and was therefore not built

- **Rotating / featured stock.** Roblox recommends it (finding 1: "introduce new
  items regularly"), and it is out of scope: the owner's brief forbids new products
  and new monetization. Noted for a later card, not implemented.
- **Personalised item ordering.** Roblox's monetization docs push personalised
  stores; that needs server-side analytics this project does not have, and would
  make the fit matrix's card order non-deterministic. Rejected.
- **Multiple images per product** (NN/g finding 3 asks for "enlarged view(s)").
  There is exactly one `IconId` per catalogue item. The detail pane enlarges the one
  that exists rather than inventing a gallery of placeholders.
