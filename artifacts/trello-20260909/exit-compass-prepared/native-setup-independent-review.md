# Independent compass native setup review — 9/10

Both small setup scripts were read in full and independently whole-compiled. No blocking fixture defect was found. This approves diagnostic preparation only, not actual compass rendering or release.

- `native-stage-owner-queue.server.luau`: SHA256 `5d661c280e14ce5a30b22f53af71ed190b3b35d39318aa98872e49a25d810a04`, 4 KB.
- `native-nav-display.server.luau`: SHA256 `464c24af9bccadb2aa50141a8e0b59cc0ca004414d26eea33c4c0d9a9a9ad8da`, 3 KB.

The staging script requires the actual single-owner Studio Play server and idle lobby. The exact LevelQueueRooms/Level1QueueRoom/LaunchZone1/ChamberFloor paths were matched against TunnelLobbyBuilder. It uses an actual downward ray against the rotated cylindrical floor rather than assuming local Size.Y is world height, checks a transformed complete avatar bounding box for collision, preserves root/model pivot offset and current facing, then performs the synchronous controlled placement. Root still uses the real queue UI; no queue event or membership is fabricated.

The NAV script requires an actual released living L1 participant with server RoundLoadingState ready. It obtains the real current Exit.Sign position and the existing PuzzleStatus RemoteEvent, changes only ExitPos and sends that owner's existing exit display event. This deliberately presents the installed NAV UI without claiming that its puzzle, light phase or exit door has completed. The actual natural exit source sets ExitPos, changes LightMode to ESCAPE and emits exit; the fixture leaves LightMode and all private objective state untouched.

Restore is owned by the exact fixture and checks the same world/token/level, target and light state before restoring the prior ExitPos. A new context or natural escape transition is preserved. Restore does not pretend to undo the client phase event: normal cleanup or Stop Play is required to reset that display, as explicitly documented. No general harness, testsuite, UI action or production-source mutation was added by this reviewer.
