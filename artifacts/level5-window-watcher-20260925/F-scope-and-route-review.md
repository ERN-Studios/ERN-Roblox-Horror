# Window Watcher courts — independent scope and route review

Read-only comparison of the native `BASELINE-*` and `FINAL-*` zone exports captured during this task. No Studio, source patch, Git or Trello changes were made by this review.

## Unaffected zones

All seven unaffected zones **A–E, G and H match exactly** for the exported properties. Each encoded JSON row was parsed, object keys canonicalized, signed zero normalized, and the complete multiset sorted without rounding or deduplicating. Chunk offsets and declared row counts were verified before comparison.

| Zone | Baseline/final signature rows | Result |
| --- | ---: | --- |
| A — Balcony Atrium | 1,259 / 1,259 | Exact |
| B — Low Eaves Arcade | 584 / 584 | Exact |
| C — Pastel Village | 1,671 / 1,671 | Exact |
| D — Floral Terraces | 1,452 / 1,452 | Exact |
| E — Domestic Labyrinth | 708 / 708 | Exact |
| G — Tilted Subdivision | 1,566 / 1,566 | Exact |
| H — Last House | 266 / 266 | Exact |

F changes from 5,334 to 4,708 signature rows. The separate MyceliumWallGrowth model changes exactly three carrier rows: CanyonRearRising, CanyonWestRising and CanyonUpperSeam. Its other five colonies and every decal row remain unchanged. These three intended changes fit F's lower ceiling.

The comparison covers the exported geometry/material/collision fields, model paths, decal fields and light fields. It does not claim equality for Roblox properties or attributes omitted by the exporter. Hashes and exact changed mold rows are in [zone-comparison-canonical.json](zone-comparison-canonical.json).

## F route obstruction review

The actual final export contains 3,337 collidable parts. A bounded offline check sampled 42 flat routes: 14 court/balcony/landing/porch approaches and 28 open-house entrance lanes derived from their actual InteriorCarpet transforms. It performed 3,296 foot-position samples and 16,480 sphere-to-oriented-box checks. **No obstruction candidates were found.**

Covered routes include both x=0 ground thresholds and the dogleg through the three courts, both upper balcony lanes and their bridge, the lower bridge, both switchback landing turns, the near watcher approach, and the hero/middle-house porch entries. The explicit bridge rail gaps align with the porch paths. House door lanes include the two retained furnished canyon rooms and the reading room.

The model uses five radius-0.9 spheres from 0.95 to 5.0 studs above the authored floor, sampled at intervals no greater than 0.4 stud. Part, WedgePart and MeshPart geometry is conservatively represented by its exported oriented bounding box. Stair slopes, step negotiation, foot support, wider avatars and live Humanoid behavior are not established by this check; the parent is running native traversal separately. This is a bounded obstruction review, not a replacement for that native test.

Detailed route counts and limitations are in [F-route-collider-review.json](F-route-collider-review.json). There are no patch recommendations from this inspection.
