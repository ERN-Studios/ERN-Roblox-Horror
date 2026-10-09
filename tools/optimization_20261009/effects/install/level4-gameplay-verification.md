# Level 4 actual gameplay verification route

Historical preparation note: MCP `require(Director)` diagnostics can use a different module cache from the running game's controller. The example below does not establish actual round power/AI state. Use normal gameplay events and replicated state for that evidence. Root's completed scope and the unverified full power/Usher/win route are recorded in the [current report](../../README.md).

The installed Director API below comes from the exact Source/editor proposal verified by root's native source CAS. The gameplay route has not been run by the effects task. The Objective/Generator call relationships were inspected in repository mirrors; root should recheck their current live Sources before using any manual runtime control.

Enter an actual Level 4 round through the public lobby queue. Let the round generator own `Start` and cleanup. Read the actual note and use the four switches in its order. The normal objective path advances to `Reels` and calls `PowerUp` with the callback that activates the Usher. Calling `PowerUp` alone exercises lighting while bypassing that objective/AI transition, so it cannot prove this gameplay route.

Record these observations on the server and each client:

1. At round entry, `PowerState()` is `Off`. Authored zone lights have wanted=false and stay off locally; the separately authored/runtime emergency lights retain their normal behavior.
2. After the correct switches, observe `PoweringUp`, `On`, then `Failing`, with the actual objective progress and Usher behavior. Near wanted=true lights remain enabled; a light farther than its budget threshold from both camera and character may be locally disabled while the server's wanted/Enabled remain true.
3. Traverse the service room, galleries, lobby, and cinema viewpoints from `actual-level-routes.json`. Entry threshold is 320 plus the light's Range; exit adds the 48-stud hysteresis. Camera and character both contribute. Check visible illumination, flashlights, star effects, ReduceFlashing, and transitions without visible popping.
4. During an actual failure/blackout, a locally suppressed light must remain disabled when the character returns; its independent wanted=false attribute carries the same-value blackout. Power recovery restores nearby wanted=true lights. Brightness, Color, and gameplay zone authority stay under the existing controllers.
5. Complete the real reel/projector/breaker or solo-fuse route and finale. End/reset the round through its normal lifecycle. Check restoration of authored disabled lights, cleanup, a second round, and streaming out/back. A two-client pass must compare the same server wanted state with each client's independent local distance result; then test distant spectating and target changes.

Read-only server diagnostics during an already active Level 4 round:

```lua
assert(workspace:GetAttribute("SelectedLevel") == 4)
assert(workspace:GetAttribute("Level4RoundActive") == true)
local systems = game:GetService("ServerScriptService"):FindFirstChild("Level 4 Systems")
local director = require(assert(systems:FindFirstChild("Level 4 Light Director")))
local player = assert(game:GetService("Players"):GetPlayers()[1])
local root = assert(player.Character and player.Character:FindFirstChild("HumanoidRootPart"))
local _, zoneId = director.ZoneAt(root.Position)
return {
    power = director.PowerState(), zones = director.ZoneCount(), zoneId = zoneId,
    zoneOn = zoneId ~= nil and director.IsZoneOn(zoneId),
    litForGameplay = director.IsLit(root.Position),
    darkForGameplay = director.IsDark(root.Position),
}
```

Exported mutating controls are `Start(manifest, generation)`, `Stop()`, `SetEscalation(level)` (clamped 0–3), `PowerUp(origin, onFailing)`, and `Finale(screens)`. `Start` immediately calls `Stop`; `PowerUp` accepts only the `Off` state. There is no exported SetZone/Blackout method. These calls change the real round; any separate manual control pass must preserve its owner/controller lifecycle and be labeled separately from normal gameplay verification.

Measure actual frame/join time, client/server memory, streaming/re-entry, and network behavior separately. The native synthetic contracts and static viewpoint counts do not establish these results.
