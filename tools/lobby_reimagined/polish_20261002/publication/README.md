This separate publication checkpoint preserves the authoritative Studio capture
without changing Studio, Git, or the earlier before/after backups. The previous
229-script capture, strict native audit failure, reviewed extraction of six task
Sources, and publication hold remain historical evidence.

The loopback receiver on port 8910 serves the frozen capture/schema from
`/private/tmp/lobby-polish-publication-inputs-20261002` and accepts only its own
`/private/tmp/lobby-polish-publish-20261002` capture. The capture uses the shared
prefix `__lobbyPolishPublish` and pins the prior after-native SHA. Receiver health
records the exact frozen inputs. It performs no persistent Studio writes.

Run the frozen local verifier after root completes the native capture:

```sh
python3 /private/tmp/lobby-polish-publication-inputs-20261002/tools/lobby_reimagined/polish_20261002/publication/verify-publication-checkpoint.py
```

The verifier reconstructs and reopens the full native place, verifies native
forest equality and all Source/editor receipts, and records reconstruction
limits. Native recoverability is independent of publication permission. The
publication Source guard recomputes every Source digest and requires the prior
229 Sources minus exactly the two class/byte/hash-pinned QA deletions to equal
the new 227 Sources. Any addition, retained change, unexpected removal, conflict,
or missing one of the eleven task/concurrent pins fails publication preflight.
The report includes only hash inventory metadata, never unrelated Source bodies
in the repository. `test_source_guard.py` exercises twelve local fixtures.

`checkpoint-install-gate.json` may prove a recoverable backup while
`publicationPreflightPassed` remains false. Neither flag claims publication or
authorizes publishing. Root must reconcile concurrent deltas and verify the
current live Source/editor/QA state immediately before publishing the existing
experience. No helper removes QA scripts or restores another developer's work.

Root subsequently reviewed and accepted the one exact concurrent Level 4 Test
Suite change. `review-concurrent-test-suite.json` and
`validate_supplemental_review.py` record that separate closed review. The
supplemental validator recomputes every Source/editor row, rejects any other
delta, checks the eleven pins, binds both capture/catalog hashes and the
unchanged failed preflight, and rereads the native forest/place durable copies.
It preserves the original failed preflight and historic strict native audit.
Seventeen negative/positive fixtures exercise the one-delta closure. A passing
supplemental review requires a fresh comparison of all 227 live scripts before
root performs an actual Studio publication.
