# Studio code mirror and repository cleanup - 12 October 2026

Captured the authoritative Studio Edit place `131311258779917`, universe
`10559217407`, at `2026-10-12T19:32:18.785168+00:00`. The native backup observed
place version `3053`. All **217 scripts and 15 RemoteEvents** from
the entire DataModel are mirrored, including archives still held by Studio.

- ReplicatedFirst: 1 script.
- ReplicatedStorage: 21 scripts.
- ServerScriptService: 105 scripts.
- ServerStorage: 22 scripts.
- StarterPlayer: 68 scripts.

Every script's Source matched ScriptEditorService editor source exactly.
The complete catalog records exact segments, classes, instance/parent identities,
raw Source/editor SHA-256, canonical source SHA-256, independent fingerprints,
Enabled/Disabled, RunContext, LinkedSource, Archivable, readable SourceAssetId,
attributes and tags. Bounded catalog/source pages check native hashes; full
catalogs matched before/after capture and before/after local reconciliation.
These checks bracket observed states; they do not claim a continuous atomic epoch.

The local reconciliation created 4 mirrors, updated 48 and kept
180 unchanged; 0 retired mirror files were removed.
Independent FNV-1a/djb2 parity passed for all 217 scripts, with no missing,
extra, drift, wrong-class or permitted-newline differences. All manifest hashes
were also recomputed from the repository files.

[Source verification receipt](studio-sync-20261012/source-verification.json),
[independent parity](studio-sync-20261012/parity-result.txt) and
[native recovery receipt](studio-sync-20261012/native-backup-summary.json)
record the exact scope and checks. The new complete exporter has 15 passing
offline tests, including large Unicode sources/catalogs, bounded transport,
source/editor conflicts, attribute type changes, path collisions and local
concurrent-change rejection. Its generated Luau compiled at -O0 and -O1.
The existing source-contract, full-sync and native-metadata suites also passed.
These are export checks; gameplay, multiplayer, streaming and performance were
not retested. Studio source, objects, settings and Play state were not changed.

Before reconciliation, the ten starting dirty files were preserved at
`refs/checkpoints/studio-sync-20261012` (`daccdfd3f833b8e0c30ec4a0445ebe0572932284`),
with exact working bytes and the original real index in
`_local/studio-code-sync-20261012/`. The scoped mirror recovery ZIP is
`_local/studio-code-sync-20261012/full-snapshot/before-mirror.zip`.
Other developers' unrelated tool, coordination and cleanup work remains local.
Verified current Studio mirrors are included in this delivery even when a matching
local edit already existed before the export.

The jointly serialized native forest and locally reconstructed `.rbxl` remain
local at `_local/studio-code-sync-20261012/native-backup/before`. Strict forest equality after reopening
passed for 218 roots, 417,891 serialized native instances
and all 217 Sources. This is an offline reconstruction, not
Studio Save-to-File. The sole measured child omission is the engine-owned,
nonarchivable `Workspace.StarterCharacter.Humanoid.Status`. The receipt lists
29 service reconstruction errors and 129 unreadable property keys; retained raw
forest/service metadata and hosted asset references do not prove exhaustive
service parity or downloaded external asset payloads.

Repository cleanup corrected obsolete Studio overwrite directions in README
and CLAUDE, marked dated gameplay claims as historical, removed the two redundant
ignore fragments under `ERN-Roblox-Horror-main/`, and removed 188
ignored Python bytecode files (6,629,444 bytes). Game assets,
native archives, tools, reviewed receipts and unrelated developer changes were
preserved. No broad cache, asset or history purge was performed.

Run the complete export into a fresh local output directory:

```powershell
python -B tools/capture_studio_snapshot.py capture --output _local/studio-code-sync-NEW/full-snapshot
python -B tools/capture_studio_snapshot.py verify --output _local/studio-code-sync-NEW/full-snapshot
python -B tools/capture_studio_snapshot.py apply --output _local/studio-code-sync-NEW/full-snapshot
python -B tools/capture_studio_snapshot.py verify --output _local/studio-code-sync-NEW/full-snapshot
```

`apply` writes only the local mirror and first saves its recovery ZIP. Preserve
a Git checkpoint and native recovery separately, inspect the exact task staging,
and commit the verified export. No repository command authorizes overwriting
Studio. This task makes a local commit only; it does not push the 48 preexisting
local commits to GitHub or publish unrelated current Studio work.
