# PlayerProtection — prepared module only

Prepared for [ak8Mgaeq](https://trello.com/c/ak8Mgaeq), 10 September 2026. The approved item is one stored charge purchased for **5 tokens**, granting **5 seconds** of protection when used. This directory implements only the temporary server state service. Nothing here is installed in the runtime source tree, synced to Studio, enabled, or published.

## API and intended integration

The proposed destination is `ServerScriptService/PlayerProtection.ModuleScript.lua`, as one server singleton. Requiring it on a client fails. It has no remotes, DataStores, Marketplace calls, healing, ForceField, inventory mutation or charge/refund logic.

| API | Contract |
|---|---|
| `GetContext(player)` | Returns a frozen `{Character, Epoch, RoundEpoch}` context and nil error, or nil and a reason. The opaque per-player Epoch and server round counter are private service state, never player attributes. Keep the entire context on the server. It refuses an already active effect. |
| `Activate(player, context)` | Requires the exact preflight context after the caller's yield. Rechecks the current Player, character/Humanoid identity, private epochs, alive state, InRound, RoundActive, Escaped and Level2_ExitTransition. Returns `true, expiresAt` or `false, reason`. The absolute deadline is server time at successful activation +5; a slow reservation cannot shorten it. No stacking or refresh. |
| `IsActive(player, character?)` | Reads only the private activation record and current server eligibility/time. An explicit old/different character returns false without cancelling a valid current-character effect. Public display attributes cannot create, extend or cancel protection. Expired/invalid records are lazily cleared. |
| `Clear(player)` | Removes the effect, clears display attributes and replaces the private player epoch, invalidating pending contexts even if no effect was active. It does not change health or inventory. |
| `Activated:Connect(callback)` | Server BindableEvent signal fires once after the private state is committed, with `(player, character, expiresAt)`. AI/capture listeners can immediately query protection and cancel that player's current target/attack/cinematic state. No private token is emitted. |

The caller must take `GetContext` **before** reserving/consuming a charge in the existing yielding profile operation, then pass that same context to `Activate` after the outcome is known. Taking a fresh context after the yield defeats the intended old-character/old-round fence. If activation is refused after a durable reservation, the future inventory integration must resolve that same reservation with an idempotent refund. This module neither implements nor certifies that transaction. Concurrent/replayed use requests still require the inventory operation identity described in `../protection-item-readiness.md`.

Published player attributes are display-only: `PlayerProtectionActive` and `PlayerProtectionExpiresAt`. The client should derive remaining time from the absolute deadline and `Workspace:GetServerTimeNow`; gameplay must call `IsActive`, never trust those attributes. The full five seconds are measured on the server, even when the cleanup callback runs late.

## Lifecycle

Records are tracked lazily when a player first requests context. One bounded per-player subscription set watches membership, escape, L2 exit transition, character added/removing and the currently observed Humanoid's death. Identity is also rechecked synchronously on API calls, including a changed Humanoid inside the same character. A deferred old Humanoid callback cannot invalidate a newer life.

Authoritative `RoundActive` changes advance the private round epoch and clear every tracked record, so consecutive rounds using the same SelectedLevel are fenced. SelectedLevel changes also invalidate state. Normal GameManager already sets RoundActive false at round end/start boundaries. Its eventual explicit round cleanup may additionally call `Clear` on participants; the service does not require a publicly writable round-generation attribute.

Each timeout closes over the exact private state and activation record. Early cleanup rechecks server time and reschedules only the remaining duration; late or stale cleanup cannot shorten the effect or remove a later activation. PlayerRemoving clears state, disconnects all per-player/death connections and removes the record. The two workspace lifecycle listeners and PlayerRemoving listener live for the singleton's server lifetime.

The offline signal host dispatches events immediately. Native integration must still verify lifecycle ordering under the game's actual signal behavior and the actual GameManager round flow. No physical multiplayer/event-scheduling proof is claimed here.

## Validation

```powershell
$env:LUAU_BIN='C:\Users\mikke\AppData\Local\Temp\codex-luau-0.737\luau.exe'
python artifacts/trello-20260909/protection-prepared/test_player_protection.py
```

**98 checks passed** while executing the complete proposed module with fake Roblox services, characters, signals and an explicit server clock/timer queue. The entire module compiles with Luau 0.737 (5 KB bytecode).

Coverage includes server-only require; frozen pre-yield context; slow reservation followed by a full five seconds; exactly one activation notification; no healing; replay/stacking refusal; forged context/other-player context/display attributes; boundaries at 4.99/5.00/5.01; old-character queries; membership/escape/exit/death/round/level changes during a yield and while active; same-level round restart; new character and replaced Humanoid; stale death callbacks; manual clear; early/stale/delayed timers; listener counts/idempotent preflight; leave/retracked state; teammate independence; and dead/missing character refusal.

Independent critic score: **9/10 for this module preparation**. The critic read the full module, harness and README, independently reran 98/98 checks and recompiled the entire module; no blocker within this scope. This does not approve runtime installation or mark the item complete. The atomic charge/reservation/refund integration, UI/input, all actual damage/sensing paths, cancellation of in-flight attacks/capture, pit expiry occupancy, mixed hiding occupants and native acceptance remain root-owned future work. The service alone does not stop arbitrary Health assignments or death. Those sites must explicitly call `IsActive` before lethal side effects, as mapped in the readiness document.
