# PoolSlide: fresh real-time fade measurement

Artifact-only helper: `pool-slide-realtime-only-fresh.luau`. Prepared 10 September 2026; parent owns native execution. No production clip, Root curve, ground offset, rig-adapter behavior or asset ID is changed.

The corrected frozen grid already passed 1,224 samples, 72 cases and 144 isolated endpoint comparisons. It measured a real finite-grid minimum floor gap of −.1317004 studs for Idle→Walk at source phase .25. The previous real-time case is invalid as a fresh fade: its destination had raw WeightCurrent=1 **before** Play, retained from the earlier grid's Stop(0). Destination weight stayed1 throughout; the outgoing source correctly faded to0. Max raw sum error was .8958333, with .018329-second maximum frame gap. This was contaminated setup, not inadequate frame rate.

The new helper repeats no frozen grid, solo phase sweep or channel comparison. It reads the same complete validated mesh geometry once and records these short cases, each on a pristine clone, Animator and animation tracks:

| Order | Transition | Source phase fraction | Fade |
|---:|---|---:|---:|
| 1 | Idle→Walk | .25 | .16 s |
| 2 | Idle→Walk | .50 | .16 s |
| 3 | Walk→Run | .50 | .16 s |
| 4 | Run→Attack | .25 | .12 s |
| 5 | Idle→Walk, baseline repeat | .25 | .16 s |
| 6 | Idle→Walk, comparison only | .25 | .08 s |
| 7 | Idle→Walk, comparison only | .25 | .04 s |

Current priorities and preview references Walk10.82/Run27.6 are preserved; Run uses the current EnragedSpeed. The destination is loaded but **never played or stopped before its actual fade**. Its initial current must be zero. Source uses full weight at its requested phase, then the actual Stop(fade)/Play(fade,1,rate) sequence starts. Only states and all 20 native bone world/local CFrames are copied during each Heartbeat. Skin reconstruction happens afterward.

Checks preserve complementary weights and active-track targets. An outgoing track may be IsPlaying=false while it still fades; it must remain in Animator's active list while contributing. The probe records both Stopped and Ended. A completed source must have fired Ended, left the active list, and the captured final pose must match a separate destination-only rig at the exact captured phase. Any stale nonzero raw weight after Ended is discounted only after that individual captured sample also matches its exact-phase reference. Raw values remain in the report.

Require at least two interior destination-weight frames and two advancing phase frames. A .04-second fade may therefore be rejected as undersampled on a slower run; that is not evidence that its geometry passes or fails. A shorter fade that passes these few cases still needs native visual continuity and coverage of other transition phases before any production decision. This helper makes no such decision.

Full states, captured bone CFrames, skin minima/feet and reference comparisons are saved in 40,000-character StringValue chunks under `ServerStorage.TrelloPoolSlideRealtimeFreshFull`. In-memory fallback: `_G.TrelloPoolSlideRealtimeFreshResult`. Existing reports are not overwritten. The compact return strips frame arrays. An invalid case retains its raw capture but receives no accepted skin result, and later cases do not run. Unexpected errors also serialize already captured CFrames instead of discarding evidence.

Luau 0.737 compilation passed. Independent critic review was requested. Temporary measurement rigs/tracks/connections/readers are cleaned up. Parent continues to own restoration of the temporary Mesh/Image API setting to OFF before publication.

Primary API sources: [Animator](https://create.roblox.com/docs/reference/engine/classes/Animator) documents that the playing-track list includes outgoing fades independently of IsPlaying; [AnimationTrack](https://create.roblox.com/docs/reference/engine/classes/AnimationTrack) distinguishes Stopped from Ended, which fires after the fade completes.
