# Lobby developer access and spawn verification

Implemented in the authoritative Studio place **131311258779917**, universe **10559217407**. The final installation contains nine scoped Sources; all nine fresh exports match editor Source and the pinned [combined manifest](../../tools/lobby_access_spawn_20261002/combined/manifest.json). The final Builder hash is `6154d95902fbe2d89976e6428fc38a69f25e91e78f5ad02afac50ef19a39fad7`; the temporary Edit-build exception was reverted.

Ordinary clients see opaque, collidable **COMING SOON** walls for Levels 5 and 6, with the existing progress values **70%** and **30%**. Their preview queue labels are hidden. Developers retain visible openings and developer-preview queues. Server authorization and the bay guard independently reject unauthorized access; the visual wall is not treated as the authorization boundary.

GameManager is the sole normal-public startup builder. It completes the revised Blender lobby, validates readiness and solid floor, then moves the existing canonical `ServerLobby.LobbySpawn` to **(220,30.4,-860)**, facing down the new tunnel. It preserves the pad's name, parent and reference, so initial spawn, death/reset and lobby-return paths agree. Reserved round servers bypass this construction. Bootstrap monitors readiness without launching a second build. Level 6 return streaming acknowledges the revised lobby's floor; Friend Boost visibility follows the selected lobby without changing bonus authority.

The new lobby is built **at runtime from the preserved raw Blender server bake**. The attempted native Edit construction failed before creating the lobby Model or modifying the pad. No persistent geometry or spawn-property changes were retained by that attempt. The original lobby stays beside the revised runtime lobby.

Actual Studio Play tests:

| Session/check | Observed result |
|---|---|
| Solo developer ZenMeister02, UID 11374988579 | Arrived near (220,33,-860), health 100. Levels 5/6 showed DEV PREVIEW and no blocking shutters. |
| Developer Level 6 queue 121 | Real CreateParty UI launched the ready Level 6 world (17,064 descendants). Holding E on its return prompt returned near (220,32.92,-860), health 100. |
| Developer death/respawn | New character near (218.87,33.00,-861.49), health 100. All nine spawn-floor rays hit the solid Road at Y=30 with upward normal 1. |
| Server & Clients ordinary Player1, UID -1 | Arrived near (219.54,33,-861), health 100; saw both COMING SOON walls and their 70%/30% progress bars. |
| Ordinary player forcibly positioned inside each protected bay | The actual server guard denied/ejected the player from both Level 5 and Level 6; denial count advanced to 1 and 2, with health 100. This was a position-injection test, not a forged RemoteEvent test. |
| Ordinary Level 1 station 101 | Real host/CreateParty UI worked and displayed GAME BEGINS IN 10, 1/6 READY · PUBLIC. Stepping off cancelled the queue. |

Evidence: [playtest JSON records](playtests/), [developer spawn](screenshots/dev-new-lobby-spawn.jpg), [developer Level 6 opening](screenshots/dev-level6-opening.jpg), [developer return](screenshots/dev-return-new-lobby.jpg), [ordinary Level 5 wall](screenshots/ordinary-level5-coming-soon.jpg), and [ordinary Level 6 wall](screenshots/ordinary-level6-coming-soon.jpg).

Claude **Opus 5.5, max effort** completed the actual focused read-only review successfully, with exit code 0 and canonical model `claude-opus-5-5` recorded in its [receipt](claude/focused-auth/receipt.json). Its station/campaign authorization questions were checked against the full installed Sources and documented in the [independent closure](devgate-audit/focused-auth-independent-closure.md). The 48 original fixtures, 10 authorization-closure cases and native-scope integrity fixtures are **source/mock/synthetic checks**, separate from the actual Play results above.

Limits: the attempted forged RemoteEvent was **not delivered** because the execution sandbox/capability restriction prevented it; this test did not execute and is not reported as passed. Mixed developer/non-developer multiplayer cooperation and production cross-server transfers were not tested. Existing `LobbyLevel6` infinite-yield warnings remain unchanged; the tested spawn, protected gates, preview launch and return paths worked despite those warnings.

Full before/after native place backups are complete. The [after backup](backup/after/backup-summary.json) contains 228 Sources, zero editor conflicts, and matching captured/reopened canonical forests. Existing unreadable service-property and reconstruction limits remain recorded in that receipt.

The [exact task-plus-concurrent native-scope check](backup/native-scope-with-concurrent.json) **passed**: nine task Sources plus two explicitly pinned concurrent Level 1 edits, with 217 other Sources and the remaining native forest preserved. The concurrent `Level 1 Systems.MazeGenerator` and `Level 1 Systems.BlenderRoomRenderer` Sources were preserved outside the task installer; this verification does not claim a semantic review of their changes. The earlier strict-nine-only failure is retained, rather than relabelled as a pass.

Publication succeeded as **v2520**. The local task commit was being finalized at this report update.

Release: Roblox confirmed **v2520** at **2026-10-02 16:33:30 UTC**. The read-only final check compiled all 228 Sources and verified exact AFTER hashes and editor parity. [Native publication receipt](publication-receipt.json). No live servers were restarted and no experience access settings changed. Local commit was being finalized after this receipt; no GitHub push is configured.
