# Level 1: authoritative analysis and Blender facelift contract

Date: 2 October 2026. Scope: keep the current Level 1 game loop and random maze;
replace its developer-preview visual layer with one consistent Blender kit.

## Evidence and authority

The inspected live place is `131311258779917`, universe `10559217407`, Studio
session `86f22f6f-aafa-4af2-b2dc-cf471bf0e3a4`. The parent inspected Git status
and current remote history before game work. The original session was playing;
the parent stopped it, and all source conclusions below were then checked
against a fresh **Edit** snapshot. No existing script was installed by this
analysis agent. The parent owns exact-instance/CAS installation and publishing.

`artifacts/level1-facelift-20261002/live-before/manifest.json` records 18 exact
sources, paths, classes, source SHA-256, editor SHA-256, script properties and
attributes. Every exported source matched `ScriptEditorService:GetEditorSource`.
The exporter rechecked source byte count and a live fingerprint inside every
chunk read. It fails if the source or editor parity changes during export.
This is a source analysis snapshot, not a whole native-place backup. The user's
later instruction explicitly said not to make a backup.

The initial Edit workspace had no generated Maze/Elevator/PitZones world,
`SelectedLevel=1`, `WorldGenerated=false`, and `LoadStage=WORLD_ERROR`. Those
attributes describe the initial session state; they do not certify a successful
or failed new facelift round.

The existing graph was queried first using its actual vocabulary: `maze`,
`generator`, `relay`, `fuse`, `lever`, `objective`, `entity`, `navigation`,
`reset`, `room`, `spawn`, `round`. The broad query returned 551 nodes and was
truncated. A narrower `maze generator` DFS returned all 52 nodes and 86 edges,
including `spawnProp`, `wallPart`, `floorTile`, `deepBeam`, `bfs`, and
`makeFurnitureHeap`, with source locations in
`ServerScriptService/Level 1 Systems/MazeGenerator.Script.lua`. The graph also
contains historical proposed fixes and other levels. Graph relationships and
repository copies were treated as navigation clues; the fresh Studio sources
are the evidence for current behavior. Querying did not rebuild the graph or
incur a new extraction cost.

## The current game loop

`GameManager` owns lobby membership, launching, world preparation, character
streaming, the elevator ride, participant lifecycle, death/reentry, completion
and transfer back to the lobby or onward to the next level. Public stations
reserve a separate server of this same place. Studio has a local-round fallback
because TeleportService cannot provide the published transfer there.

Level 1 is different from Levels 2 and 3: it has an attribute-driven, one-shot
`MazeGenerator` Script rather than a module with Build/Cleanup methods.
`GenerateWorld=true` releases generation. The generator publishes shared grid
and lighting attributes and only raises `WorldGenerated=true` after the maze,
elevator, spawn markers and lighting controllers have been created. GameManager
waits up to 180 seconds, connects the elevator and requires `MazeStart`.

`PuzzleManager` starts only for a Level 1 `RoundActive=true` round and waits
briefly for `DecorReady`. It freezes the actual `InRound` party rather than all
server players. For party size 1 through 6, the live allocation is:

| Party | Boxes | Paired levers | Relay spawns at default multiplier |
| --- | --- | --- | --- |
| 1 | 1 | 1 | 3 |
| 2 | 1 | 1 | 3 |
| 3 | 2 | 2 | 6 |
| 4 | 2 | 2 | 4 |
| 5 | 3 | 3 | 6 |
| 6 | 3 | 3 | 6 |

Each box needs one fuse. Parties of at most three get 1.5 times the default
relay supply, rounded up, without increasing the number of fuses needed to win.
These live rules supersede old header comments claiming one circuit per player.

The sequence is extraction from a noisy wall relay, carrying a visible fuse,
following a colored cable toward its distribution box, depositing a fuse, then
following the reversed current toward the paired lever. Each powered box raises
flicker/danger and may relocate the entity into the objective's area. When all
boxes are filled, the maze enters continuous red ALERT mode and every lever
unlocks. **Levers latch for the whole round**; the former timed simultaneous
lever objective is no longer live behavior. Deaths or departures do not undo
completed boxes or levers.

The final lever sets the finale speed multiplier to 1.3, starts the power-down
recording and its matching shutdown wave, and then opens the outer-border exit.
The maze stays dark in ESCAPE. Every escapee is moved to an isolated safe cabin,
anchored, marked `Escaped`, and individually announced. GameManager ends the
round when no living participant remains inside. A successful ordinary Level 1
round offers the existing result window and Level 2 continuation.

Extraction ownership is tied to the current character/session. Death during
the short relay-release animation drops that one fuse rather than crediting a
new body. Carried inventory drops on death/removal where verified floor exists.
The server independently rejects nonparticipants, escaped/dead characters,
disabled/stale prompts, excessive distance and blocked required line of sight.
The existing client hold duration is not itself proof of server-side hold time;
this facelift does not change that inherited interaction policy.

## Random topology and spatial contracts

The live defaults are GRID=40, CELL=24 studs, wall height=14, wall thickness=2:
a 960 by 960 stud maze. `MasterConfiguration.Effective` can override grid size,
cell size, openness and pit count at the next build. Rooms must scale in X/Z
when CELL changes; wall height and floor elevations retain their live values.

Generation first carves a connected cardinal grid using a random recursive
backtracker implemented with an explicit stack. A Perlin density field removes
additional walls, creating loops and broader pockets. It then guarantees a
7 by 7 cell plaza, opens a 5 by 5 cell area around the central elevator, and
opens the interior of randomly placed pit zones. The elevator shell replaces
the four ordinary grid walls at its own cell. A flood-fill repair starts just
east of the elevator and removes separating walls until every non-elevator
cell is reached.

The current layout is generated at runtime, not imported as one static maze.
The facelift preserves the exact authoritative topology block. Blender exports
reusable room components and room arrangements; Roblox chooses a compatible
room variant for every generated cell. Open sockets use N(+Z)=1, E(+X)=2,
S(-Z)=4, W(-X)=8. The bit is set only when that grid edge is open. Border sockets
never open outside the level, and both sides of every shared opening agree.

Two inward half-walls join to the existing full two-stud internal wall. Each
half-wall is one stud thick, with its outside edge on the cell boundary and
interior face one stud inside. Floors top out at Y=0; ceilings keep their
existing underside at Y=14. Columns and room props stay outside the central
square and the six-stud cardinal walking lanes. This is a grid-compatible kit,
not a replacement navigation algorithm.

The default pit zone is 6 by 6 maze cells, hence 144 by 144 studs. The actual
hole formula gives **11 by 11 twelve-stud holes per zone**, divided by one-stud
beams, over a fifty-stud drop. An old comment says 36 holes; that comment counts
maze cells rather than the physical hole lattice and is not the live geometry.
Pit touch/death protection, lethal bottoms and entity-only barriers remain
owned by the existing generator. No prefab floor or decorative collider may
cover a pit hole. In pit cells the renderer displays only ceiling and closed
perimeter shell walls; it skins the actual narrow beams and shaft bands.

## Placement, wiring and navigation coupling

Puzzle placement is not independent of the world geometry. It probes floor
and vertical walls using rays whose include filter is `Workspace.Maze`.
Eligible cells exclude pits and the elevator neighborhood. Wall stations share
an avoidance list, require clear space from decor bounding boxes, and relax
spacing over bounded retries. Boxes and levers have fallback passes followed by
count assertions; every box must have exactly one lever and one visible circuit.
The exit prefers an actual outer-border wall.

Cable routing also probes the same grid geometry. Its ordered `ObjectiveCable`
segments carry `SegmentIndex`, `Vertical`, circuit color and box/lever pairing
metadata. `Level 1 Cable Current` reconstructs those ordered paths on the client
and animates a bounded number of beads through one Heartbeat connection. Power
reverses only the current circuit. The visual facelift must retain those parts,
attributes and directions, even when a Blender mesh skins a segment.

The entity uses its own memoized cardinal grid rather than Roblox navmesh for
ordinary travel. It samples floor at cell centers and rays between adjacent
centers, excludes pit cells and caches symmetric edges. Startup learns one row
per frame. Runtime BFS returns corridor-center waypoints; direct chase uses
three body-width rays, and obstructed or pit-crossing pursuit falls back to the
grid. A 1.2-second watchdog replans after insufficient motion. An unreachable
grid target currently falls back to a straight MoveTo, so engine navigation
checks must observe retries and barriers rather than infer success from code.

Sight, flashlight attraction, noise investigation, the spotting howl, short
tracking memory, search, ballistic lunge, pit-edge shove and cinematic capture
remain unchanged. The lurk destination may be the current fuse/box/lever/exit
objective rather than a random room. Decor is solid to players but in the Decor
collision group that does not block the entity. Large heaps have dedicated
invisible sight blockers rather than relying on furniture query surfaces.

The Blender visuals have query and touch disabled. Original Maze collision/
query Parts remain authoritative and are hidden only in the preview. Imported
extra pillar/prop colliders use Decor, remain solid to players, and are disabled
when the corresponding room detail is suppressed for pits/elevator. A live
camera/first-person and raycast check is still required: invisible structural
proxies can change third-person camera occlusion even with unchanged physics.

An inherited entity relocation caveat remains: `entityToArea` rejects pits and
requires at least two cells of distance from the objective position, but it does
not explicitly test the chosen position against every other living teammate.
No multiplayer safe-distance pass is claimed from this source inspection.
Likewise, maze flood-fill connectivity includes pit cells while the entity grid
excludes them; entity reachability around every generated pit arrangement needs
runtime evidence.

## Assets, rendering and the preview boundary

The authored kit contains the socket-compatible room family and distinct
maintenance/office/records pockets. Chair, table, telephone, cardboard pile,
printer and grandfather clock templates replace the existing decor builders,
so the current scatter, heaps, scaling, spacing and clock audio still apply.
The shared ImageGen direction feeds one carpet, wallpaper and acoustic-ceiling
PBR palette. Maps include color, normal and roughness; the asset pipeline
records native Blender geometry, exported chunks, checksums and actual Roblox
mesh/image IDs. Derived normals/roughness provide authored detail, not a claim
of measured material scans.

Dynamic objective hardware retains its exact authoritative Parts, prompts,
lights, tweens and welds. Blender relay-door, fuse and lever-base meshes plus
the shared authored metal panel skin their surfaces. Moving skins use native
welds with no new colliders. The sphere lever knob uses the already exported
red sphere chunk. Circuit colors and neon hardware states remain authoritative.
Deep-shaft wall tint is applied to SurfaceAppearance so PBR does not erase the
original falloff into darkness.

Room-catalog fixture meshes are suppressed at runtime. The actual sparse
fixtures from MazeGenerator still own dead/working lamps, hum tags, relay
clusters, flicker, ALERT, POWERDOWN and ESCAPE. Rendering an illuminated fixture
in every prefab would have changed those exploration clues and the blackout.

The new developer button is local UI at the Level 1 queue room; a normal player
does not create it. The server access controller validates the exact owned
anchor, living lobby state, distance, cooldown and the existing strict developer
allowlist. `ServerStorage.Level1BlenderPreviewLaunch` independently rechecks
developer authority, busy state and complete assets. Missing component models
or any socket mask fails closed before a round starts.

Published previews reserve a separate server and pass
`Level1BlenderPreview=true` through the existing arrival packet. The destination
rechecks Level 1, asset readiness and **every actual arriving participant's**
developer authority before setting `Level1BlenderPreviewActive`. The public
station and normal campaign paths continue to use the existing visual builder.
Studio uses the real local-round preparation path, including entity, puzzle,
streaming, elevator and the normal HUD. The preview ends at Level 1 and does not
fire the campaign reward completion event.

## Reset, bounded work and verification limits

The existing puzzle session owns connections, carried-fuse character records,
relays, boxes, levers and circuit folders. Reset invalidates the session,
disconnects its connections and destroys its own generated folder. Normal
post-win display holds solved dressing until its result window closes.
GameManager destroys only its named round-owned world objects, clears shared
attributes, parks/disables the Level 1 entity scripts, and rearms the one-shot
MazeGenerator for another local/fallback round.

The new renderer owns and disconnects its listeners when that generated Maze
is destroyed. It yields during room assembly; it adds no perpetual render or
navigation loop. Preview cleanup clears its flag and room count. The Studio
error path revokes RoundActive, the post-win flag and reentry authority before
trying protected lobby recovery, and always releases its launch lock. Published
packet construction and teleport dispatch share a pcall so setup exceptions do
not strand that lock.

Offline evidence: the official Luau 0.737 compiler accepts the proposed
GameManager, MazeGenerator and BlenderRoomRenderer. The runnable
`tools/tests/test_level1_blender_preview.py` executes the actual authority,
readiness, socket and continuation functions: **51 checks passed**, including
all sixteen masks, reciprocal openings, borders, denied/dead/busy users,
missing assets, public continuation and preview completion. It also confirms
that the entire random-topology block equals the fresh live baseline. The
separate access/button fixture exercises 26 access gates and an unauthorized
client path. These are code checks, not gameplay certification.

Live runtime evidence supplied by the parent on 2026-10-02: two separately
generated Studio preview rounds each passed the 61-check runtime probe. All
1,600 room cells were connected and the three bounded engine path samples
returned Success in each round. The probe reported different socket edge
counts, 2,068 and 2,087, demonstrating two different generated layouts. Two
reset checks also passed after an actual character death.

The second preview exercised the actual puzzle interaction and escape path in
a single-player assisted Studio run. The existing P developer cheat paused the
entity and QA moved the character to objective proxies; the parent then used
the actual E interactions. Relay extraction removed ContainsFuse and created
CarriedFuseVisual, insertion set Powered, the cable light phase became ALERT
and enabled the lever, and the lever increased entity speed to 1.3. The final
phase became ESCAPE with the exit sign online. Actual character navigation
into the elevator trigger set Escaped and entered its safe cabin. The round
returned to the lobby with InRound, RoundActive and the preview flag false,
the Blender room count cleared, and no Level 2 continuation. This verifies the
assisted interaction sequence and reset; it does not establish an unassisted
playthrough or active chase difficulty.

The parent also clicked CreateParty through the actual public queue UI. The
normal round had its world, decoration and original objectives, while the
preview flag was false and no Blender rooms or preview meshes were present.
This is live evidence that the public visual-builder path remains separate.

Studio Stats reported approximately 4.77 GB during a facelift round and
4.59 GB during the public round. Those readings include Studio and the existing
whole place; they are not standalone-server memory budgets. Engine path,
heartbeat and memory samples do not measure server CPU or establish mobile/GPU
performance. Multiplayer, real published reserved-server transfer, full active
entity chase/lunge behavior, mobile performance and server CPU remain
unverified. The parent records final visual inspection and publication in the
task QA/release records rather than inferring them from this source analysis.

## Final authoritative Edit export

After the parent's runtime checks and temporary QA cleanup, the read-only
`tools/export_level1_facelift_verified.py --run` captured the five changed
scripts and the entire imported kit from Studio Edit into
`artifacts/level1-facelift-20261002/verified-studio`. Every transferred chunk
rechecked the current source/editor or complete kit fingerprint, followed by
final consistency checks. All five Source/editor pairs matched and their
SHA256 values also matched the current repository source mirrors. This helper
wrote only evidence artifacts and performed no Studio writes or native backup.

The verified kit has 39 component models, 34 room models, 498 MeshParts,
176 SurfaceAppearance instances and 51 explicit colliders across 1,215
instances. Its Ready and Complete attributes are true. Its 61 distinct mesh
asset IDs and nine PBR texture IDs exactly match the upload receipt sets.
`Level1BlenderKit.instances.json` records paths and child-index routes,
classes, import/source attributes, transforms, collision properties and
SurfaceAppearance maps; the child-index routes distinguish duplicate instance
names. This asset/property parity is separate from publication and visual
quality certification.

## Exact source ownership

- Existing live Scripts: `ServerScriptService.Level 1 Systems.MazeGenerator`,
  `PuzzleManager`, `EntityAI`, `EntityKill`, `EntityAnimation`, and
  `ServerScriptService.GameManager`.
- New renderer ModuleScript: `ServerScriptService.Level 1 Systems.BlenderRoomRenderer`.
- Shared authorities: `ReplicatedStorage.MasterConfiguration`, `DevAccess`,
  `DeathAdvice`; `ServerScriptService.PlayerProtection`, `ReentryPlacement`,
  `Round Completion Routing`, `Round Loading Runtime`.
- Relevant clients: `StarterPlayer.StarterPlayerScripts.Level 1 Cable Current`,
  `Level 1 Sound Controller`, shared `SoundController`, `RoundUI`,
  `Round Entry Client`, `Round Exit Client`, `DevCheats`.
- Native imported kit: `ServerStorage.Level1BlenderKit`, with Components and
  Rooms. The renderer uses Ready and per-room OpenMask/RoomRole metadata.
- Reviewable existing-script candidates were derived from the exact live
  baseline in `drafts/level1-facelift-20261002`. They are not proof of a live
  installation; the parent's CAS/readback records determine final parity.
