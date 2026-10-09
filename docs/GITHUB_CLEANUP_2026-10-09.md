# GitHub delivery and cleanup — 9 October 2026

The owner requested committing the complete relevant project to GitHub and
removing old dumps, temporary files and obsolete material.

This delivery starts from GitHub's existing `main` at `0b830793`, then carries
over the verified Studio source snapshot, current local tools/tests, source
assets and substantive documentation. The unrelated older local Git history
is retained locally and is not introduced into GitHub's history. The update
uses an ordinary commit and push; it does not rewrite remote history.

All 230 scripts and 15 RemoteEvents from the verified Studio Edit snapshot
remain mirrored, including Studio-held archives. The manifest records their
paths, classes, source hashes, attributes and relevant properties. During this
GitHub cleanup Studio was running Play, so the delivery uses the previously
verified Edit snapshot and does not interrupt the playtest or write Studio.

Cleanup removed 6,209 obsolete artifact files from the original local checkout
(847.6 MB), 2,961 obsolete artifact files from the prepared GitHub checkout
(1,105.5 MB), and 320 loose local scratch files (17.5 MiB). These figures refer
to distinct physical checkouts; do not add them to describe the size reduction
of one repository. Old asset snapshots, diagnostic variants, authoring
autosaves and two pre-edit Blender backups were also removed.

Kept material includes actual importer/generator inputs, test fixtures, current
model sources, upload receipts and the 53 accepted source images for the
current marketing campaign. The full Cinema final4 source delivery is retained.
Human decisions, specifications and reviewed reports remain as project records.
Active work belonging to other developers stays local. The obsolete
`restore-live-assets.sh` helper was removed with the old source archive it used.

`.gitignore` excludes newly generated captures, local agent worktrees,
authoring autosaves and scratch outputs. Reviewed permanent sources and
fixtures are explicitly versioned; a generated dump is not automatically added
to the game project.

The empty/truncated local AGENTS, README, owner briefs and historical audit were
repaired from their complete committed copies. Remote-only developer tools and
assets were preserved. This cleanup removes obsolete dumps and pending-change
noise. Delivering the complete source assets can still increase the total tree
size; historical blobs already on GitHub are not removed by a normal deletion
commit.

Source parity, manifest hashes and retained dependency paths are checked for
this delivery. Gameplay and a new Roblox publication are outside its scope.
