# u0rLQTOe / #60 — full lobby circle

Exact request: “When a lobby has reached its player capacity, prevent additional players from entering its circle.” Prepared code only; no production, Studio, UI, Trello or publication action.

The only functional source is `ServerScriptService/GameManager.Script.lua`. The immutable baseline is the currently installed, not yet published revised-Continue source, SHA-256 `3615b6a3ca5eb8dde3acdcc7c4f03ed674b5cc84641bce6ed07670e67c3e5d58`. Final proposed SHA-256: **`9ffea3691bc56e94afd297c97102d9e5679312cff8dda117acd02d44970234db`**. The full files are in `before/ServerScriptService/GameManager.Script.lua` and `proposed/ServerScriptService/GameManager.Script.lua`; `prepare.py` makes the narrow transformation and diff after its baseline guard.

## Current source and scope

`TunnelLobbyBuilder.addQueueStation` authors each painted circle as diameter **14.82**, radius **7.41**, with `QueueDetectorShape="Circle"` and `QueueRadius`. Four pads per bay are centred at local offsets `(-9,-13.2)`, `(9,-13.2)`, `(-9,13.2)` and `(9,13.2)`. The existing `CircularBayDiameter=56` and `ChamberFloor` identify the surrounding 28-stud bay. No queue geometry or builder instance is added.

GameManager already limits accepted party members through `station.maxPlayers`, configured by the actual host to 1–6, but leaves extra characters physically inside. Its previous `playerInsideZone` uses a square despite the round artwork. The proposal reads the already-authored radius for circular membership and keeps rectangular fallback for a legacy zone. The old Builder comment describing the radius as visual-only predates this change; the values themselves are unchanged.

The existing host configuration, privacy, countdown, cancellation, launch and transfer paths remain the authority. No price, purchase, paid benefit, maximum party size, Continue behavior, slide placement or ESP behavior is changed. `launchStation` is tested byte-for-byte against the baseline.

## Admission and physical correction

The new synchronous selection pass retains **current accepted characters**, with the host first, before filling remaining slots in the existing arrival-time/UserId order. Leaving, dying, disconnecting or replacing a character removes its old eligibility; a new character does not inherit its predecessor's timestamp or admission. Configuration/cancellation/reset advance a small station epoch.

Friendship lookup remains in the ordinary queue path. It can yield, so the result is fenced by host, epoch, privacy, current character and player presence. Occupancy is read afresh after the lookup. The physics-frame pass only reads the existing friend cache and never calls the friends API, waits or yields. A cold unknown friend does not displace an accepted member.

When the authoritative accepted count reaches capacity, the server corrects only extra living, unanchored, non-round characters back outside. It tries at most **16 deterministic nearby candidates**. A candidate must stay within the existing bay's body margin, outside every other queue pad with margin, clear of actual colliders, and satisfy the existing **`arrivalPointFree` 3.9-stud player separation**. Selection and placement have no yield between them, so the first corrected player's real position is considered for the second.

The collider query uses `RespectCanCollide=true` and a **3.3×5.5×3.3** box. Its size covers the previously recorded authored rig collision bounds in `spawn-spacing-prepared/native-geometry-results.json`, including any yaw: local minimum `(-1.0218506,-1.1738281,-1.0231628)`, maximum `(1,2.6881104,1.2267151)`. This is the project's measured character envelope, not certification of arbitrary future oversized avatars. `RespectCanCollide` expresses physical intent; no engine bug involving collidable parts' `CanQuery` was claimed.

Placement translates the whole model by the HRP delta, preserving the authored PivotOffset, height and facing. Only inward velocity is removed; vertical/tangential movement and normal controls remain. No wall, collision group, anchor, character listener or new remote is introduced. Accepted members can exit freely. Capacity reopening allows later entry, and reset/cancel releases the restriction. During a full launch, the existing accepted cohort is frozen and never moved; departures free physical space without admitting anyone to that in-flight launch. Reserved servers, active Studio rounds and a removed lobby are excluded.

This is server boundary correction, not a continuously colliding wall; native client prediction/smoothness still needs observation. If every candidate is blocked/occupied, the pass performs **no forced placement and still refuses extra membership**. That deliberately preserves body safety, and is not reported as successful physical exclusion in the no-space fixture.

## Focused validation

`python artifacts/trello-20260909/full-lobby-circle-prepared/test_circle.py`

**257 actual-source checks, three targeted negative controls and two whole-file compiles pass.** Controlled fixtures execute the real containment, arrival ordering, membership selection, friendship path, configuration handler, reset, target search and capacity enforcement. Cases cover 1/2/6 capacities, rotations, authored pivot offset, circle-vs-square boundary, same-frame entrances, incumbent preservation, free exit/re-entry/disconnect, replacement character identity, host settings/cancel/proximity, cold friends, five real coroutine suspension cases, full busy launch, reserved/Studio/removed-lobby/dead/round exclusions, a member at the edge, two simultaneous same-radial rejects, no safe target, physical furniture and all four authored bay offsets with neighbouring pads present. The source launch function is unchanged.

The independent critic reran those checks and reviewed final source `9ffea369…234db`: **9/10 for this prepared code**, no remaining code blocker. See `independent-review.md`. Native multiplayer correction and publication remain pending.

The three negative controls remove incumbent priority, reuse pre-yield occupancy, or remove the shared body-spacing check; each fails its intended regression. The host uses controlled vector/yaw/instance state and AABB obstacles; it does not certify native physics replication, rendering, network ownership or real multi-client movement.

Root may test a merged GM without changing this artifact:

```powershell
python artifacts/trello-20260909/full-lobby-circle-prepared/test_circle.py --source <absolute-merged-GameManager-path>
```

That executes the selected actual functions from the supplied source, keeps the launch parity assertion and negatives, compiles the whole supplied GM and records its exact hash in `validation-merged.json`. It does not apply the source. Root owns the separate proof that the circle, revised slide and ESP transforms commute and preserve their other regions.

## Later native acceptance

After independent code review and root's scoped merged installation, use real players in the normal lobby. Check 1/2/6 host capacities and the corresponding painted circle; confirm an extra player cannot remain inside under ordinary movement, while every accepted member stays untouched. Repeat with a member on the edge, two extras approaching from the same direction, the pad side near a neighbouring circle, and furniture/wall proximity. Observe actual avatar clearance and correction smoothness; client prediction must not be mistaken for a server admission.

Check free exit and immediate capacity reopening, re-entry after another player takes the vacancy, disconnect, host cancellation, public/friends cold-cache handling and normal launch/failed-launch reset. Check that the existing configured UI/countdown and actual launch cohort remain correct. A one-client synthetic fixture must not be labelled real multiplayer. Run the normal full-source compile/audit and obtain the final native critique before root's separate mouse publish.
