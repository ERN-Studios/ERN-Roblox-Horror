# Small native L1 capture acceptance

Prepared only; no Studio or runtime changes made by this task. This uses one real physical client, the existing isolated memory fixture and the normally spawned L1 Entity. It does not certify multiplayer. Root's separate purchase/expiry/refund work is reused rather than repeated here.

## Setup and run

1. Keep the existing memory fixture and all installed Protection consumers at their current normal identities. The existing two isolated memory test charges are valid for this capture test; do not add or grant further charges. Root's already completed five-token purchase evidence covers acquisition separately, so no repeat purchase is needed here. Inspect uses the raw profile path `Profile.Protection.Charges`; the flattened public response uses a different field. There must be no queued delay/failure fault for this capture attempt.
2. Join Level 1 using the normal lobby queue. Wait for the real ready state and living in-round character. Close Shop, briefing and Roblox menus. The HUD must offer use. Locate the actual `workspace.Entity` through read-only coordinates. Root may place only the actual test player on verified existing collision floor near the entity as a bounded setup, then release ordinary character movement/physics to produce contact. Record this setup explicitly; it is not navigation acceptance. Do not relocate the entity, alter the maze, fire synthetic touches or pause its AI. Teleporting into overlap alone is not proof that a real touch callback ran.
3. Root installs `ObserveCapture.Server.Script.lua` as one ordinary **Play-only server Script**. It creates only `ServerStorage.ProtectionCaptureObservation`, a server-only BindableFunction. No automatic activation or world mutation is performed. Arm while unprotected and before capture, when the real entity is close enough to reach the player inside the next 20 seconds:

```lua
local probe = game.ServerStorage.ProtectionCaptureObservation
return game:GetService("HttpService"):JSONEncode(probe:Invoke("Arm", 20))
```

4. Let actual physical contact start the capture. Release movement briefly before contact if practical so the preceding position samples are a useful restoration reference. Use **the actual HUD key Q or its use button** while alive. For a pull-stage attempt, press around 0.8–1.0 seconds after visible capture begins. For a separate ground-pin attempt, use the second existing test charge and press around 2.3 seconds after capture, once the player is visibly lying down. These timings come from the installed source: pull starts at 0.72 seconds, the ground-pin tween starts around 1.48 seconds, and lethal impact is scheduled at 124/30 ≈4.133 seconds. Client timing must be judged by the real scene, not a guessed script delay.
5. After cancellation, move away with actual controls and turn the camera. Continue the 20-second observation beyond both the old capture's scheduled lethal time and the five-second effect deadline. Do not remain deliberately touching the entity after expiry: a **new** legitimate capture is allowed. The source's same-player debounce lasts six seconds from capture start; distinguish a new capture ID from resumption of the cancelled ID.

The observer returns immediately from Arm so it does not block root's UI actions. It samples about every 0.05 seconds and records real `Touched`/`CancelKill` events, capture IDs, the actual Kill animation `94135265462008`, private protection state through the existing fixture callback, charge/token counts, HP, root orientation/position/anchoring and Humanoid controls. It never calls Activate, Clear, purchase remotes, grants, animation controls, damage, movement or AI toggles.

## Read evidence and decide

```lua
local probe = game.ServerStorage.ProtectionCaptureObservation
return game:GetService("HttpService"):JSONEncode(probe:Invoke("Status"))
```

Once `Busy=false`, fetch each `Chunk` index from 1 through the returned count, **one tool result per chunk**, concatenate strings in index order outside Studio and JSON-decode once. Each chunk is at most 40,000 characters; do not return the entire report through a truncating bridge.

```lua
return game.ServerStorage.ProtectionCaptureObservation:Invoke("Chunk", 1)
```

Required observed chain: real entity touch → active capture with ID and Kill track → the HUD consumes one charge and private Active becomes true → a matching actual CancelKill event and cleared capture state → player remains alive, root unanchored/upright, movement values restored, Kill track stops after its normal 0.12-second fade → old lethal time passes without old-ID damage. Then actual camera rotation/walking works and private protection expires without a restarted old capture. Inspect at least 0.25 seconds after cancellation before judging residual animation weight.

`DurationCompleted` means only that recording covered the requested time; it is **not an automatic PASS**. No captured touch, no active capture before activation, no one-charge consumption, a dead player, missing private activation, or interruption yields insufficient/failing evidence as applicable. Existing memory seed charges are test inventory, not a new real purchase. Before/after sampled positions do not prove an exact hidden pre-grab CFrame: visually verify standing on the real collision floor, and compare the stable preceding samples without pretending sub-frame precision. The callback/track observations alone also do not certify the camera; use actual client input.

A minimal **read-only client snapshot** after cancellation can support the UI observation:

```lua
local p = game.Players.LocalPlayer
local h = p.Character and p.Character:FindFirstChildOfClass("Humanoid")
local camera = workspace.CurrentCamera
local gui = p.PlayerGui:FindFirstChild("ProtectionHUD")
local use = gui and gui:FindFirstChild("ProtectionUse")
return game:GetService("HttpService"):JSONEncode({
    CameraType=camera.CameraType.Name, CameraSubjectIsCurrentHumanoid=camera.CameraSubject==h,
    HudEnabled=gui and gui.Enabled, UseVisible=use and use.Visible, UseActive=use and use.Active,
})
```

The helper disconnects its own listeners when recording ends. For normal cleanup, return through the game's usual round/lobby flow and inspect the existing fixture's private Active=false plus restored client controls. Stop Play when finished; do not publish the helper or memory fixture. If root removes the helper Script, its destruction cleans up only its owned BindableFunction/listeners. No world objects need moving or deleting.

The event list is capped at 160 entries. If it fills, absence of a later CancelKill event is not evidence that cancellation failed or never happened; inspect sampled state and retained positive events, and repeat with an adequate observation if a required event was lost. The observer's final reviewed SHA is `f09cb0e940c359b01902fa8597caf42e1bd98b63d9dbe4851368af7c9b98b328`; independent diagnostic-artifact score **9/10**, whole compile 9 KB. Native results remain root-owned.

## Optional L2 follow-up boundary

Use the existing normal encounter flow and actual pumps if root also wants Foam coverage. **Two pumps/Pressure or three/Finale are necessary**: Dormant and one-pump Foreshadow explicitly disallow attacks, so surviving those phases proves nothing about death protection. Foam kills synchronously; it has no L1-style asynchronous capture to cancel. Activate through the real HUD before lethal contact, then physically approach a real chase-latched Foam entity while private Active is true. Current kill reach is 5.5 studs measured in 3D from player root to navigator position. Real line of sight, eligible attack phase, chase latch and expired grace must also be established; proximity alone is insufficient. After expiry, move safely away or accept a separate normal unprotected contact control in the isolated fixture. This L1 observer does not implement or certify that L2 case.
