# Native circle evidence — real two-client capacity-one case

Server run `3c83b325` is complete, sequences 1–41, with normal `Stopped.Completed=true`. The frozen checkpoint is `trial-3c83b325/`; all earlier setup runs remain present and are excluded from the successful case. Parsing has zero rejected messages, missing chunks or identity errors.

The intentional B intrusion was radius 4.5 inside the authored radius 7.41. The first sample, **0.06378 seconds** later, already recorded B at radius **8.91000366**. All **32 samples over 1.96698 seconds** kept B there and A inside with **0.00000 studs horizontal displacement**. Minimum actual root separation was **8.90890503 studs**, both HP100 throughout. The fixture's 28 post-settling checks passed.

Actual client A received `queueconfigured` capacity 1/Public and countdown **10 → 9 → 8**, each 1/1. B received `queuefull` (station 1, capacity 1), then `lobby`; B received no `lobbycountdown` packet during the full interval. This is direct feedback plus physical exclusion evidence, not a direct read of private membership.

After the clearly logged controlled A exit, the station reset to 0/6 in **1.02923 seconds**. Re-entering the same real B yielded `HOST SETTING UP` and then B's own actual `queuehost` packet. Following root's actual X click, the server recorded both outside, 0/6 and `CircleCancelReset`; B received `queueconfigclosed`. All server checks completed in **55.6817 seconds** from arm. This canceled before launch.

Exact client/server timestamps and all packets are in `native-analysis.json`. The native executed floor-ray fixture is SHA `7419617e…66b4b3` (full value in JSON). First server run `7a96a982` stopped while armed without exclusion samples; it is an abandoned setup, not a product pass. The earlier two 240-second observer expirations likewise contain no circle test.

Limits: actual-player staging (including root's initial floor-ray host placement) is not human walk-input evidence. Client rendering/smoothness and screenshots are separate evidence. This case does not re-certify launch, capacities 2/6, cold friends, multiple simultaneous rejects or future larger avatars. No native test execution, UI action or production mutation was performed by this collector.
