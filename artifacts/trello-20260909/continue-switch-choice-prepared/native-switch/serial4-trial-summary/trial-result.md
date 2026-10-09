# Serial4 native trial — no accepted selection

**Not a Switch pass or an input-fixture pass.** The frozen export contains zero `ActualButtonActivated` events for serial4 and no accepted Continue/Return choice. It therefore does not diagnose a gameplay switching regression; root and critic own the separate input-delivery diagnosis.

Source: `../virtual-attempt-1528`, collected13:29:47.904UTC,800 complete messages/2250 chunks across all retained runs, with no reconstruction errors or sequence gaps. This summary writes only this new directory. Original records, observers, UI and runtime are unchanged.

| Actual client | Run | Received win | Shared server deadline | Authoritative choices |
|---|---|---|---|---|
| Player1/-1 | a366d8df |15:28:17.314DK |15:28:32.306DK | rev1: both deciding, open → rev2: both deciding, closed |
| Player2/-2 |35a75b2e |15:28:17.337DK |15:28:32.306DK | rev1: both deciding, open → rev2: both deciding, closed |

All17 before-deadline UI snapshots per client show both original buttons visible/active and no visible selected-choice row. The old cached `Player1 — CONTINUE` text exists only on a hidden row; it is not a new selection or a stale visible claim. After the first render update, the normal hint counts down15 through1. There is no third packet or intermediate accepted-choice revision.

Closure is observed at deadline+0.278360s for A and +0.269685s for B. First loading arrives at +0.279652s / +0.270750s. The existing server GameManager line reports window4 settled: **2 continuing,0 departed,0 returning,0 gone → cohort2**. These are automatic defaults for two still-deciding members, not two accepted clicks.

**Clock distinction:** the log's UTC timestamp is about0.283s behind `GetServerTimeNow` in the snapshot payloads. Do not compare the settlement log13:28:32.039 directly to the server-time deadline13:28:32.306 and call it early. The first server observer transition to loading/intermission=false has payload `At=1789046912.497638`, deadline+0.191216s. The exact private partition-call time was not separately instrumented.

Both clients genuinely reached Level2. A's fully released snapshot is **15:28:38.699DK**, B's **15:28:38.720DK**: each own player has100HP, InRound=true, RootAnchored=false, RoundEntryControlsReady=true and RoundEntryUIReady=true. Both see SelectedLevel2, RoundActive=true, WorldGenerated=true, RoundLoadingState=ready, PostWinIntermissionActive=false, and loading/ending UI hidden. The own-player attributes come from each actual client, not from assumptions about a remote player's replication.

The precise packets,17 UI samples per client, readiness snapshots, server state samples and bounded settlement-log line are in `trial-result.json`, with hashes of the original export. This establishes unchanged automatic progression and absence of an accepted input sequence in this trial. Same-window choice switching, its peer updates and final chosen transport still require actual accepted input evidence.
