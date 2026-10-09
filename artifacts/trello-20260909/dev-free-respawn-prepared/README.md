# Developer free respawn — prepared only

Card [bwyxIUz1 / #64](https://trello.com/c/bwyxIUz1), recorded in `trello-recheck-native-active-20260910.json`: “Add a dev cheats option that lets developers respawn into the level for free after dying, without spending Robux, tokens, or re-entry credits. This option should be available to developers only.”

The proposal adds a keyless **FREE RESPAWN** action to the existing developer panel. The existing three-user `DevAccess` whitelist is enforced by both the remote command and the server-only re-entry endpoint. A dead developer can return to the current active level through its existing safe-placement and streaming path. This action does not call Monetization, reserve a credit, grant currency, or alter the existing paid re-entry allowance. Repeated developer respawn remains possible after another death while the round is open.

The existing party-down deadline remains 15 seconds. This action can recover the last developer during that window; it does not reopen a lost round or extend the deadline. Death during the initial elevator/loading sequence retains existing round-loss behavior. A Level 2 exit-transition death remains owned by its existing automatic recovery.

## Files and composition

| Runtime destination | Prepared input | Proposed SHA-256 |
| --- | --- | --- |
| `ServerScriptService/GameManager.Script.lua` | `f006dda5f63464af3c3f7a69925a4276bcbfa19c4d8ad57ced514db6663f152d` | `eba65308b340914e973877561d9812b7c7f4718f9194b40131438002709fe762` |
| `StarterPlayer/StarterPlayerScripts/DevCheats.LocalScript.lua` | `f16d6fc3f23fbd314f77498788eae3a08fb4698ba5160166064846f3eabd5aeb` | `efd034810f01f8516130f94eebf61070d4a0fff7b81f3c43e64732cf884aa3b9` |
| `StarterPlayer/StarterPlayerScripts/ZyntraStore.LocalScript.lua` | `88f25ffed330b3786c2638a437332e3a4cff68a53475a4ae115a15dae30dcbb6` | `596ff4f45406e753824778ab7cf10b6b8109ba83309332bacb88b57fea444093` |

The GM input is the reviewed Continue + slide + full-circle + ESP composition. The Store input includes the prepared upgrade-copy correction and ESP over the existing Entity Shield/logo changes. These are **planned inputs**, not the currently installed files. `manifest.json` records the actual runtime hashes separately and contains every input path. Root must install the prior changes first or compose the exact new hunks over the eventual baseline; copying these complete files over an arbitrary runtime checkpoint could add uninstalled features. The concurrent square-shop-buttons proposal owns the Store opener/layout; this proposal changes only its DEV controls block.

`prepare.py` writes only this directory, with exact source-hash and unique replacement guards. Before/proposed copies and one diff per file preserve the handoff. There are no new Roblox instances or scripts. Monetization, DevAccess, pricing, profile formats, the existing developer keys and all arrival geometry are unchanged.

## Authority and failure behavior

The new command passes through the existing developer rate limit. `DevRespawnBusy` prevents repeated command work; a private per-round in-flight token additionally serializes the shared paid and free re-entry endpoint before its first yield. Thus a simultaneous paid request can be refused and refunded through the unchanged `useReentry` function instead of loading a second character.

Server validation requires the existing participant, active round, dead current Humanoid, authoritative and replicated InRound state, no escape and no exit-transition recovery. The round, whitelist and request identity are checked again after character loading and placement. Failure discards only this request's still-current character. A later replacement avatar is preserved. Paid failure clears only a paid allowance committed by that request; free success or failure preserves a prior paid-use flag.

The independent critic found a concrete gap in the first proposal: the existing load helper could return nil after creating a living Humanoid without an HRP, leaving the new character outside failure cleanup. The corrected helpers accept an optional private load record. They record only a changed character from the serialized engine call **before releasing its gate**, including partial engine failures. Re-entry retains that identity when the readiness wait returns nil; the still-current guard protects a later replacement. Existing callers without the optional record keep their previous behavior. The actual helpers now execute in a partial-body regression, including all four six-second readiness waits; no load timeout or retry policy changes.

Client availability follows actual Humanoid health and the round/exit state. CharacterRemoving retires the old character before the next CharacterAdded, queued old callbacks cannot enable it again, and a late Humanoid is observed. Feedback attributes are display state, not server authorization. The existing DEV menu access/input rules remain intact.

## Offline validation

Run `python artifacts/trello-20260909/dev-free-respawn-prepared/test_respawn.py` from the repository. The corrected result is **184 checks, five targeted negative controls and four full compiles**. `validation.json` records exact hashes and unchanged runtime/authority/Monetization files. The first143-check version did not model a partially created body and was not accepted for installation.

The harness executes the actual new shared re-entry functions, command handler, actual DevAccess whitelist, unchanged Monetization `useReentry`, both actual character-load helpers, and the actual new client availability/lifecycle code. It covers all three developer IDs, unauthorized calls, alive/ended/escaped/exit rejection, repeated free use, free-after-paid without entitlement reset, both concurrent paid/free orderings, load/placement errors and yields, partial living bodies without HRP, round closure, disconnect, replacement/dead bodies, refunds and retirement/late-Humanoid UI behavior. Each negative independently removes a relevant guard and must fail its named assertion. Complete planned inputs are recovered by reversing the edit spans; existing composition payloads remain intact.

Character loading, placement, signals and profile storage are controlled hosts. These results do not establish native placement, actual input/UI rendering, platform purchases or DataStore behavior. No Studio or runtime changes were performed by this preparation.

## Short native acceptance for root

1. Use an actual whitelisted account, normal queue and level readiness. Open the existing DEV panel alive: the row is disabled. Die normally while the round remains active, open the panel, and click RESPAWN. Observe one new real character, normal safe arrival/streaming, restored controls, positive health, one alive-count recovery and one re-entry notification.
2. Compare real profile values before/after without modifying them: tokens, Robux-prompt activity, re-entry credits and `ZyntraReentryUsed` must be unchanged. Repeat after another death. A previously used paid re-entry must remain used. Any paid transaction test should use the existing approved isolated memory fixture rather than spending a real credit solely for QA.
3. Check the actual dead-screen/panel interaction and caption fit on desktop and a narrow/touch layout. A non-whitelisted physical account must have no row and its command must be rejected; a single developer client is not evidence of this native multiplayer case.
4. Confirm the existing safe-placement path in normal L1/L2/L3 when those environments are available. If the round ends during a request or no safe arrival point is available, require refusal without a living uncounted body. Returning to the lobby must disable the action. Do not change the party-down deadline, force an exit-transition respawn, or claim unexecuted native cases as passed.

Independent critic review is **9/10** for the corrected prepared code; see `independent-review.md`. The critic independently reran all184 checks, five negative controls and four compiles. Native acceptance remains pending. Root owns any source composition, Studio installation, native execution and publication.
