# Level 6 tube arrival — authoritative Studio revision

Level 6 now enters through the outlet of an authored Poolrooms tube into a tall orange landing room, matching Level 3's arrival landmark. Its existing developer-preview entry, streaming floor acknowledgement, participant join and lobby return remain intact.

Only five fresh live Sources changed: World Builder, Layout Generator, Visual Adapter, Level6PreviewAccess and the client Level6PreviewTransport. Each exact class, Source and editor Source was checked before writing, rechecked inside UpdateSourceAsync, and checked again after Play. No repository script was used as a deployment baseline. Native-before captured all authoritatively serializable service children before these edits.

The tube uses the current Level 3 static geometry: 400-stud curved run, 115-stud rise, 16-stud bore, 32 longitudinal sections and 20 shell panels per section. The rear cap is widened to 17×17 to close the reference cap's outer slivers. All objects are owned by Level 6. Its marker is six studs before the outlet, based on the first runout plane, facing toward the mall. Arrival alone is raised from 12 to 30 studs; its Blender wall skin now uses the orange palette and retains the confetti carpet. The tube's shell, aperture seals and notice are exempted from the adapter's legacy visual hide pass.

The client receives a one-shot camera facing notification only after a successful authorized join. It waits for the actual character to reach the Level 6 target, preserves Custom camera control, handles generations and does not change return transport.

## Actual Studio Play verification

Test account: ZenMeister02. Deterministic Play-only seed: 1135645734. Root used the real visible E prompt and normal character physics, with actual screenshots. Early MCP navigation reports moved the server without the local client; those were rejected as walking evidence. Subsequent client Humanoid walking and real keyboard W/E verified the visible character.

| Check | Actual result |
|---|---|
| Initial real E entry | Inside the final six studs, upright, facing +X toward the room; health 100 |
| Stationary after entry | Running, PlatformStand false, essentially zero drift |
| Keyboard W across tube mouth | Walked onto the carpet without jumping or snagging; health 100 |
| Opposite doorway and corridor | Normal walking to X=20042.21; service corridor remained accessible |
| Side edges at +7.5, +6.5 and −6.5 studs | Shell/wall safely blocked the attempted side approach; player stayed grounded with health 100 |
| Return from tube | Real E returned to the lobby and cleared Level6InRound |
| Repeat real E entry | First-person camera still faced into the room after three seconds; upright, health 100 |
| Existing blackout and recovery | Observed during repeat entry; lighting recovered normally without a source change |
| Generated world | 32 rooms, 37 corridors, floor area 180088, Atomic tube, NO EXIT / ONE-WAY ARRIVAL enabled |
| Floor acknowledgement | Owned tube shell hit at Y=24.1557 with normal.Y=.98765, passing the existing .7 threshold |
| Seed comparison | 64 generated layouts validated; old/new deep comparison differed only in Arrival.H and its derived layout hash |

All five candidates independently compile. Codex reviewed exact diffs and actual images. Claude Opus 5.5/max supplied a focused design response, but its CLI reached its time bound; this is recorded truthfully, not described as a complete Claude approval.

This recreates the Level 3 arrival landmark and an upright walk-out spawn. Production Level 2 → Level 3 progression, the existing slide/ragdoll controller and GameManager were preserved; a full resumed Level 2 ride into Level 6 was not added or claimed. Multiplayer and mobile were not separately tested. Full native backups and whole-place comparison receipts record the authoritative recovery state; the native place reconstruction has explicitly recorded unreadable/unsupported engine-property limits, with the raw native forest retained locally.

Final screenshots are actual Play captures in `screenshots/`, including end-of-tube spawn, the room looking back at the tube, and the forward corridor. They are not generated concepts.

Published to the existing experience as version **2461**, confirmed by Studio's successful-publication log at 2026-10-01 21:17:04 UTC and Creator Hub's Published Version checkmark. No active servers were restarted. The repository has no configured Git remote; the task commit is local.
