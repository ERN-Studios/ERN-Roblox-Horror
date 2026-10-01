# Lobby revision R4 — Blender prepared; Studio integration blocked

The actual Blender project is complete as an offline R4 revision. The last verified
publication was version2461 from the Level6 tube-arrival task; current Studio state
must be read again when its dispatch connection recovers.
**No R4 payload, Source change or PBR template has been installed in Studio. No R4
Play test or publication has occurred.** Studio's Lua dispatch, image upload and
native computer-control window observations currently time out. The app is still
running; it has not been killed or restarted with unsaved work at risk.

## Prepared assets

- `assets/models/lobby-reimagined-r4-20261001/LobbyReimaginedPreview.blend`:
  SHA256 `165712df68a47fe4811264f3e4801d09e5a876a4a8108a1a758b53e876c02259`.
  Six distinct level bays, four pads each, mounted doorway headers, double-sided
  projecting arrow signs, continuous rounded shell, raised DJ stage and steps,
  supported furniture block-offs, speakers/trusses and fixed pickup needles.
- FBX SHA256 `01c96f012c117b9042591f6fa3fe20b90349706306780a0072d2c66d77d6d9fa`:
  300 meshes and217804 placed triangles; finite tangents/binormals and triangulation
  verified for every mesh.71 runtime chunks,54 prefab families,66872 unique triangles.
- Concrete colour, OpenGL normal, roughness and real16-bit height images are
  packed into Blender. Normal-map relief is active; the matching height image is
  retained for optional bump editing, avoiding duplicate relief. Wall/asphalt UVs
  repeat every10studs; sidewalk repeats every8studs, with continuous shell UVs.
- `blender-concrete-detail.png` and the other `blender-*.png` images are renders of
  the actual authored scene, **not Studio screenshots**. Original bay texture IDs
  are pinned for Roblox. Their PNGs have not been extracted into Blender: offline
  bay renders currently show palette proxies, not proof of final carpet/textures.
  Queue monitor labels and holograms are implemented by runtime UI/controller,
  so blank offline monitors are not an interaction verification.

## Corrections and checks

Reversed inward box face winding; set precise analytic radial normals for the
rounded tube; removed connector/threshold coplanar floor flicker; corrected furniture
support stacks; replaced generic bays with level-specific shells and furnishings;
matched the four original pad centre coordinates and radius7.41; added large,
inward-facing wall monitors and sealed doorway returns. Offline audit confirms
all six entrances have continuous floors and clear3×5×3 clearance; all12 projecting
sign faces have clear sightlines from the two normal-height approaches. Client
readability still requires a Play check. See
`review/completed-r4-offline-audit.*` and `review/pbr-package-audit.json`.

Seven scoped Source candidates are under `tools/lobby_reimagined/r4_candidates`.
The five queue/controller candidates passed Luau compilation and nine lifecycle
mocks, including cancellation during the solo/final yielding Join. Actual Claude
Opus5.5/max review succeeded and was reconciled with Codex's final v6 fixes; a
separate Codex peer review passed. These are source/mock checks, not live gameplay.

Static published SurfaceAppearance templates are the chosen production PBR path.
The RuntimeBake candidate expects three templates with nine pinned image asset IDs
and allocates no PBR EditableImages. All nine IDs are still missing, so this path
cannot be installed yet. Mesh/props-atlas baking retains the existing proven runtime
pipeline. Original campaign levels1–3 and preview allowlists remain unchanged.
Levels4–6 use authorized developer party queues, not public campaign unlocks.
Bootstrap and QueueController are preserved.12°/s vinyl rotation respects the
existing ReduceFlashing setting; its enabled animation and fixed needles still
require an actual client Play check.

## Exact continuation

1. Recover the existing Studio window and verify the correct place131311258779917 /
   universe10559217407 / group1039373905 in Edit. Close any stalled save dialog.
   Do not restart Studio before preserving fresh unsaved native work.
2. Start the read-only receiver on127.0.0.1:8891 and execute its `/capture` script.
   It captures all current Sources/editor parity, services, collision/material
   settings and the complete native instance forest. Run
   `verify_r4_checkpoint_gate.py` to reconstruct/reopen the native place and verify
   the complete forest before `/checkpoint` becomes valid. A historical fixture
   passing is not a fresh checkpoint. No native-before files have arrived yet.
3. The image upload tool timed out after300s with no returned IDs. **Check Creator
   inventory for partial uploads before retrying.** Serve `serve_r4.py` on8896 and
   upload exactly its nine `/texture/{material}/{role}.png` routes. Save the returned
   URL-to-ID map and run `pin_r4_pbr_assets.py`; never invent IDs. Verify image access
   and moderation/rendering on clients before publication.
4. Re-read fresh Studio Sources, compare exact instance/class/Source/editor to the
   catalog, and reconcile concurrent edits against Studio. Rebuild the final
   catalog with `build_install_catalog.py --finalize`, then run `install_r4.py` to
   prepare a newly pinned installer. Refresh the package server. The present
   installer deliberately fails closed because all nine asset IDs are missing.
5. Peer-reviewed installer adds only the R4-owned ServerStorage payload and three
   static PBR templates; it performs seven exact Source/editor CAS updates after
   fresh full-native equality. It preserves all R3 payloads and ServerLobby. On
   failure it records attempts/current hashes and never blindly restores Sources.
   Published native baseline has no Edit Workspace.LobbyReimaginedPreview model;
   if a concurrently saved R3 model appears, inspect/preserve it before Build's
   early-return condition can accept it.
6. In actual Studio Play, walk both approaches to every gate, each bay and stage;
   inspect distant and close sign views, textures/grazing normal relief, seams,
   ceilings, steps, collision clearance, furniture and speaker support. Exercise
   host/privacy/capacity/countdown/cancel/exit/launch, hologram upward fade, vanilla
   levels1–3 and authorized queues4–6; verify group rollback/streaming with actual
   clients. Inspect slowly spinning discs with ReduceFlashing=false and fixed
   needles. Check replicated PBR assets, shop focus/art and reset-owned resources.
   Capture actual final Play screenshots and fix/repeat any failures.
7. Export fresh verified Studio/native after state, compare only seven scoped
   Source changes plus the additive payload/properties, preserve all unrelated
   developer work, commit the exact task diff, then publish to the existing place
   and verify Roblox's publish success. Do not publish with material blockers.

No Git remote is configured. The unrelated modified cathedral `.blend` remains
untouched. macOS FileProvider/iCloud dataless files sometimes time out on reads or
reject overwrites; local `/private/tmp` caches may be used with exact SHA verification
without changing Studio or cloud settings.
