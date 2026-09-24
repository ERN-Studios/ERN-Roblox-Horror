# Level 2 groan source and Studio state check — 24 September 2026

The four published groan asset IDs previously measured in `ReplicatedStorage/Level 2 Entity Audio Bank.ModuleScript.lua` are **Pool Foam** `Bank.Foam.Groan` clips, not the Pool Slide's distant or mouth groans. They were retrieved read-only through Roblox asset delivery. Each is a stereo 44.1 kHz Ogg file, exactly 8.0 seconds long. The numbers below apply only to those Foam files; they must not be used to judge Pool Slide voice balance.

| Asset | Peak dBFS | RMS dBFS | Last 0.5 s RMS dBFS | Samples above 0.99 |
| --- | ---: | ---: | ---: | ---: |
| 135741106151964 | −3.1 | −13.3 | −59.1 | 0% |
| 135920645468915 | −3.0 | −13.8 | −69.6 | 0% |
| 82575067339531 | −3.1 | −18.5 | −80.6 | 0% |
| 76676509241608 | −3.2 | −18.1 | −107.6 | 0% |

The Foam files have peak headroom and fade out; the first two average roughly 4.5–5 dB louder than the latter two. The active Pool Slide voice instead resolves the four `Level 2 Distant Monster-Like Pipe Groan` StringValues in `ReplicatedStorage["Level 2 Sound Library"]`. In the 24 September Studio Play session these were IDs **93723101231893, 87666542035440, 120532580680571, 95187342487142**. No file-level loudness measurement has been made on those four actual Slide clips.

## Disposable Studio Play: audio-state observations

Three solo Level 2 rounds were entered through queue station 5. The first showed an actual client-side `Level 2 Distant Pipe Groan Emitter` on generated corridor geometry, 97.8 studs from the player, with groan slot 4 loaded and `IsPlaying=true` while `Level2_PoolSlideActive=false`. Another pre-spawn round showed slot 1 at 98.1 studs. The four live sound-library slots were populated and the entity audio bank was enabled.

The developer pump-pair command activated the normal two-pump sequence. In the next round `Level2_PoolSlideActive` changed to true, `SpawnCount` to 1, and state to `CHASE` about 5.2 s after the command. `Level 2 Slide Alert` was created about 6.1 s after the command, loaded and played from the rig's Head-bone-follow emitter, about 170 studs from the player. Its attachment was about 1 stud from `Head.TransformedWorldCFrame.Position` after the authored mouth offset. Walk/Run loops were also observed playing from that emitter as the rig moved.

For a longer chase observation, only in disposable Play, the solo player's `Humanoid.MaxHealth/Health` was raised to 10,000 so an attack would not end the round. A `Level 2 Slide Mouth` groan appeared about 15.9 s after the pump command while the rig was chasing. Two further mouth-groan instances were observed 9.5 s apart during `CHASE`; both reached `IsPlaying=true`. No distant pipe-groan instance was seen during a further 22.8 s of `Level2_PoolSlideActive=true`. The rig's attack one-shot also loaded and played. These are state/property observations, **not an audible balance or localization test**.

After a synthetic solo death, the client had zero active entity-audio emitters and sounds. Once the round cleanup returned to the lobby, the generated world was gone, `Level2_PoolSlideActive=false`, and there were no Slide or distant-groan `Sound` instances left. Studio Play was stopped and verified back in Edit. No Edit source, asset, saved place, or published place was changed by this audio QA.

Remaining card QA: directly **listen** in a published active Level 2 round from near/far and different sides before spawn, at mouth-origin spawn, during chase, and after despawn; confirm direction, attenuation, loudness balance of the *actual* four Slide clips, ambience pause/resume, overlap and masking of footsteps/danger cues. A solo round-end cleanup was observed here, but separate despawn/resume and Level 2 exit listening paths were not. Record the publication receipt and leave the Trello card open until these checks pass.
