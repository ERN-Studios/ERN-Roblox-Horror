# Revised Continue: root's native lookup

Read-only source/artifact lookup, 2026-09-10. No UI input or source/Studio mutation performed. Current disk hashes still match `installation/checkpoint.json`: GameManager `3615b6a3…e5d58`, RoundUI `14fdd1e5…93fe` (includes published camera fix v1858). Rediscover actual windows/Studio state; old window IDs are historical, not current targets.

## Reuse the preserved setup

- **Actual two-client host route:** `../party-continue-prepared/native-two-client-runbook.md`, its opening **Observed root execution** paragraph. The successful installed-Studio route was **Test → Start Test Session → Server and Clients**, then **Test → Add Clients** once per client from the server window. It initially created zero clients. Native client Command Bars were used because the additional windows did not expose separate MCP IDs. Read each LocalPlayer and the server roster; old Player1/−1 and Player2/−2 are examples, not assumed identities.
- The same document's **Enter the real completion path** contains the already used, guarded **server** `PuzzleWon=true` fixture. It requires normal Level 1, two actual alive/InRound players, RoundLoadingState=ready, released roots and no Escaped flags. It enters the real GameManager predicate without claiming a full puzzle playthrough or earned reward. Its preceding client identity query is read-only. No new harness is needed.
- **Do not reuse that document's old acceptance section.** Its wait beyond 16 seconds, WAITING/READY roster and Continue→Back change are superseded. Current requirement preserves **15-second auto-continue** and the original one-choice pending behavior.
- Historical genuine two-client evidence is in `../party-continue-prepared/installation/native-two-client-server.log`, `native-acceptance.md`, and the `native-player1-*` / `native-player2-*` images. This proves the setup worked; its old barrier behavior is not current acceptance.

## Exact current GUI paths

All paths begin at the **selected client's** `Players.LocalPlayer.PlayerGui`.

| Purpose | Relative path |
|---|---|
| Host modal | `RoundGui.QueueHostShade.QueueHostPanel` |
| Size minus / read count / plus | above + `.DecreasePlayers` / `.PlayerCount` / `.IncreasePlayers` |
| Privacy / create / close | above + `.PrivacyToggle` / `.CreateParty` / `.CloseQueue` |
| Result screen | `RoundGui.RoundEnding` |
| Continue | `RoundGui.RoundEnding.ContinueRun` |
| Back to Lobby | `RoundGui.RoundEnding.ReturnToLobby` |
| Countdown hint | `RoundGui.RoundEnding.EndingHint` |
| Original composition | `RoundGui.RoundEnding.EndingTitle`, `.SignalLine`, `.EndingStats` |
| Accepted choice strip | `RoundGui.RoundEnding.PartyChoices` |
| Rendered rows | strip + `.PartyChoice1`, `.PartyChoice2`, etc. (created only as needed) |

Walk into Level 1's normal host zone; four minus clicks change default6→2. Keep PUBLIC for the second actual client to join the same station normally. There is no `JoinParty` button in this RoundUI. CreateParty's actual Activated handler sends `ReplicatedStorage.Remotes.ConfigureQueue:FireServer(station, size, privacy)`. CloseQueue sends `(station, 0, "cancel")`. Native acceptance uses the actual buttons, not direct remote calls.

ContinueRun has attribute `CompletionAction="continuenow"`; ReturnToLobby has `CompletionAction="returntolobby"`. A click immediately locks **both** original actions locally and sends the action plus current server serial through RoundStatus. The chosen caption becomes CONTINUING…/RETURNING…. A choice snapshot must not unlock either button or resolve local pending state. Back after Continue is intentionally unavailable under this restored original flow.

## Authoritative events and observable state

Remote: **`ReplicatedStorage.Remotes.RoundStatus`**.

| Direction / event | Actual payload and meaning |
|---|---|
| Server → `win` | `(elapsed, escapedCount, participantCount, deadline, nextLevel, serial)`; deadline is server time+15. Client starts the unchanged countdown. |
| Server → `postwinchoices` | `{Serial, Revision, Members={{UserId, Name, Choice},…}}`; actual frozen server roster, monotonically increasing revision. No Closed field in this revised packet. |
| Client → `continuenow` / `returntolobby` | `(action, serial)`; server validates current session/deadline/level/roster/InRound and an undecided player. |
| Server → `returnpending` | `(serial)`; return acknowledgment. There is **no `continuepending` event** here. |
| Server → `continuefailed` / `returnfailed` | `(serial)`; while the old deadline remains, resets local pending and re-arms the actual actions. |

Choices are `deciding`, `continuing`, `returning`. The strip renders **only explicit accepted continuing/returning**, as username followed by CONTINUE/LOBBY. Before anyone clicks it is hidden; unanswered automatic continuation must not invent a CONTINUE row. A disconnected undecided player must not gain a fake click. Serial/revision are private client/server state communicated by the remote, **not player/workspace attributes**. GameManager/roster is a running Script; a fresh module require cannot inspect its private session.

Read server workspace `SelectedLevel`, `RoundActive`, `RoundLoadingState`, `PostWinIntermissionActive`; read each actual player's `InRound`, `Escaped`, character/Health and root.Anchored. `RoundEntryControlsReady` is set by the client NoiseReporter: read it **on that client**, not as a server-authoritative replicated flag. PostWinIntermissionActive=true and RoundActive=false identify the ordinary result window. For settlement, save the real server Output line:

`[GameManager] result window N settled: C continuing, D departed, R returning, G gone -> cohort T`

## Small current acceptance sequence

1. In the first real two-player result, leave both unanswered. The strip stays hidden and the original countdown reaches its approximately15-second server deadline; the same two players advance through normal local Level 2 loading. Record actual identities, countdown/elapsed interval, settlement cohort and both ready arrivals. A persistent wait beyond the deadline would be a regression now.
2. In a second normal two-player result, click A Continue while B is still undecided. B must see A's actual username/CONTINUE; B has no fabricated choice row. Capture before B clicks because all-decided settlement may happen immediately. Click B Back to Lobby and capture LOBBY if it remains visible before departure; no artificial minimum display time is required. Studio intentionally returns the whole local group to lobby for mixed choices; its existing fallback cannot verify live reserved-server splitting. Use a separate Continue/Continue result only if needed to resolve a concrete missing observation.
3. Reuse the separate **six-row display** package below for compact layout/scroll/reset. Never send synthetic result events during a real intermission.

## Existing native probes and display scripts

- **Read-only actual client UI snapshot:** `native-six-rows/client-readonly.luau`. It returns JSON containing actual LocalPlayer, native viewport/safe-inset overrides, original geometry/TextFits/actions, strip geometry/scroll and each row's text/visibility/reachability. It can inspect real rows too; its generic Scope string warns that synthetic rows are not multiplayer identity evidence. It creates no instances/listeners and changes no UI. Run on each actual client after A's click and after reset; an empty row set before the first click is expected.
- **Synthetic six-row sender:** `native-six-rows/server-display.luau`, instructions in `native-six-rows/RUNBOOK.md`. It is an intentional presentation mutation through existing remote events, **not read-only**. Only in a quiet Play lobby; set the actual TARGET_USER_ID when multiple clients exist. Actions `begin`, `rows`, `stale`, `clear`, `restore`, `new`, `old`, `reset`; serials −61001/−61002 cannot match real positive GameManager sessions. Six TEST names remain display-only. The companion client probe measures real text and scroll. Existing review is `native-six-rows/independent-review.md`.

Finish with End Session and verify actual Edit/source parity before the root's separate mouse publication. No old full GameManager/RoundUI snapshot should be installed from the superseded folder.

## Capture through Roblox logs, without copying Output

Historical extraction is confirmed: the saved `PARTY_NATIVE_CONTROLLED_WIN` lines occur in `%LOCALAPPDATA%\Roblox\logs\0.738.0.7381393_20260910T080907Z_Studio_AC301_last.log`.

At the current 2026-09-10 11:05Z read, the actual local test server log is `0.738.0.7381393_20260910T093231Z_Studio_86810_last.log` (StartServer launch; Player1 connection11:03:29Z and Player2 connection11:04:09Z). The new client logs are `0.738.0.7381393_20260910T110324Z_Studio_1D4AD_last.log` and `0.738.0.7381393_20260910T110406Z_Studio_7E17E_last.log`. Confirm client identities from the readback, not their order alone. These paths are under `C:\Users\mikke\AppData\Local\Roblox\logs` and change if the session restarts.

This short **server Command Bar read** prints one JSON record into the normal log; it neither completes a round nor creates a listener/helper. Its role assertion also catches accidental execution in a client:

```lua
assert(game:GetService("RunService"):IsServer(), "Use the actual test SERVER")
local players = {}
for _, p in ipairs(game:GetService("Players"):GetPlayers()) do
    local c = p.Character
    local h = c and c:FindFirstChildOfClass("Humanoid")
    local r = c and c:FindFirstChild("HumanoidRootPart")
    players[#players+1] = {Name=p.Name, UserId=p.UserId, Character=c and c.Name,
        InRound=p:GetAttribute("InRound"), Escaped=p:GetAttribute("Escaped"),
        Health=h and h.Health, Anchored=r and r.Anchored,
        Position=r and {r.Position.X,r.Position.Y,r.Position.Z}}
end
print("PARTY_AUTO_SERVER " .. game:GetService("HttpService"):JSONEncode({
    At=workspace:GetServerTimeNow(), Players=players,
    SelectedLevel=workspace:GetAttribute("SelectedLevel"),
    RoundActive=workspace:GetAttribute("RoundActive"),
    RoundLoadingState=workspace:GetAttribute("RoundLoadingState"),
    PostWinIntermissionActive=workspace:GetAttribute("PostWinIntermissionActive"),
    ServerLobbyPresent=workspace:FindFirstChild("ServerLobby")~=nil,
    PuzzleWon=workspace:GetAttribute("PuzzleWon")}))
```

For the existing client-readonly probe, wrap its complete unchanged command body in `local function snapshot() ... end` and finish with `print("PARTY_AUTO_CLIENT " .. snapshot())`. It already returns a JSON string and verifies the Play client/LocalPlayer. This command-only wrapper avoids changing the preserved probe file. Inspect or extract the uniquely prefixed **CreatorOutput** lines with `rg -n -F 'PARTY_AUTO_' <exact log path>`; take the JSON suffix after the marker and save it alongside native screenshots. Prefixes distinguish these bounded observations from unrelated logs. The server settlement line is already logged automatically. Do not infer that a blank server viewport means players lack a world: use the actual client view and these character/readiness facts.
