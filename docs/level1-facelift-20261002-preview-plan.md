# Level 1 Blender preview integration — 2026-10-02

Read-only Studio analysis of connected Studio `86f22f6f-aafa-4af2-b2dc-cf471bf0e3a4`, place `131311258779917`. Studio initially ran Play; the owner task's root agent intentionally stopped it, then the relevant sources were rechecked in Edit. The new access/button scripts were subsequently implemented offline; this document does not claim they were installed, played or published.

## Authoritative source locations

| Studio instance | Class | Source bytes | Editor matches Source |
| --- | --- | ---: | --- |
| `ReplicatedStorage.DevAccess` | ModuleScript | 1353 | yes |
| `ServerScriptService.Level4V4PreviewAccess` | Script | 12317 | yes |
| `ServerScriptService.Level5PreviewAccess` | Script | 12232 | yes |
| `ServerScriptService.Level6PreviewAccess` | Script | 12632 | yes |
| `StarterPlayer.StarterPlayerScripts.Level4PreviewPrompt` | LocalScript | 1620 | yes |
| `ServerScriptService.LobbyReimaginedPreview.QueueBridge` | ModuleScript | 20289 | yes |
| `ServerScriptService.LobbyReimaginedPreview.Bootstrap` | Script | 1217 | yes |
| `ServerScriptService.GameManager` | Script | 165258 | yes |
| `ServerScriptService.TunnelLobbyBuilder` | ModuleScript | 118480 | yes |

Script mirrors use `<name>.<class>.lua` beneath the matching service directory. The pre-task repository copies of QueueBridge and the preview controllers are older than Studio: notably the repo QueueBridge was only 73 lines, while Studio contains 398 lines and the current R4 cohort queue launch protocol. They must not replace the live sources.

## Existing preview behavior

`Level4V4PreviewAccess` targets `Workspace.Level 4 Cinema Blender`, requires `Level4Preview`, `PreviewOnly`, `Level4LayoutVersion == 4`, and `Level4PreviewReady`, and lands at the descendant `Level4V4Exit`. `Level5PreviewAccess` uses the equivalent isolated suburb model and exit. Level 4 and 5 are walk-in visual previews; they do not call the campaign `playRound` function. Level 6 calls its dedicated `Level 6 Systems.Level 6 Preview Runtime` and has `EnsureWorld`, `Join`, and `Leave` behavior.

The existing server entry checks authorize the exact host, not just a prompt name: `DevAccess`, living current avatar, no anchored/seated root, not `InRound`, not a reserved round server, distance, cooldown, world readiness, a return prompt, and colliding landing floor. They recheck the avatar, host and destination after `RequestStreamAroundAsync` yields. Level 4 and 5 also eject unauthorized avatars from the distant preview bounds. New Level 1 entry must preserve those boundaries.

`Level4PreviewPrompt` hides Level 4–6 proximity prompts locally, fail-closed if `DevAccess` is missing or fails. It does not hide a physical mesh or sign. A new visible physical Level 1 button must therefore be created locally for authorized developers, or be invisible by default with a local-only billboard. Hiding a prompt alone does not satisfy “only developers can see the button.”

`DevAccess.IsAllowed` currently accepts exactly UserIds `40920547` (mikkelczar) and `9488575949` (LaverSneglen). `IsLevel6PreviewAllowed` additionally permits `11374988579` (ZenMeister02); this is a Level 6 exception and must not be used for the new Level 1 preview. Studio mode is not authorization for the Level 1 button.

## Level 1 rooms and placement

The saved, authoritative public lobby room is `Workspace.ServerLobby.LevelQueueRooms.Level1QueueRoom`, a Model with `LevelNumber == 1`, `LevelEnabled == true`, `Level1InspiredBay == true`, and `CircularBayDiameter == 56`. Its direct `ChamberFloor` center is `(-63, 29.58, -840)` and the floor top is about `30.28`. Four existing queue pads are centered at X `-72`/`-54`, Z `-853.2`/`-826.8`, around Y `30.45`.

Suggested invisible entry anchor: `(-83, 34, -840)`, inside the room, between the queues and the back wall. It must be anchored, transparent, `CanCollide/CanTouch/CanQuery == false`, and have an explicit task ownership attribute. A local-only billboard can give the entry a visible “LEVEL 1 FACELIFT · DEV PREVIEW” label while the server owns only the invisible host and secured action. The user-visible button must not appear at the general spawn or outside this room.

The separate Blender lobby preview does not exist in the saved Edit Workspace. `ServerScriptService.LobbyReimaginedPreview.Bootstrap` builds it during Play after an authorized developer joins (the existing bootstrap also has a Studio bypass). Its runtime Level 1 room is `Workspace.LobbyReimaginedPreview.PreviewQueuePads.QueueBay_Level1`; its direct `ChamberFloor` is centered around `(157, 30.4, -840)`. An optional second Level 1 entry can be attached here after checking the lobby's explicit ownership, readiness and revision attributes. Place at the floor's world center plus `(-20, 3.6, 0)`; do not alter the four queue zones.

## Smallest scoped integration

1. Add a dedicated `ServerScriptService.Level1BlenderPreviewAccess` Script and one `StarterPlayer.StarterPlayerScripts.Level1BlenderPreviewButton` LocalScript. Both have now been implemented as new files. The server script owns transparent entry hosts, checks `DevAccess.IsAllowed`, and invokes `ServerStorage.Level1BlenderPreviewLaunch:Invoke(player)`, expecting a boolean and reason. Per the owner's later instruction to copy Level 4–6, the local script now creates the native `ProximityPrompt` with the same hold 0.5/range 10/no-line-of-sight/DEVELOPER PREVIEW settings and the action `ENTER LEVEL 1 FACELIFT PREVIEW`. The complete UI exists only after the shared allowlist succeeds, survives respawn, and hides during a campaign/Level 6 round. Neither script overwrites existing Level 4–6 access controllers or expands QueueBridge.
2. Bind only the exact Level 1 room anchors and ready preview/round route. Revalidate host ancestry, room/floor identity, player/character, distance and authorization after every yield. Keep a bounded cooldown, report failed generation/streaming, and provide a verified return path before entry.
3. Preserve public Level 1 queue admission and campaign progression. QueueBridge's `IsPreviewEntry` intentionally accepts only levels 4–6; its registration whitelist also contains only those existing controllers. Level 1 public queue zones 101–104 must not be converted into preview queues.
4. If this is a walk-in asset review, a dedicated runtime can expose `EnsureWorld`, `Join`, and `Leave` like Level 6, without touching `GameManager`. If the preview must run the existing Level 1 gameplay, the preview entry needs a scoped authorized round variant that reuses `GameManager`'s existing loading/round flow and swaps only the maze builder. A walk-in teleport cannot honestly be described as preserving the gameplay loop.

The existing Level 1 gameplay depends on shared `Workspace` round flags, globally named `Maze`, `Elevator`, `Entity`, and generated markers. It cannot safely run a second full original Level 1 loop concurrently with a lobby/world preview merely by setting `GenerateWorld` or `RoundActive`. The round variant needs to be selected before generation, carried in the reserved-server launch packet, and checked independently against every participant's `DevAccess` on arrival. Normal Level 1 queues must never select it. Studio can use the existing single-round fallback and reject preview launches while a round is busy.

## Verification needed

- Developer and ordinary-player clients: whole label/button absent for the latter, entry denied by server even if a hidden prompt is triggered or a remote is spoofed. Level 6's guest exception denied.
- Living-avatar entry/return, unreachable spoofed host, host/world replacement during streaming, failed generation/streaming, double clicks, departure and respawn cleanup.
- Both current Level 1 lobby room hosts, without stepping onto or changing existing public queue pads.
- Generated seed connectivity, real colliding floor and doorway clearance, objective reachability, and safe participant landing spacing.
- Actual gameplay round, entity/navigation and cleanup/performance measurement for the facelift; source inspection is not evidence of these passing.
- Exact source/asset mirror and staged diff, then successful Roblox publication of the existing experience only after material checks pass. The owner's later explicit instruction says no backups; this task does not create a new native place backup.

No Studio mutation or Play-state change was performed by this analysis agent. Graphify's existing graph was queried first; it contains historical records and was insufficient for the current R4 launch protocol. The live sources above supersede its older edges.

Offline verification: `tools/tests/test_level1_blender_preview_access.py` executes the real gate and room validation in official Luau with fake engine services: 26 assertions passed, including authorization/Level 6 guest denial, exact host/room/floor, living avatar, distance, request locking, cooldown, readiness/busy rejection and launch error recovery. Six server-host lifecycle and 12 complete authorized native-prompt client checks also pass, including repeated hooks, explicit cleanup, exact native interaction settings and round visibility. It executes the entire client for an unauthorized Level 6 guest and proves no visible UI is created. Both new source files compile. These checks do not establish actual Studio input, streaming, publication or gameplay behavior. Verified with `artifacts/hazmat-20260924/luau-0.737/luau.exe`.
