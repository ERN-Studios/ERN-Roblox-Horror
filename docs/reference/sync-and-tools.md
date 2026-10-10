# Historical reference: sync-and-tools

Read only the section needed for the current task. This is retained history, not current startup policy.
CLAUDE.md and AGENTS.md supersede old model, ownership, testing and sync commands below.
Never automatically import this file into startup context. Dates and environment limitations may be obsolete.

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

## There is a code knowledge graph — use it before grepping

`graphify-out/` holds a graph of this codebase: every script, the symbols in it,
and what calls what. It is built by the `graphify` CLI (already on PATH) with no
LLM cost. **Start here instead of grepping blind** — it answers "what touches
this?" and "how does A reach B?" in one call.

```
graphify explain "Level 2 Round Adapter"    # what a node is and what it neighbours
graphify path "GameManager" "Pool Foam Navigator"   # how one reaches the other
graphify update . --force                   # rebuild after code changes
```

`graphify-out/GRAPH_REPORT.md` is the human-readable summary: node and edge
counts, and the named community hubs, which is the fastest map of the project's
actual structure. `graphify-out/graph.html` is an interactive view.

Five things to know:

- **Check freshness first.** The report records the commit it was built from.
  Compare it with `git rev-parse HEAD`; a stale graph will confidently describe
  code that no longer exists. On 2026-09-02 its top community hubs were still
  named after the Slidemouth and Pool Slide encounters, both long deleted.
- **`--force` is required after deletions.** `graphify update` refuses to write a
  graph with fewer nodes than the last one unless forced, which is exactly the
  case after a refactor that removes code.
- **Run it only at the repo root.** Running it inside a service folder leaves a
  nested `graphify-out/` inside the Studio mirror — four of those had accumulated
  by 2026-09-02, 42 MB of stale duplicates. All `graphify-out/` paths are
  gitignored at any depth, so they never reach GitHub, but they do clutter the
  mirror the sync tools walk.
- **`.graphifyignore` keeps retired code out.** `ServerStorage/Archive/` is real,
  parseable Lua, so graphify indexed it: 442 of 2475 nodes (18%), and two of the
  graph's largest communities were named after the retired Slidemouth. The
  archive is now excluded by `.graphifyignore` at the repo root — the files are
  untouched on disk, they just no longer answer searches with dead code. Note
  the file is only consulted on `--force`; a plain `update` leaves old nodes in
  place until you force a rescan.
- **The graph under-covers 12 files, and one of them is GameManager.** The
  extractor stops part-way through a file it cannot fully parse and keeps
  whatever it got, reporting only a `syntax errors ... partially extracted`
  warning. Across the mirror it reaches 81% of Lua lines, but the misses are
  concentrated:

  | Script | Lines | Symbols in graph |
  |---|---:|---:|
  | GameManager | 2640 | 4 |
  | Level 3 Test Suite | 3577 | 9 |
  | Level 3 Mall Manager AI Controller | 3586 | 44 |
  | Level 3 Lighting Controller | 896 | 1 |

  So **a graph query that returns nothing about GameManager is not evidence that
  GameManager does not touch the thing** — grep those four directly. The reported
  error line is where the parser gave up, not the cause: the constructs sitting on
  those lines (`export type`, `(): boolean?`, `x.y += 1`) all parse fine in
  isolation, and it is not CRLF or non-ASCII either. graphify ships as a compiled
  binary, so this is a property of the tool, not something to fix here.

### Added 2026-09-03 (afternoon session)

- **GameManager owns the Level 1 entity outside Level 1 rounds.**
  `setLevelOneEntityActive(false)` at boot and after every cleanup stores
  `Workspace.Entity` in ServerStorage as `Lobby Stored Level 1 Entity` (root
  anchored) and disables EntityAI, EntityAnimation and EntityKill; `ensureWorld`
  brings it back before `GenerateWorld`. The saved place still holds the entity
  in Workspace; that is fine, boot moves it. The Level 2/3 adapters keep their
  own isolate/restore for their rounds.
- **RoundUI sits exactly at Luau 200-register limit.** Its main chunk has 200
  top-level locals; one more fails to compile ("Out of local registers"). Put new
  state in a `do ... end` block (the closure keeps it as an upvalue), and run the
  compile probe after every RoundUI edit.
- **Flashlight beam numbers live in `ReplicatedStorage.FlashlightProfiles`**
  (`Own`, `Mount`, `Mate`, `Spectate` x `BASE` / `L3` / `L3_BLACKOUT`). The sets
  differ on purpose (they are what each script carried); the double-render is
  still an open owner decision.
- **Level 2 remotes** are in `ReplicatedStorage."Level 2 Remotes"` (`Level 2
  Alert Event`, `Level 2 Sound Event`); Pool Foam keeps its own folder.
- **New scripts cannot be pushed by the tools.** Create them in Studio first via
  `execute_luau` + `UpdateSourceAsync`, then add the manifest item with
  `sha256_of` / `canonical_bytes` from `tools/studio_source_contract.py`.
- **`require` inside `execute_luau` is a separate module instance**, even on a
  play session Server datamodel: module-local session state is invisible there.
  Read attributes and instances instead.

### Added 2026-10-07 (night) - The store pictures on Roblox were replaced from a session (live)

- **Owner**: "Open the exact place where the pictures can be changed", then "replace all pictures and put these in".
  Live since about 23:35: the Experience Detail gallery holds the ten new pictures (T01, T02, G03, G05, G08, G09,
  G11, G02, G04, G12, each with an alt text, all approved), the Home Page tile is T01, and T02 to T06 are uploaded
  and approved but not shown. The six old gallery pictures and the old tile are off the page; copies of them and
  of the icon are in `~/Desktop/Backrooms Stay Quiet - Backup live Roblox billeder 2026-10-07`. The icon was not
  changed. The Level 2 pictures (G03, G04, T02) show the new map and are public now, by the owner's word.
  Which Roblox image each file became: `artifacts/promo-20261007/store-upload.json`.
- **How, without the mouse or the keyboard**: `tools/promo/dashboard.py` runs JavaScript in the owner's own
  Creator Dashboard tab through AppleScript (`execute ... javascript`; it works because "Allow JavaScript from
  Apple Events" is on in their Chrome) and sends requests FROM THE PAGE, so they carry the signed-in session as
  the dashboard's own buttons do. No cookie, password or key is read. `tools/promo/store_pictures.py` has the
  calls and `status` (what is live); its docstring lists every address. The page is
  `create.roblox.com/dashboard/creations/experiences/10559217407/places/131311258779917/thumbnails`.
- **Two sets, two services.** The gallery is the place asset's `previews` list (read and PATCH through
  `apis.roblox.com/assets/user-auth/v1/assets/<place>`; one PATCH with the whole list removes, reorders and sets
  alt texts; new pictures are added with `publish.roblox.com/v1/games/<universe>/thumbnail/image`). The Home
  Page tile is `apis.roblox.com/thumbnail-personalization-api` (upload, then `personalization/create` with the
  ids to show). The addresses were read out of the dashboard's own public script files.
- **Traps.** The script runs in an isolated world: it sees the page's DOM but not its React, the site's policy
  blocks inline scripts, and the page's own "Upload thumbnail" control took a file handed to it and did nothing
  while the tab was in the background. After a PATCH the list goes through half-changed states for some seconds
  AFTER the operation reports done (a read right away showed four pictures missing that were there ten seconds
  later): read until it matches before deciding anything. The old
  `develop.roblox.com/v1/universes/<id>/thumbnails/<id>` DELETE answers 200 and removes nothing. A bare
  `open <url>` from the session's shell opened nothing; `open -a "Google Chrome" <url>` did.
- **Order that never leaves the page empty**: add new pictures beside the old (ten at most), wait for "approved"
  in the public list, set the list to the approved new ones, add the rest, set the final order. Moderation took
  seconds that night. No Chrome-extension or computer-use tool was available in the session.

## Windows Studio updates retained — 2026-10-09

<!-- End of preserved original sections. -->
