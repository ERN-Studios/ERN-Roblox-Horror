# Final Level 5 closure source audit

Read-only Edit export from Studio `e7dbf962-5b02-4de6-9494-ef440fb543aa`, observed 2026-09-27 11:10:21–11:10:22 UTC. The root task owns installation/publication and separately verified the native closed lobby. This export does not infer publication from `game.PlaceVersion`, which still reports cloud Edit metadata 2150.

| Script | Bytes | djb2 | SHA-256 |
|---|---:|---:|---|
| GameManager | 166065 | 2083096384 | `1a5d4162bc38d900a67051af8bd450607e141bd2d46c06c820f7716ec57cdfc3` |
| TunnelLobbyBuilder | 116614 | 3201910213 | `735d5e62b09351de521b6246b5654367def1c70e84415510a478cc6f652ac9f2` |

Source/editor text was read in ten UTF-8-safe chunks. Every read checked the full current source's expected length/hash, exact Source/editor equality and stability before/after the read. Local assembly checked contiguous ranges, byte lengths and both rolling hashes. Exact copies are in `sources/` and `editor-sources/`; all properties and hashes are in `verified-source-receipt.json`.

Only these two verified repository script mirrors were updated. `tools/record_synced_source.py` recorded exactly their two manifest entries. All four other Level 5 task-script edits still match the post-install export byte-for-byte. Root concurrently updated the manifest's source/studio header from publication v2156 to v2157; that newer header was preserved.

The closure differs from the opening mirror only by:

- Both GameManager Level 5 default entry flags becoming false.
- Level 5's builder definition becoming inactive.
- Removing `or def.level == 5` from the room-construction override, so inactive Level 5 stations remain offline. The existing Level 4 developer behavior is preserved.

Both scripts compile. **120 offline assertions pass**, executing the exact exported access functions/default initializers and the actual builder level-definition/room-construction expressions. Normal, developer and mixed rosters are denied Level 5 with the closed configuration; the doorway and station room build inactive. Existing Levels 1–3 and Level 4/6 policy remain unchanged. These tests do not claim live-server restarts or native teleport verification.
