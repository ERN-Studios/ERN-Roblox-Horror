# Level 2 queue gate — offline map, 2026-10-08

Studio is authoritative. These findings describe the current checkout only; live Source/editor and instance inspection is still required. No commit, push or publication is authorized in this session.

- New lobby `QueueBridge.Build` registers Level 2 pads 105–108; old lobby has LaunchZone5–8. Both use GameManager's host, friends-only admission, countdown and `launchStation`.
- `rawQueuedPlayers` observes geometry. `selectQueuedPlayers` selects the host and admitted public/friends members subject to capacity. The Level 2 gate must validate this entire selected cohort; silently dropping a guest would incorrectly allow a mixed party to launch as a developer solo.
- Initial host selection and `ConfigureQueue` need the same shared `canAccessLevel` check. The remote must reject a nondeveloper even when that player is not the host. `DevFastQueue` only shortens a timer; it does not grant admission.
- Existing `launchStation`, `ensureWorld`, `prepareGroupLoading`, `playRound` and reserved-arrival checks already use `canAccessLevel`; putting Level 2 before its `level <= Routing.MaxLevel` return closes these paths.
- `Routing.NextLevel(1)` remains 2. Check the shared gate before outbound transfer claims/teleport; Studio campaign loading already checks it. Do not change progression to skip Level 2. Ordinary players will be unable to continue the campaign beyond Level 1 while the flag is false.
- Reentry requires existing round membership and the frozen participant set; `ReentryPlacement` only chooses a safe position. Loading acknowledgements require the expected character and membership. Neither is an independent queue entry.
- No separate party/host-join remote was found. A friend's server arrival follows reserved admission. Fresh live `ServerKind` and `Live Level Server` sources must be read because this checkout has references to them without their current mirrors.
- The kit preview and the new-map pedestal already require `DevAccess.IsAllowed`; leave the Poolrooms-owned scripts untouched.
- Current direct Level 3/4 pads do not require a Level 2 clear. Their access flags, ceiling and route rules must remain unchanged.

Physical candidates: new lobby Level 2 doorway is derived from the exact owned R4 header; old lobby doorway is under `ServerLobby.LevelDoorways`. Live audit located the owned Level2Maintenance folder created by LobbyReimaginedPreview.Builder before Ready. Board, two Post parts and TopRail are the four existing Default colliders; installed developer NoCollisionConstraints cover all four plus the new doorway collider. Sign art and Builder source are unchanged. The aperture is20.8x19studs; installed collider22x20.2x2 overlaps its sides/floor/roof. Safe pushout is gate-local Z12, beyond the Board. `QueueBarrier` cannot be reused alone: `QueueMember` is noncolliding with it. A Default collider plus developer-only NoCollisionConstraints preserves other queues and normal developer collision.

Party assumption: a party is the cohort actually accepted by the existing public/friends and capacity rules. A private/full outsider is not a party member and must not cancel a valid developer party. At an unconfigured pad the geometrically present cohort is rejected before a mixed party obtains a host panel.

Live ServerKind and Live Level Server are only Level5/6 guards and reservation paths; no new Level2 entry was found. QueueBridge live Source differs from its repo copy and was preserved in live-before; task edits do not overwrite it.
