# Level 1 facelift verification — 2 October 2026

Studio is authoritative: place `131311258779917`, universe `10559217407`,
session `86f22f6f-aafa-4af2-b2dc-cf471bf0e3a4`. The task was installed against
fresh Source/editor baselines with exact comparison inside each existing-script
write. Final exported sources match the five repository mirrors and their
editor sources. Existing R4 queue changes already present in live GameManager
are preserved in the mirror; they were not reapplied from Git.

No native place or Blender backup was taken, following the owner's instruction.
The task's temporary runtime QA Script was inspected and removed from Edit
before release. Unrelated dirty files, including concurrent Level 4 work, were
excluded from the task commit.

## Assets and offline checks

- Native Blender project/FBX verified: 34 room collections, 30 shared authored
  components, 61 exported mesh/material chunks and 11,036 total triangles.
  All nine native texture references are portable relative paths.
- Actual group-owned uploads: 61 mesh assets and nine PBR image assets.
  Three materials use shared albedo, normal and roughness maps.
- Final Studio kit export: 1,215 instances, 39 component models including
  aliases, 34 room models, 498 MeshParts, 176 SurfaceAppearances, 51 explicit
  detail colliders. Ready and Complete are true; all asset ID sets match receipts.
- 95 actual-function/lifecycle checks pass: 51 renderer/GM, 26 access gates,
  six host lifecycle and 12 authorized native-prompt lifecycle assertions.
  The complete unauthorized client creates no prompt. Source compiles with
  official Luau 0.737. The original topology block is unchanged.

## Actual Studio Play evidence

The Level 1 room's native developer E prompt, copied from the current Level
4–6 interaction, launched the real round. It has hold duration 0.5, range 10
and no line-of-sight requirement. The whole prompt is created locally only
after central DevAccess authorization; server and destination independently
check authorization. The exact strict developer list contains 40920547 and
9488575949; the separate Level 6 guest exception is excluded.

Two different generated preview rounds each contained 1,600 authored rooms.
Their socket graphs had 2,068 and 2,087 open edges. All reciprocal openings,
borders, connectivity, asset provenance, PBR maps, objective population and
pit-floor visibility checks passed. All three bounded engine navigation samples
(relay, fuse box, lever) succeeded on each layout, with 92–124 waypoints in the
first and 98–105 in the second. Raw receipts are under
`artifacts/level1-facelift-20261002/runtime-round-*.json`.

The first round ran with the entity active. Entity grid learning, death/result
and teardown occurred; Maze, preview flag and room-count state were cleared.
The second round used the existing developer P pause and QA character placement
near objectives. Actual E interactions extracted the fuse (ContainsFuse false,
CarriedFuseVisual present), inserted it (Powered cable, ALERT, lever enabled),
and pulled the lever (finale speed 1.3, POWERDOWN then ESCAPE). Actual character
navigation into the exit trigger set Escaped and moved the participant to the
safe cabin. The preview ended and returned to the lobby with no Level 2
continuation. This was an assisted single-player loop check, not an unassisted
playthrough or multiplayer certification.

The normal public station was also tested through its actual Create Party UI.
It reached RoundActive, WorldGenerated and DecorReady, with preview false, no
BlenderRooms folder, zero preview meshes and seven original objective children.
Its original NORMAL lighting state remained active.

## Limits and release scope

The twelve-sample Heartbeat averages were 16.64 ms and 16.61 ms, maximum 19.65
ms and 18.56 ms. This is timing evidence, not CPU profiling. Studio total memory
was approximately 4.77–4.78 GB during the preview and 4.59 GB during the public
round; it includes the existing Studio place/session and is not a standalone
published-server memory budget. No mobile/GPU or multiplayer performance pass
is claimed.

Published reserved-server transfer cannot be exercised inside Studio and remains
unverified end to end. Destination authorization and packet handling were
independently reviewed and source-tested. The facelift is available through the
developer preview; normal campaign admission remains unchanged. No observed
material blocker remains for this developer-preview release.

Published through Studio's File > Publish to Roblox. Roblox confirmed
“Published new changes … to Roblox” and “Published. Eligible players can play
now.” Post-publication checks still match all five source fingerprints and
editor pairs, Ready/Complete, 39 components and 34 rooms. No temporary QA Script
remains. The newly published cloud version number was not reported; the loaded
Edit version 2470 is not treated as that number.

Implementation commit: `a37bc1b56b9ed6e54b557d78922a73e4720beee8` (local).
No GitHub push or active-server restart was performed. Publication receipt:
`artifacts/level1-facelift-20261002/publication.json`.
