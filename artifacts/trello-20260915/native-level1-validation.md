# Level 1 native validation — 21:16 UTC

Fresh Play, actual Create Party click, ordinary elevator/loading flow reached
RoundLoadingState=ready and RoundActive=true. No harness ran in this session.

- From round start: FUSES CARRIED 0 / FIND A FUSE, visible before pickup.
- Actual 1.8-second FuseRelay interaction: carry1 / FILL A FUSE BOX.
- Actual .35-second box interaction: server events carry0, boxes1/1,
  team(mikkelczar,box,POWERED A BOX 1/1), levers1/10, lever0/1.
  Next step changed to FOLLOW THE CURRENT TO A LEVER.
- CircuitCable_01 Powered=true. Two visible moving pulses; sample .5 seconds
  apart advanced one x134.61→147.56 and the other to the lever riser.
  ReduceFlashing produced one pulse; restoring false restored normal mode.
- Actual lever interaction: lever1/1 and exactly one team PULLED LEVER 1/1.
  Re-trigger produced no duplicate team line. Exit event changed next step to
  REACH THE LIT EXIT DOOR.
- Desktop text bounds fit the objective rows. At synthetic568x320, completed
  box/lever rows competed with the compass and left it 56px wide. Root removed
  those completed rows from the exit phase; final native fit check pending.

This is one real client. Party fan-out, lobby exclusion and spectator eligibility
are covered by source-executing tests, not claimed as three native clients.
Health/entity pause/camera/viewport changes are Play-only and cleared by stopping.

## Final tiny-landscape retest — 21:44 UTC

Repeated the real fuse → box → lever flow in a fresh Play session after the
responsive exit change. At568×320 touch, exit compass is310×96 at(235,8), inside
the movement-safe ModalArea(235.2,8)-(556,104), allowing the intended1px floor
rounding. Completed objective column hidden only in this small landscape exit
state. Header232×15 fits254×25; readout162×34 fits216×41. Native PASS.
