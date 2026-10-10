# Generic installer V5 — candidate only

The production installer remains unchanged. This isolated project layout uses
the intended production `ROOT = Path(__file__).resolve().parents[1]` and tool
import path, with byte-identical copies of the current S13 helpers. There are
no Studio, native Source, production mirror, real manifest, index or commit
writes by this work. S19 should record **pending**, not implemented.

The underlying narrow defects remain the earlier observed generic installer
metadata loss and absent overwrite CAS. V5 keeps the source-authoritative
design from candidate V2, refreshes native metadata instead of blindly keeping
stale target fields, and fixes concrete races exposed while expanding its
tests. T06's old Unicode escaping gate already passes in production; this is
regression coverage, not a claim to fix that problem again. S17 separately
resolved the historical remote metadata gap; it is not an open V5 change.

## Concrete candidate scope

- Existing overwrite: fresh S13 Source/editor, identity, class, parent/path,
  properties, attributes, tags and native mode/place baseline, captured again
  in the actual UpdateSourceAsync callback; foreign drift refuses the write.
- Same Source: no native mutation; register newly read native metadata. Keep
  unknown target fields, unrelated queued rows and owner top-level metadata;
  remove a stale target trailing-newline flag only after exact readback.
- Missing target: fresh `Instance.new`, exact empty Source/editor, no overwrite
  fallback; guard parent identity/path and slot before parenting and again in
  the callback. Temporarily disable a fresh BaseScript, then restore only its
  own initial Enabled value after verified landing. Runtime objects and
  authoritative originals are never cleanup candidates.
- Failed creation: delete only the precisely owned current object with its
  known empty or candidate Source/editor and matching fields. Preserve foreign
  moves/detach, Source/editor or metadata changes and unknown getter outcomes.
  Include the primary error if owned cleanup itself fails.
- Presence response: strict shape, boolean missing flag, nonempty parent ID,
  JSON decoding and 20k response bound; malformed responses stop before write.
- Source reads: the actual reader runs in an isolated 64-line namespace with
  an 8k per-chunk bound, bracketed by actual S13 metadata and Edit checks. It
  does not change production helper globals.
- Registration: immediate original-byte manifest CAS, exclusive temporary
  creation and atomic replacement plus postread. Temp cleanup requires the
  file identity obtained from the successfully opened descriptor, a complete
  known body and matching current identity/body. Foreign open-race files,
  edits/replacements and unknown partial writes are preserved. This is not a
  cross-process lock or an atomic native-plus-local transaction.

## Executed local ports

`ports-v1.json` reports the current pinned candidate with:

- Unchanged production `tools/tests/test_install_new_scripts.py`: **20 checks**,
  actual offline Luau, both ASCII and Unicode/quote/emoji paths and all three
  old Unicode/control Source inputs preserved.
- **14** previous actual-main cases and **29** added cases; **312** current
  Python checks plus the previous fixture's **86** checks. Cases include same
  Source, no-overwrite, overwrite, wrong class, editor/read/callback conflicts,
  queued targets, Unicode mirrors, malformed presence, missing/changing parent,
  create races/errors, final metadata/property/editor/Source drift, bounded
  chunk errors, duplicate target rows and foreign existing temp preservation.
- **711** actual generated Luau guard/create cases, **2,241 checks**, **14**
  O0/O1 compile units. The native service/JSON/hash/scheduler boundaries are
  explicit fakes. Three creation classes, all original small Unicode inputs,
  and parent-path races, detach, foreign Source/editor/property edits,
  pre/post-parent errors, cleanup/getter errors and commit-then-error execute
  the candidate's generated callbacks; this is not a Studio engine pass.
- Measured large actual-main fixture: **91,702 UTF-8 bytes**, **52 chunks** for
  same Source and **27 chunks** for small-old-to-large overwrite, maximum
  source response **3,711 bytes**. Same Source makes **0 writes**; overwrite
  makes **1**. The largest overwrite request is **99,637 bytes**.

`atomic-ports-v2.json` separately reports **15 actual-main cases / 91 checks**
with real local open/write/stat/replace/postread/cleanup operations. It covers
foreign temp creation after the first exists check, foreign contents, a
same-byte replacement with a different real file identity, pre/postreplace
errors, concurrent manifest edits before and after registration, immediate
guard read errors, partial/incomplete/close write errors, cleanup unlink/getter
errors, preserved queued rows, truthful failures and no blind Source restore.
Unknown incomplete temp writes deliberately remain for review; a successful
local replace followed by an error leaves the landed or foreign current
manifest intact. These faults are not credited as transport or native tests.

## Preserved failures and small changes

All earlier files and receipts remain immutable:

| Evidence | Classification / resolution |
| --- | --- |
| V3 `failure-v1.json` | Driver selected a nonexistent `RoundUIController` filename; corrected to actual `RoundUI` in a new driver. No candidate/native execution before that error. |
| V3 `failure-v2.json` | Driver omitted LUAU_BIN for the unchanged old gate; new driver passes the existing interpreter explicitly. |
| V3 `failure-v3.json` | Driver's UTF-8 capture encountered Windows stderr encoding; new driver preserves failure bytes with replacement decoding. This receipt has null stderr and is not proof of a candidate defect. |
| V3 `failure-v4.json` | **Candidate defect**: actual generated Parent setter commits then throws before `attached=true`; precise owned allocation leaked. V4 removes the attached-flag requirement only for the still-exact parent/path/slot. Foreign detach remains preserved. |
| V4 `failure-v1.json` | Driver tried to mirror a filename containing quotes, invalid on Windows. New actual-main Unicode path omits quotes; generated native quote-path gates remain intact. |
| V4 `failure-v2.json` | Driver incorrectly expected two large reads in overwrite; its first read is the small old Source. Correct expected multi-chunk landing still checks the exact response bound. |
| V4 `atomic-failure-v1.json` | **Candidate defect**: finally deleted a temp created by another process between exists and exclusive open. V5 adds descriptor identity and known-body cleanup; actual foreign edit and same-byte identity-replacement ports also pass. |

V4/V5 passed receipts do not retroactively turn earlier failures into passes.

## Pending gates and limits

[NATIVE_AUTHORING_PLAN.md](NATIVE_AUTHORING_PLAN.md) defines the small Root-owned
fresh-ModuleScript port, all-original guards inside callback and after both
outcomes, scoped adoption/cleanup, nonce lease, concrete cases and acceptance.
Its wrapper and validator still need implementation and independent review.
No native execution is authorized by this candidate receipt itself.

Real SES/editor identity, manual authoring integration, all three native
creation classes, native editor-draft conflict and large native write transfer
are **pending**. The single-literal write request remains large; only read
responses are bounded. No FPS, memory, CPU or gameplay gain is claimed.

Manifest byte checks and temp identity/body checks have ordinary OS check/use
windows; they are not a shared lock. A native Source landing followed by a
final metadata/manifest conflict can leave fresh native Source and an old
manifest. The tool reports failure and preserves current owned/foreign state
for fresh Studio-to-repo reconciliation. It does not blindly restore old
Source or overwrite another writer's manifest to manufacture success.

Only curate/promote this candidate after the precise Root authoring gate and
remaining material constraints are resolved. Re-run with fresh baselines if
production helpers or native Studio state change.

To rerun local-only ports, use new receipt paths:

```powershell
python -B artifacts/cleanup-20261010/foundation-next-v1/installer-v5/test_candidate_v3.py --receipt <new-expanded-receipt.json>
python -B artifacts/cleanup-20261010/foundation-next-v1/installer-v5/test_atomic_faults_v2.py --receipt <new-atomic-receipt.json>
```
