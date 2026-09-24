# Level 5 — Indoor Suburbs expansion

Verified map delivery, 2026-09-23. The expanded map has passed Studio visual review, character traversal through all eight districts, representative side routes, lobby return/cleanup and the final fresh-Play check of its cutaway entrances. The final 176-script export has zero source/editor conflicts and matches the repository after the three-module sync. Map implementation commit `ec5787672527df614672a49fa19f08d6e6804603` is pushed to `codex/level5-indoor-suburbs`, with PR #7 updated. Four of five expansion checklist items are checked in Trello. A new native after-backup and verified publication remain blocked by Studio’s unresponsive Download a Copy dialog; the owner has been asked to save/cancel and publish. The earlier map's v2026 publication does **not** establish publication of this expansion.

## What changed

Level 5 now has eight distinct enclosed districts rather than a uniformly enlarged version of the first map. Low domestic corridors alternate with larger residential courts, terraces and a tall window canyon. Shorter ceilings, offset houses, through-house passages, stair circuits and separate courts create different exploration spaces along the route.

The architecture keeps the original references: ordinary pale houses, white trim, tinted domestic windows, office ceilings, carpet where lawns should be, repetitive porches and houses fused into impossible stacks. Zyntra remains the researchers' organization; the Backrooms' origin is unexplained.

| District | Ceiling Y above the map origin | Distinct environment |
| --- | ---: | --- |
| A — Balcony Atrium | 44 | Original entry reveal, multiple balcony levels and cross-bridge. |
| B — Low Eaves Arcade | 18 | Low covered porches, long dropped soffits, deep corners and two detached rooms with passages through them. |
| C — Pastel Village | 48 | Four offset courts, fourteen cottages, twelve enterable houses, six through-house shortcuts and broad side loops. |
| D — Floral Terraces | 32 | Pink stairs into a sunken green-carpet street, raised yellow porches, floral walls, two bridges and domestic alcoves underneath. The lowest floor is Y−12. |
| E — Domestic Labyrinth | 15 | Compressed empty sitting rooms, deep doorframes, dark interior windows and alternate room loops. Local soffits are lower than the outer ceiling. |
| F — Bay Window Canyon | 108 | Eight tightly grouped residential stacks, six or seven storeys high, with bay windows, cutaway façades and staggered overhangs. Three traversable elevations connect through two switchback stair circuits and bridges. |
| G — Tilted Subdivision | 66 | Eight principal houses on carpet terraces at Y0/8/16, a through-house exploration loop and two tilted houses visibly embedded into supporting domestic masses. |
| H — Last House | 26 | Quiet compact court, final house with three unwired lamps, painted arrows and the narrow descent into a contained dark landing. |

The different ceiling values are authored local Y coordinates, not identical headroom measurements throughout each district. Side rooms, balconies and the sunken street have their own floor elevations.

## What “about five times larger” measures

The new districts' authored ground envelopes sum to **331,600 square studs**, compared with the earlier envelopes' **65,396 square studs**: **5.07065×** by the same envelope-sum convention. The new districts meet at their boundaries; the historical baseline envelopes include approximately 892 square studs of overlap.

This is a map-footprint comparison, not a precise union of walkable surfaces or a navmesh-area measurement. Walls, inaccessible scenic volumes, interior footprints and small overlaps affect actual usable ground. The comparison excludes the chute and additional upper floors. It does not claim five times the playtime or uniformly scale rooms, doors, stairs or characters.

## Windows and lighting

All **356 inspected window panes** used the same non-emissive standard: `Glass`, RGB `(87, 102, 102)`, transparency `0.2`, reflectance `0`. The inspected build had **zero window-standard violations**. Neon remains on genuine fluorescent panels, interior fixtures and sconces. Windows themselves do not glow.

The tall canyon has gentle lighting beneath balconies and bridges so its ground route does not depend on ceiling lights 108 studs above it. Two subdivision fixtures are suspended from the ceiling. The last measured build contained **60 actual light instances**; this count is separate from decorative Neon fixture parts.

## Visual review and revision

Visual review found that two intermediate ceiling rafts cut through the tilted houses, and both were removed. A later source review found that the open cutaway rooms still had a continuous low façade apron. The apron is now split to provide a seven-stud walk-in opening only for open cutaway rooms. The final rebuilt map measured **11,638 BaseParts, 12,179 descendants, 60 lights and 356 windows**, with zero window-standard violations. The root's count attributes matched those measured values.

Screenshots in `assets/level5/expansion20260923/screenshots/` include seven earlier Edit views (`low-eaves.jpg`, `pastel-village.jpg`, `floral-terraces.jpg`, `domestic-rooms.jpg`, `window-canyon.jpg`, `tilted-quarter.jpg`, `last-house.jpg`) and three later Play views with HUD: `final-canyon.jpg`, `tilted-quarter-final.jpg` and `pastel-village-final.jpg`. The integration developer reported the landmark visual review passed after the raft correction. Screenshots establish visible appearance at those viewpoints; movement results below establish the tested routes separately.

## Actual Studio traversal

The integration developer walked the main route through **A → B → C → D → E → F → G → H and the chute**, using actual character navigation rather than teleporting between districts. The main routes passed. The raw navigation calls are recorded in `artifacts/level5-expansion-20260923/navigation-tool-results.json`.

- The chute was traversed with `Humanoid:MoveTo`: observed positions included `(17000.01, 16.81, 1286.44)` and the dark landing at `(17000.01, −1.40, 1313.36)`, with health 100. The character then walked back uphill to F.
- F's west stair circuit, upper bridge and east upper route passed. The navigation tool could not find a direct route from the east upper landing to the lower landing. Moving the actual Humanoid through intermediate Z962/948/930 points descended successfully with health 100; subsequent navigation to `(17065, 27, 970)` succeeded. This is a documented pathfinding-tool limitation, not an unqualified automated-route pass.
- Both G terrace stairs passed ascent and descent, and the secret through-house route passed.
- E's west and east room loops, D's side flights, a C through-cottage and B's detached waiting room passed.
- Holding L returned the player to the lobby at approximately `(-0.61, 33.16, -859.17)`, with `InRound=false` and no generated Level 5 world remaining.

The last cutaway-apron correction also passed a focused fresh Play session. The character walked into and back out of the ground reading room via `(16888, 27, 899)` → `(16869, 27, 899)`, then climbed the west stairs and entered/exited the upper cutaway room at `(16902, 57, 878)`, returning toward X16927. The final console had no errors; only ordinary EntityAI and TunnelLobbyBuilder messages were reported. These checks do not establish human multiplayer or hardware performance.

## Scoped source changes

Only these three architecture ModuleScripts belong to this expansion's intended source edit set, all under `ServerScriptService.Level 5 Systems`:

- `Level 5 Architecture`: shared geometry helpers, consistent tinted windows, A/B construction, eight enclosing districts, ceiling variety and result assembly.
- `Level 5 Neighbourhood Districts`: C/D/E geometry.
- `Level 5 Landmark Districts`: F/G/H geometry and relocated final-house/chute references.

The final 176-script export confirmed only the Architecture module changed and the two district modules were added. All 173 unrelated sources are unchanged. The ten paths containing `Level 4`, plus `Level4Generator` and `Level4GateAccess` (twelve sources total), are byte-identical. The Level 5 adapter, origin, developer gate, queue, shared round flow and lighting ownership remain unchanged. All exported files match the raw Studio Source bytes and all editor/source checks pass.

The repository stores screenshots under `assets/level5/expansion20260923/screenshots/` and verification records under `artifacts/level5-expansion-20260923/`, preserving the earlier delivery separately. `studio-source-verification.json` records all 176 script hashes and confirms the scoped changes. Fifteen historical RemoteEvent records remain preserved in the main manifest; this script export did not re-verify those remotes.

The final chute now starts at local `(0, 0, 1255)`, bends through `(0, −11, 1287)` and ends at `(0, −29, 1310)`, with a contained landing through Z1319. The ground and rear enclosure leave the descending passage clear. `PuzzleReady`, `FutureDoorPlaneZ`, `GeometryOnly_NoSlideOrCompletion` and the suggested slide-start fraction `0.7` remain architecture annotations.

## Scope and remaining checks

This remains a **map-only developer preview**. No entity, functional puzzle, controllable slide, victory trigger, reward flow or public Level 5 access was added. The final house's three lamps are set dressing for later puzzle work.

Pending at this report’s update: native after-backup and successful publication of this expansion. The delivery checklist item remains unchecked until both are verified. Human multiplayer and physical mobile/tablet performance have not been measured.

`QA-EVIDENCE.json` records the final measured Play results. Publication receipts must refer to this expansion rather than the earlier Level 5 delivery.

## Concurrent developer changes preserved

Remote branch `claude/trello-20260921` advanced to `ebb3b7c` during delivery. The full-party 3-second countdown and death-card layout fix were already identical in the verified Studio export. Merge `2d96bf9` retains the developer’s new Level 4 entity/hazmat concepts and historical brief updates; only stale manifest hash conflicts needed resolution. All 176 runtime mirrors still match the export after this merge. These are preserved upstream changes, not new Level 4 implementation by this task.
