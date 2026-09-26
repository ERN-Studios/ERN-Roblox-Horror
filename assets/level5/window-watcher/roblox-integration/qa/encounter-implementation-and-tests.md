# Window Watcher encounter — draft history and integration contract

Date: 2026-09-25. Version: `2026-09-25.intermittent.1`.

**Update 2026-09-26:** the permanent rig, published clips, encounter module, Adapter hook and client visibility guard are installed in Studio Edit. The three published clips passed 300 native bone/time comparisons (maximum component error below 0.000194; tolerance 0.001). Current runtime QA and experience publication receipts are in the [main handoff](../../../../../docs/LEVEL5_WINDOW_WATCHER_2026-09-25.md).

The sections below retain the 25 September draft contract and its tests. Files under `patches/` are historical proposals; use fresh authoritative Studio source mirrors for the installed implementation and its visual client. The guard permits local visibility only after the correct official track loads, advances and evaluates its pose. It leaves server timing and animation playback authoritative. Historical test results do not certify subsequent source changes.

## Historical prepared files

All paths below are relative to the repository root.

| File | SHA256 |
| --- | --- |
| `assets/level5/window-watcher/roblox-integration/patches/Level 5 Window Watcher Encounters.ModuleScript.lua` | `df0313bb67e3c1b7ec48548cf5b19e6173e809494e562aa98d6535f56caf9f18` |
| `assets/level5/window-watcher/roblox-integration/qa/test_window_watcher_schedule.luau` | `2b63f677eab85d19da20857f4d2605aedddc383987879f52ccc363780dbef4c3` |
| `assets/level5/window-watcher/roblox-integration/qa/test_window_watcher_lifecycle.py` | `1eb72e32a135574ee006c46a815e91ebe2da89d329b914de41c0fe609a050c4a` |

The old `tools/staging/level5_window_watcher_preview.luau` simultaneously displayed all three poses. It is reference material, **not** the intermittent implementation to install.

## Behavior and ownership

One cached, noncolliding rig appears at one of the three authored windows. A live participant entering F starts a 2–4 second first-encounter delay; an eligible window must also become visible. The actor remains visible for 8–14 seconds after its hidden animation warm-up, then waits 18–35 seconds. Different windows are selected whenever another eligible window exists; the sole eligible window may repeat.

Eligibility requires `SelectedLevel == 5`, `RoundActive == true`, a returned Player still in Players, `InRound == true`, neither Escaped nor Spectating, a living Humanoid and HumanoidRootPart, and a root position relative to Origin inside X ±160, Z 776–1036, Y −10–70. Window candidates must face at least one participant, be 3–145 studs away, and have an unobstructed ray to their real pane. Camera gaze is not read; this is physical visibility eligibility. Rays run only when a hidden appearance is due, at most three per nearby participant per 0.25-second check.

The last participant leaving F/its roster immediately hides the actor and cancels its pending reveal. No AI, chase, damage, sounds, pathfinding, completion, rewards or access changes are added. Existing developer-only Level 5 access remains authoritative.

There is one Heartbeat connection and bounded destruction/ancestry connections; no spawned threads or delayed tasks. `Cleanup(world)` is idempotent. World destruction, moving the world out of Workspace, destroying the owned encounter folder, or disabling Level5DevEnabled disconnects the owner and destroys its tracks and rig. Partial installation/load failures roll back the folder. Duplicate installation preserves the existing owner and returns an error.

The installed eyes use a UV emission mask on the actual skinned MeshPart through SurfaceAppearance, so mesh transparency hides the body and eyes together. No physical Light or GUI is required. The original BillboardGui proposal was rejected after native inspection found that the tinted pane occluded it. The encounter module also hides/restores any authored GUI/Light descendants for defensive cleanup, but the eye installer does not create them. Imported scripts/sounds are removed from the clone.

## Original integration contract

The server ModuleScript is installed as `ServerScriptService.Level 5 Systems.Level 5 Window Watcher Encounters`. The Adapter calls it after Architecture.Build, when `manifest.World` and `manifest.Origin` are assigned and the world is in Workspace; edit-mode architectural previews skip it. This snippet records the original hook contract, not a replacement for the fresh authoritative Adapter source.

```lua
if RunService:IsRunning() then
    local watcherModule = script.Parent:FindFirstChild("Level 5 Window Watcher Encounters")
    assert(watcherModule and watcherModule:IsA("ModuleScript"), "Missing Window Watcher encounters")
    local watcher = require(watcherModule)
    local result = watcher.Start(world, {
        Origin = ORIGIN,
        GetParticipants = function()
            return Players:GetPlayers()
        end,
    })
    assert(result.ok, result.error)
    manifest.WindowWatcher = result
end
```

`GetParticipants` must synchronously return a Player array without yielding. The encounter module applies the roster/alive/round filters described above. The Adapter's existing DevAccess checks remain unchanged. Its existing world-destruction cleanup already cancels the encounter; an additional explicit `watcher.Cleanup(world)` is permitted but unnecessary. The passive encounter preserves the no-damage/no-completion contract.

Required template structure:

```text
ServerStorage
  Level5WindowWatcher
    WindowWatcherRig (archivable Model; BaseParts; no Humanoid)
      AnimationController
        Animator
    Animations
      WatchingIdle (Animation with published rbxassetid://…)
      SlowWindowLean (Animation with published rbxassetid://…)
      GlassTap (Animation with published rbxassetid://…)
```

Missing AnimationController/Animator can be created by the module; duplicate controllers/Animators fail validation. The template needs a bottom-origin pivot, eight-stud prepared height and canonical −Z facing. Mesh, bind/rest bones and animation translation keys must share the same scale (~3.333 studs/metre); changing only MeshPart.Size is insufficient.

Anchors remain under `world.Level5_IndoorSuburbs.F_BayWindowCanyon.WindowWatcherAnchors`. Each is a tagged BasePart with a `WindowGlass` ObjectValue referencing its actual tagged Glass pane. The actor frame is `pane.CFrame * CFrame.new(1.1, -6.55, depth)`:

| Anchor | Clip | Inward depth |
| --- | --- | --- |
| FarUpperWindow | WatchingIdle | 0.95 studs |
| MiddleCourtWindow | SlowWindowLean | 0.95 studs |
| NearGroundWindow | GlassTap | 1.90 studs |

Depth uses the final exported GlassTap minimum Z of −1.745002 studs, leaving +0.154998 in pane space before accounting for its +0.07 rear glass surface. Native Play has shown the full tap through the real window. Final placement/clearance evidence is recorded in the main handoff; bone samples alone do not prove every skinned vertex's clearance.

`Start` returns `{ok, folder, version, actorCount = 1, assetPlaybackVerified = false}` or `{ok = false, error}`. The rig remains hidden until all three official Animator tracks report positive Length. A 20-second loading timeout removes the encounter and records `world.WindowWatcherError`; the map remains intact. Syntactic asset IDs and positive track lengths do not prove ownership permissions, correct skinning, visible bone motion or client replication.

## Historical local verification — 25 September draft

- Luau compilation passed.
- **1,031 scheduler assertions passed**, including 200 complete appearances, timer bounds, no overlap, eligible-window variety, warm-up-adjusted duration, absence/re-entry, and permanently inert state after Stop.
- **29 mocked lifecycle assertions passed** using the actual draft source: one actor; body/eye hiding; one playing track; importer-script/audio removal; duplicate-install protection; participant exit; partial animation-load rollback and retry; asset timeout; world/folder destruction; ancestry removal; and zero surviving connections after cleanup.

The scheduler test imports the actual draft. The Python lifecycle runner embeds that same source in a temporary Luau harness with bounded Roblox fakes and removes the temporary file afterward. These tests **do not verify native Animator playback, asset upload/permissions, real raycast geometry, native render visibility or multiplayer replication**.

From the repository root (replace `/path/to/luau` and `/path/to/luau-compile` with your CLI paths):

```sh
/path/to/luau-compile -O0 --null 'assets/level5/window-watcher/roblox-integration/patches/Level 5 Window Watcher Encounters.ModuleScript.lua'
```

```sh
/path/to/luau assets/level5/window-watcher/roblox-integration/qa/test_window_watcher_schedule.luau
```

```sh
python3 assets/level5/window-watcher/roblox-integration/qa/test_window_watcher_lifecycle.py /path/to/luau
```

## Loop seam audit

Read-only comparison used the three actual `assets/level5/window-watcher/*-roblox-30fps.json` files and `animation-quality-audit.json` under this task. Every one of the 25 bones has numerically identical first/last transform components for all three clips: WatchingIdle 181 samples/6 seconds, SlowWindowLean 151/5 seconds, and GlassTap 121/4 seconds. Lean/Tap starts differ from Idle's start by at most 1.9e−7 and 1.6e−7 per component respectively. The authored audit reports zero root/foot drift and no issues.

Lean/Tap metadata says non-looping, but both return to the lowered-arm idle pose, so retaining `track.Looped = true` introduces no endpoint pose jump in the exported data. It also avoids a stop returning to the imported bind/A-pose. During an 8–14-second visit, lean repeats roughly twice and tap roughly two to three times. No one-shot-to-idle state machine is needed for this passive behavior. Native playback and final guard QA are tracked in the main handoff.

## Historical temporary native Edit verification — 25 September

All three clips were bound to the exact temporary native rig with KeyframeSequenceProvider and Animator stepping. Four times per clip, plus Idle with the alternative parent-pose hierarchy, yielded **400 passing bone comparisons**; worst matrix-component error was 0.0002191 (tolerance 0.001). Direct Root under Keyframe binds correctly. These tests use temporary Studio IDs, not published animation assets.

The white UV emission eyes were also inspected natively through tinted Glass, and the temporary preview/test fixtures were removed. Durable import and real-round playback followed on 26 September. Refer to the main handoff for current client visibility, cleanup, visual QA and publication results rather than treating this older temporary test as final delivery evidence.
