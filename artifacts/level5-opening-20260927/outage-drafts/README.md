# Temporarily disable Level 5 outages

Prepared against the current opening-task Studio export, with source hashes in `manifest.json`.

The draft adds a module-local `OUTAGES_ENABLED=false` switch and a first-statement guard in `Outage.Trigger`. It returns `false, "Level 5 outages are temporarily disabled"` before session inspection, validation, serial changes, schedule allocation, JSON encoding, attribute writes or new connections.

`Start`, `Cleanup`, fixture metadata, H/chute exemptions, ownership checks and lifecycle connections remain byte-for-byte unchanged. Re-enable later by changing only the switch to `true` after review. This guard prevents new schedules; it does not clear a schedule already active in a running server. Apply after the current QA session is stopped, then verify a fresh round.

Validation: Luau O0 compilation, exact two-line scope check, and 78 mock-service behavioral assertions. Tests cover cold/invalid/repeated gate calls, no blackout schedule, no mutation or allocation, metadata preservation, foreign-owner preservation, cleanup, architecture removal and failed-start rollback. This is not a native playtest claim.

No Studio or repository changes were made. Parent must re-read exact live Source and editor Source and compare against the baseline before applying the scoped patch.
