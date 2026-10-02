These helpers capture the authoritative Studio place before and after the scoped Level 5/6 DEV gate and main lobby spawn changes. Capture and recovery helpers do not change Studio instances, Sources, settings, assets, access, or publication. The separately pinned scoped installers apply only the approved task Sources after fresh baseline checks. The receiver binds loopback only and refuses different bytes at an existing capture destination. The task always transfers a new complete native forest; it does not treat the previous task's checkpoint as current state.

Use frozen tools from `/private/tmp/lobby-access-spawn-tools-20261002` so the executing inputs remain stable. Start `receiver.py --phase before` on port 8912, then run the receiver's `/capture` Luau in the existing Studio Edit command bar. Inspect `shared.__lobbyAccessSpawnBackupStatus` and receiver completion. Do not start a second capture while the first is running.

After the capture completes, run:

```sh
python3 /private/tmp/lobby-access-spawn-tools-20261002/verify_backup.py --phase before --artifacts '/Users/zeanjuul4/Documents/Roblox Horror REPO/artifacts/lobby-access-spawn-20261002/backup'
```

The verifier validates exact source/editor hashes and native transfer hashes, reconstructs the complete native place using the preserved helper versions, reopens it, proves canonical native-forest equality, and hashes reread durable copies. Raw native chunks, full script bodies, service-property metadata, and reconstructed native places remain under `/Users/zeanjuul4/Documents/Roblox Studio Backups/20261002-lobby-access-spawn/<phase>`. Only hash inventories and proof summaries are exported into task artifacts. Unreadable service properties and reconstruction limitations remain explicit; canonical forest and Source equality do not erase those limits.

Stop only this receiver's process before starting it again with `--phase after`; then repeat capture and verification. Baseline Source/editor and SpawnLocation comparisons still need fresh in-write checks for each Studio mutation. Recovery proof does not itself authorize publication, prove behavior, or substitute for Play testing.

`claude_review.py` is a bounded read-only review runner. It supplies an explicit prompt to Claude Opus at max effort, disables tools and all MCP access, never saves the internal reasoning stream, and records actual returned canonical model, output, timeout, and owned-child cleanup. A timeout is retained as a failed attempt, never as completed collaboration. Run with `--prompt <file> --out <directory>` after the parent provides exact live baseline and candidate code.

The final task uses the established server runtime architecture. `GameManager` builds and validates the revised lobby before loading characters, then moves the canonical pad in that server. Editor-native geometry and pad properties must stay unchanged. The abandoned attempt to construct the runtime bake from an Edit client does not authorize an editor scene replacement.

After both full native captures have verified, compare them with the exact final installed candidate manifest:

```sh
/private/tmp/level6-lune-20261001/lune run /private/tmp/lobby-access-spawn-tools-20261002/verify_native_scope.luau /private/tmp/lobby-access-spawn-20261002/before /private/tmp/lobby-access-spawn-20261002/after '/Users/zeanjuul4/Documents/Roblox Horror REPO/tools/lobby_access_spawn_20261002/combined/manifest.json' '/Users/zeanjuul4/Documents/Roblox Horror REPO/artifacts/lobby-access-spawn-20261002/backup/native-scope.json' --runtime-sources-only
```

That mode permits exactly the nine path/class-pinned Source targets (eight existing Sources and the one new Guard), recomputes every Source/editor digest, and compares the full native forest after reversing only those approved Source changes in a local deserialized copy. It permits no native geometry, canonical pad, service-property, collision-group, or material-override changes. A mismatch remains a failure for review; it must never trigger restoring Studio from a repository or backup. `test_native_scope.luau` generates four offline synthetic integrity cases. These fixtures are not actual gameplay evidence.

The completed Claude contribution is the focused authorization review under `artifacts/lobby-access-spawn-20261002/claude/focused-auth`. It actually returned `claude-opus-5-5` at requested `max` effort with tools disabled. Its source-only qualifications remain explicit, and Codex's follow-up closure pins the omitted queue/campaign context. Earlier larger review timeouts and the superseded interrupted attempt are preserved separately; they are not completed reviews.
