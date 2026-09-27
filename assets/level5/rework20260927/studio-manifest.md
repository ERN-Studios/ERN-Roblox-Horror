# Level 5 Studio state manifest

Read from Roblox Studio **Edit** DataModel on 2026-09-27 at 13:11 UTC. Studio instance `e7dbf962-5b02-4de6-9494-ef440fb543aa`; place ID `131311258779917`; universe ID `10559217407`. This is an inventory of the live state at that time, not a deployment instruction.

## Source mirrors

The rolling hash below iterates over source bytes as `h = (h * 131 + byte) % 2147483647`, starting at zero. SHA-256 was calculated independently in live Studio with a read-only Luau implementation, self-checked against the known `abc` digest, and in the repository with Python. Each live `Source` was identical to `ScriptEditorService:GetEditorSource` when read. Both SHA-256 digests, byte lengths, and rolling hashes matched the checked-out mirrors.

| Live Studio path | Class | Bytes | Live Source and editor rolling hash | Mirror file | Live and mirror SHA-256 | Status |
| --- | --- | ---: | ---: | --- | --- | --- |
| `ServerScriptService.Level 5 Systems.Level 5 Architecture` | `ModuleScript` | 54,897 | 394830723 | `ServerScriptService/Level 5 Systems/Level 5 Architecture.ModuleScript.lua` | `d4d074863c4674fa470ebd82a2848d1bde5f5a2a477139299560bc7d8723dfc9` | Exact source byte parity |
| `ServerScriptService.Level5PreviewAccess` | `Script` | 12,483 | 1494237752 | `ServerScriptService/Level5PreviewAccess.Script.lua` | `f6a8c87f14475f20f3de1b3798970d2d96f7e70799509c91b3475b97c7b5404d` | Exact source byte parity |
| `ServerScriptService.Level6PreviewAccess` | `Script` | 11,150 | 1430539777 | `ServerScriptService/Level6PreviewAccess.Script.lua` | `14a9b9063931d395e0813d3d152d2007d522b2734e61689c70ce799dc5ba73aa` | Exact source byte parity |

Both preview scripts were `Enabled=true`, `Disabled=false`, and `RunContext=Legacy`. The module and both scripts were archivable and had no attributes. This check did not install either reference draft module in Studio.

## Native geometry templates

`ServerStorage.Level5GeometryTemplates` was a `Folder` with exactly two children and attributes `Owner="Level5ReferenceRework20260927"` and `Version=1`.

| Live Studio path | Class | Template attributes | Size (studs) | Local CFrame position (studs) |
| --- | --- | --- | --- | --- |
| `ServerStorage.Level5GeometryTemplates.WindowTrimSimple` | `UnionOperation` | `WindowWidth=10`, `WindowHeight=7.2`, `CrossbarCount=1`, `SourcePartCount=6`, `Level5WindowTrimTemplate=true` | `10.65 × 7.65 × 0.41` | `(-5.08, 0, -0.08)` |
| `ServerStorage.Level5GeometryTemplates.WindowTrimStandard` | `UnionOperation` | `WindowWidth=10`, `WindowHeight=7.2`, `CrossbarCount=2`, `SourcePartCount=7`, `Level5WindowTrimTemplate=true` | `10.65 × 7.65 × 0.41` | `(-5.08, 0, -0.08)` |

Both had identity rotation; color RGB `(241, 238, 220)` approximately; `SmoothPlastic`; `Anchored=true`; `CanCollide=false`; `CanQuery=false`; `CanTouch=false`; `CastShadow=false`; `UsePartColor=true`; `Transparency=0`; `Reflectance=0`; `CollisionFidelity=Hull`; `RenderFidelity=Automatic`; no descendants. AssetId and MeshId were not readable properties of these `UnionOperation` instances. Their CSG data must be preserved in a native place backup; source mirrors alone cannot recreate it.

On 2026-09-27, the same live folder was serialized in Studio Edit with `SerializationService:SerializeInstancesAsync({folder})`. The 15,955-byte engine-native result is `assets/level5/rework20260927/window-trim-templates.rbxm`, SHA-256 `76e5d0e41b28531d28854e9352442e081350110567a3e110d1bd5cac1feb616c`. A Studio `DeserializeInstancesAsync` roundtrip into an unparented model recovered the folder, both UnionOperations, their attributes, dimensions and `UsePartColor`; the temporary instances were destroyed. This backs up the changed CSG assets specifically. The pre-change full native place is `pre-rework-place.rbxl`; a post-change full `.rbxl` remains outstanding because Studio's Download a Copy file picker has not returned a save path.

## Verification scope

This read confirms the listed live instances and source/editor consistency only. It does not verify 1:1 visual fidelity, gameplay, multiplayer access, or publication.

## Integrated DEV revision — 2026-09-27 20:39 UTC

The following sources were written to their exact existing Studio instances after checking each live `Source` against `ScriptEditorService:GetEditorSource` and its pre-write hash. The write callback checked the same baseline again; the post-write Studio source/editor pair matched the proposal. At 20:39 UTC, a fresh Edit read rechecked all five live sources, classes, byte lengths and both rolling hashes. The repository mirrors below have the listed SHA-256 digests. This is a live Studio export record, not an instruction to push repository scripts into Studio.

| Live Studio path | Class | Bytes | Source/editor rolling hashes (131, 257) | Mirror SHA-256 |
| --- | --- | ---: | --- | --- |
| `ServerScriptService.GameManager` | `Script` | 168,265 | `994004659`, `1884662859` | `03694b9fcbc53589a284efd7cbc4378d5495eb07d653477b6a4a91f6d1817e27` |
| `ServerScriptService.Level 5 Systems.Level 5 Architecture` | `ModuleScript` | 71,161 | `562016983`, `975192154` | `044485bb4d1b408ca1755b05333e815543e4d2316b3c632b4c1e8d565b40abe7` |
| `ServerScriptService.Level 5 Systems.Level 5 Neighbourhood Districts` | `ModuleScript` | 29,411 | `988680040`, `2070253584` | `067292fe9285df1980d3f4eea29876746720b9373182d481550e19a74c3b9b41` |
| `ServerScriptService.Level 5 Systems.Level 5 Landmark Districts` | `ModuleScript` | 40,432 | `688882602`, `1796157685` | `f793cff7746902817a5187ecbff5745a897b1368f907350cc1d9e3649b26a6aa` |
| `ServerScriptService.Level5PreviewAccess` | `Script` | 22,459 | `549940819`, `448334585` | `f9679951e44ed6670ab1b732a520842af0ed0b67b7a9eaf11f86650c860879ce` |

`Workspace.Level5DevEnabled=true` and `Workspace.Level5PublicPreviewEnabled=false` in Edit. The Edit-only QA payload folders `_L5Integrated_Modules_TEMP` and `_L5LiveScriptPayloads_TEMP` were identity-checked and removed; neither remains. No live non-script geometry was changed in this revision. The native pre-rework place and CSG trim backup above remain the native backup records; a post-rework full `.rbxl` backup remains outstanding.

The F key `Level5DeveloperPlayPrompt` on the existing sealed Level 5 door was Play-tested with whitelisted owner UserId `9488575949`: `SelectedLevel=5`, `RoundActive=true`, player `InRound=true`, position around `(17002,24,5)`, and `Workspace.Level 5 Generated World` had 26,889 descendants and 18 Window Watcher anchors. The console showed no Level 5 error in that run. This tests Studio Play only; published-server teleport, all gates, multiplayer and visual 1:1 remain unverified. See [integrated-play-qa-2026-09-27.md](integrated-play-qa-2026-09-27.md).

## Reference and puzzle revision — 2026-09-28

The five existing Studio instances below were changed by source-scoped compare-and-swap writes after fresh `Source` and `ScriptEditorService:GetEditorSource` reads. A fresh Edit-mode read after the changes found `Source` equal to editor source for each instance. The repository mirrors have the exact source bytes represented by these lengths and hashes. All five instances have class `ModuleScript`; paths are under `ServerScriptService`.

| Live Studio path | Bytes | Source/editor rolling hashes (131, 257) | Mirror SHA-256 |
| --- | ---: | --- | --- |
| `Level 5 Systems.Level 5 Architecture` | 77,244 | `69375242`, `1165573759` | `2a0cab9570e4eaf76b0cca70bcb5346c3fd796858ee6748106232e0cd5e70f46` |
| `Level 5 Systems.Level 5 Neighbourhood Districts` | 37,295 | `1829371731`, `389190142` | `bc8d7e17bc05632a51cb35b8566e5005d94cffdc76c39a11daca13dc0256b9ab` |
| `Level 5 Systems.Level 5 Landmark Districts` | 50,328 | `1044703140`, `1732580015` | `d8f0e37d44d810280718cbc6a89ca38dfc73c5ceb85afbf6392a2108113581e9` |
| `Level 5 Systems.Level 5 Round Adapter` | 17,493 | `1866477025`, `883969944` | `bcd44ac8b965729e416f8ae94af2f7b63cad1a2834c0e539e0d79f3e0ffa765b` |
| `TunnelLobbyBuilder` | 118,480 | `1700301370`, `1905118909` | `325c1d220069976ff2a8205ef062837ffd74c9c3808b3a8d85fd270ff483417a` |

`Workspace.Level5DevEnabled=true` and `Workspace.Level5PublicPreviewEnabled=false` remained in Edit. The Level 5 queue room was refreshed from the live `TunnelLobbyBuilder` into the existing `Workspace.ServerLobby.LevelQueueRooms.Level5QueueRoom`. It retained `LevelEnabled=false` and four offline `FutureLaunchZone17`–`FutureLaunchZone20` pads. Its Level 5 theme has 89 decorative BaseParts and 3 PointLights. No other queue room was intentionally changed. The additional built geometry is script-generated, not a stored native model; the CSG trim templates and their native backup remain as recorded above.

In Studio Play, the owner passed the F-key DEV entry and solved all seven section puzzles through their client UI; each `PuzzleXSolved` became true and `SectionGateX.FullyOpen` became true. The built world had 28,923 descendants and 27,694 BaseParts in an isolated clone; the Play world had 29,671 descendants. A separate static body-box scan over 135 route waypoints and 1,884 samples found no nongate horizontal blockers. This is not a multiplayer or full avatar traversal test. The Play console showed no Level 5 error. The queue room's refreshed theme, offline pads and DEV preview flags were also inspected in Play.

Reference comparison still has material visual gaps. In particular, the neighborhood and atrium facades retain visible Roblox geometric simplification versus the supplied photographs. The Level 5 map is therefore not verified as 1:1. Studio's **Save to Roblox** reported `Saved new changes in "BACKROOMS: STAY QUIET [CO-OP HORROR]" to Roblox.` after these changes. This confirms a Roblox draft save, not a Publish to Roblox operation. Publication remains blocked by the visual fidelity requirement. A full post-change native `.rbxl` backup remains outstanding because the Studio Download a Copy save panel did not yield a valid save action; the earlier full native place and CSG backup are preserved.
