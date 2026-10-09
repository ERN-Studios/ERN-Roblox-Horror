# Loading and recording HUD QA — complete

The five scoped sources are installed with CAS and fresh native/repository readback exactly matching; all five manifests are synced. All five compile; **1,653 offline checks pass**. Native card previews, actual Level 2 entry/release, phone/PC HUD checks and Edit restoration are complete. Shop UI's own lock is released; foreign coordinator notes and queue metadata were preserved. No publish, commit or push was performed. [Final five-source SHA proof](source-proof.json).

The requested imported layout from image 2 now supplies loading presentation for every level through shared `LoadingCardView`. GameManager rounds use the existing RoundUI card and truthful entry barrier; their duplicate high-order legacy cover is retired. Live Levels 5/6 use the same shared imported layout with their existing readiness/transport lifecycle. Normal first-join lobby boot stays separate. Existing mystery titles remain: Level 2 `UNRECORDED`, Level 5 `??? WHERE?`.

## Native entry evidence

- **Baseline reproduced:** real Level 2 entry showed the imported card first, then the legacy `LevelLoadingGui` at DisplayOrder 99990 obscured `RoundGui` at DisplayOrder 100 after **0.806 seconds**. The legacy cover also remained after the imported card closed. [Timeline](native/baseline-released.txt), [baseline image](native/baseline-old-loading.jpg).
- **Fixed actual entry:** with Studio's readiness hold enabled, the imported Level 2 cover remained visible for **42.6 seconds** at the actual server entry barrier; `OldExists=false` throughout the observed hold. [Held state](native/fixed-held.txt), [new card image](native/fixed-level2-loading.jpg).
- **Actual release:** after the hold was released, `RoundActive=true`, the imported cover closed and no old loading ScreenGui appeared. [Released state](native/fixed-released.txt). This verifies real local entry/release routing, not a cosmetic timer or injected loading-only presentation event.
- **Normal fast phone entry:** actual queue 105 reached accepted `RoundEntryReadyToken` and `RoundActive=true`. The imported cover lasted **1.439 seconds**; `OldExists=false` throughout. This confirms the fix adds no cosmetic loading delay. [Phone timeline](native/phone-loading-timeline.txt).

## Native presentation and HUD

All 12 phone/PC card captures show the requested imported layout with visible text fitting its text boxes. Levels 1/3/4 retain all three instruction rows and their tip; Levels 2/5/6 have no instruction rows under the approved registry. The compact third-row/tip breathing room and horizontal anchoring fixes are included in the final module. The actual PC viewport was 1413×556 and therefore selected the compact card; full 1920×1080 PC layout is covered by imported-fixture tests.

| Level | Phone image / measurements | PC image / measurements |
| --- | --- | --- |
| 1 | [Image](native/phone-card-level1.jpg) · [JSON](native/phone-card-level1.json) | [Image](native/pc-card-level1.jpg) · [JSON](native/pc-card-level1.json) |
| 2 | [Image](native/phone-card-level2.jpg) · [JSON](native/phone-card-level2.json) | [Image](native/pc-card-level2.jpg) · [JSON](native/pc-card-level2.json) |
| 3 | [Image](native/phone-card-level3.jpg) · [JSON](native/phone-card-level3.json) | [Image](native/pc-card-level3.jpg) · [JSON](native/pc-card-level3.json) |
| 4 | [Image](native/phone-card-level4.jpg) · [JSON](native/phone-card-level4.json) | [Image](native/pc-card-level4.jpg) · [JSON](native/pc-card-level4.json) |
| 5 | [Image](native/phone-card-level5.jpg) · [JSON](native/phone-card-level5.json) | [Image](native/pc-card-level5.jpg) · [JSON](native/pc-card-level5.json) |
| 6 | [Image](native/phone-card-level6.jpg) · [JSON](native/phone-card-level6.json) | [Image](native/pc-card-level6.jpg) · [JSON](native/pc-card-level6.json) |

- **Phone:** objective 192×44, full opacity, text/underline right edge 718; real touch classification with raw mouse/keyboard false and no ForceTouch/viewport fixture override. Physical objective activation opened the allowed developer's menu (40920547), with the redundant chip inactive; closing restored the HUD. REC line and all four bracket containers are hidden. [Margin/closed state](native/phone-margin-final.txt), [physical activation](native/phone-dev-tap.txt), [recording state](native/phone-recording.txt), [final image](native/phone-final-hud.jpg).
- **PC:** objective 288×51 with the requested extra 24-pixel margin; content right edge 1358.2 and root edge 1371. REC remains 269×18 and brackets 34×34, at the existing 24-pixel edge/16-pixel top placement. Recording text transparency is 0.25 and all shown text fits. [Margin](native/pc-margin.txt), [recording](native/pc-recording.txt), [final image](native/pc-final-hud.jpg).

## Offline checks

| Suite | Passed checks |
| --- | ---: |
| Complete native RF loader lifecycle, yielding fake engine | 154 |
| Loading failure/notice ownership | 96 |
| Existing B8 plus actual shared-renderer fixture lifecycle | 855 |
| Shared RoundHud imported fixtures | 382 |
| Stamina bar imported fixture | 74 |
| B6/B7 HUD compatibility | 92 |
| **Total** | **1,653** |

The loader suite retains the earlier checks and covers reserved bootstrap handoff, late asset completion, repeated entry, bounded prefetch, live arrival/continuation, fade/remount retirement and module-replication concurrency. The old native source fails the duplicate-cover and live-renderer regressions. The shared renderer suite executes the real module against imported templates, preserving current status, mystery policy, progress and cleanup across remounts. [Loader report](../../_local/hud-recording-loading-20261009/WORK/LOADING-OWNER-REPORT.md), [shared report](../../_local/hud-recording-loading-20261009/WORK/SHARED-LOADING-REPORT.md), [compile/shared/stamina results](checks.json), [install baseline and wanted hashes](install/audit.json).

The last native rapid-switch review exposed a deferred Binder listener observing an already destroyed third-row clone. LoadingCardView now prepares that imported row through RoundHud.Mount's optional Prepare callback before font and layout bindings, so it receives normal typography and cannot enter the late DescendantAdded path. Shared/B8 checks were rerun on both final candidates; all twelve card captures were regenerated. Fresh [PC output](native/pc-console-clean.txt) and [phone output](native/phone-console-clean.txt) have no Binder lifecycle errors. The existing unapproved sound-asset warning remains unrelated to this change. [Two-source CAS audit](mount-order-install/audit.json).

## Restoration and limits

Play is stopped and the simulator is back to its default device. ForceTouch, viewport and inset fixtures are nil; the CAS binding is absent and retired briefing UI/input remains removed. The simulator's resolution query reports no active device after reset; this is its default state. [Edit restoration](native/edit-restored.txt). The final module passed its scoped CAS/compile/readback after the compact-fit and anchoring corrections; [fresh parity](source-proof.json) confirms all five current sources and synced manifests.

Live Level 5/6 lifecycle evidence is the yielding fake-engine loader suite plus native card presentation previews. These are **not real published Level 5/6 teleports or multiplayer arrival acceptance**. Native PC checks used the compact-height viewport; full-size PC layout has fixture coverage. No publication, commit or push was performed.
