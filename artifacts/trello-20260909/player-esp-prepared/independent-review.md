# Player ESP: independent prepared-code review

Reviewer: `/root/critic`. Date: 2026-09-10. **Score: 9/10 for the bounded artifact/code proposal. No required correction. Native feature acceptance and publication remain separate.**

The reviewer read all three exact diffs, the actual client/server authority paths and the reused Store layout/dispatch contracts. The separate PLAYER ESP row defaults OFF and preserves the existing B-key world-ESP/queue behaviour. The new keyless row uses the existing Activated command path with a nil-safe caption; it adds no keyboard binding.

Server positions are returned only to an approved requesting developer after the unchanged DevAccess check, strict command/boolean validation and existing 12-per-second rate gate. Requests occur at 2 Hz only while enabled. There is no broadcast, subscription table, additional remote, server polling loop or economy mutation. Server root positions cover characters not currently replicated to the observing client; the renderer itself does not require a local character model.

The local GUI owns its markers, discards invalid, stale and older snapshots, removes missing/departing players, and destroys owned state/connections on script destruction. OFF clears markers and rejects replies while disabled. Markers are noninteractive TextLabels at DisplayOrder30, below the existing Store55, RoundGui100, guide110 and capture1000 surfaces. Position labels are intentional through-wall developer information, not body outlines; offscreen/behind-camera players are hidden.

The reviewer independently reran the existing focused harness: **67 actual-source checks**, both required negative controls and **three complete compilations** passed. The harness confirms runtime hashes remain unchanged. No new runtime test framework was created by this review.

Reviewed hashes: DevCheats `f16d6fc3f23fbd314f77498788eae3a08fb4698ba5160166064846f3eabd5aeb`; Store `7d2ef14f5b02e3e0751d7eba7b0060966c6aa5f7bad63b07ea4b45a965a294b4`; GameManager `daaab0df31009b045383691660ac07a56de0b0e6066c24e373522f62b777d513`.

Native acceptance should verify the real row, ON/OFF behaviour and readable projected labels without input interference. A single client can verify its own marker and the actual server/readback path, but cannot demonstrate a second player's through-wall movement, stream-out, death/respawn or departure. Those multiplayer limits must stay explicit if not exercised. The existing 0.5-second polling delay plus network latency and 1.5-second stale timeout are appropriate, documented diagnostic limits.
