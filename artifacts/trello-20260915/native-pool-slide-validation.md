# Pool Slide native validation — 21:37 UTC

Two generated native rounds exercised the production navigator. First resolved
seed 1421051986 (random; request fell back after generation attempts); second
pinned seed 1420318884, generation attempt 1, 42 halls.

- Random: two genuine pump activations, Slide spawned 144.93 studs away;
  it reached the stationary player and entered ATTACK. Moving the player to a
  different authored node produced a 204-stud route and arrival within .18 stud.
- Pinned: attempted Foam isolation through the native Server command bar only
  changed the replicated status. Later hiding-module inspection showed command
  bar require has a separate module state, so Foam simulation was not proven
  stopped. Slide remained enabled/unpaused. Existing whitelisted
  two-pump developer control triggered the spawn 157.70 studs away.
- Character navigation moved the player from (-601.55,-415.45) to
  (-644.56,-263.15), about 158 studs. Slide followed, reached the player and
  entered ATTACK. Health remained 100000000 throughout this confirmed leg.
- CSV recorder's CHASE/ARRIVED zero-waypoint episodes are normal stationary
  arrival at the target; they are not clearance deadlocks. No CLEARANCE latch
  or computing timeout was observed on either confirmed route.
- A subsequent longer walking request ended with the player back in the
  lobby. Cause was not captured; Foam isolation was ineffective and another
  Foam kill is plausible, not proven. This is not an additional pass.
  The earlier random moving attempt was interrupted by Foam's instant kill.

Offline source-executing regression proves the fixed three-probe clearance
release against HEAD, which fails the two targeted latch checks. The live runs
exercise general stationary/moving recovery, not an artificially recreated
clearance obstruction. All test-only state was cleared by Stop Play.

Raw evidence: native-pool-slide-still.csv, native-pool-slide-final.csv,
native-pool-slide-pinned.csv. CSV `cpu` is os.clock monotonic elapsed time;
it is not CPU-only time. Actual seeds are recorded above because the first
CSV's input-override seed column does not contain the resolved random seed.
