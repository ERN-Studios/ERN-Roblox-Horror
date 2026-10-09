# Native before/after — 2026-09-10

Each run used normal single-player Play, the actual Level 1 launch zone and Create Party button. Only setup teleport to the real queue zone and an observer LocalScript were used; no synthetic elevator event. Both real entrants were alive (100 HP), InRound and unanchored. Observers received loadinggame, entryreleased and actual elevator countdown events.

The original RoundUI produced maximum positive camera pitch 0.2797835982 degrees, displacement 0.1598763466 studs and rotation 0.0048828172 radians between Camera+1 and Camera+3. Before: Completed=true, 795 frames over 13.2576306 seconds. The late peak matches the existing elevator stop calculation.

After installing only RoundUI baea58303d309a493645b763d40b9492ccffeb9a5948147ee6a012874e6a40f6, the same normal queue and observer interval reported Completed=true, 795 exact unchanged frames, 0 changed frames and zero raw position, angle and pitch deltas. The interval was 13.2512876 seconds. CameraType=Custom, original Humanoid subject and 70-degree FOV remained intact. Both observers made zero camera writes and removed their own render bindings. The second observer additionally compares CFrames directly to avoid inverse-transform numerical noise; its independent review and exact three-hunk diff are retained.

This verifies the complete delayed elevator callback interval after entryreleased, within Level 1's 19-second ride. It is not a complete playthrough or a native Level 3 test. A later MCP mouse-look attempt did not change the sampled pose and is not counted as successful input QA. Subsequent user-input/window changes and the later death (HP=0, Scriptable death camera) are outside both traces and are not evidence about this loading callback.

Play was stopped. All 125 scripts compiled, no staging failures, source audit 0 drift (one previously permitted Level 2 Lighting trailing newline). No observer or runtime test override remains in the edited place.
