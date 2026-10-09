# First loading-card level QA — complete

The two scoped sources, GameManager and RoundUI, are installed through CAS after exact native/repository baseline verification. Both compile and **1,621 offline checks pass**. Native replay and a real Level 3 queue confirm the first displayed card is correct. Fresh full native/repository readback and both synced manifests are verified; Shop UI's own lock is released with foreign metadata preserved. No publish, commit or push was performed. [Install audit and hashes](install/audit.json), [final parity and native assertions](source-proof.json).

This change affects loading announcements/rendering. Readiness acknowledgements, server admission, access checks, world generation and entry release are preserved. Reserved bootstrap uses the captured `BackroomsRound` packet's finite integer Level in `1..Routing.DevMaxLevel` (currently 4), without defaulting an unknown packet to Level 1. RoundUI accepts explicit levels 1–6, hides an unconfirmed card behind the opaque loading frame, and preserves an already confirmed level when a late untyped announcement arrives. The existing imported layout and mystery titles for Levels 2/5 remain unchanged.

## Native evidence

- **Baseline reproduced:** untyped `loadinggame` with stale SelectedLevel 1 displayed `RESTORE THE POWER`; explicit Level 3 then switched it to `FIND THE CDS`. [Wrong card](native/baseline-wrong-card.txt), [switch](native/baseline-switch.txt), [image](native/baseline-level1-flash.jpg).
- **Fixed replay:** untyped loading kept the opaque frame visible with `Card=false`/`Displayed=false`. The first displayed card after explicit Level 3 was `FIND THE CDS` with LoadingLevel 3 while SelectedLevel still remained 1; late untyped loading preserved it. [Unconfirmed](native/fixed-unconfirmed.txt), [first visible](native/fixed-first-visible.txt), [late preserved](native/fixed-late-preserved.txt). These were server-originated **UI-only event replays**, not reserved-server teleports.
- **Real normal queue 109, fresh Play:** first displayed card at **t=12.6367** was `FIND THE CDS` while SelectedLevel was still 1; SelectedLevel became 3 at t=14.8433. Actual entry token `:entry:1` appeared at t=52.9661, the server sent `entryreleased` at t=53.0994, the cover was hidden at t=53.1116 and `start` arrived at t=60.4050. RoundActive became true; `OldExists=false` throughout. Every displayed title was `FIND THE CDS`. [Full queue timeline](native/queue-three-released.txt), [actual loading image](native/queue-three-loading.jpg).

## Offline checks and restoration

| Suite | Passed checks |
| --- | ---: |
| Actual GameManager setupPlayer bootstrap | 583 |
| RoundUI loading notice and announcement delivery | 183 |
| B8/shared imported loading-card fixtures | 855 |
| **Total** | **1,621** |

The bootstrap suite covers valid levels including 3/4, unknown/malformed/non-finite/out-of-range/live-only packets, captured/deferred delivery, departure, and unchanged lobby/spectating/failure behavior. The native-before source fails the valid Level 3 announcement (`nil != 3`). [Focused test](../../_local/loading-first-card-20261009/WORK/test_bootstrap.py).

Readiness-hold and fast-queue overrides were restored to nil and verified server-side. Play is stopped; the simulator is at its default device, ForceTouch/viewport/inset fixtures are nil and CAS input is absent. A resolution query with no active simulator device is the expected default state. [Edit restoration](native/edit-restored.txt). The queue console shows no Binder errors; its sound-asset approval warning is pre-existing. [Console](native/queue-three-console.txt).

No published reserved-server teleport or multiplayer destination admission was exercised. The real queue confirms Studio's local Level 3 entry path; bootstrap packet delivery is verified by the actual setupPlayer offline harness and native UI replay.
