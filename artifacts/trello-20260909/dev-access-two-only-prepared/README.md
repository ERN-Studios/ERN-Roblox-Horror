# Developer access — two named accounts only

Card [036tYqti/#66](https://trello.com/c/036tYqti), directly read by spawn_diagnosis; exact description/checklist/comment provenance is in `manifest.json`. Only **Mikkelczar (40920547)** and **LaverSneglen (9488575949)** may have Developer-tag/dev-cheat access. **Detective_Costeau (833029598)** is the actual extra entry.

The entire proposed production change deletes that one line from `ReplicatedStorage/DevAccess.ModuleScript.lua`. Both functions and all other lines are unchanged. `IsLevel3TimelineOwner` still permits only LaverSneglen; Mikkelczar does not acquire that separate restriction's permission. Usernames are explanatory labels, never the authorization mechanism. Existing paid benefits are untouched.

| Target | Current CAS baseline | Proposed |
|---|---|---|
| `ReplicatedStorage.DevAccess` (ModuleScript) | `49fe522b959179b3e0340e3b433d99fae767689b3b1a070c30a1d465fc5b9fea` | `4c51e000ecf702c0cfb6544d3c2bf46eb9959b3f7941b6b30eec29284e185514` |

`before/`, `proposed/`, `dev-access.diff`, and `manifest.json` provide the exact compare-and-swap handoff. No runtime/Studio/UI/Trello write has occurred. `prepare.py` requires the original exact baseline and writes only this directory; after installation, do not regenerate it over the new checkpoint. `test_access.py` accepts either of these two explicitly known runtime module hashes and checks that it remains unchanged during the test.

## Actual access locations

The current 125-source sync manifest was read in full. **One list** contains these identities: DevAccess. Its real production consumers are:

- GameManager: server DevControl and DevTuning gates, plus the narrower timeline-owner check.
- ZyntraMonetization: server Developer badge and developer token-gift gate. Supporter badges/ownership remain independent.
- Level 2 Objective Controller: server developer pump operation and its continuing authority checks.
- DevCheats and Level 2 Pool Slide Dev ESP: early client access gates.
- ZyntraStore: cached DEV-page availability and separate timeline-owner presentation.
- MasterTuningClient: early access gate; NoiseReporter: cached developer-only movement/cheat behavior.

`whitelist-inventory.json` preserves exact matching source lines and hashes. It also explicitly retains references that are **not extra active whitelists**: L3 Test Suite's negative timeline-owner assertion, UIRegression's shared-authority expectations, a MasterConfiguration explanatory comment, and an archived FiveFixes NoiseReporter backup. None should be edited merely because it mentions an ID or DevAccess.

## Focused verification and future composition

Run `python artifacts/trello-20260909/dev-access-two-only-prepared/test_access.py`.

The tests reuse the existing tag, ESP and free-respawn hosts. The only changed old expectations are the now-superseded three-ID allowed lists (and their corresponding tag warning count); explicit removed-account denials are added. Current installed tag/setup and GM server callbacks are extracted from frozen current-source snapshots. Future ESP/DEV-free callbacks/load/reentry functions are matched to the reviewed Switch→slide→circle→ESP→DEV composition.

- **112 tag/access checks:** both retained IDs; removed/ordinary/spoofed/malformed identities denied; actual tag refresh/respawn/late Head/lobby lifecycle and Supporter independence; actual client early gate and server DevControl/DevTuning rejection.
- **68 existing ESP checks with updated authority:** actual position reply goes only to authorized requester; the removed account gets no reply/rate allocation; old UI/stale-data checks remain.
- **181 existing free-respawn checks with updated authority:** removed account cannot use either command or server-only free endpoint, while ordinary paid reentry stays available; existing cost/concurrency/load-failure/lifecycle checks remain.
- Four negative controls reject the old third whitelist entry and bypassed current-server, ESP, or free-endpoint gates. Eight complete sources/hosts compile. Exact inverse recovers the original module byte for byte.

Most checks above are pre-existing regression assertions, not a new test framework. They are deterministic offline hosts, not native identities, purchases or multiplayer testing.

**No future proposal is overwritten.** The five prepared GM composition-stage hashes are unchanged and recorded in the manifest. Those files and future Store/DevCheats still require shared DevAccess; they contain no copied third-ID authority. This module-only change therefore applies independently of their source deltas. Their old test scripts deliberately remain historical and still contain the former three-allowed-ID expectation: after this card, use this separate updated-authority context instead of silently rewriting their old baseline/report or treating that obsolete assertion as a production failure. New consumer source changes require fresh matching/readback, not automatic acceptance from these frozen snapshots.

## Small native/publish checkpoint for root

Apply only the reviewed ModuleScript against its actual baseline using the normal source workflow, then compile/read back/audit. **Start a fresh Play/server and fresh clients.** Roblox module caches and the existing client `devAllowed`/early-return closures retain prior initialization; changing Source during a running session does not revoke already initialized tools. This one-line patch does not add dynamic revocation.

On a real retained account, verify the normal lobby Developer badge and an existing harmless dev control still work; on an available ordinary real client, verify no Developer badge/DEV controls. If the removed account is available, test its fresh login directly. Otherwise report that its denial is covered by actual-source offline tests only; do not spoof a live UserId or claim a native removed-account login. A bought Supporter badge must remain independent. Existing in-round/lobby tag behavior is unchanged.

Only fresh servers running the published version get the new authority list. Already running published servers are not retroactively certified or revoked by this artifact. Root owns the final native evidence and mouse publication; no publication or completed Trello status is claimed here.
