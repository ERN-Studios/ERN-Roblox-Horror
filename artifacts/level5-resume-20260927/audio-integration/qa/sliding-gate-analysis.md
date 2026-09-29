# Gate cue timing analysis

Status: technical analysis only. No subjective listening or native Studio playback was performed. The candidate is not an adopted replacement.

The server currently opens each gate with a 1.6-second tween. The prepared catalog duration is four seconds; controller playback speed is one. Changing the catalog duration alone does not compress the WAV.

The original four takes were decoded to mono 44.1 kHz floats and measured in 20 ms windows. CSVs retain minimum/maximum waveform samples, RMS and peak for each window. Percentile timing and energy are objective measurements; they cannot identify which sound represents movement or the final stop.

| File | Strongest peak (s) | 99% energy reached (s) | Energy after 1.6 s |
| --- | ---: | ---: | ---: |
| sliding_gate__take01.mp3 | 1.975 | 2.661 | 74.8% |
| sliding_gate__take02.mp3 | 2.045 | 2.903 | 76.4% |
| sliding_gate__take03.mp3 | 2.550 | 2.682 | 33.3% |
| sliding_gate__take04.mp3 | 1.455 | 2.328 | 29.0% |
| L5_sliding_gate.wav | 2.550 | 2.682 | 33.3% |
| L5_sliding_gate_timing_candidate.wav | 1.615 | 1.700 | 22.0% |

All takes have appreciable energy after the tween. Take 4's strongest transient is earlier, but it still contains nearly 29% of its energy after 1.6 seconds. Switching takes solely by peak timing would not establish audible synchronization.

## Unreviewed candidate from selected take 3

The candidate keeps the selected take and makes no new sound generation:

1. Remove the first 0.20 seconds, which precede the main movement envelope.
2. Apply FFmpeg `atempo=1.4688917234` to compress time while preserving pitch.
3. Add a 5 ms input fade and 35 ms final fade; retain a 2.4-second total duration for the settling tail.

The strongest transient moves from 2.550 seconds to 1.615 seconds. The 15 ms deviation from the 1.6-second target is below the controller's nominal 100 ms sampling interval. The transient's role as a closing/settling event is inferred from the envelope and original cue brief; it requires audition. Time compression also changes texture and peak level, which must be checked by listening.

Candidate technical measurements: mono 44.1 kHz 16-bit PCM, 2.4 seconds, 211,758 bytes, true peak −6.12 dBTP, integrated loudness −25.76 LUFS. No extra gain was applied.

- Original ready WAV SHA-256: `fbaced6edc7c704c377f367723a368e98123f7cd99324b30dc31a8b4f92af9bc`
- Candidate SHA-256: `5b674f54af3f4801d34a70f88ca75214f6b62d601b68657b057e265d5482b553`

Exact processing command and original ElevenLabs generation ID are in `audio/candidates/sliding-gate-candidate-provenance.json`. Originals are unchanged. All draft asset IDs remain zero; the candidate is not installed or uploaded.
