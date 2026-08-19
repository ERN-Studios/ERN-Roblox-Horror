# Backrooms: No Way Out — working notes for Claude Code

## Where this session is running matters

**Roblox Studio can only be reached from a session running on the owner's Windows
PC.** The bridge is `%LOCALAPPDATA%\Roblox\mcp.bat`, launched through `cmd.exe`
by `tools/sync_from_studio.py`; Studio's plugin talks to it over loopback.

| Session started from | Runs on | Studio reachable? |
|---|---|---|
| VS Code extension, or `claude` in a terminal on the PC | that PC | **yes** |
| claude.ai/code, mobile, or any cloud/web session | Anthropic Linux VM | **no** — no `cmd.exe`, no `%LOCALAPPDATA%`, no route to the desktop |

A cloud session can still do everything else: read and edit the mirrored
scripts, run the analyzers, commit, push, open PRs. It just cannot read from or
write to the live place. Check with `uname -s` — `Linux` means no Studio.
Don't spend time debugging the MCP connection in that case; hand the Studio step
to a local session instead.

## The repo is a one-way mirror of Studio

Studio is the source of truth. Folders mirror the Explorer 1:1 and files are
named `Name.ClassName.lua`. `studio-sync-manifest.json` holds a sha256 per
mirrored script plus a `status`:

- `synced` — repo and Studio agree.
- `pending-studio-push` — the repo copy is NEWER; it is queued for Studio.
  `studioSha256Before` records what Studio should still hold, for conflict
  detection.
- `studio-push-conflict` — a push found Studio had drifted; needs a decision.

**Never run `pull_source_from_studio.py` while entries are pending** — it would
replace those newer repo files with Studio's older source. The tool now skips
them by default (`--force` overrides).

## Syncing

```
python tools/pull_source_from_studio.py --audit   # Studio -> repo: what drifted
python tools/pull_source_from_studio.py           # pull it

python tools/record_pending_push.py               # repo -> Studio: queue edits
python tools/push_repo_to_studio.py --audit       # classify against live Studio
python tools/push_repo_to_studio.py               # apply (two-phase, verified)
```

Writes into Studio must go through `ScriptEditorService:UpdateSourceAsync` —
raw `.Source` writes leave LocalScripts running stale bytecode. Reads must go
through `execute_luau` reading `.Source`, because `script_read` can serve a
stale editor buffer after a programmatic write.

`tools/tests/test_push_repo_to_studio.py` verifies the push tool against a fake
Studio without touching anything real (needs a `luau` binary; see the file).

## Current state (2026-08-19)

Branch `claude/roblox-code-audit-di6qxi`, PR #1: a project-wide audit of ~45k
lines — real bugs, dead code, removed-feature leftovers, duplicate work and
optimizations. **All 37 queued scripts were pushed into Studio on 2026-08-19
and verified byte-for-byte; the manifest holds no pending entries.** The PR
body is the full report.

Landing them turned up three faults in the sync tooling, all now fixed:
`select_studio` only retried one obsolete wording of StudioMCP's cold-start
error and compared place names before Studio began appending `(placeId: N)`;
the post-write verification could read stale metadata against fresh chunks and
report a failed push that had in fact landed; and the staging buffer could not
carry a source of 200k characters or more, which is why Level 2 World Builder
(235,839 B) needed the buffer to spill into numbered child parts.

Deliberately left alone and awaiting a decision from the owner: teammate
flashlights render twice (client MateBeam + FlashlightSync mounts); Level 3
room wall-art tables are keyed to retired room ids so generated rooms get no
drawings; the Slidemouth controller is complete but nothing starts it.

## House rules

- Do not remove or move in-game objects (walls, props, world geometry). Code
  only, unless asked.
- `ServerStorage/*Backup*` folders are intentional archives — never audit or
  clean them.
- Testing vs production values are documented in README.md; both are currently
  at production settings.
