# Setup verification — 2026-10-10

Current checkout: `/Users/zeanjuul4/Projects/stayquiet-poolrooms-audio-20261009`.
Branch: `codex/poolrooms-audio-20261009`; baseline HEAD: `280748b0fe7c1296e4f05c73013101bc302b1d21`.
The Documents/Roblox Horror REPO alias points to the older main checkout.
MonoCode now has the audio checkout open as its own project.

## Machine and installed tools

MacBook Air M1 (MacBookAir10,1), 8 GB RAM, arm64, macOS 15.6 (24G84).
MonoCode 0.7.0; Claude Code 2.1.296; Codex 0.162.1; Roblox Studio 0.742.0.7421053.
Existing provider logins, MCP servers, hooks, permissions and publication policy were retained.
No app restart, Studio write, playtest, asset upload or game publication was performed.

## Current defaults and launch chain

| Layer | Verified state |
| --- | --- |
| MonoCode project provider models | Audio checkout: Claude `opus`, Codex `gpt-6.1-sol`; saved in project scope |
| Ordinary fresh Claude session | Opus 5.5, Medium, Fast off; no Ultracode workflow |
| Ordinary fresh Codex session | gpt-6.1-sol, Medium, Standard; no delegated workers |
| `.claude/settings.json` | `model=opus`, `effortLevel=medium`, `fastMode=false`, `ultracode=false` |
| `.codex/config.toml` | gpt-6.1-sol, medium, `service_tier="default"`, agents disabled; one helper cap if explicitly enabled |
| Project launchers | Resolve checkout from script path, select Medium/Standard; `--low` selects Low |
| Old main checkout | Short redirect plus matching project configs; do current game work in audio checkout |

MonoCode 0.7.0 exposes project-scoped provider/model defaults, but its recent reasoning/speed selections are shared UI state. The Roblox sessions have their own saved Medium/Standard values. Check the picker before starting another ordinary UI session; use the project launchers for reproducible standalone jobs. Existing unrelated sessions and their saved model settings were preserved. Global Claude/Codex config files and MonoCode's global provider/model defaults were not changed.

Codex's installed model catalog maps `priority` to **Fast**. MonoCode's **Standard** selector saves `serviceTier=default`; Codex accepts `service_tier="default"`. Do not reuse older priority/Astra commands from historical records.

From any directory:

```sh
/Users/zeanjuul4/Projects/stayquiet-poolrooms-audio-20261009/tools/agents/start-codex.sh
/Users/zeanjuul4/Projects/stayquiet-poolrooms-audio-20261009/tools/agents/start-claude.sh
```

Use `--low` as the first launcher argument for known simple procedures. Codex's launcher rejects model/config/cwd override flags to prevent inherited launch commands reviving the old defaults. Explicit difficult-task settings can be chosen in the ordinary session picker, with a concrete reason recorded.

## Small sequential checks

1. Codex MonoCode smoke session `a95a615c-71f7-4d15-906c-8721d757bc46`, provider session `01a12607-6ea2-76c2-a412-504fc11239c3`: actual rollout cwd, model and effort matched. Saved settings were `reasoningEffort=medium`, `serviceTier=default`; shell confirmed the checkout, branch and 164-line guide. Finished in 13 seconds; 27K context shown.
2. Claude MonoCode smoke session `79164cea-05b2-4186-9f3c-057ea59da2d3`, provider session `330ab8c9-4159-4cac-ab68-e026b9200639`: actual process used `--model opus --effort medium` with project settings enabled. Transcript records `claude-opus-5-5`, effort medium, API speed/service tier standard. Finished in 7 seconds; 37K context shown.
3. Claude's actual instructions attachment contained only this checkout's 164-line CLAUDE.md and the main repository's 19-line auto-memory index. Worktree memory is shared with the main repository in this installed version. No ancestor guide or historical reference file was automatically imported.
4. Codex `config/read` returned the active project layer without a disabled reason: medium/default, agents disabled, one helper cap. Existing permission/sandbox defaults were inherited unchanged. `debug prompt-input` confirmed the local instructions and no imported archive.
5. Both Codex launcher prompt renders succeeded from `/tmp` (Medium and `--low`). A separate fresh CLI execution returned `SETUP_OK`; actual rollout cwd/model/medium matched. It made no tool calls or edits. Shell syntax checks passed for both launchers.
6. Original guide section coverage was retained in four reference files and the section index. Main guide reduced from 2,485 to 164 lines, about 95.5% fewer bytes. The references carry a historical-policy banner and have no automatic imports.
7. Studio MCP still lists `[UPDATE] BACKROOMS: STAY QUIET`, place `131311258779917`, instance `8ed31725-2418-46b9-90e9-6fac35eee0f2`; mode remains Edit. Sync script and manifest hashes still match HEAD.
8. The four pre-existing untracked audio-plan/installer files match checkpoint hashes. No game runtime mirror, geometry or audio file was changed by this setup work.
9. The existing sparse checkout now also includes `docs/reference`, `docs/workflow`, `tools/agents`, `.claude` and `.codex`; its original selection was backed up. No broad checkout expansion was used.

These checks verify the setup; they do not assert live/mirror parity or audio quality. Old main and audio history have different baselines, so do not bulk-sync either checkout.

## Checkpoint and current owner

Studio owner remains the paused **Main RBLX GAME DEV** Claude session, MonoCode ID `2c533cc4-9d71-43d0-bf98-a52b7b521b87`. Its saved future-turn setting was changed to Medium, Fast off; no active job was interrupted. Use a fresh ordinary session and the handover template if replacing its long conversation. Do not treat an old paused conversation's context as current defaults.

Recoverable setup checkpoint: `/Users/zeanjuul4/Projects/stayquiet-setup-backups/20261010/`.
It holds original guides, project session exports, memory copies, HEAD/status/diffs, untracked hashes and sanitized verification receipts. It is a local setup checkpoint, not a native Roblox place backup.
The only additional agent was bounded read-only verification; it had no Studio ownership or write access through the task instructions. No helper should remain running at handover.

## Next task

Read [next-level2-audio.md](next-level2-audio.md), reconcile the existing batches, choose 3–5 examples, then upload/install/listen to that pilot before expanding it. This setup task has saved the order; it has not begun audio production.

## Settings sources checked

- [Claude settings scopes](https://code.claude.com/docs/en/settings)
- [Claude model/effort and Ultracode](https://code.claude.com/docs/en/model-config)
- [Claude Fast mode](https://code.claude.com/docs/en/fast-mode)
- [Codex speed](https://learn.chatgpt.com/docs/agent-configuration/speed)
- [Codex subagent settings](https://learn.chatgpt.com/docs/agent-configuration/subagents)
- Installed CLI help, app-server protocol schema and model catalog were also checked; local effective receipts take precedence over historical examples.
