# Independent current native runbook review

**9/10 for the bounded handoff. No blocking finding. No native execution or feature acceptance is claimed.**

I read `native-acceptance-current.md` and checked the actual GameManager and Objective Controller route. DebugOpenExit returns the documented door/touch fields and opens the real exit without setting a player's escape/transition flags. Actual completion sets Level2_ExitTransition; runRound latches that route and carries the entry mode into the next campaign level. The Level 3 bore branch activates the world, waits a heartbeat, releases riders and emits level3access, while direct lobby entry uses the service elevator. Consequently, the correction to the earlier direct-Level-3 instruction is necessary and accurate.

The runbook uses the reviewed switch-slide composition and exact source prerequisites. It correctly requires real sensor/sweep completion, ordinary continuing players, actual per-character placement and stream request/ack ownership. It does not equate an ack packet with successful release, sparse Continue observations with a continuous ride, or two real clients/geometry fixtures with six real networked riders. The optional existing active suite is clearly separated from natural placement and acknowledges its PivotOffset and restoration limitations.

One practical setup detail: DebugOpenExit also enters the existing lethal Foam finale through openPressureDoors. If root uses this controlled fixture, stage the actual players near the real exit before the call so an unrelated long traversal is not mistaken for a slide failure. Do not suppress enemies or fake escape flags.

Actual continuous ride, landing controls and normal cleanup remain the native acceptance evidence. Stream failure, character replacement and six physical clients are not claimed without observation. This review added no probe, production change, Studio action or new tests.
