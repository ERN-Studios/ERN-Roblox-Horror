# Standing hazmat catalogue portraits

These six images replace the **static square suit samples** shown on the in-game
`SKINS` shop cards. The cards currently reference the old T-pose renders through
`ReplicatedStorage/ZyntraSkins.ModuleScript.lua` → `PreviewImageId`. The large
rotating shop viewport is already a separate 3D render and is not affected.

| Skin ID | 512 × 512 transparent shop card | Roblox Image ID | 1024 × 1024 full-body reference |
| --- | --- | ---: | --- |
| BaselineYellow | `baseline-yellow-standing-card-v1.png` | `124074662246510` | `baseline-yellow-standing-v1.png` |
| PoolService | `pool-service-standing-card-v1.png` | `128677695300171` | `pool-service-standing-v1.png` |
| SuburbSurvey | `suburb-survey-standing-card-v1.png` | `78809161314896` | `suburb-survey-standing-v1.png` |
| BlacksiteDirector | `blacksite-director-standing-card-v1.png` | `73840400724040` | `blacksite-director-standing-v1.png` |
| StaticWraith | `static-wraith-standing-card-v1.png` | `120474289726445` | `static-wraith-standing-v1.png` |
| FalseSun | `false-sun-standing-card-v1.png` | `122113892663451` | `false-sun-standing-v1.png` |

`standing-card-preview-sheet.jpg` shows all six on the current dark shop colour
at the actual 104 px desktop and 78 px narrow/touch sample sizes. The square
portraits deliberately keep transparent corners; **do not crop these to circles**.
Roblox Game Pass icons use a separate circular-safe set under
`../pass-icons/`.

## How these were made

`render_catalogue.py` imports the canonical `../baseline-rigged.glb` in
headless Blender 5.2.0 LTS, rotates the two arms and forearms into a standing rest
pose, then renders each variant with its exact existing `../textures/*.png`
ColorMap on the same UVs. No Meshy generation, model edit, hand-painted texture,
Studio action, or live Roblox asset replacement was involved. The 512 px crop
shows hood, respirator, torso, lowered arms, belt, and upper legs so the skin is
readable in a small card. The 1024 px master shows the complete suit, including
boots. The originals under `../*-preview.png` remain unchanged.

Rebuild the renders on a machine with Blender 5.2.0 LTS:

```powershell
& 'D:\Blender\blender.exe' --background --factory-startup --python 'assets\hazmat\catalogue-portraits\render_catalogue.py'
python 'assets\hazmat\catalogue-portraits\make_preview_sheet.py'
```

An initial built-in image-generation edit was inspected and discarded because
it changed small suit details. The committed portraits are deterministic 3D
renders of the actual canonical game mesh and texture maps.

## Integration gate

All six `*-standing-card-v1.png` files were uploaded as group-owned Roblox
Images on 24 September 2026 and all six returned **Approved** from Open Cloud
metadata readback. The exact SHA-256, operation, group owner and moderation
receipt are in `upload-receipt.json`; `upload_images.py` can verify them again.
Replace the six `PreviewImageId` values against **fresh Studio Source and editor
source**. Do not change the
`ImageId` ColorMap values, Game Pass icons, 3D preview, or rig. Compare all six
shop samples in a native Play client at desktop and touch sizes before claiming
the card-polish work complete; keep the old images available for rollback.

These are uploaded assets only. They are not shown in the game until a later
Studio integration is verified and published.
