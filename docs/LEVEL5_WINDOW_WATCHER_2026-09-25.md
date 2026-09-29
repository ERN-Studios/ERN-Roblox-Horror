# Level 5 — Window Watcher and reference courts

## Published delivery — 26 September 2026

**Window Watcher, the revised F courts and the gaze heartbeat are published as v2123**, place **131311258779917**. The latest native File → Publish to Roblox succeeded at **2026-09-26T12:35:15.298Z**, with a successful publish request and “Add publish notes to v2123”. See the [final delivery manifest](../artifacts/level5-window-watcher-20260926/gaze-delivery.json) and [publish receipt](../artifacts/level5-window-watcher-20260926/gaze-publish-receipt.log). The original rig/encounter integration was published as v2121 at 12:17:16.432Z; its preceding evidence below retains that scope.

The permanent rig, three published clips, intermittent encounter module, Adapter hook and client visibility guard are installed. Her eyes emit white light on the skinned iris surfaces. Developers can encounter her occasionally in the three F windows through the existing Level 5 developer queue; public Level 5 access remains restricted. No chase, damage, sounds, puzzle, slide control, rewards or completion behavior was added.

Git review and the final push receipt are tracked in [PR #10](https://github.com/ERN-Studios/ERN-Roblox-Horror/pull/10), stacked on the previous Level 5 QA work. The [Level 5 Trello card](https://trello.com/c/Y2xXThBN) retains the remaining gameplay work. Publication confirms delivery of the current place; published-server permissions and human multiplayer have not been independently tested.

## Durable assets and source provenance

The mesh and three animations were published for ERN Roblox Studios, group **1039373905**. The existing image assets are reused; no transfer of image ownership is claimed.

| Asset | Roblox asset ID | Duration |
| --- | --- | --- |
| Skinned Window Watcher mesh | `138178192370575` | — |
| Original base-color image | `91091934459636` | — |
| White-eye emission mask, v5 | `91743869995723` | — |
| WatchingIdle | `123386867650430` | 6 seconds |
| SlowWindowLean | `85635358459792` | 5 seconds |
| GlassTap | `85948818863545` | 4 seconds |

Meshy image-to-3D task `01a0d8e3-3fdd-752a-b810-ea9cace0266e` cost 15 credits; rigging task `01a0d8ec-0c4f-71fc-b513-af1e1d1e59b4` cost 5. The authorized Meshy CLI and local Blender 5.2 `bpy` pipeline were used. All three gestures were authored in Blender without paid Meshy animation tasks. No credentials or expiring download URLs are included in the repository.

The source model is 2.4 metres tall, with 11,862 triangles, 8,968 Blender vertices and 25 bones. Its serialized GLB has 8,996 vertices because normal/UV seams split vertices. Original bone names are retained; an unweighted Root was added and an unrelated helper removed. Skin weights are normalized with at most four influences. There are no finger bones; tapping uses hand/wrist motion. Reimported GLB/FBX and all clips preserve the rig and motion, with planted feet/root and matching loop endpoints.

Frozen GLB SHA-256: `cbf260ff36b8c7226f27271456eae6bf4db7fd266bdce82dda8b0eae7cbc051e`.

Editable `.blend`, GLB/FBX files, animation FBXs, source references, original texture, 30 fps pose data and Blender scripts are in `assets/level5/window-watcher/`. The [integration package](../assets/level5/window-watcher/roblox-integration/README.md) records transfer and recovery procedures. Older files under its `patches/` directory are historical proposals; authoritative Studio source mirrors contain the installed implementation.

## White eyes, placement and encounter behavior

The installed rig is eight studs tall, faces local −Z and has a floor-origin pivot. Vertices and mesh-world bind frames were centered together; runtime Bone frames and animation translations use the actual serialized GLB bases. Do not resize only MeshPart.Size or invent a new bone-axis conversion. The template is `ServerStorage.Level5WindowWatcher.WindowWatcherRig`, with sibling published `Animations`.

White eyes use a SurfaceAppearance emission mask, white tint and strength **200**. The approximately 0.067-stud iris cores follow the skin directly, without eye GUI, extra geometry, physical lights or an eye update loop. Whole-mesh hiding also hides the emission. The original dark albedo and model geometry are unchanged. Billboard eyes were rejected because tinted glass occluded them.

Mask SHA-256: `99315f05889bbc4c9f1122f502913bef7bf3fd5d7742b2a5a30ded79fee45738`. Its targeted guard around neighboring brow UV islands retains 98.34% of the mask energy. The native Play image `artifacts/level5-window-watcher-20260926/native-guarded-glass-tap.png` shows a dark body and white eyes through the actual pane with the hand raised. No obvious brow fleck is visible at that normal viewing distance; this is not immunity to every filtering artifact or a guarantee at every distance/device.

One noncolliding actor appears at a time. A living Level 5 participant in F starts a 2–4-second first-appearance delay. Eligible panes face a participant and have a clear ray to their real glass. Visits last 8–14 seconds, followed by 18–35-second hidden intervals; another eligible pane is preferred when available. Leaving the eligible audience hides the actor. World cleanup owns and removes the encounter and its tracks.

Placement uses `pane.CFrame * CFrame.new(1.1, -6.55, depth)`: depth 0.95 studs for Idle/Lean and 1.90 for Tap. The lateral offset avoids the center mullion. The authored full-mesh tap extrema reach −1.745002 studs forward, leaving about **0.084998 stud behind the pane's rear surface**. Native pose comparisons and the inspected complete gesture support this placement; the runtime observer does not measure every skinned vertex against glass on every rendered frame.

The server controls timing and official Animator playback. A scoped client guard keeps the owned actor locally hidden until the matching published track has positive Length, advances across frames and evaluates a non-bind pose. It changes local transparency rather than Bone.Transform, camera or server state. This fixes a brief loaded/unevaluated pose exposure found in the first client run.

## QA results and their limits

All **300 published-asset bone/time comparisons passed**, with maximum matrix-component error below 0.000194 against tolerance 0.001. These use the durable clips. The earlier 400 temporary-ID comparisons remain historical binding evidence. The original draft's 1,031 scheduler and 29 mocked lifecycle assertions retain their original source-version scope.

The final native server and client observers each recorded **zero failures, all three moving clips and five complete appearances**. Both reports deliberately remain **INCOMPLETE**: their 180-second observation deadlines arrived before normal round cleanup. They have not been relabeled PASS. Evidence is `final-native-server.json` and `final-native-client.json` in the final artifact directory.

A separate focused `cleanup-reentry.json` supplies that missing lifecycle observation: one active track before leaving through the normal round-return flow; zero tracks afterward; then the old actor, owner and world were removed. The client still held the old world at the three-second sample while RoundActive was false and tracks were already stopped; the settled sample confirmed all old instances removed. Re-entering through the real developer queue created a fresh world and actor, with one playing track and client guard status VISIBLE.

Client guard diagnostics recorded 3,156 display frames and five warm-up-hidden frames across 10,804 pre-render observations. Observer callback order is not guaranteed to run after the guard in each frame, so these counters are diagnostic sampling, not proof of final raster output on every frame. Native inspection and the saved real-window capture provide the separate visual evidence.

Fresh source/editor parity covers **184 scripts with zero conflicts**, and **184/184 scripts compile**. The final source parity and compile evidence accompany the runtime reports. Physical mobile/tablet performance, two-account human multiplayer and published-server asset permissions remain untested. Earlier first-run failure reports are preserved as regression evidence, not substituted for the final results.

## Reference area F and preserved vision

The former tall canyon is replaced by **33 nested domestic houses around three connected carpet courts**. Floors at 0/15/30 studs, continuous white balconies, two switchback stair circuits, short bridges, sage/rose/oatmeal façades and dark gabled roofs follow the Window Watcher concept. One shared office ceiling sits at 60 studs. Houses retain dark tinted glass and have no individual Lights or Neon. Three F mold carriers were resized for the lower enclosure. The Backrooms' origin is unknown; Zyntra is the researchers' organization, not the creator of this space.

The map before actor installation contains 11,372 BaseParts, 12,240 descendants, 44 lights and 202 tinted panes. These map-only counts exclude the runtime actor. Canonical comparison confirmed A–E, G and H match the preceding map baseline; outside F only the three named mold carriers changed. The existing Level 4 and other developer's work are preserved.

Earlier native map QA passed 44 actual Humanoid movement segments, 77 open-home checks with 462 entry rays, and 98 chute enclosure rays. No required jumps or noclip were used; only the starts of separate routes were positioned. The furnishing rerun passed 20 homes, 891 furniture parts, 7,128 corner checks and 72 mold backing rays, with no house lights or Neon. The existing access/transport check passed 74 assertions. Those results retain their map-test scope.

## Source preservation and backups

The fresh 26 September baseline matched repository checkpoint `c6109d5`: 182 scripts, no Source/editor conflicts. Git audit found no newer remote commits; the other developer's branch remained at `a8259d3`, including Signal Architect Ascendant. The integration then changed exactly three source paths relative to that baseline:

- `ServerScriptService/Level 5 Systems/Level 5 Window Watcher Encounters.ModuleScript.lua` — new server encounter module.
- `StarterPlayer/StarterPlayerScripts/WindowWatcherVisualClient.LocalScript.lua` — new scoped visibility guard.
- `ServerScriptService/Level 5 Systems/Level 5 Round Adapter.ModuleScript.lua` — encounter hook.

The preceding F-map changes remain represented by the existing Architecture and Landmark Districts source mirrors. All unrelated scripts, including the 12 Level 4 scripts and the other developer's work, are preserved.

The full native **before-integration** backup is `output/level5-window-watcher-20260926/baseline/Backrooms-pre-WindowWatcher-20260926.rbxl`: **9,637,458 bytes**, SHA-256 `eaf5a42d710113999c8661f314d4ef102666558d36a5e9b041b229b763e10fa9`.

The full native **after-integration** backup is `artifacts/level5-window-watcher-20260926/after.rbxl`: **9,763,745 bytes**, SHA-256 `be9d81da45369de47e484c451bd9e18da38c8011d5ef4a8f6e349680d9557de0`. It preserves the permanent rig and animation references as well as the source. Dated 25 September preview/checkpoint evidence remains unchanged; the 26 September artifacts and v2121 receipt describe the delivered integration.

## Additional 26 September request — gaze response

This follow-up is published as **v2123** at 12:35:15Z on 26 September. All **186 scripts** compile and match their Studio/editor sources; 183 remain unchanged from the v2121 integration. The full final backup is [after-gaze.rbxl](../artifacts/level5-window-watcher-20260926/after-gaze.rbxl), 9,767,008 bytes, SHA-256 `8b0074fd9b92a8fb87f6fb2563b3b888bcc961dbcc94f72769ce58e2100b1841`. The v2121 receipts above retain their historical scope.

`ReplicatedStorage.WindowWatcherGazeLogic` and the `WindowWatcherGazeClient` LocalScript add a local stare response. A direct stare within 12 studs uses a per-appearance random threshold of 2.5–4.5 seconds; this grows to 5–8 seconds at 100 studs. Gaze influence is full within 8° of the face, fades to zero at 30°, and fades with distance from 100 to 145 studs. Normalized exposure accumulates while looking and decays by 0.20 per second when looking away. Reaching the threshold hides her for that client until the next server appearance counter. The visibility guard respects the client-local `WindowWatcherGazeHidden` attribute; the server encounter and other clients are not changed.

A heartbeat-shaped camera pulse varies from 60–105 beats per minute, with at most 1.5° inward FOV change and smaller outward rebounds. It respects ReduceCameraShake, ReduceFlashing, menus and non-Custom cameras, and restores its own FOV contribution on exit. No audio or damage is added.

The pure helper passed **11,297 assertions**. The native test in `artifacts/level5-window-watcher-20260926/native-gaze-result.json` reports **PASS_OBSERVED_CHECKS with zero failures**. At the actual MiddleCourtWindow, the test began 11.6 studs away with a 2.6437-second threshold, then exercised approach, direct gaze, looking away and renewed gaze. Local disappearance occurred 3.997 seconds into that mixed sequence; server visibility stayed true and one official animation track continued. The mesh was locally hidden with LocalTransparencyModifier 1. FOV ranged from 68.54485° to 70.70368° and returned to 69.999985° after exit, effectively the 70° baseline. This focused gaze result supplements the earlier runtime/cleanup evidence; it does not change those observers' historical INCOMPLETE status or add physical-device or human-multiplayer coverage.
