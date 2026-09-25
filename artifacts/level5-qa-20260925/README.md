# Level 5 QA evidence — 25 September 2026

This folder records the developer map preview, not public campaign gameplay. See `../../docs/LEVEL5_QA_2026-09-25.md` for interpretation and testing limits.

- `before.rbxl` and `after.rbxl`: full native place backups before and after the three scoped Studio edits; exact hashes are in `../../studio-sync-manifest.json`.
- `final-*`: latest successful geometry, furnishing, source, compilation, canyon and arrow inspections. The arrow orientation was corrected after the earlier full geometry pass; it changes only non-queryable decorative carriers.
- `main-walk.json`: main-route physics traversal, including the disclosed harness-timeout adjustment.
- `optional-walk-before-stair-fix.json`: successful atrium, Pink House and exit-return traversal plus the original canyon failure; `final-canyon-walk.json` records the repaired full circuit.
- `Final_*.png`: latest visual views; other district images show unchanged areas. `DarkEndQA.png` records the contained dark arrival.
- `render-*.json`: one streamed Studio view per district, not mobile FPS benchmarks or whole-game memory measurements.
- `publication-v2104.json` and `publication-log.txt`: verified owner publication to the existing experience.

Native backups include pre-existing game content. No credentials, caches, temporary HTTP bridge, or test-only runtime Scripts are part of this commit.
