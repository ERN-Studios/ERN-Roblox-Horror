# Death-location Emergency Re-entry — 2026-09-20

Trello: https://trello.com/c/Ejo5OPkG (card 109).

## Behavior

Both stored and newly purchased re-entry credits already converge on GameManager's same server callback. That callback now records the death frame and returns the new character to that location. It checks solid floor, overhead clearance and other players; unsafe wall/void/pit deaths search nearby ground and the last walkable position. The existing elevator remains an emergency fallback when no safe death-area location exists.

Placement is server-anchored during a bounded streaming request. Shared PlayerProtection makes the character untargetable during placement and renews a full ten-second grace when controls release. Every current entity already checks this authority. The HUD displays “You are invisible to monsters” with a server-time countdown, including a ten-second spectator readout. Entity Shield remains five seconds and cannot consume/stack during grace. No extra charge is used for the grace effect.

The existing once-per-round, request ownership, round teardown, credit reservation and failed-attempt refund paths are preserved. Failed streaming/placement refuses the common callback so the existing inventory path can refund. Delayed character-added/removing events now invalidate only the life they belong to; an event from a removed character cannot clear new re-entry protection.

## Validation

- 18 checks execute the actual PlayerProtection source with isolated lifecycle/time mocks: five-second shield, ten-second grace, renewal after streaming, old expiry callbacks, no shield stacking, stale contexts, late character events, death, escape, round/level change and disconnect.
- 9 native Studio geometry checks cover exact XZ placement, blocked walls, nearby resolution, occupied positions, voids, last safe fallback, moving floors and lethal pit bottoms.
- A real solo Level 1 queue/round in Studio returned the player to the recorded death XZ; the root was raised approximately 0.12 studs for floor clearance. A normal server Script confirmed live protection, an unanchored root and 9.97 seconds remaining after return. Protection expired after ten seconds.
- The common paid callback succeeded with 9.98 seconds remaining and set the usage flag; a second attempt returned ALREADY_USED. This invokes the fulfillment callback only: no real purchase or inventory balance was changed.
- The client HUD showed the expected message and countdown, at 360×50 in the inspected desktop viewport. Full physical mobile/tablet and multiplayer encounter checks were not run.
- All five changed runtime sources compile. All 148 live Studio source/editor buffers match the repository. Console had no game-script errors during the final run.
- Early probes found delayed character-event invalidation, which was fixed. A separate MCP-context require has its own module state, so runtime protection was subsequently verified from a normal temporary server Script. The earlier false isolated-context result in studio-results.json is not the authoritative gameplay assertion.
- Real Marketplace receipt flow, refund persistence during a service outage, and full L2/L3 chases were not exercised. No live servers were restarted.

## State and records

Sources were changed using complete fresh Source/editor comparisons, then exact readbacks. Temporary test fixtures lived only in Play and were removed by Stop. reentry-20260920.rbxl is a complete native Edit backup taken before the final one-line stale CharacterAdded guard; the exact final PlayerProtection source is mirrored separately. source-inventory.json records source paths/classes and fresh hashes.

The owner manually published the completed re-entry change as v1942 at 15:59:51 UTC (17:59:51 Copenhagen), verified from PublishSuccessful, Place published and the v1942 log link. Trello card 109 is marked complete and moved to Done. The earlier native UI timeout is resolved by that manual publication.
