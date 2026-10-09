# Independent prepared-code review — 9/10

Reviewed on 10 September 2026. **No remaining code blocker found in this bounded proposal.** This is an artifact/code score; it does not certify installation, native character loading, input, or publication.

Reviewed outputs:

| File | SHA-256 |
| --- | --- |
| GameManager | `eba65308b340914e973877561d9812b7c7f4718f9194b40131438002709fe762` |
| DevCheats | `efd034810f01f8516130f94eebf61070d4a0fff7b81f3c43e64732cf884aa3b9` |
| ZyntraStore | `596ff4f45406e753824778ab7cf10b6b8109ba83309332bacb88b57fea444093` |

I read all three deltas, the actual re-entry/load helpers, the host and its extraction/negative controls, and independently reran `test_respawn.py`: **184 checks, five named negative controls and four whole-file compiles passed**. The runner also verified unchanged runtime, DevAccess and Monetization hashes and reversal to the complete planned inputs.

The server enforces the existing whitelist twice, accepts only a dead current participant in the active round, and rechecks lifecycle and ownership after yielding. Paid and free calls share a private in-flight lock. The free path bypasses the existing credit transaction and preserves both the stored paid allowance and the once-used flag. The unchanged paid mutator/refund path is exercised against the actual shared handler, including both concurrent orderings. The keyless DEV row follows current-character health and retirement; its display attributes do not authorize a respawn.

## Concrete finding resolved

The first 143-check version could leave a living, uncounted partial Character when the actual helper exhausted its readiness waits without an HRP. It was not approved. The final version passes a private optional load record through the existing helpers, records the changed Character immediately after the serialized engine load and before releasing its gate, and retains that record when the readiness helper returns nil. Failure kills only a recorded body that is still the player's current Character.

The added actual-helper cases cover four six-second timeouts, an engine error after partial creation, paid and free cleanup/refund behavior, a later replacement that survives, and the pre-gate-release record write. The specific negative that removes the record fails at the expected partial-body cleanup assertion. Existing callers without a record retain their behavior and retry timing.

## Installation and native boundary

These complete files use **planned** Continue/slide/circle/ESP/copy inputs, not the current runtime. Preserve the manifest prerequisites or compose the exact hunks into the later checkpoint. In particular, the concurrently prepared square Shop/Upgrades opener must survive any later Store merge.

Root's focused native acceptance remains necessary: actual DEV access over the death screen, a real respawn through normal safe placement/streaming with restored controls and one alive-count recovery, a second use after another death, unchanged tokens/credits/paid-use state, and normal round/lobby rejection and cleanup. Existing offline cases cover unauthorized access, paid/free races and synthetic load failure; they are not claims of physical multiplayer, live DataStore, or every level's native placement. The existing 15-second party-down window is preserved and is not extended by this feature.
