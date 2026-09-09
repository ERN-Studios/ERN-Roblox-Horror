# Retired Slidemouth — 2026-08-31

Slidemouth no longer runs in Level 2. The Pool Slide humanoid replaces it at the
second distinct pump; its four audio recordings remain in the sound library and
are played from the new entity.

The actual previous Studio Controller, Test Suite, disabled Client, Template and
Walk Keyframes were moved (not deleted) to
`ServerStorage.Level2RetiredSlidemouth_20260831`. Each retains its
`RetiredOriginalPath`; the client also records `RetiredOriginalEnabled`.
The three Lua files here are exact copies of the retired live source, not the
older repository Controller snapshot. They are recovery references, not active
runtime scripts. Relative module dependencies will need their original locations
if restoring; do not execute archived scripts in place.

The pre-change Adapter, humanoid controller, Sound Controller, Objective,
GameManager, DevCheats, ZyntraStore and presentation scripts are also preserved
in `ServerStorage.PoolSlideSecondPumpBackup_20260831`.

Existing Slidemouth authoring source packs and marketing history are retained.
