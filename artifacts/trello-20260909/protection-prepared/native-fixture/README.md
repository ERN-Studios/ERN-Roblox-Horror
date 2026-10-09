# Play-only protection integration fixture

Prepared only. Nothing in this directory has been installed in Studio or copied
into runtime sources. The fixture runs the complete selected Monetization Script
with the real PlayerProtection module, RemoteEvent handlers, profile callbacks,
shared ModuleScript cache and Roblox timers. Its profile and ranking stores live
only in this Play server's memory. This is a native scheduling/UI integration
test with an in-memory backend, not a live DataStore or cross-server guarantee.

## Files and exact source

- `Monetization.NativeFixture.Script.lua`: complete generated Script.
- `MemoryProfiles.ModuleScript.lua`: server-only memory backend and probe.
- `prepare_native.py`: exact, single-match source transformations; fails on drift.
- `source-manifest.json` and its hash-named snapshot: selected input and hashes.
- `fixture-transform.diff`: every change from that selected input.
- `test_native_fixture.py`: executes the complete memory module in a Luau host
  and verifies the complete Script is precisely the declared transformation.

The current fixture was regenerated from the reviewed merged Developer-tag plus
Protection transactions proposal (input SHA `1f44dfa34ef69fec7cf04be80007498a1945afde0422e2e099ec9a8675d53ef4`; fixture SHA `92f78aae8fa45dbf96348d7fe651f8747eff7fb4271b70a49765fd6593bcbb82`).
The command below is the supported regeneration route if that exact merged input
changes; re-review and revalidate any new transform before native installation:

```text
python artifacts/trello-20260909/protection-prepared/native-fixture/prepare_native.py --source <merged-artifact.lua>
python artifacts/trello-20260909/protection-prepared/native-fixture/test_native_fixture.py
```

Compile both full fixture files with `luau-compile.exe --null` as well. The
transform snapshots the exact input, preserves unrelated inserted code, and
changes only the DataStore/Badge bindings and the named profile-persistence
Studio gates. Other Studio guards remain true, including the receipt's zero
CurrencySpent and MessagingService's no-publish/no-subscribe paths. No fake paid
receipt is necessary for this item test.

## Isolation and installation by root

Use a fresh, isolated **Play server**, never Edit. Keep Studio API access disabled.
The fixture independently rejects Edit, non-Studio and client execution. Set all
Sources through the existing Studio workflow while their copies are disabled.
No script in this artifact automatically installs or starts anything.

1. Stage the actual proposed `ZyntraConfig`, `PlayerProtection`, shared
   `ProtectionClient`, Store, UIDevice, HUD and regression sources in Play-only
   copies at their intended normal instance identities. Any damage/AI integration
   exercised by the test must use the same normal PlayerProtection ModuleScript.
   Do not pretend a module required in a separate bridge VM shares the game's
   module cache. Set config/service identities before first normal require;
   replacing Source after a cached require does not reload a ModuleScript.
2. Create `ServerScriptService.ProtectionNativeMemoryProfiles` as a ModuleScript
   containing `MemoryProfiles.ModuleScript.lua`. Before its first require, set
   Workspace `ProtectionNativeFixtureRunId` to a unique 8–64-character run ID.
   Optionally set `ProtectionNativeFixtureTokens` (default 5) and
   `ProtectionNativeFixtureCharges` (default 2), integers 0–10000.
3. Create a disabled normal server Script from
   `Monetization.NativeFixture.Script.lua`. Set its own
   `ProtectionNativeFixtureRunId` attribute to the identical run ID. **Destroy
   the original Play-copy `ZyntraMonetization` Script before enabling the fixture
   and before its new RemoteEvent connections are created.** Disabling or editing
   the original Source is not this isolation step. `Bind` refuses an extant
   original named `ZyntraMonetization` and refuses a second live fixture owner.
4. Enable the normal fixture Script, then start/restart the proposed client
   scripts so they bind the normal existing `ZyntraAction`, `ZyntraGetProfile` and
   `ZyntraProfileChanged` remotes. Retire old Store/HUD GUI instances if restarting
   those clients. Do not leave duplicate client input handlers. The test must
   verify a single intended command/charge; the fixture does not prove that
   destruction of every previously running client disconnected its handlers.
5. Wait for the fixture profile and initial Studio pass refresh to settle. The
   fresh memory seed marks the two existing token grants already applied solely
   to prevent Studio pass ownership from changing the chosen test token seed.
   Both recorded Robux streams begin at zero. Confirm expected Tokens, Charges,
   revision and private Active state through the probe before arming a fault.

The service facade has no real DataStoreService reference or delegate. Unsupported
methods fail instead of forwarding. Each callback receives a copy; cancelled or
throwing callback mutations are discarded, and commits/returns/snapshots have
independent copies. A normal level completion can reach the original badge side
path, so the fixture's BadgeService facade returns false for both lookup and
award without resolving the real service. Other normal Shop products remain
outside this test: use only the five-token protection card and its use HUD; do
not invoke Marketplace purchase prompts or fabricate paid receipts.

## Probe and fault commands

The normal server Script creates only a server-side BindableFunction:
`ServerStorage.ProtectionNativeFixtureProbe`. Invoke that existing function from
the server bridge; its callback executes against the game's actual module cache.
It is not a RemoteFunction exposed to clients.

```lua
local probe = game.ServerStorage:FindFirstChild("ProtectionNativeFixtureProbe")
local player = game.Players:GetPlayers()[1]
local config = require(game.ReplicatedStorage.ZyntraConfig)
local key = "u_" .. tostring(player.UserId)
local before = probe:Invoke("Inspect", player.UserId)
probe:Invoke("ResetCounters")
probe:Invoke("QueueFault", {
    Store = config.DataStoreName, Key = key, DelaySeconds = 10,
})
-- Perform the real Store/HUD action through the client next.
```

Commands:

| Action | Argument/result |
| --- | --- |
| `Inspect` | UserId → copied Profile, server Now, actual private `IsActive`, displayed ExpiresAt and Health |
| `Snapshot` | Counts of calls/callbacks/accepted writes, last 100 timed events, copied stores and pending faults |
| `ResetCounters` | Clear counts/events; preserve all profiles and queued faults |
| `ClearFaults` | Clear queued injections only |
| `QueueFault` | Exact profile Store/Key, optional DelaySeconds 0–30, FailBefore, FailAfter, ConflictTokenDelta integer ±10000 |
| `ClearProtection` | UserId → call the real service Clear; no healing or balance change |

A queued fault applies to the next matching UpdateAsync, not a fabricated API.
`FailBefore` throws before its callback, `FailAfter` commits then throws its
response away. A conflict discards the first callback result, changes the saved
token balance by the specified amount and reruns the actual callback on a new
copy. The delta is a mock competing write, not evidence of a real developer gift.
Other same-key operations can consume queued faults; check profile/pass settling
and the timed Begin/Committed/ResponseLost events instead of assuming an injection
hit the intended reserve or finalize. Invalidating the run ID or removing its
owner causes subsequent memory/probe access to fail closed. Store facades are bound
to their Script identity and bind generation; a replacement Script obtains fresh
facades over preserved data. A retired facade cannot start a later operation, and
an operation rechecks its identity/generation after waits and callback returns
before any commit.

## Native acceptance cases still to execute

Use the actual card/HUD and retain structured probe output with server timestamps.

1. Buy once at five tokens: Tokens 5→0, Charges +1, one Bought revision. A
   four-token/zero-charge variant refuses without a committed purchase. Unknown
   response retry keeps the same SessionNonce, Revision and RequestNonce.
2. Use a charge during a valid round with a 10-second delayed reserve. During
   persistence the private effect remains inactive. When activation succeeds,
   ExpiresAt minus its activation time is the full five seconds; it is not
   shortened by those ten seconds. Observe active just before and inactive after
   the deadline. Health is unchanged.
3. Repeat the slow reserve but end/change the round or character before it
   completes. No activation; the same Reserved operation refunds at most once.
4. Queue FailAfter on Buy or Reserve. The production outer retry normally resolves
   it automatically. To force an unresolved UI state, queue FailAfter followed
   by two FailBefore faults for the same key. Retry the actual shared pending
   command; there must be one debit/charge or one effect, never a second one.
5. To lose Finalize's response, queue one empty fault (consumed by Reserve), then
   FailAfter and two FailBefore faults. Verify the targeted event sequence first.
   Finalize retry must not refresh ExpiresAt or Activate again, including after
   the original five seconds expire.
6. Queue ConflictTokenDelta +7 before a five-token Buy at balance 5. The real
   callback sees the competing balance on retry: final balance 7, one extra
   charge. This tests callback retry integration, not an actual second server.
7. Same-Play restart recovery is optional: clear effects with `ClearProtection`,
   destroy the fixture Script, preserve the memory ModuleScript and re-create a
   fresh armed normal fixture Script. Its actual profile load/claim code sees
   the saved Reserved operation. The service clear models the missing effect in
   a new server; this is explicitly not a cross-server test. Verify one refund,
   then normal fresh client profile/pending adoption before another command.

Keep the existing favorable-refund limitation: a real process loss between
gameplay activation and durable finalize can refund one already-used charge.
No atomic exactly-once guarantee spans DataStore and gameplay. These native
tests supplement the existing 215 actual transaction checks; they do not replace
live-service semantics or the later damage/AI/capture and two-player acceptance.

Stop Play to discard every fixture instance, value and arm attribute. Do not
publish or copy these generated test Sources back into Edit. Inspect normal
production source parity after Stop before any eventual release.

## Current offline evidence

73 checks execute the complete memory module: fail-closed environment/owner
guards, copied reads/callbacks/commits/snapshots, cancelled/throwing callbacks,
lost-response persistence, callback conflict retry, timed delay and owner loss,
owner replacement, retired handles, actual service-probe calls and ordered-store isolation.
The exact full-source transform, unchanged receipt/messaging sections and a later
merge sentinel also pass. Both complete fixture files compile (78 KB combined).
No native installation or integration result is claimed. The independent critic
repeated all 73 checks and both full compiles: **9/10** for this prepared artifact.
`validation.json` records this exact scope.

The first independent review scored 7/10 after reproducing an owner-swap race:
A delayed write could resume after B bound and commit under B. The correction
binds both store handles and operations to the original identity/generation,
checks after each yield/callback, and preserves data behind new B-owned handles.
The permanent tests include delayed A→B, same-instance rebind, replacement during
a callback and late calls through retired handles. Independent re-review raised
the score from **7/10 to 9/10**, with both concrete findings closed.
