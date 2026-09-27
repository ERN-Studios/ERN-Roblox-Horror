# Claude Opus 5.5 Level 5 review — 2026-09-27

CLI command requested `--model opus --effort medium`; result metadata reports canonical model `claude-opus-5-5` and `is_error=false`. Read-only review, no Studio or repository write by Claude. Original user screenshots were unavailable as local files.

# Level 5 read-only review: sections 01, 02, 05, 08, 09

I didn't edit any files. I read the pass request, brief, reference spec, both gap audits, the proposal QA notes, the section 01 and 09 build plans, the fall-audit draft, both unapplied diffs and the local Facades, Anomalies and Gallery source.

**Images:** I did inspect the image bytes for `gallery-proposal-ref02-before-gapfix`, `-ref02-gapfix-carpet`, `-ref05`, `-ref05-closer`, `-ref05-revised` (untracked), `-ref08`, and `gallery-current-ref01`, `-ref08`, `-ref09`. The ten original screenshots aren't in this checkout, so nothing below is a comparison against them. Line numbers refer to the **local** modules, which already contain the unapplied 02/05/08 drafts.

## 1. Code and collision errors (cheap, fix first)

| # | Section | Problem | Evidence | Fix and instance cost |
|---|---|---|---|---|
| A | 08 | At walkway height (`y == TOP` = 24), the `TinyBalcony` slab's top sits 0.005 studs below the carpet, so the two surfaces will flicker. Its rail and three posts stand on the walkway, 5 studs out from the wall, and don't collide. | Anomalies 1227–1235. These are the loose white hurdles on the carpet in `gallery-proposal-ref08.jpg`, plus the stray rail at bottom-left. | Skip the balcony block when `y == TOP`. Saves about 50. |
| B | 05 | The rounded balcony deck and the straight balcony slab share the same top and bottom surfaces where they overlap (about x 44–50, z 55–67). The low camera sees their undersides flicker. | 290 vs 298–300 | Make the deck 1.1 thick, or offset it 0.05 studs. Costs 0. |
| C | 09 | Same problem: the rounded end-balcony discs and the straight balcony slabs share surfaces around z 57–93 on every level. | 631 vs 645–647 | Same fix. Costs 0. |
| D | 02 | There's no floor inside the open near-left doorway or the five right-hand recesses. The dark back walls start at y=0, but sight lines through the bottom of each opening pass below them. This is the light gray still visible at the bottom of the dark doorway in the gap-fix capture. | Facades 711, 625; the carpet only spans x ±6 (551) | Extend both dark back-wall parts down to about y −6 (costs 0), or add one dark floor part per recess. |
| E | 08 | The pit floor only covers \|x\| < 28, so nothing closes the space under the two walkways. The blue area past the rails in both 08 captures is most likely sky leaking through. This is a hypothesis to check in Studio. | 1177 | Widen `DeepAtriumFloor` to the full width W. Costs 0. |
| F | 08 | The `AcrossVoidStairStack` sits at x −40, under the far walkway rather than in the open drop, so it's mostly hidden. `OppositeGallery` slabs (x 27–43) stick 1 stud into the drop and float about 37 studs from any apartment door. | 1239–1254 | Move the stairs to about x −(EDGE−5). Join the galleries to the wall, or move them next to it. |
| G | 09 | The one-part `RecessedWindowBand` per level is `M.Glass`, so it mirrors the Edit sky as blue stripes. | 630 | Switch to a dark matte material. Costs 0. |
| H | 02 | By my count, section 02 sits exactly at its 350-descendant budget (`VIEW2_BUDGET`, line 13). Any addition will trigger a warning. Check the `GeneratedDescendants` attribute to confirm. | — | Free space first (see section 02 below). |
| I | 02 + Gallery | The gallery build asserts `hiddenTiles == 40 and creamSiding == 3` (Rework Gallery 172). Removing the 40 hidden carpet tiles, or renaming or recoloring the near beige `SidingWall` parts, will break the gallery build. | — | Change the Facades builder and that assert together. |
| J | 05 | The stair flights and landings collide, but the balcony slabs they lead to don't, and there's a 1-stud gap with no guard on the balcony side. This only matters once the section is integrated into the playable route. | 388–407 vs 290 | Record it for integration. |

**Minor issues:**
- **Section 05:** the right tower's round mass, deck and rail extend into the court side wall at x = 100 (they reach x 102.5–103.8). This is hidden.
- **Section 09:** the `i <= 3` check (line 691) is always true, so it does nothing.
- **Section 08:** the ceiling grid (`-72..72`) and light positions (`±54`) are hard-coded. They'll poke through the walls if W is reduced, so derive them from W first.

## 2. Priority plan

**Section 08: fix the framing before adding detail.**
- **Why the carpet dominates:** the camera aims at x 44 (the middle of a 52-stud walkway) and 11° downward.
- **Camera:** try a position around `V(66, TOP+5.5, 70)` aimed at `V(22, TOP+3, 140)`.
- **Walkway width:** narrow it to about 28–34 studs by reducing W while keeping EDGE 28. This keeps the drop the same width but brings the apartment fronts closer to the rail. Derive the ceiling grid, lights, waypoints and camera x from W as part of this change.
- **Funding:** simplify the fronts below the walkway (y 0 and 12). Removing their door insets, casings and balcony posts frees about 200 instances.
- **Spending:** use the freed instances on connected landings or rails across the drop and on 2–3 apartment rows on the blank `RearAtriumWall`. The net cost is roughly +50.

**Section 05: composition.**
- **Symmetry:** the reference camera sits at x = 0 between towers at ±50, so the view is mirrored by construction. Move the camera to around x −10 to −14 and aim at the middle of the slope before changing any geometry.
- **Houses:** the fronts are flat WoodPlanks. Add 3–4 siding strips per front and give each house a different window count. That's about +40.
- **Captures:** the 05 captures are 894×670, so they can't be compared against the other captures or a portrait crop.

**Section 01: fund the plan by cutting, not by raising the cap.**
- **Where the instances are:** the two side towers cost about 900 of the roughly 1,738. About 450 of that is balusters (14 and 15 per floor at 13-stud spacing, lines 487–497), and at this distance they read as the uniform stripes the audit complains about.
- **Cut:** keep balusters on floors 0–2 only and use `TOWER_BAND_STYLE` above. That frees about 360.
- **Distant houses:** give the far two houses a simple mode without siding, mullions or porch rails. That frees about 140.
- **Distant towers:** add a cheap `addBalconyTower` mode with one recess strip, one slab and two band rails per floor. That's about 4 parts per floor, so three staggered towers cost about 150 instead of about 350.
- **Result:** this fits the draft plan's 1,800 allocation.

**Section 09:** follow `section09-build-plan-draft.md`, applying fixes C and G first.
- **Rail posts:** limit the new posts to the lower 8 levels of the near run (z 18–228). That's about 130–150 instances, versus 288 if every level gets them.
- **Sparse parts:** remove the single `LongRunRailPost` and `DistantWindowBayPier` parts, which frees 54.
- **Lighting:** don't grade colors on this capture yet. Its dark ceiling color (34,33,31) renders navy, so the blue cast comes from Edit-mode lighting, not the materials.

**Section 02:**
- **Free budget:** replace the 40 always-hidden carpet tiles with the textured carpet base, and update assert I at the same time. That frees 40.
- **Right openings:** darken the right recess back walls. The current `towerRecess` (150,144,130) reads as a flat light gray.
- **Ceiling:** add the uneven dark ceiling bays.
- **Camera:** the new camera turns 12° left, which moves the vanishing point right of center. The written spec can't confirm whether the reference view is oblique.

**DEV gallery and playable route:** none of this touches Architecture, `Level5PreviewAccess` or the playable route. The only shared piece is Gallery's texture pass (assert I). As the brief requires, re-read the Studio Source and editor source and compare checksums before any live write.

## 3. Where the evidence can't support a 1:1 call

- **Tower asymmetry (05) and corridor yaw (02):** the written spec doesn't say which tower is nearer or whether the corridor is viewed head-on or at an angle.
- **Counts:** bay, level and bridge-height counts for 01, 05, 08 and 09 aren't in the spec.
- **Palette and warmth:** every capture has the cool Edit-mode lighting, so color and warmth can't be judged until you capture in Play.
- **Aspect ratio:** the captures are 1920×1076, 1677×1080 and 894×670 landscape, while the references are portrait, so no crop comparison is valid.
- **Collision and navigation:** every item above still needs to be checked separately in Play.
