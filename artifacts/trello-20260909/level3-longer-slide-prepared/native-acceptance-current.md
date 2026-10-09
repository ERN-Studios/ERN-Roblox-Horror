# Longer L3 slide — current native handoff

Prepared 2026-09-10; instructions only. No native execution, runtime change or publication by this artifact. This corrects the original README's ambiguous “launch Level 3” step: a direct Level 3 lobby queue takes the service elevator and does **not** exercise the campaign's bore-resume placement.

## Exact installation stage

After the separately accepted Switch release, use the existing composition's **switch-slide** stage, not this feature's old standalone GM:

| Source | Required prior SHA-256 | Proposed SHA-256 |
|---|---|---|
| GameManager | `3d1b05993778f7640dcea4b51193cfe2cee0224552e8303bfd3dde991933d7db` | `757e2673db873c89af0f1a5d292bd6b44396eaf1f14a4923a5d201eaf2ca4439` |
| Level 3 World Builder | `f1256558007826450fe5c86cc2a0f160d2274270ae345380135d4585bcb6f6b3` | `a3a41d76f6dc6d13d782cb5dab5595757a5cd9b1d1b440f6605f310c56bf983d` |

GM file: `../continue-switch-choice-prepared/composition/variants/switch-slide/ServerScriptService/GameManager.Script.lua`.
Builder file: `proposed/ServerScriptService/Level 3 Systems/Level 3 World Builder.ModuleScript.lua`.
The Switch RoundUI/UIRegression companions stay as separately installed. Compare actual sources before installation; these hashes describe a prepared stage, not an assertion that root has installed it. Recompose if the actual checkpoint differs. `test_slide.py --gm-source <that switch-slide file>` is the existing focused host if a new merge needs checking; no new test framework is required.

## Shortest real campaign route

1. In a fresh ordinary two-client local session, create/join one **Level 2** party through the actual lobby UI. Wait for both actual characters alive, `InRound=true`, client `RoundEntryControlsReady=true`, and active/generated Level 2. Reuse the already reviewed Continue client observers on A/B and server observer before completing L2; their default 240-second windows may need a fresh run if setup used most of the window. Keep their outputs separate from Switch acceptance.
2. Either solve the actual pumps, or root may use the existing **Studio-only `Objective.DebugOpenExit()`** once in an ordinary server Script using the production module cache. Label the latter a **controlled objective/door fixture**. It sets StartedCount and calls the real door-opening path; it does not mark either player escaped or set the campaign entry mode.
3. Both actual players then physically cross the real exit sensors (or the production movement-sweep detector). If root stages players nearby to shorten travel, record that setup explicitly and release actual physics before sensor contact. Do not fake a touch, set `Level2_ExitTransition`, or replace this with a bare `PuzzleWon=true` fixture. Verify each real `Escaped=true` and `Level2_ExitTransition=true` in the existing server trace before the result window.
4. Leave both as continuers through the actual 15-second deadline, or use actual Continue clicks. Keep both continuing for the local campaign's shared L3 route; a mixed Continue/Lobby choice exercises Studio's existing whole-lobby fallback instead. Capture `win`/choices/deadline, new entry token, `level3access`, and `start` from the existing observers.
5. Observe the actual next L3 characters from anchored entry through release and the full descent, then the landing and restored controls. Do not use `ProbeLevelThreeSlideOut` during this normal entry; it actively replaces the placement under test.

The root-only optional door fixture is just this existing API, executed in the **ordinary server Script cache**, not a fresh stateful require context:

```lua
assert(game:GetService("RunService"):IsStudio() and game:GetService("RunService"):IsServer())
assert(game.PlaceId == 131311258779917 and game.GameId == 10559217407)
assert(workspace:GetAttribute("SelectedLevel") == 2)
assert(workspace:GetAttribute("RoundActive") == true and workspace:GetAttribute("WorldGenerated") == true)
local systems = game:GetService("ServerScriptService"):FindFirstChild("Level 2 Systems")
local objective = require(assert(systems and systems:FindFirstChild("Level 2 Objective Controller")))
local opened = objective.DebugOpenExit()
assert(opened.DoorsOpen == true and opened.CanTouch == true)
print("L3_SLIDE_CONTROLLED_DOOR_FIXTURE", opened.DoorsOpen, opened.CanTouch, opened.Position)
```

`DebugOpenExit` is intentionally a gameplay fixture, not a read-only observer. Root owns its execution and removal. Its real `openPressureDoors` path also makes existing Foam lethal; stage any controlled real players near the actual exit **before** opening it to avoid an irrelevant transit death. It avoids the old high-speed suite's unrelated completion reset, network ownership takeover and later player/attribute restoration.

**Why the route matters:** GameManager's `runRound` privately latches `exitTubeRoute` when a participant's actual `Level2_ExitTransition` becomes true. Only that completed L2 route passes `EntryMode="level2-exit-tube"` to `continueStudioCampaign` / the next-level teleport. A pure quest-win flag or direct L3 lobby queue leaves the mode absent. The bore branch activates Level 3, waits a heartbeat, releases prepared riders, then emits `level3access`; the other L3 branch runs the seven-second service elevator. The old README's direct-queue instruction cannot certify this branch.

## Exact observation points and acceptance

Use the existing `native-session-1300` client/server observers for entry tokens, UI/controls readiness, round state, real IDs/character changes and choice packets. They sample state changes and attach positions to those records; **they do not continuously measure the slide, record stream ack packets, or inspect slide actuators**. Do not infer a complete ride from their sparse positions.

| Phase | Actual read-only evidence | Required interpretation |
|---|---|---|
| Geometry | `Workspace["Level 3 Generated World"]`, descendant with `Level3_Level2ExitTube=true`; its `Level3_SlideLength`, `Level3_SlideRise`, resume/mouth/tangent/velocity attributes | Length400, rise115, radius8 unchanged; six nominal alphas .80/.83/.86/.89/.92/.95. Use the **actual HRP**, not Model:GetPivot(), for placement. |
| Per-player placement | Client `Remotes.Level3SlideStream.OnClientEvent` arguments `"request", token, position, timeout`; actual character/root identity, position, Anchored, Health | The requested point is the GM-selected stream destination. For two simultaneously occupied initial slots expect α.80/.83 and later Y higher; identify order from requests/positions, not UserId order. Selection uses actual vacancy and can legitimately reuse a freed slot. No yield between free-point choice and PivotTo. |
| Stream readiness | Read-only server `Level3SlideStream.OnServerEvent` listener sees `player,"ack",token,ready`; pair with the exact request token and current character, plus each client's visible local geometry | `ready=true` follows actual client presence of a **collidable** part tagged `Level3_ProgressionSlide=true` within28 studs of the request point. RequestStreamAroundAsync returning alone is insufficient. An observed ack is a packet; actual unanchor in the current ready entry proves release took effect. Never send an ack from the observer. |
| Release | RoundActive=true before current HRP.Anchored becomes false; actual initial velocity aligned downhill near62; no current `LobbyTransferShield` after release | Frame sampling may miss the exact velocity assignment. A later accelerated sample is not a measurement of the assigned62. Record requested target and first unanchor promptly, before model/tool latency loses them. |
| Actual ride | On **each real client**, ≤0.1-second capture of current HRP XYZ/velocity, Humanoid Health/PlatformStand/AutoRotate/WalkSpeed/state, character `Level2_ForcedSliding` and `Level2_RagdollServerActive` | Observe slide state, continuous travel toward the mouth, no shell escape/rear-cap crossing/void fall, genuine mouth exit and braking. A stationary pose or server-only snapshot cannot prove client-driven physics. |
| Landing | Client `Level2_ForcedSliding` cleared, PlatformStand=false, HRP unanchored, health alive, owned force/attachment absent, living joint/control restoration, actual supported mall floor and real movement input | Compare speed/joints to their pre-slide or intended current state. `Level2_DesiredWalkSpeed` or captured ResumeWalkSpeed controls restoration; do not hardcode16 or require every authored constraint disabled. Check actual walk/turn/jump as appropriate, not only properties. |
| Ordinary cleanup | After the round's actual return/removal: old L3 world absent, current new lobby character alive/unanchored, no slide marker, actuator/attachment or transfer shield on that current character; normal input works | A Studio Stop removes the entire simulation and alone does not prove normal lifecycle cleanup. If an interrupted ride/character replacement is exercised, record old/new identity and ensure an old callback does not restore/anchor the replacement. Death intentionally preserves corpse ragdoll ownership. |

Exact slide force descendants under the actual HRP are **`Level 2 Ragdoll Downhill Force`** and **`Level 2 Ragdoll Slide Force Attachment`**. Marker ownership is **character** (`Level2_ForcedSliding`, `Level2_RagdollServerActive`); entry/escape flags are on **Player**. Client-only attributes and local constraints may not replicate to the server. The existing observer's `RoundEntryUIReady` and `RoundEntryControlsReady` should therefore be read on both clients; a nil server copy is not an automatic failure.

Match per-client tube stream requests and real positions before publishing a slots result. Native two-player evidence certifies two real riders only; the other four positions remain the reviewed emitted-geometry/actual-selector evidence until six real clients are run. A clone-based six-slot fixture is supplementary, not six-client networking evidence.

## Reuse of existing suite — useful, but separate

`ServerScriptService["Level 2 Systems"]["Level 2 Exit Transition Test Suite"]` exports:

- `ValidateLevelThreeResume(workspace["Level 3 Generated World"])`: read-only structural checks, resume tangent/speed, nearby physical floor, fallback spawn. Add readback of the exact new length400/rise115; its old minimum-length threshold150 does not itself certify the patch. Run when the published resume ray is not occupied by a player's collidable body: this helper does not filter characters, so such a hit must be investigated instead of blamed on missing tube geometry.
- `ProbeLevelThreeSlideOut(world, actualPlayer)`: optional **controlled one-rider** check in a stable L3 round only. It preserves client network ownership, stages at the first published point, gives the existing velocity, samples every.1s for up to14s, then restores the saved player state. Assertions require slide state, >80% of total slide length travelled, >40-stud/s approach, peak above initial speed, mouth exit and PlatformStand=false. Keep its thresholds intact.

The second helper uses `Character:PivotTo(frame)` directly; its staged HRP can differ from the current GM's corrected HRP target by the authored model PivotOffset. It also bypasses real slot choice/entry streaming/ack/release and writes/restores player flags/position. It is **not** normal entry or exact GM placement evidence. Do not run it while the campaign is transitioning or its saved player is being replaced. The high-speed and long-duration L2 completion probes likewise have active setup/restore and are unnecessary for this narrow release.

Do not manufacture a stream failure by disabling APIs or removing the tube. If a real failure occurs, preserve its request/ack/error evidence and inspect the existing solid-elevator fallback. Missing stream-failure evidence is an explicit remaining coverage limit; this feature changes neither that fallback nor the excluded loading Testing cards.

Source basis: current/composed GM `beginVerifiedBoreStream`, `placeAtLevelThreeSlideResume`, `runRound`, `continueStudioCampaign`; L2 Objective `completeFor`, sensor/sweep handlers and `DebugOpenExit`; existing Level2 Slide Controller stream callback, `startSliding` / `finishSliding` / `restoreMovementAndCollision`; existing L2 Slide Ragdoll Service; existing Exit Transition Test Suite. No live Studio or UI was read or changed for this handoff.
