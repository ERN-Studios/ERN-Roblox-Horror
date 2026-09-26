# Level 5 surface and padlock fixes — 2026-09-26

Level 5 had overlapping wall/floor faces and a padlock that opened in PC first-person with the pointer still hidden and locked. The scoped changes remove competing surfaces, give the padlock immediate free-pointer control, and remove its dark full-screen backdrop.

## Changes

- Architecture assigns ownership to shared side-wall intervals, separates overlapping horizontal carpet/ground surfaces by bounded layers, and insets competing foundation faces. Interior ceilings use plaster instead of the incorrect carpet material. Authored stairs, sloping chute and tilted geometry remain unchanged. Watcher floor anchors follow the actual supported carpet top.
- Watcher validation accepts a finite `SurfaceLift` from 0 to 0.48 studs, with missing values treated as legacy zero. Pane orientation, actual feet support, clip-depth bounds, source SHA and permanent animation checks remain in force.
- `RoundUI`, the existing sole cursor owner, now recognizes `Level5ColourLockOpen` immediately and while rendering. The padlock keeps an active transparent input blocker and its readable panel. Character replacement and external GUI closure reuse normal modal cleanup.
- Removed the exterior “HOUSE CLUE” paper tags on later clue homes. The actual indoor clue panels, puzzle solutions and progression remain intact.

The same seven existing material variants—plaster, floral wallpaper, siding, lawn, veneer, roof shingles and carpet—are reused. Final native material receipt confirms all seven remain present (11 total variants including Level 2/default entries).

## Verified native evidence

The [compact artifacts](../artifacts/level5-surface-ui-fixes-20260926/README.md) preserve the raw reports and three screenshots.

| Check | Result |
|---|---|
| Original real E-prompt failure | UI open; `LockCenter`; cursor icon hidden; backdrop transparency .28 |
| Patched actual PC input | Wheel clickable and gate 1 solved through its real puzzle controls |
| Native cursor observer | PASS; 1,134 open frames; two opens/two closes; zero failures |
| Cursor restoration | Both settled close snapshots: GUI disabled, modal false, first-person `LockCenter`, icon hidden |
| Final native map audit | PASS; 18,168 rays; zero failures/warnings; no budget truncation |
| Shell and routes | 3,542 shell rays; 133 route segments; 1,087 sampled supports/clearances |
| Watcher anchors | PASS; 18 anchors across all 8 districts, 402 additional structural probes |
| Actual room walking | B and F: five waypoints each, 38.77 / 41.08 studs; entry → interior → exit; F carpet lift .36 studs |
| Runtime errors | No `LogService` MessageError observed in the checked round |
| Surface audit (offline) | Exact floor-top candidates 252 → 0; vertical faces 9,238 → 129; undersides 450 → 218 |
| House lighting/window checks | 1,086 tinted windows; no house lights or house Neon |

Local scoped cursor-policy tests passed 12 assertions, and the SurfaceLift bounds tests passed 13. All five changed production files compiled; nine surface-audit unit tests passed. Source inspection and mocked tests are recorded separately from native results.

The final audit sampled all seven gates in their closed state; a separate real first-gate solve does not prove every open-gate state. The two room walks used actual Humanoid MoveTo without teleporting between waypoints, forced jumps, speed changes or gate changes; they do not prove other paths. Structural rays are not full-volume proofs or actual traversal of all routes. Escape was **not** verified because tool input could not deliver that key. No physical-mobile, controller, multiplayer or every-death/reset-path claim is made.

## Verified delivery checkpoint

- Final native round-three audit: **PASS**, 18,168 main rays, zero failures; 18 Watcher anchors passed separate structural probes.
- All **192 scripts** match final Studio Source, editor source and repository; **five changed**, **187 unchanged**, including all **12 Level 4 scripts**.
- All **seven existing Level 5 image-generated MaterialVariants** retained; no replacement material assets.
- Full native backup: [`after.rbxl`](../artifacts/level5-surface-ui-fixes-20260926/after.rbxl), **9,793,957 bytes**, SHA-256 `014d75e52f27a296b84a2df0a12a7cfa21617d7988ce37eddc47b8aece0915f8`.
- Roblox publication **v2139**, verified native success log at **2026-09-26 20:01:51.250 UTC**.
- Git record: the containing commit carries the verified Studio mirror and evidence; delivery is tracked in [PR #10](https://github.com/ERN-Studios/ERN-Roblox-Horror/pull/10).

The remaining 129 exact vertical and 218 underside surface candidates are not a claim of zero possible pixel-level flicker. The final offline review found no new exposed material-changing conflict; most remaining groups concern matching-material shell/slab/furniture joints or buried undersides. See the [surface audit summary](../artifacts/level5-surface-ui-fixes-20260926/SURFACE_AUDIT_SUMMARY.md) for classification and limits. The 626 near-floor pairs are intentional or buried joins, including stair tread/riser pairs, not 626 exposed floor defects.
