# Geometry readiness — 9 September 2026

Read-only assessment for Trello [KcUdv690](https://trello.com/c/KcUdv690) and [k6e4BnS1](https://trello.com/c/k6e4BnS1). No game source, Studio instance, tuning attribute, Play state or Trello card was changed. The complete native measurement is in `geometry-current-native.json`.

## Level 2 — taller tunnels and larger Pool Slide

The entire card request is: “Increase the height of the tunnels in Level 2 so there is enough vertical clearance to make the pool slide entity larger.” It supplies no target dimension or scale. A concrete, reversible candidate can be chosen and tested autonomously.

### Current physical constraints

`Level 2 Configuration.ModuleScript.lua:57,86` has CorridorWidth=34, CorridorHeight=26, DoorWidth=30, DoorHeight=19, normal WallHeight=34 and KidsWallHeight=21. Slide halls already have heights 76/96. MasterTuning had no overrides in the observed Edit state.

The effective tunnel ceiling is much lower than 26. In `Level 2 World Builder.ModuleScript.lua:1539,1590,4528`, collidable rib and barrel geometry has its arc centre at y=1. The rib radius is min(34/2−3,30/2−1.8)=13.2; the vault radius is min(13.2+1.4,30/2−0.9)=14.1. Rib radial thickness is 2.2, vault thickness 1.6. Centreline inner crown is therefore approximately 13.1 for ribs and 14.3 for the barrel, with lower clearance away from the centreline. Actual tessellated collisions must be measured rather than equating these estimates with certified clearance. The raised walkway top is y=0.45. Raising CorridorHeight alone only raises the rectangular shell above the visible, collidable vault.

The mouths also contain radius-derived face rings/spandrels/header (`:4550` onwards); their surfaces are non-collidable but will visibly clip a larger rig unless matched to the new vault. Hall lintels still obey DoorHeight. Pressure-door panels use CorridorHeight (`:4678`); their closed/open travel and lock behavior require regression checks. Kids room height must remain greater than an enlarged doorway, or its header would become invalid.

Current Edit template, `ServerStorage.Level2Assets.Level 2 Pool Slide Template`, measured after root stopped Equipment QA:

| Property | Observed value |
|---|---:|
| Model scale | 4 |
| Rest bounding box X/Y/Z | 7.6850 / 8.0000 / 2.6432 |
| AgentRadius / AgentHeight | 5 / 9 |
| AnimatedEnvelopeRadius / Height | 4.82 / 8.61 |
| GroundOffset | 4 |
| Bones / primary | 20 / RootPart |
| RigVerified / CorridorFitVerified | false / false |

Four animations already exist: Idle `133905428587807`, Walk `122219504123224`, Run `71870594656450`, Attack `139401240947604`. Their presence is evidence of available inputs, not permission/playback/fit certification. Current Pool Slide Configuration has Enabled=false and StudioValidationMode=false. The earlier server-usage report describes a prior enabled Studio draft; its “Enabled=true” text is historical, not current state.

### Proposed implementation and acceptance

1. Introduce one shared vertical vault proportion and apply it consistently to ribs, barrel strips, mouth face rings, spandrel curve and lights. A candidate is 1.5× vertical rise while retaining current horizontal radius and corridor width. Compute ellipse segment positions/chord lengths and normals consistently; the current circular chord formula must not leave gaps when stretched. Keep foot depth, walkway and floor supports intact. Candidate shell/door/kids heights are 32/25/28; these are proposed values to inspect and adjust, not measured success.
2. Stage a cloned template at scale 6 (1.5× the current model) and remeasure it. Its expected rest height is about 12 and simple scaling of the currently stored envelope predicts radius 7.23/height 12.915. Those predictions are starting points only: remeasure full animation cycles, attack extension, all yaw angles and pivot-to-sole placement. Agent radius/height must conservatively enclose the actual sweep plus the controller margins of 0.1/0.3. Keep legacy PoolFoamGroundOffset absent or exactly consistent. Do not copy approval flags onto an untested scale.
3. Validate the rig adapter contract: valid static RootPart-to-MeshPart bind closure, server Animator, correct imported bone rig, all four published clips actually loaded, no mesh detachment/foot sliding. Recalibrate WalkAnimationReferenceSpeed and RunAnimationReferenceSpeed after scale changes; the old values 8.062205/17.367606 were measured for the previous scale.
4. Test a bounded seed set including 101, shallow/deep/drained corridors, both axes, kids junctions, pressure doors and near-touching halls. Measure swept clearance at centre and off-centre paths, turns, arch ribs and every mouth. Preserve player traversal, pump/water behavior and the already fixed Level 2 lobby spawn. Test dormant→pump2 spawn, walk10/run20, pump3 enraged32, attack/cooldown, hiding/protection and teardown. Capture actual visual evidence and server frame-time tail under pursuit; the earlier performance report did not reach pump3.
5. Only set RigVerified/CorridorFitVerified after their corresponding evidence passes. Enabling must never again turn a template validation failure into a failed Level 2 round; keep the existing safe disabled behavior until the enlarged entity is validated. Independent critic must score at least 8/10, then root publishes through the mouse UI.

This is autonomous engineering/visual QA work with existing model and animation inputs. The disabled flags are uncompleted validation, not evidence that an external asset is absent. Controller/Navigator currently cap AgentRadius at 12 and AgentHeight at 24, so the proposed scale is within their numerical range; physical traversal still needs proof. If imported animation permissions or the rig actually fail, record that concrete external requirement instead of guessing it beforehand.

**Audio is separate.** The user explicitly skipped Pool Foam sound production and assigned it to a friend. Do not demand an ElevenLabs account or audio delivery to complete tunnel geometry/Pool Slide rig clearance. Do not claim sounds were delivered or change their card to Done.

## Level 3 — make the map more square

The full current request is: “Level 3 should not be a long rectangular map. Adjust the layout toward a more square shape.” It links an older completed card; no precise aspect ratio is supplied.

### Actual dimensions and seed spread

`Level 3 Layout Generator.ModuleScript.lua:15–20,315–423` places three 2×4 districts consecutively along X, with row centres at Z=−90/+90. Every seed therefore has the same global two-row/twelve-column topology. Current config room widths are 60–78, depths 52–68, internal X gaps 24–34 and gateway gaps 38–48. The generator's fallback defaults of depth48–62/RowHalfSpacing62 are not the actual resolved configuration. Arrival is 64×54. SignalHall is the last column of district 3; a straight 560-stud +X passage leads to a 58×52 Exit room. Removing Exit reduces the measured width by exactly 618=560+58.

Read-only native sampling used the current Edit module Sources, Roblox Random, the four fallback seeds plus `104729*i+1` for i=1..100. Only imports were replaced in memory: Configuration Source was evaluated as its pure table constructor, and Master.Overlay was replaced with a read-only copy of existing numeric overrides. This avoids the real Master's default-publishing side effects. No build/require of the mutating Master overlay or world generation was executed. All 104 layouts passed the real current generator validator at attempt1, zero generation failures.

| Measured metric | Minimum | Median | Maximum |
|---|---:|---:|---:|
| Full plan width | 1833 | 1896 | 1945 |
| Plan depth | 236.5 | 244 | 248 |
| Full width/depth | 7.543 | 7.770 | 8.071 |
| Width excluding Exit | 1215 | 1278 | 1327 |
| Aspect excluding Exit | 5.000 | 5.238 | 5.485 |

Seed101 is 1860×242 (7.686); 7331 is 1916×245.5 (7.804); 65537 is 1902×239 (7.958); 1900813 is 1893×243.5 (7.774). Bounds are room-plan bounds, not the final rendered world's bounding box: the long arrival slide extends west beyond Arrival. The waiting room is below Exit and does not enlarge its X/Z footprint. Measure the slide and decorative extents separately in final native acceptance.

### Minimal concrete layout proposal

Keep each existing 2×4 district and its seven-edge spanning tree plus two loop edges. Stack the three districts along **Z** instead of concatenating them along X. This produces a global four-column/six-row core and keeps all 24 district rooms, 26 total rooms, 31 links, six cycles, three themes, five CDs and 24 hiding tables.

Use shared column centres sized from the maximum room width in each column across all three districts. This permits straight north/south gateways despite seeded room-width differences, without forcing all rooms to identical dimensions. Preserve each district's seeded depths; the next district's offset is computed from the previous south-row depth, the next north-row depth and a 38–48 clear gap. Connect one south-row room of district1 to a north-row room of district2 in the same chosen column; repeat for districts2→3. These outward north/south ports are unused by each district's internal grid. Keep Arrival west of district1 and the existing slide orientation. Keep SignalHall in district3's rightmost column, with the same straight 560-stud +X final corridor and eastern freight exit.

This avoids rotating the authored arrival/exit sets and avoids turning a single final hall into a multi-segment chase. The final hall builder already uses its StartPoint/EndPoint/Forward for its 40% spawn and 50% halfway triggers, but `makeExitSet` is explicitly +X-oriented (`Level 3 World Builder.ModuleScript.lua:1880`), so casually rotating the entire finale would require more changes.

Under current dimension bounds, stacking produces roughly 772–840 studs of depth and a full plan around 1.0–1.15k studs wide including the intact 560-stud finale. These are projected design bounds, not a tested revised generator. Choose measured acceptance of full room-plan aspect ≤1.5 and core aspect ≤2.1; both are substantial improvements over the observed 7.77/5.24 medians. Include the arrival slide in a second rendered-footprint measurement so the reported improvement is honest. If final room sampling exposes a boundary case, adjust shared spacing/offsets rather than shortening the final chase merely to satisfy the number.

Update district bounds, gateway metadata and layout version/hash intentionally. No consumers of GatewayRows were found outside the generator; local GridRow/GridColumn remain the same 2×4 indices, so existing room IDs, module candidate columns and district DFS can stay. Recompute five-CD selection after placement and retain ≥105 separation; gateways can bring rooms across districts closer, so do not assume old candidate selections remain valid.

### Required validation and remaining risks

- Stress a representative seed sweep and all fallback seeds with the real generator. Preserve deterministic same-seed/hash behavior, counts, one opening per side, cardinal links, minimum18 clearance and connected district/global graphs. Preserve seed diversity rather than silently relying on a fallback.
- Add geometry validation for corridor rectangles against non-endpoint rooms and other unrelated corridors, which the current validator does not check. Existing room AABB and graph validity alone do not prove a rearranged map is physically sound. Allow intentional endpoint junctions only.
- Native inspect at least the smallest/largest aspect cases and representative seeds 101/7331. Traverse district gateways and all CDs; check inaccessible props, overlap, visual seams and route navigation.
- Regression the already fixed slide aperture, arrival NO EXIT sign, hidden-exit reveal, the 560-stud chase with spawn40%/trigger50%, player flashlight behavior and automatic run-in freight exit. The card must not accidentally reintroduce a button requirement.
- Measure build/instance cost and pursuit stability; stacking keeps room/edge counts stable but changes line-of-sight, streaming proximity and NPC paths. Critic ≥8/10 and mouse publish follow completed validation.

This card can be implemented and completed autonomously with current source/assets. It is a generator placement/gateway change plus real world QA; there is no missing account, external asset, audio dependency or mandatory user-specified numeric input.
