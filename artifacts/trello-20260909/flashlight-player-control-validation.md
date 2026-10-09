# Level 3 flashlight remains player-controlled

Trello: nS5vj1RM, "Remove the forced flashlight". The matching runtime behavior was a forced OFF/toggle lock before the entity scream and near the end of its hunt. No automatic ON behavior was found in this path.

**Done: published v1819 on 9 September 2026 at 23:23:10.715 Danish time.** Root used the mouse through File → Publish to Roblox and verified the version in native Studio Output. Final independent critic score: **9/10**.

## Scope

Five production files changed, backed up byte-for-byte under `flashlight-before/`:

- `Level 3 Music Sequence Controller.ModuleScript.lua`: removed suppression state, its timer calculation/call and snapshot field. `Stop` clears both saved legacy attributes unconditionally, including with no previous session. `Start` already calls `Stop`.
- `Level 3 Configuration.ModuleScript.lua`: removed the two obsolete flashlight-lock duration fields and their comment.
- `FlashlightController.LocalScript.lua`: removed suppression checks/listener from local on/off and shared F/gamepad/touch input. Normal alive, InRound, battery, death, respawn and warning behavior stays in place.
- `FlashlightSync.Script.lua`: removed the matching server toggle/aim gates and force-off listener. Server flag/mount replication, alive/round guards, origin validation, rate limits and immediate off signals are unchanged.
- `Level 3 Test Suite.ModuleScript.lua`: removed dependencies on the retired configuration fields while retaining the same two sampled moments in the furniture/hiding probe. Added a no-suppression assertion.

The existing Round Adapter false-valued legacy attribute reset remains harmless and consistent with cleanup. No production code can set either suppression attribute true or read it to control a flashlight.

Exact diff: `flashlight-player-control.diff` (223 lines). Root's scoped Studio-push backup is `.studio-push-backups/20260909-211603/`.

## Verification

- `test_flashlight_player_control.py`: **217 checks passed** using actual local input/lifecycle/battery code, the complete server sync script and the actual teammate beam update. Exercises old phase boundaries, stale true attributes, F/gamepad/touch, table hiding, battery exhaustion/recharge, death, respawn, round end, immediate off, replicated flags/mounts and aim validation.
- `test_level3_flashlight_timeline.py`: **322 checks passed** using the complete music controller and complete production configuration. Exercises old lock windows, first-CD/preload gating, all phase boundaries, scream timestamps, cycles and cleanup.
- All five modified Lua files compiled successfully.
- `git diff --check` found no whitespace errors; existing mixed-newline warnings are unchanged.

Independent critic: **9/10**, no code blockers. The critic reviewed the exact five-file delta, checked remaining references, reran both focused suites and compiled all five complete files. Root then completed the native checks below; final critic score remained **9/10**.

The timeline test also rejects the original baseline on stale-attribute cleanup, and rejects a baseline with only cleanup corrected when the old lock activates at 176.035927 seconds.

Timeline timings remain:

| Event | Elapsed seconds |
|---|---:|
| Warning begins | 145 |
| Room blackout begins | 150 |
| Scream begins | 177.035917 |
| Entity hunt begins | 180.035917 |
| Hunt ends; recovery begins | 210.035917 |
| Recovery completes | 213.235917 |

## Root-owned native verification

Root launched Level 3 through its normal lobby queue, then used the live production music controller in a disposable Play session to exercise both former lock windows. The client was observed in the active Level 3 round with loading ready in the tool output; that specific post-launch observation was not separately saved in the JSON. The JSON's first entry is explicitly `beforeNormalLaunch` and is a lobby baseline, not proof of the launch.

The [native evidence](flashlight-player-control-native.json) records:

- Before the scream: the first client sample run had **2 off samples out of 174**. The cause is unresolved; an ordinary battery warning blink was a possibility, not a proven explanation. The repeat had **0 off samples out of 138**. Server sampling had **0 off samples out of 48**, with the flashlight flag and Core/Spill lights on and suppression false.
- At the hunt's end while hidden: **0 off samples out of 136** on the client and **0 out of 48** on the server, including the transition to recovery.
- Manual **F off/on under an actual hiding table** worked in both former lock windows at 100 HP. The native view also showed the actual light beam. The blackout, scream, hunt and recovery timeline continued.
- Death set the flashlight and Core/Spill lights off. The normal return to the lobby restored 100 HP with `InRound=false`, round inactive, flashlight off and the replicated mount removed.

Root stopped Play and removed the disposable test helpers before publication. Full live compilation passed **122/122** and the source audit showed **zero drift**. The focused offline suites passed **217 + 322 checks**, and all five changed files compiled individually.

**Verification boundary:** this is one actual Studio client with its server and native rendering. A second physical client and physical gamepad were not certified by this run. Offline teammate/gamepad checks do not replace those device/multiplayer tests. The first two unexplained off samples remain documented rather than being relabeled as a verified battery effect.

Root published using the mouse through **File → Publish to Roblox**. Native Studio Output confirmed **v1819**, **2026-09-09 23:23:10.715 Danish time**. Trello was updated with the results and limitations, moved to Done and marked complete.
