# Level 5 DEV gallery: live Studio record, 2026-09-27

## Authority and installation

Studio place `131311258779917`, universe `10559217407`, was in Edit mode when each live target was read. `ScriptEditorService:GetEditorSource` equalled `Source` before the scoped writes, and `UpdateSourceAsync` compared the callback's current source with the freshly read baseline. The three new ModuleScripts were first built as exact, tagged temporary instances in Studio, then moved into the live `Level 5 Systems` folder only after a successful ten-section build. The preview and camera scripts were edited/created at their exact live paths. After installation, all five live `Source` and editor sources were byte-for-byte equal to the local mirrors:

| Studio path | Class | Enabled | Bytes | Local SHA-256 |
| --- | --- | --- | ---: | --- |
| `ServerScriptService.Level 5 Systems.Level 5 Reference Facades` | ModuleScript | n/a | 44,359 | `fda2d85dd2e784b8e52410cc91c75304682f7aac95bd820bc81c02a678e8a395` |
| `ServerScriptService.Level 5 Systems.Level 5 Reference Anomalies` | ModuleScript | n/a | 78,531 | `4b0a6e7fd6ded49498b81d3e111c95db4e5d6b907096bbc6659df3df24793408` |
| `ServerScriptService.Level 5 Systems.Level 5 Rework Gallery` | ModuleScript | n/a | 16,324 | `f02f346dbaa24a54557db8d36dfb87af03d1affe874b766a17ea68399b3be565` |
| `ServerScriptService.Level5PreviewAccess` | Script | true | 16,794 | `c2e82d1904ce36ba066278312aeccb6613874386601f0a952406938b81d6ad9a` |
| `StarterPlayer.StarterPlayerScripts.Level5GalleryCamera` | LocalScript | true | 9,949 | `a8ed934ff289b50bf02ab1f1636fcaa96f9c27d351ddeab6a57be9852a1a6019` |

The gallery is tagged `GalleryContentVersion=reference-gallery-2026-09-27-v1`, `FidelityStatus=unverified-draft`, `GalleryOnly=true`, and its runtime model retains `Level5Preview=true`, `PreviewOnly=true`, and `PreviewReady=true`. It builds at `(47000, 24, 0)` only after an allowed developer uses the existing `Level5SealedDoor` prompt. The playable Level 5 Architecture, seven gates, round flags, and public access were not changed by this gallery task. The existing static preview at X=31,000 was replaced as the door's DEV view; the playable round remains separate at X=17,000.

## Build and Play checks

- Isolated Edit build with the final gallery source passed `Gallery.ReadManifest`, ten separated section cells, hub and section landing raycasts, and the 30,000-instance check. Total: **8,526 descendants**. Section descendant counts: `1,738 / 348 / 1,095 / 1,195 / 918 / 955 / 340 / 634 / 1,102 / 139`. The temporary model and modules were owner-tag checked and destroyed after capture.
- DEV Play test as whitelisted user `9488575949` passed: sealed door → gallery hub → section 01 → hub → lobby. A second Play test passed: door → hub → section 08 → hub → lobby. Server checks observed a ready, versioned model with exactly **8,526** descendants after travel. The WIP status overlay appeared only in the gallery and hid on lobby return. The client camera faced the hub stands, matched section 08's stored look vector (`dot=0.99999964`), and restored 70° FOV in the lobby.
- To make individual key presses testable by UI automation, prompt `HoldDuration` was set to `0` **in the Play data model only** before each trigger; the saved `0.5`-second hold was not separately tested. Server-side authorization, range rechecks, streaming, destination floor checks, and actual transport ran in Play.
- One-player DEV access was tested. A separate non-DEV account, multiplayer/round interaction, and public server were **not** exercised. Source review confirms the server still calls shared `DevAccess.IsAllowed`, rejects `InRound`/reserved-round states, and ejects non-DEVs from the owned preview bounds, but these are not claimed as runtime passes.

## Candidate imagegen textures

The three textures were generated with ChatGPT imagegen and uploaded to Roblox. The DEV gallery applies them through eleven `Texture` children only: carpet `rbxassetid://136282007145831` on section 02 `CarpetBase` Top at 12-stud repeats, cream clapboard `rbxassetid://107441812561821` on three nearby section 02 siding spans Right at 18 studs, and dark lawn `rbxassetid://108216315862080` on selected sections 01, 05, 06 and 09 Top faces at 16–24 studs. The gallery hides 40 opaque corridor carpet-tile parts so they do not cover the new carpet. Isolated reference-camera captures showed carpet grain and dark grass rendering. The cream siding remained too cool/grey for the warm screenshot, and tile seams/colour under final round lighting have not been approved. These remain candidates, not 1:1 materials.

## Visual release blocker

The ten supplied social-video screenshots are not available as original local image files, so exact pixel overlays were not possible. The isolated QA captures and Play views show large differences in facade rhythm, proportions, lighting, ceiling closure, planting, cottage size and the cutaway geometry. Several cells are non-traversable scenic drafts behind an invisible view-pad guard; they are labelled **VIEW ONLY / WIP**. The ten reference views have **not** been integrated into the eight playable zones, nor has the seven-gate round been retested with them. Strict 1:1 acceptance is therefore **failed/unverified**, and this Studio change must not be published to the Roblox experience yet.

The earlier full native place backup is `pre-rework-place.rbxl` (SHA-256 `9ba32d34ba3daababc203ae6e88f028af0918344c4a0df5231223f9164b649eb`); the F trim native union backup is `window-trim-templates.rbxm` (SHA-256 `76e5d0e41b28531d28854e9352442e081350110567a3e110d1bd5cac1feb616c`). No new persistent non-script Studio instances were added by this gallery; prompts, UI, textures, and geometry are generated by scripts at runtime. A post-change full native place backup was not obtained, and no publication or GitHub push is claimed.
