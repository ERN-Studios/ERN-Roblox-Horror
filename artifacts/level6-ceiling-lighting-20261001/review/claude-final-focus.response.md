**None blocking**, on the facts given. Excluding fills from the baseline array keeps the old indices intact, and fills re-derive from their primary on recovery.

One residual risk: the sweep writes fills directly, but they are restored only when a primary property actually changes.

Runtime checks:
1. **Full blackout cycle**, including a flicker follower caught in its off phase: rerun the fraction/enabled audit after recovery; expect zero mismatches and no fill stuck at 0.
2. **Cleanup/rebind**: reload Level 6 twice; confirm three connections per fill, no duplicates, and none firing on destroyed lights.
