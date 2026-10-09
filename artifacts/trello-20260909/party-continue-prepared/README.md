# Wait for the party before continuing

**SUPERSEDED — DO NOT PUBLISH THIS PROPOSAL.** Trello zlI8Rmto was clarified at 2026-09-10 08:24:33.936 UTC: restore the old end-of-level UI and automatic continuation, while showing player choices. Dedicated readback at08:36:18 UTC confirms this explicitly replaces the wait-for-everyone requirement. Root is restoring the exact v1849 `installation/before` checkpoint; the unpublished local multiplayer acceptance here is historical evidence only. Revised preparation lives in `party-autocontinue-choices-prepared`. Previous scores do not approve the revised feature.

Trello: https://trello.com/c/zlI8Rmto. Full card: “On the Continue / Back to Lobby screen, show which option each party member has clicked. Wait for the entire party to be ready to continue before advancing to the next level together.” The dedicated card/checklist reads returned no additional checklist or comment. This is an artifact-only proposal; no runtime source, Studio, live UI, datastore or Trello mutation has been made by this preparation.

## Existing cause and narrow seams

GameManager's previous `handlePostWinContinueRequest` explicitly sent the clicking player immediately. `runPostWinIntermission` already owned an immutable Routing roster and a common settlement, but its15-second timeout treated unanswered players as continuing. RoundUI only showed the local click's pending state. There was no party-choice snapshot.

This is new post-win decision behaviour, separate from the existing loading/entry/transport-failure cards in Testing. `Round Completion Routing`, `Round Loading`, entry acknowledgement, transfer claims, retry/fallback timing and destination admission algorithms remain unchanged. Root's independent spawn-overlap work occupies `placeSafelyInElevator` near593 and adapter placement; this proposal's GameManager changes start around1023. Apply the focused transform onto the newest checkpoint rather than overwriting a newer full GameManager.

## Resulting behaviour

- Server Continue records readiness without dispatching a player. The existing settlement sends the remaining ready group together.
- No auto-choice deadline. An unanswered connected participant keeps the group waiting until they choose or disconnect. Every member can opt out with Back to Lobby, including after their own Continue acknowledgement.
- The server is the only decision authority. Frozen-roster membership, current result serial, selected level, RoundActive and InRound checks remain. Duplicate, stale and nonmember requests do not change the roster.
- In live reserved round servers, an opted-out player must actually leave before the continuing group advances. Known transfer failure restores their choice through the existing recovery path. A disconnected waiting continuer becomes Gone rather than a phantom expected arrival.
- The existing transport deadline is assigned at actual settlement, after any length of voluntary waiting. The final cohort packet therefore does not inherit an expired15-second decision deadline.
- RoundStatus sends `postwinchoices` with `{Serial, Revision, Closed, Members={{UserId, Name, Choice}, ...}}`. Choice is `deciding`, `continuing`, `returning` or `gone`; rows show WAITING, CONTINUE, LOBBY or LEFT. Client snapshots are fenced by current serial and monotonically increasing revision.
- Before acknowledgement, both actions are locked. A newer snapshot caused by a peer may refresh the rows but cannot acknowledge our still-unhandled action. An acknowledged Continue shows READY and makes Back available. Returning and final departure lock the local actions. No client timeout decides a party member's destination.

The six noninteractive name/choice rows reuse the existing result screen. They sit in three rows and two columns, with a compact header on shallow displays; the original hint/actions retain their measured positions and touch targets. Explicit usernames remain in the rows; text scaling handles the two-line cells. Actual native Gotham rendering still needs root acceptance.

Studio has no real reserved-server transport. Its unchanged mixed-choice local campaign fallback returns the local group together, because the level generators park the lobby. That editor limitation does not establish a live multiplayer split; it is not replaced by a new transport simulation in production.

## Validation and release handoff

`python artifacts/trello-20260909/party-continue-prepared/test_party.py` passes **189 actual-source checks** and compiles all three complete proposed files. The actual original intermission fails the same no-decision-expiry assertion. Removing the own-action acknowledgement guard fails a separate peer-update negative control. The harness executes the complete existing Routing module and extracted actual Manager/Client functions, using mock Players/clock/transport calls; it covers prolonged waiting, two ready members, Ready→Lobby, departure barrier, failed return, stale/duplicate/nonmember inputs, disconnected undecided/ready members, final-level restrictions, client pending/ack/closed states, and seven layout sizes down to568×270 with58px safe-top allowance.

The third source is only the existing UIRegression completion-contract expectation: WAITING FOR PARTY replaces the auto-countdown expectation. Its negative-serial local button fixture can prove pending input, but cannot produce an authoritative readiness acknowledgement; that distinction is explicit in the contract. No other Testing-card work is included.

All baselines and hashes are in `before/` and `manifest.json`. `prepare.py` writes only proposals/diffs and refuses baseline changes by default. Root has now independently changed GameManager for the spawn feature; explicit `--from-before` regenerates only this proposal from its preserved snapshots. Never install the old full GameManager over that newer work. Independent critic review is **9/10**; see independent-review.md. Root should merge the three narrow transforms against current sources, verify actual all-player rows/buttons on desktop and shallow/portrait touch layouts, exercise long waiting and Ready→Back/leave, and use real multiplayer evidence for joint travel and rejected opt-out behaviour. Native/rendering/live teleport or full gameplay acceptance is not claimed by the offline checks.
