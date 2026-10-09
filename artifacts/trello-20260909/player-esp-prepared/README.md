# Player ESP proposal — isolated, not installed

Trello [Dev cheats: Add ESP for all players](https://trello.com/c/53c4MFE5) asks for a developer option showing every player's location. Both the full card and the dedicated checklist endpoint were read on 2026-09-10; there are no checklists or extra requirements.

The proposal adds a separate **PLAYER ESP** ON/OFF row to the existing developer panel. It defaults OFF, has no new keyboard binding, and does not share the existing B-key world/object ESP or fast-queue state. The current three UserIds in DevAccess remain the complete authority boundary. These are development tools for the owner's game, with no purchase, reward or player-account modification.

## Three existing files

`manifest.json` records every current raw baseline and exact proposed SHA. `baseline/` retains those original bytes and `proposed/` contains the complete candidate sources; three narrow `.diff` files accompany them. Runtime files and the sync manifest have not been changed.

* **DevCheats.LocalScript:** local ScreenGui name markers, a separate toggle/attribute, two position requests per second while enabled and camera projection while enabled. Markers are owned by PlayerGui; nothing is parented to player characters, a Mimic, the world or a hostile. OFF, a missing reply for 1.5 seconds, a departing player and script destruction remove owned markers. All owned connections are disconnected at destruction. There is no local character dependency: a valid server coordinate remains useful when streaming has not supplied that character.
* **ZyntraStore.LocalScript:** one config-like DEV row and nil-safe keyboard-caption formatting for keyless toggles. Existing mouse/touch/gamepad Activated flow and responsive row geometry are reused. All existing key captions and DevCheats keyboard bindings remain unchanged.
* **GameManager.Script:** one read-only `playerEsp` command branch behind the original DevAccess check, string/boolean validation and 12-request-per-second rate gate. It sends a fresh coordinate list only to the requesting developer through the existing RemoteEvent. It does not use FireAllClients, create a new remote, save subscribers or spawn a server loop. Actual current Character roots in Workspace are included, including the developer's own root and existing dead bodies; absent/unspawned characters have no invented coordinates. Dead bodies have a DEAD label. The normal client asks at 2 Hz, leaving the existing rate bucket room for other commands.

Existing documentation records StreamingEnabled=true, so highlighting only locally replicated character models would not satisfy the distant-player case. A server coordinate request is the minimum additional seam. The rendering is a through-wall name marker, not a body-outline effect: turn the camera toward a player to see their marker; offscreen and behind-camera labels are hidden. Visible markers are inset to keep their text within the viewport. Names use plain `@Username`, which identifies the actual Player without interpreting DisplayName markup. There is no range cutoff.

## Validation already completed

`test_proposal.py` executes the actual proposed client block, DEV-row Activated callback, command dispatch, caption expression, server handler, original rate limiter and actual DevAccess source in a controlled Luau host. **67 checks pass**, including server-only far coordinates without a local Character, default OFF, readback recipient, deny nondevelopers, strict payload gate, request rate, stale and out-of-order replies, no-camera/behind/offscreen rendering, duplicate and invalid players, leave/respawn, cleanup and preservation of key captions. Two negative controls remove the actual server authority guard or expiry cleanup and must fail. All three entire proposed scripts compile. Current runtime hashes are independently compared with the saved baseline.

These are code/behavior checks, not real multiplayer or native UI evidence. The test host uses explicit stand-ins and never presents them as physical Studio clients.

## Root installation and native acceptance

1. Recheck raw runtime hashes against the manifest and audit Studio against the current sync manifest. Root's concurrent Protection and later proposals may legitimately advance the same Store/GameManager baseline; merge only these narrow regions into that new baseline, then compile and rerun the focused handler checks. Never replace a newer runtime with an older full candidate.
2. Apply the three reviewed sources through the established record-pending and ScriptEditorService UpdateSourceAsync push workflow in CLAUDE.md, then audit/compile the place. No new Instance/script bootstrap is needed.
3. Normal lobby on a whitelisted account: existing panel, new PLAYER ESP row, default OFF. Click ON/OFF and verify names/state and removal. In third person the real developer's own marker can exercise this with one physical client; it is not proof that a second player or stream-out path worked natively. B must still change only its old world-ESP/queue pairing.
4. Check actual desktop and phone-size responsive row/caption and gamepad Activated/navigation where hardware is available. No key glyph should appear on the keyless row. Confirm markers stay below existing modal/loading/capture screens and never steal input. Check label readability near viewport edges and with a long real username.
5. For real multi-player native acceptance, use another actual client: its through-wall marker, movement, death, respawn and leave; move far enough that its Character is absent in the observing client's streaming region and confirm its server-backed marker still updates. Single-client evidence must leave this specifically pending. Server readbacks must only go to the approved requester; denial is also covered by the controlled actual-handler test.
6. OFF immediately removes labels and stops requests; a later stale response cannot restore them while OFF. Normal round transitions/character replacement require fresh server coordinates and must not leave the previous body position fixed on screen. The visual snapshot can lag by the 0.5-second query period plus network latency; the 1.5-second timeout hides a lost feed rather than claiming a live coordinate indefinitely.
7. Independent artifact review must reach at least 8/10 before installing. Native acceptance and root's mouse-based publish are separate later steps; no publish has been performed by this agent.

Run locally:

```powershell
python artifacts/trello-20260909/player-esp-prepared/test_proposal.py
```

`prepare.py` is an artifact generator with an all-file baseline hash guard. It never stages/pushes Studio and refuses to silently regenerate over a changed runtime baseline.
