# Backrooms: Stay Quiet workflow

## Project operating defaults — owner instruction, 2026-10-10

- Current checkout is `/Users/zeanjuul4/Projects/stayquiet-poolrooms-audio-20261009`,
  branch `codex/poolrooms-audio-20261009`; the main checkout is stale for game work.
- One named agent owns Studio (currently the paused `Main RBLX GAME DEV` Claude
  session). Handover must record the previous owner idle, checkpoint and new owner.
- At most one extra agent works concurrently on a scoped independent deliverable.
  Subagents/CLI jobs/Operator workers count; helpers must not touch shared Studio
  or start more agents. Preserve unknown sessions and collaborators' work.
- Ordinary sessions: Opus Medium with Fast/Ultracode off; gpt-6.1-sol Medium,
  Standard. Low suits known simple procedures; higher reasoning is task-specific.
- No compulsory Codex share in every batch and no compulsory Claude final QA.
  Each task owner implements/integrates and verifies; cross-model review needs a reason.
- Use `tools/agents/start-codex.sh` for bounded Codex jobs and the delegation
  template in `docs/workflow/`. Do not revive historical Ultra/Fast launch commands.
- Read only relevant details from `docs/reference/`; never load the whole archive
  automatically. CLAUDE.md is the current short guide; historical limits are superseded.
- Local multiplayer, mobile simulation and isolated DataStore/MemoryStore tests
  are supported subject to `docs/workflow/testing.md`; real teleports need the
  Roblox client. Source inspection alone does not prove runtime behaviour.
- Keep all existing permission, safety and publishing rules below. Setup-only
  documentation/configuration changes do not call for a Roblox publish.

## Studio is authoritative — owner instruction, 2026-09-09

- **Roblox Studio is the sole source of truth.** GitHub and Trello must never
  overwrite Studio merely because their data or instructions differ. They are
  downstream records of the live Studio game, not a deployment baseline.
- Before every game-development task, inspect repository status and current
  remote history, then read the relevant live Studio instances and source.
  Repository synchronization must never silently become a Studio write.
- Other developers edit Studio and Git concurrently. Preserve their unrelated
  work. Before a requested Studio edit, verify the exact instance, compare its
  current Source and editor source, and apply only the scoped change against
  that fresh baseline. Recheck the baseline inside the write; if it changed,
  reread and reconcile the live Studio change, not an older repository copy.
- Do not bulk-push repository scripts, restore an old place/template, delete
  objects, or accept historical `pending-studio-push` flags as authorization.
  Never use Trello completion notes to infer what currently exists in Studio.
- Export verified Studio state to the repository, with exact paths, classes,
  source hashes, and relevant properties/assets recorded. Resolve source/editor
  conflicts before claiming parity. Preserve full native place backups for
  non-script data; a source-only mirror is not the whole game.
- Before reconciling a dirty/diverged checkout, preserve a recoverable local
  checkpoint. Keep remote-only documentation, tools, assets, and developer work;
  resolve runtime mirror differences from a fresh Studio export.
- **Commit all task changes** after inspecting the exact staged diff, including
  verified Studio mirrors, relevant asset/test records, and workflow updates.
  Do not blindly `git add -A`, include credentials/caches, or discard unrelated
  changes. Record commit IDs and distinguish local commits from a GitHub push.
  A commit requirement is not permission to force-push or rewrite history.

## Level 2 verification

- Check safe spawn distance from every living participant, the second distinct
  pump spawn, and the third distinct pump escalation of the same entity.
- Measure server CPU/memory and navigation/retry behavior under an active round;
  keep the work bounded and clean up round-owned tasks/connections on reset.
- Do not claim a gameplay, performance, or multiplayer check passed from source
  inspection alone. Report unverified checks and material blockers honestly.

## Publishing preference

The user instructed on 2026-08-31: always publish completed game changes.

- After implementing and verifying requested changes, publish the current Roblox Studio place to the existing experience: place ID `131311258779917`, universe ID `10559217407`.
- Verify Roblox reports a successful publish before claiming changes are live. Merely saving in Studio or updating this repository is not publication.
- Do not publish when checks identify a material blocker; explain the blocker instead.
- This publishing preference does not authorize publishing unrelated places,
  changing access settings, or restarting active servers. The owner's newer
  instruction above separately requires commits of task changes; committing is
  not the same as pushing to GitHub or publishing the Roblox experience.

These instructions supersede older README, CLAUDE, handoff, tool, or Trello
directions that would let repository data overwrite the authoritative Studio
state.
