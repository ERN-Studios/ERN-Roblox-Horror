# GitHub readiness — curated final checkpoint

Read-only readiness inspection; **nothing staged, committed or pushed**. Root additionally authorized exactly two documentation corrections in `docs/ZYNTRA_MONETIZATION_SETUP.md`: current Developer access (the two IDs published in v1865) and the stale unpublished gift-form sentence (the preserved Monetization code shipped by v1840). An exact inverse restores the pre-edit bytes. Pricing and other catalogue paragraphs were untouched.

## Repository and gates

- Branch `main`, upstream `origin/main`, remote `https://github.com/ERN-Studios/ERN-Roblox-Horror.git`. Local HEAD and a fresh read-only `git ls-remote --heads origin main` both return **7f13f532d2a420f772842444e6b901653bcdd17b** (last commit 6 September). No divergence observed; write permission was not tested.
- No applicable AGENTS.md was found in the ancestor/runtime paths. `CLAUDE.md` requires Studio parity, no blind conflicting overwrite, exact `UpdateSourceAsync` source writes and preservation of archived/backed-up content. Its historical notes are not present-day release status.
- User's final scope: complete **ceiling lights and square buttons**, defer the new PLAYER ESP/free DEV-respawn work, then commit/push and stop. **Do not commit this snapshot before both final releases and the final source audit.** Current local GM `efcd566d…e16aa0`, DevCheats `39072aee…a5149`, Store `083c53b7…87c71` contain no `playerEsp`, `freeRespawn` or `DevRespawn` additions. Square buttons will legitimately change Store later; retain the no-new-DEV delta check then. Existing already-published Pool Slide diagnostic ESP is a separate mirrored script and is not the deferred PLAYER ESP proposal.
- At inspection: **42 tracked modified files**, zero staged, approximately **2,200 untracked files / 214 MB** (counts grow as root records evidence). `git diff --check` passed. Manifest now has **126 scripts + 14 remotes**, all 140 entries synced and all 140 local file hashes matching `studio_source_contract.sha256_of`. This local check is not a new Studio audit or publication claim.

## Explicit staging groups

1. **Final audited mirror + manifest in one commit.** `mirror-paths-current.txt` / `.nul` enumerate exactly the current manifest's 140 paths plus `studio-sync-manifest.json`. The paths remain valid when the square-button source changes, but root must re-read the final manifest and ensure its set is unchanged before using the list. Do not take sources from prepared future variants. These 141 explicit paths include unchanged tracked files harmlessly; only actual changes enter the commit.
2. **The 14 authored `tools/tests/test_*.py` runners** listed in `tests-and-required-fixtures.txt` / `.nul`, plus **five exact baseline fixture Lua files (526,394 bytes)** needed by the L2-height/L3-square tests. Other listed runners read runtime source and use temporary scratch directories. Do not add their generated harness/output files. There is no need to reintroduce the excluded Testing-card tasks to preserve already-used regression code.
3. **Current release/scope documentation**, after root updates the top to the final two releases and explicit DEV deferral: `docs/TRELLO_SCOPE_2026-09-10.md` and corrected `docs/ZYNTRA_MONETIZATION_SETUP.md`. `docs/TRELLO_PRIORITET_2026-09-09.md` is optional historical context, not the current rest list. A short final release overview can point to the current top and label local-only evidence links, instead of uploading the entire raw Trello/native archive. `scoped-docs-candidates.txt` is a recommendation, not an executed add.
4. **Existing small README/CLAUDE changes**, if root includes the corresponding published Manager behaviour: their entire diff only describes the 9 September hidden-player chase update. Preserve its original provenance; this Git diff does not show which cooperating session authored it. `docs/PATHFINDING-2026-09-09.md` and its small `tools/playtest_level3_hidden_chase.luau` are analogous optional historical evidence. Avoid claiming all pre-existing dirty changes were newly implemented by this last task.

The long runtime diff is a cumulative **published Studio mirror since 6 September**, not only today's two lobby changes. It includes prior cooperative work such as hidden-player chase and Pool Slide audio. A filename does not prove authorship. The source of inclusion is the final audited current Studio mirror; do not discard those published systems merely because another session originally authored them.

### Small manifest-listed backups are necessary mirror files

There are **21 untracked manifest-listed sources**. Besides the actual Protection/Pool Slide/ceiling scripts, **12 Lua files** belong to `ServerStorage/TEMP_PipeEntityAnimations_20260909` and the five `PoolSlideContextDiagnosticBackup_*` folders. They total about 1 MB, are already explicit `synced` manifest entries, and should accompany that unchanged manifest. Excluding them would leave a fresh checkout missing files its manifest declares present. They are distinct from the untracked multi-megabyte native evidence caches under `artifacts`. No deletion, relocation, or unsanctioned manifest pruning is proposed.

## Keep local, without deleting

- Entire `artifacts/trello-20260909` by default (**~198 MB / 2,100+ files**), except the five explicitly listed test fixtures and any deliberately curated final artwork/evidence files root chooses. In particular leave mesh caches, raw native JSON/JSONL chunks, superseded proposals, generated harnesses, temporary XML containers and account/dashboard screenshots unstaged.
- `assets/marketing/roblox-ads-v2-relaunch-20260909` (**~13 MB / 11 files**): separate ad/marketing work with no demonstrated dependency on these runtime commits. No ads/pricing work is requested at finish.
- Root-level numeric files (`1`, `1140`, `1557`, …), `.codex-death-cd-view.jpg`, and untracked `MEMORY.md`: scratch/capture/personal project context; leave untouched and unstaged.
- `docs/POOL-SLIDE-SERVER-USAGE-2026-09-09.md` is a long historical diagnostic report, and `docs/PRICING_REVIEW_2026-09-09.md` is deferred-topic research. Neither is necessary to run the current game. Raw `docs/TRELLO_SNAPSHOT_2026-09-09.json` contains board history, not runtime code; retain locally unless deliberately curated.
- Published Roblox image IDs are sufficient for runtime image loading. Original generated master PNGs can be a separate curated asset-source commit if desired; do not accidentally include all intermediate image/upload/native folders.

## Ignore and secret-file check

Existing `.gitignore` covers `.claude/`, `.claude-flow/`, all `graphify-out/`, `_local/`, `.studio-push-backups/`, bytecode, Studio export binaries, and `.env`. The actual filename `tools/discord_trello_bot/.env` is ignored. A strict filename-only check found no credential/key/env names in tracked + unignored candidates; **no secret file contents were read**, and this is not a content-secret audit. Token-product fixture names are not credentials. Avoid blanket `git add -A`, wildcard all-artifacts adds, or force-adding ignored local settings. No ignore change is required for an explicit allowlist; do not delete local evidence to make status clean.

`core.autocrlf=true`, no tracked `.gitattributes`. Git's LF→CRLF notices are transport policy, not source drift; manifest canonicalizes line endings. Do not introduce `git add --renormalize .` or change line-ending policy during this release. The corrected document preserves its existing mixed transport endings outside the two targeted paragraphs.

## Root's final sequence (not executed here)

After native/publication of lights and square buttons, stop Play and use the established whole-source compile/parity audit; verify no pending/conflict entries, no temporary fixture enabled, no new PLAYER ESP/free-respawn source delta, and no unrecorded source after the final release. Existing feature tests and reviews remain their own evidence; re-run relevant final-composition checks if the final bytes changed, rather than restarting every native suite.

Review final paths, then use the explicit source and test lists, for example from repository root:

```powershell
git --literal-pathspecs add --pathspec-from-file=artifacts/trello-20260909/git-readiness-prepared/mirror-paths-current.nul --pathspec-file-nul
git --literal-pathspecs add --pathspec-from-file=artifacts/trello-20260909/git-readiness-prepared/tests-and-required-fixtures.nul --pathspec-file-nul
git add -- docs/TRELLO_SCOPE_2026-09-10.md docs/ZYNTRA_MONETIZATION_SETUP.md
git diff --cached --name-status
git diff --cached --stat
git diff --cached --check
```

Add optional reviewed documentation files only by exact path. Confirm the staged tree contains every file referenced by its staged manifest and none of the excluded raw/effect proposals. The readiness folder itself is a local staging aid, not an automatic commit target. Re-read `origin/main` immediately before publishing Git; if unchanged, one curated final checkpoint commit (e.g. `Ship reviewed Trello gameplay and lobby updates`) followed by **`git push origin HEAD:main`** matches the user's explicit instruction. Use the actual final Roblox release IDs in the commit description. No force push or extra branch/PR is required by the task. If the remote has moved, preserve both histories and inspect the changes before a normal merge/rebase; do not overwrite remote work.

Final user report should give the actual commit and pushed branch, completed lights/square release IDs, the explicitly deferred DEV cards, and that large local evidence remains intentionally unstaged. A dirty working tree caused only by preserved excluded files is not a failed commit.
