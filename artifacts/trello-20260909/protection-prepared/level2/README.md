# Level 2 protection integration — proposed copies only

Prepared for the approved 5-token / 5-second protection item, 10 September 2026. This is an independent, bounded part of `../PlayerProtection.ModuleScript.lua` integration. **No runtime file, Studio instance, purchase, profile, UI, DataStore, enable flag or published place has been changed by this preparation.** The whole item is not complete.

## Proposed changes

`before/` holds exact byte copies of the four existing files; `baseline-sha256.json` identifies them. `proposed/` holds full proposed replacements at their intended paths. `level2-protection.diff` contains only this integration. Run `prepare.py` to regenerate from the saved baselines, never from a moving live source. Root should merge the diff if another task has since changed these files; do not overwrite unrelated newer changes with the full copies.

| File | Change |
|---|---|
| Pool Foam Controller | Common `livingPlayer` rejects private protection. `instantKill` independently checks again immediately before lethal feedback/motion/health side effects. `triggerChase` requires a presently eligible observer before latching a hunt. On activation, release only that player's reference-counted chase/target/progress/dwell state, owned footstep memory and routes; recompute affected observation while retaining eligible teammates. Preserve the entity's global chase latch, phase, speed ramp and teammates' chase marks. |
| Pool Foam Observer | The common character predicate excludes protection from incoming camera telemetry, cached camera visibility and server-head fallback. An owned activation connection discards only that player's camera sample. Actual scene rendering on the protected client's screen is unchanged. |
| Pool Slide Controller | The shared target predicate and final `TakeDamage` guard use private protection. Cancel this character's pending Attack record immediately through the activation signal and synchronously at the start of `updateAttack`, which runs before target refresh. Release its marker, stop/replan navigation and switch the existing animation driver to Idle. Preserve cooldown and monotonic attack serial so the cancelled windup cannot replay. |
| NoiseRegistry | Add an optional `sourcePlayer` to `Add` and ignore protected owned sounds in `GetBest`. Foam reports footstep ownership. Existing two-argument pump/relay/world calls retain their loudness/range/decay behavior. The registry is never globally cleared by one player's activation. A Foam patrol remembers its player-noise owner so an old route can be cancelled even after its latest hearing sample changes. |

The reviewed server singleton must be installed as `ServerScriptService.PlayerProtection` in the same eventual integration as these consumers. The `require` is mandatory; a missing service must not silently turn protection off. All new connections are placed in the encounter/observer's existing `Connections` collection and disconnected by its existing Stop/Destroy path. Global world-noise clearing at normal round teardown remains unchanged.

There is no asynchronous Foam capture to restore: that controller emits its fatal client event and sets Health to zero in the same non-yielding contact path. Its new final guard precedes both. Slide's actual pending damage lives in `session.Attack`; clearing it and selecting Idle uses the existing Rig Adapter's behavior that stops the previous Attack track. No Rig Adapter, Navigator or configuration changes are proposed.

This prepares Level 2 only. Existing Level 1 two-argument footsteps have no owner and remain behaviorally unchanged; the later Level 1 integration must pass ownership too. Other levels' AI, damage, capture and pit paths, the persisted charge/reservation/refund transaction and the player controls remain outside this delivery. Pool Slide stays disabled/unverified under its current configuration.

## Focused validation

```powershell
python artifacts/trello-20260909/protection-prepared/level2/prepare.py
python artifacts/trello-20260909/protection-prepared/level2/test_level2_protection.py
```

The harness executes the **complete reviewed protection service**, the **complete proposed NoiseRegistry**, and extracted actual functions/callbacks from the three proposed Level 2 modules. It does not implement parallel copies of those decisions. Geometric line-of-sight, camera-frustum results, animation playback and Navigator operations are controlled hosts; this is not physical gameplay evidence.

**123 checks passed.** Coverage includes private-state authority versus spoofed display attributes; 4.99/5.00-second target eligibility; protected/eligible mixed players; old accepted camera reports, new report rejection and fallback sight; both observer/controller listener registration orders; multi-entity chase reference counts; cached protected-only versus mixed observations; stale observer lists that previously could latch a hunt; proximity-dwell ownership; pending Slide windup cancellation both through the actual activation callback and with callback delivery withheld; unchanged cooldown, damage amount and one-hit behavior; eligible teammate attacks; a new valid post-expiry attack without resuming the cancelled one; Foam lethal side effects and phase/wall guards; cached player-noise routes, mixed footsteps and unchanged pump/relay/crouch/decay behavior. Actual Observer.Destroy disconnects its activation listener.

All **four full proposed modules compile** together with Luau 0.737 (92 KB bytecode); including the complete service, **five full modules compile to 97 KB**. The separate service harness remains **98/98**. At preparation completion all four runtime SHA-256 values still matched the saved baselines, confirming no runtime edits.

Independent critic score: **9/10 for this bounded artifact/code preparation**. The critic read the exact diff, tests and actual surrounding update/observation/suspend/resume code, independently reran 123/123 checks, compiled all five complete modules and verified all four runtime hashes. No necessary correction within this scope. This score does not approve runtime installation or the complete item; native deferred signal ordering, real Navigator/Attack stopping, pause/resume and two-player acceptance remain pending.

## Root-owned native acceptance after eventual integration

Use isolated server activation with a valid pre-yield context, without fake purchases or enabling the unverified Slide in the production configuration. Validate real deferred signal ordering with two participants: the protected player's Foam camera must not freeze/reveal/latch the entity, its chase references and player-noise route must clear, and a visible eligible teammate must still be pursued. Repeat activation during a Slide windup in a separate isolated fixture; check its actual Attack track stops, pending navigator work stays stopped/replans, no old windup hits, cooldown remains, and a new attack can hit after the five-second deadline.

Include a pump running during activation, old footstep hearing, paused/resumed encounters, round cleanup/restart and respawn so old callbacks cannot affect a new encounter or character. Verify native movement/animation and all final damage sites as part of the complete item, followed by independent review and root's mouse publication. The immediate offline signal host and stubbed Animator/Navigator do not certify these engine behaviors.
