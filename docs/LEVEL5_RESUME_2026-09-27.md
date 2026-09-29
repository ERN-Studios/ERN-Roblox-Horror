# Level 5 resume checkpoint — 27 September 2026

## Latest checkpoint — lobby access closed, v2157

Read [LEVEL5_OPENING_QA_2026-09-27.md](LEVEL5_OPENING_QA_2026-09-27.md) and [LEVEL5_FINAL_AUDIO_2026-09-27.md](LEVEL5_FINAL_AUDIO_2026-09-27.md) before the historical notes below. **The owner requested Level 5 closed to everyone.** Both public and developer flags are false; its lobby door is sealed and all four stations are offline. Final publication v2157 is verified. Existing running servers need a restart, requested from the owner because Creator Hub browser access is unavailable. The residential bay styling, disabled outages and B clue visibility fix remain. Before closure, a fresh native desktop run solved A–G with real wrong/correct inputs, walked the F recovery route and H descent, and returned to the lobby with cleanup. H still lacks slide/completion. Sixteen cleaned active WAVs are in `~/Downloads/Level 5 Final Sounds - Cleaned` for manual upload; no new audio IDs or hooks are installed. Do not regenerate them. The final native place download remains blocked by macOS Save; a verified prechange full recovery file and fresh source/property records are preserved.

The following text is the earlier checkpoint; its publication and blocked-QA statements are historical.

---

**Audio is still not uploaded, installed or published. No live game scripts were changed.**

## Fresh authoritative state

Studio was not running when this task began. Opening the installed app restored the correct experience in Edit mode: place `131311258779917`, universe `10559217407`, group owner `1039373905`. Studio reports **place version 2149**, and its new startup log also reports 2149. This is a newly observed current-place version; it is not a publication receipt for this task. The prior Level 5 publication receipt remains v2143.

The full read-only export contains **197 scripts**, with no Source/editor differences. All 197 Source hashes match the preceding audio-task checkpoint. All 193 scripts represented in the production repository mirror match live Studio. Four existing Level 6 scripts remain preserved in the fresh export: Expansion, Generator, PreviewAccess and PreviewPrompt. Nothing was restored from an older place file or bulk-pushed into Studio.

Compact evidence: [comparison](../artifacts/level5-resume-20260927/comparison.json), [full source index](../artifacts/level5-resume-20260927/source-index.json), [Level 5 index](../artifacts/level5-resume-20260927/level5-index.json). Full Source and editor-source copies remain locally at `../level5-resume-20260927/baseline/`, relative to the repository directory.

Git began clean at `fbec7e30513c91a8f53de6a305722b64b0441ec8`; origin and PR #10 had that same head. PR #10 is open against `codex/level5-qa-exit-polish`.

## Audio verification and scoped draft fix

All twelve existing WAVs match the saved manifest's hashes, bytes and durations: mono, 44.1 kHz, 16-bit PCM, 4,515,012 total bytes. No sounds were regenerated.

The draft controller cleared its Sound pool but left `AudioLoadedCount` at the prior value. Its cleanup now resets that diagnostic to zero. Two assertions check the active loaded count and the count after death cleanup. **218 pure logic assertions and 127 controller mock assertions pass; all four draft scripts compile.** These are offline tests with substituted loaded asset IDs, not native audio or gameplay evidence.

The existing four-second gate WAV still needs audible timing review against the actual 1.6-second gate tween. Its strongest peak is around 2.55 seconds. A timing candidate derived from the existing recording is separate from the original ready assets and must not silently replace the manifest-selected file. No claim about the sound's subjective quality is made.

## Current practical blockers

- The authenticated Creator Dashboard displays the correct **ERN Roblox Studios** owner. Native Chrome repeatedly changes active tabs while actions are pending; the direct Chrome tab connection fails during initialization. No file selection or upload succeeded. Neither supported Roblox upload environment variable checked in this process is configured. No credentials or browser cookies were extracted.
- Studio's **Download a Copy** dialog has a disabled Save button, including after selecting the new backup directory and Downloads. Cancel and later native UI reads timed out. Neither requested backup file exists. The fresh source export is therefore **not a complete native place backup**.
- No Play session was started in this resumed task. The previous entry-readiness timeout remains historical evidence, not a reproduced result today. Normal readiness and script timeouts were not changed.

The user was asked only to leave Chrome available for the upload and close the stuck Studio dialog. No assumption is made that the Mac is locked or that its memory pressure is the cause.

## Playability status

| Section | Current assessment |
|---|---|
| A | Same four-house colour puzzle; fresh native walk and wrong/correct input still unverified. |
| B | Same symbol puzzle and offset route; fresh native traversal/input unverified. |
| C | Same three address clues, printed 2/6/4; discovery distance and native traversal/input unverified. |
| D | Same switches and two street heights; native stairs/input unverified. |
| E | Same clocks and domestic passages; native collision/input unverified. |
| F | Same 28-point main route, clue detour and 12-point recovery route; fresh native checks unverified. |
| G | Same western clue house and arrow puzzle; native detour/terraces/input unverified. |
| H | Current source still explicitly marks geometry only, with no finale puzzle, sliding or completion. |

Source parity preserves the scope of the earlier audit; it does not convert historical native results into fresh passes. Outage timing/H exemption, Watcher visuals and audio, cursor behavior, performance, multiplayer and physical mobile checks remain open as recorded in the full handover. Developer-preview restrictions remain intact.

## Resume actions

After the two UI surfaces respond, save a full current native backup; finish audition and gate timing; upload the existing cues under the verified group and record IDs/permissions. Re-read live Source/editor immediately before applying the new audio modules/controller and the scoped three-line padlock-client integration. Then run the real A–G puzzle inputs/routes, F recovery, H exemption and Watcher/cleanup checks. Publish only completed, verified changes without a material blocker.
