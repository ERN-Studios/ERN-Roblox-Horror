# Native UI triage — 15 September, 21:09 UTC

Full report: native-ui-qa-full.txt. Fresh lobby run at 899x675: 10 failures,
not the 20 found when the harness was run inside an active Level 3 round.

- Seven BriefingExclusion expectations conflict with unchanged HEAD behavior:
  lobby users may open Zyntra while dispatch is running; in-round dispatch blocks
  it. These are stale lobby fixture expectations, not introduced regressions.
- Objectives-panel fixture explicitly forces ObjectivesButton visible on desktop.
  Production refreshObjectivesButton hides it on both desktop and touch whenever
  the panel is open. The test is stale after the unified MISSION BRIEF composition.
- One adversarial 568x320 layout leaves a 56x52 detector whose text overflows.
  This needs further layout handling; it is not a measured hardware result.
- ControlZoneMatrix reported no Changed event when FlashlightPower was hidden;
  the prior run passed this lane. Requires isolated reproduction before attributing
  it to a production change.
- Queue modal 719 checks, briefing text 243, safe area126, terminal1405,
  dispatch compact214, completion and same-frame exclusion all passed.

IMPORTANT: restart Play between the full harness and gameplay tests. The full
suite leaves client-local SelectedLevel=3 while the server remains at Level1;
joining a Level1 queue in that same session then waits for mismatched readiness.
That observation is a test harness residue, not proof of a normal entry failure.
The session was stopped before the next gameplay test.
