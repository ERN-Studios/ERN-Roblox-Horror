# Friend Boost: server recovery fix, 2026-10-09

User finding: the lobby chip is visible but stays at +0% while a Roblox friend is in the same lobby.

## Concrete defects in the captured source

- A failed friendship lookup counted zero and was not cached, but nothing retried it in an idle lobby. Only a later roster event or round prime could repair the cache. The new asynchronous regression runs the exact captured old module with both old and current API methods available; it fails after the outage clears and five simulated seconds pass: `the idle lobby recovers the friend without a roster event: expected 1, got 0`.
- The old per-player publication could fail A-to-B, then succeed B-to-A. B received +10% while A retained +0% until another pass.
- `PrimeRoster` could successfully warm the payout cache after an earlier failure without republishing the lobby attributes. Independent prime/publication workers could also repeat an in-flight uncached lookup.
- A departing friend could still be counted from a roster snapshot that yielded during its lookup; the next pass repaired it, but a stale intermediate percentage was committed.

The old API itself is not established as the cause. Root's native precheck found both legacy and current calls true for one independently verified Roblox friendship. The owner was alone in that native test server, so their displayed 0% was expected.

## Product change

Only `ServerScriptService/FriendBoost.ModuleScript.lua` changes. One serialized worker warms unordered pairs for lobby publication and `PrimeRoster`; each pair is attempted once per worker pass. Definitive booleans remain cached. Failures stay unknown and count zero. One coalesced five-second timer snapshots the current lobby and retries unresolved pairs until they resolve or their players leave. This repairs the percentage without requiring join/leave/rejoin.

Publication reads the cache without yielding and abandons a roster revision superseded during an API call. It also excludes players no longer parented to Players. Priming queues publication, and `Start` is idempotent. The supported `IsFriendsWithAsync` method replaces the deprecated method.

`CountRoundFriends` remains unchanged, cache-only and non-yielding. It counts unique verified friends from GameManager's actual round participants, rather than the whole server. The client, GameManager, config, completion reward source and all fractional payout rules are unchanged.

## Verification and preservation

- Luau 0.737 compile: PASS.
- Offline whole feature suite using repository payout: 933 checks PASS.
- The same suite selecting fresh native Monetization source: 933 checks PASS.
- Captured old FriendBoost source: expected FAIL on the new idle recovery regression, proving a behavioral defect independent of API naming.
- New controlled-coroutine cases cover suspended RPC join/leave, no duplicate simultaneous prime/join pair, no stale departed-friend publication, one-off asymmetric failure, persistent outage timer coalescing, idle recovery, successful prime-to-attribute recovery and non-yielding cache-only completion counts.
- All existing payout test cases and client harness/test constant blocks are unchanged. Test changes are confined to server scheduling/cases and exact-source payout fixture support.

The fresh native Monetization differs from the repository in foreign achievement-gift work. It was never overwritten. The fixture selector `FRIEND_BOOST_MONETIZATION_SOURCE` loads that native file; its exact whole-count helpers accompany the already-extracted achievement unlocker. Existing friend arithmetic still carries 0.2 tokens per friend per two-token clear in tenths and pays a whole bonus once accumulated. These offline tests exercise the completion handler; they do not claim to validate the unrelated Luna gift feature.

Product SHA-256: `b031f800fa6158d6feb8df47ec8095baa340e3b5f98a01dc2149128b2440119b` (7,972 bytes).
Test SHA-256: `5fc5c225d6e4e3f07deebd21cf0cfc3287ddd87445489a6fb21dda3a4a58718b`.

Evidence: [proof](PROOF.json), [native-to-candidate source diff](FriendBoost.native-to-candidate.diff), [agent-only test diff](test_friend_boost.agent-only.diff), [old-source red regression](old-source-red-regression.txt), [repository payout test](repo-payout-test.txt), [native payout test](native-payout-test.txt), [compile](compile.txt).

## Practical limit and native follow-up

Roblox documents that [IsFriendsWithAsync caches answers](https://create.roblox.com/docs/reference/engine/classes/Player/IsFriendsWithAsync); this fix retries API failures, but does not promise immediate refresh of a definitive false after a friendship changes within the same session. No arbitrary cache TTL or replacement friends graph is introduced.

No Studio call, multiplayer UI test, token grant, save, publish or commit was performed by this agent. Root owns native install and review. The native two-friends-same-lobby acceptance remains to be observed; offline recovery is verified without awarding tokens.
