# Completed local transport-file cleanup

Status: **completed by root, independently verified**. Root's v2 removed exactly
92 completed capture chunks, totaling **60,168,414 disk bytes**. Native calls,
native writes, canonical Source writes and manifest writes were zero. All full
archives, facts, gzip files, transfer/result receipts and Source proofs remain.
This records disk-file reduction; it is no gameplay or performance measurement.

The original reviewed candidate is pinned at
`fbe29bc1276790f25cec4b1cc6952e72627c7f185c750634ba780ae11875d212`.
The executed v2 tool is
`17618f16d82d29346072df635bdbdc690ffad4aee81d68069bb01e23e25dbb48`.
`removal-receipt.json` has SHA256
`60e100e3688c7740a71c10067363b0c873d42bcb30ae82bcb1411e27541c2b73`;
the actual post-removal consumer's `candidate.json` has SHA256
`ca4886f0cde2fe691b71c5372192591706fc0e0fdb5ac7f3d635da0c6f5b267f`.

The copied consumer is byte-identical before and after, SHA256
`3044bce8c8496d47c21ac03425cc7f0d81780dad0d2150250d90173a05d6cfe6`.
Root executed it after removing the actual files. Its four result rows exactly
match the initial paired tests:

- Diagnostic v7 and v8: real Lune Folder reload and Python serialized-reference
  verification, each with 12 roots and 105 serialized references. Before and
  partless results are exact; separate result JSON files preserve both lanes.
- Retired-authoring v3: the actual receiver's `Archive(..., phase="verify")`
  constructor and validated context, with exact complete native bytes. This is
  an offline completed-archive port; no native reconstruction was rerun here.
- External-storage v1: the actual reopen wrapper's verbatim input-preflight AST
  statements, through `native=inputs`, with complete inputs and facts equal:
  23 roots, 14,079 held nodes and 12 held Sources. Context/server/Studio creation
  is excluded. The historical strict native readable-data reopen remains failed.

Post-removal stdout reports zero eligible remaining files/bytes and cleaned
owned temporary copies. Stderr is empty. `final-review.json` independently
verifies the exact 138-before to 46-after file inventory, every protected file
hash, every pinned helper, all 92 missing paths and all 92 reconstructible slices.
The four excluded `external-storage-reopen-v1/roundtrip-part-*.bin` files are
still byte-exact. Raw external `facts.json` remains available to its consumers.

The first root attempt failed before any consumer port: the parent had created
`.gitattributes`, and the copied consumer's exclusive write rejected that file.
The tool restored all 92 chunks without overwriting concurrent files. The failed
receipt/logs and exact executed v1 source, SHA256
`54d4961f3117f8ebb7136259edfa269b1017895b836afc80f373ffd9679ecfda`,
remain in `transport-parts-after-v1`. Its repair review established all 92 bytes
and the full 138-file inventory were restored before the second attempt.
The repair changed only the new evidence paths and moved conditional
`.gitattributes` creation into `finally`; all assertion ASTs and ports remained
unchanged. That historical verifier describes the restored moment and should
not be rerun expecting the retired chunks to remain present.

The independent final-review helper initially compared the two saved inventory
JSON files byte-for-byte. Set iteration had changed JSON key order between
processes. `final-review-attempt-v1.json` preserves that verifier failure; the
corrected check compares all 138 path/hash pairs and records both raw JSON
hashes. Every archive file itself is still checked by its exact saved byte hash.
No retirement or consumer was executed by either independent review helper.

## Exact reconstruction procedure

The original candidate records each chunk's path, full-file path, byte offset,
length and SHA256, and its group's complete-file and transfer-receipt SHA256.
The actual removal receipt preserves the same ordered 92 entries. No authored
asset or native original needs reconstruction for this local batch.

For any requested chunk recovery, first resolve the recorded paths beneath the
exact MongoTV artifact directory and the recorded whitelisted group directory;
reject symlinks, traversal, name mismatch and a changed complete-file or receipt
hash. Re-read the verified complete file, slice
`full[offset:offset + bytes]`, and verify the slice length and saved chunk SHA256.
Freshly repeat the full-file/receipt guards before each write. Open the recorded
missing chunk path exclusively with Python `Path.open("xb")`, require a complete
write, then re-read and verify its saved length and hash. If the path exists,
preserve it; report whether it matches and never overwrite a differing actor's
file. The guarded rollback in the executed tool uses this exclusive-write
method. Any rehearsal must write only under a new owned temporary directory,
then remove only those owned outputs. This review performed no actual restore.

Only the three transport proof directories, the scoped retirement tool and its
tool-specific attribute line belong to this batch's commit allowlist. The
allowlist excludes transfer chunks, complete raw archives/facts, private
checkpoints, temporary outputs, runtime mirrors and main cleanup documents.
