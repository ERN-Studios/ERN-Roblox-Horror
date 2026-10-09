# Revised Continue screen: original timer and visible choices

Artifact-only proposal for [zlI8Rmto](https://trello.com/c/zlI8Rmto), matching its explicit replacement requirement dated **2026-09-10T08:24:33.936Z**. A fresh direct read after resumption confirmed the same description and To Do/incomplete state. `card-readback.json` holds the dedicated read. The earlier wait-for-every-player proposal in `party-continue-prepared` is superseded and was never published.

The published v1849 GameManager and RoundUI are the baseline. The old result title, divider, statistics, countdown, buttons, input/pending rules and transport remain intact. The original 15-second deadline automatically continues unanswered players; explicit Continue still starts the existing early transfer, and the old all-decided settlement remains. Final-level behavior is unchanged. This proposal does not create a new party barrier or change the Routing module.

## Small additive change

- GameManager sends `postwinchoices` through the existing RoundStatus remote after the actual server roster is created, an accepted decision changes, a failed decision is cleared, a player departs, or the old window closes. Packets contain the existing frozen roster's UserId, username and decision, plus session serial and monotonic revision. They do not accept client-supplied names or choices.
- RoundUI shows only accepted explicit `CONTINUE` and `LOBBY` choices, paired with usernames in frozen-roster order. Unanswered automatic continuation and an unanswered disconnect are not mislabeled as button clicks. A departed player's accepted choice remains visible to participants still on the source server. A failed decision rollback removes its previous label.
- A transparent top strip occupies existing space above the original title. Six names use two columns on desktop and one or two on phones. Overflow scrolls within the strip instead of moving or shrinking the old composition. The strip is hidden before the first explicit choice, after all choices are cleared, when the ending hides, and on reset/new session. Serial/revision guards reject old snapshots. Snapshot rendering never acknowledges a local pending command or enables/disables the original buttons.

No new remotes, modules, assets, persistent data or debug hooks. No UIRegression change is needed: its original countdown/control contract is still the intended behavior.

## Validation

Run from `G:\Roblox\MongoTV`:

```powershell
python artifacts/trello-20260909/party-autocontinue-choices-prepared/prepare.py
python artifacts/trello-20260909/party-autocontinue-choices-prepared/test_choices.py
```

Current checks: **36 actual-server checks + 141 actual-client/geometry checks**, **10 viewport fixtures**, **two negative controls**, and **two whole-file Luau compiles**. `validation.json` and `manifest.json` record source hashes and scope. Independent reviewer `audio_readiness` read the actual sources and current card, reran all checks and awarded **9/10 for this artifact/code**, with no required correction. See `independent-review.md`; native acceptance remains pending.

The server harness executes the real Routing module with the actual proposed GameManager handlers and intermission function. It covers passive 15-second continuation, accepted/rejected/duplicate/stale clicks, immediate transfer and shared reservation/deadline, departed continuation cohort, both failed-choice rollbacks, reservation refusal, disconnect, early all-decided settlement, final level and stale session. Replacing the server handlers with the original no-broadcast code fails the actual snapshot assertion.

The client harness executes the actual widget, original layout, reset/start/activation and countdown. It checks serial/revision fencing, names/choices, no false pending completion, final-level control, unchanged auto countdown, resize, rollback and hidden/reset behavior. It compares every original composition geometry property against the old function at 1280×720, 1920×1080, 568×270, 749×368, 320×568, 390×844, 1024×768, 768×1024 and two safe-inset fixtures. Six rows remain available in the scroll canvas; the narrow landscape scrolling surface is at least 44px tall for these fixtures. An injected snapshot clearing `completion.pending` fails the actual client test.

Whole-source subtraction separately proves the original server and client flows reconstruct byte-for-byte after removing only the added helper/calls/wrapper/remote branch. The harness does not simulate native Gotham glyph rasterization, engine scrolling, real network scheduling or Roblox TeleportService.

## Root installation and native acceptance

1. Confirm the runtime baselines against `manifest.json`. `prepare.py` reads immutable v1849 snapshots and writes only this artifact folder. If runtime changed, apply its narrow `manager(source)` and `ui(source)` transforms to the current source and inspect the merged diff; never copy an old full file over unrelated edits. Preserve the root's spawn fix and other releases.
2. Root installs exactly the two reviewed proposals, compiles/audits and starts a normal multiplayer round. No installation or Studio operation has been performed by this agent.
3. With two real clients at the result screen, leave both unanswered: the original 15-second countdown and automatic continuation must work. In another run, click Continue on A and verify B sees A/CONTINUE while the original transfer path proceeds. Click Back to Lobby on B and verify the server records/displays B/LOBBY before departure; the original destination and cohort must remain correct. The original flow can settle immediately once everyone decides, so the last update is not guaranteed to remain onscreen for an artificial minimum period.
4. Confirm an unanswered disconnect does not become a fake click and cannot extend the old deadline. Observe failure/retry labeling if an existing safe fixture can induce transfer failure; do not perform real purchases or persistent writes for this feature.
5. Inspect actual desktop and 568×270/320-wide result screens with six synthetic display rows, clearly distinguished from actual multiplayer identity tests. Check original title/divider/stats/hint/buttons, native text fit, touch scrolling and controller scroll focus. Confirm every name can be reached and no row touches the original divider. Test a new result/reset so old choices do not reappear.
6. Obtain final native critique ≥8, then root publishes separately with the mouse and records the actual version. **Not installed or published by this artifact.**
