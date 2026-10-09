# Studio code mirror — 9 October 2026

Captured `[UPDATE] BACKROOMS: STAY QUIET`, place `131311258779917`,
universe `10559217407`, from Studio **Edit** at
`2026-10-09T17:14:40.588140+00:00`.

The repository mirrors all **230 LuaSourceContainers and 15 RemoteEvents**
found by traversing the entire DataModel, with no service, depth or result cap.
The source inventory comprises 1 script in ReplicatedFirst, 20 in
ReplicatedStorage, 102 in ServerScriptService, 42 in ServerStorage,
63 in StarterPlayer and 2 in Workspace. Archived scripts still held by Studio
are included.

Every script's `Source` matched `ScriptEditorService:GetEditorSource` exactly.
Source transfers rechecked the script class, source fingerprint and editor
agreement for every chunk; the complete inventory and properties matched
again after capture and after repository reconciliation. Studio remained in
Edit. No Studio source or game object was changed.

`studio-sync-manifest.json` records exact path segments, classes, canonical
source SHA-256 hashes, attributes and relevant script properties. Retired
repository mirrors absent from the fresh Studio inventory were removed.
The sync selector also accepts this experience's current update-banner names,
while retaining its place-ID checks.

Verified results, with logs in `artifacts/studio-sync-20261009/`:

- Independent FNV-1a/djb2 parity: **230 exact**, 0 permitted-newline differences,
  0 drift, 0 class mismatches, 0 missing and 0 extra scripts.
- `python tools/tests/test_studio_source_contract.py`: PASS.
- `python tools/tests/test_full_sync_contract.py`: PASS.
- `python tools/verify_studio_parity.py artifacts/studio-sync-20261009/studio-parity.txt`: PASS.

Before reconciliation, tracked local changes were preserved at
`refs/checkpoints/studio-sync-20261009`
(`3c82cf5e507d8f6e6613ae7e9d8b7d49c87b0595`). Overwritten or removed local
mirror files, including untracked ones, were separately preserved in
`_local/studio-code-sync-20261009/before-mirror.zip`.

This delivery covers Studio source code, RemoteEvent markers and verification
records. It does not serialize the complete place or hosted assets. Historical
exports, scratch files and unrelated local documentation, tests and asset
changes remain local. Gameplay and compilation were not rerun for this source
mirror. No GitHub push, history reconciliation or Roblox publication is part of
this commit.
