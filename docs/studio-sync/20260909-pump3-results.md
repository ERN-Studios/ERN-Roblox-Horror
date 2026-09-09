# Level 2 pump 3, spawn distance and resource review — 2026-09-09

Studio is authoritative. No repository or Trello source was pushed into Studio.
The local dirty checkout was preserved in e736b4e, then all 52 remote commits
through 7f13f53 were retained in merge f9be5bc. A read-only Studio export
resolved the runtime mirror, not the reverse. Only the current private Pool Slide
Controller and Navigator were subsequently edited with exact Source/editor CAS.

## Implemented and exercised in Studio

- Spawn minimum increased from 60 to 100 horizontal studs from EVERY living
  participant; preferred candidate distance 140. Final grounded distance and
  visibility telemetry are recomputed immediately before the no-yield commit.
  No safe anchor means retry, not an unsafe fallback.
- Static obstacle filters are no longer rebuilt on every body/sweep query.
  Character membership is still checked every time and cached references are
  released by Destroy. Pool Foam's separate navigator is untouched.
- Optional path shortcutting has its own 0.1-second cooperative wall budget,
  reserving 0.2 seconds of the existing request deadline for installation.
  Stationary entities no longer re-certify an unnecessary path splice.
  All normal stride collision checks, door rules and request ownership remain.
- A real baseline exposed the zero-movement long-route failure. The cache alone
  did not solve it; the optional-budget/install fix passed two different layouts.
- Native value fixtures: cache 38/38; installation/deadline ownership 26/26.
  These are mocked control-flow checks, not gameplay/performance substitutes.

## Real pump tests (diagnostic player placement, one actual test client)

| Layout seed | Spawn distance | Same entity ENRAGED at 3 | Travel in 20 s | Max measured speed | Exit powered |
|---|---:|---|---:|---:|---:|
| 1254293067 | 146.165 studs | PASS | 513.307 studs | 32.001 studs/s | 11.658 s after pump 3 |
| 1094051225 | 153.290 studs | PASS | 383.095 studs | 32.003 studs/s | 11.618 s after pump 3 |

Both runs passed all 9 checks: no entity at 0/1 pumps, one spawn at pump 2,
safe measured spawn, the same entity at pump 3, speed, movement, original exit
timing, and no duplicate entity. Zero coarse direction reversals in both windows
is not a guarantee against oscillation in every map. Not an ordinary-input escape
or a complete multiplayer encounter test.

Server ScriptProfilerService sampled actual ENRAGED encounters at 1 kHz.
The post-fix budget4 run attributed 698.742 ms unique inclusive sampled script CPU
to Pool Slide over 20.445 s, while it moved 513 studs; filter refresh was 7.456 ms.
The earlier stalled baseline attributed 1843.447 ms and 631.674 ms respectively.
Different seeds/workloads: these are observations, not a controlled percentage
speedup or total machine/server CPU usage.

SceneAnalysis active inspection found one owned Path and four owned animation
tracks for this entity; those are intentional active references. After natural
round reset, later inspection showed no references attributed to its production
Navigator/RigAdapter. Unrelated/unknown references and test-held objects were
not deleted. Per-script Lua memory was unavailable because Studio reported
STUDIOPLAT37936 disabled; whole-Studio memory totals are not entity RAM.
No long-session leak or maximum-player-count certification is claimed.

## Preservation and handoff

Both temporary test scripts were removed by exact Source/editor/token guards,
and their source and results are archived under
tests/level2/poolslide/studio-review-2026-09-09. Server profilers stopped cleanly.
Final inventory: 122 scripts, only the two intended production sources changed,
no other sources removed; both resulting files were re-exported from Studio.

The native template backup under assets/level2/poolslide/native-studio-2026-09-09
is a single-model backup, NOT a whole-place backup. Non-script game data has not
been overwritten from Git. Source manifests distinguish that limitation.

Publication is still held: the pre-existing entity integration is in
StudioValidationMode=true and its rig/fit acceptance flags remain false.
This scoped pump/performance test does not complete the broader multiplayer,
rendered-animation and ordinary-escape acceptance from the integration task.
Do not publish the validation-only configuration or silently flip those flags.
No Roblox publication receipt exists for this change.
