# Level 3 slide entry — polygon aperture handoff

Trello: psRtwdjR. The user's image shows orange wall blocks intruding around the white slide mouth. The initial near-edge strip correction removed the intrusion but left black stepped holes visible from oblique viewpoints.

## Delivered change

- Only `ServerScriptService/Level 3 Systems/Level 3 World Builder.ModuleScript.lua` changed in production.
- Preserved root's Arrival/West opening-height correction, 16.0 → 16.1, and all published Level 3 run-in exit changes.
- Replaced the 40 rectangular circle strips with 20 rectangles and 20 WedgeParts. These tile the outside of the tube's actual 20-sided cross-section continuously, at the same part count.
- Projected the first tube segment's polygon onto the wall plane, accounting for its small upward slope. The aperture's edge meets the middle of each .30-stud fiberglass panel, with at least .143269 studs of clearance from the inner bore across the complete wall depth.
- The plaster face stays parallel to the wall, protruding only .01 studs to avoid a recessed seam. Existing floor/lintel and side walls overlap the seal's outer bounds. Seals remain anchored, noncolliding, nonqueryable, nontouching and without shadows.
- Tube panels, slippery physics, runout, resume frame and velocity, and ride controller are unchanged.

Exact before/after diff: `level3-slide-aperture.diff` (95 lines, original slide baseline). Agent-only diff against root's nearY/16.1 trial: `level3-slide-aperture-agent.diff` (87 lines). Agent snapshot: `slide-agent-before/Level 3 World Builder.ModuleScript.lua`.

## Offline evidence

`tools/tests/test_level3_slide_aperture.py` executes the actual Luau builders for the wall, room floor, complete tube shell/runout and aperture. Only Roblox math/Instance constructors are mocked. It then uses the generated Part/WedgePart geometry for convex separation, volume occupancy and segment/solid intersections.

Result:

```text
Level 3 slide aperture: 59694 checks passed; 59130 volume samples,
240 front/oblique rays, 40 seals, minimum bore clearance 0.143269 studs
Level 3 run-in exit: 94 checks passed
Compiled 2 KLOC into 83 KB bytecode
```

The same geometric test rejects both earlier versions without relying on the new part names/types:

- Original `slide-before.lua`: orange prism enters the bore, convex clearance `-0.53819990` studs.
- Root's nearY trial: unfilled opening at `(6151.26, 24.20125, 2.5)` with the actual room floor and first runout included.

`git diff --check` found no whitespace errors. The file's pre-existing mixed newline warning remains unchanged.

Independent mathematical/code review: **9/10**, no required code changes. Reviewer reran the aperture test and compiled the complete builder. Native WedgePart orientation was separately confirmed by root in Studio Edit: identity size `(2,2,2)` hits an X ray at `y=.5,z=.8`, misses at `y=.5,z=-.8`; temporary object destroyed.

## Root-owned final verification

**Completed by root:** Normal lobby Level 3 queue with one player and the real countdown generated a fresh world. Native front, both oblique views and the floor edge showed no orange intrusion or black stepped gaps. The actual client-owned ride probe passed: 239.261 studs travelled, peak 120.311, approach 54.853, 11.849 studs past mouth, slide state entered and released on exit. See `level3-slide-ride.json`. All 122 scripts compiled and final Studio/repo audit matched 122 with zero drift (two documented trailing-LF contracts). Independent critic reviewed code, reran the focused tests and accepted root's runtime evidence: **9/10**, no blocker.

**Published v1816 using the mouse**, File → Publish to Roblox. Native Output confirms **9 September, 22:49:48.993 Danish time**. An earlier publish of the same v1816 was already visible at 22:47:49; that earlier input was not attributable to root. This later mouse action and successful response are directly observed. Trello card moved to Done and marked complete. This closes the concrete aperture bug; published multiplayer cross-server transfer remains on the separate loading robustness card.

1. Scoped push of World Builder, then generate a fresh Level 3 world.
2. Inspect the mouth front-on and from both oblique sides, including the upper corners. The mathematical test does not establish rendering/subpixel seam quality.
3. Run the existing live, client-owned ride probe:

```lua
local suite = require(game:GetService("ServerScriptService")
    ["Level 2 Systems"]["Level 2 Exit Transition Test Suite"])
local result = suite.ProbeLevelThreeSlideOut(
    workspace["Level 3 Generated World"], game:GetService("Players"):GetPlayers()[1])
```

The probe is at `Level 2 Exit Transition Test Suite.ModuleScript.lua:900`. It protects/restores the player, positions them at the rear resume, watches up to 14 seconds, and requires >80% of the 230-stud ride, approach speed >40, peak speed >62, slide state entered and `PlatformStand=false` after exiting. It returns the measurements and `ReleasedOnExit=true`.

4. Complete the root's critic/native review and publish with the mouse through Studio's menu, per the user's latest instruction. This agent has not pushed, controlled Studio, or published.

The test assumes the current authored opening dimensions 16.0 × 16.1. If that design changes, update the sampling envelope. It validates exact geometry in double precision; native viewing remains necessary for visible cracks introduced by engine precision or rendering.
