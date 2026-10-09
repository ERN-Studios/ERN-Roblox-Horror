# PoolSlide: normal-round native acceptance helper

Prepared only for root's `GdkBpbkc` encounter verification. No Studio input, runtime/source changes, image/animation changes, uploads or tests of Trello cards in Testing were performed here. The complete helper compiles with Luau 0.737 (15 KB bytecode). Its actual Observe function passes 34 focused checks; removing the owner/round guard is rejected by the negative control. These checks address a reviewer-found incomplete-window issue and are not a broad test suite. Independent final review is pending.

## What it measures

`Acceptance.Server.Script.lua` must be a **normal server Script in a running Studio Play server**. Its `ServerStorage.PoolSlideAcceptance` is a BindableFunction, not a RemoteFunction. This is necessary to use the same ModuleScript singleton cache as GameManager's real round; requiring the controller in an unrelated plugin context can return an inactive duplicate.

The helper reads the actual `Adapter.GetManifest()` and `Controller.GetDebugSnapshot()` and calls only `Objective.DebugActivatePump(index, actualPlayer)` for the requested mutation. That existing activator uses the ordinary living-player, round, distance and line-of-sight checks. The helper never calls the pair shortcut, starts the controller, creates an entity, edits a pump count, modifies flags, pauses either hostile, changes health, creates a dummy/player or moves the tester/AI. Root positions the connected tester externally, then calls Pump. This is server activation of the actual objective handler, not proof of holding a physical prompt for 1.6 seconds.

Observation windows sample actual runtime Model pivots and the existing Navigator foot/waypoint/goal/error snapshot at roughly 10 Hz. Every seen model receives a private report identity tied to the actual Instance. Reports include workspace tagged-model counts, controller spawn count/phase, AttackSerial, target UserId and tester position/HP. Path distance, net distance, maximum displacement, model identity changes and unusually large steps are reported separately. Path distance alone is not accepted as navigation progress: circling, a stationary route query, or an external model teleport must not be labelled successful pursuit.

The old `level2-tunnel-native-navigation.luau` only certified geometry queries on a temporary clone. Its actual world-manifest pattern is reused here; its clone and `_walkingEdgeClear` queries are not used as moving-entity acceptance.

## Start in a real round

1. Root first finishes and installs the separately reviewed encounter/animation configuration. Launch Level 2 through the normal lobby queue. This helper does not enable PoolSlide or bypass rig verification. `Begin` explicitly refuses a disabled/unavailable controller, so an absent encounter cannot falsely pass the zero-pump case. A captured `StudioValidationMode=true` remains validation-only evidence, not proof that production acceptance guards pass.
2. In Play only, create a Script under ServerScriptService, set its complete Source through UpdateSourceAsync, and run it normally. Do not save the helper in Edit or the sync manifest. It refuses duplicate `PoolSlideAcceptance` instances; remove the previous helper before installing another. Its Destroying handler removes its own BindableFunction.
3. Invoke from the server side, using the real connected tester:

```lua
local probe = assert(game.ServerStorage:FindFirstChild("PoolSlideAcceptance"))
local player = assert(game.Players:GetPlayers()[1])
return probe:Invoke("Begin", player.UserId)
```

The report records the actual layout Seed and Generation. `Manifest` returns the existing server manifest if root needs exact room/corridor references. `Pumps` returns each real `Index`, current prompt position, activation distance, LOS flag and running state. Use the actual indices; do not assume array order is pump identity.

## Three layouts, one sequence per layout

Use three distinct normally generated layouts, recording seed/generation and the final installed source hashes with each export. Change pump order across layouts (for example 3→1→2, 2→3→1, 1→2→3, when those indices exist) so a station index cannot be mistaken for the number of distinct started pumps. Export before beginning the next layout; Begin starts a fresh report.

`Observe` starts asynchronously and returns immediately, letting root operate the camera/player during an observation. `Status` returns Busy, the latest window's result/error and its motion summary. Wait for Busy=false before Pump, another Observe or Export. Windows are bounded to .5–30 seconds and a report to 24 windows.

```lua
probe:Invoke("Observe", {Label="zero pumps", Seconds=2,
    Pumps=0, Models=0, Phase="DORMANT", SpawnCount=0})
-- Later, after Busy=false:
return probe:Invoke("Status")
```

`ExpectationsPassed` requires the complete requested duration and unchanged helper owner/original active round, and checks every sample in that window, including model count AND tagged count. A removed/reparented helper, replaced manifest/generation or ended round records an incomplete/Interrupted window and cannot pass. It is not a blanket motion/attack score. Preserve failed windows and errors; they are evidence rather than reasons to weaken expectations.

1. **0 pumps:** the window above must pass while Controller.Running is true. Record actual zero models.
2. **First distinct pump:** position the real living tester within the selected pump's normal reach and LOS, then `Pump(index)`. It must return Accepted=true, CounterCorrect=true and ExpectedAcceptance=true. Observe 2 seconds with Pumps=1, Models=0, Phase=DORMANT, SpawnCount=0.
3. **Repeat the same pump:** stay/reposition within normal range and invoke the same index. Accepted=false is expected; CounterCorrect and ExpectedAcceptance must remain true. Observe again at Pumps=1/Models=0/SpawnCount=0.
4. **Second distinct pump:** position near a different pump and activate it. First observe a bounded spawn-wait window with only Pumps=2 expected; models may legitimately be 0 while real deferred spawn/navigation work runs. Inspect Snapshot for actual `Models[1].Id`, Controller.SpawnCount=1 and Phase=ACTIVE. If no model appears, save the actual failed-spawn state/error and bounded wait duration. Never clone a replacement or directly start the controller to make the case pass. Once spawned, observe Pumps=2, Models=1, Phase=ACTIVE, SpawnCount=1, SameModelId=the observed ID.
5. **Repeat the second pump:** its return must be rejected without increment. Observe again with the same model ID and SpawnCount=1. Confirm no duplicate model transient was recorded.
6. **Third distinct pump:** activate the remaining pump. After the controller's next normal heartbeat, observe Pumps=3, Models=1, Phase=ENRAGED, SpawnCount=1 and the **same** model ID. The pump handler's immediate After snapshot may precede that heartbeat; use the bounded observation to establish escalation.

Example stable entity window (replace the actual ID):

```lua
probe:Invoke("Observe", {Label="third distinct: same entity enraged", Seconds=3,
    Pumps=3, Models=1, Phase="ENRAGED", SpawnCount=1, SameModelId=1})
```

## Physical navigation and attack

After the phase sequence, record a 20–30 second live pursuit window. Root chooses a traversable connected route from the actual manifest, including a doorway/corridor turn, and positions or walks the real tester on it. Keep `EntityPaused=false`; the helper reports its value but never changes it. Root must not move the entity or replace its route/position. When teleporting the tester for setup, do so before that window and identify the setup in its label.

For convincing motion evidence, inspect sampled model pivots alongside Navigator.Position and waypoint/goal progression, the net/maximum displacement toward the tester, route failures and actual camera footage. A single large movement, high cumulative distance with low net progress, a model identity change, or query-only success is not enough. `LargeSteps` is an investigation flag using the configured maximum run speed plus an 8-stud tolerance; it is not a collision proof or a universal teleport detector.

For attack, keep the actual tester in the visible swing range/front/LOS and record the windup, AttackSerial increase and subsequent HP drop at the installed windup timing. The current controller targets real Players, so a loose humanoid dummy would not exercise normal target selection. This helper supplies no fake second player or dummy. Pool Foam remains present: a health drop alone cannot be attributed to PoolSlide. Correlate the actual swing/target/serial/time and ensure the other encounter did not cause it. If the attribution is ambiguous, report attack as inconclusive. A successful fatal hit can naturally end this one-player round; no healing or resurrection is performed by the helper.

No fixed distance or attack claim is manufactured by the helper. Root records what actually happened on each of the three layouts. The raw samples allow independent assessment, including a failure or a circling route.

## Normal cleanup and exporting evidence

Use the normal failed-round/return-to-lobby flow for teardown, then call `Cleanup` **before stopping Play**. It only observes: the original world must be unparented, Adapter.GetManifest() nil, Controller.Running=false, no workspace PoolSlide tag, and all held old model Instances unparented. It does not call Adapter.Cleanup/Controller.Stop. Do not start the next layout before this check, as a new manifest would obscure teardown acceptance.

Do not enter the Level 2 completion slide as a cleanup shortcut. Normal completion can award a real badge via existing monetization code. Pump activation and the helper itself call no badge/DataStore/purchase API, and this sequence does not complete the level. Keep Studio API access unchanged/off and do not use purchase/profile tools. Root remains responsible for the normal run's external side effects; this helper is not a global service sandbox.

```lua
return probe:Invoke("Cleanup")
-- Then export; no raw Instances are in the serialized report.
local export = probe:Invoke("Export")
return export -- Bytes and Chunks
-- Read every numbered chunk separately and concatenate exactly on disk:
return probe:Invoke("Chunk", 1)
```

Save each full JSON as `pool-slide-acceptance-<actual-seed>.json` with the native camera evidence and concise result. A partial/truncated tool response is not a complete report. Export freezes the current JSON string; repeated Chunk calls return that same capture. Stop Play after evidence is saved and verify neither this helper Script nor PoolSlideAcceptance exists in Edit. Root owns source parity, final critic review and mouse publication. This helper has never been executed in Studio by its author.
