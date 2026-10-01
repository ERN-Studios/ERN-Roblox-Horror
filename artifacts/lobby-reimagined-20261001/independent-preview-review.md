# Independent preview implementation review

Final R2 was reviewed without changing Studio, Play mode, camera, input or game
state. The one delegated implementation edit was the furniture-placement block
in `tools/lobby_reimagined/build.py`; the exact scoped review is recorded in
`furniture-grounding-local-qa.json`.

The checked manifest SHA256 is
`9e25ce55ccfd8aec36878770967c83f6b1eb72676f9c783c562b5864ab333c3c`.
Its source Blender SHA256 is
`cef02885bc8b4aa34c3ca21d3d9eb3eac39fa257c67da1e5284a09d39dd10141`.
The live Server Play preview reported that same Blender hash.

The earlier runtime Source receipt and local syntax rows below describe R2
before the final Builder readability adjustment. The final Builder is 9,162
bytes with SHA256
`8d808c569101432309f954d5a0f33f48ba4e1b115831b4877e064ca56c0be921`.
`final-builder-delta-verification.json` proves that only the sign canvases and
local tunnel-lamp color/brightness changed from the independently captured R2
Source. Geometry and floor checks remain applicable. Fresh final Edit
Source/editor exports are in `verified-studio-source/manifest.json`; all four
captured final Sources compile in `final-captured-source-syntax.json`.

## Verified

- All 34 raw mesh chunks and the 4 MiB atlas match their hashes and byte counts.
  Mesh indices and UVs are in range, coordinates are finite, and all 45,384
  unique triangles are nondegenerate. Four final Luau Sources compile locally;
  candidate scripts were not executed locally.
- Actual exported placement geometry fits the previously checked side-preview
  envelope: X128.850–311.150, Y29.000–67.100, Z−900.055–−619.945. Both speaker
  towers have 3.802 studs of clearance to the nominal inner shell and 2.702 to
  the nominal rib profile above Y8. This uses actual vertices rather than the
  towers' maximum-width bounding boxes.
- All twelve furniture columns now start on the appropriate road or sidewalk.
  Twenty upper placements overlap their preceding bounds by .15 stud; far
  central singletons are grounded. The old fixed-height gaps are removed.
- The live Server Play collision audit executed 1,911 downward rays across all
  six gate approaches and the stage stairs. No sampled gate floor was missing,
  and the final step joins the deck continuously at height 4.5. The approach
  levels are approximately .80, 1.10 and 1.16 studs.
- All four live Server Play preview Source hashes match the final local files.
  The ready model is owned, atomic, and explicitly marked as an isolated design
  preview with real level launches disabled. It has 24 demo prompts and 240
  noncolliding, nontouching, nonquerying hologram bands. The original
  `ServerLobby` is present. The cloned shop reference has no enabled interactions
  or interactive part properties.
- Source review confirms corrected two-sided blade arrows, open doorway
  conduits, shell collision proxies, wider thresholds, round pad collisions,
  deferred station animation registration, tween cancellation, elapsed-time
  vinyl motion, and still rendering while the motion preference is unknown.

The detailed receipts are `independent-local-qa.json`,
`floor-path-play-receipt.json`, `runtime-contract-play-receipt.json`, and the
bounded query `floor-path-readonly.luau`. The separate FBX fallback round-trip
receipt is `blender/fbx-fallback/final-roundtrip.json`; that check was performed
by the props agent.

## Limits and accounting

The manifest's 153,004 instantiated triangles count 254 static placements. The
24 runtime rings and 240 bands add 43,008 triangles, giving 196,012 prefab mesh
triangles before cloned shop or native Part geometry. With all bands hidden,
static placements plus rings total 165,292; one active pad adds 1,152 visible
band triangles because its highest band is fully transparent. These counts are
geometry accounting, not performance measurements.

The hologram currently uses ten alpha bands, so its upward fade is stepped.
Furniture bounds contact is not a rigid-body support simulation. Floor rays
are not Humanoid navigation or gameplay tests. This audit does not claim E
input, timer/cancel interaction, multiplayer, mobile, rendering performance,
cloud publication, Edit Source/editor parity, or unchanged original non-script
objects; those require the parent's separate live checks and authoritative
backup/scope receipts. Blade mounting is close to the rib profile and should be
judged using the actual close-up render.
