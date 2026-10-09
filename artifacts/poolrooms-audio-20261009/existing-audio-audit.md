# Poolrooms audio audit — 2026-10-09

Scope: read-only repository audit and an isolated mathematical negative control. No Studio writes, asset upload, generation, publishing, Git reconciliation, or edits to existing files were performed. Nothing was auditioned; no gameplay or listening result is claimed.

## Availability

The existing tools expect `assets/level2-poolrooms-20261008/plan.json`, `sound_ids.json`, and batch folders containing `raw`, `jobs.json`, `clean`, and `levels.json`. That entire folder is absent from this checkout. Targeted recursive file searches of Documents and Projects, and targeted searches of Claude and Codex logs, found no Poolrooms generation manifests, take names, or processed assets. Duration, loudness, static, loop-seam, and decay quality of the requested Poolrooms recordings therefore cannot yet be verified from local audio.

The available `artifacts/level2-ambience-20261008/map.json` is explicitly an October 8 Edit-mode survey of a developer preview, with no walk or listening verification. It is historical context; it cannot establish the current live level or audio inventory.

Its historical `ReplicatedStorage."Level 2 Sound Library"` contained:

| Name | Asset ID |
|---|---:|
| Level 2 Room Tone | 75214252175039 |
| Level 2 Water Drop | 116103446006735 |
| Level 2 Drain Gurgle | 105244893367809 |
| Level 2 Pipe Groan | 116707880665577 |
| Level 2 Distant Monster-Like Pipe Groan 1 | 93723101231893 |
| Level 2 Distant Monster-Like Pipe Groan 2 | 87666542035440 |
| Level 2 Distant Monster-Like Pipe Groan 3 | 120532580680571 |
| Level 2 Distant Monster-Like Pipe Groan 4 | 95187342487142 |
| Level 2 Pressure Door | 113402173976510 |
| Level 2 Pump Start | 105491305106437 |

These IDs do not establish ElevenLabs provenance, content quality, or installation in the new level. The historical survey had an empty Distant Water slot, and no Sound instances in the Edit-mode map.

## Existing playback design

The local untracked `StarterPlayer/StarterPlayerScripts/Level 2 Poolrooms Ambience.LocalScript.lua` describes three client-local layers: section-based stereo beds, fixed spatial machinery/water loops, and weighted spatial random events. It reads `ReplicatedStorage.Level2Poolrooms.{Plan,Sounds}`. The authoritative Studio copies and current runtime plan must be read before adopting any part of this source.

The source supports areas S/P0/A1/P1/A3/P2/A4/P3/A2/P4/A5/P5/A6/EXIT through a historical map origin and Collision `Area` values. Random events have a 70-second repeat guard and a maximum of three concurrent events. Local bed/loop fade constants exist.

The historical map supports distinct acoustic identities: dry arrival/changing rooms; wet vaulted cistern with pump house; narrow concrete service stairs; giant nave with weir/pump bay; spillway cascade; enclosed ascending stepwell; low vent passage; domed rotunda with lion spouts/bronze disc; wood/brass lockers; empty competition pool hall; close door corridor; dry multistorey door atrium. This describes a sensible plan, not current installation.

## Playback problems that can defeat smooth exits

1. `setActive(false)` immediately unparents the entire world emitter folder (`world.Parent = on and workspace or nil`, line 295). Spatial loops and live events leave the rendered world before their volume can fade. Bed and loop gain processing later in Heartbeat does not repair that abrupt emitter removal. Keep emitters parented until their exit envelopes complete, and fade already-active events on exit, death/reset, or spectator changes.
2. `fire()` immediately assigns final event Volume and calls Play. There is no playback envelope for random events. File fades are therefore the only startup/ending protection during normal playback; cancellation has none.
3. A fixed 40-second timer destroys every event emitter, starting before playback is confirmed. The existing generator brief caps takes at 22 seconds, so normal preloaded events should finish first; delayed loads or later longer assets require a load-aware lifetime. Timeout handling should not stop a still-audible sound abruptly.
4. Loop/floor objects are created once and retain their initial positions. If live model origin changes or a round model is replaced, fixed loops need their positions refreshed or safely recreated against that new origin.

## Existing cleaner and measurement weaknesses

`tools/audio/clean.py` already offers narrow-tone shaving, static-print/haze reduction, spectral low/high-pass filtering, loudness targets, waveform-preserving limiting, OGG loop exports, circular loop filtering, and a tail/head crossfade. Those are useful building blocks.

However:

- Default one-shot fade-in is only 8 ms and fade-out 120 ms (lines 145–148). They protect waveform boundaries from clicks but do not guarantee a natural environmental swell and reverberation decay. Exposed distant events generally need take-specific starts and longer tails. Preserve real impacts; do not erase a drip or a knock's intended transient.
- The automatic verdict ignores `join_step_vs_diff_rms_db` despite measuring it. All other seam metrics in `measure.py` also have no acceptance rule in `clean.py` (lines 159–185). A bad seam can pass the existing numeric report.
- `tones_over_1k` counts only the eight peaks retained in `peaks_over1k_top`; it is not a count of every audible tone. Stronger inaudible high-prominence peaks can crowd audible peaks out of that list.
- The hiss threshold measures energy only above 1.3 times the selected low-pass cutoff. Audible broadband static below that cutoff can pass. Tonal shaving does not identify that broadband static.
- Beds/loops default to no static-print gate or haze processing. This may preserve intended water texture, but it means the default pipeline cannot guarantee clean quiet recordings merely from its current thresholds. Broad noise in water or ventilation can be legitimate, so compare raw/clean at matched loudness and judge per take rather than apply a destructive hard gate globally.
- The final `peak` field is a decoded sample peak, not a true-peak measurement. Loudness and peak checks should happen after final lossy encoding. A representative final clip should also be checked through Roblox's actual decoder and mix.

The isolated `check_existing_seam_verdict.py` constructs a 137 Hz signal in memory whose boundary step is **36.11 dB above its ordinary adjacent-sample difference RMS**, then supplies plausible non-seam fields directly to the existing verdict function. The existing verdict returns no faults. This is a verified unit-level negative control for the missing seam criterion, not a measurement or audition of any game audio.

An optional ffmpeg render of that synthetic control failed with `Operation not permitted` when writing directly into the repo. No output WAV was produced and no permission was requested for this nonessential render. The successful control uses in-memory math only.

## Recommended acceptance before installation

Recover/download the actual live sounds or generate replacements only after inspecting the live inventory. Keep raw source, exact prompts/generation metadata, selected take, processing parameters, final hash, duration, LUFS, decoded and true peak, and upload ID together.

For every loop, decode the final uploaded-format asset; verify boundary waveform step, seam high-frequency energy against ordinary audio, level continuity, and repeated playback. Continuous ambience should crossfade cyclically rather than dip to silence at every loop boundary. Apply a smooth runtime gain envelope when that loop starts or is cancelled.

For one-shots, preserve sufficient decay and bake a smooth take-specific tail. Check the first and final short windows against body level after encoding. Also implement cancellation fade-outs independently of natural Ended events.

For quiet sounds, compare noise-floor spectra at equal loudness, examine tonal and broadband residues, and audition high-gain quiet passages for metallic/warbling denoiser artefacts. Numeric thresholds alone cannot establish the user's requested absence of audible AI static.

Verify loading, random scheduling, section transitions, teleports, reset/death and spectator changes in active gameplay. Do not claim those checks from the present source audit.

## Audited local source hashes

| File | SHA-256 |
|---|---|
| tools/audio/clean.py | 436a852bd472107bdacfffa7d20a9d5eb840ccc83242d720cc95d431f124e1b4 |
| tools/audio/measure.py | 6f940898753fcadf7478e3276728fb405ba0080385712748d55e3222037419bd |
| tools/level2_poolrooms/install_sounds.py | 9b9aba0b07fabe993527055593df7f444ae2965c9a770871523eb5a44558c86c |
| local Poolrooms ambience client | aea7266f039912ffd4e62de43640e93b58bbfcc67fc7fd0ed543e126887f3b07 |
| historical map.json | cd26df9de71a38fdffb66cccf5fdba7607323e903818959760973a9af5ef5aee |
