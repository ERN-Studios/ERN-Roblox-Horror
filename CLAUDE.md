# BACKROOMS: STAY QUIET — operating guide

Owner-approved setup policy, 2026-10-10. Read AGENTS.md too.
This replaces historical model, workflow, ownership and test defaults.

## Start in the right checkout

- Checkout: `/Users/zeanjuul4/Projects/stayquiet-poolrooms-audio-20261009`.
- Branch: `codex/poolrooms-audio-20261009`.
- The Documents/Roblox Horror REPO path is a symlink to the stale main checkout.
- Use the audio checkout for current game work; do not edit main's runtime mirror.
- Confirm pwd, git status, branch and current remote history at task start.
- Preserve dirty files and other developers' results before reconciliation.
- Delegate Codex through `tools/agents/start-codex.sh`.
- Standalone Claude starts through `tools/agents/start-claude.sh`.
- Both launchers resolve this checkout and select Medium/Standard by default.
- Preserve checkpoints before replacing long sessions with fresh context.

## Studio is the sole source of truth

- Existing place: `131311258779917`; universe: `10559217407`.
- GitHub, Trello, historical notes and script mirrors are downstream records.
- Never overwrite Studio because the repository or a pending flag differs.
- Studio is reachable on this Mac through the installed StudioMCP bridge.
- Bridge: `/Applications/RobloxStudio.app/Contents/MacOS/StudioMCP`.
- Select the intended Studio instance from its connection list before reading.
- MCP names may be roblox-studio in Claude and Roblox_Studio in Codex.
- Remote/cloud access depends on the actual bridge, not just operating system.
- This guide does not authorise bulk pushes, old-place restores or other places.

## One owner and at most one helper

- One named agent owns Studio writes, playtests, keys, installation and publish.
- Current owner: paused MonoCode session `Main RBLX GAME DEV` (Claude).
- It keeps ownership until a recorded handover; setup checks do not take it over.
- At most one extra agent may work concurrently on one isolated deliverable.
- Subagents, CLI jobs, workflows and Operator workers count toward this limit.
- Helpers do not alter shared Studio or start further agents.
- Every task has one owner who integrates and verifies its own result.
- Claude may remain Studio owner with capacity and working tools.
- Codex handles scoped code, installers, audio processing, Blender and assets.
- Codex can own Studio after a clear handover and verification of its access.
- Delegate or request another model's review only for a concrete reason.
- No compulsory Codex share in every batch; no compulsory Claude final QA.
- Ordinary sessions are the default; automatic Ultracode/workflow teams are off.
- Operator may run one bounded helper if supported; it is not a standing team.
- Preserve unknown sessions. Never stop processes by name alone.

## Model settings

- Claude: existing Opus (`opus`, currently Opus 5.5), Medium, Fast off.
- Codex: gpt-6.1-sol, model_reasoning_effort=medium, Standard.
- Known simple procedures may use the launchers' --low option.
- Raise reasoning for a concrete difficult task, then return to defaults.
- Do not hardcode ultra, xhigh, ultracode or priority into routine launches.
- Installed Codex catalog labels service tier priority as Fast.
- Standard is explicit service_tier=default; verify effective job metadata.
- Project settings/launchers override inherited global defaults.
- Preserve credentials, permissions, sandbox and publication policy.
- A config edit does not prove a running session adopted the setting.
- Check fresh job metadata and exact start flags after relevant changes.

## Safe Mac synchronisation

- Before a game edit, read the exact live source and relevant editor state.
- Preserve a scoped recoverable checkpoint before reconciling dirty work.
- mac_pull_from_studio.py --audit is preliminary drift discovery only.
- Its equal-length ASCII shortcut can miss edits; it does not prove parity.
- Compare exact live sources/hashes for the files involved in the task.
- mac_merge_push.py [--dry] <file>... does scoped three-way merging.
- Baseline: last pushed copy or HEAD; third side: freshly read Studio source.
- Writer checks the baseline inside ScriptEditorService:UpdateSourceAsync.
- Preserve compare-and-swap, compilation and complete source readback.
- Resolve live/editor conflicts against fresh Studio state before writing.
- Read live .Source through execute_luau; script_read can expose a stale buffer.
- mac_record_synced.py <file>... records only exact matches to Studio.
- Preserve these tools and studio-sync-manifest.json; do not weaken guards.
- mac_push_script.py and old Windows commands are legacy paths, not defaults.
- Pulling cannot write Studio but can replace local mirror files; inspect first.
- A script export is not native recovery of geometry, assets and properties.
- Owner forbids leaving large native place backups on this nearly full Mac.
- Use an agreed existing native-recovery route; ask if none is available.

## Small tasks and handovers

- Use docs/workflow/delegation-template.md for one concrete deliverable.
- State goal, expected result, relevant files and exact starting baseline.
- Include observations, attempts, required checks and current Studio owner.
- Helpers save findings progressively to their own task notes.
- Review changed files and relevant dependencies, not the entire repository.
- Use early client/server logs and measurements to test leading hypotheses.
- Save evidence during work; session limits must not erase the whole result.
- On a provider limit, checkpoint and finish independent work with available tools.
- Transfer Studio only after the previous owner is idle and checkpoints saved.
- Record new owner, instance/mode, pending edits and next concrete check.

## Verification proportional to the change

- Separate source inspection, offline checks, Studio checks and Roblox-client checks.
- Compile edited Luau and run relevant existing tests; avoid irrelevant repeats.
- After Studio writes, compare the full source readback to the intended result.
- Gameplay changes need focused playtests and client/server Output logs.
- Performance claims need frame-time, CPU, memory or loading measurements.
- Visual map QA uses the player's view and real movement, not a parked camera.
- Solo Studio has client/server simulations; it is not multiplayer verification.
- Server & Clients supports local multiplayer; start with two clients on this Mac.
- Device Simulator tests layout/input; real device performance is a separate check.
- ForceTouchUI is a project fallback for observed older simulator behaviour.
- Do not restart Studio or change beta/security settings for setup checks alone.
- DataStore tests are possible with API access in a separate test universe.
- A second place in the production universe still shares production DataStores.
- Never enable production DataStore writes to make a test pass.
- Studio MemoryStore test data is isolated from production.
- Actual teleports/reserved travel need a published experience and Roblox client.
- DevLiveLevelServer simulates local logic, not real cross-server journeys.
- Restore temporary DevLiveLevelServer, DevLeaderboardDemo and ForceTouchUI flags.
- See docs/workflow/testing.md for the precise limits and official sources.
- Disclose material blockers and unverified checks; source review is not gameplay QA.

## Existing safety, assets and publication preferences

- Do not remove/move world objects without owner-requested scope and decisions.
- Do not clean ServerStorage.Archive or other developers' recovery data.
- New maps and props use Blender and retain their authoring .blend file.
- Use detailed PBR where appropriate; resolve overlapping geometry first.
- Ask before more Meshy credit spending under the existing owner rule.
- Do not reuse another level's entity sounds as placeholders.
- Engineer quiet audio against AI static and abrupt audible cuts.
- Silent logic tests mute a SoundGroup; forcing all Sound.Volume=0 breaks state.
- UI actions use authorised app-bound tools and current UI observations.
- Existing hands-off/frontmost safeguards still apply to real Studio keys/clicks.
- This setup permits MonoCode operation; it does not waive unrelated GUI safeguards.
- Publish completed verified requested game changes under AGENTS.md's policy.
- Material blockers prevent publish; saving, committing and publishing are distinct.
- Verify successful publish and the newest published version where accessible.
- A toast or asset Updated timestamp alone can mislead.
- Publication preference does not authorise server restarts or access changes.
- Workflow/documentation-only changes do not require publishing the game.

## Commits and completion

- Commit only this task's reviewed project changes after exact staged-diff review.
- Never blindly git add -A in a shared checkout.
- Keep credentials, caches and other people's pending assets out of the commit.
- Do not force-push, rewrite history or merge an unrelated dirty checkout.
- State commit IDs and whether GitHub push/Roblox publish actually happened.
- Complete means relevant checks passed and the evidence is saved.
- Save a short handover with remaining checks instead of loading all history.
- Next audio task: docs/workflow/next-level2-audio.md.

## Read details only when needed

- docs/workflow/setup-verification.md: effective setup and verification receipts.
- docs/workflow/delegation-template.md: bounded job and ownership templates.
- docs/workflow/testing.md: test matrix and official Roblox sources.
- docs/reference/levels-and-runtime.md: dated level details and historical fixes.
- docs/reference/audio-and-assets.md: retained sound, art, upload and promo records.
- docs/reference/sync-and-tools.md: old bridges and tooling history.
- docs/reference/workflow-and-history.md: earlier batches and historical house rules.
- docs/reference/original-section-index.json: original sections and line ranges.
- tools/*/README.md: specific Blender, sound, mobile and installer procedures.
- Original CLAUDE.md and memory backups are outside the repository.
- Do not @import these detail files or load the whole archive at startup.
- Historical model commands/test limits are superseded by this guide.
