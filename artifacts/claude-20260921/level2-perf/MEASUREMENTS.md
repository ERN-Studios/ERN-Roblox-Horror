# Level 2 performance — measurements 2026-09-21 (Trello Zpj0Gkbb)

Device: the owner's desktop PC, Roblox Studio play session (server + one client in one
process group), window 1539x809, graphics quality Automatic, **Studio in the foreground**.
Seed pinned 1182081016 (resolved 1182604661, layout attempt 6), one player, one pump started,
five Pool Foam active, no Pool Slide. This is NOT a phone/tablet or a production server.

## Client (12 s, 720 RenderStepped frames)

| Metric | Value |
|---|---|
| frame time mean / p50 / p95 / p99 / max | 16.7 / 16.7 / 18.4 / 20.2 / 22.1 ms |
| frames over 33.4 ms | 0 |
| network receive / send | 0.0 / 5.1 kbps (steady state) |
| `Stats.InstanceCount` (whole client datamodel) | 123,313 |
| streamed-in Level 2 world descendants | 74,673 |
| … of which `Texture` | **44,923** (60 %) |
| … BaseParts / MeshParts | 27,577 / 2,355 |
| … parts with `CastShadow = true` | 21,261 |
| … lights / with `Shadows = true` | 154 / **154** |
| memory (Studio process): total | 4,182 MB |
| … LuaHeap / Script / Instances / GraphicsTexture / PhysicsParts / GraphicsParts | 703.5 / 273.3 / 300.7 / 226.6 / 136.0 / 68.2 MB |

The "about 15 FPS" sample in the review (66.65 ms mean) was taken with Studio in the
background; with the window focused the same PC holds the 60 Hz cap. It is confirmed as
a throttling artefact, not a gameplay frame rate.

## Server (same round)

| Metric | Value |
|---|---|
| `Stats.HeartbeatTimeMs` / `PhysicsStepTimeMs` | 0.98 / 0.13 ms (entities idle round a standing player) |
| Heartbeat interval during a Pool Slide chase (A/B run) | mean p50 16.6 ms, p95 19.7–28.2 ms |
| world descendants | 74,654: Texture 44,923 · Part 25,175 · MeshPart 2,355 · PathfindingModifier 1,052 · CFrameValue 390 · SurfaceAppearance 209 · PointLight 138 · Bone 110 |
| models with `ModelStreamingMode = Persistent` in the world | 0 (the Pool Slide model is made Persistent at spawn) |
| moving primitives | 33 |
| layout attempts for this seed | 6 (layout only; the world is built once) |
| Pool Foam separation pass | 0.006–0.2 ms |

`StreamingMinRadius`, `StreamingTargetRadius`, `StreamingIntegrityMode`,
`StreamOutBehavior` and `Lighting.Technology` are not readable from the MCP thread
(capability `RobloxScript`); read them in Studio's Properties panel.

## Reading

- On this PC nothing in Level 2 is frame-bound or server-bound. The reports of lag are
  therefore about weaker devices, which this session cannot measure (see handoff: hardware).
- The one structural outlier is the **Texture instance count**: every tiled part gets one
  `Texture` per face, six by default, although one to three faces can be seen. That is 60 %
  of what a phone has to receive, hold in memory and stream in and out. Addressed by culling
  provably hidden faces (switchable), measured before/after with
  `Level 2 State.Level2_WorldDescendants` and the fixed-camera image diff in this folder.
- Every one of the 138–154 lights casts shadows. Roblox drops local-light shadows by itself
  at low quality levels, so the gain on a phone is unknown without a device; left as an
  owner/art decision with the number attached.
- New load-time readbacks: `Level2_LayoutSeconds`, `Level2_BuildSeconds`,
  `Level2_WorldDescendants` (and the same three for Level 3) on the level state folders.

## After hidden tile-face culling (`Performance.CullHiddenTileFaces = true`, commit 60a8d4b)

Same seed, same round state: world descendants 74,086 → **71,214**, `Texture` 44,923 → **42,051**
(−2,872, −6.4 %); build 2.27–2.36 s → 2.83 s (one sample each; not a regression signal by itself).
Fixed-camera tour (12 shots, `shots-client.luau`), pixel diff of the 3D viewport, threshold 24/255:

| Pair | stable shots 02,03,05,06,08–12 | shots 01, 04, 07 |
|---|---|---|
| unchanged run A vs unchanged run B (noise floor) | 0.00–0.17 % pixels differ | 77 % / 89 % / 3.4 % — capture timing and stream-in order, present without any change |
| unchanged vs culled | 0.00–0.13 % | 81 % / 5.7 % / 0.00 % — same artefacts (shot 01 caught the camera still at the pump; shot 04 differs by which distant arch had streamed in) |

No visible change from the culling in any stable viewpoint.

## Where the instances really are (after culling, same seed)

| Family | Textures | Parts | Faces/part |
|---|---:|---:|---:|
| `Level 2 Arch Rib n` | 16,352 | 5,518 | 3.0 |
| `Level 2 Corridor Arch Spandrel n` | 8,192 | 4,096 | 2.0 |
| `Level 2 Arch Rib n face-n` / `face n` | 7,680 | 3,840 | 2.0 |
| `Level 2 Vault Strip n` | 1,533 | 1,344 | 1.1 |
| everything else (props, treads, columns, ledges, lintels, walls, ceilings…) | ≈ 8,300 | — | — |

**The corridor vault arches are 32,224 of 42,051 textures (77 %) and 13,454 parts — about half
of every part in the level.** Each arch is built from many short box segments so it reads as a
curve, and each segment carries two or three tile textures. Face culling cannot touch that (all
three faces of a rib are visible). The lever is the arch itself: one skinned/CSG or imported
MeshPart per rib (or per corridor vault) with the tile as a SurfaceAppearance/MaterialVariant
would take the world from ~71k to roughly 26k descendants. That changes how the arches are
made, so it is an art + owner decision with a builder change to follow — see the handoff.
