# Level 2 instance budget for one generated round (World Builder, Layout Generator, Configuration)

The live config is `CullHiddenTileFaces = true` and `ArchMeshRibs = true` (CF:164, CF:179). At that config the reference seed builds about **56,000 world descendants**. **Corridor tunnels hold about 58% of them.** The single biggest family is the portal surround at each tunnel mouth: 32 spandrel strips, a header and a 30-piece face arch. It accounts for **24,192 instances (43%)**, and none of it collides, is touched or is queried.

Abbreviations:
- **WB** = `ServerScriptService/Level 2 Systems/Level 2 World Builder.ModuleScript.lua`
- **LG** = `…/Level 2 Layout Generator.ModuleScript.lua`
- **CF** = `…/Level 2 Configuration.ModuleScript.lua`

All three are clean at HEAD.

---

## 1. Earlier measurements

| Date / source | World descendants | Detail |
|---|---:|---|
| 2026-09-21, before culling. `artifacts/claude-20260921/level2-perf/MEASUREMENTS.md:34` | **74,654** | "Texture 44,923 · Part 25,175 · MeshPart 2,355 · PathfindingModifier 1,052 · CFrameValue 390 · SurfaceAppearance 209 · PointLight 138 · Bone 110" |
| same, client (`:15-22`) | 74,673 streamed; `Stats.InstanceCount` 123,313 | 21,261 parts with CastShadow; "lights / with Shadows = true 154 / **154**"; frame time p50 16.7 / p95 18.4 / max 22.1 ms (desktop PC, Studio in the foreground) |
| after culling (`:61`) | 74,086 → **71,214** | "Texture 44,923 → 42,051 (−2,872)" |
| family table (`:76-82`) | — | "Arch Rib n 16,352 tex / 5,518 parts · Corridor Arch Spandrel 8,192 / 4,096 · Arch Rib face 7,680 / 3,840 · Vault Strip 1,533 / 1,344 … **The corridor vault arches are 32,224 of 42,051 textures (77 %) and 13,454 parts**" |
| seed 738163940. `artifacts/claude-brief-20260921/level2-runtime.json`, `docs/REVIEW_FOR_CLAUDE_2026-09-21.md:83` | **71,596** server / **53,989** client | 40 halls, 66 corridors, attempt 8, 5 spiral rolls (2 built, 3 rerouted) |
| same, background frame sample. `level2-frame-sample.json`, `REVIEW…:105` | — | "mean 66,65 ms, p95 68,88 ms … omtrent 15 FPS. Studio kørte i baggrunden" (Studio was in the background, so this is throttling, not a real frame rate) |
| arch mesh pilot. `artifacts/claude-20260922/level2-arch-mesh/MEASUREMENTS.md:44-52` | 71,214 → **55,444** | 166 mesh ribs plus 1,328 invisible feet; Texture 42,051 → 29,103 |
| uploaded arch assets. `artifacts/codex-polish-20260923/README.md:83-87` | 71,771 → **56,001** | Texture 29,103 · Part 22,176 · MeshPart 2,521 · 166 mesh ribs (157 at fd1.50, 9 at fd1.80) |
| README.md:347, 360 | ~70,000 / 70,960 | "world built at 3.9 s, client acked 3.2 s after poolaccess" |
| CF:173-178 | 56,001 vs 71,771 | Arch mesh ribs have been on since 2026-09-23 |
| Server cost. `docs/POOL-SLIDE-SERVER-USAGE-2026-09-09.md:21,24,32` | — | Heartbeat 1.10 ms with Pool Foam only; the Pool Slide adds ≈1.3 ms/frame; 54.4 vs 58.3 server FPS. CLAUDE.md:132-133: the old Pool Slide used "78% … (13 FPS, 59 with it paused)" |

- **Draw calls and triangles:** no Level 2 draw-call measurement exists anywhere. The only triangle figure is the rib template: "108 vertices, 212 triangles" (arch-mesh MEASUREMENTS:35).
- **Hardware:** no phone or tablet was ever measured.

---

## 2. Build path and multipliers

**`GenerationAttempts` (CF:49) does not multiply instances.**
- Attempts only build Lua tables (LG:928-948).
- `WorldBuilder.Build` (WB:5890) runs once per accepted layout. MEASUREMENTS:37 confirms: "layout only; the world is built once".

**Build loop:**
- Halls: WB:5996-6202. Each hall gets floor (6011), ceiling (6013), role-specific dressing (6015-6169), `lightHall` (6171-6173), 1 navigation node and 4 patrol nodes (6175-6198).
- Hall walls: WB:6205-6218.
- Corridors: WB:6224-6232.
- Pumps: WB:6252-6255. Arrival: WB:6273-6274.
- Pathfinding pass (WB:6317-6332): every BasePart whose name contains "Ceiling", "Skylight" or "Roof" gets a `PathfindingModifier`.

**Primitives and their multipliers:**
- `part()` = 1 Part (WB:49-62).
- `tiledPart(faces=nil)` = Part + **6 Textures** (WB:92-96, 64-76).
- `visibleFaces` (WB:84-90) narrows only the call sites that pass a face list.
- Kids surfaces (`surfaceFor`, WB:194-201) = Part + 2 kids textures by default (WB:163-173), or the faces passed in.
- `makeRail` = 1 bar + (max(2, ⌊L/9⌋) + 1) posts (WB:1913-1930).
- `makeStairFlight` step = Part + 3 Textures (WB:1947-1949). Kids steps are Part only.
- Water is `Terrain:FillBlock` (WB:349-354), **0 instances**: one region per hall, per corridor, plus the kids pool.

---

## 3. Per corridor (tunnel segment)

Inputs: width 34 (CF:57) gives arch radius 13.2 and vault radius 14.1. Channel depth 1.5 (1.8 if drainable).

| Component | Code | Count (standard / kids-styled) |
|---|---|---:|
| Water floor | WB:4725-4729 | Part + 1 Texture = 2 |
| Side ledge + submerged curb | WB:4766-4788 | 2 × (Part + 5 Textures) = 12 |
| 2 walls | WB:4798-4813 | 2 × (Part + 1 Texture) = 4 |
| Ceiling | WB:4814-4817 | Part + Texture + PathfindingModifier = 3 |
| Ribs: rings = clamp(⌊(gap+4)/22⌋, 3, 7) (WB:4820); steps = max(14, ⌈13.2×1.9⌉) = 26 (WB:1785) | WB:4824-4837 | **mesh:** 1 MeshPart + 8 invisible feet (WB:1815-1832) = **9/ring** → 27. **Kids** (mesh path skipped, WB:1794): 26 × (Part + 2 Textures) = 78/ring → 234. Mesh switch off: 26 × 4 = 104/ring |
| Vault strips: steps = max(12, ⌊14.1×1.5⌋) = 21 | WB:1880-1909 | 21 × 2 = 42 / kids 21 × 3 = 63 |
| **Portal surround, per mouth.** Header (WB:4888-4890) + 32 slats (WB:4868, 4892-4913) + face arch of max(28, ⌈14.1×2.1⌉) = 30 steps (WB:4915-4927); each is Part + 2 Textures, all `CanCollide/CanTouch/CanQuery=false` (WB:4882-4884, 4926) | WB:4850-4928 | (1+32+30) × 3 = 189 per mouth → **378** |
| 2 lamp emitters + 2 PointLights | WB:4932-4946 | 4 |
| Pressure door + stripe (grand-hall corridors only) | WB:4956-4967 | +2 |
| Drain steps (only if depth > 2.5; drainable depth is 1.8, CF:118) | WB:4733-4743 | 0 |
| **Total** | | **472 standard / 700 kids** (3 rings); SharedWall corridors = 4 (WB:4654-4682) |

**Per stud of tunnel:** the instance count is fixed per corridor. Only the ring count scales with length:
- Each extra ring is +9 instances (+78 kids) for every 22 studs beyond 66.
- Measured 166 standard ribs over 55 standard corridors means 3.02 rings each, so gaps are ~60-84 studs.
- That works out to ~5.6-7.9 instances per stud (~0.28 m), of which **378 per corridor is the two mouths**.

**Back-derived from measured counts (seed 1182081016):**
- 3,840 face-arch parts / 60 = **64 tunnels**. 4,096 spandrels = 64 × 64. 1,344 strips = 64 × 21.
- 1,533 − 1,344 = 189 extra strip textures = 9 kids corridors × 21.
- Kids and ring parts: 1,202 = 27 × 26 + 20 × 25, with textures 3,404 = 27 × 52 + 20 × 100. That gives **27 kids-corridor ribs and 20 Ring Corridor rings**.

---

## 4. Per hall shell and per room type

**Shell (every hall):**

| Piece | Code | Count |
|---|---|---|
| Hall model | — | 1 |
| Floor | WB:358-396 | Part + 1 Texture = 2 |
| Light seals + shadow coves | WB:864-923 | 8 Parts. These exist only to hide light leaking through part seams |
| Ceiling pieces | WB:927-1073 | Each slab = Part + Texture + PathfindingModifier; each skylight pane = Part + PathfindingModifier. Lines pattern with 3 slots = 10 slabs + 3 panes |
| Walls | WB:228-343 | Slabs: Part + 1-2 Textures. **Lintel and sill use faces=nil → Part + 6 Textures each** (WB:312-314, 319-321). Sills only in wet halls (bottomY < −4) |
| Nodes | WB:6175-6198 | 5 |

- 1,052 PathfindingModifiers ≈ 64 corridor ceilings plus ~24.7 ceiling pieces per hall, which puts the average ceiling at about **71 instances**.
- 3.3 doors per hall gives walls of about **67 (wet)**, 45 (dry) and 31 (kids).
- Shell totals: **~146 wet hall**, ~120 arrival, ~145 kids (kids ceiling is ~110: round skylight modules = Union + Texture + PathfindingModifier + glass, WB:808-850).

**Room types** (shell + set pieces):

| Type | Set-piece cost | Typical total |
|---|---|---:|
| Column halls: Pillar Basin, Diving Well, Column Forest, Galleries, Arch Tunnel, Skylight (WB:6039-6052, 6096-6098). Columns per row = clamp(⌊long/38⌋, 2, 8) (WB:1556) | Many skipped by door and route guards (WB:1569-1571) | 300-550 |
| … + edge walkway (50%, WB:5355-5408) | 4 × 12 = 48 | |
| … + decorateLargeHall (area ≥ 12k, WB:5447-5701) | diving tower 97 (112 with 4 boards), slide kit ~190, play tower ~225, overlook 71, island 35, floats 4-12 | |
| … + dressHall (WB:5015-5116) | ~10 | |
| Ring Corridor (WB:6053-6083) | 3-7 rings × 25 steps × (Part + 4 Textures) = **125/ring**; no large-hall dressing (WB:6134) | 530-1,080 |
| Spiral Stair Well (WB:6086-6095) | 53 treads × 4 + 23 posts + 22 rails + mast 7 = **264** | 400-700 |
| Porthole | ≤3 × (Part + SurfaceLight) (WB:6099-6125) | ~200-450 |
| Pump Station, outside kids (WB:5242-5345) | 7 decks × 6 = 42; crates 3-5; gauge 4; tower ~85; stripes 4 → ~139; plus the pump model **77** (WB:4312-4647, scaled 0.34) | ~350 |
| Kids: Ball Pit room (WB:3723-3795) | Full pit hex-packs 371 + ~186 + ~37 ≈ **594 decorative balls** (non-colliding, WB:3766-3770) + 8 structure; plus 9 crawl-frame parts | ~760 |
| Kids: Slide Tower (WB:3829-3941) | tube 99 + ~22 | ~270 |
| Kids: Splash (WB:1076-1121, 3797-3816) | 21 | ~170 |
| Kids: Sparse / Pump Playroom | 18 / 6 + pump 77 | ~160-230 |
| Slide Hall (WB:3002-3214) | 3 flumes × (106 visual + 40 × 5 collision + 4) = 930; 4 entry tubs × 27 (WB:2708-2919: 16 collision bands + 6 handles + 5); helix 364 (120 visual + 48 × 5 collision + 4, WB:2671-2700); spiral 264 (grand 336); ≤5 columns × 14; rails ~50; deck/catwalk ~16 | **1,410 without helix / ~1,834 with helix / ~1,906 grand** + shell |
| Exit flume (WB:3228-3649) | 272 points (2 + 72 + 18 + 180, WB:3283-3328) → 271 closed segments × (1 visual + **6 collision**) = 1,897 + 5; tub 27; recovery chamber with 32-piece wall collar = 77 | **~2,007** |
| Arrival (WB:5705-5886) | gate + frames ~40 (6 PointLights, 2 SurfaceGuis); 7 compatibility markers parented to `workspace`, outside the world | ~160 |

**Shared prop costs:**
- Column = shaft (Part + 4 Textures) + 2 flare MeshParts, each carrying a cloned SurfaceAppearance (WB:1242-1254, 1400) + 5 collision cylinders (WB:1303-1338) = **14**. Essential spiral mast = 7.
- Tube = 4 + visual segments + 5 (open) or 6 (closed) collision parts per collision segment (WB:2513-2582). Visual segments = max(n, ⌊1.6n + 0.5⌋) (WB:2327-2331).

---

## 5. Typical round total, reconciled

Model used: 40 halls, 66 corridors (64 tunnels), live config. Each figure below is tagged:
- **(m)** measured,
- **(d)** derived from measured counts,
- **(e)** estimated.

The modelled total is 55,955 against the measured 56,001.

**Class-level checks:**
- **PointLight 138 matches exactly:** 128 corridor lamps (64 × 2) + 6 gate (WB:5779-5788) + 3 pump lamps (WB:4411) + 1 kids slide fill (WB:3912).
- **SurfaceLight ≈ 16** (154 − 138): ceiling panels (WB:2128), portholes, recovery chamber.
- **MeshPart:** 2,521 = 166 ribs + 2,355. The 2,355 ≈ slide halls ~1,371 + exit 276 + kids slide 46 + ~100 columns × 2 flares + ≈8 slide kits and 2 play towers. The kit and tower count is inferred.
- **SurfaceAppearance 209** ≈ 2 per column, so ~100 decorative columns ("Tiled Column 630" textures before culling = 105 shafts × 6, CF:157).
- **Other non-BasePart classes:**
  - WeldConstraint: 27 (3 × 9, WB:4304, 4502).
  - SurfaceGui: 5. TextLabel: 14.
  - ProximityPrompt: 3. NumberValue: 3.
  - Decal: ≤3, only if the asset slot is filled (WB:4270-4294).
  - UnionOperation: ~30 skylight modules.
  - Attachments: none from WB.
  - Bone 110 / CFrameValue 390: the 5 Pool Foam rigs, parented under the world (`Pool Foam Controller`:2033-2036).

**Why the ~52,000 figure is lower:** it is 7% below the 56,001 reference and inside the spread between seeds. The main per-seed swings are:
- each tunnel: ±472 (kids-styled ±700)
- each Ring Corridor ring: 125
- a slide hall's helix: ~420 (only when slide-hall width ≳ 197, WB:3113-3116)
- ball pit tier: 211 to 594 balls (WB:4125-4131)
- spiral wells: 264 each (3 of 5 were rerouted on seed 738163940)
- kits and towers: 190-225 each

The other possibility is a client count under StreamingEnabled: earlier, 53,989 client vs 71,596 server. I can't tell which without Studio. Nothing in the code path is uncounted.

The jump from the older ~71-75k figures is the arch mesh switch (−15,770) plus face culling (−2,872).

---

## 6. Ranked contributors (live config, % of 56,001)

| # | Contributor | Instances | % | Concrete reduction |
|---|---|---:|---:|---|
| 1 | **Corridor portal surrounds**: 64 × 2 mouths × (header + 32 slats + 30 face-arch pieces), each Part + 2 Textures (WB:4850-4928) | **24,192 (d)** | **43.2** | One MeshPart door surround per mouth (arch cut-out, 7-stud tile UV), or bake it into the kit's doorway wall module. **It has no collision to preserve** → 128 instances, saving ~24,060 |
| 2 | Tube collision strips: per segment floor + 2 chamfers + L + R (+ ceiling on the exit) (WB:2513-2582); entry-tub bands 16 + 3 per tub (WB:2858-2891). Exit 1,645 · slide halls ~2,480 · kits/towers ~700 · kids 50 | ~4,870 (e) | 8.7 | Gameplay-critical (`Level2_SlideFloor` / `SlideDirection` / `OneWayExit` per part). Fewer segments where straight; per-tube convex collision only if the Slide Controller reads direction from the path (the exit already publishes `PathPoints`, WB:3629). Exit helix turn 3 is a backup only (WB:3262-3268): −420 if the owner accepts |
| 3 | Hall shells: ceilings ~2,840 (seals + coves + slabs + panes + PathfindingModifiers) + walls ~2,460 + floors 80 + light panels ~100 | ~5,480 (e) | 9.8 | Blender room modules: floor, wall-with-door and ceiling-with-skylight meshes plus a few box colliders. Seals and coves disappear (seam fixes only). Quick win before the kit: give lintels and sills `visibleFaces` (~1,600 instances carry 6 textures each, WB:312-321) |
| 4 | Slide-hall set pieces: spirals 264-336, deck and catwalk rails, frames | ~550 (e) (in #7 and #3) | — | (see #7) |
| 5 | Corridor vault body: strips 2,877 + standard mesh ribs and feet 1,494 + kids Part ribs 2,106 | 6,477 (d) | 11.6 | One tunnel-module mesh per corridor (ribs and vault baked; kids version via a second SurfaceAppearance or MaterialVariant). Keep a few invisible foot colliders: the navigators clear with `GetPartBoundsInBox` (arch-mesh MEASUREMENTS:15-20). The rectangular walls and ceiling already enclose the vault |
| 6 | Tube visuals: MeshPart clones per segment (106 per flume, 120 per helix, 271 exit, 38 / 51 / 45 kits, towers, kids) + caps, tubs, folders | ~2,200 (e) | 3.9 | One Blender tube mesh per flume, or a few chunks for streaming → ~40 |
| 7 | Hall play structures: stairs dominate (each step Part + 3 Textures). Spiral wells and slide-hall spirals ~1,390, diving towers ~1,140, kit and tower frames ~730, overlooks ~355, edge walkways 720, pump decks 108, slide-hall deck/rails/frames ~240 | ~4,700 (e) | 8.4 | Meshy or Blender props (1-3 MeshParts) + untextured step colliders, or one WedgePart ramp. Steps must keep `Level2_EntityGround` (WB:1952) |
| 8 | Ring Corridor rings: 20 × 25 × (Part + 4 Textures) (WB:6076-6082) | 2,500 (d) | 4.5 | Use the rib mesh pilot here (radius-13 family): 125 → 9 per ring |
| 9 | Corridor shell remainder: floor, ledge, curb, walls, ceiling, lamps | 1,617 (d) | 2.9 | Fold into the tunnel module; keep the ledge and curb as colliders (EntityGround) |
| 10 | Columns: ~100 × 14 + masts (WB:1340-1460) | ~1,435 (e) | 2.6 | One MeshPart with shaft and flares baked, + shaft collider + one skirt band (bands are tagged ground for stepping, WB:1319-1335) → 4 |
| 11 | PathfindingModifier, one per ceiling/skylight piece, including light fixtures (WB:6317-6332) | 1,052 (m) | 1.9 (inside #1-3) | Drops automatically with fewer ceiling pieces; one per room module |
| 12 | Kids set pieces: ball pit ~600, slide-tower frame, splash, frames, clusters | ~690 (e) | 1.2 | Ball bed as one MeshPart (zero collision, WB:3766-3770) |
| 13 | Pool Foam rigs (5) | ~650 (e) | 1.2 | Out of scope |
| 14 | Loose buoyant props: floats, balls, noodles, loungers, clocks, crates | ~470 (e) | 0.8 | Keep (individual physics, WB:4974-4983); trim counts if needed |
| 15 | Pump models (3 × 77) | 231 (d) | 0.4 | Static shell as a mesh; keep the lever assembly, needle, lamp, gauge GUI and prompt (fields returned at WB:4628-4646) |
| 16 | Nodes and markers (nav 40, patrol 160, spawns) | ~210 (d) | 0.4 | Keep (navigation contract) |
| 17 | Models, folders, arrival gate, exit chamber | ~230 (e) | 0.4 | — |

**Projected kit total (estimate, my projection):**
- About **~11k** with tube collision kept as-is. Tube collision (#2) then becomes the single largest item at about 45% of what is left.
- About **~6-7k** if tube collision moves to per-tube meshes.

Terrain water stays free in instance terms but costs voxel memory. It is cleared by `FillBlock(Air)` in `Level 2 Round Adapter`:202, 213.