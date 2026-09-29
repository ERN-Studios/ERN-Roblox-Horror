# Level 5: dense neighbourhoods and household puzzles

Base revision: `c9e34b6`. Level 5 now has denser residential streets, physically sealed district boundaries, varied routes between seven household puzzles, and authored surface materials. Existing developer preview access remains in force. This change does not release Level 5 publicly or add the main hostile entity, completion rewards or a new ending mechanic.

## Map and routing

The eight existing district envelopes and their 1,078,800-square-stud footprint are retained. There are 121 additional houses, including 42 enterable homes, rather than uniformly enlarged buildings. The resulting map has **444 houses, 182 enterable homes** and **27 newly complete homes** with separate side rooms, central halls, interior plaster and wallpaper. There are 29 sparsely furnished homes in total. Bedroom, kitchen/breakfast and study furniture adds domestic detail without blocking the central passage or reserved clue walls.

| District | Added structure and route character |
|---|---|
| A — Balcony Atrium | Central residence, inner stacks and rear cottages; original four clue homes and balcony routes retained. |
| B — Low Eaves Arcade | Two house blocks make the route alternate between covered side lanes. |
| C — Pastel Village | Inner residential lanes and outer stacks connect four distinct courts; lawns now use grass. |
| D — Floral Terraces | Lower pocket stacks and a sunken home connect raised promenades with the stepped street. |
| E — Domestic Labyrinth | Nested end houses and cross-lane rooms create readable turns through domestic interiors. |
| F — Bay Window Canyon | Four central blocks and four side-court stacks subdivide the broad floor beneath the existing balcony network. |
| G — Tilted Subdivision | Central house, angled upper home, garden residences and solid terrace foundations strengthen the vertical residential scene. |
| H — Last House | Nested approach house creates a final bend; the existing final-house dogleg, arrow carriers and chute geometry are preserved. |

Broad facades use two or three domestic panes per side instead of long shopfront-like windows. All **1,050 panes** retain the common dark Glass standard. The eighteen curated Window Watcher anchors remain supported by their original rooms and panes across all eight districts. There are still **49 lights**, with **zero house lights and zero house Neon**.

Six-stud side walls extend outward from the original interior boundary. Eight-stud roof slabs, threshold walls and overlapping corner caps physically seal the shell. The two adjoining cutouts agree at every gate. Unnecessary D rails were removed from level promenades and from the full-width exit street; rails remain at actual drop edges.

`Architecture.Build` returns 120 ordered, world-space root-height `RouteWaypoints` (also `Waypoints`). `SectionGates[1…7]` contains world `Frame`, `Approach`, `Departure` and `WallThickness=8`. All face local +Z, with these local centres:

`(0,0,196)`, `(88,0,456)`, `(-120,0,936)`, `(120,0,1296)`, `(-120,0,1596)`, `(178,0,2076)`, `(-65,0,2456)`.

## Materials

The seven persistent MaterialVariants are reused across surfaces; they do not override global Roblox materials. `config.TexturePalette`, `config.MaterialVariants` and `K.material(part,key,tint?)` define the binding. Colored siding retains its pastel tint. Interior plaster is separate from exterior siding in complete homes. Grass has no carpet texture overlay.

| Variant | Base material | Tile size | ColorMap asset |
|---|---|---:|---:|
| Level5AgedPlaster | Plaster | 12 | 108985650994325 |
| Level5FloralWallpaper | Plaster | 8 | 102299936573476 |
| Level5PaintedSiding | WoodPlanks | 12 | 115748401620318 |
| Level5LawnGrass | Grass | 6 | 126776492995543 |
| Level5VeneerWood | Wood | 4 | 118880038763227 |
| Level5RoofShingles | Slate | 8 | 118077370167392 |
| Level5LoopCarpet | Fabric | 6 | 113909496202267 |

See `assets/level5/dense-materials-20260926/material-variants.json` and the adjacent provenance bundle. These MaterialService objects must travel with the native place backup; source scripts alone do not contain their authored asset data.

## Seven normal puzzles

Each normal prompt opens the appropriate puzzle. Wrong answers allow free retries. Correct answers unlock the shared physical door once, after the previous gate is fully open. The existing allowlisted developer bypass remains separate.

| Gate | Mechanism | Physical clue |
|---|---|---|
| 1 | Four colour wheels | Original four numbered colour drawings. |
| 2 | Household symbols | Ordered lamp, cup and key pictograms in a house. |
| 3 | House addresses | Three separate plaques identified by colour and written label. |
| 4 | Rocker switches | Three-position printed switch diagram. |
| 5 | Stopped clocks | Three clock faces read from left to right. |
| 6 | Television channels | Three numbered channel diagrams. |
| 7 | Last Directions / arrows | Three house-arrow drawings showing the required directions. |

There are twelve clue carriers: four preserved A drawings and eight new wall boards. Later clue houses have a small unlit “HOUSE CLUE” paper beside the actual front door. `HousePuzzleCandidate` and `PuzzleHintSurface` reserve accessible rear-wall areas; C deliberately uses three distinct homes. Clue props are noncolliding and do not render through walls.

Solutions and validation remain in the server-only `Level 5 Puzzle Catalog`. Submissions are bound to the current player, gate and nonce, with type/range/order/alive/participant/session/rate checks. The client receives presentation data and sends choices, never a solved state. Existing modal cleanup and the gate-open outage hook remain intact. Shared fixture names/ancestry, the Watcher rig/animation assets, and Level 4 are outside the geometry rewrite.

## Verification

- `native-dense-third.json`: **PASS, zero issues**, all seven gates closed.
- `native-dense-open-gates.json`: **PASS, zero issues**, all seven gates fully open after real allowlisted **F developer-bypass** interactions in the final rebuild.
- Each audit performed **17,901 bounded rays**, including 3,539 shell rays, 490 gate rays and 1,065 route samples across 119 segments. Twelve clue carriers and eighteen Watcher anchors passed their sampled support/visibility checks.
- Final native world count: **28,072 descendants / 26,443 BaseParts**, below the 30,000-total-descendant guard. Counts include the integrated runtime world rather than geometry alone.
- All seven normal puzzles were exercised with real wrong/correct inputs in the **first installed draft**. Gates 2–7 are recorded in `native-puzzle-inputs.json`; the original first puzzle was verified separately. Puzzle/progression source did not change between that draft and the final rebuild. Final open-state collision evidence uses the bypass interactions above; it is separate from the normal-solve evidence.
- The pure puzzle catalogue passed **6,910 assertions over 2,185 combinations**, including malformed submissions and authority boundaries. Geometry and puzzle source compilation passed.

The original route audit exposed two unnecessary D rail barriers plus several waypoint shortcuts and slope-height mismatches. The barriers were corrected, routes now go around houses, stair starts/landings have explicit points, and the final dogleg/chute points match the actual geometry. Both final native audits above include these corrections.

Continuous native walking passed all 120 route points in 333.52 seconds (`native-continuous-walk.json`), using normal Humanoid:MoveTo with no teleports, jumps, speed changes or gate writes during the walk. Initial staging and developer opening of gates occurred before the measured traversal.

Current-build performance was sampled during real traversal at Studio graphics Quality10 and a 1053×678 viewport:

| Sample | Average FPS | 95th-percentile frame time | Largest hitch |
|---|---:|---:|---:|
| First 30 seconds, A/B traversal with streaming | 45.0 | 47.66 ms | 2.497 seconds |
| Next 30 seconds, D traversal | 53.0 | 30.78 ms | 345.92 ms |

These measurements include Studio/OS load and initial streaming; they are not a controlled map-only benchmark. No result from the previous map is reused as proof of this build's performance. Transparent-window overdraw, static instance/collision count and memory remain the main risks; no new geometry update loop or house light budget was introduced. Physical mobile hardware and multi-account multiplayer have not been verified by these results.

Fresh-round reset returned all seven gates to locked state. Hold-L returned to the lobby and removed the generated world. A new full outage cycle observed 186 streamed fixtures across 564 samples, with zero darkness failures or restoration mismatches; unloaded fixtures are outside that sampling scope. The schedule preserved 5 seconds of falling lights and 60 full seconds of blackout.

## Delivery receipts

- Published existing place 131311258779917 as **v2133**, confirmed at 2026-09-26T17:46:27.384Z. Receipt: `artifacts/level5-dense-routes-20260926/publication-v2133.json`.
- Git delivery: branch `codex/level5-window-watcher`, [PR #10](https://github.com/ERN-Studios/ERN-Roblox-Horror/pull/10). The commit containing this document carries the matching source and asset records.
