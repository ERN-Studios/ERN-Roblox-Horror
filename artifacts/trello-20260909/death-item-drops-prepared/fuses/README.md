# IpCKlAsz — carried fuse death drops (Level 1 only)

Direct card readback confirms: “When a player dies while carrying fuses or CDs, drop those items on the ground where they died. Make the dropped items easy for other players to see and pick up.” No comments/checklists, currently To Do. This proposal covers fuses; the independent CD proposal is in `../cds`. No runtime, Studio, UI or Trello writes were performed.

## Diagnosis and change

`PuzzleManager` owns a private `session.carried[player]` count. Previously it retained that count through death and rebuilt the hand visual during Emergency Re-entry; there was no floor pickup. A relay's existing 0.55-second release callback also granted one fuse without checking whether its original character was still alive/current.

The one-file patch adds a small death pickup model under the existing `PuzzleItems` folder. One stable gold fuse, two caps, a steady light and an occluded **FUSE / FUSES ×N** label represent the exact carried count. A normal proximity prompt uses a short 0.25-second hold and 9-stud range. The existing server `canUsePrompt` revalidates frozen membership, alive character, distance, line of sight and escape state; the new pickup also requires InRound, RoundActive and the current bound character. Claiming consumes that model once and transfers its exact count atomically, before any message or visual work.

Death captures the old body's position, creates its stack, sets carried count to zero and removes its hand visual. Duplicate Died/CharacterRemoving callbacks cannot make another stack. The binding settles a dead previous body before CharacterAdded switches ownership, and stale callbacks cannot consume a new character's inventory. No yielding character wait or recurring poll is introduced. Re-entry bodies get the same death binding. Existing healthy character replacement behavior is preserved.

Ground placement uses the actual `MazeGenerator.floorTile` contract shared by normal carpet and pit gangways: an anchored horizontal Fabric part, height 1, center Y = −0.5. It selects the nearest point inset 0.8 studs from that part's edges, verifies an upward ground ray and a clear 1.4 × 2 × 1.4 world-only volume. The player's death XZ is retained when the current floor permits that footprint. A pit/void death is recovered on the nearest verified carpet/walkway instead of the lethal bottom 50 studs below. Collidable Maze/Decor geometry can reject a candidate; avatars are excluded from ground/obstruction selection. This is a rare per-death scan, not a new heartbeat or navigation service.

If the current character dies or is replaced during relay release, the still-owned one fuse is dropped at the captured death position, rather than credited to a corpse or fresh body. The callback empties its relay **only after** inventory/drop ownership succeeds. If no verified floor exists, it keeps the fuse parts, restores their original poses and re-arms the relay for another attempt. The ordinary carried-count death path likewise retains its inventory if every floor is invalid; a world with no surviving playable floor is not claimed as a successful recovery. Normal round cleanup destroys the same PuzzleItems folder and disconnects its tracked callbacks.

Dropped cores are appended to `session.fuses`. The unchanged objective-target function is refreshed after death/pickup and after a successful relay release has destroyed its old core. Boxes, lever/clutch timing, noise, rewards, purchased re-entry, profile data, exit handling and the existing disconnect policy remain unchanged. Disconnect-only item recovery is outside this death-specific card.

## Frozen files and focused evidence

Only `ServerScriptService/Level 1 Systems/PuzzleManager.Script.lua`:

- Before raw SHA-256: `4c0b34b99dfb6c09b439d06ab4cbab65fa0049f25ce09392f1032d7d258465eb`.
- Before canonical SHA-256: `a1106750a601641302d2be41f5940b09b97c13a06d33ba8a57e8b2a7c3eb8111`.
- Proposed SHA-256: `204f3edd93c7970882a2379a12c141b55acc3c941f137ee48e5955fc3e2e090c`.

Run from repository root:

```powershell
python artifacts/trello-20260909/death-item-drops-prepared/fuses/prepare.py
python artifacts/trello-20260909/death-item-drops-prepared/fuses/test_fuses.py
```

Preparation snapshots the exact baseline and only writes this artifact directory. The narrow pure `transform(source)` preserves other edits when its anchors still match; inspect the merged diff instead of copying an obsolete whole file over a newer runtime.

**92 actual-source checks pass**, including server prompt guards, two-player count conservation, duplicate/deferred death, re-entry and stale session callbacks, exact current character, actual 0.55-second callback with death/re-entry/cleanup, source-owned objective target after the relay core is destroyed, normal floor/pit/walkway/edge/blocked/no-floor cases, and retained relay retry after all ground checks fail. Two negative controls execute the original death binding and original delayed grant, and fail the specific new death/late-grant assertions. The entire proposed script compiles. The complete existing box/lever/clutch/exit/reward tail and round cleanup/start prefix are byte-identical after newline normalization. The runtime raw SHA remains unchanged.

The host executes the actual functions/callbacks against deterministic Instance, signal and axis-aligned geometry stubs. It does not simulate Roblox raycasts, physics, deferred engine delivery, prompt input, font rendering, or replication. Those need the normal native acceptance below. Independent review is **9/10**, with no remaining required code correction; see `independent-review.md`. Root's read-only `../studio-baseline-check.json` also confirms the preserved disk baseline matches the actual Edit source canonically. Neither review nor baseline equality is native acceptance.

## Native acceptance for root

Use the shared read-only observer at `../native-readonly.server.luau` when root has prepared it. It reports actual models, prompt/marker facts and objective targets; it cannot read private carried counts, so a hand visual alone must not be treated as an inventory count assertion.

1. Install the scoped PuzzleManager proposal only after before-source verification/backup. Compile/read back. Start Level 1 through the normal lobby with two real clients. A extracts two fuses and B remains alive. Note A's actual carry HUD and relay emptiness.
2. Let A die on ordinary carpet. Verify one `PuzzleItems.DroppedFuses`, `FuseCount=2`, stable position near recorded death XZ on the floor, visible gold core/label, and A's carry HUD becomes 0. Verify the actual objective target references a surviving world pickup. Check from two viewing angles and a narrow/touch layout; the marker must be legible without filling the screen or shining through walls.
3. A's corpse/spectator cannot pick up. B approaches and uses the actual prompt. B's HUD increases by exactly 2, the stack disappears, and a repeated interaction cannot increase it again. A wall, excessive distance and escaped/lobby player remain invalid. Deposit a recovered fuse in a real box: one unit is consumed and the existing objective advances normally.
4. Use an already available/test-safe re-entry path without making an account purchase. Verify A returns with zero carried fuses, can collect another and drops it on a second death. If no safe re-entry entitlement is available, record that native case pending rather than awarding a paid item.
5. With B alive, let A die by a pit. Check the pickup is on the nearest supported walkway/carpet, not the kill floor or over open air. Walk B to it and collect normally. Repeat a death next to a wall/furniture; verify no embedded or inaccessible model. Save the real world coordinates and ground evidence.
6. When feasible, have A die during the 0.55-second relay release. Confirm the relay ends empty, one recoverable additional fuse appears at the death location, and neither the corpse nor a new body acquires a hidden count. Stop/restart the round: old models and callbacks must be gone.

No currency, badge, persistent profile or extra player instance is needed for this acceptance. Root owns actual input, native evidence, critique ≥8 and separate publication. Neither half of the overall card is claimed installed or published by this artifact.
