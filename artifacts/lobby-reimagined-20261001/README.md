# Revised lobby — isolated Blender preview, October 1, 2026

The owner requested a Blender-built comparison lobby beside the authoritative current lobby, then added slowly spinning DJ records with visible pickup arms. The new preview uses black gate frames, projecting arrow signs, aged yellow tunnel walls, cable trays, furniture piles, orange queue rooms and a raised stage with independent festival speaker towers.

## Where to find it

Start Play in Studio, or join as an existing authorized preview developer. The preview is generated at **(220,30,-760)**, 220 studs to the side of the current lobby. It has a measured minimum 31.17-stud clearance from existing geometry. The preview name is `Workspace.LobbyReimaginedPreview`; it is deliberately generated per server and is not a persisted opaque-content model in Edit.

The saved place contains two owned raw Blender payload folders, four preview Sources and a Bootstrap that recreates session mesh/image content. The current lobby is preserved. Normal servers without a preview developer do not build the preview.

The bay's E prompt is explicitly **VISUAL DEMO · NO LEVEL LAUNCH**. It starts/cancels the teal ring and hollow cylinder that fades upward. Existing level launches, queues, purchases and party controls are not replaced. The copied shop artwork is inert. This is an isolated design preview, not the production lobby replacement.

## Assets and reproducibility

- Full editable source: [LobbyReimaginedPreview.blend](../../assets/models/lobby-reimagined-20261001/LobbyReimaginedPreview.blend).
- Downloadable geometry fallback: [LobbyReimaginedPreview.fbx](../../assets/models/lobby-reimagined-20261001/LobbyReimaginedPreview.fbx). It excludes native text, prompts, client animation and collision proxies.
- Final source Blend SHA256: `cef02885bc8b4aa34c3ca21d3d9eb3eac39fa257c67da1e5284a09d39dd10141`.
- Runtime manifest SHA256: `9e25ce55ccfd8aec36878770967c83f6b1eb72676f9c783c562b5864ab333c3c`.
- 34 reusable mesh families, 45,384 unique triangles; each mesh is below 20,000 triangles.
- 254 static placements total 153,004 triangles. The 24 queue rings and 240 gradient bands add 43,008, giving **196,012 total preview mesh triangles before the shop reference and native parts**. Most bands are invisible until a demo starts.
- One 1024×1024 color/wear atlas. Blender bottom-up pixels are converted to top-down rows by the runtime; mesh UV V is converted separately.
- The corrected FBX keeps only AtlasUV. A fresh Blender round-trip verified all 254 object placements within 0.0000153 stud, geometry, UVs, material indices and atlas image routes.
- Rebuild locally with Blender background/factory-startup and `tools/lobby_reimagined/build.py`, then run the separate `export_fbx_fallback.py` correction. See [IMPORT.md](../../tools/lobby_reimagined/IMPORT.md).

Do not run historical installers blindly. The initial v1/v2, pre-pile R2 and successful R2 installers pin their historical candidates. The final Builder received a separate Source/editor compare-and-swap for larger text canvases and warmer tunnel fill. Fresh Studio exports are the current authority.

## Verification

[Actual Play screenshots](play-verification/) show the tunnel, Level 3 gate, turntables and an active queue cylinder. They are separate from the five imagegen concepts in [concepts](concepts/); the complete prompts are in [imagegen-prompts.json](imagegen-prompts.json).

- Two fresh sessions built the preview in about 4 seconds; final observed build time was 4.28 seconds.
- Both records rotated about 12°/second, approximately 2 rpm, without moving their center axes. The pickup arms, cartridges, needles and console remain fixed.
- Reduced-motion behavior stopped the records and restored the test player's previous preference afterward.
- Actual E input activated the cylinder; cancel returned all bands to hidden. The authored auto-reset is 20 seconds; a later observation at 212.68 seconds confirmed idle/hidden, rather than measuring the exact transition.
- A real local avatar walked up the stage steps in Running state with health 100, reaching the deck without jumping. Independent 1,911 collision rays found no doorway floor gaps or final step/deck drops.
- Grounded furniture contacts and tower/roof clearances passed local geometry checks.
- All 205 existing Sources/classes remain unchanged; all 209 final Sources match their editor text. Only four new preview scripts and owned payload roots were added.
- Existing animation-permission and waiting-for-Level-6-remotes warnings appeared in Play; the preview produced no new runtime error.

These are single-client Studio and bounded geometry checks. Multiplayer and mobile performance are unverified. Background/raised-window Studio samples were about 14–15 render FPS and included the whole existing place; one sample reported 5,527 MB for the Studio client. A temporary client-only preview detach/reattach sample contained a transient pause, so it is not a valid isolated benchmark or evidence of a performance pass. The dev preview has not been certified as a production-performance replacement.

## Studio records and recovery

The whole-place native before/after captures, raw native bytes and reconstructed .rbxl files are preserved locally under native-before/ and native-after/. The after capture contains 70,151,801 raw bytes and 209 Sources, zero Source/editor conflicts, no skipped roots. Reconstruction has 29 service-property assignment limitations and 129 unreadable properties, plus two non-archivable engine Humanoid Status children; the raw joint native forest is retained. A source-only mirror is not claimed to represent the whole game.

The verified current four Sources, classes, paths and hashes are exported under verified-studio-source/. Scope audit records compare the original native forest and service properties against the fresh after capture.

Actual Claude Opus 5.5/max returned the queue/DJ design critique; Codex integrated and verified the implementation. Optional longer Claude review attempts timed out and are recorded as such. The installed CLI's highest exposed effort is max; no invented “ultra code” mode is claimed. See [Claude receipts](claude-review/) and [collaboration workflow](../../docs/CODEX_CLAUDE_WORKFLOW.md).

Roblox Creator Dashboard confirms current published version **2456** (previous published version2453). Publication evidence is recorded under publication/. The visible time is the saved version last-updated time, not a measured publish timestamp. A local commit and a cloud publish are separate. The repository has no configured Git remote; no GitHub push is inferred.
