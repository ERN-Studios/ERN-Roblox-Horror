# Pool Slide groan source check — 24 September 2026

The four published groan asset IDs in `ReplicatedStorage/Level 2 Entity Audio Bank.ModuleScript.lua` were retrieved read-only through Roblox asset delivery. Each is a stereo 44.1 kHz Ogg file, exactly 8.0 seconds long. This check is on the source files, **not** a directional listening test in a Level 2 round.

| Asset | Peak dBFS | RMS dBFS | Last 0.5 s RMS dBFS | Samples above 0.99 |
| --- | ---: | ---: | ---: | ---: |
| 135741106151964 | −3.1 | −13.3 | −59.1 | 0% |
| 135920645468915 | −3.0 | −13.8 | −69.6 | 0% |
| 82575067339531 | −3.1 | −18.5 | −80.6 | 0% |
| 76676509241608 | −3.2 | −18.1 | −107.6 | 0% |

The files have peak headroom and fade out; the first two average roughly 4.5–5 dB louder than the latter two. A blanket gain increase for the quiet clips would approach the peaks, so judge any balancing in game rather than normalizing blindly.

Remaining card QA: in an active Level 2 round, listen before entity spawn from near/far corridor positions, during mouth-origin spawn and chase, and after despawn; confirm directional attenuation, ambience pause/resume, no stacked timers/overlap, and full cleanup on exit or round end. Check near audio against footsteps and danger cues. Record the place version and test positions before moving the card to Done.
