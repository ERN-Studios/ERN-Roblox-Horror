# Claude Opus 5.5 review: Level 5 sections 03, 04, 06, 07 and 10

Read-only CLI audit on 2026-09-27. The command used `claude -p` with `--model opus --effort medium --output-format json --permission-mode plan --tools Read,Grep,Glob --no-session-persistence`. The returned JSON reports `is_error=false` and `modelUsage.claude-opus-5-5.canonicalModel=claude-opus-5-5`. Claude did not edit Studio or project files.

Claude read the image bytes of `gallery-current-ref03.jpg`, `ref04.jpg`, `ref06.jpg`, `ref07.jpg` and `ref10.jpg`, the reference specification, both gap audits, current gallery visual QA record, and the Facades and Anomalies module sources. The ten original screenshots are only in the ChatGPT conversation and were **not** available to Claude CLI. These landscape Edit captures predate the concurrent uncommitted builder proposals, so this is a source/capture gap audit, **not** a verified 1:1 comparison. Source line numbers below were captured while other agents were editing and may move.

## Section 03: bright cottage/apartment atrium

- `Facades.BuildBrightAtrium`: close the side and near sky exposure around the coffer ceiling. The source has a broad `CreamCeilingField` but only one closure wall; current saved capture shows blue wedges. Claude suggested side closures and a rear closure, then aligning coffer beams to the luminous tile grid.
- The section's `VisibleStairTread` X progression appears opposed to the sloped flight direction: the tread height rises toward `+X` while the `side=1` flight slopes down there. Reverse the tread X term or flight slope, then render and verify. `ConnectedStairLanding` also intersects the first `DeepBalconyDeck` and its rail near z≈56–63. Relocate the bank/landing or split the rail. These are specific geometry risks, not validated in Play.
- `addClapboardHouse` hard-codes nearly the same opening set, full-width porch and siding interval on all four cottages. Expose options for opening layout, porch width, upper paired windows and siding course spacing; give each foreground facade its own silhouette and window order at roughly the same instance cost.
- The older gallery count was 1,095 versus a 1,100 section budget. Recount the changed builder before adding the proposed closure and coffer parts. Claude has **not** seen the current cylinder tower rendered or the requested 74° FOV.

## Section 04: misty vertical tower canyon

- `Facades.BuildTowerCanyon` uses the same broad `recessedShaft` pattern for both towers. Its 29–31-stud balcony spans on 43–44-stud shafts retain a horizontal band grid. Split each into narrower, staggered balcony stacks separated by solid piers and a narrow window run; vary the setbacks and stacks across the two towers.
- Increase upper-level color convergence toward the warm gray haze. The code's existing `tierColor` interpolation reaches only about 25%; simply repeating opaque horizontal rails to the top will keep the towers visually flat. Use simpler upper-floor band/detail LOD to fund the lower facade.
- Distinguish the foreground houses through the shared `addClapboardHouse` options and porch rail treatment. Replace the dense far window shaft with a cheaper core and selected vertical strips if the double-stack change exceeds the 1,200-section budget. Claude estimated a net increase near 25 pieces, **not a measured count**.
- The saved capture predates the current opaque enclosure/central spine proposal. Fresh Studio render is needed to judge the upper haze and whether the towers actually disappear into it.

## Section 06: long gabled lawn

- `Anomalies.buildSection6`: the stored camera is very near the mirrored facade plane and looks almost along it, so the capture reads as bare porch roofs/slabs and the actual dense window grid is edge-on. Claude suggested testing a camera roughly 25–35 studs away, for example around `(20,6,-4)` aimed toward `(-24,34,165)`, then tuning against the reference composition.
- The revised source has a deeper black pocket, but its lawn-facing side return may read as a solid black monolith from the corrected camera. Check whether the void is a **break in the right facade** rather than an isolated panel; set back or facade-clad the return as needed.
- The local source's dark windows sit close to the face of a single wall mass. Add visible jamb/head depth and more ground-entry/canopy detail rather than another flat window texture. The older 955-descendant capture does not include the uncommitted opposite facade; measure `EstimatedInstances` and the actual isolated build before adding more trim.

## Section 07: exposed stair-stack cutaway

- `Anomalies.buildSection7`: the break remains a full-height rectangular slot bordered by thin, mostly straight `ExposedBrokenCore` columns. Vary the torn edge within each storey and add broken floor-slab/carpet stubs at successive levels so it reads as rooms cut open, not a staircase pasted between walls. Claude estimated about 16 extra parts for such edges.
- `CarpetTread` parts are thick brown blocks without a continuous underside. Add sloped flight soffits and open-side stringers, then check the white rails/newels against each landing. Claude estimated about 12 additional pieces. The door-to-landing alignment looked plausible **in source only**.
- The three current ceiling SurfaceLights lie ahead of the stairwell; move or add a luminous panel over the stair volume and verify in Play Lighting. The current camera in the working tree is more oblique than the older frontal capture, so render before making framing changes.

## Section 10: empty carpeted balcony room

- `Anomalies.buildSection10`: the source camera/frustum clips one jamb of the wide white foreground portal. Test a centered camera farther back, around x=0/z≈−25, with explicit FOV. Bring the central partition nearer only after that view test; otherwise it may make the room too shallow.
- One blue-looking left window in the saved capture exposes an incompletely enclosed atrium void. Add a high cap, dark lower closure and additional opposite balcony tiers/rails; keep the room otherwise sparse. Claude estimated about 50 extra pieces, unmeasured.
- Vary the six raised door panels in height so the central six-panel door reads correctly, move one fluorescent/SurfaceLight panel into the front room, and close small baseboard offsets. Inspect whether waypoint 2 routes through the partition; Claude suggested moving it toward the actual left opening around `(-30,3,26)`.
- The saved capture precedes the working-tree camera change; the mirrored camera and left-window view have not been re-rendered or navigated.

## Verification order

1. Build the five **current proposals as isolated clones** in Studio and record actual descendant counts and fresh camera captures. Do not treat these older JPEGs as current source evidence.
2. Check the section 03 tread/landing intersection and section 10 waypoint against the geometry in Studio. The Facades builder currently marks its pieces noncollidable, so gallery visuals alone cannot verify a playable route in 03/04.
3. Compare each view against its own original portrait screenshot from a matched camera/FOV/lighting; the originals are absent from this checkout, so this CLI pass cannot certify strict 1:1 facade fidelity.

The full CLI result was returned successfully; its raw JSON was temporarily stored outside the repository at `/tmp/l5-claude-remaining-refs.json`. This document is an edited summary of Claude's response, preserving its evidence limits and source-specific findings.
