# Native death-drop progress (read-only evidence)

First actual fuse pickup is recorded. A (-1) first sent E at the 14:58:42.317Z output checkpoint, but had **Triggered0 / carry0**. Keep this as failed input setup; root reports the camera was aimed away.

After the explicitly logged controlled view adjustment, the 15:00:19.813Z client output records **actual Triggered1, FUSES CARRIED 1, HP100, same character/round and Released=true**. Its own server-clock values show 1.79949 seconds from key-down start to the actual prompt event and 0.71701 seconds from that event to the carry-label readback. Log UTC and synchronized server-clock values are separate clocks.

Server setup records the initial two living participants, EntityPaused false→true (600-second cleanup timer), observed prompt Key1 and floor-checked approach. The initial pickup checkpoint preserves all 15 currently matched attributed records; no command echo is included. `collection-report.json` currently has zero parse/identity/read errors.

Death, ground drop, actual B recovery and normal cleanup are still pending. This is not feature acceptance; temporary AI pause, character positioning and camera aiming are controlled setup. Re-run the collector for subsequent marked outputs. Its writes remain local to this directory.

## Resumed state after the first attempt expired

The server logged AI-pause expiry at **15:04:56.828Z**, then Puzzle's actual **Player1 death** callback at **15:05:03.844Z**. Both lobby-avatar load attempts followed at 15:06:05.875/.880Z. These lines are preserved in `post-pause-lifecycle.json`.

The fresh `[DEATH_DROP_RESUME]` at **15:07:37.191Z** confirms both real players HP100/InRound=false at the lobby, no hand fuse visuals, RoundActive=false and Drops empty. `resume-lobby-checkpoint.json` preserves that exact record. This settles the previously unknown current state; it does not reconstruct the missed ground-drop or peer pickup. Subsequent controlled A/B queue placements at 15:09:03/04Z start a new attempt. They do not change the earlier attempt into a pass.

## Genarmeret normal runde — 17:11 DK

Serveren loggede ny helper og kontrolleret AI-pause kl. 15:11:14.064 UTC. Det faktiske før-snapshot kl. 15:11:14.077 UTC viser Level1/RoundActive=true, Player1 og Player2 InRound=true/100HP, ingen FuseHandVisual og ingen drops. De tidligere døds-/lobbyhændelser bevares som den afbrudte første opsætning. Dette nye checkpoint dokumenterer starttilstanden, ikke death-drop eller pickup.

Evidens: `rearmed-round-checkpoint.json`; løbende collector: 22 markører, 0 parse-/identitetsfejl ved denne læsning.
