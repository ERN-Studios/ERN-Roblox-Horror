# L3 compact-room furniture placement

Prepared against the byte-exact Builder in `baseline/`; the proposed Builder is in `proposed/`. Only the World Builder changes. The existing Manager waypoint fix and stricter progress validator remain separate, already-reviewed changes.

The independent critic gave the proposal **9/10** and reproduced the checks, including additional old room sizes and rejected impossible/crowded configurations. The reviewed Builder was then applied after exact baseline-SHA verification; `applied.json` records its SHA256 and compile/readback result. Root's fresh native QA is still pending. The test runner accepts either the recorded baseline or the exact reviewed proposal in runtime, and rejects other drift.

The native seed 143259491 demonstrated that the original smaller SignalHall had a continuous furniture barrier between its north and west doors. Independent analysis also found blocked ports in SparseWelcome, KidsCluster and BanquetRows. This fit therefore applies to the existing table archetypes through their shared placement loop.

Each complete table/chair group keeps its size, yaw and chair count. Its hide anchor and first-table CD socket follow the same frame. Minimum axis clamping reserves one stud of continuous Manager-centre space between the physical wall/body boundary and the **full existing** inflated navigation regions. Overlapping physical groups after clamping use a bounded opposite-corner/triangle arrangement. No collision or navigation radius is reduced. All 126×96 legacy placements remain unchanged.

## Offline evidence

Run `test_room_furniture.py` with the installed Python 3.11. It executes the actual proposed `makeTable`, fitter and table-placement portion of `makeRoomProps` in the official Luau runtime. Roblox emission infrastructure is stubbed; emitted table/chair parts and rotated navigation regions are measured independently.

- 118,782 checks passed across 4,538 layouts: all 14 archetypes at every integer W60–78/D52–68, every archetype at 126×96, and two repeated native SignalHall dimensions.
- Minimum actual emitted physical-group AABB separation: 0.828475978 stud.
- Minimum lane against **full** existing rotated navigation regions: 1.0 stud. Continuous segment tests cover all four perimeter edges and four centre-door spokes.
- Yaw, table/chair count, hide/CD local offsets, legacy layout and deterministic repeat checks pass.
- Entire proposed Builder compiles. Validation was run while the production Builder remained byte-identical to the recorded baseline.

This is geometry evidence, not a native rendering or path-following certification. Future custom room sizes smaller than the verified configuration can fail the explicit fit assertions rather than silently generate overlapping furniture.

Later native clarification: `level3-furniture-native-ring-port.json` finds18 blocked segments among155 actual ring/port probes, caused by existing structural columns and the SignalHall AV cart, with no table furniture-nav blocker. The fitted table groups reserve their lane; this does not guarantee a free ring around every other authored object. The concrete SignalHall north→west sequence passes. Any local Manager repair must still sweep each actual segment and refuse blocked alternatives. This evidence authorizes no additional furniture or structure changes by itself.

## Native acceptance before publication

1. Stop any prior round, push only the scoped reviewed source changes, and require/build a fresh world. An existing generated room retains its old furniture until rebuilt.
2. Reproduce seed 143259491 (hash L3-2-0fbba959) through the existing supported build/normal round path. Confirm ready=true and a normal 100 HP player. Keep original Manager sweep, navigation exclusion sizes and collision settings.
3. Re-run actual `volumeFits`/`volumeClear` on SignalHall's north-to-west room passage, including the perimeter near X6574.1/Z632.1→654. Native geometry should now connect the valid north start and west goal. The previous one-stud reachability lattice is useful supporting evidence; it does not by itself certify runtime movement.
4. Probe the other previously flagged ports: SparseWelcome L3_S1_R01 west; KidsCluster L3_S1_R02 east/west; BanquetRows L3_S2_R04 west and L3_S3_R01 south. Inspect physical table/chair separation and the moved hiding/CD anchors.
5. Run the normal Manager chase across the blocked room and at least two district gateways/90-degree turns. Require actual passage into the next rooms and sustained real progress; a changed path ID or one early serial increment is insufficient. Use the stricter plateau validator already in the Suite. If Roblox PFS still supplies physically invalid points, preserve the fail-closed volume checks and investigate the remaining route; do not certify this solely from the geometric lane.
6. Complete the pending normal five-CD/finale walk-in/cleanup acceptance and visual room inspection. Remove Play-only diagnostics; restore temporary mesh/image API setting before mouse publication. Root owns Studio and publication.

Independent critic review and native outcome are recorded separately; this preparation does not mark the Trello feature Done.
