# B7 / B8 visual QA recipes

Read-only source audit, 2026-10-09. This file does not create or execute any Studio actions. Root owns Studio. Use an isolated local playtest; stop that playtest after staging to clear private client timers, camera, and borrowed state. These recipes never call a server win/lose/save handler.

## Existing seams and limits

- `PlayerGui.RoundHud.UIRegressionRoundHudProbe` is the real player's cached shared HUD bindable: `capture`, `restore`, `setobjective`, `feed`, `caption`, `snapshot`, `expandobjective`.
- RoundUI has Studio-only player **attribute** seams `DevDeathCause`, `DevPartyDown`, `DevRoundEnding`, and `UIRegressionCompletionPress`. They are not bindables.
- Current L4 note/keypad, SpectateController, and RoundUI loading presentation have **no Studio-only bindable**. Do not invent an Invoke operation on their GUI.
- `UIRegressionCompletionPress` invokes production `completion.activate`, which sends `RoundStatus:FireServer(action, serial)` even when the test serial is `-1`. Do not use it or click result travel actions for visual staging.
- Do not use `DevCheatCommand/freeRespawn`, `KeypadSubmit`, production `win`/`lose` FireServer requests, Humanoid death, or a successful `entryprepare` handshake for these screenshots.

The optional downlink recipes below send only specific existing RemoteEvent **server-to-client** presentation messages to one local test player. They are explicitly separate from the Studio-only local seams.

## B7: actual L4 note and keypad

Prerequisite: the existing local test participant is in an actual Level 4 session: Workspace `Level4RoundActive=true`, `SelectedLevel=4`, `RoundActive=true`; player `InRound=true`, `Escaped` not true. The client must have subscribed to `ReplicatedStorage["Level 4 Remotes"].ClientEvent`. `roundLive()` rejects other sessions; changing only GUI.Visible is not evidence that the receiver works.

Server-context downlinks to that test player `p`:

```lua
local e = game.ReplicatedStorage["Level 4 Remotes"].ClientEvent
e:FireClient(p, {Type="Note", Text="POWER\n1 > 3 > 2 > 4\n\nin this order"})
-- After recording / closing the note:
e:FireClient(p, {Type="Keypad"})
-- Record this state promptly: wrong-code notice clears after 0.8 seconds.
e:FireClient(p, {Type="KeypadResult", Ok=false})
```

These three receiver branches update local presentation only. `Note` opens with the existing 12-stud pickup leash; keypad opens with the existing 10-stud leash. Keep the test avatar still. Opening either card closes the other.

Exact mounted paths (L4 ScreenGui DisplayOrder 60):

- `PlayerGui.Level4RoundGui.NoteCard`
- `NoteCard.Body.Items.BodyLine1..4`: PatrickHand; line 2 changes `>` to `?`; line 4 is `in this order`.
- `NoteCard.CloseHint.KeyChip` on desktop/gamepad; `NoteCard.TapToClose` on touch.
- `PlayerGui.Level4RoundGui.Keypad.DisplayBox.Display`: initial `----`, then entered digits plus dashes.
- `Keypad.Status`: `WRONG CODE`, visible for 0.8 seconds.
- `Keypad.Key1..Key9`, `Keypad.KeyC`, `Keypad.Key0`, `Keypad.KeyOK`, each authored `.Label`.
- `Keypad.Close`; touch adds sibling `Keypad.CloseHit` with 44x44 target.
- `Keypad.PressHint.KeyChip` (A), `Keypad.CloseHint.KeyChip` (Esc/B).

Safe input checks: enter `1`, `2`, then `C` (or Backspace); close via Close/CloseHit, Esc, or B. **Do not press OK/Return after four digits**: that sends KeypadSubmit to the server. The 3-column, 4-row gamepad ring has wrap-around directional neighbors, initial focus Key1, and B restores the previous selection.

Note close: clicking/tapping the whole NoteCard, E, or B. Reopen: N/DPadUp or the shared ObjectiveCard Order activation; this additionally requires an alive own-player objective subject and a string player attribute `Level4_NoteOrder`. Mere receipt of the synthetic Note event does not give that attribute, so an existing picked-up note is required to verify reread semantics. Reread has no world pickup leash. Shared Order callback is published for the Dark phase when order is known.

On touch, `Level4CardOpen` is derived from enabled visible note/keypad and suppresses the movement cluster. Verify it clears after closing. Device changes recreate the cards, so reacquire GUI paths.

## B8: death card

Client-context local seam:

```lua
local p = game.Players.LocalPlayer
p:SetAttribute("DevDeathCause", nil)
p:SetAttribute("DevDeathCause", "L4Usher") -- or L1Entity, L1Pit, L2Hole, L3Manager, Unknown
```

No health write or server death occurs. Death copy comes from actual `DeathAdvice.Copy`. Ordinary dwell is 12 seconds; click close, Esc (including Roblox MenuOpened), or B permanently closes this staged life and cancels its timer. Unknown has no tip. Re-set nil then key to stage the same cause again.

Exact mounted paths under `PlayerGui.RoundGui`:

- `DeathCause.Head.DeathCauseTitle`
- `DeathCause.Cause.DeathCauseBody`
- `DeathCause.Advice.DeathCauseTip`, `DeathCause.Advice` hidden for unknown/no tip
- `DeathCause.Head.Close`, `DeathCause.Head.CloseHint.KeyChip`
- `DeathCauseDocked.DeathCauseTitle`, `DeathCauseDocked.Close`

To verify docking using the existing Studio seam, set `DevPartyDown=20` after staging the death card. Production publishes `PartyDownCardOpen` and displays DeathCauseDocked while the party-down modal is open; its death expiry waits while that modal owns the screen. Cleanup `DevPartyDown=nil`, `DevDeathCause=nil`. No Respawn button activation.

## B8: results / escaped presentation

Set `DevRoundEnding=nil` before each chosen mode so the change signal fires:

```lua
p:SetAttribute("DevRoundEnding", nil)
p:SetAttribute("DevRoundEnding", "win") -- other modes: winfinal, lose, escape
```

- `win`: `LEVEL <SelectedLevel> CLEARED`, TIME 03:42, SURVIVORS 2/3; local 15-second countdown, two travel buttons; test server serial -1.
- `winfinal`: TIME 05:08, SURVIVORS 2/3; local 15-second countdown; only Back to Lobby.
- `lose`: TIME 04:17, SURVIVORS 0/3; objective counter captured from actual shared `LastObjective()` **before** shared Clear.
- `escape`: `YOU GOT OUT`; stats hidden; 2.75-second WATCHING <target/THE OTHERS> countdown and fade. Dev seam does not mark Escaped and does not itself activate actual SpectateController camera.
- Cleanup: `DevRoundEnding="hide"`, then nil. Capture/restore actual shared HUD via its bindable if keeping the playtest.

Mounted root is `PlayerGui.RoundGui.RoundEnding.ResultsWindow`; touch/short/narrow devices use imported ResultsTouch, still with runtime name ResultsWindow. Exact paths:

- `Head.EndingTitle`, `Head.EndingHint`
- `Head.EndingStats.Items.Stat_Time.Num`
- `Head.EndingStats.Items.Stat_Survivors.Num`
- `Head.EndingStats.Items.Stat_Counter.Label` and `.Num` (loss only when snapshot contains Counter)
- `Footer.Countdown`, `Footer.CountNum`
- `Footer.ContinueRun.Label`, `Footer.ReturnToLobby.Label`
- `PartyChoices.PartyChoice1..6`, each `.Who`, `.Sub`, `.Chip.Label`

Optional six-player roster screenshot, safe server-to-client downlink only, while the local player is already InRound:

```lua
local members = {}
for i=1,6 do members[i]={Name="QA PLAYER "..i, UserId=-100-i} end
game.ReplicatedStorage.Remotes.RoundStatus:FireClient(p, "resultroster", {Members=members})
```

For Continue/LOBBY chips after `DevRoundEnding="win"`, downlink `"postwinchoices"` with `{Serial=-1, Revision=1, Members={{Name="QA PLAYER 1",UserId=-101,Choice="continuing"},{Name="QA PLAYER 2",UserId=-102,Choice="returning"}}}`. This only calls local applyChoices. Do not activate travel buttons. On touch the footer actions remain 52px high; party list scrolls when six rows do not fit.

## B8: loading presentation

There is no current local bindable/DevLoading seam. In an isolated playtest, a safe **downlink-only** presentation recipe is:

```lua
local status = game.ReplicatedStorage.Remotes.RoundStatus
status:FireClient(p, "loadinggame", 4) -- announced level a; try 1..6 separately
-- Do not send entryprepare: Round Entry Client owns token/character readiness acks.
-- To release only this staged cover, no prepare token was assigned:
status:FireClient(p, "entryreleased", {}) -- a.Token=nil matches staged entryState.Token=nil
```

`loadinggame` clears local result/briefing state, arms local entry presentation with Token=nil, sets LoadingLevel, and restarts the existing ~7.35-second loading stages. Round Entry Client cancels any previous request on this event; no new readiness request or ack is created without entryprepare. The downlink entryreleased terminates only the staged local UI path. Do not run this during a real pending entry barrier: it would cancel that client's readiness request. Stop the isolated playtest for reliable cleanup.

Exact paths: `PlayerGui.RoundGui.LevelLoading.LoadingCard.Title`, `.Eyebrow`, `.Steps.Step1..3.Line`, `.Tip.TipText`, `.Status.StatusLine`, `.Status.Track.Fill`, `.LevelTrack.Slot1..6`. Imported LoadingCardTouch is selected when touch, safe height<620, or width<800; runtime name remains LoadingCard. Cover is pure opaque black at ZIndex100. Levels 2/5 show fixed mystery title UNRECORDED / ??? WHERE?; their eyebrow/steps/tip/divider are hidden. Level track labels 2/5 are `?`.

## B8: spectate constraint

Actual `PlayerGui.SpectateGui.SpectateBand` paths: `.Watching`, `.Who`, `.Initial.Letter`, `.SpectatePrevious`, `.SpectateNext`; sibling `SpectateBackToLobby.Label`. Q/E or DPadLeft/Right cycle living targets. BackToLobby opens `PlayerScripts.RoundExitPrompt`, not direct travel.

There is no visual-only SpectateController bindable. Setting Spectating=true alone does not start its private camera state. Actual start occurs on Humanoid.Died or escaped lifecycle. It also reports target changes via RoundStatus FireServer("spectatetarget", userId), so do not advertise it as zero server traffic. Use an already spectating participant to audit actual POV/target changes; the DevRoundEnding escape mode covers only the results-to-watch presentation.

## Source evidence

- Round HUD 287-303: actual player cached bindable operations.
- L4 client 43-54, 547-638, 667-770, 961-1014, 1048-1105: gates, paths, event payloads, inputs, leashes.
- RoundUI 1203-1324, 1370-1601, 1686-1702, 1813-1907, 1934-1985, 3984-4040, 4513-4627: imported mounting and local seams.
- SpectateController 19-26, 34-90, 240-359: paths, lifecycle, camera and target reporting.
- Round Entry Client 140-149: downlink loading cancel; entryprepare is the only readiness begin.
- Actual imported fixture: tools/tests/fixtures/hud/framewisp-dump.HUD_Screens.json.
