# Lowest-room ceiling beam clearance

Correction prepared against furniture Builder 104414, SHA `3797c080fa87b7629f8b408c3d2446ad95552be8b5baa024a8ac22e3ecd5ea3c`, then independently reviewed at 9/10 and applied after the root agent authorized it. The applied Builder is 104744 bytes, SHA `f1256558007826450fe5c86cc2a0f160d2274270ae345380135d4585bcb6f6b3`; see `applied.json`.

Root natively confirmed the S1_R04 south beam at `[6604.5,34.25,-73.04]`, size`[43.52,1.5,1.1]`, overlaps the actual Manager body by.1stud: underside33.5 versus body top33.6. The generated room is11studs tall.

The scoped `makeRoomStructure` change keeps each beam's top attached at the exact same ceiling height and preserves X/Z position, width/depth, material/collision, all four columns and room generation/count. Thickness becomes `min(1.5, roomHeight−MallManager.AgentHeight−.1)`. Default H11 uses.9stud instead of1.5, giving nominal10stud agent height+.1 and actual body top9.6+.5stud. H12/H13 keep the exact original beam geometry. A custom unsupported height≤10.1 fails clearly rather than emitting zero/negative thickness. Existing current generator settings use H11–13.

`test_beam_clearance.py` executes actual before/proposed `makeRoomStructure` and the actual current Manager `clearanceBox` in a controlled geometry host. **61,053 checks pass over2,907 default rooms** (three structural styles, three heights and all323 integer W60–78/D52–68 sizes). It verifies exact columns, beam count/top/plan geometry, collision, unchanged higher rooms, .5stud minimum actual-body gap, the exact native before-overlap/after-clear case, preserved skipped styles/module rooms and explicit invalid-height refusal. The whole proposed Builder compiles. These checks cover emitted beam geometry, not native PFS/visual rendering.

After independent review and root's scoped push into a fresh world, recheck the exact S1_R04 south body box/beam overlap and the beam's ceiling attachment. Root owns native navigation, rendering and publication. The unrelated S2_R05 corner/PFS stop remains a separate diagnosis; this patch does not move columns or claim that every room perimeter is clear.

Root subsequently confirmed a fresh normal world was READY at 100 HP and the exact S1_R04 south segment `[6604.5,24,-70]` to `[6604.5,24,-59.5]` passed the actual full-body clearance query. Root retains the native evidence and handles the visual ceiling-attachment check and publication; no overall navigation or publication completion is inferred here.
