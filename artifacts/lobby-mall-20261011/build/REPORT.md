# Mall lobby build — offline handoff, 2026-10-12

Built for Claude/main-agent visual QA and subsequent Roblox import. **Studio was not opened, read or changed; no network, browser, MCP, computer use, other agents, Git commands, commits, pushes or publication were used.** Work is confined to `tools/lobby_mall/` and this `build/` directory, with disposable scratch under `/tmp`.

## Deliverables and reproduction

- [mall.blend](mall.blend): saved Blender 5.2.0 LTS scene, packed textures and DIN Condensed Bold font, embedded exact `mall.json` data.
- [mall.json](mall.json): version 1, studs, all parts/materials/signs/lights/anchors; SHA256 `71cefe0c7982bf6a69430d09ce4fd1c377e1b0f1d462e7a69ede7e1ed613d0e9`.
- [textures/](textures/): 22 procedural colour sets, each with normal and roughness maps, **66 PNGs at 512 × 512**. Seed 611; numpy/Pillow; no downloaded assets.
- [renders/](renders/): **17 RGB PNGs at 960 × 540**, Eevee, 16 samples, fixed two threads. [Contact sheet](render_contact.jpg), [17 reference comparisons](comparisons/).
- [qa.json](qa.json), [checks.txt](checks.txt), [clearance_route.png](clearance_route.png), [blend_parity.json](blend_parity.json), [deliverable_qa.json](deliverable_qa.json), [reproducibility.json](reproducibility.json): machine-readable evidence.

Run from the project root, with only one Blender command active at a time:

```sh
/Applications/Blender.app/Contents/MacOS/Blender -b --factory-startup --threads 2 --python tools/lobby_mall/build_mall.py
/usr/local/bin/python3 -B tools/lobby_mall/check_mall.py
/Applications/Blender.app/Contents/MacOS/Blender -b --factory-startup --threads 2 --python tools/lobby_mall/render_mall.py
/usr/local/bin/python3 -B tools/lobby_mall/review_mall.py
```

`build_mall.py` holds the whole design and generates JSON and Blender geometry from the same numbers. Its Python subprocess generates the textures using the supplied Pillow installation; it does not start another Blender. A verified input fingerprint avoids rewriting an unchanged saved scene. The second exact build command regenerated JSON/PNGs and reused the verified scene; **all 68 JSON/Blender/texture files were byte-identical**. This is repeat-command reproducibility, not a claim about independent fresh irradiance-bake byte identity.

The optional `report_mall.py` writes this reviewed report after the evidence files are current. `render_mall.py -- --views R03 R13` can rerender selected views.

## What is built

The 80-stud concourse runs from z −900 to −421 with a lit section ending at −621. Core terrazzo and brown borders meet without overlap; floor top is y30 and concourse ceiling underside y46. The six shop floors use the specified 53 × 58 plan, a 27-deep queue zone and 26-deep showcase, 14-high interior, 52 × 12 opening, oak fascia and 40 × 3.2 sign. Exactly **18 radius-7.4 pads**, 0.6 high, occupy the specified centres, each with a four-high station post. Each level's three stations run from entrance to north. The regular 20-stud column lattice is instantiated in closed wall bays; shop-end piers carry their own four-by-four columns, preserving continuous openings.

OFFICE has damask, carpet, one panel, square pillar and a wall-mounted grey cabinet. POOLROOMS has a 1.2-deep water block, small tiles and five submerged columns with flared capitals reaching y44. MALL PARTY has orange/black walls, road carpet, cup table, balloon bunches and black ceiling. CINEMA has navy walls, two neon colours, pale screen, two short rows of red seats and triangle carpet. THE VOID has a rose ledge, recessed black pit, two blocks and one globe. PLAY ZONE has a coloured nine-post grid, noncolliding netting, puzzle mats and a polygonal tube mouth.

Arrival includes dead dark glass doors, mat, hanging WELCOME and two nested three-trolley trains. Two central planter/bench assemblies, six smaller plant tubs, seven blank flat leaderboard faces, the exact 30 × 23 × 2 stage, three steps, DJ console, X-legged folding table, two speakers, ten chairs (three fallen) and GRAND OPENING banner are built. Seven striped poles at x184..256 carry one tape strip at y33.2; its exact danger wording repeats ten times with twelve spaces between phrases.

The dark wing repeats empty shop modules to the terminal wall, with **no lights or props in its x184..256 floor corridor**. No static monster or substitute creature was added.

### Expanded shop and purchase anchors

The carpet has circumradius20; every shop part stays within x200..240. The closed six-counter ring has outer circumradius15, depth4 and maximum height3.6 above the 0.12-thick carpet; glass slopes down toward customers over burgundy trays. Each face has its specified product header and every exact plain price plate. Advanced Equipment includes torch/beam, battery, stamina and swatches; detector includes a large green screen and second boxed device; ITEMS has shield/potions/markers; PACKS has laid-out kit and cushioned re-entry card; tokens have two open presentation boxes; SUPPORTER has badge/easel and six glowsticks.

The pegboard tower reaches y41 and carries small boxed goods and an emissive CRT static screen. Six brass-arm opal globes sit below the radius7, 2.4-high sign fascia. The six skin displays each have a 4.6-wide, one-high oak plinth, 5.2-high hooded respirator/backpack mannequin, exact price plate and individual canopy-arm can spotlight. Their colours/patterns include yellow, pale blue waves, cream/olive map blocks, charcoal/gold, purple lenses/backpack tubes and cream/brown drawings/amber disc.

`anchors.shop_spots` contains exactly **eleven** keys (the brief's “ten” list includes eleven when EntityShield is counted): `AdvancedEquipment, EntityDetector, EntityShield, SpeedPotion, RouteMarker, ExpeditionPack, EmergencyReentry, Tokens4, Tokens20, Supporter, CosmeticEquipment`. Each is on the carpet 2.5 outward from its corresponding counter front at the price/product position.

| Skin | Plinth top centre (x,y,z) | Outward facing (x,y,z) |
|---|---|---|
| BaselineYellow | 211.25000, 31.12000, -785.15544 | -0.50000, 0.00000, -0.86603 |
| PoolService | 228.75000, 31.12000, -785.15544 | 0.50000, 0.00000, -0.86603 |
| SuburbSurvey | 237.50000, 31.12000, -770.00000 | 1.00000, 0.00000, 0.00000 |
| BlacksiteDirector | 228.75000, 31.12000, -754.84456 | 0.50000, 0.00000, 0.86603 |
| StaticWraith | 211.25000, 31.12000, -754.84456 | -0.50000, 0.00000, 0.86603 |
| FalseSun | 202.50000, 31.12000, -770.00000 | -1.00000, 0.00000, 0.00000 |

The four ordinary shop notice boards stand in their specified x/z positions. **Level 3 and Level 4 boards are suspended** at centre y40.4, with their frames' bottoms at y35.2 and hangers meeting the ceiling. This preserves 5.08 studs above the shop carpet (5.2 above the main floor); no height was specified for these boards. The earlier low board placement blocked the enlarged stand bypass. Directory and all other board coordinates/sizes remain as required; all seven faces are blank.

### Sign and lighting treatment

Every `box` face uses the pale cream-yellow texture around RGB236,226,160, brighter toward the middle; thin frame RGB62,58,46; centred single-line DIN Condensed Bold text in RGB72,66,54 with measured cap height55%. The owner sign crop overrides the concepts' red/rounded lettering. Station and plain plates use cream faces and the same dark type. Blender sign faces preview SurfaceGui-style unlit colour for readable prices; these surfaces do not add irradiance. Environmental illumination comes only from the 50 declared lights, with world strength0 and emission excluded from indirect probe capture. Glossy reflections, HDRI, haze, bloom, film grain and lens effects were not added.

There are 23 active concourse panels, five specified dead panel lenses, and exactly one dim/flicker flag at (200,−810). Flicker is a data flag, not an implemented game animation. Pool lighting alone is cool; cinema alone has coloured neon. `SkinSpot*` lights are downward can spots and stronger than individual product lights. Blender energy is a visual calibration of the exported brightness/range, so Roblox lighting still needs runtime QA.

R00 hides ceilings and uses +1 exposure; R13 hides only concourse ceiling geometry for an elevated cutaway. R14 alone adds four temporary review lights and removes them afterward. These changes are never saved back to the design scene or JSON.

## Part budget

| Group | Parts |
|---|---:|
| Arrival | 168 |
| Ceiling | 90 |
| Concourse | 75 |
| DarkWing | 225 |
| Furniture | 138 |
| Shop1 | 53 |
| Shop2 | 70 |
| Shop3 | 88 |
| Shop4 | 76 |
| Shop5 | 53 |
| Shop6 | 125 |
| Stage | 83 |
| Stand | 539 |
| Tape | 15 |
| **Total** | **1798 / <5000** |

The JSON has 56 material definitions, 57 signs, 50 lights, 18 pad anchors, eleven buy spots, six skin anchors and seven board anchors. Tiles, carpet patterns, wallpaper and pegboard holes are texture detail, not individual tile parts.

## Axis conversion and proof

One Blender unit equals one Roblox stud. Roblox (east,up,north) coordinates become Blender (X,Y,Z) = **(x,z,y)**, with no scale or origin change. The basis-swap matrix is:

```text
S = [[1,0,0], [0,0,1], [0,1,0]]
R_roblox = Ry(ry) Rx(rx) Rz(rz)    # CFrame.fromOrientation, degrees converted to radians
p_blender = S p_roblox
R_blender = S R_roblox S^T
v_blender = S v_roblox
```

S has determinant−1: it reflects handedness. Mesh face winding is reversed once after this coordinate conversion. The conjugated rotation has determinant+1 and can be stored as a Blender quaternion. Cylinder axis remains **local X**, including vertical cylinders rotated 90° around Roblox Z. A native Wedge has its high end at local +Z. Sizes always refer to native local x/y/z.

`check_mall.py` computes the corners of three actual rotated parts by explicit scalar rotations (pointwise Z, then X, then Y, equivalent to matrix RyRxRz), independently of the matrix helper, and compares them to the Blender-basis matrix result converted back with S. For the cylinder, eight native local bounding-box corners are tested because a cylinder has no literal corners. The wedge tests all six native vertices. Full lists of both coordinate sets are recorded in `qa.json` under `axis_proof`.

| Actual part | Shape | Roblox rotations, degrees | Corners | Maximum error, studs |
|---|---|---|---:|---:|
| PlantLeaf0_1 | Block | [12.0, 72.0, 12.0] | 8 | 0.000e+00 |
| Shop1_Pad1 | Cylinder | [0.0, 0.0, 90.0] | 8 | 0.000e+00 |
| Counter0_Body_Miter-1 | Wedge | [-0.0, 180.0, 90.0] | 6 | 0.000e+00 |

- `PlantLeaf0_1` first corner: Roblox `[185.38584202, 32.97824617, -806.7376877]`; Blender `[185.38584202, -806.7376877, 32.97824617]`; swapping Blender Y/Z returns that Roblox corner.
- `Shop1_Pad1` first corner: Roblox `[173.4, 30.0, -866.4]`; Blender `[173.4, -866.4, 30.0]`; swapping Blender Y/Z returns that Roblox corner.
- `Counter0_Body_Miter-1` first corner: Roblox `[225.19059892, 30.12, -778.99038106]`; Blender `[225.19059892, -778.99038106, 30.12]`; swapping Blender Y/Z returns that Roblox corner.

The saved scene verifier additionally compares **every declared part vertex** to JSON-derived world vertices; maximum error was **0.000030580 studs** (assertion tolerance0.0001). It verifies embedded JSON equality, every sign string, cap-height error <=0.00001, correct face/body shaders, and clean alpha-blended glass on all six cases. Import rotations directly with `CFrame.fromOrientation`; do not inherit the old Level5 importer's negative-yaw convention. Add the proposed offset to all positions/anchors, leaving sizes, rotations and normals unchanged. Sign normals point toward the viewing side (local +Z of their supporting plate).

## Checks and practical meaning

```text
PASS: 1798 parts / 57 signs / 50 lights
18 pad cylinders, radius12 spawn, six 52x12 openings, clear dark floor, exact signs/lights, bounds, shape contract.
Continuous 20-wide x5-high corridor: 515 centreline nodes; minimum sampled obstacle clearance 10.005344; whole-edge proof: 0.01-stud samples, 0.005-stud Lipschitz bound.
Full-width terminal strip verified from [245.5, 30, -632.5] to tape-base south tangent z=-622.1; 20 wide, 10.4 long, 5 high. No 20-wide passage through poles 12 apart.
Opposed coplanar joining faces >1 sq.stud: 1372 (flagged in qa.json; internal contact surfaces, not overlapping visible faces).
Same-facing submerged base contacts >1 sq.stud: 5 (flagged in qa.json; full coverage by the opaque basin floor verified).
Large solid overlaps: 0; same-facing coplanar face overlaps >1: 0.
Axis test maximum error: 0.000e+00
0 errors
```

The corridor is a radius10 disc swept along 515 centreline nodes for a five-high player above traversable thin floor coverings. The final independent distance samples are at most0.01 stud apart; subtracting the 0.005 Lipschitz bound gives a conservative minimum of **10.000344 studs**, so the full swept width is at least **20.000687**. The strict clearance margin is small and must be checked again after real skin models are substituted.

The approach ends with a full-width rectangle to z−622.1, the south tangent of the pole bases. **A 20-wide passage through the tape line itself is impossible with poles 12 apart**; this test means approach to the tape, not a 20-wide opening through it.

All part sizes, fields, groups, material map paths, bounds, exact sign texts, pad centres, spawn radius12, nine-high pad clear cylinders, openings, lights/dead states, plinths, buy spots, stage dimensions and dark floor were checked. Large opaque solids use convex separating-axis volume checks. Coplanar face areas above one square stud are all flagged: 1372 opposed internal joining pairs and 5 same-facing submerged water/column-base pairs. The latter lie at y28.8 and full coverage by the opaque half-stud basin floor is verified. They are recorded separately, not silently ignored; there are **zero overlapping visible coplanar faces and zero large opaque solid intersections**. Curved primitives use polygonal representations, with conservative circumscribed cylinder footprints for clearances.

`review_mall.py` verified17 RGB renders at960×540, all66 texture dimensions, current checksums and Blender/JSON parity. Every final image was visually reviewed beside its W reference (R00 beside the plan; R14 beside W11 geometry; R15/R16 beside W02 and the expanded brief). Concepts are mostly wider than16:9, so the required render format shows extra ceiling/floor rather than matching their crop exactly.

## Per-view comparison, one line each

| View | Reference | Observed difference / dimensional override |
|---|---|---|
| [R00_plan](renders/R00_plan.png) | plan_v3 | North points right to fit the full 483-stud envelope at 16:9; the dark wing remains black under the declared lighting and extends farther than the proposal drawing. Ceiling hidden. |
| [R01_arrival](renders/R01_arrival.png) | W01 | Correct long concourse, mat, two trolley trains and hanging WELCOME; the measured shop spacing places the enlarged stand much farther away than the concept, and the planter leads the view. |
| [R02_shop_and_supplies](renders/R02_shop_and_supplies.png) | W02 | South-west eye view keeps laminate, pegboard, CRT, warm globes and open shops; the requested expanded closed counter ring and six outside mannequins replace the smaller island, stools and side till. |
| [R03_shop_level1](renders/R03_shop_level1.png) | W03 | Three pads, wall cabinet, damask, floor-to-ceiling pillar and single panel match the subject; the 27-stud queue zone is deeper and its ceiling reads darker than the concept. |
| [R04_shop_level2](renders/R04_shop_level2.png) | W04 | Five columns stand on the basin floor and their stepped flared capitals reach the ceiling; water is a flat dark-teal primitive and is less visible behind the deep queue zone. Station 1 is on screen-right because it must be nearest the entrance. |
| [R05_shop_level3](renders/R05_shop_level3.png) | W05 | Orange/black walls, road carpet, folding table, nine paper cups and two balloon bunches are present; the carpet is confined to the back zone and the ceiling is darker, as the written zoning/black-ceiling brief requires. |
| [R06_shop_level4](renders/R06_shop_level4.png) | W06 | Navy room, one cyan band, one magenta band, pale screen and two rows of four red seats; seats and carpet sit farther back, and the reversed on-screen station order follows the east-side coordinates. |
| [R07_shop_level5](renders/R07_shop_level5.png) | W07 | Flat rose showcase has a real recessed black pit, narrow ledge, two blocks and one globe; the queue remains terrazzo and the two blocks read lower than the concept. No additional showcase fluorescent. |
| [R08_shop_level6](renders/R08_shop_level6.png) | W08 | Slide mouth is on the left, with nine coloured posts, netting and blue/green puzzle mats; the rear grid is simpler than the concept and there are no extra platforms or multilevel play structures. |
| [R09_queue_bay](renders/R09_queue_bay.png) | W09 | Close diagonal view includes all three OFFICE pads and station posts; foreground pad/post are larger, the back zone is farther away, and the enlarged stand is mostly outside this measured viewpoint. |
| [R10_the_tape](renders/R10_the_tape.png) | W10 | Oblique eye view from the east bypass avoids the previous extreme fisheye; the fixed event stage occupies foreground and partly obscures the left poles. All seven poles and the continuous repeated tape exist in the data. |
| [R11_in_the_dark](renders/R11_in_the_dark.png) | W11 | Black under normal lighting; the concept creature, eyes and arms are deliberately absent from static geometry so the dark floor stays completely clear for the existing game monster. |
| [R12_event_stage](renders/R12_event_stage.png) | W12 | Deck, steps, X-legged DJ table, speakers, ten chairs with three fallen and banner are present; chairs are slightly right of centre to preserve the 20-stud route, and the cloth banner is flat rather than sagging. |
| [R13_stand_from_above](renders/R13_stand_from_above.png) | W13 | Elevated three-quarter ceiling cutaway shows the exact larger hexagon, six glass counters, product groups and radial skin plinths; canopy is oak and there are no old stools/side counter. |
| [R14_dark_wing_lit_for_review](renders/R14_dark_wing_lit_for_review.png) | W11 geometry only | Four temporary work lights expose the clear floor, empty repeated shop modules, striped columns and terminal wall; this brighter diagnostic lighting is absent from mall.json and mall.blend. |
| [R15_shop_skins](renders/R15_shop_skins.png) | W02 character + suit front/back refs | New required close view shows Baseline Yellow and Pool Service plinths with the advanced counter between; gas-mask suits are deliberately simple block/ball stand-ins, not the final skin models. |
| [R16_shop_advanced_equipment](renders/R16_shop_advanced_equipment.png) | W02 character + expanded brief | New required close view shows the raised burgundy tier, torch, visible pale tapered beam, battery, stamina canister, swatch fan, header and exact price; the beam is a two-wedge approximation rather than a circular volumetric cone. |

## Remaining limitations and dissatisfaction

- This is a **static offline build**, not a proof of Roblox runtime behaviour, navigation, game functions, performance, multiplayer, mobile play, memory/CPU cost, or imported lighting. Claude's live Studio QA/import/wiring and the owner's eventual publish remain separate work.
- I am not claiming pixel-perfect concept fidelity. The mandated long plan, 27-deep queue bays, huge 40-wide shop signs, enlarged stand, 16:9 output and exact station numbering differ visibly from the images. The shop ceilings/queue fronts still read too dark compared with the concepts. Procedural terrazzo is more uniform; flora and furnishings are deliberately simple geometry.
- Skin figures preserve colours/patterns, hood, respirator, backpack and height but are coarse placeholders. Main should replace only each `<Skin>_*` mannequin prefix, retaining `SkinPlinth<Skin>`, skin price plates, lamp arms/lenses and anchors. Item props are native primitive stand-ins, not fetched game models.
- Torch beam is a two-wedge tapered transparent solid effect, not a true circular cone or volumetric simulation. Banner is flat fabric, not sagging cloth. Cinema seats are simple blocks; slide mouth is a polygon ring; water has no animated ripples. Normal maps are flat and roughness maps intentionally matte.
- R10 includes the fixed stage and hides some poles through natural occlusion; R11 is intentionally black and contains no monster. R14 is the separate geometry diagnostic. R00's far dark-wing geometry cannot be seen under its required unlit condition.
- Main must upload the supplied maps and verify MaterialVariant colour tint/tiling, especially pad-cap ring UV placement and glass/water transparency. Textures use white part tint when an absolute colour map is present; untextured parts carry their actual RGB. Verify downward `SkinSpot*` direction and fixture brightness after import. PNG availability is not asset upload or Roblox material parity.
- Five submerged coplanar base pairs remain intentionally flagged and sealed by the basin floor; audit these records if the importer changes the basin structure. Internal opposed joints also remain flagged. The counter ring has no walking entrance, but jumping/climbing restrictions were not runtime tested.
- Blender exits successfully and saves/validates the scene. Its log contains deprecation notices and a 0.062584MB shutdown bookkeeping allocation warning; no runtime game conclusion is inferred from that message.

No game scripts were synchronized, no Studio state was overwritten, and no Git commit/push or Roblox publish was performed. Nothing was staged in Studio by this helper. **The handoff is these local build artifacts for Claude QA before import.**
