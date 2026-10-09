# Rotated Walk native transition acceptance

Artifact only. Run `quarter-acceptance-cached.luau` as a server helper during normal Studio Play after parenting the reviewed quarter folder as `ServerStorage.TEMP_PoolSlideQuarterWalk_20260910` and the validated data cache as `ServerStorage.TEMP_PoolSlideMeshCache_20260910`. No animation IDs, original clips, rig, production sources or security settings change.

The original validated cached fresh evaluator is retained through reversible, single-match seams in `prepare.py`. The original mapper, complete vertex checks, fresh Animator lifecycle, raw capture before expensive skin work, weight/Ended/reference checks and cleanup remain. The quarter copy starts naturally at its authored zero; this helper does not seek the fresh destination.

Twenty-eight cases use four outgoing quarter phases: dynamic Idle→Walk; Walk→Idle/Attack; and Walk↔Run at both 20 and 32 stud/s. Walk reference is 10.82; Run reference is 27.6. Attack uses the existing .12 fade; all others .16. The four dynamic cases run for .72 seconds with acceleration24, normal speed10, and the current adapter's .1-second/.02 rate-change cadence. These are discrete unobstructed measured-speed inputs to the actual Animator, not a physical NPC movement test or obstacle simulation. Each frame records the command actually in force during capture; ramp changes apply to the next frame. The final observed native rate must reach 10/10.82, with at least three rate changes. Frame gaps above75ms fail validation.

Walk↔Run here uses constant measured-speed inputs. Actual Controller mode changes can start Run while speed is still around10 or start Walk while it decelerates from20. Those changing-speed mode transitions require encounter evidence or a separately bounded dynamic case; this diagnostic does not claim to simulate them.

Root already measured actual native pose parity separately at twelve phases/240 bone pairs, plus241 continuous frames/four loop wraps. This helper does not repeat those tests. It tests affected transitions only; it does not recertify all animations or navigation.

Reports: `_G.TrelloPoolSlideQuarterAcceptanceResult` and `ServerStorage.TrelloPoolSlideQuarterAcceptanceFull` in40,000-character StringValue chunks. Existing reports are refused before work. `ok` means the harness completed validly; `targetedAcceptancePass` also requires all measured full-skin plane gaps to be nonnegative. Native failures and raw poses remain saved. Contact thresholds use the same static-box plane+.08 convention as previous probes.

Local preparation/checks:

```powershell
python artifacts/trello-20260909/pool-slide-quarter-acceptance-prepared/prepare.py
python artifacts/trello-20260909/pool-slide-quarter-acceptance-prepared/test_targeted.py
```

The test executes the actual changed matrix, ramp and fresh capture loop against a bounded clock/track host (regular and jittered frame times), including wrong-rate, under-sampling and backwards-clock negatives. It does not simulate native skin blending. All743 checks and wholecompile passed. Audio independently repeated the checks and reviewed the code:9/10 as a diagnostic artifact, with the dynamic mode-transition limitation above. Root native results are separate.
