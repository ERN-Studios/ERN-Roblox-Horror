# Independent observer review — 9/10

## Corrected final checkpoint

**9/10 for the corrected observer pair**, with no remaining blocker found. Use client SHA256 `9993c3f7cb0a4b86f3ead09490664f9cd866182a9575c1b0f0c3666e613725cb` and server SHA256 `bc2731b5ab42428fa6952134fdbc049c0f0f2f584912909e7c0bff88a8920e85`.

Root identified two real omissions after the initial review below: UI row tables occur at serialization depth 6 and were replaced by the depth-limit string; UI-ready alone did not observe the actual controls-ready field. The narrow correction increases the bounded depth limit to 10 and adds `RoundEntryControlsReady` and `RoundEntryReadyToken` to the observed player attributes. I read both exact correction hunks, independently ran the actual nested-row serializer case, matched the attributes to `NoiseReporter` line 890 and `Round Entry Client` line 117, compiled both complete scripts and verified the new hashes. The old depth-6 version cannot establish native row-label readback. All other observer scope and cleanup behavior below is unchanged.

## Initial review, retained as history

Read both complete observers and independently compiled both successfully. Verified client SHA256 `fff655f12c671e95d77960531451fbe3d65dd39ba5880fa8c558a375e97f4bd8` and server SHA256 `dfb6df13e66d0db23005a8bfcc4673a1a141bba4e8019ae91403b2c10d01fe2c`.

**9/10 for this bounded diagnostic artifact; no necessary correction.** Studio/experience/client-server guards precede setup. The scripts read existing state, listen to existing events and print observations; they do not require modules, send remotes, move players, complete objectives or write production/gameplay state. `_G` contains only the observer's own handle. Replacement, manual stop and the bounded 240-second timer disconnect owned listeners and release owned references. Deferred sampling checks the lifetime flag.

The actual win event's `f` serial and `d` deadline are preserved. Accepted choices come from observed `postwinchoices`; button `Activated` records an input event only. UTF-8 boundary handling keeps each JSON chunk within 600 bytes and asserts the complete prefixed line stays within 750 bytes. Run, side, user, sequence and chunk indices distinguish streams during reconstruction; missing chunks must be reported as incomplete evidence.

This does not create a feature PASS. State polling is at most twice a second and positions are emitted alongside changed/forced snapshots, not as a continuous movement trace. The server does not invent access to private session serials. Client UI readiness, control readiness and actual accepted routing remain distinct. Native two-player timing/choice/routing and six-row display acceptance are still required separately.

No Studio interaction or production mutation was performed for this review.
