# Level 1 quality revision: code and geometry

The 2026-10-02 continuation starts from Studio Edit, not the previous Git
snapshot. The root exported 21 scripts into
`artifacts/level1-quality-20261002/live-before`, with Source/editor parity.
The three code drafts below were copied from those exact verified bytes.
Initial Git reads showed HEAD `310fde1`, remote-tracking main `de2e4de`, and
unrelated Level 4/Trello work. None of that unrelated work was changed here.
The existing Graphify query provided provisional file relationships; its
historical artifact nodes were not treated as current Studio authority.

## Scoped implementation

- `BlenderRoomRenderer`: requires the new `Level1BlenderKitV2`; GameManager's
  existing readiness gate already delegates to this module. The later
  synchronous animation-release fix adds only a small teardown block to the
  fresh Cinema-aware manager. Room selection consumes `SelectionWeight`: quiet 16,
  column 1, low-divider 3 and special room 4. Native mask reciprocity and
  topology stay unchanged. The new low dividers are internal details with
  matching 8.5-stud colliders; every closed boundary retains its visible
  14-stud WallHalf and original query/collision Part.
- Full fixed `RelayShell`, `FuseBoxShell`, `LeverShell` and `ExitPortal` models
  replace their matching fixed casing groups. Existing prompt/query/collision
  Parts survive. Relay doors, lever shafts/knobs, fuse cores/caps and variable
  fuse sockets use separate authored components. Circuit labels, status
  indicators, sounds and objective attributes retain their existing authority.
  Carried fuse meshes follow the existing hand-welded parts and disappear with
  the carried item. Renderer state and instance registries are strong tables;
  Maze destruction disconnects listeners and clears the active skin reference.
- The existing sparse lamp positions, SurfaceLights, hum markers, dead lamps,
  flicker and power phases remain authoritative. Their imported fluorescent
  and grid fixtures retain authored depth instead of being flattened to the
  0.15-stud panel proxy. Only Lamp meshes track emission/color; metal housing
  and five-channel grilles retain their finish. GreenGlass retains its template
  Glass material and minimum transparency while following the exit state.
  Door leaves retain their authored hinge/pushbar depth and align their back
  faces to the original proxy rather than flattening hardware into the old leaf.
- Original wallpaper reuse and saturated tint are authored/imported asset
  choices. The renderer preserves that SurfaceAppearance tint when darkening
  pit walls. Only the preview uses MongoGrade saturation 0.08; Maze destruction
  restores the prior saturation if the value still belongs to this change.
  Public Level 1 uses its original -0.3 grade and existing visual builder.
- The preview exit uses the new portal/door leaf. Its old reinforcement,
  center seam and energy-node dressing are hidden, and the header changes from
  EXIT LOCKED to EXIT. The original Sign proxy animates inward around its right
  hinge for 0.6 seconds when the existing exit opens; its welded art follows.
  The trigger, escape authority and open timing are unchanged.

## Cable routing

The previous grid BFS only proved that cell centers connect. Its rendered
lanes were offset approximately -10 studs from the center, where the authored
corner columns stand, and endpoint connectors used untested L shapes.

The new preview keeps every BFS cell step and uses distinct central lanes
starting at -2 studs, spaced by 0.55 studs. A blocked cell waypoint moves to
nearby clear floor before rendering. A single obstacle sweep includes actual
CanCollide Parts from Maze and Decor, including imported Blender colliders
with CanQuery=false. Rotated boxes use conservative world bounds, and pit
footprints block floor detours while permitting existing ceiling routes.

Every emitted preview floor/ceiling piece receives a geometric clearance
check. A visibility graph can detour around nearby corners within a four-stud
window, with at most 96 nodes. Cable thickness receives a clearance margin.
Source, terminal and overlap joiners use the same check; segment ordering,
circuit IDs, branch boundaries and the existing client current animation
remain intact. The public branch retains its existing route construction.

A physically encased source/terminal or a route that cannot be cleared within
the bounded search refuses the preview puzzle instead of drawing through an
obstacle. This error path must be exercised against actual generated worlds;
pure geometry cases do not establish that all random placements are viable.

The subsequent bounded riser audit found that `layRiser` bypasses the
floor/ceiling routing checks. Current preview calls create terminal risers
ending at the actual box/lever jacks, normally Y 2.24/2.12. Wall-station
placement rejects nearby Decor footprints within seven studs. Full-height
overhead risers are not expected for the default 24-stud cell geometry:
the 144-stud pit field has one-stud beams centered at 0.5 + 13n, whereas
its cell centers are 12 + 24n; no pit cell center has a walking floor,
and the BFS requires floor at both cell centers. This is a source-derived
constraint, not a generated-world test. Raised/tilted furniture piles exist,
so an invoked full-height riser could cross furniture that clears the floor.
No concrete current preview clipping case was established offline; the
frozen game candidates remain unchanged pending actual-world inspection.

The independent read-only SAT probe now excludes only the native upright
Maze floor/ceiling proxies by parent, walking-plane height or full ceiling
dimensions. Thin raised furniture and low physical details are inspected.
It records terminal risers by actual CableJack position/circuit identity,
full-height risers reaching WALL_H - 0.4, unclassified risers and their Y
range. An additional assertion compares terminal/jack counts and refuses
unclassified runs. Zero full-height coverage is reported explicitly. Puzzle
casings are outside the wall/column audit because intended cable-terminal
contacts enter their lower rim; this probe does not certify all casing
contacts. The actual SAT/identity/classification helpers pass 29 assertions
under official Luau 0.737, including vertical penetration of a thin raised
tabletop. That controlled geometry check does not establish that the
current random generator invokes an overhead riser there.

## Offline and Studio evidence

`tools/tests/test_level1_quality.py` executes the actual candidate functions
under official Luau 0.737: 344 checks passed. These cover weighted variants,
V2 asset readiness, 40 geometry cases, rotated false-query colliders,
blocked-waypoint relocation, wall refusal, pit/ceiling clearance and
preservation of the random topology and objective authority, fixture depth
and ceiling alignment, and door depth/back-face alignment. The existing
preview authority/socket suite passes 51 checks against the new renderer and
maze draft. All three script candidates compile.

The asset manifest has 41 native components, ten component aliases, 42 room
models and 93 chunks.
The root installed the final candidates with fresh scoped Source/editor CAS.
The actual evidence below verifies bounded generated geometry, objectives,
capture and teardown. It does not certify publication, multiplayer, GPU/mobile
performance, server CPU or every possible random placement.

The first actual preview geometry probe and its corrected alias-count rerun
passed 112 checks, including 1,600 connected rooms, 56 cable segments against
3,983 physical obstacles with no intersections, two exact terminal risers,
and three successful bounded engine paths. No full-height riser occurred;
that branch remains unexercised. The 399 physical five-channel fixtures all
match the canonical Fluorescent component; GridFixture is an alias of the
same original grille asset, so it is reported separately from physical
fixture counts. This geometry result does not establish objective completion,
reset, multiplayer or CPU performance. The original probe result is retained
alongside `runtime-seed1-geometry-final.json`; the corrected probe SHA256 is
`2b51289a65fc7335bab2948e0603073b5c7d6c78286c036480dfe1221f31f1e3`.

Open-door visual inspection subsequently found an intact boundary wall behind
the hinged leaf. Those first geometry results predate the aperture correction
and do not certify its appearance. The scoped preview correction splits the
single intersecting native wall into solid sides/header, preserves its original
full CanQuery wall, and crops only the matching Blender shell into visible
pieces. A south-open quiet Blender room forms an eight-stud outside vestibule
with matching floor, ceiling and three closed side/back colliders. The closed
Sign collides until its original authoritative opening event; the original
trigger still transfers the participant to the existing remote SafeRoom.
Public Level 1 and the random masks remain unchanged. Both owner destruction
and renderer cleanup restore the original collision/art and remove owned
geometry; restoration runs before callbacks disconnect and is idempotent.

The updated actual-function suite passes 344 assertions: the original 296,
39 aperture geometry assertions across all four cardinal directions and
distant global wall centers, and nine actual cleanup/closure assertions.
The existing 51 preview/socket assertions and official Luau compilation also
pass. Frozen aperture candidate hashes are Renderer
`2057890603a40e357999f685784a79442c4b62413f6a0f9b9eb5b7d6c14f0ea3`
and PuzzleManager
`88f38d3b2e4d62b85a3082ab313ce3289654d2fde43aa4b8431c659fb02e8d8f`.
Actual seed 5 closed and open probes each pass 122 checks. They inspect the
real query-only boundary, three cropped wall art groups, matching split
colliders, the locked/open leaf and 15 safe floor samples across the threshold
and eight-stud vestibule. The root viewed both door states and navigated the
actual character to the unchanged trigger, producing the original escape and
lobby reset. The saved reset probe passes both room-removal assertions.
Raw records are runtime-seed5-closed.json, runtime-seed5-open.json and
runtime-seed5-reset.json, with native closed/open screenshots alongside them.
Puzzle setup used assisted actor positioning and the existing pause control;
objective interactions and the original escape trigger were exercised. The
root maintains the detailed action chronology separately.

Five real preview rounds exposed an additional controller leak: EntityAnimation
retained 40 Animation children because GameManager parked the entity and
disabled its script before deferred ancestry/Enabled cleanup callbacks ran.
The scoped shared-manager correction invokes an explicitly owned
`ReleaseAnimations` BindableFunction synchronously before parking/disabling.
EntityAnimation replaces that one stable function's callback with the current
controller cleanup on startup. Already disabled controllers are skipped.
The fresh Cinema-aware GameManager baseline is retained exactly outside this
small block; all activation callers were traced. The controller/manager mock
passes 123 actual assertions, including eight tracks/assets destroyed while
the script is still enabled and the entity remains in Workspace, foreign
animation ownership, repeated teardown and original activation. Official
compilation passes. Actual post-fix reset records for seeds 5 and 6 both show
zero retained Animation children, zero playing tracks, one owned handoff,
controller disabled, participant health 100 and round/preview/InRound false.
Seed 5 used the original escape route; seed 6 observed a natural capture/death
after one grounded actor placement, then automatic reset. Its 12-second
observer passes 17 engine assertions. No AI or animation event was forced.
These two completed teardown cycles resolve the observed eight-per-round
Animation leak within this bounded test. They are not a long-run leak or
multiplayer measurement. Natural lunge, visual stride/feet assessment, exact
fatal-hit timing, full-height cable risers, mobile and server CPU remain
unverified. Final temporary-QA removal, authoritative export/audit, commits
and successful publication remain root-owned release steps.


The joint Level 4 TRIAL ROUND also passed the final actual active-round suite,
93/93, after a QA-only reachability assertion correction verified by 39 whole-
suite mock assertions. The root exercised native power/reel/projector prompts
and the physical exit. Before/after public profile DTOs confirm Level 4 clear,
CompletedLevels 0 to 1, daily Clear, NoDeath/TimeGoal, record 4:solo:clean and
Tokens 35 to 85; the actual reset clears runtime/round and resets generation,
reels and breaker holder. Actor positions were assisted, so awarded clean
labels do not prove an unassisted clean run. The transient Escaped flag was
not captured before reset. Evidence is pinned in joint-integration-report.json.
