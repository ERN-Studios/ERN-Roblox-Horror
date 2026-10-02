The strict nine-task-Source comparison failed on an authoritative concurrent Level 1 edit. Its exact failure is retained in `artifacts/lobby-access-spawn-20261002/backup/native-scope-strict-nine-failure.json`; neither that verifier nor its baseline was weakened or restored into Studio.

`verify_native_scope_with_concurrent.luau` is a separate offline comparison. It permits the same nine task path/class pins and precisely two additional existing Source bodies, pinned before and after in `backup/concurrent-source-pins.json`: MazeGenerator and BlenderRoomRenderer under `ServerScriptService.Level 1 Systems`. It changes only local deserialized copies for comparison, then requires exact canonical equality of all remaining native object data. It permits no editor geometry or SpawnLocation change. All captured service properties, collision groups/matrix and material overrides must also match. The scoped task installer receipt contains nine exact candidate targets; neither concurrent path is among those writes.

The actual full comparison passed: nine task Sources plus two explicitly accounted concurrent Sources, all remaining native state preserved, and zero captured service-property differences. `backup/native-scope-with-concurrent.json` contains the precise captures, manifest and concurrent pins hashes. This does not claim that all unrelated Sources were unchanged or that concurrent Source semantics were reviewed by this verifier. Parent/other-agent review is recorded separately.

Reproduce after full capture verification:

```sh
/private/tmp/level6-lune-20261001/lune run /private/tmp/lobby-access-spawn-tools-20261002/verify_native_scope_with_concurrent.luau /private/tmp/lobby-access-spawn-20261002/before /private/tmp/lobby-access-spawn-20261002/after '/Users/zeanjuul4/Documents/Roblox Horror REPO/tools/lobby_access_spawn_20261002/combined/manifest.json' '/Users/zeanjuul4/Documents/Roblox Horror REPO/artifacts/lobby-access-spawn-20261002/backup/native-scope-with-concurrent.json' --runtime-sources-only /private/tmp/lobby-access-spawn-tools-20261002/concurrent-source-pins.json
```

The separate synthetic integrity proof accepts that exact scope and rejects an additional spawn change, unrelated geometry change, service Gravity change, or incorrect concurrent Source pin. These are offline integrity fixtures, not gameplay tests.

Both full native places have been reconstructed, reopened and verified with durable copies under `/Users/zeanjuul4/Documents/Roblox Studio Backups/20261002-lobby-access-spawn`. The final AFTER place SHA256 is `14b980cefbfd347db5bc3d2715fa97b02e7b3ae331043b147a5669581d94c94b`, with 228 Sources and no Source/editor conflicts. Existing 29 service reconstruction property errors and 129 unreadable service-property limits remain explicit; the successful forest proof does not erase those limits. No helper performed a Studio write or publication.
