# Authoritative Edit installation inputs, 2026-10-09

The owner released the Play pause and authorized installation. This folder holds
new read-only exports from the authoritative **Edit** datamodel of the existing
Backrooms place, after repository inspection at HEAD 9ccb7ee7.

No Studio write or Play transition was performed by this worker. Root owns guarded
installation, native backups, native probes, gameplay verification and publication.
Unrelated RoundUI, Poolrooms Ambience and cleanup changes were preserved.

Fresh Source/editor parity is true for both exact instances:

| Path | Class | Instance debug ID | Bytes | Before SHA256 |
|---|---|---|---:|---|
| ReplicatedFirst.Lobby Loading Screen | LocalScript | 1_31065 | 36,701 | 872b9ed13fdc0e21332a844a6931b5ba2796a1ffd659a45f6cf0d5d945049583 |
| ServerScriptService.GameManager | Script | 1_408341 | 190,167 | 0969202a4cbb3898b32608608905e19179eb7f8b645d1613c2f5a91980984ebe |

Both fresh Edit sources match the earlier frozen snapshots byte-for-byte, so no
concurrent reconciliation was necessary and no incompatible source changes were
identified. Proposed hashes remain:

- LobbyLoading: 80818a55cab10e8bd85c5c48ac6953280f4013bd9272736eda781219fc6fce92
- GameManager: 15771bdabc9fd070d6714a4386a5babe7354b3377c8e5c8f207d718c46ab804c

Run the frozen contracts against these new installation files:

```powershell
python tools/optimization_20261009/loading/install/verify_install_proposals.py G:/Roblox/MongoTV/_local/optimization-20261009/luau-0.741/luau.exe
```

Results: both full proposed scripts compile; loading policy **51** checks pass and
spectator focus **51** checks pass. Separate receipts record exact proposed hashes.
The emitted native fixtures are prepared, not run, and still use mocked engine
boundaries. These results do not establish actual streaming, asset fetches,
multiplayer performance or successful publication.

Before root writes, verify the exact instance/class/debug ID and compare both
Source and editor source to the fresh baseline **inside** UpdateSourceAsync.
If either changed, reread and reconcile live Studio. Do not install an older full
source merely because this folder exists.
