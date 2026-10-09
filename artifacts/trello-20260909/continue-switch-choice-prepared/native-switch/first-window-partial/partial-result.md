# First Switch window — partial evidence only

**PARTIAL, not a Switch pass.** The log contains one actual A Continue click and no selection change. B made no observed click and continued by the existing default. Root used the normal two-player queue and a controlled objective-completion event; this is not a full level playthrough or cloud teleport test.

Collected at `2026-09-10T13:08:24.106212+00:00`: **138 complete messages / 384 chunks / zero rejected messages, parse issues or sequence gaps**. This certifies reconstruction only. Raw chunks and joined payloads are frozen beside this file; future collection must use a different output folder.

## Exact observed log identities

All files are under `C:/Users/mikke/AppData/Local/Roblox/logs`. Identities below come from actual Armed payloads and matching headers, not window order.

| Role | Exact log basename | Armed run |
|---|---|---|
| server / 0 | `0.738.0.7381393_20260910T130017Z_Studio_73170_last.log` | `3d307285` at 2026-09-10T15:06:53.041+02:00 |
| client / -1 | `0.738.0.7381393_20260910T130024Z_Studio_C55F4_last.log` | `fa1ea0b2` at 2026-09-10T15:04:33.089+02:00, `fc4753ae` at 2026-09-10T15:08:04.672+02:00 |
| client / -2 | `0.738.0.7381393_20260910T130025Z_Studio_5E546_last.log` | `8c4eedec` at 2026-09-10T15:05:55.458+02:00 |

## First window, serial1

- The shared server deadline received by both clients is **2026-09-10T15:07:23.239+02:00**. Deadline minus observed win delivery is 14.988121s for A and 14.965358s for B; these are client receive intervals, not a direct server timer-origin measurement.
- A clicked Continue at **2026-09-10T15:07:22.182+02:00**, only **1.056869s** before the deadline.
- Both clients received revision2: Player1=continuing, Player2=deciding, Closed=false. Both observed their Continue and Back to Lobby controls still visible/active with original captions afterward. The visible compact row said Player1 — CONTINUE. This proves no immediate first-click UI lock in these samples, but no second click occurred.
- Both received revision3 Closed=true after the deadline; first loading messages were deadline+0.361307s and +0.381339s. No earlier loading event is present in this window.
- Both actually reached Level2: normal start events, RoundActive=true, RoundLoadingState=ready, WorldGenerated=true, PostWinIntermissionActive=false, own HP100/InRound=true/unanchored, own controls/UI ready, and loading/ending UI hidden. The first brief ready-attribute samples still showed anchoring/loading; the JSON explicitly selects the later fully released samples instead.

## Observer/readiness handoff

- A was later rearmed as `fc4753ae` at15:08:04.672 DK. Its old `fa1ea0b2` run reports Stopped, Completed=false, Reason=replaced. That is not a failure of the recorded first window; it is not a completed240-second observer claim either.
- Original B requested240 seconds from15:05:55.458 DK (scheduled end15:09:55.458); the server requested240 seconds from15:06:53.041 (scheduled end15:10:53.041). These are scheduled limits, not proof of currently live subscriptions. Parent owns any rearming needed before the next test.
- This collection read only the three named logs. It did not stop, rearm or interact with any observer. The new same-window multi-click and peer-display test remains pending.
