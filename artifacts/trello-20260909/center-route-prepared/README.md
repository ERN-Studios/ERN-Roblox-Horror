# One inner rectangle after an obstructed outer route

Prepared against reviewed Manager173454 SHA`74898bacbc988579a074f9f0a382a8eb94fdf7e09656f59c07c3a56d1feed83e`; runtime Manager remains unchanged during preparation. The reviewed beam Builder104744 is applied separately.

The first room-perimeter repair natively passed the old SignalHall→west failure and continued for about18seconds. New instrumentation identifies a later south→east turn in BirthdayCenter/S2_R05. The outer southeast corner intersects an existing structural column. The current→room-centre segment is clear, but the centre→east-port segment hits the preserved southeast table's navigation region. A naive two-leg centre route is therefore rejected.

Root natively measured all four full-volume legs of an alternative inside the room: current `[6304.5254,24,396.1458]` → `[6304.5,24,358]` → `[6331.5,24,358]` → `[6331.5,24,369.5]` → `[6373.5,24,369.5]`. These are diagnostic coordinates only, never runtime constants.

The small proposal adds one optional variant to the existing local rectangle helper. Only if **every outer candidate failed**, halve the transverse extent for the same adjacent link: Z for east/west, X for north/south. Keep the longitudinal extent, existing doorway/next-room inner point, full volume checks, candidate enumeration, waypoint follower, progress and async replacement guard. Same-room targets do not use this extra variant. There is no centre teleport, extra global search or changed structural/furniture collision.

`test_center_route.py` passes **833 combined actual-source checks**: the existing436 geometry/async tests, the captured S2_R05 room with all16 actual emitted columns added to the wall/furniture fixture, its exact obstruction, the actual installed follower travelling93.850stud into the adjacent room, a sealed-door refusal, unchanged previous SignalHall waypoints, and a90-degree rotation of the complete emitted geometry exercising the other axis with identical follower distance. Native geometry confirms the selected legs; native continuous follower/plateau/rate/concurrency acceptance remains root's next step.

The existing fixed adjacent-room candidate limit remains eight paths/six segments per rectangle, at most96 candidate sweeps only when both rectangles are needed. Once installed, normal following does not enumerate them each frame. PFS replacements still require a fully clear route while an authored repair is active; this delta does not alter that guard or the original strategic room advancement.

## Reviewed source applied

Independent critic: **9/10** for exact SHA `e1332968cf1cd4e5e216381d5d6b5ed5492734213845c66151f6c33c455b2884`; critic independently reran all 833 combined actual-source checks and whole-script compilation. The existing 70 projection/progress and 222 steering checks also pass; the pre-change implementation fails the new inner-route assertion as expected.

The exact reviewed Manager is now applied to the workspace after verifying the original SHA. Studio sync, actual sustained pursuit and publication remain with the root agent. Root independently measured all four segments of the new inner candidate in a fresh normal world; those segments and endpoints were physically clear. This establishes candidate geometry, not live follower acceptance.
