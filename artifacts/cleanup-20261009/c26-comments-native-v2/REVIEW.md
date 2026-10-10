# C26: current QA coverage comments only

Status: gennemført i Studio og det verificerede lokale mirror; Root's commit
remains pending. Root executed the reviewed bounded CAS, native export and
installed verification successfully at 2026-10-10 00:33:56–00:34:24 UTC. The
preparation and evidence curation make no native or game-file writes.

The sole proposed target is `ReplicatedStorage/UIRegression.ModuleScript.lua`,
native `ReplicatedStorage.UIRegression`, a ModuleScript. The exact before Source
and its recorded manifest Source were 320,730 bytes, SHA256
`b57a2b848f7981d76225c5bb850cdcfb3de12743afadab674ee826d4747ccc64`.
The corrected candidate is 313,535 bytes, SHA256
`605da83a331022949004dab143012b408b899500f9e6c84188b8d71a31771aca`:
7,195 fewer bytes of stale comments. No performance gain is claimed.

Ten exact nonempty comment replacements are recorded in [proof.json](proof.json).
They update the analytical text-helper description, old BriefingFit/Exclusion
coverage blocks, ObjectiveCorner/anchor-margin comments, DispatchCompact's old
footprint claim and RunAll's shared-lane explanation. Every changed line is blank
or a `--` comment. Forward and reverse exact-anchor transforms reproduce the
saved Source hashes, and reject missing/duplicate anchors and wrong hashes.
The function fragment has no API calls and is not an installation command.

The historical candidate `e2fe9828...` remains byte-identical in
`../client-local-proofs/`. Its ObjectiveCorner comment claimed Level 1 and Level 3;
the current `Fit.bodyRoundHudMatrix` actually loops `{1, 2, 3, 4}`. This v2 candidate
corrects that additional comment to “Levels 1 through 4”. The v1 preparation and
its exact executed preparer are preserved under `../c26-comments-native-v1/`;
their PASS describes executable equivalence, not approval of the stale wording.
The new candidate is derived into an automatically cleaned owned temporary file,
so no new full Source duplicate is added to the proof package.

The four public compatibility lanes `BriefingFitMatrix`, `BriefingExclusionMatrix`,
`ObjectiveCornerMatrix` and `DispatchCompactMatrix` still call the same private
shared matrix through their existing `Fit.lane` wrappers. They keep their public
names, tokens, lock ownership and borrow/restore behavior. RunAll keeps one shared
matrix invocation. `Fit.DispatchReference` and the retained analytical helper stay
present. Shared objectives, admission-controlled feed/captions, device fixtures,
workspace/player attributes, all active remotes and renderer callbacks remain.
Manual/public QA callers and historical vault coverage notes are not removed or
promoted into evidence of current coverage.

Actual Luau 0.737 O0/O1 compilation compares all 197 functions, every instruction,
constant, upvalue, type payload, child/reference and function structure. Raw
binaries differ because 58 function definition lines move. The existing explicit
bytecode parser zeroes only `Proto.linedefined` varints and resizes their enclosing
proto-size varints; every other byte is retained. Canonical binaries and complete
instruction/constant dumps are identical:

| Optimization | Canonical SHA256 |
| --- | --- |
| O0 | `cd0fd2374c155a203f72b7a7f70d21c095e7b0c06cd804e9f3d10625f90302fa` |
| O1 | `d04059ceec2802fb84120f2889a49ed62737b879d9ce26c0aa64930f5d643177` |

The actual current `tools/tests/test_ui_regression_shared.py` passes 105 assertions
before and after. Only that test's `REGRESSION` source input is substituted;
current RoundHud/ShopBinder/UIStyle/Detector modules, imported PC/touch trees and
harness are retained. The real extracted borrow/restore/residue, injected error
cleanup, reentry and TouchTarget consumer bodies execute against synthetic engine
boundaries. Dependencies and before/after output hashes are recorded in the proof.
These are no new native font/full-UI/gameplay/multiplayer/streaming/performance
certificates. For this pure comment edit, executable equivalence and the actual
authoring contracts establish the local test port.

Reproduce the installed verification, using a new immutable destination:

```powershell
python -B tools/cleanup_20261009/prepare_c26_comments.py --verify-installed --dest artifacts/cleanup-20261009/c26-comments-recheck-v3
```

The installed mode requires the current canonical Source and manifest to equal
the corrected candidate while reusing the immutable before inputs and current
actual authoring fixtures. It never edits game Source or manifest. Root must
separately preserve all other Source rows and concurrent work and review console
changes at the native boundary. The stale all-client/Loading generator is not
invoked: active `announced()` and dirty RoundUI are preserved. Runtime-local
C04/C06/C07 candidates remain separate and pending their necessary ports.

The offline preparation makes no Studio calls. Root subsequently authorized one
strict S13 native metadata/hash getter; its exact code and receipt are under
`native-baseline-v1/`. It confirmed Edit, the intended place/universe, ModuleScript
identity `1_42698`, parent `1_408323`, exact raw/canonical Source/editor SHA `b57a...`,
320,730 bytes, Archivable=True, LinkedSource="", empty attributes and tags. It
returned no Source bodies and performed no writes, objects or mode changes. This
is a point-in-time read; the executed installation rechecked the full current
closure independently.

## Scoped Root-only installer

`tools/cleanup_20261009/apply_c26_comments_cleanup.py` and
`c26_comments_source_cas.luau` fork the bounded S14 installer/template. The delta
changes only the target/path/IDs, ten comment anchors, proof inputs and installed
offline compiler/UI replay instead of runtime ModuleScript staging. The native
callback transforms its current authoritative Source through exact unique comment
anchors and a final candidate SHA. It does not return a repository Source body.
Reverse order and swapped anchors reconstruct the exact before SHA for rollback.

The retained native closure guards all 212 current Source/editor identities,
parents, classes, properties, attributes and tags; 20-row catalog pages are capped
at 20,000 response bytes. Actual established Source reads use isolated 64-line
chunks capped at 8,000 response bytes and require exact SHA/length. The full
original guard/census repeats after the final yielding chunk and inside the
Source callback. Static aligned Source chunk maxima are 4,409 bytes for both
versions (103 before chunks, 101 candidate chunks); these are not measured wire
sizes. Fresh native export alone updates the mirror and its two manifest Source
fields. Installed replay then requires that verified current Source/candidate and
manifest, reruns 197-proto O0/O1 equivalence and both actual UI105 ports, followed
by a distinct final native 212-row observation and console comparison.

Commit-then-error observes the native outcome before reversing only the exact
owned candidate. Foreign/unknown Source or manifest fields are preserved;
rollback restores only own Source bytes/sha/bytes, retaining other actors' metadata.
Exclusive checkpoints/receipts and immediate file CAS before atomic replace are
retained. They are point-time guards, not an OS compare-exchange or continuous
scene ownership certificate. No original object/property/mode writes are requested.

Sixteen actual filesystem/wrapper cases pass 109 assertions with fake MCP/native,
console, git and offline-replay boundaries. They include prewrite mode/parse/size/
page/catalog/chunk rejection, commit-then-error, unknown/foreign native outcome,
failed replay/console, and actor Source/manifest-row preservation. The actual
extracted native transform separately passes five cases/eight assertions for both
exact directions, missing/duplicate anchors and wrong SHA, plus O0/O1 compilation.
Twelve generated native operations compile O0/O1. The initial test extractor
mistakenly searched the old S14 table-literal marker; it failed after the wrapper
cases and before the transform gate. Its exact source/failure receipt are retained;
the corrected final receipt executes the real C26 request-patches transform.

Root executed this reviewed command after independent peer review:

```powershell
python -B tools/cleanup_20261009/apply_c26_comments_cleanup.py --apply
```

The four new tool filenames have explicit `-text` rules after Root released S14's
shared attributes file. The preparation, fake-boundary tests and curation perform
no source install, Source rollback, staging, commit, publication or push.

## Executed result and bounded public evidence

The Root-owned [result](c26-comments-source-install-v1/result.json) records one
authoritative Source write, from `b57a...` to `605da...`, and 7,195 removed comment
bytes. It records zero other original Source, original Parent/property, object or
mode writes. No rollback was needed. The verified current export alone supplied
the canonical mirror and the target manifest's `sha256` and `bytes` fields.
Other 211 Source rows and all unrelated working-manifest rows were preserved.

The actual [installed contract](c26-comments-source-install-v1/installed-contract/proof.json)
passes the same 197-function O0/O1 executable comparison and actual current
UI105 authoring/error/restore/reentry ports before and after. Its process receipt
has exit code zero and pins that proof by hash. No runtime ModuleScript probe is
created for this pure comment batch. Existing console text is byte-identical
before and after, including the pre-existing sound rejection and older Assistant
diagnostic errors; those messages are retained rather than relabeled as clean.

Public native-before, native-after and native-final JSON contain only hashes and
metadata. The final receipt is reconstructed from the executed third 11-page
catalog with exact catalog/target equality; all 212 row identities are unique.
Only UIRegression's Source hash and byte count differ. All recorded identities,
classes, parents, properties, attributes and tags are identical; after and final
rows are byte-equivalent. The exact actual CAS and final original-check code are
also included. The [bounded proof](c26-comments-source-install-v1/bounded-transport-and-parity-proof.json)
distinguishes enforced 20,000/8,000-byte response caps from static 64-line Source
chunks: 103 before and 101 candidate chunks, each at most 4,409 bytes. The saved
pretty JSON page maximum is not a measured native wire size.

`curate-installed-proof.py` derives those records from Root's immutable private
checkpoint, guards canonical/tool bytes, and writes only exclusive public
evidence paths. Full Source/editor bodies, raw metadata page checkpoints and
the private working/HEAD manifests remain excluded. Already committed portable
before/historical-candidate inputs are referenced, not copied again. Original
v1/v2 receipts and the first failed offline extractor remain unchanged.

This certificate covers the recorded Source/editor/metadata boundary and the
comment-only authoring port. It creates no new native font/UI, gameplay, asset,
multiplayer, streaming or performance certificate. No public publication or push
was requested or performed.
