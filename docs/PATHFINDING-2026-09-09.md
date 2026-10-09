# Pool Foam and Mall Manager navigation — 2026-09-09

The reported Level 2 entity was **Pool Foam**. The newly added Pool Slide in
Studio was outside this fix.

## Was working code reverted?

No evidence of a revert was found in Git or the connected Studio edit model.
Before editing, the active Pool Foam navigator/controller/configuration and
Level 3 AI/configuration matched the repository. The Level 3 pathfinding fix
`7c73a739` (2026-08-27) remains present, including single-flight path requests,
coalescing, strategic progress and blocked-route recovery. The Pool Foam
navigation improvements from `13cbaae` (2026-08-30) remain present too.

The latest pre-fix Pool Foam navigator commit, `1cb2ac9` (2026-09-02), changed
only a comment. Its preceding `c2b7527` added opt-in stable routing that Pool
Foam did not enable. Git/reflog inspection found no reset/revert removing the
working fixes. This investigation did not inspect the currently published
Roblox place version.

## Reproduced faults and changes

- **Pool Foam route churn:** repeated identical goals rebuilt healthy routes
  whenever the 0.55-second interval elapsed. The scheduler now requests a
  replacement for a moved goal, exhausted/blocked route or explicit recovery.
- **Pool Foam delayed-route rewind:** after the entity advanced from X=0 to
  X=15 while planning yielded, the installer selected the stale waypoint X=5.
  Planning now uses one captured origin; installation joins the route to the
  current position using the existing floor/step/body checks. Unsafe joins
  preserve a usable incumbent. Forced replacement also preserves that route.
- **Pool Foam watchdog starvation:** the 1.1-second movement watchdog could
  cancel a legitimate calculation before completion. Pending work gets bounded
  grace; both request age and total time without progress bound the wait, so
  repeated young requests cannot defer recovery forever.
- **Mall Manager arrival blockage:** on seed 7331, the half-stud-high
  `Workspace.ElevatorSpawn` plate overlapped the navigation box starting 0.2
  studs above the floor. The resolved goal was almost 10 studs from the player,
  beyond the 5.4-stud attack confirmation range. The Manager stayed in CHASE,
  motionless for over 17 seconds, with no attack or recovery. Shared occupancy,
  sweep and spawn checks now allow 0.6 studs underfoot. Width remains 10.5 studs
  and the top remains 9.6 studs above the floor. Taller obstacles and furniture
  still block; world geometry was not changed.
- **Mall Manager steering commitment:** same-side avoidance refreshed its
  deadline every frame. It now expires after its original interval, allowing
  the Manager to resume straight movement when the route clears.

## Verification

Both new test programs execute the actual production helpers, with deterministic
engine/geometry stubs. Their regression assertions failed before the fixes.

```powershell
$env:LUAU_BIN = 'C:\Users\mikke\AppData\Local\Temp\codex-luau-0.737\luau.exe'
python tools/tests/test_pool_foam_navigation.py
python tools/tests/test_level3_steering.py
python tools/tests/test_pool_foam_audio.py
```

- Pool Foam navigation: **25 checks passed**, including delayed joins,
  stationary/moving goals, unsafe joins, forced replacement, and bounded
  watchdog grace across repeated requests.
- Level 3 navigation: **222 checks passed**, including steering expiry, the
  half-stud support, 0.7-stud obstacle/wall/table rejection, and unchanged
  ceiling clearance.
- Existing Pool Foam audio checks: **24 passed**.
- Studio repeated the delayed-route fixture: obsolete replans **4 → 0**;
  next waypoint after advancing to X=15 changed **X=5 → X=100**.
- Live Pool Foam, seed 7331: **44.43 studs** traversed during approximately six
  seconds, **one** route calculation/installation, waypoint index advanced
  1 → 5, and no watchdog repath. Pre-fix sampling showed a new request roughly
  every 0.6 seconds on that same stationary goal.
- Live Level 3, seed 7331: the player's position on the arrival plate now
  passes clearance; the Manager closes from 118 studs to attack range and
  initiates its attack within **4.52 seconds**. The test then cleans up before
  completing the encounter.
- Existing `ValidateNavigationLayouts`: **20 generated layouts passed**.
- Existing `ProbeChaseForwardProgress`, six seconds per generated map:

| Seed | Travel | Longest freeze | Peak concurrent path calculations |
| --- | ---: | ---: | ---: |
| 101 | 145.19 studs | 0.066 s | 1 |
| 65537 | 125.42 studs | 0.068 s | 1 |
| 1900813 | 82.61 studs | 0.067 s | 1 |

All three live chase probes passed their movement, route progress, attack
safety, speed ceiling and five-requests-per-second assertions. These are
bounded regression probes, not complete playthroughs or exhaustive map tests.

The three production scripts were applied through the conflict-checking Studio
push tool, compiled on write and verified against their repository sources.
The final whole-place compile passed **122/122 scripts**, with no failures or
unstaged probes. Their manifest entries are synced. Original sources are backed up under
`.studio-push-backups/20260909-171552` and the final controller adjustment under
`.studio-push-backups/20260909-171739`. Other existing Studio/repository drift was
left alone. No Roblox publication or Git push was performed.

## Follow-up: chase players underneath tables

The owner then requested that the Level 3 entity pursue players even while they
are underneath a table. This deliberately changes the earlier hiding contract.

Hidden players now remain eligible for nearest-player targeting and retain
`BeingChased`. The AI approaches the selected player's authoritative hiding
anchor, gives the existing two-second warning, flushes the occupants and
continues chasing. Targeted checks bypass random patrol selection and patrol
cooldowns. They still require proximity and a clear approach through the
collidable world. Target changes, leaving hiding, death or obstructed sight
cancel an obsolete check. Direct attacks still respect walls and the existing
1.5-second post-flush immunity.

Verification:

- `tools/tests/test_level3_hidden_chase.py`: **48 checks passed**; the historical
  target-eligibility implementation fails the hidden-player regression.
- Previous Level 3 navigation tests: **222 checks passed**.
- `tools/playtest_level3_hidden_chase.luau` exercised the real AI and hiding
  controllers on two generated worlds: seed 7331 with the player hidden before
  spawn, and seed 101 with the player entering hiding during an established
  chase. Both retained the target, approached the table, warned for approximately
  two seconds, flushed with immunity and resumed CHASE. Travel was 116.60 and
  99.20 studs; time to flush was 5.88 and 5.32 seconds respectively.
- Existing `ValidateConfiguration` passed, including its nine generated seeds.
- AI, hiding controller, test suite and configuration were pushed, compiled and
  verified against Studio. Pre-push copies are in
  `.studio-push-backups/20260909-173654`. Studio was returned to Edit.
