# Level 5 local audio draft — 2026-09-27

Status: source-only draft compiled and mocked; no Studio or production-repository changes by this subagent. Asset IDs are intentionally zero until root imports the selected ElevenLabs takes and grants experience access. Zero, missing and unloaded assets stay silent.

## Intended destinations

| Draft under `patches/` | Studio destination |
| --- | --- |
| `Level5AudioCatalog.ModuleScript.lua` | `ReplicatedStorage.Level5AudioCatalog` (new ModuleScript) |
| `Level5AudioLogic.ModuleScript.lua` | `ReplicatedStorage.Level5AudioLogic` (new ModuleScript) |
| `Level5SoundController.LocalScript.lua` | `StarterPlayer.StarterPlayerScripts.Level5SoundController` (new LocalScript) |
| `Level5ColourLockClient.LocalScript.lua` | Existing `StarterPlayer.StarterPlayerScripts.Level5ColourLockClient` |

The existing client is an exact fresh-baseline copy plus three added lines: one local BindableEvent beneath its owned GUI, one click event after a wheel changes, and one reject event on a nonce/gate-matched server result. The exact diff is `patches/Level5ColourLockClient.audio.diff`. No remote, answer, cursor, layout, server progression or gameplay change is made.

## Behavior and ownership

- Twelve reusable Sounds, three looping and nine one-shot voices. Five positional voices each have one invisible local emitter. The hard budget is at most sixteen voices; this catalog uses twelve.
- Sounds live under SoundService and invisible emitter Parts under the local CurrentCamera, never inside the generated world. This avoids adding to the near-limit generated-world descendant count.
- Ambient room hum follows `Level5OutageLogic.AmbientPower` and the authoritative H/chute exemption bounds. A–G fade toward blackout room tone over the same five-second fall, remain black for the schedule's sixty seconds, and recover with the same lighting transition. H retains normal hum. Missing exemption metadata follows the lighting owner's conservative exempt policy.
- Power fall/restart sounds run on observed phase transitions. Joining a world or walking out of H during an already-running phase does not replay its start. A new outage cycle is distinguished by `startedAt`, so an extended blackout does not replay collapse.
- Gate sounds watch the seven owned gate models' `Unlocked` false-to-true changes. Initial true state, replacement streamed models, world replacement and round entry establish a baseline without playback. The lock and sliding mechanism are positioned at the padlock and have bounded audible ranges. Solved gates add the unlock cue; developer bypass plays only the door. Because the server writes `Unlocked` before `OpenReason`, a real opening edge starts the slide immediately and retains a same-model pending unlock cue for at most one second while the reason replicates. This bounded state cannot transfer to a replacement model or replay an initial unlocked snapshot.
- Window Watcher reuses the owned actor SHA/flags and the existing client's 10 Hz gaze diagnostics. The diagnostics must match the current appearance number and come from a live, enabled LocalScript without `GazeError`. Heartbeat intensity and speed follow eligible visible gaze; LOS loss, hidden state, menu/modal/text focus, non-custom camera, failed/disabled/removed gaze owner and invalid participant state silence it at the next controller update (at most the normal 0.1-second update interval). Glass, close breath and gaze-disappearance cues are each at most once per appearance; natural timeout/stream-out does not fake a disappearance. A cue is consumed only when the actual emitter satisfies the same loaded-asset, distance and cooldown predicate used by playback, so seeing the actor beyond the glass/breath audible range does not discard a later cue when approaching.
- Existing SoundController footsteps and flashlight sounds remain owned by that script. No double-playing replacements are introduced.
- Death, spectating, escape, round/lobby changes, world removal and script destruction release every owned Sound/emitter. Camera replacement recreates the bounded pool while retaining gate/watcher event history.
- Playback does not wait for downloads. A missed one-shot is not queued for delayed replay. Loops can begin after loading finishes.

Diagnostics on `Level5SoundController`: `AudioActive`, `AudioVoiceCount`, `AudioLoadedCount`, `AudioPhase`, `AudioExempt`, `AudioWatcherIntensity`, `AudioCueCount`, `AudioLastCue`, `AudioError`.

## Checks completed

All four draft Lua scripts compiled with the existing Luau compiler.

`tests/test_audio_logic.luau`: **218 assertions passed** for asset validation/placeholder silence, all seven gate baselines and edges, outage/H/no-entry replay, and watcher appearance/visibility/LOS/modal/hidden/streaming state. Regressions include split gate-attribute replication in server order, bounded pending-reason expiry/replacement/bypass and cue eligibility after approaching from outside audible range.

`tests/run_controller_mock.py`: **125 assertions passed** against the actual controller source concatenated into a minimal Roblox presentation mock. It exercises real pool construction, sound playback state, GUI cue filtering, outage transitions/H exemption, death/lobby cleanup, solved-gate entry, watcher LOS/menu/hidden gating, appearance-once behavior, camera replacement, world streaming, spectating and script destruction. It also checks that no audio object is parented beneath the generated world. Regressions explicitly run an update between the server's `Unlocked` and `OpenReason` writes, approach a Watcher from 100 to 70 studs, distinguish nominal gaze distance from actual emitter distance for breath, expire delayed gate reasons, and stop every Watcher voice when the gaze owner errors with stale positive diagnostics, is disabled, or is destroyed.

Commands from project root:

```sh
output/level5-build/tools/luau/luau output/level5-audio-qa-20260927/tests/test_audio_logic.luau
python3 output/level5-audio-qa-20260927/tests/run_controller_mock.py
output/level5-build/tools/luau/luau-compile --null output/level5-audio-qa-20260927/patches/*.lua
```

The mock substitutes valid loaded asset IDs; it cannot establish Roblox moderation/permission, audible quality, spatialization or real engine playback. It is not a Studio runtime pass.

## Required integration/runtime checks

1. Compare live Source/editor to the fresh baseline immediately before applying the three-line existing-client diff. Create the two modules before the controller; root owns the Studio import.
2. Replace catalog zeros only with selected, uploaded, experience-permitted assets. Confirm `AudioLoadedCount == 12` after preloading. Keep zero for any asset that is not ready and report it honestly.
3. Audition every cue at the configured quiet volumes, normal and maximum normal player volume. Check loop seams and heartbeat timing; no abrupt jumpscare or excessive low-frequency rumble.
4. Match sliding-door foley to the actual **1.6-second** server tween (`Level 5 Section Progression`, line 176). The current four-second catalog duration is an upper lifetime, not a speed change; use a shorter movement plus settling tail or update duration to the selected take. The three-second power-return cue may similarly contain a soft tail after 1.5-second light restoration.
5. Native play: click a wheel, reject an answer, solve each gate, stand near/far from a gate, join an already-open gate; verify spatial range and no replay. Test mouse/touch/gamepad activation without changing cursor handling.
6. Observe A–G five-second fall, sixty-second blackout and recovery; H and chute stay normally lit/voiced, including crossing their bounds during the outage. Gate 7 must not schedule a fresh outage (existing server restriction).
7. Observe a real Watcher appearance through its selected window; approach from beyond 85 studs, lose LOS behind a wall, open the lock/menu, force normal hidden threshold, wait for natural timeout. Audio must stop with permission/LOS/hidden loss, without duplicate apparition/vanish cues. In a disposable Studio test, set a diagnostic `GazeError`/disable the gaze owner while positive diagnostics remain and verify all four Watcher voices stop; remove the test fault afterwards.
8. Death, lobby, spectating, new round, world streaming and camera replacement: zero leaked voices/emitters and never more than twelve current voices. Check Output and `AudioError` remain clear. Confirm no change to generated-world guard count, existing footsteps or flashlight playback.

All sections/puzzle source assessment and historic-vs-current limits remain in `qa/puzzle-source-audit.md`.
