# Second-pump Pool Slide replacement — 2026-08-31

Published through Roblox Studio as **version1701** at2026-08-31T20:33:01Z.
Studio confirmed PublishSuccessful and Place published for the existing experience.

## Current behavior

The large Pool Slide humanoid replaces Slidemouth in Level 2. It spawns once
after the **second distinct pump**, regardless of station order. The third pump
still advances the real objective and doors, but does not create another giant.
The previous stable-navigation fix, entity size, animations, attack rules and
minimum60-stud spawn separation remain unchanged.

Slidemouth's Controller, Test Suite, disabled Client, Template and Walk Keyframes
were moved to ServerStorage.Level2RetiredSlidemouth_20260831. Nothing was
permanently deleted; active Adapter hooks and client runtime copies are removed.
The exact retired live Lua sources are under assets/level2/retired-slidemouth.
The prior repository Slidemouth Controller was older; it was not used to overwrite
the newer live version.

## Four spatial groans

The existing library recordings1–4 now play only from an Attachment on the
spawned humanoid's actual RootPart, with the Head bone's offset when available.
The attachment follows the body throughout playback. No detached random monster
emitter or old Slidemouth warning/chase audio lane remains.

The shuffled four-recording bag, non-repeating bag boundary, volume0.68,
pitch0.97–1.02,18–280-stud attenuation and tiled-hall reverb are retained.
First-delay sampling is10–18seconds after a valid replicated body is available;
subsequent delays are24–42seconds. Authored pump/door cues and existing mix-busy
rules can postpone playback. Missing, inactive, removed or streamed-out bodies
are silent; cleanup occurs on source and round lifecycle changes. Common water
drops, drain gurgles, ordinary pipe groans and authored cues remain independent.
All25 library slots and IDs are preserved; Distant Splash remains absent.

## Developer button

Open the Zyntra developer phone with **J**, select **DEV**, press
**PULL TWO PUMPS**. It selects the next two unstarted pumps in station-index
order: one immediately, the second five seconds later. It does not teleport the
player. With fewer than two available pumps it changes nothing.

The actual pump actuator still drives lever/gauge visuals, counts, sound,
drainage and door timing. The proximity/LOS bypass exists only behind a private
server capability and shared developer whitelist. Both GameManager and Objective
Controller recheck authority. Ordinary prompts and Studio DebugActivatePump retain
their original proximity and LOS checks.

One sequence is allowed per live objective session. Repeated clicks cannot
duplicate it. Death, character replacement, leaving, round/level/generation/world
changes, Stop or permission loss cancel the delayed pull. If another player
pulls the reserved second pump first, the sequence does not substitute a third.

## Verification

**126/126 native Luau regressions passed against final Edit sources:**

| Fixture | Passed |
|---|---:|
| Humanoid controller |41/41|
| Stable navigator (unchanged) |43/43|
| Entity-bound audio |15/15|
| Privileged pump sequence |27/27|

Table-only fixtures execute production logic through controlled service/geometry
seams. The dev fixture uses the real public method and unchanged actuator with a
minimal session initializer; it does not re-test unrelated exit construction.

Live single-client Studio checks, with the real GameManager enabled:

- Requested/resolved seed101. Actual client DevCheatCommand → DevControl →
  server Objective actuator: counts0→1→2,5.0007615seconds between pulls. No giant
  at count1; one spawned at count2,81.49studs from the player.
- Ordinary remote-distance DebugActivatePump was rejected before the dev action.
- Genuine third-pump interaction: count3, same humanoid instance, SpawnCount1,
  zero Slidemouth models.
- The actual phone button was clicked through Studio input at count2; server
  returned NEED_TWO_AVAILABLE_PUMPS and did not activate anything extra.
- No pre-spawn monster voices. The live shuffled order was3,4,2,1,then4.
  All four actual Roblox audio assets loaded and played under the humanoid.
  First four starts were23.93,58.27,99.17,132.55seconds into the monitor:
  intervals34.33,40.90,33.38seconds.
- During a real short chase the body moved11.47studs; the playing attachment's
  root-relative drift stayed below0.000002studs. Deactivating the model left
  zero entity voice emitters.
- Fresh requested seed202 resolved to2199511. An overlapping second request
  returned SEQUENCE_BUSY. Ending the round two seconds after the first pull
  cancelled the delayed pull; after6.2seconds, count remained1, busy was false,
  and both giant and Slidemouth counts were zero.
- Final Edit preflight: nine production sources matched byte-for-byte and
  compiled; no temporary test objects/generated world remained; EntityPaused
  false; no active Slidemouth scripts; five retired objects retained.
- No new runtime errors in test console. Existing unconfigured lobby-music and
  terrain-recovery messages remained. Studio capture returned the preexisting
  blank/magenta rendering issue; UI behavior and audio/motion were instrumented,
  not claimed as a successful screenshot-based visual pass.

Full evidence: second-pump-test-results.json. This was not multiplayer/device
load testing. No Git commit/push or active-server restart was performed.

## Source preservation and publication

Nine production scripts were synced narrowly. Objective, GameManager and
ZyntraStore were newer in Studio; their current live sources were preserved
before editing, including existing completion/exit/UI fixes. Their larger Git
diffs must not be mistaken for changes all authored in this request.

Original scripts: ServerStorage.PoolSlideSecondPumpBackup_20260831.
Per-file hashes and the verified public version are recorded in
studio-sync-manifest.json under lastPoolSlideSecondPumpMirror and lastPublished.
