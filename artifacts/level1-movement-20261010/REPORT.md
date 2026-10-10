# Fly cleanup can no longer retain an entry lock

The native Studio reproduction started fly while the gameplay body was anchored by entry, released the entry anchor, then stopped fly. The old code restored the captured `Anchored=true` and the character moved 0 studs despite movement input. It also restored old humanoid/root state onto `player.Character` after replacement.

The scoped `DevCheats` change refuses fly while character movement is locked, captures the exact character/humanoid/root for each session, and restores that body's state on stop, death or removal. The flight update verifies body identity before writing. Old queued callbacks cannot change a later body/session. Flight controls and speed mathematics are preserved.

Verification:

- 230 regression assertions pass against the installed mirror. The original source fails the first anchored-entry assertion.
- Full Luau `--null -O0` and native Studio source compile pass. Source, editor source and repository agree; the manifest records the verified SHA256.
- Native entry refusal leaves the root unlocked and the character travels 17.01 studs in 1.51 seconds. Normal fly ON/OFF then walking travels 19.98 studs in 1.50 seconds.
- Normal hold-L return to lobby during fly triggers real character removal/replacement: the session is cleared, new root is unanchored, health is 100, and the body is Running.
- The native probe ran the exact installed fly/lifecycle code with a test-only remote stub because the Studio account is outside the shared developer whitelist. The actual whitelisted developer UI was not exercised.
- Probe objects/connections were removed and Studio returned to Edit. Only the LocalScript Source changed in Edit; no native properties/assets were edited.

Publication succeeded at 2026-10-10 07:28:02 UTC (09:28:02 Copenhagen) for place 131311258779917, universe 10559217407. Studio reported `PublishSuccessful` and the successful CreatorOutput message. See `publication.json`; no version number is claimed and no active servers were restarted.

The originally reported gliding in a fresh round without previous fly use was not reproduced. Normal standing, SignalArchitect movement, crouch and stand worked in investigation. This change fixes the demonstrated stale-anchor/lifecycle defect; it does not assert every possible cause of floor gliding is solved.

`source-before.json` is the recoverable exact Studio script checkpoint; `source-after.json`, `verified-mirror.json` and `verification.json` hold the authoritative export and receipts. No whole-place snapshot was created for this Source-only edit.
