# Level 6 subtle ceiling lighting — 2026-10-01

Level 6's working fluorescent fixtures now provide a restrained warm fill that reveals the ceiling tiles and grid from normal player height. The existing ambient lighting, exposure, color grade, textures, fog, saturation and contrast settings are unchanged. Dead fixtures stay dark. Lobby and Level 3 sources and geometry are outside this change.

Only two authoritative Studio Sources changed: `ServerScriptService.Level 6 Systems.Level 6 World Builder` (ModuleScript) and `StarterPlayer.StarterPlayerScripts.Level 6 Lighting Controller` (LocalScript). The builder adds one shadowless PointLight per working fixture, brightness 0.16, range 28, at 1.2 studs below the existing diffuser. The client follows the primary lamp's enabled state, brightness and color, including flicker, blackout, recovery and the final fade. It preserves the existing phase baseline array indices and uses the existing bounded connection cleanup. Actual installation used fresh Source/editor byte comparisons and guarded UpdateSourceAsync callbacks. See `install-ceiling-fill.receipt.json` and the exact `verified-studio-source/` export.

## Actual Play comparison

Open [the six-view comparison](before-after.html). These are actual Studio Play captures, not generated or retouched images. Before and after use the same seed (1135645734), camera CFrame, 70-degree field of view and normal eye height, across Arrival, Beige City, Orange/Black, Red Carpet, a connecting corridor and Kitchen Prep. The pinned seed and camera placement were Play-only QA inputs and did not persist into Edit. Kitchen Prep already had readable ceilings; its lighting was preserved.

| View | Before | Installed result |
| --- | --- | --- |
| Arrival | [Before](screenshots/arrival-before.jpg) | [After](screenshots/arrival-final.jpg) |
| Beige City | [Before](screenshots/city-before.jpg) | [After](screenshots/city-final.jpg) |
| Orange/Black | [Before](screenshots/orange-before.jpg) | [After](screenshots/orange-final-clean.jpg) |
| Red Carpet | [Before](screenshots/red-before.jpg) | [After](screenshots/red-final.jpg) |
| Corridor | [Before](screenshots/corridor-before.jpg) | [After](screenshots/corridor-final.jpg) |
| Kitchen Prep | [Before](screenshots/kitchen-before.jpg) | [After](screenshots/kitchen-final.jpg) |

The Orange/Black result was recaptured after its streamed carpet detail settled, at the identical pose. The local first-person character was hidden for the comparison; level geometry and materials were unchanged. Arrival image samples show a low warm ceiling lift, about 7% floor luminance increase and about 2% wall increase; this is fixture fill rather than a global ambient or exposure change.

## Verification and practical limits

- Actual normal avatar walking and keyboard interactions verified entry, representative rooms/corridors, return to the lobby and a second entry. Health remained 100; the returned lobby matched every cached lighting property.
- Installed fresh Play had 162 ceiling fills when the whole level was streamed. All reported follower audits had zero property mismatches, including streamed fixtures and the second entry.
- Controlled inputs in actual Play verified off/half/restored lamps, pre-blackout, full blackout, recovery and the final fade. All lights reached darkness, with no residual fill. These checks do not claim natural full-CD/music progression or multiplayer objective completion.
- Two bounded 120-frame samples of the same desktop Play viewport averaged about 60 FPS with and without the new fill. This is not a mobile or multiplayer benchmark. Connection cleanup and three connections per fill were checked in source; connection counts were not measured at runtime.
- Exact candidate compilation and independent Codex source review passed. Actual Claude Opus 5.5/max participated in lighting design, visual assessment and a successful final design review. An earlier full follower review timed out; it is not represented as an approval of the complete code diff.

Full native before/after recovery files remain local in `native-before/` and `native-after/`. Their tracked manifests and verification receipts record hashes, all script paths/classes and Source/editor parity. The serialized service-child forest is retained alongside reconstructed native places because some engine service properties cannot be reconstructed by the offline packer; those limitations are explicitly recorded. No repository snapshot was pushed into Studio.

Published version **2460** to the existing place at 17:33:10 UTC, verified by Studio's PublishSuccessful log and Creator Hub's newest published-version checkmark. See `publish-receipt.json`. Existing servers were not restarted and access settings were not changed. There is no configured Git remote, so a local commit is not a GitHub push. The unrelated cathedral Blender edit was preserved.

Existing console warnings about animation asset `114302219876492` access and lazy Level 6 state/remotes were observed. No new runtime error from either changed Source was found. One inspection command had an invalid Color3 arithmetic operation; its replacement comparison passed. These are recorded separately from the lighting verification and were not changed by this task.
