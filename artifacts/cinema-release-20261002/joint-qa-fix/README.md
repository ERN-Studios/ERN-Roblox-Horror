# Level 4 exit navigation assertion correction

The actual joint TRIAL ROUND generation 1 suite reported 92/93 checks, with only
`L4ExitScreen reachable: ExitScreen 26.1 studs from a node` failing. The original
report is `artifacts/level1-quality-20261002/joint-level4-suite-active.json`.

The authoritative cinema asset export records
`Workspace.Level 4 Cinema Blender.Collision.ExitScreen` at
`(29000, 62, -237.5500030517578)`, size `(116, 48, 0.5)`. Its bottom is Y38;
its centre is not a standing destination. The graph's nearest node 2907 is
`(29000, 36, -234.85)`, on the authored exit platform. Its distance to that
centre is 26.1398167 studs, with a 26-stud vertical difference. The old suite
incorrectly applies the other objectives' 14-stud centre-distance rule here.

The actual Objective Controller accepts a root inside the exit's object-space
box with X +0.6, Y +3 and Z +3 margins. A standing root three studs above node
2907 is `(29000, 39, -234.85)`: local Y -23 and Z 2.700003 are accepted. Node
2862 also enters that volume. All 5607 graph nodes connect to the entry; an
offline BFS has a 71-node route from the exported first entry to node 2907.
The native graph audit records nodes on all six exit treads and the platform.
`round_assets.py` checks the existing standing-root offset, two-stud steps and
exit volume; `usher_nav.py` generates floor points and clearance-tested edges.

Caller review found the Usher's `nearestNode` calls in `goTowards` (target and
current feet position) and its existing `DebugPlace` hook. None target the exit
screen centre. Actual escape uses `insideBox(..., 3)` in the Objective Controller.
The independent existing graphify index did not index these newer Level 4
modules, so this conclusion is based on current source and the asset export.

Only the suite's `L4ExitScreen` branch changes. It requires an entry-connected
floor node whose standing root enters the exact existing gameplay volume.
Every other anchor retains the 14-stud centre rule. Runtime gameplay, graph,
geometry, lobby and progression are unchanged by this candidate.

Candidate SHA256: `59f1cd5e87c72c89a60e0f1c4119a5d931b9084ba9689df1e1b94f06a3869335`.
Before source SHA256: `f1499854f678f1de6153e9144f39044f7e3073fc590351df7294d4cce88151ff`.
The root must compare fresh Studio Source/editor before applying this scoped diff.

`python artifacts/cinema-release-20261002/joint-qa-fix/test_suite_exit.py` runs
both complete actual `Suite.Run` implementations with the real Config/Nav and
mock anchors. It passes 39 assertions: the recorded centre false failure,
corrected platform entry, rotated trigger, inclusive depth margin and its
outside epsilon, sealed high trigger, far trigger, disconnected inside nodes,
and the unchanged far-reel rejection. Missing Luau exits unsuccessfully.
The official Luau compiler accepts the candidate.

These checks establish the assertion's geometry and connectivity. They do not
establish an engine collision walk-through, natural Usher chase, multiplayer
behavior or profile persistence. Root-owned actual finale/escape/reset QA and
the active-round suite rerun remain separate requirements. No Studio or
canonical source write was performed by this preparation.
