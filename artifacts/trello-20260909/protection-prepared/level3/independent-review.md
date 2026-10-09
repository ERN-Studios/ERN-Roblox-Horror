# Independent review — prepared Level 3 protection integration

**Score: 9/10 for the bounded source/artifact preparation.** Reviewed by the independent critic on 2026-09-10. No remaining code blocker was found. This is not approval of completed native integration or publication.

Reviewed the exact Manager and Hiding diffs, their surrounding production functions, the private PlayerProtection module, and the actual-source harness. Independently reran `python artifacts/trello-20260909/protection-prepared/level3/test_level3_protection.py`: **119 checks pass**, all four negative controls reject their intended regression, both complete proposed modules compile, and both runtime baseline hashes remain unchanged.

Reviewed proposal identities:

- Manager: `b8befd31131e49fb37dc5812906be5378ad90e6c6433f5d884c75d1f114b2f2d`.
- Hiding: `5eae5ad31bbfd20570fb3908e1fc04f9727a73a1cd78c177244168ba13e8d232`.

The shared acquisition gate uses private server state. Cancelling an owned attack invalidates its delayed callback; the impact independently requires the original character and Humanoid. Player-owned memory includes the retired-avatar case, while another player's pursuit and independent CD noise survive. The defensive checks precede the table-check early return. Hiding keeps ordinary occupancy and capacity; only AI queries and per-occupant flush selection exclude protected players. Voluntary exit and round cleanup still restore protected occupants normally.

The test harness runs the complete protection service and selected actual Manager/Hiding functions. It stubs geometry, navigation, sensory visibility and scheduler behavior; the Stop fixture is a bounded cancellation model. These checks therefore do not certify the complete engine bootstrap, actual deferred event ordering, rendered capture behavior, or real multi-client hiding.

Before release, install the shared service before its consumers and run bounded native acceptance: activation during normal/blackout pursuit and attack windup; exact five-second expiry and reacquisition; activation during a table warning with protected and unprotected occupants; normal voluntary exit and round cleanup; and all participants protected when a hunt begins. Validate the combined client/transaction path separately. No repeat of unrelated map, CD, or final-exit geometry tests is required solely by these two diffs.
