# Card #73 — spectator audio / UI parity (audio + UI half)

Repo-only. Nothing pushed to Studio, nothing committed, manifest untouched.

## Contract used

`SpectateController.LocalScript.lua` (NOT edited) publishes two client-local
attributes on the LocalPlayer while a dead or escaped player spectates:
`Spectating = true` and `SpectateTargetUserId = <UserId>`, and parks the
Scriptable camera — which *is* the audio listener — on the watched player's
head. Every change below resolves the subject with
`Players:GetPlayerByUserId(id)` → `.Character`, requires a living Humanoid and
a HumanoidRootPart, and otherwise falls back to the pre-existing behaviour.

**Spectating is checked BEFORE your own body, not as a dead-player fallback.**
An *escaped* player is alive and still spectating; "use my own body unless it is
dead" would have left every escapee listening to their own parked body in the
safe room for the rest of the round.

## Files changed

| File (all under `StarterPlayer/StarterPlayerScripts/`) | Change |
|---|---|
| `SoundController.LocalScript.lua` | New `audioSubject()` → `(humanoid, root, character, isSpectated)`; replaces the old `aliveParts()`. Drives the custom footstep loop, the Level 2 wade audio, the death-scream gate; new `bindSpectateTarget()` mutes the watched body's default Roblox `Running` loop and mirrors its flashlight click. |
| `Level 2 Sound Controller.LocalScript.lua` | `rootPart()` — the single listener funnel for random ambience placement, the monster groan and the pressure-door cue — resolves the spectate subject first. |
| `Level 3 Sound Controller.LocalScript.lua` | New `listenerRoot()`; the four `player.Character…HumanoidRootPart` reads (blackout scream emitter pick, PA room-song speaker ranking, reader beep, fluorescent fixture ranking) now go through it. |
| `Level 2 Objective UI.LocalScript.lua` | New `bearingRoot()`; `exitBearingText()` measures the flume bearing from the subject. |
| `Level 3 Reader Client.LocalScript.lua` | New `readerSubject(): Player`; the needle/signal root and the `Level3_Hiding` gate read the watched player. `Spectating` / `SpectateTargetUserId` added to `READER_STATE_ATTRIBUTES` so a target switch is immediate instead of waiting up to 0.10 s. |
| `PuzzleUI.LocalScript.lua` | New `detectorRoot()`; the exit-energy detector compass and the signal/distance readout measure from the subject. |
| `ProtectionHUD.LocalScript.lua` | **Unchanged** — see "deliberately not mirrored". |
| `tools/tests/test_spectate_parity.py` | New offline suite (17 checks). |

## Now mirrored to the spectator

Audio:

1. **Custom footstep loop** (the card's named example) — walk/run selection and
   volume keyed to the subject's `AssemblyLinearVelocity` and `Humanoid.WalkSpeed`,
   exactly the existing formula. `WalkSpeed` replicates from the owning client, so
   crouch (`ws > 10` gate) still correctly means silent steps.
2. **The watched body's default Roblox `Running` loop is muted locally**
   (`HumanoidRootPart.Running.Volume = 0`, recursive lookup, previous volume
   restored on target change / stand-down). This is the wrong sound the card
   reports: `RbxCharacterSounds` runs that loop on this client for *every*
   character, so with the camera on their head it was the only footstep audio a
   spectator got.
3. **Level 2 knee-deep wade audio** — stride detection, water raycast, wet/dry
   classification and volume scale all run on the subject root/character.
4. **Flashlight click** — hooked to the subject character's replicated
   `FlashlightOn` BoolValue, unhooked and rebound on every target change.
5. **Death scream** ("only the living hear it") — a spectator watching a living
   player now hears it, positional at the kill spot.
6. **Level 2**: random ambience placement, the monster groan, the pressure-door
   cue (all distance-picked from `rootPart()`).
7. **Level 3**: nearest-PA-speaker room-song ranking, nearest-fluorescent-fixture
   hum, blackout-scream emitter selection, reader beep cadence/facing.

Already parity before this card, verified, no change needed: the Level 1
fluorescent hum pool (falls back to the camera position), the Entity growl /
footsteps / idle & distant screams / chase loop / spot scream (positional at the
Entity, gated on `InRound` + `Escaped`, never on health).

UI:

8. **Level 2 objective panel exit bearing** (`FLUME 132M AHEAD-R - CLIMB`).
9. **Level 3 reader** needle, signal bars, distance — and the panel now blacks
   out while the **watched** player is hiding under a table
   (`Level3_Hiding` is server-set on the Player in
   `ServerScriptService/Level 3 Systems/Level 3 Hiding Controller.ModuleScript.lua`
   lines 150/187/280/286/296/355, so it replicates and can be read for anyone).
10. **Level 1 PuzzleUI** exit-energy detector compass arrow and signal meter.

## Deliberately NOT mirrored

- **Winded / adrenaline breathing** — impossible as the data stands.
  `Stamina` is written by `NoiseReporter.LocalScript.lua:733,768` on the
  **LocalPlayer**, i.e. client-set, so it never replicates and there is nothing
  to read for another player. Same for `PostChaseBreath`. Faking it from
  observable state would be inventing a number. Breathing stays own-only and the
  code says why. *To fix properly the server would have to publish stamina as a
  player attribute.*
- **Jumpscare "capture" scream** — fired only to the victim on the Jumpscare
  remote, left alone as instructed.
- **`ProtectionHUD` (untouched).** `PlayerProtectionActive` /
  `PlayerProtectionExpiresAt` do replicate
  (`ServerScriptService/PlayerProtection.ModuleScript.lua:30,31,123,124`), but
  the HUD's `contextAvailable()` is one predicate driving three things at once:
  `gui.Enabled` / `button.Visible`, `button.Active`, and `canPress()` — and it
  explicitly excludes `Spectating`. Showing the watched player's timer means
  splitting visible from pressable, sourcing `state.Charges` (a local
  `ProtectionClient` value that would be the spectator's own, i.e. wrong), and
  keeping Q/D-pad-down inert while spectating, plus the touch control-slot
  registration and its `assert`. That is comfortably past the ~20 line budget,
  and it is an input control rather than a readout — a live-looking "SHIELD x3
  [Q]" button that does nothing is worse than no button. **Skipped; your call
  whether it comes back as a read-only label.**
- **Level 2 / Level 3 `Escaped` gates were left as they are.** An escaped
  spectator still gets no Level 2 random ambience (`randomActive()`) and no
  Level 3 mix (`isActive()`), exactly as today. Dead spectators get everything.

## ESP — nothing to do, by construction

Dev ESP cannot reach a spectator and no code was added to stop it:

- `DevCheats.LocalScript.lua` is a **LocalScript**. `tag()` (lines 92–105)
  creates `Instance.new("Highlight")` named `DevESP` on the developer's own
  client and parents it to a workspace instance — client-created instances do
  not replicate to the server or to other clients.
- The player-ESP block in the current working tree (`DEV_PLAYER_ESP_20260910`,
  lines ~106–230, uncommitted, from another session) builds its `ScreenGui`
  under **that developer's** `player:WaitForChild("PlayerGui")` — per-client by
  definition, and its labels are positioned with the dev's own
  `workspace.CurrentCamera`.
- The toggle state `DevEspEnabled` is set with `player:SetAttribute` from the
  **client**, which likewise does not replicate to other clients.

So a spectator watching a DEV sees the DEV's world without the DEV's ESP. The
only way to break that would be to add mirroring code, which was not added.

## Stand-down

- Target change or `SpectateTargetUserId → nil`: `audioSubject()` returns nil →
  `footTarget = 0` → the loop fades out on the existing `FOOT_FADE` curve (never
  a hard cut); the muted `Running` volume is written back; the flashlight
  connection is `:Disconnect()`ed; bearings/needle/detector fall through to their
  existing "no root" text (`POWERED_HINT`, `SIGNAL // NO TRACE`, `SEARCHING…`).
- A target switch moves the Level 2 wade reference position far enough to trip
  the existing teleport guard, which stops the wade bank and re-seats the cadence.
- A 1 s retry re-runs `bindSpectateTarget()` only while `Spectating` is true and
  the `Running` sound or the `FlashlightOn` flag has not appeared yet (they can
  stream in after the target is published).
- Marked shortcut (`ponytail:` comment in the source): the `Running` mute is a
  one-shot write, not `configureDefaultSteps`' re-assert watcher. If something
  starts writing that volume back up mid-spectate, give it the same
  `GetPropertyChangedSignal("Volume")` guard.

## Verification run

```
LUAU=C:/Users/mikke/AppData/Local/Temp/codex-luau-0.737
$LUAU/luau-compile.exe --binary <each changed file>     -> all OK
export LUAU_BIN="$LUAU/luau.exe"
python tools/tests/test_spectate_parity.py   -> Spectate parity: 17 checks passed
python tools/tests/test_pool_foam_audio.py   -> Pool Foam audio: 24 checks passed
python tools/tests/test_controller_input.py  -> Controller input: 120 checks passed
```

`tools/tests/test_spectate_parity.py` extracts the **real** `audioSubject()`,
the real footstep block out of the main Heartbeat, the real
`bindSpectateTarget()`, and the real audio-slot / tuning constants by string
marker, then drives them against a stubbed DataModel. It asserts: alive → own
root drives the steps; alive-and-escaped-while-spectating → the watched root
does; dead + `SpectateTargetUserId` of a living player → that root drives the
steps, its `Running` sound is muted and its flashlight toggle clicks; the target
dies → subject is nil, loop fades to 0, muted volume handed back; no target, or
a target without `Spectating` → nil and silent.

## What the lead should check in Studio (two players required)

None of this can be proven single-client — everything below needs a real second
player, because the whole feature is about another character's replicated state.

1. **Two players, Level 1.** Kill player A, let them spectate B. B walks, then
   sprints: A must hear the custom walk/run loop change at B's cadence, and must
   **not** hear Roblox's default squeaky loop underneath. Crouch: silent.
2. Switch targets with Q/E mid-stride — the loop should fade, not cut, and B's
   default `Running` volume should come back (inspect `B.HumanoidRootPart.Running.Volume`
   in the Explorer; it is 0 only while B is the target).
3. B toggles their flashlight — A hears the click.
4. A third player C dies away from B: A (watching B) hears the positional death
   scream from C's direction, at B's ears.
5. **Level 2:** A dead spectator should now hear the pump-motor / pressure-door
   cues and the random ambience at the watched player's position, plus the wade
   splashes as B walks through knee-deep water and the dry-tile steps on the
   ledges. Check the objective panel's `FLUME …M …` line matches what B sees.
6. **Level 3:** the reader needle/bars should match B's panel; when B hides under
   a table the spectator's reader should black out with theirs; the PA room song
   and fluorescent hum should follow B's room.
7. **ESP negative check:** have a dev with ESP on be spectated — the spectator
   must see no highlights and no player labels.
8. Re-run the compile probe after pushing (`RoundUI` is untouched, but
   `SoundController` grew).
