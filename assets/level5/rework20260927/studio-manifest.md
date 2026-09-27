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

## Verification scope

This read confirms the listed live instances and source/editor consistency only. It does not verify 1:1 visual fidelity, gameplay, multiplayer access, or publication.
