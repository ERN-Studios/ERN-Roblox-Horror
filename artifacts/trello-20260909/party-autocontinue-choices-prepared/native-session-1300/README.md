# Real Continue session observers

Prepared read-only Command Bar snippets. No native execution is claimed by the preparation. Both whole files compile. There are no fresh module requires, outbound remotes, source changes, attributes written, purchases or gameplay actions.

1. In each actual Play **Client**, run all of `observer.lua` once. It infers that client's real UserId. In the Play **Server**, run `server-observer.lua` once. Both require this exact experience/place. Start before the real win event.
2. Confirm an `Armed` record for each of the three runs, then perform root's normal test. `DURATION` defaults to240 seconds and must be greater than0 and at most240. It can be shortened at the top of a snippet. Each observer returns immediately and stops automatically at its deadline.
3. Save Creator Output/log lines beginning `[CONTINUE1300|`. Group by side, UserId, Run and Sequence; join payloads by chunk index, **without line separators**. Require all advertised chunks once, then parse the combined JSON. Each UTF-8-valid print line is at most750 bytes, including its header; payload chunks are at most600 bytes. The Roblox log's own timestamp/prefix is outside that payload limit.

The client records actual `RoundStatus` events, including `win` with deadline `d`, next level `e` and actual server session serial `f`; `postwinchoices`, entry/loading/start and `lobby` are retained. It also observes real `Activated` signals on existing Continue/Return buttons, UI texts/visibility/sizes, the current selected GUI object and both players' observable state. Button activation is input evidence, while the later `postwinchoices` packet is the accepted server choice. A mouse-specific claim still requires root's actual mouse action; the Activated signal alone does not identify the input device.

Both observers record workspace attribute changes immediately and changed snapshots at a0.5-second polling cadence. Position-only changes do not generate extra logs; positions accompany state snapshots. Health, character replacement, InRound/Escaped, root anchoring, level/loading and post-win state are observable. Compare the win's actual server deadline with subsequent events/ready snapshots to assess the15-second behavior. Event receipt times on a client include replication latency, and0.5-second samples do not establish exact server callback timing.

The server does not claim access to private `activePostWin.Serial`; that field is omitted there. The client's real win serial and the shared server-time/level transitions allow correlation. `RoundEntryUIReady` means RoundUI initialized; actual `RoundEntryControlsReady` means NoiseReporter's gameplay-input/lifecycle handlers are wired. Both are captured, together with `RoundEntryReadyToken` from the actual Round Entry Client readiness loop. These are client-local and may be absent on the server or peer. Compare each client's token with workspace `RoundLoadingToken`, its own entryreleased event, hidden loading cover and live unanchored character. The flags alone are not proof of every readiness prerequisite or enabled movement in the next round.

Snapshot serialization retains nested choice-row names/text through depth10 (bounded64 entries per table). The actual installed GUI uses `RoundGui.RoundEnding.{EndingTitle,EndingStats,EndingHint,ContinueRun,ReturnToLobby,PartyChoices}`, with `PartyChoice%d+` TextLabels under PartyChoices. These names are checked against the installed RoundUI source; this observer does not manufacture rows.

An error, local player removal, replacement observer or manual stop marks `Completed=false`; the full duration stop marks only observation-window completion, not gameplay success. No stored event replay or synthetic player data is generated. A new observer replaces only the previous observer of the same side in that Lua context. To stop early in that same context:

```lua
-- Client
if _G.TrelloContinue1300_client then _G.TrelloContinue1300_client.Stop("manual") end
-- Server
if _G.TrelloContinue1300_server then _G.TrelloContinue1300_server.Stop("manual") end
```

All owned connections/timers and observer references are released on stop. Restart for a later scenario if the window expired. `prepare_observers.py` only reproduces these artifact files and their hashes in `prepared.json`.
