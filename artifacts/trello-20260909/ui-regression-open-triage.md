# Open UIRegression findings: independent read-only triage

9 September 2026. The critic reviewed the 16 previously recorded failures. No source or Studio changes were made. This narrows the investigation; it does not replace the missing raw failure evidence or prove every finding predates the session.

- **13 CreateParty cases:** strong fixture explanation. Submit sets Active=false in RoundUI (803/825); queueconfigured/loadinggame reset queueSubmitting and hide the panel without refreshing it (4020/4093). A real subsequent queuehost calls refreshQueuePanel (4015), restoring activation. QueueModalMatrix instead sets the shade visible (3575/3637) and expects Active=true (3734), exposing stale hidden submit state. A focused fixture fix should establish the real fresh-host state. Normal-flow player failure has not been demonstrated.
- **Two scenario cases:** raw Contract/Overlap details were not saved in the previous journal, so final classification remains open. objectives-panel belongs to LevelOneGuideGui. level2-alert-and-objective forces GUIs visible after resetScenario removes InRound (1187), bypassing normal gates and layout ownership. Preserve raw failure lines during the next focused run before changing product code.
- **Outer restore case:** a genuine test-cleanup finding, not proof of ordinary gameplay failure. Harness overrides GUI Visible/Active and force attributes, then compares 0.2 seconds after restoration; reactive callbacks can recompute those properties. Capture exact differences to determine the repair.

Line references describe the critic's observed source revision before the pending Shop change and can move. The focused Shop validation should not be reported as resolving these older broad-suite failures.
