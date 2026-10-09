# Completed transport chunks: local-only proposal

Status: **klar til root review; no files removed**. `candidate.json` is the exact
92-path allowlist, recording 60,168,414 duplicate bytes, every chunk hash/size,
its retained fullfile hash and byte offset, and its transfer-receipt hash.
This is a proposed disk reduction, with no runtime performance claim.

The eligible groups are native/facts/references in diagnostic v7 and v8,
native/facts in external-storage-archive-v1, and native/facts in retired-authoring
v3. Concatenation, complete index sequences, sizes, hashes and every fullfile
slice all match. The four external-storage-reopen-v1 roundtrip chunks remain
**afventer test**: historical ownership proofs name their exact hashes, and the
strict native readable-data reopen failed. Its failed recovery result remains
failed; this proposal supplies no native recovery or gameplay certification.

These chunks are capture receiver intermediates. Capture finalization in
`storage_record_archive.py`, `external_storage_archive.py` and
`retired_authoring_archive_receiver.py` reads them to assemble the complete
files. Existing completed capture destinations are immutable and cannot be
restarted by those entrypoints. Completed reference/archive consumers use the
retained complete files, verified through their actual code before and after
removing all chunks from test-owned private copies:

- For v7/v8, real Lune `verify_diagnostic_folder_archive.luau FACTS NATIVE
  NEW_RECEIPT` and Python `verify_diagnostic_folder_references.verify_archive`
  pass. Native Folder reload and serialized reference closure results are exact
  before/partless. Eight separate JSON receipts preserve both lanes' results.
- S04's actual `Archive(..., phase="verify")` constructor and `context()` pass
  with exact native bytes and validated context in both lanes. It reads complete
  native/facts/transfer/final-capture files. No receiver/server was started.
- S06's exact current `main` input-preflight AST statements, from archive/dest
  guards through `native=inputs[...]`, pass with all complete inputs and facts
  equal in both lanes: 23 roots, 14,079 held nodes, 12 held Sources. The verbatim
  extracted function is archived. Context/server/Studio code was excluded.

`candidate.json` pins every actual consumer source hash and the Lune executable
hash. The preparation helper records the executable invocations and performs
both lanes. All five original archive inventories and all consumer sources are
hash-identical before/after. Private fullfile copies are removed in `finally`
after verifying that their absolute temporary root belongs to this review
directory; no private duplicate archive remains.

Every complete `.rbxm`, `facts.json`, gzip, transfer/final/result receipt and
Source/proof record stays. In particular the raw 41 MB external facts remain
available to the prepared v4 wrapper. No authored asset/package, runtime file,
manifest, receipt ID, entitlement or player data is in the removal allowlist.

Risk is limited to losing a completed capture's redundant transfer representation.
Root must freshly guard each pinned directory, fullfile, receipt and current
chunk byte hash before removal and preserve any concurrent change. Rollback
recreates a missing chunk from the verified fullfile at its recorded offset and
length, checks its hash, and writes exclusively. An existing differing chunk
must be preserved. Rerun the same complete-file consumer ports after application;
root owns approval/application, staging, main docs and the final receipt.
