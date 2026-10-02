# R4 lobby — verified live Studio revision

The Blender R4 lobby remains beside the original ServerLobby at (220,30,-760). The rounded tunnel uses concrete color/normal/roughness maps; asphalt and sidewalk have matching PBR maps. Main headers sit over the six frames; double-sided hanging arrows remain visible from both tunnel approaches. Six themed bays host 24 real queues. Raised DJ stage/steps, speaker stands, slow vinyl rotation and fixed needles are present.

## Actual Studio Play evidence

- Six bay route walks completed with health 100; 36 runtime floor rays hit walkable floors without a miss; all 1641 lobby parts anchored.
- Actual queue UI creation/cancellation and ten-band upward hologram fade checked.
- R4 station 109 loaded the original Level 3: READY, InRound, generated world, health 100. R4 station 101 loaded normal Level 1, and a later real L hold returned to the original lobby.
- R4 station 121 loaded Level 6 at the tube arrival; E from the normal Custom camera returned to the lobby. RETURN anchor is ahead of the arrival view, within the unchanged12-stud server guard.
- Actual slow vinyl motion/static needles and ReduceFlashing stop behavior checked.
- All nine actual PBR images rendered in ImageLabels with IsLoaded=true/FetchSuccess. Raw-URI preload callback Failures were inconsistent and retained in the evidence; unsupported SurfaceAppearance preloading returned no callbacks.
- RoundUI v6 restores all nine lighting properties and atmosphere on return. Runtime-only other-party2/3 marker fixtures and a real Level 4 controller spatial handoff passed; these are not multiplayer/authenticated Level4 tests. Natural respawn from R4 restored the original lobby light.

## Review and preservation

Exact v6 RoundUI compiled, passed 17 meaningful regressions and Codex peer review; actual Claude Opus 5.5/max returned PASS FOR ACTUAL PLAY. RETURN mount compiled/passed 23 regressions; Claude reviewed the prior mount and Codex verified the final bounded radius/framing refinement.

Studio is authoritative. Full native before/after recovery snapshots and Source/editor equality are recorded separately. Concurrent Level 1 work/current GameManager 7e and MazeGenerator/PushDoors edits were preserved; the eight-source mirror includes the fresh authoritative GameManager, rather than overwriting it with installed 951. The original lobby and earlier Level 6 spawn/ceiling changes are retained.

Authenticated Level 4/5 launch, multiplayer stress and complete Level 2 entity/pump gameplay are not verified by this task. No access rules or active-server restarts were changed.

Roblox Studio reported PublishSuccessful and Place published at 2026-10-02T06:45:31Z for version2483; the filtered acknowledgment is in publication-receipt.json. The local commit ID is reported after the scoped commit is created. Git has no configured remote; a local commit is not a GitHub push.

Actual screenshots: [north signs](playtest-20261002/final-signs-north.png), [south signs](playtest-20261002/final-signs-south.png), [PBR loading proof](playtest-20261002/pbr-nine-images-loaded.png), [Level 3 queue arrival](playtest-20261002/original-level3-real-queue-launch.png).
