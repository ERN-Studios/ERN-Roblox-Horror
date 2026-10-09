# Level 5 — dark mycelium and mold decals

Three distinct transparent fungal textures generated with the built-in imagegen tool on 24 September 2026 (local time). Actual Studio Play verified loading and wall appearance for all three uploaded assets. All eight placements passed runtime QA with zero failures. Native publication as Roblox **v2036** is verified.

| Variant | File | Roblox asset ID | Size | Origin and spread |
| --- | --- | --- | --- | --- |
| Rising | level5-mold-rising-alpha.png | 111130507669211 | 1086 × 1448 | Dense lower edge, spreading upward and outward. |
| Corner | level5-mold-corner-alpha.png | 84997095468417 | 1448 × 1086 | Lower-left corner, spreading diagonally toward upper-right. |
| High seam | level5-mold-seam-alpha.png | 119550867817499 | 1254 × 1254 | High upper-right origin, spreading left and down. |

## Replacement scope

These variations now form eight verified patches anchored to different floors, corners and high wall seams. They replace all four previous tall house/stair drawing placements. The previous drawing IDs **114474831346440** and **108980796139348** are superseded for this wall treatment; retain their original files as historical provenance. Runtime QA verified zero old drawing asset references and zero old drawing attributes. Furniture and Level 4 are outside this replacement scope.

Keep the PNG alpha and each asset's proportions. The existing wall must remain visible through gaps and feathered edges. Place dense origins in contact with the intended floor/corner/seam. Do not add an opaque backing, light, glow or collision. Inspect translucent gray/olive fungal fringes on the actual wall so they blend as mold instead of resembling an attached sheet. Fresh Play QA confirmed all three asset loads, all eight placements and absence of old drawing instances. All 72 backing-wall rays passed; maximum measured wall gap was 0.1 studs.

## Alpha and provenance

Read-only Pillow inspection confirms RGBA with alpha 0–255 for all three files. Fully transparent pixels: rising **48.5110%**, corner **48.2631%**, high seam **42.9178%**. Partial alpha is preserved naturally; there is no baked rectangular background. Each selected PNG is byte-identical to its generated original. No alpha extraction, recoloring or other pixel editing was performed.

Exact prompts and generated source paths:

- Rising: `level5-mold-rising-alpha.prompt.md`; additional inspection in `level5-mold-rising-alpha.metadata.json`.
- Corner: `level5-mold-corner-generation.md`.
- High seam: `level5-mold-seam-alpha.prompt.txt`; source and inspection in `level5-mold-seam-alpha.provenance.json`.

`asset-manifest.json` records all IDs, content URLs, dimensions, byte counts, SHA-256 hashes, alpha measurements, source paths and verified runtime results.

The existing Level 5 Trello card tracks placement, visual QA and delivery separately from future gameplay.

## Verified runtime evidence

[Runtime report](../../../artifacts/level5-mold-20260924/runtime-qa.json) records Level5MoldRuntime version `2026-09-24.mold.1`: eight colonies, three variations, eight decals, 72/72 backing-wall rays, zero failures and zero old drawing references/attributes. ContentProvider checks separately confirmed all three ContentProvider loads succeeded in actual Play. The same structural pass preserves 20 furnished homes, 891 furniture parts, 7,128 checked furniture corners, 356 tinted windows and zero house lights/Neon. These checks do not claim physical multiplayer/mobile testing. Publication is separately confirmed below.

## Publication receipt

Verified native **File → Publish to Roblox** at **2026-09-23T23:05:12Z**, covering the expansion, furnishings and mold. Studio logs reported `PublishSuccessful`, `Published new changes`, `Place published` and `Add publish notes to v2036`. See [publication receipt](../../../artifacts/level5-mold-20260924/publication-v2036.json).
