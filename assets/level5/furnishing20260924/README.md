# Level 5 furniture textures and transparent wall drawings

Generated on 24 September 2026 with the built-in imagegen tool. These are usable raster texture assets, not model exports or concept substitutes. The original generated files remain under the Codex generated-images directory.

| Asset | Roblox asset ID | Dimensions | Intended use |
| --- | --- | --- | --- |
| level5-woven-upholstery.png | 83212354768208 — superseded after runtime Failure | 1254 × 1254 | Original preserved for provenance; do not use as a working runtime reference. |
| level5-woven-upholstery-v2.png | 132119936960491 — load and visual verified | 1254 × 1254 | Verified active oatmeal/sage broken-twill fabric on physical sofa/chair cushions. |
| level5-crt-front-panel.png | 129933596500815 | 1448 × 1086 (4:3) | Front fascia of a separate 3D CRT cabinet; unlit screen, two right-side knobs and vent. |
| level5-house-mural-alpha.png | 114474831346440 | 724 × 2172 (1:3) | Aged, tall drawing of stacked outlined houses, stairs, ladders and arrows on an existing large wall. |
| level5-stair-mural-alpha.png | 108980796139348 | 724 × 2172 (1:3) | Sparse impossible-stair lines in semi-transparent black on an existing light wall. |

Uploads and IDs were reported by the parent agent. File dimensions, hashes and mural alpha statistics were independently checked locally. See `asset-manifest.json` for machine-readable metadata and verification scope.

## Inspection

Both furniture textures were visually inspected directly after generation. Upholstery contains only uniform continuous fabric detail without objects, text, borders or large directional shadows. Its prompt requests seamless repetition; exact pixel-periodicity has not been measured. Check repetition at the selected in-game tile scale. A small tile size around 1.5–2 studs is a useful starting point; choose by the cushion's rendered appearance.

The CRT panel is a strict frontal crop, with no visible cabinet sides, surrounding scene, text or logos. Its screen is dark and unlit, without RGB noise or static. Subtle glass curvature is part of the image. Keep the mapped surface non-emissive and give the television physical cabinet depth; do not use the image as a standalone flat television.

The furniture PNGs are byte-for-byte copies of their generated originals. The two mural PNGs were supplied already prepared by the parent agent; this metadata task did not modify any image pixels.

## Transparent mural inspection and usage

- House mural: alpha **0–250**, **57.261%** of pixels fully transparent. Its tall aged house-tower composition was visible in the local preview.
- Stair mural: every RGB channel is **0**; alpha **0–130**, **77.650%** of pixels fully transparent. Its black lines cannot be assessed against the image viewer's black background. The parent subsequently verified both murals loading successfully and looking correct on the actual light walls in Play screenshots, including this black stair drawing.
- Preserve PNG alpha and the 1:3 artwork proportions. Apply onto an existing wall with no visible rectangular backing, emission or separate scene background. Transparent regions must reveal the wall beneath.
- Check both artworks close up and from normal walking distance for seams, clipping, overlap, legibility and unwanted rectangular edges. Local alpha inspection is not a substitute for this Studio check.

## Provenance

Prompts: IMAGEGEN_PROMPTS.md. Furniture prompts are exact. Mural entries are explicitly labeled summaries because their exact generation calls were not supplied to this agent.

- Upholstery original: /Users/zeanjuul4/.codex/generated_images/01a0cfe1-440b-79e2-acb9-8e509ddf6a64/exec-e7f8d337-9dbd-4366-a18e-9b41a013a9ce.png
  - SHA-256: 7df9d762bb4aaab6b10be097d5b5eddbb0c8f7ae2f7b6a9c08548ae28424dc8a
- CRT original: /Users/zeanjuul4/.codex/generated_images/01a0cfe1-440b-79e2-acb9-8e509ddf6a64/exec-8a09dddd-f37d-4216-88f2-c5d09c4b46c8.png
  - SHA-256: 218c65dbea3cf92d13330f4c45658e5611d14c3752ec05080563475007a06c1b

The parent agent supplied the four original uploaded IDs. This metadata task did not operate Studio or stage/commit Git changes. The first five furnishing/drawing QA items on the existing Level 5 Trello card are now complete based on parent verification. The delivery item remains unchecked; no publication is claimed.

## Runtime delivery investigation and replacement

On 24 September, the parent verified actual Play ContentProvider Success for the CRT and both murals, but Failure for upholstery 83212354768208. Re-uploading the identical PNG returned the same failing ID.

Read-only unauthenticated public AssetDelivery checks returned authentication-required errors for both failed upholstery and working CRT; both public thumbnails reported Pending. These public responses cannot diagnose the runtime difference, and do not establish moderation rejection.

A visually distinct replacement was generated with built-in imagegen and inspected: `level5-woven-upholstery-v2.png`, a fine low-contrast oatmeal/sage broken-twill weave. It is a byte-for-byte copy of its new generated original; v1 pixels remain unchanged. The parent uploaded v2 as **132119936960491**. Final actual fresh Play ContentProvider validation returned **Success** for v2, and the final screenshot visibly shows the woven fabric on cushions. The CRT and both murals also loaded successfully and looked correct in actual Play screenshots. All four active assets are verified for runtime loading and appearance.

Parent Studio logs identified content representation generation followed by CDN timeouts for v1; no moderation rejection was established.

- Generated original: /Users/zeanjuul4/.codex/generated_images/01a0cfe1-440b-79e2-acb9-8e509ddf6a64/exec-8fdca27a-fc26-4141-b073-8b47ec8ba185.png
- SHA-256: cb946ce20fa8e663b2c53a60702f1e8c88c3f7bea033aa53f75e5cbeea1634e8
- 1254 × 1254 pixels, 3,276,830 bytes. Exact prompt is recorded in IMAGEGEN_PROMPTS.md.
- In-game tile scale and woven appearance were visually verified on the actual cushions. Exact mathematical pixel periodicity has not been measured.

## Final runtime verification scope

Parent-reported actual Studio QA on 24 September: all 20 furnished homes, 891 furniture parts, 7,128 corner checks and zero structural failures. Six representative rooms passed all 17 traversal targets. The runtime contained 356 tinted glass windows, four placed murals and 11,900 world parts; furnished house interiors had zero lights and zero Neon parts. This is bounded structural and representative traversal evidence, not a claim that every interior was manually walked or physical multiplayer/mobile performance was tested. Publication remains pending.
