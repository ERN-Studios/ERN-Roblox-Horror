**Verdict (excerpt scope only):** nothing in the supplied lines provably breaks the contract. Eight conditional or hardening items remain, and items 1–3 could silently suppress or mis-gate the finale if an unseen assumption is wrong. Check item 1 first. This is not a full-file approval.

## Source findings

1. **AI 3416, generation domain (blocker if wrong).** The spawn requires `Level3_FinalHallCrossedGeneration == generation`; Objective 168 writes `session.Generation`. The call site is not supplied. If the AI passes its own hunt or session counter, or anything the forced Stop then Start bumps, the Manager never spawns and nothing errors. Fix: both modules read one round-generation source; assert equality at finale Start.

2. **AI 3400/3402/3416/3422, four deferral paths.** The supplied summary says "blocked endpoint only". The source also returns nil for no records, a missing hall, and any uncrossed or rootless living participant. 3416 is contract-consistent, but once `…ChaseActive=true` is published, a respawned or rootless participant means indefinite, silent no-Manager retries. Fix: keep the behavior, publish a distinct telemetry reason per path, and confirm the .35 s retry covers all four.

3. **Objective 150–172, latch not cleared on death in the shown lines.** Clearing happens only when the Character instance changes (152). A same-Model revive keeps the table latch and the attribute, so the player counts without re-crossing; AI 3416 inherits this. Lines 175–182 were not supplied and may cover it. If not, add before the `end` at 172:
```lua
elseif session.FinalHallCrossed[player] then
	session.FinalHallCrossed[player] = nil
	if character then character:SetAttribute("Level3_FinalHallCrossedGeneration", nil) end
```
This is moot if every revive creates a new Character.

4. **AI 3403–3405, `stateFolder()` and `Random.new` unused through 3431.** If unused below, delete them: they add a possible nil-index throw to the finale spawn. If `random` is used below 3431, that use is outside this review and must be checked against the no-random contract.

5. **Objective 192, ordering (hardening).** State `Level3_MallManagerHuntActive=true` is set before the World/workspace finale flags (193–198). AI 3854 reads workspace, so this is probably safe. A State listener that reads those flags under Immediate signals would start a normal hunt. Fix: move 192 after 198.

6. **Reader 1084–1097, degraded PLAYER state.** With `enabled` and `target == nil`, the needle, centre line and arrow are all hidden (blank dial). With a target but `root` nil or unparented, the arrow stays visible and is never updated. Fix:
```lua
local live = enabled and target ~= nil and root ~= nil and root.Parent ~= nil
needle.Visible, centerLine.Visible = not live, not live
playerCompassArrow.Visible, playerCompassLabel.Visible = live, live
if not live then playerGuide.Visible = false end
```
Whether the fallback is the needle or a "locating" label is a design call.

7. **Reader 900 vs 1094, toast flash (conditional).** Line 900 hides the pin, but the next RenderStepped re-shows it unless `panel.Visible` is already false. If panel visibility is only recomputed in the 10 Hz `updateReader`, the pin reappears over the toast for up to 100 ms. Fix: test the toast flag directly at 1093.

8. **Reader 1045, count precedes states.** `goal <= 0` (unreplicated) returns EXIT, and a saturated `inserted` overrides WORLD/DROPPED/unknown. Objective 394's `InsertedCount or ModuleCount` fallback makes this worth checking: if `ModuleCount` is a total, EXIT is premature. Fix:
```lua
if unlocked then return "EXIT" end
if goal < 1 then return "SCAN" end
```
then let the loop decide. The caller's guard is unseen.

**Checked, no finding in the shown lines:**
- Strict `>` 50% crossing test.
- Protected players counted and targetable, attack immunity kept (139–154, 2342–2357, 2498).
- Finale with no target goes to WAITING without patrol.
- Endpoint XZ/FloorY placement with no alternate, facing fallback, zero finale grace.
- Bearing sign, vertical-camera heading and edge-pin rotation math.

Pin construction (non-interactive) and destruction are not in the excerpt.

## Owner-reported mocked checks

The SHA256s, compiles, 80 assertions in 33 scenarios and 60 reader function checks are taken as reported; I did not run them. They do not settle item 1 (unless both real generation sources were exercised together), item 3 (same-Model revive), or items 6–7 (visibility sequencing across frames).

## Unverified runtime

| Case | Expect |
|---|---|
| 2–4 players; last one at 49.9% then 50.1% | No Manager, then one at EndPoint in CHASE on first tick |
| Protected player crosses last or is nearest | Counted and chased; no damage |
| Death and respawn (or in-place revive) after latch | Must re-cross |
| Leaver, escapee, spectator in hall | Excluded |
| Rootless character; prop or corpse on EndPoint | Deferred, no alternate placement, spawns when cleared |
| Player standing on EndPoint | Spawns there; no fling |
| Player beyond EndPoint+2.5 or outside width at DONE | Confirm unreachable, else finale blocks |
| Second round, same server | Stale attributes ignored |
| EntityPaused at trigger | Chase starts on unpause |
| CD states: all CARRIED; mixed; one DROPPED with collected==goal; nil; all INSERTED | PLAYER; PLAYER; SCAN; SCAN; EXIT |
| Pin in view, each edge, behind, camera vertical, fast pan | Correct edge and rotation; no one-frame lag |
| Toast, hide, modal, hiding, spectate switch, teardown | Pin gone at once; no orphan |
| Notched phone, both orientations; touch under pin | Inside safe area; input passes through |
| CD player not streamed in | Attribute still gives position |
