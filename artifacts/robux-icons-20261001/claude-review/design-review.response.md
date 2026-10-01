**Verdict:** the direction is right, with three corrections. (a) Every supplied pass thumbnail is circle-masked while products are square, so "square composition" has to mean circle-safe. (b) Numerals should be composited as vectors, not generated. (c) The three-colour palette needs named exceptions.

## 1. Current-art audit

**Systemic**
- Gold metal frames or fills all 17 token and donation images; the read is casino medallion, not research facility.
- There are three unrelated token objects: pinned chip (Tokens4), stacked cube (Tokens20), glowing crate (earners). There is no canonical currency.
- There are four backgrounds: circle mask, white, grey fog, dark square. The fog on Tokens4, Re-entry, Field, Signal and Director looks like failed background removal.
- Up2to3 is the 3x image; Up2to5 and Up3to5 are both the 5x image. Three passes have no art of their own and never show the source tier.
- Every file is soft: vents, lightning and microtext are already mush at 420.
- Redraw only: Detector, Glowstick, Re-entry, 4 Tokens. Reconceive the rest.

**Per icon**

| Icon | Failure |
|---|---|
| Advanced Equipment | Respirator helmet; no torch, beam or stamina cue; purple arc; reads as a cosmetic mask |
| Glowstick Customizer | Best concept; smoke and arc waste a third of the frame; sticks too thin |
| Zyntra Supporter | Generic star rosette; shows neither the tag nor the 10 tokens |
| Entity Detector | Correct semantics (three level bars, no positions) but photoreal, cropped by the mask, yellow corridor, microtext: a style orphan |
| Emergency Re-entry | Door plus arrow works; red glow strips and fog; nothing says "unseen" |
| Expedition Pack | Hard case reads as a permanent kit; contents tiny; canisters read as lanterns, not markers; ornate lit ring |
| 4 Tokens | Countable; fog; chip matches nothing else |
| 20 Tokens | Five multi-layer stacks are uncountable at 52px; no numeral |
| Earner 2x | Numeral under half the width inside a gear medallion; lightning; side crates |
| Earner 3x | Three crates cover the medallion and imply "3 tokens" |
| Earner 5x | Five crates mirror Tokens20's five stacks, so a permanent rate reads as a pack |
| Upgrades ×3 | Duplicates, as above |

Detector and Expedition Pack were supplied only as marketplace images; their configured shop IDs are unreviewed.

## 2. Art direction

- **Canvas:** flat opaque graphite #16191C to all four edges. No alpha, fog, vignette, ring, floor or backdrop scene. Keep the subject inside a centred circle of 88% diameter and numerals inside the central 66% square, so masked passes and square products match.
- **Rendering:** front-on, hard-edged, two-tone flat shading. One subject, at most one secondary. Minimum stroke or gap is 4% of canvas (2px at 52). No glow, no metallic gold. The 420 version is the same drawing as the 52 version, not a more detailed one.
- **Palette roles:** ivory #E8E2D2 for subjects and numerals; teal #3F9E96 for the token core and powered accents (any greyer and it dies on graphite); amber #D4962E for arrows, change and consumables. Exceptions: glowstick tubes, skin suits, and one muted red detector bar only if the in-game readout uses red for HIGH.
- **Glyph grammar:** "N×" is a permanent rate; "+N" is a one-time grant; hollow numeral, chevron, solid numeral is an upgrade. Set in one heavy grotesque, ivory with a graphite outline, composited after generation. No words, logos or prices.
- **Canonical chip:** generate once and reuse the identical cutout in all nine chip icons: square body in lighter graphite #2F363B with an ivory keyline, three ivory pin teeth per side, one notched corner, flat teal core.

## 3. Utility briefs

Shared prefix: *flat graphite square, hard-edged two-tone, front view, no text, no glow, no frame.* Quoted glyphs are composited afterwards.

1. **Advanced Equipment** — Ivory handheld torch lower-left aimed upper-right; beam a long narrow ivory cone, at most 15° spread, reaching the safe-zone edge; amber double chevron by the grip for stamina. No helmet, no colour swatches.
2. **Glowstick Customizer** — Three thick capped glowsticks fanned from one base point; tubes flat teal, amber and a third hue taken from the real picker; ivory caps. No smoke, no arc.
3. **Zyntra Supporter** — Horizontal ivory name-tag plate with a punched hole and teal stripe, left blank; one chip overlapping lower-right with "+10". No star, ribbon or laurel.
4. **Entity Detector** — Whole upright handheld, uncropped, ivory keyline; screen holds three stacked bars widening upward (teal, amber, top bar in the HIGH colour); one round button. No dots, sweep, grid or crosshair.
5. **Emergency Re-entry** — Ivory open doorway; operative silhouette inside drawn as a dashed ivory outline; one thick amber U-turn arrow curving back into the opening.
6. **Expedition Pack** — Shallow open ivory tray from above with three compartments: the amber return arrow from #5, an ivory shield with teal core, three amber route arrows in a row. No case, latches or handle.
7. **4 Research Tokens** — Four chips in a 2×2 block on the left; "+4" on the right.
8. **20 Research Tokens** — One straight side-view chip stack on the left (about eight edges, not twenty); "+20" on the right. Single stack only.

Earner template: one chip centred as a backplate at 62% width; numeral over it; a five-slot gauge beneath.

9. **Earner 2×** — "2×"; slots 1–2 ivory.
10. **Earner 3×** — "3×"; slots 1–3 ivory.
11. **Earner 5×** — "5×"; all five ivory.
12. **Upgrade 2→3** — Hollow "2" at half size upper-left, amber chevron, solid "3×"; slots 1–2 ivory, slot 3 amber.
13. **Upgrade 2→5** — Hollow "2", chevron, solid "5×"; slots 1–2 ivory, 3–5 amber.
14. **Upgrade 3→5** — Hollow "3", chevron, solid "5×"; slots 1–3 ivory, 4–5 amber.

Packs use a split layout and earners a centred one, which separates grants from rates at silhouette level. One chip, never "+", and a gauge capped at five mean source and destination cannot be read as a sum.

## 4. Donations and skins

**Tier check.** Signal (arcs), Supply (hands), Field (hexagon), Research (orbit nodes) and Command (laurel) are distinguishable but form no ladder, so rank cannot be inferred. Director and 20K share the same eight-spoke ring. 5,000 and 10,000 are the same jewelled heart differing only by hue and spike count, both on white.

**Family brief.** One flat heart on graphite with thick bars beneath. No gold, gems, hands, laurels or chip: the chip is currency and donations grant nothing. Rank is a 3×3 grid:

- **Heart:** teal outline for 10/50/100; solid teal for 250/500/1,000; solid ivory for 5,000/10,000/20K.
- **Bars:** one, two or three within each group, in ivory.
- **20K:** its three bars are amber, marking the one-time pass.

No numerals: the top three names are prices.

**Skins.** The configured IDs (122113892663451, 120474289726445) returned placeholders, so there is nothing to review; check what they resolve to. The marketplace portraits show the right subject, weakly: soft, a drawn coloured ring, shoulders clipped. Static Wraith's hood merges into the violet disc; False Sun's lower third is a flat pale band.

Do not text-generate the suits. Start from a fresh capture of each real outfit and change only crop, lighting and background: head and shoulders, mask centred, head at least 55% of canvas height, flat graphite, no ring. The capture, not this description, is the authority.

- **False Sun:** keep the ivory hooded suit with its faint line pattern, black respirator, amber lenses and dark straps.
- **Static Wraith:** keep the dark violet-blue speckled suit, grey respirator and violet lenses; add a thin cool rim light to separate the hood.

## 5. Acceptance criteria

1. **Legibility:** at 52×52 in greyscale, numeral cap height is at least 40% of canvas on earners and 35% on packs, and no stroke or gap is under 2px.
2. **Mask safety:** a full-diameter circular mask removes no subject pixels, and the unmasked square shows flat graphite on all four edges with no alpha, white or fog.
3. **Palette:** outside the three named exceptions, every non-graphite pixel is ivory, teal or amber; no gold gradients, glow or purple.
4. **Semantics:** "×" appears only on the six earners and "+" only on Tokens4, Tokens20 and Supporter; each upgrade shows a hollow source smaller than a solid destination with exactly one chip; no prices, words or pseudo-text; the detector has no dots, sweep or map.
5. **Uniqueness and fidelity:** a tester matches all 25 thumbnails at 52px to their product names with zero errors and sorts the nine donations into price order from the images alone; each skin portrait overlaid on its in-game capture shows unchanged suit colour, pattern, mask, lens colour and straps.
