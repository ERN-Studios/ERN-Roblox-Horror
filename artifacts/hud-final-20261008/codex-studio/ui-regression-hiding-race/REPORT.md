# Hiding scenario lobby-chip race

The final native sweep had one scenario failure: hiding measured Achievements.Open in the Thumbstick zone. Achievements.place correctly gates settled hiding on InRound, but polls every 0.5 seconds. UIRegression resetScenario(true) cleared InRound to nil and then yielded to Store's deferred handlers; hiding only restored InRound after reset returned. The 0.3-second scan could precede Achievements' next poll.

The scoped harness correction preserves InRound=true when resetScenario(true) is requested; lobby reset still clears it to nil. Production Achievements and all geometry checks remain untouched.

Production extracted-source runtime: 90 PASS; Luau compile PASS. A new test samples every InRound mutation and both actual reset yields, then verifies lobby reset still clears context. The frozen before source fails this test. Diff and exact hash are alongside. No Studio calls; native install/retest belongs to root.
