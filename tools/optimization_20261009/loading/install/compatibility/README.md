# Fresh streaming lifecycle compatibility proposals

These two proposals were prepared from fresh authoritative **Edit** Source and editor Source on 2026-10-09. No Studio instances, properties, source, gameplay state, or native backups were changed by this task. The owner explicitly instructed that no backups be taken now. The exact pins are in `proposal-manifest.json`; a second read-only identity/Source/editor comparison passed in `baseline-recheck.json`.

| Exact authoritative path | Class / identity | Before SHA256 | Proposed SHA256 |
| --- | --- | --- | --- |
| `StarterPlayer.StarterPlayerScripts.Level 2 Sound Controller` | LocalScript / `1_31079` | `9f8ea507c2f3e5e6a8215f117c7a0f9d33fc3cdade1c6a3a50119006ae9abb7c` | `7a0fe4360e5ffa6871df1e8cdcded6c10dda8efaa4186e7dcba59a9d2b3438e8` |
| `StarterPlayer.StarterPlayerScripts.Level 6 Playground Client` | LocalScript / `1_31113` | `a812142882845810749b6c985a1bca22a4de37b6035f1c61741df9949a122396` | `008eb778b3349b1c81ed168ccb13dacb744a2f6d945fa061d24d99d6c884131c` |

The planned streaming policy is Target 384, Min 64, Opportunistic, and Improved. Improved can remove a model after its final part streams out; individual parts can also disappear while their model remains. Stream-out parents replicas to nil and fires removal signals, without necessarily destroying the existing Luau state. Client property changes may be lost on re-entry. These are the lifecycle contracts motivating the patches. [Roblox instance streaming](https://create.roblox.com/docs/workspace/streaming)

`Level2Sound.patch.diff` releases each removed anchor from both its category list and deduplication ownership. The category stored in the existing seen table selects the one list to prune. It adds one removal connection to the existing session-owned connection list, so world replacement, round end, and root removal still disconnect everything. Same-instance and replacement-instance re-entry are classified normally. The fresh Poolrooms audio ownership gates, authored cues, source-aware monster scheduler, bounded sound cleanup, and all code after `randomActive` are byte-preserved. Without the change, old replicas remained strongly referenced until an entire world/session reset and each anchor search traversed the accumulated list. This is a retention risk, not a measured memory saving.

`Level6Client.patch.diff` keeps live finale baselines strong, as required by the documented runaway-brightness regression in the current script. A single lifetime removal listener restores and releases only saved finale values and the cached exit flicker lamp. It owns Color, Brightness, and SpotLight Angle; it does not change Enabled or the room budget controller. Restoration works after Parent becomes nil, and a failed restoration still releases removed references. Deferred callbacks can observe changed ancestry, which is why the callback does not gate restoration on Parent. [Roblox deferred events](https://create.roblox.com/docs/scripting/events/deferred)

The same L6 patch rereads the counting child's Body before reusing its cached rig and rebuilds against a replaced or returning Body. Fresh read-only server Source/editor parity for `ServerScriptService.Level 6 Systems.Level 6 Playground Game` confirmed an anchored Root plus welded MeshPart Body with Bones and no explicit ModelStreamingMode assignment. The cached rig previously returned before checking current Body identity. The original finale task, audiovisual timing, ReduceFlashing behavior, killcam, marker attributes, and animation code after rig construction are byte-preserved.

The existing L2 selectors already reject anchors outside the current world; source-aware distant groans wait/retry if no suitable streamed anchor exists. L6 map and authored folder lookups are generally guarded, marker destinations come from model attributes, and music horn ownership refreshes from currently present Props. No new dependency on far geometry, whole-world persistence, or another replication focus is introduced here. The installed spectator focus work remains separate.

`test_streaming_lifecycle.py` executes exact extracted proposed code with signal/replica fixtures under official Luau 0.741. Passed: **41 focused transition checks**, **800 checks over 400 rig removal/re-entry cycles**, five byte-preservation checks, and full compilation of both complete proposed scripts and all three generated probe files. Anchor and brightness caches also undergo 400 cycles each. The receipt is `offline-result.json`.

Reproduce from this workspace with a task-local environment setting:

```powershell
$env:LUAU_BIN='G:\Roblox\MongoTV\_local\optimization-20261009\luau-0.741\luau.exe'
python tools/optimization_20261009/loading/install/compatibility/test_streaming_lifecycle.py
```

`native-contract-probe.luau` is the mocked contract prepared for native Luau. `native-instance-probe.luau` is a bounded real Instance fixture: unparented test root, actual Parts/Lights/Bones, descendant removal and re-entry signals, ten anchor cycles, cached brightness restoration, Body replacement, and root/session cleanup. It owns and destroys every fixture, disconnects test signals even when assertions fail, and borrows no gameplay state. Neither probe has been executed by this task. Root must stage any probe in a fresh `Instance.new("ModuleScript")` with exact empty Source/editor baseline, verify authoritative originals during staging and after success/failure, and destroy the probe. A synthetic native fixture is not a gameplay or actual streaming/performance pass.

`native_compatibility_runner.py` reuses the root native runner's `make_code` and client without altering its four-probe defaults or receipt. Default invocation prepares two wrappers locally. `--verify-only` performs a read-only exact check of all five original installed optimization scripts plus these two compatibility sources; that check passed at `2026-10-09T21:58:29Z` and is recorded in `read-only-source-pins.json`. Every fixture embeds the exact helper code from the reviewed, hash-pinned installed proposals. Both emitted runner and module wrappers compile, and eight result-parser checks passed (`runner-preparation-result.json`).

Only root executes the mutation-bearing native tests:

```powershell
python tools/optimization_20261009/loading/install/compatibility/native_compatibility_runner.py --run
```

The runner requires completed `tools/optimization_20261009/source-install-receipt.json` and this folder's separate `source-install-receipt.json`. Its separate output is this folder's `native-probe-receipt.json`; it explicitly rejects the original four-probe receipt path. Each native phase checks all seven installed script identities and exact Source/editor bytes and preserves every other authoritative LuaSourceContainer. The first fixture must return boolean true and emit exactly one captured `STREAMING_LIFECYCLE_CHECKS=841` line. The second must return `nativeFixtureChecks=10` and `realStreamingGameplayPerformancePass=false`. Failure leaves a partial receipt and disposes only the isolated test module/fixtures; it never restores originals over concurrent edits.

Before installation root must reread both authoritative Source and editor Source, require the exact path/class/identity and baseline bytes above, and recheck the same baseline inside UpdateSourceAsync. Reconcile any intervening Studio changes. After installation compare exact proposed Source/editor bytes, allowing bounded editor propagation polling, and export the verified mirror. Do not use this proposal or repository copy to overwrite a changed Studio baseline.

Still required at the game level: actual L2 repeated movement beyond the target radius and return, root disappearance/re-entry, Poolrooms pack handover plus pump/entity cues, L6 normal/finale traversal and re-entry with stable original lamp brightness and visible child animation, and multiplayer distant spectating/target changes/leave. Measure join/frame time, instance retention, client graphics memory, and network behavior separately before stating a quantitative impact. This task makes no gameplay, multiplayer, performance, publish, or installed-state claim.
