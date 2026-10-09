# Level 2 new map: the owner's Roblox feedback, game track (patches only)

Owner feedback 2026-10-07 (binding: `G:/Blender/Level2_Poolrooms_New_20261006/docs/OWNER_FEEDBACK_2026-10-07_ROBLOX.md`),
contracts `docs/FEEDBACK_IMPL_CONTRACTS.md`, reports `docs/feedback_20261007_investigation/01, 05, 06, 07, 08`.
Nothing here has touched Studio or the repo's mirrored scripts. The lead applies `patch.json` in Studio with the lock.

| File | What |
|---|---|
| `patch.json` | 10 entries `{studioPath, changes:[{name, old, new}]}`, in apply order. `name` is extra; the applier reads `old`/`new` only. |
| `make_patch.py` | Generates `patch.json` and `candidates/` from the repo copies (CRLF read as LF, as the applier does). Every `old` must match exactly once at its turn; every candidate is compiled with `luau-compile.exe --null`. |
| `candidates/<repo path>` | The 10 patched scripts, and 3 test files (2 changed, 1 new) for `tools/tests/`. |
| `run_candidate_tests.py` | Runs every test that reads a changed script, against the repo (baseline) and against a temp overlay with `candidates/` laid over it. |

Baseline: the repo files as of 2026-10-08 (the result of `../level2-newmap-entry-20261007`, unchanged since).

## Repo scripts that change

1. `ServerScriptService/Level 2 Systems/Level 2 World Builder.ModuleScript.lua`
2. `ServerScriptService/GameManager.Script.lua`
3. `ServerScriptService/HazmatSkinVisuals.Script.lua`
4. `StarterPlayer/StarterPlayerScripts/HazmatSkinDriver.LocalScript.lua`
5. `ServerScriptService/FlashlightSync.Script.lua` (the mirror is CRLF; the patched source is LF, as for every scoped patch)
6. `StarterPlayer/StarterPlayerScripts/FlashlightController.LocalScript.lua` (mirror CRLF, as above)
7. `StarterPlayer/StarterPlayerScripts/DevCheats.LocalScript.lua`
8. `StarterPlayer/StarterPlayerScripts/RoundUI.LocalScript.lua`
9. `StarterPlayer/StarterPlayerScripts/Level2BlenderPreviewButton.LocalScript.lua`
10. `ServerScriptService/Level2BlenderPreviewAccess.Script.lua`

Tests (repo files, not Studio): `tools/tests/test_level2_blender_preview_access.py` (changed),
`tools/tests/test_flashlight_player_control.py` (changed), `tools/tests/test_level2_newmap_feedback.py` (new).

## Hunks, and why

**The flag.** `Level2NewMapPreview` is a server-owned player attribute that means "wears the round body outside a
round" (F22). Only `Level2BlenderPreviewAccess` sets it. It goes up just before GameManager loads the round body, so
`onCharacter` sees it. It comes down on RETURN TO LOBBY or the slide (before the lobby load), when the load fails or
throws, when that body dies (`Died`), when that body leaves the workspace (`AncestryChanged`), and when the player
leaves. An older body's hooks never clear a newer body's flag.

1. **Level 2 World Builder**: `export-tub`. Adds `WorldBuilder.MakeEntryTub = makeEntryTub` and
   `WorldBuilder.MakeTubeFromPoints = makeTubeFromPoints` before `return WorldBuilder` (F20). The change is
   additive: nothing in the module calls them, and requiring the module has no top-level side effects.

2. **GameManager**
   - `first-person`: `onCharacter` gives a flagged body LockFirstPerson with zoom 0.5/0.5, as in rounds and Level 6.
   - `no-lobby-scatter`: skips the deferred `scatterAt(lobbySpawn)` for a flagged body, so it cannot race the
     preview's pivot to P0_00.
   - `Died` is left unchanged on purpose. It still sets the Classic camera and, after 3 s, calls
     `loadLobbyCharacter`, so a death in the preview returns the player to the lobby (owner decision).

3. **HazmatSkinVisuals** (`preview-bodies`, `refresh-gate`, `built-gate`, `refresh-signal`, `record-body`, `leave`).
   - The equipped skin (default BaselineYellow) is built on the preview body.
   - It is built only on the body that spawned while the flag was up (`previewBodies`). It is never built on the
     lobby avatar that is still standing while the round body loads.
   - Rounds are unchanged.

4. **HazmatSkinDriver** (`reconcile-gate`). The client drives that suit while the flag is set. The server builds the
   visual only on the right body.

5. **FlashlightSync** (`round-body`, `focus-gate`, `toggle-gate`, `off-signal`). The server accepts the round torch,
   and its focus, for a flagged player. Clearing the flag forces the light off, as the end of a round does.

6. **FlashlightController** (`round-body`, `hud`, `touch-target`, `touch-signal`, `toggle`, `focus`, `visibility`,
   `visibility-signal`). The client gets the same round torch: the F key, the touch button, the battery HUD and focus.
   The spectate battery report stays InRound-only.

7. **DevCheats** (`perspective`, `perspective-signal`). `applyPerspective` treats the flag like InRound: first person,
   and the dev C key gives the round's third person at 6..14. Without the change it would force the lobby's
   Classic 8/18 camera on every developer.

8. **RoundUI** (`globals-owned`, `atmosphere-owned`, `comment`).
   - `Level2NewMapLightingOwned` is added to both ownership conditions in `revisedLobbyLighting.restore()`, as is
     already done for Level 4.
   - Without it, entering from the R4 lobby drops RoundUI's pending pre-R4 values while the map grades, and R4's
     night leaks into the old lobby afterwards.
   - The edit is two conditions inside an existing function and adds no top-level local, so the 200-register limit
     is untouched. The file compiles.

9. **Level2BlenderPreviewButton** (client, developer-only)
   - `services`: adds Lighting and TweenService.
   - `inside-live-root`: a removed root counts as outside the map.
   - `grade` (F21, owner: DARK with WEAK daylight shafts, not night). A port of the Level 4 Lighting Controller.
     - `takeGrade` saves what the place has: Lighting, the Atmosphere (one is made if the place has none) and the 5
       Terrain water props. `applyGrade` writes the grade and re-applies it every 0.75 s. `releaseGrade` puts
       everything back.
     - Inherited Bloom, SunRays, ColorCorrection and DepthOfField effects (LobbyLocalGrade, MongoGrade) are held off
       and restored. The script owns "Level 2 New Map Grade" and "Level 2 New Map Bloom".
     - A `Changed` guard puts a foreign write straight back. Unlike Level 4, that write becomes what release restores,
       so a server change made while the map is graded is not lost.
     - Water look (item 5): dark teal (24,62,60), transparency 0.4, reflectance 0.06, wave size 0.03, wave speed 1.2.
       It is client-local only and never set on the server.
   - `refresh`: take or apply when the character is inside the map's bounds, release when it is outside. It then
     sets `Level2NewMapLightingOwned`, which RoundUI stands down on.
   - `flicker-camera`:
     - (6) Flicker. Lamps whose holder Part has `L2NFlicker = true` flicker, ported from the Level 4 FLICKER_SOURCE:
       a stutter, usually an outage of 0.3-4 s (12 %: 6-15 s), and a quarter of lamps are "dying". ReduceFlashing
       (anything except an explicit false) gives fades only. "On" is the holder's `BaseBrightness`. Flicker runs only
       while this client grades the map.
     - (7) Camera clamp. A `BindToRenderStep` at Camera+1 runs while inside the map and not in first person (the dev
       C key). It spherecasts (r 0.5) from the camera focus to the camera and pulls the camera to where the sphere
       touched.
       - Excluded: characters, the Collision's `Guards` sub-model, parts named `Barrier` (older packets), water, and
         every non-colliding part (`RespectCanCollide`: kill boxes, veils, sensors).
       - Deliberate deviation from "against the model's Collision": the cast uses Exclude rather than
         Include=Collision. It therefore also stops at the exit slide's tube colliders, and Guards can be skipped
         without re-casting.
   - `streaming`: a holder that streams out stops flickering and is left on.
   - `added`: holders that stream in join the flicker. The look is released on `CharacterRemoving` (death reload or
     return).

10. **Level2BlenderPreviewAccess** (server)
    - `header` and `service`: comments, and ServerScriptService.
    - `leave`: clears `previewBodies` when the player leaves.
    - `newmap` (replaces the old mapPoint, enterNewMap, returnToLobby and hookNewMap):
      - **F22 entry.** EXPLORE NEW MAP runs these steps:
        1. Stream P0_00.
        2. Raise the flag.
        3. Call `ServerStorage.LoadGameplayCharacter:Invoke` (GameManager's own load and character gate).
        4. Take the first new body. Wait up to 6 s for it to come alive, and fail if any other body replaces it.
        5. Hook `Died` and `AncestryChanged`.
        6. Stream again and pivot the body to P0_00 + 2, level, facing P0_01.
        7. Reply `NEW_MAP` (the client's camera turn).

        Any failure clears the flag, gives the lobby avatar back through `LoadLobbyCharacter` if the body changed,
        and replies `PREVIEW_FAILED`.
      - **Return.** RETURN TO LOBBY (prompts at P0_00 and EXIT, kept) and the exit slide follow the same path:
        1. Stream the lobby.
        2. Clear the flag.
        3. Call `LoadLobbyCharacter`, after which GameManager gives the Classic camera and the lobby scatter.

        Fallbacks: a personal avatar, or a failed lobby load, is pivoted to LobbySpawn, and a failed load also gets
        the lobby camera. A corpse is left to GameManager's 3 s reload.
      - **F20 slide.** At boot, if marker `EXIT_SLIDE` exists, the script builds "Exit Slide" inside the preview model
        with the World Builder's own `MakeEntryTub` and `MakeTubeFromPoints`. The arguments are exactly those of the
        live exit flume: r 8, TileCool, "Level 2 Exit Flume", collidable support, not forced, and a closed one-way
        tube with overlap .18.
        - The mouth is 8.3 studs over the deck. The deck is read by ray from the map's floor collider under the
          marker (fallback: marker Y - 3, since build.luau lifts markers by 3).
        - The direction is +X, with a 6-stud stub and a black 2 x 18 x 18 End Stop overlapping its end.
        - An invisible sensor (no collision, no touch, no query) fills the rider space, from 2 studs inside the
          tub's back lip to the seal. A player whose root enters it is returned to the lobby by the path above.
      - **F6/F7d kill loop.** Every 0.1 s, a server pass over living players' HumanoidRootPart tests every Collision
        descendant named `Hazard` with `KillZone == true`, using `PointToObjectSpace`.
        - Inside a box, or inside a `Cylinder` part's circle about its X axis: `Health = 0`.
        - The pass also checks the exit-slide sensor.
        - It is polled rather than `Touched`, so it holds whatever a client has streamed. The loop ends when the
          model leaves the workspace.

## Apply order (Studio first, with the lock)

The order is the order of `patch.json`: the export and every consumer of the flag first, its producer last. Then no
flagged body ever meets an unpatched consumer, and the slide build finds the export.

1. Level 2 World Builder
2. GameManager
3. HazmatSkinVisuals
4. HazmatSkinDriver
5. FlashlightSync
6. FlashlightController
7. DevCheats
8. RoundUI (must precede the button: the button starts grading under `Level2NewMapLightingOwned`)
9. Level2BlenderPreviewButton
10. Level2BlenderPreviewAccess

### How to apply

1. Use `../level2-newmap-entry-20261007/apply_scoped_patch.py patch.json <label>`. Set its `STUDIO_ID` to the current
   session first: `list_roblox_studios` (the ID changes when Studio restarts).
2. It snapshots the fresh Studio source, asserts that every `old` matches exactly once, compiles, applies by CAS
   through `UpdateSourceAsync`, re-reads, and writes the installed copies to the repo.
3. GameManager (186 KB), RoundUI (273 KB) and the World Builder (235 KB) are large, so you may apply the list in slices
   (same order), for example with a few entries per run.
4. Audit first. Other sessions push GameManager and RoundUI. On a CONFLICT (an `old` that no longer matches), merge by
   hand and never overwrite.
5. Afterwards:
   - copy `candidates/tools/tests/*.py` to `tools/tests/`;
   - update `studio-sync-manifest.json` the usual way;
   - publishing stays the lead's call.

## Live tuning (no script push)

Set these attributes on `Workspace."Level 2 Poolrooms New (preview)"` on the server during Play. Every developer
client inside the map follows within 0.75 s. A value of the wrong type is ignored, and the default is used.

- `GradeClockTime` 13
- `GradeBrightness` 0.8
- `GradeAmbient` (18,22,23)
- `GradeOutdoorAmbient` (12,15,16)
- `GradeColorShiftTop` / `GradeColorShiftBottom` black
- `GradeDiffuse` 0.08
- `GradeSpecular` 0.35
- `GradeExposure` -0.15
- `GradeShadows` true
- `GradeShadowSoftness` 0.2
- `GradeDensity` 0.3
- `GradeOffset` 0
- `GradeHaze` 1
- `GradeGlare` 0
- `GradeAtmosphereColor` (28,34,36)
- `GradeDecay` (10,13,14)
- `GradeTint` (220,236,234)
- `GradeSaturation` -0.3
- `GradeContrast` 0.15
- `GradeColorBrightness` -0.02
- `GradeBloom` 0.5
- `GradeBloomSize` 24
- `GradeBloomThreshold` 0.95
- `GradeWaterColor` (24,62,60)
- `GradeWaterTransparency` 0.4
- `GradeWaterReflectance` 0.06
- `GradeWaterWaveSize` 0.03
- `GradeWaterWaveSpeed` 1.2

All of these are starting values, to be tuned with the owner in Play.

## Contracts consumed (other tracks)

- **Pipeline:** `Collision` descendants named `Hazard`, with attribute `KillZone = true`, for the A3a pits and the A3b
  drain. Box or Cylinder; they should be non-colliding. These are not in `build.luau` yet as of this run. Until they
  exist, the loop kills nothing.
- **Pipeline:** the `Collision.Guards` sub-model (already in the `build.luau` working copy).
- **Pipeline:** `L2NFlicker = true` on the light holder Part for `l2n_light_state = "flicker"` (not in `build.luau` yet).
- **Pipeline + A6:** marker `EXIT_SLIDE` (the floor under the tub mouth). The A6 builder already places the Empty. The
  slide room must be rebuilt before the slide is meaningful; without the marker no slide is built, and the prompts
  still work.
- **Existing:** the model attributes `BoundsCenter` and `BoundsSize`, and markers `P0_00`, `P0_01` and `EXIT`.

## Verified offline (2026-10-08)

- All 10 candidates compile (`luau-compile --null`), including RoundUI under the register limit.
- `luau-analyze` reports no new unknown globals except real Roblox ones (Color3, RaycastParams, Random, TweenInfo).
- `run_candidate_tests.py`: 22 affected tests, no regressions.
  - `test_level2_blender_preview_access.py` failed on the baseline because its harness was stale against the earlier
    entry patch; it now passes. It has 29 new-map checks: flag lifecycle, the swap rule, failure paths, zones,
    Cylinder zones and a corpse.
  - `test_level2_newmap_feedback.py` is new and runs the real sections: grade 15 checks, flicker 5, camera clamp 12,
    slide + kill zones 16, RoundUI restore 3, GameManager 5, DevCheats 3, skin visuals 6, skin driver 3, and the
    World Builder export.
- Mutation checks:
  - each new program fails when the matching baseline script is swapped in;
  - the body-swap check fails on the first (cut-off) run's access script.
- Failing before and after this patch, not caused by it:
  - `test_push_repo_to_studio.py`: needs a luau that supports `--version`.
  - `test_round_loading_notice.py`: a stale harness; its fake player lacks `SetAttribute`, which RoundUI's dispatch
    now calls.

## Not verified (needs Studio Play QA)

Nothing here ran in Roblox. These need checking in Play:

- how the grade looks (dark, weak sun patches under the oculi and hatches; Sky at ClockTime 13);
- that client-local Terrain water props render;
- the camera clamp's feel;
- the timing of LoadCharacter / RequestStreamAround (the suit body is briefly at the lobby spawn);
- the slide templates loading in a live lobby server, and the tub fitting the rebuilt A6 room;
- the kill boxes once the pipeline exports them;
- that `RaycastResult.Distance` of a Spherecast is the sphere centre's travel (as documented).

### Play QA checklist

1. As a developer, use EXPLORE NEW MAP. Expect: the hazmat body in the equipped skin, first person, facing P0_01,
   the F torch and HUD, the map dark with weak shafts, and dark water.
2. Press C. Expect: third person, and the camera stops at walls in tight rooms.
3. Expect a flicker lamp to stutter. With ReduceFlashing it should only fade.
4. Jump into an A3a pit and into the drain. Expect: dead within about 0.5 s, then after 3 s your own avatar in the
   lobby with the Classic camera and no grade leak (also check after entering from the R4 lobby).
5. Walk through the exit door into the tub. Expect a return to the lobby.
6. Use RETURN TO LOBBY at P0_00 and at EXIT.
7. In the console, expect no `[Level2NewMapPreview]` warnings. Expect `Level2NewMapPreview` to be nil after each
   return or death.
