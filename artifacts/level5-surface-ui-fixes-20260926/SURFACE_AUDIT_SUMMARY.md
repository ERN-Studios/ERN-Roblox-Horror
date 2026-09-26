# Final surface audit — 26 September 2026

Read-only audit v5 completed on 27,665 exported records / 89,098 supported faces in 6.93 seconds. Nine focused audit tests pass; material enum spellings are normalized.

| Exact face candidates | Before | Final |
| --- | ---: | ---: |
| Floor tops | 252 | **0** |
| Vertical faces | 9,238 | **129** |
| Undersides | 450 | **218** |

Final round three removes both exposed C ceiling overlaps and all four F railing/plaster strips found in round two. No new exposed material-changing conflict was identified. Remaining exact vertical groups use matching material variants and mainly concern exterior shell edges, small slab edges and joined furniture. Remaining undersides chiefly sit below ground/foundations; a 1.728-square-stud high scenic wood/plaster underside joint is unchanged from baseline. These are candidate counts, not a claim of zero possible pixel-level flicker.

The 626 near-floor pairs are intentional joints or layers whose lower-face centers lie inside the higher partner, including 539 stair tread/riser pairs. They are not 626 exposed floor defects.

Root separately reports final native geometry QA: **18,168 rays, zero failures**. Navigation and visual checks remain separate from this offline diagnostic.

See `final-surface-audit.json` for tolerances, input digests, baseline comparison, grouped paths and limitations. The task-local `qa/SURFACE_AUDIT_HANDOFF.md` records the complete review history. No Studio or product-source mutations were performed by this audit.
