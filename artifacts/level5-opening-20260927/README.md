# Level 5 preview opening evidence — 2026-09-27

Current result: **published v2157 closes Level 5 lobby access for everyone at the owner's latest request**. A fresh native lobby build confirms both access flags false, a colliding door, zero active stations and four offline stations. Already-running server restarts remain unverified. The earlier opening was published as v2153, all seven puzzles were tested with real wrong/correct inputs in desktop Studio, H endpoint was reached and the existing lobby return was verified. Those tests precede the requested closure. See [the final QA record](../../docs/LEVEL5_OPENING_QA_2026-09-27.md) for publication evidence, scope and remaining limits.

## Contents

- `post-install/`: all-197 fingerprint comparison plus full SHA-256 records for the six changed Source/editor exports. The six actual sources are mirrored at their normal repository paths.
- `post-reopen-concurrent/`: full Source/editor export and SHA-256 receipt for another developer's newly observed `Level6Renovation`. The fresh reopen audit in `qa/` found 198 scripts: all prior 197 unchanged plus this one addition. It was preserved separately, without runtime mirror writes.
- `cas-payloads/`: the six scoped apply scripts, six verify scripts, generator, mock tests, fingerprints and validation. Root applied all six successfully; the subsequent independent export proves the installed result. This directory's original preparation README predates installation and its “not executed” statement is historical.
- `access-drafts/`, `outage-drafts/`, `clue-drafts/`, `lobby-drafts/`: reviewed patches, manifests, test generators/helpers and results. Original draft-only labels describe preparation time. Their sources were subsequently installed and independently exported.
- `puzzle-review/`: source review, existing pure puzzle/layout tests, readonly Studio inspection scripts and results. The diagnosis and baseline checks preceded installation; use the final QA record for native outcomes.
- `qa/native-session2-receipts.json`: actual current-session A–G input feedback and gate results, F/G/H route receipts, H descent, and lobby cleanup. Some route segments used the existing authored rescue path or native keyboard movement when tool navigation stopped short. `qa/native-session-notes.md` is the earlier, partial pre-install test.
- `qa/publish-v2153.txt`: local Studio success log excerpt confirming the new publication and version.
- `closure/`, `qa/closure-publication.txt` and `qa/closure-final-publication.txt`: the owner's later access closure, its scoped script/native changes, the v2156 interim publication, and final v2157 publication after correcting the fresh-build station registration override.
- `qa/scoped-install-receipts.json`: the six actual `APPLIED_VERIFIED` responses. `qa/native-lobby-after-reopen.json` is metadata only because its instance values were collapsed by the connector. The complete scoped final native properties are in `closure/native-lobby-final-properties.json` (219 instances); use that record for the final closed lobby state.
- `recovery/`: full **prechange v2150** native checkpoint and its source/hierarchy audit. This is not the final v2153 native state.
- `final-native-audit/`: read-only parser, latest 198-script expected index, the original 197-script post-install expectation, and the historical freshness rejection for the old autosave. A final native backup has not been obtained.
- `package-copy-validation.json`: source locations, sizes and SHA-256 hashes of copied artifacts. No signed media URLs or credentials were found by the text pattern scan. Native lock files, caches, Python environments and duplicate full source exports were excluded.

## Source and native safety

The CAS scripts check the exact cloud place/universe, Edit mode, instance path/class, source/editor agreement and original source fingerprints. They replace only unique exact fragments, recheck inside `UpdateSourceAsync`, then verify the new source/editor result. They do not add scripts, publish, or push a runtime tree. They are historical installation records, not instructions to replay against a newer Studio state.

The preserved recovery file is 17,362,339 bytes with SHA-256 `13710246d8b2f634631418080f7cfe3eda6110791e88517bda7a5219910acc92`. Its audit matches all 197 prechange sources and validates the decoded hierarchy. It contains the six **old** source versions and the prechange native geometry. Never overwrite newer Studio work with this checkpoint to obtain a matching audit.

The final native save picker blocked completion; a browser fallback was unavailable. Publication and the six script exports were verified separately. They do not constitute a final full native backup. The native audit parser checks source hashes and hierarchy; it does not validate every native property, rendered appearance, gameplay or publication.

## Re-running tests

The preparation records are preserved byte-for-byte. Use the package replay script from the repository root so their original paths do not need to exist:

```sh
python3 artifacts/level5-opening-20260927/replay_checks.py --report /tmp/level5-opening-replay.json
```

Pass `--luau-dir /absolute/path/to/luau-binaries` if the sibling project Luau directory is unavailable. This replays the **historical opening state**, followed by the current closed-access checks. The closure record's exact fragments first reconstruct the verified open versions for the historical tests. It then reconstructs the six old baseline sources, verifies the SHA-256 hashes, and runs the unchanged original test generators in a temporary directory. It also uses the existing repository's outage mock helper and unchanged puzzle dependencies. It does not change Studio or the repository source files. The packaged run passed all 25 compile/test commands, including 120 current closure assertions; see `replay-validation.json`. Current closure tests and native receipts are in `closure/`. Generated whole-source harnesses are removed with the temporary directory. Rebase to a fresh Studio export before validating future changes.

`final-native-audit/audit_final_native.py` is relocatable with its adjacent expected index, which now includes all 198 scripts observed after reopening. It requires Python packages `numpy`, `lz4` and `zstandard`, already present in the local audio task environment. Run from the `final-native-audit` directory:

```sh
python audit_final_native.py /absolute/path/to/new-native-save.rbxl --report /absolute/path/to/audit.json
```

If Studio changes after the recorded export, first preserve and reconcile those changes and update the expected index. A mismatch is evidence to investigate, not permission to overwrite Studio.

Audio is recorded separately under `artifacts/level5-final-audio-20260927`. No new sounds or playback hooks were installed in Roblox.
