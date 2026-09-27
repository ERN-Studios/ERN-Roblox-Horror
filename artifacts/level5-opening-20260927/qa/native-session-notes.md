# Native Level 5 QA — fresh v2150 baseline

One agent-owned Play session was started and stopped through the Studio connector. No source edits had been installed. This is new evidence separate from the historical loading timeouts.

- Normal `ServerStorage.Level5DevStart:Invoke()` accepted the developer roster.
- The normal entry readiness barrier reached `ready`; world, spawn pad, collidable arrival ground, UI and controls were ready. The round then became active.
- Character navigation walked from arrival through A to the lock at normal/2x test navigation speed. The first attempted E interaction was behind AtriumRearCottage_1.BackWall; the normal server LOS guard correctly refused it. Reapproaching from the doorway opened the UI using E.
- Gate A: real mouse clicks submitted all-red; rejection feedback appeared and gate stayed locked. Real clicks changed choices to red/yellow/blue/green, then UNLOCK. Server verified `Unlocked=true`, `FullyOpen=true`, `OpenReason=SOLVED` and progression `Puzzle1Solved=true`. No developer bypass or forged submit remote was used.
- Character navigation walked through the open first gate into B and the clue residence, arriving near (17000,24.36,286.18).
- The B clue showed LAMP / CUP / KEY, numbered 1–3, correct front orientation, readable labels and symbols under normal shared lighting. It became almost unreadable during the baseline outage; even flashlight viewing was very dim. After normal 65-second restore the sign was clearly visible. Capture IDs: B_clue_live_before_fix, B_clue_flashlight, B_clue_normal_light.
- Read-only inspection found all 12 clue boards, matching definitions, supported sample viewing points, and fitting labels. This is not a complete walking-route or multiplayer proof.
- Gates B–G, F traversal/pit recovery and H ending were not exercised in this session. H still has no real completion/slide controller.
- The Play session was stopped before the attempt to download a native copy. Studio's Save dialog later hung. No outage/access/lobby/source patches were installed before that hang.

The Device Simulator API was returned to the default viewport before the test. The game declares Sensor orientation. This session used desktop mouse/keyboard only, not physical mobile or multiplayer.
