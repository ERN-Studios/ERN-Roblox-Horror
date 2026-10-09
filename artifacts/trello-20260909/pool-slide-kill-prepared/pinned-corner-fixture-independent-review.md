# Independent pinned-corner fixture review

**9/10 as a bounded native diagnostic fixture.** The 66-line source compiles in full. It requires Studio Play server, the recorded seed, the original living tester and original active manifest. It uses the existing validated pump helper and records through the existing combat observer. Its mutations are limited to the tester's setup/dodge/return PivotTo and velocity, plus its own event StringValue. There is no NPC, health, Shield, collision, inventory or economy mutation.

The .15-second delay starts from the first observed ATTACK, not the private attack start. The saved snapshots must demonstrate that the scripted dodge precedes impact and that HP survives the original impact window. Its label is a planned test, not a success assertion. TargetUserId and AttackSerial are available in the stored combat snapshots; explicitly matching the tester before triggering the dodge would also make this fixture safe to reuse with additional players. The current scenario is the actual single tester.

The return to the corner is allowed only while that same character remains alive in the original round. Restart removes the Play-only fixture. This review does not execute it, claim natural user input, or approve the pending combat feature.
