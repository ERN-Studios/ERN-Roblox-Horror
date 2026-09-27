LEVEL 5 — FINAL CLEANED SOUNDS

Upload the 16 WAV files directly inside this folder to Roblox.
Keep each filename so the asset IDs can be matched to the game.
Use the experience owner's account/group and grant the experience access.
Record the resulting IDs in UPLOAD_IDS.csv or send the IDs to Codex.

Every WAV is mono, 44.1 kHz, 16-bit PCM. All files passed format, hash,
clipping, peak and boundary checks. No new audio has been uploaded to
Roblox or installed in Studio. These are final prepared assets.

WHAT IS INCLUDED
- Room hum, puzzle click/reject/unlock: cleaned existing cues.
- Window Watcher glass/breath/heartbeat/recede: cleaned existing cues.
- Sliding gate: new 2.2-second cue; motion window 1.6 seconds plus tail.
- Wooden door opening and closing: two new cues.
- House wood creak, window-frame creak, curtain movement: new cues.
- Ceiling relay tick and subdued queue arrival bell: new cues.

Only room_hum and watcher_heartbeat should loop. All other top-level
files are one-shots. Use low in-game levels for ambience and tension cues.

INTEGRATION STATUS
The room/puzzle/gate/Watcher hooks exist in a prepared code draft that
has not been installed. The new wooden-door, house/window creak,
curtain, relay and queue cues are assets only; playback events still
need wiring. Every Roblox asset ID remains blank until manual upload.

DO_NOT_UPLOAD_NOW contains all three cleaned outage cues (outage is
being disabled) and the cleaned older 4-second gate alternative.
The new top-level L5_sliding_gate.wav is the intended gate version.

CLEANUP
Stationary broadband noise was reduced using measured quiet regions,
then cue-specific filters and gentle expansion. One-shot tails end in
25ms of exact digital silence. Loops use a 100ms cyclic join; this makes
them 0.1 seconds shorter than the previous WAVs. Intentional hum,
breath texture and heartbeat remain. Existing quiet files were not
boosted again to chase loudness. No destructive limiter was needed.

Technical checks and measured noise reduction are complete. A human
headphone/in-game listening review has not been performed; metrics do
not prove that every generated artifact is perceptually gone.

MANIFEST.json records source hashes, generation IDs, takes and settings.
VALIDATION.json records every delivered file's technical checks.
Reproducible scripts, receipts and all 32 new original takes are saved at:
/Users/zeanjuul4/.codex/.chatgpt-projects/g-p-6a72501f4e648191a4bd04f306d6606e/output/level5-final-audio-20260927
