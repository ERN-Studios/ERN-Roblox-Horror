# Loading prioritization proposal, 2026-10-09

Status: prepared and checked offline; **not applied to Studio**. The owner explicitly
keeps the current Play test running. This task made no Studio mutations and performed
no real asset fetches, gameplay actions, stop/start Play or publish.

The current authoritative Lobby Loading Screen gates every supported content ID in
both streamed lobby roots and the entire PlayerGui, including hidden round, death,
wheel and equipment UI. The proposal retains server preparation, lobby readiness,
stream requests, floor raycasts, success callbacks, retry recovery, the four-worker
foreground owner and the owner's bounded texture settling allowance. It changes
which content belongs to the initial cover:

- Visible screen UI and world assets within 128 studs of the actual arrival character.
  A host's oriented bounding box determines distance, so large/rotated geometry is
  treated conservatively without assuming room or prefab names.
- Disabled screen/billboard/surface GUIs and descendants of hidden GuiObjects are
  omitted. Surface/Billboard Adornee and Billboard Attachment hosts are respected.
  Raw imported/template content without a rendered host does not enter the boot gate.
- Remaining currently streamed lobby content is warmed after the cover fades, with
  one worker and one retry. Unopened menus remain demand loaded. Late streamed
  descendants enter a queue, indexed 200 at a time, without rescanning the map.
- Background scheduling stops on round/live-level entry and after 20 seconds.
  Arrival connections disconnect at the cap even if an uncancellable engine fetch
  has not returned. A skipped foreground pass must drain its engine ownership first.
- Critical/background counts are stored as diagnostic Player attributes. Background
  work cannot set LobbyLoadingDone, hold a cover or reopen one.

The entire Level 1-6 round/live loading section remains byte-for-byte equal after
LF normalization. Round Loading Runtime and LoadingCardView need no change.

## Fresh evidence

Baseline Source/editor parity was true for:

- ReplicatedFirst.Lobby Loading Screen, LocalScript
- ServerScriptService.Round Loading Runtime, ModuleScript
- ReplicatedStorage.LoadingCardView, ModuleScript

Exact exported baselines and SHA256 values are in baseline-capture.json. Builder and
TunnelLobbyBuilder topology sources were also read fresh, with Source/editor parity.
Edit Workspace contained neither runtime lobby; both are built by authoritative code.
Read-only Client inspection during the existing Play test subsequently found:

- LobbyReimaginedPreview: 4,009 descendants, including BlenderVisuals,
  PreviewQueuePads, InfiniteTunnelEnd, R3ShopDisplay and ArrivalGate.
- ServerLobby: 3,936 descendants, including TunnelGeometry, LevelQueueRooms,
  LevelDoorways, TunnelDetails and LobbySpawn.
- Migrated LobbySpawn: 220, 30.4, -860; character near 219.19, 34.14, -860.90.
- Many PlayerGui screens were hidden/disabled while lobby buttons were visible.

A later read-only content census caught the owner in a level near x=40016, y=603,
with only 33 streamed ServerLobby descendants and 1,765 PlayerGui descendants.
client-asset-census.json records that phase explicitly. It is **not a lobby join
baseline**, and its 34 total/0 critical IDs must not be used to claim join improvement.
No RAM, FPS, download-time or bandwidth improvement has yet been measured.

## Verification

Run:

```powershell
python tools/optimization_20261009/loading/test_loading_policy.py --luau G:/Roblox/MongoTV/_local/optimization-20261009/luau-0.741/luau.exe --emit-native tools/optimization_20261009/loading/native-contract-probe.luau
```

The proposed full script compiles with official Luau 0.741, and 51 offline contract
checks pass. They exercise the extracted production census/policy, preload engine
owner and background worker against mocked engine boundaries: OBB rotation/radius,
hidden and disabled UI, world GUI adornees, content ID dedup, streamed arrivals,
callback success/failure/absence, exception cleanup, worker bounds, retry/skip
ownership and round/live/deadline cancellation. offline-result.json identifies the
exact proposed source hash. This is not a gameplay or actual-asset performance pass.

Prepared but **not run**:

- native-contract-probe.luau: same scheduling contract in Studio Luau, with mocked
  engine boundaries. It returns a function and is safe to stage only in a fresh
  empty ModuleScript after Edit becomes available.
- native-visibility-probe.luau: 14 visibility/OBB checks on real, fresh, unparented
  non-script Instances. Its test-owned root is destroyed on success and failure.

The coordinator must verify authoritative originals before/during/after staging,
using exact empty Source/editor baselines for each fresh ModuleScript, then destroy
the probe scripts in both success and failure paths. Never clone a source container.

Required runtime checks after authorized Edit deployment:

1. Fresh lobby join on desktop and touch: capture critical/background counts,
   join-to-control, initial art sharpness and peak RAM on the same route/device.
2. Slow/failing downloads: retry, ENTER ANYWAY and REJOIN must remain usable.
   Foreground must never exceed four workers, background one.
3. Walk from spawn toward each lobby bay while background warming runs; verify
   nearby scene/UI appears correctly and the 20-second watch cap drains.
4. Enter a round or live Level 5/6 during warming; no later lobby requests may
   start, and the imported level cover/readiness handover must remain correct.
5. Confirm actual mobile/UI devices and camera sightlines justify 128 studs;
   adjust against fresh source if that radius reveals material initial-art gaps.

## Official references

Roblox recommends preloading only essential assets rather than indiscriminately
warming an entire world, and documents success status callbacks and unsupported
asset types. This change retains the existing typed mesh/PBR carrier behavior:
[ContentProvider](https://create.roblox.com/docs/reference/engine/classes/ContentProvider).
Preloading does not remove replicated instance memory; world streaming and
ReplicatedStorage archival are separate changes:
[Improve performance](https://create.roblox.com/docs/performance-optimization/improve).
