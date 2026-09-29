# Level 5 rework baseline — 2026-09-27

## Source and recovery

- Authoritative Studio place: `131311258779917`; universe: `10559217407`.
- Studio instance inspected in Edit mode: `e7dbf962-5b02-4de6-9494-ef440fb543aa`.
- The five current Level 5 runtime ModuleScripts in the tracked checkout were byte-identical to their live Studio Source and ScriptEditorService editor source before rework.
- Native pre-rework place copy: `pre-rework-place.rbxl`, SHA-256 `9ba32d34ba3daababc203ae6e88f028af0918344c4a0df5231223f9164b649eb`.
- The user's original directory was preserved separately; work takes place in the tracked sibling checkout.

## Measured old map

In a temporary Studio Play session, `Level 5 Architecture.Build` produced 29,240 descendants in a diagnostic parent model at `Vector3.new(31000, 24, 0)` in 0.71 seconds. The per-zone count includes each zone's existing enclosure and ceiling. The playable and DEV preview paths each enforce a 30,000-descendant ceiling, leaving about 760 descendants for changes before runtime-owned objects are added.

| Existing zone | Descendants | BaseParts | Houses |
| --- | ---: | ---: | ---: |
| A_BalconyAtrium | 3,048 | 2,939 | 46 |
| B_LowEavesArcade | 1,632 | 1,553 | 32 |
| C_PastelVillage | 4,361 | 4,189 | 80 |
| D_FloralTerraces | 3,007 | 2,913 | 53 |
| E_DomesticLabyrinth | 1,908 | 1,820 | 29 |
| F_BayWindowCanyon | 9,292 | 9,062 | 167 |
| G_TiltedSubdivision | 4,609 | 4,485 | 68 |
| H_LastHouse | 1,302 | 984 | 10 |

The F zone alone contains 60 closed scenic upper dwellings (at local `Y >= 42`). Their repeated facades include 116 window panes, 232 window jambs, 232 window sills, 232 facade piers, 116 window mullions and 116 crossbars. This is a candidate for replacement with a cheaper facade system; the enterable lower dwellings, clue home, Window Watcher homes, routes, doors and floor contracts require separate checks.

## Visual baseline

The Studio captures `baseline-A.jpg` through `baseline-G.jpg` record the previous environment at selected zone cameras. The visible old facades consist mostly of flat three-story rows with regular windows, isolated narrow towers and domestic slabs with metal rails. `baseline-B.jpg` shows scattered buildings where reference 2 needs a narrow straight corridor; `baseline-C.jpg` and `baseline-D.jpg` show sparse towers and houses where references 3–4 need dense cottage rows and apartment walls; `baseline-E.jpg` shows a sided house close-up where reference 10 needs a plain carpeted room. They do not match the supplied scenes' planted cottage court, long gabled frontage, round balcony towers or diagonal sloped-house structure. The screenshots include game UI and are baseline evidence, not matched-camera fidelity comparisons.

## DEV preview check

`Level5PreviewAccess` was installed in live Studio after checking the target place, exact door and source/editor parity. A local Play test as the permitted developer `LaverSneglen` found the door prompt, built the map, teleported to a collidable arrival floor at X=31000, and returned to the lobby through the return prompt. The Level 5 public flags stayed false and the queue door stayed closed. No script error appeared in the sampled console. The generated preview had 29,244 descendants after construction. Non-developer multiplayer access, active-round behavior and the final reworked geometry remain unverified.

## Acceptance status

- Reference photos: 10 distinct scene/view requirements recorded in `reference-spec.md`.
- Exact image pixel files: unavailable in this checkout; quantitative overlays are pending original files.
- Old map visual fidelity: failed by inspection of the captured Studio views.
- Revised facade/anomaly modules: pending integration and Studio verification.
- Publish: blocked by incomplete visual rework and visual QA.
- Standalone reference draft builders for views 1–10 passed isolated Studio Edit build/count checks. They remain uninstalled and fail strict visual acceptance; see `groundwork-review.md`.

## First scoped Studio change: F window frames

Studio `ServerStorage.Level5GeometryTemplates` now contains two baked `UnionOperation` templates, `WindowTrimSimple` and `WindowTrimStandard`. Both are white, anchored, noncolliding, nonqueryable, and have `UsePartColor=true`; their source part counts are 6 and 7. They keep the exact 10 × 7.2 stud pane opening and use one or two horizontal crossbars. Their stored CFrame is approximately `(-5.08, 0, -0.08)` relative to a window frame and their size is approximately `(10.65, 7.65, 0.41)`. The native place backup above predates these template assets; the eventual post-rework native backup must include them.

The live `ServerScriptService.Level 5 Systems.Level 5 Architecture` source and editor source were checked before writing (54,124 bytes, rolling hash `1805288502`). Only its F-zone 10 × 7.2 stud window trim path was changed, with a Studio source hash check inside `ScriptEditorService:UpdateSourceAsync`; the post-write source/editor copies matched (54,897 bytes, rolling hash `394830723`). Each original `WindowGlass` remains a separate Part with its `Level5TintedWindow` attribute for Window Watcher behavior; other window dimensions retain the original parts.

A new temporary Play build returned 27,472 descendants in 0.535 seconds. F fell from 9,292 to 7,524 descendants, an exact saving of 1,768; it contained 316 cloned trim unions, 344 original glass panes and 18 total Window Watcher anchors. The 28 other F windows still use their original jambs. Runtime build succeeded. The combined map's visual appearance, puzzle progression, client streaming and final scene fidelity still need testing after the full rework.

After that change, the actual developer door preview was exercised again in Play: `LaverSneglen` entered from `Level5SealedDoor`, the preview built with 27,476 descendants and 316 F trim unions, the arrival floor was collidable, and the return prompt moved the player back to the lobby. Both Level 5 public/round flags remained false. A streamed client capture is saved as `optimized-F-window-frame.jpg`; the frame and glass remained visible from the F upper atrium. This validates the scoped optimization and DEV return path for one authorized player; it does not validate non-DEV multiplayer behavior or reference fidelity.

The exact live Edit Source, editor source and repository mirror hashes, plus the UnionOperation properties, were rechecked and recorded in `studio-manifest.md`. Studio's native `Download a Copy` Save button remained disabled during a post-change backup attempt; the pre-change native copy is therefore the only verified `.rbxl` in this directory. A `Save to Roblox` action gave no visible success confirmation and is not counted as publication. The post-change native backup remains an open recovery task.
