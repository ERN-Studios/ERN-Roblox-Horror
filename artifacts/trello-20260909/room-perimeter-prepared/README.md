# L3 checked local room-perimeter repair

Prepared against frozen Manager **167812 bytes**, SHA256 `9be66ee61f415ca863ee595795470c2b7421b7990a6ad1ae6e1888c7f5672230`. The independent critic gave the final proposal **9/10** after independently rerunning436+70+222 checks and the full compile. Root then authorized applying only that reviewed Manager:173454 bytes, SHA256 `74898bacbc988579a074f9f0a382a8eb94fdf7e09656f59c07c3a56d1feed83e`; exact baseline/proposal SHA and readback are recorded in `applied.json`. No Studio operation was performed by this agent. The World Builder furniture correction must already be present in a freshly generated world (reviewed Builder104414).

## Native problem

`level3-furniture-native-door-failed.json` and `level3-furniture-native-door-compact.json` show the Manager stationary for17.1seconds near `[6604.20703125,24,630.4805908203125]` in seed143259491. The first authored strategic goal is the west room. The updated furniture geometry now passes the complete native north→west perimeter sweep, but Roblox PFS still supplies points inside the north wall's physical body clearance. Repeating PFS at larger radii already failed to change that route.

## Bounded repair

The new helper considers only the current room's rectangular perimeter. Its inset is wall half-thickness + the existing5.25 physical half-sweep +.5stud. Furniture fitting already reserves1stud between this body boundary and the full inflated nav regions, so this line has.5stud nominal space on either side; actual `volumeClear` must still pass every segment.

This reservation covers the fitted **table groups**, not every existing structural/decorative object. Root's subsequent `level3-furniture-native-ring-port.json` probes155 real segments (96ring+59port) and finds18 blocked segments, with no furniture-nav blocker: structural columns affect S1R04, S2R05, S2R06 and S3R04; SignalHall's east edge also meets the existing AV-cart television shelf. The reproduced SignalHall north→west route remains clear. These findings do not prove that ordinary PFS interior routes in those other rooms are blocked. The repair retains its actual sweep refusal and makes no universal free-ring claim; no additional Builder change is included.

Four projections connect the current position to the ring. For a same-room destination, four exit projections are considered. For an adjacent-room destination, only that actual existing link's cardinal door is considered, and the last point is the matching inner doorway point in the adjacent room. Both directions around the four corners are tried; the shortest fully clear candidate wins. Nonadjacent targets, offset/diagonal links, closed HiddenExit links, the straight finale, and any obstructed candidate are refused. There is no graph search beyond the already selected adjacent strategic room.

The repair reuses the existing `session.Path`, waypoint follower, path-swap serial and genuine-progress machinery. `PathIsRoomPerimeter` distinguishes these waypoints from a Roblox Path object. Installing the repair calls `clearPath`, invalidating the previous async token without moving the rig, crediting progress or resetting failure counts. PFS replacement clears the flag. Existing viable PFS routes are retained.

While a checked local path is active, a PFS refresh may replace it only after its **entire** accepted route and final destination approach pass the same full sweeps. A valid first coarse waypoint with invalid later wall-hug points retains the local path/index/swap serial. The shared `pathSegmentsClear` helper also replaces the equivalent existing complete-route certification loop.

Repair is attempted after a rejected active waypoint/final segment or when a coarse computation has no usable route. Ordinary direct-clear movement remains first. An authored corner cannot be consumed early unless the following segment is already physically clear, and cached authored targets are swept again before steering. Normal runtime movement still owns acceleration, full body sweeps, overlap recovery and transform changes.

## Verification

- `test_room_perimeter.py`: **436** checks pass, comprising407 geometry/follower checks and29 checks around actual asynchronous PFS refresh continuations. It runs the actual proposed helper and follower against the actual emitted current Builder wall segments and table/nav regions, with the captured native layout. Independent planar slab tests expand physical room/corridor walls by the unchanged5.25 square body and use rotated full furniture boxes without shrinking padding.
- The same native start traverses94.349stud continuously through the north/west corner and into L3_S3_R07. Every returned target and simulated step clears the fixture; no transform is changed by the navigation helper itself.
- Sealed doorway, nonadjacent target, finale, dynamic blockage, same-room furniture detour, preserved viable PFS path, token invalidation and no unearned failure reset are covered.
- The actual `requestPath` yields inside a coroutine-backed `ComputeAsync` stub: five successive valid-first/invalid-later completions retain the same path and progress; a fully clear replacement swaps normally; a late result after a newer local install is ignored. Removing the new refresh guard reproduces the exact failing assertion. Native PFS itself is not simulated by this test.
- Measured candidate calls to `volumeClear`:16 for the reproduced adjacent-room repair and90 for the same-room obstacle detour. Fixed worst-case candidate bounds are48 and192 respectively (eight or32 paths, at most six segments each). Following an installed path does not rebuild these candidates every frame.
- `test_existing_contracts.py`: prior70 projection/progress tests and222 steering tests pass against the proposal. The prior corridor-only fixture stubs the independent new room repair as refusing; its geometry deliberately omits other room walls. The407-check emitted-world harness runs the actual new repair.
- `prepare.py` compiles the entire proposed Manager with official Luau0.737 and requires the exact runtime baseline SHA before creating artifacts.

The fixture does not run Roblox PFS, native physics, vertical body/ceiling overlap or full acceleration/avoidance. Production `volumeClear` retains its actual body-overlap and furniture-aware sweep contracts; it does not add a floor-ray test. Native repetition, actual continuous progress and independent critic acceptance remain mandatory.

## Root native acceptance

After scoped source push and a fresh normal world/session, reproduce the exact seed and staged pursuit already captured. Require the Manager to enter R07 and continue through two real gateways/right-angle transitions, with no sustained motionless/progress plateau. Verify `ROOM_PERIMETER` occurs only for the constrained repair and that no stale PFS completion immediately restores rejected raw points. Check a blocked doorway still yields no illegal step and existing request/concurrency bounds hold. Reuse already-passed five-CD/finale run-in/cleanup evidence where this Manager-only delta has not changed that contract; complete only outstanding acceptance. Remove temporary diagnostics and obtain final feature score≥8 before mouse publication.
