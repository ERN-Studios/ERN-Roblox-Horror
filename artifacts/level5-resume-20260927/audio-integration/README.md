# Level 5 audio integration working draft — 27 September 2026

Status: prepared locally, not installed, uploaded or published. All catalog asset IDs remain zero. This working copy preserves the prior audio draft and adds one diagnostic cleanup fix; the separately derived gate WAV is an unreviewed candidate, not a replacement for the twelve ready WAVs.

## Code change and validation

`patches/Level5SoundController.LocalScript.lua` now resets `AudioLoadedCount` to zero in `destroyPool()`. Previously death/lobby teardown removed the Sounds but could leave a loaded count of twelve. Two assertions in `tests/controller_mock_suffix.luau` verify twelve loaded assets while active and zero after death. The regression fails the unfixed controller at the new death-cleanup assertion.

- `PASS audio logic: 218 assertions`
- `PASS real controller mocked lifecycle: 127 assertions`
- All four draft scripts compile with `luau-compile --null patches/*.lua`.
- Actual source mocks use loaded placeholder asset IDs. They do not prove native playback.

Run with the existing Luau runtime:

```sh
/path/to/luau tests/test_audio_logic.luau
python3 tests/run_controller_mock.py /path/to/luau
/path/to/luau-compile --null patches/*.lua
```

Exact changes and test records are under `qa/`. The generated controller test file is disposable and need not be committed.

## Existing gate audio analysis

See `qa/sliding-gate-analysis.md`. All four original MP3 takes, the selected ready WAV and the timing candidate were measured using 20 ms waveform/RMS windows. Existing originals remain unchanged. No new audio was generated.

`audio/candidates/L5_sliding_gate_timing_candidate.wav` derives only from the selected ready take. It is 2.4 seconds long and places its dominant transient at 1.615 seconds, near the server's 1.6-second gate tween. Its sound quality and the meaning of that transient have not been auditioned. Do not adopt or upload it automatically. Provenance and source/candidate SHA-256 hashes accompany it.

## Still required

Upload and grant the chosen twelve cues to universe 10559217407, fill real IDs, compare fresh live Studio Source/editor before applying the scoped three-line lock-client change and new audio modules/controller, then perform native playback and gameplay QA. If the timing candidate is accepted after audition, use its 2.4-second lifetime in the selected catalog. The working catalog deliberately retains the original four-second gate duration pending that decision.

A–G native puzzle/route QA, F recovery, H outage exemption, Watcher LOS/range/hide behavior and lifecycle cleanup remain unverified. H completion/sliding gameplay remains absent. No Studio baseline or publication claim is made here; last verified release remains v2143.
