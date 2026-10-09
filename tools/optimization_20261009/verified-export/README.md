# Verified authoritative seven-source export

The initial read-only Edit export of the seven installed optimization scripts recorded **373081 bytes**. All raw UTF-8 source bytes came from Studio through bounded raw-byte hexadecimal responses, with no line-ending or Unicode normalization. The later guarded Level 2 root-name correction added five bytes; this historical seven-source `manifest.json` now records **373086 bytes** and that correction's fresh exact-source receipt. Its GameManager remains the original seven-source version. The [current eight-source export](../loading/install/compatibility/spectate-bootstrap/verified-export-eight/manifest.json) separately records the subsequently installed GameManager and SpectateController bootstrap fix; all historical receipts remain preserved.

Exact Source/editor parity and candidate equality were checked before export, on every one of 96 byte chunks, and again across all seven sources after export. Every read pinned exact native path, name, class, instance debug ID, parent debug ID, parent path and parent class. Every tool response was limited to 12000 bytes. Every exported disk file was rehashed before the manifest was marked complete.

The raw files retain native Studio path segments and Roblox `Script.lua`, `LocalScript.lua` or `ModuleScript.lua` suffixes. Each manifest row records `rawFile`, `expectedRepositoryPath`, `class`, `instanceId`, `parentId`, `rawBytes`, `rawSourceSha256` and `editorParity`. Root can use this export for its separately controlled mirror reconciliation.

The exporter wrote only this task directory. It performed no Studio mutation, native backup, runtime repository mirror write, or sync-manifest write. It is a source export, not a whole-place or native asset export. The owner explicitly instructed that no backups be taken.

`export_verified_sources.py` is the read-only capture tool. It refuses to overwrite this manifest or existing raw exports, to preserve this verified receipt. It uses the coordinating native runner's existing MCP client and reviewed candidate hashes; it never invokes staging, require, gameplay, publication, or source updates.

`promote_verified_mirrors.py` prepares a scoped repository promotion. Default invocation connects to no Studio and writes only `promotion-preflight.json`, recording the exact current local before SHA256 and byte count. The local preflight passed for all seven: five existing mirrors match exact native before bytes, including the concurrently updated L2 Sound cleanup baseline, and the two new effect budget mirrors are absent. No CRLF normalization was needed. In general only exact native before/after or a CRLF-to-LF-only equivalent is accepted; any other local Source is rejected for reconciliation.

Root runs the separately controlled copy:

```powershell
python tools/optimization_20261009/verified-export/promote_verified_mirrors.py --apply
```

Apply rereads exact native Source/editor and exported instance/parent identity pins across all seven before any repository copy. It records those fresh current native hashes, rechecks all captured local before bytes, then copies only the raw source payload to each `expectedRepositoryPath`. Immediately before each copy it rechecks the local before bytes and export hash; afterward it requires exact copied bytes and rechecks every destination. The short-lived replacement file contains only the after candidate, never an old Source backup. Output is the separate `mirror-promotion-receipt.json`. Existing receipts are refused; root may supply a new task-owned `--receipt` filename after reviewing any interrupted attempt. Neither invocation writes Studio, a native backup, `studio-sync-manifest.json`, git staging, or a commit.

`test_promote_verified_mirrors.py` passed 20 bounded local guards covering unexpected/changed/appeared mirrors, exact before/after and CRLF equivalence, absent new mirrors, modified exported payloads, precise copied bytes and temporary-file cleanup. It used only synthetic small strings under a test-owned folder and did not connect to Studio or change real runtime mirrors. The generated read-only seven-source native CAS compiled with Luau 0.741. Receipt: `promotion-preparation-result.json`.
