# Level 1 elevator inset + entity audio: Claude Code QA and fixes (2026-10-04)

This continues `CLAUDE-HANDOFF.md`. The revision is **installed in the authoritative Studio and committed locally. It is not published.** The reason it is not published is in "Publication" at the end.

## Scope reminder

The Blender elevator path (`Level1ElevatorInsetKit`, `BlenderRoomRenderer`, and the `blender` branch of `MazeGenerator`) only runs while `workspace.Level1BlenderPreviewActive` is true, which means the developer preview. Public Level 1 rounds still build the legacy elevator. For public players, the only change in this revision is the `SoundController` entity audio.

## Studio state at takeover (15:58 UTC)

- Only the primary Studio process was running. The three stale local Server & Clients test windows were already gone.
- Studio was in EDIT with no Play.
- MazeGenerator, BlenderRoomRenderer and SoundController matched their mirrors byte for byte, with Source equal to the editor Source.

## Fixes made (all Studio-first, then mirrored)

1. **Steel tint.** In the first Play capture after Codex's 205/211/217 retint, the cabin read cream-white (wall sample 233,228,212). The tint was set first to 145/151/160 and then finally to **175/181/189** on all 72 kit steel SurfaceAppearances.
   - The look depends on Studio's automatic render quality. At high quality, 205 reads light gray (about 165) and 145 reads mid gray (about 124).
   - 175 stays light gray at both levels.
   - Record: `claude-tint-receipt.json`, `claude-qa/evidence/tint-compare.jpg` (low quality) and `hq-tint-compare.jpg` (high quality).
2. **Cabin side walls were turned inside out.** This was found by the adversarially verified review (workflow `wf_e4b22586-77d`) and confirmed on live runtime bounds.
   - The 32 `CabinWallModule` placements had reversed yaw. The steel sat 0.5 studs inside the 12-stud interior, in front of the colliders, with the seams on the hidden face. Both the kit's control panel and MazeGenerator's floor selector were buried inside the steel.
   - Each module was turned 180 degrees about its own pivot. The steel is now flush with `CabinSideA`/`CabinSideB`, the seams face inward, and the panels are visible.
   - The build script and the manifest are fixed. The new manifest SHA is `68dcba4e…` and the kit's `ManifestSha256` attribute is updated to match.
   - The `.blend`, `.fbx`, renders and native verification still show the old yaw. The meshes are unchanged, so no re-upload is needed.
   - Record: `claude-sidewall-receipt.json`.
3. **MazeGenerator** (scoped CAS through `apply_scoped_patch.py`; record in `claude-maze-receipt.json` and `claude-maze-*`):
   - The old doorway `sill` is hidden in blender mode. Its front face z-fought with the kit's own steel threshold.
   - The exterior is now pivoted 0.03 studs proud of `x1`. The elevator shell walls' wallpaper end faces lay on the same plane as the facade.
   - Live hash went from `a0d89927…` to `b2915a53…`, with Source equal to the editor Source.
4. **studio-sync-manifest.json.** The entries for the three owned scripts had been stale since before v2646. They now record the verified mirror hashes.

## Actual Play QA (owner account, real preview prompt, native E holds)

The preview was launched by holding E at the `QueueBay_Level1` pedestal. Firing the remote from `execute_luau` is blocked by capabilities.

| Check | Result | Evidence |
|---|---|---|
| Current-kit runtime probe (`claude-qa/elevator-kit-qa.luau`) on two different generations | 18/18 pass (68 and 84 cable segments) | `r2-elevator-kit-qa-2.json`, `r3-elevator-kit-qa.json` |
| Open doorway | 7.2-stud clear gap, no collider in the lane. The actor walked out of the cabin with real navigation. | probes above |
| v2646 structural regression (`qa-runtime.luau`) | 121/123 | `r2-readability-regression.json` |
| C, then B, then A lighting, then ALERT | Each stage passes the client lighting probe. Elevator fills are off in ALERT. | `r3-stage-C-client.json`, `r2-stage-B/A-client.json`, `r2-alert-client.json` |
| Puzzle loop | 2 relays, fuse box, lever, ESCAPE. The actor walked through the exit with navigation, giving `Escaped=true` and a win. | console and probe outputs |
| Reset | Pass: no kit clones remain, the entity is stored, the kit is intact; regression reset 2/2; client reset 3/3 | `r2-reset-*.json` |
| First-use spot scream (the open blocker) | Pass. The first spot of the session came from `Entity.HumanoidRootPart` at 24 studs: loaded within 0.3 s, TimeLength 4.81, TimePosition 0.02→0.72→1.73→Ended. The capture sound also loaded and played. | `r3-audio-client-natural-spot.json`, `r3-audio-server-natural-spot.json` |
| Asset preload on the owner client | Spot, capture and death all report `AssetFetchStatus.Success`, about 0.35 s each | `claude-qa/asset-probes-result.json` |

Notes on the results above:

- **Regression 121/123.** The 2 failures are outdated v2646 expectations. All 32 "provenance" meshes are the new inset kit's own meshes inside `Workspace.Elevator`; the other 22,186 meshes are V2 with full provenance. The 2 "PBR" pieces are the renderer's deliberate steel override.
- **Audio.** Codex's `IsLoaded=false` result came from the local multi-client test (UserId -1), not from the game.
- **Puzzle loop assistance.** Actor placement in front of each prompt was assisted, and the Entity was paused with the developer P key.

Final images (high render quality, tint 175) are in `claude-qa/evidence/final-*.jpg`.

## Open items for the owner (preview-only; none affects public rounds)

- **Light bleed at low render quality.** The cabin's own lamps (linear lamp 2.15 / range 22, cabin fill 1.05 / range 20) bleed through the 2-stud facade. At Studio's lower automatic quality this turns the wallpaper facade lemon-bright: 246,222,34 against walls at 139,110,28. With the lights off it measures 122,91,0. Moving the lamp or shortening the ranges only roughly halves the effect and changes the approved cabin light, so it was left alone.
  - Evidence: `lowquality-exterior-cabin-light-leak.jpg` and `lowquality-exterior-cabin-lights-off.jpg`.
  - At high quality there is no bleed: `final-exterior-open.jpg`.
- **Two panels by the door.** The authored control panel and the legacy floor selector now both show by the door.

## Publication

Not done. The preservation audit (`preservation-comparison.json`) found nine foreign scripts and one asset root changed in Studio since the 13:48 baseline:

- Scripts: `ZyntraConfig`, `Found Footage HUD`, `Lobby DJ` (server and client), `LobbyReimaginedPreview.Builder`, `Level5PreviewAccess`, `Level 5 Lighting Controller`, `Level 6 Playground Game`, `Level 6 Dev ESP`.
- Asset root: `Workspace."Level 5 Void"`.

None of these is mirrored in the repo. Publishing the place would ship them live. That needs the owner's decision, or the other sessions' handback, first. SoundController is listed in that file only because it was moved into the owned set after the baseline. When publication is approved:

- Publish with **File → Publish to Roblox** (it opens the "Publish with version notes" dialog).
- Confirm the Output line `Published new changes …`.
- Then migrate outdated servers only.
