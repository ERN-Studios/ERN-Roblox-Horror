# L3 protection integration map (artifact only)

Initial map was read against Manager 167812. The concrete implementation is now prepared against accepted Manager **173969 / e1332968…b2884**, with before/proposed files, exact baselines, 119 actual-source checks and four negative controls in this directory. See `README.md` and `validation.json`. Runtime and Studio are unchanged; independent critic review passed at 9/10 (see `independent-review.md`).

Reuse the prepared server-only `../PlayerProtection.ModuleScript.lua`, whose reviewed API is `GetContext(player)`, synchronous `Activate(player, originalContext)`, `IsActive(player, exactCharacter?)`, `Clear(player)`, and `Activated(player, character, absoluteDeadline)`. Only its private state/server time authorizes protection. Display attributes must never gate damage or targeting. Its lifecycle already fences character/death/exit and same-level new-round changes. No additional timer or generic effect framework is needed in L3.

## Manager

1. Require PlayerProtection from ServerScriptService. Add `IsActive(player, character)` to `livingPlayer` after resolving the actual current character. This central predicate covers visionGeometry/acquireVisibleTarget, velocity hearing, blackout/final-hall nearestLivingPlayer, hidden-player nearest pursuit, spawn-time initial target memory, attack eligibility and impact confirmation.
2. `eligibleSpawnPlayers` is a separate path (baseline2919) and must also exclude protected current characters. Otherwise a player invisible to entities still selects the Manager's spawn group/anchor. When every participant is protected, Start returns nil. Round Adapter already retries nil Start every.35s while the same hunt generation/token remains active, so expiry needs no new polling loop or one-time spawn suppression.
3. Acquisition filtering alone is insufficient. `updateBrain` keeps a live attack early return, chase visual-loss grace, and target-derived memory after `publishTarget(nil)` in beginSearch. Add a small source-identity field alongside LastKnownPosition, e.g. LastKnownPlayer+LastKnownCharacter. Set it in the four player-derived memory paths (nearest blackout, seen, heard, Start seed), retain it through tracking/search, and clear it when memory is cleared or overwritten by a world CD noise. This lets activation remove only the protected player's remembered route without deleting a teammate's target or unrelated world noise.
4. One per-session Activated connection, included in session.Connections, calls a small non-yielding cancellation helper. Verify liveSession, current exact character and IsActive. Always remove that player's suspicion. If it owns current target, remembered target or attack, invalidate AttackToken before clearing Attacking, publishTarget(nil) to release BeingChased/scream, clear only its target-derived LastKnown/search/alert/patrol route through existing clearGoal, and rearm the existing brain for a fresh eligible target. Preserve existing cooldown rather than resuming a cancelled windup at expiry. Do not call dormant for a protected bystander, as that would erase unrelated pursuit. A defensive check before Heartbeat's updateTableCheck ensures stale target/check state cannot bypass the normal brain via the table-check early return.
5. `beginAttack` already delays a token-checked impact, but currently resolves the player's current character again after the delay. Capture the initiating character (and preferably Humanoid) and require identity equality at impact, in addition to the new IsActive check. This prevents an old windup from reaching a replacement avatar. The protection check must precede AttackSerial, LastCaptureUserId and Health=0. Direct Health assignment bypasses ForceField; suppressing only client feedback is not protection.

The existing physical waypoint/perimeter routing and rate/overlap/teleport contracts remain intact. Cancellation uses clearGoal/clearPath's existing async-token invalidation; it does not implement its own navigation state machine.

## Hiding and table checks

Keep HidingController.eligible, IsHidden, GetAnchor, hidden count, prompt occupancy/capacity, collision suppression, normal exit and saved restore state unchanged. Protection does not make a player stop being hidden and does not free their occupied slot.

Provide an AI-only opt-in filter on the two existing occupancy read APIs (for example optional `excludeProtected` on OccupantCount and GetOccupiedAnchors), backed by exact current hidden records and server IsActive. Normal callers retain current semantics. Manager's chooseTableCheckAnchor and untargeted check validation request the filtered result. A protected-only table is never newly selected; a mixed table remains eligible because of its unprotected occupant.

FlushAnchor must recheck each actual record immediately before changing ExitCFrame, granting flush immunity or calling releasePlayer. Skip protected occupants entirely. Never apply the proposed protection filter to releaseAll/Stop/manual DebugExit or the user's ordinary exit request; those must still restore characters correctly. Existing flush immunity is independent and is not refreshed by item activation.

For an already running targeted check, protected target acquisition is invalidated and endTableCheck(false) cancels its cue/window without flushing; any unprotected teammate can receive a new normal warning. For an untargeted mixed check, continue only while at least one AI-eligible occupant remains; final FlushAnchor ejects only the unprotected occupants. If all occupants become protected, cancel without flush. This preserves capacity, prompts and protected collision/anchor state.

## CD, music, finale and lifecycle

Objective Controller's validPlayer/livingCharacter gates should **not** reject protected players. Collection, carrying, inserting, ordinary interaction and the validated final-hall run-in remain available. No Health mutation exists in Objective/Music/Hiding. Escaping sets Escaped=true before its safe-slot move (baseline Objective1014), which already clears the shared effect; no extra Objective hook is required. RoundActive/SelectedLevel changes already invalidate service context across same-level rounds.

Manager's collected-CD event creates an unowned WorldNoise `{Position,Time,Strength}`. Keep this world event investigable even if a protected player caused it, but do not convert that noise back into a protected player target. Do not clear every WorldNoise on activation. Music/hunt timers, blackout, finale trigger and normal CD lifecycle need no protection edits.

## Focused acceptance

- Before/at/after5.00s: normal vision, hearing, blackout/finale nearest target, spawn group and true damage impact exclude only the protected exact character; forged attributes do nothing.
- Activation while already targeted, visual-loss grace, targetless remembered SEARCH, ATTACK_WINDUP and TABLE_CHECK clears only owned state. Delayed old impact cannot capture/kill after cancellation, expiry, respawn, Stop or a new session.
- Teammate target/suspicion/world-noise investigation are preserved. A protected-only hidden table remains occupied but AI-ineligible; mixed occupancy flushes only the unprotected teammate and restores only that teammate's movement/collision state.
- Protected player may voluntarily leave hiding, collect/carry/insert a CD and run through the final doorway. Escape/death/character replacement/round cleanup invalidate protection and all attack connections normally.
- Reuse existing two-occupant Hiding and Manager test infrastructure, but add actual-source isolated protection fixtures and a bounded native chase/activation test. No claim of multi-client coverage from one physical Studio client.

Only Manager and Hiding require runtime integration under this map. Objective, Music and Round Adapter behavior is preserved and verified rather than rewritten. No user price/account/asset input remains missing.
