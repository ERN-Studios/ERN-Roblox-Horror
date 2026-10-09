# Scoped optimization commit preparation

`python tools/optimization_20261009/commit/prepare_scoped_index.py` prepares a
fresh review pinned to the current HEAD. It does not stage, commit, change the
normal index, change Studio, take backups, or modify working runtime mirrors or
the working global manifest. `GIT_OPTIONAL_LOCKS=0` prevents optional Git index
refreshes. Review artifacts remain in ignored `_local/.../commit-review/`.

The allowlist contains every changed tracked/untracked, nonignored task file
under `tools/optimization_20261009/`, excluding bytecode/cache files; the eight
exact current native source mirrors; and one constructed global manifest blob.
That blob starts from pinned HEAD, updates only the eight owned source fields,
adds the two reviewed effect sources when missing, and adjusts the three
membership counts. HEAD's other source rows, properties and metadata survive.
The current dirty working manifest remains untouched. The current eight-source
provenance is `loading/install/compatibility/spectate-bootstrap/verified-export-eight/manifest.json`;
the earlier seven-source export and its receipts remain historical.

Review `plan.json`, `review-summary.json` and `review.diff`. Every file has exact
before/after size/hash metadata. Large JSON asset/identity ledgers show counts
and hashes instead of expanding hundreds of thousands of geometry records.
Executable scripts, tools and documentation retain their full exact diff.
High confidence credential patterns are checked without printing any values.

Root stages only after review:

```powershell
python tools/optimization_20261009/commit/prepare_scoped_index.py --stage --plan <exact-plan-path>
```

The helper requires exact HEAD, normal index and all file pins, then creates
`reviewed.index` in the review directory. It adds only the explicit literal
pathspec, hashes the scoped global blob and inserts it into this separate index.
It verifies the changed path set, all task evidence raw bytes, all staged file
hashes after CRLF normalization, and all eight native sources. Git's diff check
uses `cr-at-eol` so intentional Windows line endings remain valid. Exact native
capture whitespace is recorded by file/line and recorded native source hash.
No native capture is normalized to hide inherited whitespace.

A failed check leaves a diagnostic receipt and separate index, with no commit.
If every finding is a hash-pinned native source, root may explicitly review a
JSON waiver and use a newly prepared plan with
`--reviewed-whitespace-waiver <file>`. The waiver must contain `headCommit`, a
`reason`, and `approvedFindings` matching every reported `path`, `line`, `kind`,
`rawSha256`, and `pinnedNativeSourceSha256` exactly. New tool code and unproven
captures cannot be waived. Default preparation never grants waivers.

After root reviews a complete `stage-receipt.json`, the separate commit sequence
is:

1. Recheck receipt tree/index hashes, pinned HEAD, normal index pin and reviewed
   file pins. Reprepare/review if any concurrent change invalidated a pin.
2. Create the commit object with `git commit-tree <receipt.treeId> -p
   <receipt.headCommit>`, passing the exact commit message as UTF-8 stdin. This
   creates no branch update. Never silently use a newer parent.
3. Append atomically using `git update-ref HEAD <new-commit>
   <receipt.headCommit>`. If this compare-and-set fails, stop and reprepare.
4. Verify HEAD equals the new commit and the normal index still equals the
   receipt's before pin. Feed the hash-verified
   `normal-index-after-commit.nul` bytes to `git update-index -z --index-info`
   **without** `GIT_INDEX_FILE`. This refreshes only the committed paths,
   preserving every other normal-index entry and working file. Read-only Git
   commands must be used to pin/recheck any index flags on owned paths; restore
   owned assume-unchanged/skip-worktree flags explicitly if they were present.
5. Inspect the remaining normal staged/working diff. The concurrent dirty
   RoundUI, cleanup tooling and unrelated global manifest edits must remain.

The helper implements preparation and separate-index staging only. Root owns
commit object creation, reference CAS, the scoped normal-index refresh, GitHub
push decisions, and Roblox publication.

`test_scoped_index.py` exercises scope, preservation, path guards, credential
patterns, cache filtering, line-ending rules, HEAD/index drift, subprocess index
selection and exact native whitespace waivers with offline mocks. It never
stages or commits the real repository and never accesses Studio.
