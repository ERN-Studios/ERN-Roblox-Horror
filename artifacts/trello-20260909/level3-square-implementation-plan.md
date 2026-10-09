# Level 3 square layout — implementation and fixture plan

Read-only preparation for [k6e4BnS1](https://trello.com/c/k6e4BnS1), 10 September 2026. No Level 3 runtime file, Studio state or publication changed. Implementation awaits the current Level 2 feature's publication and root's authorization.

The request is to make the long rectangular Level 3 map more square. Preserve the current arrival, 26 room IDs/roles, three themed districts, 31 links/six cycles at standard tuning, five CDs, 24 hiding tables and the straight 560-stud +X finale. The target is `max(width, depth) / min(width, depth) <= 1.5` for the full room plan and `<= 2.1` for the core excluding Exit. Report the rendered footprint including the westward arrival slide separately.

## Minimal runtime scope

1. **Layout Generator:** change placement/gateway ports, filter the first CD selections, update metadata/version and add physical layout validation.
2. **Configuration:** update `Layout.GeneratorVersion` to match. Keep room dimensions, corridor width/height, music, finale length/timing, hiding and navigation tuning unchanged.
3. **Test Suite:** extend existing `ValidateGeneratedLayouts` and `ValidateNavigationLayouts` with the new layout contracts and measured bounds. No World Builder, AI or Objective changes are expected from source inspection.

Exact pre-edit copies will be taken after authorization. The current files remain authoritative until then.

## Placement algorithm

Keep the existing local two-row/four-column district grid, slot numbers, room IDs, seeded room dimensions, decor assignments, seven-edge DFS tree and two additional loop edges. Use two placement phases so there is one final coordinate assignment rather than constructing an obsolete horizontal plan and translating it afterward.

- Generate each district's widths, two row depths, three internal gaps and room metadata. Accumulate the maximum width per column and maximum gap per column boundary across the three districts. Retain each district's own room widths/depths and each sampled inter-district clear gap.
- Set four shared X centres. The first column's western envelope begins at Arrival's east edge plus its existing entry gap. Consecutive centres differ by half of both shared column widths plus the shared gap.
- District 1 retains row centres `-RowHalfSpacing` and `+RowHalfSpacing`. For each following district, place its north-row edge after the previous district's south-row edge plus the sampled gateway gap. Equivalently, its district offset increases by `2*RowHalfSpacing + previousSouthDepth/2 + gatewayGap + nextNorthDepth/2`.
- Assign those shared X centres and final Z rows to every room, then compute each district's actual bounds from its room edges.
- Choose two gateway **columns**, each from 1–4. Join the previous district's south row to the next district's north row in the same column. These exterior South/North ports are unused by local grid edges. Start the DFS in the actual incoming room: entry row/column 1 for district 1; north row/incoming column for districts 2 and 3.
- Keep Arrival west of district 1 at its existing entry row. Keep SignalHall in the rightmost column of district 3 at the seeded exit row. Derive Exit from SignalHall exactly as today, with an edge-to-edge 560-stud +X link. The authored exit set is explicitly +X-oriented.
- Keep four GatewayLinks and their kind, themes, FromSection/ToSection and incoming/outgoing link references. Replace the unused `GatewayRows` diagnostic with `GatewayColumns` for the two inter-district links; entry/exit rows remain available on Arrival/SignalHall. Increment the generator version and resulting hash intentionally.

`GatewayRows`, GridRow and GridColumn have no consumers outside the generator that require the old global X arrangement. World Builder uses room coordinates and cardinal links; the Manager uses the resulting graph and room bounds. Final-hall markers are derived from the actual start/end points.

## CD selection correction

The current first three CDs are randomly selected one per district without testing separation against previously selected CDs. Only the last two receive that check. Stacking can put a south-row room and the next district's north-row room approximately 90–116 studs apart, so a current first choice can violate the 105-stud minimum.

Filter the first-per-district candidate list against all selected CDs before the seeded choice. Preserve its current middle-column preference and at least one CD per district. Return a normal generation-attempt failure if no legal candidate exists. Keep the current farthest-separated selection for the final two CDs. Measure retries/fallback use; do not accept successful generation that achieves square layouts mostly through fallback seeds.

## Bounds argument for standard tuning

These are conservative design bounds, not measured revised-generator results:

| Metric | Bound | Basis |
|---|---:|---|
| Shared four-column width | 312 + 102 = 414 maximum | Four widths at 78, three gaps at 34 |
| Full room-plan width | <= 1,144 | Arrival 64 + entry gap 48 + shared span 414 + final hall 560 + Exit 58 |
| Full/core depth | >= 772 | Three districts at depth 180 + 52, two gaps at 38 |
| Full aspect | <= 1.482 | 1,144 / 772; the full width remains the longer dimension |
| Core width | >= 414 | Arrival 64 + entry gap 38 + four widths at 60 + three gaps at 24 |
| Full/core depth | <= 840 | Three districts at depth 180 + 68, two gaps at 48 |
| Core aspect | <= 2.029 | 840 / 414; depth becomes the longer core dimension |

The same number 414 appears for two different bounds. The shared district span's maximum excludes Arrival; the complete core width's minimum includes Arrival. Full width is at least 1,032, above the maximum depth of 840, so width is always the longer full-plan axis. Core width is at most 526, below the minimum depth of 772, so depth is always the longer core axis. The bounds apply to the resolved standard configuration, not arbitrary Master-panel size overrides. Verify actual resolved tuning in native acceptance.

Shared maximum widths/gaps preserve minimum spacing. A district's narrower rooms can have actual edge-to-edge gaps above the original 34-stud maximum sampled gap; only the shared envelope gap stays within 24–34. This is intentional and must not be reported as preserving every original physical gap.

## Meaningful fixture design

Run the **actual generator and validator**, not a second implementation of its placement formula. An offline host may supply deterministic random draws and a read-only Master overlay, but any non-Roblox PRNG must be labeled as such; the exact 104-seed engine sweep remains native evidence. Include all four fallback seeds and `104729*i+1` for i=1..100, repeat seeds for determinism, record hashes, attempts, resolved seeds, generation failures and fallback use. Re-run the unchanged baseline through the same aspect assertions and require it to fail them.

Extend the existing generated-layout and navigation tests:

- Counts, themes, all IDs/roles, 3x8 connected districts, six cycles, 24 hide spots, five unique CDs and one per district; pairwise CD distance >=105.
- Four gateways with exact endpoint/column/side/theme metadata. Both district bridges must point South from row 2 to North on row 1, with identical X and the configured edge gap. Arrival must join East; SignalHall's hidden exit must remain +X and exactly 560 studs long.
- Same-seed hash/attempt equality; different seed diversity; no silent fallback concentration. Bounds must exactly enclose their rooms and match independently measured extrema. Aspect uses the longer/shorter dimension so flipping the long axis cannot fool it.
- Axis alignment, unique side ports, minimum 18-stud edge clearance, room AABB separation and connected graphs with/without the sealed Exit. Reuse the existing nearest-room classification checks at every corridor mouth/midpoint to catch new adjacent-district ambiguity.
- Add corridor **shell** AABB checks against every non-endpoint room and every unrelated corridor. The builder's clear width is 14 and its two outer side walls extend total width to 17 (`14 + 2*1.5`). Floor seal is +0.04 along the link. Use endpoint exemptions only for the actual endpoint rooms; a shared endpoint does not justify arbitrary corridor overlap outside that room.
- Mutation fixtures must be rejected for a foreign room crossing a corridor, two unrelated corridor shells crossing, a duplicate port, mismatched gateway metadata and CD separation below the threshold. Keep positive fixtures for ordinary endpoint joins and +0.04 floor seals; otherwise an overbroad validator could reject legitimate generation.
- Sample narrowest/widest/deepest/shallowest allowed standard room draws, gateway columns 1/4, both arrival/exit rows and CD candidates near each inter-district boundary. Test changed tuning separately for structural validity; standard aspect targets must not silently disable legitimate Master controls.

Whole-file compile is required for every changed runtime file. Scope testing to generated-layout/navigation contracts and the changed helpers rather than running unrelated known-failing broad suites.

## Native handoff

Root owns Studio generation, camera, real traversal and publication. Inspect seeds 101/7331 plus measured aspect extrema. Traverse both bridges in both directions, all CDs and hiding tables, and run actual Manager pursuit across the new 90-degree routes. Inspect walls/doorways for overlap and verify the Manager does not choose a close room across a solid wall and stall.

Recheck lobby start; slide aperture and NO EXIT arrival sign; locked final exit; five-CD reveal; unchanged 40% finale spawn/50% trigger along the 560-stud hall; physical run-in escape exactly once without a button; safe room, cleanup and a fresh round. Capture full rendered bounds including the slide and compare build duration/instance count and pursuit behavior. Independent critic must score at least 8 after native evidence; root then publishes with the mouse.

Critic's independent read-only checklist agrees with this scope and highlighted the first-CD selection gap, corridor-shell checks, actual incoming DFS root and native cross-district pursuit as the main risks. No implementation or acceptance is claimed in this document.
