# Round exit QA clarification

Root's fresh native run initially held L for 1,200 ms and then attempted to click `RoundExitGui.RoundExitShade.RoundExitCard.Confirm`. The inspected child button had `Visible=true`, but its ancestor shade was hidden. The click did not establish a return request.

## Expected behavior from current source

- `Round Exit Client` line 48 sets **HOLD_SECONDS=1.5**. The alive-player L hold accumulates `RenderStepped` deltas (388–401). It directly calls `sendLeave()` once the threshold is reached; it does not open the confirmation card.
- Releasing before 1.5 seconds resets the hold and sends nothing (418–423; releaseHold/stopHold).
- The separate confirm card opens through the `RoundExitPrompt` BindableEvent, primarily from the dead/escaped spectate UI (441). Its Confirm handler only sends when `shade.Visible` is true (443–446). A child's own Visible property is insufficient to establish that the UI is shown.
- `sendLeave()` fires `RoundStatus:FireServer("leaveround")` (361–385). If no server answer arrives, it permits a retry after eight seconds. A valid request receives `leaveack`; an unavailable Studio local lobby receives `leavefailed`.
- GameManager's handler checks the current participant/round state (2789–2798). Studio returns the player to the local lobby; published reserved servers dispatch a lobby teleport (2810–2815). `returnPlayersToLocalLobby` clears InRound, fires the lobby UI event and repositions/reloads the character (1638–1651).
- Level 5 deliberately retains its lobby/spawn in Workspace during Studio play (`Level 5 Round Adapter` 121–126), satisfying the local-return floor check.

## Resolved result

Root repeated the native input with **L held for 2,500 ms** and observed **InRound=false and RoundActive=false**. No Round Exit defect was established; no source changes are needed.

This reviewer inspected source only. The fresh native result above was reported by the root task. The correct QA action is to hold L for at least 1.5 seconds while the chip is available, allowing margin for input timing, then inspect player/round state. Check visible ancestors before using a confirmation button.
