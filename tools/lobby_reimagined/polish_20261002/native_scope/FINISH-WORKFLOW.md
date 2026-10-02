Only the root agent executes Studio capture, Git mutations, and publishing. These local helpers never contact Studio or write the Git index. The last observed published version is 2495; local capture/export/commit is not publication. No Git remote is configured, so there is no current remote history to fetch or push.

Finish the EndBlockades correction, verify its exact fresh Source/editor CAS receipt, and update `artifacts/lobby-polish-20261002/root/final-frozen-source-hashes.json` with the final six installed hashes. Keep the first-install catalog and frozen receipt immutable. The final Bays hash is `1ab19711a303b058d033de6652da3d94c15e73f7e40b4e983036fa99c805bc2c`; EndBlockades may still change. Recheck every candidate file against final pins before starting the final capture.

The frozen receiver on 8906 serves `/capture` SHA256 `cf24f54f8d69da23513438955f155fc72683da03c4650c3a4877daf83bc14b44`, `/schema` SHA256 `f9b340d8ceb219d64226320a1a7b9af2f00e2fb2bd81b3355c100423bf82ac08`, session prefix `__lobbyPolishAfter`, and expected before-native SHA256 `451e86549091122a992da3a8cabee5f38471dd20d5b77212dc6d77dad1433872`. It writes only `/private/tmp/lobby-polish-after-20261002`. Its `/health` also records unused installer inputs from its original startup; those unused rows are not the current 8905 installer version.

Root stops only its own Play session, confirms Edit state and the authoritative place/universe/group, then executes the read-only `/capture` bytes and waits for `shared.__lobbyPolishAfterBackupStatus` to complete. Source/editor conflicts or capture errors are blockers. The after receiver refuses differing files from another capture; preserve an incomplete capture separately rather than deleting somebody else's data. Do not mix parts from separate capture IDs.

Run these local steps from the repository root after the complete capture:

```sh
python3 artifacts/lobby-polish-20261002/verify-after-checkpoint.py

/private/tmp/level6-lune-20261001/lune run \
  tools/lobby_reimagined/polish_20261002/native_scope/verify_native_scope.luau \
  /private/tmp/lobby-polish-before-20261002 \
  /private/tmp/lobby-polish-after-20261002 \
  artifacts/lobby-polish-20261002/root/final-frozen-source-hashes.json \
  artifacts/lobby-polish-20261002/root/baseline-critical.json \
  artifacts/lobby-polish-20261002/materials/candidate-manifest.json \
  artifacts/lobby-polish-20261002/materials/uploaded-assets.json \
  /private/tmp/lobby-polish-after-20261002/native-scope-verification.json

python3 tools/lobby_reimagined/polish_20261002/native_scope/finish_export.py \
  --capture /private/tmp/lobby-polish-after-20261002 \
  --frozen artifacts/lobby-polish-20261002/root/final-frozen-source-hashes.json \
  --native-report /private/tmp/lobby-polish-after-20261002/native-scope-verification.json \
  --destination artifacts/lobby-polish-20261002/fresh-source-after
```

The checkpoint verifier reconstructs, reopens and compares the full native place. It retains metadata, complete Source catalogs and exact transfer hashes, even when unchanged native forest bytes can be reused. The scoped comparator then permits only three pinned existing Source/hash-attribute changes and three exact new owned modules. It verifies the static image URIs/PNG contract and original ServerLobby fingerprint. It reports unrelated concurrent deltas separately and returns false instead of restoring them. Stop and review these differences; do not turn false parity into a pass by expanding normalization.

The last command is read-only by default. Add `--write` only after it passes to export six exact Studio Source/editor mirrors, the complete source hash inventory, native proof summaries and the native scope report. It rechecks audit/capture identity, full native hash, recovery file hashes, final candidate bytes, and existing export bytes before any output. Exact source mirror filenames are:

- `ServerScriptService.LobbyReimaginedPreview.Builder.ModuleScript.luau`
- `ServerScriptService.LobbyReimaginedPreview.EndBlockades.ModuleScript.luau`
- `ServerScriptService.LobbyReimaginedPreview.MaterialPolish.ModuleScript.luau`
- `ServerScriptService.LobbyReimaginedPreview.LobbyPolishBays.ModuleScript.luau`
- `ServerScriptService.LobbyReimaginedPreview.LobbyPolishScene.ModuleScript.luau`
- `StarterPlayer.StarterPlayerScripts.LobbyReimaginedQueueController.LocalScript.luau`

If the strict audit is false solely for already reviewed concurrent work, task-only source extraction has a separate explicit path. It requires `taskScopeVerified=true`, an explicitly empty own-error list, unchanged original ServerLobby, exact native recovery, and a closed review bound to the raw audit hash, before/after capture/native/catalog hashes, every exact unrelated Source before/after/class/byte row and every typed native-delta digest. The review approves only extracting the six task Sources; it leaves strict native parity false and explicitly withholds cleanup/publication. It never expands native normalization or removes another developer's objects.

For capture `4df9e7f4-49ec-434d-abbf-d2607efa9c2a`, seven Source deltas and six native rows are recorded in `materials/concurrent-export-review.json`; user/other-developer ownership response and temporary QA cleanup remain pending. The task-only path is:

```sh
python3 tools/lobby_reimagined/polish_20261002/native_scope/finish_export.py \
  --capture /private/tmp/lobby-polish-after-20261002 \
  --before /private/tmp/lobby-polish-before-20261002 \
  --frozen artifacts/lobby-polish-20261002/root/final-frozen-source-hashes.json \
  --native-report /private/tmp/lobby-polish-after-20261002/native-scope-verification.json \
  --concurrent-review artifacts/lobby-polish-20261002/materials/concurrent-export-review.json \
  --destination artifacts/lobby-polish-20261002/fresh-source-after
```

Add `--write` only after review/check-only passes. The successful extraction manifest reports `taskSourceExportVerified=true`, while `verified=false`, `strictNativeAuditVerified=false`, `wholeForestPreservedBeyondTaskScope=false`, `publicationAuthorized=false` and `cleanupAuthorized=false` remain explicit. The full 229-source inventory contains hashes/metadata, not unrelated Source text. Any later capture, source/delta, review or audit change invalidates this closed approval. Do not publish while the other developer's temporary QA remains or their current work is unconfirmed.

Preserve both full native places, jointly serialized forests, metadata, complete Source/editor captures and their hash receipts in a durable directory outside Git, such as `/Users/zeanjuul4/RobloxNativeBackups/lobby-polish-20261002/{before,after}`. Verify copied bytes against the recovery receipt. Do not rely on `/private/tmp` for long-term recovery. Do not commit raw `.rbxl`/`.rbxm` files, transfer chunks or complete `scripts.json` game catalogs.

Refresh the explicit owned-file inventory after final export and verification records:

```sh
python3 tools/lobby_reimagined/polish_20261002/native_scope/finish_inventory.py \
  --repository '/Users/zeanjuul4/Documents/Roblox Horror REPO' \
  --output artifacts/lobby-polish-20261002/materials/final-commit-inventory.json \
  --pathspec /private/tmp/lobby-polish-task-pathspec-20261002.nul

GIT_OPTIONAL_LOCKS=0 git status --short --untracked-files=all -- \
  tools/lobby_reimagined/polish_20261002 \
  artifacts/lobby-polish-20261002 \
  assets/models/lobby-material-polish-20261002
```

The inventory includes meaningful current-task tools, candidates, baselines, fixtures, asset maps, screenshots, reviews and receipts within these three owned directories. It excludes old task directories, native binaries/chunks, complete game Source catalogs, caches, known credential filenames and symlinks. It is a path inventory, not a content or secret review. Root must inspect the exact final content and staged diff before committing.

After content review, root stages only the explicit NUL pathspec:

```sh
git add --pathspec-from-file=/private/tmp/lobby-polish-task-pathspec-20261002.nul --pathspec-file-nul
GIT_OPTIONAL_LOCKS=0 git diff --cached --check
GIT_OPTIONAL_LOCKS=0 git diff --cached --name-only
```

Inspect the task's staged statistics and complete diff with the inventory paths passed as structured subprocess arguments; this avoids unsafe shell expansion and reads no unrelated Blender file. If another developer has staged unrelated paths, preserve them and commit only the task pathspec:

```sh
git commit --only --pathspec-from-file=/private/tmp/lobby-polish-task-pathspec-20261002.nul --pathspec-file-nul \
  -m 'Polish R4 lobby materials, bays, shop and end clutter'
GIT_OPTIONAL_LOCKS=0 git log -1 --oneline
```

Record the actual local commit ID. Publishing is a separate root action through Studio to the existing place `131311258779917`, universe `10559217407`; require the successful publish result before claiming live changes. Do not publish with material verification blockers. Add the successful publication/version receipt and commit that final task record separately if it did not exist at the first commit. Source/native checks do not establish multiplayer or performance; retain the actual Play evidence and its limits.
