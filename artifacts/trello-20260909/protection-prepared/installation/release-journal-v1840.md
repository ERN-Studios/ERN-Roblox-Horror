# Protection delivered in v1840

**Published by root through the native mouse menu on 2026-09-10 at 09:09:24.097/.146 Europe/Copenhagen. Independent combined score: 8/10.** The [saved publish screenshot](../../protection-published-v1840.jpg) shows “Add publish notes to v1840” and “Published new changes”; `/root/critic` viewed it independently after publication.

The release installs the 19 agreed files in [the immutable installation manifest](install-manifest.json): 16 replacements and three new scripts, taking the production script count from 122 to 125. The critic independently compared all 19 installed files with their exact reviewed proposal hashes before final approval. Existing Developer behaviour is preserved in the reviewed merged Monetization source.

Players buy a stored Protection charge for five tokens and explicitly use it through Q, the gamepad binding or the touch control. The server owns the five-second effect, reservation/finalization and lifecycle cancellation. The feature includes the reviewed L1/L2/L3 hostile-target and impact gates; buying a charge does not activate it automatically.

## Retained acceptance evidence

- [Native Shop purchase](native-initial-buy.json): five tokens spent, one stored charge added, no activation.
- [Four-token UI refusal](native-four-token-refusal.json): inactive buy control and unchanged profile/write count. The server refusal is covered separately by the actual-source tests.
- [Delayed reservation](native-delay-reservation.json): no early activation; one expiry 5.000070 seconds after commit.
- [Retry and death during reservation](native-retry-cancel.json): no duplicate consumption or expiry extension; a cancelled reservation refunds once.
- [Actual L1 pull cancellation](../native-capture/native-pull-cancel.json) and [input/control readback](../native-capture/native-pull-input.json); [actual pin cancellation](../native-capture/native-pin-cancel.json) and [input/control readback](../native-capture/native-pin-input.json): matching real touch/capture/cancel events, two charges consumed once each, 100HP, restored motion/camera, and no stale capture or Kill track after fade. Each observation lasts approximately 14 seconds total and extends beyond expiry. The [second independent native review](../native-capture/native-cancellations-independent-review.md) agrees on these two cases.
- [Final normal cleanup and Edit checks](native-final-cleanup.json): later normal death returns the new 100HP character to the lobby; InRound/RoundActive false, protection inactive/expiry0, HUD hidden, root unanchored and controls/camera restored. Entity is returned to lobby storage. Both fixture objects and fixture source are absent in Edit. Compilation is 125/125 with no failures or unstaged scripts; source audit is 125 matched/0 drift, retaining one explicitly recorded existing L2 lighting newline allowance. Root also reported repeating the same checks after resuming, before publication.

## Limits retained in the release assessment

Native economic fault tests use an isolated memory backend with real Roblox server/client scheduling; no live DataStore write or Robux purchase was performed. Existing actual-source tests cover conflict, lost responses, lease recovery, refund and deduplication. A crash after effect delivery but before durable completion can still produce a single recovery refund, as explicitly accepted in the transaction design.

L2/L3 mixed-player AI behaviour and physical phone/gamepad combinations were not all exercised natively. Their code/fixture coverage is retained without claiming physical multiplayer or native L3 acceptance. Player teleportation was used only for labelled contact setup and safe retreat after actual movement readbacks in the two L1 tests; the entity and capture events were not spoofed.

The [combined functional review](final-functional-review.md) records why this evidence is sufficient for an 8/10 release with these limits. This journal changes documentation only. Root owns the separate Trello status update.
