# Level 2 arch-mesh pilot — measurements 2026-09-22 (ARCH_MESH_PILOT_20260922)

Device: the owner's desktop PC, Roblox Studio play session (server + one client in one
process group), window 1539x809, graphics quality Automatic, **Studio in the foreground for
the frame samples**. Seed pinned `1182081016` (resolved `1182604661`), one player,
entities paused during the counts and frame samples. This is NOT a phone/tablet or a
production server.

## What the switch changes

`Level 2 Configuration.Performance.ArchMeshRibs` (default **false**; per-session override
`workspace:SetAttribute("Level2ArchMeshRibs", true/false)`). ON, the standard corridor rib
family — the 3.2 × 2.2 band swept round the elliptical arc, VerticalScale 1.9, 26 segments at
radius 13.2 — is one `MeshPart` per arch instead of 26 textured Parts. The mesh is the LOOK
only (`CanCollide = false`): its bounding box spans the whole opening, and the Pool Foam /
Pool Slide navigators clear a body volume with `GetPartBoundsInBox` (`RespectCanCollide`),
so a colliding mesh read as a wall across every corridor ring. The collision the Part ribs
gave where anything can reach it — the feet, floor to ~10.8 studs up — is kept EXACTLY by
rebuilding those four segments per side as invisible, untextured Parts (`Level 2 Arch Rib
Foot n`). The Vault Strip shell behind the ribs, the slender `.face` portal arches, the
spandrels, the kids-hall ribs and the Ring Corridor rings are untouched.

Where the mesh comes from, in order: (1) a `MeshPart` template already in ServerStorage
(`Level 2 Arch Rib Mesh <key>`), (2) an uploaded asset id in
`Performance.ArchMeshRibAssets[key]`, (3) an `EditableMesh` built by the World Builder from
the same math. (3) needs the experience's **"Allow Mesh & Image APIs"** security setting at
runtime (it failed in the play session with exactly that message; Edit-mode plugin context
has it, which is how `WorldBuilder.EnsureArchRibMeshTemplates` built the two templates from
the command bar). Without any source the ribs stay Parts and the world records the wanted
keys in `Level2_ArchRibMeshMissingKeys`.

Two family keys exist on this layout (corridor width 34, DoorWidth 30 → radius 13.2; channel
depths 1.5 and 1.8): `r13.20_vs1.90_fd1.50_a3.20_d2.20_s26`, `r13.20_vs1.90_fd1.80_a3.20_d2.20_s26`.
Template size 28.6 × 30.0/30.3 × 3.2 studs; 108 vertices, 212 triangles; the same geometry is
exported for upload by `tools/level2_arch_rib_obj.py` (the two `.obj` files beside this note;
extents X ±14.30, Y −3.79..26.18, Z ±1.60; UVs in 7-stud tiles; pivot = arc centre =
corridor centre + 1 stud up; X across, Y up, Z along the passage).

## Same seed, same round state

| | A: Part ribs (switch off) | B: mesh ribs, colliding (rejected) | **B″: mesh ribs + 4 feet/side (shipped)** |
|---|---:|---:|---:|
| `Level2_WorldDescendants` | 71,214 | 54,116 | **55,444 (−22.1 %)** |
| Parts (BasePart, not MeshPart) | 25,223 | 20,893 | **22,221 (−3,002)** |
| MeshParts | 2,355 | 2,521 | **2,521 (+166 ribs)** |
| `Texture` instances | 42,051 | 29,103 | **29,103 (−12,948, −30.8 %)** |
| standard rib Parts (`Level 2 Arch Rib n`) | 5,518 | 1,202 (kids halls) | 1,202 (kids halls) |
| mesh ribs | 0 | 166 | **166** |
| invisible rib feet | 0 | 0 | **1,328** (8 per rib) |
| `.face` portal ribs / spandrels / Vault Strips | 3,840 / 4,096 / 1,344 | same | same |
| textures on rib parts | 24,032 | 11,084 | 11,084 (portal faces + kids ribs) |
| `Level2_BuildSeconds` | 1.86 | 2.62 | 1.58 (one sample each; template adoption) |
| client frame time, corridor view, foreground (8 s) | mean 16.67 ms, p50 16.7, p95 18.3, p99 19.2, max 19.9 | mean 16.59, p50 16.7, p95 18.4, p99 19.8, max 23.7 | not re-sampled (same content as B plus 1,328 untextured parts) |
| server `HeartbeatTimeMs` / `PhysicsStepTimeMs` | 1.19 / 0.35 | 1.19 / 0.37 | — |

Reading: on this PC neither path is frame- or server-bound (60 Hz cap both ways). The gain
is the instance count a weaker device has to receive, hold and stream: 15,770 fewer
descendants and 12,948 fewer `Texture` instances per Level 2 world, out of the arch family
that held 77 % of all textures. The remaining rib textures are the slender portal faces
(7,680) and the kids-hall ribs (3,404), both outside this pilot on purpose.

## Collision and navigation (B″, rib 1.1)

- Rays through the opening along the passage: miss (mesh and feet).
- Horizontal rays into a foot from the arc centre: y=0 hit @12.09 (the Part rib gave ~12.10),
  y=6 @11.71, y=9 @11.19, y=11 miss, y=14 miss — the feet reach y≈9.8 in rib space, 10.8
  studs above the floor; above that only the Vault Strip shell stands, as before.
- `GetPartBoundsInBox` (RespectCanCollide) of a 6-stud body box at the corridor centre: 0
  colliding parts (with B's colliding mesh it was 1 — the whole rib — which is why B was rejected).
- Live: two pumps pulled with the dev pair, Pool Foam went Foreshadow → Pressure, the Pool
  Slide spawned on its first probe (`Level2_PoolSlideSpawnCount 1`, `SpawnProbeCount 1`),
  went CHASE with `PathStatus MOVING`, moved, reached ATTACK and killed the solo player
  (recorder log in the handoff). Same on B′ (three feet per side). No console errors.

## Visual

`screens/level2-corridor-A-part-ribs.jpg` and `level2-corridor-B-mesh-ribs.jpg` are the
previous session's tour shot 6 (a hall, portal in the distance) for A and B.
`screens/level2-rib-closeup-B-mesh.jpg` is rib 1.1 from 16 studs down its corridor at FOV
100 (mesh); `level2-rib-closeup-A-parts.jpg` is the same camera on the Part ribs. The mesh
rib reads as one continuous tiled band; the Part rib is the same silhouette in 26 segments
with visible seams. Codex owns any further art judgement (tile alignment on the soffit, a
bevel, a dedicated rib texture) — the OBJ is the editable source for that.

## Not measured / open

- A phone or tablet (two thirds of the players); stream-in time; memory. Not measurable here.
- Production runtime needs an owner step: either upload the two OBJs and set
  `ArchMeshRibAssets`, or enable the Mesh & Image APIs in Game Settings → Security so the
  server may build the EditableMesh itself. Until one of those, the switch ON in a live
  server falls back to Parts (recorded in `Level2_ArchRibMeshMissingKeys`), which is the
  reason the config default stays **false**.
- Object-backed templates are not saved in the place file; `EnsureArchRibMeshTemplates`
  rebuilds them from the Edit command bar in a Studio session (this session's two templates
  are in ServerStorage now).
