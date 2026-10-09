# B8 offline implementation and QA — 2026-10-09

Product ownership for this delivery was limited to `RoundUI.LocalScript.lua` and `SpectateController.LocalScript.lua`. The coordinator owns Studio, live baseline/CAS reconciliation, shared modules, GameManager roster publication and UIRegression. No Studio session, lock, git operation, upload or publish was performed by this worker.

## Delivered

| Area | Production source | Behavior |
|---|---|---|
| Loading | `RoundUI:1222` | Actual `LoadingCard` / `LoadingCardTouch`, opaque pure-black cover, all six accents, Sage status, staged progress, `1 · ? · 3 · 4 · ? · 6` track. Level 2 / 5 reveal only their fixed mystery title or optional pool draw, status/progress and track. The synchronizing stage cannot overwrite the title. Levels 1 / 3 / 4 use actual DeathAdvice tips. Level 6 keeps THE PLAYGROUND, confirmed by coordinator after reading real Playground scripts. Existing tokenized server entry barrier, release and error/watchdog logic remain. |
| Results | `RoundUI:1370` | Actual Results Head/stat tiles/Footer and imported PartyChoice rows. Server `resultroster` is the only base roster; postwinchoices revisions/serial update choices. DisplayName resolves by UserId. The roster alone scrolls when six rows exceed the safe height; actions remain 52 px on touch. Loss takes LastObjective.Counter before Clear. Own escape reads YOU GOT OUT / WAITING FOR THE OTHERS. ReduceFlashing suppresses SignalFlash. Pressed labels survive device remount; pending/terminal/deadline disarm and failure re-arm keep real serial/deadline transport. |
| PARTY DOWN | `RoundUI:4218` | Actual PartyDownCard / Touch, NO SIGNAL, navy screen at .1 transparency, PC-only corner brackets, DisplayName FELL or no fallen line, drain bar and 00:15 clock. Nested Offer/Items keeps only visible controls. Owned / buy / waiting captions, purchase latch and cancellation recovery. Existing ZyntraAction UseReentry, Marketplace product ID and developer bindable path remain. Primary pad focus after the .6 s death-mash arm delay; B declines. CardOpen and WindowOpen remain distinct after decline. |
| Death | `RoundUI:4513` | Actual standalone Stack and separate docked 44 px strip. WHAT HAPPENED, real advice, no Advice gap for Unknown. Closing X, B or Escape/MenuOpened cancels that life’s timers and both presentations; no re-dock after close. Next death reopens. B passes under PARTY DOWN, text input and Roblox menu. Respawn/re-entry/round end close. Existing 12 s auto-close waits through PARTY DOWN. |
| Spectate | `SpectateController:34` | Actual SpectateBand / Touch and BackToLobby. WATCHING plus DisplayName, initial and Q/E or D-pad keycaps; empty and escaped wording. Transparent Frames and contextual Ink strokes on text; 6 s / 45% attention. Touch cycle targets remain 44 px. Counter surface removed; target-report remote and SpectateTargetUserId remain. Camera/body hiding/borrowed flashlight/escape-flume ownership are unchanged. |
| B4 retirement | `RoundUI` | Removed MISSION BRIEF button/panel, objective help input and open/readback attribute, objective rows and old indefinite UI waits. Unbinds previous ToggleObjectiveHelp revision. Dormant subtitle GUI/audio/cue data remain as requested. |
| B5 callers | `RoundUI:132`, `:190`, `:4109` | In-round access / teammate escape use Hud.Feed with source eligibility. Dispatch text uses Hud.Caption as its only renderer; old CommandSubtitles stays hidden. Stop/mute transport callbacks and bindings remain. Clock pauses under the source’s modal gates and resumes; disabled caption preferences do not stall transport. Delivery cache records successful Caption calls only, and caption preference changes refresh it. |

## Integration contracts

- `RoundHud.Stack(bundle,path,parent,opts)` must provide direct parts, dynamic visible/Size/Parent/LayoutOrder flow and HudStackHeight. This delivery re-parents actual PartyChoice parts into its bounded ScrollingFrame. Shared-module fixture tests and B8 tests exercise that flow.
- `RoundHud.LastObjective()` returns stable Counter={Label,Current,Max} through Clear. Results captures it before its own Clear.
- `RoundHud.Feed({Kind,Actor?,Detail,Key?})`; RoundUI owns teammate escape rows, so Round HUD does not duplicate them.
- `RoundHud.Caption("COMMAND CENTER",text[,seconds])`; duration 0 clears the current cue. Shared owner added eligible COMMAND CENTER lobby delivery using DispatchTextActive. RoundUI never invents a lobby transmission.
- Server sends `RoundStatus("resultroster",{Members={{UserId,Name},...}})` to actual participants. This delivery excludes bystanders and never synthesizes a roster from GetPlayers.
- UIRegression reads imported nested labels. Continue/Return are below ResultsWindow/Footer; their caption is Label. Provisional pressed labels now read CONTINUING... / RETURNING... while server choices remain editable. Final countdown reads RETURNING TO LOBBY IN plus CountNum, so IN alone does not mean routing to another level.

## Verified offline

Official Luau 0.737 interpreter and compiler were used. The entire RoundUI was compiled after each logical product edit, including the final changes; SpectateController also compiles. No new top-level RoundUI locals were introduced.

| Check | Result |
|---|---|
| `test_hud_b8.py` | 703 checks PASS with real RoundHud, ShopBinder, DeathAdvice and the actual PC/Touch/Screens fixtures. Includes all loading levels and mystery privacy, lifecycle/close serials, offer/cursor/input states, purchase latch, truthful loss snapshot, six-person 844x390 roster within 293 safe height, 44+ touch targets, nested labels, pressed remount, terminal revisions/deadlines, spectate target replication, modal gates and caption clocks/retries. |
| `test_round_loading_notice.py` | 96 loading-error/race/generation checks PASS, plus actual B8 fixture. |
| `test_death_advice.py` | 129 server/copy checks PASS, eight Mark call sites checked, plus actual B8 fixture and whole RoundUI compile. Coordinator shortened L5Fall tip to comply with its existing copy limit; this worker did not edit DeathAdvice. |
| `test_dev_free_respawn_offer.py` | Existing modal entitlement/transport checks 17 developer + 3 ordinary PASS, plus actual B8 offer fixture. |
| `test_controller_input.py` | 91 controller checks PASS; B2 touch 86 and B3 stamina 74 also PASS. Only stale MISSION extraction/expectations were retired; real stop/mute and spectate hardware gates remain tested. |
| `test_round_loading_host.py` | 98 server loading-host checks PASS. |
| `test_spectate_parity.py` | 18 audio parity checks PASS. B8 test additionally compares camera/body/beam, target-report and escape-flume functions byte-for-byte with the takeover before snapshot. |

Existing hand-drawn death/offer/cover fake expectations were replaced by the actual fixture test, retaining their server, modal and loading race coverage. No copy limit or behavior assertion was relaxed to hide a failure.

## Remaining coordinator gate

This is offline completion, not proof of a live install. CAS push must include the coordinator’s shared APIs and server roster event. Studio must verify rendering/font metrics and hit testing on PC/phone/pad, portrait and 844x390 landscape, bright Level 2 / neon Level 4 spectate legibility, real Roblox Escape/MenuOpened delivery, kill-cam layering, purchase prompt/receipt recovery, achievements-toast/button overlap and lifecycle after re-entry. The fake engine does not model real fonts, CanvasGroup rendering, AutomaticSize/list padding, Roblox camera replication or platform prompt/menu delivery.

## Changed paths in this worker’s implementation

- `StarterPlayer/StarterPlayerScripts/RoundUI.LocalScript.lua`
- `StarterPlayer/StarterPlayerScripts/SpectateController.LocalScript.lua`
- `tools/tests/test_hud_b8.py` (new)
- `tools/tests/test_death_advice.py`
- `tools/tests/test_round_loading_notice.py`
- `tools/tests/test_controller_input.py`
- `tools/tests/test_dev_free_respawn_offer.py`
- This report. Earlier read-only map remains `B5-B8-IMPLEMENTATION-MAP.md`.
