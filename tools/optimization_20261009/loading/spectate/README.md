# Spectator streaming focus proposal, 2026-10-09

Status: prepared and verified offline; **not applied to Studio**. All Studio access
was read-only in the owner's preserved Play session. No real replication-focus API
calls, runtime changes, Play transitions or publication occurred.

## Problem and resulting behavior

SpectateController moves a Scriptable camera to another player's Head. GameManager
already validates that target and reports SpectatorCount, but the reviewed source
has no streaming focus at the watched body. With a 384-stud target radius and
Opportunistic stream-out, a separated spectator can lose the watched player's world.

The scoped GameManager patch attaches one additional replication focus to the
validated target's live HumanoidRootPart. It leaves the default own-character focus
unchanged and removes the former added focus before adding another.

- Selection changes, round reset and PlayerRemoving detach immediately.
- The existing one-second reconciliation handles target death/escape, membership
  changes, spectator respawn, target character/root replacement and late root arrival.
  A spectator character identity change ends the prior camera owner.
- One focus record exists per spectator. There are no per-pair/character connections;
  the only added connection is one GameManager-lifetime PlayerRemoving listener.
- A failed add does not fabricate ownership. A failed removal retains ownership for
  the next reconciliation and prevents another added focus. Reconciliation continues
  for owned records even if the target map is already empty.

Existing target validation, spectator-count semantics and the rest of GameManager
remain scoped to the captured before/after spectator block. The entire proposed
GameManager compiles with official Luau 0.741.

## Source and tests

GameManager.before.luau is a **Server datamodel snapshot taken during Play**, with
Source/editor parity true. baseline-capture.json records its Script class, exact
path, byte length and SHA256. The baseline is not authorization to overwrite Edit.
Before any deployment, reread the exact Edit instance and its editor source, compare
inside the write and reconcile fresh changes. A full native place backup is still
required before game mutations.

spectate.before.luau, spectate.proposed.luau and spectate.patch.diff isolate the scoped
change. GameManager.proposed.luau is a compilation/review artifact.

Run:

```powershell
python tools/optimization_20261009/loading/spectate/test_spectate_focus.py --luau G:/Roblox/MongoTV/_local/optimization-20261009/luau-0.741/luau.exe --emit-native tools/optimization_20261009/loading/spectate/native-contract-probe.luau
```

51 focused offline contract checks pass, including the existing count-validation
cases, negative Studio UserIds, duplicate selection, remove-before-add, multiple
spectators, round/reset/leave/death/escape/respawn cleanup, root replacement,
detached/late roots, idempotence and API failure recovery. offline-result.json records
the full proposed source SHA256. The native fixture is prepared but not run and uses
mocked Players/focus APIs; stage only in a fresh empty ModuleScript, verify originals
before/during/after staging and destroy the probe after success or failure.

This does not prove native focus API behavior, gameplay, actual streaming or
multiplayer performance. Before applying/publishing a 384/64/Opportunistic/Improved
configuration, verify in an actual multiplayer test that separated spectators
receive the watched player's scene, selection/respawn/round reset removes added
focus, and client/server memory and workload remain bounded. Native instance
properties still need inspection in Edit.

## Official references

Streaming normally follows the character, and added replication foci enable another
region at a workload/memory cost. Improved models may disappear after their last
part streams out. Persistent collision and atomic slides retain their respective
contracts and reduce the memory savings available from radius changes.
[Roblox instance streaming](https://create.roblox.com/docs/workspace/streaming)
and [Player API](https://create.roblox.com/docs/reference/engine/classes/Player).
