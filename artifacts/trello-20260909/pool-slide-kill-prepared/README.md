# Pool Slide attack reach — prepared correction

Card **UmtTK3MA / #62**, ARI `6aa288e5364a5cc2fe2baecc`: “The Pool Slide monster in Level 2 does not appear to be able to kill players. Investigate and fix its attack/kill behavior.”

The prepared change corrects a concrete mismatch between the accepted large monster's navigation clearance and its much smaller attack radius. It changes **one runtime value in one Controller file: `ATTACK_DISTANCE = 5.5` → `10.5`**, plus three explanatory comment lines. No production or Studio file has been changed by this preparation.

## Diagnosis and bounded calibration

The saved v1839 release encounter proves that the old Controller can kill on clear floor. `../pool-slide-acceptance-1660039617-generation1.json`, final window, records a real target's HP100→0 during ATTACK serial1 with XZ distance4.957974891 and vertical3.520030141. The nearest Pool Foam was974.057529 studs away. The first observed ATTACK to death spans0.449846 seconds at a coarse sampling cadence; it does not measure the exact callback deadline. This rules out a universal no-damage or pivot-height failure. It does not identify every cause of the new user's report.

Current `navigationTuning` uses the accepted template's AgentRadius7.5 and WaypointArrivalDistance1.4. The actual Navigator `_bodyVolume` is an axis-aligned square14.8 studs wide, half7.4, with unchanged height16.4. The collision body stops outside a wall even though the visual parts themselves are noncollidable. Characters are excluded from navigation casts, so this is world clearance rather than player collisions.

The real authored avatar's collidable negative X/Z extents previously measured1.0218506/1.0231628 studs. In a flat inner corner with perpendicular walls and equal small clearances on each side, the nearest standable monster center is therefore9.019137567 studs from the player's HRP in XZ. The actual `_reachedGoal` can accept a certified approach up to another1.4 studs before that point:10.419137567 total. A straight side-wall example requires7.7781494 including the same arrival allowance. The old5.5 cannot attack either stopped case. An initial8.25 candidate covers the wall but fails the corner; the negative test records that failure.

The **10.5** proposal is a concrete calibration for this accepted body, authored avatar and arrival margin. It leaves a small margin above10.4191. It is not a universal scale formula, a promise that arbitrary obstacle approaches are in reach, or a proof that the pathfinder chooses the exact fixture approach. It also expands the attack circle on open floor, so native visual contact at the longest range must be judged before release. If the swing looks disconnected from its victim, that is an unresolved acceptance issue, not something the numerical tests override.

GroundOffset6 moves the model pivot; attack distance correctly uses Navigator foot in XZ with a separate vertical gate−1..7. The marker is not the damage trigger: the server samples once after the existing0.5-second windup, checks140° frozen facing, range, collidable LOS from foot+Y3, current living character/round and private Shield, then calls TakeDamage100. No marker, rig, ragdoll, target selection, animation, velocity, navigation radius, pursuit speed or Pool Foam change is needed for this narrow mismatch.

Roblox documents that `TakeDamage` respects a protecting ForceField; the proposal keeps that API and does not bypass loading protection. [Official Humanoid API source](https://raw.githubusercontent.com/Roblox/creator-docs/main/content/en-us/reference/engine/classes/Humanoid.yaml)

## Preserved behavior and verification

`test_combat.py` passes **219 checks**, **four negative controls** and **three whole compiles**. It executes the actual Controller combat/updateModel/heartbeat/Stop functions, actual Navigator `_bodyVolume` and `_reachedGoal`, and the **complete current installed PlayerProtection module**. It checks:

- Side-wall and corner terminal positions, actual approach acceptance at0/.7/1.4 margin, stale-approach rejection, precise reach/height boundaries and the historical open-floor distance.
- Attack start before and after movement, no early damage, one victim/one hit, unchanged recovery/cooldown, no damage to a nearby teammate.
- Physical LOS, behind/outside-arc and beyond-reach dodges, pause/stop/world-generation/round/death/respawn/exit guards.
- Real private Shield activation during windup, cancellation through both delivered event and polling backstop, full5-second expiry, and forged display attributes. A deterministic TakeDamage host also preserves temporary ForceField semantics rather than bypassing legitimate loading protection.

The four mutants restore5.5, substitute8.25, remove LOS, or remove impact facing. Each fails its specific behavioral assertion. Reversing the single value/comments delta recovers the baseline byte-for-byte after normal line-ending normalization. Six production source hashes remain unchanged, including Config, Navigator, Rig Adapter, Foam and PlayerProtection.

Geometry rays, Animator tracks, physics timing and navigation movement are deterministic hosts. The terminal fixtures prove actual combat/arrival predicates at analytically body-clear points; they do not run ComputeAsync or native `_centreRoute`. No new native pursuit, visual contact or hardware test is claimed.

Run: `python artifacts/trello-20260909/pool-slide-kill-prepared/test_combat.py`. Optional `--source <path>` verifies the same exact delta against another candidate copy without modifying it. `prepare.py` is artifact-only and refuses runtime baseline drift.

## Handoff

Independent prepared-code/diagnosis score: **9/10**. The critic reran all219 checks, four negative controls and three compiles, with no required code correction. See `independent-review.md`; this does not replace the native contact and approach acceptance below.

Only install `proposed/ServerScriptService/Level 2 Systems/Level 2 Pool Slide Controller.ModuleScript.lua` after the independent review and root's normal source checkpoint. Baseline raw SHA256: `f3b7bdff91e751c97f64ddcd2e9efd2dacc3b3d2a26a7ead40e01885e5c48b03`. Proposal SHA256: `9f8b259843309d3935644737a462152c1fca54707ac035dff8a4f93b86b01d60`. The retired `DRAFT ONLY` header predates this task; actual v1839 installation/publication is established by the release journal. It is preserved to keep this patch narrowly reviewable.

See `native-acceptance-plan.md` for the four bounded normal-play scenarios: open floor/wall, inner corner, preserved counterplay and normal cleanup. Root owns installation, native execution and mouse publication. Pricing, Testing cards, GM/circle/slide/ESP compositions and Trello/Discord remain outside this artifact change.
