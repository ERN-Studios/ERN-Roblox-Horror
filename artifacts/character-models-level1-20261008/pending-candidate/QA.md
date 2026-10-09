Client pending-hide candidate, prepared 2026-10-09 from `../final-candidate/`. No production/Studio/queue changes.

The client hides only captured native R15 body surfaces, Decals/Textures and named legacy seam fillers while a server-created eligible visual exists but local retarget calibration is waiting for the remaining rig. A `DescendantAdded` listener immediately covers late parts. The pending record is tied to exact Character+Visual identity. On success, it transfers genuine original transparency values into the real state without revealing native parts; the existing two pose-frame delay remains. Equipment is untouched.

A build exception, loss of visual, character replacement or player removal restores originals and disconnects the listener. A five-second bound restores a persistently unusable rig's fallback once; the retained TimedOut record prevents hide/retry oscillation. Calibration still retries so later replication can recover. No visual means no suppression, preserving invalid/missing-asset fallback.

Validation: `test_pending.py` executes the actual pending helpers, body capture/visibility/cleanup and reconcile blocks: 26 checks passed. Current expanded `../collision-candidate/test_collision.py --source-dir .../pending-candidate` passed 49 server + 61 client checks. Driver compiles with Luau 0.737 `-O0 --null`.

Known scope: suppression starts when `ZyntraHazmatSkinVisual` exists locally, not when the gameplay marker alone exists. This deliberately preserves native fallback if the server cannot build any visual; any measured pre-visual flash needs a server-authored readiness/status signal or temporary suppression during marker-to-visual replication as a further change.
