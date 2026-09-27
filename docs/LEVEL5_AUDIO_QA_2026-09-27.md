# Level 5 QA and ElevenLabs audio checkpoint — 27 September 2026

Artifact root: [`artifacts/level5-audio-qa-20260927`](../artifacts/level5-audio-qa-20260927/README.md). Paths and commands below are relative to that directory.

**Prepared, not installed or published.** Twelve original sound cues are generated and technically validated. Roblox upload is still zero; every draft catalog AssetId is deliberately zero. The production Studio scripts and repository runtime mirror are unchanged by this task.

## Playability assessment

| Section | Puzzle | Assessment in this audit |
|---|---|---|
| A | Four ordered colours in four houses | Clues, solution and retry logic are consistent. Fresh native route/input check blocked. |
| B | Three household symbols | Consistent; short clue-copy puzzle. Fresh native check blocked. |
| C | Three coloured house numbers | Consistent. Widely separated clue houses make searching longer than the other puzzles. |
| D | Three switch positions | Consistent. Both street heights and connecting stairs need the fresh walk check. |
| E | Three clock times | Consistent, with text supporting clock faces. Fresh native check blocked. |
| F | Three TV channels in the residential atrium | Consistent. Main route, clue detour and pit recovery require fresh traversal. Historical traversal is separately recorded. |
| G | Three house arrows | Consistent. The western ground-level clue house is a substantial detour. |
| H | Exit court and descent | Geometry is present, but no completion/slide gameplay is implemented. The whole level is not approved as completable. |

The seven definitions passed 6,910 assertions, including all 2,185 combinations. Existing layout arithmetic passed 2,737 assertions over seven puzzles and nine modeled viewports; a 244-pixel usable-height case remains a known limit. These are source/math checks, not native device or gameplay passes. See `qa/puzzle-source-audit.md` for exact solutions and route staging positions.

## Audio ready for import

`audio/ready/` contains twelve mono 44.1 kHz, 16-bit WAVs: normal room hum, blackout room tone, puzzle wheel click, wrong answer, unlock, sliding gate, power failure, power restoration, Watcher glass, breath, heartbeat and disappearance. The 48 original MP3 variations are retained in `audio/raw/`. Exact hashes, durations, source generation IDs and mastering measurements are in `qa/ready-audio-manifest.json`.

Generated through the connected ElevenLabs MCP, flow `jjheL5GNVJdYYNrfs1E8`, model `eleven_text_to_sound_v2`. Technical checks pass; subjective audition, Roblox moderation/experience permissions and the in-game mix have not been verified. The current ready files total 4,515,012 bytes. Do not regenerate them to resume this work.

## Integration draft

`patches/` contains two new modules, a client controller and a three-line existing padlock-client integration. None is installed. The client has twelve reusable voices and five local emitters outside the generated world, retaining the 29,928/30,000 world budget. It follows A–G outages, keeps H/chute ambience normal, and gates Watcher audio by living participation, actual gaze visibility, range and healthy gaze ownership. Existing footsteps and flashlight sounds remain with their current owner.

Independent review found and fixed three draft bugs: split gate-attribute replication dropping the unlock sound, Watcher cues being consumed outside audible range, and stale gaze diagnostics continuing heartbeat after a gaze error. Updated tests pass 218 pure logic and 125 actual-controller mock assertions. All four draft scripts compile. Mocks substitute loaded audio IDs and cannot prove actual playback.

Run with an installed Luau executable:

```sh
luau tests/test_audio_logic.luau
python3 tests/run_controller_mock.py /path/to/luau
luau-compile --null patches/*.lua
```

## Current native blocker and preserved state

Two ordinary developer-preview start attempts timed out during this session. The second built the map and placed the character, then failed the shared entry-readiness deadline. No fresh complete seven-puzzle playthrough was achieved. Studio and the authenticated Creator Dashboard also repeatedly failed UI operations, preventing audio upload and native place backup. The host was under heavy memory/swap pressure; that is evidence of a constrained test environment, not proof of the exact cause. A possible avatar-preload readiness latch is documented for investigation, not claimed as the cause or patched speculatively.

Studio was returned to Edit mode. The temporary ScriptTimeoutLength diagnostic change was restored to its original 10 seconds. The fresh export contained 197 scripts with matching Source/editor text: 193 exactly matched the prior v2143 mirror, plus four concurrent Level 6 scripts preserved locally. The export is a source checkpoint, not a full native place backup. No restart, source rollback or public release was performed. Last verified live version remains v2143.

## Resume

1. Restore responsive, unlocked Studio and Chrome without losing unsaved Studio work. Save current Studio changes before any restart.
2. Upload the twelve ready WAVs under the verified game-owner context, grant usage to universe 10559217407, and record the real asset IDs. Do not install zero-ID drafts as completed audio.
3. Audition all cues, especially the gate's 1.6-second movement versus its four-second sound/tail. Fill the catalog, compare fresh Studio Source/editor, then apply only the scoped three-line padlock change and new audio owners.
4. Use `qa/client-entry-readiness-snapshot.lua` during any loading failure before cleanup. Run real A–G puzzle inputs and all required routes, F recovery, H exemption, Watcher near/far/LOS/hide behavior, and death/lobby cleanup. Confirm all twelve assets load and no leaked voices remain.
5. Export verified final Studio state, save a full native place backup, commit and publish only after checks pass. Full completion, performance, multiplayer and physical mobile validation remain separate open items.
