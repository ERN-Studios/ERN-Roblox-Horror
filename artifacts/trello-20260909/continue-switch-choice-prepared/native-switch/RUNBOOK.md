# Normal two-client switch validation

This is a handoff only. No native action, source installation or new acceptance is claimed here. Reuse the existing reviewed observers; do not copy their old output files over new evidence.

## Arm the three existing observers after the normal queue is ready

Run the complete existing `party-autocontinue-choices-prepared/native-session-1300/observer.lua` in **each real Play Client**, and the complete `server-observer.lua` in the **Play Server**. They infer their real identities. Confirm `Armed` for client −1, client −2 and server 0, with three distinct run IDs. If this session has different real IDs, use those observed IDs in collection instead. These ordinary-context snippets have no fresh module requires or gameplay actions.

| File | SHA256 | Lifetime |
|---|---|---|
| `observer.lua` | `9993c3f7cb0a4b86f3ead09490664f9cd866182a9575c1b0f0c3666e613725cb` | 240 s |
| `server-observer.lua` | `bc2731b5ab42428fa6952134fdbc049c0f0f2f584912909e7c0bff88a8920e85` | 240 s |

The clients already capture `win` serial/deadline/next level, every `postwinchoices` packet (including the new `Closed` field), real `Activated` notifications, accepted visible `PartyChoice%d+` text, button Active/Visible, loading events and each client's `RoundEntryControlsReady`/`RoundEntryReadyToken`. Those local readiness fields may be absent on the server and peer; inspect each owning client. The server records actual two-player identities, Health/root anchoring, level/loading and post-win state. All output lines use the existing `[CONTINUE1300|...]` marker and remain below 750 bytes.

Start the result only after both actual clients have observed `start`, the current loading token has reached ready, both actual characters are alive/InRound/unanchored, and no previous post-win window is active. Root may use its already accepted **controlled PuzzleWon fixture**; that completes the objective through the real GameManager path, and is not a full quest playthrough. The shared win loop checks PuzzleWon before the other outcome tests after `start`; setting it during loading may be erased by the ordinary reset. No new win helper is needed. Do not set Escaped or manufacture players/remote packets.

## Fast genuine clicks inside the original window

The exact existing button paths are:

```
LocalPlayer.PlayerGui.RoundGui.RoundEnding.ContinueRun
LocalPlayer.PlayerGui.RoundGui.RoundEnding.ReturnToLobby
```

The currently installed Studio MCP metadata exposes `user_mouse_input` with ordered mouse actions, per-action `instance_path` and waits. `client-a-three-clicks.json` contains the exact action sequence. Root must substitute a **currently observed, reachable actual client Studio ID**; this recipe has not itself been executed. Do not assume an embedded Play Client is one of the two separate test clients.

If the actual child client is addressable, dispatch one `user_mouse_input` call after its real win UI is visible: Continue → wait 750 ms → Return → wait 750 ms → Continue. The .75-second spacing exceeds the real .15-second client and server throttle. The tool emits mouse actions into the GUI; it does not call the handlers or send the remote directly. Its success response still is not proof of accepted choices: require the later authoritative packets on both clients.

If child clients are not available through MCP, use root's native computer mouse. Keep client A's window/viewport fixed; record the actual button centers from its visible result layout before reusing coordinates. The observer's `AbsolutePosition` values are Roblox GUI coordinates, **not automatically desktop screen coordinates**. Use the native screenshot/window origin to map them. Send the three actual clicks in a short native action batch if available, or short consecutive calls with no screenshots/model analysis between them; leave .75 seconds between clicks. Inspect the saved observation logs afterwards. Do not use `GuiButton.Activated` firing, internal callbacks, UIRegression preview clicks or direct FireServer as native input evidence.

## Two decisive windows

1. In the first actual two-player result, A clicks **Continue → Lobby → Continue**; B remains unanswered. Both clients must receive the same session serial and increasing accepted revisions showing A's three choices. A's two original buttons remain usable until closure. There must be no loading/level transition after the first or second click. At the **original win deadline**, `Closed=true` locks the window and final settlement should contain two continuers: A's final choice plus B's automatic default. Observe each client's real next-level ready/start and live controls, not only a level attribute.
2. In the next ready level, arm fresh observers first if the 240-second window is nearly exhausted. Open another labeled controlled result. A clicks **Continue → Lobby** and B clicks Continue. Verify A's last accepted choice on both clients, closure at the unchanged deadline and the real server settlement line `1 continuing ... 1 returning`. The existing Studio mixed-choice fallback sends the local session to lobby; this is **not** evidence of cross-server Teleport splitting. Confirm both lobby states/normal cleanup. A separate provisional-choice disconnect can verify the native departure row if root performs it; absence of that run must remain an explicit limit.

Use the packet's fixed `win.Args.d`/`Deadline`, `win.Args.f`/SessionSerial and `postwinchoices.Args.a.{Serial,Revision,Closed,Members}`. Client event timestamps use server time but include replication latency. The deadline minus the received win time will be slightly less than 15 seconds; **no new deadline may be sent or manufactured for a click**. The first closed packet/transition can arrive after the deadline. Server settlement console output comes from the unchanged real GameManager partition, not the observer.

The `ActualButtonActivated` event is input evidence. The corresponding member choice in the subsequent server packet is acceptance evidence. A captured action without a changed accepted packet may have been throttled, late or unavailable and must not be counted as a successful switch.

## Collect without replacing v1861 evidence

`collect_current.py` is a thin adapter around the existing reviewed collector. Supply the **three observed current log filenames**, not the historical names hardcoded in its original source. It preserves all original parsing/chunk/identity checks and writes only to this task's `log-export/` (or an explicitly chosen `--out` artifact directory).

```powershell
python artifacts/trello-20260909/continue-switch-choice-prepared/native-switch/collect_current.py --server-log '<actual-server.log>' --client-a-log '<actual-client-A.log>' --client-b-log '<actual-client-B.log>'
```

Pass `--client-a-id`/`--client-b-id` only if the Armed records show identities other than −1/−2. Require every advertised part exactly once, valid JSON/header identities and the appropriate Armed/Stopped records; zero collector issues alone does not certify gameplay. Preserve normal GameManager settlement lines separately, because this collector intentionally retains only observer markers.

Manual cleanup in the same original Lua context:

```lua
-- Each Client:
if _G.TrelloContinue1300_client then _G.TrelloContinue1300_client.Stop("manual") end
-- Server:
if _G.TrelloContinue1300_server then _G.TrelloContinue1300_server.Stop("manual") end
```

Manual stop reports observation-window completion=false, which does not invalidate already captured positive events. No client/source/attribute reset is needed because these observers do not change gameplay or UI state.
