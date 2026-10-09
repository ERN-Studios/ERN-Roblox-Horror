Den kombinerede kandidat med tint er valideret offline 2026-10-09. Ingen runtimeændringer udført under denne kontrol.

Source-dir: `artifacts/character-models-level1-20261008/combined-tint-candidate`.

- `test_loading_marker.py --source-dir <source-dir>`: 40 lifecyclechecks. Alle fem mutationer fanges fortsat. Den faktiske `advancedHazmatColor` helper læses fra kandidaten; custom-colour-checken kræver nu, at den markerede gameplay-krop beholder den nye visual og sin valgte TintColor. Loading, brief, lobby, død/retur, previews, reentry, gatefejl, late-profile og watcher-oprydning testes uændret.
- `optional-tint/test_tint.py --source-dir <source-dir>`: 15 checks på faktisk helper, tintblok og refresh-cache. Den nye CLI-vælger source-dir før harnessen samles.
- `test_level2_newmap_feedback.py --source-dir <source-dir>`: 83 checks, inklusive 10 server skin-checks og 5 driverchecks. Den faktiske color-helper læses frem for en ubetinget false-fake. Color3-faken har nu R/G/B; de to nye checks kræver korrekt new-visual/custom-colour adfærd og authored default ved tilbagekaldt advanced ownership.
- `../collision-candidate/test_collision.py --source-dir <source-dir>`: 39 serverchecks + 39 klientchecks.
- Alle tre kombinerede scripts kompilerer Luau 0.737 med `--null -O0`.

I alt 216 Luau-checks passer på combined-tint, og 5/5 lifecyclemutationer fanges. WorldBuilder-exportens eksisterende Python-strukturkontroller passer også. De oprindelige isolerede kandidater passer fortsat marker40, tint15 og den opdaterede Level2-harness83.

`existing-test-minimal.diff` er regenereret. Den indeholder kun de relevante delte testændringer, uden artefaktets ROOT/source-dir-redirect eller argparse-blok. Ingen delt test, source, kø, lås eller Studio er ændret.

Asset-/texturefarvens visuelle kvalitet er fortsat ikke undersøgt; den kombinerede tint-kandidat skal stadig vælges efter faktisk asset-inspektion i Studio.
