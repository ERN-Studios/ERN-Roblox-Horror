# Level 5 final audio — 2026-09-27

The owner requested more ElevenLabs sounds, including doors opening, and cleanup of the generated static audible during quiet passages.

## Manual upload folder

`/Users/zeanjuul4/Downloads/Level 5 Final Sounds - Cleaned`

- **16 active WAV files** are directly inside the folder.
- **4 deferred WAV files** are under `DO_NOT_UPLOAD_NOW`: three outage cues and the cleaned older 4-second gate alternative.
- Upload the top-level WAVs, preserve their filenames, grant the experience access, and record the resulting Roblox IDs in `UPLOAD_IDS.csv`.

All 12 previously prepared sounds have cleaned derivatives. Their original files and the previous Downloads folder remain unchanged. Eight additional cues were selected from one authorized ElevenLabs batch of 32 takes: sliding gate, wooden door opening, wooden door closing, house wood creak, window-frame creak, curtain movement, ceiling relay tick and queue arrival bell. The new gate replaces the older gate in the active set and has a 1.6-second motion window followed by a settling tail.

## Processing and verification

Processing uses measured quiet regions for spectral noise reduction, cue-specific band limits, gentle downward expansion for one-shots, edge fades and exact silent tails. Intended room hum, breath texture and heartbeat remain. Existing cues were not boosted again to meet a loudness target. Loop joins use a 100 ms crossfade and are 0.1 seconds shorter than their previous WAVs.

For the nine existing one-shots, RMS measured over the same quiet regions fell **7.1–25.5 dB**, with a **median reduction of 11.0 dB**. These measurements describe technical noise reduction; they do not establish subjective sound quality.

Every delivered file is mono, 44.1 kHz, 16-bit PCM WAV. All 20 delivered hashes, formats, clipping checks, peaks and boundaries passed. One-shots start at zero and end with 25 ms of digital silence. The maximum measured oversampled peak is below -3 dBTP.

## Integration status

No subjective headphone or in-game listening review was performed. No sound was uploaded to Roblox and no new audio asset IDs or live audio hooks were installed as part of this work. Existing room, puzzle, gate, Watcher and outage integration remains a prepared draft. The new door, house/window, curtain, relay and queue cues are assets only until their playback events are wired.

## Repository record

[`artifacts/level5-final-audio-20260927`](../artifacts/level5-final-audio-20260927) contains the delivery folder, all 32 new raw takes, processing scripts, selected-take records, measurements, prompts and generation/session receipts. Signed media URLs and the Python environment are excluded. `repo-copy-validation.json` verifies the copy against the sanitized source record and verifies all delivered WAV hashes.

The audio asset record does not claim Roblox publication, native puzzle QA or live sound integration.
