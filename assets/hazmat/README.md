# Hazmat suit art package — 24 September 2026

On 24 September, Codex uploaded the six color maps and wheel art as **Images owned by ERN Roblox Studios** and imported six textured variants of the canonical rig into `ServerStorage`. The wheel, shop, ownership, and cosmetic visual code match Studio and the repository and were **published in v2061**; the [receipt](../../artifacts/hazmat-20260924/publication-v2061.json) verifies the six suit models and six-sector wheel in the published place file. The current visual uses the game's R15 motion as input for client-side Bone retargeting. Native Play, a two-client round, and phone/tablet simulation passed the visual checks described in [CLAUDE_INTEGRATION_HANDOFF.md](CLAUDE_INTEGRATION_HANDOFF.md). Standing preview pose, paid-purchase, DataStore rejoin, and physical-device tests remain. The older instruction in `docs/CLAUDE_ALL_ACTIVE_TRELLO_2026-09-23.md` to skip skins was superseded by the owner's later request.

## Use these files

| Purpose | File | Notes |
| --- | --- | --- |
| Shared body and skeleton | `baseline-rigged.glb` or `baseline-rigged.fbx` | Use **one** canonical rig for all six looks. 10,180 triangles, 14,463 skinned vertices, 24 bones. The embedded clip is a static pose. |
| Walk clip | `walking-armature.glb` | Source/reference only. The imported animation trials deformed the Roblox mesh; gameplay uses R15 motion retargeting instead. |
| Run clip | `running-armature.glb` | Source/reference only; do not assign the experimental animation IDs to the live visual. |
| Baseline texture | `textures/baseline-yellow.png` | Free/default hazmat suit. |
| Pool Service texture | `textures/pool-service.png` | 25-Token skin; eligible for the wheel's 5% random-skin pool. |
| Suburb Survey texture | `textures/suburb-survey.png` | 75-Token skin; eligible for the wheel's 5% random-skin pool. |
| Blacksite Director texture | `textures/blacksite-director.png` | 300 Tokens **and** 100 lifetime clears; exclude from the wheel. |
| Static Wraith texture | `textures/static-wraith.png` | 99-Robux skin, with `static-wraith-topper.glb` as an optional cosmetic backpack. |
| False Sun texture | `textures/false-sun.png` | 149-Robux skin, with `false-sun-topper.glb` as an optional cosmetic backpack. |
| Wheel art | `wheel/lucky-wheel-six-sector-random-skin.png` | Owner-approved sixth skin field, installed in the current six-sector client UI. Server odds are separate from the equal-size artwork. |

For Studio's documented `.gltf` import route, `studio-import/` also contains lossless glTF copies of the two animation files and both premium toppers. **Keep each `.gltf` beside its `.bin` and image files in its own folder** during import. These are local format conversions of the same Meshy output, not extra generated variants or extra Meshy charges. The body already has an `.fbx` copy.

All six 2048×2048 color maps fit the **same UVs** on `baseline-rigged.glb`; the UV accessor is byte-identical across the six independently rigged Meshy variants. Studio now holds six `ServerStorage.HazmatSkin_*_20260924` templates built from the canonical imported body with separate `SurfaceAppearance.ColorMap` assets. The six independently rigged Meshy study bodies remain excluded because their bind poses and skin weights differ. The runtime clones the selected template as a cosmetic visual around the physical R15 character; the R15 rig retains movement and collision. The client retargets native R15 pose changes onto Meshy Bones because the Meshy skeleton is not directly driven by the stock `Animate` script.

The two premium toppers are separate static GLBs: Static Wraith is 2,897 triangles and False Sun is 3,048. Both have been imported into Roblox and are attached as cosmetics by `HazmatSkinVisuals`; their placement was checked in native Play. Keep hitboxes, detection, movement speed, noise, interaction reach, camera obstruction, and gameplay light radius unchanged. The toppers do not include actual animated effects.

Meshy rigged exports reference the whole color PNG as both `baseColorTexture` and `emissiveTexture`, with `emissiveFactor` `[1,1,1]`. **Remove/ignore the full-surface emissive on Roblox import**; otherwise the entire suit could self-light. If either paid skin gets a glow, make it a restrained, separate cosmetic effect and validate mobile performance and horror readability. The textures are 2K masters; load only needed variants and measure mobile memory before deciding if smaller imports are needed.

## Visual checks

The downloaded Meshy preview renders were inspected. They show complete T-posed suits, distinct colors, and both backpack shapes. The six-sector wheel PNG was checked at 1254×1254 RGBA with transparent exterior, six roughly 60° fields, and a generic blue/sage hazmat icon. At about 240 px, the skin silhouette remains readable but face details become small. **Equal sector art does not represent the weighted odds**: explicitly display `5%` in the UI and keep the server-side random selection independent of wedge area.

| Default | Token: Pool Service | Token: Suburb Survey | Token: Blacksite Director |
| --- | --- | --- | --- |
| ![Baseline yellow](baseline-yellow-preview.png) | ![Pool Service](pool-service-preview.png) | ![Suburb Survey](suburb-survey-preview.png) | ![Blacksite Director](blacksite-director-preview.png) |

| Robux: Static Wraith | Static Wraith backpack | Robux: False Sun | False Sun backpack |
| --- | --- | --- | --- |
| ![Static Wraith](static-wraith-preview.png) | ![Static Wraith backpack](static-wraith-topper-preview.png) | ![False Sun](false-sun-preview.png) | ![False Sun backpack](false-sun-topper-preview.png) |

`source-refs/` holds front, left, and back images used to generate the baseline. `concepts/` holds the five skin looks and two backpack designs. The `*-preview.png` files are rendered Meshy previews. None proves Roblox R15 compatibility, realistic movement, mobile performance, or in-game look.

## Integration and release gates

The current code adds `ZyntraSkins`, `ZyntraSkinsPage`, `HazmatSkinVisuals`, and `HazmatSkinDriver` alongside scoped changes to the existing shop, monetization, wheel, and avatar UI. The owner approved **25 / 75 / 300 Tokens**, with **100 lifetime clears also required for Blacksite Director**, and **99 / 149 Robux** for Static Wraith / False Sun. The two premium offers are verified Game Passes, IDs `1994666374` and `1994816385` respectively. The client checks Roblox's current price and sale status before opening each paid prompt; the server verifies ownership before granting the cosmetic.

The wheel has six UI fields and server weights: `Token1` 40%, `Token3` 20%, `Potion1` 20%, `Potion2` 5%, `Shield1` 10%, and `Skin5` 5%. The skin field chooses an unowned Pool Service or Suburb Survey suit at spin time. If both are owned, its recorded reward is **3 Research Tokens**; it never grants Director or a premium skin. Existing pending five-sector rewards remain claimable. Unit checks cover the durable `SkinId`, fallback, and duplicate claim paths.

Offline checks passed: 23 skin checks, 401 daily-rewards checks, and 613 Lucky Wheel client checks. The Play-client terminal matrix passed 1,811 checks with no failures. Solo Studio Play showed the SKINS cards, a Pool Service Token purchase and equip, and the six-sector wheel; a forced 5% skin spin recorded and granted Pool Service once, then the original odds were restored. Native Play verified movement retargeting, both toppers, and the rotating 3D preview. A two-client Studio round verified skin visibility on both clients and the reduced Level 1 relay formula. Phone and tablet simulator checks showed a usable preview and card action. The work is **published in v2061**. The 3D preview still uses the rig's T-pose; a standing pose, paid purchase, DataStore rejoin, physical phone/tablet, and mobile memory checks remain. The Trello card stays open until its release gates pass.

Before another Studio edit, follow `AGENTS.md`: read fresh Source and editor-source, preserve other developers' work, and mirror only verified changes. The native pre-import backup is `artifacts/hazmat-20260924/studio-before-hazmat.rbxl`. The independent whole-place audit in `artifacts/hazmat-20260924/studio-parity-182-final.txt` found 182 exact script matches, with no drift, missing paths, or extra scripts.

## Meshy provenance and cost

The CLI project is local at `assets/hazmat/meshy_output/20260924_001003_hazmat-baseline-20260924_01a0d051/` and is gitignored because its snapshots contain expiring signed download URLs. For later Meshy follow-ups, reuse these IDs instead of regenerating the model. All 17 tasks succeeded; the recorded total is **160 Meshy credits** (account balance after completion: **1,748**).

| Stage | Meshy task ID | Credits |
| --- | --- | ---: |
| Baseline, multi-image-to-3d | `01a0d051-6139-70a2-88a5-1999aaa29b8d` | 30 |
| Mobile-budget remesh | `01a0d056-45f0-71ae-b756-f5ddbf80bb54` | 5 |
| Pool Service retexture | `01a0d059-cc30-762b-ada8-34ebdc85e337` | 10 |
| Suburb Survey retexture | `01a0d05b-dd9d-75cc-97f5-43a716a99754` | 10 |
| Blacksite Director retexture | `01a0d05c-234b-7030-aae2-ec9e0b762089` | 10 |
| Static Wraith retexture | `01a0d05c-57a2-7582-b161-0356ddac7ab3` | 10 |
| False Sun retexture | `01a0d05c-8cdd-709f-ada3-6fc4a5d63b19` | 10 |
| Yellow baseline retexture | `01a0d063-6db0-7119-89c1-e91c5d4218f4` | 10 |
| Canonical body rig | `01a0d05e-e5e1-73ea-b8b0-9802fab8fd0a` | 5 |
| Pool Service rig study | `01a0d063-a099-75e7-9825-6531d5ae02f9` | 5 |
| Yellow rig study | `01a0d065-c087-72d8-86a0-5dafed9dd37f` | 5 |
| Suburb Survey rig study | `01a0d065-d702-7138-95f2-de0ecfabc598` | 5 |
| Blacksite Director rig study | `01a0d065-ec6c-728c-a51b-d89de4eb382a` | 5 |
| Static Wraith rig study | `01a0d066-0374-7169-893c-fe74b8c3576f` | 5 |
| False Sun rig study | `01a0d066-1ac4-716f-aa9c-feafa7031354` | 5 |
| Static Wraith backpack, image-to-3d | `01a0d068-ad7c-73ca-9dcf-40826b35e102` | 15 |
| False Sun backpack, image-to-3d | `01a0d068-f319-74a2-bab0-8b3bb1777c36` | 15 |

Source: Meshy task JSON `consumed_credits`; the public API price list is <https://docs.meshy.ai/en/api/pricing>. No extra Meshy run is needed for the current package.
