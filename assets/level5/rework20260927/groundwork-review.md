# Level 5 reference groundwork review — 2026-09-27

## Status and provenance

The ten supplied screenshots are ten distinct visual section requirements. `reference-spec.md` records their visible elements. The original pixel files are not available in the checkout, so dimensions and matched-camera overlays remain unmeasured. The in-chat images are the visual source; the social-media and phone overlays are not scene geometry.

Claude CLI version 2.1.283 was authenticated and invoked with `--model opus --effort medium --output-format json`; its JSON metadata identified `claude-opus-5-5`. Claude produced the initial facade module for views 1–4 and anomaly builders for views 5, 6, 7 and 9. Corrective edits to the corridor, camera-facing towers and structural openings followed code review. Views 8 and 10 were completed manually after Claude CLI returned HTTP 429 session-limit errors. No lower Claude model was substituted. Authorship of an initial draft does not certify reference fidelity.

`ServerScriptService/Level 5 Systems/Level 5 Reference Facades.ModuleScript.lua` and `Level 5 Reference Anomalies.ModuleScript.lua` are **standalone, uninstalled drafts**. Neither the live `Level 5 Architecture` builder nor the DEV preview currently requires them. Installing them as overlays would leave the old mismatched buildings visible.

The pale clapboard texture in `textures/clapboard-cream-v1.png` was generated and then refined with ChatGPT image gen. It is a candidate only; it is not uploaded to Roblox or assigned to a live surface. See `textures/README.md` for the generation brief and limits.

## Isolated geometry checks

In Studio Edit, each draft module compiled with `loadstring` and loaded without changing a live instance. Each builder was then called with an unparented temporary Model and an Architecture-compatible test kit; the temporary Model was destroyed before the command returned. Descendant counts matched builder-reported totals. This checks Luau execution and generated structure, not rendering, gameplay, navigation or visual fidelity.

| Reference | Draft builder | Measured descendants | Current strict QA |
| --- | --- | ---: | --- |
| 1 | Courtyard | 180 | One simplified cottage and one short tower wall; missing the planted path/cottage row and vertical canyon depth. |
| 2 | Corridor | 335 | Real segmented openings, 40 alternating carpet tiles, ceiling grid and six warm sconces; still needs matched-perspective and facade-by-facade comparison. |
| 3 | Bright atrium | 144 | One cottage and simplified apartment/tower masses; missing a varied foreground house row and detailed stair stacks. |
| 4 | Tower canyon | 131 | One house and simplified shafts; missing dense domestic frontage and repeated recessed tower balconies. |
| 5 | Sloped houses | 708 | Front-facing arched/gridded tower bays and wrapped balcony cues now exist; pitch, curvature, stair connections and scale are unrendered. |
| 6 | Gabled lawn | 513 | Dense frontage and black pocket exist in draft; repeated rooflets/porches still need section-specific facade counts and matched visual QA. |
| 7 | Stair cutaway | 310 | Openings now have real voids between piers/lintels; torn edge and staircase still need rendering and avatar route checks. |
| 8 | Upper walkway | 576 | Manual draft; broad ledge and cross-atrium relationships are unrendered and unwalked. |
| 9 | Skybridge canyon | 463 | Bridges and balcony bands are approximated; upper circulation is tagged unwired and the rounded plan profile needs remodeling. |
| 10 | Empty room | 131 | Manual draft; openings, ceiling and window view are unrendered against the reference. |

The drafts total **3,491 descendants**. The current live architecture builds **27,472 descendants** after the scoped F-window optimization; a naive overlay would reach approximately **30,963**, before preview-owned instances, above the 30,000 descendant cap. Integration must replace old scene geometry while preserving playable route, puzzle anchors, Window Watcher glass and reset behavior. The existing eight gameplay zones and gates need a reviewed mapping to ten separate visual subsections; changing zone count blindly would break progression contracts.

## Live Studio and preview

The live Studio Edit state has `Level5PreviewAccess`, a server-gated DEV preview entered from `Level5SealedDoor`, and two native F-window trim UnionOperations. `studio-manifest.md` records the exact live source/editor/mirror hashes and template properties. An authorized developer entered the static preview and returned in a Play check; the optimized preview had 27,476 descendants. Non-DEV multiplayer, active-round restrictions and the completed ten-section scene have not been playtested.

The prior full native `.rbxl` is in `pre-rework-place.rbxl`. The two changed CSG trim assets were separately exported from live Studio through `SerializationService` to `window-trim-templates.rbxm` (15,955 bytes, SHA-256 `76e5d0e41b28531d28854e9352442e081350110567a3e110d1bd5cac1feb616c`); a Studio deserialize roundtrip recovered both UnionOperations. This is a native backup of the changed assets, not a complete post-change place backup. Studio's **Download a Copy** sheet presented a disabled Save button even with a filename and writable local destination. A separate **Save to Roblox** action was attempted, but Studio showed no success confirmation and was not counted as a verified save or publication. A new full native `.rbxl` is still required. No successful publish has been observed.

## Release gate

Visual acceptance fails. Baseline captures `baseline-A.jpg` through `baseline-G.jpg` show the old map misses the requested compositions; the draft modules have no matched Studio renders. Do not claim 1:1 or publish until all ten distinct sections are integrated, camera matched against the supplied references, inspected at playable angles, and tested for collision, navigation, performance, DEV access and the 30,000 descendant budget. The original image files would permit pixel-overlay measurements; without them, report visual judgment as qualitative.
